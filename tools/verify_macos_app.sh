#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
EXAMPLE_DIR="$ROOT_DIR/example"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "The macOS application gate requires macOS." >&2
  exit 1
fi

# This entry point also runs in a fresh CI job without the repository gate.
(
  cd "$ROOT_DIR"
  flutter pub get
)
PROFILE=debug "$ROOT_DIR/tools/build_core.sh"

(
  cd "$EXAMPLE_DIR"
  verify_release_bundle() (
    release_app="$1"
    release_executable="$release_app/Contents/MacOS/Trail"
    release_core="$release_app/Contents/Frameworks/ianvs_core.framework/ianvs_core"

    for arch in $(lipo -archs "$release_executable"); do
      if ! lipo "$release_core" -verify_arch "$arch" >/dev/null 2>&1; then
        echo "Release Rust core is missing app architecture $arch." >&2
        echo "App architectures: $(lipo -archs "$release_executable")" >&2
        echo "Rust core architectures: $(lipo -archs "$release_core")" >&2
        exit 1
      fi
    done

    python3 "$ROOT_DIR/tools/verify_native_contract.py" \
      --library "$release_core"

    codesign --verify --deep --strict "$release_app"
    signature_metadata="$(codesign -d --verbose=4 "$release_app" 2>&1)"
    case "$signature_metadata" in
      *"runtime)"*) ;;
      *)
        echo "Release app signature must enable hardened runtime." >&2
        exit 1
        ;;
    esac

    release_entitlements=""
    cleanup_release_entitlements() {
      if [ -n "$release_entitlements" ]; then
        rm -f -- "$release_entitlements"
      fi
    }
    trap cleanup_release_entitlements EXIT
    release_entitlements="$(mktemp /private/tmp/ianvs-release-entitlements.plist.XXXXXX)"
    codesign -d --entitlements :- "$release_app" \
      2>/dev/null >"$release_entitlements"
    plutil -lint "$release_entitlements" >/dev/null
    case "$signature_metadata" in
      *"Signature=adhoc"*)
        if [ "$(plutil -convert json -o - "$release_entitlements")" != "{}" ]; then
          echo "Ad-hoc Release app must have an empty entitlement dictionary." >&2
          exit 1
        fi
        ;;
      *)
        keychain_group="$(
          plutil -extract keychain-access-groups.0 raw \
            -o - "$release_entitlements" 2>/dev/null || true
        )"
        case "$keychain_group" in
          *work.ianvs.trail) ;;
          *)
            echo "Certificate-signed Release app must expose the work.ianvs.trail Keychain group." >&2
            exit 1
            ;;
        esac
        ;;
    esac
    if [ "$(
      plutil -extract com.apple.security.cs.disable-library-validation raw \
        -o - "$release_entitlements" 2>/dev/null || true
    )" = "true" ] && [[ "$signature_metadata" != *"Signature=adhoc"* ]]; then
      echo "Certificate-signed Release app must retain library validation." >&2
      exit 1
    fi
  )

  IANVS_CORE_LIB="$CORE_DIR/target/debug/libianvs_core.dylib" \
    flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart
  IANVS_CORE_LIB="$CORE_DIR/target/debug/libianvs_core.dylib" \
    flutter test -d macos integration_test/real_pty_acceptance_test.dart
  flutter test -d macos \
    integration_test/macos_keychain_profile_secret_test.dart
  flutter build macos --debug
  debug_app="$EXAMPLE_DIR/build/macos/Build/Products/Debug/Trail Development.app"
  codesign --verify --deep --strict "$debug_app"
  flutter build macos --release
  release_app="$EXAMPLE_DIR/build/macos/Build/Products/Release/Trail.app"
  verify_release_bundle "$release_app"
  # Rebuild once more to exercise CodeAsset incremental packaging and prove
  # that a Release rebuild still seals the bundled dylib cleanly.
  flutter build macos --release
  verify_release_bundle "$release_app"

  # Xcode pre-actions print their complete inherited environment. Run the
  # native test target with an allowlisted environment so local/CI signing,
  # publishing, cloud, and repository credentials cannot enter build logs.
  xcode_test_env=(
    /usr/bin/env -i
    "HOME=$HOME"
    "PATH=$PATH"
    "TMPDIR=${TMPDIR:-/tmp}"
    "LANG=${LANG:-en_US.UTF-8}"
    "LC_ALL=${LC_ALL:-en_US.UTF-8}"
  )
  if [ -n "${DEVELOPER_DIR:-}" ]; then
    xcode_test_env+=("DEVELOPER_DIR=$DEVELOPER_DIR")
  fi
  if [ -n "${TOOLCHAINS:-}" ]; then
    xcode_test_env+=("TOOLCHAINS=$TOOLCHAINS")
  fi
  "${xcode_test_env[@]}" xcodebuild test \
    -workspace macos/Runner.xcworkspace \
    -scheme Runner \
    -configuration Debug \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO
)
