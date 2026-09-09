# macOS HIG 复核

核对日期：2026-09-09。以 Apple 当前官方 HIG 为依据；项目内 macos-design-guidelines 技能作为实现检查清单。第一版 imagegen 目标稿的数值已据此修订。

## 字体

Apple 当前 [Typography](https://developer.apple.com/design/human-interface-guidelines/typography?changes=_5) 给出的 macOS 正文默认为 13 pt。配置主题使用系统 UI 字体，不再统一放大为 14 pt；本文数值落到 Flutter 的逻辑像素，不是 Retina 物理像素。

| 用途 | 项目 token |
| --- | --- |
| 对话框与页面标题 | 17 / 22 行高，Semibold |
| 分组标题 | 13 / 16，Semibold |
| 表单标签、输入、按钮、侧栏 | 13 / 16 |
| 说明文字 | 12 / 15 |

17/22、13/16、12/15 分别参考 macOS Title 2、Body 和 Callout；使用字重区分同字号的层级，取消桌面正文额外字距。没有把 iOS 的 17 pt 正文套到 Mac 上。

## 控件与布局

Apple [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) 推荐 macOS 常规控件 28×28 pt、最低 20×20 pt。项目采用 28 pt 常规基准、24 pt 紧凑图标操作；这不是“所有控件必须固定 28 高”的要求，文字、图标和错误信息仍可撑开控件。

内容边距收为 20，相关控件以 8 间隔为基准，表单标签列 120、列间隔 12，数值字段限制为短输入。20/8/120/12 是本项目对齐选择，**不是 Apple 当前 HIG 的统一强制尺寸表**。官方 [Layout](https://developer.apple.com/design/human-interface-guidelines/layout?changes=_____7&language=objc) 强调相关项成组、主要内容优先、适应窗口和语言变化；[Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields?changes=_7) 建议字段宽度与预期输入量相符、整齐排列并保持合理 Tab 顺序。

设置与 Profile 的最大尺寸调整为 940×700，侧栏 190；SSH 最大 720×700。具体窗口尺寸是根据内容密度选择，不是 HIG 固定值。全局设置去掉重复的 Trail 副标题，Profile 和 SSH 保留用于辨认当前对象的名称。

触控平台仍采用 48 pt 控件基准。窄窗口或大字体改为上下排列，底部操作区允许换行；继续验证键盘、滚动、错误定位和未保存退出提醒。

## 范围与证据

本次调整是 Flutter 配置表单的布局与主题，没有将控件替换为 AppKit 原生控件。系统字体沿用应用主题；颜色继续继承项目语义色。`final/` 是实截图，`iteration-3/` 保留 HIG 复核前的版本，`annotations/` 保存 imagegen 差异图。

截图 harness 采用本机系统 SF 字体及中文后备字体，不把测试字体误当作产品字体设计。完整界面依然通过 widget 测试渲染；独立字段 preview 见 `example/lib/ui/previews/configuration_fields_preview.dart`。
