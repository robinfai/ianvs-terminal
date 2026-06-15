# T-387 Selected Block Review Entrypoint

## Goal

让 selected block action sheet 可以从当前 block 打开只读 Review / Instant Replay workspace。

## Scope

- 在 selected block action sheet 增加 `Open in review`。
- 复用 `CommandBlockActionReducer.openReviewEntrypoint`。
- 复用 T-385 的 `CommandReviewEntrypointResolver` 和 target frame / target row workspace 定位。
- Review workspace 继续使用只读 input controller，不写 live shell。
- 增加 widget regression 覆盖 selected block 入口、workspace 打开、target frame 定位和无 shell 写入。

## Non-goals

- 不实现 diff review。
- 不改变 action search 的 review entrypoint 行为。
- 不新增 Agent / AI review。
- 不改变 selected block 来源和持久化策略。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_context_chips.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-380-selected-block-context-actions.md`
- `docs/tasks/command-center/T-381-selected-block-copy-command-actions.md`
- `docs/tasks/command-center/T-382-selected-block-scoped-search.md`
- `docs/tasks/command-center/T-385-command-action-search-review-entrypoint.md`
- `docs/tasks/command-center/T-386-selected-block-save-output.md`

## Functional Acceptance

- 点击 `Block <command>` chip 打开 action sheet 后，可以选择 `Open in review`。
- 当前 selected block 有 output range 且 replay store 有覆盖该 range 的 frame 时，打开 Instant Replay workspace。
- workspace 标题标记 `Review: <command>`，并定位到 resolver 给出的 target frame。
- 该 action 不写 shell，不复用 live terminal 的可写 input controller。
- 没有 output range 或没有 replay frame 时，显示明确 unavailable feedback。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "selected block chip can open block output in review without shell write"
flutter test test/widget_test.dart --plain-name "selected block chip"
```

## Manual QA

- 运行一个产生输出的失败命令。
- 点击 `Last exit` chip，再点击 `Block <command>` chip。
- 选择 `Open in review`。
- 确认打开 Instant Replay workspace，标题包含 `Review: <command>`。
- 确认 timeline 定位到该 block 输出附近。
- 在 review workspace 中尝试输入，确认不会写入 live shell。

## Done When

- selected block sheet 显示 review entrypoint 入口。
- review entrypoint 能定位到 selected block 的 replay target frame。
- Command Bar lane 验证门包含 selected block review regression。

## Risks / Follow-ups

- diff review 仍保持 disabled / future extension。
- 鼠标点击 scrollback 行选择任意 block 仍待实现。
