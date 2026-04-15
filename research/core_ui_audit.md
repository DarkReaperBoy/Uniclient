# Core-to-UI Audit — Bugs Found and Fixed (2026-04-15)

Comprehensive audit of the Go engine ↔ Flutter UI bridge. Five parallel agents scanned: auth flows, proto mapping, event delivery, method wiring, and data model consistency.

## Fixed (18 bugs)

### Critical
1. **Download state mismatch** — Go: `Complete=2, Failed=3`. Dart had `done=3, failed=4`. `isMediaDownloaded` was checking `== 3` (Go's failed). Fixed: Dart now checks `== 2`.
2. **TeamSpeak server key mismatch** — `buildAuthConfig()` used `Extra["server"]`, core reads `Extra["server_address"]`. Users always silently got localhost. Fixed: engine now sets `Extra["server_address"]`.
3. **FFI event use-after-free** — Go's `BridgeSetEventCallback` freed `C.CBytes` pointer immediately after `invoke_event_callback()`, but Dart's `NativeCallable.listener` reads asynchronously. Every bridge event arrived with 16 bytes of heap garbage + corrupted data. All events silently dropped. Fixed: Go no longer frees; Dart frees via `malloc.free()` after copying.

### High
3. **`user_status` events silently dropped** — Go emitted online/offline, Dart had no handler. Fixed: added `UserStatusEvent` model, stream controller, dispatch case.
4. **`retryPending` was synchronous** — Blocked UI during network I/O. Fixed: now `Future<void>` using `_callAsync`.
5. **`connectAllAccounts()` error silently lost** — Future not awaited/caught. Fixed: added `.catchError()` with logging.
6. **`sendMessage`/`editMessage` errors not caught** — Input cleared before confirming, error unhandled, text lost. Fixed: `.catchError()` restores text and shows SnackBar.
7. **`deleteMessage`/`requestDownload` Futures unhandled** — Failures silent. Fixed: added `.catchError()` with SnackBar feedback.
8. **Auth error screen showed blank** — `_buildErrorState` read `auth.error` but Go populated `auth.message`. Fixed: now checks `message` first, falls back to `error`.

### Medium
9. **`content_raw`/`content_rich` proto fields dropped** — Go populated tags 8-9, Dart ignored them. Rich text formatting lost. Fixed: added fields to `CachedMessage`, wired in `_cachedMsgFromProto`.
10. **`_handleChatRemoved` ignored accountId** — Cross-account ID collision could remove wrong chat. Fixed: `ChatRemovedEvent` now carries `accountId`, removal filters by both.
11. **Download events not connected to state** — `onDownloadComplete` never subscribed. Fixed: `ChatState` now handles it, updates `mediaLocalPath` and `mediaDownloadState`.
12. **`editMessage`/`deleteMessage` didn't refresh local state** — Relied on event or 3s poll. Fixed: optimistic local updates after engine call.
13. **Zero timestamp guard was dead code** — `time.Time{}.UnixMilli()` returns `-62135596800000`, not `0`. Fixed: now uses `msg.Timestamp.IsZero()`.
14. **`_handleBridgeEvent` catch-all swallowed errors** — No logging. Fixed: now logs error + stack trace via `Debug.error`.
15. **`qrExpiresIn` missing from Dart model** — Proto field populated by Go, never read. Fixed: added to `AuthStateData` and `_authStateFromProto`.
16. **IRC auth key mismatch** — `buildAuthConfig()` used `Extra["nickname"]`, core expected `Extra["nick"]`. Fixed earlier in session.
17. **Download state test was wrong** — Test asserted `== 3` for downloaded. Fixed to match Go constant `== 2`.

## Integration Test Results (flutter_render_test.dart)

Full pipeline test: Go engine → FFI → proto → Dart models → Provider → Flutter widgets. **20/20 passed.**

| Platform | Login | Chats | Messages | Widget Render |
|---|---|---|---|---|
| IRC | OK | 0 (no channels joined) | — | OK |
| GitHub | OK | 1 ("nahbad") | 10 | OK |
| XMPP | OK | 0 (fresh account) | — | OK |
| Telegram | SKIP (OTP) | — | — | — |
| DeltaChat | OK | 1 | 50 | OK (timestamps validated) |
| Matrix | OK | 0 (no rooms) | — | OK |
| Mumble | OK | 1 ("Root") | 0 (voice) | OK |
| TeamSpeak | OK | 2 channels | 0 (voice) | OK |

Widget render tested at: 400px (mobile), 1200px, 1400px (desktop). HomeScreen, chat list, message view, voice channels all render without crashes.

## Not Fixed (known, low priority)

- **`incoming_call`/`call_state` events** — No call UI exists yet, will add when call screen is built.
- **`GetMessageRaw` has no Dart wrapper** — Go dispatch exists, no Dart consumer yet.
- **`parentTitle`/`reactions` phantom fields** — Exist in Dart model, never populated via proto. Will be wired when engine supports them.
- **`isSent` conflates "our message" with "no sender"** — System messages may appear as sent. Needs a distinct `is_outgoing` flag from Go.
- **Pushed auth events wipe UI fields** — `AuthStateEvent` only carries 4 fields. Would need Go to push full auth state proto instead of JSON subset.
- **`_refreshMessages` merge edge case** — Paginated messages near boundary could be discarded. Rare in practice.
