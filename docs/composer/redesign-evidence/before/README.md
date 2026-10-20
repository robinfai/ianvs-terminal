# Composer redesign — current UI evidence

Captured from commit `5f164bea66d4885dd3245604bbb960ff26e6ddc6` on branch
`composer`, before the redesign. These PNGs render the production
`TerminalComposerView`, `ComposerEditor`, and `ComposerSuggestions` in Flutter;
the shell/provider state is supplied by deterministic fixtures. They are actual
widget renders, not design mockups, and do not prove a native shell integration
or physical trackpad interaction.

Host: macOS 27.0 (26A428), arm64. No other OS was used for this capture.

## Reproduce

Run from the repository's `example/` directory:

```sh
/Users/robinfai/development/flutter/bin/flutter test --no-pub \
  --dart-define=COMPOSER_EVIDENCE_DIR=../docs/composer/redesign-evidence/before \
  test/design/composer_redesign_capture_test.dart
```

For a later design, change the output directory to `../docs/composer/redesign-evidence/after`.
Omitting `COMPOSER_EVIDENCE_DIR` runs the state/render checks without saving PNGs.
Keep this `before/` set unchanged when comparing a later implementation.

The capture reuses the repository's shadow-enabled test binding and pinned
Roboto, JetBrains Mono, and Noto Sans SC capture fonts. It retains production
ColorScheme, dimensions, component themes, and code style. Every PNG has device
pixel ratio 1, so image dimensions equal the logical viewport dimensions.

## Coverage

All 16 scenarios are captured in three variants, for 48 PNGs:

| Prefix | Viewport | Appearance | Text scale |
| --- | --- | --- | --- |
| `light-` | 920 × 560 | Light | 1× |
| `dark-` | 920 × 560 | Dark | 1× |
| `narrow-2x-` | 360 × 740 | Dark | 2× |

| Scenario suffix | Setup represented |
| --- | --- |
| `empty` | Ready shell, empty focused editor, disabled run |
| `completion` | Two command completions, selected row, description |
| `history` | Filtered command history, newest selection, popup navigation |
| `suggestion` | History-derived inline suffix, outside the draft document |
| `multiline` | Three-line shell draft with wrapping at narrow width |
| `draft` | Editable local draft without a ready shell lease |
| `running` | Shell running, next draft preserved and execution disabled |
| `submitting` | Real controller submission waiting for its result |
| `suspended` | Terminal owns input, composer draft preserved |
| `unknown` | Real unknown submission outcome with recovery action |
| `rejected` | Real rejected submission, retained draft and recovery action |
| `selection` | Tab on a nonempty selection, guidance displayed |
| `noCompletions` | Explicit Tab receives an empty completion batch |
| `unavailable` | Completion provider fails, editing remains available |
| `emptyHistory` | Open history with no matching entries |
| `loading` | Completion request intentionally remains pending |

Representative references:

- [Light completion](light-completion.png)
- [Dark completion](dark-completion.png)
- [History](light-history.png)
- [Inline suggestion](light-suggestion.png)
- [Narrow history](narrow-2x-history.png)
- [Narrow unknown result](narrow-2x-unknown.png)

## Checks and observations

- Existing Composer golden test: **9/9 passed** against the current commit.
- New state/render capture matrix: **48/48 passed**, with no Flutter layout
  exceptions across these fixtures.
- `dart analyze test/design/composer_redesign_capture_test.dart`: no issues.
- Representative wide and narrow screenshots were visually inspected, including
  completion, history, inline suggestion, all warning text treatments, sending,
  loading, multiline, and recovery. This is a baseline inventory, not a claim
  that every interaction or accessibility property is satisfactory.

Observed redesign targets:

1. Draft, running, sending, and suspended states use the same small icon and do
   not show their distinguishing text until hover. Running/suspended UI still
   displays the ordinary Tab-completion hint.
2. The folder icon controls automatic suggestions but resembles a directory
   picker. Its purpose is only explained in the tooltip.
3. At 360 px and 2× text, the mode label disappears and the target label is
   reduced to `L…`. This avoids overflow but leaves context unclear.
4. Unknown-result text and the recovery button stay side by side in the narrow
   view. The warning becomes a short-column paragraph beside a large action.
5. History and completions have no persistent scroll indicator; additional rows
   are not readily discoverable from a still image.
6. The empty editor's Chinese placeholder has missing glyphs in this pinned-font
   capture. The editor's explicit non-inheriting monospace style omits the test
   theme's CJK fallback. The user's native screenshot renders that text correctly;
   this evidence does **not** establish a native application missing-glyph bug.

The isolated fixture does not exercise session focus transfer, PTY execution,
private-bridge leases, actual OS clipboard operations, hover tooltip timing, or
physical trackpad momentum. Those need existing controller/widget/integration
regressions and, where relevant, native interaction checks in the final redesign.
