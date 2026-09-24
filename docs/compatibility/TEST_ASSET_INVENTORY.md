# Compatibility Test Assets

本页列出当前可执行的兼容性测试入口，不保存某次运行结果或易过期的测试数量。
命令说明以 [TESTING](../TESTING.md) 为准。

| 层 | 当前测试 | 覆盖与边界 |
| --- | --- | --- |
| Rust native/session | [native tests](../../native/core/tests/) | 真实 PTY、生命周期、frame、OSC corpus、VT220、resize、SSH/SFTP 和 ZMODEM |
| Vendored parser | [parser source/tests](../../native/vendor/par-term-emu-core-rust/src/) | Unicode、CSI/OSC/DCS、Sixel、Kitty；不等于完整产品 E2E |
| Dart FFI | [PTY tests](../../packages/ianvs_pty/test/) | 当前 ABI 的 typed contracts、边界与错误处理 |
| Flutter runtime/viewport | [terminal tests](../../packages/ianvs_terminal/test/) | 帧解码、调度、输入、焦点、graphics、录制与回放 |
| App unit/widget | [example tests](../../example/test/) | 产品策略、session/layout、Profile、同步与平台桥接 |
| App integration | [integration tests](../../example/integration_test/) | macOS 真实 PTY、SSH、启动与外部 TUI；需要对应设备/fixture |
| Repository contracts | [root tests](../../test/) | 当前文档入口、协议示例、发布和跨层静态合同 |
| Benchmarks | [benchmark tests](../../tools/bench/test/) | 确定性 workload 与性能门禁行为；不代表跨机器性能保证 |

## 可复用验证入口

- [Makefile](../../Makefile)：`bootstrap`、`analyze`、`test`、`verify`。
- [全链路 verifier](../../tools/verify_flutter_terminal.sh)。
- [vttest GUI gate](../../tools/vttest_gui_nightly.sh)：需要外部二进制、macOS GUI 与 Flutter device。
- [manual prerequisites](../../tools/check_terminal_manual_matrix_prereqs.sh)。
- [release refresh gate](../../tools/run_release_real_pty_refresh_gate.sh)。
- [CI benchmark config](../../tools/bench/configs/bench_ci_smoke.yaml)。
- [OpenSSH fixture](../../tools/ssh_e2e/README.md) 和 [ZMODEM fixture](../../tools/zmodem_e2e/README.md)。

## 固定输入

- [real PTY acceptance](../../example/integration_test/real_pty_acceptance_test.dart)：shell 生命周期、
  alternate-screen TUI、Unicode/width 与 resize；确定性 TUI fixture 不依赖 `vttest`。
- [session regression tests](../../native/core/tests/session_test.rs)：resize/reflow 与截断边界。
- [OSC corpus](../../native/core/tests/fixtures/osc/osc_protocol_corpus_v1.json)。
- [recording fixtures](../../packages/ianvs_terminal/test/fixtures/recording/) 与
  [当前录制合同](../recording/FORMAT_CURRENT.md)。

字体、DPI、实体键盘、IME、trackpad 与系统效果按
[人工检查表](MANUAL_VERIFICATION.md) 验证。运行产物留在 `build/` 或临时目录；
存在测试源码不等于当前宿主已经执行通过。
