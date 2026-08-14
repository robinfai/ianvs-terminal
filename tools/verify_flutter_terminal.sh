#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/native/core"
VENDORED_TERMINAL_CORE_DIR="$ROOT_DIR/native/vendor/par-term-emu-core-rust"
VENDORED_ZMODEM_DIR="$ROOT_DIR/native/vendor/zmodem2"
PTY_DIR="$ROOT_DIR/packages/ianvs_pty"
TERMINAL_DIR="$ROOT_DIR/packages/ianvs_terminal"
TERMINAL_CORE_DIR="$ROOT_DIR/packages/ianvs_terminal_core"
EXAMPLE_DIR="$ROOT_DIR/example"
BACKEND_DIR="$ROOT_DIR/backend"
VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION="${VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION:-0}"
VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH="${VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH:-0}"

if ! command -v rustup >/dev/null 2>&1 || \
  ! rustup target list --installed | rg -Fx 'thumbv7em-none-eabihf' >/dev/null; then
  echo "Missing Rust target thumbv7em-none-eabihf." >&2
  echo "Install it with: rustup target add thumbv7em-none-eabihf" >&2
  exit 1
fi

"$ROOT_DIR/tools/build_core.sh"
"$ROOT_DIR/tools/verify_generated_contracts.sh"
dart run "$ROOT_DIR/tools/sync_terminal_core.dart" --check

python3 "$ROOT_DIR/tools/validate_osc_protocol_corpus.py"
python3 "$ROOT_DIR/tools/osc_semantic_probe.py" --self-test

(
  cd "$BACKEND_DIR"
  test -z "$(gofmt -l .)"
  go vet ./...
  go test -race ./...
)

(
  cd "$VENDORED_TERMINAL_CORE_DIR"
  cargo fmt --check
  cargo clippy --locked --all-targets -- -D warnings
  cargo test --locked -- --test-threads=1
)

(
  cd "$VENDORED_ZMODEM_DIR"
  cargo fmt --check
  cargo clippy --locked --all-targets --all-features -- -D warnings
  cargo check --locked --no-default-features --lib --target thumbv7em-none-eabihf
  # The integration tests spawn host `rz`/`sz`; real GNU lrzsz interoperability
  # is covered by the dedicated Docker/OpenSSH CI job below the generic gates.
  cargo test --locked --all-features --lib
  cargo test --locked --no-default-features --lib
)

(
  cd "$CORE_DIR"
  cargo fmt --check
  cargo clippy --locked --all-targets -- -D warnings
  # Set IANVS_REQUIRE_POSIX_SHM_TESTS=1 on hosts where Kitty POSIX shared memory
  # support must be verified instead of skipped when the OS blocks shm_open.
  cargo test --locked -- --test-threads=1
)

# The standalone pub.dev artifact mirrors the canonical ABI and must remain
# independently buildable from its packaged source tree.
(
  cd "$TERMINAL_CORE_DIR/native/core"
  cargo test --locked \
    --test ffi_abi_manifest_test \
    --test session_architecture_test
)

(
  cd "$ROOT_DIR"
  dart format --output=none --set-exit-if-changed .
  dart analyze --fatal-infos
)

(
  cd "$PTY_DIR"
  dart test
)

(
  cd "$TERMINAL_DIR"
  flutter test
)

(
  cd "$TERMINAL_CORE_DIR"
  flutter analyze --fatal-infos
  flutter test
)

(
  cd "$ROOT_DIR"
  dart test test/docs_contract_test.dart
  dart test \
    test/backend_makefile_contract_test.dart \
    test/terminal_core_publish_contract_test.dart \
    test/apple_build_environment_contract_test.dart \
    test/openapi_document_test.dart
)

(
  cd "$ROOT_DIR"
  dart run tools/bench/runner/bench_runner.dart --config tools/bench/configs/bench_ci_smoke.yaml
  if [ "$VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH" = "1" ]; then
    dart run tools/bench/runner/bench_runner.dart --config tools/bench/configs/bench_nightly_resource.yaml
  else
    echo "Skipping nightly resource benchmark because VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH!=1"
  fi
)

if rg -n "Set as default" "$ROOT_DIR/example/lib"; then
  echo "Found forbidden inline default mutation text in example/lib" >&2
  exit 1
fi

rg -n "Defaults & appearance" "$ROOT_DIR/example/lib/features/shell" >/dev/null

if rg -n "AppPreferencesRepository" "$ROOT_DIR/example/lib" | \
  rg -v "features/preferences/app_preferences_repository.dart|features/sessions/session_bootstrap.dart|features/sessions/session_controller.dart|features/config/local_terminal_config_loader.dart"; then
  echo "Found AppPreferencesRepository usage outside the approved Phase 3 write/bootstrap paths" >&2
  exit 1
fi

(
  cd "$EXAMPLE_DIR"
  EXAMPLE_CI_TEST_TARGETS=()
  while IFS= read -r test_target; do
    EXAMPLE_CI_TEST_TARGETS+=("$test_target")
  done < <(
    find test -type f -name '*_test.dart' \
      ! -path 'test/benchmarks/cat_log_benchmark_test.dart' \
      -print | LC_ALL=C sort
  )
  if [ "${#EXAMPLE_CI_TEST_TARGETS[@]}" -eq 0 ]; then
    echo "No example tests were discovered." >&2
    exit 1
  fi
  echo "Discovered ${#EXAMPLE_CI_TEST_TARGETS[@]} example test files."
  # The cat-log benchmark requires a captured trace and is exercised by
  # tools/cat_log_benchmark.sh. Every self-contained test, including newly
  # added test/data and test/pty suites, is discovered automatically here.
  flutter test "${EXAMPLE_CI_TEST_TARGETS[@]}"
)

if [ "$VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION" = "1" ]; then
  echo "Skipping macOS integration tests because VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION=1"
  exit 0
fi

(
  cd "$EXAMPLE_DIR"
  verify_release_bundle() (
    release_app="$1"
    release_executable="$release_app/Contents/MacOS/Ianvs Terminal"
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
    if [ "$(plutil -convert json -o - "$release_entitlements")" != "{}" ]; then
      echo "Release app must have an empty entitlement dictionary." >&2
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
  debug_app="$EXAMPLE_DIR/build/macos/Build/Products/Debug/Ianvs Terminal Dev.app"
  codesign --verify --deep --strict "$debug_app"
  flutter build macos --release
  release_app="$EXAMPLE_DIR/build/macos/Build/Products/Release/Ianvs Terminal.app"
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
