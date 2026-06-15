# T-361 Command Action Search Clear Scrollback Dispatch

## Goal

让 action search 能执行 `Clear scrollback`，从 action search 直接复用现有 runtime clear scrollback 行为，并在 runtime 不支持时显示明确反馈。

## Scope

- 从 action search 搜索并选择 `clear scrollback` 时调用 runtime `clearScrollback`。
- 增加 widget regression，确认 fake runtime 不支持 native clear 时显示不可用反馈。
- 确认 action search 执行该动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 native clear scrollback 协议或 runtime 返回格式。
- 不改变 scrollback export 行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `clear scrollback` 后按 `Enter` 会走 runtime clear scrollback 路径。
- runtime 不支持时显示 `Clear scrollback requires native runtime support.`。
- runtime 成功清理时显示 `Cleared scrollback.`。
- 执行动作不向当前 shell 写文本。
- 命令菜单里的 `Clear scrollback` 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can explain unavailable clear scrollback without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `clear scrollback`，按 `Enter`。
- 在支持 native clear 的 runtime 中确认 scrollback 被清理，并显示 `Cleared scrollback.`。
- 在不支持 native clear 的 runtime 中确认显示不可用反馈。
- 确认执行该动作不把 `clear scrollback` 或 overlay 文案写进 shell。

## Done When

- Clear scrollback 可以从 action search 执行。
- action search 对 clear scrollback unavailable path 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- fake pty backend 当前只覆盖不可用路径；成功清理路径仍依赖 runtime/controller 层测试和 manual QA。
- 后续仍需覆盖 remaining search/navigation action dispatch。
