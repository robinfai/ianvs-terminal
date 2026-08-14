use super::{
    MAX_PENDING_HOST_REQUESTS, MAX_PENDING_SESSION_EVENT_BYTES, MAX_PENDING_SESSION_EVENTS,
    ZMODEM_DEFERRED_WRITE_FAILED_KIND, unix_timestamp_micros,
};
use crate::host_request::{
    HOST_REQUEST_EVENT_NAME, HostResponseError, HostResponseV1, PendingHostRequestV1,
    host_request_v1_from_event, pending_host_request, resolve_host_response,
};
use crate::model::TerminalEvent;
use crate::runtime_contract::{RuntimeEnvelopeV1, RuntimeEventBatchV1};
use std::collections::VecDeque;

#[derive(Clone, Copy, Debug)]
pub(super) struct PendingEventLimits {
    pub(super) max_count: usize,
    pub(super) max_bytes: usize,
}

impl Default for PendingEventLimits {
    fn default() -> Self {
        Self {
            max_count: MAX_PENDING_SESSION_EVENTS,
            max_bytes: MAX_PENDING_SESSION_EVENT_BYTES,
        }
    }
}

#[derive(Debug)]
pub(super) struct QueuedTerminalEvent {
    pub(super) event: TerminalEvent,
    wire_bytes: usize,
    sequence: u64,
    timestamp_micros: u64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct PendingEventPushResult {
    pub(super) emit_overflow_diagnostic: bool,
}

#[derive(Debug, Default)]
pub(super) struct PendingEventQueue {
    pub(super) entries: VecDeque<QueuedTerminalEvent>,
    pub(super) pending_host_requests: VecDeque<PendingHostRequestV1>,
    pub(super) aggregate_bytes: usize,
    pub(super) dropped_count: u64,
    dropped_since_last_drain: u64,
    pub(super) next_sequence: u64,
    pub(super) overflow_diagnostic_emitted: bool,
    pub(super) limits: PendingEventLimits,
}

impl PendingEventQueue {
    pub(super) fn with_initial(event: TerminalEvent) -> Self {
        let mut queue = Self::default();
        let _ = queue.push(event);
        queue
    }

    pub(super) fn has_pending_zmodem_terminal_result(&self) -> bool {
        self.entries.iter().any(|entry| {
            matches!(
                entry.event.kind.as_str(),
                "zmodem_completed" | "zmodem_failed" | "zmodem_cancelled"
            )
        })
    }

    #[cfg(test)]
    pub(super) fn with_limits(max_count: usize, max_bytes: usize) -> Self {
        Self {
            limits: PendingEventLimits {
                max_count,
                max_bytes,
            },
            ..Self::default()
        }
    }

    pub(super) fn push(&mut self, event: TerminalEvent) -> PendingEventPushResult {
        let timestamp_micros = unix_timestamp_micros();
        let wire_bytes = terminal_event_wire_size(&event);
        if self.limits.max_count == 0
            || self.limits.max_bytes == 0
            || wire_bytes > self.limits.max_bytes
        {
            // Sequences describe every attempted event, including events that
            // cannot enter the bounded queue. This lets consumers observe the
            // loss as a sequence gap alongside `dropped_count`.
            self.next_sequence = self.next_sequence.saturating_add(1);
            return self.record_drop();
        }

        if let Some(transfer_id) = zmodem_progress_transfer_id(&event)
            && let Some(entry) = self.entries.back_mut()
            && zmodem_progress_transfer_id(&entry.event) == Some(transfer_id)
        {
            self.aggregate_bytes = self
                .aggregate_bytes
                .saturating_sub(entry.wire_bytes)
                .saturating_add(wire_bytes);
            entry.event = event;
            entry.wire_bytes = wire_bytes;
            entry.timestamp_micros = timestamp_micros;
            return self.enforce_limits();
        }

        let sequence = self.next_sequence;
        self.next_sequence = self.next_sequence.saturating_add(1);

        self.aggregate_bytes = self.aggregate_bytes.saturating_add(wire_bytes);
        self.entries.push_back(QueuedTerminalEvent {
            event,
            wire_bytes,
            sequence,
            timestamp_micros,
        });

        self.enforce_limits()
    }

    fn enforce_limits(&mut self) -> PendingEventPushResult {
        let mut result = PendingEventPushResult::default();
        while self.entries.len() > self.limits.max_count
            || self.aggregate_bytes > self.limits.max_bytes
        {
            let Some(index) = self.eviction_index() else {
                break;
            };
            if let Some(removed) = self.entries.remove(index) {
                self.aggregate_bytes = self.aggregate_bytes.saturating_sub(removed.wire_bytes);
                let dropped = self.record_drop();
                result.emit_overflow_diagnostic |= dropped.emit_overflow_diagnostic;
            } else {
                break;
            }
        }
        result
    }

    fn eviction_index(&self) -> Option<usize> {
        self.entries
            .iter()
            .position(|entry| {
                !pending_event_is_protected(&entry.event.kind)
                    && pending_event_is_coalescible(&entry.event.kind)
            })
            .or_else(|| {
                self.entries.iter().position(|entry| {
                    !pending_event_is_protected(&entry.event.kind)
                        && !pending_event_is_critical(&entry.event.kind)
                })
            })
            // A critical-only flood cannot be both lossless and hard-bounded.
            // Prefer retaining `exit`; otherwise discard the oldest clipboard
            // request only after every non-critical event is gone.
            .or_else(|| {
                self.entries.iter().position(|entry| {
                    !pending_event_is_protected(&entry.event.kind) && entry.event.kind != "exit"
                })
            })
            .or_else(|| {
                self.entries
                    .iter()
                    .position(|entry| !pending_event_is_protected(&entry.event.kind))
            })
            // Keep the newly appended event when possible, but never let a
            // protected-event flood defeat the queue's hard count/byte caps.
            .or_else(|| (self.entries.len() > 1).then_some(0))
    }

    fn record_drop(&mut self) -> PendingEventPushResult {
        self.dropped_count = self.dropped_count.saturating_add(1);
        self.dropped_since_last_drain = self.dropped_since_last_drain.saturating_add(1);
        let emit_overflow_diagnostic = !self.overflow_diagnostic_emitted;
        self.overflow_diagnostic_emitted = true;
        PendingEventPushResult {
            emit_overflow_diagnostic,
        }
    }

    pub(super) fn drain(&mut self) -> Vec<TerminalEvent> {
        self.aggregate_bytes = 0;
        self.dropped_since_last_drain = 0;
        self.entries.drain(..).map(|entry| entry.event).collect()
    }

    pub(super) fn drain_event_batch(&mut self, session_id: u64) -> Option<RuntimeEventBatchV1> {
        if self.entries.is_empty() && self.dropped_since_last_drain == 0 {
            return None;
        }

        self.aggregate_bytes = 0;
        let dropped_count = std::mem::take(&mut self.dropped_since_last_drain);
        let entries = self.entries.drain(..).collect::<Vec<_>>();
        let messages = entries
            .into_iter()
            .map(|entry| {
                let request = host_request_v1_from_event(
                    session_id,
                    entry.sequence,
                    entry.timestamp_micros,
                    &entry.event.kind,
                    entry.event.payload.clone(),
                );
                if let Some(request) = request
                    && let Some(pending) = pending_host_request(&request)
                    && let Ok(payload) = serde_json::to_value(request)
                {
                    self.pending_host_requests.push_back(pending);
                    while self.pending_host_requests.len() > MAX_PENDING_HOST_REQUESTS {
                        self.pending_host_requests.pop_front();
                    }
                    return RuntimeEnvelopeV1::event(
                        session_id,
                        entry.sequence,
                        entry.timestamp_micros,
                        HOST_REQUEST_EVENT_NAME.to_string(),
                        Some(payload),
                    );
                }
                RuntimeEnvelopeV1::event(
                    session_id,
                    entry.sequence,
                    entry.timestamp_micros,
                    entry.event.kind,
                    entry.event.payload,
                )
            })
            .collect();
        Some(RuntimeEventBatchV1::new(
            session_id,
            self.next_sequence,
            dropped_count,
            messages,
        ))
    }

    pub(super) fn resolve_host_response(
        &mut self,
        session_id: u64,
        raw: &str,
    ) -> Result<Option<Vec<u8>>, HostResponseError> {
        let response = HostResponseV1::decode_json(raw, session_id)?;
        let index = self
            .pending_host_requests
            .iter()
            .position(|pending| pending.request_id == response.request_id)
            .ok_or(HostResponseError::CorrelationMismatch)?;
        let bytes = resolve_host_response(&response, &self.pending_host_requests[index])?;
        self.pending_host_requests.remove(index);
        Ok(bytes)
    }

    pub(super) fn len(&self) -> usize {
        self.entries.len()
    }
}

fn pending_event_is_coalescible(kind: &str) -> bool {
    matches!(
        kind,
        "bell"
            | "resize"
            | "shell_context"
            | "session_progress"
            | "session_badge"
            | "zmodem_progress"
    )
}

fn pending_event_is_critical(kind: &str) -> bool {
    matches!(
        kind,
        "exit"
            | "ssh_auth_prompt"
            | "ssh_host_key_prompt"
            | "clipboard_copy"
            | "clipboard_paste_request"
            | "clipboard_mime_write"
            | "clipboard_mime_read_request"
            | "clipboard_mime_error"
            | "session_reset"
            | "zmodem_completed"
            | "zmodem_failed"
            | "zmodem_cancelled"
            | ZMODEM_DEFERRED_WRITE_FAILED_KIND
    )
}

fn pending_event_is_protected(kind: &str) -> bool {
    matches!(
        kind,
        "zmodem_detected"
            | "zmodem_file_offer"
            | "zmodem_started"
            | "zmodem_file_completed"
            | "zmodem_file_skipped"
            | "zmodem_completed"
            | "zmodem_failed"
            | "zmodem_cancelled"
            | ZMODEM_DEFERRED_WRITE_FAILED_KIND
    )
}

fn zmodem_progress_transfer_id(event: &TerminalEvent) -> Option<&str> {
    (event.kind == "zmodem_progress")
        .then(|| event.payload.as_ref()?.get("transferId")?.as_str())?
}

pub(super) fn terminal_event_wire_size(event: &TerminalEvent) -> usize {
    // Fixed JSON object keys/punctuation plus the largest u64 session id.
    64usize
        .saturating_add(json_string_wire_size(&event.kind))
        .saturating_add(event.payload.as_ref().map_or(4, json_value_wire_size))
}

fn json_value_wire_size(value: &serde_json::Value) -> usize {
    match value {
        serde_json::Value::Null => 4,
        serde_json::Value::Bool(true) => 4,
        serde_json::Value::Bool(false) => 5,
        serde_json::Value::Number(number) => number.to_string().len(),
        serde_json::Value::String(value) => json_string_wire_size(value),
        serde_json::Value::Array(values) => values.iter().fold(2usize, |size, value| {
            size.saturating_add(json_value_wire_size(value))
                .saturating_add(1)
        }),
        serde_json::Value::Object(values) => values.iter().fold(2usize, |size, (key, value)| {
            size.saturating_add(json_string_wire_size(key))
                .saturating_add(1)
                .saturating_add(json_value_wire_size(value))
                .saturating_add(1)
        }),
    }
}

fn json_string_wire_size(value: &str) -> usize {
    value.chars().fold(2usize, |size, character| {
        let encoded = match character {
            '"' | '\\' | '\u{0008}' | '\u{000c}' | '\n' | '\r' | '\t' => 2,
            character if character <= '\u{001f}' => 6,
            character => character.len_utf8(),
        };
        size.saturating_add(encoded)
    })
}
