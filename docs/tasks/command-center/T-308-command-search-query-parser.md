# T-308 Command Search Query Parser

## Goal

支持 command search 的文本和 filter prefix 解析。

## Scope

- 解析普通文本查询。
- 支持 `history:`、`block:`、`action:`、`cwd:`、`status:` 等 filter prefix。
- 输出统一 query model 供 search index 和 overlay 复用。

## Non-goals

- 不实现 fuzzy search 或 ranking。
- 不实现 UI。
- 不做自然语言自动识别。
- 不执行命令。
- 不做 Agent / AI 搜索。

## Files In Scope

- `example/lib/features/command_center/command_search_query_parser.dart`
- `example/test/command_center/command_search_query_parser_test.dart`

## Functional Acceptance

- raw query 被解析为 text 和 filters。
- 未知 prefix 保留为普通文本。
- 空白、连续空格和空查询稳定处理。
- quoted cwd 可被解析。
- parser 不依赖 Flutter widget 或 platform API。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_search_query_parser_test.dart
```

## Manual QA

纯 parser 任务，无需 UI QA。

## Done When

- Search index 和 overlay 共用同一个 query model。
- 已知 prefix、未知 prefix、quoted cwd 和空查询有测试。
- parser 不进行命令执行判断。

## Risks / Follow-ups

- 新 prefix 需要在 parser、index 和 overlay 中同步测试。
- `block:` filter 的实际数据由 command blocks 任务提供。
