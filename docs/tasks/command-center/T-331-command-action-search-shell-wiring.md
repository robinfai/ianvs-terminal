# T-331 Command Action Search Shell Wiring

## Goal

为 `/` action search 增加 ShellScreen 接线前的安全 helper，让 saved command insert 复用既有 terminal 写入策略。

## Scope

- 从 app action 和 saved command document 创建 `CommandActionSearchController`。
- 将 saved command selection 转成 insert terminal intent。
- 复用 `CommandSearchInsertExecutePolicy` 处理 read-only 和多行 paste policy。
- app action selection 不进入 terminal 写入路径。

## Non-goals

- 不实现 `/` overlay UI。
- 不把 `/` 快捷键接进 ShellScreen。
- 不执行 saved command。
- 不定义真实 app action registry。
- 不更新 saved command useCount 或 lastUsedAt。

## Files In Scope

- `example/lib/features/command_center/command_action_search_shell_wiring.dart`
- `example/test/command_center/command_action_search_shell_wiring_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- wiring 能用 action 列表和 saved command document 创建 controller。
- saved command insert 在 read-only=false 时返回 insert text intent。
- read-only=true 时返回 disabled intent。
- 多行 saved command 返回 requires paste policy intent。
- app action output 返回 no terminal write intent。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test \
  test/command_center/command_action_search_controller_test.dart \
  test/command_center/command_action_search_shell_wiring_test.dart \
  test/command_center/command_search_insert_execute_safety_test.dart
```

## Manual QA

纯 helper 任务，无 UI QA。后续 `/` overlay 和 ShellScreen 接线时必须手测：

- saved command insert 在 read-only 下被阻止。
- 多行 saved command 走 paste confirmation 或 paste policy。
- app action 选择不会把 action id 或标题写进 shell。
- 普通 `/` 文本不会自动打开 action search。

## Done When

- `/` ShellScreen 接线可以复用一个 helper 生成 controller 和 terminal intent。
- saved command insert 与 command search insert 使用同一安全策略。
- app action 与 saved command 的输出路径分离。

## Risks / Follow-ups

- 尚未有 `/` overlay UI。
- 尚未接入 ShellScreen 或 mode router。
- 真实 action registry 和 action dispatch 仍需后续任务。
