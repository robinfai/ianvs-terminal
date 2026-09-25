#!/usr/bin/env bash
# Expects an unlocked CI keychain containing the Developer ID identity.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
: "${MACOS_SIGNING_IDENTITY:?Developer ID Application identity is required}"
: "${SPARKLE_PUBLIC_KEY:?Sparkle public key is required}"
: "${SPARKLE_KEY_FILE:?Sparkle private key file is required}"
: "${NOTARY_KEY_FILE:?Apple notarization API key file is required}"
: "${NOTARY_KEY_ID:?Notarization key ID is required}"
: "${NOTARY_ISSUER_ID:?Notarization issuer ID is required}"
: "${RELEASE_VERSION:?Release version is required}"
: "${RELEASE_BUILD:?Monotonic build number is required}"
: "${RELEASE_REPOSITORY:?Release repository is required}"
: "${RELEASE_OUTPUT:?Output directory is required}"
: "${SPARKLE_TOOLS:?Sparkle tools directory is required}"
xcrun swift "$root/tools/release/update_keys.swift" verify "$SPARKLE_KEY_FILE" > /dev/null
mkdir -p "$RELEASE_OUTPUT"
(
  cd "$root/example"
  flutter build macos --release --build-name="$RELEASE_VERSION" --build-number="$RELEASE_BUILD"
)
app="$root/example/build/macos/Build/Products/Release/Trail.app"
[[ -d "$app/Contents/Frameworks/Sparkle.framework" ]] || {
  echo 'The built app is missing Sparkle.framework' >&2
  exit 1
}
python3 "$root/tools/release/macos_release.py" configure "$app" --public-key "$SPARKLE_PUBLIC_KEY" \
  --feed "https://github.com/$RELEASE_REPOSITORY/releases/latest/download/appcast.xml"
python3 "$root/tools/release/macos_release.py" sign "$app" --identity "$MACOS_SIGNING_IDENTITY" \
  --entitlements "$root/example/macos/Runner/Release.entitlements"
python3 "$root/tools/verify_macos_native_library.py" \
  "$app/Contents/Frameworks/ianvs_core.framework/ianvs_core"
# Every embedded executable must support both advertised architectures.
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    lipo -verify_arch arm64 x86_64 "$binary"
  fi
done < <(find "$app" -type f -print0)
archive="$RELEASE_OUTPUT/Trail-$RELEASE_VERSION-macOS-universal.zip"
ditto -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" --key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" --wait --output-format json > "$RELEASE_OUTPUT/notarization.json"
python3 - "$RELEASE_OUTPUT/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple notarization was not accepted: ' + str(result.get('status')))
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
# Repackage after stapling, then sign the exact bytes users will download.
ditto -c -k --keepParent "$app" "$archive"
signature=$("$SPARKLE_TOOLS/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" -p "$archive")
"$SPARKLE_TOOLS/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" --verify "$archive" "$signature"
python3 "$root/tools/release/macos_release.py" appcast "$app" "$archive" "$RELEASE_OUTPUT/appcast.xml" \
  --url "https://github.com/$RELEASE_REPOSITORY/releases/download/v$RELEASE_VERSION/$(basename "$archive")" \
  --signature "$signature"
"$SPARKLE_TOOLS/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" "$RELEASE_OUTPUT/appcast.xml"
"$SPARKLE_TOOLS/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" --verify "$RELEASE_OUTPUT/appcast.xml"
(cd "$RELEASE_OUTPUT" && shasum -a 256 "$(basename "$archive")" appcast.xml > SHA256SUMS)
