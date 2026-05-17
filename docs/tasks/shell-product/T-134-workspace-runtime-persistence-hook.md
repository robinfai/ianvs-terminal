# T-134 Workspace Runtime Persistence Hook

## Goal

把 P2 workspace layout persistence 接入 `ShellActionRuntimeController` 的 workspace update path，让 workspace state 变化后可以通过注入式 hook 保存 layout。

## Scope

- `example/lib/features/shell/shell_action_runtime_controller.dart`
- `example/test/shell/shell_action_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P2_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不直接依赖 `LocalWorkspaceRepository`
- 不接 UI
- 不自动恢复 layout
- 不启动真实 session
- 不保存 remote/SSH state

## Current Progress

- `ShellActionRuntimeController.run()` 已支持可选 `persistWorkspace` callback。
- workspace update side effect 会调用 `persistWorkspace`。
- layout template apply side effect 更新 workspace 后也会调用 `persistWorkspace`。
- 已补充 new tab workspace persistence 和 layout template persistence 测试。

## Functional Acceptance

- workspace state 更新后可以触发注入式持久化 hook。
- layout template 应用后可以触发同一持久化 hook。
- controller 不直接依赖 repository，实现保持可测试。
- 持久化 payload 仍是 local-only `TerminalWorkspace`。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只新增 runtime hook，不接真实 repository；无需人工 UI 验收。

## Done When

- P2 workspace layout save path 可通过 action pipeline 触发。
- 后续 ShellScreen 可把 `LocalWorkspaceRepository.save` 注入该 hook。

## Risks / Follow-ups

- 后续真实 repository 接入时要处理保存失败的可见诊断。
- layout restore trigger 仍需独立接入。
