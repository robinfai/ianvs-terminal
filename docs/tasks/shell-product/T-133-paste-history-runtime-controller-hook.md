# T-133 Paste History Runtime Controller Hook

## Goal

把 P4 paste history capture 接入 `ShellActionRuntimeController` 的 paste action 路径，让 paste decision 标记 `captureHistory` 时可以调用注入式 history recorder。

## Scope

- `example/lib/features/shell/shell_action_runtime_controller.dart`
- `example/test/shell/shell_action_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P4_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不直接依赖 `PasteHistoryRepository`
- 不写真实文件
- 不改变 paste UI
- 不发送真实 paste
- 不在 read-only block 时记录 history

## Current Progress

- `ShellActionRuntimeController.run()` 已支持可选 `recordPasteHistory` callback。
- send paste 和 confirm paste handler 会在 `captureHistory == true` 时调用 recorder。
- block paste 不记录 history。
- 已补充 paste action 记录 history callback 的测试。

## Functional Acceptance

- paste decision captureHistory 为 true 时可记录 paste text。
- recorder 由调用方注入，controller 不直接依赖 repository。
- read-only block 不记录 history。
- 真实 paste side effect 仍未触发。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只新增 runtime hook，不接真实 repository；无需人工 UI 验收。

## Done When

- P4 paste history capture 可以从 action pipeline 接入。
- 后续 ShellScreen handler 可把现有 `PasteHistoryRepository` 注入该 hook。

## Risks / Follow-ups

- 后续接真实 repository 时要避免记录敏感/被策略拒绝的大段 paste。
- confirmation UI 取消路径不能记录 history。
