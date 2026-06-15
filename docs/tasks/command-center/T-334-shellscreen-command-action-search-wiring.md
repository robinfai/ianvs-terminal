# T-334 ShellScreen Command Action Search Wiring

## Goal

把 action search 接到真实 `ShellScreen`，让用户可以从显式 command menu 入口打开 action / saved command 搜索面板，同时保持普通 terminal 输入优先。

## Scope

- 新增 `TerminalActionId.openActionSearch` 和 registry metadata。
- 在 command menu 顶部增加 `Action search` 显式入口。
- 让 command menu 搜索 `action search` 时打开 action search overlay。
- 在 active pane 右上角渲染 `CommandActionSearchOverlay`。
- 加载 `SavedCommandRepository`，供 action search 搜索 saved commands。
- saved command 选择复用 command search insert / paste safety。
- 增加 widget regression，证明普通 `/` 不会打开 action search，显式入口打开时不写 shell。

## Non-goals

- 不把普通 `/` 文本绑定为 action search shortcut。
- 不完成所有 app action 的 action-search 执行分发。
- 不替代后续 mode router。
- 不改变 terminal 默认输入路径。

## Files In Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/lib/features/shell/shell_screen_state_terminal_workspace.dart`
- `example/lib/features/shell/shell_screen_state_command_actions.dart`
- `example/lib/features/shell/shell_screen_command_menu.dart`
- `example/lib/features/shell/shell_action_registry.dart`
- `example/lib/features/shell/shell_command_menu_model.dart`
- `example/lib/features/command_center/command_action_search_shell_wiring.dart`
- `example/test/widget_test.dart`
- `example/test/shell/terminal_action_registry_test.dart`

## Functional Acceptance

- command menu 有明确 `Action search` 入口。
- `action search` 查询提交会打开 action search overlay。
- overlay 显示真实 shell action 搜索项。
- 打开 overlay 本身不会向 shell 写入。
- 普通 `/` 键不会打开 action search overlay。
- saved command insert 走 read-only 和 multiline paste policy。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "ordinary slash key does not open action search overlay"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
flutter test test/shell/terminal_action_registry_test.dart
flutter test test/command_center/command_action_search_shell_wiring_test.dart
flutter test test/shell/shell_command_action_search_adapter_test.dart
```

## Manual QA

- 打开 command menu，搜索 `action search`，确认 action search overlay 出现在 active pane。
- 在 terminal 输入普通 `/`，确认不会打开 overlay。
- 打开 overlay 后按 `Esc`，确认焦点返回 terminal。
- 有 saved command 时选择单行命令，确认只插入不自动执行。
- read-only 模式下选择 saved command，确认不会写 shell。

## Done When

- action search 有真实 ShellScreen 显式入口。
- action search 打开路径不依赖普通 `/` 文本。
- 保存命令插入复用既有 terminal safety。
- regression tests 覆盖普通 `/` 和显式入口。

## Risks / Follow-ups

- 需要后续任务把 action search action selection 完整复用现有 action dispatch。
- 需要后续 mode router 统一 terminal、command search、action search 的 input ownership。
- saved command 的创建、编辑、删除入口仍需单独规划。
