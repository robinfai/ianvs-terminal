# T-131 Productivity Runtime Controller Integration

## Goal

把 P3 productivity action result 接入 `ShellActionRuntimeController`，让 prompt navigation、command output selection 和 recent directory actions 可以通过统一 action pipeline 记录 runtime intent。

## Scope

- `example/lib/features/shell/shell_action_runtime_controller.dart`
- `example/test/shell/shell_action_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不滚动真实 viewport
- 不复制真实 command output
- 不打开真实 recent directory picker
- 不修改 terminal buffer
- 不接 UI

## Current Progress

- `ShellActionRuntimeState` 已记录 `lastPromptTarget`。
- `ShellActionRuntimeState` 已记录 `lastCommandOutputRange`。
- `ShellActionRuntimeState` 已记录 `lastRecentDirectory`。
- runtime controller 的 scroll/select/open handlers 会记录对应 payload。
- 已补充 prompt、command output、recent directory action 测试。

## Functional Acceptance

- prompt navigation action 可以记录目标 prompt mark。
- command output action 可以记录 output range。
- recent directory action 可以记录目标目录。
- controller 不执行 UI/terminal side effects。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只接 runtime controller，不接 UI；无需人工 UI 验收。

## Done When

- P3 productivity actions 已通过 action pipeline 进入 runtime controller。
- 后续 UI handler 可以消费 controller 记录的 prompt/range/directory intent。

## Risks / Follow-ups

- 后续真实 viewport/selection/picker side effects 必须处理 missing payload。
- read-only/input protected contracts 仍需在真实 side-effect 层保留。
