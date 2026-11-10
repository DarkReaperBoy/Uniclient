# Uniclient

One pure-Go, cross-platform messenger. One frontend, many chat and voice
backends — Telegram, Matrix, IRC, GitHub, XMPP, Delta Chat, Bale,
TeamSpeak, Mumble — each added and switched as easily as an account.

**Status: pre-release, GUI rebuild in progress.** The previous GUI was
removed (2026-11-01) and is being rebuilt from scratch with
[Gio](https://gioui.org), taking **AyuGram Desktop's layout (mapped 1:1)
under a Material Design skin** as the design reference. Until it lands, the
shipped desktop binary is the **headless engine host** (`uniclient` boots the
engine, serves accounts, and — with `-events` — prints the engine event stream
to stdout; the mid-rebuild GUI is available as `uniclient -gui`). Everything under the hood works against real backends with real
accounts — no demo data, no placeholder screens. What a backend cannot do
yet is hidden, not faked. See `AGENTS.md` for the project constitution.

## Run it

Binaries land on the [Releases](https://github.com/DarkReaperBoy/Uniclient/releases)
page for every release tag (all marked pre-release for now):

- **Linux** (amd64/arm64) — `uniclient-linux-<arch>`. On NixOS use the flake
  instead: `nix run github:DarkReaperBoy/Uniclient --no-write-lock-file`
  (the repo ships no `flake.lock` on purpose — inputs stay dynamic — and a
  remote flake checkout is read-only, so the flag lets nix resolve the
  inputs in memory instead of failing on a lock write; release binaries are
  built against glibc CI runners and won't start under Nix's loader — the
  flake is the supported path there).
- **Windows** — `uniclient-windows-amd64.exe` (pure Go, no runtime deps).

Headless engine host usage:

```sh
uniclient -dir ~/.uniclient -password <vault-password> [-events]
```

`Ctrl-C` / `SIGTERM` shuts the engine down cleanly. The Android APK, the
Linux/Windows binaries, and the web (WASM) build are produced by CI: every
code push to `main` uploads them as workflow artifacts (the "Build"
workflow — the freshest binaries between releases), and the web build is
live at
<https://darkreaperboy.github.io/Uniclient/> — those no-argv platforms
default to the mid-rebuild GUI: the page boots the engine and paints the
app frame — dialogs pane with its search field over a distinct list surface
(AyuGram-measured geometry, Material skin); with no account connected the
panes show the engine-driven "Add an account" empty state; the desktop
binaries default headless.

## Build from source

Requirements: Go 1.27+. Pure Go — no cgo, no system dev headers.

```sh
cd go
go build -tags goolm -o uniclient ./cmd/uniclient

# Windows (cross-builds from Linux)
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -tags goolm \
    -o uniclient.exe ./cmd/uniclient
```

The **`-tags goolm`** flag is mandatory everywhere: it selects mautrix's
pure-Go Olm implementation so Matrix E2EE works without cgo.

**Low-RAM machines**: gotd's generated `tg` package needs ~2 GB+ to compile.
The verified recipe (`-p 1 GOMEMLIMIT=900MiB GOGC=30`) is used by CI and
works on small runners.

```sh
go test -p 1 -tags goolm -count=1 ./...   # with GOMEMLIMIT=900MiB GOGC=30
```

## Architecture

```
go/
  cmd/uniclient/   ONE binary. Flag-based modes; headless engine host
                   (the rebuilt Gio window returns here too).
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
  tests/           All tests: per-package mirrors (tests/cores, tests/engine, …,
                   black-box) + live protocol tests at the root (env-gated,
                   run on demand, never in CI).
```

Every backend renders through the same frontend. A core that lacks a feature
returns `ErrNotSupported` and the UI hides the action — cores are grown to
fit the frontend, never the other way around.

## Backends

| Core | State |
|---|---|
| Telegram | Most complete (gotd/td) |
| Matrix | Builds; E2EE via pure-Go goolm (mautrix); group calls live-verified (MSC3401 full-mesh, self-hosted dendrite) |
| IRC | Live-tested against real servers (own RFC2812+IRCv3 implementation) |
| GitHub | Live-tested against the real API |
| XMPP / Delta Chat / Bale | Implemented, live verification pending |
| TeamSpeak / Mumble | Live-verified on public servers incl. the voice data plane: two-client opus voice round-trips (pure-Go codec + pure-Go audio devices) |

Live protocol tests live in `go/tests/`, gated behind the `live` build
tag (`-tags goolm,live`) with per-test env overrides (e.g.
`IRC_LIVE_SERVER`); they never run in CI and never need secrets in the
repo.

## For agents and contributors

`AGENTS.md` is the constitution (owner requirements, architecture, testing
ladder, release policy). `WORKLOG.md` is the session journal — the resume
point for agents.

No telemetry. Sessions and credentials live in an encrypted vault
(Argon2id + AES-GCM), never in plaintext files. Network traffic is the
messengers' own protocols, full stop.
