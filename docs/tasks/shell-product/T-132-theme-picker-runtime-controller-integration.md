# T-132 Theme Picker Runtime Controller Integration

## Goal

把 P5 theme picker action 接入 `ShellActionRuntimeController`，让 `openThemePicker` action 可以通过统一 action pipeline 记录 UI intent。

## Scope

- `example/lib/features/shell/shell_action_runtime_controller.dart`
- `example/test/shell/shell_action_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不打开真实 theme picker UI
- 不应用 theme
- 不修改 profile/theme runtime
- 不读取 theme repository
- 不触碰 renderer

## Current Progress

- `ShellActionRuntimeState` 已新增 `themePickerRequested`。
- runtime controller 的 `openThemePicker` handler 会记录 theme picker request。
- 已补充 theme picker action 通过 runtime controller 记录 UI intent 的测试。

## Functional Acceptance

- `openThemePicker` action 可以进入统一 action pipeline。
- controller 能记录 theme picker UI intent。
- controller 不打开真实 UI。
- 后续 UI handler 可消费该 intent。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只接 runtime controller，不打开真实 UI；无需人工 UI 验收。

## Done When

- P5 theme picker action 已通过 action pipeline 进入 runtime controller。
- 后续 shell UI 可基于 `themePickerRequested` 打开真实 picker。

## Risks / Follow-ups

- 后续需要把 theme picker UI 与 theme repository/runtime apply 接上。
- theme apply 仍需保留 renderer rewrite 非目标。
