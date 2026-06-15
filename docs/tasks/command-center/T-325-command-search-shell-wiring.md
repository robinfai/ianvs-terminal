# T-325 Command Search Shell Wiring

## Goal

把 Command Search 从独立 overlay 组件接到真实 `ShellScreen`：`Ctrl-R` 打开 command history search，选择结果后通过统一安全策略插入或显式执行。

## Scope

- 从 `CommandCenterRuntimeState` 创建 `CommandSearchOverlayController`。
- 在 terminal host key path 中消费 `Ctrl-R`，避免快捷键字节写进 shell。
- 在 active terminal pane overlay 层渲染 `CommandSearchOverlay`。
- 将 overlay insert / explicit execute output 通过 `CommandSearchInsertExecutePolicy` 转成 terminal intent。
- 多行命令复用 paste policy 和确认流程。

## Non-goals

- 不实现 saved commands。
- 不实现 `/` action search。
- 不落盘 global history。
- 不修改 terminal renderer。
- 不改变普通 terminal input、copy、paste 或 read-only 的基础规则。

## Files In Scope

- `example/lib/features/command_center/command_search_shell_wiring.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_state_command_search.dart`
- `example/lib/features/shell/shell_screen_state_terminal_workspace.dart`
- `example/lib/features/shell/shell_screen_state_clipboard.dart`
- `example/test/command_center/command_search_shell_wiring_test.dart`

## Functional Acceptance

- `Ctrl-R` 在 active terminal 中打开 command search overlay。
- `Ctrl-R` 被 ShellScreen 消费，不写入 PTY。
- overlay results 来自 Command Center runtime/session history。
- `Enter` 默认插入命令文本，不追加换行。
- modified `Enter` 产生显式执行文本。
- read-only 时 insert/execute 被禁用并给出可见原因。
- 多行命令走 paste policy，不绕过 paste confirmation。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test \
  test/command_center/command_search_shell_wiring_test.dart \
  test/command_center/command_search_overlay_test.dart \
  test/command_center/command_search_insert_execute_safety_test.dart \
  test/shell/shell_screen_architecture_test.dart
```

## Manual QA

- 运行 app 并产生几条带 shell hook 的命令历史。
- 在 active terminal 中按 `Ctrl-R`。
- 搜索并按 `Enter`，确认命令只插入不执行。
- 使用 modified `Enter`，确认显式执行才发送换行。
- 打开 read-only 后重试 insert/execute，确认不会写 shell。
- 对多行命令确认仍触发 paste confirmation 或 paste policy。

## Done When

- Command Search 有真实 ShellScreen 入口。
- shell 写入路径统一经过 insert/execute policy。
- 真实 UI 不再需要单独解析 command history。

## Risks / Follow-ups

- 当前只消费 `Ctrl-R` 打开 command history search，尚未实现 `/` action/saved command search。
- global history flush 仍需 repository 接入。
- overlay 视觉和 responsive polish 可以后续继续收口。
