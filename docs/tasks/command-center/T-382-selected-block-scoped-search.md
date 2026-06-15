# T-382 Selected Block Scoped Search

## Goal

让 selected block action sheet 支持在当前 command block 输出范围内搜索。

## Scope

- 在 selected block action sheet 增加 `Search within block`。
- 复用 `CommandBlockActionReducer.searchWithinBlock` 和 scoped search intent。
- 打开 shell search bar 时记录当前 block output range。
- 搜索结果在 scoped output range 内过滤后再计数、显示和跳转。
- 关闭搜索或重新打开普通搜索时清除 scoped range。
- 增加 widget regression 覆盖 block 范围过滤和无 shell 写入。

## Non-goals

- 不改变 native terminal search API。
- 不实现 save output 或 review entrypoint。
- action search 里的 search-within-block 由 T-383 继续扩展。

## Files In Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_state_context_chips.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/lib/features/shell/shell_screen_state_search_completion.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-380-selected-block-context-actions.md`
- `docs/tasks/command-center/T-381-selected-block-copy-command-actions.md`

## Functional Acceptance

- 点击 `Block <command>` chip 打开 action sheet 后，可以选择 `Search within block`。
- `Search within block` 打开 shell search bar，不写 shell。
- 输入查询后，只有 selected block output range 内的 matches 参与计数和跳转。
- 重新打开普通 search 后不保留 block scope。
- 关闭 search 后不保留 block scope。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "selected block chip opens scoped search within block output"
flutter test test/widget_test.dart --plain-name "selected block chip"
flutter test test/widget_test.dart --plain-name "shell search opens and scrolls to matches"
```

## Manual QA

- 运行一个包含多行输出的失败命令。
- 点击 `Last exit` chip，再点击 `Block <command>` chip。
- 选择 `Search within block` 并输入只在当前输出中出现的词。
- 再输入一个全 scrollback 里多处出现、但当前 block 中只有少数命中的词。
- 确认计数和跳转只落在当前 block 输出范围内。
- 关闭搜索后重新用普通快捷键打开搜索，确认恢复全 session 搜索。

## Done When

- selected block sheet 显示 scoped search 入口。
- shell search 能过滤 selected block output range。
- 验证门包含 scoped search regression。

## Risks / Follow-ups

- action search 里的 search-within-block 已由 T-383 覆盖。
- save output 和 review entrypoint 仍需要独立 action dispatch。
