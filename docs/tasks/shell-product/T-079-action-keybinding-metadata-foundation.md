# T-079 Action Keybinding Metadata Foundation

## Goal

在已有 `TerminalActionId` / `ShellActionRegistry` 骨架上补齐第一层 keybinding metadata，使后续 P1 的 keybinding config、用户覆盖、禁用默认快捷键和冲突诊断可以复用同一套 action descriptor。

## Scope

- `example/lib/features/shell/shell_action_registry.dart`
- `example/test/shell/terminal_action_registry_test.dart`
- `docs/tasks/README.md`

## Non-goals

- 不实现完整用户 keybinding schema
- 不改变现有快捷键触发行为
- 不引入新配置文件
- 不新增 SSH、remote、serial、SFTP 相关 action 或配置字段
- 不改 pane/layout/workspace 持久化模型

## Current Progress

- 已新增 `TerminalKeyBindingScope`，表达 `global`、`focusedApp`、`terminalFocused`、`commandPaletteOpen`。
- 已新增 `TerminalInputPolicy`，表达 `terminalFirst`、`appFirst`、`performableOnly`。
- 已新增 `TerminalKeyBinding`，用于记录默认快捷键的 scope、key 和 modifier。
- 已新增 `TerminalKeyBindingConflict` 与 `ShellActionRegistry.defaultKeyBindingConflicts()`，为默认快捷键冲突诊断提供稳定入口。
- 已将当前已有快捷键 hint 的关键 action 补上 `defaultKeyBinding` 和 `terminalInputPolicy`。
- 已修正 hotkey window registry hint，使其与现有 UI 文案保持 `alt+cmd+Space` 一致。
- 已补充 registry metadata / conflict diagnostics 的测试断言。

## Functional Acceptance

- 每个 `TerminalActionId` 都有 descriptor metadata。
- 关键默认快捷键可以从 registry descriptor 读取，不再只存在于 UI 文案中。
- 默认快捷键冲突可以通过 registry API 检测。
- 当前默认快捷键集合不引入隐藏冲突。
- 该任务不改变 runtime shortcut dispatch 行为。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/terminal_action_registry_test.dart
flutter analyze
```

## Manual QA

1. 打开 command menu，确认原有菜单项仍可见。
2. 使用 `cmd+shift+P`、`cmd+T`、`cmd+D`、`cmd+shift+D`、`alt+cmd+Space` 等现有快捷键，确认行为保持不变。

## Done When

- registry descriptor 包含 default keybinding metadata
- 默认快捷键冲突诊断 API 可用
- 相关 registry 回归通过

## Risks / Follow-ups

- 后续仍需独立任务实现用户配置覆盖、禁用默认快捷键和配置文件迁移。
- 当前 change 只是 metadata foundation；shortcut dispatch 仍由 `ShellScreen` 现有路径处理。
