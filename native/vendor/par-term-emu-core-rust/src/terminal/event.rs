//! Terminal events and notifications
//!
//! This module defines the various events that can be emitted by the terminal
//! to notify observers of state changes, user interactions, or protocol-specific actions.

use crate::terminal::context::TerminalContextEvent;
use crate::terminal::drag_drop::DragDropCommand;
use crate::terminal::file_transfer::TransferDirection;
use crate::terminal::progress::{ProgressBarAction, ProgressState};
use crate::terminal::trigger::TriggerMatch;
use crate::zone::ZoneType;

/// iTerm2 OSC 1337 `RequestAttention` action.
///
/// These values are deliberately closed over the four spellings documented
/// by iTerm2. They describe an untrusted request and never grant host-action
/// authority by themselves.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ItermAttentionAction {
    Yes,
    Once,
    No,
    Fireworks,
}

impl ItermAttentionAction {
    /// Stable wire/debug name for the product bridge.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Yes => "yes",
            Self::Once => "once",
            Self::No => "no",
            Self::Fireworks => "fireworks",
        }
    }
}

/// Protocol that produced a normalized shell-integration event.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellIntegrationSource {
    /// FinalTerm/iTerm2 OSC 133 marker.
    Osc133,
    /// VS Code OSC 633 marker.
    Osc633,
    /// iTerm2 OSC 1337 shell metadata or explicit mark.
    Osc1337,
}

impl ShellIntegrationSource {
    /// Stable wire/debug name for the protocol source.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Osc133 => "osc133",
            Self::Osc633 => "osc633",
            Self::Osc1337 => "osc1337",
        }
    }
}

/// Protocol or API that produced a working-directory change.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CwdChangeSource {
    /// Standard OSC 7 `file://` working-directory report.
    Osc7,
    /// Windows Terminal OSC 9;9 working-directory report.
    Osc9_9,
    /// VS Code OSC 633 `P;Cwd=...` property.
    Osc633,
    /// iTerm2 OSC 1337 shell metadata.
    Osc1337,
    /// Direct host/API update rather than a parsed escape sequence.
    Manual,
}

impl CwdChangeSource {
    /// Stable wire/debug name for the protocol source.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Osc7 => "osc7",
            Self::Osc9_9 => "osc9;9",
            Self::Osc633 => "osc633",
            Self::Osc1337 => "osc1337",
            Self::Manual => "manual",
        }
    }
}

/// Bell event type
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BellEvent {
    /// Standard visual bell
    VisualBell,
    /// Warning bell with volume (0-8, where 0 is off)
    WarningBell(u8),
    /// Margin bell with volume (0-8, where 0 is off)
    MarginBell(u8),
}

/// Current working directory change information
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CwdChange {
    /// Protocol or API that produced this change.
    pub source: CwdChangeSource,
    /// Previous working directory
    pub old_cwd: Option<String>,
    /// New working directory
    pub new_cwd: String,
    /// Hostname associated with new working directory (if remote)
    pub hostname: Option<String>,
    /// Username associated with new working directory (if provided)
    pub username: Option<String>,
    /// Timestamp of change (unix millis)
    pub timestamp: u64,
}

/// Terminal change event
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TabStatusUpdate {
    /// Whether the OSC payload mentioned `indicator`.
    pub indicator_present: bool,
    /// Canonical `#rrggbb` color, or `None` when the field was cleared.
    pub indicator: Option<String>,
    /// Whether the OSC payload mentioned `status`.
    pub status_present: bool,
    /// Sanitized status text, or `None` when the field was cleared.
    pub status: Option<String>,
    /// Whether the OSC payload mentioned `status-color`.
    pub status_color_present: bool,
    /// Canonical `#rrggbb` color, or `None` when the field was cleared.
    pub status_color: Option<String>,
}

impl TabStatusUpdate {
    pub(crate) fn is_empty(&self) -> bool {
        !self.indicator_present && !self.status_present && !self.status_color_present
    }

    fn retained_bytes(&self) -> usize {
        self.indicator.as_ref().map_or(0, String::len)
            + self.status.as_ref().map_or(0, String::len)
            + self.status_color.as_ref().map_or(0, String::len)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum TerminalEvent {
    /// Bell event occurred
    BellRang(BellEvent),
    /// Terminal title changed
    TitleChanged(String),
    /// Terminal was resized
    SizeChanged(usize, usize),
    /// A terminal mode changed
    ModeChanged(String, bool),
    /// Graphics added at row
    GraphicsAdded(usize),
    /// Hyperlink added with URL, position, and optional internal ID
    HyperlinkAdded {
        /// The URL of the hyperlink
        url: String,
        /// Row where hyperlink starts
        row: usize,
        /// Column where hyperlink starts
        col: usize,
        /// Internal hyperlink ID
        id: Option<u32>,
    },
    /// Dirty region (first_row, last_row)
    DirtyRegion(usize, usize),
    /// Current working directory changed (from OSC 7 or manual record)
    CwdChanged(CwdChange),
    /// A trigger pattern matched terminal output
    TriggerMatched(TriggerMatch),
    /// A user variable changed (from OSC 1337 SetUserVar)
    UserVarChanged {
        /// Variable name
        name: String,
        /// New value (base64-decoded)
        value: String,
        /// Previous value if the variable already existed
        old_value: Option<String>,
    },
    /// A named progress bar was created, updated, or removed (from OSC 934)
    ProgressBarChanged {
        /// The action that occurred
        action: ProgressBarAction,
        /// Progress bar ID
        id: String,
        /// Progress bar state (only for Set action)
        state: Option<ProgressState>,
        /// Progress percentage 0-100 (only for Set action)
        percent: Option<u8>,
        /// Optional label (only for Set action)
        label: Option<String>,
    },
    /// Badge text changed (from OSC 1337 SetBadgeFormat)
    BadgeChanged(Option<String>),
    /// Incremental tab-status update from iTerm2 OSC 21337.
    TabStatusChanged(TabStatusUpdate),
    /// UAPI OSC 3008 hierarchical terminal context changed.
    TerminalContextChanged(Box<TerminalContextEvent>),
    /// A bounded Kitty OSC 72 command requiring product-side drag/drop policy.
    DragDropCommand(Box<DragDropCommand>),
    /// Shell integration event (FinalTerm sequences)
    ShellIntegrationEvent {
        /// Protocol source normalized into this event.
        source: ShellIntegrationSource,
        /// Event type: "prompt_start", "command_start", "command_executed", "command_finished"
        event_type: String,
        /// The command text (for command_start)
        command: Option<String>,
        /// Exit code (for command_finished)
        exit_code: Option<i32>,
        /// Timestamp (Unix epoch milliseconds)
        timestamp: Option<u64>,
        /// Global cursor line (`total_lines_scrolled + cursor_row`) when the marker was emitted.
        cursor_line: Option<usize>,
        /// OSC 133 semantic prompt kind (`initial`, `secondary`, `continuation`, `right`).
        prompt_kind: Option<String>,
        /// Opaque active shell-integration lifecycle identifier.
        aid: Option<String>,
        /// Opaque suspended parent lifecycle identifier.
        parent_aid: Option<String>,
        /// Inner lifecycles implicitly closed by an `aid`-targeted `D`.
        implicit_closed_count: usize,
        /// Whether the prompt marker requires fresh-line semantics (`A`/`N` vs `P`).
        fresh_line: Option<bool>,
    },
    /// iTerm2 shell integration script version metadata.
    ShellIntegrationVersion {
        /// Bounded version reported by the shell integration script.
        version: String,
        /// Optional bounded shell name (for example `zsh`).
        shell: Option<String>,
    },
    /// iTerm2 requested the current rendered character-cell size.
    CellSizeReportRequested,
    /// iTerm2 requested that the product clear its session-scoped captured
    /// output collection.
    ///
    /// This is intentionally an event rather than a terminal-grid mutation:
    /// embedders own captured-output presentation and must scope the clear to
    /// the originating session.
    ItermClearCapturedOutputRequested,
    /// iTerm2 requested the value of a terminal/session variable.
    ///
    /// This event carries the decoded variable name only. Embedders must
    /// resolve it from session-owned state, apply a per-variable disclosure
    /// policy, and send an OSC 1337 ReportVariable reply even when the value
    /// is denied or undefined.
    ItermReportVariableRequested {
        /// Base64-decoded UTF-8 variable name from the request.
        name: String,
    },
    /// iTerm2 requested that the host open a bounded URL.
    ///
    /// This event is an untrusted request only. Embedders must apply their
    /// own active-session policy and obtain explicit user authorization
    /// before performing any external side effect.
    ItermOpenUrlRequested {
        /// Original validated URL decoded from the OSC Base64 payload.
        url: String,
    },
    /// iTerm2 requested bounded user-attention feedback.
    ///
    /// This event is an untrusted request only. Embedders must apply a
    /// persisted product policy and anti-spam controls before asking the host
    /// operating system to perform an attention effect.
    ItermAttentionRequested {
        /// One of the four exact actions documented by iTerm2.
        action: ItermAttentionAction,
    },
    /// iTerm2 attached a bounded annotation to a terminal cell range.
    ItermAnnotation {
        /// Sanitized note text shown in the product annotation UI.
        message: String,
        /// Whether AddAnnotation requested immediate presentation.
        visible: bool,
        /// Global absolute start row at the time the OSC was received.
        start_abs_row: usize,
        /// Inclusive start column.
        start_col: usize,
        /// Global absolute row containing the exclusive end coordinate.
        end_abs_row: usize,
        /// Exclusive end column on `end_abs_row`.
        end_col: usize,
    },
    /// A zone was opened (prompt, command, or output block started)
    ZoneOpened {
        /// Unique zone identifier
        zone_id: usize,
        /// Type of zone
        zone_type: ZoneType,
        /// Global absolute row where the zone starts
        abs_row_start: usize,
    },
    /// A zone was closed (prompt, command, or output block ended)
    ZoneClosed {
        /// Unique zone identifier
        zone_id: usize,
        /// Type of zone
        zone_type: ZoneType,
        /// Global absolute row where the zone starts
        abs_row_start: usize,
        /// Global absolute row where the zone ends
        abs_row_end: usize,
        /// Exit code (for output zones only)
        exit_code: Option<i32>,
    },
    /// A zone was evicted from scrollback
    ZoneScrolledOut {
        /// Unique zone identifier
        zone_id: usize,
        /// Type of zone that was evicted
        zone_type: ZoneType,
    },
    /// An environment variable changed (CWD, hostname, username)
    EnvironmentChanged {
        /// The key that changed ("cwd", "hostname", "username")
        key: String,
        /// The new value
        value: String,
        /// The previous value (if any)
        old_value: Option<String>,
    },
    /// Remote host transition detected (hostname changed)
    RemoteHostTransition {
        /// New hostname
        hostname: String,
        /// New username (if known)
        username: Option<String>,
        /// Previous hostname (if any)
        old_hostname: Option<String>,
        /// Previous username (if any)
        old_username: Option<String>,
    },
    /// Sub-shell detected (shell nesting depth changed)
    SubShellDetected {
        /// Current shell nesting depth
        depth: usize,
        /// Shell type if known (e.g., "bash", "zsh")
        shell_type: Option<String>,
    },
    /// A file transfer has started (download or upload)
    FileTransferStarted {
        /// Unique transfer identifier
        id: u64,
        /// Transfer direction (download or upload)
        direction: TransferDirection,
        /// Name of the file being transferred (if known)
        filename: Option<String>,
        /// Total expected size in bytes (if known)
        total_bytes: Option<usize>,
    },
    /// Progress update for an active file transfer
    FileTransferProgress {
        /// Unique transfer identifier
        id: u64,
        /// Number of bytes transferred so far
        bytes_transferred: usize,
        /// Total expected size in bytes (if known)
        total_bytes: Option<usize>,
    },
    /// A file transfer completed successfully
    FileTransferCompleted {
        /// Unique transfer identifier
        id: u64,
        /// Name of the file that was transferred (if known)
        filename: Option<String>,
        /// Total size of the transferred data in bytes
        size: usize,
    },
    /// A file transfer failed
    FileTransferFailed {
        /// Unique transfer identifier
        id: u64,
        /// Reason for the failure
        reason: String,
    },
    /// An upload was requested by the remote application
    UploadRequested {
        /// Upload format (e.g., "base64")
        format: String,
    },
    /// The screen was cleared (ESC[2J or ESC[3J).
    ///
    /// `include_scrollback` is true when ESC[3J (erase display + scrollback)
    /// was received.  Consumers such as par-term use this to invalidate
    /// scrollback zone/mark metadata so the scrollbar is consistent with the
    /// visible terminal state.
    ScreenCleared {
        /// Whether the scrollback buffer was also cleared (ESC[3J vs ESC[2J).
        include_scrollback: bool,
    },
    /// The terminal was reset to its initial state by RIS (`ESC c`).
    ///
    /// This is intentionally distinct from [`TerminalEvent::ScreenCleared`]:
    /// ED 2/3 clears screen content, while RIS also resets protocol semantic
    /// state such as shell metadata, badges, progress, and notifications.
    TerminalReset,
}

impl TerminalEvent {
    /// Get the kind of this event
    pub fn kind(&self) -> TerminalEventKind {
        match self {
            TerminalEvent::BellRang(_) => TerminalEventKind::BellRang,
            TerminalEvent::TitleChanged(_) => TerminalEventKind::TitleChanged,
            TerminalEvent::SizeChanged(_, _) => TerminalEventKind::SizeChanged,
            TerminalEvent::ModeChanged(_, _) => TerminalEventKind::ModeChanged,
            TerminalEvent::GraphicsAdded(_) => TerminalEventKind::GraphicsAdded,
            TerminalEvent::HyperlinkAdded { .. } => TerminalEventKind::HyperlinkAdded,
            TerminalEvent::DirtyRegion(_, _) => TerminalEventKind::DirtyRegion,
            TerminalEvent::CwdChanged(_) => TerminalEventKind::CwdChanged,
            TerminalEvent::TriggerMatched(_) => TerminalEventKind::TriggerMatched,
            TerminalEvent::UserVarChanged { .. } => TerminalEventKind::UserVarChanged,
            TerminalEvent::ProgressBarChanged { .. } => TerminalEventKind::ProgressBarChanged,
            TerminalEvent::BadgeChanged(_) => TerminalEventKind::BadgeChanged,
            TerminalEvent::TabStatusChanged(_) => TerminalEventKind::TabStatusChanged,
            TerminalEvent::TerminalContextChanged(_) => TerminalEventKind::TerminalContextChanged,
            TerminalEvent::DragDropCommand(_) => TerminalEventKind::DragDropCommand,
            TerminalEvent::ShellIntegrationEvent { .. } => TerminalEventKind::ShellIntegrationEvent,
            TerminalEvent::ShellIntegrationVersion { .. } => {
                TerminalEventKind::ShellIntegrationVersion
            }
            TerminalEvent::CellSizeReportRequested => TerminalEventKind::CellSizeReportRequested,
            TerminalEvent::ItermClearCapturedOutputRequested => {
                TerminalEventKind::ItermClearCapturedOutputRequested
            }
            TerminalEvent::ItermReportVariableRequested { .. } => {
                TerminalEventKind::ItermReportVariableRequested
            }
            TerminalEvent::ItermOpenUrlRequested { .. } => TerminalEventKind::ItermOpenUrlRequested,
            TerminalEvent::ItermAttentionRequested { .. } => {
                TerminalEventKind::ItermAttentionRequested
            }
            TerminalEvent::ItermAnnotation { .. } => TerminalEventKind::ItermAnnotation,
            TerminalEvent::ZoneOpened { .. } => TerminalEventKind::ZoneOpened,
            TerminalEvent::ZoneClosed { .. } => TerminalEventKind::ZoneClosed,
            TerminalEvent::ZoneScrolledOut { .. } => TerminalEventKind::ZoneScrolledOut,
            TerminalEvent::EnvironmentChanged { .. } => TerminalEventKind::EnvironmentChanged,
            TerminalEvent::RemoteHostTransition { .. } => TerminalEventKind::RemoteHostTransition,
            TerminalEvent::SubShellDetected { .. } => TerminalEventKind::SubShellDetected,
            TerminalEvent::FileTransferStarted { .. } => TerminalEventKind::FileTransferStarted,
            TerminalEvent::FileTransferProgress { .. } => TerminalEventKind::FileTransferProgress,
            TerminalEvent::FileTransferCompleted { .. } => TerminalEventKind::FileTransferCompleted,
            TerminalEvent::FileTransferFailed { .. } => TerminalEventKind::FileTransferFailed,
            TerminalEvent::UploadRequested { .. } => TerminalEventKind::UploadRequested,
            TerminalEvent::ScreenCleared { .. } => TerminalEventKind::ScreenCleared,
            TerminalEvent::TerminalReset => TerminalEventKind::TerminalReset,
        }
    }

    /// Conservative retained-byte estimate used by the bounded event queue.
    ///
    /// This intentionally inspects lengths only. It must never format or log
    /// attacker-controlled event text while enforcing a memory budget.
    pub(crate) fn retained_size_bytes(&self) -> usize {
        const EVENT_BASE_BYTES: usize = 128;
        let option_len = |value: &Option<String>| value.as_ref().map_or(0, String::len);
        let string_bytes = match self {
            Self::TitleChanged(title) | Self::ModeChanged(title, _) => title.len(),
            Self::HyperlinkAdded { url, .. } => url.len(),
            Self::CwdChanged(change) => option_len(&change.old_cwd)
                .saturating_add(change.new_cwd.len())
                .saturating_add(option_len(&change.hostname))
                .saturating_add(option_len(&change.username)),
            Self::TriggerMatched(trigger_match) => trigger_match
                .captures
                .iter()
                .fold(trigger_match.text.len(), |total, capture| {
                    total.saturating_add(capture.len())
                }),
            Self::UserVarChanged {
                name,
                value,
                old_value,
            } => name
                .len()
                .saturating_add(value.len())
                .saturating_add(option_len(old_value)),
            Self::ProgressBarChanged { id, label, .. } => {
                id.len().saturating_add(option_len(label))
            }
            Self::BadgeChanged(badge) => option_len(badge),
            Self::TabStatusChanged(update) => update.retained_bytes(),
            Self::TerminalContextChanged(event) => event.retained_bytes(),
            Self::DragDropCommand(command) => command.retained_bytes(),
            Self::ShellIntegrationEvent {
                event_type,
                command,
                prompt_kind,
                aid,
                parent_aid,
                ..
            } => event_type
                .len()
                .saturating_add(option_len(command))
                .saturating_add(option_len(prompt_kind))
                .saturating_add(option_len(aid))
                .saturating_add(option_len(parent_aid)),
            Self::ShellIntegrationVersion { version, shell } => {
                version.len().saturating_add(option_len(shell))
            }
            Self::ItermOpenUrlRequested { url } => url.len(),
            Self::ItermReportVariableRequested { name } => name.len(),
            Self::ItermAnnotation { message, .. } => message.len(),
            Self::EnvironmentChanged {
                key,
                value,
                old_value,
            } => key
                .len()
                .saturating_add(value.len())
                .saturating_add(option_len(old_value)),
            Self::RemoteHostTransition {
                hostname,
                username,
                old_hostname,
                old_username,
            } => hostname
                .len()
                .saturating_add(option_len(username))
                .saturating_add(option_len(old_hostname))
                .saturating_add(option_len(old_username)),
            Self::SubShellDetected { shell_type, .. } => option_len(shell_type),
            Self::FileTransferStarted { filename, .. }
            | Self::FileTransferCompleted { filename, .. } => option_len(filename),
            Self::FileTransferFailed { reason, .. } => reason.len(),
            Self::UploadRequested { format } => format.len(),
            Self::BellRang(_)
            | Self::SizeChanged(_, _)
            | Self::GraphicsAdded(_)
            | Self::DirtyRegion(_, _)
            | Self::ZoneOpened { .. }
            | Self::ZoneClosed { .. }
            | Self::ZoneScrolledOut { .. }
            | Self::FileTransferProgress { .. }
            | Self::CellSizeReportRequested
            | Self::ItermClearCapturedOutputRequested
            | Self::ItermAttentionRequested { .. }
            | Self::ScreenCleared { .. }
            | Self::TerminalReset => 0,
        };
        EVENT_BASE_BYTES.saturating_add(string_bytes)
    }
}

/// Kind of terminal event for subscription filters
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum TerminalEventKind {
    BellRang,
    TitleChanged,
    SizeChanged,
    ModeChanged,
    GraphicsAdded,
    HyperlinkAdded,
    DirtyRegion,
    CwdChanged,
    TriggerMatched,
    UserVarChanged,
    ProgressBarChanged,
    BadgeChanged,
    TabStatusChanged,
    TerminalContextChanged,
    DragDropCommand,
    ShellIntegrationEvent,
    ShellIntegrationVersion,
    CellSizeReportRequested,
    ItermClearCapturedOutputRequested,
    ItermReportVariableRequested,
    ItermOpenUrlRequested,
    ItermAttentionRequested,
    ItermAnnotation,
    ZoneOpened,
    ZoneClosed,
    ZoneScrolledOut,
    EnvironmentChanged,
    RemoteHostTransition,
    SubShellDetected,
    FileTransferStarted,
    FileTransferProgress,
    FileTransferCompleted,
    FileTransferFailed,
    UploadRequested,
    ScreenCleared,
    TerminalReset,
}

/// A drained shell integration event: (event_type, command, exit_code, timestamp, cursor_line).
pub type ShellEvent = (
    String,
    Option<String>,
    Option<i32>,
    Option<u64>,
    Option<usize>,
);

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal::Terminal;

    #[test]
    fn test_event_kind_bell_rang() {
        let event = TerminalEvent::BellRang(BellEvent::VisualBell);
        assert_eq!(event.kind(), TerminalEventKind::BellRang);

        let event2 = TerminalEvent::BellRang(BellEvent::WarningBell(5));
        assert_eq!(event2.kind(), TerminalEventKind::BellRang);

        let event3 = TerminalEvent::BellRang(BellEvent::MarginBell(3));
        assert_eq!(event3.kind(), TerminalEventKind::BellRang);
    }

    #[test]
    fn test_event_kind_title_changed() {
        let event = TerminalEvent::TitleChanged("New Title".to_string());
        assert_eq!(event.kind(), TerminalEventKind::TitleChanged);
    }

    #[test]
    fn test_event_kind_size_changed() {
        let event = TerminalEvent::SizeChanged(100, 50);
        assert_eq!(event.kind(), TerminalEventKind::SizeChanged);
    }

    #[test]
    fn test_event_kind_mode_changed() {
        let event = TerminalEvent::ModeChanged("DECCKM".to_string(), true);
        assert_eq!(event.kind(), TerminalEventKind::ModeChanged);
    }

    #[test]
    fn test_event_kind_graphics_added() {
        let event = TerminalEvent::GraphicsAdded(10);
        assert_eq!(event.kind(), TerminalEventKind::GraphicsAdded);
    }

    #[test]
    fn test_event_kind_hyperlink_added() {
        let event = TerminalEvent::HyperlinkAdded {
            url: "https://example.com".to_string(),
            row: 5,
            col: 10,
            id: Some(42),
        };
        assert_eq!(event.kind(), TerminalEventKind::HyperlinkAdded);
    }

    #[test]
    fn test_event_kind_dirty_region() {
        let event = TerminalEvent::DirtyRegion(0, 23);
        assert_eq!(event.kind(), TerminalEventKind::DirtyRegion);
    }

    #[test]
    fn test_event_kind_cwd_changed() {
        let event = TerminalEvent::CwdChanged(CwdChange {
            source: CwdChangeSource::Osc7,
            old_cwd: Some("/old/path".to_string()),
            new_cwd: "/new/path".to_string(),
            hostname: None,
            username: None,
            timestamp: 1234567890,
        });
        assert_eq!(event.kind(), TerminalEventKind::CwdChanged);
    }

    #[test]
    fn test_event_kind_trigger_matched() {
        let event = TerminalEvent::TriggerMatched(TriggerMatch {
            trigger_id: 1,
            row: 10,
            col: 0,
            end_col: 15,
            text: "error occurred".to_string(),
            captures: vec!["error occurred".to_string()],
            timestamp: 1234567890,
        });
        assert_eq!(event.kind(), TerminalEventKind::TriggerMatched);
    }

    #[test]
    fn test_event_kind_user_var_changed() {
        let event = TerminalEvent::UserVarChanged {
            name: "MY_VAR".to_string(),
            value: "new_value".to_string(),
            old_value: Some("old_value".to_string()),
        };
        assert_eq!(event.kind(), TerminalEventKind::UserVarChanged);
    }

    #[test]
    fn test_event_kind_progress_bar_changed() {
        let event = TerminalEvent::ProgressBarChanged {
            action: ProgressBarAction::Set,
            id: "download".to_string(),
            state: Some(ProgressState::Normal),
            percent: Some(50),
            label: Some("Downloading".to_string()),
        };
        assert_eq!(event.kind(), TerminalEventKind::ProgressBarChanged);
    }

    #[test]
    fn test_event_kind_badge_changed() {
        let event = TerminalEvent::BadgeChanged(Some("Important".to_string()));
        assert_eq!(event.kind(), TerminalEventKind::BadgeChanged);
    }

    #[test]
    fn test_event_kind_shell_integration_event() {
        let event = TerminalEvent::ShellIntegrationEvent {
            source: ShellIntegrationSource::Osc133,
            event_type: "prompt_start".to_string(),
            command: None,
            exit_code: None,
            timestamp: Some(1234567890),
            cursor_line: Some(5),
            prompt_kind: Some("initial".to_string()),
            aid: Some("shell-1".to_string()),
            parent_aid: None,
            implicit_closed_count: 0,
            fresh_line: Some(true),
        };
        assert_eq!(event.kind(), TerminalEventKind::ShellIntegrationEvent);
    }

    #[test]
    fn test_event_kind_zone_opened() {
        let event = TerminalEvent::ZoneOpened {
            zone_id: 1,
            zone_type: ZoneType::Prompt,
            abs_row_start: 10,
        };
        assert_eq!(event.kind(), TerminalEventKind::ZoneOpened);
    }

    #[test]
    fn test_event_kind_zone_closed() {
        let event = TerminalEvent::ZoneClosed {
            zone_id: 1,
            zone_type: ZoneType::Output,
            abs_row_start: 10,
            abs_row_end: 15,
            exit_code: Some(0),
        };
        assert_eq!(event.kind(), TerminalEventKind::ZoneClosed);
    }

    #[test]
    fn test_event_kind_zone_scrolled_out() {
        let event = TerminalEvent::ZoneScrolledOut {
            zone_id: 1,
            zone_type: ZoneType::Command,
        };
        assert_eq!(event.kind(), TerminalEventKind::ZoneScrolledOut);
    }

    #[test]
    fn test_event_kind_environment_changed() {
        let event = TerminalEvent::EnvironmentChanged {
            key: "cwd".to_string(),
            value: "/home/user".to_string(),
            old_value: Some("/home".to_string()),
        };
        assert_eq!(event.kind(), TerminalEventKind::EnvironmentChanged);
    }

    #[test]
    fn test_event_kind_remote_host_transition() {
        let event = TerminalEvent::RemoteHostTransition {
            hostname: "server.example.com".to_string(),
            username: Some("user".to_string()),
            old_hostname: Some("localhost".to_string()),
            old_username: Some("localuser".to_string()),
        };
        assert_eq!(event.kind(), TerminalEventKind::RemoteHostTransition);
    }

    #[test]
    fn test_event_kind_sub_shell_detected() {
        let event = TerminalEvent::SubShellDetected {
            depth: 2,
            shell_type: Some("bash".to_string()),
        };
        assert_eq!(event.kind(), TerminalEventKind::SubShellDetected);
    }

    #[test]
    fn test_event_kind_file_transfer_started() {
        let event = TerminalEvent::FileTransferStarted {
            id: 123,
            direction: TransferDirection::Download,
            filename: Some("file.txt".to_string()),
            total_bytes: Some(1024),
        };
        assert_eq!(event.kind(), TerminalEventKind::FileTransferStarted);
    }

    #[test]
    fn test_event_kind_file_transfer_progress() {
        let event = TerminalEvent::FileTransferProgress {
            id: 123,
            bytes_transferred: 512,
            total_bytes: Some(1024),
        };
        assert_eq!(event.kind(), TerminalEventKind::FileTransferProgress);
    }

    #[test]
    fn test_event_kind_file_transfer_completed() {
        let event = TerminalEvent::FileTransferCompleted {
            id: 123,
            filename: Some("file.txt".to_string()),
            size: 1024,
        };
        assert_eq!(event.kind(), TerminalEventKind::FileTransferCompleted);
    }

    #[test]
    fn test_event_kind_file_transfer_failed() {
        let event = TerminalEvent::FileTransferFailed {
            id: 123,
            reason: "Network error".to_string(),
        };
        assert_eq!(event.kind(), TerminalEventKind::FileTransferFailed);
    }

    #[test]
    fn test_event_kind_upload_requested() {
        let event = TerminalEvent::UploadRequested {
            format: "base64".to_string(),
        };
        assert_eq!(event.kind(), TerminalEventKind::UploadRequested);
    }

    #[test]
    fn ris_emits_terminal_reset_without_reusing_screen_cleared() {
        let mut terminal = Terminal::new(80, 24);

        terminal.process(b"\x1b[2J\x1b[3J");
        let clear_events = terminal.poll_events();
        assert_eq!(
            clear_events
                .iter()
                .filter(|event| matches!(event, TerminalEvent::ScreenCleared { .. }))
                .count(),
            2
        );
        assert!(!clear_events
            .iter()
            .any(|event| matches!(event, TerminalEvent::TerminalReset)));

        terminal.process(b"\x1bc");
        let reset_events = terminal.poll_events();
        assert_eq!(
            reset_events
                .iter()
                .filter(|event| matches!(event, TerminalEvent::TerminalReset))
                .count(),
            1
        );
        assert!(!reset_events
            .iter()
            .any(|event| matches!(event, TerminalEvent::ScreenCleared { .. })));
        assert_eq!(
            TerminalEvent::TerminalReset.kind(),
            TerminalEventKind::TerminalReset
        );
    }

    #[test]
    fn event_subscription_filter_survives_ris() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_event_subscription(std::collections::HashSet::from([
            TerminalEventKind::TerminalReset,
        ]));

        terminal.process(b"\x1bc");
        assert_eq!(
            terminal.poll_subscribed_events(),
            vec![TerminalEvent::TerminalReset]
        );

        terminal.process(b"\x1b]2;after reset\x07");
        assert!(terminal.poll_subscribed_events().is_empty());
        assert!(terminal
            .poll_events()
            .iter()
            .any(|event| matches!(event, TerminalEvent::TitleChanged(_))));
    }

    #[test]
    fn test_event_queuing_through_process() {
        let mut term = Terminal::new(80, 24);

        // Process a bell sequence
        term.process(b"\x07");

        // Poll events
        let events = term.poll_events();

        // Should have a bell event
        let bell_events: Vec<_> = events
            .iter()
            .filter(|e| matches!(e.kind(), TerminalEventKind::BellRang))
            .collect();

        assert!(!bell_events.is_empty(), "Should have received a bell event");

        // Polling again should return empty (events are consumed)
        let events2 = term.poll_events();
        assert!(events2.is_empty(), "Events should be cleared after polling");
    }

    #[test]
    fn test_event_queuing_title_change() {
        let mut term = Terminal::new(80, 24);

        // Process OSC 0 sequence to change title
        term.process(b"\x1b]0;New Title\x07");

        let events = term.poll_events();

        // Should have a title changed event
        let title_events: Vec<_> = events
            .iter()
            .filter(|e| matches!(e.kind(), TerminalEventKind::TitleChanged))
            .collect();

        assert_eq!(title_events.len(), 1);

        if let TerminalEvent::TitleChanged(title) = &title_events[0] {
            assert_eq!(title, "New Title");
        } else {
            panic!("Expected TitleChanged event");
        }
    }

    #[test]
    fn test_event_queuing_multiple_events() {
        let mut term = Terminal::new(80, 24);

        // Process multiple sequences that generate events
        term.process(b"\x07"); // Bell
        term.process(b"\x1b]0;Title1\x07"); // Title change
        term.process(b"\x07"); // Another bell

        let events = term.poll_events();

        // Should have multiple events
        assert!(events.len() >= 3, "Should have at least 3 events");

        let bell_count = events
            .iter()
            .filter(|e| matches!(e.kind(), TerminalEventKind::BellRang))
            .count();
        let title_count = events
            .iter()
            .filter(|e| matches!(e.kind(), TerminalEventKind::TitleChanged))
            .count();

        assert_eq!(bell_count, 2, "Should have 2 bell events");
        assert_eq!(title_count, 1, "Should have 1 title change event");
    }

    #[test]
    fn test_bell_event_variants() {
        let visual = BellEvent::VisualBell;
        let warning = BellEvent::WarningBell(5);
        let margin = BellEvent::MarginBell(3);

        assert_eq!(visual, BellEvent::VisualBell);
        assert_eq!(warning, BellEvent::WarningBell(5));
        assert_eq!(margin, BellEvent::MarginBell(3));

        // Test inequality
        assert_ne!(visual, warning);
        assert_ne!(visual, margin);
        assert_ne!(warning, margin);
    }

    #[test]
    fn test_cwd_change_struct() {
        let cwd_change = CwdChange {
            source: CwdChangeSource::Manual,
            old_cwd: Some("/home/user".to_string()),
            new_cwd: "/home/user/projects".to_string(),
            hostname: Some("server".to_string()),
            username: Some("user".to_string()),
            timestamp: 1234567890,
        };

        assert_eq!(cwd_change.source, CwdChangeSource::Manual);
        assert_eq!(cwd_change.source.as_str(), "manual");
        assert_eq!(cwd_change.old_cwd, Some("/home/user".to_string()));
        assert_eq!(cwd_change.new_cwd, "/home/user/projects");
        assert_eq!(cwd_change.hostname, Some("server".to_string()));
        assert_eq!(cwd_change.username, Some("user".to_string()));
        assert_eq!(cwd_change.timestamp, 1234567890);
    }

    #[test]
    fn cwd_change_sources_have_stable_wire_names() {
        assert_eq!(CwdChangeSource::Osc7.as_str(), "osc7");
        assert_eq!(CwdChangeSource::Osc9_9.as_str(), "osc9;9");
        assert_eq!(CwdChangeSource::Osc633.as_str(), "osc633");
        assert_eq!(CwdChangeSource::Osc1337.as_str(), "osc1337");
        assert_eq!(CwdChangeSource::Manual.as_str(), "manual");
    }

    #[test]
    fn retained_size_estimate_counts_payload_without_formatting_it() {
        let short = TerminalEvent::TitleChanged("x".into());
        let long = TerminalEvent::TitleChanged("secret-canary".repeat(20));

        assert!(long.retained_size_bytes() > short.retained_size_bytes());
        assert_eq!(long.retained_size_bytes(), 128 + "secret-canary".len() * 20);
    }
}
