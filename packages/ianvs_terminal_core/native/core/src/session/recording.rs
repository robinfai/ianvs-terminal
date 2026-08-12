use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use parking_lot::Mutex;
use serde_json::{Value, json};
use std::collections::{HashMap, VecDeque};
use std::fmt::Write as FmtWrite;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock};
use std::thread;
use std::time::Instant;

const RECORDING_HANDOFF_PREFIX: &str = ".ianvs-recording-handoff-";
const RECORDING_HANDOFF_SUFFIX: &str = ".ndjson";
const RECORDING_FINALIZE_JOB_ID_BYTES: usize = 16;
const RECORDING_FINALIZE_JOB_ID_ATTEMPTS: usize = 8;
const RECORDING_FINALIZE_IN_FLIGHT_LIMIT: usize = 64;
const RECORDING_FINALIZE_TERMINAL_STATUS_LIMIT: usize = 1024;
const RECORDING_FINALIZE_REGISTRY_LIMIT: usize =
    RECORDING_FINALIZE_IN_FLIGHT_LIMIT + RECORDING_FINALIZE_TERMINAL_STATUS_LIMIT;

static RECORDING_FINALIZE_JOBS: LazyLock<Mutex<RecordingFinalizeRegistry>> = LazyLock::new(|| {
    Mutex::new(RecordingFinalizeRegistry::with_limits(
        RECORDING_FINALIZE_IN_FLIGHT_LIMIT,
        RECORDING_FINALIZE_TERMINAL_STATUS_LIMIT,
        RECORDING_FINALIZE_REGISTRY_LIMIT,
    ))
});

pub(super) const RECORDING_SCHEMA_VERSION: u8 = 1;
pub(super) const RECORDING_MAX_EVENTS: usize = 4096;
pub(super) const RECORDING_MAX_PAYLOAD_BYTES: usize = 8 * 1024 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum RecordingInputPolicy {
    Record,
    Redact,
}

impl RecordingInputPolicy {
    pub(super) fn parse(value: &str) -> Option<Self> {
        match value {
            "record" => Some(Self::Record),
            "redact" => Some(Self::Redact),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Record => "record",
            Self::Redact => "redact",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct RecordingError {
    pub(super) code: &'static str,
    pub(super) message: &'static str,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum RecordingFinalizeStatus {
    Running,
    Ready,
    Failed(RecordingError),
    Unknown,
}

struct RecordingFinalizeRegistry {
    jobs: HashMap<String, RecordingFinalizeStatus>,
    terminal_order: VecDeque<String>,
    running_count: usize,
    in_flight_limit: usize,
    terminal_limit: usize,
    registry_limit: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum RecordingFinalizeAdmission {
    Admitted,
    Duplicate,
    CapacityExceeded,
}

impl RecordingFinalizeRegistry {
    fn with_limits(in_flight_limit: usize, terminal_limit: usize, registry_limit: usize) -> Self {
        Self {
            jobs: HashMap::new(),
            terminal_order: VecDeque::new(),
            running_count: 0,
            in_flight_limit,
            terminal_limit,
            registry_limit,
        }
    }

    fn status(&mut self, job_id: &str, consume_terminal: bool) -> RecordingFinalizeStatus {
        let status = self
            .jobs
            .get(job_id)
            .copied()
            .unwrap_or(RecordingFinalizeStatus::Unknown);
        if consume_terminal
            && matches!(
                status,
                RecordingFinalizeStatus::Ready | RecordingFinalizeStatus::Failed(_)
            )
        {
            self.jobs.remove(job_id);
            self.terminal_order.retain(|candidate| candidate != job_id);
        }
        status
    }

    fn register(&mut self, job_id: &str) -> RecordingFinalizeAdmission {
        if self.jobs.contains_key(job_id) {
            return RecordingFinalizeAdmission::Duplicate;
        }
        if self.running_count >= self.in_flight_limit {
            return RecordingFinalizeAdmission::CapacityExceeded;
        }
        while self.jobs.len() >= self.registry_limit {
            if !self.evict_oldest_terminal() {
                return RecordingFinalizeAdmission::CapacityExceeded;
            }
        }
        self.jobs
            .insert(job_id.to_owned(), RecordingFinalizeStatus::Running);
        self.running_count += 1;
        RecordingFinalizeAdmission::Admitted
    }

    fn complete(&mut self, job_id: &str, status: RecordingFinalizeStatus) {
        debug_assert!(matches!(
            status,
            RecordingFinalizeStatus::Ready | RecordingFinalizeStatus::Failed(_)
        ));
        let Some(current) = self.jobs.get_mut(job_id) else {
            return;
        };
        if !matches!(*current, RecordingFinalizeStatus::Running) {
            return;
        }
        *current = status;
        self.running_count = self.running_count.saturating_sub(1);
        self.terminal_order.push_back(job_id.to_owned());
        while self.terminal_order.len() > self.terminal_limit {
            self.evict_oldest_terminal();
        }
        while self.jobs.len() > self.registry_limit {
            if !self.evict_oldest_terminal() {
                break;
            }
        }
    }

    fn rollback_running(&mut self, job_id: &str) -> bool {
        if !self
            .jobs
            .get(job_id)
            .is_some_and(|status| matches!(status, RecordingFinalizeStatus::Running))
        {
            return false;
        }
        self.jobs.remove(job_id);
        self.running_count = self.running_count.saturating_sub(1);
        true
    }

    fn evict_oldest_terminal(&mut self) -> bool {
        while let Some(expired_job_id) = self.terminal_order.pop_front() {
            if self
                .jobs
                .get(&expired_job_id)
                .is_some_and(|status| !matches!(status, RecordingFinalizeStatus::Running))
            {
                self.jobs.remove(&expired_job_id);
                return true;
            }
        }
        false
    }
}

pub(super) fn recording_finalize_status(
    job_id: &str,
    consume_terminal: bool,
) -> RecordingFinalizeStatus {
    RECORDING_FINALIZE_JOBS
        .lock()
        .status(job_id, consume_terminal)
}

fn register_recording_finalize_job(job_id: &str) -> RecordingFinalizeAdmission {
    RECORDING_FINALIZE_JOBS.lock().register(job_id)
}

fn complete_recording_finalize_job(job_id: &str, status: RecordingFinalizeStatus) {
    RECORDING_FINALIZE_JOBS.lock().complete(job_id, status);
}

fn rollback_recording_finalize_job(job_id: &str) {
    let rolled_back = RECORDING_FINALIZE_JOBS.lock().rollback_running(job_id);
    debug_assert!(rolled_back, "spawn rollback must remove a running job");
}

impl RecordingError {
    fn already_active() -> Self {
        Self {
            code: "already_active",
            message: "a recording is already active for this session",
        }
    }

    fn not_active() -> Self {
        Self {
            code: "not_active",
            message: "no recording is active for this session",
        }
    }

    fn capacity_exceeded() -> Self {
        Self {
            code: "capacity_exceeded",
            message: "recording buffer capacity exceeded",
        }
    }

    fn serialize() -> Self {
        Self {
            code: "serialize_failed",
            message: "recording serialization failed",
        }
    }

    fn invalid_handoff() -> Self {
        Self {
            code: "invalid_handoff",
            message: "recording handoff directory is invalid",
        }
    }

    fn handoff_collision() -> Self {
        Self {
            code: "handoff_collision",
            message: "recording handoff job path already exists",
        }
    }

    fn entropy() -> Self {
        Self {
            code: "entropy_failed",
            message: "recording handoff job id generation failed",
        }
    }

    fn finalize_capacity_exceeded() -> Self {
        Self {
            code: "finalize_capacity_exceeded",
            message: "recording finalize worker capacity exceeded",
        }
    }

    fn finalize_worker_spawn_failed() -> Self {
        Self {
            code: "finalize_worker_spawn_failed",
            message: "recording finalize worker could not be started",
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub(super) struct RecordingFinalizeJob {
    pub(super) job_id: String,
    pub(super) handoff_path: String,
    pub(super) error_path: String,
}

#[derive(Debug)]
pub(super) struct RecordingStartResult {
    pub(super) max_events: usize,
    pub(super) max_payload_bytes: usize,
}

#[derive(Default)]
pub(super) struct SessionRecording {
    active: Option<ActiveRecording>,
    max_events: usize,
    max_payload_bytes: usize,
}

impl SessionRecording {
    pub(super) fn bounded() -> Self {
        Self::with_limits(RECORDING_MAX_EVENTS, RECORDING_MAX_PAYLOAD_BYTES)
    }

    fn with_limits(max_events: usize, max_payload_bytes: usize) -> Self {
        Self {
            active: None,
            max_events,
            max_payload_bytes,
        }
    }

    // This boundary mirrors the stable recording Session Request fields; a
    // parameter object would only move, rather than reduce, that contract.
    #[allow(clippy::too_many_arguments)]
    pub(super) fn start(
        &mut self,
        session_id: u64,
        created_at_utc: String,
        input_policy: RecordingInputPolicy,
        terminal_emulation: &'static str,
        cols: u16,
        rows: u16,
        initial_screen: Vec<u8>,
    ) -> Result<RecordingStartResult, RecordingError> {
        if self.active.is_some() {
            return Err(RecordingError::already_active());
        }
        let mut active = ActiveRecording {
            session_id,
            created_at_utc,
            input_policy,
            started_at: Instant::now(),
            events: Vec::new(),
            payload_bytes: 0,
            overflowed: false,
            max_events: self.max_events,
            max_payload_bytes: self.max_payload_bytes,
        };
        active.push_at(
            RecordingEventPayload::SessionStarted {
                terminal_emulation,
                cols,
                rows,
            },
            0,
        );
        if !initial_screen.is_empty() {
            active.push_at(RecordingEventPayload::PtyOutput(initial_screen), 0);
        }
        self.active = Some(active);
        Ok(RecordingStartResult {
            max_events: self.max_events,
            max_payload_bytes: self.max_payload_bytes,
        })
    }

    pub(super) fn record_pty_output(&mut self, bytes: &[u8]) {
        if bytes.is_empty() {
            return;
        }
        if let Some(active) = self.active.as_mut() {
            active.push(RecordingEventPayload::PtyOutput(bytes.to_vec()));
        }
    }

    pub(super) fn record_user_input(&mut self, bytes: &[u8]) {
        if let Some(active) = self.active.as_mut() {
            let payload = match active.input_policy {
                RecordingInputPolicy::Record => RecordingEventPayload::UserInput {
                    bytes: Some(bytes.to_vec()),
                    byte_length: bytes.len(),
                },
                RecordingInputPolicy::Redact => RecordingEventPayload::UserInput {
                    bytes: None,
                    byte_length: bytes.len(),
                },
            };
            active.push(payload);
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn record_resize(
        &mut self,
        cols: u16,
        rows: u16,
        pixel_width: u16,
        pixel_height: u16,
        cell_width: u16,
        cell_height: u16,
    ) {
        if let Some(active) = self.active.as_mut() {
            active.push(RecordingEventPayload::Resize {
                cols,
                rows,
                pixel_width,
                pixel_height,
                cell_width,
                cell_height,
            });
        }
    }

    pub(super) fn record_session_exited(&mut self, exit_code: Option<i32>) {
        if let Some(active) = self.active.as_mut() {
            active.push(RecordingEventPayload::SessionExited { exit_code });
        }
    }

    pub(super) fn stop(&mut self) -> Result<String, RecordingError> {
        let active = self.active.take().ok_or_else(RecordingError::not_active)?;
        if active.overflowed {
            return Err(RecordingError::capacity_exceeded());
        }
        active.encode_ndjson()
    }

    pub(super) fn prepare_finalize(
        &mut self,
        handoff_directory: &Path,
        requested_job_id: Option<&str>,
    ) -> Result<RecordingFinalizeJob, RecordingError> {
        let handoff_directory = secure_handoff_directory(handoff_directory)?;
        let paths = match requested_job_id {
            Some(job_id) => {
                if !valid_recording_finalize_job_id(job_id) {
                    return Err(RecordingError::invalid_handoff());
                }
                recording_finalize_paths(&handoff_directory, job_id.to_owned())?
            }
            None => select_recording_finalize_paths(&handoff_directory)?,
        };
        let active = self
            .active
            .as_ref()
            .ok_or_else(RecordingError::not_active)?;
        if active.overflowed {
            return Err(RecordingError::capacity_exceeded());
        }
        let faults = take_recording_finalize_faults();
        let admission = if faults.admission_capacity {
            RecordingFinalizeAdmission::CapacityExceeded
        } else {
            register_recording_finalize_job(&paths.job_id)
        };
        match admission {
            RecordingFinalizeAdmission::Admitted => {}
            RecordingFinalizeAdmission::Duplicate => {
                return Err(RecordingError::handoff_collision());
            }
            RecordingFinalizeAdmission::CapacityExceeded => {
                return Err(RecordingError::finalize_capacity_exceeded());
            }
        }
        let active = self
            .active
            .take()
            .expect("recording was checked before finalize job registration");
        let job_id = paths.job_id.clone();
        let handoff_path = paths.handoff_path.to_string_lossy().into_owned();
        let error_path = paths.error_path.to_string_lossy().into_owned();
        if let Err(active) = spawn_recording_finalize_worker(active, paths, faults) {
            rollback_recording_finalize_job(&job_id);
            self.active = Some(active);
            return Err(RecordingError::finalize_worker_spawn_failed());
        }
        Ok(RecordingFinalizeJob {
            job_id,
            handoff_path,
            error_path,
        })
    }

    pub(super) fn cancel(&mut self) -> Result<(), RecordingError> {
        self.active.take().ok_or_else(RecordingError::not_active)?;
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct RecordingFinalizeFaults {
    admission_capacity: bool,
    worker_spawn: bool,
    handoff_write: bool,
    error_marker_write: bool,
}

#[cfg(test)]
thread_local! {
    static NEXT_RECORDING_FINALIZE_FAULTS: std::cell::Cell<RecordingFinalizeFaults> =
        const { std::cell::Cell::new(RecordingFinalizeFaults {
            admission_capacity: false,
            worker_spawn: false,
            handoff_write: false,
            error_marker_write: false,
        }) };
}

#[cfg(test)]
fn take_recording_finalize_faults() -> RecordingFinalizeFaults {
    NEXT_RECORDING_FINALIZE_FAULTS.with(|faults| faults.take())
}

#[cfg(not(test))]
fn take_recording_finalize_faults() -> RecordingFinalizeFaults {
    RecordingFinalizeFaults::default()
}

fn spawn_recording_finalize_worker(
    active: ActiveRecording,
    paths: RecordingFinalizePaths,
    faults: RecordingFinalizeFaults,
) -> Result<(), ActiveRecording> {
    if faults.worker_spawn {
        return Err(active);
    }
    let active = Arc::new(Mutex::new(Some(active)));
    let worker_active = Arc::clone(&active);
    let result = thread::Builder::new()
        .name("ianvs-rec-final".to_string())
        .spawn(move || {
            let active = worker_active
                .lock()
                .take()
                .expect("finalize worker owns the admitted recording");
            finalize_recording_worker(
                &paths.job_id,
                active,
                &paths.part_path,
                &paths.handoff_path,
                &paths.error_path,
                faults,
            );
        });
    match result {
        Ok(_worker) => Ok(()),
        Err(_) => Err(active
            .lock()
            .take()
            .expect("failed spawn preserves the admitted recording")),
    }
}

#[derive(Debug)]
struct RecordingFinalizePaths {
    job_id: String,
    handoff_path: PathBuf,
    part_path: PathBuf,
    error_path: PathBuf,
}

fn select_recording_finalize_paths(
    handoff_directory: &Path,
) -> Result<RecordingFinalizePaths, RecordingError> {
    for _ in 0..RECORDING_FINALIZE_JOB_ID_ATTEMPTS {
        let job_id = random_recording_finalize_job_id()?;
        match recording_finalize_paths(handoff_directory, job_id) {
            Ok(paths) => return Ok(paths),
            Err(error) if error == RecordingError::handoff_collision() => continue,
            Err(error) => return Err(error),
        }
    }
    Err(RecordingError::handoff_collision())
}

fn random_recording_finalize_job_id() -> Result<String, RecordingError> {
    let mut random_bytes = [0_u8; RECORDING_FINALIZE_JOB_ID_BYTES];
    getrandom::fill(&mut random_bytes).map_err(|_| RecordingError::entropy())?;
    let mut job_id = String::with_capacity(RECORDING_FINALIZE_JOB_ID_BYTES * 2);
    for byte in random_bytes {
        write!(&mut job_id, "{byte:02x}").map_err(|_| RecordingError::entropy())?;
    }
    Ok(job_id)
}

pub(super) fn valid_recording_finalize_job_id(job_id: &str) -> bool {
    job_id.len() == RECORDING_FINALIZE_JOB_ID_BYTES * 2
        && job_id
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn recording_finalize_paths(
    handoff_directory: &Path,
    job_id: String,
) -> Result<RecordingFinalizePaths, RecordingError> {
    let file_name = format!("{RECORDING_HANDOFF_PREFIX}{job_id}{RECORDING_HANDOFF_SUFFIX}");
    let handoff_path = handoff_directory.join(file_name);
    let part_path = handoff_path.with_extension("ndjson.part");
    let error_path = handoff_path.with_extension("ndjson.error.json");
    let error_part_path = error_path.with_extension("json.part");
    for path in [&handoff_path, &part_path, &error_path, &error_part_path] {
        match fs::symlink_metadata(path) {
            Ok(_) => return Err(RecordingError::handoff_collision()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(_) => return Err(RecordingError::invalid_handoff()),
        }
    }
    Ok(RecordingFinalizePaths {
        job_id,
        handoff_path,
        part_path,
        error_path,
    })
}

struct ActiveRecording {
    session_id: u64,
    created_at_utc: String,
    input_policy: RecordingInputPolicy,
    started_at: Instant,
    events: Vec<RecordingEvent>,
    payload_bytes: usize,
    overflowed: bool,
    max_events: usize,
    max_payload_bytes: usize,
}

impl ActiveRecording {
    fn push(&mut self, payload: RecordingEventPayload) {
        self.push_at(payload, self.started_at.elapsed().as_micros() as u64);
    }

    fn push_at(&mut self, payload: RecordingEventPayload, monotonic_offset_micros: u64) {
        if self.overflowed {
            return;
        }
        let payload_bytes = payload.byte_len();
        if self.events.len() >= self.max_events
            || self.payload_bytes.saturating_add(payload_bytes) > self.max_payload_bytes
        {
            self.overflowed = true;
            return;
        }
        self.payload_bytes += payload_bytes;
        self.events.push(RecordingEvent {
            monotonic_offset_micros,
            payload,
        });
    }

    fn encode_ndjson(self) -> Result<String, RecordingError> {
        let mut encoded = Vec::new();
        self.write_ndjson(&mut encoded)?;
        String::from_utf8(encoded).map_err(|_| RecordingError::serialize())
    }

    fn write_ndjson<W: Write>(self, writer: &mut W) -> Result<(), RecordingError> {
        write_recording_line(
            writer,
            &json!({
            "record_type": "metadata",
            "schema_version": RECORDING_SCHEMA_VERSION,
            "session_id": self.session_id.to_string(),
            "created_at_utc": self.created_at_utc,
            "input_policy": self.input_policy.as_str(),
            }),
        )?;
        for (sequence, event) in self.events.into_iter().enumerate() {
            write_recording_line(
                writer,
                &json!({
                "record_type": "event",
                "schema_version": RECORDING_SCHEMA_VERSION,
                "session_id": self.session_id.to_string(),
                "sequence": sequence,
                "monotonic_offset_micros": event.monotonic_offset_micros,
                "event_kind": event.payload.kind(),
                "payload": event.payload.into_json(),
                }),
            )?;
        }
        Ok(())
    }
}

fn write_recording_line<W: Write>(writer: &mut W, value: &Value) -> Result<(), RecordingError> {
    serde_json::to_writer(&mut *writer, value).map_err(|_| RecordingError::serialize())?;
    writer
        .write_all(b"\n")
        .map_err(|_| RecordingError::serialize())
}

fn secure_handoff_directory(path: &Path) -> Result<PathBuf, RecordingError> {
    if !path.is_absolute() {
        return Err(RecordingError::invalid_handoff());
    }
    let metadata = fs::symlink_metadata(path).map_err(|_| RecordingError::invalid_handoff())?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(RecordingError::invalid_handoff());
    }
    let canonical = fs::canonicalize(path).map_err(|_| RecordingError::invalid_handoff())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if metadata.mode() & 0o777 != 0o700 || metadata.uid() != unsafe { libc::geteuid() } {
            return Err(RecordingError::invalid_handoff());
        }
    }
    Ok(canonical)
}

fn finalize_recording_worker(
    job_id: &str,
    active: ActiveRecording,
    part_path: &Path,
    handoff_path: &Path,
    error_path: &Path,
    faults: RecordingFinalizeFaults,
) {
    let result = if faults.handoff_write {
        Err(RecordingError::serialize())
    } else {
        write_recording_handoff(active, part_path, handoff_path)
    };
    match result {
        Ok(()) => complete_recording_finalize_job(job_id, RecordingFinalizeStatus::Ready),
        Err(error) => {
            complete_recording_finalize_job(job_id, RecordingFinalizeStatus::Failed(error));
            let _ = fs::remove_file(part_path);
            if !faults.error_marker_write {
                let _ = write_finalize_error(error_path, error.code, error.message);
            }
        }
    }
}

fn write_recording_handoff(
    active: ActiveRecording,
    part_path: &Path,
    handoff_path: &Path,
) -> Result<(), RecordingError> {
    let file = secure_create_file(part_path).map_err(|_| RecordingError::serialize())?;
    let mut writer = BufWriter::new(file);
    active.write_ndjson(&mut writer)?;
    writer.flush().map_err(|_| RecordingError::serialize())?;
    let file = writer
        .into_inner()
        .map_err(|_| RecordingError::serialize())?;
    file.sync_all().map_err(|_| RecordingError::serialize())?;
    fs::rename(part_path, handoff_path).map_err(|_| RecordingError::serialize())?;
    sync_parent_directory(handoff_path).map_err(|_| RecordingError::serialize())
}

fn secure_create_file(path: &Path) -> io::Result<File> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(path)
}

fn write_finalize_error(path: &Path, code: &str, message: &str) -> io::Result<()> {
    let part_path = path.with_extension("json.part");
    let mut file = secure_create_file(&part_path)?;
    serde_json::to_writer(&mut file, &json!({"code": code, "message": message}))
        .map_err(io::Error::other)?;
    file.write_all(b"\n")?;
    file.sync_all()?;
    fs::rename(&part_path, path)?;
    sync_parent_directory(path)
}

fn sync_parent_directory(path: &Path) -> io::Result<()> {
    let Some(parent) = path.parent() else {
        return Ok(());
    };
    File::open(parent)?.sync_all()
}

struct RecordingEvent {
    monotonic_offset_micros: u64,
    payload: RecordingEventPayload,
}

enum RecordingEventPayload {
    SessionStarted {
        terminal_emulation: &'static str,
        cols: u16,
        rows: u16,
    },
    PtyOutput(Vec<u8>),
    UserInput {
        bytes: Option<Vec<u8>>,
        byte_length: usize,
    },
    Resize {
        cols: u16,
        rows: u16,
        pixel_width: u16,
        pixel_height: u16,
        cell_width: u16,
        cell_height: u16,
    },
    SessionExited {
        exit_code: Option<i32>,
    },
}

impl RecordingEventPayload {
    fn kind(&self) -> &'static str {
        match self {
            Self::SessionStarted { .. } => "session_started",
            Self::PtyOutput(_) => "pty_output",
            Self::UserInput { .. } => "user_input",
            Self::Resize { .. } => "resize",
            Self::SessionExited { .. } => "session_exited",
        }
    }

    fn byte_len(&self) -> usize {
        match self {
            Self::PtyOutput(bytes) => bytes.len(),
            Self::UserInput {
                bytes: Some(bytes), ..
            } => bytes.len(),
            _ => 0,
        }
    }

    fn into_json(self) -> Value {
        match self {
            Self::SessionStarted {
                terminal_emulation,
                cols,
                rows,
            } => json!({
                "terminal_emulation": terminal_emulation,
                "cols": cols,
                "rows": rows,
            }),
            Self::PtyOutput(bytes) => json!({
                "bytes_base64": BASE64_STANDARD.encode(bytes),
            }),
            Self::UserInput {
                bytes: Some(bytes), ..
            } => json!({
                "bytes_base64": BASE64_STANDARD.encode(bytes),
            }),
            Self::UserInput {
                bytes: None,
                byte_length,
            } => json!({
                "byte_length": byte_length,
                "redacted": true,
            }),
            Self::Resize {
                cols,
                rows,
                pixel_width,
                pixel_height,
                cell_width,
                cell_height,
            } => json!({
                "cols": cols,
                "rows": rows,
                "pixel_width": pixel_width,
                "pixel_height": pixel_height,
                "cell_width": cell_width,
                "cell_height": cell_height,
            }),
            Self::SessionExited { exit_code } => json!({ "exit_code": exit_code }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn private_tempdir() -> tempfile::TempDir {
        let directory = tempfile::tempdir().unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::{MetadataExt, PermissionsExt};
            fs::set_permissions(directory.path(), fs::Permissions::from_mode(0o700)).unwrap();
            assert_eq!(
                fs::metadata(directory.path()).unwrap().mode() & 0o777,
                0o700
            );
        }
        directory
    }

    fn wait_for_finalize_status(
        job_id: &str,
        expected: RecordingFinalizeStatus,
    ) -> RecordingFinalizeStatus {
        for _ in 0..200 {
            let status = recording_finalize_status(job_id, false);
            if status == expected {
                return status;
            }
            thread::sleep(Duration::from_millis(5));
        }
        recording_finalize_status(job_id, false)
    }

    #[test]
    fn capture_orders_raw_output_redacted_input_resize_and_exit() {
        let mut recording = SessionRecording::with_limits(8, 1024);
        recording
            .start(
                42,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                120,
                32,
                b"\x1b[2J\x1b[Hexisting screen\x1b[3;5H".to_vec(),
            )
            .unwrap();
        recording.record_pty_output(b"ready\r\n");
        recording.record_user_input(b"secret");
        recording.record_resize(100, 30, 1000, 600, 10, 20);
        recording.record_session_exited(Some(0));

        let source = recording.stop().unwrap();
        let lines = source
            .lines()
            .map(|line| serde_json::from_str::<Value>(line).unwrap())
            .collect::<Vec<_>>();

        assert_eq!(lines.len(), 7);
        assert_eq!(lines[0]["input_policy"], "redact");
        assert_eq!(lines[2]["event_kind"], "pty_output");
        assert_eq!(lines[2]["monotonic_offset_micros"], 0);
        assert_eq!(
            BASE64_STANDARD
                .decode(lines[2]["payload"]["bytes_base64"].as_str().unwrap())
                .unwrap(),
            b"\x1b[2J\x1b[Hexisting screen\x1b[3;5H"
        );
        assert_eq!(lines[4]["event_kind"], "user_input");
        assert_eq!(lines[4]["payload"]["redacted"], true);
        assert_eq!(lines[4]["payload"]["byte_length"], 6);
        assert!(lines[4]["payload"].get("bytes_base64").is_none());
        assert_eq!(lines[5]["event_kind"], "resize");
        assert_eq!(lines[6]["event_kind"], "session_exited");
        assert_eq!(lines[6]["payload"]["exit_code"], 0);
        for (sequence, line) in lines.iter().skip(1).enumerate() {
            assert_eq!(line["sequence"], sequence);
        }
    }

    #[test]
    fn capacity_overflow_never_returns_a_partial_recording() {
        let mut recording = SessionRecording::with_limits(2, 3);
        recording
            .start(
                7,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Record,
                "vt220",
                80,
                24,
                Vec::new(),
            )
            .unwrap();
        recording.record_pty_output(b"abc");
        recording.record_user_input(b"d");

        assert_eq!(recording.stop(), Err(RecordingError::capacity_exceeded()));
    }

    #[test]
    fn finalize_prepare_returns_before_worker_handoff_and_releases_recording() {
        let directory = private_tempdir();
        let mut recording = SessionRecording::with_limits(8, 1024);
        recording
            .start(
                42,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                80,
                24,
                Vec::new(),
            )
            .unwrap();
        recording.record_pty_output(b"ready\r\n");

        let job = recording.prepare_finalize(directory.path(), None).unwrap();

        assert_eq!(job.job_id.len(), RECORDING_FINALIZE_JOB_ID_BYTES * 2);
        assert!(job.job_id.bytes().all(|byte| byte.is_ascii_hexdigit()));
        assert!(
            Path::new(&job.handoff_path)
                .file_name()
                .unwrap()
                .to_string_lossy()
                .starts_with(RECORDING_HANDOFF_PREFIX)
        );
        recording
            .start(
                43,
                "2026-07-21T00:00:01.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                80,
                24,
                Vec::new(),
            )
            .unwrap();

        let handoff = Path::new(&job.handoff_path);
        for _ in 0..200 {
            if handoff.exists() {
                break;
            }
            thread::sleep(Duration::from_millis(5));
        }
        assert!(handoff.exists());
        assert_eq!(
            wait_for_finalize_status(&job.job_id, RecordingFinalizeStatus::Ready),
            RecordingFinalizeStatus::Ready
        );
        assert_eq!(
            recording_finalize_status(&job.job_id, true),
            RecordingFinalizeStatus::Ready
        );
        assert!(!Path::new(&job.error_path).exists());
        assert!(!handoff.with_extension("ndjson.part").exists());
        let source = fs::read_to_string(handoff).unwrap();
        let lines = source
            .lines()
            .map(|line| serde_json::from_str::<Value>(line).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(lines[0]["session_id"], "42");
        assert_eq!(lines[2]["event_kind"], "pty_output");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(handoff).unwrap().permissions().mode() & 0o777,
                0o600
            );
            assert_eq!(
                fs::metadata(directory.path()).unwrap().permissions().mode() & 0o777,
                0o700
            );
        }
    }

    #[test]
    fn finalize_prepare_uses_a_preallocated_lowercase_job_id() {
        let directory = private_tempdir();
        let mut recording = SessionRecording::with_limits(8, 1024);
        recording
            .start(
                42,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                80,
                24,
                Vec::new(),
            )
            .unwrap();
        let requested = "0123456789abcdef0123456789abcdef";

        let job = recording
            .prepare_finalize(directory.path(), Some(requested))
            .unwrap();

        assert_eq!(job.job_id, requested);
        assert!(job.handoff_path.ends_with(&format!("{requested}.ndjson")));
        assert_eq!(
            wait_for_finalize_status(&job.job_id, RecordingFinalizeStatus::Ready),
            RecordingFinalizeStatus::Ready
        );
        assert_eq!(
            recording_finalize_status(&job.job_id, true),
            RecordingFinalizeStatus::Ready
        );
    }

    #[test]
    fn running_finalize_status_cannot_be_consumed_and_unknown_does_not_create_a_job() {
        let job_id = "11111111111111111111111111111111";
        assert_eq!(
            recording_finalize_status(job_id, true),
            RecordingFinalizeStatus::Unknown
        );
        assert_eq!(
            register_recording_finalize_job(job_id),
            RecordingFinalizeAdmission::Admitted
        );
        assert_eq!(
            recording_finalize_status(job_id, true),
            RecordingFinalizeStatus::Running
        );
        assert_eq!(
            recording_finalize_status(job_id, false),
            RecordingFinalizeStatus::Running
        );
        complete_recording_finalize_job(job_id, RecordingFinalizeStatus::Ready);
        assert_eq!(
            recording_finalize_status(job_id, true),
            RecordingFinalizeStatus::Ready
        );
        assert_eq!(
            recording_finalize_status(job_id, false),
            RecordingFinalizeStatus::Unknown
        );
    }

    #[test]
    fn finalize_registry_bounds_terminal_entries_without_evicting_running_jobs() {
        let mut registry = RecordingFinalizeRegistry::with_limits(5, 2, 7);
        let running_one = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        let running_two = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
        let first_terminal = "cccccccccccccccccccccccccccccccc";
        let second_terminal = "dddddddddddddddddddddddddddddddd";
        let third_terminal = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
        for job_id in [
            running_one,
            running_two,
            first_terminal,
            second_terminal,
            third_terminal,
        ] {
            assert_eq!(
                registry.register(job_id),
                RecordingFinalizeAdmission::Admitted
            );
        }

        registry.complete(first_terminal, RecordingFinalizeStatus::Ready);
        registry.complete(
            second_terminal,
            RecordingFinalizeStatus::Failed(RecordingError::serialize()),
        );
        registry.complete(third_terminal, RecordingFinalizeStatus::Ready);

        assert_eq!(
            registry.status(first_terminal, false),
            RecordingFinalizeStatus::Unknown
        );
        assert_eq!(
            registry.status(second_terminal, false),
            RecordingFinalizeStatus::Failed(RecordingError::serialize())
        );
        assert_eq!(
            registry.status(third_terminal, false),
            RecordingFinalizeStatus::Ready
        );
        assert_eq!(
            registry.status(running_one, true),
            RecordingFinalizeStatus::Running
        );
        assert_eq!(
            registry.status(running_two, true),
            RecordingFinalizeStatus::Running
        );
        assert_eq!(registry.terminal_order.len(), 2);
        assert_eq!(registry.jobs.len(), 4);
        assert_eq!(registry.running_count, 2);
    }

    #[test]
    fn concurrent_finalize_admission_never_exceeds_the_in_flight_limit() {
        use std::sync::Barrier;

        let registry = Arc::new(Mutex::new(RecordingFinalizeRegistry::with_limits(4, 8, 12)));
        let barrier = Arc::new(Barrier::new(17));
        let workers = (0..16)
            .map(|index| {
                let registry = Arc::clone(&registry);
                let barrier = Arc::clone(&barrier);
                thread::spawn(move || {
                    barrier.wait();
                    registry.lock().register(&format!("{index:032x}"))
                })
            })
            .collect::<Vec<_>>();

        barrier.wait();
        let admitted = workers
            .into_iter()
            .map(|worker| worker.join().unwrap())
            .filter(|outcome| *outcome == RecordingFinalizeAdmission::Admitted)
            .count();
        let registry = registry.lock();

        assert_eq!(admitted, 4);
        assert_eq!(registry.running_count, 4);
        assert_eq!(registry.jobs.len(), 4);
        assert!(
            registry
                .jobs
                .values()
                .all(|status| *status == RecordingFinalizeStatus::Running)
        );
    }

    #[test]
    fn total_registry_limit_evicts_only_terminal_status_for_new_admission() {
        let mut registry = RecordingFinalizeRegistry::with_limits(4, 4, 3);
        let first = "01010101010101010101010101010101";
        let second = "02020202020202020202020202020202";
        let third = "03030303030303030303030303030303";
        let fourth = "04040404040404040404040404040404";
        for job_id in [first, second, third] {
            assert_eq!(
                registry.register(job_id),
                RecordingFinalizeAdmission::Admitted
            );
        }
        assert_eq!(
            registry.register(fourth),
            RecordingFinalizeAdmission::CapacityExceeded
        );

        registry.complete(first, RecordingFinalizeStatus::Ready);
        assert_eq!(
            registry.register(fourth),
            RecordingFinalizeAdmission::Admitted
        );

        assert_eq!(registry.jobs.len(), 3);
        assert_eq!(registry.running_count, 3);
        assert_eq!(
            registry.status(first, false),
            RecordingFinalizeStatus::Unknown
        );
        assert_eq!(
            registry.status(second, false),
            RecordingFinalizeStatus::Running
        );
        assert_eq!(
            registry.status(third, false),
            RecordingFinalizeStatus::Running
        );
        assert_eq!(
            registry.status(fourth, false),
            RecordingFinalizeStatus::Running
        );
    }

    #[test]
    fn consume_and_complete_race_never_removes_a_running_job() {
        use std::sync::Barrier;

        for index in 0..32 {
            let job_id = format!("9{index:031x}");
            let registry = Arc::new(Mutex::new(RecordingFinalizeRegistry::with_limits(1, 1, 2)));
            assert_eq!(
                registry.lock().register(&job_id),
                RecordingFinalizeAdmission::Admitted
            );
            let barrier = Arc::new(Barrier::new(3));
            let consumer = {
                let registry = Arc::clone(&registry);
                let barrier = Arc::clone(&barrier);
                let job_id = job_id.clone();
                thread::spawn(move || {
                    barrier.wait();
                    registry.lock().status(&job_id, true)
                })
            };
            let completer = {
                let registry = Arc::clone(&registry);
                let barrier = Arc::clone(&barrier);
                let job_id = job_id.clone();
                thread::spawn(move || {
                    barrier.wait();
                    registry
                        .lock()
                        .complete(&job_id, RecordingFinalizeStatus::Ready);
                })
            };

            barrier.wait();
            let observed = consumer.join().unwrap();
            completer.join().unwrap();
            let final_status = registry.lock().status(&job_id, false);
            match observed {
                RecordingFinalizeStatus::Running => {
                    assert_eq!(final_status, RecordingFinalizeStatus::Ready);
                }
                RecordingFinalizeStatus::Ready => {
                    assert_eq!(final_status, RecordingFinalizeStatus::Unknown);
                }
                unexpected => panic!("unexpected racing status: {unexpected:?}"),
            }
        }
    }

    #[test]
    fn finalize_status_is_failed_when_handoff_and_error_marker_writes_both_fail() {
        let directory = private_tempdir();
        let mut recording = SessionRecording::with_limits(8, 1024);
        recording
            .start(
                42,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                80,
                24,
                Vec::new(),
            )
            .unwrap();
        let job_id = "22222222222222222222222222222222";
        NEXT_RECORDING_FINALIZE_FAULTS.with(|faults| {
            faults.set(RecordingFinalizeFaults {
                admission_capacity: false,
                worker_spawn: false,
                handoff_write: true,
                error_marker_write: true,
            });
        });

        let job = recording
            .prepare_finalize(directory.path(), Some(job_id))
            .unwrap();
        let expected = RecordingFinalizeStatus::Failed(RecordingError::serialize());

        assert_eq!(wait_for_finalize_status(job_id, expected), expected);
        assert!(!Path::new(&job.handoff_path).exists());
        assert!(!Path::new(&job.error_path).exists());
        assert_eq!(recording_finalize_status(job_id, false), expected);
        assert_eq!(recording_finalize_status(job_id, true), expected);
        assert_eq!(
            recording_finalize_status(job_id, false),
            RecordingFinalizeStatus::Unknown
        );
    }

    #[test]
    fn finalize_capacity_failure_preserves_active_recording_for_retry() {
        let directory = private_tempdir();
        let mut recording = SessionRecording::with_limits(8, 1024);
        recording
            .start(
                42,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                80,
                24,
                Vec::new(),
            )
            .unwrap();
        recording.record_pty_output(b"preserved across capacity rejection\r\n");
        let job_id = "66666666666666666666666666666666";
        NEXT_RECORDING_FINALIZE_FAULTS.with(|faults| {
            faults.set(RecordingFinalizeFaults {
                admission_capacity: true,
                worker_spawn: false,
                handoff_write: false,
                error_marker_write: false,
            });
        });

        assert_eq!(
            recording.prepare_finalize(directory.path(), Some(job_id)),
            Err(RecordingError::finalize_capacity_exceeded())
        );
        assert!(recording.active.is_some());
        assert_eq!(
            recording_finalize_status(job_id, false),
            RecordingFinalizeStatus::Unknown
        );

        let retry = recording
            .prepare_finalize(directory.path(), Some(job_id))
            .unwrap();
        assert_eq!(
            wait_for_finalize_status(job_id, RecordingFinalizeStatus::Ready),
            RecordingFinalizeStatus::Ready
        );
        let source = fs::read_to_string(&retry.handoff_path).unwrap();
        assert!(source.contains("cHJlc2VydmVkIGFjcm9zcyBjYXBhY2l0eSByZWplY3Rpb24NCg=="));
        assert_eq!(
            recording_finalize_status(job_id, true),
            RecordingFinalizeStatus::Ready
        );
    }

    #[test]
    fn finalize_worker_spawn_failure_rolls_back_status_and_preserves_active_recording() {
        let directory = private_tempdir();
        let mut recording = SessionRecording::with_limits(8, 1024);
        recording
            .start(
                42,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                80,
                24,
                Vec::new(),
            )
            .unwrap();
        recording.record_pty_output(b"preserved across failed spawn\r\n");
        let job_id = "55555555555555555555555555555555";
        NEXT_RECORDING_FINALIZE_FAULTS.with(|faults| {
            faults.set(RecordingFinalizeFaults {
                admission_capacity: false,
                worker_spawn: true,
                handoff_write: false,
                error_marker_write: false,
            });
        });

        assert_eq!(
            recording.prepare_finalize(directory.path(), Some(job_id)),
            Err(RecordingError::finalize_worker_spawn_failed())
        );
        assert!(recording.active.is_some());
        assert_eq!(
            recording_finalize_status(job_id, false),
            RecordingFinalizeStatus::Unknown
        );

        let retry = recording
            .prepare_finalize(directory.path(), Some(job_id))
            .unwrap();
        assert_eq!(
            wait_for_finalize_status(job_id, RecordingFinalizeStatus::Ready),
            RecordingFinalizeStatus::Ready
        );
        let source = fs::read_to_string(&retry.handoff_path).unwrap();
        assert!(source.contains("cHJlc2VydmVkIGFjcm9zcyBmYWlsZWQgc3Bhd24NCg=="));
        assert_eq!(
            recording_finalize_status(job_id, true),
            RecordingFinalizeStatus::Ready
        );
    }

    #[test]
    fn finalize_prepare_rejects_an_invalid_preallocated_job_id() {
        let directory = private_tempdir();
        let mut recording = SessionRecording::with_limits(8, 1024);
        recording
            .start(
                42,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                80,
                24,
                Vec::new(),
            )
            .unwrap();

        assert_eq!(
            recording.prepare_finalize(directory.path(), Some("../INVALID")),
            Err(RecordingError::invalid_handoff())
        );
    }

    #[test]
    fn finalize_prepare_rejects_relative_handoff_directories() {
        let mut recording = SessionRecording::with_limits(8, 1024);
        recording
            .start(
                7,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                80,
                24,
                Vec::new(),
            )
            .unwrap();

        assert_eq!(
            recording.prepare_finalize(Path::new("relative"), None),
            Err(RecordingError::invalid_handoff())
        );
    }

    #[test]
    fn stale_error_or_partial_file_is_a_collision_and_is_never_reused() {
        let directory = private_tempdir();
        let job_id = "ab".repeat(RECORDING_FINALIZE_JOB_ID_BYTES);
        let paths = recording_finalize_paths(directory.path(), job_id.clone()).unwrap();
        fs::write(&paths.error_path, b"stale error").unwrap();

        assert_eq!(
            recording_finalize_paths(directory.path(), job_id.clone()).unwrap_err(),
            RecordingError::handoff_collision()
        );
        fs::remove_file(&paths.error_path).unwrap();
        fs::write(&paths.part_path, b"stale partial payload").unwrap();
        assert_eq!(
            recording_finalize_paths(directory.path(), job_id).unwrap_err(),
            RecordingError::handoff_collision()
        );
    }

    #[cfg(unix)]
    #[test]
    fn finalize_prepare_rejects_symlink_handoff_directory() {
        use std::os::unix::fs::symlink;

        let directory = private_tempdir();
        let link_parent = private_tempdir();
        let link = link_parent.path().join("handoff-link");
        symlink(directory.path(), &link).unwrap();
        let mut recording = SessionRecording::with_limits(8, 1024);
        recording
            .start(
                7,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                80,
                24,
                Vec::new(),
            )
            .unwrap();

        assert_eq!(
            recording.prepare_finalize(&link, None),
            Err(RecordingError::invalid_handoff())
        );
    }

    #[cfg(unix)]
    #[test]
    fn finalize_prepare_rejects_and_does_not_chmod_shared_directory() {
        use std::os::unix::fs::{MetadataExt, PermissionsExt};

        let directory = tempfile::tempdir().unwrap();
        fs::set_permissions(directory.path(), fs::Permissions::from_mode(0o755)).unwrap();
        let mut recording = SessionRecording::with_limits(8, 1024);
        recording
            .start(
                7,
                "2026-07-21T00:00:00.000Z".to_string(),
                RecordingInputPolicy::Redact,
                "xterm256",
                80,
                24,
                Vec::new(),
            )
            .unwrap();

        assert_eq!(
            recording.prepare_finalize(directory.path(), None),
            Err(RecordingError::invalid_handoff())
        );
        assert_eq!(
            fs::metadata(directory.path()).unwrap().mode() & 0o777,
            0o755
        );
    }
}
