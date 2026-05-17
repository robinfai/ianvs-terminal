# T-233 ShellScreen scrollback export production dispatch

## Milestone

P1/P5 action runtime and visual production wiring

## Intent

Provide a real export action for native historical scrollback when available,
with visible-frame export as a fallback.

## Scope

- Add visible-frame text extraction from the active terminal viewport frame as a
  fallback.
- Prefer native historical scrollback text when the runtime exposes it.
- Write the export through `LocalTerminalScrollbackExporter`.
- Store exports under app support `scrollback_exports`.
- Mark export metadata with `scope: historical-scrollback` or
  `scope: visible-frame`.
- Add a command-menu entry for `Export visible terminal frame`.
- Register `exportScrollback` in command-menu production dispatch.
- Promote `exportScrollback` into the current default required production action
  set.

## Non-goals

- Do not add a file picker or format picker in this task.
- Do not run verification commands.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- `exportScrollback` executes through `ShellActionProductionRuntimeAdapter`.
- Empty visible frames skip export.
- Successful export writes a plain-text file and reports the path.
- Metadata clearly labels the export scope.

## Status

Implemented as historical-scrollback-first export production dispatch with a
visible-frame fallback.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.
