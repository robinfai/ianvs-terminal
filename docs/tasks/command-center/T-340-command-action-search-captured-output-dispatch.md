# T-340 Command Action Search Captured Output Dispatch

## Goal

让 action search 能执行高频非写入入口 `Captured output`，从 action search 直接打开 captured output sheet，同时保持打开动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `Captured output` 时打开 `captured-output-sheet`。
- 复用现有 captured output sheet 打开逻辑。
- 增加 widget regression，确认打开 captured output 不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 trigger matching 或 captured output 收集规则。
- 不改变 captured output 的复制、清空或通知行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `captured output` 后按 `Enter` 会打开 captured output sheet。
- captured output sheet 继续展示当前 session 已捕获内容或空状态。
- 打开 sheet 本身不向 shell 写入。
- command menu 的 captured output 入口仍沿用既有行为。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open captured output without shell write"
flutter test test/widget_test.dart --plain-name "captured output lists trigger-matched terminal rows"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `captured output`，按 `Enter`，确认 captured output sheet 出现。
- 在有 trigger match 的 session 中确认 sheet 展示已捕获行。
- 确认打开 sheet、关闭 sheet 都不写 shell；复制动作仍只写剪贴板。

## Done When

- Captured output 可以从 action search 打开。
- action search 对 captured output opening 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- captured output 的内容仍依赖 profile triggers 和 coprocess patterns；本任务只覆盖入口分发。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
