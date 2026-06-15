# T-348 Command Action Search Copy Selection Dispatch

## Goal

让 action search 能执行高频非写入入口 `Copy selection`，从 action search 直接复制当前 terminal 选区，同时保持动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `Copy selection` 时复用现有 selection copy 逻辑。
- 为 `copy` action 增加 action search 别名 `copy selection`，匹配命令菜单里的用户可见文案。
- 增加 widget regression，确认复制选区只写剪贴板、不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 terminal 选区生成规则。
- 不改变 clipboard bridge 或 paste history 记录逻辑。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_command_action_search_adapter.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `copy selection` 后按 `Enter` 会复制当前 terminal selection。
- 复制结果来自 terminal 内容，不包含 overlay 或命令菜单文本。
- 执行 copy selection 本身不向 shell 写入。
- command menu 的 Copy selection 入口仍沿用既有行为。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can copy selection without shell write"
flutter test test/widget_test.dart --plain-name "command menu copy writes the selection to the clipboard"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 在 terminal 中拖选文本，打开 action search，搜索 `copy selection` 并执行。
- 确认剪贴板内容等于 terminal 选区内容，不包含 action search 或 command menu 文案。
- 确认执行该动作不写 shell。

## Done When

- Copy selection 可以从 action search 执行。
- action search 对 copy selection 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- `copy` registry label 与命令菜单文案不同；action search 需要保留 `copy selection` 别名，避免用户按可见文案搜索不到入口。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
