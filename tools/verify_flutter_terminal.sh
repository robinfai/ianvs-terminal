#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
PTY_DIR="$ROOT_DIR/packages/ianvs_pty"
TERMINAL_DIR="$ROOT_DIR/packages/ianvs_terminal"
EXAMPLE_DIR="$ROOT_DIR/example"

"$ROOT_DIR/tools/build_core.sh"

(
  cd "$CORE_DIR"
  cargo fmt --check
  cargo clippy --all-targets -- -D warnings
  cargo test -- --test-threads=1
)

(
  cd "$PTY_DIR"
  dart test
)

(
  cd "$TERMINAL_DIR"
  flutter test
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
  flutter analyze
  flutter test
  IANVS_CORE_LIB="$CORE_DIR/target/debug/libianvs_core.dylib" \
    flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart
  IANVS_CORE_LIB="$CORE_DIR/target/debug/libianvs_core.dylib" \
    flutter test -d macos integration_test/real_pty_acceptance_test.dart
)
