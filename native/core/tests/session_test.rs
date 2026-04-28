use flutterm_core::model::{
    TerminalEmulation, TerminalProfile, TerminalProfileAppearance, TerminalProfileInteraction,
    TerminalProfileLaunch, TerminalProfileTerminal,
};
use flutterm_core::session;
use std::collections::BTreeMap;
use std::ffi::CStr;
use std::thread;
use std::time::Duration;

fn local_profile(
    id: &str,
    name: &str,
    shell: &str,
    args: Vec<String>,
    env: BTreeMap<String, String>,
    emulation: TerminalEmulation,
) -> TerminalProfile {
    local_profile_with_scrollback(id, name, shell, args, env, emulation, 8_000)
}

fn local_profile_with_scrollback(
    id: &str,
    name: &str,
    shell: &str,
    args: Vec<String>,
    env: BTreeMap<String, String>,
    emulation: TerminalEmulation,
    scrollback_lines: usize,
) -> TerminalProfile {
    TerminalProfile {
        id: id.to_string(),
        name: name.to_string(),
        launch: TerminalProfileLaunch {
            program: shell.to_string(),
            args,
            env,
            cwd: None,
        },
        terminal: TerminalProfileTerminal {
            emulation,
            scrollback_lines,
        },
        appearance: TerminalProfileAppearance::default(),
        interaction: TerminalProfileInteraction::default(),
    }
}

fn test_profile() -> TerminalProfile {
    local_profile(
        "test",
        "Test",
        "/bin/sh",
        vec!["-lc".to_string(), "printf 'hello\\n'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn interactive_profile() -> TerminalProfile {
    local_profile(
        "interactive",
        "Interactive",
        "/bin/sh",
        vec![],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn bash_readline_profile() -> TerminalProfile {
    let mut env = BTreeMap::new();
    env.insert("PS1".to_string(), "PROMPT-XYZ> ".to_string());
    env.insert("INPUTRC".to_string(), "/dev/null".to_string());
    local_profile(
        "bash-readline",
        "Bash Readline",
        "/bin/bash",
        vec![
            "--noprofile".to_string(),
            "--norc".to_string(),
            "-i".to_string(),
        ],
        env,
        TerminalEmulation::Xterm256,
    )
}

fn prompt_like_profile() -> TerminalProfile {
    local_profile(
        "prompt-like",
        "Prompt-Like",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r"printf '\x1b[38;5;196m\x1b[48;5;46mabc   \x1b[0m\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn style_only_change_profile() -> TerminalProfile {
    local_profile(
        "style-only-change",
        "Style Only Change",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.write("\x1b[31msame\x1b[0m"); sys.stdout.flush(); time.sleep(0.35); sys.stdout.write("\r\x1b[32msame\x1b[0m\n"); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn streaming_scrollback_profile() -> TerminalProfile {
    local_profile(
        "streaming-scrollback",
        "Streaming Scrollback",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "i=0; while [ \"$i\" -lt 14 ]; do printf 'line%02d\\n' \"$i\"; i=$((i + 1)); if [ \"$i\" -eq 7 ]; then sleep 0.35; fi; done"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn single_line_scroll_shift_profile() -> TerminalProfile {
    local_profile(
        "single-line-scroll-shift",
        "Single Line Scroll Shift",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "i=0; while [ \"$i\" -lt 6 ]; do printf 'line%02d\\n' \"$i\"; i=$((i + 1)); if [ \"$i\" -eq 5 ]; then sleep 0.35; fi; done"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn clear_screen_profile() -> TerminalProfile {
    local_profile(
        "clear-screen",
        "Clear Screen",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.write("before\n"); sys.stdout.flush(); time.sleep(0.35); sys.stdout.write("\x1b[2J\x1b[Hafter\n"); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn large_transcript_profile() -> TerminalProfile {
    local_profile_with_scrollback(
        "large-transcript",
        "Large Transcript",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys\nfor i in range(9000):\n    sys.stdout.write(f'line-{i:05d} abcdefghijklmnopqrstuvwxyz\\n')\nsys.stdout.flush()\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        8_000,
    )
}

fn scrollback_profile() -> TerminalProfile {
    local_profile(
        "scrollback",
        "Scrollback",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "i=0; while [ \"$i\" -lt 80 ]; do printf 'line%02d\\n' \"$i\"; i=$((i + 1)); done"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn limited_scrollback_profile() -> TerminalProfile {
    local_profile_with_scrollback(
        "scrollback-limited",
        "Scrollback Limited",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "i=0; while [ \"$i\" -lt 40 ]; do printf 'line%02d\\n' \"$i\"; i=$((i + 1)); done"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        4,
    )
}

fn wrapped_selection_profile() -> TerminalProfile {
    local_profile(
        "wrapped-selection",
        "Wrapped Selection",
        "/bin/sh",
        vec!["-lc".to_string(), "printf 'abcdefghij\\nkl\\n'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn title_profile() -> TerminalProfile {
    local_profile(
        "title",
        "Title",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]2;构建目标\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn icon_name_profile() -> TerminalProfile {
    local_profile(
        "icon-name",
        "Icon Name",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]1;图标名称\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn resize_request_profile() -> TerminalProfile {
    local_profile(
        "resize-request",
        "Resize Request",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033[8;30;100t'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn clipboard_copy_profile() -> TerminalProfile {
    local_profile(
        "clipboard-copy",
        "Clipboard Copy",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]52;c;5aSN5Yi25YaF5a658J+Mnw==\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn clipboard_paste_request_profile() -> TerminalProfile {
    local_profile(
        "clipboard-paste",
        "Clipboard Paste",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033]52;c;?\\a'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn hyperlink_profile() -> TerminalProfile {
    local_profile(
        "hyperlink",
        "Hyperlink",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]8;;https://example.com/docs\\aDocs\\033]8;;\\a\\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn vt220_hyperlink_profile() -> TerminalProfile {
    local_profile(
        "vt220-hyperlink",
        "VT220 Hyperlink",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]8;;https://example.com/docs\\aDocs\\033]8;;\\a\\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn mode_switch_profile() -> TerminalProfile {
    local_profile(
        "mode-switch",
        "Mode Switch",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033[?1h\\033='".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn vt220_da_profile() -> TerminalProfile {
    local_profile(
        "vt220-da",
        "VT220 DA",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,sys; os.write(1,b"\x1b[c"); sys.stdout.flush(); data=os.read(0,128); os.write(1,repr(data).encode()+b"\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn pixel_size_query_profile() -> TerminalProfile {
    local_profile(
        "pixel-size-query",
        "Pixel Size Query",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,sys,termios,tty,time; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b[14t"); sys.stdout.flush(); data=os.read(0,128); termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"PIXEL-RESPONSE:"+repr(data).encode()+b"\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn vt220_title_profile() -> TerminalProfile {
    local_profile(
        "vt220-title",
        "VT220 Title",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]2;构建目标\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn vt220_icon_name_profile() -> TerminalProfile {
    local_profile(
        "vt220-icon-name",
        "VT220 Icon Name",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]1;图标名称\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn vt220_clipboard_copy_profile() -> TerminalProfile {
    local_profile(
        "vt220-clipboard-copy",
        "VT220 Clipboard Copy",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]52;c;5aSN5Yi25YaF5a658J+Mnw==\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn vt220_clipboard_paste_request_profile() -> TerminalProfile {
    local_profile(
        "vt220-clipboard-paste",
        "VT220 Clipboard Paste",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033]52;c;?\\a'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn wait_for_frame_containing(session_id: u64, needle: &str) -> String {
    for _ in 0..20 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            if frame.contains(needle) {
                return frame;
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for frame containing {needle}");
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

fn frame_row_with_text<'a>(frame: &'a serde_json::Value, needle: &str) -> &'a serde_json::Value {
    frame["rows"]
        .as_array()
        .and_then(|rows| {
            rows.iter()
                .find(|row| row["text"].as_str().unwrap_or_default().contains(needle))
        })
        .expect("expected matching frame row")
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
fn session_uses_profile_scrollback_limit_for_spawn_and_resize_rebuild() {
    let session_id =
        session::create_session(&serde_json::to_string(&limited_scrollback_profile()).unwrap())
            .unwrap();

    thread::sleep(Duration::from_millis(250));
    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected initial limited scrollback frame");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["scrollback_max_offset"].as_u64(), Some(4));

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let top_frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected top-of-scrollback frame");
    assert!(!top_frame.contains("line00"));

    session::resize_session(session_id, 120, 20, 0, 0).unwrap();
    let resized_frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected resized limited scrollback frame");
    let resized_parsed: serde_json::Value = serde_json::from_str(&resized_frame).unwrap();
    assert_eq!(resized_parsed["scrollback_max_offset"].as_u64(), Some(4));

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
fn session_output_does_not_emit_activity_events() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::take_frame_diff(session_id).unwrap();
    let _ = session::poll_events(session_id).unwrap();

    session::write_session(session_id, b"printf 'quiet-output\\n'\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "quiet-output");

    let events = session::poll_events(session_id).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
    let activity = parsed
        .as_array()
        .expect("expected events array")
        .iter()
        .find(|entry| entry["kind"] == "activity");

    assert!(
        activity.is_none(),
        "output should not enqueue activity events: {}",
        serde_json::to_string_pretty(&parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn ffi_poll_events_returns_null_when_queue_is_empty() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();

    let first_ptr = flutterm_core::ffi::flutterm_session_poll_events_json(session_id);
    assert!(
        !first_ptr.is_null(),
        "expected initial started event payload"
    );
    let first_payload = unsafe { CStr::from_ptr(first_ptr) }
        .to_str()
        .expect("expected utf8 event payload")
        .to_string();
    assert!(
        first_payload.contains("\"kind\":\"started\""),
        "expected started event payload: {first_payload}"
    );
    unsafe { flutterm_core::ffi::flutterm_string_free(first_ptr) };

    let second_ptr = flutterm_core::ffi::flutterm_session_poll_events_json(session_id);
    assert!(
        second_ptr.is_null(),
        "expected empty event queue to short-circuit without JSON allocation"
    );

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
        frame.contains("\"frame_kind\":\"snapshot\"")
            && frame.contains("PROMPT-XYZ>")
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
fn first_frame_uses_snapshot_kind_and_incremental_output_uses_delta_kind() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let initial = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected initial frame");
    let initial_parsed: serde_json::Value = serde_json::from_str(&initial).unwrap();
    assert_eq!(initial_parsed["frame_kind"].as_str(), Some("snapshot"));

    session::write_session(session_id, b"printf 'delta-one\\n'\n").unwrap();

    let updated = wait_for_frame_containing(session_id, "delta-one");
    let updated_parsed: serde_json::Value = serde_json::from_str(&updated).unwrap();
    assert_eq!(updated_parsed["frame_kind"].as_str(), Some("delta"));
    assert!(
        updated_parsed["rows"]
            .as_array()
            .expect("expected frame rows")
            .len()
            < updated_parsed["viewport_rows"]
                .as_u64()
                .expect("expected viewport row count") as usize,
        "delta frame should only send changed rows: {}",
        serde_json::to_string_pretty(&updated_parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn style_only_output_changes_still_mark_the_row_dirty() {
    let session_id =
        session::create_session(&serde_json::to_string(&style_only_change_profile()).unwrap())
            .unwrap();

    let first = wait_for_frame_containing(session_id, "same");
    let second = wait_for_frame_containing(session_id, "same");

    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let second_parsed: serde_json::Value = serde_json::from_str(&second).unwrap();
    let first_row = frame_row_with_text(&first_parsed, "same");
    let second_row = frame_row_with_text(&second_parsed, "same");
    let first_foreground = first_row["style_runs"]
        .as_array()
        .and_then(|runs| runs.first())
        .and_then(|run| run["foreground"].as_str())
        .expect("expected first foreground");
    let second_foreground = second_row["style_runs"]
        .as_array()
        .and_then(|runs| runs.first())
        .and_then(|run| run["foreground"].as_str())
        .expect("expected second foreground");

    assert_ne!(first_foreground, second_foreground);
    assert_eq!(second_parsed["frame_kind"].as_str(), Some("delta"));
    assert_eq!(
        second_parsed["dirty_ranges"]
            .as_array()
            .expect("expected dirty ranges")
            .first()
            .and_then(|range| range["start"].as_u64()),
        Some(
            second_row["index"]
                .as_u64()
                .expect("expected dirty row index")
        ),
        "style-only changes should still flag the row dirty: {}",
        serde_json::to_string_pretty(&second_parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn scrolling_output_keeps_using_delta_frames_after_viewport_advances() {
    let session_id =
        session::create_session(&serde_json::to_string(&streaming_scrollback_profile()).unwrap())
            .unwrap();
    session::resize_session(session_id, 40, 5, 0, 0).unwrap();

    let _ = wait_for_frame_containing(session_id, "line06");

    let second = wait_for_frame_containing(session_id, "line13");
    let second_parsed: serde_json::Value = serde_json::from_str(&second).unwrap();
    assert_eq!(
        second_parsed["frame_kind"].as_str(),
        Some("delta"),
        "streaming output should stay on the delta path even after the visible window advances: {}",
        serde_json::to_string_pretty(&second_parsed).unwrap()
    );
    assert!(
        second_parsed["viewport_row_shift"]
            .as_i64()
            .expect("expected viewport row shift")
            < 0,
        "streaming delta frame should report that the viewport moved upward: {}",
        serde_json::to_string_pretty(&second_parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn single_line_scroll_reports_viewport_row_shift_and_bottom_dirty_range() {
    let session_id = session::create_session(
        &serde_json::to_string(&single_line_scroll_shift_profile()).unwrap(),
    )
    .unwrap();
    session::resize_session(session_id, 40, 5, 0, 0).unwrap();

    let _ = wait_for_frame_containing(session_id, "line04");

    let shifted = wait_for_frame_containing(session_id, "line05");
    let shifted_parsed: serde_json::Value = serde_json::from_str(&shifted).unwrap();

    assert_eq!(shifted_parsed["frame_kind"].as_str(), Some("delta"));
    assert_eq!(shifted_parsed["viewport_row_shift"].as_i64(), Some(-1));
    assert_eq!(
        shifted_parsed["dirty_ranges"].as_array(),
        Some(&vec![serde_json::json!({
            "start": 3,
            "end": 5,
        })]),
        "single-line viewport scroll should only dirty the newly revealed line plus the trailing cursor row: {}",
        serde_json::to_string_pretty(&shifted_parsed).unwrap()
    );
    assert_eq!(
        shifted_parsed["rows"]
            .as_array()
            .expect("expected delta rows")
            .len(),
        2,
        "single-line viewport scroll should only emit the newly revealed line plus the trailing cursor row: {}",
        serde_json::to_string_pretty(&shifted_parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn damage_driven_delta_reports_low_rows_scanned_for_single_line_scroll() {
    let session_id = session::create_session(
        &serde_json::to_string(&single_line_scroll_shift_profile()).unwrap(),
    )
    .unwrap();
    session::resize_session(session_id, 40, 5, 0, 0).unwrap();

    let _ = wait_for_frame_containing(session_id, "line04");
    let _ = wait_for_frame_containing(session_id, "line05");
    let debug_stats = session::take_frame_debug_stats_json(session_id)
        .unwrap()
        .expect("expected frame debug stats");
    let parsed: serde_json::Value = serde_json::from_str(&debug_stats).unwrap();

    assert_eq!(parsed["viewport_row_shift"].as_i64(), Some(-1));
    assert_eq!(parsed["rows_emitted"].as_u64(), Some(2));
    assert!(parsed["state_lock_wait_micros"].as_u64().is_some());
    assert!(parsed["frame_extract_micros"].as_u64().is_some());
    assert!(parsed["json_encode_micros"].as_u64().is_some());
    assert!(
        parsed["rows_scanned"]
            .as_u64()
            .expect("expected rows_scanned")
            <= 4,
        "single-line scroll should not rescan the full viewport: {}",
        serde_json::to_string_pretty(&parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn clear_screen_falls_back_to_snapshot_with_reason() {
    let session_id =
        session::create_session(&serde_json::to_string(&clear_screen_profile()).unwrap()).unwrap();
    session::resize_session(session_id, 40, 5, 0, 0).unwrap();

    let _ = wait_for_frame_containing(session_id, "before");
    let frame = wait_for_frame_containing(session_id, "after");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let debug_stats = session::take_frame_debug_stats_json(session_id)
        .unwrap()
        .expect("expected frame debug stats");
    let debug_parsed: serde_json::Value = serde_json::from_str(&debug_stats).unwrap();

    assert_eq!(parsed["frame_kind"].as_str(), Some("snapshot"));
    assert_eq!(debug_parsed["full_repaint"].as_bool(), Some(true));
    assert_eq!(
        debug_parsed["snapshot_fallback_reason"].as_str(),
        Some("clear_screen")
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_debug_stats_accumulate_input_processing_costs() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_containing(session_id, "hello");

    let stats = session::take_session_debug_stats_json(session_id)
        .unwrap()
        .expect("expected session debug stats");
    let parsed: serde_json::Value = serde_json::from_str(&stats).unwrap();

    assert!(parsed["bytes_read"].as_u64().unwrap_or_default() > 0);
    assert!(parsed["read_chunks"].as_u64().unwrap_or_default() > 0);
    assert!(parsed["terminal_process_micros"].as_u64().is_some());
    assert!(parsed["host_protocol_micros"].as_u64().is_some());
    assert!(parsed["damage_merge_micros"].as_u64().is_some());
    assert!(parsed["pending_dirty_rows"].as_u64().is_some());
    let breakdown = &parsed["terminal_process_breakdown"];
    assert!(
        breakdown.is_object(),
        "missing terminal_process_breakdown: {parsed}"
    );
    assert!(breakdown["process_calls"].as_u64().unwrap_or_default() > 0);
    assert!(breakdown["process_bytes"].as_u64().unwrap_or_default() > 0);
    assert!(breakdown["plain_ascii_bytes"].as_u64().unwrap_or_default() > 0);
    assert!(breakdown["escape_or_control_bytes"].as_u64().is_some());
    assert!(breakdown["parser_advance_micros"].as_u64().is_some());
    assert!(breakdown["scroll_micros"].as_u64().is_some());

    session::close_session(session_id).unwrap();
}

#[test]
fn transcript_is_bounded_and_resize_still_returns_snapshot() {
    let session_id =
        session::create_session(&serde_json::to_string(&large_transcript_profile()).unwrap())
            .unwrap();
    let _ = wait_for_frame_containing(session_id, "line-08999");

    let stats = session::take_session_debug_stats_json(session_id)
        .unwrap()
        .expect("expected session debug stats");
    let parsed: serde_json::Value = serde_json::from_str(&stats).unwrap();
    assert_eq!(parsed["transcript_truncated"].as_bool(), Some(true));
    assert!(parsed["transcript_bytes"].as_u64().unwrap_or_default() <= 262_144);

    session::resize_session(session_id, 100, 20, 1000, 400).unwrap();
    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame after resize");
    let parsed_frame: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed_frame["frame_kind"].as_str(), Some("snapshot"));

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
