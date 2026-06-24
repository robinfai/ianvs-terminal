# T-306 Global Command History Repository

## Goal

建立 local-first global command history 的持久化和安全 fallback。

## Scope

- 设计 command history repository。
- 支持 JSON roundtrip、limit trimming、session-local 与 global merge。
- 对损坏文件提供安全 fallback，不阻塞 app 启动。
- 为 search index 提供全局历史来源。

## Non-goals

- 不做 cloud sync。
- 不保存 remote / SSH / SFTP / serial context。
- 不实现 search overlay UI。
- 不执行或发送任何命令。
- 不绕过 privacy filter；保存前过滤由 `T-307` 接入。

## Files In Scope

- `example/lib/features/command_center/global_command_history_repository.dart`
- `example/test/command_center/global_command_history_repository_test.dart`

## Functional Acceptance

- history 可保存和读取。
- 损坏文件不会导致启动失败，并返回空历史或修复后的安全 fallback。
- 超过 limit 时保留最新可用记录。
- session-local 与 global history 的 merge 规则明确且有测试。
- repository 不保存与 v1 无关的 remote/cloud 字段。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/global_command_history_repository_test.dart
```

## Manual QA

人工检查测试临时文件不包含敏感 fixture；无需 UI QA。

## Done When

- Search index 可读取 global history。
- JSON roundtrip、corrupt fallback 和 limit trimming 有测试。
- repository 保持 local-first。

## Risks / Follow-ups

- 写入频率需要 batching，避免频繁磁盘写。
- 敏感命令过滤由 `T-307` 强制接入后才能用于真实保存路径。
