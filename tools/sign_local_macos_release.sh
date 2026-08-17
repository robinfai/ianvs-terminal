#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/example/build/macos/Build/Products/Release/Ianvs Terminal.app}"
EXPECTED_IDENTIFIER="${IANVS_APP_BUNDLE_ID:-dev.ianvs.terminal}"
LOCAL_ENTITLEMENTS="$ROOT_DIR/example/macos/Runner/LocalRelease.entitlements"
ENTITLEMENT_VALIDATOR="$ROOT_DIR/tools/validate_local_release_entitlements.py"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "local macOS release signing requires macOS" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "local macOS release app not found: $APP_PATH" >&2
  exit 1
fi

python3 "$ENTITLEMENT_VALIDATOR" "$LOCAL_ENTITLEMENTS"

signature_details="$(codesign -d --verbose=4 "$APP_PATH" 2>&1)"
was_adhoc=0
if [[ "$signature_details" == *"Signature=adhoc"* ]]; then
  was_adhoc=1
  codesign \
    --force \
    --deep \
    --sign - \
    --options runtime \
    --entitlements "$LOCAL_ENTITLEMENTS" \
    "$APP_PATH"
elif [[ "$signature_details" != *"Authority=Apple Development:"* ]]; then
  echo "local macOS release app must use an Apple Development identity" >&2
  exit 1
elif [[ "$signature_details" != *"TeamIdentifier="* ]] ||
     [[ "$signature_details" == *"TeamIdentifier=not set"* ]]; then
  echo "the selected Apple Development signature has no TeamIdentifier" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
final_details="$(codesign -d --verbose=4 "$APP_PATH" 2>&1)"
if [[ "$final_details" != *"Identifier=$EXPECTED_IDENTIFIER"* ]]; then
  echo "unexpected macOS bundle identifier; expected $EXPECTED_IDENTIFIER" >&2
  exit 1
fi
if [[ "$final_details" != *"flags=0x"*"runtime)"* ]]; then
  echo "local macOS release app is missing the hardened runtime flag" >&2
  exit 1
fi

if (( was_adhoc == 1 )); then
  if [[ "$final_details" != *"(adhoc,runtime)"* ]]; then
    echo "local macOS release app did not retain ad-hoc runtime signing" >&2
    exit 1
  fi
  codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null | \
    python3 "$ENTITLEMENT_VALIDATOR" -
fi

echo "Local macOS release signing verified: $APP_PATH"
