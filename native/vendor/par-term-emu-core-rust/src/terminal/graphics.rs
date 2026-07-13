//! Graphics management
//!
//! Handles graphics storage, retrieval, and position adjustments during scrolling.
//! Supports Sixel, iTerm2, and Kitty graphics protocols via unified GraphicsStore.

use crate::debug;
use crate::graphics::kitty::{KittyAction, KittyGraphicResult, KittyParser};
use crate::graphics::TerminalGraphic;
use crate::terminal::Terminal;
use std::time::Instant;

const GRAPHICS_SEQUENCE_OVERHEAD_BYTES: usize = 4096;
const TMUX_PASSTHROUGH_HEADER: &[u8] = b"tmux;";

fn unsupported_iterm_log_message(command: &str) -> String {
    format!(
        "Unsupported OSC 1337 command: command_bytes={}",
        command.len()
    )
}

/// Incremental decoder state for tmux/screen DCS passthrough wrappers.
///
/// No wrapper payload is retained here: decoded bytes are emitted to the OSC
/// ingress gate on every `process` call.  The largest retained state is the
/// fixed five-byte tmux header prefix.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) enum GraphicsPassthroughState {
    #[default]
    Ground,
    Escape,
    DcsStart,
    TmuxHeader(usize),
    TmuxPayload,
    TmuxPayloadEscape,
    ScreenPayload,
    ScreenPayloadEscape,
}

impl GraphicsPassthroughState {
    pub(crate) const fn is_ground(self) -> bool {
        matches!(self, Self::Ground)
    }
}

impl Terminal {
    /// Incrementally unwrap tmux/screen DCS passthrough wrappers.
    ///
    /// Decoded bytes are returned on each call so OSC policy and size limits
    /// run before an outer wrapper terminates.  Only fixed-size decoder state
    /// is retained across chunks.
    pub(crate) fn handle_graphics_passthrough_sequences(&mut self, data: &[u8]) -> Vec<u8> {
        let mut output = Vec::with_capacity(data.len().saturating_add(7));

        for &input_byte in data {
            let mut byte = Some(input_byte);
            while let Some(current) = byte.take() {
                match self.graphics_passthrough_state {
                    GraphicsPassthroughState::Ground => {
                        if current == b'\x1b' {
                            self.graphics_passthrough_state = GraphicsPassthroughState::Escape;
                        } else {
                            output.push(current);
                        }
                    }
                    GraphicsPassthroughState::Escape => {
                        if current == b'P' {
                            self.graphics_passthrough_state = GraphicsPassthroughState::DcsStart;
                        } else {
                            output.push(b'\x1b');
                            self.graphics_passthrough_state = GraphicsPassthroughState::Ground;
                            byte = Some(current);
                        }
                    }
                    GraphicsPassthroughState::DcsStart => {
                        if current == b'\x1b' {
                            // Screen's wrapper payload begins with this ESC.
                            self.graphics_passthrough_state =
                                GraphicsPassthroughState::ScreenPayloadEscape;
                        } else if current == TMUX_PASSTHROUGH_HEADER[0] {
                            self.graphics_passthrough_state =
                                GraphicsPassthroughState::TmuxHeader(1);
                        } else {
                            // Not a passthrough wrapper; preserve the DCS bytes.
                            output.extend_from_slice(b"\x1bP");
                            self.graphics_passthrough_state = GraphicsPassthroughState::Ground;
                            byte = Some(current);
                        }
                    }
                    GraphicsPassthroughState::TmuxHeader(matched) => {
                        if current == TMUX_PASSTHROUGH_HEADER[matched] {
                            let matched = matched + 1;
                            self.graphics_passthrough_state =
                                if matched == TMUX_PASSTHROUGH_HEADER.len() {
                                    GraphicsPassthroughState::TmuxPayload
                                } else {
                                    GraphicsPassthroughState::TmuxHeader(matched)
                                };
                        } else {
                            // The fixed header candidate was an ordinary DCS.
                            output.extend_from_slice(b"\x1bP");
                            output.extend_from_slice(&TMUX_PASSTHROUGH_HEADER[..matched]);
                            self.graphics_passthrough_state = GraphicsPassthroughState::Ground;
                            byte = Some(current);
                        }
                    }
                    GraphicsPassthroughState::TmuxPayload => {
                        if current == b'\x1b' {
                            self.graphics_passthrough_state =
                                GraphicsPassthroughState::TmuxPayloadEscape;
                        } else {
                            output.push(current);
                        }
                    }
                    GraphicsPassthroughState::TmuxPayloadEscape => match current {
                        b'\x1b' => {
                            // tmux doubles every ESC in the inner stream.
                            output.push(b'\x1b');
                            self.graphics_passthrough_state = GraphicsPassthroughState::TmuxPayload;
                        }
                        b'\\' => {
                            // A non-doubled ST terminates the outer wrapper.
                            self.graphics_passthrough_state = GraphicsPassthroughState::Ground;
                        }
                        _ => {
                            // Preserve malformed/non-doubled inner ESC bytes.
                            output.push(b'\x1b');
                            self.graphics_passthrough_state = GraphicsPassthroughState::TmuxPayload;
                            byte = Some(current);
                        }
                    },
                    GraphicsPassthroughState::ScreenPayload => {
                        if current == b'\x1b' {
                            self.graphics_passthrough_state =
                                GraphicsPassthroughState::ScreenPayloadEscape;
                        } else {
                            output.push(current);
                        }
                    }
                    GraphicsPassthroughState::ScreenPayloadEscape => match current {
                        b'\\' => {
                            self.graphics_passthrough_state = GraphicsPassthroughState::Ground;
                        }
                        b'\x1b' => {
                            // The first ESC is payload; the second may start ST.
                            output.push(b'\x1b');
                        }
                        _ => {
                            output.push(b'\x1b');
                            self.graphics_passthrough_state =
                                GraphicsPassthroughState::ScreenPayload;
                            byte = Some(current);
                        }
                    },
                }
            }
        }

        output
    }

    /// Strip Kitty APC graphics sequences from incoming bytes and process them.
    pub(crate) fn handle_kitty_apc_sequences(&mut self, data: &[u8]) -> Vec<u8> {
        let mut input = if self.kitty_apc_buffer.is_empty() {
            data.to_vec()
        } else {
            let mut buffered = std::mem::take(&mut self.kitty_apc_buffer);
            buffered.extend_from_slice(data);
            buffered
        };

        let mut output = Vec::with_capacity(input.len());
        let mut index = 0usize;
        while index < input.len() {
            let Some(relative_start) = find_bytes(&input[index..], b"\x1b_") else {
                output.extend_from_slice(&input[index..]);
                break;
            };
            let start = index + relative_start;
            self.advance_parser_before_kitty_apc(&input[index..start]);

            let payload_start = start + 2;
            let Some((terminator_start, terminator_end)) =
                find_apc_terminator(&input, payload_start)
            else {
                if !self.retain_incomplete_kitty_apc(&input[start..]) {
                    self.push_kitty_response(
                        None,
                        None,
                        "EINVAL: graphics sequence exceeds configured byte limit",
                    );
                }
                break;
            };

            let payload = &input[payload_start..terminator_start];
            if let Some(kitty_payload) = payload.strip_prefix(b"G") {
                self.handle_kitty_apc_payload(kitty_payload);
            }
            index = terminator_end;
        }

        input.clear();
        output
    }

    fn advance_parser_before_kitty_apc(&mut self, data: &[u8]) {
        if data.is_empty() {
            return;
        }
        let mut parser = std::mem::replace(&mut self.parser, vte::Parser::new());
        let parser_started_at = Instant::now();
        parser.advance(self, data);
        self.record_parser_advance_debug_micros(parser_started_at.elapsed().as_micros() as u64);
        self.observe_plain_text_parser_state(data);
        let _ = std::mem::replace(&mut self.parser, parser);
    }

    fn handle_kitty_apc_payload(&mut self, payload: &[u8]) {
        if self.graphics_sequence_exceeds_limit(payload.len()) {
            self.push_kitty_response(
                None,
                None,
                "EINVAL: graphics sequence exceeds configured byte limit",
            );
            return;
        }
        let Ok(payload) = std::str::from_utf8(payload) else {
            self.push_kitty_response(None, None, "EINVAL: invalid UTF-8");
            return;
        };
        let mut parser = if self.kitty_parser.is_some() && kitty_payload_is_delete_command(payload)
        {
            self.kitty_parser = None;
            KittyParser::new()
        } else {
            self.kitty_parser.take().unwrap_or_default()
        };
        parser.set_max_data_bytes(self.graphics_store.max_decoded_image_bytes());
        let more_chunks = match parser.parse_chunk(payload) {
            Ok(more_chunks) => more_chunks,
            Err(error) => {
                let image_id = parser.image_id;
                let image_number = parser.image_number;
                let should_send_error = parser.should_send_error_response();
                self.kitty_parser = None;
                if should_send_error {
                    self.push_kitty_response(image_id, image_number, &format!("EINVAL: {error}"));
                }
                return;
            }
        };
        if parser.placement_position.is_none()
            && matches!(
                parser.action,
                KittyAction::TransmitDisplay | KittyAction::Put
            )
        {
            parser.placement_position = Some((self.cursor.col, self.cursor.row));
        }
        if more_chunks {
            self.kitty_parser = Some(parser);
            return;
        }

        let image_id = parser.image_id;
        let image_number = parser.image_number;
        let prebuild_response_image_id = image_id.or_else(|| {
            image_number.and_then(|number| self.graphics_store.kitty_image_id_for_number(number))
        });
        let action = parser.action;
        let should_send_ok = parser.should_send_success_response();
        let should_send_error = parser.should_send_error_response();
        let position = parser
            .placement_position
            .unwrap_or((self.cursor.col, self.cursor.row));
        match parser.build_graphic_for_screen(
            position,
            &mut self.graphics_store,
            self.alt_screen_active,
        ) {
            Ok(KittyGraphicResult::Graphic(mut graphic)) => {
                let response_image_id = graphic.kitty_image_id.or(image_id);
                let should_move_cursor = parser.should_move_cursor_after_display();
                graphic.set_alternate_screen(self.alt_screen_active);
                let (cell_w, cell_h) = self.cell_dimensions;
                graphic.set_cell_dimensions(cell_w, cell_h);
                let (cols, rows) = self.size();
                let (span_cols, span_rows) = graphic.resolved_cell_span(Some(cols), Some(rows));
                graphic.set_display_cell_span(span_cols, span_rows);
                let mut should_add_graphic = true;
                if should_move_cursor {
                    should_add_graphic = self.move_cursor_after_kitty_placement(
                        &mut graphic,
                        position,
                        span_cols,
                        span_rows,
                    );
                }
                let row = graphic.position.1;
                if should_add_graphic && self.graphics_store.add_graphic(graphic) {
                    self.terminal_events
                        .push(crate::terminal::TerminalEvent::GraphicsAdded(row));
                }
                if should_send_ok {
                    self.push_kitty_response(response_image_id, image_number, "OK");
                }
            }
            Ok(KittyGraphicResult::VirtualPlacement {
                image_id: resolved_image_id,
                position,
                ..
            }) => {
                let (cell_w, cell_h) = self.cell_dimensions;
                let (cols, rows) = self.size();
                self.graphics_store
                    .refresh_cell_dimensions(cell_w, cell_h, cols, rows);
                self.terminal_events
                    .push(crate::terminal::TerminalEvent::GraphicsAdded(position.1));
                if should_send_ok {
                    self.push_kitty_response(Some(resolved_image_id), image_number, "OK");
                }
            }
            Ok(KittyGraphicResult::None) => {
                let response_image_id = prebuild_response_image_id.or_else(|| {
                    image_number
                        .and_then(|number| self.graphics_store.kitty_image_id_for_number(number))
                });
                if should_send_ok && (action == KittyAction::Query || response_image_id.is_some()) {
                    self.push_kitty_response(response_image_id, image_number, "OK");
                }
            }
            Err(error) => {
                let code = if error.to_string().contains("Image not found") {
                    "ENOENT"
                } else {
                    "EINVAL"
                };
                if should_send_error {
                    let response_image_id = prebuild_response_image_id.or_else(|| {
                        image_number.and_then(|number| {
                            self.graphics_store.kitty_image_id_for_number(number)
                        })
                    });
                    self.push_kitty_response(
                        response_image_id,
                        image_number,
                        &format!("{code}: {error}"),
                    );
                }
            }
        }
        self.kitty_parser = None;
    }

    fn move_cursor_after_kitty_placement(
        &mut self,
        graphic: &mut TerminalGraphic,
        position: (usize, usize),
        span_cols: usize,
        span_rows: usize,
    ) -> bool {
        let (cols, rows) = self.size();
        if cols == 0 || rows == 0 {
            return true;
        }

        let col = position
            .0
            .saturating_add(span_cols)
            .min(cols.saturating_sub(1));
        self.advance_cursor_after_graphic_block_at(graphic, span_rows, position, col)
    }

    pub(crate) fn advance_cursor_after_graphic_block(
        &mut self,
        graphic: &mut TerminalGraphic,
        graphic_rows: usize,
    ) -> bool {
        self.advance_cursor_after_graphic_block_at(
            graphic,
            graphic_rows,
            (self.cursor.col, self.cursor.row),
            0,
        )
    }

    fn advance_cursor_after_graphic_block_at(
        &mut self,
        graphic: &mut TerminalGraphic,
        graphic_rows: usize,
        base_position: (usize, usize),
        cursor_col: usize,
    ) -> bool {
        let graphic_rows = graphic_rows.max(1);
        let (_cols, screen_rows) = self.size();
        let (base_col, base_row) = base_position;
        let in_scroll_region =
            base_row >= self.scroll_region_top && base_row <= self.scroll_region_bottom;
        let outside_lr_margin =
            self.use_lr_margins && (base_col < self.left_margin || base_col > self.right_margin);
        let new_cursor_row = base_row.saturating_add(graphic_rows);
        let mut should_add_graphic = true;

        if in_scroll_region && !outside_lr_margin && new_cursor_row > self.scroll_region_bottom {
            let scroll_amount = new_cursor_row - self.scroll_region_bottom;
            let scroll_top = self.scroll_region_top;
            let scroll_bottom = self.scroll_region_bottom;

            self.active_grid_mut()
                .scroll_region_up(scroll_amount, scroll_top, scroll_bottom);
            self.adjust_graphics_for_scroll_up(scroll_amount, scroll_top, scroll_bottom);

            let original_row = graphic.position.1;
            let rows_above_region_top =
                scroll_amount.saturating_sub(original_row.saturating_sub(scroll_top));
            graphic.position.1 = original_row.saturating_sub(scroll_amount).max(scroll_top);
            graphic.scroll_offset_rows = graphic
                .scroll_offset_rows
                .saturating_add(rows_above_region_top);
            if graphic.scroll_offset_rows >= graphic_rows
                && (graphic.alternate_screen || scroll_top > 0)
            {
                should_add_graphic = false;
            }
            self.cursor.row = scroll_bottom;
        } else {
            self.cursor.row = new_cursor_row.min(screen_rows.saturating_sub(1));
        }
        self.cursor.col = cursor_col;
        self.pending_wrap = false;

        should_add_graphic
    }

    fn push_kitty_response(
        &mut self,
        image_id: Option<u32>,
        image_number: Option<u32>,
        message: &str,
    ) {
        let params = match (image_id, image_number) {
            (Some(id), Some(number)) => format!("i={id},I={number}"),
            (Some(id), None) => format!("i={id}"),
            (None, Some(number)) => format!("I={number}"),
            (None, None) => String::new(),
        };
        let response = format!("\x1b_G{params};{message}\x1b\\");
        self.push_response(response.as_bytes());
    }

    fn graphics_sequence_byte_limit(&self) -> usize {
        self.graphics_store
            .max_decoded_image_bytes()
            .saturating_mul(2)
            .saturating_add(GRAPHICS_SEQUENCE_OVERHEAD_BYTES)
            .max(GRAPHICS_SEQUENCE_OVERHEAD_BYTES)
    }

    fn iterm_inline_multipart_byte_limit(&self) -> usize {
        let decoded_limit = self.graphics_store.max_decoded_image_bytes();
        let base64_limit = (decoded_limit.saturating_add(2) / 3).saturating_mul(4);
        base64_limit
            .saturating_add(GRAPHICS_SEQUENCE_OVERHEAD_BYTES)
            .min(self.graphics_store.limits().max_total_memory)
    }

    fn graphics_sequence_exceeds_limit(&self, len: usize) -> bool {
        len > self.graphics_sequence_byte_limit()
    }

    fn retain_incomplete_kitty_apc(&mut self, pending: &[u8]) -> bool {
        if self.graphics_sequence_exceeds_limit(pending.len()) {
            self.kitty_apc_buffer.clear();
            return false;
        }
        self.kitty_apc_buffer.clear();
        self.kitty_apc_buffer.extend_from_slice(pending);
        true
    }

    /// Whether a Kitty graphics sequence or transfer is still incomplete.
    pub fn kitty_graphics_transfer_in_progress(&self) -> bool {
        self.kitty_parser.is_some() || !self.kitty_apc_buffer.is_empty()
    }

    /// Frame extraction must not advance Kitty delete state. Deferred deletes are
    /// resolved by later input events such as a replacement graphic or visible text.
    pub fn settle_graphics_transactions(&mut self) {}

    pub(crate) fn commit_deferred_kitty_deletes_for_visual_output(&mut self) {
        if let Some((image_id, placement_id, position, alternate_screen)) =
            self.pending_kitty_replacement_target()
        {
            self.graphics_store
                .commit_deferred_kitty_deletes_preserving_replacement(
                    image_id,
                    placement_id,
                    position,
                    alternate_screen,
                );
            return;
        }
        if self.kitty_transmission_in_progress() {
            return;
        }
        self.graphics_store.commit_deferred_kitty_deletes();
    }

    #[allow(clippy::type_complexity)]
    fn pending_kitty_replacement_target(&self) -> Option<(Option<u32>, u32, (usize, usize), bool)> {
        let parser = self.kitty_parser.as_ref()?;
        match parser.action {
            KittyAction::TransmitDisplay | KittyAction::Put => Some((
                parser.image_id,
                parser.placement_id.unwrap_or(0),
                parser
                    .placement_position
                    .unwrap_or((self.cursor.col, self.cursor.row)),
                self.alt_screen_active,
            )),
            _ => None,
        }
    }

    fn kitty_transmission_in_progress(&self) -> bool {
        let Some(parser) = self.kitty_parser.as_ref() else {
            return false;
        };
        parser.action == KittyAction::Transmit
    }

    /// Get graphics at a specific row
    pub fn graphics_at_row(&self, row: usize) -> Vec<&TerminalGraphic> {
        self.graphics_store
            .graphics_at_row(row)
            .into_iter()
            .filter(|graphic| graphic.alternate_screen == self.alt_screen_active)
            .collect()
    }

    /// Get all graphics
    pub fn all_graphics(&self) -> &[TerminalGraphic] {
        self.graphics_store.all_graphics()
    }

    /// Get Kitty placements retained while a clear-screen redraw is being coalesced.
    pub fn pending_cleared_kitty_graphics(&self) -> &[TerminalGraphic] {
        self.graphics_store.pending_cleared_kitty_graphics()
    }

    /// Get total graphics count
    pub fn graphics_count(&self) -> usize {
        self.graphics_store.graphics_count()
    }

    /// Get pending cleared Kitty placement count.
    pub fn pending_cleared_kitty_graphics_count(&self) -> usize {
        self.graphics_store.pending_cleared_kitty_graphics_count()
    }

    /// Count deferred Kitty deletes for diagnostics and tests.
    pub fn deferred_kitty_delete_count(&self) -> usize {
        self.graphics_store.deferred_kitty_delete_count()
    }

    /// Get graphics in scrollback for a range of rows
    pub fn scrollback_graphics(&self, start_row: usize, end_row: usize) -> Vec<&TerminalGraphic> {
        self.graphics_store
            .graphics_in_scrollback(start_row, end_row)
    }

    /// Get all scrollback graphics
    pub fn all_scrollback_graphics(&self) -> &[TerminalGraphic] {
        self.graphics_store.all_scrollback_graphics()
    }

    /// Get scrollback graphics count
    pub fn scrollback_graphics_count(&self) -> usize {
        self.graphics_store.scrollback_count()
    }

    /// Clear all graphics
    pub fn clear_graphics(&mut self) {
        self.graphics_store.clear_screen(self.alt_screen_active);
    }

    /// Get immutable access to graphics store
    pub fn graphics_store(&self) -> &crate::graphics::GraphicsStore {
        &self.graphics_store
    }

    /// Export all graphics state as JSON
    pub fn export_json_graphics(&self) -> String {
        self.graphics_store.export_json().unwrap_or_default()
    }

    /// Import graphics state from JSON
    pub fn import_json_graphics(&mut self, json: &str) -> Result<usize, String> {
        self.graphics_store
            .import_json(json)
            .map_err(|e| e.to_string())
    }

    /// Get mutable access to graphics store
    pub fn graphics_store_mut(&mut self) -> &mut crate::graphics::GraphicsStore {
        &mut self.graphics_store
    }

    pub(super) fn adjust_graphics_for_scroll_up(&mut self, n: usize, top: usize, bottom: usize) {
        // Get the current scrollback length from the grid (AFTER it has already scrolled)
        // We need to pass the OLD scrollback length (before scroll) to graphics store
        // Since the grid has already grown by `n` lines, subtract `n` to get the old length
        let scrollback_len = self.active_grid().scrollback_len();
        let primary_visible_base = self.grid.total_lines_scrolled();
        self.iterm_buttons.adjust_scroll_up(
            n,
            top,
            bottom,
            self.alt_screen_active,
            primary_visible_base,
        );
        let old_scrollback_len = if !self.alt_screen_active && top == 0 {
            scrollback_len.saturating_sub(n)
        } else {
            scrollback_len
        };

        // Adjust graphics - pass old_scrollback_len so graphics are placed at the correct position
        // Graphics entering scrollback should be placed where the text they align with went
        if !self.alt_screen_active && top == 0 {
            self.graphics_store
                .adjust_for_scroll_up_for_screen_with_scrollback_len(
                    n,
                    top,
                    bottom,
                    old_scrollback_len,
                    scrollback_len,
                    self.alt_screen_active,
                );
        } else {
            self.graphics_store.adjust_for_scroll_up_for_screen(
                n,
                top,
                bottom,
                old_scrollback_len,
                self.alt_screen_active,
            );
        }

        debug::log(
            debug::DebugLevel::Debug,
            "GRAPHICS",
            &format!(
                "Adjusted graphics for scroll_up: n={}, top={}, bottom={}, remaining graphics={}, scrollback={}, old_scrollback_len={} (current={})",
                n,
                top,
                bottom,
                self.graphics_store.graphics_count(),
                self.graphics_store.scrollback_count(),
                old_scrollback_len,
                scrollback_len
            ),
        );
    }

    /// Adjust graphics positions when scrolling down within a region
    ///
    /// When text scrolls down, graphics should scroll down with it.
    ///
    /// # Arguments
    /// * `n` - Number of lines scrolled
    /// * `top` - Top of scroll region (0-indexed)
    /// * `bottom` - Bottom of scroll region (0-indexed)
    pub(super) fn adjust_graphics_for_scroll_down(&mut self, n: usize, top: usize, bottom: usize) {
        let primary_visible_base = self.grid.total_lines_scrolled();
        self.iterm_buttons.adjust_scroll_down(
            n,
            top,
            bottom,
            self.alt_screen_active,
            primary_visible_base,
        );
        self.graphics_store.adjust_for_scroll_down_for_screen(
            n,
            top,
            bottom,
            self.alt_screen_active,
        );

        debug::log(
            debug::DebugLevel::Debug,
            "GRAPHICS",
            &format!(
                "Adjusted graphics for scroll_down: n={}, top={}, bottom={}",
                n, top, bottom
            ),
        );
    }

    /// Handle iTerm2 inline image (OSC 1337)
    ///
    /// Supports:
    /// - Single-sequence: `File=name=<b64>;size=<bytes>;inline=1:<base64 data>`
    /// - Multi-part: `MultipartFile=...` followed by `FilePart=<chunk>` sequences
    /// - File downloads (inline=0 or absent): tracked via FileTransferManager
    pub(crate) fn handle_iterm_image(&mut self, data: &str) {
        // Handle MultipartFile (start of chunked transfer)
        if let Some(params) = data.strip_prefix("MultipartFile=") {
            self.abort_iterm_multipart_buffer("interrupted by new MultipartFile");
            self.handle_multipart_file_start(params);
            return;
        }

        // Handle FilePart (chunk of data in multipart transfer)
        if let Some(chunk) = data.strip_prefix("FilePart=") {
            self.handle_file_part(chunk);
            return;
        }

        // Handle FileEnd (end of multipart transfer)
        if data == "FileEnd" {
            self.handle_file_end();
            return;
        }

        // Handle single-sequence File= transfer
        self.abort_iterm_multipart_buffer("interrupted by single File transfer");
        self.handle_single_file_transfer(data);
    }

    fn abort_iterm_multipart_buffer(&mut self, reason: &str) {
        let Some(state) = self.iterm_multipart_buffer.take() else {
            return;
        };
        if state.is_file_transfer {
            if let Some(transfer_id) = state.transfer_id {
                self.fail_iterm_file_transfer(transfer_id, reason.to_string());
            }
        }
    }

    /// Decode a base64-encoded filename from iTerm2 `name=` parameter
    fn decode_iterm_filename(params: &std::collections::HashMap<String, String>) -> String {
        const DEFAULT_FILENAME: &str = "Unnamed file";

        params
            .get("name")
            .and_then(|encoded| {
                crate::graphics::iterm::decode_base64_ignoring_ascii_whitespace(encoded.as_bytes())
                    .ok()
            })
            .and_then(|bytes| String::from_utf8(bytes).ok())
            .filter(|filename| !filename.is_empty())
            .unwrap_or_else(|| DEFAULT_FILENAME.to_string())
    }

    fn fail_iterm_file_transfer(&mut self, transfer_id: u64, reason: String) {
        let _ = self
            .file_transfer_manager
            .fail_transfer(transfer_id, reason.clone());
        self.terminal_events
            .push(crate::terminal::TerminalEvent::FileTransferFailed {
                id: transfer_id,
                reason,
            });
    }

    fn decode_complete_iterm_multipart_base64(
        state: &mut crate::terminal::ITermMultipartState,
        base64_chunk: &str,
    ) -> Result<Vec<u8>, String> {
        let cleaned_chunk: Vec<u8> = base64_chunk
            .bytes()
            .filter(|byte| !byte.is_ascii_whitespace())
            .collect();
        if cleaned_chunk.is_empty() {
            return Ok(Vec::new());
        }
        if state.base64_padding_seen {
            return Err("base64 data continued after padding".to_string());
        }
        if cleaned_chunk.contains(&b'=') {
            state.base64_padding_seen = true;
        }

        state.pending_base64.extend_from_slice(&cleaned_chunk);
        let decode_len = if state.base64_padding_seen {
            if !state.pending_base64.len().is_multiple_of(4) {
                return Ok(Vec::new());
            }
            state.pending_base64.len()
        } else {
            (state.pending_base64.len() / 4) * 4
        };
        if decode_len == 0 {
            return Ok(Vec::new());
        }

        let complete: Vec<u8> = state.pending_base64.drain(..decode_len).collect();
        crate::graphics::iterm::decode_base64_ignoring_ascii_whitespace(&complete)
            .map_err(|error| error.to_string())
    }

    fn decode_final_iterm_multipart_base64(
        state: &mut crate::terminal::ITermMultipartState,
    ) -> Result<Vec<u8>, String> {
        if state.pending_base64.is_empty() {
            return Ok(Vec::new());
        }
        let complete = std::mem::take(&mut state.pending_base64);
        crate::graphics::iterm::decode_base64_ignoring_ascii_whitespace(&complete)
            .map_err(|error| error.to_string())
    }

    /// Handle MultipartFile command (start of chunked transfer)
    fn handle_multipart_file_start(&mut self, params_str: &str) {
        use std::collections::HashMap;

        // Parse parameters: inline=1;size=280459;name=...
        let mut params = HashMap::new();
        for part in params_str.split(';') {
            if let Some((key, value)) = part.split_once('=') {
                params.insert(key.to_string(), value.to_string());
            }
        }

        let is_inline = params.get("inline").map(|v| v == "1").unwrap_or(false);
        let total_size = params.get("size").and_then(|s| s.parse::<usize>().ok());

        if is_inline {
            let decoded_limit = self.graphics_store.max_decoded_image_bytes();
            let state_limit = self.iterm_inline_multipart_byte_limit();
            let params_bytes = params
                .iter()
                .map(|(key, value)| key.len().saturating_add(value.len()))
                .sum::<usize>();
            if params_bytes > state_limit {
                debug::log(
                    debug::DebugLevel::Debug,
                    "ITERM",
                    &format!(
                        "MultipartFile rejected: retained parameters exceed limit {}",
                        state_limit
                    ),
                );
                return;
            }

            // Inline image path: check graphics limits
            if let Some(size) = total_size {
                if size > decoded_limit {
                    debug::log(
                        debug::DebugLevel::Debug,
                        "ITERM",
                        &format!(
                            "MultipartFile rejected: size {} exceeds graphics limit {}",
                            size, decoded_limit
                        ),
                    );
                    return;
                }
            }

            // Initialize multipart state for inline image
            self.iterm_multipart_buffer = Some(crate::terminal::ITermMultipartState {
                params,
                encoded_data: String::new(),
                pending_base64: Vec::new(),
                base64_padding_seen: false,
                total_size,
                accumulated_size: 0,
                is_file_transfer: false,
                transfer_id: None,
            });
        } else {
            // File transfer path: check file transfer size limits
            if let Some(size) = total_size {
                let max_size = self.file_transfer_manager.max_transfer_size();
                if size > max_size {
                    debug::log(
                        debug::DebugLevel::Debug,
                        "ITERM",
                        &format!(
                            "MultipartFile file transfer rejected: size {} exceeds limit {}",
                            size, max_size
                        ),
                    );
                    return;
                }
            }

            // Decode filename from base64 name= param
            let filename = Self::decode_iterm_filename(&params);

            // Start a download in the file transfer manager
            let transfer_id = self.file_transfer_manager.start_download(
                filename.clone(),
                total_size,
                params.clone(),
            );

            // Emit FileTransferStarted event
            self.terminal_events
                .push(crate::terminal::TerminalEvent::FileTransferStarted {
                    id: transfer_id,
                    direction: crate::terminal::TransferDirection::Download,
                    filename: if filename.is_empty() {
                        None
                    } else {
                        Some(filename)
                    },
                    total_bytes: total_size,
                });

            // Initialize multipart state for file transfer
            self.iterm_multipart_buffer = Some(crate::terminal::ITermMultipartState {
                params,
                encoded_data: String::new(),
                pending_base64: Vec::new(),
                base64_padding_seen: false,
                total_size,
                accumulated_size: 0,
                is_file_transfer: true,
                transfer_id: Some(transfer_id),
            });
        }
    }

    /// Handle FilePart command (chunk of data in multipart transfer)
    fn handle_file_part(&mut self, base64_chunk: &str) {
        let inline_decoded_limit = self.graphics_store.max_decoded_image_bytes();
        let inline_encoded_limit = self.iterm_inline_multipart_byte_limit();

        let encoded_limit_exceeded = self
            .iterm_multipart_buffer
            .as_ref()
            .filter(|state| !state.is_file_transfer)
            .is_some_and(|state| {
                state.retained_bytes().saturating_add(base64_chunk.len()) > inline_encoded_limit
            });
        if encoded_limit_exceeded {
            debug::log(
                debug::DebugLevel::Debug,
                "ITERM",
                &format!(
                    "FilePart rejected: retained encoded inline data exceeds limit {}",
                    inline_encoded_limit
                ),
            );
            self.iterm_multipart_buffer = None;
            return;
        }

        // Check if we have an active multipart transfer
        let state = match self.iterm_multipart_buffer.as_mut() {
            Some(s) => s,
            None => {
                debug::log(
                    debug::DebugLevel::Debug,
                    "ITERM",
                    "FilePart received without MultipartFile",
                );
                return;
            }
        };

        // Decode only complete base64 quanta. iTerm2 MultipartFile/FilePart
        // streams may split the encoded data at arbitrary byte boundaries.
        let decoded = match Self::decode_complete_iterm_multipart_base64(state, base64_chunk) {
            Ok(d) => d,
            Err(e) => {
                debug::log(
                    debug::DebugLevel::Debug,
                    "ITERM",
                    &format!("FilePart base64 decode failed: {}", e),
                );
                // If this is a file transfer, emit failure event
                if state.is_file_transfer {
                    if let Some(transfer_id) = state.transfer_id {
                        let _ = self
                            .file_transfer_manager
                            .fail_transfer(transfer_id, format!("base64 decode error: {}", e));
                        self.terminal_events.push(
                            crate::terminal::TerminalEvent::FileTransferFailed {
                                id: transfer_id,
                                reason: format!("base64 decode error: {}", e),
                            },
                        );
                    }
                }
                self.iterm_multipart_buffer = None;
                return;
            }
        };
        let decoded_size = decoded.len();
        let new_accumulated = state.accumulated_size.saturating_add(decoded_size);

        if !state.is_file_transfer && new_accumulated > inline_decoded_limit {
            debug::log(
                debug::DebugLevel::Debug,
                "ITERM",
                &format!(
                    "FilePart rejected: decoded inline data {} exceeds limit {}",
                    new_accumulated, inline_decoded_limit
                ),
            );
            self.iterm_multipart_buffer = None;
            return;
        }

        if let Some(expected_size) = state.total_size {
            if new_accumulated > expected_size {
                let reason = format!(
                    "size mismatch: received {} bytes, expected {}",
                    new_accumulated, expected_size
                );
                debug::log(
                    debug::DebugLevel::Debug,
                    "ITERM",
                    &format!(
                        "FilePart rejected: accumulated {} + chunk {} > expected {}",
                        state.accumulated_size, decoded_size, expected_size
                    ),
                );
                if state.is_file_transfer {
                    if let Some(transfer_id) = state.transfer_id {
                        self.fail_iterm_file_transfer(transfer_id, reason);
                    }
                }
                self.iterm_multipart_buffer = None;
                return;
            }
        }

        if state.is_file_transfer && !decoded.is_empty() {
            // File transfer path: append decoded data to transfer manager
            if let Some(transfer_id) = state.transfer_id {
                if let Err(e) = self
                    .file_transfer_manager
                    .append_data(transfer_id, &decoded)
                {
                    debug::log(
                        debug::DebugLevel::Debug,
                        "ITERM",
                        &format!("File transfer append failed: {}", e),
                    );
                    self.terminal_events
                        .push(crate::terminal::TerminalEvent::FileTransferFailed {
                            id: transfer_id,
                            reason: e,
                        });
                    self.iterm_multipart_buffer = None;
                    return;
                }

                // Emit progress event
                self.terminal_events
                    .push(crate::terminal::TerminalEvent::FileTransferProgress {
                        id: transfer_id,
                        bytes_transferred: new_accumulated,
                        total_bytes: state.total_size,
                    });
            }
        }

        // For inline images: accumulate base64 chunks
        if !state.is_file_transfer {
            state.encoded_data.push_str(base64_chunk);
        }
        state.accumulated_size = new_accumulated;

        // iTerm2 multipart transfers are explicitly terminated by FileEnd.
        // size= is kept as an expected decoded byte count for limit checks and
        // progress reporting, not as an implicit end marker.
    }

    /// Handle FileEnd command (end of multipart transfer).
    fn handle_file_end(&mut self) {
        if self.iterm_multipart_buffer.is_none() {
            debug::log(
                debug::DebugLevel::Debug,
                "ITERM",
                "FileEnd received without MultipartFile",
            );
            return;
        }

        self.finalize_multipart_transfer();
    }

    /// Finalize multipart transfer and process the complete data
    fn finalize_multipart_transfer(&mut self) {
        let inline_decoded_limit = self.graphics_store.max_decoded_image_bytes();
        // Take the buffer state
        let mut state = match self.iterm_multipart_buffer.take() {
            Some(s) => s,
            None => return,
        };

        let final_decoded = match Self::decode_final_iterm_multipart_base64(&mut state) {
            Ok(decoded) => decoded,
            Err(error) => {
                debug::log(
                    debug::DebugLevel::Debug,
                    "ITERM",
                    &format!("FileEnd base64 decode failed: {}", error),
                );
                if state.is_file_transfer {
                    if let Some(transfer_id) = state.transfer_id {
                        self.fail_iterm_file_transfer(
                            transfer_id,
                            format!("base64 decode error: {}", error),
                        );
                    }
                }
                return;
            }
        };

        if !final_decoded.is_empty() {
            let new_accumulated = state.accumulated_size.saturating_add(final_decoded.len());
            if !state.is_file_transfer && new_accumulated > inline_decoded_limit {
                debug::log(
                    debug::DebugLevel::Debug,
                    "ITERM",
                    &format!(
                        "FileEnd rejected: decoded inline data {} exceeds limit {}",
                        new_accumulated, inline_decoded_limit
                    ),
                );
                return;
            }
            if let Some(expected_size) = state.total_size {
                if new_accumulated > expected_size {
                    let reason = format!(
                        "size mismatch: received {} bytes, expected {}",
                        new_accumulated, expected_size
                    );
                    debug::log(
                        debug::DebugLevel::Debug,
                        "ITERM",
                        &format!("FileEnd rejected: {}", reason),
                    );
                    if state.is_file_transfer {
                        if let Some(transfer_id) = state.transfer_id {
                            self.fail_iterm_file_transfer(transfer_id, reason);
                        }
                    }
                    return;
                }
            }
            if state.is_file_transfer {
                if let Some(transfer_id) = state.transfer_id {
                    if let Err(error) = self
                        .file_transfer_manager
                        .append_data(transfer_id, &final_decoded)
                    {
                        debug::log(
                            debug::DebugLevel::Debug,
                            "ITERM",
                            &format!("File transfer append failed: {}", error),
                        );
                        self.terminal_events.push(
                            crate::terminal::TerminalEvent::FileTransferFailed {
                                id: transfer_id,
                                reason: error,
                            },
                        );
                        return;
                    }
                    self.terminal_events.push(
                        crate::terminal::TerminalEvent::FileTransferProgress {
                            id: transfer_id,
                            bytes_transferred: new_accumulated,
                            total_bytes: state.total_size,
                        },
                    );
                }
            }
            state.accumulated_size = new_accumulated;
        }

        if let Some(expected_size) = state.total_size {
            if state.accumulated_size != expected_size {
                let reason = format!(
                    "size mismatch: received {} bytes, expected {}",
                    state.accumulated_size, expected_size
                );
                debug::log(
                    debug::DebugLevel::Debug,
                    "ITERM",
                    &format!("FileEnd rejected: {}", reason),
                );
                if state.is_file_transfer {
                    if let Some(transfer_id) = state.transfer_id {
                        self.fail_iterm_file_transfer(transfer_id, reason);
                    }
                }
                return;
            }
        }

        if state.is_file_transfer {
            // File transfer path: complete the transfer
            if let Some(transfer_id) = state.transfer_id {
                // Get the filename and size before completing
                let filename = Self::decode_iterm_filename(&state.params);
                let size = self
                    .file_transfer_manager
                    .get_transfer(transfer_id)
                    .map(|t| t.data.len())
                    .unwrap_or(0);

                match self.file_transfer_manager.complete_transfer(transfer_id) {
                    Ok(()) => {
                        self.terminal_events.push(
                            crate::terminal::TerminalEvent::FileTransferCompleted {
                                id: transfer_id,
                                filename: if filename.is_empty() {
                                    None
                                } else {
                                    Some(filename)
                                },
                                size,
                            },
                        );
                    }
                    Err(e) => {
                        debug::log(
                            debug::DebugLevel::Debug,
                            "ITERM",
                            &format!("File transfer complete failed: {}", e),
                        );
                        self.terminal_events.push(
                            crate::terminal::TerminalEvent::FileTransferFailed {
                                id: transfer_id,
                                reason: e,
                            },
                        );
                    }
                }
            }
        } else {
            // Inline image path: delegate the bounded accumulated data to the
            // single-sequence decoder.
            let complete_data = state.encoded_data;

            // Reconstruct File= format string with params
            let mut params_parts = Vec::new();
            for (key, value) in &state.params {
                params_parts.push(format!("{}={}", key, value));
            }
            let params_str = params_parts.join(";");
            let file_data = format!("File={}:{}", params_str, complete_data);

            // Process as single-file transfer (inline image)
            self.handle_single_file_transfer(&file_data);
        }
    }

    /// Handle single-sequence File= transfer
    ///
    /// Routes to either inline image display (inline=1) or file download
    /// tracking (inline=0 or absent) based on the parsed parameters.
    fn handle_single_file_transfer(&mut self, data: &str) {
        use crate::graphics::iterm::ITermParser;

        // Split into params and image data at the colon
        let (params_str, image_data) = match data.split_once(':') {
            Some((p, d)) => (p, d),
            None => {
                debug::log(
                    debug::DebugLevel::Debug,
                    "ITERM",
                    "No colon separator in File= format",
                );
                return;
            }
        };

        // Must start with "File="
        if !params_str.starts_with("File=") {
            debug::log(
                debug::DebugLevel::Debug,
                "ITERM",
                &unsupported_iterm_log_message(params_str),
            );
            return;
        }

        let params_str = &params_str[5..]; // Remove "File=" prefix

        let mut parser = ITermParser::new();

        // Parse parameters
        if let Err(e) = parser.parse_params(params_str) {
            debug::log(
                debug::DebugLevel::Debug,
                "ITERM",
                &format!("Failed to parse iTerm params: {}", e),
            );
            return;
        }

        if parser.is_inline() {
            // ===== Inline image path (UNCHANGED from original) =====
            // Set the base64 image data
            parser.set_data(image_data.as_bytes());

            // Get cursor position for graphic placement
            let position = (self.cursor.col, self.cursor.row);

            // Decode and create graphic
            match parser.decode_image_with_animation(position) {
                Ok(decoded) => {
                    let mut graphic = decoded.graphic;
                    let animation_frames = decoded.animation_frames;
                    let animation_id = if animation_frames.len() > 1 {
                        Some(self.graphics_store.allocate_local_animation_id())
                    } else {
                        None
                    };
                    graphic.animation_id = animation_id;
                    graphic.set_alternate_screen(self.alt_screen_active);
                    // Set cell dimensions
                    let (cell_w, cell_h) = self.cell_dimensions;
                    graphic.set_cell_dimensions(cell_w, cell_h);
                    let (cols, rows) = self.size();
                    let (graphic_width_in_cols, graphic_height_in_rows) =
                        graphic.resolved_cell_span(Some(cols), Some(rows));
                    graphic.set_display_cell_span(graphic_width_in_cols, graphic_height_in_rows);

                    let mut should_add_graphic = true;
                    if !parser.do_not_move_cursor() {
                        should_add_graphic = self.advance_cursor_after_graphic_block(
                            &mut graphic,
                            graphic_height_in_rows,
                        );
                    }

                    // Add to graphics store (limit enforced internally)
                    let row = graphic.position.1;
                    if should_add_graphic && self.graphics_store.add_graphic(graphic.clone()) {
                        if let Some(animation_id) = animation_id {
                            for frame in animation_frames {
                                self.graphics_store.add_animation_frame(animation_id, frame);
                            }
                            self.graphics_store.control_animation(
                                animation_id,
                                crate::graphics::AnimationControl::EnableLooping,
                            );
                        }
                        self.terminal_events
                            .push(crate::terminal::TerminalEvent::GraphicsAdded(row));

                        debug::log(
                            debug::DebugLevel::Debug,
                            "ITERM",
                            &format!(
                                "Added iTerm image at ({}, {}), size {}x{}, cursor moved to ({}, {})",
                                position.0,
                                position.1,
                                graphic.width,
                                graphic.height,
                                self.cursor.col,
                                self.cursor.row
                            ),
                        );
                    }
                }
                Err(e) => {
                    debug::log(
                        debug::DebugLevel::Debug,
                        "ITERM",
                        &format!("Failed to decode iTerm image: {}", e),
                    );
                }
            }
        } else {
            // ===== File download path =====
            // Decode the base64 data
            let decoded = match crate::graphics::iterm::decode_base64_ignoring_ascii_whitespace(
                image_data.as_bytes(),
            ) {
                Ok(d) => d,
                Err(e) => {
                    debug::log(
                        debug::DebugLevel::Debug,
                        "ITERM",
                        &format!("File transfer base64 decode failed: {}", e),
                    );
                    return;
                }
            };

            let filename = Self::decode_iterm_filename(parser.params());
            let expected_size = parser.declared_size();
            let total_bytes = expected_size.or(Some(decoded.len()));

            // Start, append data, and complete in one go
            let transfer_id = self.file_transfer_manager.start_download(
                filename.clone(),
                total_bytes,
                parser.params().clone(),
            );

            // Emit started event
            self.terminal_events
                .push(crate::terminal::TerminalEvent::FileTransferStarted {
                    id: transfer_id,
                    direction: crate::terminal::TransferDirection::Download,
                    filename: if filename.is_empty() {
                        None
                    } else {
                        Some(filename.clone())
                    },
                    total_bytes,
                });

            if let Some(expected_size) = expected_size {
                if decoded.len() != expected_size {
                    self.fail_iterm_file_transfer(
                        transfer_id,
                        format!(
                            "size mismatch: received {} bytes, expected {}",
                            decoded.len(),
                            expected_size
                        ),
                    );
                    return;
                }
            }

            // Append the full data
            if let Err(e) = self
                .file_transfer_manager
                .append_data(transfer_id, &decoded)
            {
                debug::log(
                    debug::DebugLevel::Debug,
                    "ITERM",
                    &format!("File transfer append failed: {}", e),
                );
                self.terminal_events
                    .push(crate::terminal::TerminalEvent::FileTransferFailed {
                        id: transfer_id,
                        reason: e,
                    });
                return;
            }

            // Complete the transfer
            let size = decoded.len();
            match self.file_transfer_manager.complete_transfer(transfer_id) {
                Ok(()) => {
                    self.terminal_events.push(
                        crate::terminal::TerminalEvent::FileTransferCompleted {
                            id: transfer_id,
                            filename: if filename.is_empty() {
                                None
                            } else {
                                Some(filename)
                            },
                            size,
                        },
                    );
                }
                Err(e) => {
                    self.terminal_events
                        .push(crate::terminal::TerminalEvent::FileTransferFailed {
                            id: transfer_id,
                            reason: e,
                        });
                }
            }
        }
    }
}

fn find_bytes(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || haystack.len() < needle.len() {
        return None;
    }
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

fn find_apc_terminator(input: &[u8], start: usize) -> Option<(usize, usize)> {
    let mut index = start;
    while index < input.len() {
        if input[index] == b'\x07' {
            return Some((index, index + 1));
        }
        if input[index] == b'\x1b' && input.get(index + 1) == Some(&b'\\') {
            return Some((index, index + 2));
        }
        index += 1;
    }
    None
}

fn kitty_payload_is_delete_command(payload: &str) -> bool {
    let params = payload
        .split_once(';')
        .map_or(payload, |(params, _)| params);
    params.split(',').any(|pair| {
        let Some((key, value)) = pair.split_once('=') else {
            return false;
        };
        key == "a" && value.starts_with('d')
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::graphics::{next_graphic_id, GraphicProtocol, TerminalGraphic};

    fn create_test_terminal() -> Terminal {
        Terminal::new(80, 24)
    }

    fn create_test_graphic(col: usize, row: usize, width: usize, height: usize) -> TerminalGraphic {
        TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Sixel,
            (col, row),
            width,
            height,
            vec![], // Empty pixels for tests
        )
    }

    #[test]
    fn kitty_delete_command_detection_handles_unordered_parameters() {
        assert!(kitty_payload_is_delete_command("a=d,d=i,i=1;"));
        assert!(kitty_payload_is_delete_command("d=i,i=1,a=d;"));
        assert!(!kitty_payload_is_delete_command("a=T,m=1;AAAA"));
        assert!(!kitty_payload_is_delete_command("m=0;AAAA"));
    }

    #[test]
    fn unsupported_iterm_log_message_never_contains_command() {
        let command = "command-secret-canary";
        let message = unsupported_iterm_log_message(command);

        assert!(!message.contains(command));
        assert!(message.contains(&format!("command_bytes={}", command.len())));
    }

    #[test]
    fn kitty_reply_uses_the_atomic_response_budget() {
        const RESPONSE: &[u8] = b"\x1b_Gi=7;OK\x1b\\";
        let mut term = create_test_terminal();
        let filler = vec![b'x'; crate::terminal::MAX_RESPONSE_BUFFER_BYTES - RESPONSE.len() + 1];
        term.push_response(&filler);
        drop(filler);

        term.push_kitty_response(Some(7), None, "OK");
        assert_eq!(
            term.response_buffer.len(),
            crate::terminal::MAX_RESPONSE_BUFFER_BYTES - RESPONSE.len() + 1
        );
        assert_eq!(term.response_buffer_overflow_count(), 1);
        let buffered = term.drain_responses();
        assert!(buffered.iter().all(|byte| *byte == b'x'));
        drop(buffered);

        term.push_kitty_response(Some(7), None, "OK");
        assert_eq!(term.drain_responses(), RESPONSE);
    }

    #[test]
    fn incomplete_kitty_apc_over_limit_is_dropped() {
        let mut term = create_test_terminal();
        term.set_graphics_memory_limits(8, 8);
        let mut payload = b"\x1b_Ga=T,f=32,s=1,v=1;".to_vec();
        payload.extend(std::iter::repeat_n(b'A', 5000));

        term.process(&payload);

        assert!(term.kitty_apc_buffer.is_empty());
        assert!(!term.kitty_graphics_transfer_in_progress());
    }

    #[test]
    fn kitty_apc_accepts_c1_apc_and_st_controls() {
        let mut term = create_test_terminal();
        let mut sequence = Vec::new();
        sequence.push(0x9f);
        sequence.extend_from_slice(b"Ga=T,f=32,s=1,v=1,i=17,q=1;/wAA/w==");
        sequence.push(0x9c);

        term.process(&sequence);

        assert_eq!(term.graphics_count(), 1);
        let graphic = term.all_graphics().last().expect("expected Kitty graphic");
        assert_eq!(graphic.protocol.as_str(), "kitty");
        assert_eq!(graphic.width, 1);
        assert_eq!(graphic.height, 1);
        assert_eq!(graphic.kitty_image_id, Some(17));
        assert_eq!(graphic.pixels.as_ref(), &[255, 0, 0, 255]);
        assert!(term.drain_responses().is_empty());
    }

    #[test]
    fn incomplete_tmux_passthrough_retains_only_decoder_state() {
        let mut term = create_test_terminal();
        term.set_graphics_memory_limits(8, 8);
        let mut payload = b"\x1bPtmux;".to_vec();
        payload.extend(std::iter::repeat_n(b'A', 5000));

        term.process(&payload);

        assert_eq!(
            term.graphics_passthrough_state,
            GraphicsPassthroughState::TmuxPayload
        );
        assert!(term.drain_responses().is_empty());
    }

    #[test]
    fn test_graphics_at_row_empty() {
        let term = create_test_terminal();
        let graphics = term.graphics_at_row(0);
        assert_eq!(graphics.len(), 0);
    }

    #[test]
    fn test_graphics_at_row_single_graphic() {
        let mut term = create_test_terminal();
        // Graphic at row 5 with height 4 pixels (occupies 2 terminal rows: 5 and 6)
        let graphic = create_test_graphic(0, 5, 10, 4);
        term.graphics_store.add_graphic(graphic);

        let graphics_row_5 = term.graphics_at_row(5);
        assert_eq!(graphics_row_5.len(), 1);

        let graphics_row_6 = term.graphics_at_row(6);
        assert_eq!(graphics_row_6.len(), 1);

        let graphics_row_7 = term.graphics_at_row(7);
        assert_eq!(graphics_row_7.len(), 0);
    }

    #[test]
    fn test_graphics_at_row_multiple_graphics() {
        let mut term = create_test_terminal();
        // Graphic 1: row 5, height 4 pixels (rows 5-6)
        term.graphics_store
            .add_graphic(create_test_graphic(0, 5, 10, 4));
        // Graphic 2: row 10, height 6 pixels (rows 10-12)
        term.graphics_store
            .add_graphic(create_test_graphic(0, 10, 10, 6));
        // Graphic 3: row 5, height 2 pixels (rows 5-5)
        term.graphics_store
            .add_graphic(create_test_graphic(20, 5, 10, 2));

        let graphics_row_5 = term.graphics_at_row(5);
        assert_eq!(graphics_row_5.len(), 2); // Graphics 1 and 3

        let graphics_row_10 = term.graphics_at_row(10);
        assert_eq!(graphics_row_10.len(), 1); // Only graphic 2

        let graphics_row_8 = term.graphics_at_row(8);
        assert_eq!(graphics_row_8.len(), 0); // No graphics
    }

    #[test]
    fn test_graphics_at_row_odd_height() {
        let mut term = create_test_terminal();
        // Graphic with height 5 pixels (occupies 3 terminal rows due to div_ceil)
        term.graphics_store
            .add_graphic(create_test_graphic(0, 10, 10, 5));

        assert_eq!(term.graphics_at_row(10).len(), 1);
        assert_eq!(term.graphics_at_row(11).len(), 1);
        assert_eq!(term.graphics_at_row(12).len(), 1);
        assert_eq!(term.graphics_at_row(13).len(), 0);
    }

    #[test]
    fn test_graphics_count() {
        let mut term = create_test_terminal();
        assert_eq!(term.graphics_count(), 0);

        term.graphics_store
            .add_graphic(create_test_graphic(0, 0, 10, 10));
        assert_eq!(term.graphics_count(), 1);

        term.graphics_store
            .add_graphic(create_test_graphic(0, 5, 10, 10));
        assert_eq!(term.graphics_count(), 2);
    }

    #[test]
    fn test_clear_graphics() {
        let mut term = create_test_terminal();
        term.graphics_store
            .add_graphic(create_test_graphic(0, 0, 10, 10));
        term.graphics_store
            .add_graphic(create_test_graphic(0, 5, 10, 10));
        assert_eq!(term.graphics_count(), 2);

        term.clear_graphics();
        assert_eq!(term.graphics_count(), 0);
        assert_eq!(term.all_graphics().len(), 0);
    }

    #[test]
    fn test_adjust_graphics_for_scroll_up_basic() {
        let mut term = create_test_terminal();
        // Graphic at row 10
        term.graphics_store
            .add_graphic(create_test_graphic(0, 10, 10, 4));

        // Scroll up 3 lines in region 0-23
        term.adjust_graphics_for_scroll_up(3, 0, 23);

        assert_eq!(term.graphics_store.graphics_count(), 1);
        assert_eq!(term.graphics_store.all_graphics()[0].position.1, 7); // Moved from 10 to 7
    }

    #[test]
    fn test_adjust_graphics_for_scroll_up_remove() {
        let mut term = create_test_terminal();
        // Graphic at row 2 will scroll off when scrolling up 5 lines
        term.graphics_store
            .add_graphic(create_test_graphic(0, 2, 10, 4));

        term.adjust_graphics_for_scroll_up(5, 0, 23);

        assert_eq!(term.graphics_store.graphics_count(), 0); // Graphic removed
    }

    #[test]
    fn test_adjust_graphics_for_scroll_up_partial_region() {
        let mut term = create_test_terminal();
        // Graphic at row 5 (inside scroll region 3-15)
        term.graphics_store
            .add_graphic(create_test_graphic(0, 5, 10, 4));
        // Graphic at row 20 (outside scroll region)
        term.graphics_store
            .add_graphic(create_test_graphic(0, 20, 10, 4));

        term.adjust_graphics_for_scroll_up(2, 3, 15);

        assert_eq!(term.graphics_store.graphics_count(), 2);
        assert_eq!(term.graphics_store.all_graphics()[0].position.1, 3); // Moved from 5 to 3
        assert_eq!(term.graphics_store.all_graphics()[1].position.1, 20); // Unchanged
    }

    #[test]
    fn test_adjust_graphics_for_scroll_up_drops_boundary_overlap() {
        let mut term = create_test_terminal();
        // Graphic starts above scroll region but extends into it
        // Row 2, height 6 pixels (3 terminal rows: 2, 3, 4)
        // Scroll region is 3-15
        term.graphics_store
            .add_graphic(create_test_graphic(0, 2, 10, 6));

        term.adjust_graphics_for_scroll_up(2, 3, 15);

        // A graphic crossing a scroll-region boundary cannot be split safely.
        assert_eq!(term.graphics_store.graphics_count(), 0);
    }

    #[test]
    fn test_adjust_graphics_for_scroll_down_basic() {
        let mut term = create_test_terminal();
        // Graphic at row 10
        term.graphics_store
            .add_graphic(create_test_graphic(0, 10, 10, 4));

        // Scroll down 3 lines in region 0-23
        term.adjust_graphics_for_scroll_down(3, 0, 23);

        assert_eq!(term.graphics_store.graphics_count(), 1);
        assert_eq!(term.graphics_store.all_graphics()[0].position.1, 13); // Moved from 10 to 13
    }

    #[test]
    fn test_adjust_graphics_for_scroll_down_drops_at_bottom() {
        let mut term = create_test_terminal();
        // Graphic at row 22 in region 0-23
        term.graphics_store
            .add_graphic(create_test_graphic(0, 22, 10, 4));

        // Scroll down 5 lines - the graphic leaves the scroll region.
        term.adjust_graphics_for_scroll_down(5, 0, 23);

        assert_eq!(term.graphics_store.graphics_count(), 0);
    }

    #[test]
    fn test_adjust_graphics_for_scroll_down_partial_region() {
        let mut term = create_test_terminal();
        // Graphic at row 5 (inside scroll region 3-15)
        term.graphics_store
            .add_graphic(create_test_graphic(0, 5, 10, 4));
        // Graphic at row 20 (outside scroll region)
        term.graphics_store
            .add_graphic(create_test_graphic(0, 20, 10, 4));

        term.adjust_graphics_for_scroll_down(2, 3, 15);

        assert_eq!(term.graphics_store.graphics_count(), 2);
        assert_eq!(term.graphics_store.all_graphics()[0].position.1, 7); // Moved from 5 to 7
        assert_eq!(term.graphics_store.all_graphics()[1].position.1, 20); // Unchanged
    }

    #[test]
    fn test_adjust_graphics_for_scroll_down_drops_beyond_bottom() {
        let mut term = create_test_terminal();
        // Graphic at row 14 in scroll region 0-15
        term.graphics_store
            .add_graphic(create_test_graphic(0, 14, 10, 4));

        // Scroll down 3 lines - would go to row 17 which is beyond bottom (15)
        term.adjust_graphics_for_scroll_down(3, 0, 15);

        assert_eq!(term.graphics_store.graphics_count(), 0);
    }

    #[test]
    fn test_graphics_height_calculation() {
        let mut term = create_test_terminal();
        // Height 1 pixel = 1 terminal row
        term.graphics_store
            .add_graphic(create_test_graphic(0, 5, 10, 1));
        assert_eq!(term.graphics_at_row(5).len(), 1);
        assert_eq!(term.graphics_at_row(6).len(), 0);

        term.clear_graphics();

        // Height 2 pixels = 1 terminal row
        term.graphics_store
            .add_graphic(create_test_graphic(0, 5, 10, 2));
        assert_eq!(term.graphics_at_row(5).len(), 1);
        assert_eq!(term.graphics_at_row(6).len(), 0);

        term.clear_graphics();

        // Height 3 pixels = 2 terminal rows (div_ceil)
        term.graphics_store
            .add_graphic(create_test_graphic(0, 5, 10, 3));
        assert_eq!(term.graphics_at_row(5).len(), 1);
        assert_eq!(term.graphics_at_row(6).len(), 1);
        assert_eq!(term.graphics_at_row(7).len(), 0);
    }

    #[test]
    fn test_adjust_graphics_for_scroll_up_tall_graphic_bottom_visible() {
        // Bug fix test: Tall graphics should remain if their bottom is still visible
        // This reproduces the snake.sixel issue: 450px (225 rows) graphic in 40-row terminal
        let mut term = Terminal::new(80, 40);

        // Create a tall graphic at row 0, height 450 pixels = 225 terminal rows
        // Bottom is at row 224
        term.graphics_store
            .add_graphic(create_test_graphic(0, 0, 600, 450));

        // Scroll up by 186 rows (simulating cursor advancing from 0 to 225, then scrolling back to fit)
        // After scroll: top would be at -186 (clamped to 0), bottom at 38 (visible!)
        term.adjust_graphics_for_scroll_up(186, 0, 39);

        // Graphic should still exist (bottom is visible)
        assert_eq!(
            term.graphics_store.graphics_count(),
            1,
            "Graphic should remain when bottom is visible"
        );

        // Position should be clamped to 0
        assert_eq!(
            term.graphics_store.all_graphics()[0].position.1,
            0,
            "Position should be clamped to 0"
        );

        // After clamping to position 0, graphic still has height 225 rows
        // So it spans rows 0-224, meaning ALL visible terminal rows (0-39) show the graphic
        assert!(
            !term.graphics_at_row(0).is_empty(),
            "Graphic should be visible at row 0"
        );
        assert!(
            !term.graphics_at_row(39).is_empty(),
            "Graphic should be visible at row 39"
        );

        // The graphic spans to row 224, so any row >= 225 would not show it
        // But our terminal only has 40 rows, so we can't test row 225
        // Instead verify the graphic height is still 225 rows
        assert_eq!(
            term.graphics_store.all_graphics()[0].height,
            450,
            "Graphic height should be unchanged"
        );

        // Verify scroll offset tracks how many rows scrolled off the top
        assert_eq!(
            term.graphics_store.all_graphics()[0].scroll_offset_rows,
            186,
            "Should track 186 rows scrolled off"
        );
    }

    #[test]
    fn test_adjust_graphics_for_scroll_up_tall_graphic_completely_off() {
        // Test that graphics are removed when bottom scrolls completely off
        let mut term = Terminal::new(80, 40);

        // Create a graphic at row 0, height 40 pixels = 20 terminal rows
        term.graphics_store
            .add_graphic(create_test_graphic(0, 0, 100, 40));

        // Scroll up by 25 rows (more than the graphic's height of 20 rows)
        // Bottom is at row 19, so 25 >= 20 means completely off screen
        term.adjust_graphics_for_scroll_up(25, 0, 39);

        // Graphic should be removed
        assert_eq!(
            term.graphics_store.graphics_count(),
            0,
            "Graphic should be removed when bottom scrolls off"
        );
    }

    #[test]
    fn test_adjust_graphics_for_scroll_up_tall_graphic_edge_case() {
        // Test edge case where scroll amount equals graphic bottom
        let mut term = Terminal::new(80, 40);

        // Create a graphic at row 0, height 40 pixels = 20 terminal rows
        // Bottom is at row 19
        term.graphics_store
            .add_graphic(create_test_graphic(0, 0, 100, 40));

        // Scroll up by exactly 20 rows (n >= graphic_bottom means remove)
        term.adjust_graphics_for_scroll_up(20, 0, 39);

        // Graphic should be removed (boundary condition)
        assert_eq!(
            term.graphics_store.graphics_count(),
            0,
            "Graphic should be removed when n >= bottom"
        );
    }
}
