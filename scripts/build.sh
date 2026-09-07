#!/usr/bin/env bash
# build.sh — cross-platform release builds for Uniclient.
#
# Usage: ./scripts/build.sh [linux|windows|web|all]
#
# Notes:
#   - linux needs cgo (Gio GPU access) + X11/Wayland/EGL dev headers.
#   - windows/web are pure Go (CGO_ENABLED=0) — no cross toolchain needed.
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
	echo "==> linux/amd64 (cgo)"
	CGO_ENABLED=1 go build -p 1 -tags "$TAGS" "${strip_flags[@]}" \
		-o "$DIST/uniclient-linux-amd64" ./cmd/uniclient
	upx_compress "$DIST/uniclient-linux-amd64"
	if [ "${UNICLIENT_ARM64:-0}" = "1" ]; then
		echo "==> linux/arm64 (cgo cross — needs aarch64 pkg-config libs)"
		CGO_ENABLED=1 CC=aarch64-linux-gnu-gcc \
			PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH64" \
			go build -p 1 -tags "$TAGS" "${strip_flags[@]}" \
			-o "$DIST/uniclient-linux-arm64" ./cmd/uniclient || echo "arm64 skipped"
	fi
}

build_windows() {
	echo "==> windows/amd64 (pure Go)"
	GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -p 1 -tags "$TAGS" "${strip_flags[@]}" \
		-o "$DIST/uniclient-windows-amd64.exe" ./cmd/uniclient
	upx_compress "$DIST/uniclient-windows-amd64.exe"
}

build_web() {
	echo "==> web/wasm (pure Go)"
	GOOS=js GOARCH=wasm CGO_ENABLED=0 go build -p 1 -tags "$TAGS" \
		-trimpath -ldflags "-s -w" -o "$DIST/uniclient.wasm" ./cmd/uniclient
	# The web shell (wasm_exec.js + index.html) is generated in CI into gh-pages;
	# locally you can run scripts/web.sh to serve it on :8080.
}

case "${1:-all}" in
linux) build_linux ;;
windows) build_windows ;;
web) build_web ;;
all) build_linux && build_windows && build_web ;;
*)
	echo "usage: $0 [linux|windows|web|all]" >&2
	exit 1
	;;
esac

ls -la "$DIST"
