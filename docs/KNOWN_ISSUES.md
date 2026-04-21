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

- 当前 shell 层已经补上 `no_proxy` / `NO_PROXY=127.0.0.1,localhost,::1`，并提供 `flutterm_no_proxy` helper；在该 no-proxy 会话下，`vttest` 已可直接解析到 `/opt/homebrew/bin/vttest`，`flutter run -d macos` 也能稳定建立本地 Dart VM Service 和 app 进程。但 Flutter tool 仍可能同时打印 `Failed to foreground app; open returned 1`，说明当前 blocker 已经从“代理和工具缺失”收窄到“Flutter tool 前置台/会话判定异常”，而不是 terminal 产品回归。
- `flutterm_no_proxy flutter run -d macos --host-vmservice-port 49200` 的固定端口重试显示：即使 Flutter tool 仍报告 foreground failure，运行中的 app 仍可能已经是 frontmost 且 `visible=true`。因此，当前环境问题更像是前置台检测竞态或工具链误报；在没有完成人工键盘输入确认之前，不能直接把当前机器判成 `usable for real GUI smoke`。
- 同一环境下偶发 Flutter `HardwareKeyboard` 重复 `KeyDownEvent` 断言（已观察到 `Backspace` 与 `Y`），异常发生在框架键盘状态校验阶段。`2026-04-22` 的 no-proxy preflight 和固定端口 `flutter run` 都未再次复现该断言，但由于当前仍未完成一次已确认键盘输入的前台 terminal 会话，这个风险暂时仍只能继续视为间歇性环境 / Flutter 输入链路风险，后续如持续复现需独立排查。

## 使用建议

- 如果一次改动碰到主链路，请默认做完整 smoke 流程
- 如果某个限制不再成立，应同步更新这里以及 `README.md`
