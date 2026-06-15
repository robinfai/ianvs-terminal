# T-352 Command Action Search Bell Notifications Dispatch

## Goal

让 action search 能执行高频非写入入口 `bell notifications`，从 action search 直接切换终端响铃通知偏好，同时保持动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `bell notifications` 时复用现有通知偏好切换行为。
- 为 `toggleBellNotify` 增加 action search 别名，匹配命令菜单里的用户可见文案。
- 增加 widget regression，确认执行后出现保存反馈。
- 确认 action search 执行该动作不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变系统通知权限、bell 检测或通知发送逻辑。
- 不改变 command-finished notifications 或 activity monitor 行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_command_action_search_adapter.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `bell notifications` 后按 `Enter` 会切换 bell notification 偏好。
- 执行后显示与命令菜单一致的保存反馈。
- 执行动作不向 shell 写入。
- 命令菜单里的 bell notification toggle 行为仍沿用既有标签和反馈。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can toggle bell notifications without shell write"
flutter test test/widget_test.dart --plain-name "command menu notification toggles update labels and feedback"
flutter test test/shell/shell_command_action_search_adapter_test.dart
```

## Manual QA

- 打开 action search，搜索 `bell notifications`，按 `Enter`。
- 确认 snackbar 显示 bell notifications 已启用或禁用并保存。
- 再次打开命令菜单，确认对应 label 反映新的开关状态。
- 确认执行该动作不写 shell，也不会把 overlay 文案送进终端。

## Done When

- Bell notification toggle 可以从 action search 执行。
- action search 对 bell notification toggle 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- command menu 动态 label 会在 enable/disable 间切换；action search 需要保留稳定别名，避免用户只能通过内部 action id 搜索。
- 后续可用同一模式接入 activity monitor。
