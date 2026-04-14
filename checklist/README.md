# Uniclient — Build Checklist

**Status (updated 2026-04-14, Step 9 in progress):**
All 10 platform cores implemented with 4,079 exported methods (down from 4,350 after Step 8 dedup). Steps 1-8 DONE. Step 9 testing in progress: ~35,000 lines of comprehensive test code across 11 files. Results so far: TeamSpeak 41 PASS. Telegram 61 PASS, 2 SKIP. Bale 106 PASS, 16 SKIP. Mumble 117 PASS, 10 FAIL (diagnosed — fixes ready). XMPP 95+ PASS, 0 FAIL (still running). IRC, DeltaChat, GitHub, Matrix, Rubika still running.

## Index

| File | Methods | Lines | Status |
|------|---------|-------|--------|
| [telegram.md](telegram.md) | 893 | 15,326 | **DONE** — all gotd/td methods wrapped, calls verified bidirectional |
| [github.md](github.md) | 855 | 6,663 | **DONE** — full REST API (Actions, Repos, Apps, Codespaces, Orgs, Security) |
| [irc.md](irc.md) | 553 | 5,629 | **DONE** — RFC 1459/2812 + IRCv3 + oper + DCC + extended bans |
| [xmpp.md](xmpp.md) | 467 | 7,881 | **DONE** — RFC 6120/6121 + ~200 XEPs, Jingle, OMEMO, MUC, MIX |
| [mumble.md](mumble.md) | 381 | 7,814 | **DONE** — client protocol + Ice RPC admin + audio + authenticator |
| [teamspeak.md](teamspeak.md) | 369 | 6,754 | **DONE** — full TS3 UDP client + ServerQuery |
| [bale.md](bale.md) | 368 | 6,194 | **DONE** — bot API + user API + LiveKit calls |
| [rubika.md](rubika.md) | 329 | 5,698 | **DONE** — encrypted WebSocket + WebRTC voice |
| [matrix.md](matrix.md) | 293 | 6,409 | **DONE** — CS API + E2EE (OMEMO/Megolm) + VoIP |
| [deltachat.md](deltachat.md) | 283 | 7,469 | **DONE** — IMAP/SMTP + Autocrypt + config + multi-account |
| [flutter.md](flutter.md) | — | — | **NOT STARTED** — UI framework |
| [gui.md](gui.md) | — | — | **IN PROGRESS** — UI design spec (demo_ui.html) |

**Totals:** 4,791 functions, 76,218 lines, 62-method Core interface, 24 capability constants.

---

## Roadmap Progress

| Step | Description | Status |
|------|-------------|--------|
| 1 | Implement unimplemented checklist methods | **DONE** |
| 2 | Test ALL existing methods in every core | **DONE** |
| 3 | Replace checklists with full protocol surface | **DONE** |
| 4 | Implement all new methods to 100% | **DONE** |
| 5 | Perfect/optimize/decouple cores | **DONE** |
| 6 | Unify core APIs | **DONE** |
| 7 | Complete Telegram & Matrix method coverage | **DONE** |
| 8 | Fresh checklists + dedup + implement + optimize | **DONE** |
| 9 | Test every core (official harnesses, multi-account) | **IN PROGRESS** |
| 10 | Fresh checklists + optimize every core + retest | NOT STARTED |
| 11 | Unify every core | NOT STARTED |
| 12 | Test every unified method | NOT STARTED |
| 13 | Protobuf bridge | NOT STARTED |
| 14 | Write /docs | NOT STARTED |
| 15 | Build GUI | NOT STARTED |

See [roadmap.md](roadmap.md) for detailed progress on each step.

---

## Integration Tests
- [x] Full encryption pipeline: compose → split → compress → encrypt → send → receive → decrypt → decompress → reassemble → verify
- [x] Full encrypted file pipeline: file → compress → encrypt → split → send → receive → reassemble → decrypt → decompress → verify byte-identical
- [x] Vault lifecycle: create → store → close → reopen → verify → export → delete → import → verify
- [x] Cross-core isolation: init 10 cores → verify names, unauthenticated ops, independent shutdown
- [x] File split round-trip at exact Bale 19.5MB boundary (exact, +1, 2x, 2x+1)
- [x] Independence build: compile each core in isolation — verify no cross-core deps
