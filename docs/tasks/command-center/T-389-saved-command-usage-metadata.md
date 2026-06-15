# T-389 Saved Command Usage Metadata

## Goal

在 action search 实际插入 saved command 后，更新该命令的 `useCount` 和 `lastUsedAt`。

## Scope

- 为 saved command document 增加按 id 标记使用的模型方法。
- 让 action search overlay 在 saved command selection 时可输出完整 item。
- ShellScreen 通过可注入的 saved command repository 加载和保存 saved command document。
- saved command 成功写入 terminal 后递增 `useCount`，并写入 `lastUsedAt`。
- read-only、空命令或被策略阻止的写入不计 usage。

## Non-goals

- 不新增 saved command 创建、编辑、删除 UI。
- 不改变 saved command 排序公式，只补齐排序所需的真实使用数据。
- 不让 saved command 自动执行。
- 不绕过 multiline paste policy 或 read-only policy。

## Files In Scope

- `example/lib/features/command_center/saved_command_repository.dart`
- `example/lib/features/command_center/command_action_search_overlay.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_models.dart`
- `example/lib/features/shell/shell_screen_state_clipboard.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/lib/features/shell/shell_screen_state_terminal_workspace.dart`
- `example/test/command_center/saved_command_repository_test.dart`
- `example/test/command_center/command_action_search_overlay_test.dart`
- `example/test/widget_test.dart`

## Functional Acceptance

- saved command document 可以按 id 生成 usage-updated document。
- 命中 id 的 entry 会递增 `useCount` 并设置 `lastUsedAt`。
- 未命中 id 时 document 保持不变。
- overlay 仍支持旧的 command text 回调，同时可向 ShellScreen 输出完整 saved command item。
- ShellScreen action search 插入 saved command 后会保存 usage metadata。
- usage update 只在 terminal 写入成功后发生。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test \
  test/command_center/saved_command_repository_test.dart \
  test/command_center/command_action_search_overlay_test.dart \
  test/command_center/command_action_search_shell_wiring_test.dart
flutter test test/widget_test.dart --plain-name "action search updates saved command usage after insert"
flutter test test/widget_test.dart --plain-name "action search"
```

## Manual QA

- 预置或创建一条 saved command。
- 从 action search 搜索并插入该 saved command。
- 确认文本只插入，不自动执行。
- 重新打开 action search，确认该 saved command 仍可搜索。
- 检查本地 saved command JSON 中对应 entry 的 `useCount` 增加，`lastUsedAt` 写入。
- 在 read-only 下尝试插入，确认 terminal 不写入，usage 不增加。

## Done When

- saved command 使用统计由真实 action search insert 路径更新。
- 排序所需的 `useCount` / `lastUsedAt` 不再只是静态字段。
- Command Bar lane 验证门包含 usage metadata regression。

## Risks / Follow-ups

- saved command 创建、编辑、删除 UI 仍待后续任务。
- usage metadata 当前仅记录本地使用，不做 cloud/team sync。
