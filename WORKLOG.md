# WORKLOG — Uniclient

Every agent session appends one entry at the bottom. Format:
`## <date> — <session title>`, then what was done, decided, and left over.
The most recent entry is the current state of the project.

---

## 2026-09-07 — Restore the build, make wasm real, prove the FFI works

Session goal (owner): "build up the project, fix/continue, work until it is
fully done, push to GitHub. The research files could be outdated or plain
hallucination so do your own research."

### What I found

- Repo state at session start: the Flutter frontend had been stripped
  (61945478), go.mod/go.sum and build scripts deleted (498f5d9e), leaving
  ~529k lines of Go (373k generated proto) that could not build at all.
  AGENTS.md (fa32b30b) described a *future* project ("Code: none yet") whose
  plan did not match the code that was actually present.
- Executed my own dependency research against the module proxy (per owner's
  instruction to distrust the research files): gotd/td v0.161.0, mautrix
  v0.30.0, pion v4 current line, protobuf v1.36.12, modernc sqlite v1.58.0.
  The research files' version claims turned out accurate (Go 1.27.1 is
  current stable per go.dev).

### What I did

1. **Restored the build.** Recreated go.mod via `go mod tidy` (module
   `uniclient`, Go 1.27); fixed two API-skew compile errors:
   pion/ice/v4 v4.4.2 moved stun/v3→v4 (same URI API), and gotd v0.152+
   replaced `SetChangeTone` with `InputAiComposeToneDefault{Tone}`.
   Discovered the **goolm requirement**: mautrix's default Olm is cgo;
   `-tags goolm` selects the pure-Go implementation. Build + vet green,
   including `CGO_ENABLED=0` (pure-Go claim verified, not assumed).
2. **Made the js/wasm target buildable** (it never had been — the old
   build script had it hard-failing as "NOT CURRENTLY BUILDABLE"). Added
   `go/wrtc` compat package: type/func aliases to pion/webrtc on native
   (zero-cost, single code path), compile-only stubs on js/wasm for the
   native-only media surface. Split bale/rubika websocket dials and the
   telegram DTLS/transceiver debug chains into `_js.go`/`_native.go`
   files following the repo's existing bale_calls_js.go pattern.
3. **Found and fixed a real architecture bug in the wasm bridge**: a
   synchronous JS→Go `bridgeCall` deadlocks ("all goroutines are asleep")
   as soon as the engine does blocking fs work (vault/config), because
   syscall/fs_js callbacks cannot fire while the JS stack is stuck inside
   the call. `bridgeCall` now returns a Promise and dispatches on its own
   goroutine. This is a wire-contract change: web hosts must `await`.
4. **Test suite** (none existed): utils crypto/vault (round-trips, wrong
   key, tamper, persistence, export/import), IRC parser (RFC2812+IRCv3
   tags/prefix/trailing, standard replies), Bale pbEncode/pbDecode wire
   contract (varints→int64, nested+`__raw_N` ambiguity, repeated fields,
   deterministic field order, the real handshake frame), and the bridge
   FFI round-trip driving Init/ListAccounts/AddAccount/RemoveAccount/
   Shutdown exactly as a host does, plus error paths. All green.
   The suite caught one real bug: `categorizeError` bucketed FLOOD_WAIT
   as `auth` (bogus re-login prompt); rate limiting now categorizes first.
5. **FFI smoke suites against the real artifacts** (not just compilation):
   `scripts/smoke/smoke_c.c` drives the c-shared .so through
   BridgeCallWithLen/BridgeFree — full lifecycle PASSED.
   `scripts/smoke/smoke_wasm.mjs` (+run_wasm.mjs) drives the .wasm under
   Node with the Node fs globals — same lifecycle PASSED, including vault
   persistence through Node's filesystem.
6. **Tooling**: Makefile (build/test/vet/lint/c-shared/wasm/cli/smoke),
   `scripts/build.sh` (linux/windows/darwin/android/web/cli targets),
   `.github/workflows/ci.yml` (native gate, race detector, platform matrix
   windows/darwin/linux × amd64/arm64 all CGO_ENABLED=0, wasm build +
   artifact upload, both smoke suites), README.md with the FFI contracts,
   and `go/cmd/cli` — a headless host binary for driving the engine from a
   terminal (verified live: add/list/status round-trip).

### Decisions

- Keep the bridge/cores architecture as-is (it is the actual code that
  exists); AGENTS.md's "internal/-first Gio rewrite" remains a future plan,
  not something to attempt in one session.
- `wrtc` shim instead of splitting call transports out of the 37k-line
  telegram.go: aliases preserve the single native code path (zero risk to
  native behavior) while making wasm compile; stubs return ErrUnsupported
  at runtime (media degrades, signaling works) — the repo's own established
  pattern from bale.
- bridgeCall on wasm is async (Promise) — unavoidable given single-threaded
  wasm + blocking fs; no frontend existed to break.
- CI runs `-race` on utils/cores/bridge only: gotd's tg package under -race
  exceeds small-runner RAM (verified locally on 4GB).

### Leftovers / next session

- Frontend: none exists. The AGENTS.md P0/P1 (Gio shell, loopback backend)
  or a web host on the wasm module are the natural next steps; the engine
  side of both contracts is now verified working.
- The research/*.md protocol notes for bale/rubika remain UNTESTED against
  live servers (geo-restricted) — unchanged from before.
- Proto regeneration tooling (scripts/gen_proto.sh + gen_bridge) was
  deleted in 498f5d9e and is NOT restored; the generated code is committed
  and builds, but regenerating requires rewriting those tools.
- ADR-007 (XMPP E2EE) and the other open decisions in AGENTS.md §15 still
  stand.

### Addendum (same session, later)

Live protocol verification against REAL servers (go/tests/, build tag
`live`, env-gated, now committed):

- **GitHub core vs api.github.com** with a real PAT: Authenticate verified
  via /user ("authenticated as DarkReaperBoy (Fallen Reaper)"), GetDialogs
  round-trip, background pollLoop — PASS.
- **IRC core vs irc.oftc.net:6697**: full TLS registration (NICK/USER →
  001), MOTD (35 lines), clean Logout — PASS.
- **Found+fixed by live testing**: IRC 465 (ERR_YOUREBANNED) stalled
  registration to the 30s timeout with a generic error. Libera bans
  datacenter IPs ("Your bot is not permitted"); the core now fails within
  seconds carrying the server's actual ban text, and the reconnect loop
  stops retrying permanent bans. Verified live against Libera (fails in
  ~6s with the real reason).

## Session 3 — CI repair + the desktop app (go/cmd/web)

### CI fix
- The race-detector job was the only red one: `CGO_ENABLED=0 go test -race`
  fails instantly — the race runtime on linux/amd64 requires cgo. Fixed to
  `CGO_ENABLED=1` (+30-min timeout). Verified green on GitHub runners
  (gotd/td's own CI compiles the same tg package under -race on
  ubuntu-latest, which is why it fits the 16GB runner but not the 4GB dev box).

### The desktop app: `uniclient-web` (go/cmd/web)
- Single binary: engine + local HTTP/WS API + embedded web UI (vanilla
  HTML/CSS/JS, go:embed, no frontend toolchain). Binds 127.0.0.1 only.
- Wires the engine through the bridge exactly like the FFI hosts
  (bridge.InitEngine), then drives the rich Go API directly.
- API: accounts (add/remove/connect/disconnect), the full interactive
  per-platform auth state machine (start/input/back/cancel + live state),
  chats (unified + per-account), messages (cache reads with live fallback),
  send (optimistic pending flow), mark-read, join-channel, QR rendering
  (rsc.io/qr, server-side PNG), /ws event stream (JSON EngineEvents).
- UI: account rail with status dots, chat list with unread badges, message
  bubbles (grouping, day dividers, reply quotes, media chips, status ticks),
  auth modal driven by the state machine (incl. Telegram QR login),
  new-chat/join modal, toasts. Verified in a real headless browser
  (agent-browser + VLM screenshot review): layout clean, no console errors.
- Second launch detects the running instance and just opens the browser.

### Live end-to-end verification (this session)
- **GitHub auth via the web API with the user's PAT**: full flow
  input→token→ready ("Fallen Reaper"), auto-reconnect after restart
  (vault-persisted), send pipeline: comment to issue #2 → msg_received +
  msg_status events over WS → read-back from the cache = the real comment.
- **IRC (irc.libera.chat)**: auth flow server→nick→(optional NickServ)→
  connected; joined #libera (1428 members) through the web API.
- Both OFTC (fresh autokill — test-connection spam) and Libera (pre-existing
  datacenter bot ban, dated 8/31) now k-line this dev box's IP; IRC live
  verification remains from Session 2 + the pre-ban checks above.

### Bugs found & fixed
- `engine.JoinChat` re-synced dialogs IMMEDIATELY after sending JOIN — the
  server's JOIN echo/353/366 arrive ~1s later, so the sync cached a list
  without the new channel and never re-synced. Now waits 3s.
- Server-origin IRC NOTICEs (auth banners, k-lines, "NOTICE AUTH") created
  junk DM chats named after the server host. They now route into a single
  "Server log" pseudo-chat (also surfaced in GetDialogs) — k-line text stays
  visible without polluting the chat list.
- Web events initially hooked `bridge.SetEventCallback` (protobuf
  BridgeEvent bytes) instead of the engine's JSON envelopes — browsers now
  get pure JSON via `eng.SetEventCallback(hub.broadcast)`.

### Tooling
- `scripts/smoke/smoke_web.sh`: headless web-host smoke (health, static UI,
  QR PNG magic, GitHub auth flow incl. a REAL bogus-token network
  round-trip, WS connect, second-launch dedupe, clean SIGINT shutdown).
  PASSED locally; wired into CI as its own job.
- `.github/workflows/release.yml`: tag `v*` → 6-platform matrix build
  (linux/windows/darwin × amd64/arm64) of uniclient-web + uniclient-cli
  with launchers (Start Uniclient.bat / uniclient.sh) + README, sha256s,
  auto-created GitHub Release.

### Leftovers / next session
- Telegram login UI flow is built (phone/OTP/2FA/QR) but unverified against
  a real phone account (needs the user's SIM). GitHub + IRC verified live.
- Avatars render as colored initials; media is read-only chips (no inline
  images / downloads yet).
- Bale/Rubika remain untested (geo-restricted), unchanged.
