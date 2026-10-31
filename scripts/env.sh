#!/bin/sh
# Toolchain env for the recycled dev VM (AGENTS.md §1.14 — the recipe lives in the
# repo; the toolchain itself stays OUTSIDE it, untracked, because it is an artifact).
#
# Full-wipe recovery, proven 2026-10-31 (survived wipe #2):
#   1. TOOLCHAIN=<somewhere persistent>; mkdir -p "$TOOLCHAIN"
#   2. curl -L https://go.dev/dl/go1.27.0.linux-amd64.tar.gz | tar -C "$TOOLCHAIN" -xz
#   3. . scripts/env.sh            # sets GOROOT/GOMODCACHE/GOCACHE/PATH (below)
#   4. (cd go && go mod download)  # refill the module cache (~1.2G)
#   5. cd scripts/web-test && npm ci && npx puppeteer browsers install chrome
#      (npm postinstall may be policy-blocked; the explicit install covers it)
#   6. CGO sysroot needs (native gui builds only): scripts/devroot-setup.sh
#
# Machine truths: 4GiB cgroup — gotd native compiles OOM here, so gate.sh falls
# back to §9.7 (dispatch verify.yml). Long processes are reaped between tool
# calls — run foreground; the build cache carries progress across calls.

TOOLCHAIN="${TOOLCHAIN:-$(cd "$(dirname "$0")/.." && pwd)/../toolchain}"
export GOROOT="$TOOLCHAIN/go"
export PATH="$GOROOT/bin:$PATH"
export GOMODCACHE="$TOOLCHAIN/mod"
export GOCACHE="$TOOLCHAIN/gocache"
export GOFLAGS=-p=1
export GOMEMLIMIT=3GiB
export GOGC=20
export PUPPETEER_CACHE_DIR="$TOOLCHAIN/puppeteer-cache"
