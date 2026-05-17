# T-105 Local Terminal Notification Dispatcher

## Goal

补齐 P4 notification monitor dispatch 的纯决策层，把 bell、command finished、long-running、activity、silence 事件映射成 badge/toast/system notification 意图。

## Scope

- `example/lib/features/policies/local_terminal_notification_dispatcher.dart`
- `example/test/policies/local_terminal_notification_dispatcher_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P4_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不触发真实系统通知
- 不接 UI badge/toast
- 不监听真实 terminal events
- 不修改 `WindowBridge`
- 不新增 remote/SSH notification

## Current Progress

- 已新增 `LocalTerminalNotificationEventType`。
- 已新增 `LocalTerminalNotificationIntent`。
- 已新增 `LocalTerminalNotificationDispatcher.resolve()`。
- dispatcher 会根据 policy、focus state 和 duration threshold 返回通知意图或 null。
- 已补充 focus suppression、bell badge、long-running threshold 测试。

## Functional Acceptance

- focused 且 policy 为 unfocused 时不通知。
- unfocused bell 默认返回 badge intent。
- long-running command finished 必须满足 threshold。
- dispatcher 只返回意图，不触发平台副作用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/policies/local_terminal_notification_dispatcher_test.dart
flutter analyze
```

## Manual QA

本任务只新增纯 dispatcher，不接 UI；无需人工 UI 验收。

## Done When

- P4 notification rules 到 dispatch intent 的边界可复用。
- 后续 runtime 接入可以把 intent 映射到 badge/toast/system notification。

## Risks / Follow-ups

- 后续需要接真实 terminal bell/command events。
- 后续需要处理系统通知权限失败态。
