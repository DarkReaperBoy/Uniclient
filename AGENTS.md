# AGENTS.md — UniChat (working title) — v3.1 (final, re-verified)

> The operating system for humans and AI agents building UniChat.
> **If you are an agent with no prior context: read this file top-to-bottom, then
> `WORKLOG.md` (last 3 entries), then §15 "Current status". You may then resume work
> without asking the owner anything technical.**

Project: one pure-Go, cross-platform (Windows/macOS/Linux, Android/iOS, Web/WASM) messenger
that speaks many chat protocols and voice protocols through one standardized GUI, with
backends added/switched as easily as accounts. GUI inspired by AyuGram's layout and
Telegram feature parity (re-implemented, never copied), Material Design visuals, built
with Gio.

- Owner: non-programmer product owner. Communicates in features and acceptance, not code.
- Builders: AI coding agents (primary) + any human contributors.
- Repo created: 2026-09-07. Research verified: 2026-09-07 (three streams — see §1).
- **v3 (superseded by v3.1)**: third verification pass completed 2026-09-07 — an *executable* pure-Go
  build matrix (research/16) that corrected two v2 claims (Gio's cgo reality on
  Linux/macOS/mobile; keyring's darwin mechanism), pinned current versions of every
  dependency, and refined the Pure-Go Policy into three enforceable tiers.
- **v3.1 (this file)**: round-4 challenge-response, same day. An external AI claimed
  "Linux, Windows, and WebAssembly can all build entirely cgo-free (CGO_ENABLED=0);
  macOS and iOS are the main platforms requiring cgo." Re-verified from scratch (fresh
  toolchain, fresh module cache, gio v0.10.2 tag + master cloned): Windows+WASM pure
  (confirmed), macOS/iOS cgo (confirmed), **Linux claim REJECTED** — `gioui.org/app`
  fails CGO_ENABLED=0 on Linux under all seven build-tag combos because the X11 AND
  Wayland windowing, every GPU path, and the xkb keyboard layer are cgo in v0.10.2; gio
  master (2026-09-02) is architecturally identical. Android also requires cgo (omitted
  by the external claim). One internal correction: v3's "X11 windowing is pure Go"
  wording was wrong — it is cgo. Evidence: research/16 round 4 (raw results preserved at
  research_raw/verify4/, reproducible via scripts/verify_matrix4.sh); exact Linux
  dev-header list updated in §8.

---

## 0. The rules that never bend (read twice)

1. **Pure-Go Policy (v3, evidence-based — three tiers).** All application code is Go.
   Enforcement is mechanical, not aspirational:
   - **Tier A — application code (hard rule):** every package we write under `internal/`
     (domain, core, state, infra, ui logic) compiles with `CGO_ENABLED=0` for the full target
     matrix {windows,linux,darwin,android,ios} x {amd64,arm64} + `GOOS=js GOARCH=wasm`
     (as library packages; executable linking on android/ios is a gogio/cgo concern, below).
     Zero `.c/.m/.h` files in our repo (single exception: the vendored `internal/gumble` fork,
     whose cgo subpackages are deleted on day one).
   - **Tier B — the whole app, pure platforms:** the complete application (GUI included)
     builds with `CGO_ENABLED=0` on **Windows (amd64+arm64) and WebAssembly**. These two are
     the living proof the app is pure Go where the platform allows it. (Verified:
     research/16.)
   - **Tier C — GUI platform glue (Gio's, never ours):** on Linux, macOS, iOS and Android,
     Gio reaches the OS graphics stack through cgo — EGL/Vulkan (Linux, via pkg-config/ldl),
     Metal (macOS/iOS, via Objective-C), EGL+JNI (Android, via NDK). This is a **platform
     contract**, the same category as Xcode/NDK build toolchains: every linked library ships
     with the OS, users install nothing, and no non-Go code ever enters OUR repo. Verified
     empirically + from gio's own install doc ("Windows: no special compiler is needed, as we
     don't use CGo for Windows support" — the pure-Go claim is Windows+WASM-literal).
     Our code NEVER adds cgo. Any future native interop (mic capture, WinRT toasts,
     notifications) lives in thin build-tagged adapters under `internal/infra/*/drivers`,
     each ADR'd and documented in `docs/building.md`.
   - **Runtime guarantee (the owner's actual constraint):** nothing to install, no bundled
     native libraries, no other-language runtimes, no ffmpeg/python/node/java. Go modules are
     allowed and expected (that is not "dependency hell" — that is Go). Platform SDKs
     (Xcode, Android SDK/NDK, pkg-config headers) exist at BUILD time only.
   - Sanctioned escape hatches (each requires an ADR before use):
     - `wazero` (pure-Go wasm runtime) + wasm modules WE ship. iOS: interpreter mode only (JIT ban).
     - `purego` dlopen of system libs — optional runtime drivers, DESKTOP only (purego itself
       needs CGO_ENABLED=1 on Android/iOS), never default, never bundled requirements.
     - Optional external binaries (e.g. `notify-send`) — detected, graceful-degrade, never required.
   - Compile-budget note: gotd's generated `tg` package needs ~2 GB+ RAM to compile; on small
     machines build with `-p 1` + `GOMEMLIMIT=900MiB GOGC=30` (recipe verified, §8).
2. **No telemetry. Ever.** No analytics, no crash reporters, no update pings home. Network
   traffic = the messengers' protocols + user-configured services (e.g. translator URL)
   + explicit version-check flag the user turns on.
3. **Privacy-first defaults.** Secrets encrypted at rest (vault). Nothing leaves the device
   except protocol traffic. Local DB is the source of truth (offline-first).
4. **TDD is not negotiable** for `core/`, `domain/`, `infra/store/`, `infra/audio/`:
   failing test FIRST (fixture- or docker-backed), then code. UI code is developed against
   the Loopback fake backend with scripted-event tests. (Ladder: research/13; protocol: §7.)
5. **Never break the build to "fix later."** Every commit: `make lint test purego` green.
6. **AyuGram/Telegram Desktop/Element/gomuks are REFERENCE-ONLY.** Their licenses are
   GPL-family (gomuks AGPL, AyuGram GPLv3). Zero code copying into this repo. Read their
   code for understanding, write ours from scratch. When in doubt: don't.
7. **Scope discipline.** New features route through the roadmap + checklist (§12/§13).
   If the owner asks for something out-of-phase, add it to the backlog section, cite the
   phase, and finish the current phase gate first. (Exceptions: crashes, data-loss, security.)
8. **Worklog is sacred.** Every agent session appends to `WORKLOG.md`. No context survives
   between sessions except what's written here, in `docs/adr/`, and in git history.
9. **No secrets in the repo.** Test credentials live in env vars (`.env.test`, gitignored)
   and CI secrets. The vault format is documented, never a committed private key.
10. **Honest capability flags.** UI never fakes features a backend lacks (typing indicators
    on IRC, read receipts on GitHub...). `Caps` (§4) decides what renders. A Caps claim
    MUST be backed by an implemented capability interface (§4.4 — the registry enforces it).
11. **License of UniChat itself: MIT (proposed).** Owner confirms at first public release.
    Dependency licenses stay in {MIT, BSD, Apache-2.0, MPL-2.0} (§10); GPL/AGPL = read-only
    reference, never linked, never copied.

---

## 1. Research provenance & conflict resolution (how this file got its facts)

Three research streams feed this project:

- **Stream A (VERIFIED — the evidence base):** `research/00–14`. 70+ live web searches,
  fetched READMEs/licenses/protocol docs, 2026-09-07. Primary-source-checked.
- **Stream A round 3 (EXECUTED — strongest evidence):** `research/16`, same day. An actual
  Go 1.27.1 toolchain was installed and every planned dependency was *compiled* with
  `CGO_ENABLED=0` across the platform matrix (scripts + raw results preserved). This round
  corrected two stream-A/v2 claims:
  | # | Topic | v2 said | Executed reality (research/16) | Resolution |
  |---|---|---|---|---|
  | 1 | Gio cgo footprint | "pure Go on all platforms" (over-read of marketing) | Gio is cgo-LITERAL-pure on Windows+WASM only; Linux (EGL/Vulkan), macOS/iOS (Metal/ObjC), Android (JNI/EGL) use cgo OS glue; gio's own install doc states the Windows-only claim | **Pure-Go Policy re-tiered (§0.1)** — app code stays CGO_ENABLED=0-enforced everywhere; full app pure on Windows+WASM; OS glue accepted as platform contract. No backend/lib choices changed. |
  | 2 | keyring on macOS | "pure Go per issue #64" (right conclusion, wrong mechanism) | v0.2.8 darwin impl = `/usr/bin/security` subprocess; keybase CGo dep removed from go.mod (wincred+godbus only) | Conclusion stands; mechanism documented (research/12). macOS keyring = OS-shipped CLI, not a dependency. |
  Plus: exact current versions of all 20 modules resolved via go modules proxy (§2), gotd
  contrib's real package layout (`middleware/floodwait`, `middleware/ratelimit`, `storage` —
  there is no `contrib/session`/`contrib/peers` in v0.25.0), pion/webrtc **v4** exists
  (v4.2.20), modernc.org/sqlite has **no js/wasm build** (browser storage adapter confirmed
  necessary, as P9 already planned), and the tg-compile memory recipe.
- **Stream A round 4 (CHALLENGE-RESPONSE — re-executed):** an external AI's claim ("Linux,
  Windows, and WebAssembly can all build entirely cgo-free; macOS and iOS are the main
  cgo platforms") was tested to destruction and **partially rejected**: building
  `gioui.org/app` with CGO_ENABLED=0 fails on Linux under ALL seven build-tag combos
  (`nox11`/`nowayland`/`novulkan`/`noopengl` permutations — windowing, GPU, and keyboard
  are cgo in v0.10.2); Android's cgo requirement was omitted from the claim. The
  Windows/WASM/macOS/iOS parts were confirmed. Evidence: research/16 round 4 (fresh
  toolchain + fresh module cache); gio master (c7517b7, 2026-09-02) checked — same
  architecture. This is the model for handling external input: welcome it, then execute
  it.
- **Stream B (SUPPLIED — input, not authority):** `research/15`. An external feasibility
  analysis (rates the plan 8.2/10) plus a second model's draft AGENTS.md, pasted into the
  project 2026-09-06/07. Preserved verbatim-in-spirit; nothing in it is trusted until
  verified. (The paste arrived ~20 times, identical — checksummed; treat as one document.)

**Ratings (deliberately not averaged):**

- **8.2/10** — supplied feasibility assessment (stream B): portability, decoupling, and
  protocol fit are strong; friction sits in Gio immediate-mode state, native audio, and
  proprietary protocols.
- **7.5/10** — conservative product-readiness assessment (stream A, research/00):
  S-tier vision and constraints; C-tier literal scope; fixed by phasing (§3, §12).

**The 7.5 is the go-forward gate.** An architecture can be theoretically feasible while
still being incomplete, expensive, or operationally fragile. Feasibility is a floor, not a
verdict. (The second model's own separate score was 7.2/10 — same neighborhood; we keep
the verified 7.5.)

**Provenance rule:** where stream B conflicts with stream A, A wins until B's claim is
independently verified against upstream documentation or executable tests. Conflicts
found and resolved during the v2 merge:

| # | Topic | Stream B said | Stream A verified | Resolution |
|---|---|---|---|---|
| 1 | XMPP foundation | go-xmpp as "wire-level starting point" (muc/pubsub "useful basics") | go-xmpp self-describes as "simple Google Talk client" (RFC 3920/3921, pkg.go.dev Jul 2026); no MAM/SM/carbons ecosystem. mellium: MUC+MAM+SM+carbons subpackages, BSD-2, active (research/10) | **mellium.im/xmpp stays primary.** go-xmpp = ignored (donor-of-last-resort only) |
| 2 | Backend order | Telegram → Matrix → GitHub → IRC → ... | — (judgment, both defensible) | **Telegram → IRC → GitHub → voice → Matrix** (§12): GitHub early = neutrality probe; IRC early = fastest Caps-degradation proof; voice is product pillar #2 and must not starve; Matrix E2EE is heavy and lands after neutrality is proven |
| 3 | Backend API shape | capability interfaces only; reject one giant `FullBackend` | — (design) | **Hybrid (§4.4):** slim required `AccountConn` + optional capability interfaces + `Caps` runtime data + startup assertion that Caps claims match implemented interfaces. Best of both: compiler-enforced segregation AND data-driven UI |
| 4 | Event bus | supplied draft called a mutex design "lock-free" (its own correction) | — | Correctness first: bounded channels + coalescer; full guarantee list in §4.6 |
| 5 | Storage | supplied: boltdb; second model: "evaluate by workload" | modernc.org/sqlite passes workload gates at research level (research/12): FTS5, single-writer+WAL, pure Go | **SQLite stays**; B's runtime benchmark matrix (100k/1M/10M) adopted into §7/§10 |
| 6 | GitHub events | "not realtime; latency seconds to hours" | VERIFIED: docs.github.com/v3/activity/events — "not built to serve real-time use cases... event latency can be anywhere from 30s to 6h" | Polling + ETags design confirmed (§6); cite the docs |
| 7 | Telegram test env | "official telegram test environment where available" | VERIFIED: core.telegram.org/api/auth — 3 test DCs, reserved phone prefixes, login code = DC number x5, periodic wipes; "test on Test DCs before Production" | Adopted into the live-verification ladder (§7): tgtest (in-proc) → test DCs → production |
| 8 | DeltaChat | supplied analysis included it; second model DROPPED it from phases | Owner's spec explicitly includes DeltaChat (research/05) | **Kept** at P8 |
| 9 | File layout | `cmd/ pkg/ backend/ media/` | — | **`internal/`-first layout stays** (§9): idiomatic Go visibility; their layout noted as rejected alternative |

**Adopted from B (net improvements over v1):** capability-interface segregation,
event-bus guarantee list, platform-dependency classification (§0.1), per-backend priority
gates (§6.0), build-quality verification matrix — compile is not enough (§8), conformance
3-doc strategy (§7), notification model + dedup (§5.5), diagnostics screen + redacted
export (§5.6), extended fuzz + benchmark suites (§7/§10), source-freshness discipline
(§14), what-not-to-do list (§16).

**Source discipline for every future agent:** verify version-sensitive claims against
current upstream documentation before relying on them; never copy a source's conclusion
merely because it appears in a file — including this one. This file records decisions and
research trails; it is not authority over upstream projects. The strongest verification is
executable: when a claim can be tested by building/running code, do that (research/16 is
the template).

---

## 2. Ground truth (verified 2026-09-07; versions resolved via module proxy + compiled — re-verify >6mo-old items before leaning on them)

Full evidence: `research/` (00–16 + README with core verdicts). Executive summary:

- **Go: 1.27.1** is current stable (go.dev, 2026-09-07). Toolchain floor for the repo: latest stable.
- **Gio v0.10.2** (Aug 2026, go.mod = only pure-Go deps): active, Material widgets
  (`widget/material`), all platforms incl. WASM (experimental), gogio packages mobile apps.
  **Cgo: pure on Windows+WASM; OS-glue cgo on Linux/Metal/JNI (§0.1 Tier C, research/16).**
  Pre-1.0: pin + upgrade deliberately.
- **gotd/td v0.161.0** (MIT, stable, "mostly feature-complete"): Telegram MTProto incl. **voice/video
  calls + group voice chats via tgcalls over pion WebRTC** (`telegram/calls`), WASM transport,
  MTProxy+SOCKS, contrib **v0.25.0** (packages: `middleware/floodwait`, `middleware/ratelimit`,
  `storage` = session/peer storage), **tgtest** (pure-Go fake Telegram server for CI), and an
  **official Telegram test environment** (3 test DCs, reserved phone prefixes, login code = DC# x5,
  periodic data wipes — core.telegram.org/api/auth).
- **mautrix/go v0.30.0** (MPL-2.0, active): Matrix with **full E2EE** (goolm = pure-Go Olm/Megolm,
  cross-signing, verification). Proven end-to-end by **gomuks** (reference only, AGPL).
  CI server: Dendrite (dev wound down — fine as a frozen CI target) + Synapse nightly.
- **girc v1.1.2** (MIT): stdlib-only IRC + IRCv3 (SASL, message-tags...). **Ergo** (docker) for CI,
  with **chathistory** backfill. Fallback donor: ergochat/irc-go.
- **mellium.im/xmpp v0.23.0** (BSD-2, active May 2026): MUC/MAM/SM/carbons subpackages. OMEMO
  E2EE = known gap (ADR-007 pending; v1 ships without XMPP E2EE). go-xmpp rejected
  ("simple Google Talk client" scope).
- **Mumble**: gumble (MPL-2.0, archived; module path **layeh.com/gumble**, last commit Dec 2022 —
  confirmed) → **vendor+fork**; official docker server image
  (mumblevoip/mumble-server); protocol = protobuf control + CryptState UDP + Opus.
- **TeamSpeak**: closed protocol; ts3j (Java, Apache-2.0, last release Mar 2026) +
  TS3AudioBot headless-client code = RE knowledge base → our own Go core, **experimental,
  opt-in flag, kill criteria set** (legal note in research/09). ServerQuery ≠ voice client
  (go-ts3 = admin tool only).
- **Bale**: no official client API; aiobale (MIT, active) = RE'd WSS+protobuf user client →
  our own Go port, experimental tier, chat-only, fixtures-only testing.
- **DeltaChat**: Rust core excluded → our Go core over IMAP/SMTP + Autocrypt/SecureJoin
  (go-imap **v2.0.0-beta.8** + go-mail **v0.8.1** + go-crypto **v1.4.1**), late phase,
  interop-tested against official client on chatmail docker.
- **GitHub**: REST (**google/go-github v90.0.0**, BSD-3, releases Aug 2026) + GraphQL
  (shurcooL/githubv4, alive as of Feb 2026); reframed as notification inbox + threads +
  reactions + profiles. **Events API is not realtime — official docs: "not built to serve
  real-time use cases... latency 30s to 6h"; events retention ~31 days (Jan 2025 change)**.
  No following-feed API, no DMs — flagged, not faked. Rate limits: REST 5,000 req/h +
  GraphQL 5,000 points/h (304s w/ ETags are free). Fine-grained PAT / device flow auth.
- **Audio**: Opus pure Go = **kazzmir/opus-go v1.3.0** (transpiled libopus, enc+dec, "No cgo is
  used" — README fetched + imports compiled) primary, pion/opus (decoder-mature) secondary,
  wazero+libopus.wasm fallback. Playback = **ebitengine/oto v3.5.0** (Windows/macOS/Linux/BSD/WASM
  "no Cgo required"; Linux = pure-Go PulseAudio + ALSA dlopen fallback; Android/iOS = platform
  glue). **Mic capture is THE gap**: no maintained pure-Go capture — plan: browser-WASM first,
  Android JNI bridge (cgo glue, platform contract), Windows WASAPI syscalls, macOS/Linux last
  (research/11 has the ranked options).
- **Voice calls**: **pion/webrtc v4.2.20** (v4 line active, Sep 2026; MIT) — gotd `telegram/calls`
  rides on pion; Matrix 1:1 via Jingle+pion. (pion does NOT build for js/wasm — calls are
  native-platform features, excluded from the wasm build via tags.)
- **Storage**: **modernc.org/sqlite v1.58.0** (pure Go, active, FTS5) single-writer + WAL.
  **No js/wasm build** — browser tier uses an OPFS/JS-interop storage adapter (P9, as planned).
  Vault: filippo.io/age **v1.3.2** + zalando/go-keyring **v0.2.8** (darwin = /usr/bin/security
  subprocess — pure Go; linux = godbus; windows = wincred; mobile/wasm = passphrase fallback).
- **Markdown**: goldmark v1.8.6 (pure Go) for GitHub content rendering.
- **Build matrix (research/16, executed 2026-09-07; round-4 re-executed same day under
  external challenge):** core layer (all 20 protocol/crypto/storage/codec deps) compiles
  CGO_ENABLED=0 as libraries on the full platform matrix; full UI app compiles
  CGO_ENABLED=0 on windows amd64+arm64 and js/wasm. Linux UI builds (cgo) need a C
  compiler (gcc or clang) + pkg-config + libwayland/libxkbcommon(+x11)/libx11(+xcb)/
  libxcursor/libxfixes/libegl dev packages (exact one-liner in §8). tg compile recipe:
  `-p 1` + GOMEMLIMIT on <4GB machines.
- **Streams reconciled**: research/15 documents every B-claim, its verification status, and
  the merge outcome. When in doubt: A wins; executed evidence beats both.

---

## 3. Scope (tiers) — the answer to "everything at once"

| Tier | Backend | Mode | Phase |
|---|---|---|---|
| 1 | Telegram (gotd) | chat | 2 |
| 1 | IRC (girc) | chat | 3 |
| 1 | GitHub (go-github+v4) — the neutrality probe | chat | 4 |
| 2 | Mumble (gumble fork) + TG calls | voice anchor | 5 (voice mode itself) |
| 2 | Matrix (mautrix) | chat | 6 |
| 2 | XMPP (mellium) | chat | 7 |
| 3 | DeltaChat (own Go core) | chat | 8 |
| 3 | Web/WASM hardening | — | 9 |
| 4 | Bale (own Go core) | chat | 10a |
| 4 | TeamSpeak (own RE core) | voice | 10b (experimental flag) |

Voice-mode participants by backend: Telegram (1:1 + group, P5), Mumble (P5), Matrix 1:1
(P6+), XMPP Jingle (P7+), Matrix group via MatrixRTC/LiveKit (P10 research), TS3 (P10b
experimental). IRC/Bale/DC/GitHub = chat-only forever (Caps say so).

Platforms: desktop trio from P1; Android from P1.5 (gogio), iOS from P5 (needs audio bridge),
WASM from P9. Platform purity per §0.1: Windows+WASM = fully CGO-free builds; Linux/macOS/
Android/iOS = pure Go source + Gio OS-glue (build toolchains only).

Why this order (the three probes before the pile-on): Telegram proves the domain model
can hold the *richest* chat backend; IRC proves honest *degradation* (Caps hiding what
isn't there); GitHub proves *backend-neutrality* (a non-chat object model projected onto
the same GUI). After those three, the model is trustworthy enough to absorb Matrix E2EE,
XMPP profiles, and a from-scratch DeltaChat core without architecture lies. Voice lands
at P5 because it is product pillar #2 and its risks (audio spikes S1–S5) must be retired
early, not last.

---

## 4. Architecture

Layered, strict dependency direction (top depends on bottom, never up):

```
┌───────────────────────────────────────────────────────────────┐
│ UI (Gio)                     internal/ui                      │
│   chat mode | voice mode | settings | wizard | kit(Material)  │
│   reads immutable snapshots; emits Intents                    │
├───────────────────────────────────────────────────────────────┤
│ App state (single writer)     internal/state                  │
│   Accounts / Conversations / ViewModels / NotifCenter         │
│   Event bus (fan-in from cores, coalesced) + Intent dispatch  │
├───────────────────────────────────────────────────────────────┤
│ Core adapters (one per backend)  internal/core/<name>          │
│   telegram(gotd) irc(girc) github(go-github+v4)               │
│   matrix(mautrix) xmpp(mellium)                                │
│   mumble(internal/gumble fork) deltachat(own)                 │
│   bale(own) teamspeak(own, +build tag experimental)           │
│   loopback (fake — drives UI dev + tests)                     │
│   speak: domain types + Event stream + capability interfaces  │
├───────────────────────────────────────────────────────────────┤
│ Domain (protocol-agnostic)     internal/domain                 │
│   Account Conversation Message User Caps AuthFlow Event       │
│   Content blocks MediaRef Reaction SyncCursor errors          │
├───────────────────────────────────────────────────────────────┤
│ Infra                          internal/infra                   │
│   store(sqlite+FTS5+meta) blobs media cache vault(age)        │
│   audio(capture/playback/opus/mixer/dsp) net(proxies)         │
│   i18n fonts(slog) log                                         │
└───────────────────────────────────────────────────────────────┘
```

Hard rules:
- UI never imports a core. Cores never import UI or state. Domain imports only stdlib
  (+ x/* exceptions listed in an allowlist test).
- The **store is the UI's only source of truth**. Cores emit events; state applies them to
  the store and updates view models; the UI reads snapshots. (Offline-first for free; the
  UI is a projection of application state, never the source of it.)
- One goroutine owns state mutation (the "app actor"); cores are independent actors with
  their own serial loops (gotd-style: serialize protocol state, never share it raw).
- Events are coalesced/batched per ~100ms tick to keep 60fps under backfill storms.
- Cancellation: every core command takes `ctx`; UI cancels without leaks; reconnect loops
  use their own lifecycle ctx (not UI's frame ctx).

### 4.1 The standardization layer (the heart of "one GUI handles em all")

```go
// internal/domain/caps.go — per-account+conversation capability flags; UI hides what's off.
// Caps is RUNTIME DATA the UI renders from (server-dependent caps are negotiated live:
// IRC chathistory, XMPP MAM, Matrix room version...). It must never disagree with the
// interfaces a core actually implements — see 4.4.
type Caps struct {
    Typing, Presence, ReadReceipts, Reactions, Edits, DeleteForAll, Threads bool
    Backfill  BackfillLevel // none | local | server
    Media     MediaLevel    // none | files | photos | full
    Voice     VoiceLevel    // none | notes | calls1to1 | callsGroup
    Search    SearchLevel   // none | local | server
    E2EE      E2EELevel     // none | transport | e2ee | verified
    MaxMsgLen int
}
// Status vocabulary per capability: supported | partial | experimental | unavailable |
// server-dependent | platform-dependent (surfaced in FeatureHint UI + backend FEATURES.md).
```

### 4.2 Required backend surface (the universal minimum)

```go
// internal/domain/backend.go
type Backend interface {
    Kind() Kind            // telegram, irc, matrix, ...
    Modes() Modes          // chat, voice, both
    NewAccount(cfg AccountConfig) (AccountConn, error)
}

// Every chat-capable backend implements EXACTLY this required surface — the universal
// minimum every real chat protocol has. If a backend can't do these, it isn't a chat
// backend. Everything else is a capability interface (4.4). No god interface: no backend
// is forced to stub features its protocol doesn't have.
type AccountConn interface {
    Kind() Kind
    Me() User
    Caps() Caps                       // live capability snapshot for this account
    Events() <-chan Event             // tap; state coalesces (guarantees: 4.6)
    Auth() AuthFlow                   // wizard steps
    Conversations(ctx context.Context) ([]Conversation, error)
    SendText(ctx context.Context, conv ConvID, blocks []Block, opts SendOpts) (MsgID, error)
    Backfill(ctx context.Context, conv ConvID, before time.Time, limit int) error
    Close(ctx context.Context) error
}

type AuthFlow interface {       // generic wizard: UI renders steps generically
    Steps() []AuthStep          // {Phone, Code, Password} | {JID, Password} | {PAT}...
    Submit(ctx context.Context, step AuthStep, value string) (AuthResult, error) // Done | Next | Retry
}
```

### 4.3 Domain events & messages

```go
// internal/domain/event.go — one event vocabulary for all backends.
type Event interface{ isEvent() }
// MessageNew/Edited/Deleted/ReactionChanged/TypingStarted/ReadReceipt/PresenceChanged/
// ConversationNew/Updated/Removed/MemberJoined/Left/TitleChanged/BackfillDone/
// SyncProgress/ConnectionStateChanged/AuthChallenge/CallIncoming/VoiceRoomUpdated/
// UserSpeaking/Error{Kind: ErrAuth|ErrNet|ErrRate|ErrProto, Retryable bool}
```

```go
// internal/domain/message.go — content blocks, not HTML.
type Block interface{ isBlock() }
// Text{Runs []Run{Style, Mentions}}, MediaRef{Kind, Mime, W,H, Dur, ThumbRef},
// VoiceNote{Dur, Waveform}, Sticker{Alt, Kind: static|animated-unrendered},
// Location, Poll, Dice, Service{What}, Quote{Of, Runs}
```

Each message carries `Origin` (raw protocol IDs — event_id / msg_id+peer / node_id /
message-id+folder / issue-number+comment-id) for dedupe, retry, and protocol round-trips.
The normalized model is a *projection*: Origin + `backend_extension` (typed per-backend
payload, escape hatch for advanced features) preserve backend-native identifiers,
revisions, and opaque metadata so normalization never destroys information a later
feature needs.

### 4.4 Optional capability interfaces (segregation + enforced honesty)

```go
// internal/domain/capabilities.go — small interfaces, asserted at runtime by the state
// layer. A core implements ONLY what its protocol truthfully supports.
type Editor interface {
    EditText(ctx context.Context, conv ConvID, msg MsgID, blocks []Block) error
}
type Deleter interface {
    Delete(ctx context.Context, conv ConvID, msg MsgID, forAll bool) error
}
type Reactor interface {
    React(ctx context.Context, conv ConvID, msg MsgID, emoji string, on bool) error
}
type TypingIndicator interface {
    SetTyping(ctx context.Context, conv ConvID, st TypingState, opts GhostOpts) error
}
type ReadMarker interface {
    MarkRead(ctx context.Context, conv ConvID, upTo MsgID, opts GhostOpts) error // GhostOpts = AyuGram ghost mode
}
type Searcher interface {
    Search(ctx context.Context, q Query) ([]SearchHit, error) // server-side search
}
type Moderator interface {
    Ban(ctx context.Context, conv ConvID, user UserID) error // + Unban/Kick/Mute as separate methods
}
type MediaAPI interface {
    Download(ctx context.Context, ref MediaRef) (io.ReadCloser, error) // + progress via events
    Upload(ctx context.Context, conv ConvID, file io.Reader, meta UploadMeta) (MediaRef, error)
}
type VoiceAPI interface { // call + voice-room control; nil = no voice
    Join(ctx context.Context, room RoomRef) error
    Leave(ctx context.Context) error
    SetMuted(ctx context.Context, muted bool) error
    SetUserVolume(ctx context.Context, user UserID, gain float64) error // per-user volume
}
```

**The honesty bridge (registry-enforced):** at `NewAccount`, the registry validates that
every `Caps` claim is backed by an implemented interface — `Caps.Reactions == true` but the
conn doesn't implement `Reactor` → hard startup error ("the core lied"). Conformance
tests (§7) enforce the same rule in CI. The UI reads ONLY `Caps` (data, cheap, per-frame);
the state layer asserts interfaces (compiler-checked); the registry binds them. This
replaces both rejected extremes: v1's fat interface (forced stubs) and B's pure-interface
discovery (UI would need reflection).

Voice/media plumbing stays nil-able: `conn.Voice()` returns nil when `Caps.Voice == none`.
Loopback implements ALL capability interfaces (so UI code paths are testable everywhere).

### 4.5 State & UI wiring

```go
// internal/state/app.go
type App struct { /* owned by app actor goroutine */ }
func (a *App) Dispatch(intent Intent)        // from UI event handlers
func (a *App) Snapshot() Snapshot            // per-frame read by Gio (immutable-ish)
func (a *App) Apply(ev domain.Event) error   // from bus; writes store; bumps view models
```

- Gio frame: `ui.Layout(win, app.Snapshot())` — widgets are pure functions of Snapshot.
- All sends: UI dispatches `Intent{SendMessage{Conv, Blocks}}` → state → core command →
  result event → store marks delivery state (sending → sent → failed w/ retry).
  Outbox rules: commands carry idempotency keys; attempt counts; never assume a locally
  accepted action was remotely accepted (reconcile on ack).
- Retained UI state lives HERE (navigation, selected account/conversation, scroll anchors,
  drafts, composer, selection, upload/download progress, search, window state) — the GUI
  layer is stateless-by-default and survives restarts via the store.
- This is what makes UI fully testable: `ui` package tests = feed scripted Snapshots,
  assert Intents. `state` tests = feed scripted Events, assert store + Snapshot.

### 4.6 Event pipeline guarantees (adopted from research/15, corrected)

- **Ordering:** each core serializes its own emission (single goroutine per account); the
  state actor applies per-account FIFO. Per-conversation ordering only where the protocol
  defines it (TG updates, Matrix sync); cross-account ordering is NOT guaranteed — render
  sorts by server timestamps.
- **Dedup:** Origin key (backend+account+remote type+remote id); store upserts are
  idempotent. Duplicate delivery is NORMAL (reconnects, initial sync) and must be a no-op,
  not an error.
- **Backpressure:** bounded per-core channel (1024). Overflow policy: ephemeral events
  (typing/presence) = newest-wins coalescing; MessageNew/Edited/Deleted = NEVER dropped —
  the core blocks (backpressure propagates to its network loop; the protocol buffers).
- **Slow consumers:** the UI is not a subscriber (pull model — Snapshot per frame), so a
  slow frame can't stall ingestion. Internal subscribers (NotifCenter, media prefetcher)
  get bounded queues + drop counters surfaced in diagnostics.
- **Recovery:** the STORE is the durable projection (we do not run a separate
  event-sourcing log in v1). After a crash, state rebuilds view models from the store;
  cores resume from sync cursors. If undo/audit features arrive, revisit via ADR.
- **Shutdown:** `Close(ctx)` cancels cores → state drains with a 5s deadline → store
  checkpoint (WAL). Every path has a written owner and a test.
- **Observability:** per-core counters (emitted / applied / deduped / dropped) exposed in
  the diagnostics screen (§5.6).

### 4.7 Storage schema (SQLite; single writer; WAL; FTS5)

```sql
accounts(id, kind, display, color, priority, caps_json, session_ref, created_at, last_sync)
conversations(id, account_id, remote_id, kind, title, avatar_ref, unread, mention_unread,
              pinned, muted, folder, last_msg_id, created_at)
users(id, account_id, remote_id, handle, display, avatar_ref, is_bot, presence, last_seen)
messages(id, conv_id, remote_id, author_id, sent_at, edited_at, deleted_local, deleted_remote,
         reply_to, thread_root, blocks_json, origin_json, delivery, flags)
message_revisions(msg_id, rev, blocks_json, edited_at)   -- anti-recall edit log (AyuGram parity)
reactions(msg_id, user_id, emoji, added_at)          -- unique(msg_id,user_id,emoji)
media(id, msg_id, kind, mime, bytes, sha256, path, thumb_path, state, w, h, dur)
read_states(conv_id, account_id, up_to_msg_id)
sync_cursors(account_id, conv_id, kind, value)
kv(key, value)                                        -- settings, schema_version
messages_fts fts5(content, content=messages...)       -- search
```

Migrations: `internal/infra/store/migrations/NNN_*.sql` embedded; runner tested up/down;
schema_version in kv. Backups: single file copy (sqlite) + vault re-seal; export tool later.
The store was chosen by workload (indexes, pagination, FTS, transactions) — research/15's
storage gate list (crash recovery, corruption, migration rollback, 100k/1M/10M benchmarks)
is part of P0/P2 store tests (§7). js/wasm tier: storage adapter over OPFS (P9) —
modernc.org/sqlite has no wasm build (verified, research/16).

### 4.8 Auth, media, audio, voice (short forms; details in research/02,03,11)

- Auth: generic wizard renders AuthFlow steps; secrets → vault (age) keyed by keyring or
  passphrase; sessions stored per account (`session_ref`); never in the message DB.
- Media: download w/ progress → blob dir (sha256-deduped, LRU-thumbed) → decode in workers
  (pure Go image codecs) → Gio-drawn. Unknown formats → icon + external-open. Streaming
  io, never whole-file-in-RAM; sanitized filenames.
- **Audio service (pipeline constants — P5 golden numbers):** internal bus = 48 kHz mono
  s16le; frame = 20 ms (960 samples); Opus voice mode with DTX + FEC enabled; jitter
  buffer adaptive 60–120 ms target; mixer = one 20 ms tick, N sources with per-source gain
  (= Mumble/TS per-user volume); resampling only at device boundaries (oto context rate ≠
  48k); single `oto.Context` per process (oto constraint). `CaptureSource` /
  `PlaybackSink` / `Codec` (opus) / `Mixer` / `Jitter` interfaces; platform drivers
  build-tagged (wasm JS-audio first; Android JNI glue; Windows WASAPI syscalls; macOS/Linux
  later or ADR'd purego desktop escape hatch); capability matrix surfaced in UI (never fake).
- Voice: `VoiceAPI` per backend → voice-mode UI (channel tree, speaking tiles, per-user
  volume, PTT/VAD); Telegram via gotd calls (pion tracks); Mumble via fork; Matrix via
  pion Jingle.

---

## 5. GUI specification (two modes, AyuGram layout semantics, Material visuals)

### 5.1 Global shell
- Left **AccountRail** (AyuGram style): stacked account avatars (color-coded per backend),
  unread/mention badges, add-account button, mode switch (Chat/Voice) segmented control,
  settings + lock (vault) at bottom.
- Chat mode: [AccountRail | ChatList (folders tabs, search, archive) | Conversation (+collapsible InfoPanel)].
- Voice mode: [AccountRail | ServerTree (channels/users) | RoomStage (speaking tiles,
  controls: mute/deafen/PTT/VAD, per-user volume flyout) + side text-channel panel].
- Narrow (mobile): single column + drawer navigation; account rail collapses to current avatar.

### 5.2 Chat mode screens (build order = P1)
1. Conversation view: grouped avatars, bubbles (in/out), reply/quote, edits badge (tap =
   edit log — anti-recall data), reactions row, read ticks (if Caps.ReadReceipts), service
   messages, day separators, unread divider, new-messages button, scroll-position restore.
2. Composer: multiline editor, attach (media/files), sticker/emoji picker (static), voice
   note hold-button (when CaptureSource exists), reply/edit banner, bot-keyboard area,
   char/format toolbar (bold/italic/spoiler/code), send.
3. Chat list: avatar+title+excerpt+time, pinned section, folders tabs, unread badges,
   mute icon, search (FTS5 local + server when Caps.Search), archive collapsed group.
4. Account wizard: backend picker (kind grid with logos) → AuthFlow steps → caps summary
   ("this network has no typing indicators") → done (account joins rail).
5. Settings: accounts manager, appearance (theme/dark/AMOLED, fonts, size, bubble radius,
   accent per account), notifications (per-chat; in-app toasts + platform best-effort),
   storage (cache sizes, purge), privacy (ghost-mode matrix per account, vault lock),
   per-backend advanced (proxies for Telegram: SOCKS5/MTProto w/ test button),
   **diagnostics (5.6)**.
6. Info panel: peer profile (avatar, handle, bio, members), shared media grid, notifications
   toggle, block/report actions (where protocol supports).

### 5.3 Voice mode screens (P5)
- Server tree: channels w/ user subtrees, permissions tinting, join on click, current-room
  highlight; drag-to-move user? (Mumble move permissions — later).
- Room stage: tile per speaking user (avatar, name, VU meter), self tile w/ status,
  controls bar (mic toggle, headphones, PTT hold vs VAD toggle, bitrate/quality), per-user
  volume slider, "user entered/left" toasts, text side panel (channel chat), whisper/PM.
- Incoming call (Telegram/Matrix): system-style modal (accept/decline), then room stage
  reused with call controls.

### 5.4 Design system (`internal/ui/kit`)
- Material tokens: color roles (light/dark/AMOLED), type scale (embedded Noto), elevation,
  8dp grid, corner radius tokens (message bubbles use user-configurable radius — AyuGram
  font/appearance parity), motion 120–200ms springs.
- Components: AvatarCluster, Bubble, ReactionPill, TypingDots, PresenceDot, AccountBadge,
  FolderTabs, EmptyState, CapabilityHint (explains hidden features per Caps), Toast,
  ProgressRing (media), VoiceWaveform.
- i18n: `internal/i18n` (en, fa — RTL correctness is a P1 acceptance test), all strings
  keyed; bidi direction per message auto (x/text).
- A11y: semantics labels on all interactive widgets from day one; full screen-reader tier P3.
- Telegram-grade density, AyuGram-grade power affordances, Material visual language:
  information architecture copied only as behavior, never as assets or code.

### 5.5 Notifications (normalized model; adopted from research/15)

```text
Notification
  account, conversation, sender
  kind: message | mention | call | system
  title, body, timestamp, deep_link, priority
  requires_call_ui: bool
```
- Deduplicated against locally generated ones (hash: account + conv + kind + origin id).
- Platform delivery = best-effort adapter (desktop portals where a pure-Go path exists —
  research/12; in-app toasts always). Mobile push = platform contract (FGS/VOIP rules),
  never assumed; document honestly per platform.
- Never assume a desktop polling model survives mobile background execution.

### 5.6 Diagnostics (adopted from research/15)

Settings screen + **redacted export bundle** (support workflow): per-account connection
state, sync cursor + last sync, retry/backoff state, rate-limit state, store health + WAL
size, cache sizes, event-bus counters (4.6), voice stats (jitter/loss/latency), platform
capability state. Redaction strips account identifiers and PII before export. A user
must never need to become a programmer to know whether a backend is connected.

---

## 6. Backend integration guides (pointers + gotchas; evidence in research/)

**Priority gate (per backend, before any adapter code is written — adopted from
research/15):** the backend's research file must answer: protocol inventory, feature
inventory vs Caps, auth matrix, rate-limit model, event/sync model, offline behavior,
media model, encryption model, legal review, test-server strategy, live-verification
strategy, known incompatibilities. research/02–10 already fill this role for the planned
backends; any NEW backend gets a `research/NN-<name>.md` answering these first. No
exceptions — "no implementation merely because a repo exists."

Each core lives in `internal/core/<kind>/` with the same internal layout:
`adapter.go` (Backend impl), `auth.go` (AuthFlow), `events.go` (protocol→domain mapping),
`commands.go` (capability interface impls), `media.go`, `voice.go` (if applicable),
`internal/proto/` (generated/local schemas), `testdata/` (fixtures), `FEATURES.md`,
`DEVIATIONS.md`, `LIVELOG.md` (the conformance 3-doc set — §7).

- **telegram** (research/02): gotd client + contrib (`middleware/floodwait`,
  `middleware/ratelimit`, `storage` for sessions/peers — actual v0.25.0 package layout);
  auth phone→code→2FA; ghost mode = skip read/typing/online calls (AyuGram parity);
  anti-recall = never hard-delete locally; media via gotd uploader/downloader; voice via
  `telegram/calls` (pion tracks); MTProxy/SOCKS wizard; api_id/api_hash from owner (vault).
  Testing ladder: tgtest (in-proc) → **official Test DCs** (3 test servers, reserved phone
  prefixes, code = DC#x5 — wipe-prone, never store real data there) → production.
  Rich surface beyond chat (secret chats, stories, mini apps) lands late and gated;
  secret chats are security-critical, never a checkbox.
- **irc** (research/07): girc; SASL wizard; chathistory backfill (server-dependent Caps);
  service events; nick colors (deterministic hash); no fake features. Ergo docker CI.
- **github** (research/06 — the neutrality probe, P4): go-github REST + githubv4
  (Discussions); **notifications poller (60s+, ETags — 304s don't count against the REST
  bucket)**; reply/reaction; markdown → blocks (goldmark, pure Go); device-flow wizard.
  Object model: repositories=workspaces, issues/PRs/discussions=conversations,
  comments/review-threads=messages — but keep GitHub-native state (labels, assignees,
  milestones, review state, checks) in `backend_extension`, typed content cards in UI.
  GraphQL only where a screen needs deep traversal without REST waterfalls. Per-account
  scheduler; never hammer to fake realtime — **Events API latency is officially 30s–6h,
  retention ~31 days**. No DMs/following-feed: flagged, not faked.
- **matrix** (research/03): mautrix sync + crypto machine persisted in our sqlite; SAS
  verification UX; media via mxc; Dendrite (CI) + Synapse (nightly); coturn for calls tests.
  Modern-client profile: state events, threads, edits, reactions, receipts, device trust,
  room upgrades, spaces — through explicit Caps, not assumptions.
- **mumble** (research/08): our `internal/gumble` fork (cgo subpackages REMOVED; module
  origin = layeh.com/gumble, archived Dec 2022); proto regen from Mumble.proto; CryptState
  UDP; voice = flagship of P5; text = side panel.
- **xmpp** (research/10): **mellium** (decision re-verified in §1; go-xmpp rejected);
  MUC+MAM+SM+carbons; no E2EE v1 (badge it; ADR-007); styling parser → blocks. XEP
  support = individually testable capabilities (profile doc), never one "XMPP support"
  claim. Mellium is a toolkit, not an SDK — we own session/MUC/bookmarks logic (right
  trade: no magic, testable).
- **deltachat** (research/05): go-imap v2 + go-mail + go-crypto; Chat-* headers; SecureJoin
  state machine; IDLE loop; interop-tested against official client on chatmail docker.
  A pure-Go core is NOT DeltaChat-compatible until interop proves it (encryption
  semantics, message-state behavior) — gate accordingly.
- **bale** (research/04): WSS+protobuf port from aiobale knowledge; phone+SMS auth; fixtures
  only; "not E2EE" warning badge; kill criteria.
- **teamspeak** (research/09): build tag `experimental`; port ts3j logic (Apache-2.0,
  attribution); ServerQuery for test admin (never called "TS support"); voice packets w/
  opus; security-level PoW port; legal + protocol conformance spike BEFORE any client work.
- **loopback**: in-proc fake implementing Backend + ALL capability interfaces with script
  files (timed events, error injection) — drives ALL UI development + tests; never ships
  enabled in release builds.

Adding a new backend = research/NN file (priority gate) → copy `internal/core/_template/`
→ write the failing conformance tests FIRST (R2 fixtures or R3 docker) → fill the
capability map (Caps + interfaces, registry-validated) → FEATURES/DEVIATIONS docs →
worklog. No exceptions.

---

## 7. Testing strategy (details: research/13)

- 6-rung ladder: unit → fixture conformance → docker integration → nightly live smoke →
  owner acceptance → loopback UI tests.
- Docker matrix (`tools/testlab/docker-compose.testing.yml`, profiles per backend): ergo
  (IRC), prosody (XMPP), dendrite (Matrix) + coturn, mumble-server (official image:
  mumblevoip/mumble-server), chatmail compose (DC), teamspeak (experimental profile).
  Telegram uses gotd tgtest in-proc + official Test DCs (nightly tier). GitHub/Bale:
  fixtures (+ nightly real for GitHub with owner's PAT).
- **Conformance 3-doc per backend (adopted from research/15):** `FEATURES.md` (per-capability
  status: supported/partial/experimental/server-dependent/unavailable), `DEVIATIONS.md`
  (known deviations from spec/upstream), `LIVELOG.md` (official-server verification log:
  date, account, what was checked). No vague "Telegram supported" badges ever. FEATURES.md
  documents intent; conformance tests assert the code matches; Caps reflects negotiated
  reality (single chain of truth).
- **First tests per backend (before deep library integration):** login/logout, reconnect,
  history pagination, send, edit, delete, reply, thread, reaction, read state, presence,
  media up/down, search, rate-limit handling, duplicate-event handling, outbox retry.
  Then backend-native features.
- **TDD protocol for agents** (enforced in review checklist):
  1. RED: write the test that fails (fixture expected-output, or docker-asserted behavior).
     Commit it (or stage it) BEFORE implementation exists.
  2. GREEN: minimum implementation. No extra features sneaked in.
  3. REFACTOR: clean, then re-run full package tests + lint.
  4. Log in WORKLOG: what was tested, at which rung, with which fixture/server version.
- Fuzz (mandatory, adversarial input is normal): IRC lines+tags, mumble protobuf, matrix
  JSON events, TL blobs, XMPP XML, Bale frames, TS3 packets, GitHub JSON/GraphQL bodies,
  rich-text parser, URL/deep-link parser, media metadata parser, storage page/recovery
  parser.
- Perf gates (bench, CI smoke): opus 20ms-frame encode < 5ms (desktop); 10k-message room
  scroll at 60fps (gio profiling); store: 1k msg insert < 1s, FTS search < 50ms @ 100k msgs,
  **1M-message DB open < 3s, 10 simultaneous accounts stable / 100-account stress smoke,
  1000 queued outbox ops, 100 concurrent media downloads, voice jitter under 5% loss,
  reconnect storm (10 cores flapping)**; cold start < 2s; warm start < 1s; idle RAM <
  300MB (desktop); binary < 40MB (with embedded fonts).
- CI: lint (golangci-lint), `make purego` (layered gates below), unit + loopback always;
  docker profile per changed core (path-filtered); nightly R4.
- **Pure-Go gate, layered (v3 — recipe proven in research/16):**
  (a) core layer: `CGO_ENABLED=0 go build` of all non-GUI packages for the full matrix
  {windows,linux,darwin,android,ios} x {amd64,arm64} + js/wasm;
  (b) full app: `CGO_ENABLED=0` builds for windows amd64+arm64 + js/wasm;
  (c) source scan: zero CgoFiles in OUR repo's packages (gio's cgo lives in its own module;
  the gumble fork is stripped);
  (d) full builds: linux desktop (cgo: full dev-header list in §8),
  Android + iOS via gogio (NDK/Xcode) — CI runners with the toolchains.
  On small machines: `-p 1` + `GOMEMLIMIT=900MiB GOGC=30` for the gotd tg package.

---

## 8. Build, run, release (commands — keep them true or fix this file)

```bash
# Prereqs: Go (latest stable; 1.27.1 verified 2026-09-07), docker for integration tests.
# Linux desktop dev builds additionally need (gio cgo glue; ONE-TIME apt install; exact
# list verified 2026-09-07 via pkg-config probes — research/16 round 4): a C compiler
# (build-essential OR clang) + pkg-config + libwayland-dev libxkbcommon-dev
# libxkbcommon-x11-dev libx11-dev libx11-xcb-dev libxcursor-dev libxfixes-dev
# libegl1-mesa-dev   (libvulkan NOT needed at build time — dlopen'd at runtime).
# Windows and Web (WASM) builds need NOTHING but Go — zero compilers, verified.
# Small-RAM machines: export GOMEMLIMIT=900MiB GOGC=30 and build with -p 1 (tg package).
make run            # desktop debug build
make lint           # golangci-lint
make test           # unit + loopback (no docker)
make test-int       # boots needed docker profiles + runs R3 (integration tag)
make purego         # layered purity gates (§7) — MUST stay green
make bench          # perf gates
make fuzz           # 30s/library corpus fuzz

make build-desktop  # linux/windows/mac amd64+arm64 (linux/mac via cgo glue; win pure)
make build-android  # gogio -target android (needs Android SDK/NDK + JDK, build-time only)
make build-ios      # gogio -target ios (macOS + Xcode, build-time only)
make build-web      # GOOS=js GOARCH=wasm -> web/unichat.wasm + wasm_exec.js + index.html
make serve-web      # local static server for the wasm bundle
make testlab-up b=irc   # manual: docker compose --profile irc up -d
```

- **Build-quality verification matrix (a compile is NOT a port — adopted from research/15):**
  per platform target, the CI smoke suite verifies: app starts → shell renders → input
  works → loopback network round-trip → store opens + persists across restart → media
  decode smoke (where supported) → notifications (where supported) → deep links (where
  supported) → background/resume + permission-denial handling (mobile). WASM is a browser
  target, not "desktop Go in a browser": secure-context, storage-quota (OPFS), and
  getUserMedia rules apply (research/11).
- Releases: semver tags, CHANGELOG.md (keepachangelog format), signed tags; artifacts via
  CI matrix; mobile bundles from gogio; wasm zipped with index.html.
- Version policy: Gio pinned exact version in go.mod; upgrade = dedicated chore PR with
  the full test suite + a smoke run per platform; never mixed with feature work.

---

## 9. File structure

```
unichat/
├── AGENTS.md                  <- you are here (update when reality changes)
├── WORKLOG.md                 <- append-only agent log (protocol in §14)
├── CHANGELOG.md
├── go.mod / go.sum            <- module: unichat (rename to hosted path when we host)
├── Makefile
├── cmd/
│   ├── unichat/               # desktop/mobile entry (gio app)
│   └── unichat-web/           # wasm entry
├── internal/
│   ├── domain/                # protocol-agnostic model (Caps, Event, Message, AuthFlow,
│   │                          #   capability interfaces 4.4)
│   ├── core/
│   │   ├── _template/         # new-backend skeleton (+ FEATURES/DEVIATIONS templates)
│   │   ├── loopback/          # fake backend (scripts + error injection)
│   │   ├── telegram/ irc/ github/ matrix/ mumble/ xmpp/ deltachat/ bale/ teamspeak/
│   │   │                      # each: adapter.go auth.go events.go commands.go media.go
│   │   │                      #        voice.go proto/ testdata/ FEATURES.md DEVIATIONS.md
│   │   │                      #        LIVELOG.md
│   │   └── registry.go        # kind -> constructor + Caps-vs-interfaces validation
│   ├── gumble/                # vendored+forked mumble lib (MPL-2.0, NOTICE)
│   ├── state/                 # app actor: bus, intents, view models, outbox
│   ├── ui/
│   │   ├── kit/               # Material components + tokens + theme
│   │   ├── chat/              # chat mode widgets/screens
│   │   ├── voice/             # voice mode widgets/screens
│   │   ├── settings/ wizard/  # screens (incl. diagnostics + redacted export)
│   │   └── app.go             # shell: rails, modes, routing
│   ├── infra/
│   │   ├── store/             # sqlite + migrations + FTS5 + meta (+ wasm/OPFS adapter P9)
│   │   ├── blobs/             # media cache (sha256 LRU)
│   │   ├── vault/             # age + keyring, auto-lock
│   │   ├── audio/             # codec(opus) sources/sinks mixer dsp
│   │   ├── audio/drivers/     # build-tagged per-platform (wasm, android, wasapi, ...)
│   │   ├── net/               # dialers, proxies, backoff, circuitbreaker
│   │   └── i18n/  fonts/  log/
│   └── version/
├── tools/
│   ├── purego/                # check.sh — the layered purity gate (recipe: research/16)
│   ├── testlab/               # docker-compose.testing.yml + configs + wait scripts
│   ├── fixtures/              # capture/redact tooling for testdata
│   └── webserve/              # dev static server for wasm
├── testdata/                  # R2 fixtures per core (redacted) + fuzz corpora
├── docs/
│   ├── adr/                   # ADR-0001..NNN (decisions; template inside)
│   ├── building.md            # per-platform build matrix (kept current!)
│   └── release-checklist.md
├── research/                  # THIS evidence base (00-16 + README)
├── .github/workflows/         # ci.yml, nightly.yml, release.yml
└── THIRD-PARTY-NOTICES.md     # licenses of deps + vendored fork + attribution
```

Rules: `internal/` only (no public API yet); no package cycles (enforced by a lint test);
one `go.mod` (no workspace gymnastics); fixtures are test data (redacted); docs are code
(stale doc = bug). (Rejected alternative from research/15: `cmd/pkg/backend/media`
layout — `internal/` enforces visibility at the compiler level, which is the whole point.)

## 10. Engineering standards ("senior stuff" — enforced in review)

**Code style**
- Go latest stable (1.27.1 as of 2026-09-07; floor = latest stable at time of work).
  gofumpt formatting; imports gci-grouped (std / ext / local).
- Package names singular, short, lowercase. No `util`, `common`, `misc`, `helpers`.
- Comments explain WHY, not WHAT. Exported symbols documented (godoc style).
- Errors: wrap with `%w` + context at boundaries (`fmt.Errorf("telegram: fetch dialogs: %w", err)`).
  Typed sentinel errors in domain (`domain.ErrAuthExpired`, `ErrRateLimited{RetryAfter}`)
  drawn from the **error envelope classes** (adopted from research/15): AuthRequired /
  AuthInvalid / PermissionDenied / NotFound / RateLimited / TemporaryNetwork /
  ServerUnavailable / ProtocolError / Unsupported / MediaTooLarge / StorageCorrupt /
  CryptoError / PlatformPermissionDenied. Cores translate protocol errors into domain
  errors; UI never sees raw protocol strings; adapters preserve originals as diagnostic
  metadata. No panics outside package init; no `log.Fatal` in libraries.
- Contexts: first param; never store in structs (except long-running actors with documented
  lifecycle); every network call cancellable; goroutines have a written shutdown path
  (`Close(ctx)` idempotent, errgroup/`goleak`-style tests where practical).
- Concurrency: cores = single actor goroutine each (commands serialized via chan), state =
  app actor, store = single writer. Shared mutable state needs a justification comment.
  Race detector on in CI.
- Logging: `log/slog` child loggers per core (`slog.With("backend","telegram","acct",id)`),
  levels via settings, NEVER log message content, tokens, phone numbers (PII rule);
  debug dumps behind build tag.
- Time: UTC in store (`sent_at` server-time where protocol defines it), local only at
  render. **Explicit clock injection** in time-sensitive code so tests control time.
- IDs: internal uint64 DB ids + `Origin` strings; never reuse protocol ids as PKs.
- JSON: only at edges (fixtures, settings, blocks); tagged structs, no maps-in-maps.

**Dependency policy**
- New module deps require: pure Go (layered purego gates pass — §7), active-ish maintenance,
  license in {MIT, BSD, Apache-2.0, MPL-2.0} (GPL/AGPL: reference-only, NEVER link — see rule
  0.6), and a line in THIRD-PARTY-NOTICES.md. Track in go.sum; govulncheck in CI; `go mod tidy`
  before every PR.
- Vendored code (`internal/gumble`) pinned + attributed; patch series documented in-tree.
- Pinned core versions at research time (§2); upgrades = dedicated chore PRs.

**Decisions & docs**
- Any non-obvious choice => `docs/adr/NNN-title.md` (context / options / decision /
  consequences / rejected alternatives). Current pending: ADR-007 XMPP E2EE strategy.
- `docs/building.md` holds the real per-platform build steps (gogio/Xcode/NDK/pkg-config
  versions); update the same PR that changes builds. Stale doc = broken build = bug.
- CHANGELOG.md updated in every merged PR (user-visible lines only).

**Review checklist (agent self-review before finishing any task)**
- [ ] Failing test written FIRST (for core/domain/store/audio changes)?
- [ ] `make lint test purego` all green?
- [ ] New deps vetted (license/maintenance/pure-Go) + NOTICES updated?
- [ ] No protocol strings/PII in logs; no secrets in repo?
- [ ] Caps updated if a feature became (un)available? Registry validation passes?
      UI hides it properly? FEATURES.md still true?
- [ ] WORKLOG.md appended? Checklist below ticked? ADR written if decision made?
- [ ] Docs (building/AGENTS) still true?

**Security posture**
- Vault: age-encrypted, auto-lock after 15min idle, key in OS keyring when available
  (macOS via /usr/bin/security, Linux via SecretService/dbus, Windows via wincred —
  all pure-Go paths, research/12).
- Untrusted input: ALL protocol bytes are hostile — fuzz targets per parser (§7); no
  allocation-unbounded reads (limits + errors); images decoded with size caps; recursion
  and decompression limits; never trust remote HTML/markdown/filenames/URI schemes —
  render rich text only from our constrained block model.
- Updates: user-triggered check only (no auto-ping). Advisory monitoring = manual.
- Memory: can't guarantee zeroization in Go — document honestly; secrets kept minimal
  (session keys, not message DB).
- RE-tier backends (TS3, Bale): experimental flags, clear "unofficial client" disclosures.

**Performance budgets (CI-enforced benches; regressions block merge)**
- 60fps scrolling in 10k-message room; frame budget 16ms (measure with gio profiler).
- Store: 1k msg batch insert < 1s; FTS search < 50ms @ 100k msgs.
- Cold start to chat list < 2s; idle RAM < 300MB (desktop); binary < 40MB.
- Audio: opus encode 20ms frame < 5ms; mic→net→speaker loop < 150ms desktop.
- Extended baseline suite (§7) recorded per release; trend dashboard in CI artifacts.

---

## 11. Risk register (top risks, with mitigations)

| # | Risk | L | I | Mitigation |
|---|---|---|---|---|
| 1 | Mic capture has no pure-Go lib (macOS/Linux esp.) | H | H | Platform capture drivers + WASM-first; purego dlopen fallback behind ADR (desktop only); honest capability matrix |
| 2 | Scope explosion (owner enthusiasm) | H | H | Phased gates; backlog parking lot; owner reviews phase demos |
| 3 | Gio pre-1.0 breakage (minor = breaking) | M | M | Pinned version; upgrade chores; kit isolates Gio API surface |
| 4 | TS3/Bale wire drift (unofficial protocols) | H | M | Kill criteria (research/04,09); experimental flags; tolerant parsers |
| 5 | gotd maintenance wind-down | L | H | Fork policy (MIT); gotdgen self-serve schema regen; vendor if needed |
| 6 | mautrix-go API churn | M | M | Pin minors; integration tests catch breakage; upgrade chores |
| 7 | OMEMO absence (XMPP E2EE) | H | M | Ship flagged without E2EE v1; ADR-007; revisit w/ crypto review |
| 8 | WASM platform gaps (IME, perf, storage) | M | M | P9 dedicated hardening phase; browser storage adapter (OPFS via JS interop) |
| 9 | Agent-built codebase quality drift | M | H | TDD ladder + lint gates + review checklist + worklog discipline (this file) |
| 10 | Legal heat on RE backends | L | M | Experimental opt-in flags; no trademark use; kill criteria; archive on threat |
| 11 | Caps claims drift out of sync with implemented interfaces (capability lying) | M | M | Registry startup validation (§4.4) + conformance tests + FEATURES.md review item |
| 12 | Event-bus overload during backfill storms (slow ingestion, dropped msgs) | M | H | §4.6 guarantees: bounded channels, coalescing, never-drop policy for messages, per-core counters in diagnostics |
| 13 | Gio cgo OS-glue drift (pkg-config/EGL/Metal/NDK changes break builds) — discovered v3 | M | M | Pin gio version; build-quality matrix (§8) catches per-platform breakage in CI; watch upstream pure-Go progress (Windows+WASM already pure); worst case: fork + patch glue |

---

## 12. Step-by-step plan (phases with gates — the build order)

> Principle: every phase ends with something the owner can RUN and JUDGE.
> A phase gate is a demo + green CI + updated checklist + worklog.
> Order rationale (§1 row 2): three probes before the pile-on — Telegram (richest chat
> model), IRC (honest degradation), GitHub (backend-neutrality) — then voice (product
> pillar #2), then the heavy/own-core backends.

**P0 — Foundation (repo bootstrap)**
- go.mod, Makefile, CI skeleton (lint/test/purego), dir tree per §9, ADR-0001 (Gio),
  ADR-0002 (SQLite single-writer), THIRD-PARTY-NOTICES, i18n scaffold, fonts embedded.
- `tools/purego/check.sh` (layered gates §7 — the recipe is proven: research/16's
  scripts/verify_matrix3.sh).
- Gate: `make lint test purego` green on empty app skeleton (hello-gio window).

**P1 — GUI shell + Loopback (chat mode)**
- domain model + Caps + Event + capability interfaces; Loopback backend w/ scripted chats;
  state actor + store (migrations 001-00N) + FTS; AccountRail, ChatList, Conversation,
  Composer, wizard, settings, theming (Material tokens), i18n(en,fa)+RTL test, a11y labels.
- Gate: 3 scripted accounts, 10k-msg loopback room scrolls 60fps; owner demo #1.

**P1.5 — Android (gogio) + desktop packaging**
- gogio APK, adaptive layouts, docs/building.md filled with real matrix.
- Gate: app runs on owner's Android + all 3 desktops.

**P2 — Telegram core (chat)**
- gotd adapter: auth wizard, sync, send/edit/delete/react/read/typing(+ghost opts),
  media pipeline, folders, search (server+FTS), sponsored filter, multi-account,
  MTProxy/SOCKS; tgtest CI + fixtures; anti-recall local retention + edit log UI.
- Gate: owner daily-drives it vs real account for 3 days; tgtest+R3 green. (Demo #2.)

**P3 — IRC core (the degradation probe)**
- girc adapter + SASL wizard + chathistory backfill + service msgs + nick colors; Ergo
  docker CI; fixtures. Capability flags prove the UI hides what IRC lacks.
- Gate: owner idles in #unichat-test on test network; R3 green.

**P4 — GitHub core (the neutrality probe)**
- Device-flow auth wizard; notifications poller (60s+, ETags) → inbox; issues/PRs/
  discussions as conversations; comments + review threads as messages; reactions;
  markdown→blocks; profiles/search; rate-limit scheduler; typed GitHub cards.
- Gate: owner reads + replies in a real issue thread from the app; fixtures + nightly
  PAT smoke green; domain model unchanged by a non-chat backend (no architecture lies).

**P5 — Voice mode v1 + Mumble + Telegram calls + audio service**
- internal/gumble fork; audio service (opus codec, mixer, jitter, drivers: wasm capture +
  desktop playback); voice-mode UI; Telegram 1:1 + group calls via gotd; mumble-server CI.
- Gates: S1-S5 spikes (research/11) passed; audible TG call + mumble channel talk.

**P6 — Matrix core** — mautrix sync + E2EE (goolm) + verification UX + media +
reactions/edits/threads; Dendrite CI, Synapse nightly.
- Gate: encrypted room round-trips with Element user (owner acceptance).
**P7 — XMPP core (+ MAM/SM/carbons)** — mellium; Prosody CI. Gate: MUC+backfill+typing
demo (local + public server).
**P8 — DeltaChat core (chat-only + Autocrypt; SecureJoin stretch)** — chatmail CI; interop
tests vs official client. Gate: unencrypted + autocrypt round-trip.
**P9 — Web/WASM hardening** — browser storage (OPFS), notifications, IME, perf. Gate: 30min
browser session demo incl. Telegram.
**P10 — Experimental tier: Bale core (a) then TeamSpeak core (b)** — flagged, kill criteria
armed. Gate per research/04,09.

Ongoing every phase: perf gates, a11y, i18n, security review, docs, release checklist run.

---

## 13. Task checklist (update after EVERY session; [ ] todo, [~] in progress, [x] done,
[X] done+verified by owner; strike ~~~~ killed/deferred with reason)

### P0 Foundation
- [x] Research package + AGENTS.md v1 — verified against live sources 2026-09-07
- [x] AGENTS.md v2 merge — supplied analysis + second-model draft reconciled, conflicts
      resolved (§1), new claims verified (TG test DCs, GH events latency, go-xmpp status,
      ts3j release, mumble docker image) — 2026-09-07
- [x] **AGENTS.md v3 — third verification pass (2026-09-07): EXECUTED pure-Go build matrix
      (research/16 — Go 1.27.1, all 20 deps resolved+compiled; core layer CGO_ENABLED=0 on
      the full platform matrix; full app pure on windows+js); Gio cgo reality corrected
      (§0.1 Tier C); keyring darwin mechanism corrected; gotd contrib package layout
      corrected; pion v4 + go-github v90 current; tg-compile memory recipe documented.**
- [ ] Repo init: go.mod (module unichat), Makefile, .github/workflows/ci.yml
- [ ] purego check script (tools/purego/check.sh — layered gates per §7; recipe proven in
      scripts/verify_matrix3.sh + research/16) + make target
- [ ] ADR-0001 (Gio), ADR-0002 (sqlite single-writer), ADR-0003 (loopback-first UI dev),
      ADR-0004 (capability-interface hybrid + Caps registry validation)
- [ ] Fonts + i18n scaffold (en/fa), THIRD-PARTY-NOTICES.md, docs/adr template
- [ ] Hello-window app runs on linux (then win/mac in CI)

### P1 GUI shell + loopback
- [ ] domain: Caps, Event set, Message blocks, capability interfaces, errors (+ table tests)
- [ ] registry: Caps-vs-interfaces validation + loopback-implements-everything test
- [ ] store: migrations 001..003, FTS5 smoke, single-writer funnel (+ tests)
- [ ] loopback backend: script format, event scheduler, error injection
- [ ] state actor: bus coalescing + backpressure policy (§4.6), intents, snapshots, outbox
      (+ scripted tests incl. duplicate-event and storm cases)
- [ ] ui/kit: tokens, theme, AvatarCluster/Bubble/ReactionPill/Toast...
- [ ] chat screens: ChatList/Conversation/Composer/wizard/settings
- [ ] notification dedup (§5.5) in NotifCenter
- [ ] i18n fa + RTL rendering acceptance test
- [ ] perf: 10k-msg loopback room 60fps bench in CI
- [ ] Owner demo #1 passed

### P1.5 Android
- [ ] gogio APK builds in CI; adaptive narrow layouts; building.md matrix filled

### P2 Telegram
- [ ] tgtest harness in CI + 3 recorded-layer fixtures
- [ ] auth wizard (phone/code/2FA) + session in vault + api_id/hash config UX
- [ ] sync engine: dialogs/users/updates → store (+ dedupe tests)
- [ ] send/edit/delete/react/typing/read(+ghost opts) w/ delivery states
- [ ] media: up/down w/ progress, thumbnails, blob LRU
- [ ] folders, pinned, archive, sponsored filter, search (FTS+server)
- [ ] anti-recall retention + edit-log viewer
- [ ] MTProxy/SOCKS5 proxy wizard + auto-rotate
- [ ] multi-account (3 accounts simultaneous) + account rail wiring
- [ ] Test-DC live smoke (nightly, throwaway accounts only)
- [ ] 3-day owner daily-drive sign-off

### P3 IRC
- [ ] ergo docker profile + conformance corpus (fuzzed parser)
- [ ] SASL/external wizard, caps negotiation, ISUPPORT quirks table
- [ ] chathistory backfill + local fallback flags
- [ ] nick colors, ignore list, service message rendering

### P4 GitHub
- [ ] device-flow auth wizard + identity validation
- [ ] notifications poller (60s+, ETags, 304 accounting) → inbox conversations
- [ ] issue/PR/discussion thread loader (REST) + review-thread mapping
- [ ] reply + reactions (issues/PRs/discussions)
- [ ] markdown → blocks (goldmark) + typed GitHub content cards
- [ ] rate-limit scheduler + per-account polling budgets
- [ ] profiles/search screens (GraphQL where justified)
- [ ] recorded fixtures + nightly PAT smoke
- [ ] owner acceptance: read + reply in real issue thread

### P5 Voice v1
- [ ] S1-S5 audio spikes (research/11) — conformance + realtime budgets
- [ ] internal/gumble fork: proto regen, cgo subpackages deleted, NOTICE
- [ ] audio service: codec/mixer/jitter/drivers (wasm capture first)
- [ ] voice-mode UI (tree/stage/controls/side text)
- [ ] Telegram 1:1 + group calls (gotd calls) incl. incoming-call modal
- [ ] mumble-server docker CI: join/talk/text assertions
- [ ] per-user volume, PTT/VAD, mute/deafen polish

### P6 Matrix
- [ ] dendrite CI + synapse nightly + registration helpers
- [ ] sync loop + room state + timeline backfill
- [ ] E2EE: goolm machine persisted, SAS verification UX, key backup
- [ ] media (mxc) + reactions/edits/redactions/threads flags
- [ ] encrypted round-trip with Element (owner acceptance)

### P7 XMPP
- [ ] XEP profile doc (research/10 table) as FEATURES.md
- [ ] mellium session + roster + MUC; MAM backfill w/ sync cursors; SM resume; carbons
- [ ] auth wizard (JID/pass/custom host/cert); styling → blocks
- [ ] "not E2EE" badge + ADR-007 decision recorded
- [ ] Prosody CI + public-server nightly

### P8 DeltaChat
- [ ] go-imap v2 IDLE loop + go-mail SMTP + go-crypto Autocrypt
- [ ] Chat-* header model + SecureJoin state machine
- [ ] chatmail docker interop vs official client (round-trip gate)

### P9 WASM hardening
- [ ] OPFS storage adapter, notifications, IME input, perf pass
- [ ] 30-min browser session demo incl. Telegram

### P10 Experimental tier
- [ ] Bale: protocol capture + Go port + fixtures + kill criteria armed (research/04)
- [ ] TeamSpeak: legal/protocol spike then ts3j-logic port (research/09); experimental flag

### Cross-cutting (always)
- [ ] govulncheck clean; NOTICES current; CHANGELOG per PR
- [ ] a11y pass each phase; perf gates green; i18n strings complete
- [ ] diagnostics screen + redacted export (§5.6)
- [ ] release v0.1.0 checklist run (after P2)

**Backlog / parking lot (owner ideas awaiting phase):** stories viewer, translator
providers, streamer mode, local-premium cosmetics, secret chats (TG E2EE), Matrix group
calls (MatrixRTC/LiveKit), whisper (TS3), multi-device sync (DC Iroh-style is out of
policy scope).

---

## 14. Agent operating protocol (read this if you are the next session)

**Session start (context recovery) — the first 60 minutes:**
1. Read this file fully (it IS the context). Then `git log --oneline -20` + the last 3
   entries of `WORKLOG.md`.
2. Confirm toolchain: `go version` (latest stable; 1.27.1 as of writing). If the machine
   has < 4 GB RAM: `export GOMEMLIMIT=900MiB GOGC=30`, build with `-p 1` (§8).
3. Run `make lint test purego` FIRST to confirm the tree is healthy before changing
   anything. If broken: fix or revert before new work (broken main = highest priority).
4. Section 13 checklist = current truth. Section 12 = what's next per the gate order.
   Take the topmost unticked item of the current phase.
5. Write the failing test first (§7 TDD protocol), implement minimally, re-run the gates.
6. Tick the checklist item, append a WORKLOG entry, commit. If anything in this file
   proved wrong or stale: fix the file IN THE SAME COMMIT (supersede, never erase).

**Working rules:**
- One phase at a time; within a phase, take the topmost unticked checklist item.
- TDD (section 7) for core/domain/store/audio; loopback scripts for UI.
- Small, complete units of work: each unit ends with green lint+test+purego, a checklist
  tick, and a WORKLOG entry. Prefer 10 small sessions over 1 giant one.
- If blocked twice on the same approach: stop, write the blocker in WORKLOG ("BLOCKED:",
  what you tried, what you need), pick the next task, and let the owner read it async.
- Decisions that deviate from this file => write an ADR + update this file in the same PR.
  Never silently rewrite architectural decisions; supersede, don't erase.
- Owner questions: answer in product terms (what they'll see/do), never dump code talk.
  Never ask the owner to choose between technical options — that's our job; present the
  outcome instead ("calls will arrive a week later than Mumble support because X").
- Update the checklist as you work ([~] → [x] → owner later marks [X] after acceptance).
- Never delete research/ or WORKLOG history; supersede, don't erase.

**Source freshness & conflict discipline (adopted from research/15):**
- Re-verify any claim older than ~6 months before leaning on it (maintenance drifts).
- Version-sensitive claim? Read the primary source at implementation time (RTFM list below).
- When sources conflict: prefer executable compatibility tests + the authoritative protocol
  specification, then document the discrepancy in the backend's DEVIATIONS.md. Never copy a
  conclusion merely because it appears in a file — including AGENTS.md.
- **The strongest verification is executable**: research/16 turned two wrong doc-level
  claims into build facts by compiling everything. When a claim can be tested by building
  or running code, do that instead of trusting prose.
- When a research/15 (supplied) claim disagrees with research/00–14 (verified), the
  verified base wins until new evidence arrives (§1 provenance rule).

**RTFM links (when uncertain, READ THE PRIMARY SOURCE before guessing):**
- Go std + Gio: https://gioui.org/doc (incl. install page: platform/cgo reality),
  https://pkg.go.dev/gioui.org
- gotd: https://gotd.dev/docs (auth, updates, calls, WASM pages) + repo ARCHITECTURE.md
- Telegram protocol: https://core.telegram.org/api (auth page documents Test DCs;
  end-to-end; calls; obtaining api_id)
- Matrix: https://spec.matrix.org (client-server) + mautrix docs https://docs.mau.fi
- IRC: https://modern.ircdocs.horse + https://ircv3.net/specs (chathistory!)
- XMPP: https://xmpp.org/extensions (0045 MUC, 0313 MAM, 0198 SM) + https://mellium.im
- Mumble: mumble repo `docs/dev/network-protocol` + `src/Mumble.proto`
- DeltaChat: https://securejoin.rtfd.io + chatmail/core README
- GitHub API: https://docs.github.com/en/rest + /graphql (events page carries the
  realtime-latency warning; best-practices page carries the polling guidance)
- TS3: ts3j + TS3AudioBot sources (reference dir) — and research/09's cautions
- Bale: aiobale source + docs.bale.ai (bot API)

**Glossary:** core (per-backend adapter) / account (one identity on one backend) /
conversation (chat/room/thread) / rung (testing ladder level) / ghost mode (AyuGram:
suppress read/typing/online) / anti-recall (keep deleted msgs locally) / caps (feature
flags per backend) / loopback (in-proc fake backend) / vault (age-encrypted secret store) /
owner (the human product owner; non-programmer) / ADR (docs/adr decision record) /
experimental flag (build/runtime opt-in for RE-tier backends) / capability interface
(§4.4 optional per-protocol feature interface) / probe (P2–P4: backends chosen early to
prove model expressiveness, degradation honesty, and backend-neutrality) / OS-glue cgo
(gio's platform rendering shims — Tier C of the Pure-Go Policy, §0.1).

---

## 15. Current status (keep accurate — this is "where you left off")

- Date: 2026-09-07. **Session "restore the build" completed** (see WORKLOG.md
  for the full entry): the existing `go/` engine+cores+bridge codebase (the
  pre-AGENTS.md "pure Go core" that was stripped of its build system) now
  builds, tests, and its FFI artifacts are smoke-verified end-to-end.
  go.mod/go.sum restored against current versions (gotd v0.161.0, mautrix
  v0.30.0, pion v4 line, protobuf v1.36.12); `-tags goolm` is mandatory
  (pure-Go Olm); two API-skew fixes (pion stun v4, gotd AI-tone); the
  js/wasm target builds for the first time ever (new `go/wrtc` compat shim +
  per-core js splits); a real wasm deadlock was found and fixed
  (bridgeCall is now Promise-based — see WORKLOG); test suite added
  (utils/cores/bridge; caught the FLOOD_WAIT→auth miscategorization bug);
  C and Node FFI smoke suites PASS against the real artifacts; Makefile,
  build.sh, CI (native+race+matrix+wasm+smokes), README, and a headless
  CLI host (`go/cmd/cli`) added. **The Gio-GUI rewrite in this plan has NOT
  started** — the verified, working code is the bridge/cores architecture
  under `go/`, which this plan supersedes but does not yet replace.
- Phase: the P0 items of THIS plan remain (repo hygiene is now done via the
  restored code's own tooling; "Hello-window app" i.e. the Gio shell is still
  the first GUI milestone). Treat `go/` as the working engine core a future
  GUI wraps.
- Next session's first task: pick the frontend path — (a) start the Gio GUI
  (P1, wrapping or replacing `go/`), or (b) build a web host on the now
  verified `dist/uniclient.wasm`. Then the P0 checklist remainder.
- Owner actions pending (non-blocking, needed by P2): obtain Telegram
  api_id/api_hash (core.telegram.org/api/obtaining_api_id); decide project
  name (working title UniChat); confirm MIT as the project license (rule
  0.11); optionally reserve a git host + module path; optionally create a
  GitHub PAT (fine-grained, notifications+issues scope) for P4 nightly
  smoke.
- Known open decisions: ADR-007 (XMPP E2EE strategy), project name/module
  path, whether iOS ships in v0.1 (P5 dependency), translator provider
  choice (P3, owner preference).
- Assumptions made in this plan (owner granted autonomy; revisit if wrong):
  MVP order Telegram→IRC→GitHub (§1 row 2 rationale); voice anchored on Mumble+Telegram
  at P5; GitHub scoped to inbox+threads; TS3/Bale experimental last; English as dev
  language with fa UI strings included from P1 (RTL acceptance test); **Pure-Go Policy
  v3 tiering (§0.1) — app code 100% pure Go everywhere, full app pure on Windows+WASM,
  Gio OS-glue cgo accepted as platform contract on Linux/macOS/iOS/Android because every
  alternative is worse and it preserves the zero-runtime-dependency guarantee. If the
  owner rejects Tier C outright, the project has no viable GUI toolkit — escalate before
  building anything.**
- Ratings: 8.2/10 supplied feasibility (research/15) vs **7.5/10 conservative gate**
  (research/00). The gate number is the one that matters.

---

## 16. What not to do (the anti-pattern list — each line is a past project's tombstone)

- No god `UnifiedMessage` struct carrying every backend's fields — Origin + blocks +
  backend_extension carry the differences.
- No Telegram-as-canonical-protocol (the domain model is backend-neutral or it's wrong).
- No voice before the platform audio boundary is tested (S1–S5 spikes first).
- No ffmpeg/Qt/GTK/Electron/node/python/java escape hatches (§0; ADR-gated exceptions only).
- No network or protocol logic in widgets; no protocol strings in the UI.
- No mobile-is-shrunken-desktop; no wasm-is-native assumptions.
- No GitHub events treated as realtime (official: 30s–6h latency; poll gently).
- No "Mumble done because gumble connects" / "TS done because ServerQuery works" /
  "Matrix E2EE done because a happy path decrypts" / "TG secret chats done without
  forward-secrecy + interop tests".
- No production code before tests; no races fixed with sleeps; no flaky tests hidden with
  retries; no debug builds benchmarked as performance data.
- No silent architecture rewrites: ADR + this-file update in the same PR or it didn't happen.
- No new cgo in application code — cgo exists only in Gio's platform glue and optional
  ADR'd desktop escape hatches (off by default). Our repo stays C-free (§0.1).
- No doc-level "pure Go" claims without a build to back them (research/16 + its round-4
  re-run are the bar).

<!-- end of AGENTS.md v3.1 — maintain it like production code -->
