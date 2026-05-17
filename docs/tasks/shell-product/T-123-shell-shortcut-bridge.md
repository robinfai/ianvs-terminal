# T-123 Shell Shortcut Bridge

## Goal

补齐 `ShellScreen` shortcut 接入前的桥接层，把平台修饰键状态、keybinding scope 和 local config 解析为 `TerminalActionId`。

## Scope

- `example/lib/features/shell/shell_shortcut_bridge.dart`
- `example/test/shell/shell_shortcut_bridge_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不修改 `_shortcutActionFor`
- 不读取真实 `HardwareKeyboard`
- 不接 session bootstrap config
- 不改变现有 shortcut 行为
- 不新增 platform DSL

## Current Progress

- 已新增 `ShellShortcutBridge.resolve()`。
- bridge 可将 macOS meta shortcut 映射到默认 action。
- bridge 可将 non-mac control shortcut 映射到默认 action。
- bridge 可消费 `LocalTerminalKeybindingsConfig` override。
- 已补充 mac default、non-mac default、config override 测试。

## Functional Acceptance

- 平台 app modifier 语义集中到 bridge。
- default binding 和 user override 都可解析为 action id。
- bridge 不直接读取全局 keyboard state，便于测试。
- 后续 `_shortcutActionFor` 可逐步迁移到 bridge。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_shortcut_bridge_test.dart
flutter analyze
```

## Manual QA

本任务只新增 bridge，不接 UI；无需人工 UI 验收。

## Done When

- shortcut dispatch 有 config-aware bridge 可复用。
- 后续 `ShellScreen` 接入时不需要重复平台修饰键判断。

## Risks / Follow-ups

- 后续实际接入必须保持 terminal input protected contracts。
- 需要统一 key string canonical format，避免不同平台 label 差异。
