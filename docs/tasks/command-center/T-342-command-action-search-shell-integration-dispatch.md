# T-342 Command Action Search Shell Integration Dispatch

## Goal

让 action search 能执行高频非写入入口 `Shell integration`，从 action search 直接打开 shell integration utilities sheet，同时保持打开动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `Shell integration` 时打开 `shell-integration-utilities-sheet`。
- 复用现有 shell integration utilities 打开逻辑。
- 增加 widget regression，确认打开 shell integration utilities 不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 shell integration history、directory 或 prompt mark 数据源。
- 不改变 sheet 内部的 insert command、change directory 或 jump to mark 行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `shell integration` 后按 `Enter` 会打开 shell integration utilities sheet。
- sheet 继续使用当前 active session 的 shell integration state。
- 打开 sheet 本身不向 shell 写入。
- command menu 的 shell integration 入口仍沿用既有行为。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open shell integration without shell write"
flutter test test/widget_test.dart --plain-name "shell integration utilities synthesize a visible prompt mark from shell context"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `shell integration`，按 `Enter`，确认 shell integration utilities sheet 出现。
- 在有 shell hook history / directories / prompt marks 的 session 中确认 sheet 内容仍正确。
- 确认打开 sheet 和关闭 sheet 不写 shell；sheet 内部显式 insert/change directory 仍走既有输入路径。

## Done When

- Shell integration utilities 可以从 action search 打开。
- action search 对 shell integration opening 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- sheet 内部仍包含会写 shell 的显式动作；本任务只保证打开入口不写 shell。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
