# T-371 Command Action Search Next Search Match Dispatch

## Goal

让 action search 能执行 `Next search match`，复用现有 shell search 的 next match 行为，并保持不向 shell 写入。

## Scope

- 从 action search 搜索并选择 `next search match` 时调用现有 `_moveSearchMatch(-1)`。
- 增加 widget regression，确认已有 shell search 结果时可移动到下一条 match。
- 确认 action search 执行该动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 shell search 默认 active match 规则。
- 不改变 previous search match 或 clear search 行为。
- 不改变 search index 排序。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `next search match` 后按 `Enter` 会移动 shell search 的 active match。
- 两个 search match 时从 `2/2` 移到 `1/2`，并滚动到对应 offset。
- 执行动作不向当前 shell 写文本。
- 搜索栏的 Next 按钮行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can move to next search match without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 shell search，输入能命中多条结果的 query。
- 打开 action search，搜索 `next search match`，按 `Enter`。
- 确认 active search match 移动，terminal 没收到 action search 文案。

## Done When

- Next search match 可以从 action search 执行。
- action search 对 next search match 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- previous search match、clear search、block actions、apply theme 和 reopen closed pane 仍需要独立 action search dispatch 覆盖。
