# T-337 Command Action Search Paste History Dispatch

## Goal

让 action search 能执行高频非写入入口 `Paste history`，从 action search 直接打开 paste history sheet，同时保持打开动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `Paste history` 时打开 `paste-history-sheet`。
- 增加 widget regression，确认打开 paste history 不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 paste history entry 的选择 / 发送策略。
- 不绕过 read-only 或 paste confirmation。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `paste history` 后按 `Enter` 会打开 paste history sheet。
- 打开 sheet 本身不向 shell 写入。
- command menu 的 paste history 入口仍能打开同一 sheet。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open paste history without shell write"
flutter test test/widget_test.dart --plain-name "empty paste history disables clear action"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `paste history`，按 `Enter`，确认 paste history sheet 出现。
- 空历史和非空历史都能从 sheet 正常展示。
- 确认只打开 sheet 不会向 terminal 写入文本。

## Done When

- Paste history 可以从 action search 打开。
- action search 对 paste history opening 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- paste history entry 选择仍由既有 sheet 流程负责，后续不能绕过 paste policy。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
