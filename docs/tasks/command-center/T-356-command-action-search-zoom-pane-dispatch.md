# T-356 Command Action Search Zoom Pane Dispatch

## Goal

让 action search 能执行高频非写入入口 `Zoom pane`，从 action search 直接缩放或取消缩放当前 pane，同时保持动作本身不向 shell 写文本。

## Scope

- 从 action search 搜索并选择 `zoom pane` 时复用现有 zoom pane 状态切换行为。
- 保留至少两个 pane 的可用性边界。
- 增加 widget regression，确认执行后命令菜单显示 `Unzoom active pane`。
- 确认 action search 执行该动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 pane layout、resize 或 zoom 视觉规则。
- 不改变 split right / split down 行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `zoom pane` 后按 `Enter` 会缩放当前 pane。
- 执行动作不向当前 shell 写文本。
- 只有一个 pane 时不会绕过 zoom pane 的不可用边界。
- 命令菜单和 tab context menu 的 zoom pane 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can zoom pane without shell write"
flutter test test/widget_test.dart --plain-name "tab context menu disables pane management actions while zoomed"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 创建两个 pane，打开 action search，搜索 `zoom pane`，按 `Enter`。
- 确认当前 pane 缩放，命令菜单显示 `Unzoom active pane`。
- 再执行一次确认可以取消缩放。
- 确认执行该动作不把 `zoom pane` 或 overlay 文案写进 shell。

## Done When

- Zoom pane 可以从 action search 执行。
- action search 对 zoom pane 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- 后续仍需覆盖 layout template 和更多 workspace-level action search dispatch。
