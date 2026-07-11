/// Shell integration markers (OSC 133)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellIntegrationMarker {
    /// Start of prompt (A)
    PromptStart,
    /// Start of command input (B)
    CommandStart,
    /// Start of command output (C)
    CommandExecuted,
    /// End of command output, with exit code (D)
    CommandFinished,
}

/// Validated state of the shared OSC 133/633 shell-integration lifecycle.
///
/// This is deliberately separate from [`ShellIntegrationMarker`]: a received
/// `D` can abort command input before execution, in which case exposing a
/// `CommandFinished` marker would falsely report a completed command.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellIntegrationState {
    /// No complete shell-integration cycle has started yet.
    Idle,
    /// Prompt text is being produced (`A`).
    Prompt,
    /// Command input is being produced (`B`).
    CommandInput,
    /// The command has executed and output is being produced (`C`).
    CommandOutput,
    /// Command output ended normally (`D` after `C`).
    Finished,
    /// Command input was abandoned (`D` after `B`).
    Aborted,
}

/// Result of validating a shell-integration marker against the current state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ShellMarkerTransition {
    /// The marker is valid and the state advanced normally.
    Accepted,
    /// `D` ended command input before the command was executed.
    Aborted,
    /// The marker is out of order or a duplicate and had no effect.
    Ignored,
}

const MAX_NESTED_SHELL_LIFECYCLES: usize = 16;

/// In-memory verifier for the optional OSC 633 command metadata nonce.
///
/// The raw value is intentionally hidden from `Debug`, events, diagnostics,
/// and public accessors. It is session configuration, not execution authority.
#[derive(Clone, PartialEq, Eq)]
pub(crate) struct Osc633ExpectedNonce(String);

impl Osc633ExpectedNonce {
    pub(crate) fn new(value: String) -> Self {
        Self(value)
    }

    pub(crate) fn as_str(&self) -> &str {
        &self.0
    }

    pub(crate) fn len(&self) -> usize {
        self.0.len()
    }
}

impl std::fmt::Debug for Osc633ExpectedNonce {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("Osc633ExpectedNonce([redacted])")
    }
}

#[derive(Debug, Clone)]
struct ShellLifecycleFrame {
    marker: Option<ShellIntegrationMarker>,
    state: ShellIntegrationState,
    command: Option<String>,
    exit_code: Option<i32>,
}

/// Shell integration state
#[derive(Clone)]
pub struct ShellIntegration {
    /// Current marker
    current_marker: Option<ShellIntegrationMarker>,
    /// Validated OSC 133/633 lifecycle state.
    current_state: ShellIntegrationState,
    /// Command that was executed
    current_command: Option<String>,
    /// Exit code of last command
    last_exit_code: Option<i32>,
    /// Suspended outer command-output lifecycles while a nested shell runs.
    lifecycle_stack: Vec<ShellLifecycleFrame>,
    /// Current working directory
    cwd: Option<String>,
    /// Hostname from OSC 7 (None if localhost/implicit)
    hostname: Option<String>,
    /// Username from OSC 7 (if provided as user@host)
    username: Option<String>,
}

impl std::fmt::Debug for ShellIntegration {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ShellIntegration")
            .field("current_marker", &self.current_marker)
            .field("current_state", &self.current_state)
            .field("has_current_command", &self.current_command.is_some())
            .field("has_last_exit_code", &self.last_exit_code.is_some())
            .field("suspended_lifecycle_count", &self.lifecycle_stack.len())
            .field("has_cwd", &self.cwd.is_some())
            .field("has_hostname", &self.hostname.is_some())
            .field("has_username", &self.username.is_some())
            .finish()
    }
}

impl Default for ShellIntegration {
    fn default() -> Self {
        Self::new()
    }
}

impl ShellIntegration {
    /// Create a new shell integration state
    pub fn new() -> Self {
        Self {
            current_marker: None,
            current_state: ShellIntegrationState::Idle,
            current_command: None,
            last_exit_code: None,
            lifecycle_stack: Vec::new(),
            cwd: None,
            hostname: None,
            username: None,
        }
    }

    /// Set the current marker
    pub fn set_marker(&mut self, marker: ShellIntegrationMarker) {
        self.current_marker = Some(marker);
        self.current_state = match marker {
            ShellIntegrationMarker::PromptStart => ShellIntegrationState::Prompt,
            ShellIntegrationMarker::CommandStart => ShellIntegrationState::CommandInput,
            ShellIntegrationMarker::CommandExecuted => ShellIntegrationState::CommandOutput,
            ShellIntegrationMarker::CommandFinished => ShellIntegrationState::Finished,
        };
    }

    /// Get the current marker
    pub fn marker(&self) -> Option<ShellIntegrationMarker> {
        self.current_marker
    }

    /// Get the validated OSC 133/633 lifecycle state.
    pub fn state(&self) -> ShellIntegrationState {
        self.current_state
    }

    /// Validate and apply one shell-integration lifecycle marker.
    ///
    /// `A` is the synchronization boundary and can recover an incomplete
    /// previous cycle. `B` and `C` require their immediate predecessors.
    /// `D` after `B` is an abort and intentionally does not become a finished
    /// marker. All other out-of-order or duplicate markers are idempotent.
    pub(crate) fn transition_marker(
        &mut self,
        marker: ShellIntegrationMarker,
    ) -> ShellMarkerTransition {
        use ShellIntegrationMarker::{CommandExecuted, CommandFinished, CommandStart, PromptStart};
        use ShellIntegrationState::{CommandInput, CommandOutput, Prompt};

        let nested_prompt =
            self.current_state == ShellIntegrationState::CommandOutput && marker == PromptStart;
        if nested_prompt && self.lifecycle_stack.len() >= MAX_NESTED_SHELL_LIFECYCLES {
            return ShellMarkerTransition::Ignored;
        }

        let transition = match (self.current_state, marker) {
            (Prompt, PromptStart)
            | (CommandInput, CommandStart)
            | (CommandOutput, CommandExecuted) => ShellMarkerTransition::Ignored,
            (_, PromptStart) => ShellMarkerTransition::Accepted,
            (Prompt, CommandStart) => ShellMarkerTransition::Accepted,
            (CommandInput, CommandExecuted) => ShellMarkerTransition::Accepted,
            (CommandOutput, CommandFinished) => ShellMarkerTransition::Accepted,
            (CommandInput, CommandFinished) => ShellMarkerTransition::Aborted,
            _ => ShellMarkerTransition::Ignored,
        };

        match transition {
            ShellMarkerTransition::Accepted => {
                if nested_prompt {
                    self.lifecycle_stack.push(ShellLifecycleFrame {
                        marker: self.current_marker,
                        state: self.current_state,
                        command: self.current_command.clone(),
                        exit_code: self.last_exit_code,
                    });
                }
                self.set_marker(marker);
                if marker == PromptStart {
                    self.current_command = None;
                }
            }
            ShellMarkerTransition::Aborted => {
                self.current_marker = None;
                self.current_state = ShellIntegrationState::Aborted;
                self.current_command = None;
            }
            ShellMarkerTransition::Ignored => {}
        }

        transition
    }

    /// Restore a suspended outer command-output lifecycle after a nested shell
    /// finishes or aborts. Returns whether an outer lifecycle was resumed.
    pub(crate) fn restore_parent_lifecycle(&mut self) -> bool {
        let Some(parent) = self.lifecycle_stack.pop() else {
            return false;
        };
        self.current_marker = parent.marker;
        self.current_state = parent.state;
        self.current_command = parent.command;
        self.last_exit_code = parent.exit_code;
        true
    }

    /// Whether a completed or aborted child has a suspended parent lifecycle.
    ///
    /// Restoration is deferred until a consecutive `D` marker proves that the
    /// parent command itself returned. A following `A` starts another command
    /// cycle in the same long-lived child shell and retains the parent frame.
    pub(crate) fn has_pending_parent_lifecycle(&self) -> bool {
        !self.lifecycle_stack.is_empty()
            && matches!(
                self.current_state,
                ShellIntegrationState::Finished | ShellIntegrationState::Aborted
            )
    }

    /// Number of bounded outer lifecycles suspended by nested shells.
    #[cfg(test)]
    pub(crate) fn suspended_lifecycle_count(&self) -> usize {
        self.lifecycle_stack.len()
    }

    /// Set the current command
    pub fn set_command(&mut self, command: String) {
        self.current_command = Some(command);
    }

    /// Get the current command
    pub fn command(&self) -> Option<&str> {
        self.current_command.as_deref()
    }

    /// Set the exit code
    pub fn set_exit_code(&mut self, code: i32) {
        self.last_exit_code = Some(code);
    }

    /// Get the last exit code
    pub fn exit_code(&self) -> Option<i32> {
        self.last_exit_code
    }

    /// Set current working directory
    pub fn set_cwd(&mut self, cwd: String) {
        self.cwd = Some(cwd);
    }

    /// Get current working directory
    pub fn cwd(&self) -> Option<&str> {
        self.cwd.as_deref()
    }

    /// Set hostname from OSC 7
    pub fn set_hostname(&mut self, hostname: Option<String>) {
        self.hostname = hostname;
    }

    /// Get hostname from OSC 7
    /// Returns None if localhost (implicit in file:///path format)
    pub fn hostname(&self) -> Option<&str> {
        self.hostname.as_deref()
    }

    /// Set username from OSC 7
    pub fn set_username(&mut self, username: Option<String>) {
        self.username = username;
    }

    /// Get username from OSC 7
    pub fn username(&self) -> Option<&str> {
        self.username.as_deref()
    }

    /// Check if we're in a prompt
    pub fn in_prompt(&self) -> bool {
        matches!(
            self.current_marker,
            Some(ShellIntegrationMarker::PromptStart)
        )
    }

    /// Check if we're in command input
    pub fn in_command_input(&self) -> bool {
        matches!(
            self.current_marker,
            Some(ShellIntegrationMarker::CommandStart)
        )
    }

    /// Check if we're in command output
    pub fn in_command_output(&self) -> bool {
        matches!(
            self.current_marker,
            Some(ShellIntegrationMarker::CommandExecuted)
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shell_integration_markers() {
        let mut si = ShellIntegration::new();

        si.set_marker(ShellIntegrationMarker::PromptStart);
        assert!(si.in_prompt());

        si.set_marker(ShellIntegrationMarker::CommandStart);
        assert!(si.in_command_input());

        si.set_marker(ShellIntegrationMarker::CommandExecuted);
        assert!(si.in_command_output());
    }

    #[test]
    fn test_shell_integration_command() {
        let mut si = ShellIntegration::new();

        si.set_command("ls -la".to_string());
        assert_eq!(si.command(), Some("ls -la"));

        si.set_exit_code(0);
        assert_eq!(si.exit_code(), Some(0));
    }

    #[test]
    fn test_shell_integration_cwd() {
        let mut si = ShellIntegration::new();

        si.set_cwd("/home/user".to_string());
        assert_eq!(si.cwd(), Some("/home/user"));
    }

    #[test]
    fn test_shell_integration_default() {
        let si = ShellIntegration::default();
        assert!(si.marker().is_none());
        assert!(si.command().is_none());
        assert!(si.exit_code().is_none());
        assert!(si.cwd().is_none());
        assert!(si.hostname().is_none());
        assert!(si.username().is_none());
    }

    #[test]
    fn test_shell_integration_marker_transitions() {
        let mut si = ShellIntegration::new();

        si.set_marker(ShellIntegrationMarker::PromptStart);
        assert_eq!(si.marker(), Some(ShellIntegrationMarker::PromptStart));

        si.set_marker(ShellIntegrationMarker::CommandStart);
        assert_eq!(si.marker(), Some(ShellIntegrationMarker::CommandStart));

        si.set_marker(ShellIntegrationMarker::CommandExecuted);
        assert_eq!(si.marker(), Some(ShellIntegrationMarker::CommandExecuted));

        si.set_marker(ShellIntegrationMarker::CommandFinished);
        assert_eq!(si.marker(), Some(ShellIntegrationMarker::CommandFinished));
    }

    #[test]
    fn test_shell_integration_exit_codes() {
        let mut si = ShellIntegration::new();

        si.set_exit_code(0);
        assert_eq!(si.exit_code(), Some(0));

        si.set_exit_code(1);
        assert_eq!(si.exit_code(), Some(1));

        si.set_exit_code(127);
        assert_eq!(si.exit_code(), Some(127));

        si.set_exit_code(-1);
        assert_eq!(si.exit_code(), Some(-1));
    }

    #[test]
    fn test_shell_integration_command_updates() {
        let mut si = ShellIntegration::new();

        si.set_command("echo hello".to_string());
        assert_eq!(si.command(), Some("echo hello"));

        si.set_command("ls -la".to_string());
        assert_eq!(si.command(), Some("ls -la"));
    }

    #[test]
    fn test_shell_integration_cwd_updates() {
        let mut si = ShellIntegration::new();

        si.set_cwd("/home/user".to_string());
        assert_eq!(si.cwd(), Some("/home/user"));

        si.set_cwd("/tmp".to_string());
        assert_eq!(si.cwd(), Some("/tmp"));
    }

    #[test]
    fn test_shell_integration_in_prompt_states() {
        let mut si = ShellIntegration::new();

        assert!(!si.in_prompt());

        si.set_marker(ShellIntegrationMarker::PromptStart);
        assert!(si.in_prompt());

        si.set_marker(ShellIntegrationMarker::CommandStart);
        assert!(!si.in_prompt());
    }

    #[test]
    fn test_shell_integration_in_command_input_states() {
        let mut si = ShellIntegration::new();

        assert!(!si.in_command_input());

        si.set_marker(ShellIntegrationMarker::CommandStart);
        assert!(si.in_command_input());

        si.set_marker(ShellIntegrationMarker::CommandExecuted);
        assert!(!si.in_command_input());
    }

    #[test]
    fn test_shell_integration_in_command_output_states() {
        let mut si = ShellIntegration::new();

        assert!(!si.in_command_output());

        si.set_marker(ShellIntegrationMarker::CommandExecuted);
        assert!(si.in_command_output());

        si.set_marker(ShellIntegrationMarker::CommandFinished);
        assert!(!si.in_command_output());
    }

    #[test]
    fn test_shell_integration_full_workflow() {
        let mut si = ShellIntegration::new();

        // Start prompt
        si.set_marker(ShellIntegrationMarker::PromptStart);
        assert!(si.in_prompt());

        // User starts typing command
        si.set_marker(ShellIntegrationMarker::CommandStart);
        si.set_command("echo hello".to_string());
        assert!(si.in_command_input());
        assert_eq!(si.command(), Some("echo hello"));

        // Command executes
        si.set_marker(ShellIntegrationMarker::CommandExecuted);
        assert!(si.in_command_output());

        // Command finishes
        si.set_marker(ShellIntegrationMarker::CommandFinished);
        si.set_exit_code(0);
        assert!(!si.in_command_output());
        assert_eq!(si.exit_code(), Some(0));
    }

    #[test]
    fn test_shell_integration_empty_command() {
        let mut si = ShellIntegration::new();
        si.set_command("".to_string());
        assert_eq!(si.command(), Some(""));
    }

    #[test]
    fn test_shell_integration_marker_equality() {
        assert_eq!(
            ShellIntegrationMarker::PromptStart,
            ShellIntegrationMarker::PromptStart
        );
        assert_ne!(
            ShellIntegrationMarker::PromptStart,
            ShellIntegrationMarker::CommandStart
        );
    }

    #[test]
    fn test_shell_integration_clone() {
        let mut si = ShellIntegration::new();
        si.set_marker(ShellIntegrationMarker::PromptStart);
        si.set_command("test".to_string());
        si.set_exit_code(0);
        si.set_cwd("/home".to_string());
        si.set_hostname(Some("remote-host".to_string()));
        si.set_username(Some("alice".to_string()));

        let cloned = si.clone();
        assert_eq!(cloned.marker(), si.marker());
        assert_eq!(cloned.command(), si.command());
        assert_eq!(cloned.exit_code(), si.exit_code());
        assert_eq!(cloned.cwd(), si.cwd());
        assert_eq!(cloned.hostname(), si.hostname());
        assert_eq!(cloned.username(), si.username());
    }

    #[test]
    fn test_shell_integration_hostname() {
        let mut si = ShellIntegration::new();

        // Initially None
        assert!(si.hostname().is_none());

        // Set hostname
        si.set_hostname(Some("remote-server".to_string()));
        assert_eq!(si.hostname(), Some("remote-server"));

        // Clear hostname
        si.set_hostname(None);
        assert!(si.hostname().is_none());
    }

    #[test]
    fn test_shell_integration_username() {
        let mut si = ShellIntegration::new();

        assert!(si.username().is_none());

        si.set_username(Some("alice".to_string()));
        assert_eq!(si.username(), Some("alice"));

        si.set_username(None);
        assert!(si.username().is_none());
    }

    #[test]
    fn test_shell_integration_hostname_updates() {
        let mut si = ShellIntegration::new();

        si.set_hostname(Some("server1".to_string()));
        assert_eq!(si.hostname(), Some("server1"));

        si.set_hostname(Some("server2".to_string()));
        assert_eq!(si.hostname(), Some("server2"));

        si.set_hostname(None);
        assert!(si.hostname().is_none());
    }

    #[test]
    fn debug_output_redacts_shell_context_values() {
        let mut si = ShellIntegration::new();
        si.set_marker(ShellIntegrationMarker::CommandExecuted);
        si.set_command("command-secret-canary".to_string());
        si.set_cwd("/cwd-secret-canary".to_string());
        si.set_hostname(Some("host-secret-canary".to_string()));
        si.set_username(Some("user-secret-canary".to_string()));

        let debug = format!("{si:?}");
        for secret in [
            "command-secret-canary",
            "/cwd-secret-canary",
            "host-secret-canary",
            "user-secret-canary",
        ] {
            assert!(!debug.contains(secret), "Debug leaked {secret}");
        }
        assert!(debug.contains("has_current_command: true"));
        assert!(debug.contains("has_cwd: true"));
    }
}
