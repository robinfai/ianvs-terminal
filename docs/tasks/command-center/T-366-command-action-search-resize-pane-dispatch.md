# T-366 Command Action Search Resize Pane Dispatch

## Goal

让 action search 能执行 `Grow active pane` / `Resize pane`，复用现有 pane resize 行为，并保持不向 shell 写入。

## Scope

- 从 action search 搜索并选择 `resize pane` 时调用 `_growActivePane`。
- 复用 zoomed pane 管理阻塞反馈。
- 少于两个 pane 或 sibling 已到最小尺寸时显示现有 resize 阻塞原因。
- 增加 widget regression，确认 action search 触发后 active pane 变宽、sibling pane 变窄。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 pane resize delta 或最小尺寸策略。
- 不改变 swap/focus/zoom pane 行为。
- 不完成所有 pane management action search dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `resize pane` 后按 `Enter` 会 grow active pane。
- zoomed pane 管理被阻塞时显示已有阻塞原因。
- 少于两个 pane 或 sibling 到最小尺寸时显示现有 resize 阻塞原因。
- 执行动作不向当前 shell 写文本。
- 命令菜单里的 `Grow active pane` 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can resize pane without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 创建两个 pane，聚焦左侧 pane。
- 打开 action search，搜索 `resize pane`，按 `Enter`。
- 确认 active pane 变大、sibling pane 变小，并且 terminal 没收到 overlay 文案。
- 反复 resize 到最小尺寸边界，确认显示现有 blocked feedback。

## Done When

- Resize pane 可以从 action search 执行。
- action search 对 resize pane 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- close pane 和 reopen closed pane 仍需要独立 action search dispatch 覆盖。
