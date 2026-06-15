# T-341 Command Action Search Annotations Dispatch

## Goal

让 action search 能执行高频非写入入口 `Annotations`，从 action search 直接打开 annotations sheet，同时保持打开动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `Annotations` 时打开 `annotations-sheet`。
- 复用现有 selection controller 和 annotations sheet 打开逻辑。
- 增加 widget regression，确认打开 annotations 不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 annotation 的新增、删除或 badge 行为。
- 不改变 terminal 选区的计算方式。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `annotations` 后按 `Enter` 会打开 annotations sheet。
- annotations sheet 继续使用当前 active session 的 selected text 和 annotations。
- 打开 sheet 本身不向 shell 写入。
- command menu 的 annotations 入口仍沿用既有行为。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open annotations without shell write"
flutter test test/widget_test.dart --plain-name "annotations attach notes to selected terminal text"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `annotations`，按 `Enter`，确认 annotations sheet 出现。
- 选中 terminal 文本后重复入口，确认新增 annotation 时记录的是 terminal 选中内容。
- 确认打开 sheet、关闭 sheet 都不写 shell。

## Done When

- Annotations 可以从 action search 打开。
- action search 对 annotations opening 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- annotations 内容仍依赖 terminal selection；本任务只覆盖入口分发。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
