# T-085 Local Workspace Layout Serialization

## Goal

给 P2 workspace model 增加 local-only layout serialization，让后续 layout save/load 只恢复本地 pane topology 和 session 启动意图，不恢复远程连接或外部进程状态。

## Scope

- `example/lib/features/workspace/local_workspace_models.dart`
- `example/test/workspace/local_workspace_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P2_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入文件 repository
- 不接入 `ShellScreen`
- 不恢复 shell process 状态
- 不保存 SSH、remote、SFTP、serial session
- 不实现 layout template UI

## Current Progress

- `TerminalWorkspace` 已支持 `toJson()` / `fromJson()`。
- `TerminalWorkspaceTab` 已支持 `toJson()` / `fromJson()`。
- `TerminalPaneNode` 已支持 leaf/split tree serialization。
- layout 只保存 pane topology、active tab/pane、closed tabs/panes 和 local session intent。
- workspace layout 反序列化会拒绝 remote-only 字段。
- 已补充 layout roundtrip 和 forbidden remote field 测试。

## Functional Acceptance

- local workspace layout 可以 roundtrip。
- split direction、active tab、pane ids 和 cwd intent 在 roundtrip 后保留。
- 出现 remote-only layout 字段时抛出格式错误。
- layout schema 不表达远程连接或进程恢复。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/workspace/local_workspace_models_test.dart
flutter analyze
```

## Manual QA

本任务只新增纯模型 serialization，不接入 UI；无需人工 UI 验收。

## Done When

- workspace layout save/load 的模型层闭环可用。
- 后续 repository 或 UI 接入无需重做 layout schema。

## Risks / Follow-ups

- 后续需要加 repository 来实际读写 layout 文件。
- 后续需要加 schema version 与 migration。
- 后续需要实现 pane resize/move/swap/zoom 的 serialization 细节。
