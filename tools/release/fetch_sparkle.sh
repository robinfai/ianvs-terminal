#!/usr/bin/env bash
set -euo pipefail
output=${1:?Sparkle output directory is required}
archive="$output/Sparkle-2.10.0.tar.xz"
mkdir -p "$output"
curl --fail --location --retry 3 --silent --show-error \
  https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz \
  -o "$archive"
printf '%s  %s\n' c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c "$archive" | shasum -a 256 -c -
tar -xf "$archive" -C "$output"
