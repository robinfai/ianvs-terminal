#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/example"
PRODUCTION_IDENTIFIER="dev.ianvs.terminal"
PLATFORM="${1:-}"
FLUTTER_COMMAND="${2:-flutter}"
shift $(( $# >= 2 ? 2 : $# ))

case "$PLATFORM" in
  ios | macos) ;;
  *)
    echo "usage: build_signed_apple_release.sh <ios|macos> [flutter-command]" >&2
    exit 64
    ;;
esac

cd "$EXAMPLE_DIR"
if [[ "$PLATFORM" == "macos" ]]; then
  MACOS_BUNDLE_ID="${IANVS_MACOS_BUNDLE_ID:-}"
  if [[ -z "$MACOS_BUNDLE_ID" ]]; then
    "$FLUTTER_COMMAND" build macos --release "$@"
    "$ROOT_DIR/tools/sign_local_macos_release.sh" \
      "$EXAMPLE_DIR/build/macos/Build/Products/Release/Ianvs Terminal.app"
    exit 0
  fi
  if [[ ! "$MACOS_BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]]; then
    echo "Invalid macOS Bundle ID: $MACOS_BUNDLE_ID" >&2
    exit 64
  fi

  TEAM="$("$ROOT_DIR/tools/detect_apple_development_team.sh")"
  SIGNING_TEMP_BASE="${TMPDIR:-/tmp}"
  SIGNING_ROOT="$(
    mktemp -d "${SIGNING_TEMP_BASE%/}/ianvs-macos-signing.XXXXXX"
  )"
  SIGNING_CONFIG="$SIGNING_ROOT/DevelopmentSigning.xcconfig"
  SIGNING_ENTITLEMENTS="$SIGNING_ROOT/DevelopmentRelease.entitlements"
  cleanup_macos_signing() {
    rm -rf -- "$SIGNING_ROOT"
  }
  trap cleanup_macos_signing EXIT

  plutil -create xml1 "$SIGNING_ENTITLEMENTS"
  /usr/libexec/PlistBuddy \
    -c 'Add :keychain-access-groups array' \
    -c "Add :keychain-access-groups:0 string \$(AppIdentifierPrefix)$PRODUCTION_IDENTIFIER" \
    "$SIGNING_ENTITLEMENTS"
  printf '%s\n' \
    'CODE_SIGN_IDENTITY = Apple Development' \
    'CODE_SIGN_STYLE = Automatic' \
    "DEVELOPMENT_TEAM = $TEAM" \
    "PRODUCT_BUNDLE_IDENTIFIER = $MACOS_BUNDLE_ID" \
    "CODE_SIGN_ENTITLEMENTS = $SIGNING_ENTITLEMENTS" \
    >"$SIGNING_CONFIG"

  "$FLUTTER_COMMAND" build macos --release --config-only "$@"
  apple_build_env=(
    /usr/bin/env -i
    "HOME=$HOME"
    "PATH=$PATH"
    "TMPDIR=${TMPDIR:-/tmp}"
    "LANG=${LANG:-en_US.UTF-8}"
    "LC_ALL=${LC_ALL:-en_US.UTF-8}"
    "XCODE_XCCONFIG_FILE=$SIGNING_CONFIG"
  )
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    apple_build_env+=("DEVELOPER_DIR=$DEVELOPER_DIR")
  fi
  if [[ -n "${TOOLCHAINS:-}" ]]; then
    apple_build_env+=("TOOLCHAINS=$TOOLCHAINS")
  fi
  if [[ -n "${RUSTUP_TOOLCHAIN:-}" ]]; then
    apple_build_env+=("RUSTUP_TOOLCHAIN=$RUSTUP_TOOLCHAIN")
  fi
  if [[ -n "${PUB_CACHE:-}" ]]; then
    apple_build_env+=("PUB_CACHE=$PUB_CACHE")
  fi

  (
    cd "$EXAMPLE_DIR/macos"
    "${apple_build_env[@]}" xcodebuild \
      -workspace Runner.xcworkspace \
      -scheme Runner \
      -configuration Release \
      -derivedDataPath ../build/macos \
      -allowProvisioningUpdates \
      -quiet \
      build
  )

  MACOS_APP="$EXAMPLE_DIR/build/macos/Build/Products/Release/Ianvs Terminal.app"
  [[ -f "$MACOS_APP/Contents/embedded.provisionprofile" ]] || {
    echo "macOS development build is missing its provisioning profile" >&2
    exit 1
  }
  ACTUAL_IDENTIFIER="$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
      "$MACOS_APP/Contents/Info.plist"
  )"
  [[ "$ACTUAL_IDENTIFIER" == "$MACOS_BUNDLE_ID" ]] || {
    echo "unexpected macOS Bundle ID: $ACTUAL_IDENTIFIER" >&2
    exit 1
  }
  codesign --verify --deep --strict --verbose=2 "$MACOS_APP"
  ACTUAL_ENTITLEMENTS="$(codesign -d --entitlements - "$MACOS_APP" 2>&1)"
  [[ "$ACTUAL_ENTITLEMENTS" == *"[String] $TEAM.$MACOS_BUNDLE_ID"* ]] || {
    echo "macOS signature is missing the expected application identifier" >&2
    exit 1
  }
  [[ "$ACTUAL_ENTITLEMENTS" == *"[String] $TEAM.$PRODUCTION_IDENTIFIER"* ]] || {
    echo "macOS signature is missing the expected Keychain group" >&2
    exit 1
  }
  echo "Built profile-signed macOS development app: $MACOS_BUNDLE_ID"
  exit 0
fi

TEAM="$("$ROOT_DIR/tools/detect_apple_development_team.sh")"
IOS_BUNDLE_ID="${IANVS_IOS_BUNDLE_ID:-}"
if [[ -n "$IOS_BUNDLE_ID" &&
      ! "$IOS_BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]]; then
  echo "Invalid iOS Bundle ID: $IOS_BUNDLE_ID" >&2
  exit 64
fi
SIGNING_CONFIG="$(mktemp "${TMPDIR:-/tmp}/ianvs-apple-signing.XXXXXX")"
cleanup() {
  rm -f -- "$SIGNING_CONFIG"
}
trap cleanup EXIT

SIGNING_SETTINGS=(
  'CODE_SIGN_IDENTITY = Apple Development'
  'CODE_SIGN_STYLE = Automatic'
  "DEVELOPMENT_TEAM = $TEAM"
)
if [[ -n "$IOS_BUNDLE_ID" ]]; then
  SIGNING_SETTINGS+=("PRODUCT_BUNDLE_IDENTIFIER = $IOS_BUNDLE_ID")
fi
printf '%s\n' "${SIGNING_SETTINGS[@]}" >"$SIGNING_CONFIG"

echo "Using the Apple Development identity selected from Keychain."
if [[ -n "$IOS_BUNDLE_ID" ]]; then
  echo "Temporarily overriding the iOS Bundle ID with $IOS_BUNDLE_ID."
fi
XCODE_XCCONFIG_FILE="$SIGNING_CONFIG" \
  "$FLUTTER_COMMAND" build ios --release "$@"
