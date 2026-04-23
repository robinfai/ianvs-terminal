#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tools/ps1_diag_export.sh --out-dir /absolute/output/dir [--reference /absolute/reference.png]
EOF
}

out_dir=""
reference=""

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
    --reference)
      if [[ $# -lt 2 ]]; then
        usage
        exit 1
      fi
      reference="$2"
      shift 2
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

if [[ -n "$reference" ]]; then
  if [[ "${reference#/}" == "$reference" ]]; then
    echo "--reference must be an absolute path" >&2
    exit 1
  fi
  if [[ ! -f "$reference" ]]; then
    echo "Reference image not found: $reference" >&2
    exit 1
  fi
fi

mkdir -p "$out_dir"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$repo_root/app"

cmd=(
  flutter
  test
  test/terminal/ps1_diag_export_test.dart
  --plain-name
  "ps1 diag export writes configured artifacts"
  "--dart-define=PS1_DIAG_OUT_DIR=$out_dir"
)

if [[ -n "$reference" ]]; then
  cmd+=("--dart-define=PS1_DIAG_REFERENCE=$reference")
fi

(
  cd "$app_dir"
  "${cmd[@]}"
)
