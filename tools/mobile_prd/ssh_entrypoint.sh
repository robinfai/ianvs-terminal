#!/bin/sh
set -eu
umask 077
mkdir -p /run/sshd /run/mobile-prd /home/lab
chown lab:lab /home/lab
ssh-keygen -q -t ed25519 -N '' -f /run/mobile-prd/host_key
cat >/run/mobile-prd/sshd_config <<'EOF'
Port 22
ListenAddress 0.0.0.0
HostKey /run/mobile-prd/host_key
PidFile /run/mobile-prd/sshd.pid
PermitRootLogin no
AllowUsers lab
PasswordAuthentication yes
KbdInteractiveAuthentication no
PubkeyAuthentication no
UsePAM no
PermitEmptyPasswords no
PermitUserEnvironment no
AllowTcpForwarding no
AllowAgentForwarding no
X11Forwarding no
PermitTunnel no
UseDNS no
PrintMotd no
PrintLastLog no
LogLevel ERROR
Subsystem sftp internal-sftp
EOF
cat >/home/lab/.zshrc <<'EOF'
PROMPT='lab@dev-box %~ %# '
RPROMPT=''
HISTFILE=''
EOF
chown lab:lab /home/lab/.zshrc
exec /usr/sbin/sshd -D -e -f /run/mobile-prd/sshd_config
