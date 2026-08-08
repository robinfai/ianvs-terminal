#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd -- "$script_dir/../.." && pwd)"
readonly compose_file="$script_dir/compose.yaml"
readonly fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/ianvs-ssh-e2e.XXXXXX")"
readonly project_name="ianvs-ssh-e2e-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
readonly image="ianvs-ssh-e2e:20260808"

export IANVS_SSH_E2E_IMAGE="$image"

cleanup() {
  local status=$?
  if ((status != 0)); then
    printf '%s\n' 'SSH acceptance failed; Docker service state and logs follow:' >&2
    docker compose --project-name "$project_name" --file "$compose_file" \
      ps --all >&2 || true
    docker compose --project-name "$project_name" --file "$compose_file" \
      logs --no-color --tail 30 >&2 || true
  fi
  docker compose --project-name "$project_name" --file "$compose_file" \
    down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -rf -- "$fixture_dir"
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

ssh-keygen -q -t ed25519 -N '' -f "$fixture_dir/id_ed25519"
cp "$fixture_dir/id_ed25519" "$fixture_dir/id_ed25519_encrypted"
ssh-keygen -q -p -P '' -N 'ianvs-e2e-key-passphrase' \
  -f "$fixture_dir/id_ed25519_encrypted"
ssh-keygen -q -t ed25519 -N '' -f "$fixture_dir/wrong_host_ed25519"
export IANVS_SSH_E2E_PUBLIC_KEY="$(<"$fixture_dir/id_ed25519.pub")"
readonly wrong_host_public_key="$(<"$fixture_dir/wrong_host_ed25519.pub")"
docker build --provenance=false \
  --build-arg SOURCE_DATE_EPOCH=1785542400 \
  --tag "$image" \
  "$script_dir"
docker compose --project-name "$project_name" --file "$compose_file" \
  up --detach --wait --wait-timeout 60

published_port() {
  local service="$1"
  local address
  local port
  address="$(docker compose --project-name "$project_name" --file "$compose_file" \
    port "$service" 22)"
  port="${address##*:}"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    printf 'could not resolve mapped port for %s: %s\n' "$service" "$address" >&2
    return 1
  fi
  printf '%s\n' "$port"
}

readonly password_port="$(published_port password)"
readonly keyboard_interactive_port="$(published_port keyboard-interactive)"
readonly otp_port="$(published_port otp)"
readonly public_key_port="$(published_port publickey)"
readonly jump_port="$(published_port jump)"
readonly forwarding_port="$(published_port forwarding)"
readonly target_port="$(docker compose --project-name "$project_name" \
  --file "$compose_file" port target 22 2>/dev/null || true)"
if [[ -n "$target_port" && "$target_port" != ":0" ]]; then
  printf 'target must not publish port 22 to the host: %s\n' "$target_port" >&2
  exit 1
fi

readonly test_list="$(cargo test --locked --manifest-path "$repository_root/native/core/Cargo.toml" \
  --test ssh_openssh_acceptance_test -- --ignored --list)"
readonly required_tests=(
  openssh_authentication_and_proxy_jump_acceptance
  openssh_host_key_policy_acceptance
  openssh_negative_paths_fail_fast
)
for test_name in "${required_tests[@]}"; do
  if ! grep -Fqx -- "$test_name: test" <<<"$test_list"; then
    printf 'required ignored acceptance test is missing: %s\n' "$test_name" >&2
    exit 1
  fi
done

IANVS_SSH_E2E_PASSWORD_PORT="$password_port" \
IANVS_SSH_E2E_KEYBOARD_INTERACTIVE_PORT="$keyboard_interactive_port" \
IANVS_SSH_E2E_OTP_PORT="$otp_port" \
IANVS_SSH_E2E_PUBLIC_KEY_PORT="$public_key_port" \
IANVS_SSH_E2E_JUMP_PORT="$jump_port" \
IANVS_SSH_E2E_FORWARDING_PORT="$forwarding_port" \
IANVS_SSH_E2E_TARGET_HOST=target \
IANVS_SSH_E2E_PRIVATE_KEY="$fixture_dir/id_ed25519" \
IANVS_SSH_E2E_ENCRYPTED_PRIVATE_KEY="$fixture_dir/id_ed25519_encrypted" \
IANVS_SSH_E2E_WRONG_HOST_PUBLIC_KEY="$wrong_host_public_key" \
  cargo test --locked --manifest-path "$repository_root/native/core/Cargo.toml" \
    --test ssh_openssh_acceptance_test -- \
    --ignored --nocapture --test-threads=1

printf '%s\n' \
  'SSH acceptance passed: auth, host-key strict/accept-new, negative timeouts, two-hop ProxyJump, L/R/D ports, X11, and agent forwarding.'
