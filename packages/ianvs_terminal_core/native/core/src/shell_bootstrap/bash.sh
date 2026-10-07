__IANVS_BOOTSTRAPPING=1
command stty sane
IANVS_SHELL_INTEGRATION=1
# The entire payload was read before user rc files can change history policy.
# SSH starts with login configuration; ordinary child shells use .bashrc.
if [[ @@LOGIN@@ = 1 ]]; then
  if [[ -r /etc/profile ]]; then source /etc/profile; fi
  for __iv_file in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    if [[ -r "$__iv_file" ]]; then source "$__iv_file"; break; fi
  done
elif [[ -r "$HOME/.bashrc" ]]; then
  source "$HOME/.bashrc"
fi
__iv_registered=0
__iv_source=installed
@@CHECK@@
__iv_debug=$(trap -p DEBUG)
if __iv_valid; then
  __iv_source=reused
elif [[ -z "$__iv_debug" || "$__iv_debug" == "trap -- '__ianvs_preexec' DEBUG" ||
        "$__iv_debug" == 'trap -- '\''__bp_preexec_invoke_exec "$_"'\'' DEBUG' ]] &&
     [[ "${PROMPT_COMMAND[*]}" != *"__ianvs_prompt_command"* ]]; then
  # Repair our own partial installation, but preserve unrelated DEBUG traps.
  # Reinstalling over an existing reference to our prompt callback would capture
  # that callback as an original prompt command and recurse. Ambiguous chains
  # also expose prompt commands to DEBUG, so they cannot pass readiness checks.
  if [[ "$(trap -p DEBUG)" == "trap -- '__ianvs_preexec' DEBUG" ]]; then trap - DEBUG; fi
  unset __IANVS_SHELL_INTEGRATION_LOADED
  IANVS_SKIP_ORIGINAL_BASHRC=1
@@INSTALLER@@
fi
__iv_debug=$(trap -p DEBUG)
__iv_valid && __iv_registered=1
if [[ "$__iv_registered" = 0 ]]; then __iv_source=hook_conflict; fi
__IANVS_CONTEXT=@@CONTEXT@@
__IANVS_PROTOCOL_VERSION=1
# Stamp all subsequent events with their actual shell context.
__ianvs_emit_shell_hook() {
  [[ "$__iv_registered" = 1 ]] || return 0
  if declare -F __ianvs_composer_emit >/dev/null; then
    case "$1" in
      *'"hook":"preexec"'*) __ianvs_cavailable=0; __ianvs_composer_emit busy ;;
    esac
  fi
  local __iv_hex __iv_json="${1%\}}"
  if [[ "$1" == *'"hook":"preexec"'* && -n ${__ianvs_pending_submission:-} ]]; then
    # DEBUG reports only the first simple command. Use the literal accepted
    # Readline buffer, including when the bootstrap reused older shell hooks.
    if [[ -n ${__ianvs_pending_command+x} ]]; then
      __ianvs_last_command=$__ianvs_pending_command
      __iv_json="{\"hook\":\"preexec\",\"command\":\"$(__ianvs_json_escape "$__ianvs_pending_command")\",\"shell\":\"bash\""
    fi
    __iv_json+=",\"submission_id\":\"$__ianvs_pending_submission\""
    unset __ianvs_pending_submission __ianvs_pending_command
  fi
  __iv_hex=$(printf '%s,"context_id":"%s"}' "$__iv_json" "$__IANVS_CONTEXT" | command od -An -tx1 -v | command tr -d ' \n')
  printf '\033Phook;%s\033\\' "$__iv_hex"
  # Publish readiness after the hook's external encoders finish. Otherwise an
  # immediate Ctrl+C can interrupt those processes before Readline starts and
  # leave the host with a revoked lease but no subsequent prompt notification.
  if [[ "$1" == *'"hook":"precmd.pwd"'* ]] && declare -F __ianvs_composer_ready >/dev/null; then
    __ianvs_composer_ready
  fi
}
@@WRAPPER@@
__ianvs_command_active=0
__ianvs_last_command=''
@@COMPOSER@@
__iv_ready() { printf '\033]6973;@@NONCE@@;@@CONTEXT@@;ready;%s;%s;bash\007' "$__iv_source" "$__iv_registered"; }
__iv_ready
unset -f __iv_valid

unset __IANVS_BOOTSTRAPPING
