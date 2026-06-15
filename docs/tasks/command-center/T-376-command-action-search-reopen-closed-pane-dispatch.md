# T-376 Command Action Search Reopen Closed Pane Dispatch

## Goal

让 action search 能执行 `Reopen closed pane`，从最近关闭的 pane 重新创建一个 runtime session，并保持动作本身不向 shell 写文本。

## Scope

- SessionController 在关闭多 pane tab 里的单个 pane 时记录最近关闭的 pane。
- 从 action search 搜索并选择 `reopen closed pane` 时恢复最近关闭的 pane。
- 没有最近关闭 pane 时保留明确不可用反馈。
- 增加 widget regression，确认 close pane 后可以从 action search 恢复为两个 pane。
- 将该 regression 纳入 Command Bar lane 最小验证命令。

## Non-goals

- 不复用旧 runtime session id；reopen closed pane 会创建新的 session。
- 不恢复已关闭 shell 进程里的运行中状态。
- 不改变 close tab 或 reopen closed tab 行为。
- 不实现 mode router。

## Files In Scope

- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-367-command-action-search-close-pane-dispatch.md`
- `docs/tasks/command-center/T-375-command-action-search-remaining-unavailable-feedback.md`

## Functional Acceptance

- action search 搜索 `reopen closed pane` 后按 `Enter` 会恢复最近关闭的 pane。
- 恢复后的 pane 使用新的 runtime session id，并成为当前 active pane。
- 执行动作不向当前 shell 写文本。
- 没有最近关闭 pane 时显示 `No recently closed pane is available.`。
- 关闭整个 tab 时不把该 tab 的 closed pane stack 泄漏到其他 tab。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "action search can reopen closed pane without shell write"
flutter test test/widget_test.dart --plain-name "action search can close pane without shell write"
flutter test test/widget_test.dart --plain-name "action search explains unavailable remaining visual workspace actions without shell write"
```

## Manual QA

- 创建两个 pane。
- 用 action search 搜索 `close pane` 并关闭当前 pane。
- 再用 action search 搜索 `reopen closed pane`，按 `Enter`。
- 确认 pane 数量恢复为两个，恢复出的 pane 可聚焦，terminal 没收到 overlay 文案。

## Done When

- Reopen closed pane 可以从 action search 执行。
- SessionController 记录并消费最近关闭的 pane。
- action search 对 reopen closed pane 有 widget regression。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- 当前恢复的是新的 shell session，不是旧进程恢复。
- 如果后续要恢复更完整的 pane 布局位置，需要在 closed pane stack 中记录原始 split 位置。
- `apply theme` 仍需要 action search 支持选择具体 theme preset 或传递 `themeId`。
