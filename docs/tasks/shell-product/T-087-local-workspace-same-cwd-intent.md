# T-087 Local Workspace Same-CWD Intent

## Goal

在 P2 workspace model 中补齐 same-cwd new tab / split 的本地 session intent 继承能力，让后续 UI 可以从 active pane 派生新本地 session，而不把 shell integration 作为硬依赖。

## Scope

- `example/lib/features/workspace/local_workspace_models.dart`
- `example/test/workspace/local_workspace_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P2_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入实际 shell integration cwd tracker
- 不接入 `ShellScreen`
- 不启动真实 PTY session
- 不恢复远程连接
- 不实现 profile fallback UI

## Current Progress

- `TerminalWorkspaceTab.activeSessionIntent` 已可读取 active pane 的 local session intent。
- `TerminalWorkspace.addTabFromActivePane()` 已支持从 active pane 派生新 tab。
- `TerminalWorkspace.splitActivePaneFromActiveCwd()` 已支持从 active pane 派生 split。
- 调用方必须提供 fallback intent，供 cwd/profile 不可用时降级使用。
- 已补充 new tab/split inherit cwd 的模型测试。

## Functional Acceptance

- active pane 有 cwd 时，新 tab/split 继承该 cwd。
- active pane 有 profile intent 时，新 tab/split 继承该 profile。
- active pane intent 不可用时，调用方 fallback intent 可用。
- same-cwd 模型不依赖远程 session 或 shell process restore。

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

- P2 same-cwd new tab/split 的模型语义可复用。
- 后续 UI 接入只需把 shell integration cwd tracker 输出转成 `TerminalPaneSessionIntent`。

## Risks / Follow-ups

- 后续需要定义 shell integration disabled 时的 UI 诊断文案。
- 后续需要把 active pane cwd tracker 与该模型连接。
