#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_MANIFEST="$ROOT_DIR/native/core/Cargo.toml"
DEST_DIR="${DERIVED_FILE_DIR:?}/ianvs_core"
requested_archs="${CURRENT_ARCH:-${NATIVE_ARCH_ACTUAL:-}}"
if [[ -z "$requested_archs" || "$requested_archs" == "undefined_arch" ]]; then
  requested_archs="${ARCHS:-$(uname -m)}"
fi

targets=()
for arch in $requested_archs; do
  case "${PLATFORM_NAME:-}:$arch" in
    iphoneos:arm64 | iphoneos:aarch64)
      RUST_TARGET="aarch64-apple-ios"
      ;;
    iphonesimulator:arm64 | iphonesimulator:aarch64)
      RUST_TARGET="aarch64-apple-ios-sim"
      ;;
    iphonesimulator:x86_64)
      RUST_TARGET="x86_64-apple-ios"
      ;;
    iphoneos:*)
      echo "Unsupported iOS device architecture: $arch" >&2
      exit 1
      ;;
    iphonesimulator:*)
      echo "Unsupported iOS Simulator architecture: $arch" >&2
      exit 1
      ;;
    *)
      echo "Unsupported Apple platform: ${PLATFORM_NAME:-unknown}" >&2
      exit 1
      ;;
  esac
  targets+=("$RUST_TARGET")
done

if [[ "${#targets[@]}" -eq 0 ]]; then
  echo "No iOS Rust core architectures were requested." >&2
  exit 1
fi

# Xcode exports the iOS SDKROOT to every build phase. Cargo also compiles host
# build scripts for aarch64-apple-darwin; letting those host links inherit the
# simulator/device SDK makes clang unable to resolve macOS libSystem. Give host
# tools the macOS SDK and pin the actual Rust target back to Xcode's iOS SDK
# through target-specific rustflags.
IOS_SDKROOT="${SDKROOT:-$(xcrun --sdk "$PLATFORM_NAME" --show-sdk-path)}"
MACOS_SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT="$MACOS_SDKROOT"

PROFILE_DIR=debug
if [[ "${CONFIGURATION:-Debug}" != "Debug" ]]; then
  PROFILE_DIR=release
fi

for RUST_TARGET in "${targets[@]}"; do
  RUSTFLAGS_ENV_NAME="CARGO_TARGET_$(
    tr '[:lower:]-' '[:upper:]_' <<<"$RUST_TARGET"
  )_RUSTFLAGS"
  TARGET_RUSTFLAGS="${!RUSTFLAGS_ENV_NAME:-}"
  TARGET_RUSTFLAGS="${TARGET_RUSTFLAGS:+$TARGET_RUSTFLAGS }-C link-arg=-isysroot -C link-arg=$IOS_SDKROOT"
  export "$RUSTFLAGS_ENV_NAME=$TARGET_RUSTFLAGS"

  if ! rustup target list --installed | grep -Fqx -- "$RUST_TARGET"; then
    echo "Missing Rust target $RUST_TARGET. Install it with: rustup target add $RUST_TARGET" >&2
    exit 1
  fi

  CARGO_ARGS=(build --locked --manifest-path "$CORE_MANIFEST" --target "$RUST_TARGET")
  if [[ "$PROFILE_DIR" == "release" ]]; then
    CARGO_ARGS+=(--release)
  fi
  cargo "${CARGO_ARGS[@]}"
done

mkdir -p "$DEST_DIR"
if [[ "${#targets[@]}" -eq 1 ]]; then
  cp \
    "$ROOT_DIR/native/core/target/${targets[0]}/$PROFILE_DIR/libianvs_core.a" \
    "$DEST_DIR/libianvs_core.a"
else
  slices=()
  for RUST_TARGET in "${targets[@]}"; do
    slices+=(
      "$ROOT_DIR/native/core/target/$RUST_TARGET/$PROFILE_DIR/libianvs_core.a"
    )
  done
  xcrun lipo -create "${slices[@]}" -output "$DEST_DIR/libianvs_core.a"
fi
