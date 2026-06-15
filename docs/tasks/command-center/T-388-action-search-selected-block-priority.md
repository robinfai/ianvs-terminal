# T-388 Action Search Selected Block Priority

## Goal

让 action search 的 block actions 优先作用于用户显式选中的 command block。

## Scope

- action search 查找 active block 时先读取当前 session 的 selected block id。
- selected block 仍有效且属于当前 session 时，copy/save/search/reinput/rerun/review 等 block actions 都使用 selected block。
- selected block 缺失、失效或不属于当前 session 时，回退到最近 command block。
- 增加 widget regression 覆盖 selected block 与 newest block 不同时的 action search copy output。

## Non-goals

- 不新增鼠标点击 scrollback 行选择任意 block。
- 不改变 selected block chip 的来源和显示策略。
- 不改变 action search 没有 selected block 时的最近 block fallback。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-378-command-action-search-block-action-dispatch.md`

## Functional Acceptance

- 当前 session 已有 selected block 时，action search block actions 使用 selected block。
- selected block 与最新 block 不同时，`copy block output` 复制 selected block output。
- 该行为不写 shell。
- 没有 selected block 时，action search 继续使用最近 command block。
- selected block id 失效时，action search 安全回退最近 command block。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search prefers selected block over newest block without shell write"
flutter test test/widget_test.dart --plain-name "action search"
```

## Manual QA

- 运行一个失败命令，再运行一个成功命令。
- 点击 `Last exit` chip，让失败 block 成为 selected block。
- 打开 action search，执行 `copy block output`。
- 确认复制的是失败 block 输出，而不是最新成功命令输出。
- 清除或切换 selected block 后，确认 action search 回退最新 block。

## Done When

- action search block actions 优先 selected block。
- 最近 block fallback 保持可用。
- Command Bar lane 验证门包含 selected block priority regression。

## Risks / Follow-ups

- 鼠标点击 scrollback 行选择任意 block 仍待实现。
