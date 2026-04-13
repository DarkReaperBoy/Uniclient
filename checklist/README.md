# Uniclient — Build Checklist

**Status (updated 2026-04-13, Step 3 complete):**
All 11 platform cores implemented. Steps 1-3 DONE. Full protocol surface researched for all cores — ~790 missing methods identified across 9 cores. Telegram already at full coverage (769 methods wrapping all 685 gotd/td). Flutter UI not started.

## Index

| File | Implemented | Missing | Status |
|------|-------------|---------|--------|
| [telegram.md](telegram.md) | 769 | — | **DONE** — all 685 gotd/td methods wrapped, calls verified bidirectional |
| [bale.md](bale.md) | 304 | ~25 | **Step 3** — Bot commands (3), stubs (4), user API (3), chat mgmt (5), messages (5), exotic (5) |
| [rubika.md](rubika.md) | 270 | ~45 | **Step 3** — Auth (2), messages (2), groups (4), typed senders (7), Rubino (6), bot API (10), WS events (4) |
| [deltachat.md](deltachat.md) | 164 | ~105 | **Step 3** — Config (10), multi-account (7), chat props (17), msg props (30), contacts (13), QR (4), backup (5) |
| [teamspeak.md](teamspeak.md) | 248 | ~80 | **Step 3** — Instance mgmt (6), notifications (13), 3D audio (4), devices (8), preprocessing (5), wave (4) |
| [matrix.md](matrix.md) | 218 | ~90 | **Step 3** — Auth (7), rooms (4), profiles (4), admin (5), media (7), MatrixRTC (6), E2EE (8) |
| [mumble.md](mumble.md) | 246 | ~111 | **Step 3** — Meta Ice (11), Server Ice (~37), callbacks (9), authenticator (10), client (15), audio (4) |
| [github.md](github.md) | 299 | ~800 | **Step 3** — Actions (169), Repos (171), Apps (37), Codespaces (48), Copilot (25), Orgs (98), etc. |
| [irc.md](irc.md) | 399 | ~130 | **Step 3** — Oper cmds (46), IRCv3 (19), SASL (3), DCC (2), extended bans (18), modes (30) |
| [xmpp.md](xmpp.md) | 322 | ~120 | **Step 3** — Connection (10), messaging (12), MUC (11), MIX (5), Jingle (18), PubSub (15) |
| [flutter.md](flutter.md) | — | — | **NOT STARTED** — UI framework |
| [gui.md](gui.md) | — | — | **IN PROGRESS** — UI design spec (demo_ui.html) |

---

## Phase 0: Foundation

### Nix Flake
- [ ] `flutter doctor` passes (or only has expected warnings) in `nix develop`

### Go Bridge (`go/bridge/`)
- [ ] Event port setup (NativePort for Go→Dart events)

---

## Integration Tests
- [x] Full encryption pipeline: compose → split → compress → encrypt → send → receive → decrypt → decompress → reassemble → verify ✓ TestIntegrationFullEncryptionPipeline
- [x] Full encrypted file pipeline: file → compress → encrypt → split → send → receive → reassemble → decrypt → decompress → verify byte-identical ✓ TestIntegrationFullEncryptedFilePipeline
- [x] Vault lifecycle: create → store → close → reopen → verify → export → delete → import → verify ✓ TestIntegrationVaultLifecycle
- [x] Cross-core isolation: init 7 cores → verify names, unauthenticated ops, independent shutdown ✓ TestCrossCoreIsolation
- [x] File split round-trip at exact Bale 19.5MB boundary (exact, +1, 2x, 2x+1) ✓ TestIntegrationFileSplitBale195MB
- [x] Independence build: compile each core in isolation — verify no cross-core deps ✓ TestCoreIndependence (7 cores, all instantiate + report capabilities)
