# Local Terminal Verification Failure Triage Log

Date: 2026-05-16

Purpose: provide a single place to record the first blocking failure from each
verification batch, the likely owning milestone, and the smallest next fix task.

This log is empty until a verification batch actually fails. It is not passing
evidence and must not be used to close T-169.

## Triage Rule

When a verification batch fails:

1. Stop the closure attempt at the first blocking failure.
2. Record the failure here.
3. Record the same failed gate in
   `LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`.
4. Create or update the smallest follow-up task needed to fix the blocker.
5. Re-run only the relevant failed batch after the fix, then continue the
   normal sequence.

Do not continue to claim closure while any row in this log remains unresolved.

## Failure Rows

| ID | Batch | Gate | Command or scenario | Exit/status | First blocking failure | Likely owner | Next fix task | Resolution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| F-20260516-001 | `broader` | `unitTests` / `widgetTests` | `bash tools/local_terminal_verification_capture.sh run all-automated` -> broader step `flutter test example/test` | failed, then resolved | `shell_screen_phase3_test.dart: editing a profile in the GUI only affects new sessions` could not tap `profile-entry-default` after reopening Profiles because the menu item and entry were outside the visible test viewport. | Shell profiles UI test / P1 command menu surface | Added `ensureVisible(find.text('Profiles...'))` and `ensureVisible(find.byKey(const Key('profile-entry-default')))` before the second Profiles open/select path in `example/test/shell/shell_screen_phase3_test.dart`. | resolved by `build/local-terminal-verification/20260516T171406Z-broader`: exit 0; `All tests passed!` |
| F-20260516-002 | `integration` | `integrationTests` | `bash tools/local_terminal_verification_capture.sh run integration` before batch correction | failed, then resolved | The batch ran `flutter test -d macos example/integration_test/...` from the workspace root, so the app plugin registrar was not active and real PTY loading could not find `libianvs_core.dylib`. | Integration batch environment / T-169 verification tooling | Build debug `native/core`, run integration tests from `example`, set `IANVS_CORE_LIB`, and run the two integration files sequentially. | resolved by `build/local-terminal-verification/20260516T171644Z-integration`: exit 0 |
| F-20260516-003 | `integration` | `integrationTests` | corrected integration batch before smoke-test visibility fix | failed, then resolved | `ianvs_terminal_smoke_test.dart: profiles sheet can open another profile as a new tab` tapped `Profiles...` while the menu item was below the 800x600 test viewport, so `profiles-sheet` was not opened. | Integration smoke test / P1 command menu surface | Added `ensureVisible(find.text('Profiles…'))` before tapping the Profiles menu item in `example/integration_test/ianvs_terminal_smoke_test.dart`. | resolved by `build/local-terminal-verification/20260516T171644Z-integration`: smoke 4/4 and real PTY 7/7 passed |
| F-20260516-004 | manual product app | `manualPasteFocusSafety` | manual multiline paste path | failed, then resolved | Product paste path sent multiline clipboard text without showing the policy confirmation dialog required by the paste decision model. | P4 policy / ShellScreen paste dispatch | Routed `_pasteToSession` through `LocalTerminalPasteDecisionResolver`, added confirmation dialog, and added focused phase4 widget coverage. | resolved by focused `flutter test example/test/shell/shell_screen_phase4_test.dart` 9/9 and latest `build/local-terminal-verification/20260516T171406Z-broader` |
| F-20260516-005 | manual product app | `manualMultipaneBehavior` | manual command-menu `Zoom active pane` path | failed, then resolved | The zoom action updated `_zoomedPaneSessionId`, but `_buildTerminalWorkspace` still rendered all `activeTab.effectivePanes`, so no visible single-pane zoom occurred. | P2 workspace / ShellScreen pane rendering | Updated `_buildTerminalWorkspace` to render only the zoomed pane when present, and added focused phase4 zoom/unzoom widget coverage. | resolved by focused `flutter test example/test/shell/shell_screen_phase4_test.dart` 9/9 and latest `build/local-terminal-verification/20260516T171406Z-broader` |
| F-20260516-006 | manual/product policy audit | `manualHotkeyWindowFailurePath` | hotkey-window platform failure path | failed, then resolved | The product invoked the window bridge directly, so an unregistered hotkey-window status could become a silent no-op instead of visible failure feedback. | P4 policy / WindowBridge integration | Added `_toggleHotkeyWindowWithFeedback`, checked `WindowBridge.hotkeyStatus()`, showed `Hotkey window unavailable` SnackBar on unregistered status or platform error, and added focused phase4 failure-path coverage. | resolved by focused `flutter test example/test/shell/shell_screen_phase4_test.dart` 9/9 and latest `build/local-terminal-verification/20260516T171406Z-broader` |
| F-20260627-001 | `all-automated` -> `broader` | `unitTests` / `widgetTests` | `bash tools/local_terminal_verification_capture.sh run all-automated` | failed, then resolved | `shell_screen_architecture_test.dart` read `lib/features/shell/shell_screen.dart` from the repo root and failed with `PathNotFoundException`; `shell_screen_phase1b_test.dart` found readable-width overflow tabs compressed to about 105 px instead of the expected 180 px baseline. | Verification tooling and P2 workspace tab chrome | Made the architecture test resolve both repo-root and `example/` working directories; changed tab overflow capacity to preserve regular 180 px tabs when all tabs cannot fit compactly, while retaining compact-before-overflow behavior. | resolved by focused reruns and `build/local-terminal-verification/20260627T172040Z-all-automated`: exit 0 |
| F-20260627-002 | `integration` | `integrationTests` | `bash tools/local_terminal_verification_capture.sh run integration` | failed, then resolved | `ianvs_terminal_smoke_test.dart: closing tabs reaches the empty state and recovers via New Tab` tapped the `Close Local Shell` tooltip at a point obscured by tab chrome/list hit targets, so the last tab did not close. | Integration smoke / P2 workspace close-tab path | Changed the smoke test to close the active tab with the product Command-W shortcut instead of a hover-dependent tooltip tap. | resolved by focused smoke rerun 4/4 and `build/local-terminal-verification/20260627T172908Z-integration`: exit 0 |
| F-20260627-003 | `integration` | `integrationTests` | `bash tools/local_terminal_verification_capture.sh run integration` | failed, then resolved | `real_pty_acceptance_test.dart: real PTY wrapped trigger output is captured as a logical row` used an early viewport column measurement capped near 200 and required `row.wrapped == true`; after resize, output could fit without the wrapped flag or be reassembled as a logical row by the backend. | Integration real PTY / notification and captured-output verification | Increased the forced prefix length to survive resize timing and accepted either wrapped rows or reassembled overwide logical rows before verifying trigger notification and captured output. | resolved by focused real PTY rerun and `build/local-terminal-verification/20260627T172908Z-integration`: exit 0 |

## Owner Guide

| Failure area | Likely owner |
| --- | --- |
| Formatting or analyzer syntax/type issue in shell completion/evidence code | P1 / completion diagnostics |
| Action id, shortcut, command menu, production callback, executor, runtime adapter failure | P1 action/config |
| Tab, pane, split, focus, resize, swap, zoom, close/reopen, layout failure | P2 workspace |
| Prompt navigation, search, command output, recent items, read-only, scrollback failure | P3 productivity |
| Paste policy, paste history, OSC52, notification, hotkey-window failure | P4 policy |
| Theme, layout template, pane visual policy, scrollback export, graphics/timestamp/command-pane failure | P5 visual |
| Verification evidence, recorder, ledger, backlog gate, completion report failure | T-169 verification/closure |
| Manual local shell, paste/focus, multipane, notification, hotkey observation failure | Manual/integration gate owner plus relevant P2-P5 area |

## Failure Record Template

Copy this block when a batch fails:

```text
ID:
Batch:
Gate:
Command or scenario:
Date/time:
Working directory:
Exit/status:
First blocking failure:
Output excerpt:
Likely owner:
Affected files or surfaces:
Next fix task:
Resolution:
```

## Resolution Rule

A failure row can move to `resolved` only after:

- The smallest fix has landed.
- The failed batch has been re-run.
- The rerun output is recorded in the evidence ledger.
- No replacement blocker appears in the same gate.

If a fix reveals a different blocker, add a new row instead of overwriting the
original failure.

## Current Status

Verification batches have been rerun. The latest full automation attempt passed
in `build/local-terminal-verification/20260627T172040Z-all-automated`.

The integration batch was then rerun and passed in
`build/local-terminal-verification/20260627T172908Z-integration`.

No unresolved automated, integration, or manual product failure row remains.
Manual/integration-backed verification rows are recorded as passed in the
evidence ledger. Ledger-to-code evidence conversion is represented by
`LocalTerminalVerificationPlanRecords.latestPassed()`.
