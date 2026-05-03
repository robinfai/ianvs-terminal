use crate::model::{
    TerminalCursor, TerminalDirtyRange, TerminalEmulation, TerminalEvent, TerminalFrameDiff,
    TerminalFrameKind, TerminalFrameModes, TerminalHyperlinkRange, TerminalProfile, TerminalRow,
    TerminalSearchMatch, TerminalSelectionRequest, TerminalStyleRun,
};
use crate::pty::spawn_pty;
use par_term_emu_core_rust::cell::{Cell, CellFlags};
use par_term_emu_core_rust::color::{Color, NamedColor};
use par_term_emu_core_rust::grid::{Grid, ScrollRegionDamage};
use par_term_emu_core_rust::mouse::{MouseEncoding, MouseMode};
use par_term_emu_core_rust::terminal::{Terminal, TerminalDamage, TerminalProcessDebugStats};
use parking_lot::Mutex;
use std::collections::{BTreeSet, HashMap, VecDeque};
use std::hash::{DefaultHasher, Hash, Hasher};
use std::io::{Read, Write};
use std::sync::{
    Arc, LazyLock,
    atomic::{AtomicBool, Ordering},
};
use std::thread;
use std::time::Instant;

const DEFAULT_ROWS: u16 = 32;
const DEFAULT_COLS: u16 = 120;
const MAX_TRANSCRIPT_BYTES: usize = 256 * 1024;
const VT220_PRIMARY_DA_RESPONSE: &str = "\x1b[?62;1;2;6;7;8;9c";
const VT220_SECONDARY_DA_RESPONSE: &str = "\x1b[>1;10;0c";

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
    state: Mutex<TerminalState>,
    writer: Mutex<Box<dyn Write + Send>>,
    master: Mutex<Box<dyn portable_pty::MasterPty + Send>>,
    child: Mutex<Box<dyn portable_pty::Child + Send + Sync>>,
    events: Mutex<VecDeque<TerminalEvent>>,
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
        let runtime = spawn_pty(&profile, DEFAULT_ROWS, DEFAULT_COLS)
            .map_err(|error: anyhow::Error| SessionError::Pty(error.to_string()))?;

        let mut terminal = Terminal::with_scrollback(
            DEFAULT_COLS as usize,
            DEFAULT_ROWS as usize,
            scrollback_lines,
        );
        if emulation == TerminalEmulation::Vt220 {
            terminal.process(b"\x1b[62;1\"p");
        }

        let session = Arc::new(Self {
            session_id,
            emulation,
            scrollback_lines,
            state: Mutex::new(TerminalState {
                terminal,
                transcript: Vec::new(),
                transcript_truncated: false,
                scrollback_offset: 0,
                host_protocol: HostProtocolState::default(),
            }),
            writer: Mutex::new(runtime.writer),
            master: Mutex::new(runtime.master),
            child: Mutex::new(runtime.child),
            events: Mutex::new(VecDeque::from([TerminalEvent {
                kind: "started".to_string(),
                session_id,
                payload: None,
            }])),
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
            let mut reader = runtime.reader;
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
                            host_protocol_micros,
                            terminal_process_micros,
                            terminal_process_breakdown,
                        ) = {
                            let mut state = reader_session.state.lock();
                            let cursor_before = terminal_cursor_snapshot(state.terminal.cursor());
                            let host_started_at = Instant::now();
                            let callback_events = state
                                .host_protocol
                                .observe(&buf[..read], reader_session.emulation);
                            let host_protocol_micros = host_started_at.elapsed().as_micros() as u64;
                            let process_started_at = Instant::now();
                            state.terminal.process(&buf[..read]);
                            let terminal_process_micros =
                                process_started_at.elapsed().as_micros() as u64;
                            let terminal_process_breakdown =
                                state.terminal.take_process_debug_stats();
                            append_transcript(&mut state, &buf[..read]);
                            let damage = state.terminal.drain_active_screen_damage();
                            let cursor_after = terminal_cursor_snapshot(state.terminal.cursor());
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
                                host_protocol_micros,
                                terminal_process_micros,
                                terminal_process_breakdown,
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

                        reader_session.dirty.store(true, Ordering::SeqCst);
                    }
                    Err(_) => break,
                }
            }
        });

        Ok(session)
    }

    pub fn ping(&self) -> i32 {
        42
    }

    pub fn close(&self) -> Result<(), SessionError> {
        let _ = self.child.lock().kill();
        Ok(())
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
            if self.emulation == TerminalEmulation::Vt220 {
                terminal.process(b"\x1b[62;1\"p");
            }
            if pixel_width > 0 && pixel_height > 0 {
                terminal.set_pixel_size(pixel_width as usize, pixel_height as usize);
            }
            terminal.process(&transcript);
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

    pub fn search(&self, query: &str) -> Vec<TerminalSearchMatch> {
        if query.is_empty() {
            return Vec::new();
        }

        let state = self.state.lock();
        let terminal = &state.terminal;
        let (_viewport_cols, viewport_rows) = terminal.size();
        let mut matches = Vec::new();

        if terminal.is_alt_screen_active() {
            for row in 0..viewport_rows {
                let extracted = extract_row(
                    terminal.alt_grid().row(row),
                    terminal.alt_grid().is_line_wrapped(row),
                );
                collect_text_matches(&mut matches, &extracted.text, query, row, 0);
            }
            return matches;
        }

        let grid = terminal.grid();
        let scrollback_len = grid.scrollback_len();
        let total_lines = scrollback_len + viewport_rows;

        for visible_index in 0..total_lines {
            let extracted = if visible_index < scrollback_len {
                extract_row(
                    grid.scrollback_line(visible_index),
                    grid.is_scrollback_wrapped(visible_index),
                )
            } else {
                let screen_row = visible_index.saturating_sub(scrollback_len);
                extract_row(grid.row(screen_row), grid.is_line_wrapped(screen_row))
            };
            let scrollback_offset = total_lines.saturating_sub(viewport_rows + visible_index);
            collect_text_matches(
                &mut matches,
                &extracted.text,
                query,
                visible_index,
                scrollback_offset,
            );
        }

        matches
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
        serde_json::to_string(&stats)
            .map(Some)
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
        self.events.lock().push_back(TerminalEvent {
            kind: kind.to_string(),
            session_id: self.session_id,
            payload,
        });
    }
}

struct ExtractedRow {
    text: String,
    wrapped: bool,
    style_runs: Vec<TerminalStyleRun>,
}

struct ExtractedVisibleRow {
    row: TerminalRow,
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

fn append_transcript(state: &mut TerminalState, bytes: &[u8]) {
    state.transcript.extend_from_slice(bytes);
    if state.transcript.len() <= MAX_TRANSCRIPT_BYTES {
        return;
    }

    let overflow = state.transcript.len() - MAX_TRANSCRIPT_BYTES;
    state.transcript.drain(..overflow);
    state.transcript_truncated = true;
}

fn cached_row_state_for(entry: &ExtractedVisibleRow) -> CachedRowState {
    CachedRowState {
        text: entry.row.text.clone(),
        wrapped: entry.row.wrapped,
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
    let absolute_visible_index = viewport_start_row.saturating_add(viewport_row);
    let (cells, wrapped) = row_cells_for_visible_index(terminal, absolute_visible_index);
    let extracted = extract_row(cells, wrapped);
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

fn extract_row(cells: Option<&[Cell]>, wrapped: bool) -> ExtractedRow {
    let mut text = String::new();
    let mut style_runs = Vec::new();
    let mut run_start = 0usize;
    let mut run_style: Option<TerminalStyleRun> = None;
    let mut column_offset = 0usize;

    for cell in cells.unwrap_or_default() {
        if cell.flags.wide_char_spacer() {
            continue;
        }

        let grapheme = cell.get_grapheme();
        text.push_str(if grapheme.is_empty() { " " } else { &grapheme });
        let column_start = column_offset;
        column_offset += cell.width();
        let column_end = column_offset;
        let style = TerminalStyleRun {
            start: column_start,
            end: column_end,
            foreground: color_to_hex_delta(cell.fg, Color::Named(NamedColor::White)),
            background: color_to_hex_delta(cell.bg, Color::Named(NamedColor::Black)),
            bold: cell.flags.bold(),
            dim: cell.flags.dim(),
            italic: cell.flags.italic(),
            underline: cell.flags.underline(),
            blink: cell.flags.blink(),
            inverse: cell.flags.reverse(),
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

fn collect_text_matches(
    matches: &mut Vec<TerminalSearchMatch>,
    text: &str,
    query: &str,
    row: usize,
    scrollback_offset: usize,
) {
    let mut search_from = 0usize;
    while search_from <= text.len() {
        let Some(relative) = text[search_from..].find(query) else {
            break;
        };
        let start = search_from + relative;
        let end = start + query.len();
        matches.push(TerminalSearchMatch {
            row,
            start_col: column_for_byte_index(text, start),
            end_col: column_for_byte_index(text, end),
            text: query.to_string(),
            scrollback_offset,
        });
        search_from = end;
    }
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

fn normalize_responses(emulation: TerminalEmulation, responses: Vec<u8>) -> Vec<u8> {
    if emulation != TerminalEmulation::Vt220 || responses.is_empty() {
        return responses;
    }

    String::from_utf8_lossy(&responses)
        .replace("\x1b[?62;1;4;6;9;15;22;52c", VT220_PRIMARY_DA_RESPONSE)
        .replace("\x1b[>82;10000;0c", VT220_SECONDARY_DA_RESPONSE)
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

fn color_to_hex(color: Color) -> Option<String> {
    let (red, green, blue) = color.to_rgb();
    Some(format!("#{red:02x}{green:02x}{blue:02x}"))
}

fn color_to_hex_delta(color: Color, default: Color) -> Option<String> {
    if color == default {
        return None;
    }
    color_to_hex(color)
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
    let matches = STORE.get(session_id)?.search(query);
    serde_json::to_string(&matches).map_err(|error| SessionError::Serialize(error.to_string()))
}

pub fn selection_text_session(session_id: u64, request_json: &str) -> Result<String, SessionError> {
    let request: TerminalSelectionRequest = serde_json::from_str(request_json)
        .map_err(|error| SessionError::InvalidSelection(error.to_string()))?;
    Ok(STORE.get(session_id)?.selection_text(request))
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
    use par_term_emu_core_rust::cell::Cell;

    #[test]
    fn color_to_hex_handles_named_and_rgb_colors() {
        assert_eq!(
            color_to_hex(Color::Rgb(255, 0, 0)),
            Some("#ff0000".to_string())
        );
        assert_eq!(
            color_to_hex(Color::Indexed(46)),
            Some("#00ff00".to_string())
        );
        assert_eq!(
            color_to_hex_delta(
                Color::Named(NamedColor::White),
                Color::Named(NamedColor::White)
            ),
            None
        );
        assert_eq!(
            color_to_hex_delta(
                Color::Named(NamedColor::Black),
                Color::Named(NamedColor::Black)
            ),
            None
        );
    }

    #[test]
    fn extract_row_tracks_style_runs_in_terminal_columns() {
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

        let extracted = extract_row(Some(&row), false);

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
            Some("#800000".to_string())
        );
        assert_eq!(extracted.style_runs[1].background, None);
    }

    #[test]
    fn extract_row_omits_default_colors_from_style_runs() {
        let row = vec![Cell::new('a')];

        let extracted = extract_row(Some(&row), false);

        assert_eq!(extracted.text, "a");
        assert_eq!(extracted.style_runs.len(), 1);
        assert_eq!(extracted.style_runs[0].start, 0);
        assert_eq!(extracted.style_runs[0].end, 1);
        assert_eq!(extracted.style_runs[0].foreground, None);
        assert_eq!(extracted.style_runs[0].background, None);
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
            b"22707764223a222f746d702f666c75747465726d227d\x1b\\",
            TerminalEmulation::Xterm256,
        );

        assert_eq!(events.len(), 1);
        match &events[0] {
            CallbackEvent::ShellHook { payload } => {
                assert_eq!(payload["hook"].as_str(), Some("precmd"));
                assert_eq!(payload["pwd"].as_str(), Some("/tmp/flutterm"));
            }
            event => panic!("expected shell hook event, got {event:?}"),
        }
        assert!(state.buffer.is_empty());
    }
}
