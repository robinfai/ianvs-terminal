#!/usr/bin/env bash
#
# End-to-end acceptance for the Ianvs SSH Profile Vault.
#
# Builds the embedded web UI and the API binary, starts one local and one
# remote (dev-HTTP) server against throwaway SQLite databases, and drives both
# through a real Chrome instance with Playwright.
#
# Environment overrides:
#   GO            Go toolchain (default: go)
#   PNPM          pnpm executable (default: pnpm)
#   WEBUI_REMOTE_PORT  port for the dev remote server (default: a free port)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEBUI_DIR="$ROOT/backend/webui"
BACKEND_DIR="$ROOT/backend"
BIN="$BACKEND_DIR/bin/ianvs-api"

GO="${GO:-go}"
PNPM="${PNPM:-pnpm}"
REMOTE_PORT="${WEBUI_REMOTE_PORT:-}"

free_port() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
    return 0
  fi
  echo 47933
}

# Keep generated build artifacts away from the backend package tree (which a
# contract test scans for environment access). Reuse Go's module cache so this
# acceptance test can run offline after dependencies have been downloaded.
CACHE_ROOT="$ROOT/.tmp-home/webui-verify-$$"
TMP_DIR=""
SERVER_PIDS=()

cleanup() {
  local pid alive
  for pid in "${SERVER_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  # Brief grace period for graceful shutdown, then force-kill stragglers.
  for _ in $(seq 1 25); do
    alive=0
    for pid in "${SERVER_PIDS[@]:-}"; do
      if kill -0 "$pid" 2>/dev/null; then
        alive=1
        break
      fi
    done
    if [[ "$alive" -eq 0 ]]; then
      break
    fi
    sleep 0.2
  done
  for pid in "${SERVER_PIDS[@]:-}"; do
    kill -9 "$pid" 2>/dev/null || true
  done
  chmod -R u+w "$CACHE_ROOT" 2>/dev/null || true
  rm -rf "$CACHE_ROOT" 2>/dev/null || true
  rm -rf "${TMP_DIR:-}" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$CACHE_ROOT/gocache"
export GOCACHE="$CACHE_ROOT/gocache"

echo "==> Building web UI"
( cd "$WEBUI_DIR" && "$PNPM" install --frozen-lockfile && "$PNPM" test:unit && "$PNPM" build )

echo "==> Building ianvs-api"
mkdir -p "$BACKEND_DIR/bin"
( cd "$BACKEND_DIR" && "$GO" build -o "$BIN" ./cmd/ianvs-api )

TMP_DIR="$(mktemp -d)"
chmod 700 "$TMP_DIR"

echo "==> Generating local access token"
LOCAL_TOKEN="$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n')"

start_server() {
  local name="$1" config="$2"
  local ready="$TMP_DIR/$name.ready"
  "$BIN" serve --config "$config" >"$ready" 2>"$TMP_DIR/$name.log" &
  local pid=$!
  # Must append in the caller's scope (not a command-substitution subshell) so
  # cleanup can reach the PID and terminate the server.
  SERVER_PIDS+=("$pid")
  local url=""
  for _ in $(seq 1 200); do
    if grep -q 'IANVS_API_READY=' "$ready" 2>/dev/null; then
      url="$(sed -n 's/.*IANVS_API_READY=//p' "$ready" | tail -n 1)"
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "error: $name server exited before readiness" >&2
      cat "$TMP_DIR/$name.log" >&2
      return 1
    fi
    sleep 0.1
  done
  if [[ -z "$url" ]]; then
    echo "error: $name server never became ready" >&2
    cat "$TMP_DIR/$name.log" >&2
    return 1
  fi
  SERVER_URL="$url"
}

cat > "$TMP_DIR/local.json" <<EOF
{
  "schema_version": 1,
  "mode": "local",
  "address": "127.0.0.1:0",
  "database_driver": "sqlite",
  "database_dsn": "$TMP_DIR/local.db",
  "local_access_token": "$LOCAL_TOKEN",
  "exit_on_stdin_close": false,
  "auth_token_ttl_seconds": 86400,
  "allow_registration": false,
  "allow_insecure_sensitive_transport": false,
  "trust_proxy_headers": false
}
EOF

if [[ -z "$REMOTE_PORT" ]]; then
  REMOTE_PORT="$(free_port)"
fi

cat > "$TMP_DIR/remote.json" <<EOF
{
  "schema_version": 1,
  "mode": "remote",
  "address": "127.0.0.1:$REMOTE_PORT",
  "database_driver": "sqlite",
  "database_dsn": "$TMP_DIR/remote.db",
  "local_access_token": "",
  "exit_on_stdin_close": false,
  "auth_token_ttl_seconds": 86400,
  "allow_registration": true,
  "allow_insecure_sensitive_transport": true,
  "trust_proxy_headers": false
}
EOF
chmod 600 "$TMP_DIR/local.json" "$TMP_DIR/remote.json"

echo "==> Starting local and remote servers"
start_server local "$TMP_DIR/local.json"
LOCAL_URL="$SERVER_URL"
start_server remote "$TMP_DIR/remote.json"
REMOTE_URL="$SERVER_URL"
echo "    local:  $LOCAL_URL"
echo "    remote: $REMOTE_URL"

echo "==> Running Playwright acceptance tests"
(
  cd "$WEBUI_DIR"
  WEBUI_LOCAL_URL="$LOCAL_URL" \
    WEBUI_LOCAL_TOKEN="$LOCAL_TOKEN" \
    WEBUI_REMOTE_URL="$REMOTE_URL" \
    "$PNPM" exec playwright test --config e2e/playwright.config.ts
)

echo "==> SSH Profile Vault acceptance passed"
