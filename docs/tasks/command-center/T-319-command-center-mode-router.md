# T-319 Command Center Mode Router

## Goal

建立显式 mode router，区分 terminal、command search、action search、saved command 和 future agent。

## Scope

- 定义 Command Center mode state。
- 管理 keyboard routing、escape/cancel 和 mode transitions。
- 将 future agent mode 保留为 disabled extension point。
- 统一 Command Bar、Search 和 Action Search 的 input ownership，并明确 hidden
  terminal focus 在 command-center modes 下没有文本插入权。

## Non-goals

- 不实现 Agent mode。
- 不做自然语言自动识别。
- 不绕过 terminal input policy。
- 不实现 command search overlay 视觉。
- 不实现 saved command repository。

## Files In Scope

- `example/lib/features/command_center/command_center_mode_router.dart`
- `example/test/command_center/command_center_mode_router_test.dart`

## Functional Acceptance

- 默认 mode 是 terminal。
- 只有显式快捷键或显式入口进入增强 mode。
- `Esc` 返回 terminal mode。
- futureAgent 只作为 disabled extension point。
- hidden terminal focus 不能在 command-center modes 下拥有文本插入权。
- route decision 不会把普通文本误判成 Agent prompt。
- mode router 给出清楚的 action consumption / pass-through 结果。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_center_mode_router_test.dart
```

## Manual QA

本任务为 state/router，可不做 UI QA。后续 UI 接入时必须手测 terminal mode、search mode、action search mode 和 `Esc` 退出。

## Done When

- Command Bar、Search 和 Action Search 不再各自决定 terminal input ownership。
- command-center modes 下的文本插入权只归显式 command input，不归 hidden terminal
  focus。
- terminal-first 默认行为有测试。
- futureAgent 明确 disabled，不可被普通文本触发。

## Risks / Follow-ups

- mode router 是输入安全关键点；后续任何新 mode 都必须补充测试。
- saved command mode 需要后续 repository 和 UI 任务承接。
