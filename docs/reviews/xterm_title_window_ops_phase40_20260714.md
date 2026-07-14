# Phase 40 review — xterm title window operations — 2026-07-14

## Result

Implementation, automated review and final acceptance are complete. Two
consecutive full repository verifier runs and a cold-launch Computer Use pass
against the exact verifier-built app all passed.

## Baseline and scope

- Start SHA: `935e51101978df34125d6c884bdbbe820b290e7f`.
- Final base: latest `origin/main`
  `9443d2bc591c3c177396db7e5d3cf5088b9f902f`; the Phase 40 commit rebased
  cleanly after the upstream zsh-history PTY repair.
- Branch: `codex/xterm-title-window-ops-phase40-20260714`.
- Promoted: CSI 20/21 `t` icon/window reports; CSI 22/23 `t` selector-aware
  implicit/direct title stack; XTSMTITLE/XTRMTITLE modes 0–3.
- Retained boundary: Xterm256 terminal-local appearance and bounded PTY
  replies only. VT220 and Appearance denial remain silent.

## Official comparison and implementation decisions

The implementation was compared with the
[official xterm Patch #410 control-sequence reference](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html)
and matching 2026-04-19 `charproc.c`/`misc.c` implementation. Ianvs follows the
exact OSC L/l ST reply forms, uppercase hexadecimal query encoding, strict
hexadecimal setter decoding, selector values 0/1/2, direct positions 1–10 and
xterm's older-entry fallback for partially saved stack entries.

The terminal already stores UTF-8 titles, so modes 2/3 retain the explicit
UTF-8 state without adding a locale-dependent legacy conversion. Modes are
changed with explicit `Pm` values, matching the promoted grammar.

## Findings repaired during implementation and review

1. CSI 20/21 previously emitted no title reply; they now report independent
   terminal-owned channels with ST and optional uppercase hexadecimal data.
2. The icon label lived in a native observer while the window title lived in
   the vendored terminal. Both channels now share the terminal state machine,
   ingress sanitizer, snapshot lifecycle and frame export path.
3. CSI 22/23 previously used one 32-item `Vec<String>` for window titles only.
   It is now a bounded ten-slot structure with independent optional icon/window
   values, selector-aware restore, partial fallback and reusable direct slots.
4. XTSMTITLE/XTRMTITLE modes were routed as scroll operations or ignored. The
   CSI dispatcher now separates `CSI > ... t/T`, applies explicit modes 0–3
   and gates them through Appearance.
5. Review expanded direct-slot testing from only the upper bound to every
   position 1–10 and added invalid selector/index, implicit overflow, policy,
   RIS and snapshot assertions.
6. The first native real-PTY fixture used a Python heredoc, which replaced the
   child's PTY stdin. It now passes the script as `python3 -c` data, preserving
   the PTY and proving eight exact child-side replies.

## Targeted evidence

- Vendored Rust: 1,734 tests discovered after this phase; targeted title
  query/mode/stack tests pass, including every-byte query parsing, all direct
  slots, partial fallback, bounds, denial, RIS and snapshot restore.
- Shared corpus: 45 cases / 85 required edge classes; native and Dart mirrors
  pass. Semantic probes: 37 intents.
- Native real PTY: eight exact raw/hex/restored/direct replies, final frame
  state, resize, continued input and VT220 TIMEOUT all pass.
- Dart analysis: modified integration and corpus tests report no diagnostics.
- macOS application real PTY: child-side exact comparison reports PASS; frame
  and pane both retain `Direct;both`; continued input passes.
- A native full run passed all changed/new protocol tests. Two unrelated
  timing-sensitive tests failed once under full parallel load, then each passed
  individually and in three further consecutive repetitions; the final full
  verifier remains the acceptance authority.

## Final verification

- `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1
  tools/verify_flutter_terminal.sh` passed twice consecutively on 2026-07-14
  (Asia/Shanghai), both with exit code 0 and no source change between runs.
- Each run passed vendored Rust 1,733/1,734 with the existing one ignored;
  native unit 104/104, corpus 1/1, session 512/512 and vttest 3/3; ianvs_pty
  22/22; terminal 485 passed with one skipped; documentation 7/7; example
  grouped 954/954 and Widget 130/130; macOS smoke 4/4; application real PTY
  44/44; and RunnerTests 15/15. Rust formatting/strict Clippy plus Dart/Flutter
  analysis also passed.
- Exact standalone app:
  `example/build/macos/Build/Products/Debug/Ianvs Terminal Dev.app`.
  Executable SHA-256:
  `d8fdf23501a1beabe3ecb1eb2d96b837112c615e9cb312693f52334ebc91e8a5`.
- Computer Use cold-launched that exact stopped build. A real child compared
  eight exact raw, uppercase-hex, implicit-restore and direct-slot reply byte
  strings before visibly printing `CU40-FINAL-EXACT:PASS`. The native window
  and accessible tab both displayed `CU40 FINAL`.
- `CU40-FINAL-AFTER:continued` and `CU40FINALSHELL` proved that input returned to the
  same real zsh session. The user-authorized Quit confirmation completed and a
  subsequent process check found no matching application process.
- The first Computer Use probe attempts exposed only probe-driver quoting and
  XTSMTITLE/XTRMTITLE case-direction mistakes. They returned safely to zsh;
  correcting the ephemeral probe to the already documented grammar produced
  the successful evidence above without a product-code change.

## Compatibility and rollback

- No JSON, protobuf, FFI, configuration or persistence schema changes.
- Valid OSC 0/1/2/l/L setter behavior is preserved while icon ownership moves
  from the native observer into the terminal. Existing pane-title precedence
  is unchanged.
- Malformed/unsupported selectors, positions, modes and hexadecimal text are
  bounded no-ops; denied queries remain silent.
- Rollback: revert the Phase 40 implementation commit. CSI title queries and
  modes return to no-op/scroll routing and CSI 22/23 return to the prior
  window-title-only 32-item stack.
