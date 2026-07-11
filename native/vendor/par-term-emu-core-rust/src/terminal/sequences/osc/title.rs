//! Title-related OSC sequence handling

use super::sanitize_osc_text;
use crate::terminal::Terminal;

const MAX_TITLE_CHARS: usize = 1024;

impl Terminal {
    pub(crate) fn handle_osc_title(&mut self, command: &str, params: &[&[u8]]) {
        match command {
            "0" | "2" => {
                if params.len() >= 2 {
                    if let Ok(title) = std::str::from_utf8(params[1]) {
                        let new_title = sanitize_osc_text(title, MAX_TITLE_CHARS);
                        if self.title != new_title {
                            self.title = new_title.clone();
                            self.terminal_events
                                .push(crate::terminal::TerminalEvent::TitleChanged(new_title));
                        }
                    }
                }
            }
            "23" => {
                if let Some(title) = self.title_stack.pop() {
                    self.title = title;
                }
            }
            _ => {}
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
}
