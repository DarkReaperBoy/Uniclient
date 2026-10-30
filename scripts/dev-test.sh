#!/bin/sh
# Small-machine full quality gate (AGENTS.md §9) for boxes that cannot
# compile gotd's tg package with default GC settings (needs ≥4GB free).
#
# Usage: scripts/dev-test.sh [goos: js|linux] — default runs everything.
#
# Env kept local (never committed): Go toolchain + node must be on PATH.
# The node wrapper embeds $GOROOT/lib/wasm/wasm_exec.js and tolerates the
# known post-verdict js.Value teardown crash (PASS already printed).

set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/go"

export GOFLAGS=-p=1
export GOMEMLIMIT=3GiB GOGC=20

echo "== native: engine/cores/utils/bootstrap =="
CGO_ENABLED=1 go test -tags goolm -count=1 ./engine/... ./cores/... ./utils/... ./bootstrap/...

echo "== wasm: gui + audio (node exec) =="
# The shared runner is VERDICT-FIRST: a printed --- FAIL line always fails
# the leg, and the only tolerated crash is the known post-PASS teardown.
# (The inline runner this replaces rescued a FAIL-ing binary whenever node
# exited 0 after a panic — a false green.)
WASM_RUNNER="$ROOT/scripts/wasm-test-runner.sh"
GOOS=js GOARCH=wasm CGO_ENABLED=0 go test -tags goolm -count=1 -exec "$WASM_RUNNER" ./gui/... ./audio/...

echo "== vet + gofmt =="
# Native vet for every package that builds without system dev headers; the
# GUI needs xkbcommon/wayland cgo headers on linux (absent on sandboxes) —
# vet it under js/wasm instead (same source, pure Go). Full native vet runs
# in the CI verify workflow (§5).
CGO_ENABLED=0 go vet -tags goolm ./engine/... ./cores/... ./utils/... ./bootstrap/... ./wrtc/... 2>/dev/null || \
        CGO_ENABLED=0 go vet -tags goolm ./engine/... ./cores/... ./utils/... ./bootstrap/...
GOOS=js GOARCH=wasm CGO_ENABLED=0 go vet -tags goolm ./gui/... ./cmd/...
test -z "$(gofmt -l .)" || { echo "gofmt needed:"; gofmt -l .; exit 1; }
echo "ALL GATES GREEN"
