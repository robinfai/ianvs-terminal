# T-098 Shell Action Availability Diagnostics

## Goal

建立 action availability / disabled diagnostics 的统一模型，把 active session、shell integration feature gates、read-only、command output range 和 recent directory 等状态转成可展示的不可用原因。

## Scope

- `example/lib/features/shell/shell_action_availability.dart`
- `example/test/shell/shell_action_availability_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`
- `docs/LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 command palette UI
- 不修改 action handler
- 不改变 runtime shortcut dispatch
- 不实现具体提示文案
- 不新增 remote/SSH availability gate

## Current Progress

- 已新增 `ShellActionDisabledReason`。
- 已新增 `ShellActionAvailability`。
- 已新增 `ShellActionAvailabilityResolver`。
- resolver 已覆盖 active session、prompt navigation、command output、recent directory 和 read-only paste gates。
- 已补充 active session、prompt disabled、read-only paste、command output range 的测试。

## Functional Acceptance

- requiresActiveSession 的 action 在无 active session 时 disabled。
- prompt navigation 在无 prompt marks 或 feature unavailable 时 disabled。
- command output action 在无有效 output range 时 disabled。
- paste action 在 read-only 下 disabled。
- disabled reason 可被后续 UI 转成可见诊断。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_availability_test.dart
flutter analyze
```

## Manual QA

本任务只新增诊断模型，不接入 UI；无需人工 UI 验收。

## Done When

- action availability 诊断有统一入口。
- 后续 command palette/action menu 可以显示 disabled reason，而不是执行失败。

## Risks / Follow-ups

- 后续需要补齐更多 action-specific gates。
- 后续需要把 disabled reason 映射到用户可读文案。
