//! In-memory, per-shell submission adapter negotiated by the SSH bootstrap.
//! Ordinary terminal output cannot grant input ownership: receipts need the
//! separately generated adapter secret, active context and monotonic epoch.
use crate::composer_bridge::Submit;
use parking_lot::Mutex;
use serde_json::{Value, json};
use std::collections::{BTreeMap, VecDeque};
use std::time::{Duration, Instant};

#[derive(Default)]
pub(crate) struct RemoteComposer(Mutex<State>);

#[derive(Default)]
struct State {
    active: String,
    local_root: bool,
    contexts: BTreeMap<String, Adapter>,
    submission: Option<Submission>,
    outcomes: VecDeque<(String, String)>,
}

struct Adapter {
    command_inventory: crate::command_inventory::CommandInventory,
    secret: String,
    shell: String,
    epoch: u64,
    state: &'static str,
    cwd: String,
    home: String,
    aliases: BTreeMap<String, String>,
}

struct Submission {
    id: String,
    context: String,
    outcome: &'static str,
    started: Instant,
}

impl RemoteComposer {
    pub(crate) fn activate(&self, context: &str, local_root: bool) {
        let mut state = self.0.lock();
        Self::invalidate_locked(&mut state);
        state.active = context.into();
        state.local_root = local_root;
        if let Some(adapter) = state.contexts.get_mut(context) {
            // Returning to an ancestor must wait for its next prompt receipt.
            adapter.state = "draft";
        }
    }

    pub(crate) fn retire(&self, contexts: &[String]) {
        let mut state = self.0.lock();
        for context in contexts {
            state.contexts.remove(context);
        }
    }

    pub(crate) fn close(&self) {
        let mut state = self.0.lock();
        Self::invalidate_locked(&mut state);
        state.contexts.clear();
        state.local_root = false;
    }

    pub(crate) fn script(&self, context: &str, shell: &str) -> String {
        let source = match shell {
            "bash" => include_str!("remote_composer/bash.sh"),
            "zsh" => include_str!("remote_composer/zsh.sh"),
            _ => return String::new(),
        };
        let secret = crate::shell_bootstrap::token();
        self.0.lock().contexts.insert(
            context.into(),
            Adapter {
                command_inventory: Default::default(),
                secret: secret.clone(),
                shell: shell.into(),
                epoch: 0,
                state: "draft",
                cwd: String::new(),
                home: String::new(),
                aliases: BTreeMap::new(),
            },
        );
        source
            .replace(
                "@@COMMAND_INVENTORY@@",
                if shell == "zsh" {
                    include_str!("command_inventory.zsh")
                } else {
                    include_str!("command_inventory.bash")
                },
            )
            .replace("@@SECRET@@", &secret)
            .replace("@@CONTEXT@@", context)
    }

    /// None means the original local adapter owns this root shell. Every other
    /// context returns a snapshot, including unsupported/checking contexts.
    pub(crate) fn snapshot(&self) -> Option<Value> {
        let mut state = self.0.lock();
        Self::expire(&mut state);
        if state.local_root && state.active == "root" {
            return None;
        }
        let adapter = state.contexts.get(&state.active);
        let lease = adapter
            .filter(|a| a.state == "ready")
            .map(|a| format!("remote.{}.{}", a.secret, a.epoch));
        Some(
            json!({"state":adapter.map_or("draft", |a| a.state), "lease":lease,
            "contextId":state.active, "transport":"shell", "cwd":adapter.map_or("", |a| a.cwd.as_str()),
            "home":adapter.map_or("", |a| a.home.as_str()), "dialect":adapter.map_or("generic", |a| a.shell.as_str()),
            "submissionId":state.submission.as_ref().map(|s| &s.id),
            "outcome":state.submission.as_ref().map_or("none", |s| s.outcome),
            "history":[], "historyRevision":0,
            "commandNames": adapter.map(|a| &a.command_inventory.names),
            "aliases": adapter.map(|a| &a.aliases)}),
        )
    }

    pub(crate) fn invalidate(&self) {
        Self::invalidate_locked(&mut self.0.lock());
    }

    pub(crate) fn receipt(&self) -> Value {
        let mut state = self.0.lock();
        Self::expire(&mut state);
        json!({"submissionId":state.submission.as_ref().map(|s| &s.id),
            "outcome":state.submission.as_ref().map_or("none", |s| s.outcome)})
    }

    pub(crate) fn receipt_for(&self, id: &str) -> Option<String> {
        let mut state = self.0.lock();
        Self::expire(&mut state);
        if let Some(submission) = &state.submission
            && submission.id == id
        {
            return Some(submission.outcome.into());
        }
        state
            .outcomes
            .iter()
            .rev()
            .find(|(key, _)| key == id)
            .map(|(_, outcome)| outcome.clone())
    }

    fn invalidate_locked(state: &mut State) {
        if let Some(adapter) = state.contexts.get_mut(&state.active)
            && matches!(adapter.state, "ready" | "submitting")
        {
            adapter.state = "suspended";
        }
        if let Some(submission) = &mut state.submission
            && submission.outcome == "pending"
        {
            submission.outcome = "unknown";
            state
                .outcomes
                .push_back((submission.id.clone(), "unknown".into()));
            while state.outcomes.len() > 64 {
                state.outcomes.pop_front();
            }
        }
    }

    fn expire(state: &mut State) {
        if state
            .submission
            .as_ref()
            .is_some_and(|s| s.outcome == "pending" && s.started.elapsed() > Duration::from_secs(5))
        {
            Self::invalidate_locked(state);
        }
    }

    /// A single framed write contains only a private key sequence and ASCII
    /// metadata/hex, never literal command text, CR, LF or an accept-line key.
    /// The editor widget validates its lease before assigning/accepting text.
    pub(crate) fn submit(&self, request: Submit) -> (Value, Option<Vec<u8>>) {
        let mut state = self.0.lock();
        Self::expire(&mut state);
        let rejected = || (json!({"outcome":"rejected"}), None);
        if request.submission_id.is_empty()
            || request.submission_id.len() > 80
            || !request
                .submission_id
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-')
            || request.text.is_empty()
            || request.text.len() > 65_536
            || request
                .text
                .chars()
                .any(|c| c.is_control() && c != '\n' && c != '\t')
        {
            return rejected();
        }
        if let Some(submission) = &state.submission {
            if submission.id == request.submission_id {
                return (json!({"outcome":submission.outcome}), None);
            }
            if submission.outcome == "pending" {
                return rejected();
            }
        }
        if let Some((_, outcome)) = state
            .outcomes
            .iter()
            .find(|(id, _)| id == &request.submission_id)
        {
            return (json!({"outcome":outcome}), None);
        }
        let active = state.active.clone();
        let Some(adapter) = state.contexts.get_mut(&active) else {
            return rejected();
        };
        if adapter.state != "ready"
            || request.lease != format!("remote.{}.{}", adapter.secret, adapter.epoch)
        {
            return rejected();
        }
        let hex: String = request.text.bytes().map(|b| format!("{b:02x}")).collect();
        let wire = format!(
            "\x1b[6973;{}~{}:{}:{}!",
            adapter.secret, adapter.epoch, request.submission_id, hex
        )
        .into_bytes();
        adapter.state = "submitting";
        state.submission = Some(Submission {
            id: request.submission_id,
            context: active,
            outcome: "pending",
            started: Instant::now(),
        });
        (json!({"outcome":"pending"}), Some(wire))
    }

    /// Called before the bootstrap parser exposes bytes to the VT/recording.
    pub(crate) fn receive(&self, secret: &str, context: &str, fields: &[&str]) {
        let mut state = self.0.lock();
        Self::expire(&mut state);
        if state.active != context {
            return;
        }
        let Some(adapter) = state.contexts.get_mut(context) else {
            return;
        };
        if adapter.secret != secret {
            return;
        }
        match fields {
            ["commands" | "commands-end", ..] => {
                adapter.command_inventory.receive(fields, adapter.epoch);
            }
            ["ready", epoch, cwd, home] | ["ready", epoch, cwd, home, _] => {
                let Ok(epoch) = epoch.parse::<u64>() else {
                    return;
                };
                if epoch <= adapter.epoch {
                    return;
                }
                let (Some(cwd), Some(home)) = (path(cwd), path(home)) else {
                    return;
                };
                // Only names are needed for local intent detection. Do not
                // transport alias bodies (which may contain credentials).
                let names = fields.get(4).copied().unwrap_or("");
                if names.len() > 2048 {
                    return;
                }
                let aliases: Vec<_> = names.split(',').filter(|n| !n.is_empty()).collect();
                if aliases.len() > 64
                    || aliases.iter().any(|name| {
                        name.len() > 128
                            || !name
                                .bytes()
                                .all(|b| b.is_ascii_alphanumeric() || b"_.-".contains(&b))
                    })
                {
                    return;
                }
                adapter.aliases = aliases
                    .iter()
                    .map(|name| (name.to_string(), name.to_string()))
                    .collect();
                adapter.epoch = epoch;
                adapter.command_inventory.commit(epoch);
                adapter.cwd = cwd;
                adapter.home = home;
                adapter.state = "ready";
            }
            ["busy"] => {
                adapter.state = "running";
            }
            ["suspended"] => {
                adapter.state = "suspended";
            }
            [outcome @ ("accepted" | "rejected"), id] => {
                let Some(submission) = &mut state.submission else {
                    return;
                };
                if submission.context != context
                    || submission.id != *id
                    || submission.outcome != "pending"
                {
                    return;
                }
                submission.outcome = if *outcome == "accepted" {
                    "accepted"
                } else {
                    "rejected"
                };
                state.outcomes.push_back(((*id).into(), (*outcome).into()));
                while state.outcomes.len() > 64 {
                    state.outcomes.pop_front();
                }
                state.contexts.get_mut(context).unwrap().state = if *outcome == "accepted" {
                    "running"
                } else {
                    "suspended"
                };
            }
            _ => {}
        }
    }
}

fn path(hex: &str) -> Option<String> {
    if hex.len() > 8192 || !hex.len().is_multiple_of(2) {
        return None;
    }
    let bytes: Option<Vec<_>> = hex
        .as_bytes()
        .chunks_exact(2)
        .map(|p| u8::from_str_radix(std::str::from_utf8(p).ok()?, 16).ok())
        .collect();
    String::from_utf8(bytes?)
        .ok()
        .filter(|p| p.starts_with('/') && !p.chars().any(char::is_control))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ready(bridge: &RemoteComposer, context: &str, epoch: u64) -> String {
        let secret = bridge.0.lock().contexts[context].secret.clone();
        bridge.receive(
            &secret,
            context,
            &["ready", &epoch.to_string(), "2f746d70", "2f746d70"],
        );
        bridge.snapshot().unwrap()["lease"].as_str().unwrap().into()
    }
    fn request(lease: &str, id: &str, text: &str) -> Submit {
        Submit {
            lease: lease.into(),
            submission_id: id.into(),
            text: text.into(),
        }
    }

    #[test]
    fn command_names_require_the_current_nodes_secret_and_prompt() {
        let bridge = RemoteComposer::default();
        bridge.activate("a", false);
        bridge.script("a", "zsh");
        let secret = bridge.0.lock().contexts["a"].secret.clone();
        bridge.receive(&secret, "a", &["commands", "1", "ls,帮助,fn"]);
        assert_eq!(bridge.snapshot().unwrap()["commandNames"], json!([]));
        bridge.receive(&secret, "a", &["commands-end", "1"]);
        ready(&bridge, "a", 1);
        assert_eq!(
            bridge.snapshot().unwrap()["commandNames"],
            json!(["fn", "ls", "帮助"])
        );
        bridge.receive("forged", "a", &["commands", "2", "fake"]);
        bridge.receive("forged", "a", &["commands-end", "2"]);
        ready(&bridge, "a", 2);
        assert_eq!(bridge.snapshot().unwrap()["commandNames"], json!([]));
        bridge.activate("b", false);
        bridge.script("b", "bash");
        bridge.receive(&secret, "a", &["commands", "3", "wrong-node"]);
        bridge.receive(&secret, "a", &["commands-end", "3"]);
        ready(&bridge, "b", 1);
        assert_eq!(bridge.snapshot().unwrap()["commandNames"], json!([]));
        bridge.activate("a", false);
        ready(&bridge, "a", 3);
        assert_eq!(bridge.snapshot().unwrap()["commandNames"], json!([]));
    }

    #[test]
    fn aliases_are_bounded_authenticated_and_never_follow_another_node() {
        let bridge = RemoteComposer::default();
        bridge.activate("a", false);
        bridge.script("a", "zsh");
        let secret = bridge.0.lock().contexts["a"].secret.clone();
        bridge.receive(
            &secret,
            "a",
            &["ready", "1", "2f746d70", "2f746d70", "ll,describe"],
        );
        assert_eq!(
            bridge.snapshot().unwrap()["aliases"]["describe"],
            "describe"
        );
        bridge.receive(
            "forged",
            "a",
            &["ready", "2", "2f746d70", "2f746d70", "fake"],
        );
        assert!(bridge.snapshot().unwrap()["aliases"]["fake"].is_null());
        bridge.receive(
            &secret,
            "a",
            &["ready", "2", "2f746d70", "2f746d70", "bad;name"],
        );
        assert!(bridge.snapshot().unwrap()["aliases"]["describe"].is_string());
        bridge.activate("b", false);
        bridge.script("b", "bash");
        ready(&bridge, "b", 1);
        assert_eq!(bridge.snapshot().unwrap()["aliases"], json!({}));
        bridge.activate("a", false);
        // An older peer which omits alias metadata clears previous names.
        ready(&bridge, "a", 2);
        assert_eq!(bridge.snapshot().unwrap()["aliases"], json!({}));
    }

    #[test]
    fn only_active_authenticated_fresh_prompt_grants_a_lease() {
        let bridge = RemoteComposer::default();
        bridge.activate("a", false);
        bridge.script("a", "zsh");
        bridge.receive("a", "a", &["ready", "1", "2f746d70", "2f746d70"]);
        assert!(bridge.snapshot().unwrap()["lease"].is_null());
        let old = ready(&bridge, "a", 1);
        bridge.activate("b", false);
        bridge.script("b", "bash");
        let current = ready(&bridge, "b", 1);
        assert_eq!(
            bridge
                .submit(request(&old, "old", "touch WRONG_ENDPOINT"))
                .0["outcome"],
            "rejected"
        );
        let secret_a = bridge.0.lock().contexts["a"].secret.clone();
        bridge.receive(&secret_a, "a", &["ready", "2", "2f746d70", "2f746d70"]);
        assert_eq!(bridge.snapshot().unwrap()["lease"], current);
        bridge.activate("a", false);
        assert!(bridge.snapshot().unwrap()["lease"].is_null());
        bridge.receive(&secret_a, "a", &["ready", "1", "2f746d70", "2f746d70"]);
        assert!(bridge.snapshot().unwrap()["lease"].is_null());
        ready(&bridge, "a", 3);
        bridge.retire(&["b".into()]);
        assert_eq!(
            bridge.submit(request(&current, "stale-b", "false")).0["outcome"],
            "rejected"
        );
    }

    #[test]
    fn literal_payload_receipts_timeouts_and_raw_input_fail_closed() {
        let bridge = RemoteComposer::default();
        bridge.activate("root", false);
        bridge.script("root", "bash");
        let lease = ready(&bridge, "root", 1);
        let (pending, wire) = bridge.submit(request(
            &lease,
            "one",
            "printf '%s\\n' '中文 $()'\nprintf done",
        ));
        assert_eq!(pending["outcome"], "pending");
        let wire = wire.unwrap();
        assert!(!wire.contains(&b'\r') && !wire.contains(&b'\n'));
        assert!(!String::from_utf8_lossy(&wire).contains("printf"));
        assert!(bridge.submit(request(&lease, "one", "false")).1.is_none());
        let secret = bridge.0.lock().contexts["root"].secret.clone();
        bridge.receive(&secret, "root", &["accepted", "one"]);
        assert_eq!(bridge.snapshot().unwrap()["outcome"], "accepted");
        let lease = ready(&bridge, "root", 2);
        assert_eq!(
            bridge.submit(request(&lease, "one", "false")).0["outcome"],
            "accepted"
        );
        bridge.submit(request(&lease, "two", "false"));
        assert_eq!(bridge.receipt_for("one").as_deref(), Some("accepted"));
        assert_eq!(bridge.receipt_for("missing"), None);
        bridge.0.lock().submission.as_mut().unwrap().started =
            Instant::now() - Duration::from_secs(6);
        assert_eq!(bridge.snapshot().unwrap()["outcome"], "unknown");
        bridge.receive(&secret, "root", &["accepted", "two"]);
        assert_eq!(bridge.snapshot().unwrap()["outcome"], "unknown");
        let lease = ready(&bridge, "root", 3);
        bridge.invalidate();
        assert_eq!(
            bridge.submit(request(&lease, "raw", "false")).0["outcome"],
            "rejected"
        );
        bridge.close();
        assert!(bridge.snapshot().unwrap()["lease"].is_null());
    }

    #[test]
    #[cfg(unix)]
    fn remote_composer_real_zsh_memory_bootstrap() {
        use portable_pty::{CommandBuilder, PtySize, native_pty_system};
        use std::io::{Read, Write};
        if !std::path::Path::new("/bin/zsh").exists() {
            return;
        }
        let home = tempfile::tempdir().unwrap();
        std::fs::write(
            home.path().join(".zshrc"),
            "PROMPT='remote> '\nRPROMPT=''\nalias 帮助='echo help'\nmyfixture() { echo UNEXPECTED_INVOCATION; }\n",
        )
        .unwrap();
        let mut bootstrap =
            crate::shell_bootstrap::Bootstrap::new(crate::shell_bootstrap::token(), true);
        let bridge = bootstrap.composer.clone();
        let pair = native_pty_system().openpty(PtySize::default()).unwrap();
        let mut command = CommandBuilder::new("/bin/sh");
        command.args(["-c", &bootstrap.launch_command()]);
        for (key, value) in [("SHELL", "/bin/zsh"), ("TERM", "xterm-256color")] {
            command.env(key, value);
        }
        command.env("HOME", home.path());
        command.env("ZDOTDIR", home.path());
        command.cwd(home.path());
        let mut child = pair.slave.spawn_command(command).unwrap();
        drop(pair.slave);
        let mut reader = pair.master.try_clone_reader().unwrap();
        let mut writer = pair.master.take_writer().unwrap();
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
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
        let mut output = Vec::new();
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let mut wait = |previous: Option<&str>| {
                let deadline = Instant::now() + Duration::from_secs(8);
                loop {
                    let state = bridge.snapshot().unwrap();
                    if state["state"] == "ready" && state["lease"].as_str() != previous {
                        break state;
                    }
                    assert!(
                        Instant::now() < deadline,
                        "state={state}, output={}",
                        String::from_utf8_lossy(&output)
                    );
                    if let Ok(bytes) = rx.recv_timeout(Duration::from_millis(20)) {
                        let processed = bootstrap.feed(&bytes);
                        output.extend(processed.output);
                        for reply in processed.replies {
                            writer.write_all(&reply).unwrap();
                        }
                    }
                }
            };
            let initial = wait(None);
            let names = initial["commandNames"].as_array().unwrap();
            for name in ["ls", "cd", "帮助", "myfixture"] {
                assert!(names.contains(&json!(name)), "missing {name}");
            }
            assert!(!String::from_utf8_lossy(&output).contains("UNEXPECTED_INVOCATION"));
            let lease = initial["lease"].as_str().unwrap();
            let (_, wire) = bridge.submit(request(
                lease,
                "real",
                "export REMOTE_VALUE='中文 😀'; cd /tmp\nprintf '%s\\n' \"$REMOTE_VALUE\"",
            ));
            writer.write_all(&wire.unwrap()).unwrap();
            let deadline = Instant::now() + Duration::from_secs(8);
            loop {
                let state = bridge.snapshot().unwrap();
                if state["state"] == "ready" && state["lease"].as_str() != Some(lease) {
                    assert_eq!(state["outcome"], "accepted");
                    assert!(matches!(
                        state["cwd"].as_str(),
                        Some("/tmp" | "/private/tmp")
                    ));
                    break;
                }
                assert!(
                    Instant::now() < deadline,
                    "state={state}, output={}",
                    String::from_utf8_lossy(&output)
                );
                if let Ok(bytes) = rx.recv_timeout(Duration::from_millis(20)) {
                    let processed = bootstrap.feed(&bytes);
                    output.extend(processed.output);
                    for reply in processed.replies {
                        writer.write_all(&reply).unwrap();
                    }
                }
            }
            assert!(String::from_utf8_lossy(&output).contains("中文 😀"));
            // A stale frame is consumed and rejected without accepting raw text.
            writer.write_all(b"echo KEEP_DRAFT").unwrap();
            let secret = bridge.0.lock().contexts["root"].secret.clone();
            writer
                .write_all(format!("\x1b[6973;{secret}~1:stale:66616c7365!").as_bytes())
                .unwrap();
        }));
        let _ = child.kill();
        let _ = child.wait();
        if let Err(error) = result {
            std::panic::resume_unwind(error);
        }
    }
}
