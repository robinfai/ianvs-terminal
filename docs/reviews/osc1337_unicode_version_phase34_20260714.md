# Phase 34 review — OSC 1337 UnicodeVersion — 2026-07-14

## Result

Accepted with no remaining Phase 34 finding. Implementation, targeted tests,
the final full repository verifier, macOS real-PTY application coverage and a
cold-launch Computer Use gate all passed on the reviewed tree.

## Baseline and scope

- Start SHA: `8c1117ded801bc61fc21ec3aaf2651afc4dc3c65`.
- Branch: `codex/osc1337-unicode-version-phase34-20260714`.
- Promoted: exact Unicode versions 8 and 9, unlabeled/labeled push/pop, actual
  width-table behavior, saved cursor, snapshots, RIS and resize replay.
- Retained boundary: no reply, host action, disclosure, file/clipboard access,
  external UI, profile persistence, or new frame schema.

## Official comparison and implementation decisions

The implementation was compared with iTerm2's current escape-code docs and
source. iTerm2 exposes only versions 8 and 9, stores optional labels with the
current version, pops through newer entries to a match, and leaves the current
version unchanged after a missing-label pop empties the stack. Saved cursor
state includes the version.

Ianvs uses the official Unicode 8 W/F/A tables and the current generated table
for Unicode 9+, matching iTerm2's modern compatibility path. Existing private-
use one-cell behavior remains an explicit Nerd Font/Powerline product override.
Labels are restricted to 128 printable ASCII bytes and the stack to 64 entries.

## Findings repaired during implementation

1. The pre-existing `UnicodeVersion` enum was inert: `char_width` ignored it.
   Width selection now changes real cells, spacers, wrapping and cursor columns.
2. Grapheme handling originally forced flags and ZWJ emoji to two cells under
   every version. Unicode 8 now uses the base-character width unless an explicit
   emoji-presentation sequence forces two cells.
3. The dependency's CJK helper alone did not preserve the project's established
   Greek/Cyrillic ambiguous-width behavior. The explicit table remains the
   modern-mode front gate and the dependency covers newer entries, while
   Unicode 8 uses its complete versioned ambiguous table.
4. Protocol state initially had no saved-cursor, reset or replay ownership. The
   current version, bounded stack and saved version now round-trip through
   DECSC/DECRC and terminal snapshots; RIS and resize replay preserve the
   session-specific stack without reviving a cleared saved cursor.
5. Adding Unicode 8 made the optional Python enum conversion non-exhaustive.
   The binding now exposes and converts Unicode 8 explicitly.
6. The optional Python feature also exposed a pre-existing non-exhaustive
   observer conversion for nine newer product-routed terminal events. Those
   events now use one stable `unsupported` dictionary type without exposing
   payloads, backed by an exact redaction test, so future product-only events
   fail closed instead of breaking the optional build.

## Targeted evidence

- Shared corpus: 39 cases / 61 required edge classes.
- Semantic probes: 31 intents.
- Vendored Rust: 28 width tests, 4 protocol tests, snapshot and ingress-policy
  tests passed.
- Native core: shared corpus, xterm real-PTY style/cursor columns, labeled
  restoration, resize replay continuation and VT220 denial passed.
- Flutter: corpus mirror test, integration-test analysis and the macOS real-PTY
  U8/U9/U8-restored style-column plus resize/continued-input test passed.

## Final acceptance

- `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1
  tools/verify_flutter_terminal.sh` completed with exit code 0. This included
  1,700 vendored Rust unit tests, 11 Rust documentation tests, 101 native-core
  unit tests, the shared corpus test, 499 native real-session tests, three
  vttest regressions, Dart/Flutter analysis and package/widget tests, four
  macOS smoke tests, 38 application real-PTY tests, and 15 Runner tests. The
  ignored vendored unit/doc tests remained the existing one in each suite.
- The verifier-built executable SHA-256 was
  `a33651914f866f24b1e133e3d98f68bb61d73fef44c504051427977c6e44f45c`.
- With `PYO3_PYTHON=/usr/bin/python3`, `cargo check --all-targets --features
  python` and feature-aware Clippy passed, covering the optional Unicode 8 enum
  conversions and redacted unsupported-event test target. The crate's existing
  `pyo3/extension-module` mode does not link a standalone macOS Rust test binary
  to libpython, so execution remains a packaging-level Python-module concern.
- Computer Use cold-launched that app into a real zsh child at 93 by 21 cells.
  A child-executed probe rendered the Unicode 8 red marker one cell wide, the
  Unicode 9 blue marker two cells wide, and the labeled-pop green marker aligned
  again with Unicode 8. `CU34INPUTOK` then echoed through the same live session,
  shell integration remained active, and the app was quit with both bundle-ID
  instances confirmed stopped.
