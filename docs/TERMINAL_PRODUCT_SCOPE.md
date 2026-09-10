# Ianvs Terminal Product Scope

This document is the authoritative product boundary for Ianvs Terminal after
the 2026-07-23 scope convergence.

## Product center

Ianvs Terminal is a terminal application. Its durable product concepts are:

- **Profile**: reusable launch defaults such as program, arguments,
  environment and initial working directory.
- **Session**: one live PTY process. Runtime title, timestamps and exit state
  belong to the live session and are not restart intent.
- **Terminal Layout**: local tab/pane topology plus the active tab and pane.
- **Relaunch Spec**: the minimum data needed to start a fresh terminal:
  `profileId`, optional command/arguments and optional `cwd`.
- **Recording Library**: a recording index and recording files independent of
  layout and relaunch persistence.

The primary folder workflow is **Open Terminal at Folder**. Selecting a folder
opens a new terminal whose initial `cwd` is that folder; it does not create,
switch or remember a project container.

## Persistence contracts

- Profile, SSH credentials and configuration always use the same device-local
  repositories. SSH secrets are encrypted at rest. Saving and reconnecting do
  not require a configured or reachable API, including on iOS.
- macOS is the primary delivery platform. iOS implements the SSH-oriented
  companion flow and local persistence, while physical-device and release
  acceptance remain separate evidence requirements.
- The Go/GORM API is an optional sync destination (bundled SQLite or remote
  SQLite/MySQL). Initial connection and later retries use three-way merge against
  an encrypted, destination-scoped checkpoint. Independent edits merge; same-field
  conflicts pause that document until explicitly resolved. API configuration
  never selects a different local data set or overwrites one by migration.
- This is optional configuration synchronization for the selected API endpoint;
  it is not a managed team cloud, collaboration service, or shared terminal
  session service.
- Layout/Relaunch Spec and recording files remain device-local. Retired paste
  history is excluded from active synchronization. Existing local and remote
  history data is preserved without collection or automatic transfer.
- Disabling or changing an API preserves local data and old checkpoints. No
  supported-schema migration deletes a source database or credential archive.
- Replay provides recent screen history, a newest-first list of saved recordings,
  and a file picker. Stopping and saving a recording refreshes the local list;
  a fresh app instance rediscovers completed files for playback, search and copy.
  Recent screen history is temporary and is separate from saved recordings.
- `ianvs_recordings/` stores recordings in one flat, current-format library.
  Unsupported recording and repository metadata schemas fail closed; the app
  does not migrate, discover, or rewrite older recording layouts.
- Unsupported Workspace schemas, project identity/index and `workspace`
  configuration are outside the current contract. Runtime code does not
  discover, migrate, delete or recreate them.

Runtime titles, creation/exit timestamps, exit codes, environment metadata,
recording paths and restart policy are excluded from Relaunch Spec.

## Explicit non-goals

The current product does not define:

- Project Workspace identity, Recent Workspace or project switching;
- project explorer, Git context, IDE project model or project task model;
- plugin marketplace/runtime, managed cloud services or collaboration;
- remote-domain or multi-host Workspace abstractions.

SSH is implemented as a **Profile and Session extension**. Local shells and SSH
sessions share the same tab, pane and layout model without reintroducing a
project container.

## Diagnostics boundary

User-facing diagnostics export remains supported. The Toolbelt and its debug-only
completion/wiring panel are retired. Internal diagnostic models may support tests
and diagnostics export, but do not create a second product surface.

## Retired action boundary

The action registry contains the 39 supported actions. The 23 previously hidden
actions have been retired from dispatch, menus, shortcut resolution and dedicated
UI. Debug builds use the same boundary. Shared terminal protocols and ordinary
clipboard, search, profile, theme and notification infrastructure remain where
needed by supported behavior. Unknown legacy shortcut entries round-trip without
becoming executable; retirement does not delete user data.

See [the retirement record](reviews/trail_feature_retirement_20260907.md) for the
per-action disposition and retained compatibility boundaries.

## Historical terminology

Older task records T-312 through T-317 describe the superseded Project
Workspace implementation and remain unchanged as history. Some internal pane
action types still use the generic word `Workspace`; they model the terminal
canvas, not a persisted project identity. Product UI, persistence and current
capability claims use Terminal Layout.
