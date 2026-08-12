#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BACKEND_DIR="$ROOT_DIR/backend"
DESTINATION=${1:?destination path is required}
BUILD_DIRECTORY=${PROJECT_TEMP_DIR:-"$ROOT_DIR/build/data-api"}
ARCHITECTURES=${ARCHS:-$(uname -m)}
BINARIES=""

mkdir -p "$BUILD_DIRECTORY" "$(dirname -- "$DESTINATION")"

for architecture in $ARCHITECTURES; do
  case "$architecture" in
    arm64) go_architecture=arm64 ;;
    x86_64) go_architecture=amd64 ;;
    *)
      echo "Unsupported macOS architecture: $architecture" >&2
      exit 1
      ;;
  esac

  architecture_binary="$BUILD_DIRECTORY/ianvs-api-$architecture"
  (
    cd "$BACKEND_DIR"
    CGO_ENABLED=1 GOOS=darwin GOARCH="$go_architecture" \
      CGO_CFLAGS="-arch $architecture" \
      CGO_LDFLAGS="-arch $architecture" \
      GOCACHE="$BUILD_DIRECTORY/go-cache-$architecture" \
      go build -trimpath -o "$architecture_binary" ./cmd/ianvs-api
  )
  BINARIES="$BINARIES $architecture_binary"
done

set -- $BINARIES
if [ "$#" -eq 1 ]; then
  cp "$1" "$DESTINATION"
else
  lipo -create "$@" -output "$DESTINATION"
fi
chmod 755 "$DESTINATION"
