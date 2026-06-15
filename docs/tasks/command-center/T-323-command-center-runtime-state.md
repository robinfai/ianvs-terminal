# T-323 Command Center Runtime State

## Goal

建立 Command Center runtime state/reducer，把 shell hook lifecycle event 串成 lifecycle、history、search index 和 command block state。

## Scope

- 处理 command started、finished 和 cwd changed event。
- 维护 session-local running invocation、cwd 和 history。
- 从当前 state 生成 search index 和 block range state。
- 容忍 out-of-order finish event，不让 shell integration 异常打断 terminal。

## Non-goals

- 不接 UI。
- 不写入 shell。
- 不落盘 global history。
- 不实现 saved commands、Agent mode 或 action search。
- 不重写 terminal renderer。

## Files In Scope

- `example/lib/features/command_center/command_center_runtime.dart`
- `example/test/command_center/command_center_runtime_test.dart`

## Functional Acceptance

- `preexec`/started event 创建 running invocation。
- `command_finished`/finished event 关闭对应 running invocation，生成 status、exitCode、duration 和 history entry。
- cwd event 可补齐后续 command 的 cwd。
- session 状态隔离。
- out-of-order finish event 会生成 completed invocation 和 history，不崩溃。
- 当前 runtime state 可生成 `CommandSearchIndex` 和 `CommandBlockRangeState`。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_center_runtime_test.dart
```

## Manual QA

纯 runtime/state 任务，无需 UI QA。后续 shell wiring 任务必须验证真实 shell hook 事件能进入此 reducer。

## Done When

- Command Center 不再需要各 UI 组件各自拼 lifecycle/history/block 状态。
- 后续 shell 接线可以把 adapter event 直接喂给 runtime reducer。

## Risks / Follow-ups

- 真正的 row range 仍来自 terminal viewport/shell integration 后续接线。
- global history flush 仍需单独接入 repository。
- 如果 finish event 与 running command 匹配策略在真实 shell 中不足，需要补充 command id 或更强的 hook metadata。
