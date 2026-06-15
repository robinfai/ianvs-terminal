# T-370 Command Action Search Paste Dispatch

## Goal

让 action search 能执行 `Paste`，复用现有 clipboard paste 行为，并确保只把剪贴板内容写入 shell。

## Scope

- 从 action search 搜索并选择 `paste` 时调用现有 `_pasteToSession`。
- 当前没有 active session 时展示 blocked intent。
- 增加 widget regression，确认 action search paste 只写入剪贴板文本。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 advanced paste 或 paste history 行为。
- 不改变 multiline paste confirmation 规则。
- 不改变 bracketed paste 或 paste mode 编码。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `paste` 后按 `Enter` 会读取剪贴板并写入 active shell。
- 写入内容等于剪贴板文本。
- action search 的查询文本不会被写入 shell。
- 没有 active session 时展示 `Paste requires an active session.`。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can paste clipboard text into shell"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 复制一段单行文本。
- 打开 action search，搜索 `paste`，按 `Enter`。
- 确认 terminal 只收到剪贴板文本，没有收到 action search 查询文本。

## Done When

- Paste 可以从 action search 执行。
- action search 对 paste 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- reopen closed pane 仍需要独立 action search dispatch 覆盖。
