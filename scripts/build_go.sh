#!/usr/bin/env bash
set -euo pipefail

# Build Go shared library for the target platform.
# Usage: ./scripts/build_go.sh [linux|windows|darwin|android|web]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GO_DIR="$PROJECT_DIR/go"
BUILD_DIR="$GO_DIR/build"

mkdir -p "$BUILD_DIR"

TARGET="${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}"

cd "$GO_DIR"

case "$TARGET" in
  linux)
    echo "Building libcores.so for linux/amd64..."
    CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
      go build -tags goolm -buildmode=c-shared -o "$BUILD_DIR/libcores.so" ./bridge/
    echo "Output: $BUILD_DIR/libcores.so"
    ;;
  windows)
    echo "Building cores.dll for windows/amd64..."
    CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc \
      go build -tags goolm -buildmode=c-shared -o "$BUILD_DIR/cores.dll" ./bridge/
    echo "Output: $BUILD_DIR/cores.dll"
    ;;
  darwin)
    echo "Building libcores.dylib for darwin/arm64..."
    CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 \
      go build -tags goolm -buildmode=c-shared -o "$BUILD_DIR/libcores.dylib" ./bridge/
    echo "Output: $BUILD_DIR/libcores.dylib"
    ;;
  android)
    if [ -z "${ANDROID_NDK_HOME:-}" ]; then
      ANDROID_NDK_HOME="$ANDROID_HOME/ndk/26.1.10909125"
    fi
    for ARCH_PAIR in "arm64:aarch64-linux-android34" "amd64:x86_64-linux-android34"; do
      GOARCH="${ARCH_PAIR%%:*}"
      CC_PREFIX="${ARCH_PAIR##*:}"
      ABI="arm64-v8a"
      [ "$GOARCH" = "amd64" ] && ABI="x86_64"
      OUT_DIR="$BUILD_DIR/android/$ABI"
      mkdir -p "$OUT_DIR"
      echo "Building libcores.so for android/$GOARCH ($ABI)..."
      CGO_ENABLED=1 GOOS=android GOARCH=$GOARCH \
        CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/${CC_PREFIX}-clang" \
        go build -tags goolm -buildmode=c-shared -o "$OUT_DIR/libcores.so" ./bridge/
    done
    echo "Output: $BUILD_DIR/android/"
    ;;
  web|wasm)
    echo "Building cores.wasm for js/wasm..."
    GOOS=js GOARCH=wasm \
      go build -tags goolm -o "$BUILD_DIR/cores.wasm" ./bridge/
    cp "$(go env GOROOT)/misc/wasm/wasm_exec.js" "$BUILD_DIR/"
    echo "Output: $BUILD_DIR/cores.wasm + wasm_exec.js"
    ;;
  *)
    echo "Unknown target: $TARGET"
    echo "Usage: $0 [linux|windows|darwin|android|web]"
    exit 1
    ;;
esac

echo "Done."
