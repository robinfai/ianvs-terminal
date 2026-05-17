# T-090 Local Terminal Policy Models

## Goal

建立 P4 的 clipboard/paste/notification/hotkey window 策略模型，先覆盖输入安全和通知判定规则，为后续 runtime/UI 接入提供统一语义。

## Scope

- `example/lib/features/policies/local_terminal_policy_models.dart`
- `example/test/policies/local_terminal_policy_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P4_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入真实 clipboard bridge
- 不改 paste runtime
- 不触发系统通知
- 不调用 window bridge
- 不新增 remote/SSH policy

## Current Progress

- 已新增 clipboard policy 枚举和模型。
- 已新增 paste policy，支持 multiline/large paste confirmation 判定和 read-only paste guard。
- 已新增 monitor rule、target、focus policy。
- 已新增 notification policy 默认规则。
- 已新增 hotkey window policy 的基础 size/autohide/enabled 模型。
- 已补充 paste confirmation、read-only paste、monitor focus/threshold、hotkey size 测试。

## Functional Acceptance

- 多行粘贴需要确认。
- 大段粘贴超过阈值时需要确认。
- read-only 下禁止 paste。
- monitor rule 尊重 focus policy 和 threshold。
- hotkey window policy 能暴露不可用尺寸状态。

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

- P4 输入策略和通知策略有可复用模型。
- 后续 runtime 接入不需要重新定义 paste/monitor/hotkey 判定语义。

## Risks / Follow-ups

- 后续需要把现有 paste history 和 advanced paste surface 接入该策略。
- 后续需要把 notification target 映射到 badge/toast/system notification。
