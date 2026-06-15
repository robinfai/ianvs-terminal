# T-344 Command Action Search Coprocess Dispatch

## Goal

让 action search 能执行高频非写入入口 `Coprocess`，从 action search 直接打开 coprocess sheet，同时保持打开动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `Coprocess` 时打开 `coprocess-sheet`。
- 复用现有 coprocess sheet 打开逻辑。
- 增加 widget regression，确认打开 coprocess 不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 coprocess start、stop 或 pattern matching 行为。
- 不改变 sheet 内部字段、校验或 active summary。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `coprocess` 后按 `Enter` 会打开 coprocess sheet。
- sheet 继续使用当前 active session 的 coprocess state。
- 打开 sheet 本身不向 shell 写入。
- command menu 的 coprocess 入口仍沿用既有行为。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open coprocess without shell write"
flutter test test/widget_test.dart --plain-name "coprocess replies to matching terminal output"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `coprocess`，按 `Enter`，确认 coprocess sheet 出现。
- 在已有 active coprocess 的 session 中确认 sheet 显示 active summary。
- 确认打开 sheet 和关闭 sheet 不写 shell；sheet 内部显式 start/stop 仍走既有逻辑。

## Done When

- Coprocess 可以从 action search 打开。
- action search 对 coprocess opening 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- sheet 内部包含会启动自动回复的显式动作；本任务只保证打开入口不写 shell。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
