//! Terminal snapshot types for the Instant Replay feature.
//!
//! These structs capture a complete, clonable snapshot of terminal state
//! at a point in time, enabling efficient restore for replay navigation.

use std::collections::HashMap;

use crate::badge::SessionVariables;
use crate::cell::{Cell, CellFlags};
use crate::color::Color;
use crate::cursor::Cursor;
use crate::graphics::{GraphicsSnapshot, GraphicsStore, ImageDataRef};
use crate::mouse::{MouseEncoding, MouseMode};
use crate::shell_integration::{Osc633ExpectedNonce, ShellIntegration};
use crate::terminal::{
    PlainTextParserState, SyncUpdateScanState, TerminalInputBufferDiscardReason,
    MAX_SYNCHRONIZED_UPDATE_BYTES, SYNCHRONIZED_UPDATE_CSI_SCAN_LIMIT,
};
use crate::zone::Zone;

use super::block::ItermBlockState;
use super::color_control::Osc21ColorControlState;
use super::context::TerminalContextStack;
use super::graphics::GraphicsPassthroughState;
use super::notification::KittyNotificationState;
use super::osc_stream::OscStreamGate;
use super::pointer_shape::PointerShapeState;
use super::{ITermMultipartState, NamedProgressBar, OscCapabilityPolicy, ProgressBar};

/// Snapshot of a single Grid's state (primary or alternate screen).
#[derive(Clone)]
pub struct GridSnapshot {
    /// Visible screen cells (row-major, cols * rows)
    pub cells: Vec<Cell>,
    /// Scrollback buffer cells (flat, circular buffer linearized)
    pub scrollback_cells: Vec<Cell>,
    /// Start index of the circular scrollback buffer
    pub scrollback_start: usize,
    /// Number of lines currently in scrollback
    pub scrollback_lines: usize,
    /// Maximum scrollback capacity
    pub max_scrollback: usize,
    /// Number of columns
    pub cols: usize,
    /// Number of rows
    pub rows: usize,
    /// Line-wrap flags for visible rows
    pub wrapped: Vec<bool>,
    /// Line-wrap flags for scrollback rows
    pub scrollback_wrapped: Vec<bool>,
    /// Semantic zones
    pub zones: Vec<Zone>,
    /// Total number of lines ever scrolled into scrollback
    pub total_lines_scrolled: usize,
}

impl std::fmt::Debug for GridSnapshot {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let wrapped_rows = self.wrapped.iter().filter(|wrapped| **wrapped).count();
        let scrollback_wrapped_rows = self
            .scrollback_wrapped
            .iter()
            .filter(|wrapped| **wrapped)
            .count();
        formatter
            .debug_struct("GridSnapshot")
            .field("cols", &self.cols)
            .field("rows", &self.rows)
            .field("visible_cell_count", &self.cells.len())
            .field("scrollback_cell_count", &self.scrollback_cells.len())
            .field("scrollback_start", &self.scrollback_start)
            .field("scrollback_lines", &self.scrollback_lines)
            .field("max_scrollback", &self.max_scrollback)
            .field("wrapped_rows", &wrapped_rows)
            .field("scrollback_wrapped_rows", &scrollback_wrapped_rows)
            .field("zone_count", &self.zones.len())
            .field("total_lines_scrolled", &self.total_lines_scrolled)
            .finish()
    }
}

/// Complete snapshot of terminal state at a point in time.
#[derive(Clone)]
pub struct TerminalSnapshot {
    /// Timestamp in Unix milliseconds when this snapshot was captured
    pub timestamp: u64,
    /// Terminal width in columns
    pub cols: usize,
    /// Terminal height in rows
    pub rows: usize,

    // --- Grids ---
    /// Primary screen grid snapshot
    pub grid: GridSnapshot,
    /// Alternate screen grid snapshot
    pub alt_grid: GridSnapshot,
    /// Whether the alternate screen is currently active
    pub alt_screen_active: bool,
    /// Kitty OSC 22 pointer-shape stacks for both screens.
    pub(crate) pointer_shape_state: PointerShapeState,
    /// Primary-screen iTerm2 OSC 1337 block lifecycle and fold state.
    pub(crate) iterm_blocks: ItermBlockState,

    // --- Shell integration lifecycle ---
    /// Validated shell-integration state, including suspended nested lifecycles.
    pub(crate) shell_integration: ShellIntegration,
    /// Next monotonically increasing semantic-zone identifier.
    pub(crate) next_zone_id: usize,
    /// Current shell nesting depth used for sub-shell transition events.
    pub(crate) shell_depth: usize,
    /// Whether terminal output currently belongs to an active command lifecycle.
    pub(crate) in_command_output: bool,

    // --- OSC semantic state ---
    /// Hyperlink URL table referenced by hyperlink IDs stored on cells.
    pub(crate) hyperlinks: HashMap<u32, String>,
    /// OSC 8 protocol identifiers associated with internal hyperlink IDs.
    pub(crate) hyperlink_protocol_ids: HashMap<u32, String>,
    /// Hyperlink applied to newly written cells, if an OSC 8 span is open.
    pub(crate) current_hyperlink_id: Option<u32>,
    /// Next internal hyperlink ID, retained to prevent collisions after restore.
    pub(crate) next_hyperlink_id: u32,
    /// Primary OSC 9;4 progress state.
    pub(crate) progress_bar: ProgressBar,
    /// Named OSC 934 progress state.
    pub(crate) named_progress_bars: HashMap<String, NamedProgressBar>,
    /// Bounded OSC 99 chunk assembly and active identifier state.
    pub(crate) kitty_notification_state: KittyNotificationState,
    /// Bounded UAPI OSC 3008 hierarchy. Contexts survive terminal reset.
    pub(crate) terminal_context_stack: TerminalContextStack,
    /// Bounded ingress parser state retained across split OSC chunks.
    pub(crate) osc_stream_gate: OscStreamGate,
    /// Incremental tmux/screen passthrough decoder state.
    pub(crate) graphics_passthrough_state: GraphicsPassthroughState,
    /// OSC 1337 badge template and its session-scoped interpolation values.
    pub(crate) badge_format: Option<String>,
    pub(crate) session_variables: SessionVariables,
    /// Last identity used for remote-transition de-duplication.
    pub(crate) last_hostname: Option<String>,
    pub(crate) last_username: Option<String>,
    /// Historical parser policy for isolated SnapshotManager reconstruction.
    /// `restore_from_snapshot` deliberately does not apply these fields to an
    /// existing terminal, so replay cannot roll back a newer security deny.
    pub(crate) osc_capability_policy: OscCapabilityPolicy,
    pub(crate) accept_osc7: bool,
    pub(crate) disable_insecure_sequences: bool,
    pub(crate) allow_clipboard_read: bool,
    pub(crate) osc633_expected_nonce: Option<Osc633ExpectedNonce>,
    /// Bounded in-flight inline iTerm2 multipart image state. File-download
    /// transfers are deliberately excluded because they are host capabilities.
    pub(crate) iterm_inline_multipart: Option<ITermMultipartState>,

    // --- Graphics ---
    /// Unified graphics state for Sixel, iTerm2 inline images, and Kitty graphics.
    pub graphics: GraphicsSnapshot,

    // --- Cursors ---
    /// Primary cursor state
    pub cursor: Cursor,
    /// Alternate screen cursor state
    pub alt_cursor: Cursor,
    /// Saved cursor (DECSC/DECRC)
    pub saved_cursor: Option<Cursor>,

    // --- Current colors and attributes ---
    /// Current foreground color
    pub fg: Color,
    /// Current background color
    pub bg: Color,
    /// Current underline color (None = use foreground)
    pub underline_color: Option<Color>,
    /// Current cell attribute flags
    pub flags: CellFlags,

    /// Current dynamic default foreground and its session/profile reset baseline.
    pub default_fg: Color,
    pub baseline_default_fg: Color,
    /// Current dynamic default background and its session/profile reset baseline.
    pub default_bg: Color,
    pub baseline_default_bg: Color,
    /// Current dynamic cursor color and its session/profile reset baseline.
    pub cursor_color: Color,
    pub baseline_cursor_color: Color,
    /// iTerm2 cursor-guide presentation state. Unlike terminal modes this is
    /// session-local UI state and survives RIS until explicitly changed.
    pub cursor_guide_color: Color,
    pub use_cursor_guide: bool,
    /// Current 0-15 palette and its session/profile reset baseline.
    pub ansi_palette: [Color; 16],
    pub baseline_ansi_palette: [Color; 16],
    /// Current 16-255 palette and its session/profile reset baseline.
    pub extended_ansi_palette: [Color; 240],
    pub baseline_extended_ansi_palette: [Color; 240],
    /// Kitty OSC 21 special colors, dynamic values and alpha metadata.
    pub(crate) osc21_color_state: Osc21ColorControlState,

    // --- Saved colors and attributes ---
    /// Saved foreground color
    pub saved_fg: Color,
    /// Saved background color
    pub saved_bg: Color,
    /// Saved underline color
    pub saved_underline_color: Option<Color>,
    /// Saved cell attribute flags
    pub saved_flags: CellFlags,

    // --- Terminal modes and state ---
    /// Terminal title
    pub title: String,
    /// Auto-wrap mode (DECAWM)
    pub auto_wrap: bool,
    /// Origin mode (DECOM)
    pub origin_mode: bool,
    /// Insert mode (IRM)
    pub insert_mode: bool,
    /// Reverse video mode (DECSCNM)
    pub reverse_video: bool,
    /// Line feed / new line mode (LNM)
    pub line_feed_new_line_mode: bool,
    /// Application cursor keys mode
    pub application_cursor: bool,
    /// Bracketed paste mode
    pub bracketed_paste: bool,
    /// Unsolicited OSC 5522 MIME paste notification mode.
    pub mime_paste: bool,
    /// Synchronized update mode (DEC 2026)
    pub(crate) synchronized_updates: bool,
    /// Timestamp when the active synchronized update batch started
    pub(crate) sync_update_started_at: Option<std::time::Instant>,
    /// Buffered output held while synchronized update mode is active
    pub(crate) update_buffer: Vec<u8>,
    /// Possible split DEC 2026 CSI parameters from the previous chunk
    pub(crate) sync_update_scan_tail: Vec<u8>,
    /// Raw scanner state for DEC 2026 outside control string payloads
    pub(crate) sync_update_scan_state: SyncUpdateScanState,
    /// Whether synchronized updates were explicitly disabled during a flush
    pub(crate) sync_update_explicitly_disabled: bool,
    /// Focus tracking mode
    pub focus_tracking: bool,
    /// Alternate-screen focus tracking mode
    pub focus_tracking_alt: bool,
    /// Mouse tracking mode
    pub mouse_mode: MouseMode,
    /// Alternate-screen mouse tracking mode
    pub mouse_mode_alt: MouseMode,
    /// Mouse encoding format
    pub mouse_encoding: MouseEncoding,
    /// Alternate-screen mouse encoding format
    pub mouse_encoding_alt: MouseEncoding,
    /// Alternate scroll mode
    pub alternate_scroll: bool,
    /// Alternate-screen alternate scroll mode
    pub alternate_scroll_alt: bool,
    /// Whether left/right margins are enabled (DECLRMM)
    pub use_lr_margins: bool,
    /// Left margin column (0-indexed)
    pub left_margin: usize,
    /// Right margin column (0-indexed)
    pub right_margin: usize,
    /// Keyboard flags (kitty keyboard protocol)
    pub keyboard_flags: u16,
    /// Alternate-screen keyboard flags (kitty keyboard protocol)
    pub keyboard_flags_alt: u16,
    /// Keyboard protocol flag stack for the primary screen
    pub keyboard_stack: Vec<u16>,
    /// Keyboard protocol flag stack for the alternate screen
    pub keyboard_stack_alt: Vec<u16>,
    /// modifyOtherKeys mode level
    pub modify_other_keys_mode: u8,
    /// Alternate-screen modifyOtherKeys mode level
    pub modify_other_keys_mode_alt: u8,
    /// Character protection attribute (DECSCA)
    pub char_protected: bool,
    /// Whether bold text uses bright colors
    pub bold_brightening: bool,

    // --- Scroll region ---
    /// Scroll region top row (0-indexed)
    pub scroll_region_top: usize,
    /// Scroll region bottom row (0-indexed)
    pub scroll_region_bottom: usize,

    // --- Misc ---
    /// Tab stop positions (one bool per column)
    pub tab_stops: Vec<bool>,
    /// Pending wrap flag (DECAWM delayed wrap)
    pub pending_wrap: bool,
    /// Estimated memory footprint of this snapshot in bytes
    pub estimated_size_bytes: usize,
}

impl std::fmt::Debug for TerminalSnapshot {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let built_in_session_variable_count = [
            self.session_variables.hostname.as_ref(),
            self.session_variables.username.as_ref(),
            self.session_variables.path.as_ref(),
            self.session_variables.job.as_ref(),
            self.session_variables.last_command.as_ref(),
            self.session_variables.profile_name.as_ref(),
            self.session_variables.tty.as_ref(),
            self.session_variables.selection.as_ref(),
            self.session_variables.tmux_pane_title.as_ref(),
            self.session_variables.session_name.as_ref(),
            self.session_variables.title.as_ref(),
        ]
        .into_iter()
        .flatten()
        .count();
        let graphics_item_count = self.graphics.placements.len()
            + self.graphics.scrollback.len()
            + self.graphics.shared_images.len()
            + self.graphics.virtual_placements.len()
            + self.graphics.cleared_kitty_placements.len()
            + self.graphics.deleted_kitty_placements.len()
            + self.graphics.deferred_kitty_deletes.len()
            + self.graphics.animations.len();

        formatter
            .debug_struct("TerminalSnapshot")
            .field("timestamp", &self.timestamp)
            .field("cols", &self.cols)
            .field("rows", &self.rows)
            .field("grid", &self.grid)
            .field("alt_grid", &self.alt_grid)
            .field("alt_screen_active", &self.alt_screen_active)
            .field("shell_state", &self.shell_integration.state())
            .field(
                "has_pending_parent_lifecycle",
                &self.shell_integration.has_pending_parent_lifecycle(),
            )
            .field("shell_depth", &self.shell_depth)
            .field("in_command_output", &self.in_command_output)
            .field("hyperlink_count", &self.hyperlinks.len())
            .field(
                "hyperlink_protocol_id_count",
                &self.hyperlink_protocol_ids.len(),
            )
            .field(
                "has_current_hyperlink",
                &self.current_hyperlink_id.is_some(),
            )
            .field("progress_state", &self.progress_bar.state)
            .field("progress_percent", &self.progress_bar.progress)
            .field("named_progress_count", &self.named_progress_bars.len())
            .field(
                "kitty_notification_retained_bytes",
                &self.kitty_notification_state.retained_bytes(),
            )
            .field(
                "terminal_context_count",
                &self.terminal_context_stack.contexts().len(),
            )
            .field(
                "terminal_context_retained_bytes",
                &self.terminal_context_stack.retained_bytes(),
            )
            .field(
                "osc_ingress_retained_bytes",
                &self.osc_stream_gate.retained_bytes(),
            )
            .field(
                "graphics_passthrough_state",
                &self.graphics_passthrough_state,
            )
            .field(
                "badge_format_bytes",
                &self.badge_format.as_ref().map_or(0, String::len),
            )
            .field(
                "session_variable_count",
                &(built_in_session_variable_count + self.session_variables.custom.len()),
            )
            .field(
                "custom_session_variable_count",
                &self.session_variables.custom.len(),
            )
            .field("has_last_hostname", &self.last_hostname.is_some())
            .field("has_last_username", &self.last_username.is_some())
            .field("osc_capability_policy", &self.osc_capability_policy)
            .field("accept_osc7", &self.accept_osc7)
            .field(
                "disable_insecure_sequences",
                &self.disable_insecure_sequences,
            )
            .field("allow_clipboard_read", &self.allow_clipboard_read)
            .field(
                "osc633_expected_nonce_configured",
                &self.osc633_expected_nonce.is_some(),
            )
            .field(
                "iterm_multipart_retained_bytes",
                &self
                    .iterm_inline_multipart
                    .as_ref()
                    .map_or(0, ITermMultipartState::retained_bytes),
            )
            .field("graphics_item_count", &graphics_item_count)
            .field(
                "graphics_snapshot_bytes",
                &graphics_snapshot_estimate_size(&self.graphics),
            )
            .field("cursor_row", &self.cursor.row)
            .field("cursor_col", &self.cursor.col)
            .field("alt_cursor_row", &self.alt_cursor.row)
            .field("alt_cursor_col", &self.alt_cursor.col)
            .field("title_bytes", &self.title.len())
            .field("synchronized_updates", &self.synchronized_updates)
            .field("update_buffer_bytes", &self.update_buffer.len())
            .field(
                "sync_update_scan_tail_bytes",
                &self.sync_update_scan_tail.len(),
            )
            .field("sync_update_scan_state", &self.sync_update_scan_state)
            .field("keyboard_stack_depth", &self.keyboard_stack.len())
            .field("alt_keyboard_stack_depth", &self.keyboard_stack_alt.len())
            .field(
                "tab_stop_count",
                &self.tab_stops.iter().filter(|stop| **stop).count(),
            )
            .field("estimated_size_bytes", &self.estimated_size_bytes)
            .finish()
    }
}

impl TerminalSnapshot {
    /// Resolve a color through the runtime palette captured with this snapshot.
    pub fn resolve_color_rgb(&self, color: Color) -> (u8, u8, u8) {
        match color {
            Color::Named(named) => self.ansi_palette[named as usize].to_rgb(),
            Color::Indexed(index @ 0..=15) => self.ansi_palette[index as usize].to_rgb(),
            Color::Indexed(index) => self.extended_ansi_palette[index as usize - 16].to_rgb(),
            Color::Rgb(red, green, blue) => (red, green, blue),
        }
    }

    /// Estimate the memory footprint of this snapshot in bytes.
    ///
    /// This is a rough estimate covering the dominant cost centres
    /// (cell Vecs, scrollback, wrapped flags, tab stops, and zones).
    /// Small fixed-size fields are approximated by `size_of::<Self>()`.
    pub fn estimate_size(&self) -> usize {
        let base = std::mem::size_of::<Self>();

        // Grid cells: each Cell owns a Vec<char> for combining chars.
        // Approximate per-cell overhead as size_of::<Cell>() + 24 bytes for the
        // Vec header (pointer + len + cap) even when empty.
        let cell_size = std::mem::size_of::<Cell>();
        let grid_cells = (self.grid.cells.len() + self.grid.scrollback_cells.len()) * cell_size;
        let alt_grid_cells =
            (self.alt_grid.cells.len() + self.alt_grid.scrollback_cells.len()) * cell_size;

        let wrapped_size = self.grid.wrapped.len()
            + self.grid.scrollback_wrapped.len()
            + self.alt_grid.wrapped.len()
            + self.alt_grid.scrollback_wrapped.len();

        let zone_size =
            (self.grid.zones.len() + self.alt_grid.zones.len()) * std::mem::size_of::<Zone>();

        let tab_stops_size = self.tab_stops.len();
        let title_size = self.title.len();
        let keyboard_stack_size = (self.keyboard_stack.len() + self.keyboard_stack_alt.len())
            * std::mem::size_of::<u16>();
        let sync_update_size = self.update_buffer.len() + self.sync_update_scan_tail.len();
        let hyperlink_size = self.hyperlinks.values().map(String::len).sum::<usize>()
            + self
                .hyperlink_protocol_ids
                .values()
                .map(String::len)
                .sum::<usize>();
        let named_progress_size = self
            .named_progress_bars
            .values()
            .map(|progress| progress.id.len() + progress.label.as_ref().map_or(0, String::len))
            .sum::<usize>();
        let kitty_notification_size = self.kitty_notification_state.retained_bytes();
        let terminal_context_size = self.terminal_context_stack.retained_bytes();
        let session_variable_size = self
            .session_variables
            .custom
            .iter()
            .map(|(key, value)| key.len() + value.len())
            .sum::<usize>()
            + [
                self.session_variables.hostname.as_ref(),
                self.session_variables.username.as_ref(),
                self.session_variables.path.as_ref(),
                self.session_variables.job.as_ref(),
                self.session_variables.last_command.as_ref(),
                self.session_variables.profile_name.as_ref(),
                self.session_variables.tty.as_ref(),
                self.session_variables.selection.as_ref(),
                self.session_variables.tmux_pane_title.as_ref(),
                self.session_variables.session_name.as_ref(),
                self.session_variables.title.as_ref(),
            ]
            .into_iter()
            .flatten()
            .map(String::len)
            .sum::<usize>();
        let badge_identity_size = self.badge_format.as_ref().map_or(0, String::len)
            + self.last_hostname.as_ref().map_or(0, String::len)
            + self.last_username.as_ref().map_or(0, String::len)
            + self
                .osc633_expected_nonce
                .as_ref()
                .map_or(0, Osc633ExpectedNonce::len);
        let osc_ingress_size = self.osc_stream_gate.retained_bytes();
        let multipart_size = self
            .iterm_inline_multipart
            .as_ref()
            .map_or(0, ITermMultipartState::retained_bytes);
        let graphics_size = graphics_snapshot_estimate_size(&self.graphics);

        base + grid_cells
            + alt_grid_cells
            + wrapped_size
            + zone_size
            + tab_stops_size
            + title_size
            + keyboard_stack_size
            + sync_update_size
            + hyperlink_size
            + named_progress_size
            + kitty_notification_size
            + terminal_context_size
            + session_variable_size
            + badge_identity_size
            + osc_ingress_size
            + multipart_size
            + graphics_size
    }
}

fn graphics_snapshot_estimate_size(snapshot: &GraphicsSnapshot) -> usize {
    let vector_items = std::mem::size_of_val(snapshot.placements.as_slice())
        + std::mem::size_of_val(snapshot.scrollback.as_slice())
        + std::mem::size_of_val(snapshot.shared_images.as_slice())
        + std::mem::size_of_val(snapshot.virtual_placements.as_slice())
        + std::mem::size_of_val(snapshot.cleared_kitty_placements.as_slice())
        + std::mem::size_of_val(snapshot.deleted_kitty_placements.as_slice())
        + std::mem::size_of_val(snapshot.deferred_kitty_deletes.as_slice())
        + std::mem::size_of_val(snapshot.animations.as_slice());

    let placement_data = snapshot
        .placements
        .iter()
        .chain(snapshot.scrollback.iter())
        .chain(snapshot.virtual_placements.iter())
        .chain(snapshot.cleared_kitty_placements.iter())
        .chain(snapshot.deleted_kitty_placements.iter())
        .map(|graphic| image_data_ref_estimate_size(&graphic.data))
        .sum::<usize>();

    let shared_image_data = snapshot
        .shared_images
        .iter()
        .map(|image| image_data_ref_estimate_size(&image.data))
        .sum::<usize>();

    let animation_data = snapshot
        .animations
        .iter()
        .map(|animation| {
            std::mem::size_of_val(animation.frames.as_slice())
                + animation
                    .frames
                    .iter()
                    .map(|frame| image_data_ref_estimate_size(&frame.data))
                    .sum::<usize>()
        })
        .sum::<usize>();

    vector_items + placement_data + shared_image_data + animation_data
}

fn image_data_ref_estimate_size(data: &ImageDataRef) -> usize {
    match data {
        ImageDataRef::Inline(value) | ImageDataRef::File(value) => value.len(),
    }
}

#[cfg(test)]
fn empty_graphics_snapshot() -> GraphicsSnapshot {
    GraphicsSnapshot::empty_current_version()
}

use crate::terminal::Terminal;

impl Terminal {
    /// Capture a complete snapshot of the current terminal state.
    pub fn capture_snapshot(&self) -> TerminalSnapshot {
        let (cols, rows) = self.size();
        let grid = self.grid.capture_snapshot();
        let alt_grid = self.alt_grid.capture_snapshot();

        let mut snap = TerminalSnapshot {
            timestamp: crate::terminal::unix_millis(),
            cols,
            rows,
            grid,
            alt_grid,
            alt_screen_active: self.alt_screen_active,
            pointer_shape_state: self.pointer_shape_state.clone(),
            iterm_blocks: self.iterm_blocks.clone(),
            shell_integration: self.shell_integration.clone(),
            next_zone_id: self.next_zone_id,
            shell_depth: self.shell_depth,
            in_command_output: self.in_command_output,
            hyperlinks: self.hyperlinks.clone(),
            hyperlink_protocol_ids: self.hyperlink_protocol_ids.clone(),
            current_hyperlink_id: self.current_hyperlink_id,
            next_hyperlink_id: self.next_hyperlink_id,
            progress_bar: self.progress_bar,
            named_progress_bars: self.named_progress_bars.clone(),
            kitty_notification_state: self.kitty_notification_state.clone(),
            terminal_context_stack: self.terminal_context_stack.clone(),
            osc_stream_gate: self.osc_stream_gate.clone(),
            graphics_passthrough_state: self.graphics_passthrough_state,
            badge_format: self.badge_format.clone(),
            session_variables: self.session_variables.clone(),
            last_hostname: self.last_hostname.clone(),
            last_username: self.last_username.clone(),
            osc_capability_policy: self.osc_capability_policy,
            accept_osc7: self.accept_osc7,
            disable_insecure_sequences: self.disable_insecure_sequences,
            allow_clipboard_read: self.allow_clipboard_read,
            osc633_expected_nonce: self.osc633_expected_nonce.clone(),
            iterm_inline_multipart: self
                .iterm_multipart_buffer
                .as_ref()
                .filter(|state| !state.is_file_transfer)
                .cloned(),
            graphics: self.graphics_store.export_snapshot(),
            cursor: self.cursor,
            alt_cursor: self.alt_cursor,
            saved_cursor: self.saved_cursor,
            fg: self.fg,
            bg: self.bg,
            underline_color: self.underline_color,
            flags: self.flags,
            default_fg: self.default_fg,
            baseline_default_fg: self.baseline_default_fg,
            default_bg: self.default_bg,
            baseline_default_bg: self.baseline_default_bg,
            cursor_color: self.cursor_color,
            baseline_cursor_color: self.baseline_cursor_color,
            cursor_guide_color: self.cursor_guide_color,
            use_cursor_guide: self.use_cursor_guide,
            ansi_palette: self.ansi_palette,
            baseline_ansi_palette: self.baseline_ansi_palette,
            extended_ansi_palette: self.extended_ansi_palette,
            baseline_extended_ansi_palette: self.baseline_extended_ansi_palette,
            osc21_color_state: self.osc21_color_state.clone(),
            saved_fg: self.saved_fg,
            saved_bg: self.saved_bg,
            saved_underline_color: self.saved_underline_color,
            saved_flags: self.saved_flags,
            title: self.title.clone(),
            auto_wrap: self.auto_wrap,
            origin_mode: self.origin_mode,
            insert_mode: self.insert_mode,
            reverse_video: self.reverse_video,
            line_feed_new_line_mode: self.line_feed_new_line_mode,
            application_cursor: self.application_cursor,
            bracketed_paste: self.bracketed_paste,
            mime_paste: self.mime_paste,
            synchronized_updates: self.synchronized_updates,
            sync_update_started_at: self.sync_update_started_at,
            update_buffer: self.update_buffer.clone(),
            sync_update_scan_tail: self.sync_update_scan_tail.clone(),
            sync_update_scan_state: self.sync_update_scan_state,
            sync_update_explicitly_disabled: self.sync_update_explicitly_disabled,
            focus_tracking: self.focus_tracking,
            focus_tracking_alt: self.focus_tracking_alt,
            mouse_mode: self.mouse_mode,
            mouse_mode_alt: self.mouse_mode_alt,
            mouse_encoding: self.mouse_encoding,
            mouse_encoding_alt: self.mouse_encoding_alt,
            alternate_scroll: self.alternate_scroll,
            alternate_scroll_alt: self.alternate_scroll_alt,
            use_lr_margins: self.use_lr_margins,
            left_margin: self.left_margin,
            right_margin: self.right_margin,
            keyboard_flags: self.keyboard_flags,
            keyboard_flags_alt: self.keyboard_flags_alt,
            keyboard_stack: self.keyboard_stack.clone(),
            keyboard_stack_alt: self.keyboard_stack_alt.clone(),
            modify_other_keys_mode: self.modify_other_keys_mode,
            modify_other_keys_mode_alt: self.modify_other_keys_mode_alt,
            char_protected: self.char_protected,
            bold_brightening: self.bold_brightening,
            scroll_region_top: self.scroll_region_top,
            scroll_region_bottom: self.scroll_region_bottom,
            tab_stops: self.tab_stops.clone(),
            pending_wrap: self.pending_wrap,
            estimated_size_bytes: 0,
        };
        snap.estimated_size_bytes = snap.estimate_size();
        snap
    }

    /// Restore the terminal state from a previously captured snapshot.
    pub fn restore_from_snapshot(&mut self, mut snap: TerminalSnapshot) {
        // Parser control-string state is intentionally not part of a replay
        // snapshot. Never let an in-flight or already-discarded DCS payload
        // survive a restore and consume bytes from the restored timeline.
        if self.dcs_active || self.dcs_discarding {
            self.parser = vte::Parser::new();
            self.plain_text_parser_state = PlainTextParserState::Ground;
        }
        self.dcs_buffer = Vec::new();
        self.dcs_discarding = false;
        self.dcs_active = false;
        self.dcs_action = None;
        self.sixel_parser = None;

        let invalid_synchronized_update = snap.update_buffer.len() > MAX_SYNCHRONIZED_UPDATE_BYTES
            || snap.sync_update_scan_tail.len() > SYNCHRONIZED_UPDATE_CSI_SCAN_LIMIT;
        if invalid_synchronized_update {
            self.record_input_buffer_discard(
                TerminalInputBufferDiscardReason::SynchronizedUpdateLimit,
            );
            snap.synchronized_updates = false;
            snap.sync_update_started_at = None;
            snap.sync_update_explicitly_disabled = true;
        }
        if !snap.synchronized_updates {
            snap.update_buffer = Vec::new();
            snap.sync_update_scan_tail.clear();
            snap.sync_update_scan_state = SyncUpdateScanState::Ground;
        }

        self.grid.restore_from_snapshot(&snap.grid);
        self.alt_grid.restore_from_snapshot(&snap.alt_grid);
        self.alt_screen_active = snap.alt_screen_active;
        self.pointer_shape_state = snap.pointer_shape_state;
        self.iterm_blocks = snap.iterm_blocks;
        self.shell_integration = snap.shell_integration;
        let minimum_next_zone_id = self
            .grid
            .zones()
            .iter()
            .chain(self.alt_grid.zones())
            .map(|zone| zone.id.saturating_add(1))
            .max()
            .unwrap_or(0);
        self.next_zone_id = snap.next_zone_id.max(minimum_next_zone_id);
        self.shell_depth = snap.shell_depth;
        self.in_command_output = snap.in_command_output;
        self.hyperlinks = snap.hyperlinks;
        self.hyperlink_protocol_ids = snap.hyperlink_protocol_ids;
        self.current_hyperlink_id = snap.current_hyperlink_id;
        let minimum_next_hyperlink_id = self
            .hyperlinks
            .keys()
            .chain(self.hyperlink_protocol_ids.keys())
            .copied()
            .max()
            .map_or(0, |id| id.saturating_add(1));
        self.next_hyperlink_id = snap.next_hyperlink_id.max(minimum_next_hyperlink_id);
        self.progress_bar = snap.progress_bar;
        self.named_progress_bars = snap.named_progress_bars;
        self.kitty_notification_state = snap.kitty_notification_state;
        self.terminal_context_stack = snap.terminal_context_stack;
        self.osc_stream_gate = snap.osc_stream_gate;
        self.graphics_passthrough_state = snap.graphics_passthrough_state;
        self.badge_format = snap.badge_format;
        self.session_variables = snap.session_variables;
        self.last_hostname = snap.last_hostname;
        self.last_username = snap.last_username;
        self.iterm_multipart_buffer = snap.iterm_inline_multipart;
        let graphics_limits = *self.graphics_store.limits();
        let mut restored_graphics = GraphicsStore::with_limits(graphics_limits);
        if let Err(error) = restored_graphics.import_snapshot(&snap.graphics) {
            crate::debug::log(
                crate::debug::DebugLevel::Info,
                "SNAPSHOT",
                &format!("Failed to restore graphics snapshot: {}", error),
            );
            restored_graphics = GraphicsStore::with_limits(graphics_limits);
        }
        self.graphics_store = restored_graphics;
        self.cursor = snap.cursor;
        self.alt_cursor = snap.alt_cursor;
        self.saved_cursor = snap.saved_cursor;
        self.fg = snap.fg;
        self.bg = snap.bg;
        self.underline_color = snap.underline_color;
        self.flags = snap.flags;
        self.default_fg = snap.default_fg;
        self.baseline_default_fg = snap.baseline_default_fg;
        self.default_bg = snap.default_bg;
        self.baseline_default_bg = snap.baseline_default_bg;
        self.cursor_color = snap.cursor_color;
        self.baseline_cursor_color = snap.baseline_cursor_color;
        self.cursor_guide_color = snap.cursor_guide_color;
        self.use_cursor_guide = snap.use_cursor_guide;
        self.ansi_palette = snap.ansi_palette;
        self.baseline_ansi_palette = snap.baseline_ansi_palette;
        self.extended_ansi_palette = snap.extended_ansi_palette;
        self.baseline_extended_ansi_palette = snap.baseline_extended_ansi_palette;
        self.osc21_color_state = snap.osc21_color_state;
        self.sync_grid_blank_style();
        self.saved_fg = snap.saved_fg;
        self.saved_bg = snap.saved_bg;
        self.saved_underline_color = snap.saved_underline_color;
        self.saved_flags = snap.saved_flags;
        self.title = snap.title;
        self.auto_wrap = snap.auto_wrap;
        self.origin_mode = snap.origin_mode;
        self.insert_mode = snap.insert_mode;
        self.reverse_video = snap.reverse_video;
        self.line_feed_new_line_mode = snap.line_feed_new_line_mode;
        self.application_cursor = snap.application_cursor;
        self.bracketed_paste = snap.bracketed_paste;
        self.mime_paste = snap.mime_paste;
        self.synchronized_updates = snap.synchronized_updates;
        self.sync_update_started_at = snap.sync_update_started_at;
        self.update_buffer = snap.update_buffer;
        self.sync_update_scan_tail = snap.sync_update_scan_tail;
        self.sync_update_scan_state = snap.sync_update_scan_state;
        self.sync_update_explicitly_disabled = snap.sync_update_explicitly_disabled;
        self.suppress_synchronized_update_enable = false;
        self.sync_update_report_override = None;
        self.focus_tracking = snap.focus_tracking;
        self.focus_tracking_alt = snap.focus_tracking_alt;
        self.mouse_mode = snap.mouse_mode;
        self.mouse_mode_alt = snap.mouse_mode_alt;
        self.mouse_encoding = snap.mouse_encoding;
        self.mouse_encoding_alt = snap.mouse_encoding_alt;
        self.alternate_scroll = snap.alternate_scroll;
        self.alternate_scroll_alt = snap.alternate_scroll_alt;
        self.use_lr_margins = snap.use_lr_margins;
        self.left_margin = snap.left_margin;
        self.right_margin = snap.right_margin;
        self.keyboard_flags = snap.keyboard_flags;
        self.keyboard_flags_alt = snap.keyboard_flags_alt;
        self.keyboard_stack = snap.keyboard_stack;
        self.keyboard_stack_alt = snap.keyboard_stack_alt;
        self.modify_other_keys_mode = snap.modify_other_keys_mode;
        self.modify_other_keys_mode_alt = snap.modify_other_keys_mode_alt;
        self.char_protected = snap.char_protected;
        self.bold_brightening = snap.bold_brightening;
        self.scroll_region_top = snap.scroll_region_top;
        self.scroll_region_bottom = snap.scroll_region_bottom;
        self.tab_stops = snap.tab_stops;
        self.pending_wrap = snap.pending_wrap;
        self.mark_full_repaint("restore_from_snapshot");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cell::CellFlags;
    use crate::color::{Color, NamedColor};
    use crate::cursor::Cursor;
    use crate::shell_integration::ShellIntegrationState;
    use crate::zone::ZoneType;

    fn make_grid_snapshot(cols: usize, rows: usize) -> GridSnapshot {
        GridSnapshot {
            cells: vec![Cell::default(); cols * rows],
            scrollback_cells: Vec::new(),
            scrollback_start: 0,
            scrollback_lines: 0,
            max_scrollback: 1000,
            cols,
            rows,
            wrapped: vec![false; rows],
            scrollback_wrapped: Vec::new(),
            zones: Vec::new(),
            total_lines_scrolled: 0,
        }
    }

    fn make_terminal_snapshot(cols: usize, rows: usize) -> TerminalSnapshot {
        let grid = make_grid_snapshot(cols, rows);
        let alt_grid = make_grid_snapshot(cols, rows);

        let mut snap = TerminalSnapshot {
            timestamp: 1_700_000_000_000,
            cols,
            rows,
            grid,
            alt_grid,
            alt_screen_active: false,
            pointer_shape_state: PointerShapeState::default(),
            iterm_blocks: ItermBlockState::default(),
            shell_integration: ShellIntegration::new(),
            next_zone_id: 0,
            shell_depth: 0,
            in_command_output: false,
            hyperlinks: HashMap::new(),
            hyperlink_protocol_ids: HashMap::new(),
            current_hyperlink_id: None,
            next_hyperlink_id: 0,
            progress_bar: ProgressBar::default(),
            named_progress_bars: HashMap::new(),
            kitty_notification_state: KittyNotificationState::default(),
            terminal_context_stack: TerminalContextStack::default(),
            osc_stream_gate: OscStreamGate::default(),
            graphics_passthrough_state: GraphicsPassthroughState::default(),
            badge_format: None,
            session_variables: SessionVariables::with_dimensions(cols as u16, rows as u16),
            last_hostname: None,
            last_username: None,
            osc_capability_policy: OscCapabilityPolicy::default(),
            accept_osc7: true,
            disable_insecure_sequences: false,
            allow_clipboard_read: false,
            osc633_expected_nonce: None,
            iterm_inline_multipart: None,
            graphics: empty_graphics_snapshot(),
            cursor: Cursor::default(),
            alt_cursor: Cursor::default(),
            saved_cursor: None,
            fg: Color::Named(NamedColor::White),
            bg: Color::Named(NamedColor::Black),
            underline_color: None,
            flags: CellFlags::default(),
            default_fg: Color::Named(NamedColor::White),
            baseline_default_fg: Color::Named(NamedColor::White),
            default_bg: Color::Named(NamedColor::Black),
            baseline_default_bg: Color::Named(NamedColor::Black),
            cursor_color: Color::Named(NamedColor::White),
            baseline_cursor_color: Color::Named(NamedColor::White),
            cursor_guide_color: Color::Rgb(0xa6, 0xe8, 0xff),
            use_cursor_guide: false,
            ansi_palette: Terminal::default_ansi_palette(),
            baseline_ansi_palette: Terminal::default_ansi_palette(),
            extended_ansi_palette: Terminal::default_extended_ansi_palette(),
            baseline_extended_ansi_palette: Terminal::default_extended_ansi_palette(),
            osc21_color_state: Osc21ColorControlState::default(),
            saved_fg: Color::Named(NamedColor::White),
            saved_bg: Color::Named(NamedColor::Black),
            saved_underline_color: None,
            saved_flags: CellFlags::default(),
            title: String::new(),
            auto_wrap: true,
            origin_mode: false,
            insert_mode: false,
            reverse_video: false,
            line_feed_new_line_mode: false,
            application_cursor: false,
            bracketed_paste: false,
            mime_paste: false,
            synchronized_updates: false,
            sync_update_started_at: None,
            update_buffer: Vec::new(),
            sync_update_scan_tail: Vec::new(),
            sync_update_scan_state: SyncUpdateScanState::Ground,
            sync_update_explicitly_disabled: false,
            focus_tracking: false,
            focus_tracking_alt: false,
            mouse_mode: MouseMode::Off,
            mouse_mode_alt: MouseMode::Off,
            mouse_encoding: MouseEncoding::Default,
            mouse_encoding_alt: MouseEncoding::Default,
            alternate_scroll: false,
            alternate_scroll_alt: false,
            use_lr_margins: false,
            left_margin: 0,
            right_margin: cols.saturating_sub(1),
            keyboard_flags: 0,
            keyboard_flags_alt: 0,
            keyboard_stack: Vec::new(),
            keyboard_stack_alt: Vec::new(),
            modify_other_keys_mode: 0,
            modify_other_keys_mode_alt: 0,
            char_protected: false,
            bold_brightening: true,
            scroll_region_top: 0,
            scroll_region_bottom: rows.saturating_sub(1),
            tab_stops: vec![false; cols],
            pending_wrap: false,
            estimated_size_bytes: 0,
        };
        snap.estimated_size_bytes = snap.estimate_size();
        snap
    }

    #[test]
    fn test_terminal_snapshot_creation() {
        let snap = make_terminal_snapshot(80, 24);
        assert_eq!(snap.cols, 80);
        assert_eq!(snap.rows, 24);
        assert_eq!(snap.grid.cells.len(), 80 * 24);
        assert_eq!(snap.alt_grid.cells.len(), 80 * 24);
        assert!(!snap.alt_screen_active);
        assert_eq!(snap.cursor, Cursor::default());
        assert_eq!(snap.fg, Color::Named(NamedColor::White));
        assert_eq!(snap.bg, Color::Named(NamedColor::Black));
    }

    #[test]
    fn test_terminal_snapshot_clone() {
        let snap = make_terminal_snapshot(80, 24);
        let cloned = snap.clone();
        assert_eq!(cloned.cols, snap.cols);
        assert_eq!(cloned.rows, snap.rows);
        assert_eq!(cloned.timestamp, snap.timestamp);
        assert_eq!(cloned.grid.cells.len(), snap.grid.cells.len());
        assert_eq!(cloned.alt_grid.cells.len(), snap.alt_grid.cells.len());
        assert_eq!(cloned.cursor, snap.cursor);
        assert_eq!(cloned.fg, snap.fg);
        assert_eq!(cloned.bg, snap.bg);
    }

    #[test]
    fn test_terminal_snapshot_size_estimation() {
        let snap = make_terminal_snapshot(80, 24);
        let size = snap.estimate_size();
        // Should be at least the size of the cell data
        let min_cells = 80 * 24 * 2 * std::mem::size_of::<Cell>();
        assert!(
            size >= min_cells,
            "estimated size {size} should be >= cell data size {min_cells}"
        );
        assert_eq!(snap.estimated_size_bytes, size);
    }

    #[test]
    fn test_terminal_snapshot_with_scrollback() {
        let mut grid = make_grid_snapshot(80, 24);
        grid.scrollback_cells = vec![Cell::default(); 80 * 100];
        grid.scrollback_lines = 100;

        let mut snap = make_terminal_snapshot(80, 24);
        snap.grid = grid;
        snap.estimated_size_bytes = snap.estimate_size();

        // Scrollback should increase the estimated size
        let no_scrollback_snap = make_terminal_snapshot(80, 24);
        assert!(
            snap.estimated_size_bytes > no_scrollback_snap.estimated_size_bytes,
            "snapshot with scrollback should be larger"
        );
    }

    #[test]
    fn test_terminal_snapshot_with_colored_cells() {
        let mut snap = make_terminal_snapshot(10, 5);
        // Set some cells to have non-default colors
        snap.grid.cells[0] = Cell::with_colors('A', Color::Rgb(255, 0, 0), Color::Rgb(0, 0, 255));
        snap.grid.cells[1] =
            Cell::with_colors('B', Color::Indexed(196), Color::Named(NamedColor::Green));

        let cloned = snap.clone();
        assert_eq!(cloned.grid.cells[0].c, 'A');
        assert_eq!(cloned.grid.cells[0].fg, Color::Rgb(255, 0, 0));
        assert_eq!(cloned.grid.cells[0].bg, Color::Rgb(0, 0, 255));
        assert_eq!(cloned.grid.cells[1].c, 'B');
        assert_eq!(cloned.grid.cells[1].fg, Color::Indexed(196));
        assert_eq!(cloned.grid.cells[1].bg, Color::Named(NamedColor::Green));
    }

    #[test]
    fn restore_preserves_runtime_colors_baselines_palette_and_default_provenance() {
        let mut term = Terminal::new(8, 2);
        let baseline_fg = Color::Rgb(1, 2, 3);
        let baseline_bg = Color::Rgb(4, 5, 6);
        let baseline_cursor = Color::Rgb(7, 8, 9);
        let baseline_196 = Color::Rgb(10, 11, 12);
        term.set_default_fg(baseline_fg);
        term.set_default_bg(baseline_bg);
        term.set_cursor_color(baseline_cursor);
        term.set_ansi_palette_color(196, baseline_196).unwrap();
        term.process(b"\x1b]10;#111213\x1b\\\x1b]11;#212223\x1b\\");
        term.process(b"\x1b]12;#313233\x1b\\\x1b]4;196;#414243\x1b\\");
        term.process(b"A\x1b[38;2;17;18;19;48;2;33;34;35mB\x1b[0m");
        term.process(b"\x1b[38;5;196mC\x1b[0m");
        let snapshot = term.capture_snapshot();

        term.process(b"\x1b]10;#515253\x1b\\\x1b]11;#616263\x1b\\");
        term.process(b"\x1b]12;#717273\x1b\\\x1b]4;196;#818283\x1b\\");
        term.restore_from_snapshot(snapshot);

        assert_eq!(term.default_fg(), Color::Rgb(0x11, 0x12, 0x13));
        assert_eq!(term.default_bg(), Color::Rgb(0x21, 0x22, 0x23));
        assert_eq!(term.cursor_color(), Color::Rgb(0x31, 0x32, 0x33));
        assert_eq!(term.get_ansi_color(196), Some(Color::Rgb(0x41, 0x42, 0x43)));
        assert_eq!(
            term.resolve_color_rgb(term.active_grid().row(0).unwrap()[2].fg),
            (0x41, 0x42, 0x43)
        );

        term.process(b"\x1b]10;#919293\x1b\\\x1b]11;#a1a2a3\x1b\\");
        let row = term.active_grid().row(0).unwrap();
        assert_eq!(row[0].fg, Color::Rgb(0x91, 0x92, 0x93));
        assert_eq!(row[0].bg, Color::Rgb(0xa1, 0xa2, 0xa3));
        assert_eq!(row[1].fg, Color::Rgb(0x11, 0x12, 0x13));
        assert_eq!(row[1].bg, Color::Rgb(0x21, 0x22, 0x23));

        term.process(b"\x1b]104;196\x1b\\\x1b]110\x1b\\\x1b]111\x1b\\\x1b]112\x1b\\");
        assert_eq!(term.default_fg(), baseline_fg);
        assert_eq!(term.default_bg(), baseline_bg);
        assert_eq!(term.cursor_color(), baseline_cursor);
        assert_eq!(term.get_ansi_color(196), Some(baseline_196));
    }

    #[test]
    fn restore_preserves_iterm_cursor_guide_state_and_color() {
        let mut terminal = Terminal::new(8, 2);
        terminal.set_cursor_guide_color(Color::Rgb(0x12, 0x34, 0x56));
        terminal.process(b"\x1b]1337;HighlightCursorLine=yes\x07");
        let snapshot = terminal.capture_snapshot();

        terminal.set_cursor_guide_color(Color::Rgb(0xaa, 0xbb, 0xcc));
        terminal.process(b"\x1b]1337;HighlightCursorLine=no\x07");
        terminal.restore_from_snapshot(snapshot);

        assert!(terminal.use_cursor_guide());
        assert_eq!(terminal.cursor_guide_color(), Color::Rgb(0x12, 0x34, 0x56));
        terminal.reset();
        assert!(terminal.use_cursor_guide());
    }

    #[test]
    fn restore_mid_output_accepts_finish_and_keeps_zone_ids_unique() {
        let mut source = Terminal::new(40, 4);
        source.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;snapshot-command\x07");
        source.process(b"partial output");
        let output_id = source
            .get_zones()
            .iter()
            .find(|zone| zone.zone_type == ZoneType::Output)
            .expect("open output zone before snapshot")
            .id;
        let expected_next_zone_id = source.next_zone_id;
        let snapshot = source.capture_snapshot();

        let mut restored = Terminal::new(1, 1);
        restored.restore_from_snapshot(snapshot);
        assert_eq!(
            restored.shell_integration.state(),
            ShellIntegrationState::CommandOutput
        );
        assert!(restored.in_command_output);
        assert_eq!(restored.next_zone_id, expected_next_zone_id);

        restored.process(b"\x1b]133;D;17\x07");
        let output = restored
            .get_zones()
            .iter()
            .find(|zone| zone.id == output_id)
            .expect("restored output zone");
        assert!(output.is_closed());
        assert_eq!(output.exit_code, Some(17));
        assert_eq!(
            restored.shell_integration.state(),
            ShellIntegrationState::Finished
        );
        assert!(!restored.in_command_output);

        restored.process(b"\x1b]133;A\x07");
        let new_zone_id = restored.get_zones().last().expect("new prompt zone").id;
        assert_eq!(new_zone_id, expected_next_zone_id);
        let unique_ids = restored
            .get_zones()
            .iter()
            .map(|zone| zone.id)
            .collect::<std::collections::HashSet<_>>();
        assert_eq!(unique_ids.len(), restored.get_zones().len());
    }

    #[test]
    fn restore_preserves_hyperlink_identity_and_progress_state() {
        let mut source = Terminal::new(40, 4);
        source.process(b"\x1b]8;id=first;https://example.test/first\x1b\\A");
        let first_id = source.active_grid().row(0).unwrap()[0]
            .flags
            .hyperlink_id
            .expect("first hyperlink ID");
        source.process(b"\x1b]9;4;1;45\x1b\\");
        source.process(b"\x1b]934;set;build;percent=73;label=Compiling\x1b\\");

        let mut restored = Terminal::new(1, 1);
        restored.restore_from_snapshot(source.capture_snapshot());

        assert_eq!(
            restored.get_hyperlink_url(first_id).as_deref(),
            Some("https://example.test/first")
        );
        assert_eq!(
            restored.get_hyperlink_protocol_id(first_id).as_deref(),
            Some("first")
        );
        assert_eq!(restored.current_hyperlink_id, Some(first_id));
        assert_eq!(
            restored.progress_state(),
            crate::terminal::ProgressState::Normal
        );
        assert_eq!(restored.progress_value(), 45);
        let named = restored
            .get_named_progress_bar("build")
            .expect("restored named progress");
        assert_eq!(named.percent, 73);
        assert_eq!(named.label.as_deref(), Some("Compiling"));

        restored.process(b"B\x1b]8;;\x1b\\\x1b]8;id=second;https://example.test/second\x1b\\C");
        let row = restored.active_grid().row(0).unwrap();
        assert_eq!(row[1].flags.hyperlink_id, Some(first_id));
        let second_id = row[2].flags.hyperlink_id.expect("second hyperlink ID");
        assert_ne!(second_id, first_id);
        assert_eq!(
            restored.get_hyperlink_protocol_id(second_id).as_deref(),
            Some("second")
        );
    }

    #[test]
    fn restore_continues_split_osc_and_passthrough_without_changing_policy() {
        let mut direct = Terminal::new(40, 4);
        direct.process(b"\x1b]2;split");
        let mut restored_direct = Terminal::new(1, 1);
        restored_direct.restore_from_snapshot(direct.capture_snapshot());
        restored_direct.process(b" title\x1b\\");
        assert_eq!(restored_direct.title(), "split title");

        let mut denied = Terminal::new(40, 4);
        denied.set_allow_clipboard_read(true);
        assert!(denied.set_osc633_expected_nonce(Some("historical-nonce".to_string())));
        denied.process(b"\x1b]2;blocked");
        let denied_snapshot = denied.capture_snapshot();
        assert!(!format!("{denied_snapshot:?}").contains("historical-nonce"));
        let mut restored_denied = Terminal::new(1, 1);
        restored_denied
            .set_osc_capability_allowed(crate::terminal::OscCapability::Appearance, false);
        restored_denied.set_accept_osc7(false);
        restored_denied.set_disable_insecure_sequences(true);
        restored_denied.set_allow_clipboard_read(false);
        assert!(restored_denied.set_osc633_expected_nonce(Some("current-nonce".to_string())));
        restored_denied.restore_from_snapshot(denied_snapshot);
        restored_denied.process(b" title\x1b\\");
        assert_eq!(restored_denied.title(), "");
        assert!(!restored_denied.allow_clipboard_read());
        assert!(!restored_denied.accept_osc7());
        assert!(restored_denied.disable_insecure_sequences());
        restored_denied.process(b"\x1b]633;E;old;historical-nonce\x1b\\");
        assert_eq!(restored_denied.shell_integration.command(), None);
        restored_denied.process(b"\x1b]633;E;new;current-nonce\x1b\\");
        assert_eq!(restored_denied.shell_integration.command(), Some("new"));
        assert_eq!(
            restored_denied
                .osc_ingress_diagnostics()
                .for_intent(crate::terminal::OscIntent::Appearance)
                .policy_denied,
            1
        );

        let mut tmux = Terminal::new(40, 4);
        tmux.process(b"\x1bPtm");
        let mut restored_tmux = Terminal::new(1, 1);
        restored_tmux.restore_from_snapshot(tmux.capture_snapshot());
        restored_tmux.process(b"ux;\x1b\x1b]2;tmux title\x1b\x1b\\\x1b\\");
        assert_eq!(restored_tmux.title(), "tmux title");

        let mut screen = Terminal::new(40, 4);
        screen.process(b"\x1bP");
        let mut restored_screen = Terminal::new(1, 1);
        restored_screen.restore_from_snapshot(screen.capture_snapshot());
        restored_screen.process(b"\x1b]2;screen title\x07\x1b\\");
        assert_eq!(restored_screen.title(), "screen title");
    }

    #[test]
    fn restore_rejects_legacy_oversized_synchronized_update_buffer() {
        let mut snapshot = make_terminal_snapshot(80, 24);
        snapshot.synchronized_updates = true;
        snapshot.sync_update_started_at = Some(std::time::Instant::now());
        snapshot.update_buffer = vec![b'x'; MAX_SYNCHRONIZED_UPDATE_BYTES + 1];
        snapshot.sync_update_scan_tail = b"?2026".to_vec();
        snapshot.sync_update_scan_state = SyncUpdateScanState::Csi;

        let mut restored = Terminal::new(80, 24);
        restored.restore_from_snapshot(snapshot);

        assert!(!restored.synchronized_updates);
        assert!(restored.update_buffer.is_empty());
        assert!(restored.sync_update_scan_tail.is_empty());
        assert_eq!(restored.sync_update_scan_state, SyncUpdateScanState::Ground);
        assert_eq!(
            restored
                .input_buffer_diagnostics()
                .count(TerminalInputBufferDiscardReason::SynchronizedUpdateLimit),
            1
        );
        let sanitized = restored.capture_snapshot();
        assert!(!sanitized.synchronized_updates);
        assert!(sanitized.update_buffer.is_empty());

        restored.process(b"recovered");
        assert_eq!(restored.active_grid().row_text(0).trim_end(), "recovered");
    }

    #[test]
    fn restore_preserves_badge_user_variables_and_remote_transition_identity() {
        let mut source = Terminal::new(40, 4);
        source.process(b"\x1b]7;file://alice@remote.example/tmp/work\x07");
        source.process(b"\x1b]1337;SetUserVar=IANVS_BUILD=cmVhZHk=\x07");
        source.set_badge_format(Some(r"\(username)@\(hostname):\(IANVS_BUILD)".to_string()));
        assert_eq!(
            source.evaluate_badge().as_deref(),
            Some("alice@remote.example:ready")
        );

        let mut restored = Terminal::new(1, 1);
        restored.restore_from_snapshot(source.capture_snapshot());
        assert_eq!(
            restored.evaluate_badge().as_deref(),
            Some("alice@remote.example:ready")
        );
        assert_eq!(
            restored.session_variables().custom.get("IANVS_BUILD"),
            Some(&"ready".to_string())
        );

        let _ = restored.poll_events();
        restored.process(b"\x1b]7;file://alice@remote.example/tmp/next\x07");
        let remote_transitions = restored
            .poll_events()
            .into_iter()
            .filter(|event| {
                matches!(
                    event,
                    crate::terminal::TerminalEvent::RemoteHostTransition { .. }
                )
            })
            .count();
        assert_eq!(remote_transitions, 0);
    }

    #[test]
    fn restore_continues_inline_iterm_multipart_image_without_restoring_file_transfer() {
        use base64::{engine::general_purpose::STANDARD, Engine};

        let image = image::RgbaImage::from_pixel(1, 1, image::Rgba([255, 0, 0, 255]));
        let mut png = Vec::new();
        image
            .write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)
            .expect("test PNG");
        let encoded = STANDARD.encode(png);
        let (first, rest) = encoded.split_at(5);

        let mut source = Terminal::new(40, 4);
        source.process(b"\x1b]1337;MultipartFile=inline=1;name=cGl4ZWwucG5n\x1b\\");
        source.process(format!("\x1b]1337;FilePart={first}\x1b\\").as_bytes());
        assert!(source.iterm_multipart_buffer.is_some());

        let mut restored = Terminal::new(1, 1);
        restored.restore_from_snapshot(source.capture_snapshot());
        restored.process(format!("\x1b]1337;FilePart={rest}\x1b\\").as_bytes());
        restored.process(b"\x1b]1337;FileEnd\x1b\\");
        assert_eq!(restored.graphics_count(), 1);
        assert_eq!(restored.all_graphics()[0].protocol.as_str(), "iterm");

        source.iterm_multipart_buffer = Some(ITermMultipartState {
            is_file_transfer: true,
            transfer_id: Some(99),
            ..ITermMultipartState::default()
        });
        let mut isolated = Terminal::new(1, 1);
        isolated.restore_from_snapshot(source.capture_snapshot());
        assert!(isolated.iterm_multipart_buffer.is_none());
    }

    #[test]
    fn restore_nested_pending_lifecycle_finishes_outer_command() {
        let mut source = Terminal::new(40, 4);
        source.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;outer\x07");
        source.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;inner\x07");
        source.process(b"\x1b]133;D;2\x07");
        assert_eq!(source.shell_integration.suspended_lifecycle_count(), 1);
        assert_eq!(source.shell_depth, 2);
        assert!(source.in_command_output);
        assert!(source.get_zones().iter().all(|zone| zone.is_closed()));
        let resumed_output_id = source.next_zone_id;

        let mut restored = Terminal::new(1, 1);
        restored.restore_from_snapshot(source.capture_snapshot());
        assert_eq!(restored.shell_integration.suspended_lifecycle_count(), 1);
        assert_eq!(restored.shell_depth, 2);
        assert!(restored.in_command_output);

        restored.process(b"\x1b]133;D;9\x07");
        assert_eq!(restored.shell_integration.suspended_lifecycle_count(), 0);
        assert_eq!(restored.shell_depth, 1);
        assert!(!restored.in_command_output);
        assert_eq!(restored.shell_integration.command(), Some("outer"));
        assert_eq!(restored.shell_integration.exit_code(), Some(9));
        let resumed_output = restored
            .get_zones()
            .iter()
            .find(|zone| zone.id == resumed_output_id)
            .expect("restored resumed output zone");
        assert!(resumed_output.is_closed());
        assert_eq!(resumed_output.exit_code, Some(9));

        restored.process(b"\x1b]133;A\x07");
        assert_eq!(
            restored.get_zones().last().expect("new prompt zone").id,
            resumed_output_id + 1
        );
    }

    #[test]
    fn terminal_and_snapshot_debug_output_redact_terminal_content() {
        let mut terminal = Terminal::new(20, 4);
        terminal.process("🕵".as_bytes());
        terminal
            .shell_integration_mut()
            .set_command("command-secret-canary".to_string());
        terminal
            .shell_integration_mut()
            .set_cwd("/cwd-secret-canary".to_string());
        terminal
            .shell_integration_mut()
            .set_hostname(Some("host-secret-canary".to_string()));
        terminal
            .shell_integration_mut()
            .set_username(Some("user-secret-canary".to_string()));
        terminal.session_variables_mut().set_custom(
            "variable-name-secret-canary",
            "variable-value-secret-canary",
        );
        terminal.set_badge_format(Some("badge-secret-canary".to_string()));
        terminal.process(
            b"\x1b]8;id=hyperlink-id-secret-canary;https://url-secret-canary.invalid\x1b\\",
        );
        terminal.process(
            b"\x1b]934;set;progress-id-secret-canary;percent=50;label=progress-label-secret-canary\x1b\\",
        );
        assert!(terminal.set_osc633_expected_nonce(Some("nonce-secret-canary".to_string())));

        let terminal_debug = format!("{terminal:?}");
        let session_variables_debug = format!("{:?}", terminal.session_variables());
        let snapshot = terminal.capture_snapshot();
        let grid_debug = format!("{:?}", snapshot.grid);
        let snapshot_debug = format!("{snapshot:?}");
        for secret in [
            "🕵",
            "command-secret-canary",
            "/cwd-secret-canary",
            "host-secret-canary",
            "user-secret-canary",
            "variable-name-secret-canary",
            "variable-value-secret-canary",
            "badge-secret-canary",
            "hyperlink-id-secret-canary",
            "url-secret-canary",
            "progress-id-secret-canary",
            "progress-label-secret-canary",
            "nonce-secret-canary",
        ] {
            assert!(
                !terminal_debug.contains(secret),
                "Terminal Debug leaked {secret}"
            );
            assert!(
                !grid_debug.contains(secret),
                "GridSnapshot Debug leaked {secret}"
            );
            assert!(
                !snapshot_debug.contains(secret),
                "TerminalSnapshot Debug leaked {secret}"
            );
            assert!(
                !session_variables_debug.contains(secret),
                "SessionVariables Debug leaked {secret}"
            );
        }
        assert!(terminal_debug.contains("update_buffer_bytes"));
        assert!(grid_debug.contains("visible_cell_count"));
        assert!(snapshot_debug.contains("custom_session_variable_count: 1"));
        assert!(snapshot_debug.contains("osc633_expected_nonce_configured: true"));
        assert!(session_variables_debug.contains("custom_count: 1"));
    }

    #[test]
    fn test_grid_snapshot_creation() {
        let gs = make_grid_snapshot(120, 40);
        assert_eq!(gs.cols, 120);
        assert_eq!(gs.rows, 40);
        assert_eq!(gs.cells.len(), 120 * 40);
        assert_eq!(gs.wrapped.len(), 40);
        assert_eq!(gs.scrollback_cells.len(), 0);
        assert_eq!(gs.scrollback_lines, 0);
        assert_eq!(gs.max_scrollback, 1000);
        assert_eq!(gs.total_lines_scrolled, 0);
    }

    #[test]
    fn test_grid_snapshot_with_zones() {
        let mut gs = make_grid_snapshot(80, 24);
        gs.zones.push(Zone::new(
            1,
            crate::zone::ZoneType::Prompt,
            0,
            Some(1_700_000_000_000),
        ));
        gs.zones.push(Zone::new(
            2,
            crate::zone::ZoneType::Command,
            1,
            Some(1_700_000_000_001),
        ));
        assert_eq!(gs.zones.len(), 2);

        let cloned = gs.clone();
        assert_eq!(cloned.zones.len(), 2);
        assert_eq!(cloned.zones[0].id, 1);
        assert_eq!(cloned.zones[1].id, 2);
    }
}
