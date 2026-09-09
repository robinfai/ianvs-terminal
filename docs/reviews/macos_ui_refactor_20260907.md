# macOS UI 重构与验收（2026-09-07）

## 实现范围

- 标题栏与原生窗口按钮的 44pt 区域对齐；右侧提供搜索、设置和命令面板入口，具有语义标签、提示及悬停/焦点反馈。
- 原生窗口拖动区域避开右侧 120pt 工具栏；保留原生红黄绿按钮、窗口尺寸恢复，设置 640×400 最小内容尺寸和原生全屏行为。
- 文档标签及标签溢出按钮使用主题的 6pt 圆角；深色标题栏、标签轨道改为中性灰，提升非活动标签文字可读性。
- 系统字体沿用 `.AppleSystemUIFont`；桌面正文和主要操作文字为 13pt。公共间距为 4/6/8/12/16/20，Mac 设置控件高度为 28/28/32pt。
- 设置侧栏宽 180pt，整行选中，最小行高 36pt；支持上下方向键切换并同步键盘焦点，回车保持当前选项。侧栏与正文独立滚动，窗口不足时使用单列布局。
- 右键菜单在 macOS 使用 32pt 最小行高及主题化表面、边框和圆角；禁用原因可自然增加行高。
- 命令面板和共享对话框显式支持 Escape 关闭；命令面板关闭后恢复终端焦点。
- 数据服务选择项的状态文字在大字号下可换行，修复 1.5 倍字号窄窗口的横向溢出。
- 新增工具栏入口限于 macOS；没有变更终端协议或 PTY 核心。

## 自动验证

- 48 项相关 Flutter 回归通过：主题、主题切换、设置、终端工具栏、命令面板、Profile、数据服务设置。
- 8 项平台回归通过（含与上组重复的工具栏测试）：验证 macOS 入口与 iPhone 适配。
- 共享对话框 Escape 修改后，30 项对话框/命令面板/Profile 定向回归通过（与前组有重叠）。
- 公共 UI 组件 10 项回归通过。
- 原生 RunnerTests 26 项通过，包含窗口拖动命中区域、原生菜单与窗口行为。
- 静态分析无问题；最终 macOS Debug 构建成功。
- 小窗口测试覆盖 680×520、1.5 倍字号、浅色/深色，以及 390×844 的紧凑布局。

## Computer-use 实际验收

通过 CUA 对本机编译应用进行实际点击、粘贴、键盘操作、拖动和截图检查：

| 操作 | 观察结果 |
| --- | --- |
| 标题栏设置按钮 | 正常打开侧栏式设置，没有触发窗口拖动 |
| 设置侧栏点击、滚动 | 外观选项与主题设置均可访问，底部操作保持可见 |
| 常规 → 向下方向键 → 回车 | 正确停留在外观设置，不跳回常规 |
| 深色主题保存 | 终端、标题栏与标签轨道切换到深色 |
| 真实 shell 粘贴并执行 `echo MACOS-UI-ACCEPTANCE-OK` | 正确输出验收标记 |
| 工具栏搜索验收标记 | 显示 2/2 命中及终端高亮 |
| Escape 关闭搜索、⌘T 新建标签 | 搜索关闭，第二个标签与真实 shell 出现 |
| 标签右键 → 向右拆分 | 两个终端窗格和活动/非活动状态正常 |
| 拖动窗口边缘 | 从约 800×600 放大到 1130×760，再缩到 640×400；主界面与分屏无溢出 |
| 最终命令面板 Escape | 面板关闭；直接执行 `echo ESCAPE-FOCUS-OK` 成功，确认焦点回到终端 |
| 最终标签右键菜单 | 紧凑行高、禁用状态说明及浅色菜单表面正常 |

共享对话框的最后一项 Escape 加固由定向回归与最终构建验证；上述 CUA 截图保存在本次任务的工具记录中。

## 验收入口与环境

`example/tool/macos_ui_acceptance.dart` 使用生产 UI、真实 NativePtyBackend，以及内存中的 Profile、应用偏好和粘贴历史；布局不落盘，录制目录指向单独临时目录。它不启动 Data API，不读取其账户或主密钥。

在 `example` 目录可用 `flutter run -d macos -t tool/macos_ui_acceptance.dart` 复现。为与既有应用隔离，本次 Xcode 构建使用单独应用标识和输出目录，例如：

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -derivedDataPath build/macos-ui-acceptance \
  -destination 'platform=macOS' \
  FLUTTER_TARGET=tool/macos_ui_acceptance.dart \
  PRODUCT_BUNDLE_IDENTIFIER=dev.ianvs.terminal.uiacceptance \
  CODE_SIGNING_ALLOWED=NO build
```

正式 `lib/main.dart` 入口在当前开发环境停于数据服务启动：缺少同步的 iCloud Keychain 主密钥。此问题未通过改写密钥或数据配置规避，UI 验收采用上述隔离入口。退出既有开发实例曾被自动审批拒绝，因此保留了该实例；临时 403 审批服务错误恢复后，其他验收继续完成。
