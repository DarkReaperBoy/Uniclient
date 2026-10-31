# WORKLOG.md — the session journal

Top: the **STATE block** — rewritten every session, the resume pointer for the
next agent. Below: one entry per work session, newest first. This is the
resume-from-zero mechanism. (The pre-2026-10 history was deleted by the owner
on 2026-10-30 — it lives in git history if ever needed.)

## STATE

- cycle: 2 | phase: P0 recon (chunk 3, per-file gui surfaces)
- item: R15 fixed this session (wasm-test-runner false-green hole + R14 test self-deadlock, found via CI 41174703134 = FAILURE); chunk 3 iteration 1 DONE (chat.go)
- next: read verify.yml run <R15-NATIVE — fill after dispatch> (R15+R14 native proof), then chunk 3 iteration 2 (next surface: sidebar.go, 36KB, the chat-list journey)
- owner-waiting: re-enable Pages + cut v0.10.4; R9 web-vault decision; real-account sign-ins; first non-prerelease
- last-gate: quick GREEN (runner self-test + js vet + full gui suite with verdict discipline, 907 tests; audio leg green)

## Session 332 — R15: the js test runner had a false-green hole; R14's test self-deadlocked (2026-10-31)

- Opened the session on STATE's queued task: read verify.yml run 41174703134
  (R14 native proof). **FAILURE** — and the goroutine dump named the R14
  fix's own test: TestInSearchFromPanelIsPerWindow parked 10 minutes in
  snapshot()'s `a.mu.Lock()` (state.go:2178), called from chatsearch_test.go:25
  WITH `a.mu` already held — a same-goroutine double-Lock (Go mutexes are
  non-reentrant). The fix code itself is fine; the TEST deadlocks.
- The alarming half: the session-331 local js leg had reported "gui suite
  green 0.596s". Reproduced with the actual binary under raw node: the
  deadlock drains node's event loop, node exits 0 with NO verdict printed,
  and wasm-test-runner.sh's old `RC==0 → exit 0` short-circuit accepted it —
  **a false green over a silently truncated suite** (everything after the
  deadlocking test in run order never executed; 907 tests exist, the
  truncated leg ran ~half). The F-88 false-green class, second hole.
- Fix, three parts (R15 in BUGS.md Fixed):
  1. wasm-test-runner.sh contract inverted — success now REQUIRES the
     binary's own `PASS` line at any node exit code; RC short-circuit
     deleted; post-PASS teardown crash still tolerated.
  2. scripts/test-wasm-runner.sh — regression harness pinning hang /
     printed-FAIL / pass with instant fixture binaries (the hang fixture
     reproduces the R14 shape). RED on the old runner, GREEN after; wired
     into dev-test.sh + gate.sh (quick js-legs/runner-change, full always).
  3. chatsearch_test.go fixed — snapshot() takes a.mu itself, caller must
     not hold it.
- Verification: full gui suite through the fixed runner — 907 RUN /
  886 PASS / 21 SKIP / 0 FAIL, final PASS, direct verbose node run confirms
  the previously-truncated tail now executes; audio leg green; gate quick
  GREEN end-to-end (self-test runs inside the gate). All other a.mu.Lock
  blocks in gui tests audited — pure field access, no locking-method calls.
  All five production snapshot() call sites audited — none under lock.
- Native proof: this box can't run the native gui leg (§9.7 OOM) → verify.yml
  re-dispatched for 497a4528+this-fix; run id recorded in STATE next line.

## Session 331 — P0 chunk 2 complete: state.go 100%, R14 opened (2026-10-31)

- state.go read to the end (2,837/2,837): struct tail, refreshMessages/
  mergeMessages, downloads, auth flows, openChat full body, sendText/composer/
  loadOlder, cfgSnapshot/openSettings, load*/apply* families, snapshot() +
  frame struct; app.go Root (separate-window routing, passcode gate) +
  layoutMain both chains.
- **R14 opened (BUGS.md topmost)**: package-level `inSearchFromPanel`
  (chatsearch.go:25) — every window's GUI loop can write it (separate windows
  render the chat header incl. search button) → unsynchronized cross-goroutine
  access + UI bleed between windows; B-47 class. Call graph verified by grep
  (chatsearch 226/248/318/472 + state.go:1477). Fix = per-App field, P2.
- settings* package vars audited same session: main-window-only in practice
  (Root:51-52 keeps settings out of separate windows) → no race; P3 fold-in
  note in MAP.
- Everything else clean: engine calls outside locks throughout auth/send/
  pagination; copy-on-write on message mutations; re-entrancy + staleness
  guards everywhere. mergeMessages same-timestamp edge noted (cosmetic, MAP).
- MAP.md: chunk 2 marked mapped (330-331); chunk 3 (remaining ~88 gui files,
  one surface per iteration) queued.
- Research-only session (no Go code touched) — no gate run needed beyond the
  clean tree check.

Same session, after the recon: **R14 fixed** (BUGS topmost row per §0.4(3),
interrupting P0 as a race-class finding):

- RED seen: TestInSearchFromPanelIsPerWindow fails to compile on the old
  code (`a.inSearchFromPanel undefined`) — the F-90 seam pattern. Fix: flag
  into App (a.mu-guarded, slice-18 group) + through snapshot() into frame;
  all 5 sites converted; package var deleted; invalidate() order preserved
  in setInSearchFrom (caught my own accidental drop mid-edit).
- Machine truth again: bare `go test ./gui/` native = gotd compile OOM
  (dmesg: compile killed, anon-rss 3.3GB, 4GiB cgroup) — the js leg is the
  only local path; documented in §9.7, followed it.
- GREEN: gui suite js/wasm 0.596s; gate quick GREEN (correct closure: gui +
  cmd/uniclient); web tier first run was an honest SKIP (node_modules wiped
  with the VM) → restored per env.sh recipe (npm ci + chrome 148 to
  toolchain/puppeteer-cache) → **web gate GREEN**: full Puppeteer suite on
  the rebuilt wasm, s1-s15 + b1-b6, clean console (law 21b satisfied at the
  tiers this machine can run; the two-window scenario itself is native-only
  and pinned by the unit test at the state level).
- Edit-tool lesson (session 329's, repeated): chatsearch/state are
  space-indented; a "failed" MultiEdit can still have applied earlier edits —
  ALWAYS re-grep the file state after any MultiEdit error before retrying
  (this session: 2 of 5 edits landed despite the error report).
- Native proof: verify.yml dispatched post-push (run 41174703134); next
  session reads the run — same pattern as 329.

Post-fix work, same session:

- Constitution: language rule added to mandate point 1 (English replies;
  non-English owner input = instruction; switch only on explicit ask) —
  owner directive, commit f2bbff62.
- P0 chunk 3 opened, iteration 1 = chat.go (1,578 lines) read in full →
  MAP.md: layout priority chain, the 20-deep overlay chain, messageList row
  model + pagination trigger, messageRow bubble tree, composer submit gate.
  Lock discipline clean throughout.
- Watch item registered (NOT a BUGS row — needs reference verification per
  law 22/23): trySubmitComposer clears the composer before the async send
  result; a failed send loses the typed text (tdesktop keeps it). Same
  pattern in inline-bot/music-attach/sticker send paths.
- CI 41174703134 still in_progress at yield.

## Session 330 — constitution v3.4: law 22/23, HOT store; wipe #2 survived (2026-10-31)

Owner directive (5 adds, AGENTS.md-first): tool-verified action + reference
implementations for undocumented protocols; an urgent-research store the next
session MUST read; official-client differential testing for 100% cases;
document-for-next-session + git-current-every-few-turns; never ask confirmation,
work endlessly through all phases.

- **The VM erased the whole tree before this session started** (wipe #2: repo +
  toolchain + download copy; only upload/ and skills/ survived). Re-cloned from
  origin at 205816e9 — zero work lost because §1.14 was obeyed. The law's new
  "a recycle can wipe the whole tree" wording is empirical, not hypothetical.
- Law 22 **tool-verified or it didn't happen**: plan the verification tool BEFORE
  acting, cite its output for every claim; undocumented/ambiguous protocol →
  mine reference implementations FIRST (§8 refs; TS → ts3j/tsdeclarations),
  never invent wire behavior.
- Law 23 **100% certainty = differential proof**: exactness cases (§1.15 wire,
  vault crypto) proven by running the official client/tool against OUR build,
  comparing bytes/behavior (§9.5 → §9.6); "matches the docs" is never 100%.
- **research/HOT.md created** (§0.3 must-read + §6 definition): the urgent store,
  pruned the moment stale. First edition: wipe #2 recovery, CI run to read,
  chunk-2 pointer.
- **scripts/env.sh committed** — the toolchain recovery recipe now lives in the
  repo (session 328 kept it outside; wipe #2 ate it). Header carries the proven
  full-recovery sequence.
- Header mandate sharpened: never ask confirmation, never wait for a yes —
  decide, log the call in WORKLOG, proceed; point 3 = work endlessly through ALL
  phases. §1.14: push every few turns at minimum.
- Budget: 316 lines (ceiling raised ~300 → ~320 in all 3 mentions). 5 owner
  directives in 2 days cost +11 net (laws 22-23, HOT store, §1.14, §0.3);
  reclaimed 5 (evidence-rule overlap with law 22, §0.4, law 21, §2 platform/
  mutex/web-capability, §5 release/shell prose; also removed a §6-violating
  date from §2 web-truth). Budget serves context discipline, not itself.
- Docs-only change (no Go on the VM yet — env.sh is the rebuild plan). Evidence:
  diff reviewed, laws 19-23 sequential, cross-refs (§3/§8/§9.5/§9.6/§1.15) all
  resolve, wc -l = 316.
- Next: rebuild toolchain → read CI run 41152637658 → P0 chunk 2.

Post-constitution work, same session:

- Toolchain rebuilt from the new recipe: Go 1.27.0 + 1.3G module cache;
  env.sh had a real bug — sourced from bash, `$0` is the SHELL, so TOOLCHAIN
  resolved to `//../toolchain` and go vanished from PATH; fixed with
  BASH_SOURCE + a missing-go warning (e8e58c23). Verified: sourced → go on
  PATH, mod cache refilled, `gate.sh quick` exit 0.
- CI run 41152637658 read via API: completed / SUCCESS on 593bb350 — the
  native-gotd proof for session 329's bootstrap comment-strip. HOT pruned.
- **P0 chunk 2 iteration 1 DONE**: gui state core mapped → MAP.md (App struct
  model, Start/onEvent/openChat, lock audit). Headline: awk scanner over all
  gui/*.go (defer-aware, both call forms) — 749 a.mu.Lock() sites, ZERO
  engine calls under the lock; mutex law holds at the gui layer. Two watch
  items registered (typing-goroutine churn, serial per-account caps) as P2/P4
  candidates, not BUGS rows. state.go is 2,837 lines — iteration 2 continues
  from MAP's "NOT yet read" list.

## Session 329 — constitution v3.3: human-sim law, push law, ladder provenance (2026-10-31)

Owner directive (three adds, AGENTS.md-first gate):

- Law 21 rewritten: the agent is the tester AND plays the app like a human —
  (a) scenario-complete test design (zero/one/many, nil/empty/malformed/oversize,
  boundaries, rapid repeats, interrupt-mid-action, offline); (b) goal-directed
  journeys on the real app (boot, add account, every screen/menu, send/receive/
  edit/delete) hunting jank/slowdown/logic-error ROOT causes → P2 fix, P4 optimize.
- §1.14 sharpened: every atomic change commits AND pushes the moment it's green;
  working files live in repo folders, never outside; only artifacts/toolchains
  untracked; what is not on GitHub does not exist.
- §4 intro: merging phases or skipping a gate = failure; ladder is stack-agnostic
  (owner directive — hardens any program, any language). The owner's pasted
  P0-P7 ladder was verified rule-by-rule against §4 + §1/§3: all 11 global rules
  and all 8 phase gates were already law (merged in v3 from this same paste);
  the explicit no-merge sentence is the only addition.
- §9 gate.sh paragraph recompressed (it exists now — doc truth).
- File: 305 lines (5 over the ~300 target — the price of two new directives;
  next pure-docs session should reclaim).
- P0 chunk 1 DONE same session: cmd/uniclient + bootstrap read in full →
  research/MAP.md (entry points, wiring, journeys, risks R11-R13 now open in
  BUGS.md). Doc-truth fix riding the chunk: bootstrap's stale "TS/Mumble
  hidden until rewritten" comments stripped — the GUI picker offers both
  natively (gui/theme.go platform list); AGENTS.md §8 LIVE stands.
- Machine truth learned the hard way: this VM has a 4GiB cgroup and gotd/td/tg
  peaks 3.2GB RSS compiling even with -gcflags=all=-c=1 → native gotd legs
  OOM-kill (dmesg evidence). gate.sh learned an honest fallback: compile-OOM
  → one explicit "SKIP (§9.7 — dispatch verify.yml)" line, every other
  failure stays hard. verify.yml dispatched via API (run 41152637658,
  in_progress at yield) — the native proof for this session's Go commits.
  js legs are real and green here (gui 1.707s via wasm runner).
- Tooling quirk logged: the Edit tool space-normalizes tab-indented Go files
  on rewrite — always gofmt -w after edits + run the gate (it caught this).
- Next: read the CI run, then P0 chunk 2.

## Session 328 — gate.sh landed; R10 closed; toolchain recovered (2026-10-31)

Sandbox recycle wiped Go + PATH + the web-test node_modules. Recovery: go 1.27.0
installed at my-project/toolchain/go (survives recycles); module cache moved to
my-project/toolchain/mod (1.2G, same reason); env recipe in
my-project/toolchain/env.sh (PATH/GOMODCACHE/GOCACHE/GOFLAGS/GOMEMLIMIT/GOGC).
Repo's scripts/devroot-setup.sh covers the CGO sysroot case (needed only for
native gui builds, which the gate does not do).

- scripts/gate.sh (§9 first-commit rule): quick = gofmt + vet + test on changed
  packages since base AND their importer closure (test imports count as edges),
  split native/js legs exactly like dev-test.sh; full = all tiers except
  live/owner incl. cross-builds + web E2E (explicit SKIP lines, never silent);
  web = wasm build + Puppeteer suite. Untracked .go files scope too (new files
  are the common case). go/third_party/anet (nested module) warns, not gates.
- VERIFIED BY DRIVING IT, not by reading it: probe test in qrscan (uncommitted,
  deleted after) → quick selected uniclient/qrscan + gui + cmd/uniclient (the
  correct importer closure, correct native/js split), native test ok 0.021s,
  js test ok 1.651s via wasm runner, quick gate GREEN; clean tree → trivially
  green. The probe caught TWO real bugs pre-landing: (1) git diff ignores
  untracked files — new code was invisible to the gate; (2) go list -f does
  NOT interpret \t (literal backslash-t in output) so the awk tab-split never
  matched — the gate would have green-lit everything; format now built with
  printf. Long compiles die with the tool call (sandbox reaps processes
  between calls) — build cache carries progress across runs; gotd-js toll
  paid once, warm now.
- R10 CLOSED (verified not-a-bug, no code change): every web-reachable matrix
  call site registers OnICECandidate→sendICECandidates BEFORE the
  GatheringCompletePromise wait (1:1 offer 1224→1254; 1:1 answer pc@3692+
  trickle@3730, AcceptCall@1543; group 413→432 and 514→544). On js the SDP
  ships immediately and candidates trickle — browser-native behavior.
  Telegram/DeltaChat callers never run on web (TCP). Evidence in BUGS Fixed.
- Evidence: /tmp/gate-quick.log (scoped run GREEN, exit 0), git status clean
  post-probe, BUGS.md/WORKLOG.md updated in the same commit.
- Web tier restored and verified: npm ci (puppeteer postinstall blocked by npm
  policy, but Chrome-for-Testing 148 found + verified, cache relocated to
  my-project/toolchain/puppeteer-cache, PUPPETEER_CACHE_DIR in env.sh);
  gate.sh web GREEN (exit 0): wasm build + s-tier + b1-b6 against real Chrome.
- Next: P0 chunk 1.

## Session 327 — constitution v3.2: the self-test law (2026-10-31)

Owner directive: "test yourself, not [just] writing unit tests — add to AGENTS.md."

- Law 21 sharpened from "no unplayed GUI" to "the agent IS the tester": user-facing
  behavior is proven only by driving the real app yourself — a Puppeteer journey on
  the real wasm (console clean) or native Xvfb screenshots actually looked at — and
  saying what was seen. A green unit suite over an undriven GUI is NOT done; more
  unit tests never substitute for playing the change.
- §3 evidence rule widened gui/ → user-facing, plus "a green unit suite is not
  evidence a UI works".
- File: 301 lines (≤~300 budget, held within noise).
- Push: main 455ba54..4013491 — token from the owner's out-of-band paste, used
  transiently (credential helper, never printed/filed/URL'd); F-93 closed. First
  attempt failed on an empty password (env var lost between shell calls), not on
  the token — per-candidate dry-run proved the credential good. download/ bundle
  + patch deleted as superseded.
- Next: scripts/gate.sh → R10 → P0 chunk 1.

## Session 326 — constitution v3.1: the four weaknesses, fixed in-file (2026-10-31)

Owner directive: the agent had reported AGENTS.md's weaknesses (unenforceable prose,
no yield metric, playtest gap — "code reaches my GUI broken because it is not
playtested"); fix them inside the file itself, without the owner.

- Law 21 "No unplayed GUI — the owner is never the playtester": every gui/ change
  must be DRIVEN before it counts — the real wasm through a Puppeteer journey that
  exercises the change (console clean), or native under Xvfb with a screenshot
  actually looked at. No journey → write the journey first. Sandbox can't run it →
  BLOCKED-env in BUGS.md, never claimed "works".
- §3 evidence rule extended: for gui/ changes the evidence is a driven journey
  (E2E transcript or screenshot + what was seen), never "the logic looks right".
- §0.5 + §9: a clean turn-end now requires gate green; scripts/gate.sh must exist
  from the first session on (that session's first commit if missing) — enforcement
  executable, not remembered.
- §4 yield steering: each P2 sweep records its finding count here; two consecutive
  zero-finding sweeps redirect effort to §7 parity rows, features, P4 PERF.
- Header mandate compressed 2 lines to hold the ≤~300-line budget (final: 299).
- Evidence: docs-only — diff reviewed, law list append-only (21 added, 16-20
  unshifted, code cross-refs intact), wc -l = 299.
- Push BLOCKED: GH_TOKEN absent from env, no gh CLI, no stored credentials (verified);
  commits 3206776 + this one preserved outside the repo as download/uniclient-326.bundle
  (git bundle, verified) and download/uniclient-326.patch — owner can pull/apply or a
  future session with a token pushes. Zero code touched; no secrets in either file
  (bundle carries only repo objects).
- Next: scripts/gate.sh → R10 → P0 chunk 1.

## Session 325 — constitution v3 (2026-10-31)

Owner directive: one perfect AGENTS.md — endless "continue" loop, least words,
no context blowups, history out of the constitution. Merged the live file with
the three draft constitutions (owner paste) and the four failure-mode fixes
(chunked P0, execution mandate, comment carve-outs, blessed test triad).

- AGENTS.md rebuilt: new §0 boot/mandate, §3 atomic loop (3-strike, evidence
  rule, never-weaken-tests), §4 endless hardening cycle (gates, cycle+1→P2),
  §9 ladder + gate.sh plan; law items 16-20 added (severity, comments, deps,
  untestable, judgment). Section numbers §1.x/§2/§7/§8/§9 preserved — the 29
  code-comment cross-references stay true, zero code edits needed.
- WORKLOG: STATE block added at the top (this block).
- BUGS.md: stale open rows R5/R6 pruned (both were fixed in cycle 1 as
  F-91/F-92; the Fixed rows carry the evidence). Open: R9 (owner decision),
  R10.
- Repo visibility: private → public again (owner instruction — free-tier web
  testing). Pages serving remains disabled (owner action 2026-10-30; gh-pages
  branch intact); the E2E --live tier skips until re-enabled.
- Evidence: verified against a fresh clone (workflows, scripts/web-test,
  dev-test.sh, Makefile, BUGS/WORKLOG/research cross-refs); docs-only change.
- Next: R10, then P0 chunk 1.

## Session 324 — web hardening pass (2026-10-30/31, complete)

Owner instruction: run the phased production-hardening prompt **against
the web target**; free choice of test interface ("do whatever you want
for test interface"); **use puppeteer**; reset/update AGENTS.md (the
owner then deleted AGENTS/WORKLOG/BUGS mid-session — this file and the
fresh AGENTS.md/BUGS.md are the reset). Full phase log lives in
`research/web_hardening_2026-10.md`.

- **Phase 0 (recon, read-only):** web-surface map, platform truth table
  (only github/matrix/bale can connect from a browser), 8 critical
  journeys, 10 risk zones (R1 two-tab vault clobber … R10) — written to
  the research doc. Measured: wasm = 88.5 MB, ~20 MB gz transfer on
  gh-pages.
- **Phase 1 (safety net):** puppeteer suite under `scripts/web-test/`
  (12 shell tests on the EXACT bytes CI ships, extracted from release.yml;
  6 real-app tests incl. vault decryption for exact account counts).
  Also repaired the standing gates: aacaud ffmpeg pins per-major-version
  (local ffmpeg 7 false-failed the provenance check), gui js/wasm test
  leg (was `undefined: waitFor` — broken since stream_guards_test.go
  landed, invisible to CI), js skips for filesystem-reading tests.
  Everything green; pushed (e7cb54a6..bb799595 window).
- **Phase 2 (correctness, one bug per iteration, red-first):**
  - F-87 (R1, data loss): two tabs clobbered the web vault — fixed with
    flush-time cross-instance merge (js hook re-reads+merges the
    persisted vault; native no-op behind the lock file). Unit tests +
    b6 E2E flipped red→green.
  - R2/R3 (audio/webaudio_js mic failure-path leaks, unused micRate),
    R4 (web picker offers TCP-impossible backends), R5 (no post-boot
    crash surface in the shell), R6 (observer accumulation) — queued.

**Phase 2 (correctness, red-first, one bug per iteration):** all six
web findings fixed — F-87 two-tab vault clobber (merge-before-flush),
F-88 getUserMedia failure-path leak (per-attempt ownership), F-89 mic
rate read off the wrong object + no resample (AudioBuffer + streaming
resample; the read was a first-real-callback panic), F-90 web picker
offered TCP-impossible backends (js shows github/matrix/bale only),
F-91 no crash surface after canvas attach (window error/rejection →
overlay+Retry), F-92 observer accumulation (one tracked bootObs).
R10 audited: not a bug (trickle contract, comment corrected).
- **Phase 3:** comment/doc lies fixed (vault storage key, phantom
  IndexedDB host layer, XMPP "mellium" picker copy); dead-code deletion
  of vaultPathExists REVERTED by the suite — VaultExists→engine.Init
  uses it (usage analysis must catch wrappers).
- **Phase 4 (measured):** shell boot steady heap 88→3 MB (module bytes
  released post-instantiate — they were pinned for the app lifetime),
  download peak 170→133 MB (in-place assembly); instantiateStreaming
  REJECTED with numbers (compile is only ~200 ms). Harness:
  scripts/web-test/measure-boot.mjs.
- **Phase 5:** #status live region + noscript fallback (s15);
  below-fold-Bale resolved-by-design (scrollable List).
- **Phase 6:** secret sweep clean, zero DOM sinks (canvas = no HTML
  injection surface), scheme-allowlisted link opening; R9 (web vault
  fixed default password) needs an OWNER decision — held open.
- **Phase 7:** full battery green (gofmt/vet/vet-live/14-pkg suite/
  race legs/dev-test/15-shell/6-app/YAML). PRODUCTION: GitHub Pages
  serving is currently DISABLED on the repo (owner action ~22:00 UTC,
  gh-pages branch intact, Pages API 404) — the live tier skips with
  that reason; re-enabling + cutting v0.10.4 left to the owner.

Next (owner): re-enable Pages and cut v0.10.4 to ship the hardening;
decide R9 (web vault password); the standing owner-only rungs (live
sign-ins, first non-prerelease). Next (agent): continue from BUGS.md
open rows; the puppeteer suite now guards every web-touching change.
