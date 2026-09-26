//! Native hook normalization, independent of the bounded UI event queue. The
//! session calls this with its monotonic recording clock, never shell wall time.
use super::{RecordingError, SemanticEvent, SemanticKind};
use serde_json::Value;
use std::collections::HashMap;

const MAX_CONTEXTS: usize = 64;

#[derive(Clone, Debug)]
pub struct TimelineContext {
    pub id: String,
    pub cwd: Option<String>,
    pub hostname: Option<String>,
}

#[derive(Clone)]
struct ActiveCommand {
    id: String,
    text: String,
    cwd: Option<String>,
    hostname: Option<String>,
}
#[derive(Clone)]
struct ContextState {
    context: TimelineContext,
    available: Option<bool>,
    active: Option<ActiveCommand>,
}

#[derive(Clone)]
pub struct HookTimeline {
    contexts: HashMap<String, ContextState>,
    current_context: String,
    next_command: u64,
    last_offset: u64,
}

impl HookTimeline {
    pub fn new(context: TimelineContext) -> Result<Self, RecordingError> {
        context_event(0, &context, SemanticKind::ContextChanged).validate()?;
        let current_context = context.id.clone();
        Ok(Self {
            contexts: HashMap::from([(
                context.id.clone(),
                ContextState {
                    context,
                    available: None,
                    active: None,
                },
            )]),
            current_context,
            next_command: 0,
            last_offset: 0,
        })
    }

    pub(crate) fn for_recording(&self, root_hostname: Option<&str>) -> Self {
        let mut copy = self.clone();
        copy.last_offset = 0;
        if let Some(root) = copy.contexts.get_mut("root")
            && root.context.hostname.is_none()
        {
            root.context.hostname = root_hostname.map(str::to_owned);
        }
        copy
    }

    pub(crate) fn observe_live(&mut self, payload: &Value, context_only: bool) {
        let Some(offset) = self.last_offset.checked_add(1) else {
            return;
        };
        if context_only {
            let _ = self.observe_context(offset, payload);
        } else {
            let _ = self.observe_hook(offset, payload);
        }
    }

    pub fn initial_events(&self) -> Vec<SemanticEvent> {
        let state = &self.contexts[&self.current_context];
        let context = &state.context;
        vec![
            context_event(0, context, SemanticKind::ContextChanged),
            context_event(
                0,
                context,
                if state.available == Some(true) {
                    SemanticKind::HookAvailable
                } else {
                    SemanticKind::HookUnavailable
                },
            ),
        ]
    }

    /// Preserve the exact hook command/arguments. Unmatched finishes and lost
    /// boundaries are represented as coverage gaps, never fabricated starts.
    pub fn observe_hook(
        &mut self,
        offset: u64,
        payload: &Value,
    ) -> Result<Vec<SemanticEvent>, RecordingError> {
        if offset < self.last_offset {
            return Err(RecordingError::NonMonotonicTime);
        }
        let Some(hook) = payload.get("hook").and_then(Value::as_str) else {
            return Ok(vec![]);
        };
        if !matches!(
            hook,
            "preexec"
                | "command_finished"
                | "precmd"
                | "precmd.pwd"
                | "bootstrap.checking"
                | "bootstrap.ready"
                | "bootstrap.resume"
        ) {
            return Ok(vec![]);
        }
        let id = match payload.get("context_id") {
            None | Some(Value::Null) => self.current_context.clone(),
            Some(Value::String(id)) if !id.is_empty() => id.clone(),
            _ => return Err(RecordingError::InvalidSemanticEvent),
        };
        let existing = self.contexts.get(&id);
        let mut state = existing.cloned().unwrap_or_else(|| ContextState {
            context: TimelineContext {
                id: id.clone(),
                cwd: None,
                hostname: None,
            },
            available: None,
            active: None,
        });
        let mut records = Vec::new();
        let mut next_command = self.next_command;
        let mut retired = Vec::new();
        if hook == "bootstrap.resume"
            && let Some(value) = payload.get("retired_contexts")
        {
            let values = value
                .as_array()
                .ok_or(RecordingError::InvalidSemanticEvent)?;
            if values.len() > MAX_CONTEXTS {
                return Err(RecordingError::InvalidSemanticEvent);
            }
            for value in values {
                let retired_id = value.as_str().ok_or(RecordingError::InvalidSemanticEvent)?;
                if retired_id == id || retired_id.len() > 64 * 1024 {
                    return Err(RecordingError::InvalidSemanticEvent);
                }
                if retired.iter().any(|id| id == retired_id) {
                    continue;
                }
                if let Some(retired_state) = self.contexts.get(retired_id) {
                    if let Some(active) = &retired_state.active {
                        let mut gap = context_event(
                            offset,
                            &retired_state.context,
                            SemanticKind::HookUnavailable,
                        );
                        gap.command_id = Some(active.id.clone());
                        records.push(gap);
                    }
                    retired.push(retired_id.to_owned());
                }
            }
        }
        if existing.is_none() && self.contexts.len().saturating_sub(retired.len()) >= MAX_CONTEXTS {
            return Err(RecordingError::InvalidSemanticEvent);
        }
        if let Some(host) = optional_string(payload, "host")? {
            state.context.hostname = Some(host.to_owned());
        }
        if let Some(host) = optional_string(payload, "hostname")? {
            state.context.hostname = Some(host.to_owned());
        }
        if let Some(cwd) = optional_string(payload, "pwd")? {
            state.context.cwd = Some(cwd.to_owned());
        }
        if id != self.current_context || hook.starts_with("bootstrap.") || hook == "precmd.pwd" {
            records.push(context_event(
                offset,
                &state.context,
                SemanticKind::ContextChanged,
            ));
        }
        match hook {
            "preexec" => {
                let text = optional_string(payload, "command")?
                    .filter(|s| !s.is_empty())
                    .ok_or(RecordingError::InvalidSemanticEvent)?;
                if let Some(active) = &state.active {
                    let mut gap =
                        context_event(offset, &state.context, SemanticKind::HookUnavailable);
                    gap.command_id = Some(active.id.clone());
                    records.push(gap);
                }
                set_availability(offset, &mut state, true, &mut records);
                let command_id = allocate_command(&mut next_command)?;
                let active = ActiveCommand {
                    id: command_id,
                    text: text.to_owned(),
                    cwd: state.context.cwd.clone(),
                    hostname: state.context.hostname.clone(),
                };
                records.push(command_event(
                    offset,
                    &state.context.id,
                    &active,
                    SemanticKind::CommandStarted,
                    None,
                ));
                state.active = Some(active);
            }
            "command_finished" => {
                let text = optional_string(payload, "command")?;
                let exit_code = match payload.get("exit_code") {
                    None | Some(Value::Null) => None,
                    Some(value) => Some(
                        value
                            .as_i64()
                            .and_then(|v| i32::try_from(v).ok())
                            .ok_or(RecordingError::InvalidSemanticEvent)?,
                    ),
                };
                let active = state
                    .active
                    .take()
                    .filter(|active| text.is_none_or(|text| text == active.text));
                let active = match active {
                    Some(active) => active,
                    None => {
                        records.push(context_event(
                            offset,
                            &state.context,
                            SemanticKind::HookUnavailable,
                        ));
                        ActiveCommand {
                            id: allocate_command(&mut next_command)?,
                            text: text.unwrap_or("").to_owned(),
                            cwd: state.context.cwd.clone(),
                            hostname: state.context.hostname.clone(),
                        }
                    }
                };
                set_availability(offset, &mut state, true, &mut records);
                records.push(command_event(
                    offset,
                    &state.context.id,
                    &active,
                    SemanticKind::CommandFinished,
                    exit_code,
                ));
            }
            "bootstrap.checking" => set_availability(offset, &mut state, false, &mut records),
            "bootstrap.ready" => {
                let registered = payload
                    .get("registered")
                    .and_then(Value::as_bool)
                    .ok_or(RecordingError::InvalidSemanticEvent)?;
                set_availability(offset, &mut state, registered, &mut records);
            }
            "precmd" | "precmd.pwd" => set_availability(offset, &mut state, true, &mut records),
            "bootstrap.resume" => {}
            _ => unreachable!(),
        }
        for event in &records {
            event.validate()?;
        }
        // Commit only after every field and generated event has passed validation.
        for retired_id in retired {
            self.contexts.remove(&retired_id);
        }
        self.contexts.insert(id.clone(), state);
        self.current_context = id;
        self.next_command = next_command;
        self.last_offset = offset;
        Ok(records)
    }

    /// OSC context is supplemental metadata. It never invents command events
    /// from rendered text or duplicates the shell's preexec/finished hooks.
    pub fn observe_context(
        &mut self,
        offset: u64,
        payload: &Value,
    ) -> Result<Vec<SemanticEvent>, RecordingError> {
        if offset < self.last_offset {
            return Err(RecordingError::NonMonotonicTime);
        }
        let mut context = self.contexts[&self.current_context].context.clone();
        if let Some(host) = optional_string(payload, "hostname")? {
            context.hostname = Some(host.to_owned());
        }
        if let Some(cwd) = optional_string(payload, "cwd")? {
            context.cwd = Some(cwd.to_owned());
        }
        if payload.get("hostname") == Some(&Value::Null) {
            context.hostname = None;
        }
        let event = context_event(offset, &context, SemanticKind::ContextChanged);
        event.validate()?;
        self.contexts
            .get_mut(&self.current_context)
            .unwrap()
            .context = context;
        self.last_offset = offset;
        Ok(vec![event])
    }
}

fn allocate_command(next: &mut u64) -> Result<String, RecordingError> {
    let id = next.to_string();
    *next = next
        .checked_add(1)
        .ok_or(RecordingError::SequenceExhausted)?;
    Ok(id)
}
fn optional_string<'a>(value: &'a Value, key: &str) -> Result<Option<&'a str>, RecordingError> {
    match value.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) if value.len() <= 64 * 1024 && !value.contains('\0') => {
            Ok(Some(value))
        }
        _ => Err(RecordingError::InvalidSemanticEvent),
    }
}
fn set_availability(
    offset: u64,
    state: &mut ContextState,
    available: bool,
    records: &mut Vec<SemanticEvent>,
) {
    if state.available != Some(available) {
        records.push(context_event(
            offset,
            &state.context,
            if available {
                SemanticKind::HookAvailable
            } else {
                SemanticKind::HookUnavailable
            },
        ));
        state.available = Some(available);
    }
}
fn context_event(offset: u64, context: &TimelineContext, kind: SemanticKind) -> SemanticEvent {
    SemanticEvent {
        offset_micros: offset,
        kind,
        context_id: context.id.clone(),
        command_id: None,
        command: None,
        cwd: context.cwd.clone(),
        hostname: context.hostname.clone(),
        exit_code: None,
    }
}
fn command_event(
    offset: u64,
    context_id: &str,
    active: &ActiveCommand,
    kind: SemanticKind,
    exit_code: Option<i32>,
) -> SemanticEvent {
    SemanticEvent {
        offset_micros: offset,
        kind,
        context_id: context_id.to_owned(),
        command_id: Some(active.id.clone()),
        command: (!active.text.is_empty()).then(|| active.text.clone()),
        cwd: active.cwd.clone(),
        hostname: active.hostname.clone(),
        exit_code,
    }
}
