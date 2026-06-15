# T-330 Command Action Search Controller

## Goal

建立 `/` action search 的状态控制层，复用 T-329 的搜索结果，并把选择结果转成安全的输出意图。

## Scope

- 新增 action search state、intent 和 output。
- 支持显式 open / close。
- 支持查询更新和上下移动选择。
- 选择 app action 时输出 open action intent。
- 选择 saved command 时输出 insert saved command intent。

## Non-goals

- 不实现 `/` overlay UI。
- 不接入 ShellScreen 快捷键或输入路径。
- 不写入 terminal。
- 不执行 saved command。
- 不定义 app action registry 的真实 action 集。

## Files In Scope

- `example/lib/features/command_center/command_action_search_controller.dart`
- `example/test/command_center/command_action_search_controller_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- controller 初始状态为 closed。
- explicit open 会加载空查询结果并选择第一条。
- close 会清空 query、results 和 selected index。
- query update 只在 open 状态生效。
- selection move 不会越界。
- app action selection 只输出 action id。
- saved command selection 只输出 command text，不直接写 shell。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test \
  test/command_center/command_action_search_index_test.dart \
  test/command_center/command_action_search_controller_test.dart
```

## Manual QA

纯 controller 任务，无 UI QA。后续 `/` overlay 和 ShellScreen 接线时必须手测：

- `/` 只通过显式入口打开，不由普通文本触发。
- `Esc` 关闭后 terminal 恢复输入。
- 选择 saved command 只插入，不自动执行。
- read-only 下 insert intent 被后续安全策略阻止。

## Done When

- `/` overlay 不需要自己管理搜索状态和选择状态。
- app action 与 saved command 的选择输出互相区分。
- controller 行为有 open、close、query、move 和 accept 测试。

## Risks / Follow-ups

- 尚未有 `/` overlay UI。
- 尚未接入 ShellScreen 或 mode router。
- saved command insert 仍需要后续安全策略接线。
