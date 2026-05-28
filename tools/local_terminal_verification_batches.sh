#!/usr/bin/env bash
# shellcheck shell=bash

# Local terminal verification batch helper.
# Read-only commands: list, print.
# Execution commands: run.
# This script never updates the canonical evidence ledger.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  bash tools/local_terminal_verification_batches.sh list
  bash tools/local_terminal_verification_batches.sh print <batch>
  bash tools/local_terminal_verification_batches.sh print all-automated
  bash tools/local_terminal_verification_batches.sh run <batch>
  bash tools/local_terminal_verification_batches.sh run all-automated

Batches:
  formatting
  static-analysis
  completion
  p1
  cross-milestone
  p2-workspace
  p3-productivity
  p4-policy
  p5-visual
  verification-evidence
  broader
  integration
  manual

Notes:
  This script does not update the evidence ledger.
  Record real outputs in docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md.
  Do not treat a zero exit status as objective closure until the ledger and audit checklist are updated.
EOF
}

list_batches() {
  cat <<'EOF'
formatting
static-analysis
completion
p1
cross-milestone
p2-workspace
p3-productivity
p4-policy
p5-visual
verification-evidence
broader
integration
manual
EOF
}

print_batch() {
  case "$1" in
    formatting)
      cat <<'EOF'
dart format example/lib example/test
EOF
      ;;
    static-analysis)
      cat <<'EOF'
flutter analyze
EOF
      ;;
    completion)
      cat <<'EOF'
flutter test \
  example/test/shell/local_terminal_current_completion_state_test.dart \
  example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart \
  example/test/shell/local_terminal_pending_completion_snapshot_factory_test.dart \
  example/test/shell/local_terminal_shell_ui_wiring_facade_test.dart \
  example/test/shell/local_terminal_shell_ui_wiring_snapshot_test.dart \
  example/test/shell/local_terminal_completion_evidence_report_test.dart \
  example/test/shell/local_terminal_completion_summary_test.dart \
  example/test/shell/local_terminal_completion_diagnostics_view_model_test.dart \
  example/test/shell/local_terminal_completion_diagnostics_actions_test.dart \
  example/test/shell/local_terminal_completion_menu_model_test.dart \
  example/test/shell/local_terminal_completion_command_menu_adapter_test.dart \
  example/test/shell/local_terminal_completion_diagnostics_bundle_test.dart \
  example/test/shell/local_terminal_completion_diagnostics_presentation_test.dart \
  example/test/shell/local_terminal_completion_diagnostics_panel_test.dart \
  example/test/shell/local_terminal_completion_shell_command_menu_diagnostics_test.dart
EOF
      ;;
    p1)
      cat <<'EOF'
flutter test \
  example/test/shell/shell_action_production_action_set_test.dart \
  example/test/shell/shell_action_production_callbacks_test.dart \
  example/test/shell/shell_action_production_wiring_state_test.dart \
  example/test/shell/shell_action_production_executor_test.dart \
  example/test/shell/shell_action_production_runtime_adapter_test.dart \
  example/test/shell/shell_action_production_wiring_report_test.dart \
  example/test/shell/shell_action_production_audit_snapshot_test.dart \
  example/test/shell/shell_action_production_closure_manifest_test.dart \
  example/test/shell/local_terminal_action_domain_router_test.dart \
  example/test/shell/local_terminal_domain_wiring_summary_test.dart
EOF
      ;;
    cross-milestone)
      cat <<'EOF'
flutter test \
  example/test/shell/local_terminal_production_wiring_bundle_test.dart \
  example/test/shell/local_terminal_production_wiring_manifest_builder_test.dart
EOF
      ;;
    p2-workspace)
      cat <<'EOF'
flutter test example/test/workspace
EOF
      ;;
    p3-productivity)
      cat <<'EOF'
flutter test example/test/productivity
EOF
      ;;
    p4-policy)
      cat <<'EOF'
flutter test example/test/policies
EOF
      ;;
    p5-visual)
      cat <<'EOF'
flutter test example/test/visual
EOF
      ;;
    verification-evidence)
      cat <<'EOF'
flutter test example/test/shell/local_terminal_verification_*test.dart
EOF
      ;;
    broader)
      cat <<'EOF'
flutter test example/test
EOF
      ;;
    integration)
      cat <<'EOF'
PROFILE=debug tools/build_core.sh
cd example
IANVS_CORE_LIB="$(pwd)/../native/core/target/debug/libianvs_core.dylib" \
  flutter test -d macos integration_test/ianvs_smoke_test.dart
IANVS_CORE_LIB="$(pwd)/../native/core/target/debug/libianvs_core.dylib" \
  flutter test -d macos integration_test/real_pty_acceptance_test.dart
EOF
      ;;
    manual)
      cat <<'EOF'
Use docs/LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md.
Record observations in docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md.
EOF
      ;;
    *)
      echo "Unknown batch: $1" >&2
      return 2
      ;;
  esac
}

print_all_automated() {
  for batch in \
    formatting \
    static-analysis \
    completion \
    p1 \
    cross-milestone \
    p2-workspace \
    p3-productivity \
    p4-policy \
    p5-visual \
    verification-evidence \
    broader
  do
    echo "# Batch: $batch"
    print_batch "$batch"
    echo
  done
}

run_batch() {
  cd "$ROOT_DIR" || return 1

  echo "Running local-terminal verification batch: $1"
  echo "This script does not update docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md."
  echo "Record command output and gate status manually before claiming closure."

  case "$1" in
    formatting)
      dart format example/lib example/test
      ;;
    static-analysis)
      flutter analyze
      ;;
    completion)
      flutter test \
        example/test/shell/local_terminal_current_completion_state_test.dart \
        example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart \
        example/test/shell/local_terminal_pending_completion_snapshot_factory_test.dart \
        example/test/shell/local_terminal_shell_ui_wiring_facade_test.dart \
        example/test/shell/local_terminal_shell_ui_wiring_snapshot_test.dart \
        example/test/shell/local_terminal_completion_evidence_report_test.dart \
        example/test/shell/local_terminal_completion_summary_test.dart \
        example/test/shell/local_terminal_completion_diagnostics_view_model_test.dart \
        example/test/shell/local_terminal_completion_diagnostics_actions_test.dart \
        example/test/shell/local_terminal_completion_menu_model_test.dart \
        example/test/shell/local_terminal_completion_command_menu_adapter_test.dart \
        example/test/shell/local_terminal_completion_diagnostics_bundle_test.dart \
        example/test/shell/local_terminal_completion_diagnostics_presentation_test.dart \
        example/test/shell/local_terminal_completion_diagnostics_panel_test.dart \
        example/test/shell/local_terminal_completion_shell_command_menu_diagnostics_test.dart
      ;;
    p1)
      flutter test \
        example/test/shell/shell_action_production_action_set_test.dart \
        example/test/shell/shell_action_production_callbacks_test.dart \
        example/test/shell/shell_action_production_wiring_state_test.dart \
        example/test/shell/shell_action_production_executor_test.dart \
        example/test/shell/shell_action_production_runtime_adapter_test.dart \
        example/test/shell/shell_action_production_wiring_report_test.dart \
        example/test/shell/shell_action_production_audit_snapshot_test.dart \
        example/test/shell/shell_action_production_closure_manifest_test.dart \
        example/test/shell/local_terminal_action_domain_router_test.dart \
        example/test/shell/local_terminal_domain_wiring_summary_test.dart
      ;;
    cross-milestone)
      flutter test \
        example/test/shell/local_terminal_production_wiring_bundle_test.dart \
        example/test/shell/local_terminal_production_wiring_manifest_builder_test.dart
      ;;
    p2-workspace)
      flutter test example/test/workspace
      ;;
    p3-productivity)
      flutter test example/test/productivity
      ;;
    p4-policy)
      flutter test example/test/policies
      ;;
    p5-visual)
      flutter test example/test/visual
      ;;
    verification-evidence)
      flutter test example/test/shell/local_terminal_verification_*test.dart
      ;;
    broader)
      flutter test example/test
      ;;
    integration)
      PROFILE=debug "$ROOT_DIR/tools/build_core.sh" || return $?
      (
        cd "$ROOT_DIR/example" || exit 1
        IANVS_CORE_LIB="$ROOT_DIR/native/core/target/debug/libianvs_core.dylib" \
          flutter test -d macos integration_test/ianvs_smoke_test.dart &&
        IANVS_CORE_LIB="$ROOT_DIR/native/core/target/debug/libianvs_core.dylib" \
          flutter test -d macos integration_test/real_pty_acceptance_test.dart
      )
      ;;
    manual)
      print_batch "$1"
      return 2
      ;;
    *)
      echo "Unknown batch: $1" >&2
      return 2
      ;;
  esac
}

run_all_automated() {
  for batch in \
    formatting \
    static-analysis \
    completion \
    p1 \
    cross-milestone \
    p2-workspace \
    p3-productivity \
    p4-policy \
    p5-visual \
    verification-evidence \
    broader
  do
    echo "==> Running batch: $batch"
    run_batch "$batch" || return $?
  done
}

main() {
  if [ "$#" -lt 1 ]; then
    usage
    return 2
  fi

  case "$1" in
    list)
      list_batches
      ;;
    print)
      if [ "$#" -ne 2 ]; then
        usage
        return 2
      fi
      if [ "$2" = "all-automated" ]; then
        print_all_automated
      else
        print_batch "$2"
      fi
      ;;
    run)
      if [ "$#" -ne 2 ]; then
        usage
        return 2
      fi
      if [ "$2" = "all-automated" ]; then
        run_all_automated
      else
        run_batch "$2"
      fi
      ;;
    *)
      usage
      return 2
      ;;
  esac
}

main "$@"
