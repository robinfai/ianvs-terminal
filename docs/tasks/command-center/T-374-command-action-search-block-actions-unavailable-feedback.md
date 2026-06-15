# T-374 Command Action Search Block Actions Unavailable Feedback

## Goal

让 action search 在当前没有 active command block 时，对 block actions 给出明确不可用反馈，并保持不向 shell 写入。

## Scope

- 从 action search 搜索并选择 `copy block output` 时展示缺少 command block 的反馈。
- 同样覆盖 `reinput block command` 和 `rerun block command`。
- 增加 widget regression，确认这三条 block action 不再落入默认兜底文案。
- 确认执行这些不可用动作不写当前 pty。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不实现 active command block selection 状态。
- 不执行 block output copy、re-input 或 rerun。
- 不改变 CommandBlockActionReducer 的 domain 行为。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-373-command-action-search-clear-search-dispatch.md`

## Functional Acceptance

- action search 搜索三条 block action 后按 `Enter` 都显示 `No command block is selected.`。
- 执行动作不向当前 shell 写文本。
- 这些 action 不再显示泛化的 `This action still opens from the command menu.`。
- 后续接入 active block 时可替换为真实 CommandBlockActionReducer 执行路径。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search explains unavailable command block actions without shell write"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
```

## Manual QA

- 在没有选中 command block 的状态下打开 action search。
- 分别搜索 `copy block output`、`reinput block command`、`rerun block command`，按 `Enter`。
- 确认出现明确的缺少 command block 反馈，terminal 没收到 action search 文案。

## Done When

- 三条 block action 都有明确 unavailable feedback。
- action search 对 block action unavailable 状态有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- block action 的真实执行仍需要 active command block selection 状态。
- reopen closed pane 的真实恢复由 T-376 覆盖；apply theme 的真实执行仍需要 theme preset 参数化流程。
