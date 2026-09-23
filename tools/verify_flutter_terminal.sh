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
  ! rustup target list --installed | grep -Fqx -- 'thumbv7em-none-eabihf' >/dev/null; then
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
  # Preserve the upstream release snapshot without rewriting hundreds of
  # format calls to inline captured arguments; all other warnings stay denied.
  cargo clippy --locked --all-targets -- \
    -D warnings \
    -A clippy::uninlined_format_args
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
  dart test test/runtime_documentation_contract_test.dart
  dart test \
    test/backend_makefile_contract_test.dart \
    test/terminal_core_publish_contract_test.dart \
    test/apple_build_environment_contract_test.dart \
    test/install_ios_simulator_contract_test.dart \
    test/select_physical_ios_device_test.dart \
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

if grep -RFn -- "Set as default" "$ROOT_DIR/example/lib"; then
  echo "Found forbidden inline default mutation text in example/lib" >&2
  exit 1
fi

grep -F -- "title: context.l10n.defaultsAppearance" \
  "$ROOT_DIR/example/lib/features/shell/shell_screen_command_menu.dart" >/dev/null

if grep -RFnw -- "AppPreferencesRepository" "$ROOT_DIR/example/lib" | \
  grep -Ev "features/preferences/app_preferences_repository.dart|features/sessions/session_bootstrap.dart|features/sessions/session_controller.dart|features/config/local_terminal_config_loader.dart|persistence_repository_composition.dart"; then
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

"$ROOT_DIR/tools/verify_macos_app.sh"
