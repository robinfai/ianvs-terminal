# T-114 Shell Action Dispatcher

## Goal

聚合 P2 workspace reducer、P3 productivity reducer、P4 policy reducer 和 P5 visual reducer，建立 command menu / command palette 后续可调用的统一 action dispatch 入口。

## Scope

- `example/lib/features/shell/shell_action_dispatcher.dart`
- `example/test/shell/shell_action_dispatcher_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入现有 command menu UI
- 不执行真实 terminal side effects
- 不启动 shell session
- 不触发系统通知或 hotkey window
- 不新增 remote/SSH action

## Current Progress

- 已新增 `ShellActionDispatchResult` result family。
- 已新增 `ShellActionDispatchState`。
- 已新增 `ShellActionDispatchContext`。
- 已新增 `ShellActionDispatcher.dispatch()`。
- dispatcher 按 workspace -> productivity -> policy -> visual 顺序分发 action。
- 已补充 workspace、productivity、policy、visual、unhandled dispatch 测试。

## Functional Acceptance

- workspace action 返回 `ShellWorkspaceDispatchResult`。
- productivity action 返回 `ShellProductivityDispatchResult`。
- policy action 返回 `ShellPolicyDispatchResult`。
- visual action 返回 `ShellVisualDispatchResult`。
- 未映射 action 返回 `ShellUnhandledDispatchResult`。
- dispatcher 不触发平台副作用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_dispatcher_test.dart
flutter analyze
```

## Manual QA

本任务只新增 dispatcher，不接 UI；无需人工 UI 验收。

## Done When

- command menu / command palette 有统一 action dispatcher 可接入。
- 后续 UI 不需要分别调用 workspace/productivity/policy reducer。

## Risks / Follow-ups

- 后续需要把 dispatcher result 映射到真实 session lifecycle、viewport、paste、notification 和 hotkey side effects。
- dispatcher 优先级后续如有冲突，应通过 action category/handler registry 显式建模。
