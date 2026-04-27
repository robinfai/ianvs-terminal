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
