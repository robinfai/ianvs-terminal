use crate::model::{TerminalEmulation, TerminalProfile};
use portable_pty::{CommandBuilder, MasterPty, PtySize, native_pty_system};
use std::collections::BTreeMap;
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static SHELL_INTEGRATION_PROXY_COUNTER: AtomicU64 = AtomicU64::new(0);

pub struct PtyRuntime {
    pub master: Box<dyn MasterPty + Send>,
    pub reader: Box<dyn Read + Send>,
    pub writer: Box<dyn Write + Send>,
    pub child: Box<dyn portable_pty::Child + Send + Sync>,
    pub child_pid: Option<u32>,
    pub(crate) shell_integration_proxy: Option<ShellIntegrationProxy>,
}

pub(crate) struct ShellIntegrationProxy {
    path: PathBuf,
}

impl ShellIntegrationProxy {
    fn new(path: PathBuf) -> Self {
        Self { path }
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for ShellIntegrationProxy {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

struct CommandPlan {
    program: String,
    args: Vec<String>,
    env: BTreeMap<String, String>,
    cwd: Option<String>,
    shell_integration_proxy: Option<ShellIntegrationProxy>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ShellIntegrationKind {
    Zsh,
    Bash,
    Fish,
}

impl ShellIntegrationKind {
    fn from_program(program: &str) -> Option<Self> {
        match Path::new(program)
            .file_name()
            .and_then(|name| name.to_str())
        {
            Some("zsh") => Some(Self::Zsh),
            Some("bash") => Some(Self::Bash),
            Some("fish") => Some(Self::Fish),
            _ => None,
        }
    }

    fn temp_dir_name(self) -> &'static str {
        match self {
            Self::Zsh => "zdotdir",
            Self::Bash => "bash",
            Self::Fish => "fish",
        }
    }
}

pub fn spawn_pty(profile: &TerminalProfile, rows: u16, cols: u16) -> anyhow::Result<PtyRuntime> {
    let pty_system = native_pty_system();
    let pair = pty_system.openpty(PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    })?;

    let plan = build_command_plan(profile);

    let mut command = CommandBuilder::new(&plan.program);
    for arg in &plan.args {
        command.arg(arg);
    }
    if let Some(cwd) = &plan.cwd {
        command.cwd(cwd);
    }
    for (key, value) in &plan.env {
        command.env(key, value);
    }
    match profile.terminal.emulation {
        TerminalEmulation::Xterm256 => {
            command.env("TERM", "xterm-256color");
            command.env("COLORTERM", "truecolor");
        }
        TerminalEmulation::Vt220 => {
            command.env("TERM", "vt220");
            command.env_remove("COLORTERM");
        }
    }

    let child = pair.slave.spawn_command(command)?;
    let child_pid = child.process_id();
    let reader = pair.master.try_clone_reader()?;
    let writer = pair.master.take_writer()?;

    Ok(PtyRuntime {
        master: pair.master,
        reader,
        writer,
        child,
        child_pid,
        shell_integration_proxy: plan.shell_integration_proxy,
    })
}

fn build_command_plan(profile: &TerminalProfile) -> CommandPlan {
    build_command_plan_with_proxy_factory(profile, create_shell_integration_proxy)
}

fn build_command_plan_with_proxy_factory<F>(
    profile: &TerminalProfile,
    create_proxy: F,
) -> CommandPlan
where
    F: Fn(ShellIntegrationKind, &TerminalProfile, &str) -> std::io::Result<ShellIntegrationProxy>,
{
    let program = if profile.launch.program.is_empty() {
        crate::platform::macos::default_shell()
    } else {
        profile.launch.program.clone()
    };

    let mut env = profile.launch.env.clone();
    let mut args = profile.launch.args.clone();
    let mut shell_integration_proxy = None;

    if let Some(kind) = shell_integration_kind(profile, &program) {
        if let Ok(proxy) = create_proxy(kind, profile, &program) {
            match kind {
                ShellIntegrationKind::Zsh => apply_zsh_shell_integration(&mut env, &proxy),
                ShellIntegrationKind::Bash => {
                    apply_bash_shell_integration(&mut args, &mut env, &proxy)
                }
                ShellIntegrationKind::Fish => {
                    apply_fish_shell_integration(&mut args, &mut env, &proxy)
                }
            }
            shell_integration_proxy = Some(proxy);
        }
    }

    CommandPlan {
        program,
        args,
        env,
        cwd: profile.launch.cwd.clone(),
        shell_integration_proxy,
    }
}

fn shell_integration_kind(
    profile: &TerminalProfile,
    program: &str,
) -> Option<ShellIntegrationKind> {
    if !supports_unix_shell_integration()
        || !profile.shell_integration.enabled
        || profile.terminal.emulation != TerminalEmulation::Xterm256
        || !shell_hook_helpers_available(&profile.launch.env)
    {
        return None;
    }
    let kind = ShellIntegrationKind::from_program(program)?;
    if !shell_integration_args_supported(kind, &profile.launch.args) {
        return None;
    }
    Some(kind)
}

fn shell_integration_args_supported(kind: ShellIntegrationKind, args: &[String]) -> bool {
    match kind {
        ShellIntegrationKind::Zsh => {
            args.is_empty() || (args.len() == 1 && (args[0] == "-l" || args[0] == "--login"))
        }
        ShellIntegrationKind::Bash | ShellIntegrationKind::Fish => args.is_empty(),
    }
}

#[cfg(unix)]
fn supports_unix_shell_integration() -> bool {
    true
}

#[cfg(not(unix))]
fn supports_unix_shell_integration() -> bool {
    false
}

#[cfg(test)]
fn supports_zdotdir_proxy() -> bool {
    supports_unix_shell_integration()
}

fn apply_zsh_shell_integration(env: &mut BTreeMap<String, String>, proxy: &ShellIntegrationProxy) {
    let original_zdotdir = original_zdotdir(env);
    env.insert("FLUTTERM_SHELL_INTEGRATION".to_string(), "1".to_string());
    env.insert(
        "FLUTTERM_ORIGINAL_ZDOTDIR_WAS_SET".to_string(),
        if original_zdotdir.is_some() { "1" } else { "0" }.to_string(),
    );
    env.insert(
        "FLUTTERM_ORIGINAL_ZDOTDIR".to_string(),
        original_zdotdir.unwrap_or_default(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        proxy.path().to_string_lossy().into_owned(),
    );
}

fn apply_bash_shell_integration(
    args: &mut Vec<String>,
    env: &mut BTreeMap<String, String>,
    proxy: &ShellIntegrationProxy,
) {
    env.insert("FLUTTERM_SHELL_INTEGRATION".to_string(), "1".to_string());
    args.clear();
    args.push("--rcfile".to_string());
    args.push(proxy.path().join(".bashrc").to_string_lossy().into_owned());
}

fn apply_fish_shell_integration(
    args: &mut Vec<String>,
    env: &mut BTreeMap<String, String>,
    proxy: &ShellIntegrationProxy,
) {
    env.insert("FLUTTERM_SHELL_INTEGRATION".to_string(), "1".to_string());
    env.insert(
        "FLUTTERM_FISH_INIT".to_string(),
        proxy
            .path()
            .join("init.fish")
            .to_string_lossy()
            .into_owned(),
    );
    args.clear();
    args.push("--init-command".to_string());
    args.push(r#"source "$FLUTTERM_FISH_INIT""#.to_string());
}

fn original_zdotdir(env: &BTreeMap<String, String>) -> Option<String> {
    env.get("ZDOTDIR")
        .cloned()
        .or_else(|| std::env::var("ZDOTDIR").ok())
}

fn shell_hook_helpers_available(env: &BTreeMap<String, String>) -> bool {
    executable_on_path("od", env) && executable_on_path("tr", env)
}

fn executable_on_path(name: &str, env: &BTreeMap<String, String>) -> bool {
    let Some(path) = env
        .get("PATH")
        .cloned()
        .or_else(|| std::env::var("PATH").ok())
    else {
        return false;
    };
    path.split(':').any(|dir| {
        let candidate = Path::new(if dir.is_empty() { "." } else { dir }).join(name);
        is_executable_file(&candidate)
    })
}

#[cfg(unix)]
fn is_executable_file(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;

    fs::metadata(path)
        .map(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable_file(_path: &Path) -> bool {
    false
}

fn create_shell_integration_proxy(
    kind: ShellIntegrationKind,
    _profile: &TerminalProfile,
    _program: &str,
) -> std::io::Result<ShellIntegrationProxy> {
    create_shell_integration_proxy_in(kind, &std::env::temp_dir())
}

fn create_shell_integration_proxy_in(
    kind: ShellIntegrationKind,
    base_dir: &Path,
) -> std::io::Result<ShellIntegrationProxy> {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    for attempt in 0..100_u64 {
        let counter = SHELL_INTEGRATION_PROXY_COUNTER.fetch_add(1, Ordering::Relaxed);
        let path = base_dir.join(format!(
            "flutterm-{}-shell-integration-{}-{timestamp}-{counter}-{attempt}",
            kind.temp_dir_name(),
            process::id()
        ));
        match fs::create_dir(&path) {
            Ok(()) => {
                if let Err(error) = write_shell_integration_proxy_files(kind, &path) {
                    let _ = fs::remove_dir_all(&path);
                    return Err(error);
                }
                return Ok(ShellIntegrationProxy::new(path));
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
    Err(std::io::Error::new(
        std::io::ErrorKind::AlreadyExists,
        "could not allocate unique flutterm shell integration proxy",
    ))
}

fn write_shell_integration_proxy_files(
    kind: ShellIntegrationKind,
    dir: &Path,
) -> std::io::Result<()> {
    match kind {
        ShellIntegrationKind::Zsh => write_zsh_proxy_files(dir),
        ShellIntegrationKind::Bash => fs::write(dir.join(".bashrc"), BASH_RCFILE),
        ShellIntegrationKind::Fish => fs::write(dir.join("init.fish"), FISH_INIT),
    }
}

fn write_zsh_proxy_files(dir: &Path) -> std::io::Result<()> {
    fs::write(dir.join(".zshenv"), zsh_source_proxy(".zshenv"))?;
    fs::write(dir.join(".zprofile"), zsh_source_proxy(".zprofile"))?;
    fs::write(
        dir.join(".zshrc"),
        format!(
            "{}\n{}\n__flutterm_source_original_zdotfile \".zshrc\"\n__flutterm_install_shell_hooks >/dev/null 2>&1 || true\n__flutterm_suspend_startup_prompt_sp >/dev/null 2>&1 || true\n__flutterm_restore_zdotdir >/dev/null 2>&1 || true\n",
            ZSH_PROXY_COMMON, ZSH_HOOK_INSTALLER
        ),
    )?;
    fs::write(
        dir.join(".zlogin"),
        format!(
            "{}\n__flutterm_source_original_zdotfile \".zlogin\"\n__flutterm_restore_zdotdir >/dev/null 2>&1 || true\n",
            ZSH_PROXY_COMMON
        ),
    )?;
    fs::write(
        dir.join(".zlogout"),
        format!(
            "{}\n__flutterm_source_original_zdotfile \".zlogout\"\n",
            ZSH_PROXY_COMMON
        ),
    )?;
    Ok(())
}

fn zsh_source_proxy(file_name: &str) -> String {
    format!("{ZSH_PROXY_COMMON}\n__flutterm_source_original_zdotfile \"{file_name}\"\n")
}

const ZSH_PROXY_COMMON: &str = r#"
__flutterm_original_zdotdir() {
  emulate -L zsh
  if [[ "${FLUTTERM_ORIGINAL_ZDOTDIR_WAS_SET:-0}" == "1" ]]; then
    builtin print -r -- "${FLUTTERM_ORIGINAL_ZDOTDIR:-}"
  else
    builtin print -r -- "${HOME:-}"
  fi
}

__flutterm_source_original_zdotfile() {
  local __flutterm_file="$1"
  local __flutterm_dir="$(__flutterm_original_zdotdir)"
  [[ -n "$__flutterm_dir" ]] || return 0
  local __flutterm_path="$__flutterm_dir/$__flutterm_file"
  [[ -r "$__flutterm_path" ]] || return 0
  [[ "$__flutterm_path" != "${ZDOTDIR:-}/$__flutterm_file" ]] || return 0
  local __flutterm_proxy_zdotdir="${ZDOTDIR:-}"
  local __flutterm_proxy_zdotdir_was_set=0
  (( $+ZDOTDIR )) && __flutterm_proxy_zdotdir_was_set=1
  __flutterm_restore_zdotdir
  source "$__flutterm_path" || true
  if [[ "$__flutterm_proxy_zdotdir_was_set" == "1" ]]; then
    export ZDOTDIR="$__flutterm_proxy_zdotdir"
  else
    unset ZDOTDIR
  fi
}

__flutterm_restore_zdotdir() {
  emulate -L zsh
  if [[ "${FLUTTERM_ORIGINAL_ZDOTDIR_WAS_SET:-0}" == "1" ]]; then
    export ZDOTDIR="${FLUTTERM_ORIGINAL_ZDOTDIR:-}"
  else
    unset ZDOTDIR
  fi
}
"#;

const ZSH_HOOK_INSTALLER: &str = r#"
__flutterm_install_shell_hooks() {
  emulate -L zsh
  [[ -n "${FLUTTERM_SHELL_INTEGRATION:-}" ]] || return 0
  [[ -z "${__FLUTTERM_SHELL_INTEGRATION_LOADED:-}" ]] || return 0
  (( $+commands[od] && $+commands[tr] )) || return 0
  autoload -Uz add-zsh-hook 2>/dev/null || return 0

  typeset -g __FLUTTERM_SHELL_INTEGRATION_LOADED=1
  typeset -g __flutterm_command_active=0
  typeset -g __flutterm_last_command=""
  typeset -g __flutterm_prompt_sp_suppressed=0
  typeset -g __flutterm_prompt_sp_was_set=0
  typeset -g __flutterm_startup_prompt_sp_checked=0
  typeset -g __flutterm_startup_prompt_trimmed=0
  typeset -g __flutterm_original_prompt=""

  __flutterm_json_escape() {
    emulate -L zsh
    local __flutterm_value="${1:-}"
    __flutterm_value=${__flutterm_value//\\/\\\\}
    __flutterm_value=${__flutterm_value//\"/\\\"}
    __flutterm_value=${__flutterm_value//$'\n'/\\n}
    __flutterm_value=${__flutterm_value//$'\r'/\\r}
    __flutterm_value=${__flutterm_value//$'\t'/\\t}
    builtin printf '%s' "$__flutterm_value"
  }

  __flutterm_emit_shell_hook() {
    emulate -L zsh
    local __flutterm_json="$1"
    local __flutterm_hex
    __flutterm_hex=$(builtin printf '%s' "$__flutterm_json" | command od -An -tx1 -v 2>/dev/null | command tr -d ' \n' 2>/dev/null) || return 0
    [[ -n "$__flutterm_hex" ]] || return 0
    builtin printf '\ePhook;%s\e\\' "$__flutterm_hex" 2>/dev/null || true
  }

  __flutterm_suspend_startup_prompt_sp() {
    [[ "${__FLUTTERM_SHELL_INTEGRATION_LOADED:-}" == "1" ]] || return 0
    [[ "${__flutterm_startup_prompt_sp_checked:-0}" == "0" ]] || return 0
    builtin typeset -g __flutterm_startup_prompt_sp_checked=1
    builtin typeset -g __flutterm_prompt_sp_was_set=0
    [[ -o prompt_sp ]] && builtin typeset -g __flutterm_prompt_sp_was_set=1
    unsetopt prompt_sp
    builtin typeset -g __flutterm_prompt_sp_suppressed=1
  }

  __flutterm_trim_startup_prompt_newline() {
    [[ "${__flutterm_startup_prompt_trimmed:-0}" == "0" ]] || return 0
    builtin typeset -g __flutterm_original_prompt="$PROMPT"
    if [[ "$PROMPT" == $'\n'* ]]; then
      PROMPT="${PROMPT#$'\n'}"
      builtin typeset -g __flutterm_startup_prompt_trimmed=1
    elif [[ -o prompt_subst ]]; then
      PROMPT='${${:-${(e)__flutterm_original_prompt}}#$'\''\n'\''}'
      builtin typeset -g __flutterm_startup_prompt_trimmed=1
    else
      builtin typeset -g __flutterm_startup_prompt_trimmed=2
    fi
  }

  __flutterm_restore_startup_prompt_state() {
    if [[ "${__flutterm_startup_prompt_trimmed:-0}" == "1" ]]; then
      PROMPT="${__flutterm_original_prompt:-}"
      builtin typeset -g __flutterm_startup_prompt_trimmed=2
    fi
    if [[ "${__flutterm_prompt_sp_suppressed:-0}" == "1" ]]; then
      if [[ "${__flutterm_prompt_sp_was_set:-0}" == "1" ]]; then
        setopt prompt_sp
      else
        unsetopt prompt_sp
      fi
      builtin typeset -g __flutterm_prompt_sp_suppressed=0
    fi
  }

  __flutterm_preexec() {
    __flutterm_restore_startup_prompt_state
    emulate -L zsh
    local __flutterm_command="$(__flutterm_json_escape "${1:-}")"
    typeset -g __flutterm_command_active=1
    typeset -g __flutterm_last_command="${1:-}"
    __flutterm_emit_shell_hook "{\"hook\":\"preexec\",\"command\":\"$__flutterm_command\",\"shell\":\"zsh\"}"
    return 0
  }

  __flutterm_precmd() {
    local __flutterm_status=$?
    __flutterm_trim_startup_prompt_newline
    emulate -L zsh
    if [[ "${__flutterm_command_active:-0}" == "1" ]]; then
      local __flutterm_command="$(__flutterm_json_escape "${__flutterm_last_command:-}")"
      __flutterm_emit_shell_hook "{\"hook\":\"command_finished\",\"command\":\"$__flutterm_command\",\"exit_code\":$__flutterm_status,\"shell\":\"zsh\"}"
      typeset -g __flutterm_command_active=0
      typeset -g __flutterm_last_command=""
    fi
    __flutterm_emit_shell_hook '{"hook":"precmd","shell":"zsh"}'
    local __flutterm_pwd="$(__flutterm_json_escape "${PWD:-}")"
    __flutterm_emit_shell_hook "{\"hook\":\"precmd.pwd\",\"pwd\":\"$__flutterm_pwd\",\"shell\":\"zsh\"}"
    return $__flutterm_status
  }

  add-zsh-hook preexec __flutterm_preexec 2>/dev/null || true
  add-zsh-hook precmd __flutterm_precmd 2>/dev/null || true
}
"#;

const BASH_RCFILE: &str = r#"
__flutterm_source_original_bashrc() {
  local __flutterm_home="${HOME:-}"
  [[ -n "$__flutterm_home" ]] || return 0
  local __flutterm_path="$__flutterm_home/.bashrc"
  [[ -r "$__flutterm_path" ]] || return 0
  [[ "$__flutterm_path" != "${BASH_SOURCE[0]:-}" ]] || return 0
  . "$__flutterm_path" || true
}

__flutterm_json_escape() {
  local __flutterm_value="${1:-}"
  __flutterm_value=${__flutterm_value//\\/\\\\}
  __flutterm_value=${__flutterm_value//\"/\\\"}
  __flutterm_value=${__flutterm_value//$'\n'/\\n}
  __flutterm_value=${__flutterm_value//$'\r'/\\r}
  __flutterm_value=${__flutterm_value//$'\t'/\\t}
  printf '%s' "$__flutterm_value"
}

__flutterm_emit_shell_hook() {
  local __flutterm_json="$1"
  local __flutterm_hex
  __flutterm_hex=$(printf '%s' "$__flutterm_json" | command od -An -tx1 -v 2>/dev/null | command tr -d ' \n' 2>/dev/null) || return 0
  [[ -n "$__flutterm_hex" ]] || return 0
  printf '\ePhook;%s\e\\' "$__flutterm_hex" 2>/dev/null || true
}

__flutterm_install_shell_hooks() {
  [[ -n "${FLUTTERM_SHELL_INTEGRATION:-}" ]] || return 0
  [[ -z "${__FLUTTERM_SHELL_INTEGRATION_LOADED:-}" ]] || return 0
  command -v od >/dev/null 2>&1 || return 0
  command -v tr >/dev/null 2>&1 || return 0
  [[ -z "$(trap -p DEBUG 2>/dev/null)" ]] || return 0

  __FLUTTERM_SHELL_INTEGRATION_LOADED=1
  __flutterm_command_active=0
  __flutterm_last_command=""
  __flutterm_inside_prompt=0

  if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == declare\ -a* ]]; then
    __flutterm_original_prompt_command_is_array=1
    __flutterm_original_prompt_command_array=("${PROMPT_COMMAND[@]}")
  else
    __flutterm_original_prompt_command_is_array=0
    __flutterm_original_prompt_command_string="${PROMPT_COMMAND:-}"
  fi

  __flutterm_run_original_prompt_command() {
    local __flutterm_status="$1"
    if [[ "${__flutterm_original_prompt_command_is_array:-0}" == "1" ]]; then
      local __flutterm_prompt_command_entry
      for __flutterm_prompt_command_entry in "${__flutterm_original_prompt_command_array[@]}"; do
        [[ -n "$__flutterm_prompt_command_entry" ]] && eval "$__flutterm_prompt_command_entry" || true
      done
    elif [[ -n "${__flutterm_original_prompt_command_string:-}" ]]; then
      eval "$__flutterm_original_prompt_command_string" || true
    fi
    return "$__flutterm_status"
  }

  __flutterm_preexec() {
    local __flutterm_frame
    for __flutterm_frame in "${FUNCNAME[@]:1}"; do
      [[ "$__flutterm_frame" == __flutterm_* ]] && return 0
    done
    [[ "${__flutterm_inside_prompt:-0}" == "1" ]] && return 0
    [[ "${__flutterm_command_active:-0}" == "1" ]] && return 0

    local __flutterm_command="${BASH_COMMAND:-}"
    [[ -n "$__flutterm_command" ]] || return 0
    [[ "$__flutterm_command" == "__flutterm_prompt_command"* ]] && return 0

    __flutterm_command_active=1
    __flutterm_last_command="$__flutterm_command"
    local __flutterm_escaped_command="$(__flutterm_json_escape "$__flutterm_command")"
    __flutterm_emit_shell_hook "{\"hook\":\"preexec\",\"command\":\"$__flutterm_escaped_command\",\"shell\":\"bash\"}"
    return 0
  }

  __flutterm_prompt_command() {
    local __flutterm_status=$?
    __flutterm_inside_prompt=1
    __flutterm_run_original_prompt_command "$__flutterm_status" || true
    if [[ "${__flutterm_command_active:-0}" == "1" ]]; then
      local __flutterm_escaped_command="$(__flutterm_json_escape "${__flutterm_last_command:-}")"
      __flutterm_emit_shell_hook "{\"hook\":\"command_finished\",\"command\":\"$__flutterm_escaped_command\",\"exit_code\":$__flutterm_status,\"shell\":\"bash\"}"
      __flutterm_command_active=0
      __flutterm_last_command=""
    fi
    __flutterm_emit_shell_hook '{"hook":"precmd","shell":"bash"}'
    local __flutterm_pwd="$(__flutterm_json_escape "${PWD:-}")"
    __flutterm_emit_shell_hook "{\"hook\":\"precmd.pwd\",\"pwd\":\"$__flutterm_pwd\",\"shell\":\"bash\"}"
    __flutterm_inside_prompt=0
    return "$__flutterm_status"
  }

  trap '__flutterm_preexec' DEBUG
  if [[ "${__flutterm_original_prompt_command_is_array:-0}" == "1" ]]; then
    PROMPT_COMMAND=(__flutterm_prompt_command)
  else
    PROMPT_COMMAND=__flutterm_prompt_command
  fi
}

__flutterm_source_original_bashrc || true
__flutterm_install_shell_hooks >/dev/null 2>&1 || true
"#;

const FISH_INIT: &str = r#"
if test -n "$FLUTTERM_SHELL_INTEGRATION"; and not set -q __FLUTTERM_SHELL_INTEGRATION_LOADED
  command -sq od; or return 0
  command -sq tr; or return 0

  set -g __FLUTTERM_SHELL_INTEGRATION_LOADED 1
  set -g __flutterm_command_active 0
  set -g __flutterm_last_command ''

  function __flutterm_json_escape
    set -l __flutterm_value ''
    if set -q argv[1]
      set __flutterm_value "$argv[1]"
    end
    set __flutterm_value (string replace -a "\\" "\\\\" -- "$__flutterm_value")
    set __flutterm_value (string replace -a "\"" "\\\"" -- "$__flutterm_value")
    set -l __flutterm_lf \n
    set -l __flutterm_cr \r
    set -l __flutterm_tab \t
    set __flutterm_value (string replace -a "$__flutterm_lf" "\\n" -- "$__flutterm_value")
    set __flutterm_value (string replace -a "$__flutterm_cr" "\\r" -- "$__flutterm_value")
    set __flutterm_value (string replace -a "$__flutterm_tab" "\\t" -- "$__flutterm_value")
    printf '%s' "$__flutterm_value"
  end

  function __flutterm_emit_shell_hook
    set -l __flutterm_json "$argv[1]"
    set -l __flutterm_hex (printf '%s' "$__flutterm_json" | command od -An -tx1 -v 2>/dev/null | command tr -d ' \n' 2>/dev/null)
    test -n "$__flutterm_hex"; or return 0
    printf '\ePhook;%s\e\\' "$__flutterm_hex" 2>/dev/null; or true
  end

  function __flutterm_preexec --on-event fish_preexec
    set -g __flutterm_command_active 1
    set -g __flutterm_last_command "$argv[1]"
    set -l __flutterm_command (__flutterm_json_escape "$argv[1]")
    __flutterm_emit_shell_hook "{\"hook\":\"preexec\",\"command\":\"$__flutterm_command\",\"shell\":\"fish\"}"
  end

  function __flutterm_postexec --on-event fish_postexec
    set -l __flutterm_status $status
    if test "$__flutterm_command_active" = 1
      set -l __flutterm_command (__flutterm_json_escape "$__flutterm_last_command")
      __flutterm_emit_shell_hook "{\"hook\":\"command_finished\",\"command\":\"$__flutterm_command\",\"exit_code\":$__flutterm_status,\"shell\":\"fish\"}"
      set -g __flutterm_command_active 0
      set -g __flutterm_last_command ''
    end
  end

  function __flutterm_prompt --on-event fish_prompt
    __flutterm_emit_shell_hook '{"hook":"precmd","shell":"fish"}'
    set -l __flutterm_pwd (__flutterm_json_escape "$PWD")
    __flutterm_emit_shell_hook "{\"hook\":\"precmd.pwd\",\"pwd\":\"$__flutterm_pwd\",\"shell\":\"fish\"}"
  end
end
"#;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        TerminalProfileAppearance, TerminalProfileInteraction, TerminalProfileLaunch,
        TerminalProfileTerminal, TerminalShellIntegration,
    };
    use tempfile::tempdir;

    fn profile(
        program: &str,
        args: Vec<String>,
        env: BTreeMap<String, String>,
        emulation: TerminalEmulation,
        shell_integration_enabled: bool,
    ) -> TerminalProfile {
        TerminalProfile {
            id: "test".to_string(),
            name: "Test".to_string(),
            launch: TerminalProfileLaunch {
                program: program.to_string(),
                args,
                env,
                cwd: None,
            },
            terminal: TerminalProfileTerminal {
                emulation,
                scrollback_lines: 8_000,
            },
            shell_integration: TerminalShellIntegration {
                enabled: shell_integration_enabled,
            },
            appearance: TerminalProfileAppearance::default(),
            interaction: TerminalProfileInteraction::default(),
        }
    }

    fn build_plan_without_proxy(profile: &TerminalProfile) -> CommandPlan {
        build_command_plan_with_proxy_factory(profile, |_kind, _profile, _program| {
            panic!("proxy factory should not be called")
        })
    }

    fn helper_path_env() -> (tempfile::TempDir, String) {
        let helper_dir = tempdir().unwrap();
        for name in ["od", "tr"] {
            let path = helper_dir.path().join(name);
            fs::write(&path, "#!/bin/sh\n").unwrap();
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;

                let mut permissions = fs::metadata(&path).unwrap().permissions();
                permissions.set_mode(0o755);
                fs::set_permissions(&path, permissions).unwrap();
            }
        }
        let path = helper_dir.path().to_string_lossy().into_owned();
        (helper_dir, path)
    }

    #[test]
    fn zsh_shell_hook_integration_eligible_profile_sets_zdotdir_proxy() {
        if !supports_zdotdir_proxy() {
            return;
        }

        let original_zdotdir = tempdir().unwrap();
        let proxy_base = tempdir().unwrap();
        let (_helper_dir, helper_path) = helper_path_env();
        let mut env = BTreeMap::new();
        env.insert(
            "ZDOTDIR".to_string(),
            original_zdotdir.path().to_string_lossy().into_owned(),
        );
        env.insert("PATH".to_string(), helper_path);
        let profile = profile("/bin/zsh", vec![], env, TerminalEmulation::Xterm256, true);

        let plan = build_command_plan_with_proxy_factory(&profile, |kind, _profile, _program| {
            assert_eq!(kind, ShellIntegrationKind::Zsh);
            create_shell_integration_proxy_in(kind, proxy_base.path())
        });

        let zdotdir = plan.env.get("ZDOTDIR").expect("expected proxy ZDOTDIR");
        let proxy_path = Path::new(zdotdir);
        assert!(proxy_path.starts_with(proxy_base.path()));
        assert!(proxy_path.join(".zshenv").exists());
        assert!(proxy_path.join(".zprofile").exists());
        assert!(proxy_path.join(".zshrc").exists());
        assert!(proxy_path.join(".zlogin").exists());
        assert!(proxy_path.join(".zlogout").exists());
        assert_eq!(plan.env["FLUTTERM_SHELL_INTEGRATION"], "1");
        assert_eq!(plan.env["FLUTTERM_ORIGINAL_ZDOTDIR_WAS_SET"], "1");
        assert_eq!(
            plan.env["FLUTTERM_ORIGINAL_ZDOTDIR"],
            original_zdotdir.path().to_string_lossy()
        );
        assert!(plan.shell_integration_proxy.is_some());

        let zshrc = fs::read_to_string(proxy_path.join(".zshrc")).unwrap();
        assert!(zshrc.contains("__FLUTTERM_SHELL_INTEGRATION_LOADED"));
        assert!(zshrc.contains("add-zsh-hook preexec __flutterm_preexec"));
        assert!(zshrc.contains("add-zsh-hook precmd __flutterm_precmd"));
        assert!(zshrc.contains("\\\"hook\\\":\\\"precmd.pwd\\\""));
        assert!(zshrc.contains("__flutterm_suspend_startup_prompt_sp"));
        assert!(zshrc.contains("unsetopt prompt_sp"));
        assert!(zshrc.contains("__flutterm_trim_startup_prompt_newline"));
        assert!(zshrc.contains("__flutterm_restore_startup_prompt_state"));
        assert!(zshrc.contains("__flutterm_source_original_zdotfile \".zshrc\""));
    }

    #[test]
    fn zsh_login_shell_hook_integration_remains_eligible() {
        if !supports_zdotdir_proxy() {
            return;
        }

        let proxy_base = tempdir().unwrap();
        let (_helper_dir, helper_path) = helper_path_env();
        let mut env = BTreeMap::new();
        env.insert("PATH".to_string(), helper_path);
        let profile = profile(
            "/bin/zsh",
            vec!["-l".to_string()],
            env,
            TerminalEmulation::Xterm256,
            true,
        );

        let plan = build_command_plan_with_proxy_factory(&profile, |kind, _profile, _program| {
            assert_eq!(kind, ShellIntegrationKind::Zsh);
            create_shell_integration_proxy_in(kind, proxy_base.path())
        });

        assert_eq!(plan.args, vec!["-l"]);
        assert_eq!(plan.env["FLUTTERM_SHELL_INTEGRATION"], "1");
        assert!(plan.env.contains_key("ZDOTDIR"));
        assert!(plan.shell_integration_proxy.is_some());
    }

    #[test]
    fn bash_shell_hook_integration_eligible_profile_sets_rcfile_proxy() {
        if !supports_unix_shell_integration() {
            return;
        }

        let original_home = tempdir().unwrap();
        let proxy_base = tempdir().unwrap();
        let (_helper_dir, helper_path) = helper_path_env();
        let mut env = BTreeMap::new();
        env.insert(
            "HOME".to_string(),
            original_home.path().to_string_lossy().into_owned(),
        );
        env.insert("PATH".to_string(), helper_path);
        let profile = profile("/bin/bash", vec![], env, TerminalEmulation::Xterm256, true);

        let plan = build_command_plan_with_proxy_factory(&profile, |kind, _profile, _program| {
            assert_eq!(kind, ShellIntegrationKind::Bash);
            create_shell_integration_proxy_in(kind, proxy_base.path())
        });

        assert_eq!(plan.args.len(), 2);
        assert_eq!(plan.args[0], "--rcfile");
        let rcfile = Path::new(&plan.args[1]);
        assert!(rcfile.starts_with(proxy_base.path()));
        assert_eq!(
            rcfile.file_name().and_then(|name| name.to_str()),
            Some(".bashrc")
        );
        assert_eq!(plan.env["FLUTTERM_SHELL_INTEGRATION"], "1");
        assert!(plan.shell_integration_proxy.is_some());

        let bashrc = fs::read_to_string(rcfile).unwrap();
        assert!(bashrc.contains("__flutterm_source_original_bashrc"));
        assert!(bashrc.contains("trap -p DEBUG"));
        assert!(bashrc.contains("PROMPT_COMMAND"));
        assert!(bashrc.contains("\\\"hook\\\":\\\"precmd.pwd\\\""));
        assert!(bashrc.contains("\\\"shell\\\":\\\"bash\\\""));
    }

    #[test]
    fn fish_shell_hook_integration_eligible_profile_sets_init_command_proxy() {
        if !supports_unix_shell_integration() {
            return;
        }

        let proxy_base = tempdir().unwrap();
        let (_helper_dir, helper_path) = helper_path_env();
        let mut env = BTreeMap::new();
        env.insert("PATH".to_string(), helper_path);
        let profile = profile("/bin/fish", vec![], env, TerminalEmulation::Xterm256, true);

        let plan = build_command_plan_with_proxy_factory(&profile, |kind, _profile, _program| {
            assert_eq!(kind, ShellIntegrationKind::Fish);
            create_shell_integration_proxy_in(kind, proxy_base.path())
        });

        assert_eq!(
            plan.args,
            vec![
                "--init-command".to_string(),
                r#"source "$FLUTTERM_FISH_INIT""#.to_string()
            ]
        );
        let init_file = Path::new(
            plan.env
                .get("FLUTTERM_FISH_INIT")
                .expect("expected fish init file"),
        );
        assert!(init_file.starts_with(proxy_base.path()));
        assert_eq!(
            init_file.file_name().and_then(|name| name.to_str()),
            Some("init.fish")
        );
        assert_eq!(plan.env["FLUTTERM_SHELL_INTEGRATION"], "1");
        assert!(plan.shell_integration_proxy.is_some());

        let init = fs::read_to_string(init_file).unwrap();
        assert!(init.contains("__FLUTTERM_SHELL_INTEGRATION_LOADED"));
        assert!(init.contains("--on-event fish_preexec"));
        assert!(init.contains("--on-event fish_postexec"));
        assert!(init.contains("--on-event fish_prompt"));
        assert!(init.contains("\\\"hook\\\":\\\"precmd.pwd\\\""));
        assert!(init.contains("\\\"shell\\\":\\\"fish\\\""));
    }

    #[test]
    fn shell_hook_integration_disabled_keeps_original_launch_plan() {
        for program in ["/bin/zsh", "/bin/bash", "/bin/fish"] {
            let profile = profile(
                program,
                vec![],
                BTreeMap::new(),
                TerminalEmulation::Xterm256,
                false,
            );

            let plan = build_plan_without_proxy(&profile);

            assert_eq!(plan.program, program);
            assert!(plan.args.is_empty());
            assert_eq!(plan.env, profile.launch.env);
            assert!(plan.shell_integration_proxy.is_none());
        }
    }

    #[test]
    fn shell_hook_integration_degrades_for_unsupported_profiles() {
        let cases = [
            profile(
                "/bin/zsh",
                vec!["-f".to_string()],
                BTreeMap::new(),
                TerminalEmulation::Xterm256,
                true,
            ),
            profile(
                "/bin/zsh",
                vec![],
                BTreeMap::new(),
                TerminalEmulation::Vt220,
                true,
            ),
            profile(
                "/bin/bash",
                vec!["--noprofile".to_string()],
                BTreeMap::new(),
                TerminalEmulation::Xterm256,
                true,
            ),
            profile(
                "/bin/bash",
                vec![],
                BTreeMap::new(),
                TerminalEmulation::Vt220,
                true,
            ),
            profile(
                "/bin/fish",
                vec!["--no-config".to_string()],
                BTreeMap::new(),
                TerminalEmulation::Xterm256,
                true,
            ),
            profile(
                "/bin/fish",
                vec![],
                BTreeMap::new(),
                TerminalEmulation::Vt220,
                true,
            ),
        ];

        for profile in cases {
            let plan = build_plan_without_proxy(&profile);
            assert_eq!(plan.program, profile.launch.program);
            assert_eq!(plan.args, profile.launch.args);
            assert_eq!(plan.env, profile.launch.env);
            assert!(plan.shell_integration_proxy.is_none());
        }
    }

    #[test]
    fn shell_hook_integration_degrades_when_helpers_are_missing() {
        for program in ["/bin/zsh", "/bin/bash", "/bin/fish"] {
            let helper_dir = tempdir().unwrap();
            let mut env = BTreeMap::new();
            env.insert(
                "PATH".to_string(),
                helper_dir.path().to_string_lossy().into_owned(),
            );
            let profile = profile(program, vec![], env, TerminalEmulation::Xterm256, true);

            let plan = build_plan_without_proxy(&profile);

            assert_eq!(plan.program, program);
            assert!(plan.args.is_empty());
            assert_eq!(plan.env, profile.launch.env);
            assert!(plan.shell_integration_proxy.is_none());
        }
    }

    #[test]
    fn shell_hook_integration_degrades_when_proxy_creation_fails() {
        let (_helper_dir, helper_path) = helper_path_env();
        for program in ["/bin/zsh", "/bin/bash", "/bin/fish"] {
            let mut env = BTreeMap::new();
            env.insert("PATH".to_string(), helper_path.clone());
            let profile = profile(program, vec![], env, TerminalEmulation::Xterm256, true);

            let plan =
                build_command_plan_with_proxy_factory(&profile, |_kind, _profile, _program| {
                    Err(std::io::Error::other("forced proxy failure"))
                });

            assert_eq!(plan.program, program);
            assert!(plan.args.is_empty());
            assert_eq!(plan.env, profile.launch.env);
            assert!(plan.shell_integration_proxy.is_none());
        }
    }
}
