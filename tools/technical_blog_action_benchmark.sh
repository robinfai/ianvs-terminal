#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tools/technical_blog_action_benchmark.sh --out-dir /absolute/output/dir [--timeout-sec 20] [--profile release|debug] [--include-raw-frames]

Runs the project-action benchmark scenarios derived from the technical-blog
feedback: bulk output, streaming scroll, resize fallback, alternate screen,
and input echo latency.
USAGE
}

out_dir=""
timeout_sec="20"
profile="${PROFILE:-release}"
include_raw_frames="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      out_dir="$2"
      shift 2
      ;;
    --timeout-sec)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      timeout_sec="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || { usage; exit 1; }
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

if ! [[ "$timeout_sec" =~ ^[0-9]+$ ]] || [[ "$timeout_sec" -le 0 ]]; then
  echo "--timeout-sec must be a positive integer" >&2
  exit 1
fi

case "$profile" in
  release|debug) ;;
  *)
    echo "--profile must be release or debug" >&2
    exit 1
    ;;
esac

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$out_dir"

scenarios=(bulk-output streaming-scroll resize alternate-screen input-echo)
commands_file="$out_dir/commands.txt"
environment_file="$out_dir/environment.txt"
summary_file="$out_dir/benchmark-summary.md"
: > "$commands_file"

{
  echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "repo_root=$repo_root"
  echo "profile=$profile"
  echo "timeout_sec=$timeout_sec"
  echo "include_raw_frames=$include_raw_frames"
  uname -a | sed 's/^/uname=/'
  command -v flutter | sed 's/^/flutter_path=/' || true
  flutter --version | sed 's/^/flutter_version=/' || true
} > "$environment_file"

for scenario in "${scenarios[@]}"; do
  scenario_dir="$out_dir/$scenario"
  mkdir -p "$scenario_dir"
  cmd=(
    "$repo_root/tools/cat_log_benchmark.sh"
    --out-dir "$scenario_dir"
    --scenario "$scenario"
    --timeout-sec "$timeout_sec"
    --profile "$profile"
  )
  if [[ "$include_raw_frames" == "true" ]]; then
    cmd+=(--include-raw-frames)
  fi
  printf '%q ' "${cmd[@]}" >> "$commands_file"
  printf '\n' >> "$commands_file"
  "${cmd[@]}"
done

{
  echo "# Technical-blog action benchmark summary"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Scenarios"
  for scenario in "${scenarios[@]}"; do
    echo "- $scenario: $out_dir/$scenario"
  done
  echo
  echo "## Required evidence files"
  echo "- commands: $commands_file"
  echo "- environment: $environment_file"
  echo "- per-scenario trace: <scenario>/cat-log-benchmark.trace.json"
  echo "- per-scenario metrics: <scenario>/cat-log-benchmark.metrics.json"
  echo "- per-scenario timing: <scenario>/cat-log-benchmark.time.json"
} > "$summary_file"

echo "Technical-blog action benchmark evidence written to $out_dir"
