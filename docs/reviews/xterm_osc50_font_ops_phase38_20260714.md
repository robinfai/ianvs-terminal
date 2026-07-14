# Phase 38 review — xterm OSC 50 font operations — 2026-07-14

## Result

Accepted. Implementation, targeted compatibility review, two consecutive full
repository verifier runs and final cold-launch Computer Use acceptance are
complete with no open finding.

## Baseline and scope

- Start SHA: `5a64c0b878ce`.
- Branch: `codex/osc50-xterm-font-ops-phase38-20260714`.
- Promoted: xterm OSC 50 session-local TrueType family set/query in Xterm256
  sessions, including absolute/relative menu expressions and BEL/ST replies.
- Retained boundary: terminal output can change only the live family. It cannot
  persist a profile, change size/line height/fallbacks or authorize a host
  action.

## Official comparison and implementation decisions

The implementation was compared with the
[official xterm Patch #410 control-sequence reference](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html)
and the matching 2026-04-19 source. Ianvs mirrors `QueryFontRequest`,
`ChangeFontRequest`, `ParseShiftedFont`, `lookupRelativeFontSize` and the
TrueType `setFaceName` path. It validates xterm's eight menu indices and uses
the default face-size ordering, but deliberately does not invent the reference
terminal's configurable X resource bitmap menu.

The current profile family seeds the terminal. The frame carries only the
effective family, while Flutter retains profile-owned fallback, size and line
height. This makes the terminal protocol additive and keeps product settings
ownership explicit.

## Findings repaired during implementation and review

1. OSC 50 previously entered the generic custom-protocol path as a bounded
   no-op even though OSC 61/62 already reported xterm's font-operation names.
   It is now classified under Appearance and dispatched to an exact handler.
2. The native terminal previously had no font presentation state. The current
   family now survives RIS and snapshots; session resize reconstruction
   re-seeds its separately held profile and transcript replay restores OSC 50.
3. A parser-only implementation would not reach the renderer. Optional JSON
   `font_family` and protobuf tag 33 now cross the frame boundary, force a
   snapshot on change and invalidate Flutter glyph/cell metric caches.
4. Font-family wire input needed a stricter boundary than the 4 KiB OSC
   envelope. Native set/query state and Dart decoding now require non-empty,
   control-free UTF-8 of at most 256 bytes.
5. OSC 60 still omitted `allowFontOps` after the operation became real. The
   top-level category now follows Appearance policy while OSC 61 retains the
   official fallback-deny model.
6. The first full verifier exposed an existing snapshot-shape-dependent wide-
   grapheme assertion: a padded empty viewport row was treated as a second
   logical content row. The assertion now ignores only empty logical rows; the
   effective `A🇺🇸B` content and wrap/cursor checks remain exact. It passed three
   immediate repeats and both subsequent full verifier runs.

## Targeted evidence

- Shared corpus: 43 cases / 75 required edge classes.
- Semantic probes: 35 intents.
- Vendored Rust: plain/indexed/relative set/query, semicolon families, exact
  BEL/ST, invalid index, 256-byte/control bounds, every-byte fragmentation,
  Appearance denial, RIS and snapshot restore.
- Native core: real-PTY exact reply, JSON/protobuf family, resize replay,
  continued input and VT220 silence.
- Flutter: JSON/protobuf optional-field parity and invalid-value rejection,
  delta retain/replace semantics, and a Widget test proving that the render
  object receives the OSC family while preserving profile fallback/size/line
  height.

## Full repository verification

`VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1
tools/verify_flutter_terminal.sh` passed twice consecutively after the final
test repair. Each run covered:

- 1,719 passed / 1 ignored vendored Rust tests; native core 102/102, shared
  corpus 1/1, session 507/507 and vttest 3/3;
- PTY 22/22; Flutter terminal package 485 passed / 1 skipped; docs 7/7;
- example grouped 954/954 and Widget 130/130;
- macOS smoke 4/4, product real-PTY 42/42 and RunnerTests 15/15;
- strict Rust Clippy, Dart/Flutter analysis, benchmark smoke, Debug app build,
  protobuf regeneration and clean `git diff --check`.

## Computer Use acceptance

Computer Use cold-launched the exact verifier-built standalone app. Its
executable SHA-256 was
`56a2b62892ca247adb088113f6e83b7ad4a49be13dd3edffb88e6dd658c0a372`.
A real Python child first displayed a baseline glyph sample, then changed the
family to Menlo, queried OSC 50 with ST and visibly reported:

- `CU38-OSC50:PASS`;
- `CU38-REPLY:b'\x1b]50;Menlo\x1b\\'`;
- `CU38-AFTER:continued` and `CU38SHELLAFTER` from the same interactive zsh.

The initial long probe path lost underscore characters in Computer Use's
keyboard injection and failed before the probe started; a punctuation-safe
short path was retried in the same cold launch. The confirmed Quit action then
closed the application, and the matching process check was empty.

## Compatibility and rollback

- JSON is additive and protobuf tag 33 is new; legacy frames keep the profile
  family. Existing tags and meanings are unchanged.
- Unsupported/malformed forms remain bounded no-ops. Query replies contain
  only terminal-owned bounded font state.
- Rollback: revert the Phase 38 implementation commit; OSC 50 returns to its
  prior bounded no-op and `allowFontOps` disappears from OSC 60.
