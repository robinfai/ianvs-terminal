# T-383 Command Action Search Block Scoped Search

## Goal

让 action search 也能从最近 command block 打开 scoped search。

## Scope

- 新增 `searchWithinBlock` terminal action id 和 registry descriptor。
- action search 索引显示 `Search Within Block`。
- 选择该 action 时复用 `CommandBlockActionReducer.searchWithinBlock`。
- 复用 T-382 的 scoped search dispatch 和 output range 过滤。
- 增加 widget regression 覆盖 action search 入口、范围过滤和无 shell 写入。

## Non-goals

- 不改变 selected block sheet 行为。
- 不改变 native terminal search API。
- 不实现 save output 或 review entrypoint。
- 不改变 active block 选择策略，仍使用当前 session 最近 command block。

## Files In Scope

- `example/lib/features/shell/shell_action_registry.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-378-command-action-search-block-action-dispatch.md`
- `docs/tasks/command-center/T-382-selected-block-scoped-search.md`

## Functional Acceptance

- action search 输入 `search within block` 后可以选择对应 action。
- 当前 session 有最近 command block 时，该 action 打开 shell search bar。
- 输入查询后，只有最近 command block output range 内的 matches 参与计数和跳转。
- 该 action 不写 shell。
- 当前没有 command block 时，仍走 `No command block is selected.` fallback。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open scoped search for an active command block"
flutter test test/widget_test.dart --plain-name "action search"
flutter test test/widget_test.dart --plain-name "selected block chip opens scoped search within block output"
```

## Manual QA

- 在 shell integration 可用的 session 中运行一个产生输出的命令。
- 打开 action search，搜索 `search within block` 并执行。
- 在 search bar 输入一个全 scrollback 多处出现、但最近 block 内只有少数命中的词。
- 确认计数和跳转只落在最近 block 输出范围内。
- 在新 session 或没有 block 的状态下重复该 action，确认只显示 unavailable feedback。

## Done When

- action search 有 block scoped search 入口。
- action search scoped search 复用 T-382 的 range 过滤。
- Command Bar lane 验证门包含 action search scoped search regression。

## Risks / Follow-ups

- save output 已由 T-384 覆盖；review entrypoint 仍需要独立 action search dispatch。
