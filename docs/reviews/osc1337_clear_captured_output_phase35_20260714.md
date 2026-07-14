# Phase 35 review — OSC 1337 ClearCapturedOutput — 2026-07-14

## Result

Accepted with no remaining Phase 35 finding. Implementation, targeted tests,
two full repository verifier passes, macOS real-PTY application coverage and a
cold-launch Computer Use gate all passed on the reviewed tree.

## Baseline and scope

- Start SHA: `889c82f440549a4348916dcef92063f1c16651dc`.
- Branch: `codex/osc1337-clear-captured-output-phase35-20260714`.
- Promoted: the exact `OSC 1337;ClearCapturedOutput ST` command as a typed,
  immediate action against Ianvs's existing per-session Captured Output store.
- Retained boundary: no terminal-grid or scrollback mutation, reply, clipboard,
  filesystem, network, focus, notification, persistence, disclosure or other
  host authority.

## Official comparison and implementation decisions

The implementation was compared with iTerm2's current escape-code docs and
source. iTerm2 names the exact operation `ClearCapturedOutput`, dispatches it
through terminal/screen delegates, and notifies the owning session that its
captured-output product state changed. It is distinct from terminal-buffer and
scrollback clearing.

Ianvs therefore emits a payload-free parser event and adds the source marker
only at its trusted native bridge. The Dart runtime validates that marker and
the current session epoch; ShellScreen applies the action to entries carrying
the same session ID. The xterm-compatible facade consumes the event without
inventing a product store.

## Findings repaired during implementation

1. The parser had no representation for the documented command. Exact BEL/ST
   requests now emit one event; suffixed, parameterized and case variants are
   no-ops, and the grid/title remain unchanged.
2. Native and Dart layers had no session-safe route. The event now crosses the
   bridge with a fixed `iterm1337` source, remains bound to the current session
   epoch, and unknown sources fail closed.
3. Captured Output sheets originally owned a snapshot copied at open time. An
   externally triggered clear would have removed the backing entries while
   leaving stale rows visible. The open sheet is now keyed to its session and
   receives the authoritative empty collection immediately.
4. The initial product test proved only one-session clearing. Review expanded
   it to two split sessions: clearing the origin leaves the neighboring
   session's captured row available after switching panes.
5. Immediate events could not be allowed to replay with reconstructed frames.
   Real-PTY coverage now proves two exact wire sequences produce two events,
   malformed input produces none, and resize replay produces no historical
   clear; VT220 denies the family.

## Targeted evidence

- Shared corpus: 40 cases / 65 required edge classes.
- Semantic probes: 32 intents.
- Vendored Rust: exact BEL/ST, every-byte split, malformed variants,
  no-grid-mutation and Metadata-policy tests passed.
- Native core: shared corpus, trusted mapping, exact real-PTY count, resize
  non-replay and VT220 denial passed.
- Flutter: mirrored corpus, strict typed routing, invalid-source rejection,
  two-session widget isolation and open-sheet refresh passed.
- macOS application integration: a real child produced a captured row, emitted
  a malformed request followed by exact ST input, kept the open sheet visible
  in its empty state, preserved terminal rows and accepted continued input.

## Final acceptance

- `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1
  tools/verify_flutter_terminal.sh` completed twice with exit code 0. Each pass
  included 1,702 vendored Rust unit tests (1 existing ignored), 11 Rust
  documentation tests (1 existing ignored), 102 native-core unit tests, the
  shared corpus test, 501 native real-session tests, three vttest regressions,
  Dart/Flutter analysis and package/widget suites, four macOS smoke tests, 39
  application real-PTY tests, and 15 Runner tests.
- Vendored and native Clippy passed with warnings denied. With
  `PYO3_PYTHON=/usr/bin/python3`, the optional Python all-target check and
  feature-aware Clippy also passed.
- The verifier-built executable SHA-256 was
  `f27c86d5e0bb51e0e0f125ba65fa4c1bc59baee1f97a49b579ea99dbaa67cc62`.
- Computer Use cold-launched that executable into a real zsh child at 93 by 21
  cells. The Output tool first exposed nine captured rows; a delayed child
  emitted exact BEL-terminated `ClearCapturedOutput`, the open sheet changed to
  `0 captured lines` and its guided empty state, and the same child then printed
  `CU35-CLEAR-DONE` and `CU35-AFTER:continued`. Both app instances were
  confirmed stopped, and the temporary profile rule and probe files were
  removed after acceptance.
