__iv_valid() {
  command -v od >/dev/null && command -v tr >/dev/null || return 1
  declare -F __ianvs_emit_shell_hook >/dev/null &&
  declare -F __ianvs_json_escape >/dev/null &&
  declare -F __ianvs_run_original_prompt_command >/dev/null &&
  declare -F __ianvs_preexec >/dev/null &&
  declare -F __ianvs_prompt_command >/dev/null || return 1
  if [[ "${__ianvs_bash_hook_backend:-}" == bash-preexec ]]; then
    [[ -n "${bash_preexec_imported:-${__bp_imported:-}}" && "${PROMPT_COMMAND[*]}" == *__bp_* ]] &&
    declare -F __bp_preexec_invoke_exec >/dev/null &&
    declare -F __bp_precmd_invoke_cmd >/dev/null &&
    declare -F __bp_interactive_mode >/dev/null &&
    [[ " ${preexec_functions[*]} " == *' __ianvs_preexec '* ]] &&
    [[ " ${precmd_functions[*]} " == *' __ianvs_prompt_command '* ]]
  else
    [[ "$__iv_debug" == "trap -- '__ianvs_preexec' DEBUG" ]] &&
    [[ "${PROMPT_COMMAND[*]}" == "__ianvs_prompt_command" ]]
  fi
}
