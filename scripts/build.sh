#!/usr/bin/env bash
set -euo pipefail

# Build the Uniclient engine + FFI bridge for the target platform.
# Usage: ./scripts/build.sh [linux|windows|darwin|android|web] [output-dir]
#
# Targets:
#   linux    -> dist/libuniclient.so   (c-shared, needs cc)
#   windows  -> dist/uniclient.dll     (c-shared, needs x86_64-w64-mingw32-gcc)
#   darwin   -> dist/libuniclient.dylib (c-shared, cross from mac; on linux
#               needs osxcross — usually built ON a mac)
#   android  -> dist/android/<abi>/libuniclient.so (needs ANDROID_NDK_HOME)
#   web      -> dist/uniclient.wasm    (js/wasm, no C toolchain needed)
#   cli      -> dist/uniclient-cli     (headless host binary, CGO-free)
#
# All targets build with -tags goolm (pure-Go Olm) — see the Makefile header.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GO_DIR="$PROJECT_DIR/go"
DIST_DIR="${2:-$PROJECT_DIR/dist}"

TARGET="${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}"

mkdir -p "$DIST_DIR"
cd "$GO_DIR"

# Low-memory compile recipe (verified on 4GB boxes; harmless elsewhere).
export GOMEMLIMIT="${GOMEMLIMIT:-900MiB}"
export GOGC="${GOGC:-30}"
GOFLAGS="-p 1 -tags goolm"

case "$TARGET" in
  linux)
    echo "Building libuniclient.so for linux/$(go env GOARCH)..."
    CGO_ENABLED=1 go build $GOFLAGS -buildmode=c-shared \
      -ldflags="-s -w" -o "$DIST_DIR/libuniclient.so" ./cmd/bridge/
    echo "Output: $DIST_DIR/libuniclient.so (+ libuniclient.h)"
    ;;
  windows)
    echo "Building uniclient.dll for windows/amd64..."
    CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc \
      go build $GOFLAGS -buildmode=c-shared \
      -ldflags="-s -w" -o "$DIST_DIR/uniclient.dll" ./cmd/bridge/
    echo "Output: $DIST_DIR/uniclient.dll (+ uniclient.h)"
    ;;
  darwin)
    echo "Building libuniclient.dylib for darwin/$(go env GOARCH)..."
    CGO_ENABLED=1 GOOS=darwin go build $GOFLAGS -buildmode=c-shared \
      -ldflags="-s -w" -o "$DIST_DIR/libuniclient.dylib" ./cmd/bridge/
    echo "Output: $DIST_DIR/libuniclient.dylib (+ libuniclient.h)"
    ;;
  android)
    if [ -z "${ANDROID_NDK_HOME:-}" ]; then
      if [ -n "${ANDROID_HOME:-}" ] && [ -d "${ANDROID_HOME}/ndk" ]; then
        ANDROID_NDK_HOME="$(ls -d "${ANDROID_HOME}"/ndk/* | sort -V | tail -1)"
      else
        echo "Error: ANDROID_NDK_HOME is not set and no NDK found under ANDROID_HOME." >&2
        exit 1
      fi
    fi
    export ANDROID_NDK_HOME
    TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
    for ARCH_PAIR in "arm64:aarch64-linux-android34:arm64-v8a" "amd64:x86_64-linux-android34:x86_64"; do
      GOARCH="${ARCH_PAIR%%:*}"
      REST="${ARCH_PAIR#*:}"
      CC_PREFIX="${REST%%:*}"
      ABI="${REST##*:}"
      OUT_DIR="$DIST_DIR/android/$ABI"
      mkdir -p "$OUT_DIR"
      echo "Building libuniclient.so for android/$GOARCH ($ABI)..."
      CGO_ENABLED=1 GOOS=android GOARCH=$GOARCH \
        CC="$TOOLCHAIN/${CC_PREFIX}-clang" \
        go build $GOFLAGS -buildmode=c-shared \
        -ldflags="-s -w" -o "$OUT_DIR/libuniclient.so" ./cmd/bridge/
    done
    echo "Output: $DIST_DIR/android/"
    ;;
  web|wasm|js)
    echo "Building uniclient.wasm for js/wasm..."
    GOOS=js GOARCH=wasm CGO_ENABLED=0 go build $GOFLAGS \
      -ldflags="-s -w" -o "$DIST_DIR/uniclient.wasm" ./cmd/bridge/
    echo "Output: $DIST_DIR/uniclient.wasm"
    echo "Host contract (see go/cmd/bridge/main_js.go):"
    echo "  globalThis.bridgeCall(req: Uint8Array) -> Promise<Uint8Array>"
    echo "  globalThis.bridgeSetEventCallback(cb | null)"
    ;;
  cli)
    echo "Building uniclient-cli for $(go env GOOS)/$(go env GOARCH)..."
    CGO_ENABLED=0 go build $GOFLAGS \
      -ldflags="-s -w" -o "$DIST_DIR/uniclient-cli" ./cmd/cli/
    echo "Output: $DIST_DIR/uniclient-cli"
    ;;
  *)
    echo "Unknown target: $TARGET" >&2
    echo "Usage: $0 [linux|windows|darwin|android|web|cli] [output-dir]" >&2
    exit 1
    ;;
esac
