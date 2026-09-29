//! Session-private ZLE control channel. Terminal escape sequences never enter it.
//! The user's shell and its plugins are trusted; hostile same-UID processes are
//! outside this boundary. No command payload is evaluated by the adapter.
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::VecDeque;
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[cfg(unix)]
use std::{
    io::{Read, Write},
    os::unix::net::{UnixListener, UnixStream},
};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct Submit {
    pub lease: String,
    pub submission_id: String,
    pub text: String,
}

pub(crate) struct ComposerBridge {
    nonce: String,
    #[cfg(unix)]
    _directory: tempfile::TempDir,
    inner: Mutex<BridgeState>,
}

struct BridgeState {
    #[cfg(unix)]
    listener: UnixListener,
    #[cfg(unix)]
    stream: Option<UnixStream>,
    authenticated: bool,
    closed: bool,
    input: Vec<u8>,
    epoch: Option<String>,
    cwd: String,
    home: String,
    state: String,
    submission_id: Option<String>,
    outcome: String,
    wake_pending: bool,
    wake_issued: bool,
    submitted_at: Option<Instant>,
    outcomes: VecDeque<(String, String)>,
    history: Vec<String>,
    history_revision: u64,
    pending_history: Option<Vec<String>>,
    pending_history_bytes: usize,
    aliases: Vec<(String, String)>,
    pending_aliases: Option<Vec<(String, String)>>,
    pending_alias_bytes: usize,
}

impl ComposerBridge {
    #[cfg(unix)]
    pub(crate) fn create(_proxy_directory: &Path) -> std::io::Result<(Arc<Self>, String)> {
        let directory = tempfile::Builder::new().prefix("ic-").tempdir()?;
        let path = directory.path().join("s");
        let listener = UnixListener::bind(&path)?;
        listener.set_nonblocking(true)?;
        let nonce = crate::shell_bootstrap::token();
        let script = include_str!("composer_bridge.zsh")
            .replace("@@SOCKET@@", &path.to_string_lossy().replace('\'', "'\\''"))
            .replace("@@NONCE@@", &nonce);
        Ok((
            Arc::new(Self {
                nonce,
                _directory: directory,
                inner: Mutex::new(BridgeState {
                    listener,
                    stream: None,
                    authenticated: false,
                    closed: false,
                    input: vec![],
                    epoch: None,
                    cwd: String::new(),
                    home: String::new(),
                    state: "draft".into(),
                    submission_id: None,
                    outcome: "none".into(),
                    wake_pending: false,
                    wake_issued: false,
                    submitted_at: None,
                    outcomes: VecDeque::new(),
                    history: Vec::new(),
                    history_revision: 0,
                    pending_history: None,
                    pending_history_bytes: 0,
                    aliases: Vec::new(),
                    pending_aliases: None,
                    pending_alias_bytes: 0,
                }),
            }),
            script,
        ))
    }

    #[cfg(not(unix))]
    pub(crate) fn create(_directory: &Path) -> std::io::Result<(Arc<Self>, String)> {
        Err(std::io::Error::new(
            std::io::ErrorKind::Unsupported,
            "ZLE requires Unix",
        ))
    }

    pub(crate) fn snapshot(&self) -> Value {
        let mut state = self.inner.lock().unwrap();
        self.poll(&mut state);
        json!({"state": state.state, "lease": state.epoch.as_ref().map(|e| format!("{}.{e}", self.nonce)),
            "cwd": state.cwd, "home": state.home, "dialect": "zsh", "submissionId": state.submission_id, "outcome": state.outcome,
            "history": state.history, "historyRevision": state.history_revision})
    }

    pub(crate) fn aliases(&self) -> Vec<(String, String)> {
        let mut state = self.inner.lock().unwrap();
        self.poll(&mut state);
        if state.closed {
            return vec![];
        }
        state.aliases.clone()
    }

    /// Consume the single harmless wake byte only after ZLE has acknowledged
    /// preparation in its private keymap. Actual BUFFER assignment and accept
    /// still require the shell-side lease/context check in the commit widget.
    pub(crate) fn take_wakeup(&self) -> bool {
        let mut state = self.inner.lock().unwrap();
        self.expire(&mut state);
        if !state.closed && !state.wake_issued && std::mem::take(&mut state.wake_pending) {
            state.wake_issued = true;
            true
        } else {
            false
        }
    }

    /// Raw input revokes the lease even before ZLE's next redraw callback.
    pub(crate) fn invalidate(&self) {
        let mut state = self.inner.lock().unwrap();
        self.poll(&mut state);
        // A raw-input race must never leave a delayed commit armed. Closing
        // wakes the shell's EOF handler, which restores its original keymap.
        if state.outcome == "pending" {
            Self::close(&mut state);
        }
        state.epoch = None;
        if state.state == "ready" {
            state.state = "suspended".into();
        }
    }

    pub(crate) fn submit(&self, request: Submit) -> Value {
        let mut state = self.inner.lock().unwrap();
        self.poll(&mut state);
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
            return json!({"outcome": "rejected"});
        }
        if state.submission_id.as_ref() == Some(&request.submission_id) {
            return json!({"outcome": state.outcome});
        }
        if let Some((_, outcome)) = state
            .outcomes
            .iter()
            .find(|(id, _)| id == &request.submission_id)
        {
            return json!({"outcome": outcome});
        }
        let Some(epoch) = state.epoch.as_ref() else {
            return json!({"outcome": "rejected"});
        };
        if state.state != "ready" || request.lease != format!("{}.{epoch}", self.nonce) {
            return json!({"outcome": "rejected"});
        }
        let epoch = state.epoch.take().unwrap();
        state.submission_id = Some(request.submission_id.clone());
        state.outcome = "pending".into();
        state.state = "submitting".into();
        state.wake_pending = false;
        state.wake_issued = false;
        state.submitted_at = Some(Instant::now());
        #[cfg(unix)]
        {
            let hex: String = request.text.bytes().map(|b| format!("{b:02x}")).collect();
            let wire = format!("submit\t{epoch}\t{}\t{hex}\n", request.submission_id);
            let result = state
                .stream
                .as_mut()
                .ok_or_else(|| std::io::Error::from(std::io::ErrorKind::NotConnected))
                .and_then(|stream| {
                    stream.set_nonblocking(false)?;
                    stream.set_write_timeout(Some(std::time::Duration::from_millis(100)))?;
                    let result = stream.write_all(wire.as_bytes());
                    let _ = stream.set_nonblocking(true);
                    result
                });
            if result.is_err() {
                Self::close(&mut state);
            }
        }
        json!({"outcome": state.outcome})
    }

    fn close(state: &mut BridgeState) {
        state.closed = true;
        state.epoch = None;
        state.wake_pending = false;
        state.submitted_at = None;
        state.state = "draft".into();
        if state.outcome == "pending" {
            state.outcome = "unknown".into();
        }
        #[cfg(unix)]
        {
            state.stream = None;
        }
        state.input.clear();
        state.pending_history = None;
        state.pending_aliases = None;
    }

    fn expire(&self, state: &mut BridgeState) {
        if state.outcome == "pending"
            && state
                .submitted_at
                .is_some_and(|at| at.elapsed() > Duration::from_millis(1500))
        {
            Self::close(state);
        }
    }

    #[cfg(unix)]
    fn poll(&self, state: &mut BridgeState) {
        self.expire(state);
        if state.closed {
            return;
        }
        if state.stream.is_none() {
            if let Ok((stream, _)) = state.listener.accept() {
                if stream.set_nonblocking(true).is_err() {
                    Self::close(state);
                    return;
                }
                state.stream = Some(stream);
            } else {
                return;
            }
        }
        let mut buf = [0; 8192];
        loop {
            match state.stream.as_mut().unwrap().read(&mut buf) {
                Ok(0) => {
                    Self::close(state);
                    return;
                }
                Ok(n) => state.input.extend_from_slice(&buf[..n]),
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                Err(_) => {
                    Self::close(state);
                    return;
                }
            }
            if state.input.len() > 49152 {
                Self::close(state);
                return;
            }
        }
        while let Some(end) = state.input.iter().position(|b| *b == b'\n') {
            let bytes: Vec<u8> = state.input.drain(..=end).collect();
            let Ok(line) = std::str::from_utf8(&bytes[..bytes.len() - 1]) else {
                Self::close(state);
                return;
            };
            let fields: Vec<&str> = line.split('\t').collect();
            if !state.authenticated {
                if fields == ["hello", &self.nonce] {
                    state.authenticated = true;
                } else {
                    Self::close(state);
                    return;
                }
                continue;
            }
            match fields.as_slice() {
                ["history-begin"] if state.pending_history.is_none() => {
                    state.pending_history = Some(Vec::new());
                    state.pending_history_bytes = 0;
                }
                ["history", hex] if state.pending_history.is_some() => {
                    let Some(command) = decode_hex(hex) else {
                        Self::close(state);
                        return;
                    };
                    state.pending_history_bytes += command.len();
                    let history = state.pending_history.as_mut().unwrap();
                    if history.len() >= 100 || state.pending_history_bytes > 8192 {
                        Self::close(state);
                        return;
                    }
                    // Optional shell data must not disable submission merely
                    // because history contains literal terminal controls.
                    if !command.trim().is_empty()
                        && !command.starts_with(char::is_whitespace)
                        && !command
                            .chars()
                            .any(|c| c.is_control() && c != '\n' && c != '\t')
                    {
                        history.push(command);
                    }
                }
                ["history-end"] if state.pending_history.is_some() => {
                    let history = state.pending_history.take().unwrap();
                    if state.history != history {
                        state.history = history;
                        state.history_revision += 1;
                    }
                }
                ["aliases-begin"] if state.pending_aliases.is_none() => {
                    state.pending_aliases = Some(Vec::new());
                    state.pending_alias_bytes = 0;
                }
                ["alias", name, value] if state.pending_aliases.is_some() => {
                    let (Some(name), Some(value)) = (decode_hex(name), decode_hex(value)) else {
                        Self::close(state);
                        return;
                    };
                    state.pending_alias_bytes += name.len() + value.len();
                    let aliases = state.pending_aliases.as_mut().unwrap();
                    if aliases.len() >= 64 || state.pending_alias_bytes > 2048 {
                        Self::close(state);
                        return;
                    }
                    if !name.is_empty()
                        && name.len() <= 128
                        && value.len() <= 1024
                        && name
                            .chars()
                            .all(|c| c.is_alphanumeric() || "_-".contains(c))
                        && !value.chars().any(char::is_control)
                    {
                        aliases.push((name, value));
                    }
                }
                ["aliases-end"] if state.pending_aliases.is_some() => {
                    state.aliases = state.pending_aliases.take().unwrap();
                }
                ["ready", epoch, cwd] | ["ready", epoch, cwd, _]
                    if epoch.parse::<u64>().is_ok() && epoch.len() <= 20 =>
                {
                    let Some(cwd) = decode_hex(cwd).filter(|v| {
                        v.len() <= 4096 && v.starts_with('/') && !v.chars().any(char::is_control)
                    }) else {
                        Self::close(state);
                        return;
                    };
                    state.epoch = Some((*epoch).into());
                    state.cwd = cwd;
                    // HOME belongs to this live shell, never the GUI process.
                    // A missing or unusable HOME only disables tilde completion.
                    state.home = fields
                        .get(3)
                        .and_then(|value| decode_hex(value))
                        .filter(|value| {
                            value.starts_with('/') && !value.chars().any(char::is_control)
                        })
                        .unwrap_or_default();
                    state.state = "ready".into();
                }
                ["prepared", id]
                    if state.submission_id.as_deref() == Some(id) && state.outcome == "pending" =>
                {
                    if !state.wake_issued {
                        state.wake_pending = true;
                    }
                }
                ["busy"] => {
                    state.epoch = None;
                    state.state = "running".into();
                }
                ["continuation"] => {
                    state.epoch = None;
                    state.state = "suspended".into();
                }
                [outcome @ ("accepted" | "rejected"), id]
                    if state.submission_id.as_deref() == Some(id) =>
                {
                    state.outcome = (*outcome).into();
                    if !state.outcomes.iter().any(|(prior, _)| prior == id) {
                        state.outcomes.push_back(((*id).into(), (*outcome).into()));
                        if state.outcomes.len() > 64 {
                            state.outcomes.pop_front();
                        }
                    }
                    state.wake_pending = false;
                    state.submitted_at = None;
                    state.state = if *outcome == "accepted" {
                        "running"
                    } else {
                        "draft"
                    }
                    .into();
                }
                _ => {
                    Self::close(state);
                    return;
                }
            }
        }
    }

    #[cfg(not(unix))]
    fn poll(&self, _state: &mut BridgeState) {}
}

fn decode_hex(value: &str) -> Option<String> {
    if !value.len().is_multiple_of(2) || value.len() > 8192 {
        return None;
    }
    let bytes: Option<Vec<u8>> = value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).ok()?, 16).ok())
        .collect();
    String::from_utf8(bytes?).ok()
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    fn connected() -> (Arc<ComposerBridge>, UnixStream) {
        let (bridge, _) = ComposerBridge::create(Path::new("/tmp")).unwrap();
        let path = bridge.inner.lock().unwrap().listener.local_addr().unwrap();
        let mut shell = UnixStream::connect(path.as_pathname().unwrap()).unwrap();
        shell
            .write_all(format!("hello\t{}\nready\t1\t2f746d70\n", bridge.nonce).as_bytes())
            .unwrap();
        assert_eq!(bridge.snapshot()["state"], "ready");
        (bridge, shell)
    }
    fn submit(bridge: &ComposerBridge) {
        assert_eq!(
            bridge.submit(Submit {
                lease: format!("{}.1", bridge.nonce),
                submission_id: "test".into(),
                text: "print safe".into()
            })["outcome"],
            "pending"
        );
    }
    #[test]
    fn prepared_wakes_at_most_once_and_raw_race_revokes() {
        let (bridge, mut shell) = connected();
        submit(&bridge);
        shell.write_all(b"prepared\ttest\n").unwrap();
        bridge.snapshot();
        assert!(bridge.take_wakeup());
        shell.write_all(b"prepared\ttest\n").unwrap();
        bridge.snapshot();
        assert!(!bridge.take_wakeup());
        bridge.invalidate();
        assert_eq!(bridge.snapshot()["outcome"], "unknown");
        assert!(!bridge.take_wakeup());
    }
    #[test]
    fn deadline_prevents_a_late_wakeup() {
        let (bridge, mut shell) = connected();
        submit(&bridge);
        shell.write_all(b"prepared\ttest\n").unwrap();
        bridge.inner.lock().unwrap().submitted_at = Some(Instant::now() - Duration::from_secs(2));
        assert_eq!(bridge.snapshot()["outcome"], "unknown");
        assert!(!bridge.take_wakeup());
    }
    #[test]
    fn stale_lease_does_not_consume_the_current_lease() {
        let (bridge, _shell) = connected();
        assert_eq!(
            bridge.submit(Submit {
                lease: "stale".into(),
                submission_id: "old".into(),
                text: "print safe".into()
            })["outcome"],
            "rejected"
        );
        assert_eq!(bridge.snapshot()["state"], "ready");
    }
    #[test]
    fn history_is_atomic_and_optional_controls_are_ignored() {
        let (bridge, mut shell) = connected();
        shell
            .write_all(b"history-begin\nhistory\t6563686f206f6b\n")
            .unwrap();
        assert_eq!(bridge.snapshot()["history"], json!([]));
        shell.write_all(b"history\t1b5b6d\nhistory-end\n").unwrap();
        let snapshot = bridge.snapshot();
        assert_eq!(snapshot["state"], "ready");
        assert_eq!(snapshot["history"], json!(["echo ok"]));
        assert_eq!(snapshot["historyRevision"], 1);
        shell
            .write_all(b"history-begin\nhistory\t6563686f206f6b\nhistory-end\n")
            .unwrap();
        assert_eq!(bridge.snapshot()["historyRevision"], 1);
        shell
            .write_all(b"aliases-begin\nalias\t6763\t67697420636865636b6f7574\naliases-end\n")
            .unwrap();
        assert_eq!(bridge.aliases(), vec![("gc".into(), "git checkout".into())]);
    }
    #[test]
    fn oversized_history_snapshot_revokes_the_channel() {
        let (bridge, mut shell) = connected();
        let command = "61".repeat(3000);
        shell.write_all(b"history-begin\n").unwrap();
        for _ in 0..3 {
            shell
                .write_all(format!("history\t{command}\n").as_bytes())
                .unwrap();
            bridge.snapshot();
        }
        assert_ne!(bridge.snapshot()["state"], "ready");
        assert_eq!(bridge.snapshot()["history"], json!([]));
    }
}
