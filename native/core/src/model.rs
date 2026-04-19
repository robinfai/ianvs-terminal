use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TerminalEmulation {
    #[default]
    Xterm256,
    Vt220,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalProfile {
    pub id: String,
    pub name: String,
    pub shell: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub env: std::collections::BTreeMap<String, String>,
    pub cwd: Option<String>,
    #[serde(rename = "terminalEmulation", default)]
    pub terminal_emulation: TerminalEmulation,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalStyleRun {
    pub start: usize,
    pub end: usize,
    pub foreground: Option<String>,
    pub background: Option<String>,
    #[serde(default)]
    pub bold: bool,
    #[serde(default)]
    pub dim: bool,
    #[serde(default)]
    pub italic: bool,
    #[serde(default)]
    pub underline: bool,
    #[serde(default)]
    pub blink: bool,
    #[serde(default)]
    pub inverse: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalRow {
    pub index: usize,
    pub text: String,
    #[serde(default)]
    pub wrapped: bool,
    #[serde(default)]
    pub style_runs: Vec<TerminalStyleRun>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalCursor {
    pub row: usize,
    pub col: usize,
    pub visible: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalSelection {
    pub start_row: usize,
    pub start_col: usize,
    pub end_row: usize,
    pub end_col: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalDirtyRange {
    pub start: usize,
    pub end: usize,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TerminalFrameModes {
    #[serde(default)]
    pub application_cursor: bool,
    #[serde(default)]
    pub application_keypad: bool,
    #[serde(default)]
    pub insert_mode: bool,
    #[serde(default)]
    pub origin_mode: bool,
    #[serde(default)]
    pub line_feed_new_line_mode: bool,
    #[serde(default)]
    pub hide_cursor: bool,
    #[serde(default)]
    pub bracketed_paste: bool,
    #[serde(default)]
    pub focus_tracking: bool,
    #[serde(default)]
    pub char_protected: bool,
    #[serde(default = "default_mouse_mode")]
    pub mouse_mode: String,
    #[serde(default = "default_mouse_encoding")]
    pub mouse_encoding: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalFrameDiff {
    pub rows: Vec<TerminalRow>,
    pub cursor: TerminalCursor,
    pub selection: Option<TerminalSelection>,
    pub viewport_rows: u16,
    pub viewport_cols: u16,
    #[serde(default)]
    pub dirty_ranges: Vec<TerminalDirtyRange>,
    #[serde(default)]
    pub scrollback_offset: usize,
    #[serde(default)]
    pub scrollback_max_offset: usize,
    #[serde(default)]
    pub modes: TerminalFrameModes,
    #[serde(default)]
    pub window_title: Option<String>,
    #[serde(default)]
    pub window_icon_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalEvent {
    pub kind: String,
    pub session_id: u64,
    pub payload: Option<Value>,
}

fn default_mouse_mode() -> String {
    "off".to_string()
}

fn default_mouse_encoding() -> String {
    "default".to_string()
}
