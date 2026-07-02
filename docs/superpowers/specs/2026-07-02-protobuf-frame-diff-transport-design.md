# Protobuf Frame Diff 传输设计

## 背景

当前 terminal frame diff 使用 JSON 表达 Rust 到 Dart 的帧差异。这个路径具备可调试、跨语言实现简单、字段演进直观等优势，已经接入：

- Rust frame diff 生成：`native/core/src/session.rs`
- FFI JSON 传输：`native/core/src/ffi.rs`
- Dart FFI 封装：`packages/ianvs_pty/lib/src/native_pty_backend.dart`
- Dart frame 模型和合并：`packages/ianvs_terminal/lib/src/terminal/terminal_models.dart`
- Runtime 拉取和派发：`packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- Flutter row cache 渲染：`packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart`
- benchmark 输出：`tools/bench` 和 `example/lib/benchmarks`

现有 JSON 路径已经记录部分成本：Rust 侧有 `json_encode_micros`，Dart runtime event 有 `raw_frame_bytes`、`json_decode_micros`、`apply_frame_micros`、`queued_refresh_count` 等字段。Runtime 默认刷新策略是 33ms polling，带空闲退避、输入/滚动唤醒、刷新中排队和冷却行为。

这次设计把后续方向收成一条可验证路线：JSON 继续作为 debug/compat 默认路径，新增 protobuf frame diff 作为可开关实验传输。第一阶段不做 shared memory row buffer，也不做 zero-copy transport。

## 目标

- 新增完整覆盖 `TerminalFrameDiff` 的 protobuf 传输格式。
- 保持 JSON 为默认路径和回退路径。
- 真实 runtime 支持通过参数选择 `json` 或 `protobuf`。
- protobuf 解码后仍映射为现有 `TerminalFrameDiff`，不改变 viewport 合并和 Flutter renderer。
- release gate 同跑 JSON/protobuf，验证最终 viewport hash、schema、字段完整性和 fallback 行为。
- benchmark 能按同一字段比较 JSON/protobuf 的 payload 大小、encode/decode、apply、render、polling 和 coalescing 指标。
- 普通构建和测试不要求本机安装 `protoc`；schema 和生成物入仓。

## 非目标

- 不把 protobuf 设为默认传输格式。
- 不重写 `TerminalViewportController` 的 snapshot/delta 合并逻辑。
- 不重写 Flutter renderer 或 row cache。
- 不实现 shared memory row buffer。
- 不实现 zero-copy transport。
- 不用第一阶段的性能数值阻塞 release；第一阶段只阻塞正确性、schema、字段完整性和异常 fallback。
- 不复用 vendored streaming 的 `terminal.proto` 作为本地 FFI frame diff schema。

## 方案选择

讨论过三种非 JSON 方向：

- `binary frame diff`：字段语义和现有 frame diff 对齐，换成二进制 payload。
- `shared memory row buffer`：把行内容放到共享缓冲区，Dart 通过索引读取。
- `zero-copy transport`：尽量减少 Rust 到 Dart 到 Flutter 之间的数据拷贝。

本阶段选择 `binary frame diff`，并使用 protobuf/schema codegen 实现。原因：

- 可以和 JSON 做同一语义对象的直接对比。
- 能进入真实 runtime，而不是只停留在模拟 benchmark。
- 对 Dart/Flutter 渲染层影响最小。
- 相比 shared memory 和 zero-copy，内存生命周期和跨平台风险更可控。

生成物管理选择：`.proto`、Rust 生成代码、Dart 生成代码都入仓。普通 `cargo test`、`dart test`、`flutter test` 不依赖 `protoc`。

## 架构

第一阶段新增一条并行传输路径：

```text
Rust TerminalFrameDiff
  |-- JSON encode -> FFI string -> Dart jsonDecode -> TerminalFrameDiff
  |
  `-- protobuf encode -> FFI bytes -> Dart protobuf decode -> TerminalFrameDiff
```

模块职责：

- `native/core`
  - 新增 `frame_diff.proto`。
  - 新增 Rust protobuf encode 路径。
  - 新增 FFI bytes 函数。
  - 继续保留现有 JSON 函数。
- `packages/ianvs_pty`
  - 只增加 bytes transport API。
  - 不解析 protobuf，不理解 terminal frame 字段。
- `packages/ianvs_terminal`
  - 增加 `TerminalFrameTransport`。
  - 在 runtime 中按配置选择 JSON 或 protobuf。
  - protobuf decode 后映射到现有 `TerminalFrameDiff`。
- benchmark/profile
  - JSON/protobuf 同跑。
  - 同一套统计字段比较两条传输路径。
- docs/release gate
  - 记录 protobuf 为实验传输。
  - 记录 JSON 仍为默认和兼容路径。

## Protobuf 契约

新增独立 schema，例如：

```text
native/core/proto/frame_diff.proto
```

不复用 vendored streaming 的 `terminal.proto`。streaming 协议面向 WebSocket client/server；本设计面向本地 FFI frame diff 传输，两者的生命周期、字段和发布节奏不同。

protobuf 契约以 Dart `TerminalFrameDiff` 完整模型为准，覆盖：

- `frame_schema_version`
- `frame_kind`
- `rows`
- row `text`、`wrapped`、`modified_at`、`style_runs`
- `cursor`
- `selection`
- `viewport_rows`
- `viewport_cols`
- `dirty_ranges`
- `scrollback_offset`
- `scrollback_max_offset`
- `viewport_start_row`
- `viewport_row_shift`
- `default_foreground`
- `default_background`
- `cursor_color`
- `modes`
- `window_title`
- `window_icon_name`
- `hyperlinks`
- `inline_images`
- `graphics`

schema 规则：

- 顶层必须带 schema version。
- 所有 enum 必须有 `UNSPECIFIED = 0`。
- Dart decoder 遇到未知 enum 时走保守默认。
- 颜色优先用数值 RGB，例如 `uint32 rgb` 或 `ColorRgb` message，避免继续传 `#RRGGBB` 字符串。
- 文本字段保持 UTF-8 string。
- 第一版不做 string table。
- repeated message 使用清楚的结构，不提前压缩字段语义。
- 字段号分段预留：core frame、rows/styles、interaction metadata、graphics、future extensions。

Rust 当前尚未实际发出的 Dart 字段可以按 protobuf 默认值输出，但 Dart decoder 要支持完整字段。

## 生成流程

生成物入仓：

- Rust 生成物：`native/core/src/proto/frame_diff.pb.rs` 或同等路径。
- Dart 生成物：`packages/ianvs_terminal/lib/src/proto/frame_diff.pb.dart` 或同等路径。

普通验证不要求 `protoc`：

```bash
cd native/core
cargo test
```

```bash
cd packages/ianvs_pty
dart test
```

```bash
cd packages/ianvs_terminal
flutter test
```

只有修改 schema 时运行显式脚本，例如：

```bash
./tools/gen_frame_diff_proto.sh
```

该脚本负责：

- 检查 `protoc` 和 Rust/Dart codegen 工具是否可用。
- 从 `native/core/proto/frame_diff.proto` 生成 Rust 和 Dart 代码。
- 保持生成物稳定，避免无关格式抖动。

## Runtime 数据流

`TerminalRuntimeController` 增加参数：

```text
frameTransport: TerminalFrameTransport.json
```

默认值是 `json`。

当配置为 `json`：

1. runtime 调用 `takeFrameDiffJson(sessionId)`。
2. Dart 执行 `jsonDecode`。
3. 构造 `TerminalFrameDiff`。
4. 交给 `TerminalViewportController`。

当配置为 `protobuf`：

1. runtime 调用 `takeFrameDiffProtobuf(sessionId)`。
2. `ianvs_pty` 返回 `Uint8List?`。
3. `ianvs_terminal` 解码 protobuf message。
4. mapper 构造 `TerminalFrameDiff`。
5. 交给 `TerminalViewportController`。

protobuf 解码失败、schema 不兼容、backend 不支持 bytes symbol、返回空但 JSON 有帧时，runtime 可以回退 JSON。回退必须记录原因，不能静默发生。

## 回退规则

回退原因分两类。

允许兼容场景：

- `unsupported_backend`：native 库或 fake backend 没有 protobuf bytes API。

实验路径错误：

- `decode_error`
- `schema_mismatch`
- `missing_required_field`
- `empty_protobuf_with_json_frame`

release gate 中，`decode_error`、`schema_mismatch`、`missing_required_field` 和 `empty_protobuf_with_json_frame` 必须失败。`unsupported_backend` 只允许出现在明确声明为兼容测试的场景，不允许出现在 protobuf release gate 的真实 native run 中。

普通产品运行不需要打扰用户；benchmark 和 release gate 必须输出 fallback 统计。

## Benchmark 字段

JSON/protobuf 两条路径共用以下字段，便于对表比较：

- `transport_kind`: `json` 或 `protobuf`
- `transport_fallback_reason`
- `raw_frame_bytes`
- `wire_encode_micros`
- `wire_decode_micros`
- `apply_frame_micros`
- `frame_kind`
- `pending_frames_before`
- `pending_frames_after`
- `queued_refresh_count`
- `viewport_hash_after_apply`
- `polling_interval_ms`
- `refresh_strategy`
- `coalescing_ratio`

Rust frame debug stats 应补齐或映射：

- JSON 路径继续记录 `json_encode_micros`。
- protobuf 路径记录 `protobuf_encode_micros`。
- 汇总层统一展示为 `wire_encode_micros`。

Dart runtime stats 应补齐或映射：

- JSON 路径继续记录 `json_decode_micros`。
- protobuf 路径记录 `protobuf_decode_micros`。
- 汇总层统一展示为 `wire_decode_micros`。

真实 Flutter profile 输出必须包含 native frame debug stats、Dart runtime stats、Flutter render stats 和 Flutter frame timing stats。

## Release Gate

release gate 同一 workload 至少跑两组：

- JSON 默认路径
- protobuf 实验路径

硬性通过条件：

- final viewport hash 一致。
- `correctness.json` 通过。
- schema 校验通过。
- protobuf run 没有异常 fallback。
- 必填观测字段完整。
- native frame debug stats 存在。
- Dart runtime stats 存在。
- Flutter render/timing stats 存在。

报告但不拦截：

- payload bytes 差异。
- Rust encode p50/p95/p99。
- Dart decode p50/p95/p99。
- apply/render timing。
- polling interval。
- queued refresh。
- coalescing ratio。

性能阈值等 quiet-host 基线稳定后再作为后续任务加入硬性 gate。

## 测试计划

Rust 测试：

- `TerminalFrameDiff -> protobuf bytes` encode。
- schema version。
- enum 默认值。
- 完整字段覆盖。
- graphics、hyperlinks、modes、colors fixture。
- JSON/protobuf 来自同一语义对象。

Dart package 测试：

- `ianvs_pty` 只验证 bytes transport。
- `ianvs_terminal` 验证 protobuf decoder fixture。
- protobuf fixture 映射成和 JSON 等价的 `TerminalFrameDiff`。
- 无效 schema、未知 enum、缺字段、空 payload 的错误路径。

Runtime controller 测试：

- 默认 JSON。
- 显式 protobuf。
- unsupported backend fallback。
- decode error fallback reason。
- benchmark event 字段完整。

Benchmark/profile 测试：

- headless replay 同跑 JSON/protobuf 统计字段。
- 真实 Flutter profile harness 通过 dart-define 打开 protobuf。
- release gate 输出 JSON/protobuf 两组 summary。

## 文档更新

实现阶段需要同步：

- `docs/FRAME_DIFF.md`
  - 补 JSON/protobuf 双通道。
  - 说明 JSON 默认、protobuf 实验。
- `tools/bench/README.md`
  - 补 release gate 命令。
  - 补新增输出字段。
- `docs/TESTING.md` 或对应 release gate 任务文档
  - 补 protobuf gate 执行方式。
- `docs/KNOWN_ISSUES.md`
  - 仅在发现已知限制时更新。

## 风险和后续

主要风险：

- protobuf schema 和 Dart `TerminalFrameDiff` 模型出现漂移。
- 生成物更新流程增加维护成本。
- 完整覆盖 graphics/inline images 后，protobuf v1 范围明显大于文本快路径。
- release gate 真实 profile 受宿主负载影响，第一阶段不能直接拿性能数值做硬阈值。
- fallback 如果记录不严，会掩盖 protobuf 路径问题。

后续方向：

- 如果 protobuf 显著降低 payload 或 decode 成本，再评估设为可选默认。
- 如果高吞吐场景仍受传输或拷贝限制，再设计 shared memory row buffer。
- 如果 Dart/Flutter FFI 边界能证明可控，再评估 zero-copy transport。
- 如果 polling 成本显著，再单独设计 event-driven refresh 或 adaptive coalescing。

## 验收标准

第一阶段完成时应满足：

- JSON 默认路径行为不变。
- protobuf runtime 传输可通过显式参数启用。
- protobuf schema 覆盖 Dart `TerminalFrameDiff` 完整模型。
- `.proto`、Rust 生成物、Dart 生成物入仓。
- 普通构建和测试不依赖 `protoc`。
- JSON/protobuf 同一 workload final viewport hash 一致。
- release gate 能拦截 schema、字段完整性、correctness 和异常 fallback 问题。
- benchmark 报告能直接比较 JSON/protobuf 的 payload、encode/decode、apply/render、polling 和 coalescing 指标。
