# ianvs terminal Known Issues

这份文档只记录当前已接受的限制、缺口和临时取舍。

## 当前已知边界

- 当前只支持 macOS
- 当前只支持 local shell
- 还没有 SSH 会话链路
- scrollback 搜索目前只支持本地纯文本搜索
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
- local-only terminal 手工矩阵已于 `2026-05-06` 在 `T-059` 实际执行，但当前仍有未修复的真实失败项，不能把这轮结果当成“全部通过”
- local-terminal P0-P5 当前已有计划、竞品映射、核心 wiring、诊断和测试脚手架。`2026-05-16` 这轮已经记录 `dart format`、`flutter analyze` 和 focused automated tests 的通过证据；当前仍缺 `broader` 最后修复后的重跑、integration/smoke evidence、manual gates，以及把这些结果转换成 canonical verification evidence，因此不能把当前状态当成已完成。

## 当前环境相关风险

- `flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart` 当前可以通过，但运行时仍会打印 `Failed to foreground app; open returned 1`。这说明 smoke 已覆盖基本启动链路，但 foreground 行为仍不够干净。
- 默认 verification helper 现在用 `flutter test -d macos ...` 运行 integration smoke，避免当前 host 卡在 Flutter device discovery 的 Android `adb devices` 路径；手工 ad-hoc 跑 integration smoke 时仍不要省略 `-d macos`。这属于本机验证环境风险，不是 terminal 产品回归。
- `osascript -e 'tell application "System Events" to get UI elements enabled'` 仍返回 `false`。当前这不再阻止 `T-059` 的人工矩阵结论成立，但它仍是本地 GUI 自动化和辅助访问验证的环境风险。

## 当前真实产品缺口

- 真实 trackpad 的惯性滚动和 return-to-bottom 行为仍失败。

## 当前已接受的延期风险

- `2026-04-23` 决定先不处理宽字符和组合字符的真实终端列宽。当前 `TerminalTextCells.fromText(...)` 仍按 rune 计列，所以像 `你`、部分 emoji、组合字符这类内容，仍可能把 style run、cursor、selection、导出的列坐标带偏。当前这轮只保证非 BMP 单字符不会再被 UTF-16 下标切坏，没有把真实终端列宽问题一起收掉。
- `2026-04-23` 决定先不把 `ps1 diag export` 接到真实 live shell prompt。当前导出链默认仍基于 repo 内固定 fixture，所以 `ps1-current.png`、`shell-surface-current.png` 适合做稳定回归和几何排查，不等于真实用户会话截图。拿它和 Kaku 对比时，要把这个限制算进结论里。

## 使用建议

- 如果一次改动碰到主链路，请默认做完整 smoke 流程
- 如果某个限制不再成立，应同步更新这里以及 `README.md`
