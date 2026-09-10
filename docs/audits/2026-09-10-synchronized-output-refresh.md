# Claude Code 历史输入刷新修复

## 已确认问题

2026-09-10 的本地录制显示，历史内容在输入后约 11 毫秒已到达 PTY，
但输入行必须等下一次输出才显示。用已安装 Trail 的原生库复现了两个原因：

1. vendored `par-term-emu-core-rust` 的 DEC 2026 扫描器逐字节识别 C1 控制码，
   将“来”（UTF-8 `E6 9D A5`）的续字节当成 OSC 起始符，漏掉同步输出结束标记。
2. `Session::take_frame_diff` 在同步输出超时后未收集新产生的网格变更。
   当输入行与最终光标行不同，增量帧返回 0 个文本行，直到后续输出收集这些变更。

该依赖缺陷影响本项目中文/Unicode 终端输出和录制回放。修复在当前 vendored
依赖中维护跨块 UTF-8 扫描状态，并在会话超时路径收集网格、光标和滚动变更。
独立发布包通过 `tools/sync_terminal_core.dart` 同步。

## 验收范围

- 中文及包含 C1 值续字节的 Unicode 文本，在正常同步结束后立即产生帧。
- 分块输入、原始 C1 序列、控制字符串中的伪同步标记和回放快照保持正确。
- 缺少结束标记时，无需后续输入，超时即更新非光标行；滚动和全屏变更保持完整。
- 使用原始录制的输出与时间间隔，在新构建原生库上验证两次历史回填。
- 执行原生格式、静态检查、测试和发布包同步检查，记录实际结果。

原始录制含用户会话内容，不提交到仓库。

## 验收结果

2026-09-10 完成本次修复范围的自动化验收：

| 检查 | 结果 |
| --- | --- |
| 新增同步输出回归测试 | 8 项通过，覆盖逐字节/任意二分分块、快照恢复、真实 C1、控制字符串中的伪标记、非光标行超时更新和滚动/全屏变更 |
| 原生 core 完整测试 | 940 项通过，0 失败；4 项专用 Docker/Colima SSH、ZMODEM 测试按原配置忽略 |
| vendored 终端库完整测试及文档测试 | 1752 项通过，0 失败，2 项按原配置忽略 |
| Flutter 运行时、回放控制器、viewport 渲染测试 | 294 项通过 |
| core 与 vendored 终端库 Clippy | 使用 CI 固定的 Rust 1.88.0，全部通过；vendor 保留项目原有 `uninlined_format_args` 例外 |
| Rust 格式、差异空白与独立发布包镜像检查 | 通过 |
| 原生动态库构建及构建产物冒烟 | 通过；中文完整批次立即产生文本帧，未结束批次超时后无需新输出即可更新非光标行 |
| 原始录制逐事件 FFI 回放 | 原始字节和时间间隔保持不变；初始快照与两次历史回填均通过 |

原始录制事件 #24（7.962151 秒）和 #68（24.914528 秒）到达后，立即请求的
Protobuf 帧均包含完整历史文本和 2 个变更行。无需喂入下一次输入或输出。
初始快照 #1 直接输出 22 行，不再需要移除人工快照的同步包裹。
录制 SHA-256：`8f50b1b7634f2e7224f60e927ca542b4312f39eb2bc435aaa79dd194bb3e2eb3`。
本次逐事件回放使用测试构建的动态库，SHA-256：
`0ea8af7e1a2a06d1d33ecb629e65f6f5ce37257a39ec6347a6e4037cb2c6b569`。

主要可重复命令：

```sh
cargo fmt --manifest-path native/core/Cargo.toml --check
cargo fmt --manifest-path native/vendor/par-term-emu-core-rust/Cargo.toml --check
cargo +1.88.0 clippy --manifest-path native/core/Cargo.toml --locked --all-targets -- -D warnings
cargo +1.88.0 test --manifest-path native/core/Cargo.toml --locked -- --test-threads=1
cargo +1.88.0 clippy --manifest-path native/vendor/par-term-emu-core-rust/Cargo.toml --locked --all-targets -- -D warnings -A clippy::uninlined_format_args
cargo +1.88.0 test --manifest-path native/vendor/par-term-emu-core-rust/Cargo.toml --locked -- --test-threads=1
cargo +1.88.0 build --manifest-path native/core/Cargo.toml --locked
dart run tools/sync_terminal_core.dart --check
cd packages/ianvs_terminal
flutter test test/terminal_runtime_controller_test.dart test/terminal_replay_controller_test.dart test/terminal_viewport_render_test.dart
```

完整原生测试需要本机回环端口权限。首次沙箱执行的 4 个监听权限错误在授权环境
重跑后全部通过。默认 Rust 1.97 的新增告警未作为本次 CI 结论；使用项目固定版本。
另对原有图像重绘测试的 `format!` 参数做等价内联，解决 Rust 1.88 的既有 Clippy
告警，生成的测试脚本保持一致。

本次验收到达原生输出、帧协议与 Flutter 组件层；未执行完整 macOS GUI 旅程，
未重新安装应用，也未执行与本改动无关的后端、WebUI 或专用 SSH/ZMODEM 部署验收。
