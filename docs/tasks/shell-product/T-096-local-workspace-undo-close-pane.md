# T-096 Local Workspace Undo Close Pane

## Goal

补齐 P2 的 undo close pane 模型行为，让关闭 pane 后可以恢复最近关闭的 pane，并保持 active pane 与 closed pane stack 的确定语义。

## Scope

- `example/lib/features/workspace/local_workspace_models.dart`
- `example/test/workspace/local_workspace_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P2_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 UI
- 不恢复外部 shell process
- 不实现复杂历史树 merge
- 不新增 remote pane 类型
- 不改变现有 `ShellScreen` pane 行为

## Current Progress

- `TerminalWorkspaceTab.closeActivePane()` 已记录最近关闭的 pane。
- 已新增 `TerminalWorkspaceTab.reopenClosedPane()`。
- reopen 会把最近关闭 pane 作为 sibling 重新挂回 pane tree。
- reopen 后 activePaneId 指向恢复的 pane。
- 已补充 close/reopen pane 模型测试。

## Functional Acceptance

- close active pane 后 closedPanes 记录最近关闭 pane。
- reopen closed pane 后 closedPanes 移除该 pane。
- reopen 后 pane tree 同时包含原剩余 pane 和恢复 pane。
- reopen 后 active pane 是恢复 pane。
- 该模型不表达进程恢复或 remote session restore。

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

- P2 close/undo close pane 的模型闭环可用。
- 后续 UI 接入无需重新定义 closed pane stack 行为。

## Risks / Follow-ups

- 当前 reopen 只恢复 pane 启动意图，不恢复 shell process。
- 后续如需更复杂的恢复位置，应扩展 closed pane record，而不是恢复进程状态。
