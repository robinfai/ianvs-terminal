# T-104 Local Terminal Scrollback Exporter

## Goal

补齐 P5 scrollback export 的文件写出边界，让已准备好的 plain text、ANSI text 或 JSON payload 可以按 policy 写出到本地文件。

## Scope

- `example/lib/features/visual/local_terminal_scrollback_exporter.dart`
- `example/test/visual/local_terminal_scrollback_exporter_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不扫描真实 terminal scrollback
- 不接 renderer
- 不实现 save dialog
- 不接 command output selection
- 不实现远程文件导出

## Current Progress

- 已新增 `LocalTerminalScrollbackExport`。
- 已新增 `LocalTerminalScrollbackExporter.write()`。
- export 支持 plain text、ANSI text、JSON 后缀。
- JSON export 可按 policy 包含 metadata。
- disabled export policy 会拒绝写出。
- 已补充 plain text、JSON metadata 和 disabled policy 测试。

## Functional Acceptance

- plain text export 写成 `.txt`。
- ANSI export 预留 `.ansi`。
- JSON export 写成 `.json` 并可包含 metadata。
- disabled policy 不允许写出。
- exporter 不依赖 renderer 或 remote 文件系统。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/visual/local_terminal_scrollback_exporter_test.dart
flutter analyze
```

## Manual QA

本任务只新增文件 exporter，不接 UI；无需人工 UI 验收。

## Done When

- P5 scrollback export 的本地文件写出边界可复用。
- 后续 UI/runtime 接入只需要提供 payload 和目标目录。

## Risks / Follow-ups

- 后续需要实现真实 scrollback capture。
- 后续需要处理文件名冲突和 save dialog。
