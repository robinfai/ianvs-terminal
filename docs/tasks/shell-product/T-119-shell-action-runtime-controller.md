# T-119 Shell Action Runtime Controller

## Goal

把 action pipeline 推进到可持有状态的 runtime controller，先用注入式 executor handlers 更新 workspace、productivity 和 hotkey window state，为后续 `ShellScreen` 接入提供单一控制器边界。

## Scope

- `example/lib/features/shell/shell_action_runtime_controller.dart`
- `example/test/shell/shell_action_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 `ShellScreen`
- 不启动真实 shell session
- 不发送真实 paste
- 不触发真实 hotkey window
- 不执行平台副作用

## Current Progress

- 已新增 `ShellActionRuntimeState`。
- 已新增 `ShellActionRuntimeController`。
- controller 通过 `ShellActionPipeline` 执行 action。
- controller handlers 已能更新 workspace state、productivity state 和 hotkey window state。
- controller 会记录最后一次 side-effect plan。
- 已补充 workspace、productivity、hotkey state update 测试。

## Functional Acceptance

- workspace action 可更新 controller workspace state。
- productivity action 可更新 controller productivity state。
- hotkey action 可更新 controller policy/hotkey state。
- controller 不直接触发平台副作用。
- 后续 `ShellScreen` 可把真实 handlers 替换或扩展到该控制器边界。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只新增 runtime controller，不接 UI；无需人工 UI 验收。

## Done When

- action pipeline 有可持有状态的 runtime controller。
- 后续 UI 接入不需要直接操作 dispatcher/planner/executor 内部层。

## Risks / Follow-ups

- 后续需要把 controller state 与现有 `ShellScreen` / `SessionController` 状态同步。
- 真实 handlers 必须保留 terminal protected contracts。
