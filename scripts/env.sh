#!/bin/sh
# Toolchain env for the recycled dev VM (AGENTS.md — the recipe lives in the
# repo; the toolchain itself stays OUTSIDE it, untracked, because it is an artifact).
#
# Full-wipe recovery, proven 2026-10-31 (survived wipe #2):
#   1. TOOLCHAIN=<somewhere persistent>; mkdir -p "$TOOLCHAIN"
#   2. curl -L https://go.dev/dl/go1.27.1.linux-amd64.tar.gz | tar -C "$TOOLCHAIN" -xz
#      (one go build per GOCACHE — two different versions sharing one
#      cache poison it with "version does not match" compile errors)
#   3. . scripts/env.sh            # sets GOROOT/GOMODCACHE/GOCACHE/PATH (below)
#   4. (cd go && go mod download)  # refill the module cache (~1.2G)
#
# Machine truths: 4GiB cgroup — gotd native compiles OOM here, so gate.sh falls
# back to CI dispatch (verify.yml; AGENTS.md §9). No root — gio's cgo X11/
# Wayland/Vulkan client libs (libxkbcommon-dev, libwayland-dev,
# libvulkan-dev) cannot be installed:
# gate.sh routes gio-importing packages through windows cross-vet, Linux-native
# rides CI. Long processes are reaped between tool calls — run foreground; the
# build cache carries progress across calls.

# Sourced, never executed (exports must reach the caller's shell): `. scripts/env.sh`

_self="${BASH_SOURCE[0]:-$0}"
TOOLCHAIN="${TOOLCHAIN:-$(cd "$(dirname "$_self")/.." && pwd)/../toolchain}"
unset _self
[ -x "$TOOLCHAIN/go/bin/go" ] || echo "env.sh: warning — no go at $TOOLCHAIN/go (see recovery steps above)" >&2
export GOROOT="$TOOLCHAIN/go"
export PATH="$GOROOT/bin:$PATH"
export GOMODCACHE="$TOOLCHAIN/mod"
export GOCACHE="$TOOLCHAIN/gocache"
export GOFLAGS=-p=1
export GOMEMLIMIT=3GiB
export GOGC=20
