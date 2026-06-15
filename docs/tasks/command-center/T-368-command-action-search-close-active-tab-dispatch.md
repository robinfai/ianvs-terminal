# T-368 Command Action Search Close Active Tab Dispatch

## Goal

让 action search 能执行 `Close active tab`，复用现有 tab close 行为，并保持不向 shell 写入。

## Scope

- 从 action search 搜索并选择 `close active tab` 时调用现有 `_closeSession`。
- 增加 widget regression，确认两个 tab 时从 action search 关闭 active tab 后回到剩余 tab。
- 确认 action search 执行该动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 close tab 的 fallback focus 规则。
- 不改变 close pane 或 reopen closed tab 行为。
- 不完成所有 workspace action search dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `close active tab` 后按 `Enter` 会关闭 active tab。
- 两个 tab 时关闭 active tab 后只剩原 tab，且该 tab 被选中。
- 执行动作不向当前 shell 写文本。
- 命令菜单里的 close tab 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can close active tab without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 创建第二个 tab。
- 打开 action search，搜索 `close active tab`，按 `Enter`。
- 确认 active tab 被关闭，原 tab 重新选中，并且 terminal 没收到 overlay 文案。

## Done When

- Close active tab 可以从 action search 执行。
- action search 对 close active tab 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- reopen closed pane 仍需要独立 action search dispatch 覆盖。
