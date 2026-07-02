# 2026-07-02 Protobuf Frame Diff Transport Benchmark

## 命令

```bash
cd packages/ianvs_terminal
flutter test test/benchmarks/frame_diff_transport_benchmark_test.dart \
  --plain-name "frame diff transport benchmark exports metrics" \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_OUT=/tmp/ianvs-frame-diff-transport-benchmark-20260702/metrics.json \
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
| decode mean/frame | 21.46 us | 9.09 us | 0.423x |
| decode p95/round | 2,925 us | 1,385 us | 0.474x |

解读：

- protobuf payload 比 JSON 小约 60.7%。
- protobuf Dart decode 平均耗时比 JSON 低约 57.7%，约 2.36x faster。
- p95 round decode 也约为 JSON 的 47.4%，说明这批合成 frame 下 protobuf decode 的尾部耗时同样更低。

原始输出：`/tmp/ianvs-frame-diff-transport-benchmark-20260702/metrics.json`
