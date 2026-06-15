# T-386 Selected Block Save Output

## Goal

让 selected block action sheet 可以保存当前 block output。

## Scope

- 在 selected block action sheet 增加 `Save block output`。
- 复用 `CommandBlockActionReducer.saveOutput` 和现有 block intent dispatch。
- 复用 T-384 的 `LocalTerminalScrollbackExporter` 保存路径和文件格式。
- 导出的内容只包含 selected block output rows。
- 增加 widget regression 覆盖 selected block 入口、文件内容和无 shell 写入。

## Non-goals

- 不改变 action search 的 save output 行为。
- 不实现 selected block review entrypoint。
- 不新增文件选择器或自定义保存路径。
- 不改变 selected block 来源和持久化策略。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_context_chips.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-380-selected-block-context-actions.md`
- `docs/tasks/command-center/T-381-selected-block-copy-command-actions.md`
- `docs/tasks/command-center/T-382-selected-block-scoped-search.md`
- `docs/tasks/command-center/T-384-command-action-search-save-block-output.md`

## Functional Acceptance

- 点击 `Block <command>` chip 打开 action sheet 后，可以选择 `Save block output`。
- 该 action 只保存 selected block output，不包含 prompt、命令输入或 UI 文案。
- 保存文件使用 Application Support 下的 `scrollback_exports`。
- 该 action 不写 shell。
- 没有 output range 时显示 unavailable feedback，不创建空文件。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "selected block chip can save block output without shell write"
flutter test test/widget_test.dart --plain-name "selected block chip"
```

## Manual QA

- 运行一个产生输出的失败命令。
- 点击 `Last exit` chip，再点击 `Block <command>` chip。
- 选择 `Save block output`。
- 打开导出的 `.txt`，确认只包含当前 selected block 输出。
- 确认 live shell 没有收到任何输入。

## Done When

- selected block sheet 显示 save output 入口。
- selected block output 可以保存为本地纯文本文件。
- Command Bar lane 验证门包含 selected block save output regression。

## Risks / Follow-ups

- selected block review entrypoint 仍需要独立接入。
- 保存路径当前沿用 T-384；后续如加文件选择器，需要同时覆盖 action search 和 selected block。
