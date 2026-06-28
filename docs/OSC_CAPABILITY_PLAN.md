# OSC Capability Plan

Status: active plan for P0/P1.

This plan turns OSC support from a list of escape-code numbers into product
capability gates. The current scope is local terminal fidelity and trust; shell
metadata, notifications, and file-transfer style extensions stay out of P0/P1
unless a later task explicitly promotes them.

## Product Brief

- User goal: terminal output should behave like a modern xterm-compatible local
  terminal when apps emit common OSC sequences.
- Product constraint: keep Ianvs local-first. Do not introduce SSH/SFTP/remote
  workflow scope through OSC planning.
- Engineering constraint: parser support is not enough. A sequence is complete
  only when native state, runtime/frame data, Flutter rendering or host events,
  policy, and automated acceptance agree.

## Support Status Vocabulary

Every OSC entry uses one of these states:

- `unsupported`: intentionally ignored or outside current product scope.
- `parsed-only`: consumed by the parser but not surfaced to product code.
- `frame-visible`: exposed through `TerminalFrameDiff` for rendering/state.
- `event-visible`: exposed through runtime events or host callbacks.
- `user-actionable`: drives a visible UI behavior or a policy-controlled action.

## P0 Scope: Protocol Contract

P0 closes the support contract and prevents accidental regressions.

| OSC | Capability | Current target state | P0 decision |
| --- | --- | --- | --- |
| OSC 0/2 | window title | `frame-visible` | Keep xterm-only frame field and tests. |
| OSC 1 | icon name | `frame-visible` | Keep host observer bridge and xterm-only tests. |
| OSC 4/104 | ANSI 0-15 palette set/query/reset | `parsed-only` plus native query evidence | Keep 0-15 scope; 16-255 is not P0. |
| OSC 10/11 | default foreground/background | `frame-visible` | Keep frame defaults and snapshot fallback on color changes. |
| OSC 12/112 | cursor color set/query/reset | `frame-visible` and rendered | Promote to P1 polish because it is visible. |
| OSC 8 | hyperlinks | `user-actionable` | Keep hit-target clearing tests; add product polish in P1. |
| OSC 52 | clipboard copy/paste | `user-actionable` | Keep policy-gated runtime path; document host trust boundaries. |
| OSC 1337 File inline=1 | inline image | `frame-visible`/rendered graphics | Treat as already planned under graphics; no new P0 expansion. |
| OSC 7/133/1337 metadata | cwd/prompt/user vars | `parsed-only` or not bridged | Defer to P2 shell context. |
| OSC 9/777/934 | notification/progress | `parsed-only` or not bridged | Defer to P3 notification/status. |
| OSC 1337 File inline=0 / RequestUpload | file transfer | `unsupported` for P0/P1 | Defer; conflicts with local-terminal scope if expanded prematurely. |

P0 deliverables:

- A single support matrix in this document.
- Named regression coverage for implemented P0 rows.
- Clear unsupported/deferred status for rows that would expand product scope.
- Frame/state schema updated when a parser-owned visual state needs the renderer.

## P1 Scope: Visible Trust Polish

P1 is limited to capabilities users can see or that cross a trust boundary.

### P1-A Cursor Color

OSC 12 must reach Flutter rendering without replacing older frame fallback.

Acceptance:

- Native frame includes `cursor_color` after OSC 12.
- Dart `TerminalFrameDiff.cursorColor` parses valid color values and ignores
  malformed values.
- Delta merge preserves cursor color when later deltas omit the field.
- `RenderTerminalViewport` uses `frame.cursorColor ?? theme.cursor`.
- Smart cursor contrast still applies to the selected base cursor color.

### P1-B Hyperlink Product Polish

OSC 8 is already actionable. P1 should finish the user-facing trust layer.

Acceptance:

- Hover/tap target remains stable after dirty-row overwrite.
- Link opening is explicit and does not fire during selection or double-click
  gestures.
- The UI exposes a way to copy the URI or inspect the target before opening if a
  future surface adds link affordances.
- Unsupported or unsafe URI schemes remain host-policy controlled before open.

### P1-C Clipboard Policy

OSC 52 is already wired through runtime and example policy. P1 should keep it
policy-first.

Acceptance:

- Copy and paste requests are allow/deny/profile-policy gated.
- Invalid base64 payloads are ignored.
- Empty clipboard payloads preserve the intended empty-copy behavior.
- Paste requests reply only when policy permits reading local clipboard data.
- Manual acceptance must include a visible clipboard-copy and paste-request flow.

## Deferred Work

- P2 shell context: OSC 7, OSC 133, OSC 1337 CurrentDir/RemoteHost/SetUserVar.
- P3 status and notification: OSC 9, OSC 777, OSC 934, OSC 1337 badge.
- Later product decision: OSC 1337 File download/upload.
- Not P0/P1: public custom OSC parser hooks, remote identity, full file
  transfer, notification spam defaults.

## Verification Plan

Automated:

```bash
cargo test --manifest-path native/core/Cargo.toml --test session_test osc12
cargo test --manifest-path native/core/Cargo.toml --test session_test osc4
cargo test --manifest-path native/core/Cargo.toml --test session_test osc8
cargo test --manifest-path native/core/Cargo.toml --test session_test clipboard
cd packages/ianvs_terminal && flutter test test/terminal_runtime_controller_test.dart --plain-name "cursor"
cd example && flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "backend cursor color"
cd example && flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "OSC 8 hyperlink"
```

Manual/computer acceptance:

- Send OSC 12 in the app and verify the cursor visibly changes.
- Send OSC 8 and verify tapping opens the expected URL only on deliberate tap.
- Send OSC 52 copy/paste probes with policy enabled and disabled.

## Done Criteria

P0/P1 are done when:

- This matrix matches current code and tests.
- The implemented P0/P1 rows have automated evidence.
- Deferred rows remain explicit and do not silently enter product scope.
- Computer acceptance confirms the visible cursor-color path and the existing
  OSC 8/OSC 52 user-actionable paths.
