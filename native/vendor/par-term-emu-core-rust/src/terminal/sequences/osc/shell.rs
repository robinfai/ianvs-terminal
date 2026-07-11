//! Shell integration OSC sequence handling

use crate::debug;
use crate::shell_integration::{
    Osc633ExpectedNonce, ShellIntegrationMarker, ShellIntegrationState, ShellMarkerTransition,
};
use crate::terminal::event::{CwdChangeSource, ShellIntegrationSource};
use crate::terminal::{Terminal, TerminalEvent};
use crate::zone::{Zone, ZoneType};
use percent_encoding::percent_decode_str;
use std::path::Path;
use url::Url;

const OSC633_COMMAND_MAX_BYTES: usize = 16 * 1024;
const OSC633_CWD_MAX_BYTES: usize = 4 * 1024;
const OSC633_NONCE_MAX_BYTES: usize = 256;
const OSC7_CWD_MAX_BYTES: usize = 4 * 1024;
const OSC7_HOST_MAX_BYTES: usize = 255;
const OSC7_USERNAME_MAX_BYTES: usize = 255;
const SHELL_COMMAND_MAX_CHARS: usize = 4 * 1024;

impl Terminal {
    /// Configure the optional VS Code OSC 633 command-line correlation nonce.
    ///
    /// The nonce validates shell metadata only. It is never surfaced as an
    /// event and never authorizes command execution or another host action.
    pub fn is_valid_osc633_nonce(nonce: &str) -> bool {
        !nonce.is_empty()
            && nonce.len() <= OSC633_NONCE_MAX_BYTES
            && !nonce.chars().any(char::is_control)
            && !nonce.contains(';')
    }

    pub fn set_osc633_expected_nonce(&mut self, nonce: Option<String>) -> bool {
        match nonce {
            None => {
                self.osc633_expected_nonce = None;
                true
            }
            Some(nonce) if Self::is_valid_osc633_nonce(&nonce) => {
                self.osc633_expected_nonce = Some(Osc633ExpectedNonce::new(nonce));
                true
            }
            Some(_) => false,
        }
    }

    /// Whether strict OSC 633 `E` nonce correlation is configured.
    pub fn osc633_expected_nonce_configured(&self) -> bool {
        self.osc633_expected_nonce.is_some()
    }

    pub(crate) fn handle_osc_shell(&mut self, command: &str, params: &[&[u8]]) {
        match command {
            "7" => {
                // Set current working directory (OSC 7)
                if self.accept_osc7 && params.len() >= 2 {
                    if let Ok(cwd_url) = std::str::from_utf8(params[1]) {
                        if let Some((path, hostname, username)) = Self::parse_osc7_url(cwd_url) {
                            let path_bytes = path.len();
                            let has_hostname = hostname.is_some();
                            let has_username = username.is_some();
                            // record_cwd_change handles setting shell_integration state
                            // and reads old values before updating
                            self.record_cwd_change(crate::terminal::event::CwdChange {
                                source: CwdChangeSource::Osc7,
                                old_cwd: self.shell_integration.cwd().map(|s| s.to_string()),
                                new_cwd: path.clone(),
                                hostname: hostname.clone(),
                                username,
                                timestamp: crate::terminal::unix_millis(),
                            });
                            debug::log(
                                debug::DebugLevel::Debug,
                                "OSC7",
                                &format!(
                                    "Accepted cwd metadata: path_bytes={path_bytes}, \
                                     has_hostname={has_hostname}, has_username={has_username}"
                                ),
                            );
                        }
                    }
                }
            }
            "133" => {
                let Some(marker) = params
                    .get(1)
                    .and_then(|value| std::str::from_utf8(value).ok())
                else {
                    return;
                };
                let marker = match marker {
                    "A" => ShellIntegrationMarker::PromptStart,
                    "B" => ShellIntegrationMarker::CommandStart,
                    "C" => ShellIntegrationMarker::CommandExecuted,
                    "D" => ShellIntegrationMarker::CommandFinished,
                    _ => return,
                };
                let command = (marker == ShellIntegrationMarker::CommandExecuted)
                    .then(|| {
                        params
                            .get(2)
                            .and_then(|value| std::str::from_utf8(value).ok())
                    })
                    .flatten();
                let exit_code = (marker == ShellIntegrationMarker::CommandFinished)
                    .then(|| {
                        params
                            .get(2)
                            .and_then(|value| std::str::from_utf8(value).ok())
                            .and_then(|value| value.trim().parse::<i32>().ok())
                    })
                    .flatten();
                self.handle_shell_marker(
                    ShellIntegrationSource::Osc133,
                    marker,
                    command,
                    exit_code,
                );
            }
            "633" => self.handle_osc633(params),
            _ => {}
        }
    }

    fn handle_osc633(&mut self, params: &[&[u8]]) {
        // Keep all shell metadata tied to the primary-screen lifecycle. This
        // mirrors OSC 133 handling and prevents TUIs from spoofing host state.
        if self.alt_screen_active {
            return;
        }

        let Some(kind) = params
            .get(1)
            .and_then(|value| std::str::from_utf8(value).ok())
        else {
            return;
        };

        let marker = match kind {
            "A" => Some(ShellIntegrationMarker::PromptStart),
            "B" => Some(ShellIntegrationMarker::CommandStart),
            "C" => Some(ShellIntegrationMarker::CommandExecuted),
            "D" => Some(ShellIntegrationMarker::CommandFinished),
            _ => None,
        };
        if let Some(marker) = marker {
            let exit_code = (marker == ShellIntegrationMarker::CommandFinished)
                .then(|| {
                    params
                        .get(2)
                        .and_then(|value| std::str::from_utf8(value).ok())
                        .and_then(|value| value.trim().parse::<i32>().ok())
                })
                .flatten();
            self.handle_shell_marker(ShellIntegrationSource::Osc633, marker, None, exit_code);
            return;
        }

        match kind {
            // VS Code emits `E;<command-line>;<nonce>`. The nonce exists only
            // for shell-side correlation: validate it when the embedding
            // session supplied VSCODE_NONCE, but never log or surface it.
            "E" => {
                if !(3..=4).contains(&params.len())
                    || !self.osc633_nonce_matches(params.get(3).copied())
                {
                    return;
                }
                let Some(command) = params
                    .get(2)
                    .and_then(|value| decode_osc633_field(value, OSC633_COMMAND_MAX_BYTES))
                else {
                    return;
                };
                let command = command.trim();
                if !command.is_empty() {
                    self.shell_integration.set_command(command.to_string());
                }
            }
            "P" => {
                if params.len() != 3 {
                    return;
                }
                let Some(property) = params
                    .get(2)
                    .and_then(|value| decode_osc633_field(value, OSC633_CWD_MAX_BYTES))
                else {
                    return;
                };
                let Some(path) = property.strip_prefix("Cwd=").map(str::trim) else {
                    return;
                };
                if path.is_empty()
                    || path.len() > OSC633_CWD_MAX_BYTES
                    || path.chars().any(char::is_control)
                    || !Path::new(path).is_absolute()
                {
                    return;
                }
                self.record_cwd_change(crate::terminal::event::CwdChange {
                    source: CwdChangeSource::Osc633,
                    old_cwd: self.shell_integration.cwd().map(str::to_string),
                    new_cwd: path.to_string(),
                    hostname: self.shell_integration.hostname().map(str::to_string),
                    username: self.shell_integration.username().map(str::to_string),
                    timestamp: crate::terminal::unix_millis(),
                });
            }
            _ => {}
        }
    }

    fn osc633_nonce_matches(&self, nonce: Option<&[u8]>) -> bool {
        let decoded = match nonce {
            Some(value) => decode_osc633_field(value, OSC633_NONCE_MAX_BYTES),
            None => None,
        };
        match self
            .osc633_expected_nonce
            .as_ref()
            .map(Osc633ExpectedNonce::as_str)
        {
            Some(expected) => decoded.as_deref() == Some(expected),
            None => nonce.is_none() || decoded.is_some(),
        }
    }

    /// Normalize a validated OSC 133/633 marker into shared shell state,
    /// semantic zones, and a typed event.
    pub(crate) fn handle_shell_marker(
        &mut self,
        source: ShellIntegrationSource,
        marker: ShellIntegrationMarker,
        command: Option<&str>,
        exit_code: Option<i32>,
    ) {
        // Full suppression is intentional: TUI applications frequently emit
        // terminal-looking bytes on the alternate screen, and those bytes
        // must not mutate the primary screen's shell metadata or zones.
        if self.alt_screen_active {
            return;
        }

        let timestamp = crate::terminal::unix_millis();
        let abs_line = self.active_grid().total_lines_scrolled() + self.cursor.row;
        let close_row = abs_line.saturating_sub(1);

        // A completed child with a suspended parent is ambiguous until the
        // next lifecycle marker. A following `A` is the normal next prompt of
        // a long-lived child shell, while a consecutive `D` is the only marker
        // that proves the suspended parent command itself has returned. Keep
        // the parent suspended across any number of child command cycles and
        // pop exactly one lifecycle only for that consecutive parent `D`.
        let continuing_nested_prompt = self.shell_integration.has_pending_parent_lifecycle()
            && marker == ShellIntegrationMarker::PromptStart;
        if self.shell_integration.has_pending_parent_lifecycle()
            && marker == ShellIntegrationMarker::CommandFinished
        {
            self.confirm_nested_shell_return();
            if !self.shell_integration.restore_parent_lifecycle() {
                return;
            }
            self.in_command_output = true;
            let command = self.shell_integration.command().map(str::to_owned);
            self.open_shell_zone(ZoneType::Output, abs_line, timestamp, command);
        }

        let previous_state = self.shell_integration.state();
        match self.shell_integration.transition_marker(marker) {
            ShellMarkerTransition::Ignored => return,
            ShellMarkerTransition::Aborted => {
                self.close_shell_zone(ZoneType::Command, abs_line, None);
                self.current_command = None;
                self.in_command_output = self.shell_integration.has_pending_parent_lifecycle();
                return;
            }
            ShellMarkerTransition::Accepted => {}
        }

        match marker {
            ShellIntegrationMarker::PromptStart => {
                match previous_state {
                    ShellIntegrationState::CommandInput => {
                        self.close_shell_zone(ZoneType::Command, close_row, None);
                        self.current_command = None;
                    }
                    ShellIntegrationState::CommandOutput => {
                        self.close_shell_zone(ZoneType::Output, close_row, None);
                    }
                    _ => {}
                }

                self.push_shell_marker_event(source, marker, None, None, timestamp, abs_line);
                if continuing_nested_prompt {
                    // This is another command cycle in the same child shell,
                    // not a deeper sub-shell entry.
                } else if self.in_command_output && self.shell_depth > 0 {
                    self.shell_depth += 1;
                } else if self.shell_depth == 0 {
                    self.shell_depth = 1;
                }
                self.in_command_output = false;
                self.open_shell_zone(ZoneType::Prompt, abs_line, timestamp, None);
            }
            ShellIntegrationMarker::CommandStart => {
                let command = self.shell_integration.command().map(str::to_owned);
                self.push_shell_marker_event(
                    source,
                    marker,
                    command.clone(),
                    None,
                    timestamp,
                    abs_line,
                );
                self.close_shell_zone(ZoneType::Prompt, close_row, None);
                self.open_shell_zone(ZoneType::Command, abs_line, timestamp, command);
            }
            ShellIntegrationMarker::CommandExecuted => {
                if let Some(command) = command.and_then(validated_shell_command) {
                    self.shell_integration.set_command(command.to_string());
                }
                let command = self.shell_integration.command().map(str::to_owned);
                self.push_shell_marker_event(
                    source,
                    marker,
                    command.clone(),
                    None,
                    timestamp,
                    abs_line,
                );
                if let Some(ref mut execution) = self.current_command {
                    execution.output_start_row = Some(abs_line);
                }
                self.close_shell_zone(ZoneType::Command, close_row, None);
                self.open_shell_zone(ZoneType::Output, abs_line, timestamp, command);
                self.in_command_output = true;
            }
            ShellIntegrationMarker::CommandFinished => {
                if let Some(exit_code) = exit_code {
                    self.shell_integration.set_exit_code(exit_code);
                }
                self.push_shell_marker_event(source, marker, None, exit_code, timestamp, abs_line);
                self.close_shell_zone(ZoneType::Output, abs_line, exit_code);
                self.in_command_output = self.shell_integration.has_pending_parent_lifecycle();
            }
        }
    }

    fn push_shell_marker_event(
        &mut self,
        source: ShellIntegrationSource,
        marker: ShellIntegrationMarker,
        command: Option<String>,
        exit_code: Option<i32>,
        timestamp: u64,
        cursor_line: usize,
    ) {
        let event_type = match marker {
            ShellIntegrationMarker::PromptStart => "prompt_start",
            ShellIntegrationMarker::CommandStart => "command_start",
            ShellIntegrationMarker::CommandExecuted => "command_executed",
            ShellIntegrationMarker::CommandFinished => "command_finished",
        };
        self.terminal_events
            .push(TerminalEvent::ShellIntegrationEvent {
                source,
                event_type: event_type.to_string(),
                command,
                exit_code,
                timestamp: Some(timestamp),
                cursor_line: Some(cursor_line),
            });
    }

    fn open_shell_zone(
        &mut self,
        zone_type: ZoneType,
        abs_row: usize,
        timestamp: u64,
        command: Option<String>,
    ) {
        let zone_id = self.next_zone_id;
        self.next_zone_id += 1;
        let mut zone = Zone::new(zone_id, zone_type, abs_row, Some(timestamp));
        zone.command = command;
        self.grid.push_zone(zone);
        self.terminal_events.push(TerminalEvent::ZoneOpened {
            zone_id,
            zone_type,
            abs_row_start: abs_row,
        });
    }

    fn close_shell_zone(
        &mut self,
        expected_type: ZoneType,
        abs_row: usize,
        exit_code: Option<i32>,
    ) {
        let Some((zone_id, zone_type, abs_row_start)) = self
            .grid
            .zones()
            .iter()
            .rfind(|zone| zone.is_open() && zone.zone_type == expected_type)
            .map(|zone| (zone.id, zone.zone_type, zone.abs_row_start))
        else {
            return;
        };

        if !self.grid.close_zone(zone_id, abs_row) {
            return;
        }
        if expected_type == ZoneType::Output {
            if let Some(zone) = self
                .grid
                .zones_mut()
                .iter_mut()
                .find(|zone| zone.id == zone_id)
            {
                zone.exit_code = exit_code;
            }
        }
        let abs_row_end = self
            .grid
            .zones()
            .iter()
            .find(|zone| zone.id == zone_id)
            .map_or_else(|| abs_row.max(abs_row_start), |zone| zone.abs_row_end);
        self.terminal_events.push(TerminalEvent::ZoneClosed {
            zone_id,
            zone_type,
            abs_row_start,
            abs_row_end,
            exit_code,
        });
    }

    fn confirm_nested_shell_return(&mut self) {
        if self.shell_depth > 1 {
            // Emit the same depth transition as the historical eager detector,
            // but only after an outer `D` proves that the candidate was truly
            // nested. Missing-D recovery therefore produces no false event.
            self.terminal_events.push(TerminalEvent::SubShellDetected {
                depth: self.shell_depth,
                shell_type: None,
            });
            self.shell_depth -= 1;
            self.terminal_events.push(TerminalEvent::SubShellDetected {
                depth: self.shell_depth,
                shell_type: None,
            });
        }
    }

    /// Parse OSC 7 payload and return decoded path, hostname, username
    pub(crate) fn parse_osc7_url(
        url_str: &str,
    ) -> Option<(String, Option<String>, Option<String>)> {
        if !has_valid_percent_escapes(url_str.as_bytes()) {
            return None;
        }

        if let Ok(url) = Url::parse(url_str) {
            if url.scheme() == "file" {
                let raw_path = url.path();
                if !raw_path.is_empty() && raw_path.starts_with('/') {
                    let path = decode_osc7_component(raw_path, OSC7_CWD_MAX_BYTES)?;
                    let username = url.username();
                    let username = if username.is_empty() {
                        None
                    } else {
                        Some(decode_osc7_component(username, OSC7_USERNAME_MAX_BYTES)?)
                    };
                    let hostname = match url.host_str() {
                        Some(host) => {
                            let host = validate_osc7_decoded_component(
                                host.to_string(),
                                OSC7_HOST_MAX_BYTES,
                            )?;
                            (!host.is_empty() && !host.eq_ignore_ascii_case("localhost"))
                                .then_some(host)
                        }
                        None => None,
                    };
                    if path.starts_with('/') {
                        return Some((path, hostname, username));
                    }
                }
            }
        }

        if !url_str.starts_with("file://") {
            return None;
        }

        let mut remainder = &url_str[7..];
        if remainder.is_empty() {
            return None;
        }

        if let Some(idx) = remainder.find(['?', '#']) {
            remainder = &remainder[..idx];
        }

        let mut username = None;
        let hostname: Option<String>;
        let path: String;

        if remainder.starts_with('/') {
            path = decode_osc7_component(remainder, OSC7_CWD_MAX_BYTES)?;
            hostname = None;
        } else {
            let slash_idx = remainder.find('/')?;
            let authority = &remainder[..slash_idx];
            let path_part = &remainder[slash_idx..];

            let (user_part, host_part) = match authority.rsplit_once('@') {
                Some((user, host)) => (Some(user), host),
                None => (None, authority),
            };

            if let Some(user) = user_part {
                let decoded = decode_osc7_component(user, OSC7_USERNAME_MAX_BYTES)?;
                if !decoded.is_empty() {
                    username = Some(decoded);
                }
            }

            let host_only = host_part.split(':').next().unwrap_or("");
            let host_only = decode_osc7_component(host_only, OSC7_HOST_MAX_BYTES)?;
            if host_only.is_empty() || host_only.eq_ignore_ascii_case("localhost") {
                hostname = None;
            } else {
                hostname = Some(host_only);
            }

            path = decode_osc7_component(path_part, OSC7_CWD_MAX_BYTES)?;
        }

        if path.is_empty() || !path.starts_with('/') {
            return None;
        }

        Some((path, hostname, username))
    }
}

fn has_valid_percent_escapes(value: &[u8]) -> bool {
    let mut index = 0;
    while index < value.len() {
        if value[index] != b'%' {
            index += 1;
            continue;
        }
        let Some(high) = value.get(index + 1) else {
            return false;
        };
        let Some(low) = value.get(index + 2) else {
            return false;
        };
        if !high.is_ascii_hexdigit() || !low.is_ascii_hexdigit() {
            return false;
        }
        index += 3;
    }
    true
}

fn decode_osc7_component(value: &str, max_bytes: usize) -> Option<String> {
    let decoded = percent_decode_str(value).decode_utf8().ok()?.into_owned();
    validate_osc7_decoded_component(decoded, max_bytes)
}

fn validate_osc7_decoded_component(value: String, max_bytes: usize) -> Option<String> {
    (value.len() <= max_bytes && !value.chars().any(char::is_control)).then_some(value)
}

fn validated_shell_command(value: &str) -> Option<&str> {
    if value.chars().any(char::is_control) || value.chars().count() > SHELL_COMMAND_MAX_CHARS {
        return None;
    }
    let value = value.trim();
    (!value.is_empty()).then_some(value)
}

fn decode_osc633_field(value: &[u8], max_bytes: usize) -> Option<String> {
    if value.is_empty() || value.len() > max_bytes {
        return None;
    }

    let mut decoded = Vec::with_capacity(value.len());
    let mut index = 0;
    while index < value.len() {
        if value[index] == b'\\' {
            match value.get(index + 1).copied() {
                Some(b'x') => {
                    let high = value.get(index + 2).copied().and_then(hex_nibble)?;
                    let low = value.get(index + 3).copied().and_then(hex_nibble)?;
                    decoded.push((high << 4) | low);
                    index += 4;
                }
                Some(b'\\') => {
                    decoded.push(b'\\');
                    index += 2;
                }
                _ => {
                    // Preserve the historical behavior for unknown escapes.
                    decoded.push(value[index]);
                    index += 1;
                }
            }
        } else {
            decoded.push(value[index]);
            index += 1;
        }
        if decoded.len() > max_bytes {
            return None;
        }
    }

    let decoded = String::from_utf8(decoded).ok()?;
    (!decoded.chars().any(char::is_control)).then_some(decoded)
}

const fn hex_nibble(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shell_events(term: &mut Terminal) -> Vec<(ShellIntegrationSource, String, Option<i32>)> {
        term.poll_events()
            .into_iter()
            .filter_map(|event| match event {
                TerminalEvent::ShellIntegrationEvent {
                    source,
                    event_type,
                    exit_code,
                    ..
                } => Some((source, event_type, exit_code)),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn osc133_normal_cycle_advances_once_and_binds_exit_code() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b]133;A\x07");
        term.process(b"\x1b]133;B\x1b\\");
        term.process(b"\x1b]133;C;printf ok\x07");
        term.process(b"\x1b]133;D;7\x1b\\");

        assert_eq!(
            term.shell_integration.state(),
            ShellIntegrationState::Finished
        );
        assert_eq!(
            term.shell_integration.marker(),
            Some(ShellIntegrationMarker::CommandFinished)
        );
        assert_eq!(term.shell_integration.command(), Some("printf ok"));
        assert_eq!(term.shell_integration.exit_code(), Some(7));
        assert!(!term.in_command_output);
        assert_eq!(
            term.get_zones()
                .iter()
                .map(|zone| zone.zone_type)
                .collect::<Vec<_>>(),
            vec![ZoneType::Prompt, ZoneType::Command, ZoneType::Output]
        );
        assert_eq!(term.get_zones()[2].exit_code, Some(7));
        assert_eq!(
            shell_events(&mut term),
            vec![
                (ShellIntegrationSource::Osc133, "prompt_start".into(), None),
                (ShellIntegrationSource::Osc133, "command_start".into(), None),
                (
                    ShellIntegrationSource::Osc133,
                    "command_executed".into(),
                    None
                ),
                (
                    ShellIntegrationSource::Osc133,
                    "command_finished".into(),
                    Some(7)
                ),
            ]
        );
    }

    #[test]
    fn osc133_d_after_b_aborts_without_command_completion() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b]133;A\x07");
        term.process(b"\x1b]133;B\x07");
        term.process(b"\x1b]133;D;0\x07");

        assert_eq!(
            term.shell_integration.state(),
            ShellIntegrationState::Aborted
        );
        assert_eq!(term.shell_integration.marker(), None);
        assert_eq!(term.shell_integration.exit_code(), None);
        assert_eq!(term.get_zones().len(), 2);
        assert_eq!(term.get_zones()[1].zone_type, ZoneType::Command);
        assert_eq!(term.get_zones()[1].exit_code, None);
        assert_eq!(
            shell_events(&mut term),
            vec![
                (ShellIntegrationSource::Osc133, "prompt_start".into(), None),
                (ShellIntegrationSource::Osc133, "command_start".into(), None),
            ]
        );
    }

    #[test]
    fn osc133_d_without_command_is_ignored() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b]133;D;23\x07");

        assert_eq!(term.shell_integration.state(), ShellIntegrationState::Idle);
        assert_eq!(term.shell_integration.exit_code(), None);
        assert!(term.get_zones().is_empty());
        assert!(shell_events(&mut term).is_empty());
    }

    #[test]
    fn osc133_duplicate_a_is_idempotent() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b]133;A\x07\x1b]133;A\x1b\\");

        assert_eq!(
            term.shell_integration.state(),
            ShellIntegrationState::Prompt
        );
        assert_eq!(term.get_zones().len(), 1);
        assert_eq!(
            shell_events(&mut term),
            vec![(ShellIntegrationSource::Osc133, "prompt_start".into(), None)]
        );
    }

    #[test]
    fn osc133_b_without_a_is_ignored() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b]133;B\x07");

        assert_eq!(term.shell_integration.state(), ShellIntegrationState::Idle);
        assert!(term.get_zones().is_empty());
        assert!(shell_events(&mut term).is_empty());
    }

    #[test]
    fn osc133_c_without_b_is_ignored() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b]133;C;stale\x07");
        term.process(b"\x1b]133;A\x07");
        term.process(b"\x1b]133;C;still-stale\x07");

        assert_eq!(
            term.shell_integration.state(),
            ShellIntegrationState::Prompt
        );
        assert_eq!(term.shell_integration.command(), None);
        assert_eq!(term.get_zones().len(), 1);
        assert_eq!(
            shell_events(&mut term),
            vec![(ShellIntegrationSource::Osc133, "prompt_start".into(), None)]
        );
    }

    #[test]
    fn osc133_duplicate_c_and_d_do_not_duplicate_events_or_zones() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b]133;A\x07");
        term.process(b"\x1b]133;B\x07");
        term.process(b"\x1b]133;C;first\x07");
        term.process(b"\x1b]133;C;stale\x07");
        term.process(b"\x1b]133;D;5\x07");
        term.process(b"\x1b]133;D;99\x07");

        assert_eq!(term.shell_integration.command(), Some("first"));
        assert_eq!(term.shell_integration.exit_code(), Some(5));
        assert_eq!(term.get_zones().len(), 3);
        assert_eq!(term.get_zones()[2].exit_code, Some(5));
        let events = term.poll_events();
        assert_eq!(
            events
                .iter()
                .filter(|event| matches!(event, TerminalEvent::ShellIntegrationEvent { .. }))
                .count(),
            4
        );
        assert_eq!(
            events
                .iter()
                .filter(|event| matches!(event, TerminalEvent::ZoneClosed { .. }))
                .count(),
            3
        );
    }

    #[test]
    fn osc133_is_fully_suppressed_on_alt_screen() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b[?1049h");
        term.poll_events();
        term.process(b"\x1b]133;A\x07");
        term.process(b"\x1b]133;B\x07");
        term.process(b"\x1b]133;C;false-positive\x07");
        term.process(b"\x1b]133;D;1\x07");

        assert_eq!(term.shell_integration.state(), ShellIntegrationState::Idle);
        assert_eq!(term.shell_integration.command(), None);
        assert_eq!(term.shell_integration.exit_code(), None);
        assert_eq!(term.shell_depth, 0);
        assert!(!term.in_command_output);
        assert!(term.get_zones().is_empty());
        assert!(shell_events(&mut term).is_empty());

        term.process(b"\x1b[?1049l");
        term.process(b"\x1b]133;A\x07");
        assert_eq!(
            term.shell_integration.state(),
            ShellIntegrationState::Prompt
        );
        assert_eq!(term.get_zones().len(), 1);
    }

    #[test]
    fn shared_marker_helper_preserves_osc633_source() {
        let mut term = Terminal::new(80, 24);

        term.handle_shell_marker(
            ShellIntegrationSource::Osc633,
            ShellIntegrationMarker::PromptStart,
            None,
            None,
        );
        term.handle_shell_marker(
            ShellIntegrationSource::Osc633,
            ShellIntegrationMarker::CommandStart,
            None,
            None,
        );
        term.handle_shell_marker(
            ShellIntegrationSource::Osc633,
            ShellIntegrationMarker::CommandExecuted,
            Some("echo reusable"),
            None,
        );
        term.handle_shell_marker(
            ShellIntegrationSource::Osc633,
            ShellIntegrationMarker::CommandFinished,
            None,
            Some(0),
        );

        assert!(shell_events(&mut term)
            .iter()
            .all(|(source, _, _)| *source == ShellIntegrationSource::Osc633));
    }

    #[test]
    fn osc633_expected_nonce_rejects_missing_or_mismatched_command_metadata() {
        let mut term = Terminal::new(80, 24);
        term.shell_integration.set_command("sentinel".to_string());
        assert!(term.set_osc633_expected_nonce(Some("expected-633".to_string())));
        assert!(term.osc633_expected_nonce_configured());

        term.process(b"\x1b]633;E;missing\x07");
        term.process(b"\x1b]633;E;mismatch;wrong-633\x1b\\");
        assert_eq!(term.shell_integration.command(), Some("sentinel"));

        term.process(b"\x1b]633;E;accepted;expected-633\x1b\\");
        assert_eq!(term.shell_integration.command(), Some("accepted"));

        assert!(!term.set_osc633_expected_nonce(Some(String::new())));
        assert!(!term.set_osc633_expected_nonce(Some("bad;nonce".to_string())));
        assert_eq!(term.shell_integration.command(), Some("accepted"));
        assert!(!format!("{:?}", term.shell_integration).contains("expected-633"));
    }

    #[test]
    fn osc633_fields_decode_official_backslash_escape() {
        let mut term = Terminal::new(80, 24);
        term.process(b"\x1b]633;E;printf \\\\path\x1b\\");
        term.process(b"\x1b]633;P;Cwd=/tmp/a\\\\b\x1b\\");

        assert_eq!(term.shell_integration.command(), Some(r"printf \path"));
        assert_eq!(term.shell_integration.cwd(), Some(r"/tmp/a\b"));
    }

    #[test]
    fn nested_shell_completion_restores_outer_output_lifecycle() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;outer\x07");
        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;inner\x07");
        assert_eq!(term.shell_depth, 2);
        assert_eq!(term.shell_integration.suspended_lifecycle_count(), 1);

        term.process(b"\x1b]133;D;0\x07");
        assert_eq!(
            term.shell_integration.state(),
            ShellIntegrationState::Finished
        );
        assert_eq!(term.shell_integration.command(), Some("inner"));
        assert_eq!(term.shell_integration.suspended_lifecycle_count(), 1);
        assert_eq!(term.shell_depth, 2);
        assert!(term.in_command_output);
        assert!(term.get_zones().iter().all(|zone| zone.is_closed()));

        term.process(b"\x1b]133;D;9\x07");
        assert_eq!(
            term.shell_integration.state(),
            ShellIntegrationState::Finished
        );
        assert_eq!(term.shell_integration.command(), Some("outer"));
        assert_eq!(term.shell_integration.exit_code(), Some(9));
        assert_eq!(term.shell_integration.suspended_lifecycle_count(), 0);
        assert_eq!(term.shell_depth, 1);
        assert!(!term.in_command_output);
        let events = term.poll_events();
        let finished_codes = events
            .iter()
            .filter_map(|event| match event {
                TerminalEvent::ShellIntegrationEvent {
                    event_type,
                    exit_code,
                    ..
                } if event_type == "command_finished" => Some(*exit_code),
                _ => None,
            })
            .collect::<Vec<_>>();
        assert_eq!(finished_codes, vec![Some(0), Some(9)]);
        let depths = events
            .iter()
            .filter_map(|event| match event {
                TerminalEvent::SubShellDetected { depth, .. } => Some(*depth),
                _ => None,
            })
            .collect::<Vec<_>>();
        assert_eq!(depths, vec![2, 1]);
    }

    #[test]
    fn nested_shell_multiple_commands_preserve_outer_until_consecutive_d() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;outer\x07");
        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;inner-one\x07");
        term.process(b"\x1b]133;D;0\x07");
        assert_eq!(term.shell_integration.suspended_lifecycle_count(), 1);
        assert_eq!(term.shell_depth, 2);
        assert!(term.in_command_output);

        // A after the child's D is its next prompt, not evidence that the
        // suspended outer lifecycle was malformed or missing a terminator.
        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;inner-two\x07");
        term.process(b"\x1b]133;D;3\x07");
        assert_eq!(term.shell_integration.command(), Some("inner-two"));
        assert_eq!(term.shell_integration.exit_code(), Some(3));
        assert_eq!(term.shell_integration.suspended_lifecycle_count(), 1);
        assert_eq!(term.shell_depth, 2);
        assert!(term.in_command_output);

        let before_outer_d = term.poll_events();
        assert!(before_outer_d
            .iter()
            .all(|event| !matches!(event, TerminalEvent::SubShellDetected { .. })));

        // Only the consecutive D can belong to the suspended parent.
        term.process(b"\x1b]133;D;9\x07");
        assert_eq!(term.shell_integration.command(), Some("outer"));
        assert_eq!(term.shell_integration.exit_code(), Some(9));
        assert_eq!(term.shell_integration.suspended_lifecycle_count(), 0);
        assert_eq!(term.shell_depth, 1);
        assert!(!term.in_command_output);
        let depths = term
            .poll_events()
            .into_iter()
            .filter_map(|event| match event {
                TerminalEvent::SubShellDetected { depth, .. } => Some(depth),
                _ => None,
            })
            .collect::<Vec<_>>();
        assert_eq!(depths, vec![2, 1]);
    }

    #[test]
    fn nested_shell_abort_restores_outer_output_lifecycle() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;outer\x07");
        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;D;0\x07");

        assert_eq!(
            term.shell_integration.state(),
            ShellIntegrationState::Aborted
        );
        assert_eq!(term.shell_integration.suspended_lifecycle_count(), 1);
        assert_eq!(term.shell_depth, 2);
        assert!(term.in_command_output);

        term.process(b"\x1b]133;D;4\x07");
        assert_eq!(term.shell_integration.command(), Some("outer"));
        assert_eq!(term.shell_integration.exit_code(), Some(4));
        assert_eq!(term.shell_integration.suspended_lifecycle_count(), 0);
        assert_eq!(term.shell_depth, 1);
        assert!(!term.in_command_output);
    }

    #[test]
    fn prompt_after_completed_candidate_keeps_next_command_clean() {
        let mut term = Terminal::new(80, 24);

        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;stale\x07");
        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;recovered\x07");
        term.process(b"\x1b]133;D;0\x07");
        assert_eq!(term.shell_integration.suspended_lifecycle_count(), 1);

        // The stream is indistinguishable from a long-lived child shell. Keep
        // the candidate parent latent so A can safely start the next command,
        // but do not emit a false sub-shell transition without a parent D.
        term.process(b"\x1b]133;A\x07");
        assert_eq!(
            term.shell_integration.state(),
            ShellIntegrationState::Prompt
        );
        assert_eq!(term.shell_integration.suspended_lifecycle_count(), 1);
        assert_eq!(term.shell_depth, 2);
        assert!(!term.in_command_output);

        term.process(b"\x1b]133;B\x07\x1b]133;C;fresh\x07\x1b]133;D;3\x07");
        assert_eq!(term.shell_integration.command(), Some("fresh"));
        assert_eq!(term.shell_integration.exit_code(), Some(3));
        assert_eq!(term.shell_integration.suspended_lifecycle_count(), 1);
        assert!(term
            .poll_events()
            .iter()
            .all(|event| !matches!(event, TerminalEvent::SubShellDetected { .. })));
    }

    #[test]
    fn long_running_output_zone_survives_ring_eviction_until_d() {
        let mut term = Terminal::with_scrollback(16, 3, 5);
        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;long\x07");
        let _ = term.poll_events();

        for line in 0..24 {
            term.process(format!("line-{line:02}\r\n").as_bytes());
        }

        let retained_floor = term
            .active_grid()
            .total_lines_scrolled()
            .saturating_sub(term.active_grid().scrollback_len());
        let output = term
            .get_zones()
            .iter()
            .find(|zone| zone.zone_type == ZoneType::Output)
            .expect("active output zone must not be evicted");
        assert!(output.is_open());
        assert!(output.abs_row_start < retained_floor);
        assert!(output.abs_row_end >= retained_floor);

        term.process(b"\x1b]133;D;7\x07");
        let output = term
            .get_zones()
            .iter()
            .find(|zone| zone.zone_type == ZoneType::Output)
            .expect("closed retained output zone");
        assert!(output.is_closed());
        assert_eq!(output.exit_code, Some(7));
        assert!(output.abs_row_end >= output.abs_row_start);
        assert!(term
            .get_zone_text(output.abs_row_start)
            .is_some_and(|text| text.contains("line-")));
    }

    #[test]
    fn clear_scrollback_invalidates_zones_and_emits_evictions() {
        let mut term = Terminal::with_scrollback(16, 3, 8);
        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;clear\x07");
        term.process(b"one\r\ntwo\r\nthree\r\n");
        term.process(b"\x1b]133;D;0\x07");
        let zone_count = term.get_zones().len();
        assert!(zone_count > 0);
        let _ = term.poll_events();

        term.process(b"\x1b[3J");

        assert!(term.get_zones().is_empty());
        let evicted = term
            .poll_events()
            .into_iter()
            .filter(|event| matches!(event, TerminalEvent::ZoneScrolledOut { .. }))
            .count();
        assert_eq!(evicted, zone_count);
    }

    #[test]
    fn clear_scrollback_evictions_reach_subscription_filter() {
        let mut term = Terminal::with_scrollback(16, 3, 8);
        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;clear\x07");
        term.process(b"output\x1b]133;D;0\x07");
        let zone_count = term.get_zones().len();
        assert!(zone_count > 0);
        let _ = term.poll_events();

        term.set_event_subscription(std::collections::HashSet::from([
            crate::terminal::TerminalEventKind::ZoneScrolledOut,
        ]));
        term.process(b"\x1b[3J");

        let subscribed = term.poll_subscribed_events();
        assert_eq!(
            subscribed
                .iter()
                .filter(|event| matches!(event, TerminalEvent::ZoneScrolledOut { .. }))
                .count(),
            zone_count
        );
        assert!(term
            .poll_events()
            .iter()
            .all(|event| !matches!(event, TerminalEvent::ZoneScrolledOut { .. })));
    }

    #[test]
    fn width_reflow_invalidates_physical_zone_coordinates() {
        let mut term = Terminal::new(16, 4);
        term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;resize\x07");
        term.process(b"output\x1b]133;D;0\x07");
        let zone_count = term.get_zones().len();
        let _ = term.poll_events();

        term.resize(8, 4);

        assert!(term.get_zones().is_empty());
        let evicted = term
            .poll_events()
            .into_iter()
            .filter(|event| matches!(event, TerminalEvent::ZoneScrolledOut { .. }))
            .count();
        assert_eq!(evicted, zone_count);
    }

    #[test]
    fn same_row_shell_cycles_keep_zone_history_bounded() {
        let mut term = Terminal::new(80, 24);
        let cycle = b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;same-row\x07\x1b]133;D;0\x07";
        let mut payload = Vec::with_capacity(cycle.len() * 5_000);
        for _ in 0..5_000 {
            payload.extend_from_slice(cycle);
        }

        term.process(&payload);

        assert!(term.get_zones().len() <= crate::grid::MAX_SEMANTIC_ZONES);
        assert!(term.get_zones().last().unwrap().is_closed());
        assert!(term
            .poll_events()
            .iter()
            .any(|event| matches!(event, TerminalEvent::ZoneScrolledOut { .. })));
    }

    #[test]
    fn osc7_rejects_malformed_percent_escapes_without_state_change() {
        let mut term = Terminal::new(80, 24);

        for invalid in [
            b"\x1b]7;file:///tmp/%ZZ/bad\x07".as_slice(),
            b"\x1b]7;file:///tmp/trailing%\x07".as_slice(),
            b"\x1b]7;file:///tmp/short%2\x07".as_slice(),
            b"\x1b]7;file:///tmp/control%01bad\x07".as_slice(),
            b"\x1b]7;file:///tmp/c1%C2%85bad\x07".as_slice(),
            b"\x1b]7;file:///tmp/non-utf8%FFbad\x07".as_slice(),
            b"\x1b]7;file://user%0Aname@example.test/tmp\x07".as_slice(),
            b"\x1b]7;file://bad%0Ahost/tmp\x07".as_slice(),
        ] {
            term.process(invalid);
        }
        assert!(term.shell_integration.cwd().is_none());
        assert!(term
            .poll_events()
            .iter()
            .all(|event| !matches!(event, TerminalEvent::CwdChanged(_))));

        term.process(b"\x1b]7;file:///tmp/valid%25path\x07");
        assert_eq!(term.shell_integration.cwd(), Some("/tmp/valid%path"));

        assert!(Terminal::parse_osc7_url("file:///tmp/%01bad").is_none());
        assert!(Terminal::parse_osc7_url("file:///tmp/%C2%85bad").is_none());
        assert!(Terminal::parse_osc7_url("file:///tmp/%FFbad").is_none());
        assert!(Terminal::parse_osc7_url("file://user%0Aname@example.test/tmp").is_none());
        let oversized = format!("file:///{}", "x".repeat(OSC7_CWD_MAX_BYTES + 1));
        assert!(Terminal::parse_osc7_url(&oversized).is_none());
        let oversized_user = format!(
            "file://{}@example.test/tmp",
            "u".repeat(OSC7_USERNAME_MAX_BYTES + 1)
        );
        assert!(Terminal::parse_osc7_url(&oversized_user).is_none());
        let oversized_host = format!("file://{}/tmp", "h".repeat(OSC7_HOST_MAX_BYTES + 1));
        assert!(Terminal::parse_osc7_url(&oversized_host).is_none());
    }

    #[test]
    fn osc133_command_metadata_rejects_controls_and_excessive_runes() {
        let mut control = Terminal::new(80, 24);
        control.process(b"\x1b]133;A\x07\x1b]133;B\x07");
        control.handle_shell_marker(
            ShellIntegrationSource::Osc133,
            ShellIntegrationMarker::CommandExecuted,
            Some("printf\u{85}spoofed"),
            None,
        );
        assert_eq!(
            control.shell_integration.state(),
            ShellIntegrationState::CommandOutput
        );
        assert_eq!(control.shell_integration.command(), None);
        assert!(control.poll_events().iter().all(|event| !matches!(
            event,
            TerminalEvent::ShellIntegrationEvent {
                event_type,
                command: Some(_),
                ..
            } if event_type == "command_executed"
        )));

        let mut oversized = Terminal::new(80, 24);
        oversized.process(b"\x1b]133;A\x07\x1b]133;B\x07");
        let command = "界".repeat(SHELL_COMMAND_MAX_CHARS + 1);
        oversized.handle_shell_marker(
            ShellIntegrationSource::Osc133,
            ShellIntegrationMarker::CommandExecuted,
            Some(&command),
            None,
        );
        assert_eq!(oversized.shell_integration.command(), None);
    }
}
