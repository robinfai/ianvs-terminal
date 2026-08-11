use super::{TerminalState, retained_row_for_abs_row, selection_text_for_terminal};
use crate::model::{TerminalEmulation, TerminalSelectionRequest};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use par_term_emu_core_rust::terminal::{
    Terminal, TerminalEvent as ParserTerminalEvent, TransferDirection, TransferStatus,
};
use std::collections::BTreeMap;

pub(super) const OSC5522_MAX_TOTAL_BYTES: usize = 4 * 1024 * 1024;
pub(super) const OSC5522_MAX_CHUNK_BYTES: usize = 4096;
pub(super) const OSC5522_MAX_MIME_TYPES: usize = 64;
pub(super) const OSC5522_MAX_MIME_BYTES: usize = 255;
pub(super) const OSC5522_MAX_ID_BYTES: usize = 128;
pub(super) const OSC5522_MAX_PASSWORD_BYTES: usize = 256;
pub(super) const OSC5522_MAX_APPLICATION_NAME_BYTES: usize = 256;
pub(super) const ITERM_CLIPBOARD_MAX_BYTES: usize = 4 * 1024 * 1024;
pub(super) const ITERM_FILE_DOWNLOAD_MAX_BYTES: usize = 16 * 1024 * 1024;
pub(super) const ITERM_FILE_DOWNLOAD_MAX_PENDING: usize = 8;

#[derive(Clone, Debug)]
pub(super) enum CallbackEvent {
    Resize {
        rows: u16,
        cols: u16,
    },
    ClipboardCopy {
        selection: String,
        data: String,
    },
    ClipboardPasteRequest {
        selection: String,
    },
    ItermClipboardCopy {
        selection: String,
        data: Option<String>,
        streaming: bool,
    },
    ClipboardMimeWrite {
        payload: serde_json::Value,
    },
    ClipboardMimeReadRequest {
        payload: serde_json::Value,
    },
    ClipboardMimeError {
        payload: serde_json::Value,
    },
    ShellHook {
        payload: serde_json::Value,
    },
    ShellContext {
        payload: serde_json::Value,
    },
    ShellCommand {
        payload: serde_json::Value,
    },
    ShellUserVar {
        name: String,
        value: String,
    },
    CellSizeReportRequest,
    ClearCapturedOutput,
    ReportVariableRequest {
        payload: serde_json::Value,
    },
    OpenUrlRequest {
        payload: serde_json::Value,
    },
    AttentionRequest {
        payload: serde_json::Value,
    },
    SessionAnnotation {
        payload: serde_json::Value,
    },
    SessionNotification {
        source: String,
        action: String,
        identifier: Option<String>,
        title: String,
        message: String,
        application_name: Option<String>,
        notification_types: Vec<String>,
        expires_after_ms: Option<u32>,
        report_activation: bool,
        report_close: bool,
        buttons: Vec<String>,
    },
    SessionProgress {
        payload: serde_json::Value,
    },
    SessionBadge {
        text: Option<String>,
    },
    SessionTabStatus {
        payload: serde_json::Value,
    },
    TerminalContext {
        payload: serde_json::Value,
    },
    DragDropCommand {
        payload: serde_json::Value,
    },
    FileDownload {
        payload: serde_json::Value,
    },
    FileDownloadFailed {
        payload: serde_json::Value,
    },
    FileUploadDenied {
        payload: serde_json::Value,
    },
    SessionReset,
    Bell,
}

#[derive(Clone, Debug)]
struct Osc5522WriteState {
    location: String,
    id: Option<String>,
    password: Option<String>,
    application_name: Option<String>,
    data_by_mime: BTreeMap<String, Vec<u8>>,
    aliases_by_mime: BTreeMap<String, Vec<String>>,
    last_mime: Option<String>,
    total_bytes: usize,
    failed: bool,
}

#[derive(Clone, Debug)]
pub(super) struct ItermClipboardCaptureState {
    selection: String,
    data: Vec<u8>,
    overflowed: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum ItermClipboardBoundary {
    None,
    Start(String),
    End,
}

#[derive(Clone, Default)]
pub(super) struct HostProtocolState {
    pub(super) buffer: Vec<u8>,
    pub(super) application_keypad: bool,
    osc5522_write: Option<Osc5522WriteState>,
    pub(super) iterm_clipboard_capture: Option<ItermClipboardCaptureState>,
}

fn iterm_clipboard_boundary(payload: &[u8]) -> ItermClipboardBoundary {
    let Some(command) = payload.strip_prefix(b"1337;") else {
        return ItermClipboardBoundary::None;
    };
    if command == b"EndCopy" {
        return ItermClipboardBoundary::End;
    }
    let name = if command == b"CopyToClipboard" {
        ""
    } else if let Some(name) = command.strip_prefix(b"CopyToClipboard=") {
        if name.len() > 32
            || name
                .iter()
                .any(|byte| !byte.is_ascii() || byte.is_ascii_control())
        {
            return ItermClipboardBoundary::None;
        }
        let Ok(name) = std::str::from_utf8(name) else {
            return ItermClipboardBoundary::None;
        };
        name
    } else {
        return ItermClipboardBoundary::None;
    };

    let selection = match name {
        "find" => "find",
        "font" => "font",
        // iTerm2 routes the documented empty/rule value and unknown bounded
        // names to the general pasteboard. `general`, `clipboard`, and the
        // historical source spelling `ruler` are accepted aliases.
        _ => "c",
    };
    ItermClipboardBoundary::Start(selection.to_string())
}

impl HostProtocolState {
    pub(super) fn observe(
        &mut self,
        bytes: &[u8],
        emulation: TerminalEmulation,
    ) -> Vec<CallbackEvent> {
        if self.buffer.is_empty()
            && self.iterm_clipboard_capture.is_none()
            && !bytes.contains(&0x1b)
        {
            return Vec::new();
        }

        self.buffer.extend_from_slice(bytes);
        let mut events = Vec::new();
        let mut index = 0usize;
        let mut capture_segment_start = self.iterm_clipboard_capture.as_ref().map(|_| 0usize);

        while index < self.buffer.len() {
            if self.buffer[index] != 0x1b {
                index += 1;
                continue;
            }

            if let Some(start) = capture_segment_start.take() {
                self.append_iterm_clipboard_range(start, index);
            }

            if index + 1 >= self.buffer.len() {
                break;
            }

            let sequence_start = index;
            match self.buffer[index + 1] {
                b'=' => {
                    self.application_keypad = true;
                    index += 2;
                    self.append_iterm_clipboard_range(sequence_start, index);
                }
                b'>' => {
                    self.application_keypad = false;
                    index += 2;
                    self.append_iterm_clipboard_range(sequence_start, index);
                }
                b'c' => {
                    self.application_keypad = false;
                    self.osc5522_write = None;
                    self.iterm_clipboard_capture = None;
                    index += 2;
                }
                b']' => match self.consume_osc(index, emulation, &mut events) {
                    Some((next, boundary)) => {
                        match boundary {
                            ItermClipboardBoundary::None => {
                                self.append_iterm_clipboard_range(sequence_start, next);
                            }
                            ItermClipboardBoundary::Start(selection) => {
                                self.iterm_clipboard_capture = Some(ItermClipboardCaptureState {
                                    selection,
                                    data: Vec::new(),
                                    overflowed: false,
                                });
                            }
                            ItermClipboardBoundary::End => {
                                self.finish_iterm_clipboard_capture(&mut events);
                            }
                        }
                        index = next;
                    }
                    None => break,
                },
                b'P' => match self.consume_dcs(index, emulation, &mut events) {
                    Some(next) => {
                        index = next;
                        self.append_iterm_clipboard_range(sequence_start, index);
                    }
                    None => break,
                },
                b'[' => match self.consume_csi(index, emulation, &mut events) {
                    Some(next) => {
                        index = next;
                        self.append_iterm_clipboard_range(sequence_start, index);
                    }
                    None => break,
                },
                _ => {
                    index += 2;
                    self.append_iterm_clipboard_range(sequence_start, index);
                }
            }
            capture_segment_start = self.iterm_clipboard_capture.as_ref().map(|_| index);
        }

        if let Some(start) = capture_segment_start {
            self.append_iterm_clipboard_range(start, index);
        }

        if index > 0 {
            self.buffer.drain(..index);
        } else if self.buffer.len() > 4096 {
            let keep = 4096usize.min(self.buffer.len());
            self.buffer.drain(..self.buffer.len() - keep);
        }

        events
    }

    fn append_iterm_clipboard_range(&mut self, start: usize, end: usize) {
        if start >= end {
            return;
        }
        let Some(capture) = self.iterm_clipboard_capture.as_mut() else {
            return;
        };
        if capture.overflowed {
            return;
        }
        let bytes = &self.buffer[start..end];
        let Some(new_len) = capture.data.len().checked_add(bytes.len()) else {
            capture.data.clear();
            capture.overflowed = true;
            return;
        };
        if new_len > ITERM_CLIPBOARD_MAX_BYTES {
            capture.data.clear();
            capture.overflowed = true;
            return;
        }
        capture.data.extend_from_slice(bytes);
    }

    fn finish_iterm_clipboard_capture(&mut self, events: &mut Vec<CallbackEvent>) {
        let Some(capture) = self.iterm_clipboard_capture.take() else {
            return;
        };
        events.push(CallbackEvent::ItermClipboardCopy {
            selection: capture.selection,
            data: (!capture.overflowed).then(|| BASE64_STANDARD.encode(capture.data)),
            streaming: true,
        });
    }

    fn consume_osc(
        &mut self,
        start: usize,
        emulation: TerminalEmulation,
        events: &mut Vec<CallbackEvent>,
    ) -> Option<(usize, ItermClipboardBoundary)> {
        let mut cursor = start + 2;
        let mut terminator_len = 0usize;
        let mut terminator_start = 0usize;

        while cursor < self.buffer.len() {
            match self.buffer[cursor] {
                0x07 => {
                    terminator_start = cursor;
                    terminator_len = 1;
                    break;
                }
                0x1b if cursor + 1 < self.buffer.len() && self.buffer[cursor + 1] == b'\\' => {
                    terminator_start = cursor;
                    terminator_len = 2;
                    break;
                }
                _ => {
                    cursor += 1;
                }
            }
        }

        if terminator_len == 0 {
            return None;
        }

        let payload = self.buffer[start + 2..terminator_start].to_vec();
        let boundary = if emulation == TerminalEmulation::Xterm256 {
            iterm_clipboard_boundary(&payload)
        } else {
            ItermClipboardBoundary::None
        };
        if emulation == TerminalEmulation::Xterm256 {
            self.handle_osc_payload(&payload, events);
        }

        Some((terminator_start + terminator_len, boundary))
    }

    fn consume_dcs(
        &mut self,
        start: usize,
        emulation: TerminalEmulation,
        events: &mut Vec<CallbackEvent>,
    ) -> Option<usize> {
        let mut cursor = start + 2;
        let mut terminator_start = 0usize;

        while cursor < self.buffer.len() {
            if self.buffer[cursor] == 0x1b
                && cursor + 1 < self.buffer.len()
                && self.buffer[cursor + 1] == b'\\'
            {
                terminator_start = cursor;
                break;
            }
            cursor += 1;
        }

        if terminator_start == 0 {
            return None;
        }

        if emulation == TerminalEmulation::Xterm256 {
            let payload = self.buffer[start + 2..terminator_start].to_vec();
            self.handle_dcs_payload(&payload, events);
        }

        Some(terminator_start + 2)
    }

    fn handle_dcs_payload(&self, payload: &[u8], events: &mut Vec<CallbackEvent>) {
        let mut parts = payload.splitn(2, |byte| *byte == b';');
        let command = parts.next().unwrap_or_default();
        let encoded = parts.next().unwrap_or_default();

        if command != b"hook" || encoded.is_empty() || encoded.len() % 2 != 0 {
            return;
        }

        let mut json_bytes = Vec::with_capacity(encoded.len() / 2);
        for chunk in encoded.chunks_exact(2) {
            let Some(high) = hex_nibble(chunk[0]) else {
                return;
            };
            let Some(low) = hex_nibble(chunk[1]) else {
                return;
            };
            json_bytes.push((high << 4) | low);
        }

        let Ok(json) = String::from_utf8(json_bytes) else {
            return;
        };
        let Ok(value) = serde_json::from_str::<serde_json::Value>(&json) else {
            return;
        };
        if value.is_object() {
            events.push(CallbackEvent::ShellHook { payload: value });
        }
    }

    fn handle_osc_payload(&mut self, payload: &[u8], events: &mut Vec<CallbackEvent>) {
        let mut parts = payload.splitn(2, |byte| *byte == b';');
        let command = parts.next().unwrap_or_default();
        let remainder = parts.next().unwrap_or_default();

        match command {
            b"52" => {
                let mut args = remainder.splitn(2, |byte| *byte == b';');
                let selection =
                    String::from_utf8_lossy(args.next().unwrap_or_default()).into_owned();
                let data = args
                    .next()
                    .map(|value| String::from_utf8_lossy(value).into_owned());
                let selection = if selection.is_empty() {
                    "c".to_string()
                } else {
                    selection
                };

                if let Some(data) = data {
                    if data == "?" {
                        events.push(CallbackEvent::ClipboardPasteRequest { selection });
                    } else {
                        events.push(CallbackEvent::ClipboardCopy { selection, data });
                    }
                }
            }
            b"5522" => self.handle_osc5522(remainder, events),
            b"9" => {
                if let Some(payload) = primary_progress_payload_from_osc9(remainder) {
                    events.push(CallbackEvent::SessionProgress { payload });
                }
            }
            b"1337" => {
                if let Some(encoded) = remainder.strip_prefix(b"Copy=:") {
                    events.push(CallbackEvent::ItermClipboardCopy {
                        selection: "c".to_string(),
                        data: std::str::from_utf8(encoded).ok().map(str::to_string),
                        streaming: false,
                    });
                } else if let Ok(data) = std::str::from_utf8(remainder)
                    && let Some(payload) = shell_context_payload_from_current_dir(data)
                {
                    events.push(CallbackEvent::ShellContext { payload });
                }
            }
            _ => {}
        }
    }

    fn handle_osc5522(&mut self, remainder: &[u8], events: &mut Vec<CallbackEvent>) {
        let mut fields = remainder.splitn(2, |byte| *byte == b';');
        let metadata = fields.next().unwrap_or_default();
        let payload = fields.next().unwrap_or_default();
        let Ok(metadata) = std::str::from_utf8(metadata) else {
            self.fail_osc5522_write("EINVAL", None, events);
            return;
        };
        let Some(metadata) = parse_osc5522_metadata(metadata) else {
            self.fail_osc5522_write("EINVAL", None, events);
            return;
        };
        let request_type = metadata.get("type").map(String::as_str).unwrap_or_default();
        let id = metadata
            .get("id")
            .and_then(|value| sanitized_osc5522_id(value));
        match request_type {
            "write" => {
                if !payload.is_empty() {
                    events.push(osc5522_error_event("write", "EINVAL", id));
                    self.osc5522_write = None;
                    return;
                }
                let Some(location) = osc5522_location(&metadata) else {
                    events.push(osc5522_error_event("write", "EINVAL", id));
                    self.osc5522_write = None;
                    return;
                };
                let Some((password, application_name)) = osc5522_credentials(&metadata) else {
                    events.push(osc5522_error_event("write", "EINVAL", id));
                    self.osc5522_write = None;
                    return;
                };
                self.osc5522_write = Some(Osc5522WriteState {
                    location,
                    id,
                    password,
                    application_name,
                    data_by_mime: BTreeMap::new(),
                    aliases_by_mime: BTreeMap::new(),
                    last_mime: None,
                    total_bytes: 0,
                    failed: false,
                });
            }
            "wdata" => self.handle_osc5522_wdata(&metadata, payload, events),
            "walias" => self.handle_osc5522_walias(&metadata, payload, events),
            "read" => self.handle_osc5522_read(&metadata, payload, id, events),
            _ => self.fail_osc5522_write("EINVAL", id, events),
        }
    }

    fn handle_osc5522_wdata(
        &mut self,
        metadata: &BTreeMap<String, String>,
        payload: &[u8],
        events: &mut Vec<CallbackEvent>,
    ) {
        let Some(state) = self.osc5522_write.as_mut() else {
            events.push(osc5522_error_event("write", "EINVAL", None));
            return;
        };
        if state.failed {
            return;
        }
        let Some(encoded_mime) = metadata.get("mime") else {
            if !payload.is_empty() || state.data_by_mime.is_empty() {
                self.fail_osc5522_write("EINVAL", None, events);
                return;
            }
            let state = self.osc5522_write.take().expect("write state exists");
            let items = state
                .data_by_mime
                .into_iter()
                .map(|(mime, data)| {
                    serde_json::json!({
                        "mime": mime,
                        "data": BASE64_STANDARD.encode(data),
                        "aliases": state.aliases_by_mime.get(&mime).cloned().unwrap_or_default(),
                    })
                })
                .collect::<Vec<_>>();
            events.push(CallbackEvent::ClipboardMimeWrite {
                payload: serde_json::json!({
                    "protocol": "osc5522",
                    "location": state.location,
                    "id": state.id,
                    "password": state.password,
                    "applicationName": state.application_name,
                    "items": items,
                }),
            });
            return;
        };
        let Some(mime) = decode_osc5522_mime(encoded_mime) else {
            self.fail_osc5522_write("EINVAL", None, events);
            return;
        };
        let Ok(chunk) = BASE64_STANDARD.decode(payload) else {
            self.fail_osc5522_write("EINVAL", None, events);
            return;
        };
        if chunk.len() > OSC5522_MAX_CHUNK_BYTES
            || state.total_bytes.saturating_add(chunk.len()) > OSC5522_MAX_TOTAL_BYTES
            || (!state.data_by_mime.contains_key(&mime)
                && state.data_by_mime.len() >= OSC5522_MAX_MIME_TYPES)
            || (state.last_mime.as_deref() != Some(&mime) && state.data_by_mime.contains_key(&mime))
        {
            self.fail_osc5522_write("EINVAL", None, events);
            return;
        }
        state.total_bytes += chunk.len();
        state.last_mime = Some(mime.clone());
        state.data_by_mime.entry(mime).or_default().extend(chunk);
    }

    fn handle_osc5522_walias(
        &mut self,
        metadata: &BTreeMap<String, String>,
        payload: &[u8],
        events: &mut Vec<CallbackEvent>,
    ) {
        let Some(state) = self.osc5522_write.as_mut() else {
            events.push(osc5522_error_event("write", "EINVAL", None));
            return;
        };
        if state.failed {
            return;
        }
        let Some(target) = metadata
            .get("mime")
            .and_then(|value| decode_osc5522_mime(value))
        else {
            self.fail_osc5522_write("EINVAL", None, events);
            return;
        };
        let Ok(decoded) = BASE64_STANDARD.decode(payload) else {
            self.fail_osc5522_write("EINVAL", None, events);
            return;
        };
        let Ok(decoded) = std::str::from_utf8(&decoded) else {
            self.fail_osc5522_write("EINVAL", None, events);
            return;
        };
        let aliases = decoded
            .split_ascii_whitespace()
            .map(str::to_string)
            .collect::<Vec<_>>();
        if aliases.is_empty()
            || aliases.len() > 16
            || !state.data_by_mime.contains_key(&target)
            || aliases.iter().any(|alias| !is_valid_osc5522_mime(alias))
        {
            self.fail_osc5522_write("EINVAL", None, events);
            return;
        }
        state.aliases_by_mime.insert(target, aliases);
    }

    fn handle_osc5522_read(
        &mut self,
        metadata: &BTreeMap<String, String>,
        payload: &[u8],
        id: Option<String>,
        events: &mut Vec<CallbackEvent>,
    ) {
        let Some(location) = osc5522_location(metadata) else {
            events.push(osc5522_error_event("read", "EINVAL", id));
            return;
        };
        let Some((password, application_name)) = osc5522_credentials(metadata) else {
            events.push(osc5522_error_event("read", "EINVAL", id));
            return;
        };
        let (mime_types, list_only) = if let Some(encoded_mime) = metadata.get("mime") {
            if !payload.is_empty() {
                events.push(osc5522_error_event("read", "EINVAL", id));
                return;
            }
            let Some(mime) = decode_osc5522_mime(encoded_mime) else {
                events.push(osc5522_error_event("read", "EINVAL", id));
                return;
            };
            (vec![mime], false)
        } else {
            let Ok(decoded) = BASE64_STANDARD.decode(payload) else {
                events.push(osc5522_error_event("read", "EINVAL", id));
                return;
            };
            let Ok(decoded) = std::str::from_utf8(&decoded) else {
                events.push(osc5522_error_event("read", "EINVAL", id));
                return;
            };
            (
                decoded
                    .split_ascii_whitespace()
                    .map(str::to_string)
                    .collect::<Vec<_>>(),
                decoded == ".",
            )
        };
        if mime_types.is_empty()
            || mime_types.len() > OSC5522_MAX_MIME_TYPES
            || mime_types
                .iter()
                .any(|mime| mime != "." && !is_valid_osc5522_mime_pattern(mime))
            || (mime_types.contains(&".".to_string()) && mime_types.len() != 1)
        {
            events.push(osc5522_error_event("read", "EINVAL", id));
            return;
        }
        events.push(CallbackEvent::ClipboardMimeReadRequest {
            payload: serde_json::json!({
                "protocol": "osc5522",
                "location": location,
                "id": id,
                "password": password,
                "applicationName": application_name,
                "mimeTypes": mime_types,
                "listOnly": list_only,
            }),
        });
    }

    fn fail_osc5522_write(
        &mut self,
        status: &str,
        id: Option<String>,
        events: &mut Vec<CallbackEvent>,
    ) {
        if let Some(state) = self.osc5522_write.as_mut() {
            if state.failed {
                return;
            }
            state.failed = true;
            events.push(osc5522_error_event(
                "write",
                status,
                state.id.clone().or(id),
            ));
        } else {
            events.push(osc5522_error_event("write", status, id));
        }
    }

    fn consume_csi(
        &mut self,
        start: usize,
        emulation: TerminalEmulation,
        events: &mut Vec<CallbackEvent>,
    ) -> Option<usize> {
        let mut cursor = start + 2;
        while cursor < self.buffer.len() {
            let byte = self.buffer[cursor];
            if (0x40..=0x7e).contains(&byte) {
                if emulation == TerminalEmulation::Xterm256 && byte == b't' {
                    let payload = self.buffer[start + 2..cursor].to_vec();
                    self.handle_csi_window(&payload, events);
                }
                return Some(cursor + 1);
            }
            cursor += 1;
        }
        None
    }

    fn handle_csi_window(&mut self, payload: &[u8], events: &mut Vec<CallbackEvent>) {
        let body = String::from_utf8_lossy(payload);
        let mut parts = body.split(';');
        let Some(kind) = parts.next() else {
            return;
        };
        if kind != "8" {
            return;
        }

        let rows = parts.next().and_then(|value| value.parse::<u16>().ok());
        let cols = parts.next().and_then(|value| value.parse::<u16>().ok());
        if let (Some(rows), Some(cols)) = (rows, cols) {
            events.push(CallbackEvent::Resize { rows, cols });
        }
    }
}

#[cfg(test)]
pub(super) fn callback_event_from_parser_event(
    event: ParserTerminalEvent,
    suppress_shell_zones: bool,
) -> Option<CallbackEvent> {
    callback_event_from_parser_event_with_terminal(event, suppress_shell_zones, None)
}

pub(super) fn callback_event_from_parser_event_with_terminal(
    event: ParserTerminalEvent,
    suppress_shell_zones: bool,
    terminal: Option<&Terminal>,
) -> Option<CallbackEvent> {
    match event {
        ParserTerminalEvent::BellRang(_) => Some(CallbackEvent::Bell),
        ParserTerminalEvent::CwdChanged(change) => {
            let source = if change.source
                == par_term_emu_core_rust::terminal::CwdChangeSource::Osc1337
                && change.old_cwd.as_deref() == Some(change.new_cwd.as_str())
            {
                // OSC 1337 RemoteHost updates identity while retaining cwd.
                // Keep the established product source without emitting the
                // supplemental EnvironmentChanged/RemoteHostTransition events
                // as duplicate shell_context callbacks.
                "osc1337_remote_host"
            } else {
                change.source.as_str()
            };
            let mut payload = serde_json::Map::new();
            payload.insert(
                "source".to_string(),
                serde_json::Value::String(source.to_string()),
            );
            payload.insert(
                "cwd".to_string(),
                serde_json::Value::String(sanitize_protocol_text(&change.new_cwd, 1024)),
            );
            payload.insert(
                "hostname".to_string(),
                sanitize_protocol_text_option(change.hostname.as_deref(), 255)
                    .map_or(serde_json::Value::Null, serde_json::Value::String),
            );
            payload.insert(
                "username".to_string(),
                sanitize_protocol_text_option(change.username.as_deref(), 255)
                    .map_or(serde_json::Value::Null, serde_json::Value::String),
            );
            payload.insert(
                "timestamp".to_string(),
                serde_json::Value::from(change.timestamp),
            );
            Some(CallbackEvent::ShellContext {
                payload: serde_json::Value::Object(payload),
            })
        }
        ParserTerminalEvent::ShellIntegrationEvent {
            source,
            event_type,
            command,
            exit_code,
            timestamp,
            cursor_line,
            prompt_kind,
            aid,
            parent_aid,
            implicit_closed_count,
            fresh_line,
        } => {
            if suppress_shell_zones {
                return None;
            }
            Some(CallbackEvent::ShellCommand {
                payload: serde_json::json!({
                    "source": source.as_str(),
                    "eventType": sanitize_protocol_text(&event_type, 80),
                    "command": command
                        .as_deref()
                        .and_then(|value| sanitize_protocol_text_option(Some(value), 512)),
                    "exitCode": exit_code,
                    "timestamp": timestamp,
                    "cursorLine": cursor_line,
                    "promptKind": prompt_kind
                        .as_deref()
                        .and_then(|value| sanitize_protocol_text_option(Some(value), 32)),
                    "aid": aid
                        .as_deref()
                        .and_then(|value| sanitize_protocol_text_option(Some(value), 256)),
                    "parentAid": parent_aid
                        .as_deref()
                        .and_then(|value| sanitize_protocol_text_option(Some(value), 256)),
                    "implicitClosedCount": implicit_closed_count,
                    "freshLine": fresh_line,
                }),
            })
        }
        ParserTerminalEvent::ShellIntegrationVersion { version, shell } => {
            Some(CallbackEvent::ShellCommand {
                payload: serde_json::json!({
                    "source": "osc1337",
                    "eventType": "integration_version",
                    "version": sanitize_protocol_text(&version, 32),
                    "shell": shell
                        .as_deref()
                        .and_then(|value| sanitize_protocol_text_option(Some(value), 32)),
                }),
            })
        }
        ParserTerminalEvent::CellSizeReportRequested => Some(CallbackEvent::CellSizeReportRequest),
        ParserTerminalEvent::ItermClearCapturedOutputRequested => {
            Some(CallbackEvent::ClearCapturedOutput)
        }
        ParserTerminalEvent::ItermReportVariableRequested { name } => {
            let value =
                terminal.and_then(|terminal| resolved_iterm_report_variable(terminal, &name));
            Some(CallbackEvent::ReportVariableRequest {
                payload: serde_json::json!({
                    "source": "iterm1337",
                    "name": name,
                    "value": value,
                }),
            })
        }
        ParserTerminalEvent::ItermOpenUrlRequested { url } => {
            let url = validated_terminal_open_url(&url)?;
            Some(CallbackEvent::OpenUrlRequest {
                payload: serde_json::json!({
                    "source": "iterm1337",
                    "url": url,
                }),
            })
        }
        ParserTerminalEvent::ItermAttentionRequested { action } => {
            let action = validated_iterm_attention_action(action.as_str())?;
            Some(CallbackEvent::AttentionRequest {
                payload: serde_json::json!({
                    "source": "iterm1337",
                    "action": action,
                }),
            })
        }
        ParserTerminalEvent::ItermAnnotation {
            message,
            visible,
            start_abs_row,
            start_col,
            end_abs_row,
            end_col,
        } => {
            let retained_range = terminal.and_then(|terminal| {
                let start_row = retained_row_for_abs_row(terminal, start_abs_row)?;
                let end_row = retained_row_for_abs_row(terminal, end_abs_row)?;
                Some((start_row, end_row))
            });
            let selected_text = terminal
                .zip(retained_range)
                .map(|(terminal, (start_row, end_row))| {
                    selection_text_for_terminal(
                        terminal,
                        TerminalSelectionRequest {
                            start_row,
                            start_col,
                            end_row,
                            end_col,
                            block: false,
                        },
                    )
                })
                .unwrap_or_default();
            Some(CallbackEvent::SessionAnnotation {
                payload: serde_json::json!({
                    "source": "iterm1337",
                    "message": sanitize_protocol_text(&message, 1024),
                    "visible": visible,
                    "selectedText": sanitize_annotation_selected_text(&selected_text, 4096),
                    "startAbsRow": start_abs_row,
                    "startCol": start_col,
                    "endAbsRow": end_abs_row,
                    "endCol": end_col,
                    "startRow": retained_range.map(|value| value.0),
                    "endRow": retained_range.map(|value| value.1),
                }),
            })
        }
        ParserTerminalEvent::ZoneOpened {
            zone_id,
            zone_type,
            abs_row_start,
        } => {
            if suppress_shell_zones {
                return None;
            }
            Some(CallbackEvent::ShellCommand {
                payload: serde_json::json!({
                    "source": "osc133",
                    "eventType": "zone_opened",
                    "zoneId": zone_id,
                    "zoneType": zone_type.to_string(),
                    "absRowStart": abs_row_start,
                }),
            })
        }
        ParserTerminalEvent::ZoneClosed {
            zone_id,
            zone_type,
            abs_row_start,
            abs_row_end,
            exit_code,
        } => {
            if suppress_shell_zones {
                return None;
            }
            Some(CallbackEvent::ShellCommand {
                payload: serde_json::json!({
                    "source": "osc133",
                    "eventType": "zone_closed",
                    "zoneId": zone_id,
                    "zoneType": zone_type.to_string(),
                    "absRowStart": abs_row_start,
                    "absRowEnd": abs_row_end,
                    "exitCode": exit_code,
                }),
            })
        }
        ParserTerminalEvent::ZoneScrolledOut { zone_id, zone_type } => {
            if suppress_shell_zones {
                return None;
            }
            Some(CallbackEvent::ShellCommand {
                payload: serde_json::json!({
                    "source": "osc133",
                    "eventType": "zone_scrolled_out",
                    "zoneId": zone_id,
                    "zoneType": zone_type.to_string(),
                }),
            })
        }
        // These detailed library events accompany one authoritative
        // CwdChanged event. The native product bridge emits only that complete
        // context so profile switching/UI work runs once per protocol input.
        ParserTerminalEvent::EnvironmentChanged { .. }
        | ParserTerminalEvent::RemoteHostTransition { .. } => None,
        ParserTerminalEvent::UserVarChanged { name, value, .. } => {
            Some(CallbackEvent::ShellUserVar {
                name: sanitize_protocol_text(&name, 80),
                value: sanitize_protocol_text(&value, 512),
            })
        }
        ParserTerminalEvent::ProgressBarChanged {
            action,
            id,
            state,
            percent,
            label,
        } => {
            let action = match action {
                par_term_emu_core_rust::terminal::ProgressBarAction::Set => "set",
                par_term_emu_core_rust::terminal::ProgressBarAction::Remove => "remove",
                par_term_emu_core_rust::terminal::ProgressBarAction::RemoveAll => "remove_all",
            };
            Some(CallbackEvent::SessionProgress {
                payload: serde_json::json!({
                    "source": "ianvs_osc934",
                    "named": true,
                    "action": action,
                    // The parser already validates the 128-byte identity. It
                    // must remain exact because Dart uses it as the lifecycle
                    // key; display truncation belongs only in the UI.
                    "id": id,
                    "state": state.map(|value| value.description()),
                    "percent": percent,
                    "label": label
                        .as_deref()
                        .and_then(|value| sanitize_protocol_text_option(Some(value), 160)),
                }),
            })
        }
        ParserTerminalEvent::BadgeChanged(text) => Some(CallbackEvent::SessionBadge {
            text: text.and_then(|value| sanitize_protocol_text_option(Some(&value), 80)),
        }),
        ParserTerminalEvent::TabStatusChanged(update) => Some(CallbackEvent::SessionTabStatus {
            payload: serde_json::json!({
                "source": "osc21337",
                "indicatorPresent": update.indicator_present,
                "indicator": update.indicator,
                "statusPresent": update.status_present,
                "status": update.status
                    .as_deref()
                    .and_then(|value| sanitize_protocol_text_option(Some(value), 256)),
                "statusColorPresent": update.status_color_present,
                "statusColor": update.status_color,
            }),
        }),
        ParserTerminalEvent::TerminalContextChanged(event) => {
            let event = *event;
            let end_metadata = event.end_metadata.as_ref();
            Some(CallbackEvent::TerminalContext {
                payload: serde_json::json!({
                    "source": "osc3008",
                    "action": event.action.as_str(),
                    "id": event.id,
                    "depth": event.depth,
                    "active": event.active,
                    "type": event.metadata.context_type.map(|value| value.as_str()),
                    "user": event.metadata.user,
                    "hostname": event.metadata.hostname,
                    "machineId": event.metadata.machine_id,
                    "bootId": event.metadata.boot_id,
                    "pid": event.metadata.pid,
                    "pidfdId": event.metadata.pidfd_id,
                    "commandName": event.metadata.command_name,
                    "cwd": event.metadata.cwd,
                    "commandLine": event.metadata.command_line,
                    "vm": event.metadata.vm,
                    "container": event.metadata.container,
                    "targetUser": event.metadata.target_user,
                    "targetHost": event.metadata.target_host,
                    "contextSessionId": event.metadata.session_id,
                    "exit": end_metadata.and_then(|value| value.exit.map(|exit| exit.as_str())),
                    "status": end_metadata.and_then(|value| value.status),
                    "signal": end_metadata.and_then(|value| value.signal.as_deref()),
                    "implicitClosedCount": event.implicit_closed_count,
                }),
            })
        }
        ParserTerminalEvent::DragDropCommand(command) => {
            let command = *command;
            Some(CallbackEvent::DragDropCommand {
                payload: serde_json::json!({
                    "source": "osc72",
                    "action": command.action.wire_name(),
                    "more": command.more,
                    "identifier": command.identifier,
                    "operation": command.operation,
                    "x": command.x,
                    "y": command.y,
                    "pixelX": command.pixel_x,
                    "pixelY": command.pixel_y,
                    "payload": String::from_utf8(command.payload).ok(),
                }),
            })
        }
        ParserTerminalEvent::TerminalReset => Some(CallbackEvent::SessionReset),
        _ => None,
    }
}

pub(super) fn callback_events_from_parser_events(
    state: &mut TerminalState,
    parser_events: Vec<ParserTerminalEvent>,
    suppress_shell_zones: bool,
) -> Vec<CallbackEvent> {
    let mut callbacks = Vec::new();
    for event in parser_events {
        match event {
            ParserTerminalEvent::FileTransferStarted { .. }
            | ParserTerminalEvent::FileTransferProgress { .. } => {
                // Progress can arrive once per multipart chunk. Keep it in the
                // bounded parser state instead of exposing a floodable host
                // event surface; the product acts only on a complete file.
            }
            ParserTerminalEvent::FileTransferCompleted { id, filename, size } => {
                let retained = state.terminal.take_completed_transfer(id);
                let Some(transfer) = retained else {
                    callbacks.push(file_download_failed_callback(
                        Some(id),
                        "completed download data is unavailable",
                    ));
                    continue;
                };
                if transfer.direction != TransferDirection::Download
                    || transfer.status != TransferStatus::Completed
                    || transfer.data.len() != size
                {
                    callbacks.push(file_download_failed_callback(
                        Some(id),
                        "completed download metadata did not match retained data",
                    ));
                    continue;
                }
                let filename = filename.unwrap_or(transfer.filename);
                match state.retain_file_download(filename, transfer.data) {
                    Ok((download_id, filename, retained_size)) => {
                        callbacks.push(CallbackEvent::FileDownload {
                            payload: serde_json::json!({
                                "source": "iterm1337",
                                "transferId": download_id.to_string(),
                                "filename": filename,
                                "size": retained_size,
                            }),
                        });
                    }
                    Err(reason) => callbacks.push(file_download_failed_callback(Some(id), &reason)),
                }
            }
            ParserTerminalEvent::FileTransferFailed { id, reason } => {
                // Failed transfers are never recoverable host data. Taking the
                // terminal record here promptly releases any retained bytes.
                let _ = state.terminal.take_completed_transfer(id);
                callbacks.push(file_download_failed_callback(Some(id), &reason));
            }
            ParserTerminalEvent::UploadRequested { format } => {
                // RequestUpload would disclose user-selected local data to the
                // PTY. This phase intentionally denies it and closes the remote
                // protocol request instead of leaving the caller blocked.
                state.terminal.cancel_upload();
                callbacks.push(CallbackEvent::FileUploadDenied {
                    payload: serde_json::json!({
                        "source": "iterm1337",
                        "format": sanitize_protocol_text(&format, 32),
                        "reason": "upload is disabled",
                    }),
                });
            }
            event => {
                if let Some(callback) = callback_event_from_parser_event_with_terminal(
                    event,
                    suppress_shell_zones,
                    Some(&state.terminal),
                ) {
                    callbacks.push(callback);
                }
            }
        }
    }
    callbacks
}

fn file_download_failed_callback(parser_transfer_id: Option<u64>, reason: &str) -> CallbackEvent {
    CallbackEvent::FileDownloadFailed {
        payload: serde_json::json!({
            "source": "iterm1337",
            "parserTransferId": parser_transfer_id.map(|id| id.to_string()),
            "reason": sanitize_protocol_text(reason, 240),
        }),
    }
}

pub(super) fn discard_replayed_parser_host_events(terminal: &mut Terminal) {
    for event in terminal.poll_events() {
        match event {
            ParserTerminalEvent::FileTransferCompleted { id, .. }
            | ParserTerminalEvent::FileTransferFailed { id, .. } => {
                let _ = terminal.take_completed_transfer(id);
            }
            ParserTerminalEvent::UploadRequested { .. } => terminal.cancel_upload(),
            _ => {}
        }
    }
}

fn validated_terminal_open_url(value: &str) -> Option<String> {
    const MAX_OPEN_URL_BYTES: usize = 4096;
    if value.is_empty()
        || value.len() > MAX_OPEN_URL_BYTES
        || value.trim() != value
        || value.chars().any(char::is_control)
    {
        return None;
    }
    let parsed = url::Url::parse(value).ok()?;
    let allowed = match parsed.scheme() {
        "http" | "https" => parsed.host_str().is_some_and(|host| !host.is_empty()),
        "file" => parsed.host_str().is_none() && !parsed.path().is_empty() && parsed.path() != "/",
        _ => false,
    };
    allowed.then(|| value.to_string())
}

fn resolved_iterm_report_variable(terminal: &Terminal, name: &str) -> Option<String> {
    let variables = terminal.session_variables();
    match name {
        "session.name" => variables
            .session_name
            .clone()
            .or_else(|| (!terminal.title().is_empty()).then(|| terminal.title().to_string())),
        "session.columns" => Some(terminal.size().0.to_string()),
        "session.rows" => Some(terminal.size().1.to_string()),
        "session.hostname" => variables.hostname.clone(),
        "session.username" => variables.username.clone(),
        "session.path" => variables
            .path
            .clone()
            .or_else(|| terminal.current_directory().map(str::to_string)),
        _ => name
            .strip_prefix("user.")
            .and_then(|user_name| terminal.get_user_var(user_name))
            .map(str::to_string),
    }
}

pub(super) fn validated_iterm_attention_action(value: &str) -> Option<&'static str> {
    match value {
        "yes" => Some("yes"),
        "once" => Some("once"),
        "no" => Some("no"),
        "fireworks" => Some("fireworks"),
        _ => None,
    }
}

pub(super) fn input_sets_alt_screen(input: &[u8]) -> bool {
    let mut index = 0;
    while index + 3 < input.len() {
        if input[index] != 0x1b || input[index + 1] != b'[' || input[index + 2] != b'?' {
            index += 1;
            continue;
        }
        let params_start = index + 3;
        let mut cursor = params_start;
        while cursor < input.len() && (input[cursor].is_ascii_digit() || input[cursor] == b';') {
            cursor += 1;
        }
        if cursor >= input.len() {
            return false;
        }
        if input[cursor] == b'h' {
            let params = &input[params_start..cursor];
            if params
                .split(|byte| *byte == b';')
                .any(|param| matches!(param, b"47" | b"1047" | b"1049"))
            {
                return true;
            }
        }
        index = cursor + 1;
    }
    false
}

fn primary_progress_payload_from_osc9(remainder: &[u8]) -> Option<serde_json::Value> {
    let mut parts = remainder.split(|byte| *byte == b';');
    if parts.next()? != b"4" {
        return None;
    }
    let state = std::str::from_utf8(parts.next()?).ok()?.trim();
    let state = match state {
        "0" => "hidden",
        "1" => "normal",
        "2" => "error",
        "3" => "indeterminate",
        "4" => "warning",
        _ => return None,
    };
    let percent = parts
        .next()
        .and_then(|part| std::str::from_utf8(part).ok())
        .and_then(|value| value.trim().parse::<u8>().ok())
        .map(|value| value.min(100));
    let mut payload = serde_json::Map::from_iter([
        (
            "source".to_string(),
            serde_json::Value::String("osc9;4".to_string()),
        ),
        ("named".to_string(), serde_json::Value::Bool(false)),
        (
            "action".to_string(),
            serde_json::Value::String(if state == "hidden" { "clear" } else { "set" }.to_string()),
        ),
        (
            "state".to_string(),
            serde_json::Value::String(state.to_string()),
        ),
    ]);
    if let Some(percent) = percent {
        payload.insert("percent".to_string(), serde_json::json!(percent));
    }
    Some(serde_json::Value::Object(payload))
}

pub(super) fn shell_context_payload_from_current_dir(data: &str) -> Option<serde_json::Value> {
    let raw = data.strip_prefix("CurrentDir=")?;
    let raw = raw.trim();
    if raw.is_empty() {
        return None;
    }
    let (cwd, hostname, username) = if raw.starts_with("file://") {
        parse_file_url_context(raw)?
    } else if raw.starts_with('/') {
        (percent_decode_strict(raw)?, None, None)
    } else {
        return None;
    };
    if !cwd.starts_with('/') || cwd.chars().any(char::is_control) {
        return None;
    }
    let mut payload = serde_json::Map::new();
    payload.insert(
        "source".to_string(),
        serde_json::Value::String("osc1337_current_dir".to_string()),
    );
    payload.insert(
        "cwd".to_string(),
        serde_json::Value::String(sanitize_protocol_text(&cwd, 1024)),
    );
    if let Some(hostname) =
        hostname.and_then(|value| sanitize_protocol_text_option(Some(&value), 255))
    {
        payload.insert("hostname".to_string(), serde_json::Value::String(hostname));
    }
    if let Some(username) =
        username.and_then(|value| sanitize_protocol_text_option(Some(&value), 255))
    {
        payload.insert("username".to_string(), serde_json::Value::String(username));
    }
    Some(serde_json::Value::Object(payload))
}

fn parse_file_url_context(raw: &str) -> Option<(String, Option<String>, Option<String>)> {
    let mut remainder = raw.strip_prefix("file://")?;
    if let Some(index) = remainder.find(['?', '#']) {
        remainder = &remainder[..index];
    }
    if remainder.starts_with('/') {
        return Some((percent_decode_strict(remainder)?, None, None));
    }
    let slash = remainder.find('/')?;
    let authority = &remainder[..slash];
    let path = percent_decode_strict(&remainder[slash..])?;
    let (username, host_part) = match authority.rsplit_once('@') {
        Some((username, host)) => (Some(percent_decode_strict(username)?), host),
        None => (None, authority),
    };
    let host = host_part.split(':').next().unwrap_or_default();
    let hostname = if host.is_empty()
        || host.eq_ignore_ascii_case("localhost")
        || host == "127.0.0.1"
        || host == "::1"
    {
        None
    } else {
        Some(percent_decode_strict(host)?)
    };
    let username = username.and_then(|value| if value.is_empty() { None } else { Some(value) });
    Some((path, hostname, username))
}

fn percent_decode_strict(value: &str) -> Option<String> {
    let bytes = value.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0usize;
    while index < bytes.len() {
        if bytes[index] == b'%' {
            let high = bytes.get(index + 1).copied().and_then(hex_nibble)?;
            let low = bytes.get(index + 2).copied().and_then(hex_nibble)?;
            decoded.push((high << 4) | low);
            index += 3;
            continue;
        }
        decoded.push(bytes[index]);
        index += 1;
    }
    let decoded = String::from_utf8(decoded).ok()?;
    (!decoded.chars().any(char::is_control)).then_some(decoded)
}

pub(super) fn sanitize_protocol_text(value: &str, max_chars: usize) -> String {
    value
        .chars()
        .filter(|ch| !ch.is_control())
        .take(max_chars)
        .collect::<String>()
        .trim()
        .to_string()
}

pub(super) fn sanitize_file_download_name(value: &str) -> String {
    let basename = value
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or_default()
        .chars()
        .filter(|character| !character.is_control())
        .take(160)
        .collect::<String>();
    let basename = basename.trim();
    if basename.is_empty() || basename == "." || basename == ".." {
        "Unnamed file".to_string()
    } else {
        basename.to_string()
    }
}

fn sanitize_annotation_selected_text(value: &str, max_chars: usize) -> String {
    value
        .chars()
        .filter(|character| *character == '\n' || !character.is_control())
        .take(max_chars)
        .collect()
}

fn sanitize_protocol_text_option(value: Option<&str>, max_chars: usize) -> Option<String> {
    let value = sanitize_protocol_text(value?, max_chars);
    if value.is_empty() { None } else { Some(value) }
}

fn parse_osc5522_metadata(value: &str) -> Option<BTreeMap<String, String>> {
    let mut metadata = BTreeMap::new();
    for field in value.split(':') {
        let (key, value) = field.split_once('=')?;
        if key.is_empty()
            || key.len() > 16
            || !key
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
            || value.len() > 1024
        {
            return None;
        }
        metadata
            .entry(key.to_string())
            .or_insert_with(|| value.to_string());
        if metadata.len() > 16 {
            return None;
        }
    }
    Some(metadata)
}

fn osc5522_location(metadata: &BTreeMap<String, String>) -> Option<String> {
    match metadata
        .get("loc")
        .map(String::as_str)
        .unwrap_or("clipboard")
    {
        "clipboard" => Some("clipboard".to_string()),
        "primary" => Some("primary".to_string()),
        _ => None,
    }
}

fn sanitized_osc5522_id(value: &str) -> Option<String> {
    let sanitized = value
        .bytes()
        .filter(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'+' | b'.'))
        .take(OSC5522_MAX_ID_BYTES)
        .map(char::from)
        .collect::<String>();
    (!sanitized.is_empty()).then_some(sanitized)
}

fn osc5522_credentials(
    metadata: &BTreeMap<String, String>,
) -> Option<(Option<String>, Option<String>)> {
    let password = decode_osc5522_utf8_metadata(
        metadata.get("pw").map(String::as_str),
        OSC5522_MAX_PASSWORD_BYTES,
        false,
    )?;
    let application_name = decode_osc5522_utf8_metadata(
        metadata.get("name").map(String::as_str),
        OSC5522_MAX_APPLICATION_NAME_BYTES,
        true,
    )?;
    Some((password, application_name))
}

fn decode_osc5522_utf8_metadata(
    encoded: Option<&str>,
    max_bytes: usize,
    reject_controls: bool,
) -> Option<Option<String>> {
    let Some(encoded) = encoded else {
        return Some(None);
    };
    let decoded = BASE64_STANDARD.decode(encoded).ok()?;
    if decoded.is_empty() || decoded.len() > max_bytes {
        return None;
    }
    let value = String::from_utf8(decoded).ok()?;
    if reject_controls
        && value
            .chars()
            .any(|character| character.is_control() || character == '\u{7f}')
    {
        return None;
    }
    Some(Some(value))
}

fn decode_osc5522_mime(encoded: &str) -> Option<String> {
    let decoded = BASE64_STANDARD.decode(encoded).ok()?;
    let mime = String::from_utf8(decoded).ok()?;
    is_valid_osc5522_mime(&mime).then_some(mime)
}

fn is_valid_osc5522_mime(value: &str) -> bool {
    value.len() <= OSC5522_MAX_MIME_BYTES
        && value.split_once('/').is_some_and(|(major, minor)| {
            !major.is_empty()
                && !minor.is_empty()
                && major.bytes().all(is_osc5522_mime_byte)
                && minor.bytes().all(is_osc5522_mime_byte)
        })
}

fn is_valid_osc5522_mime_pattern(value: &str) -> bool {
    is_valid_osc5522_mime(value)
        || value.split_once('/').is_some_and(|(major, minor)| {
            !major.is_empty()
                && !minor.is_empty()
                && (major == "*" || major.bytes().all(is_osc5522_mime_byte))
                && (minor == "*" || minor.bytes().all(is_osc5522_mime_byte))
        })
}

fn is_osc5522_mime_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric()
        || matches!(
            byte,
            b'!' | b'#' | b'$' | b'&' | b'^' | b'_' | b'.' | b'+' | b'-'
        )
}

fn osc5522_error_event(operation: &str, status: &str, id: Option<String>) -> CallbackEvent {
    CallbackEvent::ClipboardMimeError {
        payload: serde_json::json!({
            "protocol": "osc5522",
            "operation": operation,
            "status": status,
            "id": id,
        }),
    }
}

fn hex_nibble(byte: u8) -> Option<u8> {
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

    #[test]
    fn split_csi_dcs_and_osc_callbacks_preserve_wire_order() {
        let wire = concat!(
            "\x1b[8;24;80t",
            "\x1bPhook;7b22686f6f6b223a22707265636d64227d\x1b\\",
            "\x1b]9;4;1;42\x07"
        );
        let mut observer = HostProtocolState::default();
        let mut events = Vec::new();

        for chunk in wire.as_bytes().chunks(3) {
            events.extend(observer.observe(chunk, TerminalEmulation::Xterm256));
        }

        assert_eq!(events.len(), 3);
        assert!(matches!(
            &events[0],
            CallbackEvent::Resize { rows: 24, cols: 80 }
        ));
        assert!(matches!(
            &events[1],
            CallbackEvent::ShellHook { payload }
                if payload["hook"] == "precmd"
        ));
        assert!(matches!(
            &events[2],
            CallbackEvent::SessionProgress { payload }
                if payload["source"] == "osc9;4" && payload["percent"] == 42
        ));
        assert!(observer.buffer.is_empty());
    }
}
