# T-202 ShellScreen completion diagnostics first patch

## Milestone

P0-P5 production wiring integration

## Intent

Define and execute the smallest safe `ShellScreen` production patch: render
read-only blocked completion diagnostics without changing terminal runtime
behavior.

## Scope

- Import the high-level shell UI wiring export surface.
- Build or hold a pending completion snapshot.
- Resolve diagnostics presentation.
- Render `LocalTerminalCompletionDiagnosticsPanel` or an equivalent read-only
  diagnostics entry point.
- Avoid changes to tab, pane, paste, notification, visual, or action execution
  behavior.

## Deliverables

- `docs/LOCAL_TERMINAL_SHELLSCREEN_PATCH_CHECKLIST_2026-05.md`
- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- First production patch is constrained to read-only diagnostics.
- Completion diagnostics remain blocked until real production wiring and
  verification evidence exist.
- No terminal behavior changes are bundled into the diagnostics patch.

## Status

Implemented as the first read-only production entry point. `ShellScreen`
imports the shell UI wiring export surface, holds a pending completion
diagnostics snapshot, and renders `LocalTerminalCompletionDiagnosticsPanel`
inside the existing toolbelt without changing terminal runtime behavior.

Verification is still pending. No analyze, tests, formatting, or manual UI
checks have been run for this patch.
