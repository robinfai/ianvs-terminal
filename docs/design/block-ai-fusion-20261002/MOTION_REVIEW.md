# Block、阅读页与 Shell 动态效果复核

2026-10-03，macOS 27.0.1（26A434）。补齐上一轮辅助功能复核之外的菜单和页面入口。手机仍只使用固定字号生产组件，不测试 iPhone 真机。

## 已修复

- Block、阅读页、筛选、书签与导出菜单遵循系统减少动态效果；Shell 的 tab 菜单、命令菜单、会话选择、设置和相关弹窗同时遵循应用与系统设置。
- 从 Block 菜单打开阅读页原先使用另一个普通页面路由，绕过公开阅读入口的保护。现在两个入口使用相同路由，减少动态效果时没有滑入；macOS 的左缘横向拖选不会误触返回。
- 保留正常动画、Escape 的最内层关闭和菜单触发点焦点恢复。阅读位置、复制、原输出和输入归属不变。

新用例先复现内部阅读页仍在屏幕外滑入（macOS x=960、iOS x=390），见[修复前失败](evidence/motion-and-fixture/motion-block-reproduction.log)。修复后从实际 Block 菜单打开页面，检查首帧和下一帧的完整边界，并覆盖普通动画与 macOS 左缘鼠标拖动。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 应用 AI、Shell、会话、偏好、主题、模式与 SSH 回归 | [1,025 项通过](evidence/motion-and-fixture/motion-regression.log)，包含新增桌面／手机菜单用例及架构约束 |
| 共享终端 Block、手机预览、时间线、复制、阅读工具及动态效果 | [74 项通过](evidence/motion-and-fixture/motion-terminal-regression.log)，专项计数不与此重复累计 |
| 静态分析 | [应用](evidence/motion-and-fixture/motion-analyze.log)、[共享终端](evidence/motion-and-fixture/motion-terminal-analyze.log)、[新原生测试](evidence/motion-and-fixture/accessibility-fixture-analyze.log)均无问题 |
| 发布镜像 | [官方同步工具检查通过](evidence/motion-and-fixture/motion-mirror-check.log) |
| 独立原生窗口 | [1 项通过](evidence/motion-and-fixture/accessibility-fixture-native.log)，六阶段与进程标识见 [result.json](evidence/motion-and-fixture/native/result.json) |

原生窗口使用生产 TerminalAiWorkspace 和内存中的终端、模型及设置，不连接 PTY、网络或凭据存储。独立标题包含 PID。待审批、附件快照、观察、输出更新、暂停及断线均留有截图；六阶段终端写入始终为 0。输出变化时状态语义节点与朗读标签保持，暂停和断线才改变标签。已直接查看[提案](evidence/motion-and-fixture/native/proposal.png)和[附件快照](evidence/motion-and-fixture/native/snapshot.png)：目标、精确命令、来源、范围和退出码可见。

这仍是原生窗口与 Flutter 语义证据，**不是 VoiceOver 实际朗读记录**。测试默认快速结束；可用 `TRAIL_ACCESSIBILITY_DWELL` 在各阶段停留，单阶段最多 20 秒。测试本身不启停 VoiceOver、不读取全局朗读数据。

## 复现

在 `example/` 运行：

```sh
flutter test --no-pub test/ai test/shell test/sessions test/preferences test/terminal_composer/terminal_mode_test.dart test/ui test/app test/ssh --reporter expanded
flutter test --no-pub integration_test/terminal_ai_accessibility_acceptance_test.dart -d macos --dart-define=TRAIL_ACCESSIBILITY_EVIDENCE=/absolute/evidence/path --reporter expanded
```

在仓库根运行：

```sh
flutter test --no-pub packages/ianvs_terminal/test/terminal/command_blocks_test.dart packages/ianvs_terminal/test/terminal/command_blocks_mobile_test.dart packages/ianvs_terminal/test/terminal/command_blocks_timeline_test.dart packages/ianvs_terminal/test/terminal/command_block_copy_test.dart packages/ianvs_terminal/test/terminal/command_block_reader_tools_test.dart packages/ianvs_terminal/test/terminal/command_blocks_motion_test.dart --reporter expanded
dart run tools/sync_terminal_core.dart --check
```

[本轮清单](evidence/motion-and-fixture/manifest.json)保存 23 个证据文件和 17 个源码哈希。完整场景状态见 [当前验收索引](CURRENT_ACCEPTANCE.md)。

## 原生窗口归属核验

继续检查发现，不能只凭测试自己写出的 PID／标题认定已获得操作系统确认。多个 Trail Development 同时运行时，AppleScript 将进程对象保存到变量会得到按名称解析的引用，后续窗口查询可能落到另一个同名进程；第一次[严格标题检查失败](evidence/motion-and-fixture/native-window-before.json)，没有因此执行朗读读取。

新增只读工具 `example/tool/verify_accessibility_fixture.py`：先核对新鲜的测试信息及实际可执行文件，原生查询每次保留 PID 筛选，再核对返回 PID、唯一标题和前台状态。PID 改变、进程结束、原生查询失败或超时均停止。它不启停 VoiceOver、不读取朗读、不激活窗口，也不把单次成功当作后续读取的授权。

同名进程并存时，已[验证实际 PID、标题与前台状态](evidence/motion-and-fixture/native-window-ownership.json)；[原生流程再次通过](evidence/motion-and-fixture/native-window-run.log)，六阶段仍无终端写入，见 [result](evidence/motion-and-fixture/native-window-result.json)。测试退出后再次检查[按预期拒绝](evidence/motion-and-fixture/native-window-after-exit.log)，没有继续读取原生窗口。首次失败并非产品标题设置失败，而是验收工具丢失进程筛选条件；不修改产品窗口行为。

运行测试时可在另一终端检查其新鲜 scope 文件：

```sh
python3 example/tool/verify_accessibility_fixture.py /absolute/evidence/path/scope.json --timeout 30
```

后续用户已授权限定窗口检查，实际启动、原生测试、字幕读取限制及清理结果见 [VoiceOver 验收尝试](VOICEOVER_ATTEMPT.md)，随后明确要求跳过 VoiceOver，实际朗读记为未验收。如未来重新验收，每次观察前仍须核对窗口归属，不能使用已结束测试的 PID 或旧检查结果。
