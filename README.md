# Uniclient

One pure-Go, cross-platform messenger. One native GUI, many chat and voice
backends — Telegram, Matrix, IRC, GitHub, XMPP, Delta Chat, Bale, Rubika —
each added and switched as easily as an account. The GUI mirrors AyuGram's
layout and behavior (re-implemented from scratch, never copied) with
Material Design visuals, built with [Gio](https://gioui.org).

**Status: pre-release.** Everything you see in the app works against real
backends with real accounts — no demo data, no placeholder screens. What a
backend cannot do yet is hidden, not faked. See `AGENTS.md` for the project
constitution and the parity roadmap.

## Run it

Binaries land on the [Releases](https://github.com/DarkReaperBoy/Uniclient/releases)
page for every release tag (all marked pre-release for now):

- **Linux** (amd64/arm64) — `uniclient-linux-<arch>`. On NixOS use the flake
  instead: `nix run github:DarkReaperBoy/Uniclient` (release binaries are
  built against glibc CI runners and won't start under Nix's loader — the
  flake is the supported path there).
- **Windows** — `uniclient-windows-amd64.exe` (pure Go, no runtime deps).
- **Android** — `uniclient.apk` (arm64).
- **Web** — a WASM build of the same GUI, deployed to
  `https://darkreaperboy.github.io/Uniclient/`.

One single binary per platform — the GUI, the engine host, and every core
compile into it. Headless/CLI behavior (when present) is a flag on the same
binary, never a second executable.

## Build from source

Requirements: Go 1.27+, and on Linux the Gio cgo headers
(`libegl1-mesa-dev libgles-dev libx11-dev libx11-xcb-dev libxkbcommon-dev
libxkbcommon-x11-dev libxcursor-dev libxfixes-dev libwayland-dev
libwayland-egl-backend-dev libvulkan-dev`).

```sh
cd go

# Linux (cgo for the GPU/window backends)
CGO_ENABLED=1 go build -tags goolm -o uniclient ./cmd/uniclient

# Windows (pure Go, cross-builds from Linux)
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -tags goolm \
    -o uniclient.exe ./cmd/uniclient

# Web (WASM, same GUI code)
GOOS=js GOARCH=wasm CGO_ENABLED=0 go build -tags goolm \
    -o uniclient.wasm ./cmd/uniclient
```

The **`-tags goolm`** flag is mandatory everywhere: it selects mautrix's
pure-Go Olm implementation so Matrix E2EE works without cgo. The only cgo
in the tree is inside Gio's own Linux GPU shims — everything else compiles
`CGO_ENABLED=0`.

**Low-RAM machines**: gotd's generated `tg` package needs ~2 GB+ to compile.
The verified recipe (`-p 1 GOMEMLIMIT=900MiB GOGC=30`) is used by CI and
works on small runners.

```sh
go test -p 1 -tags goolm -count=1 ./...   # with GOMEMLIMIT=900MiB GOGC=30
```

## Architecture

```
go/
  cmd/uniclient/   ONE binary. Flag-based modes. Gio window + engine host.
  gui/             The Gio app (AyuGram layout, Material visuals). Pure UI,
                   talks to the engine only.
  bootstrap/       Engine wiring: engine.Init + core factory + session store.
  engine/          Accounts, vault, SQLite cache, auth state machine, events,
                   media, pending queue + the shared voice pipeline
                   (mic → Opus → core, core → decode → mix → speaker).
  cores/           One file set per backend, implementing cores.Core.
  voice/           Pure-Go Opus codec + per-sender mixer (pion/opus).
  audio/           Pure-Go audio devices: PulseAudio protocol (Linux),
                   winmm syscalls (Windows), WebAudio (js/wasm).
  utils/           Config, vault, crypto, storage helpers.
  wrtc/            WebRTC shim: pion natively, browser API on js/wasm.
  tests/           Live protocol tests (env-gated, run on demand, not CI).
```

Every backend renders through the same GUI. A core that lacks a feature
returns `ErrNotSupported` and the GUI hides the action — cores are grown to
fit the GUI, never the other way around.

## Backends

| Core | State |
|---|---|
| Telegram | Most complete; 1:1 AyuGram feature parity in progress (gotd/td) |
| Matrix | Builds; E2EE via pure-Go goolm (mautrix) |
| IRC | Live-tested against real servers (own RFC2812+IRCv3 implementation) |
| GitHub | Live-tested against the real API |
| XMPP / Delta Chat / Bale / Rubika | Implemented, live verification pending |
| TeamSpeak / Mumble | Live-verified on public servers incl. the voice data plane: two-client opus voice round-trips (pure-Go codec + pure-Go audio devices) |

Live protocol tests live in `go/tests/`, gated behind env vars
(e.g. `UNICLIENT_LIVE_IRC=1`); they never run in CI and never need secrets
in the repo.

## For agents and contributors

`AGENTS.md` is the constitution (owner requirements, architecture, testing
ladder, release policy). `WORKLOG.md` is the session journal — the resume
point for agents. `research/` is agent scratch space: read old notes there
with suspicion.

No telemetry. Sessions and credentials live in an encrypted vault
(Argon2id + AES-GCM), never in plaintext files. Network traffic is the
messengers' own protocols, full stop.
