# T-373 Command Action Search Clear Search Dispatch

## Goal

让 action search 能执行 `Clear search`，复用现有 shell search 清空行为，并保持不向 shell 写入。

## Scope

- 从 action search 搜索并选择 `clear search` 时调用现有 `_clearSearch()`。
- 增加 widget regression，确认已有 shell search query 和 match 时可清空搜索状态。
- 确认 action search 执行该动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 search overlay 打开/关闭规则。
- 不改变 next search match 或 previous search match 行为。
- 不改变 search mode 或 search index 排序。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-372-command-action-search-previous-search-match-dispatch.md`

## Functional Acceptance

- action search 搜索 `clear search` 后按 `Enter` 会清空 shell search query。
- 已有 search match 状态被清空，旧 match count 不再显示。
- 执行动作不向当前 shell 写文本。
- 搜索栏的 Clear 按钮行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can clear shell search without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 shell search，输入 query 并确认有命中。
- 打开 action search，搜索 `clear search`，按 `Enter`。
- 确认 search query 清空，terminal 没收到 action search 文案。

## Done When

- Clear search 可以从 action search 执行。
- action search 对 clear search 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- block action 真实执行、apply theme 和 reopen closed pane 仍需要独立 action search dispatch 覆盖。
