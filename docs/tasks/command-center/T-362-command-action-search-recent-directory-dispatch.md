# T-362 Command Action Search Recent Directory Dispatch

## Goal

让 action search 能执行 `Open recent directory`，复用现有 recent directory 行为，并在没有可用目录时显示明确反馈。

## Scope

- 从 action search 搜索并选择 `open recent directory` 时读取当前 pane 的 shell integration recent directories。
- 没有 recent directory 时显示 `No recent directory is available.`。
- 有 recent directory 时发送现有 `cd <quoted path>` 命令到当前 session。
- 增加 widget regression，确认默认 fake runtime 的 unavailable path 不写 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 recent directory 的采集逻辑或 shell integration 数据模型。
- 不改变 `_shellQuotedPath` 行为。
- 不改变 command menu 的 `Open recent directory` 行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `open recent directory` 后按 `Enter` 会走 recent directory dispatch。
- 没有 recent directory 时显示 `No recent directory is available.`。
- 有 recent directory 时发送 `cd <quoted path>` 到当前 session，并回到 terminal focus。
- 默认 fake runtime 的 unavailable path 不向 shell 写文本。
- 命令菜单里的 `Open recent directory` 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can explain unavailable recent directory without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 打开 action search，搜索 `open recent directory`，按 `Enter`。
- 没有近期目录时确认显示 unavailable feedback。
- 有近期目录时确认终端收到 `cd <path>`，路径中空格和特殊字符被正确 quote。
- 确认 action search overlay 关闭后焦点回到当前 terminal。

## Done When

- Open recent directory 可以从 action search 执行。
- action search 对 recent directory unavailable path 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- 成功发送 `cd` 路径仍需要 shell integration 数据或 manual QA 覆盖。
- 后续仍需覆盖 prompt/search navigation、pane management 等剩余 action search dispatch。
