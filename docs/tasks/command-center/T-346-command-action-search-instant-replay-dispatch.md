# T-346 Command Action Search Instant Replay Dispatch

## Goal

让 action search 能执行高频非写入入口 `Instant replay`，从 action search 直接打开 instant replay workspace，同时保持打开动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `Instant replay` 时打开 `instant-replay-workspace`。
- 复用现有 instant replay seed 和 workspace 打开逻辑。
- 增加 widget regression，确认打开 instant replay 不写 shell。
- 在 widget test 中 mock window metrics，覆盖 instant replay seed 所需平台接口。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 instant replay frame recording 或 timeline 行为。
- 不改变 replay workspace 的复制、搜索、清空或退出行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `instant replay` 后按 `Enter` 会打开 instant replay workspace。
- workspace seed 继续使用当前 active session 的 latest viewport frame。
- 打开 workspace 本身不向 shell 写入。
- command menu / shortcut 的 instant replay 入口仍沿用既有行为。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open instant replay without shell write"
flutter test test/widget_test.dart --plain-name "command-option-b opens replay workspace backed by terminal viewport"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `instant replay`，按 `Enter`，确认 instant replay workspace 出现。
- 确认 workspace 内容来自当前 terminal viewport，且 live terminal 没有收到输入。
- 退出 workspace 后确认焦点和 live terminal 输入恢复正常。

## Done When

- Instant replay 可以从 action search 打开。
- action search 对 instant replay opening 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- instant replay seed 依赖 window metrics 平台接口；widget tests 必须 mock 该接口避免异步等待卡住。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
