//! iTerm2 OSC 1337 sequence handling

use super::sanitize_osc_text;
use crate::color::Color;
use crate::cursor::CursorShape;
use crate::debug;
use crate::terminal::event::ShellIntegrationSource;
use crate::terminal::{CwdChangeSource, Terminal, TerminalEvent};
use crate::zone::ZoneType;

const MAX_USER_VAR_NAME_CHARS: usize = 80;
const MAX_USER_VAR_VALUE_CHARS: usize = 4096;
const MAX_REMOTE_USERNAME_CHARS: usize = 80;
const MAX_REMOTE_HOSTNAME_CHARS: usize = 255;
const MAX_SHELL_INTEGRATION_VERSION_CHARS: usize = 32;
const MAX_SHELL_NAME_CHARS: usize = 32;
const MAX_SET_COLORS_PAIRS: usize = 32;

impl Terminal {
    pub(crate) fn handle_osc_iterm(&mut self, _command: &str, params: &[&[u8]]) {
        if params.len() >= 2 {
            let mut data_parts = Vec::new();
            for p in &params[1..] {
                if let Ok(s) = std::str::from_utf8(p) {
                    data_parts.push(s);
                }
            }
            let data = data_parts.join(";");

            if let Some(encoded) = data.strip_prefix("SetBadgeFormat=") {
                self.handle_set_badge_format(encoded);
            } else if let Some(payload) = data.strip_prefix("SetColors=") {
                self.handle_iterm_set_colors(payload);
            } else if let Some(payload) = data.strip_prefix("SetUserVar=") {
                self.handle_set_user_var(payload);
            } else if let Some(payload) = data.strip_prefix("RemoteHost=") {
                self.handle_remote_host(payload);
            } else if let Some(payload) = data.strip_prefix("RequestUpload=") {
                self.handle_request_upload(payload);
            } else if data == "SetMark" {
                self.handle_iterm_set_mark();
            } else if let Some(payload) = data.strip_prefix("ShellIntegrationVersion=") {
                self.handle_shell_integration_version(payload);
            } else if let Some(payload) = data.strip_prefix("CursorShape=") {
                self.handle_iterm_cursor_shape(payload);
            } else if data == "ReportCellSize" {
                self.terminal_events
                    .push(TerminalEvent::CellSizeReportRequested);
            } else if data == "ClearScrollback" {
                self.handle_iterm_clear_buffer();
            } else {
                self.handle_iterm_image(&data);
            }
        }
    }

    /// iTerm2's `ClearScrollback` name is historical: unlike CSI 3 J, the
    /// command clears both the visible grid and retained history.  It is the
    /// escape-sequence equivalent of iTerm2's Clear Buffer action.
    fn handle_iterm_clear_buffer(&mut self) {
        let preserved_rows = {
            let grid = self.active_grid();
            let cursor_row = self.cursor.row.min(grid.rows().saturating_sub(1));
            let mut start_row = cursor_row;
            while start_row > 0 && grid.is_line_wrapped(start_row - 1) {
                start_row -= 1;
            }

            // With shell integration, iTerm2 retains from the latest prompt
            // mark through the cursor. Clamp a prompt that began in history
            // to the first visible row.
            if !self.alt_screen_active {
                let visible_base = grid.total_lines_scrolled();
                let cursor_abs_row = visible_base.saturating_add(cursor_row);
                if let Some(prompt) = self.get_zones().iter().rev().find(|zone| {
                    zone.zone_type == ZoneType::Prompt && zone.abs_row_start <= cursor_abs_row
                }) {
                    start_row = prompt
                        .abs_row_start
                        .saturating_sub(visible_base)
                        .min(cursor_row);
                }
            }

            (start_row..=cursor_row)
                .filter_map(|row| {
                    grid.row(row)
                        .map(|cells| (cells.to_vec(), grid.is_line_wrapped(row)))
                })
                .collect::<Vec<_>>()
        };

        // Invalidate retained zones before clearing the visible grid so
        // subscribers still receive bounded eviction events.
        // iTerm2's history belongs to the primary buffer even when an
        // alternate-screen application sends the command.
        self.grid.clear_scrollback();
        self.graphics_store.clear_scrollback_graphics();
        self.active_grid_mut().clear();
        self.clear_graphics();

        {
            let grid = self.active_grid_mut();
            for (row, (cells, wrapped)) in preserved_rows.iter().enumerate() {
                for (col, cell) in cells.iter().cloned().enumerate() {
                    grid.set(col, row, cell);
                }
                grid.set_line_wrapped(row, *wrapped);
            }
        }

        // Keep the cursor on the final retained row, matching iTerm2's clear
        // buffer behavior for wrapped prompts and command input.
        self.cursor.row = preserved_rows.len().saturating_sub(1);
        self.saved_cursor = None;
        self.scroll_region_top = 0;
        self.scroll_region_bottom = self.size().1.saturating_sub(1);
        self.use_lr_margins = false;
        self.left_margin = 0;
        self.right_margin = self.size().0.saturating_sub(1);
        self.origin_mode = false;
        self.terminal_events.push(TerminalEvent::ScreenCleared {
            include_scrollback: true,
        });
    }

    fn handle_iterm_cursor_shape(&mut self, payload: &str) {
        let shape = match payload {
            "0" => CursorShape::Block,
            "1" => CursorShape::Bar,
            "2" => CursorShape::Underline,
            _ => return,
        };
        self.cursor.set_shape(shape);
    }

    fn handle_iterm_set_colors(&mut self, payload: &str) {
        for pair in payload.split(',').take(MAX_SET_COLORS_PAIRS) {
            let Some((key, value)) = pair.split_once('=') else {
                continue;
            };
            let key = key.trim();
            let value = value.trim();
            if key.is_empty() || value.is_empty() {
                continue;
            }
            if key == "tab" && value == "default" {
                self.set_dynamic_iterm_tab_color(None);
                continue;
            }
            // `preset` changes host profile configuration rather than a
            // session-local color resource and is intentionally unauthorized.
            if key == "preset" {
                continue;
            }
            let Some(color) = Self::parse_iterm_set_color(value) else {
                continue;
            };
            match key {
                "fg" => self.set_dynamic_default_fg(color),
                "bg" => self.set_dynamic_default_bg(color),
                "bold" => self.set_dynamic_iterm_bold_color(Some(color)),
                "link" => self.set_dynamic_iterm_link_color(Some(color)),
                "selbg" => self.set_dynamic_selection_bg_color(color),
                "selfg" => {
                    self.set_dynamic_selection_fg_color(color);
                    self.set_dynamic_selected_text_color_enabled(true);
                }
                "curbg" => self.set_dynamic_cursor_color(color),
                "curfg" => self.set_dynamic_iterm_cursor_text_color(Some(color)),
                "underline" => self.set_dynamic_iterm_underline_color(Some(color)),
                "tab" => self.set_dynamic_iterm_tab_color(Some(color)),
                _ => {
                    if let Some(index) = Self::iterm_palette_index(key) {
                        self.set_dynamic_ansi_palette_color(index, color);
                    }
                }
            }
        }
    }

    fn iterm_palette_index(key: &str) -> Option<usize> {
        Some(match key {
            "black" => 0,
            "red" => 1,
            "green" => 2,
            "yellow" => 3,
            "blue" => 4,
            "magenta" => 5,
            "cyan" => 6,
            "white" => 7,
            "br_black" => 8,
            "br_red" => 9,
            "br_green" => 10,
            "br_yellow" => 11,
            "br_blue" => 12,
            "br_magenta" => 13,
            "br_cyan" => 14,
            "br_white" => 15,
            _ => return None,
        })
    }

    fn parse_iterm_set_color(value: &str) -> Option<Color> {
        let (space, hex) = value
            .split_once(':')
            .map_or(("srgb", value), |(space, hex)| (space, hex));
        let space = space.to_ascii_lowercase();
        if !matches!(space.as_str(), "srgb" | "rgb" | "p3") {
            return None;
        }
        if !matches!(hex.len(), 3 | 6) || !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return None;
        }
        let channel = |offset: usize| -> Option<u8> {
            if hex.len() == 3 {
                let digit = u8::from_str_radix(&hex[offset..offset + 1], 16).ok()?;
                Some(digit * 17)
            } else {
                u8::from_str_radix(&hex[offset * 2..offset * 2 + 2], 16).ok()
            }
        };
        let rgb = (channel(0)?, channel(1)?, channel(2)?);
        let (red, green, blue) = if space == "p3" {
            Self::display_p3_to_srgb(rgb)
        } else {
            rgb
        };
        Some(Color::Rgb(red, green, blue))
    }

    fn display_p3_to_srgb((red, green, blue): (u8, u8, u8)) -> (u8, u8, u8) {
        let decode = |value: u8| {
            let value = f64::from(value) / 255.0;
            if value <= 0.04045 {
                value / 12.92
            } else {
                ((value + 0.055) / 1.055).powf(2.4)
            }
        };
        let encode = |value: f64| {
            let value = value.clamp(0.0, 1.0);
            let value = if value <= 0.003_130_8 {
                value * 12.92
            } else {
                1.055 * value.powf(1.0 / 2.4) - 0.055
            };
            (value * 255.0).round() as u8
        };
        let (red, green, blue) = (decode(red), decode(green), decode(blue));
        (
            encode(1.224_940_176_3 * red - 0.224_940_176_3 * green),
            encode(-0.042_056_954_7 * red + 1.042_056_954_7 * green),
            encode(-0.019_637_554_6 * red - 0.078_636_045_6 * green + 1.098_273_600_1 * blue),
        )
    }

    fn handle_iterm_set_mark(&mut self) {
        if self.alt_screen_active {
            return;
        }
        let cursor_line = self.active_grid().total_lines_scrolled() + self.cursor.row;
        self.terminal_events
            .push(TerminalEvent::ShellIntegrationEvent {
                source: ShellIntegrationSource::Osc1337,
                event_type: "mark".to_string(),
                command: None,
                exit_code: None,
                timestamp: Some(crate::terminal::unix_millis()),
                cursor_line: Some(cursor_line),
                prompt_kind: None,
                aid: None,
                parent_aid: None,
                implicit_closed_count: 0,
                fresh_line: None,
            });
    }

    fn handle_shell_integration_version(&mut self, payload: &str) {
        if self.alt_screen_active {
            return;
        }
        let (version, shell) = payload
            .split_once(';')
            .map_or((payload, None), |(version, shell)| (version, Some(shell)));
        let version = version.trim();
        if version.is_empty()
            || version.chars().count() > MAX_SHELL_INTEGRATION_VERSION_CHARS
            || !version.chars().all(|value| value.is_ascii_digit())
        {
            return;
        }
        let shell = shell.and_then(|value| {
            let value = value.trim();
            (!value.is_empty()
                && value.chars().count() <= MAX_SHELL_NAME_CHARS
                && value.chars().all(|character| {
                    character.is_ascii_alphanumeric() || "._+-".contains(character)
                }))
            .then(|| value.to_string())
        });
        self.terminal_events
            .push(TerminalEvent::ShellIntegrationVersion {
                version: version.to_string(),
                shell,
            });
    }

    pub(crate) fn handle_set_badge_format(&mut self, encoded: &str) {
        let encoded = encoded.trim();

        if encoded.is_empty() {
            self.badge_format = None;
            self.terminal_events
                .push(crate::terminal::TerminalEvent::BadgeChanged(None));
            debug::log(debug::DebugLevel::Debug, "OSC1337", "Cleared badge format");
            return;
        }

        match crate::badge::decode_badge_format(encoded) {
            Ok(format) => {
                debug::log(
                    debug::DebugLevel::Debug,
                    "OSC1337",
                    &format!("Set badge format: decoded_bytes={}", format.len()),
                );
                self.badge_format = Some(format.clone());
                let badge_text = self.evaluate_badge();
                self.terminal_events
                    .push(crate::terminal::TerminalEvent::BadgeChanged(badge_text));
            }
            Err(e) => {
                let error_kind = match e {
                    crate::badge::BadgeFormatError::Base64DecodeError(_) => "base64",
                    crate::badge::BadgeFormatError::Utf8Error(_) => "utf8",
                    crate::badge::BadgeFormatError::UnsafeContent(_) => "unsafe_content",
                    crate::badge::BadgeFormatError::TooLong(_) => "too_long",
                };
                debug::log(
                    debug::DebugLevel::Debug,
                    "OSC1337",
                    &format!("Invalid badge format: kind={error_kind}"),
                );
            }
        }
    }

    pub(crate) fn handle_set_user_var(&mut self, payload: &str) {
        if let Some((name, encoded_value)) = payload.split_once('=') {
            if name.is_empty()
                || name.chars().count() > MAX_USER_VAR_NAME_CHARS
                || name.chars().any(char::is_control)
            {
                return;
            }
            use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
            if let Ok(decoded_value) = BASE64.decode(encoded_value.trim()) {
                if let Ok(value) = String::from_utf8(decoded_value) {
                    self.set_user_var(
                        name.to_string(),
                        sanitize_osc_text(&value, MAX_USER_VAR_VALUE_CHARS),
                    );
                }
            }
        }
    }

    pub(crate) fn handle_remote_host(&mut self, payload: &str) {
        if payload.is_empty() || payload.chars().any(char::is_control) {
            return;
        }

        let (username, hostname) = if let Some((u, h)) = payload.split_once('@') {
            if h.is_empty() {
                return; // Ignore if hostname part is empty
            }
            if u.chars().count() > MAX_REMOTE_USERNAME_CHARS
                || h.chars().count() > MAX_REMOTE_HOSTNAME_CHARS
            {
                return;
            }
            (Some(u.to_string()), Some(h.to_string()))
        } else {
            if payload.chars().count() > MAX_REMOTE_HOSTNAME_CHARS {
                return;
            }
            (None, Some(payload.to_string()))
        };

        // Filter out localhost and empty values to match OSC 7 behavior
        let hostname = hostname.and_then(|h| {
            if h.is_empty() || h.eq_ignore_ascii_case("localhost") || h == "127.0.0.1" || h == "::1"
            {
                None
            } else {
                Some(h)
            }
        });

        let username = username.and_then(|u| if u.is_empty() { None } else { Some(u) });

        let current_cwd = self
            .shell_integration
            .cwd()
            .map(|s| s.to_string())
            .unwrap_or_else(|| "/".to_string());

        self.record_cwd_change(crate::terminal::event::CwdChange {
            source: CwdChangeSource::Osc1337,
            old_cwd: Some(current_cwd.clone()),
            new_cwd: current_cwd,
            hostname,
            username,
            timestamp: crate::terminal::unix_millis(),
        });
    }

    pub(crate) fn handle_request_upload(&mut self, payload: &str) {
        // payload is e.g. "format=tgz" — extract just the value
        let format = if let Some(val) = payload.strip_prefix("format=") {
            val.to_string()
        } else {
            payload.to_string()
        };
        self.terminal_events
            .push(crate::terminal::TerminalEvent::UploadRequested { format });
    }
}

#[cfg(test)]
mod tests {
    use crate::color::Color;
    use crate::terminal::event::ShellIntegrationSource;
    use crate::terminal::{Terminal, TerminalEvent};
    use crate::zone::ZoneType;
    use base64::{engine::general_purpose::STANDARD, Engine};

    #[test]
    fn set_colors_applies_all_session_local_resources_and_palette_entries() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(
            b"\x1b]1337;SetColors=fg=123,bg=srgb:234,bold=345,link=456,selbg=567,selfg=678,curbg=789,curfg=89a,underline=9ab,tab=abc,black=bcd,br_white=cde\x1b\\",
        );

        assert_eq!(terminal.default_fg(), Color::Rgb(0x11, 0x22, 0x33));
        assert_eq!(terminal.default_bg(), Color::Rgb(0x22, 0x33, 0x44));
        assert_eq!(
            terminal.iterm_bold_color(),
            Some(Color::Rgb(0x33, 0x44, 0x55))
        );
        assert_eq!(
            terminal.iterm_link_color(),
            Some(Color::Rgb(0x44, 0x55, 0x66))
        );
        assert_eq!(
            terminal.get_selection_bg_color(),
            Color::Rgb(0x55, 0x66, 0x77)
        );
        assert_eq!(
            terminal.get_selection_fg_color(),
            Color::Rgb(0x66, 0x77, 0x88)
        );
        assert!(terminal.selection_foreground_color_enabled());
        assert_eq!(terminal.cursor_color(), Color::Rgb(0x77, 0x88, 0x99));
        assert_eq!(
            terminal.iterm_cursor_text_color(),
            Some(Color::Rgb(0x88, 0x99, 0xaa))
        );
        assert_eq!(
            terminal.iterm_underline_color(),
            Some(Color::Rgb(0x99, 0xaa, 0xbb))
        );
        assert_eq!(
            terminal.iterm_tab_color(),
            Some(Color::Rgb(0xaa, 0xbb, 0xcc))
        );
        assert_eq!(
            terminal.get_ansi_color(0),
            Some(Color::Rgb(0xbb, 0xcc, 0xdd))
        );
        assert_eq!(
            terminal.get_ansi_color(15),
            Some(Color::Rgb(0xcc, 0xdd, 0xee))
        );
    }

    #[test]
    fn set_colors_converts_display_p3_and_rejects_profile_or_malformed_values() {
        let mut terminal = Terminal::new(80, 24);
        let baseline = terminal.default_fg();
        terminal.process(
            b"\x1b]1337;SetColors=fg=p3:808080,preset=Grass,bg=unknown:ffffff,tab=default,red=12xz89\x07",
        );

        assert_eq!(terminal.default_fg(), Color::Rgb(0x80, 0x80, 0x80));
        assert_eq!(
            terminal.default_bg(),
            Color::Named(crate::color::NamedColor::Black)
        );
        assert_eq!(terminal.iterm_tab_color(), None);
        assert_ne!(terminal.default_fg(), baseline);
        assert_eq!(
            terminal.get_ansi_color(1),
            Some(Color::Rgb(0xb4, 0x3c, 0x2a))
        );
    }

    #[test]
    fn set_colors_tab_default_and_ris_restore_runtime_overrides() {
        let mut terminal = Terminal::new(80, 24);
        let baseline_fg = terminal.default_fg();
        terminal.process(b"\x1b]1337;SetColors=fg=123,link=456,tab=abcdef\x1b\\");
        let snapshot = terminal.capture_snapshot();

        let mut restored = Terminal::new(80, 24);
        restored.restore_from_snapshot(snapshot);
        assert_eq!(restored.default_fg(), Color::Rgb(0x11, 0x22, 0x33));
        assert_eq!(
            restored.iterm_link_color(),
            Some(Color::Rgb(0x44, 0x55, 0x66))
        );
        assert_eq!(
            restored.iterm_tab_color(),
            Some(Color::Rgb(0xab, 0xcd, 0xef))
        );

        restored.process(b"\x1b]1337;SetColors=tab=default\x07");
        assert_eq!(restored.iterm_tab_color(), None);
        restored.process(b"\x1bc");
        assert_eq!(restored.default_fg(), baseline_fg);
        assert_eq!(restored.iterm_link_color(), None);
        assert_eq!(restored.iterm_tab_color(), None);
    }

    #[test]
    fn user_variables_strip_controls_and_reject_unsafe_names() {
        let mut terminal = Terminal::new(80, 24);
        let value = STANDARD.encode("line\nsecret\u{0085}tail");
        terminal.handle_set_user_var(&format!("safe={value}"));
        terminal.handle_set_user_var(&format!("bad\nname={value}"));

        assert_eq!(terminal.get_user_var("safe"), Some("linesecrettail"));
        assert!(terminal.get_user_var("bad\nname").is_none());
    }

    #[test]
    fn remote_identity_rejects_controls_and_oversized_fields() {
        let mut terminal = Terminal::new(80, 24);
        terminal.handle_remote_host("alice\n@remote.example");
        terminal.handle_remote_host(&format!("{}@remote.example", "u".repeat(81)));

        assert!(terminal.shell_integration().hostname().is_none());
        assert!(terminal.shell_integration().username().is_none());
    }

    #[test]
    fn set_mark_emits_bounded_primary_screen_marker_for_bel_and_st() {
        for sequence in [
            b"\x1b]1337;SetMark\x07".as_slice(),
            b"\x1b]1337;SetMark\x1b\\".as_slice(),
        ] {
            let mut terminal = Terminal::new(80, 24);
            terminal.process(b"line\r\n");
            terminal.process(sequence);
            assert!(terminal.poll_events().iter().any(|event| matches!(
                event,
                TerminalEvent::ShellIntegrationEvent {
                    source: ShellIntegrationSource::Osc1337,
                    event_type,
                    cursor_line: Some(1),
                    ..
                } if event_type == "mark"
            )));
        }

        let mut alternate = Terminal::new(80, 24);
        alternate.process(b"\x1b[?1049h\x1b]1337;SetMark\x07");
        assert!(!alternate.poll_events().iter().any(|event| matches!(
            event,
            TerminalEvent::ShellIntegrationEvent {
                source: ShellIntegrationSource::Osc1337,
                ..
            }
        )));
    }

    #[test]
    fn shell_integration_version_is_typed_bounded_metadata() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]1337;ShellIntegrationVersion=17;zsh\x1b\\");
        terminal.process(b"\x1b]1337;ShellIntegrationVersion=beta;bad\x07");
        terminal.process(b"\x1b]1337;ShellIntegrationVersion=18;bad shell\x07");

        let events = terminal.poll_events();
        assert!(events.iter().any(|event| matches!(
            event,
            TerminalEvent::ShellIntegrationVersion { version, shell }
                if version == "17" && shell.as_deref() == Some("zsh")
        )));
        assert!(events.iter().any(|event| matches!(
            event,
            TerminalEvent::ShellIntegrationVersion { version, shell }
                if version == "18" && shell.is_none()
        )));
        assert_eq!(
            events
                .iter()
                .filter(|event| matches!(event, TerminalEvent::ShellIntegrationVersion { .. }))
                .count(),
            2
        );
    }

    #[test]
    fn report_cell_size_emits_only_for_the_exact_query() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]1337;ReportCellSize\x07");
        terminal.process(b"\x1b]1337;ReportCellSize=spoof\x07");

        assert_eq!(
            terminal
                .poll_events()
                .iter()
                .filter(|event| matches!(event, TerminalEvent::CellSizeReportRequested))
                .count(),
            1
        );
    }

    #[test]
    fn clear_scrollback_clears_visible_buffer_history_and_saved_layout_state() {
        let mut terminal = Terminal::with_scrollback(8, 3, 16);
        terminal.process(b"old-0\r\nold-1\r\nold-2\r\nold-3\r\nold-4");
        terminal.process(b"\x1b[2;3r\x1b[?69h\x1b[2;7s\x1b[?6h\x1b7");
        assert!(terminal.scrollback_len() > 0);
        assert_eq!(terminal.scroll_region(), (1, 2));
        assert!(terminal.use_lr_margins);
        assert!(terminal.origin_mode());
        let current_line = terminal
            .active_grid()
            .row_text(terminal.cursor().row)
            .trim()
            .to_string();
        let _ = terminal.poll_events();

        terminal.process(b"\x1b]1337;ClearScrollback\x1b\\");

        assert_eq!(terminal.scrollback_len(), 0);
        assert_eq!(terminal.cursor().row, 0);
        assert_eq!(terminal.scroll_region(), (0, 2));
        assert!(!terminal.use_lr_margins);
        assert_eq!(terminal.left_right_margins(), (0, 7));
        assert!(!terminal.origin_mode());
        assert_eq!(terminal.active_grid().row_text(0).trim(), current_line);
        assert!((1..terminal.active_grid().rows()).all(|row| terminal
            .active_grid()
            .row_text(row)
            .trim()
            .is_empty()));
        assert!(terminal.poll_events().iter().any(|event| matches!(
            event,
            TerminalEvent::ScreenCleared {
                include_scrollback: true
            }
        )));

        // The command is exact. Near-matches must remain bounded no-ops.
        terminal.process(b"\r\x1b[2Ksentinel\x1b]1337;ClearScrollback=1\x07");
        assert_eq!(
            terminal.active_grid().row(0).unwrap()[0].get_grapheme(),
            "s"
        );
    }

    #[test]
    fn clear_scrollback_accepts_bel_st_and_every_byte_split() {
        for sequence in [
            b"\x1b]1337;ClearScrollback\x07".as_slice(),
            b"\x1b]1337;ClearScrollback\x1b\\".as_slice(),
        ] {
            for split in 1..sequence.len() {
                let mut terminal = Terminal::with_scrollback(8, 2, 8);
                terminal.process(b"one\r\ntwo\r\nthree");
                assert!(terminal.scrollback_len() > 0);
                terminal.process(&sequence[..split]);
                terminal.process(&sequence[split..]);
                assert_eq!(terminal.scrollback_len(), 0, "split={split}");
                assert_eq!(terminal.active_grid().row_text(0).trim(), "three");
            }
        }
    }

    #[test]
    fn clear_scrollback_preserves_the_wrapped_cursor_line_at_the_top() {
        let mut terminal = Terminal::with_scrollback(5, 3, 8);
        terminal.process(b"older\r\n1234567");
        assert!(terminal.active_grid().is_line_wrapped(1));

        terminal.process(b"\x1b]1337;ClearScrollback\x07");

        assert_eq!(terminal.scrollback_len(), 0);
        assert_eq!(terminal.active_grid().row_text(0), "12345");
        assert_eq!(terminal.active_grid().row_text(1).trim(), "67");
        assert!(terminal.active_grid().is_line_wrapped(0));
        assert_eq!(terminal.cursor().row, 1);
        assert_eq!(terminal.cursor().col, 2);
    }

    #[test]
    fn clear_scrollback_preserves_hard_broken_rows_from_the_latest_prompt_mark() {
        let mut terminal = Terminal::with_scrollback(12, 4, 8);
        terminal.process(b"\x1b]133;A\x07prompt-one\r\nprompt-two\x1b]133;B\x07");
        assert_eq!(terminal.active_grid().row_text(0).trim(), "prompt-one");
        assert_eq!(terminal.active_grid().row_text(1).trim(), "prompt-two");

        terminal.process(b"\x1b]1337;ClearScrollback\x1b\\");

        assert_eq!(terminal.active_grid().row_text(0).trim(), "prompt-one");
        assert_eq!(terminal.active_grid().row_text(1).trim(), "prompt-two");
        assert_eq!(terminal.cursor().row, 1);
        assert!(terminal.get_zones().is_empty());
        assert!(terminal.poll_events().iter().any(|event| matches!(
            event,
            TerminalEvent::ZoneScrolledOut {
                zone_type: ZoneType::Prompt,
                ..
            }
        )));
    }

    #[test]
    fn clear_scrollback_from_alternate_screen_clears_primary_history() {
        let mut terminal = Terminal::with_scrollback(8, 2, 8);
        terminal.process(b"one\r\ntwo\r\nthree");
        assert!(terminal.scrollback_len() > 0);

        terminal.process(b"\x1b[?1049halternate\x1b]1337;ClearScrollback\x07");
        assert!(terminal.is_alt_screen_active());
        assert_eq!(terminal.scrollback_len(), 0);
        assert_eq!(
            format!(
                "{}{}",
                terminal.active_grid().row_text(0),
                terminal.active_grid().row_text(1)
            )
            .trim(),
            "alternate"
        );

        terminal.process(b"\x1b[?1049l");
        assert!(!terminal.is_alt_screen_active());
        assert_eq!(terminal.scrollback_len(), 0);
    }

    #[test]
    fn cursor_shape_maps_exact_iterm_values_without_overriding_blink() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]1337;CursorShape=1\x07");
        assert_eq!(
            terminal.cursor().shape_override(),
            Some(crate::cursor::CursorShape::Bar)
        );
        assert_eq!(terminal.cursor().blink_override(), None);

        terminal.process(b"\x1b]1337;CursorShape=2\x1b\\");
        assert_eq!(
            terminal.cursor().shape_override(),
            Some(crate::cursor::CursorShape::Underline)
        );
        terminal.process(b"\x1b]1337;CursorShape=3\x07");
        terminal.process(b"\x1b]1337;CursorShape=01\x07");
        assert_eq!(
            terminal.cursor().shape_override(),
            Some(crate::cursor::CursorShape::Underline)
        );

        terminal.process(b"\x1b[4 q\x1b]1337;CursorShape=1\x07");
        assert_eq!(
            terminal.cursor().shape_override(),
            Some(crate::cursor::CursorShape::Bar)
        );
        assert_eq!(terminal.cursor().blink_override(), Some(false));
    }

    #[test]
    fn cursor_shape_accepts_every_byte_split_and_both_terminators() {
        for sequence in [
            b"\x1b]1337;CursorShape=1\x07".as_slice(),
            b"\x1b]1337;CursorShape=2\x1b\\".as_slice(),
        ] {
            for split in 1..sequence.len() {
                let mut terminal = Terminal::new(80, 24);
                terminal.process(&sequence[..split]);
                terminal.process(&sequence[split..]);
                assert!(
                    terminal.cursor().shape_override().is_some(),
                    "split={split}"
                );
                assert_eq!(terminal.cursor().blink_override(), None);
            }
        }
    }

    #[test]
    fn cursor_shape_is_restored_across_alternate_screen_and_ris() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]1337;CursorShape=1\x07");
        terminal.process(b"\x1b[?1049h\x1b]1337;CursorShape=2\x07");
        assert_eq!(
            terminal.cursor().shape_override(),
            Some(crate::cursor::CursorShape::Underline)
        );

        terminal.process(b"\x1b[?1049l");
        assert_eq!(
            terminal.cursor().shape_override(),
            Some(crate::cursor::CursorShape::Bar)
        );

        terminal.process(b"\x1bc");
        assert_eq!(terminal.cursor().shape_override(), None);
        assert_eq!(terminal.cursor().blink_override(), None);
    }

    #[test]
    fn shell_metadata_sequences_accept_every_byte_split() {
        type EventMatcher = fn(&TerminalEvent) -> bool;
        let cases: &[(&[u8], EventMatcher)] = &[
            (b"\x1b]1337;SetMark\x1b\\", |event| {
                matches!(
                    event,
                    TerminalEvent::ShellIntegrationEvent {
                        source: ShellIntegrationSource::Osc1337,
                        event_type,
                        ..
                    } if event_type == "mark"
                )
            }),
            (b"\x1b]1337;ShellIntegrationVersion=17;zsh\x1b\\", |event| {
                matches!(event, TerminalEvent::ShellIntegrationVersion { .. })
            }),
            (b"\x1b]1337;ReportCellSize\x1b\\", |event| {
                matches!(event, TerminalEvent::CellSizeReportRequested)
            }),
        ];

        for (sequence, matches_event) in cases {
            for split in 1..sequence.len() {
                let mut terminal = Terminal::new(80, 24);
                terminal.process(&sequence[..split]);
                terminal.process(&sequence[split..]);
                assert!(
                    terminal.poll_events().iter().any(matches_event),
                    "missing event at byte split {split} for {sequence:?}"
                );
            }
        }
    }
}
