# T-121 Shell Command Menu Model

## Goal

把现有 command menu 的固定 action 列表和顺序抽成模型层，同时复用 action view-model 和 availability diagnostics，为后续替换 `ShellScreen` 内联菜单提供低风险桥接。

## Scope

- `example/lib/features/shell/shell_command_menu_model.dart`
- `example/test/shell/shell_command_menu_model_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不替换现有 command menu widget
- 不改变菜单顺序
- 不执行 action
- 不新增菜单项 UI
- 不新增 remote/SSH action

## Current Progress

- 已新增 `ShellCommandMenuModel.defaultActionOrder`。
- default action order 保留当前 command menu 中已有 action 范围和顺序。
- 已新增 `ShellCommandMenuModel.defaultItems()`。
- default items 复用 `ShellActionViewModelBuilder.forDescriptor()`。
- 已补充 action order、item generation、disabled reason 测试。

## Functional Acceptance

- command menu action 顺序有稳定模型。
- item view model 可携带 enabled/disabled 和 disabled reason。
- 后续 UI 替换可以保留既有菜单项范围和顺序。
- 模型不引入 remote/SSH action。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_command_menu_model_test.dart
flutter analyze
```

## Manual QA

本任务只新增模型，不替换 UI；无需人工 UI 验收。

## Done When

- command menu 的数据源已有稳定桥接模型。
- 后续 `ShellScreen` 可以把内联 action list 切到该模型。

## Risks / Follow-ups

- 替换 UI 时必须确认原有 widget tests 的菜单项和快捷键文案仍通过。
- 新增 action 不应默认进入 command menu，除非产品验收明确要求。
