use super::*;
use std::os::unix::fs::PermissionsExt;
use std::process::Command;

fn executable(path: &std::path::Path, source: &str) {
    std::fs::write(path, source).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

fn decode_launcher(command: &str) -> String {
    // Wrapper context IDs are substituted after encoding. Profile IDs are
    // encoded with the script; compare what printf delivers to the target.
    regex::Regex::new(r"\\0([0-7]{3})")
        .unwrap()
        .replace_all(command, |capture: &regex::Captures<'_>| {
            char::from(u8::from_str_radix(&capture[1], 8).unwrap()).to_string()
        })
        .into_owned()
}

#[test]
fn wrapped_ssh_and_profile_connections_use_the_same_initialization() {
    for shell in ["/bin/bash", "/bin/zsh", "/opt/homebrew/bin/fish"] {
        if !std::path::Path::new(shell).exists() {
            continue;
        }
        for socket in [
            "/tmp/ianvs-existing-master".to_string(),
            "none".to_string(),
            format!("/tmp/{}", "s".repeat(110)),
            "/tmp/ianvs master".to_string(),
            "relative-master".to_string(),
        ] {
            let scratch = tempfile::tempdir().unwrap();
            // Only replace OpenSSH and socket creation. Execute the production
            // wrapper in each installed shell, preserving its real argv rules.
            executable(
                &scratch.path().join("ssh"),
                r#"#!/bin/sh
if [ "$1" = -G ]; then
  printf 'hostname fixture\nuser lab\nport 22\ncontrolpath %s\n' "$IANVS_TEST_SOCKET"
  exit 0
fi
if [ "$1" = -S ]; then exit 0; fi
printf '%s\n' "$@" > "$IANVS_TEST_ARGS"
for arg do last=$arg; done
printf %s "$last" > "$IANVS_TEST_COMMAND"
"#,
            );
            executable(&scratch.path().join("mktemp"), "#!/bin/sh\nexit 1\n");
            let kind = shell.rsplit('/').next().unwrap();
            let output = Command::new(shell)
                .args([
                    "-c",
                    &format!("{}\nssh fixture", ssh_wrapper("local", kind)),
                ])
                .env(
                    "PATH",
                    format!("{}:/usr/bin:/bin", scratch.path().display()),
                )
                .env("HOME", scratch.path())
                .env("ZDOTDIR", scratch.path())
                .env("IANVS_TEST_SOCKET", &socket)
                .env("IANVS_TEST_ARGS", scratch.path().join("args"))
                .env("IANVS_TEST_COMMAND", scratch.path().join("command"))
                .env_remove("__IANVS_CONTEXT")
                .output()
                .unwrap();
            assert!(output.status.success(), "{shell}: {:?}", output.stderr);
            let mut wrapped = Bootstrap::new("local".into(), true);
            let result = wrapped.feed(&output.stdout);
            let entered = tests::events(&result.output)
                .into_iter()
                .find(|event| event["hook"] == "bootstrap.checking")
                .unwrap_or_else(|| panic!("{shell}, socket={socket}: no SSH initialization"));
            let id = entered["context_id"].as_str().unwrap();
            let has_route = socket == "/tmp/ianvs-existing-master";
            assert_eq!(entered["sftp_route"], has_route, "{shell}: {socket}");
            assert_eq!(
                decode_launcher(&std::fs::read_to_string(scratch.path().join("command")).unwrap()),
                decode_launcher(&launcher(id, id)),
                "{shell}: {socket}"
            );
            let args = std::fs::read_to_string(scratch.path().join("args")).unwrap();
            assert!(args.contains("-t\nfixture\n"), "{args}");
            if !has_route {
                assert!(args.contains("ControlPath=none\n"), "{args}");
            }

            // The mock command has returned, so isolate its enter frame for
            // the handshake comparison before the wrapper's resume frame.
            for target in ["bash", "zsh", "fish"] {
                let mut wrapped = Bootstrap::new("local".into(), true);
                let enter_end = output.stdout.iter().position(|&b| b == 7).unwrap() + 1;
                wrapped.feed(&output.stdout[..enter_end]);
                let reply =
                    wrapped.feed(format!("\x1b]6973;{id};{id};init;{target}\x07").as_bytes());
                let mut profile = Bootstrap::new("root".into(), true);
                let expected =
                    profile.feed(format!("\x1b]6973;root;root;init;{target}\x07").as_bytes());
                assert_eq!(reply.replies.len(), 1, "{shell}: {socket}");
                // Context lengths shift Zsh's 256-character wire chunks; join
                // those chunks before comparing the actual payload contents.
                assert_eq!(
                    String::from_utf8(reply.replies[0].clone())
                        .unwrap()
                        .replace("'\\\n'", "")
                        .replace(id, "root"),
                    String::from_utf8(expected.replies[0].clone())
                        .unwrap()
                        .replace("'\\\n'", ""),
                    "{shell} -> {target}: {socket}"
                );
            }
        }
    }
}

#[test]
fn owned_socket_cleanup_does_not_create_interactive_jobs() {
    use portable_pty::{CommandBuilder, PtySize, native_pty_system};
    use std::time::Duration;

    let job_notification = regex::Regex::new(r"\[\d+\]").unwrap();
    for (shell, options) in [
        ("/bin/bash", "set -m; set -b"),
        ("/bin/zsh", "setopt MONITOR NOTIFY"),
        // POSIX_JOBS keeps job control enabled in Zsh subshells by default.
        ("/bin/zsh", "setopt MONITOR NOTIFY POSIX_JOBS"),
    ] {
        if !std::path::Path::new(shell).exists() {
            continue;
        }
        for (busy, ssh_status) in [(false, 0), (false, 255), (true, 23)] {
            // Keep the control socket path within the production length limit.
            let scratch = tempfile::tempdir_in("/tmp").unwrap();
            let root = scratch.path();
            let case = format!("{shell}, {options}, busy={busy}, status={ssh_status}");
            executable(
                &root.join("ssh"),
                r#"#!/bin/sh
if [ "$1" = -G ]; then
  printf 'hostname fixture\nuser lab\nport 22\ncontrolpath none\n'
  exit 0
fi
exit "$IANVS_TEST_EXIT"
"#,
            );
            executable(
                &root.join("mktemp"),
                r#"#!/bin/sh
mkdir "$HOME/socket" || exit 1
if [ "$IANVS_TEST_BUSY" = 1 ]; then : > "$HOME/socket/m"; fi
printf '%s/socket\n' "$HOME"
"#,
            );
            executable(
                &root.join("sleep"),
                r#"#!/bin/sh
printf '%s\n' "$@" > "$HOME/delay"
# The wrapper must return before cleanup is released. Bound the wait so a
# failing test cannot leave a worker behind after its scratch directory goes.
attempts=0
while [ ! -f "$HOME/release" ]; do
  [ "$attempts" -lt 200 ] || exit 1
  attempts=$((attempts + 1))
  /bin/sleep 0.02
done
"#,
            );
            executable(
                &root.join("rmdir"),
                r#"#!/bin/sh
/bin/rmdir "$@"
printf '%s\n' "$?" > "$HOME/cleaned"
"#,
            );
            let kind = shell.rsplit('/').next().unwrap();
            std::fs::write(root.join("wrapper"), ssh_wrapper("local", kind)).unwrap();
            let script = format!(
                r#"source "$HOME/wrapper"
{options}
set -o > "$HOME/options-before"
ssh fixture
__test_status=$?
set -o > "$HOME/options-after"
printf '__SSH_STATUS_%s__\n' "$__test_status"
jobs -p > "$HOME/jobs"
[ ! -f "$HOME/cleaned" ] || exit 91
: > "$HOME/release"
while [ ! -f "$HOME/cleaned" ]; do /bin/sleep 0.02; done
jobs
printf '__CLEANUP_FINISHED__\n'
"#
            );
            let mut command = CommandBuilder::new(shell);
            if kind == "bash" {
                command.args(["--noprofile", "--norc", "-i", "-c", &script]);
            } else {
                command.args(["-f", "-i", "-c", &script]);
            }
            command.env("HOME", root);
            command.env("ZDOTDIR", root);
            command.env("TERM", "dumb");
            command.env("PATH", format!("{}:/usr/bin:/bin", root.display()));
            command.env("__IANVS_CONTEXT", "root");
            command.env("IANVS_TEST_EXIT", ssh_status.to_string());
            command.env("IANVS_TEST_BUSY", if busy { "1" } else { "0" });
            command.cwd(root);
            // Pipes do not exercise interactive job control or Zsh's direct
            // terminal notifications. Run the production wrapper in a PTY.
            let pair = native_pty_system().openpty(PtySize::default()).unwrap();
            let mut child = pair.slave.spawn_command(command).unwrap();
            drop(pair.slave);
            let mut reader = pair.master.try_clone_reader().unwrap();
            let (tx, rx) = std::sync::mpsc::channel();
            let reader_thread = std::thread::spawn(move || {
                let mut output = Vec::new();
                let _ = reader.read_to_end(&mut output);
                let _ = tx.send(output);
            });
            let output = rx.recv_timeout(Duration::from_secs(10));
            // Release a worker even when the wrapper incorrectly waits for it.
            std::fs::write(root.join("release"), "").unwrap();
            if output.is_err() {
                let _ = child.kill();
            }
            let status = child.wait().unwrap();
            drop(pair.master);
            reader_thread.join().unwrap();
            let output = String::from_utf8_lossy(
                &output.unwrap_or_else(|error| panic!("{case}: cleanup blocked: {error}")),
            )
            .into_owned();
            assert!(status.success(), "{case}: {output}");
            assert!(output.contains("__CLEANUP_FINISHED__"), "{case}: {output}");
            assert!(
                output.contains(&format!("__SSH_STATUS_{ssh_status}__")),
                "{case}: {output}"
            );
            assert_eq!(std::fs::read_to_string(root.join("delay")).unwrap(), "65\n");
            assert_eq!(
                std::fs::read(root.join("options-before")).unwrap(),
                std::fs::read(root.join("options-after")).unwrap(),
                "{case}: the wrapper changed the caller's shell options"
            );
            assert_eq!(
                root.join("socket").exists(),
                busy,
                "{case}: cleanup must remove only an empty socket directory"
            );
            if busy {
                assert!(root.join("socket/m").exists(), "{case}");
            }
            assert_eq!(
                std::fs::read_to_string(root.join("jobs")).unwrap(),
                "",
                "{case}: cleanup leaked into the interactive job table: {output}"
            );
            assert!(
                !job_notification.is_match(&output),
                "{case}: unexpected job notification: {output}"
            );
            assert!(!output.contains("rmdir"), "{case}: {output}");
        }
    }
}
