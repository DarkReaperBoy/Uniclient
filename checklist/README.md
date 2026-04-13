# Uniclient — Build Checklist

Checked items removed. Only remaining work listed.

**Status (updated 2026-04-12, full API audit + method recount):**
All 11 platform cores implemented (56,073 lines Go). Full API audit done against official libs/specs — ~829 additional methods identified as not yet in core. Integration tests: 6/6 pass. Flutter UI not started. Total exported methods: 2,083.

## Index

| File | Phase | Exported | Not Added | Status |
|------|-------|----------|-----------|--------|
| [telegram.md](telegram.md) | Phase 1-2 | 769 | — | **DONE** — calls trimmed to 3 versions (v13 SCTP, v8 V2Impl, v4 Web), all verified bidirectional. SFU group. |
| [bale.md](bale.md) | Phase 3 | 162 | +144 | **CORE DONE** — 144 from Balethon/aiobale/web not in core |
| [rubika.md](rubika.md) | Phase 4 | 189 | +36 | **CORE DONE** — 36 from rubpy/RubikaLib/Rubino not in core |
| [deltachat.md](deltachat.md) | Phase 5 | 92 | +43 | **CORE DONE** — 43 from dc-core-rust/JSON-RPC not in core |
| [teamspeak.md](teamspeak.md) | Phase 6 | 172 | +38 | **CORE DONE** — 38 from TS3 protocol/SQ not in core |
| [matrix.md](matrix.md) | Phase 7 | 103 | +72 | **CORE DONE** — 72 from CS API spec/mautrix-go not in core |
| [mumble.md](mumble.md) | Phase 9 | 111 | +22 | **CORE DONE** — 22 from Mumble.proto/gumble not in core |
| [github.md](github.md) | Phase 10 | 56 | +230 | **CORE DONE** — 230 from REST API/GraphQL not in core |
| [irc.md](irc.md) | Phase 11 | 245 | +104 | **CORE DONE** — 104 from RFC/IRCv3/services not in core |
| [xmpp.md](xmpp.md) | Phase 12 | 178 | +123 | **CORE DONE** — 123+ from XEPs/RFCs not in core |
| [flutter.md](flutter.md) | Phase 8 | — | — | **NOT STARTED** — UI framework |
| [gui.md](gui.md) | Phase 8 | — | — | **IN PROGRESS** — UI design spec (demo_ui.html) |

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
