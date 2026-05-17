# T-099 Local Workspace Layout Repository

## Goal

补齐 P2 layout save/load 的独立 repository，让 local-only workspace layout 可以落盘、读取、corrupt repair，并与现有 runtime 启动路径解耦。

## Scope

- `example/lib/features/workspace/local_workspace_repository.dart`
- `example/test/workspace/local_workspace_repository_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P2_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 `ShellScreen`
- 不自动恢复 workspace
- 不恢复 shell process
- 不保存 remote/SSH session
- 不实现 layout template UI

## Current Progress

- 已新增 `LocalWorkspaceRepository`。
- layout 文件路径为 `flutterm_workspace_layout.json`。
- 缺失 layout 文件时返回 `null`。
- corrupt layout 会 quarantine 并写入 empty repaired layout。
- 已补充 missing、roundtrip、corrupt repair 测试。

## Functional Acceptance

- workspace layout 可独立落盘和读取。
- 缺失 layout 文件不影响现有启动路径。
- corrupt layout 有 quarantine 和 repaired empty state。
- repository 不表达 remote/SSH process restore。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/workspace/local_workspace_repository_test.dart
flutter analyze
```

## Manual QA

本任务只新增 repository，不接入 UI；无需人工 UI 验收。

## Done When

- P2 layout save/load 的 repository 层闭环可用。
- 后续 UI 接入可选择何时 save/restore，不需要重写文件层。

## Risks / Follow-ups

- 后续需要决定 layout restore 的触发时机。
- 后续需要加 schema version/migration。
