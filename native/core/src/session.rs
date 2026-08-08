use crate::frame_diff_proto;
use crate::graphic_asset_proto;
use crate::host_request::{
    HOST_REQUEST_EVENT_NAME, HostResponseError, HostResponseV1, PendingHostRequestV1,
    host_request_v1_from_event, pending_host_request, resolve_host_response,
};
#[cfg(test)]
use crate::model::TerminalProfileConnection;
use crate::model::{
    MAX_SCROLLBACK_LINES, TERMINAL_FRAME_SCHEMA_VERSION, TerminalBlock, TerminalCursor,
    TerminalCursorShape, TerminalEmulation, TerminalEvent, TerminalFrameDiff, TerminalFrameKind,
    TerminalFrameModes, TerminalHyperlinkRange, TerminalInlineButton, TerminalProfile,
    TerminalProfileAnsiColors, TerminalProfileColors, TerminalProfileFont, TerminalRow,
    TerminalSearchMatch, TerminalSelectionRequest, TerminalSizedTextPlacement, TerminalStyleRun,
    normalize_scrollback_lines,
};
use crate::pty::spawn_terminal_transport;
use crate::runtime_contract::{
    GRAPHIC_ASSET_PACKET_MAX_RGBA_BYTES, RuntimeEnvelopeV1, RuntimeEventBatchV1,
};
use crate::session_config::SessionConfigV1;
use crate::zmodem::{
    RECEIVE_COMMIT_CANCELLED, RECEIVE_COMMIT_IDLE, RECEIVE_COMMIT_PUBLISHING,
    RECEIVE_COMMIT_RESULT_READY, ZmodemDirection, ZmodemEffects, ZmodemError, ZmodemManager,
};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use par_term_emu_core_rust::cell::{Cell, CellFlags};
use par_term_emu_core_rust::color::Color;
use par_term_emu_core_rust::graphics::PLACEHOLDER_CHAR;
#[cfg(test)]
use par_term_emu_core_rust::graphics::{ImageDimension, TerminalGraphic};
use par_term_emu_core_rust::grid::Grid;
use par_term_emu_core_rust::mouse::{MouseEncoding, MouseMode};
#[cfg(test)]
use par_term_emu_core_rust::terminal::ItermAttentionAction;
use par_term_emu_core_rust::terminal::terminal_snapshot::TerminalSnapshot;
use par_term_emu_core_rust::terminal::{
    ItermButtonKind, OscCapability, Terminal, TerminalEvent as ParserTerminalEvent,
    TerminalProcessDebugStats, TransferDirection, TransferStatus, snapshot::ExportFormat,
};
use par_term_emu_core_rust::{WidthConfig, str_width};
use parking_lot::{Mutex, MutexGuard};
use regex::RegexBuilder;
use std::collections::{BTreeMap, HashMap, VecDeque};
use std::hash::{DefaultHasher, Hash, Hasher};
use std::io::{Read, Write};
use std::sync::{
    Arc, LazyLock,
    atomic::{AtomicBool, AtomicU8, AtomicU64, AtomicUsize, Ordering},
    mpsc,
};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

mod frame;
mod recording;

use frame::{
    CachedFrameMeta, CachedRowState, CollapsedBlockRange, DeltaFrameContext, DisplayProjection,
    FrameBuildContext, GraphicAssetSnapshot, PendingFrameWork, build_delta_frame,
    build_projected_graphic_placements, build_snapshot_frame, display_projection_for_terminal,
    graphic_asset_snapshots, projection_source_span, resolve_viewport_row_shift,
    snapshot_fallback_reason,
};
#[cfg(test)]
use frame::{
    PendingScrollRegion, build_graphic_placements, delta_candidate_row_indexes,
    graphic_placement_for_viewport,
};
use recording::{RecordingError, RecordingInputPolicy, SessionRecording};

const DEFAULT_ROWS: u16 = 32;
const DEFAULT_COLS: u16 = 120;
const MAX_TRANSCRIPT_BYTES: usize = 256 * 1024;
const RESOURCE_SAMPLE_CAPACITY: usize = 60;
const MAX_PENDING_SESSION_EVENTS: usize = 1024;
const MAX_PENDING_SESSION_EVENT_BYTES: usize = 8 * 1024 * 1024;
const MAX_PENDING_HOST_REQUESTS: usize = 64;
const MAX_DEFERRED_PTY_WRITE_BYTES: usize = 16 * 1024 * 1024;
const MAX_DEFERRED_PTY_WRITE_CHUNKS: usize = 2048;
const MAX_RECENT_ZMODEM_TERMINAL_IDS: usize = 256;
const MAX_DIAGNOSTIC_EVENTS: usize = 256;
const EVENT_QUEUE_OVERFLOW_DIAGNOSTIC_KIND: &str = "event_queue_overflow";
const ZMODEM_DEFERRED_WRITE_FAILED_KIND: &str = "zmodem_deferred_write_failed";
const ZMODEM_BLOCKED_IO_TIMEOUT: Duration = Duration::from_secs(60);
const ZMODEM_COMPLETION_POLL_INTERVAL: Duration = Duration::from_millis(50);
const ZMODEM_WIRE_MAX_QUEUED_BYTES: usize = 1024 * 1024;
const RESOURCE_SAMPLE_INTERVAL: Duration = Duration::from_secs(1);
const ZMODEM_DEADLINE_POLL_INTERVAL: Duration = Duration::from_millis(50);
const PTY_READER_POLL_INTERVAL: Duration = Duration::from_millis(50);
const INLINE_CLEAR_REPAINT_GRACE: Duration = Duration::from_millis(180);
const RESOURCE_SAMPLER_MAX_FAILURES: u64 = 5;

#[cfg(test)]
thread_local! {
    static FAIL_NEXT_ZMODEM_WRITER_THREAD_SPAWN: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

fn inject_zmodem_writer_thread_spawn_failure() -> bool {
    #[cfg(test)]
    {
        FAIL_NEXT_ZMODEM_WRITER_THREAD_SPAWN.with(|flag| flag.replace(false))
    }
    #[cfg(not(test))]
    false
}

fn pty_read_error_is_trusted_eof(error: &std::io::Error) -> bool {
    #[cfg(unix)]
    {
        // PTY masters conventionally report EIO, rather than Ok(0), after
        // the slave side closes. Treat that specific transport boundary as
        // EOF so a receiver that already replied to ZFIN can complete even
        // when the final OO is swallowed by the PTY teardown.
        error.raw_os_error() == Some(libc::EIO)
    }
    #[cfg(not(unix))]
    {
        let _ = error;
        false
    }
}

/// Wait until a Unix PTY master is readable without committing the reader
/// thread to an unbounded `read`. A timeout after the child-exit flag is
/// visible is an ordered drain barrier: all bytes written before that exit
/// have either been routed by the sole reader or are reported readable by the
/// second poll iteration.
fn wait_for_pty_readable(poll_handle: Option<&std::fs::File>) -> std::io::Result<bool> {
    #[cfg(unix)]
    if let Some(poll_handle) = poll_handle {
        use std::os::fd::AsRawFd as _;
        let mut descriptor = libc::pollfd {
            fd: poll_handle.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let timeout_millis =
            i32::try_from(PTY_READER_POLL_INTERVAL.as_millis()).unwrap_or(i32::MAX);
        let result = unsafe { libc::poll(&mut descriptor, 1, timeout_millis) };
        if result < 0 {
            return Err(std::io::Error::last_os_error());
        }
        return Ok(result > 0);
    }

    let _ = poll_handle;
    Ok(true)
}
const MAX_GRAPHIC_ASSET_SNAPSHOTS: usize = 128;
const VT220_PRIMARY_DA_RESPONSE: &str = "\x1b[?62;1;2;6;7;8;9c";
const VT220_SECONDARY_DA_RESPONSE: &str = "\x1b[>1;10;0c";
const OSC5522_MAX_TOTAL_BYTES: usize = 4 * 1024 * 1024;
const OSC5522_MAX_CHUNK_BYTES: usize = 4096;
const OSC5522_MAX_MIME_TYPES: usize = 64;
const OSC5522_MAX_MIME_BYTES: usize = 255;
const OSC5522_MAX_ID_BYTES: usize = 128;
const OSC5522_MAX_PASSWORD_BYTES: usize = 256;
const OSC5522_MAX_APPLICATION_NAME_BYTES: usize = 256;
const ITERM_CLIPBOARD_MAX_BYTES: usize = 4 * 1024 * 1024;
const ITERM_FILE_DOWNLOAD_MAX_BYTES: usize = 16 * 1024 * 1024;
const ITERM_FILE_DOWNLOAD_MAX_PENDING: usize = 8;
const MAX_REPLAY_CHECKPOINTS: usize = 64;
const MAX_REPLAY_CHECKPOINT_BYTES: usize = 32 * 1024 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TerminalSearchMode {
    SmartCaseSubstring,
    CaseSensitiveSubstring,
    CaseInsensitiveSubstring,
    CaseSensitiveRegex,
    CaseInsensitiveRegex,
}

enum ItermButtonActivation {
    Copy(String),
    Custom(i32),
}

impl TerminalSearchMode {
    fn from_wire(value: Option<&str>) -> Self {
        match value {
            Some("case_sensitive_substring") => Self::CaseSensitiveSubstring,
            Some("case_insensitive_substring") => Self::CaseInsensitiveSubstring,
            Some("case_sensitive_regex") => Self::CaseSensitiveRegex,
            Some("case_insensitive_regex") => Self::CaseInsensitiveRegex,
            Some("smart_case_substring") => Self::SmartCaseSubstring,
            _ => Self::SmartCaseSubstring,
        }
    }

    fn case_sensitive(self, query: &str) -> bool {
        match self {
            Self::SmartCaseSubstring => query.chars().any(char::is_uppercase),
            Self::CaseSensitiveSubstring | Self::CaseSensitiveRegex => true,
            Self::CaseInsensitiveSubstring | Self::CaseInsensitiveRegex => false,
        }
    }

    fn is_regex(self) -> bool {
        matches!(self, Self::CaseSensitiveRegex | Self::CaseInsensitiveRegex)
    }
}

#[derive(Debug, serde::Serialize)]
struct TerminalSearchResponse {
    matches: Vec<TerminalSearchMatch>,
    error_text: Option<&'static str>,
}

#[derive(Debug)]
struct TerminalSearchRow {
    row: usize,
    text: String,
    wrapped: bool,
    scrollback_offset: usize,
}

#[derive(Debug)]
struct TerminalSearchLogicalSegment {
    row: usize,
    text: String,
    start_byte: usize,
    scrollback_offset: usize,
}

static STORE: LazyLock<SessionStore> = LazyLock::new(SessionStore::default);

pub const REFRESH_HINT_FRAME_DIRTY: u32 = 1 << 0;
pub const REFRESH_HINT_EVENT_PENDING: u32 = 1 << 1;
pub const REFRESH_HINT_EXIT_PENDING: u32 = 1 << 2;

#[derive(Clone, Debug)]
enum CallbackEvent {
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

#[derive(Clone, Copy, Debug)]
struct PendingEventLimits {
    max_count: usize,
    max_bytes: usize,
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
struct QueuedTerminalEvent {
    event: TerminalEvent,
    wire_bytes: usize,
    sequence: u64,
    timestamp_micros: u64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct PendingEventPushResult {
    emit_overflow_diagnostic: bool,
}

#[derive(Debug, Default)]
struct PendingEventQueue {
    entries: VecDeque<QueuedTerminalEvent>,
    pending_host_requests: VecDeque<PendingHostRequestV1>,
    aggregate_bytes: usize,
    dropped_count: u64,
    dropped_since_last_drain: u64,
    next_sequence: u64,
    overflow_diagnostic_emitted: bool,
    limits: PendingEventLimits,
}

impl PendingEventQueue {
    fn with_initial(event: TerminalEvent) -> Self {
        let mut queue = Self::default();
        let _ = queue.push(event);
        queue
    }

    fn has_pending_zmodem_terminal_result(&self) -> bool {
        self.entries.iter().any(|entry| {
            matches!(
                entry.event.kind.as_str(),
                "zmodem_completed" | "zmodem_failed" | "zmodem_cancelled"
            )
        })
    }

    #[cfg(test)]
    fn with_limits(max_count: usize, max_bytes: usize) -> Self {
        Self {
            limits: PendingEventLimits {
                max_count,
                max_bytes,
            },
            ..Self::default()
        }
    }

    fn push(&mut self, event: TerminalEvent) -> PendingEventPushResult {
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

    fn drain(&mut self) -> Vec<TerminalEvent> {
        self.aggregate_bytes = 0;
        self.dropped_since_last_drain = 0;
        self.entries.drain(..).map(|entry| entry.event).collect()
    }

    fn drain_event_batch(&mut self, session_id: u64) -> Option<RuntimeEventBatchV1> {
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

    fn resolve_host_response(
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

    fn len(&self) -> usize {
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

fn terminal_event_wire_size(event: &TerminalEvent) -> usize {
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

#[derive(Clone, Debug)]
struct DeferredFrameGrace {
    damage_generation: u64,
    started_at: Instant,
}

struct PendingFrameSignal {
    dirty: AtomicBool,
    refresh_hint_dirty: AtomicBool,
    work: Mutex<PendingFrameWork>,
}

impl PendingFrameSignal {
    fn new(initially_dirty: bool) -> Self {
        Self {
            dirty: AtomicBool::new(initially_dirty),
            refresh_hint_dirty: AtomicBool::new(initially_dirty),
            work: Mutex::new(PendingFrameWork::default()),
        }
    }

    fn is_dirty(&self) -> bool {
        self.dirty.load(Ordering::SeqCst)
    }

    fn mutate(&self, mutation: impl FnOnce(&mut PendingFrameWork)) {
        self.mutate_inner(false, mutation);
    }

    fn mutate_reader(&self, mutation: impl FnOnce(&mut PendingFrameWork)) {
        self.mutate_inner(true, mutation);
    }

    fn mutate_inner(&self, sets_refresh_hint: bool, mutation: impl FnOnce(&mut PendingFrameWork)) {
        let mut work = self.work.lock();
        mutation(&mut work);
        self.dirty.store(true, Ordering::SeqCst);
        if sets_refresh_hint {
            self.refresh_hint_dirty.store(true, Ordering::SeqCst);
        }
    }

    fn take(&self) -> (bool, bool, PendingFrameWork) {
        let mut work = self.work.lock();
        let was_dirty = self.dirty.swap(false, Ordering::SeqCst);
        let refresh_hint_was_dirty = self.refresh_hint_dirty.swap(false, Ordering::SeqCst);
        (
            was_dirty,
            refresh_hint_was_dirty,
            std::mem::take(&mut *work),
        )
    }

    fn restore(&self, deferred_work: PendingFrameWork, restore_refresh_hint: bool) {
        let mut current_work = self.work.lock();
        if current_work.is_empty() {
            *current_work = deferred_work;
        } else if !deferred_work.is_empty() {
            let damage_generation = current_work
                .damage_generation
                .max(deferred_work.damage_generation)
                .saturating_add(1);
            let cursor_before = deferred_work
                .cursor_before
                .or_else(|| current_work.cursor_before.take());
            let cursor_after = current_work
                .cursor_after
                .take()
                .or(deferred_work.cursor_after);
            let snapshot_fallback_reason = deferred_work
                .snapshot_fallback_reason
                .or_else(|| current_work.snapshot_fallback_reason.take())
                .or_else(|| Some("concurrent_deferred_damage".to_string()));
            *current_work = PendingFrameWork {
                full_repaint: true,
                snapshot_fallback_reason,
                cursor_before,
                cursor_after,
                damage_generation,
                ..PendingFrameWork::default()
            };
        }
        self.dirty.store(true, Ordering::SeqCst);
        if restore_refresh_hint {
            self.refresh_hint_dirty.store(true, Ordering::SeqCst);
        }
    }

    fn has_refresh_hint(&self) -> bool {
        self.refresh_hint_dirty.load(Ordering::SeqCst)
    }

    fn snapshot(&self) -> PendingFrameWork {
        self.work.lock().clone()
    }
}

fn should_defer_frame_with_grace(
    deferred_frame: &Mutex<Option<DeferredFrameGrace>>,
    damage_generation: u64,
    grace: Duration,
) -> bool {
    let mut deferred = deferred_frame.lock();
    if let Some(frame) = deferred
        .as_ref()
        .filter(|frame| frame.damage_generation == damage_generation)
    {
        if frame.started_at.elapsed() < grace {
            return true;
        }
        *deferred = None;
        return false;
    }

    *deferred = Some(DeferredFrameGrace {
        damage_generation,
        started_at: Instant::now(),
    });
    true
}

#[derive(Clone, Debug, serde::Serialize)]
struct FrameDebugStats {
    rows_scanned: usize,
    rows_emitted: usize,
    frame_build_micros: u64,
    state_lock_wait_micros: u64,
    frame_extract_micros: u64,
    json_encode_micros: u64,
    protobuf_encode_micros: u64,
    full_repaint: bool,
    snapshot_fallback_reason: Option<String>,
    viewport_row_shift: i32,
    damage_generation: u64,
    active_graphics_count: usize,
    scrollback_graphics_count: usize,
    graphic_placements_count: usize,
}

#[derive(Clone, Debug, Default, serde::Serialize)]
struct SessionDebugStats {
    bytes_read: u64,
    read_chunks: u64,
    host_protocol_micros: u64,
    terminal_process_micros: u64,
    terminal_process_breakdown: TerminalProcessDebugStats,
    damage_merge_micros: u64,
    response_write_micros: u64,
    transcript_bytes: usize,
    transcript_truncated: bool,
    resize_replay_count: u64,
    resize_replay_bytes: u64,
    resize_replay_micros: u64,
    resize_replay_skipped_truncated_count: u64,
    osc_ingress_accepted: u64,
    osc_ingress_oversized: u64,
    osc_ingress_policy_denied: u64,
    synchronized_update_discards: u64,
    non_sixel_dcs_discards: u64,
    response_buffer_overflows: u64,
    vendor_terminal_event_drops: u64,
    tmux_notification_drops: u64,
    recording_dropped_events: u64,
    pending_dirty_rows: usize,
    pending_scroll_region: Option<SessionDebugScrollRegion>,
    pending_event_count: usize,
    pending_event_bytes: usize,
    pending_event_dropped_count: u64,
    pending_event_overflowed: bool,
}

#[derive(Clone, Debug, serde::Serialize)]
struct SessionDebugScrollRegion {
    top: usize,
    bottom_exclusive: usize,
    delta_rows: i32,
}

#[derive(Clone, Debug, serde::Serialize)]
struct ResourceSample {
    timestamp_micros: u64,
    session_id: u64,
    child_pid: Option<u32>,
    process_name: String,
    cpu_percent: Option<f64>,
    rss_bytes: Option<u64>,
    virtual_bytes: Option<u64>,
    thread_count: Option<i32>,
    total_user_micros: Option<u64>,
    total_system_micros: Option<u64>,
    sample_error: Option<String>,
}

#[derive(Clone, Debug, Default)]
struct ResourceSamplerState {
    previous_total_cpu_micros: Option<u64>,
    previous_sampled_at: Option<Instant>,
    consecutive_failures: u64,
}

#[derive(Clone, Debug, serde::Serialize)]
struct TerminalDiagnosticEvent {
    timestamp_micros: u64,
    session_id: u64,
    kind: String,
    payload: Option<serde_json::Value>,
}

#[derive(Clone, Debug)]
struct ProcessResourceSnapshot {
    rss_bytes: u64,
    virtual_bytes: u64,
    total_user_micros: u64,
    total_system_micros: u64,
    thread_count: i32,
}

struct PendingChildExit {
    exit_code: Option<i32>,
    payload: serde_json::Value,
}

#[derive(Clone, Debug)]
struct TerminalDiagnosticsRequest {
    max_samples: usize,
    include_content: bool,
    redaction_mode: String,
}

#[derive(Clone, Debug, serde::Serialize)]
struct TerminalDiagnosticsSummary {
    conclusion: String,
    attribution_scores: TerminalDiagnosticsScores,
    evidence: Vec<String>,
    privacy: Vec<String>,
    next_steps: Vec<String>,
    markdown: String,
}

#[derive(Clone, Debug, serde::Serialize)]
struct TerminalDiagnosticsScores {
    user_command: f64,
    native_parser_pty: f64,
    flutter_ui_render: f64,
    insufficient_evidence: f64,
}

#[derive(Default)]
pub struct SessionStore {
    sessions: Mutex<HashMap<u64, Arc<TerminalSession>>>,
    next_id: Mutex<u64>,
}

impl SessionStore {
    fn next_session_id(&self) -> u64 {
        let mut next_id = self.next_id.lock();
        *next_id += 1;
        *next_id
    }

    pub fn create_session(&self, profile: TerminalProfile) -> Result<u64, SessionError> {
        self.create_session_with_zmodem(profile, false)
    }

    fn create_session_with_zmodem(
        &self,
        profile: TerminalProfile,
        zmodem_enabled: bool,
    ) -> Result<u64, SessionError> {
        let session_id = self.next_session_id();
        let session = TerminalSession::spawn_with_zmodem(session_id, profile, zmodem_enabled)?;
        self.sessions.lock().insert(session_id, session);
        Ok(session_id)
    }

    pub fn create_replay_session(&self, profile: TerminalProfile) -> Result<u64, SessionError> {
        let session_id = self.next_session_id();
        let session = TerminalSession::spawn_replay(session_id, profile)?;
        self.sessions.lock().insert(session_id, session);
        Ok(session_id)
    }

    pub fn get(&self, session_id: u64) -> Result<Arc<TerminalSession>, SessionError> {
        self.sessions
            .lock()
            .get(&session_id)
            .cloned()
            .ok_or(SessionError::MissingSession(session_id))
    }

    pub fn close_session(&self, session_id: u64) -> Result<(), SessionError> {
        let session = self.sessions.lock().get(&session_id).cloned();
        if let Some(session) = session {
            // Keep the store authority and event queue reachable when a
            // receive publication is at its atomic commit boundary. The
            // caller can drain the completion/recovery event and retry close.
            session.close()?;
            self.sessions.lock().remove(&session_id);
        }
        Ok(())
    }
}

#[derive(thiserror::Error, Debug)]
pub enum SessionError {
    #[error("missing session {0}")]
    MissingSession(u64),
    #[error("invalid profile JSON: {0}")]
    InvalidProfile(String),
    #[error("invalid SessionConfig: {0}")]
    InvalidSessionConfig(String),
    #[error("invalid selection JSON: {0}")]
    InvalidSelection(String),
    #[error("pty error: {0}")]
    Pty(String),
    #[error("io error: {0}")]
    Io(String),
    #[error("session {0} is not a replay session")]
    NotReplaySession(u64),
    #[error("replay session {0} is read-only")]
    ReadOnlyReplaySession(u64),
    #[error("replay checkpoint {checkpoint_id} is unavailable for session {session_id}")]
    MissingReplayCheckpoint { session_id: u64, checkpoint_id: u64 },
    #[error("replay checkpoint capacity exceeded")]
    ReplayCheckpointCapacity,
    #[error("replay checkpoint requires a complete control-sequence boundary")]
    UnsafeReplayCheckpoint,
    #[error("serialization error: {0}")]
    Serialize(String),
    #[error("graphic asset error: {0}")]
    GraphicAsset(String),
    #[error("file download error: {0}")]
    FileDownload(String),
    #[error("Host Response error: {0}")]
    HostResponse(String),
    #[error("ZMODEM error: {0}")]
    Zmodem(String),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GraphicAssetMeta {
    pub width: u32,
    pub height: u32,
    pub rgba_len: usize,
    pub version: u64,
}

#[derive(Debug)]
struct PendingFileDownload {
    id: u64,
    data: Vec<u8>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum ReplayCheckpointBoundary {
    #[default]
    Ground,
    Escape,
    Csi,
    Osc,
    ControlString,
    OscEscape,
    ControlStringEscape,
}

impl ReplayCheckpointBoundary {
    fn add(&mut self, bytes: &[u8]) {
        for &byte in bytes {
            self.add_byte(byte);
        }
    }

    fn add_byte(&mut self, byte: u8) {
        if matches!(byte, 0x18 | 0x1a | 0x9c) {
            *self = Self::Ground;
            return;
        }
        *self = match *self {
            Self::Ground => match byte {
                0x1b => Self::Escape,
                0x9b => Self::Csi,
                0x9d => Self::Osc,
                0x90 | 0x98 | 0x9e | 0x9f => Self::ControlString,
                _ => Self::Ground,
            },
            Self::Escape => match byte {
                0x1b => Self::Escape,
                b'[' => Self::Csi,
                b']' => Self::Osc,
                b'P' | b'X' | b'^' | b'_' => Self::ControlString,
                0x20..=0x2f => Self::Escape,
                _ => Self::Ground,
            },
            Self::Csi => {
                if byte == 0x1b {
                    Self::Escape
                } else if (0x40..=0x7e).contains(&byte) {
                    Self::Ground
                } else {
                    Self::Csi
                }
            }
            Self::Osc => match byte {
                0x07 => Self::Ground,
                0x1b => Self::OscEscape,
                _ => Self::Osc,
            },
            Self::ControlString => {
                if byte == 0x1b {
                    Self::ControlStringEscape
                } else {
                    Self::ControlString
                }
            }
            Self::OscEscape => match byte {
                b'\\' | 0x07 => Self::Ground,
                0x1b => Self::OscEscape,
                _ => Self::Osc,
            },
            Self::ControlStringEscape => match byte {
                b'\\' => Self::Ground,
                0x1b => Self::ControlStringEscape,
                _ => Self::ControlString,
            },
        };
    }

    fn is_safe(self) -> bool {
        self == Self::Ground
    }
}

struct TerminalState {
    terminal: Terminal,
    transcript: Vec<u8>,
    transcript_truncated: bool,
    scrollback_offset: usize,
    host_protocol: HostProtocolState,
    graphic_assets: VecDeque<GraphicAssetSnapshot>,
    graphic_asset_bytes: usize,
    graphic_asset_cache_max_bytes: usize,
    pending_file_downloads: VecDeque<PendingFileDownload>,
    pending_file_download_bytes: usize,
    next_file_download_id: u64,
    replay_checkpoint_boundary: ReplayCheckpointBoundary,
}

impl TerminalState {
    fn retain_file_download(
        &mut self,
        filename: String,
        data: Vec<u8>,
    ) -> Result<(u64, String, usize), String> {
        let size = data.len();
        if size > ITERM_FILE_DOWNLOAD_MAX_BYTES {
            return Err(format!(
                "download exceeds maximum size of {ITERM_FILE_DOWNLOAD_MAX_BYTES} bytes"
            ));
        }
        if self.pending_file_downloads.len() >= ITERM_FILE_DOWNLOAD_MAX_PENDING {
            return Err("too many pending downloads".to_string());
        }
        if self.pending_file_download_bytes.saturating_add(size) > ITERM_FILE_DOWNLOAD_MAX_BYTES {
            return Err("pending download memory budget exhausted".to_string());
        }

        let filename = sanitize_file_download_name(&filename);
        let id = self.next_file_download_id.max(1);
        self.next_file_download_id = id.checked_add(1).unwrap_or(1);
        self.pending_file_download_bytes = self.pending_file_download_bytes.saturating_add(size);
        self.pending_file_downloads
            .push_back(PendingFileDownload { id, data });
        Ok((id, filename, size))
    }

    fn take_file_download(
        &mut self,
        download_id: u64,
        dst: &mut [u8],
    ) -> Result<usize, SessionError> {
        let index = self
            .pending_file_downloads
            .iter()
            .position(|download| download.id == download_id)
            .ok_or_else(|| SessionError::FileDownload(format!("missing download {download_id}")))?;
        let expected_len = self.pending_file_downloads[index].data.len();
        if dst.len() != expected_len {
            return Err(SessionError::FileDownload(format!(
                "destination length {} does not match download size {expected_len}",
                dst.len()
            )));
        }
        dst.copy_from_slice(&self.pending_file_downloads[index].data);
        let removed = self
            .pending_file_downloads
            .remove(index)
            .expect("pending download index was validated");
        self.pending_file_download_bytes = self
            .pending_file_download_bytes
            .saturating_sub(removed.data.len());
        Ok(expected_len)
    }

    fn discard_file_download(&mut self, download_id: u64) -> Result<(), SessionError> {
        let index = self
            .pending_file_downloads
            .iter()
            .position(|download| download.id == download_id)
            .ok_or_else(|| SessionError::FileDownload(format!("missing download {download_id}")))?;
        let removed = self
            .pending_file_downloads
            .remove(index)
            .expect("pending download index was validated");
        self.pending_file_download_bytes = self
            .pending_file_download_bytes
            .saturating_sub(removed.data.len());
        Ok(())
    }
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
struct ItermClipboardCaptureState {
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
struct HostProtocolState {
    buffer: Vec<u8>,
    application_keypad: bool,
    osc5522_write: Option<Osc5522WriteState>,
    iterm_clipboard_capture: Option<ItermClipboardCaptureState>,
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
    fn observe(&mut self, bytes: &[u8], emulation: TerminalEmulation) -> Vec<CallbackEvent> {
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

#[derive(Clone)]
struct ReplayCheckpoint {
    id: u64,
    snapshot: TerminalSnapshot,
    transcript: Vec<u8>,
    transcript_truncated: bool,
    scrollback_offset: usize,
    host_protocol: HostProtocolState,
    estimated_size_bytes: usize,
}

#[derive(Default)]
struct ReplayCheckpointStore {
    entries: VecDeque<ReplayCheckpoint>,
    retained_bytes: usize,
    next_id: u64,
}

impl ReplayCheckpointStore {
    fn capture(&mut self, state: &TerminalState) -> Result<u64, SessionError> {
        if !state.replay_checkpoint_boundary.is_safe() {
            return Err(SessionError::UnsafeReplayCheckpoint);
        }
        let snapshot = state.terminal.capture_snapshot();
        let estimated_size_bytes = snapshot
            .estimated_size_bytes
            .saturating_add(state.transcript.len())
            .saturating_add(state.host_protocol.buffer.len());
        if estimated_size_bytes > MAX_REPLAY_CHECKPOINT_BYTES {
            return Err(SessionError::ReplayCheckpointCapacity);
        }
        while self.entries.len() >= MAX_REPLAY_CHECKPOINTS
            || self.retained_bytes.saturating_add(estimated_size_bytes)
                > MAX_REPLAY_CHECKPOINT_BYTES
        {
            let Some(removed) = self.entries.pop_front() else {
                break;
            };
            self.retained_bytes = self
                .retained_bytes
                .saturating_sub(removed.estimated_size_bytes);
        }
        self.next_id = self.next_id.saturating_add(1).max(1);
        let id = self.next_id;
        self.entries.push_back(ReplayCheckpoint {
            id,
            snapshot,
            transcript: state.transcript.clone(),
            transcript_truncated: state.transcript_truncated,
            scrollback_offset: state.scrollback_offset,
            host_protocol: state.host_protocol.clone(),
            estimated_size_bytes,
        });
        self.retained_bytes = self.retained_bytes.saturating_add(estimated_size_bytes);
        Ok(id)
    }

    fn get(&self, checkpoint_id: u64) -> Option<ReplayCheckpoint> {
        self.entries
            .iter()
            .find(|entry| entry.id == checkpoint_id)
            .cloned()
    }
}

#[cfg(test)]
fn callback_event_from_parser_event(
    event: ParserTerminalEvent,
    suppress_shell_zones: bool,
) -> Option<CallbackEvent> {
    callback_event_from_parser_event_with_terminal(event, suppress_shell_zones, None)
}

fn callback_event_from_parser_event_with_terminal(
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

fn callback_events_from_parser_events(
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

fn discard_replayed_parser_host_events(terminal: &mut Terminal) {
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

fn validated_iterm_attention_action(value: &str) -> Option<&'static str> {
    match value {
        "yes" => Some("yes"),
        "once" => Some("once"),
        "no" => Some("no"),
        "fireworks" => Some("fireworks"),
        _ => None,
    }
}

fn input_sets_alt_screen(input: &[u8]) -> bool {
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

fn shell_context_payload_from_current_dir(data: &str) -> Option<serde_json::Value> {
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

fn sanitize_protocol_text(value: &str, max_chars: usize) -> String {
    value
        .chars()
        .filter(|ch| !ch.is_control())
        .take(max_chars)
        .collect::<String>()
        .trim()
        .to_string()
}

fn sanitize_file_download_name(value: &str) -> String {
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

pub struct TerminalSession {
    session_id: u64,
    emulation: TerminalEmulation,
    scrollback_lines: usize,
    graphics_enabled: bool,
    drag_drop_enabled: bool,
    graphics_memory_limits: Option<TerminalGraphicsMemoryLimits>,
    profile_colors: TerminalProfileColors,
    profile_font: TerminalProfileFont,
    osc633_expected_nonce: Option<String>,
    state: Mutex<TerminalState>,
    writer: Mutex<Option<Box<dyn Write + Send>>>,
    ssh_auth: Option<crate::ssh::SshAuthClient>,
    // SessionConfig v1 must explicitly opt in. Legacy clients do not know how
    // to authorize or complete transfers and therefore keep raw PTY behavior.
    zmodem_enabled: AtomicBool,
    zmodem: Mutex<ZmodemManager>,
    zmodem_sequence_gate: Mutex<()>,
    // Makes terminal ZMODEM event insertion + commit-phase release atomic
    // with close's pending-result check. This gate never covers filesystem or
    // PTY I/O, so close remains prompt when an external operation is blocked.
    zmodem_event_publication_gate: Mutex<()>,
    // Bridges manager mutation to event publication. Close checks this under
    // the publication gate, while transition acquisition uses the same gate
    // to make close-start and new protocol work mutually exclusive.
    zmodem_state_transitions_inflight: AtomicUsize,
    zmodem_state_transitions_closed: AtomicBool,
    // Serializes committing scanner passthrough to the recording/VT stream.
    // The reader and timeout pump can both release held scanner bytes, so the
    // route call and its subsequent VT commit must be one ordered operation.
    zmodem_passthrough_gate: Mutex<()>,
    zmodem_transport_gate: Mutex<()>,
    zmodem_wire_tx: Mutex<Option<mpsc::Sender<QueuedZmodemWireJob>>>,
    zmodem_wire_queued_bytes: AtomicUsize,
    pty_writer_available: AtomicBool,
    zmodem_wire_inflight: Mutex<Option<ZmodemInFlight>>,
    zmodem_inflight: Mutex<Option<ZmodemInFlight>>,
    zmodem_active_transfer_id: AtomicU64,
    zmodem_active_direction: AtomicU8,
    zmodem_draining: AtomicBool,
    zmodem_terminal_event_ids: Mutex<VecDeque<u64>>,
    zmodem_operation_epoch: Arc<AtomicU64>,
    zmodem_receive_commit_phase: Arc<AtomicU8>,
    zmodem_receive_publish_started_at: Arc<Mutex<Option<Instant>>>,
    deferred_pty_writes: Mutex<DeferredPtyWrites>,
    zmodem_transport_terminated: AtomicBool,
    pty_reader_closed: AtomicBool,
    // Unix readers own a duplicated poll descriptor and can prove that bytes
    // preceding child exit were drained. Platforms without that primitive
    // retain immediate exit publication to avoid a ConPTY close/EOF cycle.
    pty_reader_exit_barrier_enabled: AtomicBool,
    master: Mutex<Option<Box<dyn portable_pty::MasterPty + Send>>>,
    child: Mutex<Option<Box<dyn portable_pty::Child + Send + Sync>>>,
    child_killer: Mutex<Option<Box<dyn portable_pty::ChildKiller + Send + Sync>>>,
    child_pid: Option<u32>,
    pending_child_exit: Mutex<Option<PendingChildExit>>,
    process_name: String,
    is_replay: bool,
    events: Mutex<PendingEventQueue>,
    recording: Mutex<SessionRecording>,
    replay_checkpoints: Mutex<ReplayCheckpointStore>,
    diagnostic_events: Mutex<VecDeque<TerminalDiagnosticEvent>>,
    diagnostic_wire_sequence: Mutex<u64>,
    frame_packet_sequence: Mutex<u64>,
    resource_samples: Mutex<VecDeque<ResourceSample>>,
    resource_sampler_state: Mutex<ResourceSamplerState>,
    pending_frame_signal: PendingFrameSignal,
    session_debug_stats: Mutex<SessionDebugStats>,
    last_rows: Mutex<Vec<CachedRowState>>,
    last_frame_meta: Mutex<Option<CachedFrameMeta>>,
    last_frame_debug_stats: Mutex<Option<FrameDebugStats>>,
    last_frame_had_graphics: Mutex<bool>,
    deferred_clear_graphics_frame: Mutex<Option<DeferredFrameGrace>>,
    deferred_kitty_delete_graphics_frame: Mutex<Option<DeferredFrameGrace>>,
    deferred_inline_clear_frame: Mutex<Option<DeferredFrameGrace>>,
    worker_handles: Mutex<SessionWorkerHandles>,
    exited: AtomicBool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct ZmodemInFlight {
    transfer_id: u64,
    direction: ZmodemDirection,
    started_at: Instant,
}

struct ZmodemWireJob {
    bytes: Vec<u8>,
    owner: Option<(u64, ZmodemDirection)>,
    kind: ZmodemWireJobKind,
    completion: Option<mpsc::SyncSender<Result<(), ZmodemWireError>>>,
}

struct QueuedZmodemWireJob {
    job: ZmodemWireJob,
    generation: u64,
    reserved_bytes: usize,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ZmodemWireJobKind {
    Protocol,
    Cancel,
    Ordinary,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CancelActiveZmodemOutcome {
    Cancelled,
    Draining,
    Idle,
}

impl CancelActiveZmodemOutcome {
    fn as_str(self) -> &'static str {
        match self {
            Self::Cancelled => "cancelled",
            Self::Draining => "draining",
            Self::Idle => "idle",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ZmodemWireError {
    Cancelled,
    Io,
    QueueLimit,
}

struct ZmodemInFlightGuard<'a> {
    slot: &'a Mutex<Option<ZmodemInFlight>>,
    marker: Option<ZmodemInFlight>,
}

struct ZmodemStateTransitionGuard<'a> {
    counter: &'a AtomicUsize,
}

struct OwnedZmodemStateTransitionGuard {
    session: Arc<TerminalSession>,
}

impl Drop for ZmodemStateTransitionGuard<'_> {
    fn drop(&mut self) {
        let previous = self.counter.fetch_sub(1, Ordering::AcqRel);
        debug_assert!(previous > 0, "ZMODEM transition count underflow");
    }
}

impl Drop for OwnedZmodemStateTransitionGuard {
    fn drop(&mut self) {
        let previous = self
            .session
            .zmodem_state_transitions_inflight
            .fetch_sub(1, Ordering::AcqRel);
        debug_assert!(previous > 0, "ZMODEM transition count underflow");
    }
}

impl<'a> ZmodemInFlightGuard<'a> {
    fn new(
        slot: &'a Mutex<Option<ZmodemInFlight>>,
        active: Option<(u64, ZmodemDirection)>,
    ) -> Self {
        let marker = active.map(|(transfer_id, direction)| ZmodemInFlight {
            transfer_id,
            direction,
            started_at: Instant::now(),
        });
        *slot.lock() = marker;
        Self { slot, marker }
    }
}

impl Drop for ZmodemInFlightGuard<'_> {
    fn drop(&mut self) {
        let mut slot = self.slot.lock();
        if *slot == self.marker {
            *slot = None;
        }
    }
}

#[derive(Default)]
struct DeferredPtyWrites {
    chunks: VecDeque<(Vec<u8>, bool)>,
    bytes: usize,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct DeferredPtyWriteFailure {
    queued_chunks: usize,
    queued_bytes: usize,
    completed_chunks: usize,
    completed_bytes: usize,
}

impl DeferredPtyWriteFailure {
    fn payload(self) -> serde_json::Value {
        serde_json::json!({
            "source": "zmodem",
            "reason": "io_error",
            "queuedChunks": self.queued_chunks,
            "queuedBytes": self.queued_bytes,
            "completedChunks": self.completed_chunks,
            "completedBytes": self.completed_bytes,
            "unconfirmedChunks": self.queued_chunks.saturating_sub(self.completed_chunks),
            "unconfirmedBytes": self.queued_bytes.saturating_sub(self.completed_bytes),
        })
    }
}

impl DeferredPtyWrites {
    fn push(&mut self, bytes: &[u8], record_as_user_input: bool) -> Result<(), SessionError> {
        if self.chunks.len() >= MAX_DEFERRED_PTY_WRITE_CHUNKS
            || self.bytes.saturating_add(bytes.len()) > MAX_DEFERRED_PTY_WRITE_BYTES
        {
            return Err(SessionError::Zmodem(
                "deferred_pty_write_overflow".to_string(),
            ));
        }
        self.bytes = self.bytes.saturating_add(bytes.len());
        self.chunks
            .push_back((bytes.to_vec(), record_as_user_input));
        Ok(())
    }

    fn take(&mut self) -> VecDeque<(Vec<u8>, bool)> {
        self.bytes = 0;
        std::mem::take(&mut self.chunks)
    }
}

#[derive(Clone, Copy, Debug)]
struct TerminalGraphicsMemoryLimits {
    max_image_bytes: usize,
    max_total_bytes: usize,
}

#[derive(Default)]
struct SessionWorkerHandles {
    zmodem_writer: Option<thread::JoinHandle<()>>,
    reader: Option<thread::JoinHandle<()>>,
    resource_sampler: Option<thread::JoinHandle<()>>,
}

impl TerminalSession {
    pub fn spawn(session_id: u64, profile: TerminalProfile) -> Result<Arc<Self>, SessionError> {
        Self::spawn_with_zmodem(session_id, profile, false)
    }

    fn spawn_with_zmodem(
        session_id: u64,
        profile: TerminalProfile,
        zmodem_enabled: bool,
    ) -> Result<Arc<Self>, SessionError> {
        let osc633_expected_nonce = Self::validate_osc633_nonce(&profile)?;
        let runtime = spawn_terminal_transport(&profile, DEFAULT_ROWS, DEFAULT_COLS)
            .map_err(|error: anyhow::Error| SessionError::Pty(error.to_string()))?;
        let child_pid = runtime.child_pid;
        let process_name = process_name_for_profile(&profile);
        let reader = runtime.reader;
        let reader_poll_handle = runtime.reader_poll_handle;
        let shell_integration_diagnostics = runtime.shell_integration.to_diagnostic_json();
        let shell_integration_proxy = runtime.shell_integration_proxy;
        let ssh_auth = runtime.ssh_auth;
        let session = Self::new_with_ssh_auth(
            session_id,
            profile,
            osc633_expected_nonce,
            Some(runtime.writer),
            Some(runtime.master),
            Some(runtime.child),
            child_pid,
            ssh_auth,
            process_name,
            shell_integration_diagnostics,
            false,
        );
        session
            .zmodem_enabled
            .store(zmodem_enabled, Ordering::Release);
        session
            .pty_reader_exit_barrier_enabled
            .store(reader_poll_handle.is_some(), Ordering::Release);

        let zmodem_writer_handle = Self::start_zmodem_writer_or_teardown(&session)?;
        let reader_session = Arc::clone(&session);
        let reader_handle = thread::spawn(move || {
            let _shell_integration_proxy = shell_integration_proxy;
            let mut reader = reader;
            let mut buf = [0_u8; 4096];
            let trusted_eof = loop {
                match wait_for_pty_readable(reader_poll_handle.as_ref()) {
                    Ok(false) => {
                        if reader_session.exited.load(Ordering::Acquire)
                            && !wait_for_pty_readable(reader_poll_handle.as_ref()).unwrap_or(true)
                        {
                            // The second timeout starts after observing child
                            // exit. Since this is the only reader, the kernel
                            // queue is now drained through that exit boundary.
                            // Stop even if a detached descendant still holds
                            // the slave open; later descendant output is
                            // semantically after the terminal child exited.
                            break true;
                        }
                        continue;
                    }
                    Ok(true) => {}
                    Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(_) => break false,
                }
                match reader.read(&mut buf) {
                    Ok(0) => break true,
                    Ok(read) => {
                        let _passthrough = reader_session.zmodem_passthrough_gate.lock();
                        let passthrough = reader_session.route_pty_output(&buf[..read]);
                        if !passthrough.is_empty() {
                            reader_session
                                .recording
                                .lock()
                                .record_pty_output(&passthrough);
                            reader_session.ingest_pty_output(&passthrough, true);
                        }
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(error) if pty_read_error_is_trusted_eof(&error) => break true,
                    Err(_) => break false,
                }
            };
            reader_session.on_pty_reader_closed(trusted_eof);
        });
        let resource_sampler_handle = Self::start_resource_sampler(&session);
        {
            let mut worker_handles = session.worker_handles.lock();
            worker_handles.zmodem_writer = Some(zmodem_writer_handle);
            worker_handles.reader = Some(reader_handle);
            worker_handles.resource_sampler = Some(resource_sampler_handle);
        }

        Ok(session)
    }

    pub fn spawn_replay(
        session_id: u64,
        profile: TerminalProfile,
    ) -> Result<Arc<Self>, SessionError> {
        let osc633_expected_nonce = Self::validate_osc633_nonce(&profile)?;
        let process_name = process_name_for_profile(&profile);
        Ok(Self::new_with_ssh_auth(
            session_id,
            profile,
            osc633_expected_nonce,
            None,
            None,
            None,
            None,
            None,
            process_name,
            serde_json::json!({
                "mode": "replay",
                "child_spawned": false,
            }),
            true,
        ))
    }

    fn validate_osc633_nonce(profile: &TerminalProfile) -> Result<Option<String>, SessionError> {
        match profile.launch.env.get("VSCODE_NONCE") {
            Some(nonce) if Terminal::is_valid_osc633_nonce(nonce) => Ok(Some(nonce.clone())),
            Some(_) => Err(SessionError::InvalidProfile(
                "VSCODE_NONCE must be 1-256 UTF-8 bytes without controls or semicolons".to_string(),
            )),
            None => Ok(None),
        }
    }

    #[cfg(test)]
    #[allow(clippy::too_many_arguments)]
    fn new(
        session_id: u64,
        profile: TerminalProfile,
        osc633_expected_nonce: Option<String>,
        writer: Option<Box<dyn Write + Send>>,
        master: Option<Box<dyn portable_pty::MasterPty + Send>>,
        child: Option<Box<dyn portable_pty::Child + Send + Sync>>,
        child_pid: Option<u32>,
        process_name: String,
        shell_integration_diagnostics: serde_json::Value,
        is_replay: bool,
    ) -> Arc<Self> {
        Self::new_with_ssh_auth(
            session_id,
            profile,
            osc633_expected_nonce,
            writer,
            master,
            child,
            child_pid,
            None,
            process_name,
            shell_integration_diagnostics,
            is_replay,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn new_with_ssh_auth(
        session_id: u64,
        profile: TerminalProfile,
        osc633_expected_nonce: Option<String>,
        writer: Option<Box<dyn Write + Send>>,
        master: Option<Box<dyn portable_pty::MasterPty + Send>>,
        child: Option<Box<dyn portable_pty::Child + Send + Sync>>,
        child_pid: Option<u32>,
        ssh_auth: Option<crate::ssh::SshAuthClient>,
        process_name: String,
        shell_integration_diagnostics: serde_json::Value,
        is_replay: bool,
    ) -> Arc<Self> {
        let child_killer = child.as_ref().map(|child| child.clone_killer());
        let pty_writer_available = writer.is_some();
        let emulation = profile.terminal.emulation;
        let scrollback_lines = normalize_scrollback_lines(profile.terminal.scrollback_lines);
        let graphics_enabled =
            emulation == TerminalEmulation::Xterm256 && profile.terminal.graphics.enabled;
        let drag_drop_enabled =
            emulation == TerminalEmulation::Xterm256 && profile.terminal.drag_drop_enabled;
        let graphics_memory_limits = graphics_enabled.then_some(TerminalGraphicsMemoryLimits {
            max_image_bytes: profile.terminal.graphics.max_image_bytes,
            max_total_bytes: profile.terminal.graphics.max_total_bytes,
        });
        let profile_colors = profile.appearance.colors.clone();
        let profile_font = profile.appearance.font.clone();
        let mut terminal = Terminal::with_scrollback(
            DEFAULT_COLS as usize,
            DEFAULT_ROWS as usize,
            scrollback_lines,
        );
        configure_session_terminal(
            &mut terminal,
            emulation,
            graphics_memory_limits,
            &profile_colors,
            &profile_font,
            osc633_expected_nonce.as_deref(),
            drag_drop_enabled,
        );
        let zmodem_operation_epoch = Arc::new(AtomicU64::new(0));
        let zmodem_receive_commit_phase = Arc::new(AtomicU8::new(0));
        let zmodem_receive_publish_started_at = Arc::new(Mutex::new(None));

        Arc::new(Self {
            session_id,
            emulation,
            scrollback_lines,
            graphics_enabled,
            drag_drop_enabled,
            graphics_memory_limits,
            profile_colors,
            profile_font,
            osc633_expected_nonce,
            state: Mutex::new(TerminalState {
                terminal,
                transcript: Vec::new(),
                transcript_truncated: false,
                scrollback_offset: 0,
                host_protocol: HostProtocolState::default(),
                graphic_assets: VecDeque::new(),
                graphic_asset_bytes: 0,
                graphic_asset_cache_max_bytes: profile.terminal.graphics.max_total_bytes,
                pending_file_downloads: VecDeque::new(),
                pending_file_download_bytes: 0,
                next_file_download_id: 1,
                replay_checkpoint_boundary: ReplayCheckpointBoundary::default(),
            }),
            writer: Mutex::new(writer),
            ssh_auth,
            // Direct unit construction exercises the protocol implementation;
            // production spawn paths overwrite this before starting workers.
            zmodem_enabled: AtomicBool::new(true),
            zmodem: Mutex::new(ZmodemManager::for_session(
                session_id,
                Arc::clone(&zmodem_operation_epoch),
                Arc::clone(&zmodem_receive_commit_phase),
                Arc::clone(&zmodem_receive_publish_started_at),
            )),
            zmodem_sequence_gate: Mutex::new(()),
            zmodem_event_publication_gate: Mutex::new(()),
            zmodem_state_transitions_inflight: AtomicUsize::new(0),
            zmodem_state_transitions_closed: AtomicBool::new(false),
            zmodem_passthrough_gate: Mutex::new(()),
            zmodem_transport_gate: Mutex::new(()),
            zmodem_wire_tx: Mutex::new(None),
            zmodem_wire_queued_bytes: AtomicUsize::new(0),
            pty_writer_available: AtomicBool::new(pty_writer_available),
            zmodem_wire_inflight: Mutex::new(None),
            zmodem_inflight: Mutex::new(None),
            zmodem_active_transfer_id: AtomicU64::new(0),
            zmodem_active_direction: AtomicU8::new(0),
            zmodem_draining: AtomicBool::new(false),
            zmodem_terminal_event_ids: Mutex::new(VecDeque::new()),
            zmodem_operation_epoch,
            zmodem_receive_commit_phase,
            zmodem_receive_publish_started_at,
            deferred_pty_writes: Mutex::new(DeferredPtyWrites::default()),
            zmodem_transport_terminated: AtomicBool::new(false),
            pty_reader_closed: AtomicBool::new(false),
            pty_reader_exit_barrier_enabled: AtomicBool::new(false),
            master: Mutex::new(master),
            child: Mutex::new(child),
            child_killer: Mutex::new(child_killer),
            child_pid,
            pending_child_exit: Mutex::new(None),
            process_name,
            is_replay,
            events: Mutex::new(PendingEventQueue::with_initial(TerminalEvent {
                kind: "started".to_string(),
                session_id,
                payload: None,
            })),
            recording: Mutex::new(SessionRecording::bounded()),
            replay_checkpoints: Mutex::new(ReplayCheckpointStore::default()),
            diagnostic_events: Mutex::new(VecDeque::from([TerminalDiagnosticEvent {
                timestamp_micros: unix_timestamp_micros(),
                session_id,
                kind: "started".to_string(),
                payload: Some(serde_json::json!({
                    "shell_integration": shell_integration_diagnostics,
                    "replay": is_replay,
                })),
            }])),
            diagnostic_wire_sequence: Mutex::new(0),
            frame_packet_sequence: Mutex::new(0),
            resource_samples: Mutex::new(VecDeque::new()),
            resource_sampler_state: Mutex::new(ResourceSamplerState::default()),
            pending_frame_signal: PendingFrameSignal::new(true),
            session_debug_stats: Mutex::new(SessionDebugStats::default()),
            last_rows: Mutex::new(Vec::new()),
            last_frame_meta: Mutex::new(None),
            last_frame_debug_stats: Mutex::new(None),
            last_frame_had_graphics: Mutex::new(false),
            deferred_clear_graphics_frame: Mutex::new(None),
            deferred_kitty_delete_graphics_frame: Mutex::new(None),
            deferred_inline_clear_frame: Mutex::new(None),
            worker_handles: Mutex::new(SessionWorkerHandles::default()),
            exited: AtomicBool::new(false),
        })
    }

    fn ingest_pty_output(&self, bytes: &[u8], allow_host_effects: bool) {
        let _ = self.ingest_pty_output_collecting_responses(bytes, allow_host_effects, false);
    }

    fn ingest_pty_output_collecting_responses(
        &self,
        bytes: &[u8],
        allow_host_effects: bool,
        collect_responses: bool,
    ) -> Vec<u8> {
        let (
            callback_events,
            responses,
            damage,
            cursor_before,
            cursor_after,
            cleared_scrollback,
            host_protocol_micros,
            terminal_process_micros,
            terminal_process_breakdown,
        ) = {
            let mut state = self.state.lock();
            state.replay_checkpoint_boundary.add(bytes);
            let cursor_before = terminal_cursor_snapshot(&state.terminal, state.terminal.cursor());
            let process_started_at = Instant::now();
            let was_alt_screen_active = state.terminal.is_alt_screen_active();
            let input_enters_alt_screen = input_sets_alt_screen(bytes);
            let mut callback_events = Vec::new();
            let mut host_protocol_micros = 0_u64;
            let TerminalState {
                terminal,
                host_protocol,
                ..
            } = &mut *state;
            terminal.process_with_filtered_input(bytes, |filtered| {
                let host_started_at = Instant::now();
                callback_events = host_protocol.observe(filtered, self.emulation);
                host_protocol_micros = host_started_at.elapsed().as_micros() as u64;
            });
            let parser_events = state.terminal.poll_events();
            let cleared_scrollback = parser_events.iter().any(|event| {
                matches!(
                    event,
                    ParserTerminalEvent::ScreenCleared {
                        include_scrollback: true
                    }
                )
            });
            let notifications = state.terminal.take_notifications();
            if self.emulation == TerminalEmulation::Xterm256 {
                let suppress_shell_zones = was_alt_screen_active
                    || input_enters_alt_screen
                    || state.terminal.is_alt_screen_active();
                callback_events.extend(callback_events_from_parser_events(
                    &mut state,
                    parser_events,
                    suppress_shell_zones,
                ));
                callback_events.extend(notifications.into_iter().map(|notification| {
                    CallbackEvent::SessionNotification {
                        source: notification.source.to_string(),
                        action: notification.action.as_str().to_string(),
                        identifier: notification
                            .identifier
                            .map(|identifier| sanitize_protocol_text(&identifier, 128)),
                        title: sanitize_protocol_text(&notification.title, 160),
                        message: sanitize_protocol_text(&notification.message, 512),
                        application_name: notification
                            .application_name
                            .map(|application_name| sanitize_protocol_text(&application_name, 160)),
                        notification_types: notification
                            .notification_types
                            .into_iter()
                            .take(8)
                            .map(|notification_type| sanitize_protocol_text(&notification_type, 64))
                            .collect(),
                        expires_after_ms: notification.expires_after_ms,
                        report_activation: notification.report_activation,
                        report_close: notification.report_close,
                        buttons: notification
                            .buttons
                            .into_iter()
                            .take(5)
                            .map(|button| sanitize_protocol_text(&button, 64))
                            .collect(),
                    }
                }));
            }
            if cleared_scrollback {
                // Terminal-originated CSI 3 J and iTerm2 OSC 1337
                // ClearScrollback invalidate replay and navigation history.
                state.scrollback_offset = 0;
                state.transcript.clear();
                state.transcript_truncated = true;
            }
            let terminal_process_micros = (process_started_at.elapsed().as_micros() as u64)
                .saturating_sub(host_protocol_micros);
            let terminal_process_breakdown = state.terminal.take_process_debug_stats();
            if !cleared_scrollback {
                append_transcript(&mut state, bytes);
            }
            let damage = state.terminal.drain_active_screen_damage();
            let cursor_after = terminal_cursor_snapshot(&state.terminal, state.terminal.cursor());
            let responses = normalize_responses(self.emulation, state.terminal.drain_responses());
            (
                callback_events,
                responses,
                damage,
                cursor_before,
                cursor_after,
                cleared_scrollback,
                host_protocol_micros,
                terminal_process_micros,
                terminal_process_breakdown,
            )
        };

        let damage_merge_started_at = Instant::now();
        self.pending_frame_signal.mutate_reader(|work| {
            work.merge_terminal_damage(damage, cursor_before, cursor_after);
        });
        let damage_merge_micros = damage_merge_started_at.elapsed().as_micros() as u64;

        if cleared_scrollback {
            self.last_rows.lock().clear();
            *self.last_frame_meta.lock() = None;
            self.pending_frame_signal
                .mutate(|work| work.mark_full_repaint("terminal_clear_scrollback"));
        }

        if allow_host_effects {
            for event in callback_events {
                self.push_callback_event(event);
            }
        }
        let response_write_started_at = Instant::now();
        if allow_host_effects && !collect_responses && !responses.is_empty() {
            let _ = self.write_non_zmodem_or_defer(&responses, false);
        }
        let response_write_micros = response_write_started_at.elapsed().as_micros() as u64;
        self.record_input_debug_stats(
            bytes.len(),
            host_protocol_micros,
            terminal_process_micros,
            terminal_process_breakdown,
            damage_merge_micros,
            response_write_micros,
        );
        if allow_host_effects && collect_responses {
            responses
        } else {
            Vec::new()
        }
    }

    fn route_pty_output(&self, bytes: &[u8]) -> Vec<u8> {
        if !cfg!(any(target_os = "macos", target_os = "linux")) {
            return bytes.to_vec();
        }
        if self.zmodem_transport_terminated.load(Ordering::SeqCst) {
            return Vec::new();
        }
        if !self.zmodem_enabled.load(Ordering::Acquire) {
            return bytes.to_vec();
        }
        // Reader passes and ordinary writes share this gate across protocol
        // wire confirmation and effect publication. Cancellation deliberately
        // does not: it can still invalidate an operation while its PTY write
        // is outside the transport gate.
        let _sequence = self.zmodem_sequence_gate.lock();
        if self.zmodem_transport_terminated.load(Ordering::Acquire) {
            return Vec::new();
        }
        // This gate preserves PTY byte ordering across the reader, timeout
        // pump, and UI commands. Unlike the protocol-state lock it is never
        // awaited by cancellation or close; those paths fail the transport
        // directly if an underlying syscall has stalled while holding it.
        let _transport = self.zmodem_transport_gate.lock();
        let Some(_transition) = self.begin_zmodem_state_transition() else {
            return Vec::new();
        };
        let operation_epoch = self.zmodem_operation_epoch.load(Ordering::Acquire);
        let mut wire = Vec::new();
        let (mut effects, owner, confirm_closing_zfin) = {
            let mut zmodem = self.zmodem.lock();
            let active_before = zmodem.active_transfer();
            let _inflight = ZmodemInFlightGuard::new(&self.zmodem_inflight, active_before);
            let effects = match zmodem.ingest(bytes, &mut wire) {
                Ok(effects) => effects,
                Err(error) => {
                    let passthrough = zmodem.take_failure_passthrough();
                    let mut failure = zmodem.fail(&error, Some(&mut wire));
                    failure.passthrough = passthrough;
                    failure
                }
            };
            let active_after = zmodem.active_transfer();
            let confirm_closing_zfin = zmodem.receiver_waiting_final_oo();
            self.remember_zmodem_state(&zmodem);
            (
                effects,
                active_before.or(active_after),
                confirm_closing_zfin,
            )
        };
        if effects
            .events
            .iter()
            .any(|event| event.kind == "zmodem_detected")
            && !effects.passthrough.is_empty()
        {
            // Plain terminal bytes preceding the initial ZMODEM header belong
            // to the VT stream. Process them now, while their generated replies
            // can still be prepended to the first protocol write. Returning the
            // prefix to the reader would defer replies behind the newly-active
            // transfer and invert observable PTY byte order.
            let prefix = std::mem::take(&mut effects.passthrough);
            self.recording.lock().record_pty_output(&prefix);
            let responses = self.ingest_pty_output_collecting_responses(&prefix, true, true);
            if !responses.is_empty() {
                let mut ordered_wire = responses;
                ordered_wire.extend(wire);
                wire = ordered_wire;
            }
        }
        let continue_buffered_receive = self.publish_receive_file_completions(&mut effects);
        let confirm_terminal_wire = !wire.is_empty()
            && (confirm_closing_zfin
                || effects.events.iter().any(|event| {
                    matches!(
                        event.kind,
                        "zmodem_completed" | "zmodem_failed" | "zmodem_cancelled"
                    )
                }));
        let _wire_inflight = ZmodemInFlightGuard::new(&self.zmodem_inflight, owner);
        let wire_result = self.write_zmodem_wire_releasing_transport(
            &wire,
            _transport,
            owner,
            confirm_terminal_wire,
            ZmodemWireJobKind::Protocol,
        );
        if self.zmodem_operation_epoch.load(Ordering::Acquire) != operation_epoch {
            // Cancellation/forced termination won while this operation was
            // outside the ordering gate. Its protocol state and events are
            // stale, but the newer operation owns the manager state.
            effects = ZmodemEffects::default();
            if self.zmodem_transport_terminated.load(Ordering::Acquire) {
                let mut zmodem = self.zmodem.lock();
                zmodem.reset();
                self.remember_zmodem_state(&zmodem);
            }
        } else if wire_result.is_err() {
            effects = self.fail_zmodem_after_wire_error_preserving_commits(effects, owner);
        }
        let deferred_failure = self.flush_deferred_pty_writes_if_idle();
        let mut passthrough = self.apply_zmodem_effects(effects, deferred_failure);
        drop(_sequence);
        if continue_buffered_receive && !self.zmodem_transport_terminated.load(Ordering::Acquire) {
            passthrough.extend(self.route_pty_output(&[]));
        }
        passthrough
    }

    fn remember_zmodem_active(&self, active: Option<(u64, ZmodemDirection)>) {
        match active {
            Some((transfer_id, direction)) => {
                self.zmodem_active_direction.store(
                    match direction {
                        ZmodemDirection::Receive => 1,
                        ZmodemDirection::Send => 2,
                    },
                    Ordering::Release,
                );
                self.zmodem_active_transfer_id
                    .store(transfer_id, Ordering::Release);
            }
            None => {
                self.zmodem_active_transfer_id.store(0, Ordering::Release);
                self.zmodem_active_direction.store(0, Ordering::Release);
            }
        }
    }

    fn remember_zmodem_state(&self, zmodem: &ZmodemManager) {
        self.zmodem_draining
            .store(zmodem.is_draining(), Ordering::Release);
        self.remember_zmodem_active(zmodem.active_transfer());
    }

    fn begin_zmodem_state_transition(&self) -> Option<ZmodemStateTransitionGuard<'_>> {
        self.reserve_zmodem_state_transition()
            .then(|| ZmodemStateTransitionGuard {
                counter: &self.zmodem_state_transitions_inflight,
            })
    }

    fn begin_owned_zmodem_state_transition(
        session: &Arc<Self>,
    ) -> Option<OwnedZmodemStateTransitionGuard> {
        session
            .reserve_zmodem_state_transition()
            .then(|| OwnedZmodemStateTransitionGuard {
                session: Arc::clone(session),
            })
    }

    fn reserve_zmodem_state_transition(&self) -> bool {
        // Close uses the same short-lived gate to atomically observe zero
        // transitions and prohibit new ones. The guard itself never retains
        // the gate across filesystem or PTY I/O.
        let _publication = self.zmodem_event_publication_gate.lock();
        if self.zmodem_state_transitions_closed.load(Ordering::Acquire) {
            return false;
        }
        self.zmodem_state_transitions_inflight
            .fetch_add(1, Ordering::AcqRel);
        true
    }

    fn remember_zmodem_idle(&self) {
        self.zmodem_draining.store(false, Ordering::Release);
        self.remember_zmodem_active(None);
    }

    fn remembered_zmodem_active(&self) -> Option<(u64, ZmodemDirection)> {
        let transfer_id = self.zmodem_active_transfer_id.load(Ordering::Acquire);
        if transfer_id == 0 {
            return None;
        }
        let direction = match self.zmodem_active_direction.load(Ordering::Acquire) {
            1 => ZmodemDirection::Receive,
            2 => ZmodemDirection::Send,
            _ => return None,
        };
        Some((transfer_id, direction))
    }

    fn write_zmodem_wire_releasing_transport(
        &self,
        bytes: &[u8],
        transport: MutexGuard<'_, ()>,
        owner: Option<(u64, ZmodemDirection)>,
        confirm: bool,
        kind: ZmodemWireJobKind,
    ) -> Result<(), ZmodemWireError> {
        if bytes.is_empty() {
            drop(transport);
            return Ok(());
        }
        if self.zmodem_transport_terminated.load(Ordering::Acquire) {
            drop(transport);
            return Err(ZmodemWireError::Io);
        }
        if self.zmodem_wire_tx.lock().is_some() {
            let (completion, completion_rx) = if confirm {
                let (tx, rx) = mpsc::sync_channel(1);
                (Some(tx), Some(rx))
            } else {
                (None, None)
            };
            let result = self.enqueue_zmodem_wire_job(ZmodemWireJob {
                bytes: bytes.to_vec(),
                owner,
                kind,
                completion,
            });
            drop(transport);
            result?;
            return match completion_rx {
                Some(receiver) => self.await_zmodem_wire_completion(receiver, owner),
                None => Ok(()),
            };
        }
        let mut writer = self.writer.lock();
        // Preserve protocol-byte ordering by acquiring the PTY writer while
        // still owning the transport gate, then release the gate before the
        // potentially blocking syscall. The reader must remain able to
        // consume peer acknowledgements while a full-duplex SSH PTY applies
        // backpressure to a large outbound transfer.
        drop(transport);
        let Some(writer) = writer.as_deref_mut() else {
            return Err(ZmodemWireError::Io);
        };
        writer.write_all(bytes).map_err(|_| ZmodemWireError::Io)
    }

    fn await_zmodem_wire_completion(
        &self,
        receiver: mpsc::Receiver<Result<(), ZmodemWireError>>,
        owner: Option<(u64, ZmodemDirection)>,
    ) -> Result<(), ZmodemWireError> {
        let deadline = Instant::now() + ZMODEM_BLOCKED_IO_TIMEOUT;
        loop {
            match receiver.recv_timeout(ZMODEM_COMPLETION_POLL_INTERVAL) {
                Ok(result) => return result,
                Err(mpsc::RecvTimeoutError::Disconnected) => return Err(ZmodemWireError::Io),
                Err(mpsc::RecvTimeoutError::Timeout) => {}
            }
            if self.zmodem_transport_terminated.load(Ordering::Acquire) {
                return Err(ZmodemWireError::Io);
            }
            if Instant::now() >= deadline {
                // The owning protocol path converts this into one terminal
                // transfer failure. Ordinary/deferred callers have no such
                // owner, so fail the PTY transport closed here.
                if owner.is_none() {
                    self.terminate_zmodem_transport();
                }
                return Err(ZmodemWireError::Io);
            }
        }
    }

    fn enqueue_zmodem_wire_job(&self, job: ZmodemWireJob) -> Result<(), ZmodemWireError> {
        let len = job.bytes.len();
        // Protocol traffic remains strictly bounded. A user paste is one
        // already-materialized logical write, however, and rejecting it only
        // because it exceeds the actor's queue budget regresses the ordinary
        // PTY write contract. Let one oversized ordinary write reserve the
        // whole budget so it applies backpressure to every later job without
        // underflowing the queue accounting when it completes.
        let reserved_bytes = if len > ZMODEM_WIRE_MAX_QUEUED_BYTES {
            if job.kind != ZmodemWireJobKind::Ordinary {
                return Err(ZmodemWireError::QueueLimit);
            }
            ZMODEM_WIRE_MAX_QUEUED_BYTES
        } else {
            len
        };
        self.zmodem_wire_queued_bytes
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |queued| {
                queued
                    .checked_add(reserved_bytes)
                    .filter(|next| *next <= ZMODEM_WIRE_MAX_QUEUED_BYTES)
            })
            .map_err(|_| ZmodemWireError::QueueLimit)?;
        let sender = self.zmodem_wire_tx.lock().as_ref().cloned();
        let Some(sender) = sender else {
            self.zmodem_wire_queued_bytes
                .fetch_sub(reserved_bytes, Ordering::AcqRel);
            return Err(ZmodemWireError::Io);
        };
        let generation = self.zmodem_operation_epoch.load(Ordering::Acquire);
        if let Err(error) = sender.send(QueuedZmodemWireJob {
            job,
            generation,
            reserved_bytes,
        }) {
            self.zmodem_wire_queued_bytes
                .fetch_sub(error.0.reserved_bytes, Ordering::AcqRel);
            return Err(ZmodemWireError::Io);
        }
        Ok(())
    }

    fn write_zmodem_wire_direct(&self, bytes: &[u8]) -> Result<(), ZmodemWireError> {
        if bytes.is_empty() {
            return Ok(());
        }
        if self.zmodem_transport_terminated.load(Ordering::Acquire) {
            return Err(ZmodemWireError::Io);
        }
        let mut writer = self.writer.lock();
        let Some(pty) = writer.as_deref_mut() else {
            return Err(ZmodemWireError::Io);
        };
        let result = pty.write_all(bytes).map_err(|_| ZmodemWireError::Io);
        if result.is_err() {
            writer.take();
            self.pty_writer_available.store(false, Ordering::Release);
        }
        result
    }

    fn try_write_zmodem_wire_fallback(&self, bytes: &[u8]) -> Result<(), ZmodemWireError> {
        if bytes.is_empty() {
            return Ok(());
        }
        let Some(mut writer) = self.writer.try_lock() else {
            return Err(ZmodemWireError::Io);
        };
        let Some(writer) = writer.as_deref_mut() else {
            return Err(ZmodemWireError::Io);
        };
        writer.write_all(bytes).map_err(|_| ZmodemWireError::Io)
    }

    fn fail_zmodem_after_wire_error(&self) -> ZmodemEffects {
        let mut zmodem = self.zmodem.lock();
        let mut effects = if zmodem.active_transfer().is_some() {
            zmodem.fail(&ZmodemError::Io, None)
        } else if zmodem.is_active() {
            zmodem.transport_closed(false)
        } else {
            ZmodemEffects::default()
        };
        let closed = zmodem.transport_closed(false);
        effects.passthrough.extend(closed.passthrough);
        effects.events.extend(closed.events);
        effects.terminate_transport = true;
        self.remember_zmodem_state(&zmodem);
        effects
    }

    fn fail_zmodem_after_wire_error_for(
        &self,
        owner: Option<(u64, ZmodemDirection)>,
    ) -> ZmodemEffects {
        let effects = self.fail_zmodem_after_wire_error();
        if !effects.events.is_empty() || self.zmodem.lock().is_active() {
            return effects;
        }
        let Some((transfer_id, direction)) = owner else {
            return effects;
        };
        ZmodemEffects {
            passthrough: effects.passthrough,
            events: vec![crate::zmodem::ZmodemEvent {
                kind: "zmodem_failed",
                payload: serde_json::json!({
                    "source": "zmodem",
                    "transferId": transfer_id.to_string(),
                    "direction": match direction {
                        ZmodemDirection::Receive => "receive",
                        ZmodemDirection::Send => "send",
                    },
                    "reason": "io_error",
                }),
            }],
            terminate_transport: true,
            receive_publish_pending: effects.receive_publish_pending,
        }
    }

    fn fail_zmodem_after_wire_error_preserving_commits(
        &self,
        mut original: ZmodemEffects,
        owner: Option<(u64, ZmodemDirection)>,
    ) -> ZmodemEffects {
        let mut failure = self.fail_zmodem_after_wire_error_for(owner);
        if !original.receive_publish_pending {
            return failure;
        }
        // receive_publish_pending is raised at the first published file and
        // drive() deliberately stops at that boundary, so the original vector
        // contains only ordered non-terminal receive events. Preserve all of
        // them before appending the transport failure.
        original.events.extend(failure.events);
        failure.events = original.events;
        failure.receive_publish_pending = true;
        failure
    }

    fn force_zmodem_terminal(&self, transfer_id: u64, direction: ZmodemDirection, cancelled: bool) {
        let Some(_transition) = self.begin_zmodem_state_transition() else {
            return;
        };
        if !self.try_invalidate_receive_commit() {
            // A publication that has exceeded the hard I/O deadline runs in a
            // globally bounded worker. Detach its session ownership so the
            // manager can be reset and close can complete; the worker retains
            // its stable file/directory authority and any late failure still
            // enters the process-wide recovery registry.
            if !self.abandon_timed_out_receive_publication() {
                self.terminate_zmodem_transport();
                return;
            }
        }
        if self
            .zmodem_transport_terminated
            .swap(true, Ordering::AcqRel)
        {
            return;
        }
        let deferred_failure = {
            let mut deferred = self.deferred_pty_writes.lock();
            let queued_chunks = deferred.chunks.len();
            let queued_bytes = deferred.bytes;
            deferred.take();
            (queued_chunks != 0).then_some(DeferredPtyWriteFailure {
                queued_chunks,
                queued_bytes,
                completed_chunks: 0,
                completed_bytes: 0,
            })
        };
        if let Some(failure) = deferred_failure {
            self.push_event(ZMODEM_DEFERRED_WRITE_FAILED_KIND, Some(failure.payload()));
        }
        if cancelled {
            self.push_event(
                "zmodem_cancelled",
                Some(serde_json::json!({
                    "source": "zmodem",
                    "transferId": transfer_id.to_string(),
                })),
            );
        } else {
            self.push_event(
                "zmodem_failed",
                Some(serde_json::json!({
                    "source": "zmodem",
                    "transferId": transfer_id.to_string(),
                    "direction": match direction {
                        ZmodemDirection::Receive => "receive",
                        ZmodemDirection::Send => "send",
                    },
                    "reason": "timeout",
                })),
            );
        }
        if let Some(mut zmodem) = self.zmodem.try_lock() {
            zmodem.reset();
            self.remember_zmodem_state(&zmodem);
        } else {
            self.remember_zmodem_idle();
        }
        self.terminate_zmodem_transport();
    }

    fn apply_zmodem_effects(
        &self,
        effects: ZmodemEffects,
        deferred_failure: Option<DeferredPtyWriteFailure>,
    ) -> Vec<u8> {
        let _publication = self.zmodem_event_publication_gate.lock();
        let ZmodemEffects {
            passthrough,
            events,
            terminate_transport,
            receive_publish_pending,
        } = effects;
        let deferred_failure = deferred_failure.or_else(|| {
            terminate_transport.then(|| {
                let mut deferred = self.deferred_pty_writes.lock();
                let queued_chunks = deferred.chunks.len();
                let queued_bytes = deferred.bytes;
                deferred.take();
                (queued_chunks != 0).then_some(DeferredPtyWriteFailure {
                    queued_chunks,
                    queued_bytes,
                    completed_chunks: 0,
                    completed_bytes: 0,
                })
            })?
        });
        if let Some(failure) = deferred_failure {
            // This diagnostic must precede the transfer terminal event. A
            // completed/cancelled UI must never hide the fact that ordinary
            // PTY bytes queued behind the transfer were not delivered.
            self.push_event(ZMODEM_DEFERRED_WRITE_FAILED_KIND, Some(failure.payload()));
        }
        for event in events {
            self.push_event(event.kind, Some(event.payload));
        }
        if receive_publish_pending {
            // The file is already visible at its final no-replace path. Keep
            // cancellation behind that linearization point until its
            // completion event is durably ordered in the session queue.
            for pending in [RECEIVE_COMMIT_RESULT_READY, RECEIVE_COMMIT_PUBLISHING] {
                if self
                    .zmodem_receive_commit_phase
                    .compare_exchange(
                        pending,
                        RECEIVE_COMMIT_IDLE,
                        Ordering::AcqRel,
                        Ordering::Acquire,
                    )
                    .is_ok()
                {
                    *self.zmodem_receive_publish_started_at.lock() = None;
                    break;
                }
            }
        }
        if terminate_transport || deferred_failure.is_some() {
            if let Some(mut zmodem) = self.zmodem.try_lock() {
                zmodem.reset();
                self.remember_zmodem_state(&zmodem);
            }
            self.terminate_zmodem_transport();
        } else if !self.exited.load(Ordering::Acquire)
            && !self.zmodem_transport_terminated.load(Ordering::Acquire)
            && !self.zmodem.lock().is_active()
        {
            // A normal completion/cancel drain may reuse the same PTY for a
            // later transfer. Only that fully idle boundary can reopen the
            // commit phase; close marks exited before claiming cancellation.
            let _ = self.zmodem_receive_commit_phase.compare_exchange(
                RECEIVE_COMMIT_CANCELLED,
                RECEIVE_COMMIT_IDLE,
                Ordering::AcqRel,
                Ordering::Acquire,
            );
        }
        passthrough
    }

    fn publish_receive_file_completions(&self, effects: &mut ZmodemEffects) -> bool {
        if !effects.receive_publish_pending {
            return false;
        }
        if !effects
            .events
            .iter()
            .any(|event| event.kind == "zmodem_file_completed")
        {
            return false;
        }
        // Keep the original event vector intact. apply_zmodem_effects publishes
        // progress/file-completed events in protocol order and only then opens
        // the commit phase to cancellation.
        true
    }

    fn apply_zmodem_effects_and_ingest_passthrough(
        &self,
        effects: ZmodemEffects,
        deferred_failure: Option<DeferredPtyWriteFailure>,
    ) {
        let passthrough = self.apply_zmodem_effects(effects, deferred_failure);
        if !passthrough.is_empty() {
            self.recording.lock().record_pty_output(&passthrough);
            self.ingest_pty_output(&passthrough, true);
        }
    }

    fn abort_zmodem_command_error(
        zmodem: &mut ZmodemManager,
        error: &crate::zmodem::ZmodemError,
        writer: &mut dyn Write,
    ) -> Option<ZmodemEffects> {
        if !error.aborts_active_transfer() {
            return None;
        }
        let passthrough = zmodem.take_failure_passthrough();
        let mut failure = zmodem.fail(error, Some(writer));
        failure.passthrough = passthrough;
        Some(failure)
    }

    fn try_invalidate_receive_commit(&self) -> bool {
        loop {
            match self.zmodem_receive_commit_phase.load(Ordering::Acquire) {
                RECEIVE_COMMIT_PUBLISHING | RECEIVE_COMMIT_RESULT_READY => return false,
                RECEIVE_COMMIT_IDLE => {
                    if self
                        .zmodem_receive_commit_phase
                        .compare_exchange(
                            RECEIVE_COMMIT_IDLE,
                            RECEIVE_COMMIT_CANCELLED,
                            Ordering::AcqRel,
                            Ordering::Acquire,
                        )
                        .is_err()
                    {
                        continue;
                    }
                    self.zmodem_operation_epoch.fetch_add(1, Ordering::AcqRel);
                    *self.zmodem_receive_publish_started_at.lock() = None;
                    return true;
                }
                RECEIVE_COMMIT_CANCELLED => {
                    // Another invalidator may be paused between claiming the
                    // phase and advancing the epoch. Advancing it again is
                    // harmless and guarantees stale worker jobs are rejected.
                    self.zmodem_operation_epoch.fetch_add(1, Ordering::AcqRel);
                    *self.zmodem_receive_publish_started_at.lock() = None;
                    return true;
                }
                _ => return false,
            }
        }
    }

    fn abandon_timed_out_receive_publication(&self) -> bool {
        let timed_out = self
            .zmodem_receive_publish_started_at
            .lock()
            .is_some_and(|started_at| started_at.elapsed() >= ZMODEM_BLOCKED_IO_TIMEOUT);
        if !timed_out {
            return false;
        }
        if self
            .zmodem_receive_commit_phase
            .compare_exchange(
                RECEIVE_COMMIT_PUBLISHING,
                RECEIVE_COMMIT_CANCELLED,
                Ordering::AcqRel,
                Ordering::Acquire,
            )
            .is_err()
        {
            return false;
        }
        self.zmodem_operation_epoch.fetch_add(1, Ordering::AcqRel);
        *self.zmodem_receive_publish_started_at.lock() = None;
        true
    }

    fn terminate_zmodem_transport(&self) {
        // A continuously noisy peer must not refresh the quarantine forever.
        // Never wait for a writer or protocol lock here: this path is also the
        // escape hatch for a PTY/filesystem syscall that is itself stalled.
        if !self.try_invalidate_receive_commit()
            && self.zmodem_receive_commit_phase.load(Ordering::Acquire) != RECEIVE_COMMIT_CANCELLED
        {
            // Publication owns the terminalization boundary. In particular,
            // a worker may have changed PUBLISHING to RESULT_READY after a
            // watchdog's initial observation. Do not terminate transport and
            // strand that authoritative result; a timed-out worker must first
            // win the atomic PUBLISHING -> CANCELLED abandonment CAS.
            return;
        }
        self.zmodem_transport_terminated
            .store(true, Ordering::SeqCst);
        self.zmodem_wire_tx.lock().take();
        self.pty_writer_available.store(false, Ordering::Release);
        let deferred_failure = {
            let mut deferred = self.deferred_pty_writes.lock();
            let queued_chunks = deferred.chunks.len();
            let queued_bytes = deferred.bytes;
            deferred.take();
            (queued_chunks != 0).then_some(DeferredPtyWriteFailure {
                queued_chunks,
                queued_bytes,
                completed_chunks: 0,
                completed_bytes: 0,
            })
        };
        if let Some(failure) = deferred_failure {
            self.push_event(ZMODEM_DEFERRED_WRITE_FAILED_KIND, Some(failure.payload()));
        }
        if let Some(mut writer) = self.writer.try_lock() {
            writer.take();
        }
        if let Some(mut master) = self.master.try_lock() {
            master.take();
        }
        if let Some(mut child_killer) = self.child_killer.try_lock()
            && let Some(child_killer) = child_killer.as_mut()
        {
            let _ = child_killer.kill();
        }
        if let Some(mut child) = self.child.try_lock()
            && let Some(child) = child.as_mut()
        {
            let _ = child.kill();
        }
    }

    fn on_pty_reader_closed(&self, trusted_eof: bool) {
        self.finalize_pty_reader_close(trusted_eof);
        // Publish only after every ZMODEM transition guard in the finalizer
        // has dropped. Otherwise the exit-order check would observe the
        // finalizer itself and strand the exit when Dart polling is disabled.
        self.pty_reader_closed.store(true, Ordering::Release);
        self.publish_pending_child_exit_if_ready();
    }

    fn finalize_pty_reader_close(&self, trusted_eof: bool) {
        if !self.zmodem_enabled.load(Ordering::Acquire) {
            crate::zmodem::tombstone_recovery_session(self.session_id);
            return;
        }
        let Some(_transition) = self.begin_zmodem_state_transition() else {
            return;
        };
        if self.zmodem_transport_terminated.load(Ordering::Acquire) {
            let mut zmodem = self.zmodem.lock();
            zmodem.reset();
            self.remember_zmodem_state(&zmodem);
            crate::zmodem::tombstone_recovery_session(self.session_id);
            return;
        }
        let _passthrough = self.zmodem_passthrough_gate.lock();
        let sequence = self.zmodem_sequence_gate.lock();
        if self.zmodem_transport_terminated.load(Ordering::Acquire) {
            let mut zmodem = self.zmodem.lock();
            zmodem.reset();
            self.remember_zmodem_state(&zmodem);
            crate::zmodem::tombstone_recovery_session(self.session_id);
            return;
        }
        let _transport = self.zmodem_transport_gate.lock();
        let effects = {
            let mut zmodem = self.zmodem.lock();
            let active = zmodem.active_transfer();
            let _inflight = ZmodemInFlightGuard::new(&self.zmodem_inflight, active);
            let effects = zmodem.transport_closed(trusted_eof);
            self.remember_zmodem_state(&zmodem);
            effects
        };
        drop(_transport);
        let deferred_failure = self.flush_deferred_pty_writes_if_idle();
        let passthrough = self.apply_zmodem_effects(effects, deferred_failure);
        drop(sequence);
        if !passthrough.is_empty() {
            self.recording.lock().record_pty_output(&passthrough);
            self.ingest_pty_output(&passthrough, true);
        }
        crate::zmodem::tombstone_recovery_session(self.session_id);
    }

    fn write_non_zmodem_or_defer(
        &self,
        bytes: &[u8],
        record_as_user_input: bool,
    ) -> Result<(), SessionError> {
        self.write_non_zmodem_ordered(bytes, record_as_user_input, true)
    }

    fn write_non_zmodem_ordered(
        &self,
        bytes: &[u8],
        record_as_user_input: bool,
        defer_if_active: bool,
    ) -> Result<(), SessionError> {
        // A blocked receive filesystem operation can own the sequence gate
        // until its worker is abandoned. Once the watchdog has terminated the
        // transport, public input must fail promptly instead of pinning the
        // caller's isolate behind that stale owner. The post-acquisition check
        // closes the race between the first flag read and claiming the gate.
        let sequence = loop {
            if self.zmodem_transport_terminated.load(Ordering::Acquire) {
                return Err(SessionError::Io("PTY transport closed".to_string()));
            }
            if let Some(sequence) = self.zmodem_sequence_gate.try_lock() {
                if self.zmodem_transport_terminated.load(Ordering::Acquire) {
                    return Err(SessionError::Io("PTY transport closed".to_string()));
                }
                break sequence;
            }
            thread::park_timeout(ZMODEM_COMPLETION_POLL_INTERVAL);
        };
        let transport = self.zmodem_transport_gate.lock();
        if self.zmodem.lock().is_active() {
            if !defer_if_active {
                return Err(SessionError::Zmodem("transfer_active".to_string()));
            }
            return self
                .deferred_pty_writes
                .lock()
                .push(bytes, record_as_user_input);
        }
        if !self.pty_writer_available.load(Ordering::Acquire) {
            return Err(SessionError::ReadOnlyReplaySession(self.session_id));
        }
        let result = if self.zmodem_wire_tx.lock().is_some() {
            let (completion_tx, completion_rx) = mpsc::sync_channel(1);
            let queued = self.enqueue_zmodem_wire_job(ZmodemWireJob {
                bytes: bytes.to_vec(),
                owner: None,
                kind: ZmodemWireJobKind::Ordinary,
                completion: Some(completion_tx),
            });
            // Enqueue while both ordering gates are held, then release them
            // before waiting for the actor. The PTY reader may need to drain
            // remote output before that ordinary write can make progress.
            drop(transport);
            drop(sequence);
            queued.and_then(|()| self.await_zmodem_wire_completion(completion_rx, None))
        } else {
            // Preserve direct-writer ordering by claiming the writer before
            // releasing the gates, but never retain either gate across the
            // potentially blocking syscall.
            let mut writer = self.writer.lock();
            drop(transport);
            drop(sequence);
            let result = writer
                .as_deref_mut()
                .ok_or(ZmodemWireError::Io)
                .and_then(|pty| pty.write_all(bytes).map_err(|_| ZmodemWireError::Io));
            if result.is_err() {
                writer.take();
                self.pty_writer_available.store(false, Ordering::Release);
            }
            result
        };
        result.map_err(|_| SessionError::Io("PTY write failed".to_string()))?;
        if record_as_user_input {
            self.recording.lock().record_user_input(bytes);
        }
        Ok(())
    }

    fn flush_deferred_pty_writes_if_idle(&self) -> Option<DeferredPtyWriteFailure> {
        let _transport = self.zmodem_transport_gate.lock();
        if self.zmodem.lock().is_active() {
            return None;
        }
        let mut deferred = self.deferred_pty_writes.lock();
        let queued_chunks = deferred.chunks.len();
        let queued_bytes = deferred.bytes;
        let mut chunks = deferred.take();
        // Never retain the deferred-input mutex while waiting for the writer
        // actor. On timeout or BrokenPipe, both the waiter and actor terminate
        // the transport, which must be able to reacquire this mutex.
        drop(deferred);
        if chunks.is_empty() {
            return None;
        }
        let combined = chunks
            .iter()
            .flat_map(|(bytes, _)| bytes.iter().copied())
            .collect::<Vec<_>>();
        let result = if self.zmodem_wire_tx.lock().is_some() {
            let (completion_tx, completion_rx) = mpsc::sync_channel(1);
            let queued = self.enqueue_zmodem_wire_job(ZmodemWireJob {
                bytes: combined,
                owner: None,
                kind: ZmodemWireJobKind::Ordinary,
                completion: Some(completion_tx),
            });
            drop(_transport);
            queued.and_then(|()| self.await_zmodem_wire_completion(completion_rx, None))
        } else {
            drop(_transport);
            self.write_zmodem_wire_direct(&combined)
        };
        if result.is_err() {
            // A batched write may already have emitted a prefix. Retrying any
            // chunk could duplicate bytes, so report the whole batch as
            // unconfirmed and fail the transport closed.
            return Some(DeferredPtyWriteFailure {
                queued_chunks,
                queued_bytes,
                completed_chunks: 0,
                completed_bytes: 0,
            });
        }
        while let Some((bytes, record_as_user_input)) = chunks.pop_front() {
            if record_as_user_input {
                self.recording.lock().record_user_input(&bytes);
            }
        }
        None
    }

    fn poll_zmodem_timeout(&self) {
        if !self.zmodem_enabled.load(Ordering::Acquire) {
            return;
        }
        // RESULT_READY is the worker's linearization point: once reached, the
        // manager must publish that authoritative result and a watchdog may no
        // longer turn it into cancellation merely because event delivery was
        // delayed. Only an executing PUBLISHING job can time out.
        let publication_timed_out = self.zmodem_receive_commit_phase.load(Ordering::Acquire)
            == RECEIVE_COMMIT_PUBLISHING
            && self
                .zmodem_receive_publish_started_at
                .lock()
                .is_some_and(|started_at| started_at.elapsed() >= ZMODEM_BLOCKED_IO_TIMEOUT);
        if publication_timed_out
            && let Some((transfer_id, direction)) = self.remembered_zmodem_active()
        {
            self.force_zmodem_terminal(transfer_id, direction, false);
            return;
        }
        if let Some(inflight) = *self.zmodem_wire_inflight.lock()
            && inflight.started_at.elapsed() >= ZMODEM_BLOCKED_IO_TIMEOUT
        {
            self.force_zmodem_terminal(inflight.transfer_id, inflight.direction, false);
            return;
        }
        if let Some(inflight) = *self.zmodem_inflight.lock()
            && inflight.started_at.elapsed() >= ZMODEM_BLOCKED_IO_TIMEOUT
        {
            // Check before the sequence gate: the blocked filesystem/protocol
            // operation whose deadline expired may itself own that gate.
            self.force_zmodem_terminal(inflight.transfer_id, inflight.direction, false);
            return;
        }
        // Match the reader's route -> recording/VT commit critical section so
        // a timeout cannot commit a held suffix ahead of earlier passthrough.
        let _passthrough = self.zmodem_passthrough_gate.lock();
        let Some(sequence) = self.zmodem_sequence_gate.try_lock() else {
            return;
        };
        if self.zmodem_transport_terminated.load(Ordering::Acquire) {
            return;
        }
        let Some(_transport) = self.zmodem_transport_gate.try_lock() else {
            if let Some(inflight) = *self.zmodem_inflight.lock()
                && inflight.started_at.elapsed() >= ZMODEM_BLOCKED_IO_TIMEOUT
            {
                self.force_zmodem_terminal(inflight.transfer_id, inflight.direction, false);
            }
            return;
        };
        let Some(_transition) = self.begin_zmodem_state_transition() else {
            return;
        };
        let operation_epoch = self.zmodem_operation_epoch.load(Ordering::Acquire);
        let transport_available = self.pty_writer_available.load(Ordering::Acquire);
        let mut wire = Vec::new();
        let (outcome, owner, confirm_closing_zfin) = {
            let mut zmodem = self.zmodem.lock();
            let active = zmodem.active_transfer();
            let _inflight = ZmodemInFlightGuard::new(&self.zmodem_inflight, active);
            let effects = zmodem.timeout_if_needed(
                Instant::now(),
                transport_available.then_some(&mut wire as &mut dyn Write),
            );
            let active_after = zmodem.active_transfer();
            let confirm_closing_zfin = zmodem.receiver_waiting_final_oo();
            self.remember_zmodem_state(&zmodem);
            (effects, active.or(active_after), confirm_closing_zfin)
        };
        if let Some(mut effects) = outcome {
            let continue_buffered_receive = self.publish_receive_file_completions(&mut effects);
            let confirm_terminal_wire = !wire.is_empty()
                && (confirm_closing_zfin
                    || effects.events.iter().any(|event| {
                        matches!(
                            event.kind,
                            "zmodem_completed" | "zmodem_failed" | "zmodem_cancelled"
                        )
                    }));
            let wire_result = self.write_zmodem_wire_releasing_transport(
                &wire,
                _transport,
                owner,
                confirm_terminal_wire,
                ZmodemWireJobKind::Protocol,
            );
            if self.zmodem_operation_epoch.load(Ordering::Acquire) != operation_epoch {
                // Cancellation/forced termination owns the manager and its
                // terminal event. Never publish timeout effects computed
                // before the transport gate was released.
                drop(sequence);
                return;
            }
            if wire_result.is_err() {
                effects = self.fail_zmodem_after_wire_error_preserving_commits(effects, owner);
            }
            let deferred_failure = self.flush_deferred_pty_writes_if_idle();
            let mut passthrough = self.apply_zmodem_effects(effects, deferred_failure);
            drop(sequence);
            if continue_buffered_receive
                && !self.zmodem_transport_terminated.load(Ordering::Acquire)
            {
                passthrough.extend(self.route_pty_output(&[]));
            }
            if !passthrough.is_empty() {
                self.recording.lock().record_pty_output(&passthrough);
                self.ingest_pty_output(&passthrough, true);
            }
        } else {
            drop(sequence);
        }
    }

    fn accept_zmodem_receive(
        &self,
        transfer_id: u64,
        destination: &std::path::Path,
    ) -> Result<(), SessionError> {
        if !cfg!(any(target_os = "macos", target_os = "linux")) {
            return Err(SessionError::Zmodem("unsupported_platform".to_string()));
        }
        let Some(_sequence) = self.zmodem_sequence_gate.try_lock() else {
            return Err(SessionError::Zmodem("zmodem_transport_busy".to_string()));
        };
        let Some(_transport) = self.zmodem_transport_gate.try_lock() else {
            return Err(SessionError::Zmodem("zmodem_transport_busy".to_string()));
        };
        let Some(_transition) = self.begin_zmodem_state_transition() else {
            return Err(SessionError::Zmodem("session_closing".to_string()));
        };
        let operation_epoch = self.zmodem_operation_epoch.load(Ordering::Acquire);
        if !self.pty_writer_available.load(Ordering::Acquire) {
            return Err(SessionError::ReadOnlyReplaySession(self.session_id));
        }
        let mut wire = Vec::new();
        let result = {
            let mut zmodem = self.zmodem.lock();
            let _inflight = ZmodemInFlightGuard::new(
                &self.zmodem_inflight,
                Some((transfer_id, ZmodemDirection::Receive)),
            );
            let result = match zmodem.accept_receive(transfer_id, destination, &mut wire) {
                Ok(effects) => Ok(effects),
                Err(error) => {
                    let failure = Self::abort_zmodem_command_error(&mut zmodem, &error, &mut wire);
                    Err((error, failure))
                }
            };
            self.remember_zmodem_state(&zmodem);
            result
        };
        let mut effects = match result {
            Ok(effects) => effects,
            Err((error, failure)) => {
                if let Some(failure) = failure {
                    let wire_result = self.write_zmodem_wire_releasing_transport(
                        &wire,
                        _transport,
                        Some((transfer_id, ZmodemDirection::Receive)),
                        false,
                        ZmodemWireJobKind::Protocol,
                    );
                    if self.zmodem_operation_epoch.load(Ordering::Acquire) != operation_epoch {
                        return Err(SessionError::Zmodem("stale transfer".to_string()));
                    }
                    if wire_result.is_err() {
                        self.apply_zmodem_effects_and_ingest_passthrough(
                            self.fail_zmodem_after_wire_error(),
                            None,
                        );
                        return Err(SessionError::Io("ZMODEM PTY write failed".to_string()));
                    }
                    self.apply_zmodem_effects_and_ingest_passthrough(failure, None);
                }
                return Err(SessionError::Zmodem(error.to_string()));
            }
        };
        let continue_buffered_receive = self.publish_receive_file_completions(&mut effects);
        let wire_result = self.write_zmodem_wire_releasing_transport(
            &wire,
            _transport,
            Some((transfer_id, ZmodemDirection::Receive)),
            false,
            ZmodemWireJobKind::Protocol,
        );
        if self.zmodem_operation_epoch.load(Ordering::Acquire) != operation_epoch {
            return Err(SessionError::Zmodem("stale transfer".to_string()));
        }
        if wire_result.is_err() {
            self.apply_zmodem_effects_and_ingest_passthrough(
                self.fail_zmodem_after_wire_error(),
                None,
            );
            return Err(SessionError::Io("ZMODEM PTY write failed".to_string()));
        }
        let deferred_failure = self.flush_deferred_pty_writes_if_idle();
        self.apply_zmodem_effects_and_ingest_passthrough(effects, deferred_failure);
        if continue_buffered_receive && !self.zmodem_transport_terminated.load(Ordering::Acquire) {
            let passthrough = self.route_pty_output(&[]);
            if !passthrough.is_empty() {
                self.recording.lock().record_pty_output(&passthrough);
                self.ingest_pty_output(&passthrough, true);
            }
        }
        Ok(())
    }

    fn accept_zmodem_send(
        &self,
        transfer_id: u64,
        paths: &[std::path::PathBuf],
    ) -> Result<(), SessionError> {
        if !cfg!(any(target_os = "macos", target_os = "linux")) {
            return Err(SessionError::Zmodem("unsupported_platform".to_string()));
        }
        let Some(_sequence) = self.zmodem_sequence_gate.try_lock() else {
            return Err(SessionError::Zmodem("zmodem_transport_busy".to_string()));
        };
        let Some(_transport) = self.zmodem_transport_gate.try_lock() else {
            return Err(SessionError::Zmodem("zmodem_transport_busy".to_string()));
        };
        let Some(_transition) = self.begin_zmodem_state_transition() else {
            return Err(SessionError::Zmodem("session_closing".to_string()));
        };
        let operation_epoch = self.zmodem_operation_epoch.load(Ordering::Acquire);
        if !self.pty_writer_available.load(Ordering::Acquire) {
            return Err(SessionError::ReadOnlyReplaySession(self.session_id));
        }
        let mut wire = Vec::new();
        let result = {
            let mut zmodem = self.zmodem.lock();
            let _inflight = ZmodemInFlightGuard::new(
                &self.zmodem_inflight,
                Some((transfer_id, ZmodemDirection::Send)),
            );
            let result = match zmodem.accept_send(transfer_id, paths, &mut wire) {
                Ok(effects) => Ok(effects),
                Err(error) => {
                    let failure = Self::abort_zmodem_command_error(&mut zmodem, &error, &mut wire);
                    Err((error, failure))
                }
            };
            self.remember_zmodem_state(&zmodem);
            result
        };
        let effects = match result {
            Ok(effects) => effects,
            Err((error, failure)) => {
                if let Some(failure) = failure {
                    let wire_result = self.write_zmodem_wire_releasing_transport(
                        &wire,
                        _transport,
                        Some((transfer_id, ZmodemDirection::Send)),
                        false,
                        ZmodemWireJobKind::Protocol,
                    );
                    if self.zmodem_operation_epoch.load(Ordering::Acquire) != operation_epoch {
                        return Err(SessionError::Zmodem("stale transfer".to_string()));
                    }
                    if wire_result.is_err() {
                        self.apply_zmodem_effects_and_ingest_passthrough(
                            self.fail_zmodem_after_wire_error(),
                            None,
                        );
                        return Err(SessionError::Io("ZMODEM PTY write failed".to_string()));
                    }
                    self.apply_zmodem_effects_and_ingest_passthrough(failure, None);
                }
                return Err(SessionError::Zmodem(error.to_string()));
            }
        };
        let wire_result = self.write_zmodem_wire_releasing_transport(
            &wire,
            _transport,
            Some((transfer_id, ZmodemDirection::Send)),
            false,
            ZmodemWireJobKind::Protocol,
        );
        if self.zmodem_operation_epoch.load(Ordering::Acquire) != operation_epoch {
            return Err(SessionError::Zmodem("stale transfer".to_string()));
        }
        if wire_result.is_err() {
            self.apply_zmodem_effects_and_ingest_passthrough(
                self.fail_zmodem_after_wire_error(),
                None,
            );
            return Err(SessionError::Io("ZMODEM PTY write failed".to_string()));
        }
        let deferred_failure = self.flush_deferred_pty_writes_if_idle();
        self.apply_zmodem_effects_and_ingest_passthrough(effects, deferred_failure);
        Ok(())
    }

    fn cancel_zmodem(&self, transfer_id: u64) -> Result<(), SessionError> {
        let Some(_transport) = self.zmodem_transport_gate.try_lock() else {
            // The manager and its remembered identity are published while
            // this gate is held. Never authorize an id-bound cancellation
            // from a snapshot that may be changing old -> new; the caller can
            // retry after this short state transition. Stalled PTY writes do
            // not hold the gate and still take the fail-closed path below.
            return Err(SessionError::Zmodem("zmodem_transport_busy".to_string()));
        };
        let direction = self
            .remembered_zmodem_active()
            .filter(|(active_id, _)| *active_id == transfer_id)
            .map(|(_, direction)| direction)
            .ok_or_else(|| SessionError::Zmodem("stale transfer".to_string()))?;
        if !self.try_invalidate_receive_commit() {
            return Err(SessionError::Zmodem(
                "receive_commit_in_progress".to_string(),
            ));
        }
        let Some(_transition) = self.begin_zmodem_state_transition() else {
            return Err(SessionError::Zmodem("session_closing".to_string()));
        };
        let mut wire = Vec::new();
        let mut effects = {
            let mut zmodem = self.zmodem.lock();
            let _inflight =
                ZmodemInFlightGuard::new(&self.zmodem_inflight, zmodem.active_transfer());
            let effects = zmodem
                .cancel(transfer_id, &mut wire)
                .map_err(|error| SessionError::Zmodem(error.to_string()))?;
            self.remember_zmodem_state(&zmodem);
            effects
        };
        // Invalidate effects from operations that released the gate before
        // cancellation, and let the writer actor discard queued protocol
        // jobs from the old generation before it writes the ordered CAN
        // control job. A later transfer cannot make those jobs eligible
        // again even when the public transfer id is reused.
        if self.zmodem_wire_inflight.lock().is_some() {
            // A CAN frame cannot overtake an actor write already inside the
            // PTY syscall. Tear the transport down immediately instead of
            // keeping the synchronous Session Request blocked for the
            // writer watchdog interval.
            drop(_transport);
            self.force_zmodem_terminal(transfer_id, direction, true);
            return Ok(());
        }
        let wire_result = if self.zmodem_wire_tx.lock().is_some() {
            self.write_zmodem_wire_releasing_transport(
                &wire,
                _transport,
                Some((transfer_id, direction)),
                false,
                ZmodemWireJobKind::Cancel,
            )
        } else {
            drop(_transport);
            self.try_write_zmodem_wire_fallback(&wire)
        };
        if wire_result.is_err() {
            let mut zmodem = self.zmodem.lock();
            let closed = zmodem.transport_closed(false);
            effects.passthrough.extend(closed.passthrough);
            effects.events.extend(closed.events);
            effects.terminate_transport = true;
        }
        let deferred_failure = self.flush_deferred_pty_writes_if_idle();
        self.apply_zmodem_effects(effects, deferred_failure);
        Ok(())
    }

    fn cancel_active_zmodem(&self) -> Result<CancelActiveZmodemOutcome, SessionError> {
        if let Some((transfer_id, _)) = self.remembered_zmodem_active() {
            self.cancel_zmodem(transfer_id)?;
            return Ok(CancelActiveZmodemOutcome::Cancelled);
        }
        let Some(transport) = self.zmodem_transport_gate.try_lock() else {
            if self.zmodem_draining.load(Ordering::Acquire) {
                // The reader may currently be consuming residual bytes while
                // the public transfer id is already gone. Reconciliation is
                // idempotent throughout that bounded quarantine.
                return Ok(CancelActiveZmodemOutcome::Draining);
            }
            return Err(SessionError::Zmodem("zmodem_transport_busy".to_string()));
        };
        let was_draining = self.zmodem.lock().is_draining();
        drop(transport);
        if was_draining {
            // A successful id-bound cancel deliberately enters Draining with
            // no public transfer id. Reconciliation during that bounded
            // window is idempotent: leave the PTY alive and let deferred
            // ordinary input flush at the drain boundary.
            return Ok(CancelActiveZmodemOutcome::Draining);
        }
        Ok(CancelActiveZmodemOutcome::Idle)
    }

    fn resolve_zmodem_recovery(&self, token: &str) -> Option<std::path::PathBuf> {
        // Recovery ownership lives in the process-wide registry. Do not wait
        // for the protocol manager: a timed-out receive may leave that mutex
        // owned by an abandoned filesystem operation.
        crate::zmodem::resolve_owned_recovery(token, self.session_id)
    }

    pub fn replay_output(&self, bytes: &[u8]) -> Result<(), SessionError> {
        if !self.is_replay {
            return Err(SessionError::NotReplaySession(self.session_id));
        }
        if self.exited.load(Ordering::SeqCst) {
            return Err(SessionError::ReadOnlyReplaySession(self.session_id));
        }
        self.ingest_pty_output(bytes, false);
        Ok(())
    }

    pub fn replay_exit(&self, exit_code: Option<i32>) -> Result<(), SessionError> {
        if !self.is_replay {
            return Err(SessionError::NotReplaySession(self.session_id));
        }
        if !self.exited.swap(true, Ordering::SeqCst) {
            self.push_event(
                "exit",
                Some(serde_json::json!({
                    "code": exit_code,
                    "success": exit_code == Some(0),
                    "signal": null,
                })),
            );
        }
        Ok(())
    }

    pub fn capture_replay_checkpoint(&self) -> Result<u64, SessionError> {
        if !self.is_replay {
            return Err(SessionError::NotReplaySession(self.session_id));
        }
        if self.exited.load(Ordering::SeqCst) {
            return Err(SessionError::ReadOnlyReplaySession(self.session_id));
        }
        let state = self.state.lock();
        self.replay_checkpoints.lock().capture(&state)
    }

    pub fn restore_replay_checkpoint(&self, checkpoint_id: u64) -> Result<(), SessionError> {
        if !self.is_replay {
            return Err(SessionError::NotReplaySession(self.session_id));
        }
        let checkpoint = self.replay_checkpoints.lock().get(checkpoint_id).ok_or(
            SessionError::MissingReplayCheckpoint {
                session_id: self.session_id,
                checkpoint_id,
            },
        )?;
        {
            let mut state = self.state.lock();
            state.terminal.restore_from_snapshot(checkpoint.snapshot);
            state.transcript = checkpoint.transcript;
            state.transcript_truncated = checkpoint.transcript_truncated;
            state.scrollback_offset = checkpoint.scrollback_offset;
            state.host_protocol = checkpoint.host_protocol;
            state.graphic_assets.clear();
            state.graphic_asset_bytes = 0;
            state.pending_file_downloads.clear();
            state.pending_file_download_bytes = 0;
            state.replay_checkpoint_boundary = ReplayCheckpointBoundary::default();
        }
        self.last_rows.lock().clear();
        *self.last_frame_meta.lock() = None;
        *self.last_frame_debug_stats.lock() = None;
        *self.last_frame_had_graphics.lock() = false;
        *self.deferred_clear_graphics_frame.lock() = None;
        *self.deferred_kitty_delete_graphics_frame.lock() = None;
        *self.deferred_inline_clear_frame.lock() = None;
        self.exited.store(false, Ordering::SeqCst);
        self.pending_frame_signal
            .mutate(|work| work.mark_full_repaint("replay_checkpoint_restore"));
        Ok(())
    }

    pub fn ping(&self) -> i32 {
        42
    }

    pub fn refresh_hint_flags(&self) -> u32 {
        // Keyboard-interactive authentication blocks the transport thread
        // until the client responds. Promote brokered prompts before taking
        // the event snapshot so refresh-hint-driven clients wake immediately.
        self.publish_pending_ssh_auth_prompts();
        let mut flags = if self.pending_frame_signal.has_refresh_hint() {
            REFRESH_HINT_FRAME_DIRTY
        } else {
            0
        };
        // Snapshot final-exit authority under the same gate used by event
        // publication and drain. The caller therefore sees either the still
        // pending exit or its already-queued event, never an idle gap between
        // the two states.
        let _publication = self.zmodem_event_publication_gate.lock();
        if !self.events.lock().entries.is_empty() {
            flags |= REFRESH_HINT_EVENT_PENDING;
        }
        if self.pending_child_exit.lock().is_some()
            || (self.zmodem_transport_terminated.load(Ordering::Acquire)
                && !self.exited.load(Ordering::Acquire)
                && !self.is_replay)
        {
            flags |= REFRESH_HINT_EXIT_PENDING;
        }
        flags
    }

    fn close_readiness(&self) -> (bool, &'static str) {
        let _publication = self.zmodem_event_publication_gate.lock();
        if self
            .zmodem_state_transitions_inflight
            .load(Ordering::Acquire)
            != 0
            && !self.zmodem_transport_terminated.load(Ordering::Acquire)
        {
            return (false, "zmodem_transition");
        }
        if self.remembered_zmodem_active().is_some() {
            return (false, "zmodem_transfer_active");
        }
        if self.zmodem_draining.load(Ordering::Acquire) {
            return (false, "zmodem_draining");
        }
        if self.events.lock().has_pending_zmodem_terminal_result() {
            return (false, "zmodem_result_pending");
        }
        if matches!(
            self.zmodem_receive_commit_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_PUBLISHING | RECEIVE_COMMIT_RESULT_READY
        ) {
            return (false, "receive_publication_in_progress");
        }
        (true, "idle")
    }

    pub fn close(&self) -> Result<(), SessionError> {
        let publication = self.zmodem_event_publication_gate.lock();
        // Native state is authoritative. Dart may not have polled the first
        // detected/file-offer event yet, so a UI-side active-transfer set is
        // not sufficient to protect the stream from close. The remembered
        // atomics are updated before event publication and remain set through
        // cancel/terminal drain.
        if (self
            .zmodem_state_transitions_inflight
            .load(Ordering::Acquire)
            != 0
            && !self.zmodem_transport_terminated.load(Ordering::Acquire))
            || self.remembered_zmodem_active().is_some()
            || self.zmodem_draining.load(Ordering::Acquire)
        {
            return Err(SessionError::Zmodem("zmodem_transfer_active".to_string()));
        }
        if self.events.lock().has_pending_zmodem_terminal_result() {
            return Err(SessionError::Zmodem("zmodem_result_pending".to_string()));
        }
        // Atomically prevent a future receive publication before teardown.
        // If publication already owns the phase, fail promptly and retain the
        // session/event queue so a late recovery token cannot be lost.
        if !self.try_invalidate_receive_commit() && !self.abandon_timed_out_receive_publication() {
            return Err(SessionError::Zmodem(
                "receive_publication_in_progress".to_string(),
            ));
        }
        // No transition can start after this store: acquisition checks the
        // flag while holding `publication`, and all earlier guards have been
        // observed at zero above.
        self.zmodem_state_transitions_closed
            .store(true, Ordering::Release);
        drop(publication);
        self.exited.store(true, Ordering::SeqCst);
        crate::zmodem::tombstone_recovery_session(self.session_id);
        // A publish syscall on a network/FUSE filesystem may be
        // uninterruptible. Mark the transport closed first and detach any
        // unfinished reader instead of making session close depend on that
        // external filesystem returning.
        self.terminate_zmodem_transport();
        self.join_worker_threads();
        if let Some(mut zmodem) = self.zmodem.try_lock() {
            zmodem.reset();
            self.remember_zmodem_state(&zmodem);
        }
        Ok(())
    }

    fn join_worker_threads(&self) {
        self.zmodem_wire_tx.lock().take();
        let (zmodem_writer, reader, resource_sampler) = {
            let mut worker_handles = self.worker_handles.lock();
            (
                worker_handles.zmodem_writer.take(),
                worker_handles.reader.take(),
                worker_handles.resource_sampler.take(),
            )
        };

        if let Some(handle) = zmodem_writer
            && handle.is_finished()
        {
            let _ = handle.join();
        }
        if let Some(handle) = resource_sampler {
            handle.thread().unpark();
            if handle.is_finished() {
                let _ = handle.join();
            }
        }
        if let Some(handle) = reader
            && handle.is_finished()
        {
            let _ = handle.join();
        }
    }

    fn start_zmodem_writer(session: &Arc<Self>) -> Result<thread::JoinHandle<()>, SessionError> {
        let mut writer = session
            .writer
            .lock()
            .take()
            .ok_or_else(|| SessionError::Io("PTY writer is unavailable".to_string()))?;
        let (sender, receiver) = mpsc::channel::<QueuedZmodemWireJob>();
        let weak_session = Arc::downgrade(session);
        if inject_zmodem_writer_thread_spawn_failure() {
            return Err(SessionError::Io(
                "injected ZMODEM writer thread spawn failure".to_string(),
            ));
        }
        let handle = thread::Builder::new()
            .name(format!("zmodem-writer-{}", session.session_id))
            .spawn(move || {
                let mut writer_failed = false;
                let mut pending_failure = None;
                while let Ok(queued) = receiver.recv() {
                    let reserved_bytes = queued.reserved_bytes;
                    let job = queued.job;
                    let marker = job.owner.map(|(transfer_id, direction)| ZmodemInFlight {
                        transfer_id,
                        direction,
                        started_at: Instant::now(),
                    });
                    // Eligibility is decided before publishing the syscall
                    // marker. A stale queued protocol job is discarded and
                    // must never look like an in-progress write to cancel,
                    // which would unnecessarily tear down the PTY.
                    let mut marker_installed = false;
                    let result = if writer_failed {
                        Err(ZmodemWireError::Io)
                    } else {
                        let Some(session) = weak_session.upgrade() else {
                            if let Some(completion) = job.completion {
                                let _ = completion.send(Err(ZmodemWireError::Cancelled));
                            }
                            break;
                        };
                        // Cancellation advances the operation epoch before it
                        // inspects this same slot. Checking eligibility and
                        // installing the marker under one lock gives a strict
                        // ordering: either cancel sees a real syscall marker,
                        // or this actor sees the stale generation and drops it.
                        let cancelled_before_write = {
                            let mut slot = session.zmodem_wire_inflight.lock();
                            let cancelled = session
                                .zmodem_transport_terminated
                                .load(Ordering::Acquire)
                                || (job.kind == ZmodemWireJobKind::Protocol
                                    && queued.generation
                                        < session.zmodem_operation_epoch.load(Ordering::Acquire));
                            if !cancelled && let Some(marker) = marker {
                                *slot = Some(marker);
                                marker_installed = true;
                            }
                            cancelled
                        };
                        // A PTY write can remain in an uninterruptible syscall.
                        // The actor owns only a Weak while blocked so closing
                        // product/runtime state can release the session.
                        drop(session);
                        if cancelled_before_write {
                            Err(ZmodemWireError::Cancelled)
                        } else {
                            writer
                                .write_all(&job.bytes)
                                .map_err(|_| ZmodemWireError::Io)
                        }
                    };
                    let Some(session) = weak_session.upgrade() else {
                        if let Some(completion) = job.completion {
                            let _ = completion.send(result);
                        }
                        break;
                    };
                    session
                        .zmodem_wire_queued_bytes
                        .fetch_sub(reserved_bytes, Ordering::AcqRel);
                    if marker_installed && let Some(marker) = marker {
                        let mut slot = session.zmodem_wire_inflight.lock();
                        if *slot == Some(marker) {
                            *slot = None;
                        }
                    }
                    let first_io_failure = result == Err(ZmodemWireError::Io) && !writer_failed;
                    let failure_owner = first_io_failure
                        .then(|| session.remembered_zmodem_active().or(job.owner))
                        .flatten();
                    let failure_transition = failure_owner.and_then(|_| {
                        TerminalSession::begin_owned_zmodem_state_transition(&session)
                    });
                    if first_io_failure {
                        writer_failed = true;
                        // Fail closed before resolving this job or observing
                        // another queued job. Dropping the public sender stops
                        // new work; this actor only drains queued completion
                        // channels with Io after the first failed syscall.
                        // Do this independently of full transport termination:
                        // that routine deliberately defers teardown while a
                        // receive publication owns its commit boundary.
                        session.zmodem_wire_tx.lock().take();
                        session.terminate_zmodem_transport();
                    }
                    if let Some(completion) = job.completion {
                        let _ = completion.send(result);
                    }
                    if first_io_failure
                        && let (Some(failure_owner), Some(failure_transition)) =
                            (failure_owner, failure_transition)
                    {
                        // `terminate_zmodem_transport` disconnects the public
                        // sender. Drain every already-queued completion before
                        // taking the sequence gate; callers may own that gate
                        // while awaiting this actor. Publishing here after the
                        // receiver closes needs no fallible notifier thread.
                        pending_failure = Some((failure_owner, failure_transition));
                    }
                }
                if let Some((failure_owner, failure_transition)) = pending_failure {
                    let failure_session = Arc::clone(&failure_transition.session);
                    let _transition = failure_transition;
                    let _sequence = failure_session.zmodem_sequence_gate.lock();
                    failure_session.apply_zmodem_effects_and_ingest_passthrough(
                        failure_session.fail_zmodem_after_wire_error_for(Some(failure_owner)),
                        None,
                    );
                }
            })
            .map_err(|error| SessionError::Io(error.to_string()))?;
        *session.zmodem_wire_tx.lock() = Some(sender);
        Ok(handle)
    }

    fn start_zmodem_writer_or_teardown(
        session: &Arc<Self>,
    ) -> Result<thread::JoinHandle<()>, SessionError> {
        match Self::start_zmodem_writer(session) {
            Ok(handle) => Ok(handle),
            Err(error) => {
                // The child is already spawned and the PTY writer may already
                // have moved into the failed thread closure. Make failed
                // session creation a scoped teardown instead of dropping an
                // untracked live shell process.
                session.exited.store(true, Ordering::Release);
                session.terminate_zmodem_transport();
                crate::zmodem::tombstone_recovery_session(session.session_id);
                Err(error)
            }
        }
    }

    fn start_resource_sampler(session: &Arc<Self>) -> thread::JoinHandle<()> {
        let resource_session = Arc::clone(session);
        thread::spawn(move || {
            let mut sampling_enabled = true;
            let mut next_resource_sample = Instant::now();
            loop {
                if resource_session.resource_sampler_should_stop() {
                    break;
                }
                resource_session.poll_zmodem_timeout();
                let now = Instant::now();
                if sampling_enabled && now >= next_resource_sample {
                    let keep_sampling = resource_session.record_resource_sample();
                    next_resource_sample = now + RESOURCE_SAMPLE_INTERVAL;
                    let failures = resource_session
                        .resource_sampler_state
                        .lock()
                        .consecutive_failures;
                    if !keep_sampling && failures >= RESOURCE_SAMPLER_MAX_FAILURES {
                        // ZMODEM authorization, idle, and quarantine deadlines
                        // must remain live even if process metrics are no
                        // longer available.
                        sampling_enabled = false;
                    }
                }
                // Poll child status autonomously as well as retrying pending
                // publication. A disabled-polling client may consume the
                // watchdog failure just before the killed child is waitable.
                let _ = resource_session.observe_child_exit();
                // Scanner-held terminal text has a 100 ms release deadline;
                // protocol/auth/quarantine deadlines also must not inherit
                // the coarser process-resource sampling cadence.
                thread::park_timeout(ZMODEM_DEADLINE_POLL_INTERVAL);
            }
        })
    }

    fn resource_sampler_should_stop(&self) -> bool {
        self.exited.load(Ordering::Acquire)
            && self.pending_child_exit.lock().is_none()
            && (self.pty_reader_closed.load(Ordering::Acquire)
                || self.zmodem_transport_terminated.load(Ordering::Acquire))
            && self.zmodem_active_transfer_id.load(Ordering::Acquire) == 0
            && !self.zmodem_draining.load(Ordering::Acquire)
            && !matches!(
                self.zmodem_receive_commit_phase.load(Ordering::Acquire),
                RECEIVE_COMMIT_PUBLISHING | RECEIVE_COMMIT_RESULT_READY
            )
    }

    fn record_resource_sample(&self) -> bool {
        let timestamp_micros = unix_timestamp_micros();
        let Some(pid) = self.child_pid else {
            self.resource_sampler_state.lock().consecutive_failures = RESOURCE_SAMPLER_MAX_FAILURES;
            self.push_resource_sample(ResourceSample {
                timestamp_micros,
                session_id: self.session_id,
                child_pid: None,
                process_name: self.process_name.clone(),
                cpu_percent: None,
                rss_bytes: None,
                virtual_bytes: None,
                thread_count: None,
                total_user_micros: None,
                total_system_micros: None,
                sample_error: Some("child_pid_unavailable".to_string()),
            });
            return false;
        };

        let sampled_at = Instant::now();
        match sample_process_resource(pid) {
            Ok(snapshot) => {
                let total_cpu_micros = snapshot
                    .total_user_micros
                    .saturating_add(snapshot.total_system_micros);
                let cpu_percent = {
                    let mut sampler_state = self.resource_sampler_state.lock();
                    let previous_total = sampler_state.previous_total_cpu_micros;
                    let previous_sampled_at = sampler_state.previous_sampled_at;
                    sampler_state.previous_total_cpu_micros = Some(total_cpu_micros);
                    sampler_state.previous_sampled_at = Some(sampled_at);
                    sampler_state.consecutive_failures = 0;

                    previous_total.zip(previous_sampled_at).and_then(
                        |(previous_total, previous_sampled_at)| {
                            let elapsed_micros =
                                sampled_at.duration_since(previous_sampled_at).as_micros() as f64;
                            if elapsed_micros <= 0.0 || total_cpu_micros < previous_total {
                                return None;
                            }
                            let used_micros = total_cpu_micros - previous_total;
                            Some(((used_micros as f64 / elapsed_micros) * 100.0).max(0.0))
                        },
                    )
                };
                self.push_resource_sample(ResourceSample {
                    timestamp_micros,
                    session_id: self.session_id,
                    child_pid: Some(pid),
                    process_name: self.process_name.clone(),
                    cpu_percent,
                    rss_bytes: Some(snapshot.rss_bytes),
                    virtual_bytes: Some(snapshot.virtual_bytes),
                    thread_count: Some(snapshot.thread_count),
                    total_user_micros: Some(snapshot.total_user_micros),
                    total_system_micros: Some(snapshot.total_system_micros),
                    sample_error: None,
                });
                true
            }
            Err(error) => {
                {
                    let mut sampler_state = self.resource_sampler_state.lock();
                    sampler_state.consecutive_failures =
                        sampler_state.consecutive_failures.saturating_add(1);
                }
                self.push_resource_sample(ResourceSample {
                    timestamp_micros,
                    session_id: self.session_id,
                    child_pid: Some(pid),
                    process_name: self.process_name.clone(),
                    cpu_percent: None,
                    rss_bytes: None,
                    virtual_bytes: None,
                    thread_count: None,
                    total_user_micros: None,
                    total_system_micros: None,
                    sample_error: Some(error),
                });
                false
            }
        }
    }

    fn push_resource_sample(&self, sample: ResourceSample) {
        let mut samples = self.resource_samples.lock();
        samples.push_back(sample);
        while samples.len() > RESOURCE_SAMPLE_CAPACITY {
            samples.pop_front();
        }
    }

    pub fn resize(
        &self,
        cols: u16,
        rows: u16,
        pixel_width: u16,
        pixel_height: u16,
    ) -> Result<(), SessionError> {
        self.resize_with_cell_size(cols, rows, pixel_width, pixel_height, 0, 0)
    }

    pub fn resize_with_cell_size(
        &self,
        cols: u16,
        rows: u16,
        pixel_width: u16,
        pixel_height: u16,
        cell_width: u16,
        cell_height: u16,
    ) -> Result<(), SessionError> {
        let mut recording = self.recording.lock();
        let mut state = self.state.lock();
        let mut resize_replay_observation = None;
        let mut resize_replay_skipped_truncated = false;
        let (current_cols, current_rows) = state.terminal.size();
        let size_changed = current_cols != cols as usize || current_rows != rows as usize;

        if !size_changed {
            apply_terminal_pixel_metrics(
                &mut state.terminal,
                cols,
                rows,
                pixel_width,
                pixel_height,
                cell_width,
                cell_height,
            );
            if !self.is_replay {
                recording.record_resize(
                    cols,
                    rows,
                    pixel_width,
                    pixel_height,
                    cell_width,
                    cell_height,
                );
            }
            return Ok(());
        }

        let previous_max = current_scrollback_max(&state);

        // Keep SIGWINCH-triggered redraw output from being processed between
        // the PTY resize and the internal reflow/replay. Otherwise readline can
        // leak transient prompt redraws into the replay transcript.
        if let Some(master) = self.master.lock().as_mut() {
            master
                .resize(portable_pty::PtySize {
                    rows,
                    cols,
                    pixel_width,
                    pixel_height,
                })
                .map_err(|error| SessionError::Pty(error.to_string()))?;
        }

        let should_rebuild_main_screen = !state.terminal.is_alt_screen_active();

        if should_rebuild_main_screen && !state.transcript_truncated {
            let block_view_overrides = state
                .terminal
                .iterm_blocks()
                .iter()
                .filter(|block| block.complete)
                .map(|block| (block.id.clone(), block.folded, block.render))
                .collect::<Vec<_>>();
            let transcript = state.transcript.clone();
            let mut terminal =
                Terminal::with_scrollback(cols as usize, rows as usize, self.scrollback_lines);
            configure_session_terminal(
                &mut terminal,
                self.emulation,
                self.graphics_memory_limits,
                &self.profile_colors,
                &self.profile_font,
                self.osc633_expected_nonce.as_deref(),
                self.drag_drop_enabled,
            );
            if pixel_width > 0 && pixel_height > 0 {
                apply_terminal_pixel_metrics(
                    &mut terminal,
                    cols,
                    rows,
                    pixel_width,
                    pixel_height,
                    cell_width,
                    cell_height,
                );
            }
            let replay_started_at = Instant::now();
            terminal.process(&transcript);
            resize_replay_observation = Some((
                transcript.len() as u64,
                replay_started_at.elapsed().as_micros() as u64,
            ));
            // Replaying the transcript rebuilds terminal state only. Historical
            // host-facing effects must not be delivered again on the next PTY
            // read after resize.
            discard_replayed_parser_host_events(&mut terminal);
            let _ = terminal.take_notifications();
            let _ = terminal.drain_responses();
            let _ = terminal.take_process_debug_stats();
            // Protocol replay reconstructs block ranges at the new width. Keep
            // user-driven fold and document-close choices made after ingress.
            for (id, folded, rendered) in block_view_overrides {
                let _ = terminal.set_iterm_block_folded(&id, folded);
                let _ = terminal.set_iterm_block_rendered(&id, rendered);
            }
            state.terminal = terminal;
        } else {
            resize_replay_skipped_truncated =
                should_rebuild_main_screen && state.transcript_truncated;
            state.terminal.resize(cols as usize, rows as usize);
            apply_terminal_pixel_metrics(
                &mut state.terminal,
                cols,
                rows,
                pixel_width,
                pixel_height,
                cell_width,
                cell_height,
            );
        }
        let new_max = current_scrollback_max(&state);
        state.scrollback_offset =
            remap_scrollback_offset(state.scrollback_offset, previous_max, new_max);
        if state.terminal.is_alt_screen_active() {
            state.scrollback_offset = 0;
        }
        drop(state);

        {
            let mut stats = self.session_debug_stats.lock();
            if let Some((bytes, micros)) = resize_replay_observation {
                stats.resize_replay_count = stats.resize_replay_count.saturating_add(1);
                stats.resize_replay_bytes = stats.resize_replay_bytes.saturating_add(bytes);
                stats.resize_replay_micros = stats.resize_replay_micros.saturating_add(micros);
            }
            if resize_replay_skipped_truncated {
                stats.resize_replay_skipped_truncated_count = stats
                    .resize_replay_skipped_truncated_count
                    .saturating_add(1);
            }
        }

        self.last_rows.lock().clear();
        *self.last_frame_meta.lock() = None;
        self.pending_frame_signal
            .mutate(|work| work.mark_full_repaint("resize"));
        if !self.is_replay {
            recording.record_resize(
                cols,
                rows,
                pixel_width,
                pixel_height,
                cell_width,
                cell_height,
            );
        }
        Ok(())
    }

    pub fn write(&self, bytes: &[u8]) -> Result<(), SessionError> {
        if self.is_replay {
            return Err(SessionError::ReadOnlyReplaySession(self.session_id));
        }
        self.write_non_zmodem_ordered(bytes, true, false)
    }

    pub fn write_protocol_reply(&self, bytes: &[u8]) -> Result<(), SessionError> {
        if self.is_replay {
            return Err(SessionError::ReadOnlyReplaySession(self.session_id));
        }
        // Unlike user input, a terminal/host protocol reply may complete
        // asynchronously after native has detected ZMODEM but before Dart has
        // polled the detection event. Queue it behind the transfer at the
        // authoritative native ordering boundary instead of dropping it or
        // allowing it to corrupt the ZMODEM wire stream.
        self.write_non_zmodem_ordered(bytes, false, true)
    }

    pub fn respond_host_v1(&self, raw: &str) -> Result<(), SessionError> {
        let response = self
            .events
            .lock()
            .resolve_host_response(self.session_id, raw)
            .map_err(|error| SessionError::HostResponse(error.to_string()))?;
        if let Some(bytes) = response {
            self.write_non_zmodem_or_defer(&bytes, true)?;
        }
        Ok(())
    }

    pub fn scroll(&self, delta_lines: i32) {
        let mut state = self.state.lock();
        if state.terminal.is_alt_screen_active() {
            state.scrollback_offset = 0;
        } else {
            let next = state.scrollback_offset as i32 + delta_lines;
            state.scrollback_offset = next.max(0) as usize;
            state.scrollback_offset = state.scrollback_offset.min(current_scrollback_max(&state));
        }
        self.pending_frame_signal
            .mutate(|work| work.mark_full_repaint("scrollback_navigation"));
    }

    pub fn scroll_to(&self, offset: usize) {
        let mut state = self.state.lock();
        if state.terminal.is_alt_screen_active() {
            state.scrollback_offset = 0;
        } else {
            state.scrollback_offset = offset.min(current_scrollback_max(&state));
        }
        self.pending_frame_signal
            .mutate(|work| work.mark_full_repaint("scrollback_navigation"));
    }

    pub fn clear_scrollback(&self) -> Result<bool, SessionError> {
        let mut state = self.state.lock();
        state.terminal.process(b"\x1b[3J");
        state.scrollback_offset = 0;
        state.transcript.clear();
        state.transcript_truncated = true;
        drop(state);

        self.last_rows.lock().clear();
        *self.last_frame_meta.lock() = None;
        self.pending_frame_signal
            .mutate(|work| work.mark_full_repaint("clear_scrollback"));
        Ok(true)
    }

    pub fn clear_buffer(&self) -> Result<bool, SessionError> {
        let mut state = self.state.lock();
        // iTerm2 maps Command-K (Clear Buffer) to this OSC 1337 command. It
        // preserves the current prompt/editing line at the top while clearing
        // the rest of the visible grid and all retained history.
        state.terminal.process(b"\x1b]1337;ClearScrollback\x1b\\");
        state.scrollback_offset = 0;
        state.transcript.clear();
        state.transcript_truncated = true;
        drop(state);

        self.last_rows.lock().clear();
        *self.last_frame_meta.lock() = None;
        self.pending_frame_signal
            .mutate(|work| work.mark_full_repaint("clear_buffer"));
        Ok(true)
    }

    pub fn dismiss_osc99_notification(&self, identifier: &str) -> bool {
        self.state
            .lock()
            .terminal
            .dismiss_osc99_notification(identifier)
    }

    pub fn set_block_folded(&self, id: &str, folded: bool) -> bool {
        if id.is_empty()
            || id.chars().count() > par_term_emu_core_rust::terminal::MAX_ITERM_BLOCK_ID_CHARS
            || id.chars().any(char::is_control)
        {
            return false;
        }
        let mut state = self.state.lock();
        let changed = state.terminal.set_iterm_block_folded(id, folded);
        if changed {
            let max_offset = current_scrollback_max(&state);
            state.scrollback_offset = state.scrollback_offset.min(max_offset);
        }
        drop(state);
        if changed {
            self.last_rows.lock().clear();
            *self.last_frame_meta.lock() = None;
            self.pending_frame_signal.mutate(|work| {
                work.mark_full_repaint(if folded {
                    "iterm_block_fold_request"
                } else {
                    "iterm_block_unfold_request"
                })
            });
        }
        changed
    }

    pub fn set_block_rendered(&self, id: &str, rendered: bool) -> bool {
        if id.is_empty()
            || id.chars().count() > par_term_emu_core_rust::terminal::MAX_ITERM_BLOCK_ID_CHARS
            || id.chars().any(char::is_control)
        {
            return false;
        }
        let mut state = self.state.lock();
        let changed = state.terminal.set_iterm_block_rendered(id, rendered);
        drop(state);
        if changed {
            self.last_rows.lock().clear();
            *self.last_frame_meta.lock() = None;
            self.pending_frame_signal.mutate(|work| {
                work.mark_full_repaint(if rendered {
                    "iterm_block_render_request"
                } else {
                    "iterm_block_restore_request"
                })
            });
        }
        changed
    }

    pub fn activate_iterm_button(&self, id: u64) -> Result<serde_json::Value, SessionError> {
        if self.emulation != TerminalEmulation::Xterm256 || id == 0 {
            return Ok(serde_json::json!({ "activated": false }));
        }
        let activation = {
            let state = self.state.lock();
            let terminal = &state.terminal;
            let projection = display_projection_for_terminal(terminal);
            let (_, viewport_rows) = terminal.size();
            let scrollback_max_offset = projection.rows.len().saturating_sub(viewport_rows);
            let display_start_row = if terminal.is_alt_screen_active() {
                0
            } else {
                scrollback_max_offset
                    .saturating_sub(state.scrollback_offset.min(scrollback_max_offset))
            };
            if !build_terminal_inline_buttons(
                terminal,
                &projection,
                display_start_row,
                viewport_rows,
            )
            .iter()
            .any(|button| button.id == id)
            {
                return Ok(serde_json::json!({ "activated": false }));
            }
            let Some(button) = terminal.iterm_button(id) else {
                return Ok(serde_json::json!({ "activated": false }));
            };
            if !button.valid || button.alternate_screen != terminal.is_alt_screen_active() {
                return Ok(serde_json::json!({ "activated": false }));
            }
            match &button.kind {
                ItermButtonKind::Copy { .. } => terminal
                    .iterm_button_copy_text(id)
                    .map(ItermButtonActivation::Copy),
                ItermButtonKind::Custom { code, .. } => Some(ItermButtonActivation::Custom(*code)),
            }
        };
        match activation {
            Some(ItermButtonActivation::Copy(text)) => Ok(serde_json::json!({
                "activated": true,
                "kind": "copy",
                "text": text,
            })),
            Some(ItermButtonActivation::Custom(code)) => {
                self.write_non_zmodem_or_defer(format!("\x1b[?1337;{code}~").as_bytes(), false)?;
                Ok(serde_json::json!({
                    "activated": true,
                    "kind": "custom",
                }))
            }
            None => Ok(serde_json::json!({ "activated": false })),
        }
    }

    pub fn export_scrollback_text(&self, max_lines: Option<usize>) -> String {
        let state = self.state.lock();
        state
            .terminal
            .export_scrollback(ExportFormat::Plain, max_lines)
    }

    pub fn take_frame_diff(&self) -> Result<Option<TerminalFrameDiff>, SessionError> {
        let mut had_dirty_work = self.pending_frame_signal.is_dirty();

        let frame_started_at = Instant::now();

        let state_lock_started_at = Instant::now();
        let mut state = self.state.lock();
        let state_lock_wait_micros = state_lock_started_at.elapsed().as_micros() as u64;
        let frame_extract_started_at = Instant::now();
        let synchronized_timeout_flushed = state.terminal.flush_synchronized_updates_if_timed_out();
        if synchronized_timeout_flushed {
            had_dirty_work = true;
        }
        let graphics_animation_changed = if self.graphics_enabled
            && !state.terminal.synchronized_updates()
            && !state.terminal.kitty_graphics_transfer_in_progress()
        {
            !state.terminal.update_animations().is_empty()
        } else {
            false
        };
        if !had_dirty_work && !graphics_animation_changed {
            return Ok(None);
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
        let (signal_was_dirty, refresh_hint_was_dirty, pending_frame_work) =
            self.pending_frame_signal.take();
        had_dirty_work = signal_was_dirty || synchronized_timeout_flushed;
        if !had_dirty_work && !graphics_animation_changed {
            return Ok(None);
        }
        let mut last_rows = self.last_rows.lock();
        let mut last_frame_meta = self.last_frame_meta.lock();
        let frame_meta = CachedFrameMeta {
            viewport_rows,
            viewport_cols,
            scrollback_offset: state.scrollback_offset,
            viewport_start_row,
            alt_screen_active,
            default_foreground_rgb: resolve_color_rgb(theme.default_fg, &theme.ansi_palette),
            default_background_rgb: resolve_color_rgb(theme.default_bg, &theme.ansi_palette),
            cursor_color_rgb: resolve_color_rgb(theme.cursor_color, &theme.ansi_palette),
            cursor_guide_color_rgb: resolve_color_rgb(
                theme.cursor_guide_color,
                &theme.ansi_palette,
            ),
            selection_background_rgb: resolve_color_rgb(
                theme.selection_background,
                &theme.ansi_palette,
            ),
            selection_foreground_rgb: theme
                .selection_foreground
                .map(|color| resolve_color_rgb(color, &theme.ansi_palette)),
            link_color_rgb: theme
                .link_color
                .map(|color| resolve_color_rgb(color, &theme.ansi_palette)),
            cursor_text_color_rgb: theme
                .cursor_text_color
                .map(|color| resolve_color_rgb(color, &theme.ansi_palette)),
            tab_color_rgb: theme
                .tab_color
                .map(|color| resolve_color_rgb(color, &theme.ansi_palette)),
            pointer_shape: pointer_shape.clone(),
            ansi_palette: theme.ansi_palette,
            modes: modes.clone(),
            window_title: window_title.clone(),
            window_icon_name: window_icon_name.clone(),
            font_family: font_family.clone(),
        };
        let snapshot_fallback_reason = if display_projection.has_folds() {
            Some("iterm_block_projection".to_string())
        } else {
            snapshot_fallback_reason(
                &pending_frame_work,
                &last_rows,
                last_frame_meta.as_ref(),
                &frame_meta,
            )
        };
        let frame_kind = if snapshot_fallback_reason.is_some() {
            TerminalFrameKind::Snapshot
        } else {
            TerminalFrameKind::Delta
        };
        let viewport_row_shift = if frame_kind == TerminalFrameKind::Delta {
            resolve_viewport_row_shift(
                last_frame_meta.as_ref(),
                viewport_start_row,
                &frame_meta,
                pending_frame_work.scroll_region.as_ref(),
            )
        } else {
            0
        };
        let (rows, hyperlinks, current_rows, dirty_ranges, rows_scanned, rows_emitted) =
            if frame_kind == TerminalFrameKind::Snapshot {
                build_snapshot_frame(&frame_build_context)
            } else {
                build_delta_frame(DeltaFrameContext {
                    build: &frame_build_context,
                    pending_frame_work: &pending_frame_work,
                    previous_rows: &last_rows,
                    viewport_row_shift,
                })
            };
        let (graphics, active_graphics_count, scrollback_graphics_count, asset_snapshots) =
            if self.graphics_enabled {
                let active_graphics_count = terminal.graphics_count();
                let scrollback_graphics_count = terminal.scrollback_graphics_count();
                let asset_snapshots = graphic_asset_snapshots(terminal);
                let placements = build_projected_graphic_placements(
                    terminal,
                    &display_projection,
                    viewport_display_start_row,
                    viewport_rows,
                    scrollback_len,
                    alt_screen_active,
                    pending_frame_work.snapshot_fallback_reason.as_deref() == Some("clear_screen"),
                );
                (
                    placements,
                    active_graphics_count,
                    scrollback_graphics_count,
                    asset_snapshots,
                )
            } else {
                (Vec::new(), 0, 0, Vec::new())
            };
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
        let graphic_placements_count = graphics.len();
        if self.should_defer_kitty_delete_graphics_frame(
            terminal,
            &pending_frame_work,
            graphic_placements_count,
        ) {
            self.pending_frame_signal
                .restore(pending_frame_work, refresh_hint_was_dirty);
            return Ok(None);
        }
        if self.should_defer_clear_graphics_frame(&pending_frame_work, graphic_placements_count) {
            self.pending_frame_signal
                .restore(pending_frame_work, refresh_hint_was_dirty);
            return Ok(None);
        }
        if self.should_defer_inline_clear_frame(&pending_frame_work, &rows, &last_rows) {
            self.pending_frame_signal
                .restore(pending_frame_work, refresh_hint_was_dirty);
            return Ok(None);
        }
        let deferred_kitty_delete_count = terminal.deferred_kitty_delete_count();
        cache_graphic_asset_snapshots(&mut state, asset_snapshots);
        *last_rows = current_rows;
        *last_frame_meta = Some(frame_meta);
        *self.last_frame_debug_stats.lock() = Some(FrameDebugStats {
            rows_scanned,
            rows_emitted,
            frame_build_micros: frame_started_at.elapsed().as_micros() as u64,
            state_lock_wait_micros,
            frame_extract_micros: frame_extract_started_at.elapsed().as_micros() as u64,
            json_encode_micros: 0,
            protobuf_encode_micros: 0,
            full_repaint: frame_kind == TerminalFrameKind::Snapshot,
            snapshot_fallback_reason,
            viewport_row_shift,
            damage_generation: pending_frame_work.damage_generation,
            active_graphics_count,
            scrollback_graphics_count,
            graphic_placements_count,
        });
        *self.last_frame_had_graphics.lock() = graphic_placements_count > 0;
        if graphic_placements_count > 0 {
            *self.deferred_clear_graphics_frame.lock() = None;
            *self.deferred_kitty_delete_graphics_frame.lock() = None;
        }
        if deferred_kitty_delete_count == 0 {
            *self.deferred_kitty_delete_graphics_frame.lock() = None;
        }
        *self.deferred_inline_clear_frame.lock() = None;

        Ok(Some(TerminalFrameDiff {
            frame_schema_version: TERMINAL_FRAME_SCHEMA_VERSION.to_string(),
            frame_kind,
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
            viewport_row_shift,
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
        }))
    }

    pub fn take_frame_packet_v1_protobuf(
        &self,
        after_sequence: Option<u64>,
    ) -> Result<Option<Vec<u8>>, SessionError> {
        let mut next_sequence = self.frame_packet_sequence.lock();
        let sequence = *next_sequence;
        let following_sequence = sequence.checked_add(1).ok_or_else(|| {
            SessionError::Serialize("Frame Packet v1 sequence is exhausted".to_owned())
        })?;
        let acknowledgement_matches = sequence
            .checked_sub(1)
            .is_none_or(|last_emitted| after_sequence == Some(last_emitted));
        if !acknowledgement_matches {
            self.pending_frame_signal
                .mutate(|work| work.mark_full_repaint("frame_packet_sequence_resync"));
        }

        let Some(frame) = self.take_frame_diff()? else {
            return Ok(None);
        };
        let encode_started_at = Instant::now();
        let bytes = frame_diff_proto::encode_frame_packet_v1(
            self.session_id,
            sequence,
            unix_timestamp_micros(),
            &frame,
        )
        .map_err(|error| SessionError::Serialize(error.to_string()))?;
        self.record_frame_protobuf_encode_micros(encode_started_at.elapsed().as_micros() as u64);
        *next_sequence = following_sequence;
        Ok(Some(bytes))
    }

    fn should_defer_clear_graphics_frame(
        &self,
        pending_frame_work: &PendingFrameWork,
        graphic_placements_count: usize,
    ) -> bool {
        if !self.graphics_enabled || graphic_placements_count != 0 {
            return false;
        }
        if pending_frame_work.snapshot_fallback_reason.as_deref() != Some("clear_screen") {
            return false;
        }
        if !*self.last_frame_had_graphics.lock() {
            return false;
        }

        should_defer_frame_with_grace(
            &self.deferred_clear_graphics_frame,
            pending_frame_work.damage_generation,
            INLINE_CLEAR_REPAINT_GRACE,
        )
    }

    fn should_defer_kitty_delete_graphics_frame(
        &self,
        terminal: &Terminal,
        pending_frame_work: &PendingFrameWork,
        graphic_placements_count: usize,
    ) -> bool {
        if !self.graphics_enabled || graphic_placements_count != 0 {
            return false;
        }
        if terminal.deferred_kitty_delete_count() == 0 {
            return false;
        }
        if !*self.last_frame_had_graphics.lock() {
            return false;
        }

        should_defer_frame_with_grace(
            &self.deferred_kitty_delete_graphics_frame,
            pending_frame_work.damage_generation,
            INLINE_CLEAR_REPAINT_GRACE,
        )
    }

    fn should_defer_inline_clear_frame(
        &self,
        pending_frame_work: &PendingFrameWork,
        rows: &[TerminalRow],
        previous_rows: &[CachedRowState],
    ) -> bool {
        if pending_frame_work.full_repaint
            || pending_frame_work.snapshot_fallback_reason.is_some()
            || pending_frame_work.scroll_region.is_some()
            || rows.len() != 1
        {
            return false;
        }

        let row = &rows[0];
        if !row.text.trim().is_empty() {
            return false;
        }
        let Some(previous_row) = previous_rows.get(row.index) else {
            return false;
        };
        if previous_row.text.trim().is_empty() {
            return false;
        }
        let Some(cursor_after) = pending_frame_work.cursor_after.as_ref() else {
            return false;
        };
        if cursor_after.row != row.index || cursor_after.col > 1 {
            return false;
        }

        let mut deferred_frame = self.deferred_inline_clear_frame.lock();
        if let Some(deferred) = deferred_frame
            .as_ref()
            .filter(|deferred| deferred.damage_generation == pending_frame_work.damage_generation)
        {
            if deferred.started_at.elapsed() < INLINE_CLEAR_REPAINT_GRACE {
                return true;
            }
            *deferred_frame = None;
            return false;
        }

        *deferred_frame = Some(DeferredFrameGrace {
            damage_generation: pending_frame_work.damage_generation,
            started_at: Instant::now(),
        });
        true
    }

    pub fn graphic_asset_meta(
        &self,
        asset_id: u64,
        asset_version: u64,
    ) -> Result<GraphicAssetMeta, SessionError> {
        if !self.graphics_enabled {
            return Err(SessionError::GraphicAsset("graphics disabled".to_string()));
        }
        let state = self.state.lock();
        let graphic = find_cached_graphic_asset(&state, asset_id, asset_version)?;
        Ok(GraphicAssetMeta {
            width: graphic.width as u32,
            height: graphic.height as u32,
            rgba_len: graphic.pixels.len(),
            version: graphic.asset_version,
        })
    }

    pub fn graphic_asset_packet_v1_protobuf(
        &self,
        asset_id: u64,
        asset_version: u64,
    ) -> Result<Vec<u8>, SessionError> {
        if !self.graphics_enabled {
            return Err(SessionError::GraphicAsset("graphics disabled".to_string()));
        }
        let state = self.state.lock();
        let graphic = find_cached_graphic_asset(&state, asset_id, asset_version)?;
        let width = u32::try_from(graphic.width)
            .map_err(|_| SessionError::GraphicAsset("width exceeds u32".to_string()))?;
        let height = u32::try_from(graphic.height)
            .map_err(|_| SessionError::GraphicAsset("height exceeds u32".to_string()))?;
        let expected_rgba_len = graphic
            .width
            .checked_mul(graphic.height)
            .and_then(|pixels| pixels.checked_mul(4))
            .ok_or_else(|| SessionError::GraphicAsset("RGBA dimensions overflow".to_string()))?;
        if graphic.pixels.len() != expected_rgba_len {
            return Err(SessionError::GraphicAsset(
                "RGBA length does not match dimensions".to_string(),
            ));
        }
        if graphic.pixels.len() > GRAPHIC_ASSET_PACKET_MAX_RGBA_BYTES {
            return Err(SessionError::GraphicAsset(
                "RGBA exceeds Graphic Asset Packet v1 limit".to_string(),
            ));
        }
        graphic_asset_proto::encode_graphic_asset_packet_v1(
            self.session_id,
            graphic.asset_id,
            graphic.asset_version,
            width,
            height,
            graphic.pixels.as_ref(),
        )
        .map_err(|error| SessionError::Serialize(error.to_string()))
    }

    pub fn copy_graphic_asset_rgba(
        &self,
        asset_id: u64,
        asset_version: u64,
        dst: &mut [u8],
    ) -> Result<usize, SessionError> {
        if !self.graphics_enabled {
            return Err(SessionError::GraphicAsset("graphics disabled".to_string()));
        }
        let state = self.state.lock();
        let graphic = find_cached_graphic_asset(&state, asset_id, asset_version)?;
        let pixels = graphic.pixels.as_ref();
        if dst.len() < pixels.len() {
            return Err(SessionError::GraphicAsset(
                "destination too small".to_string(),
            ));
        }
        dst[..pixels.len()].copy_from_slice(pixels);
        Ok(pixels.len())
    }

    pub fn take_file_download(
        &self,
        download_id: u64,
        dst: &mut [u8],
    ) -> Result<usize, SessionError> {
        self.state.lock().take_file_download(download_id, dst)
    }

    pub fn discard_file_download(&self, download_id: u64) -> Result<(), SessionError> {
        self.state.lock().discard_file_download(download_id)
    }

    fn search(
        &self,
        query: &str,
        mode: TerminalSearchMode,
    ) -> Result<Vec<TerminalSearchMatch>, String> {
        if query.is_empty() {
            return Ok(Vec::new());
        }
        let pattern = TerminalSearchPattern::new(query, mode)?;

        let state = self.state.lock();
        let terminal = &state.terminal;
        let theme = terminal_theme_snapshot(terminal);
        let (_viewport_cols, viewport_rows) = terminal.size();
        let mut rows = Vec::new();
        if terminal.is_alt_screen_active() {
            for row in 0..viewport_rows {
                let extracted = extract_row(
                    terminal.alt_grid().row(row),
                    terminal.alt_grid().is_line_wrapped(row),
                    &theme,
                );
                rows.push(TerminalSearchRow {
                    row,
                    text: extracted.text,
                    wrapped: extracted.wrapped,
                    scrollback_offset: 0,
                });
            }
        } else {
            let grid = terminal.grid();
            let scrollback_len = grid.scrollback_len();
            let total_lines = scrollback_len + viewport_rows;
            let projection = display_projection_for_terminal(terminal);
            let display_max_offset = projection.rows.len().saturating_sub(viewport_rows);

            for visible_index in 0..total_lines {
                let Some(display_index) = projection.display_index_for_source(visible_index) else {
                    continue;
                };
                let extracted = if visible_index < scrollback_len {
                    extract_row(
                        grid.scrollback_line(visible_index),
                        grid.is_scrollback_wrapped(visible_index),
                        &theme,
                    )
                } else {
                    let screen_row = visible_index.saturating_sub(scrollback_len);
                    extract_row(
                        grid.row(screen_row),
                        grid.is_line_wrapped(screen_row),
                        &theme,
                    )
                };
                rows.push(TerminalSearchRow {
                    row: visible_index,
                    text: extracted.text,
                    wrapped: extracted.wrapped,
                    scrollback_offset: display_max_offset.saturating_sub(display_index),
                });
            }
        }

        let mut matches = Vec::new();
        collect_search_matches(&mut matches, rows, &pattern);
        Ok(matches)
    }

    pub fn selection_text(&self, request: TerminalSelectionRequest) -> String {
        let state = self.state.lock();
        selection_text_for_state(&state, request)
    }

    fn observe_child_exit(&self) -> Result<(), SessionError> {
        {
            // The exited bit and pending-exit authority are one publication
            // transition. Refresh hints and competing observers use this same
            // gate, so none can see exited=true with neither pending nor
            // queued exit, and only one observer can consume child status.
            let _publication = self.zmodem_event_publication_gate.lock();
            if !self.exited.load(Ordering::SeqCst) && !self.is_replay {
                let maybe_exit = {
                    let mut child = self.child.lock();
                    child
                        .as_mut()
                        .map(|child| child.try_wait())
                        .transpose()
                        .map_err(|error| SessionError::Io(error.to_string()))?
                        .flatten()
                };

                if let Some(exit) = maybe_exit {
                    let exit_code = i32::try_from(exit.exit_code()).ok();
                    *self.pending_child_exit.lock() = Some(PendingChildExit {
                        exit_code,
                        payload: serde_json::json!({
                            "code": exit.exit_code(),
                            "success": exit.success(),
                            "signal": exit.signal(),
                        }),
                    });
                    self.exited.store(true, Ordering::SeqCst);
                }
            }
        }

        self.publish_pending_child_exit_if_ready();

        Ok(())
    }

    fn publish_pending_child_exit_if_ready(&self) {
        // Child wait may beat the PTY reader. That reader owns final buffered
        // ZMODEM effects and recovery tokens, so `exit` is the last event and
        // cannot make Dart discard the only session authority prematurely.
        let _publication = self.zmodem_event_publication_gate.lock();
        let reader_closed = self.pty_reader_closed.load(Ordering::Acquire);
        let transport_forced = self.zmodem_transport_terminated.load(Ordering::Acquire);
        let zmodem_finalization_pending = self.remembered_zmodem_active().is_some()
            || self.zmodem_draining.load(Ordering::Acquire)
            || (!transport_forced
                && self
                    .zmodem_state_transitions_inflight
                    .load(Ordering::Acquire)
                    != 0)
            || matches!(
                self.zmodem_receive_commit_phase.load(Ordering::Acquire),
                RECEIVE_COMMIT_PUBLISHING | RECEIVE_COMMIT_RESULT_READY
            );
        if self.pty_reader_exit_barrier_enabled.load(Ordering::Acquire)
            && !reader_closed
            && !transport_forced
        {
            return;
        }
        if zmodem_finalization_pending {
            return;
        }
        let Some(pending) = self.pending_child_exit.lock().take() else {
            return;
        };
        // Transition acquisition uses the same gate and will now fail closed,
        // so no protocol event can be published after this final exit event.
        self.zmodem_state_transitions_closed
            .store(true, Ordering::Release);
        self.recording
            .lock()
            .record_session_exited(pending.exit_code);
        self.push_event("exit", Some(pending.payload));
        crate::zmodem::tombstone_recovery_session(self.session_id);
    }

    pub fn poll_events(&self) -> Result<Vec<TerminalEvent>, SessionError> {
        self.publish_pending_ssh_auth_prompts();
        self.observe_child_exit()?;
        let _publication = self.zmodem_event_publication_gate.lock();
        Ok(self.events.lock().drain())
    }

    pub fn poll_event_envelopes(&self) -> Result<Option<RuntimeEventBatchV1>, SessionError> {
        self.publish_pending_ssh_auth_prompts();
        self.observe_child_exit()?;
        let _publication = self.zmodem_event_publication_gate.lock();
        Ok(self.events.lock().drain_event_batch(self.session_id))
    }

    fn publish_pending_ssh_auth_prompts(&self) {
        let Some(auth) = &self.ssh_auth else {
            return;
        };
        for prompt in auth.take_prompts() {
            if let Ok(payload) = serde_json::to_value(prompt) {
                self.push_event("ssh_auth_prompt", Some(payload));
            }
        }
    }

    fn respond_ssh_auth(&self, challenge_id: u64, responses: Vec<String>) -> bool {
        self.ssh_auth
            .as_ref()
            .is_some_and(|auth| auth.respond(challenge_id, responses))
    }

    fn cancel_ssh_auth(&self, challenge_id: u64) -> bool {
        self.ssh_auth
            .as_ref()
            .is_some_and(|auth| auth.cancel(challenge_id))
    }

    pub fn take_frame_debug_stats_json(&self) -> Result<Option<String>, SessionError> {
        self.last_frame_debug_stats
            .lock()
            .take()
            .map(|stats| {
                serde_json::to_string(&stats)
                    .map_err(|error| SessionError::Serialize(error.to_string()))
            })
            .transpose()
    }

    fn record_frame_json_encode_micros(&self, micros: u64) {
        if let Some(stats) = self.last_frame_debug_stats.lock().as_mut() {
            stats.json_encode_micros = micros;
        }
    }

    fn record_frame_protobuf_encode_micros(&self, micros: u64) {
        if let Some(stats) = self.last_frame_debug_stats.lock().as_mut() {
            stats.protobuf_encode_micros = micros;
        }
    }

    pub fn take_session_debug_stats_json(&self) -> Result<Option<String>, SessionError> {
        let stats = self.session_debug_stats_snapshot();
        serde_json::to_string(&stats)
            .map(Some)
            .map_err(|error| SessionError::Serialize(error.to_string()))
    }

    pub fn take_diagnostic_event_v1_json(
        &self,
        name: &str,
    ) -> Result<Option<String>, SessionError> {
        let payload = match name {
            "frame_stats" => self
                .last_frame_debug_stats
                .lock()
                .take()
                .map(serde_json::to_value)
                .transpose()
                .map_err(|error| SessionError::Serialize(error.to_string()))?,
            "session_stats" => Some(
                serde_json::to_value(self.session_debug_stats_snapshot())
                    .map_err(|error| SessionError::Serialize(error.to_string()))?,
            ),
            _ => return Ok(None),
        };
        let Some(payload) = payload else {
            return Ok(None);
        };
        let sequence = {
            let mut next = self.diagnostic_wire_sequence.lock();
            let sequence = *next;
            *next = next.saturating_add(1);
            sequence
        };
        let event = RuntimeEnvelopeV1::diagnostic(
            self.session_id,
            sequence,
            unix_timestamp_micros(),
            name.to_owned(),
            payload,
        );
        serde_json::to_string(&event)
            .map(Some)
            .map_err(|error| SessionError::Serialize(error.to_string()))
    }

    fn session_debug_stats_snapshot(&self) -> SessionDebugStats {
        let mut stats = self.session_debug_stats.lock().clone();
        {
            let state = self.state.lock();
            stats.transcript_bytes = state.transcript.len();
            stats.transcript_truncated = state.transcript_truncated;
            let osc_ingress = state.terminal.osc_ingress_diagnostics();
            stats.osc_ingress_accepted = osc_ingress.accepted_total();
            stats.osc_ingress_oversized = osc_ingress.oversized_total();
            stats.osc_ingress_policy_denied = osc_ingress.policy_denied_total();
            let input_buffers = state.terminal.input_buffer_diagnostics();
            stats.synchronized_update_discards = input_buffers.synchronized_update_limit;
            stats.non_sixel_dcs_discards = input_buffers.non_sixel_dcs_limit;
            stats.response_buffer_overflows = state.terminal.response_buffer_overflow_count();
            stats.vendor_terminal_event_drops = state.terminal.terminal_event_queue_diagnostics().2;
            stats.tmux_notification_drops = state.terminal.tmux_notification_queue_diagnostics().1;
            stats.recording_dropped_events = state.terminal.recording_resource_diagnostics().2;
        }
        {
            let pending = self.pending_frame_signal.snapshot();
            stats.pending_dirty_rows = pending.dirty_rows.len();
            stats.pending_scroll_region =
                pending
                    .scroll_region
                    .as_ref()
                    .map(|scroll_region| SessionDebugScrollRegion {
                        top: scroll_region.top,
                        bottom_exclusive: scroll_region.bottom_exclusive,
                        delta_rows: scroll_region.delta_rows,
                    });
        }
        {
            let pending_events = self.events.lock();
            stats.pending_event_count = pending_events.len();
            stats.pending_event_bytes = pending_events.aggregate_bytes;
            stats.pending_event_dropped_count = pending_events.dropped_count;
            stats.pending_event_overflowed = pending_events.overflow_diagnostic_emitted;
        }
        stats
    }

    fn export_diagnostics_json(
        &self,
        request: TerminalDiagnosticsRequest,
    ) -> Result<String, SessionError> {
        let _ = self.record_resource_sample();
        let max_samples = request.max_samples.min(RESOURCE_SAMPLE_CAPACITY);
        let samples = tail_vec(&self.resource_samples.lock(), max_samples);
        let terminal_stats = self.session_debug_stats_snapshot();
        let frame_stats = self.last_frame_debug_stats.lock().clone();
        let events = tail_vec(&self.diagnostic_events.lock(), MAX_DIAGNOSTIC_EVENTS);
        let summary = diagnostics_summary(
            self.child_pid,
            &samples,
            &terminal_stats,
            frame_stats.as_ref(),
        );

        let manifest = serde_json::json!({
            "schema_version": "terminal-diagnostics-session-v1",
            "generated_at_micros": unix_timestamp_micros(),
            "session_id": self.session_id,
            "child_pid": self.child_pid,
            "process_name": &self.process_name,
            "sample_count": samples.len(),
            "include_content_requested": request.include_content,
            "content_included": false,
            "redaction_mode": request.redaction_mode,
            "platform": std::env::consts::OS,
        });

        serde_json::to_string(&serde_json::json!({
            "manifest": manifest,
            "resource_samples": samples,
            "terminal_stats": {
                "session": terminal_stats,
                "frame": frame_stats,
            },
            "events": events,
            "summary": summary,
        }))
        .map_err(|error| SessionError::Serialize(error.to_string()))
    }

    fn record_input_debug_stats(
        &self,
        bytes_read: usize,
        host_protocol_micros: u64,
        terminal_process_micros: u64,
        terminal_process_breakdown: TerminalProcessDebugStats,
        damage_merge_micros: u64,
        response_write_micros: u64,
    ) {
        let mut stats = self.session_debug_stats.lock();
        stats.bytes_read = stats.bytes_read.saturating_add(bytes_read as u64);
        stats.read_chunks = stats.read_chunks.saturating_add(1);
        stats.host_protocol_micros = stats
            .host_protocol_micros
            .saturating_add(host_protocol_micros);
        stats.terminal_process_micros = stats
            .terminal_process_micros
            .saturating_add(terminal_process_micros);
        stats
            .terminal_process_breakdown
            .add_assign(terminal_process_breakdown);
        stats.damage_merge_micros = stats
            .damage_merge_micros
            .saturating_add(damage_merge_micros);
        stats.response_write_micros = stats
            .response_write_micros
            .saturating_add(response_write_micros);
    }

    fn push_callback_event(&self, event: CallbackEvent) {
        match event {
            CallbackEvent::Resize { rows, cols } => self.push_event(
                "resize",
                Some(serde_json::json!({
                    "rows": rows,
                    "cols": cols,
                })),
            ),
            CallbackEvent::ClipboardCopy { selection, data } => self.push_event(
                "clipboard_copy",
                Some(serde_json::json!({
                    "selection": selection,
                    "data": data,
                })),
            ),
            CallbackEvent::ClipboardPasteRequest { selection } => self.push_event(
                "clipboard_paste_request",
                Some(serde_json::json!({
                    "selection": selection,
                })),
            ),
            CallbackEvent::ItermClipboardCopy {
                selection,
                data,
                streaming,
            } => self.push_event(
                "clipboard_copy",
                Some(serde_json::json!({
                    "selection": selection,
                    "data": data,
                    "protocol": "iterm1337",
                    "mode": if streaming { "stream" } else { "base64" },
                })),
            ),
            CallbackEvent::ClipboardMimeWrite { payload } => {
                self.push_event("clipboard_mime_write", Some(payload))
            }
            CallbackEvent::ClipboardMimeReadRequest { payload } => {
                self.push_event("clipboard_mime_read_request", Some(payload))
            }
            CallbackEvent::ClipboardMimeError { payload } => {
                self.push_event("clipboard_mime_error", Some(payload))
            }
            CallbackEvent::ShellHook { payload } => self.push_event("shell_hook", Some(payload)),
            CallbackEvent::ShellContext { payload } => {
                self.push_event("shell_context", Some(payload))
            }
            CallbackEvent::ShellCommand { payload } => {
                self.push_event("shell_command", Some(payload))
            }
            CallbackEvent::ShellUserVar { name, value } => self.push_event(
                "shell_user_var",
                Some(serde_json::json!({
                    "source": "osc1337_set_user_var",
                    "name": name,
                    "value": value,
                })),
            ),
            CallbackEvent::CellSizeReportRequest => {
                self.push_event("cell_size_report_request", None)
            }
            CallbackEvent::ClearCapturedOutput => self.push_event(
                "clear_captured_output",
                Some(serde_json::json!({
                    "source": "iterm1337",
                })),
            ),
            CallbackEvent::ReportVariableRequest { payload } => {
                self.push_event("report_variable_request", Some(payload))
            }
            CallbackEvent::OpenUrlRequest { payload } => {
                self.push_event("open_url_request", Some(payload))
            }
            CallbackEvent::AttentionRequest { payload } => {
                self.push_event("attention_request", Some(payload))
            }
            CallbackEvent::SessionAnnotation { payload } => {
                self.push_event("session_annotation", Some(payload))
            }
            CallbackEvent::SessionNotification {
                source,
                action,
                identifier,
                title,
                message,
                application_name,
                notification_types,
                expires_after_ms,
                report_activation,
                report_close,
                buttons,
            } => self.push_event(
                "session_notification",
                Some(serde_json::json!({
                    "source": source,
                    "action": action,
                    "id": identifier,
                    "title": title,
                    "message": message,
                    "application": application_name,
                    "types": notification_types,
                    "expiresAfterMs": expires_after_ms,
                    "reportActivation": report_activation,
                    "reportClose": report_close,
                    "buttons": buttons,
                })),
            ),
            CallbackEvent::SessionProgress { payload } => {
                self.push_event("session_progress", Some(payload))
            }
            CallbackEvent::SessionBadge { text } => self.push_event(
                "session_badge",
                Some(serde_json::json!({
                    "source": "osc1337_set_badge_format",
                    "text": text,
                })),
            ),
            CallbackEvent::SessionTabStatus { payload } => {
                self.push_event("session_tab_status", Some(payload))
            }
            CallbackEvent::TerminalContext { payload } => {
                self.push_event("terminal_context", Some(payload))
            }
            CallbackEvent::DragDropCommand { payload } => {
                self.push_event("drag_drop_command", Some(payload))
            }
            CallbackEvent::FileDownload { payload } => {
                self.push_event("file_download", Some(payload))
            }
            CallbackEvent::FileDownloadFailed { payload } => {
                self.push_event("file_download_failed", Some(payload))
            }
            CallbackEvent::FileUploadDenied { payload } => {
                self.push_event("file_upload_denied", Some(payload))
            }
            CallbackEvent::SessionReset => self.push_event("session_reset", None),
            CallbackEvent::Bell => self.push_event("bell", None),
        }
    }

    fn push_event(&self, kind: &str, payload: Option<serde_json::Value>) {
        if matches!(
            kind,
            "zmodem_completed" | "zmodem_failed" | "zmodem_cancelled"
        ) && let Some(transfer_id) = payload
            .as_ref()
            .and_then(|value| value.get("transferId"))
            .and_then(|value| {
                value
                    .as_u64()
                    .or_else(|| value.as_str().and_then(|raw| raw.parse().ok()))
            })
        {
            let mut recent = self.zmodem_terminal_event_ids.lock();
            if recent.contains(&transfer_id) {
                return;
            }
            recent.push_back(transfer_id);
            while recent.len() > MAX_RECENT_ZMODEM_TERMINAL_IDS {
                recent.pop_front();
            }
        }
        let diagnostic_payload = sanitize_diagnostic_event_payload(kind, payload.as_ref());
        let result = self.events.lock().push(TerminalEvent {
            kind: kind.to_string(),
            session_id: self.session_id,
            payload,
        });
        self.push_diagnostic_event(TerminalDiagnosticEvent {
            timestamp_micros: unix_timestamp_micros(),
            session_id: self.session_id,
            kind: kind.to_string(),
            payload: diagnostic_payload,
        });
        if result.emit_overflow_diagnostic {
            self.push_diagnostic_event(event_queue_overflow_diagnostic(self.session_id));
        }
    }

    fn push_diagnostic_event(&self, event: TerminalDiagnosticEvent) {
        let mut events = self.diagnostic_events.lock();
        events.push_back(event);
        while events.len() > MAX_DIAGNOSTIC_EVENTS {
            let index = events
                .iter()
                .position(|event| event.kind != EVENT_QUEUE_OVERFLOW_DIAGNOSTIC_KIND)
                .unwrap_or(0);
            let _ = events.remove(index);
        }
    }
}

fn event_queue_overflow_diagnostic(session_id: u64) -> TerminalDiagnosticEvent {
    TerminalDiagnosticEvent {
        timestamp_micros: unix_timestamp_micros(),
        session_id,
        kind: EVENT_QUEUE_OVERFLOW_DIAGNOSTIC_KIND.to_string(),
        payload: None,
    }
}

struct ExtractedRow {
    text: String,
    wrapped: bool,
    style_runs: Vec<TerminalStyleRun>,
}

struct ExtractedVisibleRow {
    row: TerminalRow,
    continues_from_previous: bool,
    hyperlinks: Vec<TerminalHyperlinkRange>,
}

fn terminal_cursor_snapshot(
    terminal: &Terminal,
    cursor: &par_term_emu_core_rust::cursor::Cursor,
) -> TerminalCursor {
    TerminalCursor {
        row: cursor.row,
        col: cursor.col,
        visible: cursor.visible,
        highlight_line: terminal.use_cursor_guide(),
        shape: cursor.shape_override().map(|shape| match shape {
            par_term_emu_core_rust::cursor::CursorShape::Block => TerminalCursorShape::Block,
            par_term_emu_core_rust::cursor::CursorShape::Underline => {
                TerminalCursorShape::Underline
            }
            par_term_emu_core_rust::cursor::CursorShape::Bar => TerminalCursorShape::Beam,
        }),
        blink: cursor.blink_override(),
    }
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

fn append_transcript(state: &mut TerminalState, bytes: &[u8]) {
    state.transcript.extend_from_slice(bytes);
    if state.transcript.len() <= MAX_TRANSCRIPT_BYTES {
        return;
    }

    let overflow = state.transcript.len() - MAX_TRANSCRIPT_BYTES;
    state.transcript.drain(..overflow);
    state.transcript_truncated = true;
}

fn unix_timestamp_micros() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_micros().min(u128::from(u64::MAX)) as u64)
        .unwrap_or(0)
}

fn apply_terminal_pixel_metrics(
    terminal: &mut Terminal,
    cols: u16,
    rows: u16,
    pixel_width: u16,
    pixel_height: u16,
    cell_width: u16,
    cell_height: u16,
) {
    if pixel_width > 0 && pixel_height > 0 {
        terminal.set_pixel_size(pixel_width as usize, pixel_height as usize);
    }

    let resolved_cell_width = if cell_width > 0 {
        Some(cell_width as usize)
    } else if pixel_width > 0 {
        Some((pixel_width as usize / usize::from(cols.max(1))).max(1))
    } else {
        None
    };
    let resolved_cell_height = if cell_height > 0 {
        Some(cell_height as usize)
    } else if pixel_height > 0 {
        Some((pixel_height as usize / usize::from(rows.max(1))).max(1))
    } else {
        None
    };
    if let (Some(cell_width), Some(cell_height)) = (resolved_cell_width, resolved_cell_height) {
        terminal.set_cell_dimensions(
            cell_width.min(u32::MAX as usize) as u32,
            cell_height.min(u32::MAX as usize) as u32,
        );
    }
}

fn process_name_for_profile(profile: &TerminalProfile) -> String {
    executable_basename(&profile.launch.program)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "shell".to_string())
}

fn executable_basename(value: &str) -> Option<String> {
    value
        .rsplit(['/', '\\'])
        .next()
        .filter(|part| !part.is_empty())
        .map(str::to_string)
}

fn diagnostic_hash(value: &str) -> String {
    let mut hasher = DefaultHasher::new();
    "ianvs terminal-terminal-diagnostics-v1".hash(&mut hasher);
    value.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

fn command_diagnostic_summary(value: &str) -> serde_json::Value {
    let parts = value.split_whitespace().collect::<Vec<_>>();
    let executable = parts
        .first()
        .and_then(|value| executable_basename(value))
        .unwrap_or_default();
    serde_json::json!({
        "executable_basename": executable,
        "arg_count": parts.len().saturating_sub(1),
        "hash": diagnostic_hash(value),
    })
}

fn cwd_diagnostic_summary(value: &str) -> serde_json::Value {
    let path_class = if value.starts_with("/Users/") || value == "~" || value.starts_with("~/") {
        "home"
    } else if value.starts_with("/tmp/") || value.starts_with("/var/folders/") {
        "temporary"
    } else if value.starts_with('/') {
        "absolute"
    } else if value.is_empty() {
        "empty"
    } else {
        "relative_or_other"
    };
    let depth = value
        .split('/')
        .filter(|component| !component.is_empty() && *component != ".")
        .count();
    serde_json::json!({
        "path_class": path_class,
        "depth": depth,
        "hash": diagnostic_hash(value),
    })
}

fn sanitize_diagnostic_event_payload(
    kind: &str,
    payload: Option<&serde_json::Value>,
) -> Option<serde_json::Value> {
    let payload = payload?;
    match kind {
        "resize" => Some(serde_json::json!({
            "rows": payload.get("rows").and_then(serde_json::Value::as_u64),
            "cols": payload.get("cols").and_then(serde_json::Value::as_u64),
        })),
        "exit" => Some(serde_json::json!({
            "code": payload.get("code").and_then(serde_json::Value::as_i64),
            "success": payload.get("success").and_then(serde_json::Value::as_bool),
            "signal": payload.get("signal").and_then(serde_json::Value::as_i64),
        })),
        "clipboard_copy" => Some(serde_json::json!({
            "selection": payload.get("selection").and_then(serde_json::Value::as_str),
            "protocol": payload.get("protocol").and_then(serde_json::Value::as_str),
            "mode": payload.get("mode").and_then(serde_json::Value::as_str),
            "data_bytes": payload
                .get("data")
                .and_then(serde_json::Value::as_str)
                .map(str::len),
        })),
        "clipboard_paste_request" => Some(serde_json::json!({
            "selection": payload.get("selection").and_then(serde_json::Value::as_str),
        })),
        "session_annotation" => Some(serde_json::json!({
            "source": payload.get("source").and_then(serde_json::Value::as_str),
            "visible": payload.get("visible").and_then(serde_json::Value::as_bool),
            "message_chars": payload
                .get("message")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
            "selected_text_chars": payload
                .get("selectedText")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
            "start_abs_row": payload.get("startAbsRow").and_then(serde_json::Value::as_u64),
            "start_col": payload.get("startCol").and_then(serde_json::Value::as_u64),
            "end_abs_row": payload.get("endAbsRow").and_then(serde_json::Value::as_u64),
            "end_col": payload.get("endCol").and_then(serde_json::Value::as_u64),
        })),
        "clipboard_mime_write" => Some(serde_json::json!({
            "protocol": "osc5522",
            "location": payload.get("location").and_then(serde_json::Value::as_str),
            "item_count": payload.get("items").and_then(serde_json::Value::as_array).map(Vec::len),
            "encoded_bytes": payload
                .get("items")
                .and_then(serde_json::Value::as_array)
                .map(|items| items.iter().filter_map(|item| item.get("data").and_then(serde_json::Value::as_str)).map(str::len).sum::<usize>()),
        })),
        "clipboard_mime_read_request" | "clipboard_mime_error" => Some(serde_json::json!({
            "protocol": "osc5522",
            "operation": payload.get("operation").and_then(serde_json::Value::as_str),
            "status": payload.get("status").and_then(serde_json::Value::as_str),
            "location": payload.get("location").and_then(serde_json::Value::as_str),
            "mime_count": payload.get("mimeTypes").and_then(serde_json::Value::as_array).map(Vec::len),
            "list_only": payload.get("listOnly").and_then(serde_json::Value::as_bool),
        })),
        "cell_size_report_request" => Some(serde_json::json!({})),
        "report_variable_request" => Some(serde_json::json!({
            "source": payload.get("source").and_then(serde_json::Value::as_str),
            "name": payload
                .get("name")
                .and_then(serde_json::Value::as_str)
                .map(|name| sanitize_protocol_text(name, 256)),
            "name_chars": payload
                .get("name")
                .and_then(serde_json::Value::as_str)
                .map(|name| name.chars().count()),
            "defined": payload.get("value").is_some_and(|value| !value.is_null()),
            "value_chars": payload
                .get("value")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
        })),
        "open_url_request" => Some(serde_json::json!({
            "source": payload.get("source").and_then(serde_json::Value::as_str),
            "scheme": payload
                .get("url")
                .and_then(serde_json::Value::as_str)
                .and_then(|value| url::Url::parse(value).ok())
                .map(|value| value.scheme().to_string()),
            "url_chars": payload
                .get("url")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
            "url_hash": payload
                .get("url")
                .and_then(serde_json::Value::as_str)
                .map(diagnostic_hash),
        })),
        "attention_request" => Some(serde_json::json!({
            "source": payload.get("source").and_then(serde_json::Value::as_str),
            "action": payload.get("action").and_then(serde_json::Value::as_str),
        })),
        "shell_hook" => sanitize_shell_hook_payload(payload),
        "shell_context" => sanitize_shell_context_payload(payload),
        "shell_command" => sanitize_shell_command_payload(payload),
        "shell_user_var" => Some(serde_json::json!({
            "source": payload.get("source").and_then(serde_json::Value::as_str),
            "name": payload.get("name").and_then(serde_json::Value::as_str),
            "value_chars": payload
                .get("value")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
            "value_hash": payload
                .get("value")
                .and_then(serde_json::Value::as_str)
                .map(diagnostic_hash),
        })),
        "session_notification" => Some(serde_json::json!({
            "source": payload.get("source").and_then(serde_json::Value::as_str),
            "action": payload.get("action").and_then(serde_json::Value::as_str),
            "id_chars": payload
                .get("id")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
            "id_hash": payload
                .get("id")
                .and_then(serde_json::Value::as_str)
                .map(diagnostic_hash),
            "title_chars": payload
                .get("title")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
            "title_hash": payload
                .get("title")
                .and_then(serde_json::Value::as_str)
                .map(diagnostic_hash),
            "message_chars": payload
                .get("message")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
            "message_hash": payload
                .get("message")
                .and_then(serde_json::Value::as_str)
                .map(diagnostic_hash),
            "application_chars": payload
                .get("application")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
            "application_hash": payload
                .get("application")
                .and_then(serde_json::Value::as_str)
                .map(diagnostic_hash),
            "type_count": payload
                .get("types")
                .and_then(serde_json::Value::as_array)
                .map(Vec::len),
            "expires_after_ms": payload
                .get("expiresAfterMs")
                .and_then(serde_json::Value::as_u64),
            "report_activation": payload
                .get("reportActivation")
                .and_then(serde_json::Value::as_bool),
            "report_close": payload
                .get("reportClose")
                .and_then(serde_json::Value::as_bool),
            "button_count": payload
                .get("buttons")
                .and_then(serde_json::Value::as_array)
                .map(Vec::len),
        })),
        "session_progress" => Some(serde_json::json!({
            "source": payload.get("source").and_then(serde_json::Value::as_str),
            "named": payload.get("named").and_then(serde_json::Value::as_bool),
            "action": payload.get("action").and_then(serde_json::Value::as_str),
            "state": payload.get("state").and_then(serde_json::Value::as_str),
            "percent": payload.get("percent").and_then(serde_json::Value::as_u64),
            "id_chars": payload
                .get("id")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
            "id_hash": payload
                .get("id")
                .and_then(serde_json::Value::as_str)
                .map(diagnostic_hash),
            "label_hash": payload
                .get("label")
                .and_then(serde_json::Value::as_str)
                .map(diagnostic_hash),
        })),
        "session_badge" => Some(serde_json::json!({
            "source": payload.get("source").and_then(serde_json::Value::as_str),
            "text_chars": payload
                .get("text")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
            "text_hash": payload
                .get("text")
                .and_then(serde_json::Value::as_str)
                .map(diagnostic_hash),
        })),
        "session_tab_status" => Some(serde_json::json!({
            "source": payload.get("source").and_then(serde_json::Value::as_str),
            "indicator_present": payload
                .get("indicatorPresent")
                .and_then(serde_json::Value::as_bool),
            "indicator": payload.get("indicator").and_then(serde_json::Value::as_str),
            "status_present": payload
                .get("statusPresent")
                .and_then(serde_json::Value::as_bool),
            "status_chars": payload
                .get("status")
                .and_then(serde_json::Value::as_str)
                .map(|value| value.chars().count()),
            "status_hash": payload
                .get("status")
                .and_then(serde_json::Value::as_str)
                .map(diagnostic_hash),
            "status_color_present": payload
                .get("statusColorPresent")
                .and_then(serde_json::Value::as_bool),
            "status_color": payload
                .get("statusColor")
                .and_then(serde_json::Value::as_str),
        })),
        "terminal_context" => Some(sanitize_terminal_context_payload(payload)),
        ZMODEM_DEFERRED_WRITE_FAILED_KIND => Some(serde_json::json!({
            "source": "zmodem",
            "reason": payload.get("reason").and_then(serde_json::Value::as_str),
            "queued_chunks": payload.get("queuedChunks").and_then(serde_json::Value::as_u64),
            "queued_bytes": payload.get("queuedBytes").and_then(serde_json::Value::as_u64),
            "completed_chunks": payload
                .get("completedChunks")
                .and_then(serde_json::Value::as_u64),
            "completed_bytes": payload
                .get("completedBytes")
                .and_then(serde_json::Value::as_u64),
            "unconfirmed_chunks": payload
                .get("unconfirmedChunks")
                .and_then(serde_json::Value::as_u64),
            "unconfirmed_bytes": payload
                .get("unconfirmedBytes")
                .and_then(serde_json::Value::as_u64),
        })),
        "zmodem_detected"
        | "zmodem_file_offer"
        | "zmodem_started"
        | "zmodem_progress"
        | "zmodem_file_completed"
        | "zmodem_file_skipped"
        | "zmodem_completed"
        | "zmodem_failed"
        | "zmodem_cancelled" => Some(serde_json::json!({
            "source": "zmodem",
            "transfer_id": payload.get("transferId").and_then(serde_json::Value::as_str),
            "direction": payload.get("direction").and_then(serde_json::Value::as_str),
            "size": payload.get("size").and_then(serde_json::Value::as_u64),
            "bytes_transferred": payload
                .get("bytesTransferred")
                .and_then(serde_json::Value::as_u64),
            "total_bytes": payload.get("totalBytes").and_then(serde_json::Value::as_u64),
            "file_count": payload.get("fileCount").and_then(serde_json::Value::as_u64),
            "completed_files": payload
                .get("completedFiles")
                .and_then(serde_json::Value::as_u64),
            "skipped_files": payload
                .get("skippedFiles")
                .and_then(serde_json::Value::as_u64),
            "reason": payload.get("reason").and_then(serde_json::Value::as_str),
        })),
        _ => None,
    }
}

fn sanitize_terminal_context_payload(payload: &serde_json::Value) -> serde_json::Value {
    let string_summary = |key: &str| {
        payload
            .get(key)
            .and_then(serde_json::Value::as_str)
            .map(|value| {
                serde_json::json!({
                    "chars": value.chars().count(),
                    "hash": diagnostic_hash(value),
                })
            })
    };
    serde_json::json!({
        "source": payload.get("source").and_then(serde_json::Value::as_str),
        "action": payload.get("action").and_then(serde_json::Value::as_str),
        "depth": payload.get("depth").and_then(serde_json::Value::as_u64),
        "active": payload.get("active").and_then(serde_json::Value::as_bool),
        "type": payload.get("type").and_then(serde_json::Value::as_str),
        "pid": payload.get("pid").and_then(serde_json::Value::as_u64),
        "pidfd_id": payload.get("pidfdId").and_then(serde_json::Value::as_u64),
        "status": payload.get("status").and_then(serde_json::Value::as_u64),
        "exit": payload.get("exit").and_then(serde_json::Value::as_str),
        "implicit_closed_count": payload
            .get("implicitClosedCount")
            .and_then(serde_json::Value::as_u64),
        "id": string_summary("id"),
        "user": string_summary("user"),
        "hostname": string_summary("hostname"),
        "machine_id": string_summary("machineId"),
        "boot_id": string_summary("bootId"),
        "command_name": string_summary("commandName"),
        "cwd": string_summary("cwd"),
        "command_line": string_summary("commandLine"),
        "vm": string_summary("vm"),
        "container": string_summary("container"),
        "target_user": string_summary("targetUser"),
        "target_host": string_summary("targetHost"),
        "context_session_id": string_summary("contextSessionId"),
        "signal": string_summary("signal"),
    })
}

fn sanitize_shell_context_payload(payload: &serde_json::Value) -> Option<serde_json::Value> {
    let object = payload.as_object()?;
    let mut sanitized = serde_json::Map::new();
    if let Some(source) = object.get("source").and_then(serde_json::Value::as_str) {
        sanitized.insert(
            "source".to_string(),
            serde_json::Value::String(source.to_string()),
        );
    }
    if let Some(cwd) = object.get("cwd").and_then(serde_json::Value::as_str) {
        sanitized.insert("cwd".to_string(), cwd_diagnostic_summary(cwd));
    }
    if let Some(username) = object.get("username").and_then(serde_json::Value::as_str) {
        sanitized.insert(
            "username_hash".to_string(),
            serde_json::Value::String(diagnostic_hash(username)),
        );
    }
    if let Some(hostname) = object.get("hostname").and_then(serde_json::Value::as_str) {
        sanitized.insert(
            "hostname_hash".to_string(),
            serde_json::Value::String(diagnostic_hash(hostname)),
        );
    }
    Some(serde_json::Value::Object(sanitized))
}

fn sanitize_shell_command_payload(payload: &serde_json::Value) -> Option<serde_json::Value> {
    let object = payload.as_object()?;
    let mut sanitized = serde_json::Map::new();
    for key in [
        "source",
        "eventType",
        "zoneType",
        "zoneId",
        "absRowStart",
        "absRowEnd",
        "cursorLine",
        "timestamp",
        "exitCode",
    ] {
        if let Some(value) = object.get(key) {
            sanitized.insert(key.to_string(), value.clone());
        }
    }
    if let Some(command) = object.get("command").and_then(serde_json::Value::as_str) {
        sanitized.insert("command".to_string(), command_diagnostic_summary(command));
    }
    Some(serde_json::Value::Object(sanitized))
}

fn sanitize_shell_hook_payload(payload: &serde_json::Value) -> Option<serde_json::Value> {
    let object = payload.as_object()?;
    let mut sanitized = serde_json::Map::new();
    if let Some(hook) = object.get("hook").and_then(serde_json::Value::as_str) {
        sanitized.insert(
            "hook".to_string(),
            serde_json::Value::String(hook.to_string()),
        );
    }
    if let Some(command) = object.get("command").and_then(serde_json::Value::as_str) {
        sanitized.insert("command".to_string(), command_diagnostic_summary(command));
    }
    if let Some(cwd) = object
        .get("cwd")
        .or_else(|| object.get("pwd"))
        .and_then(serde_json::Value::as_str)
    {
        sanitized.insert("cwd".to_string(), cwd_diagnostic_summary(cwd));
    }
    if let Some(shell) = object.get("shell").and_then(serde_json::Value::as_str) {
        sanitized.insert(
            "shell_basename".to_string(),
            serde_json::Value::String(executable_basename(shell).unwrap_or_default()),
        );
    }
    if let Some(username) = object
        .get("username")
        .or_else(|| object.get("user"))
        .and_then(serde_json::Value::as_str)
    {
        sanitized.insert(
            "username_hash".to_string(),
            serde_json::Value::String(diagnostic_hash(username)),
        );
    }
    if let Some(hostname) = object
        .get("hostname")
        .or_else(|| object.get("host"))
        .and_then(serde_json::Value::as_str)
    {
        sanitized.insert(
            "hostname_hash".to_string(),
            serde_json::Value::String(diagnostic_hash(hostname)),
        );
    }
    if let Some(exit_code) = object
        .get("exitCode")
        .or_else(|| object.get("exit_code"))
        .and_then(serde_json::Value::as_i64)
    {
        sanitized.insert("exit_code".to_string(), serde_json::Value::from(exit_code));
    }
    if let Some(prompt_offset) = object
        .get("promptScrollbackOffset")
        .or_else(|| object.get("prompt_scrollback_offset"))
        .or_else(|| object.get("scrollback_offset"))
        .and_then(serde_json::Value::as_i64)
    {
        sanitized.insert(
            "prompt_scrollback_offset".to_string(),
            serde_json::Value::from(prompt_offset),
        );
    }
    Some(serde_json::Value::Object(sanitized))
}

fn tail_vec<T: Clone>(values: &VecDeque<T>, max_entries: usize) -> Vec<T> {
    let skip = values.len().saturating_sub(max_entries);
    values.iter().skip(skip).cloned().collect()
}

#[cfg(target_os = "macos")]
fn sample_process_resource(pid: u32) -> Result<ProcessResourceSnapshot, String> {
    let mut info: libc::proc_taskinfo = unsafe { std::mem::zeroed() };
    let expected = std::mem::size_of::<libc::proc_taskinfo>() as libc::c_int;
    let result = unsafe {
        libc::proc_pidinfo(
            pid as libc::c_int,
            libc::PROC_PIDTASKINFO,
            0,
            &mut info as *mut _ as *mut libc::c_void,
            expected,
        )
    };
    if result != expected {
        return Err("process_resource_unavailable".to_string());
    }
    Ok(ProcessResourceSnapshot {
        rss_bytes: info.pti_resident_size,
        virtual_bytes: info.pti_virtual_size,
        total_user_micros: info.pti_total_user / 1_000,
        total_system_micros: info.pti_total_system / 1_000,
        thread_count: info.pti_threadnum,
    })
}

#[cfg(not(target_os = "macos"))]
fn sample_process_resource(_pid: u32) -> Result<ProcessResourceSnapshot, String> {
    Err("resource_sampling_unsupported".to_string())
}

fn diagnostics_summary(
    child_pid: Option<u32>,
    samples: &[ResourceSample],
    terminal_stats: &SessionDebugStats,
    frame_stats: Option<&FrameDebugStats>,
) -> TerminalDiagnosticsSummary {
    let sample_count = samples
        .iter()
        .filter(|sample| sample.sample_error.is_none())
        .count();
    let max_cpu = samples
        .iter()
        .filter_map(|sample| sample.cpu_percent)
        .fold(0.0_f64, f64::max);
    let max_rss = samples
        .iter()
        .filter_map(|sample| sample.rss_bytes)
        .max()
        .unwrap_or(0);
    let parser_micros = terminal_stats.terminal_process_micros;
    let parser_breakdown = &terminal_stats.terminal_process_breakdown;
    let scroll_micros = parser_breakdown
        .scroll_micros
        .saturating_add(parser_breakdown.scrollback_push_micros);
    let frame_build_micros = frame_stats
        .map(|stats| stats.frame_build_micros)
        .unwrap_or_default();
    let json_encode_micros = frame_stats
        .map(|stats| stats.json_encode_micros)
        .unwrap_or_default();
    let rows_scanned = frame_stats
        .map(|stats| stats.rows_scanned)
        .unwrap_or_default();

    let mut user_command = 0.0_f64;
    if max_cpu >= 50.0 {
        user_command += 0.7;
    } else if max_cpu >= 20.0 {
        user_command += 0.4;
    }
    if max_rss >= 512 * 1024 * 1024 {
        user_command += 0.5;
    } else if max_rss >= 128 * 1024 * 1024 {
        user_command += 0.25;
    }

    let mut native_parser_pty = 0.0_f64;
    if parser_micros >= 50_000 {
        native_parser_pty += 0.6;
    } else if parser_micros >= 10_000 {
        native_parser_pty += 0.3;
    }
    if parser_breakdown.escape_or_control_bytes >= 4096 {
        native_parser_pty += 0.25;
    }
    if scroll_micros >= 10_000 || parser_breakdown.scrollback_push_lines >= 1000 {
        native_parser_pty += 0.35;
    }

    let mut flutter_ui_render = 0.0_f64;
    if frame_build_micros >= 16_000 {
        flutter_ui_render += 0.45;
    }
    if json_encode_micros >= 8_000 {
        flutter_ui_render += 0.35;
    }
    if rows_scanned >= 500 {
        flutter_ui_render += 0.25;
    }

    let insufficient_evidence = if child_pid.is_none() || sample_count < 2 {
        1.0
    } else if terminal_stats.transcript_truncated {
        0.55
    } else {
        0.0
    };

    let user_command = user_command.min(1.0);
    let native_parser_pty = native_parser_pty.min(1.0);
    let flutter_ui_render = flutter_ui_render.min(1.0);
    let active_scores = [
        user_command >= 0.5,
        native_parser_pty >= 0.5,
        flutter_ui_render >= 0.5,
    ]
    .iter()
    .filter(|active| **active)
    .count();
    let conclusion = if insufficient_evidence >= 1.0 && active_scores == 0 {
        "insufficient-evidence"
    } else if active_scores >= 2 {
        "mixed"
    } else if user_command >= native_parser_pty
        && user_command >= flutter_ui_render
        && user_command >= 0.5
    {
        "user-command"
    } else if native_parser_pty >= flutter_ui_render && native_parser_pty >= 0.5 {
        "native-parser-pty"
    } else if flutter_ui_render >= 0.5 {
        "flutter-ui-render"
    } else {
        "insufficient-evidence"
    }
    .to_string();

    let evidence = vec![
        format!("valid_resource_samples={sample_count}, max_child_cpu={max_cpu:.1}%"),
        format!("max_child_rss_bytes={max_rss}"),
        format!(
            "terminal_process_micros={}, escape_or_control_bytes={}, scroll_micros={}",
            parser_micros, parser_breakdown.escape_or_control_bytes, scroll_micros
        ),
        format!(
            "frame_build_micros={}, json_encode_micros={}, rows_scanned={}",
            frame_build_micros, json_encode_micros, rows_scanned
        ),
    ];
    let privacy = vec![
        "scrollback, env, raw command line, raw cwd, username, and hostname are excluded by default"
            .to_string(),
        "shell hook command/cwd/user/host fields are summarized or salted-hashed".to_string(),
    ];
    let next_steps = match conclusion.as_str() {
        "user-command" => vec![
            "inspect the direct child command workload and consider process-tree aggregation in V2"
                .to_string(),
        ],
        "native-parser-pty" => vec![
            "capture a short high-output reproduction and inspect parser, scroll, and scrollback costs"
                .to_string(),
        ],
        "flutter-ui-render" => vec![
            "profile frame build, JSON encode, row rebuild, and paint paths around the sampled period"
                .to_string(),
        ],
        "mixed" => vec![
            "separate command CPU/RSS load from terminal parser and Flutter frame costs with targeted repros"
                .to_string(),
        ],
        _ => vec![
            "reproduce while the session is active for at least two samples and export again".to_string(),
        ],
    };
    let scores = TerminalDiagnosticsScores {
        user_command,
        native_parser_pty,
        flutter_ui_render,
        insufficient_evidence,
    };
    let markdown = diagnostics_markdown(&conclusion, &evidence, &scores, &privacy, &next_steps);

    TerminalDiagnosticsSummary {
        conclusion,
        attribution_scores: scores,
        evidence,
        privacy,
        next_steps,
        markdown,
    }
}

fn diagnostics_markdown(
    conclusion: &str,
    evidence: &[String],
    scores: &TerminalDiagnosticsScores,
    privacy: &[String],
    next_steps: &[String],
) -> String {
    let mut markdown = String::new();
    markdown.push_str("# Terminal diagnostics\n\n");
    markdown.push_str("## Conclusion\n\n");
    markdown.push_str(conclusion);
    markdown.push_str("\n\n## Evidence summary\n\n");
    for item in evidence {
        markdown.push_str("- ");
        markdown.push_str(item);
        markdown.push('\n');
    }
    markdown.push_str("\n## Attribution scores\n\n");
    markdown.push_str(&format!("- user-command: {:.2}\n", scores.user_command));
    markdown.push_str(&format!(
        "- native-parser-pty: {:.2}\n",
        scores.native_parser_pty
    ));
    markdown.push_str(&format!(
        "- flutter-ui-render: {:.2}\n",
        scores.flutter_ui_render
    ));
    markdown.push_str(&format!(
        "- insufficient-evidence: {:.2}\n",
        scores.insufficient_evidence
    ));
    markdown.push_str("\n## Privacy handling\n\n");
    for item in privacy {
        markdown.push_str("- ");
        markdown.push_str(item);
        markdown.push('\n');
    }
    markdown.push_str("\n## Suggested next steps\n\n");
    for item in next_steps {
        markdown.push_str("- ");
        markdown.push_str(item);
        markdown.push('\n');
    }
    markdown
}

fn cached_row_state_for(entry: &ExtractedVisibleRow) -> CachedRowState {
    CachedRowState {
        text: entry.row.text.clone(),
        wrapped: entry.row.wrapped,
        continues_from_previous: entry.continues_from_previous,
        style_signature: style_signature(&entry.row.style_runs),
        hyperlink_signature: hyperlink_signature(&entry.hyperlinks),
    }
}

fn extract_viewport_row(
    terminal: &Terminal,
    emulation: TerminalEmulation,
    viewport_start_row: usize,
    viewport_row: usize,
) -> ExtractedVisibleRow {
    let mut extracted = extract_source_row(
        terminal,
        emulation,
        viewport_start_row.saturating_add(viewport_row),
        viewport_row,
    );
    // Contiguous frames retain the legacy compact representation. Explicit
    // source bounds are emitted only by the non-contiguous fold projection.
    extracted.row.source_row = None;
    extracted.row.source_end_row = None;
    extracted
}

fn extract_source_row(
    terminal: &Terminal,
    emulation: TerminalEmulation,
    source_row: usize,
    viewport_row: usize,
) -> ExtractedVisibleRow {
    let theme = terminal_theme_snapshot(terminal);
    let (cells, wrapped) = row_cells_for_visible_index(terminal, source_row);
    let continues_from_previous =
        source_row > 0 && row_cells_for_visible_index(terminal, source_row - 1).1;
    let extracted = extract_row(cells, wrapped, &theme);
    let hyperlinks = if emulation == TerminalEmulation::Xterm256 {
        extract_hyperlinks_for_row(terminal, cells, viewport_row)
    } else {
        Vec::new()
    };

    ExtractedVisibleRow {
        row: TerminalRow {
            index: viewport_row,
            text: extracted.text,
            wrapped: extracted.wrapped,
            style_runs: extracted.style_runs,
            source_row: Some(source_row),
            source_end_row: Some(source_row),
        },
        continues_from_previous,
        hyperlinks,
    }
}

fn build_terminal_blocks(
    terminal: &Terminal,
    projection: &DisplayProjection,
    display_start_row: usize,
    viewport_rows: usize,
) -> Vec<TerminalBlock> {
    if terminal.is_alt_screen_active() || viewport_rows == 0 {
        return Vec::new();
    }
    let grid = terminal.grid();
    let scrollback_len = grid.scrollback_len();
    let total_rows = scrollback_len.saturating_add(grid.rows());
    if total_rows == 0 {
        return Vec::new();
    }
    let first_retained_abs_row = grid.total_lines_scrolled().saturating_sub(scrollback_len);
    let last_retained_abs_row = first_retained_abs_row.saturating_add(total_rows - 1);
    let display_end_row = display_start_row.saturating_add(viewport_rows);
    let mut blocks = terminal
        .iterm_blocks()
        .iter()
        .filter(|block| block.complete && (block.render || block.end_abs_row > block.start_abs_row))
        .filter(|block| {
            block.end_abs_row >= first_retained_abs_row
                && block.start_abs_row <= last_retained_abs_row
        })
        .filter_map(|block| {
            let source_start_row = block
                .start_abs_row
                .saturating_sub(first_retained_abs_row)
                .min(total_rows - 1);
            let source_end_row = block
                .end_abs_row
                .saturating_sub(first_retained_abs_row)
                .min(total_rows - 1);
            if projection
                .summary_id_for_source(source_start_row)
                .is_some_and(|summary_id| summary_id != block.id)
            {
                return None;
            }
            let start_display_row = projection.display_index_for_source(source_start_row)?;
            let end_display_row = projection.display_index_for_source(source_end_row)?;
            if end_display_row < display_start_row || start_display_row >= display_end_row {
                return None;
            }
            Some(TerminalBlock {
                id: block.id.clone(),
                block_type: block.block_type.clone(),
                start_row: start_display_row
                    .max(display_start_row)
                    .saturating_sub(display_start_row),
                end_row: end_display_row
                    .min(display_end_row.saturating_sub(1))
                    .saturating_sub(display_start_row),
                source_start_row,
                source_end_row,
                folded: block.folded,
                rendered: block.render,
                hidden_rows: if block.folded {
                    source_end_row.saturating_sub(source_start_row)
                } else {
                    0
                },
            })
        })
        .collect::<Vec<_>>();
    blocks.sort_by(|left, right| {
        left.start_row
            .cmp(&right.start_row)
            .then_with(|| left.end_row.cmp(&right.end_row).reverse())
            .then_with(|| left.id.cmp(&right.id))
    });
    blocks
}

fn build_terminal_inline_buttons(
    terminal: &Terminal,
    projection: &DisplayProjection,
    display_start_row: usize,
    viewport_rows: usize,
) -> Vec<TerminalInlineButton> {
    if viewport_rows == 0 {
        return Vec::new();
    }
    let alternate_screen = terminal.is_alt_screen_active();
    let first_retained_abs_row = if alternate_screen {
        0
    } else {
        terminal
            .grid()
            .total_lines_scrolled()
            .saturating_sub(terminal.grid().scrollback_len())
    };
    let display_end_row = display_start_row.saturating_add(viewport_rows);
    let mut buttons = terminal
        .iterm_buttons()
        .iter()
        .filter(|button| button.alternate_screen == alternate_screen)
        .filter_map(|button| {
            let source_row = button.row.checked_sub(first_retained_abs_row)?;
            if projection.summary_id_for_source(source_row).is_some() {
                return None;
            }
            let display_row = projection.display_index_for_source(source_row)?;
            if display_row < display_start_row || display_row >= display_end_row {
                return None;
            }
            let (kind, code, icon, block_id) = match &button.kind {
                ItermButtonKind::Copy { block_id } => {
                    ("copy".to_string(), None, None, Some(block_id.clone()))
                }
                ItermButtonKind::Custom { code, icon } => {
                    ("custom".to_string(), Some(*code), Some(icon.clone()), None)
                }
            };
            Some(TerminalInlineButton {
                id: button.id,
                kind,
                row: display_row.saturating_sub(display_start_row),
                col: button.col,
                code,
                icon,
                block_id,
                valid: button.valid,
                width_cells: par_term_emu_core_rust::terminal::ITERM_BUTTON_WIDTH_CELLS,
            })
        })
        .collect::<Vec<_>>();
    buttons.sort_by_key(|button| (button.row, button.col, button.id));
    buttons
}

fn extract_fold_summary_row(
    terminal: &Terminal,
    range: &CollapsedBlockRange,
    viewport_row: usize,
    viewport_cols: usize,
) -> ExtractedVisibleRow {
    let theme = terminal_theme_snapshot(terminal);
    let first = extract_row(
        row_cells_for_visible_index(terminal, range.source_start_row).0,
        false,
        &theme,
    );
    let last = extract_row(
        row_cells_for_visible_index(terminal, range.source_end_row).0,
        false,
        &theme,
    );
    let interior_rows = range
        .source_end_row
        .saturating_sub(range.source_start_row)
        .saturating_sub(1);
    let text = fold_summary_text(
        &first.text,
        &last.text,
        interior_rows,
        viewport_cols,
        terminal.width_config(),
    );
    let width = str_width(&text, terminal.width_config());
    let style_runs = (!text.is_empty()).then_some(TerminalStyleRun {
        start: 0,
        end: width,
        foreground: None,
        background: None,
        underline_color: None,
        bold: false,
        dim: true,
        italic: true,
        underline: false,
        blink: false,
        inverse: false,
    });
    ExtractedVisibleRow {
        row: TerminalRow {
            index: viewport_row,
            text,
            wrapped: false,
            style_runs: style_runs.into_iter().collect(),
            source_row: Some(range.source_start_row),
            source_end_row: Some(range.source_end_row),
        },
        continues_from_previous: false,
        hyperlinks: Vec::new(),
    }
}

fn fold_summary_text(
    first: &str,
    last: &str,
    interior_rows: usize,
    cols: usize,
    width_config: &WidthConfig,
) -> String {
    if cols == 0 {
        return String::new();
    }
    let mut middle = format!(
        " …{interior_rows} line{}… ",
        if interior_rows == 1 { "" } else { "s" }
    );
    if str_width(&middle, width_config) + 10 > cols {
        middle = "…".to_string();
    }
    let middle_width = str_width(&middle, width_config);
    if middle_width >= cols {
        return truncate_to_display_width(&middle, cols, width_config);
    }
    let remaining = cols - middle_width;
    let first_budget = remaining.div_ceil(2);
    let last_budget = remaining / 2;
    let first = truncate_to_display_width(first.trim_end(), first_budget, width_config);
    let last = truncate_to_display_width(last.trim(), last_budget, width_config);
    format!("{first}{middle}{last}")
}

fn truncate_to_display_width(value: &str, max_width: usize, width_config: &WidthConfig) -> String {
    let mut output = String::new();
    for character in value.chars() {
        output.push(character);
        if str_width(&output, width_config) > max_width {
            output.pop();
            break;
        }
    }
    output
}

fn cache_graphic_asset_snapshots(state: &mut TerminalState, snapshots: Vec<GraphicAssetSnapshot>) {
    for snapshot in snapshots {
        if state.graphic_assets.iter().any(|cached| {
            cached.asset_id == snapshot.asset_id
                && cached.asset_version == snapshot.asset_version
                && cached.width == snapshot.width
                && cached.height == snapshot.height
                && cached.pixels.as_ref() == snapshot.pixels.as_ref()
        }) {
            continue;
        }
        state.graphic_asset_bytes = state
            .graphic_asset_bytes
            .saturating_add(snapshot.pixels.len());
        state.graphic_assets.push_back(snapshot);
    }

    while state.graphic_assets.len() > 1
        && (state.graphic_assets.len() > MAX_GRAPHIC_ASSET_SNAPSHOTS
            || state.graphic_asset_bytes > state.graphic_asset_cache_max_bytes)
    {
        if let Some(removed) = state.graphic_assets.pop_front() {
            state.graphic_asset_bytes = state
                .graphic_asset_bytes
                .saturating_sub(removed.pixels.len());
        }
    }
}

fn find_cached_graphic_asset(
    state: &TerminalState,
    asset_id: u64,
    asset_version: u64,
) -> Result<&GraphicAssetSnapshot, SessionError> {
    let mut saw_asset_id = false;
    for asset in state.graphic_assets.iter().rev() {
        if asset.asset_id != asset_id {
            continue;
        }
        saw_asset_id = true;
        if asset.asset_version == asset_version {
            return Ok(asset);
        }
    }
    if saw_asset_id {
        Err(SessionError::GraphicAsset(
            "stale asset version".to_string(),
        ))
    } else {
        Err(SessionError::GraphicAsset("missing asset".to_string()))
    }
}

fn build_sized_text_placements(
    terminal: &Terminal,
    viewport_start_row: usize,
    viewport_rows: usize,
) -> Vec<TerminalSizedTextPlacement> {
    let viewport_end_row = viewport_start_row.saturating_add(viewport_rows);
    let scan_start_row = viewport_start_row.saturating_sub(6);
    let theme = terminal_theme_snapshot(terminal);
    let mut placements = Vec::new();

    for absolute_row in scan_start_row..viewport_end_row {
        let (cells, _) = row_cells_for_visible_index(terminal, absolute_row);
        for (col, cell) in cells.unwrap_or_default().iter().enumerate() {
            let Some(metadata) = cell.multicell else {
                continue;
            };
            if !metadata.is_anchor() {
                continue;
            }
            let width_cells = metadata.block_width();
            let height_cells = metadata.block_height();
            let block_end_row = absolute_row.saturating_add(height_cells);
            if width_cells == 0
                || height_cells == 0
                || col.saturating_add(width_cells) > terminal.size().0
                || block_end_row <= viewport_start_row
            {
                continue;
            }
            let visible_start_row = absolute_row.max(viewport_start_row);
            let visible_end_row = block_end_row.min(viewport_end_row);
            if visible_start_row >= visible_end_row {
                continue;
            }
            let (foreground, background, inverse, attribute_index) =
                frame_cell_colors(cell, &theme);
            placements.push(TerminalSizedTextPlacement {
                text: cell.get_grapheme(),
                row: visible_start_row.saturating_sub(viewport_start_row),
                col,
                width_cells,
                height_cells,
                source_row_offset_cells: visible_start_row.saturating_sub(absolute_row),
                visible_height_cells: visible_end_row.saturating_sub(visible_start_row),
                scale: metadata.scale,
                subscale_n: metadata.subscale_n,
                subscale_d: metadata.subscale_d,
                vertical_align: metadata.vertical_align,
                horizontal_align: metadata.horizontal_align,
                natural_width: metadata.natural_width,
                foreground: color_to_hex(foreground, &theme.ansi_palette),
                background: color_to_hex(background, &theme.ansi_palette),
                underline_color: (cell.flags.underline() && attribute_index != Some(1))
                    .then(|| cell.underline_color.or(theme.iterm_underline_color))
                    .flatten()
                    .and_then(|color| color_to_hex(color, &theme.ansi_palette)),
                bold: cell.flags.bold() && attribute_index != Some(0),
                dim: cell.flags.dim(),
                italic: cell.flags.italic() && attribute_index != Some(4),
                underline: cell.flags.underline() && attribute_index != Some(1),
                blink: cell.flags.blink() && attribute_index != Some(2),
                inverse,
            });
        }
    }
    placements
}

fn build_projected_sized_text_placements(
    terminal: &Terminal,
    projection: &DisplayProjection,
    display_start_row: usize,
    viewport_rows: usize,
) -> Vec<TerminalSizedTextPlacement> {
    if !projection.has_folds() {
        return build_sized_text_placements(terminal, display_start_row, viewport_rows);
    }
    let Some((source_start_row, source_end_row)) =
        projection_source_span(projection, display_start_row, viewport_rows)
    else {
        return Vec::new();
    };
    let physical_rows = source_end_row
        .saturating_sub(source_start_row)
        .saturating_add(1);
    build_sized_text_placements(terminal, source_start_row, physical_rows)
        .into_iter()
        .filter_map(|mut placement| {
            let source_row = source_start_row.saturating_add(placement.row);
            let source_end_exclusive = source_row.saturating_add(placement.height_cells.max(1));
            if projection.intersects_collapsed_range(source_row, source_end_exclusive) {
                return None;
            }
            let display_row = projection.display_index_for_source(source_row)?;
            if display_row < display_start_row
                || display_row >= display_start_row.saturating_add(viewport_rows)
            {
                return None;
            }
            placement.row = display_row.saturating_sub(display_start_row);
            Some(placement)
        })
        .collect()
}

fn extract_hyperlinks_for_row(
    terminal: &Terminal,
    cells: Option<&[Cell]>,
    row: usize,
) -> Vec<TerminalHyperlinkRange> {
    let mut ranges = Vec::new();
    let mut active_link: Option<(String, Option<String>)> = None;
    let mut active_start = 0usize;
    let mut column_offset = 0usize;

    for cell in cells.unwrap_or_default() {
        if cell.flags.wide_char_spacer() {
            continue;
        }
        if cell.multicell.is_some_and(|metadata| metadata.x > 0) {
            continue;
        }

        let column_start = column_offset;
        column_offset += cell
            .multicell
            .map_or_else(|| cell.width(), |metadata| metadata.block_width());
        let cell_link = cell.flags.hyperlink_id.and_then(|id| {
            terminal
                .get_hyperlink_url(id)
                .map(|uri| (uri, terminal.get_hyperlink_protocol_id(id)))
        });

        if active_link == cell_link {
            continue;
        }

        if let Some((uri, protocol_id)) = active_link.take() {
            ranges.push(TerminalHyperlinkRange {
                row,
                start_col: active_start,
                end_col: column_start,
                uri,
                protocol_id,
            });
        }

        if let Some(link) = cell_link {
            active_start = column_start;
            active_link = Some(link);
        }
    }

    if let Some((uri, protocol_id)) = active_link {
        ranges.push(TerminalHyperlinkRange {
            row,
            start_col: active_start,
            end_col: column_offset,
            uri,
            protocol_id,
        });
    }

    ranges
}

#[derive(Clone, Copy)]
struct TerminalThemeSnapshot {
    default_fg: Color,
    default_bg: Color,
    cursor_color: Color,
    cursor_guide_color: Color,
    selection_background: Color,
    selection_foreground: Option<Color>,
    iterm_bold_color: Option<Color>,
    iterm_underline_color: Option<Color>,
    link_color: Option<Color>,
    cursor_text_color: Option<Color>,
    tab_color: Option<Color>,
    xterm_attribute_colors: [Option<Color>; 5],
    xterm_color_attr_override: bool,
    ansi_palette: [Color; 256],
}

fn terminal_theme_snapshot(terminal: &Terminal) -> TerminalThemeSnapshot {
    TerminalThemeSnapshot {
        default_fg: terminal.default_fg(),
        default_bg: terminal.default_bg(),
        cursor_color: terminal.cursor_color(),
        cursor_guide_color: terminal.cursor_guide_color(),
        selection_background: terminal.get_selection_bg_color(),
        selection_foreground: terminal
            .selection_foreground_color_enabled()
            .then(|| terminal.get_selection_fg_color()),
        iterm_bold_color: terminal.iterm_bold_color(),
        iterm_underline_color: terminal.iterm_underline_color(),
        link_color: terminal.iterm_link_color(),
        cursor_text_color: terminal.iterm_cursor_text_color(),
        tab_color: terminal.iterm_tab_color(),
        xterm_attribute_colors: std::array::from_fn(|index| {
            (terminal.xterm_special_color_mode(index) == Some(true))
                .then(|| terminal.xterm_special_color(index))
                .flatten()
        }),
        xterm_color_attr_override: terminal.xterm_special_color_mode(5) == Some(true),
        ansi_palette: std::array::from_fn(|index| {
            terminal
                .get_ansi_color(index)
                .unwrap_or(Color::Indexed(index as u8))
        }),
    }
}

fn xterm_attribute_color(
    flags: CellFlags,
    theme: &TerminalThemeSnapshot,
) -> Option<(usize, Color)> {
    if !flags.foreground_is_default() && !theme.xterm_color_attr_override {
        return None;
    }
    [
        (3, flags.reverse()),
        (2, flags.blink()),
        (0, flags.bold()),
        (1, flags.underline()),
        (4, flags.italic()),
    ]
    .into_iter()
    .find_map(|(index, active)| {
        active
            .then_some(theme.xterm_attribute_colors[index])
            .flatten()
            .map(|color| (index, color))
    })
}

fn frame_cell_colors(
    cell: &Cell,
    theme: &TerminalThemeSnapshot,
) -> (Color, Color, bool, Option<usize>) {
    let inverse = cell.flags.reverse();
    let Some((attribute_index, attribute_color)) = xterm_attribute_color(cell.flags, theme) else {
        return if cell.flags.bold() {
            theme
                .iterm_bold_color
                .map_or((cell.fg, cell.bg, inverse, None), |color| {
                    (color, cell.bg, inverse, None)
                })
        } else {
            (cell.fg, cell.bg, inverse, None)
        };
    };
    let display_background = if inverse { cell.fg } else { cell.bg };
    (
        attribute_color,
        display_background,
        false,
        Some(attribute_index),
    )
}

fn extract_row(
    cells: Option<&[Cell]>,
    wrapped: bool,
    theme: &TerminalThemeSnapshot,
) -> ExtractedRow {
    let mut text = String::new();
    let mut style_runs = Vec::new();
    let mut run_start = 0usize;
    let mut run_style: Option<TerminalStyleRun> = None;
    let mut column_offset = 0usize;

    for cell in cells.unwrap_or_default() {
        if cell.flags.wide_char_spacer() {
            continue;
        }
        let multicell = cell.multicell;
        if multicell.is_some_and(|metadata| metadata.x > 0) {
            continue;
        }

        let grapheme = cell.get_grapheme();
        let is_kitty_placeholder = grapheme.starts_with(PLACEHOLDER_CHAR);
        let cell_width = multicell.map_or_else(|| cell.width(), |metadata| metadata.block_width());
        if multicell.is_some() {
            text.extend(std::iter::repeat_n(' ', cell_width));
        } else {
            text.push_str(if grapheme.is_empty() || is_kitty_placeholder {
                " "
            } else {
                &grapheme
            });
        }
        let column_start = column_offset;
        column_offset += cell_width;
        let column_end = column_offset;
        let (foreground, background, inverse, attribute_index) = frame_cell_colors(cell, theme);
        let style = TerminalStyleRun {
            start: column_start,
            end: column_end,
            foreground: if is_kitty_placeholder {
                None
            } else {
                color_to_hex_delta(foreground, theme.default_fg, &theme.ansi_palette)
            },
            background: if is_kitty_placeholder {
                None
            } else {
                color_to_hex_delta(background, theme.default_bg, &theme.ansi_palette)
            },
            underline_color: (!is_kitty_placeholder
                && cell.flags.underline()
                && attribute_index != Some(1))
            .then(|| cell.underline_color.or(theme.iterm_underline_color))
            .flatten()
            .and_then(|color| color_to_hex(color, &theme.ansi_palette)),
            bold: !is_kitty_placeholder && cell.flags.bold() && attribute_index != Some(0),
            dim: !is_kitty_placeholder && cell.flags.dim(),
            italic: !is_kitty_placeholder && cell.flags.italic() && attribute_index != Some(4),
            underline: !is_kitty_placeholder
                && cell.flags.underline()
                && attribute_index != Some(1),
            blink: !is_kitty_placeholder && cell.flags.blink() && attribute_index != Some(2),
            inverse: !is_kitty_placeholder && inverse,
        };

        match &run_style {
            Some(existing) if same_style(existing, &style) => {}
            Some(existing) => {
                let mut finalized = existing.clone();
                finalized.start = run_start;
                finalized.end = column_start;
                style_runs.push(finalized);
                run_start = column_start;
                run_style = Some(style);
            }
            None => {
                run_start = column_start;
                run_style = Some(style);
            }
        }
    }

    if let Some(existing) = run_style {
        let mut finalized = existing;
        finalized.start = run_start;
        finalized.end = column_offset;
        style_runs.push(finalized);
    }

    ExtractedRow {
        text,
        wrapped,
        style_runs,
    }
}

struct TerminalSearchPattern {
    regex: regex::Regex,
}

impl TerminalSearchPattern {
    fn new(query: &str, mode: TerminalSearchMode) -> Result<Self, String> {
        let pattern = if mode.is_regex() {
            query.to_string()
        } else {
            regex::escape(query)
        };
        let mut builder = RegexBuilder::new(&pattern);
        builder.case_insensitive(!mode.case_sensitive(query));
        builder
            .build()
            .map(|regex| Self { regex })
            .map_err(|error| error.to_string())
    }
}

fn collect_search_matches(
    matches: &mut Vec<TerminalSearchMatch>,
    rows: Vec<TerminalSearchRow>,
    pattern: &TerminalSearchPattern,
) {
    let mut logical_text = String::new();
    let mut segments = Vec::new();

    for row in rows {
        let start_byte = logical_text.len();
        logical_text.push_str(&row.text);
        segments.push(TerminalSearchLogicalSegment {
            row: row.row,
            text: row.text,
            start_byte,
            scrollback_offset: row.scrollback_offset,
        });

        if !row.wrapped {
            collect_logical_text_matches(matches, &logical_text, &segments, pattern);
            logical_text.clear();
            segments.clear();
        }
    }

    if !segments.is_empty() {
        collect_logical_text_matches(matches, &logical_text, &segments, pattern);
    }
}

fn collect_logical_text_matches(
    matches: &mut Vec<TerminalSearchMatch>,
    logical_text: &str,
    segments: &[TerminalSearchLogicalSegment],
    pattern: &TerminalSearchPattern,
) {
    for result in pattern.regex.find_iter(logical_text) {
        let Some((segment, byte_offset)) =
            segment_for_logical_byte_index(segments, result.start(), logical_text.len())
        else {
            continue;
        };
        let start_col = column_for_byte_index(&segment.text, byte_offset);
        let match_width = column_for_byte_index(result.as_str(), result.as_str().len());
        matches.push(TerminalSearchMatch {
            row: segment.row,
            start_col,
            end_col: start_col.saturating_add(match_width),
            text: result.as_str().to_string(),
            scrollback_offset: segment.scrollback_offset,
        });
    }
}

fn segment_for_logical_byte_index(
    segments: &[TerminalSearchLogicalSegment],
    byte_index: usize,
    logical_len: usize,
) -> Option<(&TerminalSearchLogicalSegment, usize)> {
    if byte_index == logical_len {
        let segment = segments.last()?;
        return Some((segment, segment.text.len()));
    }

    segments.iter().rev().find_map(|segment| {
        let segment_end = segment.start_byte.saturating_add(segment.text.len());
        if byte_index >= segment.start_byte && byte_index < segment_end {
            Some((segment, byte_index.saturating_sub(segment.start_byte)))
        } else {
            None
        }
    })
}

fn selection_text_for_state(state: &TerminalState, request: TerminalSelectionRequest) -> String {
    selection_text_for_terminal(&state.terminal, request)
}

fn selection_text_for_terminal(terminal: &Terminal, request: TerminalSelectionRequest) -> String {
    let normalized = normalize_selection_request(request);
    let theme = terminal_theme_snapshot(terminal);
    let total_lines = total_visible_lines(terminal);
    if total_lines == 0 || normalized.start_row >= total_lines {
        return String::new();
    }

    let end_row = normalized.end_row.min(total_lines.saturating_sub(1));
    if normalized.block {
        let mut lines = Vec::new();
        for row in normalized.start_row..=end_row {
            let (cells, _) = row_cells_for_visible_index(terminal, row);
            lines.push(slice_cells_columns(
                cells,
                normalized.start_col,
                normalized.end_col,
                &theme,
            ));
        }
        return lines.join("\n");
    }

    let mut text = String::new();
    for row in normalized.start_row..=end_row {
        let (cells, wrapped) = row_cells_for_visible_index(terminal, row);
        let start_col = if row == normalized.start_row {
            normalized.start_col
        } else {
            0
        };
        let end_col = if row == end_row && normalized.end_row < total_lines {
            normalized.end_col
        } else {
            usize::MAX
        };
        text.push_str(&slice_cells_columns(cells, start_col, end_col, &theme));
        if row != end_row && !wrapped {
            text.push('\n');
        }
    }
    text
}

fn retained_row_for_abs_row(terminal: &Terminal, abs_row: usize) -> Option<usize> {
    if terminal.is_alt_screen_active() {
        return (abs_row < terminal.size().1).then_some(abs_row);
    }
    let scrollback_len = terminal.grid().scrollback_len();
    let retained_base = terminal
        .grid()
        .total_lines_scrolled()
        .saturating_sub(scrollback_len);
    let retained_row = abs_row.checked_sub(retained_base)?;
    (retained_row < scrollback_len.saturating_add(terminal.size().1)).then_some(retained_row)
}

fn normalize_selection_request(request: TerminalSelectionRequest) -> TerminalSelectionRequest {
    if request.block {
        return TerminalSelectionRequest {
            start_row: request.start_row.min(request.end_row),
            start_col: request.start_col.min(request.end_col),
            end_row: request.start_row.max(request.end_row),
            end_col: request.start_col.max(request.end_col),
            block: true,
        };
    }

    if request.start_row < request.end_row
        || (request.start_row == request.end_row && request.start_col <= request.end_col)
    {
        return request;
    }

    TerminalSelectionRequest {
        start_row: request.end_row,
        start_col: request.end_col,
        end_row: request.start_row,
        end_col: request.start_col,
        block: false,
    }
}

fn total_visible_lines(terminal: &Terminal) -> usize {
    let (_, viewport_rows) = terminal.size();
    if terminal.is_alt_screen_active() {
        viewport_rows
    } else {
        terminal.grid().scrollback_len() + viewport_rows
    }
}

fn row_cells_for_visible_index(
    terminal: &Terminal,
    visible_index: usize,
) -> (Option<&[Cell]>, bool) {
    let (_, viewport_rows) = terminal.size();
    if terminal.is_alt_screen_active() {
        if visible_index >= viewport_rows {
            (None, false)
        } else {
            (
                terminal.alt_grid().row(visible_index),
                terminal.alt_grid().is_line_wrapped(visible_index),
            )
        }
    } else {
        primary_row_cells_for_visible_index(terminal.grid(), viewport_rows, visible_index)
    }
}

fn primary_row_cells_for_visible_index(
    grid: &Grid,
    viewport_rows: usize,
    visible_index: usize,
) -> (Option<&[Cell]>, bool) {
    let scrollback_len = grid.scrollback_len();
    if visible_index < scrollback_len {
        (
            grid.scrollback_line(visible_index),
            grid.is_scrollback_wrapped(visible_index),
        )
    } else {
        let screen_row = visible_index.saturating_sub(scrollback_len);
        if screen_row >= viewport_rows {
            (None, false)
        } else {
            (grid.row(screen_row), grid.is_line_wrapped(screen_row))
        }
    }
}

fn slice_cells_columns(
    cells: Option<&[Cell]>,
    start_col: usize,
    end_col: usize,
    theme: &TerminalThemeSnapshot,
) -> String {
    let effective_end_col = end_col.min(last_significant_column(cells, theme));
    if start_col >= effective_end_col {
        return String::new();
    }

    let mut text = String::new();
    let mut column_offset = 0usize;
    for cell in cells.unwrap_or_default() {
        if cell.flags.wide_char_spacer() {
            continue;
        }
        if cell.multicell.is_some_and(|metadata| metadata.x > 0) {
            continue;
        }

        let column_start = column_offset;
        column_offset += cell
            .multicell
            .map_or_else(|| cell.width(), |metadata| metadata.block_width());
        if column_offset <= start_col {
            continue;
        }
        if column_start >= effective_end_col {
            break;
        }

        if cell.multicell.is_none_or(|metadata| metadata.y == 0) {
            let grapheme = cell.get_grapheme();
            text.push_str(&grapheme);
        }
    }
    text
}

fn last_significant_column(cells: Option<&[Cell]>, theme: &TerminalThemeSnapshot) -> usize {
    let default_fg = theme.default_fg;
    let default_bg = theme.default_bg;
    let default_flags = CellFlags::default();
    let mut last_significant = 0usize;
    let mut column_offset = 0usize;

    for cell in cells.unwrap_or_default() {
        if cell.flags.wide_char_spacer() {
            continue;
        }
        if cell.multicell.is_some_and(|metadata| metadata.x > 0) {
            continue;
        }
        column_offset += cell
            .multicell
            .map_or_else(|| cell.width(), |metadata| metadata.block_width());
        let has_content = cell.multicell.is_none_or(|metadata| metadata.y == 0)
            && (cell.c != ' ' || !cell.combining.is_empty());
        let has_styling =
            cell.fg != default_fg || cell.bg != default_bg || cell.flags != default_flags;
        if has_content || has_styling {
            last_significant = column_offset;
        }
    }

    last_significant
}

fn column_for_byte_index(text: &str, byte_index: usize) -> usize {
    text.char_indices()
        .take_while(|(index, _)| *index < byte_index)
        .map(|(_, value)| display_width_for_char(value))
        .sum()
}

fn display_width_for_char(value: char) -> usize {
    if value.is_control() {
        return 0;
    }
    let code = value as u32;
    if (0x1100..=0x115f).contains(&code)
        || (0x2e80..=0xa4cf).contains(&code)
        || (0xac00..=0xd7a3).contains(&code)
        || (0xf900..=0xfaff).contains(&code)
        || (0xfe10..=0xfe19).contains(&code)
        || (0xfe30..=0xfe6f).contains(&code)
        || (0xff00..=0xff60).contains(&code)
        || (0xffe0..=0xffe6).contains(&code)
        || (0x1f300..=0x1faff).contains(&code)
    {
        2
    } else {
        1
    }
}

fn normalize_responses(emulation: TerminalEmulation, responses: Vec<u8>) -> Vec<u8> {
    if emulation != TerminalEmulation::Vt220 || responses.is_empty() {
        return responses;
    }

    String::from_utf8_lossy(&responses)
        .replace("\x1b[?62;1;4;6;9;15;22;52c", VT220_PRIMARY_DA_RESPONSE)
        .replace("\x1b[>82;10000;0c", VT220_SECONDARY_DA_RESPONSE)
        .replace("\x1b[?5522;1$y", "\x1b[?5522;0$y")
        .replace("\x1b[?5522;2$y", "\x1b[?5522;0$y")
        .into_bytes()
}

fn current_scrollback_max(state: &TerminalState) -> usize {
    if state.terminal.is_alt_screen_active() {
        0
    } else {
        let (_, viewport_rows) = state.terminal.size();
        display_projection_for_terminal(&state.terminal)
            .rows
            .len()
            .saturating_sub(viewport_rows)
    }
}

fn remap_scrollback_offset(
    previous_offset: usize,
    previous_max_offset: usize,
    new_max_offset: usize,
) -> usize {
    if previous_offset == 0 || new_max_offset == 0 {
        0
    } else if previous_offset >= previous_max_offset {
        new_max_offset
    } else if previous_max_offset == 0 {
        0
    } else {
        ((previous_offset as f64 / previous_max_offset as f64) * new_max_offset as f64).round()
            as usize
    }
}

fn same_style(left: &TerminalStyleRun, right: &TerminalStyleRun) -> bool {
    left.foreground == right.foreground
        && left.background == right.background
        && left.underline_color == right.underline_color
        && left.bold == right.bold
        && left.dim == right.dim
        && left.italic == right.italic
        && left.underline == right.underline
        && left.blink == right.blink
        && left.inverse == right.inverse
}

fn style_signature(style_runs: &[TerminalStyleRun]) -> u64 {
    let mut hasher = DefaultHasher::new();
    for run in style_runs {
        run.start.hash(&mut hasher);
        run.end.hash(&mut hasher);
        run.foreground.hash(&mut hasher);
        run.background.hash(&mut hasher);
        run.underline_color.hash(&mut hasher);
        run.bold.hash(&mut hasher);
        run.dim.hash(&mut hasher);
        run.italic.hash(&mut hasher);
        run.underline.hash(&mut hasher);
        run.blink.hash(&mut hasher);
        run.inverse.hash(&mut hasher);
    }
    hasher.finish()
}

fn hyperlink_signature(hyperlinks: &[TerminalHyperlinkRange]) -> u64 {
    let mut hasher = DefaultHasher::new();
    for hyperlink in hyperlinks {
        hyperlink.start_col.hash(&mut hasher);
        hyperlink.end_col.hash(&mut hasher);
        hyperlink.uri.hash(&mut hasher);
        hyperlink.protocol_id.hash(&mut hasher);
    }
    hasher.finish()
}

fn parse_hex_color(value: &str) -> Option<Color> {
    let normalized = value.trim().strip_prefix('#')?;
    if normalized.len() != 6 {
        return None;
    }
    let red = u8::from_str_radix(&normalized[0..2], 16).ok()?;
    let green = u8::from_str_radix(&normalized[2..4], 16).ok()?;
    let blue = u8::from_str_radix(&normalized[4..6], 16).ok()?;
    Some(Color::Rgb(red, green, blue))
}

fn configure_session_terminal(
    terminal: &mut Terminal,
    emulation: TerminalEmulation,
    graphics_memory_limits: Option<TerminalGraphicsMemoryLimits>,
    profile_colors: &TerminalProfileColors,
    profile_font: &TerminalProfileFont,
    osc633_expected_nonce: Option<&str>,
    drag_drop_enabled: bool,
) {
    if let Some(limits) = graphics_memory_limits {
        terminal.set_graphics_memory_limits(limits.max_image_bytes, limits.max_total_bytes);
    }
    apply_profile_colors(terminal, profile_colors);
    let _ = terminal.set_xterm_font_family_from_profile(&profile_font.family);
    configure_terminal_protocol_policy(terminal, emulation);
    terminal.set_max_transfer_size(ITERM_FILE_DOWNLOAD_MAX_BYTES);
    terminal.set_osc_capability_allowed(OscCapability::DragDrop, drag_drop_enabled);
    if let Some(nonce) = osc633_expected_nonce {
        let configured = terminal.set_osc633_expected_nonce(Some(nonce.to_string()));
        debug_assert!(configured, "VSCODE_NONCE was prevalidated");
    }
    if emulation == TerminalEmulation::Vt220 {
        terminal.process(b"\x1b[62;1\"p");
    }
}

fn configure_terminal_protocol_policy(terminal: &mut Terminal, emulation: TerminalEmulation) {
    if emulation == TerminalEmulation::Vt220 {
        for capability in [
            OscCapability::Appearance,
            OscCapability::Metadata,
            OscCapability::Hyperlink,
            OscCapability::ClipboardWrite,
            OscCapability::ClipboardRead,
            OscCapability::Notification,
            OscCapability::Media,
            OscCapability::HostAction,
            OscCapability::FileTransfer,
            OscCapability::DragDrop,
            OscCapability::CustomProtocol,
        ] {
            terminal.set_osc_capability_allowed(capability, false);
        }
        terminal.set_accept_osc7(false);
        return;
    }

    // Parse OSC 52 reads as typed requests for the Dart policy layer. This
    // does not enable the terminal's direct clipboard response flag, so the
    // host action remains deny-by-default until Dart authorizes it.
    terminal.set_osc_capability_allowed(OscCapability::ClipboardRead, true);
}

fn apply_profile_colors(terminal: &mut Terminal, colors: &TerminalProfileColors) {
    if let Some(color) = colors
        .special
        .foreground
        .as_deref()
        .and_then(parse_hex_color)
    {
        terminal.set_default_fg(color);
    }
    if let Some(color) = colors
        .special
        .background
        .as_deref()
        .and_then(parse_hex_color)
    {
        terminal.set_default_bg(color);
    }
    if let Some(color) = colors.special.cursor.as_deref().and_then(parse_hex_color) {
        terminal.set_cursor_color(color);
    }
    terminal.set_iterm_tab_color_baseline(colors.special.tab.as_deref().and_then(parse_hex_color));
    if let Some(color) = colors
        .special
        .selection
        .as_deref()
        .and_then(parse_hex_color)
    {
        terminal.set_selection_bg_color(color);
    }

    apply_profile_ansi_colors(terminal, &colors.normal, 0);
    apply_profile_ansi_colors(terminal, &colors.bright, 8);
}

fn apply_profile_ansi_colors(
    terminal: &mut Terminal,
    colors: &TerminalProfileAnsiColors,
    offset: usize,
) {
    for (index, color) in [
        colors.black.as_deref(),
        colors.red.as_deref(),
        colors.green.as_deref(),
        colors.yellow.as_deref(),
        colors.blue.as_deref(),
        colors.magenta.as_deref(),
        colors.cyan.as_deref(),
        colors.white.as_deref(),
    ]
    .into_iter()
    .enumerate()
    {
        let Some(color) = color.and_then(parse_hex_color) else {
            continue;
        };
        let _ = terminal.set_ansi_palette_color(index + offset, color);
    }
}

fn resolve_color_rgb(color: Color, ansi_palette: &[Color; 256]) -> (u8, u8, u8) {
    match color {
        Color::Named(named) => ansi_palette[named as usize].to_rgb(),
        Color::Indexed(index) => ansi_palette[index as usize].to_rgb(),
        Color::Rgb(red, green, blue) => (red, green, blue),
    }
}

fn color_to_hex(color: Color, ansi_palette: &[Color; 256]) -> Option<String> {
    let (red, green, blue) = resolve_color_rgb(color, ansi_palette);
    Some(format!("#{red:02x}{green:02x}{blue:02x}"))
}

fn color_to_hex_delta(color: Color, default: Color, ansi_palette: &[Color; 256]) -> Option<String> {
    if resolve_color_rgb(color, ansi_palette) == resolve_color_rgb(default, ansi_palette) {
        return None;
    }
    color_to_hex(color, ansi_palette)
}

fn mouse_mode_name(mode: MouseMode) -> &'static str {
    match mode {
        MouseMode::Off => "off",
        MouseMode::X10 => "x10",
        MouseMode::Normal => "normal",
        MouseMode::ButtonEvent => "button_event",
        MouseMode::AnyEvent => "any_event",
    }
}

fn mouse_encoding_name(encoding: MouseEncoding) -> &'static str {
    match encoding {
        MouseEncoding::Default => "default",
        MouseEncoding::Utf8 => "utf8",
        MouseEncoding::Sgr => "sgr",
        MouseEncoding::SgrPixels => "sgr_pixels",
        MouseEncoding::Urxvt => "urxvt",
    }
}

pub fn ping() -> i32 {
    42
}

pub fn create_session(profile_json: &str) -> Result<u64, SessionError> {
    let profile: TerminalProfile = serde_json::from_str(profile_json)
        .map_err(|error| SessionError::InvalidProfile(error.to_string()))?;
    STORE.create_session(profile)
}

pub fn create_session_v1(session_config_json: &str) -> Result<u64, SessionError> {
    let config = SessionConfigV1::decode_json(session_config_json)
        .map_err(|error| SessionError::InvalidSessionConfig(error.to_string()))?;
    let zmodem_enabled = config.client_capabilities.zmodem;
    STORE.create_session_with_zmodem(config.into_terminal_profile(), zmodem_enabled)
}

pub fn create_replay_session(profile_json: &str) -> Result<u64, SessionError> {
    let profile: TerminalProfile = serde_json::from_str(profile_json)
        .map_err(|error| SessionError::InvalidProfile(error.to_string()))?;
    STORE.create_replay_session(profile)
}

pub fn create_replay_session_v1(session_config_json: &str) -> Result<u64, SessionError> {
    let config = SessionConfigV1::decode_json(session_config_json)
        .map_err(|error| SessionError::InvalidSessionConfig(error.to_string()))?;
    STORE.create_replay_session(config.into_terminal_profile())
}

pub fn replay_session_output(session_id: u64, bytes: &[u8]) -> Result<(), SessionError> {
    STORE.get(session_id)?.replay_output(bytes)
}

pub fn replay_session_exit(session_id: u64, exit_code: Option<i32>) -> Result<(), SessionError> {
    STORE.get(session_id)?.replay_exit(exit_code)
}

pub fn replay_session_capture_checkpoint(session_id: u64) -> Result<u64, SessionError> {
    STORE.get(session_id)?.capture_replay_checkpoint()
}

pub fn replay_session_restore_checkpoint(
    session_id: u64,
    checkpoint_id: u64,
) -> Result<(), SessionError> {
    STORE
        .get(session_id)?
        .restore_replay_checkpoint(checkpoint_id)
}

pub fn close_session(session_id: u64) -> Result<(), SessionError> {
    STORE.close_session(session_id)
}

pub fn refresh_hint_flags(session_id: u64) -> Result<u32, SessionError> {
    Ok(STORE.get(session_id)?.refresh_hint_flags())
}

pub fn resize_session(
    session_id: u64,
    cols: u16,
    rows: u16,
    pixel_width: u16,
    pixel_height: u16,
) -> Result<(), SessionError> {
    STORE
        .get(session_id)?
        .resize(cols, rows, pixel_width, pixel_height)
}

pub fn resize_session_with_cell_size(
    session_id: u64,
    cols: u16,
    rows: u16,
    pixel_width: u16,
    pixel_height: u16,
    cell_width: u16,
    cell_height: u16,
) -> Result<(), SessionError> {
    STORE.get(session_id)?.resize_with_cell_size(
        cols,
        rows,
        pixel_width,
        pixel_height,
        cell_width,
        cell_height,
    )
}

pub fn write_session(session_id: u64, bytes: &[u8]) -> Result<(), SessionError> {
    STORE.get(session_id)?.write(bytes)
}

pub fn write_session_protocol_reply(session_id: u64, bytes: &[u8]) -> Result<(), SessionError> {
    STORE.get(session_id)?.write_protocol_reply(bytes)
}

pub fn respond_host_v1_json(session_id: u64, raw: &str) -> Result<(), SessionError> {
    STORE.get(session_id)?.respond_host_v1(raw)
}

pub fn scroll_session(session_id: u64, delta_lines: i32) -> Result<(), SessionError> {
    STORE.get(session_id)?.scroll(delta_lines);
    Ok(())
}

pub fn scroll_to_session(session_id: u64, offset: usize) -> Result<(), SessionError> {
    STORE.get(session_id)?.scroll_to(offset);
    Ok(())
}

pub fn search_session(session_id: u64, query: &str) -> Result<String, SessionError> {
    let matches = STORE
        .get(session_id)?
        .search(query, TerminalSearchMode::CaseSensitiveSubstring)
        .unwrap_or_default();
    serde_json::to_string(&matches).map_err(|error| SessionError::Serialize(error.to_string()))
}

pub fn search_session_with_mode(
    session_id: u64,
    query: &str,
    mode: Option<&str>,
) -> Result<String, SessionError> {
    let mode = TerminalSearchMode::from_wire(mode);
    let response = match STORE.get(session_id)?.search(query, mode) {
        Ok(matches) => TerminalSearchResponse {
            matches,
            error_text: None,
        },
        Err(_) => TerminalSearchResponse {
            matches: Vec::new(),
            error_text: Some("Invalid regular expression"),
        },
    };
    serde_json::to_string(&response).map_err(|error| SessionError::Serialize(error.to_string()))
}

pub fn selection_text_session(session_id: u64, request_json: &str) -> Result<String, SessionError> {
    let request: TerminalSelectionRequest = serde_json::from_str(request_json)
        .map_err(|error| SessionError::InvalidSelection(error.to_string()))?;
    Ok(STORE.get(session_id)?.selection_text(request))
}

pub fn clear_scrollback_session(session_id: u64) -> Result<String, SessionError> {
    let cleared = STORE.get(session_id)?.clear_scrollback()?;
    serde_json::to_string(&serde_json::json!({ "cleared": cleared }))
        .map_err(|error| SessionError::Serialize(error.to_string()))
}

pub fn clear_buffer_session(session_id: u64) -> Result<String, SessionError> {
    let cleared = STORE.get(session_id)?.clear_buffer()?;
    serde_json::to_string(&serde_json::json!({ "cleared": cleared }))
        .map_err(|error| SessionError::Serialize(error.to_string()))
}

pub fn export_scrollback_session(
    session_id: u64,
    max_lines: Option<usize>,
) -> Result<String, SessionError> {
    let content = STORE.get(session_id)?.export_scrollback_text(max_lines);
    serde_json::to_string(&serde_json::json!({
        "content": content,
        "scope": "historical-scrollback",
    }))
    .map_err(|error| SessionError::Serialize(error.to_string()))
}

fn export_diagnostics_session(
    session_id: u64,
    request: TerminalDiagnosticsRequest,
) -> Result<String, SessionError> {
    STORE.get(session_id)?.export_diagnostics_json(request)
}

fn request_json_response(value: serde_json::Value) -> Result<Option<String>, SessionError> {
    serde_json::to_string(&value)
        .map(Some)
        .map_err(|error| SessionError::Serialize(error.to_string()))
}

fn recording_error_response(error: RecordingError) -> Result<Option<String>, SessionError> {
    request_json_response(serde_json::json!({
        "ok": false,
        "error": {
            "code": error.code,
            "message": error.message,
        },
    }))
}

fn recording_initial_screen(terminal: &Terminal) -> Vec<u8> {
    let cursor = terminal.cursor();
    let mut screen = String::new();
    // Reconstruct the visible grid as one synchronized update. Without this
    // envelope a large initial screen can publish partially restored rows as
    // the replay parser consumes the ANSI stream, exposing a malformed first
    // frame before the cursor and remaining rows have been restored.
    screen.push_str("\x1b[?2026h");
    if terminal.is_alt_screen_active() {
        screen.push_str("\x1b[?1049h");
    }
    screen.push_str("\x1b[2J");
    screen.push_str(&terminal.export_visible_screen_styled());
    screen.push_str(&format!("\x1b[{};{}H", cursor.row + 1, cursor.col + 1));
    screen.push_str(if cursor.visible {
        "\x1b[?25h"
    } else {
        "\x1b[?25l"
    });
    screen.push_str("\x1b[?2026l");
    screen.into_bytes()
}

fn invalid_recording_request(message: &'static str) -> Result<Option<String>, SessionError> {
    recording_error_response(RecordingError {
        code: "invalid_request",
        message,
    })
}

pub fn request_session_json(
    session_id: u64,
    request_json: &str,
) -> Result<Option<String>, SessionError> {
    let request: serde_json::Value = serde_json::from_str(request_json)
        .map_err(|error| SessionError::Serialize(error.to_string()))?;
    let Some(kind) = request.get("kind").and_then(serde_json::Value::as_str) else {
        return Ok(None);
    };

    match kind {
        "ssh.auth_response" => {
            let challenge_id = request
                .get("challengeId")
                .and_then(serde_json::Value::as_u64)
                .or_else(|| {
                    request
                        .get("challengeId")
                        .and_then(serde_json::Value::as_str)
                        .and_then(|value| value.parse().ok())
                });
            let cancel = request
                .get("cancel")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false);
            let responses = request
                .get("responses")
                .and_then(serde_json::Value::as_array)
                .filter(|responses| responses.len() <= 32)
                .and_then(|responses| {
                    responses
                        .iter()
                        .map(|response| {
                            response
                                .as_str()
                                .filter(|response| {
                                    response.len() <= 64 * 1024 && !response.contains('\0')
                                })
                                .map(str::to_string)
                        })
                        .collect::<Option<Vec<_>>>()
                });
            let Some(challenge_id) = challenge_id else {
                return Ok(None);
            };
            let session = STORE.get(session_id)?;
            let accepted = if cancel {
                session.cancel_ssh_auth(challenge_id)
            } else if let Some(responses) = responses {
                session.respond_ssh_auth(challenge_id, responses)
            } else {
                return Ok(None);
            };
            request_json_response(serde_json::json!({ "accepted": accepted }))
        }
        "terminal.recording_start" => {
            if request
                .get("schema_version")
                .and_then(serde_json::Value::as_u64)
                != Some(recording::RECORDING_SCHEMA_VERSION.into())
            {
                return invalid_recording_request("schema_version must be 1");
            }
            let Some(created_at_utc) = request
                .get("created_at_utc")
                .and_then(serde_json::Value::as_str)
                .filter(|value| !value.is_empty() && value.ends_with('Z'))
            else {
                return invalid_recording_request(
                    "created_at_utc must be a non-empty UTC timestamp",
                );
            };
            let Some(input_policy) = request
                .get("input_policy")
                .and_then(serde_json::Value::as_str)
                .and_then(RecordingInputPolicy::parse)
            else {
                return invalid_recording_request("input_policy must be record or redact");
            };
            let session = STORE.get(session_id)?;
            let mut recording = session.recording.lock();
            let state = session.state.lock();
            let (cols, rows) = state.terminal.size();
            let terminal_emulation = match session.emulation {
                TerminalEmulation::Xterm256 => "xterm256",
                TerminalEmulation::Vt220 => "vt220",
            };
            let initial_screen = recording_initial_screen(&state.terminal);
            let result = recording.start(
                session_id,
                created_at_utc.to_string(),
                input_policy,
                terminal_emulation,
                cols as u16,
                rows as u16,
                initial_screen,
            );
            drop(state);
            match result {
                Ok(started) => request_json_response(serde_json::json!({
                    "ok": true,
                    "max_events": started.max_events,
                    "max_payload_bytes": started.max_payload_bytes,
                })),
                Err(error) => recording_error_response(error),
            }
        }
        "terminal.recording_stop" => {
            let session = STORE.get(session_id)?;
            session.observe_child_exit()?;
            match session.recording.lock().stop() {
                Ok(recording_ndjson) => request_json_response(serde_json::json!({
                    "ok": true,
                    "recording_ndjson": recording_ndjson,
                })),
                Err(error) => recording_error_response(error),
            }
        }
        "terminal.recording_cancel" => {
            let session = STORE.get(session_id)?;
            match session.recording.lock().cancel() {
                Ok(()) => request_json_response(serde_json::json!({ "ok": true })),
                Err(error) => recording_error_response(error),
            }
        }
        "terminal.search_text" => {
            let query = request
                .get("query")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default();
            let mode = request.get("mode").and_then(serde_json::Value::as_str);
            search_session_with_mode(session_id, query, mode).map(Some)
        }
        "terminal.selection_text" => {
            let Some(selection) = request.get("selection") else {
                return Ok(None);
            };
            let mut selection = selection.clone();
            let serde_json::Value::Object(selection) = &mut selection else {
                return Ok(None);
            };
            selection.insert(
                "block".to_string(),
                serde_json::Value::Bool(
                    request
                        .get("block")
                        .and_then(serde_json::Value::as_bool)
                        .unwrap_or(false),
                ),
            );
            let request_json = serde_json::to_string(&selection)
                .map_err(|error| SessionError::Serialize(error.to_string()))?;
            let text = selection_text_session(session_id, &request_json)?;
            serde_json::to_string(&serde_json::json!({ "text": text }))
                .map(Some)
                .map_err(|error| SessionError::Serialize(error.to_string()))
        }
        "terminal.clear_scrollback" => clear_scrollback_session(session_id).map(Some),
        "terminal.clear_buffer" => clear_buffer_session(session_id).map(Some),
        "terminal.dismiss_osc99_notification" => {
            let Some(identifier) = request.get("id").and_then(serde_json::Value::as_str) else {
                return Ok(None);
            };
            let dismissed = STORE
                .get(session_id)?
                .dismiss_osc99_notification(identifier);
            serde_json::to_string(&serde_json::json!({ "dismissed": dismissed }))
                .map(Some)
                .map_err(|error| SessionError::Serialize(error.to_string()))
        }
        "terminal.set_block_folded" => {
            let Some(id) = request.get("id").and_then(serde_json::Value::as_str) else {
                return Ok(None);
            };
            let Some(folded) = request.get("folded").and_then(serde_json::Value::as_bool) else {
                return Ok(None);
            };
            let updated = STORE.get(session_id)?.set_block_folded(id, folded);
            serde_json::to_string(&serde_json::json!({ "updated": updated }))
                .map(Some)
                .map_err(|error| SessionError::Serialize(error.to_string()))
        }
        "terminal.set_block_rendered" => {
            let Some(id) = request.get("id").and_then(serde_json::Value::as_str) else {
                return Ok(None);
            };
            let Some(rendered) = request.get("rendered").and_then(serde_json::Value::as_bool)
            else {
                return Ok(None);
            };
            let updated = STORE.get(session_id)?.set_block_rendered(id, rendered);
            serde_json::to_string(&serde_json::json!({ "updated": updated }))
                .map(Some)
                .map_err(|error| SessionError::Serialize(error.to_string()))
        }
        "terminal.activate_iterm_button" => {
            let Some(id) = request.get("id").and_then(serde_json::Value::as_u64) else {
                return Ok(None);
            };
            let response = STORE.get(session_id)?.activate_iterm_button(id)?;
            serde_json::to_string(&response)
                .map(Some)
                .map_err(|error| SessionError::Serialize(error.to_string()))
        }
        "terminal.export_scrollback" => {
            let max_lines = scrollback_export_max_lines_from_request(&request);
            export_scrollback_session(session_id, max_lines).map(Some)
        }
        "terminal.export_diagnostics" => {
            let max_samples = request
                .get("maxSamples")
                .or_else(|| request.get("max_samples"))
                .and_then(serde_json::Value::as_u64)
                .and_then(|value| usize::try_from(value).ok())
                .unwrap_or(RESOURCE_SAMPLE_CAPACITY)
                .min(RESOURCE_SAMPLE_CAPACITY);
            let include_content = request
                .get("includeContent")
                .or_else(|| request.get("include_content"))
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false);
            let redaction_mode = request
                .get("redactionMode")
                .or_else(|| request.get("redaction_mode"))
                .and_then(serde_json::Value::as_str)
                .unwrap_or("basic")
                .to_string();
            export_diagnostics_session(
                session_id,
                TerminalDiagnosticsRequest {
                    max_samples,
                    include_content,
                    redaction_mode,
                },
            )
            .map(Some)
        }
        "terminal.zmodem.accept_receive" => {
            let Some(transfer_id) = zmodem_transfer_id_from_request(&request) else {
                return Ok(None);
            };
            let Some(destination) = request
                .get("destination")
                .and_then(serde_json::Value::as_str)
                .filter(|value| !value.is_empty() && value.len() <= 4096 && !value.contains('\0'))
            else {
                return Ok(None);
            };
            STORE
                .get(session_id)?
                .accept_zmodem_receive(transfer_id, std::path::Path::new(destination))?;
            request_json_response(serde_json::json!({ "accepted": true }))
        }
        "terminal.zmodem.accept_send" => {
            let Some(transfer_id) = zmodem_transfer_id_from_request(&request) else {
                return Ok(None);
            };
            let Some(files) = request
                .get("files")
                .and_then(serde_json::Value::as_array)
                .filter(|files| !files.is_empty() && files.len() <= 256)
            else {
                return Ok(None);
            };
            let mut paths = Vec::with_capacity(files.len());
            for file in files {
                let Some(path) = file.as_str().filter(|value| {
                    !value.is_empty() && value.len() <= 4096 && !value.contains('\0')
                }) else {
                    return Ok(None);
                };
                paths.push(std::path::PathBuf::from(path));
            }
            STORE
                .get(session_id)?
                .accept_zmodem_send(transfer_id, &paths)?;
            request_json_response(serde_json::json!({ "accepted": true }))
        }
        "terminal.zmodem.resolve_recovery" => {
            let Some(token) = request
                .get("recoveryToken")
                .and_then(serde_json::Value::as_str)
                .filter(|value| {
                    value.len() == 32 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
                })
            else {
                return Ok(None);
            };
            let path = match STORE.get(session_id) {
                Ok(session) => session.resolve_zmodem_recovery(token),
                Err(SessionError::MissingSession(_)) => {
                    crate::zmodem::resolve_tombstoned_recovery(token, session_id)
                }
                Err(error) => return Err(error),
            };
            match path {
                Some(path) => request_json_response(serde_json::json!({
                    "available": true,
                    "path": path.to_string_lossy(),
                })),
                None => request_json_response(serde_json::json!({
                    "available": false,
                })),
            }
        }
        "terminal.zmodem.consume_recovery" => {
            let Some(token) = request
                .get("recoveryToken")
                .and_then(serde_json::Value::as_str)
                .filter(|value| {
                    value.len() == 32 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
                })
            else {
                return Ok(None);
            };
            request_json_response(serde_json::json!({
                "consumed": crate::zmodem::consume_recovery(token, session_id),
            }))
        }
        "terminal.zmodem.dismiss_recovery" => {
            let Some(token) = request
                .get("recoveryToken")
                .and_then(serde_json::Value::as_str)
                .filter(|value| {
                    value.len() == 32 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
                })
            else {
                return Ok(None);
            };
            request_json_response(serde_json::json!({
                "dismissed": crate::zmodem::dismiss_recovery(token, session_id),
            }))
        }
        "terminal.zmodem.cancel" => {
            let Some(transfer_id) = zmodem_transfer_id_from_request(&request) else {
                return Ok(None);
            };
            STORE.get(session_id)?.cancel_zmodem(transfer_id)?;
            request_json_response(serde_json::json!({ "cancelled": true }))
        }
        "terminal.zmodem.cancel_active" => {
            let outcome = STORE.get(session_id)?.cancel_active_zmodem()?;
            request_json_response(serde_json::json!({
                "reconciled": true,
                "outcome": outcome.as_str(),
            }))
        }
        "terminal.session.close_readiness" => {
            let (ready, reason) = STORE.get(session_id)?.close_readiness();
            request_json_response(serde_json::json!({
                "ready": ready,
                "reason": reason,
            }))
        }
        _ => Ok(None),
    }
}

fn zmodem_transfer_id_from_request(request: &serde_json::Value) -> Option<u64> {
    let value = request.get("transferId")?.as_str()?;
    if value.is_empty() || value.len() > 20 || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    value.parse::<u64>().ok().filter(|value| *value > 0)
}

fn scrollback_export_max_lines_from_request(request: &serde_json::Value) -> Option<usize> {
    let raw_value = request
        .get("maxLines")
        .or_else(|| request.get("max_lines"))?;
    if raw_value.is_null() {
        return None;
    }
    if let Some(value) = raw_value.as_i64() {
        if value <= 0 {
            return Some(0);
        }
        return usize::try_from(value as u64)
            .ok()
            .map(|value| value.min(MAX_SCROLLBACK_LINES));
    }
    if let Some(value) = raw_value.as_u64() {
        return Some(
            usize::try_from(value)
                .unwrap_or(MAX_SCROLLBACK_LINES)
                .min(MAX_SCROLLBACK_LINES),
        );
    }
    Some(0)
}

pub fn take_frame_diff(session_id: u64) -> Result<Option<String>, SessionError> {
    let session = STORE.get(session_id)?;
    let Some(diff) = session.take_frame_diff()? else {
        return Ok(None);
    };
    let encode_started_at = Instant::now();
    let json =
        serde_json::to_string(&diff).map_err(|error| SessionError::Serialize(error.to_string()))?;
    session.record_frame_json_encode_micros(encode_started_at.elapsed().as_micros() as u64);
    Ok(Some(json))
}

pub fn take_frame_diff_protobuf(session_id: u64) -> Result<Option<Vec<u8>>, SessionError> {
    let session = STORE.get(session_id)?;
    let Some(diff) = session.take_frame_diff()? else {
        return Ok(None);
    };
    let encode_started_at = Instant::now();
    let bytes = frame_diff_proto::encode_frame_diff(&diff)
        .map_err(|error| SessionError::Serialize(error.to_string()))?;
    session.record_frame_protobuf_encode_micros(encode_started_at.elapsed().as_micros() as u64);
    Ok(Some(bytes))
}

pub fn take_frame_packet_v1_protobuf(
    session_id: u64,
    after_sequence: Option<u64>,
) -> Result<Option<Vec<u8>>, SessionError> {
    STORE
        .get(session_id)?
        .take_frame_packet_v1_protobuf(after_sequence)
}

pub fn take_frame_debug_stats_json(session_id: u64) -> Result<Option<String>, SessionError> {
    STORE.get(session_id)?.take_frame_debug_stats_json()
}

pub fn take_session_debug_stats_json(session_id: u64) -> Result<Option<String>, SessionError> {
    STORE.get(session_id)?.take_session_debug_stats_json()
}

pub fn take_diagnostic_event_v1_json(
    session_id: u64,
    name: &str,
) -> Result<Option<String>, SessionError> {
    STORE.get(session_id)?.take_diagnostic_event_v1_json(name)
}

pub fn poll_events(session_id: u64) -> Result<String, SessionError> {
    let events = take_events(session_id)?;
    serde_json::to_string(&events).map_err(|error| SessionError::Serialize(error.to_string()))
}

pub fn take_events(session_id: u64) -> Result<Vec<TerminalEvent>, SessionError> {
    STORE.get(session_id)?.poll_events()
}

pub fn poll_event_envelopes(session_id: u64) -> Result<Option<String>, SessionError> {
    STORE
        .get(session_id)?
        .poll_event_envelopes()?
        .map(|batch| {
            serde_json::to_string(&batch)
                .map_err(|error| SessionError::Serialize(error.to_string()))
        })
        .transpose()
}

pub fn graphic_asset_meta(
    session_id: u64,
    asset_id: u64,
    asset_version: u64,
) -> Result<GraphicAssetMeta, SessionError> {
    STORE
        .get(session_id)?
        .graphic_asset_meta(asset_id, asset_version)
}

pub fn graphic_asset_packet_v1_protobuf(
    session_id: u64,
    asset_id: u64,
    asset_version: u64,
) -> Result<Vec<u8>, SessionError> {
    STORE
        .get(session_id)?
        .graphic_asset_packet_v1_protobuf(asset_id, asset_version)
}

pub fn copy_graphic_asset_rgba(
    session_id: u64,
    asset_id: u64,
    asset_version: u64,
    dst: &mut [u8],
) -> Result<usize, SessionError> {
    STORE
        .get(session_id)?
        .copy_graphic_asset_rgba(asset_id, asset_version, dst)
}

pub fn take_file_download(
    session_id: u64,
    download_id: u64,
    dst: &mut [u8],
) -> Result<usize, SessionError> {
    STORE.get(session_id)?.take_file_download(download_id, dst)
}

pub fn discard_file_download(session_id: u64, download_id: u64) -> Result<(), SessionError> {
    STORE.get(session_id)?.discard_file_download(download_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        MAX_SCROLLBACK_LINES, TerminalProfileAnsiColors, TerminalProfileAppearance,
        TerminalProfileInteraction, TerminalProfileLaunch, TerminalProfileSpecialColors,
        TerminalProfileTerminal, TerminalShellIntegration,
    };
    use par_term_emu_core_rust::cell::Cell;
    use par_term_emu_core_rust::color::NamedColor;
    use par_term_emu_core_rust::terminal::Terminal;
    use std::collections::BTreeMap;
    use std::sync::Barrier;

    #[cfg(unix)]
    #[test]
    fn pty_eio_is_treated_as_a_trusted_transport_eof() {
        assert!(pty_read_error_is_trusted_eof(
            &std::io::Error::from_raw_os_error(libc::EIO)
        ));
        assert!(!pty_read_error_is_trusted_eof(
            &std::io::Error::from_raw_os_error(libc::EBADF)
        ));
    }

    fn pending_test_event(kind: &str, payload: Option<serde_json::Value>) -> TerminalEvent {
        TerminalEvent {
            kind: kind.to_string(),
            session_id: 42,
            payload,
        }
    }

    fn terminal_state_for_file_download_test(terminal: Terminal) -> TerminalState {
        TerminalState {
            terminal,
            transcript: Vec::new(),
            transcript_truncated: false,
            scrollback_offset: 0,
            host_protocol: HostProtocolState::default(),
            graphic_assets: VecDeque::new(),
            graphic_asset_bytes: 0,
            graphic_asset_cache_max_bytes: 1024,
            pending_file_downloads: VecDeque::new(),
            pending_file_download_bytes: 0,
            next_file_download_id: 1,
            replay_checkpoint_boundary: ReplayCheckpointBoundary::default(),
        }
    }

    #[test]
    fn recording_initial_screen_is_atomic_and_round_trips_visible_state() {
        let mut source = Terminal::new(24, 5);
        source.process(
            "\x1b[2J\x1b[Hplain 界 e\u{301}\x1b[2;4H\x1b[31;1mred\x1b[0m\x1b[4;7H".as_bytes(),
        );
        source.process(b"\x1b[?25l");

        let initial_screen = recording_initial_screen(&source);

        assert!(initial_screen.starts_with(b"\x1b[?2026h"));
        assert!(initial_screen.ends_with(b"\x1b[?2026l"));

        let mut replay = Terminal::new(24, 5);
        replay.process(&initial_screen);

        assert_eq!(replay.content(), source.content());
        assert_eq!(replay.cursor().row, source.cursor().row);
        assert_eq!(replay.cursor().col, source.cursor().col);
        assert_eq!(replay.cursor().visible, source.cursor().visible);
        assert!(!replay.synchronized_updates());
    }

    #[test]
    fn osc1337_download_moves_bytes_to_one_shot_session_storage() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_max_transfer_size(ITERM_FILE_DOWNLOAD_MAX_BYTES);
        terminal.process(
            b"\x1b]1337;File=name=Li4vZXNjYXBlZC9yZXBvcnQudHh0;size=5;inline=0:aGVsbG8=\x07",
        );
        let parser_events = terminal.poll_events();
        let mut state = terminal_state_for_file_download_test(terminal);

        let callbacks = callback_events_from_parser_events(&mut state, parser_events, false);

        let [CallbackEvent::FileDownload { payload }] = callbacks.as_slice() else {
            panic!("expected one completed download callback: {callbacks:?}");
        };
        assert_eq!(payload["source"], "iterm1337");
        assert_eq!(payload["transferId"], "1");
        assert_eq!(payload["filename"], "report.txt");
        assert_eq!(payload["size"], 5);
        assert!(state.terminal.get_completed_transfers().is_empty());

        let mut bytes = [0_u8; 5];
        assert_eq!(state.take_file_download(1, &mut bytes).unwrap(), 5);
        assert_eq!(&bytes, b"hello");
        assert!(state.take_file_download(1, &mut bytes).is_err());
        assert_eq!(state.pending_file_download_bytes, 0);
    }

    #[test]
    fn osc1337_report_variable_bridge_resolves_only_session_owned_values() {
        let mut terminal = Terminal::new(93, 31);
        terminal.set_title("native-title".to_string());
        terminal
            .session_variables_mut()
            .set_hostname("host.example");
        terminal.session_variables_mut().set_username("alice");
        terminal.session_variables_mut().set_path("/work/project");
        terminal.set_user_var("gitBranch".to_string(), "feature/report".to_string());

        let resolve = |name: &str| {
            let callback = callback_event_from_parser_event_with_terminal(
                ParserTerminalEvent::ItermReportVariableRequested {
                    name: name.to_string(),
                },
                false,
                Some(&terminal),
            )
            .expect("expected report-variable callback");
            let CallbackEvent::ReportVariableRequest { payload } = callback else {
                panic!("expected report-variable request");
            };
            payload
        };

        assert_eq!(resolve("session.name")["value"], "native-title");
        assert_eq!(resolve("session.columns")["value"], "93");
        assert_eq!(resolve("session.rows")["value"], "31");
        assert_eq!(resolve("session.hostname")["value"], "host.example");
        assert_eq!(resolve("session.username")["value"], "alice");
        assert_eq!(resolve("session.path")["value"], "/work/project");
        assert_eq!(resolve("user.gitBranch")["value"], "feature/report");
        assert!(resolve("session.environment")["value"].is_null());
        assert!(resolve("user.missing")["value"].is_null());
        let user_payload = resolve("user.gitBranch");
        assert_eq!(user_payload["source"], "iterm1337");
        let diagnostics =
            sanitize_diagnostic_event_payload("report_variable_request", Some(&user_payload))
                .expect("expected privacy-safe diagnostics");
        assert_eq!(diagnostics["name"], "user.gitBranch");
        assert_eq!(diagnostics["defined"], true);
        assert_eq!(diagnostics["value_chars"], 14);
        assert!(diagnostics.get("value").is_none());
    }

    #[test]
    fn osc1337_clear_captured_output_maps_to_a_payload_free_product_action() {
        let callback = callback_event_from_parser_event(
            ParserTerminalEvent::ItermClearCapturedOutputRequested,
            false,
        )
        .expect("expected clear-captured-output callback");

        assert!(matches!(callback, CallbackEvent::ClearCapturedOutput));
    }

    #[test]
    fn osc1337_open_url_is_revalidated_and_redacted_before_product_routing() {
        let callback = callback_event_from_parser_event(
            ParserTerminalEvent::ItermOpenUrlRequested {
                url: "https://example.test/private-phase29?token=secret".to_string(),
            },
            false,
        )
        .expect("expected validated open URL request");
        let CallbackEvent::OpenUrlRequest { payload } = callback else {
            panic!("expected open URL callback");
        };
        assert_eq!(payload["source"], "iterm1337");
        assert_eq!(
            payload["url"],
            "https://example.test/private-phase29?token=secret"
        );

        for invalid in [
            "javascript:alert(1)",
            "https://",
            "file:///",
            "file://remote.example/path",
            " https://example.test/space",
            "https://example.test/control\n",
        ] {
            assert!(
                callback_event_from_parser_event(
                    ParserTerminalEvent::ItermOpenUrlRequested {
                        url: invalid.to_string(),
                    },
                    false,
                )
                .is_none(),
                "unsafe URL crossed the native bridge: {invalid:?}"
            );
        }

        let diagnostics = sanitize_diagnostic_event_payload("open_url_request", Some(&payload))
            .expect("expected privacy-safe diagnostics");
        assert_eq!(diagnostics["source"], "iterm1337");
        assert_eq!(diagnostics["scheme"], "https");
        assert!(diagnostics["url_chars"].as_u64().is_some());
        assert!(diagnostics["url_hash"].as_str().is_some());
        let serialized = diagnostics.to_string();
        assert!(!serialized.contains("example.test"));
        assert!(!serialized.contains("secret"));
        assert!(diagnostics.get("url").is_none());
    }

    #[test]
    fn osc1337_attention_is_closed_set_and_privacy_safe_before_product_routing() {
        for (action, expected) in [
            (ItermAttentionAction::Yes, "yes"),
            (ItermAttentionAction::Once, "once"),
            (ItermAttentionAction::No, "no"),
            (ItermAttentionAction::Fireworks, "fireworks"),
        ] {
            let callback = callback_event_from_parser_event(
                ParserTerminalEvent::ItermAttentionRequested { action },
                false,
            )
            .expect("expected validated attention request");
            let CallbackEvent::AttentionRequest { payload } = callback else {
                panic!("expected attention callback");
            };
            assert_eq!(payload["source"], "iterm1337");
            assert_eq!(payload["action"], expected);

            let diagnostics =
                sanitize_diagnostic_event_payload("attention_request", Some(&payload))
                    .expect("expected privacy-safe diagnostics");
            assert_eq!(diagnostics, payload);
        }

        for invalid in ["", "YES", "yes ", "forever", "firework"] {
            assert_eq!(validated_iterm_attention_action(invalid), None);
        }
    }

    #[test]
    fn osc1337_download_rejects_size_mismatch_without_retaining_bytes() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]1337;File=name=YmFkLnR4dA==;size=6;inline=0:aGVsbG8=\x07");
        let parser_events = terminal.poll_events();
        let mut state = terminal_state_for_file_download_test(terminal);

        let callbacks = callback_events_from_parser_events(&mut state, parser_events, false);

        assert!(callbacks.iter().any(|event| matches!(
            event,
            CallbackEvent::FileDownloadFailed { payload }
                if payload["reason"].as_str().is_some_and(|reason| reason.contains("size mismatch"))
        )));
        assert!(state.pending_file_downloads.is_empty());
        assert!(state.terminal.get_completed_transfers().is_empty());
    }

    #[test]
    fn osc1337_request_upload_is_cancelled_without_exposing_host_data() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]1337;RequestUpload=format=tgz\x07");
        let parser_events = terminal.poll_events();
        let mut state = terminal_state_for_file_download_test(terminal);

        let callbacks = callback_events_from_parser_events(&mut state, parser_events, false);

        assert!(matches!(
            callbacks.as_slice(),
            [CallbackEvent::FileUploadDenied { payload }]
                if payload["format"] == "tgz"
        ));
        assert_eq!(state.terminal.drain_responses(), &[0x03]);
    }

    #[test]
    fn pending_file_download_budget_does_not_evict_an_earlier_user_choice() {
        let terminal = Terminal::new(80, 24);
        let mut state = terminal_state_for_file_download_test(terminal);
        let first = vec![1_u8; ITERM_FILE_DOWNLOAD_MAX_BYTES - 1];
        assert!(
            state
                .retain_file_download("first.bin".to_string(), first)
                .is_ok()
        );

        let rejected = state.retain_file_download("second.bin".to_string(), vec![2_u8; 2]);

        assert_eq!(
            rejected.unwrap_err(),
            "pending download memory budget exhausted"
        );
        assert_eq!(state.pending_file_downloads.len(), 1);
        assert_eq!(
            state.pending_file_download_bytes,
            ITERM_FILE_DOWNLOAD_MAX_BYTES - 1
        );
    }

    #[test]
    fn iterm_block_projection_collapses_to_a_mapped_summary_and_pads_the_viewport() {
        let mut terminal = Terminal::with_scrollback(24, 6, 32);
        terminal.process(b"\x1b]1337;Block=id=build;attr=start;type=test\x07");
        terminal.process(b"first\r\ninterior\r\nlast");
        terminal.process(b"\x1b]1337;Block=id=build;attr=end\x07");
        terminal.process(b"\x1b]1337;UpdateBlock=id=build;action=fold\x07");

        let projection = display_projection_for_terminal(&terminal);
        assert!(projection.has_folds());
        assert_eq!(projection.rows.len(), 4);
        assert_eq!(projection.display_index_for_source(0), Some(0));
        assert_eq!(projection.display_index_for_source(2), Some(0));
        assert_eq!(projection.display_index_for_source(3), Some(1));

        let context = FrameBuildContext {
            terminal: &terminal,
            emulation: TerminalEmulation::Xterm256,
            display_projection: &projection,
            viewport_start_row: 0,
            viewport_display_start_row: 0,
            viewport_rows: 6,
            viewport_cols: 24,
            scrollback_len: terminal.grid().scrollback_len(),
            alt_screen_active: false,
        };
        let (rows, hyperlinks, _, dirty, _, _) = build_snapshot_frame(&context);
        assert!(hyperlinks.is_empty());
        assert_eq!(dirty.len(), 1);
        assert_eq!((dirty[0].start, dirty[0].end), (0, 6));
        assert!(rows[0].text.contains("first"));
        assert!(rows[0].text.contains("…1 line…"));
        assert_eq!(
            (rows[0].source_row, rows[0].source_end_row),
            (Some(0), Some(2))
        );
        assert_eq!(
            (rows[1].source_row, rows[1].source_end_row),
            (Some(3), Some(3))
        );
        assert_eq!((rows[5].source_row, rows[5].source_end_row), (None, None));

        let blocks = build_terminal_blocks(&terminal, &projection, 0, 6);
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].id, "build");
        assert_eq!((blocks[0].start_row, blocks[0].end_row), (0, 0));
        assert_eq!(blocks[0].hidden_rows, 2);
    }

    #[test]
    fn iterm_inline_buttons_project_to_viewport_and_hide_inside_folded_content() {
        let mut terminal = Terminal::with_scrollback(24, 6, 32);
        terminal.process(b"\x1b]1337;Block=id=copy-source;attr=start\x07copy me");
        terminal.process(b"\x1b]1337;Block=id=copy-source;attr=end\x07\r\n");
        terminal.process(b"\x1b]1337;Button=type=copy;block=copy-source\x07");
        terminal.process(b"\x1b]1337;Button=type=custom;code=42;icon=star.fill\x1b\\");

        let projection = display_projection_for_terminal(&terminal);
        let buttons = build_terminal_inline_buttons(&terminal, &projection, 0, 6);
        assert_eq!(buttons.len(), 2);
        assert_eq!(
            (buttons[0].kind.as_str(), buttons[0].row, buttons[0].col),
            ("copy", 1, 0)
        );
        assert_eq!(buttons[0].block_id.as_deref(), Some("copy-source"));
        assert_eq!(
            (buttons[1].kind.as_str(), buttons[1].code),
            ("custom", Some(42))
        );
        assert_eq!(buttons[1].icon.as_deref(), Some("star.fill"));
        assert_eq!(buttons[1].col, 4);

        terminal.process(b"\x1b]1337;Button=type=custom\x07");
        let invalidated = build_terminal_inline_buttons(&terminal, &projection, 0, 6);
        assert!(invalidated[0].valid);
        assert!(!invalidated[1].valid);

        let mut folded = Terminal::with_scrollback(24, 6, 32);
        folded.process(b"\x1b]1337;Block=id=fold;attr=start\x07first\r\n");
        folded.process(b"\x1b]1337;Button=type=custom;code=7;icon=star\x07last");
        folded.process(b"\x1b]1337;Block=id=fold;attr=end\x07");
        folded.process(b"\x1b]1337;UpdateBlock=id=fold;action=fold\x07");
        let folded_projection = display_projection_for_terminal(&folded);
        assert!(build_terminal_inline_buttons(&folded, &folded_projection, 0, 6).is_empty());
    }

    #[test]
    fn nested_fold_projection_uses_outer_summary_and_unfold_restores_identity_rows() {
        let mut terminal = Terminal::with_scrollback(20, 6, 32);
        terminal.process(b"\x1b]1337;Block=id=outer;attr=start\x07outer\r\n");
        terminal.process(b"\x1b]1337;Block=id=inner;attr=start\x07inner\r\ninner-end");
        terminal.process(b"\x1b]1337;Block=id=inner;attr=end\x07\r\nouter-end");
        terminal.process(b"\x1b]1337;Block=id=outer;attr=end\x07");
        terminal.process(b"\x1b]1337;UpdateBlock=id=inner;action=fold\x07");
        terminal.process(b"\x1b]1337;UpdateBlock=id=outer;action=fold\x07");

        let folded = display_projection_for_terminal(&terminal);
        assert_eq!(folded.collapsed.len(), 1);
        assert_eq!(folded.collapsed[0].id, "outer");
        assert_eq!(folded.display_index_for_source(3), Some(0));
        let visible_blocks = build_terminal_blocks(&terminal, &folded, 0, 6);
        assert_eq!(
            visible_blocks
                .iter()
                .map(|block| block.id.as_str())
                .collect::<Vec<_>>(),
            vec!["outer"]
        );

        assert!(terminal.set_iterm_block_folded("outer", false));
        assert!(terminal.set_iterm_block_folded("inner", false));
        let unfolded = display_projection_for_terminal(&terminal);
        assert!(!unfolded.has_folds());
        assert_eq!(
            unfolded.rows.len(),
            terminal.grid().scrollback_len() + terminal.size().1
        );
        assert_eq!(unfolded.display_index_for_source(3), Some(3));
    }

    #[test]
    fn rendered_single_line_block_is_exposed_without_becoming_foldable() {
        let mut terminal = Terminal::new(20, 4);
        terminal
            .process(b"\x1b]1337;Block=id=json;attr=start;type=application/json\x07{\"ok\":true}");
        terminal.process(b"\x1b]1337;Block=id=json;attr=end;render=1\x07");

        let projection = display_projection_for_terminal(&terminal);
        let blocks = build_terminal_blocks(&terminal, &projection, 0, 4);

        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].id, "json");
        assert_eq!(blocks[0].block_type.as_deref(), Some("application/json"));
        assert!(blocks[0].rendered);
        assert!(!blocks[0].folded);
        assert_eq!(blocks[0].source_start_row, blocks[0].source_end_row);
        assert!(!terminal.set_iterm_block_folded("json", true));
    }

    #[test]
    fn fold_summary_respects_grapheme_width_and_column_budget() {
        let width_config = WidthConfig::default();
        for columns in 1..=20 {
            let summary = fold_summary_text(
                "你e\u{301}👩\u{200d}💻first",
                "last🏁末",
                7,
                columns,
                &width_config,
            );
            assert!(
                str_width(&summary, &width_config) <= columns,
                "columns={columns} summary={summary:?}"
            );
            assert!(!summary.ends_with('\u{200d}'));
        }
    }

    #[test]
    fn pending_event_queue_enforces_count_and_retains_critical_events() {
        let mut queue = PendingEventQueue::with_limits(4, usize::MAX);
        let mut overflow_diagnostics = 0;
        for event in [
            pending_test_event("exit", None),
            pending_test_event(
                "clipboard_paste_request",
                Some(serde_json::json!({"selection": "c"})),
            ),
        ] {
            overflow_diagnostics += usize::from(queue.push(event).emit_overflow_diagnostic);
        }
        for _ in 0..10 {
            overflow_diagnostics += usize::from(
                queue
                    .push(pending_test_event("bell", None))
                    .emit_overflow_diagnostic,
            );
        }

        assert_eq!(queue.len(), 4);
        assert_eq!(queue.dropped_count, 8);
        assert_eq!(overflow_diagnostics, 1);
        assert!(queue.entries.iter().any(|entry| entry.event.kind == "exit"));
        assert!(
            queue
                .entries
                .iter()
                .any(|entry| entry.event.kind == "clipboard_paste_request")
        );
    }

    #[test]
    fn pending_event_queue_coalesces_zmodem_progress_by_transfer_id() {
        let mut queue = PendingEventQueue::with_limits(8, usize::MAX);
        let progress = |transfer_id: &str, bytes_transferred: u64| {
            pending_test_event(
                "zmodem_progress",
                Some(serde_json::json!({
                    "transferId": transfer_id,
                    "bytesTransferred": bytes_transferred,
                })),
            )
        };

        let _ = queue.push(progress("1", 1));
        let _ = queue.push(progress("1", 9));
        let _ = queue.push(progress("2", 4));

        assert_eq!(queue.len(), 2);
        assert_eq!(queue.next_sequence, 2);
        assert_eq!(
            queue.entries[0].event.payload.as_ref().unwrap()["bytesTransferred"],
            9
        );
        assert_eq!(
            queue.entries[1].event.payload.as_ref().unwrap()["transferId"],
            "2"
        );
    }

    #[test]
    fn pending_event_queue_never_coalesces_progress_across_file_transitions() {
        let mut queue = PendingEventQueue::with_limits(16, usize::MAX);
        let progress = |bytes_transferred: u64| {
            pending_test_event(
                "zmodem_progress",
                Some(serde_json::json!({
                    "transferId": "1",
                    "bytesTransferred": bytes_transferred,
                })),
            )
        };

        let _ = queue.push(progress(1));
        let _ = queue.push(pending_test_event(
            "zmodem_file_completed",
            Some(serde_json::json!({"transferId": "1"})),
        ));
        let _ = queue.push(progress(9));
        let _ = queue.push(pending_test_event(
            "zmodem_file_skipped",
            Some(serde_json::json!({"transferId": "1"})),
        ));
        let _ = queue.push(progress(10));
        let _ = queue.push(progress(11));

        assert_eq!(queue.len(), 5);
        assert_eq!(
            queue
                .entries
                .iter()
                .map(|entry| entry.event.kind.as_str())
                .collect::<Vec<_>>(),
            [
                "zmodem_progress",
                "zmodem_file_completed",
                "zmodem_progress",
                "zmodem_file_skipped",
                "zmodem_progress",
            ]
        );
        assert_eq!(
            queue.entries[4].event.payload.as_ref().unwrap()["bytesTransferred"],
            11
        );
    }

    #[test]
    fn pending_event_queue_bounds_protected_zmodem_events_under_flood() {
        let mut queue = PendingEventQueue::with_limits(3, usize::MAX);
        let protected = [
            "zmodem_detected",
            "zmodem_file_offer",
            "zmodem_started",
            "zmodem_file_completed",
            "zmodem_file_skipped",
            "zmodem_completed",
            "zmodem_failed",
            "zmodem_cancelled",
            ZMODEM_DEFERRED_WRITE_FAILED_KIND,
        ];
        for kind in protected {
            let _ = queue.push(pending_test_event(
                kind,
                Some(serde_json::json!({"transferId": kind})),
            ));
        }
        for _ in 0..100 {
            let _ = queue.push(pending_test_event("bell", None));
        }

        assert_eq!(queue.len(), 3);
        assert_eq!(
            queue
                .entries
                .iter()
                .map(|entry| entry.event.kind.as_str())
                .collect::<Vec<_>>(),
            [
                "zmodem_failed",
                "zmodem_cancelled",
                ZMODEM_DEFERRED_WRITE_FAILED_KIND
            ]
        );
        assert!(queue.aggregate_bytes <= queue.limits.max_bytes);
    }

    #[test]
    fn pending_event_queue_assigns_sequences_before_loss_and_reports_empty_batch() {
        let mut queue = PendingEventQueue::with_limits(0, usize::MAX);

        let result = queue.push(pending_test_event("bell", None));
        let batch = queue
            .drain_event_batch(7)
            .expect("a dropped event must still produce loss metadata");

        assert!(result.emit_overflow_diagnostic);
        assert!(batch.messages.is_empty());
        assert_eq!(batch.session_id, "7");
        assert_eq!(batch.next_sequence, 1);
        assert_eq!(batch.dropped_count, 1);
        assert!(queue.drain_event_batch(7).is_none());
    }

    #[test]
    fn event_envelope_path_correlates_and_consumes_clipboard_host_response_once() {
        let mut queue = PendingEventQueue::default();
        let _ = queue.push(pending_test_event(
            "clipboard_paste_request",
            Some(serde_json::json!({"selection": "c"})),
        ));

        let batch = queue.drain_event_batch(7).expect("Host Request batch");
        assert_eq!(batch.messages.len(), 1);
        assert_eq!(batch.messages[0].message_name, "host_request");
        assert_eq!(
            batch.messages[0].payload.as_ref().unwrap()["request_id"],
            "host:7:0"
        );
        assert_eq!(queue.pending_host_requests.len(), 1);

        let wrong = serde_json::json!({
            "schema_version": 1,
            "contract": "ianvs-host-response-v1",
            "request_id": "host:7:99",
            "session_id": "7",
            "operation": "clipboard.read_text",
            "ok": true,
            "timestamp_micros": 1_300,
            "payload": {"data_base64": "aGVsbG8="}
        })
        .to_string();
        assert!(queue.resolve_host_response(7, &wrong).is_err());
        assert_eq!(queue.pending_host_requests.len(), 1);

        let response = wrong.replace("host:7:99", "host:7:0");
        assert_eq!(
            queue.resolve_host_response(7, &response).unwrap(),
            Some(b"\x1b]52;c;aGVsbG8=\x07".to_vec())
        );
        assert!(queue.resolve_host_response(7, &response).is_err());
        assert!(queue.pending_host_requests.is_empty());
    }

    #[test]
    fn legacy_event_drain_keeps_clipboard_request_shape_and_registers_no_v1_request() {
        let mut queue = PendingEventQueue::default();
        let _ = queue.push(pending_test_event(
            "clipboard_paste_request",
            Some(serde_json::json!({"selection": "c"})),
        ));

        let events = queue.drain();
        assert_eq!(events[0].kind, "clipboard_paste_request");
        assert_eq!(
            events[0].payload,
            Some(serde_json::json!({"selection": "c"}))
        );
        assert!(queue.pending_host_requests.is_empty());
    }

    #[test]
    fn pending_host_request_queue_is_bounded_and_evicts_the_oldest_identity() {
        let mut queue = PendingEventQueue::default();
        for _ in 0..=MAX_PENDING_HOST_REQUESTS {
            let _ = queue.push(pending_test_event(
                "clipboard_paste_request",
                Some(serde_json::json!({"selection": "c"})),
            ));
            let _ = queue.drain_event_batch(7).expect("Host Request batch");
        }

        assert_eq!(queue.pending_host_requests.len(), MAX_PENDING_HOST_REQUESTS);
        assert_eq!(
            queue.pending_host_requests.front().unwrap().request_id,
            "host:7:1"
        );
        assert_eq!(
            queue.pending_host_requests.back().unwrap().request_id,
            "host:7:64"
        );
    }

    #[test]
    fn pending_event_queue_enforces_aggregate_bytes_by_evicting_oldest_coalescible() {
        let bell = pending_test_event("bell", None);
        let clipboard = pending_test_event(
            "clipboard_copy",
            Some(serde_json::json!({"selection": "c", "data": "safe"})),
        );
        let command = pending_test_event(
            "shell_command",
            Some(serde_json::json!({"command": "x".repeat(128)})),
        );
        let retained_bytes =
            terminal_event_wire_size(&clipboard).saturating_add(terminal_event_wire_size(&command));
        let mut queue = PendingEventQueue::with_limits(10, retained_bytes);

        let _ = queue.push(bell);
        let _ = queue.push(clipboard);
        let result = queue.push(command);

        assert!(result.emit_overflow_diagnostic);
        assert_eq!(queue.len(), 2);
        assert!(queue.aggregate_bytes <= retained_bytes);
        assert!(queue.entries.iter().all(|entry| entry.event.kind != "bell"));
        assert!(
            queue
                .entries
                .iter()
                .any(|entry| entry.event.kind == "clipboard_copy")
        );
        let drained = queue.drain();
        assert_eq!(drained.len(), 2);
        assert_eq!(queue.aggregate_bytes, 0);
    }

    #[test]
    fn pending_event_queue_bounds_bell_spam_and_emits_one_bodyless_diagnostic() {
        let mut queue = PendingEventQueue::default();
        let mut overflow_diagnostics = 0;
        for event in [
            pending_test_event("exit", None),
            pending_test_event(
                "clipboard_copy",
                Some(serde_json::json!({"selection": "c", "data": "copy"})),
            ),
            pending_test_event(
                "clipboard_paste_request",
                Some(serde_json::json!({"selection": "c"})),
            ),
        ] {
            overflow_diagnostics += usize::from(queue.push(event).emit_overflow_diagnostic);
        }
        for _ in 0..5000 {
            overflow_diagnostics += usize::from(
                queue
                    .push(pending_test_event("bell", None))
                    .emit_overflow_diagnostic,
            );
        }

        assert_eq!(queue.len(), MAX_PENDING_SESSION_EVENTS);
        assert!(queue.aggregate_bytes <= MAX_PENDING_SESSION_EVENT_BYTES);
        assert_eq!(
            queue.dropped_count,
            5003 - MAX_PENDING_SESSION_EVENTS as u64
        );
        assert_eq!(overflow_diagnostics, 1);
        for kind in ["exit", "clipboard_copy", "clipboard_paste_request"] {
            assert!(
                queue.entries.iter().any(|entry| entry.event.kind == kind),
                "critical {kind} event must survive BEL pressure"
            );
        }

        let diagnostic = event_queue_overflow_diagnostic(42);
        assert_eq!(diagnostic.kind, EVENT_QUEUE_OVERFLOW_DIAGNOSTIC_KIND);
        assert!(diagnostic.payload.is_none());
    }

    #[test]
    fn pending_frame_signal_clears_dirty_after_consuming_a_concurrent_mark() {
        let signal = Arc::new(PendingFrameSignal::new(false));
        let mutation_started = Arc::new(Barrier::new(2));
        let allow_mutation_to_finish = Arc::new(Barrier::new(2));

        let marker = {
            let signal = Arc::clone(&signal);
            let mutation_started = Arc::clone(&mutation_started);
            let allow_mutation_to_finish = Arc::clone(&allow_mutation_to_finish);
            thread::spawn(move || {
                signal.mutate_reader(|work| {
                    work.mark_full_repaint("concurrent_mark");
                    mutation_started.wait();
                    allow_mutation_to_finish.wait();
                });
            })
        };

        mutation_started.wait();
        let taker = {
            let signal = Arc::clone(&signal);
            thread::spawn(move || signal.take())
        };
        allow_mutation_to_finish.wait();

        marker.join().unwrap();
        let (had_dirty_work, had_refresh_hint, pending_work) = taker.join().unwrap();
        assert!(had_dirty_work);
        assert!(had_refresh_hint);
        assert!(pending_work.full_repaint);
        assert!(!signal.is_dirty());
        assert!(!signal.has_refresh_hint());
    }

    #[test]
    fn pending_frame_signal_local_mutation_does_not_publish_a_refresh_hint() {
        let signal = PendingFrameSignal::new(false);

        signal.mutate(|work| work.mark_full_repaint("local_resize"));

        assert!(signal.is_dirty());
        assert!(!signal.has_refresh_hint());
        let (had_dirty_work, had_refresh_hint, pending_work) = signal.take();
        assert!(had_dirty_work);
        assert!(!had_refresh_hint);
        assert!(pending_work.full_repaint);
    }

    #[test]
    fn pending_frame_signal_restore_preserves_deferred_and_concurrent_damage() {
        let signal = PendingFrameSignal::new(false);
        signal.mutate_reader(|work| work.mark_full_repaint("reader_damage"));
        let (_, had_refresh_hint, deferred_work) = signal.take();

        signal.mutate(|work| work.mark_full_repaint("local_resize"));
        signal.restore(deferred_work, had_refresh_hint);

        assert!(signal.is_dirty());
        assert!(signal.has_refresh_hint());
        let (had_dirty_work, had_refresh_hint, pending_work) = signal.take();
        assert!(had_dirty_work);
        assert!(had_refresh_hint);
        assert!(pending_work.full_repaint);
        assert_eq!(
            pending_work.snapshot_fallback_reason.as_deref(),
            Some("reader_damage")
        );
    }

    #[test]
    fn pending_frame_signal_allows_only_one_concurrent_taker_to_consume_work() {
        let signal = Arc::new(PendingFrameSignal::new(false));
        signal.mutate_reader(|work| work.mark_full_repaint("reader_damage"));
        let start = Arc::new(Barrier::new(3));

        let takers = (0..2)
            .map(|_| {
                let signal = Arc::clone(&signal);
                let start = Arc::clone(&start);
                thread::spawn(move || {
                    start.wait();
                    signal.take()
                })
            })
            .collect::<Vec<_>>();
        start.wait();
        let results = takers
            .into_iter()
            .map(|taker| taker.join().unwrap())
            .collect::<Vec<_>>();

        assert_eq!(results.iter().filter(|(dirty, _, _)| *dirty).count(), 1);
        assert_eq!(results.iter().filter(|(_, hint, _)| *hint).count(), 1);
        assert_eq!(
            results
                .iter()
                .filter(|(_, _, work)| work.full_repaint)
                .count(),
            1
        );
        assert!(!signal.is_dirty());
        assert!(!signal.has_refresh_hint());
    }

    fn pending_full_screen_scroll(
        dirty_rows: &[usize],
        viewport_row_shift: i32,
    ) -> PendingFrameWork {
        PendingFrameWork {
            dirty_rows: dirty_rows.iter().copied().collect(),
            scroll_region: Some(PendingScrollRegion {
                top: 0,
                bottom_exclusive: 5,
                delta_rows: viewport_row_shift,
            }),
            ..PendingFrameWork::default()
        }
    }

    fn long_running_lifecycle_profile() -> TerminalProfile {
        TerminalProfile {
            id: "lifecycle-close".to_string(),
            name: "Lifecycle Close".to_string(),
            launch: TerminalProfileLaunch {
                program: "/bin/sh".to_string(),
                args: vec!["-lc".to_string(), "sleep 30".to_string()],
                env: BTreeMap::new(),
                cwd: None,
            },
            connection: TerminalProfileConnection::default(),
            terminal: TerminalProfileTerminal::default(),
            shell_integration: TerminalShellIntegration { enabled: false },
            appearance: TerminalProfileAppearance::default(),
            interaction: TerminalProfileInteraction::default(),
        }
    }

    #[derive(Clone)]
    struct SharedTestWriter(Arc<Mutex<Vec<u8>>>);

    impl Write for SharedTestWriter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.0.lock().extend_from_slice(bytes);
            Ok(bytes.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    struct AlwaysFailWriter;

    impl Write for AlwaysFailWriter {
        fn write(&mut self, _bytes: &[u8]) -> std::io::Result<usize> {
            Err(std::io::Error::other("injected write failure"))
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Err(std::io::Error::other("injected write failure"))
        }
    }

    struct FailAfterWritesWriter {
        writes: Arc<AtomicUsize>,
        successful_writes: usize,
    }

    impl Write for FailAfterWritesWriter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            let index = self.writes.fetch_add(1, Ordering::AcqRel);
            if index < self.successful_writes {
                Ok(bytes.len())
            } else {
                Err(std::io::Error::other("injected ordered write failure"))
            }
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    struct FailOnceCaptureWriter {
        writes: Arc<AtomicUsize>,
        captured: Arc<Mutex<Vec<u8>>>,
    }

    impl Write for FailOnceCaptureWriter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            let index = self.writes.fetch_add(1, Ordering::AcqRel);
            if index == 0 {
                return Err(std::io::Error::other("injected first write failure"));
            }
            self.captured.lock().extend_from_slice(bytes);
            Ok(bytes.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    struct PartialThenFailWriter {
        captured: Arc<Mutex<Vec<u8>>>,
        fail_on: Vec<u8>,
        failing: bool,
    }

    impl Write for PartialThenFailWriter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            if self.failing {
                return Err(std::io::Error::other("injected partial write failure"));
            }
            if bytes == self.fail_on {
                let written = bytes.len().min(3);
                self.captured.lock().extend_from_slice(&bytes[..written]);
                self.failing = true;
                return Ok(written);
            }
            self.captured.lock().extend_from_slice(bytes);
            Ok(bytes.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    struct StateUnlockedWriter {
        session: std::sync::Weak<TerminalSession>,
        captured: Arc<Mutex<Vec<u8>>>,
    }

    impl Write for StateUnlockedWriter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            let session = self.session.upgrade().expect("session must remain alive");
            assert!(
                session.state.try_lock().is_some(),
                "custom button PTY write must happen after releasing terminal state"
            );
            self.captured.lock().extend_from_slice(bytes);
            Ok(bytes.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    struct ZmodemStateUnlockedWriter {
        session: std::sync::Weak<TerminalSession>,
        captured: Arc<Mutex<Vec<u8>>>,
    }

    impl Write for ZmodemStateUnlockedWriter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            let session = self.session.upgrade().expect("session must remain alive");
            assert!(
                session.zmodem.try_lock().is_some(),
                "ZMODEM PTY output must happen after releasing protocol state"
            );
            assert!(
                session.deferred_pty_writes.try_lock().is_some(),
                "ZMODEM PTY output must not hold the deferred-input lock"
            );
            self.captured.lock().extend_from_slice(bytes);
            Ok(bytes.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    struct BlockingTestWriter {
        entered: Option<std::sync::mpsc::SyncSender<()>>,
        release: std::sync::mpsc::Receiver<()>,
        completed: Option<std::sync::mpsc::SyncSender<()>>,
    }

    struct BlockingFailWriter {
        entered: Option<std::sync::mpsc::SyncSender<()>>,
        release: std::sync::mpsc::Receiver<()>,
    }

    impl Write for BlockingFailWriter {
        fn write(&mut self, _bytes: &[u8]) -> std::io::Result<usize> {
            if let Some(entered) = self.entered.take() {
                let _ = entered.send(());
            }
            let _ = self.release.recv();
            Err(std::io::Error::other("injected blocked write failure"))
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    impl Write for BlockingTestWriter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            if let Some(entered) = self.entered.take() {
                let _ = entered.send(());
            }
            let _ = self.release.recv();
            if let Some(completed) = self.completed.take() {
                let _ = completed.send(());
            }
            Ok(bytes.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    struct FirstWriteBlockingCapture {
        entered: Option<std::sync::mpsc::SyncSender<()>>,
        release: Option<std::sync::mpsc::Receiver<()>>,
        captured: Arc<Mutex<Vec<u8>>>,
    }

    impl Write for FirstWriteBlockingCapture {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            if let Some(entered) = self.entered.take() {
                let _ = entered.send(());
                if let Some(release) = self.release.take() {
                    let _ = release.recv();
                }
            }
            self.captured.lock().extend_from_slice(bytes);
            Ok(bytes.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    #[derive(Debug)]
    struct TestChild {
        killed: Arc<AtomicBool>,
    }

    #[derive(Debug)]
    struct TestChildKiller {
        killed: Arc<AtomicBool>,
    }

    #[derive(Debug)]
    struct BlockingExitChild {
        entered: Option<mpsc::SyncSender<()>>,
        release: Arc<Mutex<mpsc::Receiver<()>>>,
        killed: Arc<AtomicBool>,
    }

    impl portable_pty::ChildKiller for TestChildKiller {
        fn kill(&mut self) -> std::io::Result<()> {
            self.killed.store(true, Ordering::SeqCst);
            Ok(())
        }

        fn clone_killer(&self) -> Box<dyn portable_pty::ChildKiller + Send + Sync> {
            Box::new(Self {
                killed: Arc::clone(&self.killed),
            })
        }
    }

    impl portable_pty::ChildKiller for TestChild {
        fn kill(&mut self) -> std::io::Result<()> {
            self.killed.store(true, Ordering::SeqCst);
            Ok(())
        }

        fn clone_killer(&self) -> Box<dyn portable_pty::ChildKiller + Send + Sync> {
            Box::new(TestChildKiller {
                killed: Arc::clone(&self.killed),
            })
        }
    }

    impl portable_pty::Child for TestChild {
        fn try_wait(&mut self) -> std::io::Result<Option<portable_pty::ExitStatus>> {
            Ok(None)
        }

        fn wait(&mut self) -> std::io::Result<portable_pty::ExitStatus> {
            Ok(portable_pty::ExitStatus::with_exit_code(0))
        }

        fn process_id(&self) -> Option<u32> {
            None
        }

        #[cfg(windows)]
        fn as_raw_handle(&self) -> Option<std::os::windows::io::RawHandle> {
            None
        }
    }

    impl portable_pty::ChildKiller for BlockingExitChild {
        fn kill(&mut self) -> std::io::Result<()> {
            self.killed.store(true, Ordering::SeqCst);
            Ok(())
        }

        fn clone_killer(&self) -> Box<dyn portable_pty::ChildKiller + Send + Sync> {
            Box::new(TestChildKiller {
                killed: Arc::clone(&self.killed),
            })
        }
    }

    impl portable_pty::Child for BlockingExitChild {
        fn try_wait(&mut self) -> std::io::Result<Option<portable_pty::ExitStatus>> {
            if let Some(entered) = self.entered.take() {
                let _ = entered.send(());
                let _ = self.release.lock().recv();
            }
            Ok(Some(portable_pty::ExitStatus::with_exit_code(0)))
        }

        fn wait(&mut self) -> std::io::Result<portable_pty::ExitStatus> {
            Ok(portable_pty::ExitStatus::with_exit_code(0))
        }

        fn process_id(&self) -> Option<u32> {
            None
        }

        #[cfg(windows)]
        fn as_raw_handle(&self) -> Option<std::os::windows::io::RawHandle> {
            None
        }
    }

    #[test]
    fn custom_iterm_button_releases_terminal_state_before_pty_write() {
        let session = TerminalSession::new(
            41,
            long_running_lifecycle_profile(),
            None,
            None,
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let button_id = {
            let mut state = session.state.lock();
            state
                .terminal
                .process(b"\x1b]1337;Button=type=custom;code=42;icon=star.fill\x07");
            state.terminal.iterm_buttons()[0].id
        };
        let captured = Arc::new(Mutex::new(Vec::new()));
        *session.writer.lock() = Some(Box::new(StateUnlockedWriter {
            session: Arc::downgrade(&session),
            captured: Arc::clone(&captured),
        }));
        session.pty_writer_available.store(true, Ordering::Release);

        let response = session.activate_iterm_button(button_id).unwrap();

        assert_eq!(response["activated"], true);
        assert_eq!(&*captured.lock(), b"\x1b[?1337;42~");
    }

    #[test]
    fn non_zmodem_host_writes_are_deferred_until_transfer_is_inactive() {
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            42,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(SharedTestWriter(Arc::clone(&captured)))),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        // CRC16-XMODEM of an all-zero ZRQINIT header is also zero.
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        assert!(session.zmodem.lock().is_active());
        let protocol_bytes = captured.lock().len();

        session.write_protocol_reply(b"host-response").unwrap();
        session
            .write_non_zmodem_or_defer(b"button-response", false)
            .unwrap();
        assert_eq!(captured.lock().len(), protocol_bytes);

        session.zmodem.lock().reset();
        let deferred_failure = session.flush_deferred_pty_writes_if_idle();
        session.apply_zmodem_effects(ZmodemEffects::default(), deferred_failure);
        assert_eq!(
            &captured.lock()[protocol_bytes..],
            b"host-responsebutton-response"
        );
    }

    #[test]
    fn opted_out_client_keeps_zmodem_header_as_raw_terminal_output() {
        let session = TerminalSession::new(
            419,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        session.zmodem_enabled.store(false, Ordering::Release);
        let _ = session.poll_events();
        let header = b"**\x18B00000000000000";

        assert_eq!(session.route_pty_output(header), header);
        assert!(!session.zmodem.lock().is_active());
        assert!(session.poll_events().unwrap().is_empty());
        session.close().unwrap();
    }

    #[test]
    fn close_cannot_cross_manager_idle_to_terminal_event_publication() {
        let session = TerminalSession::new(
            4191,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        session.remember_zmodem_active(Some((7, ZmodemDirection::Receive)));
        let transition = session.begin_zmodem_state_transition().unwrap();
        session.remember_zmodem_idle();

        assert!(
            session
                .close()
                .unwrap_err()
                .to_string()
                .contains("zmodem_transfer_active")
        );
        session.apply_zmodem_effects(
            ZmodemEffects {
                events: vec![crate::zmodem::ZmodemEvent {
                    kind: "zmodem_completed",
                    payload: serde_json::json!({
                        "source": "zmodem",
                        "transferId": "7",
                        "direction": "receive",
                    }),
                }],
                ..ZmodemEffects::default()
            },
            None,
        );
        drop(transition);
        assert!(
            session
                .close()
                .unwrap_err()
                .to_string()
                .contains("zmodem_result_pending")
        );
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_completed");
        session.close().unwrap();
    }

    #[test]
    fn zmodem_protocol_output_releases_state_locks_before_pty_io() {
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            420,
            long_running_lifecycle_profile(),
            None,
            None,
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        *session.writer.lock() = Some(Box::new(ZmodemStateUnlockedWriter {
            session: Arc::downgrade(&session),
            captured: Arc::clone(&captured),
        }));

        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );

        assert!(!captured.lock().is_empty());
        assert!(session.zmodem.lock().is_active());
    }

    #[test]
    fn cancel_does_not_wait_for_a_blocked_zmodem_pty_write() {
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        let session = TerminalSession::new(
            421,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(BlockingTestWriter {
                entered: Some(entered_tx),
                release: release_rx,
                completed: None,
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        let route_session = Arc::clone(&session);
        let route = thread::spawn(move || route_session.route_pty_output(b"**\x18B00000000000000"));
        entered_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("protocol writer must enter its injected stall");

        session.cancel_zmodem(1).unwrap();

        assert!(session.zmodem_transport_terminated.load(Ordering::SeqCst));
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_cancelled");
        release_tx.send(()).unwrap();
        assert!(route.join().unwrap().is_empty());
        assert!(session.poll_events().unwrap().is_empty());
    }

    #[test]
    fn writer_actor_cancel_does_not_wait_for_a_blocked_protocol_write() {
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        let session = TerminalSession::new(
            422,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(BlockingTestWriter {
                entered: Some(entered_tx),
                release: release_rx,
                completed: None,
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);

        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        entered_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("writer actor must enter its injected stall");

        let started_at = Instant::now();
        session.cancel_zmodem(1).unwrap();
        assert!(started_at.elapsed() < Duration::from_secs(1));
        assert!(session.zmodem_transport_terminated.load(Ordering::Acquire));
        assert!(
            session
                .poll_events()
                .unwrap()
                .iter()
                .any(|event| event.kind == "zmodem_cancelled")
        );

        release_tx.send(()).unwrap();
        session.close().unwrap();
    }

    #[test]
    fn cancel_never_reports_success_after_receive_publication_starts() {
        let session = TerminalSession::new(
            4221,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let _ = session.poll_events();
        session
            .zmodem_receive_commit_phase
            .store(1, Ordering::Release);

        let error = session.cancel_zmodem(1).unwrap_err();

        assert!(error.to_string().contains("receive_commit_in_progress"));
        assert!(!session.zmodem_transport_terminated.load(Ordering::Acquire));
        assert!(session.poll_events().unwrap().is_empty());
        session
            .zmodem_receive_commit_phase
            .store(0, Ordering::Release);
        session.zmodem.lock().reset();
        session.remember_zmodem_idle();
        session.close().unwrap();
    }

    #[test]
    fn receive_publication_releases_only_after_ordered_effects_are_queued() {
        let session = TerminalSession::new(
            4224,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_PUBLISHING, Ordering::Release);
        let mut effects = ZmodemEffects {
            events: vec![crate::zmodem::ZmodemEvent {
                kind: "zmodem_file_completed",
                payload: serde_json::json!({
                    "source": "zmodem",
                    "transferId": "1",
                    "direction": "receive",
                    "filename": "complete.bin",
                    "size": 3,
                    "completedFiles": 1,
                }),
            }],
            receive_publish_pending: true,
            ..ZmodemEffects::default()
        };

        assert!(session.publish_receive_file_completions(&mut effects));
        assert_eq!(
            session.zmodem_receive_commit_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_PUBLISHING
        );
        assert!(session.poll_events().unwrap().is_empty());
        assert_eq!(effects.events[0].kind, "zmodem_file_completed");
        assert!(effects.receive_publish_pending);

        session.apply_zmodem_effects(effects, None);

        assert_eq!(
            session.zmodem_receive_commit_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_IDLE
        );
        assert_eq!(
            session.poll_events().unwrap()[0].kind,
            "zmodem_file_completed"
        );
        session.close().unwrap();
    }

    #[test]
    fn blocked_manager_io_watchdog_does_not_wait_for_the_sequence_gate() {
        let session = TerminalSession::new(
            4225,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let _ = session.poll_events();
        *session.zmodem_inflight.lock() = Some(ZmodemInFlight {
            transfer_id: 1,
            direction: ZmodemDirection::Receive,
            started_at: Instant::now() - ZMODEM_BLOCKED_IO_TIMEOUT,
        });
        let _sequence = session.zmodem_sequence_gate.lock();

        session.poll_zmodem_timeout();

        assert!(session.zmodem_transport_terminated.load(Ordering::Acquire));
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_failed");
    }

    #[test]
    fn ordinary_write_fails_before_a_terminated_sequence_owner_releases() {
        let session = TerminalSession::new(
            42250,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let _ = session.poll_events();
        *session.zmodem_inflight.lock() = Some(ZmodemInFlight {
            transfer_id: 1,
            direction: ZmodemDirection::Receive,
            started_at: Instant::now() - ZMODEM_BLOCKED_IO_TIMEOUT,
        });
        let sequence = session.zmodem_sequence_gate.lock();

        session.poll_zmodem_timeout();
        assert!(session.zmodem_transport_terminated.load(Ordering::Acquire));
        let write_session = Arc::clone(&session);
        let (result_tx, result_rx) = mpsc::sync_channel(1);
        let writer = thread::spawn(move || {
            let _ = result_tx.send(write_session.write_non_zmodem_or_defer(b"late-input", true));
        });

        let error = result_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("terminated write waited for the stale sequence owner")
            .unwrap_err();
        assert!(error.to_string().contains("PTY transport closed"));
        drop(sequence);
        writer.join().unwrap();
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_failed");
        session.close().unwrap();
    }

    #[test]
    fn recovery_resolution_does_not_wait_for_the_protocol_manager() {
        let session = TerminalSession::new(
            422501,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let manager = session.zmodem.lock();
        let resolve_session = Arc::clone(&session);
        let (result_tx, result_rx) = mpsc::sync_channel(1);
        let resolver = thread::spawn(move || {
            let resolved =
                resolve_session.resolve_zmodem_recovery("00112233445566778899aabbccddeeff");
            let _ = result_tx.send(resolved);
        });

        assert_eq!(
            result_rx
                .recv_timeout(Duration::from_secs(1))
                .expect("recovery resolution waited for the protocol manager"),
            None
        );
        drop(manager);
        resolver.join().unwrap();
        session.close().unwrap();
    }

    #[test]
    fn forced_transport_allows_close_while_stale_transition_is_still_blocked() {
        let session = TerminalSession::new(
            42251,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let _ = session.poll_events();
        let held_transition = session.begin_zmodem_state_transition().unwrap();
        *session.zmodem_inflight.lock() = Some(ZmodemInFlight {
            transfer_id: 1,
            direction: ZmodemDirection::Receive,
            started_at: Instant::now() - ZMODEM_BLOCKED_IO_TIMEOUT,
        });

        session.poll_zmodem_timeout();

        assert!(session.zmodem_transport_terminated.load(Ordering::Acquire));
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_failed");
        assert_eq!(session.close_readiness(), (true, "idle"));
        session.close().unwrap();
        drop(held_transition);
    }

    #[test]
    fn forced_transport_publishes_exit_after_failure_without_reader_barrier() {
        let session = TerminalSession::new(
            42252,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let _ = session.poll_events();
        session
            .pty_reader_exit_barrier_enabled
            .store(true, Ordering::Release);
        let held_transition = session.begin_zmodem_state_transition().unwrap();
        *session.zmodem_inflight.lock() = Some(ZmodemInFlight {
            transfer_id: 1,
            direction: ZmodemDirection::Receive,
            started_at: Instant::now() - ZMODEM_BLOCKED_IO_TIMEOUT,
        });

        session.poll_zmodem_timeout();
        session.exited.store(true, Ordering::Release);
        *session.pending_child_exit.lock() = Some(PendingChildExit {
            exit_code: Some(1),
            payload: serde_json::json!({"code": 1, "success": false}),
        });
        session.publish_pending_child_exit_if_ready();

        let events = session.poll_events().unwrap();
        assert_eq!(
            events
                .iter()
                .map(|event| event.kind.as_str())
                .collect::<Vec<_>>(),
            ["zmodem_failed", "exit"]
        );
        drop(held_transition);
    }

    #[test]
    fn receive_publish_watchdog_abandons_bounded_worker_and_allows_close() {
        let session = TerminalSession::new(
            4226,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_PUBLISHING, Ordering::Release);
        *session.zmodem_receive_publish_started_at.lock() =
            Some(Instant::now() - ZMODEM_BLOCKED_IO_TIMEOUT);
        *session.zmodem_inflight.lock() = Some(ZmodemInFlight {
            transfer_id: 1,
            direction: ZmodemDirection::Receive,
            started_at: Instant::now() - ZMODEM_BLOCKED_IO_TIMEOUT,
        });
        let _sequence = session.zmodem_sequence_gate.lock();

        session.poll_zmodem_timeout();

        assert!(session.zmodem_transport_terminated.load(Ordering::Acquire));
        assert_eq!(
            session.zmodem_receive_commit_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_CANCELLED
        );
        let events = session.poll_events().unwrap();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].kind, "zmodem_failed");
        assert_eq!(events[0].payload.as_ref().unwrap()["reason"], "timeout");
        session.close().unwrap();
    }

    #[test]
    fn receive_publish_watchdog_cannot_abandon_a_linearized_result() {
        let session = TerminalSession::new(
            4227,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_RESULT_READY, Ordering::Release);
        *session.zmodem_receive_publish_started_at.lock() =
            Some(Instant::now() - ZMODEM_BLOCKED_IO_TIMEOUT);

        session.poll_zmodem_timeout();

        // Reproduce the narrower race where a watchdog already decided to
        // force termination immediately before the worker published READY.
        session.force_zmodem_terminal(1, ZmodemDirection::Receive, false);

        assert!(!session.zmodem_transport_terminated.load(Ordering::Acquire));
        assert_eq!(
            session.zmodem_receive_commit_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_RESULT_READY
        );
        assert!(
            session
                .close()
                .unwrap_err()
                .to_string()
                .contains("receive_publication_in_progress")
        );

        session.apply_zmodem_effects(
            ZmodemEffects {
                events: vec![crate::zmodem::ZmodemEvent {
                    kind: "zmodem_file_completed",
                    payload: serde_json::json!({
                        "source": "zmodem",
                        "transferId": "1",
                        "direction": "receive",
                        "filename": "complete.bin",
                        "size": 3,
                        "completedFiles": 1,
                    }),
                }],
                receive_publish_pending: true,
                ..ZmodemEffects::default()
            },
            None,
        );
        assert_eq!(
            session.zmodem_receive_commit_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_IDLE
        );
        session.close().unwrap();
    }

    #[test]
    fn resource_sampler_survives_child_exit_until_receive_publication_is_reaped() {
        let session = TerminalSession::new(
            4228,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        session.exited.store(true, Ordering::Release);

        // Child wait can observe exit before the PTY reader has consumed its
        // final buffered bytes. The sampler remains the publication pump
        // until that reader boundary is explicit.
        assert!(!session.resource_sampler_should_stop());
        session.pty_reader_closed.store(true, Ordering::Release);

        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_PUBLISHING, Ordering::Release);
        assert!(!session.resource_sampler_should_stop());

        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_RESULT_READY, Ordering::Release);
        assert!(!session.resource_sampler_should_stop());

        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_IDLE, Ordering::Release);
        session
            .zmodem_active_transfer_id
            .store(4228, Ordering::Release);
        assert!(!session.resource_sampler_should_stop());
        session
            .zmodem_active_transfer_id
            .store(0, Ordering::Release);
        session.zmodem_draining.store(true, Ordering::Release);
        assert!(!session.resource_sampler_should_stop());
        session.zmodem_draining.store(false, Ordering::Release);
        assert!(session.resource_sampler_should_stop());
    }

    #[test]
    fn close_readiness_is_a_non_destructive_snapshot_of_retryable_gates() {
        let session = TerminalSession::new(
            42281,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert_eq!(session.close_readiness(), (true, "idle"));

        session
            .zmodem_state_transitions_inflight
            .store(1, Ordering::Release);
        assert_eq!(session.close_readiness(), (false, "zmodem_transition"));
        assert!(!session.exited.load(Ordering::Acquire));
        session
            .zmodem_state_transitions_inflight
            .store(0, Ordering::Release);
        assert_eq!(session.close_readiness(), (true, "idle"));
        assert!(!session.exited.load(Ordering::Acquire));
    }

    #[test]
    fn pollable_reader_barrier_keeps_exit_last_and_accepts_tail_output() {
        let session = TerminalSession::new(
            4229,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        session
            .pty_reader_exit_barrier_enabled
            .store(true, Ordering::Release);
        session.exited.store(true, Ordering::Release);
        *session.pending_child_exit.lock() = Some(PendingChildExit {
            exit_code: Some(0),
            payload: serde_json::json!({"code": 0, "success": true}),
        });

        session.publish_pending_child_exit_if_ready();
        assert!(session.events.lock().entries.is_empty());
        assert_eq!(
            session.route_pty_output(b"tail-after-wait"),
            b"tail-after-wait"
        );

        session.on_pty_reader_closed(true);
        assert_eq!(session.events.lock().entries.len(), 1);
        assert_eq!(session.events.lock().entries[0].event.kind, "exit");
        let events = session.poll_events().unwrap();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].kind, "exit");
        assert!(session.route_pty_output(b"too-late").is_empty());
    }

    #[test]
    fn pending_exit_is_published_after_zmodem_finalization_clears() {
        let session = TerminalSession::new(
            4231,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        session.pty_reader_closed.store(true, Ordering::Release);
        session.exited.store(true, Ordering::Release);
        session.zmodem_draining.store(true, Ordering::Release);
        *session.pending_child_exit.lock() = Some(PendingChildExit {
            exit_code: Some(0),
            payload: serde_json::json!({"code": 0, "success": true}),
        });

        session.publish_pending_child_exit_if_ready();
        assert!(session.events.lock().entries.is_empty());
        assert!(!session.resource_sampler_should_stop());

        session.zmodem_draining.store(false, Ordering::Release);
        session.publish_pending_child_exit_if_ready();
        assert_eq!(session.events.lock().entries.len(), 1);
        assert_eq!(session.events.lock().entries[0].event.kind, "exit");
        assert!(session.resource_sampler_should_stop());
    }

    #[test]
    fn refresh_hint_covers_pending_and_queued_exit_without_an_idle_gap() {
        let session = TerminalSession::new(
            4232,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        let _ = session.take_frame_diff();
        session
            .pty_reader_exit_barrier_enabled
            .store(true, Ordering::Release);
        session.exited.store(true, Ordering::Release);
        *session.pending_child_exit.lock() = Some(PendingChildExit {
            exit_code: Some(0),
            payload: serde_json::json!({"code": 0, "success": true}),
        });

        assert_eq!(session.refresh_hint_flags(), REFRESH_HINT_EXIT_PENDING);
        session.on_pty_reader_closed(true);
        assert_eq!(session.refresh_hint_flags(), REFRESH_HINT_EVENT_PENDING);
        assert_eq!(session.poll_events().unwrap()[0].kind, "exit");
        assert_eq!(session.refresh_hint_flags(), 0);
    }

    #[test]
    fn forced_transport_keeps_exit_hint_live_until_child_exit_is_observed() {
        let session = TerminalSession::new(
            42321,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        let _ = session.take_frame_diff();
        session
            .zmodem_transport_terminated
            .store(true, Ordering::Release);

        assert_eq!(session.refresh_hint_flags(), REFRESH_HINT_EXIT_PENDING);
        session.exited.store(true, Ordering::Release);
        assert_eq!(session.refresh_hint_flags(), 0);
        session.close().unwrap();
    }

    #[test]
    fn concurrent_child_exit_observers_publish_exactly_once_without_hint_gap() {
        let (entered_tx, entered_rx) = mpsc::sync_channel(1);
        let (release_tx, release_rx) = mpsc::sync_channel(1);
        let session = TerminalSession::new(
            42322,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            Some(Box::new(BlockingExitChild {
                entered: Some(entered_tx),
                release: Arc::new(Mutex::new(release_rx)),
                killed: Arc::new(AtomicBool::new(false)),
            })),
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        session.events.lock().drain();
        let _ = session.take_frame_diff();
        session
            .zmodem_transport_terminated
            .store(true, Ordering::Release);

        let first_session = Arc::clone(&session);
        let first = thread::spawn(move || first_session.observe_child_exit());
        entered_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("first observer did not enter child try_wait");
        let second_session = Arc::clone(&session);
        let second = thread::spawn(move || second_session.observe_child_exit());
        let hint_session = Arc::clone(&session);
        let hint = thread::spawn(move || hint_session.refresh_hint_flags());

        release_tx.send(()).unwrap();
        first.join().unwrap().unwrap();
        second.join().unwrap().unwrap();
        assert_ne!(
            hint.join().unwrap() & (REFRESH_HINT_EXIT_PENDING | REFRESH_HINT_EVENT_PENDING),
            0
        );
        let events = session.poll_events().unwrap();
        assert_eq!(
            events.iter().filter(|event| event.kind == "exit").count(),
            1
        );
        assert_eq!(session.refresh_hint_flags(), 0);
        session.close().unwrap();
    }

    #[test]
    fn unpollable_platform_does_not_wait_for_a_close_driven_reader_eof() {
        let session = TerminalSession::new(
            4230,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        session.exited.store(true, Ordering::Release);
        *session.pending_child_exit.lock() = Some(PendingChildExit {
            exit_code: Some(0),
            payload: serde_json::json!({"code": 0, "success": true}),
        });

        session.publish_pending_child_exit_if_ready();

        let events = session.poll_events().unwrap();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].kind, "exit");
    }

    #[test]
    fn stale_cancel_during_busy_transport_cannot_invalidate_the_active_transfer() {
        let session = TerminalSession::new(
            4223,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let transport = session.zmodem_transport_gate.lock();

        let error = session.cancel_zmodem(2).unwrap_err();

        assert!(error.to_string().contains("zmodem_transport_busy"));
        assert_eq!(
            session.zmodem_receive_commit_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_IDLE
        );
        assert_eq!(session.zmodem_operation_epoch.load(Ordering::Acquire), 0);
        drop(transport);
        session.zmodem.lock().reset();
        session.remember_zmodem_idle();
        session.close().unwrap();
    }

    #[test]
    fn close_returns_busy_promptly_while_receive_publication_has_not_returned() {
        let session = TerminalSession::new(
            4222,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_PUBLISHING, Ordering::Release);
        let started = Instant::now();
        let error = session.close().unwrap_err();

        assert!(started.elapsed() < Duration::from_millis(250));
        assert!(
            error
                .to_string()
                .contains("receive_publication_in_progress")
        );
        assert!(!session.exited.load(Ordering::Acquire));
        assert_eq!(
            session.zmodem_receive_commit_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_PUBLISHING
        );

        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_IDLE, Ordering::Release);
        session.close().unwrap();
    }

    #[test]
    fn resource_sampler_releases_scanner_prefix_within_the_protocol_deadline() {
        let session = TerminalSession::new(
            423,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert!(session.route_pty_output(b"*").is_empty());
        let sampler = TerminalSession::start_resource_sampler(&session);
        let deadline = Instant::now() + Duration::from_millis(500);

        loop {
            if session.state.lock().transcript == b"*" {
                break;
            }
            assert!(
                Instant::now() < deadline,
                "scanner prefix inherited the one-second resource cadence"
            );
            thread::sleep(Duration::from_millis(5));
        }

        session.exited.store(true, Ordering::SeqCst);
        session.pty_reader_closed.store(true, Ordering::Release);
        sampler.thread().unpark();
        sampler.join().unwrap();
    }

    #[test]
    fn scanner_timeout_cannot_overtake_reader_passthrough_commit() {
        let session = TerminalSession::new(
            4232,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        let (routed_tx, routed_rx) = mpsc::sync_channel(1);
        let (release_tx, release_rx) = mpsc::sync_channel(1);
        let reader_session = Arc::clone(&session);
        let reader = thread::spawn(move || {
            let _passthrough = reader_session.zmodem_passthrough_gate.lock();
            let bytes = reader_session.route_pty_output(b"earlier*");
            routed_tx.send(()).unwrap();
            release_rx.recv().unwrap();
            reader_session.recording.lock().record_pty_output(&bytes);
            reader_session.ingest_pty_output(&bytes, true);
        });
        routed_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        // The scanner's held-prefix deadline is 100 ms.
        thread::sleep(Duration::from_millis(110));

        let (timeout_done_tx, timeout_done_rx) = mpsc::sync_channel(1);
        let timeout_session = Arc::clone(&session);
        let timeout = thread::spawn(move || {
            timeout_session.poll_zmodem_timeout();
            timeout_done_tx.send(()).unwrap();
        });
        assert!(
            timeout_done_rx
                .recv_timeout(Duration::from_millis(20))
                .is_err(),
            "timeout must wait for the earlier reader commit"
        );
        release_tx.send(()).unwrap();
        reader.join().unwrap();
        timeout_done_rx
            .recv_timeout(Duration::from_secs(1))
            .unwrap();
        timeout.join().unwrap();

        assert_eq!(session.state.lock().transcript, b"earlier*");
    }

    #[test]
    fn terminal_reply_before_detection_precedes_the_first_zmodem_wire() {
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            4231,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(SharedTestWriter(Arc::clone(&captured)))),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();

        assert!(
            session
                .route_pty_output(b"\x1b[6n**\x18B00000000000000")
                .is_empty()
        );

        let wire = captured.lock();
        assert!(wire.starts_with(b"\x1b[1;1R"));
        assert!(wire.len() > b"\x1b[1;1R".len());
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_detected");
    }

    #[test]
    fn timeout_pump_does_not_overtake_a_blocked_zmodem_pty_write() {
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        let session = TerminalSession::new(
            423,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(BlockingTestWriter {
                entered: Some(entered_tx),
                release: release_rx,
                completed: None,
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        let route_session = Arc::clone(&session);
        let route = thread::spawn(move || route_session.route_pty_output(b"**\x18B00000000000000"));
        entered_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("protocol writer must enter its injected stall");

        let started = Instant::now();
        session.poll_zmodem_timeout();

        assert!(started.elapsed() < Duration::from_millis(250));
        assert!(session.zmodem_transport_gate.try_lock().is_some());
        assert!(session.poll_events().unwrap().is_empty());
        release_tx.send(()).unwrap();
        assert!(route.join().unwrap().is_empty());
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_detected");
    }

    #[test]
    fn spawned_zmodem_writer_keeps_the_pty_reader_path_nonblocking() {
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        let (completed_tx, completed_rx) = std::sync::mpsc::sync_channel(1);
        let session = TerminalSession::new(
            424,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(BlockingTestWriter {
                entered: Some(entered_tx),
                release: release_rx,
                completed: Some(completed_tx),
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        let _ = session.poll_events();

        let started = Instant::now();
        let passthrough = session.route_pty_output(b"**\x18B00000000000000");

        assert!(passthrough.is_empty());
        assert!(started.elapsed() < Duration::from_millis(250));
        entered_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("worker must own the injected PTY stall");
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_detected");
        release_tx.send(()).unwrap();
        completed_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("worker must finish after the PTY stall is released");
        session.zmodem.lock().reset();
        session.remember_zmodem_idle();
        session.close().unwrap();
    }

    #[test]
    fn writer_actor_stall_is_watched_even_after_transport_gate_is_released() {
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        let session = TerminalSession::new(
            4241,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(BlockingTestWriter {
                entered: Some(entered_tx),
                release: release_rx,
                completed: None,
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        let owner = Some((91, ZmodemDirection::Send));
        let waiter_session = Arc::clone(&session);
        let waiter = thread::spawn(move || {
            let transport = waiter_session.zmodem_transport_gate.lock();
            waiter_session.write_zmodem_wire_releasing_transport(
                b"OO",
                transport,
                owner,
                true,
                ZmodemWireJobKind::Protocol,
            )
        });
        entered_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        assert!(session.zmodem_transport_gate.try_lock().is_some());
        session
            .zmodem_wire_inflight
            .lock()
            .as_mut()
            .unwrap()
            .started_at = Instant::now() - ZMODEM_BLOCKED_IO_TIMEOUT;

        session.poll_zmodem_timeout();

        assert!(session.zmodem_transport_terminated.load(Ordering::Acquire));
        assert_eq!(waiter.join().unwrap(), Err(ZmodemWireError::Io));
        let events = session.poll_events().unwrap();
        assert_eq!(events.last().unwrap().kind, "zmodem_failed");
        assert_eq!(
            events.last().unwrap().payload.as_ref().unwrap()["reason"],
            "timeout"
        );
        release_tx.send(()).unwrap();
        session.close().unwrap();
    }

    #[test]
    fn deferred_pty_bytes_follow_queued_final_protocol_bytes() {
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            425,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(FirstWriteBlockingCapture {
                entered: Some(entered_tx),
                release: Some(release_rx),
                captured: Arc::clone(&captured),
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        let _ = session.poll_events();

        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        entered_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("protocol write must be queued first");
        session
            .write_non_zmodem_or_defer(b"deferred-user-input", true)
            .unwrap();
        session.zmodem.lock().reset();
        session.remember_zmodem_idle();
        let flush_session = Arc::clone(&session);
        let flush = thread::spawn(move || flush_session.flush_deferred_pty_writes_if_idle());

        release_tx.send(()).unwrap();
        assert_eq!(flush.join().unwrap(), None);
        let captured = captured.lock();
        assert!(captured.len() > b"deferred-user-input".len());
        assert!(captured.ends_with(b"deferred-user-input"));
        drop(captured);
        session.close().unwrap();
    }

    #[test]
    fn deferred_actor_write_failure_does_not_reenter_held_queue_lock() {
        let session = TerminalSession::new(
            4251,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(AlwaysFailWriter)),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        session
            .deferred_pty_writes
            .lock()
            .push(b"queued-before-broken-pipe", true)
            .unwrap();
        let flush_session = Arc::clone(&session);
        let (result_tx, result_rx) = mpsc::sync_channel(1);
        thread::spawn(move || {
            let _ = result_tx.send(flush_session.flush_deferred_pty_writes_if_idle());
        });

        let failure = result_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("actor failure must not deadlock on deferred queue")
            .expect("failed deferred write must be reported");
        assert_eq!(failure.queued_chunks, 1);
        assert_eq!(failure.queued_bytes, b"queued-before-broken-pipe".len());
        assert!(session.zmodem_transport_terminated.load(Ordering::Acquire));
        session.close().unwrap();
    }

    #[test]
    fn ordinary_actor_failure_terminalizes_a_transfer_queued_behind_it_once() {
        let (entered_tx, entered_rx) = mpsc::sync_channel(1);
        let (release_tx, release_rx) = mpsc::sync_channel(1);
        let session = TerminalSession::new(
            4252,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(BlockingFailWriter {
                entered: Some(entered_tx),
                release: release_rx,
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        let _ = session.poll_events();
        let write_session = Arc::clone(&session);
        let ordinary =
            thread::spawn(move || write_session.write_non_zmodem_or_defer(b"ordinary-first", true));
        entered_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("ordinary actor write must block first");

        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_detected");
        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_PUBLISHING, Ordering::Release);
        release_tx.send(()).unwrap();
        assert!(ordinary.join().unwrap().is_err());

        let deadline = Instant::now() + Duration::from_secs(1);
        let mut terminal_events = Vec::new();
        while terminal_events.is_empty() && Instant::now() < deadline {
            terminal_events.extend(session.poll_events().unwrap().into_iter().filter(|event| {
                matches!(
                    event.kind.as_str(),
                    "zmodem_completed" | "zmodem_failed" | "zmodem_cancelled"
                )
            }));
            thread::yield_now();
        }
        assert_eq!(terminal_events.len(), 1);
        assert_eq!(terminal_events[0].kind, "zmodem_failed");
        assert_eq!(
            terminal_events[0].payload.as_ref().unwrap()["transferId"],
            "1"
        );
        assert!(session.zmodem_wire_tx.lock().is_none());
        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_IDLE, Ordering::Release);
        session.close().unwrap();
    }

    #[test]
    fn duplicate_native_terminal_outcomes_are_suppressed_per_transfer() {
        let session = TerminalSession::new(
            4253,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        for kind in ["zmodem_cancelled", "zmodem_failed"] {
            session.push_event(
                kind,
                Some(serde_json::json!({
                    "source": "zmodem",
                    "transferId": "88",
                    "direction": "send",
                })),
            );
        }

        let events = session.poll_events().unwrap();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].kind, "zmodem_cancelled");
        session.close().unwrap();
    }

    #[test]
    fn cancellation_does_not_suppress_later_shell_output_or_transfer_detection() {
        let session = TerminalSession::new(
            426,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let detected = session.poll_events().unwrap();
        assert_eq!(detected[0].kind, "zmodem_detected");

        session.cancel_zmodem(1).unwrap();
        session.on_pty_reader_closed(true);
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_cancelled");
        assert_eq!(session.route_pty_output(b"prompt$ "), b"prompt$ ");

        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let next = session.poll_events().unwrap();
        assert_eq!(next[0].kind, "zmodem_detected");
        assert_eq!(next[0].payload.as_ref().unwrap()["transferId"], "2");
    }

    #[test]
    fn terminal_protocol_wire_is_confirmed_before_completion_can_be_published() {
        let session = TerminalSession::new(
            427,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(AlwaysFailWriter)),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        let owner = Some((9, ZmodemDirection::Send));
        let transport = session.zmodem_transport_gate.lock();

        let result = session.write_zmodem_wire_releasing_transport(
            b"OO",
            transport,
            owner,
            true,
            ZmodemWireJobKind::Protocol,
        );

        assert_eq!(result, Err(ZmodemWireError::Io));
        let effects = session.fail_zmodem_after_wire_error_for(owner);
        session.apply_zmodem_effects(effects, None);
        let events = session.poll_events().unwrap();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].kind, "zmodem_failed");
        assert_eq!(events[0].payload.as_ref().unwrap()["transferId"], "9");
        assert_eq!(events[0].payload.as_ref().unwrap()["reason"], "io_error");
    }

    #[test]
    fn asynchronous_wire_failure_is_ordered_after_detection() {
        let session = TerminalSession::new(
            432,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(AlwaysFailWriter)),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);

        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let deadline = Instant::now() + Duration::from_secs(1);
        let mut events = Vec::new();
        while events.len() < 2 && Instant::now() < deadline {
            events.extend(session.poll_events().unwrap());
            std::thread::yield_now();
        }

        assert_eq!(
            events
                .iter()
                .map(|event| event.kind.as_str())
                .collect::<Vec<_>>(),
            ["zmodem_detected", "zmodem_failed"]
        );
        assert!(!session.zmodem.lock().is_active());
        session.close().unwrap();
    }

    #[test]
    fn first_async_writer_io_failure_rejects_every_later_job_before_notification() {
        let writes = Arc::new(AtomicUsize::new(0));
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            4321,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(FailOnceCaptureWriter {
                writes: Arc::clone(&writes),
                captured: Arc::clone(&captured),
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        let owner = Some((901, ZmodemDirection::Send));
        let sequence = session.zmodem_sequence_gate.lock();
        session
            .enqueue_zmodem_wire_job(ZmodemWireJob {
                bytes: b"first-fails".to_vec(),
                owner,
                kind: ZmodemWireJobKind::Protocol,
                completion: None,
            })
            .unwrap();
        let (completion_tx, completion_rx) = mpsc::sync_channel(1);
        session
            .enqueue_zmodem_wire_job(ZmodemWireJob {
                bytes: b"must-not-write".to_vec(),
                owner,
                kind: ZmodemWireJobKind::Protocol,
                completion: Some(completion_tx),
            })
            .unwrap();

        assert_eq!(
            completion_rx.recv_timeout(Duration::from_secs(1)).unwrap(),
            Err(ZmodemWireError::Io)
        );
        assert_eq!(writes.load(Ordering::Acquire), 1);
        assert!(captured.lock().is_empty());
        assert!(session.zmodem_transport_terminated.load(Ordering::Acquire));
        assert!(session.poll_events().unwrap().is_empty());

        drop(sequence);
        let deadline = Instant::now() + Duration::from_secs(1);
        let events = loop {
            let events = session.poll_events().unwrap();
            if !events.is_empty() {
                break events;
            }
            assert!(Instant::now() < deadline);
            thread::yield_now();
        };
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].kind, "zmodem_failed");
        assert_eq!(events[0].payload.as_ref().unwrap()["transferId"], "901");
        assert_eq!(events[0].payload.as_ref().unwrap()["reason"], "io_error");
        assert!(session.route_pty_output(b"late-peer-completion").is_empty());
        assert!(session.poll_events().unwrap().is_empty());
        session.close().unwrap();
    }

    #[test]
    fn asynchronous_accept_wire_failure_is_ordered_after_started() {
        let writes = Arc::new(AtomicUsize::new(0));
        let session = TerminalSession::new(
            433,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(FailAfterWritesWriter {
                writes: Arc::clone(&writes),
                successful_writes: 0,
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events();
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        assert!(
            session
                .route_pty_output(b"**\x18B0100000000aa51")
                .is_empty()
        );
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_detected");
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("payload.bin");
        std::fs::write(&path, b"payload").unwrap();

        session.accept_zmodem_send(1, &[path]).unwrap();
        let deadline = Instant::now() + Duration::from_secs(1);
        let mut events = Vec::new();
        while events.len() < 2 && Instant::now() < deadline {
            events.extend(session.poll_events().unwrap());
            std::thread::yield_now();
        }

        assert_eq!(writes.load(Ordering::Acquire), 1);
        assert_eq!(
            events
                .iter()
                .map(|event| event.kind.as_str())
                .collect::<Vec<_>>(),
            ["zmodem_started", "zmodem_failed"]
        );
        session.close().unwrap();
    }

    #[test]
    fn public_user_write_cannot_overtake_queued_terminal_protocol_wire() {
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            428,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(FirstWriteBlockingCapture {
                entered: Some(entered_tx),
                release: Some(release_rx),
                captured: Arc::clone(&captured),
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        let transport = session.zmodem_transport_gate.lock();
        session
            .write_zmodem_wire_releasing_transport(
                b"final-OO",
                transport,
                Some((12, ZmodemDirection::Send)),
                false,
                ZmodemWireJobKind::Protocol,
            )
            .unwrap();
        entered_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        let writer_session = Arc::clone(&session);
        let later = thread::spawn(move || writer_session.write(b"user-input"));

        release_tx.send(()).unwrap();
        later.join().unwrap().unwrap();
        assert_eq!(&*captured.lock(), b"final-OOuser-input");
        session.close().unwrap();
    }

    #[test]
    fn cancelled_generation_discards_queued_protocol_jobs_before_ordered_can() {
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            429,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(FirstWriteBlockingCapture {
                entered: Some(entered_tx),
                release: Some(release_rx),
                captured: Arc::clone(&captured),
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        let owner = Some((14, ZmodemDirection::Send));
        for bytes in [b"old-inflight".as_slice(), b"old-queued"] {
            session
                .enqueue_zmodem_wire_job(ZmodemWireJob {
                    bytes: bytes.to_vec(),
                    owner,
                    kind: ZmodemWireJobKind::Protocol,
                    completion: None,
                })
                .unwrap();
        }
        entered_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        session
            .zmodem_operation_epoch
            .fetch_add(1, Ordering::AcqRel);
        let (completion_tx, completion_rx) = mpsc::sync_channel(1);
        session
            .enqueue_zmodem_wire_job(ZmodemWireJob {
                bytes: b"CAN".to_vec(),
                owner,
                kind: ZmodemWireJobKind::Cancel,
                completion: Some(completion_tx),
            })
            .unwrap();

        release_tx.send(()).unwrap();
        assert_eq!(
            completion_rx.recv_timeout(Duration::from_secs(1)).unwrap(),
            Ok(())
        );
        assert_eq!(&*captured.lock(), b"old-inflightCAN");
        session.close().unwrap();
    }

    #[test]
    fn zmodem_writer_queue_is_bounded_by_bytes_not_job_count() {
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        let session = TerminalSession::new(
            430,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(BlockingTestWriter {
                entered: Some(entered_tx),
                release: release_rx,
                completed: None,
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        session
            .enqueue_zmodem_wire_job(ZmodemWireJob {
                bytes: vec![1],
                owner: Some((15, ZmodemDirection::Send)),
                kind: ZmodemWireJobKind::Protocol,
                completion: None,
            })
            .unwrap();
        entered_rx.recv_timeout(Duration::from_secs(1)).unwrap();

        let overflow = session.enqueue_zmodem_wire_job(ZmodemWireJob {
            bytes: vec![2; ZMODEM_WIRE_MAX_QUEUED_BYTES],
            owner: Some((15, ZmodemDirection::Send)),
            kind: ZmodemWireJobKind::Protocol,
            completion: None,
        });
        assert_eq!(overflow, Err(ZmodemWireError::QueueLimit));
        release_tx.send(()).unwrap();
        session.close().unwrap();
    }

    #[test]
    fn oversized_ordinary_write_uses_exclusive_queue_reservation() {
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            4301,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(SharedTestWriter(Arc::clone(&captured)))),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        let bytes = vec![0x5a; ZMODEM_WIRE_MAX_QUEUED_BYTES + 17];

        session.write(&bytes).unwrap();

        assert_eq!(&*captured.lock(), &bytes);
        assert_eq!(session.zmodem_wire_queued_bytes.load(Ordering::Acquire), 0);
        session.close().unwrap();
    }

    #[test]
    fn blocked_ordinary_write_does_not_block_pty_output_drain() {
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        let session = TerminalSession::new(
            4302,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(BlockingTestWriter {
                entered: Some(entered_tx),
                release: release_rx,
                completed: None,
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        let writer_session = Arc::clone(&session);
        let write = thread::spawn(move || writer_session.write(b"blocked ordinary input"));
        entered_rx.recv_timeout(Duration::from_secs(1)).unwrap();

        let (routed_tx, routed_rx) = std::sync::mpsc::sync_channel(1);
        let reader_session = Arc::clone(&session);
        let route = thread::spawn(move || {
            let output = reader_session.route_pty_output(b"remote output");
            routed_tx.send(output).unwrap();
        });
        assert_eq!(
            routed_rx.recv_timeout(Duration::from_millis(250)).unwrap(),
            b"remote output"
        );

        release_tx.send(()).unwrap();
        write.join().unwrap().unwrap();
        route.join().unwrap();
        session.close().unwrap();
    }

    #[test]
    fn blocked_writer_actor_does_not_retain_the_terminal_session() {
        let (entered_tx, entered_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        let session = TerminalSession::new(
            431,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(BlockingTestWriter {
                entered: Some(entered_tx),
                release: release_rx,
                completed: None,
            })),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let handle = TerminalSession::start_zmodem_writer(&session).unwrap();
        session.worker_handles.lock().zmodem_writer = Some(handle);
        session
            .enqueue_zmodem_wire_job(ZmodemWireJob {
                bytes: b"blocked".to_vec(),
                owner: Some((16, ZmodemDirection::Send)),
                kind: ZmodemWireJobKind::Protocol,
                completion: None,
            })
            .unwrap();
        entered_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        let weak = Arc::downgrade(&session);

        drop(session);
        assert!(weak.upgrade().is_none());
        release_tx.send(()).unwrap();
    }

    #[test]
    fn writer_thread_spawn_failure_kills_the_unpublished_child_session() {
        let killed = Arc::new(AtomicBool::new(false));
        let session = TerminalSession::new(
            4254,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            Some(Box::new(TestChild {
                killed: Arc::clone(&killed),
            })),
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        FAIL_NEXT_ZMODEM_WRITER_THREAD_SPAWN.with(|flag| flag.set(true));

        let error = TerminalSession::start_zmodem_writer_or_teardown(&session).unwrap_err();

        assert!(error.to_string().contains("writer thread spawn failure"));
        assert!(killed.load(Ordering::Acquire));
        assert!(session.exited.load(Ordering::Acquire));
        assert!(session.zmodem_transport_terminated.load(Ordering::Acquire));
        assert!(!session.pty_writer_available.load(Ordering::Acquire));
    }

    #[test]
    fn close_detaches_an_unfinished_reader_instead_of_waiting_forever() {
        let session = TerminalSession::new(
            422,
            long_running_lifecycle_profile(),
            None,
            None,
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        session.worker_handles.lock().reader = Some(thread::spawn(move || {
            let _ = release_rx.recv();
        }));
        let (closed_tx, closed_rx) = std::sync::mpsc::sync_channel(1);
        let close_session = Arc::clone(&session);
        let closer = thread::spawn(move || {
            close_session.close().unwrap();
            let _ = closed_tx.send(());
        });

        let closed_without_release = closed_rx.recv_timeout(Duration::from_millis(250)).is_ok();
        release_tx.send(()).unwrap();
        closer.join().unwrap();

        assert!(
            closed_without_release,
            "close must not join a reader blocked in an uninterruptible syscall"
        );
    }

    #[test]
    fn zmodem_command_failure_effects_preserve_safe_passthrough() {
        let mut manager = ZmodemManager::default();
        let mut writer = AlwaysFailWriter;
        let error = manager
            .ingest(b"ordinary-prefix**\x18B00000000000000", &mut writer)
            .unwrap_err();

        let effects =
            TerminalSession::abort_zmodem_command_error(&mut manager, &error, &mut writer)
                .expect("I/O failure must abort the active transfer");

        assert_eq!(effects.passthrough, b"ordinary-prefix");
        assert!(effects.events.is_empty());
    }

    #[test]
    fn zmodem_cancel_terminal_event_and_deferred_input_wait_for_drain_boundary() {
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            43,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(SharedTestWriter(Arc::clone(&captured)))),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        assert!(
            session
                .poll_events()
                .unwrap()
                .iter()
                .any(|event| event.kind == "zmodem_detected")
        );

        session.cancel_zmodem(1).unwrap();
        assert!(session.poll_events().unwrap().is_empty());
        assert!(session.zmodem.lock().is_active());
        let protocol_bytes = captured.lock().len();
        session
            .write_non_zmodem_or_defer(b"deferred-input", true)
            .unwrap();
        assert_eq!(captured.lock().len(), protocol_bytes);

        session.on_pty_reader_closed(true);

        assert!(!session.zmodem.lock().is_active());
        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_cancelled");
        assert_eq!(&captured.lock()[protocol_bytes..], b"deferred-input");
    }

    #[test]
    fn repeated_cancel_during_drain_is_idempotent_and_preserves_the_shell() {
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            431,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(SharedTestWriter(Arc::clone(&captured)))),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let _ = session.poll_events().unwrap();

        session.cancel_zmodem(1).unwrap();
        let transport = session.zmodem_transport_gate.lock();
        assert_eq!(
            session.cancel_active_zmodem().unwrap(),
            CancelActiveZmodemOutcome::Draining
        );
        drop(transport);
        assert!(!session.zmodem_transport_terminated.load(Ordering::Acquire));
        let protocol_bytes = captured.lock().len();
        session
            .write_non_zmodem_or_defer(b"preserved-after-double-cancel", true)
            .unwrap();

        session.on_pty_reader_closed(true);

        assert!(!session.zmodem_transport_terminated.load(Ordering::Acquire));
        assert_eq!(
            &captured.lock()[protocol_bytes..],
            b"preserved-after-double-cancel"
        );
        assert_eq!(
            session
                .poll_events()
                .unwrap()
                .iter()
                .map(|event| event.kind.as_str())
                .collect::<Vec<_>>(),
            ["zmodem_cancelled"]
        );
    }

    #[test]
    fn direct_transport_termination_reports_deferred_input_failure() {
        let session = TerminalSession::new(
            432,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let _ = session.poll_events().unwrap();
        session
            .write_non_zmodem_or_defer(b"must-be-reported", true)
            .unwrap();

        session.terminate_zmodem_transport();

        let events = session.poll_events().unwrap();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].kind, ZMODEM_DEFERRED_WRITE_FAILED_KIND);
        assert_eq!(events[0].payload.as_ref().unwrap()["queuedChunks"], 1);
        assert_eq!(
            events[0].payload.as_ref().unwrap()["queuedBytes"],
            b"must-be-reported".len()
        );
    }

    #[test]
    fn zmodem_idle_transition_flushes_deferred_writes_before_later_writes() {
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            46,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(SharedTestWriter(Arc::clone(&captured)))),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let _ = session.poll_events().unwrap();
        session.cancel_zmodem(1).unwrap();
        let protocol_bytes = captured.lock().len();
        session
            .write_non_zmodem_or_defer(b"deferred-first", true)
            .unwrap();

        let completion_session = Arc::clone(&session);
        let completion = thread::spawn(move || completion_session.on_pty_reader_closed(true));
        let later_session = Arc::clone(&session);
        let later =
            thread::spawn(move || later_session.write_non_zmodem_or_defer(b"later-write", true));

        completion.join().unwrap();
        later.join().unwrap().unwrap();
        assert_eq!(
            &captured.lock()[protocol_bytes..],
            b"deferred-firstlater-write"
        );

        assert_eq!(session.poll_events().unwrap()[0].kind, "zmodem_cancelled");
    }

    #[test]
    fn zmodem_missing_writer_reports_deferred_failure_before_terminal_event() {
        let captured = Arc::new(Mutex::new(Vec::new()));
        let session = TerminalSession::new(
            47,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(SharedTestWriter(Arc::clone(&captured)))),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let _ = session.poll_events().unwrap();
        session.cancel_zmodem(1).unwrap();
        session
            .write_non_zmodem_or_defer(b"queued-without-writer", true)
            .unwrap();
        session.writer.lock().take();

        session.on_pty_reader_closed(true);

        let events = session.poll_events().unwrap();
        assert_eq!(
            events
                .iter()
                .map(|event| event.kind.as_str())
                .collect::<Vec<_>>(),
            [ZMODEM_DEFERRED_WRITE_FAILED_KIND, "zmodem_cancelled"]
        );
        let payload = events[0].payload.as_ref().unwrap();
        assert_eq!(payload["reason"], "io_error");
        assert_eq!(payload["queuedChunks"], 1);
        assert_eq!(payload["queuedBytes"], b"queued-without-writer".len());
        assert_eq!(payload["completedChunks"], 0);
        assert_eq!(payload["completedBytes"], 0);
        assert_eq!(payload["unconfirmedChunks"], 1);
        assert_eq!(payload["unconfirmedBytes"], b"queued-without-writer".len());
        assert_eq!(session.deferred_pty_writes.lock().bytes, 0);
        assert!(session.zmodem_transport_terminated.load(Ordering::SeqCst));
        assert!(
            session
                .route_pty_output(b"must remain quarantined")
                .is_empty()
        );
    }

    #[test]
    fn zmodem_partial_deferred_write_reports_failure_and_terminates_transport() {
        let captured = Arc::new(Mutex::new(Vec::new()));
        let killed = Arc::new(AtomicBool::new(false));
        let session = TerminalSession::new(
            48,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(PartialThenFailWriter {
                captured: Arc::clone(&captured),
                fail_on: b"deferred-firstdeferred-tail".to_vec(),
                failing: false,
            })),
            None,
            Some(Box::new(TestChild {
                killed: Arc::clone(&killed),
            })),
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let _ = session.poll_events().unwrap();
        session.cancel_zmodem(1).unwrap();
        let protocol_bytes = captured.lock().len();
        session
            .write_non_zmodem_or_defer(b"deferred-first", true)
            .unwrap();
        session
            .write_non_zmodem_or_defer(b"deferred-tail", true)
            .unwrap();

        session.on_pty_reader_closed(true);

        assert_eq!(&captured.lock()[protocol_bytes..], b"def");
        assert!(killed.load(Ordering::SeqCst));
        assert!(session.writer.lock().is_none());
        assert_eq!(session.deferred_pty_writes.lock().bytes, 0);
        let events = session.poll_events().unwrap();
        assert_eq!(
            events
                .iter()
                .map(|event| event.kind.as_str())
                .collect::<Vec<_>>(),
            [ZMODEM_DEFERRED_WRITE_FAILED_KIND, "zmodem_cancelled"]
        );
        let payload = events[0].payload.as_ref().unwrap();
        assert_eq!(payload["queuedChunks"], 2);
        assert_eq!(
            payload["queuedBytes"],
            b"deferred-first".len() + b"deferred-tail".len()
        );
        assert_eq!(payload["completedChunks"], 0);
        assert_eq!(payload["completedBytes"], 0);
        assert_eq!(payload["unconfirmedChunks"], 2);
        assert_eq!(
            payload["unconfirmedBytes"],
            b"deferred-first".len() + b"deferred-tail".len()
        );
        assert!(
            session
                .route_pty_output(b"must remain quarantined")
                .is_empty()
        );
    }

    #[test]
    fn zmodem_hard_drain_deadline_terminates_transport_without_releasing_payload() {
        let captured = Arc::new(Mutex::new(Vec::new()));
        let killed = Arc::new(AtomicBool::new(false));
        let session = TerminalSession::new(
            45,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(SharedTestWriter(Arc::clone(&captured)))),
            None,
            Some(Box::new(TestChild {
                killed: Arc::clone(&killed),
            })),
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        let _ = session.poll_events().unwrap();
        session.cancel_zmodem(1).unwrap();
        session
            .write_non_zmodem_or_defer(b"must-not-be-replayed", true)
            .unwrap();
        for payload in [b"opaque-1".as_slice(), b"opaque-2", b"prompt$ "] {
            assert!(session.route_pty_output(payload).is_empty());
        }
        session
            .zmodem
            .lock()
            .force_drain_hard_deadline_for_test(Instant::now());

        session.poll_zmodem_timeout();

        assert!(killed.load(Ordering::SeqCst));
        assert!(session.writer.lock().is_none());
        assert_eq!(session.deferred_pty_writes.lock().bytes, 0);
        assert!(!session.zmodem.lock().is_active());
        assert!(session.route_pty_output(b"post-kill payload").is_empty());
        let events = session.poll_events().unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].kind, ZMODEM_DEFERRED_WRITE_FAILED_KIND);
        assert_eq!(events[0].payload.as_ref().unwrap()["queuedChunks"], 1);
        assert_eq!(events[0].payload.as_ref().unwrap()["completedChunks"], 0);
        assert_eq!(events[1].kind, "zmodem_cancelled");

        session.on_pty_reader_closed(true);
        assert!(session.poll_events().unwrap().is_empty());
        assert!(!session.zmodem.lock().is_active());
    }

    #[test]
    fn zmodem_pty_reader_error_fails_active_transfer_immediately() {
        let session = TerminalSession::new(
            44,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );
        session.poll_events().unwrap();

        session.on_pty_reader_closed(false);

        assert!(!session.zmodem.lock().is_active());
        let events = session.poll_events().unwrap();
        assert_eq!(events[0].kind, "zmodem_failed");
        assert_eq!(events[0].payload.as_ref().unwrap()["reason"], "io_error");
    }

    #[test]
    fn close_session_releases_background_worker_references_promptly() {
        let store = SessionStore::default();
        let session_id = store
            .create_session(long_running_lifecycle_profile())
            .unwrap();
        let session = store.get(session_id).unwrap();

        for _ in 0..20 {
            if Arc::strong_count(&session) >= 4 {
                break;
            }
            thread::sleep(Duration::from_millis(10));
        }
        assert!(
            Arc::strong_count(&session) >= 4,
            "expected store, test, reader, and sampler references before close"
        );

        store.close_session(session_id).unwrap();
        thread::sleep(Duration::from_millis(100));

        assert_eq!(
            Arc::strong_count(&session),
            1,
            "close should release reader and sampler session references promptly"
        );
        assert!(store.get(session_id).is_err());
    }

    #[test]
    fn close_during_receive_publication_retains_session_and_event_authority() {
        let store = SessionStore::default();
        let session_id = store
            .create_session(long_running_lifecycle_profile())
            .unwrap();
        let session = store.get(session_id).unwrap();
        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_PUBLISHING, Ordering::Release);

        let error = store.close_session(session_id).unwrap_err();

        assert!(
            error
                .to_string()
                .contains("receive_publication_in_progress")
        );
        assert!(store.get(session_id).is_ok());
        assert!(!session.exited.load(Ordering::Acquire));

        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_IDLE, Ordering::Release);
        store.close_session(session_id).unwrap();
        assert!(store.get(session_id).is_err());
    }

    #[test]
    fn close_rejects_native_zmodem_before_detection_event_is_polled() {
        let session = TerminalSession::new(
            451,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events().unwrap();
        assert!(
            session
                .route_pty_output(b"**\x18B00000000000000")
                .is_empty()
        );

        let error = session.close().unwrap_err();

        assert!(error.to_string().contains("zmodem_transfer_active"));
        assert!(!session.exited.load(Ordering::Acquire));
        let detected = session.poll_events().unwrap();
        assert_eq!(detected.len(), 1);
        assert_eq!(detected[0].kind, "zmodem_detected");

        session.cancel_zmodem(1).unwrap();
        session.on_pty_reader_closed(true);
        let terminal = session.poll_events().unwrap();
        assert_eq!(terminal.last().unwrap().kind, "zmodem_cancelled");
        session.close().unwrap();
    }

    #[test]
    fn close_waits_for_a_queued_zmodem_recovery_result_to_be_polled() {
        let session = TerminalSession::new(
            45,
            long_running_lifecycle_profile(),
            None,
            Some(Box::new(Vec::<u8>::new())),
            None,
            None,
            None,
            "test".to_string(),
            serde_json::json!({}),
            false,
        );
        let _ = session.poll_events().unwrap();
        session
            .zmodem_receive_commit_phase
            .store(RECEIVE_COMMIT_PUBLISHING, Ordering::Release);
        session.apply_zmodem_effects(
            ZmodemEffects {
                events: vec![crate::zmodem::ZmodemEvent {
                    kind: "zmodem_failed",
                    payload: serde_json::json!({
                        "source": "zmodem",
                        "transferId": "1",
                        "direction": "receive",
                        "reason": "publish_failed",
                        "stagingPreserved": true,
                        "recoveryToken": "0123456789abcdef0123456789abcdef",
                    }),
                }],
                receive_publish_pending: true,
                ..ZmodemEffects::default()
            },
            None,
        );

        let error = session.close().unwrap_err();
        assert!(error.to_string().contains("zmodem_result_pending"));
        assert!(!session.exited.load(Ordering::Acquire));

        let events = session.poll_events().unwrap();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].kind, "zmodem_failed");
        session.close().unwrap();
    }

    #[test]
    fn terminal_profile_deserialization_clamps_scrollback_lines() {
        let profile: TerminalProfile = serde_json::from_value(serde_json::json!({
            "id": "test",
            "name": "Test",
            "terminal": {
                "scrollbackLines": MAX_SCROLLBACK_LINES + 1
            }
        }))
        .unwrap();

        assert_eq!(profile.terminal.scrollback_lines, MAX_SCROLLBACK_LINES);
        assert_eq!(normalize_scrollback_lines(0), 1);
    }

    #[test]
    fn scrollback_export_max_lines_request_is_bounded() {
        assert_eq!(
            scrollback_export_max_lines_from_request(&serde_json::json!({})),
            None
        );
        assert_eq!(
            scrollback_export_max_lines_from_request(
                &serde_json::json!({"maxLines": serde_json::Value::Null})
            ),
            None
        );
        assert_eq!(
            scrollback_export_max_lines_from_request(&serde_json::json!({"maxLines": -1})),
            Some(0)
        );
        assert_eq!(
            scrollback_export_max_lines_from_request(&serde_json::json!({"maxLines": 12.5})),
            Some(0)
        );
        assert_eq!(
            scrollback_export_max_lines_from_request(&serde_json::json!({"max_lines": 42})),
            Some(42)
        );
        assert_eq!(
            scrollback_export_max_lines_from_request(
                &serde_json::json!({"maxLines": MAX_SCROLLBACK_LINES + 1})
            ),
            Some(MAX_SCROLLBACK_LINES)
        );
    }

    #[test]
    fn delta_candidates_include_rows_exposed_by_negative_viewport_shift() {
        let pending = pending_full_screen_scroll(&[4], -1);

        let candidates = delta_candidate_row_indexes(&pending, 5, 100, 100, false, -1);

        assert_eq!(candidates, vec![3, 4]);
    }

    #[test]
    fn delta_candidates_include_rows_exposed_by_positive_viewport_shift() {
        let pending = pending_full_screen_scroll(&[0], 1);

        let candidates = delta_candidate_row_indexes(&pending, 5, 100, 100, false, 1);

        assert_eq!(candidates, vec![0, 1]);
    }

    #[test]
    fn color_to_hex_handles_named_and_rgb_colors() {
        let mut terminal = Terminal::with_scrollback(4, 4, 16);
        terminal
            .set_ansi_palette_color(1, Color::Rgb(0x12, 0x34, 0x56))
            .unwrap();
        let ansi_palette = terminal_theme_snapshot(&terminal).ansi_palette;

        assert_eq!(
            color_to_hex(Color::Rgb(255, 0, 0), &ansi_palette),
            Some("#ff0000".to_string())
        );
        assert_eq!(
            color_to_hex(Color::Indexed(46), &ansi_palette),
            Some("#00ff00".to_string())
        );
        assert_eq!(
            color_to_hex_delta(
                Color::Named(NamedColor::White),
                Color::Named(NamedColor::White),
                &ansi_palette,
            ),
            None
        );
        assert_eq!(
            color_to_hex_delta(
                Color::Named(NamedColor::Red),
                Color::Named(NamedColor::White),
                &ansi_palette,
            ),
            Some("#123456".to_string())
        );
    }

    #[test]
    fn extended_osc_palette_updates_renderer_visible_indexed_color() {
        let mut terminal = Terminal::with_scrollback(4, 4, 16);
        terminal.process(b"\x1b[38;5;196mX");
        let before_theme = terminal_theme_snapshot(&terminal);
        let before = extract_row(terminal.grid().row(0), false, &before_theme);
        assert_eq!(before.style_runs[0].foreground, Some("#ff0000".to_string()));
        let _ = terminal.drain_active_screen_damage();

        terminal.process(b"\x1b]4;196;#123456\x1b\\");
        let palette_damage = terminal.drain_active_screen_damage();
        assert!(palette_damage.full_repaint);
        assert_eq!(
            palette_damage.snapshot_fallback_reason.as_deref(),
            Some("ansi_palette_changed")
        );

        let after_theme = terminal_theme_snapshot(&terminal);
        let after = extract_row(terminal.grid().row(0), false, &after_theme);
        assert_eq!(after.style_runs[0].foreground, Some("#123456".to_string()));
    }

    #[test]
    fn dynamic_defaults_repaint_existing_default_glyphs_without_recoloring_explicit_same_rgb() {
        let mut terminal = Terminal::with_scrollback(4, 2, 16);
        terminal.set_default_fg(Color::Rgb(1, 2, 3));
        terminal.set_default_bg(Color::Rgb(4, 5, 6));
        terminal.process(b"A\x1b[38;2;1;2;3;48;2;4;5;6mB\x1b[0m");

        terminal.process(b"\x1b]10;#112233\x1b\\\x1b]11;#445566\x1b\\");
        let theme = terminal_theme_snapshot(&terminal);
        let extracted = extract_row(terminal.grid().row(0), false, &theme);

        let default_glyph = extracted
            .style_runs
            .iter()
            .find(|run| run.start == 0)
            .expect("default-colored glyph style");
        assert_eq!(default_glyph.foreground, None);
        assert_eq!(default_glyph.background, None);
        let explicit_same_rgb = extracted
            .style_runs
            .iter()
            .find(|run| run.start == 1)
            .expect("explicit same-RGB glyph style");
        assert_eq!(explicit_same_rgb.foreground.as_deref(), Some("#010203"));
        assert_eq!(explicit_same_rgb.background.as_deref(), Some("#040506"));
    }

    #[test]
    fn xterm_attribute_colors_repaint_default_sourced_attributes_only() {
        let mut terminal = Terminal::with_scrollback(8, 2, 16);
        terminal.process(
            b"\x1b]5;0;#ff00ff;3;#00ffff\x1b\\\x1b]6;0;1;3;1\x1b\\\x1b[1mB\x1b[38;2;1;2;3mR\x1b[0;7mV\x1b[0m",
        );
        let theme = terminal_theme_snapshot(&terminal);
        let extracted = extract_row(terminal.grid().row(0), false, &theme);

        let bold = extracted
            .style_runs
            .iter()
            .find(|run| run.start == 0)
            .expect("default-sourced bold run");
        assert_eq!(bold.foreground.as_deref(), Some("#ff00ff"));
        assert!(!bold.bold, "colorBDMode replaces the bold font by default");

        let explicit_bold = extracted
            .style_runs
            .iter()
            .find(|run| run.start == 1)
            .expect("explicit-color bold run");
        assert_eq!(explicit_bold.foreground.as_deref(), Some("#010203"));
        assert!(explicit_bold.bold);

        let reverse = extracted
            .style_runs
            .iter()
            .find(|run| run.start == 2)
            .expect("default-sourced reverse run");
        assert_eq!(reverse.foreground.as_deref(), Some("#00ffff"));
        assert_eq!(reverse.background.as_deref(), Some("#e5e5e5"));
        assert!(!reverse.inverse, "special reverse color is flattened once");

        terminal.process(b"\x1b]106;5;1\x1b\\\x1b[1;38;2;4;5;6mX\x1b[0m");
        let override_theme = terminal_theme_snapshot(&terminal);
        let overridden = extract_row(terminal.grid().row(0), false, &override_theme);
        let overridden_explicit = overridden
            .style_runs
            .iter()
            .find(|run| run.start == 3)
            .expect("colorAttrMode explicit-color override run");
        assert_eq!(overridden_explicit.foreground.as_deref(), Some("#ff00ff"));
        assert!(!overridden_explicit.bold);
    }

    #[test]
    fn iterm_set_colors_exports_bold_underline_and_frame_resource_overrides() {
        let mut terminal = Terminal::with_scrollback(8, 2, 16);
        terminal.process(
            b"\x1b]1337;SetColors=bold=ff00ff,underline=00ff00,link=112233,curfg=445566,tab=778899\x1b\\\x1b[1mB\x1b[0;4mU\x1b[0m",
        );
        let theme = terminal_theme_snapshot(&terminal);
        let extracted = extract_row(terminal.grid().row(0), false, &theme);

        let bold = extracted
            .style_runs
            .iter()
            .find(|run| run.start == 0)
            .expect("iTerm bold run");
        assert_eq!(bold.foreground.as_deref(), Some("#ff00ff"));
        assert!(bold.bold, "iTerm bold color preserves bold font weight");

        let underline = extracted
            .style_runs
            .iter()
            .find(|run| run.start == 1)
            .expect("iTerm underline run");
        assert_eq!(underline.underline_color.as_deref(), Some("#00ff00"));
        assert!(underline.underline);
        assert_eq!(theme.link_color, Some(Color::Rgb(0x11, 0x22, 0x33)));
        assert_eq!(theme.cursor_text_color, Some(Color::Rgb(0x44, 0x55, 0x66)));
        assert_eq!(theme.tab_color, Some(Color::Rgb(0x77, 0x88, 0x99)));
    }

    #[test]
    fn extract_row_tracks_style_runs_in_terminal_columns() {
        let mut terminal = Terminal::with_scrollback(4, 4, 16);
        terminal
            .set_ansi_palette_color(1, Color::Rgb(0x12, 0x34, 0x56))
            .unwrap();
        let wide = Cell::with_colors(
            '你',
            Color::Named(NamedColor::White),
            Color::Named(NamedColor::Black),
        );
        let mut spacer = Cell::default();
        spacer.flags.set_wide_char_spacer(true);
        let ascii = Cell::with_colors(
            'a',
            Color::Named(NamedColor::Red),
            Color::Named(NamedColor::Black),
        );
        let row = vec![wide, spacer, ascii];
        let theme = TerminalThemeSnapshot {
            default_fg: Color::Named(NamedColor::White),
            default_bg: Color::Named(NamedColor::Black),
            cursor_color: Color::Named(NamedColor::White),
            ..terminal_theme_snapshot(&terminal)
        };

        let extracted = extract_row(Some(&row), false, &theme);

        assert_eq!(extracted.text, "你a");
        assert_eq!(extracted.style_runs.len(), 2);
        assert_eq!(extracted.style_runs[0].start, 0);
        assert_eq!(extracted.style_runs[0].end, 2);
        assert_eq!(extracted.style_runs[0].foreground, None);
        assert_eq!(extracted.style_runs[0].background, None);
        assert_eq!(extracted.style_runs[1].start, 2);
        assert_eq!(extracted.style_runs[1].end, 3);
        assert_eq!(
            extracted.style_runs[1].foreground,
            Some("#123456".to_string())
        );
        assert_eq!(extracted.style_runs[1].background, None);
    }

    #[test]
    fn extract_row_omits_default_colors_from_style_runs() {
        let terminal = Terminal::with_scrollback(4, 4, 16);
        let default_fg = Color::Rgb(0xAB, 0xCD, 0xEF);
        let default_bg = Color::Rgb(0x12, 0x34, 0x56);
        let theme = TerminalThemeSnapshot {
            default_fg,
            default_bg,
            cursor_color: Color::Named(NamedColor::White),
            ..terminal_theme_snapshot(&terminal)
        };
        let row = vec![Cell::with_colors('a', default_fg, default_bg)];

        let extracted = extract_row(Some(&row), false, &theme);

        assert_eq!(extracted.text, "a");
        assert_eq!(extracted.style_runs.len(), 1);
        assert_eq!(extracted.style_runs[0].start, 0);
        assert_eq!(extracted.style_runs[0].end, 1);
        assert_eq!(extracted.style_runs[0].foreground, None);
        assert_eq!(extracted.style_runs[0].background, None);
    }

    #[test]
    fn profile_default_colors_update_current_sgr_defaults() {
        let mut terminal = Terminal::with_scrollback(4, 4, 16);
        let colors = TerminalProfileColors {
            special: TerminalProfileSpecialColors {
                foreground: Some("#112233".to_string()),
                background: Some("#445566".to_string()),
                ..TerminalProfileSpecialColors::default()
            },
            ..TerminalProfileColors::default()
        };
        apply_profile_colors(&mut terminal, &colors);

        terminal.process(b"a");
        let theme = terminal_theme_snapshot(&terminal);
        let extracted = extract_row(terminal.active_grid().row(0), false, &theme);

        assert_eq!(extracted.text.trim_end(), "a");
        assert!(
            extracted
                .style_runs
                .iter()
                .all(|run| run.foreground.is_none() && run.background.is_none()),
            "profile default colors must not serialize as explicit style runs: {:?}",
            extracted.style_runs
        );
    }

    #[test]
    fn profile_blank_cells_created_after_scroll_use_default_colors() {
        let mut terminal = Terminal::with_scrollback(16, 2, 16);
        let colors = TerminalProfileColors {
            special: TerminalProfileSpecialColors {
                foreground: Some("#c0c0c0".to_string()),
                background: Some("#000000".to_string()),
                ..TerminalProfileSpecialColors::default()
            },
            normal: TerminalProfileAnsiColors {
                black: Some("#14191e".to_string()),
                ..TerminalProfileAnsiColors::default()
            },
            ..TerminalProfileColors::default()
        };
        apply_profile_colors(&mut terminal, &colors);

        terminal.process(b"one\r\ntwo\r\napp\tcursor");
        let theme = terminal_theme_snapshot(&terminal);
        let extracted = extract_row(terminal.active_grid().row(1), false, &theme);

        assert!(extracted.text.starts_with("app     cursor"));
        assert!(
            extracted
                .style_runs
                .iter()
                .all(|run| run.foreground.is_none() && run.background.is_none()),
            "profile blank cells must not serialize tab gaps or row tails as explicit styles: {:?}",
            extracted.style_runs
        );
    }

    #[test]
    fn kitty_retransmit_keeps_stable_render_id_and_content_version() {
        let mut terminal = Terminal::with_scrollback(80, 24, 16);
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374;/wAA/w==\x1b\\");

        let first = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(first.len(), 1);
        assert_eq!(first[0].asset_id, 49374);

        terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374;/wAA/w==\x1b\\");

        let second = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(second.len(), 1);
        assert_eq!(second[0].render_id, first[0].render_id);
        assert_eq!(second[0].placement_id, first[0].placement_id);
        assert_eq!(second[0].asset_id, 49374);
        assert_eq!(second[0].asset_version, first[0].asset_version);

        terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374;AP8A/w==\x1b\\");

        let third = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(third.len(), 1);
        assert_eq!(third[0].render_id, first[0].render_id);
        assert_eq!(third[0].asset_id, 49374);
        assert_ne!(third[0].asset_version, first[0].asset_version);
    }

    #[test]
    fn kitty_replacement_across_image_ids_keeps_stable_placement_identity() {
        let mut terminal = Terminal::with_scrollback(80, 24, 16);
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374;/wAA/w==\x1b\\");

        let first = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(first.len(), 1);
        assert_eq!(first[0].asset_id, 49374);

        terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49375;AP8A/w==\x1b\\");

        let second = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(second.len(), 1);
        assert_eq!(second[0].placement_id, first[0].placement_id);
        assert_eq!(second[0].render_id, first[0].render_id);
        assert_eq!(second[0].asset_id, 49375);
        assert_ne!(second[0].asset_version, first[0].asset_version);
    }

    #[test]
    fn kitty_replacement_across_image_ids_can_move_with_stable_placement_identity() {
        let mut terminal = Terminal::with_scrollback(80, 24, 16);
        terminal.process(b"\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=49374;/wAA/w==\x1b\\");

        let first = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(first.len(), 1);
        assert_eq!(first[0].row, 0);
        assert_eq!(first[0].col, 0);
        assert_eq!(first[0].asset_id, 49374);

        terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
        terminal.process(b"\x1b[5;5H\x1b_Ga=T,f=32,s=1,v=1,i=49375;AP8A/w==\x1b\\");

        let second = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(second.len(), 1);
        assert_eq!(second[0].placement_id, first[0].placement_id);
        assert_eq!(second[0].render_id, first[0].render_id);
        assert_eq!(second[0].row, 4);
        assert_eq!(second[0].col, 4);
        assert_eq!(second[0].asset_id, 49375);
        assert_ne!(second[0].asset_version, first[0].asset_version);
    }

    #[test]
    fn kitty_replacement_across_image_ids_requires_matching_placement_id() {
        let mut terminal = Terminal::with_scrollback(80, 24, 16);
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374,p=1;/wAA/w==\x1b\\");

        let first = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(first.len(), 1);
        assert_eq!(first[0].asset_id, 49374);

        terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49375,p=2;AP8A/w==\x1b\\");

        let second = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(second.len(), 1);
        assert_ne!(second[0].placement_id, first[0].placement_id);
        assert_ne!(second[0].render_id, first[0].render_id);
        assert_eq!(second[0].asset_id, 49375);
    }

    #[test]
    fn kitty_default_placement_uses_stable_frame_identity() {
        let mut terminal = Terminal::with_scrollback(80, 24, 16);
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374;/wAA/w==\x1b\\");

        let placements = build_graphic_placements(&terminal, 0, 24, 0, false, false);

        assert_eq!(placements.len(), 1);
        assert_eq!(placements[0].render_id, placements[0].placement_id);
        assert!(placements[0].placement_id > 0);
        assert_eq!(placements[0].placement_id, terminal.all_graphics()[0].id);
    }

    #[test]
    fn active_graphic_rows_are_relative_to_visible_scrollback_base() {
        let mut terminal = Terminal::with_scrollback(80, 3, 16);
        terminal.process(b"line0\nline1\nline2\nline3\n");
        let scrollback_len = terminal.grid().scrollback_len();
        assert!(scrollback_len > 0);

        terminal.process(b"\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=49374;/wAA/w==\x1b\\");

        let placements =
            build_graphic_placements(&terminal, scrollback_len, 3, scrollback_len, false, false);

        assert_eq!(placements.len(), 1);
        assert_eq!(placements[0].row, 1);
    }

    #[test]
    fn graphic_placements_are_scoped_to_alternate_screen_lifecycle() {
        let mut terminal = Terminal::with_scrollback(80, 24, 16);
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374;/wAA/w==\x1b\\");

        let primary = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(primary.len(), 1);
        assert_eq!(primary[0].asset_id, 49374);

        terminal.process(b"\x1b[?1049h");
        assert!(terminal.is_alt_screen_active());
        assert!(
            build_graphic_placements(&terminal, 0, 24, 0, true, false).is_empty(),
            "primary graphics must not leak into the alternate screen"
        );

        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49375;AP8A/w==\x1b\\");
        let alt = build_graphic_placements(&terminal, 0, 24, 0, true, false);
        assert_eq!(alt.len(), 1);
        assert_eq!(alt[0].asset_id, 49375);

        terminal.process(b"\x1b[?1049l");
        assert!(!terminal.is_alt_screen_active());
        let restored = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(restored.len(), 1);
        assert_eq!(restored[0].asset_id, 49374);
        assert!(
            terminal
                .all_graphics()
                .iter()
                .all(|graphic| graphic.kitty_image_id != Some(49375)),
            "alternate-screen graphics should be discarded on exit"
        );
    }

    #[test]
    fn alternate_screen_clear_does_not_clear_primary_graphics() {
        let mut terminal = Terminal::with_scrollback(80, 24, 16);
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374;/wAA/w==\x1b\\");
        terminal.process(b"\x1b[?1049h");
        terminal.process(b"\x1b[2J");
        assert!(
            build_graphic_placements(&terminal, 0, 24, 0, true, false).is_empty(),
            "alternate-screen clear should leave the alternate screen empty"
        );

        terminal.process(b"\x1b[?1049l");
        let restored = build_graphic_placements(&terminal, 0, 24, 0, false, false);
        assert_eq!(restored.len(), 1);
        assert_eq!(restored[0].asset_id, 49374);
    }

    #[test]
    fn resize_pixel_metrics_drive_graphic_display_geometry() {
        let mut terminal = Terminal::with_scrollback(80, 24, 16);
        apply_terminal_pixel_metrics(&mut terminal, 80, 24, 800, 480, 0, 0);

        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,c=9,r=5,i=49374;/wAA/w==\x1b\\");
        let placements = build_graphic_placements(&terminal, 0, 24, 0, false, false);

        assert_eq!(placements.len(), 1);
        assert_eq!(placements[0].width_px, 90);
        assert_eq!(placements[0].height_px, 100);
        assert_eq!(placements[0].width_cells, 9);
        assert_eq!(placements[0].height_cells, 5);
    }

    #[test]
    fn explicit_cell_metrics_drive_graphic_display_geometry() {
        let mut terminal = Terminal::with_scrollback(80, 24, 16);
        apply_terminal_pixel_metrics(&mut terminal, 80, 24, 815, 487, 9, 18);

        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,c=9,r=5,i=49374;/wAA/w==\x1b\\");
        let placements = build_graphic_placements(&terminal, 0, 24, 0, false, false);

        assert_eq!(placements.len(), 1);
        assert_eq!(placements[0].width_px, 81);
        assert_eq!(placements[0].height_px, 90);
        assert_eq!(placements[0].width_cells, 9);
        assert_eq!(placements[0].height_cells, 5);
    }

    #[test]
    fn resolved_graphic_cell_span_includes_kitty_cell_offsets() {
        let mut graphic = TerminalGraphic::new(
            1,
            par_term_emu_core_rust::graphics::GraphicProtocol::Kitty,
            (0, 0),
            10,
            10,
            vec![255u8; 10 * 10 * 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.x_offset = 5;
        graphic.placement.y_offset = 15;

        assert_eq!(graphic.resolved_cell_span(Some(80), Some(24)), (2, 2));

        graphic.placement.requested_width = ImageDimension::cells(3.0);
        graphic.placement.requested_height = ImageDimension::cells(2.0);
        assert_eq!(graphic.resolved_cell_span(Some(80), Some(24)), (4, 3));
    }

    #[test]
    fn resize_updates_existing_graphic_cell_geometry() {
        let mut terminal = Terminal::with_scrollback(80, 24, 16);
        apply_terminal_pixel_metrics(&mut terminal, 80, 24, 800, 480, 10, 20);
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,c=9,r=5,i=49374;/wAA/w==\x1b\\");

        apply_terminal_pixel_metrics(&mut terminal, 80, 24, 815, 487, 9, 18);
        let placements = build_graphic_placements(&terminal, 0, 24, 0, false, false);

        assert_eq!(placements.len(), 1);
        assert_eq!(placements[0].width_px, 81);
        assert_eq!(placements[0].height_px, 90);
        assert_eq!(placements[0].width_cells, 9);
        assert_eq!(placements[0].height_cells, 5);
        assert_eq!(terminal.all_graphics()[0].display_cell_span, Some((9, 5)));
    }

    #[test]
    fn graphic_placement_crops_right_edge_to_viewport_width() {
        let mut graphic = TerminalGraphic::new(
            1,
            par_term_emu_core_rust::graphics::GraphicProtocol::Kitty,
            (75, 0),
            1,
            1,
            vec![255u8; 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.requested_width = ImageDimension::cells(9.0);
        graphic.placement.requested_height = ImageDimension::cells(5.0);
        graphic.set_display_cell_span(9, 5);

        let placement = graphic_placement_for_viewport(&graphic, 0, 0, 24, 80, 24, 0)
            .expect("right-clipped graphic should remain visible");

        assert_eq!(placement.col, 75);
        assert_eq!(placement.width_px, 90);
        assert_eq!(placement.source_x_offset_px, 0);
        assert_eq!(placement.visible_width_px, 50);
        assert_eq!(placement.visible_height_px, 100);
    }

    #[test]
    fn graphic_placement_applies_kitty_source_rectangle_before_viewport_crop() {
        let mut graphic = TerminalGraphic::new(
            1,
            par_term_emu_core_rust::graphics::GraphicProtocol::Kitty,
            (75, 0),
            100,
            50,
            vec![255u8; 100 * 50 * 4],
        );
        graphic.set_cell_dimensions(10, 10);
        graphic.placement.source_x_offset = 20;
        graphic.placement.source_y_offset = 10;
        graphic.placement.source_width = Some(40);
        graphic.placement.source_height = Some(20);
        graphic.placement.requested_width = ImageDimension::cells(8.0);
        graphic.placement.requested_height = ImageDimension::cells(4.0);
        graphic.set_display_cell_span(8, 4);

        let placement = graphic_placement_for_viewport(&graphic, 0, 0, 24, 80, 24, 0)
            .expect("source-cropped graphic should remain visible");

        assert_eq!(placement.col, 75);
        assert_eq!(placement.width_px, 200);
        assert_eq!(placement.height_px, 100);
        assert_eq!(placement.width_cells, 8);
        assert_eq!(placement.height_cells, 4);
        assert_eq!(placement.source_x_offset_px, 40);
        assert_eq!(placement.visible_width_px, 50);
        assert_eq!(placement.source_y_offset_px, 20);
        assert_eq!(placement.visible_height_px, 40);
    }

    #[test]
    fn graphic_placement_cell_span_includes_kitty_cell_offsets() {
        let mut graphic = TerminalGraphic::new(
            1,
            par_term_emu_core_rust::graphics::GraphicProtocol::Kitty,
            (0, 0),
            10,
            10,
            vec![255u8; 10 * 10 * 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.x_offset = 5;
        graphic.placement.y_offset = 15;

        let placement = graphic_placement_for_viewport(&graphic, 0, 0, 24, 80, 24, 0)
            .expect("offset graphic should remain visible");

        assert_eq!(placement.width_px, 10);
        assert_eq!(placement.height_px, 10);
        assert_eq!(placement.width_cells, 2);
        assert_eq!(placement.height_cells, 2);
        assert_eq!(placement.visible_width_px, 10);
        assert_eq!(placement.visible_height_px, 10);
        assert_eq!(placement.x_offset_px, 5);
        assert_eq!(placement.y_offset_px, 15);
    }

    #[test]
    fn graphic_placement_keeps_kitty_offset_tail_visible_at_viewport_top() {
        let mut graphic = TerminalGraphic::new(
            1,
            par_term_emu_core_rust::graphics::GraphicProtocol::Kitty,
            (0, 0),
            10,
            10,
            vec![255u8; 10 * 10 * 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.y_offset = 15;

        let placement = graphic_placement_for_viewport(&graphic, 0, 1, 3, 80, 24, 0)
            .expect("offset image tail should remain visible in the next viewport row");

        assert_eq!(placement.row, 0);
        assert_eq!(placement.height_cells, 2);
        assert_eq!(placement.source_y_offset_px, 5);
        assert_eq!(placement.visible_height_px, 5);
        assert_eq!(placement.y_offset_px, 0);
    }

    #[test]
    fn graphic_placement_drops_kitty_offset_gap_before_image() {
        let mut graphic = TerminalGraphic::new(
            1,
            par_term_emu_core_rust::graphics::GraphicProtocol::Kitty,
            (0, 0),
            10,
            5,
            vec![255u8; 10 * 5 * 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.y_offset = 30;

        assert!(
            graphic_placement_for_viewport(&graphic, 0, 0, 1, 80, 24, 0).is_none(),
            "a viewport row that only intersects the offset gap should not emit a placement"
        );
    }

    #[test]
    fn graphic_placement_drops_graphics_starting_past_right_edge() {
        let mut graphic = TerminalGraphic::new(
            1,
            par_term_emu_core_rust::graphics::GraphicProtocol::Kitty,
            (80, 0),
            1,
            1,
            vec![255u8; 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.requested_width = ImageDimension::cells(9.0);
        graphic.placement.requested_height = ImageDimension::cells(5.0);
        graphic.set_display_cell_span(9, 5);

        assert!(
            graphic_placement_for_viewport(&graphic, 0, 0, 24, 80, 24, 0).is_none(),
            "graphics starting beyond the right edge should not produce placements"
        );
    }

    #[test]
    fn graphic_placement_crops_scrolled_top_rows() {
        let mut graphic = TerminalGraphic::new(
            1,
            par_term_emu_core_rust::graphics::GraphicProtocol::Kitty,
            (0, 0),
            1,
            1,
            vec![255u8; 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.requested_width = ImageDimension::cells(9.0);
        graphic.placement.requested_height = ImageDimension::cells(5.0);
        graphic.set_display_cell_span(9, 5);
        graphic.scroll_offset_rows = 1;

        let placement = graphic_placement_for_viewport(&graphic, 0, 0, 24, 80, 24, 1)
            .expect("partially scrolled graphic should remain visible");

        assert_eq!(placement.row, 0);
        assert_eq!(placement.height_px, 100);
        assert_eq!(placement.height_cells, 5);
        assert_eq!(placement.source_y_offset_px, 20);
        assert_eq!(placement.visible_height_px, 80);
    }

    #[test]
    fn graphic_placement_crops_when_viewport_starts_inside_graphic() {
        let mut graphic = TerminalGraphic::new(
            1,
            par_term_emu_core_rust::graphics::GraphicProtocol::Kitty,
            (0, 3),
            1,
            1,
            vec![255u8; 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.requested_width = ImageDimension::cells(9.0);
        graphic.placement.requested_height = ImageDimension::cells(5.0);
        graphic.set_display_cell_span(9, 5);

        let placement = graphic_placement_for_viewport(&graphic, 3, 5, 10, 80, 24, 0)
            .expect("graphic should be visible through lower rows");

        assert_eq!(placement.row, 0);
        assert_eq!(placement.source_y_offset_px, 40);
        assert_eq!(placement.visible_height_px, 60);
    }

    #[test]
    fn graphic_placement_crops_bottom_edge_to_viewport_height() {
        let mut graphic = TerminalGraphic::new(
            1,
            par_term_emu_core_rust::graphics::GraphicProtocol::Kitty,
            (0, 4),
            1,
            1,
            vec![255u8; 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.requested_width = ImageDimension::cells(9.0);
        graphic.placement.requested_height = ImageDimension::cells(5.0);
        graphic.set_display_cell_span(9, 5);

        let placement = graphic_placement_for_viewport(&graphic, 4, 0, 6, 80, 6, 0)
            .expect("graphic bottom rows should remain visible inside a short viewport");

        assert_eq!(placement.row, 4);
        assert_eq!(placement.source_y_offset_px, 0);
        assert_eq!(placement.height_px, 100);
        assert_eq!(placement.visible_height_px, 40);
    }

    #[test]
    fn cached_graphic_assets_survive_kitty_placement_retransmit() {
        let mut state = TerminalState {
            terminal: Terminal::with_scrollback(80, 24, 16),
            transcript: Vec::new(),
            transcript_truncated: false,
            scrollback_offset: 0,
            host_protocol: HostProtocolState::default(),
            graphic_assets: VecDeque::new(),
            graphic_asset_bytes: 0,
            graphic_asset_cache_max_bytes: 256 * 1024 * 1024,
            pending_file_downloads: VecDeque::new(),
            pending_file_download_bytes: 0,
            next_file_download_id: 1,
            replay_checkpoint_boundary: ReplayCheckpointBoundary::default(),
        };
        state
            .terminal
            .process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374;/wAA/w==\x1b\\");

        let first = build_graphic_placements(&state.terminal, 0, 24, 0, false, false);
        assert_eq!(first.len(), 1);
        let snapshots = graphic_asset_snapshots(&state.terminal);
        cache_graphic_asset_snapshots(&mut state, snapshots);

        state.terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
        state
            .terminal
            .process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374;AP8A/w==\x1b\\");

        let second = build_graphic_placements(&state.terminal, 0, 24, 0, false, false);
        assert_eq!(second.len(), 1);
        assert_ne!(second[0].asset_version, first[0].asset_version);
        let old_asset =
            find_cached_graphic_asset(&state, first[0].asset_id, first[0].asset_version)
                .expect("previous asset version should remain readable briefly");
        assert_eq!(old_asset.pixels.as_ref(), &[255, 0, 0, 255]);
    }

    #[test]
    fn extract_row_hides_kitty_placeholder_cells() {
        let terminal = Terminal::with_scrollback(4, 4, 16);
        let theme = TerminalThemeSnapshot {
            default_fg: Color::Named(NamedColor::White),
            default_bg: Color::Named(NamedColor::Black),
            cursor_color: Color::Named(NamedColor::White),
            ..terminal_theme_snapshot(&terminal)
        };
        let mut placeholder = Cell::with_colors(
            PLACEHOLDER_CHAR,
            Color::Named(NamedColor::Red),
            Color::Rgb(0xff, 0xff, 0xff),
        );
        placeholder.flags.set_bold(true);
        placeholder.flags.set_underline(true);
        placeholder.flags.set_reverse(true);
        let row = vec![placeholder];

        let extracted = extract_row(Some(&row), false, &theme);

        assert_eq!(extracted.text, " ");
        assert_eq!(extracted.style_runs.len(), 1);
        let style = &extracted.style_runs[0];
        assert_eq!(style.start, 0);
        assert_eq!(style.end, 1);
        assert_eq!(style.foreground, None);
        assert_eq!(style.background, None);
        assert!(!style.bold);
        assert!(!style.underline);
        assert!(!style.inverse);
    }

    #[test]
    fn sized_text_placements_clip_blocks_crossing_the_viewport_top() {
        let mut terminal = Terminal::with_scrollback(8, 4, 12);
        terminal.process(b"\x1b]66;s=2:w=2;clip\x07");
        terminal.process(b"\x1b[4;1H\n");

        let full = build_sized_text_placements(&terminal, 0, 4);
        assert_eq!(full.len(), 1);
        assert_eq!(full[0].row, 0);
        assert_eq!(full[0].source_row_offset_cells, 0);
        assert_eq!(full[0].visible_height_cells, 2);

        let clipped = build_sized_text_placements(&terminal, 1, 4);
        assert_eq!(clipped.len(), 1);
        assert_eq!(clipped[0].text, "clip");
        assert_eq!(clipped[0].row, 0);
        assert_eq!(clipped[0].source_row_offset_cells, 1);
        assert_eq!(clipped[0].visible_height_cells, 1);
    }

    #[test]
    fn vt220_response_normalization_rewrites_da_sequences() {
        let input =
            b"\x1b[?62;1;4;6;9;15;22;52c\x1b[>82;10000;0c\x1b[?5522;1$y\x1b[?5522;2$y".to_vec();
        let output = normalize_responses(TerminalEmulation::Vt220, input);
        assert_eq!(
            String::from_utf8(output).unwrap(),
            format!(
                "{VT220_PRIMARY_DA_RESPONSE}{VT220_SECONDARY_DA_RESPONSE}\x1b[?5522;0$y\x1b[?5522;0$y"
            )
        );
    }

    #[test]
    fn host_protocol_observe_fast_path_keeps_plain_chunks_unbuffered() {
        let mut state = HostProtocolState::default();

        let events = state.observe(b"plain cat log chunk\n", TerminalEmulation::Xterm256);

        assert!(events.is_empty());
        assert!(state.buffer.is_empty());
    }

    #[test]
    fn host_protocol_observe_keeps_split_osc_sequences_working() {
        let mut state = HostProtocolState::default();

        assert!(
            state
                .observe(b"\x1b]1;build", TerminalEmulation::Xterm256)
                .is_empty()
        );
        assert!(!state.buffer.is_empty());

        let events = state.observe(b" icon\x07", TerminalEmulation::Xterm256);

        assert!(events.is_empty());
        assert!(state.buffer.is_empty());
    }

    #[test]
    fn host_protocol_captures_split_iterm_clipboard_stream_without_hiding_output() {
        let sequence = concat!(
            "\x1b]1337;CopyToClipboard\x1b\\",
            "Hello\n\x1b[31mworld\x1b[0m",
            "\x1b]1337;EndCopy\x07"
        )
        .as_bytes();

        for chunk_size in [1, 2, 7, sequence.len()] {
            let mut state = HostProtocolState::default();
            let mut events = Vec::new();
            for chunk in sequence.chunks(chunk_size) {
                events.extend(state.observe(chunk, TerminalEmulation::Xterm256));
            }

            let [
                CallbackEvent::ItermClipboardCopy {
                    selection,
                    data: Some(data),
                    streaming,
                },
            ] = events.as_slice()
            else {
                panic!("expected one iTerm2 streaming copy: {events:?}");
            };
            assert_eq!(selection, "c");
            assert!(*streaming);
            assert_eq!(
                BASE64_STANDARD.decode(data).unwrap(),
                b"Hello\n\x1b[31mworld\x1b[0m"
            );
            assert!(state.buffer.is_empty());
            assert!(state.iterm_clipboard_capture.is_none());
        }
    }

    #[test]
    fn host_protocol_maps_iterm_named_pasteboards_and_direct_base64_copy() {
        let mut state = HostProtocolState::default();
        let events = state.observe(
            concat!(
                "\x1b]1337;CopyToClipboard=find\x07find me\x1b]1337;EndCopy\x07",
                "\x1b]1337;CopyToClipboard=font\x07font me\x1b]1337;EndCopy\x07",
                "\x1b]1337;CopyToClipboard=unknown\x07general\x1b]1337;EndCopy\x07",
                "\x1b]1337;Copy=:ZGlyZWN0IPCfmIA=\x1b\\"
            )
            .as_bytes(),
            TerminalEmulation::Xterm256,
        );

        assert_eq!(events.len(), 4);
        for (index, (expected_selection, expected_text, expected_streaming)) in [
            ("find", "find me", true),
            ("font", "font me", true),
            ("c", "general", true),
            ("c", "direct 😀", false),
        ]
        .into_iter()
        .enumerate()
        {
            let CallbackEvent::ItermClipboardCopy {
                selection,
                data: Some(data),
                streaming,
            } = &events[index]
            else {
                panic!("expected iTerm2 clipboard event: {:?}", events[index]);
            };
            assert_eq!(selection, expected_selection);
            assert_eq!(
                BASE64_STANDARD.decode(data).unwrap(),
                expected_text.as_bytes()
            );
            assert_eq!(*streaming, expected_streaming);
        }
    }

    #[test]
    fn host_protocol_bounds_and_resets_iterm_clipboard_capture() {
        let mut state = HostProtocolState::default();
        assert!(
            state
                .observe(
                    b"\x1b]1337;CopyToClipboard\x07",
                    TerminalEmulation::Xterm256,
                )
                .is_empty()
        );
        assert!(
            state
                .observe(
                    &vec![b'x'; ITERM_CLIPBOARD_MAX_BYTES + 1],
                    TerminalEmulation::Xterm256,
                )
                .is_empty()
        );
        let events = state.observe(b"\x1b]1337;EndCopy\x07", TerminalEmulation::Xterm256);
        assert!(matches!(
            events.as_slice(),
            [CallbackEvent::ItermClipboardCopy { data: None, .. }]
        ));

        let events = state.observe(
            concat!(
                "\x1b]1337;CopyToClipboard\x07old",
                "\x1b]1337;CopyToClipboard=find\x07new",
                "\x1b]1337;EndCopy\x07"
            )
            .as_bytes(),
            TerminalEmulation::Xterm256,
        );
        assert!(matches!(
            events.as_slice(),
            [CallbackEvent::ItermClipboardCopy {
                selection,
                data: Some(data),
                streaming: true,
            }] if selection == "find" && BASE64_STANDARD.decode(data).unwrap() == b"new"
        ));

        assert!(
            state
                .observe(
                    b"\x1b]1337;CopyToClipboard\x07discarded\x1bc",
                    TerminalEmulation::Xterm256,
                )
                .is_empty()
        );
        assert!(state.iterm_clipboard_capture.is_none());
        assert!(
            state
                .observe(b"\x1b]1337;EndCopy\x07", TerminalEmulation::Xterm256)
                .is_empty()
        );

        let mut vt220 = HostProtocolState::default();
        assert!(
            vt220
                .observe(
                    b"\x1b]1337;CopyToClipboard\x07ignored\x1b]1337;EndCopy\x07",
                    TerminalEmulation::Vt220,
                )
                .is_empty()
        );
        assert!(vt220.iterm_clipboard_capture.is_none());
    }

    #[test]
    fn parser_annotations_resolve_terminal_text_and_redact_diagnostics() {
        let mut terminal = Terminal::new(12, 4);
        terminal.process(
            b"prefix \x1b]1337;AddAnnotation=4|Visible note\x07word\r\n\x1b]1337;AddHiddenAnnotation=Hidden|5|0|1\x1b\\value",
        );
        let annotations = terminal
            .poll_events()
            .into_iter()
            .filter_map(|event| {
                callback_event_from_parser_event_with_terminal(event, false, Some(&terminal))
            })
            .filter_map(|event| match event {
                CallbackEvent::SessionAnnotation { payload } => Some(payload),
                _ => None,
            })
            .collect::<Vec<_>>();

        assert_eq!(annotations.len(), 2);
        assert_eq!(annotations[0]["source"], "iterm1337");
        assert_eq!(annotations[0]["message"], "Visible note");
        assert_eq!(annotations[0]["visible"], true);
        assert_eq!(annotations[0]["selectedText"], "word");
        assert_eq!(annotations[0]["startRow"], 0);
        assert_eq!(annotations[0]["startCol"], 7);
        assert_eq!(annotations[0]["endRow"], 0);
        assert_eq!(annotations[0]["endCol"], 11);
        assert_eq!(annotations[1]["visible"], false);
        assert_eq!(annotations[1]["selectedText"], "value");

        let diagnostics =
            sanitize_diagnostic_event_payload("session_annotation", Some(&annotations[0]))
                .expect("annotation diagnostics");
        assert_eq!(diagnostics["message_chars"], 12);
        assert_eq!(diagnostics["selected_text_chars"], 4);
        assert!(diagnostics.get("message").is_none());
        assert!(diagnostics.get("selectedText").is_none());
    }

    #[test]
    fn host_protocol_ris_clears_native_keypad_state() {
        let mut state = HostProtocolState::default();
        state.observe(b"\x1b=", TerminalEmulation::Xterm256);
        assert!(state.application_keypad);

        let events = state.observe(b"\x1bc", TerminalEmulation::Xterm256);

        assert!(events.is_empty(), "the parser emits the typed reset event");
        assert!(!state.application_keypad);
        assert!(state.buffer.is_empty());
    }

    #[test]
    fn osc1337_current_dir_rejects_malformed_percent_utf8_and_controls() {
        assert!(shell_context_payload_from_current_dir("CurrentDir=/tmp/%ZZ").is_none());
        assert!(shell_context_payload_from_current_dir("CurrentDir=/tmp/%01bad").is_none());
        assert!(shell_context_payload_from_current_dir("CurrentDir=/tmp/%FFbad").is_none());

        let valid = shell_context_payload_from_current_dir("CurrentDir=/tmp/ianvs%20terminal")
            .expect("valid encoded absolute cwd");
        assert_eq!(valid["cwd"], "/tmp/ianvs terminal");
    }

    #[test]
    fn cwd_protocol_inputs_emit_one_authoritative_product_context_each() {
        let cases: &[(&[u8], &str)] = &[
            (b"\x1b]7;file://alice@remote.example/tmp/osc7\x07", "osc7"),
            (b"\x1b]9;9;/tmp/osc9\x07", "osc9;9"),
            (b"\x1b]633;P;Cwd=/tmp/osc633\x07", "osc633"),
            (
                b"\x1b]1337;RemoteHost=deploy@example.internal\x07",
                "osc1337_remote_host",
            ),
        ];

        for (sequence, expected_source) in cases {
            let mut terminal = Terminal::new(80, 24);
            terminal.process(sequence);
            let contexts = terminal
                .poll_events()
                .into_iter()
                .filter_map(|event| callback_event_from_parser_event(event, false))
                .filter_map(|event| match event {
                    CallbackEvent::ShellContext { payload } => Some(payload),
                    _ => None,
                })
                .collect::<Vec<_>>();

            assert_eq!(
                contexts.len(),
                1,
                "duplicate contexts for {expected_source}"
            );
            assert_eq!(contexts[0]["source"], *expected_source);
        }
    }

    #[test]
    fn local_cwd_context_explicitly_clears_remote_identity() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]7;file://alice@remote.example/tmp/remote\x07");
        let _ = terminal.poll_events();

        terminal.process(b"\x1b]7;file:///tmp/local\x07");
        let contexts = terminal
            .poll_events()
            .into_iter()
            .filter_map(|event| callback_event_from_parser_event(event, false))
            .filter_map(|event| match event {
                CallbackEvent::ShellContext { payload } => Some(payload),
                _ => None,
            })
            .collect::<Vec<_>>();

        assert_eq!(contexts.len(), 1);
        assert_eq!(contexts[0]["source"], "osc7");
        assert_eq!(contexts[0]["cwd"], "/tmp/local");
        assert_eq!(contexts[0].get("hostname"), Some(&serde_json::Value::Null));
        assert_eq!(contexts[0].get("username"), Some(&serde_json::Value::Null));
    }

    #[test]
    fn ris_maps_to_one_dedicated_product_reset_event() {
        let mut terminal = Terminal::new(80, 24);

        terminal.process(b"\x1b[2J\x1b[3J");
        let clears = terminal
            .poll_events()
            .into_iter()
            .filter_map(|event| callback_event_from_parser_event(event, false))
            .collect::<Vec<_>>();
        assert!(clears.is_empty(), "ED screen clears are not session resets");

        terminal.process(b"\x1bc");
        let resets = terminal
            .poll_events()
            .into_iter()
            .filter_map(|event| callback_event_from_parser_event(event, false))
            .collect::<Vec<_>>();
        assert_eq!(resets.len(), 1);
        assert!(matches!(resets[0], CallbackEvent::SessionReset));
    }

    #[test]
    fn osc934_product_events_preserve_full_distinct_protocol_ids() {
        let shared_prefix = "x".repeat(80);
        let first = format!("{shared_prefix}-first");
        let second = format!("{shared_prefix}-second");
        let mut terminal = Terminal::new(80, 24);
        terminal.process(
            format!("\x1b]934;set;{first};percent=10\x1b\\\x1b]934;set;{second};percent=20\x1b\\")
                .as_bytes(),
        );

        let ids = terminal
            .poll_events()
            .into_iter()
            .filter_map(|event| callback_event_from_parser_event(event, false))
            .filter_map(|event| match event {
                CallbackEvent::SessionProgress { payload } => {
                    payload["id"].as_str().map(str::to_string)
                }
                _ => None,
            })
            .collect::<Vec<_>>();

        assert_eq!(ids, vec![first, second]);
    }

    #[test]
    fn osc72_parser_event_maps_to_bounded_product_command_only_when_enabled() {
        let sequence = b"\x1b]72;t=a:i=9:x=3:y=4:X=30:Y=40:o=1;text/plain\x1b\\";
        let mut denied = Terminal::new(80, 24);
        denied.process(sequence);
        assert!(denied.poll_events().is_empty());

        let mut terminal = Terminal::new(80, 24);
        terminal.set_osc_capability_allowed(OscCapability::DragDrop, true);
        terminal.process(sequence);
        let events = terminal
            .poll_events()
            .into_iter()
            .filter_map(|event| callback_event_from_parser_event(event, false))
            .collect::<Vec<_>>();

        let [CallbackEvent::DragDropCommand { payload }] = events.as_slice() else {
            panic!("expected one OSC 72 product event: {events:?}");
        };
        assert_eq!(payload["source"], "osc72");
        assert_eq!(payload["action"], "a");
        assert_eq!(payload["identifier"], 9);
        assert_eq!(payload["x"], 3);
        assert_eq!(payload["pixelY"], 40);
        assert_eq!(payload["payload"], "text/plain");
    }

    #[test]
    fn terminal_filtered_bridge_reassembles_bounded_osc52_for_host_policy() {
        let mut terminal = Terminal::new(80, 24);
        let mut host = HostProtocolState::default();
        let encoded = "A".repeat(16 * 1024);
        let sequence = format!("\x1b]52;c;{encoded}\x1b\\");
        let mut events = Vec::new();

        for chunk in sequence.as_bytes().chunks(777) {
            terminal.process_with_filtered_input(chunk, |filtered| {
                events.extend(host.observe(filtered, TerminalEmulation::Xterm256));
            });
        }

        assert_eq!(events.len(), 1);
        assert!(matches!(
            &events[0],
            CallbackEvent::ClipboardCopy { selection, data }
                if selection == "c" && data.len() == encoded.len()
        ));
        assert!(host.buffer.is_empty());
    }

    #[test]
    fn terminal_filtered_bridge_denies_iterm_clipboard_but_keeps_stream_text_visible() {
        let mut terminal = Terminal::new(80, 4);
        terminal.set_osc_capability_allowed(OscCapability::ClipboardWrite, false);
        let mut host = HostProtocolState::default();
        let mut events = Vec::new();
        terminal.process_with_filtered_input(
            concat!(
                "\x1b]1337;CopyToClipboard\x07",
                "visible denied stream",
                "\x1b]1337;EndCopy\x1b\\",
                "\x1b]1337;Copy=:ZGVuaWVk\x07"
            )
            .as_bytes(),
            |filtered| {
                events.extend(host.observe(filtered, TerminalEmulation::Xterm256));
            },
        );

        assert!(events.is_empty());
        assert!(host.iterm_clipboard_capture.is_none());
        assert!(
            terminal
                .active_grid()
                .row_text(0)
                .contains("visible denied stream")
        );
    }

    #[test]
    fn host_protocol_assembles_osc5522_binary_mime_write_and_aliases() {
        let mut host = HostProtocolState::default();
        let packets = concat!(
            "\x1b]5522;type=write:id=mux!1:pw=c2VjcmV0:name=RWRpdG9y\x1b\\",
            "\x1b]5522;type=wdata:mime=dGV4dC9wbGFpbg==;aA==\x1b\\",
            "\x1b]5522;type=wdata:mime=dGV4dC9wbGFpbg==;aQ==\x1b\\",
            "\x1b]5522;type=walias:mime=dGV4dC9wbGFpbg==;dGV4dC91dGY4\x1b\\",
            "\x1b]5522;type=wdata:mime=aW1hZ2UvcG5n;AAEC\x1b\\",
            "\x1b]5522;type=wdata\x1b\\"
        );
        let mut events = Vec::new();
        for chunk in packets.as_bytes().chunks(11) {
            events.extend(host.observe(chunk, TerminalEmulation::Xterm256));
        }
        let [CallbackEvent::ClipboardMimeWrite { payload }] = events.as_slice() else {
            panic!("expected one assembled OSC 5522 write: {events:?}");
        };
        assert_eq!(payload["protocol"], "osc5522");
        assert_eq!(payload["location"], "clipboard");
        assert_eq!(payload["id"], "mux1");
        assert_eq!(payload["password"], "secret");
        assert_eq!(payload["applicationName"], "Editor");
        let items = payload["items"].as_array().expect("items array");
        assert_eq!(items.len(), 2);
        assert_eq!(items[0]["mime"], "image/png");
        assert_eq!(items[0]["data"], "AAEC");
        assert_eq!(items[1]["mime"], "text/plain");
        assert_eq!(items[1]["data"], "aGk=");
        assert_eq!(items[1]["aliases"][0], "text/utf8");
    }

    #[test]
    fn host_protocol_emits_osc5522_read_list_and_mime_requests() {
        let mut host = HostProtocolState::default();
        let events = host.observe(
            concat!(
                "\x1b]5522;type=read:id=list;Lg==\x1b\\",
                "\x1b]5522;type=read:loc=clipboard:id=read-1;dGV4dC9wbGFpbiBpbWFnZS8q\x1b\\",
                "\x1b]5522;type=read:id=paste:mime=dGV4dC9odG1s:pw=b25lLXRpbWU=\x1b\\"
            )
            .as_bytes(),
            TerminalEmulation::Xterm256,
        );
        assert_eq!(events.len(), 3);
        let CallbackEvent::ClipboardMimeReadRequest { payload: list } = &events[0] else {
            panic!("expected list request")
        };
        assert_eq!(list["listOnly"], true);
        assert_eq!(list["mimeTypes"][0], ".");
        let CallbackEvent::ClipboardMimeReadRequest { payload: read } = &events[1] else {
            panic!("expected MIME read request")
        };
        assert_eq!(read["id"], "read-1");
        assert_eq!(read["mimeTypes"][0], "text/plain");
        assert_eq!(read["mimeTypes"][1], "image/*");
        let CallbackEvent::ClipboardMimeReadRequest { payload: paste } = &events[2] else {
            panic!("expected paste-token MIME request")
        };
        assert_eq!(paste["mimeTypes"][0], "text/html");
        assert_eq!(paste["password"], "one-time");
        assert!(paste["applicationName"].is_null());
    }

    #[test]
    fn host_protocol_rejects_invalid_osc5522_password_metadata() {
        let events = HostProtocolState::default().observe(
            b"\x1b]5522;type=read:id=bad:pw=%%%:name=RWRpdG9y;dGV4dC9wbGFpbg==\x1b\\",
            TerminalEmulation::Xterm256,
        );
        assert!(matches!(
            events.as_slice(),
            [CallbackEvent::ClipboardMimeError { payload }]
                if payload["operation"] == "read"
                    && payload["status"] == "EINVAL"
                    && payload["id"] == "bad"
        ));
    }

    #[test]
    fn host_protocol_osc5522_write_failure_ignores_packets_until_restart() {
        let mut host = HostProtocolState::default();
        let events = host.observe(
            concat!(
                "\x1b]5522;type=write:id=bad\x1b\\",
                "\x1b]5522;type=wdata:mime=dGV4dC9wbGFpbg==;%%%\x1b\\",
                "\x1b]5522;type=wdata\x1b\\",
                "\x1b]5522;type=write:id=good\x1b\\",
                "\x1b]5522;type=wdata:mime=dGV4dC9wbGFpbg==;b2s=\x1b\\",
                "\x1b]5522;type=wdata\x1b\\"
            )
            .as_bytes(),
            TerminalEmulation::Xterm256,
        );
        assert_eq!(events.len(), 2);
        assert!(matches!(
            &events[0],
            CallbackEvent::ClipboardMimeError { payload }
                if payload["status"] == "EINVAL" && payload["id"] == "bad"
        ));
        assert!(matches!(
            &events[1],
            CallbackEvent::ClipboardMimeWrite { payload }
                if payload["id"] == "good"
        ));
    }

    #[test]
    fn host_protocol_parses_osc5522_across_every_byte_boundary() {
        let mut host = HostProtocolState::default();
        let sequence = concat!(
            "\x1b]5522;type=write:id=byte-split\x1b\\",
            "\x1b]5522;type=wdata:mime=YXBwbGljYXRpb24vb2N0ZXQtc3RyZWFt;AAEC/w==\x1b\\",
            "\x1b]5522;type=wdata\x1b\\"
        );
        let mut events = Vec::new();
        for byte in sequence.as_bytes() {
            events.extend(host.observe(std::slice::from_ref(byte), TerminalEmulation::Xterm256));
        }
        let [CallbackEvent::ClipboardMimeWrite { payload }] = events.as_slice() else {
            panic!("expected every-byte split write: {events:?}");
        };
        assert_eq!(payload["id"], "byte-split");
        assert_eq!(payload["items"][0]["mime"], "application/octet-stream");
        assert_eq!(payload["items"][0]["data"], "AAEC/w==");
    }

    #[test]
    fn host_protocol_rejects_osc5522_nonempty_start_and_oversized_chunk() {
        let oversized = BASE64_STANDARD.encode(vec![0x5a; OSC5522_MAX_CHUNK_BYTES + 1]);
        let sequence = format!(
            "\x1b]5522;type=write:id=start-data;QQ==\x1b\\\
             \x1b]5522;type=write:id=too-large\x1b\\\
             \x1b]5522;type=wdata:mime=YXBwbGljYXRpb24vb2N0ZXQtc3RyZWFt;{oversized}\x1b\\"
        );
        let events =
            HostProtocolState::default().observe(sequence.as_bytes(), TerminalEmulation::Xterm256);
        assert_eq!(events.len(), 2);
        assert!(matches!(
            &events[0],
            CallbackEvent::ClipboardMimeError { payload }
                if payload["status"] == "EINVAL" && payload["id"] == "start-data"
        ));
        assert!(matches!(
            &events[1],
            CallbackEvent::ClipboardMimeError { payload }
                if payload["status"] == "EINVAL" && payload["id"] == "too-large"
        ));
    }

    #[test]
    fn terminal_filtered_bridge_applies_policy_and_size_before_host_observer() {
        let mut denied_terminal = Terminal::new(80, 24);
        denied_terminal.set_osc_capability_allowed(OscCapability::Appearance, false);
        let mut denied_host = HostProtocolState::default();
        denied_terminal.process_with_filtered_input(b"\x1b]1;secret-icon\x07", |filtered| {
            assert!(
                denied_host
                    .observe(filtered, TerminalEmulation::Xterm256)
                    .is_empty()
            );
        });
        assert!(denied_terminal.icon_name().is_empty());
        denied_terminal.process_with_filtered_input(
            b"\x1b]0;secret-combined\x1b\\\x1b]Lsecret-legacy\x07",
            |filtered| {
                assert!(
                    denied_host
                        .observe(filtered, TerminalEmulation::Xterm256)
                        .is_empty()
                );
            },
        );
        assert_eq!(denied_terminal.title(), "");
        assert!(denied_terminal.icon_name().is_empty());

        let mut oversized_terminal = Terminal::new(80, 24);
        let mut oversized_host = HostProtocolState::default();
        let mut oversized = b"\x1b]1;".to_vec();
        oversized.extend(std::iter::repeat_n(b'x', 4097));
        oversized.extend_from_slice(b"\x07visible");
        oversized_terminal.process_with_filtered_input(&oversized, |filtered| {
            assert_eq!(filtered, b"visible");
            assert!(
                oversized_host
                    .observe(filtered, TerminalEmulation::Xterm256)
                    .is_empty()
            );
        });
        assert!(oversized_terminal.icon_name().is_empty());

        let mut oversized_legacy_terminal = Terminal::new(80, 24);
        let mut oversized_legacy_host = HostProtocolState::default();
        let mut oversized_legacy = b"\x1b]L".to_vec();
        oversized_legacy.extend(std::iter::repeat_n(b'x', 4097));
        oversized_legacy.extend_from_slice(b"\x1b\\visible");
        oversized_legacy_terminal.process_with_filtered_input(&oversized_legacy, |filtered| {
            assert_eq!(filtered, b"visible");
            assert!(
                oversized_legacy_host
                    .observe(filtered, TerminalEmulation::Xterm256)
                    .is_empty()
            );
        });
        assert!(oversized_legacy_terminal.icon_name().is_empty());
    }

    #[test]
    fn host_protocol_observe_emits_split_shell_hook_dcs() {
        let mut state = HostProtocolState::default();

        assert!(
            state
                .observe(
                    b"\x1bPhook;7b22686f6f6b223a22707265636d64222c",
                    TerminalEmulation::Xterm256
                )
                .is_empty()
        );
        assert!(!state.buffer.is_empty());

        let events = state.observe(
            b"22707764223a222f746d702f69616e7673207465726d696e616c227d\x1b\\",
            TerminalEmulation::Xterm256,
        );

        assert_eq!(events.len(), 1);
        match &events[0] {
            CallbackEvent::ShellHook { payload } => {
                assert_eq!(payload["hook"].as_str(), Some("precmd"));
                assert_eq!(payload["pwd"].as_str(), Some("/tmp/ianvs terminal"));
            }
            event => panic!("expected shell hook event, got {event:?}"),
        }
        assert!(state.buffer.is_empty());
    }

    #[test]
    fn diagnostics_summary_marks_missing_pid_as_insufficient_evidence() {
        let stats = SessionDebugStats::default();
        let summary = diagnostics_summary(None, &[], &stats, None);

        assert_eq!(summary.conclusion, "insufficient-evidence");
        assert_eq!(summary.attribution_scores.insufficient_evidence, 1.0);
    }

    #[test]
    fn diagnostics_summary_labels_high_direct_child_cpu() {
        let stats = SessionDebugStats::default();
        let samples = vec![
            ResourceSample {
                timestamp_micros: 1,
                session_id: 1,
                child_pid: Some(42),
                process_name: "sh".to_string(),
                cpu_percent: Some(5.0),
                rss_bytes: Some(16 * 1024 * 1024),
                virtual_bytes: Some(32 * 1024 * 1024),
                thread_count: Some(1),
                total_user_micros: Some(100),
                total_system_micros: Some(10),
                sample_error: None,
            },
            ResourceSample {
                timestamp_micros: 2,
                session_id: 1,
                child_pid: Some(42),
                process_name: "sh".to_string(),
                cpu_percent: Some(85.0),
                rss_bytes: Some(16 * 1024 * 1024),
                virtual_bytes: Some(32 * 1024 * 1024),
                thread_count: Some(1),
                total_user_micros: Some(900),
                total_system_micros: Some(10),
                sample_error: None,
            },
        ];

        let summary = diagnostics_summary(Some(42), &samples, &stats, None);

        assert_eq!(summary.conclusion, "user-command");
        assert!(summary.attribution_scores.user_command >= 0.5);
        assert_eq!(summary.attribution_scores.insufficient_evidence, 0.0);
    }

    #[test]
    fn tail_vec_returns_recent_entries_in_order() {
        let values = (0..70).collect::<VecDeque<_>>();

        let tail = tail_vec(&values, RESOURCE_SAMPLE_CAPACITY);

        assert_eq!(tail.len(), RESOURCE_SAMPLE_CAPACITY);
        assert_eq!(tail.first(), Some(&10));
        assert_eq!(tail.last(), Some(&69));
    }

    #[test]
    fn diagnostic_event_payload_summarizes_shell_privacy_fields() {
        let payload = serde_json::json!({
            "hook": "command_finished",
            "command": "/usr/bin/git status --short",
            "pwd": "/Users/alice/project/ianvs terminal",
            "username": "alice",
            "hostname": "alice-mac.local",
            "exit_code": 0,
        });

        let sanitized = sanitize_diagnostic_event_payload("shell_hook", Some(&payload))
            .expect("expected sanitized shell hook");

        assert_eq!(sanitized["hook"].as_str(), Some("command_finished"));
        assert_eq!(
            sanitized["command"]["executable_basename"].as_str(),
            Some("git")
        );
        assert_eq!(sanitized["command"]["arg_count"].as_u64(), Some(2));
        assert!(sanitized["command"]["hash"].as_str().is_some());
        assert_eq!(sanitized["cwd"]["path_class"].as_str(), Some("home"));
        assert!(sanitized["cwd"]["hash"].as_str().is_some());
        assert!(sanitized["username_hash"].as_str().is_some());
        assert!(sanitized["hostname_hash"].as_str().is_some());
        assert!(!sanitized.to_string().contains("alice"));
        assert!(!sanitized.to_string().contains("/Users/alice"));
        assert!(!sanitized.to_string().contains("status --short"));
    }

    #[test]
    fn diagnostic_progress_payload_hashes_private_identity() {
        let secret_id = "private-build-id-123";
        let secret_label = "private deployment label";
        let payload = serde_json::json!({
            "source": "ianvs_osc934",
            "named": true,
            "action": "set",
            "id": secret_id,
            "state": "normal",
            "percent": 42,
            "label": secret_label,
        });

        let sanitized = sanitize_diagnostic_event_payload("session_progress", Some(&payload))
            .expect("expected sanitized progress event");

        assert_eq!(
            sanitized["id_chars"].as_u64(),
            Some(secret_id.chars().count() as u64)
        );
        assert!(sanitized["id_hash"].as_str().is_some());
        assert!(sanitized["label_hash"].as_str().is_some());
        assert!(sanitized.get("id").is_none());
        let serialized = sanitized.to_string();
        assert!(!serialized.contains(secret_id));
        assert!(!serialized.contains(secret_label));
    }

    #[test]
    fn tab_status_bridge_preserves_incremental_presence_and_privacy() {
        let callback = callback_event_from_parser_event(
            ParserTerminalEvent::TabStatusChanged(
                par_term_emu_core_rust::terminal::TabStatusUpdate {
                    indicator_present: true,
                    indicator: Some("#ff9500".to_string()),
                    status_present: true,
                    status: Some("private deployment state".to_string()),
                    status_color_present: false,
                    status_color: None,
                },
            ),
            false,
        )
        .expect("expected callback");

        let CallbackEvent::SessionTabStatus { payload } = callback else {
            panic!("expected session tab status callback");
        };
        assert_eq!(payload["indicatorPresent"].as_bool(), Some(true));
        assert_eq!(payload["indicator"].as_str(), Some("#ff9500"));
        assert_eq!(payload["statusPresent"].as_bool(), Some(true));
        assert_eq!(payload["status"].as_str(), Some("private deployment state"));
        assert_eq!(payload["statusColorPresent"].as_bool(), Some(false));

        let sanitized = sanitize_diagnostic_event_payload("session_tab_status", Some(&payload))
            .expect("expected sanitized tab status");
        assert_eq!(sanitized["status_chars"].as_u64(), Some(24));
        assert!(sanitized["status_hash"].as_str().is_some());
        assert!(sanitized.get("status").is_none());
        assert!(!sanitized.to_string().contains("private deployment state"));
    }

    #[test]
    fn diagnostic_notification_payload_redacts_osc99_identity_and_text() {
        let identifier = "private-notification-id";
        let title = "secret deploy title";
        let message = "secret deploy body";
        let application = "private-build-tool";
        let payload = serde_json::json!({
            "source": "osc99",
            "action": "update",
            "id": identifier,
            "title": title,
            "message": message,
            "application": application,
            "types": ["deploy", "private"],
            "expiresAfterMs": 250,
            "reportActivation": true,
            "reportClose": true,
            "buttons": ["Approve secret", "Cancel secret"],
        });

        let sanitized = sanitize_diagnostic_event_payload("session_notification", Some(&payload))
            .expect("expected sanitized notification event");

        assert_eq!(sanitized["source"].as_str(), Some("osc99"));
        assert_eq!(sanitized["action"].as_str(), Some("update"));
        assert_eq!(sanitized["type_count"].as_u64(), Some(2));
        assert_eq!(sanitized["expires_after_ms"].as_u64(), Some(250));
        assert_eq!(sanitized["report_activation"].as_bool(), Some(true));
        assert_eq!(sanitized["report_close"].as_bool(), Some(true));
        assert_eq!(sanitized["button_count"].as_u64(), Some(2));
        assert!(sanitized["id_hash"].as_str().is_some());
        assert!(sanitized["title_hash"].as_str().is_some());
        assert!(sanitized["message_hash"].as_str().is_some());
        assert!(sanitized["application_hash"].as_str().is_some());
        let serialized = sanitized.to_string();
        for secret in [
            identifier,
            title,
            message,
            application,
            "deploy",
            "private",
            "Approve secret",
            "Cancel secret",
        ] {
            assert!(!serialized.contains(secret));
        }
    }

    #[test]
    fn diagnostic_terminal_context_payload_redacts_all_private_text() {
        let payload = serde_json::json!({
            "source": "osc3008",
            "action": "start",
            "id": "private-context-id",
            "depth": 2,
            "active": true,
            "type": "command",
            "user": "alice-secret",
            "hostname": "private-host.local",
            "cwd": "/Users/alice/private-project",
            "commandLine": "deploy --token=secret",
            "pid": 42,
            "implicitClosedCount": 0,
        });

        let sanitized = sanitize_diagnostic_event_payload("terminal_context", Some(&payload))
            .expect("expected sanitized terminal context event");

        assert_eq!(sanitized["source"].as_str(), Some("osc3008"));
        assert_eq!(sanitized["action"].as_str(), Some("start"));
        assert_eq!(sanitized["depth"].as_u64(), Some(2));
        assert_eq!(sanitized["type"].as_str(), Some("command"));
        assert!(sanitized["id"]["hash"].as_str().is_some());
        assert!(sanitized["command_line"]["hash"].as_str().is_some());
        let serialized = sanitized.to_string();
        for secret in [
            "private-context-id",
            "alice-secret",
            "private-host.local",
            "/Users/alice/private-project",
            "deploy --token=secret",
        ] {
            assert!(!serialized.contains(secret));
        }
    }
}
