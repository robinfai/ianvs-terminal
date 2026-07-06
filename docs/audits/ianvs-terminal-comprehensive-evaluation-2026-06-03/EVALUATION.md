# Ianvs Terminal Comprehensive Product Evaluation

Date: 2026-06-03

Scope: current workspace at `/Users/robinfai/personal/ianvs/ianvs-terminal`

## Method

This evaluation uses the Product Design plugin routing model:

- `product-design:index` as the router for evaluation scope.
- `user-context` preflight: no saved Product Design context exists, so this report uses only current workspace evidence.
- `audit` framework: UX, accessibility, evidence limits, and recommendations.
- Flutter UI, Material 3, and macOS design skill checks for theme, desktop behavior, keyboard/menu expectations, and accessibility risk.

## Evidence Base

Local evidence inspected:

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/ROADMAP.md`
- `docs/KNOWN_ISSUES.md`
- `docs/TESTING.md`
- `docs/LOCAL_TERMINAL_FEATURE_PLAN.md`
- `docs/LOCAL_TERMINAL_UX_AUDIT_2026-05-23.md`
- `docs/UX_APP_EXPERIENCE_AUDIT_2026-05-30.md`
- `docs/audits/ianvs-terminal-real-flow-2026-06-03/AUDIT.md`
- `tools/local_terminal_verification_status.sh`
- `example/lib/ui/foundation/app_theme.dart`
- `example/lib/ui/foundation/app_theme_tokens.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_registry.dart`
- `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`

Current-run visual evidence:

- `docs/audits/ianvs-terminal-real-flow-2026-06-03/04-driver-start.png`
- `docs/audits/ianvs-terminal-real-flow-2026-06-03/05-command-menu.png`
- `docs/audits/ianvs-terminal-real-flow-2026-06-03/06-new-tab.png`
- `docs/audits/ianvs-terminal-real-flow-2026-06-03/07-split-right.png`
- `docs/audits/ianvs-terminal-real-flow-2026-06-03/08-search-scrollback.png`
- `docs/audits/ianvs-terminal-real-flow-2026-06-03/driver-observations.json`

External comparison references:

- Ghostty official keybinding docs: https://ghostty.org/docs/config/keybind
- WezTerm official feature overview: https://wezterm.org/
- Warp official block find docs: https://docs.warp.dev/terminal/blocks/find
- iTerm2 official one-page documentation: https://stage.iterm2.com/documentation-one-page.html

## Short Verdict

Ianvs Terminal is already past the “demo shell UI” stage. It has a serious local-terminal product base: real PTY/runtime layering, visible desktop flows, command menu, tabs, panes, search, paste safety work, shell integration work, and unusually strong verification records.

The biggest current weakness is not visual quality. It is confidence at the edges:

- foreground launch still reports a failure in the current host session;
- real keyboard/input capture is not fully proven in this latest audit run;
- host-level physical shortcut, notification banner, and accessibility-tree
  proof remain separate from app-level widget/runtime evidence;
- `ShellScreen` is doing too much and will slow future product work.

Post-evaluation update, 2026-06-28: app-level shortcut dispatch, `Cmd+F`, search scope/result count/regex/global search, paste safety/read-only behavior, profile section navigation, compact tab overflow, pane header/actions, Toolbelt IA, and DPR snapping have current automated acceptance evidence. See `../ianvs-iterm2-comparison-2026-06-25/AUTOMATED_ACCEPTANCE_STATUS_2026-06-28.md`. The foreground launch warning, physical/global host shortcut delivery, accessibility-tree stability, quiet-host performance, and cross-platform hardware checks remain separate host/platform proof work.

Post-evaluation automated closure evidence:

```bash
cd example && flutter test test/widget_test.dart --plain-name "shell search overlay stays inside active split pane"
cd example && flutter test test/widget_test.dart --plain-name "shell search closes on Escape without terminal input"
cd example && flutter test test/shell/shell_screen_phase4_test.dart --plain-name "paste"
```

My overall assessment: keep investing. The project has a credible path to becoming a strong macOS local terminal, but it should stabilize proof and complexity before widening into SSH, sync, plugins, or cross-platform support.

## Scorecard

| Area | Rating | Why |
| --- | --- | --- |
| Product direction | Strong | The scope is clear: macOS local shell first, with SSH/remote explicitly out of v1. |
| First-use shell surface | Strong | The user lands on a usable terminal prompt, not a marketing or setup screen. |
| Command discoverability | Strong | Command menu is searchable, categorized, shortcut-aware, and explains disabled actions. |
| Tabs and panes | Good | New tab and split-right flow are captured and readable; full-width tab cells are an intentional interaction choice. |
| Search | Good | Search opens cleanly and focuses the field; split-pane overlay placement is automated by focused geometry and close-behavior regressions. |
| Paste safety | Good with current automated proof | Multiline confirmation, bracketed-paste sanitization, read-only blocking, and keyboard/native paste routing have automated regressions. |
| Accessibility | Promising but incomplete | Tooltips, semantics, and visible focus exist; screen-reader order and physical keyboard flow need direct proof. |
| macOS fit | Mixed | Menu bar exists and desktop shortcuts are considered; foreground launch and physical shortcut proof still need work. |
| Architecture | Strong with one large risk | Package boundaries are clear; `ShellScreen` is too large for long-term maintainability. |
| Verification | Strong | Verification status is `verified`, with 299 task docs and 131 test files; manual-only gaps remain. |
| Roadmap discipline | Strong | M1-M5 sequencing is conservative and evidence-led. |
| Product readiness | Beta-quality local terminal foundation | Good enough to keep dogfooding; not yet ready to claim broad desktop-terminal reliability. |

## Product Position

Ianvs Terminal’s strongest product story is not “another terminal with tabs.” It is:

> A local macOS terminal that treats shell output, commands, workspace layout, paste safety, and command discovery as first-class product surfaces.

That is a good lane. It avoids prematurely chasing SSH, remote domains, web collaboration, plugin ecosystems, or AI-heavy terminal workflows.

The current feature plan is especially strong because it names what not to do:

- no SSH in local v1;
- no remote workspace;
- no SFTP/serial/collaboration web session;
- no renderer rewrite unless evidence demands it;
- no cross-platform claims without target-machine proof.

That restraint matters. Terminal projects can become messy quickly when every competitor feature becomes “just one more thing.”

## UX Assessment

### What Works

The first shell surface works visually. It gives the user:

- a prompt;
- a selected tab;
- visible new-tab and command-menu controls;
- status chips for encoding, viewport, paste mode, and directory;
- a quiet canvas with enough personality in the prompt.

The command menu is the best current product surface. In `05-command-menu.png`, it shows:

- focused search field;
- examples: profile, paste history, read-only;
- top search action;
- app actions;
- shortcut hints;
- visible disabled reason for `Reopen closed tab`;
- useful icons without turning into visual clutter.

This is where Ianvs feels more designed than ordinary terminal chrome.

Tabs and panes are functional. `06-new-tab.png` proves tab creation; `07-split-right.png` proves split-right and viewport resize from `93x22` to `45x22`.

Tab cells intentionally fill the available tab strip. This favors large click targets, stable drag/reorder zones, and a clear workspace feel over the compact tab density used by some traditional terminals. Treat this as a product decision, not a visual defect, unless future user evidence shows it harms daily use.

Search is credible. `08-search-scrollback.png` shows a compact overlay with field focus and clear close affordance.

### UX Risks

The foreground launch issue is the largest user-facing risk. `docs/KNOWN_ISSUES.md` already records `Failed to foreground app; open returned 1`, and this evaluation reproduced it. A terminal must feel ready immediately after launch.

Search overlay placement in split mode now has an app-level geometry
regression proving the overlay stays inside the active pane. Dense-output visual
review can remain a supplemental product-design smoke, not the closure gate.

Paste safety remains important enough to keep in regression gates. Later
automated tests now cover multiline paste preview, paste routing, read-only
blocking, and bracketed-paste sanitization.

## Accessibility Assessment

Confirmed strengths:

- Computer Use initially exposed `New tab` and `Open command menu` labels.
- Shared UI components use `Tooltip` and `Semantics` in several places.
- Search and command menu have strong visible focus.
- Command-menu disabled reasons are visible text, not just color changes.
- Theme uses dark and light `ThemeData`, `ColorScheme`, and `ThemeExtension` tokens.

Likely gaps:

- Full screen-reader reading order is not proven.
- Physical keyboard flow is not fully proven in this run.
- Text scaling behavior is not directly audited.
- Terminal content accessibility is inherently difficult and needs a clear policy: what is read, what is focusable, and what stays canvas-only.
- Tooltip/semantics coverage exists, but the full app surface is too broad to infer complete coverage from grep alone.

Recommendation: run a focused accessibility audit after foreground/input reliability improves. Target keyboard traversal, command menu, search overlay, paste confirmation, profiles/defaults dialogs, tab strip, and pane focus cues.

## macOS Product Fit

The app has the right instincts for macOS:

- command shortcuts are designed as part of the product;
- `Cmd+F`, `Cmd+T`, `Cmd+Shift+P`, paste history, and hotkey-window behavior are tracked;
- the app has a native menu bar;
- launch visibility was previously hardened;
- hotkey window behavior is treated as a product surface, not just a bridge call.

The remaining macOS risk is proof, not intent:

- physical shortcut delivery remains manual-only in historical audit records;
- notification banner delivery is still host-level proof;
- foreground launch is still noisy;
- accessibility permission state affects automation and possibly global shortcuts.

iTerm2’s official docs show how much desktop terminal behavior lives in tabs, window state, hotkeys, and split panes. Ianvs is working in the right zones, but needs the same level of reliability before those surfaces can be called mature.

## Design System Assessment

The UI system is healthier than many Flutter desktop projects:

- `ThemeData(useMaterial3: true)` is used.
- `ColorScheme.fromSeed` is used and then mapped into app-specific roles.
- `AppThemeTokens` defines surface, text, accent, focus, danger, warning, success, spacing, radius, elevation, and control heights.
- Shared components exist under `example/lib/ui/components`.
- Terminal theme presets exist and are separate from general app chrome.

The design direction is appropriate for a terminal: dense, dark, restrained, mostly utility-first.

Risks:

- The app sometimes uses Material vocabulary in a macOS context. That is acceptable for Flutter, but desktop density and native expectations should win over mobile-like spacing.
- `shell_screen.dart` contains a large amount of UI and behavior, which makes it harder to maintain visual consistency.
- More screenshots are needed for light mode, narrow windows, dialogs, profile editing, defaults, paste confirmation, and error states.

## Architecture Assessment

The architecture document is clear and credible:

- `ianvs_pty`: PTY transport and FFI.
- `ianvs_terminal`: session runtime, config, viewport, input, selection, scroll.
- `example`: app shell, tabs, menu, profiles, defaults, demo fixtures.
- `native/core`: Rust PTY, VT parsing, frame diff, events.

This is a good boundary. It keeps app words like `Profile` out of terminal package APIs and keeps package capability from leaking into demo-specific UI.

Main concern:

- `example/lib/features/shell/shell_screen.dart` is 13,644 lines.

That one file currently carries too much surface area: terminal presentation, overlays, command menu, panes, search, paste, productivity, toolbelt, status, and bridge behavior. It is not a reason to stop product work, but it is the main code-shape risk for future speed.

Suggested extraction order:

1. Command menu overlay and view models.
2. Search overlay.
3. Paste and paste-history sheets.
4. Tab strip and pane layout widgets.
5. Status bar.
6. Shell integration utilities.

## Verification Assessment

The verification posture is unusually strong:

- `tools/local_terminal_verification_status.sh` reports `verified`.
- There are 299 task documents.
- There are 131 test files across example, package, and Rust tests.
- The testing doc separates Rust, Dart, Flutter, integration, vttest-derived tests, real PTY acceptance, and manual gates.
- Known issues are honest about current platform scope and missing non-functional guarantees.

This is good. It also means the project can afford to be stricter: when current-run proof is missing, keep saying it is missing.

Current verification gaps:

- no automated performance regression gate;
- no quiet-host/cross-machine performance baseline;
- no cross-platform validation;
- no SSH compatibility validation;
- physical shortcut behavior remains partly manual;
- real notification banner behavior remains host-dependent;
- accessibility automation is weakened by host permission state;
- `flutter run -d macos` foreground behavior remains noisy.

## Roadmap Assessment

The current M1-M5 sequence is sensible:

1. M1: automated xterm consistency.
2. M2: manual/platform/performance evidence.
3. M3: runtime extension base freeze.
4. M4: local workspace expansion.
5. M5: conditional cross-platform entry.

This is the right order. The project should resist jumping to M4/M5 before M1-M3 are truly clean.

The best roadmap rule in the current docs is: do not expand product surface until the contract and evidence are stable.

## Comparison Context

Ghostty’s keybinding docs are useful because they distinguish focused, global, unconsumed, and performable key behavior. Ianvs already has similar ideas in `TerminalInputPolicy` and action registry shape. This is a strong direction.

WezTerm’s feature set reinforces that serious terminal users expect panes, tabs, windows, multiplexing, native mouse, scrollback, font fallback, and cross-platform reach. Ianvs has local tabs, panes, and scrollback, but intentionally avoids broad remote/multiplexing scope for now.

Warp’s block find docs are useful because they show a command-output-aware search model. Ianvs has shell integration, prompt marks, command output selection, and search. That gives Ianvs a path toward command-aware terminal productivity without copying Warp’s AI/workflow surface.

iTerm2’s docs reinforce the importance of tab bar behavior, status bar placement, hotkey windows, split panes, tmux integration, and window state. Ianvs is already tracking many of these, but foreground launch and manual shortcut proof need to be tighter.

## Priority Recommendations

### P0: Reliability And Proof

1. Fix or isolate `Failed to foreground app; open returned 1`.
2. Add a maintained Product Design capture helper based on the successful Flutter Driver screenshot flow.
3. Keep paste history, multiline paste confirmation, read-only blocking, and
   bracketed-paste sanitization in default automated gates.
4. Re-run physical shortcut checks: `Cmd+F`, `Cmd+Shift+H`, `Option+Cmd+B`, `Option+Cmd+Space`.
5. Run real notification banner proof once host settings allow it.

### P1: Product Polish

1. Keep the full-width tab rationale documented so future design reviews do not treat it as accidental tab bloat.
2. Keep the split-pane search geometry regression in the automated gate.
3. Add screenshot evidence for light mode, defaults, profiles, paste confirmation, empty state, and error states.
4. Make command-menu action labels and docs line up. Completed after this audit by using `Search terminal output` consistently in the command menu and tests.
5. Keep disabled reasons visible across every command surface, not only command menu.

### P2: Architecture Health

1. Start extracting `ShellScreen` sub-surfaces.
2. Turn `audit_driver.dart` from an audit artifact into a maintained test/capture helper, or move it out of docs if it becomes reusable.
3. Add a performance regression lane after the current benchmark evidence matures.
4. Keep public runtime contracts frozen before product layers depend on row ranges and command-output attribution.

### P3: Strategic Restraint

1. Do not start SSH, remote workspace, sync, plugins, or cross-platform product claims until M1-M3 are complete.
2. Keep macOS local terminal excellent first.
3. Treat shell integration as the product wedge: cwd, prompt marks, command ranges, command history, recent directories, and safe paste.

## Final Assessment

Ianvs Terminal is a promising local terminal with a strong engineering and verification base. The visible app experience is already credible: command menu, tabs, split pane, search, status bar, and prompt design are all coherent.

The project should now focus less on adding breadth and more on making its strongest path undeniable:

- launch reliably;
- accept real input reliably;
- keep paste safety and split-pane search placement in automated regression
  gates;
- preserve the intentional full-width tab model unless real user evidence argues against it;
- reduce `ShellScreen` complexity;
- finish xterm/runtime evidence before expanding scope.

If those are handled, Ianvs can become a serious macOS local terminal rather than just a well-tested Flutter experiment.
