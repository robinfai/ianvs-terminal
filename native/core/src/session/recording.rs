use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use serde_json::{Value, json};
use std::fmt::Write as FmtWrite;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Instant;

const RECORDING_HANDOFF_PREFIX: &str = ".ianvs-recording-handoff-";
const RECORDING_HANDOFF_SUFFIX: &str = ".ndjson";
const RECORDING_FINALIZE_JOB_ID_BYTES: usize = 16;
const RECORDING_FINALIZE_JOB_ID_ATTEMPTS: usize = 8;

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

#[derive(Debug, PartialEq, Eq)]
pub(super) struct RecordingError {
    pub(super) code: &'static str,
    pub(super) message: &'static str,
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
        let active = self.active.take().ok_or_else(RecordingError::not_active)?;
        if active.overflowed {
            return Err(RecordingError::capacity_exceeded());
        }
        let job_id = paths.job_id.clone();
        let handoff_path = paths.handoff_path.to_string_lossy().into_owned();
        let error_path = paths.error_path.to_string_lossy().into_owned();
        thread::spawn(move || {
            finalize_recording_worker(
                active,
                &paths.part_path,
                &paths.handoff_path,
                &paths.error_path,
            );
        });
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

fn valid_recording_finalize_job_id(job_id: &str) -> bool {
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
    active: ActiveRecording,
    part_path: &Path,
    handoff_path: &Path,
    error_path: &Path,
) {
    let result = write_recording_handoff(active, part_path, handoff_path);
    if let Err(error) = result {
        let _ = fs::remove_file(part_path);
        let _ = write_finalize_error(error_path, error.code, error.message);
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
