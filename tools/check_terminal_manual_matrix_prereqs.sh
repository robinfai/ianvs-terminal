#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/example"
TIMEOUT_SECONDS="${FLUTTER_RUN_TIMEOUT_SECONDS:-60}"
COMMAND_TIMEOUT_SECONDS="${FLUTTER_COMMAND_TIMEOUT_SECONDS:-120}"
SMOKE_TIMEOUT_SECONDS="${FLUTTER_SMOKE_TIMEOUT_SECONDS:-180}"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M %Z')"
HOST_NAME="$(hostname -s 2>/dev/null || hostname)"
MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
MACOS_BUILD="$(sw_vers -buildVersion 2>/dev/null || echo unknown)"
USER_ID="$(id -u)"
RUN_LOG="$(mktemp -t terminal-manual-matrix-run.XXXXXX.log)"
FLUTTER_VERSION_LOG="$(mktemp -t terminal-manual-matrix-flutter-version.XXXXXX.log)"
FLUTTER_DOCTOR_LOG="$(mktemp -t terminal-manual-matrix-flutter-doctor.XXXXXX.log)"
FLUTTER_DEVICES_LOG="$(mktemp -t terminal-manual-matrix-flutter-devices.XXXXXX.log)"
SMOKE_LOG="$(mktemp -t terminal-manual-matrix-flutter-smoke.XXXXXX.log)"

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
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        output, _ = process.communicate(timeout=timeout_seconds)
        log_file.write(output or "")
        sys.exit(process.returncode if process.returncode is not None else 0)
    except subprocess.TimeoutExpired:
        process.kill()
        output, _ = process.communicate()
        log_file.write(output or "")
        sys.exit(124)
PY
}

stdin_tty="no"
if [[ -t 0 ]]; then
  stdin_tty="yes"
fi

http_proxy_value="${http_proxy:-${HTTP_PROXY:-unset}}"
https_proxy_value="${https_proxy:-${HTTPS_PROXY:-unset}}"
all_proxy_value="${all_proxy:-${ALL_PROXY:-unset}}"
no_proxy_value="${no_proxy:-${NO_PROXY:-unset}}"
loopback_no_proxy_ready="no"
case ",${no_proxy_value}," in
  *,127.0.0.1,*)
    case ",${no_proxy_value}," in
      *,localhost,*)
        case ",${no_proxy_value}," in
          *,::1,*) loopback_no_proxy_ready="yes" ;;
        esac
        ;;
    esac
    ;;
esac

ssh_session="no"
if [[ -n "${SSH_CONNECTION:-}" ]]; then
  ssh_session="yes"
fi

launchctl_gui_session="no"
if launchctl print "gui/$USER_ID" >/dev/null 2>&1; then
  launchctl_gui_session="yes"
fi

frontmost_query_status="no"
frontmost_query_detail="AppleScript could not query a frontmost app"
if frontmost_query_output="$(
  osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>&1
)"; then
  frontmost_query_status="yes"
  frontmost_query_detail="frontmost app: $frontmost_query_output"
else
  frontmost_query_detail="$frontmost_query_output"
fi

desktop_gui_session="unknown"
desktop_gui_session_detail="could not confirm a local GUI desktop session"
if [[ "$ssh_session" == "yes" ]]; then
  desktop_gui_session="no"
  desktop_gui_session_detail="SSH_CONNECTION is set for this shell"
elif [[ "$launchctl_gui_session" == "yes" && "$frontmost_query_status" == "yes" ]]; then
  desktop_gui_session="yes"
  desktop_gui_session_detail="launchctl gui/$USER_ID is available and AppleScript can query the frontmost app"
elif [[ "$launchctl_gui_session" == "yes" || "$frontmost_query_status" == "yes" ]]; then
  desktop_gui_session_detail="partial GUI evidence present; re-run from Terminal or iTerm inside the logged-in macOS desktop session"
fi

vttest_status="blocked"
vttest_detail="command -v vttest did not return a path; standard preparation path: brew install vttest"
if vttest_path="$(command -v vttest 2>/dev/null)"; then
  vttest_status="pass"
  vttest_detail="vttest available at $vttest_path"
fi

cd "$APP_DIR"

set +e
run_logged_command "$COMMAND_TIMEOUT_SECONDS" "$FLUTTER_VERSION_LOG" flutter --version
flutter_version_exit=$?

run_logged_command "$COMMAND_TIMEOUT_SECONDS" "$FLUTTER_DOCTOR_LOG" flutter doctor -v
flutter_doctor_exit=$?

run_logged_command "$COMMAND_TIMEOUT_SECONDS" "$FLUTTER_DEVICES_LOG" flutter devices
flutter_devices_exit=$?

run_logged_command "$SMOKE_TIMEOUT_SECONDS" "$SMOKE_LOG" flutter test integration_test/flutterm_smoke_test.dart
smoke_exit=$?

run_logged_command "$TIMEOUT_SECONDS" "$RUN_LOG" flutter run -d macos
run_exit=$?
set -e

flutter_version_status="fail"
flutter_version_detail="flutter --version failed (exit code $flutter_version_exit)"
if [[ "$flutter_version_exit" -eq 124 ]]; then
  flutter_version_detail="flutter --version timed out after ${COMMAND_TIMEOUT_SECONDS}s"
elif [[ "$flutter_version_exit" -eq 0 ]]; then
  flutter_version_status="pass"
  flutter_framework_line="$(sed -n '1p' "$FLUTTER_VERSION_LOG")"
  flutter_tools_line="$(sed -n '4p' "$FLUTTER_VERSION_LOG")"
  flutter_version_detail="$flutter_framework_line"
  if [[ -n "$flutter_tools_line" ]]; then
    flutter_version_detail="$flutter_version_detail | $flutter_tools_line"
  fi
fi

flutter_doctor_status="blocked"
flutter_doctor_detail="flutter doctor -v did not complete successfully"
if [[ -s "$FLUTTER_DOCTOR_LOG" ]]; then
  flutter_doctor_summary="$(
    python3 - "$FLUTTER_DOCTOR_LOG" <<'PY'
import re
import sys

pattern = re.compile(r"^(Doctor summary|\[[^]]+\]|! Doctor found issues)")
with open(sys.argv[1], encoding="utf-8") as handle:
    lines = [line.strip() for line in handle if pattern.match(line)]
print(" | ".join(lines))
PY
  )"
else
  flutter_doctor_summary=""
fi
if [[ "$flutter_doctor_exit" -eq 124 ]]; then
  flutter_doctor_detail="flutter doctor -v timed out after ${COMMAND_TIMEOUT_SECONDS}s"
  if [[ -n "$flutter_doctor_summary" ]]; then
    flutter_doctor_detail="$flutter_doctor_detail | $flutter_doctor_summary"
  fi
elif [[ "$flutter_doctor_exit" -eq 0 ]]; then
  flutter_doctor_status="pass"
  flutter_doctor_detail="${flutter_doctor_summary:-flutter doctor -v completed without reported issues}"
elif [[ -n "$flutter_doctor_summary" ]]; then
  flutter_doctor_detail="$flutter_doctor_summary"
fi

flutter_devices_status="blocked"
flutter_devices_detail="macOS device is not listed in flutter devices"
macos_device_line="$(grep -F 'macOS (desktop)' "$FLUTTER_DEVICES_LOG" | head -n 1 || true)"
if [[ -n "$macos_device_line" ]]; then
  flutter_devices_status="pass"
  flutter_devices_detail="$macos_device_line"
elif [[ "$flutter_devices_exit" -eq 124 ]]; then
  flutter_devices_detail="flutter devices timed out after ${COMMAND_TIMEOUT_SECONDS}s"
elif [[ "$flutter_devices_exit" -ne 0 ]]; then
  flutter_devices_status="fail"
  flutter_devices_detail="flutter devices failed (exit code $flutter_devices_exit)"
fi

smoke_status="fail"
smoke_detail="integration smoke failed (exit code $smoke_exit)"
if [[ "$smoke_exit" -eq 124 ]]; then
  smoke_status="blocked"
  smoke_detail="integration smoke timed out after ${SMOKE_TIMEOUT_SECONDS}s"
elif [[ "$smoke_exit" -eq 0 ]]; then
  smoke_status="pass"
  smoke_detail="integration smoke passed"
fi

vm_service_observed="no"
if grep -Fq "A Dart VM Service on macOS is available at:" "$RUN_LOG"; then
  vm_service_observed="yes"
fi

foreground_failure_observed="no"
if grep -Fq "Failed to foreground app; open returned 1" "$RUN_LOG"; then
  foreground_failure_observed="yes"
fi

app_bundle_path="$(
  find "$APP_DIR/build/macos/Build/Products/Debug" -maxdepth 1 -type d -name '*.app' 2>/dev/null |
    head -n 1 || true
)"
app_bundle_observed="no"
if [[ -n "$app_bundle_path" ]]; then
  app_bundle_observed="yes"
fi

app_process_observed="no"
if [[ "$vm_service_observed" == "yes" ]] || grep -Fq "Syncing files to device macOS..." "$RUN_LOG"; then
  app_process_observed="yes"
fi

run_status="blocked"
run_detail="script-only preflight cannot prove foreground interaction; keep this run blocked until a human confirms the app is interactive on a standard macOS desktop"
if [[ "$foreground_failure_observed" == "yes" ]]; then
  run_detail="runner reported foreground failure; treat this host as blocked until rechecked on a standard interactive macOS machine"
elif [[ "$run_exit" -ne 0 && "$run_exit" -ne 124 ]]; then
  run_status="fail"
  run_detail="flutter run exited unexpectedly before manual GUI verification could complete"
elif [[ "$run_exit" -eq 124 ]]; then
  run_detail="timed out after ${TIMEOUT_SECONDS}s; replace with pass only if foreground interaction was manually confirmed during the run"
fi

cat <<EOF
Terminal manual matrix preflight ($TIMESTAMP)

Local host evidence:
- host: $HOST_NAME
- macOS: $MACOS_VERSION ($MACOS_BUILD)
- desktop GUI session likely: $desktop_gui_session
  - $desktop_gui_session_detail
  - stdin attached to tty: $stdin_tty
  - SSH session detected: $ssh_session
  - launchctl gui/$USER_ID available: $launchctl_gui_session
  - AppleScript frontmost query: $frontmost_query_status
  - $frontmost_query_detail
  - http_proxy: $http_proxy_value
  - https_proxy: $https_proxy_value
  - all_proxy: $all_proxy_value
  - no_proxy: $no_proxy_value
  - loopback no_proxy ready: $loopback_no_proxy_ready

Flutter environment:
- \`flutter --version\`: $flutter_version_status
  - $flutter_version_detail
  - log: $FLUTTER_VERSION_LOG
- \`flutter doctor -v\`: $flutter_doctor_status
  - $flutter_doctor_detail
  - log: $FLUTTER_DOCTOR_LOG
- \`flutter devices\`: $flutter_devices_status
  - $flutter_devices_detail
  - log: $FLUTTER_DEVICES_LOG

Observed evidence:
- \`command -v vttest\`: $vttest_status
  - $vttest_detail
- \`flutter test integration_test/flutterm_smoke_test.dart\`: $smoke_status
  - $smoke_detail
  - log: $SMOKE_LOG
- \`flutter run -d macos\`: $run_status
  - $run_detail
  - exit code: $run_exit
  - timeout: ${TIMEOUT_SECONDS}s
  - Dart VM Service observed: $vm_service_observed
  - app bundle observed: $app_bundle_observed
  - app bundle path: ${app_bundle_path:-not found}
  - app process likely observed: $app_process_observed
  - \`Failed to foreground app; open returned 1\` observed: $foreground_failure_observed
  - log: $RUN_LOG

Paste-ready record:
- host: $HOST_NAME
- macOS: $MACOS_VERSION ($MACOS_BUILD)
- desktop GUI session likely: $desktop_gui_session
  - $desktop_gui_session_detail
  - stdin attached to tty: $stdin_tty
  - SSH session detected: $ssh_session
  - launchctl gui/$USER_ID available: $launchctl_gui_session
  - AppleScript frontmost query: $frontmost_query_status
  - http_proxy: $http_proxy_value
  - https_proxy: $https_proxy_value
  - all_proxy: $all_proxy_value
  - no_proxy: $no_proxy_value
  - loopback no_proxy ready: $loopback_no_proxy_ready
- \`flutter --version\`: $flutter_version_status
  - $flutter_version_detail
- \`flutter doctor -v\`: $flutter_doctor_status
  - $flutter_doctor_detail
- \`flutter devices\`: $flutter_devices_status
  - $flutter_devices_detail
- \`command -v vttest\`: $vttest_status
  - $vttest_detail
- \`integration_test/flutterm_smoke_test.dart\`: $smoke_status
  - $smoke_detail
  - log: $SMOKE_LOG
- \`flutter run -d macos\`: $run_status
  - $run_detail
  - exit code: $run_exit
  - Dart VM Service observed: $vm_service_observed
  - app bundle observed: $app_bundle_observed
  - app bundle path: ${app_bundle_path:-not found}
  - app process likely observed: $app_process_observed
  - \`Failed to foreground app; open returned 1\` observed: $foreground_failure_observed
  - foreground interaction manually confirmed: no
  - if you manually confirmed foreground interaction during this run, replace this item with \`pass\` and set the confirmation field to \`yes\`

Manual matrix placeholders:
- \`VT220 vttest\`: pass/fail/blocked
- \`powerline / ANSI prompt fidelity\`: pass/fail/blocked
- \`trackpad scrollback\`: pass/fail/blocked
- \`font-metric / DPI resize\`: pass/fail/blocked

If any matrix item is \`fail\`, split a focused task with:
- minimal repro
- impact range
- verification command or manual acceptance line
- If a matrix item stays \`blocked\` because of host/tooling conditions, continue the environment-unblock lane before returning to T-055
EOF
