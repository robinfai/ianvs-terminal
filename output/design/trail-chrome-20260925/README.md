# Trail 非 terminal 区域细节设计

生成方式：内置 imagegen，使用用户截图作为编辑目标。

范围：标题栏、工具栏、会话侧栏。图片是视觉提案，未修改应用代码。终端文字由生成模型重绘，不能作为逐像素保留的终端截图；后续实现只调整非 terminal 区域。

三张图按对话中实际显示顺序排列：

1. [方案 1](01-native-directory-tree.png)
2. [方案 2](02-quiet-grouped-navigator.png)
3. [方案 3](03-session-first-navigator.png)

[完整生成提示词](prompts.md)
