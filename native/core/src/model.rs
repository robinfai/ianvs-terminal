use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TerminalEmulation {
    #[default]
    Xterm256,
    Vt220,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TerminalCursorShape {
    #[default]
    Block,
    Underline,
    Beam,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TerminalOptionDragMode {
    NormalSelection,
    #[default]
    BlockSelection,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TerminalProfileLaunch {
    #[serde(default)]
    pub program: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub env: BTreeMap<String, String>,
    #[serde(default)]
    pub cwd: Option<String>,
}

fn default_shell_integration_enabled() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalShellIntegration {
    #[serde(default = "default_shell_integration_enabled")]
    pub enabled: bool,
}

impl Default for TerminalShellIntegration {
    fn default() -> Self {
        Self { enabled: true }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalProfileTerminal {
    #[serde(default)]
    pub emulation: TerminalEmulation,
    #[serde(rename = "scrollbackLines", default = "default_scrollback_lines")]
    pub scrollback_lines: usize,
}

impl Default for TerminalProfileTerminal {
    fn default() -> Self {
        Self {
            emulation: TerminalEmulation::Xterm256,
            scrollback_lines: default_scrollback_lines(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalProfileFont {
    #[serde(default = "default_terminal_primary_font_family")]
    pub family: String,
    #[serde(default = "default_terminal_font_fallback")]
    pub fallback: Vec<String>,
    #[serde(default = "default_terminal_font_size")]
    pub size: f64,
    #[serde(rename = "lineHeight", default = "default_terminal_line_height")]
    pub line_height: f64,
}

impl Default for TerminalProfileFont {
    fn default() -> Self {
        Self {
            family: default_terminal_primary_font_family(),
            fallback: default_terminal_font_fallback(),
            size: default_terminal_font_size(),
            line_height: default_terminal_line_height(),
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TerminalProfileColors {
    #[serde(default)]
    pub foreground: Option<String>,
    #[serde(default)]
    pub background: Option<String>,
    #[serde(default)]
    pub cursor: Option<String>,
    #[serde(default)]
    pub selection: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalProfileCursor {
    #[serde(default)]
    pub shape: TerminalCursorShape,
    #[serde(default = "default_cursor_blink")]
    pub blink: bool,
}

impl Default for TerminalProfileCursor {
    fn default() -> Self {
        Self {
            shape: TerminalCursorShape::Block,
            blink: default_cursor_blink(),
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TerminalProfileAppearance {
    #[serde(default)]
    pub font: TerminalProfileFont,
    #[serde(default)]
    pub colors: TerminalProfileColors,
    #[serde(default)]
    pub cursor: TerminalProfileCursor,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalProfileInteraction {
    #[serde(rename = "copyOnSelect", default)]
    pub copy_on_select: bool,
    #[serde(rename = "optionDragMode", default)]
    pub option_drag_mode: TerminalOptionDragMode,
}

impl Default for TerminalProfileInteraction {
    fn default() -> Self {
        Self {
            copy_on_select: false,
            option_drag_mode: TerminalOptionDragMode::BlockSelection,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct TerminalProfile {
    pub id: String,
    pub name: String,
    pub launch: TerminalProfileLaunch,
    #[serde(default)]
    pub terminal: TerminalProfileTerminal,
    #[serde(rename = "shellIntegration", default)]
    pub shell_integration: TerminalShellIntegration,
    #[serde(default)]
    pub appearance: TerminalProfileAppearance,
    #[serde(default)]
    pub interaction: TerminalProfileInteraction,
}

impl<'de> Deserialize<'de> for TerminalProfile {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let wire = TerminalProfileWire::deserialize(deserializer)?;

        let launch = wire.launch.unwrap_or_else(|| TerminalProfileLaunch {
            program: wire.shell.unwrap_or_default(),
            args: wire.args.unwrap_or_default(),
            env: wire.env.unwrap_or_default(),
            cwd: wire.cwd,
        });
        let terminal = wire.terminal.unwrap_or_else(|| TerminalProfileTerminal {
            emulation: wire.terminal_emulation.unwrap_or_default(),
            ..TerminalProfileTerminal::default()
        });

        Ok(Self {
            id: wire.id,
            name: wire.name,
            launch,
            terminal,
            shell_integration: wire.shell_integration.unwrap_or_default(),
            appearance: wire.appearance.unwrap_or_default(),
            interaction: wire.interaction.unwrap_or_default(),
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
struct TerminalProfileWire {
    id: String,
    name: String,
    #[serde(default)]
    launch: Option<TerminalProfileLaunch>,
    #[serde(default)]
    terminal: Option<TerminalProfileTerminal>,
    #[serde(default)]
    #[serde(rename = "shellIntegration", alias = "shell_integration")]
    shell_integration: Option<TerminalShellIntegration>,
    #[serde(default)]
    appearance: Option<TerminalProfileAppearance>,
    #[serde(default)]
    interaction: Option<TerminalProfileInteraction>,
    #[serde(default)]
    shell: Option<String>,
    #[serde(default)]
    args: Option<Vec<String>>,
    #[serde(default)]
    env: Option<BTreeMap<String, String>>,
    #[serde(default)]
    cwd: Option<String>,
    #[serde(rename = "terminalEmulation", default)]
    terminal_emulation: Option<TerminalEmulation>,
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
pub struct TerminalSelectionRequest {
    pub start_row: usize,
    pub start_col: usize,
    pub end_row: usize,
    pub end_col: usize,
    #[serde(default)]
    pub block: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalDirtyRange {
    pub start: usize,
    pub end: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalHyperlinkRange {
    pub row: usize,
    pub start_col: usize,
    pub end_col: usize,
    pub uri: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalSearchMatch {
    pub row: usize,
    pub start_col: usize,
    pub end_col: usize,
    pub text: String,
    pub scrollback_offset: usize,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TerminalFrameModes {
    #[serde(default)]
    pub alternate_screen: bool,
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
    pub alternate_scroll: bool,
    #[serde(default)]
    pub char_protected: bool,
    #[serde(default = "default_mouse_mode")]
    pub mouse_mode: String,
    #[serde(default = "default_mouse_encoding")]
    pub mouse_encoding: String,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TerminalFrameKind {
    #[default]
    Snapshot,
    Delta,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalFrameDiff {
    #[serde(default)]
    pub frame_kind: TerminalFrameKind,
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
    pub viewport_start_row: usize,
    #[serde(default)]
    pub viewport_row_shift: i32,
    #[serde(default)]
    pub modes: TerminalFrameModes,
    #[serde(default)]
    pub window_title: Option<String>,
    #[serde(default)]
    pub window_icon_name: Option<String>,
    #[serde(default)]
    pub hyperlinks: Vec<TerminalHyperlinkRange>,
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

fn default_scrollback_lines() -> usize {
    8_000
}

fn default_terminal_primary_font_family() -> String {
    "JetBrainsMono Nerd Font Mono".to_string()
}

fn default_terminal_font_fallback() -> Vec<String> {
    vec![
        "Menlo".to_string(),
        "JetBrainsMono Nerd Font".to_string(),
        "SF Mono".to_string(),
        "Monaco".to_string(),
        "Apple Symbols".to_string(),
    ]
}

fn default_terminal_font_size() -> f64 {
    14.0
}

fn default_terminal_line_height() -> f64 {
    1.6
}

fn default_cursor_blink() -> bool {
    true
}
