# Uniclient — Build Checklist

**Status (updated 2026-04-13, Step 6 complete):**
All 10 platform cores implemented with 4,791 functions across 76,218 lines of pure Go. Steps 1-6 DONE. All cores at 100% protocol coverage, optimized, decoupled, and unified with 62-method Core interface + 24 capability constants. Flutter UI not started.

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
| 7 | Protobuf bridge | NOT STARTED |
| 8 | Write /docs | NOT STARTED |
| 9 | Build GUI | NOT STARTED |

See [roadmap.md](roadmap.md) for detailed progress on each step.

---

## Integration Tests
- [x] Full encryption pipeline: compose → split → compress → encrypt → send → receive → decrypt → decompress → reassemble → verify
- [x] Full encrypted file pipeline: file → compress → encrypt → split → send → receive → reassemble → decrypt → decompress → verify byte-identical
- [x] Vault lifecycle: create → store → close → reopen → verify → export → delete → import → verify
- [x] Cross-core isolation: init 10 cores → verify names, unauthenticated ops, independent shutdown
- [x] File split round-trip at exact Bale 19.5MB boundary (exact, +1, 2x, 2x+1)
- [x] Independence build: compile each core in isolation — verify no cross-core deps
