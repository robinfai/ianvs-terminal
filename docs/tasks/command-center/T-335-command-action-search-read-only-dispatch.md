# T-335 Command Action Search Read-only Dispatch

## Goal

让 action search 选择结果能执行一个安全关键的真实 shell action：`toggleReadOnly`。这一步证明 action search 不只展示结果，也能把 app action output 接回 ShellScreen 行为层，同时保持不写 shell 的输入安全。

## Scope

- 从 action search 选择 `Toggle read only` 时切换当前 pane 的 read-only 状态。
- 复用 command menu 的 read-only snackbar 文案和状态切换逻辑。
- 增加 widget regression，确认 action search 执行 read-only action 不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不完成所有 action search action selection 分发。
- 不改变普通 `/` 输入策略。
- 不改变 command menu 的 read-only 行为。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/lib/features/shell/shell_screen_state_command_actions.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `read only` 后按 `Enter` 会切换当前 pane read-only。
- snackbar 使用和 command menu 相同的 enabled / disabled 文案。
- 执行该 action 不写入 shell。
- 既有 command menu read-only 测试仍然通过。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can run toggle read only without shell write"
flutter test test/widget_test.dart --plain-name "command menu accepts hyphenated read-only query"
flutter test test/widget_test.dart --plain-name "read-only mode disables paste actions in the command menu"
```

## Manual QA

- 打开 action search，搜索 `read only`，按 `Enter`，确认状态栏出现 read-only。
- 再次执行同一 action，确认 read-only 关闭。
- read-only 打开时尝试 paste / saved command insert，确认不会写 shell。

## Done When

- action search 至少有一个安全关键 app action 走真实 ShellScreen dispatch。
- read-only action 的 command menu 和 action search 行为一致。
- regression tests 覆盖 action search dispatch 不写 shell。

## Risks / Follow-ups

- 仍需后续任务把更多 action search app actions 接到共享 action dispatch。
- 长期应由 mode router / shared action executor 统一 action search、command menu 和 shortcuts。
