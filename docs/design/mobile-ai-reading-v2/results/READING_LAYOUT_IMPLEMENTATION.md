# Mobile reading layout: first implementation slice

Date: 2026-10-10

Base: `composer@5caba1c13a9e585f9bfa71a20074e96b4fb75841`

Status: **implemented_unverified — draft PR, not a release acceptance**.

## Scope

This is the first, independently reviewable code change from the mobile design
v2 discussion. It is not an implementation of all eight screens or all 32
acceptance cases. No native runtime, execution controller, approval policy,
terminal input ownership, source identity, or submission receipt logic changes.

### Implemented

- Narrow iOS/Android surfaces place the role above the message. There is no
  permanent avatar column beside the prose.
- One 16-point horizontal inset on each side owns the mobile reading measure.
  A standalone 390-point surface therefore allocates 358 points to the body.
  This is a layout formula, **not a measurement from a running app**; an outer
  host may apply additional constraints.
- User messages retain the existing neutral theme surface. AI prose has no
  full-message bubble. Both message bodies have the same left/right inset.
- Local `LayoutBuilder` constraints select the narrow layout below 600 points.
  A narrow tablet pane benefits even in a wide window. macOS/Windows/Linux
  retain the existing side-by-side role layout even in narrow desktop panes;
  wide tablet surfaces retain it as well.
- Narrow mobile Markdown uses 18-point list indentation, 8-point code-block
  padding, 8-point horizontal quote padding, and 12-point block spacing. The
  desktop values remain 24/12/12/8 respectively.
- Body font size, monospace font selection, theme color roles, raw Markdown,
  command bytes, link handling and the no-remote-image-loading policy remain
  unchanged. No zero-width breaks or newlines are inserted into file paths.

### Not implemented in this slice

Reading-state compact Composer; navigation/task-header consolidation; task
controls outside the Composer; revised pause/running status copy; task-local
compact source blocks; inline-code background redesign; list folding; input or
approval redesign. Existing behavior for these surfaces remains unchanged.

The original visual discussion included unsupported or misleading items (voice
input, arbitrary attachments, invented progress/elapsed values, and manually
marking an unknown submission successful). None are implemented.

## Files

- Production: `example/lib/features/ai/terminal_ai_message.dart`
- New regression tests:
  `example/test/ai/terminal_ai_message_mobile_layout_test.dart`
- Existing regressions to keep:
  `example/test/ai/terminal_ai_message_test.dart`

These are product-host files. No canonical terminal package or generated
standalone source was edited; do not hand-edit the generated mirror.

## Regression coverage added (not run here)

1. 320/375/390/430-point mobile surfaces, both light/dark themes and user/AI
   roles: actual body render box must be W-32 with the role above the body.
2. A narrow message surface inside a 1728-point window: use local constraints,
   not global screen width.
3. macOS widths 390/900/1728 at text scales 1 and 2: retain the original
   maximum reading width, role column and text-scaling behavior.
4. Wide tablet and narrow Android presentation boundaries. A widget fixture
   is not an Android or tablet release/support claim.
5. Full message-frame plus Markdown selection: preserve a Chinese path with
   spaces, a shell command with a literal backslash-n, file names and copy
   behavior; do not fetch Markdown images or acquire an input client.
6. Keep one vertical reading scroll and the existing body font size. Mobile
   and desktop Markdown spacing are tested separately.

## Validation record

| Check | Result |
| --- | --- |
| Base file bytes match fetched GitHub blob `f9bdbc8762e2de0d87184891922067ca5aec4638` | Passed locally |
| Whitespace/conflict-marker inspection and `git diff --check` | Passed locally |
| Dart formatting and static analysis | Not run: Dart/Flutter unavailable |
| Flutter widget tests, including new tests | Not run: Flutter unavailable |
| Complete repository `make verify` | Not run |
| Real App, native PTY/SSH, physical iPhone/IME/VoiceOver | Not run |
| Actual App screenshots/recording | Not captured |

The editing environment is Linux without Dart/Flutter. A public Git clone
attempt failed at DNS resolution; dependencies could not be fetched. Source was
read and will be committed through the connected GitHub API. Text-level checks
are not a substitute for compilation, widget execution, or visual review.

## Required checks before merge

From the complete repository in its supported Flutter/macOS environment:

```sh
dart format --output=none --set-exit-if-changed \
  example/lib/features/ai/terminal_ai_message.dart \
  example/test/ai/terminal_ai_message_mobile_layout_test.dart
(cd example && flutter analyze --fatal-infos)
(cd example && flutter test test/ai/terminal_ai_message_test.dart \
  test/ai/terminal_ai_message_mobile_layout_test.dart)
(cd example && flutter test test/ai)
make terminal-core-check
make verify
```

If the formatter reports changes, apply them and repeat the checks. Record real
exit codes and the exact implementation commit. Do not describe queued CI as a
pass. This PR must stay draft until the required checks and visual review are
complete.

## Screenshots still required

Capture the real App for a long Chinese reply with file names, a long command,
and an evidence link: narrow phone light/dark, a narrow tablet pane, and desktop
wide/narrow. Use the same content before/after. Measure the body render box,
not a phone-frame mockup. Also verify selection/copy and rotation/resize during
reading; crossing the 600-point layout breakpoint deserves explicit review.

Save original images under a new evidence directory and embed them in a later
verification report tied to the tested implementation commit. No generated or
HTML design image is accepted as running-App evidence. No placeholder image is
presented as a screenshot in this report.

## Rollback

Revert this isolated commit to restore the old message frame and spacing. No
persistent data migration or runtime protocol change is involved.
