# 顶部左右分区与命令面板入口

生成方式：内置 imagegen。

视觉要求：顶部沿侧栏边界拆为左右两区；右上仅保留齿轮作为命令面板入口，历史、搜索、设置与更多功能收进命令面板；active 目录的文件夹图标和路径文字使用强调色，非 active 目录采用默认文字色。

[效果图](04-split-command-entry.png)

这是界面效果图，命令面板以关闭状态展示，未修改应用代码。terminal 区域只作背景参考，生成图不构成逐像素保真的原始截图。

## 完整提示词

```text
Use case: precise-object-edit.
Asset type: a high-fidelity edited screenshot of Trail, a native macOS terminal application.
Input images: Image 1 is the ORIGINAL screenshot and the base edit target. Image 2 is the previous native-directory-tree design and is ONLY a design reference for the sidebar's hierarchy, folder glyphs, row spacing and selected-session treatment.
Primary request: produce ONE refined design incorporating the user's exact feedback: split the top chrome into left and right sections; reduce the top-right action icons to a SINGLE settings gear that opens a command palette; only the active directory's folder icon and path are accent-colored, with all inactive directory icons and path text in the default text color.

Target dimensions and composition: match Image 1's 1728 x 2168 portrait window and aspect ratio; edge-to-edge app screenshot, no outer background, no perspective, no presentation board, no annotations, no additional variants. The sidebar is 560 pixels wide. The title bar is 88 pixels tall. All positions below refer to the original resolution.
Top split layout:
- The vertical divider at x=560 now runs from the VERY TOP of the window through the bottom, clearly separating two independently composed header regions.
- LEFT header x=0..559 uses the SAME pale gray surface as the sidebar below, giving a visually continuous full-height sidebar. Native red/yellow/green window controls at far left; move the sidebar-toggle line icon to the right end of this LEFT header, centered approximately x=522. No centered app title inside this left section.
- RIGHT header x=560..1728 is white, matching the main content surface. Put 'Trail' LEFT-ALIGNED at x=590, vertically centered in the header. At the far right show EXACTLY ONE elegant gray settings gear at x=1688. Gear is the command palette launcher, with all History, Search, Settings and More functionality consolidated into the closed command palette. Remove history, search and ellipsis icons completely. Do not replace them with any other toolbar buttons.
- Every traffic light, sidebar toggle, the 'Trail' title and the settings gear must share the SAME geometric horizontal centerline y=44. Use consistent icon optical size, stroke and targets. No extra toolbar strip. Use a subtle single-pixel divider, flat surfaces, no always-visible button boxes.
- Do not show the command palette open, do not add an explanatory label or tooltip. The requested image is the normal closed state showing the reduced chrome.

Sidebar body: use the directory tree from Image 2 as the structural reference. Retain heading '会话' with plus action and small section label '目录  2'. Preserve TWO directories with their existing sessions:
  Active parent: '/Users/robinfai'. Its outline FOLDER ICON and PATH TEXT must be bright native accent blue #007AFF. Its disclosure chevron can be default neutral.
  Selected nested child: 'lighthouse@VM-4-2-ubuntu: ~' with a small terminal glyph, existing pale blue rounded selection fill #D9ECFF and dark blue readable text.
  Inactive parent: 'Documents/AI/records'. BOTH its folder icon AND path text MUST be default dark neutral #1D1D1F, NEVER blue, no pastel/tinted icon. This color rule is essential: only the active folder/path is highlighted.
  Unselected nested child: 'Local Shell', default dark neutral text and a neutral terminal icon.
Keep alignment and indentation consistent, 12-point outer margins, 6-8-point row corners, and compact macOS typography. Do not invent status badges or claim SSH is connected. Keep the rest of the sidebar empty.

Style grounding: existing Trail tokens: sidebar #F5F5F7, main surface white, primary text #1D1D1F, secondary #55565A, separators #D1D1D6, active accent #007AFF, selection #D9ECFF. SF Pro/PingFang-like UI typography, body 13-14 logical points at 2x display density. Spacing 4/6/8/12/16/20 points. Prioritize grouping, alignment, typography and whitespace; restrained native macOS utility interface. No decorative gradients, heavy shadows or card layouts.

CRITICAL INVARIANTS: only redesign the top header and left sidebar. Preserve Image 1's terminal content rectangle x=560..1728, y=88..2168: same white background, shell text, font, rainbow prompt segments, line positions, original clipping, times 17:19, 19:41 and 19:59, caret and whitespace. Do not redesign or alter the terminal. Keep the same window geometry and rounded outer corners. No added bottom toolbar, tabs, navigation, captions, watermark or features. Render only one clean polished screenshot.
```
