# T-328 Saved Command Repository

## Goal

建立 local-first saved command repository，为后续 `/` action search 和 saved command insert 提供安全数据基座。

## Scope

- 新增 saved command document、entry 和 repository。
- 使用 local JSON 文件 `ianvs_saved_commands.json`。
- 保存前 normalize、dedupe、limit。
- 复用 command history privacy filter，过滤明显敏感命令。
- 损坏文件 quarantine 后返回空文档。
- 输出 JSON 不包含 remote、cloud、sessionId 等 v1 外字段。

## Non-goals

- 不实现 saved command UI。
- 不实现 `/` action search UI。
- 不写 shell。
- 不实现 cloud sync、remote sync、团队共享或插件 saved commands。
- 不接入 Command Bar insert/execute。

## Files In Scope

- `example/lib/features/command_center/saved_command_repository.dart`
- `example/test/command_center/saved_command_repository_test.dart`

## Functional Acceptance

- saved command 可以保存并加载。
- entry 包含 id、title、command、cwd、tags、createdAt、updatedAt、useCount、lastUsedAt。
- blank / invalid entry 被忽略。
- 同 id entry 保留最新 updatedAt 版本。
- 超过 limit 时保留最新 entry。
- 敏感 command 不写入 saved command document。
- corrupt JSON 被隔离并恢复为空文档。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/saved_command_repository_test.dart
```

## Manual QA

纯 repository 任务，无 UI QA。后续 `/` action search 或 saved command insert 接线时必须手测：

- 保存命令后能从显式入口搜索。
- 插入 saved command 不自动执行。
- read-only 下不会写 shell。
- 多行 saved command 走 paste policy。

## Done When

- 后续 saved command UI 不需要重新定义本地文件格式。
- repository 行为有 roundtrip、privacy、dedupe、corrupt fallback 测试。
- v1 范围保持 local-only。

## Risks / Follow-ups

- 尚未有 clear/disable UI。
- 尚未和 command search/action search 合并展示。
- useCount / lastUsedAt 后续需要在实际使用 saved command 时更新。
