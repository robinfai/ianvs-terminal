#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
EXAMPLE_DIR="$ROOT_DIR/example"
TEST_TARGET="test_http/local_first_sync_http_acceptance_test.dart"
GO="${GO:-go}"
FLUTTER="${FLUTTER:-flutter}"

umask 077
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ianvs-local-first-http.XXXXXX")"
API_BIN="$FIXTURE_DIR/ianvs-api"
API_CONFIG="$FIXTURE_DIR/api-config.json"
API_STDOUT="$FIXTURE_DIR/api.stdout"
API_STDERR="$FIXTURE_DIR/api.stderr"
DEFINES_FILE="$FIXTURE_DIR/acceptance-defines.json"
API_PID=""

cleanup() {
  local status=$?
  if [[ -n "$API_PID" ]]; then
    kill "$API_PID" >/dev/null 2>&1 || true
    wait "$API_PID" 2>/dev/null || true
  fi
  if [[ -n "$FIXTURE_DIR" && "$FIXTURE_DIR" == */ianvs-local-first-http.* ]]; then
    rm -rf -- "$FIXTURE_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

echo "==> Building isolated Ianvs Data API"
(
  cd "$BACKEND_DIR"
  "$GO" build -o "$API_BIN" ./cmd/ianvs-api
)

python3 - "$API_CONFIG" "$FIXTURE_DIR/remote.db" <<'PY'
import json
import socket
import sys

config_path, database_path = sys.argv[1:]
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
with open(config_path, "w", encoding="utf-8") as output:
    json.dump(
        {
            "schema_version": 1,
            "mode": "remote",
            "address": f"127.0.0.1:{port}",
            "database_driver": "sqlite",
            "database_dsn": database_path,
            "local_access_token": "",
            "exit_on_stdin_close": False,
            "auth_token_ttl_seconds": 3600,
            "allow_registration": True,
            "allow_insecure_sensitive_transport": True,
            "trust_proxy_headers": False,
        },
        output,
    )
PY
chmod 600 "$API_CONFIG"

echo "==> Starting throwaway loopback API"
"$API_BIN" serve --config "$API_CONFIG" >"$API_STDOUT" 2>"$API_STDERR" &
API_PID=$!

API_URL=""
for _ in $(seq 1 200); do
  API_URL="$(sed -n 's/^IANVS_API_READY=//p' "$API_STDOUT" | tail -n 1)"
  if [[ -n "$API_URL" ]]; then
    break
  fi
  if ! kill -0 "$API_PID" 2>/dev/null; then
    echo "The isolated Data API exited before becoming ready." >&2
    sed -n '1,120p' "$API_STDERR" >&2
    exit 1
  fi
  sleep 0.05
done
if [[ "$API_URL" != http://127.0.0.1:* ]]; then
  echo "The isolated Data API did not publish a loopback readiness URL." >&2
  sed -n '1,120p' "$API_STDERR" >&2
  exit 1
fi

python3 - "$DEFINES_FILE" "$API_URL" <<'PY'
import base64
import json
import secrets
import sys

path, api_url = sys.argv[1:]
with open(path, "w", encoding="utf-8") as output:
    json.dump(
        {
            "IANVS_LOCAL_FIRST_HTTP_API_URL": api_url,
            "IANVS_LOCAL_FIRST_HTTP_USERNAME": f"sync-http-{secrets.token_hex(8)}",
            "IANVS_LOCAL_FIRST_HTTP_PASSWORD": f"sync-http-{secrets.token_hex(16)}",
            "IANVS_LOCAL_FIRST_HTTP_ENCRYPTION_KEY": base64.b64encode(
                secrets.token_bytes(32)
            ).decode("ascii"),
        },
        output,
    )
PY
chmod 600 "$DEFINES_FILE"

echo "==> Running real HTTP local-first sync acceptance"
(
  cd "$EXAMPLE_DIR"
  "$FLUTTER" test --no-pub "$TEST_TARGET" \
    --dart-define-from-file="$DEFINES_FILE" \
    --reporter compact
)

echo "==> Real HTTP local-first sync acceptance passed"
