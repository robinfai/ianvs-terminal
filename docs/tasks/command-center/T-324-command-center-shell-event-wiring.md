# T-324 Command Center Shell Event Wiring

## Goal

把真实 `ShellScreen` 收到的 shell hook event 接入 Command Center runtime，让 lifecycle、cwd 和 session history 不再只存在于 isolated reducer 测试里。

## Scope

- 增加 app 层 shell event wiring helper。
- 组合 `ShellHookLifecycleAdapter` 和 `CommandCenterRuntimeReducer`。
- 在 `ShellScreen` 的 `TerminalSessionShellHookEvent` 分支更新 Command Center runtime state。
- 保留现有 command finished notification 行为。
- 对未知 hook 或缺字段 hook 保持忽略，不影响 terminal。

## Non-goals

- 不接 Command Center UI。
- 不落盘 global history。
- 不生成 terminal row range。
- 不修改 PTY / package-level terminal event schema。
- 不实现 saved commands、action search、Agent mode 或自然语言入口。

## Files In Scope

- `example/lib/features/command_center/command_center_shell_event_wiring.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_state_events.dart`
- `example/test/command_center/command_center_shell_event_wiring_test.dart`

## Functional Acceptance

- `preexec` hook 会创建 running invocation。
- `command_finished` hook 会关闭 invocation 并写入 session history。
- `precmd.pwd` hook 会更新 session cwd。
- 未知 hook 返回 ignored reason，runtime state 不变。
- `ShellScreen` 继续调用原有 shell hook notification 路径。
- 普通 terminal frame、bell、exit event 行为不变。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test \
  test/command_center/command_center_shell_event_wiring_test.dart \
  test/shell/shell_screen_architecture_test.dart
```

## Manual QA

此任务只接 runtime state，当前没有新增可见 UI。后续把 history/search/block UI 读取 runtime state 时，需要补真实 shell 手工验证：

- 运行一个成功命令和一个失败命令。
- 确认 Command Center UI 能看到 command、cwd、exitCode、duration。
- 确认 command finished notification 行为没有改变。

## Done When

- Shell hook event 可以从 `ShellScreen` 进入 Command Center runtime。
- runtime wiring 有 focused 单元测试覆盖 started、finished、cwd 和 ignored hook。
- 后续 UI 任务不需要重新解析 raw shell hook payload。

## Risks / Follow-ups

- 目前 runtime state 仍是 `ShellScreen` 私有字段，尚未供 UI 读取。
- row range 和 block visible range 仍需 terminal viewport 接线。
- global history flush 仍需 repository 接入。
