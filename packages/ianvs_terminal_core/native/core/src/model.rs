use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

pub const TERMINAL_FRAME_SCHEMA_VERSION: &str = "terminal-frame-diff-v1";
pub const DEFAULT_SCROLLBACK_LINES: usize = 8_000;
pub const MAX_SCROLLBACK_LINES: usize = 100_000;

pub fn normalize_scrollback_lines(value: usize) -> usize {
    value.clamp(1, MAX_SCROLLBACK_LINES)
}

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

impl TerminalCursorShape {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Block => "block",
            Self::Underline => "underline",
            Self::Beam => "beam",
        }
    }
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

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TerminalConnectionType {
    #[default]
    Local,
    Ssh,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TerminalSshAuthMethod {
    #[default]
    Auto,
    Password,
    PublicKey,
    KeyboardInteractive,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TerminalSshHostKeyPolicy {
    #[default]
    Strict,
    AcceptNew,
    Insecure,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TerminalSshPortForwardKind {
    #[default]
    Local,
    Remote,
    Dynamic,
}

fn default_ssh_forward_bind_host() -> String {
    "127.0.0.1".to_string()
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TerminalSshPortForward {
    #[serde(rename = "type", default)]
    pub kind: TerminalSshPortForwardKind,
    #[serde(rename = "bindHost", default = "default_ssh_forward_bind_host")]
    pub bind_host: String,
    #[serde(rename = "bindPort", default)]
    pub bind_port: u16,
    #[serde(rename = "targetHost", default)]
    pub target_host: String,
    #[serde(rename = "targetPort", default)]
    pub target_port: u16,
}

fn default_ssh_port() -> u16 {
    22
}

fn default_ssh_connect_timeout_seconds() -> u64 {
    10
}

fn default_ssh_keepalive_count_max() -> usize {
    3
}

/// Authentication and host-verification settings for one ProxyJump hop.
///
/// Jump hosts are independent trust boundaries. In particular, credentials
/// from the destination connection are never inherited by this structure.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalSshJumpProfile {
    #[serde(default)]
    pub host: String,
    #[serde(default)]
    pub user: String,
    #[serde(default)]
    pub port: u16,
    #[serde(default)]
    pub auth: TerminalSshAuthMethod,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub password: Option<String>,
    #[serde(rename = "privateKeys", default)]
    pub private_keys: Vec<String>,
    #[serde(
        rename = "privateKeyPassphrase",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub private_key_passphrase: Option<String>,
    #[serde(rename = "hostKeyPolicy", default)]
    pub host_key_policy: TerminalSshHostKeyPolicy,
    #[serde(
        rename = "knownHostsFile",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub known_hosts_file: Option<String>,
    #[serde(
        rename = "connectTimeoutSeconds",
        default = "default_ssh_connect_timeout_seconds"
    )]
    pub connect_timeout_seconds: u64,
    #[serde(rename = "keepaliveSeconds", default)]
    pub keepalive_seconds: u64,
    #[serde(
        rename = "keepaliveCountMax",
        default = "default_ssh_keepalive_count_max"
    )]
    pub keepalive_count_max: usize,
}

impl Default for TerminalSshJumpProfile {
    fn default() -> Self {
        Self {
            host: String::new(),
            user: String::new(),
            port: 0,
            auth: TerminalSshAuthMethod::Auto,
            password: None,
            private_keys: Vec::new(),
            private_key_passphrase: None,
            host_key_policy: TerminalSshHostKeyPolicy::Strict,
            known_hosts_file: None,
            connect_timeout_seconds: default_ssh_connect_timeout_seconds(),
            keepalive_seconds: 0,
            keepalive_count_max: default_ssh_keepalive_count_max(),
        }
    }
}

/// Product-neutral connection settings. These defaults are internal model
/// conveniences only; SessionConfig v1 validates its complete exact wire shape
/// before deserializing this model.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalProfileConnection {
    #[serde(rename = "type", default)]
    pub connection_type: TerminalConnectionType,
    #[serde(default)]
    pub host: String,
    #[serde(default)]
    pub user: String,
    #[serde(default = "default_ssh_port")]
    pub port: u16,
    #[serde(default)]
    pub auth: TerminalSshAuthMethod,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub password: Option<String>,
    #[serde(rename = "privateKeys", default)]
    pub private_keys: Vec<String>,
    #[serde(
        rename = "privateKeyPassphrase",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub private_key_passphrase: Option<String>,
    #[serde(rename = "hostKeyPolicy", default)]
    pub host_key_policy: TerminalSshHostKeyPolicy,
    #[serde(
        rename = "knownHostsFile",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub known_hosts_file: Option<String>,
    #[serde(
        rename = "connectTimeoutSeconds",
        default = "default_ssh_connect_timeout_seconds"
    )]
    pub connect_timeout_seconds: u64,
    #[serde(rename = "keepaliveSeconds", default)]
    pub keepalive_seconds: u64,
    #[serde(
        rename = "keepaliveCountMax",
        default = "default_ssh_keepalive_count_max"
    )]
    pub keepalive_count_max: usize,
    #[serde(
        rename = "proxyCommand",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub proxy_command: Option<String>,
    #[serde(rename = "proxyJump", default, skip_serializing_if = "Option::is_none")]
    pub proxy_jump: Option<String>,
    #[serde(rename = "proxyJumpProfiles", default)]
    pub proxy_jump_profiles: Vec<TerminalSshJumpProfile>,
    #[serde(rename = "portForwards", default)]
    pub port_forwards: Vec<TerminalSshPortForward>,
    #[serde(rename = "agentForwarding", default)]
    pub agent_forwarding: bool,
    #[serde(
        rename = "agentSocket",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub agent_socket: Option<String>,
    #[serde(rename = "x11Forwarding", default)]
    pub x11_forwarding: bool,
    #[serde(
        rename = "x11TargetHost",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub x11_target_host: Option<String>,
    #[serde(rename = "x11TargetPort", default)]
    pub x11_target_port: u16,
    #[serde(rename = "x11AuthProtocol", default = "default_x11_auth_protocol")]
    pub x11_auth_protocol: String,
    #[serde(
        rename = "x11AuthCookie",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub x11_auth_cookie: Option<String>,
    #[serde(rename = "x11ScreenNumber", default)]
    pub x11_screen_number: u32,
}

fn default_x11_auth_protocol() -> String {
    "MIT-MAGIC-COOKIE-1".to_string()
}

impl Default for TerminalProfileConnection {
    fn default() -> Self {
        Self {
            connection_type: TerminalConnectionType::Local,
            host: String::new(),
            user: String::new(),
            port: default_ssh_port(),
            auth: TerminalSshAuthMethod::Auto,
            password: None,
            private_keys: Vec::new(),
            private_key_passphrase: None,
            host_key_policy: TerminalSshHostKeyPolicy::Strict,
            known_hosts_file: None,
            connect_timeout_seconds: default_ssh_connect_timeout_seconds(),
            keepalive_seconds: 0,
            keepalive_count_max: default_ssh_keepalive_count_max(),
            proxy_command: None,
            proxy_jump: None,
            proxy_jump_profiles: Vec::new(),
            port_forwards: Vec::new(),
            agent_forwarding: false,
            agent_socket: None,
            x11_forwarding: false,
            x11_target_host: None,
            x11_target_port: 0,
            x11_auth_protocol: default_x11_auth_protocol(),
            x11_auth_cookie: None,
            x11_screen_number: 0,
        }
    }
}

fn default_shell_integration_enabled() -> bool {
    true
}

fn default_graphics_enabled() -> bool {
    true
}

fn default_graphics_advertise() -> String {
    "kitty".to_string()
}

fn default_graphics_max_image_bytes() -> usize {
    100 * 1024 * 1024
}

fn default_graphics_max_total_bytes() -> usize {
    256 * 1024 * 1024
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
pub struct TerminalGraphicsConfig {
    #[serde(default = "default_graphics_enabled")]
    pub enabled: bool,
    #[serde(default = "default_graphics_advertise")]
    pub advertise: String,
    #[serde(rename = "maxImageBytes", default = "default_graphics_max_image_bytes")]
    pub max_image_bytes: usize,
    #[serde(rename = "maxTotalBytes", default = "default_graphics_max_total_bytes")]
    pub max_total_bytes: usize,
}

impl Default for TerminalGraphicsConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            advertise: default_graphics_advertise(),
            max_image_bytes: default_graphics_max_image_bytes(),
            max_total_bytes: default_graphics_max_total_bytes(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalProfileTerminal {
    #[serde(default)]
    pub emulation: TerminalEmulation,
    #[serde(rename = "scrollbackLines", default = "default_scrollback_lines")]
    pub scrollback_lines: usize,
    #[serde(default)]
    pub graphics: TerminalGraphicsConfig,
    /// Enable bounded OSC 72 parsing only when the embedding product has a
    /// system drag/drop bridge installed. Defaults off to avoid false support.
    #[serde(rename = "dragDropEnabled", default)]
    pub drag_drop_enabled: bool,
}

impl Default for TerminalProfileTerminal {
    fn default() -> Self {
        Self {
            emulation: TerminalEmulation::Xterm256,
            scrollback_lines: default_scrollback_lines(),
            graphics: TerminalGraphicsConfig::default(),
            drag_drop_enabled: false,
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
pub struct TerminalProfileSpecialColors {
    #[serde(default)]
    pub foreground: Option<String>,
    #[serde(default)]
    pub background: Option<String>,
    #[serde(default)]
    pub cursor: Option<String>,
    #[serde(default)]
    pub selection: Option<String>,
    #[serde(default)]
    pub tab: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TerminalProfileAnsiColors {
    #[serde(default)]
    pub black: Option<String>,
    #[serde(default)]
    pub red: Option<String>,
    #[serde(default)]
    pub green: Option<String>,
    #[serde(default)]
    pub yellow: Option<String>,
    #[serde(default)]
    pub blue: Option<String>,
    #[serde(default)]
    pub magenta: Option<String>,
    #[serde(default)]
    pub cyan: Option<String>,
    #[serde(default)]
    pub white: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TerminalProfileColors {
    #[serde(default)]
    pub special: TerminalProfileSpecialColors,
    #[serde(default)]
    pub normal: TerminalProfileAnsiColors,
    #[serde(default)]
    pub bright: TerminalProfileAnsiColors,
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
    pub connection: TerminalProfileConnection,
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
        let mut terminal = wire.terminal.unwrap_or_else(|| TerminalProfileTerminal {
            emulation: wire.terminal_emulation.unwrap_or_default(),
            ..TerminalProfileTerminal::default()
        });
        terminal.scrollback_lines = normalize_scrollback_lines(terminal.scrollback_lines);

        Ok(Self {
            id: wire.id,
            name: wire.name,
            launch,
            connection: wire.connection.unwrap_or_default(),
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
    connection: Option<TerminalProfileConnection>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub underline_color: Option<String>,
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
    /// Retained terminal row that supplies this display row.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_row: Option<usize>,
    /// Inclusive retained terminal row represented by the end of this display row.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_end_row: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalBlock {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub block_type: Option<String>,
    /// First viewport-relative display row occupied by the block.
    pub start_row: usize,
    /// Last viewport-relative display row occupied by the block.
    pub end_row: usize,
    /// Inclusive retained source range, independent of folding.
    pub source_start_row: usize,
    pub source_end_row: usize,
    pub folded: bool,
    /// Whether OSC 1337 requested terminal-local text-document rendering.
    #[serde(default)]
    pub rendered: bool,
    #[serde(default)]
    pub hidden_rows: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalInlineButton {
    pub id: u64,
    /// `copy` or `custom`.
    pub kind: String,
    pub row: usize,
    pub col: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub icon: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub block_id: Option<String>,
    #[serde(default)]
    pub valid: bool,
    pub width_cells: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalCursor {
    pub row: usize,
    pub col: usize,
    pub visible: bool,
    #[serde(default)]
    pub highlight_line: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub shape: Option<TerminalCursorShape>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub blink: Option<bool>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub protocol_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalSizedTextPlacement {
    pub text: String,
    pub row: usize,
    pub col: usize,
    pub width_cells: usize,
    pub height_cells: usize,
    #[serde(default)]
    pub source_row_offset_cells: usize,
    pub visible_height_cells: usize,
    pub scale: u8,
    #[serde(default)]
    pub subscale_n: u8,
    #[serde(default)]
    pub subscale_d: u8,
    #[serde(default)]
    pub vertical_align: u8,
    #[serde(default)]
    pub horizontal_align: u8,
    #[serde(default)]
    pub natural_width: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub foreground: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub background: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub underline_color: Option<String>,
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
pub struct TerminalGraphicPlacement {
    #[serde(default)]
    pub render_id: u64,
    pub placement_id: u64,
    pub asset_id: u64,
    pub asset_version: u64,
    pub protocol: String,
    pub row: usize,
    pub col: usize,
    pub width_px: usize,
    pub height_px: usize,
    pub width_cells: usize,
    pub height_cells: usize,
    #[serde(default)]
    pub source_x_offset_px: usize,
    #[serde(default)]
    pub visible_width_px: usize,
    #[serde(default)]
    pub source_y_offset_px: usize,
    #[serde(default)]
    pub visible_height_px: usize,
    #[serde(default)]
    pub z_index: i32,
    #[serde(default)]
    pub x_offset_px: u32,
    #[serde(default)]
    pub y_offset_px: u32,
    #[serde(default = "default_preserve_aspect_ratio")]
    pub preserve_aspect_ratio: bool,
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
    pub mime_paste: bool,
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
    #[serde(default)]
    pub kitty_keyboard_flags: u16,
    #[serde(default)]
    pub synchronized_output: bool,
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
    #[serde(default = "default_terminal_frame_schema_version")]
    pub frame_schema_version: String,
    #[serde(default)]
    pub frame_kind: TerminalFrameKind,
    pub rows: Vec<TerminalRow>,
    pub cursor: TerminalCursor,
    #[serde(default, skip_serializing_if = "Option::is_none")]
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
    pub global_bottom_row: u64,
    #[serde(default)]
    pub viewport_start_row: usize,
    #[serde(default)]
    pub viewport_row_shift: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_foreground: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_background: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cursor_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cursor_guide_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selection_background: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selection_foreground: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub link_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cursor_text_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tab_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pointer_shape: Option<String>,
    #[serde(default)]
    pub modes: TerminalFrameModes,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub window_title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub window_icon_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub font_family: Option<String>,
    #[serde(default)]
    pub hyperlinks: Vec<TerminalHyperlinkRange>,
    #[serde(default)]
    pub sized_text: Vec<TerminalSizedTextPlacement>,
    #[serde(default)]
    pub graphics: Vec<TerminalGraphicPlacement>,
    #[serde(default)]
    pub blocks: Vec<TerminalBlock>,
    #[serde(default)]
    pub inline_buttons: Vec<TerminalInlineButton>,
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

fn default_terminal_frame_schema_version() -> String {
    TERMINAL_FRAME_SCHEMA_VERSION.to_string()
}

fn default_mouse_encoding() -> String {
    "default".to_string()
}

fn default_preserve_aspect_ratio() -> bool {
    true
}

fn default_scrollback_lines() -> usize {
    DEFAULT_SCROLLBACK_LINES
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
