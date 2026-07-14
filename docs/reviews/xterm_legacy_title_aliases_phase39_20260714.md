# Phase 39 review — xterm legacy title aliases — 2026-07-14

## Result

Accepted. Implementation, targeted compatibility review, two consecutive full
repository verifier runs and final cold-launch Computer Use acceptance are
complete with no open finding.

## Baseline and scope

- Start SHA: `f2d91e07ea342cc24a323b0d2c05eab1ed2317d8`.
- Branch: `codex/osc-legacy-title-aliases-phase39-20260714`.
- Promoted: xterm/Sun/CDE `OSC l text` window-title and `OSC L text`
  icon-label aliases in Xterm256 sessions.
- Repaired in the same semantic family: OSC 0 now updates both the window title
  and icon label, and numeric/legacy window titles preserve semicolons.
- Retained boundary: terminal output changes only bounded session appearance.
  It cannot persist profile names, trigger a host action, or bypass VT220 and
  Appearance policy.

## Official comparison and implementation decisions

The implementation was compared with the
[official xterm Patch #410 control-sequence reference](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html)
and matching 2026-04-19 `misc.c`. The aliases are command bytes followed
directly by text; a semicolon is content, not a delimiter. OSC 0 is the combined
window-and-icon title operation.

Ianvs reuses the existing window-title state/event and native icon-label frame
state. It does not add a new frame field, product permission, persistence path
or response. CSI title-report and separate icon/title-stack window operations
remain independently reviewable scope.

## Findings repaired during implementation and review

1. The streaming gate previously waited for `;`, classified complete aliases
   as Custom, and discarded long aliases after 64 command bytes. It now
   recognizes `l/L` from byte one, treats all later bytes as a 4 KiB Appearance
   payload, and recovers after oversize input.
2. VTE splits OSC parameters at semicolons. The old OSC 0/2 handler consumed
   only the first text part. Numeric and lowercase-`l` title paths now rejoin
   every part exactly before UTF-8/control/scalar sanitization.
3. The vendored parser had no icon state, so uppercase `L` could not reach the
   existing `window_icon_name` frame. The filtered native observer now consumes
   `L` while the parser safely accepts it without mutating window-title state.
4. The native observer treated only OSC 1 as an icon update and accepted its
   text without the title channel's control/scalar sanitation. OSC 0/1/L now
   share UTF-8, control removal and 1,024-scalar bounds; invalid UTF-8 preserves
   prior state and an empty accepted label clears it.
5. A parser-only result would not prove product behavior. Native and macOS
   application real-PTY tests stage OSC 0 first, then independent `l/L`, assert
   JSON/protobuf and pane-title precedence, resize, continued input and VT220
   denial.

## Targeted evidence

- Shared corpus: 44 cases / 78 required edge classes.
- Semantic probes: 36 intents.
- Vendored Rust: BEL/ST, every-byte fragmentation, split UTF-8, semicolons,
  numeric title preservation, icon/title independence, Appearance denial and
  exact 4 KiB overflow recovery.
- Native core: OSC 0 dual update, lowercase/uppercase aliases, UTF-8/control/
  scalar bounds, invalid/empty behavior, filtered-policy/overflow gates,
  JSON/protobuf parity, real PTY, resize, continued input and VT220 denial.
- Flutter product: mirrored corpus, zero-warning static analysis and a macOS
  application real-PTY test proving both frame channels and pane-title priority.

## Final verification

`VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1
tools/verify_flutter_terminal.sh` passed twice consecutively after the final
implementation and protocol-document changes; only this final evidence record
was completed afterward. Both runs returned exit code 0 and covered:

- 1,723 passed / 1 existing ignored vendored Rust tests plus 11 passed / 1
  ignored doc tests; native core 103/103, shared corpus 1/1, session 509/509 and
  vttest 3/3;
- PTY 22/22; Flutter terminal package 485 passed / 1 skipped; docs 7/7;
- example grouped 954/954 and Widget 130/130;
- macOS smoke 4/4, product real PTY 43/43, Debug app build and RunnerTests
  15/15;
- strict Rust Clippy, Dart/Flutter analysis, benchmark smoke, protobuf
  regeneration and clean `git diff --check`.

Computer Use cold-launched the exact verifier-built standalone app. Its
executable SHA-256 was
`7db570c18bc5f99a5e0f4abce9f26cb40c08319d0984cae53a08bdf854d0f6e8`.
A real Python child visibly proved three independent stages:

- OSC 0 changed both the window and tab to `CU39 BOTH` while showing
  `CU39-OSC0-READY`;
- an empty lowercase `l` cleared the window title, then uppercase `L` made the
  product's icon-label fallback visibly show `CU39 ICON` with
  `CU39-ICON-READY`;
- lowercase `l` set and preserved the semicolon title `CU39;WINDOW`, followed
  by `CU39-WINDOW-READY`, `CU39-AFTER:continued`, and `CU39SHELLAFTER` after
  returning to the same interactive zsh.

The user-authorized Quit confirmation closed the active shell and application;
Computer Use reported both matching app records stopped and the exact process
check was empty.

## Compatibility and rollback

- No JSON, protobuf, FFI, configuration or persistence schema changes.
- Unsupported/malformed input remains a bounded no-op; valid setters never
  reply or grant host authority.
- Rollback: revert the Phase 39 implementation commit. The aliases return to a
  bounded no-op, OSC 0 returns to window-title-only product state, and numeric
  semicolon truncation returns.
