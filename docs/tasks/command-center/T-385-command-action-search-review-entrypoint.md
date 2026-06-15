# T-385 Command Action Search Review Entrypoint

## Goal

让 action search 可以从最近 command block 打开只读 Review / Instant Replay workspace。

## Scope

- 新增 `openInReview` terminal action id 和 registry descriptor。
- action search 索引显示 `Open In Review`。
- 选择该 action 时复用 `CommandBlockActionReducer.openReviewEntrypoint`。
- 复用 `CommandReviewEntrypointResolver` 从 command block output range 找 replay target frame。
- Instant Replay workspace 支持可选 target frame / target row，打开时定位到 block 输出附近。
- Review workspace 继续使用只读 input controller，不写 live shell。
- 增加 widget regression 覆盖 action search 入口、workspace 打开、target frame 定位和无 shell 写入。

## Non-goals

- 不实现 diff review。
- 不改变普通 Instant Replay shortcut 的起始帧策略。
- 不改变 selected block sheet 行为。
- 不让 review workspace 写入 live terminal。
- 不新增 Agent / AI review。

## Files In Scope

- `example/lib/features/shell/shell_action_registry.dart`
- `example/lib/features/shell/shell_command_action_search_adapter.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_models.dart`
- `example/lib/features/shell/shell_screen_instant_replay.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-378-command-action-search-block-action-dispatch.md`
- `docs/tasks/command-center/T-383-command-action-search-block-scoped-search.md`
- `docs/tasks/command-center/T-384-command-action-search-save-block-output.md`

## Functional Acceptance

- action search 输入 `open in review` 后可以选择对应 action。
- 当前 session 有最近 command block 且 replay store 有覆盖 output range 的 frame 时，打开 Instant Replay workspace。
- workspace 标题标记 `Review: <command>`，并定位到 resolver 给出的 target frame。
- 该 action 不写 shell，不复用 live terminal 的可写 input controller。
- 当前没有 command block、没有 output range 或没有 replay frame 时，显示明确 unavailable feedback。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can open block output in review without shell write"
flutter test test/widget_test.dart --plain-name "action search explains unavailable command block actions without shell write"
flutter test test/widget_test.dart --plain-name "action search"
```

## Manual QA

- 在 shell integration 可用的 session 中运行一个产生输出的失败命令。
- 打开 action search，搜索 `open in review` 并执行。
- 确认打开 Instant Replay workspace，标题包含 `Review: <command>`。
- 确认 timeline 定位到该 block 输出附近。
- 在 review workspace 中尝试输入，确认不会写入 live shell。
- 在没有 replay frame 的新 session 中重复该 action，确认只显示 unavailable feedback。

## Done When

- action search 有 review entrypoint 入口。
- review entrypoint 能定位到最近 command block 的 replay target frame。
- Command Bar lane 验证门包含 action search review regression。

## Risks / Follow-ups

- selected block sheet 的 review entrypoint 已由 T-387 覆盖。
- diff review 仍保持 disabled / future extension。
