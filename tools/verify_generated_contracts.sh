#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ianvs-generated-contracts.XXXXXX")"

cleanup() {
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/tools/gen_bindings.sh" "$TEMP_DIR/ianvs_core.h"
diff -u "$CORE_DIR/ianvs_core.h" "$TEMP_DIR/ianvs_core.h"
"$ROOT_DIR/tools/verify_native_contract.py"

# Hermetic semantic verification covers the checked-in descriptor plus Rust
# and Dart generated files without relying on a mutable system protoc install.
# tools/gen_frame_diff_proto.sh remains the explicit regeneration entrypoint.
"$ROOT_DIR/tools/verify_proto_contract.py"
