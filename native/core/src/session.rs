use crate::frame_diff_proto;
use crate::model::{
    MAX_SCROLLBACK_LINES, TERMINAL_FRAME_SCHEMA_VERSION, TerminalCursor, TerminalCursorShape,
    TerminalDirtyRange, TerminalEmulation, TerminalEvent, TerminalFrameDiff, TerminalFrameKind,
    TerminalFrameModes, TerminalGraphicPlacement, TerminalHyperlinkRange, TerminalProfile,
    TerminalProfileAnsiColors, TerminalProfileColors, TerminalRow, TerminalSearchMatch,
    TerminalSelectionRequest, TerminalSizedTextPlacement, TerminalStyleRun,
    normalize_scrollback_lines,
};
use crate::pty::spawn_pty;
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use par_term_emu_core_rust::cell::{Cell, CellFlags};
use par_term_emu_core_rust::color::Color;
use par_term_emu_core_rust::graphics::placeholder::{PlaceholderInfo, parse_diacritics};
use par_term_emu_core_rust::graphics::{
    ImageDimension, ImageSizeUnit, PLACEHOLDER_CHAR, TerminalGraphic,
};
use par_term_emu_core_rust::grid::{Grid, ScrollRegionDamage};
use par_term_emu_core_rust::mouse::{MouseEncoding, MouseMode};
use par_term_emu_core_rust::terminal::{
    OscCapability, Terminal, TerminalDamage, TerminalEvent as ParserTerminalEvent,
    TerminalProcessDebugStats, snapshot::ExportFormat,
};
use parking_lot::Mutex;
use regex::RegexBuilder;
use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};
use std::hash::{DefaultHasher, Hash, Hasher};
use std::io::{Read, Write};
use std::sync::{
    Arc, LazyLock,
    atomic::{AtomicBool, Ordering},
};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const DEFAULT_ROWS: u16 = 32;
const DEFAULT_COLS: u16 = 120;
const MAX_TRANSCRIPT_BYTES: usize = 256 * 1024;
const RESOURCE_SAMPLE_CAPACITY: usize = 60;
const MAX_PENDING_SESSION_EVENTS: usize = 1024;
const MAX_PENDING_SESSION_EVENT_BYTES: usize = 8 * 1024 * 1024;
const MAX_DIAGNOSTIC_EVENTS: usize = 256;
const EVENT_QUEUE_OVERFLOW_DIAGNOSTIC_KIND: &str = "event_queue_overflow";
const RESOURCE_SAMPLE_INTERVAL: Duration = Duration::from_secs(1);
const INLINE_CLEAR_REPAINT_GRACE: Duration = Duration::from_millis(180);
const RESOURCE_SAMPLER_MAX_FAILURES: u64 = 5;
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TerminalSearchMode {
    SmartCaseSubstring,
    CaseSensitiveSubstring,
    CaseInsensitiveSubstring,
    CaseSensitiveRegex,
    CaseInsensitiveRegex,
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
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct PendingEventPushResult {
    emit_overflow_diagnostic: bool,
}

#[derive(Debug, Default)]
struct PendingEventQueue {
    entries: VecDeque<QueuedTerminalEvent>,
    aggregate_bytes: usize,
    dropped_count: u64,
    overflow_diagnostic_emitted: bool,
    limits: PendingEventLimits,
}

impl PendingEventQueue {
    fn with_initial(event: TerminalEvent) -> Self {
        let mut queue = Self::default();
        let _ = queue.push(event);
        queue
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
        let wire_bytes = terminal_event_wire_size(&event);
        if self.limits.max_count == 0
            || self.limits.max_bytes == 0
            || wire_bytes > self.limits.max_bytes
        {
            return self.record_drop();
        }

        self.aggregate_bytes = self.aggregate_bytes.saturating_add(wire_bytes);
        self.entries
            .push_back(QueuedTerminalEvent { event, wire_bytes });

        let mut result = PendingEventPushResult::default();
        while self.entries.len() > self.limits.max_count
            || self.aggregate_bytes > self.limits.max_bytes
        {
            let index = self.eviction_index();
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

    fn eviction_index(&self) -> usize {
        self.entries
            .iter()
            .position(|entry| pending_event_is_coalescible(&entry.event.kind))
            .or_else(|| {
                self.entries
                    .iter()
                    .position(|entry| !pending_event_is_critical(&entry.event.kind))
            })
            // A critical-only flood cannot be both lossless and hard-bounded.
            // Prefer retaining `exit`; otherwise discard the oldest clipboard
            // request only after every non-critical event is gone.
            .or_else(|| {
                self.entries
                    .iter()
                    .position(|entry| entry.event.kind != "exit")
            })
            .unwrap_or(0)
    }

    fn record_drop(&mut self) -> PendingEventPushResult {
        self.dropped_count = self.dropped_count.saturating_add(1);
        let emit_overflow_diagnostic = !self.overflow_diagnostic_emitted;
        self.overflow_diagnostic_emitted = true;
        PendingEventPushResult {
            emit_overflow_diagnostic,
        }
    }

    fn drain(&mut self) -> Vec<TerminalEvent> {
        self.aggregate_bytes = 0;
        self.entries.drain(..).map(|entry| entry.event).collect()
    }

    fn len(&self) -> usize {
        self.entries.len()
    }
}

fn pending_event_is_coalescible(kind: &str) -> bool {
    matches!(
        kind,
        "bell" | "resize" | "shell_context" | "session_progress" | "session_badge"
    )
}

fn pending_event_is_critical(kind: &str) -> bool {
    matches!(
        kind,
        "exit"
            | "clipboard_copy"
            | "clipboard_paste_request"
            | "clipboard_mime_write"
            | "clipboard_mime_read_request"
            | "clipboard_mime_error"
            | "session_reset"
    )
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

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct CachedRowState {
    text: String,
    wrapped: bool,
    continues_from_previous: bool,
    style_signature: u64,
    hyperlink_signature: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct CachedFrameMeta {
    viewport_rows: usize,
    viewport_cols: usize,
    scrollback_offset: usize,
    viewport_start_row: usize,
    alt_screen_active: bool,
    default_foreground_rgb: (u8, u8, u8),
    default_background_rgb: (u8, u8, u8),
    cursor_color_rgb: (u8, u8, u8),
    cursor_guide_color_rgb: (u8, u8, u8),
    selection_background_rgb: (u8, u8, u8),
    selection_foreground_rgb: Option<(u8, u8, u8)>,
    link_color_rgb: Option<(u8, u8, u8)>,
    cursor_text_color_rgb: Option<(u8, u8, u8)>,
    tab_color_rgb: Option<(u8, u8, u8)>,
    pointer_shape: Option<String>,
    ansi_palette: [Color; 256],
    modes: TerminalFrameModes,
    window_title: Option<String>,
    window_icon_name: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct PendingScrollRegion {
    top: usize,
    bottom_exclusive: usize,
    delta_rows: i32,
}

impl From<ScrollRegionDamage> for PendingScrollRegion {
    fn from(value: ScrollRegionDamage) -> Self {
        Self {
            top: value.top,
            bottom_exclusive: value.bottom_exclusive,
            delta_rows: value.delta_rows,
        }
    }
}

#[derive(Clone, Debug)]
struct DeferredFrameGrace {
    damage_generation: u64,
    started_at: Instant,
}

#[derive(Clone, Debug, Default)]
struct PendingFrameWork {
    full_repaint: bool,
    snapshot_fallback_reason: Option<String>,
    dirty_rows: BTreeSet<usize>,
    scroll_region: Option<PendingScrollRegion>,
    cursor_before: Option<TerminalCursor>,
    cursor_after: Option<TerminalCursor>,
    damage_generation: u64,
}

impl PendingFrameWork {
    fn is_empty(&self) -> bool {
        !self.full_repaint
            && self.snapshot_fallback_reason.is_none()
            && self.dirty_rows.is_empty()
            && self.scroll_region.is_none()
            && self.cursor_before.is_none()
            && self.cursor_after.is_none()
            && self.damage_generation == 0
    }

    fn mark_full_repaint(&mut self, reason: &str) {
        self.full_repaint = true;
        self.dirty_rows.clear();
        self.scroll_region = None;
        self.bump_generation();
        if self.snapshot_fallback_reason.is_none() {
            self.snapshot_fallback_reason = Some(reason.to_string());
        }
    }

    fn merge_terminal_damage(
        &mut self,
        damage: TerminalDamage,
        cursor_before: TerminalCursor,
        cursor_after: TerminalCursor,
    ) {
        self.bump_generation();
        if self.cursor_before.is_none() {
            self.cursor_before = Some(cursor_before);
        }
        self.cursor_after = Some(cursor_after);

        if damage.full_repaint {
            self.full_repaint = true;
            self.dirty_rows.clear();
            self.scroll_region = None;
            if self.snapshot_fallback_reason.is_none() {
                self.snapshot_fallback_reason = damage.snapshot_fallback_reason;
            }
            return;
        }

        self.dirty_rows.extend(damage.dirty_rows);
        if let Some(scroll_region) = damage.scroll_region {
            self.merge_scroll_region(scroll_region.into());
        }
    }

    fn merge_scroll_region(&mut self, scroll_region: PendingScrollRegion) {
        match self.scroll_region.as_mut() {
            None => {
                self.scroll_region = Some(scroll_region);
            }
            Some(existing)
                if existing.top == scroll_region.top
                    && existing.bottom_exclusive == scroll_region.bottom_exclusive
                    && existing.delta_rows.signum() == scroll_region.delta_rows.signum() =>
            {
                existing.delta_rows = existing.delta_rows.saturating_add(scroll_region.delta_rows);
            }
            Some(_) => self.mark_full_repaint("conflicting_scroll_regions"),
        }
    }

    fn bump_generation(&mut self) {
        self.damage_generation = self.damage_generation.saturating_add(1);
    }
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
        let session_id = self.next_session_id();
        let session = TerminalSession::spawn(session_id, profile)?;
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
        if let Some(session) = self.sessions.lock().remove(&session_id) {
            session.close()?;
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
    #[error("invalid selection JSON: {0}")]
    InvalidSelection(String),
    #[error("pty error: {0}")]
    Pty(String),
    #[error("io error: {0}")]
    Io(String),
    #[error("serialization error: {0}")]
    Serialize(String),
    #[error("graphic asset error: {0}")]
    GraphicAsset(String),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GraphicAssetMeta {
    pub width: u32,
    pub height: u32,
    pub rgba_len: usize,
    pub version: u64,
}

struct GraphicAssetSnapshot {
    asset_id: u64,
    asset_version: u64,
    width: usize,
    height: usize,
    pixels: Arc<Vec<u8>>,
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
    window_icon_name: Option<String>,
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
                    // Mirror RIS for the small native-side observer state.
                    // The parser owns the typed TerminalReset event; this
                    // prevents a previously reported OSC 1 icon from being
                    // copied back into frames after that reset.
                    self.window_icon_name = None;
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
            b"1" => {
                self.window_icon_name = match String::from_utf8(remainder.to_vec()) {
                    Ok(value) if !value.is_empty() => Some(value),
                    _ => None,
                };
            }
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
    osc633_expected_nonce: Option<String>,
    state: Mutex<TerminalState>,
    writer: Mutex<Box<dyn Write + Send>>,
    master: Mutex<Box<dyn portable_pty::MasterPty + Send>>,
    child: Mutex<Box<dyn portable_pty::Child + Send + Sync>>,
    child_pid: Option<u32>,
    process_name: String,
    events: Mutex<PendingEventQueue>,
    diagnostic_events: Mutex<VecDeque<TerminalDiagnosticEvent>>,
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

#[derive(Clone, Copy, Debug)]
struct TerminalGraphicsMemoryLimits {
    max_image_bytes: usize,
    max_total_bytes: usize,
}

#[derive(Default)]
struct SessionWorkerHandles {
    reader: Option<thread::JoinHandle<()>>,
    resource_sampler: Option<thread::JoinHandle<()>>,
}

impl TerminalSession {
    pub fn spawn(session_id: u64, profile: TerminalProfile) -> Result<Arc<Self>, SessionError> {
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
        let osc633_expected_nonce = match profile.launch.env.get("VSCODE_NONCE") {
            Some(nonce) if Terminal::is_valid_osc633_nonce(nonce) => Some(nonce.clone()),
            Some(_) => {
                return Err(SessionError::InvalidProfile(
                    "VSCODE_NONCE must be 1-256 UTF-8 bytes without controls or semicolons"
                        .to_string(),
                ));
            }
            None => None,
        };
        let runtime = spawn_pty(&profile, DEFAULT_ROWS, DEFAULT_COLS)
            .map_err(|error: anyhow::Error| SessionError::Pty(error.to_string()))?;
        let child_pid = runtime.child_pid;
        let process_name = process_name_for_profile(&profile);
        let reader = runtime.reader;
        let shell_integration_diagnostics = runtime.shell_integration.to_diagnostic_json();
        let shell_integration_proxy = runtime.shell_integration_proxy;

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
            osc633_expected_nonce.as_deref(),
            drag_drop_enabled,
        );

        let session = Arc::new(Self {
            session_id,
            emulation,
            scrollback_lines,
            graphics_enabled,
            drag_drop_enabled,
            graphics_memory_limits,
            profile_colors,
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
            }),
            writer: Mutex::new(runtime.writer),
            master: Mutex::new(runtime.master),
            child: Mutex::new(runtime.child),
            child_pid,
            process_name,
            events: Mutex::new(PendingEventQueue::with_initial(TerminalEvent {
                kind: "started".to_string(),
                session_id,
                payload: None,
            })),
            diagnostic_events: Mutex::new(VecDeque::from([TerminalDiagnosticEvent {
                timestamp_micros: unix_timestamp_micros(),
                session_id,
                kind: "started".to_string(),
                payload: Some(serde_json::json!({
                    "shell_integration": shell_integration_diagnostics,
                })),
            }])),
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
        });

        let reader_session = Arc::clone(&session);
        let reader_handle = thread::spawn(move || {
            let _shell_integration_proxy = shell_integration_proxy;
            let mut reader = reader;
            let mut buf = [0_u8; 4096];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) => break,
                    Ok(read) => {
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
                            let mut state = reader_session.state.lock();
                            let cursor_before =
                                terminal_cursor_snapshot(&state.terminal, state.terminal.cursor());
                            let process_started_at = Instant::now();
                            let was_alt_screen_active = state.terminal.is_alt_screen_active();
                            let input_enters_alt_screen = input_sets_alt_screen(&buf[..read]);
                            let mut callback_events = Vec::new();
                            let mut host_protocol_micros = 0_u64;
                            let TerminalState {
                                terminal,
                                host_protocol,
                                ..
                            } = &mut *state;
                            terminal.process_with_filtered_input(&buf[..read], |filtered| {
                                let host_started_at = Instant::now();
                                callback_events =
                                    host_protocol.observe(filtered, reader_session.emulation);
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
                            if reader_session.emulation == TerminalEmulation::Xterm256 {
                                let suppress_shell_zones = was_alt_screen_active
                                    || input_enters_alt_screen
                                    || state.terminal.is_alt_screen_active();
                                callback_events.extend(parser_events.into_iter().filter_map(
                                    |event| {
                                        callback_event_from_parser_event_with_terminal(
                                            event,
                                            suppress_shell_zones,
                                            Some(&state.terminal),
                                        )
                                    },
                                ));
                                callback_events.extend(notifications.into_iter().map(
                                    |notification| {
                                        CallbackEvent::SessionNotification {
                                            source: notification.source.to_string(),
                                            action: notification.action.as_str().to_string(),
                                            identifier: notification.identifier.map(|identifier| {
                                                sanitize_protocol_text(&identifier, 128)
                                            }),
                                            title: sanitize_protocol_text(&notification.title, 160),
                                            message: sanitize_protocol_text(
                                                &notification.message,
                                                512,
                                            ),
                                            application_name: notification.application_name.map(
                                                |application_name| {
                                                    sanitize_protocol_text(&application_name, 160)
                                                },
                                            ),
                                            notification_types: notification
                                                .notification_types
                                                .into_iter()
                                                .take(8)
                                                .map(|notification_type| {
                                                    sanitize_protocol_text(&notification_type, 64)
                                                })
                                                .collect(),
                                            expires_after_ms: notification.expires_after_ms,
                                        }
                                    },
                                ));
                            }
                            if cleared_scrollback {
                                // Terminal-originated CSI 3 J and iTerm2 OSC
                                // 1337 ClearScrollback invalidate replay and
                                // navigation history just like the host API.
                                state.scrollback_offset = 0;
                                state.transcript.clear();
                                state.transcript_truncated = true;
                            }
                            let terminal_process_micros = (process_started_at.elapsed().as_micros()
                                as u64)
                                .saturating_sub(host_protocol_micros);
                            let terminal_process_breakdown =
                                state.terminal.take_process_debug_stats();
                            if !cleared_scrollback {
                                append_transcript(&mut state, &buf[..read]);
                            }
                            let damage = state.terminal.drain_active_screen_damage();
                            let cursor_after =
                                terminal_cursor_snapshot(&state.terminal, state.terminal.cursor());
                            let responses = normalize_responses(
                                reader_session.emulation,
                                state.terminal.drain_responses(),
                            );
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
                        reader_session.pending_frame_signal.mutate_reader(|work| {
                            work.merge_terminal_damage(damage, cursor_before, cursor_after);
                        });
                        let damage_merge_micros =
                            damage_merge_started_at.elapsed().as_micros() as u64;

                        if cleared_scrollback {
                            reader_session.last_rows.lock().clear();
                            *reader_session.last_frame_meta.lock() = None;
                            reader_session
                                .pending_frame_signal
                                .mutate(|work| work.mark_full_repaint("terminal_clear_scrollback"));
                        }

                        for event in callback_events {
                            reader_session.push_callback_event(event);
                        }
                        let response_write_started_at = Instant::now();
                        if !responses.is_empty() {
                            let _ = reader_session.writer.lock().write_all(&responses);
                        }
                        let response_write_micros =
                            response_write_started_at.elapsed().as_micros() as u64;
                        reader_session.record_input_debug_stats(
                            read,
                            host_protocol_micros,
                            terminal_process_micros,
                            terminal_process_breakdown,
                            damage_merge_micros,
                            response_write_micros,
                        );
                    }
                    Err(_) => break,
                }
            }
        });
        let resource_sampler_handle = Self::start_resource_sampler(&session);
        {
            let mut worker_handles = session.worker_handles.lock();
            worker_handles.reader = Some(reader_handle);
            worker_handles.resource_sampler = Some(resource_sampler_handle);
        }

        Ok(session)
    }

    pub fn ping(&self) -> i32 {
        42
    }

    pub fn refresh_hint_flags(&self) -> u32 {
        if self.pending_frame_signal.has_refresh_hint() {
            REFRESH_HINT_FRAME_DIRTY
        } else {
            0
        }
    }

    pub fn close(&self) -> Result<(), SessionError> {
        self.exited.store(true, Ordering::SeqCst);
        let _ = self.child.lock().kill();
        self.join_worker_threads();
        Ok(())
    }

    fn join_worker_threads(&self) {
        let (reader, resource_sampler) = {
            let mut worker_handles = self.worker_handles.lock();
            (
                worker_handles.reader.take(),
                worker_handles.resource_sampler.take(),
            )
        };

        if let Some(handle) = resource_sampler {
            handle.thread().unpark();
            let _ = handle.join();
        }
        if let Some(handle) = reader {
            let _ = handle.join();
        }
    }

    fn start_resource_sampler(session: &Arc<Self>) -> thread::JoinHandle<()> {
        let resource_session = Arc::clone(session);
        thread::spawn(move || {
            loop {
                if resource_session.exited.load(Ordering::SeqCst) {
                    break;
                }
                let keep_sampling = resource_session.record_resource_sample();
                let failures = resource_session
                    .resource_sampler_state
                    .lock()
                    .consecutive_failures;
                if !keep_sampling && failures >= RESOURCE_SAMPLER_MAX_FAILURES {
                    break;
                }
                thread::park_timeout(RESOURCE_SAMPLE_INTERVAL);
            }
        })
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
        let mut state = self.state.lock();
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
            return Ok(());
        }

        let previous_max = current_scrollback_max(&state);

        // Keep SIGWINCH-triggered redraw output from being processed between
        // the PTY resize and the internal reflow/replay. Otherwise readline can
        // leak transient prompt redraws into the replay transcript.
        self.master
            .lock()
            .resize(portable_pty::PtySize {
                rows,
                cols,
                pixel_width,
                pixel_height,
            })
            .map_err(|error| SessionError::Pty(error.to_string()))?;

        let should_rebuild_main_screen = !state.terminal.is_alt_screen_active();

        if should_rebuild_main_screen && !state.transcript_truncated {
            let transcript = state.transcript.clone();
            let mut terminal =
                Terminal::with_scrollback(cols as usize, rows as usize, self.scrollback_lines);
            configure_session_terminal(
                &mut terminal,
                self.emulation,
                self.graphics_memory_limits,
                &self.profile_colors,
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
            terminal.process(&transcript);
            // Replaying the transcript rebuilds terminal state only. Historical
            // host-facing effects must not be delivered again on the next PTY
            // read after resize.
            let _ = terminal.poll_events();
            let _ = terminal.take_notifications();
            let _ = terminal.drain_responses();
            let _ = terminal.take_process_debug_stats();
            state.terminal = terminal;
        } else {
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

        self.last_rows.lock().clear();
        *self.last_frame_meta.lock() = None;
        self.pending_frame_signal
            .mutate(|work| work.mark_full_repaint("resize"));
        Ok(())
    }

    pub fn write(&self, bytes: &[u8]) -> Result<(), SessionError> {
        self.writer
            .lock()
            .write_all(bytes)
            .map_err(|error| SessionError::Io(error.to_string()))
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
            state.host_protocol.window_icon_name.clone()
        } else {
            None
        };
        let pointer_shape = if self.emulation == TerminalEmulation::Xterm256 {
            terminal.pointer_shape_name().map(str::to_string)
        } else {
            None
        };
        let viewport_start_row = if alt_screen_active {
            0
        } else {
            scrollback_max_offset.saturating_sub(state.scrollback_offset)
        };
        let scrollback_len = if alt_screen_active {
            0
        } else {
            terminal.grid().scrollback_len()
        };
        let cursor_snapshot = terminal_cursor_snapshot(terminal, cursor);
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
        };
        let snapshot_fallback_reason = snapshot_fallback_reason(
            &pending_frame_work,
            &last_rows,
            last_frame_meta.as_ref(),
            &frame_meta,
        );
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
                build_snapshot_frame(terminal, self.emulation, viewport_start_row, viewport_rows)
            } else {
                build_delta_frame(DeltaFrameContext {
                    terminal,
                    emulation: self.emulation,
                    viewport_start_row,
                    viewport_rows,
                    scrollback_len,
                    alt_screen_active,
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
                let placements = build_graphic_placements(
                    terminal,
                    viewport_start_row,
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
            build_sized_text_placements(terminal, viewport_start_row, viewport_rows)
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
            hyperlinks,
            sized_text,
            graphics,
        }))
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

            for visible_index in 0..total_lines {
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
                    scrollback_offset: total_lines.saturating_sub(viewport_rows + visible_index),
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

    pub fn poll_events(&self) -> Result<Vec<TerminalEvent>, SessionError> {
        if !self.exited.load(Ordering::SeqCst) {
            let maybe_exit = self
                .child
                .lock()
                .try_wait()
                .map_err(|error| SessionError::Io(error.to_string()))?;

            if let Some(exit) = maybe_exit {
                self.exited.store(true, Ordering::SeqCst);
                self.push_event(
                    "exit",
                    Some(serde_json::json!({
                        "code": exit.exit_code(),
                        "success": exit.success(),
                        "signal": exit.signal(),
                    })),
                );
            }
        }

        Ok(self.events.lock().drain())
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
            CallbackEvent::SessionReset => self.push_event("session_reset", None),
            CallbackEvent::Bell => self.push_event("bell", None),
        }
    }

    fn push_event(&self, kind: &str, payload: Option<serde_json::Value>) {
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
    let theme = terminal_theme_snapshot(terminal);
    let absolute_visible_index = viewport_start_row.saturating_add(viewport_row);
    let (cells, wrapped) = row_cells_for_visible_index(terminal, absolute_visible_index);
    let continues_from_previous = absolute_visible_index > 0
        && row_cells_for_visible_index(terminal, absolute_visible_index - 1).1;
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
        },
        continues_from_previous,
        hyperlinks,
    }
}

fn shift_cached_rows(
    previous_rows: &[CachedRowState],
    viewport_rows: usize,
    viewport_row_shift: i32,
) -> Vec<CachedRowState> {
    let mut shifted = vec![CachedRowState::default(); viewport_rows];
    for (row, shifted_row) in shifted.iter_mut().enumerate() {
        let previous_index = row as isize - viewport_row_shift as isize;
        let Some(previous_index) = usize::try_from(previous_index).ok() else {
            continue;
        };
        if let Some(previous_row) = previous_rows.get(previous_index) {
            *shifted_row = previous_row.clone();
        }
    }
    shifted
}

fn build_snapshot_frame(
    terminal: &Terminal,
    emulation: TerminalEmulation,
    viewport_start_row: usize,
    viewport_rows: usize,
) -> (
    Vec<TerminalRow>,
    Vec<TerminalHyperlinkRange>,
    Vec<CachedRowState>,
    Vec<TerminalDirtyRange>,
    usize,
    usize,
) {
    let mut rows = Vec::with_capacity(viewport_rows);
    let mut hyperlinks = Vec::new();
    let mut current_rows = Vec::with_capacity(viewport_rows);

    for row in 0..viewport_rows {
        let extracted = extract_viewport_row(terminal, emulation, viewport_start_row, row);
        current_rows.push(cached_row_state_for(&extracted));
        hyperlinks.extend(extracted.hyperlinks.clone());
        rows.push(extracted.row);
    }

    let dirty_ranges = if viewport_rows == 0 {
        Vec::new()
    } else {
        vec![TerminalDirtyRange {
            start: 0,
            end: viewport_rows,
        }]
    };

    (
        rows,
        hyperlinks,
        current_rows,
        dirty_ranges,
        viewport_rows,
        viewport_rows,
    )
}

struct DeltaFrameContext<'a> {
    terminal: &'a Terminal,
    emulation: TerminalEmulation,
    viewport_start_row: usize,
    viewport_rows: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
    pending_frame_work: &'a PendingFrameWork,
    previous_rows: &'a [CachedRowState],
    viewport_row_shift: i32,
}

fn build_delta_frame(
    context: DeltaFrameContext<'_>,
) -> (
    Vec<TerminalRow>,
    Vec<TerminalHyperlinkRange>,
    Vec<CachedRowState>,
    Vec<TerminalDirtyRange>,
    usize,
    usize,
) {
    let DeltaFrameContext {
        terminal,
        emulation,
        viewport_start_row,
        viewport_rows,
        scrollback_len,
        alt_screen_active,
        pending_frame_work,
        previous_rows,
        viewport_row_shift,
    } = context;
    let candidate_row_indexes = delta_candidate_row_indexes(
        pending_frame_work,
        viewport_rows,
        viewport_start_row,
        scrollback_len,
        alt_screen_active,
        viewport_row_shift,
    );
    let mut next_rows = shift_cached_rows(previous_rows, viewport_rows, viewport_row_shift);
    let mut dirty_row_indexes = Vec::new();
    let mut rows = Vec::new();
    let mut hyperlinks = Vec::new();

    for row_index in &candidate_row_indexes {
        let extracted = extract_viewport_row(terminal, emulation, viewport_start_row, *row_index);
        let row_state = cached_row_state_for(&extracted);
        if next_rows.get(*row_index) != Some(&row_state) {
            dirty_row_indexes.push(*row_index);
            hyperlinks.extend(extracted.hyperlinks.clone());
            rows.push(extracted.row);
        }
        next_rows[*row_index] = row_state;
    }

    let dirty_ranges = merge_dirty_ranges(&dirty_row_indexes);
    let rows_emitted = rows.len();

    (
        rows,
        hyperlinks,
        next_rows,
        dirty_ranges,
        candidate_row_indexes.len(),
        rows_emitted,
    )
}

fn build_graphic_placements(
    terminal: &Terminal,
    viewport_start_row: usize,
    viewport_rows: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
    include_pending_cleared_kitty: bool,
) -> Vec<TerminalGraphicPlacement> {
    if viewport_rows == 0 {
        return Vec::new();
    }
    let (viewport_cols, total_viewport_rows) = terminal.size();
    let viewport_end_row = viewport_start_row.saturating_add(viewport_rows);
    let active_row_base = if alt_screen_active { 0 } else { scrollback_len };
    let mut placements = Vec::new();

    for graphic in terminal.all_graphics() {
        if graphic.alternate_screen != alt_screen_active {
            continue;
        }
        if let Some(placement) = graphic_placement_for_viewport(
            graphic,
            active_row_base.saturating_add(graphic.position.1),
            viewport_start_row,
            viewport_end_row,
            viewport_cols,
            total_viewport_rows,
            graphic.scroll_offset_rows,
        ) {
            placements.push(placement);
        }
    }

    if include_pending_cleared_kitty {
        for graphic in terminal.pending_cleared_kitty_graphics() {
            if graphic.alternate_screen != alt_screen_active {
                continue;
            }
            if let Some(placement) = graphic_placement_for_viewport(
                graphic,
                active_row_base.saturating_add(graphic.position.1),
                viewport_start_row,
                viewport_end_row,
                viewport_cols,
                total_viewport_rows,
                graphic.scroll_offset_rows,
            ) {
                placements.push(placement);
            }
        }
    }

    if !alt_screen_active {
        for graphic in terminal.all_scrollback_graphics() {
            let Some(scrollback_row) = graphic.scrollback_row else {
                continue;
            };
            if let Some(placement) = graphic_placement_for_viewport(
                graphic,
                scrollback_row,
                viewport_start_row,
                viewport_end_row,
                viewport_cols,
                total_viewport_rows,
                0,
            ) {
                placements.push(placement);
            }
        }
    }

    let theme = terminal_theme_snapshot(terminal);
    push_kitty_placeholder_graphic_placements(
        terminal,
        &theme,
        viewport_start_row,
        viewport_rows,
        viewport_end_row,
        viewport_cols,
        total_viewport_rows,
        alt_screen_active,
        &mut placements,
    );

    placements
}

#[allow(clippy::too_many_arguments)]
fn push_kitty_placeholder_graphic_placements(
    terminal: &Terminal,
    theme: &TerminalThemeSnapshot,
    viewport_start_row: usize,
    viewport_rows: usize,
    viewport_end_row: usize,
    viewport_cols: usize,
    total_viewport_rows: usize,
    alt_screen_active: bool,
    placements: &mut Vec<TerminalGraphicPlacement>,
) {
    for viewport_row in 0..viewport_rows {
        let visible_index = viewport_start_row.saturating_add(viewport_row);
        let (cells, _) = row_cells_for_visible_index(terminal, visible_index);
        let mut column_offset = 0usize;
        let mut previous_placeholder: Option<PlaceholderInfo> = None;

        for cell in cells.unwrap_or_default() {
            if cell.flags.wide_char_spacer() {
                continue;
            }

            let column_start = column_offset;
            column_offset = column_offset.saturating_add(cell.width());
            let Some(mut placeholder_info) = placeholder_info_from_cell(cell, theme) else {
                previous_placeholder = None;
                continue;
            };

            if let Some(previous) = previous_placeholder {
                let expected_col = previous.col.unwrap_or(0).saturating_add(1);
                if placeholder_info.can_inherit_from(&previous, expected_col) {
                    placeholder_info.inherit_from(&previous);
                }
            }
            previous_placeholder = Some(placeholder_info);

            let Some(graphic) = terminal
                .graphics_store()
                .get_placeholder_graphic(&placeholder_info)
            else {
                continue;
            };
            if graphic.alternate_screen != alt_screen_active || graphic.pixels.is_empty() {
                continue;
            }
            if let Some(placement) = kitty_placeholder_placement_for_viewport(
                graphic,
                placeholder_info,
                column_start,
                visible_index,
                viewport_start_row,
                viewport_end_row,
                viewport_cols,
                total_viewport_rows,
            ) {
                placements.push(placement);
            }
        }
    }
}

fn placeholder_info_from_cell(
    cell: &Cell,
    theme: &TerminalThemeSnapshot,
) -> Option<PlaceholderInfo> {
    let grapheme = cell.get_grapheme();
    if !grapheme.starts_with(PLACEHOLDER_CHAR) {
        return None;
    }

    let diacritics: String = grapheme.chars().skip(1).collect();
    let (row, col, msb) = parse_diacritics(&diacritics);
    Some(
        PlaceholderInfo::from_color(color_to_u24(cell.fg, theme))
            .with_placement_id(
                cell.underline_color
                    .map_or(0, |color| color_to_u24(color, theme)),
            )
            .with_diacritics(row, col, msb),
    )
}

fn color_to_u24(color: Color, theme: &TerminalThemeSnapshot) -> u32 {
    let (red, green, blue) = resolve_color_rgb(color, &theme.ansi_palette);
    ((red as u32) << 16) | ((green as u32) << 8) | blue as u32
}

#[allow(clippy::too_many_arguments)]
fn kitty_placeholder_placement_for_viewport(
    graphic: &TerminalGraphic,
    placeholder_info: PlaceholderInfo,
    placeholder_col: usize,
    absolute_row: usize,
    viewport_start_row: usize,
    viewport_end_row: usize,
    viewport_cols: usize,
    total_viewport_rows: usize,
) -> Option<TerminalGraphicPlacement> {
    let row = placeholder_info.row? as usize;
    let col = placeholder_info.col? as usize;
    let (source_x, source_y, source_width, source_height) = graphic.source_rect_pixels()?;
    let (span_cols, span_rows) = graphic.display_cell_span.unwrap_or_else(|| {
        graphic.resolved_cell_span(Some(viewport_cols), Some(total_viewport_rows))
    });
    if col >= span_cols || row >= span_rows {
        return None;
    }

    let tile_start_x = source_width.saturating_mul(col) / span_cols.max(1);
    let tile_end_x = source_width.saturating_mul(col.saturating_add(1)) / span_cols.max(1);
    let tile_start_y = source_height.saturating_mul(row) / span_rows.max(1);
    let tile_end_y = source_height.saturating_mul(row.saturating_add(1)) / span_rows.max(1);
    let tile_width = tile_end_x.saturating_sub(tile_start_x).max(1);
    let tile_height = tile_end_y.saturating_sub(tile_start_y).max(1);

    let mut placeholder_graphic = graphic.clone();
    placeholder_graphic.position = (placeholder_col, 0);
    placeholder_graphic.placement.source_x_offset =
        source_x.saturating_add(tile_start_x).min(u32::MAX as usize) as u32;
    placeholder_graphic.placement.source_y_offset =
        source_y.saturating_add(tile_start_y).min(u32::MAX as usize) as u32;
    placeholder_graphic.placement.source_width = Some(tile_width.min(u32::MAX as usize) as u32);
    placeholder_graphic.placement.source_height = Some(tile_height.min(u32::MAX as usize) as u32);
    placeholder_graphic.placement.requested_width = ImageDimension::cells(1.0);
    placeholder_graphic.placement.requested_height = ImageDimension::cells(1.0);
    placeholder_graphic.placement.columns = Some(1);
    placeholder_graphic.placement.rows = Some(1);
    placeholder_graphic.placement.x_offset = 0;
    placeholder_graphic.placement.y_offset = 0;
    placeholder_graphic.set_display_cell_span(1, 1);

    graphic_placement_for_viewport(
        &placeholder_graphic,
        absolute_row,
        viewport_start_row,
        viewport_end_row,
        viewport_cols,
        total_viewport_rows,
        0,
    )
}

fn graphic_placement_for_viewport(
    graphic: &TerminalGraphic,
    absolute_start_row: usize,
    viewport_start_row: usize,
    viewport_end_row: usize,
    viewport_cols: usize,
    total_viewport_rows: usize,
    scrolled_top_rows: usize,
) -> Option<TerminalGraphicPlacement> {
    let geometry = graphic_display_geometry(graphic, viewport_cols, total_viewport_rows)?;
    let width_px = geometry.width_px;
    let height_px = geometry.height_px;
    let width_cells = geometry.width_cells;
    let height_cells = geometry.height_cells;
    let (cell_width_px, cell_height_px) = graphic_cell_dimensions_px(graphic);
    let terminal_width_px = viewport_cols.saturating_mul(cell_width_px);
    let x_offset_px = graphic.placement.x_offset as usize;
    let graphic_left_px = graphic
        .position
        .0
        .saturating_mul(cell_width_px)
        .saturating_add(x_offset_px);
    if terminal_width_px == 0 || graphic_left_px >= terminal_width_px {
        return None;
    }
    let source_x_offset_px = geometry.source_x_offset_px;
    let visible_width_px = geometry
        .visible_width_px
        .min(terminal_width_px.saturating_sub(graphic_left_px))
        .max(1);
    let scrolled_top_rows = scrolled_top_rows.min(height_cells);
    let displayed_height_cells = height_cells.saturating_sub(scrolled_top_rows);
    if displayed_height_cells == 0 {
        return None;
    }
    let absolute_end_row = absolute_start_row.saturating_add(displayed_height_cells);
    if absolute_end_row <= viewport_start_row || absolute_start_row >= viewport_end_row {
        return None;
    }
    let row = absolute_start_row.saturating_sub(viewport_start_row);
    let viewport_hidden_rows = viewport_start_row
        .saturating_sub(absolute_start_row)
        .min(displayed_height_cells);
    let hidden_rows = scrolled_top_rows.saturating_add(viewport_hidden_rows);
    let visible_height_cells = displayed_height_cells
        .saturating_sub(viewport_hidden_rows)
        .min(viewport_end_row.saturating_sub(absolute_start_row.max(viewport_start_row)));
    if visible_height_cells == 0 {
        return None;
    }
    let y_offset_px = graphic.placement.y_offset as usize;
    let hidden_px = hidden_rows.saturating_mul(cell_height_px);
    let visible_window_top_px = hidden_px;
    let visible_window_bottom_px =
        hidden_px.saturating_add(visible_height_cells.saturating_mul(cell_height_px));
    let image_top_px = y_offset_px;
    let image_bottom_px = y_offset_px.saturating_add(geometry.visible_height_px);
    let visible_image_top_px = image_top_px.max(visible_window_top_px);
    let visible_image_bottom_px = image_bottom_px.min(visible_window_bottom_px);
    if visible_image_bottom_px <= visible_image_top_px {
        return None;
    }
    let image_hidden_px = visible_image_top_px.saturating_sub(image_top_px);
    let source_y_offset_px = geometry
        .source_y_offset_px
        .saturating_add(image_hidden_px)
        .min(height_px.saturating_sub(1));
    let visible_height_px = visible_image_bottom_px.saturating_sub(visible_image_top_px);
    let effective_y_offset_px = visible_image_top_px.saturating_sub(hidden_px);
    let placement_id = graphic_placement_id(graphic);
    Some(TerminalGraphicPlacement {
        render_id: placement_id,
        placement_id,
        asset_id: graphic_asset_id(graphic),
        asset_version: graphic_asset_version(graphic),
        protocol: graphic.protocol.as_str().to_string(),
        row,
        col: graphic.position.0,
        width_px,
        height_px,
        width_cells: width_cells.max(1),
        height_cells: height_cells.max(1),
        source_x_offset_px,
        visible_width_px,
        source_y_offset_px,
        visible_height_px,
        z_index: graphic.placement.z_index,
        x_offset_px: graphic.placement.x_offset,
        y_offset_px: effective_y_offset_px.min(u32::MAX as usize) as u32,
        preserve_aspect_ratio: graphic.placement.preserve_aspect_ratio,
    })
}

struct GraphicDisplayGeometry {
    width_px: usize,
    height_px: usize,
    width_cells: usize,
    height_cells: usize,
    source_x_offset_px: usize,
    visible_width_px: usize,
    source_y_offset_px: usize,
    visible_height_px: usize,
}

fn graphic_placement_id(graphic: &TerminalGraphic) -> u64 {
    graphic.id
}

fn graphic_asset_id(graphic: &TerminalGraphic) -> u64 {
    graphic
        .kitty_image_id
        .or(graphic.animation_id)
        .map(u64::from)
        .unwrap_or(graphic.id)
}

fn graphic_asset_version(graphic: &TerminalGraphic) -> u64 {
    graphic.asset_version
}

fn graphic_asset_snapshots(terminal: &Terminal) -> Vec<GraphicAssetSnapshot> {
    terminal
        .all_graphics()
        .iter()
        .chain(terminal.pending_cleared_kitty_graphics().iter())
        .chain(terminal.all_scrollback_graphics().iter())
        .chain(terminal.graphics_store().all_virtual_placements().values())
        .filter(|graphic| !graphic.pixels.is_empty())
        .map(|graphic| GraphicAssetSnapshot {
            asset_id: graphic_asset_id(graphic),
            asset_version: graphic_asset_version(graphic),
            width: graphic.width,
            height: graphic.height,
            pixels: Arc::clone(&graphic.pixels),
        })
        .collect()
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

fn graphic_display_geometry(
    graphic: &TerminalGraphic,
    viewport_cols: usize,
    viewport_rows: usize,
) -> Option<GraphicDisplayGeometry> {
    let (cell_width_px, cell_height_px) = graphic_cell_dimensions_px(graphic);
    let terminal_width_px = viewport_cols
        .saturating_mul(cell_width_px)
        .max(cell_width_px);
    let terminal_height_px = viewport_rows
        .saturating_mul(cell_height_px)
        .max(cell_height_px);
    let (source_x, source_y, source_width, source_height) = graphic.source_rect_pixels()?;

    let requested_width = graphic_dimension_px(
        graphic.placement.requested_width,
        source_width,
        cell_width_px,
        terminal_width_px,
    );
    let requested_height = graphic_dimension_px(
        graphic.placement.requested_height,
        source_height,
        cell_height_px,
        terminal_height_px,
    );

    let (visible_width_px, visible_height_px) = match (requested_width, requested_height) {
        (Some(width), Some(height)) => (width, height),
        (Some(width), None) if graphic.placement.preserve_aspect_ratio && source_width > 0 => {
            let height = ((width as f64 * source_height as f64) / source_width as f64)
                .round()
                .max(1.0) as usize;
            (width, height)
        }
        (None, Some(height)) if graphic.placement.preserve_aspect_ratio && source_height > 0 => {
            let width = ((height as f64 * source_width as f64) / source_height as f64)
                .round()
                .max(1.0) as usize;
            (width, height)
        }
        (Some(width), None) => (width, source_height.max(1)),
        (None, Some(height)) => (source_width.max(1), height),
        _ => (source_width.max(1), source_height.max(1)),
    };

    let scale_x = visible_width_px as f64 / source_width as f64;
    let scale_y = visible_height_px as f64 / source_height as f64;
    let width_px = ((graphic.width as f64) * scale_x).round().max(1.0) as usize;
    let height_px = ((graphic.height as f64) * scale_y).round().max(1.0) as usize;
    let source_x_offset_px = ((source_x as f64) * scale_x).round() as usize;
    let source_y_offset_px = ((source_y as f64) * scale_y).round() as usize;
    let source_x_offset_px = source_x_offset_px.min(width_px.saturating_sub(1));
    let source_y_offset_px = source_y_offset_px.min(height_px.saturating_sub(1));
    let visible_width_px = visible_width_px
        .min(width_px.saturating_sub(source_x_offset_px))
        .max(1);
    let visible_height_px = visible_height_px
        .min(height_px.saturating_sub(source_y_offset_px))
        .max(1);
    let x_offset_px = graphic.placement.x_offset as usize;
    let y_offset_px = graphic.placement.y_offset as usize;
    let width_cells = x_offset_px
        .saturating_add(visible_width_px)
        .div_ceil(cell_width_px)
        .max(1);
    let height_cells = y_offset_px
        .saturating_add(visible_height_px)
        .div_ceil(cell_height_px)
        .max(1);
    Some(GraphicDisplayGeometry {
        width_px,
        height_px,
        width_cells,
        height_cells,
        source_x_offset_px,
        visible_width_px,
        source_y_offset_px,
        visible_height_px,
    })
}

fn graphic_cell_dimensions_px(graphic: &TerminalGraphic) -> (usize, usize) {
    let (cell_width_px, cell_height_px) = graphic.cell_dimensions.unwrap_or((1, 1));
    (
        (cell_width_px as usize).max(1),
        (cell_height_px as usize).max(1),
    )
}

fn graphic_dimension_px(
    dimension: ImageDimension,
    fallback_px: usize,
    cell_px: usize,
    terminal_px: usize,
) -> Option<usize> {
    if dimension.is_auto() {
        return None;
    }
    let value = dimension.value.max(0.0);
    let px = match dimension.unit {
        ImageSizeUnit::Auto => fallback_px,
        ImageSizeUnit::Cells => (value * cell_px as f64).round() as usize,
        ImageSizeUnit::Pixels => value.round() as usize,
        ImageSizeUnit::Percent => ((value / 100.0) * terminal_px as f64).round() as usize,
    };
    Some(px.max(1))
}

fn delta_candidate_row_indexes(
    pending_frame_work: &PendingFrameWork,
    viewport_rows: usize,
    viewport_start_row: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
    viewport_row_shift: i32,
) -> Vec<usize> {
    let mut candidates = BTreeSet::new();
    let uses_viewport_shift =
        pending_frame_work
            .scroll_region
            .as_ref()
            .is_some_and(|scroll_region| {
                viewport_row_shift != 0
                    && scroll_region_covers_full_active_screen(scroll_region, viewport_rows)
            });

    add_shift_exposed_rows(&mut candidates, viewport_rows, viewport_row_shift);
    for row in &pending_frame_work.dirty_rows {
        if uses_viewport_shift
            && !row_is_exposed_by_viewport_shift(*row, viewport_rows, viewport_row_shift)
        {
            continue;
        }
        if let Some(visible_row) = visible_row_for_screen_row(
            *row,
            viewport_start_row,
            viewport_rows,
            scrollback_len,
            alt_screen_active,
        ) {
            candidates.insert(visible_row);
        }
        if uses_viewport_shift {
            let shifted_row = *row as isize + viewport_row_shift as isize;
            let Some(shifted_row) = usize::try_from(shifted_row).ok() else {
                continue;
            };
            if let Some(visible_row) = visible_row_for_screen_row(
                shifted_row,
                viewport_start_row,
                viewport_rows,
                scrollback_len,
                alt_screen_active,
            ) {
                candidates.insert(visible_row);
            }
        }
    }

    if let Some(scroll_region) = pending_frame_work.scroll_region.as_ref()
        && !uses_viewport_shift
    {
        add_visible_rows_for_scroll_region(
            &mut candidates,
            scroll_region,
            viewport_start_row,
            viewport_rows,
            scrollback_len,
            alt_screen_active,
        );
    }

    add_visible_cursor_row(
        &mut candidates,
        pending_frame_work.cursor_before.as_ref(),
        viewport_start_row,
        viewport_rows,
        scrollback_len,
        alt_screen_active,
    );
    add_visible_cursor_row(
        &mut candidates,
        pending_frame_work.cursor_after.as_ref(),
        viewport_start_row,
        viewport_rows,
        scrollback_len,
        alt_screen_active,
    );

    candidates.into_iter().collect()
}

fn row_is_exposed_by_viewport_shift(
    row: usize,
    viewport_rows: usize,
    viewport_row_shift: i32,
) -> bool {
    if viewport_row_shift == 0 || viewport_rows == 0 {
        return false;
    }

    let shift = viewport_row_shift.unsigned_abs() as usize;
    if viewport_row_shift < 0 {
        return row >= viewport_rows.saturating_sub(shift);
    }

    row < shift.min(viewport_rows)
}

fn add_shift_exposed_rows(
    candidates: &mut BTreeSet<usize>,
    viewport_rows: usize,
    viewport_row_shift: i32,
) {
    if viewport_row_shift == 0 || viewport_rows == 0 {
        return;
    }

    let shift = viewport_row_shift.unsigned_abs() as usize;
    if viewport_row_shift < 0 {
        let start = viewport_rows.saturating_sub(shift);
        for row in start..viewport_rows {
            candidates.insert(row);
        }
        return;
    }

    for row in 0..shift.min(viewport_rows) {
        candidates.insert(row);
    }
}

fn add_visible_rows_for_scroll_region(
    candidates: &mut BTreeSet<usize>,
    scroll_region: &PendingScrollRegion,
    viewport_start_row: usize,
    viewport_rows: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
) {
    if viewport_rows == 0 || scroll_region.top >= scroll_region.bottom_exclusive {
        return;
    }

    if alt_screen_active {
        let start = scroll_region.top.min(viewport_rows);
        let end = scroll_region.bottom_exclusive.min(viewport_rows);
        for row in start..end {
            candidates.insert(row);
        }
        return;
    }

    let region_start = scrollback_len.saturating_add(scroll_region.top);
    let region_end = scrollback_len.saturating_add(scroll_region.bottom_exclusive);
    let viewport_end = viewport_start_row.saturating_add(viewport_rows);
    let visible_start = region_start.max(viewport_start_row);
    let visible_end = region_end.min(viewport_end);
    for absolute_row in visible_start..visible_end {
        candidates.insert(absolute_row.saturating_sub(viewport_start_row));
    }
}

fn add_visible_cursor_row(
    candidates: &mut BTreeSet<usize>,
    cursor: Option<&TerminalCursor>,
    viewport_start_row: usize,
    viewport_rows: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
) {
    let Some(cursor) = cursor else {
        return;
    };

    if let Some(visible_row) = visible_row_for_screen_row(
        cursor.row,
        viewport_start_row,
        viewport_rows,
        scrollback_len,
        alt_screen_active,
    ) {
        candidates.insert(visible_row);
    }
}

fn visible_row_for_screen_row(
    screen_row: usize,
    viewport_start_row: usize,
    viewport_rows: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
) -> Option<usize> {
    if alt_screen_active {
        return (screen_row < viewport_rows).then_some(screen_row);
    }

    let absolute_row = scrollback_len.saturating_add(screen_row);
    let viewport_end = viewport_start_row.saturating_add(viewport_rows);
    if absolute_row < viewport_start_row || absolute_row >= viewport_end {
        return None;
    }
    Some(absolute_row.saturating_sub(viewport_start_row))
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

fn scroll_region_covers_full_active_screen(
    scroll_region: &PendingScrollRegion,
    viewport_rows: usize,
) -> bool {
    scroll_region.top == 0 && scroll_region.bottom_exclusive >= viewport_rows
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
        state.terminal.grid().scrollback_len()
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

fn viewport_row_shift_for(
    previous_frame_meta: Option<&CachedFrameMeta>,
    viewport_start_row: usize,
    frame_meta: &CachedFrameMeta,
) -> i32 {
    let Some(previous_frame_meta) = previous_frame_meta else {
        return 0;
    };
    if !frame_meta_is_delta_compatible(Some(previous_frame_meta), frame_meta) {
        return 0;
    }
    let row_shift = previous_frame_meta.viewport_start_row as i64 - viewport_start_row as i64;
    row_shift.clamp(i32::MIN as i64, i32::MAX as i64) as i32
}

fn resolve_viewport_row_shift(
    previous_frame_meta: Option<&CachedFrameMeta>,
    viewport_start_row: usize,
    frame_meta: &CachedFrameMeta,
    scroll_region: Option<&PendingScrollRegion>,
) -> i32 {
    let frame_meta_shift =
        viewport_row_shift_for(previous_frame_meta, viewport_start_row, frame_meta);
    if frame_meta_shift != 0 {
        return frame_meta_shift;
    }

    let Some(scroll_region) = scroll_region else {
        return 0;
    };
    if !scroll_region_covers_full_active_screen(scroll_region, frame_meta.viewport_rows) {
        return 0;
    }
    scroll_region.delta_rows.clamp(
        -(frame_meta.viewport_rows as i32),
        frame_meta.viewport_rows as i32,
    )
}

fn snapshot_fallback_reason(
    pending_frame_work: &PendingFrameWork,
    previous_rows: &[CachedRowState],
    previous_frame_meta: Option<&CachedFrameMeta>,
    frame_meta: &CachedFrameMeta,
) -> Option<String> {
    if pending_frame_work.full_repaint {
        return Some(
            pending_frame_work
                .snapshot_fallback_reason
                .clone()
                .unwrap_or_else(|| "pending_full_repaint".to_string()),
        );
    }
    if previous_rows.is_empty() {
        return Some("no_previous_frame".to_string());
    }
    if previous_rows.len() != frame_meta.viewport_rows {
        return Some("viewport_row_count_changed".to_string());
    }
    frame_meta_delta_break_reason(previous_frame_meta, frame_meta).map(str::to_string)
}

fn frame_meta_delta_break_reason(
    previous_frame_meta: Option<&CachedFrameMeta>,
    frame_meta: &CachedFrameMeta,
) -> Option<&'static str> {
    let previous_frame_meta = previous_frame_meta?;
    if previous_frame_meta.viewport_rows != frame_meta.viewport_rows
        || previous_frame_meta.viewport_cols != frame_meta.viewport_cols
    {
        return Some("viewport_metrics_changed");
    }
    if previous_frame_meta.scrollback_offset != frame_meta.scrollback_offset {
        return Some("scrollback_offset_changed");
    }
    if previous_frame_meta.alt_screen_active != frame_meta.alt_screen_active {
        return Some("alternate_screen_changed");
    }
    if previous_frame_meta.default_foreground_rgb != frame_meta.default_foreground_rgb
        || previous_frame_meta.default_background_rgb != frame_meta.default_background_rgb
    {
        return Some("terminal_default_colors_changed");
    }
    if previous_frame_meta.cursor_color_rgb != frame_meta.cursor_color_rgb {
        return Some("terminal_cursor_color_changed");
    }
    if previous_frame_meta.selection_background_rgb != frame_meta.selection_background_rgb
        || previous_frame_meta.selection_foreground_rgb != frame_meta.selection_foreground_rgb
    {
        return Some("terminal_selection_colors_changed");
    }
    if previous_frame_meta.link_color_rgb != frame_meta.link_color_rgb
        || previous_frame_meta.cursor_text_color_rgb != frame_meta.cursor_text_color_rgb
        || previous_frame_meta.tab_color_rgb != frame_meta.tab_color_rgb
    {
        return Some("terminal_iterm_colors_changed");
    }
    if previous_frame_meta.pointer_shape != frame_meta.pointer_shape {
        return Some("terminal_pointer_shape_changed");
    }
    if previous_frame_meta.ansi_palette != frame_meta.ansi_palette {
        return Some("terminal_palette_changed");
    }
    if previous_frame_meta.modes != frame_meta.modes {
        return Some("terminal_modes_changed");
    }
    if previous_frame_meta.window_title != frame_meta.window_title {
        return Some("window_title_changed");
    }
    if previous_frame_meta.window_icon_name != frame_meta.window_icon_name {
        return Some("window_icon_name_changed");
    }
    None
}

fn frame_meta_is_delta_compatible(
    previous_frame_meta: Option<&CachedFrameMeta>,
    frame_meta: &CachedFrameMeta,
) -> bool {
    frame_meta_delta_break_reason(previous_frame_meta, frame_meta).is_none()
}

fn merge_dirty_ranges(dirty_row_indexes: &[usize]) -> Vec<TerminalDirtyRange> {
    let mut ranges = Vec::new();
    let Some((&first, rest)) = dirty_row_indexes.split_first() else {
        return ranges;
    };
    let mut start = first;
    let mut end = first + 1;
    for index in rest {
        if *index == end {
            end += 1;
            continue;
        }
        ranges.push(TerminalDirtyRange { start, end });
        start = *index;
        end = *index + 1;
    }
    ranges.push(TerminalDirtyRange { start, end });
    ranges
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
    osc633_expected_nonce: Option<&str>,
    drag_drop_enabled: bool,
) {
    if let Some(limits) = graphics_memory_limits {
        terminal.set_graphics_memory_limits(limits.max_image_bytes, limits.max_total_bytes);
    }
    apply_profile_colors(terminal, profile_colors);
    configure_terminal_protocol_policy(terminal, emulation);
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
        _ => Ok(None),
    }
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

pub fn take_frame_debug_stats_json(session_id: u64) -> Result<Option<String>, SessionError> {
    STORE.get(session_id)?.take_frame_debug_stats_json()
}

pub fn take_session_debug_stats_json(session_id: u64) -> Result<Option<String>, SessionError> {
    STORE.get(session_id)?.take_session_debug_stats_json()
}

pub fn poll_events(session_id: u64) -> Result<String, SessionError> {
    let events = take_events(session_id)?;
    serde_json::to_string(&events).map_err(|error| SessionError::Serialize(error.to_string()))
}

pub fn take_events(session_id: u64) -> Result<Vec<TerminalEvent>, SessionError> {
    STORE.get(session_id)?.poll_events()
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

    fn pending_test_event(kind: &str, payload: Option<serde_json::Value>) -> TerminalEvent {
        TerminalEvent {
            kind: kind.to_string(),
            session_id: 42,
            payload,
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
            terminal: TerminalProfileTerminal::default(),
            shell_integration: TerminalShellIntegration { enabled: false },
            appearance: TerminalProfileAppearance::default(),
            interaction: TerminalProfileInteraction::default(),
        }
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
        assert_eq!(state.window_icon_name.as_deref(), Some("build icon"));
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
    fn host_protocol_ris_clears_native_icon_and_keypad_state() {
        let mut state = HostProtocolState::default();
        state.observe(b"\x1b]1;build icon\x07\x1b=", TerminalEmulation::Xterm256);
        assert_eq!(state.window_icon_name.as_deref(), Some("build icon"));
        assert!(state.application_keypad);

        let events = state.observe(b"\x1bc", TerminalEmulation::Xterm256);

        assert!(events.is_empty(), "the parser emits the typed reset event");
        assert!(state.window_icon_name.is_none());
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
        assert!(denied_host.window_icon_name.is_none());

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
        assert!(oversized_host.window_icon_name.is_none());
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
        });

        let sanitized = sanitize_diagnostic_event_payload("session_notification", Some(&payload))
            .expect("expected sanitized notification event");

        assert_eq!(sanitized["source"].as_str(), Some("osc99"));
        assert_eq!(sanitized["action"].as_str(), Some("update"));
        assert_eq!(sanitized["type_count"].as_u64(), Some(2));
        assert_eq!(sanitized["expires_after_ms"].as_u64(), Some(250));
        assert!(sanitized["id_hash"].as_str().is_some());
        assert!(sanitized["title_hash"].as_str().is_some());
        assert!(sanitized["message_hash"].as_str().is_some());
        assert!(sanitized["application_hash"].as_str().is_some());
        let serialized = sanitized.to_string();
        for secret in [identifier, title, message, application, "deploy", "private"] {
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
