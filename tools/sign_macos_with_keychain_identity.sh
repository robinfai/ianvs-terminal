#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/example/build/macos/Build/Products/Release/Ianvs Terminal.app}"
EXPECTED_IDENTIFIER="${IANVS_APP_BUNDLE_ID:-dev.ianvs.terminal}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Apple Development signing requires macOS" >&2
  exit 1
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "macOS app not found: $APP_PATH" >&2
  exit 1
fi

identity_line="$(
  security find-identity -v -p codesigning 2>&1 |
    sed -nE '/"Apple Development:/p' |
    head -n 1
)"
identity_hash="$(printf '%s\n' "$identity_line" | sed -nE 's/^[[:space:]]*[0-9]+\)[[:space:]]+([A-F0-9]{40}).*/\1/p')"
team="$("$ROOT_DIR/tools/detect_apple_development_team.sh")"
if [[ -z "$identity_hash" || -z "$team" ]]; then
  echo "No valid Apple Development signing identity was found in the login Keychain." >&2
  exit 1
fi

bundle_identifier="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$APP_PATH/Contents/Info.plist"
)"
if [[ "$bundle_identifier" != "$EXPECTED_IDENTIFIER" ]]; then
  echo "unexpected macOS bundle identifier; expected $EXPECTED_IDENTIFIER" >&2
  exit 1
fi

entitlements="$(mktemp "${TMPDIR:-/tmp}/ianvs-macos-entitlements.XXXXXX")"
cleanup() {
  rm -f -- "$entitlements"
}
trap cleanup EXIT

plutil -create xml1 "$entitlements"
/usr/libexec/PlistBuddy \
  -c "Add :com.apple.application-identifier string $team.$EXPECTED_IDENTIFIER" \
  -c "Add :com.apple.developer.team-identifier string $team" \
  -c 'Add :keychain-access-groups array' \
  -c "Add :keychain-access-groups:0 string $team.$EXPECTED_IDENTIFIER" \
  "$entitlements"

codesign \
  --force \
  --deep \
  --sign "$identity_hash" \
  --options runtime \
  --timestamp=none \
  --entitlements "$entitlements" \
  "$APP_PATH"

"$ROOT_DIR/tools/sign_local_macos_release.sh" "$APP_PATH"
