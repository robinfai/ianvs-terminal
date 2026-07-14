//! Title-related OSC sequence handling

use super::sanitize_osc_text;
use crate::terminal::Terminal;

const MAX_TITLE_CHARS: usize = 1024;

impl Terminal {
    pub(crate) fn handle_osc_title(&mut self, command: &str, params: &[&[u8]]) {
        match command {
            "0" | "2" => {
                if params.len() >= 2 {
                    self.apply_osc_title_parts(params[1], &params[2..]);
                }
            }
            _ => {}
        }
    }

    pub(crate) fn handle_legacy_osc_title(&mut self, params: &[&[u8]]) {
        let Some(first) = params.first().and_then(|param| param.strip_prefix(b"l")) else {
            return;
        };
        self.apply_osc_title_parts(first, &params[1..]);
    }

    fn apply_osc_title_parts(&mut self, first: &[u8], rest: &[&[u8]]) {
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

        if let Ok(title) = std::str::from_utf8(&bytes) {
            let new_title = sanitize_osc_text(title, MAX_TITLE_CHARS);
            if self.title != new_title {
                self.set_title(new_title.clone());
                self.terminal_events
                    .push(crate::terminal::TerminalEvent::TitleChanged(new_title));
            }
        }
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
}
