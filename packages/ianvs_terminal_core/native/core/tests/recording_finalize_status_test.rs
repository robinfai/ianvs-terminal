use ianvs_core::model::{
    TerminalEmulation, TerminalProfile, TerminalProfileAppearance, TerminalProfileConnection,
    TerminalProfileInteraction, TerminalProfileLaunch, TerminalProfileTerminal,
    TerminalShellIntegration,
};
use ianvs_core::{session, session_request};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::fs;
use std::thread;
use std::time::Duration;

fn replay_profile() -> TerminalProfile {
    TerminalProfile {
        id: "recording-finalize-status".to_string(),
        name: "Recording finalize status".to_string(),
        connection: TerminalProfileConnection::default(),
        launch: TerminalProfileLaunch {
            program: "/bin/sh".to_string(),
            args: Vec::new(),
            env: BTreeMap::new(),
            cwd: None,
        },
        terminal: TerminalProfileTerminal {
            emulation: TerminalEmulation::Xterm256,
            ..TerminalProfileTerminal::default()
        },
        shell_integration: TerminalShellIntegration::default(),
        appearance: TerminalProfileAppearance::default(),
        interaction: TerminalProfileInteraction::default(),
    }
}

fn private_tempdir() -> tempfile::TempDir {
    let directory = tempfile::tempdir().unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(directory.path(), fs::Permissions::from_mode(0o700)).unwrap();
    }
    directory
}

fn request_v1(session_id: u64, request_id: &str, operation: &str, payload: Value) -> Value {
    let raw = json!({
        "schema_version": session_request::SESSION_REQUEST_SCHEMA_VERSION,
        "contract": session_request::SESSION_REQUEST_CONTRACT,
        "request_id": request_id,
        "session_id": session_id.to_string(),
        "operation": operation,
        "payload": payload,
    })
    .to_string();
    serde_json::from_str(&session_request::request_session_v1_json(session_id, &raw).unwrap())
        .unwrap()
}

#[test]
fn finalize_status_remains_queryable_after_session_close_and_terminal_state_can_be_consumed() {
    let profile = serde_json::to_string(&replay_profile()).unwrap();
    let session_id = session::create_replay_session(&profile).unwrap();
    let directory = private_tempdir();
    let job_id = "33333333333333333333333333333333";

    let start = request_v1(
        session_id,
        "recording-status-start",
        "terminal.recording_start",
        json!({
            "schema_version": 1,
            "created_at_utc": "2026-07-21T00:00:00.000Z",
            "input_policy": "redact",
        }),
    );
    assert_eq!(start["ok"], true);
    assert_eq!(start["payload"]["ok"], true);
    session::replay_session_output(session_id, b"recorded before close\r\n").unwrap();

    let prepare = request_v1(
        session_id,
        "recording-status-prepare",
        "terminal.recording_stop_prepare",
        json!({
            "handoff_directory": directory.path().to_string_lossy(),
            "job_id": job_id,
        }),
    );
    assert_eq!(prepare["ok"], true);
    assert_eq!(prepare["payload"]["ok"], true);
    assert_eq!(prepare["payload"]["job_id"], job_id);

    session::close_session(session_id).unwrap();
    assert!(session::refresh_hint_flags(session_id).is_err());

    let mut terminal = Value::Null;
    for attempt in 0..200 {
        let response = request_v1(
            session_id,
            &format!("recording-status-poll-{attempt}"),
            "terminal.recording_finalize_status",
            json!({"job_id": job_id, "consume_terminal": false}),
        );
        assert_eq!(response["ok"], true);
        terminal = response["payload"].clone();
        if terminal["state"] == "ready" {
            break;
        }
        assert_eq!(terminal["state"], "running");
        thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(terminal["ok"], true);
    assert_eq!(terminal["state"], "ready");

    let consumed = request_v1(
        session_id,
        "recording-status-consume",
        "terminal.recording_finalize_status",
        json!({"job_id": job_id, "consume_terminal": true}),
    );
    assert_eq!(consumed["ok"], true);
    assert_eq!(consumed["payload"]["state"], "ready");

    let unknown = request_v1(
        session_id,
        "recording-status-unknown",
        "terminal.recording_finalize_status",
        json!({"job_id": job_id, "consume_terminal": false}),
    );
    assert_eq!(unknown["ok"], true);
    assert_eq!(unknown["payload"]["state"], "unknown");
}

#[test]
fn finalize_status_rejects_non_lowercase_job_ids_and_non_boolean_consume_flags() {
    let invalid_job = request_v1(
        9_999_991,
        "recording-status-invalid-job",
        "terminal.recording_finalize_status",
        json!({
            "job_id": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "consume_terminal": false,
        }),
    );
    assert_eq!(invalid_job["ok"], true);
    assert_eq!(invalid_job["payload"]["ok"], false);
    assert_eq!(invalid_job["payload"]["error"]["code"], "invalid_request");

    let invalid_consume = request_v1(
        9_999_991,
        "recording-status-invalid-consume",
        "terminal.recording_finalize_status",
        json!({
            "job_id": "44444444444444444444444444444444",
            "consume_terminal": "yes",
        }),
    );
    assert_eq!(invalid_consume["ok"], true);
    assert_eq!(invalid_consume["payload"]["ok"], false);
    assert_eq!(
        invalid_consume["payload"]["error"]["code"],
        "invalid_request"
    );
}
