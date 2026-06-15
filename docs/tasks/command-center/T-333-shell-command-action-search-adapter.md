# T-333 Shell Command Action Search Adapter

## Goal

把真实 `ShellActionRegistry` 的可见 action 转成 `/` action search 可搜索项，为 ShellScreen 接线提供真实 action 数据源。

## Scope

- 新增 `ShellCommandActionSearchAdapter`。
- 将 command palette visible 的 shell actions 映射为 `CommandActionSearchItem.appAction`。
- 使用 action id name 作为稳定 item id。
- 将 registry label 转成人类可读标题。
- 将 category、shortcut 和 disabled reason 放进 subtitle / keywords。
- 将 `CommandActionSearchOutput.openAction` 反解回 `TerminalActionId`。

## Non-goals

- 不实现 ShellScreen `/` 入口。
- 不执行 action。
- 不改变 ShellActionRegistry。
- 不改变 command menu 的现有展示。
- 不把 shell registry 依赖放进 `features/command_center`。

## Files In Scope

- `example/lib/features/shell/shell_command_action_search_adapter.dart`
- `example/test/shell/shell_command_action_search_adapter_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- 可见 registry actions 会出现在 action search items。
- 不可见 actions 不会进入 action search items。
- item title 使用可读文本，而不是 registry snake_case 原文。
- shortcut、category 和 disabled reason 能被搜索。
- app action output 可以映射回 `TerminalActionId`。
- saved command output 不会被误映射成 shell action。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test \
  test/shell/shell_command_action_search_adapter_test.dart \
  test/command_center/command_action_search_index_test.dart \
  test/command_center/command_action_search_overlay_test.dart
```

## Manual QA

纯 adapter 任务，无 UI QA。后续 ShellScreen 接线时必须手测：

- `/` action search 能搜到真实 shell actions。
- disabled action 有可见原因或后续阻止反馈。
- 选择 app action 不写 shell。
- 普通 `/` 文本不会打开 action search。

## Done When

- action search 不再依赖手写假 action 列表。
- shell registry 和 command_center 搜索模型之间有单向 adapter。
- 后续 ShellScreen 接线可以把 `openAction` output 安全映射成 `TerminalActionId`。

## Risks / Follow-ups

- 尚未接入 ShellScreen 或 mode router。
- app action 执行仍需复用现有 action dispatch / availability。
- adapter 目前不把 icon 传给 overlay，因为 search item 模型尚无 icon 字段。
