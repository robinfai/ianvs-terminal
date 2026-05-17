# T-117 Shell Action Side Effect Executor

## Goal

补齐 side-effect plan 的可注入 executor 协议，让后续 runtime/UI 可以按 plan kind 挂载真实副作用，同时保持测试层不触发平台行为。

## Scope

- `example/lib/features/shell/shell_action_side_effect_executor.dart`
- `example/test/shell/shell_action_side_effect_executor_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不实现真实副作用
- 不接 `ShellScreen`
- 不发送 paste
- 不打开 hotkey window
- 不写文件

## Current Progress

- 已新增 `ShellActionSideEffectHandler`。
- 已新增 `ShellActionSideEffectHandlers`。
- 已新增 `ShellActionSideEffectExecutor`。
- executor 根据 `ShellActionSideEffectKind` 调用对应 handler。
- 缺失 handler 和 `none` plan 会安全忽略。
- 已补充 handler dispatch 和 noop 测试。

## Functional Acceptance

- side-effect executor 可以按 kind 调用注入 handler。
- executor 本身不依赖 Flutter UI 或平台 API。
- 未注入 handler 时不抛错。
- `none` plan 不产生副作用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_side_effect_executor_test.dart
flutter analyze
```

## Manual QA

本任务只新增 executor 协议，不接 UI；无需人工 UI 验收。

## Done When

- action pipeline 已有 dispatcher -> plan -> executor 的完整抽象链路。
- 后续 `ShellScreen` 可以逐个 handler 接入真实行为。

## Risks / Follow-ups

- 后续实际 handler 必须维护 terminal focus/input/paste protected contracts。
- 真实平台 handler 需要独立错误处理和可见诊断。
