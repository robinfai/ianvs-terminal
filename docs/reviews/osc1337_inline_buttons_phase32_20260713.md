# Phase 32 review — OSC 1337 inline buttons — 2026-07-13

## Result

Accepted. Implementation, automated verification, cold-launch Computer Use
acceptance, and the final diff review all completed without remaining
actionable findings.

## Baseline and scope

- Start SHA: `6d0edb3bf640a21670691f22dd2fedf6ab5dca29`.
- Branch: `codex/osc1337-inline-buttons-phase32-20260713`.
- Promoted: documented `type=copy`, `type=custom`, global custom invalidation,
  four-cell reservation, explicit copy, and the fixed custom reply.
- Retained boundary: no OSC-provided executable action, URL, file authority,
  focus request, arbitrary reply bytes, or automatic clipboard access.

## Review findings and repairs

1. Parser state, additive JSON/Protobuf frame transport, Material overlay,
   runtime activation, shared corpus and real-PTY tests were implemented.
2. A security review found that resetting the button ID allocator on clear or
   RIS could let an old frame collide with a new button. The allocator now
   remains monotonic across those lifecycle operations, with a regression test.
3. The same review found that copy extraction could otherwise clamp an evicted
   block to a partial retained range. Copy now requires the whole completed
   block to remain retained and returns rejection otherwise.
4. Activation now requires the ID to be present in the current visible frame
   projection. Off-viewport, folded, invalid, wrong-screen and stale actions
   fail closed before any clipboard result or PTY write.

## Targeted evidence

- Vendored parser: copy/custom, BEL/ST, invalid payloads, four-cell advance,
  invalidation, alternate-screen cleanup, bounds, ingress policy and ID
  non-reuse tests pass.
- Native core: frame projection/fold exclusion, shared byte corpus, real PTY
  exact custom reply, copy text, invalidation, resize replay, stale rejection,
  VT220 denial and Protobuf fields pass.
- Dart/Flutter: JSON/Protobuf parity, strict model validation, runtime request,
  themed widget, disabled semantics, click, Tab/Enter, and example clipboard
  bridge tests pass.

## Final automated acceptance

`VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1
tools/verify_flutter_terminal.sh` exited 0 after a clean rerun. Its audited
results included:

- shared corpus: 37 cases / 53 required edge classes; semantic probes: 29;
- vendored Rust: 1,690 passed / 1 existing ignored; doc tests: 11 passed /
  1 existing ignored;
- native core: 100 unit, 1 corpus, 495 session/real-PTY and 3 VTT tests;
- `ianvs_pty`: 22 tests; Flutter package: 479 passed / 1 existing skipped;
- docs contracts: 7 tests; example: 948 broad widget, 129 shell widget,
  4 macOS smoke and 36 real-PTY tests; native Runner tests succeeded;
- Rust Clippy, Dart/Flutter analysis, formatting, corpus mirror, generated
  Protobuf compatibility and diff whitespace gates passed.

The verifier-built executable was
`example/build/macos/Build/Products/Debug/Ianvs Terminal Dev.app` with
SHA-256 `160829b434f711298778e5fb364f65f7f710bc9048e05982a0d87dd2d2c90701`.

## Computer Use acceptance

The exact verifier-built app was closed, confirmed not running, and then
cold-launched through Computer Use. A real zsh child emitted a completed block,
a copy button, a custom button with code 42, and custom invalidation.

- Accessibility exposed `Copy terminal block gui-copy-3` and
  `Activate terminal button 42` as buttons.
- Explicit copy produced clipboard hex
  `425554544f4e2d434f50592d4558414354`, exactly `BUTTON-COPY-EXACT`.
- Explicit custom activation produced PTY reply hex
  `1b5b3f313333373b34327e`, exactly `CSI ? 1337 ; 42 ~`.
- Invalidation left the custom control visible as
  `Activate terminal button 42 (disabled)`.
- The terminal accepted a subsequent command and rendered `GUI3-INPUT-OK`.

An initial exploratory keyboard pass was deliberately discarded because extra
probe text was sent while the child was in raw mode; the isolated rerun above
used fresh IDs and contains the accepted byte-exact evidence. Automated widget
coverage separately proves Tab plus Enter activation without input leakage.

## Final review

The post-acceptance review rechecked the full diff, monotonic/stale-ID and
current-frame activation rules, copy retention bounds, state/writer lock order,
JSON/Protobuf tag 32 parity, generated files, both corpus mirrors, formatting
and `git diff --check`. No actionable finding remains.
