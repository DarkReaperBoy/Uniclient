#!/usr/bin/env bash
# build.sh — cross-platform release builds for Uniclient.
#
# Usage: ./scripts/build.sh [linux|windows|all]
#
# Notes:
#   - pure Go everywhere (CGO_ENABLED=0) — no cross toolchain needed.
#   - binaries are stripped (-trimpath -ldflags "-s -w"); UPX if available
#     and not disabled (UNICLIENT_NO_UPX=1).
set -euo pipefail

cd "$(dirname "$0")/../go"
DIST="$(cd .. && pwd)/dist"
mkdir -p "$DIST"

TAGS="${TAGS:-goolm}"
export GOMEMLIMIT="${GOMEMLIMIT:-900MiB}"
export GOGC="${GOGC:-30}"

strip_flags=(-trimpath -ldflags "-s -w")

upx_compress() {
	if [ "${UNICLIENT_NO_UPX:-0}" = "1" ] || ! command -v upx >/dev/null 2>&1; then
		echo "   (upx skipped)"
		return 0
	fi
	upx --best --lzma -q "$1" || echo "   (upx failed — keeping uncompressed)"
}

build_linux() {
	echo "==> linux/amd64"
	CGO_ENABLED=1 go build -p 1 -tags "$TAGS" "${strip_flags[@]}" \
		-o "$DIST/uniclient-linux-amd64" ./cmd/uniclient
	upx_compress "$DIST/uniclient-linux-amd64"
}

build_windows() {
	echo "==> windows/amd64 (pure Go)"
	GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -p 1 -tags "$TAGS" "${strip_flags[@]}" \
		-o "$DIST/uniclient-windows-amd64.exe" ./cmd/uniclient
	upx_compress "$DIST/uniclient-windows-amd64.exe"
}

case "${1:-all}" in
linux) build_linux ;;
windows) build_windows ;;
all) build_linux && build_windows ;;
*)
	echo "usage: $0 [linux|windows|all]" >&2
	exit 1
	;;
esac

ls -la "$DIST"
