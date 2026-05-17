# T-128 Scrollback Export Runtime Controller Integration

## Goal

把 P5 scrollback export side effect 接入 `ShellActionRuntimeController`，让 `exportScrollback` action 可以通过统一 action pipeline 调用本地 exporter 并记录导出路径。

## Scope

- `example/lib/features/shell/shell_action_runtime_controller.dart`
- `example/test/shell/shell_action_runtime_controller_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接 save dialog
- 不扫描真实 terminal scrollback
- 不接 UI
- 不改变 renderer
- 不导出远程文件

## Current Progress

- `ShellActionRuntimeState` 已记录 `lastScrollbackExportPath`。
- `ShellActionRuntimeController.run()` 已支持可选 scrollback export directory、basename 和 policy。
- `exportScrollback` side effect handler 会调用 `LocalTerminalScrollbackExporter.write()`。
- 成功导出后 controller 会记录导出文件路径。
- 已补充 runtime controller 导出 scrollback payload 的测试。

## Functional Acceptance

- `exportScrollback` action 可以进入统一 action pipeline。
- controller 能把 export payload 写成本地文件。
- controller 能记录最后导出路径。
- 缺少导出目录时不触发副作用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_runtime_controller_test.dart
flutter analyze
```

## Manual QA

本任务只接 runtime controller，不接 UI/save dialog；无需人工 UI 验收。

## Done When

- P5 scrollback export 已通过 action pipeline 进入 runtime controller。
- 后续 UI 只需提供真实 scrollback payload 和目标目录。

## Risks / Follow-ups

- 后续需要接真实 scrollback capture。
- 后续需要接 save dialog 和文件名冲突处理。
