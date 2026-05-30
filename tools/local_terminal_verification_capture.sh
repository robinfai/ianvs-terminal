#!/usr/bin/env bash
# shellcheck shell=bash

# Local terminal verification capture helper.
# Read-only commands: list, print.
# Execution commands: run.
# This wrapper captures logs but never updates the canonical evidence ledger.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BATCH_SCRIPT="$ROOT_DIR/tools/local_terminal_verification_batches.sh"
CAPTURE_ROOT="${LOCAL_TERMINAL_VERIFICATION_CAPTURE_DIR:-$ROOT_DIR/build/local-terminal-verification}"

usage() {
  cat <<'EOF'
Usage:
  bash tools/local_terminal_verification_capture.sh list
  bash tools/local_terminal_verification_capture.sh print <batch>
  bash tools/local_terminal_verification_capture.sh print all-automated
  bash tools/local_terminal_verification_capture.sh run <batch>
  bash tools/local_terminal_verification_capture.sh run all-automated

This wrapper captures combined stdout/stderr and exit status under:
  build/local-terminal-verification/<timestamp>-<batch>/

It does not update docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md.
Copy the captured command, exit status, and output summary into the ledger.
Do not treat captured logs as objective closure until the ledger and audit checklist are updated.
EOF
}

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

batch_gate_hint() {
  case "$1" in
    formatting)
      echo "formatting"
      ;;
    static-analysis)
      echo "staticAnalysis"
      ;;
    completion)
      echo "unitTests, widgetTests"
      ;;
    p1|cross-milestone|p2-workspace|p3-productivity|p4-policy|p5-visual|verification-evidence|terminal-packages)
      echo "unitTests"
      ;;
    broader)
      echo "unitTests, widgetTests"
      ;;
    integration)
      echo "integrationTests"
      ;;
    manual)
      echo "manualLocalShellSmoke, manualPasteFocusSafety, manualMultipaneBehavior, manualNotificationBehavior, manualHotkeyWindowFailurePath"
      ;;
    all-automated)
      echo "formatting, staticAnalysis, unitTests, widgetTests"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

run_and_capture() {
  local batch="$1"
  local timestamp
  local safe_batch
  local output_dir
  local log_file
  local summary_file
  local ledger_file
  local gate_hint
  local status
  local final_status

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  safe_batch="$(safe_name "$batch")"
  gate_hint="$(batch_gate_hint "$batch")"
  output_dir="$CAPTURE_ROOT/$timestamp-$safe_batch"
  log_file="$output_dir/output.log"
  summary_file="$output_dir/summary.txt"
  ledger_file="$output_dir/ledger-entry.md"

  mkdir -p "$output_dir" || return 1

  {
    echo "batch: $batch"
    echo "started_at_utc: $timestamp"
    echo "working_directory: $ROOT_DIR"
    echo "command: bash tools/local_terminal_verification_batches.sh run $batch"
    echo "verification_gates: $gate_hint"
    echo "output_log: $log_file"
    echo "evidence_ledger: docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md"
    echo "started_status: running"
  } > "$summary_file"

  cd "$ROOT_DIR" || return 1

  echo "Running and capturing local-terminal verification batch: $batch"
  echo "This wrapper writes logs but does not update the canonical evidence ledger."
  echo "Review ledger-entry.md before copying any status into docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md."

  bash "$BATCH_SCRIPT" run "$batch" 2>&1 | tee "$log_file"
  status="${PIPESTATUS[0]}"
  if [ "$status" -eq 0 ]; then
    final_status="passed"
  else
    final_status="failed"
  fi

  {
    echo "finished_at_utc: $(date -u +%Y%m%dT%H%M%SZ)"
    echo "exit_status: $status"
    echo "status: $final_status"
  } >> "$summary_file"

  {
    echo "# Local Terminal Verification Ledger Entry"
    echo
    echo "| Field | Value |"
    echo "| --- | --- |"
    echo "| Batch | $batch |"
    echo "| Command | bash tools/local_terminal_verification_batches.sh run $batch |"
    echo "| Verification gates | $gate_hint |"
    echo "| Working directory | $ROOT_DIR |"
    echo "| Started at UTC | $timestamp |"
    echo "| Finished at UTC | $(date -u +%Y%m%dT%H%M%SZ) |"
    echo "| Exit status | $status |"
    echo "| Output log | $log_file |"
    echo "| Output summary | TBD |"
    echo "| Failing tests or issues | TBD |"
    echo "| Follow-up task, if needed | TBD |"
    echo "| Verification gate status | pending |"
    echo
    echo "Only change the gate status to passed after the captured output satisfies the gate rule."
    echo "If the exit status is non-zero, also add a row to docs/LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md."
  } > "$ledger_file"

  if [ "$status" -eq 0 ]; then
    echo "Captured successful batch output in $output_dir"
  else
    echo "Captured failing batch output in $output_dir" >&2
    echo "Record the blocker in docs/LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md" >&2
  fi

  return "$status"
}

main() {
  if [ "$#" -lt 1 ]; then
    usage
    return 2
  fi

  case "$1" in
    list)
      bash "$BATCH_SCRIPT" list
      ;;
    print)
      if [ "$#" -ne 2 ]; then
        usage
        return 2
      fi
      bash "$BATCH_SCRIPT" print "$2"
      ;;
    run)
      if [ "$#" -ne 2 ]; then
        usage
        return 2
      fi
      run_and_capture "$2"
      ;;
    *)
      usage
      return 2
      ;;
  esac
}

main "$@"
