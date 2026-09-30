#!/usr/bin/env bash
# Same-user, loopback-only independent-peer smoke gate. Docker gates still own
# OpenSSH/password/PAM/OTP, network-isolated ProxyJump, and pinned peer coverage.
set -euo pipefail
umask 077

readonly repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/ianvs-linux-loopback.XXXXXX")"
readonly fixture
readonly python="${IANVS_LOOPBACK_PYTHON:-$(command -v python3 || true)}"
readonly rz="${IANVS_LOOPBACK_RZ:-$(command -v rz || true)}"
readonly sz="${IANVS_LOOPBACK_SZ:-$(command -v sz || true)}"
server_pid=
cleanup() {
  local status=$?
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if ((status != 0)) && [[ -f "$fixture/peer.log" ]]; then
    tail -50 "$fixture/peer.log" >&2
  fi
  rm -rf -- "$fixture"
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

[[ "$(uname -s)" == Linux ]] || { echo 'This smoke gate requires Linux.' >&2; exit 1; }
for tool in "$python" "$rz" "$sz" /bin/bash; do
  [[ "$tool" == /* && -x "$tool" ]] || { echo "Missing absolute executable path: $tool" >&2; exit 1; }
done
"$python" -c 'import asyncssh' || {
  echo 'Install tools/linux_e2e/requirements.txt into a venv and set IANVS_LOOPBACK_PYTHON.' >&2
  exit 1
}
ssh-keygen -q -t ed25519 -N '' -f "$fixture/host_key"
ssh-keygen -q -t ed25519 -N '' -f "$fixture/client_key"
readonly test_user="ianvs-loopback"
mkdir -p "$fixture/home"
printf 'ianvs-linux-loopback-v1\n' > "$fixture/marker"
"$python" "$repository_root/tools/linux_e2e/peer.py" "$fixture" "$test_user" > "$fixture/peer.log" 2>&1 &
server_pid=$!
for attempt in {1..100}; do
  [[ -s "$fixture/port" ]] && break
  kill -0 "$server_pid" 2>/dev/null || { echo 'Loopback peer exited during setup.' >&2; exit 1; }
  sleep .1
done
[[ -s "$fixture/port" ]] || { echo 'Loopback peer did not start within 10 seconds.' >&2; exit 1; }

export IANVS_LOOPBACK_ROOT="$fixture"
export IANVS_LOOPBACK_PORT="$(cat "$fixture/port")"
export IANVS_LOOPBACK_USER="$test_user"
export IANVS_LOOPBACK_RZ="$rz"
export IANVS_LOOPBACK_SZ="$sz"
printf 'Independent loopback peer: %s; %s; %s\n' "$(cat "$fixture/peer.log")" "$("$rz" --version)" "$("$sz" --version)"
# Optional Cargo flags allow a prebuilt release/target cache to be reused.
timeout --kill-after=5 600 cargo test --locked --manifest-path "$repository_root/native/core/Cargo.toml" \
  "$@" --test linux_loopback_acceptance_test -- --ignored --nocapture --test-threads=1
