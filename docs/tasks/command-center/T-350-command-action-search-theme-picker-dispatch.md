# T-350 Command Action Search Theme Picker Dispatch

## Goal

让 action search 能执行高频非写入入口 `Theme picker`，从 action search 直接打开现有 `Defaults & appearance`，同时保持动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `theme picker` 时复用现有 Defaults & appearance 打开逻辑。
- 增加 widget regression，确认 action search 执行后出现 `defaults-dialog`。
- 确认 action search 执行该动作不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不新增独立 theme-only dialog。
- 不改变 Defaults & appearance 的保存、profile 或 theme preset 行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `theme picker` 后按 `Enter` 会打开 Defaults & appearance dialog。
- 打开动作不向 shell 写入。
- 命令菜单里的 `Terminal color presets` / `Theme picker` 搜索语义保持可用。
- Defaults & appearance 的既有 command menu 和 shortcut 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open theme picker without shell write"
flutter test test/widget_test.dart --plain-name "command menu explains disabled actions inline"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `theme picker`，按 `Enter`。
- 确认 Defaults & appearance 打开，并能看到 terminal color preset 相关区域。
- 确认执行该动作不写 shell，也不会把 overlay 文案送进终端。

## Done When

- Theme picker 可以从 action search 打开。
- action search 对 theme picker opening 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- 该入口当前复用 Defaults & appearance；若后续拆出独立 theme picker，需要同步命令菜单、action search 和验证文案。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
