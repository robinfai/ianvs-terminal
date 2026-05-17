# T-111 Local Terminal Policy Action Reducer

## Goal

把 P1 的 policy-related action id 与 P4 的 paste/notification/hotkey 策略模型连接起来，建立 action -> paste decision / notification intent / hotkey state 的纯 reducer。

## Scope

- `example/lib/features/policies/local_terminal_policy_action_reducer.dart`
- `example/test/policies/local_terminal_policy_action_reducer_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P4_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不发送真实 paste
- 不触发真实通知
- 不调用 `WindowBridge`
- 不修改 paste history repository
- 不接 UI

## Current Progress

- 已新增 `LocalTerminalPolicyActionResult` result family。
- 已新增 `LocalTerminalPolicyBundle`。
- 已新增 `LocalTerminalPolicyActionContext`。
- 已新增 `LocalTerminalPolicyActionReducer.reduce()`。
- reducer 覆盖 paste/advanced paste/paste history、bell/command/activity notification、hotkey window。
- 已补充 paste decision、notification intent、hotkey disabled failure、hotkey enabled toggle 测试。

## Functional Acceptance

- paste action 返回统一 paste decision。
- notification action 返回 dispatch intent 或 null。
- hotkey window action 在 disabled/misconfigured 时返回 visible failure state。
- hotkey window enabled 且 size 可用时返回 toggled state。
- reducer 不触发平台副作用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/policies/local_terminal_policy_action_reducer_test.dart
flutter analyze
```

## Manual QA

本任务只新增纯 reducer，不接 UI；无需人工 UI 验收。

## Done When

- P4 policy runtime 接入有 action reducer 可复用。
- 后续 UI/runtime 只需把 reducer result 映射为真实副作用。

## Risks / Follow-ups

- 后续需要把 paste decision 接入现有 paste path。
- 后续需要把 hotkey failure state 接入可见 UI。
