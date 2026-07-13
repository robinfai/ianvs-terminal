# Phase 31 review — OSC 99 interactive reports — 2026-07-13

## Result

Phase 31 is accepted. Ianvs implements Kitty OSC 99 report activation,
label-only buttons, tracked close reports, alive queries and canonical default
identity as a bounded, user-driven subset. The complete repository verifier and
the cold-launch Computer Use gate both pass. No unresolved in-scope finding
remains.

## Baseline and scope

- Start SHA: `66e8c8e7051d7f800fec8309006089426a64f55a`.
- Branch: `codex/osc99-interactive-reporting-phase31-20260713`.
- Promoted: `a=report|-report`, `c=0|1`, `p=buttons`, `p=alive`, omitted-ID
  lifecycle, and fixed activation, one-based button and close reports.
- Retained boundary: `a=focus|-focus` never changes host focus. Sound, icons,
  urgency, command data, arbitrary callbacks, file reads and clipboard reads
  remain unsupported and unauthorized.

## Trust and product decisions

Button payloads are presentation-only labels: five maximum, 64 Unicode scalars
each, separated by U+2028. Empty slots preserve their source ordinal and render
with a local fallback label. A label is never interpreted or echoed. The
product can write only three fixed response shapes assembled from a separately
bounded Kitty identifier and a validated one-based index.

Every gesture re-resolves the live session, pane and identical current
notification object. Removed sessions, stale same-ID menu objects, wrong
identifiers and out-of-range buttons fail closed. Child `p=close` does not echo
a report; only explicit user dismissal or tracked positive expiry reports close
when `c=1`. Opening the in-window menu can focus the pane because it is a user
gesture, while protocol `a=focus` itself remains inert.

## Review iterations and repairs

1. The implementation added parser/snapshot state, native and Dart typed
   fields, product lifecycle, a standard Material popup menu, shared corpus and
   end-to-end tests. The first complete verifier stopped at vendored Rust
   formatting; `cargo fmt` repaired the mechanical drift before the successful
   complete run.
2. The first application-level real-child probe used a heredoc whose stdin was
   not a TTY. It was corrected to open `/dev/tty`, matching the production
   child path, and its targeted and complete-suite runs passed.
3. Reopening the popup repeatedly inside the application integration harness
   was timing-sensitive. The durable split now proves menu taps in the widget
   test, proves one real-PTY button report through the production UI, and proves
   activation/close bytes through the same product controller and live child.
   This retains independent evidence at each boundary without weakening the
   asserted wire contract.
4. Computer Use initially attached to a Phase 30 process that predated the
   verifier build. The old Codex-owned test shell was closed and the exact
   verifier bundle was cold-launched. An initial manual sequence also omitted
   Kitty's `d=0` chunk marker; after correcting the probe, the implementation
   produced the combined title/body/buttons state. Neither issue was a product
   defect, and all acceptance observations below are from the corrected cold
   run.
5. The final lifecycle review found that in-window Dismiss removed Dart state
   and reported close but did not yet remove the identifier from the native
   `p=alive` set. A bounded synchronous host-control request now closes that
   exact native ID before explicit or timed product removal. The real-PTY test
   queries `p=alive` after Dismiss and proves the identifier is absent.
6. The first complete post-repair run inherited Finder as the foreground app
   from the no-focus Computer Use check, so macOS App Nap stalled two existing
   four-second idle timing cases. Restoring Ianvs to the foreground made both
   exact cases pass independently; the complete verifier was then rerun from
   the start and exited 0 with all idle-hint paths below their hard ceilings.
7. The final protocol diff pass compared the new response paths with Kitty's
   normative identifier and button-number rules. It found that the generic
   metadata alphabet was wider than the identifier alphabet, and that removing
   empty button labels could shift later one-based button reports. OSC 99 IDs
   are now restricted end-to-end to `[A-Za-z0-9_+.-]`; empty slots retain their
   ordinal and render as `Button N`. The Dart ingress sanitizer was also
   tightened to remove C1 controls, matching the native parser and the stated
   text policy. Parser, controller, and widget regressions cover the repairs.

The final independent diff review found no further correctness, security,
lifecycle, accessibility, compatibility or acceptance issue in the promoted
scope.

## Automated evidence

The final-tree command
`VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 tools/verify_flutter_terminal.sh`
exited 0. Audited results include:

- 36 shared-corpus cases and 49 required edge classes;
- 28 semantic probe intents;
- 1,687 vendored Rust tests with one ignored, plus 12 doc tests with one
  ignored;
- 99 native core unit tests, 492 native session tests and 3 VTT tests;
- 22 `ianvs_pty` tests;
- 477 passing `ianvs_terminal` tests with one existing skip;
- 7 documentation-contract tests;
- 948 grouped example tests and 128 top-level example widget tests;
- 4 macOS smoke tests, 35 macOS application real-PTY tests and 15 RunnerTests.

Formatting, static analysis, Clippy, protobuf checks, benchmark smoke and the
macOS Debug build passed in the same run.

## Final Computer Use gate

Computer Use cold-launched the exact verifier-built bundle:

`example/build/macos/Build/Products/Debug/Ianvs Terminal Dev.app`

Its executable SHA-256 was
`16475a1da3428e7a0198ac78acada37001c30bda89e875c257503c55bba1c5fc`.
A real zsh child emitted a chunked title/body notification whose button payload
contained an empty first slot followed by Retry. The accessibility tree and
visible popup contained the title, message, local `Button 1` fallback, Retry as
`Notification action 2`, and Dismiss.

Choosing Retry returned
`ESC ] 99 ; i=final31 ; 2 ESC \\`; activating the notification returned
`ESC ] 99 ; i=final31 ; ESC \\`; Dismiss returned
`ESC ] 99 ; i=final31:p=close ; ESC \\`. After receiving the close report,
the child queried `i=after-final:p=alive` and received the exact empty-list
reply `ESC ] 99 ; i=after-final:p=alive ; ESC \\`. The child printed all four
exact hex encodings, the notification status disappeared, and
`echo PHASE31 FINAL INPUT OK` completed in the same shell.

The no-focus safety sub-gate was run before the final repair iterations: a second
child waited before emitting `i=focus31:a=focus`; Finder was selected before
emission and remained the foreground app afterward. Reading the Ianvs
accessibility tree confirmed that `Focus must stay with Finder` had actually
arrived, excluding a false pass caused by a missing event. The later lifecycle,
identifier, button-ordinal, and C1-sanitization repairs did not touch focus
handling, and the final automated focus-safety coverage remained green.

## Compatibility and remaining boundary

The native callback and Dart event fields are additive; OSC 99 remains on the
JSON event route and no protobuf tag changed. Query output advertises only the
implemented subset. A live Kitty reference-terminal comparison remains pending
because protected terminal-emulator control is outside the Computer Use
boundary; it is not required for Ianvs Phase 31 acceptance and is not claimed
as completed.
