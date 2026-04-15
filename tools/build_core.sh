#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
PROFILE="${PROFILE:-debug}"

cd "$CORE_DIR"
if [ "$PROFILE" = "release" ]; then
  cargo build --release
  echo "Built Rust core at $CORE_DIR/target/release/libflutterm_core.dylib"
else
  cargo build
  echo "Built Rust core at $CORE_DIR/target/debug/libflutterm_core.dylib"
fi
