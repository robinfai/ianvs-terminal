# Shared by bash/zsh; fish invokes this helper with argv preserved by bash.
function ssh {
  local __iv_arg __iv_skip=0 __iv_targets=0 __iv_options=1
  for __iv_arg in "$@"; do
    if [ "$__iv_skip" = 1 ]; then __iv_skip=0; continue; fi
    if [ "$__iv_options" = 1 ]; then
      case "$__iv_arg" in
        --) __iv_options=0; continue ;;
        -T|-W*|-N|-n|-f|-M|-O*|-S*) command ssh "$@"; return $? ;;
        -b|-c|-D|-E|-e|-F|-I|-i|-J|-L|-l|-m|-o|-p|-R|-w) __iv_skip=1; continue ;;
        -t|-tt|-v|-vv|-vvv|-4|-6|-A|-a|-C|-K|-k|-q|-X|-x|-Y|-y) continue ;;
        -[piblJFDLRoEcmeIw]*?*) continue ;;
        -*) command ssh "$@"; return $? ;;
      esac
    fi
    __iv_targets=$((__iv_targets + 1))
  done
  if [ "$__iv_targets" != 1 ] || [ "$__iv_skip" != 0 ]; then command ssh "$@"; return $?; fi
  local __iv_config __iv_remote __iv_socket __iv_id __iv_cmd __iv_status __iv_parent __iv_host __iv_user __iv_port
  __iv_config=$(command ssh -G "$@" 2>/dev/null) || { command ssh "$@"; return $?; }
  __iv_remote=$(printf '%s\n' "$__iv_config" | command sed -n 's/^remotecommand //p')
  case "$__iv_remote" in ''|none) ;; *) command ssh "$@"; return $? ;; esac
  if printf '%s\n' "$__iv_config" | command grep -Eq '^(sessiontype (none|subsystem)|requesttty no|stdinnull yes|forkafterauthentication yes)$'; then command ssh "$@"; return $?; fi
  __iv_host=$(printf '%s\n' "$__iv_config" | command sed -n 's/^hostname //p')
  __iv_user=$(printf '%s\n' "$__iv_config" | command sed -n 's/^user //p')
  __iv_port=$(printf '%s\n' "$__iv_config" | command sed -n 's/^port //p')
  case "$__iv_host$__iv_user$__iv_port" in *[!a-zA-Z0-9_.:@%+-]*) command ssh "$@"; return $? ;; esac
  __iv_id=$(command od -An -N16 -tx1 /dev/urandom 2>/dev/null | command tr -d ' \n')
  if [ ${#__iv_id} != 32 ]; then command ssh "$@"; return $?; fi
  __iv_parent=${__IANVS_CONTEXT:-root}
  __iv_socket=$(printf '%s\n' "$__iv_config" | command sed -n 's/^controlpath //p')
  local __iv_owned=0
  if [ -z "$__iv_socket" ] || [ "$__iv_socket" = none ] || ! command ssh -S "$__iv_socket" -O check "$@" >/dev/null 2>&1; then
    # Socket metadata is allowed; bootstrap scripts are never written here.
    local __iv_dir
    __iv_dir=$(command mktemp -d "${TMPDIR:-/tmp}/ivssh.XXXXXXXX" 2>/dev/null) || { command ssh "$@"; return $?; }
    __iv_socket="$__iv_dir/m"
    __iv_owned=1
  fi
  # Keep filesystem metadata short enough for Unix domain sockets on macOS.
  if [ ${#__iv_socket} -gt 104 ]; then
    [ "$__iv_owned" = 1 ] && command rmdir "$__iv_dir" 2>/dev/null
    command ssh "$@"; return $?
  fi
  # Only bounded ASCII socket paths are carried in the control frame.
  case "$__iv_socket" in *[!a-zA-Z0-9_./:@+,-]*) [ "$__iv_owned" = 1 ] && command rmdir "$__iv_dir" 2>/dev/null; command ssh "$@"; return $? ;; esac
  printf '\033]6973;@@NONCE@@;%s;enter;%s;%s;%s;%s;%s\007' "$__iv_id" "$__iv_parent" "$__iv_socket" "$__iv_host" "$__iv_user" "$__iv_port"
  __iv_cmd=@@LAUNCHER@@
  __iv_cmd=${__iv_cmd//@@CONTEXT@@/$__iv_id}
  __iv_cmd=${__iv_cmd//@@CHILD_NONCE@@/$__iv_id}
  if [ "$__iv_owned" = 1 ]; then
    command ssh -o ControlMaster=auto -o ControlPersist=60 -o ControlPath="$__iv_socket" -t "$@" "$__iv_cmd"
  else
    command ssh -o ControlMaster=no -o ControlPath="$__iv_socket" -t "$@" "$__iv_cmd"
  fi
  __iv_status=$?
  printf '\033]6973;@@NONCE@@;%s;resume;done\007' "$__iv_parent"
  if [ "$__iv_owned" = 1 ]; then
    # Do not stop the master: in-flight SFTP channels own their lifetime.
    (command sleep 65; command rmdir "$__iv_dir" 2>/dev/null) </dev/null >/dev/null 2>&1 &
  fi
  return "$__iv_status"
}
