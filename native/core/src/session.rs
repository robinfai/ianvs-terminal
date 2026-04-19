use crate::model::{
    TerminalCursor, TerminalDirtyRange, TerminalEvent, TerminalFrameDiff, TerminalProfile,
    TerminalRow, TerminalStyleRun,
};
use crate::pty::spawn_pty;
use parking_lot::Mutex;
use std::collections::{HashMap, VecDeque};
use std::io::{Read, Write};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, LazyLock,
};
use std::thread;
use vt100::{Callbacks, Color, Parser, Screen};

const DEFAULT_ROWS: u16 = 32;
const DEFAULT_COLS: u16 = 120;
const DEFAULT_SCROLLBACK: usize = 8_000;

static STORE: LazyLock<SessionStore> = LazyLock::new(SessionStore::default);

enum CallbackEvent {
    Resize { rows: u16, cols: u16 },
    ClipboardCopy { selection: String, data: String },
    ClipboardPasteRequest { selection: String },
}

#[derive(Default)]
struct SessionCallbacks {
    window_title: Option<String>,
    window_icon_name: Option<String>,
    pending_events: VecDeque<CallbackEvent>,
}

impl Callbacks for SessionCallbacks {
    fn resize(&mut self, screen: &mut Screen, request: (u16, u16)) {
        let rows = request.0.max(1);
        let cols = request.1.max(1);
        screen.set_size(rows, cols);
        self.pending_events
            .push_back(CallbackEvent::Resize { rows, cols });
    }

    fn set_window_icon_name(&mut self, _: &mut Screen, icon_name: &[u8]) {
        self.window_icon_name = Some(String::from_utf8_lossy(icon_name).into_owned());
    }

    fn set_window_title(&mut self, _: &mut Screen, title: &[u8]) {
        self.window_title = Some(String::from_utf8_lossy(title).into_owned());
    }

    fn copy_to_clipboard(&mut self, _: &mut Screen, ty: &[u8], data: &[u8]) {
        self.pending_events.push_back(CallbackEvent::ClipboardCopy {
            selection: String::from_utf8_lossy(ty).into_owned(),
            data: String::from_utf8_lossy(data).into_owned(),
        });
    }

    fn paste_from_clipboard(&mut self, _: &mut Screen, ty: &[u8]) {
        self.pending_events
            .push_back(CallbackEvent::ClipboardPasteRequest {
                selection: String::from_utf8_lossy(ty).into_owned(),
            });
    }
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

pub struct TerminalSession {
    session_id: u64,
    parser: Mutex<Parser<SessionCallbacks>>,
    writer: Mutex<Box<dyn Write + Send>>,
    master: Mutex<Box<dyn portable_pty::MasterPty + Send>>,
    child: Mutex<Box<dyn portable_pty::Child + Send + Sync>>,
    events: Mutex<VecDeque<TerminalEvent>>,
    dirty: AtomicBool,
    last_rows: Mutex<Vec<String>>,
    exited: AtomicBool,
}

impl TerminalSession {
    pub fn spawn(session_id: u64, profile: TerminalProfile) -> Result<Arc<Self>, SessionError> {
        let runtime = spawn_pty(&profile, DEFAULT_ROWS, DEFAULT_COLS)
            .map_err(|error: anyhow::Error| SessionError::Pty(error.to_string()))?;

        let session = Arc::new(Self {
            session_id,
            parser: Mutex::new(Parser::new_with_callbacks(
                DEFAULT_ROWS,
                DEFAULT_COLS,
                DEFAULT_SCROLLBACK,
                SessionCallbacks::default(),
            )),
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
                        let mut parser = reader_session.parser.lock();
                        parser.process(&buf[..read]);
                        drop(parser);
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
        self.master
            .lock()
            .resize(portable_pty::PtySize {
                rows,
                cols,
                pixel_width,
                pixel_height,
            })
            .map_err(|error| SessionError::Pty(error.to_string()))?;
        self.parser.lock().screen_mut().set_size(rows, cols);
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
        let mut parser = self.parser.lock();
        let screen = parser.screen_mut();
        let current = screen.scrollback() as i32;
        let next = current.saturating_add(delta_lines).max(0) as usize;
        screen.set_scrollback(next);
        self.dirty.store(true, Ordering::SeqCst);
    }

    pub fn scroll_to(&self, offset: usize) {
        let mut parser = self.parser.lock();
        parser.screen_mut().set_scrollback(offset);
        self.dirty.store(true, Ordering::SeqCst);
    }

    pub fn take_frame_diff(&self) -> Result<Option<TerminalFrameDiff>, SessionError> {
        if !self.dirty.swap(false, Ordering::SeqCst) {
            return Ok(None);
        }

        let mut parser = self.parser.lock();
        let window_title = parser.callbacks().window_title.clone();
        let window_icon_name = parser.callbacks().window_icon_name.clone();
        let screen = parser.screen_mut();
        let (viewport_rows, viewport_cols) = screen.size();
        let scrollback_offset = screen.scrollback();
        let scrollback_max_offset = screen_max_scrollback(screen);
        let cursor = screen.cursor_position();
        let mut rows = Vec::with_capacity(viewport_rows as usize);
        let mut dirty_ranges = Vec::new();
        let mut current_row_text = Vec::with_capacity(viewport_rows as usize);
        let mut last_rows = self.last_rows.lock();

        for row in 0..viewport_rows as usize {
            let mut text = String::with_capacity(viewport_cols as usize);
            let mut style_runs = Vec::new();
            let mut run_start = 0usize;
            let mut run_style: Option<TerminalStyleRun> = None;

            for col in 0..viewport_cols as usize {
                if let Some(cell) = screen.cell(row as u16, col as u16) {
                    let contents = cell.contents();
                    let grapheme = if contents.is_empty() { " " } else { contents };
                    text.push_str(grapheme);

                    let style = TerminalStyleRun {
                        start: col,
                        end: col + grapheme.chars().count().max(1),
                        foreground: color_to_hex(cell.fgcolor()),
                        background: color_to_hex(cell.bgcolor()),
                        bold: cell.bold(),
                        italic: cell.italic(),
                        underline: cell.underline(),
                        inverse: cell.inverse(),
                    };

                    match &run_style {
                        Some(existing) if same_style(existing, &style) => {}
                        Some(existing) => {
                            let mut finalized = existing.clone();
                            finalized.start = run_start;
                            finalized.end = col;
                            style_runs.push(finalized);
                            run_start = col;
                            run_style = Some(style);
                        }
                        None => {
                            run_start = col;
                            run_style = Some(style);
                        }
                    }
                }
            }

            if let Some(existing) = run_style {
                let mut finalized = existing.clone();
                finalized.start = run_start;
                finalized.end = viewport_cols as usize;
                style_runs.push(finalized);
            }

            current_row_text.push(text.clone());
            rows.push(TerminalRow {
                index: row,
                text,
                style_runs,
            });
        }

        for (index, row_text) in current_row_text.iter().enumerate() {
            if last_rows.get(index).map(|entry| entry.as_str()) != Some(row_text.as_str()) {
                dirty_ranges.push(TerminalDirtyRange {
                    start: index,
                    end: index + 1,
                });
            }
        }
        *last_rows = current_row_text;

        Ok(Some(TerminalFrameDiff {
            rows,
            cursor: TerminalCursor {
                row: cursor.0 as usize,
                col: cursor.1 as usize,
                visible: !screen.hide_cursor(),
            },
            selection: None,
            viewport_rows,
            viewport_cols,
            dirty_ranges,
            scrollback_offset,
            scrollback_max_offset,
            window_title,
            window_icon_name,
        }))
    }

    pub fn poll_events(&self) -> Result<Vec<TerminalEvent>, SessionError> {
        self.drain_callback_events();
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

    fn drain_callback_events(&self) {
        let mut parser = self.parser.lock();
        let pending_events = std::mem::take(&mut parser.callbacks_mut().pending_events);
        drop(parser);

        for event in pending_events {
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
    }

    fn push_event(&self, kind: &str, payload: Option<serde_json::Value>) {
        self.events.lock().push_back(TerminalEvent {
            kind: kind.to_string(),
            session_id: self.session_id,
            payload,
        });
    }
}

fn same_style(left: &TerminalStyleRun, right: &TerminalStyleRun) -> bool {
    left.foreground == right.foreground
        && left.background == right.background
        && left.bold == right.bold
        && left.italic == right.italic
        && left.underline == right.underline
        && left.inverse == right.inverse
}

fn color_to_hex(color: Color) -> Option<String> {
    match color {
        Color::Default => None,
        Color::Idx(index) => Some(match index {
            0 => "#000000".to_string(),
            1 => "#cd0000".to_string(),
            2 => "#00cd00".to_string(),
            3 => "#cdcd00".to_string(),
            4 => "#0000ee".to_string(),
            5 => "#cd00cd".to_string(),
            6 => "#00cdcd".to_string(),
            7 => "#e5e5e5".to_string(),
            8 => "#7f7f7f".to_string(),
            9 => "#ff0000".to_string(),
            10 => "#00ff00".to_string(),
            11 => "#ffff00".to_string(),
            12 => "#5c5cff".to_string(),
            13 => "#ff00ff".to_string(),
            14 => "#00ffff".to_string(),
            15 => "#ffffff".to_string(),
            16..=231 => {
                let palette = [0, 95, 135, 175, 215, 255];
                let idx = (index - 16) as usize;
                let red = palette[idx / 36];
                let green = palette[(idx % 36) / 6];
                let blue = palette[idx % 6];
                format!("#{red:02x}{green:02x}{blue:02x}")
            }
            232..=255 => {
                let level = 8 + ((index - 232) * 10);
                format!("#{0:02x}{0:02x}{0:02x}", level)
            }
        }),
        Color::Rgb(red, green, blue) => Some(format!("#{red:02x}{green:02x}{blue:02x}")),
    }
}

fn screen_max_scrollback(screen: &mut Screen) -> usize {
    let current = screen.scrollback();
    screen.set_scrollback(usize::MAX);
    let max_offset = screen.scrollback();
    screen.set_scrollback(current);
    max_offset
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn color_to_hex_handles_extended_colors() {
        assert_eq!(color_to_hex(Color::Idx(0)), Some("#000000".to_string()));
        assert_eq!(color_to_hex(Color::Idx(11)), Some("#ffff00".to_string()));
        assert_eq!(color_to_hex(Color::Idx(12)), Some("#5c5cff".to_string()));
        assert_eq!(color_to_hex(Color::Idx(196)), Some("#ff0000".to_string()));
        assert_eq!(color_to_hex(Color::Idx(46)), Some("#00ff00".to_string()));
        assert_eq!(color_to_hex(Color::Idx(233)), Some("#121212".to_string()));
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
