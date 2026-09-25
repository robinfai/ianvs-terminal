# Apple HIG 字体与布局对齐（追加验收）

本轮根据用户要求，使用 macos-design-guidelines 工作流并核对 Apple 官方文档，替代上一轮凭视觉判断的局部尺寸。新结果见 `apple-system-fonts/`；旧截图保留为过程记录。

## 官方依据与实际采用值

| 项目 | 采用值 | 依据和性质 |
| --- | --- | --- |
| 正文、菜单项、范围控件 | 系统字体，13 pt Regular，16 pt 行高 | Apple HIG macOS Body |
| 菜单次级标题 | 11 pt Regular，14 pt 行高 | Apple HIG macOS Subheadline；较弱颜色表达层级 |
| 结果提示 | 12 pt Regular，15 pt 行高 | Apple HIG macOS Callout |
| 清除、导航、关闭 | 至少 28×28 pt 点击区域 | HIG macOS 默认控件尺寸；原清除 18×18、导航宽 26 均已调整 |
| 菜单行 | 默认最小高 28 pt，字号放大后自然增高 | 按默认点击目标设计；并非宣称原生 NSMenu 行高固定为 28 |
| 搜索栏 | 默认高 36 pt：28 pt 控件 + 上下各 4 pt | 项目复合控件参数 |
| 搜索栏 padding | 水平 8 pt，垂直 4 pt | 项目参数，统一对齐和视觉分组 |
| 同组 / 分组间距 | 紧密关联 4 pt，主要间隔 8 pt | 项目参数；不是 Apple 对所有控件的硬性数值 |
| 菜单 padding | 外圈 4 pt；行水平 8 pt、垂直 6 pt | 项目参数，13/16 正文与 28 pt 行高配合 |
| 菜单与触发器 | 向下偏移 8 pt，搜索栏下缘外可见间隔 4 pt | 项目参数；避免浮层边框相贴 |
| 菜单宽度 | 跟随最长本地化文案 | 删除 196 pt 固定最小宽度；中英文分别适配 |

Apple 的布局规范要求清晰分组、对齐、足够的操作空间及自适应，并未为每一种自绘菜单给出统一 padding/margin。本轮将字体和控件尺寸的官方数值，与 Flutter 复合控件的布局选择明确分开；没有把窗口级 margin 直接套进下拉菜单。

官方链接（2026-09-25 查阅）：

- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)：macOS 字体、13/16 Body、11/14 Subheadline、12/15 Callout。
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)：macOS 默认目标 28×28 pt、最小目标 20×20 pt，以及操作间距要求。
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)：对齐、分组、布局边距与上下文适配。
- [NSFont.menuFont(ofSize:)](https://developer.apple.com/documentation/appkit/nsfont/menufont(ofsize:))：传 0 使用系统默认菜单字体。

## AppKit 本机读取

macOS 27.0 上直接调用 AppKit，得到 system/menu 默认字体均为 `.AppleSystemUIFont` 13 pt，small system font 为 11 pt。regular NSSearchField 的固有高度为 24 pt；这属于原生控件自身度量，本项目复合搜索栏采用 HIG 的 28 pt 默认点击目标，并不是逐像素复制 NSSearchField。

系统字体只从本机读取，未复制或打包分发 SF/苹方字体。使用真实应用主题 `.AppleSystemUIFont` 与 `PingFang SC`，并载入应用自己的 TrailLightIcons，避免上一轮 Roboto/Noto 测试替代字体及默认 Material 图标影响目视判断。

## 验收

- 搜索相关 26 项测试全部通过，包含已有查询、快捷键、范围、导航与高亮回归。
- 同一组 6 项视觉/交互检查使用本机 Apple 字体再次全部通过。
- 定向静态分析通过，`git diff --check` 通过。
- 浅色、深色、中英文、360 pt 窄窗、两倍文字、正则错误和空结果已重新渲染检查。
- 窄窗下结果文字放到输入栏下方，保留可编辑空间和完整状态文案。
- 图片按 2× 像素倍率导出：13 pt 字号对应约 26 个图像像素，不表示界面字号为 26 pt。两倍文字压力测试与图片的 2× 导出倍率是不同概念。
- 验收范围仍是 macOS 27 的 Flutter 组件渲染，不声明原生 AppKit 控件等价或其他 OS 已实测。macOS HIG 不支持将 iOS Dynamic Type 的行为直接等同于 macOS；这里的两倍字号是 Flutter 文本缩放压力检查。

## 实际截图

[Imagegen 验收标注图](04-apple-hig-acceptance.png) · [内置 imagegen 提示词](apple-hig-prompt.md)。标注图为说明性生成图，以下原始渲染图保留实际文字与尺寸。

- [中文浅色菜单](apple-system-fonts/light-zh-filter.png)
- [英文浅色菜单](apple-system-fonts/light-en-filter.png)
- [中文深色菜单](apple-system-fonts/dark-zh-filter.png)
- [窄窗两倍字号](apple-system-fonts/narrow-scaled-filter.png)
- [错误提示](apple-system-fonts/regex-error.png)
- [空结果](apple-system-fonts/narrow-scaled-no-matches.png)

系统字体复现时，在普通截图命令前设置 `SEARCH_REVIEW_SYSTEM_FONT` 为本机 SFNS.ttf 路径，`SEARCH_REVIEW_CJK_FONT` 为本机 PingFang.ttc 路径；字体资产位置可能随 OS 变化。未设置时测试继续使用仓库的固定字体，以便常规运行复现。
