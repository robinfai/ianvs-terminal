__ianvs_command_inventory() {
  local LC_ALL=C name chunk='' epoch=$1 count=0 bytes=0
  local -A seen=()
  # compgen is a builtin: discover names, never run a candidate or read bodies.
  while IFS= builtin read -r name; do
    [[ -n $name && $name != *[,\;[:space:][:cntrl:]]* && ${#name} -le 256 ]] || continue
    [[ $name != *[\$\`\(\)\{\}\[\]\\\"\'\&\|\<\>\*\?\!]* ]] || continue
    [[ $name != __ianvs_* && $name != __ic_* && -z ${seen[$name]-} ]] || continue
    seen[$name]=1
    (( count < 4096 && bytes + ${#name} + 1 <= 65536 )) || break
    if (( ${#chunk} + ${#name} + 1 > 4096 )); then
      __ianvs_inventory_emit "commands;$epoch;$chunk"
      chunk=''
    fi
    chunk+="${chunk:+,}$name"
    (( count+=1, bytes += ${#name} + 1 ))
  done < <(builtin compgen -c)
  __ianvs_inventory_emit "commands;$epoch;$chunk"
  __ianvs_inventory_emit "commands-end;$epoch"
}
