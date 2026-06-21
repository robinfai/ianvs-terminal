# Ianvs Terminal Dev User-Journey Audit

Date: 2026-06-21

## Audit Scope

- Product surface: Ianvs Terminal Dev macOS app.
- Journeys reviewed by 5.3 spark subagents using Computer Use:
  - first-launch shell orientation and recovery
  - command input, suggestions, command search, and history insertion
  - tabs and split panes
  - Defaults & appearance, Profiles, and profile editor
  - command blocks, Action search, Command search, and Replay from command block
- Destination: local audit folder `.audits/appearance-flow`.

## Evidence

- Screenshot evidence:
  - `01_start.png`
  - `02_profiles_open.png`
  - `03_command_center_full.png`
  - `03_editor_attempt.png`
  - `04_profiles_open.png`
  - `05_profile_edit.png`
- Computer Use accessibility state evidence from five first-pass subagents.
- Current post-fix app state confirmed `Active terminal pane 1` is exposed in the accessibility tree.

Evidence limits:

- `03_command_center_full.png` includes a macOS Instruments accessibility permission prompt over the app and is not a clean product screenshot. It is useful only as contextual evidence that system-level automation dialogs can distort review captures.
- Several subagent captures were text accessibility trees rather than saved screenshots, so the audit does not claim full visual or WCAG compliance.

## First-Pass Findings

1. High: Command Center and modal recovery could lead into quit confirmation.
   - Evidence: first-launch and command-input journeys both reached `Quit Ianvs Terminal? Active shell sessions will be closed.`
   - User impact: an exploratory close/cancel path can threaten session loss and block continued use.

2. High: Split pane actions were discoverable but not reliably invokable or verifiable.
   - Evidence: tabs/panes journey saw `Split right` and `Split down` in Command Center, but no split-pane artifacts were consistently exposed.
   - User impact: users cannot trust pane creation, especially after suggestions or overlays have appeared.

3. Medium: Active pane state was not clearly exposed.
   - Evidence: tabs/panes journey could see multiple tabs but not a stable active pane marker in the accessibility tree.
   - User impact: keyboard and assistive-technology users cannot confidently tell which pane receives input.

4. Medium: Defaults & appearance and color presets were not consistently reachable.
   - Evidence: appearance journey could open Profiles and the profile editor, but Defaults & appearance / Terminal color presets sometimes fell back to shell context.
   - User impact: theme, font, and profile settings feel non-deterministic from Command Center.

5. Medium: Search/action overlays and suggestions left stale state.
   - Evidence: command search/action center journeys reported stale indexes, unavailable command-block actions, suggested-fix panels, and unclear focus recovery.
   - User impact: command history, block actions, and normal typing compete for ownership of the same input surface.

## Implemented Fixes

1. Added a shared transient-command-UI cleanup path.
   - Clears autocomplete, auto composer suggestions, command correction, and optional search/action-search overlay controllers before opening Command Center, Defaults & appearance, Profiles, and split actions.

2. Made Command search and Action search mutually clean up stale overlay state.
   - Opening one closes the other's session/controller state and clears input suggestions/corrections.

3. Guarded quit confirmation while internal overlays are open.
   - Cmd+Q is swallowed while Command Center, Defaults, Profiles, Command search, Action search, autocomplete, or auto composer is open.

4. Exposed active/inactive pane state to accessibility.
   - Each pane now exposes labels such as `Active terminal pane 1` or `Inactive terminal pane 2` and selected state.

5. Routed native macOS close and quit requests through Flutter overlay handling.
   - Window close and app quit first ask Flutter whether an internal overlay can be dismissed before showing the native quit confirmation.

6. Fixed command input execution and slash-command insertion.
   - Added `printf` to shell command classification.
   - Added `/help` as a slash command that inserts `man zshbuiltins`.
   - Made slash command selection remove stale slash tokens and repeated slash residue before inserting.

7. Made Command Center search intent-specific for ambiguous settings terms.
   - `default/defaults`, `theme/color presets`, and `profile/profiles` now route to Defaults, terminal presets, and Profiles instead of being captured by New tab subtitle text.
   - Profiles and Dynamic Profiles open directly from Command Center after route dismissal.

## Verification

- `dart analyze .`
- `flutter test test/widget_test.dart --plain-name "tab context menu split right opens a second pane in the active tab"`
- `flutter test test/widget_test.dart --plain-name "command-q is swallowed while the command center is open"`
- `flutter test test/widget_test.dart --plain-name "action search command search result opens command search"`
- `flutter test test/widget_test.dart --plain-name "command menu allows splitting down after splitting right"`
- `flutter test test/shell/shell_screen_phase3_test.dart --plain-name "defaults and appearance modal is the only place that mutates default profile and theme"`
- `flutter test test/widget_test.dart --plain-name "native window close dismisses the command center first"`
- `flutter test test/widget_test.dart --plain-name "native quit request dismisses the command center first"`
- `flutter test test/widget_test.dart --plain-name "command center defaults search opens defaults dialog"`
- `flutter test test/widget_test.dart --plain-name "command center default query opens defaults, not new tab"`
- `flutter test test/widget_test.dart --plain-name "command center theme picker search opens defaults dialog"`
- `flutter test test/widget_test.dart --plain-name "command center profile query opens profiles sheet"`
- `flutter test test/widget_test.dart --plain-name "command input submits detected shell commands from auto mode"`
- `flutter test test/widget_test.dart --plain-name "command input slash token opens help slash command"`
- `flutter test test/widget_test.dart --plain-name "command input slash selection removes token when cursor moved"`
- `flutter test test/widget_test.dart --plain-name "command input slash selection collapses repeated residue"`
- `flutter test test/widget_test.dart --plain-name "command input slash selection cleans repeated slash suffixes"`
- `flutter test test/shell/universal_input_test.dart --plain-name "classifies shell builtins with plain arguments as command input"`

## Second-Pass Status

Second and third passes found additional interaction issues:

- Command Center settings queries could still route through ambiguous results (`default` and `profile` were captured by New tab-related text).
- `/help` slash insertion could leave stale `/help` suffixes when selection focus moved or the menu was invoked repeatedly.
- Computer Use `type_text` drops `_` characters on this host; widget tests confirm the app preserves underscores, so the final manual-agent verification used no-underscore markers.

Final targeted subagent retest status:

- Appearance / Defaults / Profiles: no issues.
- Command input / Send button / `/help`: no issues after visual confirmation of the final input state.
- Cmd+Q and red window close while Command Center is open: no issues.
- Tabs/panes and command-block/action-search journeys remained clean from the previous pass.
