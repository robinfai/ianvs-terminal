# PR12 · Focused Reading UI QA · 2026-10-13

final result: passed

**Scope and visual target**

User selected option 2 and requested visual refinement with functionality/interactions preserved. Source: [concept-2.png](../mobile-block-ai-v1/results/ui-polish-2026-10-13/concept-2.png). Actual implementation: [12-qa-final-light.png](../mobile-block-ai-v1/results/ui-polish-2026-10-13/12-qa-final-light.png). Source base is `e1296bbf`; the evidence directory's `source-sha256.json` identifies the exact modified production files.

This implementation uses existing Flutter production widgets, system fonts, Material outline icons and Ianvs semantic colors; the generated image is only the selected visual reference. It introduces no raster assets or additional controls. Submission, approvals, tool execution, streaming, cancellation, focus handlers, task/menu actions and editor/controller identity are unchanged.

**Comparison and normalization**

- Source bitmap: 851×1848, generated concept with no reliable pixel/DPR measurement. Target: 402×874 logical pixels. Actual native iOS original: 1206×2622, DPR 3, viewport 402×874. There is no CSS viewport in this native app.
- Both images were normalized to 402×874 for [full-view comparison](../mobile-block-ai-v1/results/ui-polish-2026-10-13/qa-final-comparison.png). State: light, new task, draft `请检查当前项目的构建状态`, keyboard dismissed. The real OS status/safe-area chrome remains; source top whitespace is not an OS contract. Vertical differences attributable to native chrome are expected.
- [Focused component comparisons](../mobile-block-ai-v1/results/ui-polish-2026-10-13/qa-final-details.png) align the header, explanation and composer separately at logical scale. They are derived comparison images, never height evidence.
- [Four-state simulator matrix](../mobile-block-ai-v1/results/ui-polish-2026-10-13/simulator-matrix.png) and eight original screenshots cover native soft-keyboard expansion/dismissal, both themes and both orientations. The multi-line matrix fixture is `中文草稿\n第二行`; it differs deliberately from the one-line design-comparison fixture.

**Findings and iteration history**

1. Initial local implementation: intent wrapping increased composer height to 60 points (P1). Existing compact-height regressions and native telemetry caught it. Fixed compact label typography/spacing, retained 44-point targets, remeasured all final dismissed states at 56.0 points.
2. [First visual comparison](../mobile-block-ai-v1/results/ui-polish-2026-10-13/qa-first-comparison.png): intent label wrapped, explanatory copy left an orphaned last character, header status sat too far from its chevron (P2). Fixed label tracking/padding, balanced Chinese line break, and trailing alignment. The final full-view/detail comparisons above show all three resolved. No actionable P0/P1/P2 finding remains.
3. Native chrome, stronger existing border contrast, and system-font rasterization differ from the generated bitmap intentionally. They preserve native safe areas, theme contrast and real text rendering. Narrow/short or recovery-action headers retain the existing stacked presentation instead of hiding controls for visual fidelity.

**Required fidelity surfaces**

- Typography: existing system CJK/Latin family and fallback; fixed mobile sizes. Title 16/600, explanation 16/500 with 1.45 line height, secondary explanation 13 with 1.45 line height, condensed intent 12 with 1.25 line height and zero tracking. Existing draft text stays 16. Balanced Chinese explanation lines; title/status retain ellipsis and full status semantics. English long intent labels retain two-line capacity without growing beyond 56.
- Spacing/layout: 12 outer composer margin, radius 12, 1-point border, 72-point intent region plus 8-point separation. Circular send fill 34; touch area ≥44×44. Existing 44-point expand/dismiss targets retained. Header uses a single row only with sufficient constraints and no primary recovery action. The reading explanation remains centered and scrollable in the timeline.
- Colors/tokens: all changes use existing `appTheme.chrome`, `textMuted`, `border` and Material FilledButton state colors. Light/dark screenshots show distinct readable hierarchy and existing blue primary action. No widget-local color literals, gradients, shadows or new accent colors.
- Assets: real vector outline icons and native text; no decorative/image/logo assets in this design, no screenshot-as-UI implementation. Original PNGs remain unchanged; derived comparisons are labelled.
- Copy: same task/status/action meaning and bilingual explanation; only the Chinese supporting sentence gains a visual line break. No additional user-facing functionality or implementation language.

**Verification**

- Final static analysis: no issues. Dart format on changed sources/tests: 0 changes; `git diff --check` clean.
- Related widget regressions: **171 passed**, including six new Chinese/English × automatic/command/AI cases. They assert collapsed height, ≥44×44 hit areas and actual submission by tapping outside the 34-point circle. Existing tests cover draft/selection/controller retention, recovery, IME non-submission, unknown receipt and inactive ownership behavior.
- Native iOS integration: **2 passed**, light/dark; 56.0 points, draft/selection/controller retained, 0 API requests and 0 terminal writes.
- Simulator manual/driver matrix: **4/4 dismissed states at 56.0 points**. Each original PNG is 168 physical pixels across the complete outer border at DPR 3, confirmed at five scan lines against read-only RenderBox telemetry. Keyboard insets are positive in open states and zero in dismissed states; two-line text persists; request/write counters stay zero.
- Flutter MCP runtime errors: none. Full repository/other OS CI results are reported separately on the PR, not inferred from these scoped checks.

**Open questions / limits**

No blocking design questions. Actual tested OS is iOS 26.3.1 (23D8133), iPhone 17 Pro simulator; other supported OS majors were not simulated in this run. Drafts were seeded by Flutter Driver, then its text emulation disabled for native software-keyboard show/hide. The memory-port harness validates the real production UI and layout, not complete production authentication/session behavior, physical-phone typography, Pinyin composition, or live-server streaming. Prior physical-phone results remain historical evidence for `e1296bbf`.

**Implementation checklist**

- [x] Apply selected concept using existing tokens and controls.
- [x] Compare source and rendered UI together, including focused details.
- [x] Resolve all P0/P1/P2 visual findings.
- [x] Check both appearances, orientations, keyboard states, overflow and touch targets.
- [x] Retain multi-line drafts and verify complete composer border ≤56 logical pixels.
- [x] Run related regressions and native iOS integration; preserve reproducible evidence.

No additional P3 follow-up is required for this scope. PR remains Draft; no merge is authorized.
