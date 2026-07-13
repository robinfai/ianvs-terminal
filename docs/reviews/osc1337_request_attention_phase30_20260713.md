# Phase 30 review — OSC 1337 RequestAttention — 2026-07-13

## Result

Phase 30 is accepted. Ianvs implements the exact iTerm2
`OSC 1337;RequestAttention=` yes/once/no/fireworks set as a closed,
permission-gated contract. The complete repository verifier and the final
cold-launch Computer Use acceptance both pass. No unresolved in-scope finding
remains.

## Baseline and scope

- Start SHA: `467981282a9e14896ff5f3f0814a3e80a552c82c`.
- Branch: `codex/osc1337-request-attention-phase30-20260713`.
- Persistent policy: Deny by default, or Allow with limits.
- `yes`: critical AppKit attention; `once`: informational AppKit attention;
  `no`: cancel the request owned by that session; `fireworks`: bounded
  cursor-local visual attention.
- Deferred: Notification Center content, arbitrary actions, focus/activation,
  unrelated host authority, and a live iTerm2 reference-terminal comparison.

## Trust and product decisions

Parser acceptance grants no platform authority. The vendored parser emits a
closed enum, native code independently maps only the source and action, and the
Dart runtime validates both again before product policy is applied. The event
does not contain terminal content.

AppKit request IDs are owned per session, capped globally, rate-limited, and
cancelled on no, reset, close, policy disable, or disposal. A late platform
completion is protected by a session/policy epoch check. The app never activates
itself or steals focus. Fireworks remain cursor-local, viewport-bounded,
non-interactive, theme-derived, and Reduce Motion safe.

## Review iterations and repairs

1. The implementation pass added parser/native/Dart/product/macOS coverage and
   the mirrored shared corpus. A vendored Rust formatting drift was detected by
   the gate and formatted before the final verifier.
2. Direct ad-hoc `xcodebuild` invocation used a temporary listener configuration
   that was not representative of the product build. Validation was repeated
   through the repository verifier's canonical Flutter/macOS build and
   RunnerTests flow; this was an environment-only correction, not a product
   defect.
3. The first full verifier exposed an application integration test that assumed
   session ID 1. The aggregate suite advances native session IDs, so the
   fireworks finder could time out despite the product behaving correctly. The
   test now reads the active session ID from `sessionControllerProvider`; its
   targeted run and the subsequent complete verifier both pass.
4. Computer Use keyboard injection dropped shell metacharacters and underscores
   in an initial probe path. The acceptance was repeated through a temporary
   `/tmp/a.py` real-child helper outside the repository. This was an automation
   input limitation; the final terminal interaction separately proved normal
   input remained usable.
5. The final independent review found that the eight-request global cap counted
   returned AppKit IDs but did not reserve slots for platform calls still in
   flight. An unusually slow bridge could therefore allow more than eight
   concurrent requests. The cap now counts the union of owned and pending
   sessions, with a regression test that holds nine platform calls unresolved
   and proves only eight are admitted.

The final independent review found no further correctness, security, lifecycle,
accessibility, or acceptance issue in the promoted scope.

## Automated evidence

The final-tree command
`VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 tools/verify_flutter_terminal.sh`
exited 0. Audited results include:

- 35 shared-corpus cases and 49 required edge classes;
- 28 semantic probe intents;
- 1,683 vendored Rust tests with one ignored and 11 doc tests with one ignored;
- 99 native core unit tests, 490 native real/session tests, and 3 VTT tests;
- 22 `ianvs_pty` tests;
- all `ianvs_terminal` tests with one existing skip;
- 946 grouped example tests and 128 example widget tests;
- 4 macOS smoke tests, 34 macOS application real-PTY tests, and 15
  RunnerTests.

Static analysis, formatting, Clippy, protobuf checks, documentation contracts,
and the final macOS debug build also passed in the same run.

## Final Computer Use gate

Computer Use cold-launched the exact verifier-built bundle:

`example/build/macos/Build/Products/Debug/Ianvs Terminal Dev.app`

After the in-flight cap repair and complete rebuild, its final executable
SHA-256 was
`60aba9699949280f383cc462babf28d83399a38fa866ccc3573bb948ce5c6b6a`.
Defaults & appearance visibly started at Deny and persisted Allow with limits.
A real child then emitted eight spaced fireworks actions followed by once, yes,
and no. The effect was visibly rendered at the live cursor, every marker
completed, cancellation returned to the prompt, and the shell stayed responsive.

A second real-child probe emitted yes after Ianvs was placed behind Finder and
later emitted no. Finder remained the foreground app after the request and after
cancellation, demonstrating that the protocol did not activate or focus Ianvs.
Returning to the same terminal showed the armed/yes/cancelled markers, and
`echo PHASE30 INPUT OK` completed normally.

## Compatibility and remaining boundary

The native callback and Dart event kinds are additive; no frame, protobuf, or
FFI schema was changed. Missing configuration fails closed to Deny. Reverting
the phase restores bounded no-op behavior without affecting other OSC 1337
features.

The official iTerm2 escape-code documentation and AppKit API contract were used
for the implementation comparison. A live iTerm2 UI run remains pending because
protected terminal-emulator control is outside the Computer Use boundary; it is
not required for Ianvs Phase 30 acceptance and is not claimed as completed.
