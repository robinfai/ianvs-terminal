use super::*;
use crate::recording::{RecordedAsset, StorageError, StorageResult};

pub(super) struct NativeCaptureSnapshot {
    pub frame: crate::proto::frame_diff::TerminalFrameDiff,
    pub assets: Vec<RecordedAsset>,
}

impl TerminalSession {
    /// A separate complete view: does not drain UI damage, frame acknowledgements
    /// or row caches. Hidden/unpolled sessions are sampled from native state.
    pub(super) fn recording_snapshot(&self) -> StorageResult<Option<NativeCaptureSnapshot>> {
        let mut state = self.state.lock();
        let cursor_before = terminal_cursor_snapshot(&state.terminal, state.terminal.cursor());
        if state.terminal.flush_synchronized_updates_if_timed_out() {
            let damage = state.terminal.drain_active_screen_damage();
            let cursor_after = terminal_cursor_snapshot(&state.terminal, state.terminal.cursor());
            self.pending_frame_signal.mutate_reader(|work| {
                work.merge_terminal_damage(damage, cursor_before, cursor_after);
            });
        }
        if self.graphics_enabled
            && !state.terminal.synchronized_updates()
            && !state.terminal.kitty_graphics_transfer_in_progress()
            && !state.terminal.update_animations().is_empty()
        {
            self.pending_frame_signal.mutate_reader(|_| {});
        }
        let alt_screen_active = state.terminal.is_alt_screen_active();
        let scrollback_max_offset = current_scrollback_max(&state);
        if state.terminal.synchronized_updates()
            || state.terminal.kitty_graphics_transfer_in_progress()
        {
            return Ok(None);
        }
        if alt_screen_active {
            state.scrollback_offset = 0;
        } else {
            state.scrollback_offset = state.scrollback_offset.min(scrollback_max_offset);
        }
        let terminal = &state.terminal;
        let display_projection = display_projection_for_terminal(terminal);
        let theme = terminal_theme_snapshot(terminal);
        let (viewport_cols, viewport_rows) = terminal.size();
        if viewport_rows > 4096
            || viewport_cols > 4096
            || viewport_rows.saturating_mul(viewport_cols) > 1_048_576
        {
            return Err(StorageError::Invalid(
                "terminal dimensions exceed recording limit",
            ));
        }
        let global_bottom_row = u64::try_from(terminal.grid().total_lines_scrolled())
            .unwrap_or(u64::MAX)
            .saturating_add(u64::try_from(viewport_rows.saturating_sub(1)).unwrap_or(u64::MAX));

        let cursor = terminal.cursor();
        let modes = TerminalFrameModes {
            alternate_screen: alt_screen_active,
            application_cursor: terminal.application_cursor(),
            application_keypad: state.host_protocol.application_keypad,
            insert_mode: terminal.insert_mode(),
            origin_mode: terminal.origin_mode(),
            line_feed_new_line_mode: terminal.line_feed_new_line_mode(),
            hide_cursor: !cursor.visible,
            bracketed_paste: self.emulation == TerminalEmulation::Xterm256
                && terminal.bracketed_paste(),
            mime_paste: self.emulation == TerminalEmulation::Xterm256 && terminal.mime_paste(),
            focus_tracking: self.emulation == TerminalEmulation::Xterm256
                && terminal.focus_tracking(),
            alternate_scroll: self.emulation == TerminalEmulation::Xterm256
                && terminal.alternate_scroll(),
            char_protected: false,
            mouse_mode: if self.emulation == TerminalEmulation::Xterm256 {
                mouse_mode_name(terminal.mouse_mode()).to_string()
            } else {
                "off".to_string()
            },
            mouse_encoding: if self.emulation == TerminalEmulation::Xterm256 {
                mouse_encoding_name(terminal.mouse_encoding()).to_string()
            } else {
                "default".to_string()
            },
            kitty_keyboard_flags: if self.emulation == TerminalEmulation::Xterm256 {
                terminal.keyboard_flags()
            } else {
                0
            },
            synchronized_output: self.emulation == TerminalEmulation::Xterm256
                && terminal.synchronized_updates(),
        };

        let window_title = if self.emulation == TerminalEmulation::Xterm256 {
            match terminal.title() {
                "" => None,
                value => Some(value.to_string()),
            }
        } else {
            None
        };
        let window_icon_name = if self.emulation == TerminalEmulation::Xterm256 {
            match terminal.icon_name() {
                "" => None,
                value => Some(value.to_string()),
            }
        } else {
            None
        };
        let font_family = Some(terminal.xterm_font_family().to_string());
        let pointer_shape = if self.emulation == TerminalEmulation::Xterm256 {
            terminal.pointer_shape_name().map(str::to_string)
        } else {
            None
        };
        let viewport_display_start_row = if alt_screen_active {
            0
        } else {
            scrollback_max_offset.saturating_sub(state.scrollback_offset)
        };
        let viewport_start_row = display_projection
            .rows
            .get(viewport_display_start_row)
            .map(|row| display_projection.source_range(row).0)
            .unwrap_or(0);
        let scrollback_len = if alt_screen_active {
            0
        } else {
            terminal.grid().scrollback_len()
        };
        let frame_build_context = FrameBuildContext {
            terminal,
            emulation: self.emulation,
            display_projection: &display_projection,
            viewport_start_row,
            viewport_display_start_row,
            viewport_rows,
            viewport_cols,
            scrollback_len,
            alt_screen_active,
        };
        let mut cursor_snapshot = terminal_cursor_snapshot(terminal, cursor);
        if display_projection.has_folds() && !alt_screen_active {
            let cursor_source_row = scrollback_len.saturating_add(cursor.row);
            match display_projection.display_index_for_source(cursor_source_row) {
                Some(display_row)
                    if display_row >= viewport_display_start_row
                        && display_row
                            < viewport_display_start_row.saturating_add(viewport_rows) =>
                {
                    cursor_snapshot.row = display_row.saturating_sub(viewport_display_start_row);
                }
                _ => cursor_snapshot.visible = false,
            }
        }
        let (rows, hyperlinks, _, dirty_ranges, _, _) = build_snapshot_frame(&frame_build_context);
        let graphics = if self.graphics_enabled {
            build_projected_graphic_placements(
                terminal,
                &display_projection,
                viewport_display_start_row,
                viewport_rows,
                scrollback_len,
                alt_screen_active,
                false,
            )
        } else {
            Vec::new()
        };
        let snapshots = if graphics.is_empty() {
            Vec::new()
        } else {
            graphic_asset_snapshots(terminal)
        };
        let mut assets = Vec::new();
        let mut asset_bytes = 0usize;
        for placement in &graphics {
            if assets.iter().any(|asset: &RecordedAsset| {
                asset.asset_id == placement.asset_id
                    && asset.asset_version == placement.asset_version
            }) {
                continue;
            }
            let snapshot = snapshots
                .iter()
                .find(|asset| {
                    asset.asset_id == placement.asset_id
                        && asset.asset_version == placement.asset_version
                })
                .ok_or(StorageError::Invalid("visible graphic has no live pixels"))?;
            asset_bytes = asset_bytes
                .checked_add(snapshot.pixels.len())
                .ok_or(StorageError::Invalid("asset size overflow"))?;
            if assets.len() >= 256 || asset_bytes > 32 * 1024 * 1024 {
                return Err(StorageError::Invalid(
                    "visible assets exceed recording budget",
                ));
            }
            assets.push(RecordedAsset {
                asset_id: snapshot.asset_id,
                asset_version: snapshot.asset_version,
                width: u32::try_from(snapshot.width)
                    .map_err(|_| StorageError::Invalid("asset width overflow"))?,
                height: u32::try_from(snapshot.height)
                    .map_err(|_| StorageError::Invalid("asset height overflow"))?,
                rgba: snapshot.pixels.as_ref().clone(),
            });
        }
        let sized_text = if self.emulation == TerminalEmulation::Xterm256 {
            build_projected_sized_text_placements(
                terminal,
                &display_projection,
                viewport_display_start_row,
                viewport_rows,
            )
        } else {
            Vec::new()
        };
        let blocks = build_terminal_blocks(
            terminal,
            &display_projection,
            viewport_display_start_row,
            viewport_rows,
        );
        let inline_buttons = if self.emulation == TerminalEmulation::Xterm256 {
            build_terminal_inline_buttons(
                terminal,
                &display_projection,
                viewport_display_start_row,
                viewport_rows,
            )
        } else {
            Vec::new()
        };
        let frame = TerminalFrameDiff {
            frame_schema_version: TERMINAL_FRAME_SCHEMA_VERSION.to_string(),
            frame_kind: TerminalFrameKind::Snapshot,
            rows,
            cursor: cursor_snapshot,
            selection: None,
            viewport_rows: viewport_rows as u16,
            viewport_cols: viewport_cols as u16,
            dirty_ranges,
            scrollback_offset: state.scrollback_offset,
            scrollback_max_offset,
            global_bottom_row,
            viewport_start_row,
            viewport_row_shift: 0,
            default_foreground: color_to_hex(theme.default_fg, &theme.ansi_palette),
            default_background: color_to_hex(theme.default_bg, &theme.ansi_palette),
            cursor_color: color_to_hex(theme.cursor_color, &theme.ansi_palette),
            cursor_guide_color: color_to_hex(theme.cursor_guide_color, &theme.ansi_palette),
            selection_background: color_to_hex(theme.selection_background, &theme.ansi_palette),
            selection_foreground: theme
                .selection_foreground
                .and_then(|color| color_to_hex(color, &theme.ansi_palette)),
            link_color: theme
                .link_color
                .and_then(|color| color_to_hex(color, &theme.ansi_palette)),
            cursor_text_color: theme
                .cursor_text_color
                .and_then(|color| color_to_hex(color, &theme.ansi_palette)),
            tab_color: theme
                .tab_color
                .and_then(|color| color_to_hex(color, &theme.ansi_palette)),
            pointer_shape,
            modes,
            window_title,
            window_icon_name,
            font_family,
            hyperlinks,
            sized_text,
            graphics,
            blocks,
            inline_buttons,
        };
        Ok(Some(NativeCaptureSnapshot {
            frame: crate::frame_diff_proto::to_proto_frame(&frame),
            assets,
        }))
    }
}
