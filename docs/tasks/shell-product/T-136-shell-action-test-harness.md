# T-136 Shell Action Test Harness

## Goal

为后续 ShellScreen / command menu widget 接入提供 side-effect executor test harness，让测试可以断言 action pipeline 计划执行的副作用，而不触发真实平台/UI 行为。

## Scope

- `example/lib/features/shell/shell_action_test_harness.dart`
- `example/test/shell/shell_action_test_harness_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入生产代码
- 不执行真实副作用
- 不替换 ShellScreen 测试
- 不触发平台 API
- 不新增 action

## Current Progress

- 已新增 `ShellActionSideEffectCall`。
- 已新增 `ShellActionTestHarness`。
- harness 可生成记录所有 side-effect kind 的 executor。
- 已补充 send paste side-effect call 记录测试。

## Functional Acceptance

- test harness 能捕获 executor handler 调用。
- 每次调用记录 kind 和 payload。
- harness 不触发真实副作用。
- 后续 widget tests 可复用 harness。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_test_harness_test.dart
flutter analyze
```

## Manual QA

本任务只新增测试 harness；无需人工 UI 验收。

## Done When

- ShellScreen action pipeline 接入前已有可复用测试 harness。
- 后续 UI 测试可以断言 side-effect plan execution。

## Risks / Follow-ups

- 生产代码不应依赖 test harness。
- 后续 widget tests 应覆盖 disabled reason 和 protected input contracts。
