# Header tabs — selected direction 1

final result: passed

## Source and comparison

- Visual target: [selected-reference.png](selected-reference.png), the first displayed ImageGen result selected by the user. Header surface, colors, compact native typography and subtle raised active tab are the target. User explicitly overrides the mock's always-visible inline shortcuts with a shared trailing Cmd/close slot.
- Rendered production components: [comparison.png](screenshots/comparison.png); full widget captures in `screenshots/`.
- Source: 2155 × 730 px including generated black canvas padding. Comparison extracts source header `(0,258,2155,358)` and normalizes it to 1742 × 81 px. App captures: 871 × 300 logical px at 2× (1742 × 600 px); comparison extracts top 90 physical px. Narrow captures: 640 × 300 and 520 × 300 at 2×. The last has 2× text scaling.
- State: middle of three Local Shell tabs selected; default, first-tab hover, Cmd-only; light and dark. Overflow after adding further tabs is separately captured. The source has notification dots and overflow, whereas the three-tab fixture is idle without hidden sessions; notification, badge and overflow behavior is covered by existing production-component tests. Native traffic lights and colorful user shell prompt are outside Flutter's header component; their absence from the fixture is not a design change.
- Focused comparison: the same sheet contains only header crops so title typography, slot placement, padding, corner rounding and active/hover surfaces remain readable. [Baseline before/after](screenshots/baseline-diff-review.png) shows six changed desktop screenshots, including long titles, pane counts and output dots.

## Findings and comparison history

- Initial rendered dark-theme hover was brighter than the selected surface (P2). The active surface now blends 6% semantic primary text over its theme surface. Recaptured dark default and hover in the comparison show the selected tab remains prominent. No P0/P1/P2 issues remain.
- Fonts/typography: retain existing 12.5 logical px titles, selected weight 600 and inactive 500. Shortcut 11 logical px, weight 500, muted. Widget captures load deterministic production icon/font fixtures; they do not establish exact native SF rasterization.
- Spacing/layout: preserve existing equal-width/capped tabs, visible count, overflow decisions, drag targets and native drag gap. Add 3 logical px tab inset and rounded track; fixed trailing slot is at least 28 logical px and grows for text scaling. Cmd state does not shift the title or slot. No new decoration competes with status indicators.
- Colors/tokens: retain shell chrome/theme colors; active light surface uses white field token and subtle theme shadow. Dark selection uses the semantic blend above. No new palette or image assets in runtime.
- Images/icons: retain existing production icon font, title, activity dots and profile/status badges. The selected mock is documentation only, not a raster UI replacement.
- Copy/content: existing titles, tooltips, named close semantics and input behavior unchanged. No new product wording.

## Interaction verification

- Active close is visible by default; inactive close appears on hover or keyboard focus. Hidden controls are excluded from hit testing and accessibility semantics.
- Cmd alone shows ⌘1…⌘9 in the same trailing slot, including compact tabs. Cmd with another key hides the hint; actual Cmd-number switching still works. Both Command keys, window focus loss and release/background reset are covered. The observer consumes no key events.
- Close hit area increases from 12 to 28 logical px on desktop. Existing close protection remains the only close path. Touch presentation retains existing behavior.
- Four new theme/width scenarios pass, including 520 px with doubled text. Associated regression suite: 139 passed; all design tests: 839 passed, 1 existing skip. Main application interaction suite: 103 passed. Native macOS unified workspace test: 1 passed; production Release build passed. Analysis clean.

## Limits and follow-up

macOS 27.0.1 local Flutter rendering; no new physical-device installation or full OS compatibility matrix. The six macOS 26 baselines were independently reviewed from CI run 38992833766, commit 62f45975570f3213789ae0073ee630903052ffac, artifact visual-comparison-failures (12086571221). Each old master image was verified byte-for-byte against the checked-in baseline before replacement with that same runner’s actual test image. See [macOS 26 comparison](screenshots/macos26-baseline-review.png) and [provenance](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/header-tabs-2026-10-17/evidence/macos26-baseline-provenance.json). Latest CI must rerun after this baseline-only/test follow-up; this review does not claim green CI. No open design decisions. PR remains Draft and unmerged.
