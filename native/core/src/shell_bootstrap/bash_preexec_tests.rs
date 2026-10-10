//! Compatibility with the observed legacy bash-preexec prompt dispatcher.
//! Uses installed Bash and real PTYs; no SSH server, Docker or network needed.
use super::*;
use crate::composer_bridge::Submit;
use portable_pty::{CommandBuilder, PtySize, native_pty_system};
use std::path::Path;
use std::process::Command;
use std::sync::mpsc::{Receiver, RecvTimeoutError};
use std::time::{Duration, Instant};

const FIXTURE: &str = include_str!("bash_preexec_fixture.bash");
const PROMPT: &[u8] = b"__BPE_READY__> ";
const GUARD: &str =
    "if declare -F __bp_precmd_invoke_cmd &>/dev/null; then __bp_precmd_invoke_cmd; fi;";

fn wait_prompt(
    bootstrap: &mut Bootstrap,
    writer: &mut dyn Write,
    incoming: &Receiver<Vec<u8>>,
    output: &mut Vec<u8>,
    start: usize,
) {
    let deadline = Instant::now() + Duration::from_secs(8);
    while !output[start..].ends_with(PROMPT) {
        assert!(
            Instant::now() < deadline,
            "Bash prompt deadline: {}",
            String::from_utf8_lossy(&output[start..])
        );
        match incoming.recv_timeout(Duration::from_millis(20)) {
            Ok(bytes) => {
                let processed = bootstrap.feed(&bytes);
                output.extend(processed.output);
                for reply in processed.replies {
                    writer.write_all(&reply).unwrap();
                    writer.flush().unwrap();
                }
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(error) => panic!("Bash PTY closed: {error}"),
        }
    }
}

fn real_bash(shell: &str, style: &str, has_composer: bool) {
    let home = tempfile::tempdir().unwrap();
    std::fs::write(
        home.path().join(".bash_profile"),
        format!(
            "PS1='__BPE_READY__> '\nHISTCONTROL=\nHISTFILE=~/.bash_history\n__probe_style={style}\n{FIXTURE}"
        ),
    )
    .unwrap();
    let mut bootstrap = Bootstrap::new(token(), false);
    let bridge = bootstrap.composer.clone();
    let pair = native_pty_system().openpty(PtySize::default()).unwrap();
    let mut command = CommandBuilder::new("/bin/sh");
    command.args(["-c", &bootstrap.launch_command()]);
    command.env("HOME", home.path());
    command.env("SHELL", shell);
    command.env("TERM", "xterm-256color");
    command.cwd(home.path());
    let mut child = pair.slave.spawn_command(command).unwrap();
    drop(pair.slave);
    let mut reader = pair.master.try_clone_reader().unwrap();
    let mut writer = pair.master.take_writer().unwrap();
    let (tx, incoming) = std::sync::mpsc::channel();
    let reader_thread = std::thread::spawn(move || {
        loop {
            let mut bytes = [0; 8192];
            match reader.read(&mut bytes) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    if tx.send(bytes[..n].to_vec()).is_err() {
                        break;
                    }
                }
            }
        }
    });
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut output = Vec::new();
        wait_prompt(&mut bootstrap, &mut writer, &incoming, &mut output, 0);
        let initial = tests::events(&output);
        assert!(
            initial
                .iter()
                .any(|event| event["hook"] == "bootstrap.ready" && event["registered"] == true),
            "{shell} {style}: {initial:?}"
        );
        assert!(
            !initial.iter().any(|event| matches!(
                event["hook"].as_str(),
                Some("preexec" | "command_finished")
            )),
            "first prompt reported a command: {initial:?}"
        );
        let mut commands = vec![
            (false, "false", 1),
            (false, "true", 0),
            (false, "/bin/sh -c 'exit 7'", 7),
        ];
        if has_composer {
            // macOS does not provide /bin/true or /bin/false. The bootstrap
            // already requires /bin/sh; keep these external exit checks portable.
            commands.extend([
                (true, "/bin/sh -c 'exit 1'", 1),
                (true, "/bin/sh -c 'exit 0'", 0),
                (true, "/bin/sh -c 'exit 7'", 7),
            ]);
        }
        let inspect = "printf ''; __ianvs_repair_bash_preexec_prompt; __ianvs_repair_bash_preexec_prompt; __ianvs_install_shell_hooks; __ianvs_install_shell_hooks; declare -p PROMPT_COMMAND; printf 'PRECMD=%s:%s\\n' \"${#precmd_functions[@]}\" \"${precmd_functions[*]}\"; printf 'PREEXEC=%s:%s\\n' \"${#preexec_functions[@]}\" \"${preexec_functions[*]}\"; printf 'HISTORY_TAIL=%s\\n' \"$__probe_history_count\"; trap -p DEBUG";
        commands.push((has_composer, inspect, 0));
        commands.push((has_composer, "/bin/sh -c 'exit 7'", 7));
        let history = regex::Regex::new(r"HISTORY_TAIL=(\d+)").unwrap();
        for (index, (use_composer, text, code)) in commands.into_iter().enumerate() {
            let start = output.len();
            let id = format!("status-{index}");
            let wire = if use_composer {
                let state = bridge.snapshot().unwrap();
                assert_eq!(state["state"], "ready", "{shell} {style}: {state}");
                bridge
                    .submit(Submit {
                        lease: state["lease"].as_str().unwrap().into(),
                        submission_id: id.clone(),
                        text: text.into(),
                    })
                    .1
                    .expect("ready Composer must produce submission bytes")
            } else {
                format!("{text}\r").into_bytes()
            };
            writer.write_all(&wire).unwrap();
            writer.flush().unwrap();
            wait_prompt(&mut bootstrap, &mut writer, &incoming, &mut output, start);
            let events = tests::events(&output[start..]);
            let started: Vec<_> = events
                .iter()
                .filter(|event| event["hook"] == "preexec")
                .collect();
            let finished: Vec<_> = events
                .iter()
                .filter(|event| event["hook"] == "command_finished")
                .collect();
            assert_eq!(started.len(), 1, "{shell} {style}: {events:?}");
            assert_eq!(finished.len(), 1, "{shell} {style}: {events:?}");
            assert_eq!(started[0]["command"], text, "{shell} {style}: {events:?}");
            assert_eq!(finished[0]["command"], text, "{shell} {style}: {events:?}");
            assert_eq!(
                finished[0]["exit_code"], code,
                "{shell} {style}: {events:?}"
            );
            if use_composer {
                assert_eq!(started[0]["submission_id"], id);
                assert_eq!(bridge.snapshot().unwrap()["outcome"], "accepted");
            }
            if text == inspect {
                let captured = String::from_utf8_lossy(&output[start..]).replace('\r', "");
                let entry = if style.starts_with("legacy") {
                    "__ianvs_bash_preexec_precmd;"
                } else {
                    "__bp_precmd_invoke_cmd;"
                };
                let expected = if style.ends_with("array") {
                    format!(
                        "declare -a PROMPT_COMMAND=([2]=\"{entry}\" [5]=\"history -a; ((__probe_history_count+=1));\" [9]=\"__bp_interactive_mode;\")"
                    )
                } else {
                    format!(
                        "declare -- PROMPT_COMMAND=\"{entry} history -a; ((__probe_history_count+=1)); __bp_interactive_mode;\""
                    )
                };
                assert!(captured.contains(&expected), "{captured}");
                assert!(
                    captured.contains("PRECMD=1:__ianvs_prompt_command\n"),
                    "{captured}"
                );
                assert!(
                    captured.contains("PREEXEC=1:__ianvs_preexec\n"),
                    "{captured}"
                );
                assert!(
                    captured.contains("trap -- '__bp_preexec_invoke_exec \"$_\"' DEBUG"),
                    "{captured}"
                );
                let count: usize = history.captures(&captured).unwrap()[1].parse().unwrap();
                assert!(
                    count >= index,
                    "original history prompt command stopped: {captured}"
                );
            }
        }
    }));
    let _ = child.kill();
    let _ = child.wait();
    drop(writer);
    drop(pair.master);
    drop(incoming);
    let _ = reader_thread.join();
    if let Err(error) = result {
        std::panic::resume_unwind(error);
    }
}

#[test]
fn bash_preexec_status_survives_legacy_and_modern_prompt_dispatch() {
    for shell in ["/bin/bash", "/opt/homebrew/bin/bash", "/usr/local/bin/bash"] {
        if !Path::new(shell).exists() {
            continue;
        }
        let output = Command::new(shell)
            .args([
                "--noprofile",
                "--norc",
                "-c",
                "printf '%s %s' \"${BASH_VERSINFO[0]}\" \"${BASH_VERSINFO[1]}\"",
            ])
            .output()
            .unwrap();
        assert!(output.status.success());
        let version: Vec<u32> = String::from_utf8(output.stdout)
            .unwrap()
            .split_whitespace()
            .map(|part| part.parse().unwrap())
            .collect();
        for backend in ["legacy", "modern"] {
            for installation in ["deferred", "installed"] {
                real_bash(
                    shell,
                    &format!("{backend}-{installation}-string"),
                    version[0] >= 4,
                );
                // Older Bash executes PROMPT_COMMAND as a string; exercise the
                // sparse-array execution path only where Bash supports it.
                if (version[0], version[1]) >= (5, 1) {
                    real_bash(shell, &format!("{backend}-{installation}-array"), true);
                }
            }
        }
    }
}

#[test]
fn bash_preexec_repair_preserves_sparse_array_and_unknown_prompt_prefix() {
    let home = tempfile::tempdir().unwrap();
    let script = format!(
        r#"
__probe_style=legacy-installed-array
{FIXTURE}
IANVS_SHELL_INTEGRATION=1
IANVS_SKIP_ORIGINAL_BASHRC=1
PROMPT_COMMAND[10]={guard}
{hooks}
__ianvs_repair_bash_preexec_prompt
__ianvs_install_shell_hooks
[[ "${{!PROMPT_COMMAND[*]}}" = '2 5 9 10' ]] || exit 21
[[ "${{PROMPT_COMMAND[2]}}" = '__ianvs_bash_preexec_precmd;' ]] || exit 22
[[ "${{PROMPT_COMMAND[5]}}" = 'history -a; ((__probe_history_count+=1));' ]] || exit 23
[[ "${{PROMPT_COMMAND[10]}}" = {guard} ]] || exit 24
[[ "${{precmd_functions[*]}}" = '__ianvs_prompt_command' ]] || exit 25
[[ "${{preexec_functions[*]}}" = '__ianvs_preexec' ]] || exit 26
unset PROMPT_COMMAND
PROMPT_COMMAND=':; '{guard}
__probe_original=$PROMPT_COMMAND
__ianvs_repair_bash_preexec_prompt
[[ "$PROMPT_COMMAND" = "$__probe_original" ]] || exit 27
"#,
        guard = quote(GUARD),
        hooks = crate::pty::bash_hook_source()
    );
    let output = Command::new("/bin/bash")
        .args(["--noprofile", "--norc", "-c", &script])
        .env("HOME", home.path())
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "status={:?}, stderr={}",
        output.status.code(),
        String::from_utf8_lossy(&output.stderr)
    );
}
