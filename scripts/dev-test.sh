#!/bin/sh
# Small-machine full quality gate (AGENTS.md §7) for boxes that cannot
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

echo "== wasm: audio (node exec) =="
# The shared runner is VERDICT-FIRST and self-tested: a printed --- FAIL line
# always fails the leg, node exit 0 alone proves nothing (a hung/deadlocked
# binary drains node's event loop — exit 0 with no verdict — found via R14),
# and the only tolerated crash is the known post-PASS teardown. Pin those
# contracts before trusting a single verdict from the runner.
"$ROOT/scripts/test-wasm-runner.sh"
WASM_RUNNER="$ROOT/scripts/wasm-test-runner.sh"
GOOS=js GOARCH=wasm CGO_ENABLED=0 go test -tags goolm -count=1 -exec "$WASM_RUNNER" ./audio/...

echo "== vet + gofmt =="
# Native vet for every package that builds without system dev headers.
# The audio package (WebAudio js half) vets under js/wasm. Full native vet
# runs in the CI verify workflow.
CGO_ENABLED=0 go vet -tags goolm ./engine/... ./cores/... ./utils/... ./bootstrap/... ./wrtc/... 2>/dev/null || \
        CGO_ENABLED=0 go vet -tags goolm ./engine/... ./cores/... ./utils/... ./bootstrap/...
GOOS=js GOARCH=wasm CGO_ENABLED=0 go vet -tags goolm ./audio/...
test -z "$(gofmt -l .)" || { echo "gofmt needed:"; gofmt -l .; exit 1; }
echo "ALL GATES GREEN"
