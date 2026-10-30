#!/bin/sh
# wasm-test-runner.sh — runs a GOOS=js test binary under node with the Go
# wasm_exec glue. Verdict-first contract:
#   - any "--- FAIL" or trailing "FAIL" line in the output => non-zero exit,
#     no exceptions (a crash can make node exit 0 with a FAIL already
#     printed — the verdict is the truth, not the exit code);
#   - the one tolerated case: node crashes AFTER printing PASS (the known
#     js.Value teardown crash) => exit 0.
# Used by scripts/dev-test.sh for the js/wasm test legs.
set -u

TESTBIN="$1"
NODE_SCRIPT=$(mktemp /tmp/wasm-run-XXXXXX.js)
OUT=$(mktemp /tmp/wasm-out-XXXXXX.txt)
trap 'rm -f "$NODE_SCRIPT" "$OUT"' EXIT

cp "$(go env GOROOT)/lib/wasm/wasm_exec.js" "$NODE_SCRIPT"
cat >> "$NODE_SCRIPT" <<'EOF2'

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
if grep -q -- '--- FAIL' "$OUT" || tail -1 "$OUT" | grep -q '^FAIL'; then
  exit 1
fi
# A wasm panic kills the binary before the test framework prints any
# verdict, and node can still exit 0 — a bare panic line is a failure.
if grep -q '^panic:' "$OUT"; then
  exit 1
fi
if [ "$RC" -eq 0 ]; then
  exit 0
fi
VERDICT=$(grep -E '^(PASS|FAIL|ok )' "$OUT" | tail -1)
if [ "$VERDICT" = "PASS" ]; then
  exit 0
fi
exit "$RC"
