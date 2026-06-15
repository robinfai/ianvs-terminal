# T-369 Command Action Search Duplicate Current CWD Dispatch

## Goal

让 action search 能执行 `Duplicate current cwd`，复用现有 duplicate current directory 行为，并只向新 tab 写入预期的 `cd <cwd>`。

## Scope

- 从 action search 搜索并选择 `duplicate current cwd` 时创建新 tab。
- 复用当前 pane 的 shell integration `currentDirectory`。
- 向新 tab 写入 `cd <cwd>`，不把 action search 文案写入 shell。
- 增加 widget regression，确认新 tab 被创建、选中，并只收到预期 cwd 命令。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 current directory 的 shell hook 解析。
- 不改变 path quoting 规则。
- 不改变 new tab 或 reopen closed tab 行为。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `duplicate current cwd` 后按 `Enter` 会创建第二个 tab。
- 新 tab 被选中。
- 当前 pane 有 cwd 时，新 tab 收到且只收到 `cd <cwd>`。
- 当前 pane 没有 cwd 时展示 unavailable 文案，不创建误导性 shell 输入。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can duplicate current cwd into new tab"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 让 shell integration 记录当前目录。
- 打开 action search，搜索 `duplicate current cwd`，按 `Enter`。
- 确认创建新 tab、焦点进入新 tab，并且新 tab 只收到 `cd <cwd>`。

## Done When

- Duplicate current cwd 可以从 action search 执行。
- action search 对 duplicate current cwd 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- reopen closed pane 仍需要独立 action search dispatch 覆盖。
