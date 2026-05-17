# T-135 Productivity Runtime Event Controller

## Goal

把 P3 shell productivity event reducer 包装成可持有状态的 runtime controller，并支持通过注入式 hook 持久化 recent items。

## Scope

- `example/lib/features/productivity/shell_productivity_runtime_controller.dart`
- `example/test/productivity/shell_productivity_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接真实 shell hook stream
- 不直接依赖 `ShellRecentItemsRepository`
- 不接 UI
- 不启动 shell session
- 不保存 remote/SSH context

## Current Progress

- 已新增 `ShellProductivityRuntimeController`。
- controller 持有 `ShellProductivitySnapshot`。
- controller 可应用 `ShellProductivityEvent`。
- controller 支持可选 `persistRecentItems` hook。
- 已补充 event apply + recent persistence、multiple event state tests。

## Functional Acceptance

- shell productivity events 可以更新 controller snapshot。
- recent items 更新后可以通过注入式 hook 保存。
- controller 不直接依赖 repository。
- 多个 event 会保留当前 snapshot。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/productivity/shell_productivity_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只新增 runtime controller，不接真实 event stream；无需人工 UI 验收。

## Done When

- P3 shell integration event path 已有 runtime controller。
- 后续真实 shell hook event stream 可以调用该 controller 并注入 recent items repository。

## Risks / Follow-ups

- 后续需要按 pane/session scope 管理多个 productivity controller。
- recent items persistence 需要隐私/清理策略。
