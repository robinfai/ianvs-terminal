__iv_valid() {
  (( $+commands[od] && $+commands[tr] )) &&
  (( $+functions[__ianvs_emit_shell_hook] && $+functions[__ianvs_json_escape] &&
     $+functions[__ianvs_emit_preexec_hook] && $+functions[__ianvs_preexec] &&
     $+functions[__ianvs_precmd] && $+functions[__ianvs_restore_startup_prompt_state] &&
     $+functions[__ianvs_trim_startup_prompt_newline] )) &&
  (( ${preexec_functions[(Ie)__ianvs_preexec]} && ${precmd_functions[(Ie)__ianvs_precmd]} ))
}
