# T-358 Command Action Search Reopen Closed Tab Dispatch

## Goal

让 action search 能执行 `Reopen closed tab`，从 action search 直接恢复最近关闭的 tab，同时保持动作本身不向 shell 写文本。

## Scope

- 从 action search 搜索并选择 `reopen closed tab` 时复用现有 reopen closed tab 行为。
- 保留没有最近关闭 tab 时的不可用边界。
- 增加 widget regression，确认关闭一个 tab 后可以从 action search 恢复。
- 确认 action search 执行该动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 close tab / close pane 行为。
- 不复用旧 runtime session id；reopen closed tab 仍按现有逻辑创建新 session。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `reopen closed tab` 后按 `Enter` 会恢复最近关闭的 tab。
- 恢复后的 tab 成为当前选中 tab。
- 执行动作不向当前 shell 写文本。
- 没有最近关闭 tab 时不会尝试恢复。
- 命令菜单里的 `Reopen closed tab` 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can reopen closed tab without shell write"
flutter test test/widget_test.dart --plain-name "closing the last tab can recover via Reopen closed tab"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 新建一个 tab，关闭它，保留另一个 active tab。
- 打开 action search，搜索 `reopen closed tab`，按 `Enter`。
- 确认最近关闭的 tab 被恢复，并成为当前选中 tab。
- 确认执行该动作不把 `reopen closed tab` 或 overlay 文案写进 shell。

## Done When

- Reopen closed tab 可以从 action search 执行。
- action search 对 reopen closed tab 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- Reopen 会创建新的 runtime session id；测试应验证恢复行为，不应要求复用旧 tab id。
- 后续仍需覆盖 close tab / close pane 等 workspace action search dispatch。
