# Frame Diff and Row Cache Benchmark Evidence

Date: 2026-05-29
Machine: Mac16,11
CPU: Apple M4 Pro
Memory: 64 GiB
Architecture: arm64
OS: macOS 26.3.1 (25D771280a)
Flutter: 3.44.0 stable
Dart: 3.12.0
Source directory: /tmp/ianvs-technical-blog-action-benchmark
Archived directory: docs/evidence/2026-05-29-benchmark

## Purpose

This directory preserves local benchmark evidence for the Frame Diff, row-cache, fallback, and input echo paths. It is meant to prove that the benchmark chain runs and that the required metrics are captured.

Treat these numbers as local host evidence. Do not present them as cross-machine performance guarantees.

## Included scenarios

- bulk-output
- streaming-scroll
- resize
- alternate-screen
- input-echo

Each scenario directory should include:

- `cat-log-benchmark.trace.json`
- `cat-log-benchmark.metrics.json`
- `cat-log-benchmark.time.json`
- `cat-log-benchmark.capture-time.txt`
- `cat-log-benchmark.replay-time.txt`
- scenario fixture log

Top-level files:

- `commands.txt`
- `environment.txt`
- `benchmark-summary.md`

## Key local observation

`input-echo` observed `inputToDisplayMicros` at 10,596 microseconds in this run.

## Summary

| Scenario | Frames | Snapshot ratio | Delta ratio | JSON bytes | Rows emitted | Dirty row mean | Viewport shift max | Fallback reasons |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| bulk-output | 79 | 0.0127 | 0.9873 | 1,119,474 | 3,120 | 39.49 | 2189.0 | `resize: 1` |
| streaming-scroll | 901 | 0.0011 | 0.9989 | 1,201,129 | 1,801 | 2.0 | 1.0 | `resize: 1` |
| resize | 23 | 0.087 | 0.913 | 210,036 | 649 | 28.22 | 432.0 | `resize: 2` |
| alternate-screen | 222 | 0.0135 | 0.9865 | 332,684 | 558 | 2.51 | 0.0 | `resize: 1`, `alternate_screen_switch: 2` |
| input-echo | 3 | 0.3333 | 0.6667 | 16,623 | 43 | 14.33 | 0.0 | `resize: 1` |
