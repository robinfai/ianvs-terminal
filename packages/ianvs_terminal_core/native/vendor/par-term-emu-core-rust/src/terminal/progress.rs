//! Progress bar support for OSC 9;4 sequences (ConEmu/Windows Terminal style)
//!
//! The OSC 9;4 protocol allows terminal applications to report progress to the terminal
//! emulator, which can display it in the tab bar, window title, or other UI elements.
//!
//! ## Protocol Format
//!
//! `OSC 9 ; 4 ; state ; progress ST`
//!
//! Where:
//! - `state` is one of: 0 (hidden), 1 (normal), 2 (error), 3 (indeterminate), 4 (warning/paused)
//! - `progress` is 0-100 (percentage, only required for states 1, 2, 4)
//!
//! ## Examples
//!
//! ```text
//! \x1b]9;4;1;50\x1b\\   # Set progress to 50%
//! \x1b]9;4;0\x1b\\      # Hide progress bar
//! \x1b]9;4;2;100\x1b\\  # Show error state at 100%
//! \x1b]9;4;3\x1b\\      # Show indeterminate progress
//! \x1b]9;4;4;75\x1b\\   # Show warning/paused state at 75%
//! ```

/// Progress bar state from OSC 9;4 sequences
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ProgressState {
    /// Progress bar is hidden (state 0)
    #[default]
    Hidden,
    /// Normal progress display (state 1)
    Normal,
    /// Error state - operation failed (state 2)
    Error,
    /// Indeterminate/busy indicator (state 3)
    Indeterminate,
    /// Warning/paused state - operation may have issues (state 4)
    Warning,
}

impl ProgressState {
    /// Parse state from OSC 9;4 state parameter
    pub fn from_param(param: u8) -> Self {
        match param {
            0 => Self::Hidden,
            1 => Self::Normal,
            2 => Self::Error,
            3 => Self::Indeterminate,
            4 => Self::Warning,
            _ => Self::Hidden, // Invalid state defaults to hidden
        }
    }

    /// Convert state to OSC 9;4 parameter value
    pub fn to_param(self) -> u8 {
        match self {
            Self::Hidden => 0,
            Self::Normal => 1,
            Self::Error => 2,
            Self::Indeterminate => 3,
            Self::Warning => 4,
        }
    }

    /// Check if the state represents an active progress bar
    pub fn is_active(self) -> bool {
        !matches!(self, Self::Hidden)
    }

    /// Check if the state requires a progress percentage
    pub fn requires_progress(self) -> bool {
        matches!(self, Self::Normal | Self::Error | Self::Warning)
    }

    /// Get a human-readable description of the state
    pub fn description(self) -> &'static str {
        match self {
            Self::Hidden => "hidden",
            Self::Normal => "normal",
            Self::Indeterminate => "indeterminate",
            Self::Warning => "warning",
            Self::Error => "error",
        }
    }
}

/// Progress bar data from OSC 9;4 sequences
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProgressBar {
    /// Current progress state
    pub state: ProgressState,
    /// Progress percentage (0-100), only meaningful for Normal/Warning/Error states
    pub progress: u8,
}

impl Default for ProgressBar {
    fn default() -> Self {
        Self {
            state: ProgressState::Hidden,
            progress: 0,
        }
    }
}

impl ProgressBar {
    /// Create a new progress bar with the given state and progress
    pub fn new(state: ProgressState, progress: u8) -> Self {
        Self {
            state,
            progress: progress.min(100), // Clamp to 100%
        }
    }

    /// Create a hidden (inactive) progress bar
    pub fn hidden() -> Self {
        Self::default()
    }

    /// Create a normal progress bar at the given percentage
    pub fn normal(progress: u8) -> Self {
        Self::new(ProgressState::Normal, progress)
    }

    /// Create an indeterminate progress bar
    pub fn indeterminate() -> Self {
        Self::new(ProgressState::Indeterminate, 0)
    }

    /// Create a warning progress bar at the given percentage
    pub fn warning(progress: u8) -> Self {
        Self::new(ProgressState::Warning, progress)
    }

    /// Create an error progress bar at the given percentage
    pub fn error(progress: u8) -> Self {
        Self::new(ProgressState::Error, progress)
    }

    /// Check if the progress bar is active (visible)
    pub fn is_active(&self) -> bool {
        self.state.is_active()
    }

    /// Generate the OSC 9;4 escape sequence for this progress bar
    pub fn to_escape_sequence(&self) -> String {
        if self.state.requires_progress() {
            format!("\x1b]9;4;{};{}\x1b\\", self.state.to_param(), self.progress)
        } else {
            format!("\x1b]9;4;{}\x1b\\", self.state.to_param())
        }
    }
}

/// Action for an OSC 934 progress bar operation
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProgressBarAction {
    /// Create or update a progress bar
    Set,
    /// Remove a progress bar by ID
    Remove,
    /// Remove all progress bars
    RemoveAll,
}

/// Stable capability/version token for the Ianvs private OSC 934 protocol.
pub const OSC934_PROTOCOL_VERSION: &str = "ianvs-osc934/1";

/// Maximum OSC 934 payload size, excluding the OSC introducer and terminator.
///
/// The streaming OSC prefilter should enforce this before allocating an entire
/// sequence. This parser also checks the reconstructed payload length as a
/// defense-in-depth boundary for direct callers.
pub const MAX_OSC934_PAYLOAD_BYTES: usize = 8 * 1024;

/// Maximum UTF-8 byte length of a named progress identifier.
pub const MAX_OSC934_ID_BYTES: usize = 128;

/// Maximum UTF-8 byte length of a named progress label.
pub const MAX_OSC934_LABEL_BYTES: usize = 1024;

/// Maximum number of active named progress bars retained per terminal session.
///
/// State owners must reject creation of a new ID at this boundary while still
/// allowing updates and removals of existing IDs.
pub const MAX_OSC934_ACTIVE_BARS: usize = 64;

/// Canonical response to `OSC 934;query ST`.
///
/// This response intentionally contains only static protocol metadata. It must
/// never include session state, progress identifiers, labels, or other terminal
/// contents.
pub const OSC934_CAPABILITY_RESPONSE: &[u8] = b"\x1b]934;capability;ianvs-osc934/1;actions=set,remove,remove_all;states=normal,indeterminate,warning,error,hidden\x1b\\";

/// A named progress bar from OSC 934 sequences
///
/// OSC 934 supports multiple concurrent progress bars, each identified by a
/// unique string ID. Each bar has a state, percentage, and optional label.
///
/// ## Protocol Format
///
/// `OSC 934 ; action [; id] [; key=value ...] ST`
///
/// Actions:
/// - `set` — create or update a progress bar
/// - `remove` — remove a specific progress bar
/// - `remove_all` — remove all progress bars
/// - `query` — request the static [`OSC934_CAPABILITY_RESPONSE`]
///
/// Key-value parameters (for `set`):
/// - `percent=N` — progress percentage (0-100, clamped)
/// - `label=text` — descriptive label for the progress bar
/// - `state=S` — state name: `normal`, `indeterminate`, `warning`, `error`
///
/// ## Examples
///
/// ```text
/// \x1b]934;set;dl-1;percent=50;label=Downloading\x1b\\
/// \x1b]934;set;dl-1;percent=100;state=normal\x1b\\
/// \x1b]934;set;build;state=indeterminate;label=Compiling\x1b\\
/// \x1b]934;set;build;state=error;label=Build failed\x1b\\
/// \x1b]934;remove;dl-1\x1b\\
/// \x1b]934;remove_all\x1b\\
/// \x1b]934;query\x1b\\
/// ```
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NamedProgressBar {
    /// Unique identifier for the progress bar
    pub id: String,
    /// Current progress state
    pub state: ProgressState,
    /// Progress percentage (0-100), only meaningful for Normal/Warning/Error states
    pub percent: u8,
    /// Optional descriptive label
    pub label: Option<String>,
}

impl NamedProgressBar {
    /// Create a new named progress bar
    pub fn new(id: String, state: ProgressState, percent: u8, label: Option<String>) -> Self {
        Self {
            id,
            state,
            percent: percent.min(100),
            label,
        }
    }
}

/// Result of parsing an OSC 934 sequence
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProgressBarCommand {
    /// Create or update a named progress bar
    Set(NamedProgressBar),
    /// Remove a progress bar by ID
    Remove(String),
    /// Remove all progress bars
    RemoveAll,
    /// Request the terminal's static OSC 934 capability descriptor.
    Query,
}

impl ProgressBarCommand {
    fn payload_len(params: &[&[u8]]) -> Option<usize> {
        params
            .iter()
            .try_fold(params.len().saturating_sub(1), |length, param| {
                length.checked_add(param.len())
            })
    }

    fn parse_identifier(value: &[u8]) -> Option<String> {
        let value = std::str::from_utf8(value).ok()?.trim();
        if value.is_empty()
            || value.len() > MAX_OSC934_ID_BYTES
            || value.chars().any(char::is_control)
        {
            return None;
        }
        Some(value.to_string())
    }

    fn parse_label(value: &str) -> Option<String> {
        let value = value.trim();
        if value.is_empty()
            || value.len() > MAX_OSC934_LABEL_BYTES
            || value.chars().any(char::is_control)
        {
            return None;
        }
        Some(value.to_string())
    }

    /// Parse an OSC 934 parameter list into a ProgressBarCommand
    ///
    /// Expected format after the "934" prefix:
    /// params[0] = "934" (already consumed by caller)
    /// params[1] = action ("set", "remove", "remove_all")
    /// params[2] = id (for "set" and "remove")
    /// params[3..] = key=value pairs (for "set")
    ///
    /// `query` has no ID or properties. The caller is responsible for writing
    /// [`OSC934_CAPABILITY_RESPONSE`] to the device response channel without
    /// mutating progress state.
    pub fn parse(params: &[&[u8]]) -> Option<Self> {
        if Self::payload_len(params)? > MAX_OSC934_PAYLOAD_BYTES {
            return None;
        }

        // params[0] is "934", params[1] is the action
        if params.first().copied() != Some(b"934") || params.len() < 2 {
            return None;
        }

        let action = std::str::from_utf8(params[1]).ok()?.trim();

        match action {
            "set" => {
                // Need at least an ID
                if params.len() < 3 {
                    return None;
                }
                let id = Self::parse_identifier(params[2])?;

                let mut state = ProgressState::Normal;
                let mut percent: u8 = 0;
                let mut label: Option<String> = None;

                // Parse key=value pairs
                for param in &params[3..] {
                    if let Ok(kv) = std::str::from_utf8(param) {
                        let kv = kv.trim();
                        if let Some((key, value)) = kv.split_once('=') {
                            match key.trim() {
                                "percent" => {
                                    let value = value.trim();
                                    if !value.is_empty()
                                        && value.bytes().all(|byte| byte.is_ascii_digit())
                                    {
                                        if let Ok(value) = value.parse::<u16>() {
                                            percent = (value.min(100)) as u8;
                                        }
                                    }
                                }
                                "label" => {
                                    if let Some(value) = Self::parse_label(value) {
                                        label = Some(value);
                                    }
                                }
                                "state" => match value.trim() {
                                    "normal" => state = ProgressState::Normal,
                                    "indeterminate" => state = ProgressState::Indeterminate,
                                    "warning" => state = ProgressState::Warning,
                                    "error" => state = ProgressState::Error,
                                    "hidden" => state = ProgressState::Hidden,
                                    _ => {}
                                },
                                _ => {} // Ignore unknown keys
                            }
                        }
                    }
                }

                Some(Self::Set(NamedProgressBar::new(id, state, percent, label)))
            }
            "remove" => {
                if params.len() < 3 {
                    return None;
                }
                let id = Self::parse_identifier(params[2])?;
                Some(Self::Remove(id))
            }
            "remove_all" => Some(Self::RemoveAll),
            "query" if params.len() == 2 => Some(Self::Query),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_progress_state_from_param() {
        assert_eq!(ProgressState::from_param(0), ProgressState::Hidden);
        assert_eq!(ProgressState::from_param(1), ProgressState::Normal);
        assert_eq!(ProgressState::from_param(2), ProgressState::Error);
        assert_eq!(ProgressState::from_param(3), ProgressState::Indeterminate);
        assert_eq!(ProgressState::from_param(4), ProgressState::Warning);
        // Invalid values default to Hidden
        assert_eq!(ProgressState::from_param(5), ProgressState::Hidden);
        assert_eq!(ProgressState::from_param(255), ProgressState::Hidden);
    }

    #[test]
    fn test_progress_state_to_param() {
        assert_eq!(ProgressState::Hidden.to_param(), 0);
        assert_eq!(ProgressState::Normal.to_param(), 1);
        assert_eq!(ProgressState::Error.to_param(), 2);
        assert_eq!(ProgressState::Indeterminate.to_param(), 3);
        assert_eq!(ProgressState::Warning.to_param(), 4);
    }

    #[test]
    fn test_progress_state_is_active() {
        assert!(!ProgressState::Hidden.is_active());
        assert!(ProgressState::Normal.is_active());
        assert!(ProgressState::Indeterminate.is_active());
        assert!(ProgressState::Warning.is_active());
        assert!(ProgressState::Error.is_active());
    }

    #[test]
    fn test_progress_state_requires_progress() {
        assert!(!ProgressState::Hidden.requires_progress());
        assert!(ProgressState::Normal.requires_progress());
        assert!(!ProgressState::Indeterminate.requires_progress());
        assert!(ProgressState::Warning.requires_progress());
        assert!(ProgressState::Error.requires_progress());
    }

    #[test]
    fn test_progress_bar_new() {
        let pb = ProgressBar::new(ProgressState::Normal, 50);
        assert_eq!(pb.state, ProgressState::Normal);
        assert_eq!(pb.progress, 50);
    }

    #[test]
    fn test_progress_bar_clamps_to_100() {
        let pb = ProgressBar::new(ProgressState::Normal, 150);
        assert_eq!(pb.progress, 100);
    }

    #[test]
    fn test_progress_bar_constructors() {
        let hidden = ProgressBar::hidden();
        assert_eq!(hidden.state, ProgressState::Hidden);
        assert!(!hidden.is_active());

        let normal = ProgressBar::normal(75);
        assert_eq!(normal.state, ProgressState::Normal);
        assert_eq!(normal.progress, 75);
        assert!(normal.is_active());

        let indeterminate = ProgressBar::indeterminate();
        assert_eq!(indeterminate.state, ProgressState::Indeterminate);
        assert!(indeterminate.is_active());

        let warning = ProgressBar::warning(90);
        assert_eq!(warning.state, ProgressState::Warning);
        assert_eq!(warning.progress, 90);

        let error = ProgressBar::error(100);
        assert_eq!(error.state, ProgressState::Error);
        assert_eq!(error.progress, 100);
    }

    #[test]
    fn test_progress_bar_default() {
        let pb = ProgressBar::default();
        assert_eq!(pb.state, ProgressState::Hidden);
        assert_eq!(pb.progress, 0);
        assert!(!pb.is_active());
    }

    #[test]
    fn test_progress_bar_escape_sequence() {
        assert_eq!(
            ProgressBar::hidden().to_escape_sequence(),
            "\x1b]9;4;0\x1b\\"
        );
        assert_eq!(
            ProgressBar::normal(50).to_escape_sequence(),
            "\x1b]9;4;1;50\x1b\\"
        );
        assert_eq!(
            ProgressBar::error(100).to_escape_sequence(),
            "\x1b]9;4;2;100\x1b\\"
        );
        assert_eq!(
            ProgressBar::indeterminate().to_escape_sequence(),
            "\x1b]9;4;3\x1b\\"
        );
        assert_eq!(
            ProgressBar::warning(75).to_escape_sequence(),
            "\x1b]9;4;4;75\x1b\\"
        );
    }

    #[test]
    fn test_progress_state_description() {
        assert_eq!(ProgressState::Hidden.description(), "hidden");
        assert_eq!(ProgressState::Normal.description(), "normal");
        assert_eq!(ProgressState::Indeterminate.description(), "indeterminate");
        assert_eq!(ProgressState::Warning.description(), "warning");
        assert_eq!(ProgressState::Error.description(), "error");
    }

    #[test]
    fn test_progress_bar_clone() {
        let pb1 = ProgressBar::normal(50);
        let pb2 = pb1;
        assert_eq!(pb1, pb2);
    }

    #[test]
    fn test_progress_bar_debug() {
        let pb = ProgressBar::normal(50);
        let debug_str = format!("{:?}", pb);
        assert!(debug_str.contains("Normal"));
        assert!(debug_str.contains("50"));
    }

    // === OSC 934 Named Progress Bar Tests ===

    #[test]
    fn test_named_progress_bar_new() {
        let bar = NamedProgressBar::new(
            "dl-1".to_string(),
            ProgressState::Normal,
            50,
            Some("Downloading".to_string()),
        );
        assert_eq!(bar.id, "dl-1");
        assert_eq!(bar.state, ProgressState::Normal);
        assert_eq!(bar.percent, 50);
        assert_eq!(bar.label, Some("Downloading".to_string()));
    }

    #[test]
    fn test_named_progress_bar_clamps_percent() {
        let bar = NamedProgressBar::new("x".to_string(), ProgressState::Normal, 200, None);
        assert_eq!(bar.percent, 100);
    }

    #[test]
    fn test_named_progress_storage_is_bounded_but_existing_ids_can_update() {
        let mut terminal = crate::terminal::Terminal::new(80, 24);
        for index in 0..MAX_OSC934_ACTIVE_BARS {
            terminal.set_named_progress_bar(NamedProgressBar::new(
                format!("job-{index}"),
                ProgressState::Normal,
                index as u8,
                None,
            ));
        }
        let _ = terminal.poll_events();

        terminal.set_named_progress_bar(NamedProgressBar::new(
            "rejected-at-cap".to_string(),
            ProgressState::Normal,
            50,
            None,
        ));
        assert_eq!(terminal.named_progress_bars().len(), MAX_OSC934_ACTIVE_BARS);
        assert!(terminal.get_named_progress_bar("rejected-at-cap").is_none());
        assert!(terminal.poll_events().is_empty());

        terminal.set_named_progress_bar(NamedProgressBar::new(
            "job-0".to_string(),
            ProgressState::Error,
            99,
            Some("updated".to_string()),
        ));
        assert_eq!(terminal.named_progress_bars().len(), MAX_OSC934_ACTIVE_BARS);
        assert_eq!(
            terminal.get_named_progress_bar("job-0").unwrap().percent,
            99
        );
        assert_eq!(terminal.poll_events().len(), 1);

        assert!(terminal.remove_named_progress_bar("job-1"));
        terminal.set_named_progress_bar(NamedProgressBar::new(
            "replacement".to_string(),
            ProgressState::Indeterminate,
            0,
            None,
        ));
        assert_eq!(terminal.named_progress_bars().len(), MAX_OSC934_ACTIVE_BARS);
        assert!(terminal.get_named_progress_bar("replacement").is_some());
    }

    #[test]
    fn test_parse_osc934_set_basic() {
        let params: Vec<&[u8]> = vec![b"934", b"set", b"dl-1", b"percent=50", b"label=Downloading"];
        let cmd = ProgressBarCommand::parse(&params).unwrap();
        match cmd {
            ProgressBarCommand::Set(bar) => {
                assert_eq!(bar.id, "dl-1");
                assert_eq!(bar.state, ProgressState::Normal);
                assert_eq!(bar.percent, 50);
                assert_eq!(bar.label, Some("Downloading".to_string()));
            }
            _ => panic!("Expected Set command"),
        }
    }

    #[test]
    fn test_parse_osc934_set_with_state() {
        let params: Vec<&[u8]> = vec![b"934", b"set", b"build", b"state=indeterminate"];
        let cmd = ProgressBarCommand::parse(&params).unwrap();
        match cmd {
            ProgressBarCommand::Set(bar) => {
                assert_eq!(bar.id, "build");
                assert_eq!(bar.state, ProgressState::Indeterminate);
            }
            _ => panic!("Expected Set command"),
        }
    }

    #[test]
    fn test_parse_osc934_set_warning() {
        let params: Vec<&[u8]> = vec![b"934", b"set", b"job", b"state=warning", b"percent=80"];
        let cmd = ProgressBarCommand::parse(&params).unwrap();
        match cmd {
            ProgressBarCommand::Set(bar) => {
                assert_eq!(bar.state, ProgressState::Warning);
                assert_eq!(bar.percent, 80);
            }
            _ => panic!("Expected Set command"),
        }
    }

    #[test]
    fn test_parse_osc934_set_error() {
        let params: Vec<&[u8]> = vec![
            b"934",
            b"set",
            b"build",
            b"state=error",
            b"label=Build failed",
        ];
        let cmd = ProgressBarCommand::parse(&params).unwrap();
        match cmd {
            ProgressBarCommand::Set(bar) => {
                assert_eq!(bar.state, ProgressState::Error);
                assert_eq!(bar.label, Some("Build failed".to_string()));
            }
            _ => panic!("Expected Set command"),
        }
    }

    #[test]
    fn test_parse_osc934_set_minimal() {
        // Just ID, no extra params — defaults to Normal state at 0%
        let params: Vec<&[u8]> = vec![b"934", b"set", b"x"];
        let cmd = ProgressBarCommand::parse(&params).unwrap();
        match cmd {
            ProgressBarCommand::Set(bar) => {
                assert_eq!(bar.id, "x");
                assert_eq!(bar.state, ProgressState::Normal);
                assert_eq!(bar.percent, 0);
                assert_eq!(bar.label, None);
            }
            _ => panic!("Expected Set command"),
        }
    }

    #[test]
    fn test_parse_osc934_remove() {
        let params: Vec<&[u8]> = vec![b"934", b"remove", b"dl-1"];
        let cmd = ProgressBarCommand::parse(&params).unwrap();
        assert_eq!(cmd, ProgressBarCommand::Remove("dl-1".to_string()));
    }

    #[test]
    fn test_parse_osc934_remove_all() {
        let params: Vec<&[u8]> = vec![b"934", b"remove_all"];
        let cmd = ProgressBarCommand::parse(&params).unwrap();
        assert_eq!(cmd, ProgressBarCommand::RemoveAll);
    }

    #[test]
    fn test_parse_osc934_missing_action() {
        let params: Vec<&[u8]> = vec![b"934"];
        assert!(ProgressBarCommand::parse(&params).is_none());
    }

    #[test]
    fn test_parse_osc934_invalid_action() {
        let params: Vec<&[u8]> = vec![b"934", b"invalid"];
        assert!(ProgressBarCommand::parse(&params).is_none());
    }

    #[test]
    fn test_parse_osc934_set_missing_id() {
        let params: Vec<&[u8]> = vec![b"934", b"set"];
        assert!(ProgressBarCommand::parse(&params).is_none());
    }

    #[test]
    fn test_parse_osc934_set_empty_id() {
        let params: Vec<&[u8]> = vec![b"934", b"set", b""];
        assert!(ProgressBarCommand::parse(&params).is_none());
    }

    #[test]
    fn test_parse_osc934_remove_missing_id() {
        let params: Vec<&[u8]> = vec![b"934", b"remove"];
        assert!(ProgressBarCommand::parse(&params).is_none());
    }

    #[test]
    fn test_parse_osc934_percent_clamped() {
        let params: Vec<&[u8]> = vec![b"934", b"set", b"x", b"percent=999"];
        let cmd = ProgressBarCommand::parse(&params).unwrap();
        match cmd {
            ProgressBarCommand::Set(bar) => {
                assert_eq!(bar.percent, 100);
            }
            _ => panic!("Expected Set command"),
        }
    }

    #[test]
    fn test_parse_osc934_unknown_keys_ignored() {
        let params: Vec<&[u8]> = vec![b"934", b"set", b"x", b"foo=bar", b"percent=42"];
        let cmd = ProgressBarCommand::parse(&params).unwrap();
        match cmd {
            ProgressBarCommand::Set(bar) => {
                assert_eq!(bar.percent, 42);
            }
            _ => panic!("Expected Set command"),
        }
    }

    #[test]
    fn test_parse_osc934_invalid_percent_ignored() {
        for invalid_percent in [
            b"percent=abc".as_slice(),
            b"percent=+1".as_slice(),
            b"percent=-1".as_slice(),
            b"percent=65536".as_slice(),
        ] {
            let params: Vec<&[u8]> = vec![b"934", b"set", b"x", invalid_percent];
            let cmd = ProgressBarCommand::parse(&params).unwrap();
            match cmd {
                ProgressBarCommand::Set(bar) => {
                    assert_eq!(bar.percent, 0); // Stays at default
                }
                _ => panic!("Expected Set command"),
            }
        }
    }

    #[test]
    fn test_parse_osc934_requires_private_protocol_prefix() {
        let params: Vec<&[u8]> = vec![b"933", b"set", b"x"];
        assert!(ProgressBarCommand::parse(&params).is_none());
    }

    #[test]
    fn test_parse_osc934_rejects_oversized_payload() {
        let oversized = "x".repeat(MAX_OSC934_PAYLOAD_BYTES);
        let params: Vec<&[u8]> = vec![b"934", b"set", b"x", oversized.as_bytes()];
        assert!(ProgressBarCommand::parse(&params).is_none());
    }

    #[test]
    fn test_parse_osc934_accepts_payload_at_exact_limit() {
        let fixed_length = b"934".len() + b"set".len() + b"x".len() + 3;
        let filler = "z".repeat(MAX_OSC934_PAYLOAD_BYTES - fixed_length);
        let params: Vec<&[u8]> = vec![b"934", b"set", b"x", filler.as_bytes()];
        assert_eq!(
            ProgressBarCommand::payload_len(&params),
            Some(MAX_OSC934_PAYLOAD_BYTES)
        );
        assert!(matches!(
            ProgressBarCommand::parse(&params),
            Some(ProgressBarCommand::Set(_))
        ));
    }

    #[test]
    fn test_parse_osc934_rejects_oversized_or_control_character_id() {
        let oversized = "x".repeat(MAX_OSC934_ID_BYTES + 1);
        let oversized_params: Vec<&[u8]> = vec![b"934", b"set", oversized.as_bytes()];
        assert!(ProgressBarCommand::parse(&oversized_params).is_none());

        let control_params: Vec<&[u8]> = vec![b"934", b"set", b"unsafe\nidentifier"];
        assert!(ProgressBarCommand::parse(&control_params).is_none());
    }

    #[test]
    fn test_parse_osc934_accepts_id_and_label_at_exact_limits() {
        let id = "i".repeat(MAX_OSC934_ID_BYTES);
        let label = format!("label={}", "l".repeat(MAX_OSC934_LABEL_BYTES));
        let params: Vec<&[u8]> = vec![b"934", b"set", id.as_bytes(), label.as_bytes()];
        let command = ProgressBarCommand::parse(&params).unwrap();
        match command {
            ProgressBarCommand::Set(bar) => {
                assert_eq!(bar.id.len(), MAX_OSC934_ID_BYTES);
                assert_eq!(
                    bar.label.as_ref().map(String::len),
                    Some(MAX_OSC934_LABEL_BYTES)
                );
            }
            _ => panic!("Expected Set command"),
        }
    }

    #[test]
    fn test_parse_osc934_ignores_invalid_label_without_storing_it() {
        let oversized = "x".repeat(MAX_OSC934_LABEL_BYTES + 1);
        let oversized_label = format!("label={oversized}");
        let params: Vec<&[u8]> = vec![
            b"934",
            b"set",
            b"safe-id",
            b"label=valid",
            b"label=unsafe\nlabel",
            oversized_label.as_bytes(),
        ];
        let command = ProgressBarCommand::parse(&params).unwrap();
        match command {
            ProgressBarCommand::Set(bar) => assert_eq!(bar.label.as_deref(), Some("valid")),
            _ => panic!("Expected Set command"),
        }
    }

    #[test]
    fn test_parse_osc934_last_valid_duplicate_field_wins() {
        let params: Vec<&[u8]> = vec![
            b"934",
            b"set",
            b"build",
            b"percent=10",
            b"state=normal",
            b"percent=80",
            b"state=warning",
        ];
        let command = ProgressBarCommand::parse(&params).unwrap();
        match command {
            ProgressBarCommand::Set(bar) => {
                assert_eq!(bar.percent, 80);
                assert_eq!(bar.state, ProgressState::Warning);
            }
            _ => panic!("Expected Set command"),
        }
    }

    #[test]
    fn test_parse_osc934_query_has_static_non_sensitive_response() {
        let params: Vec<&[u8]> = vec![b"934", b"query"];
        assert_eq!(
            ProgressBarCommand::parse(&params),
            Some(ProgressBarCommand::Query)
        );

        let response = std::str::from_utf8(OSC934_CAPABILITY_RESPONSE).unwrap();
        assert!(response.starts_with("\u{1b}]934;capability;ianvs-osc934/1;"));
        assert!(response.contains(OSC934_PROTOCOL_VERSION));
        assert!(response.ends_with("\u{1b}\\"));
        assert!(response.contains("actions=set,remove,remove_all"));
        assert!(response.contains("states=normal,indeterminate,warning,error,hidden"));
    }

    #[test]
    fn test_parse_osc934_query_rejects_extensions_and_response_does_not_loop() {
        let extended_query: Vec<&[u8]> = vec![b"934", b"query", b"session-state"];
        assert!(ProgressBarCommand::parse(&extended_query).is_none());

        let capability_response: Vec<&[u8]> =
            vec![b"934", b"capability", OSC934_PROTOCOL_VERSION.as_bytes()];
        assert!(ProgressBarCommand::parse(&capability_response).is_none());
    }
}
