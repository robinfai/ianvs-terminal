# ianvs_pty

`ianvs_pty` 只负责 PTY 会话传输和 FFI 包装。

## 对上层暴露

- `PtySessionBackend`
- `PtySessionConfigV1Backend` / `PtyReplaySessionConfigV1Backend`
- `PtySessionRequestV1Backend` / `PtySessionFramePacketV1Backend`
- `PtyBindings`
- `PtyEvent`
- `NativePtyBackend`

## 不负责

- profile
- tab
- viewport
- shell UI

## 当前 native 合同

`NativePtyBindings` 加载时要求当前 ABI，创建仅接受 SessionConfig v1；命令、事件、
诊断、帧和图像分别使用当前版本合同，不回退到历史 Profile JSON、Frame JSON 或旧 FFI。
自定义 Dart backend 的可选接口仍用于能力分离，不代表兼容旧 native library。

完整符号与所有权边界见 [Runtime Wire Inventory](../../docs/protocols/RUNTIME_WIRE_INVENTORY.md)。
`ianvs_terminal_core` 中的 PTY 源由本包确定性生成；修改本包后在仓库根目录运行
`make terminal-core-sync`，再运行 `make terminal-core-check`。

## 测试

以下命令从仓库根目录执行，每个代码块独立运行。

```bash
cd native/core
cargo test
```

```bash
cd packages/ianvs_pty
dart analyze --fatal-infos
dart test
```
