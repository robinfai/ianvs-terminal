# Interactive shell entry shares the current host; it never opens an SSH hop.
function __ianvs_run_shell {
  local __iv_target="$1" __iv_arg __iv_id __iv_parent __iv_cmd __iv_status
  shift
  for __iv_arg in "$@"; do
    case "$__iv_arg" in
      -i|--interactive|--) ;;
      *) command "$__iv_target" "$@"; return $? ;;
    esac
  done
  if [ ! -t 0 ] || [ ! -t 1 ]; then command "$__iv_target" "$@"; return $?; fi
  __iv_id=$(command od -An -N16 -tx1 /dev/urandom 2>/dev/null | command tr -d ' \n')
  if [ ${#__iv_id} != 32 ]; then command "$__iv_target" "$@"; return $?; fi
  __iv_parent=${__IANVS_CONTEXT:-root}
  printf '\033]6973;@@NONCE@@;%s;enter_shell;%s;%s\007' "$__iv_id" "$__iv_parent" "$__iv_target"
  __iv_cmd=@@SHELL_LAUNCHER@@
  __iv_cmd=${__iv_cmd//@@CONTEXT@@/$__iv_id}
  __iv_cmd=${__iv_cmd//@@CHILD_NONCE@@/$__iv_id}
  command /bin/sh -c "$__iv_cmd" -- "$__iv_target"
  __iv_status=$?
  printf '\033]6973;@@NONCE@@;%s;resume;done\007' "$__iv_parent"
  return "$__iv_status"
}
function bash { __ianvs_run_shell bash "$@"; }
function zsh { __ianvs_run_shell zsh "$@"; }
function fish { __ianvs_run_shell fish "$@"; }
