# T-116 Shell Action Side Effect Plan

## Goal

把 unified dispatcher 的 result 转成 UI/runtime 可执行的 side-effect plan，让 command menu / command palette 后续可以先计划副作用，再由具体 runtime 层执行。

## Scope

- `example/lib/features/shell/shell_action_side_effect_plan.dart`
- `example/test/shell/shell_action_side_effect_plan_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不执行真实副作用
- 不更新 UI state
- 不发送 paste
- 不触发通知或 hotkey window
- 不写文件

## Current Progress

- 已新增 `ShellActionSideEffectKind`。
- 已新增 `ShellActionSideEffectPlan`。
- 已新增 `ShellActionSideEffectPlanner.plan()`。
- planner 覆盖 workspace、productivity、policy、visual 和 unhandled dispatch result。
- paste decision 会映射成 send/confirm/block paste side-effect kinds。
- 已补充 workspace、paste、visual、unhandled 映射测试。

## Functional Acceptance

- dispatcher result 可以统一映射成 side-effect plan。
- plan 只表达意图，不执行副作用。
- paste 决策可区分 send、confirm、block。
- visual result 可映射 theme picker/export/template side effects。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_side_effect_plan_test.dart
flutter analyze
```

## Manual QA

本任务只新增 side-effect planning，不接 UI；无需人工 UI 验收。

## Done When

- command menu / command palette 可复用 dispatcher + side-effect planner 作为统一 action pipeline。
- 后续只需实现 side-effect executor。

## Risks / Follow-ups

- 后续需要把 plan 映射到真实 runtime executor。
- side-effect executor 必须继续保留 terminal input/paste/focus protected contracts。
