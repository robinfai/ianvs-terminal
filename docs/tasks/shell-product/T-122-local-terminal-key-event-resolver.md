# T-122 Local Terminal Key Event Resolver

## Goal

补齐 keybinding runtime bridge，把 key event snapshot 映射为 resolved keybinding signature，并返回对应 `TerminalActionId`，为后续用户 keybinding override 接入 `_shortcutActionFor` 做准备。

## Scope

- `example/lib/features/config/local_terminal_key_event_resolver.dart`
- `example/test/config/local_terminal_key_event_resolver_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 `ShellScreen`
- 不读取真实 `HardwareKeyboard`
- 不修改 shortcut dispatch
- 不实现 keybinding editor UI
- 不新增平台 DSL

## Current Progress

- 已新增 `LocalTerminalKeyEventSnapshot`。
- 已新增 `LocalTerminalKeyEventResolver.resolve()`。
- resolver 通过 event signature 匹配 resolved keybindings。
- 已补充 default binding、user override、unmatched event 测试。

## Functional Acceptance

- key event snapshot 可映射默认 keybinding action。
- key event snapshot 可映射用户 override action。
- unmatched event 返回 null。
- 该 bridge 不直接读取平台输入状态，方便测试和后续接入。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/config/local_terminal_key_event_resolver_test.dart
flutter analyze
```

## Manual QA

本任务只新增 key event bridge，不接 UI；无需人工 UI 验收。

## Done When

- P1 keybinding resolver 可被 runtime shortcut dispatch 消费。
- 后续 `_shortcutActionFor` 可以从硬编码/default-only 过渡到 config-aware resolver。

## Risks / Follow-ups

- 后续需要统一 `LocalTerminalKeyBinding.key` 字符串与 `LogicalKeyboardKey` label/debugName 的规范。
- 实际接入时必须保持 terminal input protected contracts。
