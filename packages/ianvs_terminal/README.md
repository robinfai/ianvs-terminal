# ianvs_terminal

`ianvs_terminal` 建在 `ianvs_pty` 之上，负责共享 terminal 运行时和 viewport 适配。

## 对上层暴露

- `TerminalSessionConfig`
- `TerminalLaunchConfig`
- `TerminalShellIntegrationConfig`
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

The logical hook names stay shell-agnostic. zsh, bash, and fish integrations
emit `preexec`, `command_finished`, `precmd`, and `precmd.pwd`.

`TerminalShellIntegrationConfig.enabled` controls whether eligible sessions may
inject shell hooks. It defaults to `true`, but unsupported shells, most custom
shell arguments, VT220 emulation, or native proxy setup failures automatically
fall back to the original shell launch path without emitting shell-hook events.
The default zsh login shell arguments (`-l` or `--login`) remain eligible.
Native diagnostics export records the launch decision in the initial `started`
diagnostic event as `shell_integration.status`, `reason`, optional `kind`, and
optional `error`, so support logs can tell disabled/degraded sessions apart from
normal hook silence.

Bash integration uses a `DEBUG` trap for `preexec` and wraps `PROMPT_COMMAND`
for completion hooks. If a user already has a `DEBUG` trap, bash integration
automatically falls back without installing hooks. Bash may also report only the
first simple command for complex pipelines or compound commands.

## 不负责

- tab / menu / window chrome
- 系统剪贴板平台桥接
- profile 编辑器
- demo fixture

这些都留在 `example/`。剪贴板这类平台能力由上层通过 `copyToClipboard` / `readClipboard` 回调注入。

## 测试

```bash
cd packages/ianvs_terminal
flutter test
```
