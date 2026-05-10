# flutterm_terminal

`flutterm_terminal` 建在 `flutterm_pty` 之上，负责共享 terminal 运行时和 viewport 适配。

## 对上层暴露

- `TerminalSessionConfig`
- `TerminalLaunchConfig`
- `TerminalDisplayConfig`
- `TerminalRuntimeController`
- `TerminalSessionEvent`
- `TerminalSessionShellHookEvent`
- `TerminalViewport`
- `TerminalViewportController`

## Shell Hook Events

`TerminalRuntimeController.events` emits `TerminalSessionShellHookEvent` for
native `shell_hook` events. The event preserves the raw payload and exposes
lightweight fields for `hook`, `command`, `cwd`, `shell`, and `exitCode`.

The logical hook names stay shell-agnostic. The zsh baseline is `preexec`,
`command_finished`, `precmd`, and `precmd.pwd`; bash and fish integrations
should map to the same names when they are added.

## 不负责

- tab / menu / window chrome
- profile 编辑器
- demo fixture

这些都留在 `example/`。

## 测试

```bash
cd packages/flutterm_terminal
flutter test
```
