#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/example"
IOS_SIMULATOR_UDID="${IANVS_IOS_SIMULATOR_UDID:-}"
SIMULATOR_STARTED=0

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The iOS simulator gate requires macOS." >&2
  exit 1
fi

select_simulator_line() {
  local state="$1"
  xcrun simctl list devices available | awk -v requested_state="$state" '
    /^-- iOS / { in_ios = 1; next }
    /^-- / { in_ios = 0 }
    in_ios && /iPhone/ && index($0, "(" requested_state ")") { print; exit }
  '
}

if [[ -z "$IOS_SIMULATOR_UDID" ]]; then
  simulator_line="$(select_simulator_line Booted)"
  if [[ -z "$simulator_line" ]]; then
    simulator_line="$(select_simulator_line Shutdown)"
  fi
  IOS_SIMULATOR_UDID="$(
    sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/' <<<"$simulator_line"
  )"
fi

if [[ ! "$IOS_SIMULATOR_UDID" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  echo "No available iPhone simulator was found." >&2
  exit 1
fi

cleanup() {
  if [[ "$SIMULATOR_STARTED" == "1" ]]; then
    xcrun simctl shutdown "$IOS_SIMULATOR_UDID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# The Runner scheme's pre-actions print their inherited environment. Keep
# credentials, publishing tokens, and unrelated repository state out of logs.
apple_build_env=(
  /usr/bin/env -i
  "HOME=$HOME"
  "PATH=$PATH"
  "TMPDIR=${TMPDIR:-/tmp}"
  "LANG=${LANG:-en_US.UTF-8}"
  "LC_ALL=${LC_ALL:-en_US.UTF-8}"
)
simulator_arch="$(uname -m)"
IOS_EXPORTS_FILE="$ROOT_DIR/native/core/ianvs_core_ios_exports.txt"
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

verify_ios_native_exports() {
  local ios_app="$1"
  local architecture="$2"
  local executable_name
  local executable
  local actual_symbols
  local expected_symbols
  local link_images

  executable_name="$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$ios_app/Info.plist"
  )"
  executable="$ios_app/$executable_name"
  link_images=("$executable")
  if [[ -f "$ios_app/$executable_name.debug.dylib" ]]; then
    # Flutter debug builds put app-native objects in this loaded image rather
    # than the small process launcher executable.
    link_images=("$ios_app/$executable_name.debug.dylib")
  fi
  actual_symbols="$(
    for image in "${link_images[@]}"; do
      nm -arch "$architecture" -gU "$image" 2>/dev/null || true
    done | awk '$NF ~ /^_ianvs_/ { print $NF }' | LC_ALL=C sort -u
  )"
  expected_symbols="$(LC_ALL=C sort -u "$IOS_EXPORTS_FILE")"
  if [[ "$actual_symbols" != "$expected_symbols" ]]; then
    echo "The iOS application does not export the exact current Ianvs C ABI." >&2
    diff -u \
      <(printf '%s\n' "$expected_symbols") \
      <(printf '%s\n' "$actual_symbols") >&2 || true
    exit 1
  fi
}

if ! xcrun simctl list devices | grep -F "$IOS_SIMULATOR_UDID" | grep -F '(Booted)' >/dev/null; then
  xcrun simctl boot "$IOS_SIMULATOR_UDID"
  SIMULATOR_STARTED=1
fi
xcrun simctl bootstatus "$IOS_SIMULATOR_UDID" -b

(
  cd "$EXAMPLE_DIR"
  "${apple_build_env[@]}" flutter build ios --simulator --debug --no-codesign
)

IOS_APP="$(find "$EXAMPLE_DIR/build/ios/iphonesimulator" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$IOS_APP" ]]; then
  echo "Flutter did not produce an iOS simulator application." >&2
  exit 1
fi
verify_ios_native_exports "$IOS_APP" "$simulator_arch"

(
  cd "$EXAMPLE_DIR"
  "${apple_build_env[@]}" xcodebuild test \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -configuration Debug \
    -destination "id=$IOS_SIMULATOR_UDID" \
    -parallel-testing-enabled NO \
    "ARCHS=$simulator_arch" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO
  "${apple_build_env[@]}" flutter test -d "$IOS_SIMULATOR_UDID" \
    integration_test/ios_sandbox_shell_acceptance_test.dart
)

(
  cd "$EXAMPLE_DIR"
  "${apple_build_env[@]}" flutter build ios --release --no-codesign
)
IOS_RELEASE_APP="$(
  find "$EXAMPLE_DIR/build/ios/iphoneos" \
    -maxdepth 1 -name '*.app' -print -quit
)"
if [[ -z "$IOS_RELEASE_APP" ]]; then
  echo "Flutter did not produce an iOS Release device application." >&2
  exit 1
fi
verify_ios_native_exports "$IOS_RELEASE_APP" arm64
