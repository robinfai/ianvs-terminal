# Phase 18 review — OSC 133 semantic prompts and `aid` — 2026-07-13

## Result

The phase is accepted. Ianvs now implements the current iTerm2 OSC 133
`A/N/P`, `k=i/s/c/r`, and opaque `aid=` lifecycle contract through the vendor
parser, snapshot state, JSON/protobuf streaming, native callbacks, Dart typed
events, and product prompt navigation.

## Review and fixes

- Replaced exact `A/B/C/D` parameter positions with order-independent bounded
  attribute and positional parsing.
- Added non-mutating semantic-prompt events so secondary, continuation, and
  right prompts do not split command zones or create duplicate prompt marks.
- Added a 16-level snapshotted lifecycle stack with 256-byte opaque `aid`
  correlation. Unknown targets are ignored; an outer target cascades over
  inner lifecycles and reports `implicitClosedCount`.
- Preserved legacy integrations without `aid` and their conservative
  consecutive-`D` recovery behavior.
- During final review, fixed explicit duplicate `D;aid=<finished-child>` so it
  cannot accidentally trigger the legacy parent-pop heuristic.
- Added mirrored corpus/probe cases and additive wire fields:
  `promptKind`, `aid`, `parentAid`, `freshLine`, and
  `implicitClosedCount`.

## Evidence

- Official source comparison: current iTerm2 `VT100Terminal.m` and change
  `131b9c60`, reviewed 2026-07-13.
- Vendor: 1651 passed, 1 existing ignored; new OSC 133 tests include BEL/ST,
  every-byte split, prompt kinds, parameter order, invalid bounds, unknown and
  duplicate targets, nested cascade, snapshot, and RIS.
- Native: 77 unit tests, shared corpus, and 469 real-PTY/session tests passed;
  the OSC 133 real-PTY fixture asserts semantic and lifecycle metadata.
- Dart/Flutter: static analysis clean; package, example, renderer, real-PTY,
  and 925 example widget tests passed.
- macOS: Runner XCTest suite passed.
- Shared corpus: 26 cases and 37 required edge classes; semantic probe suite:
  21 intents.
- Computer Use final gate: launched the built `Ianvs Terminal Dev.app`,
  observed a healthy active shell-integration pane, injected the semantic OSC
  fixture, and confirmed subsequent interactive command/output with
  `CU_OSC133_GUI_OK` and a healthy prompt.

## Remaining broader OSC work

This phase closes modern OSC 133 semantic prompts. The broader ongoing OSC
goal still has independently deferred areas, including richer iTerm2 OSC 1337
host metadata/actions, the full Kitty notification surface, and binary/MIME
OSC 52 policy work.
