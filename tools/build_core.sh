#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
PROFILE="${PROFILE:-debug}"

cd "$CORE_DIR"

if [ "$PROFILE" != "release" ] && [ "$PROFILE" != "debug" ]; then
  echo "Unsupported Rust core profile: $PROFILE" >&2
  exit 1
fi

# macOS still ships Bash 3.2, where expanding an empty array under `set -u`
# raises an unbound-variable error. Keep the optional profile flag out of an
# array so Debug integration-test builds remain portable.
cargo_build() {
  if [ "$PROFILE" = "release" ]; then
    cargo build --locked --release "$@"
  else
    cargo build --locked "$@"
  fi
}

if [ "$(uname -s)" != "Darwin" ]; then
  cargo_build
  echo "Built Rust core at $CORE_DIR/target/$PROFILE"
  exit 0
fi

# Xcode can produce a universal app even when Cargo's host build contains only
# one architecture. Build every architecture requested by Xcode and merge the
# slices so the bundled dylib can be loaded by every app executable slice.
requested_archs="${IANVS_CORE_ARCHS:-${ARCHS:-$(uname -m)}}"
targets=()
for arch in $requested_archs; do
  case "$arch" in
    arm64 | aarch64)
      target="aarch64-apple-darwin"
      ;;
    x86_64)
      target="x86_64-apple-darwin"
      ;;
    *)
      echo "Unsupported macOS Rust core architecture: $arch" >&2
      exit 1
      ;;
  esac
  targets+=("$target")
done

if [ "${#targets[@]}" -eq 0 ]; then
  echo "No macOS Rust core architectures were requested." >&2
  exit 1
fi

for target in "${targets[@]}"; do
  if ! rustup target list --installed | grep -Fqx -- "$target"; then
    echo "Missing Rust target $target. Install it with: rustup target add $target" >&2
    exit 1
  fi
  cargo_build --target "$target"
done

output="$CORE_DIR/target/$PROFILE/libianvs_core.dylib"
mkdir -p "$(dirname "$output")"
if [ "${#targets[@]}" -eq 1 ]; then
  cp "$CORE_DIR/target/${targets[0]}/$PROFILE/libianvs_core.dylib" "$output"
else
  slices=()
  for target in "${targets[@]}"; do
    slices+=("$CORE_DIR/target/$target/$PROFILE/libianvs_core.dylib")
  done
  xcrun lipo -create "${slices[@]}" -output "$output"
fi

echo "Built Rust core at $output ($(lipo -archs "$output"))"
