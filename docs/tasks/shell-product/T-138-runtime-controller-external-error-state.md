# T-138 Runtime Controller External Error State

## Goal

给 `ShellActionRuntimeController` 的 external executor hook 增加错误捕获和状态记录，避免真实 UI/runtime handler 失败时直接打断 action pipeline。

## Scope

- `example/lib/features/shell/shell_action_runtime_controller.dart`
- `example/test/shell/shell_action_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不实现 UI error banner
- 不重试失败副作用
- 不吞掉内部 controller 状态更新
- 不改变 external executor API
- 不接平台错误类型映射

## Current Progress

- `ShellActionRuntimeState` 已新增 `lastExternalExecutorError`。
- controller 会捕获 external executor 抛出的异常。
- external executor 失败不会阻止内部状态更新。
- 已补充 external executor throw 时 controller 记录错误且不抛出的测试。

## Functional Acceptance

- external executor 失败可记录到 controller state。
- controller 不把外部副作用异常重新抛出。
- 内部 action state 仍保持更新。
- 后续 UI 可基于错误状态展示诊断。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只新增错误状态，不接 UI；无需人工 UI 验收。

## Done When

- Action pipeline 具备外部 handler 失败状态记录。
- 后续真实 ShellScreen handler 可安全接入并暴露错误。

## Risks / Follow-ups

- 后续需要把错误对象映射成用户可读诊断。
- 某些关键 side effect 失败可能需要 retry 或 rollback 策略。
