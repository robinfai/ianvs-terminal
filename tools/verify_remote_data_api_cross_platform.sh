#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/example"
TEST_TARGET="integration_test/remote_data_api_sync_acceptance_test.dart"
IOS_GATE_TARGET="integration_test/ios_remote_api_gate_acceptance_test.dart"
IOS_SIMULATOR_UDID="${IANVS_IOS_SIMULATOR_UDID:-}"
RESULT_FILE="${IANVS_ACCEPTANCE_RESULT_FILE:-/private/tmp/ianvs-cross-platform-acceptance.status}"
rm -f "$RESULT_FILE"

if [[ -z "${IANVS_ACCEPTANCE_REMOTE_API_URL:-}" ]]; then
  IANVS_ACCEPTANCE_REMOTE_API_URL="https://ianvs-api.43.132.135.30.nip.io:57321/"
fi
if [[ -z "${IANVS_ACCEPTANCE_REMOTE_USERNAME:-}" || \
      -z "${IANVS_ACCEPTANCE_REMOTE_PASSWORD:-}" || \
      -z "${IANVS_ACCEPTANCE_REMOTE_ENCRYPTION_KEY:-}" ]]; then
  if [[ ! -t 0 ]]; then
    echo "Acceptance credentials are required in a non-interactive run." >&2
    exit 2
  fi
  read -r -p "Acceptance username: " IANVS_ACCEPTANCE_REMOTE_USERNAME
  read -r -s -p "Acceptance password: " IANVS_ACCEPTANCE_REMOTE_PASSWORD
  printf '\n'
  read -r -s -p "Acceptance data encryption key: " \
    IANVS_ACCEPTANCE_REMOTE_ENCRYPTION_KEY
  printf '\n'
fi
if [[ -z "$IANVS_ACCEPTANCE_REMOTE_USERNAME" || \
      -z "$IANVS_ACCEPTANCE_REMOTE_PASSWORD" || \
      -z "$IANVS_ACCEPTANCE_REMOTE_ENCRYPTION_KEY" ]]; then
  echo "Acceptance username, password, and data encryption key are required." >&2
  exit 2
fi
export IANVS_ACCEPTANCE_REMOTE_API_URL
export IANVS_ACCEPTANCE_REMOTE_USERNAME
export IANVS_ACCEPTANCE_REMOTE_PASSWORD
export IANVS_ACCEPTANCE_REMOTE_ENCRYPTION_KEY

if [[ "${IANVS_ACCEPTANCE_REMOTE_API_URL}" != https://* ]]; then
  echo "The cross-platform acceptance API must use HTTPS." >&2
  exit 2
fi

if [[ -z "$IOS_SIMULATOR_UDID" ]]; then
  IOS_SIMULATOR_UDID="$(
    xcrun simctl list devices available | awk '
      /^-- iOS / { in_ios = 1; next }
      /^-- / { in_ios = 0 }
      in_ios && /iPhone/ && /\(Booted\)/ {
        if (match($0, /[0-9A-Fa-f-]{36}/)) {
          print substr($0, RSTART, RLENGTH)
          exit
        }
      }
    '
  )"
fi
if [[ ! "$IOS_SIMULATOR_UDID" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  echo "Boot an iPhone simulator or set IANVS_IOS_SIMULATOR_UDID." >&2
  exit 2
fi

resource_id="sync-$(openssl rand -hex 12)"
defines_file="$(mktemp "${TMPDIR:-/tmp}/ianvs-sync-acceptance.XXXXXX.json")"
credentials_file="$(mktemp "${TMPDIR:-/tmp}/ianvs-sync-credentials.XXXXXX.json")"
broker_ready_file="$(mktemp "${TMPDIR:-/tmp}/ianvs-sync-broker.XXXXXX.txt")"
chmod 600 "$defines_file" "$credentials_file" "$broker_ready_file"
broker_pid=""
remote_resource_created=0

cleanup() {
  local status=$?
  if [[ "$remote_resource_created" == "1" && -f "$defines_file" ]]; then
    run_phase macos cleanup >/dev/null 2>&1 || true
  fi
  if [[ -n "$broker_pid" ]]; then
    kill "$broker_pid" >/dev/null 2>&1 || true
    wait "$broker_pid" 2>/dev/null || true
  fi
  rm -f "$defines_file" "$credentials_file" "$broker_ready_file"
  if [[ -n "$RESULT_FILE" ]]; then
    printf '%s\n' "$status" >"$RESULT_FILE"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

python3 - "$credentials_file" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(
        {
            "username": os.environ["IANVS_ACCEPTANCE_REMOTE_USERNAME"],
            "password": os.environ["IANVS_ACCEPTANCE_REMOTE_PASSWORD"],
            "encryption_key": os.environ["IANVS_ACCEPTANCE_REMOTE_ENCRYPTION_KEY"],
        },
        output,
    )
PY

/usr/bin/env -i \
  "PATH=$PATH" \
  python3 "$ROOT_DIR/tools/serve_acceptance_credentials.py" \
  "$credentials_file" "$broker_ready_file" &
broker_pid=$!
for _ in {1..600}; do
  [[ -s "$broker_ready_file" ]] && break
  kill -0 "$broker_pid" 2>/dev/null || {
    echo "The acceptance credential broker exited before becoming ready." >&2
    exit 1
  }
  sleep 0.05
done
if [[ ! -s "$broker_ready_file" ]]; then
  echo "The acceptance credential broker did not become ready within 30 seconds." >&2
  exit 1
fi
credentials_url="$(cat "$broker_ready_file")"
if [[ "$credentials_url" != http://127.0.0.1:*/* ]]; then
  echo "The acceptance credential broker did not publish a loopback URL." >&2
  exit 1
fi

test_env=(
  /usr/bin/env -i
  "HOME=$HOME"
  "PATH=$PATH"
  "TMPDIR=${TMPDIR:-/tmp}"
  "LANG=${LANG:-en_US.UTF-8}"
  "LC_ALL=${LC_ALL:-en_US.UTF-8}"
)
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  test_env+=("DEVELOPER_DIR=$DEVELOPER_DIR")
fi
if [[ -n "${TOOLCHAINS:-}" ]]; then
  test_env+=("TOOLCHAINS=$TOOLCHAINS")
fi

write_defines() {
  local phase="$1"
  python3 - "$defines_file" "$phase" "$resource_id" "$credentials_url" <<'PY'
import json
import os
import sys

path, phase, resource_id, credentials_url = sys.argv[1:]
payload = {
    "IANVS_ACCEPTANCE_REMOTE_API_URL": os.environ["IANVS_ACCEPTANCE_REMOTE_API_URL"],
    "IANVS_ACCEPTANCE_CREDENTIALS_URL": credentials_url,
    "IANVS_ACCEPTANCE_SYNC_PHASE": phase,
    "IANVS_ACCEPTANCE_SYNC_RESOURCE_ID": resource_id,
}
with open(path, "w", encoding="utf-8") as output:
    json.dump(payload, output)
PY
}

run_phase() {
  local device="$1"
  local phase="$2"
  write_defines "$phase"
  (
    cd "$EXAMPLE_DIR"
    "${test_env[@]}" flutter test --no-pub -d "$device" "$TEST_TARGET" \
      --dart-define-from-file="$defines_file" --reporter compact
  )
}

(
  cd "$EXAMPLE_DIR"
  "${test_env[@]}" flutter test --no-pub -d "$IOS_SIMULATOR_UDID" \
    "$IOS_GATE_TARGET" --reporter compact
)
run_phase macos macos-write
remote_resource_created=1
run_phase "$IOS_SIMULATOR_UDID" ios-read-write
run_phase macos macos-read-cleanup
remote_resource_created=0
