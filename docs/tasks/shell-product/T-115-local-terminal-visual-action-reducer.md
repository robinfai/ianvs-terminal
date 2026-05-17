# T-115 Local Terminal Visual Action Reducer

## Goal

把 P5 的 visual/advanced action id 映射到可测试 result，先覆盖 theme picker、scrollback export 和 layout template apply，为后续 unified dispatcher 接入 visual 侧能力做准备。

## Scope

- `example/lib/features/visual/local_terminal_visual_action_reducer.dart`
- `example/test/visual/local_terminal_visual_action_reducer_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不打开真实 theme picker
- 不写出 scrollback 文件
- 不扫描真实 terminal buffer
- 不应用 layout template
- 不触碰 renderer

## Current Progress

- 已新增 `LocalTerminalVisualActionResult` result family。
- 已新增 `LocalTerminalVisualActionContext`。
- 已新增 `LocalTerminalVisualActionReducer.reduce()`。
- visual reducer 覆盖 `openThemePicker`、`exportScrollback` 和 `applyLayoutTemplate`。
- 已补充 theme picker、scrollback export、noop 测试。

## Functional Acceptance

- `openThemePicker` 返回 picker result。
- `exportScrollback` 返回可交给 exporter 的 payload。
- `applyLayoutTemplate` 返回待应用 template。
- 未处理 action 返回 noop。
- reducer 不触发 renderer 或文件系统副作用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/visual/local_terminal_visual_action_reducer_test.dart
flutter analyze
```

## Manual QA

本任务只新增 reducer，不接 UI；无需人工 UI 验收。

## Done When

- P5 visual action 有 reducer 边界可复用。
- 后续 dispatcher 可以统一处理 visual action。

## Risks / Follow-ups

- 后续需要把 scrollback capture 和 save dialog 接到 `LocalTerminalExportScrollbackResult`。
- 后续需要将 theme picker result 映射到 runtime appearance update。
