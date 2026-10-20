# Composer redesign — rendered verification

The `final/` set contains **127 real Flutter renders** of the redesigned
production Composer. The controller/provider state comes from deterministic
fixtures. This is implementation evidence, separate from the imagegen concepts
and the immutable `../before/` baseline.

Validated on macOS 27.0 (26A428), arm64, with the widget test target explicitly
set to macOS so menu shortcut labels use the Mac conventions. Other operating
systems were not tested by this capture workflow.

## Results

- Capture/state/layout matrix: **127/127 passed**. It checks state setup and
  layout exceptions, and ensures the editor, primary action, More control, and
  visible result/detail/menu regions stay within the viewport.
- UI interaction suite: **9/9 passed**. It verifies accept-before-run, history
  draft restoration, 320 px at 2× text, copying only the actual draft, the
  automatic-suggestion toggle, More/Esc, unknown-outcome recovery, and returning
  focus from completion-detail and shortcut dialogs. It also uses separate
  mouse-down, frame, drag, frame, and mouse-up events to select detail text;
  the detail editor must really own focus, the result panel must remain open,
  and the draft, selected result, ready lease, and submission state must remain
  unchanged.
- Static analysis of the two preview files and two redesign test files:
  **no issues found**.
- PNG inventory: **127 files**, with all reference-size images verified as
  **1712 × 920 physical pixels** (856 × 460 logical at 2× pixel density).

The final combined run also includes the nine macOS 27 Composer goldens:
**145/145 passed** (127 captures + 9 goldens + 9 interaction cases).
Native monospace fallback was subsequently checked with real character metrics
in the macOS integration test, fixed, and passed. All 127 fixed-font PNG hashes
remained identical after that fix. Preserved result excerpts, the intentional
native font failure before the fix, and the final Release artifact checksum are
in [verification-results.txt](verification-results.txt).

The interaction suite mocks the OS clipboard transport and asserts the exact
string sent through it. It does not claim to have tested the native system
clipboard. A selected suggestion is accepted into the draft by the first
primary-action click; the next click is the separate execution step.

## Reproduce

Run from `example/`:

```sh
/Users/robinfai/development/flutter/bin/flutter test --no-pub \
  --dart-define=COMPOSER_EVIDENCE_DIR=../docs/composer/redesign-evidence/after/final \
  test/design/composer_redesign_capture_test.dart

/Users/robinfai/development/flutter/bin/flutter test --no-pub \
  test/design/composer_redesign_layout_test.dart

/Users/robinfai/development/flutter/bin/dart analyze \
  lib/ui/previews/composer_preview.dart \
  lib/ui/previews/composer_preview_data.dart \
  test/design/composer_redesign_capture_test.dart \
  test/design/composer_redesign_layout_test.dart
```

Omit `COMPOSER_EVIDENCE_DIR` to validate the full matrix without writing PNGs.
Use `--name 'reference-light completion'` for the main reference-size scene.
The capture rejects a `before/` output path to prevent accidental replacement of
the original baseline. The detailed planned matrix is recorded in
[`final/capture-manifest.json`](final/capture-manifest.json); passing outcomes are
the test results above, not merely the presence of that manifest.

## Matrix

| Variant | Logical size | Pixel ratio | Text scale | Scenarios |
| --- | --- | --- | --- | --- |
| Light | 920 × 560 | 1 | 1× | All 27 |
| Dark | 920 × 560 | 1 | 1× | All 27 |
| Narrow dark | 360 × 740 | 1 | 2× | All 27 |
| Reference light/dark | 856 × 460 | 2 | 1× | 6 each |
| Compact light | 320 × 640 | 1 | 1× | 10 edge cases |
| Short dark window | 640 × 300 | 1 | 1× | 10 edge cases |
| High-contrast light/dark | 856 × 460 | 1 | 1× | 7 each |

The 27 scenarios include empty/ready, completion, filtered history, inline
suggestion, multiline draft, draft-only, running, sending, terminal-owned input,
unknown outcome, rejected submission, selected-text Tab guidance, no completion
matches, provider failure, no history yet, completion loading, unknown outcome
while loading static suggestions, long CJK cwd, long aliases, full completion
details, 40-row history, history with no filter match, unsupported shell syntax,
automatic suggestions on, More menu, copy feedback, and shortcut help.

The capture uses actual controller transitions for sending/rejection/unknown,
and actual UI clicks for More, copy, help, and compact completion details. In a
short viewport, the standard popup menu scrolls; the test scrolls the help item
into view before tapping it. Menu closure is verified after the route animation
has fully settled, without weakening the draft/focus assertions.

## Reviewed screenshots

- [Reference light / completion](final/reference-light-completion.png)
- [Reference dark / empty](final/reference-dark-empty.png)
- [360 px / 2× / unknown outcome](final/narrow-2x-unknown.png)
- [320 px / completion](final/compact-320-completion.png)
- [Short window / long alias](final/short-window-longAlias.png)
- [Long CJK cwd](final/narrow-2x-longPath.png)
- [Compact full completion details](final/narrow-2x-completionDetails.png)
- [More with Mac keyboard labels](final/narrow-2x-moreMenu.png)
- [High-contrast history](final/contrast-light-history.png)
- [Unknown outcome alongside completion loading](final/narrow-2x-unknownLoading.png)

The visual review checked the final hierarchy, focused outline, right-aligned
wide ownership label, narrow stacked context, last-directory path shortening,
primary Accept/Run label, result detail access, error/recovery placement, and
high-contrast boundary/selection treatment. No unresolved P0/P1 visual finding
was observed in the reviewed final scenes. This is representative visual
inspection combined with a full automated rendering matrix, not a claim that
all 127 screenshots were individually reviewed by a human.

Three early row-height failures remain under `iteration-1/` for comparison:

- [320 px row overflow](iteration-1/compact-320-completion.png)
- [2× text row overflow](iteration-1/narrow-2x-completion.png)
- [Short-window alias overflow](iteration-1/short-window-longAlias.png)

All three corresponding final scenes pass the layout checks and were visually
reviewed after the row-height correction. Other duplicate iteration PNGs were
removed; `before/` was not changed.

## Evidence limits

The renders reuse the repository's fixed-font capture workflow: Roboto,
JetBrains Mono, Noto Sans SC, and the Flutter SDK MaterialIcons font. They retain
production layout and theme tokens, but the native application's system text
and custom `TrailLightIcons.ttf` may have different glyph/stroke metrics.
Native window/icon observations and the real monospace-width regression are
recorded separately in [design-qa.md](../../../../design-qa.md), including Q7's
initial failure and verified fallback fix. Native screenshots remain in the
main chat's tool output; these fixed-font PNGs are not native-window captures.
The redesigned editor now inherits the capture CJK fallback, so
the old baseline's placeholder missing-glyph artifact no longer occurs.

This workflow does not test a native PTY/private shell bridge, real trackpad
momentum, real IME composition, VoiceOver, application lifecycle/handoff, or
other supported OS versions. Those need the separate controller/widget and
macOS application regressions. High-contrast renders demonstrate their state
and layout; they are not a measured contrast-ratio certification.
