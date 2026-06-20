use crate::model::{
    TerminalCursor, TerminalDirtyRange, TerminalEmulation, TerminalEvent, TerminalFrameDiff,
    TerminalFrameKind, TerminalFrameModes, TerminalHyperlinkRange, TerminalProfile,
    TerminalProfileAnsiColors, TerminalProfileColors, TerminalRow, TerminalSearchMatch,
    TerminalSelectionRequest, TerminalStyleRun,
};
use crate::pty::spawn_pty;
use par_term_emu_core_rust::cell::{Cell, CellFlags};
use par_term_emu_core_rust::color::{Color, NamedColor};
use par_term_emu_core_rust::grid::{Grid, ScrollRegionDamage};
use par_term_emu_core_rust::mouse::{MouseEncoding, MouseMode};
use par_term_emu_core_rust::terminal::{
    Terminal, TerminalDamage, TerminalProcessDebugStats, snapshot::ExportFormat,
};
use parking_lot::Mutex;
use regex::RegexBuilder;
use std::collections::{BTreeSet, HashMap, VecDeque};
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
const RESOURCE_SAMPLE_INTERVAL: Duration = Duration::from_secs(1);
const RESOURCE_SAMPLER_MAX_FAILURES: u64 = 5;
const ASCIINEMA_VERSION: u8 = 2;
const VT220_PRIMARY_DA_RESPONSE: &str = "\x1b[?62;1;2;6;7;8;9c";
const VT220_SECONDARY_DA_RESPONSE: &str = "\x1b[>1;10;0c";
static TRACE_TERMINAL_IO: LazyLock<bool> = LazyLock::new(|| {
    std::env::var("IANVS_TRACE_TERMINAL_IO")
        .map(|value| value == "1" || value.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
});

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
            Some("smart_case_substring") | _ => Self::SmartCaseSubstring,
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

#[derive(Clone, Debug)]
enum CallbackEvent {
    Resize { rows: u16, cols: u16 },
    ClipboardCopy { selection: String, data: String },
    ClipboardPasteRequest { selection: String },
    ShellHook { payload: serde_json::Value },
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

#[derive(Clone, Debug, serde::Serialize)]
struct FrameDebugStats {
    rows_scanned: usize,
    rows_emitted: usize,
    frame_build_micros: u64,
    state_lock_wait_micros: u64,
    frame_extract_micros: u64,
    json_encode_micros: u64,
    full_repaint: bool,
    snapshot_fallback_reason: Option<String>,
    viewport_row_shift: i32,
    damage_generation: u64,
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
    pending_dirty_rows: usize,
    pending_scroll_region: Option<SessionDebugScrollRegion>,
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
}

struct TerminalState {
    terminal: Terminal,
    transcript: Vec<u8>,
    transcript_truncated: bool,
    scrollback_offset: usize,
    host_protocol: HostProtocolState,
    output_recording_started_at: Instant,
    output_recording_events: VecDeque<AsciinemaOutputEvent>,
    output_recording_bytes: usize,
    output_recording_truncated: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct AsciinemaOutputEvent {
    elapsed_micros: u64,
    bytes: Vec<u8>,
}

#[derive(Clone, Debug, serde::Serialize)]
struct AsciinemaReplayValidation {
    matched: bool,
    viewport_rows: usize,
    compared_rows: usize,
    mismatch_count: usize,
    mismatches: Vec<AsciinemaReplayMismatch>,
}

#[derive(Clone, Debug, serde::Serialize)]
struct AsciinemaReplayMismatch {
    row: usize,
    recorded: String,
    rendered: String,
}

#[derive(Clone, Default)]
struct HostProtocolState {
    buffer: Vec<u8>,
    window_icon_name: Option<String>,
    application_keypad: bool,
}

impl HostProtocolState {
    fn observe(&mut self, bytes: &[u8], emulation: TerminalEmulation) -> Vec<CallbackEvent> {
        if self.buffer.is_empty() && !bytes.contains(&0x1b) {
            return Vec::new();
        }

        self.buffer.extend_from_slice(bytes);
        let mut events = Vec::new();
        let mut index = 0usize;

        while index < self.buffer.len() {
            if self.buffer[index] != 0x1b {
                index += 1;
                continue;
            }

            if index + 1 >= self.buffer.len() {
                break;
            }

            match self.buffer[index + 1] {
                b'=' => {
                    self.application_keypad = true;
                    index += 2;
                }
                b'>' => {
                    self.application_keypad = false;
                    index += 2;
                }
                b']' => match self.consume_osc(index, emulation, &mut events) {
                    Some(next) => index = next,
                    None => break,
                },
                b'P' => match self.consume_dcs(index, emulation, &mut events) {
                    Some(next) => index = next,
                    None => break,
                },
                b'[' => match self.consume_csi(index, emulation, &mut events) {
                    Some(next) => index = next,
                    None => break,
                },
                _ => {
                    index += 2;
                }
            }
        }

        if index > 0 {
            self.buffer.drain(..index);
        } else if self.buffer.len() > 4096 {
            let keep = 4096usize.min(self.buffer.len());
            self.buffer.drain(..self.buffer.len() - keep);
        }

        events
    }

    fn consume_osc(
        &mut self,
        start: usize,
        emulation: TerminalEmulation,
        events: &mut Vec<CallbackEvent>,
    ) -> Option<usize> {
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

        if emulation == TerminalEmulation::Xterm256 {
            let payload = self.buffer[start + 2..terminator_start].to_vec();
            self.handle_osc_payload(&payload, events);
        }

        Some(terminator_start + terminator_len)
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
                let data = String::from_utf8_lossy(args.next().unwrap_or_default()).into_owned();
                let selection = if selection.is_empty() {
                    "c".to_string()
                } else {
                    selection
                };

                if data == "?" {
                    events.push(CallbackEvent::ClipboardPasteRequest { selection });
                } else if !data.is_empty() {
                    events.push(CallbackEvent::ClipboardCopy { selection, data });
                }
            }
            _ => {}
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

pub struct TerminalSession {
    session_id: u64,
    emulation: TerminalEmulation,
    scrollback_lines: usize,
    profile_colors: TerminalProfileColors,
    state: Mutex<TerminalState>,
    writer: Mutex<Box<dyn Write + Send>>,
    master: Mutex<Box<dyn portable_pty::MasterPty + Send>>,
    child: Mutex<Box<dyn portable_pty::Child + Send + Sync>>,
    child_pid: Option<u32>,
    process_name: String,
    events: Mutex<VecDeque<TerminalEvent>>,
    diagnostic_events: Mutex<VecDeque<TerminalDiagnosticEvent>>,
    resource_samples: Mutex<VecDeque<ResourceSample>>,
    resource_sampler_state: Mutex<ResourceSamplerState>,
    dirty: AtomicBool,
    pending_frame_work: Mutex<PendingFrameWork>,
    session_debug_stats: Mutex<SessionDebugStats>,
    last_rows: Mutex<Vec<CachedRowState>>,
    last_frame_meta: Mutex<Option<CachedFrameMeta>>,
    last_frame_debug_stats: Mutex<Option<FrameDebugStats>>,
    exited: AtomicBool,
}

impl TerminalSession {
    pub fn spawn(session_id: u64, profile: TerminalProfile) -> Result<Arc<Self>, SessionError> {
        let emulation = profile.terminal.emulation;
        let scrollback_lines = profile.terminal.scrollback_lines.max(1);
        let profile_colors = profile.appearance.colors.clone();
        let runtime = spawn_pty(&profile, DEFAULT_ROWS, DEFAULT_COLS)
            .map_err(|error: anyhow::Error| SessionError::Pty(error.to_string()))?;
        let child_pid = runtime.child_pid;
        let process_name = process_name_for_profile(&profile);
        let reader = runtime.reader;
        let shell_integration_proxy = runtime.shell_integration_proxy;

        let mut terminal = Terminal::with_scrollback(
            DEFAULT_COLS as usize,
            DEFAULT_ROWS as usize,
            scrollback_lines,
        );
        apply_profile_colors_and_reset_screen(&mut terminal, &profile_colors);
        if emulation == TerminalEmulation::Vt220 {
            terminal.process(b"\x1b[62;1\"p");
        }

        let session = Arc::new(Self {
            session_id,
            emulation,
            scrollback_lines,
            profile_colors,
            state: Mutex::new(TerminalState {
                terminal,
                transcript: Vec::new(),
                transcript_truncated: false,
                scrollback_offset: 0,
                host_protocol: HostProtocolState::default(),
                output_recording_started_at: Instant::now(),
                output_recording_events: VecDeque::new(),
                output_recording_bytes: 0,
                output_recording_truncated: false,
            }),
            writer: Mutex::new(runtime.writer),
            master: Mutex::new(runtime.master),
            child: Mutex::new(runtime.child),
            child_pid,
            process_name,
            events: Mutex::new(VecDeque::from([TerminalEvent {
                kind: "started".to_string(),
                session_id,
                payload: None,
            }])),
            diagnostic_events: Mutex::new(VecDeque::from([TerminalDiagnosticEvent {
                timestamp_micros: unix_timestamp_micros(),
                session_id,
                kind: "started".to_string(),
                payload: None,
            }])),
            resource_samples: Mutex::new(VecDeque::new()),
            resource_sampler_state: Mutex::new(ResourceSamplerState::default()),
            dirty: AtomicBool::new(true),
            pending_frame_work: Mutex::new(PendingFrameWork::default()),
            session_debug_stats: Mutex::new(SessionDebugStats::default()),
            last_rows: Mutex::new(Vec::new()),
            last_frame_meta: Mutex::new(None),
            last_frame_debug_stats: Mutex::new(None),
            exited: AtomicBool::new(false),
        });

        let reader_session = Arc::clone(&session);
        thread::spawn(move || {
            let _shell_integration_proxy = shell_integration_proxy;
            let mut reader = reader;
            let mut buf = [0_u8; 4096];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) => break,
                    Ok(read) => {
                        let (
                            callback_events,
                            damage,
                            cursor_before,
                            cursor_after,
                            host_protocol_micros,
                            terminal_process_micros,
                            terminal_process_breakdown,
                            response_write_micros,
                        ) = {
                            let mut state = reader_session.state.lock();
                            let cursor_before = terminal_cursor_snapshot(state.terminal.cursor());
                            let mut response_write_micros = 0_u64;
                            let mut callback_events = Vec::new();
                            let TerminalState {
                                terminal,
                                host_protocol,
                                ..
                            } = &mut *state;
                            let process_stats =
                                process_terminal_output_with_immediate_responses_and_host_events(
                                    terminal,
                                    host_protocol,
                                    reader_session.emulation,
                                    &buf[..read],
                                    &mut |_, _, responses| {
                                        response_write_micros = response_write_micros
                                            .saturating_add(
                                                reader_session
                                                    .write_terminal_response_bytes(&responses),
                                            );
                                    },
                                    &mut |_, event| callback_events.push(event),
                                );
                            let terminal_process_breakdown =
                                state.terminal.take_process_debug_stats();
                            append_terminal_output_recording(&mut state, &buf[..read]);
                            let damage = state.terminal.drain_active_screen_damage();
                            let cursor_after = terminal_cursor_snapshot(state.terminal.cursor());
                            (
                                callback_events,
                                damage,
                                cursor_before,
                                cursor_after,
                                process_stats.host_protocol_micros,
                                process_stats.terminal_process_micros,
                                terminal_process_breakdown,
                                response_write_micros,
                            )
                        };

                        let damage_merge_started_at = Instant::now();
                        reader_session
                            .pending_frame_work
                            .lock()
                            .merge_terminal_damage(damage, cursor_before, cursor_after);
                        let damage_merge_micros =
                            damage_merge_started_at.elapsed().as_micros() as u64;

                        for event in callback_events {
                            reader_session.push_callback_event(event);
                        }
                        reader_session.record_input_debug_stats(
                            read,
                            host_protocol_micros,
                            terminal_process_micros,
                            terminal_process_breakdown,
                            damage_merge_micros,
                            response_write_micros,
                        );

                        reader_session.dirty.store(true, Ordering::SeqCst);
                    }
                    Err(_) => break,
                }
            }
        });
        Self::start_resource_sampler(&session);

        Ok(session)
    }

    pub fn ping(&self) -> i32 {
        42
    }

    pub fn close(&self) -> Result<(), SessionError> {
        self.exited.store(true, Ordering::SeqCst);
        let _ = self.child.lock().kill();
        Ok(())
    }

    fn start_resource_sampler(session: &Arc<Self>) {
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
                thread::sleep(RESOURCE_SAMPLE_INTERVAL);
            }
        });
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
        let mut state = self.state.lock();
        let (current_cols, current_rows) = state.terminal.size();
        let size_changed = current_cols != cols as usize || current_rows != rows as usize;

        if !size_changed {
            if pixel_width > 0 && pixel_height > 0 {
                state
                    .terminal
                    .set_pixel_size(pixel_width as usize, pixel_height as usize);
            }
            return Ok(());
        }

        let previous_max = current_scrollback_max(&state);
        trace_terminal_io_event(&format!(
            "resize cols={cols} rows={rows} alt={}",
            state.terminal.is_alt_screen_active()
        ));

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
            apply_profile_colors_and_reset_screen(&mut terminal, &self.profile_colors);
            if self.emulation == TerminalEmulation::Vt220 {
                terminal.process(b"\x1b[62;1\"p");
            }
            if pixel_width > 0 && pixel_height > 0 {
                terminal.set_pixel_size(pixel_width as usize, pixel_height as usize);
            }
            replay_transcript_without_terminal_responses(&mut terminal, &transcript);
            state.terminal = terminal;
        } else {
            state.terminal.resize(cols as usize, rows as usize);
            if pixel_width > 0 && pixel_height > 0 {
                state
                    .terminal
                    .set_pixel_size(pixel_width as usize, pixel_height as usize);
            }
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
        self.pending_frame_work.lock().mark_full_repaint("resize");
        self.dirty.store(true, Ordering::SeqCst);
        Ok(())
    }

    pub fn write(&self, bytes: &[u8]) -> Result<(), SessionError> {
        trace_terminal_io_bytes("write", bytes);
        let mut writer = self.writer.lock();
        writer
            .write_all(bytes)
            .and_then(|_| writer.flush())
            .map_err(|error| SessionError::Io(error.to_string()))
    }

    fn write_terminal_response_bytes(&self, bytes: &[u8]) -> u64 {
        if bytes.is_empty() {
            return 0;
        }
        let started_at = Instant::now();
        trace_terminal_io_bytes("response-write", bytes);
        let mut writer = self.writer.lock();
        let _ = writer.write_all(bytes);
        let _ = writer.flush();
        started_at.elapsed().as_micros() as u64
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
        self.pending_frame_work
            .lock()
            .mark_full_repaint("scrollback_navigation");
        self.dirty.store(true, Ordering::SeqCst);
    }

    pub fn scroll_to(&self, offset: usize) {
        let mut state = self.state.lock();
        if state.terminal.is_alt_screen_active() {
            state.scrollback_offset = 0;
        } else {
            state.scrollback_offset = offset.min(current_scrollback_max(&state));
        }
        self.pending_frame_work
            .lock()
            .mark_full_repaint("scrollback_navigation");
        self.dirty.store(true, Ordering::SeqCst);
    }

    pub fn clear_scrollback(&self) -> Result<bool, SessionError> {
        let mut state = self.state.lock();
        state.terminal.process(b"\x1b[3J");
        state.scrollback_offset = 0;
        state.transcript.clear();
        state.transcript_truncated = true;
        state.output_recording_events.clear();
        state.output_recording_bytes = 0;
        state.output_recording_truncated = true;
        state.output_recording_started_at = Instant::now();
        drop(state);

        self.last_rows.lock().clear();
        *self.last_frame_meta.lock() = None;
        self.pending_frame_work
            .lock()
            .mark_full_repaint("clear_scrollback");
        self.dirty.store(true, Ordering::SeqCst);
        Ok(true)
    }

    pub fn export_scrollback_text(&self, max_lines: Option<usize>) -> String {
        let state = self.state.lock();
        state
            .terminal
            .export_scrollback(ExportFormat::Plain, max_lines)
    }

    pub fn export_asciinema_recording_json(&self) -> Result<String, SessionError> {
        let state = self.state.lock();
        let (cols, rows) = state.terminal.size();
        let cast = asciinema_cast_for_state(&state, self.emulation, self.scrollback_lines);
        let validation = asciinema_replay_validation_for_state(
            &state,
            self.emulation,
            self.scrollback_lines,
            &self.profile_colors,
        );
        serde_json::to_string(&serde_json::json!({
            "content": cast,
            "scope": "terminal-output-asciinema",
            "format": "asciinema-v2",
            "version": ASCIINEMA_VERSION,
            "width": cols,
            "height": rows,
            "event_count": state.output_recording_events.len(),
            "byte_count": state.output_recording_bytes,
            "truncated": state.output_recording_truncated,
            "validation": validation,
        }))
        .map_err(|error| SessionError::Serialize(error.to_string()))
    }

    pub fn take_frame_diff(&self) -> Result<Option<TerminalFrameDiff>, SessionError> {
        if !self.dirty.swap(false, Ordering::SeqCst) {
            return Ok(None);
        }

        let frame_started_at = Instant::now();

        let state_lock_started_at = Instant::now();
        let mut state = self.state.lock();
        let state_lock_wait_micros = state_lock_started_at.elapsed().as_micros() as u64;
        let frame_extract_started_at = Instant::now();
        let alt_screen_active = state.terminal.is_alt_screen_active();
        let scrollback_max_offset = current_scrollback_max(&state);
        if alt_screen_active {
            state.scrollback_offset = 0;
        } else {
            state.scrollback_offset = state.scrollback_offset.min(scrollback_max_offset);
        }
        let terminal = &state.terminal;
        let (viewport_cols, viewport_rows) = terminal.size();

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
        let cursor_snapshot = terminal_cursor_snapshot(cursor);
        let pending_frame_work = {
            let mut pending_frame_work = self.pending_frame_work.lock();
            std::mem::take(&mut *pending_frame_work)
        };
        let mut last_rows = self.last_rows.lock();
        let mut last_frame_meta = self.last_frame_meta.lock();
        let frame_meta = CachedFrameMeta {
            viewport_rows,
            viewport_cols,
            scrollback_offset: state.scrollback_offset,
            viewport_start_row,
            alt_screen_active,
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
                build_delta_frame(
                    terminal,
                    self.emulation,
                    viewport_start_row,
                    viewport_rows,
                    scrollback_len,
                    alt_screen_active,
                    &pending_frame_work,
                    &last_rows,
                    viewport_row_shift,
                )
            };
        *last_rows = current_rows;
        *last_frame_meta = Some(frame_meta);
        *self.last_frame_debug_stats.lock() = Some(FrameDebugStats {
            rows_scanned,
            rows_emitted,
            frame_build_micros: frame_started_at.elapsed().as_micros() as u64,
            state_lock_wait_micros,
            frame_extract_micros: frame_extract_started_at.elapsed().as_micros() as u64,
            json_encode_micros: 0,
            full_repaint: frame_kind == TerminalFrameKind::Snapshot,
            snapshot_fallback_reason,
            viewport_row_shift,
            damage_generation: pending_frame_work.damage_generation,
        });

        Ok(Some(TerminalFrameDiff {
            frame_kind,
            rows,
            cursor: cursor_snapshot,
            selection: None,
            viewport_rows: viewport_rows as u16,
            viewport_cols: viewport_cols as u16,
            dirty_ranges,
            scrollback_offset: state.scrollback_offset,
            scrollback_max_offset,
            viewport_start_row,
            viewport_row_shift,
            modes,
            window_title,
            window_icon_name,
            hyperlinks,
        }))
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
                    true,
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
                        false,
                    )
                } else {
                    let screen_row = visible_index.saturating_sub(scrollback_len);
                    extract_row(
                        grid.row(screen_row),
                        grid.is_line_wrapped(screen_row),
                        &theme,
                        screen_row == terminal.cursor().row,
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

        Ok(self.events.lock().drain(..).collect())
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
        }
        {
            let pending = self.pending_frame_work.lock();
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
        let events = tail_vec(&self.diagnostic_events.lock(), 256);
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
            CallbackEvent::ShellHook { payload } => self.push_event("shell_hook", Some(payload)),
        }
    }

    fn push_event(&self, kind: &str, payload: Option<serde_json::Value>) {
        let diagnostic_payload = sanitize_diagnostic_event_payload(kind, payload.as_ref());
        self.events.lock().push_back(TerminalEvent {
            kind: kind.to_string(),
            session_id: self.session_id,
            payload,
        });
        let mut events = self.diagnostic_events.lock();
        events.push_back(TerminalDiagnosticEvent {
            timestamp_micros: unix_timestamp_micros(),
            session_id: self.session_id,
            kind: kind.to_string(),
            payload: diagnostic_payload,
        });
        while events.len() > 256 {
            events.pop_front();
        }
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

fn terminal_cursor_snapshot(cursor: &par_term_emu_core_rust::cursor::Cursor) -> TerminalCursor {
    TerminalCursor {
        row: cursor.row,
        col: cursor.col,
        visible: cursor.visible,
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

fn append_terminal_output_recording(state: &mut TerminalState, bytes: &[u8]) {
    let elapsed_micros = state
        .output_recording_started_at
        .elapsed()
        .as_micros()
        .min(u128::from(u64::MAX)) as u64;
    if !bytes.is_empty() {
        state
            .output_recording_events
            .push_back(AsciinemaOutputEvent {
                elapsed_micros,
                bytes: bytes.to_vec(),
            });
        state.output_recording_bytes = state.output_recording_bytes.saturating_add(bytes.len());
    }

    state.transcript.extend_from_slice(bytes);
    while state.output_recording_bytes > MAX_TRANSCRIPT_BYTES {
        let Some(event) = state.output_recording_events.pop_front() else {
            break;
        };
        state.output_recording_bytes = state
            .output_recording_bytes
            .saturating_sub(event.bytes.len());
        state.output_recording_truncated = true;
    }

    if state.transcript.len() > MAX_TRANSCRIPT_BYTES {
        let overflow = state.transcript.len() - MAX_TRANSCRIPT_BYTES;
        state.transcript.drain(..overflow);
        state.transcript_truncated = true;
    }
}

fn replay_transcript_without_terminal_responses(terminal: &mut Terminal, transcript: &[u8]) {
    terminal.process(transcript);
    terminal.drain_responses();
}

fn asciinema_cast_for_state(
    state: &TerminalState,
    emulation: TerminalEmulation,
    scrollback_lines: usize,
) -> String {
    let (cols, rows) = state.terminal.size();
    let header = serde_json::json!({
        "version": ASCIINEMA_VERSION,
        "width": cols,
        "height": rows,
        "timestamp": unix_timestamp_micros() / 1_000_000,
        "env": {
            "TERM": match emulation {
                TerminalEmulation::Xterm256 => "xterm-256color",
                TerminalEmulation::Vt220 => "vt220",
            },
            "IANVS_SCROLLBACK_LINES": scrollback_lines,
        },
    });
    let mut cast = serde_json::to_string(&header).unwrap_or_else(|_| "{}".to_string());
    cast.push('\n');
    for event in &state.output_recording_events {
        let timestamp = (event.elapsed_micros as f64) / 1_000_000.0;
        let output = String::from_utf8_lossy(&event.bytes);
        let line = serde_json::json!([timestamp, "o", output.as_ref()]);
        cast.push_str(&serde_json::to_string(&line).unwrap_or_else(|_| "[]".to_string()));
        cast.push('\n');
    }
    cast
}

fn asciinema_replay_validation_for_state(
    state: &TerminalState,
    emulation: TerminalEmulation,
    scrollback_lines: usize,
    profile_colors: &TerminalProfileColors,
) -> AsciinemaReplayValidation {
    let (cols, rows) = state.terminal.size();
    let mut replay = Terminal::with_scrollback(cols, rows, scrollback_lines);
    apply_profile_colors(&mut replay, profile_colors);
    if emulation == TerminalEmulation::Vt220 {
        replay.process(b"\x1b[62;1\"p");
    }
    for event in &state.output_recording_events {
        replay.process(&event.bytes);
    }

    let expected = viewport_text_lines(&replay, emulation, state.scrollback_offset);
    let rendered = viewport_text_lines(&state.terminal, emulation, state.scrollback_offset);
    let compared_rows = expected.len().max(rendered.len());
    let mut mismatches = Vec::new();
    for row in 0..compared_rows {
        let recorded = expected.get(row).cloned().unwrap_or_default();
        let rendered_row = rendered.get(row).cloned().unwrap_or_default();
        if recorded != rendered_row {
            mismatches.push(AsciinemaReplayMismatch {
                row,
                recorded,
                rendered: rendered_row,
            });
            if mismatches.len() >= 20 {
                break;
            }
        }
    }

    AsciinemaReplayValidation {
        matched: expected == rendered,
        viewport_rows: rows,
        compared_rows,
        mismatch_count: count_line_mismatches(&expected, &rendered),
        mismatches,
    }
}

fn viewport_text_lines(
    terminal: &Terminal,
    emulation: TerminalEmulation,
    scrollback_offset: usize,
) -> Vec<String> {
    let (_, viewport_rows) = terminal.size();
    let scrollback_max_offset = if terminal.is_alt_screen_active() {
        0
    } else {
        terminal.grid().scrollback_len()
    };
    let viewport_start_row = if terminal.is_alt_screen_active() {
        0
    } else {
        scrollback_max_offset.saturating_sub(scrollback_offset.min(scrollback_max_offset))
    };

    (0..viewport_rows)
        .map(|row| {
            extract_viewport_row(terminal, emulation, viewport_start_row, row)
                .row
                .text
        })
        .collect()
}

fn count_line_mismatches(left: &[String], right: &[String]) -> usize {
    let compared_rows = left.len().max(right.len());
    (0..compared_rows)
        .filter(|row| left.get(*row) != right.get(*row))
        .count()
}

fn unix_timestamp_micros() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_micros().min(u128::from(u64::MAX)) as u64)
        .unwrap_or(0)
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
            "data_bytes": payload
                .get("data")
                .and_then(serde_json::Value::as_str)
                .map(str::len),
        })),
        "clipboard_paste_request" => Some(serde_json::json!({
            "selection": payload.get("selection").and_then(serde_json::Value::as_str),
        })),
        "shell_hook" => sanitize_shell_hook_payload(payload),
        _ => None,
    }
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
    let extracted = extract_row(
        cells,
        wrapped,
        &theme,
        preserve_trailing_blank_style_for_visible_index(terminal, absolute_visible_index),
    );
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
    for row in 0..viewport_rows {
        let previous_index = row as isize - viewport_row_shift as isize;
        let Some(previous_index) = usize::try_from(previous_index).ok() else {
            continue;
        };
        if let Some(previous_row) = previous_rows.get(previous_index) {
            shifted[row] = previous_row.clone();
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

fn build_delta_frame(
    terminal: &Terminal,
    emulation: TerminalEmulation,
    viewport_start_row: usize,
    viewport_rows: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
    pending_frame_work: &PendingFrameWork,
    previous_rows: &[CachedRowState],
    viewport_row_shift: i32,
) -> (
    Vec<TerminalRow>,
    Vec<TerminalHyperlinkRange>,
    Vec<CachedRowState>,
    Vec<TerminalDirtyRange>,
    usize,
    usize,
) {
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

    if let Some(scroll_region) = pending_frame_work.scroll_region.as_ref() {
        if !uses_viewport_shift {
            add_visible_rows_for_scroll_region(
                &mut candidates,
                scroll_region,
                viewport_start_row,
                viewport_rows,
                scrollback_len,
                alt_screen_active,
            );
        }
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
    let mut active_uri: Option<String> = None;
    let mut active_start = 0usize;
    let mut column_offset = 0usize;

    for cell in cells.unwrap_or_default() {
        if cell.flags.wide_char_spacer() {
            continue;
        }

        let column_start = column_offset;
        column_offset += cell.width();
        let cell_uri = cell
            .flags
            .hyperlink_id
            .and_then(|id| terminal.get_hyperlink_url(id));

        if active_uri.as_deref() == cell_uri.as_deref() {
            continue;
        }

        if let Some(uri) = active_uri.take() {
            ranges.push(TerminalHyperlinkRange {
                row,
                start_col: active_start,
                end_col: column_start,
                uri,
            });
        }

        if let Some(uri) = cell_uri {
            active_start = column_start;
            active_uri = Some(uri);
        }
    }

    if let Some(uri) = active_uri {
        ranges.push(TerminalHyperlinkRange {
            row,
            start_col: active_start,
            end_col: column_offset,
            uri,
        });
    }

    ranges
}

#[derive(Clone, Copy)]
struct TerminalThemeSnapshot {
    default_fg: Color,
    default_bg: Color,
    ansi_palette: [Color; 16],
}

fn terminal_theme_snapshot(terminal: &Terminal) -> TerminalThemeSnapshot {
    TerminalThemeSnapshot {
        default_fg: terminal.default_fg(),
        default_bg: terminal.default_bg(),
        ansi_palette: *terminal.get_ansi_palette(),
    }
}

fn extract_row(
    cells: Option<&[Cell]>,
    wrapped: bool,
    theme: &TerminalThemeSnapshot,
    preserve_trailing_blank_style: bool,
) -> ExtractedRow {
    let mut text = String::new();
    let mut style_runs = Vec::new();
    let mut run_start = 0usize;
    let mut run_style: Option<TerminalStyleRun> = None;
    let mut column_offset = 0usize;
    let last_content_column = last_visible_content_column(cells);

    for cell in cells.unwrap_or_default() {
        if cell.flags.wide_char_spacer() {
            continue;
        }

        let grapheme = cell.get_grapheme();
        text.push_str(if grapheme.is_empty() { " " } else { &grapheme });
        let column_start = column_offset;
        column_offset += cell.width();
        let column_end = column_offset;
        let strip_trailing_blank_style = !preserve_trailing_blank_style
            && last_content_column > 0
            && column_start >= last_content_column
            && !cell_has_visible_content(&grapheme);
        let style = TerminalStyleRun {
            start: column_start,
            end: column_end,
            foreground: if strip_trailing_blank_style {
                None
            } else {
                color_to_hex_delta(cell.fg, theme.default_fg, &theme.ansi_palette)
            },
            background: if strip_trailing_blank_style {
                None
            } else {
                color_to_hex_delta(cell.bg, theme.default_bg, &theme.ansi_palette)
            },
            bold: !strip_trailing_blank_style && cell.flags.bold(),
            dim: !strip_trailing_blank_style && cell.flags.dim(),
            italic: !strip_trailing_blank_style && cell.flags.italic(),
            underline: !strip_trailing_blank_style && cell.flags.underline(),
            blink: !strip_trailing_blank_style && cell.flags.blink(),
            inverse: !strip_trailing_blank_style && cell.flags.reverse(),
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

fn last_visible_content_column(cells: Option<&[Cell]>) -> usize {
    let mut last_content_column = 0usize;
    let mut column_offset = 0usize;

    for cell in cells.unwrap_or_default() {
        if cell.flags.wide_char_spacer() {
            continue;
        }
        let grapheme = cell.get_grapheme();
        column_offset += cell.width();
        if cell_has_visible_content(&grapheme) {
            last_content_column = column_offset;
        }
    }

    last_content_column
}

fn cell_has_visible_content(grapheme: &str) -> bool {
    grapheme.chars().any(|character| !character.is_whitespace())
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
    let normalized = normalize_selection_request(request);
    let terminal = &state.terminal;
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
        text.push_str(&slice_cells_columns(cells, start_col, end_col));
        if row != end_row && !wrapped {
            text.push('\n');
        }
    }
    text
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

fn preserve_trailing_blank_style_for_visible_index(
    terminal: &Terminal,
    visible_index: usize,
) -> bool {
    if terminal.is_alt_screen_active() {
        return true;
    }
    let cursor_visible_index = terminal
        .grid()
        .scrollback_len()
        .saturating_add(terminal.cursor().row);
    visible_index == cursor_visible_index
}

fn slice_cells_columns(cells: Option<&[Cell]>, start_col: usize, end_col: usize) -> String {
    let effective_end_col = end_col.min(last_significant_column(cells));
    if start_col >= effective_end_col {
        return String::new();
    }

    let mut text = String::new();
    let mut column_offset = 0usize;
    for cell in cells.unwrap_or_default() {
        if cell.flags.wide_char_spacer() {
            continue;
        }

        let column_start = column_offset;
        column_offset += cell.width();
        if column_offset <= start_col {
            continue;
        }
        if column_start >= effective_end_col {
            break;
        }

        let grapheme = cell.get_grapheme();
        text.push_str(&grapheme);
    }
    text
}

fn last_significant_column(cells: Option<&[Cell]>) -> usize {
    let default_fg = Color::Named(NamedColor::White);
    let default_bg = Color::Named(NamedColor::Black);
    let default_flags = CellFlags::default();
    let mut last_significant = 0usize;
    let mut column_offset = 0usize;

    for cell in cells.unwrap_or_default() {
        if cell.flags.wide_char_spacer() {
            continue;
        }
        column_offset += cell.width();
        let has_content = cell.c != ' ' || !cell.combining.is_empty();
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

#[cfg(test)]
fn process_terminal_output_with_immediate_responses<F>(
    terminal: &mut Terminal,
    emulation: TerminalEmulation,
    bytes: &[u8],
    response_sink: &mut F,
) where
    F: FnMut(usize, bool, Vec<u8>),
{
    for (index, byte) in bytes.iter().enumerate() {
        terminal.process(std::slice::from_ref(byte));
        drain_terminal_responses_at(terminal, emulation, index + 1, response_sink);
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
struct TerminalOutputProcessStats {
    host_protocol_micros: u64,
    terminal_process_micros: u64,
}

fn process_terminal_output_with_immediate_responses_and_host_events<F, G>(
    terminal: &mut Terminal,
    host_protocol: &mut HostProtocolState,
    emulation: TerminalEmulation,
    bytes: &[u8],
    response_sink: &mut F,
    event_sink: &mut G,
) -> TerminalOutputProcessStats
where
    F: FnMut(usize, bool, Vec<u8>),
    G: FnMut(usize, CallbackEvent),
{
    let mut stats = TerminalOutputProcessStats::default();
    for (index, byte) in bytes.iter().enumerate() {
        let byte_slice = std::slice::from_ref(byte);
        let processed_bytes = index + 1;

        let terminal_started_at = Instant::now();
        terminal.process(byte_slice);
        drain_terminal_responses_at(terminal, emulation, processed_bytes, response_sink);
        stats.terminal_process_micros = stats
            .terminal_process_micros
            .saturating_add(terminal_started_at.elapsed().as_micros() as u64);

        let host_started_at = Instant::now();
        for event in host_protocol.observe(byte_slice, emulation) {
            event_sink(processed_bytes, event);
        }
        stats.host_protocol_micros = stats
            .host_protocol_micros
            .saturating_add(host_started_at.elapsed().as_micros() as u64);
    }
    stats
}

fn drain_terminal_responses_at<F>(
    terminal: &mut Terminal,
    emulation: TerminalEmulation,
    processed_bytes: usize,
    response_sink: &mut F,
) where
    F: FnMut(usize, bool, Vec<u8>),
{
    if !terminal.can_drain_responses() {
        return;
    }
    let responses = normalize_responses(emulation, terminal.drain_responses());
    if !responses.is_empty() {
        let alt_screen_active = terminal.is_alt_screen_active();
        trace_terminal_io_event(&format!(
            "response processed_bytes={processed_bytes} alt={} bytes={}",
            alt_screen_active,
            escaped_trace_bytes(&responses)
        ));
        response_sink(processed_bytes, alt_screen_active, responses);
    }
}

fn normalize_responses(emulation: TerminalEmulation, responses: Vec<u8>) -> Vec<u8> {
    if emulation != TerminalEmulation::Vt220 || responses.is_empty() {
        return responses;
    }

    String::from_utf8_lossy(&responses)
        .replace("\x1b[?62;1;4;6;9;15;22;52c", VT220_PRIMARY_DA_RESPONSE)
        .replace("\x1b[>82;10000;0c", VT220_SECONDARY_DA_RESPONSE)
        .into_bytes()
}

fn trace_terminal_io_event(message: &str) {
    if !*TRACE_TERMINAL_IO {
        return;
    }
    eprintln!("[ianvs-terminal-io] {message}");
}

fn trace_terminal_io_bytes(label: &str, bytes: &[u8]) {
    if !*TRACE_TERMINAL_IO {
        return;
    }
    eprintln!("[ianvs-terminal-io] {label} {}", escaped_trace_bytes(bytes));
}

fn escaped_trace_bytes(bytes: &[u8]) -> String {
    let mut escaped = String::new();
    for byte in bytes {
        match *byte {
            b'\n' => escaped.push_str("\\n"),
            b'\r' => escaped.push_str("\\r"),
            b'\t' => escaped.push_str("\\t"),
            0x1b => escaped.push_str("\\x1b"),
            0x07 => escaped.push_str("\\x07"),
            0x20..=0x7e => escaped.push(*byte as char),
            other => escaped.push_str(&format!("\\x{other:02x}")),
        }
    }
    escaped
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

fn apply_profile_colors_and_reset_screen(terminal: &mut Terminal, colors: &TerminalProfileColors) {
    apply_profile_colors(terminal, colors);
    // Keep parser colors and preallocated blank cells aligned with profile
    // defaults; ED 2 alone would clear cells back to library defaults.
    terminal.process(b"\x1b[0m\x1b[H\x1b[J");
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

fn resolve_color_rgb(color: Color, ansi_palette: &[Color; 16]) -> (u8, u8, u8) {
    match color {
        Color::Named(named) => ansi_palette[named as usize].to_rgb(),
        Color::Indexed(index) if index < 16 => ansi_palette[index as usize].to_rgb(),
        _ => color.to_rgb(),
    }
}

fn color_to_hex(color: Color, ansi_palette: &[Color; 16]) -> Option<String> {
    let (red, green, blue) = resolve_color_rgb(color, ansi_palette);
    Some(format!("#{red:02x}{green:02x}{blue:02x}"))
}

fn color_to_hex_delta(color: Color, default: Color, ansi_palette: &[Color; 16]) -> Option<String> {
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

fn export_asciinema_session(session_id: u64) -> Result<String, SessionError> {
    STORE.get(session_id)?.export_asciinema_recording_json()
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
            let max_lines = request
                .get("maxLines")
                .or_else(|| request.get("max_lines"))
                .and_then(serde_json::Value::as_u64)
                .and_then(|value| usize::try_from(value).ok());
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
        "terminal.export_asciinema" => export_asciinema_session(session_id).map(Some),
        _ => Ok(None),
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::TerminalProfileSpecialColors;
    use par_term_emu_core_rust::cell::Cell;
    use par_term_emu_core_rust::terminal::Terminal;

    #[test]
    fn color_to_hex_handles_named_and_rgb_colors() {
        let mut terminal = Terminal::with_scrollback(4, 4, 16);
        terminal
            .set_ansi_palette_color(1, Color::Rgb(0x12, 0x34, 0x56))
            .unwrap();
        let ansi_palette = *terminal.get_ansi_palette();

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
    fn extract_row_tracks_style_runs_in_terminal_columns() {
        let mut terminal = Terminal::with_scrollback(4, 4, 16);
        terminal
            .set_ansi_palette_color(1, Color::Rgb(0x12, 0x34, 0x56))
            .unwrap();
        let ansi_palette = *terminal.get_ansi_palette();
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
            ansi_palette,
        };

        let extracted = extract_row(Some(&row), false, &theme, true);

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
        let ansi_palette = *terminal.get_ansi_palette();
        let default_fg = Color::Rgb(0xAB, 0xCD, 0xEF);
        let default_bg = Color::Rgb(0x12, 0x34, 0x56);
        let theme = TerminalThemeSnapshot {
            default_fg,
            default_bg,
            ansi_palette,
        };
        let row = vec![Cell::with_colors('a', default_fg, default_bg)];

        let extracted = extract_row(Some(&row), false, &theme, true);

        assert_eq!(extracted.text, "a");
        assert_eq!(extracted.style_runs.len(), 1);
        assert_eq!(extracted.style_runs[0].start, 0);
        assert_eq!(extracted.style_runs[0].end, 1);
        assert_eq!(extracted.style_runs[0].foreground, None);
        assert_eq!(extracted.style_runs[0].background, None);
    }

    #[test]
    fn extract_row_omits_trailing_blank_background_when_not_preserved() {
        let terminal = Terminal::with_scrollback(6, 2, 16);
        let ansi_palette = *terminal.get_ansi_palette();
        let default_fg = Color::Rgb(0x1F, 0x29, 0x37);
        let default_bg = Color::Rgb(0xF6, 0xF3, 0xEC);
        let leaked_bg = Color::Rgb(0x00, 0x00, 0x00);
        let theme = TerminalThemeSnapshot {
            default_fg,
            default_bg,
            ansi_palette,
        };
        let mut row = vec![
            Cell::with_colors('a', default_fg, default_bg),
            Cell::with_colors('b', default_fg, default_bg),
            Cell::with_colors('c', default_fg, default_bg),
        ];
        row.extend((0..3).map(|_| Cell::with_colors(' ', default_fg, leaked_bg)));

        let extracted = extract_row(Some(&row), false, &theme, false);
        let preserved = extract_row(Some(&row), false, &theme, true);

        assert_eq!(extracted.text, "abc   ");
        assert!(
            extracted
                .style_runs
                .iter()
                .all(|run| run.background.is_none()),
            "non-cursor main-screen rows should not export prompt-background leaks: {:?}",
            extracted.style_runs
        );
        assert!(
            preserved
                .style_runs
                .iter()
                .any(|run| run.background == Some("#000000".to_string())),
            "cursor or alternate-screen rows still preserve intentional trailing backgrounds"
        );
    }

    #[test]
    fn profile_colors_repaint_initial_blank_cells() {
        let mut terminal = Terminal::with_scrollback(6, 2, 16);
        let colors = TerminalProfileColors {
            special: TerminalProfileSpecialColors {
                foreground: Some("#1f2937".to_string()),
                background: Some("#f6f3ec".to_string()),
                ..TerminalProfileSpecialColors::default()
            },
            ..TerminalProfileColors::default()
        };

        apply_profile_colors_and_reset_screen(&mut terminal, &colors);
        terminal.process(b"abc");

        let theme = terminal_theme_snapshot(&terminal);
        let extracted = extract_row(terminal.grid().row(0), false, &theme, false);

        assert_eq!(extracted.text, "abc   ");
        assert!(
            extracted
                .style_runs
                .iter()
                .all(|run| run.background.is_none()),
            "profile default backgrounds should stay implicit for both text and trailing blanks: {:?}",
            extracted.style_runs
        );
    }

    #[test]
    fn vt220_response_normalization_rewrites_da_sequences() {
        let input = b"\x1b[?62;1;4;6;9;15;22;52c\x1b[>82;10000;0c".to_vec();
        let output = normalize_responses(TerminalEmulation::Vt220, input);
        assert_eq!(
            String::from_utf8(output).unwrap(),
            format!("{VT220_PRIMARY_DA_RESPONSE}{VT220_SECONDARY_DA_RESPONSE}")
        );
    }

    #[test]
    fn terminal_responses_are_drained_when_query_sequence_completes() {
        let mut terminal = Terminal::with_scrollback(80, 24, 100);
        let mut drains = Vec::new();

        process_terminal_output_with_immediate_responses(
            &mut terminal,
            TerminalEmulation::Xterm256,
            b"\x1b[6nabc",
            &mut |processed_bytes, _, responses| {
                drains.push((processed_bytes, String::from_utf8(responses).unwrap()));
            },
        );

        assert_eq!(drains.len(), 1);
        assert_eq!(drains[0].0, b"\x1b[6n".len());
        assert!(drains[0].1.ends_with('R'));
    }

    #[test]
    fn terminal_responses_are_drained_before_following_plain_bytes() {
        let mut terminal = Terminal::with_scrollback(80, 24, 100);
        let segments: &[(&[u8], bool)] = &[
            (b"\x1b[>c", true),
            (b"plain-a", false),
            (b"\x1b]10;?\x07", true),
            (b"plain-b", false),
            (b"\x1b]11;?\x1b\\", true),
            (b"plain-c", false),
            (b"\x1b[?12$p", true),
            (b"plain-d", false),
        ];
        let mut input = Vec::new();
        let mut expected_offsets = Vec::new();
        for (bytes, expects_response) in segments {
            input.extend_from_slice(bytes);
            if *expects_response {
                expected_offsets.push(input.len());
            }
        }
        let mut drains = Vec::new();

        process_terminal_output_with_immediate_responses(
            &mut terminal,
            TerminalEmulation::Xterm256,
            &input,
            &mut |processed_bytes, _, responses| {
                drains.push((processed_bytes, String::from_utf8(responses).unwrap()));
            },
        );

        let actual_offsets = drains
            .iter()
            .map(|(processed_bytes, _)| *processed_bytes)
            .collect::<Vec<_>>();
        assert_eq!(actual_offsets, expected_offsets);
        assert!(drains[0].1.contains("\x1b[>82;10000;0c"));
        assert!(drains[1].1.starts_with("\x1b]10;rgb:"));
        assert!(drains[2].1.starts_with("\x1b]11;rgb:"));
        assert!(drains[3].1.contains("$y"));
    }

    #[test]
    fn terminal_responses_and_host_events_follow_split_byte_order() {
        let mut terminal = Terminal::with_scrollback(80, 24, 100);
        let mut host_protocol = HostProtocolState::default();
        let osc10 = b"\x1b]10;?\x1b\\";
        let plain = b"plain";
        let hook = b"\x1bPhook;7b22686f6f6b223a22707265636d64222c22707764223a222f746d702f69616e7673207465726d696e616c227d\x1b\\";
        let decrqm = b"\x1b[?12$p";
        let osc11 = b"\x1b]11;?\x1b\\";
        let tail = b"tail";
        let mut input = Vec::new();
        input.extend_from_slice(osc10);
        input.extend_from_slice(plain);
        input.extend_from_slice(hook);
        input.extend_from_slice(decrqm);
        input.extend_from_slice(osc11);
        input.extend_from_slice(tail);
        let expected = vec![
            (osc10.len(), "response:osc10".to_string()),
            (
                osc10.len() + plain.len() + hook.len(),
                "event:precmd".to_string(),
            ),
            (
                osc10.len() + plain.len() + hook.len() + decrqm.len(),
                "response:decrqm".to_string(),
            ),
            (
                osc10.len() + plain.len() + hook.len() + decrqm.len() + osc11.len(),
                "response:osc11".to_string(),
            ),
        ];
        let split_points = [
            osc10.len() - 1,
            osc10.len() + plain.len() + 20,
            osc10.len() + plain.len() + hook.len() - 1,
            input.len() - 1,
            input.len(),
        ];
        let timeline = std::cell::RefCell::new(Vec::new());
        let mut chunk_start = 0usize;

        for chunk_end in split_points {
            let chunk = &input[chunk_start..chunk_end];
            process_terminal_output_with_immediate_responses_and_host_events(
                &mut terminal,
                &mut host_protocol,
                TerminalEmulation::Xterm256,
                chunk,
                &mut |processed_bytes, _, responses| {
                    let response = String::from_utf8_lossy(&responses);
                    let label = if response.starts_with("\x1b]10;rgb:") {
                        "response:osc10"
                    } else if response.starts_with("\x1b]11;rgb:") {
                        "response:osc11"
                    } else if response.contains("$y") {
                        "response:decrqm"
                    } else {
                        "response:other"
                    };
                    timeline
                        .borrow_mut()
                        .push((chunk_start + processed_bytes, label.to_string()));
                },
                &mut |processed_bytes, event| match event {
                    CallbackEvent::ShellHook { payload } => {
                        let hook = payload["hook"].as_str().unwrap_or("unknown");
                        timeline
                            .borrow_mut()
                            .push((chunk_start + processed_bytes, format!("event:{hook}")));
                    }
                    other => timeline
                        .borrow_mut()
                        .push((chunk_start + processed_bytes, format!("event:{other:?}"))),
                },
            );
            chunk_start = chunk_end;
        }

        assert_eq!(timeline.into_inner(), expected);
        assert!(host_protocol.buffer.is_empty());
    }

    #[test]
    fn terminal_response_sequences_do_not_generate_follow_up_responses() {
        let mut terminal = Terminal::with_scrollback(80, 24, 100);
        let response_bytes = b"\x1b[2;2R\x1b[3;1R\x1b[>82;10000;0c\x1b]11;rgb:0000/0000/0000\x1b\\\x1b]10;rgb:c0c0/c0c0/c0c0\x1b\\\x1b[>4;2m\x1b[?12;0$y";
        let mut drains = Vec::new();

        process_terminal_output_with_immediate_responses(
            &mut terminal,
            TerminalEmulation::Xterm256,
            response_bytes,
            &mut |processed_bytes, _, responses| {
                drains.push((
                    processed_bytes,
                    String::from_utf8_lossy(&responses).to_string(),
                ));
            },
        );

        assert_eq!(drains, Vec::<(usize, String)>::new());
    }

    #[test]
    fn transcript_replay_discards_generated_terminal_responses() {
        let mut terminal = Terminal::with_scrollback(80, 24, 100);
        terminal.process(b"\x1b[>c");
        assert!(terminal.has_pending_responses());

        replay_transcript_without_terminal_responses(&mut terminal, b"\x1b[>c");

        assert!(!terminal.has_pending_responses());
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
}
