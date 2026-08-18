#![cfg(any(target_os = "macos", target_os = "linux"))]

use ianvs_core::model::{
    TerminalConnectionType, TerminalProfileConnection, TerminalSshAuthMethod,
    TerminalSshHostKeyPolicy, TerminalSshJumpProfile, TerminalSshPortForward,
    TerminalSshPortForwardKind,
};
use ianvs_core::ssh::{
    SftpOperation, SshAuthClient, SshHostKeyPrompt, SshHostKeyPromptReason, SshRuntime, spawn_ssh,
};
use std::env;
use std::fs;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
#[cfg(unix)]
use std::os::unix::net::UnixListener;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const TEST_USER: &str = "ianvs";
const TEST_PASSWORD: &str = "ianvs-e2e-password";
const TEST_OTP: &str = "654321";
const SESSION_TIMEOUT: Duration = Duration::from_secs(30);
const FAILURE_TIMEOUT: Duration = Duration::from_secs(8);
const PROMPT_TIMEOUT: Duration = Duration::from_secs(8);
const X11_REAL_COOKIE: [u8; 16] = [
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
];

fn required_env(name: &str) -> String {
    env::var(name).unwrap_or_else(|_| {
        panic!("{name} is required; run this ignored test through tools/ssh_e2e/run.sh")
    })
}

fn required_port(name: &str) -> u16 {
    required_env(name)
        .parse::<u16>()
        .unwrap_or_else(|error| panic!("{name} must be a valid TCP port: {error}"))
}

fn base_connection(port: u16) -> TerminalProfileConnection {
    TerminalProfileConnection {
        connection_type: TerminalConnectionType::Ssh,
        host: "127.0.0.1".to_string(),
        user: TEST_USER.to_string(),
        port,
        host_key_policy: TerminalSshHostKeyPolicy::Insecure,
        connect_timeout_seconds: 15,
        ..<_>::default()
    }
}

fn password_connection(port: u16) -> TerminalProfileConnection {
    TerminalProfileConnection {
        auth: TerminalSshAuthMethod::Password,
        password: Some(TEST_PASSWORD.to_string()),
        ..base_connection(port)
    }
}

fn public_key_connection(host: String, port: u16, identity: &str) -> TerminalProfileConnection {
    TerminalProfileConnection {
        host,
        port,
        auth: TerminalSshAuthMethod::PublicKey,
        private_keys: vec![identity.to_string()],
        ..base_connection(port)
    }
}

fn run_shell_probe(connection: TerminalProfileConnection, expected_role: &str) {
    let runtime = spawn_ssh(connection, 24, 100).expect("native SSH transport should start");
    run_shell_probe_runtime(runtime, expected_role);
}

fn run_sftp_probe(connection: TerminalProfileConnection, expected_role: &str) {
    let runtime = spawn_ssh(connection, 24, 100).expect("native SSH transport should start");
    let request = runtime
        .sftp
        .start_list_directory("/".to_string())
        .expect("SFTP directory request should enqueue");
    let (completion_sender, completion_receiver) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let _ = completion_sender.send(request.blocking_recv());
    });
    let listing = completion_receiver
        .recv_timeout(SESSION_TIMEOUT)
        .expect("SFTP directory request should complete")
        .expect("SFTP response channel should remain open")
        .expect("SFTP root directory should be readable");
    assert_eq!(listing.path, "/");
    assert!(
        !listing.entries.is_empty(),
        "SFTP fixture root should contain entries"
    );
    assert!(
        listing
            .entries
            .iter()
            .all(|entry| entry.name != "." && entry.name != ".."),
        "SFTP listings must omit dot entries"
    );
    let scratch = tempfile::tempdir().expect("SFTP local scratch directory");
    let upload_path = scratch.path().join("upload.txt");
    let download_path = scratch.path().join("download.txt");
    fs::write(&upload_path, b"ianvs-sftp-round-trip\n").expect("write SFTP upload fixture");
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock should follow Unix epoch")
        .as_nanos();
    let remote_directory = format!("/tmp/ianvs-sftp-e2e-{nonce}");
    let remote_file = format!("{remote_directory}/round-trip.txt");
    run_sftp_operation(
        &runtime,
        SftpOperation::CreateDirectory {
            path: remote_directory.clone(),
        },
        "create remote directory",
    );
    run_sftp_operation(
        &runtime,
        SftpOperation::UploadFile {
            local_path: upload_path.to_string_lossy().into_owned(),
            remote_path: remote_file.clone(),
        },
        "upload remote file",
    );
    run_sftp_operation(
        &runtime,
        SftpOperation::DownloadFile {
            remote_path: remote_file.clone(),
            local_path: download_path.to_string_lossy().into_owned(),
        },
        "download remote file",
    );
    assert_eq!(
        fs::read(&download_path).expect("read SFTP download fixture"),
        b"ianvs-sftp-round-trip\n"
    );
    fs::write(&upload_path, b"ianvs-sftp-overwrite\n").expect("rewrite SFTP upload fixture");
    run_sftp_operation(
        &runtime,
        SftpOperation::UploadFile {
            local_path: upload_path.to_string_lossy().into_owned(),
            remote_path: remote_file.clone(),
        },
        "atomically overwrite remote file",
    );
    run_sftp_operation(
        &runtime,
        SftpOperation::DownloadFile {
            remote_path: remote_file.clone(),
            local_path: download_path.to_string_lossy().into_owned(),
        },
        "download overwritten remote file",
    );
    assert_eq!(
        fs::read(&download_path).expect("read overwritten SFTP fixture"),
        b"ianvs-sftp-overwrite\n"
    );
    run_sftp_operation(
        &runtime,
        SftpOperation::DeleteEntry {
            path: remote_file,
            is_directory: false,
        },
        "delete remote file",
    );
    run_sftp_operation(
        &runtime,
        SftpOperation::DeleteEntry {
            path: remote_directory,
            is_directory: true,
        },
        "delete remote directory",
    );
    eprintln!("ssh-e2e: SFTP root accepted through the active SSH transport");
    run_shell_probe_runtime(runtime, expected_role);
}

fn run_sftp_operation(runtime: &SshRuntime, operation: SftpOperation, label: &str) {
    let request = runtime
        .sftp
        .start_operation(operation)
        .unwrap_or_else(|error| panic!("{label} should enqueue: {error}"));
    let (completion_sender, completion_receiver) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let _ = completion_sender.send(request.blocking_recv());
    });
    completion_receiver
        .recv_timeout(SESSION_TIMEOUT)
        .unwrap_or_else(|error| panic!("{label} should complete: {error}"))
        .unwrap_or_else(|error| panic!("{label} response channel should remain open: {error}"))
        .unwrap_or_else(|error| panic!("{label} should succeed: {error}"));
}

fn run_shell_probe_runtime(runtime: SshRuntime, expected_role: &str) {
    let SshRuntime {
        master: _,
        mut reader,
        mut writer,
        mut child,
        auth: _,
        sftp: _,
    } = runtime;
    let (output_sender, output_receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut output = Vec::new();
        let result = reader.read_to_end(&mut output).map(|_| output);
        let _ = output_sender.send(result);
    });

    writer
        .write_all(
            b"role=$(cat /etc/ianvs-ssh-e2e-role); user=$(id -un); printf 'IANVS_SSH_E2E_RESULT=%s:%s\\n' \"$role\" \"$user\"; exit\n",
        )
        .expect("probe command should be queued");
    writer.flush().expect("probe command should flush");
    drop(writer);

    let output = match output_receiver.recv_timeout(SESSION_TIMEOUT) {
        Ok(Ok(output)) => output,
        Ok(Err(error)) => panic!("SSH output reader failed: {error}"),
        Err(error) => {
            let _ = child.kill();
            panic!("SSH probe timed out: {error}");
        }
    };
    let status = child.wait().expect("SSH child status should be available");
    let output = String::from_utf8_lossy(&output);
    assert!(
        status.success(),
        "SSH probe exited with {status:?}; output:\n{output}"
    );
    let expected = format!("IANVS_SSH_E2E_RESULT={expected_role}:{TEST_USER}");
    assert!(
        output.contains(&expected),
        "SSH probe did not produce {expected:?}; output:\n{output}"
    );
    assert!(
        !output.contains("Ianvs SSH:"),
        "native SSH transport reported an error:\n{output}"
    );
    eprintln!("ssh-e2e: {expected_role} accepted through native Rust transport");
}

fn wait_for_host_key_prompt(auth: &SshAuthClient) -> SshHostKeyPrompt {
    let deadline = Instant::now() + PROMPT_TIMEOUT;
    loop {
        if let Some(prompt) = auth.take_host_key_prompts().pop() {
            return prompt;
        }
        assert!(Instant::now() < deadline, "SSH host-key prompt timed out");
        thread::sleep(Duration::from_millis(10));
    }
}

fn assert_failed_session(
    runtime: SshRuntime,
    label: &str,
    expected_error_fragments: &[&str],
) -> String {
    let started = Instant::now();
    let SshRuntime {
        master: _,
        mut reader,
        writer: _,
        mut child,
        auth: _,
        sftp: _,
    } = runtime;
    let (output_sender, output_receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut output = Vec::new();
        let result = reader.read_to_end(&mut output).map(|_| output);
        let _ = output_sender.send(result);
    });

    let status = loop {
        if let Some(status) = child.try_wait().expect("failed SSH child status") {
            break status;
        }
        if started.elapsed() >= FAILURE_TIMEOUT {
            let _ = child.kill();
            panic!("{label} did not fail within {FAILURE_TIMEOUT:?}");
        }
        thread::sleep(Duration::from_millis(10));
    };
    let output = output_receiver
        .recv_timeout(Duration::from_secs(2))
        .unwrap_or_else(|error| panic!("{label} output did not close after failure: {error}"))
        .unwrap_or_else(|error| panic!("{label} output reader failed: {error}"));
    let output = String::from_utf8_lossy(&output).into_owned();
    assert!(
        !status.success(),
        "{label} unexpectedly succeeded:\n{output}"
    );
    assert!(
        output.contains("Ianvs SSH:"),
        "{label} did not report a native SSH failure:\n{output}"
    );
    assert!(
        expected_error_fragments
            .iter()
            .all(|fragment| output.contains(fragment)),
        "{label} did not report every required fragment {expected_error_fragments:?}:\n{output}"
    );
    assert!(
        !output.contains("\r\nConnected to "),
        "{label} reported a connection before failing:\n{output}"
    );
    eprintln!(
        "ssh-e2e: {label} rejected in {:.2?}: {}",
        started.elapsed(),
        output.trim()
    );
    output
}

fn next_auth_challenge(auth: &SshAuthClient, label: &str) -> ianvs_core::ssh::SshAuthPrompt {
    let deadline = Instant::now() + PROMPT_TIMEOUT;
    loop {
        let mut prompts = auth.take_prompts();
        if !prompts.is_empty() {
            assert_eq!(
                prompts.len(),
                1,
                "{label} unexpectedly queued multiple authentication challenges"
            );
            return prompts.remove(0);
        }
        assert!(
            Instant::now() < deadline,
            "{label} did not issue an authentication challenge within {PROMPT_TIMEOUT:?}"
        );
        thread::sleep(Duration::from_millis(10));
    }
}

fn reserve_tcp_ports(count: usize) -> (Vec<TcpListener>, Vec<u16>) {
    let mut reservations = Vec::with_capacity(count);
    let mut ports = Vec::with_capacity(count);
    for _ in 0..count {
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .expect("ephemeral TCP port reservation should bind");
        let port = listener
            .local_addr()
            .expect("ephemeral listener should have an address")
            .port();
        assert!(
            !ports.contains(&port),
            "OS returned a duplicate reserved port"
        );
        reservations.push(listener);
        ports.push(port);
    }
    (reservations, ports)
}

fn connect_with_retry(port: u16) -> TcpStream {
    let deadline = Instant::now() + SESSION_TIMEOUT;
    loop {
        match TcpStream::connect(("127.0.0.1", port)) {
            Ok(stream) => {
                stream
                    .set_read_timeout(Some(Duration::from_secs(10)))
                    .expect("read timeout should apply");
                stream
                    .set_write_timeout(Some(Duration::from_secs(10)))
                    .expect("write timeout should apply");
                return stream;
            }
            Err(error) if Instant::now() < deadline => {
                let _ = error;
                thread::sleep(Duration::from_millis(25));
            }
            Err(error) => panic!("forwarding listener on port {port} did not start: {error}"),
        }
    }
}

fn assert_ssh_banner(mut stream: TcpStream, label: &str) {
    let mut banner = [0_u8; 4];
    stream
        .read_exact(&mut banner)
        .unwrap_or_else(|error| panic!("{label} did not return an SSH banner: {error}"));
    assert_eq!(&banner, b"SSH-", "{label} reached the wrong target");
}

fn start_tcp_sink(label: &'static str) -> (u16, mpsc::Receiver<Vec<u8>>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).expect("TCP sink should bind");
    let port = listener.local_addr().expect("TCP sink address").port();
    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        let result = (|| {
            let (mut stream, _) = listener.accept()?;
            stream.set_read_timeout(Some(Duration::from_secs(15)))?;
            let mut bytes = Vec::new();
            stream.read_to_end(&mut bytes)?;
            Ok::<_, std::io::Error>(bytes)
        })();
        let _ = sender.send(result.unwrap_or_else(|error| panic!("{label} sink failed: {error}")));
    });
    (port, receiver)
}

fn run_multi_round_otp_probe(port: u16) {
    let connection = TerminalProfileConnection {
        auth: TerminalSshAuthMethod::KeyboardInteractive,
        ..base_connection(port)
    };
    let runtime = spawn_ssh(connection, 24, 100).expect("OTP SSH transport should start");
    let auth = runtime.auth.clone();
    let responder = thread::spawn(move || respond_to_otp_rounds(auth));
    let SshRuntime {
        master: _,
        mut reader,
        mut writer,
        mut child,
        auth: _,
        sftp: _,
    } = runtime;
    let (output_sender, output_receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut output = Vec::new();
        let result = reader.read_to_end(&mut output).map(|_| output);
        let _ = output_sender.send(result);
    });
    writer
        .write_all(b"printf 'IANVS_SSH_E2E_RESULT=otp:%s\\n' \"$(id -un)\"; exit\n")
        .expect("OTP probe command should queue");
    drop(writer);
    let rounds = responder.join().expect("OTP responder should finish");
    assert_eq!(rounds, vec!["Fixture password:", "One-time password:"]);
    let output = output_receiver
        .recv_timeout(SESSION_TIMEOUT)
        .expect("OTP output should arrive")
        .expect("OTP output reader should succeed");
    let status = child.wait().expect("OTP child status should be available");
    let output = String::from_utf8_lossy(&output);
    assert!(status.success(), "OTP SSH session failed:\n{output}");
    assert!(output.contains("IANVS_SSH_E2E_RESULT=otp:ianvs"));
    eprintln!("ssh-e2e: two distinct keyboard-interactive OTP rounds accepted");
}

fn respond_to_otp_rounds(auth: SshAuthClient) -> Vec<String> {
    let deadline = Instant::now() + SESSION_TIMEOUT;
    let mut observed = Vec::new();
    while observed.len() < 2 && Instant::now() < deadline {
        for challenge in auth.take_prompts() {
            assert_eq!(challenge.prompts.len(), 1);
            let prompt = challenge.prompts[0].prompt.trim().to_string();
            let response = match prompt.as_str() {
                "Fixture password:" => TEST_PASSWORD,
                "One-time password:" => TEST_OTP,
                _ => panic!("unexpected OTP prompt: {prompt:?}"),
            };
            assert!(auth.respond(challenge.challenge_id, vec![response.to_string()]));
            observed.push(prompt);
        }
        thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(observed.len(), 2, "server did not issue two OTP rounds");
    observed
}

#[cfg(unix)]
fn run_forwarding_probe(port: u16, identity: &str) {
    // Hold all host listeners until immediately before spawn_ssh binds them.
    // This avoids the old three independent bind-and-drop reservation windows.
    let (port_reservations, reserved_ports) = reserve_tcp_ports(3);
    let local_port = reserved_ports[0];
    let rejected_local_port = reserved_ports[1];
    let socks_port = reserved_ports[2];
    let remote_port = 32123;
    let (remote_target_port, remote_receiver) = start_tcp_sink("remote forward");
    let (x11_target_port, x11_receiver) = start_tcp_sink("X11 forward");
    let agent_directory = tempfile::tempdir().expect("agent socket tempdir");
    let agent_path = agent_directory.path().join("agent.sock");
    let agent_listener = UnixListener::bind(&agent_path).expect("agent socket should bind");
    agent_listener
        .set_nonblocking(false)
        .expect("agent listener should be blocking");
    let (agent_sender, agent_receiver) = mpsc::channel();
    thread::spawn(move || {
        let (mut stream, _) = agent_listener
            .accept()
            .expect("agent channel should connect");
        stream
            .set_read_timeout(Some(Duration::from_secs(15)))
            .expect("agent timeout should apply");
        let mut bytes = Vec::new();
        stream
            .read_to_end(&mut bytes)
            .expect("agent bytes should read");
        let _ = agent_sender.send(bytes);
    });

    let mut connection = public_key_connection("127.0.0.1".to_string(), port, identity);
    connection.port_forwards = vec![
        TerminalSshPortForward {
            kind: TerminalSshPortForwardKind::Local,
            bind_host: "127.0.0.1".to_string(),
            bind_port: local_port,
            target_host: "target".to_string(),
            target_port: 22,
        },
        TerminalSshPortForward {
            kind: TerminalSshPortForwardKind::Dynamic,
            bind_host: "127.0.0.1".to_string(),
            bind_port: socks_port,
            target_host: String::new(),
            target_port: 0,
        },
        TerminalSshPortForward {
            kind: TerminalSshPortForwardKind::Local,
            bind_host: "127.0.0.1".to_string(),
            bind_port: rejected_local_port,
            target_host: "target".to_string(),
            target_port: 1,
        },
        TerminalSshPortForward {
            kind: TerminalSshPortForwardKind::Remote,
            bind_host: "127.0.0.1".to_string(),
            bind_port: remote_port,
            target_host: "127.0.0.1".to_string(),
            target_port: remote_target_port,
        },
    ];
    connection.agent_forwarding = true;
    connection.agent_socket = Some(agent_path.to_string_lossy().into_owned());
    connection.x11_forwarding = true;
    connection.x11_target_host = Some("127.0.0.1".to_string());
    connection.x11_target_port = x11_target_port;
    connection.x11_auth_cookie = Some("00112233445566778899aabbccddeeff".to_string());

    for (reservation, expected_port) in port_reservations.iter().zip(&reserved_ports) {
        assert_eq!(
            reservation
                .local_addr()
                .expect("reserved port address")
                .port(),
            *expected_port
        );
        assert!(
            reservation
                .take_error()
                .expect("reserved listener error state")
                .is_none(),
            "reserved port {expected_port} entered an error state"
        );
    }
    drop(port_reservations);
    let runtime = spawn_ssh(connection, 24, 100).expect("forwarding SSH transport should start");
    let SshRuntime {
        master: _,
        mut reader,
        mut writer,
        mut child,
        auth: _,
        sftp: _,
    } = runtime;
    let (output_sender, output_receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut output = Vec::new();
        let result = reader.read_to_end(&mut output).map(|_| output);
        let _ = output_sender.send(result);
    });

    assert_ssh_banner(connect_with_retry(local_port), "local port forward");
    let mut rejected = connect_with_retry(rejected_local_port);
    rejected
        .set_read_timeout(Some(Duration::from_secs(5)))
        .expect("rejected-forward timeout");
    let mut rejected_byte = [0_u8; 1];
    assert!(
        !matches!(rejected.read(&mut rejected_byte), Ok(1)),
        "a rejected local forward should close only its accepted connection"
    );

    let mut socks = connect_with_retry(socks_port);
    socks.write_all(&[5, 1, 0]).expect("SOCKS greeting");
    let mut greeting = [0_u8; 2];
    socks.read_exact(&mut greeting).expect("SOCKS method reply");
    assert_eq!(greeting, [5, 0]);
    let host = b"target";
    let mut request = vec![5, 1, 0, 3, host.len() as u8];
    request.extend_from_slice(host);
    request.extend_from_slice(&22_u16.to_be_bytes());
    socks.write_all(&request).expect("SOCKS CONNECT request");
    let mut reply = [0_u8; 10];
    socks.read_exact(&mut reply).expect("SOCKS CONNECT reply");
    assert_eq!(&reply[..2], &[5, 0]);
    assert_ssh_banner(socks, "dynamic SOCKS5 forward");

    writer
        .write_all(
            format!(
                "printf REMOTE_FORWARD >/dev/tcp/127.0.0.1/{remote_port}; printf AGENT_FORWARD | socat - UNIX-CONNECT:\"$SSH_AUTH_SOCK\"; display=${{DISPLAY#*:}}; display=${{display%%.*}}; port=$((6000+display)); cookie=$(xauth list \"$DISPLAY\" | awk 'NR == 1 {{print $3}}'); test \"${{#cookie}}\" -eq 32; escaped=$(printf '%s' \"$cookie\" | sed 's/../\\\\x&/g'); exec 3<>/dev/tcp/127.0.0.1/$port; printf '%b' '\\x6c\\x00\\x0b\\x00\\x00\\x00\\x12\\x00\\x10\\x00\\x00\\x00MIT-MAGIC-COOKIE-1\\x00\\x00' >&3; printf '%b' \"$escaped\" >&3; printf X11_FORWARD >&3; exec 3>&-; printf 'IANVS_SSH_E2E_RESULT=forwarding:%s\\n' \"$(id -un)\"; exit\n"
            )
            .as_bytes(),
        )
        .expect("forwarding probe commands should queue");
    drop(writer);

    assert_eq!(
        remote_receiver
            .recv_timeout(SESSION_TIMEOUT)
            .expect("remote bytes"),
        b"REMOTE_FORWARD"
    );
    assert_eq!(
        agent_receiver
            .recv_timeout(SESSION_TIMEOUT)
            .expect("agent bytes"),
        b"AGENT_FORWARD"
    );
    let mut expected_x11 = vec![
        b'l', 0, 11, 0, 0, 0, 18, 0, 16, 0, 0, 0, b'M', b'I', b'T', b'-', b'M', b'A', b'G', b'I',
        b'C', b'-', b'C', b'O', b'O', b'K', b'I', b'E', b'-', b'1', 0, 0,
    ];
    expected_x11.extend_from_slice(&X11_REAL_COOKIE);
    expected_x11.extend_from_slice(b"X11_FORWARD");
    assert_eq!(
        x11_receiver
            .recv_timeout(SESSION_TIMEOUT)
            .expect("X11 bytes"),
        expected_x11
    );
    let output = output_receiver
        .recv_timeout(SESSION_TIMEOUT)
        .expect("forwarding output should arrive")
        .expect("forwarding reader should succeed");
    let status = child.wait().expect("forwarding child should exit");
    let output = String::from_utf8_lossy(&output);
    assert!(status.success(), "forwarding session failed:\n{output}");
    assert!(output.contains("IANVS_SSH_E2E_RESULT=forwarding:ianvs"));
    eprintln!("ssh-e2e: local, remote, SOCKS5, agent, and X11 forwarding accepted");
}

#[test]
#[ignore = "requires the dedicated Docker OpenSSH topology; run tools/ssh_e2e/run.sh"]
fn openssh_authentication_and_proxy_jump_acceptance() {
    run_sftp_probe(
        password_connection(required_port("IANVS_SSH_E2E_PASSWORD_PORT")),
        "password",
    );

    // The server disables PasswordAuthentication and only exposes PAM-backed
    // keyboard-interactive. Reusing the password here therefore exercises the
    // native keyboard-interactive fallback, not the password method.
    run_shell_probe(
        password_connection(required_port("IANVS_SSH_E2E_KEYBOARD_INTERACTIVE_PORT")),
        "keyboard-interactive",
    );

    run_multi_round_otp_probe(required_port("IANVS_SSH_E2E_OTP_PORT"));

    let identity = required_env("IANVS_SSH_E2E_PRIVATE_KEY");
    run_shell_probe(
        public_key_connection(
            "127.0.0.1".to_string(),
            required_port("IANVS_SSH_E2E_PUBLIC_KEY_PORT"),
            &identity,
        ),
        "publickey",
    );

    let jump_port = required_port("IANVS_SSH_E2E_JUMP_PORT");
    let mut target =
        public_key_connection(required_env("IANVS_SSH_E2E_TARGET_HOST"), 22, &identity);
    target.proxy_jump = Some(format!(
        "{TEST_USER}@127.0.0.1:{jump_port},{TEST_USER}@jump2:22"
    ));
    target.proxy_jump_profiles = vec![
        TerminalSshJumpProfile {
            auth: TerminalSshAuthMethod::PublicKey,
            private_keys: vec![identity.clone()],
            host_key_policy: TerminalSshHostKeyPolicy::Insecure,
            ..<_>::default()
        },
        TerminalSshJumpProfile {
            auth: TerminalSshAuthMethod::PublicKey,
            private_keys: vec![identity.clone()],
            host_key_policy: TerminalSshHostKeyPolicy::Insecure,
            ..<_>::default()
        },
    ];
    run_shell_probe(target, "target-via-two-jumps");

    #[cfg(unix)]
    run_forwarding_probe(required_port("IANVS_SSH_E2E_FORWARDING_PORT"), &identity);
}

#[test]
#[ignore = "requires the dedicated Docker OpenSSH topology; run tools/ssh_e2e/run.sh"]
fn openssh_host_key_policy_acceptance() {
    let port = required_port("IANVS_SSH_E2E_PUBLIC_KEY_PORT");
    let identity = required_env("IANVS_SSH_E2E_PRIVATE_KEY");
    let known_hosts_directory = tempfile::tempdir().expect("known_hosts tempdir");
    let known_hosts_path = known_hosts_directory.path().join("known_hosts");
    let known_hosts = known_hosts_path.to_string_lossy().into_owned();

    let default_policy = TerminalProfileConnection::default().host_key_policy;
    assert_eq!(
        default_policy,
        TerminalSshHostKeyPolicy::AcceptNew,
        "the product SSH connection default must accept and persist new hosts"
    );
    let mut accept_new = public_key_connection("127.0.0.1".to_string(), port, &identity);
    accept_new.host_key_policy = default_policy;
    accept_new.known_hosts_file = Some(known_hosts.clone());
    run_shell_probe(accept_new, "publickey");
    let learned = fs::read_to_string(&known_hosts_path).expect("accept-new known_hosts entry");
    let host_port = format!("[127.0.0.1]:{port}");
    assert!(
        learned.lines().any(|line| line.starts_with(&host_port)),
        "accept-new did not persist {host_port:?}:\n{learned}"
    );

    let mut strict_known = public_key_connection("127.0.0.1".to_string(), port, &identity);
    strict_known.host_key_policy = TerminalSshHostKeyPolicy::Strict;
    strict_known.known_hosts_file = Some(known_hosts.clone());
    run_shell_probe(strict_known, "publickey");

    let wrong_host_key = required_env("IANVS_SSH_E2E_WRONG_HOST_PUBLIC_KEY");
    let mut key_fields = wrong_host_key.split_whitespace();
    let key_type = key_fields.next().expect("wrong host public-key type");
    let key_data = key_fields.next().expect("wrong host public-key data");
    let replaced_entry = format!("{host_port} {key_type} {key_data}\n");
    fs::write(&known_hosts_path, &replaced_entry).expect("replace known_hosts host key");

    let mut strict_changed = public_key_connection("127.0.0.1".to_string(), port, &identity);
    strict_changed.host_key_policy = TerminalSshHostKeyPolicy::Strict;
    strict_changed.known_hosts_file = Some(known_hosts.clone());
    let strict_runtime =
        spawn_ssh(strict_changed, 24, 100).expect("strict changed-key transport should start");
    let prompt = wait_for_host_key_prompt(&strict_runtime.auth);
    assert_eq!(prompt.reason, SshHostKeyPromptReason::Changed);
    assert!(
        strict_runtime
            .auth
            .respond_host_key(prompt.challenge_id, false)
    );
    assert_failed_session(
        strict_runtime,
        "strict changed host key",
        &["Unknown server key"],
    );

    let mut accept_new_changed = public_key_connection("127.0.0.1".to_string(), port, &identity);
    accept_new_changed.host_key_policy = TerminalSshHostKeyPolicy::AcceptNew;
    accept_new_changed.known_hosts_file = Some(known_hosts);
    let changed_runtime = spawn_ssh(accept_new_changed, 24, 100)
        .expect("accept-new changed-key transport should start");
    let prompt = wait_for_host_key_prompt(&changed_runtime.auth);
    assert_eq!(prompt.reason, SshHostKeyPromptReason::Changed);
    assert!(
        changed_runtime
            .auth
            .respond_host_key(prompt.challenge_id, true)
    );
    run_shell_probe_runtime(changed_runtime, "publickey");
    assert_ne!(
        fs::read_to_string(&known_hosts_path).expect("updated known_hosts remains readable"),
        replaced_entry,
        "explicit acceptance must replace the changed host key"
    );
    eprintln!("ssh-e2e: strict and accept-new host-key state transitions accepted");
}

#[test]
#[ignore = "requires the dedicated Docker OpenSSH topology; run tools/ssh_e2e/run.sh"]
fn openssh_negative_paths_fail_fast() {
    let password_port = required_port("IANVS_SSH_E2E_PASSWORD_PORT");
    let mut wrong_password = password_connection(password_port);
    wrong_password.password = Some("definitely-wrong-password".to_string());
    assert_failed_session(
        spawn_ssh(wrong_password, 24, 100).expect("wrong-password transport should start"),
        "wrong password",
        &["SSH authentication failed"],
    );

    let encrypted_identity = required_env("IANVS_SSH_E2E_ENCRYPTED_PRIVATE_KEY");
    let mut wrong_key_passphrase = public_key_connection(
        "127.0.0.1".to_string(),
        required_port("IANVS_SSH_E2E_PUBLIC_KEY_PORT"),
        &encrypted_identity,
    );
    wrong_key_passphrase.private_key_passphrase = Some("definitely-wrong-passphrase".to_string());
    assert_failed_session(
        spawn_ssh(wrong_key_passphrase, 24, 100)
            .expect("wrong-key-passphrase transport should start"),
        "wrong encrypted-key passphrase",
        &["could not load private key"],
    );

    let otp_port = required_port("IANVS_SSH_E2E_OTP_PORT");
    let otp_connection = TerminalProfileConnection {
        auth: TerminalSshAuthMethod::KeyboardInteractive,
        ..base_connection(otp_port)
    };
    let wrong_otp_runtime =
        spawn_ssh(otp_connection.clone(), 24, 100).expect("wrong-OTP transport should start");
    let first = next_auth_challenge(&wrong_otp_runtime.auth, "wrong OTP password round");
    assert_eq!(first.prompts.len(), 1);
    assert_eq!(first.prompts[0].prompt.trim(), "Fixture password:");
    assert!(
        wrong_otp_runtime
            .auth
            .respond(first.challenge_id, vec![TEST_PASSWORD.to_string()])
    );
    let second = next_auth_challenge(&wrong_otp_runtime.auth, "wrong OTP token round");
    assert_eq!(second.prompts.len(), 1);
    assert_eq!(second.prompts[0].prompt.trim(), "One-time password:");
    assert!(
        wrong_otp_runtime
            .auth
            .respond(second.challenge_id, vec!["000000".to_string()])
    );
    assert_failed_session(
        wrong_otp_runtime,
        "wrong OTP",
        &["keyboard-interactive SSH authentication failed"],
    );

    let cancelled_runtime =
        spawn_ssh(otp_connection, 24, 100).expect("cancelled-auth transport should start");
    let challenge = next_auth_challenge(&cancelled_runtime.auth, "cancel keyboard-interactive");
    assert_eq!(challenge.prompts.len(), 1);
    assert!(cancelled_runtime.auth.cancel(challenge.challenge_id));
    assert_failed_session(
        cancelled_runtime,
        "cancelled keyboard-interactive",
        &["SSH authentication challenge was cancelled"],
    );

    // Keep a real listener bound without speaking SSH. The first jump can
    // establish TCP but must hit its one-second SSH handshake timeout, with
    // no bind/drop race that could accidentally reach an unrelated service.
    let bad_jump_listener =
        TcpListener::bind(("127.0.0.1", 0)).expect("bad jump listener should bind");
    let bad_jump_port = bad_jump_listener
        .local_addr()
        .expect("bad jump listener address")
        .port();
    let identity = required_env("IANVS_SSH_E2E_PRIVATE_KEY");
    let mut bad_jump_target =
        public_key_connection(required_env("IANVS_SSH_E2E_TARGET_HOST"), 22, &identity);
    bad_jump_target.connect_timeout_seconds = 5;
    bad_jump_target.proxy_jump = Some(format!("{TEST_USER}@127.0.0.1:{bad_jump_port}"));
    bad_jump_target.proxy_jump_profiles = vec![TerminalSshJumpProfile {
        auth: TerminalSshAuthMethod::PublicKey,
        private_keys: vec![identity],
        host_key_policy: TerminalSshHostKeyPolicy::Insecure,
        connect_timeout_seconds: 1,
        ..<_>::default()
    }];
    assert_failed_session(
        spawn_ssh(bad_jump_target, 24, 100).expect("bad-jump transport should start"),
        "bad ProxyJump endpoint",
        &[
            "could not connect to ProxyJump host 127.0.0.1",
            "connection timed out after 1 seconds",
        ],
    );
    drop(bad_jump_listener);
}
