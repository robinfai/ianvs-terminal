//! xterm OSC 50 session font-family operations.

use crate::terminal::Terminal;

const MAX_FONT_FAMILY_BYTES: usize = 256;
const FONT_MENU_ORDER: [usize; 8] = [1, 2, 3, 0, 4, 5, 6, 7];
const DEFAULT_FONT_MENU_INDEX: usize = 0;

impl Terminal {
    pub(crate) fn handle_osc_font(&mut self, params: &[&[u8]], bell_terminated: bool) {
        if params.len() < 2 {
            return;
        }
        let Ok(first) = std::str::from_utf8(params[1]) else {
            return;
        };
        let mut payload = first.to_string();
        for parameter in params.iter().skip(2) {
            let Ok(parameter) = std::str::from_utf8(parameter) else {
                return;
            };
            payload.push(';');
            payload.push_str(parameter);
        }

        if let Some(query) = payload.strip_prefix('?') {
            self.reply_to_osc_font_query(query, bell_terminated);
            return;
        }

        let family = match payload.strip_prefix('#') {
            Some(indexed) => parse_font_index(indexed).map(|(_, family, _)| family),
            None => Some(payload.as_str()),
        };
        let Some(family) = family.and_then(normalize_font_family) else {
            return;
        };
        self.set_xterm_font_family(family);
    }

    fn reply_to_osc_font_query(&mut self, query: &str, bell_terminated: bool) {
        let (index, _, include_index) = match parse_font_index(query) {
            Some(parsed) => parsed,
            None => {
                self.push_osc_font_response(None, bell_terminated);
                return;
            }
        };
        let family = if include_index {
            format!("#{index} {}", self.xterm_font_family())
        } else {
            self.xterm_font_family().to_string()
        };
        self.push_osc_font_response(Some(&family), bell_terminated);
    }

    fn push_osc_font_response(&mut self, family: Option<&str>, bell_terminated: bool) {
        let mut response = String::from("\x1b]50");
        if let Some(family) = family {
            response.push(';');
            response.push_str(family);
        }
        if bell_terminated {
            response.push('\x07');
        } else {
            response.push_str("\x1b\\");
        }
        self.push_response(response.as_bytes());
    }
}

pub(crate) fn normalize_font_family(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty()
        || value.len() > MAX_FONT_FAMILY_BYTES
        || value.chars().any(char::is_control)
    {
        return None;
    }
    Some(value.to_string())
}

/// Parse xterm's optional absolute/relative font-menu expression. Ianvs has
/// one TrueType family rather than xterm's bitmap menu, so its menu anchor is
/// stable at index zero while xterm's default face-size ordering is honored.
fn parse_font_index(value: &str) -> Option<(usize, &str, bool)> {
    let (relative, value) = match value.as_bytes().first() {
        Some(b'+') => (Some(true), &value[1..]),
        Some(b'-') => (Some(false), &value[1..]),
        _ => (None, value),
    };
    let digit_count = value.bytes().take_while(u8::is_ascii_digit).count();
    let digits = &value[..digit_count];
    let remainder = &value[digit_count..];
    let number = if digits.is_empty() {
        if relative.is_some() {
            1
        } else {
            DEFAULT_FONT_MENU_INDEX
        }
    } else {
        digits.parse::<usize>().ok()?
    };
    let index = match relative {
        None => (number < FONT_MENU_ORDER.len()).then_some(number)?,
        Some(forward) => {
            let current = FONT_MENU_ORDER
                .iter()
                .position(|candidate| *candidate == DEFAULT_FONT_MENU_INDEX)?;
            let position = if forward {
                current.checked_add(number)?
            } else {
                current.checked_sub(number)?
            };
            *FONT_MENU_ORDER.get(position)?
        }
    };
    Some((index, remainder.trim_start(), !value.is_empty()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn osc50_sets_and_queries_font_family_with_matching_terminator() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_xterm_font_family_from_profile("Profile Mono");
        let _ = terminal.drain_active_screen_damage();
        terminal.process(b"\x1b]50;Courier Prime\x1b\\");
        let damage = terminal.drain_active_screen_damage();
        terminal.process(b"\x1b]50;?\x1b\\");
        terminal.process(b"\x1b]50;?\x07");

        assert_eq!(terminal.xterm_font_family(), "Courier Prime");
        assert!(damage.full_repaint);
        assert_eq!(
            damage.snapshot_fallback_reason.as_deref(),
            Some("terminal_font_changed")
        );
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]50;Courier Prime\x1b\\\x1b]50;Courier Prime\x07"
        );
    }

    #[test]
    fn osc50_supports_indexed_and_semicolon_font_names() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process("\x1b]50;#4 Family;字体\x1b\\".as_bytes());
        terminal.process(b"\x1b]50;?4\x1b\\");
        terminal.process(b"\x1b]50;?+\x1b\\");
        terminal.process(b"\x1b]50;?-1\x1b\\");

        assert_eq!(terminal.xterm_font_family(), "Family;字体");
        assert_eq!(
            terminal.drain_responses(),
            "\x1b]50;#4 Family;字体\x1b\\\x1b]50;Family;字体\x1b\\\x1b]50;#3 Family;字体\x1b\\"
                .as_bytes()
        );
    }

    #[test]
    fn osc50_rejects_invalid_family_and_reports_invalid_index_without_state_change() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_xterm_font_family_from_profile("Profile Mono");
        terminal.process(b"\x1b]50;\x1b\\");
        terminal.process(b"\x1b]50;#99 Other\x1b\\");
        terminal.process(b"\x1b]50;?99\x1b\\");

        assert_eq!(terminal.xterm_font_family(), "Profile Mono");
        assert_eq!(terminal.drain_responses(), b"\x1b]50\x1b\\");
    }

    #[test]
    fn osc50_survives_every_byte_fragmentation() {
        let sequence = b"\x1b]50;#4 Courier Prime\x1b\\";
        for split in 1..sequence.len() {
            let mut terminal = Terminal::new(80, 24);
            terminal.process(&sequence[..split]);
            terminal.process(&sequence[split..]);
            assert_eq!(terminal.xterm_font_family(), "Courier Prime");
        }
    }

    #[test]
    fn osc50_is_bounded_and_rejects_controls() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_xterm_font_family_from_profile("Profile Mono");
        let oversized = "x".repeat(MAX_FONT_FAMILY_BYTES + 1);
        terminal.handle_osc_font(&[b"50", oversized.as_bytes()], false);
        terminal.handle_osc_font(&[b"50", b"Bad\x01Font"], false);
        terminal.process(b"\x1b]50;Bad\xc2\x85Font\x1b\\");
        assert_eq!(terminal.xterm_font_family(), "Profile Mono");
    }

    #[test]
    fn osc50_obeys_appearance_policy_and_survives_ris() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_xterm_font_family_from_profile("Profile Mono");
        terminal.process(b"\x1b]50;Courier Prime\x1b\\");
        terminal.process(b"\x1bc");
        terminal.process(b"\x1b]50;?\x1b\\");
        assert_eq!(terminal.xterm_font_family(), "Courier Prime");
        assert_eq!(terminal.drain_responses(), b"\x1b]50;Courier Prime\x1b\\");

        terminal.set_osc_capability_allowed(crate::terminal::OscCapability::Appearance, false);
        terminal.process(b"\x1b]50;Denied Family\x1b\\");
        terminal.process(b"\x1b]50;?\x1b\\");
        assert_eq!(terminal.xterm_font_family(), "Courier Prime");
        assert!(terminal.drain_responses().is_empty());
    }

    #[test]
    fn osc50_round_trips_through_terminal_snapshot() {
        let mut source = Terminal::new(80, 24);
        source.set_xterm_font_family_from_profile("Profile Mono");
        source.process(b"\x1b]50;Courier Prime\x1b\\");

        let mut restored = Terminal::new(80, 24);
        restored.restore_from_snapshot(source.capture_snapshot());
        assert_eq!(restored.xterm_font_family(), "Courier Prime");
        restored.process(b"\x1b]50;?\x1b\\");
        assert_eq!(restored.drain_responses(), b"\x1b]50;Courier Prime\x1b\\");
    }
}
