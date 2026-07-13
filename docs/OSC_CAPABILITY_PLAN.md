# OSC Capability Plan

Status: active support contract. P0/P1 and the promoted P2/P3 OSC families are
implemented with automated regression coverage. Through Phase 32, the safe
incoming OSC 1337 download subset, permission-gated OpenURL subset, and bounded
RequestAttention actions are promoted alongside report-only OSC 99 notification
interactions and user-driven OSC 1337 inline buttons; uploads and other
privileged host actions stay outside the current product.

This plan turns OSC support from a list of escape-code numbers into product
capability gates. The current implementation scope is local terminal fidelity
and trust; shell metadata and notification-style extensions stay out of P0/P1.
P2/P3 below define the product and implementation shape for promoting those
families without turning Ianvs into a remote workflow or notification firehose.

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
| OSC 7/133/1337 metadata | cwd/prompt/user vars | `user-actionable` | Bridged through the P2 shell-context contract below. |
| OSC 9/9;4/777/934/1337 badge | notification/progress/badge | `user-actionable` | Bridged through the P3 status/notification contract below. |
| OSC 1337 File inline=0 | incoming file download | `user-actionable` safe subset | Active-pane explicit Save only; bounded native one-shot bytes and discard on cancel/background/timeout. |
| OSC 1337 RequestUpload | outgoing file upload | `unsupported` | Deny and close the protocol request without reading local data. |
| OSC 1337 OpenURL | external URL request | `user-actionable` safe subset | Parse as untrusted Hyperlink-capability metadata; require active-pane Ask policy and exact explicit confirmation; persistent Deny remains available. |
| OSC 1337 RequestAttention | Dock/cursor attention request | `user-actionable` bounded subset | Exact yes/once/no/fireworks actions; persistent Deny by default, explicit Allow with per-session/global limits and owned cancellation; never focus or activate the app. |
| OSC 1337 Button | inline copy/custom controls | `user-actionable` fixed-action subset | Four-cell theme-derived controls; explicit copy of retained block text or exact `CSI ? 1337 ; code ~`; stale IDs fail closed. |

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
- Flutter UI regression tests must cover visible clipboard-copy feedback and
  paste-request prompts before any desktop smoke is treated as evidence.

## P2/P3 Implementation Baseline

- Parser-side support has event concepts for cwd, shell integration markers,
  zones, user variables, remote host transitions, badges, notifications, and
  progress.
- The native session path now bridges those parser events into typed native
  session events and Flutter session/productivity/policy state for xterm
  profiles. VT220 profiles ignore promoted OSC session metadata.
- Existing Flutter surfaces are reused: shell status bar cwd/health chips,
  shell productivity reducers, workspace same-cwd actions, notification policy
  and dispatcher, tab/pane title surfaces, and local terminal verification
  records.

## P2 Scope: Shell Context and Session Metadata

P2 turns OSC shell-context sequences into quiet, pane-scoped metadata. The user
should understand "where this pane is" and get better prompt/command actions,
but Ianvs must not pretend a remote path is a local filesystem path.

### P2-A Current Directory

| OSC | Payload | Product state | Implementation target |
| --- | --- | --- | --- |
| OSC 7 | `file://host/path` | current directory plus optional host/user | Drain parser `CwdChanged` into session shell context. |
| OSC 1337 CurrentDir | iTerm-style directory payload | current directory | Parse to the same cwd event model as OSC 7. |

Interaction:

- The status bar shows the shortest useful cwd crumb for the active pane.
- Hovering the crumb shows the full sanitized path and source: local shell
  integration or remote-reported shell integration.
- Copying the path is explicit from the directory affordance; it never opens,
  reveals, or navigates the filesystem automatically.
- When cwd metadata is missing, stale, or unavailable, existing shell-health
  states stay visible: waiting, partial, or active. No modal prompt appears.
- Duplicate tab/split may inherit cwd only when the cwd is local or has no
  remote host marker. Remote cwd falls back to profile/default cwd with an
  explainable disabled reason.

Implementation:

- Reuse parser-side OSC 7 support and add OSC 1337 `CurrentDir=` parsing if it
  is not already present.
- Bridge `CwdChanged` from native terminal events into a typed Flutter session
  shell-context event, not through ad hoc status text.
- Merge cwd into `TerminalShellIntegrationSnapshot.currentDirectory` and the
  shell productivity reducer's current cwd/recent-directory state.
- Gate surfacing on `TerminalProfile.shellIntegration.enabled` and xterm
  emulation. VT220 profiles ignore these OSC events.
- Deduplicate repeated cwd values and bound recent-directory history.

Policy and trust:

- Accept only `file://` current-directory payloads with absolute paths.
- Decode percent-encoding, trim whitespace, strip control characters, and cap
  path/host/user length before storing or displaying.
- Treat non-local hostnames as remote context. Remote context may label the
  pane, but it must not enable local file reveal, local cwd launch inheritance,
  or automatic profile switching that depends on local-only paths.

### P2-B Prompt, Command, and Output Zones

| OSC | Marker | Product state | Implementation target |
| --- | --- | --- | --- |
| OSC 133;A | prompt start | prompt mark | Bridge to shell productivity prompt marks. |
| OSC 133;B | command start | command zone start | Bridge zone open and command metadata. |
| OSC 133;C | command executed | output range start | Bridge output range start. |
| OSC 133;D | command finished/exit | output range close, exit code | Bridge command-finished event and zone close. |

Interaction:

- Prompt navigation, select/copy last command output, and block-scoped search
  use these marks when available.
- If OSC 133 data is incomplete, actions are disabled with the existing
  shell-integration unavailable reason rather than failing after invocation.
- The terminal surface should not add decorative command cards for this tier.
  P2 supplies reliable zones; command-block UI remains a separate product
  decision.
- Alt-screen applications should not create user-visible prompt/output zones.

Implementation:

- Reuse parser `ShellIntegrationEvent`, `ZoneOpened`, and `ZoneClosed` events.
- Emit a typed native session event carrying event type, command, exit code,
  timestamp, cursor line, and zone row range when present.
- Update `TerminalShellIntegrationSnapshot.promptMarks`, `lastCommand`,
  `lastExitCode`, and productivity command-output ranges from one reducer path.
- Keep row/range data pane-scoped so split panes cannot leak prompt marks into
  the wrong session.

Policy and trust:

- Strip controls from command labels before storing them in recent commands or
  showing them in menus.
- Bound stored prompt marks and output ranges; evict marks when scrollback is
  cleared or zones scroll out.
- Shell-provided command text is metadata, not an instruction. Clicking a
  command history item must use the existing explicit send/paste policy path.

### P2-C Remote Host and User Variables

| OSC | Payload | Product state | Implementation target |
| --- | --- | --- | --- |
| OSC 1337 RemoteHost | `user@host` or `host` | remote identity | Bridge into shell context and remote indicator. |
| OSC 1337 SetUserVar | `name=base64(value)` | allowlisted custom metadata | Store only allowlisted, capped values. |

Interaction:

- A remote indicator appears beside the directory or shell-health chip when the
  active pane reports a non-local host.
- Tooltip copy should state the reported identity and that local path actions
  are disabled for remote context.
- User variables are not shown raw in the primary status bar. Only approved
  keys may appear in a compact inspector or future status item.

Implementation:

- Bridge parser `RemoteHostTransition`, `EnvironmentChanged`, and
  `UserVarChanged` events into the same session shell-context stream.
- Keep local values and reported remote values separate in the session model:
  `currentDirectory`, `hostname`, `username`, and `userVars`.
- Add an allowlist for user variables before any value reaches primary UI.

Policy and trust:

- Filter localhost aliases and empty host/user values.
- Cap names and values, reject binary/control-heavy values, and avoid writing
  full user variables to diagnostics unless redaction explicitly permits it.
- User variables must never affect local process launch, file opening, or shell
  command execution without a later explicit product decision.

## P3 Scope: Status, Notification, and Progress

P3 turns OSC status signals into low-noise session feedback. The default
experience should be in-window and attributable to a pane. System notifications
must reuse existing notification policy instead of bypassing it.

### P3-A Notifications

| OSC | Payload | Product state | Implementation target |
| --- | --- | --- | --- |
| OSC 9 | terminal notification | notification intent | Normalize to a session notification event. |
| OSC 777 | iTerm notification variants | notification intent | Normalize title/body/action fields. |
| OSC 99 | Kitty notification lifecycle and reports | bounded notification intent plus fixed user-action report | Correlate by session/ID and expose only label-only buttons and fixed report grammar. |

Interaction:

- Default display is an in-window toast or status chip attached to the session,
  with the session title as source context.
- System notification delivery is allowed only when the existing notification
  preference and focus policy allow it.
- Clicking a notification focuses the source session. It must not execute shell
  actions, open links, or replay OSC-provided commands.
- OSC 99 `a=report` may return only the fixed activation or one-based button
  response after an explicit in-window gesture. `a=focus` never focuses the app
  or pane by itself.
- Dismissal and tracked positive expiry return the fixed OSC 99 close shape only
  when `c=1`; child-issued close never causes a report loop.
- Duplicate or burst notifications collapse into one visible item with a count.
- Muted, blocked, or permission-denied notifications surface the existing
  visible notification failure state instead of disappearing silently.

Implementation:

- Drain parser notification buffers into typed native session events.
- Route OSC-originated notifications through `LocalTerminalNotificationPolicy`
  and `LocalTerminalNotificationDispatcher`.
- Store only a bounded recent notification list per session for UI inspection
  and diagnostics.
- Add per-session rate limiting before any system notification bridge call.

Policy and trust:

- Strip controls, cap title/body length, and normalize whitespace.
- Treat URLs in notification bodies as text unless a future link affordance
  explicitly validates and exposes them.
- Label remote-reported notifications with the remote host when known.
- Treat OSC 99 button payloads as capped labels, never commands. Re-resolve the
  current session and notification before writing a report so stale menus and
  cross-session identity reuse fail closed.

### P3-B Progress

| OSC | Payload | Product state | Implementation target |
| --- | --- | --- | --- |
| OSC 9;4 | state plus percent | primary session progress | Bridge to active progress state. |
| OSC 934 | named progress bars | bounded named progress list | Bridge set/remove/all-clear events. |

Interaction:

- The active pane can show one compact progress chip in the status bar.
- Determinate progress shows percent; indeterminate progress shows a spinner or
  pulsing state; warning/error states use the existing semantic status colors.
- Hovering the chip shows full label, state, percent, and source session.
- Clicking the chip focuses the session or opens a lightweight progress list if
  multiple named bars are active.
- Progress completion or clear hides the chip after a short grace period so the
  user can see that work finished.

Implementation:

- Drain parser `ProgressBarChanged` and OSC 9;4 progress state into a typed
  `TerminalSessionProgressEvent`.
- Keep one primary progress value plus a capped map of named progress bars per
  session.
- Coalesce fast updates so progress cannot force excessive Flutter rebuilds.
- Keep indeterminate progress state visible without synthesizing a fake `0%`
  value, and keep CR/EL inline spinner repaint coalescing in native frame
  diffs.

Policy and trust:

- Cap named progress IDs and labels, strip controls, and limit the number of
  active named bars retained per session.
- Progress is presentation state only; it must not affect process lifecycle,
  command completion, or exit-code reporting.

### P3-C Badge

| OSC | Payload | Product state | Implementation target |
| --- | --- | --- | --- |
| OSC 1337 SetBadgeFormat | base64 badge format | tab/pane badge text | Bridge `BadgeChanged` to session UI state. |

Interaction:

- Badge text appears as a short chip near the tab or pane title, not inside the
  terminal grid.
- Tooltip shows the full sanitized badge text and source session.
- Clearing the badge removes the chip. Invalid badge payloads are ignored.
- Badge text should be secondary to explicit user labels; it cannot replace the
  tab title unless the user chooses that in a later setting.

Implementation:

- Reuse parser-side badge decoding/evaluation.
- Bridge `BadgeChanged` into tab/pane state and cap the displayed label.
- Add widget coverage for set, update, clear, truncation, and accessibility
  semantics.

Policy and trust:

- Strip controls and cap decoded text before it reaches Flutter UI.
- Do not persist OSC badge text across app restarts unless a later product
  setting explicitly opts into it.

## P2/P3 Delivery Sequence

1. P2-A: Cwd/current-directory events are bridged into pane shell context,
   status-bar cwd, recent directories, and local/remote duplicate safeguards.
2. P2-B: OSC 133 markers are bridged into shell productivity prompt marks and
   command metadata. Alt-screen OSC 133 events are suppressed, and prompt marks
   are cleared when zones scroll out or local scrollback is cleared.
3. P2-C: Remote identity and allowlisted user variables are bridged without
   enabling local filesystem actions for remote-reported paths.
4. P3-A: Notifications route through the existing notification preference,
   focus, rate-limit, failure-feedback, and dispatcher policy path.
5. P3-B: Progress state has a primary chip, capped named progress list, burst
   coalescing, completion grace, and clear behavior.
6. P3-C: Badge state appears as capped tab/status chips with update, clear,
   tooltip, and accessibility coverage.

## Deferred Work

- Later product decision: OSC 1337 RequestUpload and any other outgoing file
  transfer. Incoming non-inline download is supported by Phase 28's explicit
  Save boundary.
- OSC 1337 RequestAttention is no longer deferred: Phase 30 supports its closed
  four-action set behind persistent policy, rate limits, owned AppKit request
  IDs and bounded cursor-local rendering. Focus stealing, Notification Center
  payloads and arbitrary attention actions remain unauthorized.
- OSC 99 report-only interactions are no longer deferred: Phase 31 supports
  canonical/default IDs, five label-only buttons, fixed activation/button/close
  reports and alive queries. Protocol focus, sound, icons, urgency, arbitrary
  callback payloads and command execution remain unauthorized.
- OSC 1337 Button is no longer deferred: Phase 32 supports documented copy and
  custom controls, custom invalidation, explicit retained-block copy and only
  the fixed custom CSI reply. Icon names remain presentation-only and every
  action revalidates a monotonic live session button ID.
- Not P0/P1: public custom OSC parser hooks, remote identity, full file
  transfer, notification spam defaults.
- Not P2/P3: SFTP/SSH session management, remote file browsing, automatic
  command execution from OSC metadata, custom public OSC plugin hooks, and
  persisted OSC-driven badges/user variables.

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
cd example && flutter test test/shell/shell_screen_phase4_test.dart --plain-name "OSC 52"
```

The OSC 52 UI gate includes named widget regressions:

- `OSC 52 blocked copy shows visible status and feedback`
- `OSC 52 ask policy prompts before paste read`

P2/P3 implementation gates when promoted:

```bash
cargo test --manifest-path native/core/Cargo.toml --test session_test osc7
cargo test --manifest-path native/core/Cargo.toml --test session_test osc133
cargo test --manifest-path native/core/Cargo.toml --test session_test osc1337
cargo test --manifest-path native/core/Cargo.toml --test session_test osc9
cargo test --manifest-path native/core/Cargo.toml --test session_test osc777
cargo test --manifest-path native/core/Cargo.toml --test session_test osc934
cargo test --manifest-path native/core/Cargo.toml --test session_test inline_progress
cd example && flutter test test/shell/shell_screen_phase4_test.dart --plain-name "OSC indeterminate progress shows state without fake percent"
cd example && flutter test test/sessions/session_controller_test.dart --plain-name "shell context"
cd example && flutter test test/productivity/shell_productivity_reducer_test.dart
cd example && flutter test test/shell/shell_screen_phase4_test.dart --plain-name "notification"
```

Manual/computer acceptance:

Desktop smoke remains supplemental for host integration details that widget
tests cannot prove, such as the real system clipboard bridge, OS-level focus,
and native notification delivery.

- Send OSC 12 in the app and verify the cursor visibly changes.
- Send OSC 8 and verify tapping opens the expected URL only on deliberate tap.
- Send OSC 52 copy/paste probes with policy enabled and disabled.
- Send OSC 7/1337 CurrentDir and verify the active pane cwd chip, tooltip, copy
  affordance, and remote/local fallback behavior.
- Send OSC 133 prompt/command/output markers and verify prompt navigation and
  last-output actions become available only for that pane.
- Send OSC 9/777 notification payloads and verify in-window default display,
  policy-gated system notification delivery, rate limiting, and blocked-state
  feedback.
- Send a chunked OSC 99 notification with `a=report:c=1:p=buttons`, verify the
  keyboard-native in-window menu, exact activation/button/close response bytes,
  stale-action rejection, and continued terminal input. Repeat `a=focus` while
  another app is foreground and verify Ianvs does not activate itself.
- Send OSC 9;4/934 progress updates and verify status-bar progress display,
  named progress list, completion grace, and clear behavior.
- Send OSC 1337 SetBadgeFormat and verify tab/pane badge set, update, clear,
  truncation, and tooltip behavior.
- With attention policy Allow, send OSC 1337 RequestAttention fireworks,
  once/yes/no and verify the cursor-local effect, bounded Dock attention and
  cancellation while the shell remains interactive and the app never steals
  focus. Repeat with Deny and verify no new host effect occurs.

## Done Criteria

P0/P1 implementation is done when:

- This matrix matches current code and tests.
- The implemented P0/P1 rows have automated evidence.
- Deferred rows remain explicit and do not silently enter product scope.
- Supplemental desktop smoke may record real host clipboard, focus, and native
  notification behavior, but it is not the primary P0/P1 closure gate.

P2/P3 design is done when:

- Each promoted OSC family has a product state, implementation target,
  user-facing behavior, policy boundary, and acceptance path in this document.
- The design distinguishes parser support from native-session/Flutter bridging.
- Remote context, notifications, progress, badges, and user variables are scoped
  to local-first Ianvs behavior with explicit trust and spam controls.
