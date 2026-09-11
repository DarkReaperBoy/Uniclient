#!/bin/sh
# devroot-setup.sh — build a user-space sysroot for CGO (Gio) builds on a
# no-sudo Debian-ish runner, plus a Go toolchain if missing.
#
# Why: sandbox VMs reset and often lack the X11/wayland/EGL/vulkan dev
# packages that Gio's Linux backend needs, and may lack the Go toolchain
# entirely. This script needs NO root: it `apt download`s the dev .debs
# (works as a normal user, downloads into CWD) and extracts them into
# ~/.local/sysroot, then prints the env exports to source.
#
# Usage:  sh scripts/devroot-setup.sh && . ./devroot.env
# Then:   GOGC=20 go build -p 1 -tags goolm -gcflags="all=-c=1" ./...
# (gotd's tg package OOM-kills on machines with <4GB free RAM;
#  GOGC=20 + -gcflags=all=-c=1 + -p 1 keeps it inside ~3.5GB.)
set -e

ROOT="$HOME/.local"
SYSROOT="$ROOT/sysroot"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Go toolchain (go.mod needs go 1.27) -----------------------------------
if ! command -v go >/dev/null 2>&1 || ! go version | grep -q "go1.2[78]"; then
    if [ ! -x "$ROOT/go/bin/go" ]; then
        echo ">> installing Go 1.27.1 to $ROOT/go"
        curl -sL https://go.dev/dl/go1.27.1.linux-amd64.tar.gz -o "$WORK/go.tgz"
        mkdir -p "$ROOT"
        rm -rf "$ROOT/go"
        tar -C "$ROOT" -xzf "$WORK/go.tgz"
    fi
fi
export PATH="$ROOT/go/bin:$PATH"
go version

# --- dev packages into the sysroot -----------------------------------------
mkdir -p "$SYSROOT"
cd "$WORK"

pkgs=""
pkgs="$pkgs libxkbcommon-dev libxkbcommon-x11-dev libxkbcommon-x11-0"     # xkb / xkb-x11
pkgs="$pkgs libwayland-dev libwayland-client0"                            # wayland
pkgs="$pkgs libegl-dev libegl1 libglvnd-dev libglvnd0"                    # EGL (+KHR glue)
pkgs="$pkgs libxcursor-dev libxfixes-dev libx11-xcb-dev"                  # X extras
pkgs="$pkgs libxcb-xkb-dev libxcb-xkb1"                                   # xcb-xkb
pkgs="$pkgs libxcursor1 libxfixes3 libx11-xcb1"                           # runtimes for those
# libvulkan-dev is NOT in apt on some sandboxes; pull from the Debian pool.
apt download $pkgs 2>/dev/null || echo "!! some apt downloads failed (maybe already present)"
for f in *.deb; do dpkg -x "$f" "$SYSROOT"; done

# vulkan headers via pool (package name varies by suite)
if [ ! -d "$SYSROOT/usr/include/vulkan" ]; then
    F=$(curl -sL 'https://deb.debian.org/debian/pool/main/v/vulkan-loader/' \
        | grep -oE 'libvulkan-dev_[^"]*amd64\.deb' | sort -V | tail -1)
    [ -n "$F" ] && curl -sL -o vk.deb \
        "https://deb.debian.org/debian/pool/main/v/vulkan-loader/$F" \
        && dpkg -x vk.deb "$SYSROOT"
    F=$(curl -sL 'https://deb.debian.org/debian/pool/main/libv/libvulkan-loader/' \
        | grep -oE 'libvulkan-dev_[^"]*amd64\.deb' | sort -V | tail -1)
    [ -z "$(ls "$SYSROOT"/usr/include/vulkan 2>/dev/null)" ] && [ -n "$F" ] \
        && curl -sL -o vk.deb \
        "https://deb.debian.org/debian/pool/main/libv/libvulkan-loader/$F" \
        && dpkg -x vk.deb "$SYSROOT"
fi

# KHR/khrplatform.h (Khronos registry; not shipped by the debs above)
if [ ! -f "$SYSROOT/usr/include/KHR/khrplatform.h" ]; then
    mkdir -p "$SYSROOT/usr/include/KHR"
    curl -sL -o "$SYSROOT/usr/include/KHR/khrplatform.h" \
        "https://raw.githubusercontent.com/KhronosGroup/EGL-Registry/main/api/KHR/khrplatform.h"
fi

# --- fix the sysroot: pc prefixes + dangling .so symlinks ------------------
PCDIR="$SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig"
for pc in "$PCDIR"/*.pc; do
    sed -i "s|^prefix=/usr$|prefix=$SYSROOT/usr|" "$pc"
done
# xcb-xkb must be a PUBLIC dep of xkbcommon-x11 for final links to resolve
[ -f "$PCDIR/xkbcommon-x11.pc" ] && grep -q "^Requires.private: xcb" "$PCDIR/xkbcommon-x11.pc" \
    && sed -i 's|^Requires.private: xcb >= 1.10, xcb-xkb >= 1.10$|Requires: xkbcommon, xcb, xcb-xkb|' \
        "$PCDIR/xkbcommon-x11.pc"

LIBDIR="$SYSROOT/usr/lib/x86_64-linux-gnu"
cd "$LIBDIR"
for link in *.so; do
    [ -L "$link" ] || continue
    target=$(readlink "$link")
    if [ ! -e "$target" ]; then
        if [ -e "/usr/lib/x86_64-linux-gnu/$target" ]; then
            cp -L "/usr/lib/x86_64-linux-gnu/$target" "./$target"
        fi
    fi
done

# --- emit the env -----------------------------------------------------------
ENVF="$(dirname "$0")/../devroot.env"
cat > "$ENVF" <<EOF
export PATH="$ROOT/go/bin:\$PATH"
export PKG_CONFIG_PATH="$PCDIR"
export CGO_LDFLAGS="-L$LIBDIR"
export LD_LIBRARY_PATH="$LIBDIR:\$LD_LIBRARY_PATH"
export GOGC=20
EOF
echo ""
echo ">> sysroot ready. run:  . $ENVF"
echo ">> build with:         go build -p 1 -tags goolm -gcflags='all=-c=1' ./..."
