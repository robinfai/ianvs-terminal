# T-378 Command Action Search Block Action Dispatch

## Goal

让 action search 在当前 session 有 command lifecycle 和 prompt mark 时，能直接执行最近 command block 的 copy output、re-input 和 rerun。

## Scope

- 从当前 session 的 command lifecycle 与 shell integration prompt marks 推导最近 command block。
- `copy block output` 选择该 block 的 output range 并复制真实 terminal 内容。
- `reinput block command` 将 block command 写回当前 shell，但不自动执行。
- `rerun block command` 将 block command 加换行写回当前 shell。
- 保留没有可用 block 时的 `No command block is selected.` 反馈。
- 增加 widget regressions 覆盖 copy output、re-input、rerun 和 unavailable fallback。
- 将 regressions 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不新增显式 selected block UI。
- 不改变 CommandBlockActionReducer 的 domain 行为。
- 不实现 save output 或 review entrypoint 的 action search 执行路径。
- scoped search 由 T-383 继续扩展。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `copy block output` 并选择后，复制最近 command block 的 output rows。
- action search 搜索 `reinput block command` 并选择后，向 shell 写入原命令文本。
- action search 搜索 `rerun block command` 并选择后，向 shell 写入原命令文本和换行。
- 当前没有 command block 时，三条 action 仍显示 `No command block is selected.`，且不写 shell。
- copy block output 不把 overlay 文案、prompt 或 command input 混入 clipboard。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can copy block output without shell write"
flutter test test/widget_test.dart --plain-name "action search can reinput and rerun an active command block"
flutter test test/widget_test.dart --plain-name "action search explains unavailable command block actions without shell write"
```

## Manual QA

- 在 shell integration 可用的 session 中运行一个产生输出的命令。
- 打开 action search，搜索 `copy block output`，确认 clipboard 是命令输出。
- 再搜索 `reinput block command`，确认命令文本回到 shell 且未执行。
- 再搜索 `rerun block command`，确认命令被重新发送执行。
- 在新 session 或没有 block 的状态下重复三条 action，确认只显示 unavailable feedback。

## Done When

- 三条 block action 在有最近 block 时从 action search 真实执行。
- 无 block 状态仍保持明确反馈。
- Command Bar lane 验证门包含 block action dispatch regressions。

## Risks / Follow-ups

- 当前 active block 取最近 block；显式 selected block UI 接入后应优先使用用户选择。
- prompt mark 与 lifecycle 缺失或顺序异常时仍会降级为 unavailable feedback。
- scoped search 已由 T-383 覆盖。
- save output 和 review entrypoint 仍需要独立 action search dispatch。
