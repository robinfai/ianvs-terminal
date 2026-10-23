#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ianvs-generated-contracts.XXXXXX")"

cleanup() {
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

if [ "${IANVS_CI_NATIVE_METRICS:-0}" = "1" ]; then
  python3 "$ROOT_DIR/tools/ci/time_command.py" 'C header generation' -- \
    "$ROOT_DIR/tools/gen_bindings.sh" "$TEMP_DIR/ianvs_core.h"
else
  "$ROOT_DIR/tools/gen_bindings.sh" "$TEMP_DIR/ianvs_core.h"
fi
diff -u "$CORE_DIR/ianvs_core.h" "$TEMP_DIR/ianvs_core.h"
"$ROOT_DIR/tools/verify_native_contract.py"
"$ROOT_DIR/tools/verify_native_binary_contract.sh"

# Hermetic semantic verification covers the checked-in descriptor plus Rust
# and Dart generated files without relying on a mutable system protoc install.
# tools/gen_frame_diff_proto.sh remains the explicit regeneration entrypoint.
"$ROOT_DIR/tools/verify_proto_contract.py"
