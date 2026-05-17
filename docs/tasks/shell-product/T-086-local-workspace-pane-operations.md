# T-086 Local Workspace Pane Operations

## Goal

在 P2 workspace model 中补齐 pane focus、resize、swap、zoom 的纯模型能力，为后续 action integration 和 UI 迁移提供稳定操作单元。

## Scope

- `example/lib/features/workspace/local_workspace_models.dart`
- `example/test/workspace/local_workspace_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P2_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 `ShellScreen`
- 不实现鼠标拖拽 resize UI
- 不实现方向性复杂 focus 算法
- 不保存或恢复外部进程状态
- 不新增 remote/SSH pane 类型

## Current Progress

- `TerminalWorkspaceTab.focusPane()` 已支持显式聚焦 pane。
- `TerminalWorkspaceTab.resizeActiveSplit()` 已支持更新 active pane 所在 split ratio。
- `TerminalWorkspaceTab.swapActivePaneWithSibling()` 已支持 active pane 与 sibling 交换位置。
- `TerminalWorkspaceTab.toggleZoomActivePane()` 已支持 zoom/unzoom 状态。
- layout serialization 已保存 `zoomedPaneId`。
- 已补充 focus/resize/swap/zoom 模型测试。

## Functional Acceptance

- focus 不接受不存在的 pane id。
- resize ratio 被限制在安全范围。
- swap 后 activePaneId 不变，但 pane 位置交换。
- zoom/unzoom 可以切换且不改变 pane tree。
- 操作模型不引入 remote/SSH pane 概念。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/workspace/local_workspace_models_test.dart
flutter analyze
```

## Manual QA

本任务只新增纯模型，不接入 UI；无需人工 UI 验收。

## Done When

- P2 pane 操作模型可以覆盖 split/focus/resize/swap/zoom 的基础行为。
- 后续 UI 接入只需要调用模型方法，不需要重新定义 pane tree。

## Risks / Follow-ups

- 当前 focus 是显式 pane id 聚焦，方向性 focus 仍需后续任务结合 UI 几何信息实现。
- 当前 swap 是 sibling swap，跨层级 move/swap 仍需后续任务扩展。
