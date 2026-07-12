//! Mode-related CSI sequence handling (SM/RM)

use crate::debug;
use crate::mouse::{MouseEncoding, MouseMode};
use crate::terminal::Terminal;
use vte::Params;

impl Terminal {
    pub(crate) fn handle_csi_mode(&mut self, action: char, params: &Params, intermediates: &[u8]) {
        let private = intermediates.contains(&b'?');

        // Specialized handling for synchronized updates to ensure the sequence itself is processed
        // even if buffering is active
        let mut is_sync_update = false;
        if private {
            for param_slice in params {
                if param_slice.first() == Some(&2026) {
                    is_sync_update = true;
                    break;
                }
            }
        }

        if is_sync_update {
            self.synchronized_updates = false;
            self.handle_csi_mode_impl(action, params, intermediates);
            // We do NOT restore synchronized_updates here because handle_csi_mode_impl
            // just set it to its new intended value (true for SM, false for RM).
        } else {
            self.handle_csi_mode_impl(action, params, intermediates);
        }
    }

    fn handle_csi_mode_impl(&mut self, action: char, params: &Params, intermediates: &[u8]) {
        let private = intermediates.contains(&b'?');
        match action {
            'h' => {
                // Set Mode (SM / DECSET)
                for param_slice in params {
                    let param = param_slice.first().copied().unwrap_or(0);
                    if private {
                        self.handle_decset(param);
                    } else {
                        match param {
                            4 => {
                                if !self.insert_mode {
                                    self.insert_mode = true;
                                    self.terminal_events.push(
                                        crate::terminal::TerminalEvent::ModeChanged(
                                            "insert_mode".to_string(),
                                            true,
                                        ),
                                    );
                                }
                            }
                            20 => {
                                if !self.line_feed_new_line_mode {
                                    self.line_feed_new_line_mode = true;
                                    self.terminal_events.push(
                                        crate::terminal::TerminalEvent::ModeChanged(
                                            "line_feed_new_line_mode".to_string(),
                                            true,
                                        ),
                                    );
                                }
                            }
                            _ => {}
                        }
                    }
                }
            }
            'l' => {
                // Reset Mode (RM / DECRST)
                for param_slice in params {
                    let param = param_slice.first().copied().unwrap_or(0);
                    if private {
                        self.handle_decrst(param);
                    } else {
                        match param {
                            4 => {
                                if self.insert_mode {
                                    self.insert_mode = false;
                                    self.terminal_events.push(
                                        crate::terminal::TerminalEvent::ModeChanged(
                                            "insert_mode".to_string(),
                                            false,
                                        ),
                                    );
                                }
                            }
                            20 => {
                                if self.line_feed_new_line_mode {
                                    self.line_feed_new_line_mode = false;
                                    self.terminal_events.push(
                                        crate::terminal::TerminalEvent::ModeChanged(
                                            "line_feed_new_line_mode".to_string(),
                                            false,
                                        ),
                                    );
                                }
                            }
                            _ => {}
                        }
                    }
                }
            }
            _ => {}
        }
    }

    pub(crate) fn handle_decset(&mut self, param: u16) {
        let old_mode = match param {
            1 => Some(format!("app_cursor:{}", self.application_cursor)),
            6 => Some(format!("origin:{}", self.origin_mode)),
            7 => Some(format!("wrap:{}", self.auto_wrap)),
            25 => Some(format!("cursor_visible:{}", self.cursor.visible)),
            69 => Some(format!("lr_margins:{}", self.use_lr_margins)),
            9 | 1000 | 1002 | 1003 => Some(format!("mouse:{:?}", self.mouse_mode())),
            1005 | 1006 | 1015 | 1016 => Some(format!("mouse_enc:{:?}", self.mouse_encoding())),
            1007 => Some(format!("alternate_scroll:{}", self.alternate_scroll())),
            47 | 1047 | 1049 => Some(format!("alt_screen:{}", self.alt_screen_active)),
            1004 => Some(format!("focus_tracking:{}", self.focus_tracking())),
            2004 => Some(format!("bracketed_paste:{}", self.bracketed_paste)),
            5522 => Some(format!("mime_paste:{}", self.mime_paste)),
            2026 => Some(format!("sync_updates:{}", self.synchronized_updates)),
            _ => None,
        };

        match param {
            1 => self.application_cursor = true,
            6 => {
                self.origin_mode = true;
                self.cursor.goto(0, 0); // Goto (0,0) within scroll region
            }
            7 => self.auto_wrap = true,
            25 => self.cursor.visible = true,
            69 => self.use_lr_margins = true,
            9 => self.set_mouse_mode(MouseMode::X10),
            1000 => self.set_mouse_mode(MouseMode::Normal),
            1002 => self.set_mouse_mode(MouseMode::ButtonEvent),
            1003 => self.set_mouse_mode(MouseMode::AnyEvent),
            1005 => self.set_mouse_encoding(MouseEncoding::Utf8),
            1006 => self.set_mouse_encoding(MouseEncoding::Sgr),
            1015 => self.set_mouse_encoding(MouseEncoding::Urxvt),
            1016 => self.set_mouse_encoding(MouseEncoding::SgrPixels),
            1007 => self.set_alternate_scroll(true),
            47 | 1047 => self.use_alt_screen(),
            1048 => self.save_cursor(),
            1049 => {
                if !self.alt_screen_active {
                    self.save_cursor();
                }
                self.use_alt_screen();
            }
            1004 => self.set_focus_tracking(true),
            2004 => self.bracketed_paste = true,
            5522 => self.mime_paste = true,
            2026 => {
                if !self.suppress_synchronized_update_enable && !self.synchronized_updates {
                    self.sync_update_started_at = Some(std::time::Instant::now());
                }
                if !self.suppress_synchronized_update_enable {
                    self.synchronized_updates = true;
                }
            }
            _ => {
                debug::log(
                    debug::DebugLevel::Debug,
                    "CSI",
                    &format!("Unsupported DECSET: {}", param),
                );
            }
        }

        let new_mode = match param {
            1 => Some(format!("app_cursor:{}", self.application_cursor)),
            6 => Some(format!("origin:{}", self.origin_mode)),
            7 => Some(format!("wrap:{}", self.auto_wrap)),
            25 => Some(format!("cursor_visible:{}", self.cursor.visible)),
            69 => Some(format!("lr_margins:{}", self.use_lr_margins)),
            9 | 1000 | 1002 | 1003 => Some(format!("mouse:{:?}", self.mouse_mode())),
            1005 | 1006 | 1015 | 1016 => Some(format!("mouse_enc:{:?}", self.mouse_encoding())),
            1007 => Some(format!("alternate_scroll:{}", self.alternate_scroll())),
            47 | 1047 | 1049 => Some(format!("alt_screen:{}", self.alt_screen_active)),
            1004 => Some(format!("focus_tracking:{}", self.focus_tracking())),
            2004 => Some(format!("bracketed_paste:{}", self.bracketed_paste)),
            5522 => Some(format!("mime_paste:{}", self.mime_paste)),
            2026 => Some(format!("sync_updates:{}", self.synchronized_updates)),
            _ => None,
        };

        if old_mode != new_mode && !matches!(param, 47 | 1047 | 1049) {
            use crate::terminal::TerminalEvent;
            let mode_name = match param {
                1 => "application_cursor",
                4 => "insert_mode",
                6 => "origin_mode",
                7 => "auto_wrap",
                20 => "line_feed_new_line_mode",
                25 => "cursor_visible",
                69 => "lr_margins",
                9 => "mouse_x10",
                1000 => "mouse_normal",
                1002 => "mouse_button_event",
                1003 => "mouse_any_event",
                1004 => "focus_tracking",
                1005 => "mouse_utf8",
                1006 => "mouse_sgr",
                1007 => "alternate_scroll",
                1015 => "mouse_urxvt",
                1016 => "mouse_sgr_pixels",
                47 | 1047 | 1049 => "alternate_screen",
                2004 => "bracketed_paste",
                5522 => "mime_paste",
                2026 => "synchronized_updates",
                _ => "unknown",
            };
            self.terminal_events
                .push(TerminalEvent::ModeChanged(mode_name.to_string(), true));
        }
    }

    pub(crate) fn handle_decrst(&mut self, param: u16) {
        let old_mode = match param {
            1 => Some(format!("app_cursor:{}", self.application_cursor)),
            6 => Some(format!("origin:{}", self.origin_mode)),
            7 => Some(format!("wrap:{}", self.auto_wrap)),
            25 => Some(format!("cursor_visible:{}", self.cursor.visible)),
            69 => Some(format!("lr_margins:{}", self.use_lr_margins)),
            9 | 1000 | 1002 | 1003 => Some(format!("mouse:{:?}", self.mouse_mode())),
            1005 | 1006 | 1015 | 1016 => Some(format!("mouse_enc:{:?}", self.mouse_encoding())),
            1007 => Some(format!("alternate_scroll:{}", self.alternate_scroll())),
            47 | 1047 | 1049 => Some(format!("alt_screen:{}", self.alt_screen_active)),
            1004 => Some(format!("focus_tracking:{}", self.focus_tracking())),
            2004 => Some(format!("bracketed_paste:{}", self.bracketed_paste)),
            5522 => Some(format!("mime_paste:{}", self.mime_paste)),
            2026 => Some(format!("sync_updates:{}", self.synchronized_updates)),
            _ => None,
        };

        match param {
            1 => self.application_cursor = false,
            6 => {
                self.origin_mode = false;
                self.cursor.goto(0, 0);
            }
            7 => self.auto_wrap = false,
            25 => self.cursor.visible = false,
            69 => self.use_lr_margins = false,
            9 | 1000 | 1002 | 1003 => self.set_mouse_mode(MouseMode::Off),
            1005 | 1006 | 1015 | 1016 => self.set_mouse_encoding(MouseEncoding::Default),
            1007 => self.set_alternate_scroll(false),
            47 | 1047 => self.use_primary_screen(),
            1048 => self.restore_cursor(),
            1049 => {
                let was_alt_screen = self.alt_screen_active;
                self.use_primary_screen();
                if was_alt_screen {
                    self.restore_cursor();
                }
            }
            1004 => self.set_focus_tracking(false),
            2004 => self.bracketed_paste = false,
            5522 => self.mime_paste = false,
            2026 => {
                self.synchronized_updates = false;
                self.sync_update_started_at = None;
                self.sync_update_explicitly_disabled = true;
                self.sync_update_report_override = None;
                self.flush_synchronized_updates();
            }
            _ => {
                debug::log(
                    debug::DebugLevel::Debug,
                    "CSI",
                    &format!("Unsupported DECRST: {}", param),
                );
            }
        }

        let new_mode = match param {
            1 => Some(format!("app_cursor:{}", self.application_cursor)),
            6 => Some(format!("origin:{}", self.origin_mode)),
            7 => Some(format!("wrap:{}", self.auto_wrap)),
            25 => Some(format!("cursor_visible:{}", self.cursor.visible)),
            69 => Some(format!("lr_margins:{}", self.use_lr_margins)),
            9 | 1000 | 1002 | 1003 => Some(format!("mouse:{:?}", self.mouse_mode())),
            1005 | 1006 | 1015 | 1016 => Some(format!("mouse_enc:{:?}", self.mouse_encoding())),
            1007 => Some(format!("alternate_scroll:{}", self.alternate_scroll())),
            47 | 1047 | 1049 => Some(format!("alt_screen:{}", self.alt_screen_active)),
            1004 => Some(format!("focus_tracking:{}", self.focus_tracking())),
            2004 => Some(format!("bracketed_paste:{}", self.bracketed_paste)),
            5522 => Some(format!("mime_paste:{}", self.mime_paste)),
            2026 => Some(format!("sync_updates:{}", self.synchronized_updates)),
            _ => None,
        };

        if old_mode != new_mode && !matches!(param, 47 | 1047 | 1049) {
            use crate::terminal::TerminalEvent;
            let mode_name = match param {
                1 => "application_cursor",
                4 => "insert_mode",
                6 => "origin_mode",
                7 => "auto_wrap",
                20 => "line_feed_new_line_mode",
                25 => "cursor_visible",
                69 => "lr_margins",
                9 => "mouse_x10",
                1000 => "mouse_normal",
                1002 => "mouse_button_event",
                1003 => "mouse_any_event",
                1004 => "focus_tracking",
                1005 => "mouse_utf8",
                1006 => "mouse_sgr",
                1007 => "alternate_scroll",
                1015 => "mouse_urxvt",
                1016 => "mouse_sgr_pixels",
                47 | 1047 | 1049 => "alternate_screen",
                2004 => "bracketed_paste",
                5522 => "mime_paste",
                2026 => "synchronized_updates",
                _ => "unknown",
            };
            self.terminal_events
                .push(TerminalEvent::ModeChanged(mode_name.to_string(), false));
        }
    }
}
