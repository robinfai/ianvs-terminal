# T-081 Local Terminal Config Repository And Migration

## Goal

补齐 `LocalTerminalConfigDocument` 的独立 repository 与 legacy app preferences 迁移入口，使 P1 config foundation 从纯模型推进到可落盘、可修复、可迁移的基础设施。

## Scope

- `example/lib/features/config/local_terminal_config_repository.dart`
- `example/test/config/local_terminal_config_repository_test.dart`
- `docs/tasks/README.md`

## Non-goals

- 不替换现有 `ProfileRepository`
- 不替换现有 `AppPreferencesRepository`
- 不在启动流程中自动写入新配置文件
- 不实现完整 profile migration
- 不新增 SSH、remote、serial、SFTP 字段

## Current Progress

- 已新增 `LocalTerminalConfigRepository`。
- 新配置文件路径为 `ianvs_config.json`。
- 缺失新配置时返回 `null`，不破坏旧 profile/preferences fallback。
- corrupt config 会 quarantine 并写入 repaired defaults。
- 已新增 `LocalTerminalConfigMigration.fromLegacyAppPreferences()`，把旧 app preferences 的 default profile 和 appearance 映射到新 config。
- 已补充 repository roundtrip、corrupt repair 和 legacy migration 测试。

## Functional Acceptance

- `ianvs_config.json` 不存在时不会破坏现有启动路径。
- `ianvs_config.json` 可保存和读取 `LocalTerminalConfigDocument`。
- corrupt config 有 quarantine 和 repaired defaults。
- legacy app preferences 可迁移 defaultProfileId 和 appearance。
- 该任务不改变当前运行时实际配置来源。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/config/local_terminal_config_repository_test.dart
flutter analyze
```

## Manual QA

本任务不接入 runtime 启动路径；无需人工 UI 验收。

## Done When

- local config repository 可被后续 session bootstrap 任务接入
- legacy app preferences migration adapter 可用
- 相关 repository 测试通过

## Risks / Follow-ups

- 后续需要独立任务决定何时从旧 preferences 自动迁移到新 `ianvs_config.json`。
- 后续需要把 profile list migration 纳入新 config，当前只迁移 app-level defaults/appearance。
