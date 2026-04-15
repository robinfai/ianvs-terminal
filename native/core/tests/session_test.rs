use flutterm_core::model::TerminalProfile;
use flutterm_core::session;
use std::collections::BTreeMap;
use std::thread;
use std::time::Duration;

fn test_profile() -> TerminalProfile {
    TerminalProfile {
        id: "test".to_string(),
        name: "Test".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec!["-lc".to_string(), "printf 'hello\\n'".to_string()],
        env: BTreeMap::new(),
        cwd: None,
    }
}

#[test]
fn ping_returns_expected_value() {
    assert_eq!(session::ping(), 42);
}

#[test]
fn session_emits_frame_diff_for_simple_command() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");

    assert!(frame.contains("hello"));
    session::close_session(session_id).unwrap();
}

#[test]
fn session_can_resize() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    session::resize_session(session_id, 90, 20, 0, 0).unwrap();
    thread::sleep(Duration::from_millis(100));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");

    assert!(frame.contains("\"viewport_rows\":20"));
    assert!(frame.contains("\"viewport_cols\":90"));
    session::close_session(session_id).unwrap();
}
