//! Bounded, checksummed streaming container. A bundle contains records.bin and
//! immutable assets/ blobs. Readers never rewrite damaged/legacy files. The
//! application owns library admission, active-file protection and publication.

use super::assets::{self, AssetBinding, MAX_FRAME_ASSETS, RecordedAsset};
use super::{RecordingError, ScreenReplay, SemanticEvent, VisualSample};
use crate::proto::frame_diff::TerminalFrameDiff;
use prost::Message;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, Write};
use std::path::{Path, PathBuf};

pub const RECORDING_BUNDLE_EXTENSION: &str = "trailrec";
pub const MAX_RECORD_BYTES: usize = 17 * 1024 * 1024;
const FILE_MAGIC: &[u8; 8] = b"TRLREC02";
const RECORD_MAGIC: &[u8; 4] = b"TRC2";
const HEADER_BYTES: usize = 60;
const MAX_METADATA_BYTES: usize = 64 * 1024;

pub type StorageResult<T> = Result<T, StorageError>;

#[derive(Debug, thiserror::Error)]
pub enum StorageError {
    #[error("recording runtime: {0}")]
    Runtime(String),
    #[error("recording I/O: {0}")]
    Io(#[from] std::io::Error),
    #[error("unsupported recording format; file was left unchanged")]
    UnsupportedFormat,
    #[error("invalid recording: {0}")]
    Invalid(&'static str),
    #[error("recording JSON: {0}")]
    Json(#[from] serde_json::Error),
    #[error("recording protobuf: {0}")]
    Protobuf(#[from] prost::DecodeError),
    #[error(transparent)]
    Model(#[from] RecordingError),
    #[error("recording writer has stopped after an error")]
    WriterFailed,
    #[error("recording queue capacity exhausted")]
    QueueExhausted,
    #[error("recording operation cancelled")]
    Cancelled,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RecordingMetadata {
    pub recording_id: String,
    pub started_at_unix_millis: u64,
    pub title: String,
    pub hostname: Option<String>,
}

impl RecordingMetadata {
    pub(crate) fn validate(&self) -> StorageResult<()> {
        if self.recording_id.is_empty()
            || self.recording_id.len() > 128
            || [&self.recording_id, &self.title]
                .into_iter()
                .chain(self.hostname.as_ref())
                .any(|value| value.len() > 8192 || value.contains('\0'))
        {
            return Err(StorageError::Invalid("invalid recording metadata"));
        }
        Ok(())
    }
}

#[derive(Clone, PartialEq, Message)]
struct StoredVisual {
    #[prost(uint64, tag = "1")]
    sequence: u64,
    #[prost(uint64, optional, tag = "2")]
    base_sequence: Option<u64>,
    #[prost(message, optional, tag = "3")]
    frame: Option<TerminalFrameDiff>,
    #[prost(message, repeated, tag = "4")]
    assets: Vec<AssetBinding>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum StoredRecord {
    Visual {
        sample: Box<VisualSample>,
        assets: Vec<AssetBinding>,
    },
    Semantic(SemanticEvent),
    Finished(RecordingSummary),
}

#[derive(Clone, Debug, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RecordingSummary {
    pub record_count: u64,
    pub visual_count: u64,
    pub semantic_count: u64,
    pub duration_micros: u64,
}

#[derive(Debug)]
pub struct LocatedRecord {
    pub file_offset: u64,
    pub end_offset: u64,
    pub ordinal: u64,
    pub offset_micros: u64,
    pub record: StoredRecord,
}

#[derive(Debug, PartialEq, Eq)]
pub enum RecordingCompletion {
    Finished,
    Interrupted,
    DamagedTail(String),
}

#[derive(Debug)]
pub struct ScanReport {
    pub summary: RecordingSummary,
    pub completion: RecordingCompletion,
    pub verified_bytes: u64,
}

pub struct ContainerWriter {
    root: PathBuf,
    file: File,
    summary: RecordingSummary,
    replay: ScreenReplay,
    failed: bool,
}

impl ContainerWriter {
    /// Creates a new bundle only. Existing files, bundles and legacy NDJSON are
    /// never replaced. Dropping without finish deliberately leaves no footer.
    pub fn create(path: &Path, metadata: &RecordingMetadata) -> StorageResult<Self> {
        metadata.validate()?;
        let json = serde_json::to_vec(metadata)?;
        if json.len() > MAX_METADATA_BYTES {
            return Err(StorageError::Invalid("metadata exceeds byte limit"));
        }
        let mut directory = fs::DirBuilder::new();
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            directory.mode(0o700);
        }
        directory.create(path)?;
        directory.create(path.join("assets"))?;
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(path.join("records.bin"))?;
        file.write_all(FILE_MAGIC)?;
        file.write_all(&(json.len() as u32).to_le_bytes())?;
        file.write_all(&Sha256::digest(&json))?;
        file.write_all(&json)?;
        file.sync_all()?;
        assets::sync_directory(path)?;
        assets::sync_directory(path.parent().unwrap_or(Path::new(".")))?;
        Ok(Self {
            root: path.to_owned(),
            file,
            summary: RecordingSummary::default(),
            replay: ScreenReplay::default(),
            failed: false,
        })
    }

    pub fn summary(&self) -> &RecordingSummary {
        &self.summary
    }

    pub fn append_visual(
        &mut self,
        sample: VisualSample,
        assets: &[RecordedAsset],
    ) -> StorageResult<()> {
        self.ensure_writable(sample.offset_micros)?;
        validate_asset_inputs(&sample.frame, assets)?;
        let bindings = assets
            .iter()
            .map(|asset| assets::store_asset(&self.root.join("assets"), asset))
            .collect::<StorageResult<Vec<_>>>();
        // Blob persistence failure is fatal, just as a container write failure is.
        let bindings = match bindings {
            Ok(bindings) => bindings,
            Err(error) => {
                self.failed = true;
                return Err(error);
            }
        };
        let stored = StoredVisual {
            sequence: sample.sequence,
            base_sequence: sample.base_sequence,
            frame: Some(sample.frame.clone()),
            assets: bindings,
        };
        if stored.encoded_len() > MAX_RECORD_BYTES {
            return Err(StorageError::Invalid("visual record exceeds byte limit"));
        }
        let offset = sample.offset_micros;
        self.replay.apply(sample)?;
        self.write_record(1, offset, &stored.encode_to_vec())?;
        self.summary.visual_count += 1;
        Ok(())
    }

    pub fn append_semantic(&mut self, event: &SemanticEvent) -> StorageResult<()> {
        self.ensure_writable(event.offset_micros)?;
        event.validate()?;
        self.write_record(2, event.offset_micros, &serde_json::to_vec(event)?)?;
        self.summary.semantic_count += 1;
        Ok(())
    }

    /// A background owner must call this on a wall-clock deadline, including
    /// when there are no new frames. Returning means sync_all succeeded.
    pub fn commit(&mut self) -> StorageResult<()> {
        self.ensure_writable(self.summary.duration_micros)?;
        if let Err(error) = self.file.sync_all() {
            self.failed = true;
            return Err(error.into());
        }
        Ok(())
    }

    pub fn finish(mut self, offset_micros: u64) -> StorageResult<RecordingSummary> {
        self.ensure_writable(offset_micros)?;
        let mut summary = self.summary.clone();
        summary.duration_micros = offset_micros;
        self.write_record(3, offset_micros, &serde_json::to_vec(&summary)?)?;
        self.commit()?;
        Ok(summary)
    }

    fn ensure_writable(&self, offset: u64) -> StorageResult<()> {
        if self.failed {
            return Err(StorageError::WriterFailed);
        }
        if offset < self.summary.duration_micros {
            return Err(RecordingError::NonMonotonicTime.into());
        }
        if self.summary.record_count == u64::MAX {
            return Err(RecordingError::SequenceExhausted.into());
        }
        Ok(())
    }

    fn write_record(&mut self, kind: u8, offset: u64, payload: &[u8]) -> StorageResult<()> {
        if payload.len() > MAX_RECORD_BYTES {
            return Err(StorageError::Invalid("record exceeds byte limit"));
        }
        let mut header = [0u8; HEADER_BYTES];
        header[..4].copy_from_slice(RECORD_MAGIC);
        header[4] = kind;
        header[8..12].copy_from_slice(&(payload.len() as u32).to_le_bytes());
        header[12..20].copy_from_slice(&self.summary.record_count.to_le_bytes());
        header[20..28].copy_from_slice(&offset.to_le_bytes());
        let mut checksum = Sha256::new();
        checksum.update(&header[..28]);
        checksum.update(payload);
        header[28..].copy_from_slice(&checksum.finalize());
        if let Err(error) = self
            .file
            .write_all(&header)
            .and_then(|_| self.file.write_all(payload))
        {
            self.failed = true;
            return Err(error.into());
        }
        self.summary.record_count += 1;
        self.summary.duration_micros = offset;
        Ok(())
    }
}

pub struct ContainerReader {
    root: PathBuf,
    file: File,
    pub metadata: RecordingMetadata,
    summary: RecordingSummary,
    replay: ScreenReplay,
    verified_bytes: u64,
    finished: bool,
    seeking_keyframe: bool,
    failed: bool,
}

impl ContainerReader {
    pub fn open(path: &Path) -> StorageResult<Self> {
        if !fs::symlink_metadata(path)?.file_type().is_dir() {
            return Err(StorageError::UnsupportedFormat);
        }
        let mut file = open_regular_file(&path.join("records.bin"))?;
        let mut header = [0u8; 44];
        file.read_exact(&mut header)?;
        if &header[..8] != FILE_MAGIC {
            return Err(StorageError::UnsupportedFormat);
        }
        let length = u32::from_le_bytes(header[8..12].try_into().unwrap()) as usize;
        if length > MAX_METADATA_BYTES {
            return Err(StorageError::Invalid("metadata exceeds byte limit"));
        }
        let mut json = vec![0; length];
        file.read_exact(&mut json)?;
        if Sha256::digest(&json).as_slice() != &header[12..] {
            return Err(StorageError::Invalid("metadata checksum mismatch"));
        }
        let metadata: RecordingMetadata = serde_json::from_slice(&json)?;
        metadata.validate()?;
        Ok(Self {
            root: path.to_owned(),
            file,
            metadata,
            summary: RecordingSummary::default(),
            replay: ScreenReplay::default(),
            verified_bytes: (44 + length) as u64,
            finished: false,
            seeking_keyframe: false,
            failed: false,
        })
    }

    pub(super) fn position_at_keyframe(
        &mut self,
        position: u64,
        ordinal: u64,
        visual_sequence: u64,
    ) -> StorageResult<()> {
        use std::io::SeekFrom;
        if position < self.verified_bytes || visual_sequence > ordinal {
            return Err(StorageError::Invalid("invalid keyframe index"));
        }
        self.file.seek(SeekFrom::Start(position))?;
        self.summary = RecordingSummary {
            record_count: ordinal,
            visual_count: visual_sequence,
            semantic_count: ordinal - visual_sequence,
            duration_micros: 0,
        };
        self.replay = ScreenReplay::default();
        self.seeking_keyframe = true;
        self.finished = false;
        self.failed = false;
        Ok(())
    }

    pub fn screen(&self) -> Option<&TerminalFrameDiff> {
        self.replay.screen()
    }

    pub fn load_asset(&self, binding: &AssetBinding) -> StorageResult<RecordedAsset> {
        assets::load_asset(&self.root.join("assets"), binding)
    }

    /// At most one bounded record plus one materialized screen is retained.
    /// A malformed tail fails once; callers cannot continue past corruption.
    pub fn next_record(&mut self) -> StorageResult<Option<LocatedRecord>> {
        if self.failed {
            return Err(StorageError::Invalid("reader stopped at damaged tail"));
        }
        let result = self.read_next();
        if result.is_err() {
            self.failed = true;
        }
        result
    }

    fn read_next(&mut self) -> StorageResult<Option<LocatedRecord>> {
        let position = self.file.stream_position()?;
        let mut header = [0u8; HEADER_BYTES];
        let first = self.file.read(&mut header[..1])?;
        if first == 0 {
            return Ok(None);
        }
        if self.finished {
            return Err(StorageError::Invalid("bytes after completed footer"));
        }
        self.file.read_exact(&mut header[1..])?;
        let length = u32::from_le_bytes(header[8..12].try_into().unwrap()) as usize;
        let ordinal = u64::from_le_bytes(header[12..20].try_into().unwrap());
        let offset = u64::from_le_bytes(header[20..28].try_into().unwrap());
        if &header[..4] != RECORD_MAGIC
            || header[5..8] != [0; 3]
            || !(1..=3).contains(&header[4])
            || length > MAX_RECORD_BYTES
            || ordinal != self.summary.record_count
            || offset < self.summary.duration_micros
        {
            return Err(StorageError::Invalid("invalid record header"));
        }
        // Reject impossible lengths before allocating the payload.
        let remaining = self
            .file
            .metadata()?
            .len()
            .saturating_sub(position + HEADER_BYTES as u64);
        if length as u64 > remaining {
            return Err(StorageError::Invalid("truncated record payload"));
        }
        let mut payload = vec![0; length];
        self.file.read_exact(&mut payload)?;
        let mut checksum = Sha256::new();
        checksum.update(&header[..28]);
        checksum.update(&payload);
        if checksum.finalize().as_slice() != &header[28..] {
            return Err(StorageError::Invalid("record checksum mismatch"));
        }
        let record = match header[4] {
            1 => {
                let stored = StoredVisual::decode(payload.as_slice())?;
                let frame = stored
                    .frame
                    .ok_or(StorageError::Invalid("missing visual frame"))?;
                validate_bindings(&frame, &stored.assets)?;
                let sample = VisualSample {
                    sequence: stored.sequence,
                    offset_micros: offset,
                    base_sequence: stored.base_sequence,
                    frame,
                };
                if self.seeking_keyframe {
                    self.replay.seek_keyframe(sample.clone())?;
                    self.seeking_keyframe = false;
                } else {
                    self.replay.apply(sample.clone())?;
                }
                self.summary.visual_count += 1;
                StoredRecord::Visual {
                    sample: Box::new(sample),
                    assets: stored.assets,
                }
            }
            2 => {
                let event: SemanticEvent = serde_json::from_slice(&payload)?;
                event.validate()?;
                if event.offset_micros != offset {
                    return Err(StorageError::Invalid("semantic timestamp mismatch"));
                }
                self.summary.semantic_count += 1;
                StoredRecord::Semantic(event)
            }
            3 => {
                let summary: RecordingSummary = serde_json::from_slice(&payload)?;
                let mut expected = self.summary.clone();
                expected.duration_micros = offset;
                if summary != expected {
                    return Err(StorageError::Invalid("footer counts do not match records"));
                }
                self.finished = true;
                StoredRecord::Finished(summary)
            }
            _ => unreachable!(),
        };
        self.summary.record_count += 1;
        self.summary.duration_micros = offset;
        self.verified_bytes = self.file.stream_position()?;
        Ok(Some(LocatedRecord {
            file_offset: position,
            end_offset: self.verified_bytes,
            ordinal,
            offset_micros: offset,
            record,
        }))
    }

    /// Recovery is a read-only prefix scan. Cancellation never changes files.
    /// The callback can stream an index to disk instead of accumulating history.
    pub fn scan(
        mut self,
        mut cancelled: impl FnMut() -> bool,
        mut visit: impl FnMut(&LocatedRecord) -> StorageResult<()>,
    ) -> StorageResult<ScanReport> {
        let completion = loop {
            if cancelled() {
                return Err(StorageError::Cancelled);
            }
            match self.next_record() {
                Ok(Some(record)) => visit(&record)?,
                Ok(None) => {
                    break if self.finished {
                        RecordingCompletion::Finished
                    } else {
                        RecordingCompletion::Interrupted
                    };
                }
                Err(StorageError::Io(error))
                    if error.kind() != std::io::ErrorKind::UnexpectedEof =>
                {
                    return Err(error.into());
                }
                Err(error) => break RecordingCompletion::DamagedTail(error.to_string()),
            }
        };
        if self.finished {
            self.summary.record_count -= 1;
        }
        Ok(ScanReport {
            summary: self.summary,
            completion,
            verified_bytes: self.verified_bytes,
        })
    }
}

pub(super) fn validate_asset_inputs(
    frame: &TerminalFrameDiff,
    assets: &[RecordedAsset],
) -> StorageResult<()> {
    if assets.len() > MAX_FRAME_ASSETS {
        return Err(StorageError::Invalid("too many assets in sample"));
    }
    let mut bytes = 0usize;
    for asset in assets {
        let expected = assets::expected_bytes(asset.width, asset.height)?;
        if expected != asset.rgba.len() {
            return Err(StorageError::Invalid("invalid RGBA byte count"));
        }
        bytes += expected;
    }
    if bytes > assets::MAX_ASSET_BYTES {
        return Err(StorageError::Invalid("sample assets exceed byte budget"));
    }
    let keys = assets
        .iter()
        .map(|a| (a.asset_id, a.asset_version))
        .collect::<HashSet<_>>();
    if keys.len() != assets.len() || keys != required_asset_keys(frame)? {
        return Err(StorageError::Invalid(
            "sample assets do not match visible graphics",
        ));
    }
    Ok(())
}

fn validate_bindings(frame: &TerminalFrameDiff, bindings: &[AssetBinding]) -> StorageResult<()> {
    if bindings.len() > MAX_FRAME_ASSETS {
        return Err(StorageError::Invalid("too many asset bindings"));
    }
    let mut bytes = 0usize;
    for binding in bindings {
        binding.validate()?;
        bytes += assets::expected_bytes(binding.width, binding.height)?;
    }
    if bytes > assets::MAX_ASSET_BYTES {
        return Err(StorageError::Invalid("decoded assets exceed sample budget"));
    }
    let keys = bindings
        .iter()
        .map(|a| (a.asset_id, a.asset_version))
        .collect::<HashSet<_>>();
    if keys.len() != bindings.len() || keys != required_asset_keys(frame)? {
        return Err(StorageError::Invalid(
            "asset bindings do not match visible graphics",
        ));
    }
    Ok(())
}

fn required_asset_keys(frame: &TerminalFrameDiff) -> StorageResult<HashSet<(u64, u64)>> {
    if frame.graphics.len() > 4096 {
        return Err(StorageError::Invalid("too many graphic placements"));
    }
    frame
        .graphics
        .iter()
        .map(|placement| {
            let key = placement
                .asset_key
                .as_ref()
                .ok_or(StorageError::Invalid("missing graphic asset key"))?;
            Ok((key.asset_id, key.asset_version))
        })
        .collect()
}

pub(super) fn open_regular_file(path: &Path) -> StorageResult<File> {
    let mut options = OpenOptions::new();
    options.read(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK);
    }
    let file = options.open(path)?;
    if !file.metadata()?.is_file() {
        return Err(StorageError::Invalid("expected a regular file"));
    }
    Ok(file)
}
