#!/usr/bin/env bash
# Expects an unlocked CI keychain containing the Developer ID identity.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
: "${MACOS_SIGNING_IDENTITY:?Developer ID Application identity is required}"
: "${SPARKLE_PUBLIC_KEY:?Sparkle public key is required}"
: "${SPARKLE_KEY_FILE:?Sparkle private key file is required}"
if [[ -n "${NOTARY_KEY_FILE:-}" ]]; then
  : "${NOTARY_KEY_ID:?Notarization key ID is required}"
  : "${NOTARY_ISSUER_ID:?Notarization issuer ID is required}"
  notary_auth=(--key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  : "${APPLE_ID:?Apple account email is required}"
  : "${APPLE_TEAM_ID:?Apple developer team ID is required}"
  : "${APPLE_APP_SPECIFIC_PASSWORD:?Apple app-specific password is required}"
  notary_auth=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
fi
: "${MACOS_PROFILE_FILE:?Developer ID provisioning profile is required}"
: "${RELEASE_VERSION:?Release version is required}"
: "${RELEASE_BUILD:?Monotonic build number is required}"
: "${RELEASE_REPOSITORY:?Release repository is required}"
: "${RELEASE_OUTPUT:?Output directory is required}"
: "${SPARKLE_TOOLS:?Sparkle tools directory is required}"
# Check credentials before the expensive universal build. Do not log history.
xcrun notarytool history "${notary_auth[@]}" --output-format json > /dev/null
xcrun swift "$root/tools/release/update_keys.swift" verify "$SPARKLE_KEY_FILE" > /dev/null
mkdir -p "$RELEASE_OUTPUT"
security cms -D -i "$MACOS_PROFILE_FILE" > "$RELEASE_OUTPUT/profile.plist"
python3 "$root/tools/release/prepare_distribution_profile.py" "$RELEASE_OUTPUT/profile.plist" \
  "$RELEASE_OUTPUT/distribution.entitlements" --identity "$MACOS_SIGNING_IDENTITY"
(
  cd "$root/example"
  flutter build macos --release --build-name="$RELEASE_VERSION" --build-number="$RELEASE_BUILD"
)
app="$root/example/build/macos/Build/Products/Release/Trail.app"
[[ -d "$app/Contents/Frameworks/Sparkle.framework" ]] || {
  echo 'The built app is missing Sparkle.framework' >&2
  exit 1
}
feed="https://github.com/$RELEASE_REPOSITORY/releases/latest/download/appcast.xml"
if [[ "${RELEASE_PRERELEASE:-false}" == true ]]; then
  feed="https://github.com/$RELEASE_REPOSITORY/releases/download/v0.1.0/appcast.xml"
fi
python3 "$root/tools/release/macos_release.py" configure "$app" --public-key "$SPARKLE_PUBLIC_KEY" \
  --feed "$feed"
cp "$MACOS_PROFILE_FILE" "$app/Contents/embedded.provisionprofile"
python3 "$root/tools/release/macos_release.py" sign "$app" --identity "$MACOS_SIGNING_IDENTITY" \
  --entitlements "$RELEASE_OUTPUT/distribution.entitlements"
python3 "$root/tools/verify_macos_native_library.py" \
  "$app/Contents/Frameworks/ianvs_core.framework/ianvs_core"
# Every embedded executable must support both advertised architectures.
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    for architecture in arm64 x86_64; do
      lipo "$binary" -verify_arch "$architecture"
    done
  fi
done < <(find "$app" -type f -print0)
archive="$RELEASE_OUTPUT/Trail-$RELEASE_VERSION-macOS-universal.zip"
ditto -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" "${notary_auth[@]}" --wait --timeout 45m --output-format json > "$RELEASE_OUTPUT/notarization.json"
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
# First-install disk image uses the same signed, stapled app as the update ZIP.
dmg="$RELEASE_OUTPUT/Trail-$RELEASE_VERSION-macOS-universal.dmg"
dmg_stage=$(mktemp -d)
trap 'rm -rf "$dmg_stage"' EXIT
ditto "$app" "$dmg_stage/Trail.app"
ln -s /Applications "$dmg_stage/Applications"
hdiutil create -volname "Trail $RELEASE_VERSION" -srcfolder "$dmg_stage" \
  -format UDZO -ov "$dmg"
codesign --force --sign "$MACOS_SIGNING_IDENTITY" --timestamp "$dmg"
codesign --verify --strict --verbose=2 "$dmg"
xcrun notarytool submit "$dmg" "${notary_auth[@]}" --wait --timeout 45m --output-format json > "$RELEASE_OUTPUT/notarization-dmg.json"
python3 - "$RELEASE_OUTPUT/notarization-dmg.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple DMG notarization was not accepted: ' + str(result.get('status')))
PY
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
hdiutil verify "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
(cd "$RELEASE_OUTPUT" && shasum -a 256 "$(basename "$archive")" "$(basename "$dmg")" appcast.xml > SHA256SUMS)
