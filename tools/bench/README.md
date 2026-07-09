# Ianvs Terminal Benchmark Suite

This directory contains the MVP benchmark suite for validating terminal
semantic/render decoupling:

- `snapshot_only`
- `delta_no_coalesce`
- `delta_coalesced`
- deterministic trace replay
- final viewport hash correctness
- Rust/Dart/Flutter-style NDJSON metrics
- optional OS resource NDJSON metrics
- `summary.csv` and `summary.md`

## CI Smoke

```bash
dart run tools/bench/runner/bench_runner.dart \
  --config tools/bench/configs/bench_ci_smoke.yaml
```

The smoke config runs small deterministic workloads in `headless_state_only`
mode and checks `snapshot_only` versus `delta_coalesced` final viewport hashes.
It also enforces schema validation for collected `correctness.json` and
`rust_frame.ndjson` artifacts. The smoke config also collects
`os_resource.ndjson` for process CPU/RSS visibility and enforces the configured
p95 frame-build, JSON-decode, and apply limits.

The `schemas/rust_frame.schema.json` file documents benchmark metric events.
The Rust/Dart terminal frame wire payload has its own compatibility corpus in
`packages/ianvs_terminal/test/fixtures/frame_diff_corpus` and schema in
`schemas/terminal_frame_diff.schema.json`; run
`cd packages/ianvs_terminal && flutter test test/terminal_frame_diff_corpus_test.dart`
after changing frame-diff JSON fields.

## Nightly Resource Gate

Use the quiet-host/nightly config when the runner machine has stable load and
resource samples should be hard pass/fail inputs:

```bash
VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH=1 ./tools/verify_flutter_terminal.sh
```

Or run the resource gate directly:

```bash
dart run tools/bench/runner/bench_runner.dart \
  --config tools/bench/configs/bench_nightly_resource.yaml
```

That config includes an idle baseline plus sustained output, scrollback, and
resize workloads, and enforces CPU/RSS gates:

```yaml
gates:
  max_p95_process_cpu_percent: 80
  max_peak_process_rss_bytes: 512000000
```

Keep those thresholds out of ad-hoc developer smoke runs unless the host load is
controlled; the default CI smoke records resource samples without using them as
hard pass/fail limits.

## Single Workload

```bash
dart run tools/bench/runner/bench_runner.dart \
  --workload burst_stdout.seq_1000 \
  --frame-policy delta_coalesced \
  --render-policy headless_state_only \
  --cols 80 \
  --rows 24 \
  --output build/bench-results
```

## Analyze Existing Run

```bash
dart run tools/bench/analysis/summarize.dart --input build/bench-results/<run>
```

## Frame Diff Transport Microbenchmark

To compare JSON and protobuf frame payload size plus Dart decode cost without
launching the full app harness:

```bash
cd packages/ianvs_terminal
flutter test test/benchmarks/frame_diff_transport_benchmark_test.dart \
  --plain-name "frame diff transport benchmark exports metrics" \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_OUT=/absolute/path/metrics.json
```

Optional defines:

```bash
--dart-define=FRAME_DIFF_TRANSPORT_BENCH_ITERATIONS=120
--dart-define=FRAME_DIFF_TRANSPORT_BENCH_FRAMES=120
--dart-define=FRAME_DIFF_TRANSPORT_BENCH_ROWS=40
--dart-define=FRAME_DIFF_TRANSPORT_BENCH_COLS=120
--dart-define=FRAME_DIFF_TRANSPORT_BENCH_WORKLOAD=mixed
```

The test is skipped unless `FRAME_DIFF_TRANSPORT_BENCH_OUT` is provided. The
default `mixed` workload uses fixed viewport dimensions with periodic snapshot
frames. Use `FRAME_DIFF_TRANSPORT_BENCH_WORKLOAD=resize_churn` to mirror the
profile harness resize cadence: every eight frames the synthetic viewport rows
and columns change, producing snapshot frames for resize transitions and delta
frames between them. The metrics include aggregate transport numbers and a
`by_frame_kind` breakdown for `snapshot` versus `delta` frames.

## Real Flutter Profile Matrix

The synthetic runner above is deterministic and fast, but it does not launch the
Flutter engine. To capture real Flutter rendering, run the profile harness from
the example app:

```bash
cd example
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/terminal_render_profile_test.dart \
  -d macos \
  --profile \
  --dart-define=IANVS_BENCH_PROFILE_OUTPUT=/absolute/path/to/ianvs-terminal/build/bench-results-profile/<run> \
  --dart-define=IANVS_BENCH_PROFILE_TARGET_LABEL=macos-darwin-arm64
```

By default this runs `burst_stdout_profile`, `scrollback_heavy_profile`, and
`resize_churn_profile` with five repeats each. The root output directory gets
`summary.csv`, `summary_by_workload.csv`, and `summary.md`. Each run directory
also gets `flutter_render.ndjson`, `flutter_frame_timing.ndjson`,
`metadata.json`, `correctness.json`, `summary.csv`, and `summary.md`.

## End-to-End Frame Transport Profile

To compare protobuf against a forced JSON wire path through the native runtime,
FFI boundary, Dart decode/apply, polling, and Flutter render pipeline, run the
transport profile harness:

```bash
cd example
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/terminal_transport_profile_test.dart \
  -d macos \
  --profile \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_OUTPUT=/absolute/path/to/ianvs-terminal/build/bench-results-profile/<run>/macos-darwin \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_TARGET_LABEL=macos-darwin \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_WORKLOADS=burst_stdout_profile,scrollback_heavy_profile,resize_churn_profile \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_WIRE_FORMATS=protobuf,json \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_REPEATS=3 \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_FRAME_COUNT=96
```

The output root gets `summary.csv`, `summary_by_workload.csv`, `summary.md`,
and `paired_hashes.json`. Each run directory gets `flutter_render.ndjson`,
`flutter_frame_timing.ndjson`, `dart_runtime.ndjson`, `metadata.json`,
`correctness.json`, `summary.csv`, and `summary.md`. The runtime events include
the selected `wire_format`, raw frame byte counts, Dart decode/apply timings,
and native frame build / JSON encode / protobuf encode timings.

The harness asserts that protobuf and forced JSON produce matching final
viewport hashes for each workload/repeat pair. Run the formal audit over the
six wire-prefixed workloads after collection:

```bash
dart run tools/bench/analysis/flutter_profile_audit.dart \
  --input build/bench-results-profile/<run>/macos-darwin \
  --output build/bench-results-profile/<run>/formal-audit \
  --workloads protobuf_burst_stdout_profile,protobuf_scrollback_heavy_profile,protobuf_resize_churn_profile,json_burst_stdout_profile,json_scrollback_heavy_profile,json_resize_churn_profile \
  --repeats 3 \
  --require-target-count 1
```

Useful overrides:

```bash
--dart-define=IANVS_BENCH_PROFILE_WORKLOAD=scrollback_heavy_profile
--dart-define=IANVS_BENCH_PROFILE_WORKLOADS=burst_stdout_profile,resize_churn_profile
--dart-define=IANVS_BENCH_PROFILE_REPEATS=3
--dart-define=IANVS_BENCH_PROFILE_FRAME_COUNT=120
--dart-define=IANVS_BENCH_PROFILE_TARGET_LABEL=<device-or-machine-label>
```

The summary includes real Flutter engine frame timing fields
(`p95_build_duration_micros`, `p95_raster_duration_micros`,
`p95_total_span_micros`) plus render-object paint/cache fields
(`p95_paint_micros`, `row_cache_hit_rate`). The macOS profile target is
currently the primary supported target. Additional native targets can be run by
changing `-d <device-id>` and the target label, provided the target supports the
native `ianvs_pty` FFI dependency. The current example app is not web-ready for
this harness because Chrome/web cannot compile `dart:ffi` dependencies.

For formal multi-device runs, prefer the matrix runner. It discovers Flutter
devices, skips unsupported web targets, and can enforce that enough native
targets are connected:

```bash
dart run tools/bench/runner/flutter_profile_matrix_runner.dart \
  --output build/bench-results-profile/<run> \
  --readiness-output build/bench-results-profile/<run>/readiness.json \
  --runbook-output build/bench-results-profile/<run>/runbook.md \
  --require-target-count 2
```

Use `--dry-run` to inspect the generated `flutter drive` commands without
starting the apps. On a machine with only macOS plus Chrome, the formal
two-target gate fails because Chrome cannot compile the native FFI dependency.
When `--readiness-output` is set, the runner writes a machine-readable
`ianvs-bench-flutter-profile-readiness-v1` JSON file before enforcing the gate,
including supported native targets, skipped targets, and shortage failures.
When `--runbook-output` is set, it also writes a Markdown runbook with target
discovery commands plus the exact matrix/audit commands to rerun after adding a
second native target.

After collecting one or more matrix result directories, run the formal audit to
merge and verify the report gates:

```bash
dart run tools/bench/analysis/flutter_profile_audit.dart \
  --input build/bench-results-profile/<target-run-a> \
  --input build/bench-results-profile/<target-run-b> \
  --output build/bench-results-profile/<formal-report> \
  --readiness-output build/bench-results-profile/<run>/readiness.json \
  --runbook-output build/bench-results-profile/<run>/runbook.md \
  --require-target-count 2 \
  --repeats 5
```

The audit writes `formal_profile_summary.csv`,
`formal_profile_audit.json`, `formal_profile_manifest.json`, and
`formal_profile_report.md`. It fails if target count, workload/repeat coverage,
hash correctness, or raw timing/render event files are missing. When
`--readiness-output` or `--runbook-output` is provided to the audit command, the
manifest records those files plus per-artifact presence and byte-size details.

Benchmark files are written only when these tools are run. Default product app
behavior does not emit benchmark files.
