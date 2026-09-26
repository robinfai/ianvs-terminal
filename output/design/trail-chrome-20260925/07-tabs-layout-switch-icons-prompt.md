# 顶部 tabs / 侧边栏 tabs 切换图标

生成方式：内置 imagegen。此交付为图标视觉方案，未修改应用代码。

[最终对照图](07-tabs-layout-switch-icons.png)

## 设计与交互

- 两个图标共享同样的圆角窗口外框与线条重量。
- 顶部 tabs：顶部横向分段标签条，下方保留完整内容区。
- 侧边栏 tabs：左侧纵向排列的标签列表，右侧保留完整内容区。
- 单个切换按钮显示目标布局：当前侧栏模式显示顶部 tabs 图标；当前顶部模式显示侧栏 tabs 图标。
- 悬停提示分别为“切换到顶部标签”和“切换到侧边标签”。
- 默认采用中性文字色；悬停仅增加轻微底色。与目录 active 高亮状态相互独立。
- 图中 16/18/20 px 为设计目标尺寸示意；最终矢量实现需按实际设备缩放检查。

## 完整生成提示词

```text
Use case: ui-mockup.
Asset type: a focused icon design presentation for Trail, a native macOS terminal application.
Input image: Image 1 is a STYLE AND CONTEXT REFERENCE ONLY, showing the latest accepted Trail design. This is NOT a request to alter its terminal. Borrow its native light-gray sidebar chrome, black typography, clean outline icons, compact header rhythm, and app-name-between-icons arrangement.
Primary request: redesign the paired icons for switching between TOP TABS and LEFT SIDEBAR TABS. The existing split-pane glyph is ambiguous. Create ONE coherent final icon family with two related glyphs, shown in a clean comparison sheet with actual toolbar examples. These are two states of the SAME single layout-switch button, NOT two options, NOT a segmented control and NOT a new multi-button toolbar.

Canvas: landscape 1600 x 1100 pixels, high-resolution crisp UI design sheet. Clean off-white background, precise whitespace, no mock device, no perspective, no gradients, no colorful decorative illustrations, no nested cards. Two aligned columns.
Typography: SF Pro/PingFang-like system font. All Chinese labels exact. Main page heading at upper left: '标签布局切换'. A small subdued subtitle: '横向与纵向，一眼区分'. Do not add branding slogans.

ICON FAMILY GEOMETRY:
Both glyphs share the SAME horizontally oriented rounded rectangular WINDOW FRAME, approximately 18x16 logical pixels, 2-point corners, 1.5-point dark neutral stroke #55565A, rounded line ends and carefully balanced optical weight. Both keep a single large empty content area. Never simply rotate the whole window frame.
A. TOP-TABS glyph: inside the top of the frame, three small adjacent horizontal tab cells read clearly as a tab strip; below is one uninterrupted empty content area. The tab strip takes about the top quarter of the window. At small sizes use two or three clear chunky tab divisions, with no dots, text or microscopic strokes.
B. SIDEBAR-TABS glyph: inside the left portion of the SAME window frame, three short rounded horizontal marks stacked vertically represent the tab list; the wide right portion is uninterrupted empty content. The left strip takes about one third of the width, separated by a single divider. It must be a LEFT sidebar, never right. Keep the three marks resolvable at native 18-point size. Do not use generic equal split-panes, arrows, swap symbols, hamburger menus, browser chrome dots or extra overlays.
The two icons must be immediately distinguishable as horizontal tab strip vs vertical tab list.

SHEET STRUCTURE:
- Left column header: '顶部 tabs'; right column header: '侧边栏 tabs'.
- Under each heading, show a large crisp magnified example of its glyph, about 112x96 pixels, with ample space. These large examples are simple neutral line drawings with no button background.
- Below each large icon show a compact matched row of actual rendered sizes labeled '16 px', '18 px', '20 px'. Glyphs in these previews must actually be small; leave whitespace around them.
- Show one neutral default example labeled '默认' and a second identical glyph on a very subtle pale-gray rounded hover surface labeled '悬停'. Only the hovered button gains a background, no persistent selected or blue status fill. Keep glyph shape the same between states.
- Lower third: two realistic shallow cropped Trail header/context strips, one under each corresponding icon, NOT complete app windows and NO terminal code. These are examples of a single header: native traffic lights at left, ONE layout-switch icon, title 'Trail' visually centered BETWEEN that icon and a single settings gear. A single small sidebar snippet beneath establishes current layout only when needed.
- Under the LEFT icon, label the strip '当前：侧边栏 tabs'. Its single layout-switch button shows the TOP-TABS glyph because clicking it moves tabs to the TOP. Small caption '切换到顶部标签'.
- Under the RIGHT icon, label the strip '当前：顶部 tabs'. Its single layout-switch button shows the SIDEBAR-TABS glyph because clicking it moves tabs to the LEFT SIDEBAR. Small caption '切换到侧边标签'.
- The icon names label DESTINATION layouts; each toolbar shows exactly one switch button and one gear. Do not accidentally invert the two target glyphs.
- Add one discreet bottom note: '图标表示目标布局，点击即可切换'. All captions are outside toolbar examples, not added to the app itself.
Palette matches Trail: background #F5F5F7 or white, default icon/text #55565A and #1D1D1F, divider #D1D1D6, quiet hover #EDEEF2. No blue folder icons, no connection indicators, no terminal redesign. Deliver one legible professional icon study, not multiple alternative designs.
```

## 上下文示例修正提示词

```text
Use case: precise-object-edit.
Input: the attached icon design sheet is the exact edit target.
Make ONLY a correction to the two small application context previews in the BOTTOM third. Preserve the entire upper icon study, heading, all magnified icons, size examples, default/hover states, column geometry, caption labels and final note unchanged. Preserve the canvas dimensions and design quality.
Problem to fix: both bottom previews currently show a sidebar, despite the right example being labeled current TOP TABS. Also, in the sidebar mode the title and gear should belong to the sidebar header.
Correction:
LEFT bottom preview, caption '当前：侧边栏 tabs': this is a cropped close-up of ONLY the sidebar component. Preserve its header with traffic lights, top-tabs target icon, 'Trail' centered between the target icon and gear. The pale gray sidebar should fill the entire width BELOW this preview's header, with '会话', plus, and '目录 2' positioned naturally. REMOVE the interior vertical divider and white right section in this left preview, because this crop is solely the left sidebar. No title or gear should appear outside the sidebar. Keep target icon showing TOP TABS.
RIGHT bottom preview, caption '当前：顶部 tabs': keep its header, traffic lights, SIDE-TABS target icon, 'Trail' and gear. Completely REMOVE the sidebar content below the header: no '会话', no '目录 2', no left gray column or vertical separator. Instead render a slim horizontal tab row spanning the preview's width, with two realistic tabs named 'lighthouse' (active, white surface) and 'Local Shell' (inactive, pale gray). Below the horizontal tabs is an empty white main content surface, clipped by the preview frame. No terminal text. This must unmistakably show a TOP TAB STRIP, not a sidebar.
Both lower examples are simple cropped UI references on the same design sheet. Keep their existing positions and approximate sizes, title typography, quiet colors and thin dividers. Do not change or reinterpret either icon family, their labels, or the click-target semantics. No additional words, arrows or annotations. Output the corrected single design sheet.
```
