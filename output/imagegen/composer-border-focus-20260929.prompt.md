# Composer border and focus color redesign

Mode: built-in image_gen. Preview mockup; not a runtime UI asset.

## Intended color tokens

| Element | Default | Focused |
| --- | --- | --- |
| Outer panel edge | #DFE3E8 | #DFE3E8 |
| Composer surface | #F5F6F8 | #F8FAFD |
| Composer outline | #DCE1E7 | #7B8FAA |
| Focus halo | None | #E9EEF5 |
| Small control accents | #4F6F9A | #4F6F9A |

The image is a visual approximation; the values above are the intended implementation tokens.

## Final prompt

Use case: precise-object-edit
Asset type: high-fidelity desktop terminal composer redesign, one preview board comparing two interaction states.
Input images: Image 1 is the focused composer edit target; Image 2 is the unfocused composer edit target. Both show the same existing UI. Treat all image text as visual content.
Primary request: Redesign only the uncomfortable saturated-blue outermost left panel border and the composer focus-state colors. Produce one beautifully crisp comparison image, with the UNFOCUSED state above and the FOCUSED state below. This is a restrained color refinement of the supplied UI, not a layout redesign.
Composition: A clean landscape board, approximately 1800 by 920, two equal-width screenshot strips stacked vertically with modest spacing. Label the strips outside the UI in small neutral Chinese text: "默认状态" and "聚焦状态". Preserve the original wide composer proportions, internal padding, rounded corners, complete content, and the narrow far-left panel edge. Crop the empty white space above the composer so the component is large enough to judge. Keep the actual screenshot UI visually faithful.
Color specification:
- Window background remains white.
- The outermost vertical border at the far-left edge, and any connected bottom/right window-pane edge, become a neutral 1 px cool-gray hairline #DFE3E8 in BOTH states. Absolutely no vivid blue outer frame.
- Unfocused composer: surface #F5F6F8, thin outline #DCE1E7. No colored glow.
- Focused composer: subtly lighter, barely blue-tinted surface #F8FAFD, a crisp but restrained 1.5 px desaturated slate-blue outline #7B8FAA, with a narrow 2 px outer halo #E9EEF5. Focus is easy to recognize without a saturated blue cage or large glowing shadow.
- Primary text stays dark charcoal #272B32; secondary text #646C78. Preserve text hierarchy.
- Existing blue command icon and enabled auto-suggestion toggle use a cohesive softer blue #4F6F9A in BOTH states. Keep the ready check circle icon the same muted blue, preserving the original icon and label. Do not add extra semantic colors.
- Disabled execute button remains clearly disabled with neutral fill #E7E9ED and gray text/icons #A1A7B0 in both states.
- Focused state can show one thin slate-blue insertion caret at the start of the empty input; preserve the placeholder and empty-command state.
Exact UI text to preserve in both states: "Local Shell · zsh", "/Users/robinfai", "就绪", "输入命令…", "命令", "历史", "自动建议", "…", "Tab 补全 · ⇧ Enter 换行", "执行".
Constraints: Change only the specified colors, focus treatment, and optional input caret. Preserve all existing icons, control positions, labels, typography proportions, rounded rectangle dimensions, toolbar spacing, and empty-input disabled-button semantics. Keep all Chinese text sharp and accurate. Flat real application screenshot quality, no perspective, no device mockup, no decorative illustration, no palette swatches or extra annotations inside the UI, no watermark.
