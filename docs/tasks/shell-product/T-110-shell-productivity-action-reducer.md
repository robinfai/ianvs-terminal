# T-110 Shell Productivity Action Reducer

## Goal

把 P1 的 productivity action id 与 P3 的 productivity state 连接起来，建立 action -> prompt/output/recent/search/read-only result 的纯 reducer。

## Scope

- `example/lib/features/productivity/shell_productivity_action_reducer.dart`
- `example/test/productivity/shell_productivity_action_reducer_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不滚动真实 viewport
- 不复制真实 command output
- 不打开 recent directory picker
- 不清空真实 scrollback
- 不接 command palette handler

## Current Progress

- 已新增 `ShellProductivityActionResult` result family。
- 已新增 `ShellProductivityActionContext`。
- 已新增 `ShellProductivityActionReducer.reduce()`。
- reducer 覆盖 toggle read-only、previous/next prompt、select/copy command output、open recent directory、search/global search。
- 已补充 read-only、prompt、command output、recent directory action tests。

## Functional Acceptance

- productivity action 可以由稳定 action id 驱动。
- read-only action 返回更新后的 productivity state。
- prompt action 返回目标 prompt mark。
- command output action 返回最后有效 command output range。
- recent directory action 返回可打开的本地目录。
- reducer 不触发 UI 或 terminal 副作用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/productivity/shell_productivity_action_reducer_test.dart
flutter analyze
```

## Manual QA

本任务只新增纯 reducer，不接 UI；无需人工 UI 验收。

## Done When

- P3 productivity runtime 接入有 action reducer 可复用。
- 后续 command palette/action menu 可以基于该 reducer 触发真实 side effects。

## Risks / Follow-ups

- 后续需要把 reducer result 映射到 viewport scroll、selection/copy、directory picker 等具体 side effects。
- clear scrollback 目前只返回 noop，需要后续接真实 terminal buffer 清理能力。
