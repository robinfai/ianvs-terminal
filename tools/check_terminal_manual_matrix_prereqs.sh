#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
TIMEOUT_SECONDS="${FLUTTER_RUN_TIMEOUT_SECONDS:-60}"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M %Z')"
RUN_LOG="$(mktemp -t terminal-manual-matrix-run.XXXXXX.log)"

vttest_status="blocked"
vttest_detail="command -v vttest did not return a path; standard preparation path: brew install vttest"
if vttest_path="$(command -v vttest 2>/dev/null)"; then
  vttest_status="pass"
  vttest_detail="vttest available at $vttest_path"
fi

cd "$APP_DIR"

set +e
flutter test integration_test/flutterm_smoke_test.dart
smoke_exit=$?

python3 - "$TIMEOUT_SECONDS" "$RUN_LOG" <<'PY'
import subprocess
import sys

timeout_seconds = int(sys.argv[1])
log_path = sys.argv[2]
command = ["flutter", "run", "-d", "macos"]

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
run_exit=$?
set -e

smoke_status="fail"
smoke_detail="integration smoke failed (exit code $smoke_exit)"
if [[ "$smoke_exit" -eq 0 ]]; then
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

Observed evidence:
- \`command -v vttest\`: $vttest_status
  - $vttest_detail
- \`flutter test integration_test/flutterm_smoke_test.dart\`: $smoke_status
  - $smoke_detail
- \`flutter run -d macos\`: $run_status
  - $run_detail
  - exit code: $run_exit
  - timeout: ${TIMEOUT_SECONDS}s
  - Dart VM Service observed: $vm_service_observed
  - \`Failed to foreground app; open returned 1\` observed: $foreground_failure_observed
  - log: $RUN_LOG

Paste-ready record:
- \`command -v vttest\`: $vttest_status
  - $vttest_detail
- \`integration_test/flutterm_smoke_test.dart\`: $smoke_status
  - $smoke_detail
- \`flutter run -d macos\`: $run_status
  - $run_detail
  - exit code: $run_exit
  - Dart VM Service observed: $vm_service_observed
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
