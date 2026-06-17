# T-309 Command Search Index Ranking

## Goal

建立 command search index 和 ranking。

## Scope

- 支持 prefix 和 fuzzy matching。
- Ranking 考虑 recency、cwd proximity、status 和 frequency。
- 支持 `CommandSearchQuery` 的 filters。
- 进入 index 的记录如果带有 command invocation / block locator metadata，索引和结果
  视图都不能把这些关联字段丢掉。
- 提供 10k 条 history fixture 的性能基线。

## Non-goals

- 不实现 overlay widget。
- 不执行命令。
- 不保存 history。
- 不做 Agent / AI 结果。
- 不做跨设备或云端搜索。

## Files In Scope

- `example/lib/features/command_center/command_search_index.dart`
- `example/test/command_center/command_search_index_test.dart`

## Functional Acceptance

- prefix 和 fuzzy 查询可命中历史命令。
- 当前 cwd 结果提权。
- status filter 能区分成功、失败和未知。
- 高频命令可参与排序，但不能盖过明显更近的精确命中。
- 带 block locator metadata 的记录在进入 index 和返回结果时仍可供后续 `查看命令块`
  routing 使用。
- 10k 条 fixture 的查询保持可交互。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_search_index_test.dart
```

## Manual QA

纯 index 任务，无需 UI QA。

## Done When

- Overlay 可直接消费 ranked results。
- ranked results 保留 command invocation / block locator metadata，不要求 controller
  二次猜测 block 关联。
- ranking、filter 和性能基线有测试。
- search index 不拥有 history persistence。

## Risks / Follow-ups

- 大 history 性能可能需要后续优化；最终阈值写入 `T-322` 验证门。
- Ranking 权重需要保持简单，避免难以解释的搜索结果。
