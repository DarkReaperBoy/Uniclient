#!/bin/sh
# wasm-test-runner.sh — runs a GOOS=js test binary under node with the Go
# wasm_exec glue. Verdict-first contract:
#   - any "--- FAIL" or trailing "FAIL" line in the output => non-zero exit,
#     no exceptions (a crash can make node exit 0 with a FAIL already
#     printed — the verdict is the truth, not the exit code);
#   - a bare `panic:` line with no verdict => non-zero exit (a wasm panic
#     kills the binary before the testing framework can print one);
#   - node exit 0 proves NOTHING by itself: node also exits 0 whenever its
#     event loop drains, and a hung/deadlocked wasm test binary drains it
#     while never printing a verdict (found via R14's self-deadlocking
#     test — the whole suite silently truncated and the leg went green).
#     Success REQUIRES the binary's own PASS line, at any node exit code;
#   - the one tolerated case: node crashes AFTER printing PASS (the known
#     js.Value teardown crash) => exit 0.
# Regression-pinned by scripts/test-wasm-runner.sh (hang / fail / pass).
# Used by scripts/dev-test.sh and scripts/gate.sh for the js/wasm test legs.
set -u

TESTBIN="$1"
shift  # remaining args are go-test flags (-run/-v/...) — forwarded (R21)
NODE_SCRIPT=$(mktemp /tmp/wasm-run-XXXXXX.js)
OUT=$(mktemp /tmp/wasm-out-XXXXXX.txt)
trap 'rm -f "$NODE_SCRIPT" "$OUT"' EXIT

cp "$(go env GOROOT)/lib/wasm/wasm_exec.js" "$NODE_SCRIPT"
cat >> "$NODE_SCRIPT" <<'EOF2'

(async () => {
  const go = new Go();
  // Forward EVERYTHING after the driver script — the binary path is argv[0]
  // and go-test flags (-test.run/-test.v/-test.count...) must reach the
  // binary (R21: hardcoding just the binary path silently ignored every
  // filter, so "filtered" evidence runs executed the whole suite).
  go.argv = process.argv.slice(2);
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

node "$NODE_SCRIPT" "$TESTBIN" "$@" > "$OUT" 2>/tmp/wasm-err.txt
cat "$OUT"
VERDICT=$(grep -E '^(PASS|FAIL|ok )' "$OUT" | tail -1)
if grep -q -- '--- FAIL' "$OUT" || tail -1 "$OUT" | grep -q '^FAIL'; then
  exit 1
fi
# A wasm panic kills the binary before the test framework prints any
# verdict, and node can still exit 0 — a bare panic line is a failure.
if grep -q '^panic:' "$OUT"; then
  exit 1
fi
if [ "$VERDICT" = "PASS" ]; then
  # The binary itself declared success — covers both a clean exit AND the
  # tolerated post-PASS teardown crash (node died after the verdict).
  exit 0
fi
# No PASS verdict: RC==0 means node's event loop drained with the binary
# hung or gone quiet (the R14 false-green), RC!=0 means it died early —
# either way the leg fails.
exit 1
