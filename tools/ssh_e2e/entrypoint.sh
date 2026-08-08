#!/usr/bin/env bash
set -euo pipefail

: "${IANVS_SSH_E2E_ROLE:?IANVS_SSH_E2E_ROLE is required}"
: "${IANVS_SSH_E2E_AUTH_MODE:?IANVS_SSH_E2E_AUTH_MODE is required}"

readonly test_user=ianvs
readonly test_password=ianvs-e2e-password
readonly sshd_config=/etc/ssh/sshd_config.ianvs-e2e

if ! id -u "$test_user" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$test_user"
fi
printf '%s:%s\n' "$test_user" "$test_password" | chpasswd
install -d -m 0700 -o "$test_user" -g "$test_user" "/home/$test_user/.ssh"

case "$IANVS_SSH_E2E_AUTH_MODE" in
  publickey|jump|target|forwarding)
    : "${IANVS_SSH_E2E_PUBLIC_KEY:?IANVS_SSH_E2E_PUBLIC_KEY is required}"
    printf '%s\n' "$IANVS_SSH_E2E_PUBLIC_KEY" \
      >"/home/$test_user/.ssh/authorized_keys"
    chown "$test_user:$test_user" "/home/$test_user/.ssh/authorized_keys"
    chmod 0600 "/home/$test_user/.ssh/authorized_keys"
    ;;
  password|keyboard-interactive|otp)
    ;;
  *)
    printf 'unsupported IANVS_SSH_E2E_AUTH_MODE: %s\n' \
      "$IANVS_SSH_E2E_AUTH_MODE" >&2
    exit 64
    ;;
esac

printf '%s\n' "$IANVS_SSH_E2E_ROLE" > /etc/ianvs-ssh-e2e-role

cat >"$sshd_config" <<'EOF'
Port 22
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
PidFile /run/sshd.pid
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin no
AllowUsers ianvs
StrictModes yes
UseDNS no
PrintMotd no
PrintLastLog no
PermitTunnel no
PermitUserEnvironment no
GatewayPorts no
ClientAliveInterval 30
ClientAliveCountMax 2
LogLevel VERBOSE
Subsystem sftp internal-sftp
EOF

case "$IANVS_SSH_E2E_AUTH_MODE" in
  password)
    cat >>"$sshd_config" <<'EOF'
PasswordAuthentication yes
KbdInteractiveAuthentication no
PubkeyAuthentication no
UsePAM no
AuthenticationMethods password
AllowTcpForwarding no
AllowAgentForwarding no
X11Forwarding no
EOF
    ;;
  keyboard-interactive)
    cat >>"$sshd_config" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication yes
ChallengeResponseAuthentication yes
PubkeyAuthentication no
UsePAM yes
AuthenticationMethods keyboard-interactive:pam
AllowTcpForwarding no
AllowAgentForwarding no
X11Forwarding no
EOF
    ;;
  otp)
    cat >/etc/pam.d/sshd <<'EOF'
auth required pam_ianvs_otp.so
account required pam_permit.so
session required pam_permit.so
EOF
    cat >>"$sshd_config" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication yes
ChallengeResponseAuthentication yes
PubkeyAuthentication no
UsePAM yes
AuthenticationMethods keyboard-interactive:pam
AllowTcpForwarding no
AllowAgentForwarding no
X11Forwarding no
EOF
    ;;
  publickey|target)
    cat >>"$sshd_config" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
AuthenticationMethods publickey
AllowTcpForwarding no
AllowAgentForwarding no
X11Forwarding no
EOF
    ;;
  jump)
    : "${IANVS_SSH_E2E_PERMIT_OPEN:?IANVS_SSH_E2E_PERMIT_OPEN is required}"
    if [[ ! "$IANVS_SSH_E2E_PERMIT_OPEN" =~ ^[A-Za-z0-9._-]+:[0-9]+$ ]]; then
      printf 'invalid IANVS_SSH_E2E_PERMIT_OPEN: %s\n' \
        "$IANVS_SSH_E2E_PERMIT_OPEN" >&2
      exit 64
    fi
    cat >>"$sshd_config" <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
AuthenticationMethods publickey
AllowTcpForwarding local
PermitOpen $IANVS_SSH_E2E_PERMIT_OPEN
AllowAgentForwarding no
X11Forwarding no
EOF
    ;;
  forwarding)
    cat >>"$sshd_config" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
AuthenticationMethods publickey
AllowTcpForwarding yes
AllowAgentForwarding yes
X11Forwarding yes
X11UseLocalhost yes
X11DisplayOffset 10
PermitOpen any
EOF
    ;;
esac

ssh-keygen -A >/dev/null 2>&1
/usr/sbin/sshd -t -f "$sshd_config"
exec /usr/sbin/sshd -D -e -f "$sshd_config"
