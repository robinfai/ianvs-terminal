//! Sampled visual recording. This is separate from the live frame ABI and from
//! the legacy raw-output recording format. Integration is staged: the model
//! and sampler can be validated before the app switches its capture entrypoint.

mod assets;
mod background;
mod frame_state;
mod index;
mod replay;
mod sampler;
mod storage;
mod timeline;

pub use frame_state::ScreenState;
pub use replay::ScreenReplay;
pub use sampler::{
    AdaptiveSampler, SampleRecord, SamplingPolicy, SemanticEvent, SemanticKind, VisualSample,
};

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum RecordingError {
    #[error("unsupported or malformed structured frame: {0}")]
    InvalidFrame(&'static str),
    #[error("a complete screen is required before an incremental update")]
    MissingSnapshot,
    #[error("recording timestamps must be monotonic")]
    NonMonotonicTime,
    #[error("invalid sampling policy")]
    InvalidPolicy,
    #[error("invalid command timeline event")]
    InvalidSemanticEvent,
    #[error("recording sequence exhausted")]
    SequenceExhausted,
    #[error("stored frame sequence or base does not match")]
    InvalidSequence,
}

pub use assets::{AssetBinding, RecordedAsset};
pub use background::{BackgroundWriter, QueueBudget, WriterPhase, WriterStatus};
pub use storage::{
    ContainerReader, ContainerWriter, LocatedRecord, RECORDING_BUNDLE_EXTENSION,
    RecordingCompletion, RecordingMetadata, RecordingSummary, ScanReport, StorageError,
    StorageResult, StoredRecord,
};

pub use index::{RecordingIndex, SeekScreen};

pub use timeline::{HookTimeline, TimelineContext};
