# Ianvs Terminal vs iTerm2 Experience Optimization Plan

Date: 2026-06-25

Scope: current workspace at `/Users/robinfai/flutter_projects/ianvs-terminal`, running `example` as `Ianvs Terminal Dev`, compared with installed iTerm2 `3.6.11`.

## Method And Evidence

Current Ianvs evidence:

- Ran `flutter pub get`.
- Ran `cd example && flutter run -d macos`.
- Observed startup, shell input, command menu, split right, new tab, search overlay, Defaults & appearance, Profiles list, and Profile editor.
- `flutter run` still printed `Failed to foreground app; open returned 1`, although the app became frontmost and usable.
- During UI interaction and shutdown, the debug log also emitted repeated Flutter accessibility bridge `Failed to update ui::AXTree` errors. Treat this as a verification risk until reproduced or isolated.

iTerm2 evidence:

- Installed app version: `3.6.11`, bundle id `com.googlecode.iterm2`.
- Computer Use refused direct control of iTerm2, so iTerm2 UI evidence is limited to a freshly opened default window plus AppleScript-triggered shortcut screenshots.
- Captured visible iTerm2 states: default window, split pane, Find overlay.
- Used official iTerm2 documentation to verify feature breadth.

Saved screenshots:

- `screenshots/iterm2-default-window-crop.png`
- `screenshots/iterm2-split-pane-crop.png`
- `screenshots/iterm2-find-crop.png`
- `screenshots/ianvs-profile-editor-crop-clean.png`

Official iTerm2 references:

- https://iterm2.com/features.html
- https://iterm2.com/documentation-one-page.html
- https://iterm2.com/documentation-tmux-integration.html
- https://iterm2.com/documentation-preferences-profiles-keys.html
- https://iterm2.com/3.0/documentation-menu-items.html

## Short Verdict

Ianvs is already beyond a basic terminal demo. It has a credible local-terminal surface: real shell session, tabs, panes, searchable command menu, status chips, profile editing, theme presets, search overlay, shell-integration-oriented actions, paste/history-oriented actions, instant replay, annotations, captured output, tmux/coprocess entry points, and hotkey-window entry points.

iTerm2 still wins on maturity, native macOS feel, configurability depth, proven shortcuts, global search, profile/keybinding systems, session/window restoration, hotkey windows, triggers, shell integration, tmux integration, scripting, and long-tail terminal behavior.

The immediate opportunity is not to copy iTerm2 wholesale. Ianvs should lean into a clearer command-aware terminal experience while closing the reliability and discoverability gaps that make iTerm2 feel dependable.

## Feature Comparison

| Area | iTerm2 3.6.11 | Ianvs current version | Assessment | Optimization direction |
| --- | --- | --- | --- | --- |
| Launch and window readiness | Mature native launch and window behavior. | App launches and is usable, but debug run still reports `Failed to foreground app; open returned 1`. | Ianvs intent is good, proof is noisy. | Treat foreground launch as P0; capture a clean launch proof on a quiet host. |
| First screen | Minimal native terminal window; most actions live in menus and shortcuts. | First screen has terminal, tab rail, command-menu button, new-tab button, status chips. | Ianvs is more explicit and product-like; iTerm2 is quieter. | Keep explicit controls, but make density configurable for expert users. |
| Tabs | Native compact tabs with mature window/menu behavior. | Tabs work; visual model uses large equal-width cells. | Easier targets, lower density. | Add compact tab mode, overflow behavior, close-on-hover, optional tab color. |
| Panes | `Cmd+D` / `Cmd+Shift+D`, pane title controls, visible active/inactive contrast. | Split right works; viewport updates correctly. Pane chrome is lighter. | Ianvs is functional but less discoverable once many panes exist. | Add stronger active pane cue, optional pane header, split/zoom/close affordance. |
| Search | Robust find overlay, regex support, global search, Expose-style tab search. | Search overlay opens from command menu; active-pane scope is not obvious. Global search entry exists. | Search works, but scope feedback can confuse users in split panes. | Add scope selector: active pane, current tab, all tabs. Add result count and regex/case controls. |
| Command discovery | Menus, profiles window, preferences, shortcuts. | Command menu is a strong surface: searchable, categorized, shortcut-aware, disabled reasons visible. | Ianvs can surpass iTerm2 for action discoverability. | Make command menu the primary command center, but reduce first-level overload. |
| Profiles | Searchable/taggable profile system, deep preferences, profile keys, automatic switching. | Profiles list and editor exist. Current editor covers identity, startup, args/env, automation, emulation, shell integration, typography, fallback fonts, color presets, ANSI colors. | Ianvs has a strong base but needs clearer information architecture. | Split editor into sections/tabs: General, Startup, Terminal, Appearance, Keys, Automation, Advanced. |
| Dynamic profiles/import | iTerm2 supports dynamic profiles and rich profile workflows. | Dynamic Profiles entry imports iTerm-style JSON. | Good migration hook. | Add import preview, conflict handling, profile diff, export, and rollback. |
| Keybindings | Deep global and profile key mapping, modifier remap, profile hotkeys. | Action registry has default shortcuts and input policy; UI proof is incomplete. `Cmd+F` did not open search in this run. | Architecture exists; physical shortcut proof is the gap. | Build a shortcut verification matrix and in-app conflict diagnostics. |
| Shell integration | Knows prompt, command, host, cwd; enables prompt nav, recent dirs, command autocomplete, profile switching. | Shell integration toggle and actions exist; status and prompt-aware entries are present. | Product direction matches iTerm2's strongest productivity lane. | Make shell integration health visible per pane and degrade gracefully when unavailable. |
| Paste safety/history | Paste history, advanced paste, paste warnings and transformations. | Paste, advanced paste, paste history, bracketed paste status, read-only action exist. | Strong plan; current run did not recapture paste confirmation. | Re-verify all paste paths, especially multiline/large paste and read-only mode. |
| Automation/triggers | Triggers, captured output, coprocesses, annotations, password manager. | Profile automation rules, captured output, coprocess, annotations, password manager entries exist. | Ianvs is already tracking the right advanced surfaces. | Graduate these from entries to polished flows with setup templates and diagnostics. |
| Notifications | Activity, bells, job completion via Notification Center. | Command-finished, bell, and activity monitor toggles exist. | Comparable intent; platform proof needed. | Add notification permission diagnostics and manual evidence for bell/activity/command-finished. |
| Hotkey window | Dedicated configurable hotkey windows with multiple options. | Hotkey window action exists with `Option+Cmd+Space` label. | Useful target but not mature yet. | Add dedicated settings UI, permission/failure state, and launch/restore proof. |
| tmux | Deep `tmux -CC` native integration. | tmux integration entry exists. | iTerm2 remains far ahead. | Keep tmux as advanced/future unless current users need it; do not block core UX on parity. |
| Instant replay | Mature instant replay feature. | Instant replay entry and shortcut exist. | Good differentiator to keep. | Surface it as recovery, with clear timeline and memory policy. |
| Status/toolbelt | Toolbelt with command history, jobs, profiles, paste history, captured output, recent dirs. | Toolbelt entry exists; bottom status chips show encoding, viewport, paste state, cwd. | Ianvs has a cleaner status baseline. | Make toolbelt a collapsible productivity sidebar, not a menu dump. |
| Accessibility | Mature native controls plus terminal-specific complexity. | Command menu and profile editor expose many accessibility labels; screenshots alone cannot prove full reading order. | Promising, incomplete. | Audit keyboard traversal, screen-reader order, text scaling, contrast, focus rings. |

## Current Ianvs Strengths

1. The first screen is direct and useful: shell first, not onboarding.
2. Command menu is the best current product surface. It explains actions, shortcuts, and disabled states.
3. Tabs and panes are already live, not just planned.
4. The status bar gives useful operational context: encoding, viewport, paste mode, cwd.
5. Profiles are more substantial than expected: command, cwd, args/env, shell integration, typography, fallback fonts, theme presets, ANSI colors, automation rules.
6. The product direction is command-aware: prompt marks, command output selection, recent directories, paste safety, replay, annotations, captured output.

## Key Experience Gaps

1. Launch proof is noisy because foreground activation still reports failure.
2. Shortcut behavior needs current physical proof. In this run, `Cmd+F` did not visibly open search, while menu-opened search worked.
3. Search scope is unclear in split panes. Searching the empty active pane while left pane has output returns `No matches`, which can look like broken search.
4. Command menu has too many first-level actions. It is powerful but starts to feel like an implementation inventory.
5. Tab density will not scale well if every tab stays equal-width.
6. Pane affordances are lighter than iTerm2; expert users may miss close, zoom, focus, and action handles.
7. Settings/Profile editing is comprehensive but needs a stronger structure before it grows further.
8. Advanced entries such as tmux, coprocess, captured output, password manager, hotkey window, and global search need visible maturity states.
9. Accessibility bridge errors appeared in the debug log, so screen-reader and accessibility-tree stability should be verified explicitly.

## Optimization Plan

### P0: Reliability And Proof

Goal: make the current terminal feel dependable before adding breadth.

Tasks:

- Fix or suppress the false `Failed to foreground app; open returned 1` path.
- Create a repeatable manual capture script for launch, command menu, split, tab, search, paste, profiles, and shortcuts.
- Build a shortcut proof matrix for `Cmd+T`, `Cmd+D`, `Cmd+Shift+D`, `Cmd+F`, `Cmd+Shift+P`, `Cmd+Shift+H`, `Option+Cmd+B`, and `Option+Cmd+Space`.
- Re-verify paste confirmation, paste history, advanced paste, bracketed paste, and read-only mode.
- Add a visible diagnostics state for notification permission, shell integration status, hotkey-window availability, and shortcut conflicts.
- Reproduce or eliminate the accessibility bridge `AXTree` errors with the command menu, search overlay, Defaults, Profiles, and Profile editor flows.

Acceptance:

- A clean local run can prove launch, input, split, tab, search, paste, and profile edit without ambiguous automation failures.
- Shortcut checks distinguish automation limitation from product failure.

### P1: Daily Terminal Parity

Goal: match iTerm2's everyday flow where users feel friction fastest.

Tasks:

- Add compact tab mode and tab overflow behavior.
- Add optional tab close-on-hover and tab color support.
- Add active pane border, focus ring, and optional pane header with close, split, zoom, and actions.
- Add search scope selector: active pane, current tab, all tabs.
- Add search result count and toggles for case sensitivity and regex.
- Make global search a real workspace surface if not already wired: query, per-tab results, jump-to-result.

Acceptance:

- A user with 6-10 tabs and 2-4 panes can still identify, switch, close, search, and recover context quickly.

### P2: Command-Aware Productivity

Goal: make Ianvs meaningfully different from a generic terminal.

Tasks:

- Promote shell integration health into the status bar or pane header.
- Make command blocks/ranges visible enough to support command output copy and prompt navigation.
- Add recent directories and command history as first-class toolbelt panels.
- Turn annotations and captured output into setup-guided flows with empty states.
- Add instant replay timeline with memory retention policy.

Acceptance:

- Users can navigate by prompt, copy one command's output, recover recent screen text, and reopen frequent directories without learning hidden commands.

### P3: Settings And Profile Architecture

Goal: keep iTerm2-level configurability without turning one modal into a long form.

Tasks:

- Split Profile editor into section navigation: General, Startup, Terminal, Appearance, Keys, Automation, Advanced.
- Add profile search inside settings.
- Add dirty-state summary and reset/revert per section.
- Add import preview for iTerm JSON: added, changed, skipped, unsupported fields.
- Add export for Ianvs profiles and theme presets.
- Add clear copy for "applies to new sessions only" and offer duplicate-profile workflow.

Acceptance:

- A user can answer "where do I configure font, colors, shell command, key mappings, triggers, and startup cwd?" without scanning a long scroll surface.

### P4: Mature macOS Fit

Goal: feel like a serious macOS terminal, not only a Flutter shell window.

Tasks:

- Align app menu items with visible actions: New Tab, Split, Find, Profiles, Settings, Window arrangements.
- Add native-ish Settings entry via `Cmd+,`.
- Add Window menu support for save/restore arrangement if local workspace persistence is ready.
- Add hotkey-window preferences and failure recovery.
- Add keyboard-only focus traversal for tabs, panes, command menu, search, profile editor, and toolbelt.

Acceptance:

- A macOS terminal user can discover and operate core flows from menus, shortcuts, and visible controls consistently.

### P5: Advanced iTerm2 Parity Candidates

Goal: choose advanced parity deliberately.

Candidate areas:

- `tmux -CC` style integration.
- Scripting and automation API.
- Inline image/graphics protocol support.
- Smart selection.
- Timestamps.
- Session/window arrangement persistence.
- Expose-style tab overview and tab-content search.

Recommendation:

- Defer these until P0-P3 are stable unless a real user workflow needs one urgently.
- Do not let advanced parity delay launch, shortcut, search, profile, and paste reliability.

## Product Positioning

Do not position Ianvs as "iTerm2 clone in Flutter." A stronger position is:

> A local macOS terminal where shell output, commands, paste safety, layout, and recovery are visible product surfaces.

This lets Ianvs compete on clarity and command-aware workflows while borrowing mature expectations from iTerm2 only where they reduce daily friction.

## Suggested Next Tasks

1. `T-UX-001`: Foreground launch proof and fix.
2. `T-UX-002`: Shortcut verification matrix.
3. `T-UX-003`: Search scope selector and result count.
4. `T-UX-004`: Compact tab mode and overflow behavior.
5. `T-UX-005`: Pane active-state and action affordance pass.
6. `T-UX-006`: Profile editor section navigation.
7. `T-UX-007`: Paste safety recapture and read-only path proof.
8. `T-UX-008`: Toolbelt IA: command history, recent dirs, captured output, paste history.

## Limits

- Computer Use could not directly inspect iTerm2's accessibility tree.
- iTerm2 Settings UI was not used as current-run visual evidence because `Cmd+,` did not reliably open it in the foreground during this run.
- Screenshot-only evidence cannot prove full accessibility, shortcut delivery, renderer correctness, or performance.
