# T-018 Shell 退出事件 Tab 自动关闭

## Goal

定义并落地最小安全的 shell `exit` 事件 tab 处理行为，避免 UI 保留无法继续交互的已退出 tab。

## Scope

- `example/lib/features/sessions/session_controller.dart`
  - 将 shell `exit` 事件收敛到既有 tab 关闭路径。
- `example/test/sessions/session_controller_test.dart`
  - 为 shell 退出后的 tab 关闭与焦点迁移补最小回归测试。
- `docs/tasks/T-018-terminal-exit-tab-handling.md`
  - 记录本次任务边界、验收、验证与风险。

## Non-goals

- 不新增“退出确认”、“保留已退出 tab”、“退出提示 banner / toast”等新交互。
- 不改动 SSH、split pane、跨平台 PTY 或 renderer 行为。
- 不重做 session 生命周期架构；优先复用现有 `closeSession` 语义。
- 不扩展到复杂 shell crash 分类、异常恢复或退出历史展示。

## Files In Scope

- `example/lib/features/sessions/session_controller.dart`
- `example/test/sessions/session_controller_test.dart`
- `docs/tasks/T-018-terminal-exit-tab-handling.md`

## Functional Acceptance

- 当某个 session 收到 shell `exit` 事件时，对应 tab 会自动关闭，不再停留在 tabs 列表中。
- 若退出的是非激活 tab，当前 `activeSessionId` 保持不变。
- 若退出的是当前激活 tab，焦点沿用现有关闭行为切换到剩余 tabs 的 `last` 会话。
- 若退出的是最后一个 tab，界面回到空状态（`activeSessionId == null`），而不是保留一个已退出的死 tab。
- 以上行为具备对应 controller 级回归测试。

## Verification Commands

参考 [../TESTING.md](../TESTING.md)：

```bash
cd example
flutter analyze
flutter test test/sessions/session_controller_test.dart
```

## Manual QA

1. 启动应用并打开两个 shell tab（A / B）。
2. 保持 B 为当前激活 tab，在 A 内执行 `exit`。
3. 验证 A 自动消失，焦点仍留在 B。
4. 再打开一个新 tab，并在当前激活 tab 内执行 `exit`。
5. 验证当前 tab 自动关闭，焦点切到剩余 tab。
6. 仅保留最后一个 tab 时执行 `exit`，验证界面回到空状态。

## Done When

- shell `exit` 事件不再留下可见但不可用的已退出 tab。
- 退出后的焦点迁移与手动关闭规则保持一致。
- `flutter analyze` 与目标测试命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 立即自动关闭会放弃“查看最后一屏输出”的机会；若后续需要保留退出内容，应拆独立任务设计明确的已退出态 UI。
- 当前只定义本地 shell tab 的最小策略，不覆盖异常崩溃分类或更复杂的 session 终止来源。
