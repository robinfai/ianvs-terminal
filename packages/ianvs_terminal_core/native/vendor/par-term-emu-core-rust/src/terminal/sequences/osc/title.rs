//! Title-related OSC sequence handling

use super::sanitize_osc_text;
use crate::terminal::Terminal;

const MAX_TITLE_CHARS: usize = 1024;

impl Terminal {
    pub(crate) fn handle_osc_title(&mut self, command: &str, params: &[&[u8]]) {
        if params.len() < 2 {
            return;
        }
        let Some(text) = self.osc_title_text_from_parts(params[1], &params[2..]) else {
            return;
        };
        match command {
            "0" => {
                self.set_protocol_window_title(text.clone());
                self.set_protocol_icon_name(text);
            }
            "1" => self.set_protocol_icon_name(text),
            "2" => self.set_protocol_window_title(text),
            _ => unreachable!("title dispatcher passed an unknown command"),
        }
    }

    pub(crate) fn handle_legacy_osc_title(&mut self, params: &[&[u8]]) {
        let Some(param) = params.first() else {
            return;
        };
        let Some((&command, first)) = param.split_first() else {
            return;
        };
        let Some(text) = self.osc_title_text_from_parts(first, &params[1..]) else {
            return;
        };
        match command {
            b'l' => self.set_protocol_window_title(text),
            b'L' => self.set_protocol_icon_name(text),
            _ => unreachable!("legacy title dispatcher passed an unknown command"),
        }
    }

    fn osc_title_text_from_parts(&self, first: &[u8], rest: &[&[u8]]) -> Option<String> {
        let extra_len = rest
            .iter()
            .map(|part| part.len().saturating_add(1))
            .sum::<usize>();
        let mut bytes = Vec::with_capacity(first.len().saturating_add(extra_len));
        bytes.extend_from_slice(first);
        for part in rest {
            bytes.push(b';');
            bytes.extend_from_slice(part);
        }

        let bytes = if self.title_mode_enabled(0) {
            decode_hex_title(&bytes)?
        } else {
            bytes
        };
        let text = std::str::from_utf8(&bytes).ok()?;
        Some(sanitize_osc_text(text, MAX_TITLE_CHARS))
    }

    pub(crate) fn set_protocol_window_title(&mut self, title: String) {
        if self.title != title {
            self.set_title(title.clone());
            self.terminal_events
                .push(crate::terminal::TerminalEvent::TitleChanged(title));
        }
    }

    pub(crate) fn set_protocol_icon_name(&mut self, icon_name: String) {
        self.icon_name = icon_name;
    }

    pub(crate) fn title_mode_enabled(&self, mode: u8) -> bool {
        mode < 4 && self.title_modes & (1 << mode) != 0
    }
}

fn decode_hex_title(encoded: &[u8]) -> Option<Vec<u8>> {
    if !encoded.len().is_multiple_of(2) {
        return None;
    }
    encoded
        .chunks_exact(2)
        .map(|chunk| {
            let high = hex_nibble(chunk[0])?;
            let low = hex_nibble(chunk[1])?;
            Some((high << 4) | low)
        })
        .collect()
}

fn hex_nibble(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use crate::terminal::Terminal;

    #[test]
    fn title_text_strips_controls_and_is_scalar_bounded() {
        let mut terminal = Terminal::new(80, 24);
        let title = format!("safe\u{0085}{}", "x".repeat(1100));
        terminal.handle_osc_title("2", &[b"2", title.as_bytes()]);

        assert!(!terminal.title().chars().any(char::is_control));
        assert_eq!(terminal.title().chars().count(), 1024);
        assert!(terminal.title().starts_with("safex"));
    }

    #[test]
    fn numeric_title_preserves_semicolons() {
        let mut terminal = Terminal::new(80, 24);
        terminal.handle_osc_title("2", &[b"2", b"build", b"phase", b""]);

        assert_eq!(terminal.title(), "build;phase;");
    }

    #[test]
    fn title_hex_mode_is_strict_and_applies_to_both_channels() {
        let mut terminal = Terminal::new(80, 24);
        terminal.title_modes = 1;
        terminal.handle_osc_title("0", &[b"0", b"e7aa97e58fa3"]);
        assert_eq!(terminal.title(), "窗口");
        assert_eq!(terminal.icon_name(), "窗口");

        terminal.handle_osc_title("0", &[b"0", b"0"]);
        assert_eq!(terminal.title(), "窗口");
        assert_eq!(terminal.icon_name(), "窗口");
        terminal.handle_osc_title("0", &[b"0", b"zz"]);
        assert_eq!(terminal.title(), "窗口");
        assert_eq!(terminal.icon_name(), "窗口");
    }

    #[test]
    fn icon_text_rejects_invalid_utf8_and_is_control_free_and_scalar_bounded() {
        let mut terminal = Terminal::new(80, 24);
        let icon = format!("safe\u{0085}{}", "界".repeat(1100));
        terminal.handle_osc_title("1", &[b"1", icon.as_bytes()]);

        assert!(!terminal.icon_name().chars().any(char::is_control));
        assert_eq!(terminal.icon_name().chars().count(), 1024);
        assert!(terminal.icon_name().starts_with("safe界"));
        let expected = terminal.icon_name().to_string();

        terminal.handle_osc_title("1", &[b"1", b"invalid\xff"]);
        assert_eq!(terminal.icon_name(), expected);
        terminal.handle_legacy_osc_title(&[b"L"]);
        assert_eq!(terminal.icon_name(), "");
    }
}
