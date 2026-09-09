# AGENTS.md — Uniclient

> **Zero-context agent?** Read this file top-to-bottom, then the last two
> entries of `WORKLOG.md`, then the checklist in §11. Resume work from the
> topmost unchecked item without asking the owner anything technical.
> The owner is **not a programmer** — never ask them code questions.
> This file is written so that if the owner deletes your context, the next
> agent can continue exactly where the last one left off.

Uniclient is one pure-Go, cross-platform (PC / mobile / web), multi-backend,
user-friendly messenger. One native GUI, many chat and voice backends
(Telegram, Matrix, IRC, XMPP, GitHub, Delta Chat, Bale, Rubika, TeamSpeak,
Mumble...), each added and switched as easily as an account. The GUI uses
**AyuGram's layout and features, 1:1** (re-implemented from scratch — never
copied) with **Material Design** visuals, built with **Gio**. Standardized
backend surface so one GUI can handle them all; optimized code and builds.

Current phase: **pre-release**. All GitHub releases must be marked
`prerelease: true` until the owner says otherwise.

---

## 1. Owner requirements (NON-NEGOTIABLE)

These came straight from the owner. If any decision contradicts this list,
this list wins.

1. **Pure Go. 100%.** No Node, no Electron, no Flutter, no Rust, no Python, no
   webview-wrapper in OUR repo. No external (non-Go) runtime dependencies —
   the owner will not compromise on this. The repo language stats must show
   Go (plus md/yml/sh infra files). The only acceptable non-Go artifact is
   generated at CI time into the `gh-pages` branch (see §5), never on `main`.
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
7. **Gio is the GUI toolkit** (`gioui.org`, https://github.com/gioui/gio).
   It is the only windowing dep.
8. Account switching UX: every backend is just an account you add/remove.
9. Two GUI modes: **Chat** and **Voice** (voice-chat backends surface there).
10. **No placeholders. Everything functional.** No fake accounts, no fake
    users, no mock/demo platforms, no fabricated chats or messages, no stub
    buttons, no "coming soon" panes, no dead UI pretending to work. Anything
    visible in the GUI must actually work against a real backend with a real
    account. If it cannot work yet, **hide it — never fake it**. Honest
    empty states driven by real engine state are fine; simulated content is
    not. This bans the old `cores/demo.go` (fake platform + fake account,
    owner: "horrible demo"): delete it, the `-demo` flag, the welcome-screen
    demo entry, and every README mention.
11. **AyuGram 1:1 — UI *and* functionality, every aspect.** UniClient's
    GUI is a 1:1 clone of AyuGramDesktop
    (https://github.com/AyuGram/AyuGramDesktop): same layout, same screens,
    same interactions, same features — **every aspect of it** (owner:
    "i want every aspect of it cloned"). This is a **source-level parity
    mandate**: walk AyuGramDesktop feature-by-feature and mirror each one
    in `gui/`; when unsure, the answer is what AyuGram does. If a feature
    needs functionality the cores don't have yet, **add it to the cores** —
    the GUI is never trimmed to fit the cores; the cores grow to fit the
    GUI. **One frontend for every backend:** all backends render through
    this same GUI; a backend is just an account you add (owner: "all of
    the backends use the same frontend and be like just diff accounts").
    **Telegram is the mandatory exact 1:1** — telegram core + GUI must
    reproduce AyuGram (full Telegram) functionality *exactly*, at the very
    least; other cores follow the same UI as far as their protocols allow.
    **Material Design** is the visual skin on top (owner prefers Material,
    loves AyuGram's structure). Re-implement in Gio; never copy AyuGram
    code or assets.
12. **Cores are disposable.** Cores may be stale or badly designed — if a
    core's implementation is not solid, **replace it completely**, don't
    patch it. If directly using a good pure-Go library beats a custom core,
    use the library. "Already written" is not a reason to keep bad code.
13. **Deep research first.** Every non-trivial task starts with deep
    research — web search, RTFM, primary sources (upstream repos, docs,
    protocol specs). Never assume; never trust stale notes (§10 research
    policy). Findings go into `research/`. Go beyond the code, libs and
    samples already provided.
14. **Think deeply → rate → best plan → then code.** Before writing code:
    think deeply about the architecture and design; **rate** the existing
    implementation (the arch + each affected core — a justified score,
    recorded in the session's WORKLOG entry); a bad rating means complete
    replacement (§1.12), a good one means keep and extend; then think of
    the *best* plan, not the fastest. Only then write code — tests first
    (§9), then verify against something real (§9 ladder). The order is
    mandatory: research → think → rate → plan → tests → code → verify.

## 2. Workflow (mandatory order of operations)

The owner's process, in their own words: *"do deep research... think deeply
about it, rate it, and then write code... think of best plan."* Every
non-trivial task follows this order. Never jump straight to code.

1. **Deep research** — web search, RTFM, primary sources. Write findings
   into `research/` (scratch space, §10). Distrust old notes; verify
   everything yourself.
2. **Think deeply** — architecture, design, trade-offs. Arch design and
   research always come before implementation.
3. **Rate it** — score the existing design/implementation (the arch and
   each affected core) with a justified rating, recorded in the session's
   WORKLOG entry. Bad rating → replace completely (§1.12). Good rating →
   keep and extend.
4. **Best plan** — think of the *best* plan, not the fastest, and write it
   down (WORKLOG / research/) before implementing.
5. **Tests first** — the failing test exists before the implementation
   code (§9).
6. **Write code** — pure Go (§1), standardized on the `cores.Core`
   interface (§3), optimized.
7. **Verify for real** — run the §9 ladder: unit → dockerized server →
   official server. "It compiles" is not done. "Works against a real
   server" is done.

## 3. Architecture

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

**ALSO BANNED (see §1.10):** `cores/demo.go` + `-demo` flag + welcome-screen
demo path. Fake data is not a feature.

Event flow: `cores` → `engine` (caches + normalizes) → JSON `EngineEvent`
bytes → `SetEventCallback` → `gui` notifier decodes → invalidates UI state.
(Events stay JSON-shaped so a future remote host could reuse them, but
nothing external depends on it today.)

Core interface lives in `go/cores/base.go` (~90 methods). New backends
embed `cores.StubCore` and override what they support; everything else
returns `ErrNotSupported` and the GUI hides unsupported actions via
`Capabilities()`. This is the "standardized" surface that lets one GUI
handle every backend.

## 4. Platform truth table (verified 2026-09, go1.27, gio v0.10.2)

| Target | Build | Notes |
|---|---|---|
| Linux amd64/arm64 | `CGO_ENABLED=1` + X11/wayland/EGL dev libs | CGO **required** on Linux — Gio's X11 backend and EGL/Vulkan contexts are cgo. Verified: CGO_ENABLED=0 fails. NixOS users install via flake (§6). |
| Windows amd64 | `CGO_ENABLED=0` | Pure Go (D3D11/OpenGL via syscalls). Verified. |
| Android arm64 (+amd64/x86) | gogio + Android NDK | APK output. NDK needed in CI. |
| Web | `GOOS=js GOARCH=wasm CGO_ENABLED=0` | Pure Go, same GUI code. Verified. |
| macOS/iOS | **BANNED** | Never build, never document. |

Old research claiming anything else about cgo was re-tested; only this table
is trusted. Re-verify with `scripts/gio_probe` if gio is upgraded.

## 5. Release & web deploy (CI policy)

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

**`.github/workflows/verify.yml`** — dispatch-only manual verification runner
(constitution-compliant: `workflow_dispatch` trigger, never `on: push`).
Runs the full quality gate (gofmt/vet/tests), windows+wasm cross-builds, and
an **Xvfb GUI smoke** that boots the real binary and uploads screenshots as
artifacts for review. Use it to verify any commit without cutting a release
— this is also the ONLY way to build/test on machines too small to compile
gotd's `tg` package (needs ≥4GB free RAM; small sandboxes dispatch CI
instead).

## 6. NixOS (owner's daily driver)

Root `flake.nix` provides `packages.default` (the app, built with Nix's cgo
against Nix libs) and a dev shell. Owner runs:
`nix run github:DarkReaperBoy/Uniclient`. Release binaries built on glibc CI
runners will not start on NixOS (dynamic linker path) — that is expected;
the flake is the supported path there. Never "fix" this by shipping Nix
store paths in binaries.

## 7. GUI spec (AyuGram layout 1:1, Material Design)

The GUI is the product. Target: **AyuGramDesktop's layout and features,
1:1 — UI and functionality, every aspect** (owner mandate §1.11),
re-implemented in Gio with Material Design visuals. A horrible GUI is
a release blocker, not a nit.

- **Parity doctrine (owner's words):** "1:1 ui, and same functionality…
  every aspect of it cloned." Every screen, control, and behavior
  AyuGramDesktop has is part of the spec. A missing one is a bug to fix,
  never a "difference" to accept or a redesign to invent. GUI feature
  missing core support → extend the core, never simplify the GUI.
- **One frontend, many backends:** every backend renders in this GUI —
  a backend is just an account. Backend-specific UI is limited to auth
  steps and capability-gated actions (Capabilities/ErrNotSupported);
  everything else is shared surface.
- **AyuGram layout (the standard):** three-pane structure — left chat list
  column (account switcher + search + folder tabs + dialog list), main chat
  view (peer header with name/status, message list, composer), optional
  right info/media panel. Same navigation model, same behaviors (folder
  tabs above the list, unread badges, jump-to-message, context menus).
  When unsure how something should look or behave, open AyuGramDesktop and
  copy the *behavior* (never the code).
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
- **Message bubbles**: outgoing/incoming styles, sender name in groups,
  timestamps, delivery ticks, unread separator, day dividers.
- **Login**: backend picker (grid of cards), per-backend auth form driven by
  the engine auth state machine (step prompt + input + back + progress +
  error). Never a raw JSON dump.
- **Voice mode**: second top-level GUI mode (Chat/Voice tabs) — call list,
  join screen, mic/speaker controls, wired to real voice-capable backends
  through `wrtc`. Renders **only** what the engine actually reports. No
  simulated calls, no fake participants, no "coming soon" banner — an
  honest empty state ("no voice backends connected") is the ceiling of
  what may be shown until real call UI lands.

## 8. Cores: status, sources, policy

Cores are protocol implementations behind `cores.Core`.

**Policy (owner's rules, enforced):**
- **Tests first.** Write the tests *before* reading/writing implementation
  code. Every core must be verified against something real-world-verifiable:
  a **dockerized server first** (ergo for IRC, prosody for XMPP,
  mumble-server...), then the **official server** (env-gated live tests).
  "It compiles" and "a research file says so" are not verification.
- **Replace, don't patch.** Stale/bad core → complete replacement (§1.12).
- **Non-Go implementations are reference-only.** Protocol docs, feature
  checklists, GUI inspiration. Never a runtime dependency, never vendored.
- **Go beyond what's provided.** The repo's code, libs and samples are
  starting points; do your own research. Use web search / RTFM whenever
  uncertain — old research notes may be stale or hallucinated.

| Core | State (2026-09) | Go base / candidates | Reference material (read-only) |
|---|---|---|---|
| telegram | Most complete. 1:1 AyuGram feature work continues here. | gotd/td — https://github.com/gotd/td | AyuGramDesktop — https://github.com/AyuGram/AyuGramDesktop (GUI/feature spec 1:1, §7); tdlib/td — https://github.com/tdlib/td/ (C++ official — protocol reference only) |
| matrix | Builds; E2EE via goolm (pure Go, tag `goolm`). | mautrix/go — https://github.com/mautrix/go | element-web — https://github.com/element-hq/element-web (what Matrix *supports*; its UI is NOT our inspiration — owner finds it ugly); matrix-rust-sdk — https://github.com/matrix-org/matrix-rust-sdk (Rust, ignored — non-Go) |
| irc | Live-tested vs real server (own RFC2812+IRCv3 impl). | own impl, girc-style | lrstanley/girc — https://github.com/lrstanley/girc (Go); kiwiirc/irc-framework — https://github.com/kiwiirc/irc-framework (Node); hexchat — https://github.com/hexchat/hexchat (archived client); protocol: https://modern.ircdocs.horse/ + https://ircv3.net/ |
| github | Live-tested vs real API. | own impl on net/http | The GitHub REST/GraphQL API docs themselves. **Design rule:** think what a social network needs (feed, profiles, DMs, groups, notifications) and which GitHub surfaces map to it; design the arch FIRST, *then* compare with the existing core and fix it to match. |
| xmpp | Implementation exists, unverified live. | evaluate and pick one: xmppo/go-xmpp — https://github.com/xmppo/go-xmpp vs mellium/xmpp — https://codeberg.org/mellium/xmpp | Smack — https://github.com/igniterealtime/Smack (Java); Conversations — https://codeberg.org/iNPUTmice/Conversations (Android, "just works" behavior reference — not looks) |
| bale | Implementation exists, unverified live (geo-restricted). | own protobuf-over-websocket impl | Balethon — https://github.com/Balethon/Balethon (Python); aiobale — https://github.com/aminmadaniofficial/aiobale (client impl); web client — https://web.bale.ai/ (live reference) |
| rubika | Implementation exists, unverified live (geo-restricted). | own impl | reverse-engineered protocol notes in research/ (verify before trusting) |
| deltachat | Implementation exists, unverified live. | candidate stack: go-imap + go-smtp + go-crypto + modernc/sqlite | chatmail/core — https://github.com/chatmail/core (Rust official — reference only); deltachat-desktop — https://github.com/deltachat/deltachat-desktop |
| mumble | **Broken/stale — owner called it out.** Rewrite tests-first (docker mumble-server) or keep hidden. | evaluate layeh/gumble — https://github.com/layeh/gumble; may need own impl | protocol docs — https://github.com/mumble-voip/mumble/tree/master/docs/dev/network-protocol; mumble desktop client — https://github.com/mumble-voip/mumble (possible voice-GUI inspiration) |
| teamspeak | **Broken/stale — same as mumble.** | RE candidates: ts3j — https://github.com/Manevolent/ts3j; gospeak — https://github.com/NicolasHaas/gospeak; go-ts3 — https://github.com/rocketsciencegg/go-ts3; tsclientlib — https://github.com/ReSpeak/tsclientlib | TS3AudioBot — https://github.com/Splamy/TS3AudioBot (best-effort RE sources) |

Mumble + TeamSpeak stay hidden behind an env flag until rewritten — do not
ship them as "working".

## 9. Testing rules

- **Write tests before code.** For any core/engine change: failing test
  first, then the implementation that passes it.
- `go test ./...` (with `-tags goolm`) must pass on every commit that ships.
- gofmt + vet clean, always.
- Live tests live in `go/tests/`, gated behind env vars (e.g.
  `UNICLIENT_LIVE_IRC=1`), never run in CI, never need secrets in the repo.
- Docker-based protocol tests are the preferred verification ladder rung
  before touching official servers; official-server tests are the final
  proof. Every core gets both before being called "done".

## 10. Repo hygiene

- No build artifacts committed. `dist/` is gitignored.
- No generated code committed (protobuf codegen was deleted with the bridge;
  if codegen is ever reintroduced, generate in CI, don't commit).
- **`research/` is agent scratch space.** Minimize, delete, modify, rewrite
  anything in there however needed to keep it from confusing you. Nothing in
  the repo depends on it. Read old notes with suspicion: they may be
  outdated or hallucinated — verify against primary sources before acting.
- Markdown stays short and true. If a doc describes something the code no
  longer does, fix the doc or delete it. Docs that smell like hallucination
  get deleted, not "fixed" with more words.
- `WORKLOG.md`: append one entry per work session (what changed, why, what is
  next). This is the resume-from-zero mechanism for agents.

## 11. Session checklist

Legend: `[x]` done, `[~]` in progress, `[ ]` todo. The topmost unchecked item
is the next task.

- [x] AGENTS.md rewritten from scratch (owner's 2026-09 requirements)
- [x] All md files refreshed (README, WORKLOG, research headers)
- [x] Bridge/proto/web-UI/CLI-host deleted; repo is pure Go
- [x] Single binary `cmd/uniclient` (Gio native GUI)
- [x] `gui/` package: theme, sidebar+folders, chat view, login flow, voice tab
- [x] Scrolling + scrollbars everywhere
- [x] Responsive material buttons + ripple
- [x] Progress/connection indicators
- [x] `bootstrap/` package (engine wiring without bridge)
- [x] flake.nix for NixOS (run + dev shell)
- [x] release.yml: tag-only triggers, linux+windows+android+wasm, UPX, prerelease
- [x] gh-pages WASM deploy to /Uniclient/
- [x] ci.yml removed (per owner: CI only on release)
- [x] gofmt/vet/tests green; linux/windows/wasm builds verified
- [x] AGENTS.md updated: placeholder ban (§1.10), AyuGram-1:1 layout rule
      (§1.11 + §7), core sources & policies from the owner's full
      requirements dump folded into §1/§8/§9/§10, and the owner's workflow
      rules (deep research → think deeply → rate → best plan → tests →
      code → real-world verify) enforced as §1.13-14 + §2
- [x] **Delete the demo backend** — `cores/demo.go`, `-demo` flag,
      welcome-screen demo entry, bootstrap registration: DONE, verified
      (tests-first: StartAuth rejects "demo", stale demo rows purged at
      boot; welcome-screen screenshot shows one CTA "Add an account",
      no demo mention; run 34151360457 all green)
- [x] Voice tab pass: "coming soon"/"being rebuilt" copy and dead Join
      button removed — real engine state only (§7); compile+review verified
      (visual pass lands with a real voice-capable account)
- [x] Dispatch-only verify workflow (§5) — full gate + cross-builds +
      Xvfb GUI smoke with screenshot artifacts
- [~] **AyuGram 1:1 parity program (§1.11 mandate):** mirror
      AyuGramDesktop feature-by-feature in `gui/` (source-level
      comparison, tracked in research/ayugram_parity.md); extend cores
      where functionality is missing; Telegram core+GUI = exact 1:1 first
      (folders sync, ghost mode, QR verify, message actions, settings,
      search, media...), other cores follow
      - slices 67–76 (2026-09-09): archived-chats collapsed row + view;
        sidebar row badges (verified/premium/scam/fake + @-mention +
        unread-reactions); slow-mode countdown + write-restriction
        composer; group-call live bar (GetGroupCall poll + JoinGroupCall);
        own-profile editor (avatar/username/bio/birthday); LRead/SRead
        drawer toggles (LocalReadMark config, mark-on-open gate); bot
        commands "/" menu (GetChatBotCommands); top peers strip while
        searching (GetTopPeers). README rewritten to match the real
        architecture (the old one described the deleted bridge).
- [ ] mumble + teamspeak rewrite (tests first, docker-based, §8)
- [ ] Verify xmpp / bale / rubika / deltachat cores live or replace them (§8)
- [ ] Voice mode: real call UI on top of wrtc
- [ ] First non-prerelease when owner approves
