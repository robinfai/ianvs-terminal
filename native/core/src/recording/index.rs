use super::assets::AssetBinding;
use super::storage::{
    ContainerReader, RecordingCompletion, RecordingMetadata, ScanReport, StorageError,
    StorageResult, StoredRecord, open_regular_file,
};
use crate::proto::frame_diff::TerminalFrameDiff;
use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

const MAGIC: &[u8; 8] = b"TRLIDX02";
const HEADER_BYTES: u64 = 104;
const ENTRY_BYTES: u64 = 64;

#[derive(Clone, Copy)]
struct KeyframeEntry {
    offset_micros: u64,
    file_offset: u64,
    ordinal: u64,
    visual_sequence: u64,
}

/// An on-disk binary-search table. No recording-sized array is loaded by open
/// or seek. This is a disposable cache; the checksummed container is authoritative.
pub struct RecordingIndex {
    root: PathBuf,
    file: File,
    source_bytes: u64,
    verified_bytes: u64,
    entries: u64,
}

#[derive(Debug)]
pub struct SeekScreen {
    pub offset_micros: u64,
    pub sequence: u64,
    pub frame: TerminalFrameDiff,
    pub assets: Vec<AssetBinding>,
}

impl RecordingIndex {
    /// Stream recovery/reindexing to a temporary file and publish atomically.
    /// Cancellation, source growth or scan I/O errors leave the prior cache intact.
    pub fn rebuild(path: &Path, mut cancelled: impl FnMut() -> bool) -> StorageResult<ScanReport> {
        let reader = ContainerReader::open(path)?;
        let fingerprint = metadata_fingerprint(&reader.metadata)?;
        let source_bytes = fs::metadata(path.join("records.bin"))?.len();
        let mut temporary = tempfile::NamedTempFile::new_in(path)?;
        temporary.write_all(&[0; HEADER_BYTES as usize])?;
        let mut entries = 0u64;
        let report = reader.scan(&mut cancelled, |record| {
            if let StoredRecord::Visual { sample, .. } = &record.record
                && sample.base_sequence.is_none()
            {
                let entry = KeyframeEntry {
                    offset_micros: sample.offset_micros,
                    file_offset: record.file_offset,
                    ordinal: record.ordinal,
                    visual_sequence: sample.sequence,
                };
                temporary.write_all(&encode_entry(entry))?;
                entries += 1;
            }
            Ok(())
        })?;
        if cancelled() {
            return Err(StorageError::Cancelled);
        }
        if fs::metadata(path.join("records.bin"))?.len() != source_bytes {
            return Err(StorageError::Invalid(
                "recording changed during index build",
            ));
        }
        let mut header = [0u8; HEADER_BYTES as usize];
        header[..8].copy_from_slice(MAGIC);
        header[8..16].copy_from_slice(&source_bytes.to_le_bytes());
        header[16..24].copy_from_slice(&report.verified_bytes.to_le_bytes());
        header[24..32].copy_from_slice(&entries.to_le_bytes());
        header[32..64].copy_from_slice(&fingerprint);
        header[64] = u8::from(report.completion == RecordingCompletion::Finished);
        let checksum = Sha256::digest(&header[..72]);
        header[72..].copy_from_slice(&checksum);
        temporary.seek(SeekFrom::Start(0))?;
        temporary.write_all(&header)?;
        temporary.as_file().sync_all()?;
        temporary
            .persist(path.join("seek.index"))
            .map_err(|error| error.error)?;
        super::assets::sync_directory(path)?;
        Ok(report)
    }

    pub fn open(path: &Path) -> StorageResult<Self> {
        let reader = ContainerReader::open(path)?;
        let source_bytes = fs::metadata(path.join("records.bin"))?.len();
        let mut file = open_regular_file(&path.join("seek.index"))?;
        let mut header = [0u8; HEADER_BYTES as usize];
        file.read_exact(&mut header)?;
        if &header[..8] != MAGIC
            || Sha256::digest(&header[..72]).as_slice() != &header[72..]
            || header[64] > 1
            || header[65..72] != [0; 7]
            || header[32..64] != metadata_fingerprint(&reader.metadata)?
        {
            return Err(StorageError::Invalid("invalid seek index header"));
        }
        let source_length = read_u64(&header[8..16]);
        let verified_bytes = read_u64(&header[16..24]);
        let entries = read_u64(&header[24..32]);
        if source_length != source_bytes
            || verified_bytes > source_bytes
            || entries
                .checked_mul(ENTRY_BYTES)
                .and_then(|bytes| bytes.checked_add(HEADER_BYTES))
                != Some(file.metadata()?.len())
        {
            return Err(StorageError::Invalid("stale or invalid seek index"));
        }
        Ok(Self {
            root: path.to_owned(),
            file,
            source_bytes,
            verified_bytes,
            entries,
        })
    }

    /// Binary-search a keyframe, then stream only its dependent records. The
    /// sampler bounds each group to 128 visuals, even during hook bursts.
    pub fn seek(
        &mut self,
        offset_micros: u64,
        mut cancelled: impl FnMut() -> bool,
    ) -> StorageResult<Option<SeekScreen>> {
        if cancelled() {
            return Err(StorageError::Cancelled);
        }
        if fs::metadata(self.root.join("records.bin"))?.len() != self.source_bytes {
            return Err(StorageError::Invalid(
                "recording changed after opening index",
            ));
        }
        let (mut low, mut high) = (0, self.entries);
        while low < high {
            if cancelled() {
                return Err(StorageError::Cancelled);
            }
            let middle = low + (high - low) / 2;
            if self.entry(middle)?.offset_micros <= offset_micros {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        if low == 0 {
            return Ok(None);
        }
        let keyframe = self.entry(low - 1)?;
        let mut reader = ContainerReader::open(&self.root)?;
        reader.position_at_keyframe(
            keyframe.file_offset,
            keyframe.ordinal,
            keyframe.visual_sequence,
        )?;
        let mut result = None;
        loop {
            if cancelled() {
                return Err(StorageError::Cancelled);
            }
            let record = reader
                .next_record()?
                .ok_or(StorageError::Invalid("missing indexed keyframe"))?;
            if result.is_none()
                && (record.file_offset != keyframe.file_offset
                    || record.ordinal != keyframe.ordinal
                    || record.offset_micros != keyframe.offset_micros)
            {
                return Err(StorageError::Invalid(
                    "keyframe index does not match container",
                ));
            }
            if record.end_offset > self.verified_bytes {
                return Err(StorageError::Invalid("index points beyond verified prefix"));
            }
            if record.offset_micros > offset_micros {
                break;
            }
            match record.record {
                StoredRecord::Visual { sample, assets } => {
                    if result.is_none()
                        && (sample.base_sequence.is_some()
                            || sample.sequence != keyframe.visual_sequence)
                    {
                        return Err(StorageError::Invalid("index does not point to keyframe"));
                    }
                    result = Some(SeekScreen {
                        offset_micros: sample.offset_micros,
                        sequence: sample.sequence,
                        frame: reader
                            .screen()
                            .ok_or(StorageError::Invalid("seek has no screen"))?
                            .clone(),
                        assets,
                    });
                }
                StoredRecord::Finished(_) => break,
                StoredRecord::Semantic(_) if result.is_none() => {
                    return Err(StorageError::Invalid("index points to semantic event"));
                }
                StoredRecord::Semantic(_) => {}
            }
            if record.end_offset == self.verified_bytes {
                break;
            }
        }
        Ok(result)
    }

    fn entry(&mut self, index: u64) -> StorageResult<KeyframeEntry> {
        if index >= self.entries {
            return Err(StorageError::Invalid("index entry out of range"));
        }
        self.file
            .seek(SeekFrom::Start(HEADER_BYTES + index * ENTRY_BYTES))?;
        let mut bytes = [0u8; ENTRY_BYTES as usize];
        self.file.read_exact(&mut bytes)?;
        if Sha256::digest(&bytes[..32]).as_slice() != &bytes[32..] {
            return Err(StorageError::Invalid("keyframe index checksum mismatch"));
        }
        let entry = KeyframeEntry {
            offset_micros: read_u64(&bytes[..8]),
            file_offset: read_u64(&bytes[8..16]),
            ordinal: read_u64(&bytes[16..24]),
            visual_sequence: read_u64(&bytes[24..32]),
        };
        if entry.file_offset >= self.verified_bytes || entry.visual_sequence > entry.ordinal {
            return Err(StorageError::Invalid("invalid keyframe index entry"));
        }
        Ok(entry)
    }
}

fn read_u64(bytes: &[u8]) -> u64 {
    u64::from_le_bytes(bytes.try_into().unwrap())
}
fn metadata_fingerprint(metadata: &RecordingMetadata) -> StorageResult<[u8; 32]> {
    Ok(Sha256::digest(serde_json::to_vec(metadata)?).into())
}
fn encode_entry(entry: KeyframeEntry) -> [u8; ENTRY_BYTES as usize] {
    let mut bytes = [0u8; ENTRY_BYTES as usize];
    bytes[..8].copy_from_slice(&entry.offset_micros.to_le_bytes());
    bytes[8..16].copy_from_slice(&entry.file_offset.to_le_bytes());
    bytes[16..24].copy_from_slice(&entry.ordinal.to_le_bytes());
    bytes[24..32].copy_from_slice(&entry.visual_sequence.to_le_bytes());
    let checksum = Sha256::digest(&bytes[..32]);
    bytes[32..].copy_from_slice(&checksum);
    bytes
}
