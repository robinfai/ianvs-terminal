# T-357 Command Action Search Layout Template Dispatch

## Goal

让 action search 能执行 `Apply two-pane layout`，从 action search 直接给当前单 pane tab 应用两 pane layout，同时保持动作本身不向 shell 写文本。

## Scope

- 从 action search 搜索并选择 `apply two-pane layout` 时复用现有 layout template 行为。
- 为 `applyLayoutTemplate` 增加 action search 别名，匹配 context menu 用户可见文案。
- 保留已有多 pane 时的不可用边界。
- 增加 widget regression，确认执行后当前 tab 内出现第二个 pane。
- 确认 action search 执行该动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 layout template 的视觉规则或 pane sizing。
- 不改变 split right、split down 或 zoom pane 行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_command_action_search_adapter.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `apply two-pane layout` 后按 `Enter` 会在当前 tab 内创建第二个 pane。
- 执行动作不向当前 shell 写文本。
- 已有多个 pane 时不会重复应用 layout template。
- context menu 的 `Apply two-pane layout` 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can apply two-pane layout without shell write"
flutter test test/widget_test.dart --plain-name "action search can split right without shell write"
flutter test test/shell/shell_command_action_search_adapter_test.dart
```

## Manual QA

- 打开 action search，搜索 `apply two-pane layout`，按 `Enter`。
- 确认当前 tab 内出现第二个 pane，而不是新建 tab。
- 已经有多个 pane 时再次搜索并执行，确认不会继续拆分。
- 确认执行该动作不把 `apply two-pane layout` 或 overlay 文案写进 shell。

## Done When

- Apply two-pane layout 可以从 action search 执行。
- action search 对 layout template 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- 后续仍需覆盖 export scrollback、export diagnostics 等带文件副作用的 action search dispatch。
