# ianvs terminal Testing

这份文档只保留当前工作区真实可用的验证入口。

## 文档与执行目标契约

```bash
dart test test/docs_contract_test.dart
```

该测试会校验 `docs/CURRENT_EXECUTION_TARGETS.json` 的唯一 active lane、状态字段、
证据文件和关键 token，同时检查权威文档入口里的本地 Markdown 链接。它只能证明
目标描述与仓库静态证据仍一致，不能替代后续代码测试、macOS integration 或人工 QA。

## 默认顺序

```bash
cd native/core
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```

## Compatibility Baseline (Iteration 01)

兼容性基线的权威证据入口：

- [compatibility/CAPABILITY_MATRIX.md](compatibility/CAPABILITY_MATRIX.md)
- [compatibility/TEST_ASSET_INVENTORY.md](compatibility/TEST_ASSET_INVENTORY.md)
- [compatibility/KNOWN_ISSUES.md](compatibility/KNOWN_ISSUES.md)
- [compatibility/MANUAL_VERIFICATION.md](compatibility/MANUAL_VERIFICATION.md)

完整基线必须按顺序执行并在
[T-302](tasks/verification-gates/T-302-compatibility-baseline.md) 回填真实结果：

```bash
make bootstrap
make analyze
make test
make verify
```

Resize Replay 的聚焦诊断门禁：

```bash
cd native/core
cargo test --test session_test session_reflows_single_long_line_across_resize -- --exact
cargo test --test session_test scrollback_heavy_transcript_is_bounded_and_resize_still_returns_snapshot -- --exact
```

真实 PTY、alternate-screen TUI 和 Unicode/Width/Cursor 聚焦门禁：

```bash
cd example
flutter test -d macos integration_test/real_pty_acceptance_test.dart \
  --plain-name "real PTY shell starts, accepts input, emits output, and exits"
flutter test -d macos integration_test/real_pty_acceptance_test.dart \
  --plain-name "real PTY alternate-screen TUI starts, resizes, accepts input, and exits"
flutter test -d macos integration_test/real_pty_acceptance_test.dart \
  --plain-name "real PTY OSC 1337 UnicodeVersion changes visible columns and survives resize input"
```

真实 `vttest` 是补充 GUI/nightly gate；缺少外部二进制时必须记为 `blocked`，不能
替代或否定上面的确定性 alternate-screen TUI 门禁。

Shell integration 改动的最小聚焦验证：

```bash
cd native/core
cargo test shell_hook_integration
cargo test diagnostics_export_reports_shell_integration_gate_status
```

这些测试覆盖 hook 注入、禁用/降级 reason，以及 diagnostics export 中
`started.payload.shell_integration` 的可见状态。

```bash
cd packages/ianvs_pty
dart analyze --fatal-infos
dart test
```

```bash
cd packages/ianvs_terminal
flutter analyze --fatal-infos
flutter test
```

Terminal frame diff wire schema/corpus 的聚焦验证：

```bash
cd packages/ianvs_terminal
flutter test test/terminal_frame_diff_corpus_test.dart
```

Terminal idle refresh 的单调 deadline 与诊断聚焦验证：

```bash
cd packages/ianvs_terminal
flutter test test/terminal_frame_pump_test.dart
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime traces skipped ticks and full refresh lifecycle monotonically"
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime resets deadline state after input and resize"
```

刷新诊断使用 `ianvs-terminal-refresh-policy-v1`，只写入可选的 benchmark
event sink，不进入 frame JSON/protobuf。它记录 skipped tick、full poll request、
refresh start、frame take/apply 和 refresh result；deadline 固定为
132/264/396ms，最大等待不会继续指数增长。

```bash
cd example
flutter analyze --fatal-infos
flutter test
flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart
flutter test -d macos integration_test/real_pty_acceptance_test.dart
```

当前 macOS integration gates 显式指定 `-d macos`。在本机不指定
device 时，Flutter 可能先进入 Android `adb devices` discovery 并卡住；
这不是 ianvs terminal 产品回归。

## 本地 macOS Release 签名与启动

无有效 codesigning identity 的开发机上，`flutter build macos --release`
会生成 ad-hoc 签名的 app 和嵌入 framework。启用 hardened runtime 后，这些
签名没有共同 Team ID，直接启动会被 macOS library validation 拒绝。构建正式
Release 主应用后，运行：

```bash
cd example
flutter build macos --release
cd ..
./tools/sign_local_macos_release.sh \
  "example/build/macos/Build/Products/Release/Ianvs Terminal.app"
```

`make build-macos` 默认生成具备同步 Keychain 权限的 profile-signed 构建，
因此需要在 Xcode 中登录 Apple Developer 账号，并安装匹配
`dev.ianvs.terminal.dev` 的 Apple Development 证书和 provisioning profile。

只验证本地终端、不使用远程数据服务和跨设备主密钥同步时，可以显式选择
ad-hoc 模式：

```bash
make build-macos MACOS_BUNDLE_ID=
```

该模式不要求 Xcode 账号，但不具备 iCloud Keychain entitlement；应用中的
自动主密钥同步和依赖它的远程数据服务恢复不可用。

该脚本只在检测到 ad-hoc app 时加入本地 library-validation 例外，同时保留
hardened runtime 并执行深度验签。若 app 已有证书签名，脚本不会重签。
`Runner/Release.entitlements` 不包含这个本地例外，因此分发签名的 Release
仍保留 library validation。Release 真实 PTY 刷新门禁会自动执行同一处理：

```bash
./tools/run_release_real_pty_refresh_gate.sh
```

## 运行 demo

```bash
cd example
flutter run -d macos
```

## Local Terminal Manual Matrix

当前 local-only 的 terminal 人工矩阵结果入口固定是
[tasks/verification-gates/T-059-local-terminal-manual-matrix.md](tasks/verification-gates/T-059-local-terminal-manual-matrix.md)。

## Local Terminal P0-P5 final verification

当前 local-terminal P0-P5 收尾验证入口固定为：

- [LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md](LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md)
- [LOCAL_TERMINAL_VERIFICATION_AUTHORIZATION_GATE_2026-05.md](LOCAL_TERMINAL_VERIFICATION_AUTHORIZATION_GATE_2026-05.md)
- [LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md](LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md)
- [LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md](LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md)
- [LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md](LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md)

只查看入口，不运行验证：

```bash
bash tools/local_terminal_verification_status.sh
```

可先打印自动化命令批次，不执行：

```bash
bash tools/local_terminal_verification_batches.sh print all-automated
```

显式获准后再运行自动化批次：

```bash
bash tools/local_terminal_verification_batches.sh run all-automated
```

如果需要捕获输出方便回填 ledger：

```bash
bash tools/local_terminal_verification_capture.sh run all-automated
```

capture wrapper 会在 `build/local-terminal-verification/` 下写出 `output.log`、
`summary.txt` 和 `ledger-entry.md`。脚本不会自动更新 evidence ledger。所有真实命令输出和人工观察结果都必须写回
[LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md](LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md)。

## vttest-derived 自动化覆盖

可机器断言的 `vttest` 场景不要依赖交互式 `vttest` 菜单本身；把对应 VT 序列收成自动化回归测试：

```bash
cd native/core
cargo test --test vttest_regression_test
cargo test vt220 -- --test-threads=1

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

- fast deterministic regression：`cargo test --test vttest_regression_test`、串行执行的 `cargo test vt220 -- --test-threads=1`、Flutter wraparound viewport 单测；VT220 用例密集创建 PTY，串行化可避免并发 `openpty` 引发宿主资源竞争，但不会重试或放宽产品断言
- GUI full-chain vttest：`flutter test -d macos integration_test/vttest_gui_test.dart`，使用真实 `NativePtyBackend` 和 VT220 profile 启动 `vttest`
- still manual：真实 trackpad、DPI/font-metric 切换、以及外部宿主条件仍按 `T-059` 人工矩阵记录

默认模式下，缺少 macOS GUI session、`vttest`、或 macOS Flutter device 会生成 `blocked` summary 并退出 0；`--release-gate` 下同样的前置缺失退出 2。产品断言或构建/测试失败始终退出 1。结果写到 `build/vttest-gui-nightly/<timestamp>/summary.json`，GUI 测试日志固定为同目录下的 `flutter-test.log`。

前置检查最小命令：

```bash
command -v vttest
cd example && flutter devices
osascript -e 'tell application "System Events" to get UI elements enabled'
cd example && flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart
cd example && flutter run -d macos
```

如果改动触达以下任一边界，除了自动化验证，还要重新跑 `T-059` 对应的人工 lane：

- terminal emulation / VT220 行为
- app-vs-session shortcut routing
- 真实 trackpad / scrollback 行为
- viewport scroll / return-to-bottom 行为

## Real PTY acceptance gate

当前 manual checklist 中可稳定机器断言的真实 PTY 行为，集中在：

```bash
cd example
flutter test -d macos integration_test/real_pty_acceptance_test.dart
```

这条 gate 使用真实 `NativePtyBackend`、真实 `/bin/sh` profile 和真实
terminal frame/event 通道，覆盖：

- 默认 shell 视图隐藏 line timestamp overlay
- shell-hook DCS 触发的 profile 自动切换与 baseline 恢复
- password manager stale prompt 发送拦截
- trigger 对真实重复 prompt 的 send-text 响应
- coprocess 对真实重复 prompt 的 response
- wrapped 输出下的 trigger notification 与 captured output 逻辑行拼接
- inactive tab wrapped 输出下的 activity notification 逻辑行拼接
- 子进程真实空闲四秒后，通过 FIFO 注入输出的 33ms active、264ms background
  deadline 与 396ms maximum-backoff 唤醒基线；测试打印原始微秒值并分别守住
  250/750/750ms 硬门槛

仍保留人工 smoke 的项：真实 macOS 系统通知弹窗权限、Powerline 在实际字体/DPI
组合下的观感、真实 trackpad/窗口拖拽/显示器切换等宿主 GUI 行为。

## 脚本入口

完整入口会验证 vendored ZMODEM 的 `no_std` 构建。首次运行前需要安装对应
Rust target（CI 也显式安装该 target）：

```bash
rustup target add thumbv7em-none-eabihf
```

脚本会在执行功能测试前检查这个前置条件，并给出上述安装命令。

```bash
./tools/verify_flutter_terminal.sh
```

这个脚本会先构建并验证 `native/core`，再跑 `packages/ianvs_pty`、`packages/ianvs_terminal`、`example` 的默认验证链路，并用 `grep` 守住 Phase 3 的单一 defaults 写入口约束。Dart/Flutter analyze gate 使用 `--fatal-infos`，因此 info 级诊断也会阻断 CI。`example` 默认同时运行模块化测试目录和 `example/test/widget_test.dart` 中的完整 Shell Widget 回归。脚本还会执行 `tools/bench/configs/bench_ci_smoke.yaml`，用确定性 workload 检查 frame diff hash、schema gate、`p95_frame_build_micros`、`p95_json_decode_micros` 和 `p95_apply_frame_micros` 上限，并写出 `os_resource.ndjson` / `p95_process_cpu_percent` / `peak_process_rss_bytes` 作为 CPU/RSS 可观测基线。资源阈值可通过 benchmark config 的 `max_p95_process_cpu_percent` 和 `max_peak_process_rss_bytes` 打开；普通 smoke 默认只采样，不把宿主负载波动作为失败条件。
脚本末尾会顺序执行 macOS smoke 与 real PTY acceptance，覆盖启动级 UI
路径和真实 `NativePtyBackend` / shell frame-event 路径。

夜间或安静宿主资源门禁可以在同一脚本里显式打开：

```bash
VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH=1 ./tools/verify_flutter_terminal.sh
```

这会额外运行 `tools/bench/configs/bench_nightly_resource.yaml`。该配置覆盖
`idle.quiet`、持续输出、scrollback-heavy 和 resize churn workload，并启用
`max_p95_process_cpu_percent` / `max_peak_process_rss_bytes` 资源阈值。它适合作为
nightly/quiet-host gate；跨机器可比的长期基线仍需要单独记录宿主信息和历史结果。

需要在非 GUI CI 或快速本地验证中跳过 macOS integration 时：

```bash
VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION=1 ./tools/verify_flutter_terminal.sh
```

这个模式仍会跑 Rust、Dart/Flutter package、example 模块化单测与完整 Shell Widget 回归、analyze、Phase 3 grep gate 和 benchmark CI smoke，只跳过 `flutter test -d macos integration_test/...` 两条真实 app integration gate。Kitty POSIX shared memory 专项 Rust 测试在受限宿主上会明确打印 skip；夜间或真机验证若必须证明该路径，请设置 `IANVS_REQUIRE_POSIX_SHM_TESTS=1`，让宿主不支持 `shm_open` 时直接失败。

## 按边界挑命令

- 只改 `packages/ianvs_pty`
  - `cd native/core && cargo clippy --all-targets -- -D warnings`
  - `cd native/core && cargo test`
  - `cd packages/ianvs_pty && dart analyze --fatal-infos`
  - `cd packages/ianvs_pty && dart test`
- 只改 `packages/ianvs_terminal`
  - `cd packages/ianvs_terminal && flutter analyze --fatal-infos`
  - `cd packages/ianvs_terminal && flutter test`
- 只改 `example/`
  - `cd example && flutter analyze --fatal-infos`
  - `cd example && flutter test`
- 改动跨越 FFI、runtime、viewport 或 shell
  - 全部默认顺序都跑
- 改动跨越 emulation、shortcut routing、trackpad scrollback 或 viewport scroll 行为
  - 默认顺序之外，再看 `T-059` 对应的人工矩阵 lane
