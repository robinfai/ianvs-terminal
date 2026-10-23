# CI cancellation and native phase measurements

## Scope

This iteration repairs the Example driver's cancellation cleanup and establishes a measurable baseline. It does not enable a new compilation cache, increase concurrency, add jobs, remove tests, or relax ABI/visual/Apple gates. Example still runs one Flutter invocation with concurrency 2.

## Cancellation

The driver records the first cancellation signal without raising through process creation. It tails a durable log rather than waiting on a pipe that a descendant could keep open. Cleanup inspects PID/group/state, sends TERM, waits for the group (not only the launcher), and sends KILL only when live members remain. Both waits and process inspection are bounded.

A group signalling permission/lookup error is accepted only after a successful fresh snapshot shows no live members. A live or uninspectable group is an explicit cleanup failure. A successful test command with failed cleanup becomes failure; an already failing/cancelled command retains its original nonzero code. `summary.json` schema 2 records both `command_exit_code` and `cleanup_status`/`cleanup_error`. Existing `exit_code`, `files`, `concurrency`, and elapsed fields remain.

## Measurements

`IANVS_CI_NATIVE_METRICS=1` enables the read-only collector in the existing Flutter checks and Example test step. Local verification is unchanged unless explicitly opted in. Outputs are printed as `CI_NATIVE_PHASE` and written under `build/ci/native-phases/`. The workflow uploads `flutter-native-phase-diagnostics` and `example-native-phase-diagnostics` with `if: always()` and seven-day retention, subject to runner availability during forced cancellation.

The collector reads existing `ianvs-cargo-build.json` files. It prunes Cargo build trees and does not run, replay, clean, or change Cargo. It records source (canonical/packaged), target, profile, output directory, duration, exit code, and an explicit small build-environment allowlist. No arbitrary environment or command arguments are copied.

A build is attributed only when its metric changed and its recorded interval falls inside the phase. Unchanged/old/out-of-window/malformed/removed metrics are counted or diagnosed, not silently treated as new builds. Nested phase observations belong to the child, preventing parent/child double-counting. Overlapping Hook durations use the interval union for wall time; summed work time is recorded separately.

Golden, PTY, terminal-package, standalone-core, and Example timings can now be compared with Hook work. The generated-contract phase also exposes C-header generation, canonical and packaged clean ABI compilation, and source-sync timings separately. Both ABI builds retain separate fresh target directories and actual-library verification.

## Interpretation and next experiment

`unattributed_seconds` includes all unmeasured preparation, compilation, loading and test execution. It is not a test-only number. No metric is not proof that no build happened, and the collector does not infer cache hits (`cache_status` is `unknown`). A forcibly terminated process may leave only a `.start.json`; that is incomplete evidence, not a completed measurement. Diagnostic collection errors are reported without replacing product exit status.

First obtain a fully successful Verify run with these records. Then select one native-dependency reuse experiment, keeping Debug/Release, target, SDK/toolchain, and source provenance boundaries explicit. Compare cold/warm paired runs, cache overhead, wall time, queue time and macOS runner-minutes. Do not claim speedup from failed or partial CI runs.

## Local validation for this iteration

Linux: 48 tests passed (17 unchanged Example orchestration tests, 19 new cleanup regressions, 12 measurement/workflow/shell regressions). Cancellation tests use real child processes; OS error races and Cargo preparation use controlled fixtures. The unchanged original test file was checked against Git blob `8c6f426d7e1da7b89d63b4baec437c75e57bc920`.

Workflow validation confirmed the same 10 job definitions, runners, dependency graph, matrix and timeouts; existing steps were retained. All 31 Bash run blocks and the three edited shell scripts passed syntax checks; remote actions remain commit-pinned. This environment has no Flutter, Cargo or Xcode product toolchain. These results do not certify macOS behaviour or the full product verification suite; GitHub Actions remains the acceptance gate.
