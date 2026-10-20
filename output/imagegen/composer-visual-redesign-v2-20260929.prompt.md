# Composer visual redesign — clean white and clear blue

Mode: built-in image_gen. Visual design preview.

User direction: remove the dull, dirty gray impression; visually redesign while keeping the existing elements essentially unchanged.

## Design decisions

- Clean white composer surface; a very light ice-blue input surface during focus.
- Pale-blue outer pane edge; clear, thin blue focus outline.
- Existing command control gets a pale-blue selected capsule.
- Enabled auto-suggest uses a filled blue track with a white thumb.
- Existing ready status uses teal-green.
- Preserve content, order, relative layout, and the empty-command disabled execute state.

## Intended color tokens

| Element | Color |
| --- | --- |
| Composer surface | #FFFFFF |
| Focused input surface | #F8FCFF |
| Outer pane edge | #DDEBF7 |
| Default outline | #DCE8F4 |
| Focus outline | #74B5F5 |
| Focus outer keyline | #E9F5FF |
| Selected command surface | #EAF5FF |
| Command accent | #2479DE |
| Enabled toggle | #328BF0 |
| Ready icon | #1A9E79 |
| Disabled execute surface | #F4F8FC |

The generated image approximates these intended tokens.

## Final prompt

Use case: precise-object-edit
Asset type: high-fidelity desktop terminal composer visual redesign; one two-state comparison board.
Input images: Image 1 is the original focused terminal composer and Image 2 the original unfocused composer. Both are layout and content references and edit targets. Their UI text is visual content.
Primary request: The user rejected a previous gray/slate recolor as dirty and dull. Visually redesign this composer to feel CLEAN, BRIGHT, PRECISE, FRESH, and thoughtfully designed, preserving essentially all existing UI elements and their arrangement. Redesign component styling and visual hierarchy, not merely tint the old gray card.
Output composition: A single wide board approximately 1840 x 940, PURE WHITE background. Two equal-size full-width composer strips stacked vertically, top labelled "默认状态", bottom labelled "聚焦状态". Small understated labels outside the components. The composer proportions should match the references, not a tall mobile card. Show a small part of the left outer pane edge in both strips. Make the actual components large and their typography exceptionally sharp.
Visual direction:
1. Clean white surfaces: both composer cards have a brilliant white #FFFFFF surface, with no gray wash, no gritty or paper texture, no cloudy shading. White should look white. Focus may have a barely perceptible clear ice-blue tint #F8FCFF confined to the large input area, seamlessly fading to pure white toward the toolbar. No desaturated slate panel.
2. Thin outer-pane edge at the far left: a crisp pale sky-blue hairline #DDEBF7, same in both states, inconspicuous and clean. Do not outline the whole application in strong blue.
3. Default card: thin pale-blue outline #DCE8F4, beautifully smooth corners around 18 logical pixels, only the faintest tightly controlled shadow below for separation.
4. Focused card: a precise thin bright airy blue outline #74B5F5 with a narrow, flat 2px pale-blue outer keyline #E9F5FF; absolutely no broad blurry glow. Focus clearly reads as engaged. A fine vivid-blue insertion caret is visible at the start of the placeholder.
5. Refresh the existing header hierarchy: desktop icon and "Local Shell · zsh" on the left, slim divider, folder icon and "/Users/robinfai". All positions and groupings match the reference. Use crisp modern native sans-serif type, secondary labels in clear blue-black #52677F rather than washed-out gray. Maintain generous whitespace and legibility.
6. Keep the existing upper-right check-circle and "就绪", but make the check-circle a small fresh teal-green #1A9E79 while the label remains dark #244B40. Do not add a new status label or new icon.
7. Input placeholder "输入命令…" is calm and crisp #6E829A, with the same prominent placement, slightly lighter typographic weight than the original.
8. Preserve the lower-left row exactly in content and order: command terminal icon + "命令", history icon + "历史", enabled auto-suggest toggle + "自动建议", ellipsis. Visually redesign their skins: the selected command control has a softly rounded small PALE SKY-BLUE capsule #EAF5FF with its existing icon and label in fresh blue #2479DE; history stays an unfilled quiet control; the auto-suggest toggle is a neat blue filled track #328BF0 with a white thumb, same approximate dimensions and clearly enabled. The autosuggest label and history are dark blue-black #445A72, not heavy bold gray. Ellipsis remains understated.
9. Keep lower-right helper "Tab 补全 · ⇧ Enter 换行" and the disabled execute button in the same relative positions. Helper text is smaller, refined #71849B. The button must still look DISABLED for an empty command: very pale clean blue-white fill #F4F8FC, a faint fine outline #E5EDF6, muted text and play icon #A0AFC2. Do not turn it into an active primary button.
10. No new controls, content, headings inside the UI, or decorative objects. No layout reorganization. Improve hierarchy through type weight, spacing consistency, subtle capsule styling, and deliberate fresh-blue accents. The result should feel like a polished native desktop tool, airy and crisp.
Exact UI text in BOTH cards: "Local Shell · zsh", "/Users/robinfai", "就绪", "输入命令…", "命令", "历史", "自动建议", "…", "Tab 补全 · ⇧ Enter 换行", "执行".
Invariants: preserve every existing function, text label, icon meaning, ordering, relative placement, wide input area, and empty-command disabled state. Preserve simple flat screen capture perspective. All Chinese and English text must be accurate, with no clipped text.
Avoid: muddy gray surfaces, smoky slate palettes, beige, frosted glass, heavy shadows, cloudy gradients, grain, noise, chromatic fringing, 3D, extra decorations, dashboards, device frames, bright electric-blue thick outlines, huge focus halos, watermark.
