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

- [Light overview](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/overview-light.png) / [dark overview](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/overview-dark.png)
- [Profile sections, light](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/profiles-light.png) / [dark](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/profiles-dark.png)
- [Settings sections, light](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/settings-light.png) / [dark](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/settings-dark.png)
- [Entry/recovery/authentication, light](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/entry-light.png) / [dark](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/entry-dark.png)
- [Menus and lower form sections, light](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/options-light.png) / [dark](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/options-dark.png)
- [AI components, light](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/ai-light.png) / [dark](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/ai-dark.png)
- [Landscape, light](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/landscape-light.png) / [dark](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/landscape-dark.png)
- Raw before/after images for Block, SSH, settings and profile general are in
  `../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/before-*.png` / `../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/after-*.png`.
- [Raw capture index](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/capture-manifest.json): 578 host-rendered PNGs,
  dimensions and hashes; originals remain in `build/full-ui-review/current-platform`.
- [Production source hashes](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/source-sha256.json).

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
| AI | Component states: default, error, unknown; approvals/reader/configuration | Streaming/observation/loading visual states; full shell flow (compact workspace native matrix now passed) |
| Connection landing / session lists | Actual shell landing and management; live/disconnected/reconnected fixtures | Empty/error transitions and native final check |
| SSH | Basic/advanced form, long sections, authentication and changed-host-key dialogs | Nested jump-host/import branches, keyboard-open native forms |
| Profile | All seven sections; color picker and invalid hex field, top/end; shared field changes | Remaining nested disclosure panels and profile edit/error states |
| Global settings | All five sections plus remote sync fields, top/middle/end; correct iOS capabilities | Shortcut editing, nested appearance panels |
| SFTP | Files, navigation, file menu in touch and desktop | Loading/empty/error, transfer/collision sheets |
| Recording | Actual library list, replay controls/options | Recording errors/details and native playback layout |
| Startup / master key | Onboarding, startup failure, Apple Keychain panel | Optional sync onboarding and recovery settings details |
| Diagnostics / notifications | Capabilities, standard notifications | Export/paste/security confirmation dialogs |
| Cross-platform gates | Current macOS 27 baseline candidates inspected and updated | Final full-shell native acceptance and CI rerun (10 macOS 26 CI images inspected and updated) |

## Verification at this checkpoint

- **498 passed**: current platform capture catalogue + actual shell routes,
  startup, theme, SSH forms, profile editing, AI compact input/configuration/
  discovery and replay regressions. [Log](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/full-ui-review-checkpoint.log).
- **196 passed**: terminal composer and mobile command-block behavior.
  [Log](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/full-ui-review-terminal-tests.log).
- **26 passed**: theme/high-contrast, notification, SFTP targets and session rows.
  [Log](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/full-ui-review-controls.log).
- **51 passed**: existing macOS 27 golden comparisons after inspected updates.
  [Log](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/full-ui-review-goldens-final.log).
- These runs overlap; do not add their counts into a unique-test total.
- The compact AI tests still assert the dismissed draft is <=56 logical pixels
  and controls have >=44-point hit areas. Current **native simulator** compact workspace proof passes at source `8f62e716`: 4 theme/orientation pairs, native software keyboard open/dismissed, retained two-line draft, zero request/write counters. Five PNG edge scans independently verify 168 / 3 = 56 logical pixels in every dismissed state. This does not complete the remaining whole-app native audit.
- macOS 27 existing golden changes: nine command-dock screenshots (neutral
  foreground/borders) and one scaled settings screenshot (blue switches).
  The corresponding 10 macOS 26 CI-rendered images from run 38352720965 were also inspected and updated. No 27 baselines were copied to 26; the comparator is unchanged. A new CI run must verify these updates.

## Reproduce

From `example`, with an absolute evidence directory:

```
flutter test --no-pub --dart-define=FULL_UI_EVIDENCE_DIR=/absolute/output/path test/design/full_ui_review_capture_test.dart test/design/full_shell_review_capture_test.dart test/startup/app_startup_host_test.dart
```

The startup file enables its extra capture matrix only with that define. Other
fixtures have no network, credential, file-import or real terminal side effects.
The normal visual gate remains `flutter test test/design`; changing baselines
requires inspecting actual differences, not just running `--update-goldens`.

## Native checkpoint and installation

- iPhone 17 Pro simulator, iOS 26.3.1 (23D8133), DPR 3. Actual native software keyboard, fixed fonts, CUA orientation controls. A two-line in-memory draft was seeded before `runApp`; text entry emulation stayed disabled. No physical Pinyin-input claim.
- [Raw measurements](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/native-measurements.json), eight `native-20`–`native-27` original PNGs and sidecars in the same directory. Native harness and run log are preserved there. Flutter MCP reported no runtime errors.
- [macOS 26 baseline review](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/macos-26-baseline-review.json) binds the ten inspected images to the CI artifact and before/after hashes.
- [Phone installation](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/phone-installation.json): production Release `lib/main.dart`, source `8f62e716`, installed in place as original `work.ianvs.trail`; launched successfully with both existing connections. Phone launch screenshot remains local because it contains connection identifiers. This is an installation/launch check, not a new full physical UI matrix.
- Documentation/archive contract: 20 passed after moving logs and screenshots into the allowed scoped evidence directory and scripts into `tools/ui_review`. The archive rule itself was not relaxed.

Recheck the original native screenshot measurements from the repository root:

```sh
python3 tools/ui_review/verify_compact_draft.py docs/product/mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13
```

Additional nested-form capture run: **24 passed**, with explicit SSH expansion and invalid-color assertions; no hit-test warnings or framework exceptions. [Log](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/nested-forms.log). Remote sync and color-picker originals use the `host-` prefix in the scoped evidence directory. These remain host captures, not native keyboard acceptance.
