use super::assets::RecordedAsset;
use super::storage::{
    ContainerWriter, RecordingMetadata, RecordingSummary, StorageError, StorageResult,
};
use super::{SemanticEvent, VisualSample};
use crate::proto::frame_diff::TerminalFrameDiff;
use parking_lot::Mutex;
use prost::Message;
use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, LazyLock, mpsc};
use std::thread;
use std::time::{Duration, Instant};

const COMMIT_INTERVAL: Duration = Duration::from_secs(5);
const MAX_ACTIVE_WRITERS: usize = 16;
const MAX_PENDING_RECORDS: usize = 64;
static SHARED_BUDGET: LazyLock<Arc<QueueBudget>> =
    LazyLock::new(|| QueueBudget::new(64 * 1024 * 1024));

/// Shared admission, including records currently being written. The queue owns
/// serialized bytes, so duration and object-capacity growth cannot evade bounds.
pub struct QueueBudget {
    limit: usize,
    used: AtomicUsize,
    writers: AtomicUsize,
}

impl QueueBudget {
    pub fn new(limit: usize) -> Arc<Self> {
        Arc::new(Self {
            limit,
            used: AtomicUsize::new(0),
            writers: AtomicUsize::new(0),
        })
    }
    pub fn used_bytes(&self) -> usize {
        self.used.load(Ordering::Acquire)
    }
    pub fn pressure_percent(&self) -> u8 {
        if self.limit == 0 {
            return 100;
        }
        ((self.used_bytes() as u128 * 100 / self.limit as u128).min(100)) as u8
    }
    fn reserve(self: &Arc<Self>, bytes: usize) -> StorageResult<BudgetLease> {
        self.used
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |used| {
                used.checked_add(bytes).filter(|next| *next <= self.limit)
            })
            .map_err(|_| StorageError::QueueExhausted)?;
        Ok(BudgetLease {
            budget: self.clone(),
            bytes,
        })
    }
}

struct BudgetLease {
    budget: Arc<QueueBudget>,
    bytes: usize,
}
impl Drop for BudgetLease {
    fn drop(&mut self) {
        self.budget.used.fetch_sub(self.bytes, Ordering::AcqRel);
    }
}
struct WriterLease(Arc<QueueBudget>);
impl Drop for WriterLease {
    fn drop(&mut self) {
        self.0.writers.fetch_sub(1, Ordering::AcqRel);
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WriterPhase {
    Capturing,
    Finishing,
    Finished,
    Interrupted,
    Failed,
}

#[derive(Clone, Debug)]
pub struct WriterStatus {
    pub phase: WriterPhase,
    pub written: RecordingSummary,
    pub committed: RecordingSummary,
    pub error: Option<String>,
}

struct SharedState {
    status: WriterStatus,
    finish_offset: Option<u64>,
}

struct PendingRecord {
    kind: u8,
    payload: Vec<u8>,
    _lease: BudgetLease,
}

#[derive(Clone, PartialEq, Message)]
struct PendingVisual {
    #[prost(uint64, tag = "1")]
    sequence: u64,
    #[prost(uint64, tag = "2")]
    offset_micros: u64,
    #[prost(uint64, optional, tag = "3")]
    base_sequence: Option<u64>,
    #[prost(message, optional, tag = "4")]
    frame: Option<TerminalFrameDiff>,
    #[prost(message, repeated, tag = "5")]
    assets: Vec<PendingAsset>,
}
#[derive(Clone, PartialEq, Message)]
struct PendingAsset {
    #[prost(uint64, tag = "1")]
    asset_id: u64,
    #[prost(uint64, tag = "2")]
    asset_version: u64,
    #[prost(uint32, tag = "3")]
    width: u32,
    #[prost(uint32, tag = "4")]
    height: u32,
    #[prost(bytes = "vec", tag = "5")]
    rgba: Vec<u8>,
}

/// Nonblocking producer handle. Admission failure stops this capture visibly;
/// all already admitted records drain to an interrupted prefix. No semantic
/// record is discarded merely to reduce the visual sampling rate.
pub struct BackgroundWriter {
    sender: Option<mpsc::SyncSender<PendingRecord>>,
    state: Arc<Mutex<SharedState>>,
    budget: Arc<QueueBudget>,
}

impl BackgroundWriter {
    pub fn start(path: &Path, metadata: &RecordingMetadata) -> StorageResult<Self> {
        Self::with_budget(path, metadata, SHARED_BUDGET.clone())
    }

    pub fn with_budget(
        path: &Path,
        metadata: &RecordingMetadata,
        budget: Arc<QueueBudget>,
    ) -> StorageResult<Self> {
        budget
            .writers
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |count| {
                (count < MAX_ACTIVE_WRITERS).then_some(count + 1)
            })
            .map_err(|_| StorageError::QueueExhausted)?;
        let writer_lease = WriterLease(budget.clone());
        let writer = ContainerWriter::create(path, metadata)?;
        let (sender, receiver) = mpsc::sync_channel(MAX_PENDING_RECORDS);
        let state = Arc::new(Mutex::new(SharedState {
            status: WriterStatus {
                phase: WriterPhase::Capturing,
                written: RecordingSummary::default(),
                committed: RecordingSummary::default(),
                error: None,
            },
            finish_offset: None,
        }));
        let worker_state = state.clone();
        thread::Builder::new()
            .name("trail-recording-writer".to_owned())
            .spawn(move || {
                let _writer_lease = writer_lease;
                let result = run_worker(writer, receiver, &worker_state);
                if let Err(error) = result {
                    let mut shared = worker_state.lock();
                    shared.status.phase = WriterPhase::Failed;
                    shared.status.error = Some(error.to_string());
                }
            })?;
        Ok(Self {
            sender: Some(sender),
            state,
            budget,
        })
    }

    pub fn status(&self) -> WriterStatus {
        self.state.lock().status.clone()
    }
    pub fn pressure_percent(&self) -> u8 {
        self.budget.pressure_percent()
    }

    pub fn enqueue_visual(
        &mut self,
        sample: VisualSample,
        assets: Vec<RecordedAsset>,
    ) -> StorageResult<()> {
        let result = super::storage::validate_asset_inputs(&sample.frame, &assets);
        if let Err(error) = result {
            return self.fail(error);
        }
        let pending = PendingVisual {
            sequence: sample.sequence,
            offset_micros: sample.offset_micros,
            base_sequence: sample.base_sequence,
            frame: Some(sample.frame),
            assets: assets
                .into_iter()
                .map(|a| PendingAsset {
                    asset_id: a.asset_id,
                    asset_version: a.asset_version,
                    width: a.width,
                    height: a.height,
                    rgba: a.rgba,
                })
                .collect(),
        };
        let size = pending.encoded_len();
        let lease = match self.budget.reserve(size) {
            Ok(lease) => lease,
            Err(error) => return self.fail(error),
        };
        self.admit(PendingRecord {
            kind: 1,
            payload: pending.encode_to_vec(),
            _lease: lease,
        })
    }

    pub fn enqueue_semantic(&mut self, event: &SemanticEvent) -> StorageResult<()> {
        if let Err(error) = event.validate() {
            return self.fail(error.into());
        }
        let payload = serde_json::to_vec(event)?;
        let lease = match self.budget.reserve(payload.capacity()) {
            Ok(lease) => lease,
            Err(error) => return self.fail(error),
        };
        self.admit(PendingRecord {
            kind: 2,
            payload,
            _lease: lease,
        })
    }

    pub fn interrupt(&mut self, message: String) {
        let mut shared = self.state.lock();
        if matches!(
            shared.status.phase,
            WriterPhase::Finished | WriterPhase::Interrupted
        ) {
            return;
        }
        shared.status.phase = WriterPhase::Failed;
        if shared.status.error.is_none() {
            shared.status.error = Some(message);
        }
        shared.finish_offset = None;
        self.sender.take();
    }

    pub fn request_finish(&mut self, offset_micros: u64) -> StorageResult<()> {
        let mut shared = self.state.lock();
        if shared.status.phase != WriterPhase::Capturing || self.sender.is_none() {
            return Err(StorageError::WriterFailed);
        }
        shared.finish_offset = Some(offset_micros);
        shared.status.phase = WriterPhase::Finishing;
        self.sender.take();
        Ok(())
    }

    fn admit(&mut self, record: PendingRecord) -> StorageResult<()> {
        if self.state.lock().status.phase != WriterPhase::Capturing {
            return Err(StorageError::WriterFailed);
        }
        let Some(sender) = &self.sender else {
            return Err(StorageError::WriterFailed);
        };
        match sender.try_send(record) {
            Ok(()) => Ok(()),
            Err(mpsc::TrySendError::Full(_)) => self.fail(StorageError::QueueExhausted),
            Err(mpsc::TrySendError::Disconnected(_)) => self.fail(StorageError::WriterFailed),
        }
    }

    fn fail<T>(&mut self, error: StorageError) -> StorageResult<T> {
        let mut shared = self.state.lock();
        shared.status.phase = WriterPhase::Failed;
        if shared.status.error.is_none() {
            shared.status.error = Some(error.to_string());
        }
        shared.finish_offset = None;
        self.sender.take();
        Err(error)
    }
}

fn run_worker(
    mut writer: ContainerWriter,
    receiver: mpsc::Receiver<PendingRecord>,
    state: &Mutex<SharedState>,
) -> StorageResult<()> {
    let mut deadline = Instant::now() + COMMIT_INTERVAL;
    loop {
        match receiver.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
            Ok(record) => {
                match record.kind {
                    1 => {
                        let pending = PendingVisual::decode(record.payload.as_slice())?;
                        let sample = VisualSample {
                            sequence: pending.sequence,
                            offset_micros: pending.offset_micros,
                            base_sequence: pending.base_sequence,
                            frame: pending
                                .frame
                                .ok_or(StorageError::Invalid("missing queued frame"))?,
                        };
                        let assets = pending
                            .assets
                            .into_iter()
                            .map(|a| RecordedAsset {
                                asset_id: a.asset_id,
                                asset_version: a.asset_version,
                                width: a.width,
                                height: a.height,
                                rgba: a.rgba,
                            })
                            .collect::<Vec<_>>();
                        writer.append_visual(sample, &assets)?;
                    }
                    2 => writer.append_semantic(&serde_json::from_slice(&record.payload)?)?,
                    _ => unreachable!(),
                }
                state.lock().status.written = writer.summary().clone();
                // The lease remains held through decoding and the disk write.
                drop(record);
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
        if Instant::now() >= deadline {
            writer.commit()?;
            state.lock().status.committed = writer.summary().clone();
            deadline = Instant::now() + COMMIT_INTERVAL;
        }
    }
    let finish = state.lock().finish_offset;
    if let Some(offset) = finish {
        let summary = writer.finish(offset)?;
        let mut shared = state.lock();
        shared.status.written = summary.clone();
        shared.status.committed = summary;
        shared.status.phase = WriterPhase::Finished;
    } else {
        writer.commit()?;
        let mut shared = state.lock();
        shared.status.committed = writer.summary().clone();
        if shared.status.phase != WriterPhase::Failed {
            shared.status.phase = WriterPhase::Interrupted;
        }
    }
    Ok(())
}
