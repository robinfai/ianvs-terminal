# Name-only snapshot of the live shell, including Unicode aliases/functions.
# No function body is read and no candidate command is invoked.
__ianvs_command_inventory() {
  emulate -L zsh
  zmodload zsh/parameter || return 0
  local LC_ALL=C name chunk='' epoch=$1 directory executable
  local -i count=0 bytes=0
  local -A seen
  # zsh's command hash can miss newly installed binaries even after hash -f.
  # Read PATH entries without clearing or rewriting the user's command hash.
  local -a discovered
  for directory in $path; do
    [[ -n $directory ]] || directory=.
    for executable in "$directory"/*(N); do
      [[ -f $executable && -x $executable ]] || continue
      discovered+=("${executable:t}")
      (( ${#discovered} < 8192 )) || break 2
    done
  done
  for name in ${(k)aliases} ${(k)functions} ${(k)builtins} $reswords $discovered ${(k)commands}; do
    [[ -n $name && $name != *[,\;[:space:][:cntrl:]]* && ${#name} -le 256 ]] || continue
    [[ $name != *[\$\`\(\)\{\}\[\]\\\"\'\&\|\<\>\*\?\!]* ]] || continue
    [[ $name != __ianvs_* && $name != __ic_* && -z ${seen[$name]-} ]] || continue
    seen[$name]=1
    # Hashed PATH entries can outlive their files. Builtins/functions win.
    if (( ! ${+aliases[$name]} && ! ${+functions[$name]} && ! ${+builtins[$name]} && ${+commands[$name]} )); then
      [[ -x $commands[$name] && ! -d $commands[$name] ]] || continue
    fi
    (( count < 4096 && bytes + ${#name} + 1 <= 65536 )) || break
    if (( ${#chunk} + ${#name} + 1 > 4096 )); then
      __ianvs_inventory_emit "commands;$epoch;$chunk"
      chunk=''
    fi
    chunk+="${chunk:+,}$name"
    (( ++count, bytes += ${#name} + 1 ))
  done
  __ianvs_inventory_emit "commands;$epoch;$chunk"
  __ianvs_inventory_emit "commands-end;$epoch"
}
