# 侧栏顶部：应用名在两个图标之间居中

生成方式：内置 imagegen。

[最终效果图](06-centered-title-between-icons.png)

顶部顺序为窗口按钮、侧栏图标、Trail、设置齿轮。应用名按侧栏图标与设置图标之间的区域居中。保留右侧顶部空白、命令面板统一入口及 active 目录高亮规则。此文件为视觉提案，未修改应用代码。

## 初始编辑提示词

```text
Use case: precise-object-edit.
Asset type: one revised native macOS Trail UI mockup.
Input image: the attached image is the latest mockup and exact edit target, approximately 1119 x 1405 pixels. Preserve its dimensions, aspect ratio and entire composition.
Primary request: refine the sidebar-toggle icon and place the app title 'Trail' centered BETWEEN the sidebar-toggle icon and the settings gear.

Edit ONLY the left header area, x=0..357, y=0..58:
- Keep the red/yellow/green traffic-light buttons exactly at their current positions around x=22,52,82.
- Arrange the remaining header controls in THIS exact left-to-right order: sidebar toggle, 'Trail' title, settings gear.
- Move the sidebar toggle to center x=126, y=28.
- Put the settings gear at center x=326, y=28.
- Put the 'Trail' title at center x=226, y=28, EXACTLY halfway between the two icon centers. The title is centered between the icons, not centered within the full sidebar and not placed beside the traffic lights. The horizontal distances from title center to each icon center must be equal.
- Refine the sidebar toggle into a crisp native 'sidebar.left' line icon: a horizontal rounded rectangle window outline, one vertical internal divider near the LEFT third, clearly representing the LEFT sidebar. No dots, tiny squares or right-side split. Use a clean shape that reads at small size.
- Match the sidebar toggle and gear in perceived size, dark neutral color and stroke weight, approximately 17-18 image pixels in height. No filled button backgrounds or boxes around either control.
- Both icons, the title and all three traffic lights are vertically centered on precisely the same y=28 horizontal centerline.
- Retain the title's current semibold size and color. The settings gear still represents the unified command palette launcher.

Invariants: Make NO changes elsewhere. Preserve the pale-gray left sidebar surface, vertical divider at x=358, empty white right-side header, outer window corners, all sidebar rows, Chinese labels, both folder paths, terminal glyphs, tree indentation, selected-session fill and active directory blue color. Preserve the entire terminal region, all text, rainbow prompt segments, times, cursor, whitespace and existing positions. Do not add any controls, status indicators, tooltips, footer, tabs or extra labels. Only one clean edited screenshot, no annotations or variants.
```

## 最终校正提示词

```text
Use case: precise-object-edit.
Input: the attached latest Trail screenshot is the edit target. Output ONE revised screenshot of exactly the same size and framing.
Make a tiny precision correction to the left header ONLY. Everything below y=58 and everything right of the sidebar divider must remain identical.
The header currently has traffic lights, sidebar toggle centered near x=154, the word 'Trail', and a gear centered near x=330, all on y=28.
1. Keep both icon centers at x=154 and x=330, y=28. Place the text 'Trail' with its visual bounding-box CENTER precisely at x=242, y=28, the exact midpoint between the icons. Shift the current title about 7 pixels LEFT; do not shift the icons. Its visible text should span approximately x=219..265. Keep the original understated semibold font size, no larger or heavier.
2. Correct the sidebar icon to depict a LEFT sidebar: rounded rectangular outline approximately x=143..165 and y=19..37, with the thin vertical internal divider at x=150 (one third from the LEFT), leaving the WIDER blank panel on the RIGHT. The divider must NOT be at the right third. No dots, boxes, fill, or other decoration.
Retain gear design, all traffic lights, neutral colors, alignment, sidebar width, pale gray surface and the empty white right header. No explanatory text, no title duplicates, no ruler, no guide lines. Preserve every sidebar row and all terminal text, colorful prompts, cursor and whitespace. Output just the final corrected app screenshot.
```
