# Ianvs Terminal Real Flow Audit

Date: 2026-06-03

Local folder:
`/Users/robinfai/personal/ianvs/ianvs-terminal/docs/audits/ianvs-terminal-real-flow-2026-06-03`

## Audit Scope

Target: Ianvs Terminal macOS Flutter app in this workspace.

Requested flow: real use flow for startup, shell surface, command menu, new tab, split pane, search, and paste-related behavior.

Capture tools used:

- Computer Use for initial app-window observation.
- Flutter VM service inspector screenshot for production `main.dart` surfaces.
- Flutter Driver screenshot for `test_driver/main.dart` surfaces.

Post-audit update, 2026-06-28: the missing app-level paste, shortcut, search, tab, pane, profile, Toolbelt, and DPR-snapping proofs called out by this audit have since been covered by automated tests and recorded in `../ianvs-iterm2-comparison-2026-06-25/AUTOMATED_ACCEPTANCE_STATUS_2026-06-28.md`. The foreground launch warning and host accessibility/physical-input risks remain separate environment proof items.

## Evidence Limits

This audit completed the visible app-flow path through Flutter Driver: startup, command menu, new tab, split right, and search.

The original 2026-06-03 run was limited by the host session:

- `flutter run -d macos` launched the app, but repeated launches reported `Failed to foreground app; open returned 1`.
- macOS `screencapture` returned the lock screen, so OS screenshots were rejected.
- Computer Use initially saw the Ianvs Terminal window, then text input did not reach the terminal and the AX window handle became unavailable.
- Paste history and multiline paste confirmation were not captured in that screenshot pass; later automated acceptance now covers the paste policy path.

Because of this, the report treats the Flutter Driver screenshots as accepted visual flow evidence. Real host keyboard entry, foreground ownership, and AX stability remain environment proof gaps; paste policy is no longer an app-level automated gap.

## Screenshots

- `01-launch-prompt.png`: production app surface captured through Flutter inspector after first launch.
- `02-after-type-attempt.png`: production app surface after Computer Use text-input attempt; terminal did not change.
- `03-relaunch-surface.png`: production app surface after relaunch with foreground warning.
- `04-driver-start.png`: driver entrypoint start state with visible tab, prompt, new-tab affordance, command-menu affordance, and status bar.
- `05-command-menu.png`: command menu opened from the chrome affordance.
- `06-new-tab.png`: second tab created through the command menu.
- `07-split-right.png`: active tab split into left and right panes.
- `08-search-scrollback.png`: in-terminal search overlay opened from the command menu.
- `05-driver-reference-tabs.png`: reference driver state with multiple tabs and visible command content.
- `driver-observations.json`: Flutter Driver acceptance snapshots for the completed steps.

## Step List

1. Startup shell surface
   - Evidence: `01-launch-prompt.png`, `04-driver-start.png`
   - Health: healthy.
   - Notes: The first viewport is focused on the terminal. Prompt, cursor, tab title, status chips, new tab, and command menu are visible. The app does not show a landing layer before the usable terminal.

2. Terminal input attempt
   - Evidence: `02-after-type-attempt.png`
   - Health: blocked by capture environment.
   - Notes: Computer Use text input did not visibly alter the terminal. This audit run cannot prove real keyboard entry, even though repo tests and prior audits cover terminal input.

3. Relaunch and foreground behavior
   - Evidence: `03-relaunch-surface.png`, Flutter run log.
   - Health: risk.
   - Notes: The app rendered a valid shell surface, but Flutter reported `Failed to foreground app; open returned 1`. For a desktop terminal, foreground reliability is part of the perceived product quality.

4. Command menu
   - Evidence: `05-command-menu.png`
   - Health: healthy.
   - Notes: The menu has a clear search field, examples, top action, categories, shortcut hints, icons, and inline unavailable reasons. `Reopen closed tab` explains why it is disabled, which is good product feedback.

5. New tab
   - Evidence: `06-new-tab.png`, `driver-observations.json`
   - Health: functional.
   - Notes: A second tab is created and selected. On a wide window, two tabs stretch across large cells by design. This favors large click targets, stable drag/reorder zones, and a clear workspace feel over compact terminal tab density.

6. Split right
   - Evidence: `07-split-right.png`, `driver-observations.json`
   - Health: healthy.
   - Notes: The split appears immediately, left/right panes are clear, and the status bar updates viewport size from `93x22` to `45x22`. The divider is visible without stealing attention.

7. Search terminal output
   - Evidence: `08-search-scrollback.png`, `driver-observations.json`
   - Health: healthy.
   - Notes: Search opens as a compact overlay with focus in the field. It sits over the right pane, which is expected for an overlay, though dense command output could be obscured until the user closes it.

8. Paste history and multiline paste confirmation
   - Evidence: no accepted screenshot in this run.
   - Health: not audited here.
   - Notes: This is still an important flow for a terminal product because paste safety is user-facing trust work. It should be captured in the next pass.

## Strengths

- The shell surface is direct and work-focused. The user lands on a ready prompt.
- The command menu is strong: searchable, categorized, shortcut-aware, and honest about disabled actions.
- The status bar communicates useful session context without bloating the UI.
- Split pane behavior is visually clear and the viewport-size update reassures the user that layout changed correctly.
- Full-width tab cells are intentional: they make tab activation and drag/reorder interaction easier to hit.
- The visual system has personality in the prompt while keeping the canvas quiet.

## UX Risks

- Foreground launch remains a user-facing reliability risk in this host session.
- Real keyboard input could not be revalidated through Computer Use, so manual acceptance is still needed.
- Search overlay placement is usable, but it can cover right-pane content in split mode.
- Paste safety was not captured in this run, so trust-critical paste behavior remains outside this evidence set.

## Accessibility Risks

- Screenshots alone cannot prove full keyboard access, focus order, or screen-reader flow.
- The icon-only chrome buttons depend on accurate accessible labels; Computer Use initially exposed `New tab` and `Open command menu`, which is a positive sign.
- Command-menu disabled reasons are visible and likely helpful for assistive tech, but this run did not inspect spoken output.
- Search overlay focus appears clear visually; keyboard escape/close behavior still needs manual or automated proof.

## Recommendations

1. Fix or isolate foreground launch behavior.
   - Keep the existing known issue visible until `flutter run -d macos` no longer reports foreground failure on this host.

2. Add a supported Product Design capture helper.
   - The Flutter Driver screenshot path worked well. A small maintained helper could capture startup, command menu, new tab, split, search, paste history, and paste confirmation in one pass.

3. Keep the full-width tab decision documented.
   - Do not treat wide tab cells as a polish bug unless future user evidence shows they hurt daily tab use.

4. Capture paste safety in the next audit.
   - Include paste history empty state, multiline paste preview, cancel behavior, and confirmed paste behavior.

5. Re-run with real keyboard access.
   - Validate command entry, `Cmd+Shift+P`, `Cmd+F`, tab creation, split, search typing, and overlay close behavior from physical or reliable synthetic keyboard input.

## Current Conclusion

The visible product flow is in good shape: startup, command menu, new tab, split pane, and search all present as credible desktop-terminal interactions. The strongest product risk is not the visual design; it is host-level foreground/input reliability and the missing current-run paste-safety capture.
