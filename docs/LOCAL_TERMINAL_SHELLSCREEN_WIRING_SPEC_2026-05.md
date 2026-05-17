# Local Terminal ShellScreen Wiring Spec

Date: 2026-05-16

Purpose: define the concrete production wiring surface for moving the P0-P5
foundation from callback contracts into real `ShellScreen`, `SessionController`,
settings, export, and runtime behavior.

This spec is the execution map for T-164 through T-168. It does not claim that
the wiring is complete.

## Primary wiring entry point

Use `LocalTerminalProductionWiringBundle.fromDomainCallbacks(...)` as the
preferred assembly point.

Production code should populate domain callbacks first:

| Domain | Callback type | Closure task |
| --- | --- | --- |
| P2 workspace | `LocalWorkspaceProductionCallbacks` | T-165 |
| P3 productivity | `ShellProductivityProductionCallbacks` | T-166 |
| P4 policy | `LocalTerminalPolicyProductionCallbacks` | T-167 |
| P5 visual | `LocalTerminalVisualProductionCallbacks` | T-168 |

Then route those callbacks into P1 action wiring through
`LocalTerminalActionDomainRouter` inside the bundle. This prevents duplicate
registration between action callbacks and domain callbacks.

## P1 action wiring

| Action surface | Production source | Required evidence |
| --- | --- | --- |
| Command menu action selection | `ShellScreen` command menu dispatch | Dispatches through production wiring bundle rather than direct private callbacks. |
| Keyboard shortcuts | Shortcut bridge / key event path | Shortcut-triggered actions use the same action production wiring as menu actions. |
| Runtime external executor | Action runtime dispatch path | Runtime-facing dispatch receives `ShellActionBindingResult` from production adapter/executor. |
| Diagnostics | Command menu or developer surface | Blocking binding diagnostics and dispatch reports are visible or inspectable. |

Closure evidence:

- `ShellActionProductionClosureManifest.canClose == true`.
- `ShellActionProductionWiringReport` has no blocking items.
- T-164 is marked verified in `LocalTerminalRealWiringBacklogEvidence`.

## P2 workspace callback map

| Callback | Production target | Notes |
| --- | --- | --- |
| `newTab` | Existing new-tab creation path | Must preserve current default-profile/session behavior. |
| `closeTab` | Existing tab close path | Closing last tab must reach the intended empty state. |
| `reopenClosedTab` | Reopen/undo tab stack | Must not restore remote concepts. |
| `duplicateCurrentCwd` | New tab from active pane cwd | Requires shell integration cwd or clear unavailable state. |
| `splitRight` / `splitDown` | Existing split creation paths | Must preserve focus handoff. |
| `closePane` / `reopenClosedPane` | Pane close/undo behavior | Must preserve focus fallback. |
| `focusNextPane` / `focusPreviousPane` / `focusPaneDirection` | Pane focus methods | Must not write input to terminal. |
| `resizePane` | Pane resize logic | Must preserve resize bounds. |
| `swapPane` | Pane swap/move logic | Must preserve active pane identity. |
| `zoomPane` | Pane zoom/unzoom logic | Must be reversible. |
| `saveLayout` / `restoreLayout` | Local workspace layout persistence | Must not serialize SSH/remote/serial/SFTP state. |

Closure evidence:

- `LocalWorkspaceProductionWiring.missingRequiredOperations` is empty for the
  supported P2 action set.
- P2 `LocalTerminalDomainWiringSummary` is ready.
- T-165 is marked verified in `LocalTerminalRealWiringBacklogEvidence`.

## P3 productivity callback map

| Callback | Production target | Notes |
| --- | --- | --- |
| `nextPrompt` / `previousPrompt` | Prompt mark navigation | Disabled state must be visible when shell integration is off. |
| `selectCommandOutput` / `copyCommandOutput` / `copyLastCommandOutput` / `saveCommandOutput` | Command output range handling | Must use real terminal ranges. |
| `openRecentDirectory` | Recent directory picker/open path | Requires cwd/recent-dir shell integration data. |
| `searchScrollback` / `nextSearchMatch` / `previousSearchMatch` / `clearSearch` | Existing search controller/UI | Must preserve focus and selection behavior. |
| `clearScrollback` | Terminal clear scrollback path | Must call real terminal controller behavior. |
| `toggleReadOnly` | Send-text/paste guard state | Must block all text send paths when enabled. |
| `jumpToCommandBlock` | Block/prompt scoped navigation | Can remain unavailable until block UI is production wired. |

Closure evidence:

- `ShellProductivityProductionWiring.missingRequiredOperations` is empty for the
  supported P3 action set.
- Shell-integration-disabled cases produce unavailable behavior, not exceptions.
- T-166 is marked verified in `LocalTerminalRealWiringBacklogEvidence`.

## P4 policy callback map

| Callback | Production target | Notes |
| --- | --- | --- |
| `copy` / `paste` / `pasteHistory` / `pasteAsBracketed` | Clipboard and paste paths | Must route through paste policy before sending text. |
| `confirmLargePaste` / `confirmMultilinePaste` | Paste confirmation UI | Must be visible before paste proceeds. |
| `recordPasteHistory` | Paste history persistence | Must respect configured size/disabled state. |
| `osc52Copy` | OSC 52 policy path | Must preserve emulation/profile constraints. |
| `emitBellNotification` / `emitCommandFinishedNotification` / `emitActivityNotification` / `emitSilenceNotification` / `emitPromptReadyNotification` | Notification dispatcher | Must honor focus and target policy. |
| `toggleHotkeyWindow` / `applyHotkeyWindowConfig` / `recordHotkeyWindowFailure` | `WindowBridge` and failure state | Platform/permission failures must be visible. |

Closure evidence:

- `LocalTerminalPolicyProductionWiring.missingRequiredOperations` is empty for
  the supported P4 action set.
- Read-only, large paste, multiline paste, and notification focus-policy cases
  are verified.
- T-167 is marked verified in `LocalTerminalRealWiringBacklogEvidence`.

## P5 visual callback map

| Callback | Production target | Notes |
| --- | --- | --- |
| `openThemePicker` / `applyTheme` / `importThemePreset` / `exportThemePreset` | Theme settings/UI and repository | Must apply at the intended profile/session boundary. |
| `applyLayoutTemplate` / `saveLayoutTemplate` / `exportLayoutTemplate` | Layout template repository/applier | Must produce local workspace layouts only. |
| `exportScrollback` / `exportCommandOutput` | Scrollback export path | Must use real terminal data and destination policy. |
| `applyPaneVisualPolicy` / `applySplitDividerPolicy` | Shell/workspace visual state | Must preserve existing terminal rendering contracts. |
| `configureGraphicsStorage` / `recordGraphicsEviction` | Graphics storage policy | Must not require renderer rewrite before core closure. |
| `toggleTimestamps` / `toggleCommandPane` / `openScrollbackEditor` | Advanced local UI | Can remain optional if explicitly out of the required P5 action set. |

Closure evidence:

- `LocalTerminalVisualProductionWiring.missingRequiredOperations` is empty for
  the supported P5 action set.
- Advanced optional operations are either verified or explicitly excluded from
  required closure.
- T-168 is marked verified in `LocalTerminalRealWiringBacklogEvidence`.

## Verification wiring

After production callbacks are populated:

1. Build `LocalTerminalProductionWiringBundle`.
2. Build `LocalTerminalRealWiringBacklogEvidence` from T-164 through T-169 real
   status.
3. Build `LocalTerminalCompletionEvidenceReport`.
4. Update `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` with real
   command/manual evidence.

The objective can close only when `LocalTerminalCompletionEvidenceReport` reports
`canCloseObjective == true`.

## Current status

Spec created. Production callbacks are not populated yet, and verification has
not been run.
