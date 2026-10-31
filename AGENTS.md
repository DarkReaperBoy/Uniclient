# AGENTS.md — Uniclient

> **AUTONOMOUS EXECUTION MANDATE — read first.**
> 1. The owner is **not a programmer** and only ever says "continue" (or reports a live-test
>    result). Never ask technical, architectural, or "should I continue?" questions — the
>    only permitted asks are the GitHub token and owner-only rungs (§10), logged in BUGS.md.
> 2. **"continue" = §0 Boot, then §3's atomic loop back-to-back** — chain work cycles
>    until context grows heavy (~75%), rewrite STATE, push, yield cleanly.
> 3. A finished phase, an empty BUGS.md, a green release — none of that is a stop. Take the
>    next item or open the next cycle (§4). The loop is permanent; the target is perfection.

Uniclient is one pure-Go, cross-platform (PC / mobile / web), multi-backend messenger. One
native Gio GUI, many chat and voice backends — Telegram, Matrix, IRC, GitHub, XMPP, Delta
Chat, Bale, TeamSpeak, Mumble — each added and switched as easily as an account. The GUI
mirrors AyuGram's layout and behavior 1:1 (re-implemented from scratch, never copied) with
Material Design visuals.

This file is **law + reference only** — history and session state live in WORKLOG.md (STATE
block) and BUGS.md, never here. If the code contradicts anything here, the code wins: fix
this file in the same commit. Keep it under ~300 lines.

## 0. Boot — every session, in order

1. **Sync:** `git pull --rebase origin main`. The VM can die any second — only pushed work
   exists. Missing state files → create them (§6 formats).
2. **Auth:** the GitHub token comes from env (`GH_TOKEN`) or the owner, out-of-band. It
   NEVER lands in any file, log, commit, remote URL, or doc. Never force-push `main`.
3. **Load state:** WORKLOG.md (STATE block + newest entry), then BUGS.md's open table.
4. **Pick the next item, in this order:** (1) owner-reported (enters BUGS.md on top);
   (2) red gate — any failing §9 tier or broken build, fix before everything; (3) BUGS.md
   topmost open row (severity order, §1.16); (4) the current cycle-phase item (§4);
   (5) housekeeping — dep bumps (§1.18), warning sweeps, doc-truth fixes; (6) nothing open
   → open the next cycle (§4). An agent is never "done".
5. Work it through the atomic loop (§3). The only clean end to a turn: gate green (§9),
   STATE rewritten, committed, pushed — then yield.

## 1. Owner requirements (NON-NEGOTIABLE — wins over everything)

1. **Pure Go, 100%.** No Node/Electron/Flutter/Python/JS/HTML/webview in product code.
   Exceptions: Gio's own cgo shims (Linux GPU + Nix flake), CI-generated `gh-pages` files,
   and **test tooling** (`scripts/web-test/` Puppeteer, Xvfb, docker — never shipped,
   linked, or imported). Repo stats stay Go (md/yml/sh + test-only mjs tolerated).
2. **Platforms:** Linux + Android first-class; Windows second-class but fully supported.
   **macOS/iOS BANNED** — no targets, no CI, no docs.
3. **Native GUI, one binary.** Flag-based modes; headless is a flag; a browser tab is
   never "the app".
4. **The web target is WASM** from the same GUI code, deployed to
   `https://darkreaperboy.github.io/Uniclient/` via the orphan `gh-pages` branch (when
   Pages is enabled). `main` never contains JS/HTML.
5. **CI/CD on release tags (`v*`) + manual dispatch only.** Never per-push.
6. **Release binaries small:** `-trimpath -ldflags "-s -w"`, then UPX `--best --lzma`
   (skip `.wasm`/`.apk`; UPX failure never fails the release).
7. **Gio is the only windowing dep.** `-tags goolm` on every build (pure-Go Matrix E2EE).
8. **Accounts are the model:** every backend is just an account, one shared frontend.
9. **Two GUI modes: Chat and Voice.**
10. **No placeholders — everything functional.** No demo data, stub buttons, "coming
    soon", dead UI. What cannot work against a real backend is HIDDEN, never faked.
    Honest engine-driven empty/loading/error states only.
11. **AyuGram 1:1, UI and functionality, every aspect.** Telegram is the exact bar; other
    cores follow as far as their protocols allow. Material Design is the skin. The GUI is
    never trimmed to fit cores — cores grow to fit the GUI. Re-implement, never copy.
12. **Cores are disposable:** rate before touching; a stale/bad core is replaced
    completely, not patched; a solid pure-Go library beats custom code.
13. **Research → think → rate → plan → failing test → code → verify-against-real.**
    Dockerized server before official server. "It compiles" is not done.
14. **Every atomic change: commit + push the moment it's green — the sandbox dies at
    random.** Working files live in their repo folders (`scripts/`, `research/`, state
    docs at root, tests beside code) — never outside the repo; only artifacts and
    toolchains stay untracked. What is not on GitHub does not exist.
15. **TeamSpeak & Mumble: 1:1 wire compatibility** with official protocols/clients, pinned
    to upstream test vectors, retested on public servers whenever protocol code changes.
16. **Severity decides everything:** data-loss/crash > security > wrong behavior >
    degraded UX > cosmetic > QoL.
17. **No prose comments in code** — they snowball stale biases; strip in P3, one package
    per commit. NEVER touch `//go:build`, `//go:embed`, `//go:generate`, `//nolint`,
    license headers, or `import "C"` preambles.
18. **Dependencies stay current:** one module family per commit, full gate, sweep every
    warning/error (vet, build, test, browser console, CI annotations). Not green in 3
    tries → pin it and log in BUGS.md.
19. **If a change cannot be tested, it cannot be made.** Build the harness first.
20. **Unspecified → do what a senior Unix engineer would do, then verify.** The bar is
    production-ready and rock solid.
21. **The agent is the tester and plays the app like a human.** (a) Scenario-complete
    tests — every test designed against the full matrix: zero/one/many, nil/empty/
    malformed/oversize, boundaries, rapid repeats, interrupt-mid-action, offline.
    (b) Goal-directed journeys on the REAL app (per change + standing passes): boot,
    add an account, open every screen/menu, send/receive/edit/delete messages —
    Puppeteer on the wasm or Xvfb+xdotool native — hunting jank, slowdowns, logic
    errors at their ROOT cause, then fixing (P2 loop) and optimizing (P4). A green
    unit suite never substitutes for playing it. No journey → write it first;
    sandbox can't → BLOCKED-env in BUGS.md, never "works".

## 2. Architecture

```
go/
  cmd/uniclient/   ONE binary: Gio window + engine host, flag-based modes
  gui/             AyuGram-1:1 Gio app. Pure UI → engine calls only
  bootstrap/       engine.Init + core factory + session migration
  engine/          accounts, vault-backed state, events, media, voice pipeline
  cores/           one file set per backend implementing cores.Core
  voice/           pure-Go opus codec + per-sender mixer (pion/opus)
  audio/           PulseAudio (Linux), winmm (Win), WebAudio (js), OpenSL (Android)
  utils/           vault (Argon2id+AES-GCM), config, crypto
  wrtc/            WebRTC shim: pion native, browser API on js/wasm
  tests/           live protocol tests (-tags goolm,live; never in CI)
scripts/web-test/  Puppeteer E2E suite (§9)
```

Event flow: `cores → engine (caches+normalizes) → EngineEvent JSON →
SetEventCallback/Subscribe → gui invalidation`. Core interface: `go/cores/base.go`;
unsupported actions return `ErrNotSupported` and the GUI hides them.

Platform truth (go 1.27, gio v0.10.2): Linux `CGO_ENABLED=1` (X11/Wayland/EGL — cgo
required); Windows `CGO_ENABLED=0`, cross-builds from Linux; Android gogio + NDK → APK;
Web `GOOS=js GOARCH=wasm CGO_ENABLED=0`; macOS/iOS banned.

**Web capability truth** (verified 2026-10-31 — browsers have no raw sockets): GitHub +
Matrix connect over HTTPS; Bale via gRPC-Web WebSocket (calls return `ErrNotSupported` on
web). Telegram/IRC/XMPP/DeltaChat/TeamSpeak/Mumble dial raw TCP → can never connect from a
browser → never offered in the web picker (`webConnectable` in `gui/theme.go` is the single
source of truth, kept in sync with this table).
**Web persistence:** vault → localStorage (`uniclient.vault`, AES-GCM, default password —
env/flags are unreachable in a wasm argv); cache DB → null driver (session-only); no
single-instance lock — tabs coordinate via flush-time vault merge (F-87).

**Mutex law** (`telegram_lockscan_test.go` enforces): never hold a core mutex across
network I/O or an RPC. Snapshot pattern: `t.withAPI()`, `t.withSenderAPI()`, `withPeer()`.
Every RPC is deadline-bounded (`rpcGuard`).

**Deleted forever — never resurrect:** `go/bridge/`, `go/proto/` + root `proto/`,
`go/cmd/web|bridge|cli`, `scripts/smoke/*.mjs`, `cores/demo.go` + the `-demo` flag. The
GUI calls the engine in-process — no IPC, no serialization, no second binary.

## 3. The atomic loop (one iteration = one atomic change)

```
pick item (§0.4) → research if non-trivial (primary sources → research/<topic>.md;
distrust old notes) → rate the design you're touching (n/10 + why, in the WORKLOG
entry; <7/10 → replace, don't patch) → plan the BEST fix, not the fastest → write the
failing test and SEE it fail → make ONE atomic change → gate (§9) green → update
STATE/BUGS/WORKLOG → commit → push → next item
```

- One concern per commit: fix, refactor, perf, deps, docs never travel together;
  state-file edits ride along with the change they describe.
- Green after every change, no exceptions. Red → fix or `git revert` immediately; never
  push red; never bank unpushed work (risky WIP → `git push origin HEAD:wip/<slug>`,
  delete the branch when merged).
- **3-strike rule:** the same approach failing 3× → revert, document repro + attempts in
  BUGS.md as BLOCKED, move on. Never grind on one problem.
- Flaky test = bug: fix determinism (waitFor, fake clocks), never retry-until-green; race
  fixes prove out with `-count=20`.
- **Never weaken a test to get green:** no skips, deletes, `t.Skip`, loosened assertions,
  or regenerated goldens. A deliberate behavior change updates its `TestKnown_*` pin in
  the same commit and says so.
- **Evidence rule:** "done/works/fixed" only from command output seen THIS session —
  never from memory or from reading code. For user-facing changes the evidence is a
  driven journey (E2E transcript or screenshot + what you saw), never "the logic
  looks right"; a green unit suite is not evidence a UI works. WORKLOG entries cite
  the command + result.

## 4. The hardening cycle (endless)

Cycle + phase live in the WORKLOG STATE block. A phase starts only when the previous EXIT
GATE is met and recorded — merging phases or skipping a gate = failure. The ladder is
stack-agnostic (owner directive 2026-10-31): it hardens any program, any language.
Crash/data-loss/security findings interrupt any phase — fix via the loop, then resume. After P7: cycle += 1 and back to P2 with fresh lenses (redo P0 only
for surfaces never mapped or heavily changed since). Dependency bumps are allowed in any
phase as their own commits (§1.18). **Yield steering:** each P2 sweep records its finding
count in WORKLOG; two consecutive zero-finding sweeps → shift weight to §7 parity rows,
feature gaps, and P4 PERF.

| # | Phase | Do | EXIT GATE |
|---|---|---|---|
| 0 | Recon (read-only) | Read every file of the not-yet-mapped surfaces, **one package per iteration** (context safety): read → append to `research/MAP.md` → tick + commit + push. Map entry points, data flow, state/mutexes, external APIs, auth flows, screens; critical journeys (login, core actions, send, error paths); risk zones (races, lock-across-RPC, unvalidated input, leaked goroutines/timers/listeners, duplicated state, swallowed errors). | map + journeys + risk register written |
| 1 | Safety net | Verify every test tier (§9). Characterization tests (`TestKnown_*`) pin CURRENT behavior of every critical journey, bugs included. Write `research/GUI_CHECKLIST.md`: journeys × expected × edges (empty, offline, invalid input, rapid clicks, refresh mid-action, back button, mobile viewport). Create `scripts/gate.sh` if missing. | full gate green; checklist committed |
| 2 | Correctness (bugs only) | One lens per sweep: logic/state → races (`-race`, lock order) → ctx/goroutine/async lifecycles → unhandled & swallowed errors → boundary/protocol edges (nil/empty/malformed/UTF-8 truncation) → leaks (tickers, listeners, fds, goroutines). ONE bug per commit: red test → fix → gate green. No refactor/perf/style here. | full sweep, zero findings above cosmetic |
| 3 | Prune & refactor (behavior-preserving) | Prove deadness across ALL build tags (linux/windows/js/android/goolm/live) before deleting; doubt → BUGS.md, don't delete. Strip prose comments one package per commit (§1.17). Deduplicate, split oversized functions, untangle state. A behavior change = bug → revert. | gate green; every deletion logged with evidence |
| 4 | Performance (measure, never guess) | Baselines FIRST in `research/PERF.md`: `go test -bench -benchmem`, pprof cpu/heap, startup, wasm/binary size, frame time, allocs/frame, goroutine count. Optimize only measured hot paths, one per commit: measure → change → re-measure. Reject what doesn't beat baseline or adds complexity for <5%. | before/after numbers per change |
| 5 | UI/UX | Walk every screen against AyuGramDesktop + `research/GUI_CHECKLIST.md`: spacing/type/alignment/color; states code forgets (loading, empty, error, offline, permission-denied, slow network); focus, keyboard nav, tab order, double-submit, jank; mobile/tablet/desktop; contrast + Gio semantic labels. | every screen × state ticked |
| 6 | Security | Every boundary (network → core → engine → vault/GUI; downloads, archives, deeplinks, URIs): injection, path traversal, shell XSS/CSP, open redirects, TLS/TOFU, vault crypto, decompression/parse bombs (run the fuzzers), secrets in code/logs, internal-error leaks; `govulncheck`. Fix via the P2 loop. | every item verified; govulncheck clean |
| 7 | Full verification | Full gate + web E2E + native Xvfb + the whole checklist: zero failures, zero console errors/warnings, zero stderr panics, mobile viewport. Any failure → red test → fix → rerun everything. Release only here (§5). | all pass; WORKLOG changelog grouped by phase with verify steps |

## 5. Release, web deploy, CI, NixOS

- Release only at the P7 gate: `flake.nix` version == tag, tag `v*` (**version must be ≥
  the newest existing tag** — the v0.9.1-after-v0.10.2 mistake must never repeat), push
  the tag, all jobs green, `prerelease: true` until the owner flips it, record in WORKLOG.
  Artifacts: `uniclient-<os>-<arch>[.exe]`, `uniclient.apk` — one per platform, no
  tarballs unless asked.
- `release.yml` (tags + dispatch): gofmt/vet/vet-live/test/race legs → nix gate (build +
  smoke + version==tag) → linux×2/windows/android builds → web job (`needs: test`;
  writes `index.html` + `wasm_exec.js` from `$GOROOT/lib` + `uniclient.wasm` to the
  orphan `gh-pages` branch, force-push; zero GitHub-API calls from the shell) → publish.
- The self-updating shell (same-origin revalidation, ETag readout, determinate MB
  progress, offline fallback, Retry, overlay hides on canvas attach, post-boot crash
  surface) **exists only as `release.yml`'s heredoc** — the E2E suite extracts it from
  there; keep them in sync.
- `verify.yml` = the same gate on `workflow_dispatch` + Xvfb GUI smoke with screenshot
  artifacts; `flake.yml` = vendorHash helper. Machine too small to compile gotd →
  dispatch verify.yml and read the run.
- NixOS (owner's daily driver): `nix run github:DarkReaperBoy/Uniclient
  --no-write-lock-file`; `flake.lock` is never committed; release binaries (glibc
  runners) don't start on Nix — the flake is the supported path.

## 6. Files, formats & context hygiene

- **AGENTS.md** — law + reference only; no history, dates, or session state; fix or cut
  anything the code disproves, in the same commit; ≤ ~300 lines.
- **WORKLOG.md** — starts with the **STATE block** (≤8 lines: cycle | phase | item |
  next | owner-waiting | last gate), rewritten every session; then entries newest-first
  and terse (did / evidence / next); keep <300 lines — prune old entries, git retains
  them. This is the resume-from-zero memory.
- **BUGS.md** — open table, topmost first (severity order): `| ID | where | what |
  evidence | next step |`; statuses OPEN / BLOCKED / NEEDS_OWNER; IDs sequential `F-<n>`
  (`R-<n>` = risk IDs from research docs); fixed rows move to the Fixed table with their
  red→green evidence. Owner-reported items enter at the top.
- **research/** — agent scratch + cycle artifacts (`MAP.md`, `GUI_CHECKLIST.md`,
  `PERF.md`, protocol notes). Distrust old notes; verify against primary sources.
- Never commit build output, generated code, `dist/`, `artifacts/`, `flake.lock`, or
  secrets. Markdown stays short and true — delete doc lies, never pad them.
- **Context discipline:** noisy commands → redirect to a file, `tail -40`; read by range
  (`grep -n` → `sed -n 'a,bp'`), list funcs before reading >400-line files; delegate
  recon/log-triage to subagents when available; STATE is the only memory that must
  survive — rewrite it before every yield; assume context can vanish between any two
  commands (push early); end every turn in ≤5 lines: done / evidence / next.

## 7. GUI spec (the product — a horrible GUI is a release blocker)

AyuGramDesktop is the spec: same three-pane layout (chat list + main chat view + optional
right panel), same screens, behaviors, interactions — every aspect. A missing one is a
bug, never a "difference"; `research/ayugram_parity.md` tracks the rows (195/200 PRESENT
at last audit; the 5 non-PRESENT rows are recorded owner decisions — not buildable
without the owner). Scrolling + Material ripple everywhere; progress/connection
indicators (green/amber/red; empty ≠ loading); honest empty states; local passcode gate;
Chat/Voice tabs; "one frontend, many accounts"; backend-specific UI limited to auth steps
+ capability-gated actions. Voice renders only what the engine reports — no simulated
calls. When unsure how something looks or behaves, open AyuGramDesktop and copy the
behavior, never the code.

## 8. Cores — status, policy, references (read-only; non-Go is never a dependency)

Policy: rate before touching (§3); a core never imports engine or another core; stale
cores stay hidden from the GUI until rewritten; TS/Mumble carry the §1.15 wire bar.

| Core | State | Base / references |
|---|---|---|
| telegram | most complete; the AyuGram 1:1 bar | gotd/td; refs: AyuGramDesktop (spec), tdlib (protocol only) |
| matrix | E2EE goolm; MSC3401 full-mesh calls live-verified (dendrite); no LiveKit interop | mautrix/go; refs: element-web (capabilities only) |
| irc | live-verified vs real servers | own RFC2812+IRCv3; refs: modern.ircdocs.horse, ircv3.net |
| github | live-verified vs the real API | own net/http; refs: GitHub REST/GraphQL docs |
| xmpp | local-server-verified in CI; data-form IBR | own; refs: Conversations (behavior) |
| bale | pre-auth live-verified (gRPC-Web); real OTP = owner rung | own protobuf-over-WebSocket; refs: web.bale.ai |
| deltachat | local-server-verified in CI (IMAP/SMTP); real account = owner rung | go-imap/go-smtp/go-crypto; refs: chatmail/core |
| mumble | LIVE incl. voice (public server, two-client opus); OCB2 1:1 port | own; refs: mumble protocol docs |
| teamspeak | LIVE incl. voice (EAX, generation counters, QuickLZ 1:1 golden vectors) | own; refs: ts3j, ReSpeak/tsdeclarations |

## 9. Testing rules & the verification ladder

**Tests first, always:** the failing test exists before the fix; every BUGS.md fix lands
red→green. The suite is the contract — green after every change (§3). Climb to the
highest rung your change touches; a protocol change always reaches rung 5 or 6; a GUI
change reaches rung 4.

1. **Unit/integration** — from `go/`: `make test` (CGO_ENABLED=1, `-p 1`, `-tags goolm`,
   `GOMEMLIMIT=900MiB GOGC=30` — gotd's `tg` needs it). `make lint` (vet + gofmt) clean.
2. **js/wasm leg** — `scripts/dev-test.sh` (native engine/cores/utils/bootstrap +
   `GOOS=js` gui/audio under the verdict-first node runner). The small-machine gate.
3. **Cross-builds** — `make windows` + `make wasm` (both pure Go).
4. **GUI, for real:**
   - *Web:* `make wasm && cd scripts/web-test && node run.mjs` — shell tier (the exact CI
     bytes, extracted from the release.yml heredoc) + app tier (the real wasm:
     boot→welcome→picker→auth form, vault persistence, two-tab merge). `--live` re-checks
     the deployed site when Pages is enabled. **Fail on any console error or warning.**
     Viewports 390/820/1440. Click targets are calibrated in canvas space
     (`scripts/web-test/README.md`); an `e2e`-tagged UI-snapshot hook is the sanctioned
     upgrade if calibration drifts.
   - *Native Linux:* the real binary under `Xvfb` (+ xdotool input), screenshots to
     `artifacts/` (gitignored). Look at the screenshots yourself; describe what you saw
     in the WORKLOG evidence line. In CI: verify.yml's Xvfb GUI smoke.
5. **Dockerized real server** (ergo IRC, prosody XMPP, mumble-server, dendrite, IMAP/SMTP
   harness) — the preferred rung before official servers.
6. **Official/live servers** — `go/tests/*_live_test.go`, `-tags goolm,live`, env-gated
   (`IRC_LIVE_SERVER`, `MUMBLE_LIVE_SERVER`, …). Never in CI, never secrets in the repo.
   TS/Mumble protocol changes always retest on a public server (§1.15).
7. **CI = the release gate** (§5). Machine too small to compile gotd → `gh workflow run
   verify.yml`, watch the run, read logs + screenshots.

`scripts/gate.sh` exists — keep it true: `quick` (changed packages + importers) after
every commit; `full` (every tier except live) at phase ends, dep bumps, pre-tag; `web`
(wasm build + Puppeteer suite) for GUI work.

## 10. Owner-only rungs & pre-push invariants

**Owner-only rungs** — never block on them, never ask twice: log as NEEDS_OWNER in
BUGS.md, keep working, re-mention only in the turn-ending summary. Typical: real-account
live sign-ins, real mic/speaker + Android device tests, product/security decisions that
are the owner's to make, re-enabling GitHub Pages + cutting the next release, flipping
prerelease off. The live list sits in the WORKLOG STATE block.

**Before every push, verify:** every ladder tier your change touches is green; no
TODO/FIXME/placeholder markers and no dead UI; no secrets/tokens anywhere; error messages
leak no internals; BUGS.md IDs sequential; WORKLOG STATE current; AGENTS.md still ≤ ~300
lines; repo stats still Go.
