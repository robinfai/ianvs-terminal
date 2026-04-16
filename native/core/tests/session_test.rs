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

fn interactive_profile() -> TerminalProfile {
    TerminalProfile {
        id: "interactive".to_string(),
        name: "Interactive".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![],
        env: BTreeMap::new(),
        cwd: None,
    }
}

fn wait_for_frame_containing(session_id: u64, needle: &str) -> String {
    for _ in 0..20 {
        if let Some(frame) = session::take_frame_diff(session_id)
            .unwrap()
            .filter(|frame| frame.contains(needle))
        {
            return frame;
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for frame containing {needle:?}");
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

#[test]
fn interactive_session_accepts_input_and_emits_output() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();

    thread::sleep(Duration::from_millis(250));
    let _ = session::take_frame_diff(session_id);

    session::write_session(session_id, b"printf 'roundtrip\\n'\n").unwrap();

    let frame = wait_for_frame_containing(session_id, "roundtrip");
    assert!(frame.contains("roundtrip"));

    session::write_session(session_id, b"exit\n").unwrap();
    session::close_session(session_id).unwrap();
}
