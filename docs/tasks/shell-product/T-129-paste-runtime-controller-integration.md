# T-129 Paste Runtime Controller Integration

## Goal

把 P4 paste decision 接入 `ShellActionRuntimeController`，让 paste action 通过统一 action pipeline 后能记录 send/confirm/block paste 决策和原始文本。

## Scope

- `example/lib/features/policies/local_terminal_paste_decision.dart`
- `example/lib/features/shell/shell_action_runtime_controller.dart`
- `example/test/policies/local_terminal_paste_decision_test.dart`
- `example/test/shell/shell_action_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P4_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不向 terminal 发送真实文本
- 不打开 confirmation UI
- 不写入 paste history repository
- 不读取系统剪贴板
- 不改 terminal input controller

## Current Progress

- `LocalTerminalPasteDecision` 已携带原始 paste text。
- `ShellActionRuntimeState` 已记录 `lastPasteDecision`。
- runtime controller 的 send/confirm/block paste handlers 会记录最后一次 paste decision。
- 已补充 paste decision text 断言和 runtime controller paste action 测试。

## Functional Acceptance

- paste decision 保留原始文本。
- paste action 进入 pipeline 后 controller 可记录 send/confirm/block 决策。
- read-only block/confirmation/send 仍只表达意图，不触发真实输入。
- 后续真实 paste handler 可从 decision 中读取 text。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/policies/local_terminal_paste_decision_test.dart
flutter test test/shell/shell_action_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只接 runtime controller，不发送真实 paste；无需人工 UI 验收。

## Done When

- P4 paste action 已通过 action pipeline 进入 runtime controller。
- 后续真实 paste side effect 可以基于 `LocalTerminalPasteDecision.text` 安全实现。

## Risks / Follow-ups

- 后续接入真实 terminal paste 时必须保留 read-only 和 multiline/large confirmation gates。
- paste history capture 仍需接 repository。
