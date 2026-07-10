#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/example"
APP_PATH="$EXAMPLE_DIR/build/macos/Build/Products/Release/Ianvs Terminal.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/Ianvs Terminal"
TIMEOUT_SECONDS="${IANVS_RELEASE_REFRESH_GATE_TIMEOUT_SECONDS:-180}"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ianvs-release-refresh-gate.XXXXXX")"
STDOUT_LOG="$LOG_DIR/stdout.log"
STDERR_LOG="$LOG_DIR/stderr.log"

cleanup() {
  rm -f "$STDOUT_LOG" "$STDERR_LOG"
  rmdir "$LOG_DIR"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "release real PTY refresh gate requires macOS" >&2
  exit 1
fi

if ! [[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "IANVS_RELEASE_REFRESH_GATE_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 1
fi

cd "$EXAMPLE_DIR"
flutter build macos \
  --release \
  --target=integration_test/real_pty_acceptance_test.dart \
  --dart-define=IANVS_STANDALONE_RELEASE_TEST_GATE=true \
  --dart-define=IANVS_REFRESH_POLICY_GATE_ONLY=true \
  --dart-define=IANVS_REFRESH_HINT_LIMIT_MS=250 \
  --dart-define=IANVS_REFRESH_FALLBACK_LIMIT_MS=750

# Preserve hardened runtime while making the no-certificate local build
# launchable. Certificate-signed builds keep their existing signature.
"$ROOT_DIR/tools/sign_local_macos_release.sh" "$APP_PATH"

runner_status=0
if python3 "$ROOT_DIR/tools/run_process_group_with_timeout.py" \
  "$TIMEOUT_SECONDS" \
  "$STDOUT_LOG" \
  "$STDERR_LOG" \
  "$APP_EXECUTABLE"
then
  runner_status=0
else
  runner_status=$?
fi

sed -n '1,260p' "$STDOUT_LOG"
sed -n '1,160p' "$STDERR_LOG" >&2

if (( runner_status != 0 )); then
  echo "release real PTY refresh gate app exited with status $runner_status" >&2
  exit "$runner_status"
fi

if grep -Fqx \
  'IANVS_STANDALONE_RELEASE_TEST_RESULT=passed tests=3' \
  "$STDOUT_LOG"; then
  exit 0
fi

echo "release real PTY refresh gate did not report three passing tests" >&2
exit 1
