# T-082 Local Terminal Keybinding Resolver

## Goal

把 registry 默认快捷键和 `LocalTerminalConfig` 中的 disabled/override 合成统一 resolved keybinding 列表，并提供 resolved conflict diagnostics，为后续替换 `ShellScreen` 中硬编码 shortcut dispatch 做准备。

## Scope

- `example/lib/features/config/local_terminal_keybinding_resolver.dart`
- `example/lib/features/config/local_terminal_config_models.dart`
- `example/test/config/local_terminal_keybinding_resolver_test.dart`
- `docs/tasks/README.md`

## Non-goals

- 不接入 `ShellScreen` shortcut dispatch
- 不改 runtime 快捷键行为
- 不实现快捷键配置 UI
- 不实现平台差异化 keybinding DSL
- 不新增 SSH、remote、serial、SFTP 配置

## Current Progress

- 已新增 `LocalTerminalKeyBindingResolver.resolve()`。
- resolver 能读取 registry default keybinding。
- resolver 能应用 disabled default action。
- resolver 能用 user override 替换 registry default。
- 已新增 `LocalTerminalKeyBindingResolver.conflicts()`，用于检测最终 resolved binding 冲突。
- 已补充 default resolve、disable、override、conflict detection 测试。

## Functional Acceptance

- 空配置能解析出 registry 默认 keybinding 列表。
- disabled default action 会移除对应默认 binding。
- user override 会替换对应 action 的默认 binding。
- resolved conflicts 可以从最终 binding 列表诊断出来。
- 本任务不改变现有快捷键运行时行为。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/config/local_terminal_keybinding_resolver_test.dart
flutter analyze
```

## Manual QA

本任务不接入 runtime shortcut dispatch；无需人工 UI 验收。

## Done When

- keybinding resolver 可被后续 shortcut dispatch migration 任务复用
- resolved conflict diagnostics 可用
- 相关 resolver 测试通过

## Risks / Follow-ups

- 后续需要把 `LocalTerminalKeyBinding.key` 的字符串规范和 Flutter `LogicalKeyboardKey` 做正式映射。
- 后续需要将 `ShellScreen` 的 `_shortcutActionFor` 逐步切到 resolver，不应一次性替换所有输入路径。
