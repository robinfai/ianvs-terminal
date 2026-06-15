# T-379 Context Chip Last Failed Block Navigation

## Goal

让 ShellScreen 的 context chips 显示最近失败 command block，并允许用户点击 chip 回到该 block。

## Scope

- Context chip wiring 从 `CommandBlockRangeState` 派生最近 failed block。
- ShellScreen 基于当前 session lifecycle 和 prompt marks 构建 block range state。
- 显示 `Last exit` chip，包含失败 exit code。
- 点击 `Last exit` chip 滚动到该 command block 的 input row。
- 保持 chip click 不写 shell。
- 增加 widget regression 覆盖真实 shell hook / terminal frame 路径。

## Non-goals

- 不实现显式 selected block UI。
- 不打开 block action menu。
- 不实现 last successful block chip。
- 不改变 terminal renderer 或 scrollback model。

## Files In Scope

- `example/lib/features/command_center/command_center_context_wiring.dart`
- `example/lib/features/shell/shell_screen_state_context_chips.dart`
- `example/lib/features/shell/shell_screen_state_terminal_workspace.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-326-command-center-context-chip-wiring.md`

## Functional Acceptance

- 失败命令产生 lifecycle 和 prompt marks 后，active pane 显示 `Last exit Exit <code>`。
- 点击该 chip 调用 terminal runtime scroll-to，并定位到失败 block input row。
- chip click 不向 shell 写入任何文本。
- 没有 block range 时不显示 last-exit chip。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "context chip navigates to the last failed command block"
flutter test test/widget_test.dart --plain-name "action search"
```

## Manual QA

- 在 shell integration 可用的 session 中运行一个失败命令。
- 确认 terminal overlay 出现 `Last exit Exit <code>` chip。
- 滚动到其他位置后点击该 chip，确认回到失败命令所在 block。
- 确认 shell 没收到 chip 文案或命令文本。

## Done When

- Last failed block chip 来自真实 runtime/session state。
- 点击 chip 能安全导航到失败 block。
- Command Bar lane 验证门包含该 regression。

## Risks / Follow-ups

- selected block chip 仍需要显式 selection state。
- 如果 shell integration 缺少 prompt marks，last-exit chip 会降级为不可见。
