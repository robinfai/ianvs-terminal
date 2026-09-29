# Composer V4 — caret-only focus

Mode: built-in image_gen. Visual design preview.

User-directed refinements:
- Remove the input underline.
- Remove the separate vertical rail and colored strip outside the left card border.
- Show focus only with the insertion caret; keep the card border, surface, and control styling consistent between states.
- Keep the existing UI elements and “Shell 就绪” status.

## Final prompt

Use case: precise-object-edit
Asset type: minimal revision to the supplied two-state desktop composer design board.
Input image: the attached V3 comparison board is the single edit target.
Primary request: Apply ONLY the user's final cleanup: no input underline; no little colored strip to the LEFT of the composer border; focus is shown only by the insertion caret.
Required edits:
1. In the bottom "聚焦状态" card, DELETE the short blue horizontal underline below "输入命令…". Restore that area to the same uninterrupted pure-white card surface. KEEP the thin blue vertical insertion caret immediately before the placeholder.
2. In BOTH cards, DELETE the separate straight vertical rail and the narrow pale-blue/gray rectangular strip immediately OUTSIDE the rounded rectangle's far-left edge. In the reference these appear as a vertical segment and faint tinted block to the left of each card. Replace the entire external left gutter with the same clean white as the presentation canvas. No leftover sliver, colored side tab, vertical marker, tint patch, or protruding straight line.
3. KEEP the actual rounded composer border continuous and intact on all four sides, including its smoothly rounded left corners. Its thin neutral color must be uniform on all sides, with no accent segment at the left.
4. Match the focused card's outline, white fill, and subtle shadow to the default card. The ONLY visual difference indicating focus should be the insertion caret. No focus underline, blue outline, added glow, surface tint, heavier left edge, or changed status/control color.
Preserve absolutely everything else: two stacked wide cards with the same positions and proportions; board labels "默认状态" and "聚焦状态"; white canvas; header icons and spacing; font sizes and weights; top-right small status dot and "Shell 就绪"; the selected pale-blue "命令" capsule; history icon and label; filled blue enabled autosuggest switch and its label; ellipsis; keyboard helper; disabled execute button. Do NOT remove or recolor the blue selected command capsule—it is an existing control, not the unwanted exterior strip.
Exact text remains: "Local Shell · zsh", "/Users/robinfai", "Shell 就绪", "输入命令…", "命令", "历史", "自动建议", "…", "Tab 补全 · ⇧ Enter 换行", "执行", "默认状态", "聚焦状态".
Output: the same crisp flat two-state UI comparison board, with accurate Chinese and English text. No new elements, no redesign of other controls, no textures, no watermark.
