#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ianvs-native-abi.XXXXXX")"

cleanup() {
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

case "$(uname -s)" in
  Darwin)
    LIBRARY_NAME=libianvs_core.dylib
    ;;
  Linux)
    LIBRARY_NAME=libianvs_core.so
    ;;
  *)
    echo "Unsupported native ABI verification host: $(uname -s)" >&2
    exit 1
    ;;
esac

verify_clean_artifact() {
  source_root="$1"
  dart_library="$2"
  target_dir="$3"

  CARGO_TARGET_DIR="$target_dir" cargo build \
    --locked \
    --manifest-path "$source_root/Cargo.toml"
  library="$target_dir/debug/$LIBRARY_NAME"
  "$ROOT_DIR/tools/verify_native_contract.py" \
    --header "$source_root/ianvs_core.h" \
    --manifest "$source_root/ianvs_core_abi_v1.json" \
    --dart-library "$dart_library" \
    --library "$library"
}

verify_clean_artifact \
  "$ROOT_DIR/native/core" \
  "$ROOT_DIR/packages/ianvs_pty/lib" \
  "$TEMP_DIR/root-target"

verify_clean_artifact \
  "$ROOT_DIR/packages/ianvs_terminal_core/native/core" \
  "$ROOT_DIR/packages/ianvs_terminal_core/lib/src/pty" \
  "$TEMP_DIR/standalone-target"
