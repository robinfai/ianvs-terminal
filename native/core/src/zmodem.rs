//! Session-owned ZMODEM transport interception and file transfer state.
//!
//! ZMODEM is a byte-stream protocol layered directly on the PTY transport. It
//! must run before the VT parser so file payload bytes never become terminal
//! rows, OSC input, scrollback, or recording data.

use parking_lot::Mutex as ParkingMutex;
use serde_json::Value;
use std::collections::{HashSet, VecDeque};
#[cfg(target_os = "macos")]
use std::ffi::CStr;
#[cfg(unix)]
use std::ffi::CString;
use std::fs;
use std::fs::{File, FileTimes, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
#[cfg(unix)]
use std::os::fd::{AsRawFd, FromRawFd};
#[cfg(target_os = "macos")]
use std::os::unix::ffi::OsStrExt;
#[cfg(unix)]
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock, mpsc};
use std::time::SystemTime;
use std::time::{Duration, Instant, UNIX_EPOCH};
use unicode_normalization::UnicodeNormalization;
use zmodem2::{Action, Event, FileInfo, Position, Receiver, Sender};

const HEX_HEADER_PREFIX: &[u8] = b"**\x18B";
const HEX_HEADER_ENCODED_BYTES: usize = 14;
const HEX_HEADER_BYTES: usize = HEX_HEADER_PREFIX.len() + HEX_HEADER_ENCODED_BYTES;
const MAX_INITIAL_HEADER_FLOW_BYTES: usize = 32;
const MAX_INITIAL_HEADER_CANDIDATE_BYTES: usize = HEX_HEADER_BYTES + MAX_INITIAL_HEADER_FLOW_BYTES;
const MAX_WIRE_BUFFER_BYTES: usize = 256 * 1024;
const MAX_FILES_PER_BATCH: usize = 256;
const MAX_FILE_BYTES: u64 = u32::MAX as u64;
const MAX_BATCH_BYTES: u64 = 16 * 1024 * 1024 * 1024;
const PROGRESS_INTERVAL: Duration = Duration::from_millis(250);
const SNAPSHOT_PROGRESS_CHUNK_BYTES: usize = 64 * 1024;
const SCANNER_HOLD_TIMEOUT: Duration = Duration::from_millis(100);
const AUTHORIZATION_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const TRANSFER_IDLE_TIMEOUT: Duration = Duration::from_secs(60);
const PROTOCOL_RETRY_INTERVAL: Duration = Duration::from_secs(10);
// Keep PTY uploads at one CRC-bounded subpacket per acknowledgement. GNU
// lrzsz 0.12.21rc advertises CANOVIO on a real OpenSSH PTY, but its buffered
// receive path can reject otherwise byte-identical multi-subpacket windows.
// A one-subpacket window retains CRC32 and interoperates with both PTY and
// pipe receivers while still sustaining local-SSH transfer rates.
const SEND_ACK_WINDOW_SUBPACKETS: usize = 1;
const DRAIN_QUIET_TIMEOUT: Duration = Duration::from_millis(250);
const DRAIN_HARD_TIMEOUT: Duration = Duration::from_secs(5);
const CANCEL_BYTES: &[u8] = b"\x18\x18\x18\x18\x18\x18\x18\x18";
const MAX_FILENAME_BYTES: usize = 240;
const TEMP_FILE_ATTEMPTS: usize = 128;
const MAX_RECOVERY_ENTRIES: usize = 64;
const RECOVERY_ENTRY_TTL: Duration = Duration::from_secs(60 * 60);
const RECOVERY_REVEAL_LEASE: Duration = Duration::from_secs(5 * 60);
const MAX_SNAPSHOT_WORKERS: usize = 4;
const MAX_SNAPSHOT_FILES_GLOBAL: usize = MAX_FILES_PER_BATCH;
const MAX_SNAPSHOT_BYTES_GLOBAL: u64 = MAX_BATCH_BYTES;
const MAX_SNAPSHOT_FDS_GLOBAL: usize = MAX_FILES_PER_BATCH * 2;
const MAX_RECEIVE_FILES_GLOBAL: usize = MAX_FILES_PER_BATCH;
const MAX_RECEIVE_BYTES_GLOBAL: u64 = MAX_BATCH_BYTES;
const MAX_RECEIVE_FDS_GLOBAL: usize = MAX_FILES_PER_BATCH * 4;
pub(crate) const RECEIVE_COMMIT_IDLE: u8 = 0;
pub(crate) const RECEIVE_COMMIT_PUBLISHING: u8 = 1;
pub(crate) const RECEIVE_COMMIT_CANCELLED: u8 = 2;
pub(crate) const RECEIVE_COMMIT_RESULT_READY: u8 = 3;

static ACTIVE_SNAPSHOT_WORKERS: AtomicUsize = AtomicUsize::new(0);
#[cfg(test)]
static TEST_SNAPSHOT_WORKER_ACTIVE: AtomicBool = AtomicBool::new(false);
static SNAPSHOT_REAPER: OnceLock<Option<mpsc::SyncSender<std::thread::JoinHandle<()>>>> =
    OnceLock::new();
static SNAPSHOT_RESOURCE_POOL: OnceLock<Arc<SnapshotResourcePool>> = OnceLock::new();
static STAGING_CLEANUP_WORKER: OnceLock<Option<mpsc::Sender<StagingCleanup>>> = OnceLock::new();
static RECEIVE_RESOURCE_POOL: OnceLock<Arc<ReceiveResourcePool>> = OnceLock::new();

#[derive(Clone, Copy, Debug)]
struct SnapshotResourceLimits {
    max_files: usize,
    max_bytes: u64,
    max_fds: usize,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct SnapshotResourceUsage {
    files: usize,
    bytes: u64,
    fds: usize,
}

struct SnapshotResourcePool {
    limits: SnapshotResourceLimits,
    usage: Mutex<SnapshotResourceUsage>,
}

impl SnapshotResourcePool {
    fn new(limits: SnapshotResourceLimits) -> Arc<Self> {
        Arc::new(Self {
            limits,
            usage: Mutex::new(SnapshotResourceUsage::default()),
        })
    }

    fn acquire(
        self: &Arc<Self>,
        files: usize,
        bytes: u64,
        fds: usize,
    ) -> Option<SnapshotResourceLease> {
        if files == 0
            || files > self.limits.max_files
            || bytes > self.limits.max_bytes
            || fds > self.limits.max_fds
        {
            return None;
        }
        let mut usage = self.usage.lock().ok()?;
        let next = SnapshotResourceUsage {
            files: usage.files.checked_add(files)?,
            bytes: usage.bytes.checked_add(bytes)?,
            fds: usage.fds.checked_add(fds)?,
        };
        if next.files > self.limits.max_files
            || next.bytes > self.limits.max_bytes
            || next.fds > self.limits.max_fds
        {
            return None;
        }
        *usage = next;
        drop(usage);
        Some(SnapshotResourceLease {
            _inner: Arc::new(SnapshotResourceLeaseInner {
                pool: Arc::clone(self),
                usage: SnapshotResourceUsage { files, bytes, fds },
            }),
        })
    }

    #[cfg(test)]
    fn usage(&self) -> SnapshotResourceUsage {
        *self.usage.lock().unwrap()
    }
}

struct SnapshotResourceLeaseInner {
    pool: Arc<SnapshotResourcePool>,
    usage: SnapshotResourceUsage,
}

impl Drop for SnapshotResourceLeaseInner {
    fn drop(&mut self) {
        if let Ok(mut usage) = self.pool.usage.lock() {
            usage.files = usage.files.saturating_sub(self.usage.files);
            usage.bytes = usage.bytes.saturating_sub(self.usage.bytes);
            usage.fds = usage.fds.saturating_sub(self.usage.fds);
        }
    }
}

#[derive(Clone)]
struct SnapshotResourceLease {
    _inner: Arc<SnapshotResourceLeaseInner>,
}

fn snapshot_resource_pool() -> &'static Arc<SnapshotResourcePool> {
    SNAPSHOT_RESOURCE_POOL.get_or_init(|| {
        SnapshotResourcePool::new(SnapshotResourceLimits {
            max_files: MAX_SNAPSHOT_FILES_GLOBAL,
            max_bytes: MAX_SNAPSHOT_BYTES_GLOBAL,
            max_fds: MAX_SNAPSHOT_FDS_GLOBAL,
        })
    })
}

#[derive(Debug)]
struct ReceiveResourcePool {
    limits: SnapshotResourceLimits,
    usage: Mutex<SnapshotResourceUsage>,
}

impl ReceiveResourcePool {
    fn new(limits: SnapshotResourceLimits) -> Arc<Self> {
        Arc::new(Self {
            limits,
            usage: Mutex::new(SnapshotResourceUsage::default()),
        })
    }

    fn acquire(
        self: &Arc<Self>,
        files: usize,
        bytes: u64,
        fds: usize,
    ) -> Option<ReceiveResourceLease> {
        let mut usage = self.usage.lock().ok()?;
        let next = SnapshotResourceUsage {
            files: usage.files.checked_add(files)?,
            bytes: usage.bytes.checked_add(bytes)?,
            fds: usage.fds.checked_add(fds)?,
        };
        if next.files > self.limits.max_files
            || next.bytes > self.limits.max_bytes
            || next.fds > self.limits.max_fds
        {
            return None;
        }
        *usage = next;
        Some(ReceiveResourceLease {
            pool: Arc::clone(self),
            usage: SnapshotResourceUsage { files, bytes, fds },
        })
    }

    #[cfg(test)]
    fn usage(&self) -> SnapshotResourceUsage {
        *self.usage.lock().unwrap()
    }
}

#[derive(Debug)]
struct ReceiveResourceLease {
    pool: Arc<ReceiveResourcePool>,
    usage: SnapshotResourceUsage,
}

impl ReceiveResourceLease {
    fn reserve_bytes(&mut self, bytes: u64) -> Result<(), ZmodemError> {
        if bytes == 0 {
            return Ok(());
        }
        let mut usage = self.pool.usage.lock().map_err(|_| ZmodemError::Io)?;
        let next_bytes = usage
            .bytes
            .checked_add(bytes)
            .filter(|next| *next <= self.pool.limits.max_bytes)
            .ok_or(ZmodemError::ResourceLimit)?;
        usage.bytes = next_bytes;
        self.usage.bytes = self
            .usage
            .bytes
            .checked_add(bytes)
            .ok_or(ZmodemError::ResourceLimit)?;
        Ok(())
    }
}

impl Drop for ReceiveResourceLease {
    fn drop(&mut self) {
        if let Ok(mut usage) = self.pool.usage.lock() {
            usage.files = usage.files.saturating_sub(self.usage.files);
            usage.bytes = usage.bytes.saturating_sub(self.usage.bytes);
            usage.fds = usage.fds.saturating_sub(self.usage.fds);
        }
    }
}

fn receive_resource_pool() -> &'static Arc<ReceiveResourcePool> {
    RECEIVE_RESOURCE_POOL.get_or_init(|| {
        ReceiveResourcePool::new(SnapshotResourceLimits {
            max_files: MAX_RECEIVE_FILES_GLOBAL,
            max_bytes: MAX_RECEIVE_BYTES_GLOBAL,
            max_fds: MAX_RECEIVE_FDS_GLOBAL,
        })
    })
}

struct SnapshotWorkerPermit;

#[cfg(test)]
struct TestSnapshotWorkerPermit;

#[cfg(test)]
impl TestSnapshotWorkerPermit {
    fn acquire() -> Self {
        while TEST_SNAPSHOT_WORKER_ACTIVE
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            std::thread::yield_now();
        }
        Self
    }
}

#[cfg(test)]
impl Drop for TestSnapshotWorkerPermit {
    fn drop(&mut self) {
        TEST_SNAPSHOT_WORKER_ACTIVE.store(false, Ordering::Release);
    }
}

impl SnapshotWorkerPermit {
    fn acquire() -> Option<Self> {
        ACTIVE_SNAPSHOT_WORKERS
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |active| {
                (active < MAX_SNAPSHOT_WORKERS).then_some(active + 1)
            })
            .ok()
            .map(|_| Self)
    }
}

impl Drop for SnapshotWorkerPermit {
    fn drop(&mut self) {
        ACTIVE_SNAPSHOT_WORKERS.fetch_sub(1, Ordering::AcqRel);
    }
}

fn snapshot_reaper() -> Option<&'static mpsc::SyncSender<std::thread::JoinHandle<()>>> {
    SNAPSHOT_REAPER
        .get_or_init(|| {
            let (sender, receiver) =
                mpsc::sync_channel::<std::thread::JoinHandle<()>>(MAX_SNAPSHOT_WORKERS);
            std::thread::Builder::new()
                .name("zmodem-snapshot-reaper".to_string())
                .spawn(move || {
                    for worker in receiver {
                        let _ = worker.join();
                    }
                })
                .ok()
                .map(|_| sender)
        })
        .as_ref()
}

fn reap_snapshot_worker(worker: std::thread::JoinHandle<()>) {
    if worker.is_finished() {
        let _ = worker.join();
        return;
    }
    if let Some(reaper) = snapshot_reaper() {
        match reaper.try_send(worker) {
            Ok(()) => return,
            Err(error) => {
                let worker = match error {
                    mpsc::TrySendError::Full(worker) | mpsc::TrySendError::Disconnected(worker) => {
                        worker
                    }
                };
                if worker.is_finished() {
                    let _ = worker.join();
                } else {
                    // The worker itself owns a global permit, so detaching a
                    // handle here cannot create an unbounded population even
                    // if a filesystem syscall never returns.
                    drop(worker);
                }
                return;
            }
        }
    }
    // Thread creation failure leaves no safe way to synchronously join an
    // unknown blocking filesystem syscall while holding protocol state. The
    // global permit still bounds detached workers, while cooperative
    // cancellation prevents subsequent chunks from being copied.
    drop(worker);
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ZmodemDirection {
    Receive,
    Send,
}

impl ZmodemDirection {
    fn as_str(self) -> &'static str {
        match self {
            Self::Receive => "receive",
            Self::Send => "send",
        }
    }
}

#[derive(Debug)]
pub struct ZmodemEvent {
    pub kind: &'static str,
    pub payload: Value,
}

impl ZmodemEvent {
    fn new(kind: &'static str, payload: Value) -> Self {
        Self { kind, payload }
    }
}

#[derive(Debug, Default)]
pub struct ZmodemEffects {
    pub passthrough: Vec<u8>,
    pub events: Vec<ZmodemEvent>,
    pub terminate_transport: bool,
    pub(crate) receive_publish_pending: bool,
}

#[derive(Debug, thiserror::Error)]
pub enum ZmodemError {
    #[error("ZMODEM transfer is not awaiting this operation")]
    InvalidState,
    #[error("ZMODEM transfer id does not match the active transfer")]
    StaleTransfer,
    #[error("invalid ZMODEM destination")]
    InvalidDestination,
    #[error("invalid ZMODEM source file list")]
    InvalidSourceFiles,
    #[error("ZMODEM snapshot resource limit exceeded")]
    ResourceLimit,
    #[error("ZMODEM operation is unsupported on this platform")]
    UnsupportedPlatform,
    #[error("ZMODEM I/O failed")]
    Io,
    #[error("ZMODEM publish failed for {partial_path}")]
    Publish {
        partial_path: PathBuf,
        recovery_token: Option<String>,
    },
    #[error("ZMODEM protocol failed: {0}")]
    Protocol(String),
    #[error("ZMODEM wire buffer limit exceeded")]
    WireBufferOverflow,
    #[error("ZMODEM transfer timed out")]
    Timeout,
}

impl ZmodemError {
    pub(crate) fn aborts_active_transfer(&self) -> bool {
        matches!(
            self,
            Self::Io
                | Self::Publish { .. }
                | Self::Protocol(_)
                | Self::WireBufferOverflow
                | Self::Timeout
                | Self::UnsupportedPlatform
        )
    }
}

#[derive(Debug)]
struct SendFile {
    file: File,
    name: String,
    size: u32,
    modification_time: Option<u64>,
}

struct SendSource {
    file: File,
    name: String,
    size: u32,
    modification_time: Option<u64>,
    original_mutation: SendSourceMutation,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct SendSourceMutation {
    modified: Option<SystemTime>,
    #[cfg(unix)]
    changed_seconds: i64,
    #[cfg(unix)]
    changed_nanoseconds: i64,
}

impl SendSourceMutation {
    fn from_metadata(metadata: &fs::Metadata) -> Self {
        Self {
            modified: metadata.modified().ok(),
            #[cfg(unix)]
            changed_seconds: metadata.ctime(),
            #[cfg(unix)]
            changed_nanoseconds: metadata.ctime_nsec(),
        }
    }
}

#[derive(Debug)]
struct ReceiveFile {
    file: File,
    directory: ReceiveDirectory,
    temp_name: String,
    backup_name: Option<String>,
    base_name: String,
    name: String,
    /// True only after the no-replace rename has published `name`. Cleanup
    /// must never probe the merely intended destination before that point:
    /// another creator may legitimately claim it while cleanup is deferred.
    final_name_published: bool,
    expected_size: Option<u32>,
    modification_time: Option<u64>,
    owner_session_id: Option<u64>,
    written: u64,
    publish_protected: bool,
    _resource_lease: ReceiveResourceLease,
}

struct VerifiedPublishedFile {
    file: File,
    mutation: SendSourceMutation,
    length: u64,
}

impl VerifiedPublishedFile {
    fn revalidate(&self, directory: &ReceiveDirectory, name: &str) -> std::io::Result<()> {
        let metadata = self.file.metadata()?;
        if metadata.len() != self.length
            || SendSourceMutation::from_metadata(&metadata) != self.mutation
            || !directory.entry_matches_file(name, &self.file)?
        {
            return Err(std::io::Error::from(std::io::ErrorKind::InvalidData));
        }
        Ok(())
    }

    fn restore_write_mode_and_revalidate(
        &self,
        directory: &ReceiveDirectory,
        name: &str,
    ) -> std::io::Result<()> {
        #[cfg(unix)]
        {
            let trusted_length = self.length;
            let trusted_modified = self.mutation.modified;
            // Reject any mutation after the verified link-removal boundary.
            // The following chmod is the only expected ctime change.
            self.revalidate(directory, name)?;
            self.file
                .set_permissions(fs::Permissions::from_mode(0o600))?;
            self.file.sync_all()?;
            let metadata = self.file.metadata()?;
            // chmod necessarily changes ctime, so the final check keeps the
            // trusted pre-chmod length and mtime baseline while explicitly
            // allowing only that ctime transition. Never replace the trusted
            // baseline with metadata read after the file becomes writable.
            if metadata.len() != trusted_length
                || metadata.modified().ok() != trusted_modified
                || metadata.permissions().mode() & 0o777 != 0o600
                || !directory.entry_matches_file(name, &self.file)?
            {
                return Err(std::io::Error::from(std::io::ErrorKind::InvalidData));
            }
            Ok(())
        }

        #[cfg(not(unix))]
        {
            let _ = (directory, name);
            Err(std::io::Error::from(std::io::ErrorKind::Unsupported))
        }
    }

    fn accept_verified_link_removal(
        &mut self,
        directory: &ReceiveDirectory,
        name: &str,
    ) -> std::io::Result<()> {
        #[cfg(unix)]
        {
            let metadata = self.file.metadata()?;
            if metadata.len() != self.length
                || metadata.modified().ok() != self.mutation.modified
                || metadata.nlink() != 1
                || !directory.entry_matches_file(name, &self.file)?
            {
                return Err(std::io::Error::from(std::io::ErrorKind::InvalidData));
            }
            // Removing the one rollback hard link necessarily changes ctime.
            // Rebase only ctime after proving that trusted size/mtime, link
            // count, and final-name identity are unchanged.
            self.mutation.changed_seconds = metadata.ctime();
            self.mutation.changed_nanoseconds = metadata.ctime_nsec();
            self.revalidate(directory, name)
        }

        #[cfg(not(unix))]
        {
            let _ = (directory, name);
            Err(std::io::Error::from(std::io::ErrorKind::Unsupported))
        }
    }
}

#[derive(Debug)]
struct ReceiveDirectory {
    selected_path: PathBuf,
    #[cfg(unix)]
    handle: File,
    _fd_lease: ReceiveResourceLease,
}

struct RecoveryEntry {
    token: String,
    owner_session_id: Option<u64>,
    directory: ReceiveDirectory,
    temp_name: String,
    cleanup_names: Vec<String>,
    file: File,
    created_at: Instant,
    reveal_lease_until: Option<Instant>,
    _file_resource_lease: ReceiveResourceLease,
}

struct RecoveryCandidate {
    directory: ReceiveDirectory,
    temp_name: String,
    file: File,
    _file_fd_lease: ReceiveResourceLease,
}

struct StagingCleanup {
    file: File,
    directory: ReceiveDirectory,
    temp_name: String,
    cleanup_names: Vec<String>,
    _file_resource_lease: ReceiveResourceLease,
}

#[derive(Clone, Copy)]
struct RecoverySessionTombstone {
    session_id: u64,
    created_at: Instant,
}

#[derive(Default)]
struct RecoveryRegistry {
    entries: VecDeque<RecoveryEntry>,
    closed_sessions: VecDeque<RecoverySessionTombstone>,
}

static RECOVERY_REGISTRY: OnceLock<Mutex<RecoveryRegistry>> = OnceLock::new();
static RECOVERY_SWEEPER_STARTED: Mutex<bool> = Mutex::new(false);

impl ReceiveDirectory {
    fn open(path: &Path) -> Result<Self, ZmodemError> {
        if !path.is_absolute() {
            return Err(ZmodemError::InvalidDestination);
        }

        #[cfg(unix)]
        {
            let fd_lease = receive_resource_pool()
                .acquire(0, 0, 1)
                .ok_or(ZmodemError::ResourceLimit)?;
            let mut options = OpenOptions::new();
            options.read(true).custom_flags(
                libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK,
            );
            let handle = options
                .open(path)
                .map_err(|_| ZmodemError::InvalidDestination)?;
            if !handle
                .metadata()
                .map_err(|_| ZmodemError::InvalidDestination)?
                .is_dir()
            {
                return Err(ZmodemError::InvalidDestination);
            }
            Ok(Self {
                selected_path: path.to_path_buf(),
                handle,
                _fd_lease: fd_lease,
            })
        }

        #[cfg(not(unix))]
        {
            let _ = path;
            Err(ZmodemError::UnsupportedPlatform)
        }
    }

    fn try_clone(&self) -> Result<Self, ZmodemError> {
        #[cfg(unix)]
        {
            let fd_lease = receive_resource_pool()
                .acquire(0, 0, 1)
                .ok_or(ZmodemError::ResourceLimit)?;
            Ok(Self {
                selected_path: self.selected_path.clone(),
                handle: self.handle.try_clone().map_err(|_| ZmodemError::Io)?,
                _fd_lease: fd_lease,
            })
        }

        #[cfg(not(unix))]
        {
            Err(ZmodemError::UnsupportedPlatform)
        }
    }

    fn current_path(&self) -> Option<PathBuf> {
        #[cfg(target_os = "macos")]
        {
            let mut buffer = vec![0_i8; libc::PATH_MAX as usize];
            // SAFETY: `buffer` is writable for PATH_MAX bytes and the live
            // directory descriptor remains owned by `self` for the call.
            if unsafe {
                libc::fcntl(
                    self.handle.as_raw_fd(),
                    libc::F_GETPATH,
                    buffer.as_mut_ptr(),
                )
            } == 0
            {
                // SAFETY: F_GETPATH writes a NUL-terminated path on success.
                let bytes = unsafe { CStr::from_ptr(buffer.as_ptr()) }.to_bytes();
                return Some(PathBuf::from(std::ffi::OsStr::from_bytes(bytes)));
            }
        }

        #[cfg(target_os = "linux")]
        if let Ok(path) = fs::read_link(format!("/proc/self/fd/{}", self.handle.as_raw_fd())) {
            return Some(path);
        }

        None
    }

    fn child_path(&self, name: &str) -> PathBuf {
        self.current_path()
            .unwrap_or_else(|| self.selected_path.clone())
            .join(name)
    }

    #[cfg(unix)]
    fn child_name(name: &str) -> std::io::Result<CString> {
        if name.is_empty() || name.as_bytes().contains(&b'/') {
            return Err(std::io::Error::from(std::io::ErrorKind::InvalidInput));
        }
        CString::new(name.as_bytes())
            .map_err(|_| std::io::Error::from(std::io::ErrorKind::InvalidInput))
    }

    fn child_exists(&self, name: &str) -> std::io::Result<bool> {
        #[cfg(unix)]
        {
            let child_name = Self::child_name(name)?;
            let mut stat = std::mem::MaybeUninit::<libc::stat>::uninit();
            // SAFETY: `name` is NUL-terminated and `stat` points to writable
            // storage. AT_SYMLINK_NOFOLLOW makes any existing entry count.
            let result = unsafe {
                libc::fstatat(
                    self.handle.as_raw_fd(),
                    child_name.as_ptr(),
                    stat.as_mut_ptr(),
                    libc::AT_SYMLINK_NOFOLLOW,
                )
            };
            if result == 0 {
                return Ok(true);
            }
            let error = std::io::Error::last_os_error();
            if error.raw_os_error() == Some(libc::ENOENT) {
                Ok(false)
            } else {
                Err(error)
            }
        }

        #[cfg(not(unix))]
        {
            let _ = name;
            Err(std::io::Error::from(std::io::ErrorKind::Unsupported))
        }
    }

    #[cfg(unix)]
    fn entry_matches_file(&self, name: &str, file: &File) -> std::io::Result<bool> {
        let name = Self::child_name(name)?;
        let mut entry = std::mem::MaybeUninit::<libc::stat>::uninit();
        let mut opened = std::mem::MaybeUninit::<libc::stat>::uninit();
        // SAFETY: both stat buffers are writable and the directory/name/file
        // descriptors remain live for the calls. AT_SYMLINK_NOFOLLOW makes a
        // replacement symlink compare as the symlink itself, never its target.
        let entry_result = unsafe {
            libc::fstatat(
                self.handle.as_raw_fd(),
                name.as_ptr(),
                entry.as_mut_ptr(),
                libc::AT_SYMLINK_NOFOLLOW,
            )
        };
        if entry_result != 0 {
            let error = std::io::Error::last_os_error();
            return if error.raw_os_error() == Some(libc::ENOENT) {
                Ok(false)
            } else {
                Err(error)
            };
        }
        // SAFETY: the file descriptor is live and `opened` is writable.
        if unsafe { libc::fstat(file.as_raw_fd(), opened.as_mut_ptr()) } != 0 {
            return Err(std::io::Error::last_os_error());
        }
        // SAFETY: both calls above initialized their stat buffers on success.
        let entry = unsafe { entry.assume_init() };
        let opened = unsafe { opened.assume_init() };
        Ok(entry.st_dev == opened.st_dev
            && entry.st_ino == opened.st_ino
            && (entry.st_mode & libc::S_IFMT) == libc::S_IFREG)
    }

    #[cfg(unix)]
    fn verified_child_path(&self, name: &str, file: &File) -> Option<PathBuf> {
        if !self.entry_matches_file(name, file).ok()? {
            return None;
        }
        let directory_path = self.current_path()?;
        let reopened_directory = ReceiveDirectory::open(&directory_path).ok()?;
        let directory_metadata = self.handle.metadata().ok()?;
        let reopened_metadata = reopened_directory.handle.metadata().ok()?;
        if directory_metadata.dev() != reopened_metadata.dev()
            || directory_metadata.ino() != reopened_metadata.ino()
            || !reopened_directory.entry_matches_file(name, file).ok()?
        {
            return None;
        }
        Some(directory_path.join(name))
    }

    #[cfg(not(unix))]
    fn entry_matches_file(&self, _name: &str, _file: &File) -> std::io::Result<bool> {
        Ok(false)
    }

    #[cfg(not(unix))]
    fn verified_child_path(&self, _name: &str, _file: &File) -> Option<PathBuf> {
        None
    }

    fn create_new(&self, name: &str) -> std::io::Result<File> {
        #[cfg(unix)]
        {
            let name = Self::child_name(name)?;
            // SAFETY: the directory descriptor and NUL-terminated relative
            // name are valid; create-new plus no-follow prevents replacement
            // and final-component symlink traversal.
            let fd = unsafe {
                libc::openat(
                    self.handle.as_raw_fd(),
                    name.as_ptr(),
                    libc::O_RDWR
                        | libc::O_CREAT
                        | libc::O_EXCL
                        | libc::O_NOFOLLOW
                        | libc::O_CLOEXEC,
                    0o600,
                )
            };
            if fd < 0 {
                Err(std::io::Error::last_os_error())
            } else {
                // SAFETY: `openat` returned a newly owned descriptor.
                Ok(unsafe { File::from_raw_fd(fd) })
            }
        }

        #[cfg(not(unix))]
        {
            let _ = name;
            Err(std::io::Error::from(std::io::ErrorKind::Unsupported))
        }
    }

    fn open_existing_regular(&self, name: &str) -> std::io::Result<File> {
        #[cfg(unix)]
        {
            let child_name = Self::child_name(name)?;
            // SAFETY: the directory descriptor and NUL-terminated relative
            // name are valid. O_NOFOLLOW rejects a replaced symlink.
            let fd = unsafe {
                libc::openat(
                    self.handle.as_raw_fd(),
                    child_name.as_ptr(),
                    libc::O_RDONLY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
                )
            };
            if fd < 0 {
                return Err(std::io::Error::last_os_error());
            }
            // SAFETY: `openat` returned a newly owned descriptor.
            let file = unsafe { File::from_raw_fd(fd) };
            if !file.metadata()?.file_type().is_file() || !self.entry_matches_file(name, &file)? {
                return Err(std::io::Error::from(std::io::ErrorKind::InvalidData));
            }
            Ok(file)
        }

        #[cfg(not(unix))]
        {
            let _ = name;
            Err(std::io::Error::from(std::io::ErrorKind::Unsupported))
        }
    }

    fn remove(&self, name: &str) -> std::io::Result<()> {
        #[cfg(unix)]
        {
            let name = Self::child_name(name)?;
            // SAFETY: the descriptor and NUL-terminated relative name are
            // valid; flags 0 removes a non-directory entry only.
            let result = unsafe { libc::unlinkat(self.handle.as_raw_fd(), name.as_ptr(), 0) };
            if result == 0 {
                Ok(())
            } else {
                Err(std::io::Error::last_os_error())
            }
        }

        #[cfg(not(unix))]
        {
            let _ = name;
            Err(std::io::Error::from(std::io::ErrorKind::Unsupported))
        }
    }

    fn sync(&self) -> std::io::Result<()> {
        #[cfg(unix)]
        {
            self.handle.sync_all()
        }

        #[cfg(not(unix))]
        {
            Err(std::io::Error::from(std::io::ErrorKind::Unsupported))
        }
    }

    fn sync_published_file(
        &self,
        source_file: &File,
        name: &str,
    ) -> std::io::Result<VerifiedPublishedFile> {
        let published = self.open_existing_regular(name)?;
        if !self.entry_matches_file(name, source_file)?
            || !self.entry_matches_file(name, &published)?
        {
            return Err(std::io::Error::from(std::io::ErrorKind::InvalidData));
        }
        published.sync_all()?;
        let metadata = published.metadata()?;
        let source_metadata = source_file.metadata()?;
        let mutation = SendSourceMutation::from_metadata(&metadata);
        let verified = VerifiedPublishedFile {
            file: published,
            mutation,
            length: metadata.len(),
        };
        if source_metadata.len() != verified.length
            || SendSourceMutation::from_metadata(&source_metadata) != mutation
        {
            return Err(std::io::Error::from(std::io::ErrorKind::InvalidData));
        }
        verified.revalidate(self, name)?;
        Ok(verified)
    }

    fn rename_child_noreplace(&self, source: &str, destination: &str) -> std::io::Result<()> {
        #[cfg(unix)]
        let source_name = Self::child_name(source)?;
        #[cfg(unix)]
        let destination_name = Self::child_name(destination)?;

        #[cfg(target_os = "macos")]
        let result = unsafe {
            libc::renameatx_np(
                self.handle.as_raw_fd(),
                source_name.as_ptr(),
                self.handle.as_raw_fd(),
                destination_name.as_ptr(),
                libc::RENAME_EXCL,
            )
        };

        #[cfg(target_os = "linux")]
        let result = unsafe {
            libc::syscall(
                libc::SYS_renameat2,
                self.handle.as_raw_fd(),
                source_name.as_ptr(),
                self.handle.as_raw_fd(),
                destination_name.as_ptr(),
                libc::RENAME_NOREPLACE,
            )
        };

        #[cfg(any(target_os = "macos", target_os = "linux"))]
        if result == 0 {
            Ok(())
        } else {
            Err(std::io::Error::last_os_error())
        }

        #[cfg(all(unix, not(any(target_os = "macos", target_os = "linux"))))]
        {
            let _ = (source_name, destination_name);
            Err(std::io::Error::from(std::io::ErrorKind::Unsupported))
        }

        #[cfg(not(unix))]
        {
            let _ = (source, destination);
            Err(std::io::Error::from(std::io::ErrorKind::Unsupported))
        }
    }

    #[cfg(unix)]
    fn create_publish_backup(
        &self,
        source_name: &str,
        source_file: &File,
    ) -> Result<String, Option<String>> {
        if !self
            .entry_matches_file(source_name, source_file)
            .map_err(|_| None)?
        {
            return Err(None);
        }
        let source = Self::child_name(source_name).map_err(|_| None)?;
        for _ in 0..TEMP_FILE_ATTEMPTS {
            let backup_name = format!(
                ".ianvs-zmodem-backup-{}.part",
                random_hex_token().map_err(|_| None)?
            );
            let backup = Self::child_name(&backup_name).map_err(|_| None)?;
            // The staging file is already 0400. A same-directory hard link
            // is an O(1), same-filesystem rollback authority supported on the
            // ordinary POSIX filesystems where rename-based publication is
            // available; it does not depend on APFS clonefile or FICLONE.
            let result = unsafe {
                libc::linkat(
                    self.handle.as_raw_fd(),
                    source.as_ptr(),
                    self.handle.as_raw_fd(),
                    backup.as_ptr(),
                    0,
                )
            };
            if result == 0 {
                let verification = (|| {
                    let backup_file = self.open_existing_regular(&backup_name)?;
                    if !self.entry_matches_file(&backup_name, source_file)? {
                        return Err(std::io::Error::from(std::io::ErrorKind::InvalidData));
                    }
                    backup_file.sync_all()
                })();
                match verification {
                    Ok(()) => return Ok(backup_name),
                    Err(_) => {
                        // linkat has already created an alias. Forget its name
                        // only after identity-safe detach confirms it is gone;
                        // otherwise return the name to ReceiveFile cleanup.
                        if self
                            .detach_verified_alias(&backup_name, source_file)
                            .is_err()
                        {
                            return Err(Some(backup_name));
                        }
                        return Err(None);
                    }
                }
            }
            let error = std::io::Error::last_os_error();
            if error.kind() != std::io::ErrorKind::AlreadyExists {
                return Err(None);
            }
        }
        Err(None)
    }

    #[cfg(not(unix))]
    fn create_publish_backup(
        &self,
        _source_name: &str,
        _source_file: &File,
    ) -> Result<String, Option<String>> {
        Err(None)
    }

    fn remove_verified_child(&self, name: &str, file: &File) -> std::io::Result<()> {
        if !self.entry_matches_file(name, file)? {
            return Err(std::io::Error::from(std::io::ErrorKind::InvalidData));
        }
        self.remove(name)?;
        self.sync()
    }

    fn detach_verified_alias(&self, name: &str, file: &File) -> std::io::Result<()> {
        if !self.entry_matches_file(name, file)? {
            return Ok(());
        }
        match self.remove_verified_child(name, file) {
            Ok(()) => Ok(()),
            Err(error) => {
                // remove_verified_child may have unlinked successfully and
                // failed only while syncing the directory. Re-check identity:
                // if our inode is no longer reachable through this name, the
                // recovery authority is isolated even though durability could
                // not be confirmed. A replacement is never deleted.
                if self.entry_matches_file(name, file).unwrap_or(true) {
                    Err(error)
                } else {
                    Ok(())
                }
            }
        }
    }

    fn quarantine_for_removal(&self, name: &str, file: &File) -> std::io::Result<Option<String>> {
        for _ in 0..TEMP_FILE_ATTEMPTS {
            let quarantine = format!(".ianvs-zmodem-quarantine-{}.part", random_hex_token()?);
            match self.rename_child_noreplace(name, &quarantine) {
                Ok(()) => {
                    if self.entry_matches_file(&quarantine, file)? {
                        return Ok(Some(quarantine));
                    }
                    // A replacement that won before the atomic rename is not
                    // ours. Put it back when possible and never unlink it.
                    let _ = self.rename_child_noreplace(&quarantine, name);
                    return Ok(None);
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
                Err(error) => return Err(error),
            }
        }
        Err(std::io::Error::from(std::io::ErrorKind::AlreadyExists))
    }

    fn publish_file_noreplace(
        &self,
        source_file: &File,
        source: &str,
        destination: &str,
    ) -> std::io::Result<()> {
        #[cfg(unix)]
        if !self.entry_matches_file(source, source_file)? {
            return Err(std::io::Error::from(std::io::ErrorKind::InvalidData));
        }
        self.rename_child_noreplace(source, destination)
    }
}

fn recovery_registry() -> &'static Mutex<RecoveryRegistry> {
    RECOVERY_REGISTRY.get_or_init(|| Mutex::new(RecoveryRegistry::default()))
}

fn prune_recovery_registry(registry: &mut RecoveryRegistry, now: Instant) {
    let mut index = 0;
    while index < registry.entries.len() {
        let reveal_leased = registry.entries[index]
            .reveal_lease_until
            .is_some_and(|deadline| deadline > now);
        if !reveal_leased
            && now.duration_since(registry.entries[index].created_at) > RECOVERY_ENTRY_TTL
        {
            if let Some(entry) = registry.entries.remove(index) {
                schedule_recovery_cleanup(entry);
            }
        } else {
            index += 1;
        }
    }
    registry
        .closed_sessions
        .retain(|tombstone| now.duration_since(tombstone.created_at) <= RECOVERY_ENTRY_TTL);
}

fn recovery_candidate(entry: &RecoveryEntry) -> Option<RecoveryCandidate> {
    let file_fd_lease = receive_resource_pool().acquire(0, 0, 1)?;
    Some(RecoveryCandidate {
        directory: entry.directory.try_clone().ok()?,
        temp_name: entry.temp_name.clone(),
        file: entry.file.try_clone().ok()?,
        _file_fd_lease: file_fd_lease,
    })
}

fn lease_recovery_candidate(entry: &mut RecoveryEntry, now: Instant) -> Option<RecoveryCandidate> {
    // Acquire every fallible clone/FD lease before extending the externally
    // visible Reveal lease. A failed resolve must not pin an unusable entry.
    let candidate = recovery_candidate(entry)?;
    entry.reveal_lease_until = now.checked_add(RECOVERY_REVEAL_LEASE);
    Some(candidate)
}

fn remove_recovery_entry(token: &str, session_id: u64) {
    let entry =
        {
            let Ok(mut registry) = recovery_registry().lock() else {
                return;
            };
            let Some(index) = registry.entries.iter().position(|entry| {
                entry.token == token && entry.owner_session_id == Some(session_id)
            }) else {
                return;
            };
            registry.entries.remove(index)
        };
    let Some(entry) = entry else {
        return;
    };
    schedule_recovery_cleanup(entry);
}

fn recovery_sweeper_loop() {
    loop {
        std::thread::sleep(Duration::from_secs(60));
        if let Ok(mut registry) = recovery_registry().lock() {
            prune_recovery_registry(&mut registry, Instant::now());
        }
    }
}

fn start_recovery_sweeper_with<F>(started: &Mutex<bool>, spawn: F) -> bool
where
    F: FnOnce() -> std::io::Result<std::thread::JoinHandle<()>>,
{
    let Ok(mut started) = started.lock() else {
        return false;
    };
    if *started {
        return true;
    }
    match spawn() {
        Ok(_worker) => {
            // Dropping JoinHandle detaches the process-lifetime sweeper.
            *started = true;
            true
        }
        Err(_) => false,
    }
}

fn start_recovery_sweeper() -> bool {
    start_recovery_sweeper_with(&RECOVERY_SWEEPER_STARTED, || {
        std::thread::Builder::new()
            .name("zmodem-recovery-sweeper".to_string())
            .spawn(recovery_sweeper_loop)
    })
}

fn register_recovery(cleanup: StagingCleanup, owner_session_id: Option<u64>) -> Option<String> {
    register_recovery_with_sweeper(cleanup, owner_session_id, start_recovery_sweeper)
}

fn register_recovery_with_sweeper<F>(
    cleanup: StagingCleanup,
    owner_session_id: Option<u64>,
    ensure_sweeper: F,
) -> Option<String>
where
    F: FnOnce() -> bool,
{
    let directory = match cleanup.directory.try_clone() {
        Ok(directory) => directory,
        Err(_) => {
            schedule_cleanup(cleanup);
            return None;
        }
    };
    if !directory
        .entry_matches_file(&cleanup.temp_name, &cleanup.file)
        .unwrap_or(false)
    {
        schedule_cleanup(cleanup);
        return None;
    }
    let token = match random_hex_token() {
        Ok(token) => token,
        Err(_) => {
            schedule_cleanup(cleanup);
            return None;
        }
    };
    let now = Instant::now();
    if !ensure_sweeper() {
        // A recovery authority without a live TTL sweeper could retain its
        // hidden file and resource leases indefinitely. Fail closed and make
        // the publish error non-recoverable instead.
        schedule_cleanup(cleanup);
        return None;
    }
    let mut registry = match recovery_registry().lock() {
        Ok(registry) => registry,
        Err(_) => {
            schedule_cleanup(cleanup);
            return None;
        }
    };
    prune_recovery_registry(&mut registry, now);
    if let Some(owner_session_id) = owner_session_id
        && let Some(tombstone) = registry
            .closed_sessions
            .iter_mut()
            .find(|entry| entry.session_id == owner_session_id)
    {
        // A publish failure that finishes concurrently with session close is
        // recoverable for a full TTL from the failure, not merely from close.
        tombstone.created_at = now;
    }
    let StagingCleanup {
        file,
        directory: _,
        temp_name,
        cleanup_names,
        _file_resource_lease: file_resource_lease,
    } = cleanup;
    if !push_recovery_entry(
        &mut registry,
        RecoveryEntry {
            token: token.clone(),
            owner_session_id,
            directory,
            temp_name,
            cleanup_names,
            file,
            created_at: now,
            reveal_lease_until: None,
            _file_resource_lease: file_resource_lease,
        },
        MAX_RECOVERY_ENTRIES,
    ) {
        return None;
    }
    if let Some(owner_session_id) = owner_session_id {
        // Every live recovery entry carries its own closed-session fallback
        // authority. The token remains unguessable and owner-bound, while a
        // session close racing a late publish failure can no longer strand a
        // complete staging file merely because the tombstone queue was full.
        upsert_recovery_session_tombstone(&mut registry, owner_session_id, now);
    }
    Some(token)
}

fn random_hex_token() -> std::io::Result<String> {
    let mut random = [0_u8; 16];
    File::open("/dev/urandom")?.read_exact(&mut random)?;
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut token = String::with_capacity(32);
    for byte in random {
        token.push(char::from(HEX[usize::from(byte >> 4)]));
        token.push(char::from(HEX[usize::from(byte & 0x0f)]));
    }
    Ok(token)
}

fn push_recovery_entry(
    registry: &mut RecoveryRegistry,
    entry: RecoveryEntry,
    max_entries: usize,
) -> bool {
    if max_entries == 0 {
        schedule_recovery_cleanup(entry);
        return false;
    }
    while registry.entries.len() >= max_entries {
        let now = Instant::now();
        let Some(index) = registry.entries.iter().position(|entry| {
            entry
                .reveal_lease_until
                .is_none_or(|deadline| deadline <= now)
        }) else {
            schedule_recovery_cleanup(entry);
            return false;
        };
        if let Some(evicted) = registry.entries.remove(index) {
            schedule_recovery_cleanup(evicted);
        }
    }
    registry.entries.push_back(entry);
    true
}

fn resolve_recovery_path(token: &str, session_id: u64) -> Option<PathBuf> {
    resolve_recovery_path_at(token, session_id, Instant::now())
}

pub(crate) fn resolve_owned_recovery(token: &str, session_id: u64) -> Option<PathBuf> {
    resolve_recovery_path(token, session_id)
}

fn resolve_recovery_path_at(token: &str, session_id: u64, now: Instant) -> Option<PathBuf> {
    if token.len() != 32 || !token.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    let candidate = {
        let mut registry = recovery_registry().lock().ok()?;
        prune_recovery_registry(&mut registry, now);
        let entry = registry
            .entries
            .iter_mut()
            .find(|entry| entry.token == token && entry.owner_session_id == Some(session_id))?;
        lease_recovery_candidate(entry, now)?
    };
    let path = candidate
        .directory
        .verified_child_path(&candidate.temp_name, &candidate.file)
        .filter(|path| path.is_absolute());
    if path.is_none() {
        remove_recovery_entry(token, session_id);
    }
    path
}

pub(crate) fn tombstone_recovery_session(session_id: u64) {
    tombstone_recovery_session_at(session_id, Instant::now());
}

fn tombstone_recovery_session_at(session_id: u64, now: Instant) {
    if !start_recovery_sweeper() {
        return;
    }
    let Ok(mut registry) = recovery_registry().lock() else {
        return;
    };
    prune_recovery_registry(&mut registry, now);
    upsert_recovery_session_tombstone(&mut registry, session_id, now);
}

fn upsert_recovery_session_tombstone(
    registry: &mut RecoveryRegistry,
    session_id: u64,
    now: Instant,
) {
    registry
        .closed_sessions
        .retain(|tombstone| tombstone.session_id != session_id);
    while registry.closed_sessions.len() >= MAX_RECOVERY_ENTRIES {
        let Some(index) = registry.closed_sessions.iter().position(|tombstone| {
            !registry
                .entries
                .iter()
                .any(|entry| entry.owner_session_id == Some(tombstone.session_id))
        }) else {
            // Every retained tombstone protects a live recovery entry. A
            // close with no recovery must not evict that authority merely to
            // reserve space for a hypothetical late publish failure.
            return;
        };
        registry.closed_sessions.remove(index);
    }
    registry
        .closed_sessions
        .push_back(RecoverySessionTombstone {
            session_id,
            created_at: now,
        });
}

pub(crate) fn resolve_tombstoned_recovery(token: &str, session_id: u64) -> Option<PathBuf> {
    resolve_tombstoned_recovery_at(token, session_id, Instant::now())
}

fn resolve_tombstoned_recovery_at(token: &str, session_id: u64, now: Instant) -> Option<PathBuf> {
    if token.len() != 32 || !token.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    let candidate = {
        let mut registry = recovery_registry().lock().ok()?;
        prune_recovery_registry(&mut registry, now);
        if !registry
            .closed_sessions
            .iter()
            .any(|tombstone| tombstone.session_id == session_id)
        {
            return None;
        }
        let entry = registry
            .entries
            .iter_mut()
            .find(|entry| entry.token == token && entry.owner_session_id == Some(session_id))?;
        lease_recovery_candidate(entry, now)?
    };
    let path = candidate
        .directory
        .verified_child_path(&candidate.temp_name, &candidate.file)
        .filter(|path| path.is_absolute());
    if path.is_none() {
        remove_recovery_entry(token, session_id);
    }
    path
}

pub(crate) fn consume_recovery(token: &str, session_id: u64) -> bool {
    if token.len() != 32 || !token.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return false;
    }
    let entry =
        {
            let Ok(mut registry) = recovery_registry().lock() else {
                return false;
            };
            prune_recovery_registry(&mut registry, Instant::now());
            let Some(index) = registry.entries.iter().position(|entry| {
                entry.token == token && entry.owner_session_id == Some(session_id)
            }) else {
                return false;
            };
            registry.entries.remove(index)
        };
    // Reveal has transferred authority for the preserved path to the user.
    // Release native handles and quota without deleting that user-visible
    // file. Dismiss uses the destructive path below.
    entry.is_some()
}

pub(crate) fn dismiss_recovery(token: &str, session_id: u64) -> bool {
    if token.len() != 32 || !token.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return false;
    }
    let entry =
        {
            let Ok(mut registry) = recovery_registry().lock() else {
                return false;
            };
            prune_recovery_registry(&mut registry, Instant::now());
            let Some(index) = registry.entries.iter().position(|entry| {
                entry.token == token && entry.owner_session_id == Some(session_id)
            }) else {
                return false;
            };
            registry.entries.remove(index)
        };
    let Some(entry) = entry else {
        return false;
    };
    schedule_recovery_cleanup(entry);
    true
}

fn discard_abandoned_recovery(token: &str) -> bool {
    if token.len() != 32 || !token.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return false;
    }
    let entry = {
        let Ok(mut registry) = recovery_registry().lock() else {
            return false;
        };
        prune_recovery_registry(&mut registry, Instant::now());
        let Some(index) = registry
            .entries
            .iter()
            .position(|entry| entry.token == token)
        else {
            return false;
        };
        registry.entries.remove(index)
    };
    let Some(entry) = entry else {
        return false;
    };
    schedule_recovery_cleanup(entry);
    true
}

impl ReceiveFile {
    fn detach_published_name(&mut self) -> std::io::Result<()> {
        if !self.final_name_published {
            return Ok(());
        }
        let result = self.directory.detach_verified_alias(&self.name, &self.file);
        if result.is_ok() {
            self.final_name_published = false;
        }
        result
    }

    fn protect_publish_source(&mut self) -> Result<(), ZmodemError> {
        #[cfg(unix)]
        {
            self.file
                .set_permissions(fs::Permissions::from_mode(0o400))
                .map_err(|_| ZmodemError::Io)?;
            self.file.sync_all().map_err(|_| ZmodemError::Io)?;
            self.publish_protected = true;
            Ok(())
        }

        #[cfg(not(unix))]
        {
            Err(ZmodemError::UnsupportedPlatform)
        }
    }

    fn restore_recovery_mode(&mut self) {
        if !self.publish_protected {
            return;
        }
        #[cfg(unix)]
        {
            let _ = self.file.set_permissions(fs::Permissions::from_mode(0o600));
            let _ = self.file.sync_all();
        }
        self.publish_protected = false;
    }

    fn switch_to_publish_backup(&mut self) -> Result<(), ZmodemError> {
        let backup_name = self.backup_name.clone().ok_or(ZmodemError::Io)?;
        if !self
            .directory
            .entry_matches_file(&backup_name, &self.file)
            .map_err(|_| ZmodemError::Io)?
        {
            return Err(ZmodemError::Io);
        }
        // The stable descriptor already refers to the hard-linked inode. Do
        // not consume another global FD lease merely to change which verified
        // name is exposed as the recovery authority.
        self.temp_name = backup_name;
        self.backup_name = None;
        Ok(())
    }

    #[cfg(test)]
    fn recoverable_path(&self) -> PathBuf {
        self.directory.child_path(&self.temp_name)
    }

    #[cfg(test)]
    fn discard_staging(self) {
        StagingCleanup::from(self).discard();
    }
}

impl From<ReceiveFile> for StagingCleanup {
    fn from(file: ReceiveFile) -> Self {
        let ReceiveFile {
            file,
            directory,
            temp_name,
            backup_name,
            name,
            final_name_published,
            _resource_lease: file_resource_lease,
            ..
        } = file;
        let mut cleanup_names = Vec::new();
        if let Some(backup_name) = backup_name
            && backup_name != temp_name
        {
            cleanup_names.push(backup_name);
        }
        if final_name_published && name != temp_name && !cleanup_names.contains(&name) {
            cleanup_names.push(name);
        }
        Self {
            file,
            directory,
            temp_name,
            cleanup_names,
            _file_resource_lease: file_resource_lease,
        }
    }
}

impl From<RecoveryEntry> for StagingCleanup {
    fn from(entry: RecoveryEntry) -> Self {
        Self {
            file: entry.file,
            directory: entry.directory,
            temp_name: entry.temp_name,
            cleanup_names: entry.cleanup_names,
            _file_resource_lease: entry._file_resource_lease,
        }
    }
}

impl StagingCleanup {
    fn discard(self) {
        // Move the candidate to a fresh random quarantine name, then verify
        // the moved inode before unlink. POSIX has no conditional unlink by
        // inode, so the selected directory is explicitly trusted against a
        // hostile same-UID watcher; these checks protect ordinary replacement
        // races and path redirection, not adversarial mutation between calls.
        let mut names = Vec::with_capacity(self.cleanup_names.len() + 1);
        names.push(self.temp_name);
        names.extend(self.cleanup_names);
        for name in names {
            if let Ok(Some(quarantine)) = self.directory.quarantine_for_removal(&name, &self.file)
                && self
                    .directory
                    .entry_matches_file(&quarantine, &self.file)
                    .unwrap_or(false)
            {
                let _ = self.directory.remove(&quarantine);
                let _ = self.directory.sync();
            }
        }
    }
}

fn staging_cleanup_sender() -> Option<&'static mpsc::Sender<StagingCleanup>> {
    STAGING_CLEANUP_WORKER
        .get_or_init(|| {
            let (sender, receiver) = mpsc::channel::<StagingCleanup>();
            std::thread::Builder::new()
                .name("zmodem-staging-cleanup".to_string())
                .spawn(move || {
                    for cleanup in receiver {
                        cleanup.discard();
                    }
                })
                .ok()
                .map(|_| sender)
        })
        .as_ref()
}

fn schedule_staging_cleanup(file: ReceiveFile) {
    schedule_cleanup(StagingCleanup::from(file));
}

fn schedule_recovery_cleanup(entry: RecoveryEntry) {
    schedule_cleanup(StagingCleanup::from(entry));
}

fn schedule_cleanup(cleanup: StagingCleanup) {
    let Some(sender) = staging_cleanup_sender() else {
        // Thread creation failure is exceptional; retain the previous
        // best-effort cleanup behavior instead of leaking the staging file.
        cleanup.discard();
        return;
    };
    if let Err(error) = sender.send(cleanup) {
        error.0.discard();
    }
}

struct ReceiveTransfer {
    id: u64,
    owner_session_id: Option<u64>,
    engine: Box<Receiver>,
    wire: Vec<u8>,
    wire_offset: usize,
    destination: Option<ReceiveDirectory>,
    current_offer: Option<(String, Option<u32>, Option<u64>)>,
    current_file: Option<ReceiveFile>,
    preparation: Option<ReceivePreparation>,
    publication: Option<ReceivePublication>,
    publication_failure: Option<ZmodemEvent>,
    publication_transport_closed: Option<bool>,
    offered_files: usize,
    completed_files: usize,
    transferred_bytes: u64,
    last_progress: Instant,
    last_activity: Instant,
    progress_deadline: Instant,
    protocol_retry_at: Instant,
    authorization_deadline: Instant,
    session_completed: bool,
    commit_cancellation: Option<ReceiveCommitCancellation>,
}

#[derive(Clone)]
struct ReceiveCommitCancellation {
    operation_epoch: Arc<AtomicU64>,
    expected_epoch: u64,
    publish_phase: Arc<AtomicU8>,
    publish_started_at: Arc<ParkingMutex<Option<Instant>>>,
}

impl ReceiveCommitCancellation {
    fn is_cancelled(&self) -> bool {
        self.operation_epoch.load(Ordering::Acquire) != self.expected_epoch
    }

    fn begin_publish(&self) -> bool {
        // Cancellation claims IDLE by changing it to CANCELLED before it
        // advances the operation epoch. Claim the entire publication job,
        // including metadata and durability syscalls, before a worker is
        // acquired or spawned. Exactly one side can therefore win and close
        // can never miss a pre-namespace failure carrying recovery authority.
        if self.is_cancelled() {
            return false;
        }
        // Hold the watchdog timestamp lock across the phase transition. An
        // observer that sees PUBLISHING and then takes this lock must also see
        // its start time; otherwise the CAS and timestamp store expose a tiny
        // false-negative window to close/watchdog code.
        let mut publish_started_at = self.publish_started_at.lock();
        if self
            .publish_phase
            .compare_exchange(
                RECEIVE_COMMIT_IDLE,
                RECEIVE_COMMIT_PUBLISHING,
                Ordering::AcqRel,
                Ordering::Acquire,
            )
            .is_err()
        {
            return false;
        }
        *publish_started_at = Some(Instant::now());
        if self.is_cancelled() {
            self.publish_phase
                .store(RECEIVE_COMMIT_CANCELLED, Ordering::Release);
            *publish_started_at = None;
            return false;
        }
        true
    }

    fn mark_result_ready(&self) -> bool {
        self.publish_phase
            .compare_exchange(
                RECEIVE_COMMIT_PUBLISHING,
                RECEIVE_COMMIT_RESULT_READY,
                Ordering::AcqRel,
                Ordering::Acquire,
            )
            .is_ok()
    }

    fn publication_is_current(&self) -> bool {
        !self.is_cancelled()
            && self.publish_phase.load(Ordering::Acquire) == RECEIVE_COMMIT_PUBLISHING
    }
}

enum ReceivePreparationDestination {
    Path(PathBuf),
    Open(ReceiveDirectory),
}

struct ReceivePreparation {
    result: mpsc::Receiver<ReceivePreparationResult>,
    worker: Option<std::thread::JoinHandle<()>>,
    cancel: Arc<AtomicBool>,
}

struct ReceivePreparationResult {
    result: Result<PreparedReceive, ZmodemError>,
    finished_at: Instant,
}

struct ReceivePublication {
    result: mpsc::Receiver<ReceivePublicationResult>,
    worker: Option<std::thread::JoinHandle<()>>,
}

struct ReceivePublicationResult {
    result: Result<String, ZmodemError>,
    size: u64,
    finished_at: Instant,
}

impl Drop for ReceivePublication {
    fn drop(&mut self) {
        let Some(worker) = self.worker.take() else {
            return;
        };
        if worker.is_finished() {
            let _ = worker.join();
        } else {
            // Publication may be blocked in an uninterruptible FUSE/network
            // filesystem syscall. The shared worker permit bounds detached
            // jobs process-wide while the file/recovery authority stays owned
            // by the worker until it eventually returns.
            reap_snapshot_worker(worker);
        }
    }
}

fn start_receive_publication(
    id: u64,
    file: ReceiveFile,
    cancellation: ReceiveCommitCancellation,
) -> Result<ReceivePublication, ZmodemError> {
    // The phase and watchdog timestamp cover every path from this point,
    // including worker-pool exhaustion and thread-spawn failure.
    if !cancellation.begin_publish() {
        schedule_staging_cleanup(file);
        return Err(ZmodemError::InvalidState);
    }
    #[cfg(test)]
    let test_worker_permit = TestSnapshotWorkerPermit::acquire();
    let worker_permit = match SnapshotWorkerPermit::acquire() {
        Some(permit) => permit,
        None => return Err(preserved_publish_error(file)),
    };
    // Keep ownership recoverable if thread creation itself fails. Once the
    // worker starts, it takes the file out under this short, non-I/O lock.
    let file_slot = Arc::new(Mutex::new(Some(file)));
    let worker_file_slot = Arc::clone(&file_slot);
    let (result_tx, result_rx) = mpsc::channel();
    let worker = std::thread::Builder::new()
        .name(format!("zmodem-receive-publish-{id}"))
        .spawn(move || {
            let _worker_permit = worker_permit;
            #[cfg(test)]
            let _test_worker_permit = test_worker_permit;
            let Some(file) = worker_file_slot
                .lock()
                .ok()
                .and_then(|mut slot| slot.take())
            else {
                let _ = result_tx.send(ReceivePublicationResult {
                    result: Err(ZmodemError::Io),
                    size: 0,
                    finished_at: Instant::now(),
                });
                return;
            };
            let size = file.written;
            let result = commit_receive_file(file, Some(&cancellation));
            if result.is_err() {
                // Successful commits linearize RESULT_READY while they still
                // own the stable file/directory authority. Failures do not
                // expose a final file, so the worker may mark them here.
                linearize_receive_publication_failure(&cancellation, &result);
            }
            let _ = result_tx.send(ReceivePublicationResult {
                result,
                size,
                finished_at: Instant::now(),
            });
        });
    match worker {
        Ok(worker) => Ok(ReceivePublication {
            result: result_rx,
            worker: Some(worker),
        }),
        Err(_) => {
            let file = file_slot
                .lock()
                .ok()
                .and_then(|mut slot| slot.take())
                .ok_or(ZmodemError::Io)?;
            Err(preserved_publish_error(file))
        }
    }
}

fn linearize_receive_publication_failure(
    cancellation: &ReceiveCommitCancellation,
    result: &Result<String, ZmodemError>,
) {
    if !cancellation.mark_result_ready()
        && let Err(ZmodemError::Publish {
            recovery_token: Some(token),
            ..
        }) = result
    {
        // Timeout won before this failure could become an authoritative
        // session event. The token can never reach the user, so revoke it and
        // delete its hidden authority instead of retaining an unreachable
        // complete file.
        let _ = discard_abandoned_recovery(token);
    }
}

impl Drop for ReceivePreparation {
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::Release);
        let Some(worker) = self.worker.take() else {
            return;
        };
        if worker.is_finished() {
            let _ = worker.join();
        } else {
            reap_snapshot_worker(worker);
        }
    }
}

struct PreparedReceive {
    destination: Option<ReceiveDirectory>,
    file: Option<ReceiveFile>,
}

impl Drop for PreparedReceive {
    fn drop(&mut self) {
        if let Some(file) = self.file.take() {
            schedule_staging_cleanup(file);
        }
    }
}

fn start_receive_preparation(
    id: u64,
    owner_session_id: Option<u64>,
    destination: ReceivePreparationDestination,
    name: String,
    size: Option<u32>,
    modification_time: Option<u64>,
) -> Result<ReceivePreparation, ZmodemError> {
    #[cfg(test)]
    let test_worker_permit = TestSnapshotWorkerPermit::acquire();
    let worker_permit = SnapshotWorkerPermit::acquire().ok_or(ZmodemError::ResourceLimit)?;
    let cancel = Arc::new(AtomicBool::new(false));
    let worker_cancel = Arc::clone(&cancel);
    let (result_tx, result_rx) = mpsc::channel();
    let worker = std::thread::Builder::new()
        .name(format!("zmodem-receive-prepare-{id}"))
        .spawn(move || {
            let _worker_permit = worker_permit;
            #[cfg(test)]
            let _test_worker_permit = test_worker_permit;
            let result = (|| {
                if worker_cancel.load(Ordering::Acquire) {
                    return Err(ZmodemError::InvalidState);
                }
                let (directory, retain_destination) = match destination {
                    ReceivePreparationDestination::Path(path) => {
                        (ReceiveDirectory::open(&path)?, true)
                    }
                    ReceivePreparationDestination::Open(directory) => (directory, false),
                };
                if worker_cancel.load(Ordering::Acquire) {
                    return Err(ZmodemError::InvalidState);
                }
                let file = create_receive_file_at(
                    &directory,
                    &name,
                    size,
                    modification_time,
                    id,
                    owner_session_id,
                    Some(&worker_cancel),
                )?;
                if worker_cancel.load(Ordering::Acquire) {
                    schedule_staging_cleanup(file);
                    return Err(ZmodemError::InvalidState);
                }
                Ok(PreparedReceive {
                    destination: retain_destination.then_some(directory),
                    file: Some(file),
                })
            })();
            let _ = result_tx.send(ReceivePreparationResult {
                result,
                finished_at: Instant::now(),
            });
        })
        .map_err(|_| ZmodemError::Io)?;
    Ok(ReceivePreparation {
        result: result_rx,
        worker: Some(worker),
        cancel,
    })
}

struct AwaitingSend {
    id: u64,
    wire: Vec<u8>,
    last_activity: Instant,
    authorization_deadline: Instant,
}

struct PreparingSend {
    id: u64,
    engine: Option<Sender>,
    wire: Vec<u8>,
    wire_offset: usize,
    result: mpsc::Receiver<SnapshotMessage>,
    worker: Option<std::thread::JoinHandle<()>>,
    cancel: Arc<AtomicBool>,
    snapshot_bytes: u64,
    progress_deadline: Instant,
    protocol_retry_at: Instant,
}

enum SnapshotMessage {
    Progress {
        bytes: u64,
        at: Instant,
    },
    Finished {
        result: Result<PreparedSend, ZmodemError>,
        at: Instant,
    },
}

struct PreparedSend {
    files: VecDeque<SendFile>,
    total_bytes: u64,
    snapshot_resources: SnapshotResourceLease,
}

impl Drop for PreparingSend {
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::Release);
        let Some(worker) = self.worker.take() else {
            return;
        };
        if worker.is_finished() {
            let _ = worker.join();
        } else {
            // Never block the protocol-state lock on a filesystem syscall.
            // The process-wide reaper owns the handle until the cooperative
            // worker exits, avoiding an untracked detached worker per cancel.
            reap_snapshot_worker(worker);
        }
    }
}

struct SendTransfer {
    id: u64,
    engine: Sender,
    wire: Vec<u8>,
    wire_offset: usize,
    files: VecDeque<SendFile>,
    current: Option<SendFile>,
    completed_bytes: u64,
    current_position: u64,
    total_bytes: u64,
    completed_files: usize,
    skipped_files: usize,
    last_progress: Instant,
    last_activity: Instant,
    progress_deadline: Instant,
    protocol_retry_at: Instant,
    session_completed: bool,
    _snapshot_resources: SnapshotResourceLease,
}

struct DrainingTransfer {
    last_activity: Instant,
    hard_deadline: Instant,
    terminal_event: Option<ZmodemEvent>,
    hard_terminated: bool,
    receive_publish_pending: bool,
}

enum TransferState {
    Scanning {
        held: Vec<u8>,
        held_since: Option<Instant>,
    },
    Receiving(ReceiveTransfer),
    AwaitingSend(AwaitingSend),
    PreparingSend(PreparingSend),
    Sending(SendTransfer),
    Draining(DrainingTransfer),
}

pub struct ZmodemManager {
    state: TransferState,
    next_id: u64,
    failure_passthrough: Vec<u8>,
    owner_session_id: Option<u64>,
    operation_epoch: Option<Arc<AtomicU64>>,
    receive_commit_phase: Option<Arc<AtomicU8>>,
    receive_publish_started_at: Option<Arc<ParkingMutex<Option<Instant>>>>,
}

impl Default for ZmodemManager {
    fn default() -> Self {
        Self {
            state: scanning_state(),
            next_id: 1,
            failure_passthrough: Vec::new(),
            owner_session_id: None,
            operation_epoch: None,
            receive_commit_phase: None,
            receive_publish_started_at: None,
        }
    }
}

impl ZmodemManager {
    pub(crate) fn for_session(
        session_id: u64,
        operation_epoch: Arc<AtomicU64>,
        receive_commit_phase: Arc<AtomicU8>,
        receive_publish_started_at: Arc<ParkingMutex<Option<Instant>>>,
    ) -> Self {
        Self {
            state: scanning_state(),
            next_id: 1,
            failure_passthrough: Vec::new(),
            owner_session_id: Some(session_id),
            operation_epoch: Some(operation_epoch),
            receive_commit_phase: Some(receive_commit_phase),
            receive_publish_started_at: Some(receive_publish_started_at),
        }
    }

    pub fn is_active(&self) -> bool {
        !matches!(self.state, TransferState::Scanning { .. })
    }

    pub(crate) fn is_draining(&self) -> bool {
        matches!(self.state, TransferState::Draining(_))
    }

    pub(crate) fn active_transfer(&self) -> Option<(u64, ZmodemDirection)> {
        match &self.state {
            TransferState::Receiving(transfer) => Some((transfer.id, ZmodemDirection::Receive)),
            TransferState::AwaitingSend(transfer) => Some((transfer.id, ZmodemDirection::Send)),
            TransferState::PreparingSend(transfer) => Some((transfer.id, ZmodemDirection::Send)),
            TransferState::Sending(transfer) => Some((transfer.id, ZmodemDirection::Send)),
            TransferState::Scanning { .. } | TransferState::Draining(_) => None,
        }
    }

    pub fn ingest(
        &mut self,
        bytes: &[u8],
        writer: &mut dyn Write,
    ) -> Result<ZmodemEffects, ZmodemError> {
        self.failure_passthrough.clear();
        let mut effects = ZmodemEffects::default();
        match &mut self.state {
            TransferState::Scanning { held, held_since } => {
                held.extend_from_slice(bytes);
                if let Some((offset, direction)) = find_initial_header(held) {
                    effects.passthrough.extend_from_slice(&held[..offset]);
                    let wire = held.split_off(offset);
                    held.clear();
                    let id = self.allocate_id();
                    effects.events.push(ZmodemEvent::new(
                        "zmodem_detected",
                        serde_json::json!({
                            "source": "zmodem",
                            "transferId": id.to_string(),
                            "direction": direction.as_str(),
                        }),
                    ));
                    match direction {
                        ZmodemDirection::Receive => {
                            let mut engine =
                                Receiver::with_flow_control(0, true).map_err(protocol_error)?;
                            engine.set_manual_file_accept(true);
                            let now = Instant::now();
                            self.state = TransferState::Receiving(ReceiveTransfer {
                                id,
                                owner_session_id: self.owner_session_id,
                                engine: Box::new(engine),
                                wire,
                                wire_offset: 0,
                                destination: None,
                                current_offer: None,
                                current_file: None,
                                preparation: None,
                                publication: None,
                                publication_failure: None,
                                publication_transport_closed: None,
                                offered_files: 0,
                                completed_files: 0,
                                transferred_bytes: 0,
                                last_progress: now,
                                last_activity: now,
                                progress_deadline: now + TRANSFER_IDLE_TIMEOUT,
                                protocol_retry_at: now + PROTOCOL_RETRY_INTERVAL,
                                authorization_deadline: now + AUTHORIZATION_TIMEOUT,
                                session_completed: false,
                                commit_cancellation: self.operation_epoch.as_ref().map(|epoch| {
                                    ReceiveCommitCancellation {
                                        operation_epoch: Arc::clone(epoch),
                                        expected_epoch: epoch.load(Ordering::Acquire),
                                        publish_phase: Arc::clone(
                                            self.receive_commit_phase
                                                .as_ref()
                                                .expect("session manager has a commit phase"),
                                        ),
                                        publish_started_at: Arc::clone(
                                            self.receive_publish_started_at
                                                .as_ref()
                                                .expect("session manager has a publish timestamp"),
                                        ),
                                    }
                                }),
                            });
                            if let Err(error) = self.drive(writer, &mut effects, true) {
                                self.failure_passthrough = std::mem::take(&mut effects.passthrough);
                                return Err(error);
                            }
                        }
                        ZmodemDirection::Send => {
                            let now = Instant::now();
                            self.state = TransferState::AwaitingSend(AwaitingSend {
                                id,
                                wire,
                                last_activity: now,
                                authorization_deadline: now + AUTHORIZATION_TIMEOUT,
                            });
                        }
                    }
                } else {
                    flush_scanner_prefix(held, &mut effects.passthrough);
                    *held_since = (!held.is_empty()).then(Instant::now);
                }
            }
            TransferState::Receiving(transfer) => {
                if transfer.publication_failure.is_some() {
                    // A protocol failure that races a durable publication is
                    // quarantined until the worker result is reaped. Further
                    // peer bytes are opaque drain payload and must neither
                    // overflow the old engine buffer nor reach the terminal.
                } else {
                    if !bytes.is_empty() {
                        let now = Instant::now();
                        transfer.last_activity = now;
                        // A legal 4 KiB/8 KiB subpacket may arrive in small PTY
                        // reads over more than one retry interval. Raw transport
                        // activity postpones only the short protocol retry; the
                        // independent hard progress deadline remains fixed.
                        // Once local ZFIN has been sent, unconsumed bytes are
                        // terminal output held for later passthrough, not proof
                        // that the optional peer OO handshake is progressing.
                        // They must not postpone the bounded missing-OO fallback.
                        if !transfer.engine.is_waiting_final_oo() {
                            transfer.protocol_retry_at = now + PROTOCOL_RETRY_INTERVAL;
                        }
                    }
                    append_wire(&mut transfer.wire, bytes)?;
                }
            }
            TransferState::AwaitingSend(transfer) => {
                if !bytes.is_empty() {
                    transfer.last_activity = Instant::now();
                }
                append_wire(&mut transfer.wire, bytes)?;
            }
            TransferState::PreparingSend(transfer) => {
                if !bytes.is_empty() {
                    transfer.protocol_retry_at = Instant::now() + PROTOCOL_RETRY_INTERVAL;
                }
                append_wire(&mut transfer.wire, bytes)?;
            }
            TransferState::Sending(transfer) => {
                if !bytes.is_empty() {
                    let now = Instant::now();
                    transfer.last_activity = now;
                    transfer.protocol_retry_at = now + PROTOCOL_RETRY_INTERVAL;
                }
                append_wire(&mut transfer.wire, bytes)?;
                self.drive(writer, &mut effects, true)?;
            }
            TransferState::Draining(transfer) => {
                if !bytes.is_empty() && !transfer.hard_terminated {
                    transfer.last_activity = Instant::now();
                }
                // An aborted protocol stream is opaque until a quiet or hard
                // drain boundary. Never let its residual payload reach the VT
                // parser, scrollback, transcript, or recorder.
            }
        }
        if matches!(self.state, TransferState::Receiving(_)) && !effects.receive_publish_pending {
            self.finish_receive_preparation(writer, &mut effects)?;
            self.drive(writer, &mut effects, true)?;
            self.finish_receive_preparation(writer, &mut effects)?;
        }
        if matches!(self.state, TransferState::PreparingSend(_)) {
            self.drive_send_preparation_protocol(writer)?;
            self.finish_send_preparation(writer, &mut effects)?;
        }
        Ok(effects)
    }

    pub fn take_failure_passthrough(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.failure_passthrough)
    }

    pub fn accept_receive(
        &mut self,
        transfer_id: u64,
        destination: &Path,
        _writer: &mut dyn Write,
    ) -> Result<ZmodemEffects, ZmodemError> {
        if !cfg!(any(target_os = "macos", target_os = "linux")) {
            return Err(ZmodemError::UnsupportedPlatform);
        }
        let TransferState::Receiving(transfer) = &mut self.state else {
            return Err(ZmodemError::InvalidState);
        };
        if transfer.id != transfer_id {
            return Err(ZmodemError::StaleTransfer);
        }
        if Instant::now() >= transfer.authorization_deadline {
            return Err(ZmodemError::Timeout);
        }
        if transfer.destination.is_some()
            || transfer.current_file.is_some()
            || transfer.preparation.is_some()
            || transfer.publication.is_some()
        {
            return Err(ZmodemError::InvalidState);
        }
        let (name, size, modification_time) = transfer
            .current_offer
            .clone()
            .ok_or(ZmodemError::InvalidState)?;
        if !destination.is_absolute() {
            return Err(ZmodemError::InvalidDestination);
        }
        let preparation = start_receive_preparation(
            transfer.id,
            transfer.owner_session_id,
            ReceivePreparationDestination::Path(destination.to_path_buf()),
            name,
            size,
            modification_time,
        )?;
        transfer.preparation = Some(preparation);
        let now = Instant::now();
        transfer.last_activity = now;
        transfer.progress_deadline = now + TRANSFER_IDLE_TIMEOUT;
        transfer.protocol_retry_at = now + PROTOCOL_RETRY_INTERVAL;
        let mut effects = ZmodemEffects::default();
        effects.events.push(started_event(
            transfer.id,
            ZmodemDirection::Receive,
            None,
            None,
        ));
        Ok(effects)
    }

    fn finish_receive_preparation(
        &mut self,
        writer: &mut dyn Write,
        effects: &mut ZmodemEffects,
    ) -> Result<bool, ZmodemError> {
        let message = {
            let TransferState::Receiving(transfer) = &mut self.state else {
                return Ok(false);
            };
            let Some(preparation) = transfer.preparation.as_mut() else {
                return Ok(false);
            };
            match preparation.result.try_recv() {
                Ok(result) => result,
                Err(mpsc::TryRecvError::Empty) => return Ok(false),
                Err(mpsc::TryRecvError::Disconnected) => return Err(ZmodemError::Io),
            }
        };
        let progress_deadline = match &self.state {
            TransferState::Receiving(transfer) => transfer.progress_deadline,
            _ => return Err(ZmodemError::InvalidState),
        };
        if message.finished_at >= progress_deadline {
            return Err(ZmodemError::Timeout);
        }
        let mut preparation = {
            let TransferState::Receiving(transfer) = &mut self.state else {
                return Err(ZmodemError::InvalidState);
            };
            transfer
                .preparation
                .take()
                .ok_or(ZmodemError::InvalidState)?
        };
        let worker = preparation.worker.take().ok_or(ZmodemError::InvalidState)?;
        worker.join().map_err(|_| ZmodemError::Io)?;
        let mut prepared = message.result?;
        let pending_file = prepared.file.take().ok_or(ZmodemError::InvalidState)?;
        let TransferState::Receiving(transfer) = &mut self.state else {
            schedule_staging_cleanup(pending_file);
            return Err(ZmodemError::InvalidState);
        };
        if let Err(error) = transfer.engine.accept_file_at(0) {
            schedule_staging_cleanup(pending_file);
            return Err(protocol_error(error));
        }
        if let Some(destination) = prepared.destination.take() {
            transfer.destination = Some(destination);
        }
        transfer.current_file = Some(pending_file);
        let now = Instant::now();
        transfer.last_activity = now;
        transfer.progress_deadline = now + TRANSFER_IDLE_TIMEOUT;
        transfer.protocol_retry_at = now + PROTOCOL_RETRY_INTERVAL;
        self.drive(writer, effects, true)
            .map_err(active_drive_error)?;
        Ok(true)
    }

    pub fn accept_send(
        &mut self,
        transfer_id: u64,
        paths: &[PathBuf],
        writer: &mut dyn Write,
    ) -> Result<ZmodemEffects, ZmodemError> {
        if !cfg!(any(target_os = "macos", target_os = "linux")) {
            return Err(ZmodemError::UnsupportedPlatform);
        }
        let TransferState::AwaitingSend(awaiting) = &self.state else {
            return Err(ZmodemError::InvalidState);
        };
        if awaiting.id != transfer_id {
            return Err(ZmodemError::StaleTransfer);
        }
        if Instant::now() >= awaiting.authorization_deadline {
            return Err(ZmodemError::Timeout);
        }
        if paths.is_empty()
            || paths.len() > MAX_FILES_PER_BATCH
            || paths.iter().any(|path| !path.is_absolute())
        {
            return Err(ZmodemError::InvalidSourceFiles);
        }
        #[cfg(test)]
        let test_worker_permit = TestSnapshotWorkerPermit::acquire();
        let worker_permit = SnapshotWorkerPermit::acquire().ok_or(ZmodemError::ResourceLimit)?;
        let file_count = paths.len();
        let mut engine = Sender::new().map_err(protocol_error)?;
        engine.set_streaming_window(SEND_ACK_WINDOW_SUBPACKETS);
        let id = awaiting.id;
        let wire = awaiting.wire.clone();
        let cancel = Arc::new(AtomicBool::new(false));
        let worker_cancel = Arc::clone(&cancel);
        let (result_tx, result_rx) = mpsc::channel();
        let worker_paths = paths.to_vec();
        let worker = std::thread::Builder::new()
            .name(format!("zmodem-snapshot-{id}"))
            .spawn(move || {
                let _worker_permit = worker_permit;
                #[cfg(test)]
                let _test_worker_permit = test_worker_permit;
                let progress_tx = result_tx.clone();
                let result = (|| {
                    let (reserved_files, reserved_bytes) = preflight_send_sources(&worker_paths)?;
                    let reserved_fds = reserved_files
                        .checked_mul(2)
                        .ok_or(ZmodemError::ResourceLimit)?;
                    let snapshot_resources = snapshot_resource_pool()
                        .acquire(reserved_files, reserved_bytes, reserved_fds)
                        .ok_or(ZmodemError::ResourceLimit)?;
                    let (sources, total_bytes) = open_send_sources(&worker_paths)?;
                    if total_bytes != reserved_bytes {
                        return Err(ZmodemError::InvalidSourceFiles);
                    }
                    let files = snapshot_send_sources(sources, &worker_cancel, |bytes| {
                        let _ = progress_tx.send(SnapshotMessage::Progress {
                            bytes,
                            at: Instant::now(),
                        });
                    })?;
                    Ok(PreparedSend {
                        files,
                        total_bytes,
                        snapshot_resources,
                    })
                })();
                let _ = result_tx.send(SnapshotMessage::Finished {
                    result,
                    at: Instant::now(),
                });
            })
            .map_err(|_| ZmodemError::Io)?;
        let now = Instant::now();
        self.state = TransferState::PreparingSend(PreparingSend {
            id,
            engine: Some(engine),
            wire,
            wire_offset: 0,
            result: result_rx,
            worker: Some(worker),
            cancel,
            snapshot_bytes: 0,
            progress_deadline: now + TRANSFER_IDLE_TIMEOUT,
            protocol_retry_at: now + PROTOCOL_RETRY_INTERVAL,
        });
        let mut effects = ZmodemEffects::default();
        effects.events.push(started_event(
            id,
            ZmodemDirection::Send,
            Some(file_count),
            None,
        ));
        self.drive_send_preparation_protocol(writer)?;
        Ok(effects)
    }

    fn drive_send_preparation_protocol(
        &mut self,
        writer: &mut dyn Write,
    ) -> Result<(), ZmodemError> {
        for _ in 0..65_536 {
            let TransferState::PreparingSend(preparing) = &mut self.state else {
                return Ok(());
            };
            let engine = preparing.engine.as_mut().ok_or(ZmodemError::InvalidState)?;
            match engine.poll() {
                Action::WriteWire(bytes) => {
                    writer.write_all(bytes).map_err(|_| ZmodemError::Io)?;
                    let len = bytes.len();
                    engine.wire_written(len);
                }
                Action::Event(Event::Aborted) => {
                    return Err(ZmodemError::Protocol("peer aborted".to_string()));
                }
                Action::Event(_) => {}
                Action::Idle => {
                    if preparing.wire_offset >= preparing.wire.len() {
                        preparing.wire.clear();
                        preparing.wire_offset = 0;
                        return Ok(());
                    }
                    let peer_progress_before = engine.peer_progress_epoch();
                    let consumed = engine
                        .submit_wire(&preparing.wire[preparing.wire_offset..])
                        .map_err(protocol_error)?;
                    if engine.peer_progress_epoch() != peer_progress_before {
                        let now = Instant::now();
                        preparing.progress_deadline = now + TRANSFER_IDLE_TIMEOUT;
                        preparing.protocol_retry_at = now + PROTOCOL_RETRY_INTERVAL;
                    }
                    preparing.wire_offset = preparing.wire_offset.saturating_add(consumed);
                    compact_wire(&mut preparing.wire, &mut preparing.wire_offset);
                    if consumed == 0 {
                        return Ok(());
                    }
                }
                Action::ReadFile { .. } => return Ok(()),
                Action::WriteFile(_) => return Err(ZmodemError::InvalidState),
                _ => return Ok(()),
            }
        }
        Err(ZmodemError::Protocol(
            "send preparation protocol pump exceeded its work budget".to_string(),
        ))
    }

    fn finish_send_preparation(
        &mut self,
        writer: &mut dyn Write,
        effects: &mut ZmodemEffects,
    ) -> Result<(), ZmodemError> {
        let TransferState::PreparingSend(preparing) = &mut self.state else {
            return Ok(());
        };
        let result = loop {
            match preparing.result.try_recv() {
                Ok(SnapshotMessage::Progress { bytes, at }) => {
                    if bytes > preparing.snapshot_bytes {
                        if at >= preparing.progress_deadline {
                            return Err(ZmodemError::Timeout);
                        }
                        preparing.snapshot_bytes = bytes;
                        preparing.progress_deadline = at + TRANSFER_IDLE_TIMEOUT;
                    }
                }
                Ok(SnapshotMessage::Finished { result, at }) => {
                    if at >= preparing.progress_deadline {
                        return Err(ZmodemError::Timeout);
                    }
                    break result;
                }
                Err(mpsc::TryRecvError::Empty) => return Ok(()),
                Err(mpsc::TryRecvError::Disconnected) => return Err(ZmodemError::Io),
            }
        };
        let worker = preparing.worker.take().ok_or(ZmodemError::InvalidState)?;
        worker.join().map_err(|_| ZmodemError::Io)?;
        let PreparedSend {
            mut files,
            total_bytes,
            snapshot_resources,
        } = result?;
        let current = files.pop_front().ok_or(ZmodemError::InvalidSourceFiles)?;
        let mut engine = preparing.engine.take().ok_or(ZmodemError::InvalidState)?;
        engine
            .start_file(send_file_info(&current))
            .map_err(protocol_error)?;
        let now = Instant::now();
        let id = preparing.id;
        let wire = std::mem::take(&mut preparing.wire);
        let wire_offset = preparing.wire_offset;
        preparing.cancel.store(true, Ordering::Release);
        self.state = TransferState::Sending(SendTransfer {
            id,
            engine,
            wire,
            wire_offset,
            files,
            current: Some(current),
            completed_bytes: 0,
            current_position: 0,
            total_bytes,
            completed_files: 0,
            skipped_files: 0,
            last_progress: now,
            last_activity: now,
            progress_deadline: now + TRANSFER_IDLE_TIMEOUT,
            protocol_retry_at: now + PROTOCOL_RETRY_INTERVAL,
            session_completed: false,
            _snapshot_resources: snapshot_resources,
        });
        self.drive(writer, effects, true)
            .map_err(active_drive_error)
    }

    pub fn cancel(
        &mut self,
        transfer_id: u64,
        writer: &mut dyn Write,
    ) -> Result<ZmodemEffects, ZmodemError> {
        let active_id = self.active_id().ok_or(ZmodemError::InvalidState)?;
        if active_id != transfer_id {
            return Err(ZmodemError::StaleTransfer);
        }
        let _ = writer.write_all(CANCEL_BYTES);
        self.cleanup_partial();
        self.state = draining_state(
            ZmodemEvent::new(
                "zmodem_cancelled",
                serde_json::json!({
                    "source": "zmodem",
                    "transferId": transfer_id.to_string(),
                }),
            ),
            false,
        );
        Ok(ZmodemEffects::default())
    }

    pub(crate) fn receiver_waiting_final_oo(&self) -> bool {
        matches!(
            &self.state,
            TransferState::Receiving(transfer) if transfer.engine.is_waiting_final_oo()
        )
    }

    pub fn fail(&mut self, error: &ZmodemError, writer: Option<&mut dyn Write>) -> ZmodemEffects {
        let Some(transfer_id) = self.active_id() else {
            return ZmodemEffects::default();
        };
        let direction = match self.state {
            TransferState::Receiving(_) => ZmodemDirection::Receive,
            TransferState::AwaitingSend(_)
            | TransferState::PreparingSend(_)
            | TransferState::Sending(_) => ZmodemDirection::Send,
            TransferState::Scanning { .. } | TransferState::Draining(_) => unreachable!(),
        };
        if let Some(writer) = writer {
            let _ = writer.write_all(CANCEL_BYTES);
        }
        if direction == ZmodemDirection::Receive
            && let TransferState::Receiving(transfer) = &mut self.state
            && transfer.publication.is_some()
        {
            // The worker owns a complete file and its recovery authority.
            // Quarantine the protocol failure, but keep the receiver/worker
            // handle reachable until its result has been linearized and
            // published. Dropping it here would let a detached worker create
            // a final file or token that no session event can describe.
            transfer
                .publication_failure
                .get_or_insert_with(|| failed_event(transfer_id, direction, error));
            transfer.wire.clear();
            transfer.wire_offset = 0;
            return ZmodemEffects::default();
        }
        self.cleanup_partial();
        let receive_publish_pending = direction == ZmodemDirection::Receive
            && self.receive_commit_phase.as_ref().is_some_and(|phase| {
                matches!(
                    phase.load(Ordering::Acquire),
                    RECEIVE_COMMIT_PUBLISHING | RECEIVE_COMMIT_RESULT_READY
                )
            });
        self.state = draining_state(
            failed_event(transfer_id, direction, error),
            receive_publish_pending,
        );
        ZmodemEffects::default()
    }

    pub fn timeout_if_needed(
        &mut self,
        now: Instant,
        mut writer: Option<&mut dyn Write>,
    ) -> Option<ZmodemEffects> {
        if let TransferState::Scanning {
            held,
            held_since: Some(held_since),
        } = &mut self.state
            && !held.is_empty()
            && now.duration_since(*held_since) >= SCANNER_HOLD_TIMEOUT
        {
            return Some(ZmodemEffects {
                passthrough: std::mem::take(held),
                events: Vec::new(),
                terminate_transport: false,
                receive_publish_pending: false,
            });
        }
        if let TransferState::Draining(transfer) = &mut self.state {
            if transfer.hard_terminated {
                return None;
            }
            if now >= transfer.hard_deadline {
                transfer.hard_terminated = true;
                return Some(ZmodemEffects {
                    passthrough: Vec::new(),
                    events: transfer.terminal_event.take().into_iter().collect(),
                    terminate_transport: true,
                    receive_publish_pending: transfer.receive_publish_pending,
                });
            }
            let quiet = now.duration_since(transfer.last_activity) >= DRAIN_QUIET_TIMEOUT;
            if quiet {
                let TransferState::Draining(transfer) =
                    std::mem::replace(&mut self.state, scanning_state())
                else {
                    unreachable!()
                };
                return Some(ZmodemEffects {
                    passthrough: Vec::new(),
                    events: transfer.terminal_event.into_iter().collect(),
                    terminate_transport: false,
                    receive_publish_pending: transfer.receive_publish_pending,
                });
            }
            return None;
        }

        if matches!(
            &self.state,
            TransferState::Receiving(transfer) if transfer.preparation.is_some()
        ) {
            let Some(preparation_writer) = writer.as_deref_mut() else {
                return Some(self.fail(&ZmodemError::Io, None));
            };
            let mut effects = ZmodemEffects::default();
            match self.finish_receive_preparation(preparation_writer, &mut effects) {
                Ok(true) => return Some(effects),
                Ok(false) => {}
                Err(error) => {
                    let failure = self.fail(&error, Some(preparation_writer));
                    effects.events.extend(failure.events);
                    effects.terminate_transport |= failure.terminate_transport;
                    return Some(effects);
                }
            }
        }

        if matches!(self.state, TransferState::PreparingSend(_)) {
            let Some(writer) = writer else {
                return Some(self.fail(&ZmodemError::Io, None));
            };
            let mut effects = ZmodemEffects::default();
            if let Err(error) = self.finish_send_preparation(writer, &mut effects) {
                let failure = self.fail(&error, Some(writer));
                effects.events.extend(failure.events);
                effects.terminate_transport |= failure.terminate_transport;
                return Some(effects);
            }
            let TransferState::PreparingSend(preparing) = &mut self.state else {
                return Some(effects);
            };
            if now >= preparing.progress_deadline {
                return Some(self.fail(&ZmodemError::Timeout, Some(writer)));
            }
            if now < preparing.protocol_retry_at {
                return None;
            }
            preparing.protocol_retry_at = now + PROTOCOL_RETRY_INTERVAL;
            if let Err(error) = preparing
                .engine
                .as_mut()
                .ok_or(ZmodemError::InvalidState)
                .and_then(|engine| engine.timeout().map_err(protocol_error))
            {
                return Some(self.fail(&error, Some(writer)));
            }
            if let Err(error) = self.drive_send_preparation_protocol(writer) {
                return Some(self.fail(&error, Some(writer)));
            }
            return Some(effects);
        }

        if matches!(
            &self.state,
            TransferState::Receiving(transfer) if transfer.publication.is_some()
        ) {
            // Publication owns stable file/directory descriptors and can
            // finish without a live PTY. If the SSH transport disappeared
            // while the filesystem worker was in flight, keep polling it
            // through a sink so its durable result is published before the
            // deferred transport failure releases the receive phase.
            let mut sink = std::io::sink();
            let publication_writer: &mut dyn Write = match writer.as_deref_mut() {
                Some(writer) => writer,
                None => &mut sink,
            };
            let mut effects = ZmodemEffects::default();
            match self.drive(publication_writer, &mut effects, true) {
                Ok(()) if effects.events.is_empty() => return None,
                Ok(()) => return Some(effects),
                Err(error) => {
                    let failure = self.fail(&error, Some(publication_writer));
                    effects.events.extend(failure.events);
                    effects.terminate_transport |= failure.terminate_transport;
                    effects.receive_publish_pending |= failure.receive_publish_pending;
                    return Some(effects);
                }
            }
        }

        let timed_out = match &self.state {
            TransferState::Scanning { .. } => return None,
            TransferState::AwaitingSend(transfer) => now >= transfer.authorization_deadline,
            TransferState::Receiving(transfer) if transfer.preparation.is_some() => {
                now >= transfer.progress_deadline
            }
            TransferState::Receiving(transfer) if transfer.destination.is_none() => {
                now >= transfer.authorization_deadline
            }
            TransferState::Receiving(transfer) => now >= transfer.progress_deadline,
            TransferState::Sending(transfer) => now >= transfer.progress_deadline,
            TransferState::PreparingSend(_) => unreachable!(),
            TransferState::Draining(_) => unreachable!(),
        };
        if !timed_out {
            let protocol_retry_due = match &self.state {
                TransferState::Receiving(transfer) => now >= transfer.protocol_retry_at,
                TransferState::Sending(transfer) => now >= transfer.protocol_retry_at,
                TransferState::PreparingSend(_) => unreachable!(),
                TransferState::AwaitingSend(_) => false,
                TransferState::Scanning { .. } | TransferState::Draining(_) => unreachable!(),
            };
            if !protocol_retry_due {
                return None;
            }

            let Some(writer) = writer else {
                return Some(self.fail(&ZmodemError::Io, None));
            };
            let retry_result = match &mut self.state {
                TransferState::Receiving(transfer) => {
                    transfer.protocol_retry_at = now + PROTOCOL_RETRY_INTERVAL;
                    transfer.engine.timeout().map_err(protocol_error)
                }
                TransferState::Sending(transfer) => {
                    transfer.protocol_retry_at = now + PROTOCOL_RETRY_INTERVAL;
                    transfer.engine.timeout().map_err(protocol_error)
                }
                _ => unreachable!(),
            };
            let mut effects = ZmodemEffects::default();
            let result = retry_result.and_then(|()| self.drive(writer, &mut effects, false));
            if let Err(error) = result {
                let failure = self.fail(&error, Some(writer));
                effects.events.extend(failure.events);
                effects.terminate_transport |= failure.terminate_transport;
            }
            return Some(effects);
        }
        Some(self.fail(&ZmodemError::Timeout, writer))
    }

    /// Resolves an active transfer when the PTY reader reaches its transport
    /// boundary. A trustworthy EOF can stand in for the sender's final `OO`
    /// only after the receiver has replied with `ZFIN`; every other active
    /// state fails immediately because no opaque protocol bytes can follow.
    pub fn transport_closed(&mut self, trusted_eof: bool) -> ZmodemEffects {
        if matches!(self.state, TransferState::Scanning { .. }) {
            let TransferState::Scanning { held, .. } =
                std::mem::replace(&mut self.state, scanning_state())
            else {
                unreachable!()
            };
            return ZmodemEffects {
                passthrough: held,
                events: Vec::new(),
                terminate_transport: false,
                receive_publish_pending: false,
            };
        }
        if matches!(self.state, TransferState::Draining(_)) {
            if matches!(
                &self.state,
                TransferState::Draining(transfer) if transfer.hard_terminated
            ) {
                return ZmodemEffects::default();
            }
            let TransferState::Draining(transfer) =
                std::mem::replace(&mut self.state, scanning_state())
            else {
                unreachable!()
            };
            return ZmodemEffects {
                passthrough: Vec::new(),
                events: transfer.terminal_event.into_iter().collect(),
                terminate_transport: false,
                receive_publish_pending: transfer.receive_publish_pending,
            };
        }

        if let TransferState::Receiving(transfer) = &mut self.state
            && transfer.publication.is_some()
        {
            // The filesystem publication has independent, bounded ownership.
            // Do not drop that worker (and its recovery authority) merely
            // because SSH ended. Its result is polled by timeout_if_needed;
            // drive_receiver then reports the file result before converting
            // this deferred boundary into the terminal transfer failure.
            transfer
                .publication_transport_closed
                .get_or_insert(trusted_eof);
            return ZmodemEffects::default();
        }

        if trusted_eof
            && let TransferState::Receiving(transfer) = &mut self.state
            && transfer.engine.is_waiting_final_oo()
            && transfer.current_file.is_none()
            && transfer.engine.transport_closed().is_ok()
        {
            let mut effects = ZmodemEffects::default();
            let mut sink = std::io::sink();
            if self.drive(&mut sink, &mut effects, true).is_ok()
                && matches!(self.state, TransferState::Scanning { .. })
            {
                return effects;
            }
        }

        let error = if trusted_eof {
            ZmodemError::Protocol("unexpected transport EOF".to_string())
        } else {
            ZmodemError::Io
        };
        self.fail_at_transport_boundary(&error)
    }

    pub fn reset(&mut self) {
        self.cleanup_partial();
        self.state = scanning_state();
    }

    #[cfg(test)]
    pub(crate) fn force_drain_hard_deadline_for_test(&mut self, deadline: Instant) {
        let TransferState::Draining(transfer) = &mut self.state else {
            panic!("test helper requires a draining transfer")
        };
        transfer.hard_deadline = deadline;
    }

    fn drive(
        &mut self,
        writer: &mut dyn Write,
        effects: &mut ZmodemEffects,
        // Timeout retransmissions are local maintenance and must not extend
        // either the peer-idle deadline or the response-silence deadline.
        // CRC-valid peer protocol activity rearms the short response timer;
        // only file/phase progress can extend the hard no-progress deadline.
        refresh_activity: bool,
    ) -> Result<(), ZmodemError> {
        for _ in 0..65_536 {
            let peer_progress_before = match &self.state {
                TransferState::Receiving(transfer) => transfer.engine.peer_progress_epoch(),
                TransferState::Sending(transfer) => transfer.engine.peer_progress_epoch(),
                _ => 0,
            };
            let mut progress = match &mut self.state {
                TransferState::Receiving(transfer) => drive_receiver(transfer, writer, effects)?,
                TransferState::Sending(transfer) => drive_sender(transfer, writer, effects)?,
                _ => DriveProgress::Idle,
            };
            let peer_progress_after = match &self.state {
                TransferState::Receiving(transfer) => transfer.engine.peer_progress_epoch(),
                TransferState::Sending(transfer) => transfer.engine.peer_progress_epoch(),
                _ => peer_progress_before,
            };
            if peer_progress_after != peer_progress_before && progress != DriveProgress::Meaningful
            {
                progress = DriveProgress::Protocol;
            }
            if progress == DriveProgress::Idle {
                break;
            }
            if refresh_activity
                && matches!(
                    progress,
                    DriveProgress::Protocol | DriveProgress::Meaningful
                )
            {
                let now = Instant::now();
                match &mut self.state {
                    TransferState::Receiving(transfer) => {
                        transfer.last_activity = now;
                        if progress == DriveProgress::Meaningful {
                            transfer.progress_deadline = now + TRANSFER_IDLE_TIMEOUT;
                        }
                        transfer.protocol_retry_at = now + PROTOCOL_RETRY_INTERVAL;
                    }
                    TransferState::Sending(transfer) => {
                        transfer.last_activity = now;
                        if progress == DriveProgress::Meaningful {
                            transfer.progress_deadline = now + TRANSFER_IDLE_TIMEOUT;
                        }
                        transfer.protocol_retry_at = now + PROTOCOL_RETRY_INTERVAL;
                    }
                    _ => {}
                }
            }
            if effects.receive_publish_pending {
                // The receive publication guard is retained until the
                // session queues the matching completion event. Yield after
                // one committed file instead of trying to claim the shared
                // publish phase again in this drive pass.
                break;
            }
            if matches!(
                &self.state,
                TransferState::Receiving(transfer) if transfer.session_completed
            ) {
                // A terminal protocol event is a hard consumption boundary.
                // Bytes left in the same PTY chunk belong to the shell or
                // next application protocol and must be reclassified by the
                // scanner after this engine reaches its terminal state.
                break;
            }
        }

        let publication_failure = match &mut self.state {
            TransferState::Receiving(transfer)
                if effects.receive_publish_pending && transfer.publication.is_none() =>
            {
                transfer.publication_failure.take()
            }
            _ => None,
        };
        if let Some(terminal_event) = publication_failure {
            // File completion/recovery is already in `effects` and therefore
            // precedes this quarantined failure. Keep the transport in drain
            // until its quiet boundary publishes the terminal failure.
            self.state = draining_state(terminal_event, true);
            return Ok(());
        }

        let completed = match &mut self.state {
            TransferState::Receiving(transfer) => {
                transfer.session_completed
                    && transfer.current_file.is_none()
                    && transfer.publication.is_none()
                    && matches!(transfer.engine.poll(), Action::Idle)
            }
            TransferState::Sending(transfer) => {
                transfer.session_completed && matches!(transfer.engine.poll(), Action::Idle)
            }
            _ => false,
        };
        if completed {
            let (id, direction, remaining, completed_files, skipped_files) = match &mut self.state {
                TransferState::Receiving(transfer) => (
                    transfer.id,
                    ZmodemDirection::Receive,
                    take_unconsumed_wire(&transfer.wire, transfer.wire_offset),
                    transfer.completed_files,
                    0,
                ),
                TransferState::Sending(transfer) => (
                    transfer.id,
                    ZmodemDirection::Send,
                    take_unconsumed_wire(&transfer.wire, transfer.wire_offset),
                    transfer.completed_files,
                    transfer.skipped_files,
                ),
                _ => unreachable!(),
            };
            effects.events.push(completed_event(
                id,
                direction,
                completed_files,
                skipped_files,
            ));
            self.state = scanning_state();
            if !remaining.is_empty() {
                match self.ingest(&remaining, writer) {
                    Ok(next) => {
                        effects.passthrough.extend(next.passthrough);
                        effects.events.extend(next.events);
                        effects.terminate_transport |= next.terminate_transport;
                        effects.receive_publish_pending |= next.receive_publish_pending;
                    }
                    Err(error) => {
                        let mut safe = std::mem::take(&mut effects.passthrough);
                        safe.extend(self.take_failure_passthrough());
                        self.failure_passthrough = safe;
                        return Err(error);
                    }
                }
            }
        }
        Ok(())
    }

    fn active_id(&self) -> Option<u64> {
        match &self.state {
            TransferState::Scanning { .. } => None,
            TransferState::Receiving(transfer) => Some(transfer.id),
            TransferState::AwaitingSend(transfer) => Some(transfer.id),
            TransferState::PreparingSend(transfer) => Some(transfer.id),
            TransferState::Sending(transfer) => Some(transfer.id),
            TransferState::Draining(_) => None,
        }
    }

    fn allocate_id(&mut self) -> u64 {
        let id = self.next_id.max(1);
        self.next_id = id.checked_add(1).unwrap_or(1);
        id
    }

    fn cleanup_partial(&mut self) {
        if let TransferState::Receiving(transfer) = &mut self.state
            && let Some(file) = transfer.current_file.take()
        {
            // Closing or unlinking a staging file can block indefinitely on
            // network filesystems. Transfer cancellation must release the
            // session transport/state locks first, so a single process-wide
            // worker owns cleanup. The staging-file permit globally bounds
            // both active files and queued cleanup work.
            schedule_staging_cleanup(file);
        }
    }

    fn fail_at_transport_boundary(&mut self, error: &ZmodemError) -> ZmodemEffects {
        let (transfer_id, direction) = match &self.state {
            TransferState::Receiving(transfer) => (transfer.id, ZmodemDirection::Receive),
            TransferState::AwaitingSend(transfer) => (transfer.id, ZmodemDirection::Send),
            TransferState::PreparingSend(transfer) => (transfer.id, ZmodemDirection::Send),
            TransferState::Sending(transfer) => (transfer.id, ZmodemDirection::Send),
            TransferState::Scanning { .. } | TransferState::Draining(_) => {
                return ZmodemEffects::default();
            }
        };
        self.cleanup_partial();
        self.state = scanning_state();
        ZmodemEffects {
            passthrough: Vec::new(),
            events: vec![failed_event(transfer_id, direction, error)],
            terminate_transport: false,
            receive_publish_pending: false,
        }
    }
}

fn scanning_state() -> TransferState {
    TransferState::Scanning {
        held: Vec::new(),
        held_since: None,
    }
}

fn draining_state(terminal_event: ZmodemEvent, receive_publish_pending: bool) -> TransferState {
    let now = Instant::now();
    TransferState::Draining(DrainingTransfer {
        last_activity: now,
        hard_deadline: now + DRAIN_HARD_TIMEOUT,
        terminal_event: Some(terminal_event),
        hard_terminated: false,
        receive_publish_pending,
    })
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum DriveProgress {
    Idle,
    Maintenance,
    Protocol,
    Meaningful,
}

impl Drop for ZmodemManager {
    fn drop(&mut self) {
        self.cleanup_partial();
    }
}

fn drive_receiver(
    transfer: &mut ReceiveTransfer,
    writer: &mut dyn Write,
    effects: &mut ZmodemEffects,
) -> Result<DriveProgress, ZmodemError> {
    if transfer.publication.is_some() {
        let message = {
            let publication = transfer
                .publication
                .as_mut()
                .ok_or(ZmodemError::InvalidState)?;
            match publication.result.try_recv() {
                Ok(message) => message,
                Err(mpsc::TryRecvError::Empty) => return Ok(DriveProgress::Idle),
                Err(mpsc::TryRecvError::Disconnected) => return Err(ZmodemError::Io),
            }
        };
        let mut publication = transfer
            .publication
            .take()
            .ok_or(ZmodemError::InvalidState)?;
        let worker = publication.worker.take().ok_or(ZmodemError::InvalidState)?;
        worker.join().map_err(|_| ZmodemError::Io)?;
        let name = message.result?;
        transfer.completed_files = transfer.completed_files.saturating_add(1);
        transfer.current_offer = None;
        transfer.last_activity = message.finished_at;
        effects.receive_publish_pending = true;
        effects.events.push(ZmodemEvent::new(
            "zmodem_file_completed",
            serde_json::json!({
                "source": "zmodem",
                "transferId": transfer.id.to_string(),
                "direction": "receive",
                "filename": name,
                "size": message.size,
                "completedFiles": transfer.completed_files,
            }),
        ));
        if let Some(trusted_eof) = transfer.publication_transport_closed.take() {
            let error = if trusted_eof {
                ZmodemError::Protocol("unexpected transport EOF".to_string())
            } else {
                ZmodemError::Io
            };
            // The durable file-completion event was already appended to this
            // effect batch. Quarantine the deferred transport failure so the
            // outer drive loop can publish completion first, then enter the
            // opaque drain state. Returning Err here would make the ordinary
            // ingest path discard the partially-built effect batch.
            transfer
                .publication_failure
                .get_or_insert_with(|| failed_event(transfer.id, ZmodemDirection::Receive, &error));
        }
        return Ok(DriveProgress::Meaningful);
    }
    match transfer.engine.poll() {
        Action::WriteWire(bytes) => {
            writer.write_all(bytes).map_err(|_| ZmodemError::Io)?;
            let len = bytes.len();
            transfer.engine.wire_written(len);
            Ok(DriveProgress::Maintenance)
        }
        Action::WriteFile(bytes) => {
            let file = transfer
                .current_file
                .as_mut()
                .ok_or(ZmodemError::InvalidState)?;
            let next_file_bytes = file
                .written
                .checked_add(bytes.len() as u64)
                .filter(|value| *value <= MAX_FILE_BYTES)
                .ok_or(ZmodemError::InvalidDestination)?;
            let next_batch_bytes = transfer
                .transferred_bytes
                .checked_add(bytes.len() as u64)
                .filter(|value| *value <= MAX_BATCH_BYTES)
                .ok_or(ZmodemError::InvalidDestination)?;
            file._resource_lease.reserve_bytes(bytes.len() as u64)?;
            file.file.write_all(bytes).map_err(|_| ZmodemError::Io)?;
            let len = bytes.len();
            file.written = next_file_bytes;
            transfer.transferred_bytes = next_batch_bytes;
            transfer.engine.file_written(len).map_err(protocol_error)?;
            let progress_total = file
                .expected_size
                .map(u64::from)
                .filter(|total| *total >= file.written);
            maybe_progress(
                transfer.id,
                ZmodemDirection::Receive,
                file.written,
                progress_total,
                &mut transfer.last_progress,
                effects,
            );
            Ok(DriveProgress::Meaningful)
        }
        Action::Event(event) => {
            match event {
                Event::FileStarted(info) => {
                    let raw_name = info.name.to_vec();
                    let size = info.size.map(Position::get);
                    let modification_time = info.modification_time;
                    handle_receive_file_started(
                        transfer,
                        &raw_name,
                        size,
                        modification_time,
                        effects,
                    )?;
                }
                Event::FileCompleted => {
                    let file = transfer
                        .current_file
                        .take()
                        .ok_or(ZmodemError::InvalidState)?;
                    if let Some(cancellation) = transfer.commit_cancellation.clone() {
                        transfer.publication =
                            Some(start_receive_publication(transfer.id, file, cancellation)?);
                    } else {
                        let size = file.written;
                        let name = commit_receive_file(file, None)?;
                        transfer.completed_files = transfer.completed_files.saturating_add(1);
                        transfer.current_offer = None;
                        effects.events.push(ZmodemEvent::new(
                            "zmodem_file_completed",
                            serde_json::json!({
                                "source": "zmodem",
                                "transferId": transfer.id.to_string(),
                                "direction": "receive",
                                "filename": name,
                                "size": size,
                                "completedFiles": transfer.completed_files,
                            }),
                        ));
                    }
                }
                Event::SessionCompleted => transfer.session_completed = true,
                Event::Aborted => return Err(ZmodemError::Protocol("peer aborted".to_string())),
                _ => {}
            }
            Ok(DriveProgress::Meaningful)
        }
        Action::Idle => {
            if transfer.wire_offset >= transfer.wire.len() {
                transfer.wire.clear();
                transfer.wire_offset = 0;
                return Ok(DriveProgress::Idle);
            }
            let consumed = transfer
                .engine
                .submit_wire(&transfer.wire[transfer.wire_offset..])
                .map_err(protocol_error)?;
            transfer.wire_offset = transfer.wire_offset.saturating_add(consumed);
            compact_wire(&mut transfer.wire, &mut transfer.wire_offset);
            Ok(if consumed > 0 {
                DriveProgress::Maintenance
            } else {
                DriveProgress::Idle
            })
        }
        Action::ReadFile { .. } => Err(ZmodemError::InvalidState),
        _ => Ok(DriveProgress::Idle),
    }
}

fn handle_receive_file_started(
    transfer: &mut ReceiveTransfer,
    raw_name: &[u8],
    size: Option<u32>,
    modification_time: Option<u64>,
    effects: &mut ZmodemEffects,
) -> Result<(), ZmodemError> {
    let name = validated_received_name(raw_name)?;
    if transfer.preparation.is_some() || transfer.publication.is_some() {
        return Err(ZmodemError::Protocol(
            "peer announced a new file while destination preparation was active".to_string(),
        ));
    }
    if let Some(file) = transfer.current_file.take() {
        schedule_staging_cleanup(file);
        return Err(ZmodemError::Protocol(
            "peer announced a new file before completing the active file".to_string(),
        ));
    }
    if transfer.offered_files >= MAX_FILES_PER_BATCH {
        return Err(ZmodemError::InvalidDestination);
    }
    transfer.offered_files = transfer.offered_files.saturating_add(1);
    // GNU lrzsz can announce the size of a file that is still growing. Treat
    // ZFILE size as progress metadata, never as an authorization reservation
    // or an exact write limit; actual persisted bytes remain hard-bounded.
    if size.is_some_and(|size| u64::from(size) > MAX_FILE_BYTES) {
        return Err(ZmodemError::InvalidDestination);
    }
    transfer.current_offer = Some((name.clone(), size, modification_time));
    effects.events.push(ZmodemEvent::new(
        "zmodem_file_offer",
        serde_json::json!({
            "source": "zmodem",
            "transferId": transfer.id.to_string(),
            "direction": "receive",
            "filename": name,
            "size": size,
            "modificationTimeSeconds": modification_time,
        }),
    ));
    if let Some(destination) = transfer.destination.as_ref() {
        let preparation = start_receive_preparation(
            transfer.id,
            transfer.owner_session_id,
            ReceivePreparationDestination::Open(destination.try_clone()?),
            name,
            size,
            modification_time,
        )?;
        transfer.preparation = Some(preparation);
        let now = Instant::now();
        transfer.progress_deadline = now + TRANSFER_IDLE_TIMEOUT;
        transfer.protocol_retry_at = now + PROTOCOL_RETRY_INTERVAL;
    }
    Ok(())
}

fn drive_sender(
    transfer: &mut SendTransfer,
    writer: &mut dyn Write,
    effects: &mut ZmodemEffects,
) -> Result<DriveProgress, ZmodemError> {
    match transfer.engine.poll() {
        Action::WriteWire(bytes) => {
            writer.write_all(bytes).map_err(|_| ZmodemError::Io)?;
            let len = bytes.len();
            transfer.engine.wire_written(len);
            Ok(DriveProgress::Maintenance)
        }
        Action::ReadFile { offset, max_len } => {
            let file = transfer.current.as_mut().ok_or(ZmodemError::InvalidState)?;
            file.file
                .seek(SeekFrom::Start(u64::from(offset.get())))
                .map_err(|_| ZmodemError::Io)?;
            let remaining = usize::try_from(file.size.saturating_sub(offset.get()))
                .map_err(|_| ZmodemError::Io)?;
            let mut buffer = vec![0_u8; max_len.min(remaining)];
            if !buffer.is_empty() {
                file.file
                    .read_exact(&mut buffer)
                    .map_err(|_| ZmodemError::Io)?;
            }
            transfer
                .engine
                .submit_file(&buffer)
                .map_err(protocol_error)?;
            let position = u64::from(offset.get()).saturating_add(buffer.len() as u64);
            let previous_position = transfer.current_position;
            transfer.current_position = transfer.current_position.max(position);
            let transferred = transfer
                .completed_bytes
                .saturating_add(transfer.current_position);
            maybe_progress(
                transfer.id,
                ZmodemDirection::Send,
                transferred,
                Some(transfer.total_bytes),
                &mut transfer.last_progress,
                effects,
            );
            Ok(if transfer.current_position > previous_position {
                DriveProgress::Meaningful
            } else {
                // A valid rewind/retransmit is protocol maintenance. It must
                // not extend the hard no-progress deadline indefinitely.
                DriveProgress::Maintenance
            })
        }
        Action::Event(event) => {
            match event {
                Event::FileCompleted => {
                    let completed = transfer.current.take().ok_or(ZmodemError::InvalidState)?;
                    transfer.completed_bytes = transfer
                        .completed_bytes
                        .saturating_add(u64::from(completed.size));
                    transfer.current_position = 0;
                    transfer.completed_files = transfer.completed_files.saturating_add(1);
                    effects.events.push(ZmodemEvent::new(
                        "zmodem_file_completed",
                        serde_json::json!({
                            "source": "zmodem",
                            "transferId": transfer.id.to_string(),
                            "direction": "send",
                            "filename": completed.name,
                            "size": completed.size,
                            "completedFiles": transfer.completed_files,
                        }),
                    ));
                    if let Some(next) = transfer.files.pop_front() {
                        transfer
                            .engine
                            .start_file(send_file_info(&next))
                            .map_err(protocol_error)?;
                        transfer.current = Some(next);
                    } else {
                        transfer.engine.finish().map_err(protocol_error)?;
                    }
                }
                Event::SessionCompleted => transfer.session_completed = true,
                Event::Aborted => return Err(ZmodemError::Protocol("peer aborted".to_string())),
                Event::FileSkipped => handle_send_file_skipped(transfer, effects)?,
                Event::FileStarted(_) => {}
                _ => {}
            }
            Ok(DriveProgress::Meaningful)
        }
        Action::Idle => {
            if transfer.wire_offset >= transfer.wire.len() {
                transfer.wire.clear();
                transfer.wire_offset = 0;
                return Ok(DriveProgress::Idle);
            }
            let consumed = transfer
                .engine
                .submit_wire(&transfer.wire[transfer.wire_offset..])
                .map_err(protocol_error)?;
            transfer.wire_offset = transfer.wire_offset.saturating_add(consumed);
            compact_wire(&mut transfer.wire, &mut transfer.wire_offset);
            Ok(if consumed > 0 {
                DriveProgress::Maintenance
            } else {
                DriveProgress::Idle
            })
        }
        Action::WriteFile(_) => Err(ZmodemError::InvalidState),
        _ => Ok(DriveProgress::Idle),
    }
}

fn handle_send_file_skipped(
    transfer: &mut SendTransfer,
    effects: &mut ZmodemEffects,
) -> Result<(), ZmodemError> {
    let skipped = transfer.current.take().ok_or(ZmodemError::InvalidState)?;
    transfer.completed_bytes = transfer
        .completed_bytes
        .saturating_add(transfer.current_position);
    transfer.current_position = 0;
    transfer.skipped_files = transfer.skipped_files.saturating_add(1);
    effects.events.push(ZmodemEvent::new(
        "zmodem_file_skipped",
        serde_json::json!({
            "source": "zmodem",
            "transferId": transfer.id.to_string(),
            "direction": "send",
            "filename": skipped.name,
            "size": skipped.size,
            "completedFiles": transfer.completed_files,
            "skippedFiles": transfer.skipped_files,
        }),
    ));
    if let Some(next) = transfer.files.pop_front() {
        transfer
            .engine
            .start_file(send_file_info(&next))
            .map_err(protocol_error)?;
        transfer.current = Some(next);
    } else {
        transfer.engine.finish().map_err(protocol_error)?;
    }
    Ok(())
}

fn find_initial_header(bytes: &[u8]) -> Option<(usize, ZmodemDirection)> {
    for offset in 0..bytes.len() {
        if let InitialHeaderCandidate::Complete(direction) =
            parse_initial_header_candidate(&bytes[offset..])
        {
            return Some((offset, direction));
        }
    }
    None
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum InitialHeaderCandidate {
    Incomplete,
    Invalid,
    Complete(ZmodemDirection),
}

/// Parses one possible initial ZHEX header while ignoring in-band software
/// flow-control bytes. Serial/PTY relays are allowed to insert XON/XOFF (also
/// with mark parity) between header bytes; those bytes must remain in the
/// original wire slice passed to the protocol engine after detection.
fn parse_initial_header_candidate(bytes: &[u8]) -> InitialHeaderCandidate {
    if bytes.is_empty() {
        return InitialHeaderCandidate::Incomplete;
    }

    let mut prefix_offset = 0;
    let mut encoded = [0_u8; HEX_HEADER_ENCODED_BYTES];
    let mut encoded_offset = 0;
    let mut flow_bytes = 0;

    for (wire_offset, byte) in bytes.iter().copied().enumerate() {
        if wire_offset >= MAX_INITIAL_HEADER_CANDIDATE_BYTES {
            return InitialHeaderCandidate::Invalid;
        }
        if (prefix_offset != 0 || encoded_offset != 0) && is_flow_control(byte) {
            flow_bytes += 1;
            if flow_bytes > MAX_INITIAL_HEADER_FLOW_BYTES {
                return InitialHeaderCandidate::Invalid;
            }
            continue;
        }
        if prefix_offset < HEX_HEADER_PREFIX.len() {
            if byte & 0x7f != HEX_HEADER_PREFIX[prefix_offset] {
                return InitialHeaderCandidate::Invalid;
            }
            prefix_offset += 1;
            continue;
        }
        if !(byte & 0x7f).is_ascii_hexdigit() {
            return InitialHeaderCandidate::Invalid;
        }
        encoded[encoded_offset] = byte;
        encoded_offset += 1;
        if encoded_offset == encoded.len() {
            let Some(decoded) = decode_hex_header(&encoded) else {
                return InitialHeaderCandidate::Invalid;
            };
            return match decoded[0] {
                0 => InitialHeaderCandidate::Complete(ZmodemDirection::Receive),
                1 => InitialHeaderCandidate::Complete(ZmodemDirection::Send),
                _ => InitialHeaderCandidate::Invalid,
            };
        }
    }
    InitialHeaderCandidate::Incomplete
}

fn is_flow_control(byte: u8) -> bool {
    matches!(byte & 0x7f, 0x11 | 0x13)
}

fn decode_hex_header(encoded: &[u8]) -> Option<[u8; 7]> {
    if encoded.len() != HEX_HEADER_ENCODED_BYTES {
        return None;
    }
    let mut decoded = [0_u8; 7];
    for (index, chunk) in encoded.chunks_exact(2).enumerate() {
        decoded[index] = (hex_nibble(chunk[0] & 0x7f)? << 4) | hex_nibble(chunk[1] & 0x7f)?;
    }
    let expected = crc16_xmodem(&decoded[..5]);
    let actual = u16::from_be_bytes([decoded[5], decoded[6]]);
    (expected == actual).then_some(decoded)
}

fn hex_nibble(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

fn crc16_xmodem(bytes: &[u8]) -> u16 {
    let mut crc = 0_u16;
    for byte in bytes {
        crc ^= u16::from(*byte) << 8;
        for _ in 0..8 {
            crc = if crc & 0x8000 != 0 {
                (crc << 1) ^ 0x1021
            } else {
                crc << 1
            };
        }
    }
    crc
}

fn flush_scanner_prefix(held: &mut Vec<u8>, passthrough: &mut Vec<u8>) {
    let keep = longest_possible_prefix(held);
    let flush = held.len().saturating_sub(keep);
    passthrough.extend_from_slice(&held[..flush]);
    held.drain(..flush);
}

fn longest_possible_prefix(bytes: &[u8]) -> usize {
    let maximum = bytes
        .len()
        .min(MAX_INITIAL_HEADER_CANDIDATE_BYTES.saturating_sub(1));
    for length in (1..=maximum).rev() {
        let suffix = &bytes[bytes.len() - length..];
        if is_possible_header_prefix(suffix) {
            return length;
        }
    }
    0
}

fn is_possible_header_prefix(bytes: &[u8]) -> bool {
    matches!(
        parse_initial_header_candidate(bytes),
        InitialHeaderCandidate::Incomplete
    )
}

fn append_wire(wire: &mut Vec<u8>, bytes: &[u8]) -> Result<(), ZmodemError> {
    if wire.len().saturating_add(bytes.len()) > MAX_WIRE_BUFFER_BYTES {
        return Err(ZmodemError::WireBufferOverflow);
    }
    wire.extend_from_slice(bytes);
    Ok(())
}

fn compact_wire(wire: &mut Vec<u8>, offset: &mut usize) {
    if *offset == wire.len() {
        wire.clear();
        *offset = 0;
    } else if *offset >= 4096 {
        wire.drain(..*offset);
        *offset = 0;
    }
}

fn take_unconsumed_wire(wire: &[u8], offset: usize) -> Vec<u8> {
    if offset >= wire.len() {
        Vec::new()
    } else {
        wire[offset..].to_vec()
    }
}

fn preflight_send_sources(paths: &[PathBuf]) -> Result<(usize, u64), ZmodemError> {
    if paths.is_empty() || paths.len() > MAX_FILES_PER_BATCH {
        return Err(ZmodemError::InvalidSourceFiles);
    }
    let mut total = 0_u64;
    for path in paths {
        if !path.is_absolute() {
            return Err(ZmodemError::InvalidSourceFiles);
        }
        let metadata = fs::symlink_metadata(path).map_err(|_| ZmodemError::InvalidSourceFiles)?;
        if !metadata.file_type().is_file() || metadata.len() > MAX_FILE_BYTES {
            return Err(ZmodemError::InvalidSourceFiles);
        }
        total = total
            .checked_add(metadata.len())
            .filter(|value| *value <= MAX_BATCH_BYTES)
            .ok_or(ZmodemError::InvalidSourceFiles)?;
    }
    Ok((paths.len(), total))
}

fn open_send_sources(paths: &[PathBuf]) -> Result<(VecDeque<SendSource>, u64), ZmodemError> {
    if paths.is_empty() || paths.len() > MAX_FILES_PER_BATCH {
        return Err(ZmodemError::InvalidSourceFiles);
    }
    let mut result = VecDeque::with_capacity(paths.len());
    let mut used_name_keys = HashSet::with_capacity(paths.len());
    let mut total = 0_u64;
    for path in paths {
        if !path.is_absolute() {
            return Err(ZmodemError::InvalidSourceFiles);
        }
        let source = open_send_file(path)?;
        // Inspect the opened handle, not a path checked before open. On Unix,
        // O_NOFOLLOW makes the final path component check/open atomic.
        let metadata = source
            .metadata()
            .map_err(|_| ZmodemError::InvalidSourceFiles)?;
        if !metadata.file_type().is_file() || metadata.len() > MAX_FILE_BYTES {
            return Err(ZmodemError::InvalidSourceFiles);
        }
        total = total
            .checked_add(metadata.len())
            .filter(|value| *value <= MAX_BATCH_BYTES)
            .ok_or(ZmodemError::InvalidSourceFiles)?;
        let name = path
            .file_name()
            .and_then(|value| value.to_str())
            .and_then(|value| reserve_unique_send_name(value, &mut used_name_keys))
            .ok_or(ZmodemError::InvalidSourceFiles)?;
        let original_mutation = SendSourceMutation::from_metadata(&metadata);
        result.push_back(SendSource {
            file: source,
            name,
            size: u32::try_from(metadata.len()).map_err(|_| ZmodemError::InvalidSourceFiles)?,
            modification_time: original_mutation
                .modified
                .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
                .map(|value| value.as_secs()),
            original_mutation,
        });
    }
    Ok((result, total))
}

#[cfg(test)]
fn open_send_files(paths: &[PathBuf]) -> Result<(VecDeque<SendFile>, u64), ZmodemError> {
    let (sources, total) = open_send_sources(paths)?;
    let files = snapshot_send_sources(sources, &AtomicBool::new(false), |_| {})?;
    Ok((files, total))
}

fn snapshot_send_sources(
    sources: VecDeque<SendSource>,
    cancel: &AtomicBool,
    mut report_progress: impl FnMut(u64),
) -> Result<VecDeque<SendFile>, ZmodemError> {
    let mut files = VecDeque::with_capacity(sources.len());
    let mut completed_bytes = 0_u64;
    for source in sources {
        if cancel.load(Ordering::Acquire) {
            return Err(ZmodemError::Io);
        }
        let file = snapshot_send_file(
            source.file,
            u64::from(source.size),
            source.original_mutation,
            cancel,
            |bytes| report_progress(completed_bytes.saturating_add(bytes)),
        )?;
        completed_bytes = completed_bytes.saturating_add(u64::from(source.size));
        files.push_back(SendFile {
            file,
            name: source.name,
            size: source.size,
            modification_time: source.modification_time,
        });
    }
    Ok(files)
}

fn snapshot_send_file(
    mut source: File,
    expected_size: u64,
    initial_mutation: SendSourceMutation,
    cancel: &AtomicBool,
    mut report_progress: impl FnMut(u64),
) -> Result<File, ZmodemError> {
    let mut snapshot = tempfile::tempfile().map_err(|_| ZmodemError::Io)?;
    #[cfg(unix)]
    snapshot
        .set_permissions(std::fs::Permissions::from_mode(0o600))
        .map_err(|_| ZmodemError::Io)?;

    let copy_limit = expected_size.saturating_add(1);
    let mut copied = 0_u64;
    let mut buffer = vec![0_u8; SNAPSHOT_PROGRESS_CHUNK_BYTES];
    while copied < copy_limit {
        if cancel.load(Ordering::Acquire) {
            return Err(ZmodemError::Io);
        }
        let remaining = usize::try_from(copy_limit - copied)
            .unwrap_or(usize::MAX)
            .min(buffer.len());
        let read = source
            .read(&mut buffer[..remaining])
            .map_err(|_| ZmodemError::Io)?;
        if read == 0 {
            break;
        }
        if cancel.load(Ordering::Acquire) {
            return Err(ZmodemError::Io);
        }
        snapshot
            .write_all(&buffer[..read])
            .map_err(|_| ZmodemError::Io)?;
        copied = copied.saturating_add(read as u64);
        report_progress(copied);
    }
    let final_metadata = source
        .metadata()
        .map_err(|_| ZmodemError::InvalidSourceFiles)?;
    if copied != expected_size
        || final_metadata.len() != expected_size
        || SendSourceMutation::from_metadata(&final_metadata) != initial_mutation
    {
        return Err(ZmodemError::InvalidSourceFiles);
    }

    snapshot.flush().map_err(|_| ZmodemError::Io)?;
    snapshot
        .seek(SeekFrom::Start(0))
        .map_err(|_| ZmodemError::Io)?;
    Ok(snapshot)
}

fn reserve_unique_send_name(
    raw_name: &str,
    used_name_keys: &mut HashSet<String>,
) -> Option<String> {
    let base_name = sanitize_local_name(raw_name);
    if base_name.is_empty() {
        return None;
    }
    if used_name_keys.insert(portable_wire_name_key(&base_name)) {
        return Some(base_name);
    }
    for index in 1..10_000 {
        let candidate = destination_candidate(&base_name, index);
        if used_name_keys.insert(portable_wire_name_key(&candidate)) {
            return Some(candidate);
        }
    }
    None
}

fn portable_wire_name_key(name: &str) -> String {
    name.nfkc().flat_map(char::to_lowercase).nfkc().collect()
}

#[cfg(unix)]
fn open_send_file(path: &Path) -> Result<File, ZmodemError> {
    let mut options = OpenOptions::new();
    options
        .read(true)
        // O_NONBLOCK prevents an attacker-controlled FIFO from blocking the
        // synchronous authorization path before the opened handle can be
        // rejected by its file type below. It has no effect on regular files.
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK);
    options
        .open(path)
        .map_err(|_| ZmodemError::InvalidSourceFiles)
}

#[cfg(not(unix))]
fn open_send_file(path: &Path) -> Result<File, ZmodemError> {
    // std does not expose a portable no-follow open. Keep the conservative
    // pre-check on other targets and verify the opened handle is still a
    // regular file below. Platform-specific implementations can strengthen
    // this without weakening Unix callers.
    let metadata = fs::symlink_metadata(path).map_err(|_| ZmodemError::InvalidSourceFiles)?;
    if !metadata.file_type().is_file() {
        return Err(ZmodemError::InvalidSourceFiles);
    }
    File::open(path).map_err(|_| ZmodemError::InvalidSourceFiles)
}

fn create_receive_file_at(
    directory: &ReceiveDirectory,
    raw_name: &str,
    size: Option<u32>,
    modification_time: Option<u64>,
    transfer_id: u64,
    owner_session_id: Option<u64>,
    cancel: Option<&AtomicBool>,
) -> Result<ReceiveFile, ZmodemError> {
    let file_resource_lease = receive_resource_pool()
        .acquire(1, 0, 1)
        .ok_or(ZmodemError::ResourceLimit)?;
    let base_name = sanitize_local_name(raw_name);
    let name = unique_destination_name(directory, &base_name, cancel)?;
    // Clone the stable directory identity before creating a staging entry so
    // a descriptor-duplication failure cannot strand a newly created file.
    let file_directory = directory.try_clone()?;
    let (file, temp_name) = create_unique_partial(directory, transfer_id, cancel)?;
    Ok(ReceiveFile {
        file,
        directory: file_directory,
        temp_name,
        backup_name: None,
        base_name,
        name,
        final_name_published: false,
        expected_size: size,
        modification_time,
        owner_session_id,
        written: 0,
        publish_protected: false,
        _resource_lease: file_resource_lease,
    })
}

#[cfg(test)]
fn create_receive_file(
    directory: &Path,
    raw_name: &str,
    size: Option<u32>,
    modification_time: Option<u64>,
    transfer_id: u64,
) -> Result<ReceiveFile, ZmodemError> {
    let directory = ReceiveDirectory::open(directory)?;
    create_receive_file_at(
        &directory,
        raw_name,
        size,
        modification_time,
        transfer_id,
        None,
        None,
    )
}

fn create_unique_partial(
    directory: &ReceiveDirectory,
    transfer_id: u64,
    cancel: Option<&AtomicBool>,
) -> Result<(File, String), ZmodemError> {
    for _ in 0..TEMP_FILE_ATTEMPTS {
        if cancel.is_some_and(|cancel| cancel.load(Ordering::Acquire)) {
            return Err(ZmodemError::InvalidState);
        }
        let nonce = random_hex_token().map_err(|_| ZmodemError::Io)?;
        let temp_name = format!(
            ".ianvs-zmodem-{}-{transfer_id}-{nonce}.part",
            std::process::id()
        );
        match directory.create_new(&temp_name) {
            Ok(file) => return Ok((file, temp_name)),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => return Err(ZmodemError::Io),
        }
    }
    Err(ZmodemError::Io)
}

fn send_file_info(file: &SendFile) -> FileInfo<'_> {
    let mut info = FileInfo::new(file.name.as_bytes(), Some(Position::new(file.size)));
    if let Some(modification_time) = file.modification_time {
        info = info.with_modification_time(modification_time);
    }
    info
}

fn apply_modification_time(file: &File, modification_time: Option<u64>) -> Result<(), ZmodemError> {
    let Some(seconds) = modification_time else {
        return Ok(());
    };
    let modified = UNIX_EPOCH
        .checked_add(Duration::from_secs(seconds))
        .ok_or(ZmodemError::Io)?;
    file.set_times(FileTimes::new().set_modified(modified))
        .map_err(|_| ZmodemError::Io)
}

fn commit_receive_file(
    received: ReceiveFile,
    cancellation: Option<&ReceiveCommitCancellation>,
) -> Result<String, ZmodemError> {
    commit_receive_file_with_metadata_and_sync(
        received,
        |directory, file, source, destination| {
            directory.publish_file_noreplace(file, source, destination)
        },
        apply_modification_time,
        (
            ReceiveDirectory::sync_published_file,
            ReceiveDirectory::sync,
        ),
        cancellation,
    )
}

#[cfg(test)]
fn commit_receive_file_with(
    received: ReceiveFile,
    mut publish: impl FnMut(&Path, &Path) -> std::io::Result<()>,
) -> Result<String, ZmodemError> {
    commit_receive_file_with_metadata(
        received,
        |directory, _file, source, destination| {
            publish(
                &directory.child_path(source),
                &directory.child_path(destination),
            )
        },
        apply_modification_time,
        None,
    )
}

#[cfg(test)]
fn commit_receive_file_with_metadata(
    received: ReceiveFile,
    publish: impl FnMut(&ReceiveDirectory, &File, &str, &str) -> std::io::Result<()>,
    set_modification_time: impl FnMut(&File, Option<u64>) -> Result<(), ZmodemError>,
    cancellation: Option<&ReceiveCommitCancellation>,
) -> Result<String, ZmodemError> {
    commit_receive_file_with_metadata_and_sync(
        received,
        publish,
        set_modification_time,
        (ReceiveDirectory::sync_published_file, |_| Ok(())),
        cancellation,
    )
}

fn commit_receive_file_with_metadata_and_sync(
    mut received: ReceiveFile,
    mut publish: impl FnMut(&ReceiveDirectory, &File, &str, &str) -> std::io::Result<()>,
    mut set_modification_time: impl FnMut(&File, Option<u64>) -> Result<(), ZmodemError>,
    durability: (
        impl FnMut(&ReceiveDirectory, &File, &str) -> std::io::Result<VerifiedPublishedFile>,
        impl FnMut(&ReceiveDirectory) -> std::io::Result<()>,
    ),
    cancellation: Option<&ReceiveCommitCancellation>,
) -> Result<String, ZmodemError> {
    let (mut sync_published_file, mut sync_directory) = durability;
    if received.file.flush().is_err() {
        schedule_staging_cleanup(received);
        return Err(ZmodemError::Io);
    }
    if set_modification_time(&received.file, received.modification_time).is_err()
        || received.file.sync_all().is_err()
    {
        return Err(preserved_publish_error(received));
    }
    if cancellation.is_some_and(|cancellation| !cancellation.publication_is_current()) {
        return Err(cancelled_publish_error(received));
    }
    if received.protect_publish_source().is_err() {
        return Err(preserved_publish_error(received));
    }

    // Establish rollback authority before the namespace publication point.
    // If this fails, the original named staging file is still complete and
    // is registered directly; no best-effort rename rollback is required.
    match received
        .directory
        .create_publish_backup(&received.temp_name, &received.file)
    {
        Ok(backup_name) => received.backup_name = Some(backup_name),
        Err(orphaned_backup) => {
            received.backup_name = orphaned_backup;
            return Err(preserved_publish_error(received));
        }
    }

    // Publish with a same-directory, no-replace rename. The successful rename
    // is the single namespace linearization point: it creates the final name
    // and removes the staging name atomically, so there is no check/unlink
    // cleanup window. A stable source handle and hidden read-only rollback
    // link remain live until final verification completes.
    for index in 0..10_000 {
        if cancellation.is_some_and(|cancellation| !cancellation.publication_is_current()) {
            return Err(cancelled_publish_error(received));
        }
        if index > 0 {
            received.name = destination_candidate(&received.base_name, index);
        }
        match publish(
            &received.directory,
            &received.file,
            &received.temp_name,
            &received.name,
        ) {
            Ok(()) => {
                received.final_name_published = true;
                let mut published = match sync_published_file(
                    &received.directory,
                    &received.file,
                    &received.name,
                ) {
                    Ok(published) => published,
                    Err(_) => return Err(preserved_publish_error(received)),
                };
                if cancellation.is_some_and(|cancellation| !cancellation.publication_is_current()) {
                    return Err(cancelled_publish_error(received));
                }
                if sync_directory(&received.directory).is_err() {
                    return Err(preserved_publish_error(received));
                }
                if cancellation.is_some_and(|cancellation| !cancellation.publication_is_current()) {
                    return Err(cancelled_publish_error(received));
                }
                if published
                    .revalidate(&received.directory, &received.name)
                    .is_err()
                {
                    return Err(preserved_publish_error(received));
                }
                if cancellation.is_some_and(|cancellation| !cancellation.publication_is_current()) {
                    return Err(cancelled_publish_error(received));
                }
                let Some(backup_name) = received.backup_name.as_deref() else {
                    return Err(preserved_publish_error(received));
                };
                // Remove the rollback link while both names are still 0400.
                // Only after that durable namespace update may the published
                // file become writable.
                if received
                    .directory
                    .detach_verified_alias(backup_name, &received.file)
                    .is_err()
                {
                    return Err(preserved_publish_error(received));
                }
                received.backup_name = None;
                if cancellation.is_some_and(|cancellation| !cancellation.publication_is_current()) {
                    return Err(cancelled_publish_error(received));
                }
                if published
                    .accept_verified_link_removal(&received.directory, &received.name)
                    .is_err()
                {
                    return Err(preserve_or_cleanup_postpublish(received));
                }
                if cancellation.is_some_and(|cancellation| !cancellation.publication_is_current()) {
                    return Err(cancelled_publish_error(received));
                }
                if published
                    .restore_write_mode_and_revalidate(&received.directory, &received.name)
                    .is_err()
                {
                    return Err(preserve_or_cleanup_postpublish(received));
                }
                received.publish_protected = false;
                if let Some(cancellation) = cancellation
                    && !cancellation.mark_result_ready()
                {
                    return Err(cancelled_publish_error(received));
                }
                let published_name = received.name.clone();
                return Ok(published_name);
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => {
                return Err(preserved_publish_error(received));
            }
        }
    }
    Err(preserved_publish_error(received))
}

fn preserve_or_cleanup_postpublish(received: ReceiveFile) -> ZmodemError {
    preserve_or_cleanup_postpublish_with(received, |directory, name, file| {
        directory.create_publish_backup(name, file)
    })
}

fn preserve_or_cleanup_postpublish_with(
    mut received: ReceiveFile,
    create_backup: impl FnOnce(&ReceiveDirectory, &str, &File) -> Result<String, Option<String>>,
) -> ZmodemError {
    // The rollback link may already have been removed. Recreate it from the
    // still-open, identity-checked final file before reporting preservation.
    // If even that fails, explicitly quarantine every known alias; never let
    // a generic error drop ReceiveFile while a final path remains visible.
    match create_backup(&received.directory, &received.name, &received.file) {
        Ok(backup) => {
            received.backup_name = Some(backup);
            preserved_publish_error(received)
        }
        Err(orphaned_backup) => {
            received.backup_name = orphaned_backup;
            // Backup recreation also fails when another file has replaced the
            // published name. Run the identity-aware detach before handing
            // cleanup to another thread; a mismatch clears ownership so that
            // delayed cleanup never quarantines the unrelated replacement.
            let _ = received.detach_published_name();
            schedule_staging_cleanup(received);
            ZmodemError::Io
        }
    }
}

fn cancelled_publish_error(mut received: ReceiveFile) -> ZmodemError {
    // A timeout may win after the no-replace rename but before the worker can
    // linearize RESULT_READY. Detach the final alias synchronously when
    // possible and hand every remaining verified name to bounded cleanup.
    if received.final_name_published
        && !received
            .directory
            .entry_matches_file(&received.temp_name, &received.file)
            .unwrap_or(false)
    {
        let _ = received.detach_published_name();
    }
    schedule_staging_cleanup(received);
    ZmodemError::InvalidState
}

fn preserved_publish_error(received: ReceiveFile) -> ZmodemError {
    let mut received = received;
    let staging_matches = received
        .directory
        .entry_matches_file(&received.temp_name, &received.file)
        .unwrap_or(false);
    if staging_matches {
        // A pre-publication failure keeps the original staging name, but it may
        // not become writable while a hidden hard-link alias still exists.
        if let Some(backup_name) = received.backup_name.as_deref()
            && received
                .directory
                .detach_verified_alias(backup_name, &received.file)
                .is_err()
        {
            schedule_staging_cleanup(received);
            return ZmodemError::Io;
        }
        received.backup_name = None;
    } else {
        // Publication renamed the staging entry to its final name. Remove that
        // public alias while the inode is still 0400, then expose only the
        // hidden rollback name. This prevents later writes through the final
        // path from mutating the recovery content and makes Discard complete.
        if received.detach_published_name().is_err() || received.switch_to_publish_backup().is_err()
        {
            schedule_staging_cleanup(received);
            return ZmodemError::Io;
        }
    }
    received.restore_recovery_mode();
    let owner_session_id = received.owner_session_id;
    let cleanup = StagingCleanup::from(received);
    let partial_path = cleanup.directory.child_path(&cleanup.temp_name);
    ZmodemError::Publish {
        partial_path,
        recovery_token: register_recovery(cleanup, owner_session_id),
    }
}

fn unique_destination_name(
    directory: &ReceiveDirectory,
    raw_name: &str,
    cancel: Option<&AtomicBool>,
) -> Result<String, ZmodemError> {
    let safe = sanitize_local_name(raw_name);
    let safe = if safe.is_empty() {
        "Unnamed file".to_string()
    } else {
        safe
    };
    if !directory.child_exists(&safe).map_err(|_| ZmodemError::Io)? {
        return Ok(safe);
    }
    for index in 1..10_000 {
        if cancel.is_some_and(|cancel| cancel.load(Ordering::Acquire)) {
            return Err(ZmodemError::InvalidState);
        }
        let candidate = destination_candidate(&safe, index);
        if !directory
            .child_exists(&candidate)
            .map_err(|_| ZmodemError::Io)?
        {
            return Ok(candidate);
        }
    }
    Ok(destination_candidate("received", 10_000))
}

fn destination_candidate(safe: &str, index: usize) -> String {
    let path = Path::new(safe);
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("file");
    let extension = path.extension().and_then(|value| value.to_str());
    let suffix = match extension {
        Some(extension) => format!(" ({index}).{extension}"),
        None => format!(" ({index})"),
    };
    finalize_local_name(format_name_with_suffix(stem, &suffix), "received")
}

fn sanitize_received_name(raw: &[u8]) -> String {
    let basename = raw
        .rsplit(|byte| matches!(*byte, b'/' | b'\\'))
        .next()
        .unwrap_or_default();
    let decoded = String::from_utf8_lossy(basename);
    sanitize_local_name(&decoded)
}

fn validated_received_name(raw: &[u8]) -> Result<String, ZmodemError> {
    let basename = raw
        .rsplit(|byte| matches!(*byte, b'/' | b'\\'))
        .next()
        .unwrap_or_default();
    if basename.iter().any(|byte| byte.is_ascii_control())
        || basename
            .last()
            .is_some_and(|byte| matches!(*byte, b' ' | b'.'))
        || String::from_utf8_lossy(basename)
            .chars()
            .any(is_bidi_control)
    {
        return Err(ZmodemError::InvalidDestination);
    }
    Ok(sanitize_received_name(raw))
}

fn sanitize_local_name(raw: &str) -> String {
    let value = raw
        .chars()
        .filter_map(|character| {
            if character.is_control() || is_bidi_control(character) {
                None
            } else if matches!(
                character,
                '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*'
            ) {
                Some('_')
            } else {
                Some(character)
            }
        })
        .collect::<String>();
    finalize_local_name(value, "Unnamed file")
}

fn is_bidi_control(character: char) -> bool {
    matches!(
        character,
        '\u{061c}'
            | '\u{200e}'
            | '\u{200f}'
            | '\u{202a}'..='\u{202e}'
            | '\u{2066}'..='\u{2069}'
    )
}

fn finalize_local_name(mut value: String, fallback: &str) -> String {
    for _ in 0..2 {
        value = value.trim().trim_end_matches([' ', '.']).to_string();
        if value.is_empty() || value == "." || value == ".." {
            value = fallback.to_string();
        }
        if is_windows_reserved_name(&value) {
            value.insert(0, '_');
        }
        truncate_utf8(&mut value, MAX_FILENAME_BYTES);
    }

    // A byte truncation can expose a trailing dot/space that was previously
    // followed by a multibyte character. Re-clean and revalidate the final
    // byte-bounded form before it is ever used as a directory entry.
    value = value.trim().trim_end_matches([' ', '.']).to_string();
    if value.is_empty()
        || value == "."
        || value == ".."
        || is_windows_reserved_name(&value)
        || value.len() > MAX_FILENAME_BYTES
    {
        value = fallback.to_string();
        if is_windows_reserved_name(&value) {
            value.insert(0, '_');
        }
        truncate_utf8(&mut value, MAX_FILENAME_BYTES);
        value = value.trim().trim_end_matches([' ', '.']).to_string();
    }
    value
}

fn is_windows_reserved_name(value: &str) -> bool {
    let stem = value
        .split('.')
        .next()
        .unwrap_or_default()
        .trim_end_matches([' ', '.'])
        .to_ascii_uppercase();
    matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || stem
            .strip_prefix("COM")
            .or_else(|| stem.strip_prefix("LPT"))
            .is_some_and(|number| {
                matches!(number, "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9")
            })
}

fn format_name_with_suffix(stem: &str, suffix: &str) -> String {
    let mut suffix = suffix.to_string();
    truncate_utf8(&mut suffix, MAX_FILENAME_BYTES.saturating_sub("file".len()));
    let max_stem_bytes = MAX_FILENAME_BYTES.saturating_sub(suffix.len());
    let mut stem = stem.to_string();
    truncate_utf8(&mut stem, max_stem_bytes);
    if stem.is_empty() {
        stem.push_str("file");
    }
    stem.push_str(&suffix);
    finalize_local_name(stem, "received")
}

fn truncate_utf8(value: &mut String, max_bytes: usize) {
    if value.len() <= max_bytes {
        return;
    }
    let mut boundary = max_bytes;
    while boundary > 0 && !value.is_char_boundary(boundary) {
        boundary -= 1;
    }
    value.truncate(boundary);
}

fn started_event(
    transfer_id: u64,
    direction: ZmodemDirection,
    file_count: Option<usize>,
    total_bytes: Option<u64>,
) -> ZmodemEvent {
    ZmodemEvent::new(
        "zmodem_started",
        serde_json::json!({
            "source": "zmodem",
            "transferId": transfer_id.to_string(),
            "direction": direction.as_str(),
            "fileCount": file_count,
            "totalBytes": total_bytes,
        }),
    )
}

fn completed_event(
    transfer_id: u64,
    direction: ZmodemDirection,
    completed_files: usize,
    skipped_files: usize,
) -> ZmodemEvent {
    ZmodemEvent::new(
        "zmodem_completed",
        serde_json::json!({
            "source": "zmodem",
            "transferId": transfer_id.to_string(),
            "direction": direction.as_str(),
            "completedFiles": completed_files,
            "skippedFiles": skipped_files,
        }),
    )
}

fn failed_event(transfer_id: u64, direction: ZmodemDirection, error: &ZmodemError) -> ZmodemEvent {
    let mut payload = serde_json::json!({
        "source": "zmodem",
        "transferId": transfer_id.to_string(),
        "direction": direction.as_str(),
        "reason": error_code(error),
    });
    if let ZmodemError::Publish {
        partial_path,
        recovery_token,
    } = error
    {
        let partial_name = partial_path
            .file_name()
            .map(|name| sanitize_local_name(&name.to_string_lossy()))
            .unwrap_or_else(|| "ZMODEM partial file".to_string());
        if let Some(token) = recovery_token {
            payload["recoverablePartialName"] = Value::String(partial_name);
            payload["stagingPreserved"] = Value::Bool(true);
            payload["recoveryToken"] = Value::String(token.clone());
        }
    }
    ZmodemEvent::new("zmodem_failed", payload)
}

fn maybe_progress(
    transfer_id: u64,
    direction: ZmodemDirection,
    transferred: u64,
    total: Option<u64>,
    last_progress: &mut Instant,
    effects: &mut ZmodemEffects,
) {
    let now = Instant::now();
    if total != Some(transferred) && now.duration_since(*last_progress) < PROGRESS_INTERVAL {
        return;
    }
    *last_progress = now;
    effects.events.push(ZmodemEvent::new(
        "zmodem_progress",
        serde_json::json!({
            "source": "zmodem",
            "transferId": transfer_id.to_string(),
            "direction": direction.as_str(),
            "bytesTransferred": transferred,
            "totalBytes": total,
        }),
    ));
}

fn protocol_error(error: zmodem2::Error) -> ZmodemError {
    ZmodemError::Protocol(error.to_string())
}

fn active_drive_error(error: ZmodemError) -> ZmodemError {
    match error {
        ZmodemError::InvalidState
        | ZmodemError::InvalidDestination
        | ZmodemError::InvalidSourceFiles => ZmodemError::Protocol(error.to_string()),
        ZmodemError::UnsupportedPlatform => ZmodemError::Protocol(error.to_string()),
        error => error,
    }
}

fn error_code(error: &ZmodemError) -> &'static str {
    match error {
        ZmodemError::InvalidState => "invalid_state",
        ZmodemError::StaleTransfer => "stale_transfer",
        ZmodemError::InvalidDestination => "invalid_destination",
        ZmodemError::InvalidSourceFiles => "invalid_source_files",
        ZmodemError::ResourceLimit => "resource_limit",
        ZmodemError::UnsupportedPlatform => "unsupported_platform",
        ZmodemError::Io => "io_error",
        ZmodemError::Publish { .. } => "publish_failed",
        ZmodemError::Protocol(_) => "protocol_error",
        ZmodemError::WireBufferOverflow => "wire_buffer_overflow",
        ZmodemError::Timeout => "timeout",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wait_for_path_removal(path: &Path) {
        let deadline = Instant::now() + Duration::from_secs(2);
        while path.exists() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(5));
        }
        assert!(!path.exists(), "staging path was not removed: {path:?}");
    }

    fn wait_for_empty_directory(path: &Path) {
        let deadline = Instant::now() + Duration::from_secs(2);
        loop {
            if fs::read_dir(path).unwrap().next().is_none() {
                return;
            }
            assert!(
                Instant::now() < deadline,
                "staging directory did not become empty: {path:?}"
            );
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    struct FailingWriter;

    impl Write for FailingWriter {
        fn write(&mut self, _buffer: &[u8]) -> std::io::Result<usize> {
            Err(std::io::Error::other("injected writer failure"))
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Err(std::io::Error::other("injected writer failure"))
        }
    }

    fn receive_transfer(id: u64) -> ReceiveTransfer {
        let now = Instant::now();
        let mut engine = Receiver::with_flow_control(0, true).unwrap();
        engine.set_manual_file_accept(true);
        ReceiveTransfer {
            id,
            owner_session_id: None,
            engine: Box::new(engine),
            wire: Vec::new(),
            wire_offset: 0,
            destination: None,
            current_offer: None,
            current_file: None,
            preparation: None,
            publication: None,
            publication_failure: None,
            publication_transport_closed: None,
            offered_files: 0,
            completed_files: 0,
            transferred_bytes: 0,
            last_progress: now,
            last_activity: now,
            progress_deadline: now + TRANSFER_IDLE_TIMEOUT,
            protocol_retry_at: now + PROTOCOL_RETRY_INTERVAL,
            authorization_deadline: now + AUTHORIZATION_TIMEOUT,
            session_completed: false,
            commit_cancellation: None,
        }
    }

    fn accept_send_ready(
        manager: &mut ZmodemManager,
        transfer_id: u64,
        paths: &[PathBuf],
        writer: &mut dyn Write,
    ) -> ZmodemEffects {
        let mut effects = manager.accept_send(transfer_id, paths, writer).unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            let mut prepared = ZmodemEffects::default();
            manager
                .finish_send_preparation(writer, &mut prepared)
                .unwrap();
            effects.events.extend(prepared.events);
            effects.passthrough.extend(prepared.passthrough);
            effects.terminate_transport |= prepared.terminate_transport;
            if !matches!(manager.state, TransferState::PreparingSend(_)) {
                return effects;
            }
            std::thread::sleep(Duration::from_millis(1));
        }
        panic!("send snapshot worker did not finish")
    }

    fn accept_receive_ready(
        manager: &mut ZmodemManager,
        transfer_id: u64,
        destination: &Path,
        writer: &mut dyn Write,
    ) -> Result<ZmodemEffects, ZmodemError> {
        let mut effects = manager.accept_receive(transfer_id, destination, writer)?;
        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            if manager.finish_receive_preparation(writer, &mut effects)? {
                return Ok(effects);
            }
            std::thread::sleep(Duration::from_millis(1));
        }
        panic!("receive preparation worker did not finish")
    }

    fn receiver_waiting_for_final_oo(directory: &Path) -> ZmodemManager {
        let mut sender = Sender::new().unwrap();
        sender
            .start_file(FileInfo::new(b"empty.bin", Some(Position::ZERO)))
            .unwrap();
        let mut manager = ZmodemManager::default();
        let mut receiver_wire = Vec::new();
        let mut accepted = false;
        let mut finish_requested = false;

        for _ in 0..10_000 {
            match sender.poll() {
                Action::WriteWire(bytes) => {
                    let bytes = bytes.to_vec();
                    sender.wire_written(bytes.len());
                    let effects = manager.ingest(&bytes, &mut receiver_wire).unwrap();
                    if effects
                        .events
                        .iter()
                        .any(|event| event.kind == "zmodem_file_offer")
                    {
                        assert!(!accepted);
                        accept_receive_ready(&mut manager, 1, directory, &mut receiver_wire)
                            .unwrap();
                        accepted = true;
                    }
                    if matches!(
                        &manager.state,
                        TransferState::Receiving(transfer)
                            if transfer.engine.is_waiting_final_oo()
                    ) {
                        return manager;
                    }
                }
                Action::ReadFile { .. } => sender.submit_file(&[]).unwrap(),
                Action::Event(Event::FileCompleted) => {
                    assert!(!finish_requested);
                    sender.finish().unwrap();
                    finish_requested = true;
                }
                Action::Event(event) => panic!("unexpected sender event: {event:?}"),
                Action::Idle => {
                    assert!(!receiver_wire.is_empty(), "protocol made no progress");
                    let wire = std::mem::take(&mut receiver_wire);
                    assert!(sender.submit_wire(&wire).unwrap() > 0);
                }
                action => panic!("unexpected sender action: {action:?}"),
            }
        }
        panic!("receiver never reached WaitFinalOo")
    }

    fn receiver_with_partial_file(directory: &Path) -> (ZmodemManager, PathBuf) {
        const FILE_SIZE: u32 = 20 * 1024;
        let mut sender = Sender::new().unwrap();
        sender
            .start_file(FileInfo::new(
                b"partial.bin",
                Some(Position::new(FILE_SIZE)),
            ))
            .unwrap();
        let mut manager = ZmodemManager::default();
        let mut receiver_wire = Vec::new();
        let mut accepted = false;

        for _ in 0..10_000 {
            match sender.poll() {
                Action::WriteWire(bytes) => {
                    let bytes = bytes.to_vec();
                    sender.wire_written(bytes.len());
                    let effects = manager.ingest(&bytes, &mut receiver_wire).unwrap();
                    if effects
                        .events
                        .iter()
                        .any(|event| event.kind == "zmodem_file_offer")
                    {
                        assert!(!accepted);
                        accept_receive_ready(&mut manager, 1, directory, &mut receiver_wire)
                            .unwrap();
                        accepted = true;
                    }
                    let staging = match &manager.state {
                        TransferState::Receiving(transfer) => transfer
                            .current_file
                            .as_ref()
                            .filter(|file| file.written > 0 && file.written < u64::from(FILE_SIZE))
                            .filter(|_| !receiver_wire.is_empty())
                            .map(ReceiveFile::recoverable_path),
                        _ => None,
                    };
                    if let Some(staging) = staging {
                        return (manager, staging);
                    }
                }
                Action::ReadFile { offset, max_len } => {
                    let remaining = usize::try_from(FILE_SIZE - offset.get()).unwrap();
                    let len = max_len.min(remaining);
                    assert!(len > 0);
                    sender.submit_file(&vec![b'x'; len]).unwrap();
                }
                Action::Event(event) => panic!("file completed too early: {event:?}"),
                Action::Idle => {
                    assert!(!receiver_wire.is_empty(), "protocol made no progress");
                    let wire = std::mem::take(&mut receiver_wire);
                    assert!(sender.submit_wire(&wire).unwrap() > 0);
                }
                action => panic!("unexpected sender action: {action:?}"),
            }
        }
        panic!("receiver never persisted a partial file")
    }

    fn hex_header(frame: u8, flags: [u8; 4]) -> Vec<u8> {
        let mut payload = vec![frame];
        payload.extend_from_slice(&flags);
        let crc = crc16_xmodem(&payload);
        let mut result = HEX_HEADER_PREFIX.to_vec();
        for byte in payload.into_iter().chain(crc.to_be_bytes()) {
            result.extend_from_slice(format!("{byte:02x}").as_bytes());
        }
        result
    }

    #[test]
    fn detector_requires_a_crc_valid_initial_header() {
        let mut invalid = hex_header(0, [0; 4]);
        *invalid.last_mut().unwrap() = b'1';
        assert_eq!(find_initial_header(&invalid), None);
        assert_eq!(
            find_initial_header(&hex_header(0, [0; 4])),
            Some((0, ZmodemDirection::Receive))
        );
        assert_eq!(
            find_initial_header(&hex_header(1, [0, 0, 0, 0x23])),
            Some((0, ZmodemDirection::Send))
        );
    }

    #[test]
    fn detector_accepts_uppercase_hex_headers() {
        let mut header = hex_header(1, [0, 0, 0, 0x23]);
        header[HEX_HEADER_PREFIX.len()..].make_ascii_uppercase();
        assert_eq!(
            find_initial_header(&header),
            Some((0, ZmodemDirection::Send))
        );
    }

    #[test]
    fn detector_accepts_mark_parity_without_rewriting_original_wire_bytes() {
        let mut header = hex_header(1, [0, 0, 0, 0x23]);
        header.iter_mut().for_each(|byte| *byte |= 0x80);
        assert_eq!(
            find_initial_header(&header),
            Some((0, ZmodemDirection::Send))
        );

        let mut input = b"original-prefix".to_vec();
        input.extend_from_slice(&header);
        let mut manager = ZmodemManager::default();
        let effects = manager.ingest(&input, &mut Vec::new()).unwrap();

        assert_eq!(effects.passthrough, b"original-prefix");
        let TransferState::AwaitingSend(transfer) = &manager.state else {
            panic!("parity-marked ZRINIT must be detected")
        };
        assert_eq!(transfer.wire, header);
    }

    #[test]
    fn detector_ignores_split_xon_xoff_without_rewriting_original_wire_bytes() {
        let header = hex_header(1, [0, 0, 0, 0x23]);
        let mut noisy = header[..HEX_HEADER_PREFIX.len()].to_vec();
        for (index, byte) in header[HEX_HEADER_PREFIX.len()..]
            .iter()
            .copied()
            .enumerate()
        {
            noisy.push(if index % 2 == 0 { 0x11 } else { 0x93 });
            noisy.push(byte);
        }
        assert_eq!(
            find_initial_header(&noisy),
            Some((0, ZmodemDirection::Send))
        );

        let mut manager = ZmodemManager::default();
        let mut passthrough = Vec::new();
        for byte in noisy.iter().copied() {
            let effects = manager.ingest(&[byte], &mut Vec::new()).unwrap();
            passthrough.extend(effects.passthrough);
        }

        assert!(passthrough.is_empty());
        let TransferState::AwaitingSend(transfer) = &manager.state else {
            panic!("flow-controlled split ZRINIT must be detected")
        };
        assert_eq!(transfer.wire, noisy);

        let receive_header = hex_header(0, [0; 4]);
        let mut noisy_receive = receive_header[..HEX_HEADER_PREFIX.len()].to_vec();
        for (index, byte) in receive_header[HEX_HEADER_PREFIX.len()..]
            .iter()
            .copied()
            .enumerate()
        {
            noisy_receive.push(if index % 2 == 0 { 0x91 } else { 0x13 });
            noisy_receive.push(byte);
        }
        let mut receiver = ZmodemManager::default();
        let mut response = Vec::new();
        receiver.ingest(&noisy_receive, &mut response).unwrap();
        assert!(matches!(receiver.state, TransferState::Receiving(_)));
        assert!(!response.is_empty());
    }

    #[test]
    fn raw_subpacket_activity_rearms_retry_without_extending_hard_progress_deadline() {
        let mut manager = ZmodemManager {
            state: TransferState::Receiving(receive_transfer(91)),
            next_id: 92,
            failure_passthrough: Vec::new(),
            owner_session_id: None,
            operation_epoch: None,
            receive_commit_phase: None,
            receive_publish_started_at: None,
        };
        let TransferState::Receiving(transfer) = &mut manager.state else {
            unreachable!()
        };
        let hard_deadline = transfer.progress_deadline;
        transfer.protocol_retry_at = Instant::now();

        manager.ingest(b"a", &mut Vec::new()).unwrap();

        let TransferState::Receiving(transfer) = &manager.state else {
            panic!("partial subpacket input must keep the receiver active")
        };
        assert_eq!(transfer.progress_deadline, hard_deadline);
        assert!(transfer.protocol_retry_at > Instant::now());
    }

    #[test]
    fn invalid_parity_marked_candidate_passes_through_byte_for_byte() {
        let mut candidate = hex_header(1, [0, 0, 0, 0x23]);
        candidate.iter_mut().for_each(|byte| *byte |= 0x80);
        candidate[HEX_HEADER_PREFIX.len()] = b'g' | 0x80;
        candidate.extend_from_slice(b" unchanged");

        let mut manager = ZmodemManager::default();
        let effects = manager.ingest(&candidate, &mut Vec::new()).unwrap();

        assert_eq!(effects.passthrough, candidate);
        assert!(!manager.is_active());
    }

    #[test]
    fn scanner_preserves_split_prefix_and_flushes_plain_bytes() {
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        let first = manager.ingest(b"ready\r\n**\x18", &mut writer).unwrap();
        assert_eq!(first.passthrough, b"ready\r\n");
        assert!(first.events.is_empty());

        let header = hex_header(0, [0; 4]);
        let second = manager.ingest(&header[3..], &mut writer).unwrap();
        assert!(second.passthrough.is_empty());
        assert_eq!(second.events[0].kind, "zmodem_detected");
        assert!(manager.is_active());
    }

    #[test]
    fn invalid_candidate_is_returned_byte_for_byte() {
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        let bytes = b"plain **\x18B00000000000001 tail";
        let effects = manager.ingest(bytes, &mut writer).unwrap();
        assert_eq!(effects.passthrough, bytes);
        assert!(!manager.is_active());
    }

    #[test]
    fn scanner_flushes_a_stale_partial_prefix() {
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        let effects = manager.ingest(b"trailing*", &mut writer).unwrap();
        assert_eq!(effects.passthrough, b"trailing");

        let effects = manager
            .timeout_if_needed(
                Instant::now() + SCANNER_HOLD_TIMEOUT + Duration::from_millis(1),
                Some(&mut writer),
            )
            .expect("stale scanner prefix should flush");

        assert_eq!(effects.passthrough, b"*");
        assert!(effects.events.is_empty());
        assert!(!manager.is_active());
    }

    #[test]
    fn received_names_are_flattened_and_sanitized() {
        assert_eq!(
            validated_received_name(b"../../etc/passwd").unwrap(),
            "passwd"
        );
        assert_eq!(
            validated_received_name(b"folder\\file.txt").unwrap(),
            "file.txt"
        );
        assert_eq!(validated_received_name(b"CON.txt").unwrap(), "_CON.txt");
        assert_eq!(
            validated_received_name(b"bad<name>:?.txt").unwrap(),
            "bad_name___.txt"
        );
        assert!(sanitize_local_name(&"界".repeat(200)).len() <= MAX_FILENAME_BYTES);
    }

    #[test]
    fn invalid_raw_receive_basename_is_rejected_before_offer() {
        let bidi = "safe\u{202e}.txt".as_bytes();
        let invalid: [&[u8]; 5] = [
            b"bad\x00name.txt",
            b"bad\x1fname.txt",
            b"bad\x7fname.txt",
            b"trailing-space ",
            b"trailing-dot.",
        ];
        for raw in invalid.into_iter().chain(std::iter::once(bidi)) {
            let mut transfer = receive_transfer(77);
            let mut effects = ZmodemEffects::default();

            let error =
                handle_receive_file_started(&mut transfer, raw, Some(1), None, &mut effects)
                    .unwrap_err();

            assert!(matches!(error, ZmodemError::InvalidDestination));
            assert_eq!(transfer.offered_files, 0);
            assert!(transfer.current_offer.is_none());
            assert!(effects.events.is_empty());
        }
    }

    #[test]
    fn received_names_revalidate_after_utf8_byte_truncation_and_strip_bidi_controls() {
        let exactly_240 = "a".repeat(MAX_FILENAME_BYTES);
        let over_240 = "a".repeat(MAX_FILENAME_BYTES + 1);
        assert_eq!(sanitize_local_name(&exactly_240).len(), MAX_FILENAME_BYTES);
        assert_eq!(sanitize_local_name(&over_240).len(), MAX_FILENAME_BYTES);

        for exposed_suffix in ['.', ' '] {
            let raw = format!("{}{exposed_suffix}界", "a".repeat(MAX_FILENAME_BYTES - 1));
            let safe = sanitize_local_name(&raw);
            assert!(safe.len() <= MAX_FILENAME_BYTES);
            assert!(!safe.ends_with([' ', '.']));
        }

        let bidi = "safe\u{061c}\u{200e}\u{200f}\u{202a}\u{202b}\u{202c}\u{202d}\u{202e}\u{2066}\u{2067}\u{2068}\u{2069}.txt";
        assert_eq!(sanitize_local_name(bidi), "safe.txt");
        assert_eq!(sanitize_local_name("CON\u{202e}.txt"), "_CON.txt");

        let generated = destination_candidate(&format!("{}.txt", "a".repeat(400)), 9_999);
        assert!(generated.len() <= MAX_FILENAME_BYTES);
        assert!(!generated.ends_with([' ', '.']));
        assert!(!generated.is_empty());
        assert!(!is_windows_reserved_name(&generated));

        let fallback = format_name_with_suffix("", &".".repeat(500));
        assert!(fallback.len() <= MAX_FILENAME_BYTES);
        assert!(!fallback.ends_with([' ', '.']));
        assert!(!fallback.is_empty());
        assert!(!is_windows_reserved_name(&fallback));
    }

    #[test]
    fn duplicate_receive_offer_drops_staging_and_preserves_original_offer() {
        let directory = tempfile::tempdir().unwrap();
        let mut transfer = receive_transfer(7);
        transfer.current_offer = Some(("original.bin".to_string(), Some(3), None));
        let mut partial =
            create_receive_file(directory.path(), "original.bin", Some(3), None, 7).unwrap();
        partial.file.write_all(b"x").unwrap();
        partial.written = 1;
        let staging = partial.recoverable_path();
        transfer.current_file = Some(partial);
        let mut effects = ZmodemEffects::default();

        let error = handle_receive_file_started(
            &mut transfer,
            b"replacement.bin",
            Some(9),
            None,
            &mut effects,
        )
        .unwrap_err();

        assert!(matches!(error, ZmodemError::Protocol(_)));
        assert!(transfer.current_file.is_none());
        assert_eq!(
            transfer.current_offer,
            Some(("original.bin".to_string(), Some(3), None))
        );
        wait_for_path_removal(&staging);
        assert!(effects.events.is_empty());
    }

    #[test]
    fn receive_offer_limit_is_independent_of_completed_file_count() {
        let mut transfer = receive_transfer(7);
        let mut effects = ZmodemEffects::default();
        for index in 0..MAX_FILES_PER_BATCH {
            let name = format!("offer-{index}.bin");
            handle_receive_file_started(
                &mut transfer,
                name.as_bytes(),
                Some(0),
                None,
                &mut effects,
            )
            .unwrap();
        }
        assert_eq!(transfer.offered_files, MAX_FILES_PER_BATCH);
        assert_eq!(transfer.completed_files, 0);

        let error = handle_receive_file_started(
            &mut transfer,
            b"one-too-many.bin",
            Some(0),
            None,
            &mut effects,
        )
        .unwrap_err();
        assert!(matches!(error, ZmodemError::InvalidDestination));
        assert_eq!(transfer.offered_files, MAX_FILES_PER_BATCH);
    }

    #[cfg(not(unix))]
    #[test]
    fn receive_is_fail_closed_on_platforms_without_dirfd_operations() {
        assert!(matches!(
            ReceiveDirectory::open(&std::env::temp_dir()),
            Err(ZmodemError::UnsupportedPlatform)
        ));
    }

    #[cfg(all(unix, not(any(target_os = "macos", target_os = "linux"))))]
    #[test]
    fn receive_publish_is_fail_closed_on_unsupported_unix_targets() {
        let directory = tempfile::tempdir().unwrap();
        let receive_directory = ReceiveDirectory::open(directory.path()).unwrap();
        let source = receive_directory.create_new("source.part").unwrap();

        let error = receive_directory
            .publish_file_noreplace(&source, "source.part", "final.bin")
            .unwrap_err();

        assert_eq!(error.kind(), std::io::ErrorKind::Unsupported);
        assert!(receive_directory.child_path("source.part").exists());
        assert!(!receive_directory.child_path("final.bin").exists());
    }

    #[test]
    fn received_file_is_published_without_overwriting() {
        let directory = tempfile::tempdir().unwrap();
        let existing = directory.path().join("report.txt");
        fs::write(&existing, b"existing").unwrap();
        let modification_time = 1_700_000_123_u64;

        let mut received = create_receive_file(
            directory.path(),
            "report.txt",
            Some(3),
            Some(modification_time),
            7,
        )
        .unwrap();
        let final_path = received.directory.child_path(&received.name);
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        commit_receive_file(received, None).unwrap();

        assert_eq!(fs::read(existing).unwrap(), b"existing");
        assert_eq!(final_path.file_name().unwrap(), "report (1).txt");
        assert_eq!(fs::read(&final_path).unwrap(), b"new");
        assert_eq!(
            fs::metadata(&final_path)
                .unwrap()
                .modified()
                .unwrap()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            modification_time
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(final_path).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
    }

    #[test]
    fn concurrent_destination_claim_is_retried_atomically() {
        let directory = tempfile::tempdir().unwrap();
        let mut first =
            create_receive_file(directory.path(), "report.txt", Some(3), None, 7).unwrap();
        let mut second =
            create_receive_file(directory.path(), "report.txt", Some(3), None, 7).unwrap();
        assert_ne!(first.temp_name, second.temp_name);
        assert_eq!(first.name, second.name);
        first.file.write_all(b"one").unwrap();
        first.written = 3;
        second.file.write_all(b"two").unwrap();
        second.written = 3;

        assert_eq!(commit_receive_file(first, None).unwrap(), "report.txt");
        assert_eq!(commit_receive_file(second, None).unwrap(), "report (1).txt");
        assert_eq!(
            fs::read(directory.path().join("report.txt")).unwrap(),
            b"one"
        );
        assert_eq!(
            fs::read(directory.path().join("report (1).txt")).unwrap(),
            b"two"
        );
    }

    #[test]
    fn publish_collision_retry_does_not_require_hard_links() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "report.txt", Some(3), None, 17).unwrap();
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let mut attempts = 0;

        let name = commit_receive_file_with(received, |source, destination| {
            attempts += 1;
            if attempts == 1 {
                return Err(std::io::Error::from(std::io::ErrorKind::AlreadyExists));
            }
            fs::rename(source, destination)
        })
        .unwrap();

        assert_eq!(attempts, 2);
        assert_eq!(name, "report (1).txt");
        assert_eq!(fs::read(directory.path().join(name)).unwrap(), b"new");
    }

    #[test]
    fn failed_publish_preserves_complete_staging_file_for_recovery() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "report.txt", Some(3), None, 18).unwrap();
        let staging = received.recoverable_path();
        received.file.write_all(b"new").unwrap();
        received.written = 3;

        let error = commit_receive_file_with(received, |_, _| {
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
        })
        .unwrap_err();

        assert!(matches!(
            &error,
            ZmodemError::Publish { partial_path, .. } if partial_path == &staging
        ));
        assert_eq!(fs::read(staging).unwrap(), b"new");
    }

    #[test]
    fn recovery_registration_fails_closed_when_sweeper_cannot_start() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "orphan.bin", Some(3), None, 701).unwrap();
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let staging_path = received.recoverable_path();

        let token =
            register_recovery_with_sweeper(StagingCleanup::from(received), Some(701), || false);

        assert!(token.is_none());
        let deadline = Instant::now() + Duration::from_secs(1);
        while staging_path.exists() {
            assert!(
                Instant::now() < deadline,
                "failed sweeper startup retained hidden recovery authority"
            );
            std::thread::yield_now();
        }
    }

    #[test]
    fn failed_recovery_sweeper_start_remains_retryable() {
        let started = Mutex::new(false);
        assert!(!start_recovery_sweeper_with(&started, || {
            Err(std::io::Error::other("injected spawn failure"))
        }));
        assert!(!*started.lock().unwrap());

        assert!(start_recovery_sweeper_with(&started, || {
            std::thread::Builder::new().spawn(|| {})
        }));
        assert!(*started.lock().unwrap());
    }

    #[test]
    fn prepublication_cleanup_never_touches_an_unowned_intended_name() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "claimed.txt", Some(3), None, 204).unwrap();
        let staging = received.recoverable_path();
        let intended = directory.path().join(&received.name);
        received.file.write_all(b"new").unwrap();
        fs::write(&intended, b"unrelated").unwrap();

        received.discard_staging();

        assert!(!staging.exists());
        assert_eq!(fs::read(intended).unwrap(), b"unrelated");
    }

    #[test]
    fn postpublish_backup_failure_explicitly_removes_the_final_alias() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "late.txt", Some(3), None, 196).unwrap();
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        received
            .directory
            .publish_file_noreplace(&received.file, &received.temp_name, &received.name)
            .unwrap();
        received.final_name_published = true;
        let final_path = directory.path().join(&received.name);
        assert_eq!(fs::read(&final_path).unwrap(), b"new");

        let error = preserve_or_cleanup_postpublish_with(received, |_, _, _| Err(None));

        assert!(matches!(error, ZmodemError::Io));
        wait_for_path_removal(&final_path);
    }

    #[test]
    fn postpublish_backup_failure_never_moves_a_replacement_final_name() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "replaced.txt", Some(3), None, 205).unwrap();
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        received
            .directory
            .publish_file_noreplace(&received.file, &received.temp_name, &received.name)
            .unwrap();
        received.final_name_published = true;
        let final_path = directory.path().join(&received.name);
        fs::remove_file(&final_path).unwrap();
        fs::write(&final_path, b"unrelated").unwrap();

        let error = preserve_or_cleanup_postpublish_with(received, |_, _, _| Err(None));

        assert!(matches!(error, ZmodemError::Io));
        assert_eq!(fs::read(final_path).unwrap(), b"unrelated");
    }

    #[cfg(unix)]
    #[test]
    fn backup_verification_failure_keeps_the_created_alias_in_cleanup_authority() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "late-link.txt", Some(3), None, 203).unwrap();
        received.file.write_all(b"new").unwrap();
        received.file.sync_all().unwrap();
        received.protect_publish_source().unwrap();
        let backup_name = received
            .directory
            .create_publish_backup(&received.temp_name, &received.file)
            .unwrap();
        let backup_path = directory.path().join(&backup_name);
        received
            .directory
            .publish_file_noreplace(&received.file, &received.temp_name, &received.name)
            .unwrap();
        received.final_name_published = true;
        let final_path = directory.path().join(&received.name);

        let error =
            preserve_or_cleanup_postpublish_with(received, |_, _, _| Err(Some(backup_name)));

        assert!(matches!(error, ZmodemError::Io));
        wait_for_path_removal(&final_path);
        wait_for_path_removal(&backup_path);
    }

    #[test]
    fn publish_failure_holds_close_phase_until_recovery_event_publication() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "late.txt", Some(3), None, 197).unwrap();
        received.owner_session_id = Some(197);
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let operation_epoch = Arc::new(AtomicU64::new(1));
        let publish_phase = Arc::new(AtomicU8::new(RECEIVE_COMMIT_IDLE));
        let publish_started_at = Arc::new(ParkingMutex::new(None));
        let cancellation = ReceiveCommitCancellation {
            operation_epoch: Arc::clone(&operation_epoch),
            expected_epoch: 1,
            publish_phase: Arc::clone(&publish_phase),
            publish_started_at: Arc::clone(&publish_started_at),
        };
        assert!(cancellation.begin_publish());

        let error = commit_receive_file_with_metadata(
            received,
            |_, _, _, _| Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)),
            apply_modification_time,
            Some(&cancellation),
        )
        .unwrap_err();
        let ZmodemError::Publish {
            recovery_token: Some(token),
            ..
        } = &error
        else {
            panic!("publish failure must retain owner-bound recovery authority")
        };
        assert_eq!(
            publish_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_PUBLISHING
        );

        let mut manager = ZmodemManager::for_session(
            197,
            operation_epoch,
            Arc::clone(&publish_phase),
            publish_started_at,
        );
        manager.state = TransferState::Receiving(receive_transfer(7));
        assert!(manager.fail(&error, None).events.is_empty());
        let effects = manager
            .timeout_if_needed(
                Instant::now() + DRAIN_QUIET_TIMEOUT + Duration::from_millis(1),
                None,
            )
            .unwrap();

        assert!(effects.receive_publish_pending);
        assert_eq!(effects.events[0].kind, "zmodem_failed");
        assert_eq!(effects.events[0].payload["recoveryToken"], token.as_str());
        assert_eq!(
            publish_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_PUBLISHING
        );
        assert_eq!(
            publish_phase.compare_exchange(
                RECEIVE_COMMIT_PUBLISHING,
                RECEIVE_COMMIT_IDLE,
                Ordering::AcqRel,
                Ordering::Acquire,
            ),
            Ok(RECEIVE_COMMIT_PUBLISHING)
        );
        assert!(dismiss_recovery(token, 197));
    }

    #[test]
    fn abandoned_publish_failure_revokes_its_unreachable_recovery_token() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "abandoned.txt", Some(3), None, 204).unwrap();
        received.owner_session_id = Some(204);
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let operation_epoch = Arc::new(AtomicU64::new(15));
        let publish_phase = Arc::new(AtomicU8::new(RECEIVE_COMMIT_IDLE));
        let cancellation = ReceiveCommitCancellation {
            operation_epoch: Arc::clone(&operation_epoch),
            expected_epoch: 15,
            publish_phase: Arc::clone(&publish_phase),
            publish_started_at: Arc::new(ParkingMutex::new(None)),
        };
        assert!(cancellation.begin_publish());
        let result = commit_receive_file_with_metadata(
            received,
            |_, _, _, _| Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)),
            apply_modification_time,
            Some(&cancellation),
        );
        let Err(ZmodemError::Publish {
            partial_path,
            recovery_token: Some(token),
        }) = &result
        else {
            panic!("failure must register recovery before the timeout race")
        };
        assert_eq!(
            resolve_recovery_path(token, 204),
            Some(partial_path.clone())
        );
        assert_eq!(
            publish_phase.compare_exchange(
                RECEIVE_COMMIT_PUBLISHING,
                RECEIVE_COMMIT_CANCELLED,
                Ordering::AcqRel,
                Ordering::Acquire,
            ),
            Ok(RECEIVE_COMMIT_PUBLISHING)
        );
        operation_epoch.fetch_add(1, Ordering::AcqRel);

        linearize_receive_publication_failure(&cancellation, &result);

        assert_eq!(resolve_recovery_path(token, 204), None);
        wait_for_path_removal(partial_path);
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn backup_creation_failure_keeps_original_complete_staging_authority() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "readonly.txt", Some(3), None, 194).unwrap();
        received.owner_session_id = Some(194);
        let staging = received.recoverable_path();
        received.file.write_all(b"new").unwrap();
        received.written = 3;

        let original_permissions = fs::metadata(directory.path()).unwrap().permissions();
        fs::set_permissions(directory.path(), fs::Permissions::from_mode(0o500)).unwrap();
        let result = commit_receive_file(received, None);
        fs::set_permissions(directory.path(), original_permissions).unwrap();

        let ZmodemError::Publish {
            partial_path,
            recovery_token: Some(token),
        } = result.unwrap_err()
        else {
            panic!("hard-link failure must retain original staging authority")
        };
        assert_eq!(partial_path, staging);
        assert_eq!(fs::read(&staging).unwrap(), b"new");
        assert!(!directory.path().join("readonly.txt").exists());
        assert_eq!(resolve_recovery_path(&token, 194), Some(staging));
        assert!(dismiss_recovery(&token, 194));
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn directory_sync_failure_prevents_completion_and_preserves_recovery() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "durable.txt", Some(3), None, 180).unwrap();
        received.owner_session_id = Some(180);
        let original_staging = received.recoverable_path();
        let final_path = directory.path().join("durable.txt");
        received.file.write_all(b"new").unwrap();
        received.written = 3;

        let error = commit_receive_file_with_metadata_and_sync(
            received,
            |directory, _, source, destination| {
                fs::rename(
                    directory.child_path(source),
                    directory.child_path(destination),
                )
            },
            apply_modification_time,
            (ReceiveDirectory::sync_published_file, |_| {
                Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
            }),
            None,
        )
        .unwrap_err();

        let ZmodemError::Publish {
            partial_path,
            recovery_token: Some(token),
        } = error
        else {
            panic!("directory sync failure must remain recoverable")
        };
        assert_ne!(partial_path, original_staging);
        assert!(!original_staging.exists());
        assert_eq!(fs::read(&partial_path).unwrap(), b"new");
        assert!(!final_path.exists());
        fs::write(&final_path, b"attacker").unwrap();
        assert_eq!(fs::read(&partial_path).unwrap(), b"new");
        assert_eq!(
            resolve_recovery_path(&token, 180),
            Some(partial_path.clone())
        );
        assert!(dismiss_recovery(&token, 180));
        wait_for_path_removal(&partial_path);
        assert_eq!(fs::read(final_path).unwrap(), b"attacker");
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn published_inode_sync_failure_prevents_completion_and_preserves_recovery() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "inode.txt", Some(3), None, 187).unwrap();
        received.owner_session_id = Some(187);
        let original_staging = received.recoverable_path();
        let final_path = directory.path().join("inode.txt");
        received.file.write_all(b"new").unwrap();
        received.written = 3;

        let error = commit_receive_file_with_metadata_and_sync(
            received,
            |directory, _, source, destination| {
                fs::rename(
                    directory.child_path(source),
                    directory.child_path(destination),
                )
            },
            apply_modification_time,
            (
                |_, _, _| Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)),
                ReceiveDirectory::sync,
            ),
            None,
        )
        .unwrap_err();

        let ZmodemError::Publish {
            partial_path,
            recovery_token: Some(token),
        } = error
        else {
            panic!("published inode sync failure must remain recoverable")
        };
        assert_ne!(partial_path, original_staging);
        assert!(!original_staging.exists());
        assert_eq!(fs::read(&partial_path).unwrap(), b"new");
        assert!(!final_path.exists());
        assert_eq!(
            resolve_recovery_path(&token, 187),
            Some(partial_path.clone())
        );
        assert!(dismiss_recovery(&token, 187));
        wait_for_path_removal(&partial_path);
        assert!(!final_path.exists());
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn atomic_publish_removes_staging_without_a_separate_unlink() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "unlink.txt", Some(3), None, 188).unwrap();
        let staging = received.recoverable_path();
        let final_path = directory.path().join("unlink.txt");
        received.file.write_all(b"new").unwrap();
        received.written = 3;

        let name = commit_receive_file_with(received, |source, destination| {
            fs::rename(source, destination)
        })
        .unwrap();

        assert_eq!(name, "unlink.txt");
        assert!(!staging.exists());
        assert_eq!(fs::read(final_path).unwrap(), b"new");
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn replacement_after_initial_verification_uses_independent_recovery_backup() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "replaced.txt", Some(3), None, 189).unwrap();
        received.owner_session_id = Some(189);
        let original_staging = received.recoverable_path();
        let final_path = directory.path().join("replaced.txt");
        received.file.write_all(b"new").unwrap();
        received.written = 3;

        let error = commit_receive_file_with_metadata_and_sync(
            received,
            |directory, _, source, destination| {
                fs::rename(
                    directory.child_path(source),
                    directory.child_path(destination),
                )
            },
            apply_modification_time,
            (ReceiveDirectory::sync_published_file, |_| {
                fs::remove_file(&final_path)?;
                fs::write(&final_path, b"attacker")
            }),
            None,
        )
        .unwrap_err();

        let ZmodemError::Publish {
            partial_path,
            recovery_token: Some(token),
        } = error
        else {
            panic!("a replaced final name must be rebuilt as recoverable staging")
        };
        assert_ne!(partial_path, original_staging);
        assert!(!original_staging.exists());
        assert_eq!(fs::read(&partial_path).unwrap(), b"new");
        assert_eq!(fs::read(&final_path).unwrap(), b"attacker");
        assert_eq!(resolve_recovery_path(&token, 189), Some(partial_path));
        assert!(dismiss_recovery(&token, 189));
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn publish_backup_is_a_read_only_prepublication_hard_link() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "authority.txt", Some(3), None, 190).unwrap();
        received.file.write_all(b"new").unwrap();
        received.file.sync_all().unwrap();
        received.protect_publish_source().unwrap();
        let backup_name = received
            .directory
            .create_publish_backup(&received.temp_name, &received.file)
            .unwrap();
        let backup = received
            .directory
            .open_existing_regular(&backup_name)
            .unwrap();
        assert_eq!(
            backup.metadata().unwrap().ino(),
            received.file.metadata().unwrap().ino()
        );
        assert_eq!(
            backup.metadata().unwrap().permissions().mode() & 0o777,
            0o400
        );

        received
            .directory
            .publish_file_noreplace(&received.file, &received.temp_name, "authority.txt")
            .unwrap();
        received
            .directory
            .remove_verified_child(&backup_name, &received.file)
            .unwrap();
        received
            .file
            .set_permissions(fs::Permissions::from_mode(0o600))
            .unwrap();
        assert!(!received.directory.child_path(&backup_name).exists());
        assert_eq!(
            fs::read(directory.path().join("authority.txt")).unwrap(),
            b"new"
        );
        assert_eq!(
            fs::metadata(directory.path().join("authority.txt"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn final_mode_restore_rejects_same_size_mutation_with_restored_mtime() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "trusted.txt", Some(3), None, 196).unwrap();
        received.file.write_all(b"new").unwrap();
        received.file.sync_all().unwrap();
        received.protect_publish_source().unwrap();
        received
            .directory
            .publish_file_noreplace(&received.file, &received.temp_name, "trusted.txt")
            .unwrap();
        let mut published = received
            .directory
            .sync_published_file(&received.file, "trusted.txt")
            .unwrap();
        published
            .accept_verified_link_removal(&received.directory, "trusted.txt")
            .unwrap();
        let trusted_modified = published.mutation.modified.unwrap();
        std::thread::sleep(Duration::from_millis(2));
        received.file.seek(SeekFrom::Start(0)).unwrap();
        received.file.write_all(b"bad").unwrap();
        received
            .file
            .set_times(FileTimes::new().set_modified(trusted_modified))
            .unwrap();

        assert!(
            published
                .restore_write_mode_and_revalidate(&received.directory, "trusted.txt")
                .is_err()
        );
        assert_eq!(
            fs::metadata(directory.path().join("trusted.txt"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o400
        );
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn staging_replacement_race_never_deletes_unrelated_content() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "identity.txt", Some(3), None, 191).unwrap();
        received.owner_session_id = Some(191);
        let original_staging = received.recoverable_path();
        let final_path = directory.path().join("identity.txt");
        received.file.write_all(b"new").unwrap();
        received.written = 3;

        let error = commit_receive_file_with_metadata_and_sync(
            received,
            |directory, _, source, destination| {
                let source = directory.child_path(source);
                fs::remove_file(&source)?;
                fs::write(&source, b"unrelated")?;
                fs::rename(source, directory.child_path(destination))
            },
            apply_modification_time,
            (
                ReceiveDirectory::sync_published_file,
                ReceiveDirectory::sync,
            ),
            None,
        )
        .unwrap_err();

        let ZmodemError::Publish {
            partial_path,
            recovery_token: Some(token),
        } = error
        else {
            panic!("the stable received inode must be rebuilt for recovery")
        };
        assert_ne!(partial_path, original_staging);
        assert!(!original_staging.exists());
        assert_eq!(fs::read(&partial_path).unwrap(), b"new");
        assert_eq!(fs::read(&final_path).unwrap(), b"unrelated");
        assert_eq!(resolve_recovery_path(&token, 191), Some(partial_path));
        assert!(dismiss_recovery(&token, 191));
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn replaced_staging_entry_is_never_published_as_received_content() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "report.txt", Some(3), None, 181).unwrap();
        received.owner_session_id = Some(181);
        let staging = received.recoverable_path();
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        fs::remove_file(&staging).unwrap();
        fs::write(&staging, b"attacker replacement").unwrap();

        assert!(matches!(
            commit_receive_file(received, None),
            Err(ZmodemError::Io)
        ));
        assert!(!directory.path().join("report.txt").exists());
        assert_eq!(fs::read(staging).unwrap(), b"attacker replacement");
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn recovery_token_rejects_replaced_or_symlinked_staging_entry() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "report.txt", Some(3), None, 182).unwrap();
        received.owner_session_id = Some(182);
        let staging = received.recoverable_path();
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let error = commit_receive_file_with(received, |_, _| {
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
        })
        .unwrap_err();
        let ZmodemError::Publish {
            recovery_token: Some(token),
            ..
        } = error
        else {
            panic!("publish failure must register a recovery token")
        };
        fs::remove_file(&staging).unwrap();
        std::os::unix::fs::symlink("/etc/hosts", &staging).unwrap();

        assert!(resolve_recovery_path(&token, 182).is_none());
    }

    #[test]
    fn recovery_fallback_authority_remains_owner_bound_and_expires() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "report.txt", Some(3), None, 183).unwrap();
        received.owner_session_id = Some(183);
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let created_at = Instant::now();
        let error = commit_receive_file_with(received, |_, _| {
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
        })
        .unwrap_err();
        let ZmodemError::Publish {
            recovery_token: Some(token),
            ..
        } = error
        else {
            panic!("publish failure must register a recovery token")
        };
        let staging = resolve_recovery_path(&token, 183).unwrap();
        assert!(resolve_recovery_path(&token, 183).is_some());
        assert!(resolve_tombstoned_recovery_at(&token, 183, created_at).is_some());
        assert!(resolve_tombstoned_recovery_at(&token, 184, created_at).is_none());
        assert!(resolve_tombstoned_recovery_at(&token, 183, created_at).is_some());
        let expired_at = Instant::now()
            .checked_sub(RECOVERY_ENTRY_TTL + Duration::from_millis(1))
            .unwrap();
        {
            let mut registry = recovery_registry().lock().unwrap();
            let entry = registry
                .entries
                .iter_mut()
                .find(|entry| entry.token == token)
                .unwrap();
            entry.created_at = expired_at;
            entry.reveal_lease_until = Some(expired_at);
            registry
                .closed_sessions
                .iter_mut()
                .find(|entry| entry.session_id == 183)
                .unwrap()
                .created_at = expired_at;
        }
        assert!(resolve_tombstoned_recovery(&token, 183).is_none());
        wait_for_path_removal(&staging);
    }

    #[test]
    fn recovery_registration_after_session_close_is_tombstoned_atomically() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "late.txt", Some(3), None, 184).unwrap();
        received.owner_session_id = Some(184);
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        tombstone_recovery_session(184);

        let error = commit_receive_file_with(received, |_, _| {
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
        })
        .unwrap_err();
        let ZmodemError::Publish {
            recovery_token: Some(token),
            ..
        } = error
        else {
            panic!("publish failure must register a recovery token")
        };

        let staging = resolve_tombstoned_recovery(&token, 184).unwrap();
        {
            let registry = recovery_registry().lock().unwrap();
            let entry = registry
                .entries
                .iter()
                .find(|entry| entry.token == token)
                .unwrap();
            assert!(
                entry
                    .reveal_lease_until
                    .is_some_and(|deadline| deadline > Instant::now())
            );
        }
        assert!(consume_recovery(&token, 184));
        assert!(resolve_tombstoned_recovery(&token, 184).is_none());
        assert!(!consume_recovery(&token, 184));
        assert_eq!(fs::read(staging).unwrap(), b"new");
    }

    #[test]
    fn ordinary_session_closes_cannot_evict_a_live_recovery_tombstone() {
        const OWNER: u64 = 49_000;
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "retained.txt", Some(3), None, OWNER).unwrap();
        received.owner_session_id = Some(OWNER);
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let error = commit_receive_file_with(received, |_, _| {
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
        })
        .unwrap_err();
        let ZmodemError::Publish {
            recovery_token: Some(token),
            ..
        } = error
        else {
            panic!("publish failure must register a recovery token")
        };
        tombstone_recovery_session(OWNER);

        for session_id in 50_000..50_000 + MAX_RECOVERY_ENTRIES as u64 + 8 {
            tombstone_recovery_session(session_id);
        }

        assert!(resolve_tombstoned_recovery(&token, OWNER).is_some());
        assert!(dismiss_recovery(&token, OWNER));
    }

    #[test]
    fn capacity_full_registration_replaces_only_the_now_orphaned_tombstone() {
        fn entry(directory: &Path, owner: u64) -> RecoveryEntry {
            let received =
                create_receive_file(directory, &format!("{owner}.txt"), Some(0), None, owner)
                    .unwrap();
            let ReceiveFile {
                file,
                directory,
                temp_name,
                _resource_lease,
                ..
            } = received;
            RecoveryEntry {
                token: format!("{owner:032x}"),
                owner_session_id: Some(owner),
                directory,
                temp_name,
                cleanup_names: Vec::new(),
                file,
                created_at: Instant::now(),
                reveal_lease_until: None,
                _file_resource_lease: _resource_lease,
            }
        }

        let directory = tempfile::tempdir().unwrap();
        let now = Instant::now();
        let mut registry = RecoveryRegistry::default();
        for owner in 60_000..60_000 + MAX_RECOVERY_ENTRIES as u64 {
            push_recovery_entry(
                &mut registry,
                entry(directory.path(), owner),
                MAX_RECOVERY_ENTRIES,
            );
            upsert_recovery_session_tombstone(&mut registry, owner, now);
        }
        let next_owner = 70_000;

        push_recovery_entry(
            &mut registry,
            entry(directory.path(), next_owner),
            MAX_RECOVERY_ENTRIES,
        );
        upsert_recovery_session_tombstone(&mut registry, next_owner, now);

        assert_eq!(registry.entries.len(), MAX_RECOVERY_ENTRIES);
        assert_eq!(registry.closed_sessions.len(), MAX_RECOVERY_ENTRIES);
        assert!(
            registry
                .closed_sessions
                .iter()
                .any(|entry| entry.session_id == next_owner)
        );
        assert!(registry.closed_sessions.iter().all(|tombstone| {
            registry
                .entries
                .iter()
                .any(|entry| entry.owner_session_id == Some(tombstone.session_id))
        }));
        while let Some(entry) = registry.entries.pop_front() {
            schedule_recovery_cleanup(entry);
        }
    }

    #[test]
    fn dismissing_recovery_deletes_the_hidden_staging_file() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "dismiss.txt", Some(3), None, 185).unwrap();
        received.owner_session_id = Some(185);
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let error = commit_receive_file_with(received, |_, _| {
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
        })
        .unwrap_err();
        let ZmodemError::Publish {
            recovery_token: Some(token),
            ..
        } = error
        else {
            panic!("publish failure must register a recovery token")
        };
        let staging = resolve_recovery_path(&token, 185).unwrap();

        assert!(dismiss_recovery(&token, 185));
        assert!(!dismiss_recovery(&token, 185));
        wait_for_path_removal(&staging);
    }

    #[test]
    fn recovery_capacity_eviction_deletes_the_oldest_hidden_file() {
        fn entry(directory: &Path, name: &str, token: &str) -> (RecoveryEntry, PathBuf) {
            let received = create_receive_file(directory, name, Some(0), None, 186).unwrap();
            let path = received.recoverable_path();
            let ReceiveFile {
                file,
                directory,
                temp_name,
                _resource_lease,
                ..
            } = received;
            (
                RecoveryEntry {
                    token: token.to_string(),
                    owner_session_id: Some(186),
                    directory,
                    temp_name,
                    cleanup_names: Vec::new(),
                    file,
                    created_at: Instant::now(),
                    reveal_lease_until: None,
                    _file_resource_lease: _resource_lease,
                },
                path,
            )
        }

        let directory = tempfile::tempdir().unwrap();
        let (first, first_path) = entry(directory.path(), "first.txt", "first");
        let (second, second_path) = entry(directory.path(), "second.txt", "second");
        let mut registry = RecoveryRegistry::default();
        push_recovery_entry(&mut registry, first, 1);
        push_recovery_entry(&mut registry, second, 1);

        wait_for_path_removal(&first_path);
        assert!(second_path.exists());
        schedule_recovery_cleanup(registry.entries.pop_front().unwrap());
        wait_for_path_removal(&second_path);
    }

    #[test]
    fn recovery_reveal_lease_prevents_ttl_and_capacity_eviction() {
        fn entry(directory: &Path, name: &str, token: &str) -> (RecoveryEntry, PathBuf) {
            let received = create_receive_file(directory, name, Some(0), None, 192).unwrap();
            let path = received.recoverable_path();
            let ReceiveFile {
                file,
                directory,
                temp_name,
                _resource_lease,
                ..
            } = received;
            (
                RecoveryEntry {
                    token: token.to_string(),
                    owner_session_id: Some(192),
                    directory,
                    temp_name,
                    cleanup_names: Vec::new(),
                    file,
                    created_at: Instant::now(),
                    reveal_lease_until: None,
                    _file_resource_lease: _resource_lease,
                },
                path,
            )
        }

        let directory = tempfile::tempdir().unwrap();
        let now = Instant::now();
        let (mut revealed, revealed_path) = entry(
            directory.path(),
            "revealed.txt",
            "00112233445566778899aabbccddeeff",
        );
        revealed.created_at = now
            .checked_sub(RECOVERY_ENTRY_TTL + Duration::from_secs(1))
            .unwrap();
        revealed.reveal_lease_until = now.checked_add(RECOVERY_REVEAL_LEASE);
        let (challenger, challenger_path) = entry(
            directory.path(),
            "challenger.txt",
            "11223344556677889900aabbccddeeff",
        );
        let mut registry = RecoveryRegistry::default();
        assert!(push_recovery_entry(&mut registry, revealed, 1));

        prune_recovery_registry(&mut registry, now);
        assert!(revealed_path.exists());
        assert!(!push_recovery_entry(&mut registry, challenger, 1));
        assert_eq!(registry.entries.len(), 1);
        assert_eq!(
            registry.entries.front().unwrap().token,
            "00112233445566778899aabbccddeeff"
        );
        assert!(revealed_path.exists());
        wait_for_path_removal(&challenger_path);

        let failure = failed_event(
            192,
            ZmodemDirection::Receive,
            &ZmodemError::Publish {
                partial_path: challenger_path,
                recovery_token: None,
            },
        );
        assert!(failure.payload.get("stagingPreserved").is_none());
        assert!(failure.payload.get("recoverablePartialName").is_none());
        assert!(failure.payload.get("recoveryToken").is_none());

        schedule_recovery_cleanup(registry.entries.pop_front().unwrap());
        wait_for_path_removal(&revealed_path);
    }

    #[test]
    fn failed_recovery_candidate_clone_does_not_extend_reveal_lease() {
        let directory = tempfile::tempdir().unwrap();
        let received =
            create_receive_file(directory.path(), "lease.txt", Some(0), None, 195).unwrap();
        let path = received.recoverable_path();
        let ReceiveFile {
            file,
            directory,
            temp_name,
            _resource_lease,
            ..
        } = received;
        let mut entry = RecoveryEntry {
            token: "33445566778899001122aabbccddeeff".to_string(),
            owner_session_id: Some(195),
            directory,
            temp_name,
            cleanup_names: Vec::new(),
            file,
            created_at: Instant::now(),
            reveal_lease_until: None,
            _file_resource_lease: _resource_lease,
        };
        let pool = receive_resource_pool();
        let usage = pool.usage();
        let remaining_fds = pool.limits.max_fds.saturating_sub(usage.fds);
        let blocker = pool.acquire(0, 0, remaining_fds).unwrap();

        assert!(lease_recovery_candidate(&mut entry, Instant::now()).is_none());
        assert!(entry.reveal_lease_until.is_none());

        drop(blocker);
        StagingCleanup::from(entry).discard();
        assert!(!path.exists());
    }

    #[test]
    fn failed_recovery_registration_schedules_complete_staging_cleanup() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "unregistered.txt", Some(3), None, 196).unwrap();
        received.owner_session_id = Some(196);
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let staging = received.recoverable_path();
        let pool = receive_resource_pool();
        let usage = pool.usage();
        let remaining_fds = pool.limits.max_fds.saturating_sub(usage.fds);
        let blocker = pool.acquire(0, 0, remaining_fds).unwrap();

        let error = preserved_publish_error(received);

        assert!(matches!(
            error,
            ZmodemError::Publish {
                recovery_token: None,
                ..
            }
        ));
        drop(blocker);
        wait_for_path_removal(&staging);
        wait_for_empty_directory(directory.path());
    }

    #[test]
    fn failed_mtime_update_preserves_complete_staging_file_for_recovery() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "report.txt", Some(3), Some(u64::MAX), 19)
                .unwrap();
        let staging = received.recoverable_path();
        received.file.write_all(b"new").unwrap();
        received.written = 3;

        let error = commit_receive_file_with_metadata(
            received,
            |directory, file, source, destination| {
                directory.publish_file_noreplace(file, source, destination)
            },
            |_, _| Err(ZmodemError::Io),
            None,
        )
        .unwrap_err();

        assert!(matches!(
            &error,
            ZmodemError::Publish { partial_path, .. } if partial_path == &staging
        ));
        assert_eq!(fs::read(staging).unwrap(), b"new");
        assert!(!directory.path().join("report.txt").exists());
    }

    #[test]
    fn cancellation_during_commit_metadata_never_publishes_the_file() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "cancelled.txt", Some(3), None, 20).unwrap();
        let staging = received.recoverable_path();
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let operation_epoch = Arc::new(AtomicU64::new(7));
        let cancellation = ReceiveCommitCancellation {
            operation_epoch: Arc::clone(&operation_epoch),
            expected_epoch: 7,
            publish_phase: Arc::new(AtomicU8::new(RECEIVE_COMMIT_IDLE)),
            publish_started_at: Arc::new(ParkingMutex::new(None)),
        };
        assert!(cancellation.begin_publish());
        let mut publish_attempted = false;
        let cancel_epoch = Arc::clone(&operation_epoch);

        let error = commit_receive_file_with_metadata(
            received,
            |_, _, _, _| {
                publish_attempted = true;
                Ok(())
            },
            move |_, _| {
                cancel_epoch.fetch_add(1, Ordering::AcqRel);
                Ok(())
            },
            Some(&cancellation),
        )
        .unwrap_err();

        assert!(matches!(error, ZmodemError::InvalidState));
        assert!(!publish_attempted);
        assert!(!directory.path().join("cancelled.txt").exists());
        wait_for_path_removal(&staging);
    }

    #[test]
    fn timeout_winning_after_rename_removes_the_unlinearized_final_file() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "timed-out.txt", Some(3), None, 201).unwrap();
        let staging = received.recoverable_path();
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let operation_epoch = Arc::new(AtomicU64::new(13));
        let publish_phase = Arc::new(AtomicU8::new(RECEIVE_COMMIT_IDLE));
        let cancellation = ReceiveCommitCancellation {
            operation_epoch: Arc::clone(&operation_epoch),
            expected_epoch: 13,
            publish_phase: Arc::clone(&publish_phase),
            publish_started_at: Arc::new(ParkingMutex::new(None)),
        };
        assert!(cancellation.begin_publish());
        let timed_out_cancellation = cancellation.clone();

        let error = commit_receive_file_with_metadata_and_sync(
            received,
            |directory, file, source, destination| {
                directory.publish_file_noreplace(file, source, destination)
            },
            apply_modification_time,
            (
                move |directory: &ReceiveDirectory, file: &File, name: &str| {
                    let published = directory.sync_published_file(file, name)?;
                    assert_eq!(
                        timed_out_cancellation.publish_phase.compare_exchange(
                            RECEIVE_COMMIT_PUBLISHING,
                            RECEIVE_COMMIT_CANCELLED,
                            Ordering::AcqRel,
                            Ordering::Acquire,
                        ),
                        Ok(RECEIVE_COMMIT_PUBLISHING)
                    );
                    timed_out_cancellation
                        .operation_epoch
                        .fetch_add(1, Ordering::AcqRel);
                    Ok(published)
                },
                |_| Ok(()),
            ),
            Some(&cancellation),
        )
        .unwrap_err();

        assert!(matches!(error, ZmodemError::InvalidState));
        assert_eq!(
            publish_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_CANCELLED
        );
        assert!(!directory.path().join("timed-out.txt").exists());
        wait_for_path_removal(&staging);
    }

    #[test]
    fn cancellation_claiming_idle_prevents_receive_publication() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "claimed.txt", Some(3), None, 21).unwrap();
        let staging = received.recoverable_path();
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let operation_epoch = Arc::new(AtomicU64::new(11));
        let publish_phase = Arc::new(AtomicU8::new(RECEIVE_COMMIT_IDLE));
        let cancellation = ReceiveCommitCancellation {
            operation_epoch: Arc::clone(&operation_epoch),
            expected_epoch: 11,
            publish_phase: Arc::clone(&publish_phase),
            publish_started_at: Arc::new(ParkingMutex::new(None)),
        };
        assert_eq!(
            publish_phase.compare_exchange(
                RECEIVE_COMMIT_IDLE,
                RECEIVE_COMMIT_CANCELLED,
                Ordering::AcqRel,
                Ordering::Acquire,
            ),
            Ok(RECEIVE_COMMIT_IDLE)
        );
        operation_epoch.fetch_add(1, Ordering::AcqRel);
        let mut publish_attempted = false;

        let error = commit_receive_file_with_metadata(
            received,
            |_, _, _, _| {
                publish_attempted = true;
                Ok(())
            },
            |_, _| Ok(()),
            Some(&cancellation),
        )
        .unwrap_err();

        assert!(matches!(error, ZmodemError::InvalidState));
        assert!(!publish_attempted);
        assert!(!directory.path().join("claimed.txt").exists());
        wait_for_path_removal(&staging);
    }

    #[test]
    fn successful_receive_publish_linearizes_result_before_event_publication() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "complete.txt", Some(3), None, 22).unwrap();
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let publish_phase = Arc::new(AtomicU8::new(RECEIVE_COMMIT_IDLE));
        let cancellation = ReceiveCommitCancellation {
            operation_epoch: Arc::new(AtomicU64::new(9)),
            expected_epoch: 9,
            publish_phase: Arc::clone(&publish_phase),
            publish_started_at: Arc::new(ParkingMutex::new(None)),
        };
        assert!(cancellation.begin_publish());

        let name = commit_receive_file_with_metadata(
            received,
            |directory, file, source, destination| {
                directory.publish_file_noreplace(file, source, destination)
            },
            apply_modification_time,
            Some(&cancellation),
        )
        .unwrap();

        assert_eq!(name, "complete.txt");
        assert_eq!(fs::read(directory.path().join(name)).unwrap(), b"new");
        assert_eq!(
            publish_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_RESULT_READY
        );
    }

    #[test]
    fn receive_publication_claims_phase_and_watchdog_before_worker_acquisition() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "queued.txt", Some(3), None, 202).unwrap();
        received.file.write_all(b"new").unwrap();
        received.written = 3;
        let operation_epoch = Arc::new(AtomicU64::new(14));
        let publish_phase = Arc::new(AtomicU8::new(RECEIVE_COMMIT_IDLE));
        let publish_started_at = Arc::new(ParkingMutex::new(None));
        let cancellation = ReceiveCommitCancellation {
            operation_epoch,
            expected_epoch: 14,
            publish_phase: Arc::clone(&publish_phase),
            publish_started_at: Arc::clone(&publish_started_at),
        };
        let held_worker_gate = TestSnapshotWorkerPermit::acquire();
        let starter =
            std::thread::spawn(move || start_receive_publication(202, received, cancellation));

        let deadline = Instant::now() + Duration::from_secs(1);
        while publish_phase.load(Ordering::Acquire) == RECEIVE_COMMIT_IDLE {
            assert!(
                Instant::now() < deadline,
                "publication phase was not claimed"
            );
            std::thread::yield_now();
        }
        assert_eq!(
            publish_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_PUBLISHING
        );
        assert!(publish_started_at.lock().is_some());

        drop(held_worker_gate);
        let mut publication = starter.join().unwrap().unwrap();
        let deadline = Instant::now() + Duration::from_secs(1);
        let message = loop {
            match publication.result.try_recv() {
                Ok(message) => break message,
                Err(mpsc::TryRecvError::Empty) => {
                    assert!(
                        Instant::now() < deadline,
                        "publication worker did not finish"
                    );
                    std::thread::yield_now();
                }
                Err(mpsc::TryRecvError::Disconnected) => panic!("publication result disconnected"),
            }
        };
        publication.worker.take().unwrap().join().unwrap();
        assert_eq!(message.result.unwrap(), "queued.txt");
        assert_eq!(
            publish_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_RESULT_READY
        );
    }

    #[test]
    fn transport_close_waits_for_bounded_receive_publication_result() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "complete.txt", Some(3), None, 23).unwrap();
        received.file.write_all(b"new").unwrap();
        received.written = 3;

        let operation_epoch = Arc::new(AtomicU64::new(12));
        let publish_phase = Arc::new(AtomicU8::new(RECEIVE_COMMIT_IDLE));
        let publish_started_at = Arc::new(ParkingMutex::new(None));
        let cancellation = ReceiveCommitCancellation {
            operation_epoch: Arc::clone(&operation_epoch),
            expected_epoch: 12,
            publish_phase: Arc::clone(&publish_phase),
            publish_started_at: Arc::clone(&publish_started_at),
        };
        let publication = start_receive_publication(23, received, cancellation.clone()).unwrap();
        let mut transfer = receive_transfer(23);
        transfer.current_offer = Some(("complete.txt".to_string(), Some(3), None));
        transfer.commit_cancellation = Some(cancellation);
        transfer.publication = Some(publication);
        let mut manager = ZmodemManager::for_session(
            7,
            operation_epoch,
            Arc::clone(&publish_phase),
            publish_started_at,
        );
        manager.state = TransferState::Receiving(transfer);

        let boundary = manager.transport_closed(true);
        assert!(boundary.events.is_empty());
        assert!(matches!(manager.state, TransferState::Receiving(_)));

        let file_result = (0..100)
            .find_map(|_| {
                let effects = manager.timeout_if_needed(Instant::now(), None);
                if effects.is_none() {
                    std::thread::sleep(Duration::from_millis(5));
                }
                effects
            })
            .expect("publication worker must report through the closed transport");
        assert_eq!(file_result.events[0].kind, "zmodem_file_completed");
        assert_eq!(
            publish_phase.load(Ordering::Acquire),
            RECEIVE_COMMIT_RESULT_READY
        );
        assert!(matches!(manager.state, TransferState::Draining(_)));

        let terminal = manager.transport_closed(true);
        assert_eq!(terminal.events[0].kind, "zmodem_failed");
        assert_eq!(terminal.events[0].payload["reason"], "protocol_error");
        assert!(terminal.receive_publish_pending);
        assert_eq!(
            fs::read(directory.path().join("complete.txt")).unwrap(),
            b"new"
        );
    }

    #[test]
    fn ingest_preserves_file_completion_when_transport_closes_during_publication() {
        let operation_epoch = Arc::new(AtomicU64::new(24));
        let publish_phase = Arc::new(AtomicU8::new(RECEIVE_COMMIT_PUBLISHING));
        let publish_started_at = Arc::new(ParkingMutex::new(Some(Instant::now())));
        let (result_tx, result_rx) = mpsc::channel();
        let worker_phase = Arc::clone(&publish_phase);
        let worker = std::thread::spawn(move || {
            worker_phase.store(RECEIVE_COMMIT_RESULT_READY, Ordering::Release);
            result_tx
                .send(ReceivePublicationResult {
                    result: Ok("complete.txt".to_string()),
                    size: 3,
                    finished_at: Instant::now(),
                })
                .unwrap();
        });
        let mut transfer = receive_transfer(24);
        transfer.current_offer = Some(("complete.txt".to_string(), Some(3), None));
        transfer.publication = Some(ReceivePublication {
            result: result_rx,
            worker: Some(worker),
        });
        let mut manager =
            ZmodemManager::for_session(24, operation_epoch, publish_phase, publish_started_at);
        manager.state = TransferState::Receiving(transfer);

        let boundary = manager.transport_closed(true);
        assert!(boundary.events.is_empty());

        let deadline = Instant::now() + Duration::from_secs(1);
        let published = loop {
            match manager.ingest(&[], &mut Vec::new()) {
                Ok(effects) if !effects.events.is_empty() => break effects,
                Ok(_) => {}
                Err(error) => panic!("completion batch was discarded: {error}"),
            }
            assert!(
                Instant::now() < deadline,
                "publication result was not reaped"
            );
            std::thread::yield_now();
        };
        assert_eq!(published.events.len(), 1);
        assert_eq!(published.events[0].kind, "zmodem_file_completed");
        assert!(published.receive_publish_pending);
        assert!(matches!(manager.state, TransferState::Draining(_)));

        let terminal = manager.transport_closed(true);
        assert_eq!(terminal.events.len(), 1);
        assert_eq!(terminal.events[0].kind, "zmodem_failed");
        assert!(terminal.receive_publish_pending);
    }

    #[test]
    fn protocol_failure_reaps_inflight_receive_publication_before_terminal_failure() {
        let operation_epoch = Arc::new(AtomicU64::new(30));
        let publish_phase = Arc::new(AtomicU8::new(RECEIVE_COMMIT_PUBLISHING));
        let publish_started_at = Arc::new(ParkingMutex::new(Some(Instant::now())));
        let (result_tx, result_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let worker_phase = Arc::clone(&publish_phase);
        let worker = std::thread::spawn(move || {
            release_rx.recv().unwrap();
            worker_phase.store(RECEIVE_COMMIT_RESULT_READY, Ordering::Release);
            result_tx
                .send(ReceivePublicationResult {
                    result: Ok("complete.txt".to_string()),
                    size: 3,
                    finished_at: Instant::now(),
                })
                .unwrap();
        });
        let mut transfer = receive_transfer(30);
        transfer.current_offer = Some(("complete.txt".to_string(), Some(3), None));
        transfer.publication = Some(ReceivePublication {
            result: result_rx,
            worker: Some(worker),
        });
        let mut manager = ZmodemManager::for_session(
            30,
            operation_epoch,
            Arc::clone(&publish_phase),
            publish_started_at,
        );
        manager.state = TransferState::Receiving(transfer);

        let immediate = manager.fail(
            &ZmodemError::Protocol("wire buffer overflow".to_string()),
            None,
        );
        assert!(immediate.events.is_empty());
        assert!(matches!(
            &manager.state,
            TransferState::Receiving(transfer)
                if transfer.publication.is_some() && transfer.publication_failure.is_some()
        ));
        manager
            .ingest(&vec![0x55; 300_000], &mut Vec::new())
            .unwrap();
        assert!(matches!(manager.state, TransferState::Receiving(_)));

        release_tx.send(()).unwrap();
        let deadline = Instant::now() + Duration::from_secs(1);
        let published = loop {
            if let Some(effects) = manager.timeout_if_needed(Instant::now(), None) {
                break effects;
            }
            assert!(
                Instant::now() < deadline,
                "publication result was not reaped"
            );
            std::thread::yield_now();
        };
        assert_eq!(published.events.len(), 1);
        assert_eq!(published.events[0].kind, "zmodem_file_completed");
        assert!(published.receive_publish_pending);
        assert!(matches!(manager.state, TransferState::Draining(_)));

        let terminal = manager
            .timeout_if_needed(
                Instant::now() + DRAIN_QUIET_TIMEOUT + Duration::from_millis(1),
                None,
            )
            .unwrap();
        assert_eq!(terminal.events.len(), 1);
        assert_eq!(terminal.events[0].kind, "zmodem_failed");
        assert!(terminal.receive_publish_pending);
    }

    #[cfg(unix)]
    #[test]
    fn receive_publish_stays_bound_to_selected_directory_after_path_replacement() {
        let parent = tempfile::tempdir().unwrap();
        let selected = parent.path().join("selected");
        let moved = parent.path().join("moved");
        fs::create_dir(&selected).unwrap();

        let mut received = create_receive_file(&selected, "report.txt", Some(3), None, 20).unwrap();
        received.file.write_all(b"new").unwrap();
        received.written = 3;

        fs::rename(&selected, &moved).unwrap();
        fs::create_dir(&selected).unwrap();
        fs::write(selected.join("report.txt"), b"replacement-directory").unwrap();

        assert_eq!(commit_receive_file(received, None).unwrap(), "report.txt");
        assert_eq!(fs::read(moved.join("report.txt")).unwrap(), b"new");
        assert_eq!(
            fs::read(selected.join("report.txt")).unwrap(),
            b"replacement-directory"
        );
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    #[test]
    fn recoverable_staging_path_tracks_a_renamed_selected_directory() {
        let parent = tempfile::tempdir().unwrap();
        let selected = parent.path().join("selected");
        let moved = parent.path().join("moved");
        fs::create_dir(&selected).unwrap();

        let mut received = create_receive_file(&selected, "report.txt", Some(3), None, 21).unwrap();
        received.owner_session_id = Some(41);
        let temp_name = received.temp_name.clone();
        received.file.write_all(b"new").unwrap();
        received.written = 3;

        fs::rename(&selected, &moved).unwrap();
        fs::create_dir(&selected).unwrap();

        let error = commit_receive_file_with(received, |_, _| {
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
        })
        .unwrap_err();
        let expected = moved.join(temp_name);

        let ZmodemError::Publish {
            partial_path,
            recovery_token,
        } = error
        else {
            panic!("expected recoverable publish failure")
        };
        assert_eq!(
            fs::canonicalize(&partial_path).unwrap(),
            fs::canonicalize(&expected).unwrap()
        );
        assert_eq!(fs::read(partial_path).unwrap(), b"new");
        let recovery_token = recovery_token.unwrap();
        assert!(resolve_recovery_path(&recovery_token, 42).is_none());
        let recovery_path = resolve_recovery_path(&recovery_token, 41).unwrap();
        assert_eq!(
            fs::canonicalize(recovery_path).unwrap(),
            fs::canonicalize(&expected).unwrap()
        );
        assert!(!selected.read_dir().unwrap().any(|entry| entry.is_ok()));
    }

    #[cfg(unix)]
    #[test]
    fn partial_cleanup_stays_bound_to_selected_directory_after_path_replacement() {
        let parent = tempfile::tempdir().unwrap();
        let selected = parent.path().join("selected");
        let moved = parent.path().join("moved");
        fs::create_dir(&selected).unwrap();

        let received = create_receive_file(&selected, "report.txt", Some(3), None, 22).unwrap();
        let temp_name = received.temp_name.clone();
        fs::rename(&selected, &moved).unwrap();
        fs::create_dir(&selected).unwrap();
        fs::write(selected.join(&temp_name), b"unrelated").unwrap();

        received.discard_staging();

        assert!(!moved.join(&temp_name).exists());
        assert_eq!(fs::read(selected.join(temp_name)).unwrap(), b"unrelated");
    }

    #[cfg(unix)]
    #[test]
    fn partial_cleanup_never_unlinks_a_replacement_staging_entry() {
        let directory = tempfile::tempdir().unwrap();
        let received =
            create_receive_file(directory.path(), "cleanup.txt", Some(3), None, 193).unwrap();
        let staging = received.recoverable_path();
        fs::remove_file(&staging).unwrap();
        fs::write(&staging, b"unrelated").unwrap();

        received.discard_staging();

        assert_eq!(fs::read(staging).unwrap(), b"unrelated");
    }

    #[test]
    fn publish_failure_event_reports_only_a_bounded_recoverable_basename() {
        let directory = tempfile::tempdir().unwrap();
        let staging = directory.path().join(".payload.ianvs-part");
        fs::write(&staging, b"complete").unwrap();
        let mut manager = ZmodemManager {
            state: TransferState::Receiving(receive_transfer(7)),
            next_id: 8,
            failure_passthrough: Vec::new(),
            owner_session_id: None,
            operation_epoch: None,
            receive_commit_phase: None,
            receive_publish_started_at: None,
        };
        let error = ZmodemError::Publish {
            partial_path: staging.clone(),
            recovery_token: Some("0123456789abcdef0123456789abcdef".to_string()),
        };

        assert!(manager.fail(&error, None).events.is_empty());
        let terminal = manager.transport_closed(true);

        assert_eq!(terminal.events[0].payload["reason"], "publish_failed");
        assert_eq!(
            terminal.events[0].payload["recoverablePartialName"],
            ".payload.ianvs-part"
        );
        assert_eq!(terminal.events[0].payload["stagingPreserved"], true);
        assert_eq!(
            terminal.events[0].payload["recoveryToken"],
            "0123456789abcdef0123456789abcdef"
        );
        assert!(
            terminal.events[0]
                .payload
                .get("recoverablePartialPath")
                .is_none()
        );
        assert!(
            !terminal.events[0]
                .payload
                .to_string()
                .contains(directory.path().to_string_lossy().as_ref())
        );
        assert_eq!(fs::read(staging).unwrap(), b"complete");

        let long_name = format!("{}.part", "a".repeat(MAX_FILENAME_BYTES * 2));
        let bounded = failed_event(
            7,
            ZmodemDirection::Receive,
            &ZmodemError::Publish {
                partial_path: Path::new("/private/secret").join(long_name),
                recovery_token: None,
            },
        );
        assert!(bounded.payload.get("recoverablePartialName").is_none());
        assert!(bounded.payload.get("stagingPreserved").is_none());
        assert!(bounded.payload.get("recoveryToken").is_none());
        assert!(!bounded.payload.to_string().contains("/private/secret"));
    }

    #[test]
    fn unknown_receive_size_is_limited_dynamically_and_can_commit() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "stream.bin", None, None, 9).unwrap();
        received.file.write_all(b"streamed").unwrap();
        received.written = 8;

        assert_eq!(commit_receive_file(received, None).unwrap(), "stream.bin");
        assert_eq!(
            fs::read(directory.path().join("stream.bin")).unwrap(),
            b"streamed"
        );
    }

    #[test]
    fn announced_receive_size_is_an_estimate_for_a_growing_file() {
        let directory = tempfile::tempdir().unwrap();
        let mut received =
            create_receive_file(directory.path(), "growing.bin", Some(3), None, 91).unwrap();
        received.file.write_all(b"growing").unwrap();
        received.written = 7;

        assert_eq!(commit_receive_file(received, None).unwrap(), "growing.bin");
        assert_eq!(
            fs::read(directory.path().join("growing.bin")).unwrap(),
            b"growing"
        );
    }

    #[test]
    fn receive_accept_failure_is_transactional() {
        let directory = tempfile::tempdir().unwrap();
        let mut transfer = receive_transfer(7);
        transfer.current_offer = Some(("payload.bin".to_string(), Some(3), None));
        let mut manager = ZmodemManager {
            state: TransferState::Receiving(transfer),
            next_id: 8,
            failure_passthrough: Vec::new(),
            owner_session_id: None,
            operation_epoch: None,
            receive_commit_phase: None,
            receive_publish_started_at: None,
        };
        let mut writer = Vec::new();

        manager
            .accept_receive(7, directory.path(), &mut writer)
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        let error = loop {
            match manager.finish_receive_preparation(&mut writer, &mut ZmodemEffects::default()) {
                Ok(false) if Instant::now() < deadline => {
                    std::thread::sleep(Duration::from_millis(1));
                }
                Ok(false) => panic!("receive preparation worker did not finish"),
                Ok(true) => panic!("invalid receiver state unexpectedly accepted a file"),
                Err(error) => break error,
            }
        };
        assert!(matches!(error, ZmodemError::Protocol(_)));
        let TransferState::Receiving(transfer) = &manager.state else {
            panic!("failed acceptance must preserve the pending transfer");
        };
        assert!(transfer.destination.is_none());
        assert!(transfer.current_file.is_none());
        wait_for_empty_directory(directory.path());
    }

    #[test]
    fn cancel_cleans_partial_even_when_can_write_fails() {
        let directory = tempfile::tempdir().unwrap();
        let mut transfer = receive_transfer(7);
        let partial =
            create_receive_file(directory.path(), "payload.bin", Some(3), None, 7).unwrap();
        let temp_path = partial.recoverable_path();
        transfer.current_file = Some(partial);
        let mut manager = ZmodemManager {
            state: TransferState::Receiving(transfer),
            next_id: 8,
            failure_passthrough: Vec::new(),
            owner_session_id: None,
            operation_epoch: None,
            receive_commit_phase: None,
            receive_publish_started_at: None,
        };

        let effects = manager.cancel(7, &mut FailingWriter).unwrap();

        assert!(effects.events.is_empty());
        wait_for_path_removal(&temp_path);
        assert!(matches!(manager.state, TransferState::Draining(_)));

        let effects = manager.transport_closed(true);
        assert_eq!(effects.events[0].kind, "zmodem_cancelled");
        assert!(!manager.is_active());
    }

    #[test]
    fn trusted_eof_mid_receive_fails_and_schedules_partial_removal() {
        let directory = tempfile::tempdir().unwrap();
        let mut transfer = receive_transfer(7);
        let mut partial =
            create_receive_file(directory.path(), "payload.bin", Some(3), None, 7).unwrap();
        partial.file.write_all(b"x").unwrap();
        partial.written = 1;
        let temp_path = partial.recoverable_path();
        transfer.current_file = Some(partial);
        let mut manager = ZmodemManager {
            state: TransferState::Receiving(transfer),
            next_id: 8,
            failure_passthrough: Vec::new(),
            owner_session_id: None,
            operation_epoch: None,
            receive_commit_phase: None,
            receive_publish_started_at: None,
        };

        let effects = manager.transport_closed(true);

        assert_eq!(effects.events[0].kind, "zmodem_failed");
        assert_eq!(effects.events[0].payload["reason"], "protocol_error");
        wait_for_path_removal(&temp_path);
        assert!(!manager.is_active());
    }

    #[test]
    fn trusted_eof_after_receiver_zfin_completes_without_final_oo() {
        let directory = tempfile::tempdir().unwrap();
        let mut manager = receiver_waiting_for_final_oo(directory.path());

        let effects = manager.transport_closed(true);

        assert_eq!(effects.events[0].kind, "zmodem_completed");
        assert_eq!(effects.events[0].payload["completedFiles"], 1);
        assert_eq!(effects.events[0].payload["skippedFiles"], 0);
        assert_eq!(fs::read(directory.path().join("empty.bin")).unwrap(), b"");
        assert!(!manager.is_active());
    }

    #[test]
    fn trusted_eof_recovers_plain_terminal_output_while_waiting_for_oo() {
        let directory = tempfile::tempdir().unwrap();
        let mut manager = receiver_waiting_for_final_oo(directory.path());
        let marker = b"IANVS_ZMODEM_RECEIVE_MD5=abc_DONE";

        let waiting = manager.ingest(marker, &mut Vec::new()).unwrap();
        assert!(waiting.passthrough.is_empty());
        assert!(waiting.events.is_empty());
        assert!(manager.is_active());

        let completed = manager.transport_closed(true);

        assert_eq!(completed.passthrough, marker);
        assert_eq!(completed.events[0].kind, "zmodem_completed");
        assert!(!manager.is_active());
    }

    #[test]
    fn final_oo_is_filtered_but_same_chunk_terminal_marker_is_preserved() {
        let directory = tempfile::tempdir().unwrap();
        let mut manager = receiver_waiting_for_final_oo(directory.path());
        let marker = b"\r\nIANVS_ZMODEM_RECEIVE_MD5=abc_DONE\r\n";
        let mut wire = b"OO".to_vec();
        wire.extend_from_slice(marker);

        let completed = manager.ingest(&wire, &mut Vec::new()).unwrap();

        assert_eq!(completed.passthrough, marker);
        assert_eq!(completed.events[0].kind, "zmodem_completed");
        assert!(!manager.is_active());
    }

    #[test]
    fn completed_remainder_is_rescanned_for_a_contiguous_transfer_header() {
        let directory = tempfile::tempdir().unwrap();
        let mut manager = receiver_waiting_for_final_oo(directory.path());
        let next_header = hex_header(1, [0, 0, 0, 0x23]);
        let mut wire = b"OO".to_vec();
        wire.extend_from_slice(&next_header);

        let effects = manager.ingest(&wire, &mut Vec::new()).unwrap();

        assert!(effects.passthrough.is_empty());
        assert_eq!(effects.events[0].kind, "zmodem_completed");
        assert_eq!(effects.events[1].kind, "zmodem_detected");
        assert_eq!(effects.events[1].payload["direction"], "send");
        assert!(matches!(manager.state, TransferState::AwaitingSend(_)));
    }

    #[test]
    fn receiver_missing_final_oo_completes_after_bounded_retry_wait() {
        let directory = tempfile::tempdir().unwrap();
        let mut manager = receiver_waiting_for_final_oo(directory.path());
        let marker = b"terminal output held while waiting for OO";
        assert!(
            manager
                .ingest(marker, &mut Vec::new())
                .unwrap()
                .passthrough
                .is_empty()
        );
        let first_retry = match &manager.state {
            TransferState::Receiving(transfer) => transfer.protocol_retry_at,
            _ => unreachable!(),
        };
        let mut writer = Vec::new();
        let mut completed = None;
        for retry in 0..10_u32 {
            let now = first_retry + PROTOCOL_RETRY_INTERVAL.saturating_mul(retry);
            let effects = manager
                .timeout_if_needed(now, Some(&mut writer))
                .expect("each final handshake deadline should be handled");
            if !effects.events.is_empty() {
                completed = Some(effects);
                break;
            }
            assert!(effects.events.is_empty());
            assert!(manager.is_active());
        }

        let completed = completed.expect("the bounded final handshake wait should complete");
        assert_eq!(completed.events[0].kind, "zmodem_completed");
        assert_eq!(completed.passthrough, marker);
        assert!(!manager.is_active());
    }

    #[test]
    fn sustained_terminal_output_cannot_postpone_missing_final_oo_completion() {
        let directory = tempfile::tempdir().unwrap();
        let mut manager = receiver_waiting_for_final_oo(directory.path());
        let marker = b"background shell output while OO is missing\n";
        let mut expected_passthrough = Vec::new();
        let mut writer = Vec::new();
        let mut completed = None;

        for _ in 0..10 {
            let waiting = manager.ingest(marker, &mut writer).unwrap();
            assert!(waiting.passthrough.is_empty());
            expected_passthrough.extend_from_slice(marker);
            let retry_at = match &manager.state {
                TransferState::Receiving(transfer) => transfer.protocol_retry_at,
                _ => break,
            };
            let effects = manager
                .timeout_if_needed(retry_at, Some(&mut writer))
                .expect("terminal bytes must not postpone the closing retry");
            if !effects.events.is_empty() {
                completed = Some(effects);
                break;
            }
        }

        let completed = completed.expect("missing OO must complete on the bounded retry budget");
        assert_eq!(completed.events[0].kind, "zmodem_completed");
        assert_eq!(completed.passthrough, expected_passthrough);
        assert!(!manager.is_active());
    }

    #[test]
    fn peer_skip_emits_file_event_continues_batch_and_reports_statistics() {
        let directory = tempfile::tempdir().unwrap();
        let first = directory.path().join("first.bin");
        let second = directory.path().join("second.bin");
        fs::write(&first, b"first").unwrap();
        fs::write(&second, b"second").unwrap();
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        manager
            .ingest(&hex_header(1, [0, 0, 0, 0x23]), &mut writer)
            .unwrap();
        accept_send_ready(&mut manager, 1, &[first, second], &mut writer);

        let first_skip = manager.ingest(&hex_header(5, [0; 4]), &mut writer).unwrap();
        assert_eq!(first_skip.events[0].kind, "zmodem_file_skipped");
        assert_eq!(first_skip.events[0].payload["filename"], "first.bin");
        assert_eq!(first_skip.events[0].payload["skippedFiles"], 1);
        let TransferState::Sending(transfer) = &manager.state else {
            panic!("batch should continue after first ZSKIP")
        };
        assert_eq!(transfer.current.as_ref().unwrap().name, "second.bin");

        let second_skip = manager.ingest(&hex_header(5, [0; 4]), &mut writer).unwrap();
        assert_eq!(second_skip.events[0].kind, "zmodem_file_skipped");
        let mut zfin = hex_header(8, [0; 4]);
        zfin.extend_from_slice(b"\r\n");
        let completed = manager.ingest(&zfin, &mut writer).unwrap();
        let completed = completed
            .events
            .iter()
            .find(|event| event.kind == "zmodem_completed")
            .expect("session should complete after the skipped batch");
        assert_eq!(completed.payload["completedFiles"], 0);
        assert_eq!(completed.payload["skippedFiles"], 2);
        assert!(!manager.is_active());
    }

    #[test]
    fn late_zskip_and_zrpos_rewind_keep_send_progress_monotonic() {
        const FIRST_SIZE: usize = 32 * 1024;
        const SECOND_SIZE: usize = 24 * 1024;
        let directory = tempfile::tempdir().unwrap();
        let first = directory.path().join("first.bin");
        let second = directory.path().join("second.bin");
        fs::write(&first, vec![b'a'; FIRST_SIZE]).unwrap();
        fs::write(&second, vec![b'b'; SECOND_SIZE]).unwrap();
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        manager
            .ingest(&hex_header(1, [0, 0, 0, 0x23]), &mut writer)
            .unwrap();
        accept_send_ready(&mut manager, 1, &[first, second], &mut writer);

        let TransferState::Sending(transfer) = &mut manager.state else {
            panic!("send should be active")
        };
        transfer.last_progress = Instant::now() - PROGRESS_INTERVAL;

        let first_pass = manager.ingest(&hex_header(9, [0; 4]), &mut writer).unwrap();
        let first_progress = first_pass
            .events
            .iter()
            .filter(|event| event.kind == "zmodem_progress")
            .filter_map(|event| event.payload["bytesTransferred"].as_u64())
            .collect::<Vec<_>>();
        assert!(!first_progress.is_empty());
        let TransferState::Sending(transfer) = &manager.state else {
            panic!("send should remain active")
        };
        let first_high_water = transfer.current_position;
        assert!(first_high_water > 0);
        assert!(first_high_water < FIRST_SIZE as u64);

        manager.ingest(&hex_header(9, [0; 4]), &mut writer).unwrap();
        let TransferState::Sending(transfer) = &manager.state else {
            panic!("send should remain active after rewind")
        };
        assert_eq!(transfer.current_position, first_high_water);

        let skipped = manager.ingest(&hex_header(5, [0; 4]), &mut writer).unwrap();
        assert!(
            skipped
                .events
                .iter()
                .any(|event| event.kind == "zmodem_file_skipped")
        );
        let TransferState::Sending(transfer) = &mut manager.state else {
            panic!("batch should continue after late ZSKIP")
        };
        assert_eq!(transfer.completed_bytes, first_high_water);
        assert_eq!(transfer.current_position, 0);
        assert_eq!(transfer.current.as_ref().unwrap().name, "second.bin");
        transfer.last_progress = Instant::now() - PROGRESS_INTERVAL;

        let second_pass = manager.ingest(&hex_header(9, [0; 4]), &mut writer).unwrap();
        let second_progress = second_pass
            .events
            .iter()
            .filter(|event| event.kind == "zmodem_progress")
            .filter_map(|event| event.payload["bytesTransferred"].as_u64())
            .collect::<Vec<_>>();
        assert!(!second_progress.is_empty());

        let observed = first_progress
            .into_iter()
            .chain(second_progress)
            .collect::<Vec<_>>();
        assert!(observed.windows(2).all(|values| values[0] <= values[1]));
        assert!(observed.last().copied().unwrap() >= first_high_water);
    }

    #[test]
    fn repeated_zrpos_rewinds_cannot_extend_the_send_progress_deadline() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("payload.bin");
        fs::write(&path, vec![b'x'; 32 * 1024]).unwrap();
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        manager
            .ingest(&hex_header(1, [0, 0, 0, 0x23]), &mut writer)
            .unwrap();
        accept_send_ready(&mut manager, 1, &[path], &mut writer);
        manager.ingest(&hex_header(9, [0; 4]), &mut writer).unwrap();
        let deadline = Instant::now() + Duration::from_millis(50);
        let TransferState::Sending(transfer) = &mut manager.state else {
            panic!("send should remain active")
        };
        assert!(transfer.current_position > 0);
        transfer.progress_deadline = deadline;

        for _ in 0..8 {
            manager.ingest(&hex_header(9, [0; 4]), &mut writer).unwrap();
            let TransferState::Sending(transfer) = &manager.state else {
                panic!("rewind must not finish the send")
            };
            assert_eq!(transfer.progress_deadline, deadline);
        }

        let effects = manager
            .timeout_if_needed(deadline, Some(&mut writer))
            .expect("the original hard deadline must still expire");
        assert!(effects.events.is_empty());
        assert!(matches!(manager.state, TransferState::Draining(_)));
    }

    #[test]
    fn protocol_failure_quarantines_residual_payload_until_drain_boundary() {
        let mut manager = ZmodemManager::default();
        let error = manager
            .ingest(&hex_header(0, [0; 4]), &mut FailingWriter)
            .expect_err("receiver handshake write must fail");
        let effects = manager.fail(&error, Some(&mut FailingWriter));
        assert!(effects.events.is_empty());
        assert!(matches!(manager.state, TransferState::Draining(_)));

        let quarantined = manager
            .ingest(b"binary payload\0\x18garbage", &mut Vec::new())
            .unwrap();
        assert!(quarantined.passthrough.is_empty());
        let boundary = Instant::now() + DRAIN_QUIET_TIMEOUT + Duration::from_millis(1);
        let effects = manager.timeout_if_needed(boundary, None).unwrap();
        assert_eq!(effects.events[0].kind, "zmodem_failed");
        assert!(!manager.is_active());

        let plain = manager.ingest(b"prompt$ ", &mut Vec::new()).unwrap();
        assert_eq!(plain.passthrough, b"prompt$ ");
    }

    #[test]
    fn protocol_failure_preserves_plain_bytes_before_the_detection_boundary() {
        let mut manager = ZmodemManager::default();
        let mut bytes = b"prompt before transfer\r\n".to_vec();
        bytes.extend_from_slice(&hex_header(0, [0; 4]));

        manager
            .ingest(&bytes, &mut FailingWriter)
            .expect_err("receiver handshake write must fail");

        assert_eq!(
            manager.take_failure_passthrough(),
            b"prompt before transfer\r\n"
        );
    }

    #[test]
    fn draining_sustained_payload_hits_a_non_refreshable_hard_deadline() {
        let mut manager = ZmodemManager::default();
        let error = manager
            .ingest(&hex_header(0, [0; 4]), &mut FailingWriter)
            .expect_err("receiver handshake write must fail");
        manager.fail(&error, Some(&mut FailingWriter));
        let hard_deadline = match &manager.state {
            TransferState::Draining(transfer) => transfer.hard_deadline,
            _ => panic!("failure must enter quarantine"),
        };
        let active_at = hard_deadline - Duration::from_millis(1);

        for payload in [b"payload-1".as_slice(), b"payload-2", b"prompt$ "] {
            let effects = manager.ingest(payload, &mut Vec::new()).unwrap();
            assert!(effects.passthrough.is_empty());
            let TransferState::Draining(transfer) = &mut manager.state else {
                panic!("sustained opaque bytes must remain quarantined")
            };
            transfer.last_activity = active_at;
            assert!(manager.timeout_if_needed(active_at, None).is_none());
            assert!(manager.is_active());
        }

        let terminal = manager.timeout_if_needed(hard_deadline, None).unwrap();
        assert_eq!(terminal.events[0].kind, "zmodem_failed");
        assert!(terminal.terminate_transport);
        assert!(manager.is_active());
        assert!(matches!(
            &manager.state,
            TransferState::Draining(transfer) if transfer.hard_terminated
        ));

        let quarantined = manager.ingest(b"still opaque", &mut Vec::new()).unwrap();
        assert!(quarantined.passthrough.is_empty());
        assert!(manager.transport_closed(true).events.is_empty());
        assert!(manager.is_active());
    }

    #[test]
    fn mid_file_zfin_never_completes_and_transport_eof_cleans_partial() {
        let directory = tempfile::tempdir().unwrap();
        let (mut manager, staging) = receiver_with_partial_file(directory.path());
        let mut writer = Vec::new();

        let error = manager
            .ingest(&hex_header(8, [0; 4]), &mut writer)
            .expect_err("vendor must reject ZFIN while a file is incomplete");
        assert!(matches!(error, ZmodemError::Protocol(_)));
        assert!(staging.exists());
        assert!(manager.fail(&error, Some(&mut writer)).events.is_empty());
        assert!(matches!(manager.state, TransferState::Draining(_)));
        wait_for_path_removal(&staging);

        let terminal = manager.transport_closed(true);
        assert_eq!(terminal.events[0].kind, "zmodem_failed");
        assert!(!directory.path().join("partial.bin").exists());
        assert!(!manager.is_active());
    }

    #[test]
    fn authorization_deadline_is_not_renewed_by_peer_traffic() {
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        manager
            .ingest(&hex_header(1, [0, 0, 0, 0x23]), &mut writer)
            .unwrap();
        let deadline = match &manager.state {
            TransferState::AwaitingSend(transfer) => transfer.authorization_deadline,
            _ => panic!("expected pending send authorization"),
        };
        manager.ingest(b"peer chatter", &mut writer).unwrap();

        let effects = manager
            .timeout_if_needed(deadline + Duration::from_millis(1), Some(&mut writer))
            .expect("fixed authorization deadline must expire");
        assert!(effects.events.is_empty());
        assert!(matches!(manager.state, TransferState::Draining(_)));

        let effects = manager.transport_closed(true);
        assert_eq!(effects.events[0].payload["reason"], "timeout");
    }

    #[test]
    fn receiver_protocol_retry_pump_recovers_a_dropped_handshake_without_renewing_idle() {
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        manager.ingest(&hex_header(0, [0; 4]), &mut writer).unwrap();
        let (retry_at, peer_activity) = match &manager.state {
            TransferState::Receiving(transfer) => {
                (transfer.protocol_retry_at, transfer.last_activity)
            }
            _ => panic!("expected active receiver"),
        };
        let initial_wire_len = writer.len();

        let effects = manager
            .timeout_if_needed(retry_at, Some(&mut writer))
            .expect("protocol retry deadline must be pumped");

        assert!(effects.events.is_empty());
        assert!(
            writer.len() > initial_wire_len,
            "ZRINIT must be retransmitted"
        );
        let TransferState::Receiving(transfer) = &manager.state else {
            panic!("receiver must remain active")
        };
        assert_eq!(transfer.last_activity, peer_activity);
        assert_eq!(
            transfer.protocol_retry_at,
            retry_at + PROTOCOL_RETRY_INTERVAL
        );
    }

    #[test]
    fn sender_protocol_retry_pump_recovers_a_dropped_file_offer_without_renewing_idle() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("payload.bin");
        fs::write(&path, b"payload").unwrap();
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        manager
            .ingest(&hex_header(1, [0, 0, 0, 0x23]), &mut writer)
            .unwrap();
        accept_send_ready(&mut manager, 1, &[path], &mut writer);
        let (retry_at, peer_activity) = match &manager.state {
            TransferState::Sending(transfer) => {
                (transfer.protocol_retry_at, transfer.last_activity)
            }
            _ => panic!("expected active sender"),
        };
        let initial_wire_len = writer.len();

        let effects = manager
            .timeout_if_needed(retry_at, Some(&mut writer))
            .expect("protocol retry deadline must be pumped");

        assert!(effects.events.is_empty());
        assert!(
            writer.len() > initial_wire_len,
            "ZFILE must be retransmitted"
        );
        let TransferState::Sending(transfer) = &manager.state else {
            panic!("sender must remain active")
        };
        assert_eq!(transfer.last_activity, peer_activity);
        assert_eq!(
            transfer.protocol_retry_at,
            retry_at + PROTOCOL_RETRY_INTERVAL
        );
    }

    #[test]
    fn sender_ack_rearms_retry_deadline_before_the_same_sampler_tick() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("payload.bin");
        fs::write(&path, vec![b'x'; 32 * 1024]).unwrap();
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        manager
            .ingest(&hex_header(1, [0, 0, 0, 0x23]), &mut writer)
            .unwrap();
        accept_send_ready(&mut manager, 1, &[path], &mut writer);
        manager
            .ingest(&hex_header(9, 0_u32.to_le_bytes()), &mut writer)
            .unwrap();

        let acknowledged = match &mut manager.state {
            TransferState::Sending(transfer) => {
                assert!(transfer.current_position > 0);
                transfer.protocol_retry_at = Instant::now();
                u32::try_from(transfer.current_position).unwrap()
            }
            _ => panic!("expected active sender"),
        };
        manager
            .ingest(&hex_header(3, acknowledged.to_le_bytes()), &mut writer)
            .unwrap();
        let wire_len_after_ack = writer.len();

        assert!(
            manager
                .timeout_if_needed(Instant::now(), Some(&mut writer))
                .is_none(),
            "an ACK processed before the sampler tick must rearm its response deadline"
        );
        assert_eq!(
            writer.len(),
            wire_len_after_ack,
            "the current data window must not be spuriously retransmitted"
        );
    }

    #[test]
    fn long_windowed_send_accepts_near_deadline_acks_without_spurious_retries() {
        const FILE_SIZE: usize = 256 * 1024;
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("payload.bin");
        let contents = (0..FILE_SIZE)
            .map(|index| (index % 251) as u8)
            .collect::<Vec<_>>();
        fs::write(&path, &contents).unwrap();

        let mut manager = ZmodemManager::default();
        let mut receiver = Receiver::new().unwrap();
        let mut downstream = Vec::new();
        let mut downstream_offset = 0;
        let mut upstream = Vec::new();
        let mut persisted = Vec::with_capacity(FILE_SIZE);
        let mut receiver_completed = false;
        let mut sender_completed = false;

        let zrinit = match receiver.poll() {
            Action::WriteWire(bytes) => {
                let bytes = bytes.to_vec();
                receiver.wire_written(bytes.len());
                bytes
            }
            action => panic!("receiver must start with ZRINIT, got {action:?}"),
        };
        manager.ingest(&zrinit, &mut downstream).unwrap();
        accept_send_ready(&mut manager, 1, &[path], &mut downstream);

        for _ in 0..500_000 {
            let mut progressed = false;

            match receiver.poll() {
                Action::WriteWire(bytes) => {
                    let len = bytes.len();
                    upstream.extend_from_slice(bytes);
                    receiver.wire_written(len);
                    progressed = true;
                }
                Action::WriteFile(bytes) => {
                    let len = bytes.len();
                    persisted.extend_from_slice(bytes);
                    receiver.file_written(len).unwrap();
                    progressed = true;
                }
                Action::Event(Event::SessionCompleted) => {
                    receiver_completed = true;
                    progressed = true;
                }
                Action::Event(Event::Aborted) => panic!("receiver aborted the long transfer"),
                Action::Event(_) => progressed = true,
                Action::Idle if downstream_offset < downstream.len() => {
                    let consumed = receiver
                        .submit_wire(&downstream[downstream_offset..])
                        .unwrap();
                    assert!(consumed > 0);
                    downstream_offset += consumed;
                    if downstream_offset == downstream.len() {
                        downstream.clear();
                        downstream_offset = 0;
                    }
                    progressed = true;
                }
                Action::Idle => {}
                action => panic!("unexpected receiver action: {action:?}"),
            }

            if !upstream.is_empty() {
                if let TransferState::Sending(transfer) = &mut manager.state {
                    // The peer reply wins a race with the resource sampler:
                    // it arrives just after the old response deadline, but is
                    // processed before that sampler tick runs.
                    transfer.protocol_retry_at = Instant::now();
                }
                let wire = std::mem::take(&mut upstream);
                let effects = manager.ingest(&wire, &mut downstream).unwrap();
                sender_completed |= effects
                    .events
                    .iter()
                    .any(|event| event.kind == "zmodem_completed");
                let wire_len_after_reply = downstream.len();
                assert!(
                    manager
                        .timeout_if_needed(Instant::now(), Some(&mut downstream))
                        .is_none(),
                    "a processed peer reply must defer the next protocol retry"
                );
                assert_eq!(
                    downstream.len(),
                    wire_len_after_reply,
                    "the sampler must not retransmit after fresh peer progress"
                );
                progressed = true;
            }

            if sender_completed
                && receiver_completed
                && downstream_offset == downstream.len()
                && upstream.is_empty()
            {
                break;
            }
            assert!(progressed, "long windowed transfer deadlocked");
        }

        assert!(sender_completed, "core sender did not complete");
        assert!(receiver_completed, "vendor receiver did not complete");
        assert_eq!(persisted, contents);
    }

    #[test]
    fn sender_protocol_retries_remain_bounded_without_peer_or_file_progress() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("payload.bin");
        fs::write(&path, b"payload").unwrap();
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        manager
            .ingest(&hex_header(1, [0, 0, 0, 0x23]), &mut writer)
            .unwrap();
        accept_send_ready(&mut manager, 1, &[path], &mut writer);
        let first_retry = match &manager.state {
            TransferState::Sending(transfer) => transfer.protocol_retry_at,
            _ => panic!("expected active sender"),
        };

        for retry in 0..10 {
            let now = first_retry + PROTOCOL_RETRY_INTERVAL.saturating_mul(retry as u32);
            let TransferState::Sending(transfer) = &mut manager.state else {
                break;
            };
            // Isolate the protocol response budget from the aggregate idle
            // watchdog: refreshing only the latter, without delivering peer
            // or file progress, must not defer or replenish vendor retries.
            transfer.last_activity = now;
            let _ = manager.timeout_if_needed(now, Some(&mut writer));
        }

        assert!(matches!(manager.state, TransferState::Draining(_)));
        let terminal = manager.transport_closed(true);
        assert_eq!(terminal.events[0].kind, "zmodem_failed");
        assert_eq!(terminal.events[0].payload["reason"], "protocol_error");
    }

    #[test]
    fn peer_noise_cannot_extend_the_send_no_progress_deadline() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("payload.bin");
        fs::write(&path, b"payload").unwrap();
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        manager
            .ingest(&hex_header(1, [0, 0, 0, 0x23]), &mut writer)
            .unwrap();
        accept_send_ready(&mut manager, 1, &[path], &mut writer);
        let deadline = Instant::now() + Duration::from_millis(10);
        let TransferState::Sending(transfer) = &mut manager.state else {
            panic!("expected active sender")
        };
        transfer.progress_deadline = deadline;
        transfer.protocol_retry_at = Instant::now();

        for noise in [0x11, 0x13, 0x91, 0x93, b'x'] {
            manager.ingest(&[noise], &mut writer).unwrap();
            let TransferState::Sending(transfer) = &manager.state else {
                panic!("noise must not finish the transfer")
            };
            assert_eq!(transfer.progress_deadline, deadline);
            assert!(transfer.protocol_retry_at > Instant::now());
        }

        let effects = manager
            .timeout_if_needed(deadline, Some(&mut writer))
            .expect("the hard no-progress deadline must remain enforceable");
        assert!(effects.events.is_empty());
        assert!(matches!(manager.state, TransferState::Draining(_)));
        let terminal = manager.transport_closed(true);
        assert_eq!(terminal.events[0].kind, "zmodem_failed");
        assert_eq!(terminal.events[0].payload["reason"], "timeout");
    }

    #[test]
    fn snapshot_resource_pool_is_process_wide_and_leased_until_last_owner_drops() {
        let pool = SnapshotResourcePool::new(SnapshotResourceLimits {
            max_files: 4,
            max_bytes: 40,
            max_fds: 8,
        });
        let start = Arc::new(std::sync::Barrier::new(3));
        let release = Arc::new(std::sync::Barrier::new(3));
        let (result_tx, result_rx) = mpsc::channel();
        let mut workers = Vec::new();
        for _ in 0..2 {
            let pool = Arc::clone(&pool);
            let start = Arc::clone(&start);
            let release = Arc::clone(&release);
            let result_tx = result_tx.clone();
            workers.push(std::thread::spawn(move || {
                start.wait();
                let lease = pool.acquire(3, 30, 6);
                result_tx.send(lease.is_some()).unwrap();
                release.wait();
                drop(lease);
            }));
        }
        drop(result_tx);

        start.wait();
        let acquired = [result_rx.recv().unwrap(), result_rx.recv().unwrap()];
        assert_eq!(acquired.into_iter().filter(|value| *value).count(), 1);
        assert_eq!(
            pool.usage(),
            SnapshotResourceUsage {
                files: 3,
                bytes: 30,
                fds: 6
            }
        );
        release.wait();
        for worker in workers {
            worker.join().unwrap();
        }
        assert_eq!(pool.usage(), SnapshotResourceUsage::default());

        let lease = pool.acquire(4, 40, 8).unwrap();
        let queued_or_sending_owner = lease.clone();
        drop(lease);
        assert_eq!(
            pool.usage(),
            SnapshotResourceUsage {
                files: 4,
                bytes: 40,
                fds: 8
            }
        );
        assert!(pool.acquire(1, 1, 1).is_none());
        drop(queued_or_sending_owner);
        assert_eq!(pool.usage(), SnapshotResourceUsage::default());
    }

    #[test]
    fn receive_resource_pool_enforces_file_byte_and_fd_limits_until_drop() {
        let pool = ReceiveResourcePool::new(SnapshotResourceLimits {
            max_files: 2,
            max_bytes: 10,
            max_fds: 3,
        });
        let mut first = pool.acquire(1, 0, 2).unwrap();
        first.reserve_bytes(7).unwrap();
        assert_eq!(
            pool.usage(),
            SnapshotResourceUsage {
                files: 1,
                bytes: 7,
                fds: 2,
            }
        );
        assert!(matches!(
            first.reserve_bytes(4),
            Err(ZmodemError::ResourceLimit)
        ));
        assert!(pool.acquire(2, 0, 0).is_none());
        assert!(pool.acquire(0, 0, 2).is_none());

        let second = pool.acquire(1, 3, 1).unwrap();
        assert!(pool.acquire(1, 0, 0).is_none());
        drop(first);
        assert_eq!(
            pool.usage(),
            SnapshotResourceUsage {
                files: 1,
                bytes: 3,
                fds: 1,
            }
        );
        drop(second);
        assert_eq!(pool.usage(), SnapshotResourceUsage::default());
    }

    #[test]
    fn cancelling_send_preparation_signals_the_snapshot_worker() {
        let (_result_tx, result_rx) = mpsc::channel();
        let (exit_tx, exit_rx) = mpsc::channel();
        let cancel = Arc::new(AtomicBool::new(false));
        let worker_cancel = Arc::clone(&cancel);
        let worker = std::thread::spawn(move || {
            while !worker_cancel.load(Ordering::Acquire) {
                std::thread::sleep(Duration::from_millis(1));
            }
            let _ = exit_tx.send(());
        });
        let now = Instant::now();
        let mut manager = ZmodemManager {
            state: TransferState::PreparingSend(PreparingSend {
                id: 7,
                engine: Some(Sender::new().unwrap()),
                wire: Vec::new(),
                wire_offset: 0,
                result: result_rx,
                worker: Some(worker),
                cancel: Arc::clone(&cancel),
                snapshot_bytes: 0,
                progress_deadline: now + TRANSFER_IDLE_TIMEOUT,
                protocol_retry_at: now + PROTOCOL_RETRY_INTERVAL,
            }),
            next_id: 8,
            failure_passthrough: Vec::new(),
            owner_session_id: None,
            operation_epoch: None,
            receive_commit_phase: None,
            receive_publish_started_at: None,
        };
        let mut writer = Vec::new();

        manager.cancel(7, &mut writer).unwrap();

        assert!(cancel.load(Ordering::Acquire));
        exit_rx
            .recv_timeout(Duration::from_secs(1))
            .expect("cancelled snapshot worker must exit for its reaper");
        assert!(matches!(manager.state, TransferState::Draining(_)));
    }

    #[test]
    fn send_preparation_retries_protocol_without_waiting_for_snapshot_completion() {
        let (result_tx, result_rx) = mpsc::channel();
        let mut engine = Sender::new().unwrap();
        engine
            .start_file(FileInfo::new(b"payload.bin", Some(Position::new(1))))
            .unwrap();
        let now = Instant::now();
        let mut manager = ZmodemManager {
            state: TransferState::PreparingSend(PreparingSend {
                id: 8,
                engine: Some(engine),
                wire: Vec::new(),
                wire_offset: 0,
                result: result_rx,
                worker: None,
                cancel: Arc::new(AtomicBool::new(false)),
                snapshot_bytes: 0,
                progress_deadline: now + TRANSFER_IDLE_TIMEOUT,
                protocol_retry_at: now,
            }),
            next_id: 9,
            failure_passthrough: Vec::new(),
            owner_session_id: None,
            operation_epoch: None,
            receive_commit_phase: None,
            receive_publish_started_at: None,
        };
        let mut writer = Vec::new();
        manager
            .drive_send_preparation_protocol(&mut writer)
            .unwrap();
        let initial_wire_bytes = writer.len();

        manager
            .timeout_if_needed(now, Some(&mut writer))
            .expect("retry deadline must pump the preparing sender");

        assert!(writer.len() > initial_wire_bytes);
        assert!(matches!(manager.state, TransferState::PreparingSend(_)));
        drop(result_tx);
    }

    #[test]
    fn send_preparation_obeys_the_hard_no_progress_deadline() {
        let (result_tx, result_rx) = mpsc::channel();
        let now = Instant::now();
        let mut manager = ZmodemManager {
            state: TransferState::PreparingSend(PreparingSend {
                id: 9,
                engine: Some(Sender::new().unwrap()),
                wire: Vec::new(),
                wire_offset: 0,
                result: result_rx,
                worker: None,
                cancel: Arc::new(AtomicBool::new(false)),
                snapshot_bytes: 0,
                progress_deadline: now,
                protocol_retry_at: now + PROTOCOL_RETRY_INTERVAL,
            }),
            next_id: 10,
            failure_passthrough: Vec::new(),
            owner_session_id: None,
            operation_epoch: None,
            receive_commit_phase: None,
            receive_publish_started_at: None,
        };
        let mut writer = Vec::new();

        let effects = manager
            .timeout_if_needed(now, Some(&mut writer))
            .expect("hard no-progress deadline must fail preparation");

        assert!(effects.events.is_empty());
        assert!(matches!(manager.state, TransferState::Draining(_)));
        assert!(
            result_tx
                .send(SnapshotMessage::Progress { bytes: 1, at: now })
                .is_err()
        );
    }

    #[test]
    fn queued_finished_snapshot_is_not_rejected_by_an_authorization_deadline() {
        let (result_tx, result_rx) = mpsc::channel();
        let now = Instant::now();
        let mut file = tempfile::tempfile().unwrap();
        file.write_all(b"x").unwrap();
        file.seek(SeekFrom::Start(0)).unwrap();
        let pool = SnapshotResourcePool::new(SnapshotResourceLimits {
            max_files: 1,
            max_bytes: 1,
            max_fds: 2,
        });
        let snapshot_resources = pool.acquire(1, 1, 2).unwrap();
        result_tx
            .send(SnapshotMessage::Finished {
                result: Ok(PreparedSend {
                    files: VecDeque::from([SendFile {
                        file,
                        name: "payload.bin".to_string(),
                        size: 1,
                        modification_time: None,
                    }]),
                    total_bytes: 1,
                    snapshot_resources,
                }),
                at: now,
            })
            .unwrap();
        let mut manager = ZmodemManager {
            state: TransferState::PreparingSend(PreparingSend {
                id: 10,
                engine: Some(Sender::new().unwrap()),
                wire: Vec::new(),
                wire_offset: 0,
                result: result_rx,
                worker: Some(std::thread::spawn(|| {})),
                cancel: Arc::new(AtomicBool::new(false)),
                snapshot_bytes: 1,
                progress_deadline: now + TRANSFER_IDLE_TIMEOUT,
                protocol_retry_at: now + PROTOCOL_RETRY_INTERVAL,
            }),
            next_id: 11,
            failure_passthrough: Vec::new(),
            owner_session_id: None,
            operation_epoch: None,
            receive_commit_phase: None,
            receive_publish_started_at: None,
        };
        let mut writer = Vec::new();

        let effects = manager
            .timeout_if_needed(now, Some(&mut writer))
            .expect("the queued snapshot must advance preparation");

        assert!(effects.events.is_empty());
        assert!(matches!(manager.state, TransferState::Sending(_)));
    }

    #[test]
    fn late_finished_snapshot_cannot_revive_an_expired_send_preparation() {
        let (result_tx, result_rx) = mpsc::channel();
        let deadline = Instant::now();
        let mut file = tempfile::tempfile().unwrap();
        file.write_all(b"x").unwrap();
        file.seek(SeekFrom::Start(0)).unwrap();
        let pool = SnapshotResourcePool::new(SnapshotResourceLimits {
            max_files: 1,
            max_bytes: 1,
            max_fds: 2,
        });
        let snapshot_resources = pool.acquire(1, 1, 2).unwrap();
        result_tx
            .send(SnapshotMessage::Finished {
                result: Ok(PreparedSend {
                    files: VecDeque::from([SendFile {
                        file,
                        name: "late.bin".to_string(),
                        size: 1,
                        modification_time: None,
                    }]),
                    total_bytes: 1,
                    snapshot_resources,
                }),
                at: deadline + Duration::from_millis(1),
            })
            .unwrap();
        let mut manager = ZmodemManager {
            state: TransferState::PreparingSend(PreparingSend {
                id: 11,
                engine: Some(Sender::new().unwrap()),
                wire: Vec::new(),
                wire_offset: 0,
                result: result_rx,
                worker: Some(std::thread::spawn(|| {})),
                cancel: Arc::new(AtomicBool::new(false)),
                snapshot_bytes: 0,
                progress_deadline: deadline,
                protocol_retry_at: deadline + PROTOCOL_RETRY_INTERVAL,
            }),
            next_id: 12,
            failure_passthrough: Vec::new(),
            owner_session_id: None,
            operation_epoch: None,
            receive_commit_phase: None,
            receive_publish_started_at: None,
        };
        let mut writer = Vec::new();

        let effects = manager
            .timeout_if_needed(deadline + Duration::from_millis(1), Some(&mut writer))
            .expect("late snapshot completion must fail preparation");

        assert!(effects.events.is_empty());
        assert!(matches!(manager.state, TransferState::Draining(_)));
    }

    #[test]
    fn late_receive_preparation_cannot_revive_an_expired_deadline() {
        let directory = tempfile::tempdir().unwrap();
        let received =
            create_receive_file(directory.path(), "late.bin", Some(0), None, 12).unwrap();
        let staging = received.recoverable_path();
        let (result_tx, result_rx) = mpsc::channel();
        let deadline = Instant::now();
        result_tx
            .send(ReceivePreparationResult {
                result: Ok(PreparedReceive {
                    destination: None,
                    file: Some(received),
                }),
                finished_at: deadline + Duration::from_millis(1),
            })
            .unwrap();
        let mut transfer = receive_transfer(12);
        transfer.progress_deadline = deadline;
        transfer.preparation = Some(ReceivePreparation {
            result: result_rx,
            worker: Some(std::thread::spawn(|| {})),
            cancel: Arc::new(AtomicBool::new(false)),
        });
        let mut manager = ZmodemManager::default();
        manager.state = TransferState::Receiving(transfer);
        let mut writer = Vec::new();

        let effects = manager
            .timeout_if_needed(deadline + Duration::from_millis(1), Some(&mut writer))
            .expect("late receive preparation must fail");

        assert!(effects.events.is_empty());
        assert!(matches!(manager.state, TransferState::Draining(_)));
        wait_for_path_removal(&staging);
    }

    #[test]
    fn send_preparation_keeps_the_peer_handshake_moving() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("payload.bin");
        fs::write(&path, vec![b'x'; 1024 * 1024]).unwrap();
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        manager
            .ingest(&hex_header(1, [0, 0, 0, 0x23]), &mut writer)
            .unwrap();
        let before = writer.len();

        let effects = manager.accept_send(1, &[path], &mut writer).unwrap();

        assert_eq!(effects.events[0].kind, "zmodem_started");
        assert!(writer.len() > before, "preparation must answer the peer");
        assert!(manager.is_active());
    }

    #[test]
    fn send_authorization_defers_filesystem_validation_to_the_cancelable_worker() {
        let directory = tempfile::tempdir().unwrap();
        let missing = directory.path().join("missing.bin");
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        manager
            .ingest(&hex_header(1, [0, 0, 0, 0x23]), &mut writer)
            .unwrap();

        let effects = manager.accept_send(1, &[missing], &mut writer).unwrap();

        assert_eq!(effects.events[0].kind, "zmodem_started");
        assert!(matches!(manager.state, TransferState::PreparingSend(_)));
        let deadline = Instant::now() + Duration::from_secs(1);
        loop {
            match manager.finish_send_preparation(&mut writer, &mut ZmodemEffects::default()) {
                Err(ZmodemError::InvalidSourceFiles) => break,
                Ok(()) if Instant::now() < deadline => std::thread::yield_now(),
                other => panic!("unexpected asynchronous validation result: {other:?}"),
            }
        }
    }

    #[test]
    fn send_files_capture_modification_time() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("payload.bin");
        fs::write(&path, b"payload").unwrap();
        let modification_time = 1_700_000_456_u64;
        File::open(&path)
            .unwrap()
            .set_times(
                FileTimes::new().set_modified(UNIX_EPOCH + Duration::from_secs(modification_time)),
            )
            .unwrap();

        let (files, total) = open_send_files(&[path]).unwrap();

        assert_eq!(total, 7);
        assert_eq!(files[0].modification_time, Some(modification_time));
    }

    #[cfg(unix)]
    #[test]
    fn send_snapshot_rejects_same_size_rewrite_even_when_mtime_is_restored() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("payload.bin");
        fs::write(&path, vec![b'a'; SNAPSHOT_PROGRESS_CHUNK_BYTES * 2]).unwrap();
        let source = open_send_file(&path).unwrap();
        let metadata = source.metadata().unwrap();
        let initial_mutation = SendSourceMutation::from_metadata(&metadata);
        let original_modified = metadata.modified().unwrap();
        std::thread::sleep(Duration::from_millis(2));
        let mut rewritten = false;

        let result = snapshot_send_file(
            source,
            metadata.len(),
            initial_mutation,
            &AtomicBool::new(false),
            |_| {
                if rewritten {
                    return;
                }
                rewritten = true;
                let mut replacement = OpenOptions::new().write(true).open(&path).unwrap();
                replacement
                    .seek(SeekFrom::Start(SNAPSHOT_PROGRESS_CHUNK_BYTES as u64))
                    .unwrap();
                replacement
                    .write_all(&vec![b'b'; SNAPSHOT_PROGRESS_CHUNK_BYTES])
                    .unwrap();
                replacement
                    .set_times(FileTimes::new().set_modified(original_modified))
                    .unwrap();
            },
        );

        assert!(matches!(result, Err(ZmodemError::InvalidSourceFiles)));
        assert_eq!(
            fs::metadata(&path).unwrap().modified().ok(),
            Some(original_modified),
            "the ctime check, rather than mtime drift, must reject the rewrite"
        );
    }

    #[test]
    fn authorized_send_uses_an_immutable_pathless_snapshot() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("payload.bin");
        fs::write(&path, b"authorized-bytes").unwrap();

        let (mut files, total) = open_send_files(std::slice::from_ref(&path)).unwrap();
        let mut send_file = files.pop_front().unwrap();
        fs::write(&path, b"replacement-data").unwrap();
        fs::remove_file(&path).unwrap();

        let mut bytes = Vec::new();
        send_file.file.read_to_end(&mut bytes).unwrap();
        assert_eq!(bytes, b"authorized-bytes");
        assert_eq!(total, bytes.len() as u64);
        assert_eq!(send_file.size, bytes.len() as u32);

        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;

            let metadata = send_file.file.metadata().unwrap();
            assert_eq!(metadata.mode() & 0o777, 0o600);
            assert_eq!(metadata.nlink(), 0, "snapshot must have no filesystem path");
        }
    }

    #[test]
    fn send_batch_names_remain_unique_after_sanitization_and_utf8_truncation() {
        let mut used = HashSet::new();
        let first = reserve_unique_send_name("bad<name.txt", &mut used).unwrap();
        let second = reserve_unique_send_name("bad?name.txt", &mut used).unwrap();
        assert_eq!(first, "bad_name.txt");
        assert_eq!(second, "bad_name (1).txt");

        let prefix = "界".repeat(80);
        let long_first = reserve_unique_send_name(&format!("{prefix}a"), &mut used).unwrap();
        let long_second = reserve_unique_send_name(&format!("{prefix}b"), &mut used).unwrap();
        assert_ne!(long_first, long_second);
        assert!(long_first.len() <= MAX_FILENAME_BYTES);
        assert!(long_second.len() <= MAX_FILENAME_BYTES);
        assert!(long_first.is_char_boundary(long_first.len()));
        assert!(long_second.is_char_boundary(long_second.len()));
    }

    #[test]
    fn send_batch_wire_names_are_ascii_case_insensitively_unique() {
        let mut used = HashSet::new();

        let first = reserve_unique_send_name("A.txt", &mut used).unwrap();
        let second = reserve_unique_send_name("a.txt", &mut used).unwrap();

        assert_eq!(first, "A.txt");
        assert_eq!(second, "a (1).txt");
        assert!(first.len() <= MAX_FILENAME_BYTES);
        assert!(second.len() <= MAX_FILENAME_BYTES);
    }

    #[test]
    fn send_batch_wire_names_normalize_unicode_before_casefolding() {
        let mut used = HashSet::new();
        assert_eq!(
            portable_wire_name_key("É.txt"),
            portable_wire_name_key("e\u{301}.txt")
        );

        let first = reserve_unique_send_name("É.txt", &mut used).unwrap();
        let second = reserve_unique_send_name("e\u{301}.txt", &mut used).unwrap();

        assert_eq!(first, "É.txt");
        assert_eq!(second, "e\u{301} (1).txt");
        assert_ne!(
            portable_wire_name_key(&first),
            portable_wire_name_key(&second)
        );
        assert!(first.len() <= MAX_FILENAME_BYTES);
        assert!(second.len() <= MAX_FILENAME_BYTES);
    }

    #[cfg(unix)]
    #[test]
    fn open_send_files_assigns_unique_wire_names_to_sanitization_collisions() {
        let directory = tempfile::tempdir().unwrap();
        let first = directory.path().join("bad<name.txt");
        let second = directory.path().join("bad?name.txt");
        fs::write(&first, b"first").unwrap();
        fs::write(&second, b"second").unwrap();

        let (files, total) = open_send_files(&[first, second]).unwrap();

        assert_eq!(total, 11);
        assert_eq!(files[0].name, "bad_name.txt");
        assert_eq!(files[1].name, "bad_name (1).txt");
    }

    #[cfg(unix)]
    #[test]
    fn open_send_files_assigns_unique_wire_names_to_casefold_collisions() {
        let directory = tempfile::tempdir().unwrap();
        let upper_directory = directory.path().join("upper");
        let lower_directory = directory.path().join("lower");
        fs::create_dir(&upper_directory).unwrap();
        fs::create_dir(&lower_directory).unwrap();
        let first = upper_directory.join("A.txt");
        let second = lower_directory.join("a.txt");
        fs::write(&first, b"first").unwrap();
        fs::write(&second, b"second").unwrap();

        let (files, total) = open_send_files(&[first, second]).unwrap();

        assert_eq!(total, 11);
        assert_eq!(files[0].name, "A.txt");
        assert_eq!(files[1].name, "a (1).txt");
    }

    #[cfg(unix)]
    #[test]
    fn send_rejects_symbolic_links() {
        use std::os::unix::fs::symlink;

        let directory = tempfile::tempdir().unwrap();
        let target = directory.path().join("target.txt");
        let link = directory.path().join("link.txt");
        fs::write(&target, b"payload").unwrap();
        symlink(&target, &link).unwrap();

        assert!(matches!(
            open_send_files(&[link]),
            Err(ZmodemError::InvalidSourceFiles)
        ));
    }

    #[cfg(unix)]
    #[test]
    fn send_rejects_fifo_without_waiting_for_a_writer_and_rejects_devices() {
        use std::ffi::CString;
        use std::os::unix::ffi::OsStrExt;

        let directory = tempfile::tempdir().unwrap();
        let fifo = directory.path().join("payload.fifo");
        let fifo_path = CString::new(fifo.as_os_str().as_bytes()).unwrap();
        // SAFETY: `fifo_path` is a live, NUL-terminated CString and the mode
        // contains only permission bits accepted by mkfifo(2).
        assert_eq!(unsafe { libc::mkfifo(fifo_path.as_ptr(), 0o600) }, 0);

        assert!(matches!(
            open_send_files(&[fifo]),
            Err(ZmodemError::InvalidSourceFiles)
        ));
        assert!(matches!(
            open_send_files(&[PathBuf::from("/dev/null")]),
            Err(ZmodemError::InvalidSourceFiles)
        ));
    }

    #[test]
    fn pending_transfer_times_out_and_returns_to_scanning() {
        let mut manager = ZmodemManager::default();
        let mut writer = Vec::new();
        let detected = manager
            .ingest(&hex_header(1, [0, 0, 0, 0x23]), &mut writer)
            .unwrap();
        assert_eq!(detected.events[0].kind, "zmodem_detected");

        let effects = manager
            .timeout_if_needed(
                Instant::now() + AUTHORIZATION_TIMEOUT + Duration::from_secs(1),
                Some(&mut writer),
            )
            .expect("pending transfer should time out");

        assert!(effects.events.is_empty());
        assert!(matches!(manager.state, TransferState::Draining(_)));
        assert!(writer.ends_with(CANCEL_BYTES));

        let terminal = manager
            .timeout_if_needed(
                Instant::now() + DRAIN_QUIET_TIMEOUT + Duration::from_millis(1),
                Some(&mut writer),
            )
            .unwrap();
        assert_eq!(terminal.events[0].kind, "zmodem_failed");
        assert_eq!(terminal.events[0].payload["reason"], "timeout");
        assert!(!manager.is_active());
    }
}
