#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
sparkle=${1:?Sparkle bin directory is required}
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/trail-signature-test.XXXXXX")
trap 'rm -rf -- "$test_dir"' EXIT
public_key=$(xcrun swift "$root/tools/release/update_keys.swift" generate "$test_dir/private.key")
SPARKLE_PUBLIC_KEY="$public_key" xcrun swift "$root/tools/release/update_keys.swift" verify "$test_dir/private.key" > /dev/null
if SPARKLE_PUBLIC_KEY=invalid xcrun swift "$root/tools/release/update_keys.swift" verify "$test_dir/private.key" > "$test_dir/mismatch.log" 2>&1; then
  echo 'Mismatched update keys were accepted' >&2
  exit 1
fi
printf 'signed update fixture\n' > "$test_dir/archive"
signature=$("$sparkle/sign_update" --ed-key-file "$test_dir/private.key" -p "$test_dir/archive")
"$sparkle/sign_update" --ed-key-file "$test_dir/private.key" --verify "$test_dir/archive" "$signature"
printf 'tampered bytes\n' >> "$test_dir/archive"
if "$sparkle/sign_update" --ed-key-file "$test_dir/private.key" --verify "$test_dir/archive" "$signature" > "$test_dir/tamper.log" 2>&1; then
  echo 'Tampered archive was accepted' >&2
  exit 1
fi
echo 'Matching key succeeds; mismatched key and tampered archive are rejected.'
