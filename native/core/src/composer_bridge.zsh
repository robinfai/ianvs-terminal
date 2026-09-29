# Private ZLE adapter. Explicitly duplicate the socket with close-on-exec:
# zsocket in system zsh 5.9 otherwise passes it to external programs.
# Startup happens only in the local zsh proxy; never sent as terminal input.
() {
  emulate -L zsh
  [[ -o interactive ]] || return
  zmodload zsh/zle || return
  zmodload zsh/net/socket || return
  zmodload zsh/system || return
  zsocket '@@SOCKET@@' || return
  local __ic_socket=$REPLY
  typeset -gi __ic_fd=-1 __ic_epoch=0 __ic_available=0
  if ! sysopen -rw -o cloexec -u __ic_fd /dev/fd/$__ic_socket; then
    exec {__ic_socket}<&-
    return
  fi
  exec {__ic_socket}<&-
  builtin print -r -u $__ic_fd -- $'hello\t@@NONCE@@'
  __ic_hex() {
    local LC_ALL=C char byte
    REPLY=''
    for char in ${(s::)1}; do
      builtin printf -v byte '%02x' "'$char"
      REPLY+=$byte
    done
  }
  # Read the shell's own history, including commands entered through raw ZLE.
  # No history file is opened and no command is evaluated. A complete snapshot
  # is bounded below the private channel's frame budget and published atomically.
  __ic_history() {
    emulate -L zsh
    zmodload zsh/parameter || return 0
    local LC_ALL=C entry command
    local -i count=0 bytes=0
    local -a events
    events=( ${(Onk)history} )
    builtin print -r -u $__ic_fd -- history-begin
    for entry in ${events[1,200]}; do
      command=$history[$entry]
      [[ -n $command && $command != [[:space:]]* ]] || continue
      (( ${#command} <= 4096 )) || continue
      (( bytes + ${#command} <= 8192 && count < 100 )) || break
      __ic_hex "$command"
      builtin print -r -u $__ic_fd -- $'history\t'"$REPLY"
      (( bytes += ${#command}, ++count ))
    done
    builtin print -r -u $__ic_fd -- history-end
  }
  __ic_aliases() {
    emulate -L zsh
    zmodload zsh/parameter || return 0
    local LC_ALL=C name value name_hex
    local -i count=0 bytes=0
    builtin print -r -u $__ic_fd -- aliases-begin
    for name in ${(ok)aliases}; do
      value=$aliases[$name]
      (( ${#name} <= 128 && ${#value} <= 1024 )) || continue
      (( bytes + ${#name} + ${#value} <= 2048 && count < 64 )) || break
      __ic_hex "$name"
      name_hex=$REPLY
      __ic_hex "$value"
      builtin print -r -u $__ic_fd -- $'alias\t'"$name_hex"$'\t'"$REPLY"
      (( bytes += ${#name} + ${#value}, ++count ))
    done
    builtin print -r -u $__ic_fd -- aliases-end
  }
  __ic_init() {
    emulate -L zsh
    (( __ic_fd >= 0 )) || return 0
    __ic_available=0
    if [[ $CONTEXT == start && -z $BUFFER && ${ZLE_RECURSIVE:-0} == 0 ]]; then
      (( ++__ic_epoch ))
      __ic_available=1
      __ic_history
      __ic_aliases
      __ic_hex "$PWD"
      builtin print -r -u $__ic_fd -- $'ready\t'"$__ic_epoch"$'\t'"$REPLY"
    else
      builtin print -r -u $__ic_fd -- continuation
    fi
  }
  __ic_busy() {
    if [[ -n ${__ic_payload+x} ]]; then
      bindkey -M "$__ic_keymap" '^@' "$__ic_old_widget"
      unset __ic_payload
    fi
    if (( __ic_available && __ic_fd >= 0 )); then
      __ic_available=0
      builtin print -r -u $__ic_fd -- busy
    fi
  }
  __ic_redraw() { [[ -z $BUFFER ]] || __ic_busy }
  __ic_receive() {
    emulate -L zsh
    setopt extendedglob
    local i wire action epoch id hex escaped='' pair
    if [[ -n $2 ]] || ! IFS= builtin read -r -t 1 wire <&$__ic_fd; then
      zle -F $__ic_fd
      if [[ -n ${__ic_payload+x} ]]; then
        bindkey -M "$__ic_keymap" '^@' "$__ic_old_widget"
        unset __ic_payload
      fi
      __ic_available=0
      exec {__ic_fd}<&-
      __ic_fd=-1
      return
    fi
    local -a fields
    fields=("${(@ps:\t:)wire}")
    action=$fields[1] epoch=$fields[2] id=$fields[3] hex=$fields[4]
    if [[ $action != submit || ${#fields} != 4 || $epoch != $__ic_epoch || $CONTEXT != start || -n $BUFFER || ${ZLE_RECURSIVE:-0} != 0 ]] || (( ! __ic_available )); then
      builtin print -r -u $__ic_fd -- $'rejected\t'"$id"
      return
    fi
    [[ $hex == [0-9a-f]## && ${#hex} -le 131072 && $(( ${#hex} % 2 )) == 0 ]] || return
    for (( i=1; i <= ${#hex}; i+=2 )); do
      pair=$hex[i,i+1]
      escaped+="\x$pair"
    done
    typeset -g __ic_payload=$escaped __ic_id=$id __ic_claim_epoch=$epoch __ic_keymap=$KEYMAP
    local binding
    binding=$(bindkey -M "$KEYMAP" '^@')
    typeset -g __ic_old_widget=${${(z)binding}[-1]}
    if [[ $__ic_old_widget != set-mark-command && $__ic_old_widget != undefined-key ]]; then
      builtin print -r -u $__ic_fd -- $'rejected\t'"$id"
      unset __ic_payload
      return
    fi
    bindkey -M "$KEYMAP" '^@' __ic_commit
    builtin print -r -u $__ic_fd -- $'prepared\t'"$id"
  }
  __ic_commit() {
    emulate -L zsh
    bindkey -M "$__ic_keymap" '^@' "$__ic_old_widget"
    if [[ $CONTEXT != start || -n $BUFFER || $__ic_claim_epoch != $__ic_epoch ]] || (( ! __ic_available )); then
      builtin print -r -u $__ic_fd -- $'rejected\t'"$__ic_id"
      unset __ic_payload
      return
    fi
    builtin printf -v BUFFER '%b' "$__ic_payload"
    CURSOR=${#BUFFER}
    __ic_available=0
    unset __ic_payload
    builtin print -r -u $__ic_fd -- $'accepted\t'"$__ic_id"
    zle .accept-line
  }
  zle -N __ic_commit
  setopt extendedglob
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget line-init __ic_init
  add-zle-hook-widget line-finish __ic_busy
  add-zle-hook-widget line-pre-redraw __ic_redraw
  add-zle-hook-widget isearch-update __ic_busy
  zle -N __ic_receive
  zle -F -w $__ic_fd __ic_receive
}
