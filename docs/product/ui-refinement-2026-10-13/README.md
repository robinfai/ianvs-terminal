# Full application UI refinement — in progress

The requested scope is **all UI, including Block and configuration forms**,
using the selected [Focused Reading reference](../mobile-block-ai-v1/results/ui-polish-2026-10-13/concept-2.png).
This checkpoint is not final acceptance. PR #12 remains Draft; do not merge.

## Changes in this checkpoint

- Shared mobile typography: 16-point section/page headings, 12-point secondary
  labels; body text, editable text metrics and padded touch targets retained.
- Shared mobile form outlines: 12-point corners, neutral separators, visible
  focus/error treatments. Increase Contrast retains thicker, stronger outlines.
- Block and command dock: neutral text/separators instead of blue-tinted text;
  less vertical padding on touch. Existing controls, order and callbacks retained.
- Profile editor: remove the extra mobile search/navigation card, unify the
  content surface, reduce large field/group gaps, use shared mobile rule fields.
- AI connection configuration: external field labels and subdued explanatory
  copy, using the same form component as SSH. Keys, controllers, validators,
  field order, discovery, testing, saving and approval configuration unchanged.
- AI approval cards: 16-point padding, 12-point corners; keep active accent border
  and all existing confirmation controls. Adaptive settings/replay switches use
  the existing blue action color consistently.

No controller, request, persistence, navigation, submission, cancellation or
execution logic is changed. Terminal font preferences are not changed. The
published terminal/core copies have the same presentation-only spacing patch.

## Current evidence

The capture catalogue renders production widgets with in-memory fixtures at
402×874, 874×402 and 1280×900 logical pixels, both appearances. It uses the actual
`TargetPlatformVariant` as well as the theme, and platform-appropriate settings
capabilities. It saves the first viewport plus middle/end of scrollable forms.

- [Light overview](evidence/overview-light.png) / [dark overview](evidence/overview-dark.png)
- [Profile sections, light](evidence/profiles-light.png) / [dark](evidence/profiles-dark.png)
- [Settings sections, light](evidence/settings-light.png) / [dark](evidence/settings-dark.png)
- [Entry/recovery/authentication, light](evidence/entry-light.png) / [dark](evidence/entry-dark.png)
- [Menus and lower form sections, light](evidence/options-light.png) / [dark](evidence/options-dark.png)
- [AI components, light](evidence/ai-light.png) / [dark](evidence/ai-dark.png)
- [Landscape, light](evidence/landscape-light.png) / [dark](evidence/landscape-dark.png)
- Raw before/after images for Block, SSH, settings and profile general are in
  `evidence/before-*.png` / `evidence/after-*.png`.
- [Raw capture index](evidence/capture-manifest.json): 536 host-rendered PNGs,
  dimensions and hashes; originals remain in `build/full-ui-review/current-platform`.
- [Production source hashes](evidence/source-sha256.json).

These are **host widget captures with deterministic substitute fonts**, not
native iOS screenshots. They establish layout/rendering evidence, not native
keyboard, safe-area or physical-device acceptance. The profile editor catalogue
also exercises reusable sections beyond those directly exposed by each platform's
connection management route. Do not count that as route coverage.

## Coverage ledger and outstanding work

| Surface | Current inspection | Remaining before completion |
| --- | --- | --- |
| Default Block / command dock | Completed/failed output, dock, desktop completion/history/suggestion baselines; touch/desktop rendering | Native actual shell draft, empty/running/long-output visual pass |
| Raw terminal / keyboard / menus | Shell entry, mobile session menu, desktop command menu, keyboard bar | Search, paste/link-trust prompts, live native chrome |
| AI | Component states: default, error, unknown; approvals/reader/configuration | Whole workspace native keyboard matrix; streaming/observation/loading visual states |
| Connection landing / session lists | Actual shell landing and management; live/disconnected/reconnected fixtures | Empty/error transitions and native final check |
| SSH | Basic/advanced form, long sections, authentication and changed-host-key dialogs | Nested jump-host/import branches, keyboard-open native forms |
| Profile | All seven sections, top/middle/end; shared field changes | Color picker, nested disclosure panels and edit/error states |
| Global settings | All five sections, top/middle/end; correct iOS capabilities | Remote sync credentials, shortcut editing, nested appearance panels |
| SFTP | Files, navigation, file menu in touch and desktop | Loading/empty/error, transfer/collision sheets |
| Recording | Actual library list, replay controls/options | Recording errors/details and native playback layout |
| Startup / master key | Onboarding, startup failure, Apple Keychain panel | Optional sync onboarding and recovery settings details |
| Diagnostics / notifications | Capabilities, standard notifications | Export/paste/security confirmation dialogs |
| Cross-platform gates | Current macOS 27 baseline candidates inspected and updated | macOS 26 candidate review; final simulator acceptance and CI |

## Verification at this checkpoint

- **498 passed**: current platform capture catalogue + actual shell routes,
  startup, theme, SSH forms, profile editing, AI compact input/configuration/
  discovery and replay regressions. [Log](evidence/full-ui-review-checkpoint.log).
- **196 passed**: terminal composer and mobile command-block behavior.
  [Log](evidence/full-ui-review-terminal-tests.log).
- **26 passed**: theme/high-contrast, notification, SFTP targets and session rows.
  [Log](evidence/full-ui-review-controls.log).
- **51 passed**: existing macOS 27 golden comparisons after inspected updates.
  [Log](evidence/full-ui-review-goldens-final.log).
- These runs overlap; do not add their counts into a unique-test total.
- The compact AI tests still assert the dismissed draft is <=56 logical pixels
  and controls have >=44-point hit areas. Current **native simulator** proof is
  pending. Previous native results belong to the earlier AI-only commit.
- macOS 27 existing golden changes: nine command-dock screenshots (neutral
  foreground/borders) and one scaled settings screenshot (blue switches).
  Review the macOS 26 CI-rendered candidates separately; do not copy 27 baselines
  to 26 or relax the comparator.

## Reproduce

From `example`, with an absolute evidence directory:

```
flutter test --no-pub --dart-define=FULL_UI_EVIDENCE_DIR=/absolute/output/path test/design/full_ui_review_capture_test.dart test/design/full_shell_review_capture_test.dart test/startup/app_startup_host_test.dart
```

The startup file enables its extra capture matrix only with that define. Other
fixtures have no network, credential, file-import or real terminal side effects.
The normal visual gate remains `flutter test test/design`; changing baselines
requires inspecting actual differences, not just running `--update-goldens`.
