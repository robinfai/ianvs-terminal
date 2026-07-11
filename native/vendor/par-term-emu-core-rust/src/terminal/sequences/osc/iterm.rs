//! iTerm2 OSC 1337 sequence handling

use super::sanitize_osc_text;
use crate::debug;
use crate::terminal::{CwdChangeSource, Terminal};

const MAX_USER_VAR_NAME_CHARS: usize = 80;
const MAX_USER_VAR_VALUE_CHARS: usize = 4096;
const MAX_REMOTE_USERNAME_CHARS: usize = 80;
const MAX_REMOTE_HOSTNAME_CHARS: usize = 255;

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
            } else {
                self.handle_iterm_image(&data);
            }
        }
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
    use crate::terminal::Terminal;
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
}
