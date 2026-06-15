# T-363 Command Action Search Focus Next Pane Dispatch

## Goal

让 action search 能执行 `Focus next pane`，复用现有 pane focus 行为，并保持不向 shell 写入。

## Scope

- 从 action search 搜索并选择 `focus next pane` 时调用 `_focusRelativePane(..., delta: 1)`。
- 复用 zoomed pane 管理阻塞反馈。
- 没有 next pane 时显示 `No next pane is available.`。
- 增加 widget regression，确认两个 pane 间可以从 action search 聚焦下一个 pane。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 pane ordering 或 wrapping 规则。
- 不改变 split pane 或 focus previous pane 行为。
- 不完成所有 pane management action search dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `focus next pane` 后按 `Enter` 会聚焦下一个 pane。
- zoomed pane 管理被阻塞时显示已有阻塞原因。
- 没有 next pane 时显示 `No next pane is available.`。
- 执行动作不向当前 shell 写文本。
- 命令菜单里的 `Focus next pane` 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can focus next pane without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 创建两个 pane，聚焦第一个 pane。
- 打开 action search，搜索 `focus next pane`，按 `Enter`。
- 确认焦点移动到第二个 pane，并且 terminal 没收到 overlay 文案。
- 在 zoomed pane 状态下确认显示 pane management blocked feedback。

## Done When

- Focus next pane 可以从 action search 执行。
- action search 对 focus next pane 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- focus previous pane、resize pane、swap pane 仍需要独立 action search dispatch 覆盖。
