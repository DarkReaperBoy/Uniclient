# AGENTS.md — Uniclient

> **Zero-context agent?** Read this file, then the newest WORKLOG.md entry,
> then the open items in BUGS.md. Resume from the topmost open item without
> asking the owner anything technical. **The owner is not a programmer** —
> never ask them code questions. This file exists so that if the owner
> deletes your context, the next agent continues exactly where the last one
> stopped.
>
> RESET NOTE (2026-10-30): the owner deleted the previous AGENTS.md /
> WORKLOG.md / BUGS.md (11k+ accumulated lines, git history keeps them).
> This file is the compact rewrite. Keep it under ~250 lines — the old
> file's slice-by-slice narrative is what WORKLOG entries and the git log
> are for.

Uniclient is one pure-Go, cross-platform (PC / mobile / web), multi-backend
messenger. One native Gio GUI, many chat and voice backends — Telegram,
Matrix, IRC, GitHub, XMPP, Delta Chat, Bale, TeamSpeak, Mumble — each
added and switched as easily as an account. The GUI mirrors AyuGram's
layout and behavior 1:1 (re-implemented from scratch, never copied) with
Material Design visuals.

## 1. Owner requirements (NON-NEGOTIABLE)

1. **Pure Go, 100%.** No Node/Electron/Flutter/Python runtime deps in the
   product. The only non-Go artifacts: (a) the CI-time gh-pages shell
   (§5), never on `main`; (b) **puppeteer E2E tests under
   `scripts/web-test/`** — test-only infra per the owner's 2026-10-30
   "use puppeteer" mandate; never ships, never links, never imported.
2. **Platforms:** Linux + Android first-class, Windows second-class but
   fully supported. **macOS/iOS BANNED** — no targets, no CI jobs, no docs.
3. **Native GUI, not web.** One single binary per platform, flag-based
   modes, no second executable. Headless/CLI = a flag.
4. **The web target is WASM** from the same GUI code, deployed to
   `https://darkreaperboy.github.io/Uniclient/` via the orphan `gh-pages`
   branch. CI builds it; `main` never contains JS/HTML.
5. **CI/CD on release tags (`v*`) + manual dispatch only.** Never per-push.
6. **Release binaries small:** `-trimpath -ldflags "-s -w"`, then UPX
   (`--best --lzma`, skip on .wasm/.apk; UPX failure never fails release).
7. **Gio is the only windowing dep.** cgo only inside Gio's Linux GPU shims
   and the NixOS flake build; everything else is `CGO_ENABLED=0`.
8. **Accounts are the model:** every backend is just an account.
9. **Two GUI modes: Chat and Voice.**
10. **No placeholders — everything functional.** No demo data, no stub
    buttons, no "coming soon". What cannot work against a real backend is
    HIDDEN, never faked (includes the web picker: only backends that can
    actually connect from a browser may be offered on GOOS=js — see §3).
11. **AyuGram 1:1, UI and functionality, every aspect.** The GUI is never
    trimmed to fit cores; cores grow to fit the GUI. Telegram is the exact
    bar. Material Design is the skin. Re-implement, never copy.
12. **Cores are disposable:** a stale/bad core is replaced completely, not
    patched. If a solid pure-Go library beats a custom core, use the library.
13. **Research → think → rate → plan → tests → code → verify-against-real.**
    Dockerized server before official server; "it compiles" is not done.
14. **Push after every unit of progress.** Only what is on GitHub survives
    VM resets. The GitHub token (provided out-of-band) NEVER lands in any
    file, log, or doc.
15. **TeamSpeak & Mumble: 1:1 wire compatibility** with official
    protocol/clients, pinned against upstream vectors, live-tested on
    public servers before the owner's own live test.

## 2. Architecture

```
go/
  cmd/uniclient/   ONE binary: Gio window + engine host, flag-based modes
  gui/             AyuGram-1:1 Gio app (91k loc). Pure UI → engine calls only
  bootstrap/       engine.Init + core factory + session migration
  engine/          accounts, vault-backed state, events, media, voice pipe
  cores/           one file set per backend implementing cores.Core
  voice/           pure-Go opus + per-sender mixer (pion/opus)
  audio/           PulseAudio (Linux), winmm (Win), WebAudio (js), OpenSL (Android)
  utils/           vault (Argon2id+AES-GCM), config, crypto
  wrtc/            WebRTC shim: pion native, browser API on js/wasm
  tests/           live protocol tests (-tags goolm,live; never in CI)
scripts/web-test/  puppeteer E2E suite (§4)
```

Event flow: `cores → engine (caches+normalizes) → EngineEvent JSON →
SetEventCallback/Subscribe → gui → invalidation`. Core interface:
`go/cores/base.go`; unsupported actions return `ErrNotSupported` and the
GUI hides them.

Platform truth table (go 1.27, gio v0.10.2):
| Target | Build | Notes |
|---|---|---|
| Linux amd64/arm64 | `CGO_ENABLED=1` + X11/wayland/EGL dev libs | cgo REQUIRED (Gio GPU) |
| Windows amd64 | `CGO_ENABLED=0` | pure Go, cross-builds from Linux |
| Android arm64 | gogio + NDK | APK output |
| Web | `GOOS=js GOARCH=wasm CGO_ENABLED=0` | same GUI code |
| macOS/iOS | **BANNED** | |

Web capability truth (verified 2026-10-31 — browsers have no raw sockets):
GitHub + Matrix connect over HTTPS; Bale connects via gRPC-Web WebSocket
(calls return ErrNotSupported on web). Telegram/IRC/XMPP/DeltaChat/
TeamSpeak/Mumble dial raw TCP → **cannot ever connect from a browser**;
they must not be offered in the web picker (§1.10).
Web persistence: vault → localStorage ("uniclient.vault", AES-GCM,
default password — env/flags are unreachable in a wasm argv); cache DB →
null driver (session-only); no single-instance lock — tabs coordinate via
flush-time vault merge (F-87).

## 3. GUI spec

AyuGramDesktop is the spec: same three-pane layout, same screens,
behaviors, interactions — every aspect. Missing one is a bug, never a
"difference". Scrolling + Material ripple everywhere; progress/connection
indicators; honest empty states; local passcode gate; Chat/Voice tabs;
backend-specific UI limited to auth steps + capability-gated actions.
A horrible GUI is a release blocker.

## 4. Testing ladder (every level must stay green)

1. **Unit, tests-first** — the failing test exists before the fix. gofmt +
   `go vet -tags goolm ./...` (+ `-tags goolm,live ./tests/`) clean always.
2. **Native suite:** `cd go && CGO_ENABLED=1 go test -p 1 -tags goolm
   -count=1 ./...` with `GOMEMLIMIT=900MiB GOGC=30` (gotd's tg needs it;
   small machines: `scripts/dev-test.sh`).
3. **js/wasm leg:** `scripts/dev-test.sh js` — gui package compiled
   GOOS=js under the node wasm_exec runner. Filesystem-dependent tests
   skip on js (no filesystem there by design).
4. **Puppeteer web E2E** (`scripts/web-test/`, run after `make wasm`):
   shell tier (12 tests: progress/revalidation/deploy/404-retry/offline/
   exit-relaunch/no-localStorage/mobile/back-button/same-origin) + app
   tier (6 tests: boot→welcome→picker→auth form, vault persistence,
   two-tab merge). `node run.mjs --live` targets the deployed site.
   Click targets are calibrated in canvas space (README). Keep the suite
   green on every web-touching change.
5. **Live protocol tests** (`-tags goolm,live`, env-gated, never in CI):
   dockerized server first, official server last.
6. **CI = the release gate:** release.yml (tag/dispatch): gofmt/vet/vet-
   live/test/race legs, nix gate, linux×2/windows/android, web job
   (builds wasm + shell, deploys gh-pages, `needs: [test]`), prerelease
   publish. verify.yml = the same gate, dispatch-only, + Xvfb GUI smoke
   screenshots. flake.yml = vendorHash helper.

## 5. Release & web deploy

Tag `v*` or dispatch. All releases `prerelease: true` until the owner
flips it. Version must be ≥ the newest existing tag (the v0.9.1/v0.10.x
sequence mistake must not repeat), and flake.nix `version` must equal the
tag. The web job writes `index.html` (the self-updating shell: same-origin
no-cache revalidation, ETag "updated/up to date" readout, determinate MB
progress, offline force-cache fallback, Retry, overlay hides on canvas
attach — the shell exists ONLY as release.yml's heredoc; the E2E suite
extracts it from there, keep them in sync), `wasm_exec.js` and
`uniclient.wasm` into the orphan gh-pages branch, force-pushed. Zero
GitHub-API calls from the shell.

## 6. NixOS (owner's daily driver)

`nix run github:DarkReaperBoy/Uniclient --no-write-lock-file`. No
flake.lock is ever committed (owner rule: inputs stay dynamic); both
workflows' nix gate runs that exact lockless shape first. Release binaries
(glibc runners) do not start on NixOS — the flake is the supported path.

## 7. Current state (2026-10-31)

- Feature parity CLOSED at 195/200 (the 5 non-PRESENT rows are recorded
  owner decisions/core-only, none buildable without the owner).
- v0.10.3 shipped, all 8 CI jobs green. Standing phase: stability/bug hunt.
- Web hardening pass (session 324, research/web_hardening_2026-10.md):
  Phase 0-1 done (full web recon + puppeteer suite 18 tests green);
  F-87 vault two-tab clobber fixed (merge-before-flush).
- Owner-only rungs: real-account live sign-ins (xmpp/bale/deltachat),
  first non-prerelease ≥ v0.10.3.

## 8. Invariants (check before every push)

- Suite green at every level of §4 that your change touches.
- No TODO/FIXME/placeholder markers; no dead UI.
- No secrets/tokens in files or logs; error messages leak no internals.
- BUGS.md rows sequential (no gaps/dupes); WORKLOG gets one entry per
  session; this file stays compact (< ~250 lines).
- Language stats stay Go (+ md/yml/sh infra + the test-only mjs).
