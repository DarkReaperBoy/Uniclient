#!/bin/sh
# The executable gate (AGENTS.md §9) — enforcement is code, not memory.
#
# Usage: scripts/gate.sh quick|full [base-ref]
#   quick [base] — gofmt + vet + tests on the packages changed since <base>
#          (default origin/main) AND every package that imports them (test
#          imports count as edges). Run after every commit; mid-work it also
#          covers staged + unstaged edits (working tree vs base).
#   full  — every §9 tier except live/owner rungs: gofmt everywhere, vet +
#          tests for ALL packages (native leg + js/wasm leg for audio),
#          cross-build (windows). The web E2E + Xvfb GUI tiers return with
#          the rebuilt GUI (AGENTS.md §6).
#
# Recipes mirror scripts/dev-test.sh: audio verifies under GOOS=js (its
# WebAudio half only compiles there); everything else runs natively.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
GATE="${1:-}"
if [ $# -gt 0 ]; then shift; fi
BASE="${1:-origin/main}"

command -v go >/dev/null 2>&1 || { echo "gate: go not on PATH" >&2; exit 2; }
[ -n "$GATE" ] || { echo "usage: scripts/gate.sh quick|full|web [base-ref]" >&2; exit 2; }

cd "$ROOT/go"
export GOFLAGS=-p=1
export GOMEMLIMIT=3GiB GOGC=20
TAGS=goolm
# Small-machine recipe: gotd's tg package
# OOM-kills under default compile concurrency on <4GB-free boxes.
GCFLAGS="all=-c=1"
RUNNER="$ROOT/scripts/wasm-test-runner.sh"

fail() { echo "gate: FAIL — $*" >&2; exit 1; }

# go_run CMD... — run a go invocation; an OOM-killed COMPILE (gotd's tg needs
# >4GB free RAM; this box has a 4GiB cgroup) degrades to one EXPLICIT §9-rung-7
# skip line — CI verify.yml is the real gate on such machines. Anything else
# is a hard fail. Output is echoed either way.
go_run() {
        out=$(mktemp) || fail "mktemp"
        if "$@" >"$out" 2>&1; then
                cat "$out"; rm -f "$out"; return 0
        fi
        if grep -q "compile: signal: killed" "$out"; then
                echo "SKIP (§9 rung 7 — compile OOM, machine too small for gotd; dispatch verify.yml): $*"
                rm -f "$out"; return 0
        fi
        cat "$out"; rm -f "$out"
        fail "command failed: $*"
}

# --- package scoping -------------------------------------------------------
# Import paths of (a) packages with .go files changed since BASE and (b) the
# transitive closure of packages importing them. Empty output = nothing to do.
scoped_packages() {
        tmp=$(mktemp) || fail "mktemp"
        git -C "$ROOT" diff --name-only "$BASE" -- go/ >"$tmp.raw" || fail "git diff $BASE"
        # untracked files are invisible to git diff — but new files are the most
        # common change there is; fold them in (respecting .gitignore)
        git -C "$ROOT" ls-files --others --exclude-standard -- go/ >>"$tmp.raw"
        grep '\.go$' "$tmp.raw" | grep -v '/testdata/' | sed 's|^go/||' \
                | xargs -r -n1 dirname | sort -u >"$tmp.dirs"
        if grep -q 'third_party/anet' "$tmp.raw"; then
                echo "gate: NOTE — go/third_party/anet is a nested module; quick does not gate it (android-only, own go.mod)" >&2
        fi
        if [ ! -s "$tmp.dirs" ]; then
                rm -f "$tmp.raw" "$tmp.dirs"
                return 0
        fi
        MOD=$(go list -m)
        sed "s|^\./||;s|^|$MOD/|" "$tmp.dirs" >"$tmp.seeds"
        rm -f "$tmp.raw" "$tmp.dirs"
        # NB: go list -f does NOT interpret \t — build the format with printf so the
        # separators are REAL tabs (a literal "\t" silently breaks the awk split).
        FMT=$(printf '{{.ImportPath}}\t{{join .Imports ","}}\t{{join .TestImports ","}}')
        go list -tags "$TAGS" -f "$FMT" ./... \
                | awk -F'\t' -v seeds="$tmp.seeds" '
                        NR == FNR { sel[$0] = 1; next }
                        { pkgs[++np] = $1; edges[$1] = $2 "," $3 }
                        END {
                                dirty = 1
                                while (dirty) {
                                        dirty = 0
                                        for (p = 1; p <= np; p++) {
                                                name = pkgs[p]
                                                if (sel[name]) continue
                                                n = split(edges[name], arr, ",")
                                                for (i = 1; i <= n; i++)
                                                        if (arr[i] != "" && sel[arr[i]]) { sel[name] = 1; dirty = 1; break }
                                        }
                                }
                                for (p = 1; p <= np; p++) if (sel[pkgs[p]]) print pkgs[p]
                        }' "$tmp.seeds" -
        rm -f "$tmp.seeds"
}

run_native() {
        [ $# -gt 0 ] || return 0
        echo "== native vet: $* =="
        go_run env CGO_ENABLED=0 go vet -tags "$TAGS" -gcflags="$GCFLAGS" "$@"
        echo "== native test: $* =="
        go_run env CGO_ENABLED=1 go test -tags "$TAGS" -count=1 -gcflags="$GCFLAGS" "$@"
}

run_js() {
        [ $# -gt 0 ] || return 0
        echo "== js vet: $* =="
        GOOS=js GOARCH=wasm CGO_ENABLED=0 go vet -tags "$TAGS" "$@"
        echo "== js test (wasm runner) =="
        "$ROOT/scripts/test-wasm-runner.sh"
        GOOS=js GOARCH=wasm CGO_ENABLED=0 go test -tags "$TAGS" -count=1 -exec "$RUNNER" "$@"
}

partition_gio() {
        GIO_PKGS=""
        PURE_PKGS=""
        for p in "$@"; do
                [ -n "$p" ] || continue
                if go list -tags "$TAGS" -deps "$p" 2>/dev/null | grep -q '^gioui\.org/'; then
                        GIO_PKGS="$GIO_PKGS $p"
                else
                        PURE_PKGS="$PURE_PKGS $p"
                fi
        done
}

run_gio_legs() {
        [ -n "$GIO_PKGS" ] || return 0
        echo "== gio cgo legs (no root on this VM for xkbcommon/wayland/vulkan;"
        echo "   Linux-native compiles ride CI verify.yml — AGENTS.md §7/§9):$GIO_PKGS =="
        echo "== windows vet (local substitute) =="
        go_run env GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go vet -tags "$TAGS" -gcflags="$GCFLAGS" $GIO_PKGS
}

quick() {
        changed_go=$( {
                git -C "$ROOT" diff --name-only "$BASE" -- go/
                git -C "$ROOT" ls-files --others --exclude-standard -- go/
        } | grep '\.go$' || true)
        if [ -n "$changed_go" ]; then
                bad=$(cd "$ROOT" && echo "$changed_go" | xargs -r gofmt -l) || true
                [ -z "$bad" ] || fail "gofmt needed on: $bad"
        fi
        pkgs=$(scoped_packages)
        if [ -z "$pkgs" ]; then
                echo "quick: no Go packages changed since $BASE — trivially green"
                return 0
        fi
        echo "quick: scoped packages since $BASE:"
        echo "$pkgs" | sed 's/^/  /'
        nat=""; js=""
        for p in $pkgs; do
                case "$p" in
                        */audio|*/audio/*) js="$js $p" ;;
                        *) nat="$nat $p" ;;
                esac
        done
        partition_gio $nat
        # shellcheck disable=SC2086
        run_native $PURE_PKGS
        run_gio_legs
        # A runner change gates itself even when no Go package did (run_js
        # already self-tests whenever it runs; this covers the js-empty case).
        if [ -z "$js" ] && { git -C "$ROOT" diff --name-only "$BASE" -- scripts/wasm-test-runner.sh scripts/test-wasm-runner.sh | grep -q . \
                || git -C "$ROOT" status --porcelain -- scripts/wasm-test-runner.sh | grep -q .; }; then
                echo "== wasm runner changed — self-test =="
                "$ROOT/scripts/test-wasm-runner.sh"
        fi
        # shellcheck disable=SC2086
        run_js $js
        echo "quick gate GREEN"
}

full() {
        echo "== gofmt (all) =="
        bad=$(gofmt -l .) || true
        [ -z "$bad" ] || { echo "$bad"; fail "gofmt needed"; }
        all_pkgs=$(go list ./...)
        # shellcheck disable=SC2086
        partition_gio $all_pkgs
        echo "== native test: all (pure set) =="
        # shellcheck disable=SC2086
        go_run env CGO_ENABLED=1 go test -tags "$TAGS" -count=1 -gcflags="$GCFLAGS" $PURE_PKGS
        run_gio_legs
        echo "== js test: audio =="
        "$ROOT/scripts/test-wasm-runner.sh"
        GOOS=js GOARCH=wasm CGO_ENABLED=0 go test -tags "$TAGS" -count=1 \
                -exec "$RUNNER" ./audio/...
        echo "== vet: native + js split =="
        nat=$(echo $PURE_PKGS | tr ' ' '\n' | grep -vE '/(audio)(/|$)' | tr '\n' ' ')
        # shellcheck disable=SC2086
        go_run env CGO_ENABLED=0 go vet -tags "$TAGS" -gcflags="$GCFLAGS" $nat
        GOOS=js GOARCH=wasm CGO_ENABLED=0 go vet -tags "$TAGS" ./audio/...
        echo "== js/wasm compile: all (mirrors CI) =="
        go_run env GOOS=js GOARCH=wasm CGO_ENABLED=0 go build -tags "$TAGS" ./...
        echo "== cross-build: windows =="
        mkdir -p "$ROOT/dist"
        go_run env GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -tags "$TAGS" -gcflags="$GCFLAGS" \
                -trimpath -ldflags "-s -w" -o "$ROOT/dist/uniclient-windows-amd64.exe" ./cmd/uniclient
        echo "full gate GREEN"
}

case "$GATE" in
        quick) quick ;;
        full) full ;;
        *) echo "usage: scripts/gate.sh quick|full [base-ref]" >&2; exit 2 ;;
esac
