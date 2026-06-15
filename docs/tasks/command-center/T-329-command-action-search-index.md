# T-329 Command Action Search Index

## Goal

建立 `/` action search 的纯逻辑搜索层，把内置 action 和 saved command 放进同一个可排序结果列表。

## Scope

- 新增 command action search item、result、match kind 和 selection intent。
- 支持 app action 的 title、subtitle、keywords 搜索。
- 支持 saved command 的 title、tag、command text 搜索。
- 空查询时 app action 优先，saved command 按 useCount 辅助排序。
- saved command 选择结果只表达 insert intent，不直接写 shell。

## Non-goals

- 不实现 `/` UI。
- 不实现 saved command 创建、编辑或删除 UI。
- 不把结果自动写入 terminal。
- 不执行 saved command。
- 不改变 read-only、paste confirmation 或 terminal input policy。

## Files In Scope

- `example/lib/features/command_center/command_action_search_index.dart`
- `example/test/command_center/command_action_search_index_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action 可以通过 title 或 keyword 命中。
- saved command 可以通过 title、tag 或 command text 命中。
- 结果区分 app action 和 saved command。
- saved command selection 是 `insertSavedCommand`，且 `writesToTerminalOnSelect` 为 false。
- limit 会约束返回结果数量。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_action_search_index_test.dart
```

## Manual QA

纯 search index 任务，无 UI QA。后续 `/` UI 接线时必须手测：

- `/` 只通过显式入口打开，不由普通文本触发。
- 选择 saved command 只插入，不自动执行。
- read-only 下 saved command insert 被阻止。
- 多行 saved command 仍走 paste policy。

## Done When

- `/` UI 可以复用同一个 action/saved command 搜索结果模型。
- saved command 搜索不会绕过 terminal 写入安全策略。
- action 与 saved command 的排序和 match 行为有测试。

## Risks / Follow-ups

- 尚未有 `/` overlay UI。
- 尚未接入 real ShellScreen 的 action registry。
- saved command useCount / lastUsedAt 仍需要在实际使用时更新。
