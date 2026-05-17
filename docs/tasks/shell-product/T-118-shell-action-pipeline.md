# T-118 Shell Action Pipeline

## Goal

把 unified dispatcher、side-effect planner 和 injectable executor 组合成一个可调用 pipeline，给后续 `ShellScreen` / command menu / command palette 提供单入口 action execution path。

## Scope

- `example/lib/features/shell/shell_action_pipeline.dart`
- `example/test/shell/shell_action_pipeline_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 `ShellScreen`
- 不实现真实 side-effect handlers
- 不启动 shell session
- 不发送 paste
- 不触发系统通知或 hotkey window

## Current Progress

- 已新增 `ShellActionPipelineResult`。
- 已新增 `ShellActionPipeline`。
- pipeline 按 `dispatch -> plan -> execute` 顺序运行。
- pipeline 返回 dispatch result 和 side-effect plan，方便 UI/runtime 记录或诊断。
- 已补充 workspace、productivity、policy、visual action pipeline 测试。

## Functional Acceptance

- action pipeline 可以统一处理 workspace action。
- action pipeline 可以统一处理 productivity action。
- action pipeline 可以统一处理 policy action。
- action pipeline 可以统一处理 visual action。
- pipeline 本身只调用注入 executor，不直接触发平台副作用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_pipeline_test.dart
flutter analyze
```

## Manual QA

本任务只新增 pipeline，不接 UI；无需人工 UI 验收。

## Done When

- action execution 已形成 `registry -> availability/view-model -> dispatcher -> plan -> executor -> pipeline` 的完整抽象链路。
- 后续 `ShellScreen` 只需要接入 pipeline 和真实 handlers。

## Risks / Follow-ups

- 后续真实 handlers 必须继续保留 terminal input、paste、focus、selection protected contracts。
- pipeline 接入 UI 时应记录 unhandled action 和 disabled reason，避免静默失败。
