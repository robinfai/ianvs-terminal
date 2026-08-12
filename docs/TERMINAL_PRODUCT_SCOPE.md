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

- The Go/GORM data API is the target durable store for Profile, Terminal
  Layout/Relaunch Spec, and configuration resources. Local mode uses SQLite;
  remote mode supports SQLite or MySQL with the same ORM model.
- `ianvs_terminal_layout.json`, `ianvs_config.json`, and the other historical
  app-support JSON documents are one-way local migration inputs. The importer
  never rewrites or deletes them.
- `ianvs_recordings/` stores recordings in one flat, current-format library.
  Unsupported recording and repository metadata schemas fail closed; the app
  does not migrate, discover, or rewrite older recording layouts.
- Legacy Workspace v1-v3, project identity/index and `workspace` config are
  read-only migration inputs. New writes never recreate them.

Runtime titles, creation/exit timestamps, exit codes, environment metadata,
recording paths and restart policy are excluded from Relaunch Spec.

## Explicit non-goals

The current product does not define:

- Project Workspace identity, Recent Workspace or project switching;
- project explorer, Git context, IDE project model or project task model;
- plugin marketplace/runtime, cloud sync or collaboration;
- remote-domain or multi-host Workspace abstractions.

SSH is implemented as a **Profile and Session extension**. Local shells and SSH
sessions share the same tab, pane and layout model without reintroducing a
project container.

## Diagnostics boundary

User-facing diagnostics export remains supported. Internal completion/wiring
diagnostics are compiled into the Toolbelt only in debug builds and are not a
release product panel.

## Historical terminology

Older task records T-312 through T-317 describe the superseded Project
Workspace implementation and remain unchanged as history. Some internal pane
action types still use the generic word `Workspace`; they model the terminal
canvas, not a persisted project identity. Product UI, persistence and current
capability claims use Terminal Layout.
