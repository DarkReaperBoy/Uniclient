#!/usr/bin/env bash
set -euo pipefail

# Build Flutter app for the target platform.
# Usage: ./scripts/build_flutter.sh [linux|android|web] [debug|profile|release]
#
# NixOS workaround: Flutter's build system rejects symlinked engine artifacts
# (nix store uses symlinks). This script bypasses Flutter's unpack step by:
# 1. Compiling Dart code with Flutter's frontend_server directly
# 2. Populating the ephemeral directory from dereferenced engine artifacts
# 3. Building the native runner with CMake/Ninja
#
# Requires: nix-shell (auto-provides cmake, ninja, pkg-config, gtk3)

PLATFORM="${1:-linux}"
BUILD_MODE="${2:-debug}"
DART_DIR="$(cd "$(dirname "$0")/../dart" && pwd)"

# Find Flutter SDK
FLUTTER_SDK="${FLUTTER_ROOT:-}"
if [[ -z "$FLUTTER_SDK" ]]; then
  if command -v flutter &>/dev/null; then
    FLUTTER_SDK="$(dirname "$(dirname "$(readlink -f "$(which flutter)")")")"
  fi
fi

if [[ -z "$FLUTTER_SDK" ]]; then
  echo "ERROR: Flutter SDK not found. Run inside 'nix develop' or set FLUTTER_ROOT."
  exit 1
fi

DART_SDK="$FLUTTER_SDK/bin/cache/dart-sdk"
DARTAOT="$DART_SDK/bin/dartaotruntime"
ENGINE_DIR="$FLUTTER_SDK/bin/cache/artifacts/engine"

echo "Flutter SDK: $FLUTTER_SDK"
echo "Platform:    $PLATFORM"
echo "Mode:        $BUILD_MODE"

case "$PLATFORM" in
  linux)
    ENGINE_VARIANT="linux-x64"
    EPHEMERAL="$DART_DIR/linux/flutter/ephemeral"
    BUILD_DIR="$DART_DIR/build/linux/x64/$BUILD_MODE"

    echo ""
    echo "=== Step 1: Compile Dart code ==="
    mkdir -p "$BUILD_DIR/flutter_assets"

    PATCHED_SDK="$ENGINE_DIR/common/flutter_patched_sdk/"
    if [[ "$BUILD_MODE" == "release" ]]; then
      PATCHED_SDK="$ENGINE_DIR/common/flutter_patched_sdk_product/"
    fi

    # Use Flutter's asset bundler for proper font/asset manifests
    cd "$DART_DIR"
    CI=true FLUTTER_SUPPRESS_ANALYTICS=true "$FLUTTER_SDK/bin/flutter" build bundle \
      --debug --target lib/main.dart \
      --asset-dir "$BUILD_DIR/flutter_assets" 2>&1 | tail -3
    cd - >/dev/null

    # Compile Dart with Flutter's frontend_server (overwrite the kernel_blob from bundle)
    "$DARTAOT" "$ENGINE_DIR/$ENGINE_VARIANT/frontend_server_aot.dart.snapshot" \
      --sdk-root "$PATCHED_SDK" \
      --target=flutter \
      --packages="$DART_DIR/.dart_tool/package_config.json" \
      --output-dill "$BUILD_DIR/flutter_assets/kernel_blob.bin" \
      --track-widget-creation \
      "$DART_DIR/lib/main.dart" 2>&1 | tail -1

    # Copy VM snapshots (chmod in case previous copies from nix store are read-only)
    chmod u+w "$BUILD_DIR/flutter_assets/vm_isolate_snapshot.bin" "$BUILD_DIR/flutter_assets/isolate_snapshot.bin" 2>/dev/null || true
    cp -Lf "$ENGINE_DIR/$ENGINE_VARIANT/vm_isolate_snapshot.bin" "$BUILD_DIR/flutter_assets/"
    cp -Lf "$ENGINE_DIR/$ENGINE_VARIANT/isolate_snapshot.bin" "$BUILD_DIR/flutter_assets/"
    echo "  Dart compilation done."

    echo ""
    echo "=== Step 2: Populate ephemeral directory ==="
    mkdir -p "$EPHEMERAL/cpp_client_wrapper/include/flutter"
    mkdir -p "$EPHEMERAL/flutter_linux"

    # Engine library + ICU data (dereference symlinks, force overwrite read-only from nix store)
    chmod u+w "$EPHEMERAL/libflutter_linux_gtk.so" "$EPHEMERAL/icudtl.dat" 2>/dev/null || true
    cp -Lf "$ENGINE_DIR/$ENGINE_VARIANT/libflutter_linux_gtk.so" "$EPHEMERAL/"
    cp -Lf "$ENGINE_DIR/$ENGINE_VARIANT/icudtl.dat" "$EPHEMERAL/"

    # GTK headers
    chmod u+w "$EPHEMERAL/flutter_linux/"*.h 2>/dev/null || true
    cp -Lf "$ENGINE_DIR/$ENGINE_VARIANT/flutter_linux/"*.h "$EPHEMERAL/flutter_linux/" 2>/dev/null || true

    # C API headers
    PUBLIC_HEADERS="$FLUTTER_SDK/engine/src/flutter/shell/platform/common/public"
    if [[ -d "$PUBLIC_HEADERS" ]]; then
      chmod u+w "$EPHEMERAL/"*.h 2>/dev/null || true
      cp -Lf "$PUBLIC_HEADERS"/*.h "$EPHEMERAL/" 2>/dev/null || true
    fi

    # C++ client wrapper (from engine source tree)
    COMMON_WRAPPER="$FLUTTER_SDK/engine/src/flutter/shell/platform/common/client_wrapper"
    if [[ -d "$COMMON_WRAPPER" ]]; then
      chmod -R u+w "$EPHEMERAL/cpp_client_wrapper/" 2>/dev/null || true
      # Source files
      for f in core_implementations.cc standard_codec.cc plugin_registrar.cc engine_method_result.cc; do
        cp -f "$COMMON_WRAPPER/$f" "$EPHEMERAL/cpp_client_wrapper/" 2>/dev/null || true
      done
      # Private headers
      for f in binary_messenger_impl.h byte_buffer_streams.h texture_registrar_impl.h; do
        cp -f "$COMMON_WRAPPER/$f" "$EPHEMERAL/cpp_client_wrapper/" 2>/dev/null || true
      done
      # Public headers
      cp -f "$COMMON_WRAPPER/include/flutter/"*.h "$EPHEMERAL/cpp_client_wrapper/include/flutter/" 2>/dev/null || true
    fi
    echo "  Ephemeral populated."

    echo ""
    echo "=== Step 3: Build native runner ==="
    mkdir -p "$BUILD_DIR/native_assets/linux"

    # Build with nix-shell to get GTK dev dependencies
    nix-shell -p cmake ninja pkg-config gtk3.dev glib.dev pango.dev cairo.dev atk.dev gdk-pixbuf.dev --run "
      cd '$BUILD_DIR' &&
      rm -f CMakeCache.txt &&
      export FLUTTER_SKIP_ASSEMBLE=1 &&
      cmake '$DART_DIR/linux' -DCMAKE_BUILD_TYPE=Debug -G Ninja 2>&1 | tail -3 &&
      ninja install 2>&1
    " 2>/dev/null

    # Copy Go shared library into bundle
    GO_LIB="$(cd "$(dirname "$0")/../go/build" && pwd)/libcores.so"
    if [[ -f "$GO_LIB" ]]; then
      cp -f "$GO_LIB" "$BUILD_DIR/bundle/lib/libcores.so"
      echo "  Copied libcores.so into bundle."
    else
      echo "  WARNING: libcores.so not found at $GO_LIB — run scripts/build_go.sh first"
    fi

    echo ""
    echo "=== Build complete ==="
    echo "Bundle: $BUILD_DIR/bundle/"
    echo "Binary: $BUILD_DIR/bundle/uniclient"
    echo "Run:    $BUILD_DIR/bundle/uniclient"
    ;;

  android)
    cd "$DART_DIR"
    export FLUTTER_ROOT="$FLUTTER_SDK"
    export CI=true
    export FLUTTER_SUPPRESS_ANALYTICS=true
    "$FLUTTER_SDK/bin/flutter" build apk "--$BUILD_MODE" 2>&1
    ;;

  web)
    cd "$DART_DIR"
    export FLUTTER_ROOT="$FLUTTER_SDK"
    export CI=true
    export FLUTTER_SUPPRESS_ANALYTICS=true
    "$FLUTTER_SDK/bin/flutter" build web 2>&1
    ;;

  *)
    echo "Usage: $0 [linux|android|web] [debug|profile|release]"
    exit 1
    ;;
esac
