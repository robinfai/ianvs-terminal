__iv_valid() {
  command -v od >/dev/null && command -v tr >/dev/null || return 1
  declare -F __ianvs_emit_shell_hook >/dev/null &&
  declare -F __ianvs_json_escape >/dev/null &&
  declare -F __ianvs_run_original_prompt_command >/dev/null &&
  declare -F __ianvs_preexec >/dev/null &&
  declare -F __ianvs_prompt_command >/dev/null || return 1
  [[ "$__iv_debug" == "trap -- '__ianvs_preexec' DEBUG" ]] &&
  [[ "${PROMPT_COMMAND[*]}" == "__ianvs_prompt_command" ]]
}
