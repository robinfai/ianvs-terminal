#!/usr/bin/env bash
# shellcheck shell=bash

# Read-only navigation helper. This script does not execute verification.

set -u

cat <<'EOF'
Local terminal verification status

Current decision:
  verified

Verification authorization:
  authorized on 2026-05-16
  automated, integration, and manual/integration-backed gates have passing evidence
  docs/LOCAL_TERMINAL_VERIFICATION_AUTHORIZATION_GATE_2026-05.md

Latest automated evidence:
  build/local-terminal-verification/20260516T145142Z-all-automated
  format/analyze/focused completion/P1/P2-P5/verification-evidence batches passed
  build/local-terminal-verification/20260516T171224Z-static-analysis
  latest static-analysis rerun passed
  build/local-terminal-verification/20260516T171406Z-broader
  latest broader rerun passed
  build/local-terminal-verification/20260516T171327Z-verification-evidence
  latest verification-evidence rerun passed
  build/local-terminal-verification/20260516T171644Z-integration
  latest integration passed

Manual/integration-backed evidence:
  local shell smoke passed
  paste/focus safety passed
  multipane behavior passed after zoom fix
  notification behavior passed through broader and real PTY evidence
  hotkey-window failure path passed through visible-failure regression

Primary handoff:
  docs/LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md

Audit and status:
  docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md
  docs/LOCAL_TERMINAL_COMPLETION_AUDIT_SNAPSHOT_2026-05-16.md
  docs/LOCAL_TERMINAL_MILESTONE_IMPLEMENTATION_STATUS_2026-05.md
  docs/KNOWN_ISSUES.md

Verification execution:
  docs/LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md
  docs/LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md
  docs/LOCAL_TERMINAL_VERIFICATION_READINESS_CHECKLIST_2026-05.md

Evidence recording:
  docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md
  docs/LOCAL_TERMINAL_VERIFICATION_RECORD_EXAMPLES_2026-05.md
  docs/LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md
  docs/LOCAL_TERMINAL_EVIDENCE_RECORDING_RUNBOOK_2026-05.md
  docs/LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md

Helper scripts:
  bash tools/local_terminal_verification_batches.sh list
  bash tools/local_terminal_verification_batches.sh print all-automated
  bash tools/local_terminal_verification_capture.sh run broader
  bash tools/local_terminal_verification_capture.sh run integration
  bash tools/local_terminal_verification_batches.sh run all-automated
  bash tools/local_terminal_verification_capture.sh run all-automated

Notes:
  This status script does not run verification.
  Canonical records now include all required passing gates.
  Use ledger, manifest, LocalTerminalVerificationPlanRecords.latestPassed(), and LocalTerminalCurrentCompletionState.verified() as the completion evidence set.
EOF
