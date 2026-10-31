# WORKLOG.md — the session journal

Top: the **STATE block** — rewritten every session, the resume pointer for the
next agent. Below: one entry per work session, newest first. This is the
resume-from-zero mechanism. (The pre-2026-10 history was deleted by the owner
on 2026-10-30 — it lives in git history if ever needed.)

## STATE

- cycle: 2 | phase: P0 (chunked recon; web surface closed in cycle 1)
- item: P0 chunk 1 DONE (cmd/uniclient + bootstrap → MAP.md); verify.yml run 41152637658 in flight
- next: read verify.yml run 41152637658 (native-gotd proof of the bootstrap comment strip) → P0 chunk 2 (gui state/mutex surfaces, one package per iteration)
- owner-waiting: re-enable Pages + cut v0.10.4; R9 web-vault decision; real-account sign-ins; first non-prerelease
- last-gate: quick GREEN (js legs real; native legs explicit §9.7 OOM skip → CI run 41152637658)

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
