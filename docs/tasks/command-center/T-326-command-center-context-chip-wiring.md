# T-326 Command Center Context Chip Wiring

## Goal

把已实现的 Context Chips 接到真实 `ShellScreen` active terminal pane，展示 cwd、profile、shell hook 状态和 read-only 状态。

## Scope

- 从 `CommandCenterRuntimeState` 和 pane shell integration 派生 context chip state。
- runtime cwd 优先，shell integration cwd 作为 fallback。
- 在 active terminal pane overlay 层渲染 chips。
- 在 search、command search、autocomplete、auto composer、copy mode 打开时隐藏 chips，避免 UI 重叠。
- chip click 只触发安全 intent：toggle read-only、打开 profile 管理或显示诊断消息。

## Non-goals

- 不接 selected block 或 last failed block chip。
- 不实现 block action menu。
- 不探测 git branch。
- 不写 shell。
- 不改变 terminal renderer 或 scrollback。

## Files In Scope

- `example/lib/features/command_center/command_center_context_wiring.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_state_context_chips.dart`
- `example/lib/features/shell/shell_screen_state_terminal_workspace.dart`
- `example/test/command_center/command_center_context_wiring_test.dart`

## Functional Acceptance

- active pane 显示 cwd、profile 和 shell hook chip。
- runtime cwd 优先于 shell integration cwd。
- 缺 cwd 时 shell hook chip 显示 limited / missing cwd。
- read-only session 显示 read-only chip。
- 点击 read-only chip 切换 read-only。
- chip click 不直接写 terminal。
- overlay 不进入 scrollback，也不和 search/autocomplete/command search 层同时显示。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test \
  test/command_center/command_center_context_wiring_test.dart \
  test/command_center/context_chips_test.dart \
  test/shell/shell_screen_architecture_test.dart
```

## Manual QA

- 运行 app，确认 active pane 上出现 cwd/profile/shell chips。
- 切换 cwd，确认 cwd chip 后续随 shell hook 更新。
- 打开 read-only，确认 read-only chip 出现。
- 打开 `Ctrl-R`、terminal search、autocomplete、copy mode，确认 chips 隐藏且不遮挡。
- 点击 chips，确认只出现诊断或安全面板，不发送 shell input。

## Done When

- Context Chips 有真实 ShellScreen 入口。
- 可见 chip state 来自 runtime/session state，而不是测试 fixture。
- 后续 selected block state 接线可追加 selected block chip。

## Risks / Follow-ups

- last exit block navigation 由 T-379 覆盖；selected block 仍依赖显式 selection state。
- git branch chip 需要单独定义 debounce、错误处理和性能门。
- chip 视觉密度可能需要后续跟 Command Bar 一起收口。
