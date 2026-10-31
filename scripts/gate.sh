#!/bin/sh
# The executable gate (AGENTS.md §9) — enforcement is code, not memory.
#
# Usage: scripts/gate.sh quick|full|web [base-ref]
#   quick [base] — gofmt + vet + tests on the packages changed since <base>
#          (default origin/main) AND every package that imports them (test
#          imports count as edges). Run after every commit; mid-work it also
#          covers staged + unstaged edits (working tree vs base).
#   full  — every §9 tier except live/owner rungs: gofmt everywhere, vet +
#          tests for ALL packages (native leg + js/wasm leg), cross-builds
#          (windows + wasm), web E2E when node + node_modules are present
#          (an explicit SKIP line otherwise — never silent). The native Xvfb
#          GUI smoke lives in CI verify.yml.
#   web  — wasm build + the Puppeteer E2E suite (scripts/web-test).
#
# Recipes mirror scripts/dev-test.sh: gui/audio/cmd verify under GOOS=js
# (linux cgo headers not needed); everything else runs natively.

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
RUNNER="$ROOT/scripts/wasm-test-runner.sh"

fail() { echo "gate: FAIL — $*" >&2; exit 1; }

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
        CGO_ENABLED=0 go vet -tags "$TAGS" "$@"
        echo "== native test: $* =="
        CGO_ENABLED=1 go test -tags "$TAGS" -count=1 "$@"
}

run_js() {
        [ $# -gt 0 ] || return 0
        echo "== js vet: $* =="
        GOOS=js GOARCH=wasm CGO_ENABLED=0 go vet -tags "$TAGS" "$@"
        echo "== js test (wasm runner): $* =="
        GOOS=js GOARCH=wasm CGO_ENABLED=0 go test -tags "$TAGS" -count=1 -exec "$RUNNER" "$@"
}

web_e2e() {
        command -v node >/dev/null 2>&1 || { echo "web E2E: SKIP — node not on PATH"; return 0; }
        [ -d "$ROOT/scripts/web-test/node_modules" ] || {
                echo "web E2E: SKIP — scripts/web-test/node_modules missing (run npm ci there)"
                return 0
        }
        echo "== web E2E: Puppeteer suite =="
        (cd "$ROOT/scripts/web-test" && node run.mjs)
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
                        */gui|*/gui/*|*/audio|*/audio/*|*/cmd|*/cmd/*) js="$js $p" ;;
                        *) nat="$nat $p" ;;
                esac
        done
        # shellcheck disable=SC2086
        run_native $nat
        # shellcheck disable=SC2086
        run_js $js
        echo "quick gate GREEN"
}

full() {
        echo "== gofmt (all) =="
        bad=$(gofmt -l .) || true
        [ -z "$bad" ] || { echo "$bad"; fail "gofmt needed"; }
        echo "== native test: all =="
        CGO_ENABLED=1 go test -tags "$TAGS" -count=1 ./...
        echo "== js test: gui audio cmd =="
        GOOS=js GOARCH=wasm CGO_ENABLED=0 go test -tags "$TAGS" -count=1 \
                -exec "$RUNNER" ./gui/... ./audio/... ./cmd/...
        echo "== vet: native + js split =="
        nat=$(go list ./... | grep -vE '/(gui|audio|cmd)(/|$)' | tr '\n' ' ')
        # shellcheck disable=SC2086
        CGO_ENABLED=0 go vet -tags "$TAGS" $nat
        GOOS=js GOARCH=wasm CGO_ENABLED=0 go vet -tags "$TAGS" ./gui/... ./audio/... ./cmd/...
        echo "== cross-builds: windows + wasm =="
        mkdir -p "$ROOT/dist"
        GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -tags "$TAGS" \
                -trimpath -ldflags "-s -w" -o "$ROOT/dist/uniclient-windows-amd64.exe" ./cmd/uniclient
        GOOS=js GOARCH=wasm CGO_ENABLED=0 go build -tags "$TAGS" \
                -trimpath -ldflags "-s -w" -o "$ROOT/dist/uniclient.wasm" ./cmd/uniclient
        web_e2e
        echo "full gate GREEN"
}

web() {
        echo "== wasm build =="
        mkdir -p "$ROOT/dist"
        GOOS=js GOARCH=wasm CGO_ENABLED=0 go build -tags "$TAGS" \
                -trimpath -ldflags "-s -w" -o "$ROOT/dist/uniclient.wasm" ./cmd/uniclient
        web_e2e
        echo "web gate GREEN"
}

case "$GATE" in
        quick) quick ;;
        full) full ;;
        web) web ;;
        *) echo "usage: scripts/gate.sh quick|full|web [base-ref]" >&2; exit 2 ;;
esac
