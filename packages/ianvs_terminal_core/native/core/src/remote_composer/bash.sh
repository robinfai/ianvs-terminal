# Readline 4+ exposes the literal editing buffer to bind -x. Older Bash remains raw.
__ianvs_composer_install() {
  [[ $__iv_registered == 1 && $- == *i* && ${BASH_VERSINFO[0]} -ge 4 ]] || return
  [[ -o emacs || -o vi ]] || return
  if [[ -o vi ]]; then __ianvs_cmap=vi-insert; else __ianvs_cmap=emacs-standard; fi
  __ianvs_cepoch=0
  __ianvs_cavailable=0
  __ianvs_composer_emit() { builtin printf '\033]6973;@@SECRET@@;@@CONTEXT@@;composer;%s\007' "$1"; }
  __ianvs_inventory_emit() { __ianvs_composer_emit "$1"; }
  @@COMMAND_INVENTORY@@
  __ianvs_composer_resume_preexec() {
    # bash-preexec < 0.6 can consume its interactive flag for a bind -x command.
    # Restore it after our keybind so the accepted line reaches the real
    # preexec hook, after Readline has echoed it and advanced to the output row.
    if [[ "${__ianvs_bash_hook_backend:-}" == bash-preexec ]]; then
      __bp_interactive_mode force
    fi
  }
  __ianvs_composer_noop() { __ianvs_composer_resume_preexec; }
  __ianvs_composer_disarm() {
    bind -m "$__ianvs_cmap" -x '"\e[6975;@@SECRET@@~":__ianvs_composer_noop'
  }
  __ianvs_composer_ready() {
    # A syntax error or Ctrl+C in PS2 can return without any preexec hook.
    # The next manually entered command must not inherit that submission.
    unset __ianvs_pending_submission __ianvs_pending_command
    __ianvs_composer_disarm
    ((__ianvs_cepoch+=1))
    __ianvs_cavailable=1
    local cwd=$(builtin printf %s "$PWD" | command od -An -tx1 -v | command tr -d ' \n')
    local home=$(builtin printf %s "$HOME" | command od -An -tx1 -v | command tr -d ' \n')
    local name names='' count=0 LC_ALL=C
    while IFS= builtin read -r name; do
      [[ -n $name && $name != *[^a-zA-Z0-9_.-]* && ${#name} -le 128 ]] || continue
      (( count < 64 && ${#names} + ${#name} + 1 <= 2048 )) || break
      names+="${names:+,}$name"
      ((count+=1))
    done < <(builtin compgen -A alias)
    __ianvs_command_inventory "$__ianvs_cepoch"
    __ianvs_composer_emit "ready;$__ianvs_cepoch;$cwd;$home;$names"
  }
  __ianvs_composer_receive() {
    local wire epoch id hex escaped='' pair i
    __ianvs_composer_disarm
    IFS= builtin read -r -s -t 2 -n 131200 -d '!' wire || return
    epoch=${wire%%:*}; wire=${wire#*:}
    id=${wire%%:*}; hex=${wire#*:}
    [[ -n $id && $id != *[!a-zA-Z0-9-]* && ${#id} -le 80 ]] || return
    if [[ $epoch != "$__ianvs_cepoch" || $__ianvs_cavailable != 1 || -n $READLINE_LINE || ${READLINE_LINE+x} != x ]]; then
      __ianvs_composer_emit "rejected;$id"
      return
    fi
    [[ -n $hex && $hex != *[!0-9a-f]* && ${#hex} -le 131072 && $(( ${#hex} % 2 )) == 0 ]] || return
    for ((i=0; i<${#hex}; i+=2)); do
      pair=${hex:i:2}
      case "$pair" in 0[0-8b-f]|1[0-9a-f]|7f) return ;; esac
      escaped+="\x$pair"
    done
    builtin printf -v READLINE_LINE '%b' "$escaped"
    READLINE_POINT=${#READLINE_LINE}
    __ianvs_cavailable=0
    # Only a validated receive can arm the next key in our private macro.
    # Rejection leaves a no-op; it never accepts an existing user's line.
    bind -m "$__ianvs_cmap" '"\e[6975;@@SECRET@@~":accept-line'
    __ianvs_pending_submission=$id
    __ianvs_pending_command=$READLINE_LINE
    __ianvs_composer_emit "accepted;$id"
  }
  __ianvs_composer_dispatch() {
    __ianvs_composer_receive
    __ianvs_composer_resume_preexec
  }
  bind -m "$__ianvs_cmap" -x '"\e[6974;@@SECRET@@~":__ianvs_composer_dispatch'
  bind -m "$__ianvs_cmap" '"\e[6973;@@SECRET@@~":"\e[6974;@@SECRET@@~\e[6975;@@SECRET@@~"'
  __ianvs_composer_disarm
}
__ianvs_composer_install || true
