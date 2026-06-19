# T-319 Command Center Mode Router

## Goal

建立显式 mode router，区分 terminal、command search、action search、saved command、Agent
conversation 和 command review。

## Scope

- 定义 Command Center mode state。
- 管理 keyboard routing、escape/cancel 和 mode transitions。
- 将 Agent conversation、Agent inline ask 和 Agent command review 作为一等 mode。
- 统一 Command Bar、Search 和 Action Search 的 input ownership，并明确 hidden
  terminal focus 在 command-center modes 下没有文本插入权。

## Non-goals

- 不实现真实 Agent provider 调用；本阶段只定义 mode 和 input ownership。
- 不让自然语言自动识别绕过可见 route UI 或 terminal-first 默认行为。
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
- Agent conversation 和 command review 是可表示、可测试的一等 mode。
- hidden terminal focus 不能在 command-center modes 下拥有文本插入权。
- route decision 不会把 terminal mode 普通文本静默写入 Agent composer。
- mode router 给出清楚的 action consumption / pass-through 结果。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_center_mode_router_test.dart
```

## Manual QA

本任务为 state/router，可不做 UI QA。后续 UI 接入时必须手测 terminal mode、search mode、
action search mode、Agent conversation、command review 和 `Esc` 退出。

## Done When

- Command Bar、Search 和 Action Search 不再各自决定 terminal input ownership。
- command-center modes 下的文本插入权只归显式 command input，不归 hidden terminal
  focus。
- terminal-first 默认行为有测试。
- Agent conversation 和 command review 的输入所有权有测试，普通 terminal 文本仍默认进 shell。

## Risks / Follow-ups

- mode router 是输入安全关键点；后续任何新 mode 都必须补充测试。
- saved command mode 需要后续 repository 和 UI 任务承接。
