# T-095 Planned Action ID Expansion

## Goal

把 P2-P5 中已经进入模型层的能力补进 `TerminalActionId` / `ShellActionRegistry`，先建立稳定 action 边界，后续 UI、command palette、keybinding 和 config 接入都引用同一批 action id。

## Scope

- `example/lib/features/shell/shell_action_registry.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 command menu UI
- 不接入快捷键默认值
- 不实现 action handler
- 不改变现有 shortcut dispatch 行为
- 不新增 remote/SSH action

## Current Progress

- 已新增 workspace/session actions：`duplicateCurrentCwd`、`reopenClosedTab`。
- 已新增 pane actions：`focusNextPane`、`focusPreviousPane`、`resizePane`、`swapPane`、`zoomPane`、`closePane`、`reopenClosedPane`。
- 已新增 shell productivity actions：`copyCommandOutput`、`toggleReadOnly`、`clearScrollback`、`openRecentDirectory`。
- 已新增 monitor actions：`toggleCommandFinishedNotify`、`toggleBellNotify`、`toggleActivityMonitor`。
- 已新增 advanced/local actions：`exportScrollback`、`openThemePicker`、`applyLayoutTemplate`。
- 每个新 action 已有 registry descriptor、label、category、icon 和 active-session requirement。

## Functional Acceptance

- P2-P5 后续 UI 和 keybinding 接入可以引用稳定 action id。
- 新 action 不引入 SSH、remote、SFTP、serial 语义。
- 新 action 默认不改变现有 runtime 行为。
- 每个 action 都有 descriptor metadata。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/terminal_action_registry_test.dart
flutter analyze
```

## Manual QA

本任务只扩展 registry metadata，不接入 UI；无需人工 UI 验收。

## Done When

- P2-P5 的关键规划能力都有可引用 action id。
- 后续 command palette/keybinding/config 接入无需临时新增私有 action enum。

## Risks / Follow-ups

- 后续需要逐步把这些 action 接入 command palette 和实际 handler。
- 部分 action 需要 feature disabled diagnostics，不能直接无条件暴露为可执行。
