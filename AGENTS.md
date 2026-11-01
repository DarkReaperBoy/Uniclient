# AGENTS.md — Uniclient

> **AUTONOMOUS EXECUTION MANDATE — read first.**
> 1. The owner is **not a programmer** and only ever says "continue" (or reports a live-test
>    result / a new direction). Never ask technical, architectural, or confirmation
>    questions, and never wait for a yes — decide, log the call in WORKLOG, proceed. The
>    only permitted asks are the GitHub token and owner-only rungs (§11). **Language:**
>    reply in English only. Owner input in another language (e.g. Chinese) is an
>    INSTRUCTION — interpret and execute it, still answering in English.
> 2. **"continue" = §0 Boot, then the atomic loop (§3) back-to-back** — chain cycles
>    until context grows heavy (~75%), rewrite STATE, push, yield cleanly.
> 3. A finished front, an empty open-items list, a green release — none of that is a
>    stop. Work endlessly: take the next item or open the next front.
> 4. **An owner redirect overrides every standing plan instantly:** drop the old plan,
>    record the redirect in WORKLOG, execute the new instruction completely.

Uniclient is one pure-Go, cross-platform (PC / mobile / web), multi-backend messenger:
one frontend over many chat and voice backends — Telegram, Matrix, IRC, GitHub, XMPP,
Delta Chat, Bale, TeamSpeak, Mumble — each added and switched as easily as an account.

**Direction (owner, 2026-11-01):** the old GUI (AyuGram-flavored) was **removed
entirely** — it was not 1:1 with AyuGram Desktop and is being **rebuilt from scratch**
with **Telegram Desktop / Telegram Web / Telegram Android as the design references**,
on **Gio** (§6). Until the owner orders the build, the shipped binary is the headless
engine host. The cores and the engine are the product.

This file is **law + reference only** — history and session state live in WORKLOG.md,
never here. If the code contradicts anything here, the code wins: fix this file in the
same commit. Hard ceiling ~330 lines (raised 2026-11-01 for the tests + GUI-rebuild +
product-surface laws).

## 0. Boot — every session, in order

1. **Sync:** `git pull --rebase origin main`. The VM can die any second — only pushed
   work exists. Missing state files → create them (§8).
2. **Auth:** the GitHub token comes from env (`GH_TOKEN`) or the owner, out-of-band. It
   NEVER lands in any file, log, commit, remote URL, or doc. Never force-push `main`.
3. **Load state:** WORKLOG.md — STATE block, newest entry, open items. The only state
   file there is.
4. **Pick the next item, in order:** (1) owner-reported (enters open items on top);
   (2) red gate — failing §7 tier or broken build, fix before everything; (3) topmost
   open item (severity order, §1.10); (4) the current front.
5. Work it through the atomic loop (§3). The only clean end to a turn: gate green (§9),
   STATE rewritten, committed, pushed — then yield.

## 1. Owner requirements (NON-NEGOTIABLE — wins over everything)

1. **Pure Go, 100%.** No Node/Electron/Flutter/Python/JS/HTML/webview in product code.
   Exceptions: CI-generated `gh-pages` files, test tooling (`scripts/web-test/`-class
   Puppeteer/Xvfb — never shipped/linked/imported). Repo stats stay Go.
2. **Platforms:** Linux + Android first-class; Windows second-class but fully
   supported. **macOS/iOS BANNED** — no targets, no CI, no docs.
3. **One binary per platform**, flag-based modes; headless is a flag; a browser tab is
   never "the app".
4. **The web target is WASM** from the same code, deployed to the orphan `gh-pages`
   branch → `https://darkreaperboy.github.io/Uniclient/` (when the rebuilt GUI ships).
   `main` never contains JS/HTML. Until then: a js/wasm compile check keeps the target
   honest, no artifact.
5. **CI/CD on release tags (`v*`) + manual dispatch only.** Never per-push.
6. **Release binaries small:** `-trimpath -ldflags "-s -w"`, then UPX `--best --lzma`
   (skip `.wasm`/`.apk`; UPX failure never fails the release).
7. **Gio is the only windowing dep** — for the rebuilt GUI (§6). `-tags goolm` on
   every build (pure-Go Matrix E2EE).
8. **Accounts are the model:** every backend is just an account, one shared frontend.
9. **No placeholders.** No demo data, stub buttons, "coming soon", dead UI. What cannot
   work against a real backend is HIDDEN, never faked; honest engine-driven
   empty/loading/error states only.
10. **Severity decides everything:** data-loss/crash > security > wrong behavior >
    degraded UX > cosmetic > QoL.
11. **Cores are disposable:** rate before touching; a stale/bad core is replaced
    completely, not patched; a solid pure-Go library beats custom code.
12. **Research → think → rate → plan → failing test → code → verify-against-real.**
    Dockerized server before official server. "It compiles" is not done.
13. **Dependencies stay current:** one module family per commit, full gate, sweep
    warnings. Not green in 3 tries → pin it, log it in WORKLOG open items.
14. **If a change cannot be tested, it cannot be made.** Build the harness first.
15. **Unspecified → do what a senior Unix engineer would do, then verify.**
16. **TeamSpeak & Mumble: 1:1 wire compatibility** with official protocols/clients,
    pinned to upstream test vectors, retested on public servers whenever protocol code
    changes.
17. **Tool-verified or it didn't happen.** Plan the verification tool BEFORE acting;
    cite its output for every claim. Undocumented protocol behavior → mine reference
    implementations FIRST (same-protocol open-source clients; e.g. TeamSpeak → ts3j,
    tsdeclarations) — never invent wire behavior.
18. **100% certainty = differential proof:** official client/tool vs OUR build, bytes
    and behavior compared. "Matches the docs" is never 100%.
19. **No premium, no bloat:** nothing premium/paid ever ships — no paid-tier feature,
    no useless feature, no useless look; if it is not load-bearing for free chatting,
    it does not exist in this product.
20. **Lean on every axis, every platform — phone, desktop, web alike:** least
    dependencies, least size, least hardware resource use, least latency — each one a
    hard budget, never an afterthought.
21. **This is production code obeying clean code rules.** Refactor clunky code as you
    go — never leave it for later; senior-dev intuition and common sense decide the
    ties; the bar is nothing short of SOTA perfection.

## 2. No comments in code. Ever.

Comments are prose welded to code — they snowball bias: every stale sentence steers the
next reader (human or AI) away from what the code actually does. The code is the only
truth; names and structure carry all the meaning.

1. **Zero prose comments in the Go tree.** Doc comments, section banners, `// TODO`,
   inline asides — all of it. If a comment feels necessary, fix the names or the
   structure instead.
2. **Only permitted exceptions (load-bearing syntax, not prose):** compiler directives
   (`//go:build`, `//go:embed`, `//go:generate`, `//go:linkname`, legacy `// +build`,
   `//line`), cgo `import "C"` preambles, Example `// Output:` pins.
3. **Enforcement:** `scripts/strip_comments.py` — byte-level lexical state machine
   (string/rune/raw-string aware; preserves the exceptions; refuses any file that does
   not lex). Run it after any edit that slipped a comment in; `--check` gates in CI
   (§9); gofmt-clean at all times.
4. Non-Go tool files (`yml/sh/mjs/py`) carry only short operational notes — never
   history, progress, or references to docs that do not exist.
5. `go/third_party/anet` is an upstream nested module — outside comment law and the
   stripper.

## 3. The atomic loop (one iteration = one atomic change)

```
pick item (§0.4) → research if non-trivial (primary sources, in-session; notes land in
the WORKLOG entry, NEVER in new doc files) → rate the design you're touching (n/10 +
why; <7/10 → replace, don't patch) → plan the BEST fix, not the fastest → write the
failing test and SEE it fail → make ONE atomic change → gate (§9) green → update
WORKLOG → commit → push → next item
```

- One concern per commit: fix, refactor, perf, deps, docs never travel together; state
  rides along with the change it describes.
- **Push the moment it's green — every few turns at minimum.** The sandbox dies at
  random; what is not on GitHub does not exist.
- Green after every change, no exceptions. Red → fix or `git revert` immediately; never
  push red; never bank unpushed work (risky WIP → `git push origin HEAD:wip/<slug>`).
- **3-strike rule:** the same approach failing 3× → revert, document repro + attempts
  in WORKLOG open items as BLOCKED, move on.
- Flaky test = bug: fix determinism, never retry-until-green; race fixes prove out with
  `-count=20`.
- **Never weaken a test to get green:** no skips, deletes, `t.Skip`, loosened
  assertions, or regenerated goldens. A deliberate behavior change updates its pin in
  the same commit and says so.
- **Evidence rule:** "done/works/fixed" only from command output seen THIS session —
  never from memory or from reading code. User-facing changes cite a driven journey
  (§4). WORKLOG entries cite the command + result.

## 4. The agent tests like a human (the center of the loop)

The AI is fully in the loop: it is the tester, and it plays the app like a real user.
Not optional, not delegable to the unit suite.

1. **A green unit suite is never evidence that user-facing behavior works.** Unit tests
   pin logic; they cannot see dead screens, wrong flows, jank, or broken journeys.
2. **Before any user-facing change is called done, drive the REAL program through its
   REAL interface:** today that is the headless host — boot, `-events` stream, SIGTERM
   → exit 0, real exit codes/stdout/stderr. With the GUI: native under `Xvfb` +
   xdotool with screenshots you look at yourself; web via Puppeteer against the real
   wasm bytes (fail on any console error/warning; viewports 390/820/1440).
3. **Journeys that matter:** boot, add account, every affected screen and menu,
   send/receive/edit/delete, failure + offline + empty + slow paths, double-submit,
   refresh mid-action, back button, mobile viewport.
4. **Evidence is part of the change:** E2E transcript, screenshot + what was seen, or
   event-stream trace lands in the WORKLOG entry. No evidence → not done.
5. **A bug fix = reproduce through the interface first**, then fix, then watch the
   failure disappear through the same interface.
6. If the sandbox cannot drive a surface: BLOCKED-env in WORKLOG open items — never
   "works".
7. **Scenario-complete unit tests** for what a journey cannot reach: zero/one/many,
   nil/empty/malformed/oversize, boundaries, rapid repeats, interrupt, offline.
## 5. Tests live in `go/tests/` — black-box, always

1. **Production packages contain zero `_test.go` files.** Unit tests live in
   `go/tests/<pkg>/` mirroring their package (`package tests`, dot-import of the
   package under test); live protocol tests stay at `go/tests/` root (`-tags live`,
   env-gated, never in CI).
2. **Tests use the exported API.** The 2026-11-01 migration opened the packages:
   distinctive helpers/types are exported (TsParseInit1, MumbleVarintDecode,
   MediaPlayer, …); fields/methods/constructors that must not be API are reached only
   through `ForTest*` hooks quarantined in one file per package (`testhooks*.go`).
3. **Hooks are debt, not a pattern:** never grow them; when a flow gains a real
   exported API its hooks die in the same commit; a new hook needs a WORKLOG open item
   naming its retirement path. Mutex/array hooks return pointers (lock-and-mutate
   semantics); map-of-value entries use `With*` copy hooks; source-scanning pins read
   `../../<pkg>/` paths.
4. `go test ./...` runs everything; `scripts/dev-test.sh` = small-machine shape
   (native `./tests/...` + js `./tests/audio/...` via the wasm runner).

## 6. The rebuilt GUI (direction set 2026-11-01 — build NOT yet ordered)

The references: **Telegram Desktop** (three-pane, keyboard-first, dense),
**Telegram Web** (route-driven, responsive, virtualized), **Telegram Android**
(Material, back-stack, bottom sheets). Never AyuGram — that mandate is revoked forever.

1. **Elm loop is the only pattern.** One `Model` holds all app state and ONE goroutine
   owns it. Every input is a `Msg` (gesture, engine event, tick, resize).
   `update(Model, Msg) (Model, Cmd)` is pure; `view(Model)` is pure. Engine calls
   happen only inside `Cmd` execution — never in view/update. Result: zero locks in UI
   code, stale async results dropped by generation, and journeys testable as Msg
   sequences.
2. **Boundary:** engine events cross into the UI through a single pump goroutine
   (coalescing under load → `win.Invalidate()`); Cmd results return as Msgs.
3. **Capabilities project the UI:** cores declare capabilities (send/edit/react/files/
   voice/replies/presence/typing…); the view renders only what the active account's
   core supports (§1.8/§1.9). Zero per-core UI code — one widget kit for every core.
4. **Layout is a pure function of (Model, window size):** ≥1000dp three-pane
   (Desktop), 600–1000dp two-pane, <600dp one-pane + back stack (Android).
   Navigation is a typed route stack in Model; panes are projections; deep links push
   routes. Windows are views over the one Model — per-window package state is
   forbidden (the old separate.go bug class, made impossible).
5. **Design system:** Telegram-flavored Material tokens — day/night/AMOLED palettes,
   type scale, 12dp bubbles, dense vs touch density by breakpoint. Kit on gio/material:
   chat-list row, message bubble (tails, reply quote, ticks, reactions), auto-growing
   composer (attach sheet, voice-hold), context menu, bottom sheet, FAB, unread
   divider, typing indicator.
6. **Performance laws:** virtualized history (O(visible) work), keyed diffing by
   (chatID, msgID), image decode off-loop with size-keyed cache, zero steady-state
   allocs in view, one animation clock.
7. **Testing (§4):** journeys are Msg-sequence scenario tests in `tests/gui`; the real
   app gains a `--script` action channel (tap/type/wait/screenshot) so the agent
   drives it like a human; Xvfb + Puppeteer CI legs return with it.

## 7. Architecture

```
go/
  cmd/uniclient/   ONE binary: headless engine host today; the rebuilt Gio window
                   lands here too (flag-based modes)
  bootstrap/       engine.Init + core factory + session migration
  engine/          accounts, vault-backed state, events, media, voice pipeline
  cores/           one file set per backend implementing cores.Core
  voice/           pure-Go opus codec + per-sender mixer (pion/opus)
  audio/           PulseAudio (Linux), winmm (Win), WebAudio (js), OpenSL (Android)
  utils/           vault (Argon2id+AES-GCM), config, crypto
  wrtc/            WebRTC shim: pion native, browser API on js/wasm
  tests/           ALL tests (§5): per-package mirrors + live tests
  testhooks*.go    ForTest* quarantine, one file set per package (§5.3)
```

Event flow: `cores → engine (caches+normalizes) → EngineEvent JSON →
SetEventCallback/Subscribe → UI`. Core interface: `go/cores/base.go`; unsupported
actions return `ErrNotSupported` and the UI hides them. Platform truth (go 1.27,
pure Go since the GUI removal): Linux/Windows/Android `CGO_ENABLED=0` (race needs
cgo); Web `GOOS=js GOARCH=wasm`; macOS/iOS banned.

**Web truth** (no raw sockets in browsers): GitHub + Matrix over HTTPS; Bale via
gRPC-Web WebSocket (`ErrNotSupported` on web); Telegram/IRC/XMPP/DeltaChat/TeamSpeak/
Mumble dial raw TCP → never browser-connectable → never in the web picker. Vault →
localStorage (`uniclient.vault`, AES-GCM, default password — env/flags unreachable in
a wasm argv); cache DB → null driver; tabs coordinate via flush-time vault merge
(F-87).

**Mutex law** (enforced by `tests/cores/lockorder_test.go`): never hold a core mutex
across network I/O or an RPC; snapshot via `t.withAPI()`/`t.withSenderAPI()`/`withPeer()`;
every RPC deadline-bounded (`rpcGuard`).

**Deleted forever — never resurrect:** `go/gui/` + the gui-only media cluster
(`lottie`, `h264vid`, `vp9anim`, `webm`, `vcodec`, `qrscan`), `go/bridge/`, `go/proto/`
+ root `proto/`, `go/cmd/web|bridge|cli`, `scripts/smoke/*.mjs`, `cores/demo.go` + the
`-demo` flag, `scripts/web-test/` (returns rebuilt for the new GUI). The UI calls the
engine in-process — no IPC, no second binary.

## 8. Release, web deploy, CI, NixOS

- Release only at a fully green gate: `flake.nix` version == tag; tag `v*` ≥ the newest
  existing tag; `prerelease: true` until the owner flips it; record in WORKLOG.
  Artifacts while headless: `uniclient-<os>-<arch>[.exe]`, no tarballs. The android
  APK + web (gh-pages) jobs return with the rebuilt GUI.
- `release.yml` (tags + dispatch): test/vet/race legs → nix gate (build + smoke +
  version==tag) → linux×2/windows builds → publish.
- `verify.yml` = the dispatch gate: comment-ban + gofmt + vet (+live) + test + race
  (`./tests/cores/` pinned subset) + headless smoke (boot `-events`, vault created,
  SIGTERM → exit 0) + nix + cross-builds (windows exe + js/wasm check). Too small to
  compile gotd → dispatch and read the run.
- `flake.yml` = vendorHash helper (dispatch after dependency changes; commits the new
  hash itself). NixOS (owner's daily driver): `nix run github:DarkReaperBoy/Uniclient
  --no-write-lock-file`; `flake.lock` never committed; release binaries (glibc) don't
  start on Nix — the flake is the supported path.

## 9. Testing rules & the verification ladder

**Tests first, always:** the failing test exists before the fix; every fix lands
red→green. Climb to the highest rung your change touches; a protocol change always
reaches rung 5 or 6; a user-facing change reaches rung 4.

1. **Unit/integration** — from `go/`: `make test` (CGO_ENABLED=1, `-p 1`, `-tags goolm`,
   `GOMEMLIMIT=900MiB GOGC=30` — gotd's `tg` needs it). `make lint` clean.
2. **js/wasm leg** — `scripts/dev-test.sh` (native `./tests/...` + `GOOS=js`
   `./tests/audio/...` under the verdict-first node runner).
3. **Cross-builds** — `make windows` + js/wasm compile check (both pure Go).
4. **The REAL interface** — §4: headless journeys today; Xvfb/Puppeteer with the GUI.
5. **Dockerized real server** (ergo IRC, prosody XMPP, mumble-server, dendrite,
   IMAP/SMTP harness) — preferred before official servers.
6. **Official/live servers** — `go/tests/*_live_test.go`, `-tags goolm,live`, env-gated
   (`IRC_LIVE_SERVER`, …). Never in CI, never secrets in the repo. TS/Mumble protocol
   changes always retest on a public server (§1.16).
7. **CI = the gate of record** — dispatch `verify.yml`, watch the run at job AND step
   level, record run id + result in WORKLOG STATE. Includes the comment-ban check
   (§2) and the headless smoke.

`scripts/gate.sh` exists — keep it true: `quick` (changed packages + importers) after
every commit; `full` (every tier except live/owner rungs) at front ends, dep bumps,
pre-tag.

## 10. Files, formats & context hygiene

- **AGENTS.md** — this file; law + reference only; no history or session state; fix or
  cut anything the code disproves, in the same commit; ≤ ~330 lines.
- **WORKLOG.md** — the ONLY state file: **STATE block** (≤8 lines: front | next |
  owner-waiting | last-gate), rewritten every session; then open items (topmost first,
  severity order: `| ID | where | what | evidence | next step |`; OPEN / BLOCKED /
  NEEDS_OWNER); then entries newest-first (did / evidence / next). Keep <300 lines —
  prune old entries, git retains them. The resume-from-zero memory.
- **README.md** — product-facing only. **No other progress/research/parity/bug
  docs** — notes live in WORKLOG entries and are pruned with them.
- Never commit build output, `dist/`, `artifacts/`, `flake.lock`, or secrets.
  Markdown stays short and true — delete doc lies, never pad them.
- **Context discipline:** noisy commands → redirect to a file, `tail -40`; read by
  range; delegate recon/log-triage to subagents when available; rewrite STATE before
  every yield; assume context can vanish between any two commands (push early); end
  every turn in ≤5 lines: done / evidence / next.

## 11. Owner-only rungs & pre-push invariants

**Owner-only rungs** — never block on them, never ask twice: log as NEEDS_OWNER in
WORKLOG open items, keep working, re-mention only in the turn-ending summary. Typical:
real-account live sign-ins, real mic/speaker + Android device tests, product/security
decisions that are the owner's to make, re-enabling Pages + cutting releases, flipping
prerelease off, ordering the GUI build, setting the next direction.

**Before every push, verify:** every ladder tier your change touches is green; the
comment ban holds (`strip_comments.py --check` clean); no TODO/FIXME/placeholder
markers and no dead UI; no secrets/tokens anywhere; error messages leak no internals;
WORKLOG STATE current; AGENTS.md still ≤ ~330 lines; repo stats still Go.
