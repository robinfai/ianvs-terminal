# Isolated compatibility fixture for the observed bash-preexec dispatch contract.
# The guarded entry, status dispatch and DEBUG filtering reproduce the observed
# contract. In particular, do not exempt our new wrapper by its function name.
bash_preexec_imported=defined
__bp_imported=defined
precmd_functions=()
preexec_functions=()
__probe_history_count=0
__bp_set_ret_value() { return "${1:-0}"; }
__bp_interactive_mode() { __bp_preexec_interactive_mode=on; }
__bp_precmd_invoke_cmd() {
  __bp_last_ret_value=$? BP_PIPESTATUS=("${PIPESTATUS[@]}")
  if ((__bp_inside_precmd > 0)); then return; fi
  local __bp_inside_precmd=1
  local precmd_function
  for precmd_function in "${precmd_functions[@]}"; do
    if type -t "$precmd_function" >/dev/null; then
      __bp_set_ret_value "$__bp_last_ret_value" "$__bp_last_argument_prev_command"
      "$precmd_function"
    fi
  done
  __bp_set_ret_value "$__bp_last_ret_value"
}
__bp_trim_whitespace() {
  local __bp_trimmed=${2:-}
  __bp_trimmed=${__bp_trimmed#"${__bp_trimmed%%[![:space:]]*}"}
  __bp_trimmed=${__bp_trimmed%"${__bp_trimmed##*[![:space:]]}"}
  printf -v "$1" '%s' "$__bp_trimmed"
}
__bp_in_prompt_command() {
  local prompt_command_array
  IFS=$'\n;' read -rd '' -a prompt_command_array <<< "${PROMPT_COMMAND:-}"
  local trimmed_arg
  __bp_trim_whitespace trimmed_arg "${1:-}"
  local command trimmed_command
  for command in "${prompt_command_array[@]:-}"; do
    __bp_trim_whitespace trimmed_command "$command"
    if [[ "$trimmed_command" = "$trimmed_arg" ]]; then return 0; fi
  done
  return 1
}
__bp_preexec_invoke_exec() {
  __bp_last_argument_prev_command="${1:-}"
  if ((__bp_inside_preexec > 0)); then return; fi
  local __bp_inside_preexec=1
  if [[ ! -t 1 && -z "${__bp_delay_install:-}" ]]; then return; fi
  if [[ -n "${COMP_LINE:-}" ]]; then return; fi
  if [[ -z "${__bp_preexec_interactive_mode:-}" ]]; then
    return
  elif [[ 0 -eq "${BASH_SUBSHELL:-}" ]]; then
    __bp_preexec_interactive_mode=''
  fi
  if __bp_in_prompt_command "${BASH_COMMAND:-}"; then
    __bp_preexec_interactive_mode=''
    return
  fi
  local this_command
  this_command=$(export LC_ALL=C; HISTTIMEFORMAT= builtin history 1 | sed '1 s/^ *[0-9][0-9]*[* ] //')
  [[ -n "$this_command" ]] || return
  local preexec_function preexec_function_ret_value
  local preexec_ret_value=0
  for preexec_function in "${preexec_functions[@]:-}"; do
    if type -t "$preexec_function" >/dev/null; then
      __bp_set_ret_value "${__bp_last_ret_value:-0}"
      "$preexec_function" "$this_command"
      preexec_function_ret_value=$?
      if [[ "$preexec_function_ret_value" != 0 ]]; then
        preexec_ret_value=$preexec_function_ret_value
      fi
    fi
  done
  __bp_set_ret_value "$preexec_ret_value" "$__bp_last_argument_prev_command"
}
__bp_install() {
  trap '__bp_preexec_invoke_exec "$_"' DEBUG
  local __probe_entry='if declare -F __bp_precmd_invoke_cmd &>/dev/null; then __bp_precmd_invoke_cmd; fi;'
  if [[ $__probe_style == modern* ]]; then __probe_entry='__bp_precmd_invoke_cmd;'; fi
  if [[ $__probe_style == *array* ]]; then
    unset PROMPT_COMMAND
    PROMPT_COMMAND=()
    PROMPT_COMMAND[2]=$__probe_entry
    PROMPT_COMMAND[5]='history -a; ((__probe_history_count+=1));'
    PROMPT_COMMAND[9]='__bp_interactive_mode;'
  else
    PROMPT_COMMAND="$__probe_entry history -a; ((__probe_history_count+=1)); __bp_interactive_mode;"
  fi
  __bp_precmd_invoke_cmd
  __bp_interactive_mode
}
if [[ $__probe_style == *deferred* ]]; then
  PROMPT_COMMAND=$'history -a;\n__bp_install'
else
  __bp_install
fi
