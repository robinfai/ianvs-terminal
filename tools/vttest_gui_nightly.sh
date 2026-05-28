#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tools/vttest_gui_nightly.sh [--release-gate] [--out-dir /absolute/output/dir]

Runs the vttest GUI/manual-nightly gate. In default mode, missing host
preconditions are reported as blocked and exit 0. In --release-gate mode,
blocked preconditions exit 2. Product/test failures exit 1 in both modes.
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
EXAMPLE_DIR="$ROOT_DIR/example"
release_gate="false"
timestamp="$(date '+%Y%m%dT%H%M%S%z')"
out_dir="$ROOT_DIR/build/vttest-gui-nightly/$timestamp"
command_timeout="${IANVS_VTTEST_COMMAND_TIMEOUT_SECONDS:-120}"
gui_timeout="${IANVS_VTTEST_GUI_TIMEOUT_SECONDS:-300}"
preflight_timeout="${IANVS_VTTEST_PREFLIGHT_TIMEOUT_SECONDS:-10}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-gate)
      release_gate="true"
      shift
      ;;
    --out-dir)
      if [[ $# -lt 2 ]]; then
        usage
        exit 1
      fi
      out_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${out_dir#/}" == "$out_dir" ]]; then
  echo "--out-dir must be an absolute path" >&2
  exit 1
fi

mkdir -p "$out_dir"
events_file="$out_dir/events.jsonl"
blocked_reasons_file="$out_dir/blocked-reasons.txt"
: >"$events_file"
: >"$blocked_reasons_file"

record_event() {
  local name="$1"
  local status="$2"
  local exit_code="$3"
  local log_path="${4:-}"
  local detail="${5:-}"
  python3 - "$events_file" "$name" "$status" "$exit_code" "$log_path" "$detail" <<'PY'
import json
import sys

events_file, name, status, exit_code, log_path, detail = sys.argv[1:]
with open(events_file, "a", encoding="utf-8") as handle:
    handle.write(json.dumps({
        "name": name,
        "status": status,
        "exitCode": int(exit_code),
        "log": log_path or None,
        "detail": detail or None,
    }, ensure_ascii=False) + "\n")
PY
}

write_summary() {
  local status="$1"
  local exit_code="$2"
  local failed_step="${3:-}"
  python3 - "$out_dir" "$events_file" "$blocked_reasons_file" "$status" "$exit_code" "$release_gate" "$failed_step" <<'PY'
import json
import os
import sys

out_dir, events_file, reasons_file, status, exit_code, release_gate, failed_step = sys.argv[1:]
events = []
if os.path.exists(events_file):
    with open(events_file, encoding="utf-8") as handle:
        events = [json.loads(line) for line in handle if line.strip()]
blocked_reasons = []
if os.path.exists(reasons_file):
    with open(reasons_file, encoding="utf-8") as handle:
        blocked_reasons = [line.rstrip("\n") for line in handle if line.strip()]
summary = {
    "status": status,
    "exitCode": int(exit_code),
    "releaseGate": release_gate == "true",
    "failedStep": failed_step or None,
    "blockedReasons": blocked_reasons,
    "events": events,
}
path = os.path.join(out_dir, "summary.json")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
print(path)
PY
}

add_blocked_reason() {
  local reason="$1"
  printf '%s\n' "$reason" >>"$blocked_reasons_file"
}

run_logged_command() {
  local timeout_seconds="$1"
  local log_path="$2"
  shift 2
  python3 - "$timeout_seconds" "$log_path" "$@" <<'PY'
import subprocess
import sys

timeout_seconds = int(sys.argv[1])
log_path = sys.argv[2]
command = sys.argv[3:]

with open(log_path, "w", encoding="utf-8") as log_file:
    def write_output(value):
        if not value:
            return
        if isinstance(value, bytes):
            value = value.decode("utf-8", "replace")
        log_file.write(value)

    try:
        process = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout_seconds,
        )
        write_output(process.stdout)
        sys.exit(process.returncode)
    except subprocess.TimeoutExpired as exc:
        write_output(exc.stdout)
        write_output(exc.stderr)
        sys.exit(124)
PY
}

run_step() {
  local name="$1"
  local timeout_seconds="$2"
  local log_path="$3"
  shift 3
  set +e
  run_logged_command "$timeout_seconds" "$log_path" "$@"
  local exit_code=$?
  set -e
  if [[ "$exit_code" -eq 0 ]]; then
    record_event "$name" "pass" "$exit_code" "$log_path"
    return 0
  fi
  record_event "$name" "fail" "$exit_code" "$log_path"
  return "$exit_code"
}

preflight_blocked="false"

if [[ "$(uname -s)" != "Darwin" ]]; then
  preflight_blocked="true"
  add_blocked_reason "vttest GUI gate requires macOS"
  record_event "preflight.macos" "blocked" 0 "" "uname -s is not Darwin"
else
  record_event "preflight.macos" "pass" 0 "" "macOS host"
fi

vttest_path="${IANVS_VTTEST_BIN:-}"
if [[ -z "$vttest_path" ]]; then
  vttest_path="$(command -v vttest 2>/dev/null || true)"
fi
if [[ -z "$vttest_path" || ! -x "$vttest_path" ]]; then
  preflight_blocked="true"
  add_blocked_reason "vttest executable not found; install with brew install vttest or set IANVS_VTTEST_BIN"
  record_event "preflight.vttest" "blocked" 0 "" "vttest not found"
else
  record_event "preflight.vttest" "pass" 0 "" "$vttest_path"
fi

user_id="$(id -u)"
gui_session="pass"
gui_detail="launchctl gui/$user_id and frontmost app query succeeded"
if ! launchctl print "gui/$user_id" >/dev/null 2>&1; then
  gui_session="blocked"
  gui_detail="launchctl gui/$user_id is unavailable"
fi
frontmost_log="$out_dir/frontmost-app.log"
set +e
run_logged_command \
  "$preflight_timeout" \
  "$frontmost_log" \
  osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'
frontmost_exit=$?
set -e
if [[ "$frontmost_exit" -ne 0 ]]; then
  gui_session="blocked"
  gui_detail="$gui_detail; AppleScript frontmost app query failed"
fi
if [[ "$gui_session" == "blocked" ]]; then
  preflight_blocked="true"
  add_blocked_reason "interactive macOS desktop session could not be confirmed"
fi
record_event "preflight.desktop-gui" "$gui_session" "$frontmost_exit" "$frontmost_log" "$gui_detail"

devices_log="$out_dir/flutter-devices.log"
set +e
run_logged_command "$command_timeout" "$devices_log" flutter devices
devices_exit=$?
set -e
if [[ "$devices_exit" -ne 0 ]]; then
  preflight_blocked="true"
  add_blocked_reason "flutter devices did not complete successfully"
  record_event "preflight.flutter-devices" "blocked" "$devices_exit" "$devices_log"
elif ! grep -Fq "macOS (desktop)" "$devices_log"; then
  preflight_blocked="true"
  add_blocked_reason "flutter devices did not list macOS (desktop)"
  record_event "preflight.flutter-devices" "blocked" 0 "$devices_log" "macOS desktop device missing"
else
  record_event "preflight.flutter-devices" "pass" 0 "$devices_log"
fi

if [[ "$preflight_blocked" == "true" ]]; then
  if [[ "$release_gate" == "true" ]]; then
    write_summary "blocked" 2 "preflight" >/dev/null
    echo "vttest GUI gate blocked; summary: $out_dir/summary.json" >&2
    exit 2
  fi
  write_summary "blocked" 0 "preflight" >/dev/null
  echo "vttest GUI gate blocked; summary: $out_dir/summary.json"
  exit 0
fi

build_log="$out_dir/build-core.log"
if ! run_step "build.core" "$command_timeout" "$build_log" "$ROOT_DIR/tools/build_core.sh"; then
  write_summary "failed" 1 "build.core" >/dev/null
  echo "vttest GUI gate failed; summary: $out_dir/summary.json" >&2
  exit 1
fi

core_lib="$CORE_DIR/target/debug/libianvs_core.dylib"
if [[ ! -f "$core_lib" ]]; then
  record_event "preflight.core-lib" "fail" 1 "" "$core_lib not found after build"
  write_summary "failed" 1 "preflight.core-lib" >/dev/null
  echo "vttest GUI gate failed; summary: $out_dir/summary.json" >&2
  exit 1
fi
record_event "preflight.core-lib" "pass" 0 "" "$core_lib"

if ! (
  cd "$CORE_DIR"
  run_step \
    "cargo.vttest-regression" \
    "$command_timeout" \
    "$out_dir/cargo-vttest-regression.log" \
    cargo test --test vttest_regression_test
); then
  write_summary "failed" 1 "cargo.vttest-regression" >/dev/null
  echo "vttest GUI gate failed; summary: $out_dir/summary.json" >&2
  exit 1
fi

if ! (
  cd "$CORE_DIR"
  run_step \
    "cargo.vt220" \
    "$command_timeout" \
    "$out_dir/cargo-vt220.log" \
    cargo test vt220
); then
  write_summary "failed" 1 "cargo.vt220" >/dev/null
  echo "vttest GUI gate failed; summary: $out_dir/summary.json" >&2
  exit 1
fi

if ! (
  cd "$EXAMPLE_DIR"
  run_step \
    "flutter.viewport-wraparound" \
    "$command_timeout" \
    "$out_dir/flutter-viewport-wraparound.log" \
    flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport repaints consecutive full-width wrapped rows without leaving a shorter middle row"
); then
  write_summary "failed" 1 "flutter.viewport-wraparound" >/dev/null
  echo "vttest GUI gate failed; summary: $out_dir/summary.json" >&2
  exit 1
fi

if ! (
  cd "$EXAMPLE_DIR"
  IANVS_CORE_LIB="$core_lib" IANVS_VTTEST_BIN="$vttest_path" run_step \
    "flutter.vttest-gui" \
    "$gui_timeout" \
    "$out_dir/flutter-test.log" \
    flutter test -d macos integration_test/vttest_gui_test.dart
); then
  write_summary "failed" 1 "flutter.vttest-gui" >/dev/null
  echo "vttest GUI gate failed; summary: $out_dir/summary.json" >&2
  exit 1
fi

write_summary "pass" 0 "" >/dev/null
echo "vttest GUI gate passed; summary: $out_dir/summary.json"
