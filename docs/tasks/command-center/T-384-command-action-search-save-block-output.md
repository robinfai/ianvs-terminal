# T-384 Command Action Search Save Block Output

## Goal

让 action search 可以把最近 command block 的输出保存为本地纯文本文件。

## Scope

- 新增 `saveBlockOutput` terminal action id 和 registry descriptor。
- action search 索引显示 `Save Block Output`。
- 选择该 action 时复用 `CommandBlockActionReducer.saveOutput`。
- 只导出 command block output rows，不包含 prompt、命令输入或 overlay 文案。
- 复用 `LocalTerminalScrollbackExporter` 写入 Application Support 下的 `scrollback_exports`。
- 成功后显示包含文件路径的 snackbar，并提供 `Copy path`。
- 增加 widget regression 覆盖 action search 入口、文件内容和无 shell 写入。

## Non-goals

- 不改变 selected block sheet 行为；selected block save output 由 T-386 覆盖。
- 不实现 review entrypoint。
- 不新增文件选择器或自定义保存路径。
- 不改变 scrollback exporter 的格式和 policy。
- 不改变 active block 选择策略，仍使用当前 session 最近 command block。

## Files In Scope

- `example/lib/features/shell/shell_action_registry.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-378-command-action-search-block-action-dispatch.md`
- `docs/tasks/command-center/T-383-command-action-search-block-scoped-search.md`

## Functional Acceptance

- action search 输入 `save block output` 后可以选择对应 action。
- 当前 session 有最近 command block 且有输出时，该 action 写出 `.txt` 文件。
- 写出的内容只包含 block output，行尾按 terminal 选择文本裁剪尾部空白。
- 成功后 snackbar 显示 `Command block output saved to <path>`。
- 该 action 不写 shell。
- 当前没有 command block 或没有 output range 时，仍走 `No command block is selected.` 或 `No command block output is available.` fallback。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can save block output without shell write"
flutter test test/widget_test.dart --plain-name "action search explains unavailable command block actions without shell write"
flutter test test/widget_test.dart --plain-name "action search"
```

## Manual QA

- 在 shell integration 可用的 session 中运行一个产生多行输出的命令。
- 打开 action search，搜索 `save block output` 并执行。
- 确认 snackbar 显示保存路径，`Copy path` 可复制路径。
- 打开导出的 `.txt`，确认只包含最近 block 输出，不包含 prompt、命令输入或 UI 文案。
- 在新 session 或没有 block 的状态下重复该 action，确认只显示 unavailable feedback。

## Done When

- action search 有 save block output 入口。
- 最近 command block output 可以保存到本地纯文本文件。
- Command Bar lane 验证门包含 save block output regression。

## Risks / Follow-ups

- 保存路径当前固定为 Application Support / `scrollback_exports`；后续可以增加显式保存位置选择。
- review entrypoint 已由 T-385 覆盖。
