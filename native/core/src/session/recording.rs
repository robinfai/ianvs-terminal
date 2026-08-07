use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use serde_json::{Value, json};
use std::time::Instant;

pub(super) const RECORDING_SCHEMA_VERSION: u8 = 1;
pub(super) const RECORDING_MAX_EVENTS: usize = 4096;
pub(super) const RECORDING_MAX_PAYLOAD_BYTES: usize = 8 * 1024 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum RecordingInputPolicy {
    Record,
    Redact,
}

impl RecordingInputPolicy {
    pub(super) fn parse(value: &str) -> Option<Self> {
        match value {
            "record" => Some(Self::Record),
            "redact" => Some(Self::Redact),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Record => "record",
            Self::Redact => "redact",
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub(super) struct RecordingError {
    pub(super) code: &'static str,
    pub(super) message: &'static str,
}

impl RecordingError {
    fn already_active() -> Self {
        Self {
            code: "already_active",
            message: "a recording is already active for this session",
        }
    }

    fn not_active() -> Self {
        Self {
            code: "not_active",
            message: "no recording is active for this session",
        }
    }

    fn capacity_exceeded() -> Self {
        Self {
            code: "capacity_exceeded",
            message: "recording buffer capacity exceeded",
        }
    }

    fn serialize() -> Self {
        Self {
            code: "serialize_failed",
            message: "recording serialization failed",
        }
    }
}

#[derive(Debug)]
pub(super) struct RecordingStartResult {
    pub(super) max_events: usize,
    pub(super) max_payload_bytes: usize,
}

#[derive(Default)]
pub(super) struct SessionRecording {
    active: Option<ActiveRecording>,
    max_events: usize,
    max_payload_bytes: usize,
}

impl SessionRecording {
    pub(super) fn bounded() -> Self {
        Self::with_limits(RECORDING_MAX_EVENTS, RECORDING_MAX_PAYLOAD_BYTES)
    }

    fn with_limits(max_events: usize, max_payload_bytes: usize) -> Self {
        Self {
            active: None,
            max_events,
            max_payload_bytes,
        }
    }

    // This boundary mirrors the stable recording Session Request fields; a
    // parameter object would only move, rather than reduce, that contract.
    #[allow(clippy::too_many_arguments)]
    pub(super) fn start(
        &mut self,
        session_id: u64,
        created_at_utc: String,
        input_policy: RecordingInputPolicy,
        terminal_emulation: &'static str,
        cols: u16,
        rows: u16,
        initial_screen: Vec<u8>,
    ) -> Result<RecordingStartResult, RecordingError> {
        if self.active.is_some() {
            return Err(RecordingError::already_active());
        }
        let mut active = ActiveRecording {
            session_id,
            created_at_utc,
            input_policy,
            started_at: Instant::now(),
            events: Vec::new(),
            payload_bytes: 0,
            overflowed: false,
            max_events: self.max_events,
            max_payload_bytes: self.max_payload_bytes,
        };
        active.push_at(
            RecordingEventPayload::SessionStarted {
                terminal_emulation,
                cols,
                rows,
            },
            0,
        );
        if !initial_screen.is_empty() {
            active.push_at(RecordingEventPayload::PtyOutput(initial_screen), 0);
        }
        self.active = Some(active);
        Ok(RecordingStartResult {
            max_events: self.max_events,
            max_payload_bytes: self.max_payload_bytes,
        })
    }

    pub(super) fn record_pty_output(&mut self, bytes: &[u8]) {
        if bytes.is_empty() {
            return;
        }
        if let Some(active) = self.active.as_mut() {
            active.push(RecordingEventPayload::PtyOutput(bytes.to_vec()));
        }
    }

    pub(super) fn record_user_input(&mut self, bytes: &[u8]) {
        if let Some(active) = self.active.as_mut() {
            let payload = match active.input_policy {
                RecordingInputPolicy::Record => RecordingEventPayload::UserInput {
                    bytes: Some(bytes.to_vec()),
                    byte_length: bytes.len(),
                },
                RecordingInputPolicy::Redact => RecordingEventPayload::UserInput {
                    bytes: None,
                    byte_length: bytes.len(),
                },
            };
            active.push(payload);
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn record_resize(
        &mut self,
        cols: u16,
        rows: u16,
        pixel_width: u16,
        pixel_height: u16,
        cell_width: u16,
        cell_height: u16,
    ) {
        if let Some(active) = self.active.as_mut() {
            active.push(RecordingEventPayload::Resize {
                cols,
                rows,
                pixel_width,
                pixel_height,
                cell_width,
                cell_height,
            });
        }
    }

    pub(super) fn record_session_exited(&mut self, exit_code: Option<i32>) {
        if let Some(active) = self.active.as_mut() {
            active.push(RecordingEventPayload::SessionExited { exit_code });
        }
    }

    pub(super) fn stop(&mut self) -> Result<String, RecordingError> {
        let active = self.active.take().ok_or_else(RecordingError::not_active)?;
        if active.overflowed {
            return Err(RecordingError::capacity_exceeded());
        }
        active.encode_ndjson()
    }

    pub(super) fn cancel(&mut self) -> Result<(), RecordingError> {
        self.active.take().ok_or_else(RecordingError::not_active)?;
        Ok(())
    }
}

struct ActiveRecording {
    session_id: u64,
    created_at_utc: String,
    input_policy: RecordingInputPolicy,
    started_at: Instant,
    events: Vec<RecordingEvent>,
    payload_bytes: usize,
    overflowed: bool,
    max_events: usize,
    max_payload_bytes: usize,
}

impl ActiveRecording {
    fn push(&mut self, payload: RecordingEventPayload) {
        self.push_at(payload, self.started_at.elapsed().as_micros() as u64);
    }

    fn push_at(&mut self, payload: RecordingEventPayload, monotonic_offset_micros: u64) {
        if self.overflowed {
            return;
        }
        let payload_bytes = payload.byte_len();
        if self.events.len() >= self.max_events
            || self.payload_bytes.saturating_add(payload_bytes) > self.max_payload_bytes
        {
            self.overflowed = true;
            return;
        }
        self.payload_bytes += payload_bytes;
        self.events.push(RecordingEvent {
            monotonic_offset_micros,
            payload,
        });
    }

    fn encode_ndjson(self) -> Result<String, RecordingError> {
        let mut lines = Vec::with_capacity(self.events.len() + 1);
        lines.push(json!({
            "record_type": "metadata",
            "schema_version": RECORDING_SCHEMA_VERSION,
            "session_id": self.session_id.to_string(),
            "created_at_utc": self.created_at_utc,
            "input_policy": self.input_policy.as_str(),
        }));
        for (sequence, event) in self.events.into_iter().enumerate() {
            lines.push(json!({
                "record_type": "event",
                "schema_version": RECORDING_SCHEMA_VERSION,
                "session_id": self.session_id.to_string(),
                "sequence": sequence,
                "monotonic_offset_micros": event.monotonic_offset_micros,
                "event_kind": event.payload.kind(),
                "payload": event.payload.into_json(),
            }));
        }
        let encoded = lines
            .into_iter()
            .map(|line| serde_json::to_string(&line))
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| RecordingError::serialize())?;
        Ok(format!("{}\n", encoded.join("\n")))
    }
}

struct RecordingEvent {
    monotonic_offset_micros: u64,
    payload: RecordingEventPayload,
}

enum RecordingEventPayload {
    SessionStarted {
        terminal_emulation: &'static str,
        cols: u16,
        rows: u16,
    },
    PtyOutput(Vec<u8>),
    UserInput {
        bytes: Option<Vec<u8>>,
        byte_length: usize,
    },
    Resize {
        cols: u16,
        rows: u16,
        pixel_width: u16,
        pixel_height: u16,
        cell_width: u16,
        cell_height: u16,
    },
    SessionExited {
        exit_code: Option<i32>,
    },
}

impl RecordingEventPayload {
    fn kind(&self) -> &'static str {
        match self {
            Self::SessionStarted { .. } => "session_started",
            Self::PtyOutput(_) => "pty_output",
            Self::UserInput { .. } => "user_input",
            Self::Resize { .. } => "resize",
            Self::SessionExited { .. } => "session_exited",
        }
    }

    fn byte_len(&self) -> usize {
        match self {
            Self::PtyOutput(bytes) => bytes.len(),
            Self::UserInput {
                bytes: Some(bytes), ..
            } => bytes.len(),
            _ => 0,
        }
    }

    fn into_json(self) -> Value {
        match self {
            Self::SessionStarted {
                terminal_emulation,
                cols,
                rows,
            } => json!({
                "terminal_emulation": terminal_emulation,
                "cols": cols,
                "rows": rows,
            }),
            Self::PtyOutput(bytes) => json!({
                "bytes_base64": BASE64_STANDARD.encode(bytes),
            }),
            Self::UserInput {
                bytes: Some(bytes), ..
            } => json!({
                "bytes_base64": BASE64_STANDARD.encode(bytes),
            }),
            Self::UserInput {
                bytes: None,
                byte_length,
            } => json!({
                "byte_length": byte_length,
                "redacted": true,
            }),
            Self::Resize {
                cols,
                rows,
                pixel_width,
                pixel_height,
                cell_width,
                cell_height,
            } => json!({
                "cols": cols,
                "rows": rows,
                "pixel_width": pixel_width,
                "pixel_height": pixel_height,
                "cell_width": cell_width,
                "cell_height": cell_height,
            }),
            Self::SessionExited { exit_code } => json!({ "exit_code": exit_code }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capture_orders_raw_output_redacted_input_resize_and_exit() {
        let mut recording = SessionRecording::with_limits(8, 1024);
        recording
            .start(
                42,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                120,
                32,
                b"\x1b[2J\x1b[Hexisting screen\x1b[3;5H".to_vec(),
            )
            .unwrap();
        recording.record_pty_output(b"ready\r\n");
        recording.record_user_input(b"secret");
        recording.record_resize(100, 30, 1000, 600, 10, 20);
        recording.record_session_exited(Some(0));

        let source = recording.stop().unwrap();
        let lines = source
            .lines()
            .map(|line| serde_json::from_str::<Value>(line).unwrap())
            .collect::<Vec<_>>();

        assert_eq!(lines.len(), 7);
        assert_eq!(lines[0]["input_policy"], "redact");
        assert_eq!(lines[2]["event_kind"], "pty_output");
        assert_eq!(lines[2]["monotonic_offset_micros"], 0);
        assert_eq!(
            BASE64_STANDARD
                .decode(lines[2]["payload"]["bytes_base64"].as_str().unwrap())
                .unwrap(),
            b"\x1b[2J\x1b[Hexisting screen\x1b[3;5H"
        );
        assert_eq!(lines[4]["event_kind"], "user_input");
        assert_eq!(lines[4]["payload"]["redacted"], true);
        assert_eq!(lines[4]["payload"]["byte_length"], 6);
        assert!(lines[4]["payload"].get("bytes_base64").is_none());
        assert_eq!(lines[5]["event_kind"], "resize");
        assert_eq!(lines[6]["event_kind"], "session_exited");
        assert_eq!(lines[6]["payload"]["exit_code"], 0);
        for (sequence, line) in lines.iter().skip(1).enumerate() {
            assert_eq!(line["sequence"], sequence);
        }
    }

    #[test]
    fn capacity_overflow_never_returns_a_partial_recording() {
        let mut recording = SessionRecording::with_limits(2, 3);
        recording
            .start(
                7,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Record,
                "vt220",
                80,
                24,
                Vec::new(),
            )
            .unwrap();
        recording.record_pty_output(b"abc");
        recording.record_user_input(b"d");

        assert_eq!(recording.stop(), Err(RecordingError::capacity_exceeded()));
    }
}
