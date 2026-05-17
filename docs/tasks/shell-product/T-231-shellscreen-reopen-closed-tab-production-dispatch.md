# T-231 ShellScreen reopen closed tab production dispatch

## Milestone

P1/P2 action runtime and workspace production wiring

## Intent

Implement `reopenClosedTab` as a local recreation of the most recently closed
tab's profile/layout, and route it through production dispatch.

## Scope

- Track recently closed tabs in `SessionController`.
- Record tabs closed by user-initiated close paths.
- Do not record runtime-natural session exits as reopenable tabs.
- Recreate the most recently closed tab with fresh runtime sessions using the
  original pane profile snapshots where available.
- Preserve pane count, split axis, and active pane intent when recreating.
- Add command-menu production dispatch for `reopenClosedTab`.
- Add a command-menu entry for `Reopen closed tab`.
- Promote `reopenClosedTab` into the current default required production action
  set.

## Non-goals

- Do not restore the original PTY process state.
- Do not restore scrollback contents.
- Do not persist closed-tab history across app restarts.
- Do not claim full workspace restoration is complete.

## Deliverables

- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- Closing a tab or last pane records a reopenable tab snapshot.
- `reopenClosedTab` creates fresh sessions using the recorded profile layout.
- Runtime-natural exits are not recorded as reopenable tabs.
- The command menu enables `Reopen closed tab` only when a closed tab is
  available.

## Status

Implemented as local closed-tab recreation production dispatch.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.
