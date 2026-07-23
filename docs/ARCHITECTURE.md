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
- `PtySessionConfigV1Backend`
- `PtyReplaySessionConfigV1Backend`
- `PtySessionRequestV1Backend`
- `PtySessionRequestV1`
- `PtySessionResponseV1`
- `PtyBindings`
- `PtyEvent`
- `NativePtyBackend`

这里不暴露 tab、profile、viewport 这些 app 词汇。

### `ianvs_terminal`

- `TerminalSessionConfig`
- `TerminalSessionConfigV1`
- `TerminalLaunchConfig`
- `TerminalDisplayConfig`
- `TerminalRuntimeController`
- `TerminalSessionEvent`
- `TerminalViewport`
- `TerminalViewportController`

这里不暴露 `Profile` 这个 app 词汇。session create 主路径使用有版本、带上限的
SessionConfig v1；旧 Profile-shaped wire 只保留在 package 内部的兼容回退中，供新
Dart/旧 native 和旧 Dart/新 native 的升级窗口使用，不把这个兼容债务抛给上层。
通用 session command 则由 `ianvs_terminal` 内部的单一兼容 transport 优先发送有关联
identity 的 Session Request/Response v1；旧 `{kind, ...payload}` 对象只在 capability
缺失时原样回退。operation-specific client 仍拥有各自 payload 和返回语义。
native-to-product 的 Host Request/Response v1 只承载确实需要关联响应的 child 请求；
当前首个 operation 是 OSC 52 `clipboard.read_text`。URL、attention、notification 和
asset transfer 继续保持单向事件或专用通道，不因名字里带 request 就自动归入双向合同。
Frame/Session 运行指标优先使用 Runtime Envelope v1 的 Diagnostic Event 专用形态；旧
debug-stat FFI 只作为双栈兼容面。`terminal.export_diagnostics` 的隐私证据包是独立合同，
不因运行指标迁移而改变。高频 Frame 主路径优先使用带 session identity、sequence 和
timestamp 的 Protobuf Frame Packet v1；只有成功解码和接受的序号才会被确认，确认漂移由
native Snapshot 重同步。旧 Frame Protobuf/JSON 符号继续作为升级兼容面，Frame payload 和
资产传输合同不随外层 packet 改动。decoded RGBA 资产传输优先使用原子 Graphic Asset
Packet v1；Dart 校验 session/asset/version、尺寸和 100 MiB 上限，旧 meta/copy symbols 只在
新 packet symbol 缺失时回退。

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

## App 侧终端状态

当前产品状态边界由 [TERMINAL_PRODUCT_SCOPE.md](TERMINAL_PRODUCT_SCOPE.md)
定义：

- `Profile` 提供可复用启动默认值；
- `Session` 拥有 live PTY 和运行态；
- `Terminal Layout` 只保存 tab/pane topology、焦点和最小 Relaunch Spec；
- `Relaunch Spec` 只保存 `profileId`、可选 command/arguments 和可选 `cwd`；
- `Recording Library` 独立保存录制，不把 recording path 写回重启意图。

`Open Terminal at Folder` 只以所选目录作为新 Session 的初始 `cwd`。它不创建
Project Workspace identity，不切换现有 tab/PTY，也不维护 Recent Workspace。
旧 Workspace v1-v3、project index 和 `workspace` config 只作为单向迁移输入。

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

- `native/core` 仍接受旧 Profile-shaped create wire 和旧 session request wire，但两者都只是
  显式兼容面；产品主路径分别使用 SessionConfig v1 和 Session Request/Response v1。
- Host Request/Response v1 当前只迁移 OSC 52 文本剪贴板读取；旧 Dart/new native 仍走
  `clipboard_paste_request`，new Dart/old native 仍走直接 PTY response，不删除旧 wire。
- Diagnostic Event v1 当前只迁移 `frame_stats` / `session_stats`；旧 Dart/new native 和
  new Dart/old native 仍可使用两个 legacy debug-stat symbols，诊断导出包保持独立。
- Terminal Frame Packet v1 只包装现有 `terminal-frame-diff-v1`；旧 Protobuf/JSON Frame
  symbols、graphic RGBA 和 file-download bytes 均不删除或迁入 packet。
- Graphic Asset Packet v1 只迁移 decoded RGBA 读取；旧 meta/copy symbols 保留，且 null 或
  malformed packet 不在同一次调用中静默降级。file-download 和 Recording wire 不变。
- `example/` 目录里的 Flutter package 现阶段仍保留 `name: app`，这是为了稳定既有 `package:app/...` import 面；macOS bundle identity 由 Runner project 单独维护。
- 本次边界调整不处理 pub.dev 发布、插件系统和跨平台扩展。
- SSH 是延期扩展；若后续实现，只扩展 Profile/Session，不恢复 Project Workspace。
- completion/wiring 诊断面板只在 debug build 的 Toolbelt 中出现；用户诊断导出保持独立。
