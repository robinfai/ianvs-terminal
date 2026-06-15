# T-380 Selected Block Context Actions

## Goal

让用户从 context chips 选中的 command block 打开 block actions，并执行最常用的 block 操作。

## Scope

- ShellScreen 记录当前 session 的 selected command block id。
- 点击 `Last exit` chip 导航到失败 block 时，同时选中该 block。
- Context chip wiring 使用 selected block id 显示 `Block <command>` chip。
- 点击 `Block` chip 打开 block action sheet。
- Sheet 支持 `Copy block output`、`Reinput block command` 和 `Rerun block command`。
- `Copy block command` 和 `Copy command and output` 由 T-381 继续扩展。
- `Search within block` 由 T-382 继续扩展。
- action 执行复用 `CommandBlockActionReducer` 和现有 terminal/clipboard 路径。
- 增加 widget regressions 覆盖 copy output、re-input 和 rerun。

## Non-goals

- 不实现鼠标点击 scrollback 行来选择 block。
- 不实现 scoped search、save output 或 review entrypoint。
- 不持久化 selected block state。
- 不改变 action search 的 block action 行为。

## Files In Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_state_context_chips.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-326-command-center-context-chip-wiring.md`
- `docs/tasks/command-center/T-379-context-chip-last-failed-block-navigation.md`

## Functional Acceptance

- 点击 `Last exit` chip 后，active pane 出现 `Block <command>` chip。
- 点击 `Block` chip 打开 action sheet。
- `Copy block output` 复制真实 block output，不写 shell。
- `Reinput block command` 将原命令文本写回 shell，不加换行。
- `Rerun block command` 将原命令文本加换行写回 shell。
- 所有 action 都来自 selected block，不使用 overlay 文案。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "selected block chip opens block actions without shell write"
flutter test test/widget_test.dart --plain-name "selected block chip can reinput and rerun block command"
flutter test test/widget_test.dart --plain-name "context chip navigates to the last failed command block"
```

## Manual QA

- 运行失败命令并确认 `Last exit` chip 出现。
- 点击 `Last exit` chip，确认出现 `Block <command>` chip。
- 点击 `Block` chip，分别执行 copy、reinput、rerun。
- 确认 copy 只进 clipboard；reinput 不执行；rerun 会执行。

## Done When

- selected block chip 不再显示 not-ready feedback。
- block action sheet 有 widget regressions。
- Command Bar lane 验证门包含 selected block action regressions。

## Risks / Follow-ups

- 鼠标点击 scrollback 行选择任意 block 仍待实现。
- `Copy block command` 和 `Copy command and output` 已由 T-381 覆盖。
- scoped search 已由 T-382 覆盖。
- save output 已由 T-386 覆盖；review entrypoint 已由 T-387 覆盖。
