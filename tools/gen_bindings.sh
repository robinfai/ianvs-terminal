#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
CBINDGEN_VERSION="0.29.2"

cd "$CORE_DIR"
if ! command -v cbindgen >/dev/null 2>&1; then
  cargo install cbindgen --version "$CBINDGEN_VERSION" --locked
fi

cbindgen --crate ianvs_core --output "$CORE_DIR/ianvs_core.h"
echo "Generated C header at $CORE_DIR/ianvs_core.h"
