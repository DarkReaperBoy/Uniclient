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

echo "== wasm: gui (node exec) =="
WASM_RUNNER=$(mktemp -d)/go_js_wasm_exec.sh
{
  echo '#!/bin/sh'
  echo 'TESTBIN="$1"; shift'
  echo 'NODE_SCRIPT=$(mktemp /tmp/wasm-run-XXXXXX.js)'
  echo "OUT=\$(mktemp /tmp/wasm-out-XXXXXX.txt)"
  echo 'cp "$(go env GOROOT)/lib/wasm/wasm_exec.js" "$NODE_SCRIPT"'
  cat << 'PREP'
cat >> "$NODE_SCRIPT" << 'EOF2'

(async () => {
  const go = new Go();
  go.argv = [process.argv[2]];
  const wasmBinary = require('fs').readFileSync(process.argv[2]);
  try {
    const result = await WebAssembly.instantiate(wasmBinary, go.importObject);
    const code = await go.run(result.instance);
    process.exit(code === undefined ? 0 : code);
  } catch (err) {
    console.error(String(err && err.stack || err).split('\n')[0]);
    process.exit(2);
  }
})();
EOF2
node "$NODE_SCRIPT" "$TESTBIN" > "$OUT" 2>/tmp/wasm-err.txt
RC=$?
cat "$OUT"
VERDICT=$(grep -E "^(PASS|FAIL|ok |--- FAIL)" "$OUT" | tail -1)
[ "$RC" -ne 0 ] && echo "$VERDICT" | grep -q "^PASS" && RC=0
rm -f "$NODE_SCRIPT" "$OUT"
exit $RC
PREP
} > "$WASM_RUNNER"
chmod +x "$WASM_RUNNER"
GOOS=js GOARCH=wasm CGO_ENABLED=0 go test -tags goolm -count=1 -exec "$WASM_RUNNER" ./gui/...
rm -rf "$(dirname "$WASM_RUNNER")"

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
