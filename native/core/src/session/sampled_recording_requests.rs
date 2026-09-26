//! Capture ownership survives SessionStore removal. Requests only reserve jobs
//! or read bounded state; filesystem work runs on a background coordinator.
use super::*;
use crate::recording::{RecordingMetadata, RecordingSummary, WriterMonitor, WriterPhase};
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::path::{Component, Path};
use std::sync::{LazyLock, Weak};

const MAX_RETAINED_JOBS: usize = 128;
const MAX_UNSETTLED_JOBS: usize = 16;
static JOBS: LazyLock<Mutex<HashMap<String, Arc<CaptureJob>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
struct StartRequest {
    schema_version: u32,
    capture_id: String,
    bundle_path: String,
    metadata: RecordingMetadata,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct IdentityRequest {
    schema_version: u32,
    capture_id: String,
    bundle_path: String,
}

enum CaptureState {
    Starting,
    Attached(WriterMonitor),
    StartFailed(String),
}

struct CaptureJob {
    session_id: u64,
    request: StartRequest,
    stop_requested: AtomicBool,
    state: Mutex<CaptureState>,
}

impl CaptureJob {
    fn response(&self) -> Value {
        let mut written = RecordingSummary::default();
        let mut committed = RecordingSummary::default();
        let mut error = None;
        let stop_requested = self.stop_requested.load(Ordering::Acquire);
        let (phase, settled) = match &*self.state.lock() {
            CaptureState::Starting => ("starting", false),
            CaptureState::StartFailed(message) => {
                error = Some(message.clone());
                ("failed", true)
            }
            CaptureState::Attached(monitor) => {
                let status = monitor.status();
                written = status.written;
                committed = status.committed;
                error = status.error;
                let phase = match status.phase {
                    WriterPhase::Capturing if stop_requested => "stopping",
                    WriterPhase::Capturing => "capturing",
                    WriterPhase::Finishing => "stopping",
                    WriterPhase::Finished => "finished",
                    WriterPhase::Interrupted => "interrupted",
                    WriterPhase::Failed => "failed",
                };
                (phase, status.settled)
            }
        };
        json!({
            "ok": true,
            "schema_version": 2,
            "capture_id": self.request.capture_id,
            "bundle_path": self.request.bundle_path,
            "session_id": self.session_id.to_string(),
            "phase": phase,
            "settled": settled,
            "stop_requested": stop_requested,
            "written": written,
            "committed": committed,
            "error": error,
        })
    }

    fn settled(&self) -> bool {
        match &*self.state.lock() {
            CaptureState::Starting => false,
            CaptureState::StartFailed(_) => true,
            CaptureState::Attached(monitor) => monitor.status().settled,
        }
    }
}

pub(super) fn request(session_id: u64, operation: &str, payload: &Value) -> Value {
    if session_id == 0 {
        return error("invalid_request", "session id must be positive");
    }
    if operation == "terminal.sampled_recording_start" {
        let Ok(request) = serde_json::from_value::<StartRequest>(payload.clone()) else {
            return error("invalid_request", "invalid recording start payload");
        };
        if !valid_identity(
            request.schema_version,
            &request.capture_id,
            &request.bundle_path,
        ) || request.metadata.recording_id != request.capture_id
            || request.metadata.validate().is_err()
        {
            return error("invalid_request", "invalid recording identity or metadata");
        }
        return start(session_id, request);
    }
    let Ok(identity) = serde_json::from_value::<IdentityRequest>(payload.clone()) else {
        return error("invalid_request", "invalid recording identity payload");
    };
    if !valid_identity(
        identity.schema_version,
        &identity.capture_id,
        &identity.bundle_path,
    ) {
        return error("invalid_request", "invalid recording identity");
    }
    let mut jobs = JOBS.lock();
    let Some(job) = jobs.get(&identity.capture_id) else {
        // Unknown is not proof that a previous process finished writing. The
        // library must retain its filesystem claim until recovery establishes it.
        return error("unknown_capture", "recording ownership is unknown");
    };
    if job.session_id != session_id || job.request.bundle_path != identity.bundle_path {
        return error("identity_conflict", "recording identity does not match");
    }
    match operation {
        "terminal.sampled_recording_status" => job.response(),
        "terminal.sampled_recording_stop" => {
            job.stop_requested.store(true, Ordering::Release);
            job.response()
        }
        "terminal.sampled_recording_release" => {
            if !job.settled() {
                return error("capture_unsettled", "recording worker still owns its files");
            }
            let mut response = job.response();
            response["released"] = Value::Bool(true);
            jobs.remove(&identity.capture_id);
            response
        }
        _ => error("invalid_request", "unsupported recording operation"),
    }
}

fn valid_identity(version: u32, id: &str, path: &str) -> bool {
    let path_buf = Path::new(path);
    version == 2
        && id.len() == 32
        && id
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        && path.len() <= 4096
        && !path.contains('\0')
        && path_buf.is_absolute()
        && !path_buf.components().any(|c| c == Component::ParentDir)
        && path_buf.file_name().and_then(|v| v.to_str()) == Some(&format!("{id}.trailrec"))
}

fn start(session_id: u64, request: StartRequest) -> Value {
    let mut jobs = JOBS.lock();
    if let Some(job) = jobs.get(&request.capture_id) {
        return if job.session_id == session_id && job.request == request {
            job.response()
        } else {
            error(
                "identity_conflict",
                "capture id is already bound to another request",
            )
        };
    }
    if jobs.len() >= MAX_RETAINED_JOBS
        || jobs.values().filter(|job| !job.settled()).count() >= MAX_UNSETTLED_JOBS
    {
        return error("capture_capacity", "recording job capacity reached");
    }
    if jobs
        .values()
        .any(|job| job.session_id == session_id && !job.settled())
    {
        return error(
            "session_recording_active",
            "session already has an unsettled capture",
        );
    }
    let Ok(session) = STORE.get(session_id) else {
        return error(
            "session_not_found",
            "recording session is no longer available",
        );
    };
    let job = Arc::new(CaptureJob {
        session_id,
        request,
        stop_requested: AtomicBool::new(false),
        state: Mutex::new(CaptureState::Starting),
    });
    jobs.insert(job.request.capture_id.clone(), job.clone());
    let worker_job = job.clone();
    if let Err(error) = thread::Builder::new()
        .name("trail-capture-control".into())
        .spawn(move || run_job(worker_job, session))
    {
        *job.state.lock() = CaptureState::StartFailed(error.to_string());
    }
    job.response()
}

fn run_job(job: Arc<CaptureJob>, session: Arc<TerminalSession>) {
    let monitor = match session
        .start_sampled_capture(Path::new(&job.request.bundle_path), &job.request.metadata)
    {
        Ok(monitor) => monitor,
        Err(error) => {
            *job.state.lock() = CaptureState::StartFailed(error.to_string());
            return;
        }
    };
    *job.state.lock() = CaptureState::Attached(monitor.clone());
    let weak: Weak<TerminalSession> = Arc::downgrade(&session);
    drop(session);
    let mut stop_sent = false;
    while !monitor.status().settled {
        if !stop_sent && job.stop_requested.load(Ordering::Acquire) {
            if let Some(session) = weak.upgrade() {
                // A delayed stop must never stop a subsequent recording.
                let _ = session.stop_sampled_capture_matching(Some(&job.request.capture_id));
            }
            stop_sent = true;
        }
        thread::sleep(Duration::from_millis(100));
    }
}

fn error(code: &str, message: &str) -> Value {
    json!({"ok": false, "error": {"code": code, "message": message}})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_close_does_not_wait_on_capture_filesystem_creation() {
        let profile =
            json!({"id":"start-gate","name":"start-gate","launch":{"program":"/not/executed"}});
        let id = create_replay_session(&profile.to_string()).unwrap();
        let session = STORE.get(id).unwrap();
        let _starting = session.sampled_capture_start.lock();
        // The start-only gate represents a blocked filesystem create. Close
        // must complete while it is held, without waiting for disk access.
        close_session(id).unwrap();
        assert!(session.exited.load(Ordering::Acquire));
    }

    #[test]
    fn native_status_matches_the_shared_dart_contract_fixture() {
        let fixture: Value = serde_json::from_str(include_str!(
            "../../tests/fixtures/recording/sampled_capture_status_v2.json"
        ))
        .unwrap();
        let id = fixture["capture_id"].as_str().unwrap().to_string();
        let job = CaptureJob {
            session_id: 42,
            request: StartRequest {
                schema_version: 2,
                capture_id: id.clone(),
                bundle_path: fixture["bundle_path"].as_str().unwrap().to_string(),
                metadata: RecordingMetadata {
                    recording_id: id,
                    started_at_unix_millis: 42,
                    title: "fixture".into(),
                    hostname: None,
                },
            },
            stop_requested: AtomicBool::new(false),
            state: Mutex::new(CaptureState::Starting),
        };
        assert_eq!(job.response(), fixture);
    }
}
