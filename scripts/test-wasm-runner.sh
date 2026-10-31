#!/bin/sh
# test-wasm-runner.sh — regression harness for scripts/wasm-test-runner.sh.
#
# The runner is the SOLE verdict source for every js/wasm test leg
# (dev-test.sh, gate.sh quick/full). A hole in it silently turns any hung
# test into a green leg — exactly what R14 exposed: a self-deadlocking
# test parked the wasm binary forever, node's event loop drained, node
# exited 0, and the runner's old `RC==0 → exit 0` short-circuit declared
# GREEN while the suite had silently truncated (a false green of the F-88
# class). This harness pins the three contracts the runner must keep:
#
#   1. hang   — a wasm test binary that deadlocks and prints NO verdict
#               must FAIL the leg, whatever node's exit code is;
#   2. fail   — a printed `--- FAIL:` verdict must FAIL the leg even if
#               the process exits 0 (the F-88 contract);
#   3. pass   — a healthy binary's PASS verdict must PASS the leg;
#   4. flags  — go-test flags (-run / -v) after the binary path must reach
#               the binary (R21: the old driver hardcoded go.argv to just
#               the binary path, so every "filtered" evidence run silently
#               executed the WHOLE suite — an evidence-integrity hole in
#               the sole verdict source, Law 22).
#
# Fixtures are three dependency-free Go test binaries built in a temp dir
# (instant builds). A `timeout` guard keeps a regressed runner from hanging
# the harness itself: RC 124 means the runner never returned — a failure
# of the harness check, never a pass-by-accident.
#
# Usage: scripts/test-wasm-runner.sh   (run from anywhere; needs go + node)

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUNNER="$ROOT/scripts/wasm-test-runner.sh"

command -v go >/dev/null 2>&1 || { echo "test-wasm-runner: SKIP — go not on PATH"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "test-wasm-runner: SKIP — node not on PATH"; exit 0; }
[ -x "$RUNNER" ] || { echo "test-wasm-runner: FAIL — runner not executable: $RUNNER" >&2; exit 1; }

WORK=$(mktemp -d) || { echo "test-wasm-runner: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# build_fixture <name> <test-body> — writes a one-test module and compiles
# it to a GOOS=js test binary at $WORK/<name>.test.
build_fixture() {
        name="$1"; body="$2"
        mkdir -p "$WORK/$name"
        cat > "$WORK/$name/go.mod" <<EOF
module $name

go 1.27
EOF
        cat > "$WORK/$name/${name}_test.go" <<EOF
package main

import (
        "sync"
        "testing"
)

type app struct {
        mu   sync.Mutex
        flag bool
}

func (a *app) snapshot() bool {
        a.mu.Lock()
        defer a.mu.Unlock()
        return a.flag
}

$body
EOF
        (cd "$WORK/$name" && GOOS=js GOARCH=wasm CGO_ENABLED=0 \
                go test -c -o "$WORK/$name.test" .) || {
                echo "test-wasm-runner: FAIL — fixture $name did not build" >&2
                exit 1
        }
}

# run_case <name> <expect: fail|pass> — runs the fixture through the
# runner and asserts the verdict class. timeout 120 guards a hung runner.
run_case() {
        name="$1"; expect="$2"
        timeout 120 "$RUNNER" "$WORK/$name.test" >/dev/null 2>&1
        rc=$?
        if [ "$rc" -eq 124 ]; then
                echo "test-wasm-runner: FAIL — runner never returned on $name (timeout)" >&2
                exit 1
        fi
        if [ "$expect" = "fail" ] && [ "$rc" -eq 0 ]; then
                echo "test-wasm-runner: FAIL — runner declared GREEN on $name (rc=0), expected a failure" >&2
                exit 1
        fi
        if [ "$expect" = "pass" ] && [ "$rc" -ne 0 ]; then
                echo "test-wasm-runner: FAIL — runner failed a healthy binary ($name, rc=$rc)" >&2
                exit 1
        fi
        echo "test-wasm-runner: ok — $name handled (runner rc=$rc, expected $expect)"
}

# 1. hang: the R14 shape — hold a.mu, call a method that locks a.mu again.
#    The binary prints no verdict; node exits 0 on a drained event loop.
build_fixture hang 'func TestSelfDeadlock(t *testing.T) {
        a := &app{}
        a.mu.Lock()
        got := a.snapshot()
        a.mu.Unlock()
        if got {
                t.Fatal("unreachable")
        }
}'

# 2. fail: a real failing test — `--- FAIL:` printed, exit code 1.
build_fixture failtest 'func TestAlwaysFails(t *testing.T) {
        t.Fatal("intentional fixture failure")
}'

# 3. pass: a healthy binary — the framework prints PASS, exits 0.
build_fixture passtest 'func TestPasses(t *testing.T) {
        a := &app{}
        a.mu.Lock()
        a.flag = true
        a.mu.Unlock()
        if !a.snapshot() {
                t.Fatal("snapshot lost the flag")
        }
}'

# 4. flags (R21): with forwarding, -test.run=TestForwarded must keep the
#    binary on TestForwarded only — TestOther (which fails) never runs and
#    -test.v shows the RUN line. With the old argv-dropping driver the
#    filter was silently ignored, TestOther ran and failed the leg.
build_fixture flagfwd 'func TestForwarded(t *testing.T) {}

func TestOther(t *testing.T) {
        t.Fatal("must be filtered out by -test.run")
}'

run_case hang fail
run_case failtest fail
run_case passtest pass

# Contract 4: verdict must be PASS (TestOther filtered out) and the
# verbose RUN line must appear in the runner's stdout.
FLAG_OUT=$(timeout 120 "$RUNNER" "$WORK/flagfwd.test" -test.run=TestForwarded -test.v=true 2>/dev/null)
FLAG_RC=$?
if [ "$FLAG_RC" -eq 124 ]; then
        echo "test-wasm-runner: FAIL — runner never returned on flagfwd (timeout)" >&2
        exit 1
fi
if [ "$FLAG_RC" -ne 0 ] || ! printf '%s' "$FLAG_OUT" | grep -q 'RUN.*TestForwarded' || printf '%s' "$FLAG_OUT" | grep -q 'TestOther'; then
        echo "test-wasm-runner: FAIL — flags not forwarded (rc=$FLAG_RC; want TestForwarded run, TestOther filtered)" >&2
        exit 1
fi
echo "test-wasm-runner: ok — flagfwd handled (-run/-v reach the binary, rc=$FLAG_RC)"

echo "test-wasm-runner: ALL CONTRACTS GREEN (hang caught, fail caught, pass accepted, flags forwarded)"
