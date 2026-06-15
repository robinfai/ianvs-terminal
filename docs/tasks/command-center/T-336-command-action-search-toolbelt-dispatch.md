# T-336 Command Action Search Toolbelt Dispatch

## Goal

让 action search 能执行一个非写入型 panel action：`Toolbelt`。这一步继续扩大 action search 的真实 action 覆盖面，同时证明选择 app action 不会写入 shell。

## Scope

- 从 action search 搜索并选择 `Toolbelt` 时打开 `shell-toolbelt-panel`。
- 增加 `_openToolbelt()` helper，让 command menu fallback 和 action search 共用打开逻辑。
- 增加 widget regression，确认 Toolbelt action search dispatch 不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不完成全部 action search action dispatch。
- 不改变 Toolbelt 子项行为。
- 不改变普通 `/` 输入策略。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/lib/features/shell/shell_screen_state_command_actions.dart`
- `example/lib/features/shell/shell_screen_state_shortcuts_status.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `toolbelt` 后按 `Enter` 会打开 Toolbelt panel。
- 打开 Toolbelt 不向 shell 写入。
- command menu 的 Toolbelt 入口仍能打开同一 panel。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open toolbelt without shell write"
flutter test test/widget_test.dart --plain-name "toolbelt opens a sidebar with terminal tool shortcuts"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `toolbelt`，按 `Enter`，确认 Toolbelt panel 出现。
- 关闭 Toolbelt 后用 command menu 的 Toolbelt 入口再打开一次。
- 确认两条路径都不会把文本写进 terminal。

## Done When

- Toolbelt 可以从 action search 打开。
- action search 对非写入 panel action 的 dispatch 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- 后续仍需把更多 app actions 接到共享 dispatch。
- 长期应由 mode router / shared action executor 统一 action search、command menu 和 shortcuts。
