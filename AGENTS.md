# AGENTS.md — Uniclient

> **AUTONOMOUS EXECUTION MANDATE — read first.**
> 1. The owner is **not a programmer** and only ever says "continue" (or reports a live-test
>    result / a new direction). Never ask technical, architectural, or confirmation
>    questions, and never wait for a yes — decide, log the call in WORKLOG, proceed. The
>    only permitted asks are the GitHub token and owner-only rungs (§9). **Language:**
>    reply in English only. Owner input in another language (e.g. Chinese) is an
>    INSTRUCTION — interpret and execute it, still answering in English.
> 2. **"continue" = §0 Boot, then the atomic loop (§3) back-to-back** — chain cycles until
>    context grows heavy (~75%), rewrite STATE, push, yield cleanly.
> 3. A finished front, an empty open-items list, a green release — none of that is a stop.
>    Work endlessly: take the next item or open the next front. The loop is permanent.
> 4. **An owner redirect overrides every standing plan instantly:** drop the old plan,
>    record the redirect in WORKLOG, execute the new instruction completely.

Uniclient is one pure-Go, cross-platform (PC / mobile / web), multi-backend messenger:
one frontend over many chat and voice backends — Telegram, Matrix, IRC, GitHub, XMPP,
Delta Chat, Bale, TeamSpeak, Mumble — each added and switched as easily as an account.

**Direction (owner, 2026-11-01):** the current native GUI is **deprecated** — it is not
1:1 with AyuGram Desktop and will be **removed**. Removal is NOT yet ordered: until the
owner says go, keep it compiling and gate-green and invest nothing in it — no features,
no parity, no polish; the old AyuGram-1:1 mandate is revoked. The cores and the engine
are the product.

This file is **law + reference only** — history and session state live in WORKLOG.md,
never here. If the code contradicts anything here, the code wins: fix this file in the
same commit. Hard ceiling ~300 lines.

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
5. Work it through the atomic loop (§3). The only clean end to a turn: gate green (§7),
   STATE rewritten, committed, pushed — then yield.

## 1. Owner requirements (NON-NEGOTIABLE — wins over everything)

1. **Pure Go, 100%.** No Node/Electron/Flutter/Python/JS/HTML/webview in product code.
   Exceptions: Gio's own cgo shims, CI-generated `gh-pages` files, test tooling
   (`scripts/web-test/` Puppeteer, Xvfb, docker — never shipped/linked/imported). Repo
   stats stay Go (md/yml/sh + test-only mjs/py tolerated).
2. **Platforms:** Linux + Android first-class; Windows second-class but fully
   supported. **macOS/iOS BANNED** — no targets, no CI, no docs.
3. **One binary per platform**, flag-based modes; headless is a flag; a browser tab is
   never "the app".
4. **The web target is WASM** from the same code, deployed to the orphan `gh-pages`
   branch → `https://darkreaperboy.github.io/Uniclient/` (when Pages is enabled).
   `main` never contains JS/HTML.
5. **CI/CD on release tags (`v*`) + manual dispatch only.** Never per-push.
6. **Release binaries small:** `-trimpath -ldflags "-s -w"`, then UPX `--best --lzma`
   (skip `.wasm`/`.apk`; UPX failure never fails the release).
7. **Gio is the only windowing dep** (for as long as the GUI exists). `-tags goolm` on
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
13. **Dependencies stay current:** one module family per commit, full gate, sweep every
    warning. Not green in 3 tries → pin it and log it in WORKLOG open items.
14. **If a change cannot be tested, it cannot be made.** Build the harness first.
15. **Unspecified → do what a senior Unix engineer would do, then verify.**
16. **TeamSpeak & Mumble: 1:1 wire compatibility** with official protocols/clients,
    pinned to upstream test vectors, retested on public servers whenever protocol code
    changes.
17. **Tool-verified or it didn't happen.** Plan the verification tool BEFORE acting;
    cite its output for every claim. Undocumented protocol behavior → mine reference
    implementations FIRST (same-protocol open-source clients; e.g. TeamSpeak → ts3j,
    tsdeclarations) — never invent wire behavior.
18. **100% certainty = differential proof:** run the official client/tool against OUR
    build and compare bytes and behavior. "Matches the docs" is never 100%.

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
   (§7); gofmt-clean at all times.
4. Non-Go tool files (`yml/sh/mjs/py`) carry only short operational notes — never
   history, progress, or references to docs that do not exist.
5. `go/third_party/anet` is an upstream nested module — outside comment law and the
   stripper.

## 3. The atomic loop (one iteration = one atomic change)

```
pick item (§0.4) → research if non-trivial (primary sources, in-session; notes land in
the WORKLOG entry, NEVER in new doc files) → rate the design you're touching (n/10 +
why; <7/10 → replace, don't patch) → plan the BEST fix, not the fastest → write the
failing test and SEE it fail → make ONE atomic change → gate (§7) green → update
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
   REAL interface:**
   - *Web:* Puppeteer against the real wasm — `make wasm && cd scripts/web-test &&
     node run.mjs` (shell tier = the exact CI bytes; app tier = the real binary); fail
     on any console error or warning; viewports 390/820/1440.
   - *Native:* the real binary under `Xvfb` + xdotool, screenshots to `artifacts/`
     (gitignored) — look at them yourself, describe what was seen in the WORKLOG
     evidence line.
   - *Terminal:* a real terminal, real exit codes, real stdout/stderr.
   While the deprecated GUI still ships, anything that touches it gets exactly this.
3. **Journeys that matter:** boot, add account, every affected screen and menu,
   send/receive/edit/delete, failure + offline + empty + slow paths, double-submit,
   refresh mid-action, back button, mobile viewport.
4. **Evidence is part of the change:** E2E transcript, screenshot + what was seen, or
   HTTP trace lands in the WORKLOG entry. No evidence → not done.
5. **A bug fix = reproduce through the interface first**, then fix, then watch the
   failure disappear through the same interface.
6. If the sandbox cannot drive a surface: BLOCKED-env in WORKLOG open items — never
   "works".
7. **Scenario-complete unit tests** for what a journey cannot reach: zero/one/many,
   nil/empty/malformed/oversize, boundaries, rapid repeats, interrupt-mid-action,
   offline.

## 5. Architecture

```
go/
  cmd/uniclient/   ONE binary: window + engine host, flag-based modes
  gui/             DEPRECATED Gio app (removal pending) — pure UI → engine calls only
  bootstrap/       engine.Init + core factory + session migration
  engine/          accounts, vault-backed state, events, media, voice pipeline
  cores/           one file set per backend implementing cores.Core
  voice/           pure-Go opus codec + per-sender mixer (pion/opus)
  audio/           PulseAudio (Linux), winmm (Win), WebAudio (js), OpenSL (Android)
  utils/           vault (Argon2id+AES-GCM), config, crypto
  wrtc/            WebRTC shim: pion native, browser API on js/wasm
  tests/           live protocol tests (-tags goolm,live; never in CI)
scripts/web-test/  Puppeteer E2E suite (§4, §7)
```

Event flow: `cores → engine (caches+normalizes) → EngineEvent JSON →
SetEventCallback/Subscribe → gui invalidation`. Core interface: `go/cores/base.go`;
unsupported actions return `ErrNotSupported` and the UI hides them.

Platform truth (go 1.27, gio v0.10.2): Linux `CGO_ENABLED=1` (X11/Wayland/EGL); Windows
`CGO_ENABLED=0` (cross from Linux); Android gogio+NDK → APK; Web
`GOOS=js GOARCH=wasm CGO_ENABLED=0`; macOS/iOS banned.

**Web capability truth** (no raw sockets in browsers): GitHub + Matrix over HTTPS; Bale
via gRPC-Web WebSocket (calls `ErrNotSupported` on web). Telegram/IRC/XMPP/DeltaChat/
TeamSpeak/Mumble dial raw TCP → never browser-connectable → never in the web picker
(`webConnectable` in `gui/theme.go`, kept in sync with this table).

**Web persistence:** vault → localStorage (`uniclient.vault`, AES-GCM, default password
— env/flags unreachable in a wasm argv); cache DB → null driver (session-only); no
single-instance lock — tabs coordinate via flush-time vault merge (F-87).

**Mutex law** (`telegram_lockscan_test.go` enforces): never hold a core mutex across
network I/O or an RPC; snapshot via `t.withAPI()`/`t.withSenderAPI()`/`withPeer()`;
every RPC deadline-bounded (`rpcGuard`).

**Deleted forever — never resurrect:** `go/bridge/`, `go/proto/` + root `proto/`,
`go/cmd/web|bridge|cli`, `scripts/smoke/*.mjs`, `cores/demo.go` + the `-demo` flag. The
UI calls the engine in-process — no IPC, no serialization, no second binary.

## 6. Release, web deploy, CI, NixOS

- Release only at a fully green gate: `flake.nix` version == tag; tag `v*` ≥ the newest
  existing tag; `prerelease: true` until the owner flips it; record in WORKLOG.
  Artifacts: one `uniclient-<os>-<arch>[.exe]`/`uniclient.apk` per platform, no
  tarballs.
- `release.yml` (tags + dispatch): gofmt/vet/vet-live/test/race legs → nix gate (build +
  smoke + version==tag) → linux×2/windows/android builds → web job (`needs: test`;
  writes `index.html` + `wasm_exec.js` + `uniclient.wasm` to the orphan `gh-pages`
  branch, force-push; zero GitHub-API calls from the shell) → publish.
- The self-updating shell (same-origin revalidation, ETag, determinate MB progress,
  offline fallback, Retry, crash surfaces) **exists only as `release.yml`'s heredoc** —
  the E2E suite extracts it from there; keep them in sync.
- `verify.yml` = the dispatch gate: test/vet/race + comment-ban check + cross-builds +
  android + Xvfb GUI smoke with screenshot artifacts. Machine too small to compile
  gotd → dispatch it and read the run.
- `flake.yml` = vendorHash helper. NixOS (owner's daily driver): `nix run
  github:DarkReaperBoy/Uniclient --no-write-lock-file`; `flake.lock` never committed;
  release binaries (glibc runners) don't start on Nix — the flake is the supported
  path.

## 7. Testing rules & the verification ladder

**Tests first, always:** the failing test exists before the fix; every fix lands
red→green. Climb to the highest rung your change touches; a protocol change always
reaches rung 5 or 6; a user-facing change reaches rung 4.

1. **Unit/integration** — from `go/`: `make test` (CGO_ENABLED=1, `-p 1`, `-tags goolm`,
   `GOMEMLIMIT=900MiB GOGC=30` — gotd's `tg` needs it). `make lint` clean.
2. **js/wasm leg** — `scripts/dev-test.sh` (native engine/cores/utils/bootstrap +
   `GOOS=js` gui/audio under the verdict-first node runner). The small-machine gate.
3. **Cross-builds** — `make windows` + `make wasm` (both pure Go).
4. **The REAL interface** — §4: web E2E (`node run.mjs`) and/or native Xvfb journeys
   with screenshots.
5. **Dockerized real server** (ergo IRC, prosody XMPP, mumble-server, dendrite,
   IMAP/SMTP harness) — preferred before official servers.
6. **Official/live servers** — `go/tests/*_live_test.go`, `-tags goolm,live`, env-gated
   (`IRC_LIVE_SERVER`, `MUMBLE_LIVE_SERVER`, …). Never in CI, never secrets in the
   repo. TS/Mumble protocol changes always retest on a public server (§1.16).
7. **CI = the gate of record** — dispatch `verify.yml`, watch the run at job AND step
   level, record run id + result in WORKLOG STATE. Includes the comment-ban check
   (§2) and the Xvfb GUI smoke.

`scripts/gate.sh` exists — keep it true: `quick` (changed packages + importers) after
every commit; `full` (every tier except live/owner rungs) at front ends, dep bumps,
pre-tag; `web` (wasm build + Puppeteer suite) for UI work.

## 8. Files, formats & context hygiene

- **AGENTS.md** — this file; law + reference only; no history or session state; fix or
  cut anything the code disproves, in the same commit; ≤ ~300 lines.
- **WORKLOG.md** — the ONLY state file: **STATE block** (≤8 lines: front | next |
  owner-waiting | last-gate), rewritten every session; then open items (topmost first,
  severity order: `| ID | where | what | evidence | next step |` — the former BUGS.md
  role; statuses OPEN / BLOCKED / NEEDS_OWNER); then entries newest-first (did /
  evidence / next). Keep <300 lines — prune old entries, git retains them. This is the
  resume-from-zero memory.
- **README.md** — product-facing only.
- **No other progress/research/parity/bug docs.** The 2026-11-01 owner purge deleted
  BUGS.md + research/ (MAP, HOT, ayugram_parity, web_hardening, protocol notes); do
  NOT recreate that apparatus — research notes and risk findings live in WORKLOG
  entries and get pruned with them.
- Never commit build output, `dist/`, `artifacts/`, `flake.lock`, or secrets.
  Markdown stays short and true — delete doc lies, never pad them.
- **Context discipline:** noisy commands → redirect to a file, `tail -40`; read by
  range; delegate recon/log-triage to subagents when available; rewrite STATE before
  every yield; assume context can vanish between any two commands (push early); end
  every turn in ≤5 lines: done / evidence / next.

## 9. Owner-only rungs & pre-push invariants

**Owner-only rungs** — never block on them, never ask twice: log as NEEDS_OWNER in
WORKLOG open items, keep working, re-mention only in the turn-ending summary. Typical:
real-account live sign-ins, real mic/speaker + Android device tests, product/security
decisions that are the owner's to make, re-enabling Pages + cutting releases, flipping
prerelease off, ordering the GUI removal, setting the new direction.

**Before every push, verify:** every ladder tier your change touches is green; the
comment ban holds (`strip_comments.py --check` clean); no TODO/FIXME/placeholder
markers and no dead UI; no secrets/tokens anywhere; error messages leak no internals;
WORKLOG STATE current; AGENTS.md still ≤ ~300 lines; repo stats still Go.
