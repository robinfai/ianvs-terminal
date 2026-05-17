# T-101 Shell Productivity Event Reducer

## Goal

补齐 shell integration event 到 P3 productivity state 的归约层，让 prompt marks、cwd tracking、command finished、command output range、recent commands/directories 可以通过统一 adapter 接入。

## Scope

- `example/lib/features/productivity/shell_productivity_reducer.dart`
- `example/test/productivity/shell_productivity_reducer_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入真实 shell hook event stream
- 不修改 session controller
- 不写入 recent items repository
- 不接 UI
- 不新增 remote/SSH command event

## Current Progress

- 已新增 `ShellProductivityEvent` sealed event family。
- 已新增 prompt mark、command finished、command output range、cwd changed 事件。
- 已新增 `ShellProductivitySnapshot`。
- 已新增 `ShellProductivityReducer.reduce()`。
- reducer 能把 cwd/prompt/command/output 事件映射到 productivity state 和 recent items。
- 已补充 prompt mark、cwd、command finished、command output range 归约测试。

## Functional Acceptance

- prompt mark event 会记录 prompt mark。
- cwd event 会更新 current cwd 和 recent directories。
- command finished event 会记录 recent command 并继承 current cwd。
- command output range event 会让 command output action 具备可用数据。
- event family 不表达 remote/SSH command。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/productivity/shell_productivity_reducer_test.dart
flutter analyze
```

## Manual QA

本任务只新增 reducer，不接入真实事件流；无需人工 UI 验收。

## Done When

- P3 productivity state 具备 shell integration event adapter。
- 后续 runtime 接入只需要把现有 shell hook 输出转换成 reducer event。

## Risks / Follow-ups

- 后续需要定义 recent items 的落盘和隐私策略。
- 后续需要把 reducer 接入 session/pane scoped state。
