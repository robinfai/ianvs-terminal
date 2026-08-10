//! Bounded semantic context state for the UAPI OSC 3008 protocol.
//!
//! Context data is untrusted terminal metadata.  This module deliberately
//! stores and reports it without granting any host-side capability.

/// Maximum number of simultaneously nested OSC 3008 contexts.
pub const MAX_TERMINAL_CONTEXT_DEPTH: usize = 32;
/// Maximum decoded UTF-8 bytes retained for one metadata field.
pub const MAX_TERMINAL_CONTEXT_TEXT_BYTES: usize = 255;
/// Maximum decoded bytes retained for a context identity.
pub const MAX_TERMINAL_CONTEXT_ID_BYTES: usize = 64;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TerminalContextType {
    Boot,
    Container,
    Vm,
    Elevate,
    ChangePrivileges,
    Subcontext,
    Remote,
    Shell,
    Command,
    App,
    Service,
    Session,
}

impl TerminalContextType {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Boot => "boot",
            Self::Container => "container",
            Self::Vm => "vm",
            Self::Elevate => "elevate",
            Self::ChangePrivileges => "chpriv",
            Self::Subcontext => "subcontext",
            Self::Remote => "remote",
            Self::Shell => "shell",
            Self::Command => "command",
            Self::App => "app",
            Self::Service => "service",
            Self::Session => "session",
        }
    }

    pub(crate) fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "boot" => Self::Boot,
            "container" => Self::Container,
            "vm" => Self::Vm,
            "elevate" => Self::Elevate,
            "chpriv" => Self::ChangePrivileges,
            "subcontext" => Self::Subcontext,
            "remote" => Self::Remote,
            "shell" => Self::Shell,
            "command" => Self::Command,
            "app" => Self::App,
            "service" => Self::Service,
            "session" => Self::Session,
            _ => return None,
        })
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TerminalContextMetadata {
    pub context_type: Option<TerminalContextType>,
    pub user: Option<String>,
    pub hostname: Option<String>,
    pub machine_id: Option<String>,
    pub boot_id: Option<String>,
    pub pid: Option<u64>,
    pub pidfd_id: Option<u64>,
    pub command_name: Option<String>,
    pub cwd: Option<String>,
    pub command_line: Option<String>,
    pub vm: Option<String>,
    pub container: Option<String>,
    pub target_user: Option<String>,
    pub target_host: Option<String>,
    pub session_id: Option<String>,
}

impl TerminalContextMetadata {
    pub(crate) fn retained_bytes(&self) -> usize {
        let length = |value: &Option<String>| value.as_ref().map_or(0, String::len);
        [
            &self.user,
            &self.hostname,
            &self.machine_id,
            &self.boot_id,
            &self.command_name,
            &self.cwd,
            &self.command_line,
            &self.vm,
            &self.container,
            &self.target_user,
            &self.target_host,
            &self.session_id,
        ]
        .into_iter()
        .fold(0usize, |total, value| total.saturating_add(length(value)))
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TerminalContextExit {
    Success,
    Failure,
    Crash,
    Interrupt,
}

impl TerminalContextExit {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Success => "success",
            Self::Failure => "failure",
            Self::Crash => "crash",
            Self::Interrupt => "interrupt",
        }
    }

    pub(crate) fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "success" => Self::Success,
            "failure" => Self::Failure,
            "crash" => Self::Crash,
            "interrupt" => Self::Interrupt,
            _ => return None,
        })
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TerminalContextEndMetadata {
    pub exit: Option<TerminalContextExit>,
    pub status: Option<u8>,
    pub signal: Option<String>,
}

impl TerminalContextEndMetadata {
    pub(crate) fn retained_bytes(&self) -> usize {
        self.signal.as_ref().map_or(0, String::len)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TerminalContext {
    pub id: String,
    pub metadata: TerminalContextMetadata,
}

impl TerminalContext {
    pub(crate) fn retained_bytes(&self) -> usize {
        self.id.len().saturating_add(self.metadata.retained_bytes())
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TerminalContextAction {
    Start,
    Update,
    End,
}

impl TerminalContextAction {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Start => "start",
            Self::Update => "update",
            Self::End => "end",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TerminalContextEvent {
    pub action: TerminalContextAction,
    pub id: String,
    pub depth: usize,
    pub active: bool,
    pub metadata: TerminalContextMetadata,
    pub end_metadata: Option<TerminalContextEndMetadata>,
    pub implicit_closed_count: usize,
}

impl TerminalContextEvent {
    pub(crate) fn retained_bytes(&self) -> usize {
        self.id
            .len()
            .saturating_add(self.metadata.retained_bytes())
            .saturating_add(
                self.end_metadata
                    .as_ref()
                    .map_or(0, TerminalContextEndMetadata::retained_bytes),
            )
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TerminalContextStack {
    contexts: Vec<TerminalContext>,
}

impl TerminalContextStack {
    pub fn contexts(&self) -> &[TerminalContext] {
        &self.contexts
    }

    pub fn active(&self) -> Option<&TerminalContext> {
        self.contexts.last()
    }

    pub(crate) fn retained_bytes(&self) -> usize {
        self.contexts.iter().fold(0usize, |total, context| {
            total.saturating_add(context.retained_bytes())
        })
    }

    pub(crate) fn start(
        &mut self,
        id: String,
        metadata: TerminalContextMetadata,
    ) -> Option<TerminalContextEvent> {
        if let Some(index) = self.contexts.iter().position(|context| context.id == id) {
            let implicit_closed_count = self.contexts.len().saturating_sub(index + 1);
            self.contexts.truncate(index + 1);
            self.contexts[index].metadata = metadata.clone();
            return Some(TerminalContextEvent {
                action: TerminalContextAction::Update,
                id,
                depth: self.contexts.len(),
                active: true,
                metadata,
                end_metadata: None,
                implicit_closed_count,
            });
        }

        if self.contexts.len() >= MAX_TERMINAL_CONTEXT_DEPTH {
            return None;
        }
        self.contexts.push(TerminalContext {
            id: id.clone(),
            metadata: metadata.clone(),
        });
        Some(TerminalContextEvent {
            action: TerminalContextAction::Start,
            id,
            depth: self.contexts.len(),
            active: true,
            metadata,
            end_metadata: None,
            implicit_closed_count: 0,
        })
    }

    pub(crate) fn end(
        &mut self,
        id: &str,
        end_metadata: TerminalContextEndMetadata,
    ) -> Option<TerminalContextEvent> {
        let index = self.contexts.iter().position(|context| context.id == id)?;
        let context = self.contexts[index].clone();
        let implicit_closed_count = self.contexts.len().saturating_sub(index + 1);
        self.contexts.truncate(index);
        Some(TerminalContextEvent {
            action: TerminalContextAction::End,
            id: context.id,
            depth: self.contexts.len(),
            active: false,
            metadata: context.metadata,
            end_metadata: Some(end_metadata),
            implicit_closed_count,
        })
    }
}
