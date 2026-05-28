# T-076 Terminal Performance Baseline xterm Probes

## Goal

Create explicit terminal performance baselines before optimizing parser, input, search, link detection, frame application, or Unicode-heavy rendering paths.

## Scope

- Parser throughput baseline.
- Frame application throughput baseline.
- URL-heavy visible-row link detection baseline.
- Input and paste throughput baseline.
- Search text extraction cost baseline.
- Unicode-heavy render/scroll baseline.

## Non-goals

- Do not optimize code in this task unless a separate implementation task is created.
- Do not treat functional test pass/fail as performance evidence.
- Do not add external benchmarking dependencies without approval.

## Files In Scope

- `example/test/benchmarks/cat_log_benchmark_test.dart`
- `tools/cat_log_benchmark.sh`
- `native/core/tests/vttest_regression_test.rs`
- `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- `example/test/terminal/render_terminal_viewport_test.dart`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- Existing functional commands pass for parser, input, render, and search paths, but they do not record throughput or allocation baselines.
- `KNOWN_ISSUES.md` and the audit both identify missing formal performance baselines.
- `Cache translateToString calls`, parser fast-path, parser reset-ZDM, input handler, linkifier, core terminal, and Unicode performance rows all need benchmark evidence before optimization.
- `tools/cat_log_benchmark.sh --out-dir /tmp/ianvs terminal-xterm-risk-benchmark --timeout-sec 5 --profile debug` passed on 2026-05-13. The local debug snapshot captured 384 frames from a 1,185,579-byte fixture; replay time was 3.77s real time on this host. This confirms the benchmark command path and metrics export, but it is not a release-grade baseline.
- Release-grade benchmark capture is queued in [../../XTERM_MANUAL_CONFIRMATION_QUEUE.md](../../XTERM_MANUAL_CONFIRMATION_QUEUE.md) item M-013 because useful numbers require a quiet, identified host.

## Functional Acceptance

- Define baseline metrics and acceptable variance for parser, frame application, URL-heavy link detection, input/paste, search extraction, and Unicode-heavy render/scroll.
- Add benchmark commands that can run locally and in CI or document why a benchmark remains manual/local-only.
- Record a first baseline snapshot in the task and audit.
- Split any failing or suspicious performance result into a smaller implementation task.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/benchmarks/cat_log_benchmark_test.dart

tools/cat_log_benchmark.sh
tools/cat_log_benchmark.sh --out-dir /tmp/ianvs terminal-xterm-risk-benchmark --timeout-sec 5 --profile debug
```

## Manual QA

1. Run the benchmark commands on a quiet local machine.
2. Capture host CPU, OS, Flutter version, and command output.
3. Compare a URL-heavy transcript, Unicode-heavy transcript, and large plain ASCII transcript.

## Done When

- The audit has concrete benchmark commands instead of functional-test proxies for performance rows.
- Baseline numbers are recorded with host/toolchain context.
- Optimization work is deferred to separate tasks.

## Risks / Follow-ups

- Local performance numbers can vary substantially by host; record host context with every snapshot.
