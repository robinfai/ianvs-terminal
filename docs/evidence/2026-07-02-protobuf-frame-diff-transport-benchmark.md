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
