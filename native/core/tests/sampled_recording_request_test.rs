use ianvs_core::recording::{ContainerReader, RecordingCompletion};
use ianvs_core::session;
use ianvs_core::session_request::request_session_v1_json;
use serde_json::{Value, json};
use std::path::Path;
use std::time::{Duration, Instant};

struct Engine(u64);
impl Engine {
    fn new() -> Self {
        let profile =
            json!({"id":"capture-request", "name":"capture", "launch":{"program":"/not/executed"}});
        Self(session::create_replay_session(&profile.to_string()).unwrap())
    }
}
impl Drop for Engine {
    fn drop(&mut self) {
        let _ = session::close_session(self.0);
    }
}
fn call(id: u64, operation: &str, payload: Value) -> Value {
    let request = json!({
        "schema_version":1, "contract":"ianvs-session-request-v1",
        "request_id":"capture-test", "session_id":id.to_string(),
        "operation":format!("terminal.sampled_recording_{operation}"), "payload":payload,
    });
    let response: Value =
        serde_json::from_str(&request_session_v1_json(id, &request.to_string()).unwrap()).unwrap();
    assert_eq!(response["ok"], true, "{response}");
    response["payload"].clone()
}
fn start_payload(id: &str, parent: &Path) -> Value {
    json!({
        "schema_version":2, "capture_id":id,
        "bundle_path":parent.join(format!("{id}.trailrec")),
        "metadata":{"recording_id":id,"started_at_unix_millis":42,"title":"部署复盘","hostname":"host-a"},
    })
}
fn identity(start: &Value) -> Value {
    json!({"schema_version":2,"capture_id":start["capture_id"],"bundle_path":start["bundle_path"]})
}
fn wait_for(id: u64, start: &Value, check: impl Fn(&Value) -> bool) -> Value {
    let deadline = Instant::now() + Duration::from_secs(8);
    loop {
        let status = call(id, "status", identity(start));
        assert_eq!(status["ok"], true, "{status}");
        if check(&status) {
            return status;
        }
        assert!(Instant::now() < deadline, "{status}");
        std::thread::sleep(Duration::from_millis(10));
    }
}
fn release(id: u64, start: &Value) {
    assert_eq!(call(id, "release", identity(start))["released"], true);
}

#[test]
fn stop_immediately_after_start_drains_and_same_start_is_idempotent() {
    let dir = tempfile::tempdir().unwrap();
    let engine = Engine::new();
    let start = start_payload("11111111111111111111111111111111", dir.path());
    session::replay_session_output(engine.0, b"existing capture screen").unwrap();
    assert_eq!(call(engine.0, "start", start.clone())["ok"], true);
    assert_eq!(call(engine.0, "start", start.clone())["ok"], true);
    assert_eq!(
        call(engine.0, "stop", identity(&start))["stop_requested"],
        true
    );
    let status = wait_for(engine.0, &start, |s| s["settled"] == true);
    assert_eq!(status["phase"], "finished", "{status}");
    assert_eq!(status["written"], status["committed"]);
    let path = Path::new(start["bundle_path"].as_str().unwrap());
    let report = ContainerReader::open(path)
        .unwrap()
        .scan(|| false, |_| Ok(()))
        .unwrap();
    assert_eq!(report.completion, RecordingCompletion::Finished);
    assert_eq!(report.summary.semantic_count, 2);
    release(engine.0, &start);
}

#[test]
fn detached_status_and_retry_survive_session_removal() {
    let dir = tempfile::tempdir().unwrap();
    let engine = Engine::new();
    let id = engine.0;
    let start = start_payload("22222222222222222222222222222222", dir.path());
    call(id, "start", start.clone());
    wait_for(id, &start, |s| s["phase"] == "capturing");
    assert_eq!(
        call(id, "release", identity(&start))["error"]["code"],
        "capture_unsettled"
    );
    session::replay_session_output(id, b"last screen before close").unwrap();
    drop(engine);
    let status = wait_for(id, &start, |s| s["settled"] == true);
    assert_eq!(status["phase"], "finished", "{status}");
    assert_eq!(call(id, "start", start.clone()), status);
    assert_eq!(call(id, "stop", identity(&start))["settled"], true);
    release(id, &start);
    assert_eq!(
        call(id, "status", identity(&start))["error"]["code"],
        "unknown_capture"
    );
}

#[test]
fn identity_conflicts_and_late_stop_cannot_affect_a_new_capture() {
    let dir = tempfile::tempdir().unwrap();
    let engine = Engine::new();
    let first = start_payload("33333333333333333333333333333333", dir.path());
    call(engine.0, "start", first.clone());
    wait_for(engine.0, &first, |s| s["phase"] == "capturing");
    let mut conflict = first.clone();
    conflict["metadata"]["title"] = json!("different");
    assert_eq!(
        call(engine.0, "start", conflict)["error"]["code"],
        "identity_conflict"
    );
    assert_eq!(
        call(engine.0 + 100_000, "stop", identity(&first))["error"]["code"],
        "identity_conflict"
    );
    let second = start_payload("44444444444444444444444444444444", dir.path());
    assert_eq!(
        call(engine.0, "start", second.clone())["error"]["code"],
        "session_recording_active"
    );
    call(engine.0, "stop", identity(&first));
    wait_for(engine.0, &first, |s| s["settled"] == true);
    assert_eq!(call(engine.0, "start", second.clone())["ok"], true);
    wait_for(engine.0, &second, |s| s["phase"] == "capturing");
    call(engine.0, "stop", identity(&first));
    assert_eq!(
        call(engine.0, "status", identity(&second))["phase"],
        "capturing"
    );
    call(engine.0, "stop", identity(&second));
    wait_for(engine.0, &second, |s| s["settled"] == true);
    release(engine.0, &first);
    release(engine.0, &second);
}

#[test]
fn failed_create_is_settled_without_replacing_or_deleting_existing_files() {
    let dir = tempfile::tempdir().unwrap();
    let engine = Engine::new();
    let start = start_payload("55555555555555555555555555555555", dir.path());
    let path = Path::new(start["bundle_path"].as_str().unwrap());
    std::fs::create_dir(path).unwrap();
    std::fs::write(path.join("legacy.ndjson"), b"preserve existing data").unwrap();
    call(engine.0, "start", start.clone());
    let status = wait_for(engine.0, &start, |s| s["settled"] == true);
    assert_eq!(status["phase"], "failed");
    assert!(status["error"].is_string());
    release(engine.0, &start);
    assert_eq!(
        std::fs::read(path.join("legacy.ndjson")).unwrap(),
        b"preserve existing data"
    );
    assert!(!path.join("records.bin").exists());
}

#[test]
fn malformed_requests_never_claim_a_path_or_accept_unknown_fields() {
    let dir = tempfile::tempdir().unwrap();
    let engine = Engine::new();
    let valid = start_payload("66666666666666666666666666666666", dir.path());
    let mutations = [
        ("schema_version", json!(1)),
        ("capture_id", json!("BAD")),
        ("bundle_path", json!("relative.trailrec")),
        ("extra", json!(true)),
        ("metadata", json!({})),
    ];
    for (key, value) in mutations {
        let mut invalid = valid.clone();
        invalid[key] = value;
        assert_eq!(
            call(engine.0, "start", invalid)["error"]["code"],
            "invalid_request"
        );
    }
    assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 0);
    assert_eq!(
        call(engine.0, "status", identity(&valid))["error"]["code"],
        "unknown_capture"
    );
}

#[test]
fn closing_while_start_is_pending_always_reaches_detached_settlement() {
    let dir = tempfile::tempdir().unwrap();
    for attempt in 0..5 {
        let engine = Engine::new();
        let id = engine.0;
        let start = start_payload(&format!("{:032x}", 100 + attempt), dir.path());
        assert_eq!(call(id, "start", start.clone())["ok"], true);
        drop(engine);
        let status = wait_for(id, &start, |s| s["settled"] == true);
        assert!(
            matches!(status["phase"].as_str(), Some("finished" | "failed")),
            "{status}"
        );
        let path = Path::new(start["bundle_path"].as_str().unwrap());
        if path.exists() {
            let report = ContainerReader::open(path)
                .unwrap()
                .scan(|| false, |_| Ok(()))
                .unwrap();
            assert_eq!(
                report.summary,
                serde_json::from_value(status["committed"].clone()).unwrap()
            );
        }
        release(id, &start);
    }
}
