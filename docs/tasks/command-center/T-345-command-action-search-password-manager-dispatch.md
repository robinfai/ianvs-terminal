# T-345 Command Action Search Password Manager Dispatch

## Goal

让 action search 能执行高频非写入入口 `Password manager`，从 action search 直接打开 password manager sheet，同时保持打开动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `Password manager` 时打开 `password-manager-sheet`。
- 复用现有 password manager sheet 打开逻辑。
- 增加 widget regression，确认打开 password manager 不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 password prompt 检测。
- 不改变保存、删除或发送密码的行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `password manager` 后按 `Enter` 会打开 password manager sheet。
- 打开 sheet 本身不向 shell 写入。
- sheet 内部发送密码仍必须通过既有 prompt 检查。
- command menu 的 password manager 入口仍沿用既有行为。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open password manager without shell write"
flutter test test/widget_test.dart --plain-name "password manager sends saved passwords only at prompts"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `password manager`，按 `Enter`，确认 password manager sheet 出现。
- 无密码 prompt 时点击发送仍不写 shell；出现 password prompt 后显式发送才写入。
- 确认打开 sheet 和关闭 sheet 不写 shell。

## Done When

- Password manager 可以从 action search 打开。
- action search 对 password manager opening 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- password manager 内部包含敏感发送动作；本任务只保证打开入口不写 shell。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
