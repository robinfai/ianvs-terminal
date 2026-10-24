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
# CI sets this only after its separate blocking visual-baseline gate ran.
# That step remains failed when the visual comparison fails; it is not retried.
# A normal local invocation still discovers and runs every design test.
VERIFY_FLUTTER_TERMINAL_SKIP_DESIGN_TESTS="${VERIFY_FLUTTER_TERMINAL_SKIP_DESIGN_TESTS:-0}"
case "$VERIFY_FLUTTER_TERMINAL_SKIP_DESIGN_TESTS" in
  0|1) ;;
  *) echo "VERIFY_FLUTTER_TERMINAL_SKIP_DESIGN_TESTS must be 0 or 1" >&2; exit 64 ;;
esac
# Keep the local entrypoint complete while CI runs two independent suites.
VERIFY_FLUTTER_TERMINAL_SUITE="${VERIFY_FLUTTER_TERMINAL_SUITE:-all}"
case "$VERIFY_FLUTTER_TERMINAL_SUITE" in
  all|native|flutter) ;;
  *) echo "VERIFY_FLUTTER_TERMINAL_SUITE must be all, native or flutter" >&2; exit 64 ;;
esac
VERIFY_FLUTTER_TERMINAL_EXAMPLE_MODE="${VERIFY_FLUTTER_TERMINAL_EXAMPLE_MODE:-all}"
case "$VERIFY_FLUTTER_TERMINAL_EXAMPLE_MODE" in
  all|skip|only) ;;
  *) echo "Invalid VERIFY_FLUTTER_TERMINAL_EXAMPLE_MODE" >&2; exit 64 ;;
esac
VERIFY_FLUTTER_TERMINAL_EXAMPLE_SHARD="${VERIFY_FLUTTER_TERMINAL_EXAMPLE_SHARD:-all}"
case "$VERIFY_FLUTTER_TERMINAL_EXAMPLE_SHARD" in
  all|0|1|2) ;;
  *) echo "Invalid Example shard" >&2; exit 64 ;;
esac
run_example_tests() (
  ci_begin_phase "Example tests"
  cd "$EXAMPLE_DIR"
  EXAMPLE_CI_TEST_TARGETS=()
  example_test_index=0
  while IFS= read -r test_target; do
    if [ "$VERIFY_FLUTTER_TERMINAL_SKIP_DESIGN_TESTS" = "1" ] && \
      [[ "$test_target" == test/design/* ]]; then
      continue
    fi
    if [ "$VERIFY_FLUTTER_TERMINAL_EXAMPLE_SHARD" = "all" ] || \
       [ "$((example_test_index % 3))" = "$VERIFY_FLUTTER_TERMINAL_EXAMPLE_SHARD" ]; then
      EXAMPLE_CI_TEST_TARGETS+=("$test_target")
    fi
    example_test_index=$((example_test_index + 1))
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
  # CI excludes test/design after its separate blocking gate ran, even if red.
  flutter test "${EXAMPLE_CI_TEST_TARGETS[@]}"
)

# Bash 3.2 can exit before the `time` keyword reports an errexit failure.
# Call only inside a phase subshell: its EXIT trap logs both success/failure
# without changing the parent shell's traps or suppressing `set -e`.
ci_begin_phase() {
  echo "CI phase: $1"
  CI_PHASE_STARTED=$SECONDS
  CI_NATIVE_PHASE_STATE=""
  if [ "${IANVS_CI_NATIVE_METRICS:-0}" = "1" ]; then
    CI_NATIVE_PHASE_STATE="$(python3 "$ROOT_DIR/tools/ci/native_phase_metrics.py" begin "$1")" || \
      echo "Native phase measurement unavailable" >&2
  fi
  trap 'ci_phase_status=$?; printf "CI phase duration: %s seconds\n" "$((SECONDS - CI_PHASE_STARTED))" >&2; if [ -n "$CI_NATIVE_PHASE_STATE" ]; then python3 "$ROOT_DIR/tools/ci/native_phase_metrics.py" finish "$CI_NATIVE_PHASE_STATE" "$ci_phase_status" || echo "Native phase measurement incomplete" >&2; fi; exit "$ci_phase_status"' EXIT
}

if [ "$VERIFY_FLUTTER_TERMINAL_SUITE" != "flutter" ]; then
  if ! command -v rustup >/dev/null 2>&1 || \
    ! rustup target list --installed | grep -Fqx -- 'thumbv7em-none-eabihf' >/dev/null; then
    echo "Missing Rust target thumbv7em-none-eabihf." >&2
    echo "Install it with: rustup target add thumbv7em-none-eabihf" >&2
    exit 1
  fi
fi

if [ "$VERIFY_FLUTTER_TERMINAL_EXAMPLE_MODE" = "only" ]; then
  if [ "$VERIFY_FLUTTER_TERMINAL_SUITE" != "flutter" ]; then
    echo "Example-only requires flutter suite" >&2; exit 64
  fi
  (
    ci_begin_phase "Example native debug build"
    "$ROOT_DIR/tools/build_core.sh"
  )
  run_example_tests
  # Keep the experiment outside the measured test phase. Only shard 0 replays
  # Cargo; the other shards report the original hook measurement unchanged.
  if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    NATIVE_PROBE_ARGS=(--root "$ROOT_DIR")
    if [ "$VERIFY_FLUTTER_TERMINAL_EXAMPLE_SHARD" = "0" ]; then
      NATIVE_PROBE_ARGS+=(--replay)
    fi
    python3 "$ROOT_DIR/tools/ci/native_hook_probe.py" "${NATIVE_PROBE_ARGS[@]}"
  fi
  exit 0
fi

if [ "$VERIFY_FLUTTER_TERMINAL_SUITE" != "native" ]; then
  (
    ci_begin_phase "Native debug prebuild"
    "$ROOT_DIR/tools/build_core.sh"
  )
  (
    ci_begin_phase "Generated contracts and sync"
    "$ROOT_DIR/tools/verify_generated_contracts.sh"
    if [ "${IANVS_CI_NATIVE_METRICS:-0}" = "1" ]; then
      python3 "$ROOT_DIR/tools/ci/time_command.py" 'Standalone source sync' -- \
        dart run "$ROOT_DIR/tools/sync_terminal_core.dart" --check
    else
      dart run "$ROOT_DIR/tools/sync_terminal_core.dart" --check
    fi
  )
  (
    ci_begin_phase "OSC corpus validation"
    python3 "$ROOT_DIR/tools/validate_osc_protocol_corpus.py"
    python3 "$ROOT_DIR/tools/osc_semantic_probe.py" --self-test
  )
fi

if [ "$VERIFY_FLUTTER_TERMINAL_SUITE" != "flutter" ]; then
  (
    ci_begin_phase "Rust completion core"
    cd "$ROOT_DIR/native/completion_core"
    cargo fmt --check
    cargo clippy --locked --all-targets -- -D warnings
    cargo test --locked
  )
  if [ "$(uname -s)" = "Darwin" ]; then
    python3 "$ROOT_DIR/tools/composer/run_shell_matrix.py" --required --shell zsh
  fi

  (
    ci_begin_phase "Go backend"
    cd "$BACKEND_DIR"
    test -z "$(gofmt -l .)"
    go vet ./...
    go test -race ./...
  )

  (
    ci_begin_phase "Vendored terminal core"
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
    ci_begin_phase "Vendored ZMODEM"
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
    ci_begin_phase "Rust application core"
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
    ci_begin_phase "Packaged ABI contracts"
    cd "$TERMINAL_CORE_DIR/native/core"
    cargo test --locked \
      --test ffi_abi_manifest_test \
      --test session_architecture_test
  )
fi

# A native-only run must never invoke Flutter or the Apple app integration.
if [ "$VERIFY_FLUTTER_TERMINAL_SUITE" = "native" ]; then
  exit 0
fi

(
  ci_begin_phase "Dart formatting and analysis"
  cd "$ROOT_DIR"
  # Match the source scope of `make format-check`, including repository tools.
  # Ignored scratch probes and old staged checkouts are not product sources.
  dart format --output=none --set-exit-if-changed \
    example/lib example/test example/integration_test example/test_driver \
    example/test_http example/tool packages test tools
  dart analyze --fatal-infos
)

(
  ci_begin_phase "Dart PTY tests"
  cd "$PTY_DIR"
  dart test
)

(
  ci_begin_phase "Flutter terminal package tests"
  cd "$TERMINAL_DIR"
  flutter test
)

(
  ci_begin_phase "Standalone terminal core tests"
  cd "$TERMINAL_CORE_DIR"
  flutter analyze --fatal-infos
  flutter test
)

(
  ci_begin_phase "Repository contract tests"
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
  ci_begin_phase "Performance smoke"
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

if [ "$VERIFY_FLUTTER_TERMINAL_EXAMPLE_MODE" != "skip" ]; then
  run_example_tests
fi

if [ "$VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION" = "1" ]; then
  echo "Skipping macOS integration tests because VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION=1"
  exit 0
fi

"$ROOT_DIR/tools/verify_macos_app.sh"
