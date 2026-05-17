# T-127 Layout Template Runtime Controller Integration

## Goal

把 P5 layout template apply side effect 接入 `ShellActionRuntimeController`，让 `applyLayoutTemplate` action 可以通过现有 action pipeline 更新 P2 workspace state。

## Scope

- `example/lib/features/shell/shell_action_runtime_controller.dart`
- `example/test/shell/shell_action_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 UI template picker
- 不启动真实 shell session
- 不保存 workspace layout
- 不实现复杂模板拓扑
- 不接远程/SSH 模板

## Current Progress

- `ShellActionRuntimeController.run()` 已支持可选 `LocalTerminalLayoutTemplateApplyContext`。
- `applyLayoutTemplate` side effect handler 会调用 `LocalTerminalLayoutTemplateApplier.apply()`。
- 成功应用 local-only template 后会更新 controller workspace state。
- 已补充 two-pane template 通过 runtime controller 更新 workspace 的测试。

## Functional Acceptance

- `applyLayoutTemplate` action 可以进入统一 action pipeline。
- controller 能把 layout template result 转成 workspace state 更新。
- non-local 或缺少 context 的 template 不产生副作用。
- 不启动或恢复 shell process。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只接入 runtime controller，不接 UI；无需人工 UI 验收。

## Done When

- P5 layout template 已通过 action pipeline 进入 workspace runtime state。
- 后续 UI 只需提供 template 和 apply context。

## Risks / Follow-ups

- 后续 UI 接入时需要生成稳定 pane/tab ids。
- 后续需要把应用后的 workspace layout 保存策略接入 `LocalWorkspaceRepository`。
