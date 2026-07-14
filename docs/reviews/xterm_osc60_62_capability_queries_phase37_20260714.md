# Phase 37 review — xterm OSC 60/61/62 capability queries — 2026-07-14

## Result

Implementation, compatibility review, two complete repository verifier passes
and final Computer Use acceptance are complete with no remaining finding.

## Baseline and scope

- Start SHA: `e860728f150f`.
- Branch: `codex/osc60-62-xterm-capabilities-phase37-20260714`.
- Promoted: read-only xterm XTQALLOWED, XTQDISALLOWED and XTQALLOWABLE
  reporting through OSC 60, 61 and 62 in Xterm256 sessions.
- Retained boundary: the queries can only report terminal-owned fixed names and
  effective policy booleans. They cannot grant authority, mutate product state,
  read clipboard content or introduce a frame/event/protobuf schema.

## Official comparison and implementation decisions

The implementation was compared with the
[official xterm Patch #410 control-sequence reference](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html)
and the corresponding source archive dated 2026-04-19. The reference report
functions are `report_allowed_ops`, `report_disallowed_ops` and
`report_allowable_ops` in `misc.c`; the category and operation tables are in
`charproc.c`.

Ianvs preserves the canonical table names and order, accepts xterm's
`allowWinOps` compatibility name as well as `allowWindowOps`, matches category
names without ASCII case sensitivity, and mirrors the request's BEL/ST
terminator. OSC 60 maps the top-level list conservatively onto categories that
are wholly enabled. OSC 61 exposes only implemented exceptions plus effective
clipboard parser policy. OSC 62 reports xterm's current allowable name tables
without claiming that every named operation is enabled. A selection exception
only means that an OSC 52 request can reach product policy; it does not bypass
the application's deny/prompt decision.

Unlike xterm's permissive dispatcher, Ianvs accepts only the exact query
shapes. Missing, unknown, extra and reply-shaped forms remain silent. This is a
deliberate loop-suppression boundary for echoed PTY traffic.

## Findings repaired during implementation and review

1. OSC 60/61/62 previously entered the generic custom-protocol class and ended
   as bounded no-ops. Exact handlers now return terminal-owned replies while
   retaining the existing 4 KiB ingress and response budgets.
2. The first capability interpretation treated partially implemented
   mouse/window categories as top-level OSC 60 allowances and treated OSC 61
   as the inverse of current parent state. Review aligned it with xterm's parent
   switch plus fallback-deny-list model and kept partial categories absent from
   OSC 60.
3. A reply-shaped request could otherwise be mistaken for another query by a
   loose dispatcher. Exact parameter counts, known category matching and silent
   rejection prevent response loops.
4. Window review initially omitted `SetWinSizeChars` from OSC 61, but the
   current parser does not execute `CSI 8;rows;cols t` as an xterm character-size
   request. It is now correctly reported as denied. Pixel/character size
   queries, title-stack push/pop and rectangular checksum remain the only fixed
   window exceptions; selection requests continue to follow effective
   ClipboardRead/ClipboardWrite parser policy, including the legacy
   insecure-sequence switch, without granting the eventual host action.
5. The initial macOS real-PTY test launched its Python child through a heredoc,
   replacing stdin and removing the TTY needed by `termios`. The permanent test
   now uses `python3 -c`, performs an exact child-side byte comparison, and
   proves continued input after the replies.
6. The first complete verifier pass exposed a product-test lifecycle race: the
   Python child exited immediately after its continued-input marker, allowing
   session cleanup to clear the final frame before the assertion observed it.
   The child now remains alive for one second after that marker, matching the
   established real-PTY harness pattern and preserving the evidence frame.

## Targeted evidence

- Shared corpus: 42 cases / 75 required edge classes.
- Semantic probes: 34 intents.
- Vendored Rust: exact category tables, current policy, compatibility alias and
  case, BEL/ST, every-byte fragmentation, malformed/unknown/reply-loop forms,
  overflow recovery and custom-protocol denial.
- Native core: exact mixed-terminator replies over a real PTY, no response
  replay after resize, continued input and VT220 silence.
- Flutter: mirrored corpus validation plus a macOS `testWidgets` real child
  that compares all reply bytes and remains interactive.

## Final acceptance

- `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1
  tools/verify_flutter_terminal.sh` passed twice consecutively with exit code
  0 after the final implementation/test fix. Each pass covered strict format,
  Clippy and analysis; 1,713 vendored tests (1,712 passed, one existing
  ignored), 12 Rust doc tests (11 passed, one existing ignored), 102 native
  core unit tests, 505 native session tests, three vttest cases, 22 PTY tests,
  482 terminal-package tests with the existing skip, seven documentation
  contract tests, 954 example grouped tests, 130 Widget tests, four macOS smoke
  tests, 41 product real-PTY tests and 15 RunnerTests.
- The accepted standalone executable was
  `example/build/macos/Build/Products/Debug/Ianvs Terminal Dev.app/Contents/MacOS/Ianvs Terminal Dev`
  with SHA-256
  `dcf3b72b909e224895dcfcffce6b3b6c16e5d56f0f0c9122c7c893f971970240`.
- Final Computer Use cold-launched that exact build and ran a real Python child
  in Local Shell. The child sent mixed ST/BEL OSC 60/61/62 queries, compared
  the full returned byte stream and visibly printed `CU37-OSC60-62:PASS`.
  `CU37-AFTER:continued` and a subsequent zsh command/output pair,
  `CU37-SHELL-AFTER`, proved that input returned to the same shell. The
  confirmed Quit action then left both matching bundle records with
  `isRunning:false`.
- Two earlier long inline Computer Use setup strings were excluded from
  acceptance after the input automation dropped punctuation. The counted run
  used the same temporary probe through a short path; the probe was removed
  after acceptance. Neither excluded setup reached the OSC assertions.

## Compatibility and rollback

- No frame, event, FFI, JSON or protobuf schema changes. Replies flow directly
  to the originating child PTY.
- Unknown/malformed forms remain bounded no-ops. VT220 and a denied
  CustomProtocol capability remain silent.
- The allowable tables follow xterm Patch #410. Ianvs policy reporting is
  conservative and does not promise unsupported host-window, font, termcap,
  locator or highlight operations.
- Rollback: revert the Phase 37 implementation commit; OSC 60/61/62 return to
  their previous bounded custom-protocol no-op behavior.
