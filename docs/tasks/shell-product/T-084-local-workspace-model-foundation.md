# T-084 Local Workspace Model Foundation

## Goal

建立 P2 的本地 workspace / tab / pane tree 数据模型，先覆盖 split、close active pane、close/reopen tab 和 empty state 等核心行为，为后续 `ShellScreen` 分步接入打基础。

## Scope

- `example/lib/features/workspace/local_workspace_models.dart`
- `example/test/workspace/local_workspace_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P2_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 `ShellScreen`
- 不改变现有 pane UI 行为
- 不实现 layout persistence
- 不恢复外部进程状态
- 不新增 SSH、remote、serial、SFTP workspace 概念

## Current Progress

- 已新增 `TerminalWorkspace`。
- 已新增 `TerminalWorkspaceTab`。
- 已新增 `TerminalPaneNode`。
- 已新增 `TerminalPaneSessionIntent`，只表达本地 session 启动意图。
- 已实现 add tab、close active tab、reopen closed tab。
- 已实现 split active pane 和 close active pane 的纯模型行为。
- 已补充 empty state、split、focus fallback、reopen closed tab 的模型测试。

## Functional Acceptance

- workspace 可以从 empty state 新增 tab。
- split active pane 后 pane tree 保留原 pane 并聚焦新 pane。
- close active pane 后聚焦剩余 pane。
- close last tab 后 workspace 进入 empty state。
- reopen closed tab 可以恢复最近关闭的 tab。

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

- P2 的 workspace/tab/pane 基础模型可被后续 UI 和 persistence 任务复用。
- 本地模型不包含 remote/SSH/session process restore 概念。

## Risks / Follow-ups

- 后续需要实现 layout save/load。
- 后续需要实现 pane resize/move/swap/zoom。
- 后续需要把现有 `ShellScreen` pane 状态分步迁移到该模型。
