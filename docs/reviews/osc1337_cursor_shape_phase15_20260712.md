# Phase 15 review — OSC 1337 dynamic cursor shape — 2026-07-12

## Outcome

- Start SHA: `4d0093e2f731cf8974e371a9dfbf13233f9506b0`.
- Implementation SHA: `66d477b`.
- Branch: `codex/osc1337-cursor-shape-20260712`.
- Scope: iTerm2 OSC 1337 CursorShape and the existing DECSCUSR dynamic style
  path; no host action or input authority.

## Findings and fixes

| Finding | Resolution |
|---|---|
| OSC 1337 CursorShape fell through to image handling | Added exact 0/1/2 parsing under the appearance capability |
| DECSCUSR changed native cursor state but the frame omitted style | Added optional cursor shape/blink JSON and protobuf fields |
| Flutter always rendered the static profile cursor | Resolve protocol fields independently over the profile fallback |
| A shape-only OSC must not seize blink ownership | Shape and blink have separate presence flags from parser through renderer |
| Cursor-only changes could be hidden by cell-focused tests | Added a no-visible-cell-damage real-PTY delta regression |
| DECSCUSR also changed warning-bell volume | Removed the unrelated side effect and locked it with a regression |

## Evidence before the repository-wide gate

- official iTerm2 and xterm grammars reviewed;
- exact/malformed OSC values, BEL/ST, every-byte split and appearance denial;
- DECSCUSR values, unknown no-op, alternate screen, RIS and bell independence;
- corpus 23 cases/30 required edge classes and semantic probes 19 intents;
- real-PTY OSC, CSI, cursor-only delta, VT220 and JSON/protobuf tests;
- missing-field and cursor-only Dart delta tests;
- Flutter shape precedence and steady-blink tests;
- macOS application real-PTY OSC beam to CSI steady-underline transition.

The repository-wide verifier passed with exit code 0: corpus 23/30, semantic
probes 19, vendored tests 1,638, native lib 75/75, native session 465/465,
example grouped 925/925, complete Widget 125/125, macOS smoke 4/4, real PTY
24/24 and native RunnerTests 12/12. The optional nightly resource benchmark was
not enabled.

After manual unlock, Computer Use exercised a cold-launched standalone Debug
build through a real PTY. A key-stepped probe froze and visibly confirmed the
thin vertical `P15-BEAM`, steady bottom-line `P15-UNDERLINE`, and both visible
and hidden phases of `P15-BLOCK`. It then printed `P15-PASS`; a subsequent
`echo P15-INTERACTIVE` returned normally and accessibility reported
`SHELL ACTIVE`. The earlier fixed-delay attempt was not used for underline
evidence because it advanced past that stage; the key-stepped repeat is the
acceptance run.

## Compatibility and rollback

JSON fields are optional and protobuf tags 4/5 are additive. Old consumers
ignore them; new consumers use profile behavior when they are absent. Existing
profile cursor settings remain authoritative until a child explicitly emits a
cursor protocol. Reverting the implementation commit returns OSC 1337
CursorShape to a bounded unsupported no-op and DECSCUSR to native-only state.
