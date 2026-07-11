# OSC protocol preflight — 2026-07-11

- Baseline and starting SHA: `7635bac099dd6121af1405562ff42db933379b1c`
- Branch at review start: `main`
- User work preserved: untracked `docs/audits/.DS_Store`
- Primary parser: `native/vendor/par-term-emu-core-rust/src/terminal/sequences/osc/`
- Session/frame bridge: `native/core/src/session.rs`, `native/core/src/model.rs`
- Wire schemas: `native/core/proto/frame_diff.proto`, generated Rust and Dart bindings
- Dart/runtime/UI: `packages/ianvs_terminal/lib/src/terminal/`

## Review findings

| Review claim | Result | Evidence |
|---|---|---|
| OSC 21 mutates title stack | confirmed defect | dispatcher routed `21` to `handle_osc_title` |
| OSC 22 pops title stack | confirmed defect | dispatcher routed `22` to `handle_osc_title` |
| OSC 8 loses `id=` | confirmed compatibility gap | parser deduplicated only by URI; frame schema carried only URI |
| OSC 110/111/112 reset to hard-coded colors | confirmed defect | reset arms assigned fixed RGB values |
| OSC 4/104 supports only 0–15 | confirmed compatibility gap | palette storage is `[Color; 16]` |
| OSC 133 recovery is incomplete | implemented but incomplete | A–D exists with zone events; broader malformed-order corpus remains deferred |
| OSC 633 absent | confirmed compatibility gap | no dispatcher/adapter exists |
| OSC 9;9 absent | confirmed compatibility gap | OSC 9 handles notifications/progress only |
| OSC 934 is private | documented private extension | implementation is Ianvs/par-term-specific |

The first repair pass addresses the confirmed side effects, OSC 8 identity loss,
and dynamic-color baseline reset. Larger protocol additions remain explicit in
the support matrix rather than being advertised as implemented.
