# T-301 OSC 99 Notification Menu Regression

## Goal

Restore explicit OSC 99 notification actions in the current tab chrome after
the legacy status bar was removed.

## Scope

- Turn the existing tab pane-signal chip into a Material 3 notification menu
  whenever its tab contains recent notifications.
- Expose OSC 99 activation, numbered button, and dismiss actions for both
  visible and overflow-tab rows.
- Route menu selections back to the originating PTY session.
- Exercise all three interactions through the real PTY integration test.

## Non-goals

- Do not restore the removed legacy status bar.
- Do not change OSC 99 parsing, report encoding, or controller identity checks.
- Do not weaken the exact-byte real PTY assertions.

## Files In Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_chrome.dart`
- `example/lib/features/shell/shell_screen_state_events.dart`
- `example/integration_test/real_pty_acceptance_test.dart`
- `docs/tasks/verification-gates/T-301-osc99-notification-menu-regression.md`
- `docs/tasks/README.md`

## Functional Acceptance

- A tab with a recent notification exposes its existing pane-signal chip as an
  accessible menu button.
- OSC 99 numbered buttons and activation send their exact reports to the source
  child process.
- Dismiss removes the notification and sends the close report when requested.
- The interaction remains available when a tab is displayed in the overflow
  list.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd example
flutter test -d macos integration_test/real_pty_acceptance_test.dart \
  --plain-name "real PTY OSC 99 reports explicit menu interactions to its source child"
```

```bash
make verify
```

## Manual QA

Not required for the regression gate. The macOS real PTY test drives the
current tab chrome and verifies the report bytes observed by the child process.

## Done When

- The focused real PTY interaction passes through the current UI.
- Repository verification passes.
- No legacy status-bar code is restored.

## Risks / Follow-ups

- The combined pane-signal chip prioritizes notification inspection whenever
  any recent notification exists; progress-only signals retain pane-focus
  behavior.

## Result

- Restored notification actions on the current tab pane-signal chip without
  restoring the legacy status bar.
- The focused real PTY test passed all button, activation, and dismiss flows,
  including their exact OSC 99 report bytes.
- The final `make verify` run passed all 44 real PTY tests, the macOS build,
  and all 16 Runner XCTest cases.
