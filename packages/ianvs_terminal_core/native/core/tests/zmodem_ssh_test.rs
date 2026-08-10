#![cfg(any(target_os = "macos", target_os = "linux"))]

use ianvs_core::model::{
    TerminalEmulation, TerminalProfile, TerminalProfileAppearance, TerminalProfileConnection,
    TerminalProfileInteraction, TerminalProfileLaunch, TerminalProfileTerminal,
    TerminalShellIntegration,
};
use ianvs_core::session;
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::fs::{File, FileTimes};
use std::path::PathBuf;
use std::process::Command;
use std::thread;
use std::time::{Duration, UNIX_EPOCH};
use tempfile::tempdir;

const WAIT_ATTEMPTS: usize = 1_800;

struct SessionGuard(u64);

impl Drop for SessionGuard {
    fn drop(&mut self) {
        let _ = session::close_session(self.0);
    }
}

fn required_env(name: &str) -> String {
    env::var(name).unwrap_or_else(|_| {
        panic!(
            "{name} is required; run this ignored test only against the dedicated tools/zmodem_e2e fixture"
        )
    })
}

fn ssh_profile(id: &str, remote_command: &str) -> TerminalProfile {
    let target = required_env("IANVS_ZMODEM_SSH_TARGET");
    let port = required_env("IANVS_ZMODEM_SSH_PORT");
    let identity = required_env("IANVS_ZMODEM_SSH_IDENTITY");
    let program = env::var("IANVS_ZMODEM_SSH_BIN").unwrap_or_else(|_| "/usr/bin/ssh".to_string());
    TerminalProfile {
        id: id.to_string(),
        name: id.to_string(),
        connection: TerminalProfileConnection::default(),
        launch: TerminalProfileLaunch {
            program,
            args: vec![
                "-tt".to_string(),
                "-F".to_string(),
                "/dev/null".to_string(),
                "-o".to_string(),
                "BatchMode=yes".to_string(),
                "-o".to_string(),
                "StrictHostKeyChecking=no".to_string(),
                "-o".to_string(),
                "UserKnownHostsFile=/dev/null".to_string(),
                "-o".to_string(),
                "LogLevel=ERROR".to_string(),
                "-e".to_string(),
                "none".to_string(),
                "-i".to_string(),
                identity,
                "-p".to_string(),
                port,
                target,
                remote_command.to_string(),
            ],
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

fn start(profile: TerminalProfile) -> SessionGuard {
    let config = serde_json::json!({
        "schema_version": 1,
        "contract": "ianvs-session-config-v1",
        "session_id": profile.id,
        "display_name": profile.name,
        "client_capabilities": {"zmodem": true},
        "config": {
            "launch": profile.launch,
            "terminal": profile.terminal,
            "shellIntegration": profile.shell_integration,
            "appearance": profile.appearance,
            "interaction": profile.interaction,
        },
    });
    let id = session::create_session_v1(&config.to_string()).unwrap();
    SessionGuard(id)
}

fn assert_dedicated_fixture() {
    let profile = ssh_profile(
        "zmodem-ssh-fixture-probe",
        "set -eu; test \"$(cat /etc/ianvs-zmodem-e2e-fixture)\" = 'snapshot=20260801T000000Z;lrzsz=0.12.21-11build1;openssh-server=1:9.6p1-3ubuntu13.18'; test \"$(dpkg-query -W -f='${Version}' lrzsz)\" = '0.12.21-11build1'; test \"$(dpkg-query -W -f='${Version}' openssh-server)\" = '1:9.6p1-3ubuntu13.18'; test \"$(rz --version)\" = 'rz (GNU lrzsz) 0.12.21rc'; test \"$(sz --version)\" = 'sz (lrzsz) 0.12.21rc'",
    );
    let output = Command::new(&profile.launch.program)
        .args(&profile.launch.args)
        .output()
        .expect("dedicated ZMODEM SSH fixture probe should start");
    assert!(
        output.status.success(),
        "SSH target is unavailable or is not the dedicated tools/zmodem_e2e fixture: {output:?}"
    );
}

fn wait_for_event(session_id: u64, kind: &str) -> serde_json::Value {
    let mut observed = Vec::new();
    for _ in 0..WAIT_ATTEMPTS {
        let raw = session::poll_events(session_id).unwrap();
        let batch: serde_json::Value = serde_json::from_str(&raw).unwrap();
        if let Some(events) = batch.as_array() {
            for event in events.iter().filter(|event| {
                event["kind"]
                    .as_str()
                    .is_some_and(|kind| kind.starts_with("zmodem_") && kind != "zmodem_progress")
            }) {
                eprintln!(
                    "zmodem-e2e: event {} {}",
                    event["kind"].as_str().unwrap_or("unknown"),
                    event["payload"]
                );
            }
            observed.extend(events.iter().cloned());
            if let Some(event) = events.iter().find(|event| event["kind"] == kind) {
                return event.clone();
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!(
        "timed out waiting for {kind}; observed {}",
        serde_json::to_string_pretty(&observed).unwrap()
    );
}

fn wait_for_zmodem_terminal_events(session_id: u64, kind: &str) -> Vec<serde_json::Value> {
    let mut observed = Vec::new();
    for _ in 0..WAIT_ATTEMPTS {
        let raw = session::poll_events(session_id).unwrap();
        let batch: serde_json::Value = serde_json::from_str(&raw).unwrap();
        if let Some(events) = batch.as_array() {
            for event in events.iter().filter(|event| {
                event["kind"].as_str().is_some_and(|event_kind| {
                    event_kind.starts_with("zmodem_") && event_kind != "zmodem_progress"
                })
            }) {
                eprintln!(
                    "zmodem-e2e: event {} {}",
                    event["kind"].as_str().unwrap_or("unknown"),
                    event["payload"]
                );
                observed.push(event.clone());
            }
            if events.iter().any(|event| event["kind"] == kind) {
                return observed;
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!(
        "timed out waiting for {kind}; observed {}",
        serde_json::to_string_pretty(&observed).unwrap()
    );
}

fn wait_for_frame_texts(session_id: u64, needles: &[String]) {
    let mut observed = vec![false; needles.len()];
    for _ in 0..WAIT_ATTEMPTS {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            for (index, needle) in needles.iter().enumerate() {
                observed[index] |= frame.contains(needle);
            }
            if observed.iter().all(|value| *value) {
                return;
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    let missing = needles
        .iter()
        .zip(observed)
        .filter_map(|(needle, found)| (!found).then_some(needle))
        .collect::<Vec<_>>();
    panic!("timed out waiting for terminal text markers {missing:?}");
}

fn md5(path: &std::path::Path) -> String {
    #[cfg(target_os = "macos")]
    let output = Command::new("/sbin/md5").arg("-q").arg(path).output();
    #[cfg(target_os = "linux")]
    let output = Command::new("/usr/bin/md5sum").arg(path).output();
    let output = output.expect("platform MD5 tool should start");
    assert!(output.status.success(), "md5 failed: {output:?}");
    String::from_utf8(output.stdout)
        .unwrap()
        .split_whitespace()
        .next()
        .unwrap()
        .to_string()
}

fn modification_time_seconds(path: &std::path::Path) -> u64 {
    fs::metadata(path)
        .unwrap()
        .modified()
        .unwrap()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

const RECEIVE_REMOTE_COMMAND: &str = r#"set -eu; test -f /etc/ianvs-zmodem-e2e-fixture; work=$(mktemp -d /tmp/ianvs-zmodem-receive.XXXXXX); cleanup() { rm -rf -- "$work"; }; trap cleanup EXIT HUP INT TERM; first="$work/ianvs-zmodem-receive-a.bin"; second="$work/ianvs-zmodem-receive-b.bin"; dd if=/dev/urandom of="$first" bs=1048576 count=4 status=none; dd if=/dev/urandom of="$second" bs=262144 count=3 status=none; touch -d @1700000123 "$first"; touch -d @1700000789 "$second"; first_md5=$(md5sum "$first" | cut -d' ' -f1); first_size=$(stat -c %s "$first"); first_mtime=$(stat -c %Y "$first"); second_md5=$(md5sum "$second" | cut -d' ' -f1); second_size=$(stat -c %s "$second"); second_mtime=$(stat -c %Y "$second"); cd "$work"; sz -e "$first" "$second"; cleanup; trap - EXIT HUP INT TERM; printf '\nIANVS_ZMODEM_RECEIVE_FILE_MD5=%s_SIZE=%s_MTIME=%s_DONE\n' "$first_md5" "$first_size" "$first_mtime"; printf 'IANVS_ZMODEM_RECEIVE_FILE_MD5=%s_SIZE=%s_MTIME=%s_DONE\n' "$second_md5" "$second_size" "$second_mtime""#;

const SEND_REMOTE_COMMAND: &str = r#"set -eu; test -f /etc/ianvs-zmodem-e2e-fixture; work=$(mktemp -d /tmp/ianvs-zmodem-send.XXXXXX); cleanup() { rm -rf -- "$work"; }; trap cleanup EXIT HUP INT TERM; primary="$work/__IANVS_PRIMARY_BASENAME__"; companion="$work/ianvs-zmodem-batch-companion.bin"; cd "$work"; rz -bye; count=$(find "$work" -mindepth 1 -maxdepth 1 -type f -printf x | wc -c); test "$count" -eq 2; test -f "$primary"; test -f "$companion"; primary_md5=$(md5sum -- "$primary" | cut -d' ' -f1); primary_size=$(stat -c %s -- "$primary"); primary_mtime=$(stat -c %Y -- "$primary"); companion_md5=$(md5sum -- "$companion" | cut -d' ' -f1); companion_size=$(stat -c %s -- "$companion"); companion_mtime=$(stat -c %Y -- "$companion"); cleanup; trap - EXIT HUP INT TERM; printf 'IANVS_ZMODEM_SEND_A_MD5=%s_SIZE=%s_MTIME=%s_DONE\n' "$primary_md5" "$primary_size" "$primary_mtime"; printf 'IANVS_ZMODEM_SEND_B_MD5=%s_SIZE=%s_MTIME=%s_DONE\n' "$companion_md5" "$companion_size" "$companion_mtime""#;

fn send_remote_command(primary_basename: &str) -> String {
    assert!(
        !primary_basename.is_empty()
            && primary_basename != "ianvs-zmodem-batch-companion.bin"
            && primary_basename
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-')),
        "IANVS_ZMODEM_SSH_SEND_FILE must have a distinct shell-safe ASCII basename"
    );
    SEND_REMOTE_COMMAND.replace("__IANVS_PRIMARY_BASENAME__", primary_basename)
}

#[test]
#[ignore = "requires the dedicated Colima/OpenSSH fixture; see tools/zmodem_e2e/README.md"]
fn zmodem_round_trips_files_over_real_openssh_pty() {
    assert_dedicated_fixture();
    eprintln!("zmodem-e2e: receive start");
    let receive_profile = ssh_profile("zmodem-ssh-receive", RECEIVE_REMOTE_COMMAND);

    let receive_directory = tempdir().unwrap();
    let receive_session = start(receive_profile);
    let offer = wait_for_event(receive_session.0, "zmodem_file_offer");
    eprintln!("zmodem-e2e: receive offer");
    assert_eq!(offer["payload"]["direction"], "receive");
    assert_eq!(offer["payload"]["filename"], "ianvs-zmodem-receive-a.bin");
    assert_eq!(
        offer["payload"]["modificationTimeSeconds"],
        1_700_000_123_u64
    );
    let transfer_id = offer["payload"]["transferId"].as_str().unwrap();
    let response = session::request_session_json(
        receive_session.0,
        &serde_json::json!({
            "kind": "terminal.zmodem.accept_receive",
            "transferId": transfer_id,
            "destination": receive_directory.path(),
        })
        .to_string(),
    )
    .unwrap();
    assert_eq!(
        response
            .as_deref()
            .and_then(|raw| serde_json::from_str::<serde_json::Value>(raw).ok())
            .and_then(|value| value["accepted"].as_bool()),
        Some(true)
    );
    eprintln!("zmodem-e2e: receive accepted");
    let receive_events = wait_for_zmodem_terminal_events(receive_session.0, "zmodem_completed");
    let completed = receive_events
        .iter()
        .find(|event| event["kind"] == "zmodem_completed")
        .unwrap();
    eprintln!("zmodem-e2e: receive completed");
    assert_eq!(completed["payload"]["direction"], "receive");
    assert_eq!(completed["payload"]["completedFiles"], 2);
    assert!(receive_events.iter().any(|event| {
        event["kind"] == "zmodem_file_offer"
            && event["payload"]["filename"] == "ianvs-zmodem-receive-b.bin"
            && event["payload"]["modificationTimeSeconds"] == 1_700_000_789_u64
    }));
    let mut receive_markers = Vec::new();
    for (name, size, mtime) in [
        ("ianvs-zmodem-receive-a.bin", 4 * 1024 * 1024, 1_700_000_123),
        ("ianvs-zmodem-receive-b.bin", 3 * 262_144, 1_700_000_789),
    ] {
        let received_path = receive_directory.path().join(name);
        assert_eq!(fs::metadata(&received_path).unwrap().len(), size);
        let received_md5 = md5(&received_path);
        let received_size = fs::metadata(&received_path).unwrap().len();
        let received_mtime = modification_time_seconds(&received_path);
        assert_eq!(received_mtime, mtime);
        receive_markers.push(format!(
            "IANVS_ZMODEM_RECEIVE_FILE_MD5={received_md5}_SIZE={received_size}_MTIME={received_mtime}_DONE"
        ));
        eprintln!(
            "zmodem-e2e: receive verified name={name} md5={received_md5} size={received_size} mtime={received_mtime}"
        );
    }
    wait_for_frame_texts(receive_session.0, &receive_markers);
    drop(receive_session);

    let send_path = PathBuf::from(required_env("IANVS_ZMODEM_SSH_SEND_FILE"));
    assert!(
        send_path.is_absolute() && send_path.is_file(),
        "IANVS_ZMODEM_SSH_SEND_FILE must name an absolute regular file"
    );
    let expected_md5 = md5(&send_path);
    let expected_size = fs::metadata(&send_path).unwrap().len();
    let expected_mtime = modification_time_seconds(&send_path);
    let expected_name = send_path
        .file_name()
        .and_then(|name| name.to_str())
        .expect("send fixture must have a UTF-8 basename")
        .to_string();
    let companion_directory = tempdir().unwrap();
    let companion_path = companion_directory
        .path()
        .join("ianvs-zmodem-batch-companion.bin");
    fs::write(&companion_path, b"ianvs-zmodem-batch-companion\n").unwrap();
    let companion_mtime = UNIX_EPOCH + Duration::from_secs(1_700_000_789);
    File::options()
        .write(true)
        .open(&companion_path)
        .unwrap()
        .set_times(FileTimes::new().set_modified(companion_mtime))
        .unwrap();
    let companion_md5 = md5(&companion_path);
    let companion_size = fs::metadata(&companion_path).unwrap().len();
    let send_remote_command = send_remote_command(&expected_name);
    let send_profile = ssh_profile("zmodem-ssh-send", &send_remote_command);
    eprintln!("zmodem-e2e: send start");
    let send_session = start(send_profile);
    let detected = wait_for_event(send_session.0, "zmodem_detected");
    eprintln!("zmodem-e2e: send detected");
    assert_eq!(detected["payload"]["direction"], "send");
    let transfer_id = detected["payload"]["transferId"].as_str().unwrap();
    let response = session::request_session_json(
        send_session.0,
        &serde_json::json!({
            "kind": "terminal.zmodem.accept_send",
            "transferId": transfer_id,
            "files": [send_path, companion_path],
        })
        .to_string(),
    )
    .unwrap();
    assert_eq!(
        response
            .as_deref()
            .and_then(|raw| serde_json::from_str::<serde_json::Value>(raw).ok())
            .and_then(|value| value["accepted"].as_bool()),
        Some(true)
    );
    eprintln!("zmodem-e2e: send accepted");
    let send_events = wait_for_zmodem_terminal_events(send_session.0, "zmodem_completed");
    let completed = send_events
        .iter()
        .find(|event| event["kind"] == "zmodem_completed")
        .unwrap();
    eprintln!("zmodem-e2e: send completed");
    assert_eq!(completed["payload"]["direction"], "send");
    assert_eq!(completed["payload"]["completedFiles"], 2);
    assert!(send_events.iter().any(|event| {
        event["kind"] == "zmodem_file_completed"
            && event["payload"]["filename"] == expected_name
            && event["payload"]["size"] == expected_size
    }));
    assert!(send_events.iter().any(|event| {
        event["kind"] == "zmodem_file_completed"
            && event["payload"]["filename"] == "ianvs-zmodem-batch-companion.bin"
            && event["payload"]["size"] == companion_size
    }));
    wait_for_frame_texts(
        send_session.0,
        &[
            format!(
                "IANVS_ZMODEM_SEND_A_MD5={expected_md5}_SIZE={expected_size}_MTIME={expected_mtime}_DONE"
            ),
            format!(
                "IANVS_ZMODEM_SEND_B_MD5={companion_md5}_SIZE={companion_size}_MTIME=1700000789_DONE"
            ),
        ],
    );
    eprintln!(
        "zmodem-e2e: send verified first_md5={expected_md5} first_size={expected_size} first_mtime={expected_mtime} second_md5={companion_md5} second_size={companion_size} second_mtime=1700000789"
    );
}
