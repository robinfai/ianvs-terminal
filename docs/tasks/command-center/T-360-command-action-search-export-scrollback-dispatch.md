# T-360 Command Action Search Export Scrollback Dispatch

## Goal

让 action search 能执行 `Export scrollback`，从 action search 直接复用现有 scrollback/visible frame 导出行为，并在成功后显示导出路径。

## Scope

- 从 action search 搜索并选择 `export scrollback` 时复用现有 `_exportVisibleFrame` 路径。
- 增加 widget regression，使用 fake application support directory 验证导出的 `.txt` 文件包含可见终端内容。
- 确认 action search 执行该动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 scrollback export 的文件格式、目录策略或 metadata。
- 不改变 diagnostics export 行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `export scrollback` 后按 `Enter` 会走 scrollback export 路径。
- 成功导出后显示 `Scrollback exported to ...` snackbar，并保留 `Copy path` 动作。
- 导出的 `.txt` 文件包含当前可见 terminal 内容。
- 执行动作不向当前 shell 写文本。
- 命令菜单里的 `Export scrollback` 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can export scrollback without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `export scrollback`，按 `Enter`。
- 确认 snackbar 显示导出路径，并且 `Copy path` 可用。
- 打开导出文件，确认包含当前 scrollback 或可见 terminal 内容。
- 确认执行该动作不把 `export scrollback` 或 overlay 文案写进 shell。

## Done When

- Export scrollback 可以从 action search 执行。
- action search 对 scrollback export success path 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- widget test 需要在 `runAsync` 中触发该动作，才能稳定驱动真实文件 I/O。
- 后续仍需覆盖 clear scrollback 等剩余 action search dispatch。
