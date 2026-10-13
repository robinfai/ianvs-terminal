# Full application UI refinement — reviewed; remote gates pending

The requested scope is **all UI, including Block and configuration forms**,
using the selected [Focused Reading reference](../mobile-block-ai-v1/results/ui-polish-2026-10-13/concept-2.png).
The application UI review and local validation are complete. Remote CI is still pending. PR #12 remains Draft; do not merge.

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

## Final coverage ledger

| Surface | Reviewed states and evidence |
| --- | --- |
| Default Block / command dock | Empty/draft/completed/failed/running/long output; completion/history/suggestions. Actual native Shell Block draft/empty states in both orientations and appearances. |
| Raw terminal / keyboard / menus | Shell entry, mobile session and desktop command menus, keyboard bar, search, paste, link/report/clipboard prompts. Native terminal/search/chrome in both orientations. |
| AI | Default/error/unknown/waiting/streaming/loading/changed-target, approvals/reader/configuration. Actual native Shell AI draft remains 56 points in all four combinations, with zero submission/write counters. |
| Connection landing / session lists | Actual shell landing/management, empty/error transitions and live/disconnected/reconnected fixtures. Native landing/connection entry. |
| SSH | Basic/advanced forms, authentication/changed-host-key, invalid jump host; imported hosts list/menu/empty/error. Native basic/advanced fields and keyboard insets. |
| Profile | Seven sections, nested appearance/fallback fonts, custom color picker/invalid hex, blank-name validation; scrolling top/middle/end. Native seven-section matrix. |
| Global settings | Five sections, nested appearance panels, remote sync, shortcut recording/unsafe/conflict; native horizontal dialog and error states. |
| SFTP | List/navigation/menu, loading/empty/error/busy/create/delete/error; native directory/menu. Transfers reuse busy state and the OS chooser; no separate app sheet exists. |
| Recording | Library list/empty/error, replay controls/options and nested recording details. Native replay/options/search/content-only. |
| Startup / master key | Onboarding/startup failure/Apple Keychain, optional sync/invalid input, recovery and disable confirmation. |
| Diagnostics / notifications | Capabilities, notifications, paste/link/report/clipboard confirmations, existing diagnostic-export notification with reveal action. Export filesystem behavior is not part of this UI-only fixture. |
| Cross-platform | Six host combinations (iOS portrait/landscape and macOS, each dark/light); native iOS 26.3.1 routes in both orientations. Final remote CI remains pending. |

The catalogue covers application-owned UI, not OS-owned file choosers or permission sheets.
In-memory fixtures establish visual/state coverage, not live backend acceptance.
Only iOS 26.3.1 simulator and the documented iOS 27.0.1 installation check were
used for this final pass; supported OS versions are not all claimed as tested.

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

## Deep-state and native application follow-up

Two actual short-window problems were reproduced and fixed without changing
approval or shortcut logic:

- OSC 52 clipboard confirmation overflowed by 10 logical pixels in landscape.
  Its title/content can now scroll while the actions remain available. Metadata
  uses neutral surface/text tokens instead of a secondary accent fill.
- Shortcut recording overflowed by 48 logical pixels in landscape. Its content
  now scrolls inside the existing dialog; title, actions, focus/key handler,
  validation, binding and conflict behavior remain unchanged.

**106 passed** for 96 deep-state captures and 10 shortcut behavior regressions;
**214 passed** for actual shell routes, startup states and shell behavior.
These are separate groups from earlier checkpoint counts and must not be added
into a project-wide unique total. Modified-file analysis is clean.

[Deep-state index](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/deep-capture-manifest.json)
lists 198 host captures: two appearances, iOS portrait/landscape and macOS.
They cover shortcut record/error/conflict, SFTP loading/empty/error/busy and
create/delete confirmation, Block running/long output, AI waiting/streaming and
approval states, shell search/trust/paste prompts, recording empty/error, and
onboarding/recovery nested states. No real external requests or destructive
operations are performed by these fixtures.

[Native shell index](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/native-shell-manifest.json)
preserves 82 PNGs from the dedicated iPhone 17 Pro simulator (iOS 26.3.1):
39 portrait and 43 landscape. Both native integration runs passed. The portrait
run has two scenario tests; the final landscape run adds shortcut recording and
error in both appearances. This checks the final shortcut layout fix natively.
Native profile pages cover seven sections in both appearances; the main shell
flow covers connection/forms/settings, terminal, SFTP and replay.

These PNGs are `integration_test` captures of the native Flutter application
rendering, **not full OS screenshots**. Gray keyboard areas are excluded system
pixels, not blank app content. Logged physical sizes/DPR and keyboard insets
verify available layout space, not physical typing or Pinyin composing. The
separate earlier compact AI proof contains full simulator captures and remains
56 logical pixels in all four dismissed states. Neither new production change
modifies the composer.

Original before/after dialog PNGs and `deep-final.log`, `shell-final.log`,
`deep-analyze.log`, `native-shell-portrait.log` and `native-shell-landscape.log`
are in the same scoped evidence directory. Native and host evidence are kept
separate. The final follow-up below closes the remaining application-owned UI rows.

Latest production Release rebuild and strict signature verification passed.
After reconnecting the phone, source `a265785f` was installed in place and
launched successfully with both saved connections and no onboarding. No new
physical UI matrix is claimed. The launch screenshot remains local because it
contains connection identifiers. [Build/install status](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/latest-build-installation.json) records this distinction. Documentation/archive contract: 20 passed.

## Final follow-up

- Final nested/entry captures: **60 + 12 tests passed**, with 126 host PNGs in
  [the final host index](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/final-host-manifest.json).
  This closes import/jump-host, expanded settings/profile, validation, recording
  details, diagnostic notification and empty/error entry states.
- Final native integration: **four scenario tests plus teardown passed per
  orientation**; [102 original application PNGs](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/native-shell-manifest.json)
  replace the earlier 82-image native index. The actual Shell Block and AI routes
  retain separate two-line drafts, with no submit/write calls.
- Native Block revealed missing Chinese glyphs hidden by substitute host fonts.
  iOS now resolves CJK through PingFang SC before Apple Symbols, retaining
  fixed-width Latin families first. Native light/dark portrait/landscape images
  confirm correct Chinese. No terminal font preference was changed.
- An existing 40-point iPad automatic-intent toolbar overflow reproduced against
  the preceding theme. The responsive width budget now includes the automatic
  intent label. Controls, order, callbacks and input handling are unchanged;
  both published terminal package copies carry the same presentation fix.
- Final local checks: **29** theme/preview/phone/iPad/desktop draft tests,
  **188** composer behavior tests, **151** composer layout/capture/golden tests
  passed. Counts overlap earlier runs and are not a unique-test sum. Modified
  Dart-file analysis and formatting pass.
- [Actual Shell AI measurements](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/final-shell-ai-measurements.json):
  **56.0 logical pixels** in all four dismissed theme/orientation combinations,
  keyboard inset zero. The Block dock has its own existing layout; the 56-point
  requirement applies to the AI composer.
- Final Release was built from `lib/main.dart`, strictly signature-verified and
  installed in place as `work.ianvs.trail`; launch confirms both saved connections
  remain and onboarding is not shown. Installation provenance is recorded
  in the updated latest-build-installation record. This is not a new physical
  keyboard/input matrix.
- Remote run 38357070249: Go and Windows passed; three Linux dependency builds
  failed on Ubuntu snapshot HTTP 503 before product tests; Apple jobs remained
  in progress at the checkpoint. The new pushed commit triggers fresh gates.
  No CI configuration or certificate policy was changed for this UI work.

Final documentation/archive contract: **20 passed**.

## Native CI harness follow-up

The final UI commit `cfe42099` passed seven remote jobs, including full repository,
visual baseline, independent package and iOS gates. The macOS native test stage
failed on different quit cases across two attempts of run 38360207790. Exact
assertion/crash details were unavailable in the previous logging setup.

The follow-up changes test scheduling and diagnostics only: callbacks receive a
five-second host allowance, a missed callback stops that test's subsequent phases,
and CI preserves xcresult diagnostics without masking the original failure. The
production shutdown timeout and all UI/runtime source remain unchanged. All 35
native cases passed eight cold-process repetitions locally (280 runs); the 20
documentation checks pass. These local repetitions do not prove the remote failure
cause or replace current CI. [Investigation and verification](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/native-harness-follow-up.txt)
and [xcresult summary](../mobile-block-ai-v1/evidence/shared/full-ui-refinement-2026-10-13/native-harness-repeat-summary.json)
record the evidence. See PR #12's latest checks for the final remote result.
