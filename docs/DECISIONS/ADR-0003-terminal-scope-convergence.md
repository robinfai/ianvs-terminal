# ADR-0003: Converge On Terminal Layout Instead Of Project Workspace

- Status: Accepted
- Date: 2026-07-23

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
them. Relaunch Spec stores only launchable intent. Recordings use their own
flat library/index. Internal completion diagnostics are debug-only, while
diagnostics export remains supported.

SSH is deferred, not rejected. A future SSH design must extend Profile and
Session without restoring the project Workspace abstraction.

## Consequences

- Multi-tab and split-pane restoration remains available.
- Restoring a layout always creates fresh PTYs.
- Runtime titles, exit state and recording paths cannot silently become
  restart policy.
- Unsupported project collections remain outside runtime discovery and are
  not modified by the app.
- Historical T-312 through T-317 records remain valid history but no longer
  describe the current product surface.

## Rejected alternatives

- Keep Project Workspace as a hidden storage identity: rejected because it
  preserves the same coupling and invites the UI to return.
- Put recording paths in Relaunch Spec: rejected because recording ownership
  and fresh process launch have different lifecycles.
- Remove tab/pane persistence together with Workspace: rejected because
  terminal layout is a core terminal capability.
