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

- 当前文档里曾假设 `flutterm_no_proxy` helper 已可直接使用，但 `2026-04-22 10:09 CST` 的当前会话实际返回 `flutterm_no_proxy not found`。因此，本机取证现在必须使用显式 no-proxy 环境变量；helper 缺失属于当前 host 事实，不是 terminal 产品行为。
- `2026-04-22 11:11 CST` 的显式 no-proxy preflight 显示：host `BINGHUILUO-MC6`、macOS `26.3.1 (25D771280a)`、`flutter doctor -v` / `flutter devices` / `integration_test/flutterm_smoke_test.dart` 都已 `pass`，`command -v vttest` 也已恢复为 `pass`，但 `flutter run -d macos` 仍打印 `Failed to foreground app; open returned 1`，即使 Dart VM Service、app bundle 和 app 进程都已出现。这说明当前 host 的剩余问题已经收窄到前置台与交互确认，而不是工具缺失或 terminal 产品回归。
- 当前会话的 `osascript -e 'tell application "System Events" to get UI elements enabled'` 返回 `false`。再结合 `2026-04-22 10:11 CST` 的固定端口 `flutter run -d macos --host-vmservice-port 49200` 结果可知：app 进程已启动、VM Service 可用、`visible=true`，但本机会话仍没有可用的辅助访问权限来完成 viewport 点击和键盘输入确认。基于这组证据，当前机器仍应被视为 `unsuitable local host`，不应继续承担 `T-055` 的完成责任。
- Flutter `HardwareKeyboard` 重复 `KeyDownEvent` 风险这轮没有再次复现，但由于 `y` / `Backspace` / `pwd` / `echo hello` / `ls` 这条最小输入链根本没有完成，风险也不能视为已收敛；后续若在可交互前台会话里再次出现，仍应单开环境排障任务。

## 使用建议

- 如果一次改动碰到主链路，请默认做完整 smoke 流程
- 如果某个限制不再成立，应同步更新这里以及 `README.md`
