function __iv_valid
  command -sq od; and command -sq tr; or return 1
  functions -q __ianvs_preexec __ianvs_postexec __ianvs_prompt __ianvs_emit_shell_hook __ianvs_json_escape; or return 1
  functions __ianvs_preexec | string match -q '*--on-event fish_preexec*'; and functions __ianvs_postexec | string match -q '*--on-event fish_postexec*'; and functions __ianvs_prompt | string match -q '*--on-event fish_prompt*'
end
