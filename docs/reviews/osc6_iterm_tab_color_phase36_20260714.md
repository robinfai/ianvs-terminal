# Phase 36 review — iTerm2 OSC 6 tab color — 2026-07-14

## Result

Accepted with no remaining Phase 36 finding. Implementation, targeted tests,
two full repository verifier passes, macOS real-PTY application coverage and a
cold-launch Computer Use gate all passed on the reviewed tree.

## Baseline and scope

- Start SHA: `07de5c6ca649a91a9e7d2c2663ba5fb1fad05f9a`.
- Branch: `codex/osc6-iterm-tab-color-phase36-20260714`.
- Promoted: exact incremental red, green and blue tab-color components plus the
  exact `bg;*;default` profile restoration action.
- Retained boundary: session-local appearance only; no reply, persistence,
  disclosure, clipboard, filesystem, network, focus, notification or other
  host authority.

## Official comparison and implementation decisions

The implementation was compared with iTerm2's current escape-code docs and
source revision `7c0361f5afe234bfa255ce486065eb964c7ca01a`. The source applies
one RGB component at a time, retains the other current components, starts from
black when no tab color exists, and routes the default action back to the saved
profile settings.

Ianvs therefore uses its existing session tab-color frame state rather than
adding a second product concept. The native profile's `special.tab` value is
now installed as the reset baseline. Exact iTerm2 payloads take the incremental
path; all other OSC 6 payloads retain the existing xterm attribute-mode path.

## Findings repaired during implementation and review

1. The parser previously treated every OSC 6 payload as xterm attribute-color
   modes, so documented iTerm2 component requests had no product effect. The
   exact `6;1;bg` namespace now composes bounded RGB state without changing the
   xterm grammar.
2. Dart already serialized the profile tab color, but native profile setup did
   not install it. The reset baseline now crosses config into the terminal, so
   OSC reset and RIS restore the user's profile color rather than always
   removing the runtime value.
3. Reset initially compared the post-reset value with itself and could miss the
   repaint. Review captures the prior color before restoration and invalidates
   the frame only when the visible value actually changes.
4. The first mirrored Dart corpus assertions accidentally used a literal
   backslash before `x1b`. The fixture contract test exposed the mismatch; the
   assertion now checks actual escape bytes.
5. VT220 real-PTY coverage proved profile preservation indirectly. Review added
   a direct Appearance-capability regression so policy denial is explicit at
   the streaming parser boundary.

## Targeted evidence

- Shared corpus: 41 cases / 70 required edge classes.
- Semantic probes: 33 intents.
- Vendored Rust: incremental components, mixed terminators, every-byte input,
  malformed forms, snapshot/RIS, reset, xterm coexistence and policy denial.
- Native core: shared corpus, profile baseline, frame JSON/protobuf parity,
  real-PTY resize replay, continued input and VT220 denial.
- Flutter: mirrored corpus and incremental/profile-reset widget color checks.
- macOS application integration: a real child emits three components plus a
  malformed value, reaches `#ff8040`, accepts continued input, and resets to the
  profile's `#102030`.

## Final acceptance

- `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1
  tools/verify_flutter_terminal.sh` completed twice with exit code 0. Each pass
  included 1,704 vendored Rust unit tests (1 existing ignored), 11 Rust
  documentation tests (1 existing ignored), 102 native-core unit tests, the
  shared corpus test, 503 native real-session tests, three vttest regressions,
  Dart/Flutter analysis and package/widget suites, four macOS smoke tests, 40
  application real-PTY tests, and 15 Runner tests. Example grouped tests passed
  954/954 and the focused Widget suite passed 130/130.
- Vendored and native Clippy passed with warnings denied. The current native
  manifest defines no `python` feature, so the obsolete optional-feature command
  is not an applicable gate. Both package and example Flutter analyses passed
  with fatal infos enabled.
- The verifier-built executable SHA-256 was
  `c583c57b725177a85bd5c14fd544119424526742dbf982d39105ea6ea2daa0e1`.
- Computer Use cold-launched that exact standalone app into a real zsh child at
  93 by 21 cells. A Python child emitted red 255, green 128 and blue 64 plus an
  invalid red 999 request. `CU36-SET-FF8040` appeared with a visible orange tab
  color bar; the malformed value left it intact. After `continued`, exact
  default removed the bar and printed `CU36-RESET:continued`; the returned zsh
  then printed `CU36AFTER`. The Quit confirmation was accepted under the user's
  explicit exit authorization, both matching app instances reported stopped,
  and the temporary probe was removed.

## Compatibility and rollback

- No frame or protobuf schema changes: the existing optional `tab_color` field
  carries both OSC 1337 SetColors and OSC 6 incremental state.
- Missing profile tab color keeps the previous no-color default. Existing
  xterm OSC 6 and OSC 106 attribute-mode semantics remain unchanged.
- Rollback: revert the Phase 36 implementation commit; iTerm2 OSC 6 returns to
  a bounded no-op under xterm mode parsing while existing OSC 1337 tab colors
  and xterm special-color modes remain available.
