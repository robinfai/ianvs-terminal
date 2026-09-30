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

## 桌面 native 构建

构建 hook 支持 macOS（arm64/x64）和 GNU/Linux（arm64/x64）。Linux 产物为
`libianvs_core.so`，随 Flutter bundle 放入可执行文件旁的 `lib/` 目录；分发时须保留
完整 bundle。macOS 继续使用 framework/dylib，iOS 继续从进程加载已静态链接的符号。
开发时可用 `IANVS_CORE_LIB` 指定 native library；product 构建只加载 bundle 内产物，
不会使用该环境变量或源码目录的调试库。

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
