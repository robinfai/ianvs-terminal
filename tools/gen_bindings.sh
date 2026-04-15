#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"

cd "$CORE_DIR"
if ! command -v cbindgen >/dev/null 2>&1; then
  cargo install cbindgen --locked
fi

cbindgen --crate flutterm_core --output "$CORE_DIR/flutterm_core.h"
echo "Generated C header at $CORE_DIR/flutterm_core.h"
