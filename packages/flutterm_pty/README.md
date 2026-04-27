# flutterm_pty

`flutterm_pty` 只负责 PTY 会话传输和 FFI 包装。

## 对上层暴露

- `PtySessionBackend`
- `PtyBindings`
- `PtyEvent`
- `NativePtyBackend`

## 不负责

- profile
- tab
- viewport
- shell UI

## 测试

```bash
cd native/core
cargo test
```

```bash
cd packages/flutterm_pty
dart test
```
