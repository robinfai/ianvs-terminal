# T-109 Local Workspace Action Reducer

## Goal

把 P1 的 `TerminalActionId` 与 P2 的 `TerminalWorkspace` 模型连接起来，建立 action -> workspace state change 的纯 reducer，为后续 `ShellScreen` runtime 接入降低风险。

## Scope

- `example/lib/features/workspace/local_workspace_action_reducer.dart`
- `example/test/workspace/local_workspace_action_reducer_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P2_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 `ShellScreen`
- 不启动真实 local shell session
- 不接 pane UI
- 不处理 shortcut dispatch
- 不新增 remote/SSH workspace action

## Current Progress

- 已新增 `LocalWorkspaceActionContext`。
- 已新增 `LocalWorkspaceActionReducer.reduce()`。
- reducer 覆盖 new tab、duplicate current cwd、split right/down、close/reopen tab、close/reopen pane、zoom、swap。
- 未处理的 action 保持 workspace 不变。
- 已补充 new tab、split、close/reopen tab、unhandled action 测试。

## Functional Acceptance

- workspace action 可以由稳定 action id 驱动。
- new tab / duplicate cwd 使用 local session intent。
- split action 更新 active tab 的 pane tree。
- close/reopen tab 维护 closed tab stack。
- 未接入的 action 不产生副作用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/workspace/local_workspace_action_reducer_test.dart
flutter analyze
```

## Manual QA

本任务只新增纯 reducer，不接 UI；无需人工 UI 验收。

## Done When

- P2 workspace runtime 接入有 action reducer 可复用。
- 后续 `ShellScreen` 可以逐步把 workspace action handler 切到该 reducer。

## Risks / Follow-ups

- 后续需要把 reducer context 的 id 生成和 active session lifecycle 接入真实 controller。
- 后续需要把 reducer 输出映射到现有 tab/pane UI state。
