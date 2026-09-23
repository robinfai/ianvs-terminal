# ADR-0003: Converge On Terminal Layout Instead Of Project Workspace

Status: Accepted. Current product authority is [TERMINAL_PRODUCT_SCOPE.md](../TERMINAL_PRODUCT_SCOPE.md).

## Context

The application had grown a Project Workspace identity, Recent Workspace
index, project switcher and a Session Descriptor containing both fresh-launch
intent and runtime/recording metadata. Those concepts made a terminal behave
like a small IDE and coupled layout restoration to project and recording
lifecycle.

## Decision

Use five product concepts: Profile, Session, Terminal Layout, Relaunch Spec and
Recording Library. Opening a folder launches a new terminal at that `cwd`; it
does not switch an application container.

Project identity, Recent Workspace and project switching are removed from the
product and from current persistence. Unsupported Workspace documents are
outside the runtime contract: the app does not discover, migrate or delete
them. Relaunch Spec persists only `profileId` and optional `cwd`; the referenced
Profile supplies command and connection settings. Recordings use their own flat
library/index. User diagnostics export remains supported.

SSH and SFTP extend Profile and Session without restoring Project Workspace.

## Consequences

- Multi-tab and split-pane restoration remains available.
- Restoring a layout always creates fresh PTYs.
- Runtime titles, exit state and recording paths cannot silently become
  restart policy.
- Unsupported project collections remain outside runtime discovery and are
  not modified by the app.

## Rejected alternatives

- Keep Project Workspace as a hidden storage identity: rejected because it
  preserves the same coupling and invites the UI to return.
- Put recording paths in Relaunch Spec: rejected because recording ownership
  and fresh process launch have different lifecycles.
- Remove tab/pane persistence together with Workspace: rejected because
  terminal layout is a core terminal capability.
