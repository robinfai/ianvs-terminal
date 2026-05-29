#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tools/cat_log_benchmark.sh --out-dir /absolute/output/dir [--scenario bulk-output|streaming-scroll|resize|alternate-screen|input-echo] [--fixture /absolute/fixture.log] [--timeout-sec 20] [--profile release|debug] [--include-raw-frames]
EOF
}

out_dir=""
fixture=""
timeout_sec="20"
profile="${PROFILE:-release}"
include_raw_frames="false"
scenario="bulk-output"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      if [[ $# -lt 2 ]]; then
        usage
        exit 1
      fi
      out_dir="$2"
      shift 2
      ;;
    --fixture)
      if [[ $# -lt 2 ]]; then
        usage
        exit 1
      fi
      fixture="$2"
      shift 2
      ;;
    --scenario)
      if [[ $# -lt 2 ]]; then
        usage
        exit 1
      fi
      scenario="$2"
      shift 2
      ;;
    --timeout-sec)
      if [[ $# -lt 2 ]]; then
        usage
        exit 1
      fi
      timeout_sec="$2"
      shift 2
      ;;
    --profile)
      if [[ $# -lt 2 ]]; then
        usage
        exit 1
      fi
      profile="$2"
      shift 2
      ;;
    --include-raw-frames)
      include_raw_frames="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$out_dir" ]]; then
  echo "--out-dir is required" >&2
  usage
  exit 1
fi

if [[ "${out_dir#/}" == "$out_dir" ]]; then
  echo "--out-dir must be an absolute path" >&2
  exit 1
fi

if [[ -n "$fixture" ]]; then
  if [[ "${fixture#/}" == "$fixture" ]]; then
    echo "--fixture must be an absolute path" >&2
    exit 1
  fi
  if [[ ! -f "$fixture" ]]; then
    echo "Fixture log not found: $fixture" >&2
    exit 1
  fi
fi

if ! [[ "$timeout_sec" =~ ^[0-9]+$ ]] || [[ "$timeout_sec" -le 0 ]]; then
  echo "--timeout-sec must be a positive integer" >&2
  exit 1
fi

if [[ "$profile" != "release" && "$profile" != "debug" ]]; then
  echo "--profile must be release or debug" >&2
  exit 1
fi

case "$scenario" in
  bulk-output|streaming-scroll|resize|alternate-screen|input-echo)
    ;;
  *)
    echo "--scenario must be bulk-output, streaming-scroll, resize, alternate-screen, or input-echo" >&2
    exit 1
    ;;
esac

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
example_dir="$repo_root/example"

mkdir -p "$out_dir"

PROFILE="$profile" "$repo_root/tools/build_core.sh"

if [[ "$profile" == "release" ]]; then
  core_lib="$repo_root/native/core/target/release/libianvs_core.dylib"
else
  core_lib="$repo_root/native/core/target/debug/libianvs_core.dylib"
fi

capture_time_log="$out_dir/cat-log-benchmark.capture-time.txt"
replay_time_log="$out_dir/cat-log-benchmark.replay-time.txt"
time_json="$out_dir/cat-log-benchmark.time.json"

cmd=(
  flutter
  test
  test/benchmarks/cat_log_benchmark_test.dart
  --plain-name
  "cat log benchmark exports metrics"
  "--dart-define=CAT_LOG_BENCH_OUT_DIR=$out_dir"
  "--dart-define=CAT_LOG_BENCH_CORE_PROFILE=$profile"
  "--dart-define=CAT_LOG_BENCH_CORE_LIB=$core_lib"
)

capture_cmd=(
  dart
  run
  tool/cat_log_trace_capture.dart
  --out-dir
  "$out_dir"
  --scenario
  "$scenario"
  --timeout-sec
  "$timeout_sec"
)

if [[ -n "$fixture" ]]; then
  capture_cmd+=(--fixture "$fixture")
fi

if [[ "$include_raw_frames" == "true" ]]; then
  capture_cmd+=(--include-raw-frames)
fi

(
  cd "$example_dir"
  IANVS_CORE_LIB="$core_lib" /usr/bin/time -lp "${capture_cmd[@]}"
) 2> >(tee "$capture_time_log" >&2)

(
  cd "$example_dir"
  IANVS_CORE_LIB="$core_lib" /usr/bin/time -lp "${cmd[@]}"
) 2> >(tee "$replay_time_log" >&2)

time_field() {
  local field="$1"
  local file="$2"
  awk -v field="$field" '$1 == field {print $2}' "$file" | tail -n 1
}

cpu_percent_for() {
  local real="$1"
  local user="$2"
  local sys="$3"
  awk -v real="$real" -v user="$user" -v sys="$sys" 'BEGIN {
  if (real > 0) {
    printf "%.2f", ((user + sys) / real) * 100
  } else {
    printf "0.00"
  }
}'
}

file_size() {
  local file="$1"
  if [[ -f "$file" ]]; then
    stat -f%z "$file"
  else
    printf "0"
  fi
}

capture_real_sec="$(time_field real "$capture_time_log")"
capture_user_sec="$(time_field user "$capture_time_log")"
capture_sys_sec="$(time_field sys "$capture_time_log")"
capture_cpu_percent="$(cpu_percent_for "$capture_real_sec" "$capture_user_sec" "$capture_sys_sec")"
replay_real_sec="$(time_field real "$replay_time_log")"
replay_user_sec="$(time_field user "$replay_time_log")"
replay_sys_sec="$(time_field sys "$replay_time_log")"
replay_cpu_percent="$(cpu_percent_for "$replay_real_sec" "$replay_user_sec" "$replay_sys_sec")"
trace_file="$out_dir/cat-log-benchmark.trace.json"
metrics_file="$out_dir/cat-log-benchmark.metrics.json"
fixture_bytes="0"
if [[ -n "$fixture" ]]; then
  fixture_bytes="$(file_size "$fixture")"
else
  fixture_bytes="$(file_size "$out_dir/cat-log-benchmark.fixture.log")"
fi

cat >"$time_json" <<EOF
{
  "coreProfile": "$profile",
  "coreLibPath": "$core_lib",
  "scenario": "$scenario",
  "includeRawFrames": $include_raw_frames,
  "fixtureBytes": $fixture_bytes,
  "traceBytes": $(file_size "$trace_file"),
  "metricsBytes": $(file_size "$metrics_file"),
  "captureTime": {
    "realSec": $capture_real_sec,
    "userSec": $capture_user_sec,
    "sysSec": $capture_sys_sec,
    "cpuPercent": $capture_cpu_percent
  },
  "replayTime": {
    "realSec": $replay_real_sec,
    "userSec": $replay_user_sec,
    "sysSec": $replay_sys_sec,
    "cpuPercent": $replay_cpu_percent
  }
}
EOF

echo "Benchmark metrics written to $out_dir"
