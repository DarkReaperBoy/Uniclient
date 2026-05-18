# GUI Audit — Cycle 1 Phase Ayugram (2026-05-18 21:51)

## Code Comparison (Dart vs AyuGram)

# bridge — Platform-specific FFI/WASM bridge to Go backend

## Issues Found

### [CRITICAL] Web bridge uses `assert()` instead of error throw — breaks in release builds
- **File:** `dart/lib/bridge/bridge_web.dart:37`
- **Issue:** The check `assert(_initialized, '...')` is stripped in release builds. The function will try to call uninitialized JS interop functions, causing cryptic JS errors instead of a clear error message.
- **Fix:** Change to match FFI pattern (line 70 in `bridge_ffi.dart`):
  ```dart
  // WRONG (current):
  assert(_initialized, 'Bridge not initialized. Call init() first.');
  
  // RIGHT (FFI pattern):
  if (!_initialized) {
    throw StateError('Bridge not initialized. Call init() first.');
  }
  ```
- **Severity:** CRITICAL — the code appears to work in debug builds but silently fails in release

### [MAJOR] Missing initialization check in `call()` — no guard for uninitialized state
- **File:** `dart/lib/bridge/bridge_web.dart:36-42`
- **Issue:** After fixing the assertion, also add the same guard to `call()`:
  ```dart
  Uint8List call(Uint8List requestBytes) {
    if (!_initialized) {
      throw StateError('Bridge not initialized. Call init() first.');
    }
    // ... rest of method
  }
  ```
- **Severity:** MAJOR — if init() is skipped, the code fails with unclear JS errors

## Verification Status

### What was verified:
- ✅ FFI implementation (bridge_ffi.dart) — memory management, isolate usage, event callbacks all correct
- ✅ WASM implementation (bridge_web.dart) — JS interop setup correct, event flow correct
- ✅ Stub implementation (bridge_stub.dart) — intentionally throws, correct
- ✅ Facade pattern (bridge.dart) — clean delegation, no logic issues
- ✅ Test suite (bridge_test.dart) — comprehensive tests covering init, sync call, async call, event stream
- ✅ Integration with EngineService — properly called and used end-to-end

### Notes:
- The bridge is properly wired to Go backend (tests confirm end-to-end flow)
- Event system works correctly via NativeCallable.listener on native, JS callback on web
- Async bridge correctly uses Isolate.run on native (non-blocking), wraps sync in Future on web (idiomatic)
- No stubs or placeholders in actual implementation — only intentional fallback stub
- Memory management is proper in FFI (calloc cleanup, pointer freeing)

## Recommendation:
Fix both asserts→throws in bridge_web.dart before shipping web version. Desktop/native (FFI) version is solid.


# notification_system — NotificationSystem orchestrator

- [ ] [MAJOR] `checkDelayed()` resolves mute state only via the pre-set `muteStateUnknown` flag; AyuGram re-evaluates `computeSkipState()` live against actual settings at check time, so even if the flag is never cleared via `resolveDelayedMuteState()` the notification still dispatches once settings are available. In Dart, if `resolveDelayedMuteState()` is never called for a chat the queued notification is silently dropped. — `notification_system.dart:501` ← `AyuGramDesktop/Telegram/SourceFiles/window/notifications_manager.cpp:646`

# notification_types — Reaction/PollVote fields never populated from backend

## Critical Issues

- [ ] [CRITICAL] **Reaction and poll vote notifications show as regular messages** — The notification composition logic in `notification_types.dart` has complete support for reactions and poll votes (functions `_composeReactionText`, `_composePollVoteText`, subtitle generation for reactions), and the notification system checks these flags (`notification_system.dart:276-277`), but the fields `isReaction`, `isPollVote`, `reactionEmoji`, `reactorName`, `pollVoteOption`, `reactedToType` are never populated from the engine. In `chat_state.dart:2304-2342`, `NotificationData` is created without setting these fields, so they default to false/empty. Result: all reactions and poll votes display as regular messages, with wrong text composition and missing reaction emoji.
  - `notification_types.dart:40,55,96,111` ← Backend wiring bug: engine never populates these fields
  - `chat_state.dart:2304-2342` ← Where notifications are created, reaction/poll fields never set
  - `notification_system.dart:276-277` ← Code expects these fields but never receives them
  - Proto definition `engine.pb.dart` lacks these fields entirely — Go backend not sending them


# app_state — AppState / GhostModeAccountSettings

- [ ] [MAJOR] `_notifCorner` enum ordering mismatches AyuGram spec — Dart maps `1=topCenter, 2=topRight, 4=bottomRight`; AyuGram `ScreenCorner` maps `1=TopRight, 2=BottomRight, 4=TopCenter`. Positions 1, 2, and 4 are swapped. Additionally, AyuGram's default is `BottomRight = 2`, but Dart defaults to `4`. Any rendering code indexed against AyuGram's enum values will place the notification popup in the wrong corner for values 1, 2, and 4 — `app_state.dart:252` ← `AyuGram/core/core_settings.h:101-105,1088`

- [ ] [MAJOR] `setRecentStickersCount` allows minimum of 0 but AyuGram validates minimum of 1 — `v = v.clamp(0, 200)` should be `v.clamp(1, 200)`; setting 0 is spec-invalid and could produce a broken sticker panel — `app_state.dart:1809` ← `AyuGram/ayu/ayu_settings.cpp:519`

- [ ] [MAJOR] `_flushWindowPrefs()` is called without `await` inside `dispose()` — the method is `Future<void>` and performs async file I/O; calling it unawaited means settings changed close to app exit are silently lost on shutdown — `app_state.dart:3604-3606`

# audio_service — 2 issues

- [ ] [MAJOR] FILE_REFERENCE retry sends the same stale file reference — `audio_service.dart:219-225` retries `_engine.reportMusicListen(...)` with the same `_currentFileRef` that caused the initial `FILE_REFERENCE_*` error, so the retry is guaranteed to fail. AyuGram calls `document->session().api().refreshFileReference(origin, callback)` to fetch a fresh reference from the original message, then only retries if the reference actually changed — `media_player_listen_tracker.cpp:82-93`

- [ ] [MAJOR] Playback position never saved or restored — `audio_service.dart` always opens files from position 0 with no seek-to-saved-position after open. AyuGram saves position for songs ≥ 20 minutes and videos ≥ 1 minute (`kMinLengthForSavePositionMusic = 20*60`, `kMinLengthForSavePositionVideo = 60`) via `session.local().setMediaLastPlaybackPosition()`, and restores it at `result.position = local.mediaLastPlaybackPosition(document->id)` on open — `media_player_instance.cpp:55-56,140,885`

# auth_state — Auth flow state machine gaps

- [ ] [CRITICAL] `needsInput` misses the `'recover'` state — if the Go engine emits a password-recovery code entry state, `needsInput` returns `false`, auto-poll stops, and the UI will not prompt for recovery code input — `auth_state.dart:44` ← `intro_password_check.cpp:292`

- [ ] [MAJOR] SRP_ID_INVALID handling has no loop/storm protection — AyuGram records `_lastSrpIdInvalidTime` and compares against `kHandleSrpIdInvalidTimeout`; a second SRP_ID_INVALID within the timeout shows a server error and aborts. Dart unconditionally restores the 2FA input state with "Password verification failed. Please try again." so a server-side SRP storm leaves the user looping forever with no escape — `auth_state.dart:99-112` ← `intro_password_check.cpp:169-178`

- [ ] [MAJOR] QR code expiry not handled — AyuGram calls `_refreshTimer.callOnce(std::max(left, 1) * 1000)` based on the server-reported `expires` field to refresh the token before it goes stale. `auth_state.dart` has no such timer; if the Go engine does not proactively push a new QR auth event before expiry, the displayed QR code silently becomes invalid with no UI feedback — `auth_state.dart:49` ← `intro_qr.cpp:432-441`

- [ ] [MAJOR] `needsInput` misses the `'email'` state — AyuGram has a dedicated `EmailWidget` step for email verification during 2FA setup. If the Go engine emits an `'email'` state, `needsInput` returns `false`, auto-poll stops, and the user cannot submit the email code — `auth_state.dart:44` ← `intro_email.cpp:30`

# ayu_forward — Forward state machine and intelligent forward logic

- [ ] [CRITICAL] Sender-level noForwards triggers `intelligentForward` but `buildChunks` never routes those messages to `resendAsOwn` — `needsIntelligentForward` at line 286 returns `true` when any `msg.senderNoForwards` is set, calling `intelligentForward`, but `buildChunks` (line 138–165) only checks `isMessageRestricted` (message-level `noForwards` flag) — so messages from restricted senders get assigned `ForwardMethod.native` and are natively forwarded in violation of the sender restriction. In C++ this case is caught first in `ApiWrap::forwardMessages` (apiwrap.cpp:3487): `isFullAyuForwardNeeded` checks `item->from()->isAyuNoForwards()` and, if true, routes the **entire batch** to `AyuForward::forwardMessages` (full resendAsOwn) before `intelligentForward` is ever reached. The Dart has no equivalent full-batch resendAsOwn path for sender-level restriction — `ayu_forward.dart:281` ← `apiwrap.cpp:3487` + `ayu_forward.cpp:233`

- [ ] [MAJOR] Native forward chunk sends each message individually instead of as a batch — `ForwardMethod.native` case at line 227–238 iterates per message calling `engine.forwardMessage(...)` once per `msg`. In C++ `intelligentForward` (ayu_forward.cpp:299), native chunks call `AyuSync::forwardMessagesSync(session, chunk.items, action, draft.options)` with the full item list in one call, which maps to a single `messages.forwardMessages` Telegram API request preserving album grouping. Per-message Dart calls issue N separate forward requests; album messages in native chunks are forwarded as ungrouped individual messages — `ayu_forward.dart:229` ← `ayu_forward.cpp:299`

# bridge_ffi.dart — No issues found

## Summary
The FFI bridge implementation is **correctly designed and fully functional**. All memory management, event handling, and platform compatibility are properly implemented.

## Verification Checklist

### Memory Management ✅
- **Line 127-129:** Request buffer allocated and copied correctly via `calloc`
- **Line 131:** Output length pointer allocated via `calloc`
- **Line 148-149:** Both pointers properly freed in finally block
- **Line 142:** Result copied to Uint8List before freeing C memory
- **Line 145:** Go-allocated memory freed via `free(resultPtr)` callback
- **Line 175:** Event data freed via `malloc.free(data)` after copying (correct for C.CBytes)
  - ✅ Matches Go side comment in `cmd/bridge/main.go:50-52` ("Dart frees it after copying")
  - ✅ Proper pairing: Go allocates via C.malloc, Dart frees via malloc.free

### Event Callback System ✅
- **Line 182:** `NativeCallable<_EventCallbackC>.listener(_onEvent)` — correct pattern
  - Uses `.listener` (not `.fromFunction`) to marshal calls back to Dart isolate
  - Avoids "Cannot invoke native callback outside an isolate" crashes
  - Matches Go export signature in `cmd/bridge/main.go:55` (`void (*event_callback_t)(void* data, int32_t len)`)
- **Line 168-177:** Event handler properly:
  - Checks for invalid length (line 169)
  - Copies bytes immediately (line 174)
  - Frees Go-allocated memory (line 175)
  - Emits to StreamController (line 176)

### Library Loading ✅
- **Line 94-102 (Linux):** Checks exe directory + lib subdir, fallback to system path
- **Line 104-108 (macOS):** Framework path search correct
- **Line 110-114 (Windows):** Local DLL search correct
- **Line 116 (Android):** Hardcodes `libcores.so` (correct for APK native lib)
- **Line 117:** Throws on unsupported platform (fail-fast)
- **Line 36:** `_resolvedLibPath` shared across isolates (correct for process-wide handle reuse)

### Initialization & Error Handling ✅
- **Line 49-50:** Guards against double-init
- **Line 70-72:** Guard against uninitialized state in `call()`
- **Line 78-79:** Guard against uninitialized state in `callAsync()`
- **Line 137-139:** Defensive check for nullptr and zero-length results
- **Line 169:** Defensive check for invalid event length

### Async Implementation ✅
- **Line 82:** Uses `Isolate.run()` for non-blocking FFI call
  - Correct pattern for blocking operations
  - Isolate.run automatically handles library reloading on same process handle
  - Comment on line 154 correctly notes: "DynamicLibrary.open with the same path reuses the process-wide handle (cheap)"

### Resource Cleanup ✅
- **Line 85-91 `dispose()`:** Proper lifecycle
  - Unregisters event callback (line 87)
  - Closes StreamController (line 89)
  - Closes NativeCallable (line 90)

### No Stubs or Placeholders ✅
- ✅ No `TODO` comments
- ✅ No `TODO()` function calls
- ✅ No hardcoded fake data
- ✅ No "coming soon" stubs
- ✅ No early returns with errors (only defensive checks)
- ✅ All functions are complete implementations

### Performance ✅
- ✅ Async calls use Isolate.run (non-blocking)
- ✅ Event streaming via broadcast StreamController (efficient multicast)
- ✅ Lazy library loading (only loaded on init)
- ✅ No unnecessary copies in hot paths
- ✅ calloc/malloc used appropriately for FFI interop

### Type Safety ✅
- ✅ FFI type signatures match Go exports (`BridgeCallWithLen`, `BridgeFree`, `BridgeSetEventCallback`)
- ✅ Pointer casting correct in `_onEvent` (line 174: `data.cast<Uint8>()`)
- ✅ All FFI types properly declared (lines 13-33)

## Cross-File Verification

### Go Backend Compatibility ✅
- ✅ `BridgeCallWithLen` signature matches Go export in `cmd/bridge/main.go:10-14`
- ✅ `BridgeFree` matches Go export in `cmd/bridge/main.go:21-26`
- ✅ `BridgeSetEventCallback` matches Go export in `cmd/bridge/main.go:31-52`
- ✅ Event callback signature `_EventCallbackC` matches `event_callback_t` typedef in Go

### Bridge Facade Integration ✅
- ✅ Implements `BridgeImpl` interface expected by `bridge.dart:15`
- ✅ All required properties and methods present (`events`, `isInitialized`, `init()`, `call()`, `callAsync()`, `dispose()`)

### EngineService Integration ✅
- ✅ Called via `Bridge` facade in `engine_service.dart:22`
- ✅ Events properly streamed to `_bridgeEventSub` for parsing (line 54 of engine_service.dart)

## Comparison to AyuGram Desktop
*Note: AyuGram Desktop is pure C++/Qt with no Dart/Flutter UI. Bridge_ffi.dart is architecture-specific to this project's Go+Flutter stack and has no direct AyuGram equivalent. This file implements the low-level FFI binding layer, not UI.*

## Conclusion
**No critical, major, or minor issues detected.**

The FFI bridge is production-ready. All memory management is correct, event handling is robust, platform loading is comprehensive, and integration with Go backend is properly wired. The code exemplifies proper Dart FFI patterns (Isolate.run for blocking, NativeCallable.listener for callbacks, proper cleanup).

# chat_state — Saved-sublists pagination wrong, folder filter logic wrong

- [ ] [MAJOR] `_kFirstPerPage = 20` should be 10 — the comment at line 1203 even says "kFirstPerPage=10" but the constant is 20, causing 2× too many saved sublists fetched on first load — `chat_state.dart:109` ← `data_saved_messages.cpp:31` (`constexpr auto kFirstPerPage = 10`)

- [ ] [MAJOR] `_kPerPage = 100` should be 50 — subsequent saved-sublist pages are 2× oversized vs AyuGram — `chat_state.dart:110` ← `data_saved_messages.cpp:30` (`constexpr auto kPerPage = 50`)

- [ ] [MAJOR] Folder filter applies exclusion flags (excludeMuted / excludeRead / excludeArchived) **before** checking the explicit include list, so an explicitly-included chat that is muted/read/archived is incorrectly hidden. AyuGram evaluates it as `(typeFilter AND exclusionConditions) OR _always.contains(history)` — `_always` (explicit includes) bypasses all exclusion conditions. Dart checks `excludeMuted/Read/Archived` first and only reaches `includeSet.contains()` afterwards — `chat_state.dart:706-734` ← `data_chat_filters.cpp:366-386`

- [ ] [MAJOR] When `excludeRead` is set, AyuGram still shows chats with an unread mention (`state.mention`) — Dart checks only `c.unreadCount == 0` with no mention exception, incorrectly hiding chats that have an unread mention but total unreadCount = 0 — `chat_state.dart:715` ← `data_chat_filters.cpp:379-382`

# telegram_palette — Color value deviations and algorithm differences

## Scope
Dart file: `dart/lib/theme/telegram_palette.dart`
Ground truth: `/tmp/theme_extract/day-blue/colors.tdesktop-theme`, `/tmp/theme_extract/night/colors.tdesktop-theme`, `AyuGram/Telegram/lib_ui/ui/colors.palette`, `AyuGram/Telegram/lib_ui/ui/style/style_palette_colorizer.cpp`

---

## dayBlue theme — Wrong color values

- [ ] [CRITICAL] `dayBlue.msgOutBg` is `#DEF1FD` (0xFFDEF1FD) but official day-blue theme has `#def1fd` — the Dart value matches; however `msgOutBg` in the green-tint classic day should be `#effdde`. For the dayBlue preset, the official value is `#def1fd` which matches. No issue here.

- [ ] [CRITICAL] `dayBlue.msgOutServiceFg` is `Color(0xFF168ACD)` (same as msgInServiceFg) but the base `colors.palette` defines `msgOutServiceFg: #45a32d` (green). The day-blue theme overrides this to `windowActiveTextFg` but the official day-blue `.tdesktop-theme` line 259 states `msgOutServiceFg: windowActiveTextFg` which resolves to `#168acd`. Dart's dayBlue value `0xFF168ACD` matches after resolution — no deviation.

- [ ] [CRITICAL] `dayBlue.historyScrollBg` is `Color(0x00000000)` but the official day-blue `.tdesktop-theme` line 249 has `historyScrollBg: #00000000` — both are transparent/zero. This matches.

- [ ] [CRITICAL] `dayBlue.msgOutShadow` is `Color(0x1A0D5A91)` (`#0d5a911a`) but the official day-blue theme has `msgOutShadow: #0d5a911a` — this matches (alpha first in Dart ARGB vs last in hex RGBA). However the base `colors.palette` at line 357 has `msgOutShadow: #3ac3461d`. The day-blue theme overrides this. Dart uses the day-blue override value — correct.

- [ ] [MAJOR] `dayBlue.msgInBgSelected` is `Color(0xFFBBE1FC)` (`#bbe1fc`) but the official day-blue theme (line 252) has `msgInBgSelected: #bbe1fc` — values match. The base `colors.palette` has `#c2dcf2` which is the non-themed value; the dayBlue preset correctly uses `#bbe1fc`.

- [ ] [CRITICAL] `dayBlue.msgOutReplyBarColor` is `Color(0xFF059DE8)` (`#059de8`) but official day-blue theme (line 274) has `msgOutReplyBarColor: historyOutIconFg` which resolves to `#059de8`. This matches.

- [ ] [CRITICAL] `dayBlue.historyFileOutIconFg` is `Color(0xFFEFFDDE)` and `historyFileOutIconFgSelected` is `Color(0xFFCBEBB5)`, using the green outbox bubble colors. But the official day-blue theme (line 411) derives these from `msgOutBg`/`msgOutBgSelected`. For the standard day-blue theme `msgOutBg = #def1fd` (light blue) and `msgOutBgSelected = #bbe1fc`. The Dart uses `#effdde` (green-tinted) and `#cbebb5` — these are the CLASSIC green theme values, not the blue day-blue values. — `dart/lib/theme/telegram_palette.dart:3180` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:411-412`

- [ ] [CRITICAL] `dayBlue.historyFileOutRadialFg`/`historyFileOutRadialFgSelected` same issue as historyFileOutIconFg — uses green tint `#effdde`/`#cbebb5` instead of blue `#def1fd`/`#bbe1fc`. — `dart/lib/theme/telegram_palette.dart:3182-3183` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:413-414`

- [ ] [CRITICAL] `dayBlue.msgOutDateFg` is `Color(0xFF86A8C2)` (`#86a8c2`) but the base `colors.palette` line 362 has `msgOutDateFg: #6db566` (green) and the day-blue theme (line 267) overrides to `#86a8c2`. Dart's value `0xFF86A8C2` matches the day-blue override — correct.

- [ ] [CRITICAL] `dayBlue.msgOutServiceFgSelected` is `Color(0xFF469992)` but the day-blue theme (line 260) has `msgOutServiceFgSelected: windowActiveTextFg` which is `#168acd` — not `#469992`. `#469992` is the classic green non-themed value from `colors.palette` line 354. This is WRONG for dayBlue. — `dart/lib/theme/telegram_palette.dart:3158` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:260`

- [ ] [CRITICAL] `dayBlue.msgInShadowSelected` is `Color(0x29548DBB)` but day-blue theme line 262 has `msgInShadowSelected: #1d629730` (RGBA) = alpha 0x30, RGB `1d6297`. In Dart ARGB format that's `Color(0x301D6297)`. Dart uses `0x29548DBB` — completely different color. — `dart/lib/theme/telegram_palette.dart:3159` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:262`

- [ ] [CRITICAL] `dayBlue.msgOutShadowSelected` is `Color(0x2237A78D)` but day-blue theme line 264 has `msgOutShadowSelected: #2e74aa29` = `Color(0x292E74AA)`. Dart uses completely different values. — `dart/lib/theme/telegram_palette.dart:3160` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:264`

- [ ] [CRITICAL] `dayBlue.msgOutDateFgSelected` is `Color(0xFF56B2A6)` but day-blue theme line 268 has `msgOutDateFgSelected: #6ca0c2`. Dart's value `#56b2a6` (teal) vs official `#6ca0c2` (blue-gray). — `dart/lib/theme/telegram_palette.dart:3162` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:268`

- [ ] [CRITICAL] `dayBlue.msgOutMonoFgSelected` is `Color(0xFF459866)` but day-blue theme has `msgOutMonoFgSelected: msgOutMonoFg` which is `#4e7391`. Dart uses `#459866` (greenish) instead. — `dart/lib/theme/telegram_palette.dart:3167` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:373-374`

- [ ] [CRITICAL] `dayBlue.msgOutReplyBarSelColor` is `Color(0xFF45A3AA)` but day-blue theme line 275 has `msgOutReplyBarSelColor: historyOutIconFgSelected` which is `#149ce6`. Dart uses `#45a3aa` (teal). — `dart/lib/theme/telegram_palette.dart:3164` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:275`

- [ ] [MAJOR] `dayBlue.mediaOutFg` is `Color(0xFF6FAB69)` but day-blue theme line 323 has `mediaOutFg: #80a3bd`. Dart uses a greenish value instead of blue-gray. — `dart/lib/theme/telegram_palette.dart:3198` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:323`

- [ ] [MAJOR] `dayBlue.mediaOutFgSelected` is `Color(0xFF56B2A6)` but day-blue theme line 324 has `mediaOutFgSelected: #5f8fb3`. Dart uses `#56b2a6` (teal), official is `#5f8fb3` (blue). — `dart/lib/theme/telegram_palette.dart:3199` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:324`

- [ ] [MAJOR] `dayBlue.msgFileThumbLinkOutFg` is `Color(0xFF4BA831)` but day-blue theme line 285 has `msgFileThumbLinkOutFg: #0a8bd0`. Dart uses `#4ba831` (green), official is `#0a8bd0` (blue). — `dart/lib/theme/telegram_palette.dart:3171` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:285`

- [ ] [MAJOR] `dayBlue.msgFileThumbLinkOutFgSelected` is `Color(0xFF31A298)` but day-blue theme line 286 has `msgFileThumbLinkOutFgSelected: lightButtonFgOver` = `#168acd`. Dart uses `#31a298` (teal). — `dart/lib/theme/telegram_palette.dart:3172` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:286`

- [ ] [MAJOR] `dayBlue.msgFileOutBgSelected` is `Color(0xFF50AC9B)` but day-blue theme line 292 has `msgFileOutBgSelected: #51a3d3`. Dart uses `#50ac9b` (teal/green), official is `#51a3d3` (blue). — `dart/lib/theme/telegram_palette.dart:3175` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:292`

- [ ] [MAJOR] `dayBlue.msgWaveformOutInactive` is `Color(0xFFB3D4E7)` but day-blue theme line 315 has `msgWaveformOutInactive: #b3d4e7` — values match. However `msgWaveformOutInactiveSelected` is `Color(0xFF91C3C3)` but day-blue theme line 316 has `#87bcdb`. — `dart/lib/theme/telegram_palette.dart:3192` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:316`

- [ ] [MAJOR] `dayBlue.msgWaveformOutActiveSelected` is `Color(0xFF6BADAD)` but day-blue theme line 314 has `msgWaveformOutActiveSelected: #51a3d3`. Dart uses `#6badad` (teal), official is `#51a3d3` (blue). — `dart/lib/theme/telegram_palette.dart:3191` ← `/tmp/theme_extract/day-blue/colors.tdesktop-theme:314`

- [ ] [MAJOR] `dayBlue.overviewPhotoSelectOverlay` is `Color(0x3340ACE3)` (`#40ace333`) but day-blue theme line 348 has `#40ace333` — both encode the same RGBA value but Dart stores as ARGB `0x3340ACE3`. The hex value `#40ace333` in the `.tdesktop-theme` is ARGB format where `40` is the RGB start and `33` is alpha? Checking: C++ color format is `#rrggbbaa` in `.tdesktop-theme`, so `#40ace333` = RGB `40ace3` alpha `33` = `Color(0x3340ACE3)`. This matches.

---

## night theme — Wrong color values

- [ ] [CRITICAL] `night.msgFile1Bg` through `msgFile4BgSelected` (16 values) are all identical to the day-blue theme values (e.g. `msgFile1Bg: Color(0xFF72B1DF)`). But the official night theme (lines 300-315) has completely different dark-mode file type colors: `msgFile1Bg: #3e7eba`, `msgFile1BgDark: #24679e`, `msgFile1BgOver: #1d5e93`, `msgFile1BgSelected: #ffffff`, `msgFile2Bg: #3ea34a`, etc. The Dart night theme uses light-mode file colors instead of night-specific ones. — `dart/lib/theme/telegram_palette.dart:3471-3486` ← `/tmp/theme_extract/night/colors.tdesktop-theme:300-315`

- [ ] [CRITICAL] `night.historyCallArrowInFg` is `Color(0xFF32B032)` but night theme (line 207) has `historyCallArrowInFg: #5093d6` (blue). Dart uses green `#32b032`. — `dart/lib/theme/telegram_palette.dart:3720` ← `/tmp/theme_extract/night/colors.tdesktop-theme:207`

- [ ] [CRITICAL] `night.historyCallArrowInFgSelected` is `Color(0xFF2592A8)` but night theme (line 208) has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3721` ← `/tmp/theme_extract/night/colors.tdesktop-theme:208`

- [ ] [CRITICAL] `night.historyCallArrowMissedInFg` is `Color(0xFFDD5B4A)` but night theme (line 209) has `callArrowMissedFg` = `#ed5050`. Dart uses `#dd5b4a`, official is `#ed5050`. — `dart/lib/theme/telegram_palette.dart:3722` ← `/tmp/theme_extract/night/colors.tdesktop-theme:209,117`

- [ ] [CRITICAL] `night.historyCallArrowMissedInFgSelected` is `Color(0xFFDD5B4A)` but night theme (line 210) has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3723` ← `/tmp/theme_extract/night/colors.tdesktop-theme:210`

- [ ] [CRITICAL] `night.historyCallArrowOutFgSelected` is `Color(0xFF2592A8)` but night theme (line 212) has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3725` ← `/tmp/theme_extract/night/colors.tdesktop-theme:212`

- [ ] [CRITICAL] `night.msgInBg` is `Color(0xFF24292E)` but night theme (line 256) has `#182533`. Deviation is large — completely different background. — `dart/lib/theme/telegram_palette.dart:3390` ← `/tmp/theme_extract/night/colors.tdesktop-theme:256`

- [ ] [CRITICAL] `night.msgInBgSelected` is `Color(0xFF2E70A5)` and night theme has `#2e70a5` — matches.

- [ ] [CRITICAL] `night.msgInDateFg` is `Color(0xFF7A858F)` but night theme (line 270) has `#6d7f8f`. — `dart/lib/theme/telegram_palette.dart:3396` ← `/tmp/theme_extract/night/colors.tdesktop-theme:270`

- [ ] [CRITICAL] `night.msgInDateFgSelected` is `Color(0xFF7A858F)` (same as msgInDateFg) but night theme (line 271) has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3738` ← `/tmp/theme_extract/night/colors.tdesktop-theme:271`

- [ ] [CRITICAL] `night.msgOutDateFgSelected` is `Color(0xFF7DA8D3)` (same as msgOutDateFg) but night theme (line 273) has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3739` ← `/tmp/theme_extract/night/colors.tdesktop-theme:273`

- [ ] [CRITICAL] `night.msgInServiceFgSelected` is `Color(0xFF71BAFA)` (same as msgInServiceFg) but night theme (line 263) has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3734` ← `/tmp/theme_extract/night/colors.tdesktop-theme:263`

- [ ] [CRITICAL] `night.msgOutServiceFg` is `Color(0xFFFFFFFF)` but night theme (line 264) has `#90caff` (light blue). — `dart/lib/theme/telegram_palette.dart:3399` ← `/tmp/theme_extract/night/colors.tdesktop-theme:264`

- [ ] [CRITICAL] `night.msgOutServiceFgSelected` is `Color(0xFFFFFFFF)` but night theme (line 265) has `#ffffff` — this matches.

- [ ] [CRITICAL] `night.msgInReplyBarSelColor` is `Color(0xFF429BDB)` but night theme (line 278) has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3740` ← `/tmp/theme_extract/night/colors.tdesktop-theme:278`

- [ ] [CRITICAL] `night.msgOutReplyBarSelColor` is `Color(0xFF65B9F4)` but night theme (line 280) has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3741` ← `/tmp/theme_extract/night/colors.tdesktop-theme:280`

- [ ] [CRITICAL] `night.msgInMonoFgSelected` is `Color(0xFF5A8CB7)` (same as msgInMonoFg) but night theme (line 284) has `#a3cdf7`. — `dart/lib/theme/telegram_palette.dart:3743` ← `/tmp/theme_extract/night/colors.tdesktop-theme:284`

- [ ] [CRITICAL] `night.msgOutMonoFg` is `Color(0xFFBAD9F6)` — night theme (line 283) has `#aed1f3`. — `dart/lib/theme/telegram_palette.dart:3403` ← `/tmp/theme_extract/night/colors.tdesktop-theme:283`

- [ ] [CRITICAL] `night.msgOutMonoFgSelected` is `Color(0xFFBAD9F6)` but night theme (line 285) has `#a3cdf7`. — `dart/lib/theme/telegram_palette.dart:3744` ← `/tmp/theme_extract/night/colors.tdesktop-theme:285`

- [ ] [CRITICAL] `night.msgFileInBgOver` is `Color(0xFF4AA6D9)` but night theme (line 295) has `#489ed7`. — `dart/lib/theme/telegram_palette.dart:3750` ← `/tmp/theme_extract/night/colors.tdesktop-theme:295`

- [ ] [CRITICAL] `night.msgFileInBgSelected` is `Color(0xFF3F96D0)` but night theme (line 296) has `#6ab4f4`. — `dart/lib/theme/telegram_palette.dart:3751` ← `/tmp/theme_extract/night/colors.tdesktop-theme:296`

- [ ] [CRITICAL] `night.msgFileOutBgSelected` is `Color(0xFFFFFFFF)` but night theme (line 299) has `#58abf3`. — `dart/lib/theme/telegram_palette.dart:3752` ← `/tmp/theme_extract/night/colors.tdesktop-theme:299`

- [ ] [CRITICAL] `night.historyFileInIconFg` is `Color(0xFF24292E)` (uses msgInBg value) but night theme (line 316) has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3753` ← `/tmp/theme_extract/night/colors.tdesktop-theme:316`

- [ ] [CRITICAL] `night.historyFileInIconFgSelected` is `Color(0xFF2E70A5)` but night theme (line 317) has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3754` ← `/tmp/theme_extract/night/colors.tdesktop-theme:317`

- [ ] [CRITICAL] `night.historyFileOutIconFg` is `Color(0xFF265E8C)` but night theme (line 320) has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3757` ← `/tmp/theme_extract/night/colors.tdesktop-theme:320`

- [ ] [CRITICAL] `night.historyFileThumbIconFg` is `Color(0xFF24292E)` but night theme (line 324) has `#efefef`. — `dart/lib/theme/telegram_palette.dart:3761` ← `/tmp/theme_extract/night/colors.tdesktop-theme:324`

- [ ] [CRITICAL] `night.msgBotKbRippleBg` is `Color(0x20FFFFFF)` but night theme (line 339) has `#92c0e50b` (tiny alpha, different RGB). — `dart/lib/theme/telegram_palette.dart:3772` ← `/tmp/theme_extract/night/colors.tdesktop-theme:339`

- [ ] [CRITICAL] `night.msgBotKbOverBgAdd` is `Color(0x20FFFFFF)` but night theme (line 337) has `#80b1db0f`. — `dart/lib/theme/telegram_palette.dart:3770` ← `/tmp/theme_extract/night/colors.tdesktop-theme:337`

- [ ] [CRITICAL] `night.toastBg` is `Color(0xE52C3033)` (`#2c3033e5`) but night theme (line 348) has `#000000b2`. — `dart/lib/theme/telegram_palette.dart:3781` ← `/tmp/theme_extract/night/colors.tdesktop-theme:348`

- [ ] [CRITICAL] `night.callBg` is `Color(0xF226282C)` but night theme (line 429) has `#14191ff5`. Both are dark semi-transparent but different values (alpha `0xF2` vs `0xF5`, RGB `26282C` vs `14191F`). — `dart/lib/theme/telegram_palette.dart:3833` ← `/tmp/theme_extract/night/colors.tdesktop-theme:429`

- [ ] [CRITICAL] `night.callAnswerBg` is `Color(0xFF66C95B)` (green, same as light theme) but night theme (line 434) has `#488fc9` (blue). — `dart/lib/theme/telegram_palette.dart:3842` ← `/tmp/theme_extract/night/colors.tdesktop-theme:434`

- [ ] [CRITICAL] `night.callAnswerRipple` is `Color(0xFF52B149)` (green) but night theme (line 435) has `#4286c2` (blue). — `dart/lib/theme/telegram_palette.dart:3843` ← `/tmp/theme_extract/night/colors.tdesktop-theme:435`

- [ ] [CRITICAL] `night.callAnswerBgOuter` is `Color(0x2650EB41)` but night theme (line 436) has `#3f95eb26`. — `dart/lib/theme/telegram_palette.dart:3844` ← `/tmp/theme_extract/night/colors.tdesktop-theme:436`

- [ ] [CRITICAL] `night.callHangupBg` is `Color(0xFFD75A5A)` but night theme (line 437) has `#cc4646`. — `dart/lib/theme/telegram_palette.dart:3845` ← `/tmp/theme_extract/night/colors.tdesktop-theme:437`

- [ ] [CRITICAL] `night.callHangupRipple` is `Color(0xFFC04646)` but night theme (line 438) has `#ca4141`. — `dart/lib/theme/telegram_palette.dart:3846` ← `/tmp/theme_extract/night/colors.tdesktop-theme:438`

- [ ] [CRITICAL] `night.callBarBg` is `Color(0xFF2B5278)` (= `dialogsBgActive`) but night theme (line 443) has `#366693`. — `dart/lib/theme/telegram_palette.dart:3848` ← `/tmp/theme_extract/night/colors.tdesktop-theme:443`

- [ ] [CRITICAL] `night.callBarMuteRipple` is `Color(0xFF315A80)` (= `dialogsRippleBgActive`) but night theme (line 444) has `#4b7dab`. — `dart/lib/theme/telegram_palette.dart:3849` ← `/tmp/theme_extract/night/colors.tdesktop-theme:444`

- [ ] [CRITICAL] `night.callBarBgMuted` is `Color(0xFF8F8F8F)` but night theme (line 445) has `#35495d`. — `dart/lib/theme/telegram_palette.dart:3850` ← `/tmp/theme_extract/night/colors.tdesktop-theme:445`

- [ ] [CRITICAL] `night.mediaviewTextLinkFg` is `Color(0xFF4DB8FF)` (same as day-blue) but night theme (line 416) has `#70baf5`. — `dart/lib/theme/telegram_palette.dart:3818` ← `/tmp/theme_extract/night/colors.tdesktop-theme:416`

- [ ] [CRITICAL] `night.historyOutIconFg` is `Color(0xFF62B2FD)` but night theme line 201 has `#6bbfff`. — `dart/lib/theme/telegram_palette.dart:3438` ← `/tmp/theme_extract/night/colors.tdesktop-theme:201`

- [ ] [CRITICAL] `night.historyOutIconFgSelected` is `Color(0xFF62B2FD)` (same) but night theme line 202 has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3719` ← `/tmp/theme_extract/night/colors.tdesktop-theme:202`

- [ ] [CRITICAL] `night.historyIconFgInverted` is `Color(0xFFFFFFFF)` but night theme line 203 has `#ffffffe5` (alpha `0xE5`). — `dart/lib/theme/telegram_palette.dart:3441` ← `/tmp/theme_extract/night/colors.tdesktop-theme:203`

- [ ] [MAJOR] `night.msgWaveformInActiveSelected` is `Color(0xFF549CD7)` but night theme line 330 has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3766` ← `/tmp/theme_extract/night/colors.tdesktop-theme:330`

- [ ] [MAJOR] `night.msgWaveformInInactiveSelected` is `Color(0xFF3A4D61)` but night theme line 332 has `#6fa5d4`. — `dart/lib/theme/telegram_palette.dart:3767` ← `/tmp/theme_extract/night/colors.tdesktop-theme:332`

- [ ] [MAJOR] `night.msgWaveformOutActiveSelected` is `Color(0xFF62B2FD)` but night theme line 334 has `#ffffff`. — `dart/lib/theme/telegram_palette.dart:3768` ← `/tmp/theme_extract/night/colors.tdesktop-theme:334`

- [ ] [MAJOR] `night.msgWaveformOutInactiveSelected` is `Color(0xFF4B7FB3)` but night theme line 336 has `#6fa5d4`. — `dart/lib/theme/telegram_palette.dart:3769` ← `/tmp/theme_extract/night/colors.tdesktop-theme:336`

---

## Colorizer algorithm — Wrong domain

- [ ] [MAJOR] The `colorize()` method operates in HSV throughout (lines 1204, 1218-1246). The C++ colorizer (`style_palette_colorizer.cpp`) also works entirely in HSV (`QColor::fromHsv`, `getHsv`). However the Dart code clamps the new accent's lightness using HSL (`HSLColor.fromColor`, line 1210-1213), then converts back to HSV. The C++ `ColorizerFrom()` operates purely in HSV with `lightnessMin`/`lightnessMax` fields that are HSV value (0-255), not HSL lightness. Converting through HSL introduces non-equivalence for saturated colors. — `dart/lib/theme/telegram_palette.dart:1210-1213` ← `AyuGram/Telegram/lib_ui/ui/style/style_palette_colorizer.h:17-19`

- [ ] [MAJOR] The colorizer's `hueThreshold` is hardcoded as `15.0` (line 1216). The C++ `hueThreshold` is set per-theme by `ColorizerFrom()`. The value 15 is used for the built-in Telegram Desktop themes (via `kThemeHueDistance = 15` in `window_themes.cpp`). This is coincidentally correct for standard themes but any custom `colorizer` with a different threshold won't be respected. — `dart/lib/theme/telegram_palette.dart:1216` ← `AyuGram/Telegram/lib_ui/ui/style/style_palette_colorizer.h:17`

---

## Performance

- [ ] [MAJOR] `colorize()` creates a full `TelegramPalette` copy with ~500+ fields on every call with a new accent color, and there is no caching — every accent change triggers complete reconstruction. The C++ uses a lazy colorize pass over only modified entries. While not semantically wrong, recomputing all 500+ fields synchronously on every accent change will cause frame drops on low-end devices when the user adjusts theme color. — `dart/lib/theme/telegram_palette.dart:1249-1784`

---

## Summary of root cause

The `dayBlue` preset incorrectly uses green-tinted values (from the classic day/green theme) for several outgoing-message-related colors (`msgOutServiceFgSelected`, `msgOutReplyBarSelColor`, `mediaOutFg`, `msgFileThumbLinkOutFg`, file icon colors). These should be blue-tinted for the day-blue theme.

The `night` preset has pervasive errors: it uses day-theme file type colors unchanged, wrong call UI colors (green answer button instead of night's blue), wrong selected-state colors (many should be `#ffffff` in night mode but aren't), and wrong bot keyboard overlay colors.

# theme_file — Cloud meta format incompatibility, wrong background size limit, paletteChecksum semantics mismatch

- [ ] [CRITICAL] `writeCloudMeta` exports in format `// id:X hash:Y` (single line, lowercase keys, no space after colon) but AyuGram `WriteCloudToText` writes `// ID: X\n// ACCESS: Y\n` (separate lines, uppercase keys, `: ` separator). Files exported by Dart are unreadable by Telegram Desktop/AyuGram — `ReadCloudFromText` splits by `\n` and uses `entry.indexOf(": ")` to parse, so `id:X hash:Y` yields no match. Also, AyuGram's `kCloudInTextEnd` ends with `\n\n` (double newline) but Dart writes only `\n`. — `theme_file.dart:181-184` ← `window_theme_editor.cpp:346-356`

- [ ] [CRITICAL] `readCloudMeta` uses regexes `r'id:(\d+)'` and `r'hash:(\d+)'` (lowercase, no space) which cannot parse files from Telegram Desktop/AyuGram that have format `// ID: X` and `// ACCESS: Y`. The `parsePaletteText` service-block parser at lines 95–101 has the same bug: strips `//` then applies `id:(\d+)` — `ID: 12345` (uppercase with space) will never match. Cloud metadata is silently lost when opening any real `.tdesktop-theme` file. — `theme_file.dart:97-100` and `theme_file.dart:186-199` ← `window_theme_editor.cpp:358-381`

- [ ] [CRITICAL] `_kBackgroundMaxPixels = 40 * 1024 * 1024` (40 megapixels) but AyuGram's `kBackgroundSizeLimit = 25 * 1024 * 1024` (25 megapixels). The comment on line 10 says "matches AyuGram kBackgroundSizeLimit" but it is 60% too large. Theme files containing oversized backgrounds that AyuGram would reject are accepted by this parser. — `theme_file.dart:10` ← `window_theme.cpp:56`

- [ ] [MAJOR] `paletteChecksum` has wrong semantics. Dart computes it as `getCrc32(file.content)` (CRC32 of the palette file bytes extracted from the ZIP) at line 1463. AyuGram computes it as `style::palette::Checksum()` — a compile-time structural checksum of the style palette definitions, used to invalidate cache across app version upgrades. These are fundamentally different: AyuGram's checksum is a constant per build version; Dart's is a content hash. The `validateThemeCache` logic based on this value (line 1495) will behave incorrectly — it re-decodes the ZIP to re-hash the palette file instead of comparing a version token. — `theme_file.dart:1456-1473` and `theme_file.dart:1495` ← `window_theme.cpp:376` and `window_theme.cpp:385`

# theme_preview — Rendering issues vs AyuGram Desktop

## Issues Found

- [ ] [CRITICAL] Microphone icon uses static Material Icons.mic instead of animated Lottie icon — `theme_preview.dart:694-695` ← `window_theme_preview.cpp:570-575`
  - Dart draws static `Icons.mic` with material icon rendering
  - AyuGram uses `Lottie::MakeIcon()` for animated voice-to-video icon
  - Dart missing animation entirely

- [ ] [CRITICAL] Emoji button icon uses Material Icons.sentiment_satisfied_alt instead of theme icon — `theme_preview.dart:679-680` ← `window_theme_preview.cpp:584`
  - Dart: `_drawMaterialIcon(canvas, Icons.sentiment_satisfied_alt, ...)`
  - AyuGram: `emojiButton.icon[_palette]` from theme styles
  - Material icon won't match theme colors/style

- [ ] [CRITICAL] Attach icon uses Material Icons.attach_file instead of theme icon — `theme_preview.dart:655` ← `window_theme_preview.cpp:567`
  - Dart: `_drawMaterialIcon(canvas, Icons.attach_file, ...)`
  - AyuGram: `st::historyAttach.icon[_palette]` from theme styles
  - Material icon inconsistent with AyuGram UI

- [ ] [CRITICAL] Top bar icons (search, call, menu) hardcoded to absolute positions assuming 903px width — `theme_preview.dart:264,267,270` ← `window_theme_preview.cpp:537-542`
  - Dart uses magic numbers: `903 - 36`, `903 - 44 - 4 - 36`, `903 - 44 - 4 - 40 - 34`
  - These break if canvas is resized to non-903px width (class accepts custom width param at line 14-17)
  - Canvas scaling (lines 75-78) masks this but doesn't fix underlying non-proportional positioning
  - AyuGram uses icon width properties: `st::topBarMenuToggle.width`, `st::topBarCall.width`, `st::topBarSearch.width` composed left-to-right
  - Example: Dart's `903 - 44 - 4 - 36 = 819` hardcodes call icon position; if width=500, this will be off-screen

- [ ] [MAJOR] Photo timestamp rendered with different layer order than AyuGram — `theme_preview.dart:601-636` ← `window_theme_preview.cpp:1008-1017`
  - Dart rendering order: bubble bg → photo → caption → time background → time
  - AyuGram rendering order: bubble bg → text/caption → time → **photo** (photo drawn last, on top)
  - Dart draws photo before text; AyuGram draws photo after text (photo occludes timestamp in AyuGram)
  - Dart adds explicit semi-transparent background behind time (line 632: `Color(0x80000000)`); AyuGram doesn't
  - Visual mismatch: in Dart, timestamp visible on photo; in AyuGram, photo covers part of text/timestamp

- [ ] [MAJOR] Dimensions hardcoded as class constants instead of theme-aware — `theme_preview.dart:17-18,65-71` ← `window_theme_preview.cpp:214-227`
  - Dart static values: `_dialogsWidth = 312`, `_topBarHeight = 54`, `_composeHeight = 46`, `_rowHeight = 62`
  - AyuGram uses style values: `st::themePreviewDialogsWidth`, `st::topBarHeight`, `st::historySendSize.height()`, `st::dialogsRowHeight`
  - Dart dimensions can't adapt if theme specifies different layout; only canvas scaling applies (non-uniform if aspect changes)
  - Not critical for preview, but makes theme customization impossible

- [ ] [MAJOR] Emoji button circle positioning uses relative math instead of theme metrics — `theme_preview.dart:672-690` ← `window_theme_preview.cpp:577-604`
  - Dart: computes emojiX based on hardcoded compose area width assumptions
  - AyuGram: uses `emojiButton.width`, `emojiButton.iconPosition.x()`, proper margin calculations
  - Dart's approach works but is brittle; theme changes break it

- [ ] [MAJOR] Compose field placeholder uses hardcoded text instead of localized string — `theme_preview.dart:668` ← `window_theme_preview.cpp:623`
  - Dart: hardcoded `'Write a message...'`
  - AyuGram: uses `tr::lng_message_ph(tr::now)` for localized string
  - Not a UI bug but violates i18n practices

## Summary

Dart implementation uses Material Design icons and hardcoded positions where AyuGram uses theme icons and style constants. Icon animations missing (Lottie). Photo/timestamp rendering order differs. Hardcoded dimensions prevent theme customization. Multiple icon positions assume 903px width and will break if resized.

# wallpaper.dart — Pattern & gradient rendering

## Issues Found

- [x] [CRITICAL] Default patternIntensity is 40, should be 50 — `wallpaper.dart:25` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_wall_paper.h:110`
  - AyuGram defines `kDefaultIntensity = 50` but Dart hardcodes 40 in WallpaperData constructor
  - This affects all wallpaper creation via `WallpaperData()` and `fromColors()`

- [x] [CRITICAL] Missing pattern inversion for dark backgrounds with positive intensity — `wallpaper.dart:178-276` ← `AyuGramDesktop/Telegram/SourceFiles/ui/chat/chat_theme.cpp:1146,1155-1170`
  - AyuGram spec (research/telegram_desktop_ui.md:7756) requires: "when positive intensity is used AND background is dark (HSV value ≤ 0.3), the pattern is inverted"
  - Pattern inversion: replicate each pixel's alpha byte into R, G, B channels (white-on-transparent silhouette from dark-on-transparent)
  - Dart has NO inversion logic — affects readability of patterns over dark chat backgrounds
  - Severity: high — user-visible rendering bug causing illegible patterns

- [x] [MAJOR] ColorFilter.mode(Colors.white, BlendMode.dstIn) may not correctly implement negative pattern darkening — `wallpaper.dart:501-504` ← `AyuGramDesktop/Telegram/SourceFiles/ui/chat/chat_theme.cpp:116-117`
  - AyuGram uses `setCompositionMode(CompositionMode_DestinationIn)` before drawing pattern when opacity < 0
  - Dart uses `ColorFilter.mode(Colors.white, BlendMode.dstIn)` on the pattern image
  - BlendMode.dstIn semantics: "keep destination where source is opaque"
  - With white source (opaque everywhere), this effectively = noop; does NOT mask the pattern correctly
  - Expected: pattern acts as mask on gradient (darkens gradient where pattern is transparent)
  - Actual: pattern may not composite correctly over gradients
  - Recommend: test negative pattern rendering against AyuGram reference (e.g. -50 intensity)

- [x] [MINOR] Pattern overlay uses Opacity widget (line 484-485) which clamps patternOpacity — `wallpaper.dart:262,485` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_wall_paper.cpp:256-258`
  - Line 262: `opacity = wallpaper.patternOpacity.clamp(0.0, 1.0)` clamps negative opacity to 0
  - Line 485: uses this clamped opacity in Opacity widget
  - This works correctly because line 483 checks `if (intensity >= 0)` first (negative patterns skip Opacity widget)
  - Not a bug, just noted for clarity ✓

---

## Verification Checklist

- [ ] Test positive pattern (intensity ~50) over light background: should render with SoftLight blend
- [ ] Test negative pattern (intensity ~-50) over gradient: should darken where pattern is opaque
- [ ] Test negative pattern intensity == -100: black overlay should NOT be applied (spec: "strict > -1.0")
- [ ] Test pattern inversion: render dark pattern over dark gradient (HSV ≤ 0.3) — should invert to white-on-transparent
- [ ] Screenshot comparison: pattern rendering against AyuGram Desktop reference
- [ ] Verify ColorFilter behavior: test if dstIn mode works correctly for negative patterns

# active_sessions_screen — Audit findings

- [ ] [MAJOR] Session row date format is relative ("2h ago", "3d ago") instead of AyuGram's absolute format (same-day → time "14:35", same-week → weekday name, older → short date) — `active_sessions_screen.dart:462-475` ← `AyuGramDesktop/Telegram/SourceFiles/api/api_authorizations.cpp:258-268`

- [ ] [MAJOR] Current session location line incorrectly appends "• online": Dart calls `formatDate(lastActive)` unconditionally producing "country • online", but C++ skips the date for the current session entirely (hash==0 → `entry.active` not appended) — `active_sessions_screen.dart:1126-1131` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_active_sessions.cpp:160-165`

- [ ] [MAJOR] `terminateAll` removes sessions from local list without reloading from server; C++ calls `_authorizations->cancelCurrentRequest()` then `_authorizations->reload()` after the server confirms, so partial failures on the server side leave the Dart UI permanently desynced until the 60 s poll fires — `active_sessions_screen.dart:256-265` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_active_sessions.cpp:879-892`

- [ ] [MAJOR] No reactive subscription to server-pushed updates: C++ subscribes to `_authorizations->listValue()` which fires on every `_listChanges` (after reload AND after any terminate), so the list stays live; Dart only polls via a flat 60 s timer — `active_sessions_screen.dart:195` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_active_sessions.cpp:761-764` / `api/api_authorizations.cpp:192-198`

## admin_tools — placeholders, missing admin log events

- [ ] [CRITICAL] Bot "Currency Balance" button is a placeholder toast instead of opening the earnings screen — AyuGram navigates to `Info::ChannelEarn::Make(peer)` (shows actual balance and earnings analytics) — `admin_tools.dart:1212` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1866`

- [ ] [CRITICAL] Bot "Credits Balance" button is a placeholder toast instead of opening the credits screen — AyuGram navigates to `Info::BotEarn::Make(peer)` (shows actual Telegram Stars balance) — `admin_tools.dart:1220` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1925`

- [ ] [CRITICAL] Bot "Edit Intro" button is a placeholder toast — AyuGram resolves @BotFather via `MTPcontacts_ResolveUsername`, then calls `sendBotStart(show, bot, bot, "<username>-intro")` and opens the BotFather conversation — `admin_tools.dart:1236` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1998,2590-2606`

- [ ] [CRITICAL] Bot "Edit Commands" button is a placeholder toast — AyuGram resolves @BotFather and calls `sendBotStart(show, bot, bot, "<username>-commands")` — `admin_tools.dart:1244` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:2010,2590-2606`

- [ ] [CRITICAL] Bot "Edit Settings" button is a placeholder toast — AyuGram resolves @BotFather and calls `sendBotStart(show, bot, bot, "<username>")` (no suffix for general settings) — `admin_tools.dart:1252` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:2022,2590-2606`

- [ ] [MAJOR] Admin log `_actionDescription()` missing `change_location` event — AyuGram handles `MTPDchannelAdminLogEventActionChangeLocation` and shows "changed group location" / "removed group location" — `admin_tools.dart:4438-4543` ← `AyuGram/history/admin_log/history_admin_log_item.cpp:1347-1374`

- [ ] [MAJOR] Admin log `_actionDescription()` missing `toggle_autotranslation` event — AyuGram handles `MTPDchannelAdminLogEventActionToggleAutotranslation` and shows "enabled/disabled auto-translation" — `admin_tools.dart:4438-4543` ← `AyuGram/history/admin_log/history_admin_log_item.cpp:2155-2165`

- [ ] [MAJOR] Admin log `_actionDescription()` missing `participant_edit_rank` event — AyuGram handles `MTPDchannelAdminLogEventActionParticipantEditRank` showing who changed which custom rank — `admin_tools.dart:4438-4543` ← `AyuGram/history/admin_log/history_admin_log_item.cpp:2167-2240`

# bridge_stub.dart — No issues found

## Summary
The stub bridge implementation is **correctly designed and fully implements the expected FFI bridge interface**. All required methods are present with matching signatures and correct behavior for a fallback stub.

## Interface Verification
- ✅ `events` property returns empty stream (correct for no-emit stub)
- ✅ `isInitialized` property returns false (never initialized)
- ✅ `init()` throws UnsupportedError (correct for unsupported platform)
- ✅ `call()` throws UnsupportedError (correct for unsupported platform)  
- ✅ `callAsync()` throws UnsupportedError (correct for unsupported platform)
- ✅ `dispose()` is no-op (correct, nothing to dispose)

## Design Correctness
The stub is a proper compile-time fallback selected by conditional imports in `bridge.dart:9-11` when neither FFI (native platforms) nor web (WASM) implementations are available. It loudly fails at runtime rather than silently succeeding, which is the correct behavior.

All method signatures match both the FFI implementation (`bridge_ffi.dart`) and web implementation (`bridge_web.dart`).

**No critical, major, or minor issues detected.**

# advanced_settings_screen — Audit

## advanced_settings_screen — Backend wiring and behavioral issues

- [ ] [CRITICAL] `SetProxy` engine call is fired (`app_state.dart:2086`) but `dispatch_engine.go` has **no handler** for `"SetProxy"` (only `"GetCacheSize"` and `"ClearCache"` exist at lines 1114/1121). Proxy mode changes are persisted to local prefs and a Dart-side socket check is done, but the Go engine/MTP layer is never told to use the proxy. In AyuGram, `ProxiesBoxController::setProxySettings()` calls `Core::App().setCurrentProxy()` → `_account->mtp().restart()` which actually reroutes network traffic. — `advanced_settings_screen.dart:393-396` / `app_state.dart:2086-2097` ← `settings_advanced.cpp:126-132` / `connection_box.cpp:2168-2185`

- [ ] [CRITICAL] `SetAutoDownload` engine call is fired (`app_state.dart:2104`) but `dispatch_engine.go` has **no handler** for `"SetAutoDownload"`. AyuGram's `AutoDownloadBox::setupContent()` saves settings via `_session->settings().autoDownload().setBytesLimit()` then calls `_session->saveSettingsDelayed()`, `_session->data().photoLoadSettingsChanged()`, and `_session->data().documentLoadSettingsChanged()` which trigger actual download behavior changes. The Dart side stores preferences and fires a dead engine call — the engine never restricts/allows media downloads. — `advanced_settings_screen.dart:1446-1458` / `app_state.dart:2100-2107` ← `auto_download_box.cpp:160-223`

- [ ] [CRITICAL] Window close behavior (§14.7.4) — the "Run in background / Close to taskbar / Quit" radio state (`windowCloseBehavior`) is stored and displayed, but **the Linux runner `on_window_delete` always hides to tray when `self->indicator` exists, ignoring the setting entirely** (line 463-478 of `my_application.cc`). AyuGram's `BuildWindowCloseBehaviorSection` writes `settings->setCloseBehavior()` which drives the actual close behavior via `workModeValue()` subscription and the `Tray` object. The Dart setting has no effect on the actual window close action. — `advanced_settings_screen.dart:633-657` / `app_state.dart:2188-2193` ← `settings_advanced.cpp:352-412` / `connection_box.cpp:2198-2212`

- [ ] [CRITICAL] Screen reader section logic is inverted. AyuGram (`settings_advanced.cpp:1185-1187`) shows the section **only when BOTH `detected == true` AND `disabled == true`** (i.e., only when a reader is active but the optimization mode has been disabled — effectively showing a "re-enable" toggle). The Dart implementation shows the section whenever `_screenReaderDetected == true`, which is the wrong condition. Furthermore, the toggle label in Dart is "Optimize for screen readers" (enabling → optimize), while AyuGram's toggle (`lng_screen_reader_settings_disable`) is a "Disable optimization" toggle (inverted semantics — checked = disabled). — `advanced_settings_screen.dart:1106-1126` ← `settings_advanced.cpp:1184-1221`

- [ ] [CRITICAL] Screen reader toggle (`setScreenReaderOptimized`) saves to prefs only and calls `notifyListeners()` (`app_state.dart:2002-2007`). AyuGram calls `Ui::SetScreenReaderModeDisabled(value)` which is a runtime global that immediately changes accessibility behavior. There is no Flutter/engine call to actually enable screen reader optimization. — `advanced_settings_screen.dart:1117-1125` / `app_state.dart:2002-2007` ← `settings_advanced.cpp:1207-1217`

- [ ] [CRITICAL] Hardware acceleration for video toggle (`setHardwareAccelVideo`) only saves to prefs (`app_state.dart:1939-1944`). AyuGram calls `Core::App().settings().setHardwareAcceleratedVideo(enabled)` → `Core::App().saveSettingsDelayed()`, which persists to a settings file that the media pipeline reads at startup. The Dart setting is never applied to any video decoder. — `advanced_settings_screen.dart:824-831` / `app_state.dart:1939-1944` ← `settings_advanced.cpp:846-864`

- [ ] [CRITICAL] Spellchecker toggle (`setSpellcheckerEnabled`) and auto-download dictionaries toggle (`setSpellcheckerAutoDownload`) only save to prefs and call `notifyListeners()`. There is no Flutter spellcheck integration (`SpellCheckConfig` is not used anywhere in the codebase). AyuGram calls `settings->setSpellcheckerEnabled()` → `Core::App().saveSettingsDelayed()` which the actual Qt spellcheck backend reads. The Dart setting has no effect on text input fields. — `advanced_settings_screen.dart:1052-1080` / `app_state.dart:1988-2000` ← `settings_advanced.cpp:877-946`

- [ ] [CRITICAL] "Manage Dictionaries" dialog in Dart scans `/usr/share/hunspell` for `.dic` files and lists them as read-only information. AyuGram's `Ui::ManageDictionariesBox` (called at `settings_advanced.cpp:937`) allows downloading and enabling/disabling dictionaries for the actual spellchecker. The Dart dialog provides no ability to download or activate dictionaries; it only lists already-installed system files. — `advanced_settings_screen.dart:2121-2279` ← `settings_advanced.cpp:932-942`

- [ ] [CRITICAL] Update section — the "Update UniClient" button when a new version is available opens a browser link to GitHub releases (`_openWithSystem(...releases/tag/v$_latestVersion)`). AyuGram's `update->setClickedCallback` calls `Core::checkReadyUpdate()` then `Core::Restart()` to apply a downloaded update in-place. The Dart implementation cannot download or apply updates; it redirects the user to manually download and replace the binary. — `advanced_settings_screen.dart:326-358` ← `settings_advanced.cpp:1139-1145`

- [ ] [CRITICAL] Recent Downloads ("Downloads" button) opens a Dart-only custom dialog (`_RecentDownloadsBox`) that reads from `appState.recentDownloads` (an in-memory list). AyuGram opens the `Info::Downloads` section (`settings_advanced.cpp:181-183`) which shows all active and completed downloads managed by the real MTProto download manager. The Dart list is not populated by engine download events — it is only as complete as whatever was recorded in local prefs. Newly downloaded files from the chat are not reflected unless explicitly tracked. — `advanced_settings_screen.dart:422-432` ← `settings_advanced.cpp:174-185`

- [ ] [MAJOR] Proxy validation in `_checkProxy()` / `_validateProtocol()` tests TCP socket connectivity with a basic SOCKS5 handshake (`advanced_settings_screen.dart:2704-2755`). AyuGram uses `MTP::ResetProxyCheckers()` with full MTP connection probing (`connection_box.cpp:1798`). The Dart check can report "available" for a proxy that doesn't route Telegram's MTProto traffic (e.g., an HTTP-CONNECT proxy that works for HTTP but not MTPROTO). — `advanced_settings_screen.dart:2704-2755` ← `connection_box.cpp:1894-1939`

- [ ] [MAJOR] Proxy rotation feature is absent. AyuGram's connection_box has a full proxy rotation UI: a "Rotate proxies" checkbox with a rotation timeout slider (`connection_box.cpp:1091-1130`). The Dart ProxiesBox has no proxy rotation toggle or timeout control, despite AyuGram persisting `proxyRotationEnabled` and `proxyRotationTimeout` settings. — `advanced_settings_screen.dart:2590-3426` ← `connection_box.cpp:569-571, 1091-1130`

- [ ] [MAJOR] Window close behavior section is shown on **all Linux** builds (`advanced_settings_screen.dart:635`: `if (!Platform.isLinux) return const []`). AyuGram only shows this section on non-Windows, non-macOS platforms **and** only when `Platform::TrayIconSupported()` is true — when no tray is available, the section is wrapped in a `builder.scope(... std::move(shown))` that hides it entirely (`settings_advanced.cpp:356-412`). If the tray is not available, the "Run in background" option is meaningless. — `advanced_settings_screen.dart:635` ← `settings_advanced.cpp:356-362`

- [ ] [MAJOR] Native window frame option is shown only when `Platform.isLinux` (`advanced_settings_screen.dart:621`). AyuGram guards with `Ui::Platform::NativeWindowFrameSupported()` and additionally shows different labels for Wayland ("Use Qt window frame") vs X11 ("Use system window frame") (`settings_advanced.cpp:329-345`). The Dart always uses "Use system window frame" regardless of Wayland/X11, and doesn't check if the platform actually supports a native frame (e.g., some compositors may not). — `advanced_settings_screen.dart:621-629` ← `settings_advanced.cpp:328-346`

- [ ] [MAJOR] OpenGL toggle (`setOpenGlDisabled`) only saves to prefs (`app_state.dart:1946-1951`). AyuGram calls `Core::App().settings().setDisableOpenGL(!enabled)` → `Local::writeSettings()` → `Core::Restart()` (confirmed restart dialog is shown, `settings_advanced.cpp:811-822`). While the Dart code does show a restart dialog (`_showRestartDialog`) and calls `_restartApp()` (process restart via `Platform.resolvedExecutable`), the OpenGL flag itself is never passed to the Flutter engine — Flutter always uses its own renderer regardless. — `advanced_settings_screen.dart:843-854` / `app_state.dart:1946-1951` ← `settings_advanced.cpp:796-824`

- [ ] [MAJOR] Auto power saving ("Automatic Power Saving") toggle in the Dart `PowerSavingBox` only stores a preference (`app_state.dart:2377-2382`). AyuGram's `PowerSavingBox` wires the automatic toggle to `Core::App().batterySaving().value()` — an OS-level battery API (`base/battery_saving.h`) that detects actual power-saver mode and automatically adjusts the `PowerSaving::kAll` flags. The Dart `_detectBattery()` checks `/sys/class/power_supply` but `_checkPowerSaverMode()` calls `powerprofilesctl get` — this only covers Power Profiles Daemon, not UPower or battery state APIs. The detected state is not wired to automatically apply power saving flags. — `advanced_settings_screen.dart:2312-2344` ← `settings_power_saving.cpp:39-113`

- [ ] [MAJOR] The "Export Telegram Data" button (`advanced_settings_screen.dart:1156-1166`) calls `showExportPanel(context, ExportTarget(...))`. AyuGram calls `Core::App().exportManager().start(session)` after hiding settings (`controller->window().hideSettingsAndLayer()`). Whether the Dart export panel is fully functional or a stub depends on `chat_export.dart` — but the trigger mechanism is divergent: AyuGram hides the settings layer first with a `boxDuration` delay (`settings_advanced.cpp:1165-1172`), while Dart pops to root and uses a 150ms delay, which may cause context issues. — `advanced_settings_screen.dart:1157-1165` ← `settings_advanced.cpp:1161-1172`

# auth_screen — Auth screen behavioral and wiring issues

- [ ] [CRITICAL] Language picker stores `_selectedLanguageCode` preference but never downloads or applies Telegram language packs from the API — picker appears fully functional but is not engine-wired; AyuGram fetches packs via `lang_cloud_manager` on selection — `auth_screen.dart:2150-2170,2236` ← `AyuGram/Telegram/SourceFiles/lang/lang_cloud_manager.cpp`

- [ ] [MAJOR] `SRP_ID_INVALID` maps to the string `'Session expired, retrying...'` but nothing in the Dart actually re-fetches password data; AyuGram calls `requestPasswordData()` → `MTPaccount_GetPassword` to obtain fresh SRP parameters before retrying — without this the user is stuck on the 2FA screen — `auth_screen.dart:743` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_password_check.cpp:157-177`

- [ ] [MAJOR] `"Didn't get the code?"` button rendered unconditionally inside `_OtpCodeInput`; AyuGram's equivalent (`_noTelegramCode` / "No Telegram account?") is only shown when `getData()->codeByTelegram == true` — when code is delivered via SMS the button must be hidden — `auth_screen.dart:1957-1966` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_code.cpp:103-107`

- [ ] [MAJOR] `PASSWORD_RECOVERY_EXPIRED` is mapped to an error string but the UI stays in recovery mode; AyuGram clears `_emailPattern` and calls `toPassword()` to return the user to password entry — `auth_screen.dart:749` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_password_check.cpp:260-262`

- [ ] [MAJOR] `PASSWORD_RECOVERY_NA` is mapped to the string `'Recovery not available.'` but the reset button is never shown; AyuGram's `recoverStartFail()` calls `showReset()` → `showResetButton()` so the user can still reset the account — `auth_screen.dart:749` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_password_check.cpp:258-259,334-345`

- [ ] [MAJOR] `_CoverGradient` is displayed statically during `qr` and `input` (phone) steps; every AyuGram intro step is constructed with `hasCover = false` (default), so the cover gradient is never statically visible — it only appears during cross-step transition animations — showing it as a persistent 208 px header for those two steps has no equivalent in AyuGram — `auth_screen.dart:137,367-370` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_step.cpp:325-326`, `intro_phone.cpp:54`, `intro_qr.cpp:198`

# ayu_appearance_page — Audit findings

- [ ] [CRITICAL] App icon change not applied to running app: selecting an icon only calls `appState.setAppIcon(v)` (state save) but never calls the equivalent of `applyIcon()` — no window icon refresh, no tray icon update, no notification badge refresh — `ayu_appearance_page.dart:988` ← `AyuGram/ayu/ui/components/icon_picker.cpp:42-52,178` (`applyIcon()` calls `Window::OverrideApplicationIcon`, `refreshApplicationIcon`, `tray().updateIconCounters`, `notifyUnreadBadgeChanged`)

- [ ] [CRITICAL] `exit(0)` used instead of graceful restart: both the avatar-corners restart dialog (dart:281) and the font-change restart dialog (dart:906) call `exit(0)` which hard-kills the process with no state flushing — `ayu_appearance_page.dart:281,906` ← `AyuGram/ayu/ui/settings/settings_ayu_utils.cpp:36-43` (`ShowRestartPrompt` uses `Core::Restart()` for graceful restart with confirmation)

- [ ] [MAJOR] Icon picker deselection has no fade-out animation: `_prevSelected` is tracked (dart:987) but `wasPrev` (dart:983) is never used in the `AnimatedOpacity` opacity expression — old selection snaps instantly to opacity 0 while new one fades in; C++ crossfades both simultaneously — `ayu_appearance_page.dart:983,994-998` ← `AyuGram/ayu/ui/components/icon_picker.cpp:119-129` (`opacity = 1.0f - _animation.value(1.0f)` for old, `_animation.value(1.0f)` for new)

- [ ] [MAJOR] Font selector has no keyboard navigation: Dart dialog has no key handler for `Up`/`Down`/`PageUp`/`PageDown` to move selection through the font list — `ayu_appearance_page.dart:759-888` ← `AyuGram/ayu/ui/boxes/font_selector.cpp:967-989` (`keyPressEvent` handles `Key_Up`, `Key_Down`, `Key_PageUp`, `Key_PageDown` with scroll-to-selected)

# ayu_chats_page — Audit Findings

- [ ] [CRITICAL] `_MessagePreviewStandalone` is a static Flutter mockup with hardcoded fake bubbles — AyuGram's `MessagePreview` renders real `HistoryItem` objects through the full Telegram rendering pipeline (`view->draw(p, context)`), subscribes to all relevant settings changes via `rpl::merge(...)` and calls `refresh()` automatically. The Dart version approximates appearance but cannot reflect how messages actually render (font metrics, actual theme colors, real bubble geometry from `Ui::SetBubbleRadiusOverride`). The preview is non-authoritative. — `ayu_chats_page.dart:643` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/components/message_preview.cpp:52-140`

- [ ] [CRITICAL] Wide multiplier `min` is `0.5` in Dart but `kMinSize = 1.00` in AyuGram — allows 10 invalid extra values (0.50–0.95) that AyuGram never permits — `ayu_chats_page.dart:363` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:241`

- [ ] [MAJOR] Wide multiplier `divisions: 70` in Dart but AyuGram uses 61 steps (`(4.00 - 1.00) / 0.05 + 1 = 61`) — with correct `min=1.0` that means `divisions=60`; Dart's 70 divisions produce 71 discrete positions over the wrong range — `ayu_chats_page.dart:365` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:277`

- [ ] [MAJOR] Recent Stickers Count slider `steps: 200` is off-by-one — AyuGram uses `.steps = 200 + 1` (201 steps, yielding values 0–200); Dart's 200 steps only reaches index 199 — `ayu_chats_page.dart:61` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:79`

- [ ] [MAJOR] Bubble radius slider does not update the preview in real-time during drag — AyuGram fires `previewState->widget->setBubbleRadius(index)` on every `onChanged` tick (during drag); Dart only calls `widget.onChanged` inside `onChangeEnd` after a blocking confirm dialog. Preview stays stale while dragging — `ayu_chats_page.dart:474-490` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:255-265`

- [ ] [MAJOR] Context menu description text is shown **before** the choose-buttons in Dart but AyuGram places it **after** all buttons (`builder.addSkip(); builder.addDividerText(...); builder.addSkip();` at the end of `BuildContextMenuElements`) — `ayu_chats_page.dart:176-179` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:373-375`

- [ ] [MAJOR] Missing section divider between the stickers toggles and the Recent Stickers Count slider — AyuGram's `BuildStickersAndEmoji` ends with `ayu.addSectionDivider()` before `BuildRecentStickersLimit` is called, creating a visual break; Dart places the slider directly after the reactions toggle with no intervening divider — `ayu_chats_page.dart:58-66` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:70,73`

- [ ] [MAJOR] Message Shot description uses `b.addDescription(...)` widget directly after the toggle, with no surrounding skips — AyuGram wraps it as `builder.addSkip(); builder.addDividerText(...); builder.addSkip();` (styled `DividerText` with vertical spacing on both sides) — `ayu_chats_page.dart:90-91` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:127-129`

- [ ] [MAJOR] Wide multiplier description text is missing — AyuGram renders `builder.addDividerText(tr::ayu_SettingsWideMultiplierDescription())` with surrounding skips after the wide multiplier slider; Dart renders it inline as a plain `Text` inside `_WideMultiplierSliderState.build` without the divider-text style — `ayu_chats_page.dart:387-392` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:291-293`

- [ ] [MAJOR] Bubble radius `onFinalChanged` in AyuGram applies the setting **immediately** then shows a non-blocking restart prompt via `ShowRestartPrompt(controller)` — Dart instead shows a **blocking** confirm dialog before applying, and cancelling the dialog reverts the slider. This is a UX contract inversion — `ayu_chats_page.dart:478-489` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:260-265`

# ayu_filters_page — Audit findings

- [ ] [CRITICAL] "Restrict" snackbar action adds a global exclusion (telling the engine "don't apply this shared filter in this dialog") instead of converting the filter to a per-dialog filter (setting `filter.dialogId = dialogId` and updating it so it is no longer shared). The user sees "Tap to restrict to this dialog" but the code does the opposite — it excludes the newly-created shared filter from the current dialog rather than binding it to that dialog. — `ayu_filters_page.dart:1270-1274` ← `AyuGram/ayu/ui/settings/filters/edit_filter.cpp:228-239`

- [ ] [MAJOR] Export `_doExport` collects `dialogId` values from both per-dialog filters **and** exclusions when building the `peers` hint map, so the exported JSON contains peer hints for dialog IDs that only appear as exclusion targets. AyuGram only collects peers from filters whose `dialogId` is non-null (per-dialog filters), never from exclusions. — `ayu_filters_page.dart:1711-1713` ← `AyuGram/ayu/features/filters/filters_utils.cpp:511-514`

- [ ] [MAJOR] `_ShadowBanRowState._resolvePeerInfo()` resolves a shadow-banned peer by checking `chat.chatId.endsWith(idStr)` as a fallback. Telegram channel IDs are stored as `-100XXXXXXXXXX` so the bare numeric part can appear as a suffix of unrelated IDs, potentially matching the wrong peer. AyuGram strips the sign and applies `PeerId::kChatTypeMask` bit-masking (`abs(dialogId)` + `PeerIdHelper`) to get the correct peer regardless of sign or type prefix. — `ayu_filters_page.dart:1039` ← `AyuGram/ayu/ui/settings/filters/per_dialog_filter.cpp:28-29,36`

# ayugram_settings_screen — Category icon mismatches

- [ ] [MAJOR] "AyuGram" category button uses `Icons.favorite_border` (heart outline) but AyuGram uses `menuIconGroupReactions` → `"menu/group_reactions"` (animated emoji reactions icon) — `ayugram_settings_screen.dart:136` ← `AyuGram/ayu/ui/settings/settings_main.cpp:106` + `AyuGram/ui/menu_icons.style:140`

- [ ] [MAJOR] "Filters" category button uses `Icons.filter_list` but AyuGram uses `menuIconTagFilter` → `"menu/tag_filter"` — `ayugram_settings_screen.dart:142` ← `AyuGram/ayu/ui/settings/settings_main.cpp:109` + `AyuGram/ui/menu_icons.style:165`

- [ ] [MAJOR] "General" category button uses `Icons.grid_view` but AyuGram uses `menuIconShowAll` → `"menu/all_media"` (show-all icon, not a grid) — `ayugram_settings_screen.dart:148` ← `AyuGram/ayu/ui/settings/settings_main.cpp:113` + `AyuGram/ui/menu_icons.style:153`

- [ ] [MAJOR] "Other" category button uses `Icons.star` but AyuGram uses `menuIconFave` → `"menu/favorite"` (Telegram's specific favorites star asset) — `ayugram_settings_screen.dart:167` ← `AyuGram/ayu/ui/settings/settings_main.cpp:131` + `AyuGram/ui/menu_icons.style:37`

# ayu_other_page — 4 issues

- [ ] [CRITICAL] Donation amounts (USD/TON/RUB) and donate username are compile-time `String.fromEnvironment()` constants with hardcoded defaults (`'5.00'`, `'3.50'`, `'386'`, `'RadianceTG'`); AyuGram fetches all four values at runtime via `RCManager` which polls `https://update.ayugram.one/rc/current/desktop2` every hour (with extera fallback), so they can change without an app rebuild — `ayu_other_page.dart:421-428` ← `rc_manager.cpp:179-203` + `donate_info_box.cpp:179-182`

- [ ] [MAJOR] DonateInfoBox username tap uses `launchUrl(Uri.parse('https://t.me/...'), mode: LaunchMode.externalApplication)` (opens external browser/Telegram app); AyuGram creates an in-app deep link via `controller->session().createInternalLinkFull(usernameTrimmed)` so clicking opens the user's profile/chat within the client — `ayu_other_page.dart:443-445` ← `donate_info_box.cpp:211`

- [ ] [MAJOR] `_SupportDescription` wraps the entire paragraph in `InkWell` making all text tappable; AyuGram uses `AddDividerText` with `Ui::Text::Link(...)` so only the "contact support" span is a link — `ayu_other_page.dart:394-415` ← `settings_other.cpp:161-167`

- [ ] [MAJOR] QR box address display uses `SelectableText` (plain selectable label); AyuGram uses `Ui::InviteLinkLabel` which is a specialized copyable-link widget with dedicated visual treatment for addresses — `ayu_other_page.dart:665-668` ← `donate_qr_box.cpp:142-146`

# ayu_section_builder — Settings Section Builder Audit

- [ ] [MAJOR] Nested checkbox left padding 44px vs AyuGram's 57px (23% off) — `ayu_section_builder.dart:770` ← `settings.style:567` (`powerSavingButton: padding: margins(57px, 8px, 22px, 8px)`) + `settings_ayu_utils.cpp:233`

- [ ] [MAJOR] Nested checkbox vertical padding 6px top/bottom vs AyuGram's 8px (25% off) — `ayu_section_builder.dart:770` ← `settings.style:568` (`powerSavingButton: padding: margins(57px, 8px, 22px, 8px)`)

- [ ] [MAJOR] Toggle row bottom padding 10px vs AyuGram's 8px for no-icon variant (25% off) — `ayu_section_builder.dart:274` (`EdgeInsets.symmetric(vertical: 10)`) ← `settings.style:26` (`settingsButtonNoIcon: padding: margins(22px, 10px, 22px, 8px)`)

- [ ] [MAJOR] `_NestedCheckbox` uses plain `GestureDetector` with no ripple feedback; AyuGram creates a `Ui::RippleButton` child stacked behind each checkbox to provide click ripple — `ayu_section_builder.dart:756` ← `settings_ayu_utils.cpp:364` (`Ui::CreateChild<Ui::RippleButton>(verticalLayout, st::defaultRippleAnimation)`)

# ayu_toggle — No issues found

Comprehensive comparison against AyuGram Desktop ToggleView (lib_ui/ui/widgets/checkbox.cpp:108-148, checkbox.h:141-163) and style definitions (lib_ui/ui/widgets/widgets.style:874-890).

**Dimensions verified:**
- Border: 2px ✓ (ayu_toggle.dart:54 ← widgets.style:880)
- Diameter: 14px (material), 16px (default) ✓ (ayu_toggle.dart:55,61 ← widgets.style:882,873)
- Width: 14px ✓ (ayu_toggle.dart:56 ← widgets.style:883)
- Shift: -2px (material), 1px (default) ✓ (ayu_toggle.dart:57,62 ← widgets.style:881,872)
- Anim padding: 2px ✓ (ayu_toggle.dart:58 ← widgets.style:884)

**Animation verified:**
- Duration: 150ms ✓ (ayu_toggle.dart:30 ← widgets.style:879)
- Curve: easeOutCubic (material), linear (default) ✓ (ayu_toggle.dart:68 ← checkbox.cpp:62)
- Direction: forward=true, reverse=false ✓ (ayu_toggle.dart:39-42 ← checkbox.cpp:57-62)

**Color interpolation verified:**
- Track: checkboxFg → windowBgActive ✓ (ayu_toggle.dart:84 ← checkbox.cpp:120, widgets.style:878,876)
- Thumb fill: always windowBg ✓ (ayu_toggle.dart:96 ← checkbox.cpp:135, widgets.style:877,875)
- Thumb border: checkboxFg → windowBgActive ✓ (ayu_toggle.dart:164 ← checkbox.cpp:132-133)

**Paint logic verified:**
- Track rendering (rounded rect with foreground color) ✓ (ayu_toggle.dart:144 ← checkbox.cpp:129-130)
- Thumb position interpolation ✓ (ayu_toggle.dart:147 ← checkbox.cpp:117)
- Material animPadding deflation ✓ (ayu_toggle.dart:152-155 ← checkbox.cpp:123-126)
- Thumb fill and border drawing ✓ (ayu_toggle.dart:158-167 ← checkbox.cpp:135-136)

**State management verified:**
- initState properly creates AnimationController ✓ (ayu_toggle.dart:26-33)
- didUpdateWidget handles value changes ✓ (ayu_toggle.dart:36-45 ← checkbox.cpp:48-68)
- dispose properly cleans up controller ✓ (ayu_toggle.dart:48-51)

**Callback wiring verified:**
- onTap invokes onChanged with inverted value ✓ (ayu_toggle.dart:77)

**Size calculation verified:**
- Total width: 2×border + diameter + width ✓ (ayu_toggle.dart:73 ← checkbox.cpp:101)
- Total height: 2×border + diameter ✓ (ayu_toggle.dart:74 ← checkbox.cpp:101)

**Paint optimization verified:**
- shouldRepaint checks all dynamic properties (t, fgColor, bgColor) ✓ (ayu_toggle.dart:173-174)

**Notes:**
- Ripple animation, X/V marks, and locked state are not present in Dart, but these features are disabled in the default toggle style (xsize=0, vsize=0, stroke=0, all unused in AyuGram for standard toggles)
- Canvas clipping in Dart (line 130) is a safe addition not present in AyuGram paint method
- All color references resolved correctly from theme palette

**Conclusion:** Widget is a faithful, fully-functional port of AyuGram's ToggleView with no missing features for the default style and no implementation bugs.

# call_panel — Call Panel UI

- [ ] [CRITICAL] `showScreenShareChooser` is not imported — called at `call_panel.dart:342` but only defined in `call_screen.dart:2363`; `call_panel.dart` has no `import 'call_screen.dart'` (imports at lines 1–18). This is an unresolved identifier that breaks screen sharing — `_onScreenShareTap` will throw a compile/runtime error. ← `AyuGramDesktop/Telegram/SourceFiles/calls/calls_panel.cpp:394` (screen share toggle is fully wired)

- [ ] [CRITICAL] Signal quality scale mismatch — `call_panel.dart:1926-1927` computes `(quality * _barCount / 100).ceil()` treating `quality` as a 0–100 percentage. The engine bridge returns 0–4 directly (matching AyuGram `Call::kSignalBarCount = 4`; confirmed by `engine_models.dart:2526` defaulting `signalQuality = 4`). At full signal (quality=4): `(4×4/100)⌈⌉ = 1` — shows only 1 of 4 bars. Correct mapping is `quality.clamp(0, _barCount)`. ← `AyuGramDesktop/Telegram/SourceFiles/calls/calls_signal_bars.cpp:38-39` (`i < _count` where `_count` is 0–4 directly)

- [ ] [CRITICAL] Rating dialog shown unconditionally on every call close — `call_panel.dart:2179-2183` always calls `showCallRatingDialog(context, callId: effectiveCallId)` regardless of server intent. AyuGram only shows the rating box when the server sets `need_rating` on the `PhoneCallDiscarded` update (`calls_call.cpp:809`). This will display a rating prompt after every call including ones the user declines or that fail. ← `AyuGramDesktop/Telegram/SourceFiles/calls/calls_call.cpp:809`

- [ ] [CRITICAL] `showCallPanel` dialog state is frozen at creation — `call_panel.dart:2173` calls `showDialog` capturing a static `CallPanelInfo` object. There is no mechanism to push state updates into the dialog after it is shown (no `StatefulBuilder`, no stream, no `Provider` rebuild scope). Accepting an incoming call (`onAccept` at line 2201) fires `engine.acceptCall` but the panel stays on the `incoming` UI with Decline/Answer buttons forever — it never transitions to `connecting`/`active`, never shows the controls row, never updates mute/camera state, never shows video streams. AyuGram's panel is a live reactive widget updated via `replaceCall()` and observable streams. ← `AyuGramDesktop/Telegram/SourceFiles/calls/calls_panel.cpp:1126-1150` (`requestControlsHidden`/`updateControlsShown` react to live state changes)

- [ ] [MAJOR] Controls auto-hide never fires while mouse is stationary over panel in non-fullscreen video mode — `call_panel.dart:304-310` `_onMouseMove()` only schedules the hide timer (`_kHideControlsFullscreen = 5s`) when `widget.info.isFullscreen`. In non-fullscreen video mode, `onHover`/`onEnter` show controls but no hide timer is started; controls only hide when mouse exits (2s). In AyuGram, any mouse movement in a windowed video call restarts `kHideControlsQuickTimeout` (2s), so controls auto-hide after 2s of inactivity even when not fullscreen. ← `AyuGramDesktop/Telegram/SourceFiles/calls/calls_panel.cpp:79,309` (`kHideControlsQuickTimeout = 2s` applies to all video modes)

- [ ] [MAJOR] 1-to-conference upgrade has a race condition that can orphan the user — `call_panel.dart:435-443`: `createConferenceCall` → `endCall` (existing 1:1) → `joinGroupCall` → `inviteToConferenceCall`. If `createConferenceCall` succeeds but the subsequent `endCall` or `joinGroupCall` throws, the original 1:1 call is terminated with no conference to fall back into. AyuGram handles this atomically server-side via `phone.upgradePherenceCall` / migration path in `calls_instance.cpp:startOrJoinConferenceCall`. ← `AyuGramDesktop/Telegram/SourceFiles/calls/calls_instance.cpp` (`startOrJoinConferenceCall` with atomic migration)

# call_screen — GroupCallPanel / MinimisedCallBar audit

## Issues

- [ ] [CRITICAL] "Start Recording" menu item calls `engine.toggleScreenSharing(accountId, callId, false)` instead of a recording API — it literally disables screen sharing instead of starting recording — `call_screen.dart:1229` ← `calls/group/calls_group_panel.cpp:1325` (should call `StartCallRecording`)

- [ ] [CRITICAL] Active-state gradient colors for MinimisedCallBar are wrong: Dart uses `[0xFF52CE5B, 0xFF00B151]` for "active" (both personal and group call). AyuGram uses `groupCallLive1=#0dcc39` / `groupCallLive2=#0bb6bd` (teal second stop, not pure green). Dart omits the teal entirely — `call_screen.dart:1741,1751` ← `calls_top_bar.cpp:118` + `colors.palette:582-583`

- [ ] [CRITICAL] MinimisedCallBar muted-state gradient is wrong: Dart uses `[0xFF5B6BBE, 0xFF7B68EE]` (custom blue/purple). AyuGram uses `groupCallMuted1=#0992ef` / `groupCallMuted2=#16ccfb` (bright blue/cyan). Deviation >25% — `call_screen.dart:1753` ← `colors.palette:584-585`

- [ ] [CRITICAL] MinimisedCallBar force-muted gradient is wrong: Dart uses `[0xFF9B59B6, 0xFF7B68EE, 0xFF8E44AD]` (generic purple). AyuGram uses `groupCallForceMutedBar1=#c65493 / #7a6af1 / #5f95e8` (pink→purple→blue). All three stops differ by >25% — `call_screen.dart:1757` ← `calls_top_bar.cpp:110-115` + `colors.palette:586-588`

- [ ] [CRITICAL] Video button and screen-share button never show active (highlighted) state — `cameraEnabled` is toggled in a closure but never passed to `GroupCallPanel` props, and `_GroupCallControlButton.isActive` is always false for both buttons. There is no `setSbState` call for camera/screen state, so the UI never reflects the actual state — `call_screen.dart:1162-1182` vs expected `call_screen.dart:1004-1044`

- [ ] [CRITICAL] `_CallBarHangupButton` always calls `engine.leaveGroupCall(accountId, '')` with empty string callId — it has no callId available in its context (it's a standalone StatelessWidget with no callId parameter). The hangup from the minimised bar will always send empty callId to the engine — `call_screen.dart:2289, 2298, 2308`

- [ ] [MAJOR] `_BigMuteButton` blob animation only runs when `state == unmuted`, but stops when muted/forceMuted. AyuGram shows a static circle (no blobs) only when muted, which is correct, but the blob should be animated even at rest level 0 when transitioning — the Dart ticker is abruptly stopped instead of fading out over ~250ms — `call_screen.dart:789-796` ← `calls_top_bar.cpp:57` (`kHideBlobsDuration = 500ms`)

- [ ] [MAJOR] `_SpeakerBlobAvatar` blob scale constants: `_minorScale=0.414` and `_majorScale=0.138` are arbitrarily chosen. AyuGram `groupCallRowBlobMinRadius=27px` / `groupCallRowBlobMaxRadius=29px` define absolute pixel radii, not scale factors relative to the avatar radius. The Dart code derives blob size from the avatar radius via these fractional scales, producing incorrect blob sizes compared to spec. At 29px max AyuGram radius vs Dart's `29.0 * 0.414 ≈ 12px` minor and `29.0 * 0.138 ≈ 4px` major — `call_screen.dart:442-443` ← `calls.style:1144-1145`

- [ ] [MAJOR] `_BlobPainter.shouldRepaint` does not include `majorBlob`/`minorBlob` object changes — only checks `level`, `radius`, `color`. Since `_BlobState` is mutated in-place, the repaint condition misses state changes between frames when level hasn't changed, potentially freezing blob animation — `call_screen.dart:672-674`

- [ ] [MAJOR] `GroupCallPanel._buildBottomControls()` uses `padding: const EdgeInsets.fromLTRB(24, 16, 24, 113)` — the 113px bottom padding is a hardcoded guess. AyuGram uses `groupCallButtonBottomSkip: 113px` for narrow and `groupCallButtonBottomSkipWide: 108px` for wide mode, but the Dart code applies 113px in both narrow and wide layout without switching — `call_screen.dart:292` ← `calls.style:1020-1021`

- [ ] [MAJOR] `_LinearBlobsBar` always runs its animation ticker (`.repeat()` in `initState`) unconditionally, regardless of audio level. AyuGram's `LinearBlobs` stops animating when level drops to 0 for `kHideBlobsDuration=500ms` and freezes the paint. The Dart widget continues spinning its ticker even when `level=0.0`, wasting CPU every frame while the call bar is visible — `call_screen.dart:1930-1935` ← `calls_top_bar.cpp:471-528`

- [ ] [MAJOR] `_LinearBlobsPainter.shouldRepaint` compares `old.blobRadii != blobRadii` by reference — this is always `true` (different list objects), so every animation tick forces a full repaint even when nothing visually changed. Should compare by value or use identity check properly — `call_screen.dart:2007-2008`

- [ ] [MAJOR] `showGroupCallPanel` uses `GroupCallPanel.defaultHeight = 520px` for non-RTMP calls, correctly matching `groupCallHeight: 520px`. But RTMP calls use `defaultWidthRtmp=720px` and the same 520px height, whereas AyuGram uses `groupCallHeightRtmp: 580px` for RTMP — the panel is 60px shorter than spec for RTMP streams — `call_screen.dart:59-60,1100-1102` ← `calls.style:547,549`

- [ ] [MAJOR] `GroupCallPanel._formatDuration` always pads hours with leading zeros (formats `1:05:03`). AyuGram's `FormatDurationText` does NOT pad hours — it outputs `1:05:03` which is the same, but also the Dart `GroupCallPanel._formatDuration` does NOT handle hours at all (only `mm:ss`), while `MinimisedCallBar._formatDuration` does handle hours. The group call title duration will overflow to `00:00` clamped display after 99 minutes instead of switching to `h:mm:ss` format — `call_screen.dart:101-104` ← `format_values.cpp:137-140`

- [ ] [MAJOR] `_SignalBarsPainter` uses hardcoded bar heights `[3, 6, 9, 12]` and bar width `3.0` with skip `1.0`. AyuGram `callBarSignalBars` specifies `width: 3px; skip: 1px; min: 3px; max: 12px` — the heights array matches min/max but uses linear steps `[3,6,9,12]` rather than AyuGram's formula: `min + (max - min) * (i / (kSignalBarCount - 1))` which gives `[3, 6, 9, 12]` for count=4 (same result), so heights are correct. However, `inactiveOpacity: 0.5` matches `0.5` alpha used in Dart. The size `19x12` is computed as `width + (width+skip)*(count-1) = 3+4*3=15` wide, not 19 — the `19` width is wrong, should be `3+(3+1)*3=15px` — `call_screen.dart:2140` ← `calls_signal_bars.cpp:23-25`

- [ ] [MAJOR] `_GroupCallControlButton` uses circle size `48×48` for screen/video buttons. AyuGram `callButton` style defines `width: 68px; height: 79px` for control buttons with a 44px ripple area. The Dart circle is substantially smaller than spec (48 vs 44px bgSize which is the inner circle, but container is 68×79 total) — the hit area and visual size are both wrong — `call_screen.dart:1025-1029` ← `calls.style:89-98` (`callButton: 68×79`)

- [ ] [MAJOR] `_GroupCallActionButton` (hang-up button) is `56×56`. AyuGram uses `callHangup` which extends `callAnswer` with `bgSize: 44px` inside a `68×79` container — `call_screen.dart:1062-1069` ← `calls.style:130-138`

- [ ] [MAJOR] Raise-hand logic: when `forceMuted && !raisedHand`, tapping the mute button sets `raisedHand = true` and calls `engine.raiseHand(..., true)`. But there is no path to lower the hand — once raised, tapping the mute button again hits `else if (!forceMuted)` which is still false. The hand is permanently stuck raised until the admin unmutes. AyuGram lowers the hand if already raised on the same tap — `call_screen.dart:1149-1159` ← `calls_group_panel.cpp:591-596`

## calls_screen — Calls Box, Create Call, Group Calls, Call Settings

- [ ] [CRITICAL] Active group call detection uses a polling scan of up to 200 chats on open, rather than subscribing to `PeerUpdate::Flag::GroupCall` data layer events. AyuGram's `ListController::prepare()` registers a `session().changes().peerUpdates(Flag::GroupCall)` reactive subscription so the list auto-updates whenever any peer's group-call status changes, without rescanning. The Dart code's `_onGroupCallEvent` stream fires only after `_initialGroupCallLoadDone` is set, meaning there is a window where events are silently dropped while the initial scan is in progress. — `calls_screen.dart:180-209`, `calls_screen.dart:211-213` ← `calls_box_controller.cpp:193-214`

- [ ] [CRITICAL] `_loadAlreadyInParticipants()` calls `engine.getGroupCall(accountId, '')` with an **empty chatId string**. This will either fail or return wrong data. AyuGram passes the real peer ID to resolve already-in participants from the active conference. This causes the "already in this call" status in `_ConfInviteRow` to never be shown correctly when creating a call from an existing context. — `calls_screen.dart:988-996` ← `calls_group_invite_controller.cpp:818-828`

- [ ] [CRITICAL] `_CallSettingsScreen` enumerates audio devices by spawning OS processes (`pactl`, `v4l2-ctl`, `system_profiler`, `powershell`) instead of calling the engine via `engine.getAudioDevices()`. The engine path is a fallback that runs only when the platform is not Linux. AyuGram uses a `Webrtc::DeviceResolver` + `Core::App().mediaDevices().devicesValue()` reactive stream to keep the device list live and automatically react to plug/unplug events. The subprocess approach is one-shot and misses hot-plug device changes. — `calls_screen.dart:2283-2402` ← `settings_calls.cpp:57-70`, `settings_calls.cpp:93-153`

- [ ] [CRITICAL] Call settings screen is reached via `Navigator.push` to a full `Scaffold`-based `_CallSettingsScreen`, but AyuGram navigates to `Settings::CallsId()` — the existing Settings section — with `window->showSettings(Settings::CallsId(), ...)`. The Dart screen is a parallel, standalone widget that diverges from the main settings flow and will not appear inside the settings navigation stack. — `calls_screen.dart:299-304` ← `calls_box_controller.cpp:876-879`

- [ ] [MAJOR] Group call join button (right-action icon) calls `engine.joinGroupCall(chat.accountId, chat.chatId)` without first opening a group call panel/screen. AyuGram's right-action for `GroupCallRow` calls `_window->startOrJoinGroupCall(row->peer())` which navigates to the group call screen, handles microphone permission, and handles the "already in a different call" conflict. The Dart code fires the join and silently swallows any error (`catch (_) {}`), leaving the user with no feedback and no call screen. — `calls_screen.dart:710-715` ← `calls_box_controller.cpp:247-249`

- [ ] [MAJOR] `_CallHistoryRow` row-click navigates by jumping to the message via timestamp (`group.newest.timestamp * 1000`) as the offset, but AyuGram uses `itemId` (message ID) directly: `window->showPeerHistory(peer, Way::ClearStack, itemId)`. Using a timestamp as a scroll offset is unreliable and may land on the wrong message or nowhere. — `calls_screen.dart:2094-2100` ← `calls_box_controller.cpp:600-610`

- [ ] [MAJOR] `_startRedial` always dials with `video: false`, ignoring `group.isVideo`. AyuGram's `rowRightActionClicked` calls `Core::App().calls().startOutgoingCall(user, {})` and determines call type from the row's `CallType` enum set from `ComputeCallType()` which checks `call->video`. The Dart redial button icon changes based on `group.isVideo` but the actual dial call doesn't honour it. — `calls_screen.dart:2055-2065` ← `calls_box_controller.cpp:456-466`, `calls_box_controller.cpp:612-617`

- [ ] [MAJOR] `_GroupCallRow` has no "Active Video Chats" subsection title. AyuGram renders `Ui::AddSubsectionTitle(groupCalls->entity(), tr::lng_call_box_groupcalls_subtitle())` — the string is "Active video chats" — above the group call list. The Dart code uses the section header text "Active Group Calls" instead of "Active video chats", and as a plain `Text` widget rather than the subsection-title style (smaller, uppercase-like accent color). — `calls_screen.dart:559-566` ← `calls_box_controller.cpp:835-837`

- [ ] [MAJOR] `_ConfInviteRow.elementsCount()` in AyuGram returns 0 for already-in rows and 2 (video icon = element 1, audio icon = element 2) for others, laid out with `createCallVideoMargins` / `createCallAudioMargins`. The Dart implementation uses two `IconButton` widgets in an absolute `Stack`, but right-side margin/position is hardcoded (`right: 64` / `right: 28`) instead of reading from the style system. If the row width changes (mobile layout), the icons will overlap or go off-screen. — `calls_screen.dart:1822-1860` ← `calls_group_invite_controller.cpp:220-245`

- [ ] [MAJOR] When creating a conference call with exactly 1 selected contact, the Dart code takes the single-call path (`engine.startCall`) and the `discardedInviteMsgId` path only applies when `discardedInviteMsgId != 0`. AyuGram's `PrepareCreateCallBox` uses `selected.size() != 1 || discardedInviteMsgId` — the same logic — but the actual single call is triggered via `Core::App().calls().startOutgoingCall(invite.user, { invite.video })`. The Dart path ignores video mode for the single-call case when selected via audio button (forces `video: false` when `isVideo` is already correctly stored in `_selectedVideo`). — `calls_screen.dart:1076-1082` ← `calls_group_invite_controller.cpp:1185-1197`

- [ ] [MAJOR] Call settings "Other" section is missing the "Open system sound preferences" button (`tr::lng_settings_call_open_system_prefs()`). AyuGram's `BuildOtherSection` adds this button which calls `Platform::OpenSystemSettings(SystemSettingsType::Audio)`. The Dart `_CallSettingsScreen` does have this action at line 2586, but it is placed in a separate row widget (`_CallSettingsActionRow`) disconnected from any "Other" section header — there is no section header for it; the section jumps from "Camera" header directly to "Other" header to this button, creating a wrong visual grouping. — `calls_screen.dart:2571-2606` ← `settings_calls.cpp:411-428`

- [ ] [MAJOR] `_InputLevelMeter` spawns an audio capture subprocess (`parec`, `pw-record`, `rec`, `ffmpeg`) to measure microphone level during call settings. AyuGram uses `Webrtc::AudioInputTester` from the `webrtc` module (a proper native audio input tester with `base::Timer` at 50ms interval) which does not spawn external processes, handles device selection via the resolved `deviceId`, and integrates with the existing ADM. The subprocess approach will capture audio from the default device regardless of selected input device setting, and will not work if the system does not have `parec`/`pw-record`/`rec`/`ffmpeg` installed. — `calls_screen.dart:2938-2987` ← `settings_calls.cpp:114-153`

- [ ] [MAJOR] `_CallSettingsDeviceRow` device picker uses `AlertDialog` with `RadioListTile` rows built in a `Column` (not a `ListView`). If the device list is long, the dialog overflows. AyuGram uses `ChoosePlaybackDeviceBox` / `ChooseCaptureDeviceBox` which are scrollable `PeerListBox`-style boxes with lazy loading. — `calls_screen.dart:2624-2668` ← `settings_calls.cpp:72-113`

- [ ] [MAJOR] Active group calls section shows a subsection header ("Active Group Calls") that is **always rendered in the widget tree** (inside `AnimatedSize`) even when there are no active calls; only the content is hidden via `entries.isEmpty ? SizedBox.shrink() : Column(...)`. AyuGram toggles the entire `SlideWrap` section off with `groupCalls->hide(anim::type::instant)` / `groupCalls->toggleOn(state->groupCallsController.shownValue())`, ensuring zero layout space when hidden. The `AnimatedSize` wrapper means the section always occupies space during animation transitions. — `calls_screen.dart:549-577` ← `calls_box_controller.cpp:828-843`

- [ ] [MAJOR] `_CallGroup` grouping uses `_dateKey` (string "YYYY-M-D") and `_callTypeKey` ("out"/"in"/"missed") matching. AyuGram's `Row::canAddItem()` groups items by same peer history, same `QDate`, and same `Type` enum. The Dart implementation is correct in logic but `_dateKey` uses `dt.month` (1-12, not zero-padded) so "2024-1-5" and "2024-10-5" have different lengths but that is fine. However AyuGram also sorts items within a group by `id` descending (`ranges::sort`), while Dart preserves insertion order. The display of grouped entries will show calls in wrong order inside a group. — `calls_screen.dart:146-175` ← `calls_box_controller.cpp:273-280`

- [ ] [MAJOR] `_ClearCallHistoryBox.onConfirm` calls `engine.clearCallHistory(accountId, revoke: revoke)`. AyuGram's `ClearCallsBox` uses `MTPmessages_DeletePhoneCallHistory` which is a multi-page operation (it loops via `offset > 0` until all history pages are deleted, applying MTProto updates after each page). The Dart call is fire-and-forget: it clears the UI list locally but does not verify the multi-page deletion completed, and does not apply the resulting MTProto updates that the desktop client processes. — `calls_screen.dart:284-296` ← `calls_box_controller.cpp:735-764`

# chat_export — Audit Findings

## chat_export — Incorrect default state: `_profileMusic`, `_privateChannels`, and others differ from AyuGram defaults

- [ ] [MAJOR] Default export types mismatch: AyuGram's `DefaultTypes()` enables `PersonalInfo|Userpics|Contacts|Stories|ProfileMusic|PersonalChats|PrivateGroups`. Dart sets `_profileMusic = true` and `_privateChannels = false` matching, but `_botChats = false` whereas AyuGram also has BotChats disabled by default — that part matches. However `_sessions = false` and `_otherData = false` are correct as they are absent from `DefaultTypes()`. The mismatch is `_profileMusic = true` is correct, BUT `_privateChannels = false` and all others match too. **Actual mismatch**: AyuGram defaults DO NOT include `PersonalChats | BotChats` in `fullChats` (they are always full, see `DefaultFullChats()`). The Dart code omits the `MustBeFull`/`MustNotBeFull` constraint entirely — `PersonalChats` and `BotChats` are always exported in full in AyuGram (no "Only my messages" sub-option at all), but Dart passes `hasSubOption: false` for those without enforcing `fullChats` semantics in the export params. — `chat_export.dart:1249-1259` ← `export_settings.h:115-118` and `export_settings.cpp:30-36`

## chat_export — `forceSubPath` not sent to engine — export written to wrong directory

- [ ] [CRITICAL] AyuGram's `ResolveSettings()` sets `forceSubPath = true` when using the default download path; `export_output_abstract.cpp` uses this flag to create a timestamped subdirectory automatically. The Dart `_startExport()` never sends a `force_sub_path` field in `exportParams`. When the user leaves the default location (`Downloads/TelegramExport`), the backend will not create a per-export timestamped subdirectory, colliding with prior exports. — `chat_export.dart:775-800` ← `export_view_panel_controller.cpp:126-131` and `export_output_abstract.cpp:26-31`

## chat_export — `_ExportSuggestBox` text and title are wrong (hardcoded, mismatched)

- [ ] [MAJOR] `_ExportSuggestBox` shows title "Export Your Data" and text "You can export your data from Telegram, including chats, messages, and media. The export will be processed by Telegram servers and may take some time." AyuGram's `SuggestBox` uses `lng_export_suggest_title` = "Data export ready" and `lng_export_suggest_text` = "You can now download the data you requested. Start exporting data?" Cancel button says "Cancel" in Dart vs `lng_export_suggest_cancel` = "Not now" in AyuGram. — `chat_export.dart:3037-3088` ← `export_view_panel_controller.cpp:53-64`

## chat_export — Processing view: stop-confirmation text deviates from AyuGram

- [ ] [MAJOR] `_showStopConfirmation()` displays "Are you sure you want to stop exporting your data?" and button label "Stop". AyuGram uses `lng_export_sure_stop` = "Are you sure you want to stop exporting your data?\n\nIf you do, you'll need to start over." — the critical second sentence is missing in Dart. — `chat_export.dart:682-683` ← `export_view_panel_controller.cpp:358-361` and `lang.strings` "lng_export_sure_stop"

## chat_export — Progress view: "please wait" text deviates from AyuGram spec

- [ ] [MAJOR] Processing phase shows "Please wait, export is in progress." AyuGram uses `lng_export_progress` = "You can close this window now. Please don't quit Telegram until the data export is completed." — the Dart text is entirely different in meaning (it says wait, AyuGram says you can close the window). — `chat_export.dart:2201-2205` ← `export_view_progress.cpp:264-268` and `lang.strings` "lng_export_progress"

## chat_export — Completed view: "Show My Data" button label wrong

- [ ] [MAJOR] Completed state shows button label "Show My Data". AyuGram uses `lng_export_done` = "Show my data" (lowercase "my", lowercase "data"). Minor case difference but also: AyuGram uses `File::ShowInFolder(path)` (opens containing folder), while Dart calls `_openExportFolder()` which opens the folder directly via `xdg-open`/`open`/`explorer` — this is equivalent, not a critical issue. — `chat_export.dart:2369` ← `export_view_panel_controller.cpp:327-330` and `lang.strings` "lng_export_done"

## chat_export — Takeout invalid error text wrong

- [ ] [MAJOR] Dart shows "Sorry, your data export session has expired, please try again." AyuGram uses `lng_export_invalid` = "Sorry, you started a new data export, so this data export has been canceled." — completely different message and meaning. — `chat_export.dart:970-974` ← `export_view_panel_controller.cpp:225-228` and `lang.strings` "lng_export_invalid"

## chat_export — Delay error format deviates from AyuGram

- [ ] [MAJOR] Dart shows "Please try again in about N hours, on Month Day, Year at HH:MM." AyuGram uses `lng_export_delay` = "For security reasons, you will be able to begin downloading your data in {hours}. We have notified all your devices about the export request to make sure it's authorized and give you time to react if it's not.\n\nPlease come back on {date} and repeat the request using the same device." The Dart message is a completely different and much shorter text. — `chat_export.dart:977-991` ← `export_view_panel_controller.cpp:229-249` and `lang.strings` "lng_export_delay"

## chat_export — Size slider has 100 positions (0-99) but `_sizeLimitMB` reads 8MB at index 7, not index 7 (0-based) as documented by AyuGram

- [ ] [MAJOR] AyuGram uses `kSizeValueCount = 100` positions (indices 0..99) and `SizeLimitByIndex(index)` does `index += 1` making it 1-based. Dart uses `_sizeSliderPos = 7` (0-based, so `i = 8` after `+1`) → `_sizeLimitMB = 8` MB, which matches `AyuGram sizeLimit = 8 * 1024 * 1024`. However Dart sends `size_limit_mb` (megabytes integer) while the engine expects bytes (`sizeLimit` in AyuGram is bytes). If the Go bridge interprets `size_limit_mb` as MB it's fine, but the field name differs from AyuGram's internal `sizeLimit` bytes representation — the engine must convert. This is an integration risk not visible in the UI alone. — `chat_export.dart:414-424` and `793` ← `export_view_settings.h:28` and `export_view_settings.cpp:89-113`

## chat_export — Section header "Chats" shows "Chat export settings" in AyuGram

- [ ] [MAJOR] `_buildSectionHeader('Chats', ...)` renders "Chats". AyuGram uses `lng_export_header_chats` = "Chat export settings". The Dart value is shortened and differs from spec. — `chat_export.dart:1248` ← `export_view_settings.cpp:191` and `lang.strings` "lng_export_header_chats"

## chat_export — Section header "Media" should be "Media export settings"

- [ ] [MAJOR] `_buildSectionHeader('Media', ...)` renders "Media". AyuGram uses `lng_export_header_media` = "Media export settings". — `chat_export.dart:1539` ← `export_view_settings.cpp:229` and `lang.strings` "lng_export_header_media"

## chat_export — Section header "Output format" should be "Location and format"

- [ ] [MAJOR] `_buildSectionHeader('Output format', ...)` renders "Output format". AyuGram uses `lng_export_header_format` = "Location and format". — `chat_export.dart:1340` ← `export_view_settings.cpp:290` and `lang.strings` "lng_export_header_format"

## chat_export — Location label text differs: shows "Location: path" instead of "Download path: {path}"

- [ ] [MAJOR] `_buildLocationLabel` shows "Location: " prefix. AyuGram uses `lng_export_option_location` = "Download path: {path}". — `chat_export.dart:1622` ← `export_view_settings.cpp:316-322` and `lang.strings` "lng_export_option_location"

## chat_export — Size limit label shows only "N MB" without context text

- [ ] [MAJOR] Media section shows only `'$_sizeLimitMB MB'` as a label. AyuGram uses `lng_export_option_size_limit` = "Size limit: {size}", positioning it above-right the slider. The Dart label lacks the "Size limit:" prefix. — `chat_export.dart:1561` ← `export_view_settings.cpp:853-858` and `lang.strings` "lng_export_option_size_limit"

## chat_export — "Skip file" label differs from spec

- [ ] [MAJOR] Processing view shows link "Skip file". AyuGram uses `lng_export_skip_file` = "Skip this file". — `chat_export.dart:2183` ← `export_view_progress.cpp:259` and `lang.strings` "lng_export_skip_file"

## chat_export — `_ExportPanelController` lacks proper `hideOnDeactivate` — panel stays open when app deactivates during export

- [ ] [MAJOR] AyuGram sets `_panel->setHideOnDeactivate(true)` during processing and `setHideOnDeactivate(false)` on error. Dart's `_FloatingExportPanel` uses `AppLifecycleState.inactive` check but only for `_hideOnDeactivate` (which is `true` only during processing), and calls `Navigator.of(context).pop()` — but the export panel is in an `OverlayEntry`, not a Navigator route, so `Navigator.pop()` is a no-op. The deactivate behavior is broken. — `chat_export.dart:625-629` ← `export_view_panel_controller.cpp:278`, `299`, `335`

## chat_export — `_ExportPanelController.showAndActivate` does not re-bring panel to front visually

- [ ] [MAJOR] `showAndActivate()` calls `_entry!.markNeedsBuild()` which only triggers a rebuild of the overlay entry, but does NOT reorder it to be on top of other overlay entries. AyuGram's `activatePanel()` calls `_panel->showAndActivate()` which brings the window to the foreground. In Dart the overlay entry retains its insertion order — if other overlays were inserted after it, the export panel remains behind them. — `chat_export.dart:187-192` ← `export_view_panel_controller.cpp:163-167`

## chat_export — Processing view: animated fade-out of old step rows not implemented

- [ ] [MAJOR] AyuGram's `ProgressWidget::Row` has animated fade in/out of label instances when a step's ID changes (`toggleInstance` with opacity animation, `_old` vector of fading instances). Dart replaces step labels in-place using `AnimatedSwitcher` only for the label text, without fading out the progress bar of old step rows. The visual transition when steps complete is incorrect. — `chat_export.dart:2110-2162` ← `export_view_progress.cpp:73-182`

## chat_export — `_buildCompletedPlaceholder` copies _exportSteps but does not reflect actual completed step data from engine

- [ ] [MAJOR] The completed view creates `completedSteps` by mapping existing `_exportSteps` and substituting `info: 'Done'` for empty info fields. However `_exportSteps` is populated by `_buildExportStepList()` at start time and may not reflect what the engine actually completed (e.g. if the engine added steps dynamically via `_onExportProgress`). Steps that were never updated will show placeholder "Done" labels with no real info. — `chat_export.dart:2266-2271` ← `export_view_progress.cpp:310-353`

## chat_export — Completed view missing total file count display

- [ ] [MAJOR] AyuGram's completed state shows `lng_export_total_amount` = "Total files: {amount}" (in the done state via `showDone()`). Dart's completed view does not display total file count anywhere despite `_totalFiles` and `_totalSizeBytes` being tracked. — `chat_export.dart:2257-2375` ← `lang.strings` "lng_export_total_amount"

## chat_export — `_ExportSuggestBox` button dismisses without starting export when `onStart` is null

- [ ] [CRITICAL] `_ExportSuggestBox.onStart` can be null. The "OK" button calls `onStart?.call()` — if the caller didn't pass `onStart`, clicking OK dismisses the dialog but does nothing, silently failing to trigger the export. This is a stub behavior. AyuGram's `SuggestBox` always calls `Core::App().exportManager().start(...)` on OK. — `chat_export.dart:3067-3072` ← `export_view_panel_controller.cpp:57-61`

# chat_list_panel — Audit Findings

- [ ] [CRITICAL] `_forwardHoverTimer` declared and doc-commented as "Auto-select timer: opens the hovered chat after 2s hover (kFreezeTimeout)" but is never started anywhere in the file. The `DragTarget.onMove` callback (line 905) only cancels and resets the timer, never calls `Timer(const Duration(seconds: 2), ...)`. The auto-open-chat-after-2s hover feature during forward-drag is completely absent. — `chat_list_panel.dart:177` ← `dialogs/dialogs_inner_widget.cpp:3952` (`_freezeTimer.callOnce(kFreezeTimeout)` where `kFreezeTimeout = 2000ms`)

- [ ] [CRITICAL] `SearchResult.timestamp` is returned by the Go engine as Unix seconds (`m.Timestamp.Unix()`) but `_SearchMessageRow` passes it to `DateTime.fromMillisecondsSinceEpoch(result.timestamp)` which expects milliseconds. All search result dates display as near-epoch (year 1970 / early 1970s). Additionally `chatState.jumpToMessage(result.timestamp, ...)` passes the seconds value to a function that expects milliseconds, jumping to the wrong message position. Fix: multiply by 1000 at both sites. — `chat_list_panel.dart:4400` and `chat_list_panel.dart:791` ← `go/engine/search.go:240` (`Timestamp: m.Timestamp.Unix()`)

- [ ] [MAJOR] `_SearchTab.thisTopic` case (line 515) filters chat results by `chatId` only — identical to `thisPeer` — and the `topicId` variable read at line 518 is never passed to any search call. The message search at line 484–488 calls `chatState.searchMessages(query, accountId: ...)` without a `topicId` argument for the `thisTopic` tab, so "This Topic" search returns the same results as "This Peer" rather than scoping to the active forum topic. — `chat_list_panel.dart:515-524` and `chat_list_panel.dart:484-488` ← `dialogs/dialogs_inner_widget.cpp:2128` (topic-scoped search using `topicId`)

## chat_list_row — Swipe direction inverted, badge icon colors wrong, ripple wrong

- [ ] [CRITICAL] Swipe direction is inverted: Dart slides row RIGHT (positive `_swipeOffset`) revealing action on the LEFT, but AyuGram swipes LEFT (`data.translation < 0`) revealing action on the RIGHT edge of the row. The `clamp(0.0, _maxSwipeOffset)` at line 752 prevents left-swipe entirely. Dart never activates for left-drag. — `chat_list_row.dart:749-753` ← `dialogs/ui/dialogs_layout.cpp:447-453` + `dialogs/dialogs_widget.cpp:804`

- [ ] [CRITICAL] Mention/reaction/poll badge icons use `badgeBg` (unread badge background) as the icon color in wide mode. AyuGram uses distinct theme colors: mention → `dialogsMentionIconFg` (#40a7e3), reaction → `dialogsReactionIconFg` (#e05356), poll → `dialogsPollIconFg` (#997be1). The palette already declares these three fields but they are not used. — `chat_list_row.dart:288,297,305` ← `dialogs/dialogs.style:580-608` + `lib_ui/ui/colors.palette:690-692`

- [ ] [MAJOR] Swipe action ripple on threshold-crossing is wrong. AyuGram draws an ellipse that expands based on `swipeTranslation * reachRatio` using `ResolveQuickActionBgActive` color, positioned near the top-right of the action area (`geometry.width() - offset, offset`). Dart draws a white semi-transparent (`rgba(255,255,255,0.20)`) circle centered in the 80px SizedBox on the LEFT side of the row. Wrong color, wrong position, wrong growth logic. — `chat_list_row.dart:916-941` ← `dialogs/ui/dialogs_layout.cpp:979-986`

- [ ] [MAJOR] Forum jump bubble padding is 5px left/right (area1) and 4/5px (area2), but AyuGram spec uses `forumDialogJumpPadding: margins(8px, 3px, 8px, 3px)` — 8px left/right for both areas. Dart is 3px short on each horizontal side. — `chat_list_row.dart:2377,2411` ← `dialogs/dialogs.style:142`

- [ ] [MAJOR] `debugPrint('[SWIPE] dragUpdate ...')` at line 745 is left in production code, printing on every drag-update frame — performance and log-noise issue. — `chat_list_row.dart:745`

# chat_settings_screen — Audit Findings

## chat_settings_screen — Critical & Major Issues

- [ ] [MAJOR] Accent color circle size is 22px (`_circleSize = 22.0`) but AyuGram spec is 24px (`st::settingsAccentColorSize: 24px`). This is a >8% deviation from the style spec, causing the entire accent palette row to render smaller than intended — `chat_settings_screen.dart:925` ← `AyuGram/settings/settings.style:313`

- [ ] [MAJOR] Sensitive content age-verification flow is wrong: Dart shows a plain `AlertDialog` with hardcoded "I am over 18" text (`chat_settings_screen.dart:584–606`). AyuGram's real flow calls `session->appConfig().ageVerifyNeeded()` and, if true, redirects to `ShowAgeVerificationRequired()` which opens a bot WebApp for proper country/age-based verification rather than a static dialog. The Dart implementation always uses the same dialog regardless of appConfig state — `chat_settings_screen.dart:579–607` ← `AyuGram/settings/sections/settings_privacy_security.cpp:294–303`

- [ ] [MAJOR] Cloud theme "Edit" button is shown only when `t.isCreator && isActive` (`chat_settings_screen.dart:436–439`). AyuGram additionally requires `cloud.documentId` is non-zero — a theme created without a document (draft theme) should not have an edit button in the list. The missing `documentId` check means the Edit option appears for themes that cannot actually be opened in the editor — `chat_settings_screen.dart:436–438` ← `AyuGram/window/themes/window_themes_cloud_list.cpp:630–635`

- [ ] [MAJOR] Cloud theme deletion does not reset the active theme before deleting: AyuGram's `remove` closure first checks whether the deleted theme is currently applied and if so calls `ResetToSomeDefault()` + `KeepApplied()` before removing (`window_themes_cloud_list.cpp:640–653`). The Dart implementation calls `engine.deleteCloudTheme()` directly with no reset logic, leaving the UI in a broken state if the user deletes the currently-active theme — `chat_settings_screen.dart:2314–2316` ← `AyuGram/window/themes/window_themes_cloud_list.cpp:638–660`

- [ ] [MAJOR] The "Show All" toggle for cloud themes in Dart hides after 4 themes (`if (themes.length > 4)`), shows a scrollable row when collapsed (`chat_settings_screen.dart:2101`, `2124`), and uses a two-way toggle between collapsed/expanded. AyuGram's `CloudList` instead shows ALL themes in a wrapping grid by default and only exposes a one-way "Show All" link-button that appears when `list->allShown()` is false — i.e., the list is always displayed, "Show All" expands more results, but there is no "collapse" action. Dart's behavior (hiding all but 4 and toggling) deviates significantly from the C++ UX — `chat_settings_screen.dart:2101–2131` ← `AyuGram/settings/sections/settings_chat.cpp:2757–2763`

- [ ] [MAJOR] The background thumbnail widget is 76×76px in Dart (`chat_settings_screen.dart:2532`). AyuGram's `st::settingsBackgroundThumb` is also 76px but the C++ `BackgroundRow::resizeGetHeight()` returns `st::settingsBackgroundThumb` as the total widget HEIGHT (it also paints a separate loading radial on the same 76×76 rect). The Dart thumbnail has correct dimensions BUT uses a static `CircularProgressIndicator` progress animation (`_loadingController.value`) instead of AyuGram's radial animation that reflects actual download progress (`radialProgress()` from the session). The loading state is cosmetically stuck showing animated indeterminate progress rather than real download progress — `chat_settings_screen.dart:2562–2582` ← `AyuGram/settings/sections/settings_chat.cpp:495–542`

- [ ] [MAJOR] The `_ChooseFontBox` offers a hardcoded list of 5 font families (`Inter`, `Roboto`, `Open Sans`, `Noto Sans`, `System Default`). AyuGram's `ChooseFontBox` (`ui/boxes/choose_font_box.cpp`) scans system fonts and lists all installed fonts. The Dart implementation ignores the system font catalogue — users cannot select fonts that are installed on their system but not in the hardcoded list — `chat_settings_screen.dart:1862–1868` ← `AyuGram/settings/sections/settings_chat.cpp:2873–2900`

- [ ] [MAJOR] Sticker pack reorder via drag-and-drop (`_reorder` at `chat_settings_screen.dart:3612`) only reorders items in the local `_packs` list in memory but never persists the new order to the backend. AyuGram calls `session->data().stickers().reorder()` and then saves the new order via the API (`messages.reorderStickerSets`). The Dart reorder function has no engine call — `chat_settings_screen.dart:3612–3618` — no corresponding backend call exists anywhere in that method.

- [ ] [MAJOR] The `_ThemePreviewPainter` chat bubble radius is `const Radius.circular(2)` which matches `st::settingsThemeBubbleRadius: 2px`. However, the `_CloudThemePreviewPainter` also uses `const Radius.circular(2)` for its bubble previews (`chat_settings_screen.dart:3292`, `3301`, `3307`). These cloud theme cards render differently from the built-in theme previews in AyuGram which uses `chatThemeBubbleRadius: 10px` for cloud theme bubbles vs `settingsThemeBubbleRadius: 2px` for built-in theme cards. The Dart code uses the wrong radius (2px instead of 10px) for cloud theme bubble previews — `chat_settings_screen.dart:3292` ← `AyuGram/settings/settings.style:281,293`

- [ ] [MAJOR] The reaction chooser (`_ReactionChooserButton`) displays reaction emoji strings as both the emoji icon AND the label text on each row (line 4261: `Text(emoji, ...)` in the label column), making every row show `❤️  ❤️`. AyuGram's `ReactionsSettingsBox` uses the proper localised reaction name (e.g. "Heart", "Thumbs Up") as the label, not the emoji code again. This produces broken display for all quick-reaction choices — `chat_settings_screen.dart:4259–4262`.

# chat_switch_overlay — Chat Switch Overlay Audit

- [ ] [CRITICAL] Topic cell userpic layout is reversed: Dart shows forum avatar (56 px) as the main element with topic-color badge (24 px) at bottom-right. AyuGram shows `TopicIconButton` (the actual topic icon, 56 px) as the primary element and the **forum peer's** userpic as the small (24 px) overlay positioned at the bottom-right — `chat_switch_overlay.dart:508-533` ← `AyuGram/window/window_chat_switch_process.cpp:99-140`

- [ ] [CRITICAL] Topic color is computed from `topicId % 6` using a local color table. AyuGram derives the color from `ForumTopic::colorId()` which is the server-assigned `int32 _colorId` field (user-set per topic). The hash approach gives wrong colors for any topic whose assigned colorId doesn't match its raw ID modulo 6 — `chat_switch_overlay.dart:39-42` ← `AyuGram/data/data_forum_topic.cpp:829-830`

- [ ] [CRITICAL] After pressing Q to remove the selected chat, `_selected` is set to `-1` and never restored. AyuGram immediately calls `setSelected(std::min(selected - 1, _shownCount - 1))` so a new item is highlighted and the next Ctrl-release confirms it. In Dart the overlay stays visible with no selection, and releasing Ctrl triggers `onCancel()` instead of switching — `chat_switch_overlay.dart:222` ← `AyuGram/window/window_chat_switch_process.cpp:387-393`

- [ ] [MAJOR] `_shownPerRow` and `_shownRows` are updated through `addPostFrameCallback` (deferred to the next frame). The `_shownCount` getter reads them immediately, so during keyboard navigation that happens in the same frame as a resize, `_shownCount` returns stale values causing wrong modular wrap-around. AyuGram recomputes everything synchronously inside `layout()` which runs directly from the size-change signal — `chat_switch_overlay.dart:210,289-298` ← `AyuGram/window/window_chat_switch_process.cpp:420-490`

# chat_view — Audit chunk 48

## chat_view — Missing bars, voice listen state, group call defects

- [ ] [CRITICAL] `_stopAndSendRecording()` immediately sends the recording with zero preview: no "listen before send" (ListenWrap) state — after the user locks recording and taps Stop, AyuGram presents a waveform preview with play/pause, trim handles, and a delete button before any message is sent; Dart skips this entirely and fires `engine.sendVoice` / `engine.sendVideoNote` inline — `chat_view.dart:13266` ← `AyuGram/Telegram/SourceFiles/history/view/controls/history_view_voice_record_bar.cpp:669`

- [ ] [CRITICAL] `TranslateBar` is completely absent — AyuGram constructs a `TranslateBar` in `ChatWidget`'s initialiser (line 279) and `setupTranslateBar()` (line 1977) that automatically surfaces above the compose area when the chat's language differs from the user's locale; no equivalent widget or logic exists anywhere in chat_view.dart — `chat_view.dart` (no implementation) ← `AyuGram/Telegram/SourceFiles/history/view/history_view_chat_section.cpp:279`

- [ ] [CRITICAL] `_ContactStatusBar` handles only three states (isBlocked → Unblock, isBot → label, non-contact → Add/Block); AyuGram's `ContactStatus` has nine states, five of which are completely unimplemented: `UnarchiveOrBlock`, `UnarchiveOrReport`, `SharePhoneNumber`, `RequestChatInfo`, and `SetBotPhoto` — `chat_view.dart:9345` ← `AyuGram/Telegram/SourceFiles/history/view/history_view_contact_status.cpp:348`

- [ ] [MAJOR] `_GroupCallBar` builds the userpic row with `participants.take(3)` — no sort — so the first three participants in the data list appear, regardless of who is currently speaking; AyuGram sorts by `speaking DESC, max(lastActive, date) DESC` so the most-active speakers always appear leftmost — `chat_view.dart:10527` ← `AyuGram/Telegram/SourceFiles/history/view/history_view_group_call_bar.cpp:122`

- [ ] [MAJOR] `_GroupCallUserpic` renders a static green border ring for speaking participants; AyuGram's `GroupCallUserpics` drives per-userpic `BlobsAnimation` with an animated `_speakingAnimation` that pulses outward blobs in sync with audio level — `chat_view.dart:10550` ← `AyuGram/Telegram/SourceFiles/ui/chat/group_call_userpics.h:48`

- [ ] [MAJOR] `_GroupCallBar` height hardcoded at 52 px; AyuGram uses `st::historyReplyHeight = 49px` for all reply-style bars including the group call bar — `chat_view.dart:10530` ← `AyuGram/Telegram/SourceFiles/chat_helpers/chat_helpers.style:1067`

- [ ] [MAJOR] `TopicReopenBar` is absent — for forum topics where `isClosed == true` but the user has `canToggleClosed == true` (i.e. admin), AyuGram shows a prominently animated reopen bar via `_topicReopenBar` above the message list; Dart shows only the compose area with no indication the topic is closed and no reopen affordance — `chat_view.dart:5310` ← `AyuGram/Telegram/SourceFiles/history/view/history_view_chat_section.cpp:634`

- [ ] [MAJOR] Admin join-requests bar (`RequestsBar`) is absent — AyuGram creates a `_requestsBar` (type `Ui::RequestsBar`) in `HistoryWidget` that surfaces a "N new member requests" banner above the compose area for admins with pending approval requests; Dart has no equivalent — `chat_view.dart` (no implementation) ← `AyuGram/Telegram/SourceFiles/history/history_widget.h:774`

## choose_datetime_box — schedule/calendar/time-picker dialog suite

- [ ] [MAJOR] Non-premium repeat click shows a custom `TelegramBox` dialog instead of a toast notification — C++ calls `Settings::ShowPremiumPromoToast(...)` which displays a dismissable toast with a clickable "Premium" link; Dart pops up a full box with a hardcoded text block — `choose_datetime_box.dart:1173` ← `history_view_schedule_box.cpp:129-143`

- [ ] [MAJOR] Title text wrong for self-chat: Dart shows `'Set a reminder'` but AyuGram's `lng_remind_title = "Remind me on..."` — `choose_datetime_box.dart:1215` ← `history_view_schedule_box.cpp:118-120` + `lang.strings:4644`

- [ ] [MAJOR] Title text wrong for scheduling: Dart shows `'Schedule message'` but AyuGram's `lng_schedule_title = "Send this message on..."` — `choose_datetime_box.dart:1215` ← `history_view_schedule_box.cpp:118-120` + `lang.strings:4643`

- [ ] [MAJOR] "Send when online" button uses wrong widget type: Dart places an `IconButton(Icons.more_vert)` inside `titleTrailing`; C++ calls `box->addTopButton(infoTopBarMenu)` which places a three-dot icon button flush against the right edge of the box title bar (a proper top-button slot), not in a trailing row widget — `choose_datetime_box.dart:1216-1239` ← `history_view_schedule_box.cpp:189-195` + `box_layer_widget.cpp:264-267`

- [ ] [MAJOR] Time input field missing scroll-wheel increment/decrement: C++ `TimePart` widget supports mouse-wheel to increment/decrement hour (step 1) and minute (step 10); Dart `_TimeInputField` has no `Listener(onPointerSignal:...)` on the hour/minute text fields — `choose_datetime_box.dart:1685-1735` ← `time_part_input.cpp:74-87` (wheelEvent, `_wheelStep`)

- [ ] [MAJOR] Time input field missing Left-arrow key navigation from minute back to hour: C++ `TimePart` fires `_jumpToPrevious` on Left-arrow at cursor position 0, causing `TimeInput` to move cursor to end of hour field and focus it; Dart has no such KeyEvent handler in `_TimeInputField` — `choose_datetime_box.dart:1714-1733` ← `time_input.cpp:110-113` + `time_part_input.cpp:61-64`

- [ ] [MAJOR] Time input field missing Backspace-erase backward navigation: C++ `TimePart` fires `_erasePrevious` on Backspace when the field is empty and cursor is at position 0, causing the previous field (hour) to erase its last character and gain focus; Dart minute field has no such handler — `choose_datetime_box.dart:1714-1733` ← `time_input.cpp:107-109` + `time_part_input.cpp:56-59`

- [ ] [MAJOR] Time error shown as horizontal shake animation rather than animated red border: C++ `TimeInput::showError()` transitions the bottom border color from `borderFgActive` to `borderFgError` via `_a_error` animation (no movement); Dart translates the entire time widget with a TweenSequence shake — `choose_datetime_box.dart:1024-1037` ← `time_input.cpp:320-342`

- [ ] [MAJOR] Calendar highlighted day (selected/current) uses wrong color: C++ paints the highlighted circle with `st::dialogsBgActive` (`#419fd9`) for the normal case, and `st::windowBgOver` for grayed-out; Dart uses `context.palette.windowBgActive` (`#40a7e3`) for the selected circle — this is the accent color not the dialogs active bg, diverging for custom themes — `choose_datetime_box.dart:891-892` ← `calendar_box.cpp:871`

- [ ] [MAJOR] Calendar missing range-selection mode: C++ `CalendarBox` supports `allowsSelection`, `toggleSelectionMode`, `startSelection`, `updateSelection` for multi-day range picking (with Shift+click / two-press selection), a "Select days" left button, and a floating date label overlay; Dart has no selection mode at all — `choose_datetime_box.dart:84-463` ← `calendar_box.cpp:459-521`, `1294-1376`

- [ ] [MAJOR] Calendar missing dynamic image support per day: C++ `CalendarBox` accepts a `dynamicImageForDate` callback that overlays a circular avatar image on individual calendar cells with fade-in animation; Dart has no `_dynamicImageForDate` equivalent — `choose_datetime_box.dart:84-463` ← `calendar_box.cpp:720-869`

- [ ] [MAJOR] Calendar title shows wrong arrow indicator: C++ `CalendarBox::Title::paintEvent` draws a small right-pointing triangle before the month/year text (not a dropdown arrow icon); Dart renders `Icons.arrow_drop_down` — `choose_datetime_box.dart:299` ← `calendar_box.cpp:1147-1159`

- [ ] [MAJOR] MonthYearPicker "Jump to date" title not from spec: C++ uses `FillMonthYearPicker` (no explicit dialog title; it is a naked `GenericBox`); Dart shows `title: 'Jump to date'` — `choose_datetime_box.dart:642` ← `calendar_box.cpp:43-188`

- [ ] [MAJOR] MonthYearPicker drum picker height wrong: C++ uses `st::settingsWorkingHoursPicker = 200px` (5 × 40px items); Dart hard-codes `_drumHeight = _itemHeight * 5 = 200` but the C++ month drum adjusts its item count based on min/max year boundaries per selected year — Dart's month drum shows all 12 months unconditionally instead of only the valid months for the selected year at edges — `choose_datetime_box.dart:654-678` ← `calendar_box.cpp:85-153`

- [ ] [MAJOR] Repeat period map uses hardcoded English strings instead of localized keys: C++ uses `tr::lng_schedule_repeat_never`, `tr::lng_schedule_repeat_daily` etc. (localization-aware); Dart has `const Map<int, String>` with literal English — `choose_datetime_box.dart:53-62` ← `choose_date_time.cpp:254-268`

- [ ] [MAJOR] Default schedule time offset wrong: C++ `DefaultScheduleTime()` defaults to `now + 600` seconds (10 minutes); Dart uses `DateTime.now().add(const Duration(minutes: 10))` which is the same numeric value but always set in the Dart layer — however, C++ passes `time` as an arg and the caller provides `DefaultScheduleTime()`. Dart ignores any passed `initialDate` for min-time enforcement since it re-computes from `DateTime.now()` on every validation call — not a bug per se, but the default initial display time in the Dart widget is `+10 min` while C++ defaults to `+10 min` (`600s`). This matches. No issue here.

- [ ] [MAJOR] Time input field max date uses `+365 days` instead of `addYears(1)`: C++ uses `QDateTime::currentDateTime().addYears(1)` (next calendar year, accounts for leap years); Dart uses `today.add(const Duration(days: 365))` — off by one day in leap years — `choose_datetime_box.dart:1113` ← `choose_date_time.cpp:114-115`

- [ ] [MAJOR] Calendar missing scroll-based month navigation (scroll area): C++ `CalendarBox` wraps `Inner` in a `ScrollArea` and scrolls between months by dragging/scrolling — the month changes as the user scrolls past month boundaries; Dart only supports wheel-scroll on the header area to jump months — `choose_datetime_box.dart:238-244` ← `calendar_box.cpp:1234-1429`

# engine_service — Bridge/engine service layer audit

## Scope
`dart/lib/bridge/engine_service.dart` (~5,800 lines). Pure service layer — all methods call through to the Go FFI engine via `_callRaw` (sync) or `_callAsync` (background isolate). No UI code. Compared against AyuGram `data_group_call.h`, `data_changes.h`, and general Telegram data model patterns.

---

- [ ] [MAJOR] `getMessages` uses synchronous `_callRaw` (blocks UI thread): loads up to 50 messages including proto decode + per-message `jsonDecode(contentRaw)` in `_cachedMsgFromProto`. On a slow device with rich messages this easily exceeds 16 ms/frame. Should use `_callAsync` — `engine_service.dart:2432` ← AyuGram `data/data_histories.h` (all history requests are async)

- [ ] [MAJOR] `searchMessages` uses synchronous `_callRaw` (blocks UI thread): full-text search across cached messages is unbounded and could be slow — `engine_service.dart:4455` ← AyuGram `data/data_search_controller.h` (search is async/deferred with `DelayedSearchController`)

- [ ] [MAJOR] `_cachedMsgFromProto` never populates `forwardFromId` — the converter at line 5563 reads `p.forwardFrom` (display name) but no `p.forwardFromId` or `extra['forward_from_id']` extraction. Meanwhile `getDeletedMessages` JSON path (line 2526) correctly sets `forwardFromId: map['forward_from_id']`. Every message loaded via the normal proto path (getMessages / fetchLiveMessages / getScheduledMessages / getPinnedMessages) has `forwardFromId == ''`, breaking "Forwarded from" click-to-open-chat navigation — `engine_service.dart:5580` ← `engine_service.dart:2526`

- [ ] [MAJOR] `GroupCallParticipant` constructed at `getGroupCall` (line 1946) only populates 6 fields: `userId`, `displayName`, `isMuted`, `isSpeaking`, `hasVideo`, `avatarPath`. Missing from AyuGram's participant struct: `volume` (per-participant audio volume), `mutedByMe` (admin-muted vs self-muted — these need different icons/behaviour), `canSelfUnmute`, `sounding`, `additionalSpeaking`. Without `mutedByMe` the call participant list cannot distinguish admin-muted from self-muted state — `engine_service.dart:1946` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_group_call.h` (muted/mutedByMe/canSelfUnmute/volume fields)

- [ ] [MAJOR] `_dispatchEngineEvent` switch has no `default` case (line 5336): unknown event types are silently dropped. Any future engine event additions (story_updated, forum_topic_updated, scheduled_sent, call_signal_bars, etc.) will be black-holed without error — `engine_service.dart:5336` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_changes.h` (`Changes::storyUpdated`, `topicUpdated`, etc.)

- [ ] [MAJOR] `getStickerFiles` (line 1787) and `getGifFiles` (line 1807) both reuse `EngineGetCustomEmojiFilesRequest` / `EngineGetCustomEmojiFilesResponse` proto types for completely different content types. If the custom-emoji proto ever gains new fields the sticker/GIF paths will silently forward garbage fields. Should have dedicated proto messages — `engine_service.dart:1787` ← `engine_service.dart:1360` (custom emoji uses same request type legitimately)

- [ ] [MAJOR] `getGroupCall` event-path (`group_call_state`) uses `GroupCallInfo.fromJson` (line 5450) while the poll-path uses the inline proto converter (line 1941). These two code paths produce `GroupCallParticipant` objects from different sources — the JSON path may include fields (e.g. `mutedByMe`) that the proto converter drops, creating inconsistent state depending on how the call info was fetched — `engine_service.dart:5448` ← `engine_service.dart:1941`

- [ ] [MAJOR] `getSharedMedia` uses synchronous `_callRaw` (line 4519) and `searchChats` uses synchronous `_callRaw` (line 4465). Shared media scan and chat search both query SQLite over potentially large datasets on the UI thread — `engine_service.dart:4519` ← AyuGram `data/data_shared_media.h` (all shared media queries are async)

- [ ] [MAJOR] `_callAsync` return type is non-nullable `Future<Uint8List>` (line 5269), but 10+ call-sites check `if (respBytes == null || respBytes.isEmpty)` (e.g. lines 460, 477, 598, 1984). The null branch is dead code — if `_callAsync` ever changes signature to `Future<Uint8List?>` these sites would crash instead of handling it; if it never becomes nullable the dead branch masks the intent. The real guard should be only `respBytes.isEmpty` — `engine_service.dart:460` ← `engine_service.dart:5269`

# color_picker_box — Color picker dialog vs AyuGram ColorEditor

- [ ] [MAJOR] No custom circular cursor on gradient picker square — AyuGram generates a 16px circle cursor (black ring with white outline) and sets it via `setCursor(generateCursor())` in the `Picker` constructor; the Dart `_GradientSquare` sets no `mouseCursor` at all — `color_picker_box.dart:785` ← `AyuGramDesktop/Telegram/SourceFiles/ui/widgets/color_editor.cpp:69-99`

- [ ] [MAJOR] Shared `_wheelAccum` across all numeric fields — `_wheelAccum` is a single instance variable (int) that all seven numeric fields share via the `Listener.onPointerSignal`; AyuGram gives each `Field` its own `_wheelDelta` member so scrolling one field cannot bleed into another — `color_picker_box.dart:78,585` ← `AyuGramDesktop/Telegram/SourceFiles/ui/widgets/color_editor.cpp:646,732`

- [ ] [MAJOR] 2 px gap inserted between new/current color swatches — `const SizedBox(height: 2)` separates the two color samples; AyuGram places `_currentRect = _newRect.translated(0, st::colorSampleSize.height())` with zero separation — `color_picker_box.dart:537` ← `AyuGramDesktop/Telegram/SourceFiles/ui/widgets/color_editor.cpp:1061`

- [ ] [MAJOR] Hex (result) field spans full inner box width instead of being aligned to the field column — Dart places the `_hexField` in the outer `Column` as an `Expanded` row, making it fill the entire `innerWidth` (~354 px); AyuGram sizes it to `fieldWidth + resultDelta = 60 + 29 = 89 px` and aligns it with the left edge of the opacity slider — `color_picker_box.dart:457-461,641-681` ← `AyuGramDesktop/Telegram/SourceFiles/ui/widgets/color_editor.cpp:1083-1093`

- [ ] [MAJOR] Slider arrow color sourced from `windowActiveTextFg` instead of `sliderBgActive` — both the hue slider and opacity slider receive `arrowColor: accentFg` where `accentFg = p.windowActiveTextFg`; AyuGram uses `sliderBgActive` for all four directional arrow icons — `color_picker_box.dart:418,437` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/boxes.style:515-518`

- [ ] [MAJOR] `lightnessMin`/`lightnessMax` clamped in HSV brightness space instead of HSL lightness — Dart applies limits to `_brightness` (the V component of HSV) via `_clampedBrightness`; AyuGram's `setLightnessLimits` operates on HSL lightness (0-255) via `QColor::fromHsl`, producing different output for any saturated colour — `color_picker_box.dart:205-210` ← `AyuGramDesktop/Telegram/SourceFiles/ui/widgets/color_editor.cpp:568-607,885-896`

# compose_entities — Text Composition & Entity Management

## Summary
**Status**: Functional with minor gaps vs. AyuGram reference  
**Core Logic**: Implemented correctly for single-edit scenarios, entity offset tracking, markdown-to-entity conversion  
**Comparison**: AyuGram C++ (input_field.cpp) vs. Dart implementation (compose_entities.dart)

---

## Findings

- [ ] [MAJOR] Missing bounds validation for custom emoji substring extraction — `compose_entities.dart:354` ← AyuGram doesn't have this issue because emoji handling is in the input field wrapper
  - **Issue**: Line 352 checks `ce.offset >= src.length` but doesn't validate `ce.offset + ce.length <= src.length`. If an emoji entity extends beyond text bounds (possible after text deletion), `src.substring(ce.offset + ce.length)` will throw RangeError.
  - **Impact**: Crash when getTextWithAppliedMarkdown() is called after certain text edit sequences.
  - **Fix**: Add check: `if (ce.offset < 0 || ce.offset >= src.length || ce.offset + ce.length > src.length) continue;`

- [ ] [MAJOR] No protection against applying markdown formatting inside URL entities — `compose_entities.dart:377-409` ← AyuGram explicitly checks for links (input_field.cpp:3784-3832)
  - **Issue**: The markdown delimiter detection loop doesn't check if markdown delimiters are inside existing URL entities. A URL like `http://test.com/__test__/test` would have markdown applied inside it, converting `__test__` to italic formatting within the URL.
  - **Impact**: Markdown formatting applied inside URLs can break link functionality or create conflicting entity types.
  - **Reference**: AyuGram's getTextWithAppliedMarkdown() calls `TextUtilities::ParseEntities(originalText, 0).entities` and explicitly skips markdown tags that intersect with detected links (lines 3824-3832).
  - **Fix**: Before line 377, parse existing text for URL entities and exclude markdown matches that overlap with detected URLs.

- [ ] [MINOR] Text change detection finds only common prefix, not suffix — `compose_entities.dart:71-76`
  - **Issue**: `_onTextChanged()` uses common prefix matching to find the change position. For edits at the text end or middle, this finds the first difference but doesn't use common suffix matching for efficiency.
  - **Example**: Old: `"hello world test"`, New: `"hello there test"` — finds change at position 6 and scans the entire remainder even though suffix `"test"` is identical.
  - **Impact**: Slightly inefficient for large text edits, but correctness is preserved because delta tracking accounts for all changes.
  - **AyuGram equivalent**: Doesn't have an equivalent issue because it tracks input through QTextEdit's document model rather than raw text comparison.
  - **Note**: This is acceptable for real-time character-by-character editing (typical use case).

---

## Verified Correct Behavior

✓ **Entity offset adjustment during insertions/deletions** (lines 80-115): Correctly handles entity shifting and trimming when text is inserted or deleted.  
✓ **Custom emoji replacement with alt text** (lines 307-332, 349-363): Properly tracks offset changes and updates affected entities.  
✓ **Markdown delimiter parsing** (lines 365-409): Correctly handles nested/overlapping markdown, respects isBlock flag for code blocks, rejects inline code with newlines.  
✓ **Entity offset mapping after markdown stripping** (lines 415-443): Offset map calculation is correct; adjustments preserve entity boundaries.  
✓ **Text span building with proper styling** (lines 474-580): Style merging for overlapping formats, custom emoji rendering, and proper handling of spoiler/code backgrounds match Flutter conventions.  
✓ **JSON serialization to Telegram API format** (lines 21-40): FormatType enum correctly maps to Telegram entity type strings (bold, italic, text_url, custom_emoji, etc.).

---

## Comparison to AyuGram Desktop

| Aspect | Dart (`compose_entities.dart`) | AyuGram C++ (`input_field.cpp`) |
|--------|------|-------|
| Entity structure | Flat list with offset/length + type | QVector<TextWithTags::Tag> with string IDs |
| Text change tracking | Common prefix + delta calculation | QTextEdit document model (more robust) |
| Markdown parsing | Manual delimiter search + offset map | Tag-based system with markdown tag tracking |
| URL protection | ❌ Missing | ✅ ParseEntities + overlap checks |
| Custom emoji | Placeholder char replacement | QTextEdit-integrated with native support |
| Performance | O(n) for text change, O(n²) for markdown parse | O(n) optimized with tag cache |

---

## Recommendations

1. **[CRITICAL FIX]** Add bounds check for emoji length (line 352)
2. **[IMPORTANT FIX]** Implement URL entity detection before markdown parsing (consider calling engine's URL parser if available, or regex-based detection)
3. **[OPTIONAL]** Implement common-suffix matching in `_onTextChanged()` for better efficiency with large pastes
4. **[TESTING]** Add test cases for:
   - Markdown inside URLs: `"Check **http://example.com/__path**"` should preserve URL integrity
   - Emoji at text end: Create emoji, then delete characters after it
   - Entity overlap: Multiple entities covering same range with mixed types

---

## No Critical Placeholders or Stubs Found

All methods are fully implemented and wired to entity tracking. No mock data, TODO comments, or disabled functionality detected.

# confirm_box — Audit Findings

## confirm_box — SingleChoiceBox closes on item selection (wrong behavior)

- [ ] [MAJOR] `_SingleChoiceContent._select()` closes the box immediately when a radio item is tapped, but AyuGram's `SingleChoiceBox` only closes via `group->setChangedCallback` which fires immediately on radio change — so the behavior is actually equivalent. However, the Dart version also adds an "OK" button (`Navigator.of(context).pop(_selected)`) that does nothing different from just tapping. The C++ version has no separate confirm action: it closes immediately in the callback with no OK button. The OK button in the Dart version is redundant but not wrong — it is a MAJOR behavioral deviation because AyuGram's `SingleChoiceBox` provides only one `addButton(tr::lng_box_ok(), [=] { box->closeBox(); })` which just closes without emitting the selection again. The Dart OK button pops with `_selected` which is correct. Not a blocker, but behaviorally different flow. — `confirm_box.dart:799,817-820` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/single_choice_box.cpp:22,48-54`

## confirm_box — showReportReactionBox missing ban-user checkbox

- [ ] [CRITICAL] `showReportReactionBox` in Dart shows a box with title "Report Reactions" and a "BAN USER" confirm button, but the AyuGram `ReportReactionBox` includes an optional **checkbox** "Ban user and report" (`tr::lng_report_and_ban_button`) that is conditionally shown based on a `ban` parameter. The Dart implementation hardcodes the ban action into the confirm button label without offering the checkbox — meaning the user cannot choose to only report without banning. Furthermore, the Dart implementation does NOT call the engine at all — it only returns a `bool` to the caller but performs no API call. The AyuGram version calls `MTPmessages_ReportReaction` directly (the engine call). The Dart box is purely a UI stub with no backend wiring. — `confirm_box.dart:1551-1582` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_actions.cpp:1295-1343`

## confirm_box — showReportReactionBox missing ban-kick API call

- [ ] [CRITICAL] When AyuGram's `ReportReactionBox` confirm is pressed, it (a) kicks the participant from the group via `chatParticipants().kick()` if ban checkbox is checked, and (b) calls `MTPmessages_ReportReaction` on the session API. The Dart `showReportReactionBox` does neither — it simply returns `true` to the caller with no engine call. No ban, no report API call. — `confirm_box.dart:1566-1572` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_actions.cpp:1315-1338`

## confirm_box — showDynamicReportFlow receives `dynamic engine` (untyped)

- [ ] [CRITICAL] `showDynamicReportFlow` accepts `engine` as `dynamic` type (`required dynamic engine`) instead of the typed `EngineService`. This bypasses all type-checking and any method resolution errors will be runtime crashes. The AyuGram equivalent passes a properly typed `Api::CreateReportMessagesOrStoriesCallback` closure. — `confirm_box.dart:1311-1315` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/report_messages_box.cpp:75-78`

## confirm_box — ReportDetailsBox uses wrong Lottie animation

- [ ] [MAJOR] `_ReportDetailsBox` uses the animation `'assets/animations/blocked_peers_empty.json'` as the decorative icon in the report details box. AyuGram's `AddReportDetailsIconButton` also uses `"blocked_peers_empty"` as the lottie icon name (via `Settings::CreateLottieIcon`), so this matches. However, in AyuGram this icon is displayed before the text explaining the report (`tr::lng_report_details_about()`). The Dart box shows the lottie animation, then a description text, then a TextField — which matches the AyuGram order. No issue here on icon name, but the description text used is `'Please enter any additional details relevant to your report.'` while AyuGram uses `tr::lng_report_details_about()` which in English renders as "Please describe the violation in a few words." — a different string. — `confirm_box.dart:1499-1510` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/report_box_graphics.cpp:130-145`

## confirm_box — ReportDetailsBox submit does not distinguish optional vs mandatory

- [ ] [MAJOR] AyuGram's `ReportDetailsBox` (the one called from the static photo-report flow) submits regardless of whether text is empty — the optional check belongs to the dynamic flow box. The Dart `_ReportDetailsBox` has a proper `optional` field and validates when `!optional && text.isEmpty`. This matches the dynamic report flow (`report_messages_box.cpp:171-177`). However, when `optional=true` (the default), the Dart box submits an empty string which is then returned to `showDynamicReportFlow` — which is correct behavior. Not a bug.

## confirm_box — _DeleteContent._confirmLabel wrong count for deleteAll with moderatePanel

- [ ] [MAJOR] In `_confirmLabel` getter (line 566-569), when `_deleteAll` is true, the Dart code computes count as `_totalFromSender` when `> 0`, else falls back to `widget.messageCount`. In AyuGram `delete_messages_box.cpp:218-233`, the delete button text is updated reactively from a `MessagesSearch` that queries the server for total messages from that user. The Dart `_fetchModerateCount` calls `engine.countMessagesFrom()` synchronously (line 504) which uses a local JSON call, not a live server search. This means the count shown in the button may be stale (local cache count vs server-side search result). — `confirm_box.dart:504,566-569` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/delete_messages_box.cpp:206-234`

## confirm_box — _DeleteContent missing hasSavedMusicMessages and hasScheduledMessages checks

- [ ] [MAJOR] AyuGram's `DeleteMessagesBox::prepare()` has two additional text variants: `hasSavedMusicMessages()` changes the body to `tr::lng_selected_remove_saved_music` and suppresses the revoke checkbox for scheduled messages (`hasScheduledMessages()` → skip revoke). Neither check exists in the Dart `_DeleteContent`. The revoke checkbox will incorrectly appear for saved-music messages and scheduled messages when it shouldn't. — `confirm_box.dart:510-550,574-584` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/delete_messages_box.cpp:236-295`

## confirm_box — _DeleteContent missing paidPostType / paid-post delete confirmation

- [ ] [MAJOR] AyuGram's `deleteAndClear()` checks `paidPostType()` and shows a nested confirmation box (with warning text about Stars/TON) before actually deleting paid suggested posts. The Dart `_confirm()` (line 586-598) has no such check — it always calls `Navigator.pop` immediately. Deleting a paid suggested post will skip the secondary safety confirmation. — `confirm_box.dart:586-598` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/delete_messages_box.cpp:550-578`

## confirm_box — _DeleteContent missing date-range delete mode

- [ ] [MAJOR] AyuGram's `DeleteMessagesBox` has a 4th constructor for date-range deletion (`firstDayToDelete`/`lastDayToDelete`) with its own body text (`tr::lng_sure_delete_by_date_one` / `tr::lng_sure_delete_by_date_many`). The Dart `DeleteBoxMode` enum has no equivalent mode, so the date-range bulk-delete confirmation path is entirely absent. — `confirm_box.dart:391` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/delete_messages_box.cpp:72-121`

## confirm_box — _DeleteContent revokeLabel wrong for clearHistory on megagroup/group

- [ ] [MAJOR] For `clearHistory` mode on a group/megagroup peer, AyuGram shows a revoke checkbox (calls `revokeText(peer)`) only if `canRevokeFullHistory()` is true and the peer is a user. For channels it sets `_revokeJustClearForChannel = true` and skips the revoke checkbox. The Dart `_revokeLabel` getter returns `null` for all `clearHistory` modes (line 574-584 — it only returns a label for `singleMessage`/`bulkMessages`). This is correct for clear-history but the `canRevoke` field still being `true` at the call site when used for history-clearing DMs would incorrectly suppress the checkbox display because the Dart code only checks `mode`. The fix path must be verified at call sites, but the getter logic here is structurally correct for the cases handled. Not a separate MAJOR.

## confirm_box — ScreenShareChooser uses xrandr/wmctrl (X11-only, no Wayland support)

- [ ] [MAJOR] `_ScreenShareChooserState._loadSources()` uses `xrandr --listmonitors` and `wmctrl -l` / `xdotool` to enumerate screens and windows. These are X11 tools. On Wayland (which is the default for KDE/GNOME since ~2023) `xrandr` only works via XWayland and `wmctrl`/`xdotool` don't work at all on native Wayland windows. The AyuGram screen-share chooser uses platform-native APIs (PipeWire on Linux). The Dart implementation will silently fail to enumerate windows on Wayland, falling back to a single "Entire Screen" entry with no window list — `confirm_box.dart:1071-1149` ← AyuGram uses PipeWire/portal (no direct equivalent file, this is a systemic platform limitation)

## confirm_box — ScreenShareChooser source thumbnails missing

- [ ] [MAJOR] AyuGram's screen-share chooser shows live thumbnail previews of each screen/window source in the grid. The Dart `_ScreenShareChooser` shows only a static `Icons.desktop_windows` or `Icons.web_asset` icon — no preview thumbnail at all. Users cannot visually identify which window to select. — `confirm_box.dart:1221-1229` ← AyuGram desktop screen-share chooser provides live capture previews

## confirm_box — _RadioRow top padding (20px bottom-only per row) vs AyuGram (boxOptionListSkip: 20px as margin bottom per item)

- [ ] [MAJOR] Each `_RadioRow` uses `padding: const EdgeInsets.fromLTRB(24, 0, 24, 20)` (line 860). AyuGram's `SingleChoiceBox` adds each radio with `QMargins(st::boxPadding.left() + st::boxOptionListPadding.left(), 0, st::boxPadding.right(), st::boxOptionListSkip)` where `boxOptionListSkip = 20px` and `boxOptionListPadding = margins(0,0,0,0)`. The left margin in AyuGram is `24 + 0 = 24px` which matches. However AyuGram adds a top-spacer widget of height `st::boxOptionListPadding.top() + st::autolockButton.margin.top()` before the first radio. The Dart adds `const EdgeInsets.only(top: 4, bottom: 8)` padding to the containing Column instead. This is a minor layout difference in the top spacing but the per-row spacing matches. Not enough for MAJOR, skip.

## confirm_box — boxClosing cancel callback not fired when dialog is dismissed via barrier

- [ ] [MAJOR] AyuGram's `ConfirmBox` wires `box->boxClosing()` to always fire the cancel callback (line 100-103 in confirm_box.cpp), unless `strictCancel` is set (line 106-108). The Dart `showConfirmBox` tracks `confirmed` and `explicitCancel` booleans and calls `onCancel` in `.then()` if neither is set (line 341-343). However the `strictCancel` handling is inverted: when `strictCancel=true`, AyuGram calls `lifetime->destroy()` to disconnect the boxClosing signal so cancel is NOT fired on barrier dismiss. The Dart code checks `!strictCancel` before calling `onCancel` in `.then()` — which is logically equivalent. This is correct.

## confirm_box — _ReportOptionPickerBox missing left "Back" button

- [ ] [MAJOR] AyuGram's dynamic report box (`report_messages_box.cpp:191-196`) adds a left-aligned back button (`tr::lng_create_group_back`) when `!reportInput.optionId.isNull()` (i.e., when at a sub-level of the option tree). The Dart `_ReportOptionPickerBox` only has a "CANCEL" button with no back navigation — meaning users cannot go back one level in a multi-level report option tree, they can only cancel the entire flow. — `confirm_box.dart:1414-1421` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/report_messages_box.cpp:191-196`

## confirm_box — _ReportOptionPickerBox missing "comment" option inline in picker box

- [ ] [MAJOR] AyuGram's dynamic box renders both option buttons AND (if `result.commentOption` is set) an inline `InputField` plus a divider label, all within a single box. The Dart `showDynamicReportFlow` handles the `'add_comment'` branch by opening a separate `showReportDetailsBox`. This means the comment input appears in a new box rather than inline, which is a UX difference vs AyuGram (comment field is shown in the same box as other options when `commentOption` is present). — `confirm_box.dart:1349-1369` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/report_messages_box.cpp:124-196`

## confirm_box — getPermissionStatus uses pactl/ls for permission detection (unreliable)

- [ ] [MAJOR] `getPermissionStatus` for microphone runs `pactl list sources short` and treats any output as "granted" (line 904-911). This checks PulseAudio/PipeWire availability, not actual permission. A system can have PulseAudio running but still deny microphone access to the app. For camera it checks `/dev/video0` existence (line 912-915), which will show as granted even if the app lacks `video` group membership. AyuGram on Linux uses platform-level permission APIs. These heuristics will return false positives — the app skips the permission denied box when the mic/camera is actually unavailable to it. — `confirm_box.dart:899-919` ← AyuGram uses Qt's permission system (no direct file equivalent, systemic issue)

# contacts_screen — contacts box, row, edit/share dialogs

## Findings

- [ ] [CRITICAL] `_suggestBirthday()` shows a toast with the selected date string but never calls any engine method. The Go core has `UsersSuggestBirthday` (`telegram.go:24400`) but it is not wired through `bridge.go` and not exposed in `engine_service.dart`. The AyuGram implementation opens `internal:edit_birthday:suggest:<userId>` URL which routes to the full birthday edit flow. The Dart stub silently drops the birthday suggestion on the floor. — `contacts_screen.dart:1397-1408` ← `AyuGram/boxes/peers/edit_contact_box.cpp:582-589`

- [ ] [CRITICAL] Online-sort is never updated while the dialog is open: `_throttledRefresh()` is defined but never called — there is no subscription to `EngineService.onUserStatus` events. The AyuGram `ContactsBoxController::setSortMode(Online)` subscribes to `session().changes().peerUpdates(OnlineStatus)` and fires `_sortByOnlineTimer` on every online-status change to re-sort the list. Without this, the contact order freezes at open time and never reflects users coming online/offline. — `contacts_screen.dart:292-296` (dead code — never invoked) ← `AyuGram/boxes/peer_list_controllers.cpp:791-803`

- [ ] [CRITICAL] Middle-click on a contact row calls `widget.onTap()` (opens chat in same window) instead of opening the chat in a new window. AyuGram `rowMiddleClicked` fires `_wheelClicks` event which is handled with `window->showInNewWindow(p)`. — `contacts_screen.dart:1059` ← `AyuGram/boxes/peer_list_controllers.cpp:137-153, 183-185`

- [ ] [MAJOR] Mutual-contact indicator is entirely absent. AyuGram shows a dedicated `ayuContactsMutualIcon` right-action badge on each row where `isMutualContact()` is true (the user's contact who also has the current user in their contacts). No equivalent field, model field, or rendering exists in the Dart codebase. — `contacts_screen.dart:687-1141` (no mutual indicator anywhere) ← `AyuGram/boxes/peer_list_controllers.cpp:65-114`

- [ ] [MAJOR] Share-contact box uses a dynamic `_columnsForWidth()` formula `(screenWidth / 90).floor().clamp(3, 10)` instead of AyuGram's fixed 4-column layout. AyuGram `ShareBox::Inner` initialises `_columnCount = 4` as a constant and never changes it. The Dart value will produce different grids at narrow widths (3 columns at 270px, etc.) diverging from the reference. — `contacts_screen.dart:1942-1944` ← `AyuGram/boxes/share_box.cpp:180`

- [ ] [MAJOR] The `_ContactsBox` sort toggle icon uses Material `Icons.sort_by_alpha` / `Icons.access_time`, deviating from AyuGram's custom `contacts_alphabet` / `contacts_online` SVG icons. AyuGram also dynamically overrides the icon via `setIconOverride` after each toggle (alphabet icon shown when currently sorted by online, online icon shown when sorted alphabetically). The Dart toggles the correct direction but uses wrong icons. — `contacts_screen.dart:671-676` ← `AyuGram/boxes/peer_list_controllers.cpp:172-180`, `AyuGram/boxes/boxes.style:162-173`

- [ ] [MAJOR] The sort-button hover highlight feature is missing. AyuGram calls `window->checkHighlightControl(u"contacts/sort"_q, state->toggleSort, { .rippleShape = true })` via `setShowFinishedCallback` so the sort button gets a ripple highlight the first time the contacts box opens. No equivalent exists in the Dart `_SortToggle`. — `contacts_screen.dart:637-684` ← `AyuGram/boxes/peer_list_controllers.cpp:186-193`

- [ ] [MAJOR] `_suggestPhoto` in `_EditContactBox` uses `suggestContactPhoto` (engine method exists, line 504 of engine_service.dart) and correctly calls the engine. However the suggest-photo button should be hidden when `_user->starsPerMessageChecked()` is true (user requires stars-per-message). There is no `starsPerMessage` field in `ContactInfo` and no hide-guard on the button. This causes the button to appear for premium-pay-per-message bots where it is disabled in AyuGram. — `contacts_screen.dart:1622-1629` ← `AyuGram/boxes/peers/edit_contact_box.cpp:619-620`

- [ ] [MAJOR] `_ContactsBox` does not subscribe to any engine events (contact added/deleted/updated) to refresh the list. After `deleteContact`, `addContact`, or `blockUser` calls, the contact list only refreshes via `_loadContacts()` triggered by `onContactChanged` callbacks — but these are only wired from the row-level callbacks, not from background engine events (e.g. contact deleted on another device). AyuGram's `ContactsBoxController::prepare()` calls `rebuildRows()` and subscribes to session change events for live refresh. — `contacts_screen.dart:70-86` ← `AyuGram/boxes/peer_list_controllers.cpp:723-758`

## create_group_wizard — Create Group/Channel Wizard

- [ ] [CRITICAL] `CreateGroup` does not pass TTL at creation time: Go backend calls `MessagesCreateChat` without the `TtlPeriod` field, then the Dart code issues a separate `setHistoryTTL` after creation. AyuGram passes `f_ttl_period` flag and the TTL value atomically inside `MTPmessages_CreateChat`. This can leave the group without a TTL if the post-creation call fails, and is a behavioral deviation from spec. — `create_group_wizard.dart:713-718` ← `boxes/add_contact_box.cpp:743-748`

- [ ] [CRITICAL] No Forum/Megagroup wizard type — the wizard exposes only `group` and `channel` wizard types. AyuGram has four types: `Type::Group`, `Type::Channel`, `Type::Megagroup`, and `Type::Forum`. Megagroup and Forum creation use different `MTPchannels_CreateChannel` flags (`f_megagroup`, `f_forum`). There is no UI or code path to create a public megagroup (supergroup) or a forum via this wizard. — `create_group_wizard.dart:27` ← `boxes/add_contact_box.cpp:832-836`

- [ ] [CRITICAL] `CHANNELS_TOO_MUCH` on channel/group creation shows only a text error, not a `ChannelsLimitBox`. AyuGram responds to this error by opening `Box(ChannelsLimitBox, &controller->session())`. The Dart wizard just sets `_error` to a string and leaves the user with no action. — `create_group_wizard.dart:683,734` ← `boxes/add_contact_box.cpp:902-905`

- [ ] [CRITICAL] `PEER_FLOOD` on member addition shows only generic text. AyuGram calls `PeerFloodErrorText()` which generates a localized message with a clickable "More Info" link pointing to `t.me/spambot`. Dart shows `'Too many requests. Please try again later.'` — no link, no spambot reference. — `create_group_wizard.dart:685,735` ← `boxes/add_contact_box.cpp:243-248`

- [ ] [CRITICAL] `USERS_TOO_FEW` on group creation shows text only. AyuGram shows `Ui::MakeInformBox(tr::lng_cant_invite_privacy())` — an informational dialog explaining privacy settings prevented adding the user. Dart shows only an error string inline. — `create_group_wizard.dart:684,733` ← `boxes/add_contact_box.cpp:768-770`

- [ ] [MAJOR] `CHANNELS_ADMIN_PUBLIC_TOO_MUCH` during username check in `SetupChannelBox` should force-switch to Private (set `_tooMuchUsernames = true`, then when user tries to switch back to Public, show the revoke dialog). The Dart `_checkUsernameApi` just shows a toast / sets `_isPublic = false` with no state-machine to block the user from switching back to public without revoking. — `create_group_wizard.dart:555-558` ← `boxes/add_contact_box.cpp:1465-1471`

- [ ] [MAJOR] `SetupChannelBox` performs an initial username availability check against `"preston"` on `prepare()` to detect server-side restrictions before the user types anything (e.g. `CHANNEL_PUBLIC_GROUP_NA` or `CHANNELS_ADMIN_PUBLIC_TOO_MUCH`). The Dart setup channel step has no equivalent initial server-side probe — it only checks when the user types into the username field. — `create_group_wizard.dart:120-127` ← `boxes/add_contact_box.cpp:1038-1044`

- [ ] [MAJOR] Member add error `USER_PRIVACY_RESTRICTED` is unhandled. AyuGram calls `ChatInviteForbidden(show, chat, forbidden)` which shows a specific dialog explaining the user's privacy settings blocked the invite. In the Dart wizard the entire error surface is a single `catch (e)` showing `e.toString()` — no fine-grained invite error handling. — `create_group_wizard.dart:793-799` ← `boxes/add_contact_box.cpp:250-253`

- [ ] [MAJOR] `USERNAME_NOT_MODIFIED` is not treated as success in `_save()` of `_EditPeerTypeBoxState`. AyuGram's `parseError` maps `USERNAME_NOT_MODIFIED` → `UsernameResult::Ok` and closes the box. If the user saves without actually changing the username, the Dart code catches the exception and displays it as an error. — `create_group_wizard.dart:2739-2773` ← `boxes/add_contact_box.cpp:1418-1420`

- [ ] [MAJOR] `USERNAMES_UNAVAILABLE` error is unhandled in `_save()`. AyuGram maps it to `UsernameResult::Occupied` (same as `USERNAME_OCCUPIED`) and shows the "link already taken" error. Dart's catch block will surface the raw exception string. — `create_group_wizard.dart:2739-2773` ← `boxes/add_contact_box.cpp:1426-1428`

# custom_emoji_cache — Broken listener notification, wrong frame sizes, memory leak

- [ ] [CRITICAL] `addListener()` consumers (`emoji_status_widget.dart:49`, `reactions_detail.dart:1317`, `message_bubble.dart:2278`, `message_bubble.dart:5995`) are NEVER notified on successful cache loads. `_notifyListeners(changedDocIds)` only fires `_globalListeners` when `changedDocIds` is null/empty — but every successful fetch passes a non-empty set, so the else-branch is dead in the happy path. Widgets using `addListener()` register in `_globalListeners` but only get callbacks on error (empty changedIds). Emoji status icons, custom emoji in messages, and reaction emoji will permanently show placeholders after data loads. — `custom_emoji_cache.dart:478-493` ← `data_custom_emoji.cpp:878` (AyuGram per-instance repaint callback always fires on the specific instance, never silently dropped)

- [ ] [MAJOR] `isolated` frame size hardcoded to 43px; AyuGram computes `(st::largeEmojiSize + 2 * st::largeEmojiOutline) = (36 + 2) = 38px` at default scale — 13.2% deviation, isolated emoji (1–7 emoji-only messages) will render oversized. — `custom_emoji_cache.dart:46` ← `data_custom_emoji.cpp:87-89` + `chat.style:773-774`

- [ ] [MAJOR] `setIcon` frame size hardcoded to 24px; AyuGram computes `int(ConvertScale(18 * 7 / 6., scale)) = 21px` at default scale — 14.3% deviation, sticker-set footer icons and emoji status icons will render wrong size. — `custom_emoji_cache.dart:47` ← `data_custom_emoji.cpp:91-92`

- [ ] [MAJOR] `normal` frame size hardcoded to 20px; AyuGram applies `AdjustCustomEmojiSize(emojiSize) = round(emojiSize * 1.12)` making it ~22px — ~10% deviation, inline custom emoji in text will render slightly smaller than spec. — `custom_emoji_cache.dart:43` ← `text_custom_emoji.cpp:44-46` + `data_custom_emoji.cpp:1011-1014`

- [ ] [MAJOR] `_evictFromMemory` does not clear `_thumbs` or `_paths` — all thumb and path bytes for unreferenced documents stay in memory forever. Only `_files` is removed. When ref count drops to zero (widget disposed), the animation file is freed but the thumbnail bytes leak. — `custom_emoji_cache.dart:197-205` ← `data_custom_emoji.cpp:864-869` (AyuGram erases the Instance from `_instances[sizeIndex]` map on destroy, fully freeing all cached data for that document+size)

- [ ] [MAJOR] `_retryDelayMs = 5000ms` retry backoff is invented; AyuGram's `requestFinished()` retries immediately when `_pendingForRequest` is non-empty — with 5s delay, transient failures leave emoji invisible for 5 seconds before retry, degrading perceived performance. — `custom_emoji_cache.dart:105` ← `data_custom_emoji.cpp:871-875`

# edit_forum_topic_box — 3 issues

- [ ] [MAJOR] `_showPremiumToast` missing "View Premium" navigation button — in AyuGram, the `StickerToast` for `Section::TopicIcon` renders a `RoundButton` whose click handler calls `Settings::ShowPremium(window, u"forum_topic_icon"_q)`, letting the user navigate to the Premium subscription page directly from the toast; the Dart overlay at line 577 shows only hardcoded text with no actionable button, so users cannot subscribe to Premium from the premium-icon block — `edit_forum_topic_box.dart:577` ← `AyuGram/SourceFiles/history/view/history_view_sticker_toast.cpp:226-239` / `AyuGram/SourceFiles/boxes/peers/edit_forum_topic_box.cpp:235-239`

- [ ] [MAJOR] `_buildSetTabIcon` calls `base64Decode` in the build method on every rebuild — `base64Decode(set.stickers.first.thumbB64)` at line 717 is executed for every emoji-set tab on every `setState` call (title changes, selection changes, etc.); base64 decoding is CPU-intensive and must be cached in `initState`/`_fetchInstalledEmojiSets` rather than computed during paint — `edit_forum_topic_box.dart:717` ← `AyuGram/SourceFiles/chat_helpers/emoji_list_widget.cpp` (EmojiListWidget lazily loads thumbnails once, not on every paint)

- [ ] [MAJOR] `_buildEmojiSetGrid` builds all stickers eagerly with `Wrap` — AyuGram uses `EmojiListWidget` with `Mode::TopicIcon` which is a virtualised, lazy-rendering list; the Dart `Wrap` inside `SingleChildScrollView` at line 800 constructs every sticker widget (potentially 100–200+ items per set) unconditionally on every rebuild triggered by title edits, causing jank on every keystroke while an emoji-set tab is active — `edit_forum_topic_box.dart:800` ← `AyuGram/SourceFiles/boxes/peers/edit_forum_topic_box.cpp:290-299` (`EmojiListWidget` with lazy `customRecentList`)

# edit_mark_box — Text field edit dialog with validation

## Issues Found

- [x] [MAJOR] Hardcoded border colors instead of theme colors — `edit_mark_box.dart:99,104` ← `edit_mark_box.cpp:31` (InputField uses `st::defaultInputField` theme style)
  - Dart hardcodes error color `0xFFe53935` (red) and focus color `0xFF40a7e3` (blue)
  - Should respect theme/palette like other UI elements
  - AyuGram uses `st::defaultInputField` which inherits theme colors from style system

- [x] [MAJOR] Manual error state management instead of InputField's built-in error handling — `edit_mark_box.dart:42-54,64-71` ← `edit_mark_box.cpp:73-80` (uses `_text->showError()`)
  - Dart: Manual `_showError` boolean, manual error clearing logic in listener
  - AyuGram: Uses `_text->showError()` method on InputField widget, cleaner separation of concerns
  - Dart duplicates error management that should be in the TextField/InputField widget

- [x] [MAJOR] Hardcoded font size and weight instead of using style constants — `edit_mark_box.dart:93,96` ← `edit_mark_box.cpp:31` (uses `st::defaultInputField`)
  - Dart hardcodes: `fontSize: 14` for input text, `fontWeight: FontWeight.w600, fontSize: 14` for hint
  - Should use responsive/themed font metrics from palette/style system
  - AyuGram uses `st::defaultInputField` which provides proper font configuration

- [x] [MAJOR] Padding hardcoded instead of using style constants — `edit_mark_box.dart:87` ← `edit_mark_box.cpp:37,41,92-93` (uses `st::contactPadding`, `st::boxPadding`, `st::newGroupInfoPadding`)
  - Dart: `EdgeInsets.fromLTRB(24, 2, 24, 8)` hardcoded
  - AyuGram: Calculates from style constants (`contactPadding.top()`, `boxPadding`, `newGroupInfoPadding`)
  - Makes layout non-responsive to style changes or different screen sizes

- [x] [MAJOR] Static title instead of reactive producer — `edit_mark_box.dart:6-22` (title: String) ← `edit_mark_box.cpp:21-23` (rpl::producer<QString> title)
  - Dart: Simple `String title` parameter - static, cannot update
  - AyuGram: Uses `rpl::producer<QString> title` - reactive, can update after creation
  - Limits use case where title might change dynamically

## Behavioral Differences

- [x] [MAJOR] Input field configuration mismatch — `edit_mark_box.dart:88-110` ← `edit_mark_box.cpp:29-33`
  - Dart: Uses standard Flutter TextField with custom decoration
  - AyuGram: Uses specialized Ui::InputField with:
    - Title passed to constructor (becomes reactive hint/label)
    - Built-in error styling via `showError()` method
    - Built-in focus handling via `setFocusFast()`
    - Reactive submit signal via `submits()` producer
  - Dart's standard TextField doesn't provide these conveniences

- [x] [MAJOR] Resize handling not implemented — `edit_mark_box.dart` lacks resizeEvent ← `edit_mark_box.cpp:82-94`
  - AyuGram: `resizeEvent()` recalculates InputField width and position based on new box width
  - Dart: TextField implicitly fills available width (depends on TelegramBox layout)
  - If box is resizable, Dart version might not reflow properly

## Summary

edit_mark_box.dart is a functional implementation but diverges significantly from AyuGram's design:
1. **Theme integration**: Hardcoded colors/fonts instead of using theme system
2. **Widget design**: Manual state management vs. specialized InputField with built-in behavior
3. **Responsiveness**: Hardcoded padding/dimensions vs. style constants
4. **Reactivity**: Static data vs. reactive producers

The Dart version works but lacks the flexibility and maintainability of the AyuGram reference implementation.

# emoji_panel — Emoji/Sticker/GIF tabbed panel audit

- [ ] [CRITICAL] `resetEmojiPrefsForAccountSwitch()` is defined but never called anywhere in the Dart codebase — module-level globals `_recentEmojis`, `_skinTonePrefs`, `_emojiPrefsConfigDir` persist across account switches, polluting the new account's emoji history with the previous account's data — `emoji_panel.dart:39` ← function exists but has zero callers

- [ ] [CRITICAL] `_onSearchResultContextMenu` saves GIF via `int.tryParse(result.id) ?? 0` — inline bot result IDs from Giphy/gif search are not numeric strings, so this resolves to 0 and calls `engine.saveGif(account, 0)`, saving nothing or the wrong document — `emoji_panel.dart:3013` ← `gifs_list_widget.cpp:AddGifAction` uses the document pointer directly, not a string-parsed int

- [ ] [MAJOR] Recent emoji limit is 50 instead of 54 — both `_recentEmojis.sublist(0, 50)` cap points use 50 — `emoji_panel.dart:834,911` ← `AyuGramDesktop/Telegram/SourceFiles/core/core_settings.h:74` (`constexpr auto kRecentEmojiLimit = 54`)

- [ ] [MAJOR] Skin tone color picker fires immediately on `onLongPress` — AyuGram delays 500ms before showing the picker (`kColorPickerDelay = crl::time(500)`, `_showPickerTimer.callOnce(kColorPickerDelay)`) to prevent accidental triggers — `emoji_panel.dart:1537` ← `AyuGramDesktop/Telegram/SourceFiles/chat_helpers/emoji_list_widget.cpp:72,2303`

- [ ] [MAJOR] Sticker pack removal (X button in section header) calls `_uninstallPack()` immediately with no confirmation dialog — AyuGram always shows `MakeConfirmRemoveSetBox` before uninstalling — `emoji_panel.dart:2190` ← `AyuGramDesktop/Telegram/SourceFiles/chat_helpers/stickers_list_widget.cpp:3296-3307`

- [ ] [MAJOR] Recent stickers display is hardcapped at 20 (`cappedRecent = recent.length > 20 ? recent.sublist(0, 20) : recent`) — Telegram API returns up to 200 recent stickers; AyuGram shows all of them (with optional "Unlimited recent stickers" flag) — `emoji_panel.dart:1670` ← `AyuGramDesktop/Telegram/SourceFiles/chat_helpers/stickers_list_widget.cpp:93-103`

- [ ] [MAJOR] Sticker/emoji panel data never refreshes after external changes — `_loaded` guard prevents re-fetch; no engine event subscriptions anywhere in `_StickerTabState` or `_EmojiTabState` — if user installs a pack from another screen, the panel stays stale until app restart — `emoji_panel.dart:1655` (initState with no event listeners)

- [ ] [MAJOR] `_gifFileCache` is a module-level `Map<int, String>` that grows forever — every GIF loaded writes a temp file to `/tmp/uniclient_gif_*.mp4` and caches the path; there is no eviction, size limit, or cleanup on dispose — accumulated temp files persist for the process lifetime — `emoji_panel.dart:3494`

- [ ] [MAJOR] Tab slide `AnimatedBuilder` reconstructs both full tab widget trees (`_EmojiTab`, `_StickerTab`, `_GifTab`) on every animation frame with no `RepaintBoundary` wrapping — the entire panel repaints every 16ms for 200ms on each tab switch — `emoji_panel.dart:574-621`

# ayu_filter — Regex filter engine

## Summary
`ayu_filter.dart` maps to `ayu/features/filters/filters_controller.cpp`, `filters_utils.cpp`, and `filters_cache_controller.cpp`. Core logic is largely correct; the critical gaps are: missing import confirmation dialog, wrong service-message type mapping for 25, and O(n) cache scan.

---

- [ ] [CRITICAL] `importFromJson` applies changes immediately with no confirmation dialog — C++ `FilterUtils::importFromJson` at `filters_utils.cpp:417-432` shows `Ui::MakeConfirmBox` with `ChangeSummaryText(changes)` and requires user approval before calling `applyChanges`; Dart `importFromJson` at `ayu_filter.dart:306` applies all filter/exclusion mutations directly with no user consent — `filters_utils.cpp:417` ← `ayu_filter.dart:306`

- [ ] [CRITICAL] `importFromJson` missing `HasChanges` guard — C++ checks `if (!HasChanges(changes))` at `filters_utils.cpp:411` and toasts `ayu_FiltersToastFailNoChanges` when nothing would change; Dart has no such guard and silently processes empty imports — `filters_utils.cpp:411` ← `ayu_filter.dart:306`

- [ ] [CRITICAL] Service type 25 mapped to boost text — `_serviceMessageType` at `ayu_filter.dart:190` returns 25 for messages containing "boosted"/"boost"; C++ `typeOfMessage` at `filters_utils.cpp:624` returns 25 (TYPE_GIFT_PREMIUM_CHANNEL) only when `gift->channel && gift->type == Premium`; boost service messages have no distinct type in C++ and fall through to 10 (TYPE_DATE) — `filters_utils.cpp:624` ← `ayu_filter.dart:190`

- [ ] [MAJOR] `_serviceMessageType` uses fragile text-string heuristics for all service types — Dart lines 185–192 match localized text strings ("Voice call", "Suggested", "wallpaper", etc.); C++ `typeOfMessage` at `filters_utils.cpp:534-637` uses structured media fields (`media->call()`, `media->photo()`, `media->paper()`, `item->isUserpicSuggestion()`, `media->gift()`, etc.) — any service message whose text doesn't match the Dart patterns will be misclassified as TYPE_DATE (10) instead of the correct type — `filters_utils.cpp:605` ← `ayu_filter.dart:185`

- [ ] [MAJOR] `_hasFilteredMessages` scans entire `_messageCache` linearly — `ayu_filter.dart:476-479` iterates all entries (up to `_maxCacheSize` = 10,000) and does string-prefix matching for every chat open; C++ `hasFilteredMessages` at `filters_cache_controller.cpp:161` checks `dialogsWithHiddenBlockedMessages` in O(1) then does `filteredMessages.find(peer->id.value)` to scope iteration to only that dialog's entries — `filters_cache_controller.cpp:161` ← `ayu_filter.dart:476`

- [ ] [MAJOR] `publishFilters` shows no success or failure toast — C++ `FilterUtils::publishFilters` at `filters_utils.cpp:382-391` calls `Ui::Toast::Show(tr::lng_stickers_copied)` on success and `Ui::Toast::Show(tr::ayu_FiltersToastFailPublish)` on failure; Dart `publishFilters` at `ayu_filter.dart:397-399` silently returns `null` on failure and at line 395-396 only copies to clipboard with no UI feedback — `filters_utils.cpp:382` ← `ayu_filter.dart:395`

- [ ] [MAJOR] `importFromLink` shows no failure toast — C++ `FilterUtils::gotFailure` at `filters_utils.cpp:696-699` calls `Ui::Toast::Show(tr::ayu_FiltersToastFailFetch)` on network error, and `filters_utils.cpp:318-320` shows `ayu_FiltersToastFailImport` for invalid JSON; Dart `importFromLink` at `ayu_filter.dart:359-361` returns an error string with no in-file toast, putting all feedback responsibility on callers — `filters_utils.cpp:696` ← `ayu_filter.dart:359`

# emoji_status_widget — Critical wiring issues with collectible & userpic formats

## Issues Found

- [x] **[CRITICAL]** Collectible emoji status colors never sent to widget — `emoji_status_widget.dart:96-98` expects format `"collectible:documentId:centerHex:edgeHex"`, but `telegram.go:11470` only returns document ID as plain number. Colors (centerColor, edgeColor) exist in AyuGram's `EmojiStatusCollectible` struct (`data_emoji_statuses.h:32-33`) but are never extracted or sent via FFI bridge.

- [x] **[CRITICAL]** Userpic emoji status not implemented in backend — `emoji_status_widget.dart:100-103` has code to handle `"userpic:"` prefix, but backend's `extractEmojiStatusID()` (`telegram.go:11462-11474`) never generates this format. This feature is completely unimplemented end-to-end.

- [x] **[CRITICAL]** Format mismatch with AyuGram reference — AyuGram's `CollectibleCustomEmojiId()` (`data_custom_emoji.cpp:1110-1111`) returns only `"collectible:" + collectible_id` (no colors, and collectible_id not document_id), but widget parser expects `"collectible:" + documentId + colors`. The IDs themselves are different types (collectible ID vs document ID).

- [x] **[MAJOR]** ShaderMask gradient application incomplete — `emoji_status_widget.dart:222-230` applies RadialGradient shader to collectible emojis, but without actual color data being sent (issue #1), this renders the gradient as transparent fallback. Even if colors were sent, the gradient rendering quality vs AyuGram spec is untested.

## Root Causes

1. **Backend mismatch**: Go's `extractEmojiStatusID()` strips all metadata except plain document ID
2. **Missing feature**: Userpic emoji status parsing never wired to backend
3. **Type confusion**: Collectible ID vs Document ID — AyuGram uses collectible ID for the serialized string, Dart expects document ID
4. **Missing data transport**: EmojiStatusCollectible colors (centerColor, edgeColor from `data_emoji_statuses.h`) need to be extracted and sent through FFI

## What AyuGram Does (Reference)

- Stores colors in `EmojiStatusCollectible` struct: centerColor, edgeColor (`data_emoji_statuses.h:26-39`)
- Serializes collectible status as: `"collectible:" + collectible_id` ONLY (no colors embedded) (`data_custom_emoji.cpp:1110-1111`)
- Colors accessed separately via `EmojiStatuses::collectibleInfo()` (`data_emoji_statuses.h:84`)

## Status

None of these features are fully wired. The widget compiles and renders fallbacks, but collectible gradient colors and userpic emoji status are completely non-functional.

# filter_column — Sidebar filter column

- [ ] [CRITICAL] Badge color on active tab ignores active state: when `unreadAllMuted=true` and `isActive=true`, Dart renders badge with `sideBarBadgeBgMuted`; AyuGram renders `sideBarBadgeBg` (non-muted) on active tabs regardless of muted state — `filter_column.dart:949-951` ← `lib_ui/ui/widgets/side_bar_button.cpp:162-164`

- [ ] [CRITICAL] No scroll-to-active when active folder changes programmatically: `_scrollToActiveTab()` is only called from `_onFolderTap()` (user tap). If the active folder changes from another screen, account switch, or any external source, the sidebar doesn't scroll to reveal the active tab — `filter_column.dart:340-341` ← `window/window_filters_menu.cpp:110-130`

- [ ] [CRITICAL] Locked folder does not reset active filter: AyuGram resets `activeChatsFilter` to `FilterId(0)` when the currently active filter becomes locked (exceeds premium limit after refresh). Dart has no such reset, leaving the user stuck in an inaccessible folder — `filter_column.dart:636` ← `window/window_filters_menu.cpp:235-238`

- [ ] [MAJOR] Hamburger unread indicator uses wrong approach: AyuGram switches the menu button's icon to a composite icon asset (`windowFiltersMainMenuUnread` / `windowFiltersMainMenuUnreadMuted`) that has the dot drawn into the icon artwork. Dart overlays an external 8×8 `Container` dot via `Stack`. Visual result differs from spec — `filter_column.dart:596-601` ← `window/window_filters_menu.cpp:161-178` and `window/window.style:276-283`

- [ ] [MAJOR] Lock icon renders differently from C++ reference: AyuGram prepends filler characters to the label text and draws the lock icon to the left of the first text line at the text baseline (`side_bar_button.cpp:105-125`). Dart wraps label in a `Row(lock icon, text)`, placing the lock icon to the left of the text block rather than at the baseline of line 1 — `filter_column.dart:904-924` ← `lib_ui/ui/widgets/side_bar_button.cpp:105-125`

## folders_settings_screen — Edit filter box missing static-title toggle; tag-color picker blocks non-premium users incorrectly; Share button is a stub; filter icons use generic Material icons instead of proper SVG filter icons

- [ ] [CRITICAL] `_EditFilterBox` has no "Disable Animations / Enable Animations" toggle button for static-title (emoji-only titles). AyuGram shows a `Ui::LinkButton` inside the name field that toggles `staticTitle` and controls whether custom-emoji in the folder name loop or freeze. The Dart box stores no `staticTitle` field and never passes it to `editFolder`/`createFolder`, so folders with animated custom-emoji titles cannot be made static — `folders_settings_screen.dart:1233–1755` ← `AyuGram/boxes/filters/edit_filter_box.cpp:455–488,820–846`

- [ ] [CRITICAL] In `_TagColorSection` (tag-color picker inside `_EditFilterBox`), clicking any color chip when the user is non-premium simply selects the color locally and lets the dialog be saved with that color index. AyuGram gates every non-`kNoTag` button click behind `ShowPremiumPreviewToBuy(w, PremiumFeature::FilterTags)` and does NOT update the local selection — non-premium users see all 7 colors as interactive but AyuGram blocks them. The Dart code lets non-premium users pick any color and saves it — `folders_settings_screen.dart:2117–2130` ← `AyuGram/boxes/filters/edit_filter_box.cpp:782–787`

- [ ] [CRITICAL] The "Show Tags" (`_TagsToggle`) section is shown unconditionally; AyuGram hides the entire tags section when `!session->premiumPossible()` (i.e. on non-standard TG clients/servers). The Dart code has no equivalent `premiumPossible` check — `folders_settings_screen.dart:424–435` ← `AyuGram/settings/sections/settings_folders.cpp:996–998`

- [ ] [CRITICAL] `_ShowLinkBox` "Share" button just copies the URL and shows a toast "Link copied to share" — it does not invoke any platform share sheet. AyuGram calls the OS share mechanism. This is a stub that pretends to share but only copies — `folders_settings_screen.dart:2708–2717` ← `AyuGram/boxes/filters/edit_filter_box.cpp:884–928`

- [ ] [CRITICAL] Tag-color section inside `_EditFilterBox` is always visible. AyuGram wraps it in a `SlideWrap` that is toggled off when `!(possible && (tagsEnabled || !premium))` — i.e. it hides when tags are disabled AND the user is premium, or when premium is not possible. The Dart `_TagColorSection` is always rendered with no such guard — `folders_settings_screen.dart:1980–1986` ← `AyuGram/boxes/filters/edit_filter_box.cpp:643–651`

- [ ] [MAJOR] Filter icon picker (`_FilterIconPanel` / `_kFilterIcons`) uses generic Material Design icons (e.g. `Icons.pets`, `Icons.menu_book`) as substitutes for the actual Telegram filter SVG icons. AyuGram renders real `Ui::FilterIcon` sprites loaded from `ui/filter_icon_panel` / `styles/style_filter_icons`. The mapping is visually wrong for all 30 icons — `folders_settings_screen.dart:26–57,3064` ← `AyuGram/boxes/filters/edit_filter_box.cpp:209–298`

- [ ] [MAJOR] `_FolderRow` marks removal immediately with `_pendingRemovals` and defers the actual `deleteFolder` call to `dispose()` (`_saveChanges`). AyuGram marks `row.removed = true` client-side immediately, then calls `state->save` on navigation-away which fires all pending MTProto requests in a controlled sequence (add → remove → reorder). The Dart version does each deletion independently and serially in a `for` loop without ordering guarantees, and never re-orders filters after removals — `folders_settings_screen.dart:143–154` ← `AyuGram/settings/sections/settings_folders.cpp:623–769`

- [ ] [MAJOR] When removing a chatlist folder, `_ChatlistFolderRemovalDialog._loadSuggestions` populates `_alwaysChats` from `folder.chatIds` directly from local state. AyuGram calls `MTPchatlists_GetLeaveChatlistSuggestions` to get the server-authoritative list of peers to suggest leaving, then additionally calls `Api::ProcessFilterRemove` which shows a dedicated removal box. The Dart code calls `getLeaveChatlistSuggestions` but uses `_alwaysChats` (derived from local `chatIds`) as the display list, not the server suggestions — the two lists can be different — `folders_settings_screen.dart:4419–4436` ← `AyuGram/settings/sections/settings_folders.cpp:394–418`

- [ ] [MAJOR] The View section (`_ViewSection`) uses `LayoutBuilder` with a `452px` width threshold to decide whether to show the section. AyuGram toggles it via `controller->enoughSpaceForFiltersValue()` which is a reactive signal based on the window's actual content width. The hardcoded `452` is an approximation that will be wrong on HiDPI or non-standard window sizes — `folders_settings_screen.dart:445–469` ← `AyuGram/settings/sections/settings_folders.cpp:1118`

- [ ] [MAJOR] `_EditFilterBox` closes on Save via `Navigator.of(context).pop(FolderInfo(...))` and the caller (`_showEditFilterBox`) calls `chatState.editFolder` / `chatState.createFolder`. AyuGram's flow runs `state->save(button, next)` which batches all pending add/remove/reorder MTProto requests atomically and only then calls `doneCallback`. The Dart flow always issues a separate editFolder/createFolder call without re-ordering the filter list — there is no equivalent `saveOrder` MTProto call (`messages.updateDialogFiltersOrder`) — `folders_settings_screen.dart:262–302` ← `AyuGram/settings/sections/settings_folders.cpp:765–769`

# forum_topic_icon — No issues found

Audited against:
- `AyuGram/Telegram/Resources/art/topic_icons/*.svg` (path/gradient/opacity ground truth)
- `AyuGram/Telegram/SourceFiles/dialogs/dialogs.style:55-74` (size/font/textTop values)
- `AyuGram/Telegram/SourceFiles/data/data_forum_topic.cpp:50-145` (letter extraction, fallback color, icon frame logic)

All CRITICAL and MAJOR checks passed:

**Sizes** — `defaultSize=21`, `normalSize=19`, `largeSize=26`, `infoSize=32` match `dialogs.style:55-74` exactly. Font sizes (11/10/13/15px bold) and textTop values (2/2/3/4px) are correct.

**Colors** — All 7 palettes (blue/yellow/violet/green/rose/red/gray) match their respective SVG `linearGradient` stop-colors exactly. `_defaultColorId=0x9AABAB` correctly mirrors AyuGram's `ForumTopicDefaultIcon()→"gray"` fallback path (`data_forum_topic.cpp:70-73`).

**Gradients** — `fillY1Frac`/`fillY2Frac`/`strokeY1Frac`/`strokeY2Frac` fractions correctly translate all SVG `y1%`/`y2%` values. Blue stroke `strokeY2Frac=0.9939588` matches `blue.svg` linearGradient-2 `y2="99.39588%"`.

**Stroke width** — `2.94736842` matches `blue.svg` and `gray.svg`. Green/red/violet/yellow/rose SVGs use `2.84210526` (~3.5% narrower) while Dart applies the blue value to all — deviation is ~0.026 px at 21 px (cosmetic, below 10% threshold).

**Bubble path shape** — Dart uses the blue/gray path (`M42,4.47368421`) for all 7 palettes; the green-family SVGs use a slightly different variant (`M42,4.42105263`). Pixel deviation is ~0.013 px at 21 px (cosmetic).

**Highlight opacity** — `withValues(alpha: 0.375)` vs SVG `opacity="0.37491644"` — difference is 0.02% (cosmetic).

**Letter extraction** — `title.characters` (Unicode grapheme clusters) + `RegExp(r'[\p{L}\p{N}]', unicode: true)` is semantically equivalent to AyuGram's `Ui::Emoji::Find`-skip + `QChar::isLetterOrNumber` (`data_forum_topic.cpp:101-126`). Both skip emoji sequences and return the first letter-or-digit codepoint.

**Letter alignment** — `(targetSize - tp.width) / 2` horizontal centering matches `style::al_top` (AlignHCenter|AlignTop) with `QRect(0, textTop, size, font->height*2)` (`data_forum_topic.cpp:138-141`).

**General icon** — `_GeneralIconPainter` reproduces `general.svg` (20×20 viewBox, single `#FFFFFF` path recolored via parameter), matching `ForumTopicGeneralIconFrame` (`data_forum_topic.cpp:147-163`).

**Custom emoji backend** — `engine.getCustomEmojiFiles` and `engine.getCustomEmojiThumbs` are both wired (`forum_topic_icon.dart:428,438`). TGS/Lottie, WebP, and WebM all have active render paths with proper fallback chain.

**Lifecycle** — Ref-counting (`_refRetain`/`_refRelease`) and 5-second deferred cache eviction are correctly implemented. `dispose()` cancels the timer, disposes animation/player/temp-file, and releases the ref.

# ghost_settings_page — Account picker label stale after account switch

- [ ] [CRITICAL] Account picker button shows the *active* account's name instead of the *selected* account's name after switching ghost profile — `ghost_settings_page.dart:85` passes `activeAccount: appState.activeAccount` to `_GhostEssentialsHeader`; `_AccountPickerButton._currentLabel` (line 591) returns `accountLabel(activeAccount!)` which is always the main app active account (e.g. account A), even after the user taps the picker and selects account B. The settings rendered below correctly switch to B's ghost settings (via `_selectedUserId`, line 94), but the picker label still reads A's name — misleading the user into thinking they are editing A's config. Fix: pass the account whose `selfUserId == _selectedUserId` (looked up from `appState.accounts`) instead of `appState.activeAccount`. ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_ayu.cpp:295` (`state->pickerButton->setText(PickerLabel(userId))` — the picker button text is explicitly updated to the newly-selected user's name inside `selectGhostProfile` every time the selection changes)

## hamburger_drawer — missing Go bridge handlers, wrong cover color, wrong My Profile target

- [ ] [CRITICAL] `MarkAllChatsRead` called from Dart but Go bridge handler does not exist — silent no-op — `hamburger_drawer.dart:407` ← `window_main_menu.cpp:769` (LRead uses `MarkAsReadChatList(chats)`; Go bridge `dispatch_engine.go` has no `MarkAllChatsRead` case)

- [ ] [CRITICAL] `OpenSavedMessages` called from Dart but Go bridge handler does not exist — silent no-op — `hamburger_drawer.dart:293` ← `window_main_menu.cpp:764` (`showPeerHistory(session.user())` navigates to Saved Messages; Go bridge `dispatch_engine.go` has no `OpenSavedMessages` case)

- [ ] [CRITICAL] `RemoveBotFromMenu` called from Dart but Go bridge handler does not exist — silent no-op — `hamburger_drawer.dart:188` ← `window_main_menu_helpers.cpp:345` (`bots->removeFromMenu(show, user)`; Go bridge `dispatch_engine.go` has no `RemoveBotFromMenu` case)

- [ ] [CRITICAL] "My Profile" tap opens `InfoPanel.pushUserProfileRequest` (user profile panel) instead of the user's Stories section — `hamburger_drawer.dart:165` ← `window_main_menu.cpp:713` (`controller->showSection(Info::Stories::Make(controller->session().user()))`)

- [ ] [MAJOR] Cover background uses `windowBgActive` (`#40a7e3`) but spec says `mainMenuCoverBg = dialogsBgActive` (`#419fd9`) — `hamburger_drawer.dart:748` ← `colors.palette:497` (`mainMenuCoverBg: dialogsBgActive`) and `window.style:124` (`toggledFg: mainMenuCoverBg`)

- [ ] [MAJOR] "Add Account" right-click context menu only shown when `Alt+Shift` is held; AyuGram shows it on any right-click (in release builds right-click without `IsAltShift` returns early but in normal use ctrl+click adds to production) — `hamburger_drawer.dart:1191` ← `settings_information.cpp:1032` (`!IsAltShift` guard is debug-only; normal right-click is swallowed)

- [ ] [MAJOR] Archive context menu missing "New Window" option (Ctrl+click on archive row should open archive in separate window); Dart has no ctrl-modifier check on the archive tap — `hamburger_drawer.dart:479` ← `window_main_menu.cpp:533` (`if (modifiers & Qt::ControlModifier) { controller->showInNewWindow(...) }`) and `window_peer_menu.cpp:1849` (`addNewWindow()` in `fillArchiveActions`)

- [ ] [MAJOR] Archive context menu missing "Expand/Collapse" toggle (shown when archive is not pinned to menu); Dart only shows a static "Show in chat list" item regardless of current archive state — `hamburger_drawer.dart:526` ← `window_peer_menu.cpp:1854` (`if (!inmenu) { _addAction(expand/collapse text, ...) }`)

- [ ] [MAJOR] Seasonal snowflake animation (Christmas/New Year decoration over cover, Dec 24–Jan 1 in night mode) is completely absent in Dart — `hamburger_drawer.dart` (no snowflake code) ← `window_main_menu.cpp:444` (`if (CanCheckSpecialEvent() && CheckSpecialEvent()) { … Ui::Snowflakes … }`)

- [ ] [MAJOR] SRead ("Mark Stories as Viewed") uses `markAllChatsRead` which does not send story-specific read packets; AyuGram calls `MarkAsReadChatList` which walks all chats including story sources and sends the appropriate MTProto read events — `hamburger_drawer.dart:443` ← `window_main_menu.cpp:791` (`MarkAsReadChatList(chats)` with `sendReadMessages=true`)

# info_panel — Audit findings

## info_panel — Backend wiring / Stub behavior

- [ ] [CRITICAL] `_RingtonePickerDialog` — selecting any ringtone just calls `Navigator.pop(context)` with no value; the selected tone ID is never passed to any engine call. `getSavedRingtones` is fetched but the sound is never applied. The entire ringtone picker is a non-functional stub that dismisses without setting anything. — `info_panel.dart:1458,1466` ← `api/api_ringtones.cpp:118`

- [ ] [CRITICAL] `avatarBytes` always passed as `null` in `_ChatInfoPage` cover delegate. Line 2650: `avatarBytes: widget.chat.avatarPath.isEmpty ? null : null` — both branches are `null`. The chat avatar bytes path through the avatar viewer is permanently dead; avatar-only chats (no local file, bytes available) show an initials fallback instead of the real avatar. — `info_panel.dart:2650`

- [ ] [CRITICAL] `_MediaListView` used inside the expanded inline grid of `_SharedMediaSection` renders a `Column` with unbounded `for` loops over all items (line 6043–6053). It is NOT lazy — every item is built immediately. For chats with 100+ files/audio/links/voice messages this freezes the UI. The `_SharedMediaSubPage` (full-screen view) correctly uses `SliverList.builder`, but the compact in-panel view does not. — `info_panel.dart:6043`

- [ ] [MAJOR] `_MediaGrid` (expanded inline panel view, lines 5854–5878) uses `ListView.builder(shrinkWrap: true, physics: NeverScrollableScrollPhysics())` inside a `Column`. This causes the framework to compute all children without virtualization (shrinkWrap forces full measurement), making grids with many photos/videos fully non-lazy. This is the same widget embedded in `_SharedMediaSection._toggleGrid`. — `info_panel.dart:5854`

- [ ] [MAJOR] `_GifMasonryGrid` (expanded inline panel view, lines 5970–5999) same issue: `ListView.builder(shrinkWrap: true, physics: NeverScrollableScrollPhysics())`. Full materialization with no virtual scrolling. — `info_panel.dart:5970`

## info_panel — Missing features / Missing renderers

- [ ] [MAJOR] `round` (video messages) and `poll` media types have no dedicated list item renderer. Both fall through to `default: return _FileListItem(...)` in `_MediaListView._buildListItem` (line 6062) and in `_SharedMediaSubPage._buildLazyList` (line 3378). Round messages should show a circular thumbnail with duration; polls should show a poll icon with question text. Rendering them as file rows is visually wrong. — `info_panel.dart:6062`

- [ ] [MAJOR] `_AudioListItem` (lines 6145–6218) has a static play icon but tapping it does nothing — no `onTap` handler, no `AudioService.play()` call. Clicking an audio track in the Shared Media list is a no-op. Similarly `_VoiceListItem` (lines 6220–6280) has no tap handler to start playback. AyuGram plays the track on tap from the media list. — `info_panel.dart:6145,6220`

- [ ] [MAJOR] `_FileListItem` (lines 6067–6143) has no `onTap` — tapping a file in the media list does nothing (no open/download action). — `info_panel.dart:6067`

- [ ] [MAJOR] `_LinkListItem` (lines 6314–6370) has no `onTap` — tapping a link does not open it in the browser. — `info_panel.dart:6314`

## info_panel — Visual accuracy

- [ ] [MAJOR] `_TopicInfoCoverDelegate.coverHeight` is hardcoded to `77.0` (line 1882). AyuGram's topic cover is a non-collapsing fixed bar that mirrors `st::infoTopicCover` dimensions; the hardcoded value has not been cross-referenced against the style sheet value and may be incorrect. The topic cover also has no action buttons (mute, etc.) unlike the user/group cover. — `info_panel.dart:1882`

- [ ] [MAJOR] `_MembersSection` renders the member list as a `Column` via `.map()` spread into the parent `Column` children (lines 7001–7009) with a manual `_displayLimit` = 20 / show-more button. AyuGram uses a proper sliver list that virtualizes all members. With 200+ members the full `Column` materializes all visible rows simultaneously without any virtualization. — `info_panel.dart:7001`

## info_panel — Minor wiring notes

- [ ] [MAJOR] `_GetMoreBoosts` button (line 7921) just copies the boost URL to clipboard with a toast. In AyuGram this opens the Premium/Boost purchase flow. Copying the URL is a stub workaround, not the real behavior. — `info_panel.dart:7921`

## input_dialogs — Input Dialogs (UsernameBox, AddContactBox, CountrySelectBox, EditInviteLink, CreatePollBox)

- [ ] [CRITICAL] UsernameBox: reorder of additional usernames never calls `reorderAccountUsernames` — dragging to reorder only updates local UI state; `_save()` only calls `toggleAccountUsername` and `updateAccountUsername` but never calls `engine.reorderAccountUsernames(accountId, newOrder)`, so reordering is silently discarded — `input_dialogs.dart:291-312` ← `username_box.cpp:372-383` (`list->save()` flushes reorder before `editor->save()`)

- [ ] [CRITICAL] EditInviteLink: existing expiry is always shown as "Custom" when editing — `initState` tries to match `existingExpire` (a Unix timestamp, e.g. `1748123456`) against preset keys `{3600, 86400, 604800}` using a 10% tolerance; a timestamp is never within 10% of a 3-digit/6-digit offset, so every link with a standard expiry is wrongly pre-populated as Custom — `input_dialogs.dart:1290-1302` ← `edit_invite_link.cpp:242` (AyuGram uses relative negative offsets like `-kHour, -kDay, -kDay*7` internally and computes expiry as `now - value`; Dart should compute the remaining seconds as `existingExpire - now` and match that)

- [ ] [MAJOR] CreatePollBox: poll options limit is hardcoded to 32 (`_kMaxOptions = 32`) instead of reading the server-configured `poll_answers_max` app config value — AyuGram reads `appConfig->pollOptionsLimit()` which defaults to 12 (not 32) and varies per server; Dart hardcodes 32, so polls will accept up to 32 options but the server will reject them beyond the configured limit — `input_dialogs.dart:1746` ← `create_poll_box.cpp:2510` (`appConfig->pollOptionsLimit()`)

- [ ] [MAJOR] CreatePollBox: poll media upload is local-path-only with no actual upload to Telegram servers — `_pickOptionMedia` collects a local file path and returns `CreatePollResult.optionMediaPaths` as strings; AyuGram uploads each option's media via `startPreparedPhotoUpload`/`startPreparedDocumentUpload`/`startPreparedVideoUpload` before submit, obtaining `MTPInputFile` references; the Dart flow passes raw file paths to `createPoll` which must handle upload internally, but this is not implemented — `input_dialogs.dart:1929-1958` ← `create_poll_box.cpp:1862-1930`

- [ ] [MAJOR] CreatePollBox: "Show Who Voted" (anonymous voting toggle) is missing — AyuGram has a separate `showWhoVoted` toggle (`lng_polls_create_show_who_voted`) distinct from `anonymous`; in AyuGram `anonymous=false` means public votes (show who voted), but it is a separate control that can be disabled for certain peer types; Dart conflates this with the `_anonymous` flag and does not check `_disabled & PollData::Flag::PublicVotes` — `input_dialogs.dart:2149-2155` ← `create_poll_box.cpp:2541-2553`

- [ ] [MAJOR] CreatePollBox: poll duration preset list diverges from AyuGram — Dart offers 12 presets (5min, 10min, 30min, 1h, 2h, 4h, 8h, 12h, 1d, 2d, 3d, 7d); AyuGram uses a popup menu with 5 presets (1h, 3h, 8h, 24h, 72h) plus a "Custom date/time" picker via `ChooseDateTimeBox`; Dart lacks the custom date picker for poll close time — `input_dialogs.dart:1872-1926` ← `create_poll_box.cpp:2664-2700`

- [ ] [MAJOR] UsernameBox: username check debounce fires on every keystroke including when the current username equals `widget.currentUsername` — the `_onChanged` guard at line 200 sets `_isValid=false` and returns early for unchanged username, but this means if the user types, deletes back to current username, then types again, the early-return leaves `_isValid=false` even though the empty-username clear path should allow saving; the save button is gated on `_isValid || username.isEmpty` so saving with unchanged username (clear case) still works, but this is confusing edge case behavior vs AyuGram which simply passes the original username through to the API — `input_dialogs.dart:200-208`

- [ ] [MAJOR] EditInviteLink: subscription toggle toast message missing when link is subscription-locked — AyuGram shows `lng_group_invite_subscription_toast` when clicking a locked subscription toggle; Dart simply sets `onTap: null` (disabling interaction entirely), which silently ignores the tap rather than explaining the lock — `input_dialogs.dart:1510-1513` ← `edit_invite_link.cpp:150-154`

# instant_view — Audit Findings

- [ ] [CRITICAL] Map block renders OpenStreetMap tiles directly instead of using Telegram's `GeoPoint`/`CloudFile` map service — `instant_view.dart:1436,1452` ← `AyuGramDesktop/Telegram/SourceFiles/iv/iv_instance.cpp` (`streamMap()`/`UpdateCloudFile()`). AyuGram fetches map tiles via `LoadCloudFile()` with `GeoPointLocation`; Dart opens an OSM URL in the external browser, breaking visual consistency and correct behavior.

- [ ] [CRITICAL] Subtitle block font size/weight mismatch — `instant_view.dart:383` uses `18px w500`; AyuGram `iv.style` specifies `ivSubtitleFont: font(16px semibold)` (16 px, semibold). >10% size deviation plus wrong weight.

- [ ] [MAJOR] Table colspan padding cells are inserted as bare `SizedBox.shrink()` outside a `TableCell` wrapper — `instant_view.dart:914–920`. Flutter's `Table` widget requires every child in a `TableRow` to be a `TableCell`; mixing unwrapped widgets and `TableCell` siblings in the same row produces layout errors and assertion failures on cells spanning >1 column.

- [ ] [MAJOR] Audio download failure is silent — `instant_view.dart:2064–2068`. On `engine.downloadIVDocument` exception the audio block returns without setting any error state, leaving the user staring at a stopped spinner. The video block correctly sets `_error` on failure (`instant_view.dart:1901`); audio must do the same — `AyuGramDesktop/Telegram/SourceFiles/iv/iv_instance.cpp` (audio error path shows fallback label).

- [ ] [MAJOR] `geo.access` field never validated before constructing the map tile URL — `instant_view.dart:1410`. AyuGram checks the `access` token before making the map request; without it the coordinates alone are insufficient for authenticated tile loading, and the block silently renders a broken map.

# emoji_data — Emoji keyword search data and EmojiKeywords manager

- [ ] [CRITICAL] `kEmojiSuggestions` hardcoded list covers ~500 emoji while AyuGram's legacy database (`emoji_autocomplete.json`) has **2666 entries** — roughly 81% of emoji are unsearchable via keyword fallback before server keywords load — `emoji_data.dart:3-643` ← `AyuGramDesktop/Telegram/lib_ui/emoji_suggestions/emoji_autocomplete.json` (2666 entries) + `emoji_keywords.cpp:200-242` (`AppendLegacySuggestions` calls `GetSuggestions`)

- [ ] [MAJOR] `_searchLegacyData` is called unconditionally at line 804 regardless of `exact` flag, so exact queries still search legacy data — C++ skips all legacy suggestions for exact queries entirely — `emoji_data.dart:804` ← `emoji_keywords.cpp:638-641` (`if (!exact) { AppendLegacySuggestions(result, query); }`)

- [ ] [MAJOR] `_searchLegacyData` is missing the bad-character filter from C++ `AppendLegacySuggestions` — C++ rejects queries containing chars outside `[a-zA-Z0-9_\-+]` before searching legacy data; Dart has no such guard, allowing spurious matches on emoji/punctuation queries — `emoji_data.dart:862-889` ← `emoji_keywords.cpp:203-212` (`badSuggestionChar` lambda + early return)

- [ ] [MAJOR] No `refreshed()` reactive signal — C++ fires `_refreshed.fire({})` whenever server keyword data arrives so the emoji suggestion widget can repaint; Dart has no equivalent, meaning the autocomplete list won't live-update when `loadServerKeywords` is called while the popup is open — `emoji_data.dart:698-907` (no signal) ← `emoji_keywords.h:37` (`rpl::producer<> refreshed() const`) + `emoji_keywords.cpp:518-519`

- [ ] [MAJOR] No disk caching of server keyword data — C++ reads/writes a binary cache at `internal::CacheFileFolder() + "/keywords/<lang>"` so keywords are available instantly on next launch without waiting for the API; Dart must re-fetch all keyword packs from the server on every cold start — `emoji_data.dart:682-695` (`load()` has no persist path) ← `emoji_keywords.cpp:84-166` (`ReadLocalCache` / `WriteLocalCache` + `CacheFilePath`)

- [ ] [MAJOR] No `maxQueryLength()` public API — C++ exposes `maxQueryLength()` so callers can skip the search entirely for queries longer than any stored key (perf guard); Dart exposes nothing, so `_searchLangPack` always enters the binary search even for impossibly long queries — `emoji_data.dart:823-860` (no early-exit on query length at call site) ← `emoji_keywords.h:49` (`int maxQueryLength() const`) + `emoji_keywords.cpp:682-690`

- [ ] [MAJOR] Always fetches full keyword list; never uses differential updates — C++ checks `_data.version > 0` and calls `messages.GetEmojiKeywordsDifference` for incremental updates (only changed keywords); Dart always issues `GetEmojiKeywords` (full fetch) and replaces all data, causing unnecessary bandwidth every hourly refresh — `emoji_data.dart:682-695` (full replace, no delta) ← `emoji_keywords.cpp:411-416` (`_data.version > 0 ? GetEmojiKeywordsDifference : GetEmojiKeywords`)

# keyboard_shortcuts — Audit findings

- [ ] [CRITICAL] `mediaPrevious`/`mediaNext` handlers seek ±5 seconds within the current track instead of moving to the previous/next playlist item — `keyboard_shortcuts.dart:1268-1287` ← `AyuGram/media/player/media_player_instance.cpp:1112-1124` (`previous()` / `next()` call `moveInPlaylist(data, ±1, false)` — track navigation, not seek)

- [ ] [CRITICAL] Chat-switch overlay (Ctrl+Tab) is registered as a plain shortcut command and only fires `showChatSwitchRequest` once (line 1091); AyuGram implements a full state machine via `HandlePossibleChatSwitch` that intercepts raw key events during an active switch: arrow-key/Q navigation within the overlay, Escape to cancel, Enter/Ctrl-release to confirm — none of that exists in the Dart shortcut system — `keyboard_shortcuts.dart:834-839, 1090-1097` ← `AyuGram/core/shortcuts.cpp:34-45, 894-974`

- [ ] [MAJOR] On macOS, folder shortcuts (`allChats`, `folder1`…`lastFolder`) bind with `control: true`, which the Mac key-swap at line 697–698 maps to Command ⌘ (`hwMeta`). AyuGram uses `meta` (= physical Control ^) for folder shortcuts on Mac (`const auto ctrl = Platform::IsMac() ? u"meta"_q : u"ctrl"_q`), so the two keys diverge: Dart fires on ⌘+1…⌘+8, AyuGram fires on ^+1…^+8 — `keyboard_shortcuts.dart:697-698, 884-907` ← `AyuGram/core/shortcuts.cpp:469, 511-517`

- [ ] [MAJOR] `supportScrollToCurrent` handler calls `ChatListPanel.requestNavigateChat(0)` ("navigate by 0 steps") instead of scrolling the list to the currently-active chat row; AyuGram's handler calls `scrollToEntry(row)` on the dialogs widget — `keyboard_shortcuts.dart:1301-1305` ← `AyuGram/core/shortcuts.cpp:87` + `AyuGram/dialogs/dialogs_inner_widget.cpp:5720-5727`

# language_box — Audit Findings

## language_box — Search widget type wrong (MultiSelect vs TextField)

- [ ] [MAJOR] AyuGram uses `Ui::MultiSelect` (tag-based search widget with cancel X button and `st::defaultMultiSelect` style), not a plain underline `TextField`. The Dart implementation uses a `TextField` with `UnderlineInputBorder` which has a different appearance and does not support the cancel (clear) button behavior — `language_box.dart:346-365` ← `AyuGram/SourceFiles/boxes/language_box.cpp:1339-1343`

## language_box — Keyboard navigation does not scroll list to highlighted item

- [ ] [MAJOR] When navigating with arrow/page/home/end keys, AyuGram calls `scrollToY(selected.ymin, selected.ymax)` to ensure the highlighted row is visible. Dart updates `_highlightIndex` but never calls `_scrollController.animateTo` or `jumpTo`, so the highlighted row can scroll off-screen — `language_box.dart:135-183` ← `AyuGram/SourceFiles/boxes/language_box.cpp:1510-1524`

## language_box — Description text after translation toggles is wrong

- [ ] [MAJOR] AyuGram shows `tr::lng_translate_settings_about` = "The 'Translate' button will appear in the context menu of messages containing text." Dart hardcodes "Translate messages in chats with a different language." which is a different string — `language_box.dart:338-340` ← `AyuGram/Resources/langs/lang.strings:6918`

## language_box — "Do Not Translate" row value uses nativeName instead of LanguageName

- [ ] [MAJOR] For single language, AyuGram calls `Ui::LanguageName(list.front())` which returns the English name translated into the current UI language. Dart's `_skipLangsLabel` returns `entry.nativeName` (the language's own name, e.g. "Русский" for Russian) instead of the localized English form — `language_box.dart:208-218` ← `AyuGram/SourceFiles/boxes/language_box.cpp:1488-1492`

## language_box — Skip languages editor uses Checkbox (left) instead of SettingsButton toggle (right)

- [ ] [MAJOR] AyuGram's `EditSkipTranslationLanguages` calls `Ui::ChooseLanguageBox` which renders each language as a `SettingsButton` with a **right-side toggle switch** (`paintToggle`). Dart's `_SkipLanguagesEditor` uses a `Checkbox` widget on the **left side** — a completely different visual layout — `language_box.dart:962-966` ← `AyuGram/SourceFiles/ui/boxes/choose_language_box.cpp:179,312-327`

## language_box — Menu toggle button size wrong (34px vs 40px)

- [ ] [MAJOR] AyuGram computes the menu toggle area as `size = st::topBarSearch.width = 40px` (square 40×40). Dart uses `SizedBox(width: 34, height: 34)` — 6px smaller — `language_box.dart:669-671` ← `AyuGram/SourceFiles/boxes/language_box.cpp:437` / `AyuGram/SourceFiles/info/info.style:1032-1033`

## language_box — Share toast text differs from AyuGram

- [ ] [MAJOR] AyuGram shows `tr::lng_username_copied` = "Link copied to clipboard" after copying the language link. Dart shows "Language link copied to clipboard." — a different hardcoded string — `language_box.dart:740-741` ← `AyuGram/SourceFiles/boxes/language_box.cpp:517`

## language_box — "At least one language" toast text differs

- [ ] [MAJOR] AyuGram shows `tr::lng_translate_settings_one` = "Please choose at least one language so that it can be used as the \"Translate to\" language." Dart shows the shorter hardcoded "You must keep at least one language." — `language_box.dart:845` ← `AyuGram/Resources/langs/lang.strings:6919`

## language_box — "N languages" label missing singular form

- [ ] [MAJOR] AyuGram uses `tr::lng_languages_count` which has plural forms: "{count} language" (one) / "{count} languages" (other). Dart hardcodes `'${langs.length} languages'` with no singular handling — `language_box.dart:217` ← `AyuGram/Resources/langs/lang.strings:650-651`

# media_viewer — Audit Findings

## media_viewer — Placeholders, Backend Wiring, Visual & Behavioral Issues

- [ ] [CRITICAL] Text recognition shells out to `tesseract` CLI and copies raw stdout to clipboard — no inline OCR overlay rendered on the image (AyuGram draws interactive text-region boxes over the photo with hover+copy support) — `media_viewer.dart:3395-3412` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:7275-7325`

- [ ] [CRITICAL] `_onDateTap` jumps by timestamp (`chatState.jumpToMessage(msg.timestamp)`) instead of by message ID — will land at wrong message when multiple messages share the same second — `media_viewer.dart:2680-2684` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:6507-6547`

- [ ] [CRITICAL] `_showInChat` also jumps by timestamp without `highlightMsgId` — same wrong-message bug as `_onDateTap`; the optional `highlightMsgId` parameter exists in `chat_state.dart` but is never passed — `media_viewer.dart:2816-2820` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:2016-2020`

- [ ] [CRITICAL] `_showInFolder` does not close the viewer after revealing the file in the file manager — AyuGram calls `close()` when not in windowed mode — `media_viewer.dart:3027-3031` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:3286-3291`

- [ ] [CRITICAL] Forward action shows a homemade `AlertDialog` chat-picker instead of the real forward box — missing "as copy", "no caption", "message link" options; does not respect `noForwards` flag at the API level — `media_viewer.dart:2822-2928` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:3293-3308`

- [ ] [CRITICAL] Copy-image and copy-frame to clipboard shell out to `wl-copy`/`xclip` subprocess — Linux-only, breaks on Windows/macOS and any Linux without those tools installed — `media_viewer.dart:2966-3024` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:3424-3430`

- [ ] [CRITICAL] `_onSenderTap` calls `UniClientShell.toggleInfoRequest` (opens current chat's info panel) instead of navigating to the sender's profile — `media_viewer.dart:2671-2678` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:6522-6530`

- [ ] [MAJOR] Zoom scale math is wrong — `_scaleForLevel` uses `(level+1)` / `1/(-level+1)` arithmetic giving 8× at level 7; AyuGram uses `exp2(_zoom)` giving 128× at level 7 — `media_viewer.dart:739-756` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:2626-2696`

- [ ] [MAJOR] Speed boost overlay always shows hardcoded `'2.0×'` label — AyuGram's speed is drag-adjustable so the label must update dynamically from `_preBoostSpeed` — `media_viewer.dart:4086` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:6227-6244`

- [ ] [MAJOR] Gallery thumbnail strip container is `80px` tall with no top/bottom padding — spec requires `14px` padding top + `80px` height + `14px` padding bottom = `108px` total; `_stripOffset` at line 529 also only adds 4px not 28px — `media_viewer.dart:69,529,3771` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view.style:286-291`

- [ ] [MAJOR] PIP progress track rendered as two `Flexible` containers in a `Row` — no `CustomPainter`, no rounded corners, missing `pipPlaybackSkip: 4px` padding above/below the track — `media_viewer.dart:4939-4975` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view.style:451-455`

- [ ] [MAJOR] OCR overlay (interactive text-region boxes on photo) is entirely absent — only the backend call and clipboard copy exist; the visual feature showing recognized text regions over the image is never rendered — `media_viewer.dart:3395-3412` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:1527-1530`

- [ ] [MAJOR] `mention` and `text_mention` caption entities are rendered as styled text but have no `TapGestureRecognizer` — tapping a mention does nothing; AyuGram opens the peer's profile — `media_viewer.dart:3531-3535` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:7558`

- [ ] [MAJOR] Story views avatar stack renders placeholder colored circles with person icon instead of real user photos — engine fetch returns viewer data with profile info but it is not used for avatar rendering — `media_viewer.dart:7654-7708` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp` (story views rendering)

- [ ] [MAJOR] `_shareAtTime` constructs a raw string like `"filename at MM:SS"` sent as a plain text message — AyuGram generates a `?t=` timestamp URL; also shown for private videos where a public link does not exist — `media_viewer.dart:3033-3118` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp` (share at time logic)

- [ ] [MAJOR] Save toast text hardcodes the word `'Downloads'` — when saving to a non-Downloads directory the label is wrong; AyuGram shows the actual resolved save path with a clickable directory link — `media_viewer.dart:2750` ← `AyuGramDesktop/Telegram/SourceFiles/media/view/media_view_overlay_widget.cpp:876-913`

# message_bubble — Audit

## Game card play stub, request_phone wiring, Telegram deep links

- [ ] [CRITICAL] `_GameCard._onPlay` stub: when no inline-keyboard button has a pre-cached URL (`btn.type == 'game' && btn.url.isNotEmpty` fails), the method starts `Future.delayed(const Duration(seconds: 15), ...)` which silently resets `_loading` without calling the engine. A `botCallbackGame` call must be issued instead (matching `_InlineButton._onTap`'s `'game'` case which already calls `chatState.botCallbackGame` correctly) — `message_bubble.dart:9037` ← `api/api_bot.cpp` (game button → `getBotCallbackAnswer` with `game=true`)

- [ ] [MAJOR] `request_phone` inline button sends the account phone number as a raw text message via `chatState.sendMessage(phone)` (line 9739). AyuGram shows a confirmation box (`tr::lng_bot_share_phone`) and, if confirmed, calls `session.api().shareContact(session.user(), action)` which sends an `InputMediaContact`. Sending as plain text is functionally incorrect — it produces a text message instead of a contact card — `message_bubble.dart:9734-9740` ← `api/api_bot.cpp:373-396`

- [ ] [MAJOR] `_WebPagePreview._buildActionButton` calls `Process.run('xdg-open', [url])` for every Telegram-type web-page link (`telegram_stickerset`, `telegram_botapp`, `telegram_channel`, `telegram_megagroup`, `telegram_chat`, `telegram_user`, `telegram_voicechat`, `telegram_livestream`, `telegram_theme`, `telegram_background`, `telegram_newbot`, `telegram_giftcode`, `telegram_channel_boost`, `telegram_channel_request`). All of these must be handled in-app (opening chats with `chatState.openChatById`, showing the sticker pack viewer for stickerset, opening `WebAppPanel` for botapp, etc.). Browser-fallback defeats the entire Telegram deep-link system — `message_bubble.dart:8836-8843` ← `history/view/media/history_view_web_page.cpp:147,333,354,365`

## my_profile_page — Profile/Edit Profile page audit

- [ ] [CRITICAL] `SetPersonalChannel` and `ClearPersonalChannel` are called from Dart but have NO handler in the Go engine dispatch (`dispatch_engine.go` has no `case "SetPersonalChannel"` or `case "ClearPersonalChannel"`). Engine calls silently fail — setting/clearing personal channel does nothing. — `my_profile_page.dart:2632,2594` ← `engine_service.dart:3843,3851` ← `dispatch_engine.go` (missing cases)

- [ ] [CRITICAL] Profile photo area (`_ProfilePhotoArea`) uses `Column(mainAxisAlignment: MainAxisAlignment.start)` with no `crossAxisAlignment: CrossAxisAlignment.center`, so the avatar, name, and status are left-aligned. AyuGram explicitly centers the photo horizontally with `(max - photoWidth) / 2` and centers name/status with `(max - name->width()) / 2`. The avatar will render pinned to the left edge of the column rather than centered in the available width. — `my_profile_page.dart:779-780` ← `settings_information.cpp:361-377`

- [ ] [CRITICAL] Upload sub-button is 30×30px. AyuGram specifies `uploadUserpicSize: 32px` and `uploadUserpicButtonBorder: 2px`. Dart button is 2px too small. — `my_profile_page.dart:1812-1813` ← `boxes.style:81,88`

- [ ] [CRITICAL] Avatar context menu for photo edit (`_showAvatarMenu`) has only two options: "Upload Photo" and "Set Emoji". AyuGram's `UserpicButton` role `ChoosePhoto` additionally shows the existing photo (view), supports clipboard paste, and integrates with the full media picker flow including "Suggest Photo" in peer context. Missing "View Photo" option when no tap triggers the viewer (tap on button triggers menu, not view). — `my_profile_page.dart:885-913` ← `userpic_button.cpp:247-274`

- [ ] [MAJOR] Bio field does not implement emoji autocomplete/suggestions. AyuGram calls `Ui::Emoji::SuggestionsController::Init()` and `bio->setInstantReplaces(Ui::InstantReplaces::Default())` on the bio `InputField`. The Dart `TextField` has no equivalent emoji popup. — `my_profile_page.dart:672-695` ← `settings_information.cpp:740-744`

- [ ] [MAJOR] Name-to-status vertical gap is `+1px` in Dart (`EdgeInsets.only(top: 1)`). AyuGram uses `settingsInfoNameSkip: -1px` — a negative skip meaning the status label overlaps the name by 1px, creating tighter spacing. Dart adds 1px of positive space instead, making the gap 2px off. — `my_profile_page.dart:856` ← `settings.style:213` / `settings_information.cpp:377`

- [ ] [MAJOR] `_YourColorRow` uses a custom inline `_EditPeerColorBox` dialog with 7 hardcoded fallback colors and a basic emoji picker. AyuGram's `AddPeerColorButton` opens `EditPeerColorBox` which shows a live color-indexed preview bubble rendered using `SetupPeerColorSample` → `Ui::ColorSample` (server-provided color indices, collectible colors, emoji status overlays, full message preview bubble). The Dart implementation shows a static color swatch labeled "A" with hardcoded colors rather than live server indices and the rich preview. — `my_profile_page.dart:1385-1398,1499-1795` ← `edit_peer_color_box.cpp:2724-2780`, `settings_information.cpp:522-529`

- [ ] [MAJOR] Birthday privacy footer logic uses a simplified string match (`'nobody'`, `'everyone'`, `'contacts'`, `'close_friends'`). AyuGram checks `isExactlyContacts` — a reactive stream that evaluates whether the privacy rule is exactly `Option::Contacts` with no allow/deny lists and no premium flag. The Dart fallback shows the wrong text when users have complex privacy rules (e.g. contacts-except-list), always displaying "your contacts" instead of the generic "manage" text. — `my_profile_page.dart:416-476` ← `settings_information.cpp:467-492`

- [ ] [MAJOR] `_EditPeerColorBox` preview widget shows "Your Name" and "Message preview text" as hardcoded strings. AyuGram's `SetupPeerColorSample` subscribes to `peerFlagsValue(peer, PeerUpdate::Flag::Name)` to show the real user name, and renders a full `Ui::ColorSample` bubble that updates reactively when the server returns color data. Dart uses static placeholder text. — `my_profile_page.dart:1608-1624` ← `edit_peer_color_box.cpp:2558-2572`

- [ ] [MAJOR] `_EditPeerColorBox` emoji placeholder falls back to displaying `#NNN` text for unresolved emoji IDs when `thumbB64` is empty. AyuGram renders emoji stickers using actual document thumbnails. The `#NNN` text is a stub. — `my_profile_page.dart:1775-1779`

- [ ] [MAJOR] Birthday picker dialog layout order is Day → Month → Year (left-to-right). AyuGram's `EditBirthdayBox` uses Day → Month → Year with specific geometry: years at right 50% width split, months in center, days at left — with each taking `half/2`, `half`, `half/2` respectively. Dart uses `Flexible(flex:1)`, `Flexible(flex:2)`, `Flexible(flex:1)` which is the same ratio but rendered by Flutter's flex, not AyuGram's fixed pixel geometry. Visual match is approximate but the picker widget is `Ui::VerticalDrumPicker` (custom C++ widget with configurable paint callbacks) vs Flutter's `ListWheelScrollView` — acceptable Flutter equivalent but picker height is 200px in both (AyuGram `settingsWorkingHoursPicker: 200px`, Dart `SizedBox(height: 200)`). — `my_profile_page.dart:2800-2830` ← `edit_birthday_box.cpp:35-95`, `settings.style:681`

# notification_popup — Audit vs AyuGram Default Notification Manager

## Dimensions / timing — all pass

All numeric constants match `window/window.style` exactly:
`_notifyWidth`=320, `_notifyMinHeight`=80, `_notifyDeltaX`=6, `_notifyDeltaY`=7,
`_photoSize`=62, `_photoPos`=9, `_closeSize`=30, `_closePosRight`=1, `_closePosTop`=2,
`_textLeft`=83 (9+62+12), `_textTop`=7, `_itemTopOffset`=12, `_borderWidth`=1,
`_hideAllHeight`=36, `_replyButtonSize`=36, `_replyFieldMinH`=36, `_replyFieldMaxH`=72,
`_fadeInDuration`=150 ms, `_slowHideDuration`=4000 ms, `_fastHideDuration`=150 ms,
`_waitBeforeHide`=3000 ms, `_actionsFadeDuration`=200 ms,
reply field padding `fromLTRB(8,8,8,6)` = `notifyReplyArea.textMargins(8,8,8,6)`.
Border color uses `palette?.windowShadowFgFallback` = `notifyBorder: windowShadowFgFallback`. ✓

---

- [ ] [CRITICAL] After reply is sent, the replied popup is slow-hidden (4 000 ms fade-out) instead of fast-hidden (150 ms). C++ `sendReply()` calls `manager()->notificationReplied()` → `unlinkFromShown()` → `unlinkHistory()` → `hideFast()` for the replied notification, then `manager()->startAllHiding()` slow-hides the rest. Dart `_onReplySend` calls `_startSlowHide` on every popup including the replied one, so it takes 4 seconds to disappear instead of 150 ms. — `notification_popup.dart:322-325` ← `AyuGram/window/notifications_manager_default.cpp:1168-1176`

- [ ] [MAJOR] `_hasReceivedInput` is forced to `true` via a 1-second `Timer`, bypassing the platform's user-input detection. C++ `checkLastInput()` queries the OS last-input timestamp via `base::Platform::LastUserInputTimeSupported()` and only starts the hide countdown when real input is detected. On platforms where `WaitForInputForCustom()` returns `true` (Windows), notifications should wait indefinitely until the user actually moves the mouse or types; Dart always overrides after 1 second. — `notification_popup.dart:181-186` ← `AyuGram/window/notifications_manager_default.cpp:767-784`

- [ ] [MAJOR] `_HiddenUserpicPlaceholder` clips the app icon to `BorderRadius.circular(4)` (rounded rect). C++ `hiddenUserpicPlaceholder()` scales `LogoNoMargin()` and draws it with `p.drawPixmap()` — no clip, no rounding. The logo's visual shape comes from the image itself (transparent corners), not from a widget clip. The Dart rounding is wrong. — `notification_popup.dart:776-778` ← `AyuGram/window/notifications_manager_default.cpp:115-127,923-925`

- [ ] [MAJOR] Reply field has no maximum message length. C++ calls `_replyArea->setMaxLength(MaxMessageSize)` (4 096 characters). Without a limit, the user can type an arbitrarily long string that will be rejected at the API level with no feedback. — `notification_popup.dart:997-1010` ← `AyuGram/window/notifications_manager_default.cpp:1138`

## notifications_settings_screen — Audit Results

- [ ] [CRITICAL] "Contact joined Telegram" toggle reads from local AppState persisted value (always hardcoded true on first run) instead of fetching actual server state via `engine.getContactSignUpNotification()` on screen open. The real value is only sent to the server on toggle, never initially read — so the UI shows the wrong state until the user toggles. — `notifications_settings_screen.dart:501` ← `settings_notifications.cpp:1286` (`session->api().contactSignupSilentCurrent()` fetched live)

- [ ] [CRITICAL] "Accept calls on this device" toggle reads from local AppState (`notifAcceptCallsOnDevice` hardcoded to `true`, persisted locally) instead of fetching the authorizations state from the engine. AyuGram calls `authorizations->reload()` every time this section is shown to get the live server value. The Dart screen never calls any equivalent fetch — state is always the persisted local default and can be permanently wrong after a device change. — `notifications_settings_screen.dart:558` ← `settings_notifications.cpp:1338` (`authorizations->reload()` called in `BuildCallNotificationsSection`)

- [ ] [CRITICAL] "Pinned messages" toggle state is local-only (AppState field defaulting to `true`, saved to SharedPreferences). AyuGram stores this in `Core::App().settings().notifyAboutPinned()` (global app settings, not server). The Dart side stores it locally but `saveLocalNotifyConfig` with `type: 'pinned_messages'` only writes to the SQLite `kv` table — this value is never read back to initialize the toggle on screen open, so the displayed state diverges from whatever was last saved. — `notifications_settings_screen.dart:516-524` ← `settings_notifications.cpp:1306-1323`

- [ ] [CRITICAL] "Notification sound" toggle in the type sub-page (`_NotificationTypeSubPage`) calls `_persistSoundState` which calls `updateDefaultNotifySettings` without the mute duration — this sends `enabled=true/false, forever=true/false` to Telegram's `account.updateDefaultNotifySettings` TL call, but the MuteMenu in AyuGram uses a time-based mute (`muteForever` or `muteFor N seconds`). The Dart toggle permanently unmutes or permanently mutes, discarding any timed mute the user may have set. — `notifications_settings_screen.dart:1680-1693` ← `settings_notifications_type.cpp:428-443` (`MuteMenu::SetupMuteMenu` with proper mute time handling)

- [ ] [CRITICAL] Reactions sub-page (`_ReactionsSubPage`) `_showFromDialog` shows only "From everyone" and "From my contacts" as options but omits "From nobody" as a selectable radio option. AyuGram's `ShowFromBox` shows `NotifyFrom::All` and `NotifyFrom::Contacts` — "None" is not a radio option there either, BUT the toggle button controls None. The dialog in Dart allows selecting values but then saves them without triggering re-check against current saved state, meaning double-tapping OK with same value fires a redundant API call. More critically: `ShowFromBox` only fires `done()` callback on OK (not Cancel), while Dart fires `onChanged` inside the builder before Navigator.pop — so if the user taps Cancel the onChange was already called. — `notifications_settings_screen.dart:3086-3145` ← `settings_notifications_reactions.cpp:46-87`

- [ ] [CRITICAL] `_ReactionsSubPage._reactionsEnabled` and `_pollVotesEnabled` are tracked as separate booleans but derived from `_reactionsFrom != _ReactionsFrom.none`. When `_persistSettings` is called, it passes `reactionsEnabled: _reactionsFrom != _ReactionsFrom.none` (correctly derived), but `_reactionsEnabled` state variable is only set on toggle, not kept in sync when `_reactionsFrom` changes via the sub-dialog. This means the stored `_reactionsEnabled` field can diverge from `_reactionsFrom`, and reading `_reactionsEnabled` anywhere gives stale data. — `notifications_settings_screen.dart:3004-3070` ← `settings_notifications_reactions.cpp:111-134`

- [ ] [MAJOR] Exception list uses `muteChat(accountId, chatId, false)` to "remove" an exception — this just unmutes the chat but does NOT call Telegram's `account.resetNotifySettings` or `account.updateNotifySettings` (reset to default), which is what `ExceptionsController::rowRightActionClicked` does (`session().data().notifySettings().resetToDefault(row->peer())`). Unmuting is not the same as resetting to default — the peer still has a per-peer override. — `notifications_settings_screen.dart:1865-1869` ← `settings_notifications_type.cpp:254-257`

- [ ] [MAJOR] "Delete all exceptions" calls `muteChat(exc.accountId, exc.chatId, false)` for each exception. AyuGram calls `window->session().data().notifySettings().clearExceptions(type)` — a single batch call that resets all exceptions for a type atomically. The Dart implementation fires N individual muteChat calls, each making a separate API request, which can FLOOD_WAIT and leaves some exceptions partially reset. — `notifications_settings_screen.dart:2092-2098` ← `settings_notifications_type.cpp:620-635`

- [ ] [MAJOR] The "Add an exception" picker in Dart shows a local chat list from `ChatState`, filtered to chats not already in exceptions. AyuGram's `AddExceptionBoxController` extends `ChatsListBoxController` which loads from the full peer list including contacts not in the local chat list, and applies `Data::DefaultNotifyType(peer) != _type` filter plus `!peer->isSelf() && !peer->isRepliesChat() && !peer->isVerifyCodes()` exclusions. The Dart picker does not exclude "Saved Messages", "Replies", or "Verify Codes" chats from the list. — `notifications_settings_screen.dart:1908-2055` ← `settings_notifications_type.cpp:189-199`

- [ ] [MAJOR] Exception row `onTap` fires a context menu (`_showExceptionContextMenu`) instead of row-level mute menu. AyuGram's `ExceptionsController::rowClicked` calls `delegate()->peerListShowRowMenu(row, true)` which opens the MuteMenu directly (full mute/unmute/mute-for options). The Dart context menu only has "View profile", "Mute/Unmute", and "Remove exception" — it does not include "Mute for…" duration picker or the full MuteMenu with recent durations, losing feature parity. — `notifications_settings_screen.dart:2145-2210` ← `settings_notifications_type.cpp:250-321`

- [ ] [MAJOR] The notification preview widget (`_NotificationPreview`) uses a static `_SampleNotificationCard` for the corner hover overlay, while AyuGram renders actual notification samples using `prepareNotificationSampleLarge()` which paints using the actual app logo (`Window::LogoNoMargin()`) and real notification style values (`st::notifyWidth`, `st::notifyMinHeight`, `st::notifyBorderWidth` border). The Dart overlay shows a generic placeholder card with "Uniclient" / "You have a new message" hardcoded text, not scaled to match the actual platform notification size. — `notifications_settings_screen.dart:1071-1131` ← `settings_notifications.cpp:487-524`

- [ ] [MAJOR] The reactions notify settings sub-page (`_ReactionsSubPage`) initializes `_reactionsEnabled=true` and `_pollVotesEnabled=true` as hard defaults before `_loadSettings()` completes asynchronously. AyuGram's `rs.reload()` is called synchronously before any UI is built and the toggles are bound to reactive streams (`rs.messagesFrom()`, `rs.pollVotesFrom()`). In Dart, if the async load is slow or fails (catch swallowed at line 3031), the UI shows wrong defaults and the user sees incorrect toggle states without any indication. — `notifications_settings_screen.dart:3003-3033` ← `settings_notifications_reactions.cpp:261` (`rs.reload()` before UI construction)

- [ ] [MAJOR] Global volume slider (`_VolumeSliderSection`) calls `saveLocalNotifyConfig` with `type: 'global_volume'`, writing to SQLite KV, but this data is never loaded back on screen open — `AppState.notifVolume` is only persisted to SharedPreferences (via `_saveWindowPrefs`), not read from the engine's notify config table. The two storage paths are silently diverged. Additionally AyuGram's volume slider calls `Core::App().notifications().playSound(session, 0, volume/100.)` on every slider change to preview the sound; the Dart implementation at lines 334-348 correctly plays a preview via `_playVolumePreview`, but reads from a local file (`uniclient_msg_incoming.wav`) that may not exist, silently doing nothing if absent. — `notifications_settings_screen.dart:334-348` ← `settings_notifications.cpp:1040-1052`

- [ ] [MAJOR] The `_NotificationTypeSubPage._volume` state is initialized to `100` hardcoded. `_loadDefaultSettings()` fetches `getDefaultNotifySettings` which returns `sound_id` and `sound_name` but the response map is not documented to contain `volume` — and the engine's `GetDefaultNotifySettings` implementation in Go only returns `enabled`, `sound_enabled`, `sound_id`, `sound_name`. So volume is never actually loaded from backend for per-type settings; the slider always starts at 100. — `notifications_settings_screen.dart:1523-1526,1569-1600` ← `settings_notifications_type.cpp:513-528` (volume loaded via `DefaultRingtonesVolumeController(session, type)`)

# payment_panel — Payment Panel Audit

- [ ] [CRITICAL] X button closes panel immediately with no confirmation — AyuGram checks `_form->hasChanges()` and shows a "sure you want to close?" dialog first — `payment_panel.dart:641` ← `payments_checkout_process.cpp:576-581`

- [ ] [CRITICAL] Non-native card entry (URL-based providers) calls `launchUrl(..., externalApplication)` which leaves the app — AyuGram opens the provider URL in an **embedded WebView inside the payment panel** via `showEditCardByUrl` / `createWebview` — `payment_panel.dart:1191` ← `payments_panel.cpp:438-468`

- [ ] [CRITICAL] Native card form has zero input validation — no Luhn check, no card number space-group formatting, no expiry date auto-slash formatting — AyuGram uses `stripe_card_validator.cpp` (Luhn, card-type groups) and `PostprocessCardValidateResult`/`PostprocessExpireDateValidateResult` for real-time formatting — `payment_panel.dart:1229-1306` ← `payments_edit_card.cpp:33-95`

- [ ] [CRITICAL] Shipping address edit opens a single free-text `AlertDialog` — AyuGram routes to `panelEditShippingInformation()` → `showEditInformation(InformationField::ShippingStreet)` which opens a full validated multi-field panel (street1, street2, city, state, country, postcode separately) — `payment_panel.dart:1113-1116` ← `payments_checkout_process.cpp:766-768` + `payments_panel.cpp:279-295`

- [ ] [CRITICAL] Name/Email/Phone each edit in a single `AlertDialog` text box — AyuGram routes each to `panelEditName/Email/Phone()` → `showEditInformation` focused on the specific field with proper masking and validation — `payment_panel.dart:1119-1130` ← `payments_checkout_process.cpp:770-779` + `payments_panel.cpp:279-295`

- [ ] [CRITICAL] Payment validation errors displayed as a generic `_errorText` string — AyuGram maps 10+ specific server codes (REQ_INFO_NAME_INVALID, ADDRESS_STREET_LINE1_INVALID, LOCAL_CARD_NUMBER_INVALID, etc.) to individual field highlights — `payment_panel.dart:363-369` ← `payments_checkout_process.cpp:479-515`

- [ ] [CRITICAL] Submission not blocked when shipping options exist but none is selected — AyuGram at submit-time checks `!options.list.empty() && options.selectedId.isEmpty()` and forces the shipping option chooser before proceeding — `payment_panel.dart:334-344` ← `payments_checkout_process.cpp:645-646`

- [ ] [MAJOR] Bot trust warning shown unconditionally before the first submission attempt (client-side) — AyuGram only shows it when a `BotTrustRequired` event fires from the form layer (server-driven); showing it upfront is both incorrect timing and may trigger it for bots that don't require it — `payment_panel.dart:270-296` ← `payments_checkout_process.cpp:410-413`

- [ ] [MAJOR] Product thumbnail downloaded via raw `dart:io` `HttpClient` bypassing the engine — AyuGram loads it through `Form::loadThumbnail()` → `photo->load(Data::PhotoSize::Thumbnail)` using the data layer (blurred preview first, then full quality via `ThumbnailUpdated` event) — `payment_panel.dart:1739-1763` ← `payments_form.cpp:281-309`

- [ ] [MAJOR] Custom tip dialog uses `int.tryParse` so decimal input ("5.00") silently fails and sets no tip — AyuGram uses a money `Field` that accepts decimal values and converts them correctly — `payment_panel.dart:1597` ← `payments_panel.cpp:387-424`

- [ ] [MAJOR] When custom tip exceeds `_maxTip`, input is silently discarded with no feedback — AyuGram shows an animated `errorWrap` label "Max tip: X" — `payment_panel.dart:1603-1606` ← `payments_panel.cpp:409-414`

# peer_short_info — Audit

## peer_short_info — Cover scroll, video bar, open-chat wiring, loader size, phone format, photo preload

- [ ] [CRITICAL] "Send Message" / "View Group" / "View Channel" button silently does nothing when the chat is not present in `chatState.chats` — `chatState.chats.where(...).firstOrNull` returns null and `openChat` is never called. AyuGram always fires `_openRequests` and the caller handles navigation via `window->showPeerHistory(peer)` which does not require the chat to be cached locally. — `peer_short_info.dart:1146-1151` ← `boxes/peers/prepare_short_info_box.cpp:483`

- [ ] [CRITICAL] `_videoProgress` is initialized to `1.0` (line 130) and is not reset when the video player is created. While the video is loading (between `player.open()` and the first position stream event), the photo progress bar for the active frame renders at 100% fill instead of 0%. AyuGram explicitly renders 0 progress when `_videoInstance` exists but `_videoDuration == 0`: `progress = (_videoInstance ? 0. : 1.)`. — `peer_short_info.dart:130` ← `boxes/peers/peer_short_info_box.cpp:299`

- [ ] [MAJOR] Cover background scrolls at `_kParallaxFactor = 0.3` (i.e. 30% of scroll speed) via `Positioned(top: -scrollOffset * _kParallaxFactor)`. AyuGram has no parallax: the cover widget is an ordinary child of the vertical layout inside the scroll area and moves 1:1 with the content. The Dart's parallax layer makes the photo appear to "stick" as the info rows scroll up — a visible behavioral departure from the spec. — `peer_short_info.dart:478` ← `boxes/peers/peer_short_info_box.cpp:217-259`

- [ ] [MAJOR] Circular loading indicator on the cover is 24×24 px (`SizedBox(width: 24, height: 24)`). AyuGram uses `boxLoadingSize = 20px` for the radial animation rect in `PeerShortInfoCover::radialRect()`. Both the cover radial and the info-rows spinner are 24px in Dart. — `peer_short_info.dart:771-772` ← `lib_ui/ui/layers/layers.style:146`

- [ ] [MAJOR] Phone number is only prefixed with `'+'` if missing (`_formatPhone`) with no regional grouping or separators. AyuGram calls `Ui::FormatPhone(user->phone())` which renders the number with proper international spacing (e.g. `+1 234 567-8901`). — `peer_short_info.dart:1088-1091` ← `boxes/peers/prepare_short_info_box.cpp:228`

- [ ] [MAJOR] No adjacent-photo preloading. AyuGram's `Preload()` fetches the previous and next photo in the user's photo history before the user navigates, so photo transitions are instant. The Dart calls `engine.getUserPhotoAtIndex` on demand with a `_photoLoading` spinner visible every navigation step. — `peer_short_info.dart:358-370` ← `boxes/peers/prepare_short_info_box.cpp:112-145`

## photo_crop_editor — Dart vs AyuGram Desktop audit

### CRITICAL

- [ ] [CRITICAL] Paint button in paint-mode control bar has `onPressed: () {}` stub — button does nothing when tapped — `photo_crop_editor.dart:2601` ← `editor/photo_editor_controls.cpp:305` (`_paintModeButtonActive` is display-only / `WA_TransparentForMouseEvents`; in Dart the active-paint icon button should be inert/display-only, not a stub with `() {}`. Current code is misleading and leaves the button silently dead with no visual distinction from a real button)

- [ ] [CRITICAL] Tool buttons use static `Icon` widgets (Flutter `Icons.*`) instead of Lottie animated `.tgs` icons — AyuGram uses `ToolLottieButton` backed by `photo_editor_pen.tgs`, `photo_editor_arrow.tgs`, `photo_editor_marker.tgs`, `photo_editor_blur.tgs`, `photo_editor_eraser.tgs` with hover-play animation — `photo_crop_editor.dart:3057-3062` ← `editor/color_picker.cpp:332-346`

- [ ] [CRITICAL] `_kToolButtonSize = 36.0` — AyuGram specifies `photoEditorToolButtonSize: 20px` (the icon/hit area is 20px + 8px extra = 28px total, not 36px) — `photo_crop_editor.dart:111` ← `editor/editor.style:136,145`

- [ ] [CRITICAL] Brush stroke rendering uses simple `lineTo` path — AyuGram uses quadratic bezier smoothing with pressure (`quadTo` on midpoints via `scene_item_canvas.cpp:175`) and `kInvStrength`/`kHalfStrength` smoothing pass — `photo_crop_editor.dart:2166-2173` ← `editor/scene/scene_item_canvas.cpp:96-118, 175`

### MAJOR

- [ ] [MAJOR] `_ToolBrush` default `sizeRatio = 0.125` — AyuGram defaults `kDefaultBrushSizeRatio = 0.9` (very different; initial brush size is nearly full-range in AyuGram, minuscule in Dart) — `photo_crop_editor.dart:130` ← `editor/photo_editor.cpp:26, 74`

- [ ] [MAJOR] `_kToolSelectDuration = Duration(milliseconds: 200)` — AyuGram specifies `photoEditorToolButtonSelectDuration: 120` (ms) — `photo_crop_editor.dart:112` ← `editor/editor.style:140`

- [ ] [MAJOR] Blur stroke uses `sigmaX/Y = stroke.width * 0.8` as blur radius — AyuGram uses a fixed `photoEditorBlurRadius: 20` for the image blur, with the stroke width scaled by `photoEditorBlurSizeMultiplier: 3.0` controlling brush size only, not sigma — `photo_crop_editor.dart:103, 2242-2243` ← `editor/editor.style:153,155`, `editor/scene/scene.cpp:251-253`

- [ ] [MAJOR] `_RainbowColorButton` size is `_kRainbowRingSize = 28.0` — AyuGram uses `photoEditorColorButtonSize: 24px` — `photo_crop_editor.dart:109, 3287-3288` ← `editor/editor.style:126`

- [ ] [MAJOR] Tool selection indicator slide animation uses `Curves.easeOutCirc` on a 200ms controller — AyuGram uses `anim::easeOutCirc` on 120ms (`photoEditorToolButtonSelectDuration`) — `photo_crop_editor.dart:112, 3121` ← `editor/color_picker.cpp:545`, `editor/editor.style:140`

- [ ] [MAJOR] Tool button gap in `_PaintToolRow` is `4.0` px implicit (via `Padding(horizontal: 2)`) — AyuGram uses `photoEditorToolButtonGap: 18px` between color button and tools — `photo_crop_editor.dart:3110-3148` ← `editor/editor.style:138`, `editor/color_picker.cpp:481-488`

- [ ] [MAJOR] `_kPaletteItemSize = 20.0` matches AyuGram, but palette buttons render as `Container` with flat `color` fill — AyuGram uses `Ui::ColorSample` with `setSelectionCutout(true)` (inner-ring selection indicator) — `photo_crop_editor.dart:2993-3006` ← `editor/color_picker.cpp:713-733`

- [ ] [MAJOR] Custom-color "plus" button is `Icon(Icons.add, size: 14)` inside a plain circle border — AyuGram renders a `PlusCircle` with `st::photoEditorColorPalettePlusLine = 2px` lines using round cap style — `photo_crop_editor.dart:3013-3026` ← `editor/color_picker.cpp:79-108`

- [ ] [MAJOR] Sticker panel opens as `showModalBottomSheet` — AyuGram uses a floating `StickersPanelController` positioned near the stickers button (not a bottom sheet) with `ShowRequest::ToggleAnimated` — `photo_crop_editor.dart:710-728` ← `editor/photo_editor_controls.cpp:443-468`

- [ ] [MAJOR] `_kColorButtonSwitchDuration = Duration(milliseconds: 140)` matches AyuGram's `kColorButtonSwitchDuration = 140`, but the rainbow ring button uses `AnimatedContainer` which does not animate the inner fill color between old and new values — AyuGram uses `anim::color()` lerp with `_colorButtonAnimation` — `photo_crop_editor.dart:3285-3304` ← `editor/color_picker.cpp:592-619`

- [ ] [MAJOR] `_PaintTopBar` (undo/redo row) renders undo/redo on opposite ends of the full bar width with `const Spacer()` — AyuGram positions `_paintTopButtons` above `_paintBottomButtons` at the same horizontal center, separated by `photoEditorControlsCenterSkip: 6px` — `photo_crop_editor.dart:2940-2965` ← `editor/photo_editor_controls.cpp:375-382`

- [ ] [MAJOR] Tool selection indicator pill in `_PaintToolRow` is a `Container(color: Color(0x33FFFFFF), shape: BoxShape.circle)` Positioned absolutely — AyuGram uses a separate `_toolSelection` RpWidget with `paintOn` drawing an ellipse at `photoEditorToolButtonSelectedOpacity: 0.35` opacity — `photo_crop_editor.dart:3126-3137` ← `editor/color_picker.cpp:313-330`

### MINOR

- [ ] [MINOR] `_kPaletteGap = 6.0` matches `photoEditorColorPaletteGap: 6px` — correct — `photo_crop_editor.dart:71` ← `editor/editor.style:130`

- [ ] [MINOR] `_kControlBarHeight = 48` matches `photoEditorButtonBarHeight: 48px` — correct — `photo_crop_editor.dart:32` ← `editor/editor.style:37`

- [ ] [MINOR] `_kControlBarWidth = 422` matches `photoEditorButtonBarWidth: 422px` — correct — `photo_crop_editor.dart:33` ← `editor/editor.style:38`

- [ ] [MINOR] `_kCropHandleSize = 10.0` matches `photoEditorCropPointSize: 10px` — correct — `photo_crop_editor.dart:50` ← `editor/editor.style:166`

- [ ] [MINOR] `_kBrushSizeControlHeight = 280.0` matches `photoEditorBrushSizeControlHeight: 280px` — correct — `photo_crop_editor.dart:81` ← `editor/editor.style:158`

- [ ] [MINOR] `_kContentMarginBottom = 146` matches `photoEditorControlsHeight: 146px` comment — correct — `photo_crop_editor.dart:20` ← `editor/editor.style:16`

- [ ] [MINOR] `_kMarkerOpacity = 0.35` matches `photoEditorMarkerOpacity: 0.35` — correct — `photo_crop_editor.dart:77` ← `editor/editor.style:147`

- [ ] [MINOR] `_kMarkerSizeMultiplier = 2.5` matches `photoEditorMarkerSizeMultiplier: 2.5` — correct — `photo_crop_editor.dart:78` ← `editor/editor.style:148`

- [ ] [MINOR] `_kArrowHeadLengthFactor = 2.5` matches `photoEditorArrowHeadLengthFactor: 2.5` — correct — `photo_crop_editor.dart:75` ← `editor/editor.style:149`

- [ ] [MINOR] `_kArrowHeadAngleDeg = 26.0` matches `photoEditorArrowHeadAngleDegrees: 26` — correct — `photo_crop_editor.dart:74` ← `editor/editor.style:151`

- [ ] [MINOR] `_EditorStickerPicker` has hardcoded 4 emoji group rows of 24 emojis — sticker tab uses `engine.getInstalledStickerPacks()` which is correct backend wiring, but emoji tab is hardcoded (acceptable since emoji is static content, not server-driven) — `photo_crop_editor.dart:3368-3378`

- [ ] [MINOR] Crop export writes output to `/tmp/crop_<timestamp>.png` — file is not cleaned up after being sent to callback — potential accumulation of temp files — `photo_crop_editor.dart:1047-1051`

- [ ] [MINOR] `EmojiAvatarBuilder` export writes to `/tmp/emoji_avatar_<timestamp>.png` — same cleanup issue — `photo_crop_editor.dart:3923-3927`

- [ ] [MINOR] `_kPlusCircleSize = 20.0` used for the custom-color plus button — AyuGram's `PlusCircle` is sized to `st::photoEditorColorPaletteItemSize = 20px` — matches — `photo_crop_editor.dart:114` ← `editor/editor.style:129`

# popup_menu — Context menu / popup menu widget

- [ ] [MAJOR] Light-mode shortcut hover color is `0xFF888888` but AyuGram uses `windowSubTextFgOver = #919191` — `popup_menu.dart:868` ← `lib_ui/ui/colors.palette:15` + `lib_ui/ui/widgets/widgets.style:979`

- [ ] [MAJOR] Submenu always opens to the right regardless of locale; AyuGram explicitly checks `style::RightToLeft()` and flips submenu to the left side when in RTL mode — `popup_menu.dart:578` ← `lib_ui/ui/widgets/popup_menu.cpp:927-936`

## privacy_settings_screen — Privacy & Security settings screen audit

- [ ] [CRITICAL] "Active Web Sessions (Logged-in Websites)" button is entirely missing from the Security section — AyuGram shows it whenever `websites().totalValue() > 0`, with a count label; the Dart file has no `getWebsites`/`getWebsiteCount` call, no websites screen navigation, and no websites entry in the security section — `privacy_settings_screen.dart:994-1012` ← `settings_privacy_security.cpp:765-784`

- [ ] [CRITICAL] "Disable Sensitive Content Filtering" toggle is completely absent — AyuGram calls `SetupSensitiveContent` which shows a toggle for `sensitiveContent().enabled()` gated on `canChange()`; the Dart file has zero references to sensitive content anywhere — `privacy_settings_screen.dart:552-610` ← `settings_privacy_security.cpp:258-314`

- [ ] [CRITICAL] `onSaved` callback after editing a privacy rule does NOT update `always_users`/`never_users` counts in `_privacySettings` — the map is merged with only `{'option': newOption}`, so `_privacyLabel()` immediately shows stale exception counts (e.g. "+3, -1" vanishes) until the next 15-second poll — `privacy_settings_screen.dart:819-838` ← `settings_privacy_security.cpp:124-144`

- [ ] [CRITICAL] `_PrivacyExceptionPicker` only shows contacts — AyuGram's `EditPrivacyBox` lets users search and add any user/group/channel by username or peer search, not just contacts; entering a non-contact username to whitelist/blacklist is impossible in the Dart implementation — `privacy_settings_screen.dart:7055-7267` ← `settings_privacy_controllers.cpp`

- [ ] [MAJOR] Archive-and-mute section is missing the two premium-gated sub-toggles: "Keep Archived Unmuted" and "Keep Archived in Folders" — the fields `_archiveKeepUnmuted` and `_archiveKeepFolders` are fetched and sent to the engine but never rendered as toggles in `_buildArchiveAndMuteSection` — `privacy_settings_screen.dart:946-992` ← `settings_privacy_security.cpp:981-1023`

- [ ] [MAJOR] `_GlobalTTLScreen` missing "Apply to existing chats" link — AyuGram's `BuildApplyToExisting` adds a footer link that opens a chat-list picker allowing the user to bulk-apply the new TTL to selected chats; the Dart screen has no equivalent — `privacy_settings_screen.dart:4932-5135` ← `settings_global_ttl.cpp:401-464`

- [ ] [MAJOR] Local passcode stored as a plain SHA-256 hash on disk with no per-device salt — AyuGram uses `domain.local().setPasscode()` which applies OS-level domain storage with multiple passes; the Dart implementation writes `{hash: sha256(passcode)}` to a plain JSON file in configDir, making it trivially brute-forceable from the filesystem — `privacy_settings_screen.dart:5340-5343`

- [ ] [MAJOR] `_LocalPasscodeManage._changePasscode()` pushes a new `_LocalPasscodeCreate` screen instead of the correct "Change Passcode" flow — it does not first verify the current passcode before allowing creation of a new one, unlike AyuGram which uses `LocalPasscodeChange` (which re-checks the old passcode first) — `privacy_settings_screen.dart:5798-5808` ← `settings_local_passcode.cpp:379-383`

- [ ] [MAJOR] `CloudPasswordStart` intro screen has three consecutive empty `SizedBox(height: 61)` spacers and no body content between the subtitle and the "Set Password" button — the equivalent AyuGram screen (`settings_cloud_password_start`) shows a lottie animation, an explanation paragraph, and a link to "Learn more"; this looks broken — `privacy_settings_screen.dart:3127-3131`

- [ ] [MAJOR] `_buildBotsAndWebsitesSection` section title is missing — AyuGram renders a "Bots & Websites" subsection title above "Clear Payment and Shipping Info"; the Dart section has no heading, causing the row to appear headingless between sections — `privacy_settings_screen.dart:994-1012` ← `settings_privacy_security.cpp:1026-1049`

- [ ] [MAJOR] Birthday picker in the privacy editor uses `showDatePicker` (a generic Flutter date picker) instead of a day/month only picker — Telegram birthday privacy does not include a year, but the Dart code saves full `picked.day, picked.month, picked.year` via `engine.updateBirthday` — this sends the birth year to the server unnecessarily and is inconsistent with the AyuGram privacy controller which works with a `Data::Birthday{.day, .month}` without year — `privacy_settings_screen.dart:2093-2115` ← `settings_privacy_controllers.cpp`

- [ ] [MAJOR] Privacy exception picker (always/never lists) only persists user IDs from contacts; it cannot accept group or channel exceptions — AyuGram's `ExceptionUsersCount` counts all peer types including chats and channels, and the UI lets users add groups/channels to exception lists; the Dart picker has no concept of chat/channel exceptions and the `_alwaysUsers`/`_neverUsers` lists hold only string user IDs — `privacy_settings_screen.dart:1968-1995, 2176-2196` ← `settings_privacy_security.cpp:316-326`

# reactions_detail — Reactions & Read-Receipt Detail Panel

- [ ] [MAJOR] `_loadMore()` appends paginated reactors without deduplication — `dart/lib/ui/reactions_detail.dart:310,314` (`_masterReactors.addAll(result.reactors)` / `_allReactors.addAll(result.reactors)`) ← `AyuGram/history/view/reactions/history_view_reactions_list.cpp:428-433` (`Controller::appendRow` calls `peerListFindRow(id(peer,reaction))` and returns false on dup). If the reaction list changes mid-scroll (users add/remove reactions between pages), the offset-based pagination can return a previously seen peer; AyuGram's explicit dedup prevents duplicate rows, the Dart has none.

- [ ] [MAJOR] `_filteredReactors` getter is a computed property (lines 332-343) called at minimum N+1 times per `build()` frame: once in `itemCount: _filteredReactors.length` (line 523) and once per `itemBuilder` index (line 532), each call invoking `.where().toList()` — `dart/lib/ui/reactions_detail.dart:332,523,532` ← `AyuGram/history/view/reactions/history_view_reactions_list.cpp:260-280` (AyuGram computes the filtered list once per `showReaction()` call and stores it in `_filtered`). Dart creates N+1 new list objects per render pass; the result should be assigned once at the top of `build()` or cached as a state field updated in `setState()`.

# send_files_box — Audit Findings

## send_files_box — Missing AI Caption Button

- [ ] [CRITICAL] No AI caption assistance button in the send files dialog. AyuGram sets up a `ComposeAiButton` alongside the caption field (`_aiButton = Ui::SetupCaptionAiButton(...)`) and updates its geometry reactively. The Dart file has no equivalent AI caption button anywhere in the build tree. — `send_files_box.dart:1879` ← `AyuGram/boxes/send_files_box.cpp:1913`

## send_files_box — Caption "above" is a checkbox, not send-menu-only state

- [ ] [MAJOR] The `_captionAbove` state (whether caption is above media) is exposed as a standalone `_CheckboxRow` widget in the footer area. In AyuGram it is not a checkbox at all — it is exclusively controlled via the send-menu (`CaptionDown`/`CaptionUp` action types), driven by `_invertCaption` and surfaced only as a menu item. The Dart implementation exposes this as a persistent visible checkbox, which is wrong behavior. — `send_files_box.dart:1941-1948` ← `AyuGram/boxes/send_files_box.cpp:757-759`

## send_files_box — validateLength does not show premium upgrade box

- [ ] [CRITICAL] When the caption exceeds the character limit, AyuGram shows a `CaptionLimitReachedBox` that offers premium upgrade (`_show->showBox(Box(CaptionLimitReachedBox, session, remove, &_st.premium))`). The Dart `_send()` merely does an early return (`if (_captionController.text.length > _kCaptionMaxLength) return;`) with no user-facing error box. The user gets no feedback and no upgrade prompt. — `send_files_box.dart:1358` ← `AyuGram/boxes/send_files_box.cpp:2348-2357`

## send_files_box — Premium-aware caption character limit not used

- [ ] [MAJOR] AyuGram's character limit for captions is dynamic: it reads `Data::PremiumLimits(&session).captionLengthCurrent()` and computes `remove = text.size() - limit` to display the correct remaining count. The Dart file hardcodes `_kCaptionMaxLength = 4096` and `_kCaptionWarnThreshold = 3900` as constants with no premium awareness. Premium users who have a higher limit will be incorrectly blocked or warned too early. — `send_files_box.dart:21-22` ← `AyuGram/boxes/send_files_box.cpp:1979-1981`

## send_files_box — `checkWithWay` / permission check completely missing

- [ ] [CRITICAL] AyuGram validates that the current send way is permissible for the peer before allowing "Group files" and "Send as documents" toggles — using `checkWithWay(sendWay)` which calls `_check(file, compress, silent)` (the `SendFilesCheck` callback from `DefaultCheckForPeer`). If the check fails, the checkbox is reverted. The Dart file applies the toggle unconditionally with `setState(() => _sendAsDocuments = v)` / `setState(() => _groupFiles = v)`, never checking peer restrictions. — `send_files_box.dart:1929,1939` ← `AyuGram/boxes/send_files_box.cpp:1749-1775`

## send_files_box — Reply header is a plain static widget, not animated ReplyPillHeader

- [ ] [MAJOR] AyuGram uses a dedicated `SendFiles::ReplyPillHeader` widget (with hide animation, close button, dynamic height, and spoiler preview) sourced from the live history item. The Dart implementation renders a static `Container` with hardcoded `Icon(Icons.reply)` and plain text — no close button, no animation, no resolve of the actual message data. — `send_files_box.dart:1639-1681` ← `AyuGram/boxes/send_files_box_reply_header.h:31-75`

## send_files_box — DivideByGroups / PrepareFilesBundle not implemented; caption assignment is wrong

- [ ] [CRITICAL] In AyuGram, `send()` calls `DivideByGroups(std::move(_list), way, ...)` then `PrepareFilesBundle(...)` to correctly split files into send groups, then assigns the main caption to the last file in the last album group. The Dart `_send()` skips this entirely — it passes `paths` as a flat list with a single `caption` field and no group/album structure. The caller (compose box) receives no `PreparedBundle` equivalent, so album grouping and per-group caption placement is never enforced at the bundle level. — `send_files_box.dart:1376-1393` ← `AyuGram/boxes/send_files_box.cpp:2426-2449`

## send_files_box — saveSendWaySettings not called on send

- [ ] [MAJOR] AyuGram persists the user's send way preferences when confirmed: `saveSendWaySettings(_wayRemember && _wayRemember->checked())`. This writes to `Core::App().settings().setSendFilesWay(way)` and calls `saveSettingsDelayed()`. The Dart `_send()` reads `_wayRemember` flag but never persists the send way back to app settings; the result is only forwarded in `SendFilesResult.remember` to the caller, which is only advisory. — `send_files_box.dart:1384` ← `AyuGram/boxes/send_files_box.cpp:2411`

## send_files_box — `_canMoveCaption` check is weaker than AyuGram's

- [ ] [MAJOR] AyuGram's `canMoveCaption` gate checks `_list.canMoveCaption(way.groupFiles() && way.sendImagesAsPhotos(), way.sendImagesAsPhotos())`, which accounts for the send way combination. The Dart getter `_canMoveCaption` only checks `!_sendAsDocuments && _captionController.text.isNotEmpty && _files.any((f) => f.isMediaType)`, missing the groupFiles dimension and the proper sendImagesAsPhotos coupling. — `send_files_box.dart:625-628` ← `AyuGram/boxes/send_files_box.cpp:732-735`

## send_files_box — Photo editor hint label shown based on counter, not session setting

- [ ] [MAJOR] AyuGram shows the "click to open in photo editor" hint label only when `_show->session().settings().photoEditorHintShown()` returns true (counter-based) and `_list.canHaveEditorHintLabel()` returns true. The Dart shows the hint based on `_photoEditorHintShown` which is set when any file is replaced via the editor, which is the wrong trigger — it should display when the session counter crosses the threshold, not only after the user has already used the editor. — `send_files_box.dart:1731-1738` ← `AyuGram/boxes/send_files_box.cpp:1831-1834`

## send_files_box — `_showTopMenu` (top-right "..." button) duplicates send-menu items incorrectly

- [ ] [MAJOR] The top-right `_TopMenuButton` in the Dart opens `_showTopMenu`, which re-implements its own list of items (quality, spoiler, sticker). In AyuGram the top button opens the same `SendMenu::FillSendMenu` as the send button — with the full menu including CaptionUp/Down and PhotoQuality toggled correctly via `_sendMenuCallback`. The Dart's top menu duplicates quality/spoiler toggle logic in a second code path without the `CaptionDown/Up` items, and misses the sticker conversion that AyuGram does (converting image to WEBP before sending). — `send_files_box.dart:1317-1351` ← `AyuGram/boxes/send_files_box.cpp:1168-1219`

## send_files_box — Send as sticker converts image to WEBP; Dart omits conversion

- [ ] [CRITICAL] In AyuGram, "Send as sticker" converts the image data to WEBP format in-memory (`sourceImage->data.save(&buffer, "WEBP")`) and calls `addFiles(Storage::PrepareMediaFromImage(...))` with the converted bytes before sending. The Dart `_sendAsSticker()` simply calls `_send(asSticker: true)` and passes the original file path unchanged. No WEBP conversion happens; the file remains whatever format it was. — `send_files_box.dart:1353-1355` ← `AyuGram/boxes/send_files_box.cpp:1192-1213`

## send_files_box — File drag-and-drop between document blocks uses desktop_drop not internal QDrag

- [ ] [MAJOR] AyuGram implements file reordering for document blocks via `setupDragForBlock` using a custom `application/x-tg-sendfile-index` MIME type and `QDrag`, restricting drops to only blocks where `isFileBlock(from) && isFileBlock(index)` (files/music, not media). The Dart's `_FileListPreview` uses Flutter's `LongPressDraggable<int>` / `DragTarget<int>` accepting any index without the `isFileBlock` restriction, meaning media items can be reordered with the file drag system when they should be handled by album reorder. — `send_files_box.dart:3317-3330` ← `AyuGram/boxes/send_files_box.cpp:2484-2549`

## send_files_box — `canBeSentInSlowmode` check missing when adding files

- [ ] [MAJOR] AyuGram's `addFile()` checks `_list.canBeSentInSlowmode()` after appending each file and removes it if the slow-mode constraint is violated. The Dart `_addMoreFiles()` and `_addDroppedFiles()` only gate at the UI level with a toast if `isSlowMode && _files.isNotEmpty`, but do not individually validate each file against the slow-mode rule after addition — a race condition could allow extra files to accumulate in the list. — `send_files_box.dart:1191-1250` ← `AyuGram/boxes/send_files_box.cpp:2150-2166`

## send_files_box — Emoji panel uses EmojiTabbedPanel (full panel); AyuGram uses EmojiOnly-mode TabbedPanel

- [ ] [MAJOR] AyuGram sets up the emoji panel with `TabbedSelector::Mode::EmojiOnly` and `features.stickersSettings = false` / `features.openStickerSets = false`. The Dart uses `EmojiTabbedPanel` from `emoji_panel.dart` which is the full tabbed emoji+sticker panel (also used in the compose bar). This makes the send-files emoji panel heavier and inconsistent with the AyuGram source. — `send_files_box.dart:1895-1917` ← `AyuGram/boxes/send_files_box.cpp:2003-2051`

## send_files_box — Caption field does not drop files via MimeData hook

- [ ] [MAJOR] In AyuGram, the caption `InputField` has a `setMimeDataHook` that intercepts paste/drop events on the field itself: if the dropped data contains local files or an image, it calls `addFiles(data)` to add them to the list. The Dart caption `TextField` has no equivalent hook — dropping files onto the caption area does not add them to the file list, only the outer `DropTarget` handles drops. — `send_files_box.dart:1862-1876` ← `AyuGram/boxes/send_files_box.cpp:1892-1901`

## send_files_box — `_showEditCaptionDialog` / `_editFileCaption` use AlertDialog not styled box

- [ ] [MAJOR] Per-file caption editing in AyuGram opens a proper `EditFileCaptionBox` that uses `Ui::InputField` with `InitMessageFieldHandlers`, session-aware emoji, and `SetupCaptionAiButton`. The Dart uses a plain `AlertDialog` with a bare `TextField` — no custom emoji support, no AI button, no markdown field handlers, and no styled format matching the desktop design. — `send_files_box.dart:729-789` ← `AyuGram/boxes/send_files_box.cpp:180-258`

## send_files_box — `_showEditPriceDialog` uses AlertDialog; AyuGram uses EditPriceBox with star icon

- [ ] [MAJOR] AyuGram's "Set price" flow opens `EditPriceBox` which renders a `NumberInput` widget, paints a star icon at a specific position (`st::paidStarIcon.paint` at `st::paidStarIconTop`), includes an about-link label, and enforces a server-side `stars_paid_post_amount_max` limit. The Dart uses an `AlertDialog` with a plain `TextField` and a hardcoded `⭐` prefix text, ignoring server limits entirely. — `send_files_box.dart:1459-1492` ← `AyuGram/boxes/send_files_box.cpp:260-335`

## send_files_box — Autocomplete uses local `members` list; should use `FieldAutocomplete` with peer session

- [ ] [CRITICAL] AyuGram sets up caption autocomplete via `setupCaptionAutocomplete()` which calls `ChatHelpers::InitFieldAutocomplete` binding to the actual `_toPeer` for both mentions and hashtags via the session. The Dart implements its own `_detectMentionQuery()` / `_detectHashtagQuery()` that scan a `List<MemberInfo>` passed in at construction time and a static in-memory `RecentHashtags` list. This means (a) the mention list is stale (not updated from engine), (b) hashtag suggestions are session-local and not synced with Telegram's server-side recent hashtags, and (c) commands and other autocomplete features supported by `FieldAutocomplete` are absent. — `send_files_box.dart:417-505` ← `AyuGram/boxes/send_files_box.cpp:1922-1969`

## send_files_box — `_SpoilerOverlay` uses `BackdropFilter` blur; AyuGram uses Lottie-particle animation

- [ ] [MAJOR] AyuGram spoiler overlays use `SpoilerAnimation` (Lottie-based particle animation distinct from a simple CSS-style blur). The Dart `_SpoilerOverlay` uses `BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24))` with a custom `CustomPainter` for particles. While visually similar, the blur-based approach is heavier on GPU compositing (forces offscreen layer for every spoilered thumbnail), and the animation is not the correct Lottie-backed particle system. — `send_files_box.dart:3587-3659` ← `AyuGram/boxes/send_files_box.h:64` (uses `Ui::SpoilerAnimation`)

# settings_screen — Audit

- [ ] [CRITICAL] `setEmojiStatus` and `clearEmojiStatus` call Go bridge methods that don't exist — `AccountUpdateEmojiStatus` is explicitly skipped in dispatch_gen.go; emoji status picker renders and accepts input but the API call silently fails every time — `settings_screen.dart:1180,1214` ← `go/bridge/dispatch_gen.go:19079` (`// Skipped: AccountUpdateEmojiStatus`)

- [ ] [CRITICAL] `setEmojiStatus` passes `item.fileId` (a document ID string) as the `emoji` parameter — even if the backend were implemented, the payload would send `{"emoji": "5123456789"}` (a file ID) instead of a custom emoji document reference; parameter semantics are wrong — `settings_screen.dart:1180` ← `dart/lib/bridge/engine_service.dart:3827` (`String emoji`)

- [ ] [MAJOR] Video/camera device selection not persisted to backend — `_selectedCamera` state update calls only `setState()` with no `engine.setCallAudioDevice(accountId, 'camera', dev)` call; audio output/input devices at lines 2256/2267 DO call the engine, camera does not — `settings_screen.dart:2310-2313` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_calls.cpp:776` (`Core::App().settings().setCameraDeviceId(id)`)

- [ ] [MAJOR] "Use same device for calls" toggle not persisted — toggling `_sameDevice` only calls `setState()`; no engine call to clear/set device IDs; in AyuGram toggling this clears `callPlaybackDeviceId`/`callCaptureDeviceId` and immediately calls `Core::App().saveSettingsDelayed()` — `settings_screen.dart:2272-2289` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_calls.cpp:255-275`

- [ ] [MAJOR] Business Hours editor is a read-only stub — hours display as static text with hardcoded fallback `'9:00 - 18:00'`; no time picker, no edit tap target, no way to change per-day hours; AyuGram treats `BusinessHours` as a full interactive section (`PremiumFeature::BusinessHours`) — `settings_screen.dart:3074-3086` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_business.cpp:118`

- [ ] [MAJOR] Premium features screen silently falls back to a hardcoded list of 21 features when `getPremiumFeatures()` fails or returns empty — backend errors are invisible and the displayed features may not match what the user's account actually supports — `settings_screen.dart:2461-2484` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_premium.cpp` (dynamic feature list from API)

- [ ] [MAJOR] Quick replies list has no delete/remove control — individual quick reply items render as read-only rows; AyuGram uses `messages.DeleteQuickReplyShortcut` (TL method); Go bridge has the method but Dart UI never calls it — `settings_screen.dart:3156-3173` ← `AyuGramDesktop/Telegram/SourceFiles/data/business/data_shortcut_messages.cpp:579`

- [ ] [MAJOR] Business chat links list has no revoke/delete control — link rows show only a copy button; Go bridge has `AccountDeleteBusinessChatLink` at dispatch_gen.go:18686 but it is never exposed in engine_service.dart or called from the UI — `settings_screen.dart:3326-3350` ← `go/bridge/dispatch_gen.go:18686`

# shell — Shell layout, connection state, call bar wiring

- [ ] [CRITICAL] Personal call hangup does not call engine — `onHangup: () => chatState.setActivePersonalCall(null)` only clears local state; the Go engine never receives a hang-up command and keeps the call alive in the background. Group call correctly calls `engine.endCall(accountId, callId)` but personal call has no equivalent — `shell.dart:348` ← `calls/calls_top_bar.cpp:271` (`tr::lng_call_bar_hangup` wired to `hangup()` which calls `_call->hangup()`)

- [ ] [CRITICAL] Personal call mute toggle does not call engine — `onToggleMute: () { chatState.setActivePersonalCall(personalCall.copyWith(isMuted: !personalCall.isMuted)) }` only mutates local Dart state; `engine.setCallMuted()` is never invoked, so the actual call audio stream is unaffected — `shell.dart:350-353` ← `calls/calls_top_bar.cpp:727` (`TopBar::setMuted` wired to real call mute)

- [ ] [MAJOR] Connection widget tap opens proxy dialog instead of refreshing state — `onTap: () => showProxiesDialog(context)` (line 1147) opens the proxy settings screen. In AyuGram the widget is an `AbstractButton`; pressing it fires `_refreshStateRequests` which calls `refreshState()` to re-poll the network manager — no proxy dialog is opened — `shell.dart:1147` ← `window/window_connecting_widget.cpp:518-523`

- [ ] [MAJOR] Group call self-muted detection compares wrong identifiers — `p.userId == accountId` (line 358) compares a participant's Telegram user-ID string against `chatState.activeChat?.accountId` which is the internal account/session identifier (e.g. the engine-side account handle), not the platform user ID. `AccountInfo` has a separate `selfUserId` field for this purpose; the comparison will never match so `selfMuted` is always `false`, causing the mute button to always show the unmuted icon — `shell.dart:357-358` ← `calls/calls_top_bar.cpp` (self-participant identified by user peer matching, not session handle)

- [ ] [MAJOR] `_InfoLayerOverlay` in two-column mode covers the dialogs column — the dim overlay is stacked over the entire `_buildTwoColumn` widget tree (lines 558-563), so the dialogs column is dimmed and tapping it closes the info panel. In AyuGram, the info section is shown as a `LayerWidget` (`Wrap::Layer`) which is positioned only over the chat/right portion of the window; the dialogs column remains interactive and does not dismiss the layer — `shell.dart:558-563` ← `info/info_layer_widget.cpp:255` (`resizeGetHeight` scopes layer to chat area width), `mainwidget.cpp:1831-1836` (layer shown via `showSpecialLayer`, not full-screen overlay)

# shortcuts_settings_screen — Keyboard Shortcuts Settings

- [ ] [MAJOR] `_isModified` getter called directly inside `build()` on every rebuild — it allocates a full `defaultByCmd` map, iterates all 50+ `ShortcutCommand.values`, calls `ShortcutSystem.defaultBindingsList` (which wraps a `List.unmodifiable` each call), and sorts per-command lists. During recording, every key event triggers `setState` → rebuild → this full O(n) scan. Should be a cached `bool _modified` field updated only in `_assignBinding`, `_clearBinding`, `_resetToDefaults`, and `_loadBindings`. — `shortcuts_settings_screen.dart:376` ← `settings/sections/settings_shortcuts.cpp:198-210` (`checkModified` is called only on mutation, not on every paint)

- [ ] [MAJOR] `_startRecording` calls `_removedKeys.clear()` unconditionally, erasing conflict strikethrough markers for ALL commands whenever the user clicks a new row to record. In AyuGram, conflict state is per-button (`button->removed = rpl::variable<bool>`) and is only cleared when the conflicting key is explicitly resolved via `S::Change(was, now, command, entry.command)`. In the Dart, if the user assigns Ctrl+K to Search (displacing FormatLink) and then immediately clicks on "Close Telegram" to record, FormatLink's Ctrl+K strikethrough disappears from the UI even though `_currentBindings` still holds the entry (it's only excluded via `_removedKeys`). The shortcut system state is correct but the UI shows stale/wrong conflict state. — `shortcuts_settings_screen.dart:203` ← `settings/sections/settings_shortcuts.cpp:377-386`

- [ ] [MAJOR] `ListView` with all rows built as an eager `children` list — the total row count is 54 commands × (1 or more bindings per command) ≈ 60–80+ `_ShortcutRow` widgets, all constructed unconditionally on every `build()`. Should use `ListView.builder` with a pre-flattened `List<Widget>` or a `SliverList` with a delegate to allow viewport-based lazy construction. — `shortcuts_settings_screen.dart:397` ← `settings/sections/settings_shortcuts.cpp:474-484` (AyuGram adds widgets lazily via `fill()` per visible entry)

- [ ] [MAJOR] `_addAnotherBinding` (called from the context menu) always appends a new empty slot without checking whether the command already has an existing empty slot waiting for input. AyuGram's context menu handler first searches `i->now` for an existing `QKeySequence()` (empty) entry and reuses it; only if none exists does it push a new one. In the Dart, clicking "Add another binding" twice creates two phantom recording rows for the same command. — `shortcuts_settings_screen.dart:255-258` ← `settings/sections/settings_shortcuts.cpp:312-323`

# spoiler_animation — 2 issues

- [ ] [MAJOR] Image darkening overlay uses white (255,255,255,32) instead of black (0,0,0,32) for zero-particle areas, causing image spoilers to lighten the background rather than darken it. C++ pre-fills with `QColor(0,0,0,kImageSpoilerDarkenAlpha)` (pure black at alpha=32) then composites white particles on top; Dart initializes all pixels as white (255,255,255) then in `_applyImageDarkening` sets transparent-pixel alpha to 32, yielding (255,255,255,32) — a whitening effect opposite to the intended darkening. — `spoiler_animation.dart:300-302` ← `spoiler_mess.cpp:853-854`

- [ ] [MAJOR] Cache header `frameDuration` field (written at offset 20) is never read or validated on cache load. `_saveSpoilerCache` writes all 6 header fields including `_kFrameDurationMs` at offset 20 (`header.setInt32(20, _kFrameDurationMs, Endian.little)`), but `_loadSpoilerCache` only reads and checks version, dataLen, storedHash, framesCount, and canvasSize — skipping frameDuration entirely. C++ `FromSerialized` validates all three Validator fields (frameDuration, framesCount, canvasSize) and rejects the cache if any mismatch. A stale cache built with a different frame duration would be silently accepted by Dart, producing a timing mismatch between the stored animation and runtime expectations. — `spoiler_animation.dart:219-230, 288` ← `spoiler_mess.cpp:732-741`

# stats_chart — Chart rendering visual bugs and per-frame performance issues

- [ ] [CRITICAL] `_FilterButton` inactive text color is always `Colors.white` (line 1424: `const inactiveText = Colors.white`), applied on line 1454 when `active = false`. Background when inactive is `colorScheme.surface` (white in light mode) → white text on white background = invisible label. AyuGram uses the line's own color as inactive text so the label stays readable — `stats_chart.dart:1424` ← `AyuGram/statistics/widgets/chart_lines_filter_widget.cpp:57` (`_inactiveTextColor(st::premiumButtonFg->c)` / line 122 transitions text from `_activeColor` toward `_inactiveTextColor`; unchecked state = `_activeColor` = colored text on background)

- [ ] [MAJOR] Footer dim overlay color is hardcoded to `const Color(0x99e2eef9)` (line 963) regardless of `isDark`. `isDark` is available at the call site but ignored for this parameter. In dark mode this renders a light-blue overlay on a dark background — `stats_chart.dart:963` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:665` (`statisticsChartInactive: #e2eef999` is the default/light-theme value; dark themes override it; `chart_widget.cpp:449` uses `st::statisticsChartInactive` which is theme-aware)

- [ ] [MAJOR] `_cachedTP` cache key (line 1594) is `'$text|${style.fontSize}'` — omits color. The equality guard on line 1601 compares full `TextSpan` (which includes `TextStyle.color`). During ruler crossfade animation `rulerCrossfade < 1.0`, label colors change each frame (e.g. `Colors.white.withValues(alpha: 0.6 * rulerCrossfade)` at line 1694), so the equality check always fails and `layout()` is called on every animation frame for every ruler and date label — `stats_chart.dart:1594` / `stats_chart.dart:1601` ← `AyuGram/statistics/chart_widget.cpp:749` (AyuGram animates ruler alpha via `rulersView.setAlpha()` separately without relaying out text per tick)

- [ ] [MAJOR] `_buildTooltip` allocates, lays out, and immediately disposes multiple `TextPainter` objects on every call (lines 1041-1066) just to measure maximum column widths. `_buildTooltip` is called from `build()` whenever `_selectedIndex != null`, and `build()` is driven by `setState` on each animation tick (from `_chartTicker`, `_lineAlphaControllers`, etc.). While a point is selected during any active animation, this creates N×3 TextPainters per frame (N = line count) — `stats_chart.dart:1040` ← `AyuGram/statistics/widgets/point_details_widget.cpp` (AyuGram uses a persistent `PointDetailsWidget` that updates in place rather than rebuilding per frame)

- [ ] [MAJOR] Footer handle color uses `accentColor.withValues(alpha: 0.7)` (line 2351) — theme primary color. AyuGram specifies a fixed neutral gray-blue `statisticsChartActive: #baccd9d8` for the selection handles, independent of the accent color — `stats_chart.dart:2351` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:666` / `AyuGram/statistics/chart_widget.cpp:488` (`p.setBrush(st::statisticsChartActive)`)

# main — Audit findings

## main — Tray Ctrl+click separate window not implemented

- [ ] [CRITICAL] Ctrl+click on a tray account item logs a debug message and then falls through to the same normal account-switch path — no separate window is opened. AyuGram calls `Core::App().ensureSeparateWindowFor({ strong })` on Ctrl+click and skips `maybeActivate` entirely; the Dart does the opposite: it still calls `appState.setActiveAccountId` + `chatState.switchAccount` even when `ctrlPressed == true`, so the window is just switched instead of duplicated. — `main.dart:393-397` ← `tray_accounts_menu.cpp:62-64`

## main — Theme revert overlay timer drift

- [ ] [MAJOR] `_ThemeRevertOverlayState` decrements `_remainingMs` by a fixed 100 on every timer tick (`_remainingMs -= 100`). If the timer fires late (tab throttled, debug breakpoint, frame jank) the countdown underestimates elapsed time and auto-revert fires later than the 16-second spec. AyuGram computes remaining seconds from wall clock (`(kWaitBeforeRevertMs - msPassed) / 1000` where `msPassed = crl::now() - _started`) so it is immune to timer jitter. — `main.dart:2183` ← `window_theme_warning.cpp:99-104`

## main — Passcode lock screen uses hardcoded English strings

- [ ] [MAJOR] `_PasscodeLockScreen` hardcodes four main-UI strings in English while the rest of the app uses the `TrStrings` l10n system and supports 19 locales. The hardcoded strings and their AyuGram equivalents:
  - `'Please enter your passcode'` (AyuGram: `lng_passcode_enter` = "Enter your local passcode") — `main.dart:2561` ← `lang.strings:1173`
  - `'Your passcode'` hint — `main.dart:2592` ← `lang.strings:1174`
  - `'Submit'` button — `main.dart:2639` ← `lang.strings:1175`
  - `'Log out'` link — `main.dart:2674` ← `lang.strings:1176`

  `strings.dart` only declares `lngPasscodeWrong()` (line 15); the other four keys are absent from the l10n file entirely, so non-English users see English text on the passcode screen.

# sticker_pack_viewer — Audit findings

- [ ] [CRITICAL] "View Pack" context menu item is a stub — `case 'pack': break;` does nothing when tapped — `sticker_pack_viewer.dart:648-649` ← `boxes/sticker_set_box.cpp:1782-1801` (AyuGram shows "Add to Set" or navigates to the pack; the Dart case simply breaks with no action)

- [ ] [CRITICAL] Premium Unlock button has empty `onPressed: () {}` — tapping it does nothing — `sticker_pack_viewer.dart:305` ← `boxes/sticker_set_box.cpp:984-988` (AyuGram calls `Settings::ShowPremium(window, u"animated_emoji"_q)` to open the Premium upgrade screen)

- [ ] [CRITICAL] Fave toggle doesn't update local UI state — after calling `faveSticker()` the `sticker.isFaved` field on the `StickerInfoItem` is not flipped, so the context menu immediately reopened still shows the wrong label ("Add to Favorites" when it was just added, or vice versa) — `sticker_pack_viewer.dart:643-647` ← `boxes/sticker_set_box.cpp:1773` (AyuGram reads `isFaved(document)` from the live data layer which is updated synchronously by `ToggleFavedSticker`)

- [ ] [MAJOR] Context menu missing "Delete sticker" action for set creators — AyuGram shows a destructive "Delete" menu item with confirmation box when `amSetCreator()` is true — `sticker_pack_viewer.dart:630-650` ← `boxes/sticker_set_box.cpp:1788-1800`

- [ ] [MAJOR] Context menu missing "Add to Set" action for non-creators — AyuGram adds `Api::AddAddToStickerSetAction` for users who own a custom sticker set but didn't create this one — `sticker_pack_viewer.dart:630-650` ← `boxes/sticker_set_box.cpp:1782-1786`

## story_editor — video story backend missing, disabled premium gate broken, contacts exclusion stub

- [ ] [CRITICAL] `sendStoryWithVideoFile` calls engine command `'SendStoryWithVideo'` but no handler for this command exists anywhere in the Go backend (not in `dispatch_engine.go`, not in `dispatch_gen.go`, not in `telegram.go`) — video story posting always throws an unhandled error — `story_editor.dart:472` ← `go/bridge/dispatch_engine.go:3562` (only `SendStoryWithPhoto` exists, `SendStoryWithVideo` is absent)

- [ ] [CRITICAL] "Contacts" privacy option UI shows subtitle "Exclude people" but clicking it never opens a contact-exclusion picker; selecting `StoryPrivacyOption.contacts` and posting sends `InputPrivacyValueAllowContacts{}` with no disallow-list — the "exclude specific contacts from contacts audience" flow is a stub with misleading UI — `story_editor.dart:2248` ← `data/data_story.h:30` (`StoryPrivacy::Contacts` with exclusion is a distinct privacy mode, not raw AllowContacts)

- [ ] [MAJOR] `_durationItem(48)` creates a `PopupMenuItem` with `enabled: false` and `onTap` set to show a premium toast, but Flutter's `PopupMenuItem` does not fire `onTap` when `enabled: false` — the 48h option is silently unresponsive instead of showing the paywall toast — `story_editor.dart:1700-1707` ← `media/stories/media_stories_controller.cpp:1875` (premium gate check triggers visible prompt)

- [ ] [MAJOR] When a video file is selected and the user reaches the post stage, `_renderCanvasToBytes()` is NOT called and no overlay (paint strokes, text items, stickers) is composited onto the video — all editorial annotations placed on a video story are silently discarded on post — `story_editor.dart:471-483` ← `editor/editor_paint.cpp` (paint layer is composited into the final media before sending)

# telegram_toast — Sticker/emoji premium toast wiring and style issues

- [ ] [CRITICAL] Animated emoji premium toast never triggered — both callers (`message_bubble.dart:3436`, `chat_view.dart:1588`) pass `isEmoji: false`. The toast branches for `isEmoji: true` (animated emoji subscribe prompt, toSaved variant) are completely dead. In AyuGram, `StickerToast::showFor` sets `isEmoji = (setType == Data::StickersType::Emoji)` and triggers a different message for emoji packs. — `telegram_toast.dart:426-449` ← `history_view_sticker_toast.cpp:143-155`

- [ ] [CRITICAL] `onOpenSavedMessages` callback always `null` in every call site — both `message_bubble.dart:3436-3443` and `chat_view.dart:1588-1595` never pass `onOpenSavedMessages`. The "Open" button shown on every second emoji toast would silently do nothing (`_viewCallback` returns `null`, so the button is hidden, but the correct behavior is to navigate to Saved Messages). — `telegram_toast.dart:503` ← `history_view_sticker_toast.cpp:227-233`

- [ ] [MAJOR] Wrong "View"/"Open" button color — Dart uses `Color(0xFF6AB2F2)` (#6ab2f2, R=106 G=178 B=242). AyuGram uses `mediaviewTextLinkFg = #4db8ff` (R=77 G=184 B=255). These are visually distinct colours (>10% channel deviation on R and B). — `telegram_toast.dart:548` ← `colors.palette:527` + `chat.style:266`

- [ ] [MAJOR] Pack name shows technical short name instead of display title — callers pass `message.stickerSetShortName` (e.g. `"AnimatedEmoji"`) as `packName`. AyuGram first looks up the title from the local sets cache, then if missing makes a `messages.getStickerSet` API request to fetch the display title (e.g. `"Animated Emoji"`) before showing the toast. The Dart toast therefore shows the URL short-name to users instead of the human-readable pack title. — `message_bubble.dart:3438-3440` / `chat_view.dart:1590-1592` ← `history_view_sticker_toast.cpp:89-132`

# telegram_tooltip — 5 issues

- [ ] [MAJOR] `_ArrowPainter.paint()` clamps arrow position to `[arrowSkip, size.width - arrowSkip]` (66px minimum from each edge), but AyuGram constrains the tooltip box so the arrow is at least `arrowSkipMin` (24px) from the edge — the clamp bound should come from `arrowSkipMin` (24px), not `arrowSkip` (66px); in edge cases where the target is near a screen edge the Dart arrow is clamped 2.75× too aggressively — `telegram_tooltip.dart:462-463` ← `tooltip.cpp:380-381` + `widgets.style:1308`

- [ ] [MAJOR] `_resolveSide()` never returns `TooltipSide.left` or `TooltipSide.right` — the `left`/`right` cases at lines 351-354 fall through to bottom/top, making `TooltipSide.left` and `TooltipSide.right` dead code; AyuGram preserves Left/Right as distinct sides that affect both layout and animation — `telegram_tooltip.dart:351-355` ← `tooltip.h:96-98` + `tooltip.cpp:372-387`

- [ ] [MAJOR] Animation slide direction is always vertical (`Offset(0.0, slideOffset)`) regardless of tooltip side; AyuGram uses horizontal slide (`x += shift`) for Left/Right sides and vertical slide for Top/Bottom — `telegram_tooltip.dart:327-335` ← `tooltip.cpp:395-401`

- [ ] [MAJOR] Regular `TelegramTooltip` follows the cursor dynamically — `_onHover` updates `_lastPointer` and calls `markNeedsBuild()` causing the overlay to reposition on every pointer move; AyuGram tooltip is static (positioned once when shown) and hides if the cursor moves more than `startDragDistance()` from the initial show position — `telegram_tooltip.dart:71-74` ← `tooltip.cpp:62-72`

- [ ] [MAJOR] No window-active guard before showing the regular tooltip — Dart's `_show()` inserts the overlay unconditionally; AyuGram only shows the tooltip when `tooltipWindowActive()` returns true (i.e., when the application window has focus) — `telegram_tooltip.dart:85-95` ← `tooltip.cpp:49-60`

# theme_editor — Audit Findings

## Sources
- Dart: `dart/lib/ui/theme_editor.dart`
- AyuGram: `Telegram/SourceFiles/window/themes/window_theme_editor.cpp`
- AyuGram: `Telegram/SourceFiles/window/themes/window_theme_editor_block.cpp`
- AyuGram: `Telegram/SourceFiles/window/themes/window_theme_editor_box.cpp`
- Style: `Telegram/SourceFiles/window/window.style:167-170`

---

- [ ] [CRITICAL] `accessHash` hardcoded as `0` when building `CloudThemeMeta` for update path — `account_UpdateTheme` requires a real access hash obtained from `account_GetTheme`, so passing 0 will cause the API call to fail for any existing theme update — `theme_editor.dart:281` ← `window_theme_editor_box.cpp:525` (`MTP_inputTheme(MTP_long(fields.id), MTP_long(fields.accessHash))`)

- [ ] [CRITICAL] Import file picker uses `FileType.any` (accepts all files) — AyuGram filters to `*.tdesktop-theme *.tdesktop-palette` only; accepting arbitrary files causes silent parse failures with no user feedback — `theme_editor.dart:341` ← `window_theme_editor.cpp:787` (`"Theme files (*.tdesktop-theme *.tdesktop-palette)"`)

- [ ] [CRITICAL] "Show in Folder" menu item is disabled unless the user has previously exported a file (`_themeFilePath != null`) — AyuGram always enables this item and shows the live editing palette path (`EditingPalettePath()`), not an export destination; the Dart behavior breaks the primary "show your editing file in folder" use case — `theme_editor.dart:402-406` ← `window_theme_editor.cpp:757-759`

- [ ] [CRITICAL] When editing a token whose value is referenced (copied) by other tokens, Dart only updates the single token in `_colorMap` — AyuGram propagates the change through all dependent copies via `checkCopiesChanged()` cascading through `_context.changed` events — `theme_editor.dart:169-178` (`_updateColor`) ← `window_theme_editor_block.cpp:624-637` (`checkCopiesChanged`)

- [ ] [MAJOR] Active editing row uses `accentColor.withAlpha(30)` (~12% tinted background) — AyuGram fills the row with solid `st::dialogsBgActive` (fully opaque selection blue), a dramatically different visual — `theme_editor.dart:771` ← `window_theme_editor_block.cpp:717` (`p.fillRect(rect, active ? st::dialogsBgActive : ...)`)

- [ ] [MAJOR] When a color editor is open (editing state), AyuGram dims all rows below the active row with a `st::layerBg` semi-transparent overlay to visually focus attention — Dart has no such overlay; all non-editing rows remain fully opaque, breaking the focus UX — `theme_editor.dart` (no overlay anywhere in `_PaletteEntryRow`) ← `window_theme_editor_block.cpp:751-752` (`if (isEditing() && !active ...) p.fillRect(rect, st::layerBg)`)

- [ ] [MAJOR] Close button is positioned on the LEFT of the toolbar (`Row` starts with `IconButton(Icons.close)`) — AyuGram places the close button on the RIGHT via `_close->moveToRight(0, 0)` with the menu toggle immediately to its left — `theme_editor.dart:657-661` ← `window_theme_editor.cpp:857-858`

- [ ] [MAJOR] `updateCloudTheme` engine call does not pass the access hash — the bridge method signature omits it (`updateCloudTheme(accountId, themeId, title, slug, themeData)`) while the MTProto `account.updateTheme` requires `InputTheme` which is `{id, access_hash}` — `theme_editor.dart:311-316` ← `window_theme_editor_box.cpp:522-525`

- [ ] [MAJOR] Page-down/page-up keyboard navigation uses estimated row heights via `_estimateRowHeight` instead of reading actual rendered positions — AyuGram computes `selectSkipPage` from the real scroll height and iterates through actual row heights (`st::themeEditorMargin.top() + st::themeEditorSampleSize.height() + ...`) — `theme_editor.dart:462-483` ← `window_theme_editor.cpp:530-538`

- [ ] [MAJOR] `_sortByAccentDistance` computes accent distance using HSL lightness (via `HSLColor`) but returns score `255 - (color.saturation * 255).round()` — AyuGram sorts by `255 - fromSaturation` where `fromSaturation` is QColor's HSL saturation (0–255 int range), while Flutter's `HSLColor.saturation` is 0.0–1.0; the `clamp(0,255)` at the end masks the error but the sort order is computed identically only by accident — `theme_editor.dart:116-122` ← `window_theme_editor_block.cpp:454-466`

- [ ] [MAJOR] Background image in `_SaveThemeBox` is always re-encoded as JPEG at quality 87, even if the source was a PNG — AyuGram preserves the original format (`parsed.isPng`) and writes `background.png` vs `background.jpg` accordingly; Dart always produces JPEG — `theme_editor.dart:1173-1177` (`_encodeAsJpeg87`) ← `window_theme_editor_box.cpp:338-343` (`parsed.isPng ? ".png" : ".jpg"`)

- [ ] [MAJOR] Save precondition checks (passcode lock, session existence) are absent from the Dart SAVE THEME button — AyuGram blocks the save with a toast if the account is passcode-locked or has no session before opening the save box — `theme_editor.dart:275-337` (`_handleSaveToCloud` — no lock check) ← `window_theme_editor.cpp:837-842`

# titlebar — Custom CSD titlebar

- [ ] [CRITICAL] `_startDrag()` is called on **every** `onPointerMove` event during a drag, spamming the native channel with repeated `startDrag` method calls. AyuGram calls `startSystemMove()` once and immediately sends a synthetic `MouseButtonRelease` to clear `_mousePressed`, guaranteeing a single invocation per drag gesture — `titlebar.dart:241` (`onPointerMove: (_) => _startDrag()`) ← `ui_platform_window_title.cpp:487-494` (`if (_mousePressed) { window()->windowHandle()->startSystemMove(); SendSynteticMouseEvent(…, Qt::LeftButton); }`)

- [ ] [MAJOR] Window context menu is shown on `onSecondaryTapUp` (right-button **release**), but AyuGram shows it on `mousePressEvent` with `Qt::RightButton` (right-button **press-down**). The menu appears immediately on press in the reference — `titlebar.dart:238` (`onSecondaryTapUp: (_) => _showWindowMenu()`) ← `ui_platform_window_title.cpp:476-478` (`} else if (e->button() == Qt::RightButton) { ShowWindowMenu(window(), e->windowPos().toPoint()); }`)

- [ ] [MAJOR] Button icons use generic Flutter Material icons (`Icons.remove`, `Icons.crop_square`, `Icons.filter_none`, `Icons.close`) instead of Telegram's custom SVG assets (`title_button_minimize`, `title_button_maximize`, `title_button_restore`, `title_button_close`). The restore icon in particular (`Icons.filter_none`) is visually wrong — the reference uses a distinct overlapping-squares glyph — `titlebar.dart:296-302` ← `widgets.style:1602,1620,1635-1648,1653` (`{ "title_button_minimize", … }`, `{ "title_button_maximize", … }`, `{ "title_button_restore", … }`, `{ "title_button_close", … }`)

# web_app_panel — WebApp Mini-App Panel

- [ ] [CRITICAL] `_allowClipboardRead` is always `false` and never set — `WebAppPanelData` has no `allowClipboardRead` field so it can never be passed in; the flag stays false forever and blocks all clipboard reads even for bots that have permission — `web_app_panel.dart:136` ← `attach_bot_webview.h:272` (`_allowClipboardRead : 1 = false` initialized from `args.allowClipboardRead`)

- [ ] [CRITICAL] `_lastWebviewInteraction` is initialized to epoch and never updated — `setInteractionHandler` wires up a native callback that updates this timestamp on every webview interaction; Dart never wires this up, so `timeSinceInteraction.inSeconds` is always billions of seconds > 10, meaning clipboard reads are permanently blocked even when `_allowClipboardRead` were true — `web_app_panel.dart:137,715-717` ← `attach_bot_webview.cpp:920-922` (`raw->setInteractionHandler([=] { _lastWebviewInteraction = crl::now(); });`)

- [ ] [CRITICAL] `web_app_close` incorrectly triggers close-confirmation dialog — AyuGram calls `_delegate->botClose()` directly (no confirmation) because the bot itself is requesting close; Dart calls `_close()` which checks `_closeNeedConfirmation` and may show a dialog, contradicting the spec — `web_app_panel.dart:263-264` ← `attach_bot_webview.cpp:963`

- [ ] [MAJOR] `web_app_open_tg_link` missing `keepOpen=true` — AyuGram passes `keepOpen = true` so the panel stays open when the TG link is handled; Dart's engine call has no equivalent and the panel may close unexpectedly — `web_app_panel.dart:435-438` ← `attach_bot_webview.cpp:1374` (`_delegate->botHandleLocalUri("https://t.me" + path, true)`)

- [ ] [MAJOR] Downloads submenu missing from the three-dot menu — AyuGram checks `botDownloads(true)`, and if non-empty inserts a full downloads submenu with per-entry actions above Settings; Dart's `_showMenu` has no downloads section at all — `web_app_panel.dart:1256-1313` ← `attach_bot_webview.cpp:752-830`

- [ ] [MAJOR] Button state is accumulated progressively using `prev.*` — AyuGram reads all fields fresh from the incoming args object on each `processButtonMessage` call (`args["is_active"].toBool()` defaults to `false` when absent, `args["text"].toString()` defaults to empty string); Dart substitutes `prev.active` / `prev.text` when fields are absent, causing stale button state when bots send partial updates — `web_app_panel.dart:1023-1036` ← `attach_bot_webview.cpp:1713-1745`

- [ ] [MAJOR] `invoiceClosed` / `hideForPayment` not implemented — AyuGram hides the panel with `hideForPayment()` while the native payment UI runs and re-shows it via `invoiceClosed(slug, status)` after completion; Dart immediately fires `invoice_closed` from the engine call result without any panel hiding/re-showing, breaking the native payment flow — `web_app_panel.dart:487-508` ← `attach_bot_webview.cpp:2147-2163`

- [ ] [MAJOR] `openPopup` with empty `message` doesn't close bot — AyuGram calls `_delegate->botClose()` if message is empty or buttons array is empty; Dart shows the dialog with an empty message or no buttons instead — `web_app_panel.dart:1082-1109` ← `attach_bot_webview.cpp:1442-1450`

- [ ] [MAJOR] Viewport not re-sent on webview geometry changes — AyuGram sends `viewport_changed` inside the container geometry listener (`rpl::combine(container->geometryValue(), _footerHeight.value()) | rpl::on_next(...)`) so bots get live resize updates; Dart only sends viewport when the bot explicitly requests it with `web_app_request_viewport` — `web_app_panel.dart:1067-1080` ← `attach_bot_webview.cpp:940-951`

- [ ] [MAJOR] Progress spinner color is wrong — AyuGram uses `st::paymentsLoading.color` which maps to `windowSubTextFg` (a dedicated muted color, fully opaque); Dart uses `(isDark ? Colors.white : palette.windowFg).withValues(alpha: _kProgressOpacity)` (30% opacity of the foreground text color); the constant `_kProgressOpacity = 0.3` in AyuGram is used for the background fill overlay, not the spinner arc — `web_app_panel.dart:1531-1532` ← `attach_bot_webview.cpp:637-644` + `payments.style:137-141`

## engine_models — Data model audit

### GroupCallParticipant — fields in Dart class never populated from Go JSON

The Go engine struct `engine.GroupCallParticipant` (`go/engine/cache_chats.go:1434`) only emits these JSON keys:
`user_id`, `display_name`, `is_muted`, `is_speaking`, `has_video`, `avatar_path`, `can_self_unmute`, `raised_hand_rating`, `volume`, `audio_level`.

The event handler (`go/engine/events.go:464`) constructs with even fewer fields (no `can_self_unmute`, `raised_hand_rating`, `volume`, `audio_level`).

The following Dart fields exist in the constructor and are parsed in `fromJson` but the Go bridge **never emits them** — they will always be their zero defaults:

- [ ] [CRITICAL] `mutedByMe` — defined at `engine_models.dart:2257`, parsed `fromJson` at `engine_models.dart:2296`, but `go/engine/cache_chats.go:1434` has no `muted_by_me` JSON field. AyuGram `data_group_call.h:51` has `mutedByMe`. Add `MutedByMe bool json:"muted_by_me,omitempty"` to `engine.GroupCallParticipant` and populate from `cores.CallParticipant`.
- [ ] [CRITICAL] `sounding` — defined at `engine_models.dart:2259`, parsed at `engine_models.dart:2298`, but `go/engine/cache_chats.go:1434` has no `sounding` field. AyuGram `data_group_call.h:46`. Add to Go struct.
- [ ] [CRITICAL] `additionalSounding` — defined at `engine_models.dart:2267`, parsed at `engine_models.dart:2306`, not in `go/engine/cache_chats.go:1434`. AyuGram `data_group_call.h:48`. Add to Go struct.
- [ ] [CRITICAL] `additionalSpeaking` — defined at `engine_models.dart:2268`, parsed at `engine_models.dart:2307`, not in `go/engine/cache_chats.go:1434`. AyuGram `data_group_call.h:49`. Add to Go struct.
- [ ] [CRITICAL] `ssrc` — defined at `engine_models.dart:2266`, parsed at `engine_models.dart:2305`, not in `go/engine/cache_chats.go:1434`. AyuGram `data_group_call.h:44` (`uint32 ssrc`). Required for audio routing. Add to Go struct.
- [ ] [CRITICAL] `lastActive` — defined at `engine_models.dart:2269`, parsed at `engine_models.dart:2308`, not in `go/engine/cache_chats.go:1434`. AyuGram `data_group_call.h:42` (`TimeId lastActive`). Add to Go struct.
- [ ] [CRITICAL] `date` — defined at `engine_models.dart:2270`, parsed at `engine_models.dart:2309`, not in `go/engine/cache_chats.go:1434`. AyuGram `data_group_call.h:41` (`TimeId date`). Add to Go struct.

### GroupCallInfo — fields in Dart class never populated from Go JSON

The Go engine struct `engine.GroupCallInfo` (`go/engine/cache_chats.go:1424`) only has: `call_id`, `chat_id`, `title`, `participants_count`, `participants`, `active`.

- [ ] [CRITICAL] `isRtmp` — defined at `engine_models.dart:2320`, parsed `fromJson` at `engine_models.dart:2344`, but `go/engine/cache_chats.go:1424` has no `is_rtmp` field. AyuGram `data_group_call.h:86` (`bool rtmp() const`). Add `IsRtmp bool json:"is_rtmp,omitempty"` to `engine.GroupCallInfo` and populate from `cores.CallSession.Meta["is_rtmp"]`.
- [ ] [CRITICAL] `scheduleDate` — defined at `engine_models.dart:2321`, parsed `fromJson` at `engine_models.dart:2346`, but `go/engine/cache_chats.go:1424` has no `schedule_date` field. AyuGram `data_group_call.h:75` (`TimeId scheduleDate`). Add to Go struct and populate from `cores.CallSession.Meta["schedule_date"]`.
- [ ] [CRITICAL] `origin` — defined at `engine_models.dart:2322`, parsed `fromJson` at `engine_models.dart:2347`, but `go/engine/cache_chats.go:1424` has no `origin` field. AyuGram `data_group_call.h:63` (`enum GroupCallOrigin: Group, Conference, VideoStream`). Add `Origin string json:"origin,omitempty"` to Go struct.

### CachedMessage — field parsed but never emitted by Go bridge

- [ ] [CRITICAL] `forwardFromId` — defined at `engine_models.dart:468`, parsed `fromJson` at `engine_models.dart:767` (`j['forward_from_id']`), but `go/engine/cache_msgs.go:42` only has `ForwardFrom string json:"forward_from"` — there is no `forward_from_id` field anywhere in the Go engine JSON. The field will always be empty string. Either add `ForwardFromID string json:"forward_from_id,omitempty"` to `engine.CachedMessage` (populated from `cores.CoreMessage.ForwardFromID` at `go/cores/base.go:274`), or remove `forwardFromId` from the Dart model if unused.

