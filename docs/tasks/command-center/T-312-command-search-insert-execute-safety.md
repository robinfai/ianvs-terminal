# T-312 Command Search Insert Execute Safety

## Goal

确保搜索结果默认插入，不自动执行，显式执行受安全策略保护。

## Scope

- 定义 insert command、explicit execute、read-only guard、paste/multiline safety。
- 将 overlay selection intent 接入 command input path，而不是 hidden terminal focus。
- 确保写入 shell 的路径仍经过既有 safety policy。

## Non-goals

- 不让 `Enter` 默认执行命令。
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
- `Cmd/Ctrl+Enter` 才产生显式执行。
- hidden terminal focus 不能成为搜索结果插入目标。
- read-only 下 explicit execute disabled，并给出 reason。
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
- 启用 read-only 后尝试显式执行，确认不可用。
- 对多行结果确认仍出现或遵守 paste/multiline safety。

## Done When

- Search overlay 不会意外执行命令。
- 插入目标固定为 command input，且不会落到 hidden terminal focus。
- 插入和显式执行路径都有测试覆盖。
- 所有发送到 shell 的路径经过安全策略。

## Risks / Follow-ups

- 快捷键和 terminal `Ctrl-R` 语义冲突需要在配置或文档中清楚表达。
- 后续 Command Bar 接入时必须复用同一 insert/execute safety。
