# T-130 Notification Runtime Controller Integration

## Goal

把 P4 notification intent 接入 `ShellActionRuntimeController`，让 notification-related action 可以通过统一 action pipeline 记录最后一次 badge/toast/system notification 意图。

## Scope

- `example/lib/features/shell/shell_action_runtime_controller.dart`
- `example/test/shell/shell_action_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P4_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不触发真实系统通知
- 不更新真实 badge/toast UI
- 不请求平台权限
- 不监听真实 terminal bell/activity
- 不改 `WindowBridge`

## Current Progress

- `ShellActionRuntimeState` 已记录 `lastNotificationIntent`。
- runtime controller 的 show notification handler 会记录 `LocalTerminalNotificationIntent`。
- notification action 可以通过 pipeline 进入 controller state。
- 已补充 bell notification action 记录 intent 的测试。

## Functional Acceptance

- notification action 进入 pipeline 后可记录 notification intent。
- intent 包含 notification event type。
- controller 不触发平台通知副作用。
- 后续真实 notification runtime 可从 intent 映射 badge/toast/system notification。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只接 runtime controller，不触发真实通知；无需人工 UI 验收。

## Done When

- P4 notification action 已通过 action pipeline 进入 runtime controller。
- 后续 badge/toast/system notification handler 可复用 intent。

## Risks / Follow-ups

- 后续系统通知权限失败必须映射为可见状态。
- notification UI 接入时要尊重 focus policy 和 threshold。
