# T-339 Command Action Search Copy Mode Dispatch

## Goal

让 action search 能执行高频非写入入口 `Copy mode`，从 action search 直接进入 terminal copy mode，同时保持打开动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `Copy mode` 时进入 copy mode。
- 复用现有 `SelectionController` 和 copy mode 进入逻辑。
- 增加 widget regression，确认打开 copy mode 不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 copy mode 的选区扩展、复制或退出行为。
- 不改变 command menu 的 copy mode 入口。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `copy mode` 后按 `Enter` 会进入 copy mode。
- copy mode 使用当前 active session 的 viewport 和 selection controller。
- 打开 copy mode 本身不向 shell 写入。
- command menu 的 copy mode 入口仍沿用既有行为。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open copy mode without shell write"
flutter test test/widget_test.dart --plain-name "command-shift-c copy mode extends selection and copies with enter"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `copy mode`，按 `Enter`，确认 terminal 显示 Copy mode 提示。
- 在 copy mode 中用方向键扩展选择并按 `Enter` 复制，确认复制结果来自 terminal 内容。
- 确认打开 copy mode 时不写 shell，退出后焦点回到 terminal。

## Done When

- Copy mode 可以从 action search 打开。
- action search 对 copy mode opening 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- copy mode 仍依赖 active session 的 viewport；空 viewport 时应继续保持既有 no-op 行为。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
