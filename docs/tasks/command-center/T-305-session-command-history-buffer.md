# T-305 Session Command History Buffer

## Goal

建立 session-local command history buffer。

## Scope

- 记录当前 session 内完成的命令。
- 支持 newest-first、去重、limit trimming、cwd/status metadata。
- 保留 command invocation / block locator metadata，供后续 block-backed filtering 和
  `Ctrl-R -> 查看命令块` routing 使用。
- 为 `Ctrl-R` overlay 提供不依赖落盘的即时历史来源。

## Non-goals

- 不做 global history 落盘。
- 不做 search overlay UI。
- 不做 Agent / AI、remote / SSH、cloud sync 或协作。
- 不重写 terminal renderer。
- 不改变普通输入默认发给 shell 的行为。

## Files In Scope

- `example/lib/features/command_center/session_command_history_buffer.dart`
- `example/test/command_center/session_command_history_buffer_test.dart`

## Functional Acceptance

- `command_finished` 后可立即检索该命令。
- 同 session 内结果按 newest-first 返回。
- 空命令或只有空白的命令不入库。
- 同 command/cwd 的重复记录按最新一次合并。
- 已有关联的 command invocation / block locator metadata 不会在入 buffer 或去重时丢失。
- 不同 session 的 history 相互隔离。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/session_command_history_buffer_test.dart
```

## Manual QA

纯模型任务，不改变 UI 或 runtime 行为；无需人工 UI QA。

## Done When

- `Ctrl-R` overlay 可以先消费 session-local history。
- session-local history 记录仍保留可回到 command block 的 locator metadata。
- buffer 的去重、排序和 session 隔离有单元测试覆盖。
- buffer 不依赖文件系统。

## Risks / Follow-ups

- 全局落盘由 `T-306` 处理。
- privacy filter 由 `T-307` 接入，当前任务不决定敏感命令策略。
