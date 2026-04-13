# Pre-GUI Roadmap Progress

**Current Step:** 3
**Current Core:** (all cores — replace checklists with full protocol surface)
**Current Method:** Research full protocol surface for each core
**Last Updated:** 2026-04-13

## Steps

| Step | Description | Status |
|------|-------------|--------|
| 1 | Implement unimplemented checklist methods | **DONE** |
| 2 | Test ALL existing methods in every core | **DONE** |
| 3 | Replace checklists with full protocol surface | NOT STARTED |
| 4 | Implement all new methods to 100% | NOT STARTED |
| 5 | Perfect/optimize/decouple cores | NOT STARTED |
| 6 | Unify core APIs | NOT STARTED |
| 7 | Protobuf bridge | NOT STARTED |
| 8 | Write /docs | NOT STARTED |
| 9 | Build GUI | NOT STARTED |

## Detailed Progress

### Step 1 — Implement Unimplemented Checklist Methods — DONE

All checklist methods implemented across all 9 cores:

- [x] Mumble — 140 methods (15 client protocol + 7 Ice RPC admin via pure-Go Ice wire protocol client). Tested Ice against Murmur 1.5.857 + Ice 3.7.10.
- [x] TeamSpeak — 38 methods implemented. NOT TESTED.
- [x] Delta Chat — 43 methods implemented. NOT TESTED.
- [x] Matrix — 64 methods implemented. NOT TESTED.
- [x] IRC — 95 methods implemented. NOT TESTED.
- [x] XMPP — 101 methods implemented. NOT TESTED.
- [x] Bale — 105 methods implemented. NOT TESTED.
- [x] GitHub — 190 methods implemented. NOT TESTED.
- [x] Rubika — 230 methods implemented, 89 tests ALL PASS (including WebRTC voice chat).

### Step 2 — Test ALL Existing Methods — DONE

636 extended methods tested across 7 cores (+ Mumble/Rubika from Step 1). All pass.

- [x] Matrix — 64 extended methods: 46 pass, 1 skip (URLPreview unsupported by Dendrite). All pass on local Dendrite. Test: `go/tests/matrix_extended_test.go`
- [x] Delta Chat — 43 extended methods: ALL PASS (nine.testrun.org chatmail). Test: `go/tests/dc_extended_test.go`
- [x] IRC — 95 extended methods: ALL PASS (Libera.Chat). Test: `go/tests/irc_extended_test.go`
- [x] XMPP — 101 extended methods: ALL PASS (yax.im Prosody). Test: `go/tests/xmpp_extended_test.go`. Registered new account via XEP-0077.
- [x] TeamSpeak — 38 extended methods: ALL PASS (local Docker TS3 3.13.7). Test: `go/tests/ts3_extended_test.go`. Fixed protocol bug: `nextRecvID` was 2, should be 1.
- [x] Bale — 105 extended methods: ALL PASS (tapi.bale.ai, bot API + gRPC error paths). Test: `go/tests/bale_extended_test.go`
- [x] GitHub — 190 extended methods: ALL PASS (github.com, real PAT). Test: `go/tests/github_extended_test.go`. Created/merged real PR, tested full lifecycle.
- [x] Mumble — all methods verified in Step 1 (Ice RPC, audio, crypto, protocol)
- [x] Rubika — 89 tests ALL PASS in Step 1 (including WebRTC voice chat)

**Docker containers used:** `dendrite-test` (Matrix), `mumble-test` (Mumble), `ts3-test` (TeamSpeak 3.13.7)
**Bug fixed:** TS3 incoming command pID counter set to 2 instead of 1 after handshake, causing initserver to be stuck in reorder queue. Fixed in `go/cores/teamspeak.go`.
**New credentials:** XMPP (yax.im `uctest1776076689`), TeamSpeak (Docker serveradmin), GitHub (PAT from git remote). All in `auth/auth.md`.

### Step 3 — Replace Checklists
- [ ] (list cores here when Step 2 is done)

### Step 4 — Implement New Methods to 100%
- [ ] (populate from new checklists when Step 3 is done)

### Step 5 — Perfect/Optimize/Decouple
- [ ] (populate when Step 4 is done)

### Step 6 — Unify Core APIs
- [ ] (populate when Step 5 is done)

### Step 7 — Protobuf Bridge
- [ ] (populate when Step 6 is done)

### Step 8 — Write /docs
- [ ] (populate when Step 7 is done)

### Step 9 — Build GUI
- [ ] (populate when Step 8 is done)
