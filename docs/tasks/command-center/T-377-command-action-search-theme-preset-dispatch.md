# T-377 Command Action Search Theme Preset Dispatch

## Goal

让 action search 能直接选择并应用 terminal theme preset，同时保持动作本身不向 shell 写文本。

## Scope

- ShellCommandActionSearchAdapter 为每个 `terminalThemePresets` 条目生成 `applyTheme:<presetId>` app action。
- 从 action search 搜索并选择某个主题预设时，将 preset palette 保存到有效默认 profile。
- 保留无参数 `apply theme` action 的明确反馈。
- 增加 adapter regression，确认主题预设 action 携带可搜索 metadata。
- 增加 widget regression，确认选择主题预设后 profile colors 被保存。
- 将 regressions 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不改变 Defaults & appearance dialog 的保存流程。
- 不实现自定义导入主题或外部 theme repository。
- 不把旧 runtime session 的已启动颜色实时重写；新 session 使用保存后的 profile appearance。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/shell/shell_command_action_search_adapter.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/shell/shell_command_action_search_adapter_test.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-375-command-action-search-remaining-unavailable-feedback.md`
- `docs/tasks/command-center/T-376-command-action-search-reopen-closed-pane-dispatch.md`

## Functional Acceptance

- action search 可以搜到 `Apply <preset name> theme`。
- 主题预设 action id 使用 `applyTheme:<presetId>`，可解析出具体 theme id。
- 选择主题预设后，保存的默认 profile colors 等于 preset palette。
- 执行动作不向当前 shell 写文本。
- 搜索无参数 `apply theme` 仍显示 `Apply theme requires choosing a theme preset.`。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/shell/shell_command_action_search_adapter_test.dart --plain-name "adds terminal theme preset actions with encoded theme ids"
flutter test test/widget_test.dart --plain-name "action search can apply terminal theme preset without shell write"
flutter test test/widget_test.dart --plain-name "action search explains unavailable remaining visual workspace actions without shell write"
```

## Manual QA

- 打开 action search，搜索某个 terminal preset 名称。
- 选择 `Apply <preset name> theme`。
- 新建 tab，确认新 tab 使用该 preset 的 terminal colors。
- 确认 terminal 没收到 overlay 文案。

## Done When

- Theme preset 可以从 action search 直接应用。
- Adapter 和 widget regressions 覆盖 theme preset dispatch。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- 当前应用目标是有效默认 profile；后续如需作用于 active profile，需要明确产品规则。
- 当前不实时重绘已启动 pty 的颜色；需要时应走 terminal display config 更新路径。
- block action 的最近 block 执行由 T-378 覆盖；显式 selected block UI 仍是后续工作。
