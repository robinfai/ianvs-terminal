# Terminal cursor overlay A/B decision

## Decision

GO. The terminal cursor overlay is enabled by default because the frozen gate is eligible, all reason codes are empty, and the correctness preflight is bound to the same runner invocation that produced the profile data.

## Frozen gate and tests

- Gate implementation SHA-256: `912f1c6b6c9b8a8e05e1cb042c6d99b10fbc802e0b395dbea421123ec9a1513e`
- Gate test SHA-256: `40c3312ee8aba848f22c127bb0dd1218319ff6ac6fc8ef23e336b8bb720a843d`
- Fresh gate tests: 52/52 passed.
- Package and example static analysis: no issues.

The hashes were recorded before the formal A/B run and rechecked after it.

## Formal command

Run from the repository root on the `macos-darwin` profile target:

```sh
dart run tools/bench/runner/flutter_profile_matrix_runner.dart --device macos --output /tmp/ianvs-terminal-cursor-overlay-ab --workloads cursor_blink_idle_surface_profile,cursor_blink_idle_overlay_profile --repeats 5 --frame-count 24 --require-target-count 1
```

The runner executed these correctness suites sequentially before `flutter drive` and only then injected `IANVS_BENCH_CORRECTNESS_SUITES_PASSED=true`:

1. Package cursor and graphics tests: 27/27 passed.
2. Example cursor tests: 13/13 passed.
3. Exact IME composing-across-blink test: 1/1 passed.

The runner exited 0. Its dry-run mode is fail-closed and prints the profile command with `IANVS_BENCH_CORRECTNESS_SUITES_PASSED=false`.

## Artifact audit

- 10 correctness summaries: five surface and five overlay.
- 10/10 viewport comparisons matched; every reference and tested hash was `53962855`.
- 240 render events: 120 surface repaint events and 120 cursor overlay events.
- 250 frame timing events.
- Each repeat observed 24 blink transitions.

## Gate observations

| Observation | Result | Limit |
|---|---:|---:|
| Cursor paint p95 ratio | 0.0805369 | <= 0.8 |
| Build p95 ratio | 0.3048544 | <= 1.05 |
| Raster p95 ratio | 1.0 | <= 1.05 |
| Total span p95 ratio | 0.7141694 | <= 1.05 |
| Surface / overlay missed vsync | 0 / 0 | no regression |
| Additional overlay layers | 1 | <= 1 |
| Live cursor pictures | 1 | <= 1 |
| Maximum cursor paint bounds area | 187 px2 | <= two cells |
| Estimated cursor picture bytes | 2992 | <= 5984 |
| Bounds / memory violations | 0 / 0 | 0 |

The frozen machine-readable result is [`cursor_overlay_gate.json`](cursor_overlay_gate.json).
