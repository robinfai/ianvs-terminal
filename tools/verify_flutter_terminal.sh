#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
PTY_DIR="$ROOT_DIR/packages/flutterm_pty"
TERMINAL_DIR="$ROOT_DIR/packages/flutterm_terminal"
EXAMPLE_DIR="$ROOT_DIR/example"

"$ROOT_DIR/tools/build_core.sh"

(
  cd "$CORE_DIR"
  cargo fmt --check
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
  rg -v "features/preferences/app_preferences_repository.dart|features/sessions/session_controller.dart"; then
  echo "Found AppPreferencesRepository usage outside the approved Phase 3 write path" >&2
  exit 1
fi

(
  cd "$EXAMPLE_DIR"
  flutter analyze
  flutter test
  flutter test integration_test/flutterm_smoke_test.dart
)
