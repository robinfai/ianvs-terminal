//! Product transport acceptance; fixtures are owned by tools/ssh_boundary_lab/product.py.
use super::*;
use crate::model::{
    TerminalConnectionType, TerminalProfile, TerminalSshAuthMethod, TerminalSshHostKeyPolicy,
};
use crate::pty::{PtyRuntime, spawn_terminal_transport};
use crate::ssh::SftpOperation;
use std::time::{Duration, Instant};

struct Terminal {
    runtime: PtyRuntime,
    incoming: std::sync::mpsc::Receiver<Vec<u8>>,
    output: Vec<u8>,
}
impl Terminal {
    fn new(profile: &TerminalProfile) -> Self {
        let mut runtime = spawn_terminal_transport(profile, 30, 120).unwrap();
        let mut reader = std::mem::replace(&mut runtime.reader, Box::new(std::io::empty()));
        let (tx, incoming) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            loop {
                let mut data = vec![0; 8192];
                match reader.read(&mut data) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        data.truncate(n);
                        if tx.send(data).is_err() {
                            break;
                        }
                    }
                }
            }
        });
        Self {
            runtime,
            incoming,
            output: Vec::new(),
        }
    }
    fn send(&mut self, command: &str) -> usize {
        let start = self.output.len();
        self.runtime
            .writer
            .write_all(format!("{command}\r").as_bytes())
            .unwrap();
        self.runtime.writer.flush().unwrap();
        start
    }
    fn until(
        &mut self,
        start: usize,
        predicate: impl Fn(&[serde_json::Value], &[u8]) -> bool,
    ) -> Vec<serde_json::Value> {
        let deadline = Instant::now() + Duration::from_secs(15);
        loop {
            let events = super::tests::events(&self.output[start..]);
            if predicate(&events, &self.output[start..]) {
                return events;
            }
            assert!(
                Instant::now() < deadline,
                "transport deadline: {}",
                String::from_utf8_lossy(&self.output[start..])
            );
            match self.incoming.recv_timeout(Duration::from_millis(100)) {
                Ok(data) => {
                    self.output.extend(data);
                    assert!(self.output.len() < 8 * 1024 * 1024);
                }
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
                Err(_) => panic!(
                    "transport closed: {}",
                    String::from_utf8_lossy(&self.output[start..])
                ),
            }
        }
    }
    fn ready(&mut self, start: usize) -> serde_json::Value {
        self.until(start, |events, _| {
            events.iter().any(|e| e["hook"] == "bootstrap.ready")
        })
        .into_iter()
        .find(|e| e["hook"] == "bootstrap.ready")
        .unwrap()
    }
    fn enter(&mut self, command: &str) -> String {
        let start = self.send(command);
        let ready = self.ready(start);
        assert_eq!(ready["registered"], true, "{ready}");
        ready["context_id"].as_str().unwrap().into()
    }

    fn verify_capabilities(&mut self, context: &str) -> serde_json::Value {
        let initial = self.until(0, |events, _| {
            events
                .iter()
                .any(|e| e["hook"] == "precmd.pwd" && e["context_id"] == context)
        });
        let ready = initial
            .iter()
            .find(|e| e["hook"] == "bootstrap.ready" && e["context_id"] == context)
            .unwrap();
        let builtin = [
            "current_directory",
            "prompt_lifecycle",
            "command_start",
            "command_text",
            "command_finish",
            "exit_code",
            "shell_identity",
        ];
        for capability in builtin {
            assert_eq!(ready["checks"][capability], "registered", "{ready}");
        }
        assert!(
            !initial.iter().any(|e| e["context_id"] == context
                && (e["hook"] == "preexec" || e["hook"] == "command_finished")),
            "commands were reported before user input: {initial:?}"
        );
        let shell = ready["shell"].clone();
        let mut observations = Vec::new();
        for (command, code) in [("false", 1), ("true", 0)] {
            let start = self.send(command);
            let events = self.until(start, |events, _| {
                let finished = events.iter().position(|e| {
                    e["hook"] == "command_finished"
                        && e["command"] == command
                        && e["exit_code"] == code
                        && e["context_id"] == context
                });
                finished.is_some_and(|index| {
                    events[index + 1..]
                        .iter()
                        .any(|e| e["hook"] == "precmd.pwd" && e["context_id"] == context)
                })
            });
            let started = events
                .iter()
                .position(|e| {
                    e["hook"] == "preexec" && e["command"] == command && e["context_id"] == context
                })
                .expect("missing command start");
            let finished = events
                .iter()
                .position(|e| {
                    e["hook"] == "command_finished"
                        && e["command"] == command
                        && e["exit_code"] == code
                        && e["context_id"] == context
                })
                .unwrap();
            assert!(started < finished, "{events:?}");
            assert_eq!(events[started]["shell"], shell);
            assert_eq!(events[finished]["shell"], shell);
            assert!(
                events[finished + 1..]
                    .iter()
                    .any(|e| e["hook"] == "precmd" && e["context_id"] == context)
            );
            assert!(
                events[finished + 1..]
                    .iter()
                    .any(|e| e["hook"] == "precmd.pwd"
                        && e["context_id"] == context
                        && e["pwd"].as_str().is_some_and(|pwd| pwd.starts_with('/')))
            );
            observations.push(json!({"command": command, "exit_code": code,
                "event_order": ["preexec", "command_finished", "precmd", "precmd.pwd"]}));
        }
        json!({"shell": shell, "startup_registered": builtin, "runtime_verified": builtin,
            "no_command_before_input": true, "observations": observations})
    }
    fn operation(&self, context: &str, operation: SftpOperation) -> Result<(), String> {
        self.runtime
            .ssh_sftp
            .as_ref()
            .unwrap()
            .start_operation_in_context(operation, context.into())
            .unwrap()
            .blocking_recv()
            .unwrap()
    }
    fn role(&self, context: &str, path: &std::path::Path) -> String {
        self.operation(
            context,
            SftpOperation::DownloadFile {
                remote_path: "/home/lab/role.txt".into(),
                local_path: path.to_string_lossy().into(),
            },
        )
        .unwrap();
        std::fs::read_to_string(path).unwrap().trim().into()
    }
    fn leave(&mut self, parent: &str) {
        let start = self.send("exit");
        self.until(start, |events, _| {
            events
                .iter()
                .any(|e| e["hook"] == "bootstrap.resume" && e["context_id"] == parent)
        });
    }
    fn close_cleanly(&mut self) {
        self.send("exit");
        let deadline = Instant::now() + Duration::from_secs(3);
        while self.runtime.child.try_wait().unwrap().is_none() && Instant::now() < deadline {
            if let Ok(data) = self.incoming.recv_timeout(Duration::from_millis(50)) {
                self.output.extend(data);
            }
        }
    }
}
impl Drop for Terminal {
    fn drop(&mut self) {
        let _ = self.runtime.child.kill();
        let _ = self.runtime.child.wait();
    }
}

#[test]
fn local_registration_is_reported_without_a_user_command() {
    for shell in ["/bin/bash", "/bin/zsh", "/opt/homebrew/bin/fish"] {
        if !std::path::Path::new(shell).exists() {
            continue;
        }
        let scratch = tempfile::tempdir().unwrap();
        let mut profile: TerminalProfile =
            serde_json::from_value(json!({"id":"startup-check", "name":"Startup check"})).unwrap();
        profile.launch.program = shell.into();
        profile
            .launch
            .env
            .insert("HOME".into(), scratch.path().to_string_lossy().into());
        profile.launch.cwd = Some(scratch.path().to_string_lossy().into());
        profile.shell_integration.ssh_wrapper = false;
        let mut terminal = Terminal::new(&profile);
        let ready = terminal.ready(0);
        assert_eq!(ready["registered"], true, "{shell}: {ready}");
        assert_eq!(ready["checks"]["command_start"], "registered");
        assert_eq!(ready["checks"]["command_finish"], "registered");
        assert_eq!(ready["checks"]["exit_code"], "registered");
        assert_eq!(ready["checks"]["prompt_navigation"], "unverified");
        assert!(
            !super::tests::events(&terminal.output)
                .iter()
                .any(|event| event["hook"] == "preexec" || event["hook"] == "command_finished"),
            "startup created a command event: {}",
            String::from_utf8_lossy(&terminal.output)
        );
        terminal.close_cleanly();
    }
}

#[test]
fn local_bash_conflict_does_not_record_prompt_commands() {
    let scratch = tempfile::tempdir().unwrap();
    std::fs::write(scratch.path().join(".bashrc"), format!(
        "__IANVS_BOOTSTRAPPING=1\nIANVS_SKIP_ORIGINAL_BASHRC=1\nIANVS_SHELL_INTEGRATION=1\n{}\nPROMPT_COMMAND+='; :'\nPS1='LOCAL_READY> '\nunset __IANVS_BOOTSTRAPPING\n",
        crate::pty::bash_hook_source()
    )).unwrap();
    let mut profile: TerminalProfile =
        serde_json::from_value(json!({"id":"bash-conflict", "name":"Bash conflict"})).unwrap();
    profile.launch.program = "/bin/bash".into();
    profile
        .launch
        .env
        .insert("HOME".into(), scratch.path().to_string_lossy().into());
    let mut terminal = Terminal::new(&profile);
    let ready = terminal.ready(0);
    assert_eq!(ready["registered"], false, "{ready}");
    let events = terminal.until(0, |_, bytes| {
        String::from_utf8_lossy(bytes).contains("LOCAL_READY>")
    });
    assert!(
        !events
            .iter()
            .any(|event| event["hook"] == "preexec" || event["hook"] == "command_finished"),
        "{events:?}"
    );
    terminal.close_cleanly();
}

#[test]
fn local_registration_detects_login_hook_removal() {
    if !std::path::Path::new("/bin/zsh").exists() {
        return;
    }
    let scratch = tempfile::tempdir().unwrap();
    std::fs::write(scratch.path().join(".zlogin"), "preexec_functions=()\n").unwrap();
    let mut profile: TerminalProfile =
        serde_json::from_value(json!({"id":"startup-conflict", "name":"Startup conflict"}))
            .unwrap();
    profile.launch.program = "/bin/zsh".into();
    profile.launch.args = vec!["-l".into()];
    profile
        .launch
        .env
        .insert("HOME".into(), scratch.path().to_string_lossy().into());
    let mut terminal = Terminal::new(&profile);
    let ready = terminal.ready(0);
    assert_eq!(ready["registered"], false, "{ready}");
    assert_eq!(ready["checks"]["command_start"], "unavailable");
    terminal.close_cleanly();
}

#[test]
fn local_shell_switch_keeps_tracking_without_ssh_wrapping() {
    if !std::path::Path::new("/bin/zsh").exists() {
        return;
    }
    let scratch = tempfile::tempdir().unwrap();
    std::fs::write(
        scratch.path().join(".bashrc"),
        "HISTCONTROL=\nHISTFILE=~/.bash_history\nCHILD_RC=bash\n",
    )
    .unwrap();
    std::fs::write(
        scratch.path().join(".zshrc"),
        "unsetopt hist_ignore_space\nHISTFILE=~/.zsh_history\nHISTSIZE=100\nSAVEHIST=100\n",
    )
    .unwrap();
    let mut profile: TerminalProfile =
        serde_json::from_value(json!({"id":"shell-switch", "name":"Shell switch"})).unwrap();
    profile.launch.program = "/bin/zsh".into();
    profile
        .launch
        .env
        .insert("HOME".into(), scratch.path().to_string_lossy().into());
    profile.launch.cwd = Some(scratch.path().to_string_lossy().into());
    profile.shell_integration.ssh_wrapper = false;
    let mut terminal = Terminal::new(&profile);
    terminal.until(0, |events, _| events.iter().any(|e| e["hook"] == "precmd"));
    let bash = terminal.enter("bash");
    let start = terminal.send("test \"$CHILD_RC\" = bash");
    terminal.until(start, |events, _| {
        events.iter().any(|e| {
            e["hook"] == "command_finished" && e["exit_code"] == 0 && e["context_id"] == bash
        })
    });
    let start = terminal.send("false");
    terminal.until(start, |events, _| {
        events.iter().any(|e| {
            e["hook"] == "command_finished"
                && e["command"] == "false"
                && e["exit_code"] == 1
                && e["context_id"] == bash
        })
    });
    let zsh = terminal.enter("zsh");
    assert_ne!(bash, zsh);
    let start = terminal.send("false");
    terminal.until(start, |events, _| {
        events.iter().any(|e| {
            e["hook"] == "command_finished"
                && e["command"] == "false"
                && e["exit_code"] == 1
                && e["context_id"] == zsh
        })
    });
    terminal.leave(&bash);
    terminal.leave("root");
    let start = terminal.send("bash -c 'printf __SCRIPT_OK__'");
    let script_events = terminal.until(start, |events, bytes| {
        String::from_utf8_lossy(bytes).contains("__SCRIPT_OK__")
            && events.iter().any(|e| e["hook"] == "command_finished")
    });
    assert!(
        !script_events
            .iter()
            .any(|e| e["hook"] == "bootstrap.checking")
    );
    let start = terminal.send("false");
    terminal.until(start, |events, _| {
        events.iter().any(|e| {
            e["hook"] == "command_finished" && e["command"] == "false" && e["exit_code"] == 1
        })
    });
    terminal.close_cleanly();
    for file in [".bash_history", ".zsh_history"] {
        let history = std::fs::read_to_string(scratch.path().join(file)).unwrap();
        assert!(
            history.contains("false"),
            "missing history positive control: {file}"
        );
        assert!(
            !history.contains("__ianvs") && !history.contains("eval "),
            "injected history in {file}"
        );
    }
}

#[test]
#[ignore = "requires disposable OpenSSH fixtures from tools/ssh_boundary_lab/product.py"]
fn product_ssh_bootstrap_acceptance() {
    let fixture: serde_json::Value = serde_json::from_slice(
        &std::fs::read(std::env::var("IANVS_BOOTSTRAP_FIXTURE").unwrap()).unwrap(),
    )
    .unwrap();
    let profile = |node: &str, inject: bool| {
        let mut p: TerminalProfile = serde_json::from_value(
            json!({"id":"bootstrap-acceptance", "name":"Bootstrap acceptance"}),
        )
        .unwrap();
        p.connection.connection_type = TerminalConnectionType::Ssh;
        p.connection.host = "127.0.0.1".into();
        p.connection.port = fixture["nodes"][node]["port"].as_u64().unwrap() as u16;
        p.connection.user = "lab".into();
        p.connection.auth = TerminalSshAuthMethod::PublicKey;
        p.connection.private_keys = vec![fixture["key"].as_str().unwrap().into()];
        p.connection.host_key_policy = TerminalSshHostKeyPolicy::Strict;
        p.connection.known_hosts_file = Some(fixture["known_hosts"].as_str().unwrap().into());
        p.shell_integration.ssh_auto_inject = Some(inject);
        p.shell_integration.ssh_wrapper = true;
        p
    };
    let mut evidence = Vec::new();
    for (node, source) in [
        ("a", "installed"),
        ("zsh", "installed"),
        ("fish", "installed"),
        ("preloaded", "reused"),
        ("debug", "hook_conflict"),
        ("stale", "installed"),
        ("history", "installed"),
        ("readonly", "installed"),
        ("sh", "unsupported"),
    ] {
        println!("PRODUCT direct {node}");
        let mut terminal = Terminal::new(&profile(node, true));
        let ready = terminal.ready(0);
        assert_eq!(ready["source"], source, "{node}: {ready}");
        terminal.until(0, |_, bytes| {
            String::from_utf8_lossy(bytes).contains("Connected to")
        });
        let text = String::from_utf8_lossy(&terminal.output);
        // The application-ready banner comes after the capability check record.
        let ready_frame = hook(ready.clone());
        let ready_offset = terminal
            .output
            .windows(ready_frame.len())
            .position(|bytes| bytes == ready_frame)
            .unwrap();
        assert!(text.find("Connected to").unwrap() > ready_offset);
        if source == "installed" || source == "reused" {
            let verified = terminal.verify_capabilities("root");
            evidence.push(json!({"scenario": node, "source": source,
                "ready_before_connected": true, "capabilities": verified}));
        } else {
            assert_eq!(ready["registered"], false);
            evidence.push(json!({"scenario": node, "source": source,
                "ready_before_connected": true, "registered": false}));
        }
        if matches!(node, "a" | "zsh" | "fish") {
            println!("PRODUCT shell switching {node}");
            let bash = terminal.enter("bash");
            evidence.push(json!({"scenario": format!("{node}/bash"), "capabilities": terminal.verify_capabilities(&bash)}));
            let zsh = terminal.enter("zsh");
            evidence.push(json!({"scenario": format!("{node}/bash/zsh"), "capabilities": terminal.verify_capabilities(&zsh)}));
            let fish = terminal.enter("fish");
            evidence.push(json!({"scenario": format!("{node}/bash/zsh/fish"), "capabilities": terminal.verify_capabilities(&fish)}));
            let child = terminal.enter("ssh c");
            let scratch = tempfile::tempdir().unwrap();
            assert_eq!(terminal.role(&child, &scratch.path().join("role")), "c");
            terminal.leave(&fish);
            terminal.leave(&zsh);
            terminal.leave(&bash);
            terminal.leave("root");
        }
        terminal.close_cleanly();
    }
    println!("PRODUCT early input");
    let mut early = Terminal::new(&profile("a", true));
    early.send("false");
    assert_eq!(early.ready(0)["registered"], true);
    early.until(0, |events, _| {
        events.iter().any(|e| {
            e["hook"] == "command_finished" && e["command"] == "false" && e["exit_code"] == 1
        })
    });
    early.close_cleanly();
    println!("PRODUCT disabled");
    let mut disabled = Terminal::new(&profile("a", false));
    disabled.until(0, |_, bytes| {
        String::from_utf8_lossy(bytes).contains("LAB_PROMPT>")
    });
    assert!(
        !super::tests::events(&disabled.output)
            .iter()
            .any(|e| e["hook"] == "bootstrap.ready")
    );
    disabled.close_cleanly();
    let scratch = tempfile::tempdir().unwrap();
    for local in [false, true] {
        println!("PRODUCT recursive SSH / ControlMaster / SFTP local={local}");
        let mut p = profile("a", true);
        if local {
            p.connection.connection_type = TerminalConnectionType::Local;
            p.launch.program = "/bin/bash".into();
            p.launch
                .env
                .insert("HOME".into(), scratch.path().to_string_lossy().into());
            p.launch
                .env
                .insert("BASH_SILENCE_DEPRECATION_WARNING".into(), "1".into());
            p.launch.cwd = Some(scratch.path().to_string_lossy().into());
        }
        let mut terminal = Terminal::new(&p);
        let root = if local {
            terminal.until(0, |events, _| events.iter().any(|e| e["hook"] == "precmd"));
            terminal.enter(&format!(
                "ssh -F {} a",
                quote(fixture["local_config"].as_str().unwrap())
            ))
        } else {
            assert_eq!(terminal.ready(0)["registered"], true);
            "root".into()
        };
        evidence.push(json!({"scenario": format!("recursive/local={local}/a"),
            "capabilities": terminal.verify_capabilities(&root)}));
        let b = terminal.enter("ssh b");
        evidence.push(
            json!({"scenario": format!("recursive/local={local}/b-no-sftp"),
            "capabilities": terminal.verify_capabilities(&b)}),
        );
        let c = terminal.enter("ssh c");
        evidence.push(json!({"scenario": format!("recursive/local={local}/c"),
            "capabilities": terminal.verify_capabilities(&c)}));
        assert_eq!(terminal.role(&c, &scratch.path().join("role.txt")), "c");
        let shell_c = terminal.enter("zsh");
        evidence.push(json!({"scenario": format!("recursive/local={local}/c/zsh"),
            "capabilities": terminal.verify_capabilities(&shell_c)}));
        assert_ne!(shell_c, c);
        // The file panel keeps its host context while the foreground shell changes.
        assert_eq!(
            terminal.role(&c, &scratch.path().join("same-host.txt")),
            "c"
        );
        terminal.leave(&c);
        let source = scratch.path().join("source.txt");
        std::fs::write(&source, "endpoint-c").unwrap();
        terminal
            .operation(
                &c,
                SftpOperation::UploadFile {
                    local_path: source.to_string_lossy().into(),
                    remote_path: "/home/lab/product-write.txt".into(),
                },
            )
            .unwrap();
        // Replacement takes a second SFTP channel on the same pinned route.
        std::fs::write(&source, "endpoint-c-overwrite").unwrap();
        terminal
            .operation(
                &c,
                SftpOperation::UploadFile {
                    local_path: source.to_string_lossy().into(),
                    remote_path: "/home/lab/product-write.txt".into(),
                },
            )
            .unwrap();
        terminal.leave(&b);
        assert!(
            terminal
                .operation(
                    &c,
                    SftpOperation::CreateDirectory {
                        path: "/home/lab/WRONG_ENDPOINT".into()
                    }
                )
                .is_err()
        );
        assert!(
            terminal
                .runtime
                .ssh_sftp
                .as_ref()
                .unwrap()
                .start_list_directory_in_context("/home/lab".into(), b.clone())
                .unwrap()
                .blocking_recv()
                .unwrap()
                .is_err()
        );
        terminal.leave(&root);
        if local {
            terminal.leave("root");
        }
        terminal.close_cleanly();
    }
    if let Some(path) = fixture["capability_evidence"].as_str() {
        std::fs::write(
            path,
            serde_json::to_vec_pretty(&json!({"passed": true, "scenarios": evidence})).unwrap(),
        )
        .unwrap();
    }
}
