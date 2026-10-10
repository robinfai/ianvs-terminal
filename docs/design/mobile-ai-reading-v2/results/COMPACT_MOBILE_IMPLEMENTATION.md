# Mobile task chrome and compact input — local-build candidate

Date: 2026-10-11. Base: `composer@aa45f0d8309ff168fec6dc0916ad5cb3bc9b40de`.
Status: **implemented_unverified**. No application screenshot or native device
acceptance is claimed. The user will build/install locally and return screenshots.

## What this candidate changes

The production phone host now opts into `TerminalAiWorkspace.compactMobile`.
This is a view-only presentation option for a host that already supplies session
navigation. It is not an alternative task controller, execution loop or PTY.
Desktop and standalone workspaces keep their previous presentation by default.

- The task strip uses a title/task menu, a state-specific primary action and an
  error-details entry when needed. History/new task/observer no longer occupy
  a permanent row of separate icons. The host's top AI toggle reads “终端” in the
  task view and still uses the existing read-only observation callback.
- Empty, unfocused drafts use a single-row editor. Its target size is 48–56
  logical points excluding exterior margins and system safe areas; a widget
  regression measures the actual render box when executed.
- Focusing, typing or attaching a source reveals the editing controls. The
  TextField remains at the same element position with the same controller and
  FocusNode. Long drafts retain 1–4 lines, full-screen editing and source details.
- Very short viewports use a one-row editor with explicit expand/hide-keyboard
  controls. Chrome can scroll rather than reducing touch targets.
- “回到最新” belongs to the timeline and only appears when following is paused
  and unread lower content exists. It no longer reserves a Composer row.
- AI recovery actions are no longer appended as a second block of buttons after
  the transcript. The task strip has one primary action; the details sheet holds
  checks, reconnect, read-only observation, input takeover and connection settings.
- Terminal-unavailable drafts stay editable but neither the submit button nor
  hardware Enter starts model inference. Target changes similarly require explicit
  resolution. Successful reconnection does not send the retained draft.
- Unknown submission outcomes take precedence over ordinary disconnection.
  “检查原提交” remains primary. AI supplements can still be locally deferred,
  with explicit saved-only copy and a save icon; no retry or “mark successful” UI.
- Pause copy no longer says a command is still running solely because AI is paused.
  A fresh known running-command context is required for that qualifier.
- Mobile inline code no longer paints opaque background fragments. Fenced code
  keeps its themed container; code bytes, selections and existing fonts are unchanged.

## Safety and source identity

The new file is `terminal_ai_workspace_mobile.dart`, a part of the existing
workspace library. It calls existing `_review`, `_resume`, observer, controller
and host reconnection functions. Full approval, source provenance and target
comparison remain on their original paths. There is no new auto-approval,
command replay, background permission or data persistence behavior.

Details-sheet rows only return an action intent. After dismissal the originating
controller/task/pane and current route/lifecycle are checked again. A stale row
cannot reconnect or take over a subsequently selected task. Reconnect callbacks
are guarded against repeated clicks, including stale callbacks. Showing details
alone does not infer, write terminal input or take over the task.

## Deliberate limits

**The global runtime error banner is not suppressed or deduplicated in this
candidate.** Its message is not a reliable session/operation correlation key. It
can describe another operation, and hiding it whenever AI has a terminal error
would swallow unrelated failures. It therefore remains visible independently;
the redundant *AI* transcript recovery controls have been removed. A later
structured-error correlation change may combine these only with proven identity.

The top-level Files/SFTP entry remains available. Native Block previews/Reader,
whole-task progress, task-local source folding, voice input, arbitrary file
attachments, source text rewriting and offline model conversations are not added.
No generated concept image is used as an application screenshot or runtime UI.

## Checks performed here

- Base workspace, host wiring and message source bytes were reconstructed from
  connected GitHub reads and matched their Git blob SHA-1 identities.
- `git diff --check` and source-level checks are recorded with the PR.
- Dart/Flutter SDKs are unavailable in the editing container. Public Git access
  also failed DNS resolution. **Dart formatting, analyzer, widget tests, native
  builds and `make verify` have not been run here.** Source checks do not prove
  compilation or behavior. The PR remains draft pending local/CI results.

New regression file: `example/test/ai/terminal_ai_compact_mobile_test.dart`.
It explicitly exercises the production host presentation option, including
phone widths/themes, stable editor state, IME, offline drafts, reconnect
single-flight, unknown receipts, stale detail choices, observer/takeover,
desktop fallback and transparent inline code. Existing standalone/desktop tests
remain useful but do not substitute for this new production-layout suite.

## Local build and verification

Use a clean worktree/branch; do not discard local changes or overwrite the
production app automatically. Read the current project instructions first.

```sh
# From the repository root, after checking out the PR branch:
dart format example/lib/features/ai/terminal_ai_workspace.dart \
  example/lib/features/ai/terminal_ai_workspace_mobile.dart \
  example/lib/features/ai/terminal_ai_message.dart \
  example/lib/features/shell/shell_screen_ai.dart \
  example/test/ai/terminal_ai_compact_mobile_test.dart
(cd example && flutter analyze --fatal-infos)
(cd example && flutter test test/ai/terminal_ai_compact_mobile_test.dart)
(cd example && flutter test test/ai)
make terminal-core-check
make verify
```

Formatting is explicitly not verified in this environment. Keep formatter edits
and report the resulting commit/hash when returning screenshots. Use the existing
project's authorized iPhone development build/install path; this change adds no
new signing/provisioning or installation command.

## Screenshots requested from the local build

| ID | Actual state to capture | What to check |
| --- | --- | --- |
| M01 | Long reply; empty input; keyboard hidden | Compact editor; broad reading area; no extra arrow row |
| M02 | Focused multiline Chinese draft | 1–4 lines; toolbar/IME; same draft after keyboard dismissal |
| M03 | Terminal unavailable with retained reply | Task-strip reconnect + details; no repeated recovery button block |
| M04 | Expanded failure details | Actual errors/target; check/observer/SSH choices; no implicit send |
| M05 | Reconnecting → recovered | Single-flight; draft retained; zero automatic submission |
| M06 | Unknown receipt, including unavailable terminal | Receipt check stays primary; supplements are saved only |
| M07 | Reading earlier content with more below | Floating latest control outside input; no forced scroll |
| M08 | Landscape/short window and desktop regression | Controls reachable; editing value preserved; desktop layout unchanged |

For each image record build commit, device/OS, viewport, theme, keyboard and actual
connection state. A screenshot only proves visibility; duplicate-submit/IME and
reconnect assertions also require test logs or a continuous recording. Keep
failures visible in the result record; do not mark these scenarios verified until
run. Do not publish host secrets or real sensitive output in evidence.

## Rollback

Revert this isolated commit. No native protocol, persistent schema, approval or
profile changes are involved. No generated standalone package was hand-edited.
