use ianvs_core::model::{
    TerminalEmulation, TerminalProfile, TerminalProfileAppearance, TerminalProfileInteraction,
    TerminalProfileLaunch, TerminalProfileTerminal, TerminalShellIntegration,
};
use ianvs_core::session;
use par_term_emu_core_rust::color::{Color, NamedColor};
use par_term_emu_core_rust::terminal::Terminal as ParserTerminal;
use std::collections::BTreeMap;
use std::ffi::CStr;
use std::fs;
use std::path::Path;
use std::thread;
use std::time::Duration;
use tempfile::tempdir;

const SESSION_WAIT_ATTEMPTS: usize = 50;

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
        shell_integration: TerminalShellIntegration::default(),
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

fn sgr_colon_truecolor_profile() -> TerminalProfile {
    local_profile(
        "sgr-colon-truecolor",
        "SGR Colon Truecolor",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r"printf '\x1b[38:2::255:0:0mR\x1b[0m\x1b[48:2::0:0:255mB\x1b[0m\n'".to_string(),
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
            "i=0; while [ \"$i\" -lt 6 ]; do printf 'line%02d\\n' \"$i\"; i=$((i + 1)); done; sleep 1; printf 'line06\\n'; sleep 0.1"
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

fn search_modes_profile() -> TerminalProfile {
    local_profile(
        "search-modes",
        "Search Modes",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf 'Alpha\\nalpha\\nERR 100\\nerr 200\\n'".to_string(),
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

fn top_anchored_partial_scrollback_profile() -> TerminalProfile {
    local_profile(
        "top-anchored-partial-scrollback",
        "Top Anchored Partial Scrollback",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
sys.stdout.write('\x1b[1;13r')
for row in range(1, 14):
    sys.stdout.write(f'\x1b[{row};1Hrow{row:02d}')
sys.stdout.write('\x1b[1;1H\x1b[2S')
sys.stdout.flush()
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
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

fn shell_hook_profile() -> TerminalProfile {
    local_profile(
        "shell-hook",
        "Shell Hook",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1bPhook;7b22686f6f6b223a22707265636d64222c22707764223a222f746d702f69616e7673207465726d696e616c227d\x1b\\")'"#
                .to_string(),
        ],
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

fn apc_unsupported_noop_profile() -> TerminalProfile {
    local_profile(
        "apc-unsupported-noop",
        "APC Unsupported Noop",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf 'before\\033_APC-LEAK\\033\\\\after\\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn non_csi_string_controls_profile() -> TerminalProfile {
    local_profile(
        "non-csi-string-controls",
        "Non-CSI String Controls",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf 'pre\\033^PM-LEAK\\033\\\\mid\\033XSOS-LEAK\\033\\\\post\\n'".to_string(),
        ],
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

fn alternate_screen_profile() -> TerminalProfile {
    local_profile(
        "alternate-screen",
        "Alternate Screen",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033[?1049hALTSCREEN'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn alternate_scroll_profile() -> TerminalProfile {
    local_profile(
        "alternate-scroll",
        "Alternate Scroll",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033[?1049h\\033[?1007hALTSCROLL'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn alternate_wrapped_line_profile() -> TerminalProfile {
    local_profile(
        "alternate-wrapped-line",
        "Alternate Wrapped Line",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time
time.sleep(0.2)
sys.stdout.write('\x1b[?1049hABCDEFGHIJK')
sys.stdout.flush()
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn synchronized_output_profile() -> TerminalProfile {
    local_profile(
        "synchronized-output",
        "Synchronized Output",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; time.sleep(0.2); sys.stdout.write("\x1b[?2026h"); sys.stdout.flush(); time.sleep(0.2); sys.stdout.write("\rSYNC-MID"); sys.stdout.flush(); time.sleep(0.8); sys.stdout.write("\rSYNC-FINAL\x1b[?2026l\n"); sys.stdout.flush()'"#
                .to_string(),
        ],
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

fn osc4_query_profile() -> TerminalProfile {
    local_profile(
        "osc4-query",
        "OSC 4 Query",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,select,sys,termios,time,tty; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b]4;1;rgba:12/34/56/78\x1b\\"); os.write(1,b"\x1b]4;1;?\x1b\\"); sys.stdout.flush(); ready,_,_=select.select([0],[],[],2.0); data=os.read(0,128) if ready else b"TIMEOUT"; termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"OSC4-RESPONSE:"+repr(data).encode()+b"\n")'"#
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

fn vt220_wraparound_repaint_profile() -> TerminalProfile {
    local_profile(
        "vt220-wraparound-repaint",
        "VT220 Wraparound Repaint",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.write("\x1b[2J\x1b[H*****\n***\n*****"); sys.stdout.flush(); time.sleep(0.35); sys.stdout.write("\x1b[H***************"); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn wait_for_frame_containing(session_id: u64, needle: &str) -> String {
    for _ in 0..SESSION_WAIT_ATTEMPTS {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap()
            && frame.contains(needle)
        {
            return frame;
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for frame containing {needle}");
}

fn wait_for_frame_idle(session_id: u64) {
    let mut idle_polls = 0;
    for _ in 0..SESSION_WAIT_ATTEMPTS {
        if session::take_frame_diff(session_id).unwrap().is_some() {
            idle_polls = 0;
        } else {
            idle_polls += 1;
            if idle_polls >= 10 {
                return;
            }
        }
        thread::sleep(Duration::from_millis(50));
    }
    panic!("timed out waiting for frame stream to settle");
}

fn wait_for_frame_where(session_id: u64, predicate: impl Fn(&str) -> bool) -> String {
    for _ in 0..SESSION_WAIT_ATTEMPTS {
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
    for _ in 0..SESSION_WAIT_ATTEMPTS {
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

fn wait_for_shell_hook_sequence(session_id: u64, hooks: &[&str]) -> Vec<serde_json::Value> {
    let mut events = Vec::new();
    for _ in 0..30 {
        let polled = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&polled).unwrap();
        if let Some(entries) = parsed.as_array() {
            for entry in entries {
                if entry["kind"] != "shell_hook" {
                    continue;
                }
                let Some(next_hook) = hooks.get(events.len()) else {
                    return events;
                };
                if entry["payload"]["hook"].as_str() == Some(next_hook) {
                    events.push(entry.clone());
                    if events.len() == hooks.len() {
                        return events;
                    }
                }
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for shell hooks {hooks:?}");
}

fn wait_for_readonly_command_round(
    session_id: u64,
    command: &str,
    begin_marker: &str,
    end_marker: &str,
) -> Vec<String> {
    let mut saw_preexec = false;
    let mut saw_finished = false;
    let mut captured_lines = Vec::new();
    let mut debug_events = Vec::new();
    let mut debug_frames = Vec::new();

    for _ in 0..80 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            let frame_lines = logical_rows_from_frame(&frame);
            captured_lines.extend(frame_lines);
            debug_frames.push(frame);
        }

        let polled = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&polled).unwrap();
        if let Some(entries) = parsed.as_array() {
            for entry in entries {
                debug_events.push(entry.clone());
                if entry["kind"] != "shell_hook" {
                    continue;
                }
                let payload = &entry["payload"];
                if payload["command"].as_str() != Some(command) {
                    continue;
                }
                match payload["hook"].as_str() {
                    Some("preexec") => saw_preexec = true,
                    Some("command_finished") => {
                        saw_finished = true;
                        assert_eq!(
                            payload["exit_code"].as_i64(),
                            Some(0),
                            "readonly command failed: {command}"
                        );
                    }
                    _ => {}
                }
            }
        }

        let joined_output = captured_lines.join("\n");
        if saw_preexec
            && saw_finished
            && joined_output.contains(begin_marker)
            && joined_output.contains(end_marker)
        {
            return captured_lines;
        }
        thread::sleep(Duration::from_millis(50));
    }

    panic!(
        "timed out waiting for readonly command round\ncommand: {command}\nbegin: {begin_marker}\nend: {end_marker}\npreexec: {saw_preexec}\nfinished: {saw_finished}\nlines:\n{}\nevents:\n{}\nframes:\n{}",
        captured_lines.join("\n"),
        serde_json::to_string_pretty(&debug_events).unwrap(),
        debug_frames.join("\n--- frame ---\n")
    );
}

fn find_shell(name: &str) -> Option<String> {
    [
        format!("/bin/{name}"),
        format!("/usr/bin/{name}"),
        format!("/opt/homebrew/bin/{name}"),
        format!("/usr/local/bin/{name}"),
    ]
    .into_iter()
    .find(|path| Path::new(path.as_str()).exists())
}

fn fish_runtime_stays_open(fish_path: &str) -> bool {
    let Ok(home) = tempdir() else {
        return false;
    };
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "fish-runtime-probe",
        "Fish Runtime Probe",
        fish_path,
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.shell_integration.enabled = false;
    let Ok(profile_json) = serde_json::to_string(&profile) else {
        return false;
    };
    let Ok(session_id) = session::create_session(&profile_json) else {
        return false;
    };
    thread::sleep(Duration::from_millis(250));
    let exited = session::poll_events(session_id)
        .ok()
        .and_then(|events| serde_json::from_str::<serde_json::Value>(&events).ok())
        .and_then(|events| {
            events.as_array().map(|entries| {
                entries
                    .iter()
                    .any(|entry| entry["kind"].as_str() == Some("exit"))
            })
        })
        .unwrap_or(true);
    let _ = session::close_session(session_id);
    !exited
}

fn assert_shell_hook_command_lifecycle(session_id: u64, shell: &str) {
    session::write_session(session_id, b"echo ok\n").unwrap();
    let hooks = wait_for_shell_hook_sequence(session_id, &["preexec", "command_finished"]);
    let preexec_event = &hooks[0];
    assert_eq!(preexec_event["payload"]["shell"].as_str(), Some(shell));
    assert_eq!(
        preexec_event["payload"]["command"].as_str(),
        Some("echo ok")
    );
    let finished_event = &hooks[1];
    assert_eq!(finished_event["payload"]["shell"].as_str(), Some(shell));
    assert_eq!(
        finished_event["payload"]["command"].as_str(),
        Some("echo ok")
    );
    assert_eq!(finished_event["payload"]["exit_code"].as_i64(), Some(0));

    session::write_session(session_id, b"false\n").unwrap();
    let hooks = wait_for_shell_hook_sequence(session_id, &["preexec", "command_finished"]);
    let failed_event = &hooks[1];
    assert_eq!(failed_event["payload"]["shell"].as_str(), Some(shell));
    assert_eq!(failed_event["payload"]["command"].as_str(), Some("false"));
    assert_eq!(failed_event["payload"]["exit_code"].as_i64(), Some(1));
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

fn frame_row_at_index(frame: &serde_json::Value, index: u64) -> &serde_json::Value {
    frame["rows"]
        .as_array()
        .and_then(|rows| rows.iter().find(|row| row["index"].as_u64() == Some(index)))
        .expect("expected matching frame row index")
}

#[test]
fn ping_returns_expected_value() {
    assert_eq!(session::ping(), 42);
}

#[test]
fn close_session_reports_missing_session_ids() {
    let error = session::close_session(u64::MAX).unwrap_err();

    assert_eq!(error.to_string(), format!("missing session {}", u64::MAX));
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
fn session_top_anchored_partial_scroll_region_contributes_to_scrollback() {
    let session_id = session::create_session(
        &serde_json::to_string(&top_anchored_partial_scrollback_profile()).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "row03");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert!(parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0);

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let scrolled = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected scrolled frame diff");
    assert!(scrolled.contains("row01"));
    assert!(scrolled.contains("row02"));

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
fn session_frame_diff_exposes_alternate_screen_mode() {
    let session_id =
        session::create_session(&serde_json::to_string(&alternate_screen_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "ALTSCREEN");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["alternate_screen"].as_bool(), Some(true));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_alternate_scroll_mode() {
    let session_id =
        session::create_session(&serde_json::to_string(&alternate_scroll_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "ALTSCROLL");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["alternate_screen"].as_bool(), Some(true));
    assert_eq!(parsed["modes"]["alternate_scroll"].as_bool(), Some(true));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_preserves_wrapped_line_metadata_in_alternate_screen() {
    let session_id =
        session::create_session(&serde_json::to_string(&alternate_wrapped_line_profile()).unwrap())
            .unwrap();
    session::resize_session(session_id, 5, 4, 0, 0).unwrap();

    let frame = wait_for_frame_containing(session_id, "K");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["alternate_screen"].as_bool(), Some(true));
    assert_eq!(
        frame_row_at_index(&parsed, 0)["text"].as_str(),
        Some("ABCDE")
    );
    assert_eq!(
        frame_row_at_index(&parsed, 0)["wrapped"].as_bool(),
        Some(true)
    );
    assert_eq!(
        frame_row_at_index(&parsed, 1)["text"].as_str(),
        Some("FGHIJ")
    );
    assert_eq!(
        frame_row_at_index(&parsed, 1)["wrapped"].as_bool(),
        Some(true)
    );
    assert_eq!(
        frame_row_at_index(&parsed, 2)["text"]
            .as_str()
            .unwrap_or_default()
            .trim_end(),
        "K"
    );
    assert_eq!(
        frame_row_at_index(&parsed, 2)["wrapped"].as_bool(),
        Some(false)
    );
    assert!(
        logical_rows_from_frame(&frame)
            .iter()
            .any(|row| row == "ABCDEFGHIJK"),
        "alternate-screen wrapped rows should reassemble as one logical row: {}",
        serde_json::to_string_pretty(&parsed).unwrap()
    );

    let text =
        session::selection_text_session(session_id, &selection_request(0, 3, 2, 1, false)).unwrap();
    assert_eq!(text, "DEFGHIJK");

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
fn session_emits_shell_hook_events_from_dcs_hooks() {
    let session_id =
        session::create_session(&serde_json::to_string(&shell_hook_profile()).unwrap()).unwrap();

    let event = wait_for_event(session_id, "shell_hook");
    assert_eq!(event["payload"]["hook"].as_str(), Some("precmd"));
    assert_eq!(
        event["payload"]["pwd"].as_str(),
        Some("/tmp/ianvs terminal")
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_shell_hook_integration_emits_lifecycle_hooks_when_enabled() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "PROMPT='ianvs terminal-test% '\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "zsh-shell-integration",
            "Zsh Shell Integration",
            "/bin/zsh",
            vec![],
            env,
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let startup_hooks =
        wait_for_shell_hook_sequence(session_id, &["bootstrapped", "precmd", "precmd.pwd"]);
    assert_eq!(startup_hooks[0]["payload"]["shell"].as_str(), Some("zsh"));
    let pwd_event = &startup_hooks[2];
    let expected_pwd = fs::canonicalize(original_zdotdir.path()).unwrap();
    assert_eq!(
        pwd_event["payload"]["pwd"].as_str(),
        Some(expected_pwd.to_string_lossy().as_ref())
    );

    session::write_session(session_id, b"echo ok\n").unwrap();
    let hooks = wait_for_shell_hook_sequence(session_id, &["preexec", "command_finished"]);
    let preexec_event = &hooks[0];
    assert_eq!(
        preexec_event["payload"]["command"].as_str(),
        Some("echo ok")
    );
    let finished_event = &hooks[1];
    assert_eq!(
        finished_event["payload"]["command"].as_str(),
        Some("echo ok")
    );
    assert_eq!(finished_event["payload"]["exit_code"].as_i64(), Some(0));

    session::write_session(session_id, b"false\n").unwrap();
    let hooks = wait_for_shell_hook_sequence(session_id, &["preexec", "command_finished"]);
    let failed_event = &hooks[1];
    assert_eq!(failed_event["payload"]["command"].as_str(), Some("false"));
    assert_eq!(failed_event["payload"]["exit_code"].as_i64(), Some(1));

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_shell_hook_integration_stably_pairs_readonly_commands_with_real_pty_output() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let home = tempdir().unwrap();
    let cwd = tempdir().unwrap();
    fs::write(
        home.path().join(".zshrc"),
        "PROMPT='ianvs ro-test% '\nalias ll='ls -la'\n",
    )
    .unwrap();
    fs::write(cwd.path().join("alpha.txt"), "alpha-one\nalpha-two\n").unwrap();
    fs::write(cwd.path().join("beta.txt"), "beta-one\n").unwrap();
    fs::write(cwd.path().join("data.txt"), "one\ntwo\nthree\n").unwrap();

    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "zsh-shell-integration-readonly-rounds",
        "Zsh Shell Integration Readonly Rounds",
        "/bin/zsh",
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.launch.cwd = Some(cwd.path().to_string_lossy().into_owned());
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    session::resize_session(session_id, 120, 48, 0, 0).unwrap();

    let startup_hooks =
        wait_for_shell_hook_sequence(session_id, &["bootstrapped", "precmd", "precmd.pwd"]);
    assert_eq!(startup_hooks[0]["payload"]["shell"].as_str(), Some("zsh"));

    let rounds = [
        (
            "printf 'IANVS_RO_01_BEGIN\\n'; pwd; printf 'IANVS_RO_01_END\\n'",
            "IANVS_RO_01_BEGIN",
            "IANVS_RO_01_END",
            cwd.path().to_string_lossy().into_owned(),
        ),
        (
            "printf 'IANVS_RO_02_BEGIN\\n'; ls -1; printf 'IANVS_RO_02_END\\n'",
            "IANVS_RO_02_BEGIN",
            "IANVS_RO_02_END",
            "alpha.txt".to_string(),
        ),
        (
            "printf 'IANVS_RO_03_BEGIN\\n'; cat alpha.txt; printf 'IANVS_RO_03_END\\n'",
            "IANVS_RO_03_BEGIN",
            "IANVS_RO_03_END",
            "alpha-two".to_string(),
        ),
        (
            "printf 'IANVS_RO_04_BEGIN\\n'; wc -l data.txt; printf 'IANVS_RO_04_END\\n'",
            "IANVS_RO_04_BEGIN",
            "IANVS_RO_04_END",
            "data.txt".to_string(),
        ),
        (
            "printf 'IANVS_RO_05_BEGIN\\n'; uname -s >/dev/null; printf 'uname-ok\\n'; printf 'IANVS_RO_05_END\\n'",
            "IANVS_RO_05_BEGIN",
            "IANVS_RO_05_END",
            "uname-ok".to_string(),
        ),
        (
            "printf 'IANVS_RO_06_BEGIN\\n'; ll; printf 'IANVS_RO_06_END\\n'",
            "IANVS_RO_06_BEGIN",
            "IANVS_RO_06_END",
            "alpha.txt".to_string(),
        ),
    ];

    for (command, begin_marker, end_marker, expected_output) in rounds {
        session::write_session(session_id, format!("{command}\n").as_bytes()).unwrap();
        let lines = wait_for_readonly_command_round(session_id, command, begin_marker, end_marker);
        let output = lines.join("\n");
        assert!(
            output.contains(&expected_output),
            "readonly command output was not captured into frame rows\ncommand: {command}\nexpected: {expected_output}\noutput:\n{output}"
        );
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_shell_hook_integration_preserves_prompt_substitution_from_zshrc() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "setopt prompt_subst\nPROMPT='$(print ianvs terminal-subst)% '\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "zsh-shell-integration-prompt-subst",
            "Zsh Shell Integration Prompt Substitution",
            "/bin/zsh",
            vec![],
            env,
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "ianvs terminal-subst");
    assert!(
        !frame.contains("$(print ianvs terminal-subst)"),
        "prompt substitution should be evaluated, not displayed literally: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_shell_hook_integration_sources_zshrc_with_original_zdotdir() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        r#"if [[ "${ZDOTDIR:-}" == "${HOME:-}" ]]; then
  PROMPT='ianvs terminal-zdot-ok% '
else
  PROMPT='ianvs terminal-zdot-bad% '
fi
"#,
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "zsh-shell-integration-original-zdotdir",
            "Zsh Shell Integration Original ZDOTDIR",
            "/bin/zsh",
            vec![],
            env,
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "ianvs terminal-zdot-ok");
    assert!(
        !frame.contains("ianvs terminal-zdot-bad"),
        "original .zshrc should see the user's ZDOTDIR, not the ianvs terminal proxy: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_shell_hook_integration_preserves_postdisplay_redraws() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "PROMPT='ianvs terminal-postdisplay% '\n\
         __ianvs_test_self_insert() {\n\
           zle .self-insert\n\
           POSTDISPLAY=' ghost-suggestion'\n\
           region_highlight+=(\"$#BUFFER $(($#BUFFER + $#POSTDISPLAY)) fg=8\")\n\
           zle -R\n\
         }\n\
         zle -N self-insert __ianvs_test_self_insert\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "zsh-shell-integration-postdisplay",
            "Zsh Shell Integration POSTDISPLAY",
            "/bin/zsh",
            vec![],
            env,
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let _ = wait_for_frame_containing(session_id, "ianvs terminal-postdisplay");
    session::write_session(session_id, b"g").unwrap();
    let frame = wait_for_frame_containing(session_id, "ghost-suggestion");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let row = frame_row_with_text(&parsed, "ghost-suggestion");
    let ghost_style = row["style_runs"]
        .as_array()
        .expect("expected style runs")
        .iter()
        .find(|run| run["foreground"].as_str() == Some("#687378"))
        .expect("expected fg=8 autosuggestion style run");
    assert!(
        frame.contains("ghost-suggestion"),
        "zsh POSTDISPLAY redraws should remain visible with shell integration: {frame}"
    );
    assert!(
        ghost_style["start"].as_u64().unwrap_or_default()
            < ghost_style["end"].as_u64().unwrap_or_default(),
        "autosuggestion style run should cover visible cells: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_initial_prompt_sp_marker_is_cleared_before_multiline_prompt() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "setopt prompt_sp\nPROMPT=$'\\nianvs terminal-prompt> '\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "zsh-prompt-sp-marker",
            "Zsh Prompt SP Marker",
            "/bin/zsh",
            vec![],
            env,
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "ianvs terminal-prompt");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let marker_row = parsed["rows"]
        .as_array()
        .expect("expected rows")
        .iter()
        .find(|row| row["text"].as_str().unwrap_or_default().starts_with('%'));
    assert!(
        marker_row.is_none(),
        "zsh PROMPT_SP marker should be cleared before the prompt frame: {frame}"
    );
    let prompt_row = frame_row_with_text(&parsed, "ianvs terminal-prompt");
    assert_eq!(
        prompt_row["index"].as_u64(),
        Some(0),
        "the startup prompt should not leave a blank first row: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn prompt_sp_clear_sequence_marks_cleared_marker_row_dirty() {
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "prompt-sp-clear-sequence",
            "Prompt SP Clear Sequence",
            "/bin/sh",
            vec![
                "-lc".to_string(),
                "printf '\\033[1m\\033[7m%%\\033[27m\\033[1m\\033[0m                                                                               '; \
                 sleep 0.2; \
                 printf '\\r \\r\\033Phook;68656c6c6f\\033\\\\\\r\\033[0m\\033[27m\\033[24m\\033[J\\r\\nianvs terminal-prompt\\r\\n> '; \
                 sleep 0.2"
                    .to_string(),
            ],
            BTreeMap::new(),
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let _ = wait_for_frame_where(session_id, |frame| {
        let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
        parsed["rows"]
            .as_array()
            .expect("expected rows")
            .iter()
            .any(|row| {
                row["index"].as_u64() == Some(0)
                    && row["text"].as_str().unwrap_or_default().starts_with('%')
            })
    });
    let frame = wait_for_frame_containing(session_id, "ianvs terminal-prompt");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let row_zero = frame_row_at_index(&parsed, 0);
    assert!(
        !row_zero["text"]
            .as_str()
            .unwrap_or_default()
            .starts_with('%'),
        "clearing zsh's PROMPT_SP marker must dirty row 0: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn bash_shell_hook_integration_emits_lifecycle_hooks_when_enabled() {
    let Some(bash_path) = find_shell("bash") else {
        return;
    };

    let home = tempdir().unwrap();
    let cwd = tempdir().unwrap();
    fs::write(home.path().join(".bashrc"), "PS1='ianvs terminal-bash$ '\n").unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "bash-shell-integration",
        "Bash Shell Integration",
        &bash_path,
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.launch.cwd = Some(cwd.path().to_string_lossy().into_owned());
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let startup_hooks =
        wait_for_shell_hook_sequence(session_id, &["bootstrapped", "precmd", "precmd.pwd"]);
    assert_eq!(startup_hooks[0]["payload"]["shell"].as_str(), Some("bash"));
    let pwd_event = &startup_hooks[2];
    let expected_pwd = fs::canonicalize(cwd.path()).unwrap();
    assert_eq!(pwd_event["payload"]["shell"].as_str(), Some("bash"));
    assert_eq!(
        pwd_event["payload"]["pwd"].as_str(),
        Some(expected_pwd.to_string_lossy().as_ref())
    );

    assert_shell_hook_command_lifecycle(session_id, "bash");

    session::close_session(session_id).unwrap();
}

#[test]
fn fish_shell_hook_integration_emits_lifecycle_hooks_when_enabled() {
    let Some(fish_path) = find_shell("fish") else {
        return;
    };
    if !fish_runtime_stays_open(&fish_path) {
        return;
    }

    let home = tempdir().unwrap();
    let cwd = tempdir().unwrap();
    let fish_config_dir = home.path().join(".config/fish");
    fs::create_dir_all(&fish_config_dir).unwrap();
    fs::write(
        fish_config_dir.join("config.fish"),
        "function fish_prompt; printf 'ianvs terminal-fish> '; end\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "fish-shell-integration",
        "Fish Shell Integration",
        &fish_path,
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.launch.cwd = Some(cwd.path().to_string_lossy().into_owned());
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let startup_hooks =
        wait_for_shell_hook_sequence(session_id, &["bootstrapped", "precmd", "precmd.pwd"]);
    assert_eq!(startup_hooks[0]["payload"]["shell"].as_str(), Some("fish"));
    let pwd_event = &startup_hooks[2];
    let expected_pwd = fs::canonicalize(cwd.path()).unwrap();
    assert_eq!(pwd_event["payload"]["shell"].as_str(), Some("fish"));
    assert_eq!(
        pwd_event["payload"]["pwd"].as_str(),
        Some(expected_pwd.to_string_lossy().as_ref())
    );

    assert_shell_hook_command_lifecycle(session_id, "fish");

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_shell_hook_integration_disabled_emits_no_shell_hooks() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "PROMPT='ianvs terminal-disabled% '\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "zsh-shell-integration-disabled",
        "Zsh Shell Integration Disabled",
        "/bin/zsh",
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.shell_integration.enabled = false;
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::poll_events(session_id).unwrap();

    session::write_session(session_id, b"echo still-works\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "still-works");
    assert_event_kind_never_arrives(session_id, "shell_hook");

    session::close_session(session_id).unwrap();
}

#[test]
fn bash_shell_hook_integration_disabled_emits_no_shell_hooks() {
    let Some(bash_path) = find_shell("bash") else {
        return;
    };

    let home = tempdir().unwrap();
    fs::write(
        home.path().join(".bashrc"),
        "PS1='ianvs terminal-disabled$ '\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "bash-shell-integration-disabled",
        "Bash Shell Integration Disabled",
        &bash_path,
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.shell_integration.enabled = false;
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::poll_events(session_id).unwrap();

    session::write_session(session_id, b"echo still-works\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "still-works");
    assert_event_kind_never_arrives(session_id, "shell_hook");

    session::close_session(session_id).unwrap();
}

#[test]
fn fish_shell_hook_integration_disabled_emits_no_shell_hooks() {
    let Some(fish_path) = find_shell("fish") else {
        return;
    };
    if !fish_runtime_stays_open(&fish_path) {
        return;
    }

    let home = tempdir().unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "fish-shell-integration-disabled",
        "Fish Shell Integration Disabled",
        &fish_path,
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.shell_integration.enabled = false;
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::poll_events(session_id).unwrap();

    session::write_session(session_id, b"echo still-works\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "still-works");
    assert_event_kind_never_arrives(session_id, "shell_hook");

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

    let first_ptr = ianvs_core::ffi::ianvs_session_poll_events_json(session_id);
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
    unsafe { ianvs_core::ffi::ianvs_string_free(first_ptr) };

    let second_ptr = ianvs_core::ffi::ianvs_session_poll_events_json(session_id);
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
fn session_synchronized_output_defers_intermediate_frames_until_disable() {
    let session_id =
        session::create_session(&serde_json::to_string(&synchronized_output_profile()).unwrap())
            .unwrap();

    thread::sleep(Duration::from_millis(700));
    let mut final_frame = None;
    for _ in 0..5 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            let visible_text = logical_rows_from_frame(&frame).join("\n");
            assert!(
                !visible_text.contains("SYNC-MID"),
                "synchronized output must not publish the intermediate frame: {frame}"
            );
            if visible_text.contains("SYNC-FINAL") {
                final_frame = Some(frame);
                break;
            }
        }
        thread::sleep(Duration::from_millis(50));
    }

    let frame = final_frame.unwrap_or_else(|| wait_for_frame_containing(session_id, "SYNC-FINAL"));
    let visible_text = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible_text.contains("SYNC-FINAL"),
        "expected synchronized output to flush the final frame: {frame}"
    );
    assert!(
        !visible_text.contains("SYNC-MID"),
        "final synchronized frame should only expose the latest output: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc4_query_reports_rgb_for_alpha_color_specs() {
    let session_id =
        session::create_session(&serde_json::to_string(&osc4_query_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC4-RESPONSE");
    assert!(
        frame.contains(r"OSC4-RESPONSE:b'\\x1b]4;1;rgb:1212/3434/5656\\x1b\\\\'"),
        "expected OSC 4 query to report the RGB portion of an alpha color spec: {frame}"
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
fn session_apc_sequence_is_unsupported_noop() {
    let session_id =
        session::create_session(&serde_json::to_string(&apc_unsupported_noop_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "before");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let rows = logical_rows_from_frame(&frame);
    assert!(
        rows.iter().any(|row| row.contains("beforeafter")),
        "APC should not interrupt surrounding printable text: {rows:?}"
    );
    assert!(
        !frame.contains("APC-LEAK"),
        "APC payload must not render into terminal rows: {frame}"
    );
    assert!(
        parsed["rows"]
            .as_array()
            .expect("expected rows")
            .iter()
            .all(|row| !row["text"]
                .as_str()
                .unwrap_or_default()
                .contains("APC-LEAK"))
    );

    let events = session::poll_events(session_id).unwrap();
    assert!(
        !events.contains("APC-LEAK"),
        "APC payload must not surface through app events: {events}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_pm_and_sos_sequences_are_unsupported_noops() {
    let session_id = session::create_session(
        &serde_json::to_string(&non_csi_string_controls_profile()).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "pre");
    let rows = logical_rows_from_frame(&frame);
    assert!(
        rows.iter().any(|row| row.contains("premidpost")),
        "PM/SOS should not interrupt surrounding printable text: {rows:?}"
    );
    assert!(
        !frame.contains("PM-LEAK") && !frame.contains("SOS-LEAK"),
        "PM/SOS payloads must not render into terminal rows: {frame}"
    );

    let events = session::poll_events(session_id).unwrap();
    assert!(
        !events.contains("PM-LEAK") && !events.contains("SOS-LEAK"),
        "PM/SOS payloads must not surface through app events: {events}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_wraparound_repaint_keeps_full_width_rows_dirty_and_complete() {
    let session_id = session::create_session(
        &serde_json::to_string(&vt220_wraparound_repaint_profile()).unwrap(),
    )
    .unwrap();
    session::resize_session(session_id, 5, 4, 0, 0).unwrap();

    let mut first_phase_history = Vec::new();
    let mut saw_first_phase = false;
    for _ in 0..20 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            first_phase_history.push(frame.clone());
            let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
            saw_first_phase = parsed["rows"].as_array().is_some_and(|rows| {
                rows.iter()
                    .find(|row| row["index"].as_u64() == Some(1))
                    .and_then(|row| row["text"].as_str())
                    == Some("***  ")
            });
            if saw_first_phase {
                break;
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    assert!(
        saw_first_phase,
        "timed out waiting for initial shorter middle row: {}",
        first_phase_history.join("\n---\n")
    );

    let mut second_phase_history = Vec::new();
    let mut second = None;
    for _ in 0..20 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            second_phase_history.push(frame.clone());
            let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
            let has_full_rows = parsed["rows"].as_array().is_some_and(|rows| {
                rows.iter()
                    .find(|row| row["index"].as_u64() == Some(0))
                    .and_then(|row| row["text"].as_str())
                    == Some("*****")
                    && rows
                        .iter()
                        .find(|row| row["index"].as_u64() == Some(1))
                        .and_then(|row| row["text"].as_str())
                        == Some("*****")
                    && rows
                        .iter()
                        .find(|row| row["index"].as_u64() == Some(2))
                        .and_then(|row| row["text"].as_str())
                        == Some("*****")
            });
            if has_full_rows {
                second = Some(frame);
                break;
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    let second = second.unwrap_or_else(|| {
        panic!(
            "timed out waiting for full-width wrap repaint: {}",
            second_phase_history.join("\n---\n")
        )
    });

    let second_parsed: serde_json::Value = serde_json::from_str(&second).unwrap();
    assert_eq!(
        frame_row_at_index(&second_parsed, 0)["text"].as_str(),
        Some("*****")
    );
    assert_eq!(
        frame_row_at_index(&second_parsed, 1)["text"].as_str(),
        Some("*****")
    );
    assert_eq!(
        frame_row_at_index(&second_parsed, 2)["text"].as_str(),
        Some("*****")
    );
    assert!(
        second_parsed["dirty_ranges"]
            .as_array()
            .is_some_and(|ranges| ranges.iter().any(|range| {
                range["start"].as_u64() == Some(0) && range["end"].as_u64().unwrap_or_default() >= 3
            })),
        "wrap-around repaint should cover all three rows in at least one dirty range: {}",
        serde_json::to_string_pretty(&second_parsed).unwrap()
    );

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
fn session_search_empty_query_returns_no_matches() {
    let session_id =
        session::create_session(&serde_json::to_string(&scrollback_profile()).unwrap()).unwrap();

    wait_for_frame_containing(session_id, "line79");

    let search = session::search_session(session_id, "").unwrap();
    let matches: serde_json::Value = serde_json::from_str(&search).unwrap();

    assert_eq!(matches.as_array().map(Vec::len), Some(0));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_wrapped_line_search_matches_across_visual_rows() {
    let session_id =
        session::create_session(&serde_json::to_string(&wrapped_selection_profile()).unwrap())
            .unwrap();

    thread::sleep(Duration::from_millis(200));
    session::resize_session(session_id, 5, 4, 50, 80).unwrap();
    let _ = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row == "abcdefghij")
    });

    let search = session::search_session(session_id, "defg").unwrap();
    let matches: serde_json::Value = serde_json::from_str(&search).unwrap();
    let first = matches
        .as_array()
        .and_then(|entries| entries.first())
        .expect("expected wrapped search match");

    assert_eq!(first["text"].as_str(), Some("defg"));
    assert_eq!(first["row"].as_u64(), Some(0));
    assert_eq!(first["start_col"].as_u64(), Some(3));
    assert_eq!(first["end_col"].as_u64(), Some(7));
    assert_eq!(first["scrollback_offset"].as_u64(), Some(0));

    let frame_after = session::take_frame_diff(session_id).unwrap();
    assert!(
        frame_after.is_none(),
        "search should not dirty or scroll the terminal"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_search_request_supports_substring_case_modes() {
    let session_id =
        session::create_session(&serde_json::to_string(&search_modes_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "err 200");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["scrollback_offset"].as_u64(), Some(0));

    let smart_lower = search_request(session_id, "alpha", "smart_case_substring");
    assert_eq!(smart_lower["error_text"].as_str(), None);
    assert_eq!(smart_lower["matches"].as_array().map(Vec::len), Some(2));

    let smart_upper = search_request(session_id, "Alpha", "smart_case_substring");
    assert_eq!(smart_upper["matches"].as_array().map(Vec::len), Some(1));
    assert_eq!(smart_upper["matches"][0]["text"].as_str(), Some("Alpha"));

    let case_sensitive = search_request(session_id, "alpha", "case_sensitive_substring");
    assert_eq!(case_sensitive["matches"].as_array().map(Vec::len), Some(1));
    assert_eq!(case_sensitive["matches"][0]["text"].as_str(), Some("alpha"));

    let case_insensitive = search_request(session_id, "alpha", "case_insensitive_substring");
    assert_eq!(
        case_insensitive["matches"].as_array().map(Vec::len),
        Some(2)
    );

    let frame_after = session::take_frame_diff(session_id).unwrap();
    assert!(
        frame_after.is_none(),
        "search should not dirty or scroll the terminal"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_search_request_supports_regex_modes_and_errors() {
    let session_id =
        session::create_session(&serde_json::to_string(&search_modes_profile()).unwrap()).unwrap();

    wait_for_frame_containing(session_id, "err 200");

    let case_sensitive = search_request(session_id, r"ERR \d+", "case_sensitive_regex");
    assert_eq!(case_sensitive["error_text"].as_str(), None);
    assert_eq!(case_sensitive["matches"].as_array().map(Vec::len), Some(1));
    assert_eq!(
        case_sensitive["matches"][0]["text"].as_str(),
        Some("ERR 100")
    );

    let case_insensitive = search_request(session_id, r"ERR \d+", "case_insensitive_regex");
    assert_eq!(
        case_insensitive["matches"].as_array().map(Vec::len),
        Some(2)
    );
    assert_eq!(
        case_insensitive["matches"][1]["text"].as_str(),
        Some("err 200")
    );

    let invalid = search_request(session_id, r"ERR \d+(", "case_sensitive_regex");
    assert_eq!(invalid["matches"].as_array().map(Vec::len), Some(0));
    assert_eq!(
        invalid["error_text"].as_str(),
        Some("Invalid regular expression")
    );

    let frame_after = session::take_frame_diff(session_id).unwrap();
    assert!(
        frame_after.is_none(),
        "search should not dirty or scroll the terminal"
    );

    session::close_session(session_id).unwrap();
}

fn search_request(session_id: u64, query: &str, mode: &str) -> serde_json::Value {
    let request = serde_json::json!({
        "kind": "terminal.search_text",
        "query": query,
        "mode": mode,
    });
    let response = session::request_session_json(session_id, &request.to_string())
        .unwrap()
        .expect("expected search response");
    serde_json::from_str(&response).unwrap()
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

    let _ = wait_for_frame_containing(session_id, "line05");
    wait_for_frame_idle(session_id);

    let shifted = wait_for_frame_containing(session_id, "line06");
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

    let _ = wait_for_frame_containing(session_id, "line05");
    wait_for_frame_idle(session_id);
    let _ = wait_for_frame_containing(session_id, "line06");
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
fn asciinema_export_records_output_and_validates_replay_rendering() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_containing(session_id, "hello");

    let request = serde_json::json!({"kind": "terminal.export_asciinema"});
    let response = session::request_session_json(session_id, &request.to_string())
        .unwrap()
        .expect("expected asciinema export response");
    let parsed: serde_json::Value = serde_json::from_str(&response).unwrap();
    let content = parsed["content"]
        .as_str()
        .expect("asciinema export should include content");
    let mut lines = content.lines();
    let header: serde_json::Value =
        serde_json::from_str(lines.next().expect("missing asciinema header")).unwrap();
    let first_event: serde_json::Value =
        serde_json::from_str(lines.next().expect("missing asciinema output event")).unwrap();

    assert_eq!(parsed["format"].as_str(), Some("asciinema-v2"));
    assert_eq!(parsed["scope"].as_str(), Some("terminal-output-asciinema"));
    assert_eq!(parsed["event_count"].as_u64(), Some(1));
    assert_eq!(parsed["truncated"].as_bool(), Some(false));
    assert_eq!(parsed["validation"]["matched"].as_bool(), Some(true));
    assert_eq!(parsed["validation"]["mismatch_count"].as_u64(), Some(0));
    assert_eq!(header["version"].as_u64(), Some(2));
    assert_eq!(header["env"]["TERM"].as_str(), Some("xterm-256color"));
    assert_eq!(first_event[1].as_str(), Some("o"));
    assert!(
        first_event[2]
            .as_str()
            .unwrap_or_default()
            .contains("hello")
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn diagnostics_export_returns_privacy_preserving_evidence_package() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(1100));

    let request = serde_json::json!({
        "kind": "terminal.export_diagnostics",
        "maxSamples": 4,
        "includeContent": true,
        "redactionMode": "basic",
    });
    let response = session::request_session_json(session_id, &request.to_string())
        .unwrap()
        .expect("expected diagnostics export response");
    let parsed: serde_json::Value = serde_json::from_str(&response).unwrap();

    assert_eq!(
        parsed["manifest"]["schema_version"].as_str(),
        Some("terminal-diagnostics-session-v1")
    );
    assert_eq!(parsed["manifest"]["session_id"].as_u64(), Some(session_id));
    assert_eq!(
        parsed["manifest"]["content_included"].as_bool(),
        Some(false)
    );
    assert_eq!(
        parsed["manifest"]["include_content_requested"].as_bool(),
        Some(true)
    );
    assert_eq!(parsed["manifest"]["redaction_mode"].as_str(), Some("basic"));
    assert!(
        parsed["manifest"]["child_pid"].is_u64(),
        "expected captured child pid: {parsed}"
    );

    let samples = parsed["resource_samples"]
        .as_array()
        .expect("expected resource samples");
    assert!(!samples.is_empty());
    assert!(samples.len() <= 4);
    assert!(samples.windows(2).all(|window| {
        window[0]["timestamp_micros"].as_u64().unwrap_or_default()
            <= window[1]["timestamp_micros"].as_u64().unwrap_or_default()
    }));
    assert!(parsed["terminal_stats"]["session"].is_object());
    assert!(parsed["events"].as_array().is_some());
    assert_eq!(
        parsed["summary"]["conclusion"].as_str(),
        Some("insufficient-evidence")
    );
    assert!(
        parsed["summary"]["markdown"]
            .as_str()
            .unwrap_or_default()
            .contains("Privacy handling")
    );
    assert!(
        !response.contains("USER="),
        "diagnostics response should not include raw env"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn diagnostics_export_after_session_close_fails_stably() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    session::close_session(session_id).unwrap();

    let request = serde_json::json!({
        "kind": "terminal.export_diagnostics",
    });

    assert!(session::request_session_json(session_id, &request.to_string()).is_err());
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

#[test]
fn session_sgr_colon_truecolor_skips_empty_color_space_id() {
    let session_id =
        session::create_session(&serde_json::to_string(&sgr_colon_truecolor_profile()).unwrap())
            .unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let rows = parsed["rows"].as_array().expect("expected rows");
    assert!(
        rows[0]["text"]
            .as_str()
            .expect("expected row text")
            .starts_with("RB"),
        "expected row to start with styled cells: {frame}"
    );

    let style_runs = rows[0]["style_runs"]
        .as_array()
        .expect("expected style runs");
    assert_eq!(style_runs[0]["foreground"].as_str(), Some("#ff0000"));
    assert_eq!(style_runs[1]["background"].as_str(), Some("#0000ff"));

    session::close_session(session_id).unwrap();
}

#[test]
fn parser_sgr_reset_cases_clear_individual_attributes() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.process(b"\x1b[1;2;3;4;5;7;8;9;53m\x1b[38;5;1m\x1b[48;5;2m\x1b[58:5:3mA");
    terminal.process(b"\x1b[22;23;24;25;27;28;29;39;49;55;59mB");

    let rows = terminal.get_row_range(0, 1);
    let styled = &rows[0][0];
    assert!(styled.flags.bold());
    assert!(styled.flags.dim());
    assert!(styled.flags.italic());
    assert!(styled.flags.underline());
    assert!(styled.flags.blink());
    assert!(styled.flags.reverse());
    assert!(styled.flags.hidden());
    assert!(styled.flags.strikethrough());
    assert!(styled.flags.overline());
    assert_eq!(styled.fg, Color::Named(NamedColor::Red));
    assert_eq!(styled.bg, Color::Named(NamedColor::Green));
    assert_eq!(
        styled.underline_color,
        Some(Color::Named(NamedColor::Yellow))
    );

    let reset = &rows[0][1];
    assert!(!reset.flags.bold());
    assert!(!reset.flags.dim());
    assert!(!reset.flags.italic());
    assert!(!reset.flags.underline());
    assert!(!reset.flags.blink());
    assert!(!reset.flags.reverse());
    assert!(!reset.flags.hidden());
    assert!(!reset.flags.strikethrough());
    assert!(!reset.flags.overline());
    assert_eq!(reset.fg, Color::Named(NamedColor::White));
    assert_eq!(reset.bg, Color::Named(NamedColor::Black));
    assert_eq!(reset.underline_color, None);
}
