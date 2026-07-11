# Terminal cursor overlay A/B decision

## Decision

NO-GO. The terminal cursor overlay and its production experiment seam were removed. A historical formal run had produced a GO result, but two fresh runs of the unchanged frozen gate on the final candidate both failed the total-span threshold. The optimization therefore does not have stable end-to-end evidence and must not remain enabled or dormant in production.

## Frozen gate and tests

- Gate implementation SHA-256: `912f1c6b6c9b8a8e05e1cb042c6d99b10fbc802e0b395dbea421123ec9a1513e`
- Gate test SHA-256: `40c3312ee8aba848f22c127bb0dd1218319ff6ac6fc8ef23e336b8bb720a843d`
- Correctness preflight passed in both final-candidate A/B runs.
- The gate implementation, thresholds, and tests were not changed to obtain this decision.

The hashes were checked before and after the final-candidate runs.

## Final-candidate A/B evidence

Both runs used five surface repeats and five overlay repeats with 24 observed blink transitions per repeat.

The historical candidate command, run from the repository root before the experiment seam was removed, was:

```sh
dart run tools/bench/runner/flutter_profile_matrix_runner.dart \
  --device macos \
  --output <output-root> \
  --workloads cursor_blink_idle_surface_profile,cursor_blink_idle_overlay_profile \
  --repeats 5 \
  --frame-count 24 \
  --require-target-count 1
```

The runner's package cursor/graphics, example cursor, and exact IME-across-blink correctness preflights all passed before each profile. The actual target label was `macos-darwin`. The raw output roots were `/tmp/ianvs-cursor-overlay-eac57d2.YYGWIn` and `/tmp/ianvs-cursor-overlay-eac57d2-rerun.9Jukz0`.

| Run | Total-span p95 ratio | Missed vsync, surface / overlay | Decision |
|---|---:|---:|---|
| 1 | 1.6786461 | 0 / 1 | NO-GO: total-span regression and missed-vsync regression |
| 2 | 1.9833154 | 1 / 1 | NO-GO: total-span regression |

The frozen total-span limit is `<= 1.05`. Cursor paint, build, raster, layer count, live picture count, paint bounds, estimated picture memory, and viewport correctness all passed, but those local improvements do not override the failed end-to-end threshold. The checked-in machine-readable result is the second run: [`cursor_overlay_gate.json`](cursor_overlay_gate.json).

| Frozen threshold | Limit | Final rerun observation |
|---|---:|---:|
| Repeats per variant | `>= 5` | `5 / 5` |
| Blink transitions per repeat | `>= 20` | `24 / 24` minimum |
| Cursor paint p95 ratio | `<= 0.8` | `0.1054945` |
| Build p95 ratio | `<= 1.05` | `0.4603313` |
| Raster p95 ratio | `<= 1.05` | `1.0` |
| Total-span p95 ratio | `<= 1.05` | `1.9833154` |
| Additional overlay layers | `<= 1` | `1` |
| Live cursor pictures | `<= 1` | `1` |
| Cursor paint bounds | `<= 2 cells` | `187 px2`, no violations |
| Estimated cursor picture memory | `<= 5984 bytes` | `2992 bytes`, no violations |

## Sampling audit

The A/B artifact audit found 24 render events but 25 frame-timing events per repeat. The integration test was still collecting the settling pump after the intended trace window. Removing that 25th timing from both completed data sets did not change either NO-GO outcome.

The profile test now snapshots frame timings immediately after the measured action, before the 500 ms settling interval and final pump. A surface-only confirmation run then produced exactly 24 blink transitions, 24 surface repaint events, and 24 frame-timing events, with a matching viewport hash and no cursor-overlay paints:

```sh
dart run tools/bench/runner/flutter_profile_matrix_runner.dart \
  --output /tmp/ianvs-cursor-surface-nogo.SnXLjN \
  --workloads cursor_blink_idle_profile \
  --repeats 1 \
  --frame-count 24 \
  --device macos \
  --require-target-count 1
```

- Artifact: `/tmp/ianvs-cursor-surface-nogo.SnXLjN/macos-darwin/cursor_blink_idle_profile/repeat_1`
- Workload: `cursor_blink_idle_profile`
- Viewport hash: `53962855` / `53962855`
- Missed vsync: `0`

## Production outcome

- Removed the cursor overlay render object.
- Removed `TerminalCursorExperimentScope` and
  `TerminalCursorExperimentMode` from production code.
- Restored the surface-rendered cursor path while preserving later terminal coordination changes.
- Kept the report and frozen gate implementation as historical evidence of why the optimization was rejected.

Reopening this optimization requires a newly frozen experiment with strict timing-window ownership, interleaved or ABBA variant ordering to reduce fixed-order bias, and enough frame-phase detail to explain total-span variance before any production seam is reintroduced.
