# T-354 Command Action Search Split Right Dispatch

## Goal

让 action search 能执行高频非写入入口 `Split right`，从 action search 直接在当前 tab 内创建右侧 pane，同时保持动作本身不向现有 shell 写文本。

## Scope

- 从 action search 搜索并选择 `split right` 时复用现有 pane split 行为。
- 保留 split axis conflict 检查，避免绕过命令菜单的可用性边界。
- 增加 widget regression，确认执行后当前 tab 内出现第二个 pane。
- 确认 action search 执行该动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 split layout 算法、pane resize 或 focus 策略。
- 不实现 split down、zoom pane 或 layout template。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `split right` 后按 `Enter` 会在当前 tab 内创建第二个 pane。
- 执行动作不向当前 shell 写文本。
- split right 的 conflict guard 仍然生效。
- 命令菜单和 tab context menu 的 split right 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can split right without shell write"
flutter test test/widget_test.dart --plain-name "tab context menu split right opens a second pane in the active tab"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `split right`，按 `Enter`。
- 确认当前 tab 内出现右侧 pane，而不是新建 tab。
- 确认执行该动作不把 `split right` 或 overlay 文案写进 shell。

## Done When

- Split right 可以从 action search 执行。
- action search 对 split right 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- Split 操作会创建新 pane/session；后续需要继续覆盖 split down、zoom pane 和 layout template 的 action search dispatch。
