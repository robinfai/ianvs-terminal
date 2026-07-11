//! Kitty OSC 22 mouse-pointer shape handling.

use crate::terminal::pointer_shape::PointerShape;
use crate::terminal::Terminal;

const MAX_OSC22_RESPONSE_BYTES: usize = 4 * 1024;
const MAX_POINTER_SHAPE_NAME_BYTES: usize = 64;

impl Terminal {
    /// Current OSC 22 shape for the active screen. An empty stack returns
    /// `None`, allowing the product layer to choose its default/grabbed shape.
    pub fn pointer_shape_name(&self) -> Option<&'static str> {
        self.pointer_shape_state
            .current(self.alt_screen_active)
            .map(PointerShape::wire_name)
    }

    fn valid_pointer_shape_name(name: &str) -> bool {
        !name.is_empty()
            && name.len() <= MAX_POINTER_SHAPE_NAME_BYTES
            && name.bytes().all(|byte| {
                byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'_' | b'-')
            })
    }

    fn osc22_query_value(&self, name: &str) -> &'static str {
        match name {
            "__current__" => self.pointer_shape_name().unwrap_or("0"),
            // These names match the actual Ianvs viewport fallback behavior.
            "__default__" => "text",
            "__grabbed__" => "default",
            _ if PointerShape::parse_canonical(name).is_some() => "1",
            _ => "0",
        }
    }

    fn respond_to_osc22_query(&mut self, names: &str) {
        let mut response = String::from("\x1b]22;");
        for (index, name) in names.split(',').enumerate() {
            let value = if Self::valid_pointer_shape_name(name) {
                self.osc22_query_value(name)
            } else {
                "0"
            };
            let separator_bytes = usize::from(index > 0);
            if response
                .len()
                .saturating_add(separator_bytes)
                .saturating_add(value.len())
                .saturating_add(2)
                > MAX_OSC22_RESPONSE_BYTES
            {
                break;
            }
            if index > 0 {
                response.push(',');
            }
            response.push_str(value);
        }
        response.push_str("\x1b\\");
        self.push_response(response.as_bytes());
    }

    pub(crate) fn handle_osc_pointer_shape(&mut self, params: &[&[u8]]) {
        if params.len() > 2 {
            return;
        }
        let payload = params.get(1).copied().unwrap_or_default();
        let Ok(payload) = std::str::from_utf8(payload) else {
            return;
        };
        if payload.len() > 4 * 1024 {
            return;
        }
        let (operation, names) = match payload.as_bytes().first().copied() {
            Some(operation @ (b'=' | b'>' | b'<' | b'?')) => (operation, &payload[1..]),
            _ => (b'=', payload),
        };

        if operation == b'?' {
            self.respond_to_osc22_query(names);
            return;
        }

        let alternate_screen = self.alt_screen_active;
        let mut changed = false;
        match operation {
            b'=' => {
                for name in names.split(',') {
                    if name.is_empty() {
                        changed |= self.pointer_shape_state.set_current(alternate_screen, None);
                    } else if Self::valid_pointer_shape_name(name) {
                        if let Some(shape) = PointerShape::parse_set_name(name) {
                            changed |= self
                                .pointer_shape_state
                                .set_current(alternate_screen, Some(shape));
                        }
                    }
                }
            }
            b'>' => {
                for name in names.split(',') {
                    if Self::valid_pointer_shape_name(name) {
                        if let Some(shape) = PointerShape::parse_set_name(name) {
                            changed |= self.pointer_shape_state.push(alternate_screen, shape);
                        }
                    }
                }
            }
            b'<' => changed = self.pointer_shape_state.pop(alternate_screen),
            _ => unreachable!("OSC 22 operation is normalized above"),
        }
        if changed {
            self.mark_full_repaint("pointer_shape_changed");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal::pointer_shape::MAX_POINTER_SHAPE_STACK_DEPTH;
    use crate::terminal::OscCapability;

    #[test]
    fn osc22_supports_all_canonical_names_and_static_queries() {
        let mut terminal = Terminal::new(80, 24);
        let names = PointerShape::ALL
            .into_iter()
            .map(PointerShape::wire_name)
            .collect::<Vec<_>>()
            .join(",");
        terminal.process(format!("\x1b]22;?{names}\x1b\\").as_bytes());

        assert_eq!(
            terminal.drain_responses(),
            format!("\x1b]22;{}\x1b\\", vec!["1"; 30].join(",")).as_bytes()
        );
        terminal.process(b"\x1b]22;?__current__,__default__,__grabbed__,no-such-name\x07");
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]22;0,text,default,0\x1b\\"
        );
    }

    #[test]
    fn osc22_sets_pushes_pops_resets_and_accepts_xterm_aliases() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]22;pointer\x1b\\");
        assert_eq!(terminal.pointer_shape_name(), Some("pointer"));

        terminal.process(b"\x1b]22;>wait,crosshair\x1b\\");
        assert_eq!(terminal.pointer_shape_name(), Some("crosshair"));
        terminal.process(b"\x1b]22;<ignored,names\x1b\\");
        assert_eq!(terminal.pointer_shape_name(), Some("wait"));
        terminal.process(b"\x1b]22;<\x1b\\");
        assert_eq!(terminal.pointer_shape_name(), Some("pointer"));

        terminal.process(b"\x1b]22;=hand2\x1b\\");
        assert_eq!(terminal.pointer_shape_name(), Some("pointer"));
        terminal.process(b"\x1b]22;\x1b\\");
        assert_eq!(terminal.pointer_shape_name(), None);
        terminal.process(b"\x1b]22;<\x1b\\");
        assert_eq!(terminal.pointer_shape_name(), None);
    }

    #[test]
    fn osc22_keeps_screen_local_stacks_and_ris_clears_both() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]22;pointer\x1b\\");
        terminal.process(b"\x1b[?1049h\x1b]22;wait\x1b\\");
        assert_eq!(terminal.pointer_shape_name(), Some("wait"));
        terminal.process(b"\x1b[?1049l");
        assert_eq!(terminal.pointer_shape_name(), Some("pointer"));
        terminal.process(b"\x1b[?1049h");
        assert_eq!(terminal.pointer_shape_name(), Some("wait"));

        terminal.reset();
        assert_eq!(terminal.pointer_shape_name(), None);
        terminal.process(b"\x1b[?1049h");
        assert_eq!(terminal.pointer_shape_name(), None);
    }

    #[test]
    fn osc22_snapshot_restores_both_stacks() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]22;pointer\x1b\\\x1b[?1049h\x1b]22;wait\x1b\\");
        let snapshot = terminal.capture_snapshot();

        terminal.process(b"\x1b]22;crosshair\x1b\\\x1b[?1049l\x1b]22;help\x1b\\");
        terminal.restore_from_snapshot(snapshot);
        assert_eq!(terminal.pointer_shape_name(), Some("wait"));
        terminal.process(b"\x1b[?1049l");
        assert_eq!(terminal.pointer_shape_name(), Some("pointer"));
    }

    #[test]
    fn osc22_stack_is_bounded_and_evicts_the_oldest_shape() {
        let mut terminal = Terminal::new(80, 24);
        let pushed = (0..40)
            .map(|index| PointerShape::ALL[index % PointerShape::ALL.len()].wire_name())
            .collect::<Vec<_>>()
            .join(",");
        terminal.process(format!("\x1b]22;>{pushed}\x1b\\").as_bytes());
        assert_eq!(
            terminal.pointer_shape_state.active_depth(false),
            MAX_POINTER_SHAPE_STACK_DEPTH
        );

        for _ in 0..31 {
            terminal.process(b"\x1b]22;<\x1b\\");
        }
        assert_eq!(
            terminal.pointer_shape_name(),
            Some(PointerShape::ALL[8].wire_name())
        );
    }

    #[test]
    fn osc22_survives_every_byte_split_with_bel_or_st() {
        for terminator in [b"\x07".as_slice(), b"\x1b\\".as_slice()] {
            let mut sequence = b"\x1b]22;>wait,pointer".to_vec();
            sequence.extend_from_slice(terminator);
            for split in 1..sequence.len() {
                let mut terminal = Terminal::new(80, 24);
                terminal.process(&sequence[..split]);
                terminal.process(&sequence[split..]);
                assert_eq!(
                    terminal.pointer_shape_name(),
                    Some("pointer"),
                    "split={split}, terminator={terminator:?}"
                );
            }
        }
    }

    #[test]
    fn osc22_invalid_fields_are_isolated_and_next_sequence_recovers() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]22;>pointer,INVALID,bad/name,wait\x1b\\");
        assert_eq!(terminal.pointer_shape_name(), Some("wait"));
        terminal.process(b"\x1b]22;bad;extra\x1b\\");
        assert_eq!(terminal.pointer_shape_name(), Some("wait"));
        terminal.process(b"\x1b]22;?pointer,INVALID,bad/name,wait\x1b\\");
        assert_eq!(terminal.drain_responses(), b"\x1b]22;1,0,0,1\x1b\\");
    }

    #[test]
    fn osc22_appearance_policy_denial_blocks_mutation_and_queries() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_osc_capability_allowed(OscCapability::Appearance, false);
        terminal.process(b"\x1b]22;pointer\x1b\\\x1b]22;?__current__,pointer\x1b\\");

        assert_eq!(terminal.pointer_shape_name(), None);
        assert!(terminal.drain_responses().is_empty());
    }
}
