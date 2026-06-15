# T-347 Command Action Search Select Command Output Dispatch

## Goal

让 action search 能执行高频非写入入口 `Select command output`，从 action search 直接选择最近一次命令输出，同时保持动作本身不写 shell。

## Scope

- 从 action search 搜索并选择 `Select command output` 时复用现有 command output selection 逻辑。
- 增加 widget regression，确认选择后可通过既有 `Copy selection` 复制到最近命令输出。
- 确认 action search 执行该动作不写 shell。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 shell integration prompt mark 生成或降级规则。
- 不改变 copy selection、copy command output 或 clipboard 行为。
- 不完成所有 action search action dispatch。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- action search 搜索 `select command output` 后按 `Enter` 会选择最近一次 prompt marks 之间的输出。
- 后续 `Copy selection` 得到选中的 command output 文本。
- 执行 select command output 本身不向 shell 写入。
- command menu 的 select command output 入口仍沿用既有行为。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can select command output without shell write"
flutter test test/widget_test.dart --plain-name "command selection selects the last command output"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 运行一个有输出的命令，再打开 action search，搜索 `select command output` 并执行。
- 使用 Copy selection，确认剪贴板只包含命令输出，不包含 prompt 或 overlay 文本。
- 确认执行该动作不写 shell；prompt marks 缺失时不产生错误写入。

## Done When

- Select command output 可以从 action search 执行。
- action search 对 select command output 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- 该动作依赖 shell integration prompt marks；缺 mark 时应继续保持 no-op / focus restore 行为。
- 后续仍需将更多 action search app actions 接到共享 dispatch。
