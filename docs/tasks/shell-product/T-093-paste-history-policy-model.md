# T-093 Paste History Policy Model

## Goal

补齐 P4 paste history policy 的模型层，定义 paste history 捕获、去重、limit、持久化意图和 focus-safe 约束，为后续现有 paste history UI 接入统一策略做准备。

## Scope

- `example/lib/features/policies/local_terminal_policy_models.dart`
- `example/test/policies/local_terminal_policy_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P4_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不改现有 paste history repository
- 不接入 paste history sheet UI
- 不改变 paste runtime
- 不读取剪贴板
- 不新增 remote/SSH policy

## Current Progress

- 已新增 `LocalTerminalPasteHistoryPolicy`。
- 已新增 `LocalTerminalPasteHistoryState`。
- paste history 支持 enabled、maxEntries、persist、captureMultiline、captureLargePaste。
- state record 支持 newest-first、去重和 limit trimming。
- state 显式保留 `focusShouldReturnToTerminal`，作为后续 UI 接入的 focus-safe 合同。
- 已补充 capture gate、去重、limit 和 multiline reject 测试。

## Functional Acceptance

- 空文本不进入 history。
- large paste 是否进入 history 由策略控制。
- multiline paste 是否进入 history 由策略控制。
- history 保留最新唯一项并遵守 maxEntries。
- paste history UI 后续必须把 focus 还给 terminal。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/policies/local_terminal_policy_models_test.dart
flutter analyze
```

## Manual QA

本任务只新增纯模型，不接入 UI；无需人工 UI 验收。

## Done When

- P4 paste history policy 有可复用模型。
- 后续 runtime/UI 接入无需重新定义 history 捕获和 focus-safe 规则。

## Risks / Follow-ups

- 后续需要将现有 `PasteHistoryRepository` 接入该 policy。
- 后续需要在 paste history sheet 关闭后显式恢复 terminal focus。
