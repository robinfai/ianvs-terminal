# T-083 Shell Shortcut Registry Dispatch

## Goal

让 `ShellScreen` 的快捷键入口开始消费 registry/resolver 的默认 keybinding metadata，减少 shortcut action 映射散落，为后续用户配置覆盖和 conflict diagnostics 接入运行时铺路。

## Scope

- `example/lib/features/shell/shell_screen.dart`
- `docs/tasks/README.md`

## Non-goals

- 不接入用户配置文件中的 keybinding override
- 不改变 tab 数字快捷键特例
- 不改 terminal input controller
- 不实现完整 shortcut editor UI
- 不新增 SSH、remote、serial、SFTP 能力

## Current Progress

- `_shortcutActionFor` 已从 `LocalTerminalKeyBindingResolver.resolve()` 读取 registry default binding。
- 默认 binding 匹配会根据当前平台选择 `Meta` 或 `Control` 作为 app modifier，保留原有 macOS / non-mac 语义。
- tab 数字快捷键仍由 `_tabShortcutIndexFor` 独立处理。
- runtime 仍使用空 `LocalTerminalKeybindingsConfig`，即当前行为只消费默认值，不启用用户 override。

## Functional Acceptance

- 现有默认快捷键 action 不再需要在 `_shortcutActionFor` 中逐个 switch 映射。
- registry descriptor 中的 default keybinding 是 runtime shortcut dispatch 的来源。
- 未接入用户 override 前，现有快捷键行为保持默认路径。
- tab 数字快捷键行为保持原有特例。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/terminal_action_registry_test.dart
flutter test test/config/local_terminal_keybinding_resolver_test.dart
flutter test test/widget_test.dart --plain-name "command-shift-p opens the command menu without leaking input"
flutter analyze
```

## Manual QA

1. 使用 `cmd+shift+P` 打开 command menu。
2. 使用 `cmd+T` 新建 tab。
3. 使用 `cmd+D` / `cmd+shift+D` split pane。
4. 使用 `cmd+1` 到 `cmd+9` 切换 tab，确认数字快捷键仍可用。

## Done When

- `_shortcutActionFor` 消费 registry/resolver metadata。
- 后续用户配置 keybinding 可以在同一 resolver 上继续接入。

## Risks / Follow-ups

- 后续需要把实际用户 `LocalTerminalConfig` 注入 resolver，而不是使用空配置。
- 后续需要把 conflict diagnostics 暴露到配置 warnings UI。
