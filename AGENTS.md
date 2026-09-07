# AGENTS.md — Uniclient

> **If you are an agent with no prior context:** read this file top-to-bottom,
> then read `WORKLOG.md` (last 2 entries), then check the checklist at the
> bottom. Then resume work without asking the owner anything technical.
> The owner is **not a programmer** — never ask them code questions.

Uniclient is one pure-Go, cross-platform messenger. One native GUI, many chat
backends (Telegram, Matrix, IRC, XMPP, GitHub, Delta Chat, Bale, Rubika,
TeamSpeak, Mumble...), each added and switched as easily as an account.
GUI inspired by **AyuGram** (Telegram feature parity, re-implemented — never
copied) with **Material Design** visuals, built with **Gio**.

Current phase: **pre-release**. All GitHub releases must be marked
`prerelease: true` until the owner says otherwise.

---

## 1. Owner requirements (NON-NEGOTIABLE)

These came straight from the owner. If any decision contradicts this list,
this list wins.

1. **Pure Go. 100%.** No Node, no Electron, no Flutter, no Rust, no Python, no
   webview-wrapper in OUR repo. The repo language stats must show Go (plus
   md/yml/sh infra files). The only acceptable non-Go artifact is generated at
   CI time into the `gh-pages` branch (see §4), never on `main`.
   cgo exception: Gio's Linux GPU access needs tiny cgo shims *inside the gio
   dependency* — that's the Go toolchain compiling Go-shipped code, still fine.
2. **Platforms:** Linux and Android are **first-class**. Windows is
   **second-class but fully supported**. **macOS and iOS are BANNED** — no
   build targets, no CI jobs, no docs mentioning them except this ban.
3. **Native GUI, not web.** The desktop app is a native Gio window. Opening a
   browser tab as "the desktop app" is forbidden. One **single binary** —
   no separate CLI host, no separate web host, no shared library.
   Headless/CLI mode may exist as a *flag* on the same binary, never as a
   second binary.
4. **The web target is WASM** built from the same GUI code, deployed to
   GitHub Pages at `https://darkreaperboy.github.io/Uniclient/` via the
   `gh-pages` branch. CI builds it; `main` never contains JS/HTML.
5. **CI/CD runs on release tags only** (`v*`), plus manual `workflow_dispatch`.
   Never on every push/PR.
6. **Release binaries are small:** `-trimpath -ldflags "-s -w"`, then **UPX**
   (`upx --best --lzma`, skip on .wasm/.apk). UPX breaks on some arm64 setups —
   guard it so failure never fails the release.
7. **Gio is the GUI toolkit** (`gioui.org`). It is the only windowing dep.
8. Account switching UX: every backend is just an account you add/remove.
9. Two GUI modes: **Chat** and **Voice** (voice-chat backends surface there).

## 2. Architecture

```
go/
  cmd/uniclient/   ONE binary. Flag-based modes. Gio window + engine host.
  gui/             The Gio app: theme, layout, chat list, chat view, login,
                   voice panel, notifications. Pure UI, talks to engine only.
  bootstrap/       Engine wiring: engine.Init + core factory + session store.
                   (This is the seam where hosts plug in.)
  engine/          Accounts, vault, SQLite cache, auth state machine, events,
                   media, pending queue. NO UI code, NO proto, NO bridge.
  cores/           One file set per backend. Implements cores.Core.
                   A core never imports another core. Never imports engine.
  utils/           Config, vault, crypto, storage helpers.
  wrtc/            WebRTC shim: pion natively, browser API on js/wasm.
  tests/           Live protocol tests (env-gated, run on demand, not CI).
```

**DELETED FOREVER (do not resurrect):** `go/bridge/` (protobuf FFI bridge),
`go/proto/` + root `proto/` (wire contract), `go/cmd/web` (browser desktop),
`go/cmd/bridge` (c-shared lib), `go/cmd/cli` (second binary),
`scripts/smoke/*.mjs|.c` (JS smoke tests). The GUI calls `engine` methods
directly — in-process Go calls, no IPC, no serialization layer. That is the
whole point of a native GUI.

Event flow: `cores` → `engine` (caches + normalizes) → JSON `EngineEvent`
bytes → `SetEventCallback` → `gui` notifier decodes → invalidates UI state.
(Events stay JSON-shaped so a future remote host could reuse them, but
nothing external depends on it today.)

Core interface lives in `go/cores/base.go` (~90 methods). New backends
embed `cores.StubCore` and override what they support; everything else
returns `ErrNotSupported` and the GUI hides unsupported actions via
`Capabilities()`.

## 3. Platform truth table (verified 2026-09, go1.27, gio v0.10.2)

| Target | Build | Notes |
|---|---|---|
| Linux amd64/arm64 | `CGO_ENABLED=1` + X11/wayland/EGL dev libs | CGO **required** on Linux — Gio's X11 backend and EGL/Vulkan contexts are cgo. Verified: CGO_ENABLED=0 fails. NixOS users install via flake (§5). |
| Windows amd64 | `CGO_ENABLED=0` | Pure Go (D3D11/OpenGL via syscalls). Verified. |
| Android arm64 (+amd64/x86) | gogio + Android NDK | APK output. NDK needed in CI. |
| Web | `GOOS=js GOARCH=wasm CGO_ENABLED=0` | Pure Go, same GUI code. Verified. |
| macOS/iOS | **BANNED** | Never build, never document. |

Old research claiming anything else about cgo was re-tested; only this table
is trusted. Re-verify with `scripts/gio_probe` if gio is upgraded.

## 4. Release & web deploy (CI policy)

`.github/workflows/release.yml` — triggers: `push: tags: ['v*']` +
`workflow_dispatch`. Never `on: push` to a branch.

Jobs:
1. **test** — `go vet`, `gofmt -l` gate, `go test ./...` (tags goolm) on linux.
2. **build-native** — linux/amd64 + linux/arm64 (CGO, -s -w, UPX),
   windows/amd64 (CGO_ENABLED=0, -s -w, UPX) → `uniclient-<os>-<arch>[.exe]`.
3. **build-android** — gogio → `uniclient.apk`.
4. **build-web** — wasm → checkout orphan `gh-pages`, write `index.html` +
   `wasm_exec.js` (from `$GOROOT/lib`) + `uniclient.wasm`, force-push.
   Assets use **relative** paths; base URL is `/Uniclient/`.
5. Attach everything to the GitHub release, **`prerelease: true`**.

One artifact name per platform, all called `uniclient-*`. No tarballs unless
the owner asks.

## 5. NixOS (owner's daily driver)

Root `flake.nix` provides `packages.default` (the app, built with Nix's cgo
against Nix libs) and a dev shell. Owner runs:
`nix run github:DarkReaperBoy/Uniclient`. Release binaries built on glibc CI
runners will not start on NixOS (dynamic linker path) — that is expected;
the flake is the supported path there. Never "fix" this by shipping Nix
store paths in binaries.

## 6. GUI spec (AyuGram-inspired, Material Design)

The GUI is the product. A horrible GUI is a release blocker, not a nit.

- **Chat folders** (AyuGram/Telegram parity): folder tabs above the chat list
  (All / Unread / Groups / Channels / custom per-account folders from
  `GetFolders`). This was missing and the owner was angry about it.
- **Scrolling everywhere**: chat list, message list, settings — every
  `layout.List` gets a scrollbar. Message view starts scrolled to bottom,
  auto-scrolls on new messages, scroll-up loads older history.
- **Responsive buttons**: every clickable is a `material.Clickable`/
  `material.Button` (ripple included). No dead-feeling custom click rects.
- **Progress indicators**: connecting/login/sending states show
  spinners/progress bars; account rows show connection dots
  (green=connected, amber=connecting, red=error); empty-vs-loading states
  are distinct. The owner must never wonder "is it doing anything?"
- **Layout**: left sidebar (account switcher, search, folder tabs, chat
  list) + right chat view (header with peer name/status, message list,
  composer). Adaptive: sidebar collapses on narrow/mobile widths.
- **Message bubbles**: outgoing/incoming styles, sender name in groups,
  timestamps, delivery ticks, unread separator, day dividers.
- **Login**: backend picker (grid of cards), per-backend auth form driven by
  the engine auth state machine (step prompt + input + back + progress +
  error). Never a raw JSON dump.
- **Voice mode**: second top-level tab — call list, join screen, mic/speaker
  controls. Placeholder-acceptable until voice cores land, but the tab and
  navigation must exist and look intentional.
- **Demo backend** (`cores/demo.go`): a fake platform with sample chats,
  folders, an echo bot and typing simulation, selectable from the welcome
  screen. Lets the owner (a non-programmer) evaluate the GUI with zero
  accounts. The GUI must be fully demoable before any core is trusted.

## 7. Cores status & policy

Cores are protocol implementations behind `cores.Core`. The old ones were
stale; per backend the policy is: **write tests first** (unit + env-gated
live test against a real or dockerized server), then implement, then wire
into `bootstrap` + GUI.

| Core | State (2026-09) |
|---|---|
| telegram (gotd/td) | Most complete. 1:1 AyuGram feature work continues here. |
| matrix (mautrix) | Builds; E2EE via goolm (pure Go, tag `goolm`). |
| irc (girc-style own impl) | Live-tested vs real server. |
| github | Live-tested vs real API. |
| xmpp, bale, rubika, deltachat | Implementations exist, unverified live. |
| mumble, teamspeak | **Broken/stale — owner explicitly called them out.** Do not ship them as "working". Either rewrite with tests or mark hidden+experimental. Current decision: hidden behind an env flag until rewritten. |

## 8. Testing rules

- `go test ./...` (with `-tags goolm`) must pass on every commit that ships.
- gofmt + vet clean, always.
- Live tests live in `go/tests/`, gated behind env vars (e.g.
  `UNICLIENT_LIVE_IRC=1`), never run in CI, never need secrets in the repo.
- Docker-based protocol tests (prosody, ergo, mumble-server...) are the
  preferred way to verify cores without the real internet.

## 9. Repo hygiene

- No build artifacts committed. `dist/` is gitignored.
- No generated code committed (protobuf codegen was deleted with the bridge;
  if codegen is ever reintroduced, generate in CI, don't commit).
- Markdown stays short and true. If a doc describes something the code no
  longer does, fix the doc or delete it. Docs that smell like hallucination
  get deleted, not "fixed" with more words.
- `WORKLOG.md`: append one entry per work session (what changed, why, what is
  next). This is the resume-from-zero mechanism for agents.

## 10. Session checklist

Legend: `[x]` done, `[~]` in progress, `[ ]` todo.

- [x] AGENTS.md rewritten from scratch (owner's 2026-09 requirements)
- [x] All md files refreshed (README, WORKLOG, research headers)
- [x] Bridge/proto/web-UI/CLI-host deleted; repo is pure Go
- [x] Single binary `cmd/uniclient` (Gio native GUI)
- [x] `gui/` package: theme, sidebar+folders, chat view, login flow, voice tab
- [x] Scrolling + scrollbars everywhere
- [x] Responsive material buttons + ripple
- [x] Progress/connection indicators
- [x] Demo backend for GUI evaluation
- [x] `bootstrap/` package (engine wiring without bridge)
- [x] flake.nix for NixOS (run + dev shell)
- [x] release.yml: tag-only triggers, linux+windows+android+wasm, UPX, prerelease
- [x] gh-pages WASM deploy to /Uniclient/
- [x] ci.yml removed (per owner: CI only on release)
- [x] gofmt/vet/tests green; linux/windows/wasm builds verified
- [ ] mumble + teamspeak rewrite (tests first, docker-based)
- [ ] Telegram 1:1 AyuGram features (folders sync, ghost mode, ...)
- [ ] Voice mode: real call UI on top of wrtc
- [ ] First non-prerelease when owner approves
