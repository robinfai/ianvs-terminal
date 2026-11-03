//! Copy only validated primary recording bytes and referenced image blobs into
//! a newly owned staging bundle. The external source is never used for caches.
use super::assets::{self, AssetBinding};
use super::cache::FileStamp;
use super::storage::open_regular_file;
use super::{
    ContainerReader, RecordingMetadata, ScanReport, StorageError, StorageResult, StoredRecord,
};
use serde::Deserialize;
use std::collections::VecDeque;
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

const COPY_BUFFER_BYTES: usize = 256 * 1024;
const RECENT_ASSETS: usize = 256;
const MAX_COPY_BYTES: u64 = 9_007_199_254_740_991;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct CopyRequest {
    source_path: String,
    destination_path: String,
    maximum_bytes: u64,
}

pub(super) struct CopyReport {
    pub metadata: RecordingMetadata,
    pub scan: ScanReport,
    pub source_bytes: u64,
    pub copied_bytes: u64,
}

fn check(cancelled: &impl Fn() -> bool) -> StorageResult<()> {
    if cancelled() {
        Err(StorageError::Cancelled)
    } else {
        Ok(())
    }
}

fn bundle_path(value: &str) -> StorageResult<&Path> {
    let path = Path::new(value);
    if value.len() > 4096
        || value.contains('\0')
        || !path.is_absolute()
        || path.extension().and_then(|x| x.to_str()) != Some("trailrec")
    {
        return Err(StorageError::Invalid(
            "expected an absolute sampled recording bundle",
        ));
    }
    Ok(path)
}

fn create_directory(path: &Path) -> StorageResult<()> {
    let mut builder = fs::DirBuilder::new();
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        builder.mode(0o700);
    }
    builder.create(path)?;
    Ok(())
}

pub(super) fn copy_bundle(
    request: CopyRequest,
    cancelled: impl Fn() -> bool,
) -> StorageResult<CopyReport> {
    check(&cancelled)?;
    if request.maximum_bytes == 0 || request.maximum_bytes > MAX_COPY_BYTES {
        return Err(StorageError::Invalid("invalid import byte budget"));
    }
    let source = bundle_path(&request.source_path)?;
    let destination = bundle_path(&request.destination_path)?;
    let parent = destination
        .parent()
        .ok_or(StorageError::Invalid("missing import parent"))?;
    // The caller supplies an already-owned staging parent. Never create a copy
    // inside the external bundle, even through a symlinked parent component.
    if fs::canonicalize(parent)?.starts_with(fs::canonicalize(source)?) {
        return Err(StorageError::Invalid(
            "copy destination is inside the source bundle",
        ));
    }
    let source_stamp = FileStamp::read(&source.join("records.bin"))?;
    let metadata = ContainerReader::open(source)?.metadata;
    if metadata.recording_id.len() != 32
        || !metadata
            .recording_id
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err(StorageError::Invalid(
            "unsupported imported recording identity",
        ));
    }
    let source_bytes = open_regular_file(&source.join("records.bin"))?
        .metadata()?
        .len();
    if source_bytes > request.maximum_bytes {
        return Err(StorageError::Invalid(
            "import exceeds remaining storage budget",
        ));
    }
    check(&cancelled)?;
    // This create is the ownership boundary. A pre-existing destination, of any
    // type, is rejected before the cleanup path can run.
    create_directory(destination)?;
    let result = (|| {
        create_directory(&destination.join("assets"))?;
        copy_primary(source, destination, source_bytes, &cancelled)?;
        let copied = ContainerReader::open(destination)?;
        if copied.metadata != metadata
            || FileStamp::read(&source.join("records.bin"))? != source_stamp
        {
            return Err(StorageError::Invalid("source changed during import"));
        }
        let mut assets = AssetCopier {
            source: source.join("assets"),
            destination: destination.join("assets"),
            copied_bytes: source_bytes,
            maximum_bytes: request.maximum_bytes,
            recent: VecDeque::new(),
        };
        let scan = copied.scan(&cancelled, |record| {
            if let StoredRecord::Visual {
                assets: bindings, ..
            } = &record.record
            {
                for binding in bindings {
                    check(&cancelled)?;
                    assets.copy(binding)?;
                }
            }
            Ok(())
        })?;
        if FileStamp::read(&source.join("records.bin"))? != source_stamp {
            return Err(StorageError::Invalid("source changed during import"));
        }
        check(&cancelled)?;
        assets::sync_directory(&destination.join("assets"))?;
        assets::sync_directory(destination)?;
        assets::sync_directory(parent)?;
        check(&cancelled)?;
        Ok(CopyReport {
            metadata,
            scan,
            source_bytes,
            copied_bytes: assets.copied_bytes,
        })
    })();
    if result.is_err() {
        // Only our newly created directory is eligible. The application retains
        // its staging journal until this job actually settles, including when a
        // filesystem error prevents immediate cleanup here.
        if fs::remove_dir_all(destination).is_ok() {
            let _ = assets::sync_directory(parent);
        }
    }
    result
}

fn copy_primary(
    source: &Path,
    destination: &Path,
    bytes: u64,
    cancelled: &impl Fn() -> bool,
) -> StorageResult<()> {
    let mut input = open_regular_file(&source.join("records.bin"))?;
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut output = options.open(destination.join("records.bin"))?;
    let mut remaining = bytes;
    let mut buffer = vec![0; COPY_BUFFER_BYTES];
    while remaining > 0 {
        check(cancelled)?;
        let count = remaining.min(buffer.len() as u64) as usize;
        input.read_exact(&mut buffer[..count])?;
        output.write_all(&buffer[..count])?;
        remaining -= count as u64;
    }
    if input.read(&mut buffer[..1])? != 0 {
        return Err(StorageError::Invalid("source grew during import"));
    }
    check(cancelled)?;
    output.sync_all()?;
    Ok(())
}

struct AssetCopier {
    source: PathBuf,
    destination: PathBuf,
    copied_bytes: u64,
    maximum_bytes: u64,
    // Bound deduplication memory independently of recording duration. Older
    // blobs can be revalidated from the already copied destination when needed.
    recent: VecDeque<(Vec<u8>, u32, u32)>,
}

impl AssetCopier {
    fn copy(&mut self, binding: &AssetBinding) -> StorageResult<()> {
        binding.validate()?;
        let key = (binding.digest.clone(), binding.width, binding.height);
        if let Some(index) = self.recent.iter().position(|item| item == &key) {
            self.recent.remove(index);
        } else {
            let target = self.destination.join(binding.filename()?);
            match fs::symlink_metadata(target) {
                Ok(_) => {
                    assets::load_asset(&self.destination, binding)?;
                }
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                    if !fs::symlink_metadata(&self.source)?.is_dir() {
                        return Err(StorageError::Invalid("invalid source asset directory"));
                    }
                    let bytes = assets::expected_bytes(binding.width, binding.height)? as u64 + 16;
                    if bytes > self.maximum_bytes.saturating_sub(self.copied_bytes) {
                        return Err(StorageError::Invalid(
                            "import assets exceed remaining storage budget",
                        ));
                    }
                    let asset = assets::load_asset(&self.source, binding)?;
                    if assets::store_asset(&self.destination, &asset)? != *binding {
                        return Err(StorageError::Invalid("copied asset binding changed"));
                    }
                    self.copied_bytes += bytes;
                }
                Err(error) => return Err(error.into()),
            }
        }
        self.recent.push_back(key);
        if self.recent.len() > RECENT_ASSETS {
            self.recent.pop_front();
        }
        Ok(())
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct PublishRequest {
    staging_path: String,
    destination_path: String,
    recording_id: String,
}

pub(super) fn publish_bundle(request: PublishRequest) -> StorageResult<()> {
    let staging = bundle_path(&request.staging_path)?;
    let destination = bundle_path(&request.destination_path)?;
    let metadata = ContainerReader::open(staging)?.metadata;
    if metadata.recording_id != request.recording_id
        || request.recording_id.len() != 32
        || !request
            .recording_id
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        || destination.file_name().and_then(|name| name.to_str())
            != Some(&format!("{}.trailrec", request.recording_id))
    {
        return Err(StorageError::Invalid("staged recording identity changed"));
    }
    let parent = destination
        .parent()
        .ok_or(StorageError::Invalid("missing publication parent"))?;
    if fs::canonicalize(parent)?.starts_with(fs::canonicalize(staging)?) {
        return Err(StorageError::Invalid(
            "publication destination is inside staging",
        ));
    }
    rename_bundle_noreplace(staging, destination)
}

fn rename_bundle_noreplace(source: &Path, destination: &Path) -> StorageResult<()> {
    #[cfg(any(target_os = "macos", target_os = "linux"))]
    {
        use std::ffi::CString;
        use std::os::fd::AsRawFd;
        use std::os::unix::ffi::OsStrExt;
        use std::os::unix::fs::OpenOptionsExt;
        let open_parent = |path: &Path| -> StorageResult<std::fs::File> {
            Ok(OpenOptions::new()
                .read(true)
                .custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC)
                .open(
                    path.parent()
                        .ok_or(StorageError::Invalid("missing publication parent"))?,
                )?)
        };
        let name = |path: &Path| -> StorageResult<CString> {
            CString::new(
                path.file_name()
                    .ok_or(StorageError::Invalid("missing bundle name"))?
                    .as_bytes(),
            )
            .map_err(|_| StorageError::Invalid("invalid bundle name"))
        };
        let source_parent = open_parent(source)?;
        let destination_parent = open_parent(destination)?;
        let from = name(source)?;
        let to = name(destination)?;
        // The no-replace operation is atomic. Checking exists then calling
        // std::fs::rename would silently replace a destination created in between.
        #[cfg(target_os = "macos")]
        let result = unsafe {
            libc::renameatx_np(
                source_parent.as_raw_fd(),
                from.as_ptr(),
                destination_parent.as_raw_fd(),
                to.as_ptr(),
                libc::RENAME_EXCL,
            )
        };
        #[cfg(target_os = "linux")]
        let result = unsafe {
            libc::syscall(
                libc::SYS_renameat2,
                source_parent.as_raw_fd(),
                from.as_ptr(),
                destination_parent.as_raw_fd(),
                to.as_ptr(),
                libc::RENAME_NOREPLACE,
            )
        };
        if result != 0 {
            return Err(std::io::Error::last_os_error().into());
        }
        destination_parent.sync_all()?;
        source_parent.sync_all()?;
        Ok(())
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    {
        let _ = (source, destination);
        Err(StorageError::Invalid(
            "exclusive recording publication is unavailable on this platform",
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::recording::ContainerWriter;
    use std::cell::Cell;

    #[test]
    fn cancellation_during_primary_copy_removes_only_the_owned_partial_bundle() {
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("source.trailrec");
        let destination = root.path().join("copy.trailrec");
        ContainerWriter::create(
            &source,
            &RecordingMetadata {
                recording_id: "a".repeat(32),
                started_at_unix_millis: 1,
                title: "copy cancellation".into(),
                hostname: None,
            },
        )
        .unwrap()
        .finish(0)
        .unwrap();
        OpenOptions::new()
            .write(true)
            .open(source.join("records.bin"))
            .unwrap()
            .set_len(1024 * 1024)
            .unwrap();
        let original = fs::read(source.join("records.bin")).unwrap();
        let checkpoints = Cell::new(0);
        let result = copy_bundle(
            CopyRequest {
                source_path: source.to_str().unwrap().into(),
                destination_path: destination.to_str().unwrap().into(),
                maximum_bytes: 2 * 1024 * 1024,
            },
            || {
                let count = checkpoints.get() + 1;
                checkpoints.set(count);
                count == 4
            },
        );
        assert!(matches!(result, Err(StorageError::Cancelled)));
        assert_eq!(checkpoints.get(), 4);
        assert!(!destination.exists());
        assert_eq!(fs::read(source.join("records.bin")).unwrap(), original);
    }

    #[test]
    fn growth_after_admission_rejects_the_snapshot_and_removes_owned_staging() {
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("source.trailrec");
        let destination = root.path().join("copy.trailrec");
        ContainerWriter::create(
            &source,
            &RecordingMetadata {
                recording_id: "a".repeat(32),
                started_at_unix_millis: 1,
                title: "copy race".into(),
                hostname: None,
            },
        )
        .unwrap()
        .finish(0)
        .unwrap();
        let original = fs::read(source.join("records.bin")).unwrap();
        let checkpoints = Cell::new(0);
        let result = copy_bundle(
            CopyRequest {
                source_path: source.to_str().unwrap().into(),
                destination_path: destination.to_str().unwrap().into(),
                maximum_bytes: 1024 * 1024,
            },
            || {
                let count = checkpoints.get() + 1;
                checkpoints.set(count);
                if count == 3 {
                    OpenOptions::new()
                        .append(true)
                        .open(source.join("records.bin"))
                        .unwrap()
                        .write_all(b"growing source")
                        .unwrap();
                }
                false
            },
        );
        assert!(matches!(
            result,
            Err(StorageError::Invalid("source grew during import"))
        ));
        assert!(!destination.exists());
        let mut changed = original;
        changed.extend_from_slice(b"growing source");
        assert_eq!(fs::read(source.join("records.bin")).unwrap(), changed);
    }
}
