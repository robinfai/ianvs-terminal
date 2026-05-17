# T-137 Runtime Controller External Executor Hook

## Goal

让 `ShellActionRuntimeController` 支持可选 external side-effect executor，使 ShellScreen 后续可以在保留 controller 默认状态更新的同时，把 side-effect plan 转交给真实 UI/runtime handler。

## Scope

- `example/lib/features/shell/shell_action_runtime_controller.dart`
- `example/test/shell/shell_action_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不实现真实 UI/runtime handler
- 不改变默认 controller 行为
- 不替换 ShellScreen
- 不触发平台 API
- 不新增 action

## Current Progress

- `ShellActionRuntimeController.run()` 已支持可选 `externalExecutor`。
- controller 仍先执行内部状态更新 handlers。
- controller 会把同一个 side-effect plan 传给 external executor。
- 已补充 external executor 记录 send paste side effect 的测试。

## Functional Acceptance

- external executor 可以观察/执行同一个 side-effect plan。
- 未传 external executor 时默认行为不变。
- controller 仍记录 lastPlan 和内部状态。
- ShellScreen 后续可注入真实 side-effect handlers。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只新增注入 hook；无需人工 UI 验收。

## Done When

- Runtime controller 可桥接真实 UI/runtime side effects。
- ShellScreen 接入无需绕过 action pipeline。

## Risks / Follow-ups

- external executor 失败时需要后续定义错误处理和用户可见诊断。
- 真实 handlers 必须维护 terminal protected contracts。
