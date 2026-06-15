# T-359 Command Action Search Export Diagnostics Dispatch

## Goal

让 action search 能执行 `Export diagnostics`，从 action search 直接复用现有 diagnostics export 行为，并在没有可导出 bundle 时显示明确反馈。

## Scope

- 从 action search 搜索并选择 `export diagnostics` 时复用现有 diagnostics export 路径。
- 增加 widget regression，确认没有可导出 bundle 时显示不可用反馈。
- 确认 action search 执行该动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 diagnostics bundle 的采集内容或文件格式。
- 不强制在 widget test 中创建真实 diagnostics bundle。
- 不改变 export scrollback 行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `export diagnostics` 后按 `Enter` 会走 diagnostics export 路径。
- 没有可导出 bundle 时显示 `Diagnostics export is unavailable for the active sessions.`。
- 执行动作不向当前 shell 写文本。
- 命令菜单里的 `Export diagnostics` 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can explain unavailable diagnostics export"
flutter test test/widget_test.dart --plain-name "export diagnostics explains when no bundle is available"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `export diagnostics`，按 `Enter`。
- 在没有可导出 bundle 时确认出现不可用反馈。
- 在有 diagnostics bundle 时确认 snackbar 显示导出路径，并且 `Copy path` 可用。
- 确认执行该动作不把 `export diagnostics` 或 overlay 文案写进 shell。

## Done When

- Export diagnostics 可以从 action search 执行。
- action search 对 diagnostics export unavailable path 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- 真实 bundle 导出路径仍需要 manual QA 或专门文件系统测试覆盖。
- 后续仍需覆盖 export scrollback 等文件副作用更强的 action search dispatch。
