#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_DIR="$ROOT_DIR/example"
FLUTTER_BIN="${1:-flutter}"
IOS_SIMULATOR_UDID="${IANVS_IOS_SIMULATOR_UDID:-}"
SIMULATOR_CREDENTIALS="${IANVS_IOS_SIMULATOR_CREDENTIALS:-}"
SIMULATOR_REMOTE_API_URL="${IANVS_IOS_SIMULATOR_REMOTE_API_URL:-https://api.terminal.ianvs.work/}"
credential_broker_pid=""
credential_broker_ready=""
credential_broker_consumed=""

cleanup() {
  if [[ -n "$credential_broker_pid" ]]; then
    kill "$credential_broker_pid" >/dev/null 2>&1 || true
    wait "$credential_broker_pid" 2>/dev/null || true
  fi
  if [[ -n "$credential_broker_ready" ]]; then
    rm -f "$credential_broker_ready"
  fi
  if [[ -n "$credential_broker_consumed" ]]; then
    rm -f "$credential_broker_consumed"
  fi
}
trap cleanup EXIT INT TERM

if [[ "$#" -gt 1 ]]; then
  echo "Usage: tools/install_ios_simulator.sh [flutter-binary]" >&2
  exit 64
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Installing an iOS simulator app requires macOS." >&2
  exit 1
fi

available_devices="$(xcrun simctl list devices available)"

select_simulator_line() {
  local state="$1"
  awk -v requested_state="$state" '
    /^-- iOS / { in_ios = 1; next }
    /^-- / { in_ios = 0 }
    in_ios && /iPhone/ && index($0, "(" requested_state ")") { print; exit }
  ' <<<"$available_devices"
}

find_requested_simulator_line() {
  local requested_id="$1"
  awk -v requested_id="$requested_id" '
    /^-- iOS / { in_ios = 1; next }
    /^-- / { in_ios = 0 }
    in_ios && /iPhone/ && index($0, "(" requested_id ")") { print; exit }
  ' <<<"$available_devices"
}

if [[ -n "$IOS_SIMULATOR_UDID" ]]; then
  simulator_line="$(find_requested_simulator_line "$IOS_SIMULATOR_UDID")"
else
  simulator_line="$(select_simulator_line Booted)"
  if [[ -z "$simulator_line" ]]; then
    simulator_line="$(select_simulator_line Shutdown)"
  fi
  IOS_SIMULATOR_UDID="$(
    sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/' <<<"$simulator_line"
  )"
fi

if [[ -z "$simulator_line" || ! "$IOS_SIMULATOR_UDID" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  echo "No available iPhone simulator was found." >&2
  exit 1
fi

simulator_name="$(
  sed -E 's/^[[:space:]]*//; s/[[:space:]]+\([0-9A-Fa-f-]{36}\)[[:space:]]+\((Booted|Shutdown)\).*$//' \
    <<<"$simulator_line"
)"

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

printf 'Using iPhone simulator: %s (%s)\n' \
  "$simulator_name" "$IOS_SIMULATOR_UDID"
if ! xcrun simctl list devices | grep -F "$IOS_SIMULATOR_UDID" | grep -F '(Booted)' >/dev/null; then
  xcrun simctl boot "$IOS_SIMULATOR_UDID"
fi
xcrun simctl bootstatus "$IOS_SIMULATOR_UDID" -b

(
  cd "$EXAMPLE_DIR"
  "${apple_build_env[@]}" "$FLUTTER_BIN" build ios \
    --simulator --debug --no-codesign -t lib/simulator_main.dart
)

IOS_APP="$(
  find "$EXAMPLE_DIR/build/ios/iphonesimulator" \
    -maxdepth 1 -name '*.app' -print -quit
)"
if [[ -z "$IOS_APP" ]]; then
  echo "Flutter did not produce an iOS simulator application." >&2
  exit 1
fi
IOS_BUNDLE_ID="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$IOS_APP/Info.plist"
)"
if [[ -z "$IOS_BUNDLE_ID" ]]; then
  echo "The iOS simulator application has no bundle identifier." >&2
  exit 1
fi

xcrun simctl install "$IOS_SIMULATOR_UDID" "$IOS_APP"
if [[ -n "$SIMULATOR_CREDENTIALS" && -f "$SIMULATOR_CREDENTIALS" ]]; then
  credentials_mode="$(stat -f '%Lp' "$SIMULATOR_CREDENTIALS")"
  if (( (8#$credentials_mode & 077) != 0 )); then
    echo "Simulator credentials must be owner-only (0600 or 0400)." >&2
    exit 1
  fi
  credential_broker_ready="$(
    mktemp "${TMPDIR:-/tmp}/ianvs-simulator-broker.XXXXXX.txt"
  )"
  credential_broker_consumed="$(
    mktemp "${TMPDIR:-/tmp}/ianvs-simulator-consumed.XXXXXX.txt"
  )"
  chmod 600 "$credential_broker_ready" "$credential_broker_consumed"
  /usr/bin/env -i "PATH=$PATH" python3 \
    "$ROOT_DIR/tools/serve_acceptance_credentials.py" \
    "$SIMULATOR_CREDENTIALS" "$credential_broker_ready" \
    "$credential_broker_consumed" &
  credential_broker_pid=$!
  for _ in {1..600}; do
    [[ -s "$credential_broker_ready" ]] && break
    kill -0 "$credential_broker_pid" 2>/dev/null || {
      echo "Simulator credential broker exited before becoming ready." >&2
      exit 1
    }
    sleep 0.05
  done
  if [[ ! -s "$credential_broker_ready" ]]; then
    echo "Simulator credential broker did not become ready within 30 seconds." >&2
    exit 1
  fi
  credentials_url="$(<"$credential_broker_ready")"
  if [[ "$credentials_url" != http://127.0.0.1:*/* ]]; then
    echo "Simulator credential broker published an invalid URL." >&2
    exit 1
  fi
  SIMCTL_CHILD_IANVS_SIMULATOR_CREDENTIALS_URL="$credentials_url" \
    SIMCTL_CHILD_IANVS_SIMULATOR_REMOTE_API_URL="$SIMULATOR_REMOTE_API_URL" \
    xcrun simctl launch --terminate-running-process \
      "$IOS_SIMULATOR_UDID" "$IOS_BUNDLE_ID"
  for _ in {1..600}; do
    [[ -s "$credential_broker_consumed" ]] && break
    kill -0 "$credential_broker_pid" 2>/dev/null || {
      echo "Simulator credential broker exited before key delivery." >&2
      exit 1
    }
    sleep 0.05
  done
  if [[ ! -s "$credential_broker_consumed" ]]; then
    echo "Simulator did not consume credentials within 30 seconds." >&2
    exit 1
  fi
  printf '%s\n' 'Delivered owner-only credentials through a loopback broker.'
else
  xcrun simctl launch --terminate-running-process \
    "$IOS_SIMULATOR_UDID" "$IOS_BUNDLE_ID"
fi
printf 'Installed and launched: %s\n' "$IOS_BUNDLE_ID"
