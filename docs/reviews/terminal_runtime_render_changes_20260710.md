# Ianvs Terminal 运行时与渲染变更记录

日期：2026-07-11（Asia/Shanghai）

基线：`4b19f04`

最终受评代码：`63b445e9b8d8277151bffeb4e5eab8d5806bb1de`

## 变更概览

本分支相对基线修改 77 个文件，主要覆盖 terminal refresh、render/graphics cache、cursor 实验与回退、runtime coordinator、JSON/Protobuf transport、macOS integration lifecycle、本地 Release hardening、benchmark 和回归测试。

最终生产行为没有启用 cursor overlay。该实验的代码曾在中间提交中存在，但最终提交完整回退，只保留 gate、报告逻辑和 NO-GO 证据。

## 提交清单

| SHA | 角色/结果 |
| --- | --- |
| `a81b1403` | preflight：恢复 macOS Release hardened runtime |
| `4265e752` | 设计：固定运行时/渲染评审边界与停止条件 |
| `6fd8b125` | 计划：七个 phase 与最终双门禁 |
| `aaf51924` | preflight test：旧 widget coverage 对齐当前 shell UI |
| `9d73ae2a` | refresh：约束并记录 idle refresh/backoff |
| `279ee407` | refresh：可选 native hint 与 fallback |
| `fb8d6e75` | render：减少绘制分配抖动 |
| `ec204b18` | graphics：revision 驱动 cache 同步 |
| `c1d83e27` | cursor 实验：加入可测 overlay 候选 |
| `462666aa` | benchmark：空 wire-format label 修正 |
| `1a05d4d2` | coordinator：隔离 frame pump、focus、graphics sync |
| `9de20a6f` | transport：隔离 decoder facade 与 wire coordinator |
| `a9ecf908` | benchmark：过滤 transport frame metrics |
| `efbb110c` | Release：本地临时签名保留 hardening |
| `d0ba7f02` | macOS smoke：hidden lifecycle 受控恢复 |
| `eac57d25` | macOS integration：共享 lifecycle recovery helper |
| `63b445e9` | cursor 最终决策：回退未证实收益的 overlay |

## Refresh 与 frame pump

主要文件：

- `native/core/src/session.rs`
- `native/core/src/ffi.rs`
- `packages/ianvs_pty/lib/src/native_pty_backend.dart`
- `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart`
- `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump_controller.dart`
- `packages/ianvs_terminal/lib/src/runtime/terminal_refresh_policy.dart`
- `packages/ianvs_terminal/lib/src/runtime/terminal_refresh_scheduler.dart`
- `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`

行为变化：

- native 暴露轻量 refresh hint capability。
- Dart pump 根据 active/background、hint、空刷新次数和 hard ceiling 选择下一次 deadline。
- hint 缺失或被 mask 时继续使用有界 fallback。
- input、resize、activation 与 session lifecycle 会更新交互状态并重置 backoff。
- metrics 记录 empty refresh、backoff skip、current delay、refresh class 和 hint/fallback 决策。

兼容边界：不支持新 capability 的 backend 不需要改变；JSON-only 和旧 backend 继续可用。

## Render、graphics 与 cursor

主要文件：

- `packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart`
- `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
- `packages/ianvs_terminal/lib/src/terminal/terminal_models.dart`
- `packages/ianvs_terminal/lib/src/terminal/terminal_graphics_cache.dart`
- `packages/ianvs_terminal/lib/src/terminal/terminal_graphics_sync.dart`
- `packages/ianvs_terminal/lib/src/terminal/terminal_focus_reporter.dart`

最终保留的变化：

- row visual/layout 与 glyph paragraph cache 复用现有对象。
- paint/scratch collection 避免热路径重复分配。
- graphics 与 asset key 集合只在 revision 改变时同步。
- focus report 的 attach/detach/gain/loss 决策移入 `TerminalFocusReporter`。
- graphics cache owner/sync 决策移入 `TerminalGraphicsSync`。

最终删除的实验：

- cursor overlay render object；
- `TerminalCursorExperimentScope`；
- `TerminalCursorExperimentMode`；
- overlay listener、cache、Expando、dead import 和生产入口。

最终 cursor 继续在 main surface 绘制。NO-GO 不是“实验没有局部改善”，而是“端到端 total span 没有稳定满足冻结阈值”。

## JSON/Protobuf transport

新增/调整边界：

- `terminal_frame_decoder.dart`：decoder facade；
- `terminal_frame_transport_coordinator.dart`：capability 与 wire preference；
- `terminal_json_frame_decoder.dart`：JSON decode；
- `terminal_protobuf_frame_decoder.dart`：Protobuf decode；
- `terminal_frame_validation_limits.dart`：共享边界；
- `terminal_wire_compatibility.dart`：共享兼容归一化；
- `terminal_frame_wire_fixture.dart`：跨格式测试 fixture。

选择规则：

1. 显式 JSON 永远读取 JSON。
2. automatic 仅在 capability 报告支持时读取 Protobuf。
3. 不支持 capability 或 capability=false 时读取 JSON。
4. 已选择 Protobuf 后，本次读取失败不会再读 JSON。

测试覆盖字段边界、malformed payload、极端 viewport、style runs、graphics、hyperlink、selection、cursor、dirty range 和 final frame parity。

## macOS integration 与 Release hardening

主要文件：

- `example/macos/Runner.xcodeproj/project.pbxproj`
- `example/macos/Runner/LocalRelease.entitlements`
- `tools/sign_local_macos_release.sh`
- `tools/validate_local_release_entitlements.py`
- `example/test/support/macos_integration_test_lifecycle.dart`
- macOS smoke/real PTY integration tests

变化：

- Release build 明确保留 hardened runtime。
- 本地 adhoc 签名只放宽 library validation，以允许本地 Rust dylib/framework 组合。
- 签名脚本逐层重签并验证主程序、dylib 和嵌套 frameworks 的 runtime flag。
- integration runner 若启动时 hidden 且 frames disabled，只走受控 lifecycle 恢复；其他异常状态继续 fail-fast。

## Benchmark 与测试资产

新增或扩展：

- refresh policy/scheduler/frame-pump controller tests；
- real PTY hint/fallback/ceiling acceptance；
- JSON/Protobuf codec parity 与 corpus；
- render paint/cache metrics；
- graphics sync 与 focus reporter tests；
- cursor overlay frozen gate、profile report 与 decision evidence；
- transport profile matrix 与 formal audit；
- macOS app identity、entitlement、signing 和 lifecycle tests；
- docs contract。

Cursor profile 的采样边界修复为：在 settling pump 之前立即快照 `FrameTiming`，因此 24 次 blink 对应 24 条 timing，不再错误收集 25 条。

## 公共 API 与结构边界

保留：

- `TerminalFrameDiff.fromJson`；
- `TerminalFrameDiff.fromProtobufBytes`；
- JSON compatibility path；
- 现有 viewport/widget 层级；
- `TerminalViewport` 对 key、selection、caret geometry、IME 与 `TextInputConnection` 的所有权。

新增 coordinator 是内部边界，不访问不属于它们的 viewport/scheduler 状态。没有为了文件整洁而进行破坏性 factory 迁移。

## 最终验证摘要

- 完整 `verify_flutter_terminal.sh`：最终代码上连续两次通过，无中间代码改动。
- JSON/Protobuf parity：26/26。
- transport profile：18 runs，9/9 viewport hash pairs matched。
- Release refresh gate：3/3。
- 本地 Release：54.6 MB，deep/strict codesign 通过，所有目标 `adhoc,runtime`。
- Computer：启动、ASCII/CJK、idle marker、resize、tabs、split/focus、cursor、真实滚轮 scrollback、关闭/空状态和恢复均通过。

## 未执行与原因

最终 Computer 续作没有再次运行完整自动化矩阵或 transport/profile 长跑；这些命令已经在相同受评代码 SHA 上连续通过并由 handoff 记录，续作没有代码改动。续作重新执行了依赖锁定解析、Release build、本地签名与 deep/strict 验证，并完成之前缺失的界面门禁。

文档提交只包含两份最终报告。工作树中既有的未跟踪 `docs/audits/.DS_Store` 不属于本评审，不会纳入提交。

## 风险与后续

- 本地 adhoc 签名不能替代发布签名和公证。
- Intel Mac、DPI 切换和所有 IME/第三方 shell 组合仍需发布矩阵覆盖。
- 后续性能结论必须继续以端到端 frozen gate 为准，不能只看局部 paint 指标。
- 若 runtime/frame schema 继续演进，应保持 JSON/Protobuf 同 fixture、同 validation limits 和同 hash audit。
