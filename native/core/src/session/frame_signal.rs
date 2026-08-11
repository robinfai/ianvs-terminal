use super::frame::PendingFrameWork;
use parking_lot::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

#[derive(Clone, Debug)]
pub(super) struct DeferredFrameGrace {
    pub(super) damage_generation: u64,
    pub(super) started_at: Instant,
}

pub(super) struct PendingFrameSignal {
    dirty: AtomicBool,
    refresh_hint_dirty: AtomicBool,
    work: Mutex<PendingFrameWork>,
}

impl PendingFrameSignal {
    pub(super) fn new(initially_dirty: bool) -> Self {
        Self {
            dirty: AtomicBool::new(initially_dirty),
            refresh_hint_dirty: AtomicBool::new(initially_dirty),
            work: Mutex::new(PendingFrameWork::default()),
        }
    }

    pub(super) fn is_dirty(&self) -> bool {
        self.dirty.load(Ordering::SeqCst)
    }

    pub(super) fn mutate(&self, mutation: impl FnOnce(&mut PendingFrameWork)) {
        self.mutate_inner(false, mutation);
    }

    pub(super) fn mutate_reader(&self, mutation: impl FnOnce(&mut PendingFrameWork)) {
        self.mutate_inner(true, mutation);
    }

    fn mutate_inner(&self, sets_refresh_hint: bool, mutation: impl FnOnce(&mut PendingFrameWork)) {
        let mut work = self.work.lock();
        mutation(&mut work);
        self.dirty.store(true, Ordering::SeqCst);
        if sets_refresh_hint {
            self.refresh_hint_dirty.store(true, Ordering::SeqCst);
        }
    }

    pub(super) fn take(&self) -> (bool, bool, PendingFrameWork) {
        let mut work = self.work.lock();
        let was_dirty = self.dirty.swap(false, Ordering::SeqCst);
        let refresh_hint_was_dirty = self.refresh_hint_dirty.swap(false, Ordering::SeqCst);
        (
            was_dirty,
            refresh_hint_was_dirty,
            std::mem::take(&mut *work),
        )
    }

    pub(super) fn restore(&self, deferred_work: PendingFrameWork, restore_refresh_hint: bool) {
        let mut current_work = self.work.lock();
        if current_work.is_empty() {
            *current_work = deferred_work;
        } else if !deferred_work.is_empty() {
            let damage_generation = current_work
                .damage_generation
                .max(deferred_work.damage_generation)
                .saturating_add(1);
            let cursor_before = deferred_work
                .cursor_before
                .or_else(|| current_work.cursor_before.take());
            let cursor_after = current_work
                .cursor_after
                .take()
                .or(deferred_work.cursor_after);
            let snapshot_fallback_reason = deferred_work
                .snapshot_fallback_reason
                .or_else(|| current_work.snapshot_fallback_reason.take())
                .or_else(|| Some("concurrent_deferred_damage".to_string()));
            *current_work = PendingFrameWork {
                full_repaint: true,
                snapshot_fallback_reason,
                cursor_before,
                cursor_after,
                damage_generation,
                ..PendingFrameWork::default()
            };
        }
        self.dirty.store(true, Ordering::SeqCst);
        if restore_refresh_hint {
            self.refresh_hint_dirty.store(true, Ordering::SeqCst);
        }
    }

    pub(super) fn has_refresh_hint(&self) -> bool {
        self.refresh_hint_dirty.load(Ordering::SeqCst)
    }

    pub(super) fn snapshot(&self) -> PendingFrameWork {
        self.work.lock().clone()
    }
}

pub(super) fn should_defer_with_grace(
    deferred_frame: &Mutex<Option<DeferredFrameGrace>>,
    damage_generation: u64,
    grace: Duration,
) -> bool {
    let mut deferred = deferred_frame.lock();
    if let Some(frame) = deferred
        .as_ref()
        .filter(|frame| frame.damage_generation == damage_generation)
    {
        if frame.started_at.elapsed() < grace {
            return true;
        }
        *deferred = None;
        return false;
    }

    *deferred = Some(DeferredFrameGrace {
        damage_generation,
        started_at: Instant::now(),
    });
    true
}
