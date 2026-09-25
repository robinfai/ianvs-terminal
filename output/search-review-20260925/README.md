# 搜索栏细节整改与验收

最新追加验收：[Apple HIG 字体与布局对齐](apple-hig.md)。用户要求按 Apple 规范校正后，菜单改为按文案宽度、13/16 正文、11/14 次级标题及 28 pt 控件目标；最新截图位于 `apple-system-fonts/`。以下保留前两轮历史记录。

结论：两轮整改后，本次检查的搜索栏、筛选/范围菜单及相关状态没有未解决问题。

## 迭代记录

1. 原图审查：发现菜单过宽、文字层级偏重、选中背景贴边、分组过碎、浮层间距和阴影过重。均已整改。
2. 实际 Flutter 渲染复查：发现两倍字号裁字、错误状态截断及中英混杂。已整改；同时完善菜单打开/选中语义、禁用导航外观及大字号空结果提示。
3. 最终验收：中英文菜单、浅深色、360 像素窄窗与两倍字号、正则错误、空结果、键盘选择及搜索回归通过。

| 编号 | 整改结果 | 验收证据 |
| --- | --- | --- |
| 01 | 菜单最小行宽从 288 缩至 196，长英文按内容撑开 | final/light-zh-filter.png、final/light-en-filter.png |
| 02 | 标题使用次级色和小字，普通项 400、选中项 500 字重 | final/light-zh-filter.png |
| 03 | 菜单四周 4 像素内边距，选中背景不再贴边 | final/light-zh-filter.png、final/regex-selected.png |
| 04 | 普通搜索与正则两组，仅保留组间分隔线 | final/light-zh-filter.png |
| 05 | 两个菜单统一偏移、边框和阴影；展开按钮有状态提示 | final/light-zh-scope.png、final/dark-zh-filter.png |
| 06 | 输入高度及范围控件随字号调整；大字号结果单独显示 | final/narrow-scaled-input.png、final/narrow-scaled-no-matches.png |
| 07 | 正则错误使用完整本地化文案与状态图标 | final/regex-error.png |

## 图像

- [用户原图](00-original.png)
- [第一轮问题标注（最终校正）](01-issues-final.png)
- [第二轮复查标注](02-review-issues.png)
- [最终验收标注](03-acceptance.png)
- [最终实际浅色截图](final/light-zh-filter.png)
- [最终实际深色截图](final/dark-zh-filter.png)
- [最终实际窄窗截图](final/narrow-scaled-filter.png)
- [Imagegen 提示词](prompts.md)

标注使用内置 imagegen 生成；生成图可能重新采样文字及线条，仅用作评审说明。`final/` 中的图片是未经图像生成编辑的 Flutter 实际组件渲染，作为验收依据。`round-1/` 和 `round-2/` 保留过程证据。

## 验证与边界

- 20 项已有搜索回归测试通过，覆盖查询、导航、跨窗格/标签搜索、快捷键、焦点、高亮和正则。
- 6 项新增检查通过，覆盖中英文、浅深色、窄窗两倍字号、文本可见范围、键盘菜单、错误/空状态及选中语义。
- 定向 `flutter analyze --no-pub` 通过；`git diff --check` 通过。
- 实测宿主：macOS 27.0（26A428）。截图运行真实 ShellScreen，使用 FakePtyBackend 和固定测试字体；不是已发布原生应用的系统截图。
- 原图没有说明其字号和设备缩放，不做跨环境逐像素相等声明。未在其他 macOS 版本、iOS 真机或 VoiceOver 中实测；本次不声明整个应用无缺陷或全面无障碍合规。
- 搜索栏属于包含原生终端依赖的私有 ShellScreen 组件，采用实际组件渲染场景作为预览，避免将 FFI 依赖接入基于 Web 的 Widget Previewer。
- Flutter 提示共享设计包与应用的 `uses-material-design` 值不同；应用已有自带图标字体，本次未更改该配置，图标已通过截图检查。

复现命令（在 `example/` 下）：

```sh
SEARCH_REVIEW_CAPTURE_DIR="$PWD/../output/search-review-20260925/final" flutter test --no-pub test/design/terminal_search_visual_capture_test.dart
flutter test --no-pub test/widget_test.dart --plain-name search
flutter analyze --no-pub lib/features/shell/shell_screen.dart lib/features/shell/shell_screen_search.dart test/design/terminal_search_visual_capture_test.dart
```

本次改动包含搜索组件、对应测试和本目录验收记录。原有 `tools/app_review_ssh/` 未改动。
