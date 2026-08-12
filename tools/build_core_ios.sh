#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_MANIFEST="$ROOT_DIR/native/core/Cargo.toml"
DEST_DIR="${TARGET_BUILD_DIR:?}/ianvs_core"
ARCH="${CURRENT_ARCH:-${NATIVE_ARCH_ACTUAL:-}}"
if [[ -z "$ARCH" || "$ARCH" == "undefined_arch" ]]; then
  ARCH="$(uname -m)"
fi

case "${PLATFORM_NAME:-}" in
  iphoneos)
    RUST_TARGET="aarch64-apple-ios"
    ;;
  iphonesimulator)
    case "$ARCH" in
      arm64)
        RUST_TARGET="aarch64-apple-ios-sim"
        ;;
      x86_64)
        RUST_TARGET="x86_64-apple-ios"
        ;;
      *)
        echo "Unsupported iOS Simulator architecture: $ARCH" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unsupported Apple platform: ${PLATFORM_NAME:-unknown}" >&2
    exit 1
    ;;
esac

PROFILE_DIR=debug
CARGO_ARGS=(build --locked --manifest-path "$CORE_MANIFEST" --target "$RUST_TARGET")
if [[ "${CONFIGURATION:-Debug}" != "Debug" ]]; then
  PROFILE_DIR=release
  CARGO_ARGS+=(--release)
fi

if ! rustup target list --installed | grep -Fqx -- "$RUST_TARGET"; then
  echo "Missing Rust target $RUST_TARGET. Install it with: rustup target add $RUST_TARGET" >&2
  exit 1
fi

cargo "${CARGO_ARGS[@]}"
mkdir -p "$DEST_DIR"
cp \
  "$ROOT_DIR/native/core/target/$RUST_TARGET/$PROFILE_DIR/libianvs_core.a" \
  "$DEST_DIR/libianvs_core.a"
