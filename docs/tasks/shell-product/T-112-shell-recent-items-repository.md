# T-112 Shell Recent Items Repository

## Goal

补齐 P3 recent commands / recent directories 的本地持久化边界，让 recent items 可以独立保存、读取和 corrupt repair。

## Scope

- `example/lib/features/productivity/shell_productivity_models.dart`
- `example/lib/features/productivity/shell_recent_items_repository.dart`
- `example/test/productivity/shell_recent_items_repository_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入真实 shell integration event stream
- 不接 command palette picker UI
- 不启动 new tab/split
- 不同步云端或远程目录
- 不记录 remote/SSH context

## Current Progress

- `ShellRecentCommandEntry` 已支持 JSON serialization。
- `ShellRecentDirectoryEntry` 已支持 JSON serialization。
- `ShellRecentItemsState` 已支持 JSON serialization。
- 已新增 `ShellRecentItemsRepository`。
- recent items 文件路径为 `flutterm_recent_items.json`。
- 缺失文件返回默认空状态。
- corrupt 文件会 quarantine 并写入 repaired defaults。
- 已补充 missing、roundtrip、corrupt repair 测试。

## Functional Acceptance

- recent commands/directories 可以本地落盘和读取。
- 缺失文件不影响启动路径。
- corrupt 文件有 quarantine 和 repaired defaults。
- repository 不保存 remote/SSH context。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/productivity/shell_recent_items_repository_test.dart
flutter analyze
```

## Manual QA

本任务只新增 repository，不接 UI；无需人工 UI 验收。

## Done When

- P3 recent items persistence 边界可复用。
- 后续 picker UI 和 shell integration reducer 可以复用该 repository。

## Risks / Follow-ups

- 后续需要定义隐私设置和清理策略。
- 后续需要把 repository 接入 session/pane scoped recent items lifecycle。
