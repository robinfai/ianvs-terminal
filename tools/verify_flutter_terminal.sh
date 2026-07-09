#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
PTY_DIR="$ROOT_DIR/packages/ianvs_pty"
TERMINAL_DIR="$ROOT_DIR/packages/ianvs_terminal"
EXAMPLE_DIR="$ROOT_DIR/example"
VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION="${VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION:-0}"
VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS="${VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS:-0}"
VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH="${VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH:-0}"

"$ROOT_DIR/tools/build_core.sh"

(
  cd "$CORE_DIR"
  cargo fmt --check
  cargo clippy --all-targets -- -D warnings
  # Set IANVS_REQUIRE_POSIX_SHM_TESTS=1 on hosts where Kitty POSIX shared memory
  # support must be verified instead of skipped when the OS blocks shm_open.
  cargo test -- --test-threads=1
)

(
  cd "$PTY_DIR"
  dart analyze --fatal-infos
  dart test
)

(
  cd "$TERMINAL_DIR"
  flutter analyze --fatal-infos
  flutter test
)

(
  cd "$ROOT_DIR"
  dart test test/docs_contract_test.dart
)

(
  cd "$ROOT_DIR"
  dart run tools/bench/runner/bench_runner.dart --config tools/bench/configs/bench_ci_smoke.yaml
  if [ "$VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH" = "1" ]; then
    dart run tools/bench/runner/bench_runner.dart --config tools/bench/configs/bench_nightly_resource.yaml
  else
    echo "Skipping nightly resource benchmark because VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH!=1"
  fi
)

if rg -n "Set as default" "$ROOT_DIR/example/lib"; then
  echo "Found forbidden inline default mutation text in example/lib" >&2
  exit 1
fi

rg -n "Defaults & appearance" "$ROOT_DIR/example/lib/features/shell" >/dev/null

if rg -n "AppPreferencesRepository" "$ROOT_DIR/example/lib" | \
  rg -v "features/preferences/app_preferences_repository.dart|features/sessions/session_controller.dart|features/config/local_terminal_config_loader.dart"; then
  echo "Found AppPreferencesRepository usage outside the approved Phase 3 write/bootstrap paths" >&2
  exit 1
fi

(
  cd "$EXAMPLE_DIR"
  EXAMPLE_CI_TEST_TARGETS=(
    test/app
    test/config
    test/platform
    test/policies
    test/preferences
    test/productivity
    test/profiles
    test/sessions
    test/shell
    test/terminal
    test/terminal_input_controller_test.dart
    test/ui
    test/visual
    test/workspace
  )
  flutter analyze --fatal-infos
  flutter test "${EXAMPLE_CI_TEST_TARGETS[@]}"
  if [ "$VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS" = "1" ]; then
    flutter test test/widget_test.dart
  else
    echo "Skipping example/test/widget_test.dart because VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS!=1"
  fi
)

if [ "$VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION" = "1" ]; then
  echo "Skipping macOS integration tests because VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION=1"
  exit 0
fi

(
  cd "$EXAMPLE_DIR"
  IANVS_CORE_LIB="$CORE_DIR/target/debug/libianvs_core.dylib" \
    flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart
  IANVS_CORE_LIB="$CORE_DIR/target/debug/libianvs_core.dylib" \
    flutter test -d macos integration_test/real_pty_acceptance_test.dart
)
