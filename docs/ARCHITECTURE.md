# flutterm Architecture

这份文档描述当前稳定架构，只在模块边界、核心数据流或长期约束发生变化时更新。

## 目标

当前架构服务于一个非常明确的目标：

- 用最少的复杂度做出一个真实可运行的 terminal 产品原型
- 把 Flutter GUI 和 terminal core 清晰分层
- 让后续 Linux / Windows 接入时尽量复用同一套 UI 和 FFI 协议
- 在不提前实现 native renderer 的前提下，把升级路径留出来

## 分层

### Flutter 层

Flutter 负责所有应用级 GUI：

- tab 管理
- profile 管理
- 顶层布局
- terminal viewport widget
- 复制 / 粘贴 / 选择等桌面交互

当前关键模块：

- `app/lib/features/sessions/`
- `app/lib/features/profiles/`
- `app/lib/features/shell/`
- `app/lib/features/terminal/`
- `app/lib/ffi/flutterm_core.dart`

### Rust core 层

Rust 负责 terminal 运行时的核心能力：

- PTY 创建与进程生命周期
- 本地 shell 启动
- ANSI / VT 解析
- screen state 与 scrollback
- frame diff 与事件输出

当前关键模块：

- `native/core/src/pty.rs`
- `native/core/src/session.rs`
- `native/core/src/model.rs`
- `native/core/src/ffi.rs`

## 数据流

运行时主链路如下：

1. Flutter 通过 profile 创建 session
2. Dart FFI 调用 Rust `create_session`
3. Rust 通过 `portable-pty` 启动本地 shell
4. shell 输出进入 `vt100` parser
5. Rust 从 screen state 生成 `TerminalFrameDiff`
6. Flutter 定时拉取 frame diff 和事件
7. `RenderTerminalViewport` 用 Canvas 绘制当前 viewport

输入方向则相反：

1. Flutter 收到键盘、鼠标、滚轮、粘贴事件
2. Dart 侧把输入编码成字节流或滚动请求
3. FFI 调用 Rust `write` / `scroll` / `resize`
4. Rust 更新 PTY 和 terminal state

## Flutter viewport

当前 terminal viewport 采用 `LeafRenderObjectWidget + RenderBox`，而不是 widget 树堆很多 `Text`。

这样做是为了保证：

- 绘制路径集中
- hit testing 可控
- 光标、选区、背景、文本的重绘粒度可控
- 后续如果替换 renderer，Flutter 外层 API 可以尽量不变

当前绘制策略：

- 只绘制当前可见 viewport
- 文本按行渲染
- 行内按 style run 构建 `Paragraph`
- 用缓存减少重复构建
- 光标和选区由 Canvas 直接绘制

## FFI 契约

当前 FFI 以 C ABI 暴露给 Dart，接口保持最小集：

- `flutterm_ping`
- `flutterm_session_create`
- `flutterm_session_close`
- `flutterm_session_resize`
- `flutterm_session_write`
- `flutterm_session_scroll`
- `flutterm_session_take_frame_diff_json`
- `flutterm_session_poll_events_json`
- `flutterm_string_free`

当前选择 JSON 作为跨语言载体，理由是：

- 首版开发速度快
- 调试简单
- 结构边界清楚

如果后面 frame diff 体积成为瓶颈，再考虑改成更紧凑的二进制协议。

## macOS 打包策略

为了让 `flutter run -d macos` 可运行，Rust 动态库不是直接从仓库目录加载，而是通过 Xcode build phase 打进 app bundle：

- build 时执行 `tools/build_core.sh`
- 将 `libflutterm_core.dylib` 复制到 app bundle 的 `Frameworks` 目录
- 对动态库执行 codesign
- Dart 侧优先从 bundle 内路径加载

这一步是 macOS 运行态成立的关键，因为直接从 repo 目录 `dlopen` 会被 app sandbox 阻断。

## 为什么现在不做 native renderer

当前阶段有意不做 native renderer，原因是：

- 先验证产品是否值得继续
- 先把 session / parser / frame diff 这条链路做稳
- 先用更简单的实现摸清 viewport 实际瓶颈

换句话说，当前优先级是：

- 正确性
- 分层清晰
- 可运行
- 可测试

而不是：

- 极限吞吐
- 极限渲染性能

## 后续跨平台思路

当前实现只支持 macOS，但后续 Linux / Windows 的目标是尽量复用：

- Flutter GUI
- Riverpod 状态层
- `TerminalViewport` 对外行为
- Dart FFI client
- Rust session/core 抽象

预期需要替换或补充的主要是：

- PTY 平台适配
- 构建链
- 少量输入和系统行为差异处理

如果 Flutter Canvas 未来不够用，再引入 native renderer 时也应尽量保持：

- profile 模型不变
- session 生命周期不变
- frame / event 协议尽量兼容

## 当前边界

这份架构文档描述的是当前 MVP，不是最终产品形态。

当前明确不包含：

- SSH 会话链路
- split pane
- 插件化扩展
- renderer backend 抽象
- `wgpu` 或其他 GPU 渲染后端

等本地 shell MVP 稳定后，再决定下一步是：

1. 继续做 terminal 体验
2. 接入 SSH
3. 替换 renderer
