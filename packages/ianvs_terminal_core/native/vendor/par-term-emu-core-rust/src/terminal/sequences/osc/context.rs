//! UAPI OSC 3008 terminal-context parser.

use crate::terminal::{
    Terminal, TerminalContextEndMetadata, TerminalContextExit, TerminalContextMetadata,
    TerminalContextType, MAX_TERMINAL_CONTEXT_ID_BYTES, MAX_TERMINAL_CONTEXT_TEXT_BYTES,
};

fn unescape(value: &[u8], max_bytes: usize) -> Option<String> {
    let mut decoded = Vec::with_capacity(value.len().min(max_bytes));
    let mut index = 0;
    while index < value.len() {
        if value[index..].starts_with(b"\\x3b") {
            decoded.push(b';');
            index += 4;
        } else if value[index..].starts_with(b"\\x5c") {
            decoded.push(b'\\');
            index += 4;
        } else {
            decoded.push(value[index]);
            index += 1;
        }
        if decoded.len() > max_bytes {
            return None;
        }
    }
    let decoded = std::str::from_utf8(&decoded).ok()?;
    if decoded.chars().any(char::is_control) {
        return None;
    }
    Some(decoded.to_string())
}

fn context_id(value: &[u8]) -> Option<String> {
    let value = unescape(value, MAX_TERMINAL_CONTEXT_ID_BYTES)?;
    (!value.is_empty()
        && value
            .as_bytes()
            .iter()
            .all(|byte| (b' '..=b'~').contains(byte)))
    .then_some(value)
}

fn text(value: &[u8]) -> Option<String> {
    unescape(value, MAX_TERMINAL_CONTEXT_TEXT_BYTES)
}

fn numeric(value: &[u8]) -> Option<u64> {
    let value = std::str::from_utf8(value).ok()?;
    (!value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit()))
        .then(|| value.parse().ok())?
}

fn signal(value: &[u8]) -> Option<String> {
    let value = std::str::from_utf8(value).ok()?;
    (value.len() <= 64
        && value.starts_with("SIG")
        && value
            .bytes()
            .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit()))
    .then(|| value.to_string())
}

fn split_key_value(parameter: &[u8]) -> Option<(&[u8], &[u8])> {
    let separator = parameter.iter().position(|byte| *byte == b'=')?;
    Some((&parameter[..separator], &parameter[separator + 1..]))
}

fn pairs<'a>(params: &'a [&'a [u8]]) -> impl Iterator<Item = (&'a [u8], &'a [u8])> {
    params
        .iter()
        .skip(2)
        .filter_map(|parameter| split_key_value(parameter))
}

fn parse_start_metadata(params: &[&[u8]]) -> TerminalContextMetadata {
    let mut metadata = TerminalContextMetadata::default();
    for (key, value) in pairs(params) {
        match key {
            b"type" => {
                metadata.context_type = std::str::from_utf8(value)
                    .ok()
                    .and_then(TerminalContextType::parse)
            }
            b"user" => metadata.user = text(value),
            b"hostname" => metadata.hostname = text(value),
            b"machineid" => metadata.machine_id = text(value),
            b"bootid" => metadata.boot_id = text(value),
            b"pid" => metadata.pid = numeric(value),
            b"pidfdid" => metadata.pidfd_id = numeric(value),
            b"comm" => metadata.command_name = text(value),
            _ => {}
        }
    }

    for (key, value) in pairs(params) {
        match (metadata.context_type, key) {
            (Some(TerminalContextType::Shell | TerminalContextType::Command), b"cwd") => {
                metadata.cwd = text(value)
            }
            (Some(TerminalContextType::Command), b"cmdline") => metadata.command_line = text(value),
            (Some(TerminalContextType::Vm), b"vm") => metadata.vm = text(value),
            (Some(TerminalContextType::Container), b"container") => {
                metadata.container = text(value)
            }
            (
                Some(
                    TerminalContextType::Elevate
                    | TerminalContextType::ChangePrivileges
                    | TerminalContextType::Vm
                    | TerminalContextType::Container
                    | TerminalContextType::Remote
                    | TerminalContextType::Session,
                ),
                b"targetuser",
            ) => metadata.target_user = text(value),
            (Some(TerminalContextType::Remote), b"targethost") => {
                metadata.target_host = text(value)
            }
            (Some(TerminalContextType::Session), b"sessionid") => metadata.session_id = text(value),
            _ => {}
        }
    }
    metadata
}

fn parse_end_metadata(params: &[&[u8]]) -> TerminalContextEndMetadata {
    let mut metadata = TerminalContextEndMetadata::default();
    for (key, value) in pairs(params) {
        match key {
            b"exit" => {
                metadata.exit = std::str::from_utf8(value)
                    .ok()
                    .and_then(TerminalContextExit::parse)
            }
            b"status" => {
                metadata.status = numeric(value).and_then(|value| u8::try_from(value).ok())
            }
            b"signal" => metadata.signal = signal(value),
            _ => {}
        }
    }
    metadata
}

impl Terminal {
    pub(crate) fn handle_osc3008(&mut self, params: &[&[u8]]) {
        let Some((operation, raw_id)) = params
            .get(1)
            .and_then(|parameter| split_key_value(parameter))
        else {
            return;
        };
        let Some(id) = context_id(raw_id) else {
            return;
        };

        let event = match operation {
            b"start" => self
                .terminal_context_stack
                .start(id, parse_start_metadata(params)),
            b"end" => self
                .terminal_context_stack
                .end(&id, parse_end_metadata(params)),
            _ => None,
        };
        if let Some(event) = event {
            self.terminal_events
                .push(crate::terminal::TerminalEvent::TerminalContextChanged(
                    Box::new(event),
                ));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal::{TerminalContextAction, MAX_TERMINAL_CONTEXT_DEPTH};

    fn context_events(terminal: &mut Terminal) -> Vec<crate::terminal::TerminalContextEvent> {
        terminal
            .poll_events()
            .into_iter()
            .filter_map(|event| match event {
                crate::terminal::TerminalEvent::TerminalContextChanged(event) => Some(*event),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn starts_nested_contexts_and_decodes_textual_escapes() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]3008;start=root;type=shell;user=a\\x3bb;cwd=/tmp\\x5cdir\x1b\\");
        terminal.process(b"\x1b]3008;start=child;type=command;cmdline=echo hi\x07");
        assert_eq!(terminal.terminal_context_stack.contexts().len(), 2);
        let root = &terminal.terminal_context_stack.contexts()[0];
        assert_eq!(root.metadata.user.as_deref(), Some("a;b"));
        assert_eq!(root.metadata.cwd.as_deref(), Some("/tmp\\dir"));
        assert_eq!(context_events(&mut terminal).len(), 2);
    }

    #[test]
    fn repeated_start_replaces_metadata_and_implicitly_ends_children() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]3008;start=root;type=shell;user=old\x1b\\");
        terminal.process(b"\x1b]3008;start=child;type=command\x1b\\");
        terminal.process(b"\x1b]3008;start=root;type=shell;user=new\x1b\\");
        let event = context_events(&mut terminal).pop().unwrap();
        assert_eq!(event.action, TerminalContextAction::Update);
        assert_eq!(event.implicit_closed_count, 1);
        assert_eq!(event.metadata.user.as_deref(), Some("new"));
        assert_eq!(terminal.terminal_context_stack.contexts().len(), 1);
    }

    #[test]
    fn known_parent_end_closes_descendants_and_unknown_end_is_ignored() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]3008;start=root;type=shell\x1b\\");
        terminal.process(b"\x1b]3008;start=child;type=command\x1b\\");
        let _ = context_events(&mut terminal);
        terminal.process(b"\x1b]3008;end=missing;exit=failure\x1b\\");
        assert!(context_events(&mut terminal).is_empty());
        terminal.process(b"\x1b]3008;end=root;exit=success;status=0\x1b\\");
        let event = context_events(&mut terminal).pop().unwrap();
        assert_eq!(event.action, TerminalContextAction::End);
        assert_eq!(event.implicit_closed_count, 1);
        assert_eq!(event.end_metadata.unwrap().status, Some(0));
        assert!(terminal.terminal_context_stack.contexts().is_empty());
    }

    #[test]
    fn invalid_fields_are_ignored_without_losing_valid_fields() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(
            b"\x1b]3008;start=ctx;type=command;pid=nope;cwd=/ok;cmdline=ok;targethost=wrong\x1b\\",
        );
        let metadata = &terminal.terminal_context_stack.active().unwrap().metadata;
        assert_eq!(metadata.pid, None);
        assert_eq!(metadata.cwd.as_deref(), Some("/ok"));
        assert_eq!(metadata.command_line.as_deref(), Some("ok"));
        assert_eq!(metadata.target_host, None);
    }

    #[test]
    fn rejects_new_context_at_depth_limit_but_keeps_existing_stack() {
        let mut terminal = Terminal::new(80, 24);
        for index in 0..MAX_TERMINAL_CONTEXT_DEPTH + 1 {
            terminal.process(format!("\x1b]3008;start=c{index};type=subcontext\x1b\\").as_bytes());
        }
        assert_eq!(
            terminal.terminal_context_stack.contexts().len(),
            MAX_TERMINAL_CONTEXT_DEPTH
        );
        assert_eq!(
            context_events(&mut terminal).len(),
            MAX_TERMINAL_CONTEXT_DEPTH
        );
    }

    #[test]
    fn rejects_invalid_identity_and_oversized_or_control_text_fields() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]3008;start=;type=shell\x1b\\");
        terminal.process(b"\x1b]3008;start=unicode-\xc3\xa9;type=shell\x1b\\");
        let long = "x".repeat(MAX_TERMINAL_CONTEXT_TEXT_BYTES + 1);
        terminal.process(
            format!("\x1b]3008;start=ok;type=shell;user={long};hostname=valid\x1b\\").as_bytes(),
        );
        assert_eq!(terminal.terminal_context_stack.contexts().len(), 1);
        let metadata = &terminal.terminal_context_stack.active().unwrap().metadata;
        assert_eq!(metadata.user, None);
        assert_eq!(metadata.hostname.as_deref(), Some("valid"));
    }

    #[test]
    fn context_hierarchy_survives_snapshot_restore_and_ris() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]3008;start=root;type=shell;cwd=/work\x1b\\");
        terminal.process(b"\x1b]3008;start=child;type=command;cmdline=build\x1b\\");
        let snapshot = terminal.capture_snapshot();

        terminal.reset();
        assert_eq!(terminal.terminal_context_stack.contexts().len(), 2);
        assert_eq!(
            terminal.terminal_context_stack.active().unwrap().id,
            "child"
        );

        let mut restored = Terminal::new(80, 24);
        restored.restore_from_snapshot(snapshot);
        assert_eq!(restored.terminal_context_stack.contexts().len(), 2);
        assert_eq!(
            restored
                .terminal_context_stack
                .active()
                .unwrap()
                .metadata
                .command_line
                .as_deref(),
            Some("build")
        );
    }

    #[test]
    fn osc3008_survives_every_byte_split_with_bel_or_st_terminators() {
        for terminator in [b"\x07".as_slice(), b"\x1b\\".as_slice()] {
            let mut sequence =
                b"\x1b]3008;start=split;type=command;cwd=/tmp;cmdline=echo \xe4\xbd\xa0\xe5\xa5\xbd"
                    .to_vec();
            sequence.extend_from_slice(terminator);
            for split in 1..sequence.len() {
                let mut terminal = Terminal::new(80, 24);
                terminal.process(&sequence[..split]);
                terminal.process(&sequence[split..]);
                let events = context_events(&mut terminal);
                assert_eq!(events.len(), 1, "split={split}, terminator={terminator:?}");
                assert_eq!(
                    events[0].metadata.command_line.as_deref(),
                    Some("echo 你好")
                );
            }
        }
    }
}
