# T-332 Command Action Search Overlay Widget

## Goal

实现 `/` action search 的可见 overlay，让 action 和 saved command 可以在同一个搜索面板里展示、筛选和选择。

## Scope

- 新增 `CommandActionSearchOverlay` widget。
- 渲染 app action 和 saved command 的标题、类型和辅助信息。
- 支持查询输入、空状态、loading 状态和 unavailable reason。
- 支持方向键移动选择。
- `Enter` 对 app action 输出 action id。
- `Enter` 对 saved command 输出 command text。
- `Esc` 关闭 overlay 并消费按键。

## Non-goals

- 不实现 ShellScreen `/` 入口。
- 不把普通 `/` 文本解释成 action search。
- 不执行 saved command。
- 不定义真实 app action registry。
- 不更新 saved command useCount 或 lastUsedAt。

## Files In Scope

- `example/lib/features/command_center/command_action_search_overlay.dart`
- `example/test/command_center/command_action_search_overlay_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- overlay 打开时展示 action 和 saved command。
- 搜索输入会更新 controller query 和结果列表。
- 方向键移动选择且不漏给父级。
- `Enter` 能分别输出 open action 和 insert saved command。
- `Esc` 会关闭 overlay 且不漏给父级。
- 空、loading、unavailable 状态有可见文本或进度反馈。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test \
  test/command_center/command_action_search_controller_test.dart \
  test/command_center/command_action_search_overlay_test.dart \
  test/command_center/command_action_search_shell_wiring_test.dart
```

## Manual QA

本任务仍是 isolated widget，无真实 ShellScreen QA。后续 `/` ShellScreen 接线时必须手测：

- `/` 只通过显式入口打开，不由普通文本触发。
- `Esc` 关闭后 terminal 恢复输入。
- 选择 saved command 只插入，不自动执行。
- read-only 下 saved command insert 被后续安全策略阻止。
- 多行 saved command 走 paste confirmation 或 paste policy。

## Done When

- `/` UI 可以展示 action 和 saved command。
- overlay 的 keyboard ownership 有 widget test。
- saved command 选择仍只产生 insert intent，不直接执行。

## Risks / Follow-ups

- 尚未接入 ShellScreen 或 mode router。
- 真实 action registry 和 action dispatch 仍需后续任务。
- saved command 使用统计仍未更新。
