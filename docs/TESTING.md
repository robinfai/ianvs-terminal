# flutterm Testing

这份文档只保留当前工作区真实可用的验证入口。

## 默认顺序

```bash
cd native/core
cargo fmt --check
cargo test
```

```bash
cd packages/flutterm_pty
dart test
```

```bash
cd packages/flutterm_terminal
flutter test
```

```bash
cd example
flutter analyze
flutter test
flutter test -d macos integration_test/flutterm_smoke_test.dart
```

当前 macOS smoke 显式指定 `-d macos`。在本机不指定 device 时，
Flutter 可能先进入 Android `adb devices` discovery 并卡住；这不是
flutterm 产品回归。

## 运行 demo

```bash
cd example
flutter run -d macos
```

## Local Terminal Manual Matrix

当前 local-only 的 terminal 人工矩阵结果入口固定是
[tasks/verification-gates/T-059-local-terminal-manual-matrix.md](tasks/verification-gates/T-059-local-terminal-manual-matrix.md)。

## vttest-derived 自动化覆盖

可机器断言的 `vttest` 场景不要依赖交互式 `vttest` 菜单本身；把对应 VT 序列收成自动化回归测试：

```bash
cd native/core
cargo test --test vttest_regression_test
cargo test vt220

cd ../../example
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport repaints consecutive full-width wrapped rows without leaving a shorter middle row"
```

这些测试覆盖 VT220/vttest 类 screen-features 的 autowrap、terminal reports、已知 wrap-around 回归，以及 Flutter viewport 对连续满宽 wrapped rows 的重绘。真实 app 前台、macOS shortcut 抢键、trackpad/DPI 这类依赖宿主 GUI 的项仍保留在 `T-059` 人工矩阵。

## vttest GUI nightly/manual gate

真实 macOS GUI + 真实 PTY + 真实 `vttest` 的完整链路入口：

```bash
./tools/vttest_gui_nightly.sh
./tools/vttest_gui_nightly.sh --release-gate
```

这条 gate 分三层：

- fast deterministic regression：`cargo test --test vttest_regression_test`、`cargo test vt220`、Flutter wraparound viewport 单测
- GUI full-chain vttest：`flutter test -d macos integration_test/vttest_gui_test.dart`，使用真实 `NativePtyBackend` 和 VT220 profile 启动 `vttest`
- still manual：真实 trackpad、DPI/font-metric 切换、以及外部宿主条件仍按 `T-059` 人工矩阵记录

默认模式下，缺少 macOS GUI session、`vttest`、或 macOS Flutter device 会生成 `blocked` summary 并退出 0；`--release-gate` 下同样的前置缺失退出 2。产品断言或构建/测试失败始终退出 1。结果写到 `build/vttest-gui-nightly/<timestamp>/summary.json`，GUI 测试日志固定为同目录下的 `flutter-test.log`。

前置检查最小命令：

```bash
command -v vttest
cd example && flutter devices
osascript -e 'tell application "System Events" to get UI elements enabled'
cd example && flutter test -d macos integration_test/flutterm_smoke_test.dart
cd example && flutter run -d macos
```

如果改动触达以下任一边界，除了自动化验证，还要重新跑 `T-059` 对应的人工 lane：

- terminal emulation / VT220 行为
- app-vs-session shortcut routing
- 真实 trackpad / scrollback 行为
- viewport scroll / return-to-bottom 行为

## 脚本入口

```bash
./tools/verify_flutter_terminal.sh
```

这个脚本会先构建并验证 `native/core`，再跑 `packages/flutterm_pty`、`packages/flutterm_terminal`、`example` 的默认验证链路，并用 `grep` 守住 Phase 3 的单一 defaults 写入口约束。

## 按边界挑命令

- 只改 `packages/flutterm_pty`
  - `cd native/core && cargo test`
  - `cd packages/flutterm_pty && dart test`
- 只改 `packages/flutterm_terminal`
  - `cd packages/flutterm_terminal && flutter test`
- 只改 `example/`
  - `cd example && flutter analyze`
  - `cd example && flutter test`
- 改动跨越 FFI、runtime、viewport 或 shell
  - 全部默认顺序都跑
- 改动跨越 emulation、shortcut routing、trackpad scrollback 或 viewport scroll 行为
  - 默认顺序之外，再看 `T-059` 对应的人工矩阵 lane
