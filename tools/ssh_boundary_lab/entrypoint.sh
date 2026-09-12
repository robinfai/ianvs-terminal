#!/bin/bash
set -euo pipefail
ssh-keygen -A
install -m 600 -o lab -g lab /fixture/client.pub /home/lab/.ssh/authorized_keys
install -m 600 -o lab -g lab /fixture/client /home/lab/.ssh/id_ed25519
install -m 600 -o lab -g lab /fixture/wrong /home/lab/.ssh/wrong
chsh -s "/usr/bin/${LAB_SHELL:-bash}" lab
if [[ "${LAB_PASSWORD:-no}" == yes ]]; then
  printf '%s\n' 'lab:fixture-boundary-password' | chpasswd
fi
cat > /home/lab/.ssh/config <<'EOF'
Host *
  User lab
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  BatchMode yes
  StrictHostKeyChecking yes
  UserKnownHostsFile ~/.ssh/known_hosts
  ConnectTimeout 3
  ConnectionAttempts 1
  LogLevel ERROR
EOF
cat > /home/lab/.bashrc <<'EOF'
PS1='LAB_PROMPT> '
HISTCONTROL=ignorespace
HISTFILE=/home/lab/.bash_history
EOF
printf '%s\n' '. ~/.bashrc' > /home/lab/.bash_profile
printf '%s\n' "PROMPT='LAB_PROMPT> '" 'setopt HIST_IGNORE_SPACE' 'HISTFILE=~/.zsh_history' > /home/lab/.zshrc
# Completion generation is unrelated to hooks and expensive under strace.
printf '%s\n' 'skip_global_compinit=1' > /home/lab/.zshenv
mkdir -p /home/lab/.config/fish
cat > /home/lab/.config/fish/config.fish <<'EOF'
function fish_prompt
  printf 'LAB_PROMPT> '
end
EOF
if [[ "${LAB_STARTUP:-}" == debug ]]; then
  printf '%s\n' "trap ':' DEBUG" >> /home/lab/.bashrc
elif [[ "${LAB_STARTUP:-}" == stale ]]; then
  printf '%s\n' '__IANVS_SHELL_INTEGRATION_LOADED=1' >> /home/lab/.bashrc
elif [[ "${LAB_STARTUP:-}" == preloaded ]]; then
  # This is deliberately a server-provided hook, present before injection.
  cat /fixture/bash-hook >> /home/lab/.bashrc
elif [[ "${LAB_STARTUP:-}" == switch ]]; then
  printf '%s\n' 'exec /usr/bin/fish -i' >> /home/lab/.bashrc
elif [[ "${LAB_STARTUP:-}" == noisy ]]; then
  printf '%s\n' "printf 'UNEXPECTED_STARTUP_OUTPUT\\n'" >> /home/lab/.bashrc
elif [[ "${LAB_STARTUP:-}" == tmux ]]; then
  printf '%s\n' '[[ -n "${TMUX:-}" ]] || exec tmux new-session -s boundary' >> /home/lab/.bashrc
elif [[ "${LAB_STARTUP:-}" == history ]]; then
  printf '%s\n' 'HISTCONTROL=' >> /home/lab/.bashrc
elif [[ "${LAB_STARTUP:-}" == nohelpers ]]; then
  mkdir -p /fixture/nohelpers
  printf '%s\n' 'PATH=/fixture/nohelpers' >> /home/lab/.bashrc
fi
printf '%s\n' "${LAB_ROLE:-unknown}" > /home/lab/role.txt
mkdir -p /home/lab/work
chown -R lab:lab /home/lab
cat > /etc/ssh/sshd_config <<EOF
Port 22
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_ed25519_key
PidFile /run/sshd.pid
AuthorizedKeysFile .ssh/authorized_keys
PubkeyAuthentication yes
PasswordAuthentication ${LAB_PASSWORD:-no}
KbdInteractiveAuthentication no
PermitEmptyPasswords no
UsePAM no
PermitRootLogin no
AllowUsers lab
PrintMotd no
PrintLastLog no
LogLevel VERBOSE
PermitTTY ${LAB_TTY:-yes}
AllowTcpForwarding ${LAB_FORWARDING:-yes}
MaxSessions ${LAB_MAX_SESSIONS:-10}
EOF
if [[ "${LAB_SFTP:-yes}" == yes ]]; then
  printf '%s\n' 'Subsystem sftp internal-sftp' >> /etc/ssh/sshd_config
fi
if [[ "${LAB_FORCE:-}" == yes ]]; then
  printf '%s\n' 'ForceCommand /bin/echo FORCE_COMMAND_ONLY' >> /etc/ssh/sshd_config
fi
/usr/sbin/sshd -t
if [[ "${LAB_READONLY:-no}" == yes ]]; then
  chmod -R a-w /home/lab /tmp
fi
exec strace -ff -qq -s 128 -o /run/sshd.trace -e trace=%file /usr/sbin/sshd -D -e
