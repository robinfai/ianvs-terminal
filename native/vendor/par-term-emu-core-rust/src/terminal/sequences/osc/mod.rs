//! OSC (Operating System Command) sequence handling dispatcher

mod clipboard;
mod color;
mod context;
mod drag_drop;
mod iterm;
mod notify;
mod pointer;
mod shell;
mod sized_text;
mod tab_status;
mod title;

use crate::debug;
use crate::terminal::Terminal;
use std::collections::HashSet;

/// Maximum number of OSC 8 identities retained by one terminal.
///
/// At this high-water mark, identities no longer referenced by either grid or
/// by the currently open hyperlink are reclaimed. If every entry is still
/// active, a new identity is rejected until one becomes reclaimable.
pub(crate) const MAX_HYPERLINK_ENTRIES: usize = 1024;

pub(super) fn sanitize_osc_text(value: &str, max_chars: usize) -> String {
    value
        .chars()
        .filter(|character| !character.is_control())
        .take(max_chars)
        .collect()
}

/// Maximum total OSC data length in bytes (128 MB)
/// Must be large enough for inline images (iTerm2/Kitty protocols send
/// base64-encoded image data inside a single OSC sequence).
const MAX_OSC_DATA_LENGTH: usize = 128 * 1024 * 1024;

fn unsupported_osc_log_message(command: &str, params: &[&[u8]]) -> String {
    let payload_bytes = params
        .iter()
        .skip(1)
        .map(|parameter| parameter.len())
        .sum::<usize>();
    format!(
        "Unsupported OSC command: command_bytes={} params={} payload_bytes={}",
        command.len(),
        params.len().saturating_sub(1),
        payload_bytes
    )
}

impl Terminal {
    fn referenced_hyperlink_ids(&self) -> HashSet<u32> {
        let mut referenced = HashSet::new();
        referenced.extend(self.current_hyperlink_id);
        for cell in self
            .grid
            .cells
            .iter()
            .chain(self.grid.scrollback_cells.iter())
            .chain(self.alt_grid.cells.iter())
            .chain(self.alt_grid.scrollback_cells.iter())
        {
            referenced.extend(cell.flags.hyperlink_id);
        }
        referenced
    }

    fn reclaim_unreferenced_hyperlinks(&mut self) {
        let referenced = self.referenced_hyperlink_ids();
        self.hyperlinks.retain(|id, _| referenced.contains(id));
        self.hyperlink_protocol_ids
            .retain(|id, _| self.hyperlinks.contains_key(id));
    }

    fn allocate_hyperlink_id(&mut self) -> Option<u32> {
        if self.hyperlinks.len() >= MAX_HYPERLINK_ENTRIES {
            self.reclaim_unreferenced_hyperlinks();
        }
        if self.hyperlinks.len() >= MAX_HYPERLINK_ENTRIES {
            return None;
        }

        // The map has at most MAX_HYPERLINK_ENTRIES entries, so one of these
        // consecutive wrapping IDs is guaranteed to be free even after a
        // long-running session wraps the u32 counter.
        let id = (0..=MAX_HYPERLINK_ENTRIES)
            .map(|offset| self.next_hyperlink_id.wrapping_add(offset as u32))
            .find(|candidate| !self.hyperlinks.contains_key(candidate))?;
        self.next_hyperlink_id = id.wrapping_add(1);
        Some(id)
    }

    fn get_or_insert_hyperlink_id(&mut self, url: &str, protocol_id: Option<&str>) -> Option<u32> {
        if let Some(id) = self
            .hyperlinks
            .iter()
            .find(|(id, value)| {
                value.as_str() == url
                    && self.hyperlink_protocol_ids.get(id).map(String::as_str) == protocol_id
            })
            .map(|(id, _)| *id)
        {
            return Some(id);
        }

        let id = self.allocate_hyperlink_id()?;
        self.hyperlinks.insert(id, url.to_string());
        if let Some(protocol_id) = protocol_id {
            self.hyperlink_protocol_ids
                .insert(id, protocol_id.to_string());
        }
        Some(id)
    }

    /// Check if an OSC command should be filtered due to security settings
    pub(crate) fn is_insecure_osc(&self, command: &str) -> bool {
        if !self.disable_insecure_sequences {
            return false;
        }

        matches!(command, "52" | "8" | "9" | "99" | "777")
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
                // OSC 23 has no title-stack meaning; title push/pop is CSI 22/23 t.
                "0" | "2" => self.handle_osc_title(command, params),
                "7" | "133" | "633" => self.handle_osc_shell(command, params),
                "8" => self.handle_osc_hyperlink(params),
                "9" | "99" | "777" | "934" => self.handle_osc_notify(command, params),
                "52" => self.handle_osc_clipboard(command, params),
                "22" => self.handle_osc_pointer_shape(params),
                "66" => self.handle_osc_sized_text(params),
                "72" => self.handle_osc_drag_drop(params),
                "4" | "5" | "6" | "10" | "11" | "12" | "13" | "14" | "15" | "16" | "17" | "18"
                | "19" | "21" | "104" | "105" | "106" | "110" | "111" | "112" | "113" | "114"
                | "115" | "116" | "117" | "118" | "119" => self.handle_osc_color(command, params),
                "1337" => self.handle_osc_iterm(command, params),
                "21337" => self.handle_osc_tab_status(params),
                "3008" => self.handle_osc3008(params),
                _ => {
                    debug::log(
                        debug::DebugLevel::Debug,
                        "OSC",
                        &unsupported_osc_log_message(command, params),
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
                    let Some(id) = self.get_or_insert_hyperlink_id(url, protocol_id.as_deref())
                    else {
                        // Do not accidentally continue the previous identity
                        // when a distinct new link cannot be retained.
                        self.current_hyperlink_id = None;
                        return;
                    };

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
