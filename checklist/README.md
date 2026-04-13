# Uniclient — Build Checklist

Checked items removed. Only remaining work listed.

**Status (updated 2026-04-13, Step 1 near-complete):**
All 11 platform cores implemented (64,801 lines Go). 8/10 cores fully implemented. Remaining: Rubika (+36), Mumble (+7 Ice RPC stubs). Integration tests: 6/6 pass. Flutter UI not started. Total exported methods: ~2,690.

## Index

| File | Phase | Exported | Not Added | Status |
|------|-------|----------|-----------|--------|
| [telegram.md](telegram.md) | Phase 1-2 | 769 | — | **DONE** — calls trimmed to 3 versions (v13 SCTP, v8 V2Impl, v4 Web), all verified bidirectional. SFU group. |
| [bale.md](bale.md) | Phase 3 | 267 | — | **ALL IMPLEMENTED** — 105 extended methods added, not yet tested |
| [rubika.md](rubika.md) | Phase 4 | 189 | +36 | **CORE DONE** — 36 from rubpy/RubikaLib/Rubino not in core |
| [deltachat.md](deltachat.md) | Phase 5 | 135 | — | **ALL IMPLEMENTED** — 43 extended methods added, not yet tested |
| [teamspeak.md](teamspeak.md) | Phase 6 | 210 | — | **ALL IMPLEMENTED** — 38 extended methods added, not yet tested |
| [matrix.md](matrix.md) | Phase 7 | 167 | — | **ALL IMPLEMENTED** — 64 extended methods added, not yet tested |
| [mumble.md](mumble.md) | Phase 9 | 133 | +7 | **CORE DONE** — 7 Ice RPC admin methods need real implementation |
| [github.md](github.md) | Phase 10 | 246 | — | **ALL IMPLEMENTED** — 190 extended methods added, not yet tested |
| [irc.md](irc.md) | Phase 11 | 340 | — | **ALL IMPLEMENTED** — 95 extended methods added, not yet tested |
| [xmpp.md](xmpp.md) | Phase 12 | 279 | — | **ALL IMPLEMENTED** — 101 extended methods added, not yet tested |
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
