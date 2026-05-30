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
- `example/tool/cat_log_trace_capture.dart`
- `tools/cat_log_benchmark.sh`
- `tools/technical_blog_action_benchmark.sh`
- `native/core/tests/vttest_regression_test.rs`
- `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- `example/test/terminal/render_terminal_viewport_test.dart`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- Existing functional commands pass for parser, input, render, and search paths, but they do not record throughput or allocation baselines.
- `KNOWN_ISSUES.md` and the audit both identify missing formal performance baselines.
- `Cache translateToString calls`, parser fast-path, parser reset-ZDM, input handler, linkifier, core terminal, and Unicode performance rows all need benchmark evidence before optimization.
- `tools/cat_log_benchmark.sh --out-dir /tmp/ianvs terminal-xterm-risk-benchmark --timeout-sec 5 --profile debug` passed on 2026-05-13. The local debug snapshot captured 384 frames from a 1,185,579-byte fixture; replay time was 3.77s real time on this host. This confirms the benchmark command path and metrics export, but it is not a release-grade baseline.
- `tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-manual-20260529 --timeout-sec 5 --profile release --include-raw-frames` passed on 2026-05-29 on macOS 15.7.7, Apple M1 Pro, 32 GiB RAM. It captured a release bulk-output snapshot with a 1,185,579-byte fixture, 113 frames, replay real time 8.16s, p95 frame duration 7.745ms, p95 frame build 635us, p95 frame extract 279us, 2 of 113 dropped frames, `terminal_process_micros` 29726, and `plain_ascii_fast_path_micros` 28516.
- The 2026-05-29 and 2026-05-30 release snapshots are not complete quiet-host baselines: Codex, the debug example app, and Flutter tooling were active. All T-076 scenario classes now have first release snapshots; quiet-host reruns remain queued in [../../XTERM_MANUAL_CONFIRMATION_QUEUE.md](../../XTERM_MANUAL_CONFIRMATION_QUEUE.md) item M-013 as a future refresh.
- The 2026-05-29 run wrote artifacts under `/tmp/ianvs-terminal-xterm-manual-20260529`. `cat-log-benchmark.time.json` had a malformed `captureTime.realSec` field because the script captured `Running build hooks...real 3.77` without a newline; use `cat-log-benchmark.capture-time.txt` as the capture-time source for that run.
- `tools/cat_log_benchmark.sh` now parses `/usr/bin/time` fields even when build-hook stderr glues text to the `real` token, defaults missing numeric fields to `0`, and records scenario fixture bytes such as `input-echo.fixture.log`.
- `tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-input-echo-20260529-fixed2 --scenario input-echo --timeout-sec 8 --profile release --include-raw-frames` passed on 2026-05-29. `cat-log-benchmark.time.json` validates with `python3 -m json.tool`, records `fixtureBytes: 1538`, capture real 1.32s, and replay real 8.33s. Metrics captured 3 frames, `inputToDisplayMicros` 8958, p95 frame duration 70.5ms, p95 frame build 226us, p95 frame extract 226us, `terminal_process_micros` 42, `plain_ascii_fast_path_micros` 40, and 1 dropped frame.
- `example/tool/cat_log_trace_capture.dart` and `tools/cat_log_benchmark.sh` now support `--scenario url-heavy`; `example/test/benchmarks/cat_log_benchmark_test.dart` replays the captured raw frames and taps visible URL rows through the real `TerminalViewport.onOpenLink` path.
- `tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-url-heavy-20260529-fixed3 --scenario url-heavy --timeout-sec 8 --profile release --include-raw-frames` passed on 2026-05-29. `cat-log-benchmark.time.json`, `cat-log-benchmark.metrics.json`, and `cat-log-benchmark.trace.json` validate with `python3 -m json.tool`. Metrics captured a 377,600-byte fixture, 30 frames, replay real time 7.38s, p95 frame duration 33.307ms, p95 frame build 393us, p95 frame extract 268us, p95 JSON encode 18us, `terminal_process_micros` 8881, 3 dropped frames, and a visible URL probe with 2 attempts and 2 opened links in 36,573us.
- `example/tool/cat_log_trace_capture.dart`, `tools/cat_log_benchmark.sh`, and `tools/technical_blog_action_benchmark.sh` now support `--scenario unicode-heavy`.
- `tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-unicode-heavy-20260529 --scenario unicode-heavy --timeout-sec 8 --profile release --include-raw-frames` passed on 2026-05-29. `cat-log-benchmark.time.json`, `cat-log-benchmark.metrics.json`, and `cat-log-benchmark.trace.json` validate with `python3 -m json.tool`. Metrics captured a 271,587-byte fixture, 58 frames, replay real time 7.05s, p95 frame duration 11.98ms, p95 frame build 804us, p95 frame extract 308us, p95 JSON encode 21us, `terminal_process_micros` 40400, and 3 dropped frames.
- `example/tool/cat_log_trace_capture.dart`, `tools/cat_log_benchmark.sh`, and `tools/technical_blog_action_benchmark.sh` now support `--scenario paste-throughput`, `--scenario search-extraction`, and `--scenario parser-heavy`.
- `tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-paste-throughput-20260530 --scenario paste-throughput --timeout-sec 8 --profile release --include-raw-frames` passed on 2026-05-30. `cat-log-benchmark.time.json`, `cat-log-benchmark.metrics.json`, and `cat-log-benchmark.trace.json` validate with `python3 -m json.tool`. Metrics captured a 45,954-byte, 640-line payload, visible sentinel echo in 107,939us, 1 frame, replay real time 6.71s, p95 frame duration 78.924ms, p95 frame build 221us, p95 frame extract 221us, p95 JSON encode 46us, `terminal_process_micros` 4455, and 1 dropped frame.
- `tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-search-extraction-20260530 --scenario search-extraction --timeout-sec 8 --profile release --include-raw-frames` passed on 2026-05-30. `cat-log-benchmark.time.json`, `cat-log-benchmark.metrics.json`, and `cat-log-benchmark.trace.json` validate with `python3 -m json.tool`. Metrics captured a 430,130-byte fixture, 27 frames, replay real time 7.55s, p95 frame duration 33.632ms, p95 frame build 649us, p95 frame extract 335us, p95 JSON encode 23us, `terminal_process_micros` 13758, 2 dropped frames, and a native search probe returning 4,200 matches in a 371,497-byte result with p95 request time 27,785us.
- `tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-parser-heavy-20260530 --scenario parser-heavy --timeout-sec 8 --profile release --include-raw-frames` passed on 2026-05-30. `cat-log-benchmark.time.json`, `cat-log-benchmark.metrics.json`, and `cat-log-benchmark.trace.json` validate with `python3 -m json.tool`. Metrics captured a 545,160-byte dense CSI/SGR/OSC 8 fixture, 116 frames, replay real time 7.58s, p95 frame duration 14.308ms, p95 frame build 1143us, p95 frame extract 469us, p95 JSON encode 49us, `terminal_process_micros` 66637, and 5 dropped frames.
- Existing debug multi-scenario evidence is archived under `docs/evidence/2026-05-29-benchmark` for `bulk-output`, `streaming-scroll`, `resize`, `alternate-screen`, and `input-echo`; treat those as local host/debug evidence rather than release guarantees.

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
tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-manual-20260529 --timeout-sec 5 --profile release --include-raw-frames
tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-input-echo-20260529-fixed2 --scenario input-echo --timeout-sec 8 --profile release --include-raw-frames
tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-url-heavy-20260529-fixed3 --scenario url-heavy --timeout-sec 8 --profile release --include-raw-frames
tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-unicode-heavy-20260529 --scenario unicode-heavy --timeout-sec 8 --profile release --include-raw-frames
tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-paste-throughput-20260530 --scenario paste-throughput --timeout-sec 8 --profile release --include-raw-frames
tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-search-extraction-20260530 --scenario search-extraction --timeout-sec 8 --profile release --include-raw-frames
tools/cat_log_benchmark.sh --out-dir /tmp/ianvs-terminal-xterm-parser-heavy-20260530 --scenario parser-heavy --timeout-sec 8 --profile release --include-raw-frames
```

## Manual QA

1. Run the benchmark commands on a quiet local machine.
2. Capture host CPU, OS, Flutter version, and command output.
3. Repeat the release benchmark suite on a quiet host when comparing future optimization work.

## Done When

- The audit has concrete benchmark commands instead of functional-test proxies for performance rows.
- Baseline numbers are recorded with host/toolchain context.
- Optimization work is deferred to separate tasks.

## Risks / Follow-ups

- Local performance numbers can vary substantially by host; record host context with every snapshot.
