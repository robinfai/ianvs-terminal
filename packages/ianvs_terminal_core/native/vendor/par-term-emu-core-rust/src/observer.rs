//! Terminal observer trait for push-based event delivery
//!
//! Observers receive terminal events via trait callbacks after each `process()` call.
//! Events are dispatched after processing completes (deferred dispatch), ensuring
//! no internal mutexes are held during callbacks.

use std::collections::HashSet;
use std::sync::Arc;

use crate::terminal::{TerminalEvent, TerminalEventKind};

/// Unique identifier for a registered observer
pub type ObserverId = u64;

/// Terminal event observer trait
///
/// Implement this trait to receive push-based terminal events. All methods have
/// default no-op implementations, so you only need to override the ones you care about.
///
/// Events are dispatched in two phases:
/// 1. Category-specific method (`on_zone_event`, `on_command_event`, etc.)
/// 2. Catch-all `on_event` (always called for every event)
///
/// # Thread Safety
/// Observers must be `Send + Sync` since they may be called from different threads.
/// Dispatch happens after `process()` returns — no Terminal internal state is borrowed.
pub trait TerminalObserver: Send + Sync {
    /// Called for zone lifecycle events (ZoneOpened, ZoneClosed, ZoneScrolledOut)
    fn on_zone_event(&self, _event: &TerminalEvent) {}

    /// Called for command/shell integration events (ShellIntegrationEvent)
    fn on_command_event(&self, _event: &TerminalEvent) {}

    /// Called for environment changes (CwdChanged, EnvironmentChanged,
    /// RemoteHostTransition, SubShellDetected)
    fn on_environment_event(&self, _event: &TerminalEvent) {}

    /// Called for screen content events (BellRang, TitleChanged, SizeChanged,
    /// ModeChanged, GraphicsAdded, HyperlinkAdded, DirtyRegion, UserVarChanged,
    /// ProgressBarChanged, BadgeChanged, TriggerMatched)
    fn on_screen_event(&self, _event: &TerminalEvent) {}

    /// Called for ALL events (catch-all). Called after category-specific methods.
    fn on_event(&self, _event: &TerminalEvent) {}

    /// Which event kinds this observer is interested in (None = all)
    fn subscriptions(&self) -> Option<&HashSet<TerminalEventKind>> {
        None
    }
}

/// Internal entry for a registered observer
pub(crate) struct ObserverEntry {
    pub id: ObserverId,
    pub observer: Arc<dyn TerminalObserver>,
}

/// Event category for routing to observer methods
pub(crate) enum EventCategory {
    Zone,
    Command,
    Environment,
    Screen,
}

/// Categorize an event for routing to the appropriate observer method
pub(crate) fn event_category(event: &TerminalEvent) -> EventCategory {
    match event {
        TerminalEvent::ZoneOpened { .. }
        | TerminalEvent::ZoneClosed { .. }
        | TerminalEvent::ZoneScrolledOut { .. } => EventCategory::Zone,

        TerminalEvent::ShellIntegrationEvent { .. } => EventCategory::Command,

        TerminalEvent::CwdChanged(_)
        | TerminalEvent::EnvironmentChanged { .. }
        | TerminalEvent::RemoteHostTransition { .. }
        | TerminalEvent::SubShellDetected { .. } => EventCategory::Environment,

        _ => EventCategory::Screen,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal::Terminal;
    use std::sync::Mutex;

    #[derive(Default)]
    struct RecordingObserver {
        kinds: Mutex<Vec<TerminalEventKind>>,
    }

    impl TerminalObserver for RecordingObserver {
        fn on_event(&self, event: &TerminalEvent) {
            self.kinds.lock().unwrap().push(event.kind());
        }
    }

    #[test]
    fn specialized_polling_preserves_push_observer_dispatch_cursor() {
        let observer = Arc::new(RecordingObserver::default());
        let mut terminal = Terminal::new(80, 24);
        terminal.add_observer(observer.clone());

        terminal.process(b"\x1b]7;file:///tmp/one\x07\x1b]2;first\x07");
        assert_eq!(terminal.poll_cwd_events().len(), 1);
        terminal.process(b"\x1b]2;second\x07");

        assert_eq!(
            *observer.kinds.lock().unwrap(),
            vec![
                TerminalEventKind::CwdChanged,
                TerminalEventKind::EnvironmentChanged,
                TerminalEventKind::TitleChanged,
                TerminalEventKind::TitleChanged,
            ],
        );
    }

    #[test]
    fn observer_registration_survives_ris_and_receives_reset() {
        let observer = Arc::new(RecordingObserver::default());
        let mut terminal = Terminal::new(80, 24);
        let observer_id = terminal.add_observer(observer.clone());

        terminal.process(b"\x1bc");
        terminal.process(b"\x1b]2;after reset\x07");

        assert_eq!(terminal.observer_count(), 1);
        assert!(terminal.remove_observer(observer_id));
        assert_eq!(
            *observer.kinds.lock().unwrap(),
            vec![
                TerminalEventKind::TerminalReset,
                TerminalEventKind::TitleChanged,
            ],
        );
    }
}
