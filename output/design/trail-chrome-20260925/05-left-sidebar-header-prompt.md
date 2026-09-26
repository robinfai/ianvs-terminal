# 侧栏展开模式：标题与命令入口集中在左侧

生成方式：内置 imagegen。

[效果图](05-left-sidebar-header.png)

顶部顺序：红黄绿窗口按钮、Trail 应用名、侧栏开关、设置齿轮。设置齿轮仍作为统一命令面板入口。右侧顶部留空，active 目录的文件夹与路径文字高亮规则延续上一版。

仅更新视觉提案，未修改应用代码；生成图中的 terminal 文本不作为逐像素保真的原始截图。

## 完整提示词

```text
Use case: precise-object-edit.
Asset type: one polished macOS Trail app UI screenshot, revising the current sidebar-open design.
Input image: Image 1 is the exact edit target, the latest approved-direction mockup. Edit this image rather than creating a new composition.
Primary request: In this split/sidebar-open mode, move BOTH the app name 'Trail' and the settings gear into the LEFT sidebar header. The main/right header must become completely empty.
Target framing: preserve the input's approximately 1119 x 1405 portrait dimensions, aspect ratio, full window, sidebar width around 358 px, and current thin full-height vertical divider. One screenshot, no collage, no annotations.
Perform only this local header change, y=0..58:
- Left header retains its pale gray continuous sidebar surface.
- Keep the red/yellow/green native traffic lights in their exact positions at the far left.
- Place the single 'Trail' app name immediately to the right of the traffic-light group, at approximately x=122, in the same understated semibold dark UI font.
- At the right end of this SAME LEFT header place the existing sidebar-toggle icon at approximately x=287 and the settings gear at approximately x=328. The gear is the unified command palette entry point. Both icons have the same optical size and stroke weight.
- All traffic lights, the 'Trail' title and both icons share the same geometric centerline y=28. Keep breathing space and native compact hit targets. No visible button boxes.
- REMOVE the previous 'Trail' text from the right content header and REMOVE the gear from the far top-right corner. Do not duplicate them. The entire right header x>=358 is plain white, with no title, toolbar controls, text, dividers, palette hints or new features.
- Keep the command palette CLOSED. All history/search/settings/more functionality is conceptually in that palette; do not add separate action icons anywhere.

Invariants: Everything below y=58 stays as in the source. Preserve terminal rectangle and text, font, rainbow shell prompt segments, positions, times, whitespace and cursor. Do not expand terminal upward or move any terminal line. Preserve sidebar heading '会话', its plus action, section '目录 2', both paths and both sessions, row geometry and selection state. Active '/Users/robinfai' folder icon AND path remain blue; inactive 'Documents/AI/records' folder icon and path remain default dark neutral. Selected remote session retains its existing pale blue fill. No changes to the typography or indentation of the tree. Preserve outer window corners and all other geometry. No added status badges, toolbar, tab bar, footer or watermark.
Style: crisp native macOS utility UI, SF Pro/PingFang-like typography, flat surfaces and restrained existing colors. Output the single edited screenshot only.
```
