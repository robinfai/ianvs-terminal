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
flutter test integration_test/flutterm_smoke_test.dart
```

## 运行 demo

```bash
cd example
flutter run -d macos
```

## Local Terminal Manual Matrix

当前 local-only 的 terminal 人工矩阵结果入口固定是
[tasks/verification-gates/T-059-local-terminal-manual-matrix.md](tasks/verification-gates/T-059-local-terminal-manual-matrix.md)。

前置检查最小命令：

```bash
command -v vttest
cd example && flutter devices
osascript -e 'tell application "System Events" to get UI elements enabled'
cd example && flutter test integration_test/flutterm_smoke_test.dart
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
