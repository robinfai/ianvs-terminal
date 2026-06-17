# T-312 Command Search Insert Execute Safety

## Goal

确保 `Ctrl-R` 搜索结果默认回填到 command input，不自动执行，并沿用既有多行输入安全语义。

## Scope

- 定义默认 insert command 的目标和 paste/multiline safety。
- 将 overlay selection intent 接入 command input path，而不是 hidden terminal focus。
- 确保默认回填不会绕过既有 shell safety policy。

## Non-goals

- 不让 `Enter` 默认执行命令。
- 不把显式执行定义为本轮 `Ctrl-R` 主流程验收项。
- 不绕过 read-only 或 paste confirmation。
- 不实现 search index 或 overlay 视觉。
- 不做自然语言自动识别。
- 不新增 Agent / AI execute path。

## Files In Scope

- `example/lib/features/command_center/command_search_intents.dart`
- `example/test/command_center/command_search_insert_execute_safety_test.dart`
- 必要的 `example/lib/features/shell/` input wiring

## Functional Acceptance

- `Enter` 插入到 command input 且不发送回车。
- hidden terminal focus 不能成为搜索结果插入目标。
- 多行结果进入既有 paste/multiline policy，但最终落点仍是 command input。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_search_insert_execute_safety_test.dart
```

## Manual QA

- 在真实 app 中运行几条命令。
- 打开 `Ctrl-R`，选择历史命令。
- 按 `Enter`，确认命令只回填到 command input、不执行。
- 确认隐藏 terminal focus 不会收到插入文本。
- 对多行结果确认仍出现或遵守 paste/multiline safety。

## Done When

- Search overlay 不会意外执行命令。
- 插入目标固定为 command input，且不会落到 hidden terminal focus。
- 单行和多行回填路径都有测试覆盖。
- 默认回填不会绕过既有安全策略。

## Risks / Follow-ups

- 快捷键和 terminal `Ctrl-R` 语义冲突需要在配置或文档中清楚表达。
- 如果后续恢复显式执行入口，需要单独定义快捷键、read-only 和 paste safety 责任链。
