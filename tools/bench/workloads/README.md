# Benchmark Workloads

Workloads are deterministic and can be generated locally:

```bash
dart run tools/bench/workloads/burst_stdout/generate.dart
dart run tools/bench/workloads/scrollback_heavy/generate.dart
dart run tools/bench/workloads/resize_churn/generate.dart
```

The runner can also resolve built-in workload names directly, so generated
trace files are useful for inspection but are not required for CI smoke.
