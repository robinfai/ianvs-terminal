#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/tools/build_core.sh"

cd "$ROOT_DIR/app"
flutter analyze
flutter test
flutter test integration_test/flutterm_smoke_test.dart
