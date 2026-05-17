# T-108 Shell Action View Models

## Goal

补齐 command palette / action menu 的通用 view-model 层，把 registry descriptor、availability 和 disabled reason 文案合成 UI 可直接渲染的 item。

## Scope

- `example/lib/features/shell/shell_action_view_models.dart`
- `example/test/shell/shell_action_view_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入现有 command menu widget
- 不改变菜单排序
- 不执行 action handler
- 不改变 shortcut dispatch
- 不新增 remote/SSH action

## Current Progress

- 已新增 `ShellActionMenuItemViewModel`。
- 已新增 `ShellActionViewModelBuilder.commandPaletteItems()`。
- 已新增 `ShellActionViewModelBuilder.forDescriptor()`。
- view model 可携带 enabled/disabled、disabled title/description 和 shortcut hint。
- 已补充 command palette visible filtering、disabled copy、shortcut hint 测试。

## Functional Acceptance

- command palette view model 只包含 registry 标记为 visible 的 action。
- disabled action 携带统一 title/description。
- shortcut hint 从 registry descriptor 继承。
- UI 后续可直接渲染，不需要重复 action availability 判断。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_view_models_test.dart
flutter analyze
```

## Manual QA

本任务只新增 view-model adapter，不接入 UI；无需人工 UI 验收。

## Done When

- command palette/action menu 有可复用 item view model。
- 后续 UI 接入可以显示 disabled reason，而不是执行失败。

## Risks / Follow-ups

- 后续需要把现有 command menu 切到该 view-model。
- 后续需要接入用户 keybinding override 后的 shortcut hint。
