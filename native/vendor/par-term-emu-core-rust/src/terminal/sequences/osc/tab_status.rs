use crate::terminal::{TabStatusUpdate, Terminal, TerminalEvent};

use super::sanitize_osc_text;

const MAX_TAB_STATUS_CHARS: usize = 256;

fn canonical_color((red, green, blue): (u8, u8, u8)) -> String {
    format!("#{red:02x}{green:02x}{blue:02x}")
}

fn split_escaped_fields(payload: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut escaped = false;

    for character in payload.chars() {
        if escaped {
            if matches!(character, ';' | '\\') {
                current.push(character);
            } else {
                current.push('\\');
                current.push(character);
            }
            escaped = false;
        } else if character == '\\' {
            escaped = true;
        } else if character == ';' {
            fields.push(current);
            current = String::new();
        } else {
            current.push(character);
        }
    }
    fields.push(current);
    fields
}

impl Terminal {
    pub(crate) fn handle_osc_tab_status(&mut self, params: &[&[u8]]) {
        let payload = params
            .iter()
            .skip(1)
            .map(|parameter| String::from_utf8_lossy(parameter))
            .collect::<Vec<_>>()
            .join(";");
        let mut update = TabStatusUpdate {
            indicator_present: false,
            indicator: None,
            status_present: false,
            status: None,
            status_color_present: false,
            status_color: None,
        };

        for field in split_escaped_fields(&payload) {
            let (key, value) = field.split_once('=').unwrap_or((&field, ""));
            match key {
                "indicator" if value.is_empty() => {
                    update.indicator_present = true;
                    update.indicator = None;
                }
                "indicator" => {
                    if let Some(color) = Self::parse_color_spec(value) {
                        update.indicator_present = true;
                        update.indicator = Some(canonical_color(color));
                    }
                }
                "status" => {
                    update.status_present = true;
                    let text = sanitize_osc_text(value, MAX_TAB_STATUS_CHARS);
                    update.status = (!text.is_empty()).then_some(text);
                }
                "status-color" if value.is_empty() => {
                    update.status_color_present = true;
                    update.status_color = None;
                }
                "status-color" => {
                    if let Some(color) = Self::parse_color_spec(value) {
                        update.status_color_present = true;
                        update.status_color = Some(canonical_color(color));
                    }
                }
                _ => {}
            }
        }

        if !update.is_empty() {
            self.terminal_events
                .push(TerminalEvent::TabStatusChanged(update));
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::terminal::{TabStatusUpdate, Terminal, TerminalEvent};

    fn last_update(terminal: &mut Terminal) -> TabStatusUpdate {
        terminal
            .poll_events()
            .into_iter()
            .find_map(|event| match event {
                TerminalEvent::TabStatusChanged(update) => Some(update),
                _ => None,
            })
            .expect("expected tab status update")
    }

    #[test]
    fn parses_set_clear_partial_and_escaped_status() {
        let mut terminal = Terminal::new(24, 80);
        terminal.handle_osc_tab_status(&[
            b"21337",
            b"indicator=#FF9500",
            b"status=Working\\",
            b"phase",
            b"status-color=rgb:5f/87/ff",
        ]);

        assert_eq!(
            last_update(&mut terminal),
            TabStatusUpdate {
                indicator_present: true,
                indicator: Some("#ff9500".to_string()),
                status_present: true,
                status: Some("Working;phase".to_string()),
                status_color_present: true,
                status_color: Some("#5f87ff".to_string()),
            }
        );

        terminal.handle_osc_tab_status(&[b"21337", b"status="]);
        let cleared = last_update(&mut terminal);
        assert!(!cleared.indicator_present);
        assert!(cleared.status_present);
        assert_eq!(cleared.status, None);
        assert!(!cleared.status_color_present);
    }

    #[test]
    fn ignores_unknown_and_invalid_fields_without_overwriting_valid_values() {
        let mut terminal = Terminal::new(24, 80);
        terminal.handle_osc_tab_status(&[
            b"21337",
            b"indicator=#00d75f",
            b"indicator=not-a-color",
            b"future=value",
        ]);
        let update = last_update(&mut terminal);
        assert_eq!(update.indicator.as_deref(), Some("#00d75f"));

        terminal.handle_osc_tab_status(&[b"21337", b"indicator=nope"]);
        assert!(terminal.poll_events().is_empty());
    }

    #[test]
    fn sanitizes_and_bounds_status_text() {
        let mut terminal = Terminal::new(24, 80);
        let long = format!("status=A\u{0007}{}", "B".repeat(400));
        terminal.handle_osc_tab_status(&[b"21337", long.as_bytes()]);
        let update = last_update(&mut terminal);
        let status = update.status.expect("status");
        assert!(!status.chars().any(char::is_control));
        assert_eq!(status.chars().count(), 256);
    }

    #[test]
    fn terminal_process_supports_split_st_and_bel_framing() {
        let mut terminal = Terminal::new(24, 80);
        terminal.process(b"\x1b]21337;indicator=#ff9500;status=Work");
        assert!(terminal.poll_events().is_empty());
        terminal.process(b"ing;status-color=#5f87ff\x1b\\");
        let set = last_update(&mut terminal);
        assert_eq!(set.status.as_deref(), Some("Working"));
        assert_eq!(set.indicator.as_deref(), Some("#ff9500"));

        terminal.process(b"\x1b]21337;status=\x07");
        let clear = last_update(&mut terminal);
        assert!(clear.status_present);
        assert_eq!(clear.status, None);
    }
}
