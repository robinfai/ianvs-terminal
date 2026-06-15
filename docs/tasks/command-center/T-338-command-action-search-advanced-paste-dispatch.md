# T-338 Command Action Search Advanced Paste Dispatch

## Goal

让 action search 能执行高频非写入入口 `Advanced paste`，从 action search 直接打开 advanced paste sheet，同时保持打开动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `Advanced paste` 时打开 `advanced-paste-sheet`。
- 增加 widget regression，确认打开 advanced paste 不写 shell。
- 测试中 mock clipboard，避免依赖本机剪贴板状态。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 advanced paste transform / send 行为。
- 不绕过 read-only 或 paste policy。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `advanced paste` 后按 `Enter` 会打开 advanced paste sheet。
- advanced paste sheet 用当前 clipboard 文本初始化。
- 打开 sheet 本身不向 shell 写入。
- command menu 的 advanced paste 入口仍能打开同一 sheet。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open advanced paste without shell write"
flutter test test/widget_test.dart --plain-name "advanced paste transforms edited clipboard text before sending"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `advanced paste`，按 `Enter`，确认 advanced paste sheet 出现。
- 确认 sheet 初始内容来自 clipboard。
- 关闭 sheet 时不写 shell；点击 Send 时继续走既有 paste 流程。

## Done When

- Advanced paste 可以从 action search 打开。
- action search 对 advanced paste opening 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- advanced paste 的发送动作仍必须由既有 paste policy 和 read-only 守住。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
