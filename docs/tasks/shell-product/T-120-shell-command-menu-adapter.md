# T-120 Shell Command Menu Adapter

## Goal

建立 command menu 接入 action pipeline 的 adapter：菜单项来自 action view-model，用户选择 action 后交给 `ShellActionRuntimeController` 执行。

## Scope

- `example/lib/features/shell/shell_command_menu_adapter.dart`
- `example/test/shell/shell_command_menu_adapter_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不替换现有 command menu widget
- 不改变菜单 UI 排版
- 不接真实 session lifecycle
- 不执行平台副作用
- 不新增 remote/SSH action

## Current Progress

- 已新增 `ShellCommandMenuAdapter`。
- adapter 可从 `ShellActionViewModelBuilder` 生成 command menu items。
- adapter 可把 selected action 交给 `ShellActionRuntimeController` 执行。
- 已补充 item generation 和 select execution 测试。

## Functional Acceptance

- command menu item 数据来自统一 action view-model。
- selected action 通过 runtime controller 执行。
- adapter 不直接处理 dispatcher/planner/executor 内部细节。
- adapter 不触发平台副作用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_command_menu_adapter_test.dart
flutter analyze
```

## Manual QA

本任务只新增 adapter，不替换现有 UI；无需人工 UI 验收。

## Done When

- 现有 command menu 后续可逐步切到 adapter。
- command menu 数据和执行入口都复用 action pipeline。

## Risks / Follow-ups

- 后续替换现有 command menu 时必须保持现有菜单项、快捷键文案和测试路径。
- disabled item 的 UI 呈现仍需接入现有 widget。
