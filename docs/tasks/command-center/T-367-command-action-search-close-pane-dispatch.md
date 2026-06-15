# T-367 Command Action Search Close Pane Dispatch

## Goal

让 action search 能执行 `Close pane`，复用现有 pane close 行为，并保持不向 shell 写入。

## Scope

- 从 action search 搜索并选择 `close pane` 时调用现有 `_closeSession`。
- 增加 widget regression，确认两个 pane 时从 action search 关闭 active pane 后只剩一个 pane。
- 确认 action search 执行该动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 close pane 的 fallback focus 规则。
- 不改变 close tab 或 reopen closed pane 行为。
- 不完成所有 pane management action search dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `close pane` 后按 `Enter` 会关闭 active pane。
- 两个 pane 时关闭 active pane 后只剩一个 `TerminalViewport`。
- 执行动作不向当前 shell 写文本。
- 命令菜单里的 `Close pane` 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can close pane without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 创建两个 pane。
- 打开 action search，搜索 `close pane`，按 `Enter`。
- 确认 active pane 被关闭，剩余 pane 可继续输入，并且 terminal 没收到 overlay 文案。

## Done When

- Close pane 可以从 action search 执行。
- action search 对 close pane 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- close active tab 已有独立 action search dispatch；reopen closed pane 的真实恢复由 T-376 覆盖。
