# Local Terminal ShellScreen Patch Checklist

Date: 2026-05-16

Purpose: define the smallest safe production patch for wiring local terminal
completion diagnostics into `ShellScreen` without changing terminal behavior.

This checklist is intentionally narrower than T-164 through T-168. It creates a
low-risk first production integration step: display current blocked completion
diagnostics from the already-built snapshot/panel surfaces.

## First patch scope

Wire diagnostics display only.

Do not change:

- Tab creation or close behavior.
- Pane split/focus/resize/swap/zoom behavior.
- Paste or send-text behavior.
- Notification dispatch behavior.
- Theme/layout/export behavior.
- Action registry dispatch behavior.

## Files expected to change

| File | Change |
| --- | --- |
| `example/lib/features/shell/shell_screen.dart` | Import the high-level shell UI wiring export surface and render a diagnostics entry point or panel in a non-invasive location. |
| Optional widget test file | Add or update a widget test only after the production patch is applied and verification is allowed. |

## Preferred integration object

Use:

- `LocalTerminalPendingCompletionSnapshotFactory`
- `LocalTerminalCompletionDiagnosticsPresentationResolver`
- `LocalTerminalCompletionDiagnosticsPanel`

Avoid:

- Direct imports of low-level closure manifest builders.
- Direct construction of verification evidence lists in `ShellScreen`.
- Fake `TerminalActionId` values for completion diagnostics.

## Suggested implementation sequence

1. Add import:
   `local_terminal_shell_ui_wiring_exports.dart`.
2. Create a pending snapshot with:
   `LocalTerminalPendingCompletionSnapshotFactory().build(capturedAt: DateTime.now())`.
3. Resolve presentation with:
   `LocalTerminalCompletionDiagnosticsPresentationResolver(...)`.
4. If presentation is visible and mode is `inlinePanel`, render:
   `LocalTerminalCompletionDiagnosticsPanel(snapshot: snapshot)`.
5. Keep the panel visually secondary and read-only.
6. Do not wire action/domain callbacks in the same patch.

## Acceptance criteria for the first patch

- `ShellScreen` can show blocked completion diagnostics without changing terminal
  runtime behavior.
- Diagnostics are read-only.
- No tab/pane/paste/action execution path changes are included.
- The completion state still reports blocked.
- T-164 through T-169 remain pending until real production callbacks and
  verification evidence are added.

## Risk controls

- If `ShellScreen` layout is crowded, prefer a developer-panel or command-menu
  section over inline rendering.
- If creating `DateTime.now()` in build would cause unnecessary rebuild churn,
  store the snapshot once in state/init path instead.
- If diagnostics are too verbose for the main shell, render only counts plus a
  route/sheet entry point.

## Current status

Patch checklist created. The production file has not been changed by this
checklist, and no verification has been run in this session.
