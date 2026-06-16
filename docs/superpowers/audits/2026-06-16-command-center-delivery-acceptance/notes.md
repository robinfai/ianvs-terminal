# Command Center Delivery Acceptance Notes

Date: 2026-06-16
Branch: `codex/command-center-roadmap-intake`
Worktree: `/Users/robinfai/.config/superpowers/worktrees/ianvs-terminal/codex/command-center-roadmap-intake`

## Product Design Context

- Product Design saved context preflight returned no saved user context.
- Requirement source used for this review: `/Users/robinfai/Downloads/ianvs-command-center-product-plan.zip`.
- The plan positions Ianvs Command Center as a terminal-safe command input, history search, command block, and context action center.
- The product direction is explicit over magic: ordinary text stays terminal-first, while search, actions, saved commands, and future agent surfaces require explicit entry.

## Requirement Backtrace

The product plan called for:

- Command editor that does not break normal terminal input.
- Command history with lifecycle metadata, cwd, exit code, privacy filtering, and local persistence.
- Command Search via explicit overlay, with insert-first behavior and explicit execution.
- Command Blocks built from shell hook lifecycle and terminal row ranges.
- Block Actions such as copy output, save output, search within block, re-input, rerun, and review entrypoints.
- Context Chips for cwd, profile, hook status, last exit, read-only, and selected block context.
- Safety gates for read-only mode, paste confirmation, shortcut isolation, shell integration fallback, and verification.

## Branch And Merge Relationship

- Current shell worktree `/Users/robinfai/personal/ianvs/ianvs-terminal` is on `main`.
- The reviewed functional branch is `codex/command-center-roadmap-intake`.
- `codex/command-center-roadmap-intake` contains the command block work through merge commit `5c9bb08`, which merged `origin/codex/command-block-history-tools`.
- The local `codex/command-block-history-tools` branch points at `326a235`; the reviewed branch merged the remote command-block branch at `3f9ac18`, so the reviewed branch includes the later command-block fixes after the local pointer.
- Relative to `main`, the reviewed branch is a large product line: `229 files changed, 39846 insertions(+), 958 deletions(-)` before this acceptance fix.
- `main` currently has one later roadmap bookkeeping commit not in the functional branch: `a5888c7 Mark command center roadmap intake plan complete`.

## Implementation Arc

1. Command block history foundation:
   - Feature flags and config models.
   - Command block model/controller state.
   - Output range capture, cleanup, cwd tracking, and disabled-state hardening.
   - Command block action pipeline, overlay view models, shell rendering, history peek, review entrypoints, replay, and alternate-buffer stabilization.

2. Command Center core:
   - Command invocation lifecycle model and shell hook adapter.
   - Degraded lifecycle state for shell integration fallback.
   - Session and global command history repositories.
   - History privacy filter.
   - Query parser, ranking index, overlay controller, overlay widget, and insert/execute safety.
   - Command block range model, navigation, reducer, and shell action wiring.
   - Modern command bar editor, context chips, mode router, sticky command header, and review entrypoints.

3. Product wiring:
   - Runtime state and shell event wiring.
   - Command Search shell wiring.
   - Context chip wiring and command history persistence.
   - Saved command repository.
   - Action Search index, controller, shell wiring, overlay, adapter, and broad dispatch coverage for terminal actions.

4. Command block / Command Center fusion:
   - Context chips can jump to last failed block and open selected block actions.
   - Selected block actions cover copy command, scoped search, save output, and review entrypoints.
   - Action Search can operate on selected or active command blocks.
   - Pre-acceptance fusion commit `bdad616` uses command block snapshots for command center actions.
   - The current acceptance fix commit passes active command block context through Action Search metadata, availability, and dispatch paths.

## Product Value

- Turns terminal output from a plain scrollback stream into reusable command objects.
- Makes command recall safer: search defaults to inserting commands instead of executing them.
- Gives users immediate context before acting: cwd, profile, shell hooks, last exit, and selected block are visible.
- Gives failed commands useful next actions: copy output, save output, search inside output, re-input, rerun, and review.
- Keeps safety rules central: read-only, paste policy, shell integration fallback, and command block availability are surfaced as disabled reasons instead of silent failure.
- Keeps v1 local-first and terminal-first, avoiding a premature chat or agent default.

## Captured Flow Evidence

- `01-default-state.png`: app default state after enabling Command Center and Command Blocks flags.
- `02-command-blocks-failure.png`: command block rendering with a failed command.
- `03-command-menu-action-search-entry.png`: command menu showing Action Search entry.
- `04-action-search-no-block-bug.png`: acceptance issue found during review; Action Search showed `No command block available` despite visible command blocks.
- `05-action-search-context-fix-rerun.png`: app relaunched after fix; default state captured successfully.
- A later fullscreen capture attempt was rejected and not retained because it produced a black screenshot.

## Acceptance Issue Found And Fixed

Issue:

- In Action Search, `Copy block output` could display `Integration action • No command block available` even when command blocks were visible.
- Product impact: the user sees a usable command block on screen but the action surface says it cannot act on it. This breaks trust in the command object model.

Root cause:

- `ShellCommandActionSearchAdapter.itemsFor` built action metadata without the active command block.
- `ShellActionViewModelBuilder` could not pass command block context into availability resolution.
- Availability and dispatcher mapping only covered part of the command block action set.

Fix:

- Pass active command block and command block feature flags from `shell_screen_state_command_action_search.dart` into the Action Search adapter.
- Pass `CommandBlock?` through `ShellActionViewModelBuilder` into `ShellActionAvailabilityResolver`.
- Include active block command text in block action subtitles and search keywords.
- Map all Action Search command block actions in availability and dispatcher: copy output, save output, open review, search within block, re-input, and rerun.

## Verification

Passed:

- `flutter analyze`
- `flutter test test/shell/shell_command_action_search_adapter_test.dart --plain-name "uses active command block context"`
- `flutter test test/shell/shell_action_availability_test.dart`
- `flutter test test/shell/shell_action_dispatcher_test.dart`
- `flutter test test/widget_test.dart --plain-name "action search can copy block output without shell write"`
- `flutter run -d macos` built and launched the macOS app.

Limits:

- Computer Use could not attach to the offscreen macOS app window and returned `cgWindowNotFound`.
- Window-level screenshots worked for the relaunched default state, then became unstable after keyboard automation.
- The final Action Search fix is therefore verified by widget-level UI coverage and focused unit tests, rather than a post-fix Computer Use screenshot of the overlay.
- Keyboard automation through accessibility also showed earlier input normalization oddities around escape sequences and semicolons; this should be treated as tool-path evidence only unless reproduced by direct manual typing.

## Product Design Verdict

The branch realizes the product plan’s core promise: a terminal-first Command Center that makes command history, command blocks, and context-aware actions available without turning normal terminal input into an implicit agent prompt.

The main acceptance risk was not the breadth of features, but consistency between visual command blocks and the action surfaces that act on them. The found Action Search context bug was fixed and covered with tests. Before final merge, the branch should still get a broader test pass because the change set is large and touches native PTY behavior, Flutter shell UI, and shared terminal package rendering.
