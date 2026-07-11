//! OSC (Operating System Command) sequence handling dispatcher

mod clipboard;
mod color;
mod iterm;
mod notify;
mod shell;
mod title;

use crate::debug;
use crate::terminal::Terminal;

/// Maximum total OSC data length in bytes (128 MB)
/// Must be large enough for inline images (iTerm2/Kitty protocols send
/// base64-encoded image data inside a single OSC sequence).
const MAX_OSC_DATA_LENGTH: usize = 128 * 1024 * 1024;

impl Terminal {
    /// Check if an OSC command should be filtered due to security settings
    pub(crate) fn is_insecure_osc(&self, command: &str) -> bool {
        if !self.disable_insecure_sequences {
            return false;
        }

        matches!(command, "52" | "8" | "9" | "777")
    }

    /// VTE OSC dispatch - handle OSC sequences
    pub(in crate::terminal) fn osc_dispatch_impl(
        &mut self,
        params: &[&[u8]],
        _bell_terminated: bool,
    ) {
        debug::log_osc_dispatch(params);
        if params.is_empty() {
            return;
        }

        // Reject excessively large OSC data to prevent memory exhaustion
        let total_len: usize = params.iter().map(|p| p.len()).sum();
        if total_len > MAX_OSC_DATA_LENGTH {
            debug::log(
                debug::DebugLevel::Debug,
                "OSC",
                &format!(
                    "OSC data too large: {} bytes (max {}), ignoring",
                    total_len, MAX_OSC_DATA_LENGTH
                ),
            );
            return;
        }

        if let Ok(command) = std::str::from_utf8(params[0]) {
            if self.is_insecure_osc(command) {
                debug::log(
                    debug::DebugLevel::Debug,
                    "SECURITY",
                    &format!(
                        "Blocked insecure OSC {} (disable_insecure_sequences=true)",
                        command
                    ),
                );
                return;
            }

            match command {
                // OSC 21 and 22 are used by modern terminals for dynamic
                // colors and pointer shapes. Until those protocols are
                // implemented, consume them through the unsupported path;
                // they must never mutate the title stack.
                "0" | "2" | "23" => self.handle_osc_title(command, params),
                "7" | "133" => self.handle_osc_shell(command, params),
                "8" => self.handle_osc_hyperlink(params),
                "9" | "777" | "934" => self.handle_osc_notify(command, params),
                "52" => self.handle_osc_clipboard(command, params),
                "4" | "104" | "10" | "11" | "12" | "110" | "111" | "112" => {
                    self.handle_osc_color(command, params)
                }
                "1337" => self.handle_osc_iterm(command, params),
                _ => {
                    debug::log(
                        debug::DebugLevel::Debug,
                        "OSC",
                        &format!("Unsupported OSC command: {}", command),
                    );
                }
            }
        }
    }

    pub(crate) fn handle_osc_hyperlink(&mut self, params: &[&[u8]]) {
        if params.len() >= 3 {
            if let Ok(url) = std::str::from_utf8(params[2]) {
                let url = url.trim();
                let protocol_id = std::str::from_utf8(params[1]).ok().and_then(|value| {
                    value
                        .split(':')
                        .filter_map(|parameter| parameter.split_once('='))
                        .find_map(|(key, value)| {
                            (key == "id"
                                && !value.is_empty()
                                && value.len() <= 1024
                                && !value.chars().any(char::is_control))
                            .then(|| value.to_string())
                        })
                });

                if url.is_empty() {
                    self.current_hyperlink_id = None;
                } else {
                    let id = self
                        .hyperlinks
                        .iter()
                        .find(|(id, value)| {
                            value.as_str() == url
                                && self.hyperlink_protocol_ids.get(id) == protocol_id.as_ref()
                        })
                        .map(|(k, _)| *k)
                        .unwrap_or_else(|| {
                            let id = self.next_hyperlink_id;
                            self.hyperlinks.insert(id, url.to_string());
                            if let Some(protocol_id) = protocol_id.clone() {
                                self.hyperlink_protocol_ids.insert(id, protocol_id);
                            }
                            self.next_hyperlink_id += 1;
                            id
                        });

                    self.current_hyperlink_id = Some(id);

                    self.terminal_events
                        .push(crate::terminal::TerminalEvent::HyperlinkAdded {
                            url: url.to_string(),
                            row: self.cursor.row,
                            col: self.cursor.col,
                            id: Some(id),
                        });
                }
            }
        } else if params.len() == 2 {
            self.current_hyperlink_id = None;
        }
    }
}

#[cfg(test)]
mod tests;
