# Ianvs Terminal Product Scope

This document defines the current authoritative product boundary for Ianvs
Terminal. Historical scope changes remain in dated task records.

## Product center

Ianvs Terminal is a terminal application. Its durable product concepts are:

- **Profile**: reusable launch defaults such as program, arguments,
  environment and initial working directory.
- **Session**: one live PTY process. Runtime title, timestamps and exit state
  belong to the live session and are not restart intent.
- **Terminal Layout**: local tab/pane topology plus the active tab and pane.
- **Relaunch Spec**: the minimum data needed to start a fresh terminal:
  `profileId` and optional `cwd`. Command, arguments and connection settings
  always come from the referenced current Profile.
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
recording paths, command overrides and restart policy are excluded from Relaunch
Spec. Stale command fields in current-schema documents are ignored and are not
written back.

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

The action registry (`TerminalActionId` and `ShellActionRegistry`) contains 40
supported actions, including the SSH session SFTP panel. The 23 previously hidden
actions have been retired from dispatch, menus, shortcut resolution and dedicated
UI. Debug builds use the same boundary. Shared terminal protocols and ordinary
clipboard, search, profile, theme and notification infrastructure remain where
needed by supported behavior. Unknown legacy shortcut entries round-trip without
becoming executable; retirement does not delete user data.

## Historical terminology

Older task records T-312 through T-317 describe the superseded Project
Workspace implementation and remain unchanged as history. Current pane action
types, product UI, persistence and capability claims use Terminal Layout.
Test fixture variable names and historical records may still
use the generic word `workspace`; they do not define a persisted project identity.
