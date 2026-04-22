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
- `T-055` 已于 `2026-04-22` 按 override `forced-closed`，所以 repo 仍缺当前人工验证的 terminal 手工兼容性矩阵（VT220 `vttest`、powerline / ANSI prompt、真实 trackpad scrollback、字体度量 / DPI resize）

## 当前环境相关风险

- 当前最佳已知证据只说明：`BINGHUILUO-MC6` 是 `unsuitable local host`。`command -v vttest`、`flutter doctor -v`、`flutter devices`、`integration_test/flutterm_smoke_test.dart` 均已有 `pass` 证据，但 `flutter run -d macos` 仍打印 `Failed to foreground app; open returned 1`，而且没有完成真实前台键盘交互确认。
- `osascript -e 'tell application "System Events" to get UI elements enabled'` 仍返回 `false`，同时当前 repo 也没有真实 trackpad 与替代字体度量 / DPI 条件的手工结果。因此，VT220、powerline / ANSI prompt、真实 trackpad scrollback、字体度量 / DPI resize 这四条矩阵 lane 目前仍是未执行的已知风险，不是已通过的产品证据。
- 如果未来确实需要补这组人工证据，应新开 focused task，而不是重新激活已经 `forced-closed` 的 `T-055` live handoff。

## 使用建议

- 如果一次改动碰到主链路，请默认做完整 smoke 流程
- 如果某个限制不再成立，应同步更新这里以及 `README.md`
