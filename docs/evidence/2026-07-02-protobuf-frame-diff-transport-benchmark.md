# 2026-07-02 Protobuf Frame Diff Transport Benchmark

## Mixed workload 命令

```bash
cd packages/ianvs_terminal
flutter test test/benchmarks/frame_diff_transport_benchmark_test.dart \
  --plain-name "frame diff transport benchmark exports metrics" \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_OUT=/tmp/ianvs-frame-diff-transport-benchmark-final.json \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_ITERATIONS=120 \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_FRAMES=120 \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_ROWS=40 \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_COLS=120
```

## 范围

- 模式：`flutter_test_debug`
- 样本：120 个合成 frame，120 轮，共 14,400 次 JSON decode 和 14,400 次 protobuf decode
- viewport：40 行 x 120 列
- 覆盖字段：rows、style runs、cursor、dirty ranges、colors、modes、window metadata、hyperlinks、graphics
- 正确性：JSON/protobuf decode 后的 frame hash 全部一致

这次 benchmark 是 Dart 侧 frame decode 和 payload size 的直接对比，不包含 Rust encode、FFI 边界、Flutter render 或真实 polling/coalescing 行为。端到端 release gate 仍需在后续 profile harness 里汇总 runtime/native/render metrics。

## 结果

| 指标 | JSON | Protobuf | 比例 |
| --- | ---: | ---: | ---: |
| total bytes | 461,518 | 181,541 | 0.393x |
| mean bytes/frame | 3,845.98 | 1,512.84 | 0.393x |
| decode mean/frame | 20.92 us | 8.61 us | 0.412x |
| decode p95/round | 2,719 us | 1,411 us | 0.519x |

解读：

- protobuf payload 比 JSON 小约 60.7%。
- protobuf Dart decode 平均耗时比 JSON 低约 58.8%，约为 JSON 的 2.43 倍。
- p95 round decode 也约为 JSON 的 51.9%，说明这批合成 frame 下 protobuf decode 的尾部耗时同样更低。

原始输出：`/tmp/ianvs-frame-diff-transport-benchmark-final.json`

## Resize churn workload 命令

```bash
cd packages/ianvs_terminal
flutter test test/benchmarks/frame_diff_transport_benchmark_test.dart \
  --plain-name "frame diff transport benchmark exports metrics" \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_OUT=/tmp/ianvs-frame-diff-transport-resize-20260702.json \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_WORKLOAD=resize_churn \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_ITERATIONS=120 \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_FRAMES=96 \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_ROWS=40 \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_COLS=120
```

## Resize churn 范围

- 模式：`flutter_test_debug`
- 样本：96 个合成 frame，120 轮，共 11,520 次 JSON decode 和 11,520 次 protobuf decode
- viewport 基准：40 行 x 120 列
- resize cadence：每 8 帧切换一次 rows/cols，尺寸变化帧为 `snapshot`，中间帧为 `delta`
- frame 组成：12 个 `snapshot`，84 个 `delta`
- 正确性：JSON/protobuf decode 后的 frame hash 全部一致

## Resize churn 结果

| 指标 | JSON | Protobuf | 比例 |
| --- | ---: | ---: | ---: |
| total bytes | 264,924 | 96,371 | 0.364x |
| mean bytes/frame | 2,759.63 | 1,003.86 | 0.364x |
| decode mean/frame | 15.96 us | 6.04 us | 0.378x |
| decode p95/round | 1,997 us | 819 us | 0.410x |

按 frame kind 拆分：

| frame kind | count | JSON mean bytes | Protobuf mean bytes | bytes ratio | JSON decode/frame | Protobuf decode/frame | decode ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| snapshot | 12 | 13,458.58 | 5,936.17 | 0.441x | 70.26 us | 25.56 us | 0.364x |
| delta | 84 | 1,231.20 | 299.25 | 0.243x | 6.04 us | 2.56 us | 0.425x |

解读：

- resize workload 下 protobuf payload 比 JSON 小约 63.6%。
- protobuf Dart decode 平均耗时比 JSON 低约 62.2%，约为 JSON 的 2.64 倍。
- 尺寸变化产生的 `snapshot` 帧仍然明显更大，但 protobuf 在 snapshot 上 decode 耗时约为 JSON 的 36.4%。
- 中间 `delta` 帧 protobuf payload 只有 JSON 的 24.3%，decode 耗时约为 JSON 的 42.5%。

原始输出：`/tmp/ianvs-frame-diff-transport-resize-20260702.json`

## 端到端 transport profile 命令

```bash
cd example
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/terminal_transport_profile_test.dart \
  -d macos \
  --profile \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_OUTPUT=/Users/robinfai/personal/ianvs/ianvs-terminal/.worktrees/protobuf-frame-diff-transport/example/build/bench-results-profile/transport-pb-json-20260702/macos-darwin \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_TARGET_LABEL=macos-darwin \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_WORKLOADS=burst_stdout_profile,scrollback_heavy_profile,resize_churn_profile \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_WIRE_FORMATS=protobuf,json \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_REPEATS=3 \
  --dart-define=IANVS_BENCH_TRANSPORT_PROFILE_FRAME_COUNT=96
```

Formal audit:

```bash
dart run tools/bench/analysis/flutter_profile_audit.dart \
  --input example/build/bench-results-profile/transport-pb-json-20260702/macos-darwin \
  --output build/bench-results-profile/transport-pb-json-20260702/formal-audit \
  --workloads protobuf_burst_stdout_profile,protobuf_scrollback_heavy_profile,protobuf_resize_churn_profile,json_burst_stdout_profile,json_scrollback_heavy_profile,json_resize_churn_profile \
  --repeats 3 \
  --require-target-count 1
```

## 端到端 transport profile 范围

- 模式：macOS Flutter profile target
- backend：真实 `NativePtyBackend.load()`，每个 run 启动 `/bin/sh -lc 'stty -echo; exec /bin/cat'`
- runtime：启用 polling，protobuf 自动路径与 forced JSON 路径分别运行
- 覆盖链路：Rust frame build、Rust JSON/protobuf encode、FFI、Dart decode、runtime frame apply、polling refresh、Flutter render、Flutter frame timing
- workload：`burst_stdout_profile`、`scrollback_heavy_profile`、`resize_churn_profile`
- 样本：每个 workload/wire 3 次，每次 96 个 semantic input frame
- 正确性：每个 workload/repeat 的 protobuf 与 forced JSON final viewport hash 一致

端到端 profile 期间曾暴露一个自动 PB 路径问题：PB backend 支持 protobuf 时，如果一次 polling 恰好没有 PB frame，runtime 会立即 JSON fallback；高吞吐下两次调用之间可能新到一帧，导致 PB run 内混入 JSON 事件。修复后 backend 显式暴露 `supportsProtobufFrameDiffs`，支持 PB 时空返回只表示“当前没有 frame”，不再 JSON 补读；旧 native 没有 PB 符号时仍保留 JSON 兼容 fallback。

## 端到端 transport profile 结果

| workload | wire | avg raw bytes | avg p95 native encode | avg p95 Dart decode | avg p95 total span | avg p95 apply frame |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| burst_stdout_profile | protobuf | 110,232.3 | 87.0 us | 80.0 us | 3,425.3 us | 92.7 us |
| burst_stdout_profile | JSON | 319,739.0 | 213.3 us | 83.3 us | 2,358.0 us | 53.0 us |
| scrollback_heavy_profile | protobuf | 28,669.0 | 63.3 us | 71.7 us | 1,671.3 us | 95.7 us |
| scrollback_heavy_profile | JSON | 124,531.0 | 179.3 us | 97.7 us | 1,678.7 us | 71.3 us |
| resize_churn_profile | protobuf | 86,928.3 | 76.0 us | 65.7 us | 4,592.3 us | 82.7 us |
| resize_churn_profile | JSON | 275,485.7 | 387.0 us | 118.0 us | 4,672.7 us | 52.3 us |

比值：

| workload | JSON/PB raw bytes | JSON/PB native encode | JSON/PB Dart decode | JSON/PB total span |
| --- | ---: | ---: | ---: | ---: |
| burst_stdout_profile | 2.90x | 2.45x | 1.04x | 0.69x |
| scrollback_heavy_profile | 4.34x | 2.83x | 1.36x | 1.00x |
| resize_churn_profile | 3.17x | 5.09x | 1.80x | 1.02x |

Formal audit output:

- `build/bench-results-profile/transport-pb-json-20260702/formal-audit/formal_profile_audit.json`
- `build/bench-results-profile/transport-pb-json-20260702/formal-audit/formal_profile_summary.csv`
- `build/bench-results-profile/transport-pb-json-20260702/formal-audit/formal_profile_report.md`

Audit result: `passed: true`, `target_count: 1`, `run_count: 18`, `failures: []`.

## 端到端 transport profile 结论

- protobuf 在 wire size 和 Rust encode 上收益稳定：三个 profile workload 的 JSON raw bytes 是 protobuf 的 2.90x 到 4.34x，JSON native encode p95 是 protobuf 的 2.45x 到 5.09x。
- resize 场景里 protobuf 的端到端 wire/encode/decode 优势最明确：raw bytes 下降约 68.5%，native encode p95 从 387.0 us 降到 76.0 us，Dart decode p95 从 118.0 us 降到 65.7 us。
- Flutter render total span 不完全由 wire format 决定。scrollback 和 resize 下 protobuf 与 JSON 接近，burst 下 JSON 的 avg p95 total span 更低。这说明当前结果支持“生产默认 protobuf”，但还不支持“删除 JSON 路径”。
- 建议保留 JSON 作为 forced debug/compat wire，同时让 protobuf 成为默认 runtime path。移除 JSON 应等到至少满足：多平台 native profile 覆盖、PB schema 迁移策略稳定、debug 导出/兼容工具不依赖 JSON frame diff、以及 render span 波动有更长期样本确认。
