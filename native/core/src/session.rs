use crate::model::{
    TerminalCursor, TerminalDirtyRange, TerminalEmulation, TerminalEvent, TerminalFrameDiff,
    TerminalFrameModes, TerminalHyperlinkRange, TerminalProfile, TerminalRow, TerminalSearchMatch,
    TerminalStyleRun,
};
use crate::pty::spawn_pty;
use par_term_emu_core_rust::cell::Cell;
use par_term_emu_core_rust::color::{Color, NamedColor};
use par_term_emu_core_rust::grid::Grid;
use par_term_emu_core_rust::mouse::{MouseEncoding, MouseMode};
use par_term_emu_core_rust::terminal::Terminal;
use parking_lot::Mutex;
use std::collections::{HashMap, VecDeque};
use std::io::{Read, Write};
use std::sync::{
    Arc, LazyLock,
    atomic::{AtomicBool, Ordering},
};
use std::thread;

const DEFAULT_ROWS: u16 = 32;
const DEFAULT_COLS: u16 = 120;
const DEFAULT_SCROLLBACK: usize = 8_000;
const VT220_PRIMARY_DA_RESPONSE: &str = "\x1b[?62;1;2;6;7;8;9c";
const VT220_SECONDARY_DA_RESPONSE: &str = "\x1b[>1;10;0c";

static STORE: LazyLock<SessionStore> = LazyLock::new(SessionStore::default);

#[derive(Clone, Debug)]
enum CallbackEvent {
    Resize { rows: u16, cols: u16 },
    ClipboardCopy { selection: String, data: String },
    ClipboardPasteRequest { selection: String },
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct CachedRowState {
    text: String,
    wrapped: bool,
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
    state: Mutex<TerminalState>,
    writer: Mutex<Box<dyn Write + Send>>,
    master: Mutex<Box<dyn portable_pty::MasterPty + Send>>,
    child: Mutex<Box<dyn portable_pty::Child + Send + Sync>>,
    events: Mutex<VecDeque<TerminalEvent>>,
    dirty: AtomicBool,
    last_rows: Mutex<Vec<CachedRowState>>,
    exited: AtomicBool,
}

impl TerminalSession {
    pub fn spawn(session_id: u64, profile: TerminalProfile) -> Result<Arc<Self>, SessionError> {
        let runtime = spawn_pty(&profile, DEFAULT_ROWS, DEFAULT_COLS)
            .map_err(|error: anyhow::Error| SessionError::Pty(error.to_string()))?;

        let mut terminal = Terminal::with_scrollback(
            DEFAULT_COLS as usize,
            DEFAULT_ROWS as usize,
            DEFAULT_SCROLLBACK,
        );
        if profile.terminal_emulation == TerminalEmulation::Vt220 {
            terminal.process(b"\x1b[62;1\"p");
        }

        let session = Arc::new(Self {
            session_id,
            emulation: profile.terminal_emulation,
            state: Mutex::new(TerminalState {
                terminal,
                transcript: Vec::new(),
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
            last_rows: Mutex::new(Vec::new()),
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
                        let (callback_events, responses) = {
                            let mut state = reader_session.state.lock();
                            let callback_events = state
                                .host_protocol
                                .observe(&buf[..read], reader_session.emulation);
                            state.terminal.process(&buf[..read]);
                            state.transcript.extend_from_slice(&buf[..read]);
                            let responses = normalize_responses(
                                reader_session.emulation,
                                state.terminal.drain_responses(),
                            );
                            (callback_events, responses)
                        };

                        for event in callback_events {
                            reader_session.push_callback_event(event);
                        }
                        if !responses.is_empty() {
                            let _ = reader_session.writer.lock().write_all(&responses);
                        }

                        reader_session.dirty.store(true, Ordering::SeqCst);
                        reader_session.push_event("activity", None);
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

        if should_rebuild_main_screen {
            let transcript = state.transcript.clone();
            let mut terminal =
                Terminal::with_scrollback(cols as usize, rows as usize, DEFAULT_SCROLLBACK);
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
        self.dirty.store(true, Ordering::SeqCst);
    }

    pub fn scroll_to(&self, offset: usize) {
        let mut state = self.state.lock();
        if state.terminal.is_alt_screen_active() {
            state.scrollback_offset = 0;
        } else {
            state.scrollback_offset = offset.min(current_scrollback_max(&state));
        }
        self.dirty.store(true, Ordering::SeqCst);
    }

    pub fn take_frame_diff(&self) -> Result<Option<TerminalFrameDiff>, SessionError> {
        if !self.dirty.swap(false, Ordering::SeqCst) {
            return Ok(None);
        }

        let mut state = self.state.lock();
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

        let mut rows = Vec::with_capacity(viewport_rows);
        let mut hyperlinks = Vec::new();
        let mut dirty_ranges = Vec::new();
        let mut current_rows = Vec::with_capacity(viewport_rows);
        let mut last_rows = self.last_rows.lock();

        for row in 0..viewport_rows {
            let (cells, wrapped) = if alt_screen_active {
                (
                    terminal.alt_grid().row(row),
                    terminal.alt_grid().is_line_wrapped(row),
                )
            } else {
                primary_row_cells(terminal.grid(), viewport_rows, state.scrollback_offset, row)
            };
            let extracted = extract_row(cells, wrapped);
            if self.emulation == TerminalEmulation::Xterm256 {
                hyperlinks.extend(extract_hyperlinks_for_row(terminal, cells, row));
            }

            current_rows.push(CachedRowState {
                text: extracted.text.clone(),
                wrapped: extracted.wrapped,
            });
            rows.push(TerminalRow {
                index: row,
                text: extracted.text,
                wrapped: extracted.wrapped,
                style_runs: extracted.style_runs,
            });
        }

        for (index, row_state) in current_rows.iter().enumerate() {
            if last_rows.get(index) != Some(row_state) {
                dirty_ranges.push(TerminalDirtyRange {
                    start: index,
                    end: index + 1,
                });
            }
        }
        *last_rows = current_rows;

        Ok(Some(TerminalFrameDiff {
            rows,
            cursor: TerminalCursor {
                row: cursor.row,
                col: cursor.col,
                visible: cursor.visible,
            },
            selection: None,
            viewport_rows: viewport_rows as u16,
            viewport_cols: viewport_cols as u16,
            dirty_ranges,
            scrollback_offset: state.scrollback_offset,
            scrollback_max_offset,
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

fn primary_row_cells(
    grid: &Grid,
    viewport_rows: usize,
    scrollback_offset: usize,
    row: usize,
) -> (Option<&[Cell]>, bool) {
    let scrollback_len = grid.scrollback_len();
    let total_lines = scrollback_len + viewport_rows;
    let start_index = total_lines.saturating_sub(viewport_rows + scrollback_offset);
    let visible_index = start_index + row;

    if visible_index < scrollback_len {
        (
            grid.scrollback_line(visible_index),
            grid.is_scrollback_wrapped(visible_index),
        )
    } else {
        let screen_row = visible_index.saturating_sub(scrollback_len);
        (grid.row(screen_row), grid.is_line_wrapped(screen_row))
    }
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

pub fn take_frame_diff(session_id: u64) -> Result<Option<String>, SessionError> {
    Ok(STORE
        .get(session_id)?
        .take_frame_diff()?
        .map(|diff| {
            serde_json::to_string(&diff).map_err(|error| SessionError::Serialize(error.to_string()))
        })
        .transpose()?)
}

pub fn poll_events(session_id: u64) -> Result<String, SessionError> {
    let events = STORE.get(session_id)?.poll_events()?;
    serde_json::to_string(&events).map_err(|error| SessionError::Serialize(error.to_string()))
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
}
