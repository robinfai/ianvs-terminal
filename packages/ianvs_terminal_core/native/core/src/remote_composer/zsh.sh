# Installed only during the controlled bootstrap, after the user's rc files.
__ianvs_composer_install() {
  emulate -L zsh
  [[ $__iv_registered == 1 && -o interactive && -o zle ]] || return
  autoload -Uz add-zle-hook-widget || return
  typeset -gi __ianvs_cepoch=0 __ianvs_cavailable=0
  __ianvs_composer_emit() { builtin printf '\033]6973;@@SECRET@@;@@CONTEXT@@;composer;%s\007' "$1" }
  __ianvs_inventory_emit() { __ianvs_composer_emit "$1" }
  @@COMMAND_INVENTORY@@
  __ianvs_composer_ready() {
    emulate -L zsh
    __ianvs_cavailable=0
    if [[ $CONTEXT == start && -z $BUFFER && ${ZLE_RECURSIVE:-0} == 0 ]]; then
      unset __ianvs_pending_submission __ianvs_pending_command
      (( ++__ianvs_cepoch ))
      __ianvs_cavailable=1
      local cwd=$(builtin printf %s "$PWD" | command od -An -tx1 -v | command tr -d ' \n')
      local home=$(builtin printf %s "$HOME" | command od -An -tx1 -v | command tr -d ' \n')
      local name names='' LC_ALL=C
      local -i count=0
      for name in ${(ok)aliases}; do
        [[ -n $name && $name != *[^a-zA-Z0-9_.-]* && ${#name} -le 128 ]] || continue
        (( count < 64 && ${#names} + ${#name} + 1 <= 2048 )) || break
        names+="${names:+,}$name"
        (( ++count ))
      done
      __ianvs_command_inventory "$__ianvs_cepoch"
      __ianvs_composer_emit "ready;$__ianvs_cepoch;$cwd;$home;$names"
    else
      __ianvs_composer_emit suspended
    fi
  }
  __ianvs_composer_busy() {
    if (( __ianvs_cavailable )); then
      __ianvs_cavailable=0
      __ianvs_composer_emit busy
    fi
  }
  __ianvs_composer_redraw() { [[ -z $BUFFER ]] || __ianvs_composer_busy }
  __ianvs_composer_receive() {
    emulate -L zsh
    setopt extendedglob
    local wire epoch id hex escaped='' chunk='' decoded
    local -i i
    local -a chunks match mbegin mend
    # No command evaluation: decode literal bytes only after validating ownership.
    # Keep per-byte reads so a partial frame still times out and bytes after '!'
    # remain in ZLE. Appending to the entire frame for every byte is quadratic;
    # collect bounded chunks and join once instead.
    local char
    for (( i=0; i < 131200; ++i )); do
      IFS= builtin read -r -k 1 -t 2 char || return
      [[ $char == '!' ]] && break
      chunk+=$char
      if (( ${#chunk} == 1024 )); then
        chunks+=("$chunk")
        chunk=''
      fi
    done
    [[ $char == '!' ]] || return
    wire="${(j::)chunks}$chunk"
    epoch=${wire%%:*}; wire=${wire#*:}
    id=${wire%%:*}; hex=${wire#*:}
    [[ $id == [a-zA-Z0-9-]## && ${#id} -le 80 ]] || return
    if [[ $epoch != $__ianvs_cepoch || $CONTEXT != start || -n $BUFFER || ${ZLE_RECURSIVE:-0} != 0 ]] || (( ! __ianvs_cavailable )); then
      __ianvs_composer_emit "rejected;$id"
      return
    fi
    [[ $hex == [0-9a-f]## && ${#hex} -le 131072 && $(( ${#hex} % 2 )) == 0 ]] || return
    for (( i=1; i <= ${#hex}; i+=1024 )); do
      chunk=$hex[i,i+1023]
      decoded=${chunk//(#b)(??)/\\x$match[1]}
      # Match complete byte escapes so a low nibble and the next high nibble
      # cannot be mistaken for a control. Tab and newline remain allowed.
      if [[ $decoded == (*\\x0[0-8b-f]*|*\\x1[0-9a-f]*|*\\x7f*) ]]; then return; fi
      escaped+=$decoded
    done
    builtin printf -v BUFFER '%b' "$escaped"
    CURSOR=${#BUFFER}
    __ianvs_cavailable=0
    typeset -g __ianvs_pending_submission=$id
    typeset -g __ianvs_pending_command=$BUFFER
    __ianvs_composer_emit "accepted;$id"
    zle .accept-line
  }
  zle -N __ianvs_composer_receive
  for keymap in emacs viins; do
    bindkey -M "$keymap" $'\e[6973;@@SECRET@@~' __ianvs_composer_receive
  done
  add-zle-hook-widget line-init __ianvs_composer_ready
  add-zle-hook-widget line-finish __ianvs_composer_busy
  add-zle-hook-widget line-pre-redraw __ianvs_composer_redraw
  add-zle-hook-widget isearch-update __ianvs_composer_busy
}
__ianvs_composer_install || true
