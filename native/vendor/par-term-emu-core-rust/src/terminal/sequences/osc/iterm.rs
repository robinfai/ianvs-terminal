//! iTerm2 OSC 1337 sequence handling

use super::sanitize_osc_text;
use crate::cursor::CursorShape;
use crate::debug;
use crate::terminal::event::ShellIntegrationSource;
use crate::terminal::{CwdChangeSource, Terminal, TerminalEvent};

const MAX_USER_VAR_NAME_CHARS: usize = 80;
const MAX_USER_VAR_VALUE_CHARS: usize = 4096;
const MAX_REMOTE_USERNAME_CHARS: usize = 80;
const MAX_REMOTE_HOSTNAME_CHARS: usize = 255;
const MAX_SHELL_INTEGRATION_VERSION_CHARS: usize = 32;
const MAX_SHELL_NAME_CHARS: usize = 32;

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
            } else {
                self.handle_iterm_image(&data);
            }
        }
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
    use crate::terminal::event::ShellIntegrationSource;
    use crate::terminal::{Terminal, TerminalEvent};
    use base64::{engine::general_purpose::STANDARD, Engine};

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
