command stty sane
set -gx IANVS_SHELL_INTEGRATION 1
set -l __iv_source installed
set -l __iv_registered 0
@@CHECK@@
if __iv_valid
  set __iv_source reused
else
  set -e __IANVS_SHELL_INTEGRATION_LOADED
@@INSTALLER@@
end
if __iv_valid
  set __iv_registered 1
else
  set __iv_source helpers_missing
end
set -gx __IANVS_CONTEXT @@CONTEXT@@
set -g __IANVS_PROTOCOL_VERSION 1
function __ianvs_emit_shell_hook
  set -l __iv_json (string sub --end -1 -- "$argv[1]")
  set -l __iv_hex (printf '%s,"context_id":"%s"}' "$__iv_json" "$__IANVS_CONTEXT" | command od -An -tx1 -v | command tr -d ' \n')
  printf '\033Phook;%s\033\\' "$__iv_hex"
end
@@WRAPPER@@
set -g __ianvs_command_active 0
set -g __ianvs_last_command ''
printf '\033]6973;@@NONCE@@;@@CONTEXT@@;ready;%s;%s;fish\007' "$__iv_source" "$__iv_registered"

functions -e __iv_valid
