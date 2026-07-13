//! Notification and progress OSC sequence handling

use super::sanitize_osc_text;
use crate::debug;
use crate::terminal::notification::{
    KittyNotificationAssembly, MAX_KITTY_NOTIFICATION_APPLICATION_CHARS,
    MAX_KITTY_NOTIFICATION_BODY_CHARS, MAX_KITTY_NOTIFICATION_BUTTONS,
    MAX_KITTY_NOTIFICATION_BUTTON_CHARS, MAX_KITTY_NOTIFICATION_ID_BYTES,
    MAX_KITTY_NOTIFICATION_TITLE_CHARS, MAX_KITTY_NOTIFICATION_TYPES,
    MAX_KITTY_NOTIFICATION_TYPE_CHARS,
};
use crate::terminal::progress::{
    ProgressBar, ProgressBarCommand, ProgressState, OSC934_CAPABILITY_RESPONSE,
};
use crate::terminal::CwdChangeSource;
use crate::terminal::Terminal;
use crate::terminal::{Notification, NotificationAction};
use base64::{engine::general_purpose, Engine};
use std::path::Path;

const MAX_NOTIFICATION_TITLE_CHARS: usize = 160;
const MAX_NOTIFICATION_MESSAGE_CHARS: usize = 512;
const MAX_KITTY_NOTIFICATION_METADATA_BYTES: usize = 1024;
const MAX_KITTY_NOTIFICATION_PLAIN_CHUNK_BYTES: usize = 2048;
const MAX_KITTY_NOTIFICATION_ENCODED_CHUNK_BYTES: usize = 4096;
const MAX_KITTY_NOTIFICATION_EXPIRY_MS: u64 = u32::MAX as u64;
const MAX_KITTY_NOTIFICATION_BUTTON_PAYLOAD_CHARS: usize = MAX_KITTY_NOTIFICATION_BUTTONS
    * MAX_KITTY_NOTIFICATION_BUTTON_CHARS
    + MAX_KITTY_NOTIFICATION_BUTTONS.saturating_sub(1);
const OSC99_CAPABILITY_PAYLOAD: &str = "a=report:c=1:o=always:p=title,body,close,alive,buttons:w=1";

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum KittyNotificationPayloadKind {
    #[default]
    Title,
    Body,
    Buttons,
    Close,
    Query,
    Alive,
    Unsupported,
}

#[derive(Debug, Default)]
struct KittyNotificationMetadata {
    identifier: Option<String>,
    payload_kind: KittyNotificationPayloadKind,
    done: bool,
    encoded: bool,
    application_name: Option<String>,
    notification_types: Vec<String>,
    expiry_specified: bool,
    expires_after_ms: Option<u32>,
    report_activation: Option<bool>,
    report_close: Option<bool>,
}

fn is_kitty_metadata_value_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || b"-_/+.,(){}[]*&^%$#@!`~=?".contains(&byte)
}

fn is_kitty_notification_identifier_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || b"_-+.".contains(&byte)
}

fn decode_base64_text(value: &[u8], max_encoded_bytes: usize, max_chars: usize) -> Option<String> {
    if value.len() > max_encoded_bytes {
        return None;
    }
    let decoded = general_purpose::STANDARD
        .decode(value)
        .or_else(|_| general_purpose::STANDARD_NO_PAD.decode(value))
        .ok()?;
    let text = std::str::from_utf8(&decoded).ok()?;
    Some(sanitize_osc_text(text, max_chars))
}

fn parse_kitty_notification_metadata(value: &[u8]) -> Option<KittyNotificationMetadata> {
    if value.len() > MAX_KITTY_NOTIFICATION_METADATA_BYTES {
        return None;
    }
    let value = std::str::from_utf8(value).ok()?;
    let mut metadata = KittyNotificationMetadata {
        done: true,
        ..KittyNotificationMetadata::default()
    };
    if value.is_empty() {
        return Some(metadata);
    }

    for field in value.split(':') {
        let (key, value) = field.split_once('=')?;
        if key.len() != 1 || !key.as_bytes()[0].is_ascii_alphabetic() {
            return None;
        }
        if !value.bytes().all(is_kitty_metadata_value_byte) {
            return None;
        }
        match key {
            "i" => {
                if value.is_empty()
                    || value.len() > MAX_KITTY_NOTIFICATION_ID_BYTES
                    || !value.bytes().all(is_kitty_notification_identifier_byte)
                {
                    return None;
                }
                metadata.identifier = Some(value.to_string());
            }
            "p" => {
                metadata.payload_kind = match value {
                    "title" => KittyNotificationPayloadKind::Title,
                    "body" => KittyNotificationPayloadKind::Body,
                    "buttons" => KittyNotificationPayloadKind::Buttons,
                    "close" => KittyNotificationPayloadKind::Close,
                    "?" => KittyNotificationPayloadKind::Query,
                    "alive" => KittyNotificationPayloadKind::Alive,
                    _ => KittyNotificationPayloadKind::Unsupported,
                };
            }
            "d" => {
                metadata.done = match value {
                    "0" => false,
                    "1" => true,
                    _ => return None,
                };
            }
            "e" => {
                metadata.encoded = match value {
                    "0" => false,
                    "1" => true,
                    _ => return None,
                };
            }
            "f" => {
                metadata.application_name = Some(decode_base64_text(
                    value.as_bytes(),
                    MAX_KITTY_NOTIFICATION_METADATA_BYTES,
                    MAX_KITTY_NOTIFICATION_APPLICATION_CHARS,
                )?);
            }
            "t" => {
                if metadata.notification_types.len() < MAX_KITTY_NOTIFICATION_TYPES {
                    let notification_type = decode_base64_text(
                        value.as_bytes(),
                        MAX_KITTY_NOTIFICATION_METADATA_BYTES,
                        MAX_KITTY_NOTIFICATION_TYPE_CHARS,
                    )?;
                    if !notification_type.is_empty()
                        && !metadata.notification_types.contains(&notification_type)
                    {
                        metadata.notification_types.push(notification_type);
                    }
                }
            }
            "w" => {
                let expiry = value.parse::<i64>().ok()?;
                if !(-1..=MAX_KITTY_NOTIFICATION_EXPIRY_MS as i64).contains(&expiry) {
                    return None;
                }
                metadata.expiry_specified = true;
                metadata.expires_after_ms = (expiry >= 0).then_some(expiry as u32);
            }
            "o" => {
                if value != "always" {
                    return None;
                }
            }
            "a" => {
                for action in value.split(',') {
                    match action {
                        "report" => metadata.report_activation = Some(true),
                        "-report" => metadata.report_activation = Some(false),
                        // Protocol-driven focus is deliberately never honored.
                        "focus" | "-focus" => {}
                        _ => return None,
                    }
                }
            }
            "c" => {
                metadata.report_close = Some(match value {
                    "0" => false,
                    "1" => true,
                    _ => return None,
                });
            }
            // Icons, sound, urgency and visibility occasions are consumed but
            // never acted upon by the safe subset.
            _ => {}
        }
    }
    Some(metadata)
}

fn joined_osc_payload(params: &[&[u8]]) -> Option<Vec<u8>> {
    let retained =
        params.iter().map(|part| part.len()).sum::<usize>() + params.len().saturating_sub(1);
    if retained > MAX_KITTY_NOTIFICATION_ENCODED_CHUNK_BYTES {
        return None;
    }
    let mut payload = Vec::with_capacity(retained);
    for (index, part) in params.iter().enumerate() {
        if index > 0 {
            payload.push(b';');
        }
        payload.extend_from_slice(part);
    }
    Some(payload)
}

fn decode_kitty_notification_payload(payload: &[u8], encoded: bool) -> Option<String> {
    if encoded {
        if payload.len() > MAX_KITTY_NOTIFICATION_ENCODED_CHUNK_BYTES {
            return None;
        }
        let decoded = general_purpose::STANDARD
            .decode(payload)
            .or_else(|_| general_purpose::STANDARD_NO_PAD.decode(payload))
            .ok()?;
        if decoded.len() > MAX_KITTY_NOTIFICATION_PLAIN_CHUNK_BYTES {
            return None;
        }
        return std::str::from_utf8(&decoded).ok().map(str::to_string);
    }
    if payload.len() > MAX_KITTY_NOTIFICATION_PLAIN_CHUNK_BYTES {
        return None;
    }
    std::str::from_utf8(payload).ok().map(str::to_string)
}

fn append_sanitized_bounded(target: &mut String, value: &str, max_chars: usize) {
    let retained = target.chars().count();
    if retained >= max_chars {
        return;
    }
    target.extend(
        value
            .chars()
            .filter(|character| !character.is_control())
            .take(max_chars - retained),
    );
}

fn apply_kitty_metadata(
    assembly: &mut KittyNotificationAssembly,
    metadata: &KittyNotificationMetadata,
) {
    if let Some(application_name) = metadata.application_name.as_ref() {
        assembly.application_name = Some(application_name.clone());
    }
    for notification_type in &metadata.notification_types {
        if assembly.notification_types.len() >= MAX_KITTY_NOTIFICATION_TYPES {
            break;
        }
        if !assembly.notification_types.contains(notification_type) {
            assembly.notification_types.push(notification_type.clone());
        }
    }
    if metadata.expiry_specified {
        assembly.expires_after_ms = metadata.expires_after_ms;
    }
    if let Some(report_activation) = metadata.report_activation {
        assembly.report_activation = report_activation;
    }
    if let Some(report_close) = metadata.report_close {
        assembly.report_close = report_close;
    }
}

fn finalize_kitty_buttons(assembly: &mut KittyNotificationAssembly) {
    let buttons = assembly
        .button_payload
        .split('\u{2028}')
        .map(|label| sanitize_osc_text(label, MAX_KITTY_NOTIFICATION_BUTTON_CHARS))
        .take(MAX_KITTY_NOTIFICATION_BUTTONS)
        .collect::<Vec<_>>();
    assembly.buttons = if buttons.iter().all(String::is_empty) {
        Vec::new()
    } else {
        buttons
    };
    assembly.button_payload.clear();
}

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
            "99" => self.handle_osc99(params),
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

    fn handle_osc99(&mut self, params: &[&[u8]]) {
        let Some(metadata_bytes) = params.get(1).copied() else {
            return;
        };
        let Some(metadata) = parse_kitty_notification_metadata(metadata_bytes) else {
            return;
        };
        let now = crate::terminal::unix_millis();
        self.kitty_notification_state.expire(now);
        let identifier = metadata
            .identifier
            .clone()
            .unwrap_or_else(|| "0".to_string());

        match metadata.payload_kind {
            KittyNotificationPayloadKind::Query => {
                self.push_response(
                    format!("\x1b]99;i={identifier}:p=?;{OSC99_CAPABILITY_PAYLOAD}\x1b\\")
                        .as_bytes(),
                );
            }
            KittyNotificationPayloadKind::Alive => {
                let active = self.kitty_notification_state.active_identifiers().join(",");
                self.push_response(
                    format!("\x1b]99;i={identifier}:p=alive;{active}\x1b\\").as_bytes(),
                );
            }
            KittyNotificationPayloadKind::Close => {
                if self.kitty_notification_state.close(&identifier).is_none() {
                    return;
                }
                self.enqueue_notification(Notification::kitty(
                    NotificationAction::Close,
                    Some(identifier),
                    KittyNotificationAssembly::default(),
                ));
            }
            KittyNotificationPayloadKind::Unsupported => {
                self.kitty_notification_state.discard_pending(&identifier);
            }
            KittyNotificationPayloadKind::Title
            | KittyNotificationPayloadKind::Body
            | KittyNotificationPayloadKind::Buttons => {
                let Some(payload) = joined_osc_payload(&params[2..]) else {
                    return;
                };
                let Some(payload) = decode_kitty_notification_payload(&payload, metadata.encoded)
                else {
                    self.kitty_notification_state.discard_pending(&identifier);
                    return;
                };

                let mut assembly = if metadata.done {
                    self.kitty_notification_state
                        .take_pending(&identifier)
                        .unwrap_or_default()
                } else {
                    let Some(assembly) = self.kitty_notification_state.pending_mut(&identifier)
                    else {
                        return;
                    };
                    apply_kitty_metadata(assembly, &metadata);
                    match metadata.payload_kind {
                        KittyNotificationPayloadKind::Title => append_sanitized_bounded(
                            &mut assembly.title,
                            &payload,
                            MAX_KITTY_NOTIFICATION_TITLE_CHARS,
                        ),
                        KittyNotificationPayloadKind::Body => append_sanitized_bounded(
                            &mut assembly.body,
                            &payload,
                            MAX_KITTY_NOTIFICATION_BODY_CHARS,
                        ),
                        KittyNotificationPayloadKind::Buttons => append_sanitized_bounded(
                            &mut assembly.button_payload,
                            &payload,
                            MAX_KITTY_NOTIFICATION_BUTTON_PAYLOAD_CHARS,
                        ),
                        _ => unreachable!(),
                    }
                    return;
                };

                apply_kitty_metadata(&mut assembly, &metadata);
                match metadata.payload_kind {
                    KittyNotificationPayloadKind::Title => append_sanitized_bounded(
                        &mut assembly.title,
                        &payload,
                        MAX_KITTY_NOTIFICATION_TITLE_CHARS,
                    ),
                    KittyNotificationPayloadKind::Body => append_sanitized_bounded(
                        &mut assembly.body,
                        &payload,
                        MAX_KITTY_NOTIFICATION_BODY_CHARS,
                    ),
                    KittyNotificationPayloadKind::Buttons => append_sanitized_bounded(
                        &mut assembly.button_payload,
                        &payload,
                        MAX_KITTY_NOTIFICATION_BUTTON_PAYLOAD_CHARS,
                    ),
                    _ => unreachable!(),
                }
                finalize_kitty_buttons(&mut assembly);
                if assembly.title.is_empty() {
                    if assembly.body.is_empty() {
                        return;
                    }
                    assembly.title = assembly.body.clone();
                    assembly.body.clear();
                }

                let was_active = self.kitty_notification_state.is_active(&identifier);
                let expires_at = assembly
                    .expires_after_ms
                    .filter(|expiry| *expiry > 0)
                    .map(|expiry| now.saturating_add(expiry as u64));
                if !self
                    .kitty_notification_state
                    .activate(identifier.clone(), expires_at)
                {
                    return;
                }
                let action = if was_active {
                    NotificationAction::Update
                } else {
                    NotificationAction::Show
                };
                self.enqueue_notification(Notification::kitty(action, Some(identifier), assembly));
            }
        }
    }

    /// Remove an OSC 99 identifier after an attributable product dismissal.
    /// This synchronizes `p=alive` without emitting a child-originated close
    /// event or trusting product-supplied response bytes.
    pub fn dismiss_osc99_notification(&mut self, identifier: &str) -> bool {
        if identifier.is_empty()
            || identifier.len() > MAX_KITTY_NOTIFICATION_ID_BYTES
            || !identifier
                .bytes()
                .all(is_kitty_notification_identifier_byte)
        {
            return false;
        }
        self.kitty_notification_state
            .expire(crate::terminal::unix_millis());
        self.kitty_notification_state.close(identifier).is_some()
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
    use crate::terminal::{NotificationAction, Terminal};

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

    #[test]
    fn kitty_osc99_supports_plain_title_and_semicolons() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]99;;Build; complete\x1b\\");

        let notifications = terminal.take_notifications();
        assert_eq!(notifications.len(), 1);
        assert_eq!(notifications[0].source, "osc99");
        assert_eq!(notifications[0].action, NotificationAction::Show);
        assert_eq!(notifications[0].identifier.as_deref(), Some("0"));
        assert_eq!(notifications[0].title, "Build; complete");
        assert_eq!(notifications[0].message, "");
    }

    #[test]
    fn kitty_osc99_assembles_base64_title_body_and_metadata() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]99;i=job-1:d=0:e=1:f=YnVpbGRjdGw=:t=ZGVwbG95:w=250;RGVwbG95\x1b\\");
        assert!(terminal.notifications().is_empty());
        terminal.process(b"\x1b]99;i=job-1:p=body:e=1;Q29tcGxldGU=\x1b\\");

        let notification = terminal.take_notifications().pop().unwrap();
        assert_eq!(notification.action, NotificationAction::Show);
        assert_eq!(notification.identifier.as_deref(), Some("job-1"));
        assert_eq!(notification.title, "Deploy");
        assert_eq!(notification.message, "Complete");
        assert_eq!(notification.application_name.as_deref(), Some("buildctl"));
        assert_eq!(notification.notification_types, ["deploy"]);
        assert_eq!(notification.expires_after_ms, Some(250));
    }

    #[test]
    fn kitty_osc99_updates_and_closes_only_known_identifiers() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]99;i=job;First\x1b\\");
        terminal.process(b"\x1b]99;i=job;Second\x1b\\");
        terminal.process(b"\x1b]99;i=missing:p=close;\x1b\\");
        terminal.process(b"\x1b]99;i=job:p=close;\x1b\\");
        terminal.process(b"\x1b]99;p=close;\x1b\\");

        let notifications = terminal.take_notifications();
        assert_eq!(notifications.len(), 3);
        assert_eq!(notifications[0].action, NotificationAction::Show);
        assert_eq!(notifications[1].action, NotificationAction::Update);
        assert_eq!(notifications[1].title, "Second");
        assert_eq!(notifications[2].action, NotificationAction::Close);
        assert_eq!(notifications[2].identifier.as_deref(), Some("job"));
    }

    #[test]
    fn kitty_osc99_capability_query_reports_only_safe_subset() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]99;i=probe-1:p=?;\x1b\\");

        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]99;i=probe-1:p=?;a=report:c=1:o=always:p=title,body,close,alive,buttons:w=1\x1b\\"
        );
        assert!(terminal.notifications().is_empty());
    }

    #[test]
    fn kitty_osc99_rejects_malformed_and_unsupported_payloads() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]99;i=bad:d=2;ignored\x1b\\");
        terminal.process(b"\x1b]99;i=bad:p=buttons;ignored\x1b\\");
        terminal.process(b"\x1b]99;i=bad:e=1;not-base64!\x1b\\");
        terminal.process(b"\x1b]99;i=bad key;ignored\x1b\\");
        terminal.process(b"\x1b]99;i=bad:w=4294967296;ignored\x1b\\");
        terminal.process(b"\x1b]99;i=bad:o=unfocused;ignored\x1b\\");

        assert!(terminal.notifications().is_empty());
        assert_eq!(terminal.kitty_notification_state.retained_counts(), (0, 0));
    }

    #[test]
    fn kitty_osc99_bounds_pending_and_active_identifiers() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_max_notifications(128);
        for index in 0..65 {
            terminal.process(format!("\x1b]99;i=p{index}:d=0;chunk\x1b\\").as_bytes());
        }
        assert_eq!(terminal.kitty_notification_state.retained_counts().0, 64);

        for index in 0..65 {
            terminal.process(format!("\x1b]99;i=a{index};done\x1b\\").as_bytes());
        }
        assert_eq!(terminal.kitty_notification_state.retained_counts().1, 64);
        assert_eq!(terminal.notifications().len(), 64);
    }

    #[test]
    fn kitty_osc99_expired_identifier_is_not_treated_as_update() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]99;i=short:w=1;First\x1b\\");
        terminal.kitty_notification_state.expire(u64::MAX);
        terminal.process(b"\x1b]99;i=short;Second\x1b\\");

        let notifications = terminal.take_notifications();
        assert_eq!(notifications.len(), 2);
        assert_eq!(notifications[0].action, NotificationAction::Show);
        assert_eq!(notifications[1].action, NotificationAction::Show);
    }

    #[test]
    fn kitty_osc99_pending_chunks_survive_snapshot_restore() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]99;i=snapshot:d=0;Title\x1b\\");
        let snapshot = terminal.capture_snapshot();

        let mut restored = Terminal::new(80, 24);
        restored.restore_from_snapshot(snapshot);
        restored.process(b"\x1b]99;i=snapshot:p=body;Body\x1b\\");

        let notification = restored.take_notifications().pop().unwrap();
        assert_eq!(notification.title, "Title");
        assert_eq!(notification.message, "Body");
    }

    #[test]
    fn kitty_osc99_pending_buttons_and_report_metadata_survive_snapshot_restore() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]99;i=snapshot-actions:d=0:a=report:c=1;Deploy\x1b\\");
        terminal
            .process("\x1b]99;i=snapshot-actions:p=buttons:d=0;Approve\u{2028}\x1b\\".as_bytes());
        let snapshot = terminal.capture_snapshot();

        let mut restored = Terminal::new(80, 24);
        restored.restore_from_snapshot(snapshot);
        restored.process(b"\x1b]99;i=snapshot-actions:p=buttons;Retry\x1b\\");

        let notification = restored.take_notifications().pop().unwrap();
        assert_eq!(notification.title, "Deploy");
        assert_eq!(notification.buttons, ["Approve", "Retry"]);
        assert!(notification.report_activation);
        assert!(notification.report_close);
    }

    #[test]
    fn kitty_osc99_handles_byte_splits_and_bel_or_st_terminators() {
        for sequence in [
            b"\x1b]99;i=st;ST\x1b\\".as_slice(),
            b"\x1b]99;i=bel;BEL\x07".as_slice(),
        ] {
            let mut terminal = Terminal::new(80, 24);
            for byte in sequence.chunks(1) {
                terminal.process(byte);
            }
            let notification = terminal.take_notifications().pop().unwrap();
            assert_eq!(
                notification.title,
                if sequence.ends_with(b"\x07") {
                    "BEL"
                } else {
                    "ST"
                }
            );
        }
    }

    #[test]
    fn kitty_osc99_rejects_oversized_chunks_and_never_enables_actions() {
        let mut terminal = Terminal::new(80, 24);
        let mut oversized_plain = b"\x1b]99;i=plain;".to_vec();
        oversized_plain.extend(std::iter::repeat_n(b'x', 2049));
        oversized_plain.extend_from_slice(b"\x1b\\");
        terminal.process(&oversized_plain);

        let mut oversized_base64 = b"\x1b]99;i=encoded:e=1;".to_vec();
        oversized_base64.extend(std::iter::repeat_n(b'A', 4097));
        oversized_base64.extend_from_slice(b"\x1b\\");
        terminal.process(&oversized_base64);

        terminal.process(b"\x1b]99;i=safe:a=focus:s=Y3VzdG9t:g=aWNvbg==;Safe notification\x1b\\");

        let notifications = terminal.take_notifications();
        assert_eq!(notifications.len(), 1);
        assert_eq!(notifications[0].identifier.as_deref(), Some("safe"));
        assert_eq!(notifications[0].title, "Safe notification");
        assert!(!notifications[0].report_activation);
        assert!(terminal.drain_responses().is_empty());
    }

    #[test]
    fn kitty_osc99_supports_report_only_actions_and_bounded_buttons() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]99;i=deploy:d=0:a=report,focus:c=1;Deploy ready\x1b\\");
        terminal.process(
            "\x1b]99;i=deploy:p=buttons;Approve\u{2028}Retry\u{2028}Logs\u{2028}Cancel\u{2028}Later\u{2028}Ignored\x1b\\"
                .as_bytes(),
        );

        let notification = terminal.take_notifications().pop().unwrap();
        assert_eq!(notification.identifier.as_deref(), Some("deploy"));
        assert!(notification.report_activation);
        assert!(notification.report_close);
        assert_eq!(
            notification.buttons,
            ["Approve", "Retry", "Logs", "Cancel", "Later"]
        );

        terminal.process(b"\x1b]99;i=empty-slots:d=0:a=report;Choose\x1b\\");
        terminal.process("\x1b]99;i=empty-slots:p=buttons;\u{2028}Retry\x1b\\".as_bytes());
        let empty_slots = terminal.take_notifications().pop().unwrap();
        assert_eq!(empty_slots.buttons, ["", "Retry"]);

        terminal.process(b"\x1b]99;i=deploy:a=-report,-focus;Updated\x1b\\");
        let updated = terminal.take_notifications().pop().unwrap();
        assert_eq!(updated.action, NotificationAction::Update);
        assert!(!updated.report_activation);
        assert!(!updated.report_close);
        assert!(updated.buttons.is_empty());
    }

    #[test]
    fn kitty_osc99_alive_query_and_default_identifier_follow_lifecycle() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]99;;Default\x1b\\");
        terminal.process(b"\x1b]99;i=build;Build\x1b\\");
        terminal.process(b"\x1b]99;i=query:p=alive;\x1b\\");

        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]99;i=query:p=alive;0,build\x1b\\"
        );

        terminal.process(b"\x1b]99;p=close;\x1b\\");
        let notifications = terminal.take_notifications();
        assert_eq!(
            notifications.last().unwrap().action,
            NotificationAction::Close
        );
        assert_eq!(
            notifications.last().unwrap().identifier.as_deref(),
            Some("0")
        );

        terminal.process(b"\x1b]99;i=query:p=alive;\x1b\\");
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]99;i=query:p=alive;build\x1b\\"
        );

        assert!(terminal.dismiss_osc99_notification("build"));
        assert!(!terminal.dismiss_osc99_notification("build"));
        assert!(!terminal.dismiss_osc99_notification("bad:id"));
        assert!(!terminal.dismiss_osc99_notification("bad?id"));
        terminal.process(b"\x1b]99;i=query:p=alive;\x1b\\");
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]99;i=query:p=alive;\x1b\\"
        );
    }

    #[test]
    fn kitty_osc99_rejects_unknown_actions_and_invalid_close_reporting() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]99;i=command:a=command;Ignored\x1b\\");
        terminal.process(b"\x1b]99;i=close:c=2;Ignored\x1b\\");
        terminal.process(b"\x1b]99;i=bad?id:a=report;Ignored\x1b\\");
        terminal.process(b"\x1b]99;i=bad?id:p=?;\x1b\\");

        assert!(terminal.notifications().is_empty());
        assert!(terminal.drain_responses().is_empty());
        assert_eq!(terminal.kitty_notification_state.retained_counts(), (0, 0));
    }
}
