use super::recording_snapshot::NativeCaptureSnapshot;
use super::*;
use crate::recording::{
    AdaptiveSampler, BackgroundWriter, HookTimeline, RecordedAsset, RecordingMetadata,
    SampleRecord, SamplingPolicy, StorageError, StorageResult, VisualSample, WriterPhase,
    WriterStatus,
};
use std::path::Path;

pub(super) struct SampledCapture {
    token: String,
    started: Instant,
    sampler: AdaptiveSampler,
    timeline: HookTimeline,
    assets: Vec<RecordedAsset>,
    writer: BackgroundWriter,
}

impl SampledCapture {
    fn now(&self) -> u64 {
        self.started.elapsed().as_micros().min(u128::from(u64::MAX)) as u64
    }
    fn active(&self) -> bool {
        self.writer.status().phase == WriterPhase::Capturing
    }

    fn visual(&mut self, sample: VisualSample) -> StorageResult<()> {
        self.writer.enqueue_visual(sample, self.assets.clone())
    }

    fn snapshot(&mut self, offset: u64, snapshot: NativeCaptureSnapshot) -> StorageResult<()> {
        self.sampler
            .set_writer_pressure(self.writer.pressure_percent());
        self.assets = snapshot.assets;
        if let Some(sample) = self.sampler.observe_frame(offset, snapshot.frame)? {
            self.visual(sample)?;
        }
        Ok(())
    }

    fn event(&mut self, event: crate::recording::SemanticEvent) -> StorageResult<()> {
        for record in self.sampler.observe_semantic(event)? {
            match record {
                SampleRecord::Visual(sample) => self.visual(*sample)?,
                SampleRecord::Semantic(event) => self.writer.enqueue_semantic(&event)?,
            }
        }
        Ok(())
    }

    fn fail(&mut self, error: StorageError) {
        self.writer.interrupt(error.to_string());
    }
}

impl TerminalSession {
    pub(super) fn start_sampled_capture(
        self: &Arc<Self>,
        path: &Path,
        metadata: &RecordingMetadata,
    ) -> StorageResult<WriterStatus> {
        if !path.is_absolute() {
            return Err(StorageError::Invalid("recording path must be absolute"));
        }
        if self.exited.load(Ordering::SeqCst) {
            return Err(StorageError::Invalid("session already exited"));
        }
        let mut slot = self.sampled_capture.lock();
        if slot.as_ref().is_some_and(|capture| {
            matches!(
                capture.writer.status().phase,
                WriterPhase::Capturing | WriterPhase::Finishing
            )
        }) {
            return Err(StorageError::Invalid(
                "session already has an active recording",
            ));
        }
        let initial = self.recording_snapshot()?.ok_or(StorageError::Invalid(
            "screen is in a synchronized update; retry start",
        ))?;
        let mut sampler = AdaptiveSampler::new(SamplingPolicy::default())?;
        let first = sampler
            .observe_frame(0, initial.frame)?
            .ok_or(StorageError::Invalid("missing initial recording frame"))?;
        let timeline = self
            .recording_timeline
            .lock()
            .for_recording(metadata.hostname.as_deref());
        let writer = BackgroundWriter::start(path, metadata)?;
        let mut capture = SampledCapture {
            token: crate::shell_bootstrap::token(),
            started: Instant::now(),
            sampler,
            timeline,
            assets: initial.assets,
            writer,
        };
        capture.visual(first)?;
        for event in capture.timeline.initial_events() {
            capture.event(event)?;
        }
        let token = capture.token.clone();
        let weak = Arc::downgrade(self);
        *slot = Some(capture);
        // The timer owns no strong session reference while sleeping. Closing a
        // session never waits for disk I/O, and dropping it interrupts capture.
        if let Err(error) = thread::Builder::new()
            .name("trail-recording-sampler".into())
            .spawn(move || {
                loop {
                    thread::sleep(Duration::from_millis(100));
                    let Some(session) = weak.upgrade() else {
                        break;
                    };
                    if !session.sampled_capture_tick(&token) {
                        break;
                    }
                }
            })
        {
            slot.as_mut().unwrap().writer.interrupt(error.to_string());
            return Err(error.into());
        }
        Ok(slot.as_ref().unwrap().writer.status())
    }

    fn sampled_capture_tick(&self, token: &str) -> bool {
        let child_status = self.observe_child_exit();
        let mut slot = self.sampled_capture.lock();
        let Some(capture) = slot
            .as_mut()
            .filter(|capture| capture.token == token && capture.active())
        else {
            return false;
        };
        let result = (|| {
            child_status.map_err(|error| StorageError::Runtime(error.to_string()))?;
            if let Some(snapshot) = self.recording_snapshot()? {
                capture.snapshot(capture.now(), snapshot)?;
            }
            if let Some(sample) = capture.sampler.tick(capture.now())? {
                capture.visual(sample)?;
            }
            Ok(())
        })();
        if let Err(error) = result {
            capture.fail(error);
            return false;
        }
        true
    }

    /// Invoked before UI queue admission. Independent ordering and queue failure
    /// are owned by the recording, not by frontend event polling/coalescing.
    pub(super) fn observe_sampled_hook(&self, payload: &serde_json::Value, context_only: bool) {
        self.recording_timeline
            .lock()
            .observe_live(payload, context_only);
        let mut slot = self.sampled_capture.lock();
        let Some(capture) = slot.as_mut().filter(|capture| capture.active()) else {
            return;
        };
        let result = (|| {
            if let Some(snapshot) = self.recording_snapshot()? {
                capture.snapshot(capture.now(), snapshot)?;
            }
            let offset = capture.now();
            let events = if context_only {
                capture.timeline.observe_context(offset, payload)?
            } else {
                capture.timeline.observe_hook(offset, payload)?
            };
            for event in events {
                capture.event(event)?;
            }
            Ok(())
        })();
        if let Err(error) = result {
            capture.fail(error);
        }
    }

    pub(super) fn stop_sampled_capture(&self) -> StorageResult<Option<WriterStatus>> {
        let mut slot = self.sampled_capture.lock();
        let Some(capture) = slot.as_mut() else {
            return Ok(None);
        };
        if !capture.active() {
            return Ok(Some(capture.writer.status()));
        }
        let result = (|| {
            if let Some(snapshot) = self.recording_snapshot()? {
                capture.snapshot(capture.now(), snapshot)?;
            }
            let offset = capture.now();
            if let Some(sample) = capture.sampler.finish(offset)? {
                capture.visual(sample)?;
            }
            capture.writer.request_finish(offset)
        })();
        if let Err(error) = result {
            capture.fail(error);
        }
        Ok(Some(capture.writer.status()))
    }
}

pub fn start_sampled_recording(
    session_id: u64,
    path: &Path,
    metadata: &RecordingMetadata,
) -> StorageResult<WriterStatus> {
    STORE
        .get(session_id)
        .map_err(|error| StorageError::Runtime(error.to_string()))?
        .start_sampled_capture(path, metadata)
}
pub fn stop_sampled_recording(session_id: u64) -> StorageResult<Option<WriterStatus>> {
    STORE
        .get(session_id)
        .map_err(|error| StorageError::Runtime(error.to_string()))?
        .stop_sampled_capture()
}
pub fn sampled_recording_status(session_id: u64) -> StorageResult<Option<WriterStatus>> {
    let session = STORE
        .get(session_id)
        .map_err(|error| StorageError::Runtime(error.to_string()))?;
    Ok(session
        .sampled_capture
        .lock()
        .as_ref()
        .map(|capture| capture.writer.status()))
}
