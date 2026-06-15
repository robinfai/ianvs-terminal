# T-365 Command Action Search Swap Pane Dispatch

## Goal

让 action search 能执行 `Swap active pane`，复用现有 pane swap 行为，并保持不向 shell 写入。

## Scope

- 从 action search 搜索并选择 `swap pane` 时调用 `swapActivePaneWithSibling`。
- 复用 zoomed pane 管理阻塞反馈。
- 少于两个 pane 时显示 `Swap pane requires at least two panes.`。
- 增加 widget regression，确认两个 pane 的屏幕位置会从 action search 触发交换。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 pane ordering 或 sibling selection 规则。
- 不改变 focus next/previous pane 或 resize pane 行为。
- 不完成所有 pane management action search dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `swap pane` 后按 `Enter` 会交换 active pane 和 sibling pane。
- zoomed pane 管理被阻塞时显示已有阻塞原因。
- 少于两个 pane 时显示 `Swap pane requires at least two panes.`。
- 执行动作不向当前 shell 写文本。
- 命令菜单里的 `Swap active pane` 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can swap pane without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 创建两个 pane，确认 pane 1 在左、pane 2 在右。
- 打开 action search，搜索 `swap pane`，按 `Enter`。
- 确认 pane 2 与 pane 1 交换位置，并且 terminal 没收到 overlay 文案。
- 在 zoomed pane 状态下确认显示 pane management blocked feedback。

## Done When

- Swap pane 可以从 action search 执行。
- action search 对 swap pane 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- resize pane、close pane 和 reopen closed pane 仍需要独立 action search dispatch 覆盖。
