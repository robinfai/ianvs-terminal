# Local Terminal Shell UI Wiring Handoff

Date: 2026-05-16

Purpose: identify the stable entry points that `ShellScreen`, developer
diagnostics, or command-menu UI should use when wiring the local terminal P0-P5
completion surfaces.

This handoff does not close the work. It prevents future production wiring from
depending on low-level manifest internals directly.

## Preferred production wiring entry points

| Use case | Preferred entry point | Avoid depending on directly |
| --- | --- | --- |
| Build real P0-P5 production wiring state | `LocalTerminalProductionWiringBundle.fromDomainCallbacks(...)` | Individual manifest builders unless debugging |
| Route domain callbacks into shell actions | `LocalTerminalActionDomainRouter` through the bundle | Hand-written action-name maps |
| Render current blocked state in UI/logs | `LocalTerminalShellUiWiringSnapshot` | Raw milestone/backlog lists |
| Render Shell UI diagnostics from real evidence | `LocalTerminalShellUiWiringFacade` | Separate summary/menu/diagnostic objects assembled ad hoc |
| Render command-menu/developer-panel sections | `LocalTerminalCompletionCommandMenuAdapter` | Completion controller internals |
| Render command-menu disabled reasons | `LocalTerminalCompletionShellCommandMenuDiagnostics` | Fake `TerminalActionId` values |
| Build final closure evidence | `LocalTerminalCompletionEvidenceReport` through `LocalTerminalRealWiringBacklogEvidence` | Boolean-only closure flags |
| Record verification gates | `LocalTerminalVerificationEvidence.defaultRequiredPending(...)` then replace gates with real results | Omitted gates or skipped gates as success |

## Production wiring sequence

1. Populate P2-P5 domain callbacks from real `ShellScreen`,
   `SessionController`, settings, export, notification, and runtime methods.
2. Build `LocalTerminalProductionWiringBundle.fromDomainCallbacks(...)`.
3. Use the bundle's routed action callbacks for P1 action production wiring.
4. Build `LocalTerminalVerificationEvidence` from real command/manual output.
5. Convert verification evidence to T-169 backlog evidence through
   `LocalTerminalRealWiringTaskEvidence.fromVerificationEvidence(...)`.
6. Build `LocalTerminalCompletionEvidenceReport`.
7. Expose UI diagnostics through `LocalTerminalShellUiWiringFacade` or
   `LocalTerminalShellUiWiringSnapshot`.
8. Update `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` with
   concrete evidence.

## Rules for ShellScreen integration

- Do not register P1 action callbacks separately if the same behavior is already
  represented by a P2-P5 domain callback.
- Do not fabricate `TerminalActionId` values for completion diagnostics.
- Do not treat `ShellActionProductionWiringState.isReady` as final completion;
  tests, analysis, formatting, and manual gates still have to pass.
- Do not make skipped required verification gates count as passed.
- Do not mark optional advanced P5 items complete unless they are either wired
  and verified or explicitly excluded from the required operation set.
- Keep SSH, remote, serial, SFTP, collaboration, and plugin ecosystem behavior
  out of this local-terminal closure path.

## Current status

The handoff is ready for the next implementation pass. Real production callbacks
are still not populated, and no verification command/manual gate has been run in
this session.

## Stable import surface

Future ShellScreen wiring should prefer importing `example/lib/features/shell/local_terminal_shell_ui_wiring_exports.dart` for high-level production wiring, completion diagnostics, snapshot, and verification evidence surfaces. Avoid importing low-level manifest builders directly unless debugging a specific closure calculation.

## Reusable diagnostics panel

Future ShellScreen or developer diagnostics UI can render `LocalTerminalCompletionDiagnosticsPanel` from `example/lib/features/shell/local_terminal_shell_ui_wiring_exports.dart`. The panel consumes `LocalTerminalShellUiWiringSnapshot` and remains read-only.

## Diagnostics presentation mode

Future ShellScreen wiring can use `LocalTerminalCompletionDiagnosticsPresentation` to decide whether blocked completion diagnostics should appear as an inline panel, modal sheet, command-menu section, or developer panel without hard-coding that decision into completion evidence models.

## Diagnostics presentation resolver

Future ShellScreen wiring can use `LocalTerminalCompletionDiagnosticsPresentationResolver` to resolve inline panel, modal sheet, command-menu section, or developer-panel display mode from a shell UI wiring snapshot and a preferred mode. Keep this display decision outside completion evidence objects.

## Pending snapshot factory

Future diagnostics should prefer `LocalTerminalPendingCompletionSnapshotFactory` when rendering a default blocked state before real production wiring or verification evidence exists. It initializes verification evidence from `LocalTerminalVerificationPlanRecords.defaultPending()` so command/manual gate metadata is preserved.

## First ShellScreen patch checklist

Use `docs/LOCAL_TERMINAL_SHELLSCREEN_PATCH_CHECKLIST_2026-05.md` for the first production integration pass. That patch should wire read-only completion diagnostics only and must not change tab, pane, paste, notification, visual, or action execution behavior.
