# Local Terminal Manual Verification Template

Date: 2026-05-16

Purpose: provide a fill-in evidence template for the manual or integration gates
required by T-169.

This template is not verification evidence until it is filled with real observed
results.

## Metadata

| Field | Value |
| --- | --- |
| Verification date | TBD |
| Verifier | TBD |
| Platform | TBD |
| App build or commit | TBD |
| Shell used | TBD |
| Local terminal profile | TBD |
| Notes | TBD |

## Gate: local shell smoke

Required scenario:

- Launch a local `/bin/zsh` or `/bin/bash` session.
- Create a new tab.
- Split right or down.
- Run a simple command.
- Close pane/tab and confirm the expected focus or empty state.

Evidence:

| Check | Result |
| --- | --- |
| Shell launches successfully | TBD |
| New tab works | TBD |
| Split works | TBD |
| Simple command output renders | TBD |
| Close/focus fallback works | TBD |
| Blockers | TBD |

## Gate: paste and focus safety

Required scenario:

- Paste single-line text.
- Paste multiline text and observe confirmation behavior.
- Trigger large paste confirmation when applicable.
- Enable read-only mode and confirm paste/send-text is blocked.
- Confirm focus and selection are preserved.

Evidence:

| Check | Result |
| --- | --- |
| Single-line paste works through policy | TBD |
| Multiline paste confirmation appears | TBD |
| Large paste confirmation appears when threshold is met | TBD |
| Read-only blocks paste/send-text | TBD |
| Focus remains stable | TBD |
| Blockers | TBD |

## Gate: multipane behavior

Required scenario:

- Split panes.
- Focus next/previous or directional focus.
- Resize pane.
- Swap pane.
- Zoom and unzoom pane.
- Close pane and close last tab/pane.

Evidence:

| Check | Result |
| --- | --- |
| Split creates expected pane | TBD |
| Focus navigation works | TBD |
| Resize respects bounds | TBD |
| Swap preserves active identity | TBD |
| Zoom is reversible | TBD |
| Close fallback/empty state is correct | TBD |
| Blockers | TBD |

## Gate: notification behavior

Required scenario:

- Trigger bell notification.
- Trigger command-finished notification.
- Trigger activity notification for inactive pane when applicable.
- Trigger silence or prompt-ready behavior when configured.
- Confirm focus and target policy are honored.

Evidence:

| Check | Result |
| --- | --- |
| Bell policy honored | TBD |
| Command-finished policy honored | TBD |
| Activity policy honored | TBD |
| Silence/prompt-ready policy honored | TBD |
| Notification target policy honored | TBD |
| Blockers | TBD |

## Gate: hotkey-window failure path

Required scenario:

- Toggle hotkey window.
- Apply configured size/position behavior if implemented.
- Observe success or simulate/observe platform/permission failure.
- Confirm failure is visible and not silent.

Evidence:

| Check | Result |
| --- | --- |
| Toggle path invoked | TBD |
| Config behavior honored | TBD |
| Platform/permission failure visible | TBD |
| No silent no-op observed | TBD |
| Blockers | TBD |

## Recording into verification evidence

After filling this template:

1. Convert each passed manual gate into a
   `LocalTerminalVerificationGateRecord.passed(...)`.
2. Convert each failed gate into a
   `LocalTerminalVerificationGateRecord.failed(...)`.
3. Preserve key observations in `notes`.
4. Preserve log or screenshot references in `output` where applicable.
5. Use `LocalTerminalVerificationEvidenceRecorder.recordAll(...)`.

## Current status

Template created. No manual gate has been executed in this session.
