//! In-memory shell bootstrap shared by SSH protocol sessions and local ssh wrappers.
//! Only a session-scoped, explicitly requested handshake can write bootstrap input.
use serde_json::json;
use std::collections::{BTreeMap, VecDeque};
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};

pub(crate) const TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);
const PREFIX: &[u8] = b"\x1b]6973;";
const MAX_FRAME: usize = 8192;

pub(crate) fn token() -> String {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes).expect("OS randomness unavailable");
    bytes.iter().map(|v| format!("{v:02x}")).collect()
}
fn quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}
fn fish_quote(s: &str) -> String {
    format!("'{}'", s.replace('\\', "\\\\").replace('\'', "\\'"))
}
fn hook(value: serde_json::Value) -> Vec<u8> {
    let hex: String = value
        .to_string()
        .bytes()
        .map(|b| format!("{b:02x}"))
        .collect();
    format!("\x1bPhook;{hex}\x1b\\").into_bytes()
}

/// The login command contains only a small initializer. No SFTP, curl or files.
fn shell_launch_script(nonce: &str, context: &str, child: bool) -> String {
    let frame = format!("\\033]6973;{nonce};{context};init;");
    let bash_init = format!(
        "command stty raw -echo || exit 124; printf '{frame}bash\\007'; while IFS= read -r -t 10 __ianvs_wire; do case \"$__ianvs_wire\" in ' true {nonce}-{context}; '*) break;; esac; done; case \"$__ianvs_wire\" in ' true {nonce}-{context}; '*) ;; *) command stty sane; exit 124;; esac; command stty sane; eval \"$__ianvs_wire\"; unset __ianvs_wire"
    );
    let fish_init = format!(
        "command stty raw -echo; or exit 124; printf '{frame}fish\\007'; set -l __ianvs_wire; while read __ianvs_wire; if string match -q ' true {nonce}-{context}; *' -- \"$__ianvs_wire\"; break; end; end; command stty sane; eval $__ianvs_wire; set -e __ianvs_wire"
    );
    // -g filters the very first command before rc files can change history options.
    // -f and -d defer user and global rc loading; /etc/zshenv is unavoidable.
    format!(
        r#"__iv_shell={target}
case "${{__iv_shell##*/}}" in
bash) exec "$__iv_shell" --norc -c {bash} -- "$__iv_shell" ;;
zsh) command stty icanon -echo kill '^U' || exit 124; printf '{frame}zsh\007'; exec "$__iv_shell" -d -f -g -i -o no_zle ;;
fish) exec "$__iv_shell" -i --init-command {fish} ;;
*) printf '\033]6973;{nonce};{context};ready;unsupported;0;unknown\007'; exec "$__iv_shell" -l ;;
esac"#,
        target = if child {
            "\"$1\""
        } else {
            "\"${SHELL:-/bin/sh}\""
        },
        bash = quote(&format!(
            "exec \"$1\" --rcfile <(printf %s {}) -i",
            quote(&bash_init)
        )),
        fish = quote(&fish_init)
    )
}

pub(crate) fn launcher(nonce: &str, context: &str) -> String {
    let script = shell_launch_script(nonce, context, false);
    // The SSH server parses this command with the account's current shell.
    // Fish and POSIX shells disagree on doubled backslashes in single quotes;
    // octal digits use only single backslashes and need no embedded apostrophes.
    let octal: String = script.bytes().map(|b| format!("\\0{b:03o}")).collect();
    let mut octal = octal;
    for marker in ["@@CONTEXT@@", "@@CHILD_NONCE@@"] {
        let placeholder: String = marker.bytes().map(|b| format!("\\0{b:03o}")).collect();
        octal = octal.replace(&placeholder, marker);
    }
    format!("exec /bin/sh -c 'eval \"$(printf %b \"{octal}\")\"'")
}

fn ssh_wrapper(nonce: &str, shell: &str) -> String {
    let body = include_str!("shell_bootstrap/ssh.bash")
        .replace("@@NONCE@@", nonce)
        .replace(
            "@@LAUNCHER@@",
            &quote(&launcher("@@CHILD_NONCE@@", "@@CONTEXT@@")),
        );
    if shell == "fish" {
        // An external helper preserves fish argv without requiring Bash syntax in fish.
        format!(
            "function ssh\n command bash -c {} -- $argv\nend\n",
            fish_quote(&(body + "\nssh \"$@\""))
        )
    } else {
        body
    }
}

pub(crate) fn wrapper(nonce: &str, shell: &str, wrap_ssh: bool) -> String {
    let helper = include_str!("shell_bootstrap/shells.bash")
        .replace("@@NONCE@@", nonce)
        .replace(
            "@@SHELL_LAUNCHER@@",
            &quote(&shell_launch_script("@@CHILD_NONCE@@", "@@CONTEXT@@", true)),
        );
    let mut wrappers = if shell == "fish" {
        ["bash", "zsh", "fish"]
            .into_iter()
            .map(|target| {
                format!(
                    "function {target}\n command bash -c {} -- $argv\nend\n",
                    fish_quote(&format!("{helper}\n__ianvs_run_shell {target} \"$@\""))
                )
            })
            .collect::<String>()
    } else {
        helper
    };
    if wrap_ssh {
        wrappers.push_str(&ssh_wrapper(nonce, shell));
    }
    wrappers
}

fn registration_check(shell: &str) -> &'static str {
    match shell {
        "bash" => include_str!("shell_bootstrap/check.bash"),
        "zsh" => include_str!("shell_bootstrap/check.zsh"),
        "fish" => include_str!("shell_bootstrap/check.fish"),
        _ => "",
    }
}

/// Local rc files use the same registration checks and authenticated receipt as
/// in-memory SSH/child-shell bootstrap. This never submits a terminal command.
pub(crate) fn local_ready(nonce: &str, shell: &str) -> String {
    let check = registration_check(shell);
    if shell == "fish" {
        format!(
            "\n{check}\nfunction __ianvs_report_initialization\n set -l registered 0\n set -l origin hook_conflict\n if __iv_valid\n  set registered 1\n  set origin checked\n end\n printf '\\033]6973;{nonce};root;ready;%s;%s;fish\\007' $origin $registered\nend\n__ianvs_report_initialization\nfunctions -e __iv_valid __ianvs_report_initialization\n"
        )
    } else {
        // Bash does not inherit DEBUG into ordinary functions. Capture its trap
        // at the call site, after all rc initialization, before entering ours.
        let debug_arg = if shell == "bash" {
            "\"$(trap -p DEBUG)\""
        } else {
            "''"
        };
        let call = if shell == "zsh" {
            // Check after .zlogin and all rc files, before the first hook prompt.
            // Keep the user's prompt hooks and remove only our one-shot entry.
            "precmd_functions=(__ianvs_report_initialization ${precmd_functions:#__ianvs_report_initialization})".into()
        } else {
            format!("__ianvs_report_initialization {debug_arg}")
        };
        let cleanup = if shell == "zsh" {
            "precmd_functions=(${precmd_functions:#__ianvs_report_initialization})"
        } else {
            ":"
        };
        let failed = if shell == "bash" {
            "else __ianvs_emit_shell_hook() { :; };"
        } else {
            ""
        };
        format!(
            "\n{check}\n__ianvs_report_initialization() {{\n local __iv_debug=\"${{1:-}}\" __iv_registered=0 __iv_source=hook_conflict\n if __iv_valid; then __iv_registered=1; __iv_source=checked; {failed} fi\n printf '\\033]6973;{nonce};root;ready;%s;%s;{shell}\\007' \"$__iv_source\" \"$__iv_registered\"\n {cleanup}\n unset -f __iv_valid\n}}\n{call}\n"
        )
    }
}

fn body(nonce: &str, context: &str, shell: &str, wrap: bool, login: bool) -> String {
    let source = match shell {
        "bash" => include_str!("shell_bootstrap/bash.sh")
            .replace("@@INSTALLER@@", crate::pty::bash_hook_source()),
        "zsh" => include_str!("shell_bootstrap/zsh.sh")
            .replace("@@INSTALLER@@", crate::pty::zsh_hook_source()),
        "fish" => include_str!("shell_bootstrap/fish.fish")
            .replace("@@INSTALLER@@", crate::pty::fish_shell_integration_source()),
        _ => return String::new(),
    };
    let wrapper = wrapper(nonce, shell, wrap);
    let source = source
        .replace("@@CHECK@@", registration_check(shell))
        .replace("@@NONCE@@", nonce)
        .replace("@@CONTEXT@@", context)
        .replace("@@LOGIN@@", if login { "1" } else { "0" })
        .replace("@@WRAPPER@@", &wrapper);
    let escaped = source.replace('\\', "\\\\").replace('\n', "\\n");
    let marker = format!(" true {nonce}-{context}; ");
    if shell == "fish" {
        format!(
            "{marker}eval (printf '%b' {} | string collect)\n",
            fish_quote(&escaped)
        )
    } else if shell == "zsh" {
        // Canonical input lets ^U discard keys typed before InitShell. Keep each
        // physical line below the PTY line limit, preserving one history event.
        let chunks: Vec<String> = escaped
            .chars()
            .collect::<Vec<_>>()
            .chunks(256)
            .map(|chars| quote(&chars.iter().collect::<String>()))
            .collect();
        format!(
            "\x15{marker}eval \"$(printf '%b' {})\"\n",
            chunks.join("\\\n")
        )
    } else {
        format!("{marker}eval \"$(printf '%b' {})\"\n", quote(&escaped))
    }
}

#[derive(Clone)]
struct Context {
    parent: String,
    started: Option<std::time::Instant>,
    completed: bool,
    available: bool,
    socket: Option<String>,
    host: String,
    user: String,
    port: u16,
    kind: &'static str,
    host_context: String,
}
impl Context {
    fn root() -> Self {
        Self {
            parent: String::new(),
            started: None,
            completed: false,
            available: true,
            socket: None,
            host: String::new(),
            user: String::new(),
            port: 22,
            kind: "root",
            host_context: "root".into(),
        }
    }
}
pub(crate) struct Bootstrap {
    nonce: String,
    wrap: bool,
    pending: Vec<u8>,
    contexts: BTreeMap<String, Context>,
    pub(crate) active: String,
    pub(crate) ready: bool,
    local_root: bool,
    input: Vec<u8>,
}
pub(crate) struct Processed {
    pub output: Vec<u8>,
    pub replies: Vec<Vec<u8>>,
}
fn checks(registered: bool) -> serde_json::Value {
    let mut map = serde_json::Map::new();
    for name in [
        "current_directory",
        "prompt_lifecycle",
        "command_start",
        "command_text",
        "command_finish",
        "exit_code",
        "shell_identity",
    ] {
        map.insert(
            name.into(),
            json!(if registered {
                "registered"
            } else {
                "unavailable"
            }),
        );
    }
    for name in [
        "hostname",
        "username",
        "integration_version",
        "prompt_navigation",
        "command_output_ranges",
        "user_variables",
    ] {
        map.insert(name.into(), json!("unverified"));
    }
    map.into()
}
fn valid_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-')
}
impl Bootstrap {
    pub(crate) fn new(nonce: String, wrap: bool) -> Self {
        Self {
            nonce,
            wrap,
            pending: Vec::new(),
            contexts: BTreeMap::from([("root".into(), Context::root())]),
            active: "root".into(),
            ready: false,
            local_root: false,
            input: Vec::new(),
        }
    }
    pub(crate) fn checking(&self) -> bool {
        // Local rc files may ask for input (for example a keychain password).
        // There is no injected payload to protect at the local root.
        !(self.local_root && self.active == "root")
            && self
                .contexts
                .get(&self.active)
                .is_some_and(|ctx| ctx.started.is_some() && !ctx.completed)
    }
    fn take_input(&mut self) -> Vec<u8> {
        if self.checking() {
            Vec::new()
        } else {
            std::mem::take(&mut self.input)
        }
    }
    fn context_token<'a>(&'a self, id: &'a str) -> &'a str {
        if id == "root" { &self.nonce } else { id }
    }
    pub(crate) fn launch_command(&self) -> String {
        launcher(&self.nonce, "root")
    }
    fn event(&self, ctx: &str, name: &str) -> serde_json::Value {
        let context = &self.contexts[ctx];
        json!({"hook":name, "context_id":ctx, "parent_context_id":context.parent,
            "host":context.host,"user":context.user,"port":context.port,
            "context_kind":context.kind,"host_context_id":context.host_context,
            "sftp_route":context.available && self.contexts.get(&context.host_context).is_some_and(|host| host.socket.is_some())})
    }
    fn finish(&mut self, ctx: &str, source: &str, registered: bool, shell: &str) -> Vec<u8> {
        self.contexts.get_mut(ctx).unwrap().completed = true;
        if ctx == "root" {
            self.ready = true;
        }
        let mut event = self.event(ctx, "bootstrap.ready");
        event["source"] = json!(source);
        event["registered"] = json!(registered);
        event["shell"] = json!(shell);
        event["checks"] = if source == "timeout" {
            checks(false)
                .as_object()
                .unwrap()
                .keys()
                .map(|key| (key.clone(), json!("unverified")))
                .collect::<serde_json::Map<_, _>>()
                .into()
        } else {
            checks(registered)
        };
        hook(event)
    }
    pub(crate) fn feed(&mut self, bytes: &[u8]) -> Processed {
        self.pending.extend_from_slice(bytes);
        let mut result = Processed {
            output: self.expire_due(),
            replies: Vec::new(),
        };
        loop {
            let Some(start) = self.pending.windows(PREFIX.len()).position(|p| p == PREFIX) else {
                let keep = (1..PREFIX.len())
                    .rev()
                    .find(|&n| self.pending.ends_with(&PREFIX[..n]))
                    .unwrap_or(0);
                let len = self.pending.len() - keep;
                result.output.extend(self.pending.drain(..len));
                break;
            };
            result.output.extend(self.pending.drain(..start));
            let Some(end) = self.pending.iter().position(|&b| b == 7) else {
                if self.pending.len() > MAX_FRAME {
                    result.output.push(self.pending.remove(0));
                    continue;
                }
                break;
            };
            let frame: Vec<_> = self.pending.drain(..=end).collect();
            let text = String::from_utf8_lossy(&frame[PREFIX.len()..frame.len() - 1]);
            let fields: Vec<_> = text.split(';').collect();
            if fields.len() < 4 {
                result.output.extend(frame);
                continue;
            }
            let authority = if matches!(fields[2], "enter" | "enter_shell") {
                fields[3]
            } else {
                fields[1]
            };
            if !self.contexts.contains_key(authority) || fields[0] != self.context_token(authority)
            {
                result.output.extend(frame);
                continue;
            }
            let ctx = fields[1];
            if !valid_id(ctx) {
                continue;
            }
            match fields[2] {
                "enter"
                    if self.wrap
                        && fields.len() == 8
                        && fields[3] == self.active
                        && self.contexts.len() < 128
                        && !self.contexts.contains_key(ctx) =>
                {
                    let socket = fields[4];
                    if socket.len() > 104
                        || !socket.starts_with('/')
                        || !socket
                            .bytes()
                            .all(|b| b.is_ascii_alphanumeric() || b"_./:@+,-".contains(&b))
                    {
                        continue;
                    }
                    if fields[5..7]
                        .iter()
                        .any(|s| s.len() > 255 || s.chars().any(char::is_control))
                    {
                        continue;
                    }
                    let Ok(port) = fields[7].parse::<u16>() else {
                        continue;
                    };
                    self.contexts.insert(
                        ctx.into(),
                        Context {
                            parent: fields[3].into(),
                            socket: Some(socket.into()),
                            host: fields[5].into(),
                            user: fields[6].into(),
                            port,
                            kind: "ssh",
                            host_context: ctx.into(),
                            ..Context::root()
                        },
                    );
                    self.active = ctx.into();
                    result
                        .output
                        .extend(hook(self.event(ctx, "bootstrap.checking")));
                }
                "enter_shell"
                    if fields.len() == 5
                        && fields[3] == self.active
                        && matches!(fields[4], "bash" | "zsh" | "fish")
                        && self.contexts.len() < 128
                        && !self.contexts.contains_key(ctx) =>
                {
                    let parent = self.contexts[fields[3]].clone();
                    self.contexts.insert(
                        ctx.into(),
                        Context {
                            parent: fields[3].into(),
                            host: parent.host,
                            user: parent.user,
                            port: parent.port,
                            host_context: parent.host_context,
                            kind: "shell",
                            ..Context::root()
                        },
                    );
                    self.active = ctx.into();
                    result
                        .output
                        .extend(hook(self.event(ctx, "bootstrap.checking")));
                }
                "init" if matches!(fields[3], "bash" | "zsh" | "fish") && ctx == self.active => {
                    if let Some(context) = self.contexts.get_mut(ctx) {
                        if context.started.is_none() && !context.completed {
                            context.started = Some(std::time::Instant::now());
                            result
                                .output
                                .extend(hook(self.event(ctx, "bootstrap.checking")));
                            result.replies.push(
                                body(
                                    self.context_token(ctx),
                                    ctx,
                                    fields[3],
                                    self.wrap,
                                    self.contexts[ctx].kind != "shell",
                                )
                                .into_bytes(),
                            );
                        }
                    }
                }
                "ready" if fields.len() == 6 && ctx == self.active => {
                    if let Some(context) = self.contexts.get(ctx) {
                        if !context.completed
                            && (context.started.is_some() || fields[3] == "unsupported")
                        {
                            result.output.extend(self.finish(
                                ctx,
                                fields[3],
                                fields[4] == "1",
                                fields[5],
                            ));
                        }
                    }
                }
                "resume" if self.contexts.contains_key(ctx) && ctx != self.active => {
                    let mut child = self.active.clone();
                    let mut leaving = Vec::new();
                    while let Some(context) = self.contexts.get(&child) {
                        if child == ctx {
                            break;
                        }
                        leaving.push(child.clone());
                        child = context.parent.clone();
                    }
                    if child != ctx {
                        continue;
                    }
                    // Report retired IDs before pruning; old editors must fail closed.
                    for id in &leaving {
                        self.contexts.get_mut(id).unwrap().available = false;
                    }
                    self.active = ctx.into();
                    let mut event = self.event(ctx, "bootstrap.resume");
                    event["retired_contexts"] = json!(leaving);
                    result.output.extend(hook(event));
                    self.contexts.retain(|_, context| context.available);
                }
                _ => {}
            }
        }
        result
    }
    pub(crate) fn expire_due(&mut self) -> Vec<u8> {
        let id = self.active.clone();
        if self.contexts.get(&id).is_some_and(|ctx| {
            !ctx.completed && ctx.started.is_some_and(|t| t.elapsed() >= TIMEOUT)
        }) {
            return self.finish(&id, "timeout", false, "unknown");
        }
        Vec::new()
    }
    pub(crate) fn expire(&mut self) -> Vec<u8> {
        self.degrade("timeout")
    }
    pub(crate) fn degrade(&mut self, reason: &str) -> Vec<u8> {
        if self.ready {
            return Vec::new();
        }
        self.finish("root", reason, false, "unknown")
    }
    pub(crate) fn route_for(&self, id: &str) -> anyhow::Result<Vec<String>> {
        let host_context = self
            .contexts
            .get(&self.active)
            .map(|ctx| ctx.host_context.as_str());
        if id != self.active && Some(id) != host_context {
            anyhow::bail!(
                "SSH shell context is not active; return to it before starting another file operation"
            );
        }
        let mut route = Vec::new();
        let mut id = id;
        loop {
            let ctx = self
                .contexts
                .get(id)
                .filter(|c| c.available)
                .ok_or_else(|| anyhow::anyhow!("SSH shell context is no longer available"))?;
            if let Some(socket) = &ctx.socket {
                route.push(socket.clone());
            }
            if ctx.parent.is_empty() {
                break;
            }
            id = &ctx.parent;
        }
        route.reverse();
        Ok(route)
    }
}

/// Multiplex exclusively through known sockets. If a master disappeared, the
/// disabled ProxyCommand prevents OpenSSH from opening a new network connection.
pub(crate) fn sftp_command(route: &[String]) -> Option<String> {
    let mut command: Option<String> = None;
    for socket in route.iter().rev() {
        let prefix = format!(
            "ssh -F /dev/null -S {} -o ControlMaster=no -o BatchMode=yes -o ProxyCommand=false -o ClearAllForwardings=yes -T",
            quote(socket)
        );
        command = Some(match command {
            None => format!("{prefix} -s ianvs-mux sftp"),
            Some(inner) => format!("{prefix} ianvs-mux {}", quote(&inner)),
        });
    }
    command
}

struct SharedWriter(Arc<Mutex<Box<dyn Write + Send>>>);
struct UserWriter {
    writer: SharedWriter,
    state: Arc<Mutex<Bootstrap>>,
}
impl Write for UserWriter {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        let mut state = self.state.lock().unwrap();
        if state.checking() {
            if state.input.len() + bytes.len() > 65536 {
                return Err(std::io::Error::other(
                    "shell initialization input buffer is full",
                ));
            }
            state.input.extend(bytes);
            Ok(bytes.len())
        } else {
            self.writer.write(bytes)
        }
    }
    fn flush(&mut self) -> std::io::Result<()> {
        self.writer.flush()
    }
}
impl Write for SharedWriter {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().write(bytes)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        self.0.lock().unwrap().flush()
    }
}
struct BootstrapReader {
    receiver: std::sync::mpsc::Receiver<std::io::Result<Vec<u8>>>,
    writer: SharedWriter,
    state: Arc<Mutex<Bootstrap>>,
    queued: VecDeque<u8>,
}
impl Drop for BootstrapReader {
    fn drop(&mut self) {
        self.state.lock().unwrap().contexts.clear();
    }
}
impl Read for BootstrapReader {
    fn read(&mut self, out: &mut [u8]) -> std::io::Result<usize> {
        if out.is_empty() {
            return Ok(0);
        }
        while self.queued.is_empty() {
            match self
                .receiver
                .recv_timeout(std::time::Duration::from_millis(100))
            {
                Ok(bytes) => {
                    let processed = self.state.lock().unwrap().feed(&bytes?);
                    for reply in processed.replies {
                        self.writer.write_all(&reply)?;
                        self.writer.flush()?;
                    }
                    self.queued.extend(processed.output);
                }
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                    self.queued.extend(self.state.lock().unwrap().expire_due())
                }
                Err(_) => {
                    self.queued
                        .extend(std::mem::take(&mut self.state.lock().unwrap().pending));
                    if self.queued.is_empty() {
                        return Ok(0);
                    }
                }
            }
        }
        let input = self.state.lock().unwrap().take_input();
        if !input.is_empty() {
            self.writer.write_all(&input)?;
            self.writer.flush()?;
        }
        let n = out.len().min(self.queued.len());
        for byte in &mut out[..n] {
            *byte = self.queued.pop_front().unwrap();
        }
        Ok(n)
    }
}
pub(crate) fn wrap_local(
    mut reader: Box<dyn Read + Send>,
    writer: Box<dyn Write + Send>,
    nonce: String,
    wrap_ssh: bool,
) -> anyhow::Result<(
    Box<dyn Read + Send>,
    Box<dyn Write + Send>,
    crate::ssh::SshSftpClient,
)> {
    let writer = Arc::new(Mutex::new(writer));
    let mut bootstrap = Bootstrap::new(nonce, wrap_ssh);
    bootstrap.local_root = true;
    bootstrap.contexts.get_mut("root").unwrap().started = Some(std::time::Instant::now());
    let initial = hook(bootstrap.event("root", "bootstrap.checking"));
    let state = Arc::new(Mutex::new(bootstrap));
    let sftp = crate::ssh::local_sftp_client(state.clone())?;
    let (sender, receiver) = std::sync::mpsc::sync_channel(8);
    std::thread::Builder::new()
        .name("ianvs-shell-bootstrap".into())
        .spawn(move || {
            loop {
                let mut bytes = vec![0; 8192];
                match reader.read(&mut bytes) {
                    Ok(0) => break,
                    Ok(n) => {
                        bytes.truncate(n);
                        if sender.send(Ok(bytes)).is_err() {
                            break;
                        }
                    }
                    Err(e) => {
                        let _ = sender.send(Err(e));
                        break;
                    }
                }
            }
        })?;
    Ok((
        Box::new(BootstrapReader {
            receiver,
            writer: SharedWriter(writer.clone()),
            state: state.clone(),
            queued: initial.into(),
        }),
        Box::new(UserWriter {
            writer: SharedWriter(writer),
            state,
        }),
        sftp,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn split_frames_reject_foreign_duplicate_and_late_init() {
        let mut bootstrap = Bootstrap::new("test".into(), true);
        assert!(
            bootstrap
                .feed(b"\x1b]6973;wrong;root;init;bash\x07")
                .replies
                .is_empty()
        );
        assert!(
            bootstrap
                .feed(b"prefix\x1b]6973;test;root;ini")
                .replies
                .is_empty()
        );
        let accepted = bootstrap.feed(b"t;bash\x07suffix");
        assert_eq!(accepted.replies.len(), 1);
        assert_eq!(
            accepted.replies[0].iter().filter(|&&b| b == b'\n').count(),
            1
        );
        assert!(
            bootstrap
                .feed(b"\x1b]6973;test;root;init;bash\x07")
                .replies
                .is_empty()
        );
        let mut bootstrap = Bootstrap::new("test".into(), true);
        bootstrap.expire();
        assert!(
            bootstrap
                .feed(b"\x1b]6973;test;root;init;bash\x07")
                .replies
                .is_empty()
        );
    }
    #[test]
    fn nested_routes_resume_the_parent() {
        let mut bootstrap = Bootstrap::new("test".into(), true);
        bootstrap
            .feed(b"\x1b]6973;test;a;enter;root;/tmp/a;a;user;22\x07\x1b]6973;a;a;init;bash\x07");
        bootstrap.feed(b"\x1b]6973;a;b;enter;a;/tmp/b;b;user;22\x07\x1b]6973;b;b;init;bash\x07");
        assert_eq!(
            bootstrap.route_for(&bootstrap.active).unwrap(),
            vec!["/tmp/a", "/tmp/b"]
        );
        bootstrap.feed(b"\x1b]6973;a;a;resume;done\x07");
        assert_eq!(
            bootstrap.route_for(&bootstrap.active).unwrap(),
            vec!["/tmp/a"]
        );
    }
    #[test]
    fn child_shell_reuses_host_route_and_does_not_authorize_other_hosts() {
        let mut b = Bootstrap::new("root-secret".into(), true);
        b.feed(b"\x1b]6973;root-secret;a;enter;root;/tmp/a;a;user;22\x07");
        let checked = b.feed(b"\x1b]6973;a;shell-a;enter_shell;a;bash\x07");
        let event = events(&checked.output).pop().unwrap();
        assert_eq!(event["context_kind"], "shell");
        assert_eq!(event["host_context_id"], "a");
        assert_eq!(event["sftp_route"], true);
        assert_eq!(b.route_for("a").unwrap(), vec!["/tmp/a"]);
        assert_eq!(b.route_for("shell-a").unwrap(), vec!["/tmp/a"]);
        assert!(b.route_for("root").is_err());
        b.feed(b"\x1b]6973;shell-a;c;enter;shell-a;/tmp/c;c;user;22\x07");
        assert_eq!(b.route_for("c").unwrap(), vec!["/tmp/a", "/tmp/c"]);
        assert!(b.route_for("a").is_err());
        b.feed(b"\x1b]6973;shell-a;shell-a;resume;done\x07");
        assert_eq!(b.route_for("a").unwrap(), vec!["/tmp/a"]);
        b.feed(b"\x1b]6973;a;a;resume;done\x07");
        assert!(b.route_for("shell-a").is_err());
        assert_eq!(b.route_for("a").unwrap(), vec!["/tmp/a"]);
    }
    pub(super) fn events(output: &[u8]) -> Vec<serde_json::Value> {
        regex::bytes::Regex::new(r"\x1bPhook;([0-9a-f]+)\x1b\\")
            .unwrap()
            .captures_iter(output)
            .filter_map(|capture| {
                let hex = &capture[1];
                let bytes: Vec<u8> = hex
                    .chunks_exact(2)
                    .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
                    .collect();
                serde_json::from_slice(&bytes).ok()
            })
            .collect()
    }
    #[test]
    fn stale_ready_cycles_and_closed_endpoints_are_rejected() {
        let mut b = Bootstrap::new("test".into(), true);
        assert!(
            b.feed(b"\x1b]6973;test;root;ready;installed;1;bash\x07")
                .output
                .is_empty()
        );
        b.feed(b"\x1b]6973;test;a;enter;root;/tmp/a;a;user;22\x07");
        b.feed(b"\x1b]6973;a;root;enter;a;/tmp/b;b;user;22\x07");
        assert_eq!(b.active, "a");
        b.feed(b"\x1b]6973;a;a;init;bash\x07");
        b.contexts.get_mut("a").unwrap().started = Some(std::time::Instant::now() - TIMEOUT);
        assert!(!b.expire_due().is_empty());
        assert!(
            b.feed(b"\x1b]6973;a;a;ready;installed;1;bash\x07")
                .output
                .is_empty()
        );
        let pinned = b.route_for("a").unwrap();
        b.feed(b"\x1b]6973;test;root;resume;done\x07");
        assert!(b.route_for("a").is_err());
        assert_eq!(pinned, vec!["/tmp/a"]);
        assert!(
            sftp_command(&pinned)
                .unwrap()
                .contains("ProxyCommand=false")
        );
    }
    #[test]
    fn a_child_cannot_forge_its_parents_control_frames() {
        let mut b = Bootstrap::new("parent-secret".into(), true);
        b.feed(b"\x1b]6973;parent-secret;a;enter;root;/tmp/a;a;user;22\x07");
        b.feed(b"\x1b]6973;a;root;resume;done\x07");
        b.feed(b"\x1b]6973;a;forged;enter;root;/tmp/other;other;user;22\x07");
        assert_eq!(b.active, "a");
        assert!(!b.contexts.contains_key("forged"));
        assert!(b.route_for("root").is_err());
        let body = body(b.context_token("a"), "a", "bash", true, true);
        assert!(!body.contains("parent-secret"));
        assert!(launcher("@@CHILD_NONCE@@", "@@CONTEXT@@").contains("@@CHILD_NONCE@@"));
    }
    #[cfg(unix)]
    fn real_shell(shell: &str, rc: &str, expected: &str) {
        use portable_pty::{CommandBuilder, PtySize, native_pty_system};
        let home = tempfile::tempdir().unwrap();
        std::fs::write(
            home.path().join(".bash_profile"),
            format!("HISTCONTROL=\nHISTFILE=~/.bash_history\n{rc}\n"),
        )
        .unwrap();
        std::fs::write(home.path().join(".zshrc"), format!("unsetopt hist_ignore_space\nHISTFILE=~/.zsh_history\nHISTSIZE=100\nSAVEHIST=100\n{rc}\n")).unwrap();
        let pair = native_pty_system().openpty(PtySize::default()).unwrap();
        let mut bootstrap = Bootstrap::new(token(), false);
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
        let (tx, rx) = std::sync::mpsc::channel();
        let reader_thread = std::thread::spawn(move || {
            loop {
                let mut buf = [0; 8192];
                match reader.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if tx.send(buf[..n].to_vec()).is_err() {
                            break;
                        }
                    }
                }
            }
        });
        let mut output = Vec::new();
        let deadline = std::time::Instant::now() + TIMEOUT;
        while !bootstrap.ready && std::time::Instant::now() < deadline {
            if let Ok(bytes) = rx.recv_timeout(std::time::Duration::from_millis(100)) {
                let result = bootstrap.feed(&bytes);
                output.extend(result.output);
                for reply in result.replies {
                    writer.write_all(&reply).unwrap();
                    writer.flush().unwrap();
                }
            }
        }
        let initial_events = events(&output);
        let initial_ready = initial_events
            .iter()
            .find(|e| e["hook"] == "bootstrap.ready")
            .unwrap();
        assert_eq!(
            initial_ready["checks"]["command_start"],
            if expected == "hook_conflict" {
                "unavailable"
            } else {
                "registered"
            }
        );
        assert_eq!(
            initial_ready["checks"]["command_finish"],
            initial_ready["checks"]["command_start"]
        );
        assert!(
            !initial_events
                .iter()
                .any(|e| e["hook"] == "preexec" || e["hook"] == "command_finished")
        );
        writer
            .write_all(b"false\nprintf '__BOOTSTRAP_OK__\\n'\nexit\n")
            .unwrap();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
        while std::time::Instant::now() < deadline {
            match rx.recv_timeout(std::time::Duration::from_millis(50)) {
                Ok(bytes) => output.extend(bootstrap.feed(&bytes).output),
                Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => break,
                Err(_) => {}
            }
        }
        let exit_deadline = std::time::Instant::now() + std::time::Duration::from_secs(1);
        while child.try_wait().unwrap().is_none() && std::time::Instant::now() < exit_deadline {
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        let exited = child.try_wait().unwrap().is_some();
        let _ = child.kill();
        let _ = child.wait();
        drop(writer);
        drop(pair.master);
        drop(rx);
        let _ = reader_thread.join();
        let text = String::from_utf8_lossy(&output);
        assert!(exited && bootstrap.ready, "shell {shell}: {text}");
        let events = events(&output);
        let ready = events
            .iter()
            .find(|e| e["hook"] == "bootstrap.ready")
            .unwrap();
        assert_eq!(ready["source"], expected, "{text}");
        assert!(
            !text.contains("parse error") && !text.contains("syntax error"),
            "{text}"
        );
        if expected != "hook_conflict" {
            assert_eq!(ready["registered"], true, "{text}");
            assert!(
                events.iter().any(|e| e["hook"] == "command_finished"
                    && e["command"] == "false"
                    && e["exit_code"] == 1),
                "{events:?}"
            );
            assert!(
                !events.iter().any(|e| e["hook"] == "preexec"
                    && e["command"]
                        .as_str()
                        .is_some_and(|s| s.contains("__iv_") || s.starts_with("eval "))),
                "{events:?}"
            );
        } else {
            assert_eq!(ready["registered"], false);
        }
        let history = std::fs::read_to_string(home.path().join(if shell.ends_with("zsh") {
            ".zsh_history"
        } else {
            ".bash_history"
        }))
        .unwrap();
        assert!(
            history.contains("false"),
            "history positive control missing: {history}"
        );
        assert!(
            !history.contains("__ianvs")
                && !history.contains("__iv_")
                && !history.contains("eval "),
            "{history}"
        );
    }
    #[cfg(unix)]
    #[test]
    fn bash_memory_bootstrap() {
        real_shell("/bin/bash", "", "installed");
    }
    #[cfg(unix)]
    #[test]
    fn bash_keeps_foreign_debug_trap() {
        real_shell("/bin/bash", "trap ':' DEBUG", "hook_conflict");
    }
    #[cfg(unix)]
    #[test]
    fn bash_repairs_stale_flag() {
        real_shell(
            "/bin/bash",
            "__IANVS_SHELL_INTEGRATION_LOADED=1",
            "installed",
        );
    }
    #[cfg(unix)]
    #[test]
    fn bash_reuses_server_hooks() {
        real_shell(
            "/bin/bash",
            &format!(
                "IANVS_SHELL_INTEGRATION=1\n{}",
                crate::pty::bash_hook_source()
            ),
            "reused",
        );
    }
    #[cfg(unix)]
    #[test]
    fn bash_rejects_ambiguous_prompt_chains_without_reinstalling() {
        real_shell(
            "/bin/bash",
            &format!(
                "IANVS_SHELL_INTEGRATION=1\n{}\nPROMPT_COMMAND+='; :'\n",
                crate::pty::bash_hook_source()
            ),
            "hook_conflict",
        );
    }
    #[cfg(unix)]
    #[test]
    fn zsh_memory_bootstrap() {
        if std::path::Path::new("/bin/zsh").exists() {
            real_shell("/bin/zsh", "", "installed");
        }
    }
}

#[cfg(all(test, unix))]
#[path = "shell_bootstrap/acceptance.rs"]
mod acceptance;
