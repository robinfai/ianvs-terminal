# Imagegen prompts

Mode: built-in `image_gen`; no CLI/API fallback. Annotation boards are explanatory graphics; unmodified Flutter captures are acceptance evidence.

## 01 Initial issues (accepted after correction)

Use case: precise-object-edit
Asset type: Chinese UI audit annotation.
Input image: original screenshot is edit target.
Primary request: Preserve original screenshot and add only numbered small red markers over evidence, with explanations in an added white footer. Do not redraw, rearrange or fix original UI. Top-left source pixel is (0,0), source width1114 height596.
Place marker 01 at (540,320) INSIDE MENU, the blank area right of menu text (menu spans x62..637). Place marker 02 at (320,154) beside 筛选. Place marker 03 at (620,218) at the selected row right edge. Place marker 04 at (390,248), the separator immediately below 智能大小写, NOT the separator below 忽略大小写. Place marker 05 at (600,112), menu top border adjacent to toolbar bottom.
Footer title: "第一轮 · 问题标注（校正版）"
Footer text exactly:
"01 菜单过宽，右侧留白过多"
"02 标题和普通选项字重偏重"
"03 选中背景贴边，缺少内侧留白"
"04 智能大小写被单独分隔，分组过碎"
"05 弹层与工具栏过近，阴影和边框偏重"
Constraints: only five small numbered markers and short leader lines, no large red rectangles; preserve original screenshot proportions and all five rows. The annotations describe evidence and are not acceptance screenshots.

Correction pass: Move only marker 04 upward to the blue selected row lower boundary between 智能大小写 and 区分大小写. Preserve all other labels and UI.

## 02 Second-round findings

Use case: precise-object-edit
Asset type: second-round Chinese UI QA annotated evidence.
Input images: Image1 is actual Flutter screenshot of a narrow window at 2x text with search field clipped; Image2 is actual Flutter screenshot with regex error.
Create one audit board preserving the screenshot evidence. Put image1 and image2 beside each other, then add brief readable annotation labels below each. Do NOT fix, redraw, or beautify the UI. Point one red arrow in image1 to the cropped 搜索 placeholder at top of search bar; point another in image2 to the truncated red "正则表…" status and English "Invalid regular expression".
Title "第二轮 · 复查发现"
Exact callout texts:
"06 两倍字号：搜索输入框固定高度，文字被裁切"
"07 错误提示：状态截断，中文界面混入英文"
Footer "菜单尺寸、内边距、分组和弹层间距已改善；以上问题继续整改"
Constraints: preserve actual visible defects, full screenshots, no fake passing checkmarks, no additional UI elements.

## 03 Final acceptance

Use case: precise-object-edit
Asset type: final Chinese UI acceptance annotation board for a real Flutter implementation.
Input images: all five inputs are accepted actual Flutter screenshots, NOT mockups. Image1 light search filter menu; Image2 dark search filter menu; Image3 narrow window at 2x text showing complete 搜索; Image4 localized regex error; Image5 narrow 2x text with no matches.
Primary request: Make a clean, readable final review board. Preserve the real screenshot contents and geometry; crop away unused empty terminal canvas if needed but never change any UI. Main large light filter screenshot on left, compact evidence panels on right for dark menu, 2x input, regex error and empty result. Add green numbered acceptance annotations OUTSIDE the screenshots with thin leader lines to verified UI.
Title exact: "最终验收 · 本次检查项已通过"
Main labels exact:
"01 菜单收紧，文字完整"
"02 普通项与选中项层级清晰"
"03 选中背景四周留白"
"04 普通搜索与正则两组"
"05 浮层有间距，边框与阴影统一"
Supporting labels exact:
"深色模式：通过"
"06 两倍字号：输入文字完整"
"07 错误提示：中文完整，无截断"
"空结果：提示完整，不挤压输入"
Footer exact: "26 项搜索与界面测试通过 · 静态分析通过"
Small scope note exact: "验收范围：macOS 27 的 Flutter 组件渲染；浅色、深色、中英文、窄窗与两倍字号。标注图仅为说明，原始截图另存。"
Constraints: Only annotate and arrange actual screenshot evidence. No redesigned UI, no invented text inside screenshots, no global claim that the entire app is bug-free. Clear Simplified Chinese.
