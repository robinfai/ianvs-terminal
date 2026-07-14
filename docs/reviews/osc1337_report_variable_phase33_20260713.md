# Phase 33 review — OSC 1337 ReportVariable — 2026-07-13

## Result

Implementation, the final-tree automated verifier, and the cold-launch Computer
Use gate are accepted. No open finding remains for the Phase 33 scope.

## Baseline and scope

- Start SHA: `28d7834488a2d84727e08e00a2e45656bdff9999`.
- Branch: `codex/osc1337-report-variable-phase33-20260713`.
- Request: strict Base64 UTF-8 variable name through iTerm2 OSC 1337.
- Reply: exact BEL-terminated `OSC 1337;ReportVariable=<Base64 value> BEL`.
- Supported surface: twelve accurately owned `session.*` values and bounded
  terminal-owned `user.*` values.
- Retained boundary: no host environment, file, clipboard, command-output,
  process-introspection, focus, launch, URL, or generic host-action authority.

## Official comparison and product decision

The implementation was compared with the official iTerm2 escape-code and
variable documentation and with iTerm2 source paths `VT100Terminal.m`,
`VT100Output.m`, `PTYSession.m`, `iTermNaggingController.m`,
`iTermVariables.m`, and `iTermVariableScope+Session.h`.

iTerm2 sends an empty response when the exact variable is denied or undefined
and stores a future allow/deny decision per name. Ianvs follows that contract
with an immediate empty first response, an active-pane future-policy prompt,
safe focused **Always Deny**, **Always Allow**, and non-persisting **Not Now**.
Only one prompt may be visible, with a 30-second global cooldown. Defaults &
appearance lists up to 64 decisions and can forget one or all.

## Review findings and repairs

1. The parser initially allowed a 4 KiB decoded name while Dart enforced 256
   bytes, and it surfaced C0/C1 controls. All parser, runtime and config gates
   now agree on 256 UTF-8 bytes and reject control characters; multibyte
   boundary tests were added.
2. The native bridge must resolve terminal-owned `user.*` before product
   permission is known. Its candidate value is now retained only in the
   runtime's private one-shot token. The public event contains only source and
   name, so an unprivileged consumer cannot inspect the candidate.
3. Response tokens are bound to session identity and epoch. Wrong-session,
   duplicate, stale, closed-session and oversized responses fail closed;
   overflow receives an immediate empty response and close removes tokens.
4. Product `session.*` values are re-resolved from current pane/frame state.
   Native title/context fallback and `user.*` candidate access require the
   exact stored Allow decision. Denied, undefined and unsupported names reply
   empty; malformed wire input is a bounded no-op.
5. Config serialization filters unsupported names before applying its 64-item
   cap. A widget assertion that could pass vacuously now first requires exactly
   two empty replies.

## Automated evidence

`VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1
tools/verify_flutter_terminal.sh` exited 0 on the final code tree.

- shared corpus: 38 cases / 57 required edge classes; semantic probes: 30;
- vendored Rust: 1,693 passed / 1 existing ignored; doc tests: 11 passed /
  1 existing ignored;
- native core: 101 unit, 1 corpus, 497 session/real-PTY and 3 VTT tests;
- `ianvs_pty`: 22 tests; Dart/Flutter analysis and package suites passed;
- docs contracts: 7 tests; example macOS smoke: 4; application real PTY: 37;
  RunnerTests: 15;
- Clippy, formatting, generated Protobuf compatibility, corpus mirroring,
  macOS builds and diff whitespace gates passed.

The verifier-built executable is
`example/build/macos/Build/Products/Debug/Ianvs Terminal Dev.app` with SHA-256
`c90b23ee27221de9ab551b39a529adc6a1195756af104e9d2d27dd5648e52b5b`.

## Computer Use acceptance

Accepted on 2026-07-14 against a cold launch of the exact verifier-built app.
The app was first quit, including the user-authorized active shell-session
closure, and then relaunched at 93×21 with `SHELL ACTIVE` before the real-child
probe ran.

- The first `user.CU33_KEY` request returned the exact empty reply
  `1b5d313333373b5265706f72745661726961626c653d07` and opened the active-pane
  **Allow future variable reports?** prompt. Accessibility exposed the exact
  variable name, explanatory boundary text, **Not Now**, **Always Allow**, and
  **Always Deny**; the deny action retained the visible safe-default emphasis.
- Explicit **Always Allow** produced the exact BEL-terminated `cu33-value`
  response
  `1b5d313333373b5265706f72745661726961626c653d5933557a4d793132595778315a513d3d07`.
- The immediately following unsupported `session.environment` request returned
  the same exact empty reply and did not open a second prompt.
- `echo CU33-INPUT-OK` executed and printed `CU33-INPUT-OK` in the same shell
  after the protocol round trip.
- Defaults & appearance showed **Terminal variable reports**,
  `1 remembered · 1 allowed · 0 denied`, exact name `user.CU33_KEY`, status
  **Allow**, and the single/all removal controls. Acceptance did not invoke a
  removal control.
