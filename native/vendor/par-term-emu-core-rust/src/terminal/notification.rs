//! Notification support for OSC 9, OSC 99 and OSC 777 sequences.

use std::collections::HashMap;

pub(crate) const MAX_KITTY_NOTIFICATION_IDS: usize = 64;
pub(crate) const MAX_KITTY_NOTIFICATION_ID_BYTES: usize = 128;
pub(crate) const MAX_KITTY_NOTIFICATION_TITLE_CHARS: usize = 160;
pub(crate) const MAX_KITTY_NOTIFICATION_BODY_CHARS: usize = 512;
pub(crate) const MAX_KITTY_NOTIFICATION_APPLICATION_CHARS: usize = 160;
pub(crate) const MAX_KITTY_NOTIFICATION_TYPE_CHARS: usize = 64;
pub(crate) const MAX_KITTY_NOTIFICATION_TYPES: usize = 8;
pub(crate) const MAX_KITTY_NOTIFICATION_BUTTONS: usize = 5;
pub(crate) const MAX_KITTY_NOTIFICATION_BUTTON_CHARS: usize = 64;

/// Lifecycle action represented by a terminal notification event.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NotificationAction {
    /// Display a newly created notification.
    Show,
    /// Replace a still-active notification with the same identifier.
    Update,
    /// Close a still-active notification.
    Close,
}

impl NotificationAction {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Show => "show",
            Self::Update => "update",
            Self::Close => "close",
        }
    }
}

/// Notification data from OSC 9 or OSC 777 sequences
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notification {
    /// Canonical protocol source (`osc` for legacy OSC 9/777 or `osc99`).
    pub source: &'static str,
    /// Notification lifecycle action.
    pub action: NotificationAction,
    /// Protocol identifier used for update and close correlation.
    pub identifier: Option<String>,
    /// Notification title (may be empty for OSC 9)
    pub title: String,
    /// Notification message/body
    pub message: String,
    /// Optional Base64-decoded application name from Kitty's `f` metadata.
    pub application_name: Option<String>,
    /// Bounded Base64-decoded Kitty notification types.
    pub notification_types: Vec<String>,
    /// `None` uses platform policy, `Some(0)` requests no automatic expiry,
    /// and a positive value is a bounded expiry duration in milliseconds.
    pub expires_after_ms: Option<u32>,
    /// Whether an explicit user activation should be reported to the child.
    pub report_activation: bool,
    /// Whether an explicit or timed close should be reported to the child.
    pub report_close: bool,
    /// Bounded, presentation-only button labels. Labels never contain commands.
    pub buttons: Vec<String>,
}

impl Notification {
    /// Create a new notification
    pub fn new(title: String, message: String) -> Self {
        Self {
            source: "osc",
            action: NotificationAction::Show,
            identifier: None,
            title,
            message,
            application_name: None,
            notification_types: Vec::new(),
            expires_after_ms: None,
            report_activation: false,
            report_close: false,
            buttons: Vec::new(),
        }
    }

    pub(crate) fn kitty(
        action: NotificationAction,
        identifier: Option<String>,
        assembly: KittyNotificationAssembly,
    ) -> Self {
        Self {
            source: "osc99",
            action,
            identifier,
            title: assembly.title,
            message: assembly.body,
            application_name: assembly.application_name,
            notification_types: assembly.notification_types,
            expires_after_ms: assembly.expires_after_ms,
            report_activation: assembly.report_activation,
            report_close: assembly.report_close,
            buttons: assembly.buttons,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct KittyNotificationAssembly {
    pub(crate) title: String,
    pub(crate) body: String,
    pub(crate) application_name: Option<String>,
    pub(crate) notification_types: Vec<String>,
    pub(crate) expires_after_ms: Option<u32>,
    pub(crate) report_activation: bool,
    pub(crate) report_close: bool,
    pub(crate) button_payload: String,
    pub(crate) buttons: Vec<String>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct KittyActiveNotification {
    pub(crate) expires_at_unix_ms: Option<u64>,
}

/// Bounded OSC 99 chunk and lifecycle state retained per terminal session.
#[derive(Debug, Clone, Default)]
pub(crate) struct KittyNotificationState {
    pending: HashMap<String, KittyNotificationAssembly>,
    active: HashMap<String, KittyActiveNotification>,
}

impl KittyNotificationState {
    pub(crate) fn pending_mut(
        &mut self,
        identifier: &str,
    ) -> Option<&mut KittyNotificationAssembly> {
        if !self.pending.contains_key(identifier)
            && self.pending.len() >= MAX_KITTY_NOTIFICATION_IDS
        {
            return None;
        }
        Some(self.pending.entry(identifier.to_string()).or_default())
    }

    pub(crate) fn take_pending(&mut self, identifier: &str) -> Option<KittyNotificationAssembly> {
        self.pending.remove(identifier)
    }

    pub(crate) fn discard_pending(&mut self, identifier: &str) {
        self.pending.remove(identifier);
    }

    pub(crate) fn expire(&mut self, now_unix_ms: u64) {
        self.active.retain(|_, notification| {
            notification
                .expires_at_unix_ms
                .is_none_or(|expires_at| expires_at > now_unix_ms)
        });
    }

    pub(crate) fn is_active(&self, identifier: &str) -> bool {
        self.active.contains_key(identifier)
    }

    pub(crate) fn activate(&mut self, identifier: String, expires_at_unix_ms: Option<u64>) -> bool {
        let was_active = self.active.contains_key(&identifier);
        if !was_active && self.active.len() >= MAX_KITTY_NOTIFICATION_IDS {
            return false;
        }
        self.active
            .insert(identifier, KittyActiveNotification { expires_at_unix_ms });
        true
    }

    pub(crate) fn close(&mut self, identifier: &str) -> Option<KittyActiveNotification> {
        self.pending.remove(identifier);
        self.active.remove(identifier)
    }

    pub(crate) fn active_identifiers(&self) -> Vec<&str> {
        let mut identifiers = self.active.keys().map(String::as_str).collect::<Vec<_>>();
        identifiers.sort_unstable();
        identifiers
    }

    pub(crate) fn retained_bytes(&self) -> usize {
        let pending = self
            .pending
            .iter()
            .map(|(identifier, assembly)| {
                identifier.len()
                    + assembly.title.len()
                    + assembly.body.len()
                    + assembly.application_name.as_ref().map_or(0, String::len)
                    + assembly
                        .notification_types
                        .iter()
                        .map(String::len)
                        .sum::<usize>()
                    + assembly.button_payload.len()
                    + assembly.buttons.iter().map(String::len).sum::<usize>()
            })
            .sum::<usize>();
        pending + self.active.keys().map(String::len).sum::<usize>()
    }

    #[cfg(test)]
    pub(crate) fn retained_counts(&self) -> (usize, usize) {
        (self.pending.len(), self.active.len())
    }
}

/// Notification trigger type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum NotificationTrigger {
    /// Terminal bell rang
    Bell,
    /// Terminal activity detected
    Activity,
    /// Silence detected (no activity for duration)
    Silence,
    /// Custom trigger with ID
    Custom(u32),
}

/// Notification alert type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NotificationAlert {
    /// Desktop/system notification
    Desktop,
    /// Sound alert with volume (0-100)
    Sound(u8),
    /// Visual alert (flash, border, etc.)
    Visual,
}

/// Notification event record
#[derive(Debug, Clone)]
pub struct NotificationEvent {
    /// What triggered the notification
    pub trigger: NotificationTrigger,
    /// Type of alert
    pub alert: NotificationAlert,
    /// Optional message
    pub message: Option<String>,
    /// Timestamp when event occurred
    pub timestamp: u64,
    /// Whether notification was delivered
    pub delivered: bool,
}

/// Notification configuration
#[derive(Debug, Clone)]
pub struct NotificationConfig {
    /// Enable desktop notifications on bell
    pub bell_desktop: bool,
    /// Enable sound on bell (0 = disabled, 1-100 = volume)
    pub bell_sound: u8,
    /// Enable visual alert on bell
    pub bell_visual: bool,
    /// Enable notifications on activity
    pub activity_enabled: bool,
    /// Activity threshold (seconds of inactivity before triggering)
    pub activity_threshold: u64,
    /// Enable notifications on silence
    pub silence_enabled: bool,
    /// Silence threshold (seconds of activity before silence notification)
    pub silence_threshold: u64,
}

impl Default for NotificationConfig {
    fn default() -> Self {
        Self {
            bell_desktop: false,
            bell_sound: 0,
            bell_visual: true,
            activity_enabled: false,
            activity_threshold: 10,
            silence_enabled: false,
            silence_threshold: 300,
        }
    }
}

use crate::terminal::Terminal;

impl Terminal {
    // === Feature 37: Terminal Notifications ===

    /// Add a notification event
    pub fn add_notification_event(
        &mut self,
        trigger: NotificationTrigger,
        alert: NotificationAlert,
        message: Option<String>,
    ) {
        let event = NotificationEvent {
            trigger,
            alert,
            message,
            timestamp: crate::terminal::unix_millis(),
            delivered: false,
        };

        self.notification_events.push(event);
        if self.notification_events.len() > self.max_notifications {
            self.notification_events.remove(0);
        }
    }

    /// Get notification configuration
    pub fn notification_config(&self) -> &NotificationConfig {
        &self.notification_config
    }

    /// Get mutable access to notification configuration
    pub fn notification_config_mut(&mut self) -> &mut NotificationConfig {
        &mut self.notification_config
    }

    /// Get notification configuration
    pub fn get_notification_config(&self) -> NotificationConfig {
        self.notification_config.clone()
    }

    /// Set notification configuration
    pub fn set_notification_config(&mut self, config: NotificationConfig) {
        self.notification_config = config;
    }

    /// Get all notification events
    pub fn get_notification_events(&self) -> &[NotificationEvent] {
        &self.notification_events
    }

    /// Clear all notification events
    pub fn clear_notification_events(&mut self) {
        self.notification_events.clear();
    }

    /// Mark a notification as delivered by index
    pub fn mark_notification_delivered(&mut self, index: usize) {
        if let Some(event) = self.notification_events.get_mut(index) {
            event.delivered = true;
        }
    }

    /// Update last activity timestamp
    pub fn update_activity(&mut self) {
        self.last_activity_time = crate::terminal::unix_millis();
    }

    /// Check for silence notification trigger
    pub fn check_silence(&mut self) {
        if !self.notification_config.silence_enabled {
            return;
        }
        let now = crate::terminal::unix_millis();
        if now - self.last_activity_time > self.notification_config.silence_threshold * 1000
            && now - self.last_silence_check > self.notification_config.silence_threshold * 1000
        {
            self.add_notification_event(
                NotificationTrigger::Silence,
                NotificationAlert::Visual,
                Some("Terminal is silent".to_string()),
            );
            self.last_silence_check = now;
        }
    }

    /// Check for activity notification trigger
    pub fn check_activity(&mut self) {
        if self.notification_config.activity_enabled {
            // Implementation for activity check
        }
    }

    /// Register a custom notification trigger
    pub fn register_custom_trigger(&mut self, id: u32, message: String) {
        self.custom_triggers.insert(id, message);
    }

    /// Trigger a custom notification by ID
    pub fn trigger_custom_notification(&mut self, id: u32, alert: NotificationAlert) {
        let message = self.custom_triggers.get(&id).cloned();
        self.add_notification_event(NotificationTrigger::Custom(id), alert, message);
    }

    /// Handle a bell notification
    pub fn handle_bell_notification(&mut self) {
        let alert = if self.notification_config.bell_desktop {
            NotificationAlert::Desktop
        } else if self.notification_config.bell_sound > 0 {
            NotificationAlert::Sound(self.notification_config.bell_sound)
        } else {
            NotificationAlert::Visual
        };
        self.add_notification_event(
            NotificationTrigger::Bell,
            alert,
            Some("Bell rang".to_string()),
        );
    }

    /// Explicitly trigger a notification
    pub fn trigger_notification(
        &mut self,
        trigger: NotificationTrigger,
        alert: NotificationAlert,
        message: Option<String>,
    ) {
        self.add_notification_event(trigger, alert, message);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_notification_new() {
        let notif = Notification::new("Title".to_string(), "Message".to_string());
        assert_eq!(notif.title, "Title");
        assert_eq!(notif.message, "Message");
    }

    #[test]
    fn test_notification_empty_title() {
        let notif = Notification::new("".to_string(), "Message".to_string());
        assert_eq!(notif.title, "");
        assert_eq!(notif.message, "Message");
    }

    #[test]
    fn test_notification_empty_message() {
        let notif = Notification::new("Title".to_string(), "".to_string());
        assert_eq!(notif.title, "Title");
        assert_eq!(notif.message, "");
    }

    #[test]
    fn test_notification_both_empty() {
        let notif = Notification::new("".to_string(), "".to_string());
        assert_eq!(notif.title, "");
        assert_eq!(notif.message, "");
    }

    #[test]
    fn test_notification_clone() {
        let notif1 = Notification::new("Title".to_string(), "Message".to_string());
        let notif2 = notif1.clone();
        assert_eq!(notif1, notif2);
    }

    #[test]
    fn test_notification_equality() {
        let notif1 = Notification::new("Title".to_string(), "Message".to_string());
        let notif2 = Notification::new("Title".to_string(), "Message".to_string());
        assert_eq!(notif1, notif2);
    }

    #[test]
    fn test_notification_inequality_title() {
        let notif1 = Notification::new("Title1".to_string(), "Message".to_string());
        let notif2 = Notification::new("Title2".to_string(), "Message".to_string());
        assert_ne!(notif1, notif2);
    }

    #[test]
    fn test_notification_inequality_message() {
        let notif1 = Notification::new("Title".to_string(), "Message1".to_string());
        let notif2 = Notification::new("Title".to_string(), "Message2".to_string());
        assert_ne!(notif1, notif2);
    }

    #[test]
    fn test_notification_debug() {
        let notif = Notification::new("Title".to_string(), "Message".to_string());
        let debug_str = format!("{:?}", notif);
        assert!(debug_str.contains("Title"));
        assert!(debug_str.contains("Message"));
    }

    #[test]
    fn test_notification_with_unicode() {
        let notif = Notification::new("📢 Alert".to_string(), "Message with emoji 🎉".to_string());
        assert_eq!(notif.title, "📢 Alert");
        assert_eq!(notif.message, "Message with emoji 🎉");
    }

    #[test]
    fn test_notification_with_newlines() {
        let notif = Notification::new(
            "Multi\nLine\nTitle".to_string(),
            "Multi\nLine\nMessage".to_string(),
        );
        assert!(notif.title.contains('\n'));
        assert!(notif.message.contains('\n'));
    }

    #[test]
    fn test_notification_with_special_chars() {
        let notif = Notification::new(
            "Title with \"quotes\" and 'apostrophes'".to_string(),
            "Message with <tags> & symbols".to_string(),
        );
        assert!(notif.title.contains('"'));
        assert!(notif.message.contains('<'));
    }
}
