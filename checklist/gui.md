# GUI Audit — Cycle 1 Phase Ayugram (2026-05-09 01:56)

## Code Comparison Findings (Dart vs AyuGram)

# bridge — No critical or major issues found

## Summary

The `bridge.dart` file and its platform-specific implementations (`bridge_ffi.dart`, `bridge_web.dart`, `bridge_stub.dart`) are complete, well-structured, and properly wired to the Go backend. No stubs, placeholders, unimplemented features, or broken wiring detected.

## Verification Checklist

✅ **Placeholders & Stubs:**
- No empty callbacks (onTap: () {})
- No TODO/FIXME/HACK comments
- No hardcoded fake data or mock objects
- No "coming soon" snackbars or fake feedback
- No functions throwing "not implemented"
- All features properly wired to backend

✅ **Backend Wiring:**
- Bridge.dart correctly delegates to platform-specific implementations via conditional imports
- bridge_ffi.dart properly calls exported Go functions (BridgeCallWithLen, BridgeFree, BridgeSetEventCallback)
- bridge_web.dart properly calls JS interop functions (bridgeCall, bridgeSetEventCallback)
- Go backend (go/cmd/bridge/main.go) implements all three exported functions
- All functions delegate to actual bridge.Call() implementation (not stubs)
- Event callbacks properly marshaled between Go and Dart

✅ **Memory Management:**
- bridge_ffi.dart: Proper allocation/deallocation of C memory (lines 107-109, 128-129)
- bridge_ffi.dart: Proper event data copying and freeing (lines 154-155)
- bridge_web.dart: Proper stream cleanup in dispose() (line 49)

✅ **Event Handling:**
- bridge_ffi.dart: Uses NativeCallable.listener instead of Pointer.fromFunction for thread-safety (line 162)
- Proper StreamController.broadcast for multiple event listeners (line 146, bridge_ffi)
- Go side: Proper memory handling for C callbacks (go/cmd/bridge/main.go lines 58-68)

✅ **Platform Coverage:**
- bridge_stub.dart: Correct fallback for unsupported platforms with UnsupportedError
- bridge_ffi.dart: Linux, Windows, macOS, Android via dynamic library loading
- bridge_web.dart: Web/WASM via JS interop

✅ **Code Quality:**
- Dart analyzer: No issues
- No unused imports
- Proper error handling with assertions (initialized checks)
- Async operations properly handled via Isolate.run for FFI

## Conclusion

All methods are fully implemented and wired to the backend. No implementation gaps, stubs, or placeholders detected. The architecture is clean and follows proper FFI best practices for memory management, thread safety, and platform-specific handling.


# web_drop_web — Web drag-and-drop file zone

## CRITICAL Issues

## MAJOR Issues

## Notes

- On web, the JavaScript Drag and Drop API has security restrictions: dropped files cannot be accessed directly by filename—they must be processed through specific APIs like File objects in the DataTransfer. However, the current implementation extracts filenames but doesn't use them, which wastes the extraction effort and wastes user time (they must re-select files via FilePicker).

- The DragEvent extraction logic (`web_drop_web.dart:58-74`) is correct for the web platform's constraints, but the integration with the calling code breaks the feature entirely.

- Recommended fix: Modify the callback in `chat_view.dart` to pass the extracted File objects (or their metadata) to `_uploadFiles()` instead of opening FilePicker, or document why FilePicker is necessary and add explanatory text to the overlay.

# notification_system — NotificationSystem orchestrator audit

## Compared against: `window/notifications_manager.cpp` + `window/notifications_manager.h`

---


# notification_types.dart — Missing Privacy & Poll Vote Handling

## Summary
Data/utility file for notification text composition. Compares against AyuGram Desktop's `notifications_manager.cpp` (1079-1676). Core logic is present but missing critical privacy settings handling and poll vote composition.

---

## Findings


---

## Data Model Completeness

✅ **NotificationData** has fields for all needed info:
- ✅ `isReaction`, `reactorName`, `reactionEmoji` for reactions
- ✅ `isPollVote`, `pollQuestion` for polls
- ✅ `forwardFrom`, `forwardCount` for forwards (though forwardFrom unused)
- ✅ `spoilerLoginCode` for masking sensitive codes
- ✅ `multiAccount`, `accountUsername` for multi-account suffix
- ✅ `isScheduled`, forum/sublist fields for title composition

⚠️ **NotificationSettings** is missing critical privacy flags:
- ❌ No `hideNameAndPhoto` equivalent (AyuGram uses this to completely redact name/photo based on security/privacy settings)
- ❌ No `hideMarkAsRead` equivalent (AyuGram uses this to disable mark-as-read for scheduled messages)
- ✅ Has `previewName`, `previewText` which map to some of AyuGram's privacy levels

---

## Text Composition Logic

### Matches AyuGram ✅
- **Title composition** (line 233-256): Forum titles, sublist titles, scheduled reminders, multi-account suffix
- **Scheduled emoji** (line 248): Uses 📅 emoji for incoming scheduled (same as AyuGram line 1674)
- **Message type dispatch** (line 293-329): Photo, video, audio, voice, sticker, GIF, file, poll, location, contact, invoice
- **Spoiler masking** (line 331-340): Masks spoiler text and login codes (AyuGram line 1613-1614)
- **Forward count display** (line 278-279): Shows "N forwarded messages" count
- **Subtitle for groups** (line 265-268): Shows sender name in group/channel notifications

### Missing/Wrong ❌
- **Poll vote composition**: No separate function for poll votes
- **Reaction privacy filtering**: No hideReactionSender check
- **Forward-from details**: Field defined but unused

---

## Test Coverage Needed
1. Send poll vote notification → verify it shows the voted option, not poll title
2. Set reactions notifications to "hide previews" → verify reactor name is hidden
3. Forward a message → verify any "from" metadata is handled correctly
4. Reaction from self → verify it doesn't show "You reacted"


# app_state — Ghost mode enum collapse, wrong engine mapping, missing fields, wrong defaults

## Findings

- [ ] [CRITICAL] `sendWithoutSound` is typed as `bool` in Dart's `GhostModeAccountSettings` but AyuGram uses a 3-way `SendWithoutSoundOption` enum (Never=0, InGhostMode=1, Always=2). The "InGhostMode" behavior — automatically sending without sound only while ghost mode is active — is completely missing. Dart collapses Never and InGhostMode both to `false`, so the conditional behavior is lost. — `app_state.dart:29,44,68,84,981-985` ← `ayu_settings.h:96,115,170` + `ayu_settings.cpp:112-122`

- [ ] [CRITICAL] `setSendUploadProgress` calls `_engine.updateConfig(sendTyping: v)` and `_syncGhostToEngine` maps `sendTyping: s.sendUploadProgress`. Upload progress and typing status are distinct engine fields. This silently aliases `sendUploadProgress` to the `sendTyping` engine field, so disabling upload-progress in ghost mode also disables typing indicators (and vice versa) — two independent ghost features are conflated into one. — `app_state.dart:941,1215` ← `ayu_settings.h:91,92` (separate `sendOnlinePackets` and `sendUploadProgress` fields)

- [ ] [CRITICAL] `suggestGhostModeBeforeViewingStory` is entirely absent from Dart's `GhostModeAccountSettings`. AyuGram stores it per-account (default `true`), persists it in JSON, and uses it to prompt the user before viewing a story in normal mode. The Dart struct has no field, no fromJson/toJson entry, no getter/setter — the feature is silently dropped. — `app_state.dart:21-90` ← `ayu_settings.h:98,141,172` + `ayu_settings.cpp:131-135,219`

- [ ] [MAJOR] `setGhostModeEnabled(true)` does not call any `markAsOnline` equivalent on the engine. AyuGram's C++ immediately calls `AyuWorker::markAsOnline(session)` when enabling ghost mode so the user appears online before going silent. Dart's implementation only updates the toggle values and syncs to engine but never sends the presence packet, so the user may appear offline immediately instead of transitioning cleanly. — `app_state.dart:860-900` ← `ayu_settings.cpp:145-151`

- [ ] [MAJOR] `_filterZalgo` defaults to `true` in Dart (field init, `resetAyuSettings`, and load fallback `?? true`), but AyuGram defaults it to `false`. Users get zalgo text filtering enabled out-of-the-box while AyuGram ships it off. — `app_state.dart:265,1163,2739` ← `ayu_settings.h:689`

- [ ] [MAJOR] `wideMultiplier` is clamped to `[1.0, 4.0]` in Dart but AyuGram validates `[0.5, 4.0]`. Values 0.5–0.99 are valid AyuGram wide-column multipliers that Dart rejects outright, and settings migrated from AyuGram JSON in that range would be silently pinned to 1.0. — `app_state.dart:716` ← `ayu_settings.cpp:518`

- [ ] [MAJOR] `materialSwitches` load fallback is `?? false` but AyuGram defaults it to `true`. Any user whose prefs file lacks this key (first upgrade from an older build) gets switches rendered in the non-material style instead of the AyuGram default. — `app_state.dart:2633` ← `ayu_settings.h:635`

- [ ] [MAJOR] `_screenReaderOptimized` is never written to `_saveWindowPrefs` or read back in `_loadWindowPrefs`, so the setting resets to `false` on every cold launch. It is declared and has a setter but is silently non-persistent. — `app_state.dart:136,421,1691-1692` (absent from the `_saveWindowPrefs` map at lines 2799–2970)

# audio_service — Audio metadata not passed to player

## Critical Issues

- [x] [CRITICAL] Missing audio metadata when calling playVoice() — `audio_service.dart:34-39` (playVoice signature has performer/title/chatId parameters) vs actual calls in `message_bubble.dart:4098,4108,4497` (only pass filePath/msgId/msgTimestamp, never pass performer/title/chatId even though Message class has audioPerformer, audioTitle, senderName, chatId fields). Metadata parameters accepted but never populated by callers.

- [x] [CRITICAL] Unused metadata fields in AudioService — `audio_service.dart:12-14` (_currentPerformer, _currentTitle, _currentChatId stored but never displayed or used). Getters exist (lines 22-24) but never called in UI. Compare to AyuGram Desktop: `media_player_instance.h` tracks AudioMsgId with full message context; Dart layer stores metadata but doesn't use it.

- [x] [CRITICAL] AudioService.playVoice() called with empty performer/title in keyboard shortcuts — `keyboard_shortcuts.dart:1206,1212,1218` calls playVoice('', msgId) for play/pause/toggle, passing empty filePath. This works because of the early return on matching msgId (line 40-46), but signals the architectural issue: metadata is never required by the implementation.

## Summary

**Root cause:** Dart UI calls `playVoice(filePath, msgId, msgTimestamp)` but never passes the optional performer/title/chatId parameters even though Message objects contain audioPerformer, audioTitle, senderName. The AudioService accepts these as parameters but has no callers that populate them, making them dead code.

**Comparison to AyuGram:** In AyuGram Desktop (media_player_instance.h), Audio messages are identified by AudioMsgId which carries DocumentData and FullMsgId (containing message context). Metadata flows through the player system. In Dart, metadata flows from engine→Message but stops at AudioService.playVoice() entry point.

**Expected behavior:** All three call sites should pass:
- performer: msg.audioPerformer (or senderName as fallback)
- title: msg.audioTitle  
- chatId: msg.chatId

See message_bubble.dart lines 4098, 4108, 4497 and keyboard_shortcuts.dart lines 1206, 1212, 1218.

# auth_state — Auth flow state manager

- [ ] [CRITICAL] SRP_ID_INVALID silent-retry catch block is dead code — `auth_state.dart:101-117` ← `intro_password_check.cpp:169-178`
  The catch at line 101 checks `errStr.contains('SRP_ID_INVALID')`, but `_engine.submitAuthInput()` (`engine_service.dart:137-143`) never throws for SRP errors — the Go engine wraps all errors as `AuthStateError` states returned as the proto response value, not as thrown exceptions. The SRP_ID_INVALID error arrives at line 97 as `result.error`, `_currentAuth = result` is assigned, and execution falls through to `notifyListeners()` at line 125. The catch block never executes. User sees the raw error state immediately with no retry. AyuGram's `handleSrpIdInvalid()` works correctly because it is invoked directly from `pwdSubmitFail()` as an MTP error callback, not from a try/catch around a future.

- [ ] [CRITICAL] SRP retry calls `submitInput` with flow already in error state — `auth_state.dart:115` ← `intro_password_check.cpp:177` (`requestPasswordData`)
  Even if the catch were somehow triggered, `await submitInput(input)` (line 115) calls `_engine.submitAuthInput(accountId, input)` again. But the Go flow state is now `AuthStateError` (set at `engine/auth.go:127`), so `advanceTelegram` hits the default branch and returns `fmt.Errorf("unexpected state error for telegram")` — another error state is returned, not a retry. AyuGram fixes this by calling `requestPasswordData()` first (cpp:177), which makes a fresh `MTPaccount_GetPassword` RPC to obtain a new SRP challenge ID before retrying `checkPasswordHash()`. The Dart retry has no equivalent refresh step and would fail unconditionally.

# ayu_forward — Forward state machine and intelligent chunking

- [ ] [CRITICAL] `isMessageRestricted` omits `unsupportedTTL` check — C++ `isAyuForwardNeeded` guards on `item->unsupportedTTL()` as a separate condition from `item->media()->ttlSeconds()` (self-destruct timer messages that the client doesn't support), but Dart collapses both into `msg.ttlSeconds > 0`; messages with `_unsupportedTTL > 0` and no media TTL take the native forward path instead of resend-as-own, which will fail — `ayu_forward.dart:101` ← `ayu_forward.cpp:227`

- [ ] [MAJOR] Sender-level AyuNoForwards check (`isFullAyuForwardNeeded`) absent — C++ top-level gate in `ApiWrap::forwardMessages` checks `item->from()->isAyuNoForwards()` BEFORE the per-message chunking; if true it forces the entire batch through `forwardMessages` (full resend-as-own) bypassing `intelligentForward`; Dart has no sender-level check — `isChatRestricted` only covers `chat.noForwards` (the peer side of the same check) but ignores the sender side entirely, so messages sent by a restricted sender will incorrectly try native forward — `ayu_forward.dart:106` ← `ayu_forward.cpp:233-235`, `apiwrap.cpp:3487`

- [ ] [MAJOR] `_groupByAlbum` breaks chronological message order in resend-as-own path — non-album messages are appended to `groups` inline, then all album groups are appended at the end via `groups.addAll(albumMap.values)`; for a sequence [A, B1, B2, C] where B1+B2 share an album the Dart sends [[A], [C], [B1,B2]] instead of [[A], [B1,B2], [C]]; C++ `prepareMedia` advances the outer loop index `i` to consume consecutive album members in-place, preserving order — `ayu_forward.dart:156-164` ← `ayu_forward.cpp:137-148`

- [ ] [MAJOR] `statusText` conflates `preparing` and `sending` phases — Dart maps both `AyuForwardPhase.preparing` and `AyuForwardPhase.sending` to the identical string `'Forwarding messages'`; C++ emits a distinct `tr::ayu_AyuForwardStatusPreparing` during `State::Preparing` and `tr::ayu_AyuForwardStatusForwarding` only during `State::Sending`; users see no indication that the operation is in a pre-send preparation stage — `ayu_forward.dart:33-35` ← `ayu_forward.cpp:84-89`

# chat_state — State Management Audit

- [ ] [CRITICAL] `togglePinSavedSublist` has explicit "TBD" comment — only mutates local lists, never calls engine; `MTPmessages_ToggleSavedDialogPin` is never issued — `chat_state.dart:1188` ← `AyuGram/window/window_peer_menu.cpp:469`

- [ ] [CRITICAL] `markSavedSublistRead` is a stub — body is only `notifyListeners()`, no backend call; AyuGram calls `SavedSublist::readTillEnd()` which sends `messages.readHistory` — `chat_state.dart:1211` ← `AyuGram/data/data_saved_sublist.cpp:285`

- [ ] [CRITICAL] `deleteSavedSublist` removes items from local lists only — never calls engine; AyuGram sends `MTPmessages_DeleteSavedHistory` via `ApiWrap::deleteSublistHistory` — `chat_state.dart:1215` ← `AyuGram/apiwrap.cpp:1469`

- [ ] [CRITICAL] `reorderPinnedChats` mutates in-memory `_pinnedChatOrders` only — drag-to-reorder never persists; AyuGram sends `MTPmessages_ReorderPinnedDialogs` with `f_force` flag — `chat_state.dart:1695` ← `AyuGram/apiwrap.cpp:397`

- [ ] [CRITICAL] `reorderFolders` mutates local `_folders` list only — never persists order to server; AyuGram sends `MTPmessages_UpdateDialogFiltersOrder` — `chat_state.dart:811` ← `AyuGram/data/data_chat_filters.cpp:913`

- [ ] [MAJOR] Folder filter collapses contacts, non-contacts, and bots into a single "any DM" branch with comment "We can't distinguish contact/non-contact/bot yet"; AyuGram uses `user->isContact()` and `Flag::Bots` to filter each category separately — `chat_state.dart:700` ← `AyuGram/data/data_chat_filters.cpp:350`

- [ ] [MAJOR] `_autoPreloadForumTopics` and `loadMoreForumTopics` always call `getForumTopics(accountId, chatId)` with no offset parameter — pagination never advances beyond the first batch; AyuGram uses offset-based `requestTopics` — `chat_state.dart:1007` ← `AyuGram/data/data_forum.cpp` (`Forum::requestTopics`)

- [ ] [MAJOR] Saved Messages chat detected by string comparison `chat.title == 'Saved Messages'` — fragile and wrong for non-English locales; AyuGram uses `peer->isSelf()` identity check — `chat_state.dart:891` ← `AyuGram/dialogs/dialogs_inner_widget.cpp:3672`

# bridge_ffi.dart — Audit Report

## Summary
**No critical or major issues found.**

The `bridge_ffi.dart` file is a well-implemented FFI bridge that correctly:
- Loads native Go libraries on all platforms (Linux, macOS, Windows, Android)
- Manages FFI function lookups and symbol resolution
- Handles synchronous and asynchronous calls to the Go backend
- Implements proper memory allocation/deallocation with try/finally blocks
- Manages bidirectional event callbacks from Go to Dart
- Uses correct patterns for cross-thread callback marshaling (NativeCallable.listener)

## Architecture Assessment

**Note on AyuGram comparison:** bridge_ffi.dart is a Dart FFI bridge implementation with no direct correspondence in AyuGram Desktop C++ source. AyuGram is a pure C++/Qt application with no Dart or FFI layer. This audit assesses the bridge against Dart/FFI best practices rather than AyuGram source.

## Code Quality Checks

### ✓ No Placeholders/Stubs
- All methods have complete implementations
- No `TODO`, `FIXME`, `HACK`, or `not implemented` comments
- No empty callbacks or dummy implementations

### ✓ Backend Wiring
- `BridgeCallWithLen` properly exported and called: `bridge.go:28`
- `BridgeFree` properly freed memory: `bridge_ffi.dart:125`
- `BridgeSetEventCallback` registered correctly: `bridge_ffi.dart:64`
- Go library (`libcores.so` 102MB) successfully built and deployed
- Engine integration verified in `engine_service.dart:3622,3653`

### ✓ Memory Management
- Proper allocation in `_doCall()`: `bridge_ffi.dart:107-111`
- Proper freeing in try/finally: `bridge_ffi.dart:113-130`
- Event callback memory freed after copying: `bridge_ffi.dart:154-156`
- No memory leaks on error paths (finally blocks execute)

### ✓ Async/Threading
- `Isolate.run()` correctly isolates blocking calls: `bridge_ffi.dart:78`
- `NativeCallable.listener` correctly marshals callbacks to Dart isolate: `bridge_ffi.dart:162`
- Event controller properly handles concurrent events: `bridge_ffi.dart:146`

### ✓ Platform Support
- All platforms handled: Linux (bundled + fallback), macOS, Windows, Android: `bridge_ffi.dart:87-98`
- Bundled library check on Linux: `bridge_ffi.dart:89-91`

### ✓ Lifecycle Management
- Proper initialization guard: `bridge_ffi.dart:50`
- Proper cleanup on dispose: `bridge_ffi.dart:81-85`
- Safe disposal from engine: `engine_service.dart:3594`

## Verdict
**Ready for production. No fixes required.**

# telegram_palette — Color palette data class

## Issues

- [ ] [CRITICAL] `scrollBg` is fully transparent (`Color(0x00000000)`) in both `dayBlue` and `classicDay`; should be `Color(0x1A000000)` per the palette default. The value that belongs in `scrollBg` (alpha=0x1A) was placed in `scrollBgOver` instead (alpha=0x1A vs correct 0x2C), so both are wrong — `scrollBg` gets alpha=0 (invisible), `scrollBgOver` gets the value that was meant for `scrollBg` — `telegram_palette.dart:2824-2825` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:64-65`

- [ ] [CRITICAL] `introCoverTopBg`/`introCoverBottomBg` use a blue gradient (`Color(0xFF0F89D0)` / `Color(0xFF39B0F0)`) in all four themes (dayBlue, night, classicDay, nightGreen) but the palette default is dark navy `#2B2242` for both. Both day and night themes share identical intro cover values which is wrong for night — `telegram_palette.dart:2815-2817,3365-3367` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:171-173`

- [ ] [MAJOR] `menuSeparatorFg: Color(0xFFE5E5E5)` in `dayBlue` (line 2862) and `classicDay` (line 3932) — palette defines it as `#f1f1f1` = `Color(0xFFF1F1F1)` (windowBgOver), but the Dart uses `Color(0xFFE5E5E5)` (= windowBgRipple). Separator appears visually darker than it should — `telegram_palette.dart:2862` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:60`

- [ ] [MAJOR] `mainMenuCoverBg: Color(0xFF40A7E3)` in `dayBlue` (line 2866) — palette defines it as `dialogsBgActive` which resolves to `#419fd9` = `Color(0xFF419FD9)`, not `windowBgActive` (`0xFF40A7E3`). Slightly wrong cover background — `telegram_palette.dart:2866` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:496`

- [ ] [MAJOR] `kColorizeIgnoredKeys` is an incomplete exclusion set. At least 20 tokens are passed without `s()` in `colorize()` (meaning they are excluded from accent shift) but are NOT listed in this set: `trayCounterBg`, `trayCounterBgMute`, `trayCounterFg`, `trayCounterBgMacInvert`, `trayCounterFgMacInvert`, `paymentsTipActive`, `callArrowFg`, `callArrowMissedFg`, `botKbPrimaryBg`, `botKbDangerBg`, `botKbSuccessBg`, `botKbInlinePrimaryBg`, `botKbInlineDangerBg`, `botKbInlineSuccessBg`, `mapPointDrop`, `mapPointDot`, `youtubePlayIconBg`, `youtubePlayIconFg`, `videoPlayIconBg`, `videoPlayIconFg`, `historyCallArrow*` (6 tokens), `stickerPanPremium1`, `stickerPanPremium2`. Any consumer relying on `kColorizeIgnoredKeys` to determine what changes with accent will get incorrect results — `telegram_palette.dart:1148-1172,1476-1481,1500-1504,1520-1521,1637-1640`

- [ ] [MAJOR] Five token names used throughout the file do not exist anywhere in AyuGram source or `colors.palette`: `outlineButtonOutlineFg`, `dialogsForwardBg`, `dialogsForwardFg`, `mainMenuCoverFg`, `profileOtherAdminStarFg`. Verified with `grep -rn` across all of `/home/nako/Documents/AyuGramDesktop/Telegram/` returning no matches. These are invented — if the real Telegram Desktop ever exposes these palette entries, the names may clash or diverge — `telegram_palette.dart:45,75-76,221-224,261-268` ← `AyuGram/Telegram/lib_ui/ui/colors.palette` (absent)

- [ ] [MAJOR] Entire group call color section (~20 tokens) is absent from the `TelegramPalette` class: `groupCallBg`, `groupCallActiveFg`, `groupCallMembersBg`, `groupCallMembersBgOver`, `groupCallMembersBgRipple`, `groupCallMembersFg`, `groupCallMemberActiveIcon`, `groupCallMemberActiveStatus`, `groupCallMemberInactiveIcon`, `groupCallMemberInactiveStatus`, `groupCallMemberMutedIcon`, `groupCallMemberNotJoinedStatus`, `groupCallIconFg`, `groupCallLive1/2`, `groupCallMuted1/2`, `groupCallForceMuted*`, `groupCallMenuBg`, `groupCallLeaveBg`, etc. Any group call UI must hardcode colors and cannot be themed — `telegram_palette.dart:5-559` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:569-598`

- [ ] [MAJOR] `_enforceContrast()` uses a contrast ratio threshold of `3.0` (line 2187) but WCAG AA minimum for normal text is 4.5:1. The function is applied to text-on-background pairs like `activeButtonFg/activeButtonBg`, `dialogsUnreadFg/dialogsUnreadBg`, `historyUnreadBarFg/historyUnreadBarBg`, and `sideBarBadgeFg/sideBarBadgeBg` after dark-theme accent colorization. Using 3.0 means readable contrast is not guaranteed for small text — `telegram_palette.dart:2187`

# theme_file.dart audit

## CRITICAL: Missing getCrc32 import/implementation

- [x] [CRITICAL] `getCrc32()` function called in theme caching code but never imported or defined anywhere in the codebase — `theme_file.dart:1350,1359,1381,1390` ← Function does not exist. Will cause runtime crashes when caching themes.
  - Line 1350: `final contentChecksum = getCrc32(themeFileBytes);`
  - Line 1359: `paletteChecksum = getCrc32(file.content as List<int>);`
  - Line 1381: `final contentChecksum = getCrc32(themeFileBytes);`
  - Line 1390: `return getCrc32(file.content as List<int>) == cache.paletteChecksum;`
  - Related AyuGram code: `window_theme.cpp:377,388` uses `base::crc32(content.constData(), content.size())` from `base/crc32hash.h`
  - **Impact:** Theme caching will completely fail at runtime. The `buildThemeCache()`, `validateThemeCache()` functions are non-functional.

## No other structural issues found

- Palette parsing logic (lines 62-146) correctly mimics AyuGram's `ReadPaletteValues()` behavior by parsing name:value pairs with optional comments
- Theme file size limits (8-9) match AyuGram's `kThemeSchemeSizeLimit` (1 MB) and `kThemeBackgroundSizeLimit` (4 MB)  
- ZIP detection (196-201) correctly checks for ZIP magic number (0x50 0x4B 0x03 0x04)
- Color parsing (253-270) handles both RGB (#RRGGBB) and RGBA (#RRGGBBAA) formats correctly, matching AyuGram's expectations
- Background image handling (220-227) correctly looks for `background.jpg`, `background.png`, `tiled.jpg`, `tiled.png` in that priority order, matching AyuGram
- Cloud metadata parsing (172-192) correctly extracts id/hash from comment block (// THEME EDITOR SERVICE INFO START/END)
- Palette-to-map conversion (308-819) comprehensively maps all 400+ color tokens to TelegramPalette fields
- No hardcoded fake data, stubs, or placeholders detected

## Resolution

To fix: Import or implement `getCrc32()`. Options:
1. Use `package:convert` or `package:crypto` from pubspec.yaml (already available at version 3.0.6)
2. Implement CRC32 using algorithm from `base/crc32hash.h` in AyuGram
3. Import from a utilities file that should exist but doesn't

# theme_preview — Audit Findings

## Summary
Theme preview widget renders a mock Telegram UI showing dialogs and chat areas. Compared against AyuGram Desktop's `window_theme_preview.cpp`. Found layout and visual accuracy issues.

---

## Critical Issues

- [ ] **[CRITICAL]** Dialogs panel width is 260px, should be 312px — `theme_preview.dart:36` ← `media_view.style:themePreviewDialogsWidth` + `window_theme_preview.cpp:223`
  - This is a 52px deviation that breaks the layout aspect ratio and misrepresents the actual Telegram Desktop UI proportions
  - AyuGram uses `st::themePreviewDialogsWidth` which is defined as 312px in media_view.style
  - Dart hardcodes 260px, causing the entire preview to be horizontally misaligned
  - **Impact**: User sees wrong aspect ratio for dialogs panel (narrower than actual)

---

## Major Issues

- [ ] **[MAJOR]** Top bar missing three icon buttons (menu, call, search) — `theme_preview.dart:221-253` ← `window_theme_preview.cpp:534-542`
  - AyuGram paints menu icon, call icon, search icon on the right side of top bar (line 537-542)
  - Dart paints only avatar, title, and status — no icons
  - **Impact**: Preview doesn't show the actual top bar UI (missing ~3 buttons), looks incomplete

- [ ] **[MAJOR]** Compose area is simplified compared to AyuGram — `theme_preview.dart:438-470` ← `window_theme_preview.cpp:557-627`
  - Missing emoji button with proper styling (Dart draws nothing, AyuGram draws emoji button + circle outline)
  - Missing proper text field styling (AyuGram fills the field background, Dart just draws placeholder text)
  - Missing send button animation icon (AyuGram uses Lottie animation, Dart simple arrow)
  - **Impact**: Compose area looks oversimplified and doesn't match actual Telegram Desktop UI

---

## Minor/Cosmetic Issues

- [ ] **[MINOR]** Message types are simplified (no photo bubbles, no audio waveforms, no service bubbles) — `theme_preview.dart:275-327` ← `window_theme_preview.cpp:382-401`
  - AyuGram demo includes: photo bubbles, audio bubbles with waveforms, date service bubbles
  - Dart demo includes: only text bubbles with replies and check marks
  - **Note**: This may be intentional simplification for preview purposes; the Dart implementation works but shows fewer message types

- [ ] **[MINOR]** Sample data differs (intentional) — `theme_preview.dart:81-114` ← `window_theme_preview.cpp:344-376`
  - Dart sample names: "Paul", "Saved Messages", "Design Team", "Alice Cooper", etc.
  - AyuGram sample names: "Eva Summer", "Alexandra Smith", "Mike Apple", "Evening Club", etc.
  - **Note**: OK — preview sample data can differ, not a bug

---

## Design Observations

1. **Backend wiring**: ✓ Correct — this is a pure rendering preview widget with NO backend calls. Should only display TelegramPalette colors. This is intentional.

2. **Text measurement**: Uses TextPainter.layout() to estimate widths, reasonable approach for Flutter.

3. **Custom icons**: Dart draws check marks, pin icon, attach icon, send arrow using Path + Paint. These appear hand-crafted and may not match AyuGram's actual icons exactly.

4. **Palette integration**: Correctly uses TelegramPalette for colors throughout (dialogsNameFg, windowBg, msgInBg, etc.).

---

## Recommendations

1. **Fix dialogs width**: Change line 36 from `260` to `312` to match AyuGram spec
2. **Add top bar icons**: Paint menu, call, search icons on the right side of top bar
3. **Improve compose area**: Add proper emoji button styling and text field background
4. **Optional**: Add more message types (photos, audio) for more complete preview

# wallpaper — Audit findings

- [x] [CRITICAL] Default pattern intensity mismatch: Dart uses 40 (hardcoded fallback line 88, default param line 66), AyuGram uses 50 (kDefaultIntensity in data_wall_paper.h:110). When loading a wallpaper or creating one without explicit intensity, Dart will have wrong default value. — `wallpaper.dart:23,66,88` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_wall_paper.h:110`

- [x] [MAJOR] Pattern opacity calculation uses abs() incorrectly: `patternOpacity => patternIntensity.abs() / 100.0` (line 33) applies absolute value to intensity, which breaks semantic equivalence with AyuGram where patternOpacity should carry sign information for negative intensities. While this doesn't break current rendering due to line 475's intensity check, it violates the spec and could cause issues if patternOpacity is used elsewhere. — `wallpaper.dart:33` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_wall_paper.cpp:256-257` (returns `_intensity / 100.0` without abs())

- [x] [MAJOR] Fallback intensity value on URL parsing is 40 instead of 50: When parsing wallpaper URL, the default intensity if not in params is 40 (line 88), but should be 50 per AyuGram's kDefaultIntensity. This means legacy or partially-specified URLs will load with wrong intensity. — `wallpaper.dart:88` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_wall_paper.h:110, cpp:389`


# active_sessions_screen — Audit Findings

- [ ] [CRITICAL] `_classifyDevice` ignores `apiId` — AyuGram classifies devices primarily by `apiId` (e.g., apiIds {5,6,24,1026,1083,2458,2521,21724}→Android; {2040,17349,611335}→Desktop; {1,7,10840,16352}→iOS; {2496,739222,1025907}→Web), falling back to string matching only as a secondary check. Dart's `_classifyDevice` uses only string-matching on `device`/`platform`/`appName` and never reads `apiId` from the session map, producing wrong device icons/colors for all sessions where the device name lacks platform keywords (e.g., "Xiaomi Redmi" won't match "android") — `active_sessions_screen.dart:51-82` ← `AyuGram/settings/sections/settings_active_sessions.cpp:167-235`

- [ ] [CRITICAL] Missing "Official App" row in session info box — AyuGram calls `AddSessionInfoRow(container, tr::ayu_SessionInfoOfficialApp(), data.officialApp ? tr::lng_box_yes : tr::lng_box_no, st::menuIconInfo)` in every session info box. Dart's `_showSessionInfoBox` (lines 416-559) shows Application / System / IP / Location rows but has no `officialApp` row, so users can't see whether a session is from an official client — `active_sessions_screen.dart:477-511` ← `AyuGram/settings/sections/settings_active_sessions.cpp:463-467`

- [ ] [MAJOR] `_otherSessions` getter returns sessions in engine-delivery order — AyuGram explicitly sorts other sessions descending by `activeTime`: `ranges::sort(_data.list, std::greater<>(), &EntryData::activeTime)`. Dart's getter at line 134-136 applies no sort, so the most recently active session may appear anywhere in the list — `active_sessions_screen.dart:134-136` ← `AyuGram/settings/sections/settings_active_sessions.cpp:787`

- [ ] [MAJOR] Chrome/Edge detection order is wrong — AyuGram's `detectBrowser()` checks `"edg/"`, `"edgios/"`, `"edga/"` strings before checking `"chrome"` because modern Edge Chromium user-agents contain "Chrome". Dart checks `a.contains('chrome')` at line 56 before `a.contains('edge')` at line 57, causing Edge sessions to be misclassified as Chrome (wrong icon and gradient color) — `active_sessions_screen.dart:56-58` ← `AyuGram/settings/sections/settings_active_sessions.cpp:179-191`

- [ ] [MAJOR] Session row location line missing IP fallback — AyuGram's `LocationAndDate()` uses `entry.location.isEmpty() ? entry.ip : entry.location` so the list row always shows at least the IP address. Dart builds `locationLine` from `location` only (line 950-953); when `location` is empty the location segment is blank and only the date is shown — `active_sessions_screen.dart:949-953` ← `AyuGram/settings/sections/settings_active_sessions.cpp:160-165`

- [ ] [MAJOR] Session info box big userpic missing Lottie animation — AyuGram's `GenerateUserpicBig()` loads a per-device-type `.lottie` file (`device_desktop_win.lottie`, `device_phone_android.lottie`, etc.) and plays it once the box is shown, giving the userpic animated life. Dart's `_DeviceUserpic` is a static gradient circle with a Material `IconData`; no animation is played — `active_sessions_screen.dart:1024-1045` ← `AyuGram/settings/sections/settings_active_sessions.cpp:297-322`

- [ ] [MAJOR] Current session section header shows wrong text — AyuGram uses `tr::lng_sessions_header()` ("Current Session") as the subsection title at line 929-931. Dart shows the hardcoded string `'This device'` (line 694), which is a different label not matching the official Telegram UI — `active_sessions_screen.dart:694-699` ← `AyuGram/settings/sections/settings_active_sessions.cpp:929-931`

- [ ] [MAJOR] `_buildOtherSessionsList` footer text is wrong — AyuGram shows `tr::lng_sessions_about_apps()` ("You can log in to Telegram from multiple platforms simultaneously") after the active sessions list. Dart shows `'Interrupted login attempts and sessions on other devices that haven't been confirmed will appear here.'` (line 846-847), which is the text for the incomplete-sessions section (`lng_sessions_incomplete_about`), not for active sessions — `active_sessions_screen.dart:843-851` ← `AyuGram/settings/sections/settings_active_sessions.cpp:990`

- [ ] [MAJOR] Empty sessions state uses wrong widget — AyuGram renders `tr::lng_sessions_other_desc()` as a `Ui::FlatLabel` with `st::boxDividerLabel` style (a subdued inline text, no icon). Dart's `_buildEmptyPlaceholder` shows a large centered column with a `Icons.security` icon and "No other active sessions" text (lines 890-906), a completely different layout and different string — `active_sessions_screen.dart:890-906` ← `AyuGram/settings/sections/settings_active_sessions.cpp:1014-1021`

# admin_tools — Placeholders, missing wiring, and behavioral inaccuracies

## _EditPeerInfoBox

- [ ] [CRITICAL] "Set Photo" and "Set Video" menu items do nothing — `_showPhotoMenu` handler at `admin_tools.dart:308` only handles `'remove'`; `value == 'set'` and `value == 'set_video'` branches are absent. No file picker is opened, no `editChatPhoto` / `setChatPhoto` engine call is made. Photo upload is completely non-functional. ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:806` (uploads via `StickersBox` / `photos::UploadProfilePhoto`)

- [ ] [CRITICAL] Photo removal only updates local state — `_avatarRemoved = true` is set at `admin_tools.dart:310` but `_onSave()` at `admin_tools.dart:599` never calls any engine method to remove the photo. `engine.removeChatPhoto` / `editChatPhoto(null)` does not exist in `engine_service.dart` and is never called. Removing the photo visually resets the UI but the server photo is unchanged. ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:2843` (sends `MTPchannels_EditPhoto`)

- [ ] [CRITICAL] "Discussion Group / Linked Channel" row is an empty stub — `admin_tools.dart:379`: `onTap: () {}`. AyuGram opens `EditDiscussionLinkBox` which calls `channels.GetGroupsForDiscussion` then lets the user pick a discussion group. No engine method for this exists and no dialog is shown. ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:901` (`Controller::showEditDiscussionLinkBox`)

- [ ] [CRITICAL] "Visible History" row is an empty stub — `admin_tools.dart:388`: `onTap: () {}`. AyuGram opens `EditPeerHistoryVisibilityBox` and saves via `channels.TogglePreHistoryHidden`. No engine method exists in `engine_service.dart`. ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1330` (`Controller::fillHistoryVisibilityButton`)

- [ ] [CRITICAL] "Topics" row is an empty stub — `admin_tools.dart:397`: `onTap: () {}`. While `engine.toggleForum` exists in engine_service (`engine_service.dart:1847`), the Topics row never calls it. ← `AyuGram/boxes/peers/toggle_topics_box.cpp`

- [ ] [CRITICAL] "Auto-Translation" toggle is an empty stub with hardcoded OFF state — `admin_tools.dart:408`: `onTap: () {}`. The `_EditRow` with `isToggle: true` renders `Switch(value: false, ...)` always at `admin_tools.dart:1382`. Neither the current auto-translate state is loaded from the engine, nor is any toggle call made. No `toggleAutoTranslate` method exists in `engine_service.dart`. ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1213` (`Controller::fillAutoTranslateButton`)

- [ ] [CRITICAL] "Sign Messages" toggle is an empty stub with hardcoded OFF state — `admin_tools.dart:416`: `onTap: () {}`. Same `Switch(value: false)` issue. Current sign-messages state is not loaded, toggle is never called. No `toggleSignMessages` exists in `engine_service.dart`. ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1286`

- [ ] [CRITICAL] "Add Stickers" row is an empty stub — `admin_tools.dart:563`: `onTap: () {}`. AyuGram opens `StickersBox` to pick a sticker set and saves via `channels.SetStickers`. No engine method for setting a group sticker set exists in `engine_service.dart`. ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:829` (`createStickersEdit`)

- [ ] [MAJOR] `_EditRow` with `isToggle: true` always renders `Switch(value: false, ...)` — `admin_tools.dart:1382`. Both the Auto-Translation and Sign Messages rows use `isToggle: true` but the switch is hardcoded to `false` and never reflects real state. Even if the group has sign messages enabled, the toggle always shows OFF. ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1286` (reads `channel->addsSignature()`)

- [ ] [MAJOR] `_EditPeerInfoBoxState._descCtrl` is pre-filled from `getUserProfile` instead of `getChatFullInfo` — `admin_tools.dart:71`. For groups/channels, the description lives in `ChatFull.about`, not in a user profile bio. Calling `getUserProfile` on a group/channel ID may silently fail or return wrong data. ← `AyuGram/boxes/peers/edit_peer_info_box.cpp` (reads `peer->asChannel()->about()` from channel full)

- [ ] [MAJOR] Description save skips when field is empty — `admin_tools.dart:615`: `if (newDesc.isNotEmpty)` means you cannot clear an existing description by emptying the field. AyuGram always sends the description on save, even if empty string, to allow clearing it. ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:saveDescription()` (unconditional save)

## _EditAdminBox

- [ ] [CRITICAL] Existing admin rights are never loaded when editing an existing admin — `_EditAdminBoxState.initState()` at `admin_tools.dart:2074` always initializes all flags to `enabled = true` regardless of the member's current rights. When opening the box for an existing admin, all permissions appear fully granted. No engine call fetches the current admin's actual rights. No `getMemberAdminRights` method exists in `engine_service.dart`. ← `AyuGram/boxes/peers/edit_participant_box.cpp` (loads existing rights from `participant->adminRights()`)

- [ ] [CRITICAL] Transfer Ownership is a toast-only stub — `admin_tools.dart:2231`: `showTelegramToast(context, 'Transfer ownership requires 2FA verification')`. AyuGram requires an actual 2FA password dialog flow to confirm transfer (`ChannelOwnershipTransfer::requestPassword`). The stub shows a toast and does nothing; ownership is never actually transferred. ← `AyuGram/boxes/peers/channel_ownership_transfer.cpp:79` (`requestPassword()`)

- [ ] [MAJOR] "Promoted by" link in admin box taps do nothing — `admin_tools.dart:2569`: `onTap: () {}`. AyuGram navigates to the promoter's profile. ← `AyuGram/boxes/peers/edit_participant_box.cpp` (shows `PrepareShortInfoBox` for promoter)

## _EditRestrictedBox

- [ ] [CRITICAL] Existing banned rights are not loaded for the specific member — `_EditRestrictedBoxState._loadDefaults()` at `admin_tools.dart:1501` calls `engine.getDefaultBannedRights(...)` (group defaults) instead of fetching the individual member's current banned rights. When editing a restricted user, the UI shows group defaults, not what that user is actually banned from. ← `AyuGram/boxes/peers/edit_participant_box.cpp` (loads from `participant->bannedRights()`)

## _AdminLogScreen / _AdminLogFilterDialog

- [ ] [CRITICAL] Admin log filter checkboxes are completely ignored — `_AdminLogFilterDialog._checks` map is built and shown at `admin_tools.dart:3292`, but the `onApply` callback at `admin_tools.dart:3354` just calls `_loadEvents()` without passing any filter flags. `engine.getAdminLogEvents(...)` signature at `engine_service.dart:2054` has no `filters` parameter, so filter selections are never sent to the backend. Every "Apply" reloads all events regardless of checked filters. ← `AyuGram/history/admin_log/history_admin_log_inner.cpp:456` (`applyFilter` sends `MTPChannelAdminLogEventsFilter` flags)

- [ ] [MAJOR] Admin log date badge `_currentDateLabel` is updated only in `_buildDateSeparator` (called during build) but read in the floating overlay — `admin_tools.dart:2965`. During scroll the label may be stale because `_currentDateLabel` is only updated when the list rebuilds, not on every scroll tick. The badge shows the wrong date while scrolling. ← `AyuGram/history/admin_log/history_admin_log_inner.cpp` (date label updated in scroll handler)

## _MemberTabBody

- [ ] [CRITICAL] "Add to Banned / Add Exception / Add Admin" button is a toast-only stub — `admin_tools.dart:4796`: `showTelegramToast(ctx, 'Select a user...')`. No user-picker dialog is opened. Clicking "Add Admin" or "Add Exception" in the member tabs shows a toast instead of a contact/search selector. ← `AyuGram/boxes/peers/edit_participants_box.cpp` (opens `AddParticipantsBoxController` or `AddBotToGroupBoxController`)

## _InviteLinksBox

- [ ] [MAJOR] "Share" button copies to clipboard instead of sharing — `admin_tools.dart:3776` and `admin_tools.dart:4179`: both Share buttons call `Clipboard.setData(...)` with toast "Link copied to clipboard". On desktop this is acceptable but on mobile it should open the share sheet. No platform share intent is used. ← `AyuGram/boxes/peers/edit_peer_invite_links.cpp` (uses `QApplication::clipboard` on desktop, share sheet on mobile)

# advanced_settings_screen — Audit Findings

## Critical: Backend Wiring

- [ ] [CRITICAL] `_AutoDownloadBox` Save button discards all changes — the "Save" button only calls `Navigator.of(context).pop()` and never writes `_photos`, `_files`, `_downloadLimit`, `_videoMessages`, `_videos`, `_gifs`, `_autoPlayLimit` to AppState or the engine — `advanced_settings_screen.dart:1462` ← `auto_download_box.cpp:211` (`_session->saveSettingsDelayed()`)

- [ ] [CRITICAL] `_AutoDownloadBox` ignores persisted settings and always opens with hardcoded defaults (`_photos = true`, `_files = false`, `_videoMessages = true`, etc.) instead of reading current session auto-download settings — `advanced_settings_screen.dart:1326-1333` ← `auto_download_box.cpp:99` (`_session->settings().autoDownload()`)

- [ ] [CRITICAL] `_LocalStorageBox` is entirely non-functional: `_tagSizes` is initialized to all-zeros and never populated from actual disk cache, so "All data" always shows "0 B", "Clear All" is permanently disabled, and the OK button discards all slider changes without writing to AppState or triggering any real cache eviction — `advanced_settings_screen.dart:1575,1703,1735-1743,1824` ← `settings_chat.cpp:1871` (`LocalStorageBox::Show(controller)`)

- [ ] [CRITICAL] Proxy list is never loaded from AppState — `_proxies` is always initialized empty; any proxy entries added during a session are lost when the dialog is closed and reopened — `advanced_settings_screen.dart:2195` ← `connection_box.cpp` (ProxiesBoxController loads from `Core::App().settings().proxy()`)

- [ ] [CRITICAL] Proxy IPv6 toggle (`_ipv6`) is hardcoded to `false` and never read from or written back to AppState when the dialog is accepted — `advanced_settings_screen.dart:2193` ← `core_settings_proxy.cpp:115` (IPv6 is serialized as part of proxy settings)

- [ ] [CRITICAL] Proxy-for-calls toggle (`_proxyForCalls`) is hardcoded to `false` and never loaded from or persisted to AppState — `advanced_settings_screen.dart:2194` ← `core_settings_proxy.cpp` (proxyForCalls serialized with proxy state)

- [ ] [CRITICAL] Proxy connectivity status is never tested — all entries permanently remain at `_ProxyStatus.checking` ("Checking...") with `pingMs = 0`; no ping or reachability check is performed — `advanced_settings_screen.dart:2167,2543` ← `connection_box.cpp:2279` (`ProxiesBoxController::refreshChecker()`)

- [ ] [CRITICAL] Proxy QR code dialog shows a generic Material icon (`Icons.qr_code`) instead of a real generated QR code bitmap — the QR code feature is a visual stub — `advanced_settings_screen.dart:2732-2733` ← `connection_box.cpp:215` (actual QR image is generated and drawn)

## Major: Behavior

- [ ] [MAJOR] "Update UniClient" button calls `exit(0)` instead of applying a downloaded update and restarting — AyuGram calls `Core::checkReadyUpdate()` before exit so the updater applies the patch on next launch — `advanced_settings_screen.dart:246` ← `settings_advanced.cpp:1481` (`Core::checkReadyUpdate()`)

- [ ] [MAJOR] Window close behavior radio options include label "Quit Telegram" — should say "Quit UniClient" or "Quit" — `advanced_settings_screen.dart:532` ← `settings_advanced.cpp:398` (`tr::lng_settings_quit_on_close`)

# bridge_stub — No issues found

## Summary

Audited `dart/lib/bridge/bridge_stub.dart` against the `BridgeImpl` interface specification from `bridge.dart` and reference implementations in `bridge_ffi.dart` and `bridge_web.dart`.

## Findings

**Status:** ✅ PASS

The stub bridge implementation is correctly designed and implemented:

1. **Interface Compliance** — All required methods present with correct signatures:
   - `events` getter: `Stream<Uint8List>` ✓
   - `isInitialized` getter: `bool` ✓
   - `init({String? libraryPath})`: `void` ✓
   - `call(Uint8List)`: `Uint8List` ✓
   - `callAsync(Uint8List)`: `Future<Uint8List>` ✓
   - `dispose()`: `void` ✓

2. **Appropriate Stub Behavior** — Correctly fails-safe:
   - Operations that would require working backend (`init`, `call`, `callAsync`) throw `UnsupportedError` with descriptive message
   - Query methods (`events`, `isInitialized`) return safe sentinel values (empty stream, false)
   - `dispose()` is a no-op, which is correct since the stub allocates no resources

3. **Error Handling** — All error paths are explicit:
   - `init()`: throws `UnsupportedError` with message "No bridge implementation available for this platform"
   - `call()`: throws same error
   - `callAsync()`: throws same error
   - Prevents silent failures or masked errors

4. **Resource Management** — `dispose()` is safe:
   - Correctly a no-op since stub doesn't allocate resources (no streams to close, no library handles to free)
   - Safe to call multiple times
   - Matches pattern in conditional implementations

## Conditional Import System

The stub functions correctly as the fallback in `bridge.dart` (line 9):
```dart
import 'bridge_stub.dart'
    if (dart.library.ffi) 'bridge_ffi.dart'
    if (dart.library.js_interop) 'bridge_web.dart' as impl;
```

This ensures that:
- On native platforms with FFI support: `bridge_ffi.dart` is used ✓
- On web with WASM: `bridge_web.dart` is used ✓
- On any other platform: `bridge_stub.dart` fails explicitly ✓

## Conclusion

This is a well-implemented fallback bridge that correctly documents its stub status and fails fast with clear error messages if the conditional import system fails. No code changes required.

# auth_screen — Auth Screen Audit

- [ ] [CRITICAL] Reset Account confirm button is a no-op — pops dialog but makes no engine/backend call to actually delete the account — `auth_screen.dart:372-374` ← `intro_widget.cpp:547` (`MTPaccount_DeleteAccount`)

- [ ] [CRITICAL] "Forgot Password" → recovery mode toggle sets `_isRecoveryMode = true` locally but never calls `MTPauth_RequestPasswordRecovery` to actually send the recovery email to the user — `auth_screen.dart:764-766` ← `intro_password_check.cpp:307-312`

- [ ] [CRITICAL] OTP call-back countdown reaches zero and sets `_calling = true` locally, showing "Calling..." indefinitely, but never fires any resend/call API request through the engine — `auth_screen.dart:1444-1446` ← `intro_code.cpp:307-313` (`MTPauth_ResendCode`)

- [ ] [CRITICAL] "Didn't get the code?" dialog shows static informational text only — "Edit Phone Number" goes back to phone, "OK" closes; no resend code is triggered. AyuGram wires this to `MTPauth_ResendCode` — `auth_screen.dart:137-175` ← `intro_code.cpp:440-454`

- [ ] [CRITICAL] Signup avatar bytes are picked and stored in `_signupAvatarBytes` but `authState.submitInput('$firstName\n$lastName')` never includes or uploads them; photo is silently dropped — `auth_screen.dart:127` ← `intro_signup.cpp:30-34` (UserpicButton handles upload)

- [ ] [MAJOR] `_CoverGradient` renders only a single offset send-icon and gradient; AyuGram cover requires: title label at `introCoverTitleTop=136px`, description label at `introCoverDescriptionTop=174px`, left scatter icon (`introLeft`), and right scatter icon (`introRight`) — `auth_screen.dart:1255-1298` ← `intro.style:38,47,16-17`

- [ ] [MAJOR] Language picker dialog calls `addRecentLanguage` and closes, but never applies the selected language to the UI — no equivalent of `Lang::CurrentCloudManager().switchToLanguage()` is called — `auth_screen.dart:2049-2052` ← `intro_widget.cpp:282`

# ayu_appearance_page — Audit Findings

- [ ] [CRITICAL] Section order is wrong: App Icon section is placed last in Dart but must be first per C++ (`BuildAppIcon` is called first in `kMeta`) — `ayu_appearance_page.dart:188-193` ← `settings_appearance.cpp:387-388`

- [ ] [CRITICAL] `hideNotificationBadge` toggle is placed under "Chat Folders" section in Dart but belongs inside `BuildAppIcon` (the App Icon section) in C++ — `ayu_appearance_page.dart:80-86` ← `settings_appearance.cpp:66-81`

- [ ] [CRITICAL] Font selector shows a hardcoded list of 11 preset fonts instead of dynamically loading all system fonts via `QFontDatabase::families()` — users cannot select any installed font not in the preset list — `ayu_appearance_page.dart:564-568` ← `font_selector.cpp:204-219`

- [ ] [CRITICAL] Font selector has no search/filter input — C++ uses `Ui::MultiSelect` with live full-text search across all font rows — `ayu_appearance_page.dart:592-695` ← `font_selector.cpp:894-939`

- [ ] [CRITICAL] Font selector does not show a restart dialog after applying a font change — C++ calls `Core::Restart()` confirm box on save and on reset — `ayu_appearance_page.dart:697-700` ← `font_selector.cpp:857-869`

- [ ] [CRITICAL] Font selector missing "Reset" button — C++ has `addLeftButton(tr::ayu_BoxActionReset(), ...)` that resets font to empty and triggers restart — `ayu_appearance_page.dart:673-689` ← `font_selector.cpp:871-888`

- [ ] [CRITICAL] App icon picker renders icons with a `CustomPainter` drawing fake shapes instead of loading real icon preview images via `AyuAssets::loadPreview(iconName)` — visual output is completely incorrect — `ayu_appearance_page.dart:764-769` ← `icon_picker.cpp:117`

- [ ] [CRITICAL] App icon picker does not apply the selected icon to the OS — C++ calls `applyIcon()` which updates the taskbar icon, system tray, and app icon via `Window::OverrideApplicationIcon` and `Core::App().refreshApplicationIcon()` — `ayu_appearance_page.dart:746` ← `icon_picker.cpp:42-52,177-181`

- [ ] [CRITICAL] Avatar corners preview click opens `xdg-open` in a browser (Linux-only) instead of navigating to the channel in-app via `showPeerByLink` — `ayu_appearance_page.dart:430` ← `avatar_corners_preview.cpp:97-100`

- [ ] [CRITICAL] Drawer elements order is wrong: C++ puts LRead (`showLReadToggleInDrawer`) and SRead (`showSReadToggleInDrawer`) before Night Mode and Ghost Mode; Dart reverses this, placing Night Mode/Ghost Mode at lines 153–163 then LRead/SRead at lines 165–175 — `ayu_appearance_page.dart:153-175` ← `settings_appearance.cpp:336-363`

- [ ] [MAJOR] Avatar corners preview is missing the official badge icon (`st::dialogsExteraOfficialIcon`) that C++ draws next to the "AyuGram Releases" name — `ayu_appearance_page.dart:456-462` ← `avatar_corners_preview.cpp:72-73`

- [ ] [MAJOR] Avatar corners preview status text is "Preview of avatar corners" in Dart but must be "Better late than never" per C++ — `ayu_appearance_page.dart:464` ← `avatar_corners_preview.cpp:77`

- [ ] [MAJOR] Avatar corners preview height is hardcoded to 62 px in Dart but C++ derives it from `st::defaultDialogRow.height` (a theme-aware style constant) — `ayu_appearance_page.dart:434` ← `avatar_corners_preview.cpp:35`

# ayu_chats_page — Audit Findings

## Critical Issues

### 1. [CRITICAL] Wide Multiplier Slider — Wrong Minimum Value
- **Issue**: Minimum value is 0.5, should be 1.0
- **Location**: `ayu_chats_page.dart:322` ← `AyuGramDesktop/ayu/ui/settings/settings_chats.cpp:241`
- **Detail**: The C++ code defines `constexpr auto kMinSize = 1.00;` (line 241), but the Dart slider uses `min: 0.5`. This allows users to set values below the valid range (1.0–4.0). The slider snaps with `(v * 20).round() / 20.0`, but starting from 0.5 is mathematically incorrect.
- **Impact**: Users can set invalid wide multiplier values (0.5, 0.55, 0.60, etc.) that the C++ engine will reject or behave unexpectedly with.

### 2. [CRITICAL] Wide Multiplier Slider — Wrong Divisions
- **Issue**: Divisions set to 70, should be 60
- **Location**: `ayu_chats_page.dart:324` ← `AyuGramDesktop/ayu/ui/settings/settings_chats.cpp:277`
- **Detail**: C++ formula: `(4.00 - 1.00) / 0.05 = 60` steps, so `steps = 61` (line 277). Dart uses `divisions: 70`, which is incorrect. Even with the wrong min value, 70 divisions across 3.5 units (0.5–4.0) gives ~0.05 per step by coincidence, but the range is wrong.
- **Impact**: Slider granularity doesn't match C++ expectations.

### 3. [CRITICAL] Message Preview Settings Not Editable
- **Issue**: Settings like `replaceMarksWithIcons`, `semiTransparentDeleted`, `deletedMark`, `editedMark` are passed to the preview widget but NOT exposed as editable controls on the page
- **Location**: `ayu_chats_page.dart:107-117` (passed to `_BubbleRadiusSection` but never shown as toggles/buttons)
- **Reference**: `AyuGramDesktop/ayu/ui/settings/settings_chats.cpp:154-227` (all exposed as toggle/button controls)
- **Detail**: The C++ page has:
  - Line 154–160: `addSettingToggle` for "Replace marks with icons"
  - Line 162–197: `addButton` controls for deleted/edited mark editing
  - Line 199–204: `addSettingToggle` for "Remove message tail"
  - Line 206–211: `addSettingToggle` for "Hide share button"
  - Line 213–218: `addSettingToggle` for "Simple quotes and replies"
  - Line 221–230: `addSettingToggle` for "Semi-transparent deleted messages" + beta badge
  
  The Dart page only shows toggles for:
  - Line 118–123: "Remove message tail"
  - Line 124–129: "Simple quotes and replies"
  
  **Missing**: "Replace marks with icons" toggle, deleted/edited mark buttons, "Hide share button" toggle, "Semi-transparent deleted messages" toggle
- **Impact**: Users cannot modify these settings from the Chats page; the settings are read-only for preview purposes but not editable.

### 4. [CRITICAL] Missing "Hide Share" Button Toggle
- **Issue**: The "Hide side Share button" setting exists in AppState but is never exposed as a toggle in the page
- **Location**: `ayu_chats_page.dart` (no control; should be added)
- **Reference**: `AyuGramDesktop/ayu/ui/settings/settings_chats.cpp:206-211`
- **Detail**: In C++, line 207 shows the setting ID is `ayu/hideFastShare`. AppState has `hideFastShare` property (confirmed in earlier grep), but there's no toggle for it on the page.
- **Impact**: Setting exists but is inaccessible from the UI.

### 5. [CRITICAL] Missing "Semi-transparent Deleted Messages" Toggle  
- **Issue**: The `semiTransparentDeleted` setting is not exposed as an editable toggle on the page
- **Location**: `ayu_chats_page.dart` (no control; should be added)
- **Reference**: `AyuGramDesktop/ayu/ui/settings/settings_chats.cpp:221-230`
- **Detail**: C++ adds a toggle + beta badge (line 221–230). Dart passes the value to preview but doesn't allow editing.
- **Impact**: Setting is read-only for preview, not editable.

### 6. [CRITICAL] Missing "Replace Marks with Icons" Toggle
- **Issue**: The `replaceMarksWithIcons` setting is not exposed as an editable toggle on the main page
- **Location**: `ayu_chats_page.dart` (no control; should be added)
- **Reference**: `AyuGramDesktop/ayu/ui/settings/settings_chats.cpp:154-160`
- **Detail**: C++ adds this as the first toggle in the message settings section (line 154–160).
- **Impact**: Setting affects preview but cannot be changed from this page.

### 7. [CRITICAL] Missing Deleted/Edited Mark Edit Buttons
- **Issue**: No button controls to edit `deletedMark` and `editedMark` strings
- **Location**: `ayu_chats_page.dart` (no controls; should be added)
- **Reference**: `AyuGramDesktop/ayu/ui/settings/settings_chats.cpp:162-197`
- **Detail**: C++ provides two button controls (line 162–178 for deleted mark, line 180–195 for edited mark) that open edit dialogs. These launch `EditMarkBox` to let users customize the text.
- **Impact**: Users cannot edit the marks; they're hardcoded and only visible in the preview.

### 8. [CRITICAL] Section Order Mismatch — Bubble Radius Before Wide Multiplier
- **Issue**: Bubble radius slider comes before wide multiplier slider in Dart, but should come after other message options
- **Location**: `ayu_chats_page.dart:102-117` vs `ayu_chats_page.dart:107-117`
- **Reference**: `AyuGramDesktop/ayu/ui/settings/settings_chats.cpp:235-294` (called after BuildMarks, so after tail/share/quotes toggles)
- **Detail**: 
  - C++ order: preview → replace marks → marks buttons → remove tail → hide share → simple quotes → [THEN] bubble radius → wide multiplier
  - Dart order: wide multiplier slider → bubble radius section with preview → remove tail → simple quotes
  
  The C++ code calls `BuildMarks()` (which includes preview and toggles) first (line 466), then `BuildWideMessagesMultiplier()` (line 467), which builds the bubble radius and wide multiplier sliders. So sliders come AFTER the toggles, not before.
- **Impact**: UI layout doesn't match AyuGram Desktop reference implementation.

---

## Summary

**Blocker issues preventing this page from being feature-complete:**
1. Wide multiplier slider: min=0.5 (should be 1.0), divisions=70 (should be 60)
2. Six message customization settings missing from the page (not editable, only used in preview)
3. Section ordering doesn't match the reference implementation

**Status**: This page is **NOT usable**. Users cannot:
- Set valid wide multiplier values
- Edit message mark text
- Toggle "Replace marks with icons"
- Toggle "Hide share button"
- Toggle "Semi-transparent deleted messages"

All these controls exist in AppState but are not exposed in the UI.

# ayu_filters_page — Audit Findings

- [ ] [CRITICAL] `_ShadowBanRow` hardcodes "User $id" as display name instead of resolving the actual peer name from session data — `ayu_filters_page.dart:851` ← `per_dialog_filter.cpp:35-40` (`PerDialogFiltersListRow::generateName()` calls `getPeerFromDialogId()` and falls back to `"UNKNOWN (ID: %1)"` only when peer is unresolved)

- [ ] [CRITICAL] `_ShadowBanRow` always shows the letter 'U' in the avatar (`const Text('U', ...)`) — never attempts peer lookup for a real userpic — `ayu_filters_page.dart:843` ← `per_dialog_filter.cpp:43-58` (`generatePaintUserpicCallback` calls `getPeerFromDialogId` and only falls back to empty userpic with 'U' when the peer cannot be resolved at all)

- [ ] [CRITICAL] Import applies changes immediately without showing the confirmation/summary dialog — AyuGram shows `MakeConfirmBox` with a full change summary (new filters count, removed filters, updated filters, new exclusions, removed exclusions, dialogs to resolve) before applying anything — `ayu_filters_page.dart:1183-1218` ← `filters_utils.cpp:417-432`

- [ ] [CRITICAL] Import does not process `removeFiltersById`, `removeExclusions`, or `peers` fields from the backup JSON — only adds filters and exclusions, cannot sync deletions or resolve peer hints — `ayu_filters_page.dart:1192-1218` ← `filters_utils.cpp:786-855`

- [ ] [CRITICAL] Export JSON is missing `removeFiltersById`, `removeExclusions`, and `peers` fields — AyuGram always emits all five top-level keys (`version`, `filters`, `exclusions`, `removeFiltersById`, `removeExclusions`, `peers`) for cross-version compatibility — `ayu_filters_page.dart:1232-1237` ← `filters_utils.cpp:457-530`

- [ ] [MAJOR] New filter `caseInsensitive` defaults to `false` — AyuGram defaults `caseInsensitive = true` for every new filter — `ayu_filters_page.dart:900` ← `edit_filter.cpp:143`

- [ ] [MAJOR] Regex validation uses Dart's built-in `RegExp` engine — AyuGram validates and executes with the ICU `icu::RegexPattern::compile` engine (supports full ICU regex including lookaheads, Unicode categories, etc.) — a pattern accepted by Dart `RegExp` may be rejected by the ICU engine at runtime and vice versa — `ayu_filters_page.dart:913-921` ← `edit_filter.cpp:57-99`

- [ ] [MAJOR] Select-chat dialog only iterates `chatState.chats` (locally cached list) — AyuGram uses `Window::ShowChooseRecipientBox` with `InlineBots::PeerType` flags (Bot | Group | Broadcast) enabling full peer search with network resolution for any peer — `ayu_filters_page.dart:165-230` ← `settings_filters.cpp:196-217`

- [ ] [MAJOR] After saving a new shared filter from within a per-dialog context, AyuGram shows an action toast ("Shown in [dialog]? Tap to restrict") letting the user immediately scope the new filter to that dialog — not implemented in Dart — `ayu_filters_page.dart:933-960` ← `edit_filter.cpp:220-239`

# ayugram_settings_screen — Audit Findings

- [ ] [CRITICAL] Logo renders Material icon stub instead of actual PNG/SVG app icon assets. C++ calls `AyuAssets::currentAppLogoPad()` which loads `:/gui/art/ayu/{name}/app.svg` or `app.png` from bundled resources and renders them into the logo area. Dart uses `_iconForTheme(selectedIcon)` (e.g. `Icons.send`, `Icons.headphones`) displayed in a solid-color circle — no real image asset is loaded at all. — `ayugram_settings_screen.dart:74-79` ← `ayu/ui/settings/settings_main.cpp:41-65` + `ayu/ui/ayu_logo.cpp:42-92`

- [ ] [CRITICAL] Channel and Chat link buttons open an external browser (via `xdg-open`) instead of navigating to the peer within the app. C++ uses `controller->showPeerByLink(Window::PeerByLinkInfo{.usernameOrId = QString("ayugram")})` — the channel/group opens as an in-app chat. Dart calls `_openUrl('https://t.me/ayugram')` → `Process.run('xdg-open', [url])` which launches the system browser. — `ayugram_settings_screen.dart:189,196` ← `ayu/ui/settings/settings_main.cpp:149-164`

- [ ] [CRITICAL] `_openUrl` uses `Process.run('xdg-open', [url])` which is Linux-only and silent-fails on Windows/macOS. C++ uses `QDesktopServices::openUrl()` which is cross-platform for all four external link buttons (Crowdin, Documentation, and the mis-wired Channel/Chat). — `ayugram_settings_screen.dart:245-247` ← `ayu/ui/settings/settings_main.cpp:172-184`

- [ ] [MAJOR] AyuGram category button shows "Ghost Mode active" as a dynamic subtitle when ghost mode is on. The original C++ `addSectionButton` has no subtitle field — section buttons in `BuildCategories` display only their title. This is an invented UI element not present in the reference. — `ayugram_settings_screen.dart:129` ← `ayu/ui/settings/settings_main.cpp:103-107`

# ayu_other_page — Audit Findings

- [ ] [CRITICAL] All 5 crypto donation addresses are truncated to 8–9 characters, generating invalid QR codes and showing wrong addresses — `ayu_other_page.dart:38` (`UQA4i8U3`), `:46` (`bc1qdk6qq`), `:54` (`0x405589`), `:62` (`8ZHQpPxp`), `:70` (`TRpbajq3`) ← `settings_other.cpp:154-158` (full addresses: `UQA4i8U8vP3mYUZSV3KqDQEHPwmhninEqCkkKc7BITQ652de`, `bc1qdk6qq4mzq5yap3fpy0qau3246w3m3uwac9f0xd`, `0x405589857C8DFAb45B2027c68ad1e58877FDa347`, `8ZHQpPxpsdRjsWoBcF1dmvRM5dB6zEhJ3jMBFZjYfyHs`, `TRpbajq38qU8joThgAfKJLyEPbNjzsdPJ1`)

- [ ] [CRITICAL] "Register URL Scheme" button is a stub — shows SnackBar("Done") but never calls any URL scheme registration; AyuGram calls `Core::Application::RegisterUrlScheme()` which registers `tg://` and `tdesktop://` schemes with the OS — `ayu_other_page.dart:100-105` ← `settings_other.cpp:204-207`

- [ ] [CRITICAL] QR dialog missing copy-to-clipboard button — AyuGram's QR box has a full-width "Copy" button that copies the address to clipboard and shows a toast; Dart only shows `SelectableText` with no copy affordance — `ayu_other_page.dart:305-379` ← `donate_qr_box.cpp:148-158`

- [ ] [CRITICAL] QR code missing crypto icon in the center — AyuGram renders the relevant SVG icon (e.g., `donates/ton.svg`) embedded at the center of the QR code via `MakeQrWithIcon`; Dart uses a plain `QrImageView` with no icon — `ayu_other_page.dart:344-353` ← `donate_qr_box.cpp:31-66`

- [ ] [CRITICAL] Donate button icons are text/emoji placeholder characters (`'B'`, `'💎'`, `'₿'`, `'Ξ'`, `'S'`, `'T'`) — AyuGram loads real SVG icons from `:/gui/icons/ayu/donates/{name}.svg`; no SVG donation icon assets exist in `dart/assets/` — `ayu_other_page.dart:27-67` ← `settings_other.cpp:52-57`

- [ ] [CRITICAL] "Contact support" link opens `tg://support` via `xdg-open` (system URL handler, likely opens another Telegram app or does nothing) — AyuGram intercepts `tg://support` internally via `HandleSupport` to show the `FillDonateInfoBox` (donation amounts from RC Manager, proof submission steps, badge info) — `ayu_other_page.dart:297` ← `ayu_url_handlers.cpp:133-142`

- [ ] [MAJOR] QR dialog title shows the crypto name ("TON", "Bitcoin", etc.) instead of the proper "QR Code" title — `ayu_other_page.dart:332` ← `donate_qr_box.cpp:79` (`tr::lng_group_invite_context_qr()`)

# ayu_section_builder — Audit Findings

- [ ] [CRITICAL] `addBetaBadge(text)` is a standalone row widget unattached to any button — AyuGram's `AddBetaBadge` takes a `not_null<Button*>` and attaches the badge as a child widget INSIDE the button row, positioned right after the button text via `fullTextWidth()`. There is no standalone badge section in AyuGram. — `ayu_section_builder.dart:102-123` ← `AyuGram/ayu/ui/settings/settings_ayu_utils.cpp:47-75`

- [ ] [CRITICAL] Beta badge background color is orange (`Color(0xFFFF9500)`) in both the standalone `addBetaBadge` and inline `showBetaBadge` toggle — AyuGram uses `p.setBrush(st::windowBgActive)` (accent blue). — `ayu_section_builder.dart:111,211` ← `AyuGram/ayu/ui/settings/settings_ayu_utils.cpp:62`

- [ ] [CRITICAL] `_AyuChooseButton` uses an inline Flutter `DropdownButton<int>` — AyuGram renders a settings button with a right-aligned label showing the current selection, which on click opens a modal `SingleChoiceBox` dialog. These are entirely different interaction patterns. — `ayu_section_builder.dart:346-363` ← `AyuGram/ayu/ui/settings/settings_ayu_utils.cpp:494-536`

- [ ] [MAJOR] `addSectionTitle` padding is `fromLTRB(22, 14, 22, 6)` — AyuGram `defaultSubsectionTitlePadding` is `margins(22px, 7px, 10px, 9px)` (top 7 not 14, right 10 not 22, bottom 9 not 6). Top padding is 2× too large, right padding is 2× too large. — `ayu_section_builder.dart:23` ← `AyuGram/Telegram/lib_ui/ui/layers/layers.style:155`

- [ ] [MAJOR] `addSectionTitle` uses `FontWeight.w500` (medium) — AyuGram `defaultSubsectionTitle` uses `semibold` font weight. — `ayu_section_builder.dart:26` ← `AyuGram/Telegram/lib_ui/ui/layers/layers.style:149-151`

- [ ] [MAJOR] `addSectionDivider` renders only `divider + skip` — AyuGram `AddSectionDivider` / `AyuSectionBuilder::addSectionDivider` uses `skip + divider + skip` (three items, with skip both before and after the divider line). — `ayu_section_builder.dart:125-132` ← `AyuGram/ayu/ui/settings/settings_ayu_utils.cpp:635-638` and `ayu_builder.cpp:263-267`

- [ ] [MAJOR] Standalone `addBetaBadge` padding is `horizontal:6, vertical:2` — AyuGram `ayuBetaBadgePadding` is `margins(4px, 1px, 4px, 1px)`. Horizontal is 50% too large, vertical is 2× too large. — `ayu_section_builder.dart:109` ← `AyuGram/ayu/ui/ayu_styles.style:119`

- [ ] [MAJOR] `_AyuCollapsibleToggle` shows a small 8×8 dot when any child is checked — AyuGram's collapsible toggle renders a dynamic `"N/M"` count label (bold, e.g. "3/5") appended to the button title, updating live as checkboxes change. — `ayu_section_builder.dart:435-444` ← `AyuGram/ayu/ui/settings/settings_ayu_utils.cpp:229-242`

- [ ] [MAJOR] `_AyuCollapsibleToggle` and `AyuNestedCheckboxItem` have no lock support — AyuGram implements Shift+click per-checkbox locking: locked checkboxes are dimmed to 0.4 opacity and ignored by the master toggle. `AyuNestedCheckboxItem` is missing `lockGetter`/`lockSetter` fields entirely. — `ayu_section_builder.dart:153-162,370-388` ← `AyuGram/ayu/ui/settings/settings_ayu_utils.cpp:380-418`

# ayu_toggle — Toggle switch widget audit

## Reference Implementation
- **AyuGram Source**: `/home/nako/Documents/AyuGramDesktop/Telegram/lib_ui/ui/widgets/checkbox.cpp` (ToggleView class)
- **AyuGram Style**: `/home/nako/Documents/AyuGramDesktop/Telegram/lib_ui/ui/widgets/widgets.style` (defaultToggle definition)

## Comparison: ayu_toggle.dart vs AyuGram ToggleView

### Dimensions & Colors

- [ ] [CRITICAL] Track height mismatch — `ayu_toggle.dart:62` MD3 track height is 18px vs AyuGram default toggle uses `diameter + 2*border` (typically 18-20px depending on border width). `ayu_toggle.dart:68` iOS track height is 20px. **Need to verify these match AyuGram's actual rendering at 1:1 pixel precision** — compare against AyuGram Desktop reference UI screenshots. — `ayu_toggle.dart:61-70` ← `widgets.style:defaultToggle`

- [ ] [MAJOR] Thumb diameter mismatch — `ayu_toggle.dart:63` MD3 thumb is 14px vs AyuGram `diameter: 14px` ✓ matches. `ayu_toggle.dart:69` iOS thumb is 16px (not defined in standard AyuGram, custom variant). — `ayu_toggle.dart:63,69` ← `widgets.style:defaultToggle diameter`

- [ ] [MAJOR] Track width values not validated — `ayu_toggle.dart:61` MD3 width 32px, `ayu_toggle.dart:67` iOS width 36px. AyuGram style defines `width: 14px` (this is the EXTRA width beyond diameter for the sliding space). The Dart widths (32-36px total) appear to include the full track + thumb space, but need verification against actual AyuGram rendering. — `ayu_toggle.dart:61,67` ← `widgets.style:defaultToggle width`

- [ ] [MAJOR] Color interpolation — `ayu_toggle.dart:88-91` uses `windowBgActive` for active color and hardcoded grayscale (0xFF5A6A78 dark, 0xFFCBCBCB light) for inactive. AyuGram uses `toggledFg`, `untoggledFg`, `toggledBg`, `untoggledBg` (4 colors). Dart only uses 2 colors. **Background track color is being interpolated, but AyuGram also animates the border/pen color** — missing second color pair for border animation. — `ayu_toggle.dart:88-91` ← `checkbox.cpp:145-146` (ToggleView::paint pen animation)

### Animation & Curves

- [ ] [MAJOR] Curve mismatch — `ayu_toggle.dart:77` uses `Curves.easeOutCubic` for Material, `Curves.linear` for iOS. AyuGram's checkbox.cpp doesn't explicitly specify curve in the ToggleView class. **Need to check what animation curve AyuGram ToggleView uses** (likely `anim::linear` or default). Dart's easeOutCubic is NOT verified against AyuGram. — `ayu_toggle.dart:77` ← `checkbox.cpp:ToggleView::paint` (animation setup, line ~157)

- [ ] [MINOR] Duration consistency — `ayu_toggle.dart:35-36` uses 150ms (MD3) and 120ms (iOS). AyuGram defines `duration: 150` in style. Dart iOS variant is 120ms (non-standard). — `ayu_toggle.dart:35-36` ← `widgets.style:defaultToggle duration: 150`

### Material Design 3 Animation Padding

- [ ] [MAJOR] animPadding logic — `ayu_toggle.dart:94-96` reduces thumb diameter by `md3AnimPad * 2 * (1-t)` during toggle animation (thumb shrinks while animating). AyuGram does the same at `checkbox.cpp:144` (ayuToggleAnim interpolates from `_st->animPadding` to 0). **Implementation matches** ✓ — `ayu_toggle.dart:94-96` ← `checkbox.cpp:144-145`

### Visual Rendering Structure

- [ ] [MAJOR] Thumb positioning — `ayu_toggle.dart:98-99` calculates thumb position as `baseLeft + (thumbD - diam) / 2`. In the inactive state (t=0), thumb is at `inset + (thumbD - diam) / 2` (centered). In active state (t=1), thumb moves to `inset + (trackW - thumbD - 2*inset) + (thumbD - diam) / 2` (right side). This is equivalent to AyuGram's `toggleLeft = left + anim::interpolate(0, fullWidth - SwitchDiameter(_st), toggled)` at `checkbox.cpp:139`. **Positioning logic is equivalent** ✓ — `ayu_toggle.dart:98-99` ← `checkbox.cpp:139`

- [ ] [CRITICAL] White thumb hardcoded — `ayu_toggle.dart:121` thumb color is `Colors.white` (hardcoded). AyuGram's ToggleView at `checkbox.cpp:146` draws the thumb with colors animated from `_st->untoggledBg` to `_st->toggledBg`. **In dark mode or non-standard themes, white thumb will NOT be visible on dark track.** This is a rendering bug. — `ayu_toggle.dart:121` ← `checkbox.cpp:146` (brush animation: `anim::brush(_st->untoggledBg, _st->toggledBg, toggled)`)

- [ ] [CRITICAL] Missing border stroke — `ayu_toggle.dart:102-129` has no border drawn. AyuGram's ToggleView at `checkbox.cpp:147-149` draws a pen/border with width `_st->border` and color animating from `untoggledFg` to `toggledFg`. **Dart toggle is missing the outer border/stroke entirely.** This is a visual regression. — `ayu_toggle.dart:102-129` ← `checkbox.cpp:147-149`

- [ ] [MAJOR] Icon/lock icon support — AyuGram's ToggleView at `checkbox.cpp:150-159` optionally draws a lock icon or X→V animation inside the thumb if `_locked || _st->xsize > 0`. Dart implementation has NO support for locked state or icons. **Not a critical bug (Telegram desktop rarely uses locked toggles), but a feature gap.** — N/A in Dart ← `checkbox.cpp:150-159`

### Animation Calculation

- [ ] [MAJOR] Curve application — `ayu_toggle.dart:86` applies curve via `curve.transform(_controller.value)` before all calculations. AyuGram applies curve inside the Abstract class via `anim::linear` in the animation setup. **Verify that easeOutCubic in Dart matches AyuGram's actual curve.** — `ayu_toggle.dart:86` ← `checkbox.cpp:AbstractCheckView` animation setup (check Animations::Simple implementation for default curve)

### Wiring & Backend

- [ ] [OK] Callback wired — `ayu_toggle.dart:82` calls `widget.onChanged?.call(!widget.value)`. This is correct delegation to parent. ✓

- [ ] [OK] State sync — `ayu_toggle.dart:39-48` updates animation controller when `widget.value` changes. Correct implementation of `didUpdateWidget`. ✓

### Summary of Issues

**CRITICAL (rendering bugs):**
1. White thumb color hardcoded — will be invisible on dark toggled state or custom themes
2. Missing border/pen stroke around the thumb — visual regression vs AyuGram

**MAJOR (possible visual deviations):**
1. Track and thumb dimensions not verified against pixel-perfect AyuGram rendering
2. Only 2 colors used instead of 4 (missing border color animation)
3. Animation curve (easeOutCubic) not verified against AyuGram

**MINOR (non-critical deviations):**
1. iOS variant uses 120ms duration (not in standard AyuGram)
2. No support for locked state or icons (AyuGram feature not needed for Telegram)


# call_panel — Audit Findings

## call_panel — Controls not wired to engine

- [ ] [CRITICAL] Mute button is an empty stub — `onTap: () {}` does nothing; no engine call to mute/unmute the microphone — `call_panel.dart:553` ← `calls/calls_panel.cpp:389-392` (`_call->setMuted(!_call->muted())`)

- [ ] [CRITICAL] Add People button is an empty stub — `onTap: () {}` does nothing; should open invite/conference box — `call_panel.dart:558` ← `calls/calls_panel.cpp:425-457` (`Group::PrepareInviteBox` / `startOrJoinConferenceCall`)

- [ ] [CRITICAL] Screen share handler never calls the engine — `_onScreenShareTap` selects a source then exits with only a comment; no engine call to start/stop sharing — `call_panel.dart:206-215` ← `calls/calls_panel.cpp:394-417` (`_call->toggleScreenSharing(deviceId, withAudio)`)

- [ ] [CRITICAL] Camera toggle handler never calls the engine — `_onCameraTap` checks permission then exits with only a comment; no engine call to enable/disable camera — `call_panel.dart:217-221` ← `calls/calls_panel.cpp:419-423` (`_call->toggleCameraSharing(!_call->isSharingCamera())`)

- [ ] [CRITICAL] `showCallPanel` wires `onAccept` to an empty lambda — the answer button does nothing instead of calling the engine to answer the incoming call — `call_panel.dart:1503` ← `calls/calls_panel.cpp:481-482` (`_call->answer()`)

- [ ] [CRITICAL] Device selector menu result is always discarded — `showMenu<String>()` return value is never `.then()`'d, so selecting "Default Camera" or "Default Microphone" has no effect — `call_panel.dart:226-237` ← `calls/calls_panel.cpp:1044-1049` (`showDevicesMenu` → `setCameraDeviceId`)

## call_panel — Fingerprint emoji table wrong

- [ ] [CRITICAL] Encryption fingerprint uses a wrong, custom 100-emoji table — AyuGram defines a specific 329-entry table (the canonical Telegram fingerprint emoji set) from which emojis are picked by `value % kEmojiCount` using the SHA-256 of the encryption key; the Dart widget uses a 100-emoji set of modern face/animal emojis chosen randomly — `call_panel.dart:1099-1120` ← `calls/calls_emoji_fingerprint.cpp:34-89,121,165`

## call_panel — Call duration not synced from engine

- [ ] [MAJOR] Call duration timer resets to 0 on every state transition to `active` — the Dart widget runs `_durationSeconds = 0` on each `active` state start and counts seconds locally; it should read the actual elapsed call time from the engine so resuming a call mid-session shows the correct duration — `call_panel.dart:192-198` ← `calls/calls_panel.cpp:460-463` (`_call` provides `getWaitingSoundPeakValue` / duration; `updateDurationText` reads from call object)

# call_screen — Group call panel, minimised call bar, screen-share chooser

- [ ] [CRITICAL] `showGroupCallPanel` passes `onToggleMute`, `onToggleVideo`, `onOpenMenu` as `null` — all three callbacks are unset, so the mute button, video button, and menu button in the panel do nothing — `call_screen.dart:933-970` ← `calls/group/calls_group_panel.cpp:573-601` (mute), `:755` (video), `:535` (hangup wiring)

- [ ] [CRITICAL] Screen-share result is never forwarded to the engine — `showGroupCallPanel` calls `showScreenShareChooser(ctx)` without `await` and discards the returned `ScreenShareSource?`; no FFI bridge call for `toggleScreenSharing` is ever made — `call_screen.dart:963` ← `calls/group/calls_group_panel.cpp:367-374` (`_call->toggleScreenSharing(deviceId, withAudio)`)

- [ ] [CRITICAL] Desktop-capture enumeration uses ad-hoc shell commands instead of tgcalls `DesktopCaptureSourceManager` — Dart calls `xrandr`, `wmctrl`, `kdotool` via `Process.run`; AyuGram calls `tgcalls::DesktopCaptureSourceManager(Type::Screen)` and `tgcalls::DesktopCaptureSourceManager(Type::Window)` — `call_screen.dart:1591-1693` ← `calls/group/ui/desktop_capture_choose_source.cpp:451-504`

- [ ] [CRITICAL] Screen-share thumbnails are static file paths, not live video frames — AyuGram creates a `tgcalls::DesktopCaptureSourceHelper` + `Webrtc::VideoTrack` per source and renders the live first frame; Dart shows a `FileImage(thumbnailPath)` or a placeholder icon with no live capture — `call_screen.dart:2000-2016` ← `calls/group/ui/desktop_capture_choose_source.cpp:133-246`

- [ ] [CRITICAL] `GroupCallPanel` duration counter always starts at 0, no call-start-time parameter — users joining an ongoing call see "00:00"; `MinimisedCallBar` has `callStartTime` but `GroupCallPanel` does not — `call_screen.dart:57,62-63` ← `calls/calls_top_bar.cpp:733-750` (duration from real `call->getDurationMs()`)

- [ ] [CRITICAL] No blob animation below the minimised call bar — AyuGram's `TopBar::initBlobsUnder` creates `Ui::Paint::LinearBlobs` (3 blobs, segments 5/7/8) that render below the bar and react to `group->levelUpdates()`; Dart `MinimisedCallBar` has no such blob widget — `call_screen.dart:1012-1243` ← `calls/calls_top_bar.cpp:444-580`

- [ ] [MAJOR] `GroupCallPanel` default height 540 px ≠ AyuGram `groupCallHeight: 520px` — `call_screen.dart:47` ← `calls/calls.style:546`

- [ ] [MAJOR] `_BigMuteButton` blob radii are wrong — Dart uses `_blobMinRadius = 28`, `_blobMaxRadius = 33`; AyuGram style defines `callMuteMinorBlobMinRadius: 64px`, `callMuteMinorBlobMaxRadius: 74px`, `callMuteMajorBlobMinRadius: 67px`, `callMuteMajorBlobMaxRadius: 77px` — `call_screen.dart:717-718` ← `calls/calls.style:324-327`

- [ ] [MAJOR] Force-muted tap shows no toast — AyuGram shows `tr::lng_group_call_force_muted_sub` toast when a force-muted user taps the mute button; Dart `_CallBarMuteButton` silently disables the tap with `onTap: isForceMuted ? null : onTap` and `_BigMuteButton` calls `widget.onTap` regardless of force-mute state — `call_screen.dart:1265` ← `calls/calls_top_bar.cpp:296-303`

- [ ] [MAJOR] Hangup in group call bar has no admin leave-or-end dialog — AyuGram checks `group->canManage()` and shows `Group::LeaveBox` for admins; Dart `_CallBarHangupButton` always calls `onHangup` directly with no dialog — `call_screen.dart:1496-1519` ← `calls/calls_top_bar.cpp:424-439`

- [ ] [MAJOR] `_CallBarState` has no `RaisedHand` case — AyuGram's `BarStateFromMuteState` maps `MuteState::RaisedHand` → `BarState::ForceMuted`; Dart `_resolveBarState()` has no raised-hand branch, so a raised-hand participant is incorrectly shown as active or muted — `call_screen.dart:1079-1087` ← `calls/calls_top_bar.cpp:61-74`

- [ ] [MAJOR] Recording dot minimum opacity 0.3 ≠ AyuGram `kRecordingOpacity = 0.6` — Dart animates `0.3 + 0.7 * value` (range 0.3–1.0); AyuGram animates between `kRecordingOpacity (0.6)` and `1.0` — `call_screen.dart:669` ← `calls/group/calls_group_panel.cpp:80-81,1324-1327`

- [ ] [MAJOR] `_BlobPainter.shouldRepaint` unconditionally returns `true` — repaints every vsync even when level/radius/blob state is unchanged; should compare fields — `call_screen.dart:636` ← (performance regression, no AyuGram equivalent)

- [ ] [MAJOR] `_BigMuteButton` label shows "Unmute" for `forceMuted` state with no visual distinction — AyuGram's `CallMuteButton` shows a distinct "Raise Hand" / forced-mute type; Dart uses a simple ternary `unmuted ? 'Mute' : 'Unmute'` which gives force-muted users the same "Unmute" text as self-muted — `call_screen.dart:852-853` ← `calls/group/calls_group_panel.cpp:891-910`

# calls_screen — Audit Findings

## Critical Stubs & Broken Backend Wiring

- [ ] [CRITICAL] `_CallHistoryRow` primary `onTap: () {}` is a complete stub — clicking a call history row does nothing. AyuGram's `BoxController::rowClicked` navigates to the peer's chat history at the exact call message ID (`window->showPeerHistory(peer, ClearStack, itemId)`). — `calls_screen.dart:1933` ← `AyuGram/calls/calls_box_controller.cpp:600-610`

- [ ] [CRITICAL] "Share Link" button in `_ConferenceCallLinkBox` calls `Navigator.of(context).pop()` — just closes the dialog instead of invoking the OS share sheet with the link. — `calls_screen.dart:1483` ← `AyuGram/calls/calls_box_controller.cpp:800` (PrepareCreateCallBox wires invite link to share)

- [ ] [CRITICAL] "Join this call yourself" link calls `Navigator.of(context).pop()` — closes dialog without joining the conference call. Should trigger `engine.joinGroupCall` or equivalent to actually enter the call the user just created. — `calls_screen.dart:1518` ← `AyuGram/calls/calls_box_controller.cpp:800-802`

- [ ] [CRITICAL] "Open system sound preferences" row has empty `onTap: () {}`. AyuGram calls `Platform::OpenSystemSettings(SystemSettingsType::Audio)` which launches the OS audio settings (pavucontrol on Linux, System Preferences on Mac). — `calls_screen.dart:2224` ← `AyuGram/settings/sections/settings_calls.cpp:411-425`

- [ ] [CRITICAL] Device picker in `_showDevicePicker` only lists `['Default']` — hardcoded, never queries the engine for real audio or video devices. The engine has no `getAudioDevices`/`getVideoDevices`/`getCameraDevices` method at all, making the entire Output/Input/Camera device selection UI non-functional. — `calls_screen.dart:2241` ← `AyuGram/settings/sections/settings_calls.cpp:57-70` (uses `Core::App().mediaDevices().devicesValue(type)` for live device list)

- [ ] [CRITICAL] `_acceptCalls` toggle stores only local state (`bool _acceptCalls = true`) and is never persisted or sent to any engine method. AyuGram calls `authorizations->toggleCallsDisabledHere(!value)` which makes an `account.updateDeviceLocked` API call. Toggling the switch here has zero effect on actual incoming call delivery. — `calls_screen.dart:2109,2211` ← `AyuGram/settings/sections/settings_calls.cpp:392-408`

- [ ] [CRITICAL] `_useSameDevices` toggle stores only local state and is never persisted. AyuGram reads `settings->callPlaybackDeviceId().isEmpty() && settings->callCaptureDeviceId().isEmpty()` as the initial state and on toggle calls `settings->setCallPlaybackDeviceId/setCallCaptureDeviceId` with `Core::App().saveSettingsDelayed()`. No engine call wires this setting. — `calls_screen.dart:2108,2182` ← `AyuGram/settings/sections/settings_calls.cpp:245-275`

- [ ] [CRITICAL] `_outputDevice`, `_inputDevice`, `_cameraDevice` fields are local state never saved to settings or sent to the engine. Selecting a device in the picker updates the label only; the actual audio routing is unchanged. There is no `engine.setOutputDevice`/`setInputDevice`/`setCameraDevice` call anywhere in the file. — `calls_screen.dart:2105-2107,2150-2200` ← `AyuGram/settings/sections/settings_calls.cpp:83-89,104-112`

## Major Issues

- [ ] [MAJOR] `_InputLevelMeter` uses a fake looping animation (`level: _controller.value * 0.35`) instead of real microphone capture. AyuGram instantiates `Webrtc::AudioInputTester` with the selected capture device, polls it every `kMicTestUpdateInterval` ms via `base::Timer`, and feeds the real PCM level into the meter. — `calls_screen.dart:2559` ← `AyuGram/settings/sections/settings_calls.cpp:113-151`

- [ ] [MAJOR] `_confcallSizeLimit` is hardcoded to `200` in two places. AyuGram reads the limit from `controller->session().appConfig().confcallSizeLimit()` which is a server-side value fetched from `help.getAppConfig`. If the server raises or lowers the limit, the Dart UI will be wrong. — `calls_screen.dart:711,873` ← `AyuGram/calls/calls_box_controller.cpp:785-787`

# chat_export — Backend wiring is entirely simulated; no engine calls

- [ ] [CRITICAL] `_startExport` runs a fake `Timer.periodic` loop that simulates progress with hardcoded speed increments — it never calls `AccountInitTakeoutSession`, never reads from the Go bridge, and produces no real export data — `chat_export.dart:677-688` ← `export_view_panel_controller.cpp:204-207` (`_process->startExport(*_settings, PrepareEnvironment(_session))`)

- [ ] [CRITICAL] `_skipCurrentFile` advances the local step index in the Dart widget only — it never calls `_process->skipFile(randomId)` on the backend, so files cannot actually be skipped — `chat_export.dart:766-774` ← `export_view_panel_controller.cpp:314-317` (`_process->skipFile(randomId)`)

- [ ] [CRITICAL] `AccountInitTakeoutSession` and `AccountFinishTakeoutSession` are both skipped in the bridge dispatch table with comment "complex external types" — the bridge layer has no callable entry point for starting or finishing a real takeout session — `go/bridge/dispatch_gen.go:18707` and `go/bridge/dispatch_gen.go:18914`

- [ ] [CRITICAL] Progress tracking (`_tickExport`, `_totalFiles`, `_totalSizeBytes`) is fully fabricated: `step.progress` advances by a deterministic formula `0.02 + 0.01 * _currentStepIndex`, file count increments by `10 + _currentStepIndex * 5`, and size grows by `(512 + _currentStepIndex * 256) * 1024` — none of these values come from the engine — `chat_export.dart:717-739` ← `export_controller.cpp:100-108` (real counters: `_messagesWritten`, `_userpicsWritten`, `_storiesWritten`, etc.)

- [ ] [CRITICAL] `_bringPanelToFront` is a `// no-op` stub — AyuGram calls `_panel->showAndActivate()` when the user taps the top-bar during processing — `chat_export.dart:690-692` ← `export_view_panel_controller.cpp:163-167` (`activatePanel()` → `_panel->showAndActivate()`)

- [ ] [MAJOR] Default settings mismatch: Dart initialises `_botChats = false`, `_stories = true`, `_profileMusic = true`, `_privateChannels = false`, `_publicGroups = false`, `_publicChannels = false` — AyuGram defaults (`Settings::DefaultTypes()`) include `PersonalInfo | Userpics | Contacts | Stories | ProfileMusic | PersonalChats | PrivateGroups` — meaning `_stories` and `_profileMusic` match but `_contacts` should default to `true` (it does), while `_privateChannels` and `_publicGroups`/`_publicChannels` correctly default to `false`; however `_sessions = false` and `_otherData = false` are correct — the only mismatch is `_botChats = false` while AyuGram `DefaultFullChats()` includes `PersonalChats | BotChats` (fullChats field governs "export full messages", not types, so this is not a direct mismatch but types do not include `BotChats` in defaults either — this is actually correct) — `chat_export.dart:302-329` ← `export_settings.h:105-118`

- [ ] [MAJOR] Default media size limit is `sizeLimit = 8 * 1024 * 1024` (8 MB = index 7 in the slider, 0-based) in AyuGram; Dart uses `_sizeSliderPos = 7` which maps to `_sizeLimitMB` returning `8` MB — this appears correct, but the slider range is `0..99` in Dart and `kSizeValueCount` in AyuGram — `kSizeValueCount` is never defined in the files read, so the slider upper bound may differ — `chat_export.dart:325` ← `export_view_settings.cpp:89-112`

- [ ] [MAJOR] `_openExportFolder` uses `Process.run('xdg-open', [path])` which launches asynchronously and ignores errors — AyuGram uses `File::ShowInFolder(finished->path)` which is the platform-specific "reveal in file manager" call; more importantly, the Dart code opens the folder on button press in the completed phase, but the folder path it opens is `_exportLocation` (the user-chosen destination), which was never actually written to because no real export ran — `chat_export.dart:542-551` ← `export_view_panel_controller.cpp:327-331`

- [ ] [MAJOR] The `skipFile` button is shown after a 5-second timer identical to AyuGram's `kShowSkipFileTimeout = 5 * crl::time(1000)`, but the skip action advances a local progress counter instead of passing a `randomId` to the backend — in AyuGram, `skipFileClicks` emits the `_fileRandomId` of the current row which is a real server-assigned ID — `chat_export.dart:756-763` ← `export_view_progress.cpp:284-287` (`return _skipFile->entity()->clicks() | rpl::map([=] { return _fileRandomId; })`)

- [ ] [MAJOR] The completed phase shows "Total files: N" and "Total size: X" where both values were incremented by the fake timer loop — these numbers are meaningless since no real export ran — `chat_export.dart:2076-2080` ← `export_view_panel_controller.cpp:326-330` (real completion: `FinishedState` with actual `path`)

- [ ] [MAJOR] `_exportLocation` is saved to a local JSON file via `_saveExportSettings()` but AyuGram persists settings through `_session->local().writeExportSettings(settings)` (MTProto account storage) — the two persistence mechanisms are not equivalent; on reinstall or account switch the local JSON path will be stale or missing — `chat_export.dart:487-519` ← `export_view_panel_controller.cpp:417-429`

- [ ] [MAJOR] The processing view shows only the last 3 steps (startIdx = activeIdx − 2) — AyuGram's `ProgressWidget` keeps all rows and fades out old ones using animated opacity, not a sliding window — `chat_export.dart:1906-1913` ← `export_view_progress.cpp:315-352` (all rows kept, old rows fade out)

- [ ] [MAJOR] `_triggerTakeoutInvalidError`, `_triggerTakeoutInitDelayError`, `_triggerDiskError`, and `_triggerGenericApiError` are dead code — no engine event wires into them because the export is fully simulated; they will never be called in normal app flow — `chat_export.dart:777-824`

# chat_list_panel — Audit Findings

## chat_list_panel — Stub actions, wrong methods, fake data

- [ ] [CRITICAL] "Edit Folder" context menu item is a `break` stub — pressing it does nothing. `showEditFolderBox` is already imported at line 23 and used elsewhere (line 4136); the handler just needs `showEditFolderBox(context, folder!)` — `chat_list_panel.dart:2324` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/dialogs_inner_widget.cpp` (tab context-menu opens filter editor)

- [ ] [CRITICAL] "Edit Folders" context menu item is a `break` stub — pressing it does nothing. Should navigate to `FoldersSettingsScreen` (exists at `folders_settings_screen.dart:92`) — `chat_list_panel.dart:2330` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/dialogs_inner_widget.cpp` (tab context-menu "setup filters" navigates to filters screen)

- [ ] [CRITICAL] Drag-to-filter drop handler only calls `debugPrint` and never adds the chat to the folder. The drop at `_onReorderPointerUp` resolves `folderId` correctly but then discards it with a debug print instead of calling an engine method — `chat_list_panel.dart:1075` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/dialogs_inner_widget.cpp` (drag-to-filter drop adds chat to folder via `chatFilters().editFilter(…)`)

- [ ] [CRITICAL] "Public Posts" search tab does not perform a real search. It only filters the already-loaded local chat list to channels (`results.where((c) => c.type == ChatType.channel)`). In Telegram Desktop this tab triggers `messages.searchPosts` — a separate API call that returns messages across all public channels — `chat_list_panel.dart:494-496` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/dialogs_search_posts.cpp:172` (`PostsSearch::requestSearch` calls `MTPresult messages.SearchGlobal` / `messages.search` with posts flag)

- [ ] [CRITICAL] `_TopPeersStrip` uses fake data. It builds top-peers from the locally cached DM chat list sorted by `lastMsgTime`. Real top peers come from `contacts.getTopPeers` (server-ranked by frequency). The local sort produces a different (wrong) list — `chat_list_panel.dart:2452-2458` ← `AyuGramDesktop/Telegram/SourceFiles/data/components/top_peers.cpp:186` (`TopPeers::request` calls `MTPcontacts_GetTopPeers`)

- [ ] [CRITICAL] `SwipeAction.read` swipe calls `chatState.markRead()` — the no-argument method that reads the currently **active** chat's last message, not the swiped chat. Should call `chatState.markChatRead(chat.accountId, chat.chatId)` — `chat_list_panel.dart:933-934` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_peer_menu.cpp:693` (`MarkAsReadThread(thread)` called on the specific thread, not the active one)

- [ ] [CRITICAL] `SwipeAction.unread` swipe calls `chatState.markRead()` — marks the active chat as **read** instead of marking the swiped chat as unread. There is no `markChatUnread` method in `ChatState`; this entire action is unwired — `chat_list_panel.dart:935-936` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_peer_menu.cpp:697` (`changeDialogUnreadMark(history, true)` marks the specific dialog as unread)

- [ ] [CRITICAL] Context menu "Mark as Unread" action does nothing. The `case 'read':` handler only fires when `chat.unreadCount > 0` (mark as read path). When `unreadCount == 0` the menu label shows "Mark as Unread" but the if-guard skips execution — there is no else branch to call `changeDialogUnreadMark` — `chat_list_panel.dart:1417-1420` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_peer_menu.cpp:697` (`changeDialogUnreadMark(history, true)`)

- [ ] [CRITICAL] Reaction tag context menu "Remove tag" action is silently dropped. The `.then()` handler only checks for `'edit'` and `'filter'`; `'remove'` falls through with no call. No `removeSavedReactionTag` method exists in `ChatState` — `chat_list_panel.dart:5301-5307` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/dialogs_search_tags.h` (`SearchTags` handles tag removal via `messages.removeSavedReactionTag` RPC)

# chat_list_row — Audit findings

- [ ] [CRITICAL] `_isSavedMessages` detected by hardcoded English title string `'Saved Messages'`; breaks for any non-English locale or user-renamed chat — `chat_list_row.dart:985` ← `AyuGramDesktop/SourceFiles/data/data_peer.cpp:1606` (`isSelf()`)

- [ ] [CRITICAL] `_TopicJumpBubble` has no `onTap`; tapping it falls through to `ForumChatListRow.onTap` which opens the whole forum — never navigates to the specific unread topic as AyuGram does via `pressedTopicJumpRootId` — `chat_list_row.dart:1967` ← `AyuGramDesktop/SourceFiles/dialogs/dialogs_inner_widget.cpp:5236`

- [ ] [CRITICAL] Poll unread badge entirely absent — `ChatListRow` only renders mention and reaction icon badges; AyuGram renders a third badge for `badgesState.poll` — `chat_list_row.dart:280` ← `AyuGramDesktop/SourceFiles/dialogs/ui/dialogs_layout.cpp:273`

- [ ] [CRITICAL] `_TypingDotsIndicator` hardcodes the label `"${userName} typing"` for every send-action type; AyuGram renders 10+ distinct strings (RecordVoice, UploadPhoto, UploadVideo, RecordRound, ChooseSticker, etc.) from `SendActionPainter` — `chat_list_row.dart:1267` ← `AyuGramDesktop/SourceFiles/history/view/history_view_send_action.cpp:271`

- [ ] [CRITICAL] `ForumChatListRow` row header has no unread-count badge, pinned icon, or mention/reaction/poll badges — the right column of the forum group row is empty; AyuGram's `RowPainter::Paint` applies the same badge painting path to forum rows — `chat_list_row.dart:1814` ← `AyuGramDesktop/SourceFiles/dialogs/ui/dialogs_layout.cpp:225`

- [ ] [CRITICAL] `_HoverBuilder` tracks hover state but `isHovered` is never referenced inside the builder lambda — unread badge "Over" colors (`dialogsUnreadBgOver`, `dialogsUnreadBgMutedOver`) are never applied on hover — `chat_list_row.dart:99` ← `AyuGramDesktop/SourceFiles/dialogs/dialogs.style:76` (dialogsUnreadFont / Over states)

- [ ] [MAJOR] Online badge shows/hides instantly; AyuGram animates it over `dialogsOnlineBadgeDuration: 150ms` — `chat_list_row.dart:1059` ← `AyuGramDesktop/SourceFiles/dialogs/dialogs_row.cpp:207`, `dialogs.style:148`

- [ ] [MAJOR] `ForumChatListRow` forum-group title uses `fontSize: 14` while `ChatListRow` uses 13 — AyuGram's `forumDialogRow` inherits `defaultDialogRow` with no font-size override; both rows should use `semiboldFont` at the same size — `chat_list_row.dart:1825` ← `AyuGramDesktop/SourceFiles/dialogs/dialogs.style:107`

# chat_settings_screen — Audit Findings

- [ ] [CRITICAL] `_useSystemAccent` checkbox updates only local state — never calls `appState.setSystemAccent()` or any engine method; toggling it has zero effect — `chat_settings_screen.dart:234` ← `settings/sections/settings_chat.cpp:2544-2548` (`settings.setSystemAccentColorEnabled(checked)`)

- [ ] [CRITICAL] `_fontFamily` is local state only — `_ChooseFontBox` calls `onFontSelected` which does `setState(() => _fontFamily = f)` but never persists to `appState` or any engine call; font is reset on every rebuild — `chat_settings_screen.dart:307` ← `settings/sections/settings_chat.cpp:2875-2879` (`settings->setCustomFontFamily(chosen); Local::writeSettings(); Core::Restart()`)

- [ ] [CRITICAL] Cloud theme `'edit'` context menu item is an empty stub — `case 'edit': break;` does nothing; AyuGram should open a theme editor — `chat_settings_screen.dart:1969-1970` ← `settings/sections/settings_chat.cpp:876-890` (cloud theme edit flow)

- [ ] [CRITICAL] Cloud theme `'delete'` shows fake toast without any engine call — `showTelegramToast(context, 'Theme deleted')` runs with no `engine.deleteCloudTheme(...)` invocation; theme is never actually deleted — `chat_settings_screen.dart:1993-1997` ← `settings/sections/settings_chat.cpp:876-890`

- [ ] [CRITICAL] "My Stickers" and "Emoji Sets" navigation buttons are missing from `_StickersEmojiSection` — `_StickerNavButton` widget class is defined but never instantiated anywhere in `_StickersEmojiSection.build()`; AyuGram has two nav buttons after the checkboxes — `chat_settings_screen.dart:2693-2789` ← `settings/sections/settings_chat.cpp:1553-1582` (`stickersButton` → `StickersBox`, `emojiSetsButton` → `ManageSetsBox`)

- [ ] [MAJOR] "Double-click React" option has no reaction chooser — Dart shows a static `Icon(Icons.favorite)` as trailing; AyuGram adds a `buttonRight` circle button that opens `ReactionsSettingsBox` so the user can pick which reaction to use — `chat_settings_screen.dart:3011-3015` ← `settings/sections/settings_chat.cpp:1676-1766`

- [ ] [MAJOR] Font selection in `_ChooseFontBox` is not applied — pressing "Apply" calls `widget.onFontSelected(_selected)` which sets local state but there is no `Core::Restart()` equivalent or any mechanism to actually switch the app font — `chat_settings_screen.dart:1750` ← `settings/sections/settings_chat.cpp:2877-2878`

- [ ] [MAJOR] `_SettingsCheckbox` uses `vertical: 6` padding instead of spec's 10px — `EdgeInsets.symmetric(vertical: 6)` vs `settingsCheckboxPadding: margins(22px, 10px, 10px, 10px)`; affects Tile Background and Adaptive Layout checkboxes — `chat_settings_screen.dart:2313` ← `settings/sections/settings_chat.cpp` style `settingsCheckboxPadding`

- [ ] [MAJOR] "Choose from gallery" opens OS file picker instead of Telegram's background browser — `_pickFromGallery()` calls `FilePicker.platform.pickFiles(type: FileType.image)` (local file); AyuGram's gallery opens `Box<BackgroundBox>(controller)` — a full Telegram wallpaper browser with online content — `chat_settings_screen.dart:101-104` ← `settings/sections/settings_chat.cpp:476-478`

- [ ] [MAJOR] Background thumbnail shows no radial loading indicator — `_ChatBackgroundSection` renders the thumbnail statically; AyuGram's `BackgroundRow` has a `Ui::RadialAnimation` that displays while a wallpaper is downloading/applying — `chat_settings_screen.dart:2163-2184` ← `settings/sections/settings_chat.cpp:494-542`

# chat_switch_overlay — Audit Findings

## chat_switch_overlay — Account/chat switch overlay (Ctrl+Tab)

- [ ] [CRITICAL] Arrow Up/Down keys navigate linearly (prev/next) instead of row-based (±shownPerRow). AyuGram: Up → `_selected - _shownPerRow` (wrapping), Down → `_selected + _shownPerRow` (wrapping). Dart maps both arrowDown and arrowRight to `_moveNext()` and both arrowUp and arrowLeft to `_movePrev()`, which is completely wrong for multi-row grids. — `chat_switch_overlay.dart:86-93` ← `window/window_chat_switch_process.cpp:267-272`

- [ ] [CRITICAL] Layout algorithm missing two row-reduction safety conditions. AyuGram: when `_shownRows > 2` and `_shownPerRow * 2 > _shownRows * 4`, reduces rows to 2. When `_shownRows > 1` and `_shownPerRow > _shownRows * 7`, reduces rows to 1. Dart only clamps perRow (≤7 for rows>1, ≤4 for rows>2) but never reduces row count based on these ratio conditions, producing wrong grid shapes in certain screen widths. — `chat_switch_overlay.dart:177-183` ← `window/window_chat_switch_process.cpp:440-453`

- [ ] [CRITICAL] Panel background border-radius is 12px but AyuGram uses `boxRadius = 6px`. 100% deviation exceeds threshold. — `chat_switch_overlay.dart:19,201` ← `ui/lib_ui/ui/layers/layers.style:38` (`boxRadius: 6px`)

- [ ] [CRITICAL] Selection highlight border-radius is 8px but AyuGram uses `st::boxRadius = 6px` (33% deviation). — `chat_switch_overlay.dart:265` ← `window/window_chat_switch_process.cpp:194,200` + `lib_ui/ui/layers/layers.style:38`

- [ ] [CRITICAL] Saved Messages detection uses hardcoded English string `'Saved Messages'` — will produce wrong result for any non-English locale or custom-named Saved Messages. AyuGram uses `peer->isSelf()` (identity check, locale-independent). — `chat_switch_overlay.dart:297` ← `window/window_chat_switch_process.cpp:133`

- [ ] [CRITICAL] `_shownPerRow` and `_shownRows` are mutated directly during `build()` (lines 185–186) without `setState()`. These fields drive keyboard navigation in `_moveNext`/`_movePrev`. If Flutter calls `build()` between a layout change and a key event, navigation uses stale counts; if a key event arrives before first build, both are 1 (initialised at declaration). — `chat_switch_overlay.dart:185-186` ← `window/window_chat_switch_process.cpp:439,454` (C++ recalculates in `layout()`, a separate method triggered synchronously before any input handling)

- [ ] [MAJOR] Userpic size is 46px but AyuGram style specifies 56px (`chatSwitchUserpic.size: 56px`). 18% deviation. — `chat_switch_overlay.dart:13` ← `window/window.style:355`

- [ ] [MAJOR] Initial selection starts at `initialIndex = 1` (second chat) by default. AyuGram always places the currently opened thread at index 0 and selects it (`_selected = 0`), so the first Tab press moves to index 1. Dart skips the opened-chat selection entirely, making Shift+Tab from the overlay wrap to the last entry instead of returning to the current chat. — `chat_switch_overlay.dart:35,55` ← `window/window_chat_switch_process.cpp:331`

- [ ] [MAJOR] `base64Decode(chat.avatarPath)` executes synchronously on the UI thread inside `build()` on every rebuild. For large avatars (multi-KB base64) this causes frame jank. Should decode once and cache, or use `compute()`/`Isolate.run`. — `chat_switch_overlay.dart:310` ← (performance; AyuGram loads userpics asynchronously via `Ui::UserpicButton` reactive updates at `window/window_chat_switch_process.cpp:114-141`)

- [ ] [MAJOR] No thread-destruction tracking. AyuGram subscribes to `thread->asTopic()->destroyed()` / `thread->asSublist()->destroyed()` and auto-removes entries when the underlying thread is deleted mid-session. Dart's list is a snapshot taken at widget creation; destroyed topics/sublists stay visible until the overlay is dismissed and reopened. — `chat_switch_overlay.dart:54` ← `window/window_chat_switch_process.cpp:357-368`

## chat_view — Placeholders, broken backend wiring, and behavioral inaccuracies

- [ ] [CRITICAL] `_stopAndSendRecording()` resets UI state but never calls any engine method to send the recorded voice or video-round message — the recording is silently discarded — `chat_view.dart:13245` ← `AyuGram/history/view/controls/history_view_compose_controls.cpp` (voice recording pipeline calls `session().api().sendVoiceNote()`)

- [ ] [CRITICAL] `_addFilter()` saves dialog with a toast "Filter added" but never calls any engine or local storage to actually persist the regex filter — `chat_view.dart:2349` ← `AyuGram/ayu/ui/context_menu/context_menu.cpp:946` (`controller->show(Settings::RegexEditBox(&filter, …))` opens persistent edit dialog with save callbacks to `AyuDatabase`)

- [ ] [CRITICAL] `_ComposeAiBoxState._submit()` for `_AiMode.style` and `_AiMode.fix` is a hard stub that always sets an error message "Style/Fix mode requires Telegram Premium with Cocoon AI" — no engine call is made — `chat_view.dart:20708` ← `AyuGram/ayu/features/translator/ayu_translator.cpp:44` (real translate/rewrite uses `messages.translateText` API)

- [ ] [CRITICAL] `_BotReplyKeyboard` always calls `onButtonPressed(btn.text)` regardless of `btn.type` — buttons with `type == 'request_contact'` should open a contact-share confirmation dialog, `type == 'request_location'` should request GPS permission and share location, `type == 'request_poll'` should open a poll creation flow — `chat_view.dart:8778` ← `AyuGram/api/api_bot.cpp:391` (`shareContact` for contact type) and `AyuGram/api/api_bot.cpp:399` (`PeerMenuCreatePoll` for request_poll type)

- [ ] [CRITICAL] `_WriteRestrictionBar` "BOOST THIS GROUP TO SEND MESSAGES" button shows a toast instead of opening the channel boost panel — `chat_view.dart:9307` ← `AyuGram/chat_helpers/message_field.cpp:1347` (`window->resolveBoostState(peer->asChannel(), boosts)` navigates to the real boost screen)

- [ ] [CRITICAL] `_WriteRestrictionBar` "Unlock" button for Premium restriction shows a snackbar instead of navigating to the Telegram Premium subscription flow — `chat_view.dart:9363` ← `AyuGram/history/history_widget.cpp:7491` (`PremiumRequiredSendRestriction` opens the premium paywall)

- [ ] [CRITICAL] `_PinnedBar` `onClose` at call-site only sets `_pinnedBarDismissed = true` (in-memory, resets on restart) — should call engine to either unpin the message (if user has pin rights) or call `HidePinnedBar` (which persists via `session.settings().setHiddenPinnedMessageId()`) — `chat_view.dart:4510` ← `AyuGram/history/history_widget.cpp:9475` (`hidePinnedMessage()` branches on `canPinMessages()` to call `ToggleMessagePinned` or `HidePinnedBar`)

- [ ] [CRITICAL] `_GroupCallBar` `onJoin` at line 4488 calls `chatState.joinGroupCall()` only — bypasses permission check and never opens the group call panel — the correct path at line 4433 does `requestCallPermissions` + `showGroupCallPanel` — `chat_view.dart:4488` ← `AyuGram/history/history_widget.cpp` (group call join shows the voice chat UI panel)

- [ ] [CRITICAL] `_showScheduledMenu` shows a menu with "Create Poll" and "Create To-do List" options but the returned `Future` has no `.then()` handler — selecting either item does nothing — `chat_view.dart:6020` ← `AyuGram/history/history_widget.cpp` (`_scheduledMenu` items trigger `showCreatePollBox` and `showCreateTodoListBox`)

- [ ] [MAJOR] Top-bar menu "Mark as Unread" is never executed — the `'read'` case handler at line 5747 only marks as read when `chat.unreadCount > 0` and silently does nothing when the label shows "Mark as Unread" — `chat_view.dart:5747` ← `AyuGram/window/window_peer_menu.cpp:697` (`changeDialogUnreadMark(history, true)` is called for the unread direction)

- [ ] [MAJOR] `_StarGiftCard` has no `GestureDetector`/`onTap` — tapping a gift card in `_StarGiftSheet` does nothing; selecting a gift should open a purchase confirmation — `chat_view.dart:18161` ← `AyuGram/boxes/star_gift_box.cpp:2370` (`strong->show(Box(GiftBox, strong, peer, …))` opens the purchase flow on selection)

- [ ] [MAJOR] `EngineService` has no `sendVoice`, `sendAudioFile`, or `sendVideoNote` methods — voice/video-round recording is entirely UI-only with no backend send path — `dart/lib/bridge/engine_service.dart` (no such method exists) ← `AyuGram/history/view/controls/history_view_compose_controls.cpp` (voice recording finalize calls real MTProto upload+send)

# choose_datetime_box — Calendar / ScheduleMessage / TimePicker audit

- [ ] [CRITICAL] Calendar title is static text with no click handler — AyuGram's `CalendarBox::Title` is an `AbstractButton` that, when clicked, opens a dual-drum month/year picker (`FillMonthYearPicker`) letting the user jump to any month/year instantly. The Dart renders the title as a plain string via `TelegramBox(title: ...)` with no `onTap` — the entire month/year jump feature is absent — `choose_datetime_box.dart:241` ← `AyuGram/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:1216-1231`

- [ ] [CRITICAL] Long-press on prev/next nav arrows should jump to min/max date (after `kJumpDelay = 700ms`), not continuously scroll through months. AyuGram's `jumpAfterDelay` fires a timer after 700ms and calls `jump()` which moves to `_context->minDayIndex()` / `_context->maxDayIndex()`. The Dart's `_startFastJump` fires every 150ms and repeatedly calls `_prevMonth()` / `_nextMonth()` — completely different semantics — `choose_datetime_box.dart:154-163,251-262` ← `AyuGram/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:1319-1337`

- [ ] [CRITICAL] Arrow-key behavior in CalendarBox is wrong. AyuGram's `keyPressEvent` maps `Left/Up/PageUp` → previous month and `Right/Down/PageDown` → next month. The Dart's `_handleKey` maps arrows to per-day focus movement (-1/+1/−7/+7 days) — a behavior that does not exist in AyuGram at all — `choose_datetime_box.dart:166-192` ← `AyuGram/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:1510-1530`

- [ ] [MAJOR] Calendar week start is hardcoded Monday (`_weekDays = ['Mo','Tu','We','Th','Fr','Sa','Su']`). AyuGram uses `QLocale().firstDayOfWeek()` to determine the locale's first day of week and shifts all columns accordingly via `DayOfWeekIndex()`. A user in a locale where the week starts on Sunday will see wrong column alignment — `choose_datetime_box.dart:27,235-236` ← `AyuGram/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:299-300,374-396`

- [ ] [MAJOR] Calendar missing ripple animations on day cells. AyuGram creates a `RippleAnimation::EllipseMask` on mouse-press for each cell (stored in `_ripples` map), painted over the cell on every frame until the ripple drains. The Dart has only hover state (`_hovering` bool), no press ripple — `choose_datetime_box.dart:438-488` ← `AyuGram/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:978-1010,875-884`

- [ ] [MAJOR] Calendar missing scroll-based infinite month navigation. AyuGram's `CalendarBox` wraps an `Inner` in a `ScrollArea`; scrolling past the visible rows automatically advances the month via `processScroll()`. The Dart shows a fixed 6-row grid with no scroll area — the user can only navigate months via the arrow buttons — `choose_datetime_box.dart:296-371` ← `AyuGram/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:1234-1239,1409-1429`

- [ ] [MAJOR] Minimum schedule time buffer not enforced. AyuGram enforces `kMinimalSchedule = 10` seconds: the `collect()` lambda rejects any datetime where `result < min()`, where `min()` defaults to `base::unixtime::now() + 10`. The Dart's `_validateTime` only checks `dt.isBefore(DateTime.now())` — a datetime exactly at "now" is accepted, allowing a schedule 0–9 seconds in the past by the time the server processes it — `choose_datetime_box.dart:604-616` ← `AyuGram/Telegram/SourceFiles/ui/boxes/choose_date_time.cpp:28,110-112,208-210`

- [ ] [MAJOR] Non-premium repeat-period tap is silently ignored instead of showing a premium upsell. AyuGram's `ChooseRepeatPeriod` takes a `filter` callback; when `locked` is true (non-premium), the caller sets a filter that shows the premium preview box on click. The Dart sets `onTap: widget.isPremium ? _showRepeatMenu : null` — the tap does nothing for non-premium users, no upsell — `choose_datetime_box.dart:846` ← `AyuGram/Telegram/SourceFiles/ui/boxes/choose_date_time.cpp:286-294,322-325`

- [ ] [MAJOR] TimePickerBox initial-index selection uses exact `indexOf` match only. AyuGram's `TimePickerBox` uses `ranges::lower_bound` plus distance-to-nearest to snap to the closest value when `startValue` is between two list items. The Dart falls back to index 0 when the value is not found exactly — `choose_datetime_box.dart:919-921` ← `AyuGram/Telegram/SourceFiles/ui/boxes/time_picker_box.cpp:49-60`

- [ ] [MAJOR] Date field should open calendar on focus, not only on tap. AyuGram wires `state->day->focusedChanges()` so that the calendar opens whenever the day field receives focus (keyboard tab, click, etc.). The Dart wraps the date field in a `GestureDetector(onTap: _openCalendar)` — focus via keyboard or programmatic `requestFocus()` does not open the calendar — `choose_datetime_box.dart:775-776` ← `AyuGram/Telegram/SourceFiles/ui/boxes/choose_date_time.cpp:173-196`

# color_picker_box — Color picker dialog vs AyuGram ColorEditor

## Reference
- Dart: `dart/lib/ui/color_picker_box.dart`
- AyuGram: `ui/widgets/color_editor.cpp` + `boxes/boxes.style`

---

- [ ] [CRITICAL] Opacity slider orientation is wrong: AyuGram places it **horizontally below the picker** (`color_editor.cpp:864-874` `Slider::Direction::Horizontal`; `resizeEvent` line 1036-1043 positions it at `rect::bottom(_picker) + st::colorEditSkip`). Dart makes it a `_VerticalOpacitySlider` placed to the right of the hue slider — `color_picker_box.dart:297-311` ← `AyuGram/ui/widgets/color_editor.cpp:868`

- [ ] [CRITICAL] Field layout is completely inverted: AyuGram stacks H/S/B then R/G/B **vertically** to the **right** of the picker+hue slider (see `resizeEvent` lines 1050-1082, fields positioned at `fieldLeft` = right of hue slider). Dart puts all fields in **horizontal rows below** the picker — `color_picker_box.dart:248-252` ← `AyuGram/ui/widgets/color_editor.cpp:1063-1082`

- [ ] [MAJOR] Slider position indicator uses wrong visual: AyuGram renders **arrow icons** (`colorSliderArrowLeft`/`colorSliderArrowRight`) pointing from both sides of the slider track at the current value position. Dart draws two concentric circles (dark outer + white inner) — `color_picker_box.dart:757-771` ← `AyuGram/ui/widgets/color_editor.cpp:406-415` + `boxes/boxes.style:515-518`

- [ ] [MAJOR] Hex result field limited to 6 chars — breaks RGBA entry: AyuGram's `ResultField::correctValue` allows up to 8 characters and `updateFromResultField` accepts 6 (RGB) or 8 (RGBA). Dart uses `LengthLimitingTextInputFormatter(6)` blocking 8-char hex — `color_picker_box.dart:427` ← `AyuGram/ui/widgets/color_editor.cpp:812,1200`

- [ ] [MAJOR] Picker crosshair radius is 8px but AyuGram uses 6px (`colorPickerMarkRadius`): `_kCrosshairRadius = 8` in Dart vs `st::colorPickerMarkRadius = 6` used in `drawEllipse` — `color_picker_box.dart:13` ← `AyuGram/boxes/boxes.style:512` + `color_editor.cpp:135`

- [ ] [MAJOR] Picker crosshair ignores color lightness: AyuGram computes luminance (`0.2989*R + 0.587*G + 0.114*B`) and draws the marker **black** when lightness > 0.6, **white** otherwise. Dart always draws white — `color_picker_box.dart:700-703` ← `AyuGram/ui/widgets/color_editor.cpp:121-127`

- [ ] [MAJOR] Mouse wheel does not increment/decrement numeric fields: AyuGram's `Field::wheelEvent` changes the field value by scroll delta (step=5), enabling precise color editing with scroll. Not implemented in Dart `_NumericField` — `color_picker_box.dart:524-591` ← `AyuGram/ui/widgets/color_editor.cpp:720-739`

- [ ] [MAJOR] Up/Down arrow keys do not increment/decrement field values: AyuGram's `Field::keyPressEvent` handles `Qt::Key_Up`/`Qt::Key_Down` to call `changeValue(±1)`. Dart's TextField has no such key handler — `color_picker_box.dart:563-585` ← `AyuGram/ui/widgets/color_editor.cpp:752-760`

- [ ] [MAJOR] Enter key in numeric fields submits the dialog instead of advancing focus: AyuGram's `fieldSubmitted()` cycles focus H→S→B→R→G→B→hex, only submitting when focus is on the hex result field. Dart's `onSubmitted: _submit` submits immediately from any field — `color_picker_box.dart:341,350,358,373,382,391,430` ← `AyuGram/ui/widgets/color_editor.cpp:960-979`

- [ ] [MAJOR] Current color swatch is not interactive: AyuGram's `mousePressEvent` detects a click on `_currentRect` and calls `updateFromColor(_current)` to reset to the original color. Dart's `_SwatchBox` is a static `Container` with no tap handler — `color_picker_box.dart:320-328` ← `AyuGram/ui/widgets/color_editor.cpp:1119-1123`

# engine_service — Bridge/Service Layer Audit

## Summary

`engine_service.dart` is the Dart FFI bridge wrapper. No UI placeholders exist. Issues are all
backend-wiring correctness and performance. AyuGram reference used for protocol behavior
(`api/api_editing.cpp`, `apiwrap.cpp`, `data/data_forum_topic.cpp`).

---

- [ ] [CRITICAL] `editMessage` silently drops `entities` parameter — rich-text formatting
  (bold, italic, code, mentions, links) is lost whenever a formatted message is edited.
  The parameter is in the signature but never written to `EngineEditMessageRequest`.
  AyuGram sets `MTPmessages_EditMessage::Flag::f_entities` explicitly when entities are
  non-empty. — `engine_service.dart:1793-1800` ←
  `AyuGram/api/api_editing.cpp:301`

- [ ] [CRITICAL] `readMessageContents` sends request with empty `chatId` — the request uses
  `EngineMarkChatReadRequest` but only sets `accountId` and `upToMsgId`; `chatId` is never
  assigned. On channels/supergroups the Go engine requires the peer to dispatch
  `channels.ReadMessageContents`; without it the RPC has no channel context and will either
  fail silently or mark wrong messages. AyuGram always passes `inputChannel` for channel
  peers. — `engine_service.dart:420-425` ← `AyuGram/apiwrap.cpp:1392-1395`

- [ ] [MAJOR] Nine methods misuse unrelated proto request types, piggybacking fields from
  semantically wrong messages. If the Go handler ever validates the message type or if a
  proto field is renamed, all nine silently break:
  - `reportSpam` uses `EngineLeaveChatRequest` — `engine_service.dart:380-385`
  - `getLinkedChatId` uses `EngineLeaveChatRequest` — `engine_service.dart:387-394`
  - `deleteContact` uses `EngineBlockUserRequest` — `engine_service.dart:405-410`
  - `joinChannel` uses `EngineLeaveChatRequest` — `engine_service.dart:1817-1822`
  - `editChatTitle` uses `EngineSaveDraftRequest.text` for the title — `engine_service.dart:1831-1837`
  - `editChatDescription` uses `EngineSaveDraftRequest.text` for the description — `engine_service.dart:1839-1844`
  - `toggleForum` uses `EngineMuteChatRequest.muted` to carry forum-enabled bool — `engine_service.dart:1847-1853`
  - `clearHistory` uses `EngineLeaveChatRequest` — `engine_service.dart:1855-1860`
  - `deleteChat` uses `EngineLeaveChatRequest` — `engine_service.dart:1862-1867`

  Each should have a dedicated proto request. ← `AyuGram/data/data_thread.h` (each operation
  is a distinct API call with its own parameter set)

- [ ] [MAJOR] `pinForumTopic`, `toggleForumTopicClosed`, and `toggleGeneralTopicHidden` all
  smuggle a boolean into `EngineEditForumTopicRequest.colorId` (an int field for color IDs).
  `colorId = pinned ? 1 : 0` etc. AyuGram uses distinct `channels.UpdatePinnedForumTopic`
  and `channels.EditForumTopic` MTProto calls, each with their own flag fields. The Go
  backend must mirror this hack exactly or these operations silently do nothing/corrupt
  topic colors. — `engine_service.dart:488-512` ←
  `AyuGram/data/data_forum_topic.cpp:463-475` (`setClosed`, `setClosedAndSave`)

- [ ] [MAJOR] `_groupCallStateController` is never closed in `dispose()` — all other 14
  stream controllers are closed (lines 3595-3608) but `_groupCallStateController` is
  missing. This leaks the stream; listeners are never notified of closure and the controller
  holds memory. — `engine_service.dart:40` (declaration), `engine_service.dart:3592-3609`
  (dispose missing it) ← `AyuGram/data/data_group_call.h` (GroupCall has explicit
  destructor cleanup)

- [ ] [MAJOR] `contentRaw` JSON blob is decoded 14 times per message in `_cachedMsgFromProto`
  — each helper (`_waveformFromRaw`, `_reactionsFromRaw`, `_topicFieldFromRaw`,
  `_topicColorFromRaw`, `_boolExtraFromRaw`, `_intExtraFromRaw`, `_int64FieldFromRaw`,
  `_doubleExtraFromRaw`, `_stringListExtraFromRaw`, `_pollOptionsFromRaw`,
  `_altQualitiesFromRaw`, `_replyKeyboardFromRaw`, `_inlineKeyboardFromRaw`) calls
  `jsonDecode(contentRaw)` independently. With the default limit of 50 messages
  (`getMessages` line 1656) that is 50 × 14 = 700 JSON parses per chat open, all on the
  UI thread via synchronous `_callRaw`. Fix: decode once at the top of `_cachedMsgFromProto`
  and pass the result to each extractor. — `engine_service.dart:3869-4226` (converters),
  `engine_service.dart:1656-1665` (`getMessages` sync call) ←
  `AyuGram/data/data_session.cpp:5367` (AyuGram parses MTP message once and extracts all
  fields in a single pass)

# confirm_box — 8 issues

- [ ] [CRITICAL] `_confirmLabel` uses literal `'Delete (...)'` placeholder instead of live count — `confirm_box.dart:511` ← `AyuGram/boxes/delete_messages_box.cpp:228-233`
  AyuGram does a live message search (`search->searchMessages({ .from = _moderateFrom })`) and shows the result as `"Delete (N)"` where N is the real count. The Dart version hardcodes the string suffix as `' (...)'` with no connection to any engine query.

- [ ] [CRITICAL] `requestPermissionOrFail` never requests permission for `canRequest` status — `confirm_box.dart:887-890` ← `AyuGram/boxes/confirm_box.cpp` (no equivalent desktop flow)
  For `PermissionStatus.canRequest`, the code immediately calls `getPermissionStatus` a second time (same system check, same result), declares failure, and shows the settings dialog — it never triggers any OS permission prompt. The `canRequest` branch is functionally identical to `denied`.

- [ ] [MAJOR] Report reason `Fake Account` shown for all report targets; should be Channel/Group/Bot only — `confirm_box.dart:1201` ← `AyuGram/ui/boxes/report_box_graphics.cpp:89-93`
  AyuGram gates `Reason::Fake` on `source == Channel || source == Group || source == Bot`. Dart's static `_reasons` list always includes it regardless of `ReportTarget`.

- [ ] [MAJOR] Report reasons `IllegalDrugs` and `PersonalDetails` shown for all targets; should be Message/Story only — `confirm_box.dart:1206-1207` ← `AyuGram/ui/boxes/report_box_graphics.cpp:110-119`
  AyuGram only adds these two reasons when `source == Message || source == Story`. Dart's flat `_reasons` list exposes them for every target including Channel, Group, ProfilePhoto, etc.

- [ ] [MAJOR] `_revoke` checkbox always initialised `false`, ignoring saved user preference — `confirm_box.dart:452` ← `AyuGram/boxes/delete_messages_box.cpp:247-252`
  AyuGram reads `revokeByDefault = !settings.rememberedDeleteMessageOnlyForYou()` and uses it as the initial checked state. The Dart `_DeleteContentState` hardcodes `bool _revoke = false`, so users who previously chose "also delete for them" always see the box unchecked.

- [ ] [MAJOR] `_revokeRemember` shown whenever `_revoke == true` instead of when it deviates from default — `confirm_box.dart:582-589` ← `AyuGram/boxes/delete_messages_box.cpp:262-267`
  AyuGram shows the "Remember this choice" checkbox only when `checked != revokeByDefault`, i.e. only when the user is changing from their preference. Dart shows it unconditionally on `_revoke == true`, surfacing it even when the current state matches the saved default.

- [ ] [MAJOR] Screen share source list enumerates monitors only (`xrandr`), no application windows — `confirm_box.dart:977` ← AyuGram DesktopCapture / NativeDesktopCaptureSource (tgcalls platform)
  AyuGram's chooser shows both screens and capturable windows. The Dart `_loadSources` calls only `xrandr --listmonitors`; there is no window enumeration path, so users can only share an entire monitor.

- [ ] [MAJOR] "Enable auto-delete" link button absent from delete-messages dialog — `confirm_box.dart:540-605` (no equivalent) ← `AyuGram/boxes/delete_messages_box.cpp:300-315`
  AyuGram appends an `autoDeleteSettings` link button ("Enable auto-delete" / "Edit auto-delete settings") when the peer supports TTL (`TTLValidator::can()`). The Dart `_DeleteContent` renders no such control.

## contacts_screen — stubs, broken backend wiring, missing DM creation, dropped comment

- [ ] [CRITICAL] `_openChat` silently does nothing if no DM exists for the contact — clicking any contact not yet in chat list opens nothing; AyuGram calls `showPeerHistory(peer)` which creates or navigates to the DM — `contacts_screen.dart:524` ← `AyuGram/boxes/peer_list_controllers.cpp:776`

- [ ] [CRITICAL] "Suggest photo" button is an empty stub `onTap: () {}` — no engine method exists for `api.peerPhoto().suggest()` at the Go bridge or Core interface level — `contacts_screen.dart:2115` ← `AyuGram/boxes/peers/edit_contact_box.cpp:893`

- [ ] [CRITICAL] "Set personal photo" button is an empty stub `onTap: () {}` — no engine method exists for `api.peerPhoto().upload()` for a contact user — `contacts_screen.dart:2123` ← `AyuGram/boxes/peers/edit_contact_box.cpp:896`

- [ ] [CRITICAL] "Reset to default" button is an empty stub `onTap: () {}` — no engine method exists for `api.peerPhoto().clearPersonal()` — `contacts_screen.dart:2131` ← `AyuGram/boxes/peers/edit_contact_box.cpp:727`

- [ ] [CRITICAL] Notes field in `_EditContactBox` is collected (`_notesCtrl`) but never passed to the backend — `engine.addContact()` takes only `(phone, firstName, lastName)` with no `note` parameter; AyuGram sends the note via `MTPcontacts_AddContact` with `Flag::f_note` — `contacts_screen.dart:1920` ← `AyuGram/boxes/peers/edit_contact_box.cpp:92`

- [ ] [CRITICAL] `_ShareContactBox` comment field is shown in UI and collected via `_commentController` but never passed to `engine.sendContact()` — the comment is silently dropped; AyuGram's share box sends `comment = field->getTextWithAppliedMarkdown()` with the submission — `contacts_screen.dart:2401` ← `AyuGram/boxes/share_box.cpp:686`

- [ ] [CRITICAL] `_openStory` stub — tapping a contact's story ring calls `_openChat(contact)` instead of a story viewer; no story viewer engine method exists in the bridge — `contacts_screen.dart:540` ← `AyuGram/boxes/peer_list_controllers.cpp:778`

- [ ] [MAJOR] Global search only handles `@username` queries (line 120 `query.startsWith('@')`); plain-text name/phone queries never trigger a server-side `contacts.Search` API call; AyuGram's `PeerListGlobalSearchController` sends `MTPcontacts_Search` for any non-empty query — `contacts_screen.dart:120` ← `AyuGram/boxes/peer_list_controllers.cpp:308`

- [ ] [MAJOR] `_isValidPhone` missing special-number cases: AyuGram allows `phone.startsWith("42") && length in {2, 5, 6}` but Dart only matches `^42\d\d$` (length 4); the "42", "42xxx", "42xxxx" forms are incorrectly rejected — `contacts_screen.dart:1110` ← `AyuGram/boxes/add_contact_box.cpp:54`

- [ ] [MAJOR] Sort toggle icon semantics are inverted — AyuGram displays the icon for the *target* mode (alphabet icon when currently Online, online icon when currently Alphabet); Dart displays the icon for the *current* mode, which is the opposite convention — `contacts_screen.dart:594` ← `AyuGram/boxes/peer_list_controllers.cpp:177`

# create_group_wizard — Audit Findings

- [ ] [CRITICAL] Photo upload for group/channel is never sent to the engine after creation. `_photoBytes`/`_photoPath` are set by `_pickPhoto()` and displayed in the wizard UI, but neither `_submitGroup()` (line 585) nor `_submitInfo()` (line 536, channel creation at line 555) call any engine method to upload the photo to the new chat. `EditChannelPhoto` exists in Go (telegram.go:17175) and has a dispatch (dispatch_gen.go:19567), but there is no matching method in engine_service.dart and the wizard never calls it. The userpic is silently dropped on group/channel creation. — `create_group_wizard.dart:585-620` / `create_group_wizard.dart:550-583` ← `telegram.go:17175`

- [ ] [CRITICAL] Camera option in the userpic menu falls back to `_pickPhoto()` (file picker), not a camera capture. Line 327-328: `} else if (value == 'camera') { _pickPhoto(); }` — camera is listed as a distinct option in the menu but does exactly the same thing as "Upload Photo", giving users no actual camera access. — `create_group_wizard.dart:327-328`

- [ ] [CRITICAL] `_EditPeerTypeBox._save()` only saves the username change (lines 2434–2483). It does NOT save `_noForwards`, `_joinToSend`, or `_joinRequest` on Save — those flags are toggled live via `_toggleFlag()` on every individual switch change (lines 2537–2560), so they are applied immediately but not batched with the username save. This means if the user changes public/private type AND permission flags together and hits Save, the username is updated but there is no ordering or rollback relationship: if the username save fails, the permission flags were already pushed. AyuGram batches all fields into `EditPeerTypeData` and saves them atomically on the Save button click (edit_peer_type_box.cpp:771–783). — `create_group_wizard.dart:2434-2483` ← `edit_peer_type_box.cpp:771-783`

- [ ] [CRITICAL] Multiple usernames list (`UsernamesList`) is not implemented. AyuGram's `edit_peer_type_box.cpp:467` adds a `UsernamesList` widget that shows all secondary usernames for a channel and allows reordering/disabling them. The Dart `_EditPeerTypeBox` only handles one username field with no awareness of secondary usernames. The `usernamesOrder()` data is collected and passed to the save callback in AyuGram (edit_peer_type_box.cpp:775–778) but there is no equivalent in the Dart box. — `create_group_wizard.dart:2260-2935` ← `edit_peer_type_box.cpp:462-472`

- [ ] [CRITICAL] `CHANNEL_PUBLIC_GROUP_NA` error (public groups not available in this region) is not handled in either `_onUsernameChanged` (line 390) or `_checkUsernameApi` (line 441). In AyuGram, receiving this error sets `_usernameState = UsernameState::NotAvailable` and forces privacy back to `NoUsername` (edit_peer_type_box.cpp:574–576). In the Dart code, this error falls through to the generic "Sorry, this link is invalid" message and the public radio button is left selected, leaving the user stuck. — `create_group_wizard.dart:460-477` ← `edit_peer_type_box.cpp:572-576`

- [ ] [CRITICAL] `USERNAME_PURCHASE_AVAILABLE` error is not handled in the wizard. AyuGram shows a "purchase available" state for collectible/Fragment usernames (edit_peer_type_box.cpp:587-592) with a special `UsernameCheckInfo::PurchaseAvailable` display. The Dart wizard has no handling for this error code in either `_checkUsernameApi` (line 441) or `_EditPeerTypeBoxState._onUsernameChanged` (line 2380) — it falls through to "Sorry, this link is invalid". — `create_group_wizard.dart:460-477` ← `edit_peer_type_box.cpp:586-592`

- [ ] [MAJOR] `setHistoryTTL` is called fire-and-forget without `await` (line 598). It is a `void` sync method (`engine_service.dart:261`) that calls `_callRaw` (not async), so TTL setting has no error handling or confirmation before navigation. If the raw FFI call fails silently, the user navigates to the new group with TTL not set and no indication of failure. — `create_group_wizard.dart:597-599`

- [ ] [MAJOR] "Invite via Link" button in member picker step (line 1139) is always rendered for both group and channel flows (`widget.type == _WizardType.group` condition forces it visible even when `_inviteLink.isEmpty`). When tapped and `_inviteLink` is empty (groups: invite link is never loaded during group creation), `onTap` does nothing. Groups never call `_loadInviteLink()` during their flow (only channels call it at line 562). The button appears to work but silently does nothing for groups. — `create_group_wizard.dart:1139-1145`

- [ ] [MAJOR] `_PublicLinksLimitBox` uses hardcoded constants `_freeLimit = 10` and `_premiumLimit = 20` (lines 1989–1990). AyuGram fetches these dynamically from the server via `Data::PremiumLimits(session).channelsPublicDefault()` and `channelsPublicPremium()` (premium_limits_box.cpp:641–642), which reads from `appConfigLimit("channels_public_limit_default", 10)` / `appConfigLimit("channels_public_limit_premium", 20)`. The Telegram server can push different limits via app config; hardcoding means the display will be wrong for users who receive non-standard limits. — `create_group_wizard.dart:1989-1990` ← `premium_limits_box.cpp:641-642`

- [ ] [MAJOR] `_EditPeerTypeBox._save()` does not handle the case where switching from public to private (clearing username) while `_noForwards`/`_joinToSend`/`_joinRequest` flags have already been toggled live. Specifically when `newUsername == _currentUsername` (line 2447) the method pops without saving anything, even though the user may have toggled permission flags. Those flags were already pushed individually but the user experience is inconsistent: Save button dismisses the box as if no changes were made. — `create_group_wizard.dart:2447-2450`

- [ ] [MAJOR] Share button in `_EditPeerTypeBox` invite link section (line 2866–2873) copies to clipboard instead of sharing. The label says "Share" and uses `Icons.share` but the `onTap` handler calls `Clipboard.setData` identical to the Copy button. No system share sheet is invoked. This is dead UI. — `create_group_wizard.dart:2865-2873`

- [ ] [MAJOR] Slowmode values in `_EditPeerTypeBoxState` are `[0, 5, 10, 30, 60, 300, 900, 3600]` (line 2318). AyuGram defines 8 values via `SlowmodeDelayByIndex`: `0, 5, 10, 30, 60, 300, 900, 3600` (edit_peer_permissions_box.cpp:191–204). The values match, but the Dart slider saves on `onChangeEnd` by calling `_setSlowmode` directly (line 2602–2604) — this means every slider release makes a live engine call without a Save button. AyuGram batches slowmode into the full permissions save. If the user cancels the box after moving the slider, slowmode has already been changed on the server with no rollback. — `create_group_wizard.dart:2600-2604` ← `edit_peer_permissions_box.cpp:1258-1269`

- [ ] [MAJOR] Permission toggles (`_joinToSend`, `_noForwards`, `_joinRequest`) are applied live on toggle (lines 2537–2560) without a Save button confirmation. AyuGram applies these only when the Save button is clicked (edit_peer_type_box.cpp:771–783). This means changes cannot be cancelled once toggled. — `create_group_wizard.dart:2537-2560` ← `edit_peer_type_box.cpp:771-783`

# custom_emoji_cache — Audit Findings

- [ ] [CRITICAL] WebM animated emoji (video/webm sticker type) silently degrades to static preview — `_buildCachedEmoji` and `_buildStaticFrame` in `dart/lib/ui/message_bubble.dart:6246-6295` only branch on `file.isTgs` and `file.isWebp`; `file.isWebm` falls through to `_buildPreviewOrBlank`, showing only a thumbnail instead of animation ← `AyuGram/data/stickers/data_custom_emoji.cpp:396-403` (WebM handled via `FFmpeg::FrameGenerator` — it is a full animated type, not a fallback)

- [ ] [CRITICAL] Thumb request batch `_flushBatch` sends all IDs without the 100-per-request chunk limit — `dart/lib/ui/custom_emoji_cache.dart:250-263` (iterates and fires `_fetchThumbBatch` with the full list), while `_flushFileBatch` at `custom_emoji_cache.dart:265-283` correctly chunks by `kMaxPerRequest` — `AyuGram/data/stickers/data_custom_emoji.cpp:769-774` (`while (!_pendingForRequest.empty() && ids.size() < kMaxPerRequest)` — strictly caps every batch at 100)

- [ ] [MAJOR] Synchronous disk I/O on UI thread inside `request()` — `dart/lib/ui/custom_emoji_cache.dart:218-225` calls `thumbFile.existsSync()`, `readAsBytesSync()`, `pathFile.existsSync()`, `readAsBytesSync()` on the main isolate, blocking frame rendering on slow storage ← `AyuGram/data/stickers/data_custom_emoji.cpp:308-328` (all cache lookups go through `document->owner().cacheBigFile().get(key, callback)` which is async)

- [ ] [MAJOR] TGS (Lottie) gzip decompression runs synchronously on the UI thread — `dart/lib/ui/message_bubble.dart:2209` and `5873` and `6161` call `gzip.decode(file.fileData)` inside widget `_onCacheUpdate` callbacks; large TGS files (some are 50–200 KB compressed) will cause visible frame drops ← `AyuGram/data/stickers/data_custom_emoji.cpp:394-415` (decompression and frame generation happen inside `Lottie::FrameGenerator` / `FFmpeg::FrameGenerator` off the main thread)

- [ ] [MAJOR] Frame size constants are hardcoded pixel values with no DPI scaling — `dart/lib/ui/custom_emoji_cache.dart:20-25` (`normal: 20.0, large: 27.0, isolated: 43.0, setIcon: 24.0`) are device-independent points, but AyuGram computes actual frame sizes by calling `Ui::Text::AdjustCustomEmojiSize(emoji / factor) * factor` where factor is `style::DevicePixelRatio()` ← `AyuGram/data/stickers/data_custom_emoji.cpp:1011-1015` — on 2× displays the Dart sizes are half the correct rendered resolution

- [ ] [MAJOR] `EmojiSizeTag.large` and `EmojiSizeTag.setIcon` are never passed to `acquire`/`release` anywhere in the codebase — every call site uses only `EmojiSizeTag.normal` or `EmojiSizeTag.isolated` (`dart/lib/ui/message_bubble.dart:2189,5822,6091`, `dart/lib/ui/emoji_status_widget.dart:49`, `dart/lib/ui/chat_view.dart:11777`) — so the per-size refcount system (`dart/lib/ui/custom_emoji_cache.dart:64`) is only half-wired; emoji displayed at large/setIcon sizes are never ref-counted and cannot be properly evicted ← `AyuGram/data/stickers/data_custom_emoji.h:150-155` (four separate instance maps, one per `SizeTag`, all actively managed)

- [ ] [MAJOR] `kPerRow = 16`, `kMaxFrames = 180`, and `kPreloadFrames = 3` are defined in `EmojiSizeConstants` (`dart/lib/ui/custom_emoji_cache.dart:27-29`) but never referenced anywhere in the codebase — they hint at a planned frame-preloading/row-layout pipeline that was never implemented; without it the cache has no cross-size approximate-preview fallback, so emoji always start blank until the full file loads ← `AyuGram/data/stickers/data_custom_emoji.cpp:523-548` (`prepareNonExactPreview` scales an existing instance from any other size tag as an immediate approximate preview, avoiding blank frames entirely)

# edit_forum_topic_box — Audit Findings

- [ ] [CRITICAL] `_iconEmojiId` stores Unicode codepoints (emoji.runes.first) instead of Telegram DocumentIds — callers pass this directly to `engine.createForumTopic` / `engine.editForumTopic`, sending wrong values to `MTPmessages_EditForumTopic` which expects a 64-bit DocumentId — `edit_forum_topic_box.dart:468-480` ← `edit_forum_topic_box.cpp:350-375` (stores `document->id` as `DocumentId`)

- [ ] [CRITICAL] Emoji icon selector uses a hardcoded static list of Unicode emoji characters (`_defaultTopicEmojiIcons`) instead of fetching real Telegram forum topic icons from the server via `inputStickerSetEmojiDefaultTopicIcons` — AyuGram uses `EmojiListWidget` with `Mode::TopicIcon`, calls `icons->requestDefaultIfUnknown()` and `icons->list()` to get actual SVG-based DocumentId icons; the Dart grid shows system emoji (💬 📢) which are visually wrong — `edit_forum_topic_box.dart:29-54` ← `edit_forum_topic_box.cpp:283-305`

- [ ] [CRITICAL] Premium icon check shows a SnackBar stub instead of the proper StickerToast premium preview — AyuGram uses `HistoryView::StickerToast` with `Section::TopicIcon` which shows the actual sticker with a "Get Premium" CTA; the Dart shows a 2-second SnackBar with no actionable path — `edit_forum_topic_box.dart:470-476` ← `edit_forum_topic_box.cpp:335-344`

- [ ] [CRITICAL] No "reset to default / clear custom icon" entry in the emoji selector grid — AyuGram inserts `kDefaultIconId` (0x7FFF'FFFF'FFFF'FFFF) as the first cell in the emoji list, which when selected sets `state->iconId = 0` (clears custom icon); the Dart grid has no such option, so once a custom emoji is selected the only way to revert is clicking a color cell — `edit_forum_topic_box.dart:485-525` ← `edit_forum_topic_box.cpp:285-288` (`list.insert(begin(list), kDefaultIconId)`)

- [ ] [MAJOR] Both divider label strings are wrong — for bot: Dart says "Choose a title for the thread" (missing "and icon"); for topic: Dart says "Choose a title and an icon for the topic" (wrong word order) — AyuGram: `lng_bot_thread_choose_title_and_icon` = "Choose a thread name and icon", `lng_forum_choose_title_and_icon` = "Choose a topic name and icon" — `edit_forum_topic_box.dart:443-445` ← `edit_forum_topic_box.cpp:501-502` + `Resources/langs/lang.strings:7319,7337`

- [ ] [MAJOR] Color cycling blocked unconditionally when `isEditing=true` — AyuGram only disables the icon button when `created = topic && !topic->creating()`, i.e. only when the topic is fully persisted server-side; a topic still in "creating" state allows cycling even in the edit box — `edit_forum_topic_box.dart:293` ← `edit_forum_topic_box.cpp:477-479`

# edit_mark_box — Critical issues: missing validation, wrong buttons, incorrect padding

## Issues Found

- [x] [CRITICAL] Missing Cancel button — `edit_mark_box.dart:82-95` ← `edit_mark_box.cpp:44-59`
  - AyuGram has 3 buttons: Reset (left), Save (right), Cancel (right)
  - Dart has only 2 buttons: Reset (left), Save (right)
  - Users cannot cancel the dialog without closing the entire app or using system back button

- [x] [CRITICAL] No input validation — `edit_mark_box.dart:56-59` ← `edit_mark_box.cpp:73-80`
  - AyuGram calls `submit()` which validates `_text->getLastText().trimmed().isEmpty()` and shows error if empty
  - Dart `_save()` directly saves without validation, allowing empty strings to be saved
  - AyuGram shows error state via `_text->showError()` when user tries to save empty text
  - Dart has no error UI — silently accepts empty input

- [x] [MAJOR] Incorrect content padding — `edit_mark_box.dart:70` ← `edit_mark_box.cpp:37,92-93`
  - Dart hardcoded: `EdgeInsets.fromLTRB(24, 2, 24, 8)` 
  - AyuGram spec: `st::contactPadding = margins(49px, 2px, 0px, 14px)` — left padding is 49px, not 24px; right is 0px, not 24px; bottom is 14px, not 8px
  - This causes text field to be misaligned on desktop (too far left, not enough space on right)

- [x] [MAJOR] No error feedback UI — `edit_mark_box.dart:71-80` ← `edit_mark_box.cpp:74-76`
  - AyuGram calls `_text->setFocus()` and `_text->showError()` when submit fails
  - Dart has no equivalent — no error visual, no focus management on failed validation

- [x] [MAJOR] Missing Enter key validation — `edit_mark_box.dart:62-97` vs `edit_mark_box.cpp:61-67`
  - AyuGram: Enter calls `submit()` which validates empty text first (line 62-66 in cpp)
  - Dart: onConfirm → _save() directly (line 68 in dart) — no validation, allows empty input on Enter
  - Users can accidentally save empty text by pressing Enter

- [x] [MINOR] Static title instead of reactive — `edit_mark_box.dart:25` ← `edit_mark_box.cpp:22,30`
  - AyuGram accepts `rpl::producer<QString> title` (reactive, can update mid-dialog)
  - Dart uses `final String title` (static)
  - Low priority but differs from original design

## Summary

The edit_mark_box is **functionally broken** — missing Cancel button, no input validation, wrong padding. A user can save empty text, and there's no way to cancel without system back button.

**Blocking fixes needed before shipping:**
1. Add Cancel button to buttons list
2. Implement validation in _save() to reject empty input and show visual feedback
3. Fix padding to match AyuGram spec (49, 2, 0, 14)
4. Add TextField error state display when validation fails

# emoji_panel — Audit Findings

## emoji_panel — placeholder/stub, persistence gaps, wrong height ratio, sticker context menu incomplete, sticker/GIF not sent as documents

- [ ] [CRITICAL] `onTap: () {}` on the "Add"/"Unlock" button in `_CustomPackHeader` is a no-op placeholder — tapping "Add" on an uninstalled custom emoji pack does nothing; AyuGram calls `_localSetsManager->install(setId)` via the panel's add-button — `emoji_panel.dart:1083` ← `AyuGram/chat_helpers/stickers_list_widget.cpp:2318`

- [ ] [CRITICAL] Sticker and GIF selection does NOT send a sticker/GIF document — both `onStickerSelected` and `onGifSelected` funnel into `onEmojiSelected` (a `ValueChanged<String>`), which in `chat_view.dart` inserts emoji/fileId as plain text into the compose field; AyuGram fires `_chosen.fire({.document = document})` and `_fileChosen.fire({.document = document})` — `emoji_panel.dart:496-497, 1773, 2280` ← `AyuGram/chat_helpers/stickers_list_widget.cpp:2168`, `AyuGram/chat_helpers/gifs_list_widget.cpp:541`

- [ ] [CRITICAL] Recent emojis (`_recentEmojis`) and skin tone preferences (`_skinTonePrefs`) are module-level Dart variables — they are never persisted to disk or loaded from storage; after app restart both lists are empty; AyuGram persists these in the session database — `emoji_panel.dart:30, 760`

- [ ] [CRITICAL] `_kHeightRatio = 0.55` but AyuGram `emojiPanHeightRatio: 0.75` — the panel height is 27% too short relative to the window height; this crushes vertical space for grids — `emoji_panel.dart:18` ← `AyuGram/chat_helpers/chat_helpers.style:497`

- [ ] [MAJOR] Sticker context menu is missing the "Remove from Recent" option that AyuGram shows when the sticker is in the Recent section (`lng_recent_stickers_remove` → calls `Api::ToggleRecentSticker`); the Dart menu only has Fave/Unfave and View Set — `emoji_panel.dart:1564-1568` ← `AyuGram/chat_helpers/stickers_list_widget.cpp:2209-2215`

- [ ] [MAJOR] "View Set" context menu item (`value == 'view_set'`) has no handler in `.then()` — the value is produced by the menu but no `else if (value == 'view_set')` branch exists, so tapping it silently does nothing; AyuGram opens a full sticker set box — `emoji_panel.dart:1566, 1570-1585` ← `AyuGram/chat_helpers/stickers_list_widget.cpp:2203-2206`

- [ ] [MAJOR] Pack section headers in the sticker grid have no "remove set" (uninstall) button; AyuGram renders a 20×20 `stickerPanRemoveSet` icon button at the right of every pack header that calls `MTPmessages_UninstallStickerSet` — `emoji_panel.dart:1784-1797` ← `AyuGram/chat_helpers/stickers_list_widget.cpp:1358-1382, 3296-3383`

- [ ] [MAJOR] `_kEmojiCellSize = 40.0` but AyuGram `stickersEmojiPickerItemSize: 30px` (the skin-tone picker item size) and `emojiSuggestionSize: 40px` — the skin-tone popup popup cells use `_kEmojiCellSize` (40px) while the correct picker strip item size is 30px, making the popup 33% wider than spec — `emoji_panel.dart:23, 992-996` ← `AyuGram/chat_helpers/chat_helpers.style:436`

- [ ] [MAJOR] `_kCategoryBarHeight = 38.0` but AyuGram `footer: 36px` and `stickersEmojiPickerStripHeight: 40px`; the emoji category bar at bottom uses 38px while spec defines 36px for the footer bar — `emoji_panel.dart:25` ← `AyuGram/chat_helpers/chat_helpers.style:438, 749`

- [ ] [MAJOR] GIF search resolves the bot username by hardcoding `'gif'` (`resolveUsername(accountId, 'gif')`); AyuGram reads `session().serverConfig().gifSearchUsername` from the server config, which varies by DC/deployment — the hardcoded string will fail for non-default server configs — `emoji_panel.dart:2264` ← `AyuGram/chat_helpers/gifs_list_widget.cpp:925`

- [ ] [MAJOR] GIF search results displayed while query field is loading (before `_searchQuery` is set) show a spinner but `_searching` is set to `true` before `_gifBotId` is resolved, so typing immediately sends the first character to `resolveUsername` every time the search bot is not cached, racing against quick typing — `emoji_panel.dart:2235, 2263-2270`

- [ ] [MAJOR] Featured sticker packs do not display the unread badge (small colored dot) for newly added packs that have not been viewed; AyuGram renders `stickersFeaturedUnreadSize: 5px` dot next to the "Add" button for unread featured packs — `emoji_panel.dart:1801-1915` ← `AyuGram/chat_helpers/chat_helpers.style:411-413`, `AyuGram/chat_helpers/stickers_list_widget.cpp:1291-1305`

- [ ] [MAJOR] The `_TabBar` widget uses text labels ("Emoji", "Stickers", "GIFs") for tabs; AyuGram uses icon-based category strip (ComposeIcons) not text labels for the main selector — `emoji_panel.dart:417, 443-474` ← `AyuGram/chat_helpers/chat_helpers.style:738-782`

# emoji_status_widget — Missing gzip import, hardcoded loop limit deviation

- [ ] [CRITICAL] Missing `import 'dart:convert';` — `gzip.decode()` called at line 146 but gzip not imported; will silently fail at runtime when decompressing TGS (animated emoji status) files — `emoji_status_widget.dart:146` ← `text_custom_emoji.cpp` (AyuGram LimitedLoopsEmoji wrapping pattern shows proper gzip decompression needed for animation playback)

- [ ] [MAJOR] Hardcoded `_maxLoops = 2` limits emoji status animations to 2 loops — differs from AyuGram default which loops indefinitely (LimitedLoopsEmoji used only when explicitly configured); the Dart widget will stop animating after 2 complete loops while AyuGram emoji badges can loop continuously — `emoji_status_widget.dart:33,162-170` ← `info_profile_badge.cpp:140-143` (AyuGram only wraps with LimitedLoopsEmoji when `_customStatusLoopsLimit > 0`, default is 0 meaning no limit)

- [ ] [MAJOR] "userpic:" emoji status silently ignored with no special handling — code parses and discards the userpic prefix at line 101-103 without extracting or using any data from it; may need separate rendering path like AyuGram's userpic emoji builder — `emoji_status_widget.dart:101-103` ← `info/userpic/info_userpic_emoji_builder.cpp` (AyuGram has dedicated userpic emoji builder modules for proper rendering)

# filter_column — Audit findings

- [ ] [CRITICAL] `case 'edit': break;` — "Edit Folder" context menu action is a stub that does nothing — `filter_column.dart:294-295` ← `window/window_filters_menu.cpp:447` (`EditExistingFilter(_session, id)`)

- [ ] [CRITICAL] Edit button at bottom opens the app drawer (`widget.onOpenDrawer`) instead of the Folders settings page — `filter_column.dart:432` ← `window/window_filters_menu.cpp:417-429` (`openFiltersSettings()` → `showSettings(Settings::FoldersId())`)

- [ ] [CRITICAL] Filter icons are guessed from folder name keywords using generic Material icons (`Icons.folder`, `Icons.group`, etc.) instead of real Telegram filter icons — `filter_column.dart:53-62` ← `window/window_filters_menu.cpp:327-330` (`Ui::LookupFilterIcon(Ui::ComputeFilterIcon(filter))` with SVG icons)

- [ ] [CRITICAL] Hamburger button never shows the other-accounts unread badge — always passes `unreadCount: 0`; AyuGram wires `OtherAccountsUnreadState` to switch the icon to `windowFiltersMainMenuUnread` / `windowFiltersMainMenuUnreadMuted` when other accounts have unreads — `filter_column.dart:323-331` ← `window/window_filters_menu.cpp:162-178`

- [ ] [CRITICAL] No locked/premium folder handling — tapping a folder beyond the free limit should show a `FiltersLimitBox` upgrade prompt; Dart unconditionally calls `setActiveFolder` on all folders — `filter_column.dart:409-415` ← `window/window_filters_menu.cpp:371-376` (`raw->locked()` check + `FiltersLimitBox`)

- [ ] [MAJOR] Badge font is `fontSize: 10` but AyuGram specifies `badgeStyle.font: font(12px semibold)` — `filter_column.dart:579` ← `window/window.style:262-264`

- [ ] [MAJOR] Context menu is missing the "Remove Folder" (destructive) action — AyuGram shows Edit + Mark as Read + Remove; Dart only shows mark_read + edit (stub) — `filter_column.dart:271-283` ← `window/window_filters_menu.cpp:458-465`

- [ ] [MAJOR] Drag-over auto-switch timer is 2000 ms; AyuGram uses `ChoosePeerByDragTimeout = 1000 ms` — `filter_column.dart:94` ← `config.h` (`ChoosePeerByDragTimeout = 1000`) + `window/window_filters_menu.cpp:401`

- [ ] [MAJOR] No animated scroll-to-button when the active folder changes — AyuGram uses a `_scrollToAnimation` with `st::slideDuration`/`sineInOut` easing to scroll the sidebar list so the newly-active tab is visible; Dart has no equivalent — `filter_column.dart:65-436` ← `window/window_filters_menu.cpp:180-204`

# ayu_filter — Regex filter engine audit

## Critical Issues Found

- [ ] [CRITICAL] **Media type mapping is incorrect** — `ayu_filter.dart:119-128` ← `AyuGramDesktop/.../filters_utils.cpp:534-638`
  - Input type 4 (voice) maps to 15 (animated sticker in AyuGram), should map to 2 (TYPE_VOICE)
  - Input type 5 (videonote) maps to 12 (contact in AyuGram), should map to 5 (TYPE_ROUND_VIDEO)
  - Input type 7 (gif) maps to 11 (action photo in AyuGram), should map to 8 (TYPE_GIF)
  - Missing many media types: service messages (10), contact (12), poll (17), location (4), stories (23-24), gifts (18,25,30), giveaways (26,28), paid media (29), emojis (19), etc.
  - The full `typeOfMessage()` function in AyuGram returns 30 distinct codes; Dart only maps 8 input types to ~7 output codes
  - Result: Media-based filtering will fail for ~70% of message types in AyuGram Desktop

- [ ] [CRITICAL] **Shadow-ban check missing conditional** — `ayu_filter.dart:307-314` ← `AyuGramDesktop/.../filters_controller.cpp:95-136`
  - Dart: Filters ALL messages from shadow-banned users regardless of context
  - AyuGram: Only filters messages from shadow-banned users if `item->from() != item->history()->peer` (i.e., NOT in 1:1 conversations with the user)
  - Dart code: `if (appState.isShadowBanned(senderId)) return true;` (no peer context check)
  - AyuGram code: `if (isShadowBanned(item->from()) && item->from()->id != item->history()->peer->id) { shadowBanMatched = true; return true; }`
  - Result: Messages from shadow-banned users in private chats will be incorrectly hidden (should only hide messages about them, not from them in 1:1s)

- [ ] [CRITICAL] **Missing group/album message handling** — `ayu_filter.dart:130-178` ← `AyuGramDesktop/.../filters_utils.cpp:658-685`
  - Dart: Extracts text only from single message (`msg.contentText` + inline entities)
  - AyuGram: Extracts text from ALL items in a message group/album, concatenates with `\n`
  - CachedMessage has no group reference, so cannot implement this without model change
  - Result: When filtering grouped messages (photo albums with captions), only the first message is checked; other grouped items aren't matched

## Major Issues Found

- [ ] [MAJOR] **Entity extraction format mismatch** — `ayu_filter.dart:135-157` ← `AyuGramDesktop/.../filters_utils.cpp:640-656`
  - Dart: Parses `contentRich` as JSON and looks for fields: `{'type': 'url'|'text_url', 'url': '...', 'offset': ..., 'length': ...}`
  - AyuGram: Uses `original.entities` API objects directly, checks `entity.type() == EntityType::Url` or `EntityType::CustomUrl`, then `entity.data()` or substring by offset/length
  - Both approaches functionally equivalent IF the Go backend correctly serializes entities into JSON format
  - Risk: If Go serialization doesn't match expected JSON schema, URL extraction fails silently (try/catch at line 156 swallows all errors)

- [ ] [MAJOR] **Missing service message type detection** — `ayu_filter.dart:0-0` ← `AyuGramDesktop/.../filters_utils.cpp:534-638`
  - Dart: No check for `msg.isService` flag; doesn't detect service messages (joins, leaves, title changes, etc.)
  - AyuGram: `if (item->isService()) { ... return 10 or other service types }`
  - Result: Service messages are treated as text (type 0) instead of their actual type; cannot filter by "is service message"

- [ ] [MAJOR] **Unbounded message cache growth** — `ayu_filter.dart:180-346`
  - Cache map `_messageCache` only grows, never shrinks: `_messageCache[cacheKey] = result`
  - No eviction, no size limits, no TTL
  - AyuGram also has unbounded cache but with `filteredMessages.clear()` on `rebuildCache()` (line 97)
  - Dart calls `invalidateMessage()` for individual items but nothing triggers full clear
  - Risk: In long sessions with many messages, memory usage grows monotonically until app restart

- [ ] [MAJOR] **Inconsistent button formatting** — `ayu_filter.dart:161` ← `AyuGramDesktop/.../filters_utils.cpp:675`
  - Dart: `buf.write('\n<button>${btn.text} ${btn.data}</button>');`
  - AyuGram: `text.append("<button>").append(button.text).append(" ").append(qs(button.data)).append("</button>");`
  - Functionally equivalent but order differs: Dart includes `\n` inside write call, AyuGram with separate append
  - Minor impact on string matching

## Warnings (Not showstoppers, but notable differences)

- [ ] **No inline keyboard handling in entity extraction** — `ayu_filter.dart:135-157`
  - Dart extracts URLs from `contentRich` entities separately from inline keyboards (lines 159-162)
  - AyuGram extracts URLs from text entities, then separately processes reply markup buttons
  - Dart's approach may duplicate URLs if they appear both as text entities and in inline buttons (no deduplication)

- [ ] **Reversed pattern logic matches both implementations** — `ayu_filter.dart:112-116` ← `AyuGramDesktop/.../filters_controller.cpp:49-65`
  - Both correctly handle inverted patterns: `return filter.reversed ? !found : found`
  - AyuGram: `if ((!reversed && match) || (reversed && !match)) return true;` (equivalent)
  - ✓ No issue, just confirming correctness

- [ ] **Regex compilation flags match** — `ayu_filter.dart:105` ← `AyuGramDesktop/.../filters_cache_controller.cpp:55-56`
  - Both: `multiLine: true` + optional `caseSensitive` flag
  - Dart uses Dart's `RegExp`, AyuGram uses ICU regex (unicode/regex.h)
  - May have subtle differences in regex behavior (lookahead, backrefs, etc.) but basic patterns work the same
  - ✓ No issue for standard patterns

## Summary

**6 items require fixing:**
1. Fix media type mapping (voice→2, videonote→5, gif→8, add missing types)
2. Add shadow-ban conditional check (only filter if not in 1:1 conversation)
3. Document limitation: group messages not filterable without CachedMessage.groupId
4. Verify Go backend JSON serialization of entities matches expected schema
5. Add service message type detection
6. Add cache eviction policy (clear on rebuildCache or size limit)

**Current status: BROKEN FOR PRODUCTION**
- Filtering will silently drop ~70% of media types
- Shadow-banning will over-filter (hiding legitimate messages)
- Grouped messages won't be filtered correctly
- Cache will leak memory over time

# folders_settings_screen — Audit

- [ ] [CRITICAL] `_TagsToggleState._onToggle` debounce timer is a stub with an empty body and comment "Debounced server request would go here" — folder tags toggle setting is never persisted to backend — `folders_settings_screen.dart:987-989` ← `AyuGramDesktop/Telegram/SourceFiles/settings/settings_folders.cpp` (filter update calls `session->api().request()` to persist filter changes immediately)

# forum_topic_icon — Audit Findings

- [ ] [CRITICAL] `_bubblePathD` coordinates don't match AyuGram SVG source — Dart uses slightly different control-point values throughout the entire path (e.g. first point `M42,4.42105263` vs AyuGram `M42,4.47368421`, `80.5789474` vs `80.5263158`, etc.), so the rendered bubble outline shape deviates from the spec — `forum_topic_icon.dart:123` ← `AyuGramDesktop/Telegram/Resources/art/topic_icons/blue.svg:18`

- [ ] [CRITICAL] `extractTopicLetter` silently drops Chinese, Japanese and Korean topic titles — the `code > 0x2600` guard skips all code points above U+2600, which includes CJK Unified Ideographs (U+4E00+), Hiragana/Katakana (U+3040+) and Hangul (U+AC00+); AyuGram's `ExtractNonEmojiLetter` uses `Ui::Emoji::Find()` to skip only actual emoji codepoint sequences and accepts all `QChar::isLetterOrNumber()` values including CJK, so those topics show no letter overlay in Dart but do in AyuGram — `forum_topic_icon.dart:115` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_forum_topic.cpp:101`

- [ ] [MAJOR] Default fallback palette is blue instead of gray — when `colorId` is not one of the six known values, Dart falls back to `topicIconPalettes[0x6FB9F0]` (blue), whereas AyuGram's `ForumTopicDefaultIcon()` returns `"gray"` causing it to load `gray.svg` (neutral gray gradient); topics with unrecognised color IDs render with wrong gradient — `forum_topic_icon.dart:58` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_forum_topic.cpp:71`

# ghost_settings_page — Ghost Settings Page Audit

- [ ] [CRITICAL] `sendWithoutSound` is stored and rendered as a `bool` toggle, but AyuGram defines it as `SendWithoutSoundOption` enum with three values (Never=0, InGhostMode=1, Always=2) rendered as a 3-option dropdown — `ghost_settings_page.dart:165-171` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ayu_settings.h:48-83` and `settings_ayu.cpp:504-544`

- [ ] [CRITICAL] `suggestGhostModeBeforeViewingStory` toggle is entirely missing — AyuGram includes it in the ghost essentials section after the sendWithoutSound button; no AppState field or UI widget for it exists in Dart — `ghost_settings_page.dart` (absent) ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_ayu.cpp:547-564`

- [ ] [CRITICAL] Account picker `onScopeChanged` callback silently drops the `userId` argument — selecting account A only calls `setUseGlobalGhostMode(false)` and ignores which account was chosen, so all ghost toggles always reflect the active/global account rather than the picker-selected account; AyuGram maintains a per-page `state->selectedUserId` that drives all lockable-toggle reads and writes — `ghost_settings_page.dart:60-69` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_ayu.cpp:283-346`

- [ ] [MAJOR] No auto-migration from per-account to global settings when only one active account exists — AyuGram copies all per-account ghost settings to the global slot (userId=0) on section build when `activeCount <= 1 && !useGlobalGhostMode`; the Dart page is a `StatelessWidget` with no such initialization logic — `ghost_settings_page.dart:16` (absent) ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_ayu.cpp:319-337`

- [ ] [MAJOR] No description hint below the Ghost Mode toggle explaining the shift-click/long-press to lock gesture — AyuGram renders `tr::ayu_GhostModeOptionShiftDescription` immediately after the collapsible ghost toggle; without it users have no way to discover the lock feature — `ghost_settings_page.dart:72-142` (absent) ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_ayu.cpp:427-430`

# hamburger_drawer — Critical wiring errors, wrong LRead/SRead semantics, positional bugs

- [ ] [CRITICAL] `showLReadToggleInDrawer` row is wired as a stateful `sendReadMessages` toggle (`_InlineToggle` + `setSendReadMessages()`), but in AyuGram it is a **one-shot "mark all chats read without sending receipts"** action: it temporarily disables `sendReadMessages`, calls `MarkAsReadChatList`, then restores the original value — it never persistently changes the setting — `hamburger_drawer.dart:371-379` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_main_menu.cpp:767-782`

- [ ] [CRITICAL] `showSReadToggleInDrawer` row is wired as a stateful `sendReadStories` toggle (`_InlineToggle` + `setSendReadStories()`), but in AyuGram it is a **one-shot "mark all chats read WITH receipts"** action that first shows a confirmation dialog, then temporarily enables `sendReadMessages`, calls `MarkAsReadChatList` with a 200 ms delay for forums, and restores — it is not a story-read toggle — `hamburger_drawer.dart:382-390` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_main_menu.cpp:784-813`

- [ ] [CRITICAL] `_FooterSection._openUrl` calls `Process.run('xdg-open', [url])` which is Linux-only; on Windows, macOS, and Android the call silently fails, making all footer links (UniClient repo, releases, About) non-functional on those platforms — `hamburger_drawer.dart:1565` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_main_menu_helpers.cpp:41-53` (Qt handles cross-platform URL opening transparently)

- [ ] [MAJOR] "Log Out" is always added to the account-row context menu regardless of whether the account is active, but in AyuGram `Log Out` is only added for **inactive** accounts (`if (!isActive)`) — logging out the active account from the switcher is not supported in the reference — `hamburger_drawer.dart:1013-1014` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_information.cpp:59-80`

- [ ] [MAJOR] The entire lower half of the cover (from `mainMenuCoverNameTop = 84px` to `mainMenuCoverHeight = 134px`) is a single `ToggleAccountsButton` click target in AyuGram, so clicking the name or status text also toggles the account list; in the Dart only the 48×48 userpic and the 24×24 chevron widget are `GestureDetector` tap targets — the name and status text are not tappable — `hamburger_drawer.dart:597-650` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_main_menu.cpp:934-948`

- [ ] [MAJOR] Account-list toggle chevron is positioned at `right: 18, top: 18` (top-right corner, y ≈ 30 px from cover top), but `mainMenuTogglePosition: point(30px, 30px)` places it at `(width − 30, coverHeight − 30) = (width − 30, 104)` — 30 px above the bottom edge of the cover, adjacent to the status text, not in the top corner — `hamburger_drawer.dart:653-657` ← `AyuGramDesktop/Telegram/SourceFiles/window/window.style:165` + `window_main_menu.cpp:197-202`

- [ ] [MAJOR] "New Group" and "New Channel" rows have no right-click handler; in AyuGram `AddMyChannelsBox()` wraps both buttons and adds a right-click popup listing the user's own groups/channels — `hamburger_drawer.dart:212-228` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_main_menu_helpers.cpp:55-273`

- [ ] [MAJOR] Menu-bot rows have no right-click handler; in AyuGram each bot button has a right-click popup with "Remove from Menu" (`bots->removeFromMenu()`) — `hamburger_drawer.dart:179-199` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_main_menu_helpers.cpp:327-350`

- [ ] [MAJOR] "Add Account" right-click context menu is triggered by any right-click; in AyuGram (non-debug builds) the Production/Test context menu requires **Alt+Shift + right-click** (`IsAltShift(clickModifiers())`); plain right-click is a no-op — `hamburger_drawer.dart:908-912` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_information.cpp:63-70`

- [ ] [MAJOR] "Saved Messages" row silently does nothing when the chat is not yet present in `chatState.chats`; AyuGram calls `controller->showPeerHistory(controller->session().user())` which always works regardless of whether the history is in the dialog list — `hamburger_drawer.dart:255-264` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_main_menu.cpp:759-765`

# info_panel — Audit Findings

- [ ] [CRITICAL] "Message" action button in DM cover has `onTap: null` — tapping it does nothing. AyuGram calls `window->showPeerHistory(peer->id, ...)` to navigate to the chat. — `info_panel.dart:823` ← `AyuGram/info/profile/info_profile_top_bar.cpp:780-784`

- [ ] [CRITICAL] "Call" action button in DM cover has `onTap: null` — tapping it does nothing. AyuGram calls `Core::App().calls().startOutgoingCall(user, {})`. — `info_panel.dart:835` ← `AyuGram/info/profile/info_profile_top_bar.cpp:900-903`

- [ ] [CRITICAL] "Boosts" menu item in stats menu is a dead stub — when selected, no navigation occurs. The `if (value == 'statistics')` branch handles stats but there is no `case 'boosts'` handler. AyuGram has a full separate `Info::Boosts` section (`info_boosts_widget.cpp`). — `info_panel.dart:1784-1799` ← `AyuGram/info/channel_statistics/boosts/info_boosts_widget.h`

- [ ] [CRITICAL] `_ForumTopicsDialog` always initialises `_enabled = false` regardless of whether the group already has topics enabled. `chat.isForum` is available in `ChatInfo` but is never read in `initState`. Opening the dialog on a forum group shows "Topics: Off" incorrectly, and saving overwrites the real state. — `info_panel.dart:3092` ← `AyuGram/info/profile/info_profile_actions.cpp` (forum toggle reads live peer state)

- [ ] [CRITICAL] `_PublicForwardRow.onTap` is an empty callback `onTap: () {}`. AyuGram's `PublicForwardsController::rowClicked` navigates to the forwarded message or story in the referenced peer. Tapping a public forward row in Dart does nothing. — `info_panel.dart:7437` ← `AyuGram/info/statistics/info_statistics_list_controllers.cpp:370-373`

- [ ] [CRITICAL] `_MiniWaveformPainter` renders a static deterministic fake waveform using `rng = 42` constant and `(i * 42 + 17) % 13` — no actual audio waveform data from the message is used. Every voice message in shared media shows the same pattern. — `info_panel.dart:5001-5006` ← `AyuGram/info/media/info_media_list_widget.cpp` (renders real waveform bytes from message)

- [ ] [MAJOR] `_SharedMediaSubPage._loadItems` fetches at most 200 items with a fixed `limit: 200` and no pagination cursor. Channels with thousands of photos will silently show only the first 200 with no "load more". AyuGram's `info_media_provider` uses incremental loading with scroll-triggered pagination. — `info_panel.dart:2266-2275`

- [ ] [MAJOR] `_SharedMediaSection` (inline preview in chat info) uses a fixed `limit: 100` with no pagination. Same issue — large shared media sets truncated silently. — `info_panel.dart:3763-3776`

- [ ] [MAJOR] `_MediaGrid` and `_MediaListView` render all items eagerly into a `Column` inside `SingleChildScrollView`. For large media sets this is an OOM/jank risk. AyuGram uses a virtualised list (`SliverList`/lazy delegates). — `info_panel.dart:4504-4537`, `4748-4762`

- [ ] [MAJOR] `_UserProfilePage` (pushed when tapping a member) shows no shared media section. AyuGram's profile info for any peer includes a shared media count section (photos, videos, files, etc.). — `info_panel.dart:2168-2216` ← `AyuGram/info/profile/info_profile_inner_widget.cpp`

- [ ] [MAJOR] Cover action buttons overflow fallback at line 840–843 is a stub: `// overflow popup placeholder — wired when call UI lands`. When more than 3 action buttons are needed the "More" button is shown but clicking it does nothing (empty callback). — `info_panel.dart:840-843`

- [ ] [MAJOR] `_CommonGroupsRow` displays a count and a chevron but has no `onTap`. AyuGram navigates to a full common groups list when tapped. — `info_panel.dart:2839-2864` ← `AyuGram/info/profile/info_profile_actions.cpp` (common groups action)

- [ ] [MAJOR] Public forwards list in `_MessageStatsPage` only shows the initial batch returned by `getMessageStats` — there is no infinite scroll / load-more. AyuGram's `PublicForwardsController::loadMoreRows` uses a paginated token API to load the full list. — `info_panel.dart:7267-7276` ← `AyuGram/info/statistics/info_statistics_list_controllers.cpp:342-348`

# input_dialogs — Input Dialogs Audit

## Username Box

- [ ] [CRITICAL] Multiple usernames not supported — Dart only has a single username field; AyuGram uses `UsernamesList` widget alongside the editor, allowing up to 32 usernames per account with reordering — `input_dialogs.dart:80-329` ← `AyuGram/boxes/username_box.cpp:362-393`

- [ ] [MAJOR] Debounce timer is 400 ms instead of 200 ms — `input_dialogs.dart:194` ← `AyuGram/boxes/peers/edit_peer_common.h:17` (`kUsernameCheckTimeout = crl::time(200)`)

- [ ] [MAJOR] `@` prefix rejected by regex — AyuGram's `changed()` allows `@` only at index 0 and strips it in `getName()` before sending to API; Dart's `^[a-zA-Z][a-zA-Z0-9_]{4,31}$` rejects `@myusername` with "invalid" error — `input_dialogs.dart:119,179-186` ← `AyuGram/boxes/username_box.cpp:209-213` (`ch != '@' || i > 0`) and `310` (`replace('@', QString())`)

## Add Contact Box

- [ ] [MAJOR] Default country hardcoded to `US` — AyuGram pre-fills country code from the session user's own phone via `Countries::ExtractPhoneCode(session->user()->phone())`; Dart always defaults to US regardless of user locale — `input_dialogs.dart:380` ← `AyuGram/boxes/add_contact_box.cpp:304`

- [ ] [MAJOR] First/last name order not locale-aware — AyuGram checks `langFirstNameGoesSecond()` and inverts tab order + field positions for locales (e.g. Japanese/Korean) where last name comes first; Dart always shows first name first — `input_dialogs.dart:528-534` ← `AyuGram/boxes/add_contact_box.cpp:307,314-315,398-408`

- [ ] [MAJOR] No navigation to peer after adding contact — AyuGram calls `window->showPeerHistory(user)` when a new contact is found and then hides the layer; Dart just pops the dialog — `input_dialogs.dart:486` ← `AyuGram/boxes/add_contact_box.cpp:486-499`

- [ ] [MAJOR] Phone number grouping is wrong — AyuGram uses `Countries::Groups(s)` for country-specific grouping (e.g. US: `XXX XXX XXXX`, not uniform triplets); Dart's `_PhoneNumberFormatter` inserts a space every 3rd digit unconditionally — `input_dialogs.dart:651-683` ← `AyuGram/boxes/add_contact_box.cpp:300-306` (`[](const QString &s) { return Countries::Groups(s); }`)

- [ ] [MAJOR] Special test phone validation differs — AyuGram accepts `42`-prefix numbers at lengths 2, 5, 6, and exactly `4242`; Dart only accepts `^42\d\d$` (length 4 only), missing length-2, 5, 6 cases — `input_dialogs.dart:412-415` ← `AyuGram/boxes/add_contact_box.cpp:54-63`

## Country Picker

- [ ] [MAJOR] Row height 40 px vs spec 36 px — `input_dialogs.dart:753` (`itemExtent: 40`) ← AyuGram style skeleton (`countryRowHeight: 36px`) and `AyuGram/ui/boxes/country_select_box.cpp:235` (`_rowHeight(st::countryRowHeight)`)

- [ ] [MAJOR] Filtering uses `contains` instead of word-start match — AyuGram's `updateFilter` only matches entries where a name component *starts with* the search word (`name.startsWith(word)`); Dart uses `.contains(q)` which returns false positives — `input_dialogs.dart:712-713` ← `AyuGram/ui/boxes/country_select_box.cpp:488-493`

- [ ] [MAJOR] Selected country not moved to top of list — AyuGram places the currently selected country first (`LastValidISO` logic in `init()`), so it's immediately visible when the picker opens; Dart keeps alphabetical order — `input_dialogs.dart:709-714` ← `AyuGram/ui/boxes/country_select_box.cpp:277-285`

## Edit Invite Link Box

- [ ] [CRITICAL] Custom expiry date picker missing — AyuGram includes a `0` (Custom) option in the expiry radio list that opens a `ChooseDateTimeBox`; Dart only offers five hardcoded presets with no way to set an arbitrary date — `input_dialogs.dart:861-874` ← `AyuGram/ui/boxes/edit_invite_link.cpp:242-321`

- [ ] [CRITICAL] Custom usage limit input missing — AyuGram includes a `0` (Custom) option in the usage list that opens a `NumberInput` dialog; Dart only offers `Unlimited/1/10/100` — `input_dialogs.dart:869-874` ← `AyuGram/ui/boxes/edit_invite_link.cpp:323-369`

- [ ] [MAJOR] Default expiry is 30 days instead of Never — Dart initialises `_expireOption = 2592000` (30 days); AyuGram defaults to `kMaxLimit` (never expires) — `input_dialogs.dart:854` ← `AyuGram/ui/boxes/edit_invite_link.cpp:91` (`const auto expire = data.expireDate ? data.expireDate : kMaxLimit`)

- [ ] [MAJOR] No label max-length enforcement — AyuGram calls `labelField->setMaxLength(kMaxLabelLength)` (32 chars); Dart has no character limit on the label input — `input_dialogs.dart:968-972` ← `AyuGram/ui/boxes/edit_invite_link.cpp:29,171` (`constexpr auto kMaxLabelLength = 32`)

## Create Poll Box

- [ ] [CRITICAL] Max options cap is 10 instead of 32 — Dart returns early at 10 options (`if (_optionCtrls.length >= 10) return`); AyuGram sets `kMaxOptionsCount = PollData::kMaxOptions = 32` — `input_dialogs.dart:1142` ← `AyuGram/boxes/create_poll_box.cpp:104` and `AyuGram/data/data_poll.h:121`

- [ ] [CRITICAL] Quiz mode missing correct answer selection — Dart's `CreatePollResult` has only `quiz: bool` with no `correctOptionIndex`; AyuGram renders a radio button per option (`enableChooseCorrect`) when quiz mode is toggled so users pick which answer is correct — required by the Telegram API — `input_dialogs.dart:1092-1106,1257-1260` ← `AyuGram/boxes/create_poll_box.cpp:2601-2608`

- [ ] [CRITICAL] Quiz solution/explanation field missing — AyuGram shows a dedicated `setupSolution` text field (up to `kSolutionLimit = 200` chars) when quiz mode is enabled; Dart has no such field, making quiz polls uncreatable with explanations — `input_dialogs.dart:1122-1301` ← `AyuGram/boxes/create_poll_box.cpp:1370-1433,2740-2846`

- [ ] [CRITICAL] No question character limit — AyuGram enforces `kQuestionLimit = 255` chars and shows a warning at 80; Dart applies no limit to the question field — `input_dialogs.dart:1195-1198` ← `AyuGram/boxes/create_poll_box.cpp:103,1247` (`question->setMaxLength(kQuestionLimit + kErrorLimit)`)

- [ ] [CRITICAL] No option character limit — AyuGram enforces `kOptionLimit = 100` chars per option and warns at 30; Dart applies no limit — `input_dialogs.dart:1213-1216` ← `AyuGram/boxes/create_poll_box.cpp:105,372` (`_field->setMaxLength(kOptionLimit + kErrorLimit)`)

# instant_view — Critical wiring and missing block gaps

- [ ] [CRITICAL] `url` rich-text spans: `href` extracted at line 621 but immediately discarded — no `TapGestureRecognizer` attached, so every hyperlink in IV body is visually styled but completely non-interactive — `instant_view.dart:620-627` ← `iv_prepare.cpp:1074` (`<a href=...>` anchor tag)

- [ ] [CRITICAL] `email` rich-text spans have no `TapGestureRecognizer` and no `mailto:` handler — email addresses render in accent color but tapping does nothing — `instant_view.dart:628-631` ← `iv_prepare.cpp:1080` (`href: "mailto:" + email`)

- [ ] [CRITICAL] `phone` rich-text spans have no `TapGestureRecognizer` and no `tel:` handler — phone numbers render in accent color but tapping does nothing — `instant_view.dart:653-656` ← `iv_prepare.cpp:1090` (`href: "tel:" + phone`)

- [ ] [CRITICAL] Photos display only a base64 minithumbnail (`block['thumb']`) — AyuGram fetches and displays full-resolution photos via `photoFullUrl()` served through the webview data handler; users see blurry low-resolution placeholders — `instant_view.dart:277-298` ← `iv_prepare.cpp:500,525` (`photoFullUrl` vs `minithumbnail`)

- [ ] [CRITICAL] Six block types silently swallowed by `default: return SizedBox.shrink()`: `video`, `collage`, `slideshow`, `channel`, `audio`, `map` — videos, audio players, photo collages, slideshows, channel-join buttons, and map embeds are completely invisible in rendered IV pages — `instant_view.dart:231-233` ← `iv_prepare.cpp:115,121,122,123,124,131`

- [ ] [CRITICAL] `embed` block not actually embedded — AyuGram renders embed blocks as real HTML/iframe content via `IV.initEmbedBlocks()` JavaScript; Dart shows only a tappable plain-text URL that opens in the browser — `instant_view.dart:496-519` ← `iv_controller.cpp:284` (`hasEmbeds ? "IV.initEmbedBlocks();" : ""`)

- [ ] [MAJOR] Zoom control completely absent — AyuGram has Ctrl+/Ctrl−/Ctrl+0 keyboard shortcuts, a zoom menu item with +/− buttons and a percent readout (`ivZoomButtonsSize: 26px`, `ivResetZoom`), and persists zoom via `Delegate::ivSetZoom` — `instant_view.dart` (no zoom) ← `iv_controller.cpp:62-65,1103-1151` / `iv.style:30-58`

- [ ] [MAJOR] Back/forward navigation absent — AyuGram shows animated back/forward icon buttons wired to `window.history.back()` / `window.history.forward()` in the webview — `instant_view.dart` (no navigation history) ← `iv_controller.cpp:478-514`

- [ ] [MAJOR] Share functionality absent — AyuGram has a "Share" menu item that opens a share box overlay (`showShareMenu()`) — `instant_view.dart` (no share) ← `iv_controller.cpp:1140-1142,1194-1247`

- [ ] [MAJOR] `_fallbackToBrowser` and all external-open calls use `Process.run('xdg-open', ...)` which silently fails on Windows and macOS; should use `url_launcher` or platform-conditional logic — `instant_view.dart:61,89,117,511,567` ← portability requirement

- [ ] [MAJOR] Related articles fire `xdg-open` (external browser) instead of opening a new IV page inside the app — AyuGram fires `Event::Type::OpenPage` to reuse the IV controller — `instant_view.dart:566-567` ← `iv_controller.cpp:1051-1055`

- [ ] [MAJOR] Title font is 15px; AyuGram specifies `ivSubtitleFont: font(16px semibold)` — `instant_view.dart:83` ← `iv.style:68`

- [ ] [MAJOR] AppBar uses Flutter default height (~56 dp); AyuGram's subtitle bar is `ivSubtitleHeight: 48px` — `instant_view.dart:73` ← `iv.style:76`

- [ ] [MAJOR] Preformatted code blocks show plain monospace text with no syntax highlighting — AyuGram initialises syntax highlighting via `IV.initPreBlocks()` — `instant_view.dart:257-274` ← `iv_controller.cpp:283`

# keyboard_shortcuts — Shortcut system stubs, wrong handler implementations, missing commands

- [ ] [CRITICAL] `recordVoice` handler always returns false — key binding fires but voice recording never starts — `keyboard_shortcuts.dart:1105-1107` ← `shortcuts.cpp:532` (`Command::RecordVoice` is a real command dispatched to compose controls in AyuGram)

- [ ] [CRITICAL] `mediaPrevious` and `mediaNext` handlers check state but perform no action — both check `audio.currentMsgId.isNotEmpty` and return true/false without calling any skip/previous/next method on `AudioService` — `keyboard_shortcuts.dart:1227-1234` ← `shortcuts.cpp:47-54` (autoRepeatCommands includes MediaPrevious/Next, expected to advance track)

- [ ] [CRITICAL] `chatSwitchOverlayReverse` calls the identical `showChatSwitchRequest` as forward with no direction argument — overlay switch cannot navigate backwards — `keyboard_shortcuts.dart:1077-1080` ← `shortcuts.cpp:933-961` (AyuGram fires `{.action = Qt::Key_Backtab}` for reverse vs `Qt::Key_Tab` for forward)

- [ ] [CRITICAL] `isMediaViewerOpenCallback` uses `nav.canPop()` which is true whenever any dialog or route is pushed, not only when the media viewer is open — enables `mediaViewerVideoFullscreen` shortcut in wrong contexts (e.g. while settings dialog is open) — `keyboard_shortcuts.dart:1049-1056` ← `shortcuts.h:78` (`Command::MediaViewerFullscreen` scope should be gated on the media viewer overlay specifically)

- [ ] [CRITICAL] All ten format commands (formatBold, formatItalic, formatUnderline, formatStrike, formatCode, formatBlockquote, formatSpoiler, formatClear, formatLink, formatDate) have default key bindings but zero `registerHandler` calls anywhere in the codebase — `ShortcutSystem.dispatch()` will return false for all of them; Ctrl+B/I/U/K and all formatting shortcuts are completely non-functional — `keyboard_shortcuts.dart:956-975` (bindings) vs `keyboard_shortcuts.dart:1058-1265` (no format handlers) ← `shortcuts.h:15-90` (these exist as commands that widgets subscribe to via `Shortcuts::Requests()`)

- [ ] [CRITICAL] `openFilePicker` has a default binding (Ctrl+O, line 934) but no `registerHandler` ever registered — `ShortcutSystem.dispatch()` finds no handler, file picker never opens — `keyboard_shortcuts.dart:934-935` ← `shortcuts.cpp:525` (no default in AyuGram either, but the Dart code adds one without wiring it)

- [ ] [MAJOR] `supportReloadTemplates` handler calls `chatState.loadChats()` (reloads the chat list) instead of reloading support reply templates — `keyboard_shortcuts.dart:1237-1239` ← `support_templates.cpp:452-461` (AyuGram calls `Templates::reload()` which re-reads the templates file from disk and shows a toast)

- [ ] [MAJOR] `supportHistoryBack` and `supportHistoryForward` handlers call `ChatListPanel.requestNavigateChat(-1/1)` which moves through the chat list — AyuGram's handlers call `chatEntryHistoryMove(-1/1)` which navigates the support mode conversation history queue — `keyboard_shortcuts.dart:1254-1261` ← `window_session_controller.cpp:1966-1971`

- [ ] [MAJOR] `pastePlainText` command is in the enum, scoped, and appears in the settings UI but has no `registerHandler` registered anywhere — if a user binds a key to it in shortcuts-custom.json, the dispatch fires but nothing handles it — `keyboard_shortcuts.dart:91,192,265` (defined) vs absence of handler ← `shortcuts.h:15-90`

- [ ] [MAJOR] `RecordRound` command (video circle messages) is present in AyuGram but missing from the Dart `ShortcutCommand` enum entirely — cannot be bound or handled — absent from `keyboard_shortcuts.dart:22-99` ← `shortcuts.h:73` and `shortcuts.cpp:138`

- [ ] [MAJOR] Custom file reader does not handle the `"removed": true` flag — AyuGram writes entries with `{..., "removed": true}` when a default binding is deleted; the Dart `_loadCustomFile()` ignores unknown keys and treats such entries as add-binding-without-command null removals — `keyboard_shortcuts.dart:526-554` ← `shortcuts.cpp:434-449` (AyuGram checks `removed->toBool()` and calls `remove(key, command)`)

- [ ] [MAJOR] System media "search" and "find" key sequences (OS-level Search/Find keys on keyboards) are not mapped in `_keyNames` and therefore cannot be bound — AyuGram registers `"search"` and `"find"` as default bindings for `Command::Search` — absent from `keyboard_shortcuts.dart:279-324` ← `shortcuts.cpp:485-486`

- [ ] [MAJOR] Ctrl+Shift+X is assigned as a default binding to BOTH `supportHistoryBack` (line 945) and `formatStrike` (line 963) — when support mode is active and compose is focused, `supportHistoryBack` is dispatched first (it appears earlier in `_bindings`) and consumes the event, making strikethrough unreachable — `keyboard_shortcuts.dart:945-946,962-963` ← `shortcuts.cpp:499` (AyuGram only assigns Ctrl+Shift+X to `SupportHistoryBack`; format shortcuts have no defaults in AyuGram)

# language_box — Language box audit

- [ ] [CRITICAL] Selecting a language does not call any engine method to switch the app language. `_selectLanguage` only calls `appState.addRecentLanguage()` and pops the dialog. AyuGram calls `Lang::CurrentCloudManager().switchToLanguage(language)` which downloads and applies the language pack from Telegram's servers. — `language_box.dart:86-90` ← `AyuGram/boxes/language_box.cpp:1379-1392`

- [ ] [CRITICAL] Translation toggle settings (Show Translate Button, Translate Entire Chats) are never persisted. All callbacks go to `AppState` only; no engine calls are made from this file (only 1 engine call exists: `getLanguages`). AyuGram calls `Core::App().settings().setTranslateButtonEnabled()` + `saveSettingsDelayed()` and `setTranslateChatEnabled()` + `saveSettingsDelayed()`. — `language_box.dart:168,177` ← `AyuGram/boxes/language_box.cpp:1433-1470`

- [ ] [CRITICAL] "Do Not Translate" editor (`_SkipLanguagesEditor`) shows ALL Telegram interface languages from `engine.getLanguages()`. AyuGram's `EditSkipTranslationLanguages()` uses `TranslationLanguagesList()` — a curated ~80-language list of Google Translate-supported languages. These lists are completely different: Telegram UI language packs ≠ translation-capable languages. — `language_box.dart:104-115,719-728` ← `AyuGram/boxes/translate_box.cpp:121-148` + `AyuGram/ui/boxes/choose_language_box.cpp:27-128`

- [ ] [CRITICAL] Skip-translation language selection not persisted via engine. `appState.setSkipTranslationLanguages()` is in-memory only. AyuGram calls `Core::App().settings().setSkipTranslationLanguages()` + `Core::App().saveSettingsDelayed()`. — `language_box.dart:704` ← `AyuGram/boxes/translate_box.cpp:141-145`

- [ ] [CRITICAL] Language removal/restore is not persisted to local storage. `appState.addRemovedLanguage()` and `appState.restoreRemovedLanguage()` are in-memory only. AyuGram calls `Local::removeRecentLanguage(row->data.id)` on delete and `Local::saveRecentLanguages(...)` on restore. — `language_box.dart:605-608` ← `AyuGram/boxes/language_box.cpp:520-534`

- [ ] [MAJOR] Search uses substring matching (`contains(q)`) instead of AyuGram's prefix word matching. AyuGram uses `TextUtilities::PrepareSearchWords` + `item.startsWith(needle)` — only rows where every query word starts a keyword are shown. Searching "erm" would match "German" in Dart but not in AyuGram. — `language_box.dart:73-76` ← `AyuGram/boxes/language_box.cpp:662-700`

- [ ] [MAJOR] Recent language list does not pin the current language first. AyuGram's `PrepareLists()` uses `stable_partition` to place the active language at index 0 in recent; if it's not in recent at all, a fake entry is generated and prepended. Dart just iterates `recentLanguageCodes` in insertion order. — `language_box.dart:299-306` ← `AyuGram/boxes/language_box.cpp:258-298`

- [ ] [MAJOR] User can delete the currently selected language. AyuGram's `canRemove` returns false when `row->check->checked()` — the selected language is never removable. Dart shows the Delete option for any non-official language regardless of selection state. — `language_box.dart:404,581-587` ← `AyuGram/boxes/language_box.cpp:506-508`

- [ ] [MAJOR] `canShare` does not exclude `#`-prefixed lang IDs (`#custom`, etc.). AyuGram: `return !_areOfficial && !row->data.id.startsWith('#')`. Dart: `!lang.official` only — would show a Share option for custom lang packs, producing an invalid `https://t.me/setlanguage/#custom` link. — `language_box.dart:404,570-575` ← `AyuGram/boxes/language_box.cpp:502-504`

- [ ] [MAJOR] No keyboard navigation in the language list. AyuGram implements Up/Down/PageUp/PageDown/Home/End/Space/Return/Enter navigation through `LanguageBox::keyPressEvent` + `Rows::keyPressEvent` + `Rows::selectSkip`. Dart has no keyboard handling for the list. — `language_box.dart` (absent) ← `AyuGram/boxes/language_box.cpp:357-375,1504-1529`

- [ ] [MAJOR] `passportRowSkip` between title and description is 4px in Dart but 2px per spec. AyuGram row height = `passportRowPadding.top + titleHeight + passportRowSkip(2px) + descHeight + passportRowPadding.bottom`. — `language_box.dart:437` ← `AyuGram/passport/passport.style:110`

# emoji_data — Static emoji database vs. server-sourced

## Summary

The Dart emoji_data.dart implements a hardcoded static emoji search database, while AyuGram Desktop loads emoji keywords from Telegram's language pack servers. The Dart version works for basic emoji autocomplete but diverges significantly from AyuGram's architecture in data sourcing, language support, and recent emoji prioritization.

## Critical Issues

- [ ] [CRITICAL] **Hardcoded static emoji list instead of server-sourced language packs** — `emoji_data.dart:1-642` ← `emoji_keywords.cpp:608-642`
  - AyuGram loads emoji keywords from Telegram servers via `EmojiKeywords::query()` which pulls from multiple language packs (`_data` map at line 75 in emoji_keywords.h)
  - Dart version hardcodes all 638 emojis with only English keywords into `kEmojiSuggestions`
  - **Impact**: No multi-language support, keywords won't auto-update with server changes, user language preferences ignored

- [ ] [CRITICAL] **No recent emoji prioritization** — `emoji_data.dart:650-680` ← `emoji_keywords.cpp:650-672 (PrioritizeRecent)`
  - AyuGram ranks recently used emojis first via `PrioritizeRecent()` (line 650-672), which reads from `Core::App().settings().recentEmoji()`
  - Dart `searchEmoji()` returns results in fixed order: exact → prefix → contains, ignoring frequency
  - **Impact**: Users won't see their frequently-used emojis first; emoji suggestions don't adapt to user behavior

## Major Issues

- [ ] [MAJOR] **No emoji variant support (skin tones, modifiers)** — `emoji_data.dart:650-680` ← `emoji_keywords.cpp:674-680 (ApplyVariants)`
  - AyuGram applies user emoji variant preferences via `settings.lookupEmojiVariant(emoji)` (line 677), handling skin tone and modifier emoji variants
  - Dart version returns raw emoji strings with no variant application
  - **Impact**: Users' emoji tone preferences won't be respected; variant emoji won't display in their chosen style

- [ ] [MAJOR] **Duplicate emoji entry** — `emoji_data.dart:545` ← (no AyuGram equivalent, native data quality issue)
  - Line 539: `EmojiEntry('🧲', ['magnet', 'attract'])`
  - Line 545: `EmojiEntry('🧲', ['magnet'])` ← duplicate
  - **Impact**: Duplicate 🧲 in results; second entry is redundant and less informative (missing 'attract' keyword)
  - **Fix**: Remove line 545 entirely

- [ ] [MAJOR] **Missing legacy suggestion fallback** — `emoji_data.dart:650-680` ← `emoji_keywords.cpp:638-640 (AppendLegacySuggestions)`
  - AyuGram appends legacy emoji suggestions when query is not exact (line 639): `AppendLegacySuggestions(result, query)`
  - Dart version only returns matches from the hardcoded list; no fallback mechanism
  - **Impact**: If new emoji aren't in the Dart list, no suggestions; less future-proof

- [ ] [MAJOR] **Missing exact-match parameter** — `emoji_data.dart:650` signature ← `emoji_keywords.h:43-45`
  - AyuGram's `query()` accepts `bool exact` parameter (line 43) to control whether to append legacy suggestions
  - Dart version doesn't expose this; search always returns all match types
  - **Impact**: UI can't request exact-match-only searches if needed (low risk, but interface incompleteness)

- [ ] [MAJOR] **No emoji validation at load time** — `emoji_data.dart:1-642` ← (implied by emoji_keywords.cpp:78-82 FindExact)
  - AyuGram validates all emoji strings with `FindExact()` (line 78-82) during cache load; rejects invalid emoji
  - Dart hardcoded list is never validated; if an emoji string is malformed, it will silently fail in the UI
  - **Impact**: Low risk (emoji literals in source are safe), but data consistency is not enforced

## Wiring & Functional Status

✅ **Backend wiring is correct**: Emoji autocomplete is properly connected
- `searchEmoji()` is called in `chat_view.dart:3325` when `AutocompleteType.emoji` query triggers
- Results populate `_acFilteredEmojis`
- `_EmojiSuggestionPanel` renders results in UI (line 17377+)
- Tapping an emoji inserts it via `_insertAutocomplete()` (lines 3449, 3468)
- **Status**: Feature works end-to-end for basic emoji insertion

## Performance Notes

- Emoji search is O(n) per query: loops through all 638+ emoji entries (line 656)
- No caching of search results; repeated queries with same text re-scan the list
- For autocomplete at keystroke speed, this is acceptable (638 items is negligible), but could optimize with memoization
- AyuGram uses `std::map<QString, vector>` keyed by keyword (line 44 in emoji_keywords.cpp) for O(log n) lookup; Dart uses linear scan

## Recommendations

1. **High priority**: Remove duplicate magnet emoji (line 545) — trivial data cleanup
2. **Medium priority**: Implement server-sourced language packs instead of hardcoded list (aligns with AyuGram, enables multi-language)
3. **Medium priority**: Track and prioritize recently-used emojis (improves UX, matches AyuGram)
4. **Low priority**: Support emoji variants/skin tones via engine settings (future enhancement)
5. **Low priority**: Add memoization to `searchEmoji()` for repeated queries (micro-optimization)

---

**Comparison Complete**: Feature is functionally wired and working, but architectural differences (static vs. server-sourced, no recent tracking, no variants) may cause divergence as Telegram's emoji support evolves.

# media_viewer — Stub actions, broken clipboard, missing engine wiring

- [ ] [CRITICAL] `_cancelDownload` shows a toast instead of calling an engine cancel method — `media_viewer.dart:2705` ← `media_view_overlay_widget.cpp:3274` (`_document->cancel()`)

- [ ] [CRITICAL] `_showAttachedStickers` shows a toast instead of opening an attached-sticker-set picker — `media_viewer.dart:2709` ← `media_view_overlay_widget.cpp:3457` (`attachedStickers.requestAttachedStickerSets(window, _photo)`)

- [ ] [CRITICAL] `_setAsUserpic` shows a toast without calling any engine API — `media_viewer.dart:2713` ← `media_view_overlay_widget.cpp:2151` (`peer->session().api().peerPhoto().set(peer, photo)`)

- [ ] [CRITICAL] `_reportUserpic` shows a fake "Report sent" toast without opening a report dialog or calling any engine method — `media_viewer.dart:2717` ← `media_view_overlay_widget.cpp:2191` (`window->show(ReportProfilePhotoBox(peer, photo))`)

- [ ] [CRITICAL] `_viewStatistics` shows a toast instead of navigating to a statistics screen — `media_viewer.dart:2721` ← `media_view_overlay_widget.cpp:48` (includes `info_statistics_widget.h`)

- [ ] [CRITICAL] `_showOcrResult` shows a toast instead of performing OCR and displaying an in-overlay text result; additionally `_ocrAvailable` is hardcoded `false` (line 2866) so the OCR button is permanently hidden — `media_viewer.dart:2868` ← `media_view_overlay_widget.cpp:3396` (`recognize()` toggles `_showRecognitionResults` overlay)

- [ ] [CRITICAL] `_copyImageToClipboard` copies the file path as plain text instead of the actual image bitmap — `media_viewer.dart:2675` ← `media_view_overlay_widget.cpp:3435` (`mime->setImageData(image)` / `_photoMedia->setToClipboard()`)

- [ ] [CRITICAL] `_copyVideoFrame` copies the file path as plain text instead of extracting and copying the current video frame — `media_viewer.dart:2682` ← `media_view_overlay_widget.cpp:3431` (`transformedShownContent()` pixel capture)

- [ ] [CRITICAL] `_openDrawEditor` runs `xdg-open` to launch an external app instead of opening the in-app photo editor — `media_viewer.dart:2913` ← `media_view_overlay_widget.cpp:3405` (`requestDrawToReply()` launches the Editor module)

- [ ] [CRITICAL] Story reply compose "Attach file" button has empty `onTap: () {}` — `media_viewer.dart:5194` ← (AyuGram stories compose has full media attachment flow)

- [ ] [CRITICAL] Story reply compose emoji picker button has empty `onTap: () {}` — `media_viewer.dart:5239` ← (AyuGram opens emoji/reaction picker on tap)

- [ ] [CRITICAL] `_handleAreaChannelPost` has a TODO comment and does nothing — `media_viewer.dart:5517` ← (AyuGram navigates to the channel message via deep link)

- [ ] [CRITICAL] `_onSenderTap` just pops the navigator without navigating to the sender's peer info page — `media_viewer.dart:2501` ← `media_view_overlay_widget.cpp:7597` (`window->showPeerInfo(_from)`)

- [ ] [CRITICAL] `_showAllMedia` just pops the media viewer instead of navigating to the shared-media overview — `media_viewer.dart:2701` ← `media_view_overlay_widget.cpp:3358` (`showMediaOverview()` opens the SharedMedia info page)

- [ ] [CRITICAL] Story like button (`onLike`) only toggles local `_liked` state without calling any engine reaction API — `media_viewer.dart:6212` ← (AyuGram calls `stories->like()` / reaction API on the server)

- [ ] [CRITICAL] Story emoji reaction (`onReaction`) only sets `_liked = true` locally without calling any engine reaction API — `media_viewer.dart:6213` ← (AyuGram sends reaction via `stories->sendReaction()`)

- [ ] [CRITICAL] `_handleAreaReaction` only does `setState(() => _liked = true)` without calling any engine method — `media_viewer.dart:5504` ← (AyuGram sends reaction to server)

- [ ] [CRITICAL] Stealth mode activation never calls an engine method: `widget.onActivate?.call()` where the callback is always `null` at every call site — `media_viewer.dart:6490` ← (AyuGram calls `_stories->activateStealthMode()` on confirmation)

- [ ] [MAJOR] Default video volume is 0.8 but AyuGram uses 0.9 — `media_viewer.dart:328` ← `core_settings.h:123` (`kDefaultVolume = 0.9`)

- [ ] [MAJOR] Three animation controllers (`_controlsAnim`, `_bufferSpinCtrl`, `_saveToastAnim`) each call `setState(() {})` in their `addListener` callbacks, forcing full widget-tree rebuilds on every animation frame (60 fps) instead of scoping repaints with `AnimatedBuilder` or `AnimatedOpacity` — `media_viewer.dart:374`, `402`, `409`

# message_bubble — Audit Findings

- [ ] [CRITICAL] Poll voting never submitted to engine — `_onOptionTap` (line 7920–7943) only updates `_selectedIndices` / `_hasVoted` locally; no engine or chat_state method is called. `engine_service.dart` and `chat_state.dart` have zero poll-related methods. Multiple-choice polls have no "Vote" submit button at all — selected options can never be submitted. ← `api/api_polls.cpp:147` (`Polls::sendVotes()` → `MTPmessages_SendVote`)

- [ ] [CRITICAL] Inline `switch_inline` button is a stub — `message_bubble.dart:9261` has `case 'switch_inline': break;` with no body. Should prefill the compose bar with `@bot_name <query>` and switch to inline query mode. ← `history_view_message.cpp` (ReplyMarkupClickHandler handles SwitchInlineQuery)

- [ ] [CRITICAL] Inline `buy` button is a stub — `message_bubble.dart:9267` has `case 'buy': break;` with no body. Should open the invoice/payment flow. ← `history_view_invoice.cpp` (payment click handler)

- [ ] [CRITICAL] Inline `user_profile` button is a stub — `message_bubble.dart:9284` has `case 'user_profile': break;` with no body. Should open the referenced user's profile. ← `history_view_message.cpp`

- [ ] [CRITICAL] Inline `request_phone`, `request_location`, `request_poll`, `request_peer` buttons are all stubs — `message_bubble.dart:9286–9290` four `break` statements with no bodies. ← `history_view_message.cpp` (each has a distinct click handler in AyuGram)

- [ ] [CRITICAL] Game "PLAY GAME" button uses wrong mechanism — `_GameCardState._onPlay()` (`message_bubble.dart:8621–8642`) searches for a pre-set `btn.url` on game buttons, which is always empty. The correct flow is to call `MTPmessages_GetBotCallbackAnswer` with the `f_game` flag and open the URL returned in the callback response. When no URL is found the code silently stalls for 15 seconds then resets the spinner. ← `api/api_bot.cpp:82–87` (isGame → `f_game` flag, URL returned from callback `data.vurl()`)

- [ ] [CRITICAL] Location map is a fake placeholder — `_MapGridPainter.paint()` (`message_bubble.dart:4983–5018`) draws hardcoded grid lines and three diagonal "road" lines at fixed positions. No real map tile is fetched or rendered. ← `history_view_location.cpp:1` (uses `CloudImage` / static map tile via Telegram API)

- [ ] [CRITICAL] Contact card action buttons have no `onTap` — `_ContactIndicator._actionButton()` (`message_bubble.dart:5141–5153`) returns a plain `Text` widget inside an `Expanded`, with no `GestureDetector` or `InkWell`. "Send Message", "Add Contact", and "View Details" are purely cosmetic labels. ← `history_view_contact.cpp:57–77` (`SendMessageClickHandler` opens peer chat; `AddContactClickHandler` opens add-contact box)

- [ ] [MAJOR] SVG `S`/`s` smooth cubic Bezier is wrong — `message_bubble.dart:6445–6452`: the first control point must be the reflection of the previous control point relative to the current position, but the code passes `cx, cy` (the *new endpoint*) as the first control, producing `path.cubicTo(cx, cy, x2, y2, cx, cy)` where both the first control and the endpoint are identical. All custom emoji paths containing `S`/`s` commands render as degenerate curves instead of smooth splines. ← SVG 1.1 spec §8.3.6; AyuGram uses Qt's `QPainterPath` which implements this correctly

- [ ] [MAJOR] SVG `T`/`t` smooth quadratic Bezier is wrong — `message_bubble.dart:6461–6466`: should reflect the previous quadratic control point, but the code passes `cx, cy` (the endpoint) for both the control and endpoint arguments: `path.quadraticBezierTo(cx, cy, cx, cy)` — a degenerate curve equivalent to `lineTo(cx, cy)`. ← SVG 1.1 spec §8.3.7

- [ ] [MAJOR] SVG `A` arc command stubbed as `lineTo` — `message_bubble.dart:6467–6470`: all five arc parameters (rx, ry, x-axis-rotation, large-arc-flag, sweep-flag) are consumed and discarded, then `path.lineTo(cx, cy)` draws a straight line to the endpoint. Emoji paths using elliptical arcs are visually wrong. ← SVG 1.1 spec §8.3.8; `A` is listed in `_commands` at line 6346 so it does appear in real emoji path data

# my_profile_page — Profile/Edit Profile page audit

- [ ] [CRITICAL] Status in photo area is hardcoded to the string `'online'` regardless of actual user status; AyuGram uses `StatusValue(self)` which calls `Data::OnlineText(user, now)` with a repeating timer to show real last-seen/online/offline text — `my_profile_page.dart:660` ← `AyuGram/settings/sections/settings_information.cpp:281-299`

- [ ] [CRITICAL] Birthday footer "your contacts" link is an empty stub (`onTap: () {}`); in AyuGram both the contacts link and the manage link navigate to `edit_privacy_birthday` — `my_profile_page.dart:299` ← `AyuGram/settings/sections/settings_information.cpp:482-491`

- [ ] [CRITICAL] Birthday footer text is static and never queries the actual privacy API; AyuGram calls `session->api().userPrivacy().reload(key)` and then conditionally shows `lng_settings_birthday_contacts` (visible to contacts) vs `lng_settings_birthday_about` (not-visible text) based on the live privacy rule — `my_profile_page.dart:288-340` ← `AyuGram/settings/sections/settings_information.cpp:468-491`

- [ ] [CRITICAL] Personal channel clear/set operations do not update `_personalChannelName` state: after `engine.clearPersonalChannel()` or `engine.setPersonalChannel()` the row still displays the stale channel name because there is no `setState(()=>_personalChannelName=...)` and no callback wired back to the parent (unlike `_YourColorRow` which has `onColorChanged`) — `my_profile_page.dart:1019-1044` ← `AyuGram/settings/sections/settings_information.cpp:501-533`

- [ ] [MAJOR] Bio input accepts and stores newlines (`maxLines: null`, no stripping); AyuGram explicitly strips newlines in the `assign` lambda (`bio->setText(text.replace('\n', ' '))`) even though the field is `InputField::Mode::MultiLine` — `my_profile_page.dart:534` ← `AyuGram/settings/sections/settings_information.cpp:673-678`

# notification_popup — Notification Popup Widget Audit

- [ ] [CRITICAL] `_Avatar` widget declares `avatarPath` field (line 661) but never uses it in `build()` — the image is never rendered; every notification always shows colour-initial fallback regardless of whether a real peer photo is available — `notification_popup.dart:659-703` ← `AyuGramDesktop/window/notifications_manager_default.cpp:919-926` (`_history->peer->paintUserpicLeft` / `manager()->hiddenUserpicPlaceholder()`)

- [ ] [MAJOR] `_onReplyCancel` closes the reply field and starts a hide countdown (`notification_popup.dart:304-311`), but AyuGram's `replyCancel()` calls `unlinkHistoryInManager()`, which fully dismisses the notification immediately — `notification_popup.dart:304-311` ← `AyuGramDesktop/window/notifications_manager_default.cpp:791-793`

- [ ] [MAJOR] HideAll button position is inverted for bottom corners: Dart places it at `size.height - _notifyDeltaY - _hideAllHeight` (43 px from screen edge, *below* all popups), but AyuGram places it at `lastShift` which for bottom-corner direction puts it *above* all popups — furthest from the corner — `notification_popup.dart:429-461` ← `AyuGramDesktop/window/notifications_manager_default.cpp:313-318` (`_hideAll->changeShift(lastShift)` with `Direction::Up`)

- [ ] [MAJOR] `_recalcPositions()` unconditionally adds `_hideAllHeight + _notifyDeltaY` (43 px) to the starting shift for **all** corners, including top corners (`notification_popup.dart:328-329`). For top corners AyuGram places notifications at `notifyDeltaY=7` from the top edge; Dart places them at `50`, creating a 43 px empty gap — `notification_popup.dart:321-337` ← `AyuGramDesktop/window/notifications_manager_default.cpp:297-302` (`shift = st::notifyDeltaY`, no offset for HideAll)

- [ ] [MAJOR] HideAll button renders with a static style and no hover state (`notification_popup.dart:440-461`); AyuGram uses `st::lightButtonBgOver`/`st::lightButtonFgOver` to change background and text colour on mouse-over — `notification_popup.dart:440-461` ← `AyuGramDesktop/window/notifications_manager_default.cpp:1330-1342` (`HideAllButton::paintEvent`, `_mouseOver ? st::lightButtonBgOver : st::lightButtonBg`)

- [ ] [MAJOR] After reply send, Dart fast-hides only the replied popup (`_startFastHide`, `notification_popup.dart:301`); AyuGram calls `manager()->startAllHiding()` which starts a slow hide on **every** visible notification — `notification_popup.dart:296-302` ← `AyuGramDesktop/window/notifications_manager_default.cpp:1168-1176`

# notifications_settings_screen — Backend wiring completely absent; stubs; state not loaded

## Critical — Backend disconnected

- [ ] [CRITICAL] "Contact joined Telegram" toggle only saves to local JSON prefs, never calls `saveContactSignupSilent` server API — `notifications_settings_screen.dart:418-420` ← `AyuGram/settings/sections/settings_notifications.cpp:1298-1303`

- [ ] [CRITICAL] "Accept calls on this device" toggle only saves to local JSON prefs; never calls `authorizations.toggleCallsDisabledHere()` and never reads live server state from `authorizations.callsDisabledHereValue()` — `notifications_settings_screen.dart:466-468` ← `AyuGram/settings/sections/settings_notifications.cpp:1340-1354`

- [ ] [CRITICAL] Notification type global toggles (private chats / groups / channels) only set `appState.notifPrivateChats/Groups/Channels` (local JSON), never call `settings.defaultUpdate(type, MuteValue{unmute,forever})` (Telegram `account.updateNotifySettings` API) — `notifications_settings_screen.dart:342, 355, 368` ← `AyuGram/settings/sections/settings_notifications.cpp:227-233`

- [ ] [CRITICAL] Type sub-page `_exceptions` list starts empty and is never loaded from the backend; AyuGram's `ExceptionsController.prepare()` loads from `session().data().notifySettings().exceptions(type)` and subscribes to live `exceptionsUpdates` — `notifications_settings_screen.dart:1364` ← `AyuGram/settings/sections/settings_notifications_type.cpp:213-219`

- [ ] [CRITICAL] Type sub-page `_enabled`, `_soundEnabled`, `_volume`, `_selectedToneId` are hardcoded defaults (`true, true, 100, -1`), never loaded from `session.data.notifySettings().defaultSettings(type)` — so the sub-page always shows "on / sound on / 100%" regardless of real account state — `notifications_settings_screen.dart:1357-1361` ← `AyuGram/settings/sections/settings_notifications_type.cpp:392-397`

- [ ] [CRITICAL] Changes to `_enabled` and `_soundEnabled` in the type sub-page only call `setState()`, never call `settings.defaultUpdate(type, MuteValue)` to persist to the Telegram server — `notifications_settings_screen.dart:1420, 1443` ← `AyuGram/settings/sections/settings_notifications.cpp:227-233`

- [ ] [CRITICAL] Adding an exception via `_showPeerPicker` only appends to the local `_exceptions` list; never calls the Telegram mute API (`MuteMenu::FillMuteMenu`) to actually mute the peer on the server — `notifications_settings_screen.dart:1681-1688` ← `AyuGram/settings/sections/settings_notifications_type.cpp:174-177`

- [ ] [CRITICAL] Removing an exception only removes from the local list; never calls `session().data().notifySettings().resetToDefault(peer)` to remove the server-side peer exception — `notifications_settings_screen.dart:1509-1510` ← `AyuGram/settings/sections/settings_notifications_type.cpp:257-258`

- [ ] [CRITICAL] Exception mute toggle (context menu mute/unmute) only flips local `isMuted` field; never calls the mute API — `notifications_settings_screen.dart:1818-1831` ← `AyuGram/settings/sections/settings_notifications_type.cpp:292-321`

- [ ] [CRITICAL] Reactions sub-page `_reactionsEnabled`, `_reactionsFrom`, `_pollVotesEnabled`, `_pollVotesFrom` are hardcoded defaults, never loaded from `session.api().reactionsNotifySettings()` (which calls `rs.reload()` on open), and changes are never saved via `reactionsNotifySettings.setAllFrom(from)` — `notifications_settings_screen.dart:2621-2625` ← `AyuGram/settings/sections/settings_notifications.cpp:280-322`

- [ ] [CRITICAL] "view_profile" in exception context menu is a stub — comment reads `// Profile viewing would navigate to the chat/user profile` with no navigation code; AyuGram calls `window->showPeerInfo(peer)` — `notifications_settings_screen.dart:1816-1817` ← `AyuGram/settings/sections/settings_notifications_type.cpp:305-309`

- [ ] [CRITICAL] "View exceptions" button in the toggle confirmation dialog only pops the dialog (`Navigator.of(ctx).pop()`), never navigates to the type sub-page; AyuGram's equivalent opens the NotificationsType section via `showOther(NotificationsType::Id(type))` — `notifications_settings_screen.dart:2499-2502` ← `AyuGram/settings/sections/settings_notifications.cpp:263-269`

- [ ] [CRITICAL] `_allAccountsNotify` is uninitialized widget-local state (always `true` on open), never read from AppState or a persisted setting; the toggle resets every time the screen is opened — `notifications_settings_screen.dart:56, 173-174` ← `AyuGram/settings/sections/settings_notifications.cpp:943-970`

## Major — Wrong initial state / performance

- [ ] [MAJOR] `_privateExceptionCount`, `_groupExceptionCount`, `_channelExceptionCount` all start at 0 so the sub-row status text always reads "Click here to change" until the user opens and closes each sub-page; should be loaded from `session.data.notifySettings().exceptions(type).size()` on screen init — `notifications_settings_screen.dart:59-61` ← `AyuGram/settings/sections/settings_notifications.cpp:204-214`

- [ ] [MAJOR] `_MonitorPainter.shouldRepaint` unconditionally returns `true`, causing a full canvas repaint on every parent rebuild; should compare selectedCorner/hoverCorner/barOpacities/isDark/accent — `notifications_settings_screen.dart:1130` ← `AyuGram/settings/sections/settings_notifications.cpp:340-413`

- [ ] [MAJOR] Ringtones (custom tones list, selected tone ID) are purely in-memory local state with no backend synchronization; AyuGram loads ringtones from `session->api().ringtones()` (which fetches from Telegram servers via `account.getSavedRingtones`) — `notifications_settings_screen.dart:1734-1765` ← `AyuGram/settings/sections/settings_notifications.cpp:13` (api/api_ringtones.h included)

# payment_panel — Audit findings

- [ ] [CRITICAL] All section buttons (payment method, shipping address/method, name, email, phone) have empty `onTap: () {}` — tapping them does nothing in form mode. AyuGram routes each to a specific delegate method: `panelEditPaymentMethod()`, `panelEditShippingInformation()`, `panelChooseShippingOption()`, `panelEditName()`, `panelEditEmail()`, `panelEditPhone()`. The entire "edit" flow for every data field is dead. — `payment_panel.dart:768` ← `AyuGram/payments/ui/payments_form_summary.cpp:499-558`

- [ ] [CRITICAL] `_paymentMethod` is never populated from form data — always `null`, always displays "Not selected". `_fetchForm` reads `prices`, `suggested_tips`, `saved_info`, etc. but never reads the saved payment method title from the response. AyuGram reads `_method.savedMethods[_method.savedMethodIndex].title`. — `payment_panel.dart:117,722-723` ← `AyuGram/payments/ui/payments_form_summary.cpp:501-504`

- [ ] [CRITICAL] Currency decimal places hardcoded to 2 (`abs ~/ 100`, `abs % 100`). Wrong for JPY (exp=0: 1000 JPY should display ¥1000, not ¥10.00) and BHD (exp=3). AyuGram's `FillAmountAndCurrency` calls `LookupCurrencyRule` to get per-currency exponent, e.g. JPY has `exp=0`, BHD has `exp=3`. — `payment_panel.dart:295-296` ← `AyuGram/ui/text/format_values.cpp:228,262,187`

- [ ] [CRITICAL] `_computeTotal()` omits selected shipping option prices — sums only `_prices`. AyuGram's `computeTotalAmount()` adds the sum of the selected shipping option's own prices on top of invoice prices plus tips. A shipping cost is silently dropped from the displayed total and from the PAY button label. — `payment_panel.dart:644-650` ← `AyuGram/payments/ui/payments_form_summary.cpp:149-167`

- [ ] [CRITICAL] Receipt date rendered at the bottom of the panel after section buttons. AyuGram renders the receipt date as the first row in the prices section (before line items), styled as a full/bold row. The Dart pushes it to an afterthought position below sections, mismatching the TDesktop layout. — `payment_panel.dart:509-518` ← `AyuGram/payments/ui/payments_form_summary.cpp:321-328`

- [ ] [MAJOR] Tips amount row is a static text widget — not a clickable link. AyuGram makes the tips value a link whose click handler calls `panelChooseTips()` so the user can edit the tip amount. Dart has no equivalent interaction. — `payment_panel.dart:494-497` ← `AyuGram/payments/ui/payments_form_summary.cpp:362-365`

- [ ] [MAJOR] Terms URL dialog never opens `_termsUrl` in a browser — shows only a generic hardcoded string "By completing this payment, you agree to the Terms of Service of the payment provider." The actual URL fetched from the API at line 186 is stored but never surfaced to the user. — `payment_panel.dart:255-290,186` ← `AyuGram/payments/ui/payments_panel_data.h:58` (`termsUrl` field)

- [ ] [MAJOR] `_progressFade` AnimationController is initialised and animated on data load (line 211) but never drives any widget opacity in the build method — the loading overlay never fades out. The loading widget uses a hardcoded `Opacity(opacity: 0.3)` with no connection to `_progressFade`. — `payment_panel.dart:127,134-138,211,438-439` ← `AyuGram/payments/ui/payments_panel.cpp:110-150` (shownAnimation drives opacity)

# peer_short_info — Peer Short Info Box Audit

- [ ] [CRITICAL] `_photoCount` is permanently 1 — no engine call to load the user's photo list, so photo navigation (progress bars, swipe zones) is completely dead. `_photoCount` is set to `1` at init and never updated; the `if (_photoCount > 1)` guards at lines 467 and 522 never fire, so progress bars and left/right tap zones are never rendered for any user — `peer_short_info.dart:114` ← `prepare_short_info_box.cpp:533` (`UserPhotosReversedViewer`, `kOverviewLimit=48`, count set from `userSlice->size()` at line 305)

- [ ] [CRITICAL] `_navigatePhoto` changes `_currentPhotoIndex` but never loads a different photo — the cover always displays the original `widget.avatarPath` regardless of index; there is no engine call to fetch photo at index N. Navigation would only move the progress-bar painter state (if bars were visible) but never change the displayed image — `peer_short_info.dart:199` ← `prepare_short_info_box.cpp:427` (moveRequests updates `state->current.index` → `push(true)` → `ProcessCurrent` → `ProcessFullPhoto` emits new photo)

- [ ] [CRITICAL] Status text for DM users is hardcoded to `'last seen recently'` — this is placeholder data, not from the engine. AyuGram computes live status via `Data::OnlineText(user, now)` with a timer that re-fires on `OnlineChangeTimeout` — `peer_short_info.dart:405` ← `prepare_short_info_box.cpp:253` (`Data::OnlineText(user, now)` + base::Timer)

- [ ] [CRITICAL] Personal channel name displayed as plain text with no tap handler — AyuGram's `channelValue()` returns `tr::link(fields.channelName, fields.channelLink)`, a clickable link that navigates to the channel. The Dart row has only a copy-to-clipboard action; tapping the channel name does nothing — `peer_short_info.dart:596` ← `peer_short_info_box.cpp:881` (`tr::link(fields.channelName, fields.channelLink)`)

- [ ] [CRITICAL] Username displayed as plain unclickable text — AyuGram returns `tr::link(fields.username, fields.usernameLink)`, a tappable link that opens the profile URL. Dart shows `@username` as a `SelectableText` with copy-only; the `usernameLink` field from the engine is never used — `peer_short_info.dart:627` ← `peer_short_info_box.cpp:902` (`tr::link(fields.username, fields.usernameLink)`)

- [ ] [MAJOR] Bio/About text loses entity formatting — AyuGram stores and renders the about field as `TextWithEntities` (`Info::Profile::AboutWithEntities`), preserving inline hyperlinks and text formatting. `UserProfile.bio` is a plain `String` and rendered in a plain `SelectableText`; any links or bold/italic spans in user bios are silently stripped — `peer_short_info.dart:617` ← `prepare_short_info_box.cpp:236` (`AboutWithEntities(peer, peer->about())`) and `peer_short_info_box.cpp:806`

- [ ] [MAJOR] Notes field loses entity formatting — same issue as bio: `UserProfile.notes` is a plain `String`. AyuGram's `note` is `TextWithEntities` — `peer_short_info.dart:650` ← `peer_short_info_box.cpp:931` (`noteValue()` returning `TextWithEntities`)

- [ ] [MAJOR] `_isSelf` detected via hardcoded English string `'Saved Messages'` — will silently fail for users running a non-English locale, causing the "Send Message" action button to appear on the user's own saved messages chat — `peer_short_info.dart:244` ← `prepare_short_info_box.cpp:461` (`peer->isSelf()`)

- [ ] [MAJOR] `additionalStatus` label absent — AyuGram shows a secondary status line on the cover ("Set by you" when viewing a personal photo, "Public photo" for the fallback) via `_additionalStatus` label positioned above the primary status. No equivalent exists in Dart — `peer_short_info.dart` (absent) ← `peer_short_info_box.cpp:427` (`applyAdditionalStatus`, `_additionalStatus.create`)

- [ ] [MAJOR] Group/channel live member count never updates — member count is a static constructor parameter (`widget.memberCount`); AyuGram subscribes to `PeerUpdate::Flag::Members` and recomputes `tr::lng_chat_status_members` reactively. If member count changes during the box's lifetime, Dart shows the stale value — `peer_short_info.dart:407` ← `prepare_short_info_box.cpp:265` (`peerFlagsValue(peer, UpdateFlag::Members)`)

- [ ] [MAJOR] `_onScroll` calls `setState` on every scroll pixel, rebuilding the entire widget tree. AyuGram calls `_cover.setScrollTop()` which calls `_widget->update()` on only the cover widget. At minimum, parallax and opacity math should be separated from full rebuilds using an `AnimatedBuilder` or custom `RenderObject` — `peer_short_info.dart:163` ← `peer_short_info_box.cpp:687` (`_cover.setScrollTop(_scroll->scrollTop())`)

# photo_crop_editor — Audit Findings

- [ ] [CRITICAL] `_done()` passes the original `widget.imageFile` unchanged to `onDone` — the crop rect, rotation, and flip state are tracked visually but never applied to produce a modified output image. The `onDone` parameter is named `croppedFile` but receives the unmodified source. AyuGram calls `ImageModified(fileImage->original(), mods)` before firing the done callback. — `photo_crop_editor.dart:352-354` ← `AyuGram/editor/photo_editor_layer_widget.cpp:113-118`

- [ ] [CRITICAL] `_ImageCropAreaState._cropRect`, `_rotationDegrees`, and `_flipped` are private with no accessor; `_PhotoCropEditorState._done()` has no path to read them, so the save output is architecturally impossible to fix without refactoring. No `saveCropRect()`-equivalent on the Dart crop widget. — `photo_crop_editor.dart:609,348` ← `AyuGram/editor/editor_crop.cpp:586-591`

- [ ] [CRITICAL] Paint mode is a complete stub: `_paintUndo()` and `_paintRedo()` contain an explicit comment "Will be connected when paint strokes are implemented." and do nothing. No brush tools (Pen/Arrow/Marker/Blur/Eraser), no ColorPicker, no brush size control, no stickers panel, no text tool — only the mode toggle exists. — `photo_crop_editor.dart:327-332` ← `AyuGram/editor/photo_editor.cpp:351-408`

- [ ] [CRITICAL] `_PaintTopBar` always renders undo and redo with `_IconState.inactive` and `onPressed: () {}` — empty no-op callbacks regardless of paint history state. AyuGram dynamically enables/disables them via `UndoController.canPerformChanges()` and sets `WA_TransparentForMouseEvents` when no history is available. — `photo_crop_editor.dart:1399-1410` ← `AyuGram/editor/photo_editor_controls.cpp:427-441`

- [ ] [CRITICAL] Missing corners level button for `PhotoCropShape.roundedRect` — AyuGram shows a `cornersButton` with a 4-level popup menu (Large/Medium/Small/None) when `cropType == CropType::RoundedRect`. Dart has no such button and hardcodes `_kForumRadiusMultiplier = 0.3` (Large only), making corner radius permanently fixed. — `photo_crop_editor.dart:49` ← `AyuGram/editor/photo_editor_controls.cpp:280-284,526-587`

- [ ] [MAJOR] "Done" button in paint mode calls `_done()` which saves and pops the navigator — but AyuGram's paint-mode Done saves the strokes and returns to transform mode; only transform-mode Done exits the editor. This causes premature dismissal of the editor when the user confirms paint work. — `photo_crop_editor.dart:1159-1165` ← `AyuGram/editor/photo_editor.cpp:317-332`

- [ ] [MAJOR] `_CropAspect` enum is missing the `3:4` portrait ratio. AyuGram offers: Original, Square, 3:2, 16:9, **3:4**, 9:16, Free. Dart has: original, square, ratio3x2, ratio16x9, ratio9x16, free — the `3:4` (0.75) entry is absent. — `photo_crop_editor.dart:76-96` ← `AyuGram/editor/photo_editor_controls.cpp:516`

- [ ] [MAJOR] Paint mode bottom bar is missing the stickers button and text tool button. AyuGram's paint-mode `_paintBottomButtons` contains: cancel, paint-mode-active, stickersButton, textButton, done. Dart only has: cancel, brush icon (active), done — photo annotation with stickers and text is entirely absent. — `photo_crop_editor.dart:1149-1166` ← `AyuGram/editor/photo_editor_controls.cpp:308-320`

## popup_menu — Telegram popup/context menu widget

- [ ] [CRITICAL] No submenu support — `TelegramMenuItem` has no submenu field; no submenu display, hover-to-open, or Left/Right arrow navigation; entire submenu system is absent — `popup_menu.dart:48` ← `lib_ui/ui/widgets/popup_menu.cpp:103`

- [ ] [MAJOR] Corner radius is 8px but AyuGram uses 6px — `popup_menu.dart:8` ← `lib_ui/ui/widgets/widgets.style:1008`

- [ ] [MAJOR] Animation height starts at 30% (`0.3 + 0.7 * curve`) but AyuGram `startHeight: 0.45` means 45%; menu appears to expand from a smaller initial size than spec — `popup_menu.dart:250` ← `lib_ui/ui/widgets/widgets.style:947`

- [ ] [MAJOR] Scroll padding hardcoded to 8px for all menus; when items have icons AyuGram switches to `popupMenuWithIcons` which sets `scrollPadding: margins(0px, 5px, 0px, 5px)` — `popup_menu.dart:14` ← `lib_ui/ui/widgets/widgets.style:1716`

- [ ] [MAJOR] Menu content is a plain `Column` with no scroll area; tall menus exceeding screen height will overflow/clip instead of scrolling; AyuGram wraps menu in a `ScrollArea` — `popup_menu.dart:475` ← `lib_ui/ui/widgets/popup_menu.cpp:207`

- [ ] [MAJOR] No keyboard shortcut text rendered in menu items; AyuGram `Action::paint()` draws shortcut string at right edge; `TelegramMenuItem` has no shortcut field at all — `popup_menu.dart:515` ← `lib_ui/ui/widgets/menu/menu_action.cpp:142`

- [ ] [MAJOR] Disabled item uses `maxLines: 2` (text can wrap to two lines) while enabled items use `maxLines: 1`; AyuGram calls `drawLeftElided` uniformly for all states — `popup_menu.dart:745` ← `lib_ui/ui/widgets/menu/menu_action.cpp:108`

# privacy_settings_screen — Audit Findings

## CRITICAL

- [ ] [CRITICAL] File extensions "Save" button closes dialog without persisting data — `privacy_settings_screen.dart:1129-1131` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_privacy_security.cpp:385-399`
  - Dart: `onPressed: () { Navigator.of(ctx).pop(); }` — no engine call whatsoever
  - AyuGram reads the extensions text, splits, creates a `flat_set<QString>`, calls `settings->setNoWarningExtensions()`, then saves to disk via `Account::saveSettings()`
  - The entire "No-Warning Extensions" feature is a UI shell with zero backend effect

- [ ] [CRITICAL] Login Email row has empty `onTap: () {}` stub — `privacy_settings_screen.dart:691` ← `AyuGramDesktop/Telegram/SourceFiles/settings/cloud_password/settings_cloud_password_login_email.cpp:50-119`
  - Row is visible when `_loginEmailPattern.isNotEmpty` (line 683), but tap does nothing
  - AyuGram has a full `LoginEmail` step that opens an email input field, calls `Api::RequestLoginEmailCode`, then navigates to `LoginEmailConfirm` for code verification
  - Tapping the displayed email pattern in Dart: no navigation, no action

## MAJOR

- [ ] [MAJOR] Blocked users list loaded all-at-once with no pagination — `privacy_settings_screen.dart:6353-6362` ← `AyuGramDesktop/Telegram/SourceFiles/settings/settings_privacy_controllers.cpp:369-408`
  - Dart: `await engine.getBlockedUsers(accountId)` fetches the full list in a single call; no offset, no cursor
  - AyuGram: `BlockedBoxController::loadMoreRows()` uses `_offset` and `_allLoaded` fields, passes offset to `Api::BlockedPeers`, increments offset on each `applySlice()` call — properly handles >200 blocked users
  - With large block lists this triggers full list decode in UI thread and unbounded memory growth

# Audit Chunk 7 — main.dart

Source: `/home/nako/Documents/uniclient/dart/lib/main.dart`
Ground truth: `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/`

---

## passcode — lockout delay schedule wrong

- [ ] [CRITICAL] Passcode lockout uses `elapsed >= badTries * 5` (seconds), which gives 15s/20s/25s/30s/35s for tries 3–7. AyuGram uses a per-step table: 3→5s, 4→10s, 5→15s, 6→20s, 7→25s, else→30s. Every threshold is wrong — at 3 bad tries the Dart lock waits 15s but AyuGram only waits 5s. — `main.dart:2242` (app_state.dart) ← `AyuGram/SourceFiles/settings.h:116`

## passcode — system unlock button does nothing

- [ ] [CRITICAL] `_triggerSystemUnlock()` updates only a cooldown timestamp and returns — it never calls any biometric/system-auth API. The button is rendered and shown to users but is a dead stub. AyuGram calls `SuggestSystemUnlock()` which invokes the platform auth dialog and handles `SystemUnlockResult::Success/FloodError`. — `main.dart:2294` ← `AyuGram/SourceFiles/window/window_lock_widgets.cpp:201`

## passcode — no auto-trigger of system unlock on window focus

- [ ] [MAJOR] AyuGram automatically suggests system unlock every time the window regains focus (`windowActiveValue() | rpl::skip(1) | rpl::filter([=](bool active) { return active && !_systemUnlockSuggested; })`). The Dart `didChangeAppLifecycleState` handler only re-focuses the text field on resume — it never calls `_triggerSystemUnlock`. Even if the stub were fixed, the auto-prompt on focus would still be missing. — `main.dart:2220` ← `AyuGram/SourceFiles/window/window_lock_widgets.cpp:163`

## passcode — submit button gap wrong (70px vs 40px spec)

- [ ] [MAJOR] Error text and submit button are positioned starting at `inputY + 70`. AyuGram spec (`passcodeSubmitSkip: 40px`) places the submit button at `passcode.y() + passcode.height() + 40`. The Dart layout adds 70px below the input before the error zone begins, placing the submit button ~30px lower than spec. — `main.dart:2403` ← `AyuGram/SourceFiles/boxes/boxes.style:298` and `window_lock_widgets.cpp:302`

## passcode — systemUnlock type discrimination missing Windows Hello icon

- [ ] [MAJOR] On the system unlock button, Dart shows `Icons.fingerprint` for biometrics and `Icons.lock_open_outlined` for everything else. AyuGram uses three distinct icons: `passcodeSystemTouchID` (finger), `passcodeSystemAppleWatch` (watch), `passcodeSystemSystemPwd` (permissions) and on Windows always uses the WinHello icon unconditionally. The `UnlockType.companion` (Apple Watch) case maps to the generic `lock_open_outlined` instead of a watch icon. — `main.dart:2441` ← `AyuGram/SourceFiles/window/window_lock_widgets.cpp:176`

## passcode — FloodError not shown when canTry returns false

- [ ] [MAJOR] When `passcodeCanTry()` is false, AyuGram shows `tr::lng_flood_error` and calls `showError()` on the input. Dart shows `'Please try again later'` (hardcoded English string, not a localised key) and does not select the existing text or give the input field's shake-error feedback. — `main.dart:2268` ← `AyuGram/SourceFiles/window/window_lock_widgets.cpp:264`

## theme revert — notification inline reply not wired to engine

- [ ] [CRITICAL] `onReplySend` callback in the `NotificationPopupOverlay` is an explicit `// TODO: wire to engine sendMessage` stub — the callback body is empty. Users who expand a notification and type a reply and press Send will get no message sent. — `main.dart:1954` ← (no AyuGram counterpart; this is a backend-wiring gap)

## theme revert — overlay width wrong (320px vs 364px spec)

- [ ] [MAJOR] `_ThemeRevertOverlay` uses `_boxWidth = 320.0`. AyuGram sets `themeWarningWidth: boxWideWidth` where `boxWideWidth: 364px`. The overlay is 44px narrower than spec. — `main.dart:1990` ← `AyuGram/SourceFiles/boxes/boxes.style:347` and `lib_ui/ui/layers/layers.style:118`

## theme revert — overlay is positioned at bottom, not centered

- [ ] [MAJOR] The Dart overlay is anchored at `bottom: 20` (a strip at the screen bottom). AyuGram's `WarningWidget` renders centered in the window (`(height() - st::themeWarningHeight) / 2`). The overlay appears in the wrong location. — `main.dart:2054` ← `AyuGram/SourceFiles/window/themes/window_theme_warning.cpp:78`

## theme revert — Enter key keeps theme; Escape reverts (correct), but no paint-event title/body layout

- [ ] [MAJOR] AyuGram's warning box draws a title line and a countdown text at `themeWarningTextTop: 60px` from the inner rect top using the custom style. The Dart overlay uses a Column with SizedBox(height:6) spacer (no fixed vertical position for the countdown text), so the `themeWarningTextTop` invariant is not respected. Not visually identical to spec. — `main.dart:2105` ← `AyuGram/SourceFiles/window/themes/window_theme_warning.cpp:69`

# reactions_detail — Audit Findings

## reactions_detail — Reactions detail panel (who reacted / who read)

- [ ] [CRITICAL] Custom emoji reactions fully broken: `ReactorInfo` has no `documentId` field (`engine_service.dart:2253` maps only `emoji`, `peerId`, `peerName`, `date`), so custom emoji reactors arrive with `emoji = ''`. All custom emoji tabs then get `selectedTab = ''` simultaneously (all appear selected at once via `isSelected: selectedTab == r.emoji`), tapping any custom emoji tab calls `onTabSelected('')` which fires `getMessageReactorsList` with empty filter (= all reactions), and `_filteredReactors` filters to `r.emoji == ''` showing all custom emoji reactors mixed together instead of the one tapped. — `reactions_detail.dart:509,236` ← `history_view_reactions_tabs.cpp:37-58` (custom emoji rendered via `CustomEmojiFactory` keyed on `DocumentId`, not emoji string)

- [ ] [CRITICAL] No real user profile photos: `_ReactorAvatar` renders a colored circle with text initials only (`reactions_detail.dart:820-852`). Neither `ReactorInfo` nor `ReadParticipantInfo` carry photo data, and the engine has no `GetUserPhoto` method, so actual profile photos are never shown for any reactor or read-participant row. AyuGram's `PeerListRow` loads and caches real peer avatars. — `reactions_detail.dart:820` ← `history_view_reactions_list.cpp:152-167` (`Row` extends `PeerListRow` with live userpic loading)

- [ ] [MAJOR] "All reactions" tab uses wrong icon: Dart uses `Icons.favorite` (`reactions_detail.dart:501`) instead of the `reactionsTabAll` icon (`menu/read_reactions`). AyuGram uses `st::reactionsTabAll` / `st::reactionsTabAllSelected` for the empty-reaction-id (all) tab. — `reactions_detail.dart:501` ← `chat.style:862-863` (`reactionsTabAll: icon {{ "menu/read_reactions", windowFg }}`)

- [ ] [MAJOR] Individual reaction tabs not sorted by count descending: `_ReactionTabBar` iterates `reactions` in their original order (`reactions_detail.dart:507`). AyuGram's `CreateTabs` explicitly sorts individual reactions by count descending (`sorted` vector, `ranges::sort`) before appending tabs. High-count reactions should appear first after the "all" tab. — `reactions_detail.dart:507` ← `history_view_reactions_tabs.cpp:152-159` (`ranges::sort(sorted, std::greater<>(), &Entry::first)`)

- [ ] [MAJOR] `ReadPrivacyState.myHidden` "Show" button is non-functional: it opens an `AlertDialog` with only an "OK" dismiss button (`reactions_detail.dart:914-931`) and does not call the engine to disable the "hide read time" privacy setting. AyuGram's equivalent calls `api->globalPrivacy().updateHideReadTime({})` to actually reveal read times, or opens the Premium upsell. The user gets no actionable path to fix their privacy setting. — `reactions_detail.dart:914` ← `history_view_context_menu.cpp:2025-2036` (`showOrPremium` → `updateHideReadTime({})`)

# send_files_box — Audit Findings

## send_files_box — SendFilesResult fields ignored at call site

- [ ] [CRITICAL] `chat_view.dart` ignores almost all `SendFilesResult` fields: `silent`, `scheduledDate`, `spoilers`, `sendAsDocuments`, `groupFiles`, `remember`, `sendLargePhotos`, `captionAbove`, `perFileCaptions`, `ctrlShiftEnter`, `sendAsSticker` — only `caption` is forwarded to `uploadFile()`. The entire send-options UI is cosmetic and has no effect on the actual send. — `dart/lib/ui/chat_view.dart:3827-3830` ← `boxes/send_files_box.cpp:2387-2450`

## send_files_box — Photo editor does not feed back edited image

- [ ] [CRITICAL] `_openEditor()` calls `PhotoCropEditor.open()` without an `onDone` callback, so the edited/cropped image is never written back into `_files`. The edit opens, closes, and the send box still contains the original unmodified image. — `dart/lib/ui/send_files_box.dart:1806-1814` ← `boxes/send_files_box.cpp:1361-1379` (editor result is applied via `refreshAllAfterChanges`)

## send_files_box — "Send When Online" sends immediately, not when-online

- [ ] [CRITICAL] The "Send When Online" menu item (value `'when_online'`) calls `_send()` with no arguments — it sends immediately like a normal send. It must pass a special scheduling token or `sendWhenOnline` flag to the engine. AyuGram routes this through `SendMenu::DefaultCallback` with `ActionType::WhenOnline`. — `dart/lib/ui/send_files_box.dart:1009-1010` ← `boxes/send_files_box.cpp:764-773`

## send_files_box — File context menu missing Rename, Replace, and Edit/Clear Cover

- [ ] [CRITICAL] Right-clicking a file in the album or single media preview only shows "Spoiler effect". AyuGram's context menu includes: "Replace attachment", "Open in photo editor" (for photos), "Rename file" (for non-media), "Edit caption" (for non-media), "Edit cover" (for videos in channel/self-chat), "Clear cover". None of these exist in the Dart implementation. — `dart/lib/ui/send_files_box.dart:1599-1612` ← `boxes/send_files_box.cpp:1524-1638`

## send_files_box — Emoji panel is a static hardcoded 30-emoji grid

- [ ] [MAJOR] `_EmojiQuickPanel` shows a fixed static list of 30 emojis hardcoded in the source. AyuGram uses a full `TabbedSelector` panel showing the user's actual recent emojis from the session. Emojis shown never change and don't reflect user history. — `dart/lib/ui/send_files_box.dart:2875-2882` ← `boxes/send_files_box.cpp:2003-2058`

## send_files_box — Caption field does not support text entities / markup

- [ ] [MAJOR] The caption field is a plain `TextField` with no entity/markup support. AyuGram's caption field is an `InputField` with `TextWithTags` supporting bold, italic, code, strikethrough, mentions, etc. via `InitMessageFieldHandlers`. Formatted captions cannot be created. — `dart/lib/ui/send_files_box.dart:1278-1294` ← `boxes/send_files_box.cpp:1837-1920`

## send_files_box — "Remember" checkbox has no persistence — setting is not saved

- [ ] [MAJOR] The "Remember" checkbox sets `_wayRemember = true` in the result, but no code in the codebase reads `result.remember` to persist the send-way setting. AyuGram's `saveSendWaySettings()` writes to `Core::App().settings()` and calls `saveSettingsDelayed()`. — `dart/lib/ui/send_files_box.dart:961` ← `boxes/send_files_box.cpp:2328-2346`

## send_files_box — Slowmode: group-files checkbox not hidden when OnlyOne constraint active

- [ ] [MAJOR] When `isSlowMode` is true, the "Group files" checkbox is hidden correctly (`if (_hasGroupOption && !widget.isSlowMode)`), but multi-file adds are not validated against the slowmode constraint. AyuGram's `addFile()` pops the file if `canBeSentInSlowmode()` fails when `SendFilesAllow::OnlyOne` is set, and shows a toast. The Dart version silently accepts extra files in slowmode chats. — `dart/lib/ui/send_files_box.dart:1337` ← `boxes/send_files_box.cpp:2146-2167`

## send_files_box — Caption autocomplete (mentions, commands) not set up

- [ ] [MAJOR] AyuGram calls `setupCaptionAutocomplete()` which wires `FieldAutocomplete` for @mentions, #hashtags etc. into the caption field. The Dart `TextField` has no autocomplete at all. — `dart/lib/ui/send_files_box.dart:1278-1294` ← `boxes/send_files_box.cpp:1922-1970`

## send_files_box — Title text does not distinguish image-only selections

- [ ] [MAJOR] Title always shows "Send file" / "Send N files". AyuGram shows "Send image", "Send video", "Send N images selected", "Send N files selected" based on file types via `refreshTitleText()`. — `dart/lib/ui/send_files_box.dart:1121-1126` ← `boxes/send_files_box.cpp:2169-2191`

## send_files_box — Drag drop zones: dropped files in photo zone don't switch to compress mode

- [ ] [MAJOR] When files are dropped in the photo zone (`wasPhotoZone == true`), the code sets `_sendAsDocuments = false`. But this is backwards: the photo zone should switch to *compressed* (not-as-documents) mode. The document zone (top) should force `_sendAsDocuments = true`. The logic at line 1094-1097 has top (zone 1) as document and bottom (zone 2) as photo, but the drop handler conditionally flips `_sendAsDocuments` based on `wasPhotoZone` in a way that is inverted: photo zone sets `sendAsDocuments = false` (correct), but document zone also shouldn't automatically set `sendAsDocuments = true` unless there are media files — the current code does this unconditionally. AyuGram tracks photo vs. file zone separately via `droppedCallback(compress)`. — `dart/lib/ui/send_files_box.dart:1085-1098` ← `boxes/send_files_box.cpp:869-876`

# settings_screen — Audit Findings

## settings_screen — Main Settings Screen

- [ ] [CRITICAL] `_showAvatarMenu` discards result of `showMenu<String>()` — no `.then()` handler, no engine calls for photo upload, emoji avatar, or photo removal; tapping any menu item does nothing — `settings_screen.dart:685` ← `settings_main.cpp:210-225`

- [ ] [CRITICAL] QR code dialog shows `Icons.qr_code_2` Material icon placeholder instead of a real generated QR code; AyuGram calls `Ui::DefaultShowFillPeerQrBoxCallback(show, _user)` which renders the actual QR image — `settings_screen.dart:928` ← `settings_main.cpp:248-249`

- [ ] [CRITICAL] Language row trailing text hardcoded as `'English'`; AyuGram uses `Lang::GetInstance().nativeName()` as a live reactive value that updates when language changes — `settings_screen.dart:307` ← `settings_main.cpp:486-490`

- [ ] [CRITICAL] Stars balance hardcoded as `'0'`; AyuGram uses `session->credits().balanceValue()` piped through `FormatCreditsAmountToShort()` — `settings_screen.dart:345` ← `settings_main.cpp:547-554`

- [ ] [CRITICAL] TON Currency balance hardcoded as `'0'`; AyuGram uses `session->credits().tonBalanceValue()` — `settings_screen.dart:360` ← `settings_main.cpp:568-571`

- [ ] [CRITICAL] TON Currency row always visible; AyuGram shows it only when `tonBalanceValue` is non-empty (`.shown = session->credits().tonBalanceValue() | rpl::map([](CreditsAmount c) { return !c.empty(); })`) — `settings_screen.dart:355-369` ← `settings_main.cpp:576-578`

- [ ] [CRITICAL] Profile cover shows `account?.phone` at the `settingsPhoneTop` position; AyuGram's Cover replaces the phone field with `IDString(_user)` (numeric user ID) at that same position — `settings_screen.dart:629` ← `settings_main.cpp:285-290`

- [ ] [CRITICAL] Emoji status panel shows hardcoded list of 24 text emoji characters in a grid; AyuGram uses `Info::Profile::EmojiStatusPanel` which loads animated custom emoji sticker packs from Telegram's servers — `settings_screen.dart:796-800` ← `settings_main.cpp:126-127,227-231`

- [ ] [MAJOR] Avatar size 88×88px; AyuGram uses `st::infoProfileCover.photo.size` which resolves to `infoProfilePhotoInnerSize = 72px` (22% too large) — `settings_screen.dart:543-544` ← `info.style:527-530`

- [ ] [MAJOR] Profile header height `SizedBox(height: 112)`; AyuGram computes `st::settingsPhotoTop(8) + photo.size.height()(72) + st::settingsPhotoBottom(16) = 96px` (~17% taller than spec) — `settings_screen.dart:529` ← `settings_main.cpp:143-147`

- [ ] [MAJOR] Gap between avatar and text column is 2px (`SizedBox(width: 2)`) based on wrong 88px avatar assumption; with correct 72px avatar, gap = `settingsNameLeft(112) - settingsPhotoLeft(22) - 72 = 18px` — `settings_screen.dart:587` ← `settings_main.cpp:316-318`

- [ ] [MAJOR] Entire premium section (Premium/Stars/TON/Business/Gift) always rendered; AyuGram skips it entirely when `!session->premiumPossible()` — `settings_screen.dart:334` ← `settings_main.cpp:528-529`

- [ ] [MAJOR] "Send a Gift" row always shown; AyuGram conditions on `session->premiumCanBuy()` — `settings_screen.dart:377-383` ← `settings_main.cpp:589-597`

- [ ] [MAJOR] Folders row always shown; AyuGram conditionally shows based on `chatsFilters().has() || dialogsFiltersEnabled()`, preloads filter suggestions when shown — `settings_screen.dart:247-257` ← `settings_main.cpp:428-444`

- [ ] [MAJOR] Interface scale slider range hardcoded `_kMin=100, _kMax=300`; AyuGram uses `style::kScaleMin=50` to `style::MaxScaleForRatio(devicePixelRatio)`, making the range device-DPI-aware — `settings_screen.dart:1135-1137` ← `settings_main.cpp:1064-1077, style_core_scale.h:20`

- [ ] [MAJOR] Scale preview while dragging is a fake in-page mockup with hardcoded colored circles and gray bars; AyuGram calls `SetupScalePreview` which renders a floating window showing the actual UI at the selected scale — `settings_screen.dart:1275-1350` ← `settings_main.cpp:1157-1178`

# shell — Audit Findings

- [ ] [CRITICAL] Group call `onHangup` is an empty no-op: pressing the hang-up button in the minimised group-call bar does nothing — no engine call, no state change, call never ends — `shell.dart:346` ← `window_session_controller.cpp` (groups calls must call leave/discard; engine_service.dart has no `leaveGroupCall` method at all)

- [ ] [CRITICAL] Group call `onToggleMute` is an empty no-op: the mute-toggle button in the minimised group-call bar does nothing — `shell.dart:347` ← `call_screen.dart:292` dispatches real mute action; engine_service.dart has no `muteGroupCall` method, so the wiring cannot be completed until the engine method is added

- [ ] [MAJOR] Reconnect countdown is hardcoded to 30 s regardless of what the server says: `_reconnectInterval = 30` is a made-up constant — `shell.dart:939` ← `window_connecting_widget.cpp:325` derives `wait = ((-state) / 1000) + 1` from the actual MTP `dcstate()` value; the Dart ignores the engine's `waitTillRetry` and always counts down from 30 s

- [ ] [MAJOR] Connecting pill text shown without hover for `disconnected` and `unstable` states: `showText = _isHovered || _isWaiting || state == ConnState.disconnected || state == ConnState.unstable` always expands the pill to show "Connecting…" text for those states — `shell.dart:1060-1063` ← `window_connecting_widget.cpp:451-455` only emits non-empty text for Connecting when `underCursor` (hover); for the Waiting state text is always shown, but there is no AyuGram equivalent of an always-text `unstable` state

# shortcuts_settings_screen — Audit findings

- [ ] [CRITICAL] `RecordRound` command is completely absent from both `keyboard_shortcuts.dart` and the settings screen — AyuGram defines `Command::RecordRound` and lists it in the settings as a customizable shortcut between RecordVoice and the admin log separator — `shortcuts_settings_screen.dart:85` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_shortcuts.cpp:114` + `AyuGramDesktop/Telegram/SourceFiles/core/shortcuts.h:73`

- [ ] [MAJOR] `showArchive` and `showContacts` are grouped under "Chat Nav" (group 3) instead of the Folders group — AyuGram places `ShowArchive` and `ShowContacts` after `FolderPrevious` in the folders block, not in the chat navigation block — `shortcuts_settings_screen.dart:33-34` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_shortcuts.cpp:99-101`

# skeleton_animation — Visual & integration gaps vs AyuGram

## Critical Issues

- [ ] **[CRITICAL]** Glare shimmer effect is visually opposite: AyuGram gradient modulates shape opacity directly (center darker), but Dart overlay-blends glareColor over baseColor (center brighter) — `skeleton_animation.dart:59-122` ← `AyuGram/ui/effects/skeleton_animation.cpp:87-116`. Fix: Change gradient to use direct opacity modulation instead of overlay blend, or use `Color.lerp()` to match AyuGram's darkening effect.

- [ ] **[CRITICAL]** Gradient sweep width differs: AyuGram uses full textWidth (100% of placeholder width), Dart uses fixed 40% (`size.width * 0.4`) — `skeleton_animation.dart:104` ← `AyuGram/ui/effects/skeleton_animation.cpp:99`. Fix: Change to `final glareWidth = size.width;` or match actual content width.

- [ ] **[CRITICAL]** SkeletonTextPlaceholder and SkeletonMultiLinePlaceholder are standalone widgets, not integrated with FlatLabel like AyuGram's SkeletonAnimation class — `skeleton_animation.dart:20-208` ← `AyuGram/ui/effects/skeleton_animation.h:17-35, skeleton_animation.cpp:33`. These widgets exist but are never instantiated in the codebase (`grep -r SkeletonTextPlaceholder dart/ --include="*.dart"` returns no usage). Fix: Either integrate with actual FlatLabel/Text widgets, or remove if not needed.

- [ ] **[CRITICAL]** SkeletonMultiLinePlaceholder generates random line widths instead of querying actual text layout — `skeleton_animation.dart:163-167` ← `AyuGram/ui/effects/skeleton_animation.cpp:67 (countLineWidths())`. Dart's random approach produces fake placeholders that don't match real text dimensions. Fix: Pass actual line widths from parent widget, or remove randomization.

## Major Issues

- [ ] **[MAJOR]** No backend integration: skeleton widgets are purely decorative. They don't fetch or display real data, no engine calls, no state updates from server. Confirm if these are meant as standalone aesthetic elements or if they should bind to actual FlatLabel/chat widgets loading data.

- [ ] **[MAJOR]** Transparency math differs: Dart applies `glareColor.withValues(alpha: 0)` at gradient edges, which becomes fully transparent when drawn, then blends over baseColor (srcOver blend produces higher final alpha in center). AyuGram applies direct opacity to entire gradient (center is inherently less opaque). Fix: Match AyuGram by using a gradient that directly sets opacity (e.g., gradient with opacities [0.5, 0.2, 0.5] instead of [transparent, glareColor, transparent]).

---

## Checklist

- [ ] Read `research/telegram_desktop_ui.md` § skeleton animation (if present) before fixing
- [ ] Test both desktop (1024x768) and mobile (400x720) sizes to verify gradient sweep is visible
- [ ] Compare visual output of Dart shimmer vs AyuGram's darker-center effect
- [ ] If standalone widgets are intentional, document in `research/` why they diverge from AyuGram
- [ ] If FlatLabel integration is needed, implement SkeletonAnimation class wrapping FlatLabel
- [ ] Remove unused widgets if audit determines they're not part of the final UI

# spoiler_animation — Particle generation, caching, and threading gaps

- [ ] [CRITICAL] `_renderSpriteSheet` runs all 60-frame × 9000-particle draw operations synchronously on the main Dart isolate — the `async` keyword yields only at `await picture.toImage()`, so the entire particle rendering loop (~540k draw calls) blocks the UI thread and causes severe jank when spoilers first appear — `spoiler_animation.dart:132-253` ← `spoiler_mess.cpp:260` (`crl::async([=, &spoiler] { ... GenerateSpoilerMess ... })` runs the whole generation on a background thread)

- [ ] [MAJOR] No disk caching of generated sprite sheets — every app launch regenerates the full particle sheet from scratch — `spoiler_animation.dart:114-130` (no serialize/deserialize path) ← `spoiler_mess.cpp:196-226` (`ReadDefaultMask`/`WriteDefaultMask` persist the sheet to `emojiCacheFolder()/spoiler/{text,image}` and reload on subsequent launches via `SpoilerMessCached::FromSerialized`)

- [ ] [MAJOR] Particle birth frames use `rng.nextInt(_kFrameCount)` (uniform random), but C++ distributes them evenly across the animation timeline: `start = index * framesCount * frameDuration / particlesCount` — with 9000 particles over 1980ms each particle starts ~0.22ms apart, guaranteeing uniform density at every frame; Dart's random assignment can produce frame-to-frame density variance — `spoiler_animation.dart:163` ← `spoiler_mess.cpp:154-157`

- [ ] [MAJOR] Particle velocity direction uses uniform angular distribution (`angle = rng.nextDouble() * 2π`, then `cos`/`sin`) — C++ uses `x = RandomIndex(2*max+1) / max` (x uniform in [-1,1]) and `y = sqrt(1-x²) * sign`, which biases particle motion toward vertical directions and produces a visually distinct motion pattern — `spoiler_animation.dart:155-161` ← `spoiler_mess.cpp:124-145`

- [ ] [MAJOR] Text spoiler overlay falls back to `BlendMode.plus` (additive brightening) when `tintColor` is null, but C++ `FillSpoilerRect` uses default `CompositionMode_SourceOver` alpha compositing — additive blending progressively over-brightens layered content and diverges visually from the reference — `spoiler_animation.dart:304` ← `spoiler_mess.cpp:431-508` (plain `p.drawImage` with no explicit composition mode override)

- [ ] [MAJOR] `powerSavingPaused` is sampled once at `initSpoiler` via a `try/catch` and never refreshed — if the user toggles the power-saving setting while a spoiler widget is alive the animation continues (or stays frozen) incorrectly; C++ polls `anim::Disabled()` on every `SpoilerAnimation::index()` call so pausing/resuming is instantaneous — `spoiler_animation.dart:453-459` ← `spoiler_mess.cpp:796` (`if (anim::Disabled()) { paused = true; }` inside `index()`)

# stats_chart — Audit findings

## stats_chart — statistics chart widget

- [ ] [CRITICAL] `isFooterHidden` parsed from wrong JSON field: Dart reads `parsed['isFooterHidden']` (top-level) but AyuGram reads `root["subchart"]["show"]` (nested). Footer will be shown/hidden incorrectly — `stats_chart.dart:130` ← `AyuGram/statistics/statistics_data_deserialize.cpp:109-115`

- [ ] [CRITICAL] `weekFormat` detection uses wrong signal: Dart infers week format from timestamp delta between first two data points (`>= 6 * 24 * 3600 * 1000`); AyuGram reads `xTooltipFormatter` field from JSON (checks for `"'week'"` substring). These diverge whenever the field is explicitly set but timestamps don't match the delta heuristic — `stats_chart.dart:135-140` ← `AyuGram/statistics/statistics_data_deserialize.cpp:146-151`

- [ ] [CRITICAL] `defaultZoomXIndex` parsed from wrong field with wrong type: Dart reads `parsed['defaultZoomXIndex']` as `int?`; AyuGram reads `subchart.defaultZoom` as an array of two timestamps and resolves them to x-indices. Zoom entry point will be wrong or null when it should be set — `stats_chart.dart:131` ← `AyuGram/statistics/statistics_data_deserialize.cpp:116-135`

- [ ] [CRITICAL] Shake animation missing when user attempts to hide the last visible filter line: Dart silently returns (`return`) with no feedback; AyuGram calls `raw->shake()` which plays a horizontal shake animation on the checkbox — `stats_chart.dart:1163` ← `AyuGram/statistics/widgets/chart_lines_filter_widget.cpp:200-215`

- [ ] [CRITICAL] Line color key theming not implemented: AyuGram calls `FillLineColorsByKey()` on palette change to remap named keys ("BLUE", "GREEN", "RED", etc.) to current theme colors via `st::statisticsChartLineBlue` etc. Dart stores only the raw hex color from JSON and never updates on theme change — `stats_chart.dart:116-120` ← `AyuGram/statistics/chart_widget.cpp:41-65`

- [ ] [MAJOR] Footer gap (11px `statisticsChartFooterSkip`) missing between chart area and footer: AyuGram adds `statisticsChartFooterSkip: 11px` to the footer area total height, creating visible separation. Dart places `_kChartHeight` SizedBox and `_kFooterHeight` SizedBox back-to-back with zero gap — `stats_chart.dart:820-845` ← `AyuGram/statistics/statistics.style:28` and `chart_widget.cpp:873`

- [ ] [MAJOR] Filter button inactive background hardcoded: Dart uses `Color(0xFF1A2633)` (dark) / `Color(0xFFEEEEEE)` (light). AyuGram uses `st::boxBg` (theme-aware background color from `FlatCheckbox` constructor at `_inactiveColor(st::boxBg->c)`). Will be wrong on non-standard themes — `stats_chart.dart:1242-1243` ← `AyuGram/statistics/widgets/chart_lines_filter_widget.cpp:59`

- [ ] [MAJOR] Footer dim overlay colors hardcoded: Dart uses `Color(0x88000000)` / `Color(0x44AAAAAA)` for the inactive regions flanking the selection handle. AyuGram uses `st::statisticsChartInactive` (palette-bound). Will look wrong on light/non-default themes — `stats_chart.dart:1778-1779` ← `AyuGram/statistics/chart_widget.cpp:449`

- [ ] [MAJOR] Line name em dash substitution missing: AyuGram replaces `-` characters in line names with em dash `QChar(8212)` during deserialization. Dart passes names through unmodified. Filter button labels and tooltip line names will show hyphens where em dashes should appear — `stats_chart.dart:119` ← `AyuGram/statistics/statistics_data_deserialize.cpp:169`

- [ ] [MAJOR] DoubleLinear chart has no dual Y-axis rulers: Dart's `_drawRulerSet` draws a single shared Y-axis for all lines. AyuGram's `ChartRulersView` renders left and right Y-axis rulers in the line colors of the two respective lines. The right-side scale is completely absent in Dart — `stats_chart.dart:1395-1431` ← `AyuGram/statistics/view/chart_rulers_view.cpp:63-78`

- [ ] [MAJOR] Date label crossfade system is simplified: AyuGram maintains a queue of `BottomCaptionLineData` entries (up to 2) with independent step/alpha levels that fade across, using `restartBottomLineAlpha()` and a 200ms alpha animation per density change. Dart uses a single `_dateLabelAlpha` that fades all labels uniformly — `stats_chart.dart:1452-1455` ← `AyuGram/statistics/chart_widget.cpp:1015-1082`

- [ ] [MAJOR] Currency ruler labels (USD conversion) not displayed: AyuGram's `ChartRulersView` shows a right-side ruler with USD-converted values when `currencyRate` is present, using `Info::ChannelEarn::ToUsd`. Dart shows only raw values in the single ruler regardless of currency — `stats_chart.dart:1395-1431` ← `AyuGram/statistics/view/chart_rulers_view.cpp:46-62`

- [ ] [MAJOR] Tooltip zoom arrow uses wrong icon: Dart shows `Icons.chevron_right` (14px Material icon). AyuGram renders a custom two-segment arrow drawn at `statisticsDetailsArrowShift: 3px` / `statisticsDetailsArrowStroke: 1.5` in the exact foreground color. Visual mismatch — `stats_chart.dart:928-930` ← `AyuGram/statistics/widgets/point_details_widget.cpp:143-148` and `statistics.style:21-22`

- [ ] [MAJOR] `_updateRulerRange()` and `_updateFooterYRange()` called inside `build()`: These functions iterate over all visible data points (O(n)) and may call `_ensureTickerRunning()` → start ticker → `setState` → `build()` again. On every animation frame the ticker fires `setState`, which invokes `build()`, which recomputes Y ranges unnecessarily. These calls belong in `_onChartTick` and `_toggleLine`/`_onFooterPanUpdate`, not in the build method — `stats_chart.dart:642-643` ← `AyuGram/statistics/chart_widget.cpp:531-625` (animation controller handles Y recompute only on X/filter changes)

# sticker_pack_viewer — Missing install handler, wrong grid layout for emoji sets, incorrect padding

- [ ] [CRITICAL] Add button is disabled (onPressed: null) and doesn't call installStickerSet when clicked — `sticker_pack_viewer.dart:155` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/sticker_set_box.cpp:996`

- [ ] [MAJOR] Grid always uses 5 columns for all sticker types, but should use 8 columns for emoji sets — `sticker_pack_viewer.dart:181` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/sticker_set_box.cpp:1270` (kEmojiPerRow = 8 vs kStickersPerRow = 5)

- [ ] [MAJOR] Padding is hardcoded to 8px for all types, should use emojiSetPadding (12px,0px,12px,0px) for emoji and stickersPadding (19px,13px,19px,13px) for stickers — `sticker_pack_viewer.dart:179` ← research/telegram_desktop_ui.md (emojiSetPadding, stickersPadding)

- [ ] [MAJOR] Button text doesn't differentiate between sticker types: always shows "Add Stickers" but AyuGram shows "Add Pack", "Add Masks", or "Add Emoji" based on type — `sticker_pack_viewer.dart:164` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/sticker_set_box.cpp:991-995`

# engine_models — Data model DTO audit

File implements: Dart model classes mirroring Go engine types (AccountInfo, ChatInfo, CachedMessage, events, forum topics, scheduled messages, etc.) — pure data / serialization layer, no UI.

---

- [ ] [CRITICAL] `CachedMessage.fromJson` is called by `MsgReceivedEvent.fromJson` on every real-time incoming message event (`engine_service.dart:3746`), but it does **not** decode `content_raw` — so all fields labeled "extracted from contentRaw extra fields" (`pollQuestion`, `pollOptions`, `geoLat`/`geoLong`, `contactFirstName`/`contactPhone`, `wpUrl`/`wpTitle`/`wpDescription`, `gameTitle`, `invoiceTitle`, `audioTitle`/`audioPerformer`, `repliesCount`, `replyKeyboard`, `inlineKeyboard`, `views`, `forwards`, `topicId`, `ttlSeconds`, `altQualities`, `mediaUnread`, `stickerSetShortName`, `viaBotName`) always default to `''`/`0`/`[]` for every real-time received message. The message is immediately inserted into `_messages` (`chat_state.dart:2089`) and rendered. A received poll renders with no question and no options; a location message renders with `geoLat = 0.0 / geoLong = 0.0`; a voice message has no waveform bar; a contact card is blank. AyuGram always has full data before rendering — poll question is read from `PollData::question` (populated on receive, never deferred) and voice waveform is decoded from the full document immediately on receive — `engine_models.dart:696` ← `AyuGram/data/data_poll.cpp:65`, `AyuGram/data/data_document.cpp:441`

- [ ] [CRITICAL] `CachedMessage.fromJson:728` attempts to parse `j['media_waveform']` from top-level JSON, but the Go `CachedMessage` struct (`engine/cache_msgs.go:24-71`) has no `MediaWaveform` field — this key is never present in the JSON event payload, so `mediaWaveform` is always `const []` for every message received via the real-time event path. Voice messages arriving in real-time show no waveform visualization. AyuGram decodes waveform from the document's `VoiceData::waveform` field (`data_document.cpp:441-445`) which is populated during the same receive pass — `engine_models.dart:728` ← `AyuGram/data/data_document.cpp:1333`

- [ ] [MAJOR] `StickerInfoItem.isFaved` (line 2111) is a non-final mutable field on a plain data class. Mutating `isFaved` directly (`item.isFaved = true`) produces no `notifyListeners`, no stream event, and no widget rebuild — the sticker grid will silently show the wrong fav state after toggling. AyuGram's sticker fav state is tracked in a session-level `Data::Stickers` store that emits updates via `Notify::PeerUpdated` / `session().changes()`, never by mutating a data field — `engine_models.dart:2111` ← `AyuGram/data/data_stickers.cpp` (sticker fav/unfav via `addedToSet`/`removedFromSet` triggers `session().changes().peerUpdated.fire`)

- [ ] [MAJOR] `AuthStateData.fromJson` (lines 148–167) does not parse `qrData` (line 118) or `avatarB64` (line 121). These fields remain `const []` / `''` for any `AuthStateData` constructed via `fromJson`. Tests `widget_comprehensive_test.dart:1267` and `widget_comprehensive_test.dart:1301` use this factory for QR-auth coverage, so QR-code rendering and avatar display in auth flow are untested. (Production code uses `_authStateFromProto` which correctly populates both fields — `engine_service.dart:3825-3828`; the `fromJson` factory is test-only but its gaps mean zero test coverage of QR data flow.) AyuGram's QR login always passes full link bytes through from the API response — `engine_models.dart:148` ← `AyuGram/ui/auth/auth_form_qr.cpp` (QR bytes come in full from `MTP::AuthImportLoginToken`)

- [ ] [MAJOR] `ScheduledMessages.isScheduledMsgId` (line 2647) uses `_kServerMaxMsgId = 0x3FFFFFFF` (1,073,741,823). AyuGram's `ServerMaxMsgId = 1LL << 56` (72,057,594,037,927,936 — `data_msg_id.h:80`). If this method is ever called with actual Telegram message IDs, it will return `true` for any ID > 1 billion (most channel post IDs and media IDs), misidentifying normal messages as scheduled. The method is currently unreferenced from UI code (dead code), but the wrong constant creates a latent critical bug if wired up — `engine_models.dart:2647` ← `AyuGram/data/data_msg_id.h:80`

# story_editor — Story Editor Layer

- [ ] [CRITICAL] Video file never sent to engine — `_postStory()` always falls into `_renderCanvasToBytes()` when `_videoFile != null` (because `_imageFile` is null), which renders only the gradient background and sends that as a photo; the actual video file is completely ignored and there is no `sendStoryWithVideo` call — `story_editor.dart:329-349` ← `editor_paint.cpp:1` (video story requires separate video upload API)

- [ ] [CRITICAL] Privacy, duration, and posting settings not passed to engine — `_privacy`, `_durationHours`, `_saveToProfile`, `_allowSharing` are captured in UI state but `engine.sendStoryWithPhoto` only receives `accountId`, `caption`, and `photoData`; all four settings are silently discarded — `story_editor.dart:345-349` ← `engine_service.dart:946-951`

- [ ] [CRITICAL] `_renderCanvasToBytes()` excludes paint strokes and scene items from exported image — the canvas renderer draws only the background image or gradient, never iterating over `_strokes` or `_sceneItems`; any drawn strokes, text overlays, or emoji are absent from the uploaded story — `story_editor.dart:366-391` ← `editor_paint.cpp:276-281` (AyuGram's `saveScene()` serialises the full scene including canvas items)

- [ ] [CRITICAL] Sticker picker shows only 64 hardcoded emojis, never real Telegram sticker packs — AyuGram uses `ItemSticker(document, itemBaseData())` driven by `stickerChosen()` from the sticker panel controller which pulls live packs from the session; Dart renders a static `_emojis` const array with no engine call — `story_editor.dart:2164-2228` ← `editor_paint.cpp:146-152`

- [ ] [CRITICAL] Eraser `BlendMode.clear` has no effect without `saveLayer` — the paint layer is a `CustomPaint` placed directly in a `Stack`; `BlendMode.clear` on a `Canvas` that is not inside a `saveLayer` composite clears to transparent, revealing black background rather than erasing underlying strokes; needs `canvas.saveLayer(Rect.largest, Paint())` wrapper — `story_editor.dart:1634-1637` ← `scene_item_canvas.cpp:131-141` (AyuGram uses `CompositionMode_Source` on an isolated per-canvas pixmap)

- [ ] [CRITICAL] Stroke path uses `lineTo` only — AyuGram renders each stroke segment as `path.quadTo(p0, ctrl)` with a midpoint control, preceded by two passes of Catmull-Rom smoothing via `smoothStroke()`; Dart draws a raw polyline (`path.lineTo`) producing jagged, faceted strokes instead of smooth curves — `story_editor.dart:1641-1645` ← `scene_item_canvas.cpp:162-177` (quadTo) and `scene_item_canvas.cpp:218-231` (double-pass smoothing)

- [ ] [MAJOR] Video duration hardcoded to 60 seconds — `_videoDuration` is set to `Duration(seconds: 60)` unconditionally on video pick; no video metadata is read; trim slider is calibrated against a wrong total duration — `story_editor.dart:241` ← `_VideoTrimSlider` widget uses this value for display

- [ ] [MAJOR] Video trim thumbnails are fake coloured blocks — `_VideoTrimPainter` fills frame cells with HSL hue-shifted colours; no video frame extraction is attempted; the trim bar shows fictional rainbow tiles rather than actual video frames — `story_editor.dart:2104-2112` ← AyuGram generates real frame thumbnails for the trim control

- [ ] [MAJOR] Upload progress is artificially simulated — two `Future.delayed` sleeps (100 ms, 150 ms) fake progress at 30 %, 60 %, 100 % rather than tracking real upload bytes; if the engine call takes longer the bar freezes at 60 % — `story_editor.dart:339-356`

- [ ] [MAJOR] "Stickers" tab label in picker panel exists but is non-functional — `_StickerPickerPanel._tabs` declares `['Emoji', 'Stickers']` and renders both labels, but no tab switch logic, no sticker grid, and no engine call back the "Stickers" label; tapping it does nothing — `story_editor.dart:2162-2200`

- [ ] [MAJOR] Privacy "Selected Contacts" option has no contact selection UI — selecting it in `_PrivacyDialog` saves the enum value but never opens a contact picker; the story would be posted with no allowed viewers if the engine honored the setting — `story_editor.dart:1824-1828`

- [ ] [MAJOR] Arrow arrowhead direction uses adjacent point instead of minimum-distance lookback — AyuGram walks backward through stroke history to find a point at `size × 1.5` distance from the tip before computing angle; Dart always uses `points[length-2]` which is often the immediately preceding sample, producing wildly inaccurate arrowhead angles on slow strokes — `story_editor.dart:1649-1651` ← `scene_item_canvas.cpp:234-248`

- [ ] [MAJOR] `FocusNode` created in `build()` without reference or disposal — `story_editor.dart:421` creates `FocusNode()..requestFocus()` inline; this allocates a new `FocusNode` on every rebuild, leaking the previous one since it is never stored in state or disposed in `dispose()` — `story_editor.dart:421`

- [ ] [MAJOR] `_StrokePainter.shouldRepaint` returns unconditional `true` — every `setState` call during stroke drawing (fired on every pointer-move event) repaints the entire strokes canvas from scratch; with hundreds of strokes this is O(n) work per pointer sample; AyuGram uses incremental dirty-rect updates via `_rectToUpdate` — `story_editor.dart:1670` ← `scene_item_canvas.cpp:204`

- [ ] [MAJOR] `_continueStroke` calls `setState` on every `onPointerMove` event — this triggers a full rebuild of the entire `_StoryEditorLayerState` widget tree on each pointer sample (typically 120 times/second at high refresh rates); strokes and scene items should be driven by a `ValueNotifier`/`ChangeNotifier` to isolate repaints — `story_editor.dart:551-555`

- [ ] [MAJOR] Color button diameter is 28 px vs spec 24 px — `_buildColorButton()` sizes the circle at `width: 28, height: 28`; AyuGram specifies `photoEditorColorButtonSize: 24px` — `story_editor.dart:888-889` ← `editor.style:126`

# telegram_toast — Toast widget audit

- [ ] [CRITICAL] Wrong background color: Dart uses pure black at ~70% opacity (`Color(0xB2000000)`) but AyuGram `toastBg` is dark charcoal gray at ~90% opacity (`#2c3033e5` → Flutter `Color(0xE52C3033)`); both hue and alpha are wrong — `telegram_toast.dart:34` ← `AyuGram/lib_ui/ui/colors.palette:444`

- [ ] [CRITICAL] `_StickerToast` missing animated sticker/emoji preview: AyuGram renders a Lottie or custom-emoji animated preview widget in the toast's left padding area (`setupLottiePreview`/`setupEmojiPreview`, size = `font->height * 2`); Dart shows text only — `telegram_toast.dart:383-415` ← `AyuGram/SourceFiles/history/view/history_view_sticker_toast.cpp:216-225`

- [ ] [MAJOR] Default (no-attach) toast anchored at bottom (`bottom: 52px`) instead of vertically centered: AyuGram positions `RectPart::None` toasts at `middle = QPoint((w-tw)/2, (h-th)/2)` — exact screen center; Dart uses `bottom: _kMargin * 4` which keeps the toast near the bottom — `telegram_toast.dart:217` ← `AyuGram/lib_ui/ui/toast/toast_widget.cpp:483`

- [ ] [MAJOR] Slide-attached toasts incorrectly add opacity fade: AyuGram slide toasts keep `opacity = 1.0` throughout (only position animates); Dart wraps `FractionalTranslation` in `Opacity(opacity: _fadeIn/fadeOut.value)` causing unwanted simultaneous fade — `telegram_toast.dart:163-169` ← `AyuGram/lib_ui/ui/toast/toast_widget.cpp:571-573`

- [ ] [MAJOR] `_StickerToast` display duration is 1500ms instead of 3000ms: AyuGram uses `kPremiumToastDuration = 3 * crl::time(1000)` for sticker toasts; Dart hardcodes `Timer(const Duration(milliseconds: 1500), _startHide)` — `telegram_toast.dart:303` ← `AyuGram/SourceFiles/history/view/history_view_sticker_toast.cpp:31`

- [ ] [MAJOR] `_StickerToast` text layout wrong: AyuGram renders `tr::bold(title)` on line 1 + newline + pack-specific body text (`tr::lng_animated_emoji_text` / `tr::lng_sticker_premium_text`); Dart renders a flat inline sentence with no bold title and no two-line structure — `telegram_toast.dart:322-380` ← `AyuGram/SourceFiles/history/view/history_view_sticker_toast.cpp:148-156`

- [ ] [MAJOR] `_StickerToast` uses wrong `maxWidth` (480px vs 380px): the sticker toast style `historyPremiumToast` sets `maxWidth: 380px`; Dart uses the default `_kMaxWidth = 480px` — `telegram_toast.dart:385` ← `AyuGram/SourceFiles/ui/chat/chat.style:258`

- [ ] [MAJOR] `_StickerToast` missing right-click to dismiss: AyuGram creates a `clickableBackground` `AbstractButton` over the toast that calls `hideAnimated()` on right-click; Dart has no such handler — `telegram_toast.dart:397-413` ← `AyuGram/SourceFiles/history/view/history_view_sticker_toast.cpp:190-198`

# telegram_tooltip — Color not wired to palette + tooltip delay mismatch

- [ ] [CRITICAL] `showImportantTooltip()` hardcodes text color as `Colors.white` instead of using `palette.importantTooltipFg` from PaletteProvider — `telegram_tooltip.dart:494` ← `telegram_palette.dart:importantTooltipFg` / `widgets.style:defaultImportantTooltipLabel`

- [ ] [MAJOR] `TelegramTooltip` shows with 1000ms delay (`_kShowDelay`) vs AyuGram's 500ms (`kTooltipShowTimeoutMs`) — `telegram_tooltip.dart:12` ← `calls_emoji_fingerprint.cpp:19`

- [ ] [MAJOR] Missing `hideAfter()` support on `ImportantTooltip` — AyuGram's `ImportantTooltip::hideAfter()` allows auto-dismiss after timeout, Dart version only supports manual dismissal via callback — `telegram_tooltip.dart:208-226` ← `lib_ui/ui/widgets/tooltip.h:102`


# theme_confirm_overlay — Behavioral mismatch on removal animation

## Issues Found

- [ ] [MAJOR] **Overlay doesn't animate out before removal** — When user confirms or reverts, the overlay is immediately removed from the widget tree without fade-out animation. AyuGram's `WarningWidget::hideAnimated()` (window_theme_warning.cpp:122-124) animates the overlay out using `startAnimation(true)` before removal. Dart version calls the callback and parent immediately hides it via `setState(() => _showThemeConfirm = false)` (chat_settings_screen.dart:414,418), which removes the widget from the tree instantly. The overlay only has fade-in animation (initState:43), no fade-out. **Expected:** ThemeConfirmOverlay should animate out over ~200ms before calling the callback, or parent should handle the animation.
  - `theme_confirm_overlay.dart:29-30` (no hideAnimated/removal animation mechanism)
  - `window_theme_warning.cpp:122-144` (hideAnimated calls startAnimation which animates out)
  - `chat_settings_screen.dart:410-420` (parent immediately sets _showThemeConfirm = false on callback)

- [ ] [MAJOR] **No localization for text strings** — Title and countdown text are hardcoded English strings. AyuGram uses `tr::lng_theme_sure_keep(tr::now)` and `tr::lng_theme_reverting(tr::now, lt_count, _secondsLeft)` for multi-language support (window_theme_warning.cpp:70,113). Dart version uses hardcoded strings: "Are you sure you want to keep this theme?" and "Theme will revert in $seconds seconds" (theme_confirm_overlay.dart:112,122). **Expected:** Text should use localization/i18n framework if app supports multiple languages.
  - `theme_confirm_overlay.dart:112,122` (hardcoded strings)
  - `window_theme_warning.cpp:70,113` (uses tr::lng_* translation keys)

## Non-Issues (design differences appropriate for Flutter/mobile)

- Button layout: AyuGram uses bottom-right stacked layout (RoundButton, `st::defaultBox.buttonPadding`); Flutter uses side-by-side Row centered at bottom. This is appropriate responsive design for mobile/web vs desktop.
- Button type: AyuGram uses `Ui::RoundButton`; Flutter uses `TextButton`. Appropriate for Flutter Material Design.
- Colors: Hardcoded in Dart (0xFF3390EC, 0xFF40A7E3); AyuGram uses theme values (`st::boxBg`, etc.). Acceptable for single-theme app.
- Countdown timer: Both 15999ms, updates every 100ms ✓
- Escape key behavior: Both revert on Escape ✓
- Fade animation: Both have fade in on show (200ms) ✓
- Auto-revert on timeout: Both auto-revert when countdown reaches 0 ✓
- Backend wiring: onKeep → `appState.keepAppliedTheme()`, onRevert → `appState.revertTheme()` ✓

# theme_editor — Audit Findings

## theme_editor — Critical and major gaps vs AyuGram Desktop

- [ ] [CRITICAL] No cloud save API call — `_SaveThemeBoxState._save()` packs theme locally and pops the dialog; no `MTPaccount_CreateTheme` / `MTPaccount_UpdateTheme` call is ever made, so themes are never uploaded to Telegram cloud despite the "Link" slug field existing — `theme_editor.dart:749-771` ← `window_theme_editor_box.cpp:710-737` (`SaveTheme` → `SavePreparedTheme` → `MTPaccount_CreateTheme`)

- [ ] [CRITICAL] No color picker — clicking a palette row opens only an inline hex text field; AyuGram opens a full RGBA `ColorEditor` box with HSV sliders — `theme_editor.dart:497-526` ← `window_theme_editor_block.cpp:323-357` (`activateRow` → `Ui::show(Box([=](box){ ColorEditor(box, Mode::RGBA, value) ... }))`)

- [ ] [CRITICAL] No close confirmation when palette is unsaved — `Navigator.of(context).pop()` fires immediately with no change-detection check; AyuGram shows "Are you sure? Unsaved changes will be discarded." — `theme_editor.dart:238` ← `window_theme_editor.cpp:914-929` (`closeWithConfirmation` calling `PaletteChanged`)

- [ ] [CRITICAL] Slug validation allows empty slug — Dart skips validation entirely when slug is empty (`if (slug.isNotEmpty && !_validateSlug(slug)) return`); AyuGram requires `IsGoodSlug` which rejects any slug shorter than `kMinSlugSize=5`, including empty — `theme_editor.dart:757-758` ← `window_theme_editor_box.cpp:376-386,896-901`

- [ ] [MAJOR] Color swatch size wrong — Dart renders a 32×32 square swatch; AyuGram uses `themeEditorSampleSize: size(90px, 51px)` — `theme_editor.dart:571` ← `window.style:167`

- [ ] [MAJOR] Row height fixed at 60px — Dart uses `itemExtent: 60` for all rows; AyuGram computes dynamic height: `themeEditorMargin.top(10) + themeEditorSampleSize.height(51) + descriptionSkip(10) + descriptionText.height + themeEditorMargin.bottom(10)` giving minimum ~71px without a description, taller with one — `theme_editor.dart:200,325` ← `window_theme_editor_block.cpp:533-558`

- [ ] [MAJOR] Name font 13px instead of 15px semibold — `theme_editor.dart:488-492` ← `window.style:170` (`themeEditorNameFont: font(15px semibold)`)

- [ ] [MAJOR] Missing "Existing / New" row split — AyuGram separates the palette list into two `EditorBlock` sections ("Existing" rows from the file and "New" rows from default style), with a "New keys" title between them; Dart has a single flat `ListView` — `theme_editor.dart:318-356` ← `window_theme_editor.cpp:399-401,551-558` and `window_theme_editor_block.cpp:552-558`

- [ ] [MAJOR] No row description text — AyuGram renders a `descriptionText` below the colour name when available (`style::main_palette::data()`); Dart only shows `= copyOf` reference — `theme_editor.dart:545-557` ← `window_theme_editor_block.cpp:745-749`

- [ ] [MAJOR] Missing `:sort-for-accent` filter command — AyuGram's filter field recognises the literal query `:sort-for-accent` and re-sorts all rows by HSL distance to the accent colour; Dart filter is simple substring only — `theme_editor.dart:59-63` ← `window_theme_editor.cpp:479-487` (`sortByAccentDistance`)

- [ ] [MAJOR] "Show in Folder" menu item replaced — AyuGram's three-item menu has Export / Import / "Show in folder" (opens the palette file location); Dart substitutes "Copy Palette Text" and removes the folder-reveal action — `theme_editor.dart:128-148` ← `window_theme_editor.cpp:757-761`

- [ ] [MAJOR] Slug field not pre-filled with random slug — AyuGram pre-fills the link field with a randomly generated 16-char slug via `GenerateSlug()`; Dart starts with an empty `TextEditingController()` — `theme_editor.dart:701` ← `window_theme_editor_box.cpp:811,986-1007`

- [ ] [MAJOR] Export filename always "custom" — both branches of the ternary at `theme_editor.dart:83` evaluate to `'custom'`, so every exported file is named `custom.tdesktop-theme` regardless of theme title — `theme_editor.dart:83`

- [ ] [MAJOR] No ripple animation on row press — Dart uses plain hover-colour swap; AyuGram has `RippleAnimation` triggered on `mousePressEvent` for each row — `theme_editor.dart:466-576` ← `window_theme_editor_block.cpp:561-580,786-797`

- [ ] [MAJOR] Save button is a small header TextButton instead of full-width bottom bar — AyuGram renders the save action as a full-width `st::dialogsUpdateButton` bar anchored to the bottom of the editor column; Dart has a small `TextButton('Save')` inside the top header row — `theme_editor.dart:262-265` ← `window_theme_editor.cpp:675-678,879`

# titlebar — Active state, dimensions, right-click menu missing

- [ ] [CRITICAL] Titlebar height is 28px and button width is 46px but AyuGram spec is 24px / 36px — 17% height deviation and 28% button width deviation — `titlebar.dart:65-66` ← `AyuGram/lib_ui/ui/widgets/widgets.style:1576-1577`

- [ ] [CRITICAL] Missing active/inactive window focus state: titlebar background never switches between `titleBg` (inactive) and `titleBgActive` (active); AyuGram `paintEvent` uses `active ? st->bgActive : st->bg` — `titlebar.dart:177` ← `AyuGram/lib_ui/ui/platform/ui_platform_window_title.cpp:462-467`

- [ ] [CRITICAL] Missing active/inactive button state update: AyuGram tracks `_activeState` and calls `updateButtonsState()` to switch button icons between inactive (`minimizeIcon`) and active (`minimizeIconActive`) variants on window focus change; Dart `_WinButton` has no such state change — `titlebar.dart:235-260` ← `AyuGram/lib_ui/ui/platform/ui_platform_window_title.cpp:80-125`

- [ ] [CRITICAL] Missing right-click context menu on drag area: AyuGram `mousePressEvent` calls `ShowWindowMenu(window(), e->windowPos().toPoint())` on right-click; Dart `GestureDetector` has no `onSecondaryTap`/`onSecondaryLongPress` handler — `titlebar.dart:200-205` ← `AyuGram/lib_ui/ui/platform/ui_platform_window_title.cpp:473-478`

- [ ] [MAJOR] Material icon substitutes used instead of custom title button sprite icons: Dart uses `Icons.remove`, `Icons.filter_none`, `Icons.crop_square`, `Icons.close`; AyuGram uses `title_button_minimize`, `title_button_maximize`, `title_button_restore`, `title_button_close` icon sprites — `titlebar.dart:147,154,162` ← `AyuGram/lib_ui/ui/widgets/widgets.style:1600-1667`

- [ ] [MAJOR] Missing `oneSideControls` consolidation: AyuGram `updateControlsPosition()` moves all buttons to one side when `oneSideControls` is set or layout dictates it; Dart always renders left buttons on left and right buttons on right with no consolidation — `titlebar.dart:195-208` ← `AyuGram/lib_ui/ui/platform/ui_platform_window_title.cpp:325-339`

- [ ] [MAJOR] `isDark` variable computed but never used — suggests active/inactive coloring logic was started but abandoned; dead code indicating incomplete implementation — `titlebar.dart:176` ← `AyuGram/lib_ui/ui/colors.palette:101` (`titleBgActive` color)

# web_app_panel — Web App Panel Audit

- [ ] [CRITICAL] No actual webview embedded — "ready" state shows static placeholder "Web App opened externally" with open-in-browser fallback instead of embedded webview content — `web_app_panel.dart:384-416` ← `AyuGramDesktop/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:173` (`createWebview()`)

- [ ] [CRITICAL] `_simulateLoading()` fakes loading with a hardcoded 800ms delay — no real webview initialization, no actual page load events — `web_app_panel.dart:140-151` ← `AyuGramDesktop/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:493-500` (real webview init with `showWebview()`)

- [ ] [CRITICAL] `_onBack()` is an empty stub — back button press never dispatches `"back_button_pressed"` event to the mini app JS — `web_app_panel.dart:190` ← `AyuGramDesktop/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:472-475` (`postEvent("back_button_pressed")`)

- [ ] [CRITICAL] Main button `onPressed: () {}` is a dead callback — click never sends `"main_button_pressed"` event to the webview — `web_app_panel.dart:471` ← `AyuGramDesktop/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:1907-1909` (main button click dispatches event)

- [ ] [CRITICAL] Secondary button `onPressed: () {}` is a dead callback — click never sends `"secondary_button_pressed"` event to the webview — `web_app_panel.dart:483` ← `AyuGramDesktop/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:1909` (secondary button click dispatches event)

- [ ] [CRITICAL] `_showMenu` discards `showMenu<String>()` return value — menu item selections ("Open Bot", "Settings", "Remove from Menu") are never handled; no delegate callbacks fire on tap — `web_app_panel.dart:208-241` ← `AyuGramDesktop/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:780-822` (each item calls `_delegate->botHandleMenuButton(...)`)

- [ ] [CRITICAL] No webview message handler — panel never processes any `web_app_*` JS commands (web_app_setup_main_button, web_app_setup_back_button, web_app_setup_settings_button, web_app_request_theme, web_app_request_viewport, web_app_close, web_app_data_send, etc.) so the mini app JS cannot control the panel at all — `web_app_panel.dart:102-557` (no message handler exists) ← `AyuGramDesktop/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:953-1100` (`setMessageHandler` handling 30+ commands)

- [ ] [MAJOR] Secondary button position defaults to `WebAppButtonPosition.bottom` — AyuGram's `ParsePosition()` returns `RectPart::Left` as default (side-by-side layout), meaning unspecified position should default to left — `web_app_panel.dart:111` ← `AyuGramDesktop/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:70-81`

- [ ] [MAJOR] Menu is missing required items — AyuGram always shows "Reload page" (reloads webview), "Terms" (opens mini apps ToS URL), and "Privacy" (calls `botOpenPrivacyPolicy()`); none of these exist in the Dart menu — `web_app_panel.dart:214-239` ← `AyuGramDesktop/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:785-806`

- [ ] [MAJOR] "Settings" menu item never fires `"settings_button_pressed"` to the webview even when menu selection is handled — AyuGram calls `postEvent("settings_button_pressed")` when settings is tapped — `web_app_panel.dart:224-231` ← `AyuGramDesktop/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:776-778`

