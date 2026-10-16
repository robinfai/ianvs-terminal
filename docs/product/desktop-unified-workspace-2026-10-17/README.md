# 桌面端 Block + AI 融合工作区

桌面端进入 Block 后，同一工作区、同一个输入框处理命令和 AI 提问，原生命令块与当前任务的回复、审批放在同一条内容流中。普通终端模式继续提供原始终端输入。

- 自动／命令／AI 是输入用途，切换不复制草稿、不提交请求。已有命令草稿进入工作区时迁移一次，历史命令重新输入也使用共享草稿。
- 普通模式往返、终端只读预览及重连保留任务和草稿。明确选择普通模式后不会立即重新打开融合工作区。原生终端仍挂载，后台状态与命令块继续更新。
- 桌面端没有 LLM 配置时仍可执行命令；AI 提问引导配置。移动端原有 LLM 门槛、可跳过首次配置和默认模式设置不变。
- 桌面输入框中的 Cmd+I（其他桌面平台 Ctrl+I）切换输入用途；焦点在输入框外时切换工作区／预览。会话快捷键保留，输入法 composing、模态窗口和只读预览继续限制输入。返回可交互工作区时恢复输入焦点。
- 打开工作区本身不调用模型。预览或普通模式接管后，旧发送回调立即失效；工具审批、取消后迟到数据隔离和未知提交不重试规则继续生效。
- 模式菜单统一标为 Block + AI，桌面状态栏显示共用输入／只读；工具栏采用紧凑图标，发送按钮靠右。

## 验证范围

- 相关回归 **871 / 871 通过**：AI、命令编辑器、会话关闭和草稿保护、快捷键、模式切换、连接生命周期、移动端首次配置及固定字号。融合流程覆盖 iOS、Android、macOS、Windows、Linux 的组件平台变体。
- 桌面布局 **4 / 4 通过**：深浅色 × 1200 × 800（文字比例 1.0）／640 × 400（文字比例 2.0）。覆盖命令、AI 回复、两行草稿、输入用途快捷键、预览返回与布局溢出检查。截图使用 DPR 2。
- **macOS 27.0.1 (26A434) 原生集成 1 / 1 通过**：真实 Native PTY 启动隔离的 zsh，执行 printf 命令；同一输入框通过本地回环 HTTP 收到 AI 回复；普通模式往返保留两行草稿和命令历史。
- 静态分析、变更 Dart 格式、diff 检查和 core 镜像检查通过；生产入口 macOS Release 构建通过。

原生集成使用内存配置、临时 shell 目录和确定性的本地模型响应，不连接真实 SSH／外部 LLM。Windows、Linux 本轮仅执行组件平台变体，没有原生运行；其他受支持 macOS 版本未在本轮复验。原生测试的前台激活警告未阻止测试，截图由原生 Flutter 渲染树采集，不代表手动系统窗口验收。

移动端 56 逻辑像素相关组件回归本轮通过；本轮没有新的手机安装、实机或 iOS 模拟器原生验收。此前 iOS 深浅色／横竖屏的 56.0 测量见[移动端融合验收](../mobile-unified-workspace-2026-10-16/README.md)。生产构建输出包含已有 Swift 通知实现警告，构建成功。PR 保持 Draft，不合并。

## 截图和日志

| 状态 | 截图 |
| --- | --- |
| 深色 1200 × 800 | [原图](screenshots/desktop-unified-dark-1200-scale-1.0.png) |
| 浅色 1200 × 800 | [原图](screenshots/desktop-unified-light-1200-scale-1.0.png) |
| 深色 640 × 400，文字比例 2.0 | [原图](screenshots/desktop-unified-dark-640-scale-2.0.png) |
| 浅色 640 × 400，文字比例 2.0 | [原图](screenshots/desktop-unified-light-640-scale-2.0.png) |
| macOS 原生命令与 AI 回复 | [原图](screenshots/native-unified-dark.png) |

[871 项回归](evidence/regressions.log) · [布局复核](evidence/visual.log) · [原生集成](evidence/native.log) · [静态分析](evidence/analyze.log) · [格式](evidence/format.log) · [Core 同步](evidence/core-sync.log) · [正式构建](evidence/production-build.log) · [源码哈希](source-sha256.json)

```sh
# 在 example/ 中运行
flutter test --no-pub test/ai test/terminal_composer test/shell/terminal_modes_test.dart test/shell/desktop_unified_chrome_test.dart test/shell/mobile_terminal_modes_test.dart test/shell/shell_close_protection_test.dart test/shell/desktop_session_status_test.dart test/shell/mobile_sessions_lifecycle_test.dart test/startup/app_startup_host_test.dart test/ui/phone_text_scale_policy_test.dart
flutter test --no-pub integration_test/desktop_unified_workspace_test.dart -d macos
flutter build macos --release --no-pub -t lib/main.dart
```
