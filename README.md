# Uniclient

One pure-Go, cross-platform messenger engine that speaks many chat protocols
through one standardized FFI bridge. Native hosts (Flutter, Qt, anything with
a C FFI) load the c-shared library; the browser loads the js/wasm module.
One Go core, every frontend.

## The desktop app (no toolchain needed)

**Just want to chat?** Download a binary from the
[Releases](https://github.com/DarkReaperBoy/Uniclient/releases) page, unpack,
and run:

* **Windows** — double-click `Start Uniclient.bat`
* **Linux / macOS** — `./uniclient.sh` (or `./uniclient-web`)

Your browser opens the app at `http://127.0.0.1:8199`. Add an account with
the **+** button (Telegram, GitHub, IRC, Matrix, XMPP, Delta Chat, Bale,
Rubika, TeamSpeak, Mumble), pick a chat, and message. Everything stays on
your machine: the server binds 127.0.0.1 only, and credentials live in an
encrypted vault.

From source:

```sh
cd go && CGO_ENABLED=0 go build -tags goolm -o uniclient-web ./cmd/web
./uniclient-web          # or: -port 9000, -dir /path/to/config, -no-browser
```

A second launch detects the running instance and just opens the browser.

## What's in the box

| Piece | Path | What it is |
|---|---|---|
| Desktop app | `go/cmd/web/` | The chat app: engine + local HTTP/WS API + embedded web UI |
| Engine | `go/engine/` | Accounts, vault, SQLite cache, media, auth, events — the layer every backend plugs into |
| Bridge | `go/bridge/` | Protobuf request/response dispatch (`__engine` + per-core routing, 500+ methods) |
| Cores | `go/cores/` | Protocol backends: Telegram (gotd/MTProto), Matrix (mautrix, full E2EE via goolm), IRC, XMPP, GitHub, Mumble, TeamSpeak, Bale, Rubika, DeltaChat |
| FFI entries | `go/cmd/bridge/` | c-shared native build + js/wasm build |
| CLI host | `go/cmd/cli/` | Headless host for driving the engine from a terminal |
| Compat shim | `go/wrtc/` | pion/webrtc native/js API unification (calls compile everywhere, media degrades on web) |
| Proto | `proto/` + `go/proto/` | The bridge wire contract (generated code committed) |

## Build

Requirements: Go 1.27+, a C compiler for the c-shared target, Node 18+ for the
wasm smoke test.

```sh
make build        # compile everything, CGO_ENABLED=0
make test         # test suite
make c-shared     # dist/libuniclient.so + libuniclient.h
make wasm         # dist/uniclient.wasm
make cli          # dist/uniclient-cli (headless host)
make smoke        # build + run both FFI smoke suites (C and Node)
```

Or per-platform: `./scripts/build.sh [linux|windows|darwin|android|web|cli]`.
The web host smoke suite lives in `scripts/smoke/smoke_web.sh`.

**The goolm tag is mandatory everywhere**: mautrix's default Olm
implementation is cgo; `-tags goolm` selects the pure-Go implementation so the
engine stays C-free. The only cgo in the repo is the export shim required by
`-buildmode=c-shared`.

**Low-RAM builds**: gotd's generated `tg` package needs ~2 GB+ to compile. The
Makefile and build script already export the verified recipe
(`-p 1 GOMEMLIMIT=900MiB GOGC=30`); it is harmless on big machines.

## The FFI contract

### Native (c-shared)

```c
void* BridgeCallWithLen(void* data, int32_t len, int32_t* outLen);  // request -> response
void  BridgeFree(void* ptr);                                        // release a returned buffer
void* BridgeNextEvent(int32_t* outLen);                             // pull next async event (blocks)
void  BridgeStopEvents(void);                                       // unblock the event reader
```

Requests and events are protobufs: `BridgeRequest{core_id, method, payload}`
→ `BridgeResponse{ok, error, error_code, payload}`. See `proto/models.proto`
and `proto/engine.proto`. Error codes are categorized sentinels
(`auth`, `rate_limited`, `network`, `timeout`, `not_found`, `permission`,
`not_supported`, `unknown`) so hosts can react without string matching.

A complete C-side example lives in `scripts/smoke/smoke_c.c`.

### Web (js/wasm)

```js
globalThis.bridgeCall(reqBytes)          // -> Promise<Uint8Array>
globalThis.bridgeSetEventCallback(cb)    // cb(eventBytes) | null to clear
```

`bridgeCall` is async **by design**: js/wasm is single-threaded and the engine
does blocking filesystem work (vault, config), which can only complete when
the JS call stack unwinds. Run it with Node's wasm bootstrap
(`lib/wasm/wasm_exec_node.js`-style globals) for filesystem support —
see `scripts/smoke/run_wasm.mjs`.

## Smoke tests (prove the artifacts actually work)

```sh
make smoke-c     # builds the .so, then a C program drives the full lifecycle:
                 # Init -> ListAccounts -> AddAccount -> ListAccounts -> Shutdown
make smoke-wasm  # builds the .wasm, then Node drives the same lifecycle
```

Both are wired into CI (`.github/workflows/ci.yml`) alongside the native
gate, race detector, platform matrix (windows/darwin/linux × amd64/arm64),
the wasm build, and the web-host smoke suite.

## CLI quick start

```sh
dist/uniclient-cli init          # create engine state at ~/.uniclient
dist/uniclient-cli add telegram  # add an account
dist/uniclient-cli accounts
dist/uniclient-cli raw __engine ListAccounts </dev/null | xxd
```

State: `~/.uniclient/` (override with `UNICLIENT_HOME`, vault password with
`UNICLIENT_PASSWORD`).

## Notes for core contributors

- **Pure-Go policy**: application code compiles `CGO_ENABLED=0` across the
  platform matrix (CI enforces it). cgo exists only in the c-shared export
  shim and never in engine/cores code.
- **Calls on wasm**: signaling works, media doesn't. `go/wrtc` aliases the
  full pion/webrtc API on native platforms and stubs the native-only media
  surface on js/wasm — the pattern the bale core established. Don't import
  `pion/webrtc` media types directly from cores; import `uniclient/wrtc`.
- **Sessions/credentials** live in the encrypted vault (Argon2id + AES-GCM),
  never in plaintext files.
- **No telemetry.** Network traffic is the messengers' protocols, full stop.

See `AGENTS.md` for the full project constitution and roadmap context.

## Co-Authorship

This project was developed with the assistance of GLM 5.3 AI.

Co-Authored-By: GLM 5.3 <noreply@z.ai>

## Co-Authorship

This project was developed with the assistance of GLM 5.3 AI.

Co-Authored-By: GLM 5.3 <noreply@z.ai>
