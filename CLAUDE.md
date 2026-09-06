# CLAUDE.md

**MANDATORY — every rule in this file is a HARD requirement, not a suggestion.**

## What This Project Is

**Uniclient Go core** — pure Go backend for a unified multi-platform messaging
client. No UI lives here; the frontend is a separate project that consumes
this core over FFI (c-shared library).

- **Pure Go only.** ZERO CGo dependencies, no C/C++ libs, no pkg-config, no
  system libraries. The only `import "C"` allowed is the irreducible minimum in
  `go/cmd/bridge/main.go` that makes `//export` emit symbols for c-shared
  builds — no C preamble, no C types, no C calls. Matrix E2EE is pure Go via
  `-tags goolm`. Core code always builds with `CGO_ENABLED=0`; CGO is used
  only when *linking* the c-shared library (Go toolchain requirement, not a
  dependency).
- **One file per platform core** (`go/cores/telegram.go`, `go/cores/bale.go`,
  …) implementing the `Core` interface from `go/cores/base.go`.
- **No core imports another core. No core imports the engine.** Delete any
  single core file and everything else must still compile.

## Layout

```
go/
  cores/    one file per platform + base.go (Core interface) + proxy.go
            optional platform sub-files use build tags (bale_calls_livekit.go
            is !js; bale_calls_js.go is the js stub)
  engine/   orchestration: SQLite cache, auth FSM, events, pending queue,
            media pipeline, vault-backed accounts
  bridge/   protobuf dispatch (Call → method), event push, ghost intercept
  cmd/bridge/  c-shared entry (main.go) + wasm entry (main_js.go, target
            currently unbuildable — see below)
  proto/    generated protobuf Go types
  utils/    standalone: vault (AES-256-GCM), config, storage, crypto,
            retry, vp8 encoder
proto/      .proto sources + scripts/gen_bridge codegen tool
research/   protocol specs & findings (living docs — keep updated)
```

## Commands

```bash
nix develop                 # dev shell (go, gcc, protoc, protoc-gen-go)

# Build Go shared library
scripts/build_go.sh linux     # → go/build/libcores.so
scripts/build_go.sh windows   # → go/build/cores.dll     (needs mingw)
scripts/build_go.sh darwin    # → go/build/libcores.dylib
scripts/build_go.sh android   # → go/build/android/*/    (needs ANDROID_NDK_HOME)
scripts/build_go.sh web       # NOT buildable yet — exits with an error

# Build / test (goolm tag is REQUIRED — mautrix libolm is pure-Go only with it)
cd go && CGO_ENABLED=0 go build -tags goolm ./...
cd go && CGO_ENABLED=0 go test -tags goolm ./...
cd go && CGO_ENABLED=0 go vet -tags goolm ./...

# Regenerate protobuf bridge (protoc + protoc-gen-go required)
scripts/gen_proto.sh
```

The `goolm` build tag is non-negotiable for anything touching
`maunium.net/go/mautrix` — without it the libolm C bindings try to compile.
The dev shell exports `GOFLAGS=-tags=goolm` so plain `go build ./...` works.

**js/wasm target status:** NOT buildable. pion/webrtc (used by the call
transports in telegram, matrix, rubika, deltachat, bale) and
coder/websocket have no `GOOS=js` support. `cmd/bridge/main_js.go` and the
bale js-stub pattern (`bale_calls_js.go`) are kept as the roadmap for
reviving it; reviving requires js stubs for every call transport. Do not
claim web support anywhere until `GOOS=js GOARCH=wasm go build ./...`
passes.

## Hard Rules

- **Zero placeholders.** Never stub a method that "returns an error" and call
  it done. Every exported method is a real implementation or explicitly
  `ErrNotSupported` where the platform genuinely lacks the feature.
- **No duplicate methods.** Before implementing anything from a checklist,
  grep the core file for the same functionality under a different name.
- **Research first.** Weird protocol findings go into `research/`
  immediately. Checklists (per-platform TODOs) live in `checklist/`.
- **Live-tested or it didn't happen.** All API tests hit real servers with
  real credentials from `auth/` (gitignored). Prune passing tests, never
  re-run them. Test files live in `go/tests/` (gitignored) so they never get
  committed.
- **No PII in commits** — no real names, phones, user IDs, tokens.
- **Sessions in `auth/`** (gitignored): `auth/{platform}_session.json`.
  Rate limits: 1.5s delay between calls, skip on FLOOD_WAIT.
- **Keep docs in sync**: `research/` for protocol quirks, per-platform
  `checklist/` files for status. `CLAUDE.md` is rules only.
- **Git push after every work session.**
- Be human. Warmth in conversation, rigor in implementation.
