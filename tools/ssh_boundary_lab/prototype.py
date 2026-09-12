"""Experimental bootstrap only. This is not the application's SSH backend."""
import base64
import re
import shlex
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def repository_hook(name):
    source = (ROOT / 'native/core/src/pty.rs').read_text()
    return re.search(r'const ' + name + r': &str = r#"(.*?)"#;', source, re.S)[1]


def encode(source):
    return base64.b64encode(source.encode()).decode()


def bash_bundle(mux=True):
    # The payload stores no copy of itself. Each hop passes the same bundle plus
    # a new parent ID. This avoids exponential quoting/payload growth.
    before = r'''
IANVS_SHELL_INTEGRATION=1
IANVS_SKIP_ORIGINAL_BASHRC=1
source "$HOME/.bashrc"
__ianvs_lab_debug="$(trap -p DEBUG)"
__ianvs_lab_valid() {
  declare -F __ianvs_preexec >/dev/null &&
  declare -F __ianvs_prompt_command >/dev/null &&
  [[ "$__ianvs_lab_debug" == *"__ianvs_preexec"* ]] &&
  [[ "${PROMPT_COMMAND[*]}" == *"__ianvs_prompt_command"* ]]
}
__ianvs_lab_before=missing
__ianvs_lab_valid && __ianvs_lab_before=reused
'''
    after = r'''
__LAB_CONTEXT="$(hostname):$$"
__LAB_PARENT="${__LAB_PARENT:-root}"
__ianvs_lab_debug="$(trap -p DEBUG)"
__ianvs_lab_registered=false
__ianvs_lab_valid && __ianvs_lab_registered=true
__ianvs_lab_emit() {
  local hex
  hex=$(printf '%s' "$1" | od -An -tx1 -v | tr -d ' \n')
  printf '\033Plab;%s\033\\' "$hex"
}
# Keep repository event semantics, adding only experimental attribution.
__ianvs_emit_shell_hook() {
  local value="${1%\}}"
  local hex
  hex=$(printf '%s,"context_id":"%s"}' "$value" "$__LAB_CONTEXT" | od -An -tx1 -v | tr -d ' \n')
  printf '\033Phook;%s\033\\' "$hex"
}
ssh() {
  # Deliberately bounded prototype: only a plain interactive destination.
  # All other invocations preserve argv and bypass injection.
  if [[ $# != 1 || "$1" == -* ]]; then
    command ssh "$@"
    return $?
  fi
  local target="$1" result bootstrap
  __ianvs_lab_emit "{\"stage\":\"enter\",\"parent\":\"$__LAB_CONTEXT\",\"target\":\"$target\"}"
  printf -v bootstrap 'export __LAB_BUNDLE=%q __LAB_PARENT=%q; exec /bin/bash --rcfile <(printf %%s "$__LAB_BUNDLE" | base64 -d) -i' "$__LAB_BUNDLE" "$__LAB_CONTEXT"
  command ssh -tt __MUX_OPTIONS__ "$target" "$bootstrap"
  result=$?
  __ianvs_lab_emit "{\"stage\":\"resume\",\"context_id\":\"$__LAB_CONTEXT\",\"exit_code\":$result}"
  return "$result"
}
__ianvs_lab_emit "{\"stage\":\"ready\",\"context_id\":\"$__LAB_CONTEXT\",\"parent\":\"$__LAB_PARENT\",\"registered\":$__ianvs_lab_registered,\"source\":\"$__ianvs_lab_before\"}"
'''
    options = ('-o ControlMaster=auto -o ControlPersist=60 '
               '-o ControlPath=/home/lab/.ssh/cm-%C') if mux else '-o ControlMaster=no -S none'
    return before + '\nif [[ "$__ianvs_lab_before" != reused ]]; then\n' + repository_hook('BASH_RCFILE') + '\nfi\n' + after.replace('__MUX_OPTIONS__', options)


def bash_command(mux=True):
    bundle = encode(bash_bundle(mux))
    return (f'export __LAB_BUNDLE={shlex.quote(bundle)} __LAB_PARENT=root; '
            'exec /bin/bash --rcfile <(printf %s "$__LAB_BUNDLE" | base64 -d) -i')


def streamed_install(shell):
    """Runs after the fixture's first internal prompt, before UI release.

    This tests memory installation in the actual final shell. It does NOT
    solve general prompt detection on arbitrary production hosts.
    """
    if shell == 'bash':
        return ' eval "$(printf %s ' + encode(bash_bundle(False)) + ' | base64 -d)"'
    if shell == 'zsh':
        body = 'IANVS_SHELL_INTEGRATION=1\n' + repository_hook('ZSH_HOOK_INSTALLER') + '\n__ianvs_install_shell_hooks\n'
        # Emit the same DCS lab framing used by the runner.
        marker = '{"stage":"ready","shell":"zsh"}'.encode().hex()
        body += "printf '\\033Plab;" + marker + "\\033\\\\'\n"
        return ' eval "$(printf %s ' + encode(body) + ' | base64 -d)"'
    if shell == 'fish':
        marker = '{"stage":"ready","shell":"fish"}'.encode().hex()
        body = 'set -gx IANVS_SHELL_INTEGRATION 1\n' + repository_hook('FISH_INIT')
        body += "\nprintf '\\033Plab;" + marker + "\\033\\\\'\n"
        return ' eval (printf %s ' + encode(body) + ' | base64 -d | string collect)'
    raise ValueError(shell)
