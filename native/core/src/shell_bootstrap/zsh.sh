command stty sane
setopt ZLE RCS GLOBAL_RCS
IANVS_SHELL_INTEGRATION=1
# /etc/zshenv was already loaded by zsh. Preserve the actual ZDOTDIR.
[[ -r "${ZDOTDIR:-$HOME}/.zshenv" ]] && source "${ZDOTDIR:-$HOME}/.zshenv"
if [[ @@LOGIN@@ = 1 ]]; then
  for __iv_file in /etc/zprofile "${ZDOTDIR:-$HOME}/.zprofile"; do
    [[ -r "$__iv_file" ]] && source "$__iv_file"
  done
fi
for __iv_file in /etc/zshrc "${ZDOTDIR:-$HOME}/.zshrc"; do
  [[ -r "$__iv_file" ]] && source "$__iv_file"
done
if [[ @@LOGIN@@ = 1 ]]; then
  for __iv_file in /etc/zlogin "${ZDOTDIR:-$HOME}/.zlogin"; do
    [[ -r "$__iv_file" ]] && source "$__iv_file"
  done
fi
__iv_source=installed
__iv_registered=0
@@CHECK@@
if __iv_valid; then
  __iv_source=reused
else
  unset __IANVS_SHELL_INTEGRATION_LOADED
@@INSTALLER@@
  __ianvs_install_shell_hooks
fi
if __iv_valid; then __iv_registered=1; else __iv_source=helpers_missing; fi
__IANVS_CONTEXT=@@CONTEXT@@
__IANVS_PROTOCOL_VERSION=1
__ianvs_emit_shell_hook() {
  emulate -L zsh
  local __iv_hex __iv_json="${1%\}}"
  __iv_hex=$(printf '%s,"context_id":"%s"}' "$__iv_json" "$__IANVS_CONTEXT" | command od -An -tx1 -v | command tr -d ' \n')
  printf '\033Phook;%s\033\\' "$__iv_hex"
}
@@WRAPPER@@
__ianvs_command_active=0
__ianvs_last_command=''
printf '\033]6973;@@NONCE@@;@@CONTEXT@@;ready;%s;%s;zsh\007' "$__iv_source" "$__iv_registered"
