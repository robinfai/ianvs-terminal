#![cfg(target_os = "linux")]

use ianvs_core::model::{
    TerminalConnectionType, TerminalProfileAppearance, TerminalProfileConnection,
    TerminalProfileInteraction, TerminalProfileLaunch, TerminalProfileTerminal,
    TerminalShellIntegration, TerminalSshAuthMethod, TerminalSshHostKeyPolicy,
};
use ianvs_core::session;
use ianvs_core::ssh::{SftpOperation, SshRuntime, spawn_ssh};
use serde_json::{Value, json};
use std::env;
use std::fs::{self, File, FileTimes};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant, UNIX_EPOCH};

const TIMEOUT: Duration = Duration::from_secs(30);

fn required_env(name: &str) -> String {
    env::var(name).unwrap_or_else(|_| panic!("{name} is required; run tools/linux_e2e/run.sh"))
}

fn fixture() -> PathBuf {
    let root = PathBuf::from(required_env("IANVS_LOOPBACK_ROOT"));
    assert!(root.is_absolute());
    assert_eq!(
        fs::read_to_string(root.join("marker")).unwrap(),
        "ianvs-linux-loopback-v1\n"
    );
    root
}

fn connection(root: &Path) -> TerminalProfileConnection {
    TerminalProfileConnection {
        connection_type: TerminalConnectionType::Ssh,
        host: "127.0.0.1".to_string(),
        port: required_env("IANVS_LOOPBACK_PORT").parse().unwrap(),
        user: required_env("IANVS_LOOPBACK_USER"),
        auth: TerminalSshAuthMethod::PublicKey,
        private_keys: vec![root.join("client_key").to_string_lossy().into_owned()],
        host_key_policy: TerminalSshHostKeyPolicy::Strict,
        known_hosts_file: Some(root.join("known_hosts").to_string_lossy().into_owned()),
        connect_timeout_seconds: 5,
        ..<_>::default()
    }
}

fn sftp_operation(runtime: &SshRuntime, operation: SftpOperation) {
    let response = runtime.sftp.start_operation(operation).unwrap();
    let (sender, receiver) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let _ = sender.send(response.blocking_recv());
    });
    receiver.recv_timeout(TIMEOUT).unwrap().unwrap().unwrap();
}

fn shell_probe(runtime: SshRuntime) {
    let SshRuntime {
        mut reader,
        mut writer,
        mut child,
        ..
    } = runtime;
    let (sender, receiver) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let mut output = Vec::new();
        let result = reader.read_to_end(&mut output).map(|_| output);
        let _ = sender.send(result);
    });
    writer
        .write_all(b"test -t 0 && test -t 1 && printf 'IANVS_LOOPBACK_%s\\n' SSH_OK; exit\n")
        .unwrap();
    writer.flush().unwrap();
    drop(writer);
    let output = match receiver.recv_timeout(TIMEOUT) {
        Ok(result) => result.unwrap(),
        Err(error) => {
            let _ = child.kill();
            panic!("native SSH shell timed out: {error}");
        }
    };
    assert!(child.wait().unwrap().success());
    let text = String::from_utf8_lossy(&output);
    assert!(text.contains("IANVS_LOOPBACK_SSH_OK"), "{text}");
    assert!(!text.contains("Ianvs SSH:"), "{text}");
}

#[test]
#[ignore = "requires disposable AsyncSSH/lrzsz peer; run tools/linux_e2e/run.sh"]
fn native_ssh_sftp_and_zmodem_loopback() {
    let root = fixture();
    let connection = connection(&root);
    let runtime = spawn_ssh(connection.clone(), 24, 100).unwrap();
    let remote = PathBuf::from("/sftp-remote");
    let upload = root.join("sftp-upload.bin");
    let download = root.join("sftp-download.bin");
    let payload = payload(257 * 1024, 13);
    fs::write(&upload, &payload).unwrap();
    sftp_operation(
        &runtime,
        SftpOperation::CreateDirectory {
            path: remote.to_string_lossy().into_owned(),
        },
    );
    let remote_file = remote.join("roundtrip.bin");
    sftp_operation(
        &runtime,
        SftpOperation::UploadFile {
            local_path: upload.to_string_lossy().into_owned(),
            remote_path: remote_file.to_string_lossy().into_owned(),
        },
    );
    let listing = runtime
        .sftp
        .start_list_directory(remote.to_string_lossy().into_owned())
        .unwrap();
    let (sender, receiver) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let _ = sender.send(listing.blocking_recv());
    });
    let listing = receiver.recv_timeout(TIMEOUT).unwrap().unwrap().unwrap();
    assert!(
        listing
            .entries
            .iter()
            .any(|entry| entry.name == "roundtrip.bin")
    );
    sftp_operation(
        &runtime,
        SftpOperation::DownloadFile {
            local_path: download.to_string_lossy().into_owned(),
            remote_path: remote_file.to_string_lossy().into_owned(),
        },
    );
    assert_eq!(fs::read(&download).unwrap(), payload);
    sftp_operation(
        &runtime,
        SftpOperation::DeleteEntry {
            path: remote_file.to_string_lossy().into_owned(),
            is_directory: false,
        },
    );
    sftp_operation(
        &runtime,
        SftpOperation::DeleteEntry {
            path: remote.to_string_lossy().into_owned(),
            is_directory: true,
        },
    );
    assert!(!root.join("sftp-remote").exists());
    shell_probe(runtime);
    eprintln!("linux-loopback: strict-key native SSH and SFTP list/upload/download/delete passed");
    zmodem_roundtrip(&root, connection);
}

struct SessionGuard(u64);

impl Drop for SessionGuard {
    fn drop(&mut self) {
        let _ = session::close_session(self.0);
    }
}

fn terminal(connection: TerminalProfileConnection) -> SessionGuard {
    // SessionConfig's exact wire contract requires explicit null option fields;
    // TerminalProfile serialization deliberately omits those fields.
    let mut connection = serde_json::to_value(connection).unwrap();
    for key in [
        "password",
        "privateKeyPassphrase",
        "knownHostsFile",
        "proxyCommand",
        "proxyJump",
        "agentSocket",
        "x11TargetHost",
        "x11AuthCookie",
    ] {
        connection
            .as_object_mut()
            .unwrap()
            .entry(key)
            .or_insert(Value::Null);
    }
    let config = json!({
        "schema_version": 1,
        "contract": "ianvs-session-config-v1",
        "session_id": "linux-loopback-zmodem",
        "display_name": "Linux loopback ZMODEM",
        "client_capabilities": {"zmodem": true},
        "config": {
            "launch": TerminalProfileLaunch::default(),
            "connection": connection,
            "terminal": TerminalProfileTerminal::default(),
            "shellIntegration": TerminalShellIntegration { enabled: false, ..<_>::default() },
            "appearance": TerminalProfileAppearance::default(),
            "interaction": TerminalProfileInteraction::default(),
        }
    });
    SessionGuard(session::create_session_v1(&config.to_string()).unwrap())
}

fn payload(size: usize, salt: usize) -> Vec<u8> {
    (0..size)
        .map(|index| ((index + salt) % 256) as u8)
        .collect()
}

fn quote(path: &Path) -> String {
    format!("'{}'", path.to_string_lossy().replace('\'', "'\\''"))
}

fn send_command(session_id: u64, command: &str) {
    session::write_session(session_id, format!("stty -echo; {command}\n").as_bytes()).unwrap();
}

fn event(session_id: u64, kind: &str) -> Value {
    let deadline = Instant::now() + TIMEOUT;
    while Instant::now() < deadline {
        let events: Vec<Value> =
            serde_json::from_str(&session::poll_events(session_id).unwrap()).unwrap();
        for event in events {
            assert_ne!(event["kind"], "zmodem_failed", "{event}");
            if event["kind"] == kind {
                return event;
            }
        }
        thread::sleep(Duration::from_millis(10));
    }
    panic!("timed out waiting for {kind}");
}

fn request(session_id: u64, operation: &str, payload: Value) {
    let deadline = Instant::now() + TIMEOUT;
    loop {
        match session::request_session(session_id, operation, &payload) {
            Err(session::SessionError::Zmodem(reason))
                if reason == "zmodem_transport_busy" && Instant::now() < deadline =>
            {
                thread::sleep(Duration::from_millis(10));
            }
            result => {
                let response: Value = serde_json::from_str(&result.unwrap().unwrap()).unwrap();
                assert_eq!(response["accepted"], true, "{response}");
                return;
            }
        }
    }
}

fn marker(session_id: u64, expected: &str) {
    let deadline = Instant::now() + TIMEOUT;
    while Instant::now() < deadline {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap()
            && frame.contains(expected)
        {
            return;
        }
        thread::sleep(Duration::from_millis(10));
    }
    panic!("shell did not resume after transfer: {expected}");
}

fn zmodem_roundtrip(root: &Path, connection: TerminalProfileConnection) {
    let source = root.join("zmodem-source");
    let download = root.join("zmodem-download");
    let remote = root.join("zmodem-remote");
    for directory in [&source, &download, &remote] {
        fs::create_dir(directory).unwrap();
    }
    let fixtures = [("first.bin", 131_071, 3), ("second.bin", 65_539, 17)];
    for (name, size, salt) in fixtures {
        let file = source.join(name);
        fs::write(&file, payload(size, salt)).unwrap();
        File::options()
            .write(true)
            .open(file)
            .unwrap()
            .set_times(
                FileTimes::new().set_modified(UNIX_EPOCH + Duration::from_secs(1_700_000_123)),
            )
            .unwrap();
    }
    let receive = terminal(connection.clone());
    send_command(
        receive.0,
        &format!(
            "cd {} && {} -e first.bin second.bin; printf 'IANVS_RECEIVE_%s\\n' DONE",
            quote(&source),
            quote(Path::new(&required_env("IANVS_LOOPBACK_SZ"))),
        ),
    );
    let offer = event(receive.0, "zmodem_file_offer");
    assert_eq!(offer["payload"]["direction"], "receive");
    request(
        receive.0,
        "terminal.zmodem.accept_receive",
        json!({"transferId": offer["payload"]["transferId"], "destination": download}),
    );
    let completed = event(receive.0, "zmodem_completed");
    assert_eq!(completed["payload"]["completedFiles"], 2);
    marker(receive.0, "IANVS_RECEIVE_DONE");
    drop(receive);
    let send = terminal(connection);
    send_command(
        send.0,
        &format!(
            "cd {} && {} -bye; printf 'IANVS_SEND_%s\\n' DONE",
            quote(&remote),
            quote(Path::new(&required_env("IANVS_LOOPBACK_RZ"))),
        ),
    );
    let detected = event(send.0, "zmodem_detected");
    assert_eq!(detected["payload"]["direction"], "send");
    request(
        send.0,
        "terminal.zmodem.accept_send",
        json!({
            "transferId": detected["payload"]["transferId"],
            "files": [source.join("first.bin"), source.join("second.bin")],
        }),
    );
    let completed = event(send.0, "zmodem_completed");
    assert_eq!(completed["payload"]["completedFiles"], 2);
    marker(send.0, "IANVS_SEND_DONE");
    drop(send);
    for directory in [&download, &remote] {
        for (name, size, salt) in fixtures {
            let file = directory.join(name);
            assert_eq!(fs::read(&file).unwrap(), payload(size, salt));
            assert_eq!(
                fs::metadata(&file)
                    .unwrap()
                    .modified()
                    .unwrap()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs(),
                1_700_000_123
            );
        }
    }
    eprintln!(
        "linux-loopback: bidirectional two-file GNU lrzsz batches, exact bytes/mtime, and shell continuation passed"
    );
}
