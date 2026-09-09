# 交互复核差异标注

模式：内置 imagegen，compositing。输入依次为 `before/01-shortcut-toolbar.png`、`before/02-category-menu.png`、`after/shortcuts-light.png`、`after/category-menu-light.png`；输出为 `annotations.png`。

```text
Use case: compositing.
Asset type: Chinese configuration UI comparison and annotation board.
Create one clean landscape review board titled “配置交互复核 · 间距与下拉菜单”.
Input image 1 is the user's BEFORE shortcut settings screenshot, containing a red rectangle the user drew to identify the cramped filter area. Input image 2 is the user's BEFORE oversized category dropdown. Input image 3 is the implemented AFTER shortcut settings screenshot. Input image 4 is the implemented AFTER category dropdown screenshot.
The user screenshots are Retina 2x, while the new Flutter screenshots are 1x at an 800×600 logical window. Normalize displayed scale sensibly and preserve all original UI contents, labels, values, and proportions. The fourth image is authoritative for the new popup geometry. This is annotation of real implementation, not a redesign.
Use two rows: top row compare the filter toolbar before and after, bottom row compare the category popup before and after. Keep enough surrounding UI to show alignment. Label columns “调整前” and “调整后”. Use restrained blue numbered callouts in surrounding margins, with leader lines to exact controls. Avoid covering original UI text.
Include these exact callouts where supported by the screenshots: “1 搜索、分类与恢复按钮同排”; “2 筛选区与列表间距 16”; “3 菜单与输入框等宽”; “4 桌面菜单行高基准 32”; “5 统一字号、圆角、选中标记与阴影”.
Add small text footer: “窄屏与大字号采用两行筛选布局；菜单项随内容增高。尺寸为逻辑单位。图像标注用于复核，真实界面以原始截图为准。”
Do not invent controls, values, new features, navigation items, macOS traffic lights or extra app chrome. Do not remove or rewrite screenshot content to make it appear fixed. Preserve Chinese as closely as possible. White board background, crisp legible comparison, modest typography, no decorative mockup effects.
```
