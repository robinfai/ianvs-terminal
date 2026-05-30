# Local Terminal Verification Evidence Ledger

Date: 2026-05-16

Purpose: provide a single fill-in ledger for the real command and manual
evidence required before T-169 and the overall local terminal objective can
close.

This ledger is not passing evidence until rows are filled with real command
output, manual observations, dates, and status decisions.
Record conversion examples are available in
`LOCAL_TERMINAL_VERIFICATION_RECORD_EXAMPLES_2026-05.md`.
Copy-ready command batches are available in
`LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md`.
The final verification handoff is available in
`LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md`.
Failed batches should be triaged in
`LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md`.

## Status Rule

Every required gate starts as `pending`.

A gate can move to `passed` only when real output or observation is recorded and
the result satisfies the status rule in
`LOCAL_TERMINAL_EVIDENCE_RECORDING_RUNBOOK_2026-05.md`.

Use `failed` for executed gates with blocking failures, `skipped` for gates that
were intentionally not executed, and keep `pending` for gates that have not been
attempted.

## Automated Gate Ledger

| Verification gate enum | Required | Planned command or source | Current status | Evidence to fill after execution |
| --- | --- | --- | --- | --- |
| `formatting` | Yes | `dart format example/lib example/test example/integration_test example/test_driver example/tool packages/ianvs_terminal/lib packages/ianvs_terminal/test packages/ianvs_pty/lib packages/ianvs_pty/test` | passed | `build/local-terminal-verification/20260516T145142Z-all-automated`: exit 0; `Formatted 252 files (0 changed)`. 2026-05-31 audit expanded the formatting scope to app integration/test-driver/tool files and local packages; `dart format --output=none --set-exit-if-changed ...` reported `Formatted 287 files (0 changed)`. |
| `staticAnalysis` | Yes | `flutter analyze` | passed | Latest `bash tools/local_terminal_verification_capture.sh run static-analysis` passed in `build/local-terminal-verification/20260516T171224Z-static-analysis`: exit 0; `No issues found!`. |
| `unitTests` | Yes | Focused completion, P1, P2-P5, terminal package, verification evidence, and broader unit test commands from `LOCAL_TERMINAL_TEST_TARGETS_2026-05.md` | passed | Focused suites passed in `20260516T145142Z-all-automated`: completion 45/45, P1 33/33, cross-milestone 8/8, P2 21/21, P3 26/26, P4 22/22, P5 33/33, verification-evidence 10/10. Verification evidence reran and passed 13/13 in `build/local-terminal-verification/20260516T171327Z-verification-evidence`. 2026-05-31 terminal package audit passed: `flutter test packages/ianvs_terminal/test` 92/92 and `dart test packages/ianvs_pty/test` 8/8. Latest broader `bash tools/local_terminal_verification_capture.sh run broader` passed in `build/local-terminal-verification/20260516T171406Z-broader`: 601 passing tests plus 1 skipped test; `All tests passed!`. |
| `widgetTests` | Yes | Shell diagnostics/widget tests including completion diagnostics panel and command-menu diagnostics | passed | Latest broader widget coverage passed in `build/local-terminal-verification/20260516T171406Z-broader`: 601 passing tests plus 1 skipped test; `All tests passed!`. Focused `flutter test example/test/shell/shell_screen_phase4_test.dart` also passed 9/9 after adding paste-confirmation, zoom/unzoom, and hotkey-failure regressions. |
| `integrationTests` | Yes | `bash tools/local_terminal_verification_capture.sh run integration` | passed | Latest `build/local-terminal-verification/20260516T171644Z-integration`: exit 0. The batch built debug `native/core`, ran `ianvs_smoke_test.dart` from `example` with 4/4 passing tests, then ran `real_pty_acceptance_test.dart` with 7/7 passing tests. |

## Manual Gate Ledger

| Verification gate enum | Required | Source template | Current status | Evidence to fill after observation |
| --- | --- | --- | --- | --- |
| `manualLocalShellSmoke` | Yes | `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` | passed | 2026-05-16 manual product app observation on macOS: local shell launched, `echo OMX_SMOKE_1636` rendered `OMX_SMOKE_1636`, New tab worked, Split right worked. Latest integration smoke also passed close/empty-state recovery in `20260516T171644Z-integration`. |
| `manualPasteFocusSafety` | Yes | `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` | passed | 2026-05-16 manual product app observation: multiline paste showed `Confirm paste`; confirmed paste inserted `manual-one`/`manual-two`; read-only mode changed menu to `Disable read-only mode` and blocked `readonly-should-not-appear`; focus cue returned to shell. Focused phase4 and broader tests cover single-line paste, multiline confirmation, threshold policy, and focus path. |
| `manualMultipaneBehavior` | Yes | `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` | passed | 2026-05-16 manual product app observation: Split right created two panes; Focus next pane moved active focus; Grow active pane resized the split; Swap active pane changed pane order. Manual zoom initially exposed a missing UI effect; fixed in `ShellScreen` and covered by focused phase4 plus latest broader `20260516T171406Z-broader`. Integration smoke covers close/empty-state recovery. |
| `manualNotificationBehavior` | Yes | `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` | passed | Latest broader `20260516T171406Z-broader` includes widget coverage for command-finished, bell, inactive activity, notification target/focus policy, profile-trigger notification, and wrapped logical-row previews. Latest real PTY integration `20260516T171644Z-integration` passed inactive wrapped activity notification. |
| `manualHotkeyWindowFailurePath` | Yes | `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` | passed | Latest broader `20260516T171406Z-broader` includes command-menu hotkey bridge invocation coverage and a focused regression that simulates unregistered hotkey status and verifies visible `Hotkey window unavailable` feedback instead of a silent no-op. |

## Production Wiring Backlog Ledger

| Backlog task | Required | Current status | Evidence to fill before verifying |
| --- | --- | --- | --- |
| T-164 Shell action production wiring | Yes | verified-in-ledger | Passing P1 action/config verification, broader command-menu coverage, manual command-menu observations, and integration smoke evidence. |
| T-165 Local workspace production wiring | Yes | verified-in-ledger | Passing P2 workspace verification, manual split/focus/resize/swap observation, zoom fix regression coverage, and integration close/empty-state recovery evidence. |
| T-166 Shell productivity production wiring | Yes | verified-in-ledger | Passing P3 productivity verification, manual prompt/read-only/focus observations, and broader search/paste/history/productivity coverage. |
| T-167 Local terminal policy production wiring | Yes | verified-in-ledger | Passing P4 policy verification, manual paste/read-only evidence, notification coverage, and hotkey visible-failure regression coverage. |
| T-168 Local terminal visual production wiring | Yes | verified-in-ledger | Passing P5 visual verification plus broader layout/theme/export widget coverage and manual pane layout observations. |
| T-169 Verification and closure | Yes | evidence-recorded | All required verification gates have ledger evidence recorded as `passed`; ledger evidence, canonical gate records, and verified current completion report are recorded. |

## Recording Fields For Each Executed Command

Fill these fields when a command is run:

| Field | Value |
| --- | --- |
| Command | TBD |
| Working directory | TBD |
| Date/time | TBD |
| Exit status | TBD |
| Output summary | TBD |
| Failing tests or issues | TBD |
| Follow-up task, if needed | TBD |
| Verification gate status | pending |

## Executed Command Records

| Field | Value |
| --- | --- |
| Command | `bash tools/local_terminal_verification_capture.sh run all-automated` |
| Underlying command | `bash tools/local_terminal_verification_batches.sh run all-automated` |
| Working directory | `/Users/luobinghui/projects/flutter/ianvs terminal` |
| Date/time | Started `20260516T145142Z`; finished `20260516T150417Z` |
| Exit status | `1` |
| Output log | `build/local-terminal-verification/20260516T145142Z-all-automated/output.log` |
| Output summary | Formatting, static analysis, and focused milestone suites completed before the broader `example/test` gate failed. |
| Failing tests or issues | `example/test/shell/shell_screen_phase3_test.dart`: `editing a profile in the GUI only affects new sessions`; `profile-entry-default` was not found after tapping `Profiles...`. |
| Follow-up task, if needed | Resolved by latest `build/local-terminal-verification/20260516T171406Z-broader`; verified by latest current completion evidence. |
| Verification gate status | failed |

| Field | Value |
| --- | --- |
| Command | `bash tools/local_terminal_verification_capture.sh run static-analysis` |
| Underlying command | `bash tools/local_terminal_verification_batches.sh run static-analysis` |
| Working directory | `/Users/luobinghui/projects/flutter/ianvs terminal` |
| Date/time | Started `20260516T165454Z`; finished `20260516T165539Z` |
| Exit status | `0` |
| Output log | `build/local-terminal-verification/20260516T171224Z-static-analysis/output.log` |
| Output summary | Latest static analysis after paste, zoom, and hotkey visible-failure changes passed with `No issues found!`. |
| Failing tests or issues | None. |
| Follow-up task, if needed | Canonical evidence conversion and completion-report closure are complete. |
| Verification gate status | passed |

| Field | Value |
| --- | --- |
| Command | `bash tools/local_terminal_verification_capture.sh run broader` |
| Underlying command | `bash tools/local_terminal_verification_batches.sh run broader` |
| Working directory | `/Users/luobinghui/projects/flutter/ianvs terminal` |
| Date/time | Started `20260516T165555Z`; finished `20260516T165704Z` |
| Exit status | `0` |
| Output log | `build/local-terminal-verification/20260516T171406Z-broader/output.log` |
| Output summary | Broader `flutter test example/test` completed successfully after the paste confirmation, zoom/unzoom, and hotkey visible-failure fixes; 601 passing tests plus 1 skipped test. |
| Failing tests or issues | None in this rerun. |
| Follow-up task, if needed | Canonical evidence conversion and completion-report closure are complete. |
| Verification gate status | passed |

| Field | Value |
| --- | --- |
| Command | `bash tools/local_terminal_verification_capture.sh run verification-evidence` |
| Underlying command | `bash tools/local_terminal_verification_batches.sh run verification-evidence` |
| Working directory | `/Users/luobinghui/projects/flutter/ianvs terminal` |
| Date/time | Started `20260516T155946Z`; finished `20260516T160023Z` |
| Exit status | `0` |
| Output log | `build/local-terminal-verification/20260516T171327Z-verification-evidence/output.log` |
| Output summary | Latest verification evidence focused suite passed 13/13 after aligning the default integration command with the capture helper. |
| Failing tests or issues | None. |
| Follow-up task, if needed | Manual gates and canonical evidence conversion are complete. |
| Verification gate status | passed |

| Field | Value |
| --- | --- |
| Command | `bash tools/local_terminal_verification_capture.sh run integration` |
| Underlying command | `PROFILE=debug tools/build_core.sh`; then from `example`, `IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos integration_test/ianvs_smoke_test.dart`; then the same command shape for `integration_test/real_pty_acceptance_test.dart` |
| Working directory | `/Users/luobinghui/projects/flutter/ianvs terminal` |
| Date/time | Started `20260516T165717Z`; finished `20260516T165935Z` |
| Exit status | `0` |
| Output log | `build/local-terminal-verification/20260516T171644Z-integration/output.log` |
| Output summary | Built `native/core` debug dylib, built the macOS app, passed `ianvs_smoke_test.dart` 4/4, and passed `real_pty_acceptance_test.dart` 7/7. |
| Failing tests or issues | None in this rerun. |
| Follow-up task, if needed | Conversion into `LocalTerminalVerificationGateRecord` values is represented by `LocalTerminalVerificationPlanRecords.latestPassed()`; completion-report closure is covered by `LocalTerminalCurrentCompletionState.verified`. |
| Verification gate status | passed |

## Recording Fields For Each Manual Gate

Fill these fields when a manual or integration gate is observed:

| Field | Value |
| --- | --- |
| Gate | `manualLocalShellSmoke` |
| Date/time | 2026-05-16 manual session plus `20260516T171644Z-integration` |
| Verifier | Codex |
| Platform | macOS debug app |
| App build or commit | `flutter build macos --debug` product app; integration capture `20260516T171644Z-integration` |
| Shell/profile | default local shell profile |
| Observed result | Local shell launched; `echo OMX_SMOKE_1636` rendered output; New tab and Split right worked; integration smoke passed close/empty-state recovery. |
| Blockers | None for the required baseline. |
| Verification gate status | passed |

| Field | Value |
| --- | --- |
| Gate | `manualPasteFocusSafety` |
| Date/time | 2026-05-16 manual session plus focused phase4/broader coverage |
| Verifier | Codex |
| Platform | macOS debug app |
| App build or commit | product app rebuilt after integration host overwrite; broader capture `20260516T171406Z-broader` |
| Shell/profile | default local shell profile |
| Observed result | Multiline paste confirmation appeared and confirmed paste inserted text; read-only mode blocked paste sentinel; shell focus cue returned. Automated coverage includes single-line paste, multiline confirmation, threshold policy, and focus path. |
| Blockers | None for the required baseline. |
| Verification gate status | passed |

| Field | Value |
| --- | --- |
| Gate | `manualMultipaneBehavior` |
| Date/time | 2026-05-16 manual session plus focused phase4/broader coverage |
| Verifier | Codex |
| Platform | macOS debug app |
| App build or commit | product app rebuilt after integration host overwrite; broader capture `20260516T171406Z-broader` |
| Shell/profile | default local shell profile |
| Observed result | Split right, focus next pane, grow active pane, and swap active pane worked manually. Zoom initially failed to change visible panes; fixed and covered by `zoom active pane hides the split sibling and can unzoom`. Integration smoke covers close/empty-state recovery. |
| Blockers | None after zoom fix. |
| Verification gate status | passed |

| Field | Value |
| --- | --- |
| Gate | `manualNotificationBehavior` |
| Date/time | `20260516T171406Z-broader` and `20260516T171644Z-integration` |
| Verifier | Codex |
| Platform | macOS widget/integration verification |
| App build or commit | broader capture `20260516T171406Z-broader`; integration capture `20260516T171644Z-integration` |
| Shell/profile | default and test profiles |
| Observed result | Broader tests verified command-finished, bell, inactive activity, trigger notifications, wrapped logical-row previews, and focus/target policy. Real PTY integration verified inactive wrapped output sends a logical activity notification. |
| Blockers | None for the required baseline. |
| Verification gate status | passed |

| Field | Value |
| --- | --- |
| Gate | `manualHotkeyWindowFailurePath` |
| Date/time | `20260516T171406Z-broader` |
| Verifier | Codex |
| Platform | macOS widget verification |
| App build or commit | broader capture `20260516T171406Z-broader` |
| Shell/profile | default local shell profile |
| Observed result | Existing command-menu test verifies the hotkey bridge invocation; new focused regression simulates unregistered platform status and verifies visible `Hotkey window unavailable` feedback without calling the toggle path. |
| Blockers | None after visible-failure fix. |
| Verification gate status | passed |

## Conversion To Code Evidence

After real rows are filled:

1. Convert each ledger row into `LocalTerminalVerificationGateRecord` values.
2. Start from `LocalTerminalVerificationPlanRecords.defaultPending()`.
3. Apply records through `LocalTerminalVerificationEvidenceRecorder.recordAll(...)`.
4. Convert the resulting evidence into T-169 with
   `LocalTerminalRealWiringTaskEvidence.fromVerificationEvidence(...)`.
5. Verify T-164 through T-168 only when their production wiring acceptance
   criteria and relevant verification rows are passing.
6. Rebuild `LocalTerminalCompletionEvidenceReport`.
7. Update `LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` with concrete
   evidence references.

## Current Ledger State

Automated verification was attempted through
`bash tools/local_terminal_verification_capture.sh run all-automated`.
The captured batch finished at `20260516T150417Z` with exit status `1`; the
failed `broader` step was fixed and superseded by the latest successful broader
capture at `20260516T165555Z`.

Latest full-run evidence directory:
`build/local-terminal-verification/20260516T145142Z-all-automated`.

Automated gates are now closed with carried-forward focused evidence plus the
successful latest `broader` rerun. Formatting and static analysis passed.
Focused completion, P1, cross-milestone, P2, P3, P4, P5, and
verification-evidence suites passed. The final broader `flutter test
example/test` gate passed after the profile visibility, paste confirmation,
zoom/unzoom, and hotkey visible-failure fixes.

Integration also passed after the batch was corrected to build `native/core`,
run from the `example` package so desktop plugins are registered, and execute
the smoke and real-PTY integration files sequentially.

Manual and integration-backed gates are recorded as `passed` in this ledger.
T-169 and overall objective closure are represented by `LocalTerminalVerificationPlanRecords.latestPassed()` and `LocalTerminalCurrentCompletionState.verified`, with all required gates passed.
