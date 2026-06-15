# T-375 Command Action Search Remaining Unavailable Feedback

## Goal

让 action search 对剩余不能直接执行的状态给出明确反馈，并保持不向 shell 写入。

## Scope

- 从 action search 搜索并选择 `reopen closed pane` 但没有最近关闭 pane 时展示明确反馈。
- 从 action search 搜索并选择 `apply theme` 时展示需要先选择主题预设的反馈。
- 增加 widget regression，确认这两个动作不再落入默认兜底文案。
- 确认执行这些不可用动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不实现 closed pane 的真实恢复；该路径由 T-376 覆盖。
- 不实现携带 `themeId` 的 action search 输出。
- 不直接应用某个 terminal theme preset。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-373-command-action-search-clear-search-dispatch.md`
- `docs/tasks/command-center/T-374-command-action-search-block-actions-unavailable-feedback.md`

## Functional Acceptance

- action search 搜索 `reopen closed pane` 且没有最近关闭 pane 时显示 `No recently closed pane is available.`。
- action search 搜索 `apply theme` 后按 `Enter` 显示 `Apply theme requires choosing a theme preset.`。
- 执行动作不向当前 shell 写文本。
- 这两个 action 不再显示泛化的 `This action still opens from the command menu.`。
- 后续接入真实状态或参数化输出时，可替换为真实执行路径。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search explains unavailable remaining visual workspace actions without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 在 action search 中搜索 `reopen closed pane`，按 `Enter`。
- 在 action search 中搜索 `apply theme`，按 `Enter`。
- 确认出现明确的不可用反馈，terminal 没收到 action search 文案。

## Done When

- `reopen closed pane` 的空状态和 `apply theme` 都有明确 unavailable feedback。
- action search 对这两个动作有 widget regression。
- Command Bar lane 验证门包含该 regression。
- 可见 registry action 不再缺少 action search switch 分支，`openActionSearch` 除外。

## Risks / Follow-ups

- `reopen closed pane` 的真实恢复由 T-376 覆盖。
- `apply theme` 的真实执行仍需要 action search 支持选择具体 theme preset 或传递 `themeId`。
- `apply theme` 当前反馈是诚实阻塞，不代表真实产品能力已经完成。
