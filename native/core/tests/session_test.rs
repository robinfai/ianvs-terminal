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

fn bash_readline_profile() -> TerminalProfile {
    let mut env = BTreeMap::new();
    env.insert("PS1".to_string(), "PROMPT-XYZ> ".to_string());
    env.insert("INPUTRC".to_string(), "/dev/null".to_string());
    TerminalProfile {
        id: "bash-readline".to_string(),
        name: "Bash Readline".to_string(),
        shell: "/bin/bash".to_string(),
        args: vec![
            "--noprofile".to_string(),
            "--norc".to_string(),
            "-i".to_string(),
        ],
        env,
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

fn wrapped_selection_profile() -> TerminalProfile {
    TerminalProfile {
        id: "wrapped-selection".to_string(),
        name: "Wrapped Selection".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec!["-lc".to_string(), "printf 'abcdefghij\\nkl\\n'".to_string()],
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

fn hyperlink_profile() -> TerminalProfile {
    TerminalProfile {
        id: "hyperlink".to_string(),
        name: "Hyperlink".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            "printf '\\033]8;;https://example.com/docs\\aDocs\\033]8;;\\a\\n'".to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Xterm256,
    }
}

fn vt220_hyperlink_profile() -> TerminalProfile {
    TerminalProfile {
        id: "vt220-hyperlink".to_string(),
        name: "VT220 Hyperlink".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            "printf '\\033]8;;https://example.com/docs\\aDocs\\033]8;;\\a\\n'".to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Vt220,
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

fn pixel_size_query_profile() -> TerminalProfile {
    TerminalProfile {
        id: "pixel-size-query".to_string(),
        name: "Pixel Size Query".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,sys,termios,tty,time; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b[14t"); sys.stdout.flush(); data=os.read(0,128); termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"PIXEL-RESPONSE:"+repr(data).encode()+b"\n")'"#
                .to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Xterm256,
    }
}

fn vt220_title_profile() -> TerminalProfile {
    TerminalProfile {
        id: "vt220-title".to_string(),
        name: "VT220 Title".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            "printf '\\033]2;构建目标\\a'".to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Vt220,
    }
}

fn vt220_icon_name_profile() -> TerminalProfile {
    TerminalProfile {
        id: "vt220-icon-name".to_string(),
        name: "VT220 Icon Name".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            "printf '\\033]1;图标名称\\a'".to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Vt220,
    }
}

fn vt220_clipboard_copy_profile() -> TerminalProfile {
    TerminalProfile {
        id: "vt220-clipboard-copy".to_string(),
        name: "VT220 Clipboard Copy".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec![
            "-lc".to_string(),
            "printf '\\033]52;c;5aSN5Yi25YaF5a658J+Mnw==\\a'".to_string(),
        ],
        env: BTreeMap::new(),
        cwd: None,
        terminal_emulation: TerminalEmulation::Vt220,
    }
}

fn vt220_clipboard_paste_request_profile() -> TerminalProfile {
    TerminalProfile {
        id: "vt220-clipboard-paste".to_string(),
        name: "VT220 Clipboard Paste".to_string(),
        shell: "/bin/sh".to_string(),
        args: vec!["-lc".to_string(), "printf '\\033]52;c;?\\a'".to_string()],
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

fn assert_event_kind_never_arrives(session_id: u64, kind: &str) {
    for _ in 0..10 {
        let events = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
        let matching = parsed
            .as_array()
            .expect("expected events array")
            .iter()
            .find(|entry| entry["kind"] == kind);
        assert!(
            matching.is_none(),
            "unexpected event {kind:?}: {}",
            serde_json::to_string_pretty(&parsed).unwrap()
        );
        thread::sleep(Duration::from_millis(50));
    }
}

fn selection_request(
    start_row: usize,
    start_col: usize,
    end_row: usize,
    end_col: usize,
    block: bool,
) -> String {
    serde_json::json!({
        "start_row": start_row,
        "start_col": start_col,
        "end_row": end_row,
        "end_col": end_col,
        "block": block,
    })
    .to_string()
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
fn session_selection_text_reads_linear_ranges_across_scrollback() {
    let session_id =
        session::create_session(&serde_json::to_string(&scrollback_profile()).unwrap()).unwrap();

    let _ = wait_for_frame_containing(session_id, "line79");
    let text =
        session::selection_text_session(session_id, &selection_request(5, 2, 7, 4, false)).unwrap();

    assert_eq!(text, "ne05\nline06\nline");
    session::close_session(session_id).unwrap();
}

#[test]
fn session_selection_text_keeps_wrapped_rows_contiguous() {
    let session_id =
        session::create_session(&serde_json::to_string(&wrapped_selection_profile()).unwrap())
            .unwrap();

    thread::sleep(Duration::from_millis(200));
    session::resize_session(session_id, 5, 4, 50, 80).unwrap();
    let _ = wait_for_frame_containing(session_id, "kl");
    let text =
        session::selection_text_session(session_id, &selection_request(0, 3, 1, 2, false)).unwrap();

    assert_eq!(text, "defg");
    session::close_session(session_id).unwrap();
}

#[test]
fn session_selection_text_clamps_block_ranges_to_available_rows_and_columns() {
    let session_id =
        session::create_session(&serde_json::to_string(&scrollback_profile()).unwrap()).unwrap();

    let _ = wait_for_frame_containing(session_id, "line79");
    let text =
        session::selection_text_session(session_id, &selection_request(78, 4, 120, 20, true))
            .unwrap();

    assert_eq!(text, "78\n79\n");
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
fn session_preserves_latest_visible_output_when_shrinking_height() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::take_frame_diff(session_id).unwrap();

    session::write_session(
        session_id,
        b"i=0; while [ \"$i\" -lt 40 ]; do printf 'keep-%02d\\n' \"$i\"; i=$((i + 1)); done\n",
    )
    .unwrap();

    let before = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains("keep-39"))
    });
    assert!(
        logical_rows_from_frame(&before)
            .iter()
            .any(|row| row.contains("keep-39"))
    );

    session::resize_session(session_id, 120, 16, 0, 0).unwrap();

    let after = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected resized frame diff");
    assert!(
        logical_rows_from_frame(&after)
            .iter()
            .any(|row| row.contains("keep-39")),
        "expected the latest visible output to remain on screen after shrinking height",
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
fn vt220_sessions_do_not_surface_window_title_from_osc_sequences() {
    let session_id =
        session::create_session(&serde_json::to_string(&vt220_title_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["window_title"].as_str(), None);

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
fn vt220_sessions_do_not_surface_window_icon_name_from_osc_sequences() {
    let session_id =
        session::create_session(&serde_json::to_string(&vt220_icon_name_profile()).unwrap())
            .unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["window_icon_name"].as_str(), None);

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
fn session_resize_does_not_insert_blank_rows_before_readline_prompt() {
    let session_id =
        session::create_session(&serde_json::to_string(&bash_readline_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_containing(session_id, "PROMPT-XYZ>");

    session::write_session(
        session_id,
        b"printf 'HEADER-%050d\\nMID-%050d\\nENDMARK\\n' 0 0\n",
    )
    .unwrap();

    let before = wait_for_frame_where(session_id, |frame| {
        let rows = logical_rows_from_frame(frame);
        rows.iter().any(|row| row.contains("ENDMARK"))
            && rows.iter().any(|row| row.contains("PROMPT-XYZ>"))
    });
    let before_rows = logical_rows_from_frame(&before);
    let before_end = before_rows
        .iter()
        .rposition(|row| row.contains("ENDMARK"))
        .expect("expected ENDMARK before resize");
    let before_prompt = before_rows
        .iter()
        .rposition(|row| row.contains("PROMPT-XYZ>"))
        .expect("expected prompt before resize");
    assert_eq!(
        before_prompt,
        before_end + 1,
        "expected prompt to stay adjacent before resize: {before_rows:#?}"
    );

    session::resize_session(session_id, 48, 24, 0, 0).unwrap();
    let _ = wait_for_frame_where(session_id, |frame| frame.contains("PROMPT-XYZ>"));
    session::resize_session(session_id, 92, 24, 0, 0).unwrap();

    let after = wait_for_frame_where(session_id, |frame| {
        let rows = logical_rows_from_frame(frame);
        rows.iter().any(|row| row.contains("ENDMARK"))
            && rows.iter().any(|row| row.contains("PROMPT-XYZ>"))
    });
    let after_rows = logical_rows_from_frame(&after);
    let after_end = after_rows
        .iter()
        .rposition(|row| row.contains("ENDMARK"))
        .expect("expected ENDMARK after resize");
    let after_prompt = after_rows
        .iter()
        .rposition(|row| row.contains("PROMPT-XYZ>"))
        .expect("expected prompt after resize");

    assert_eq!(
        after_prompt,
        after_end + 1,
        "resize inserted blank logical rows before prompt: {after_rows:#?}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_resize_keeps_readline_input_compact() {
    let session_id =
        session::create_session(&serde_json::to_string(&bash_readline_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_containing(session_id, "PROMPT-XYZ>");

    session::write_session(
        session_id,
        b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
    )
    .unwrap();

    let _ = wait_for_frame_where(session_id, |frame| {
        frame.contains("PROMPT-XYZ>")
            && frame.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    });

    session::resize_session(session_id, 40, 24, 0, 0).unwrap();
    let _ = wait_for_frame_where(session_id, |frame| frame.contains("PROMPT-XYZ>"));
    session::resize_session(session_id, 96, 24, 0, 0).unwrap();

    let after = wait_for_frame_where(session_id, |frame| {
        frame.contains("PROMPT-XYZ>")
            && frame.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    });
    let parsed: serde_json::Value = serde_json::from_str(&after).unwrap();
    let rows = parsed["rows"].as_array().expect("expected rows");
    let prompt_row = rows
        .iter()
        .rposition(|row| {
            row["text"]
                .as_str()
                .unwrap_or_default()
                .contains("PROMPT-XYZ>")
        })
        .expect("expected prompt row after resize");
    let cursor_row = parsed["cursor"]["row"]
        .as_u64()
        .expect("expected cursor row") as usize;

    for row in &rows[prompt_row..=cursor_row] {
        let text = row["text"].as_str().unwrap_or_default().trim_end();
        assert!(
            !text.is_empty(),
            "resize inserted blank physical rows inside readline block: {}",
            serde_json::to_string_pretty(&parsed).unwrap()
        );
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_pixel_only_resize_does_not_emit_winch_redraw() {
    let session_id =
        session::create_session(&serde_json::to_string(&bash_readline_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_containing(session_id, "PROMPT-XYZ>");

    session::write_session(session_id, b"trap 'printf \"\\127INCH-MARKER\"' WINCH\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "PROMPT-XYZ>");

    for _ in 0..3 {
        let _ = session::take_frame_diff(session_id).unwrap();
        thread::sleep(Duration::from_millis(20));
    }

    session::resize_session(session_id, 120, 32, 1600, 768).unwrap();
    thread::sleep(Duration::from_millis(200));

    let frame = session::take_frame_diff(session_id).unwrap();
    let frame_text = frame.unwrap_or_default();
    assert!(
        !frame_text.contains("WINCH-MARKER"),
        "pixel-only resize should not signal readline redraw: {frame_text}"
    );

    session::resize_session(session_id, 119, 32, 1600, 768).unwrap();
    let _ = wait_for_frame_containing(session_id, "WINCH-MARKER");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_pixel_only_resize_updates_xtwinops_pixel_size() {
    let session_id =
        session::create_session(&serde_json::to_string(&pixel_size_query_profile()).unwrap())
            .unwrap();

    session::resize_session(session_id, 120, 32, 1600, 768).unwrap();

    let frame = wait_for_frame_containing(session_id, "PIXEL-RESPONSE");
    assert!(
        frame.contains(r"PIXEL-RESPONSE:b'\\x1b[4;768;1600t'"),
        "expected CSI 14 t to report pixel-only resize dimensions: {frame}"
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
fn vt220_sessions_do_not_emit_clipboard_copy_events_from_osc_52() {
    let session_id =
        session::create_session(&serde_json::to_string(&vt220_clipboard_copy_profile()).unwrap())
            .unwrap();

    assert_event_kind_never_arrives(session_id, "clipboard_copy");

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
fn vt220_sessions_do_not_emit_clipboard_paste_requests_from_osc_52_queries() {
    let session_id = session::create_session(
        &serde_json::to_string(&vt220_clipboard_paste_request_profile()).unwrap(),
    )
    .unwrap();

    assert_event_kind_never_arrives(session_id, "clipboard_paste_request");

    session::close_session(session_id).unwrap();
}

#[test]
fn xterm_sessions_surface_osc8_hyperlink_ranges() {
    let session_id =
        session::create_session(&serde_json::to_string(&hyperlink_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "Docs");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let hyperlinks = parsed["hyperlinks"]
        .as_array()
        .expect("expected hyperlink ranges");

    assert_eq!(hyperlinks.len(), 1);
    assert_eq!(hyperlinks[0]["row"].as_u64(), Some(0));
    assert_eq!(hyperlinks[0]["start_col"].as_u64(), Some(0));
    assert_eq!(hyperlinks[0]["end_col"].as_u64(), Some(4));
    assert_eq!(
        hyperlinks[0]["uri"].as_str(),
        Some("https://example.com/docs")
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_do_not_surface_osc8_hyperlink_ranges() {
    let session_id =
        session::create_session(&serde_json::to_string(&vt220_hyperlink_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "Docs");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let hyperlinks = parsed["hyperlinks"]
        .as_array()
        .expect("expected hyperlink ranges");

    assert!(hyperlinks.is_empty());

    session::close_session(session_id).unwrap();
}

#[test]
fn session_searches_scrollback_text_without_changing_scroll_position() {
    let session_id =
        session::create_session(&serde_json::to_string(&scrollback_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "line79");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["scrollback_offset"].as_u64(), Some(0));

    let search = session::search_session(session_id, "line05").unwrap();
    let matches: serde_json::Value = serde_json::from_str(&search).unwrap();
    let first = matches
        .as_array()
        .and_then(|entries| entries.first())
        .expect("expected search match");

    assert_eq!(first["text"].as_str(), Some("line05"));
    assert_eq!(first["start_col"].as_u64(), Some(0));
    assert_eq!(first["end_col"].as_u64(), Some(6));
    assert!(
        first["scrollback_offset"].as_u64().unwrap_or_default() > 0,
        "expected old scrollback match to have a non-zero scrollback offset"
    );

    let frame_after = session::take_frame_diff(session_id).unwrap();
    assert!(
        frame_after.is_none(),
        "search should not dirty or scroll the terminal"
    );

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
