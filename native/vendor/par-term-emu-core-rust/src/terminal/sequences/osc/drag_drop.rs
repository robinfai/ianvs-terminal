//! Kitty OSC 72 drag-and-drop command parsing.

use crate::terminal::drag_drop::{
    DragDropAction, DragDropCommand, MAX_OSC72_METADATA_BYTES, MAX_OSC72_PAYLOAD_BYTES,
};
use crate::terminal::{Terminal, TerminalEvent};

#[derive(Default)]
struct ParsedMetadata {
    action: Option<DragDropAction>,
    more: bool,
    identifier: Option<u32>,
    operation: Option<u32>,
    x: Option<i32>,
    y: Option<i32>,
    pixel_x: Option<i32>,
    pixel_y: Option<i32>,
}

fn parse_u32(value: &[u8]) -> Option<u32> {
    let value = std::str::from_utf8(value).ok()?;
    if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    value.parse().ok()
}

fn parse_i32(value: &[u8]) -> Option<i32> {
    let value = std::str::from_utf8(value).ok()?;
    let digits = value.strip_prefix('-').unwrap_or(value);
    if digits.is_empty() || !digits.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    value.parse().ok()
}

fn parse_metadata(metadata: &[u8]) -> Option<ParsedMetadata> {
    if metadata.len() > MAX_OSC72_METADATA_BYTES {
        return None;
    }
    let mut parsed = ParsedMetadata::default();
    for pair in metadata.split(|byte| *byte == b':') {
        if pair.is_empty() {
            continue;
        }
        let separator = pair.iter().position(|byte| *byte == b'=')?;
        let (key, value_with_separator) = pair.split_at(separator);
        let value = &value_with_separator[1..];
        match key {
            b"t" => {
                if value.len() != 1 {
                    return None;
                }
                parsed.action = DragDropAction::parse(value[0]);
                parsed.action?;
            }
            b"m" => {
                parsed.more = match value {
                    b"0" => false,
                    b"1" => true,
                    _ => return None,
                }
            }
            b"i" => {
                let identifier = parse_u32(value)?;
                if identifier == 0 {
                    return None;
                }
                parsed.identifier = Some(identifier);
            }
            b"o" => parsed.operation = Some(parse_u32(value)?),
            b"x" => parsed.x = Some(parse_i32(value)?),
            b"y" => parsed.y = Some(parse_i32(value)?),
            b"X" => parsed.pixel_x = Some(parse_i32(value)?),
            b"Y" => parsed.pixel_y = Some(parse_i32(value)?),
            // Unknown metadata is reserved for compatible protocol growth.
            _ => {}
        }
    }
    Some(parsed)
}

impl Terminal {
    pub(crate) fn handle_osc_drag_drop(&mut self, params: &[&[u8]]) {
        let metadata = params.get(1).copied().unwrap_or_default();
        let Some(parsed) = parse_metadata(metadata) else {
            return;
        };
        let payload_len = params
            .iter()
            .skip(2)
            .fold(0usize, |total, part| total.saturating_add(part.len()))
            .saturating_add(params.len().saturating_sub(3));
        if payload_len > MAX_OSC72_PAYLOAD_BYTES {
            return;
        }
        let mut payload = Vec::with_capacity(payload_len);
        for (index, part) in params.iter().skip(2).enumerate() {
            if index > 0 {
                payload.push(b';');
            }
            payload.extend_from_slice(part);
        }
        self.terminal_events
            .push(TerminalEvent::DragDropCommand(Box::new(DragDropCommand {
                action: parsed.action.unwrap_or(DragDropAction::AcceptDrops),
                more: parsed.more,
                identifier: parsed.identifier,
                operation: parsed.operation,
                x: parsed.x,
                y: parsed.y,
                pixel_x: parsed.pixel_x,
                pixel_y: parsed.pixel_y,
                payload,
            })));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal::OscCapability;

    fn terminal() -> Terminal {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_osc_capability_allowed(OscCapability::DragDrop, true);
        terminal
    }

    fn only_command(terminal: &mut Terminal) -> DragDropCommand {
        let events = terminal.poll_events();
        let [TerminalEvent::DragDropCommand(command)] = events.as_slice() else {
            panic!("expected exactly one drag/drop command: {events:?}");
        };
        command.as_ref().clone()
    }

    #[test]
    fn parses_accept_query_and_full_metadata() {
        let mut terminal = terminal();
        terminal
            .process(b"\x1b]72;t=a:i=7:x=-1:y=2:X=30:Y=40:o=3:m=1;text/plain text/uri-list\x1b\\");
        let command = only_command(&mut terminal);
        assert_eq!(command.action, DragDropAction::AcceptDrops);
        assert!(command.more);
        assert_eq!(command.identifier, Some(7));
        assert_eq!(command.operation, Some(3));
        assert_eq!(command.x, Some(-1));
        assert_eq!(command.y, Some(2));
        assert_eq!(command.pixel_x, Some(30));
        assert_eq!(command.pixel_y, Some(40));
        assert_eq!(command.payload, b"text/plain text/uri-list");

        terminal.process(b"\x1b]72;t=q:i=9;\x07");
        let query = only_command(&mut terminal);
        assert_eq!(query.action, DragDropAction::Query);
        assert_eq!(query.identifier, Some(9));
    }

    #[test]
    fn preserves_semicolons_and_defaults_to_accept() {
        let mut terminal = terminal();
        terminal.process(b"\x1b]72;;text/plain;parameter\x1b\\");
        let command = only_command(&mut terminal);
        assert_eq!(command.action, DragDropAction::AcceptDrops);
        assert_eq!(command.payload, b"text/plain;parameter");
    }

    #[test]
    fn rejects_malformed_bounds_and_denied_policy() {
        let mut terminal = terminal();
        for sequence in [
            b"\x1b]72;t=nope;bad\x1b\\".as_slice(),
            b"\x1b]72;t=a:m=2;bad\x1b\\".as_slice(),
            b"\x1b]72;t=a:i=0;bad\x1b\\".as_slice(),
            b"\x1b]72;t=a:x=2147483648;bad\x1b\\".as_slice(),
        ] {
            terminal.process(sequence);
        }
        assert!(terminal.poll_events().is_empty());

        let oversized = format!("\x1b]72;t=p;{}\x1b\\", "A".repeat(4097));
        terminal.process(oversized.as_bytes());
        assert!(terminal.poll_events().is_empty());

        terminal.set_osc_capability_allowed(OscCapability::DragDrop, false);
        terminal.process(b"\x1b]72;t=q;\x1b\\");
        assert!(terminal.poll_events().is_empty());
    }

    #[test]
    fn survives_every_byte_split_with_bel_or_st() {
        for sequence in [
            b"\x1b]72;t=M:i=4:x=3:y=5:o=1;text/plain\x07".as_slice(),
            b"\x1b]72;t=M:i=4:x=3:y=5:o=1;text/plain\x1b\\".as_slice(),
        ] {
            for split in 0..=sequence.len() {
                let mut terminal = terminal();
                terminal.process(&sequence[..split]);
                terminal.process(&sequence[split..]);
                let command = only_command(&mut terminal);
                assert_eq!(command.action, DragDropAction::Drop);
                assert_eq!(command.identifier, Some(4));
                assert_eq!(command.payload, b"text/plain");
            }
        }
    }
}
