# flutterm Known Issues

这份文档只记录当前已接受的限制、缺口和临时取舍。

## 当前已知边界

- 当前只支持 macOS
- 当前只支持 local shell
- 还没有 SSH 会话链路
- 还没有 split pane
- 还没有全文搜索
- 还没有 sync
- 还没有插件系统
- 当前没有 native renderer
- 当前没有 `wgpu` renderer

## 当前技术取舍

- terminal viewport 先使用 Flutter Canvas，而不是 native renderer
- Flutter 与 Rust 当前通过 JSON frame diff / event 交互
- macOS 运行依赖把 Rust 动态库打进 app bundle
- 为了让本地 shell MVP 可运行，当前没有启用 app sandbox

## 当前缺少的非功能性保障

- 还没有正式性能基线
- 还没有自动化性能回归检查
- 还没有跨平台验证
- 还没有 SSH 兼容性验证
- 还没有稳定执行的 terminal 手工兼容性矩阵（VT220 `vttest`、powerline / ANSI prompt、真实 trackpad scrollback、字体度量 / DPI resize）

## 当前环境相关风险

- 在当前受限的 macOS 运行环境里执行 `flutter run -d macos` 时，应用仍可能打印 `Failed to foreground app; open returned 1`。`2026-04-21 14:52 CST` 的 preflight 复跑里 app 已成功构建并附着 Dart VM Service，但 60 秒内仍未能稳定前置到可交互桌面，因此 terminal 主链路任务暂时不能在这里完成真实 GUI smoke。这类 `blocked` 结论应继续归入环境排障，不应记成 terminal 产品回归。
- 当前常用开发环境未默认提供 `vttest`，VT220 手工矩阵依赖额外工具准备；当前已确认 Homebrew 提供标准安装入口，可用 `brew install vttest` 作为标准开发机准备路径。执行 `T-055` 的目标机器还需要真实可交互桌面、physical trackpad，以及至少一组替代字体或 DPI 条件。
- 同一环境下偶发 Flutter `HardwareKeyboard` 重复 `KeyDownEvent` 断言（已观察到 `Backspace` 与 `Y`），异常发生在框架键盘状态校验阶段。`2026-04-21` 的非交互式 `flutter run -d macos` 复跑未再次触发该断言，但因为前置台问题仍阻塞真实键盘交互，这个风险暂时只能继续视为间歇性环境 / Flutter 输入链路风险，后续如持续复现需独立排查。

## 使用建议

- 如果一次改动碰到主链路，请默认做完整 smoke 流程
- 如果某个限制不再成立，应同步更新这里以及 `README.md`
