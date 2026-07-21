#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${HOME:-}" ]]; then
  export PATH="$PATH:$HOME/.pub-cache/bin"
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
proto_file="$repo_root/native/core/proto/frame_diff.proto"
graphic_asset_proto_file="$repo_root/native/core/proto/graphic_asset.proto"
rust_out="$repo_root/native/core/src/proto"
dart_out="$repo_root/packages/ianvs_terminal/lib/src/proto"
graphic_asset_dart_out="$repo_root/packages/ianvs_pty/lib/src/proto"

if ! command -v protoc >/dev/null 2>&1; then
  echo "protoc is required to regenerate frame diff protobuf files." >&2
  exit 1
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo is required to regenerate Rust frame diff protobuf files." >&2
  exit 1
fi

if ! command -v protoc-gen-dart >/dev/null 2>&1; then
  echo "protoc-gen-dart is required. Install it with: dart pub global activate protoc_plugin" >&2
  exit 1
fi

mkdir -p "$rust_out" "$dart_out" "$graphic_asset_dart_out"

(
  cd "$repo_root/native/core"
  cargo build --features regenerate-proto
)

protoc \
  --proto_path="$repo_root/native/core/proto" \
  --dart_out="$dart_out" \
  "$proto_file"

protoc \
  --proto_path="$repo_root/native/core/proto" \
  --dart_out="$graphic_asset_dart_out" \
  "$graphic_asset_proto_file"

# protoc_plugin emits descriptor metadata by default, but the runtime only needs
# the message and enum outputs committed for this local transport schema.
rm -f "$dart_out/frame_diff.pbjson.dart"
rm -f "$graphic_asset_dart_out/graphic_asset.pbjson.dart"
