use flutterm_core::model::{TerminalEmulation, TerminalProfile};
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
        terminal_emulation: TerminalEmulation::Xterm256,
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
        terminal_emulation: TerminalEmulation::Xterm256,
    }
}

fn prompt_like_profile() -> TerminalProfile {
    TerminalProfile {
        id: "prompt-like".to_string(),
        name: "Prompt-Like".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            r"printf '\x1b[38;5;196m\x1b[48;5;46mabc   \x1b[0m\n'".to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Xterm256,
    }
}

fn scrollback_profile() -> TerminalProfile {
    TerminalProfile {
        id: "scrollback".to_string(),
        name: "Scrollback".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            "i=0; while [ \"$i\" -lt 80 ]; do printf 'line%02d\\n' \"$i\"; i=$((i + 1)); done"
                .to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Xterm256,
    }
}

fn title_profile() -> TerminalProfile {
    TerminalProfile {
        id: "title".to_string(),
        name: "Title".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            "printf '\\033]2;构建目标\\a'".to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Xterm256,
    }
}

fn icon_name_profile() -> TerminalProfile {
    TerminalProfile {
        id: "icon-name".to_string(),
        name: "Icon Name".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            "printf '\\033]1;图标名称\\a'".to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Xterm256,
    }
}

fn resize_request_profile() -> TerminalProfile {
    TerminalProfile {
        id: "resize-request".to_string(),
        name: "Resize Request".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec!["-lc".to_string(), "printf '\\033[8;30;100t'".to_string()],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Xterm256,
    }
}

fn clipboard_copy_profile() -> TerminalProfile {
    TerminalProfile {
        id: "clipboard-copy".to_string(),
        name: "Clipboard Copy".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            "printf '\\033]52;c;5aSN5Yi25YaF5a658J+Mnw==\\a'".to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Xterm256,
    }
}

fn clipboard_paste_request_profile() -> TerminalProfile {
    TerminalProfile {
        id: "clipboard-paste".to_string(),
        name: "Clipboard Paste".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec!["-lc".to_string(), "printf '\\033]52;c;?\\a'".to_string()],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Xterm256,
    }
}

fn mode_switch_profile() -> TerminalProfile {
    TerminalProfile {
        id: "mode-switch".to_string(),
        name: "Mode Switch".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec!["-lc".to_string(), "printf '\\033[?1h\\033='".to_string()],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Xterm256,
    }
}

fn vt220_da_profile() -> TerminalProfile {
    TerminalProfile {
        id: "vt220-da".to_string(),
        name: "VT220 DA".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,sys; os.write(1,b"\x1b[c"); sys.stdout.flush(); data=os.read(0,128); os.write(1,repr(data).encode()+b"\n")'"#
                .to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Vt220,
    }
}

fn wait_for_frame_containing(session_id: u64, needle: &str) -> String {
    wait_for_frame_where(session_id, |frame| frame.contains(needle))
}

fn wait_for_frame_where(session_id: u64, predicate: impl Fn(&str) -> bool) -> String {
    for _ in 0..20 {
        if let Some(frame) = session::take_frame_diff(session_id)
            .unwrap()
            .filter(|frame| predicate(frame))
        {
            return frame;
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for matching frame");
}

fn wait_for_event(session_id: u64, kind: &str) -> serde_json::Value {
    for _ in 0..20 {
        let events = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
        if let Some(event) = parsed
            .as_array()
            .and_then(|entries| entries.iter().find(|entry| entry["kind"] == kind))
        {
            return event.clone();
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for event {kind:?}");
}

fn logical_rows_from_frame(frame: &str) -> Vec<String> {
    let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
    let rows = parsed["rows"].as_array().expect("expected rows");
    let mut logical_rows = Vec::new();
    let mut current = String::new();

    for row in rows {
        current.push_str(row["text"].as_str().unwrap_or_default().trim_end());
        if !row["wrapped"].as_bool().unwrap_or(false) {
            logical_rows.push(std::mem::take(&mut current));
        }
    }

    if !current.is_empty() {
        logical_rows.push(current);
    }

    logical_rows
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
fn session_reports_scrollback_bounds_and_clamps_absolute_scroll() {
    let session_id =
        session::create_session(&serde_json::to_string(&scrollback_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "line79");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let max_offset = parsed["scrollback_max_offset"]
        .as_u64()
        .expect("expected scrollback max offset");
    assert!(max_offset > 0);

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected scrolled frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let offset = parsed["scrollback_offset"]
        .as_u64()
        .expect("expected scrollback offset");
    let max_after_scroll = parsed["scrollback_max_offset"]
        .as_u64()
        .expect("expected scrollback max offset");

    assert_eq!(offset, max_after_scroll);
    session::close_session(session_id).unwrap();
}

#[test]
fn session_reflows_single_long_line_across_resize() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::take_frame_diff(session_id).unwrap();

    session::write_session(session_id, b"printf 'reflow-%0130d\\n' 0\n").unwrap();

    let before = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.starts_with("reflow-") && row.len() == 137)
    });
    assert!(
        logical_rows_from_frame(&before)
            .iter()
            .any(|row| row.starts_with("reflow-") && row.len() == 137)
    );

    session::resize_session(session_id, 40, 24, 0, 0).unwrap();

    let after = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.starts_with("reflow-") && row.len() == 137)
    });
    let after_parsed: serde_json::Value = serde_json::from_str(&after).unwrap();
    assert!(
        after_parsed["rows"]
            .as_array()
            .expect("expected rows")
            .iter()
            .any(|row| row["wrapped"].as_bool() == Some(true))
    );
    assert!(
        logical_rows_from_frame(&after)
            .iter()
            .any(|row| row.starts_with("reflow-") && row.len() == 137)
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_application_cursor_and_keypad_modes() {
    let session_id =
        session::create_session(&serde_json::to_string(&mode_switch_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["application_cursor"].as_bool(), Some(true));
    assert_eq!(parsed["modes"]["application_keypad"].as_bool(), Some(true));

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_reply_with_vt220_primary_device_attributes() {
    let session_id =
        session::create_session(&serde_json::to_string(&vt220_da_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "?62;1;2;6;7;8;9c");
    assert!(!frame.contains("?62;1;4;6;9;15;22;52c"));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_surfaces_window_title_from_osc_sequences() {
    let session_id =
        session::create_session(&serde_json::to_string(&title_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["window_title"].as_str(), Some("构建目标"),);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_surfaces_window_icon_name_from_osc_sequences() {
    let session_id =
        session::create_session(&serde_json::to_string(&icon_name_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["window_icon_name"].as_str(), Some("图标名称"),);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_resize_events_from_terminal_requests() {
    let session_id =
        session::create_session(&serde_json::to_string(&resize_request_profile()).unwrap())
            .unwrap();

    let event = wait_for_event(session_id, "resize");
    assert_eq!(event["payload"]["rows"].as_u64(), Some(30));
    assert_eq!(event["payload"]["cols"].as_u64(), Some(100));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_reflows_scrollback_history_across_resize() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    let marker = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZreflow";
    let first_line = format!("L00-{marker}");
    let last_line = format!("L47-{marker}");
    thread::sleep(Duration::from_millis(250));
    let _ = session::take_frame_diff(session_id);

    let command = format!(
        "i=0; while [ \"$i\" -lt 48 ]; do printf 'L%02d-{marker}\\n' \"$i\"; i=$((i + 1)); done\n"
    );
    session::write_session(session_id, command.as_bytes()).unwrap();

    let bottom_frame = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains(&last_line))
    });
    let bottom_parsed: serde_json::Value = serde_json::from_str(&bottom_frame).unwrap();
    assert!(
        bottom_parsed["scrollback_max_offset"]
            .as_u64()
            .expect("expected scrollback max offset")
            > 0
    );

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let top_before = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains(&first_line))
    });
    assert!(
        logical_rows_from_frame(&top_before)
            .iter()
            .any(|row| row.contains(&first_line))
    );

    session::resize_session(session_id, 40, 24, 0, 0).unwrap();
    let top_after = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains(&first_line))
    });
    let top_after_parsed: serde_json::Value = serde_json::from_str(&top_after).unwrap();
    assert!(
        top_after_parsed["rows"]
            .as_array()
            .expect("expected rows")
            .iter()
            .any(|row| row["wrapped"].as_bool() == Some(true))
    );
    assert!(
        logical_rows_from_frame(&top_after)
            .iter()
            .any(|row| row.contains(&first_line))
    );

    session::scroll_to_session(session_id, 0).unwrap();
    let bottom_after = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains(&last_line))
    });
    assert!(
        logical_rows_from_frame(&bottom_after)
            .iter()
            .any(|row| row.contains(&last_line))
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_clipboard_copy_events_from_osc_52() {
    let session_id =
        session::create_session(&serde_json::to_string(&clipboard_copy_profile()).unwrap())
            .unwrap();

    let event = wait_for_event(session_id, "clipboard_copy");
    assert_eq!(event["payload"]["selection"].as_str(), Some("c"));
    assert_eq!(
        event["payload"]["data"].as_str(),
        Some("5aSN5Yi25YaF5a658J+Mnw=="),
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_clipboard_paste_requests_from_osc_52_queries() {
    let session_id = session::create_session(
        &serde_json::to_string(&clipboard_paste_request_profile()).unwrap(),
    )
    .unwrap();

    let event = wait_for_event(session_id, "clipboard_paste_request");
    assert_eq!(event["payload"]["selection"].as_str(), Some("c"));

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

#[test]
fn session_preserves_trailing_spaces_in_row_text() {
    let session_id =
        session::create_session(&serde_json::to_string(&prompt_like_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let rows = parsed["rows"].as_array().expect("expected rows");
    let text = rows[0]["text"].as_str().expect("expected row text");

    assert!(text.starts_with("abc   "));
    assert!(text.ends_with(' '));
    assert!(text.len() > 6);
    let style_runs = rows[0]["style_runs"]
        .as_array()
        .expect("expected style runs");
    let first_run = &style_runs[0];
    assert_eq!(first_run["background"].as_str(), Some("#00ff00"));
    assert_eq!(first_run["foreground"].as_str(), Some("#ff0000"));

    session::close_session(session_id).unwrap();
}
