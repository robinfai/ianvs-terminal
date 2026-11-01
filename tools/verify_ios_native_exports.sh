#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:?Usage: verify_ios_native_exports.sh path/to/Runner.app [architecture]}"
arch="${2:-arm64}"
name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")"
image="$app/$name"
if [[ -f "$app/$name.debug.dylib" ]]; then
  image="$app/$name.debug.dylib"
fi
# Dart resolves these names through dlsym. The dynamic export trie, rather than
# a debug symbol table, is the contract that must survive archive/IPA stripping.
actual="$(xcrun dyld_info -arch "$arch" -exports "$image" | awk '$NF ~ /^_ianvs_/ {print $NF}' | LC_ALL=C sort -u)"
expected="$(LC_ALL=C sort -u "$ROOT_DIR/native/core/ianvs_core_ios_exports.txt")"
if [[ "$actual" != "$expected" ]]; then
  echo 'The iOS application is missing its dynamically exported Ianvs C ABI.' >&2
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
  exit 1
fi
printf 'Verified iOS runtime exports: %s (%s)\n' "$app" "$arch"
