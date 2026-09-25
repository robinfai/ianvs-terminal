# Apple HIG annotation prompt

Mode: built-in imagegen. Raw screenshots are in apple-system-fonts/.

Final correction: change the selected-row height badge from 05 to 03; remove the misleading spacing ruler and point to the inset; label the generated panels as 截图标注示意 rather than 实际截图.

Use case: precise-object-edit
Asset type: annotated macOS typography and spacing acceptance sheet.
Inputs: Image1 actual Flutter screenshot with installed SF/PingFang fonts in Chinese light mode; Image2 English screenshot; Image3 dark screenshot. All are edit targets/evidence.
Primary request: Preserve these actual UI screenshots, and add a precise Chinese annotation board explaining verified Apple HIG-aligned font metrics and project spacing. Main screenshot left, English and dark menu crops right. Use small numbered green markers and readable labels in margins; do not alter UI text, geometry or fonts in screenshots.
Title: "Apple HIG · 字体与间距验收"
Exact labels:
"01 正文与菜单：13 pt Regular / 16 pt 行高"
"02 次级标题：11 pt / 14 pt 行高"
"03 点击区域：至少 28 × 28 pt"
"04 菜单宽度跟随中英文内容"
"05 项目间距参数：4 pt / 8 pt"
Footer text:
"字体与控件目标参考 Apple HIG；4/8 pt 间距为本项目布局参数。"
"SF 与苹方实际渲染 · 浅深色与中英文复查通过"
"截图为 2× 导出，图像像素不等于界面 pt。"
Constraints: do not claim Apple mandates all spacing values. Do not turn screenshot text into bold headings. No invented controls or modified screenshot content. Annotations are explanatory and raw screenshots are saved separately.
