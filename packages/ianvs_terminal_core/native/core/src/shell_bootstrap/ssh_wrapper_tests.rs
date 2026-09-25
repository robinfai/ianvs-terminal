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
