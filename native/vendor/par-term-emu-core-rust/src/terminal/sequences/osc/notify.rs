//! Notification and progress OSC sequence handling

use super::sanitize_osc_text;
use crate::debug;
use crate::terminal::progress::{
    ProgressBar, ProgressBarCommand, ProgressState, OSC934_CAPABILITY_RESPONSE,
};
use crate::terminal::CwdChangeSource;
use crate::terminal::Notification;
use crate::terminal::Terminal;
use std::path::Path;

const MAX_NOTIFICATION_TITLE_CHARS: usize = 160;
const MAX_NOTIFICATION_MESSAGE_CHARS: usize = 512;

impl Terminal {
    pub(crate) fn handle_osc_notify(&mut self, command: &str, params: &[&[u8]]) {
        match command {
            "9" => {
                if params.len() >= 2 {
                    if let Ok(param1) = std::str::from_utf8(params[1]) {
                        let param1 = param1.trim();
                        match param1 {
                            "4" => self.handle_osc9_progress(&params[2..]),
                            "9" if params.len() == 3 => {
                                self.handle_osc9_current_dir(params.get(2).copied())
                            }
                            // Missing or extra fields are malformed OSC 9;9,
                            // but must never fall back to a notification.
                            "9" => {}
                            _ => {
                                let notification = Notification::new(
                                    String::new(),
                                    sanitize_osc_text(param1, MAX_NOTIFICATION_MESSAGE_CHARS),
                                );
                                self.enqueue_notification(notification);
                            }
                        }
                    }
                }
            }
            "777" => {
                if params.len() >= 4 {
                    if let Ok(action) = std::str::from_utf8(params[1]) {
                        if action == "notify" {
                            if let (Ok(title), Ok(message)) = (
                                std::str::from_utf8(params[2]),
                                std::str::from_utf8(params[3]),
                            ) {
                                let notification = Notification::new(
                                    sanitize_osc_text(title, MAX_NOTIFICATION_TITLE_CHARS),
                                    sanitize_osc_text(message, MAX_NOTIFICATION_MESSAGE_CHARS),
                                );
                                self.enqueue_notification(notification);
                            }
                        }
                    }
                }
            }
            "934" => {
                self.handle_osc934(params);
            }
            _ => {}
        }
    }

    fn handle_osc9_current_dir(&mut self, value: Option<&[u8]>) {
        let Some(value) = value else {
            return;
        };
        let Ok(path) = std::str::from_utf8(value) else {
            return;
        };
        let path = path.trim();
        if path.is_empty()
            || path.len() > 4096
            || path.chars().any(char::is_control)
            || !Path::new(path).is_absolute()
        {
            return;
        }

        self.record_cwd_change(crate::terminal::event::CwdChange {
            source: CwdChangeSource::Osc9_9,
            old_cwd: self.shell_integration.cwd().map(str::to_string),
            new_cwd: path.to_string(),
            hostname: self.shell_integration.hostname().map(str::to_string),
            username: self.shell_integration.username().map(str::to_string),
            timestamp: crate::terminal::unix_millis(),
        });
    }

    pub(crate) fn handle_osc9_progress(&mut self, params: &[&[u8]]) {
        if params.is_empty() {
            return;
        }

        let state_param = match std::str::from_utf8(params[0]) {
            Ok(s) => s.trim(),
            Err(_) => return,
        };

        let state_num: u8 = match state_param.parse::<u32>() {
            Ok(n) => n.min(u8::MAX as u32) as u8,
            Err(_) => return,
        };

        let state = ProgressState::from_param(state_num);

        let progress = if state.requires_progress() && params.len() >= 2 {
            match std::str::from_utf8(params[1]) {
                Ok(s) => s
                    .trim()
                    .parse::<u32>()
                    .map(|progress| progress.min(100) as u8)
                    .unwrap_or(0),
                Err(_) => 0,
            }
        } else {
            0
        };

        self.progress_bar = ProgressBar::new(state, progress);

        debug::log(
            debug::DebugLevel::Debug,
            "OSC9",
            &format!(
                "Progress bar: state={}, progress={}",
                state.description(),
                progress
            ),
        );
    }

    pub(crate) fn handle_osc934(&mut self, params: &[&[u8]]) {
        match ProgressBarCommand::parse(params) {
            Some(ProgressBarCommand::Set(bar)) => {
                debug::log(
                    debug::DebugLevel::Debug,
                    "OSC934",
                    &format!(
                        "Set named progress: state={}, percent={}, id_bytes={}, label_bytes={}",
                        bar.state.description(),
                        bar.percent,
                        bar.id.len(),
                        bar.label.as_deref().map_or(0, str::len),
                    ),
                );
                self.set_named_progress_bar(bar);
            }
            Some(ProgressBarCommand::Remove(id)) => {
                debug::log(debug::DebugLevel::Debug, "OSC934", "Remove named progress");
                self.remove_named_progress_bar(&id);
            }
            Some(ProgressBarCommand::RemoveAll) => {
                debug::log(
                    debug::DebugLevel::Debug,
                    "OSC934",
                    "Remove all progress bars",
                );
                self.remove_all_named_progress_bars();
            }
            Some(ProgressBarCommand::Query) => {
                self.push_response(OSC934_CAPABILITY_RESPONSE);
            }
            None => {
                debug::log(
                    debug::DebugLevel::Debug,
                    "OSC934",
                    "Failed to parse OSC 934 sequence",
                );
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::terminal::Terminal;

    #[test]
    fn notification_text_strips_controls_and_is_scalar_bounded() {
        let mut terminal = Terminal::new(80, 24);
        let title = format!("title\u{0085}{}", "t".repeat(200));
        let message = format!("message\n{}", "m".repeat(600));
        terminal.handle_osc_notify(
            "777",
            &[b"777", b"notify", title.as_bytes(), message.as_bytes()],
        );

        let notification = terminal.take_notifications().pop().unwrap();
        assert!(!notification.title.chars().any(char::is_control));
        assert!(!notification.message.chars().any(char::is_control));
        assert_eq!(notification.title.chars().count(), 160);
        assert_eq!(notification.message.chars().count(), 512);
    }
}
