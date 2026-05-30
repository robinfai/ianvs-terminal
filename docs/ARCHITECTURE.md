# ianvs terminal Architecture

这份文档只回答一个问题：当前仓库里，哪一层负责什么。

## 工作区分层

- `packages/ianvs_pty`
  - 负责 PTY 会话传输和 FFI 包装
  - 对上层公开 `PtySessionBackend`、`PtyEvent`、`PtyBindings`、`NativePtyBackend`
  - 能力边界只有 `create / write / read|poll / resize / scroll / close`
- `packages/ianvs_terminal`
  - 依赖 `ianvs_pty`
  - 负责 `TerminalSessionConfig`、`TerminalLaunchConfig`、`TerminalDisplayConfig`
  - 负责 `TerminalRuntimeController`、`TerminalSessionEvent`
  - 负责 viewport、输入编码、选区、滚动和焦点相关适配
- `example/`
  - 负责 tab、窗口壳、菜单、profile 编辑、defaults、demo fixture
  - 负责用 demo 侧元数据包住 `TerminalSessionConfig`
  - 通过 `features/terminal/terminal.dart` 和 `features/pty/pty.dart` 消费 package
  - 平台桥接（例如系统剪贴板）留在 `example/lib/platform/`
  - 不再定义 PTY/terminal 共享能力
- `native/core`
  - 负责 Rust PTY、VT 解析、frame diff、事件输出
  - 当前仍保留原位置，不为目录整齐额外搬 Rust 源码

## 公开接口

### `ianvs_pty`

- `PtySessionBackend`
- `PtyBindings`
- `PtyEvent`
- `NativePtyBackend`

这里不暴露 tab、profile、viewport 这些 app 词汇。

### `ianvs_terminal`

- `TerminalSessionConfig`
- `TerminalLaunchConfig`
- `TerminalDisplayConfig`
- `TerminalRuntimeController`
- `TerminalSessionEvent`
- `TerminalViewport`
- `TerminalViewportController`

这里不暴露 `Profile` 这个 app 词汇。对 native/core 仍需旧 wire 形状的地方，由 package 内部适配，不把这个兼容债务抛给上层。

### `example/` 本地边界入口

- `example/lib/features/terminal/terminal.dart`
- `example/lib/features/pty/pty.dart`
- `example/lib/platform/clipboard_bridge.dart`

`example` 内部业务代码不再直接散落地 import `ianvs_terminal` / `ianvs_pty`；优先经过这些本地入口收口。这样 package 边界和 app 边界各自只有一个入口面。

## 数据流

创建会话：

1. `example/` 选择一个 demo profile。
2. demo profile 组装成 `TerminalSessionConfig`。
3. `TerminalRuntimeController` 把中性的 session config 转成当前 native wire。
4. `ianvs_pty` 通过 FFI 调 Rust。
5. `native/core` 启 PTY、解析输出并生成 frame diff / 事件。

输入与视口：

1. `example/` 把焦点、滚动、键盘、菜单动作交给 `ianvs_terminal`。
2. `ianvs_terminal` 把输入编码成字节或滚动请求。
3. `ianvs_pty` 下发给 Rust。
4. `TerminalRuntimeController` 消费 frame diff / event，驱动 `TerminalViewportController`。

## 不属于 package 的内容

以下能力明确留在 `example/`：

- tab 生命周期和排序
- 窗口标题与窗口壳
- launcher / command menu
- 系统剪贴板桥接
- defaults / appearance UI
- profile 编辑器
- `reference_demo.dart` 和其他 demo fixture

## 当前约束

- `native/core` 现在还吃旧的 profile wire，所以 `ianvs_terminal` 内部保留了一层 native wire 适配。
- `example/` 目录里的 Flutter package 现阶段仍保留 `name: app`，这是为了稳定既有 `package:app/...` import 面；macOS bundle identity 由 Runner project 单独维护。
- 本次边界调整不处理 pub.dev 发布、插件系统和跨平台扩展。
