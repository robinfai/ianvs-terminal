# flutterm_terminal

`flutterm_terminal` 建在 `flutterm_pty` 之上，负责共享 terminal 运行时和 viewport 适配。

## 对上层暴露

- `TerminalSessionConfig`
- `TerminalLaunchConfig`
- `TerminalDisplayConfig`
- `TerminalRuntimeController`
- `TerminalSessionEvent`
- `TerminalViewport`
- `TerminalViewportController`

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
