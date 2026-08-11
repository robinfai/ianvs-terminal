#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
OUTPUT="${1:-$CORE_DIR/ianvs_core.h}"

cargo run \
  --locked \
  --quiet \
  --manifest-path "$CORE_DIR/Cargo.toml" \
  --example generate_c_header \
  -- "$OUTPUT"
echo "Generated C header at $OUTPUT"
