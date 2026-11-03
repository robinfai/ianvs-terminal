//! Disposable disk caches. Recording writes are authoritative; cache failures
//! disable publication and cause a bounded-memory recovery scan on next open.
use super::SemanticEvent;
use super::index::{KeyframeEntry, encode_entry, metadata_fingerprint, write_header};
use super::storage::{
    RecordingMetadata, ScanReport, StorageError, StorageResult, open_regular_file,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

pub(super) const TIMELINE_HEADER_BYTES: usize = 80;
pub(super) const TIMELINE_MAGIC: &[u8; 8] = b"TRLCMD02";
const SUMMARY_MAGIC: &[u8; 8] = b"TRLINFO2";
const MAX_SUMMARY_BYTES: usize = 64 * 1024;

/// Identity and change stamps are local cache validation, not a replacement for
/// record checksums. Copying a bundle to another filesystem rebuilds its caches.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct FileStamp {
    bytes: u64,
    modified_nanos: u128,
    #[cfg(unix)]
    device: u64,
    #[cfg(unix)]
    inode: u64,
    #[cfg(unix)]
    changed_seconds: i64,
    #[cfg(unix)]
    changed_nanos: i64,
}

impl FileStamp {
    pub(super) fn read(path: &Path) -> StorageResult<Self> {
        let metadata = open_regular_file(path)?.metadata()?;
        #[cfg(unix)]
        use std::os::unix::fs::MetadataExt;
        Ok(Self {
            bytes: metadata.len(),
            modified_nanos: metadata
                .modified()?
                .duration_since(UNIX_EPOCH)
                .map_err(|_| StorageError::Invalid("invalid file modification time"))?
                .as_nanos(),
            #[cfg(unix)]
            device: metadata.dev(),
            #[cfg(unix)]
            inode: metadata.ino(),
            #[cfg(unix)]
            changed_seconds: metadata.ctime(),
            #[cfg(unix)]
            changed_nanos: metadata.ctime_nsec(),
        })
    }
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct CachedReport {
    schema_version: u32,
    metadata: [u8; 32],
    source: FileStamp,
    seek: FileStamp,
    commands: FileStamp,
    report: ScanReport,
}

pub(super) fn load_report(path: &Path, metadata: &RecordingMetadata) -> StorageResult<ScanReport> {
    let mut file = open_regular_file(&path.join("summary.index"))?;
    let length = file.metadata()?.len();
    if !(44..=44 + MAX_SUMMARY_BYTES as u64).contains(&length) {
        return Err(StorageError::Invalid("invalid summary cache length"));
    }
    let mut header = [0; 44];
    file.read_exact(&mut header)?;
    if &header[..8] != SUMMARY_MAGIC
        || u32::from_le_bytes(header[8..12].try_into().unwrap()) as u64 != length - 44
    {
        return Err(StorageError::Invalid("invalid summary cache header"));
    }
    let mut payload = vec![0; (length - 44) as usize];
    file.read_exact(&mut payload)?;
    if Sha256::digest(&payload).as_slice() != &header[12..] {
        return Err(StorageError::Invalid("summary cache checksum mismatch"));
    }
    let cached: CachedReport = serde_json::from_slice(&payload)?;
    if cached.schema_version != 2
        || cached.metadata != metadata_fingerprint(metadata)?
        || cached.source != FileStamp::read(&path.join("records.bin"))?
        || cached.seek != FileStamp::read(&path.join("seek.index"))?
        || cached.commands != FileStamp::read(&path.join("commands.index"))?
        || cached.report.verified_bytes > cached.source.bytes
        || cached
            .report
            .summary
            .visual_count
            .checked_add(cached.report.summary.semantic_count)
            != Some(cached.report.summary.record_count)
    {
        return Err(StorageError::Invalid("stale or invalid summary cache"));
    }
    Ok(cached.report)
}

/// Publish last: an incomplete header update, replaced index or source change
/// invalidates the previous marker. No entire index is copied at commit time.
pub(super) fn publish_report(
    path: &Path,
    metadata: &RecordingMetadata,
    source: FileStamp,
    report: &ScanReport,
) -> StorageResult<()> {
    let cached = CachedReport {
        schema_version: 2,
        metadata: metadata_fingerprint(metadata)?,
        source,
        seek: FileStamp::read(&path.join("seek.index"))?,
        commands: FileStamp::read(&path.join("commands.index"))?,
        report: report.clone(),
    };
    if cached.source != FileStamp::read(&path.join("records.bin"))? {
        return Err(StorageError::Invalid(
            "recording changed during cache publication",
        ));
    }
    let bytes = serde_json::to_vec(&cached)?;
    if bytes.len() > MAX_SUMMARY_BYTES {
        return Err(StorageError::Invalid("summary cache exceeds byte limit"));
    }
    let mut temporary = tempfile::NamedTempFile::new_in(path)?;
    temporary.write_all(SUMMARY_MAGIC)?;
    temporary.write_all(&(bytes.len() as u32).to_le_bytes())?;
    temporary.write_all(&Sha256::digest(&bytes))?;
    temporary.write_all(&bytes)?;
    temporary.as_file().sync_all()?;
    temporary
        .persist(path.join("summary.index"))
        .map_err(|error| error.error)?;
    super::assets::sync_directory(path)?;
    Ok(())
}

pub(super) fn write_timeline_header(
    file: &mut impl Write,
    source_bytes: u64,
    fingerprint: &[u8; 32],
) -> StorageResult<()> {
    let mut header = [0; TIMELINE_HEADER_BYTES];
    header[..8].copy_from_slice(TIMELINE_MAGIC);
    header[8..16].copy_from_slice(&source_bytes.to_le_bytes());
    header[16..48].copy_from_slice(fingerprint);
    let checksum = Sha256::digest(&header[..48]);
    header[48..].copy_from_slice(&checksum);
    file.write_all(&header)?;
    Ok(())
}

pub(super) fn write_event(file: &mut impl Write, event: &SemanticEvent) -> StorageResult<()> {
    let bytes = serde_json::to_vec(event)?;
    file.write_all(&(bytes.len() as u32).to_le_bytes())?;
    file.write_all(&Sha256::digest(&bytes))?;
    file.write_all(&bytes)?;
    Ok(())
}

/// Appends a fixed-size keyframe entry or one bounded command at a time. Headers
/// and a small summary marker are updated only after primary data is synced.
pub(super) struct IncrementalIndexes {
    root: PathBuf,
    metadata: RecordingMetadata,
    seek: File,
    commands: File,
    entries: u64,
}

impl IncrementalIndexes {
    pub(super) fn create(root: &Path, metadata: &RecordingMetadata) -> StorageResult<Self> {
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut seek = options.open(root.join("seek.index"))?;
        let mut commands = options.open(root.join("commands.index"))?;
        seek.write_all(&[0; super::index::HEADER_BYTES as usize])?;
        commands.write_all(&[0; TIMELINE_HEADER_BYTES])?;
        Ok(Self {
            root: root.to_owned(),
            metadata: metadata.clone(),
            seek,
            commands,
            entries: 0,
        })
    }

    pub(super) fn visual(
        &mut self,
        offset_micros: u64,
        file_offset: u64,
        ordinal: u64,
        visual_sequence: u64,
    ) -> StorageResult<()> {
        self.seek.write_all(&encode_entry(KeyframeEntry {
            offset_micros,
            file_offset,
            ordinal,
            visual_sequence,
        }))?;
        self.entries += 1;
        Ok(())
    }

    pub(super) fn semantic(&mut self, event: &SemanticEvent) -> StorageResult<()> {
        write_event(&mut self.commands, event)
    }

    pub(super) fn publish(&mut self, report: &ScanReport) -> StorageResult<()> {
        let source = FileStamp::read(&self.root.join("records.bin"))?;
        let fingerprint = metadata_fingerprint(&self.metadata)?;
        self.seek.seek(SeekFrom::Start(0))?;
        write_header(
            &mut self.seek,
            source.bytes,
            report,
            self.entries,
            &fingerprint,
        )?;
        self.seek.seek(SeekFrom::End(0))?;
        self.commands.seek(SeekFrom::Start(0))?;
        write_timeline_header(&mut self.commands, source.bytes, &fingerprint)?;
        self.commands.seek(SeekFrom::End(0))?;
        self.seek.sync_all()?;
        self.commands.sync_all()?;
        publish_report(&self.root, &self.metadata, source, report)
    }
}
