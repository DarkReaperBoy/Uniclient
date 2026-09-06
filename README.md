# Uniclient — Go Core

Pure Go backend for a unified multi-platform messaging client. Ten platforms
implement the same `Core` interface, plus a shared engine layer (SQLite cache,
auth FSM, events, pending queue, media pipeline) and a protobuf FFI bridge so
**any** frontend can drive the whole thing.

**The UI is a separate project** — this repo is backend only. The Go core
compiles to a c-shared library (`libcores.so` / `cores.dll` / `libcores.dylib`)
that any frontend can load over FFI. The previous Flutter frontend has been
removed; a new frontend will be built separately.

## Architecture

```
┌──────────────────────────────────────────────┐
│                 Go core library              │
│                                              │
│  cores/          one file per platform:      │
│    telegram.go   MTProto (gotd/td)           │
│    bale.go       bot API + gRPC-Web user API │
│    rubika.go     WebSocket proprietary       │
│    deltachat.go  IMAP/SMTP, Autocrypt E2EE   │
│    teamspeak.go  TS3 UDP client protocol     │
│    matrix.go     CS API + E2EE (mautrix)     │
│    cores/mumble  TCP+UDP, OCB2 crypto        │
│    github.go     REST API as messaging layer │
│    irc.go        RFC 1459/2812 + IRCv3       │
│    xmpp.go       RFC 6120/6121 + 30+ XEPs    │
│                                              │
│  engine/         orchestration: SQLite cache │
│                  (rebuildable from vault),   │
│                  auth FSM, events, pending   │
│                  queue, media pipeline       │
│                                              │
│  bridge/         protobuf dispatch, event    │
│                  push, ghost intercept       │
│                                              │
│  utils/          vault (AES-256-GCM), config,│
│                  storage, retry, vp8 encoder │
└──────────────────────────────────────────────┘
                    │
          protobuf over FFI / WASM
                    │
             ┌──────┴──────┐
             │  Frontend   │   ← separate project, your choice of stack
             └─────────────┘
```

- **No core imports another core. No core imports the engine.** Delete
  `telegram.go` and the rest still compile; delete all cores and the engine
  still stands.
- **Engine** (`go/engine/`) orchestrates cores: SQLite cache, auth FSM for all
  10 platforms, offline-first pending queue, media download pipeline,
  reconnect with backoff, vault-backed accounts.
- **Bridge** (`go/bridge/`) dispatches every method over a single entry point
  (`BridgeCall`) with serialized `BridgeRequest`/`BridgeResponse` protos.
  Async events are delivered via a pull-model export (`BridgeNextEvent`).
- **Vault** (`go/utils/vault.go`) — AES-256-GCM encrypted single file holding
  accounts, credentials, sessions, and config. Single source of truth;
  the SQLite cache is rebuildable from it.

## Why?

Instead of juggling ten separate clients, one Go core gives you a shared
interface: same message models, same error types, same capabilities system.
Adding a platform is one Go file and one registration line in the bridge.

## Platforms

| Core | Transport | Notes |
|---|---|---|
| Telegram | MTProto via [gotd/td](https://github.com/gotd/td) | bot + user mode, 1:1 calls (9/9 protocol versions, pure Go pion) |
| Bale | HTTP bot API + gRPC-Web user API | LiveKit calls, CDN/DNS fallback for blocked networks |
| Rubika | WebSocket proprietary protocol | AES-256-CBC + RSA auth exchange |
| Delta Chat | IMAP/SMTP | Autocrypt E2EE, WebRTC calls, tested on 8 public chatmail instances |
| TeamSpeak 3 | UDP client protocol (not ServerQuery) | EAX crypto, QuickLZ, RSA puzzle, real voice transport |
| Matrix | CS API via [mautrix-go](https://github.com/mautrix/go) | full E2EE (pure-Go goolm), WebRTC calls |
| Mumble | TLS TCP + OCB2-encrypted UDP | protobuf 1.5+ and legacy formats, TCP tunnel fallback |
| GitHub | REST API | DMs/groups via profile-repo issues, 5-layer rate limiting |
| IRC | TCP/TLS | RFC 1459/2812 + IRCv3, SASL, CTCP/DCC, services (NickServ etc.) |
| XMPP | TCP/STARTTLS | RFC 6120/6121 + 30+ XEPs, MUC, MAM, Jingle |

## Building

Pinned toolchain: **Go 1.26**. Build with the `goolm` tag (pure-Go Matrix E2EE;
without it the mautrix libolm C bindings would be pulled in, violating the
zero-C-deps invariant).

```bash
# Dev shell (go, gcc, protoc, protoc-gen-go) — GOFLAGS=-tags=goolm is preset
nix develop

# Build the shared library for your platform
scripts/build_go.sh linux      # → go/build/libcores.so

# Other targets
scripts/build_go.sh windows    # → go/build/cores.dll (needs mingw-w64)
scripts/build_go.sh darwin     # → go/build/libcores.dylib
scripts/build_go.sh android    # → go/build/android/*/ (needs ANDROID_NDK_HOME)
```

> The `web` (wasm) target is **not buildable yet**: pion/webrtc (call
> transports) and coder/websocket have no `GOOS=js` support. The wasm entry
> point (`go/cmd/bridge/main_js.go`) is kept for a future revival.

### Embedding / consuming the core

- **Native frontend:** dlopen `libcores.so`, call
  `BridgeCallWithLen(data, len, &outLen)` with a serialized `BridgeRequest`,
  free the returned pinned buffer with `BridgeFree`. Events: drain
  `BridgeNextEvent` on a dedicated thread until `BridgeStopEvents`.
- **WASM frontend (future):** the entry point (`go/cmd/bridge/main_js.go`)
  exposes `bridgeCall` / `bridgeSetEventCallback` as JS functions, but the
  wasm build is currently blocked on js support in the WebRTC deps — see
  the note under Building.

The request/response schema is defined in `proto/engine.proto` and
`proto/models.proto`; per-platform method protos in `proto/cores/*.proto`.
Regenerate Go types + dispatch with `scripts/gen_proto.sh`.

## Tests

Live API tests (real servers, real credentials) live in `go/tests/` —
gitignored by design, they never get committed. Run the unit tests with:

```bash
cd go && go test -tags goolm ./...
```

## Research & Protocol Documentation

| File | Contents |
|---|---|
| `research/telegram_notes.md` | gotd/td API quirks, bot limitations, FLOOD_WAIT |
| `research/tgcalls_protocol.md` | Telegram calls: reverse-engineered spec, 9 protocol versions |
| `research/bale_protocol.md` | Bale: bot API, user gRPC-Web, LiveKit call protocol, DNS fallback |
| `research/rubika_protocol.md` | Rubika: WebSocket protocol, AES crypto, file upload, GUID format |
| `research/deltachat_protocol.md` | Delta Chat: IMAP/SMTP, Autocrypt E2EE, SecureJoin |
| `research/teamspeak_protocol.md` | TS3 UDP client protocol: handshake, QuickLZ, AES-128-EAX, identity |
| `research/matrix_protocol.md` | Matrix CS API: mautrix-go SDK mapping, E2EE, VoIP |
| `research/mumble_protocol.md` | Mumble: TCP/UDP protocol, OCB2 crypto, voice format |
| `research/xmpp_protocol.md` | XMPP: RFC 6120/6121 + 30+ XEPs, SASL, MUC, PubSub, Jingle |
| `research/engine_architecture.md` | Engine layer spec: cache, auth FSM, events, pending queue |
| `research/ice_protocol.md` | ZeroC Ice wire protocol for Murmur admin RPC |

## License

[MIT](LICENSE)
