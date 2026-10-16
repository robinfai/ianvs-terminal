# 移动端 Block + AI 融合工作区

用户确认 Block 与 AI 是同一个模式。现在移动端只有普通终端和 Block + AI 两种工作模式；进入 Block + AI 后，用同一个输入框执行命令或提问，同一条内容流显示原生命令块与当前任务的 AI 内容。

- 配置有效 LLM 且 Shell 支持时，新会话默认融合模式。默认普通模式、无 LLM 限制、可跳过首次配置的规则继续生效，桌面模式不变。
- 输入菜单的自动／命令／AI 是本次输入的用途。输入方式切换不换页、不复制草稿、不发送；人工命令等待结果时，下一条命令草稿仍保持命令用途，执行锁继续阻止重复提交。
- 顶部“终端预览”只读查看原终端；会话菜单选普通模式或显式接管才恢复原始终端输入。观察状态中的旧发送回调立即失效。iPad 并排时，任务侧仍可编辑，终端侧保持只读。
- 重新输入历史命令直接编辑融合输入框。普通模式往返、配置移除／恢复、SSH 重连均保留对应草稿；重连延续主动选择的模式，不把能力退化误认为用户改了默认值。
- 原生历史与当前任务内容按稳定位置组合；回执关联到原生命令块后去重。跨重连的相同 block ID 按来源隔离。进入融合界面本身不发起推理，也不在后台未打开的会话中提前创建任务。
- AI 审批、后台取消、迟到数据隔离和未知提交不自动重试沿用现有执行控制。

## 验证

- 最终相关回归：814 通过。包含 iOS / Android 真实 ShellScreen 组件中的“命令 → AI 提问 → 普通模式 → 融合模式”流程、回环 HTTP 模型响应、原始终端输入保护、重连、后台生命周期、引导和固定字号。
- iOS 原生模拟器：iPhone 17 Pro，iOS 26.3.1 (23D8133)，DPR 3；竖屏 402 × 874、横屏 874 × 402 逻辑像素。使用本任务专用设备，未修改真机。
- 原生融合工作区流程覆盖深浅色 × 横竖屏四种状态，均验证空输入、命令输入、多行草稿、模式菜单打开及键盘收起、终端预览返回、普通模式往返。收起输入栏均为 **56.0** 逻辑像素。该定向运行只选择这一流程；同一测试文件的三个无关流程被过滤，并非执行失败。
- 静态分析、全部变更 Dart 格式、diff 检查和 core 镜像检查通过；生产入口 iOS simulator debug 构建通过。
- 原生旋转期间出现系统方向请求的短暂 warning；每个场景都有实际横竖屏尺寸断言和截图，实际方向转换通过。

本轮原生测试采用内存配置和模拟终端数据，不连接真实 SSH 或真实 LLM；回环 HTTP 请求仅用于自动回归。本轮未安装到手机或进行新的真机验收，PR 保持 Draft，不合并。

## 截图与日志

| 状态 | 原生截图 | 收起高度 |
| --- | --- | --- |
| 浅色竖屏 | [原图](screenshots/unified-collapsed-light-portrait.png) | 56.0 |
| 深色竖屏 | [原图](screenshots/unified-collapsed-dark-portrait.png) | 56.0 |
| 浅色横屏 | [原图](screenshots/unified-collapsed-light-landscape.png) | 56.0 |
| 深色横屏 | [原图](screenshots/unified-collapsed-dark-landscape.png) | 56.0 |

[测量数据](evidence/native-metrics.json) · [原生运行记录](evidence/native-test.log) · [相关回归](evidence/regressions.log) · [静态分析](evidence/analyze.log) · [构建](evidence/production-build.log) · [来源文件哈希](source-sha256.json)

```sh
# 在 example/ 运行；模拟器 ID 使用本任务的专用设备。
flutter test --no-pub test/ai test/terminal_composer test/shell/mobile_terminal_modes_test.dart test/startup/app_startup_host_test.dart test/shell/mobile_sessions_lifecycle_test.dart test/ui/phone_text_scale_policy_test.dart
TRAIL_REVIEW_SCREENSHOTS=../build/mobile-unified-native flutter drive --no-pub --driver=test_driver/ios_design_review.dart --target=integration_test/ios_unified_workspace_test.dart -d C5C8CE03-EBEE-4F71-A327-5F208D20B49C
```
