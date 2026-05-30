# GUI Audit — Cycle 1 Phase Ayugram (2026-05-27 19:07)

## Code Comparison (Dart vs AyuGram)

# web_drop — File drag-and-drop utility for web platform

## Findings

- ✓ [CLOSED 2026-05-29] File size limit — `web_drop_web.dart:56` `_kMaxFileSizeBytes` corrected to `4000 * 1024 * 1024` (4000 MiB), matching AyuGram `kFileSizePremiumLimit` (`storage/localimageloader.h:25`) and the drag-drop reject at `storage/storage_media_prepare.cpp:150`. Verified by byte-exact value comparison + clean `flutter analyze`. (web-only file — no visual/desktop render to screenshot.)

## Verification

**No critical placeholders, stubs, or unimplemented features found.**

- ✓ All event listeners (dragenter, dragover, drop, dragleave) properly registered and cleaned up in initState/dispose
- ✓ Enter count tracking correctly handles nested elements (line 90-92, 130-132)
- ✓ Drag update throttled at 60Hz (16ms intervals) — reasonable for UI (line 117-120)
- ✓ MIME type collection on drag enter works correctly (line 93-105)
- ✓ File reading with 4 concurrent limit prevents resource exhaustion (line 169-171)
- ✓ Error handling properly catches exceptions and filters invalid reads (line 184-186, 188)
- ✓ Fully integrated with chat_view.dart: onDrop triggers file write + upload via `_uploadFiles()` (verified)
- ✓ Conditional imports work correctly: web_drop_web.dart for JS interop, web_drop_stub.dart for non-web

**Performance:**
- ✓ No unnecessary rebuilds (widget.child only, no extra state in build)
- ✓ No large synchronous operations on UI thread (FileReader is async)
- ✓ Batched file reads prevent memory spikes

**Wiring:**
- ✓ Backend fully integrated: dropped files are written to temp storage via `_writeWebDroppedFiles()` then uploaded via engine
- ✓ onDropRejected properly shows user feedback via SnackBar

---

## Recommendation

✓ Done & verified 2026-05-29 — `web_drop_web.dart:56` = `4000 * 1024 * 1024` (4000 MiB).
NOTE: the desktop drag-drop limit `chat_view.dart:18123` still has the identical bug (4096 MiB) — logged as a new finding below.

# chat_view — desktop drag-drop file size limit

- ✓ [CLOSED 2026-05-29] File size limit (desktop drag-drop) — `chat_view.dart:18123` `_kMaxDragFileSize` corrected to `4000 * 1024 * 1024` (4000 MiB), byte-exact match to AyuGram `kFileSizePremiumLimit` (`storage/localimageloader.h:25` = `4'000 * int64(1024*1024)`); reject check `storage/storage_media_prepare.cpp:150,217`; used at `chat_view.dart:18143`. Comment fixed. VERIFIED: byte-exact value comparison + app builds, launches & renders chat list cleanly (smoke test, no crash).

# notification_manager_default — DefaultManager logic deviations

- ✓ [CLOSED 2026-05-29] `startAllHiding()` HideAll-button fade — now schedules `_hideAllHideTimer` (deferred by `_dismissDuration`=3000ms, matching the rows) then calls `onStartHidingHideAll` → overlay sets `_hideAllOpacity 1.0→0.0` over 4000ms easeInCirc. Condition `showHideAll && _queue.length < 2` is a 1:1 port of `if (_hideAll && _queuedNotifications.size() < 2) _hideAll->startHiding()` (`notifications_manager_default.cpp:207-209`). Constants byte-match `window.style` (`notifySlowHide: 4000`, easeInCirc). VERIFIED at runtime (desktop 1024×768 + mobile 400×720): forced DefaultManager overlay, injected 2 notifs, HideAll button renders at opacity 1.0; instrumented log trace shows schedule→fire(+3.002s)→`_hideAllOpacity 1.0→0.0`. No crashes.

- ✓ [CLOSED 2026-05-29] `stopAllHiding()` HideAll-button restore — now cancels the pending `_hideAllHideTimer` and (when `showHideAll`) calls `onStopHidingHideAll` → overlay sets `_hideAllOpacity →1.0` over 150ms linear. 1:1 port of `if (_hideAll) _hideAll->stopHiding()` (`notifications_manager_default.cpp:217-219`); restore = `hideStop()` 150ms (`notifyFastAnim: 150`, linear). VERIFIED at runtime: re-enter DURING an active fade (opacity already heading to 0) correctly cancels + restores to 1.0 (log trace), and re-enter BEFORE the timer fires cancels it (no fade). Timer also torn down in `hideAll`/`clearAllFast`/`dispose`. No crashes.

# notification_manager_native — Linux DBus/Portal Notification Manager

- ✓ [CLOSED 2026-05-29] [MAJOR] Localized action labels — "Open"/"Mark as Read"/"Reply" now route through `TrStrings.lngOpenLink()`/`lngContextMarkRead()`/`lngNotificationReply()` on BOTH the DBus actions path and the Flatpak portal "Mark as read" button (3 strings added to strings.dart). 1:1 with AyuGram `tr::lng_open_link`/`tr::lng_context_mark_read`/`tr::lng_notification_reply` (`notifications_manager_linux.cpp:608,615,621,628`). VERIFIED: no hardcoded labels remain in the file; runtime dispatched 47 DBus notifications without error.

- ✓ [CLOSED 2026-05-29] [MAJOR] Placeholder userpic is now a circle, not a square — per-pixel circle draw (transparent corners + vertical gradient + anti-aliased edge, `numChannels:4` RGBA) replaces `img.fill()`. Gradient pairs = exact Telegram palette `historyPeerN UserpicBg/Bg2`; index map `[0,7,4,1,6,3,5]` byte-matches `ColorIndexToPaletteIndex` (`chat_style.cpp:1205`); 1:1 with `EmptyUserpic::paintCircle` (vertical `QLinearGradient` + circle shape). VERIFIED by standalone render of the exact logic: 4 corners alpha=0 (transparent), centre alpha=255 (opaque), top colour 90,201,227 ≠ bottom 54,156,212 (gradient).

- ✓ [CLOSED 2026-05-29] [MAJOR] App-icon fallback when userpic unavailable — tracks `imageHintSet`; `app_icon = imageHintSet ? '' : _desktopEntry`, so a decode failure / missing avatar (no image-data hint, even with previews on) falls back to the app icon instead of an icon-less notification. 1:1 with AyuGram `(!hasImage ? ApplicationIconName() : "")` (`notifications_manager_linux.cpp:772-773`). VERIFIED in code (app_icon now derives from `imageHintSet`).

- ✓ [CLOSED 2026-05-29] [MAJOR] `handlesSound` no longer gates on DND — now `handlesSound => _capabilities.contains('sound')`, a static capability check matching AyuGram `VolumeSupported()`/`HasCapability` (`notifications_manager_linux.cpp:235`). DND stays enforced separately: when `_inhibited` the sound-hint branch sets `suppress-sound=true` (analog of `invokeIfNotInhibited`, cpp:873). VERIFIED LIVE under real DND (`Inhibited (DND): true` in log): 47 notifications dispatched `(silent) (DND)`, server-suppressed, no app fallback audio.

- ✓ [CLOSED 2026-05-29] [MAJOR] Temp filenames now collision-free 64-bit random — `_randomFileId()` (random uint64 as 16-hex) replaces 32-bit `hashCode` for userpic, placeholder AND sound temp files. 1:1 with AyuGram `base::RandomValue<uint64>()` (`notifications_utilities.cpp:69`). VERIFIED LIVE: cache files use 16-hex-digit random names, e.g. `userpic_be0ef37464097324.png`, `userpic_53fe5f729882829a.png`.

- ✓ [CLOSED 2026-05-29] [MAJOR] Sound cache is now bounded LRU — `_kMaxSoundCacheEntries=64`; a cache hit refreshes recency (remove+reinsert) and `_evictSoundCacheIfNeeded()` drops least-recently-used entries AND deletes their temp files on overflow, so `/tmp/.../uniclient_audio_cache` can't grow unbounded. Matches AyuGram `Media::Audio::LocalDiskCache` (`notifications_manager_linux.cpp:337`). VERIFIED in code (eviction loop + recency refresh present).

# notification_system — NotificationSystem scheduling & dedup

- ✓ [CLOSED 2026-05-29] [CRITICAL] `clearForAccount` now tears down ALL per-account state — `_settingWaiters`, `_pendingTimers` (every timer `.cancel()`ed), `_groupedBuffer`, and `_accountStates` are cleared by `'$accountId:'` prefix match (trailing colon guards account "1" vs "12"); previously only `_whenMaps`/`_lastAlertPerThread` were cleared so timers scheduled via `_scheduleDispatch` fired AFTER logout with stale data (`notification_system.dart:705-732`). 1:1 with AyuGram `clearFromSession`→`clearForThreadIf` which erases `_whenMaps`/`_whenAlerts`/`_waiters`/`_settingWaiters` per thread AND cancels `_waitTimer` (`notifications_manager.cpp:542-600`). VERIFIED in code + clean build (exit 0) + app launched/rendered both modes with no crash.

- ✓ [CLOSED 2026-05-29] [CRITICAL] `_settingWaiters` is now a per-thread QUEUE (`Map<String,List<NotificationData>>`) — `onNewMessage` appends EVERY unknown-mute notification to the thread's list instead of `putIfAbsent` of a single value, so all N messages arriving during the unknown-state window are preserved; `checkDelayed()` and `resolveDelayedMuteState()` drain the WHOLE queue on resolution (`notification_system.dart:140,270-275,580-658`). Matches AyuGram where the full unread queue lives on the Thread and `checkDelayed`→`showNext` dispatches all N (`notifications_manager.cpp:646-678`). VERIFIED in code + AyuGram source + clean build.

- ✓ [CLOSED 2026-05-29] [MAJOR] `_whenMaps` dedup now uses the full `_threadKey` (incl. `:t:topicRootId` / `:s:sublistPeerId`), identical to `_lastAlertPerThread` — both `_passesDedup` and `_dispatch` key by `_threadKey(data)`, and per-topic/sublist clears use matching keys, so a different topic in the same group is no longer wrongly suppressed after `clearIncomingFromTopic` (`notification_system.dart:300-313,331,544,692-703`). 1:1 with AyuGram keying `_whenMaps`/`_whenAlerts`/`_settingWaiters` by `not_null<Data::Thread*>` (`notifications_manager.h:212-223`, confirmed). VERIFIED in code + AyuGram source.

- ✓ [CLOSED 2026-05-29] [MAJOR] `notifyFromAll=false` filter is no longer a no-op — `_shouldNotifyForType` dropped the `_activeAccountId.isNotEmpty` guard, and `main.dart` keeps `_notifSystem.activeAccountId` synced to `AppState.activeAccountId` on each notification, so notifications from non-active accounts are genuinely silenced (`notification_system.dart:286-298`, `main.dart:567-573`). 1:1 with AyuGram `!notifyFromAll() && &thread->session().account() != &Core::App().domain().active()` — no empty-skip fallback (`notifications_manager.cpp:342-343`, confirmed). VERIFIED in code + AyuGram source.

# notification_types — Backend wiring & composition

- ✓ [CLOSED 2026-05-29] [CRITICAL] forwardCount >1 is now reachable. Per-message stays `forwardFrom.isNotEmpty ? 1 : 0` (1:1 with AyuGram `isForwarded ? 1 : 0`, `notifications_manager.cpp:852`); `NotificationSystem._flushGroupedBuffer` (`notification_system.dart:483-492`) groups consecutive forwards from the same `senderId` within a 2s window and raises `forwardCount: group.length`, firing `lngForwardMessages` → "Forwarded N messages" (`notification_types.dart:344-345`). Matches AyuGram grouping (`notifications_manager.cpp:887-905` `++forwardedCount`; display `:1608-1609`). End-to-end path confirmed: `onNewMessage`→`_isGroupable`(277)→`_addToGroupBuffer`(278)→flush. VERIFIED in code + AyuGram + clean build/launch both modes.

- ✓ [CLOSED 2026-05-29] [CRITICAL] senderId populated — `chat_state.dart` writes `senderId: msg.senderId`; consumed by forward/album grouping (`notification_system.dart:423,459`). VERIFIED in code.

- ✓ [CLOSED 2026-05-29] [CRITICAL] accountUsername & multiAccount populated — `multiAccount: _appState.accounts.length > 1`, `accountUsername: _notifAccountLabel()` (username else displayName); `_composeTitle` appends ` ➜ username` (`notification_types.dart:305-307`). 1:1 with AyuGram `addTargetAccountName` (`notifications_manager.cpp:1248-1264`: `username().isEmpty() ? name() : username()`, separator " ➜ "). VERIFIED in code + AyuGram.

- ✓ [CLOSED 2026-05-29] [MAJOR] caption extended to types {1,2,3,4,7,8} (photo/video/audio/voice/GIF/file) via `_withCaption`. Matches AyuGram `MediaFile::notificationText` (`data_media_types.cpp:1294` routes video/GIF/voice/audio-file/file through `WithCaptionNotificationText`; sticker returns early `:1270`). Videonote(5)/sticker(6) correctly excluded — they carry no caption. VERIFIED in code + AyuGram.

- ✓ [CLOSED 2026-05-29] [MAJOR] NotificationSettings now wired — `main.dart._buildNotifSettings` maps AppState (volume, corner via `_mapNotifCorner`, maxNotificationCount, displayIndex, preview/per-type/notifyFromAll toggles) → NotificationSettings at init; `_syncNotifSettings` listener keeps them live on change. Settings now affect real notifications (was hardcoded defaults). VERIFIED in code + clean launch (no crash on init path).

- ✓ [CLOSED 2026-05-29] [MAJOR] isReactorPeer populated — `(msg.isReaction || msg.isPollVote) && chat.type==dm`; `_composeSubtitle` hides reactor name when set (`notification_types.dart:317`). 1:1 with AyuGram `reactionFrom != peer` (`notifications_manager.cpp:1590`) — in a DM the reactor IS the peer. VERIFIED in code + AyuGram.

- ✓ [CLOSED 2026-05-29] [MAJOR] spoiler login-code now checks the PEER — `loginCodePeerIds.contains(event.chatId)` first, senderId fallback. 1:1 with AyuGram `peer->isNotificationsUser() || peer->isVerifyCodes()` (`notifications_manager.cpp:1104-1107`). IDs 333000/777000/489000 are hardcoded in Telegram Desktop's own `data_peer.h:283` (333000 | kServiceNotificationsId 777000) + `data_peer.cpp:1593` (kVerifyCodesId 489000) — ground-truth, not a deviation. VERIFIED in code + AyuGram.

- ✓ [CLOSED 2026-05-29] [MINOR] subtitle is NOT dead — `NotificationSystem._dispatch` fills it from `composeNotificationContent` (`notification_system.dart:529`) and NativeManager renders it (`notification_manager_native.dart:695-701,813`). Matches AyuGram `.subtitle = subtitle` (`notifications_manager.cpp:1659`). VERIFIED in code + AyuGram.

- ✓ [CLOSED 2026-05-29] [MINOR] topicRootId now populated (`topicRootId: msg.topicRootId`) and used in `_threadKey` per-topic dedup. Remaining fields (soundDocumentPath/soundNone/perChatVolume/muteStateUnknown/isMonoforumSublist/sublistPeerName/sublistPeerId) are forward-looking scaffolding for unbuilt monoforum/custom-sound features (negligible memory) — MINOR, acceptable. VERIFIED in code.


# app_state — AppState settings state management

- ✓ [CLOSED 2026-05-29 — FALSE POSITIVE] `passcodeCanTry()` (`app_state.dart:2860-2874`) escalating lockout (5/10/15/20/25/≥30 s) is an EXACT 1:1 match to AyuGram `passcodeCanTry()` at `settings.h:116-127` (same `switch (cPasscodeBadTries())`: 3→5000 … 7→25000, default 30000). The finding cited `config.h:35 WrongPasscodeTimeout=1500` as ground truth, but that constant is UNUSED dead code (zero .cpp references; real retry logic lives in settings.h). Dart replicates AyuGram ground truth 1:1 — spec-compliant, NO change needed (do not 'fix' to flat 1500 ms; that would BREAK parity).

# chat_state — Pagination & Navigation Constants (VERIFIED CLOSED 2026-05-30)

## Summary
Four numeric constants audited against AyuGram Desktop ground truth: 3 deviated and were fixed (commit 5286351b), 1 was a false positive (already correct). Stage-2 verified all four 1:1 against source; built debug + launched, renders desktop+mobile, no crashes.

---

- ✓ [CLOSED 2026-05-30] [MAJOR] `_kFirstPerPage` 10→20 — byte-exact match to AyuGram `kListFirstPerPage = 20` (`data/data_saved_messages.cpp:33`), first-page count for the saved-dialogs LIST. Used by `getSavedSublists` (the sublist list = `MTPmessages_GetSavedDialogs`), which AyuGram pages via `_offset.id ? kListPerPage : kListFirstPerPage` (`data_saved_messages.cpp:298`). The original 10 matched the file's DEAD `kFirstPerPage` constant (defined, never referenced) — wrong. VERIFIED: source-to-source + builds/launches clean.

- ✓ [CLOSED 2026-05-30] [MAJOR] `_kPerPage` 50→100 — byte-exact match to AyuGram `kListPerPage = 100` (`data/data_saved_messages.cpp:32`), subsequent-page (offset) count for the saved-dialogs LIST. Original 50 matched the DEAD `kPerPage` constant — wrong. VERIFIED: source-to-source + builds/launches clean.

- ✓ [CLOSED 2026-05-30] [MAJOR] `_maxChatOpenHistory` 30→50 — byte-exact match to AyuGram `kMaxChatEntryHistorySize = 50` (`window/window_session_controller.cpp:138`, enforced at cpp:2410). Ctrl+Tab switcher history cap. VERIFIED: source-to-source + builds/launches clean.

- ✓ [CLOSED 2026-05-30 — FALSE POSITIVE, left unchanged] [MAJOR] Message-load `limit = _isFirstLoad ? 30 : 50` is CORRECT. `_loadMessages` (`chat_state.dart:2142`) loads the **main chat history** via `getMessages` → mirrors the real Telegram Desktop loader `history/history_widget.cpp:216-217` (`kMessagesPerPageFirst = 30` / `kMessagesPerPage = 50`, used at cpp:4403,4419,4485-4486,4543,4611,4621) — byte-exact. The checklist mis-cited `ayu/ui/message_history/history_inner.cpp:66-68` (`kMessagesFirstPage=20`/`kMessagesPerPage=30`), which is AyuGram's **message edit-history viewer** (namespace `MessageHistory`, paginating one message's edit revisions, `InnerWidget::requestMore` cpp:725) — wrong reference. Changing 30/50 → 20/30 would BREAK desktop parity. Do NOT "fix" this. VERIFIED 1:1 against both AyuGram files.

## telegram_palette — Colorize exclusion and contrast enforcement bugs

- [ ] [CRITICAL] `stickerPanPremium1` and `stickerPanPremium2` incorrectly excluded from accent colorization — passed without `s()` in `colorize()` but NOT listed in C++ `kColorizeIgnoredKeys` — `telegram_palette.dart:1727-1728` ← `window_themes_embedded.cpp:33-102`

- [ ] [CRITICAL] `historyCallArrowInFg`, `historyCallArrowInFgSelected`, `historyCallArrowMissedInFg`, `historyCallArrowMissedInFgSelected`, `historyCallArrowOutFg`, `historyCallArrowOutFgSelected` incorrectly excluded from colorization — passed without `s()` but NOT in `kColorizeIgnoredKeys` — `telegram_palette.dart:1740-1745` ← `window_themes_embedded.cpp:33-102`

- [ ] [CRITICAL] `historyPeerUserpicFg`, `historyPeerSavedMessagesBg`, `historyPeerArchiveUserpicBg`, `historyPeerSavedMessagesBg2` incorrectly excluded from colorization — NOT in `kColorizeIgnoredKeys` — `telegram_palette.dart:1749-1752` ← `window_themes_embedded.cpp:33-102`

- [ ] [CRITICAL] `settingsIconFg` (white icon shape) incorrectly excluded from colorization — only `settingsIconBg*` variants are in `kColorizeIgnoredKeys`, not `settingsIconFg` — `telegram_palette.dart:1753` ← `window_themes_embedded.cpp:89-96`

- [ ] [CRITICAL] `youtubePlayIconBg`, `youtubePlayIconFg`, `videoPlayIconBg`, `videoPlayIconFg` incorrectly excluded from colorization — NOT in `kColorizeIgnoredKeys` — `telegram_palette.dart:1797-1800` ← `window_themes_embedded.cpp:33-102`

- [ ] [CRITICAL] `mapPointDrop`, `mapPointDot` incorrectly excluded from colorization — NOT in `kColorizeIgnoredKeys` — `telegram_palette.dart:1810-1811` ← `window_themes_embedded.cpp:33-102`

- [ ] [CRITICAL] NightGreen theme missing file icon contrast enforcement — `_enforceContrast(includeFileIcons: windowBg == const Color(0xFF17212B))` enables file icon checking only for Night (windowBg=0xFF17212B); NightGreen also has file icon `keepContrast` pairs in C++ but is skipped because its windowBg (0xFF282E33) ≠ 0xFF17212B — `telegram_palette.dart:1961` ← `window_themes_embedded.cpp:156-167`

- [ ] [MAJOR] Static colorize cache shared across all `TelegramPalette` instances — `_cachedColorizeResult`, `_cachedColorizeBaseHash`, `_cachedColorizeAccentHash`, `_cachedColorizeThreshold` are `static` class variables; if multiple theme instances coexist, one instance's colorize call invalidates another's cache, producing stale results — `telegram_palette.dart:1307-1310` ← `style_palette_colorizer.cpp` (no equivalent; C++ uses per-instance colorizer struct)

# theme_file — Theme file parsing & caching

- [ ] [CRITICAL] `_parseZipTheme` reads background file from ZIP with no byte-size limit — AyuGram enforces `kThemeBackgroundSizeLimit = 4 MB` (`window_theme.h:42`) via `readFileContent(..., kThemeBackgroundSizeLimit)`. A ZIP containing a multi-hundred-MB background.jpg will be loaded entirely into memory before any validation. — `theme_file.dart:331` ← `AyuGramDesktop/Telegram/SourceFiles/window/themes/window_theme.cpp:251` + `window_theme.h:42`

- [ ] [CRITICAL] `accessHash` parsed with `int.tryParse` (signed int64) — Telegram access hashes are `uint64`; values with the high bit set (> 9 223 372 036 854 775 807) will cause `int.tryParse` to return `null`, silently dropping `CloudThemeMeta`. AyuGram uses `toULongLong()` (uint64). — `theme_file.dart:102,218` ← `AyuGramDesktop/Telegram/SourceFiles/window/themes/window_theme_editor.cpp:369`

- [ ] [MAJOR] Corrupted/oversized background is silently ignored instead of being a fatal error — AyuGram's `LoadTheme` returns `false` and refuses the theme when a background file exists but fails pixel-dimension checks. Dart logs a debug print and continues loading the theme without a background, diverging from the spec. — `theme_file.dart:332-337` ← `AyuGramDesktop/Telegram/SourceFiles/window/themes/window_theme.cpp:332-341`

- [ ] [MAJOR] Background file search order depends on ZIP archive order instead of explicit priority — AyuGram tries files in hard-coded order: `background.jpg` → `background.png` → `tiled.jpg` → `tiled.png` (and only sets `tiled=true` before trying tiled files). Dart iterates the archive and takes the first matching entry; a ZIP where `tiled.png` appears before `background.jpg` in the central directory would produce `tiled=true` in Dart and `tiled=false` in AyuGram. — `theme_file.dart:305-318` ← `AyuGramDesktop/Telegram/SourceFiles/window/themes/window_theme.cpp:263-275`

- [ ] [MAJOR] `_readImageDimensions` only recognises JPEG SOF0 (0xC0) and SOF2 (0xC2) markers — SOF1 (extended sequential DCT, 0xC1), SOF3 (lossless, 0xC3), and arithmetic-coded SOF variants (0xC9–0xCB, 0xCD–0xCF) are not handled; valid JPEGs using these variants will fail dimension extraction and be rejected as backgrounds. AyuGram delegates to `QImageReader::size()` which handles all valid JPEG types. — `theme_file.dart:279` ← `AyuGramDesktop/Telegram/SourceFiles/window/themes/window_theme.cpp:326-337`

# theme_name_generator — Color and word list mismatches vs AyuGram

- [ ] [CRITICAL] Color values don't match AyuGram — "Berry" is rgb(142, 68, 173) in Dart but rgb(142, 0, 0) in AyuGram, breaking color-to-name mapping consistency. The color distance algorithm will match different colors to different names on mobile vs desktop. Replace Dart's _colors list with AyuGram's exact kColors values (102 colors from window_themes_generate_name.cpp:16-116). Example: Berry should be 0x8e0000 (bright red), not purple. `theme_name_generator.dart:38-140` ← `AyuGramDesktop/Telegram/SourceFiles/window/themes/window_themes_generate_name.cpp:16-116`

- [ ] [CRITICAL] Adjectives list differs from AyuGram — Dart has ~80 custom adjectives but AyuGram has 108 standard ones. This causes the same color to generate different theme names (e.g., "Ancient Berry" vs "Antique Berry"). Replace _adjectives with exact list from kAdjectives. `theme_name_generator.dart:142-163` ← `AyuGramDesktop/Telegram/SourceFiles/window/themes/window_themes_generate_name.cpp:118-226`

- [ ] [CRITICAL] Nouns list is wrong terminology and doesn't match AyuGram — Dart calls them "_nouns" but AyuGram calls them "kSubjectives". The actual word lists are completely different (Dart has poetic words like "Ambrosia", "Cascade", "Echo" while AyuGram has "Attack", "Avalanche", "Blast", "Burst", "Candy", "Carnival"). Replace _nouns with exact kSubjectives list. `theme_name_generator.dart:165-183` ← `AyuGramDesktop/Telegram/SourceFiles/window/themes/window_themes_generate_name.cpp:228-310`

- [ ] [MAJOR] Function behavior differs from AyuGram — AyuGram uses `ranges::min_element` with a distance comparator (C++ STL), Dart uses a manual for loop. While functionally equivalent, the algorithm should be verified to produce identical distance calculations. The formula is identical but verify boundary conditions. `theme_name_generator.dart:4-30` ← `AyuGramDesktop/Telegram/SourceFiles/window/themes/window_themes_generate_name.cpp:314-351`

**Impact**: Theme names generated on mobile will differ from desktop because:
1. Same accent color gets mapped to different base colors (different color name)
2. Different adjectives/subjectives randomly chosen (different modifiers)
3. Result: user creates a "Antique Bronze" theme on desktop but it would be called "Ancient Berry" on mobile

**Solution**: Replace all three constants (_colors, _adjectives, _nouns) with exact copies from AyuGram's kColors, kAdjectives, and kSubjectives.

# wallpaper — Wallpaper rendering & animation

## Summary
The `wallpaper.dart` file implements chat wallpaper rendering with support for solid colors, gradients, images, and patterns. The implementation includes animated multi-color gradients and pattern overlays. Overall structure is sound, but there are a few issues to verify:

## Findings

- [ ] [MAJOR] Gradient rotation logic may not match AyuGram for complex (3+ color) gradients — `wallpaper.dart:370-389` ← `AyuGram/data/data_wall_paper.cpp:260-263`
  - AyuGram's `gradientRotation()` explicitly returns 0 for complex gradients with the comment "In case of complex gradients rotation value is dynamic"
  - The Dart code animates rotation even for 3+ color gradients, but the base `gradientRotation` parameter should be 0 for these
  - Need to verify: is the animation progress being calculated independently from stored rotation, or does the baseRotation affect 3+ color gradients?

- [ ] [MAJOR] Pattern inversion logic appears correct but relies on luminance calculation — `wallpaper.dart:675-686` ← verify against AyuGram UI utils
  - The code inverts pattern when background is dark (HSV value <= 0.3)
  - This matches typical light/dark pattern switching logic, but exact threshold and algorithm should be verified against AyuGram source

- [ ] [MAJOR] Image encoding constants need verification — `wallpaper.dart:727-730`
  - JPEG quality: 87 (typical)
  - Thumb size: 320px (reasonable)
  - Max wallpaper size: 2960px (verify against Telegram limits)
  - Max aspect ratio: 40:1 (verify against Telegram limits)

- [ ] [MINOR] Average color computation uses sampling strategy (`step = imageBytes.length ~/ 1000`) — `wallpaper.dart:704`
  - Samples every ~1KB of image data for speed
  - Acceptable for average color, but verify this doesn't cause significant color drift on small images

- [ ] [MINOR] Animation respects power-saving mode correctly — `wallpaper.dart:329-334, 528-533`
  - Pauses/resumes animation based on AppState power-saving flag
  - Looks correct, matches expected behavior

## No Critical Issues Found

- No placeholder/stub callbacks ✓
- No hardcoded fake data ✓
- All UI elements are functional (not cosmetic) ✓
- Pattern and gradient rendering logic is implemented ✓
- Animation loop is properly managed ✓
- Lifecycle (initState/dispose) is correctly handled ✓
- shouldRepaint logic is appropriate ✓

# active_sessions_screen — Active Sessions Screen Audit

- [ ] [CRITICAL] Double-write of custom device model: `_showRenameDialog` calls both `engine.setCustomDeviceModel()` AND `appState.customDeviceModel = text`, but `AppState.customDeviceModel` setter already calls `_engine.callGeneric(accountId, 'SetDeviceModel', ...)` internally — this fires two separate engine calls for the same rename, with one going to `SetCustomDeviceModel` and the other to the non-existent `SetDeviceModel` handler — `active_sessions_screen.dart:790-791` ← `app_state.dart:2521`

- [ ] [CRITICAL] `AppState.customDeviceModel` setter calls `_engine.callGeneric(accountId, 'SetDeviceModel', ...)` but `SetDeviceModel` has no handler in `dispatch_engine.go` — only `SetCustomDeviceModel` exists (line 4478) — this means every assignment to `appState.customDeviceModel` sends an unhandled engine call that is silently swallowed — `app_state.dart:2521` ← `go/bridge/dispatch_engine.go:4478`

- [ ] [MAJOR] Auto-terminate section (TTL) is always shown even when there are no other sessions — AyuGram only shows it when `_list->itemsCount() > 0` (`ttlWrap->toggleOn(_list->itemsCount() | rpl::map(_1 > 0))`), but the Dart build method appends `_buildAutoTerminateSection` unconditionally at the end of the sliver list — `active_sessions_screen.dart:913-916` ← `settings_active_sessions.cpp:1030`

- [ ] [MAJOR] Session sorting uses lexicographic string comparison on `last_active` ISO date strings rather than actual `DateTime` comparison — `_recomputeCachedLists` sorts with `bDate.compareTo(aDate)` which is correct for ISO 8601 strings, but the Go struct serializes `last_active` as a `time.Time` JSON value (RFC 3339) — if Go ever emits a non-padded or timezone-varied format, lexicographic sort silently breaks; should parse to `DateTime` before comparing — `active_sessions_screen.dart:226-229,235-238` ← `go/cores/base.go:577`

- [ ] [MAJOR] `_showAutoTerminateDialog` builds its own custom radio-button dialog with a fixed set of options `[7, 30, 90, 180, 365]` and calls `engine.setSessionAutoTerminateDays()` directly on Save — AyuGram opens `SelfDestructionBox` (a generic box) that also calls `_session->api().authorizations().updateTTL(value)` which triggers a reactive `ttlDays` update back into the UI via `rpl::variable` — the Dart dialog has no reactive back-channel: if `setSessionAutoTerminateDays` fails silently, `_autoTerminateDays` stays at the old value with no error shown — `active_sessions_screen.dart:434-449` ← `settings_active_sessions.cpp:1005-1009`, `self_destruction_box.cpp:170-181`

- [ ] [MAJOR] `_showTerminateConfirmation` and `_showTerminateAllConfirmation` use generic `AlertDialog` instead of AyuGram's confirm-box pattern — AyuGram shows a red-accented "Reset" button using `st::attentionBoxButton` with localized `tr::lng_settings_reset_one_sure`/`tr::lng_settings_reset_sure` copy; Dart uses hardcoded English "Terminate Session" / "Are you sure you want to terminate…" which does not match the real Telegram confirmation text — `active_sessions_screen.dart:461-515` ← `settings_active_sessions.cpp:876,891`

- [ ] [MAJOR] After `terminateOne` succeeds, AyuGram removes the session from its local `_data` list and calls `_inner->showData(_data)` immediately without re-fetching from the server — Dart instead calls `_loadSessions()` which fires a full network round-trip to `GetSessions` — this causes the list to flash (re-enters `_loading = true` path would not occur since `_loading` is already false, but there is a visible latency before the row disappears) — `active_sessions_screen.dart:300-307` ← `settings_active_sessions.cpp:853-868`

## admin_tools — Edit Peer Info Box, Permissions, Members, Admin Log, Invite Links

- [ ] [CRITICAL] `joinToSend` / `joinRequest` toggles shown for ALL non-channel groups (`!_isChannel`), but AyuGram only exposes these for megagroups (`_peer->isMegagroup()`). Regular chats (non-supergroup groups) don't support these API flags and sending them will fail or silently no-op. — `admin_tools.dart:547` ← `edit_peer_info_box.cpp:1002-1005`

- [ ] [CRITICAL] Statistics screen implemented as a flat key/value dialog dumping raw JSON (`data.entries.map(...)`) — `admin_tools.dart:1915-1929`. AyuGram navigates to a full `Info::ChannelStatistics` section page with proper charts, growth graphs, and breakdown panels. The current implementation loses all interactive/graphical statistics content. — `admin_tools.dart:1882-1940` ← `edit_peer_info_box.cpp:1729`

- [ ] [CRITICAL] Boosts screen shows as a modal dialog (`showDialog`) — `admin_tools.dart:1942-2015`. AyuGram navigates to a full `Info::Boosts::Make(_peer)` section page with the full boosts widget. The dialog lacks the Boosts section's full feature set (gifting, boosters list, replace boost UI). — `admin_tools.dart:1942` ← `edit_peer_info_box.cpp:1665`

- [ ] [CRITICAL] Verify Accounts dialog loads from `engine.getContacts()` (contact list search) — `admin_tools.dart:1575`. AyuGram only shows the Verify Accounts button when `botInfo->verifierSettings` is set (bot has verifier capabilities), and opens `MakeVerifyPeersBox` which is a dedicated peer-picker UI, not a contacts list. The Dart implementation shows the button unconditionally and uses wrong data source. — `admin_tools.dart:1567-1686` ← `edit_peer_info_box.cpp:2026-2057`

- [ ] [CRITICAL] Group Sticker section shown only for non-channel, non-bot (`!_isChannel && !_isBot`) — `admin_tools.dart:229`. AyuGram shows it only when `canEditStickers` which is `isChannel && channel->canEditStickers()` — meaning it's a CHANNEL feature (megagroups/broadcast), not a regular group feature. The Dart logic is inverted. — `admin_tools.dart:229` ← `edit_peer_info_box.cpp:1467,1679`

- [ ] [MAJOR] Delete peer uses a single `engine.deleteChat()` call for both groups and channels — `admin_tools.dart:2347`. AyuGram's `deleteChannel()` also deletes the migrated-from legacy chat via `session->api().deleteConversation(chat, false)` if `channel->migrateFrom()` is non-null (line 2847-2854). Dart skips this step, leaving orphaned migrated chats. — `admin_tools.dart:2329-2356` ← `edit_peer_info_box.cpp:2843-2865`

- [ ] [MAJOR] Auto-Translation toggle shown unconditionally when `_isChannel` — `admin_tools.dart:569`. AyuGram guards it with `canEditAutoTranslate` which is `isChannel && channel->canEditAutoTranslate()` — a separate capability check beyond just being a channel. Dart shows the toggle for channels where the admin lacks `canEditAutoTranslate` permission. — `admin_tools.dart:569` ← `edit_peer_info_box.cpp:1438-1439,1498`

- [ ] [MAJOR] Sign Messages toggle shown unconditionally when `_isChannel` — `admin_tools.dart:580`. AyuGram guards it with `canEditSignatures` which additionally requires `!channel->isMegagroup()` (signatures are only for broadcast channels, not megagroups). Dart displays the toggle for megagroup channels where it has no effect. — `admin_tools.dart:580` ← `edit_peer_info_box.cpp:1435-1437`

- [ ] [MAJOR] `_showBoostRequiredDialog` shown for auto-translate lock uses hardcoded fallback `minLevel = 3` when `_autoTranslateMinLevel == 0` — `admin_tools.dart:915`. AyuGram reads the required level from `Data::LevelLimits(&channel->session()).channelAutoTranslateLevelMin()` (dynamic from server appConfig). The Dart fallback may be wrong for different server configurations. — `admin_tools.dart:915` ← `edit_peer_info_box.cpp:1221-1222`

- [ ] [MAJOR] `_confirmDelete` does not distinguish between channels and legacy groups — `admin_tools.dart:2329`. AyuGram's `deleteWithConfirmation` asserts `channel != nullptr`, meaning delete is only shown when `canDeleteChannel` is true (`isChannel && channel->canDelete()`). Dart always shows the Delete button regardless of whether the user has delete rights. — `admin_tools.dart:2242-2263` ← `edit_peer_info_box.cpp:1468,1683-1691`

- [ ] [MAJOR] `_toggleAutoTranslate` inverts the semantics of `_autoTranslateDisabled` — `admin_tools.dart:921`. When toggling from disabled→enabled the code sets `newVal = !_autoTranslateDisabled` (true=disabled) which becomes `true`, then calls `togglePeerTranslations(..., true)` (disable=true). The logic is correct if the engine flag means "no_translations=true means disabled", but `newVal` is confusingly named and the toggle inversion on re-call risks double-flip. — `admin_tools.dart:914-934` ← `edit_peer_info_box.cpp:2684-2704`

- [ ] [MAJOR] `_buildAdminControlsSection` always shows Removed Users row — `admin_tools.dart:1767-1780`. AyuGram's `canViewKicked` is `isChannel && (channel->isMegagroup() ? (channel->isBroadcast() || channel->isGigagroup()) : true)`, meaning for megagroups it's false (megagroups that are not broadcast/gigagroup cannot show kicked list). Dart shows it for all channels including megagroups. — `admin_tools.dart:1767` ← `edit_peer_info_box.cpp:1458-1461`

- [ ] [MAJOR] Recent Actions row shown for all channels without admin-rights check — `admin_tools.dart:1796-1809`. AyuGram requires `hasRecentActions = isChannel && (channel->hasAdminRights() || channel->amCreator())`. Dart shows it unconditionally for all channels (including channels where user is just a subscriber). — `admin_tools.dart:1796` ← `edit_peer_info_box.cpp:1462-1463`

- [ ] [MAJOR] `_buildBotManageSection` / `fillBotCurrencyButton` shows Currency Balance unconditionally — `admin_tools.dart:1296-1303`. AyuGram only shows this button if the cached balance is non-empty (hidden by default via `SlideWrap.toggle(!state->balance.current().isEmpty())`). Dart always renders the button, potentially showing a non-functional row for bots with no earnings. — `admin_tools.dart:1296` ← `edit_peer_info_box.cpp:1858-1870`

- [ ] [MAJOR] `_buildBotManageSection` / `fillBotCreditsButton` shows Credits Balance unconditionally — `admin_tools.dart:1304-1311`. Same issue as Currency Balance: AyuGram hides the button until the credits API confirms a non-zero balance. Dart always renders it. — `admin_tools.dart:1304` ← `edit_peer_info_box.cpp:1917-1929`

- [ ] [MAJOR] Affiliate Program for bots shown unconditionally in `_buildBotManageSection` — `admin_tools.dart:1316-1319`. AyuGram guards it with `Info::BotStarRef::Setup::Allowed(_peer)` check at line 1964. Dart shows it for all bots. — `admin_tools.dart:1316` ← `edit_peer_info_box.cpp:1961-1964`

- [ ] [MAJOR] `_showVerifyAccountsDialog` toggles verification via `engine.callGeneric('BotsSetCustomVerification', ...)` with `{'bot_id': widget.chat.chatId, 'peer_id': c.userId}` — `admin_tools.dart:1646-1654`. The `bot_id` field is passed the chat's own `chatId` (the bot peer), but then the `peer_id` is the contact to verify — the semantic mapping is correct, but using `callGeneric` with string-typed MTProto fields rather than a typed engine method risks silent failures. Additionally, the verify button is never guarded by `botInfo.verifierSettings` which is the canonical gate. — `admin_tools.dart:1646` ← `edit_peer_info_box.cpp:2040-2043`

## advanced_settings_screen — Advanced Settings Screen Audit

- [ ] [CRITICAL] "When Closing Window" section visibility is inverted: shown when `showTrayIcon == true` but AyuGram shows it only when tray is DISABLED (`workMode == WindowOnly`), meaning the section appears when it should be hidden and vice versa — `advanced_settings_screen.dart:711` ← `settings_advanced.cpp:357-362`

- [ ] [CRITICAL] Screen reader section visibility is wrong: Dart shows the section whenever `_screenReaderDetected` is true, but AyuGram shows it only when BOTH a screen reader is detected AND `ScreenReaderModeDisabled()` returns true (i.e., the mode is already disabled by user) — section should only appear in that specific state — `advanced_settings_screen.dart:1209` ← `settings_advanced.cpp:1185-1188`

- [ ] [CRITICAL] Screen reader toggle semantics are inverted: Dart has `value: appState.screenReaderOptimized` with label "Screen reader optimization" (on = optimization active), but AyuGram's toggle starts `toggled = rpl::single(disabled)` with label "Disable screen reader mode" — the toggle controls disabling the mode, not enabling it — `advanced_settings_screen.dart:1218-1228` ← `settings_advanced.cpp:1199-1217`

- [ ] [MAJOR] Hardware video acceleration toggle incorrectly shows a restart dialog on every change: `_showRestartDialog` is called unconditionally after toggling, but AyuGram simply saves settings with no restart prompt for this specific toggle — `advanced_settings_screen.dart:902-905` ← `settings_advanced.cpp:855-864`

- [ ] [MAJOR] "When Closing Window" radio button order is wrong: Dart order is `['Quit', 'Close to the taskbar', 'Run in background']` (indices 0,1,2), but AyuGram renders them as RunInBackground first, CloseToTaskbar second, Quit last — `advanced_settings_screen.dart:719` ← `settings_advanced.cpp:391-399`

## auth_screen — Auth screen vs AyuGram intro_* sources

- [ ] [CRITICAL] Email verification step (`EmailStatus::SetupRequired` / `intro_email.cpp`) is entirely absent from `auth_screen.dart`. AyuGram introduces a dedicated `EmailWidget` step when `getData()->emailStatus == EmailStatus::SetupRequired`, collects an email address, calls `MTPaccount_SendVerifyEmailCode`, then navigates to `CodeWidget`. The Dart `AuthStateData` model has no `email` or `emailPatternSetup` field and `_buildStepContent` has no `'email'` branch — the whole flow is dropped. — `auth_screen.dart:563-630` ← `AyuGram/intro/intro_email.cpp:30-145` and `intro/intro_widget.h:66-69`

- [ ] [CRITICAL] Fragment URL code delivery is not handled. AyuGram stores `codeByFragmentUrl` in `Data` (`intro/intro_widget.h:64`) and in `CodeWidget::submit()` opens the URL with `File::OpenUrl` instead of accepting a typed code (`intro/intro_code.cpp:367-373`). The Next button text also changes to `lng_intro_fragment_button`. The Dart model has no `codeByFragmentUrl` field and `_OtpCodeInput` / `_buildInput` never check for it — the Fragment anonymous-number flow is silently broken. — `auth_screen.dart:1002-1202` ← `AyuGram/intro/intro_code.cpp:367-373` and `intro/intro_widget.h:64`

- [ ] [CRITICAL] `toPassword()` in AyuGram shows an inform-box (`lng_signin_cant_email_forgot`) and then calls `showReset()` which re-enables the password field and shows the Reset Account button (`intro/intro_password_check.cpp:325-348`). In Dart, `_handleTryPassword()` shows an `AlertDialog` with OK, then sets `_isRecoveryMode = false` and `_showResetButton = true` (`auth_screen.dart:820-846`). The reset button is shown **immediately after OK** regardless of whether `toPassword()` was triggered by an expired recovery code — but AyuGram calls `showReset()` in both `toPassword()` and `recoverStartFail()`, gating the reset button on the no-recovery path. Dart duplicates the reset-button appearance on every "Can't Access Email?" dismiss. — `auth_screen.dart:820-846` ← `AyuGram/intro/intro_password_check.cpp:325-348`

- [ ] [CRITICAL] `noTelegramCode()` in AyuGram calls `MTPauth_ResendCode` directly and on success updates `callStatus`, `callTimeout`, and `codeByTelegram = false`, then calls `updateDescText()` to switch from Telegram-delivery to SMS/call mode with a live countdown (`intro/intro_code.cpp:440-497`). In Dart, clicking "Didn't get the code?" only shows a dialog with two choices: "Edit Phone Number" (calls `cancelAuth()`) or "Request a Call" (sends `__resend_code`). There is no state update that flips `codeByTelegram = false` or restarts the call countdown — the UI never transitions from Telegram-code-mode to call-countdown-mode as AyuGram does. — `auth_screen.dart:209-250` ← `AyuGram/intro/intro_code.cpp:440-497`

- [ ] [MAJOR] QR login does not handle `loginTokenMigrateTo`: AyuGram's `handleTokenResult` matches `auth_loginTokenMigrateTo` and calls `importTo(dcId, token)` which switches the main DC and calls `MTPauth_ImportLoginToken` (`intro/intro_qr.cpp:443-477`). The Dart QR widget renders the token via `AuthStateData.qrData` decoded from the engine, but the engine side never surfaces a DC-migration event back to the UI and the Dart layer has no import-token path at all. If the server returns a migration response the QR just hangs without completing. — `auth_screen.dart:1002-1108` ← `AyuGram/intro/intro_qr.cpp:443-477`

- [ ] [MAJOR] QR auto-refresh on `updateLoginToken` update is not replicated. AyuGram watches MTProto updates in `QrWidget` and calls `refreshCode()` immediately when an `updateLoginToken` arrives, or sets `_forceRefresh` if a request is in flight (`intro/intro_qr.cpp:248-271`). The Dart engine streams QR data via `AuthStateData.qrData` but there is no push-refresh mechanism — the UI only refreshes when the engine proactively sends a new auth event. If the token expires while no engine event arrives, the QR silently becomes invalid with no visual feedback. — `auth_screen.dart:1020-1031` ← `AyuGram/intro/intro_qr.cpp:248-271`

- [ ] [MAJOR] Call-status timer in `_OtpCodeInputState` transitions to `_calling = true` after countdown but does NOT automatically fire `MTPauth_ResendCode`. In AyuGram `CodeWidget::sendCall()` calls `MTPauth_ResendCode` the moment `_callTimeout` reaches zero and moves to `CallStatus::Calling` / `CallStatus::Called` (`intro/intro_code.cpp:302-338`). Dart sets `_calling = true` and shows a "Resend code" button that must be tapped manually — the automatic call request that AyuGram triggers at countdown-zero is absent. — `auth_screen.dart:1697-1709` ← `AyuGram/intro/intro_code.cpp:302-338`

- [ ] [MAJOR] `_OtpCodeInput` cell width is 40 px but AyuGram's `introCodeDigitHeight` is the height (50 px) and width is calculated as `height * 0.8 = 40 px` with explicit `st::introCodeDigitSkip` (10 px) gap. Dart uses `_cellWidth = 40` and `_cellGap = 10` which matches numerically, but the background fill color is `windowBgOver` (a hover color) in AyuGram (`intro/intro_code_input.cpp:131`) while Dart uses hardcoded dark/light bg colors (`Color(0xFF202B36)` / `Color(0xFFEFEFEF)`) that do not follow the theme palette. — `auth_screen.dart:1928-1930` ← `AyuGram/intro/intro_code_input.cpp:128-132`

- [ ] [MAJOR] `_OtpCodeInput` delete-key behavior diverges: AyuGram clears the current cell first; if it was already empty it goes back one cell and clears that one (`intro/intro_code_input.cpp:272-280`). Dart goes back if current is empty, then deletes — but it triggers an animated reverse on the cleared digit index rather than clearing the previous. The index management differs: AyuGram does `std::clamp(_currentIndex - 1, 0, digits.size())` unconditionally after clear, whereas Dart only decrements if current was empty and then tries to animate-clear. This can leave focus on the wrong cell after delete chains. — `auth_screen.dart:1738-1757` ← `AyuGram/intro/intro_code_input.cpp:272-280`

- [ ] [MAJOR] Signup Terms of Service flow is inverted. AyuGram's `SignupWidget::submit()` calls `acceptTerms()` **before** sending `MTPauth_SignUp` when `termsLock.popup` is set, and ToS acceptance is a prerequisite gated inside `submit()` (`intro/intro_signup.cpp:197-205`). Dart checks `!_termsAccepted` in `_submit()` and shows the terms dialog, but only calls `_submit(authState)` recursively from the Accept button — this means the engine call (`authState.submitInput`) is re-entered from within a dialog callback while the widget tree may have changed. There is also no guard against `_termsAccepted` being reset to `false` if the user navigates away and back. — `auth_screen.dart:175-199` ← `AyuGram/intro/intro_signup.cpp:196-206`

- [ ] [MAJOR] 2FA recovery flow does not match AyuGram's two-state toggle. AyuGram maintains separate password and code fields, toggling visibility between them (`intro/intro_password_check.cpp:292-322`): `toRecover()` hides `_pwdField`, shows `_codeField`, hides `_toRecover`, shows `_toPassword`, then calls `MTPauth_RequestPasswordRecovery` for the email pattern. Dart uses a single `_isRecoveryMode` boolean with one `_recoveryCodeController` but submits the recovery code via `authState.submitInput(code)` which routes through `__request_recovery` only for the *request* step and a bare code for the *submit* step. However the two-step split (first request the recovery, get email pattern back, then submit the code) is collapsed: Dart's `_handleForgotPassword` sends `__request_recovery` and *immediately* flips to recovery mode before the email pattern arrives, so `sentTo` may still be empty when the recovery field renders. — `auth_screen.dart:937-950` ← `AyuGram/intro/intro_password_check.cpp:292-322`

- [ ] [MAJOR] Cover animation plane icon is a generic custom path approximation (`_TelegramPlanePainter`) rather than the actual `st::introQrPlane` sprite used by AyuGram (`intro/intro_qr.cpp:544`). The cover gradient uses Flutter `Icons.chat_bubble_outline_rounded` and `Icons.forum_outlined` as decorations (`auth_screen.dart:1486-1497`) — AyuGram's cover uses specific Telegram illustration assets, not Material icons. This is a >25% visual deviation on the cover/branding area. — `auth_screen.dart:1461-1548` ← `AyuGram/intro/intro_qr.cpp:531-548`

# ayu_appearance_page — Audit

- [ ] [CRITICAL] App icon change not applied live — `_AppIconPickerState.onTap` (line 1089) only calls `widget.onChanged(newIcon)` which persists the setting, but never applies it. AyuGram's `applyIcon()` calls `Window::OverrideApplicationIcon()`, `Core::App().refreshApplicationIcon()`, `Core::App().tray().updateIconCounters()`, and `Core::App().domain().notifyUnreadBadgeChanged()` to reflect the change immediately in the tray, taskbar, and window frame. The Dart version requires a full restart to see any icon change. — `ayu_appearance_page.dart:1089` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/components/icon_picker.cpp:42`

- [ ] [MAJOR] Avatar preview tap silently fails before channel is resolved — `_AvatarCornersPreviewState.onTap` guards with `if (_channelId != null)` (line 506), so tapping during or after a failed `resolveUsername` does nothing. AyuGram's `mouseReleaseEvent` calls `showPeerByLink({.usernameOrId = u"AyuGramReleases"_q})` which resolves the username on-demand and always navigates regardless of prior resolution state. — `ayu_appearance_page.dart:506` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/components/avatar_corners_preview.cpp:98`

# ayu_chats_page — Chats Settings Page

- [ ] [MAJOR] `_BubbleRadiusSlider.onChanged` calls `widget.onChanged(newVal)` on every drag frame (line 520), triggering `AppState.setBubbleRadius → notifyListeners()` per frame and causing a full-page rebuild on every animation frame during drag. `_WideMultiplierSlider` correctly defers to `onChangeEnd` only (line 419). AyuGram's bubble radius slider uses a separate `onChanged` (live preview only, never persists) and `onFinalChanged` (persist + restart prompt) — `ayu_chats_page.dart:517-521` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:255-265`

- [ ] [MAJOR] `_BubbleRadiusSliderState.didUpdateWidget` (line 470-475) resets `_localValue` when `widget.value` changes externally but leaves `_committedValue` stale. After an external reset (e.g. to default 16), if the user then drags to the old committed value, `onChangeEnd`'s guard `if (newVal == _committedValue) return` (line 524) will silently skip the restart prompt and the persist call. `_WideMultiplierSliderState.didUpdateWidget` correctly resets both fields (line 370-372). — `ayu_chats_page.dart:470-475` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:248-270`

- [ ] [MAJOR] `_MessagePreviewStandalone` (line 704) is a static Flutter approximation that renders a manually-drawn bubble. AyuGram's `MessagePreview` (`message_preview.cpp:52-140`) constructs real `HistoryView::Element` items, calls `Ui::SetBubbleRadiusOverride(_state->bubbleRadius)` then `view->draw(p, context)` with a full `ChatStyle`/`ChatTheme` painting context, and draws the share button using `st::historyFastShareIcon` at `st::historyFastShareSize`. The Dart approximates the tail corner radius as `(radiusLarge * 6 / 16).clamp(0.0, 6.0)` (line 734) with no basis in Telegram's actual radius math, and uses `Icons.shortcut` (line 864) instead of the real forward icon. The preview is labelled "Visual approximation only" but does not reflect actual Telegram bubble rendering for the `removeTail` or `bubbleRadius` settings being configured. — `ayu_chats_page.dart:704-912` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/components/message_preview.cpp:142-191`

# ayu_filters_page — Audit Findings

## ayu_filters_page — Filter edit uses Dart RegExp (RE2) instead of ICU regex engine

- [ ] [CRITICAL] Regex validation uses Dart's `RegExp` (RE2 engine) which differs fundamentally from AyuGram's ICU `icu::RegexPattern`. The Dart code warns "Not supported in Go RE2 engine: lookahead, lookbehind, and backreferences are unavailable" but AyuGram Desktop uses ICU which DOES support all of these. The warning is architecturally backward — a filter valid in AyuGram Desktop (ICU) may be rejected by the Dart validator as "unsupported", and vice versa a pattern that passes Dart validation may fail at the engine. The error message on line 1242 referencing "Go RE2 engine" is incorrect since AyuGram uses ICU. — `ayu_filters_page.dart:1231-1251` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/filters/edit_filter.cpp:57-99`

## ayu_filters_page — "Clear All" doesn't call FiltersCacheController::rebuildCache + fireUpdate

- [ ] [MAJOR] In AyuGram, clearing all filters calls `AyuDatabase::deleteAllFilters()`, `AyuDatabase::deleteAllExclusions()`, then `FiltersCacheController::rebuildCache()` and `FiltersCacheController::fireUpdate()` — two separate steps: DB mutation then cache invalidation + UI signal. The Dart implementation calls `appState.filterEngine.clearAll()` then `appState.saveFilterEngine()`. The `clearAll()` correctly calls `rebuildCache()` and `notifyListeners()`, but `saveFilterEngine()` only calls `_saveWindowPrefs()`. There is no equivalent of `fireUpdate()` that would trigger message list re-renders for already-displayed messages — the chat list will not re-check filtered messages after a clear. — `ayu_filters_page.dart:247-249` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_filters.cpp:240-247`

## ayu_filters_page — "Select Chat" type filter is wrong (DMs and channels included, Dart filters them out)

- [ ] [MAJOR] The C++ `fillTopBarMenu` "Select Chat" action opens `ShowChooseRecipientBox` with types `Bot | Group | Broadcast` only — DMs (plain users) are excluded. The Dart `_SelectChatDialog` when `onChatSelected == null` (the per-dialog flow) filters to `ChatType.group || ChatType.channel || ChatType.topic || isBot` — which matches the spec. However, when `onChatSelected != null` (used for the Shadow Ban "Select Chat" dialog at line 802-817), `_filterChats` returns ALL chats without type filtering (line 302: `if (widget.onChatSelected != null) return chats;`). This means the Shadow Ban "Add" dialog can select any chat including channels and topics, but AyuGram's shadow ban only targets users/peers, not broadcast channels. — `ayu_filters_page.dart:301-309` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_filters.cpp:199-215`

## ayu_filters_page — Import "No changes" path doesn't match C++ behavior

- [ ] [MAJOR] In the C++ `importFromJson`, when `HasChanges(changes)` is false, it shows a toast `tr::ayu_FiltersToastFailNoChanges` and returns immediately — no confirmation dialog shown. The Dart `_doImport` at line 1598 shows a `SnackBar('No changes')` but only after the full `previewImport` runs AND a separate `peersToResolve.isEmpty` check. The C++ checks `HasChanges` which also counts `peersToBeResolved` — if there are peers to resolve but no filter changes, C++ still proceeds. The Dart checks `!changes.hasChanges && peersToResolve.isEmpty` at line 1598, meaning if there are only peers to resolve (no filter add/update/remove), it shows "No changes" and returns instead of resolving the peers. This silently drops peer resolution from imports that have only peer hints. — `ayu_filters_page.dart:1598-1603` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_utils.cpp:61-68,411-415`

## ayu_filters_page — Export calls `engine.publishFilters()` which is on `AyuFilterEngine` not `EngineService`

- [ ] [MAJOR] `_doExport` at line 1721 calls `engine.publishFilters(peers: peers)` where `engine` is `appState.filterEngine` (an `AyuFilterEngine` Dart object). The `publishFilters` method in `AyuFilterEngine` performs a raw HTTP multipart POST to `https://dpaste.com/api/v2/` directly from Dart (ayu_filter.dart:466-503). The C++ `FilterUtils::publishFilters()` does the same dpaste POST but also shows a `Ui::Toast::Show(tr::lng_stickers_copied(tr::now))` on success. The Dart version shows `SnackBar('Link copied to clipboard')` at line 1726 only when `result.error == null`, but `publishFilters` returns `(url: pasteUrl, error: null)` — the SnackBar fires correctly. However, the Dart `publishFilters` in `ayu_filter.dart:489` checks `response.statusCode == 201` for success, while dpaste returns `302` (redirect) for a successful paste — the `HttpClient` in Dart follows redirects by default so `statusCode` after `request.close()` is the final redirect target status (200), not 201. This means `pasteUrl` will always be empty and export via URL will always fail. — `ayu_filters_page.dart:1721-1728` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_utils.cpp:344-391`

## ayu_filters_page — Import confirmation dialog uses plain bullet list instead of rich text with entity count links

- [ ] [MAJOR] In C++, `ChangeSummaryText` builds a `TextWithEntities` with styled rich text using pluralized locale strings like `tr::ayu_FiltersSheetNewFilters(lt_count, N)`. The Dart `_showImportConfirmation` at line 1653 builds a plain bullet list of raw English strings. This means: (1) no localization, (2) no rich text formatting that AyuGram's confirm box supports, (3) the summary structure is a manually constructed list instead of the locale-defined format. Additionally the C++ confirmation has `.title = tr::ayu_FiltersSheetTitle()` — the Dart dialog uses hardcoded `'Import filters'` title at line 1680. — `ayu_filters_page.dart:1653-1714` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_utils.cpp:70-138`

## ayu_filters_page — Per-dialog filter row displays avatar+name but not the PeerList-style userpic from Telegram session data

- [ ] [MAJOR] In C++, the per-dialog filter list uses `PerDialogFiltersListController` which extends `PeerListController`. Each row is a `PerDialogFiltersListRow` which calls `getPeerFromDialogId()` to get the real `PeerData*` and uses `PeerListRow::generatePaintUserpicCallback` — i.e., real Telegram profile pictures from the session cache. For unknown peers, it renders a circle with letter "U". The Dart `_ShadowBanRow` at line 1051 resolves names/avatars via `engine.getUserProfile()` and `engine.downloadSingleAvatar()` — but this is an async network call on every render, not a session cache lookup. For the per-dialog filter section (lines 82-107), `_NavigationButton` shows just text with no avatar at all. AyuGram shows full peer userpics in the per-dialog list. — `ayu_filters_page.dart:82-107` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/filters/per_dialog_filter.cpp:43-58`

## ayu_filters_page — Toggle filter enable/disable uses wrong AyuDatabase path (no DB persistence)

- [ ] [CRITICAL] In AyuGram C++, toggling a filter's enabled state at `settings_filters_list.cpp:119-124` calls `AyuDatabase::updateRegexFilter(*state)` then `FiltersCacheController::rebuildCache()` and `FiltersCacheController::fireUpdate()` — the state is persisted to SQLite immediately. In the Dart implementation, `onToggleEnabled` at line 683-686 calls `engine.updateFilter(f.copyWith(enabled: !f.enabled))` then `appState.saveFilterEngine()`. `saveFilterEngine()` only calls `_saveWindowPrefs()` which persists to a JSON prefs file, not to a proper database. There is no Go bridge call to persist the filter toggle to the engine — the in-memory state is saved to prefs JSON but the Go engine (which actually runs filters) is never notified of the change. The Go engine's filter state is only loaded at app start, so toggling a filter in the Dart UI has no effect on the running Go filter engine. — `ayu_filters_page.dart:683-686` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/filters/settings_filters_list.cpp:115-127`

## ayu_filters_page — Adding a new filter shows SnackBar with "Restrict" action, but the restrict action calls `engine.updateFilter` without persisting via Go bridge

- [ ] [CRITICAL] When a new shared filter is added from a per-dialog context (lines 1298-1314), the Dart code shows a SnackBar with a "Restrict" action that calls `engine.updateFilter(updated)` and `appState.saveFilterEngine()`. As with the toggle issue above, this only updates the Dart in-memory `AyuFilterEngine` and saves prefs JSON — it never calls a Go bridge method to update the filter in the Go engine. In AyuGram C++, `RegexEditBox` calls `AyuDatabase::addRegexFilter(newFilter)` (line 213 in edit_filter.cpp) which writes to the actual SQLite database that the Go engine reads. The Dart bridge has no equivalent `AddRegexFilter` bridge call being invoked. — `ayu_filters_page.dart:1291-1314` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/filters/edit_filter.cpp:210-245`

## ayu_filters_page — `hasPerDialogFilters()` only checks per-dialog filters but not exclusions; per-dialog section omits dialogs that have ONLY exclusions

- [ ] [MAJOR] In C++, `PerDialogFiltersListController::prepare()` builds the per-dialog list from both `getAllRegexFilters()` (counting `filter.dialogId` entries) AND `getAllFiltersExclusions()` (counting `exclusion.dialogId` entries). A dialog with only exclusions (no per-dialog filters) still appears in the list. In the Dart implementation, `hasPerDialogFilters()` at `ayu_filter.dart:333` only checks `_filters.any((f) => !f.isShared)` — if a dialog has only exclusions but no per-dialog filters, `hasPerDialogFilters()` returns false and the entire "Per-Dialog Filters" section is hidden. The `dialogIdsWithFilters()` at line 335 also only covers `_filters` not `_exclusions`. — `ayu_filters_page.dart:75,81` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/filters/per_dialog_filter.cpp:86-125`

# ayu_general_page — Property name mismatches with AyuGram Desktop

- [ ] [MAJOR] Property name `hideSimilarChannelsTab` doesn't match AyuGram's `hideSimilarChannels()` — `ayu_general_page.dart:78` ← `AyuGramDesktop/ayu/ayu_settings.h:283` (method exists as `hideSimilarChannels()`, NOT `hideSimilarChannelsTab()`)
- [ ] [MAJOR] Property name `increaseContentHeight` should be `increaseWebviewHeight` to match AyuGram — `ayu_general_page.dart:158` ← `AyuGramDesktop/ayu/ayu_settings.h:288` (C++ uses `increaseWebviewHeight()`)
- [ ] [MAJOR] Property name `increaseContentWidth` should be `increaseWebviewWidth` to match AyuGram — `ayu_general_page.dart:163` ← `AyuGramDesktop/ayu/ayu_settings.h:289` (C++ uses `increaseWebviewWidth()`)
- [ ] [MAJOR] Property name `confirmStickers` should be `stickerConfirmation` to match AyuGram — `ayu_general_page.dart:176` ← `AyuGramDesktop/ayu/ayu_settings.h:344` (C++ uses `stickerConfirmation()`)
- [ ] [MAJOR] Property name `confirmGifs` should be `gifConfirmation` to match AyuGram — `ayu_general_page.dart:183` ← `AyuGramDesktop/ayu/ayu_settings.h:345` (C++ uses `gifConfirmation()`)
- [ ] [MAJOR] Property name `confirmVoiceMessages` should be `voiceConfirmation` to match AyuGram — `ayu_general_page.dart:190` ← `AyuGramDesktop/ayu/ayu_settings.h:346` (C++ uses `voiceConfirmation()`)

**Summary:** All UI callbacks and state properties use Dart-specific naming conventions instead of matching AyuGram Desktop's method names. These properties are defined in `app_state.dart` and loaded/saved via the window prefs file, but the naming convention diverges from the C++ reference implementation documented in `ayu_settings.h` (lines 283, 288-289, 344-346).

**Note:** The UI is fully functional and not a placeholder; however, if these settings are intended to maintain compatibility with AyuGram Desktop's naming convention (as suggested by the comment "§54.14: AyuGram General settings" in app_state.dart:3435), the property names should be aligned.

# ayugram_settings_screen — Layout and visual accuracy issues

- [ ] [MAJOR] `_FlatCategoryButton` text starts at 79px instead of AyuGram's 60px — outer padding is `fromLTRB(22,10,22,10)` plus a `SizedBox(width:57)` totals 79px for text start; AyuGram `settingsButton` has `padding: margins(60px, 10px, 22px, 10px)` with `iconLeft: 20px` — `ayugram_settings_screen.dart:312-318` ← `AyuGram/SourceFiles/settings/settings.style:13-16`

- [ ] [MAJOR] `_FlatCategoryButton` icon mispositioned — icon is centered inside a 57px SizedBox starting at 22px left, putting it at ~50px centre; AyuGram uses `iconLeft: 20px` (icon left-edge at 20px, 24px wide, centre ~32px) — `ayugram_settings_screen.dart:316-319` ← `AyuGram/SourceFiles/settings/settings.style:16`

- [ ] [MAJOR] Section header labels ("Categories", "Links") use `FontWeight.w500` (medium) instead of semibold — AyuGram `defaultSubsectionTitle` uses `font(boxFontSize semibold)` = 14px w600 — `ayugram_settings_screen.dart:129` ← `AyuGram/Telegram/lib_ui/ui/layers/layers.style:149-151`

- [ ] [MAJOR] Section header bottom padding 6px instead of 9px — Dart uses `EdgeInsets.fromLTRB(22, 0, 22, 6)`; AyuGram `defaultSubsectionTitlePadding: margins(22px, 7px, 10px, 9px)` has 9px bottom — `ayugram_settings_screen.dart:126` ← `AyuGram/Telegram/lib_ui/ui/layers/layers.style:155`

- [ ] [MAJOR] Wrong icons on three category buttons — General uses `Icons.photo_library_outlined` (should be `menuIconShowAll` = `menu/all_media`), AyuGram category uses `Icons.emoji_emotions_outlined` (should be `menuIconGroupReactions` = `menu/group_reactions`), Other uses `Icons.star_border` (should be `menuIconFave` = `menu/favorite`) — `ayugram_settings_screen.dart:135,147,165` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_main.cpp:106,114,128`

# ayu_other_page — Audit Findings

- [ ] [CRITICAL] RC config fetched only once on dialog open (static `_rcFetched` flag), never refreshed — C++ `RCManager::start()` fetches at app launch and every hour via `_timer->start(60 * 60 * 1000)`; donate amounts/username stay stale for the entire session after first open — `ayu_other_page.dart:472-489` ← `AyuGram/ayu/utils/rc_manager.cpp:33-42`

- [ ] [CRITICAL] QR code size hardcoded to 180px — C++ dynamically sizes to fill box width: `qrMaxSize = int(st::aboutWidth * 1.25) - boxRowPadding` (≈400px); a 180px QR is significantly harder to scan — `ayu_other_page.dart:784` ← `AyuGram/ayu/ui/boxes/donate_qr_box.cpp:94-111`

- [ ] [MAJOR] `_DonateInfoBox` missing top-right close X button — C++ calls `box->addTopButton(st::boxTitleClose, [=] { box->closeBox(); })`, giving both a title-bar X and a bottom Close button; Dart only has the bottom Close button — `ayu_other_page.dart:587-676` ← `AyuGram/ayu/ui/boxes/donate_info_box.cpp:137`

- [ ] [MAJOR] `_DonateQrBox` has a redundant `GestureDetector` on the address container that copies to clipboard with "Address copied" snackbar — C++ has no such tap target, only the `InviteLinkLabel` widget and a single copy button that shows `Ui::Toast::Show(tr::lng_text_copied)`; the two copy paths in Dart show different messages ("Address copied" vs "Address copied to clipboard"), creating inconsistent feedback — `ayu_other_page.dart:813-848` vs `ayu_other_page.dart:852-862` ← `AyuGram/ayu/ui/boxes/donate_qr_box.cpp:142-158`

- [ ] [MAJOR] QR center icon uses fixed 36×36 container regardless of QR size — C++ uses `kCenterRatio = 0.20`, making the overlay logo scale proportionally with the QR image; Dart's fixed size looks oversized at 180px QR — `ayu_other_page.dart:794-808` ← `AyuGram/ayu/ui/boxes/donate_qr_box.cpp:54-65`

# ayu_section_builder — Audit Findings

## ayu_section_builder — Beta badge text color uses hardcoded white instead of windowFgActive

- [ ] [MAJOR] `_AyuSettingToggle` inline beta badge uses `color: Colors.white` but C++ uses `textFg: windowFgActive` (which is theme-dependent, not always white) — `ayu_section_builder.dart:343` ← `AyuGram/SourceFiles/settings/settings.style:148`

- [ ] [MAJOR] `_BetaBadgeOverlay` also uses `color: Colors.white` for badge text instead of theme `windowFgActive` — `ayu_section_builder.dart:270` ← `AyuGram/SourceFiles/settings/settings.style:148`

## ayu_section_builder — Beta badge rounding radius is wrong

- [ ] [MAJOR] `_BetaBadgeOverlay` uses `BorderRadius.circular(4)` as rounding. C++ computes the radius as `st::ayuBetaBadgePadding.left()` = 4px applied via `drawRoundedRect`. The Dart's circular-4 result matches numerically, but `_AyuSettingToggle`'s inline badge also uses `BorderRadius.circular(4)` — matches. No deviation here (informational; both are 4px).

## ayu_section_builder — Beta badge position computation is wrong in _BetaBadgeOverlay

- [ ] [CRITICAL] `_BetaBadgeOverlay._updateOffset()` computes badge left offset as `22 + textPainter.width + 4` (a fixed 22px left margin + measured text width + 4px gap). The C++ `AddBetaBadge` positions the badge using `st.padding.left() + parent->fullTextWidth() + st::settingsPremiumNewBadgePosition.x()`, where `settingsPremiumNewBadgePosition.x() = 4px` and `st.padding.left() = 22px` for `settingsButtonNoIcon`. The Dart's 22px constant is correct only for no-icon toggles; when an icon is present (`settingsButton` has `padding: margins(60px, …)`), the left padding should be 60px, not 22px. The `_AyuSettingToggle` with `icon != null` shifts content by 14px SizedBox + 20px icon, but the badge is placed inline in the Row so it is actually correctly positioned by the Row flow — however `_BetaBadgeOverlay` (used by `addBetaBadge`) always uses 22px which breaks when called on a toggle that has an icon — `ayu_section_builder.dart:236` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_ayu_utils.cpp:69-74`

## ayu_section_builder — addSectionDivider produces a visible divider line; C++ produces skip+divider+skip

- [ ] [MAJOR] Dart `addSectionDivider()` renders a `Container(height:1)` between two `SizedBox(height:6)` — a thin 1px rule. C++ `addSectionDivider()` calls `_builder.addSkip()` + `_builder.addDivider()` + `_builder.addSkip()`, where `AddDivider` produces a full-bleed background-colored region (not a 1px line), styled as a section separator block. The Dart's 1px colored line is a different visual than TDesktop's divider widget — `ayu_section_builder.dart:131-138` ← `AyuGram/SourceFiles/ayu/ui/settings/ayu_builder.cpp:263-267`

## ayu_section_builder — addSubsectionTitle font size is wrong

- [ ] [MAJOR] Dart `addSubsectionTitle` renders at `fontSize: 13`. C++ uses `defaultSubsectionTitle` which is `font: font(boxFontSize semibold)` = 14px semibold — `ayu_section_builder.dart:37` ← `AyuGram/SourceFiles/../lib_ui/ui/layers/layers.style:148-154`

## ayu_section_builder — addSubsectionTitle padding is wrong

- [ ] [MAJOR] Dart `addSubsectionTitle` uses `EdgeInsets.fromLTRB(22, 7, 10, 9)` which happens to match `defaultSubsectionTitlePadding: margins(22px, 7px, 10px, 9px)`. No deviation. (Informational — correct.)

## ayu_section_builder — addSectionTitle has no equivalent in AyuGram C++ builder

- [ ] [MAJOR] `addSectionTitle()` is invented in the Dart layer. The C++ `AyuSectionBuilder` has no `addSectionTitle` method — sections use `addSubsectionTitle` (via `SectionBuilder::addSubsectionTitle`) for all category headers. The Dart invents a separate larger title at `fontSize:15 w600` that has no counterpart in AyuGram source — `ayu_section_builder.dart:23-30` ← `AyuGram/SourceFiles/ayu/ui/settings/ayu_builder.h:1-92` (method absent)

## ayu_section_builder — addDescription uses wrong padding and font vs C++ DividerText

- [ ] [MAJOR] `addDescription` renders at `fontSize:12` with `padding: symmetric(horizontal:22, vertical:4)`. C++ uses `addDividerText` which calls `AddDividerText` → `defaultBoxDividerLabelPadding: margins(22px, 8px, 22px, 16px)` with `defaultTextStyle` font (14px). The Dart `addDescription` is 12px with 4px vertical padding, which is both the wrong font size and wrong padding compared to the C++ divider text widget — `ayu_section_builder.dart:144-150` ← `AyuGram/SourceFiles/../lib_ui/ui/widgets/widgets.style:693-699`

## ayu_section_builder — addDividerText uses wrong layout (no DividerLabel bar, wrong font, wrong padding)

- [ ] [MAJOR] Dart `addDividerText` renders a plain 1px `Container` divider line followed by a 12px text label at `fromLTRB(22, 7, 22, 0)`. C++ `addDividerText` calls `Ui::AddDividerText` which wraps content in a `DividerLabel` widget that includes a background bar region above the text (`defaultDividerBar`) and applies `defaultBoxDividerLabelPadding: margins(22px, 8px, 22px, 16px)`. The Dart version is missing the divider bar widget, uses wrong font size (12px vs 14px via defaultTextStyle), and wrong vertical padding — `ayu_section_builder.dart:152-164` ← `AyuGram/SourceFiles/ui/vertical_list.cpp:50-67`

## ayu_section_builder — Slider missing showTitle=false variant

- [ ] [MAJOR] C++ `SliderArgs` has a `showTitle` boolean (line 74 of ayu_builder.h) — when `showTitle=false` the title row is skipped and the label width hint changes. Dart `_AyuSlider` always renders the title row and has no way to suppress it, making the `showTitle=false` slider variant impossible — `ayu_section_builder.dart:420-475` ← `AyuGram/SourceFiles/ayu/ui/settings/ayu_builder.cpp:193-206`

## ayu_section_builder — _AyuCollapsibleToggle expand arrow uses wrong icon

- [ ] [MAJOR] Dart uses `Icons.expand_more` (Material Design chevron) for the collapse arrow. C++ uses `st::permissionsExpandIcon` which is `icon{{ "info/edit/expand_arrow_small", windowBoldFg }}` — a Telegram-specific SVG icon, not Material icons — `ayu_section_builder.dart:740-748` ← `AyuGram/SourceFiles/info/info.style:1314`

## ayu_section_builder — Collapsible section animates with AnimatedSize but C++ uses SlideWrap with easeOutCubic

- [ ] [MAJOR] Dart `_AyuCollapsibleToggle` uses `AnimatedSize(duration: 150ms, curve: Curves.easeOutCubic)` to expand/collapse. C++ uses `Ui::SlideWrap` which animates opacity+height via `wrap->ease = anim::easeOutCubic` and `st::slideWrapDuration` (150ms). The duration and easing match, but `AnimatedSize` only animates height — it does not fade content in/out as `SlideWrap` does. The C++ collapse also sets `wrap->hide(anim::type::instant)` initially (collapsed by default), while the Dart uses `isExpanded` passed in — `ayu_section_builder.dart:752-770` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_ayu_utils.cpp:286-301`

## ayu_section_builder — Collapsible toggle header layout differs from C++ (wrong separator width)

- [ ] [MAJOR] Dart separator between label area and toggle is `Container(width:1, height:18)`. C++ separator is computed from `st.toggle.border` and `st.toggle.diameter` of the `powerSavingButtonNoIcon` toggle style, and is rendered with `textBgOver` color fill. The Dart hardcodes 18px height and uses `dividerColor` instead of the toggle-hover background color — `ayu_section_builder.dart:703-708` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_ayu_utils.cpp:162-187`

## ayu_section_builder — Collapsible toggle master toggle click area width is hardcoded at 70px

- [ ] [MAJOR] Dart uses `SizedBox(width:70)` for the toggle button area. C++ uses `st::rightsButtonToggleWidth = 70px` — width matches, but in C++ the toggle button is a `SettingsButton` child that is repositioned to align flush-right with the parent button's right edge. The Dart `GestureDetector` is inline in a Row, so it does not align to the right edge when the label is short — `ayu_section_builder.dart:718-730` ← `AyuGram/SourceFiles/boxes/boxes.style:587` and `AyuGram/SourceFiles/ayu/ui/settings/settings_ayu_utils.cpp:175-188`

## ayu_section_builder — _NestedCheckbox indent is wrong (57px vs C++ 57px via powerSavingButton.padding)

- [ ] [MAJOR] Dart `_NestedCheckbox` uses `left: 57` indent. C++ uses `st::powerSavingButton.padding` which is `margins(57px, 8px, 22px, 8px)`. Left indent matches (57px). Vertical padding in C++ is 8px top/bottom from `powerSavingButton.padding`; Dart uses `top:8, bottom:8` — matches. No deviation (informational — correct).

## ayu_section_builder — _NestedCheckbox Shift+click uses HardwareKeyboard.instance (not flutter-idiomatic)

- [ ] [MAJOR] Dart implements Shift+click lock toggling via `HardwareKeyboard.instance.isShiftPressed` checked inside `onTap`. This is a direct HardwareKeyboard poll, which does not work on mobile (touch) platforms and is fragile. C++ checks `button->clickModifiers() & Qt::ShiftModifier` in the ripple button's click callback, which is provided by the platform event. On mobile, this feature simply never activates in the Dart implementation — `ayu_section_builder.dart:803` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_ayu_utils.cpp:383-385`

## ayu_section_builder — _TgCheckboxPainter check mark geometry differs from Telegram's checkbox

- [ ] [MAJOR] Dart `_TgCheckboxPainter` draws a checkmark at relative coords `(0.25,0.5)→(0.42,0.67)→(0.75,0.33)`. C++ uses `Ui::Checkbox` with `st::settingsCheckbox` which renders via `Ui::CheckView` — the actual checkmark is drawn by the TDesktop check animation system with specific pixel geometry, not these relative proportions. The Dart proportions are approximate — `ayu_section_builder.dart:890-894` ← `AyuGram/SourceFiles/settings/settings.style:160-162`

## ayu_section_builder — ayuSettingsScaffold AppBar title font is wrong

- [ ] [MAJOR] `ayuSettingsScaffold` uses `fontSize:17, FontWeight.w600` for the AppBar title. TDesktop settings panel titles use the `boxTitle` style which is `boxFontSize` (14px) semibold in a fixed-height title bar, not a Flutter `AppBar` at all. The entire `AppBar` pattern is not present in TDesktop — settings open as inline sections inside the main window's settings panel, not as separate push-navigation screens with back arrows — `ayu_section_builder.dart:928-930` ← `AyuGram/SourceFiles/settings/settings.style:13-17` (settings panel layout, no AppBar)

# bridge_web — Web WASM Bridge Implementation Audit

## CRITICAL ISSUES

- [ ] **[CRITICAL] Function name mismatch: Dart imports `bridgeCall` but Go exports `BridgeCallWithLen`** — `bridge_web.dart:14-15` ← `go/cmd/bridge/main.go:27` + `scripts/build_go.sh:57`
  - Go exports: `BridgeCallWithLen` (FFI-style with pointer/length params)
  - JavaScript names via `wasm_exec.js`: `bridgeCallWithLen` (lowercase camelCase)
  - Dart imports: `bridgeCall` (wrong name, will be undefined at runtime)
  - Result: When Dart calls `_jsBridgeCall()`, JavaScript will throw "bridgeCall is not defined"

- [ ] **[CRITICAL] Function signature incompatibility: FFI pointer/length API not compatible with JavaScript/WASM** — `bridge_web.dart:36-44` ← `go/cmd/bridge/main.go:28-37`
  - Go function expects: `BridgeCallWithLen(data *C.uint8_t, dataLen C.int32_t, outLen *C.int32_t) *C.uint8_t`
  - Dart calls it with: `_jsBridgeCall(JSUint8Array data)` (single parameter)
  - WASM has no raw pointers—this calling convention doesn't work in JavaScript
  - Even with correct name, this would fail or return garbage data
  - **Fix needed**: Either (1) create WASM-friendly wrapper functions in Go that handle memory marshaling, or (2) create a JavaScript wrapper in `index.html` that bridges between the JavaScript API and Go's FFI API

- [ ] **[CRITICAL] Event callback parameter mismatch** — `bridge_web.dart:32` ← `go/cmd/bridge/main.go:53`
  - Go `BridgeSetEventCallback` expects: `cb C.event_callback_t` (C callback function pointer)
  - Dart passes: `_onEventFromGo.toJS` (converted to JSFunction)
  - The Go side will receive this and try to invoke it as a C function pointer (via `C.invoke_event_callback`)
  - This is **not a valid C callback** in the WASM context—the parameter types are incompatible

## Status

**The web bridge is non-functional.** The WASM module loads but all calls will fail because:
1. Function names don't match (bridgeCall ≠ bridgeCallWithLen)
2. Function signatures are incompatible with JavaScript semantics
3. Memory marshaling between JS and WASM is not implemented

**Root cause:** The bridge was designed for native FFI (Linux/Windows/macOS using C pointers) but the same code is being used for WASM without adaptation. WASM requires different APIs.

## Required Fixes

1. **Create WASM-compatible Go exports** — Add wrapper functions in `go/cmd/bridge/` that:
   - Export `bridgeCall(data []byte) []byte` or similar (not pointer-based)
   - Handle all memory marshaling internally
   - Make these available to JavaScript with the correct names

2. **Or create a JavaScript wrapper** — In `dart/web/index.html` or a separate `.js` file:
   - Define `window.bridgeCall` and `window.bridgeSetEventCallback`
   - These wrap the Go `bridgeCallWithLen` with proper pointer/memory handling
   - Convert between JavaScript Uint8Array and WASM linear memory

3. **Test the web build** — Build `go build -o cores.wasm` and verify:
   - `bridgeCall` and `bridgeSetEventCallback` are callable from JavaScript console
   - They return the expected types
   - Memory marshaling works correctly


# call_panel — Backend Wiring, Animation, and Device API Issues

- [ ] [MAJOR] `engine.setCallAudioDevice` called without `await` on all three device-selection paths — errors silently swallowed — `call_panel.dart:526,572,575` ← `calls/calls_panel.cpp:1065-1077` (AyuGram saves device synchronously via `Core::App().settings().set*DeviceId`)

- [ ] [MAJOR] Camera/video device enumeration calls `getAudioDevices(accountId, 'camera')` — camera is `Webrtc::DeviceType::Camera` (a VIDEO device), not an audio device — conflates two orthogonal device classes — `call_panel.dart:194` ← `calls/calls_panel.cpp:1046` (`DeviceType::Camera` passed separately from `DeviceType::Playback`/`DeviceType::Capture`)

- [ ] [MAJOR] "Add People" button always shown in active state with no `_conferenceSupported` guard; AyuGram gates visibility on server-capability flag — if backend doesn't support conference calls tapping the button fires `engine.createConferenceCall()` which will fail silently — `call_panel.dart:981-985` ← `calls/calls_panel.cpp:1425` (`toggleButton(_addPeople, !isWaitingUser && _conferenceSupported)`)

- [ ] [MAJOR] Incoming-call ripple ring (`_RippleRingPainter`) never actually animates — `rippleController` (2 000 ms repeating) is passed to `AnimatedBuilder` but its `.value` is never read by the painter; `shouldRepaint` returns false every frame because `soundPeakValue` only changes at 100 ms intervals, so the ring renders as a static glow, not the expanding pulse seen in AyuGram — `call_panel.dart:1430-1494` ← `calls/calls_panel.cpp:465-473` (`setOuterValue` called on `CallButton` which drives a proper expanding outer-ring animation)

- [ ] [MAJOR] `_rippleController` (2 000 ms, repeating) drives `AnimatedBuilder` at 60 fps but produces zero visual change between sound-peak polls — causes unnecessary 60 fps Dart build cycles for what needs only ~10 fps (100 ms poll rate); `rippleController` should be removed or replaced with the sound-peak timer as the rebuild trigger — `call_panel.dart:137,164-167,1430-1439` ← `calls/calls_panel.cpp:465` (AyuGram only redraws on `kSoundSampleMs` timer, not a continuous animation loop)

## call_screen — GroupCallPanel / MinimisedCallBar / ScreenShare audit

- [ ] [CRITICAL] `_subscribeToCallState()` listener only updates `_isRecording` and `_participantSpeaking`; it never propagates participant list changes, mute-state changes (`isForceMuted`, `isSelfMuted`), `isCanManage`, `scheduleDate`, or `participantsCount` back into the widget — all those require a full widget rebuild via `setSbState`, which `_callStateSub` inside `_GroupCallPanelState` cannot reach — `call_screen.dart:233-259` ← `calls/group/calls_group_panel.cpp:663-675` (AyuGram subscribes `_call->real()`, `_call->levelUpdates()`, `_call->stateValue()` as reactive streams that drive every rebuild)

- [ ] [CRITICAL] Participant rows are never re-sorted when speaking state changes. AyuGram uses a full comparator that places speaking participants at top, raised-hand participants (by `raisedHandRating`) next, force-muted at bottom, and everything else in between — `call_screen.dart:748-767` (`_buildParticipantsList` just renders `widget.info.participants` as-is) ← `calls/group/calls_group_members.cpp:775-808` (full sort order with `kTop`, raised hand rating, and `_canManage` branch)

- [ ] [CRITICAL] Participant state machine is simplified to a binary `isSpeaking` flag. AyuGram tracks six states: `Active`, `Inactive`, `Muted`, `RaisedHand`, `Calling`, `Invited`, each with distinct icon and sort priority, plus `canSelfUnmute` and `raisedHandRating` for ordering — `call_screen.dart:459-471` (only `isMuted` icon + `isSpeaking` icon + `hasVideo` icon) ← `calls/group/calls_group_members_row.cpp:165-193` (`updateState()` branches on `participant.muted`, `participant.canSelfUnmute`, `participant.raisedHandRating`)

- [ ] [CRITICAL] Speaking threshold is `0.01` in Dart but AyuGram's authoritative threshold is `kSpeakLevelThreshold = 0.2` — a level between 0.01 and 0.2 would show a participant as "speaking" in the Dart UI but not in AyuGram — `call_screen.dart:224` (`entry.value > 0.01`) ← `calls/group/calls_group_call.h:420` (`kSpeakLevelThreshold = 0.2`) and `calls/group/calls_group_members_row.cpp:325`

- [ ] [CRITICAL] Row blob animation ignores `kBlobScale = 0.605` and `kMinorBlobFactor = 0.9`. AyuGram's minor blob minRadius = `groupCallRowBlobMinRadius * 0.9 = 24.3px` and minScale = `0.605 * 0.9 = 0.5445`; Dart uses flat radii of 27/29 with no scale factor — `call_screen.dart:1023-1026` (`_minRadius = 27.0`, `_minorBlobRadius = 27.0`, no `minScale`) ← `calls/group/calls_group_members_row.cpp:44-61` (`.minScale = kBlobScale * kMinorBlobFactor`, `.minRadius = st::groupCallRowBlobMinRadius * kMinorBlobFactor`)

- [ ] [CRITICAL] Row blob levelDuration is wrong. AyuGram uses `kLevelDuration = 100 + 500 * 0.23 = 215ms` (matching the constant). Dart hardcodes `_levelDuration = Duration(milliseconds: 215)` but the blob advance rate (`_radii[i] += (target - r) * 0.12`) is computed per-tick not per-215ms interval, making the smoothing respond far faster than AyuGram — `call_screen.dart:1030` vs `calls/group/calls_group_members_row.cpp:30`

- [ ] [CRITICAL] Participant menu is missing the "Raise hand lower" (admin: lower another participant's raised hand) action that AyuGram exposes per participant for call admins — `call_screen.dart:481-502` (only mute/unmute/volume/kick items) ← `calls/group/calls_group_members_row.cpp` (Row delegates expose raisedHandRating and separate action set)

- [ ] [CRITICAL] Wide mode hides controls permanently — there is no `kHideControlsTimeout = 5s` auto-hide timer for wide/RTMP mode. AyuGram shows controls in wide mode and hides them 5 seconds after the last mouse movement via `_hideControlsTimer` — `call_screen.dart:829-886` (`_buildWideMode` always renders `_buildBottomControls(wide: true)` unconditionally) ← `calls/group/calls_group_panel.cpp:85` (`kHideControlsTimeout = 5 * crl::time(1000)`) and `calls/group/calls_group_panel.cpp:1270-1278` (`toggleWideControls`)

- [ ] [CRITICAL] Push-to-talk (Space key) is gated on `widget.isRtmp` but AyuGram gates it on `_call->rtmp()`. For a regular voice chat that is not RTMP, Space should NOT trigger PTT — but the Dart handler at line 275 and the `showGroupCallPanel` keyboard handler at line 1762 both check `info.isRtmp`, which is correct. However, `_handleKeyEvent` in `_GroupCallPanelState` also blocks on `!widget.isRtmp` at line 275 meaning non-RTMP group calls never get PTT through this code path, but AyuGram confirms this is intentional. [Reverify: this matches AyuGram `calls/group/calls_group_panel.cpp:402` — only `_call->rtmp()` calls get Space PTT.] Confirmed correct, no issue.

- [ ] [MAJOR] Mute button in scheduled mode ignores `_call->rtmp()` toggle-fullscreen path. AyuGram's mute button click for RTMP calls calls `toggleFullScreen()` instead of muting — `call_screen.dart:1816-1879` (the `onToggleMute` callback in `showGroupCallPanel` never calls `toggleFullScreen`) ← `calls/group/calls_group_panel.cpp:584-589` (`} else if (_call->rtmp()) { toggleFullScreen(); return; }`)

- [ ] [MAJOR] Recording dot animation uses `opacity: 0.6 + 0.4 * value` (range 0.6–1.0) but AyuGram animates between `kRecordingOpacity = 0.6` and `1.0` (opaque), which matches. However, the dot size is 6×6px while AyuGram uses `st::groupCallRecordingMark = 6px` plus `skip = 4px` giving a total clickable target of 14×14px with a click callback that shows a toast — the Dart dot has no click handler — `call_screen.dart:1285-1295` ← `calls/group/calls_group_panel.cpp:1307-1341` (`_recordingMark->setClickedCallback`)

- [ ] [MAJOR] `_callStateSub` in `_GroupCallPanelState` fires `setState()` for speaking updates, but `isSelfMuted`, `isForceMuted`, `isCanManage`, `isRaisedHand` are `final` fields taken from `widget.*` — they come from `showGroupCallPanel`'s `StatefulBuilder` closure. If those values change via a backend event, the inner `_GroupCallPanelState` will not see the update until `setSbState` is called. There is no subscription pathway from `onGroupCallState` to update `selfMuted`, `forceMuted`, `raisedHand` inside `showGroupCallPanel` — `call_screen.dart:1718-1726` (only `msgSub` listening in outer scope; no state subscription) ← `calls/group/calls_group_panel.cpp:280-287` (`setupRealCallViewers` → `subscribeToChanges(real)`)

- [ ] [MAJOR] Scheduled call countdown uses a simple `_formatDuration` showing total elapsed seconds. AyuGram uses a dedicated `Ui::GroupCallScheduledLeft` widget with a gradient label that shows `"Late by"` only when strictly past the time and ignores sub-second negatives — `call_screen.dart:663-729` (custom `Stack` layout hardcoded at pixel offsets 10/52/160) ← `calls/group/calls_group_panel.cpp:942-1006` (`setupScheduledLabels`, `_startsIn`, `_countdown`, `_startsWhen` placed via `groupCallStartsInTop = 10px`, `groupCallCountdownTop = 52px`, `groupCallStartsWhenTop = 160px`)

- [ ] [MAJOR] Wide sidebar width is 204px (Dart) but AyuGram does not use a fixed-width sidebar — participants occupy a separate panel backed by `PeerList` with `groupCallMembersWidthMax: 480px` on the right when in wide mode. The Dart 204px sidebar deviates significantly from reference — `call_screen.dart:81` (`static const sidebarWidth = 204.0`) ← `calls/calls.style:846` (`groupCallMembersWidthMax: 480px`)

- [ ] [MAJOR] Bottom controls padding uses hardcoded `113px` bottom skip for narrow and `108px` for wide, matching `groupCallButtonBottomSkip: 113px` and `groupCallButtonBottomSkipWide: 108px`. However the `padding` here is in logical Flutter pixels; AyuGram's values are device-pixel values (px in .style = px, not logical). On high-DPI screens this will misalign — `call_screen.dart:771` (`padding: EdgeInsets.fromLTRB(24, 16, 24, wide ? 108 : 113)`) ← `calls/calls.style:1020-1021`

- [ ] [MAJOR] `_BigMuteButton` blob radii use `_minorBlobMinRadius = 64.0` / `_minorBlobMaxRadius = 74.0` and `_majorBlobMinRadius = 67.0` / `_majorBlobMaxRadius = 77.0`. AyuGram has `callMuteMinorBlobMinRadius: 64px`, `callMuteMinorBlobMaxRadius: 74px`, `callMuteMajorBlobMinRadius: 67px`, `callMuteMajorBlobMaxRadius: 77px` — values match. BUT the `callMuteButton` circle size in AyuGram is `bgSize: 42px` (not 44px as used in Dart) and `bgPosition: point(13px, 13px)` — `call_screen.dart:1339` (`_circleSize = 42.0`) matches; however `call_screen.dart:1634` (`Container width: 44, height: 44`) for `_GroupCallControlButton` uses 44px background circles against AyuGram's `bgSize: 42px` for `callMuteButtonActive` — mismatched by 2px — `call_screen.dart:1634` ← `calls/calls.style:279`

- [ ] [MAJOR] `_callBarMuteButton` in `MinimisedCallBar` shows a `SnackBar` toast "You are muted by an admin" when force-muted, but AyuGram shows the toast text from `tr::lng_group_call_force_muted_sub` in a proper `Ui::Toast` positioned within the call bar context — using `ScaffoldMessenger` will show the toast at the bottom of the host scaffold, not in the call bar — `call_screen.dart:2843-2851` ← `calls/calls_top_bar.cpp:296-303` (`_show->showToast(tr::lng_group_call_force_muted_sub(tr::now))`)

- [ ] [MAJOR] `_LinearBlobsBar` always ticks even when `level == 0`, only freezing after `_hideBlobsDuration = 500ms`. AyuGram uses `kHideBlobsDuration = 500ms` identically, which is correct. But the Dart linear blobs use fixed green/teal colors `[0xFF52CE5B, 0xFF00B151, 0xFF4DC920]` for all states. AyuGram maps blob colors to bar state (active = live gradient, muted = muted colors, force-muted = purple gradient) — `call_screen.dart:2793-2797` ← `calls/calls_top_bar.cpp:105-128` (`Colors()` map from `BarState` to color vectors)

- [ ] [MAJOR] `_SignalBars` widget uses 4 fixed bars (3/6/9/12px heights, 3px wide, 1px skip). AyuGram's `callBarSignalBars` uses `width: 3px`, `skip: 1px`, `min: 3px`, `max: 12px` — the heights match. However the `inactiveOpacity` for unlit bars in AyuGram is `0.5` (from `callPanelSignalBars`), while Dart uses `0.5` as alpha on Colors.white — correct but Dart renders `Colors.white.withValues(alpha: 0.5)` which is 50% opacity white, whereas AyuGram applies `inactiveOpacity: 0.5` to the foreground color `callBarFg` (which on dark theme is ~white). Functionally equivalent but the color base differs — `call_screen.dart:2976-2993` ← `calls/calls.style:461-467`

- [ ] [MAJOR] `_UserpicStrip` strokes each userpic avatar with `Border.all(color: Colors.white24, width: 2)`. AyuGram uses `groupCallTopBarUserpics: { stroke: 2px }` but the stroke color is the background color (used for separation), not white24 — `call_screen.dart:3051-3054` ← `calls/calls.style:1033-1037`

## calls_screen — CallsBox, GroupCallRow, CallHistoryRow, CreateCallBox, CallSettings

- [ ] [MAJOR] First-page load uses 20 items; subsequent pages use 100 — reversed from AyuGram which requests 100 on first load (_offsetId==0) and 20 on subsequent loads — `calls_screen.dart:79-80,115,135` ← `calls_box_controller.cpp:56-57,544`

- [ ] [MAJOR] GroupCallRow status label appends "· N participant(s)" to the type string — AyuGram sets only the type/visibility string ("public channel", "private group", etc.) with no participant count — `calls_screen.dart:622-636` ← `calls_box_controller.cpp:107-116`

- [ ] [MAJOR] _CreateCallBox button label switches between "Start Call" and "Create Call" based on selection — AyuGram uses "Start Call" (lng_group_call_confcall_add) when selected, "Create" (lng_create_group_create) when empty — the Dart wording is custom, not matching AyuGram's exact i18n keys — `calls_screen.dart:1214` ← `calls_group_invite_controller.cpp:1200-1204`

- [ ] [MAJOR] When creating a conference call with zero selections, Dart calls `engine.createConferenceCall()` immediately — AyuGram does NOT create a call on zero-selection; the create button label is "Create" (lng_create_group_create) and `startOrJoinConferenceCall` is only called when user confirms the dialog — `calls_screen.dart:1115-1150` ← `calls_group_invite_controller.cpp:1185-1199`

- [ ] [MAJOR] _ConferenceCallLinkBox "Join this call yourself" GestureDetector onTap goes to `engine.joinGroupCall(accountId, callId)` then gets group call info — AyuGram uses `startOrJoinConferenceCall({.call = call, .linkSlug = ExtractConferenceSlug(link)})` which drives the full conference join flow through Instance — Dart bypasses the slug-based join path — `calls_screen.dart:1695-1727` ← `calls_group_common.cpp:446-451`

## chat_export — Export panel deviations from AyuGram Desktop

- [ ] [MAJOR] Error state shows "Try Again" button that retries the export (goes back to settings phase via `_retryExport`), but AyuGram Desktop has no retry mechanism — after `showCriticalError` the panel shows text only, no buttons, user must close and reopen from settings — `chat_export.dart:2529-2553` ← `export/view/export_view_panel_controller.cpp:264-279`

- [ ] [MAJOR] Per-chat/per-topic panel height is hardcoded to 540px but AyuGram always uses a single fixed `exportPanelSize = 364x480` for all export modes (full, single peer, single topic) — `chat_export.dart:275-277,1268` ← `export/view/export.style:13`

- [ ] [MAJOR] `ExportPhase.completed` is defined and listed in switch cases but is never set anywhere in the code — the `_onExportComplete` handler keeps the phase as `ExportPhase.processing` and uses the `_exportDone` flag instead, leaving `ExportPhase.completed` as permanently unreachable dead code that could cause confusion if used — `chat_export.dart:133,433,1344` ← `export/view/export_view_panel_controller.cpp:407-410`

- [ ] [MAJOR] On stop confirmation, Dart calls `cancelExport(accountId)` (a clean cancel), but AyuGram calls `_process->cancelExportFast()` only when the user confirms the stop dialog with no pending callback — when a callback is present (e.g. account switch mid-export) AyuGram calls `stopExport()` first, then the callback; Dart has no equivalent distinction — `chat_export.dart:709` ← `export/view/export_view_panel_controller.cpp:338-375`

- [ ] [MAJOR] Engine-initiated `CancelledState` is not handled — AyuGram reacts to `CancelledState` arriving from the process controller by calling `stopExport()` which hides the panel; Dart only closes the panel when the user explicitly confirms the stop dialog, so if the engine cancels independently the panel stays open with no reaction — `chat_export.dart:820-890` ← `export/view/export_view_panel_controller.cpp:411-414`

## chat_list_panel — Chat list panel audit

- [ ] [CRITICAL] Chat preview (peek) on userpic click in wide mode is entirely missing — AyuGram shows a floating preview overlay when clicking the avatar in the wide column (`isUserpicPressOnWide()` → `scheduleChatPreview()`); Dart has no userpic-tap handler in `ChatListRow` and no preview overlay anywhere — `chat_list_panel.dart:923-955` ← `AyuGram/dialogs/dialogs_inner_widget.cpp:2173-2174,5187-5189`

- [ ] [MAJOR] Context menu missing "Add to Folder" item — AyuGram's `fillContextMenuActions()` always calls `addToggleFolder()` which adds a submenu-based folder picker; the Dart `_showChatContextMenu` builds its items list with no folder/filter entry at all — `chat_list_panel.dart:1482-1543` ← `AyuGram/window/window_peer_menu.cpp:1743-1765,652-674`

- [ ] [MAJOR] Context menu missing standalone "Block User" item for DM non-contacts — AyuGram adds `addBlockUser()` for user peers who are not in contacts; Dart only calls `blockUser()` inside the delete/leave confirmation, never as a standalone menu action — `chat_list_panel.dart:1482-1543` ← `AyuGram/window/window_peer_menu.cpp:1755-1758`

- [ ] [MAJOR] Folder tab "Delete Folder" fires directly without confirmation dialog — Dart calls `chatState.deleteFolder()` immediately on menu selection; AyuGram shows a `lng_filters_delete_sure` confirmation box (via `RemoveChatFilterRequests`) before committing the deletion — `chat_list_panel.dart:2514-2516` ← `AyuGram/api/api_chat_filters_remove_manager.cpp:73-83`

- [ ] [MAJOR] Stories bar initial state is expanded (`_expanded = true`) while AyuGram initialises it collapsed (`_expanded = false`) — on first render the Dart stories bar always shows in tall expanded mode (77px) instead of the correct collapsed mode (35px with stacked thumbnails) — `chat_list_panel.dart:2925` ← `AyuGram/dialogs/ui/dialogs_stories_list.h:208`

# chat_list_row — Audit findings

- [ ] [CRITICAL] Draft text suppressed when `chat.unreadCount > 0` or `chat.isUnreadMark` — in AyuGram, draft and unread badge are independent display elements (draft in text area, badge in right column); draft must show regardless of unread count — `chat_list_row.dart:382-383` ← `AyuGram/dialogs/ui/dialogs_layout.cpp:615` (`else if (draft || ...)` has no unread-count gate)

- [ ] [MAJOR] `_WarningBadge` padding is `horizontal: 3, vertical: 1` but spec says `horizontal: 2, vertical: 0` — badge renders 2px wider and 2px taller than spec — `chat_list_row.dart:1551` ← `AyuGram/dialogs/dialogs.style:dialogsScamPadding: margins(2px, 0px, 2px, 0px)`

- [ ] [MAJOR] `_RepliesMessagesUserpic` gradient `#5EB5F7 → #3E97DE` is wrong; must be `historyPeerSavedMessagesBg → historyPeerSavedMessagesBg2` = `#5caffa → #408acf` (same as Saved Messages) — `chat_list_row.dart:1966` ← `AyuGram/ui/empty_userpic.cpp:436-439` + `AyuGram/lib_ui/ui/colors.palette:313,319`

- [ ] [MAJOR] `_HiddenAuthorUserpic` gradient `#72B1DF → #5091C2` (blue) is wrong; must be `premiumButtonBg2 → premiumButtonBg3` = `#a767ff → #db5c9d` (purple-to-pink, matching Telegram's premium gradient) — `chat_list_row.dart:2037` ← `AyuGram/ui/empty_userpic.cpp:477-479` + `AyuGram/lib_ui/ui/colors.palette:657-658`

- [ ] [MAJOR] `ForumChatListRow` top row has no `_SendStateIcon` — AyuGram renders send state (sending/sent/received/lock for closed) for ALL row types including forum rows; outgoing message status is invisible in forum rows — `chat_list_row.dart:2244-2320` ← `AyuGram/dialogs/ui/dialogs_layout.cpp:766-804`

- [ ] [MAJOR] `ForumChatListRow` has no `typingUser`/`typingAction` fields and no `_TypingDotsIndicator` — forum chats cannot display typing indicators; in AyuGram `sendActionPainter()->paint(...)` fires for all row types and replaces the text/topics area while someone is typing — `chat_list_row.dart:2100-2130` ← `AyuGram/dialogs/ui/dialogs_layout.cpp:642-748`

- [ ] [MAJOR] `_TopicsPreview` prepends `# ` to general topic title (`topic.isGeneral ? '# ${topic.title}' : topic.title`) — AyuGram uses `topic->titleWithIcon()` which is just the plain title ("General") with no hash prefix — `chat_list_row.dart:2397` ← `AyuGram/dialogs/ui/dialogs_topics_view.cpp:83`

# chat_settings_screen — Audit vs AyuGram settings_chat.cpp

## Issues Found

- [ ] [CRITICAL] "Choose from file" accepts only images but AyuGram also accepts `.tdesktop-theme`/`.tdesktop-palette` files and calls `Window::Theme::Apply()` on them — theme file import is silently dropped — `chat_settings_screen.dart:273-306` ← `AyuGram/settings/sections/settings_chat.cpp:694-734`

- [ ] [CRITICAL] `_WallpaperBrowser._decodeAllThumbs()` decodes all base64 thumbnails synchronously on the main thread in `initState` and `didUpdateWidget` — for large wallpaper lists this blocks the UI thread for hundreds of ms; AyuGram's `BackgroundBox` renders thumbnails lazily per item — `chat_settings_screen.dart:2800-2828` ← `AyuGram/settings/sections/settings_chat.cpp:477`

- [ ] [CRITICAL] Sensitive content section visibility uses `(_sensitiveCanChange || _ageVerifyNeeded)` but AyuGram only toggles the section on `sensitiveContent().canChange()` — when `ageVerifyNeeded=true` but `canChange=false` the Dart side incorrectly shows the section even though toggling will always fail with a toast, creating a broken UI state — `chat_settings_screen.dart:626` ← `AyuGram/settings/sections/settings_privacy_security.cpp:313`

- [ ] [CRITICAL] The sensitive content section only shows when `_sensitiveLoaded` AND the user can change it, but when the account has `ageVerifyNeeded=true` enabling the toggle shows a toast but leaves `_sensitiveEnabled = true` in local state (optimistic update at line 128) — the rollback only happens on the API call failure path, not on the age-verify short-circuit path — meaning the toggle displays "ON" even though nothing was sent — `chat_settings_screen.dart:114-137`

- [ ] [MAJOR] `_ReactionChooserButton` falls back to a static hardcoded map `_reactionNames` for reaction labels — the reaction list itself is loaded from the engine via `getAvailableReactions`, but names are resolved from the local `const _reactionNames` map (63 entries) rather than from the server-provided reaction names; any reaction the server returns that isn't in the map shows raw emoji as its label — `chat_settings_screen.dart:4328-4390, 4531` ← `AyuGram/settings/sections/settings_chat.cpp:1664-1772` (AyuGram uses live `reactions.list()` with proper names)

- [ ] [MAJOR] The Quick Action preview in Dart uses a simple pulsing `Icon` widget (`_QuickActionPreview`, line 3280) but AyuGram renders the preview using a `Lottie::Icon` animated via `Dialogs::ResolveQuickDialogLottieIconName` and `DrawQuickAction` — the preview is visually wrong and does not match the actual quick action icon used in the chat list — `chat_settings_screen.dart:3280-3449` ← `AyuGram/settings/sections/settings_chat.cpp:2138-2249`

- [ ] [MAJOR] Cloud theme accent color application is incomplete — when installing a cloud theme `installCloudTheme()` is called but the local theme is changed to either `'night'` or `'day_blue'` based on `theme.isDark` and the cloud accent is applied via `updateAccentColor`; AyuGram's `CloudList` loads and applies the actual cloud theme document (palette + wallpaper), not a generic dark/day preset — cloud themes with custom colors, custom wallpapers, or multiple accent variants are not applied correctly — `chat_settings_screen.dart:468-483` ← `AyuGram/settings/sections/settings_chat.cpp:2703-2800`

- [ ] [MAJOR] The "Suggest Animated Emoji" checkbox is gated on both `isPremium` AND `suggestEmoji` — but in AyuGram it is shown with `addSliding` controlled by `rpl::combine(Data::AmPremiumValue, suggestEmoji->value(), _1 && _2)` meaning it is hidden (not disabled) when either condition is false; the Dart side shows it (as disabled) when `suggestEmoji=true && isPremium=false`, which means non-premium users see a permanently-locked checkbox that should be invisible — `chat_settings_screen.dart:3585-3594` ← `AyuGram/settings/sections/settings_chat.cpp:1506-1523`

- [ ] [MAJOR] `_StickerPackManager` calls `_load()` (which awaits `getInstalledStickerPacks`) and on completion calls `setState` but does NOT dispose or cancel any in-flight async operations when the widget is disposed mid-load — if the bottom sheet is dismissed before load completes, `setState` is called on an unmounted widget which throws in debug mode; same issue in `_removePack`, `_installPack`, and `_search` — `chat_settings_screen.dart:3776-3848` (no `mounted` check before setState in the sticker load path at line 3789)

- [ ] [MAJOR] `_CloudThemeSection._buildGrid` uses a fixed `SizedBox(height: _gridHeight(visibleThemes.length))` calculated at `rows * 116.0` per row — if the available width produces narrower cards the fixed height causes clipping; AyuGram uses a proper `Ui::VerticalLayout` that sizes to content — `chat_settings_screen.dart:2351-2384`

# chat_switch_overlay — Audit

## Dimensions / style values — all match AyuGram

All numeric constants match `window/window.style`:
- `_cellWidth/Height = 72×104` ← `chatSwitchSize: size(72px, 104px)`
- `_userpicSize = 56` ← `chatSwitchUserpic: size(56px, 56px)`
- `_userpicTop = 8` ← `chatSwitchUserpicTop: 8px`
- `_nameSkip = 6` ← `chatSwitchNameSkip: 6px`
- `_selectLineWidth = 3` ← `chatSwitchSelectLine: 3px`
- `_panelMargin = 16` ← `chatSwitchMargins: margins(16px,…)`
- `_panelPadding = 12` ← `chatSwitchPadding: margins(12px,…)`
- `_panelRadius = 6` ← `boxRadius: 6px`
- Font size 11px ← `chatSwitchNameLabel: font(11px)`
- Animation duration 150ms ← `slideWrapDuration: 150`

---

- [ ] [MAJOR] Selection highlight uses opacity fade instead of animated border-width grow — AyuGram animates `pen.setWidthF(chatSwitchSelectLine * animValue)` so the 3 px border grows from 0 to full width; Dart wraps the same border in `AnimatedOpacity(opacity: selected ? 1.0 : 0.0)` which fades the fully-drawn 3 px border in/out — `chat_switch_overlay.dart:400-409` ← `window/window_chat_switch_process.cpp:184-201`

- [ ] [MAJOR] Name label does not break at arbitrary character boundaries — AyuGram calls `label->setBreakEverywhere(true)` immediately after creating the label so long single-word names wrap mid-glyph; Dart `Text` widget uses default word-boundary wrapping with `TextOverflow.ellipsis`, truncating instead of wrapping long tokens — `chat_switch_overlay.dart:418-427` ← `window/window_chat_switch_process.cpp:149`

- [ ] [MAJOR] Out-of-bounds selection clamped instead of cleared on resize — when the panel narrows and `_selected >= _shownCount`, AyuGram sets `_selected = -1` (no selection) so the next Tab press cleanly starts at 0; Dart clamps to `visible - 1` (keeps the last visible item selected), diverging from intended behaviour — `chat_switch_overlay.dart:294-301` ← `window/window_chat_switch_process.cpp:455-457`

# choose_datetime_box — Audit Findings

- [ ] [MAJOR] Calendar "Select days" button placed on right side instead of left — In AyuGram `createButtons()` (non-selection, allowsSelection=true) uses `addButton(Close)` on the right and `addLeftButton(Select days)` on the left. Dart passes `[TelegramBoxButton('Select days'), TelegramBoxButton('Close')]` with no `isLeft:true`, making both right-aligned — `choose_datetime_box.dart:489` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:1431`

- [ ] [MAJOR] Selection range renders per-cell circles instead of row-spanning rounded pill — AyuGram `paintRows()` draws a single `drawRoundedRect` spanning all selected cells within each row (cells share a continuous highlight bar). Dart `_DayCell` renders `BoxShape.circle` per cell for `isInRange`, producing disconnected dots instead of a bar — `choose_datetime_box.dart:1108` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:799`

- [ ] [MAJOR] Drag-to-extend selection not implemented — AyuGram `mouseMoveEvent` (line 934–947) calls `_context->updateSelection(index)` whenever the mouse is dragged while pressed in selection mode, enabling click-drag to define a range. Dart `_DayCell` only has `onTap`; no pointer-drag gesture extends the selection — `choose_datetime_box.dart:640` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:934`

- [ ] [MAJOR] Shift-click to extend selection not implemented — AyuGram `mousePressEvent` (line 997–1009): if selection mode is active and either Shift is held OR it is the second press when single-day selected, calls `updateSelection` instead of `startSelection` (two-press semantics). Dart `_selectDay` always calls `_startSelection` on first tap and `_updateSelection` on second tap with no Shift-modifier path — `choose_datetime_box.dart:321` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:997`

- [ ] [MAJOR] `kJumpDelay` constant is wrong — AyuGram defines `kJumpDelay = 2 * crl::time(350) = 700ms` and this is the delay before jumping to min/max on long-press. Dart `_kJumpDelay = 700` is correct in value, but Dart starts the jump timer on `onPointerDown` and cancels on `onTap` (no hold-detection); AyuGram uses `MouseButtonPress` → timer fires → jump. In Dart a single click always fires onTap first which cancels the timer, but the timer also fires on any press-hold correctly. However the `onTap` handler calls `_cancelJump()` then `_goPrevMonth()` (line 518–520) — so a tap also navigates a month AND cancels jump. This is correct. No issue here (minor note only).

- [ ] [MAJOR] Repeat period row uses `lower_bound` nearest-match logic in AyuGram but Dart `_showRepeatMenu` uses exact-value display — AyuGram `ChooseRepeatPeriod` label uses `ranges::lower_bound` to find nearest entry and displays that. Dart stores `_repeatPeriod` as exact value from map and displays `_repeatPeriods[_repeatPeriod] ?? "Never"`, falling back to "Never" for unknown values. This is functionally equivalent since values only come from the map entries. No actual issue.

- [ ] [CRITICAL] `requireImage` mode not implemented — AyuGram `CalendarBox::Inner` has `setRequireImage(bool)` which, when true, prevents selecting days that have no dynamic image loaded (lines 954–958: `if (_requireImage) { ... selected = kEmptySelection }`). Dart has no equivalent; all non-disabled days are always selectable regardless of whether a dynamic image was loaded — `choose_datetime_box.dart` (no implementation) ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:954`

- [ ] [MAJOR] Ripple animation on day cells not implemented — AyuGram `Inner` creates a per-cell `RippleAnimation` on `mousePressEvent` (line 987–993) with an ellipse mask matching `cellInner`, and paints it in `paintRows` (line 875–888). Dart `_DayCell` uses Flutter's `InkWell` with `customBorder: CircleBorder` which provides ripple, but the ripple is suppressed in selection mode: AyuGram skips ripple paint in selection mode (line 876: `if (it != _ripples.cend() && !selectionMode)`). Dart does not disable InkWell ripple during selection mode — `choose_datetime_box.dart:1130` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:876`

- [ ] [MAJOR] Silent-send via Ctrl key not applied at box level — AyuGram `ScheduleBox` (history_view_schedule_box.cpp line 102–104) checks `base::IsCtrlPressed()` in the `submit` lambda and sets `options.silent = true`. Dart `_submit` checks `HardwareKeyboard.instance.isControlPressed` at the time the Schedule button is pressed (line 1639), which only fires when the button widget is tapped — it does not capture Ctrl state from Enter key submission (line 1597: `onSubmit: () => _submit()` in `_TimeInputField`). Pressing Enter in the time field submits without checking Ctrl — `choose_datetime_box.dart:1597` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_schedule_box.cpp:102`

# engine_service — Bridge service layer audit

## Summary

`engine_service.dart` is the high-level Dart wrapper around the FFI bridge. It is well-structured and covers a very wide API surface (~250 methods). No placeholder stubs, no "coming soon" snackbars, no fake data. All calls correctly reach the Go engine via `_callRaw`/`_callAsync`. However, four concrete bugs were found:

---

## Findings

- [ ] [CRITICAL] `EngineGroupCallParticipant` proto is missing `video_joined`, `only_min_loaded`, `video_camera_endpoint`, `video_screen_endpoint`, `video_camera_paused`, `video_screen_paused` — so `getGroupCall()` always returns participants with those fields at their zero defaults (false/empty string). The Dart model `GroupCallParticipant` declares all six fields correctly, but the proto carrying them (`proto/engine.proto:959-977`) has none of them. Only the `group_call_state` event path (`engine_service.dart:6135`, via `GroupCallInfo.fromJson`) correctly delivers these fields because it goes through JSON. The proto path (`engine_service.dart:2166-2201`) is broken for all video-related participant state. — `engine_service.dart:2180` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_group_call.h:bool videoJoined`, `bool onlyMinLoaded`, `videoParams`

- [ ] [CRITICAL] `EngineGroupCallInfo` proto (`proto/engine.proto:979-986`) only carries 6 fields (`call_id`, `chat_id`, `title`, `participants_count`, `participants[]`, `active`) — `getGroupCall()` always returns `GroupCallInfo` with `isRtmp`, `isRecording`, `recordStartDate`, `scheduleDate`, `listenersHidden`, `messagesEnabled`, `messagesMinPrice`, `conferenceInviteLink` all at zero/false/empty. These fields exist on the Dart model but are never populated by the sync fetch path. Only `group_call_state` push events (`engine_service.dart:6135`) deliver complete data. — `engine_service.dart:2174-2201` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_group_call.h:bool rtmp()`, `bool listenersHidden()`, `scheduleStartSubscribed()`

- [ ] [CRITICAL] Non-engine core events are silently dropped — `engine_service.dart:6008` contains the comment `// Non-engine core events will be handled when per-core UI is built.` and does nothing. Any event fired by a non-Telegram core (Bale, Matrix, Rubika, XMPP, IRC, etc.) is discarded at the bridge listener. This means multi-platform accounts cannot receive live `msg_received`, `chat_updated`, `auth_state`, or any other event. AyuGram dispatches all data-source events to the appropriate handler. — `engine_service.dart:6004-6008` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_changes.h:Changes::peerUpdated`, `messageUpdated`, `entryUpdated`

- [ ] [MAJOR] `_msgReactionsUpdatedController` (declared at `engine_service.dart:45`) and `_notifySettingsController` (declared at `engine_service.dart:56`) are never closed in `dispose()` — `dispose()` at lines 5894-5917 closes 20 of the 22 broadcast `StreamController`s but omits these two. On app hot-restart or account removal the streams leak. AyuGram cleans up all subscriptions on session teardown. — `engine_service.dart:5894-5917` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_session.h` (session destruction closes all subscriptions)

- [ ] [MAJOR] `getDeletedMessages()` uses the synchronous blocking call `_callRaw` and parses JSON inline on the UI thread — `engine_service.dart:2902-2937`. The parallel `getMessages()` at line 2806 correctly uses `_callAsync` + `Isolate.run` to offload protobuf parsing. `getDeletedMessages` returns up to 20 messages with full field mapping but does both the FFI call and all JSON parsing synchronously on the Dart main isolate. AyuGram loads deleted/history items from a background thread. — `engine_service.dart:2902` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_histories.h:Histories::deleteMessages` (async)

# color_picker_box — Color Picker Dialog

- [ ] [CRITICAL] Chat settings and photo editor callers need `Mode::HSL` (X=hue, Y=saturation, horizontal lightness slider) but implementation always uses HSV/RGBA mode (X=saturation, Y=brightness, vertical hue slider) — wrong color model for 2 of 3 use-sites — `color_picker_box.dart:9-20` ← `settings_chat.cpp:375-377`, `color_picker.cpp:751`, `color_editor.cpp:875-882`

- [ ] [CRITICAL] Lightness slider completely missing when `lightnessMin`/`lightnessMax` are set — AyuGram shows a horizontal `Type::Lightness` slider constrained to `[min, max]` below the picker; Dart has no slider at all and silently clamps via HSL post-processing, giving the user no way to navigate within the allowed lightness range — `color_picker_box.dart:207-221, 439-454` ← `color_editor.cpp:885-896, 1036-1049`, `settings_chat.cpp:386-388`

- [ ] [MAJOR] For `photo_crop_editor.dart` usage (no lightness limits), picker should still be `Mode::HSL` (hue on X, saturation on Y, 2D rainbow grid) but renders HSV RGBA gradient (white-to-hue left-right, white-to-black top-bottom) — wrong picker model for photo editor brush color selection — `color_picker_box.dart:852-876` ← `color_editor.cpp:212-247`, `color_picker.cpp:751`

- [ ] [MAJOR] Slider arrows drawn as custom quadratic bezier paths; AyuGram uses pre-rendered `colorSliderArrow` sprite icons (`colorSliderArrowLeft/Right/Top/Bottom` from `sliderBgActive`) — visual shape differs, bezier curves look organic rather than sharp triangular arrows — `color_picker_box.dart:1024-1031, 1142-1149` ← `boxes.style:515-518`, `color_editor.cpp:393-416`

- [ ] [MAJOR] Hex field output is uppercase (`.toUpperCase()`) but AyuGram outputs lowercase hex (`'a' + (value - 10)`) — `color_picker_box.dart:231,233` ← `color_editor.cpp:1001-1005`

- [ ] [MAJOR] `_HorizontalOpacityPainter._checkerCacheMap` is a `static final Map<Size, ui.Picture>` with no eviction policy — grows unbounded if the picker is shown at varying sizes; AyuGram uses a pre-existing shared `style::TransparentPlaceholder()` brush with zero allocation — `color_picker_box.dart:1086` ← `color_editor.cpp:373-375`

## confirm_box — Box/Dialog Infrastructure, Delete Box, Single Choice, Screen Share, Report Flow

- [ ] [CRITICAL] `openSystemSettingsForPermission` uses `'sound'` for **both** microphone and camera on Linux — camera should open `'camera'` (gnome-control-center) or `'kcm_v4l2'` / `'kcm_kamera'` (KDE) instead of the PulseAudio sound panel — `confirm_box.dart:1128` ← `moderate_messages_box.cpp:949` (camera/microphone separation is standard in all desktop clients)

- [ ] [CRITICAL] `_tryPortalScreenCast` accesses `client.uniqueName` synchronously immediately after `DBusClient.session()` before the D-Bus connection is established — `uniqueName` is always empty at this point, causing the early-return on line 1280 to always fire and the entire portal screen-cast path to silently fail on Wayland — `confirm_box.dart:1271,1279-1280` ← `confirm_box.dart` (DBus requires awaiting connection before uniqueName is populated)

- [ ] [CRITICAL] `showAutoDeleteTimerBox` offers only 4 options (Off / 1 day / 1 week / 1 month) via a radio-button `SingleChoiceBox` — AyuGram's `TTLBox` uses a `TimePickerBox` with 16 options spanning 1 day through 1 year (1-7 days, 2-3 weeks, 1-6 months, 12 months) — `confirm_box.dart:1059-1065` ← `menu/menu_ttl.cpp:168-184`

- [ ] [MAJOR] Delete-confirm userpic layout mismatch: `CircleAvatar` has `radius: 20` (40 px diameter) but AyuGram's `DeleteChatBox` uses `st::mainMenuUserpic` which is `size(48px, 48px)` — should be `radius: 24` — `confirm_box.dart:757` ← `moderate_messages_box.cpp:964`, `window/window.style:93`

- [ ] [MAJOR] Delete-confirm userpic + name is rendered as `Center(child: Row(mainAxisSize: min))` — centered in the box — but AyuGram's `IconWithTitle` renders them full-width, icon left-aligned at `x=0`, text positioned to the right of the icon — `confirm_box.dart:752-783` ← `moderate_messages_box.cpp:967-978`, `ui/boxes/confirm_box.cpp:120-153`

- [ ] [MAJOR] Dead variable `isChannel` in `_doConfirm` (line 684) is assigned but never read — indicates incomplete logic: in AyuGram the revoke/leave semantics differ for channels, and this variable was presumably meant to guard some branch that was never finished — `confirm_box.dart:684` ← `boxes/delete_messages_box.cpp:587-589`

- [ ] [MAJOR] `_SingleChoiceContent` has `buttons: const []` — no Cancel or OK button is shown — AyuGram's `SingleChoiceBox` always adds an OK button (`tr::lng_box_ok()`) that closes the box without changing selection, allowing the user to dismiss without committing — `confirm_box.dart:990` ← `ui/boxes/single_choice_box.cpp:22`

- [ ] [MAJOR] `_ReportOptionPickerBox` shows a `chevron_right` icon only — AyuGram's `ReportReasonBox` shows a distinct per-category icon for each reason (spam, violence, child abuse, pornography, copyright, drugs, personal details, other) using `FloatingIcon` with styled icons (`st.spam`, `st.violence`, etc.) — per-option icons are entirely absent — `confirm_box.dart:1938-1942` ← `ui/boxes/report_box_graphics.cpp:64-121`

- [ ] [MAJOR] When `showBackButton: true` and `hasComment: false` in `_ReportOptionPickerBox`, the button row contains **only** the `Back` button — no `Cancel` — AyuGram's report boxes always render a cancel button for every option-picking step; users with `showBackButton=true` on a no-comment step have no explicit dismiss path — `confirm_box.dart:1989-2006` ← `ui/boxes/report_box_graphics.cpp:122`

- [ ] [MAJOR] `_ReportDetailsBox` (standalone comment-only report box) uses `'assets/animations/blocked_peers_empty.json'` as the Lottie animation — AyuGram's `AddReportDetailsIconButton` uses `u"blocked_peers_empty"_q` from `Settings::CreateLottieIcon` with `st::normalBoxLottieSize` — the Lottie fires immediately (forward on init), while AyuGram defers animation until `setShowFinishedCallback` (after the box open animation completes) — `confirm_box.dart:2097-2104` ← `ui/boxes/report_box_graphics.cpp:209-221`

# contacts_screen — Critical and Major Issues

- [ ] [MAJOR] Middle-click (wheel click) on contact row does NOT open in new window — calls `_navigateToChat` (switches chat in same pane) and shows a toast instead of `showInNewWindow(peer)` — `contacts_screen.dart:613-618` ← `AyuGram/boxes/peer_list_controllers.cpp:183-185`

- [ ] [MAJOR] Story ring draws ALL segments with one uniform shader (all gradient if any unread, all gray if all read) — AyuGram draws read segments in thin gray and unread segments in thick gradient separately via `PeerListStoriesSegments`; the Dart model has no `unreadStoryCount` field, only `hasUnreadStory` bool, so it cannot reproduce per-segment read/unread differentiation — `contacts_screen.dart:1392-1431` (`_ContactStoryRingPainter`) ← `AyuGram/boxes/peer_list_controllers.cpp:204-237` (`PeerListStoriesSegments`)

- [ ] [MAJOR] Story ring missing `videoStream` state — AyuGram renders live-video-stream stories with a solid red/attention color (`st::attentionButtonFg`) as a single full arc; the Dart `_ContactStoryRingPainter` has no such case and the `ContactInfo` model has no `isVideoStream` field — `contacts_screen.dart:1379-1439` ← `AyuGram/boxes/peer_list_controllers.cpp:212-225`

- [ ] [MAJOR] "Suggest photo" and "Set personal photo" buttons invoke `FilePicker.platform.pickFiles()` directly without showing a popup menu — AyuGram opens `showPhotoMenu(bool suggest)` which offers three options: (1) choose from file, (2) paste from clipboard if clipboard has an image, (3) emoji builder; the Dart skips the menu entirely and passes raw file path to engine with no image crop/edit step (AyuGram uses `Editor::PrepareProfilePhotoFromFile` with ellipse crop before upload) — `contacts_screen.dart:1576-1630` (`_suggestPhoto`, `_setPersonalPhoto`) ← `AyuGram/boxes/peers/edit_contact_box.cpp:798-887` (`showPhotoMenu`, `choosePhotoFile`)

- [ ] [MAJOR] After "Suggest photo" completes, AyuGram immediately opens the peer's chat (`_window->showPeerHistory(_user->id)`) so the user can see the suggestion request in the chat; the Dart only shows a toast and stays on the edit contact dialog — `contacts_screen.dart:1584-1588` ← `AyuGram/boxes/peers/edit_contact_box.cpp:893-894`

# create_channel_screen — Dead code, unused widget

- [ ] [CRITICAL] Unused widget — `create_channel_screen.dart:11` ← Dead code. `CreateChannelScreen` is defined but never imported or used anywhere in the codebase. Grep across all `.dart` files yields zero references. The hamburger drawer (`hamburger_drawer.dart:261`) directly calls `showCreateChannelWizard(context)` without navigating to this screen. Delete the entire file. AyuGram's pattern (`window_session_controller.cpp:3185`) directly opens the dialog without an intermediate screen — Dart code should match by calling the wizard directly from the menu, not through a dead-code router screen.


## create_giveaway_box — Audit findings

- [ ] [CRITICAL] Missing "Specific Users / Award" giveaway type entirely — AyuGram supports a fourth mode (GiveawayType::SpecificUsers / AwardMembersListController) where an admin selects specific users to receive gifts, toggled by clicking the Premium row. Dart only exposes random/credits/prepaid. — `create_giveaway_box.dart:15` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:269-457`

- [ ] [CRITICAL] `_boostsPerPremium` is hardcoded to 4 instead of being read from appConfig `giveaway_boosts_per_premium`. AyuGram reads this at runtime via `apiOptions.giveawayBoostsPerPremium()` which queries `appConfig.get<int>("giveaway_boosts_per_premium", 4)`. Hardcoding means incorrect boost counts if Telegram changes this server-side value. — `create_giveaway_box.dart:89` ← `AyuGram/api/api_premium.cpp:689-694`

- [ ] [CRITICAL] Country picker uses a hardcoded static map of ~70 countries. AyuGram uses `Countries::Instance().list()` (the full registered country list from the Telegram server/protocol, typically 200+ entries), sorted alphabetically, with `countryNameByISO2()` for display and `Countries::Instance().flagEmojiByISO2()` for flags. The Dart list is missing hundreds of countries. — `create_giveaway_box.dart:1597-1617` ← `AyuGram/info/channel_statistics/boosts/giveaway/select_countries_box.cpp:81-168`

- [ ] [CRITICAL] `giveawayCountriesMax` limit is never enforced in the Dart country picker — users can select any number of countries. AyuGram gates every selection attempt through `checkErrorCallback` (`giveaway_countries_max` from appConfig, default 10) and shows a toast if exceeded. — `create_giveaway_box.dart:1714-1722` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:966-975`

- [ ] [CRITICAL] `giveawayAddPeersMax` limit is never enforced in the Dart channel picker — unlimited additional channels can be added. AyuGram enforces `giveaway_add_peers_max` (appConfig, default 10) via `CreateErrorCallback`. — `create_giveaway_box.dart:306-338` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:923-929`

- [ ] [CRITICAL] Random/credits giveaway launch goes through a custom `engine.launchRandomGiveaway` / `engine.launchCreditsGiveaway` call returning a URL that is then opened externally. AyuGram routes ALL giveaway types (except prepaid premium) through `Payments::CheckoutProcess::Start(invoice, done)` — the payments checkout process which shows an in-app payment UI. The Dart approach bypasses this entirely and uses no payment UI flow. — `create_giveaway_box.dart:214-253` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1537`

- [ ] [CRITICAL] `random_id` for the credits giveaway is generated via `Random().nextInt(1 << 31)`, a low-entropy 31-bit int. AyuGram uses `UniqueIdFromCreditsOption()` which computes a 64-bit XXH64 hash of credits+storeProduct+currency+amount+peerId+sessionUniqueId to produce a deterministic, collision-resistant ID. The Dart approach risks ID collisions and doesn't produce a deterministic ID for retry-safety. — `create_giveaway_box.dart:279` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:75-86`

- [ ] [CRITICAL] For credits giveaway, `storeProduct` field is never passed to `launchCreditsGiveaway`. AyuGram explicitly sets `invoice.storeProduct = option.storeProduct` in the credits invoice, which is required for store-based purchases. — `create_giveaway_box.dart:267-287` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1410-1415`

- [ ] [CRITICAL] Prepaid credits giveaway type (`BoostPrepaidGiveaway.credits != 0`) is not distinguished from a prepaid premium giveaway. AyuGram has a separate `isPrepaidCredits` path that constructs a different invoice (`giveawayCredits = prepaid->credits`, `randomId = prepaid->id`) and shows a different subtitle (`lng_giveaway_credits_new_about`). Dart treats all prepaid giveaways identically. — `create_giveaway_box.dart:537-593` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:301-390`

- [ ] [CRITICAL] Premium terms link is absent. AyuGram always appends a `lng_premium_gift_terms` label (with a clickable link opening the Premium settings page) below the gift duration options for random giveaways and below the date section for prepaid giveaways. The Dart UI has no terms link anywhere. — `create_giveaway_box.dart:660-682` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1019-1080`

- [ ] [MAJOR] End date minimum enforced as "3 days from now" (`Duration(days: 3)`) but AyuGram's date picker minimum is `QDateTime::currentSecsSinceEpoch` (i.e. right now, no minimum offset). Only the initial default value is set 3 days ahead; the picker itself allows any future time. — `create_giveaway_box.dart:1171` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1281`

- [ ] [MAJOR] Credits options "Show More" expansion is not implemented. AyuGram hides `isExtended` options by default and shows a "Show more" button that reveals them. The Dart code partially filters extended options (`!(opt['extended'] == true) || opt['is_default'] == true || entry.key == _selectedCreditsOptionIndex`) but never provides a "show more" button to reveal the rest. — `create_giveaway_box.dart:783-785` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:674-693`

- [ ] [MAJOR] `giveawayBoostsPerPremium` is not dynamically applied to the "boosts" label shown in the channel list row subtitle. AyuGram's channel list controller reads `apiOptions.giveawayBoostsPerPremium() * sliderValue` reactively; Dart uses the hardcoded `_boostsPerPremium * _currentWinners`. — `create_giveaway_box.dart:632-653` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:888-897`

- [ ] [MAJOR] Prepaid giveaway does not pass `storeProduct` or `storeQuantity` in the launch payload. AyuGram's prepaid path passes these in the invoice. The Dart prepaid launch at `_doLaunchPrepaid` never includes them. — `create_giveaway_box.dart:176-203` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1399-1405`

- [ ] [MAJOR] "Additional prize" description field disappears from prepaid giveaway section. AyuGram's `additionalWrap` is inside `randomWrap` which is shown for ALL non-specific giveaways including prepaid. In Dart, `_buildSettingsSection` includes the additional prize field but it is shared between prepaid/random/credits; however, the `_buildPrepaidSection` does not include it, so the about-text below the field is also absent. AyuGram shows a combined about-text (`lng_giveaway_prizes_just_premium` etc.) that varies by type; Dart has no such text at all. — `create_giveaway_box.dart:1135-1165` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1100-1253`

- [ ] [MAJOR] Country search in the Dart picker uses `startsWith` only on the full country name; AyuGram's picker matches `startsWith` on flag, name, AND `alternativeName` fields from the countries database. Countries with alternative names (e.g. "Iran, Islamic Republic of" / "Iran") will not be found by their alternative name in Dart. — `create_giveaway_box.dart:1643-1647` ← `AyuGram/info/channel_statistics/boosts/giveaway/select_countries_box.cpp:160-167`

- [ ] [MAJOR] Channel picker shows only channels from the locally-loaded `chatState.chatsForAccount()`. AyuGram uses `MyChannelsListController` which queries the full peer list from the Telegram API for channels the admin owns, not just what happens to be in the local chat cache. — `create_giveaway_box.dart:307-317` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:919-929`

- [ ] [MAJOR] After a successful non-prepaid giveaway, Dart shows a plain toast "Giveaway launched!". AyuGram shows a rich multi-line toast with title (`lng_giveaway_created_title`) and body (`lng_giveaway_created_body`) containing a clickable link that navigates to the Boosts info page, with `kDoneTooltipDuration` (5s). The Dart success feedback is vastly simpler and missing the navigation link. — `create_giveaway_box.dart:243-246` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1476-1502`

- [ ] [MAJOR] `giveawayPeriodMax` is fetched as a separate engine call in `_loadOptions`. AyuGram derives this from `apiOptions.giveawayPeriodMax()` which comes from the same `PremiumGiftCodeOptions` request, not a separate call. A distinct engine method for this is non-standard and may not exist in the backend implementation. — `create_giveaway_box.dart:113` ← `AyuGram/api/api_premium.cpp:710-715`

# create_group_wizard — Audit Findings

## create_group_wizard — Group/Channel Creation Wizard

- [ ] [CRITICAL] Forum-type userpic uses circle shape instead of rounded-square (forum shape) — `create_group_wizard.dart:1126` ← `AyuGram/boxes/add_contact_box.cpp:568` (`_type == Type::Forum ? PeerUserpicShape::Forum : Auto`). The `_UserpicButton` at line 1126 never passes `isForum: true`; forum avatars must be rendered with a rounded-square shape matching AyuGram.

- [ ] [CRITICAL] TTL auto-delete picker shown in title bar for megagroup and forum types — `create_group_wizard.dart:1071` ← `AyuGram/boxes/add_contact_box.cpp:628` (`if (_type == Type::Group)`). AyuGram only attaches the TTL menu button for `Type::Group`; Dart shows it for all `!= channel` (megagroup + forum included), which is wrong.

- [ ] [CRITICAL] Basic group photo upload silently fails — `create_group_wizard.dart:851` ← `AyuGram/go/cores/telegram.go:20103`. After `createGroup`, the code calls `_engine.editChannelPhoto(accountId, chatId, photoPath)`, but the Go backend at line 20103 does `ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }`. A basic group chat ID resolves to `PeerChat`, not `PeerChannel`, so the photo is never set and the error is swallowed at `debugPrint('Failed to upload group photo')` — photo silently never applies.

- [ ] [MAJOR] Missing member-invitation confirmation dialog for basic groups — `create_group_wizard.dart:927` ← `AyuGram/boxes/peers/add_participants_box.cpp:977`. For non-channel peers AyuGram shows a `ConfirmBox` with an "Also share chat history" checkbox before adding members (`tr::lng_participant_invite_sure`). Dart calls `_engine.addMembers` directly with no confirmation step.

- [ ] [MAJOR] Member picker counter always shows "/ 200000" regardless of chat type — `create_group_wizard.dart:1094` ← `AyuGram/boxes/peers/add_participants_box.cpp:842`. Basic Telegram groups (`messages.createChat`) are capped at 200 participants. The title bar hardcodes `'${_selectedMembers.length} / 200000'` for all wizard types; it should show `/ 200` when `widget.type == _WizardType.group`.

- [ ] [MAJOR] Slowmode state is loaded and saved in `_EditPeerTypeBox` but has no UI control — `create_group_wizard.dart:2972` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:191`. Helper methods `_slowmodeLabel()` and `_slowmodeIndex()` are defined but never called anywhere; `_slowmodeSeconds` is read from the engine and written back on save, but the user has no slider or picker to change it. Slowmode configuration is completely invisible and inaccessible.

# custom_emoji_cache — Ref-count bug, dead global listener API, missing cross-size preview, unbounded disk cache

- [ ] [CRITICAL] `acquire()` discards its ref-count token (calls `acquireToken()` and ignores return value), making the `acquireToken()`/`releaseToken()` API inaccessible through the `acquire()` path; meanwhile `release()` removes `tokens.first` (insertion-ordered, line 177) rather than a named token — mixing the two APIs on the same key would corrupt the ref count and could cause premature `_evictFromMemory` while other widgets still hold a live reference — `custom_emoji_cache.dart:159-161,174-184` ← `data_custom_emoji.h:151-156` (AyuGram tracks instances via `unordered_map<DocumentId, unique_ptr<Instance>>` with explicit per-ID ownership, no ambiguous dual-API)

- [ ] [MAJOR] `addListener(cb)` / `removeListener(cb)` public API adds to `_globalListeners` (line 122-123) which can never be notified: every caller of `_notifyListeners` passes a non-empty `Set<int>` (`_loadFromDisk` line 286, `_fetchThumbBatch` line 445, `_fetchFileBatch` line 476), which triggers the early `return` at line 489 before the global-listener loop runs — any widget that registers via `addListener()` will silently receive zero updates — `custom_emoji_cache.dart:122-123,479-494` ← `data_custom_emoji.cpp:878-898` (AyuGram's `repaintLater/invokeRepaints` notifies all registered instances without a split code path)

- [ ] [MAJOR] `prepareNonExactPreview` at line 208-213 only checks `_files[documentId]` and triggers a disk load — it does not consult `_thumbs[documentId]` which may already be populated — when `request()` (thumb batch) has completed but `requestFile()` has not, the method returns `null` and fires a redundant disk probe despite a usable in-memory thumb being available; callers get no preview when they could — `custom_emoji_cache.dart:208-213` ← `data_custom_emoji.cpp:523-548` (AyuGram's `prepareNonExactPreview` iterates all other size instances and scales any available `imagePreview` to the requested size, always returning something if any size is loaded)

- [ ] [MAJOR] `EmojiSizeConstants.frameSizes` hardcodes logical-pixel values (22, 27, 38, 21) computed at 100% UI scale — the `isolated` value of 38 is `st::largeEmojiSize + 2 * st::largeEmojiOutline` evaluated at scale=1; at 125% or 150% Telegram-style UI scale the style constants grow proportionally, making the correct frame size larger, but the Dart code never recomputes — `custom_emoji_cache.dart:42-47` ← `data_custom_emoji.cpp:83-95,1011-1014` (AyuGram calls `EmojiSizeFromTag(tag)` which reads live style values, then applies `AdjustCustomEmojiSize(emoji/factor)*factor` to get the correct physical-pixel size at any scale)

- [ ] [MAJOR] Disk cache (`$cacheDir/emoji/*.dat`, `*.thumb`, `*.path`, `*.mime`) is written unconditionally in `_writeToDisk`, `_writeThumbToDisk`, `_writePathToDisk` (lines 230-254) but is never pruned — `initDiskCache` (line 104-120) only reads the index, never deletes old entries — on a device with many conversations containing custom emoji the cache grows without bound — `custom_emoji_cache.dart:104-120,230-254` ← `data_custom_emoji.cpp:294-328` (AyuGram stores emoji frames in `cacheBigFile()` which is a bounded LRU store with a configured maximum size)

# edit_forum_topic_box — Color grid active during edit discards changes; wrong initial color

- [ ] [MAJOR] Color grid cells (`_buildGridCell`) remain interactive during editing — user can select a different color, the preview updates, but `editForumTopic` has no `colorId` parameter and the call site (`chat_list_panel.dart:5732–5734`) does not pass `result.colorId`, so the change is silently discarded on save. AyuGram prevents this entirely by disabling the icon button (`WA_TransparentForMouseEvents`) whenever the topic is already created, making color cycling impossible during editing — `edit_forum_topic_box.dart:1184` (`onTap: () => _selectColorFromGrid(colorId)` has no `isEditing` guard) ← `AyuGram/boxes/peers/edit_forum_topic_box.cpp:474–479` (`icon->setAttribute(Qt::WA_TransparentForMouseEvents, created || (iconId != 0))`)

- [ ] [MAJOR] Initial color for a new topic is always `_topicColorIds[0]` (0x6FB9F0, blue, hardcoded) — AyuGram randomly picks a starting color via `ChooseNextColorId(0, state->otherColorIds)` which calls `base::RandomIndex` over the full color list — `edit_forum_topic_box.dart:140` (`_colorId = widget.existingColorId ?? _topicColorIds[0]`) ← `AyuGram/boxes/peers/edit_forum_topic_box.cpp:436` (`topic ? topic->colorId() : ChooseNextColorId(0, state->otherColorIds)`)

# emoji_panel — Audit Findings

## emoji_panel — Sticker/GIF/Emoji panel UI and backend wiring

- [ ] [CRITICAL] `_stickerFileCache` is a `static final Map<int, CustomEmojiFileData>` with **no eviction policy** — stores raw `Uint8List` file bytes (100–500 KB per sticker) that accumulate indefinitely across sessions; with large packs installed this leaks megabytes — `emoji_panel.dart:1638` ← `stickers_list_widget.cpp` (AyuGram uses `DocumentMedia` with session-scoped lifetime and LRU eviction from the media cache; no unbounded static maps)

- [ ] [CRITICAL] `_StickerTabState` and `_GifTabState` have **no engine event subscriptions** — `_loaded = true` guard prevents refresh after external changes (pack installed via link, GIF saved from chat, pack updated server-side); panel content silently goes stale — `emoji_panel.dart:1654` ← `stickers_list_widget.h` (`refreshRecent()`, `refreshStickers()`, `beforeHiding()`/`afterShown()` hooks called by `TabbedSelector` on every relevant update)

- [ ] [MAJOR] `_kStickerFooterHeight = 44.0` — AyuGram's sticker icon strip is `footer: 36px`; Dart renders it 22% too tall — `emoji_panel.dart:1605` ← `chat_helpers.style:749`

- [ ] [MAJOR] Sticker long-press preview is **dismissed by backdrop tap**, not on press release — AyuGram shows preview after `QApplication::startDragTime()` ms hold and dismisses it immediately in `mouseReleaseEvent` (the user never needs to tap anything); Dart's `OverlayEntry` requires an explicit backdrop tap or pan gesture — `emoji_panel.dart:2284` ← `stickers_list_widget.cpp:2245`

- [ ] [MAJOR] `_StickerCell` and `_GifCell` play looping animated content (Lottie / WebM) but have **no `RepaintBoundary`** — every animation frame triggers repaint of the entire surrounding list; `_CustomEmojiCell` correctly wraps in `RepaintBoundary` (line 1364) but the sticker and GIF cells do not — `emoji_panel.dart:2543` / `emoji_panel.dart:3522`

- [ ] [MAJOR] `_TabContent.build()` nests a `LayoutBuilder` inside an `AnimatedBuilder` — the animation controller fires at ~60 fps during tab-slide transitions; each frame triggers a full layout recalculation via `LayoutBuilder`; the width value (`constraints.maxWidth`) does not change between frames and the layout pass is wasted — `emoji_panel.dart:575`

- [ ] [MAJOR] Sticker preview `OverlayEntry` uses a **single** `Future.delayed(const Duration(milliseconds: 500))` to check for a newly-loaded file — if the file arrives after 500 ms the preview stays as a placeholder forever; no continuous polling or proper completion callback — `emoji_panel.dart:1963`

# ayu_filter — Regex filter engine data layer

## Reference files
- Dart: `dart/lib/data/ayu_filter.dart`
- C++: `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_controller.cpp`
- C++: `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_utils.cpp`
- C++: `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_cache_controller.cpp`

---

- [ ] [MAJOR] `_serviceMessageType` falls through to `if (msg.mediaType == 2) return 8` which assigns TYPE_GIF (8) to service messages with video mediaType — no such mapping exists in AyuGram; the C++ `typeOfMessage` for service items checks `media->call()`, `media->photo()`, gift types, giveaway results, and then falls back to `return 10 // TYPE_DATE` with no video→GIF case — `ayu_filter.dart:243` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_utils.cpp:604`

- [ ] [MAJOR] `extractMatchBlob` single-message path does not trim text before appending to the match blob — AyuGram does `text = extractSingle(item).trimmed()` for both single and group items; Dart trims group items (`line 271`) but skips trim for single items (`line 278`), causing a divergence: patterns anchored with `^`/`$` or that rely on no leading whitespace behave differently for single messages — `ayu_filter.dart:278` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_utils.cpp:667`

# filter_column — Audit findings

## Compared against:
- `lib_ui/ui/widgets/side_bar_button.cpp` + `side_bar_button.h`
- `SourceFiles/window/window_filters_menu.cpp`
- `SourceFiles/window/window.style` + `lib_ui/ui/widgets/widgets.style`
- `SourceFiles/ui/filter_icons.cpp`

---

- [ ] [MAJOR] Button height is fixed at `minHeight=62px` and never grows for multi-line folder labels. In C++, `SideBarButton::resizeGetHeight` adds extra height for each additional text line beyond one: `result + max(text - oneLineHeight, 0)`. In Dart, `_SideBarButtonLayout.getSize` always returns `Size(maxWidth, minHeight)` (62px). For a long folder name that wraps to 3 lines, the text starts at `textTop=40px` and extends to ~y=79px — overflowing the 62px button and visually overlapping the button below. — `filter_column.dart:1176-1178` ← `side_bar_button.cpp:109-116`

- [ ] [MAJOR] `_openFoldersSettings` always fires `engine.getSuggestedFolders` on every invocation, even on repeat calls after suggestions are already loaded. C++ short-circuits: `if (filters->suggestedLoaded()) { showSettings(); return; }` — no network call if data is fresh. Dart has no such guard: it unconditionally calls the engine, adds a round-trip latency on every repeated open of the folders settings screen, and the `_waitingSuggested` flag only prevents double-fire (not cache reuse). — `filter_column.dart:650-660` ← `window_filters_menu.cpp:418-429`

# folders_settings_screen — Folders Settings Screen Audit

- [ ] [CRITICAL] No drag-to-reorder for folder list — the main folder list uses a plain `for` loop with `_FolderRow` items and no `ReorderableListView`, `DragTarget`, or any reorder mechanic. AyuGram's `FilterRowButton` is built inside a reorderable wrap, and the full `state->save` machinery commits the new order to the server. Users cannot drag folders to reorder them at all — `folders_settings_screen.dart:393-406` ← `settings_folders.cpp:466-541`

- [ ] [CRITICAL] `createFolder` and `editFolder` bridge methods missing `newChats`/`existingChats` parameters — the engine bridge at `engine_service.dart:850-886` (createFolder) and `engine_service.dart:913-951` (editFolder) do not include `new_chats` or `existing_chats` in the JSON payload. The UI correctly collects `_newChats`/`_existingChats` state (lines 1225-1226) and returns them in the `FolderInfo` result (lines 1734-1735), but they are silently dropped before hitting the backend. Any folder created or edited with these flags set will have them ignored — `engine_service.dart:850-886` ← `settings_folders.cpp:58` (`Flag::f_contacts` etc. show all flags are required)

- [ ] [CRITICAL] Tags toggle hidden from non-premium users entirely — `folders_settings_screen.dart:453-454` gates the `_TagsToggle` widget on `effectivePremium == true`. AyuGram shows the toggle to ALL users whenever `session->premiumPossible()` (line 996 `settings_folders.cpp`); non-premium users see a locked toggle that fires `ShowPremiumPreviewToBuy` on tap (line 1048). The Dart hides the feature from non-premium users rather than showing it with a paywall — `folders_settings_screen.dart:453-454` ← `settings_folders.cpp:996-1048`

- [ ] [CRITICAL] `_showPremiumPurchaseDialog` is a stub placeholder — `folders_settings_screen.dart:4839-4884` shows a static dialog telling users to "subscribe in the official Telegram app." It does nothing — no deeplink, no in-app payment, no premium preview screen. This is called from `SimpleLimitBox` (line 4818) and from tag color chip (line 2007-2008) whenever premium is required. AyuGram calls `ShowPremium` / `ShowPremiumPreviewToBuy` which opens the actual premium purchase flow — `folders_settings_screen.dart:4839-4884` ← `settings_premium.h` (`ShowPremium`, `ShowPremiumPreviewToBuy`)

- [ ] [MAJOR] Non-chatlist folder with invite links deleted without confirmation — `folders_settings_screen.dart:174-183` checks `folder.isChatList` to decide whether to show a confirmation dialog, but skips it for all other folders. AyuGram's `markForRemoval` (line 423) additionally shows `Ui::MakeConfirmBox` with "Are you sure?" when `row->filter.hasMyLinks()` is true, even for non-chatlist filters. Regular folders that have been made shareable can be silently deleted — `folders_settings_screen.dart:174-183` ← `settings_folders.cpp:423-435`

- [ ] [MAJOR] `_ChatlistFolderRemovalDialog` has no Cancel button — `folders_settings_screen.dart:4498-4638` shows a "Remove" / "Remove and leave N" button but no Cancel. The dialog can only be dismissed by tapping outside (barrier is dismissible by default) — there is no explicit cancel action. AyuGram's equivalent `Ui::MakeConfirmBox` always includes a cancel button — `folders_settings_screen.dart:4598-4638` ← `settings_folders.cpp:424-435`

- [ ] [MAJOR] `showEditFolderBox` (public, used from `chat_list_panel.dart` and `filter_column.dart`) omits `newChats`/`existingChats` — the call at `folders_settings_screen.dart:79-91` passes `result.contacts`, `result.groups` etc. but not `result.newChats` or `result.existingChats`. Even if the bridge were fixed, this call site would still drop these flags. This path is triggered from right-click context menus and the folder tab bar — `folders_settings_screen.dart:79-91` ← `engine_service.dart:913-951`

# forum_topic_icon — Bubble path and stroke wrong for 5/7 colors; animation loops forever

- [ ] [CRITICAL] `_bubblePathD` uses the blue/gray SVG path (`M42,4.47368421 C52.6535116...`) for ALL 7 colors, but yellow/green/violet/rose/red SVGs use a distinct path (`M42,4.42105263 C52.6675181...`) — different control points throughout; 5 of 7 icons render the wrong bubble shape — `forum_topic_icon.dart:153` ← `AyuGram/Telegram/Resources/art/topic_icons/yellow.svg:15` (and green.svg, violet.svg, rose.svg, red.svg)

- [ ] [CRITICAL] Stroke width hardcoded as `2.94736842 * s` for all colors, but yellow/green/violet/rose/red SVGs specify `stroke-width="2.84210526"` (~3.4% thinner); blue and gray correctly use `2.94736842` — `forum_topic_icon.dart:310` ← `AyuGram/Telegram/Resources/art/topic_icons/yellow.svg:15`

- [ ] [MAJOR] `CustomEmojiTopicIcon` always calls `_lottieController!.repeat()` (infinite loop), but AyuGram uses `kUserpicLoopsCount = 1` for custom-emoji topic icons in the dialog list (`LimitedLoopsEmoji` plays once then stops); `TopicIconWidget` exposes no `loopCount` parameter so dialog-list callers cannot configure this — `forum_topic_icon.dart:603` ← `AyuGram/Telegram/SourceFiles/data/data_forum_topic.cpp:810`

# ghost_settings_page — Ghost/Spy settings page audit

- [ ] [CRITICAL] `setLocalPremium` updates local state only, never calls engine — toggling "Local Premium" is purely cosmetic and the Go engine never unlocks premium features — `dart/lib/state/app_state.dart:1427` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ayu_settings.cpp:678` (`setLocalPremium` saves + emits reactive change used throughout the C++ codebase; `updateConfig()` in `dart/lib/bridge/engine_service.dart:5215` has no `localPremium` parameter)

- [ ] [CRITICAL] `setDisableAds` updates local state only, never calls engine — toggling "Disable Ads" is purely cosmetic and the Go engine never suppresses sponsored content — `dart/lib/state/app_state.dart:1434` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ayu_settings.cpp:577` (`setDisableAds` saves + emits reactive change consumed by ad-suppression logic; `updateConfig()` in `dart/lib/bridge/engine_service.dart:5215` has no `disableAds` parameter)

# hamburger_drawer — Menu order, label, and visibility issues

- [ ] [CRITICAL] Archive row placed at bottom of menu instead of top. AyuGram calls `setupArchive()` before `setupMenu()` (constructor line 358 vs 359), so the Archive button is the **first** item in `_menu`. Dart puts it last, after all other rows including AyuGram-specific toggles — `hamburger_drawer.dart:476` ← `window_main_menu.cpp:358-359`

- [ ] [MAJOR] LRead and SRead rows are in the wrong position. AyuGram inserts them between Saved Messages (line 759) and Settings (line 838): LRead at line 767, SRead at line 784. Dart places them after Night Mode and Ghost Mode (lines 410–458), reversing their order relative to Settings — `hamburger_drawer.dart:410-458` ← `window_main_menu.cpp:767-813`

- [ ] [MAJOR] SRead row label is wrong: Dart shows "Mark Stories as Viewed" but AyuGram's `ayu_SReadMessages` translates to **"Read on Server"** — a feature that sends read receipts for all chats, not just stories. This misleads users about what the button does — `hamburger_drawer.dart:434` ← `Telegram/Resources/langs/lang.strings:8242`

- [ ] [MAJOR] LRead row label mismatch: Dart shows "Mark All Read (Silent)" but AyuGram's `ayu_LReadMessages` translates to **"Read on Local"** — `hamburger_drawer.dart:413` ← `Telegram/Resources/langs/lang.strings:8241`

- [ ] [MAJOR] PlainShadow divider after My Profile/Bots block is always rendered. AyuGram only adds it when `showMyProfileInDrawer() || showBotsInDrawer()` (line 720). Dart renders it unconditionally at lines 228–234, leaving a spurious separator when both those rows are hidden — `hamburger_drawer.dart:228-234` ← `window_main_menu.cpp:720-723`

- [ ] [MAJOR] Archive context menu shows "Expand/Collapse" even when archive is in main menu. AyuGram only adds the expand/collapse action when `!inmenu` (line 1854). Dart always includes it (line 549–552) regardless of whether `archiveInMainMenu` is true — `hamburger_drawer.dart:549-552` ← `window_peer_menu.cpp:1854-1861`

## info_panel — Critical media interaction and layout dimension issues

- [ ] [CRITICAL] `_GridCell` has no tap/gesture handler — photos and videos cannot be opened from the shared media grid — `info_panel.dart:6894` ← `AyuGram/SourceFiles/info/profile/info_profile_actions.cpp`
- [ ] [CRITICAL] `_GifCell` has no tap/gesture handler — GIFs cannot be opened from the shared media grid — `info_panel.dart:7120` ← `AyuGram/SourceFiles/info/profile/info_profile_actions.cpp`
- [ ] [CRITICAL] `_RoundListItem._onTap()` calls `audio.playVoice()` for round video messages instead of opening a video player — `info_panel.dart:6737` ← `AyuGram/SourceFiles/info/profile/info_profile_actions.cpp`
- [ ] [MAJOR] Cover `minHeight = 56.0` vs AyuGram `infoTopBarHeight: 54px` — 2px deviation — `info_panel.dart:550` ← `AyuGram/SourceFiles/styles/style_info.h`
- [ ] [MAJOR] Cover `maxHeight = 236.0` vs AyuGram `infoProfileTopBarHeightMax: 234px` (180+54) — 2px deviation — `info_panel.dart:549` ← `AyuGram/SourceFiles/styles/style_info.h`
- [ ] [MAJOR] No `infoMinimalWidth: 324px` or `infoDesiredWidth: 392px` constraints enforced on the panel — `info_panel.dart:273` ← `AyuGram/SourceFiles/styles/style_info.h`
- [ ] [MAJOR] `_UserProfilePage` shows no action buttons row (Message, Mute, Call) for group member profiles — `info_panel.dart:3079` ← `AyuGram/SourceFiles/info/profile/info_profile_top_bar.cpp:776`
- [ ] [MAJOR] `_MembersSection._sortedMembers()` sorts online-first then alphabetical, missing owner/admin priority tier before online status — `info_panel.dart:7415` ← `AyuGram/SourceFiles/info/profile/info_profile_members.cpp`
- [ ] [MAJOR] `_SharedMediaSubPage` receives a `scrollController` param but uses its own internal `_contentScrollController` — outer nav-stack scroll position is never saved or restored for this page — `info_panel.dart:3224` ← `AyuGram/SourceFiles/info/info_flexible_scroll.cpp`

## input_dialogs — Behavioral and wiring issues across 5 dialog boxes

- [ ] [CRITICAL] `showEditInviteLinkBox` has no `isGroup` parameter — AyuGram uses `data.isGroup` to conditionally display different approval-toggle descriptions ("Anyone with this link can join your group" vs "...channel"), but the Dart implementation always shows a single hardcoded string regardless of chat type — `input_dialogs.dart:1259` ← `AyuGram/ui/boxes/edit_invite_link.cpp:126-133`

- [ ] [CRITICAL] `CreatePollBox` submit is not wired to `SendMenu` / schedule flow — AyuGram integrates `SendMenu::DefaultCallback`, `SendMenu::SetupMenuAndShortcuts`, and `PaidSendButtonText` to allow scheduled sends, paid sends, and custom send options via right-click context menu on the Create button. The Dart implementation pops a plain `CreatePollResult` with no `sendOptions` field and no schedule/send-menu support — `input_dialogs.dart:2005` ← `AyuGram/boxes/create_poll_box.cpp:3002-3036`

- [ ] [CRITICAL] Poll options limit is hardcoded at 32 instead of coming from `appConfig->pollOptionsLimit()` — AyuGram reads the live server-side limit from the app config and also shows the correct "X more options" / "maximum" label reactively as the user types. The Dart always uses `_kMaxOptions = 32` and rebuilds the label in `build()`. If the server raises the limit, the Dart silently rejects options — `input_dialogs.dart:1826` ← `AyuGram/boxes/create_poll_box.cpp:2509-2513`

- [ ] [MAJOR] `showEditInviteLinkBox` uses a hardcoded approval-description string instead of the contextual group/channel variant — Dart shows `'Users will request to join and admins will approve them.'` and `'Anyone with this link can join your group.'` for all chats regardless of whether the chat is a group or channel, and ignores `isGroup`. AyuGram conditionally switches between `tr::lng_group_invite_about_approve()` / `tr::lng_group_invite_about_approve_channel()` and their no-approve counterparts — `input_dialogs.dart:1566-1570` ← `AyuGram/ui/boxes/edit_invite_link.cpp:126-133`

- [ ] [MAJOR] `showEditInviteLinkBox` label field is placed above the expire/usage sections, but AyuGram places the label field immediately after the approval/subscription toggles and adds a divider with "about" text below it (`tr::lng_group_invite_label_about`). Dart omits the divider-label below the label field entirely — `input_dialogs.dart:1611-1623` ← `AyuGram/ui/boxes/edit_invite_link.cpp:160-172`

- [ ] [MAJOR] `showEditInviteLinkBox` missing expire/usage about-text dividers — AyuGram renders `tr::lng_group_invite_expire_about` below the expire section and `tr::lng_group_invite_usage_about` below the usage section as divider labels. Dart has no such contextual hints — `input_dialogs.dart:1624-1735` ← `AyuGram/ui/boxes/edit_invite_link.cpp:209-222`

- [ ] [MAJOR] `_CreatePollContentState` — "Allow Adding Options" lock condition differs from AyuGram. Dart disables it when `_quiz || (!_anonymous && !_showWhoVoted)`, but AyuGram locks it when `quiz.toggled() || (showWhoVoted && !showWhoVoted->toggled())`. Dart's condition `!_anonymous && !_showWhoVoted` is wrong — the correct condition is `showWhoVoted present && NOT toggled` (i.e. the option is only available when showWhoVoted IS on, not the inverse). This produces incorrect unlock behavior — `input_dialogs.dart:2456` ← `AyuGram/boxes/create_poll_box.cpp:2762-2764`

- [ ] [MAJOR] `_CreatePollContentState._allowRevoting` lock behavior differs — Dart disables revoting toggle only when `_quiz` is enabled (via `locked: _quiz`). AyuGram additionally locks it via `_disabled & PollData::Flag::RevotingDisabled`, meaning the server-side `RevotingDisabled` flag is not respected in the Dart implementation — `input_dialogs.dart:2461-2468` ← `AyuGram/boxes/create_poll_box.cpp:2773-2774`

- [ ] [MAJOR] `_UsernameBoxContentState` description text is hardcoded in English. AyuGram's username box uses reactive localized strings via `tr::lng_username_description1(tr::rich)` and `tr::lng_username_description2(tr::rich)` with proper rich-text entity rendering and combined via `rpl::combine`. Dart uses a hardcoded static `TextSpan` tree, meaning this text is never localized or updated if the server changes the wording — `input_dialogs.dart:447-461` ← `AyuGram/boxes/username_box.cpp:334-353`

- [ ] [MAJOR] `_UsernameBoxContentState` check-info type `Default` with "choose username" hint text is missing — AyuGram fires `UsernameCheckInfo::Type::Default` with `tr::lng_username_choose(tr::now)` when no check is in progress and no status exists. Dart shows nothing (`_statusText = null`) in this state, omitting the contextual hint shown in AyuGram — `input_dialogs.dart:209-216` ← `AyuGram/boxes/username_box.cpp:246-252`

- [ ] [MAJOR] `_CreatePollContentState` — description field has no max length enforced at submission and no count warning triggered by field height. AyuGram's `setupDescription` does not call `setMaxLength()` on the description field (unlike question/solution which do), meaning it is soft-limited only via the submit validation warning. Dart enforces a hard `LengthLimitingTextInputFormatter(_kDescriptionLimit)` which may reject valid input if the server-side limit differs — `input_dialogs.dart:2318-2320` ← `AyuGram/boxes/create_poll_box.cpp:1317-1368`

# instant_view — Audit findings

## Sources compared
- Dart: `dart/lib/ui/instant_view.dart`
- AyuGram: `Telegram/SourceFiles/iv/iv_controller.cpp`, `iv_prepare.cpp`, `iv_delegate_impl.cpp`, `iv.style`

---

- [ ] [CRITICAL] Ctrl+M minimize shortcut is a no-op stub — `instant_view.dart:228-230` ← `iv_controller.cpp:1022-1023` (`processKey` calls `minimize()` → `_window->setWindowState(Qt::WindowMinimized)`; Dart has empty handler with comment "uses platform channel on desktop" but no actual platform channel call)

- [ ] [CRITICAL] Rich text `'image'` type silently dropped — `instant_view.dart:1706-1707` ← `iv_prepare.cpp:1042-1057` (AyuGram emits `<img>` tag with `src` and `width`/`height` for `MTPDtextImage`; Dart returns `null`, so inline images in article body text are never rendered)

- [ ] [CRITICAL] Zoom minimum incorrectly clamped to 100% — `instant_view.dart:60,202-203` ← `iv_controller.cpp:62-65,152-154` (`kZoomStep=10`, minus button just decrements with no lower bound; Dart `.clamp(100, 300)` prevents zooming out below 100%, a valid and used feature)

- [ ] [CRITICAL] Channel join state not reactive to engine events — `instant_view.dart:2856-2874` ← `iv_controller.cpp:574-598` (AyuGram uses `fillInChannelValuesScript` + `toggleInChannelScript` to reactively push join-state changes into the page via JavaScript; Dart `_checkMembership` only reads `chatState.chats` once at `initState`, so if the user joins/leaves the channel elsewhere the Join button never updates)

- [ ] [MAJOR] Back/Forward navigation buttons placed on wrong side — `instant_view.dart:251-263` ← `iv_controller.cpp:444-446` (AyuGram places Back/Forward on the LEFT of the title bar via `_back->moveToLeft(0,0)` with animated slide-in; Dart puts them in `AppBar.actions` on the RIGHT side with instant show/hide, no animation)

- [ ] [MAJOR] Back button never shown as disabled — `instant_view.dart:252-256` ← `iv_controller.cpp:886-898` (AyuGram toggles back button visibility based on `canGoBack || canGoForward` and disables the entity when `!canGoBack`; Dart uses `if (_canGoBack)` so the button completely disappears rather than being visible-but-disabled when only forward history exists)

- [ ] [MAJOR] `processLink` context handling missing — `instant_view.dart:1646-1655` ← `iv_controller.cpp:1031-1065` (AyuGram dispatches typed events for `channel`, `join_link`, `webpage`, and `viewer` contexts from link clicks; Dart only does `onNavigateIV` or `launchUrl`, losing channel-open, join-link, and media-viewer context routing)

- [ ] [MAJOR] Audio seek bar non-interactive — `instant_view.dart:2280-2286` ← `iv_prepare.cpp` (audio rendered as HTML `<audio>` with browser native controls; Dart uses `LinearProgressIndicator` which is display-only, users cannot seek to a position by tapping/dragging)

- [ ] [MAJOR] Generic embed WebView only on mobile, silently degrades to link card on desktop — `instant_view.dart:2612-2626` ← `iv_controller.cpp:647-901` (AyuGram renders all embeds inside the IV WebView so they work on all platforms; Dart wraps in `_EmbedWebView` only when `Platform.isAndroid || Platform.isIOS`, on Linux/Windows/macOS the embed block shows a link card instead)

- [ ] [MAJOR] `Image.file` decoded at full resolution without cache hints — `instant_view.dart:1780-1782,1924-1925` ← (AyuGram renders photos via WebView which naturally respects display size; Dart loads `Image.file(file, fit: BoxFit.cover, width: double.infinity)` with no `cacheWidth`/`cacheHeight`, decoding the full-resolution file every time into memory)

# emoji_data — Emoji keyword search and prioritization

- [ ] [CRITICAL] Server keyword diff deletions are never applied — `EmojiKeywordsResult` model has no `deleted` field (`engine_models.dart:3701-3711`), and the call site always passes `deleted: const {}` (`chat_view.dart:3800`). AyuGram's `ApplyDifference` handles `MTPDemojiKeywordDeleted` entries that remove stale keywords from the local pack; in Dart those deletions are silently discarded, so the local lang pack diverges from the server over time — `dart/lib/data/emoji_data.dart:2820` ← `AyuGram/chat_helpers/emoji_keywords.cpp:274`

- [ ] [MAJOR] `_prioritizeRecent` diverges from C++ when a recent emoji sits exactly at the `lastRecent` boundary — Dart increments `lastRecent` (`else if (idx == lastRecent) lastRecent++`), treating the item as already-prioritized and placing subsequent recents after it. C++ does NOT increment `lastRecent` in the equivalent case (`it > lastRecent` is false, no rotation, no advance), so subsequent recents are rotated to the front and push the boundary emoji back. For recents=[A,B] against results=[A,B,C], Dart produces [A,B,C] while C++ produces [B,A,C] — `dart/lib/data/emoji_data.dart:3070-3076` ← `AyuGram/chat_helpers/emoji_keywords.cpp:653-669`

- [ ] [MAJOR] No keyboard input-method language detection — AyuGram calls `QGuiApplication::inputMethod()->locale().uiLanguages()` and keeps an LRU deque of up to 4 keyboard input languages (`kKeepNotUsedInputLanguagesCount = 4`), requesting emoji keywords for whichever language the user is currently typing in. Dart only uses `appState.selectedLanguageCode`, system locale, and hardcoded `'en'` (`chat_view.dart:3781-3784`). If the user's keyboard is set to a different language (e.g., typing Arabic or Russian while the UI is in English), no emoji suggestions appear for that language — `dart/lib/data/emoji_data.dart:2910` ← `AyuGram/chat_helpers/emoji_keywords.cpp:587`

# keyboard_shortcuts — Shortcut System

## Summary
Core shortcut machinery is well-implemented and all command names, default bindings, and formatting key sequences match AyuGram 1:1. Two critical bugs in the chat-switch state machine make the Ctrl+Tab overlay permanently broken after first use.

---

- [ ] [CRITICAL] `handleKeyEvent` ignores `KeyUpEvent`, so releasing Ctrl/Meta during chat-switch overlay is never detected and the overlay cannot auto-confirm — `keyboard_shortcuts.dart:673` ← `shortcuts.cpp:965-973` (`QEvent::KeyRelease` branch calls `CancelChatSwitch(Qt::Key_Enter)` on modifier release)

- [ ] [CRITICAL] `chatSwitchStarted` is set to `true` on first Ctrl+Tab (line 1166) but the only reset is inside `resume()` (line 493), which is semantically for unpausing shortcuts after a modal, not for ending a chat-switch session — after the first Ctrl+Tab every subsequent press returns `false` at line 1165 and the overlay can never open again — `keyboard_shortcuts.dart:1165-1171,492-495` ← `shortcuts.cpp:833-841` (`CancelChatSwitch` always resets `ChatSwitchStarted = false`)

- [ ] [MAJOR] `ctrl+r` is bound to both `readChat` and `recordVoice` (lines 887-892), both with `chatRequired` scope; `readChat`'s handler (lines 1198-1201) calls a void method then unconditionally returns `true`, so `dispatch()` exits before ever calling the `recordVoice` handler — recording voice via shortcut is permanently broken — `keyboard_shortcuts.dart:887-892,1198-1201` ← `shortcuts.cpp:527-532` (AyuGram assigns both to `ctrl+r` but they fire through independent priority-ranked handlers, not one blocking the other)

- [ ] [MAJOR] During an active chat-switch overlay AyuGram routes `Left`, `Right`, `Up`, `Down`, and `Q` key events to `NavigateChatSwitch` to move within the overlay — the Dart has no `chatSwitchStarted` branch in `handleKeyEvent`, so those keys fall through to normal shortcut dispatch (navigating the chat list instead of the overlay) — `keyboard_shortcuts.dart:666-712` ← `shortcuts.cpp:34-40,844-868` (`kChatSwitchSpecialKeys` array and `NavigateChatSwitch`)

# language_box — Language box audit

## Findings

- [ ] [CRITICAL] `_switchCloudLanguage()` calls `engine.callGeneric(accountId, 'SetLanguage', {'lang_code': langCode})` which only sends a server-side preference change (Telegram API account.setContentSettings or similar). It does NOT download or apply a language pack, and there is no call to Flutter's locale machinery — the app's displayed UI language never changes. AyuGram calls `Lang::CurrentCloudManager().switchToLanguage(language)` which downloads the cloud lang pack, writes it to local storage, and re-renders the entire UI in the new language. The Flutter app has no equivalent mechanism, so language selection is purely cosmetic. — `language_box.dart:218-223` ← `language_box.cpp:1379-1392`

- [ ] [MAJOR] Share link toast says `'Link copied to clipboard'` (hardcoded). AyuGram shows `tr::lng_username_copied(tr::now)` which is the localised "Link copied." toast used consistently everywhere in the app for copied links. — `language_box.dart:808` ← `language_box.cpp:517`

- [ ] [MAJOR] `_SkipLanguagesEditor` search (`_sortedFilteredLangs`, line 952-961) splits names into words and does word-prefix matching (`any word starts with needle`). AyuGram's `Row::filtered()` in `choose_language_box.cpp` does a full-string prefix match: `_status.startsWith(query, Qt::CaseInsensitive) || _titleText.startsWith(query, Qt::CaseInsensitive)`. For multi-word names like "Western Frisian", searching "fris" matches in Dart (word "frisian" starts with it) but NOT in AyuGram (full string "Western Frisian" does not start with "fris"). — `language_box.dart:952-961` ← `choose_language_box.cpp:164-167`

## media_viewer — Audit chunk 72

### Critical stubs and missing wiring

- [ ] [CRITICAL] `_recognizeText()` is a complete stub — `_isTextRecognitionAvailable` is hardcoded `false`, function body returns immediately with no actual OCR call. AyuGram fully implements platform-specific OCR (macOS: `VNRecognizeTextRequest`, Windows: WinRT OCR, Linux returns `false` from `Platform::TextRecognition::RecognizeText`). The toolbar "Recognize Text" button is conditionally hidden because of the `false` flag, but the entire feature is unimplemented — `media_viewer.dart:3378-3383` ← `media_view_overlay_widget.cpp:3396,5704`

- [ ] [CRITICAL] Story viewed/read event is never reported to the engine. When `_loadStory()` is called and content is shown, there is zero call to mark the story as viewed (no `engine.markStoryViewed`, `engine.readStory`, or equivalent). AyuGram sends `stories.incrementStoryViews` as part of the view flow — the Dart code never does this, meaning stories always appear unread from the server's perspective — `media_viewer.dart:6481-6514` ← `media/stories/media_stories_view.cpp` (stories view tracking)

- [ ] [CRITICAL] No engine call to download not-yet-downloaded media in the viewer. When `msg.mediaLocalPath.isEmpty`, the viewer shows a placeholder (`_buildErrorPlaceholder`) but never requests the engine to download the file. AyuGram triggers streaming/download via `_document->saveFromDataSilent()` or `_photo->load()` when opening the viewer on undownloaded content — `media_viewer.dart:2017-2027` ← `media_view_overlay_widget.cpp:1419-1442`

- [ ] [CRITICAL] `_isChannelPost` is detected by checking `_currentMessage.views > 0` which is wrong — any viewed message (not just channel posts) can have `views > 0`. This causes the "View Statistics" menu item to appear for non-channel messages and calls `engine.getMessageStats` on chat messages where it's invalid — `media_viewer.dart:3251` ← `media_view_overlay_widget.cpp:2109-2117` (uses `computeOverviewType()` based on shared-media type, not view count)

- [ ] [CRITICAL] Copy/save restrictions not enforced. `noForwards` is only checked on the "Forward" menu item (`media_viewer.dart:3265`) but `copy_image`, `copy_frame`, and `save_as` menu items are shown unconditionally when `mediaLocalPath.isNotEmpty`, ignoring the `noForwards` / copy restriction flag. AyuGram calls `hasCopyMediaRestriction()` before showing copy and save-as actions in the context menu — `media_viewer.dart:3261-3263, 3278-3279` ← `media_view_overlay_widget.cpp:2022-2029, 2100-2106`

- [ ] [CRITICAL] Attached stickers context menu item missing entirely. AyuGram shows "Attached Stickers" (`lng_context_attached_stickers`) when `_photo->hasAttachedStickers()` or `_document->hasAttachedStickers()`. There is no equivalent in the Dart context menu builder — `media_viewer.dart:3253-3282` ← `media_view_overlay_widget.cpp:2032-2037`

- [ ] [CRITICAL] Sponsored messages context menu not handled. AyuGram short-circuits `fillContextMenuActions` for sponsored messages and shows a dedicated sponsored menu (`Menu::FillSponsored`). The Dart viewer has no sponsored message detection or handling at all — `media_viewer.dart:3253-3282` ← `media_view_overlay_widget.cpp:1957-1968`

- [ ] [CRITICAL] Poll/retract-vote context menu item missing. AyuGram shows "Retract Vote" when viewing a poll result in the overlay. Dart has no `currentPollAnswer` check or retract action — `media_viewer.dart:3253-3282` ← `media_view_overlay_widget.cpp:1982-1996`

- [ ] [CRITICAL] "Show All Media" navigation is broken/stub. `_showAllMedia()` calls `UniClientShell.openInfoRequest?.call()` and then `InfoPanel.pushSharedMediaRequest?.call(mediaType)` — both are nullable callbacks that may be null if no one has registered them. There is no guarantee the navigation actually works, and the call relies on static registration that is never verified — `media_viewer.dart:3101-3117`

- [ ] [CRITICAL] PiP widget missing double-click to enlarge. AyuGram's `Pip::handleDoubleClick` at line 1155 calls `_closeAndContinue()` which enlarges the PiP back to full screen. The Dart `_PipWidgetState` `GestureDetector` has no `onDoubleTap` handler — single-click plays/pauses, but there is no way to expand via double-click — `media_viewer.dart:4772-4964` ← `media_view_pip.cpp:1155-1162`

### Major behavioral and wiring issues

- [ ] [MAJOR] Story viewer never pauses story timer when `_composeFocused` transitions. When the compose field loses focus, `_resumePlayback()` is called, but this incorrectly re-starts a photo timer that may have already expired. There is no guard to avoid re-advancing a completed timer, causing a spurious `_goToNext()` call — `media_viewer.dart:6327-6338` ← `media/stories/media_stories_view.cpp` (compose focus handling)

- [ ] [MAJOR] `_reportUserpic` calls `engine.reportMessage` with the message ID, not the actual userpic/photo report API. AyuGram uses `session->api().request(MTPaccount_ReportPeer(...))` or the dedicated photo/userpic report endpoint — the Dart implementation calls the general message report endpoint which is semantically wrong for a userpic report — `media_viewer.dart:3146-3169` ← `media_view_overlay_widget.cpp:2159-2200`

- [ ] [MAJOR] `_shareAtTime` copies a link to clipboard but does not offer the "Share" action (opening a share dialog / forwarding the link). AyuGram calls `shareAtTime()` which opens the full forward/share sheet with the timestamped URL. The Dart implementation just silently copies to clipboard with a toast — `media_viewer.dart:3091-3099` ← `media_view_overlay_widget.cpp:2044-2068`

- [ ] [MAJOR] Stealth mode cooldown and enabled-till state is never fetched from the engine. `showStoryStealthModeDialog` is called with only `onActivate` — `isPremium`, `enabledTill`, and `cooldownTill` are never loaded from the engine before displaying the dialog. The dialog defaults to `isPremium: context.read<AppState>().effectivePremium` but the cooldown/active-until state is always `null`, so the countdown timer never appears — `media_viewer.dart:7133-7137` ← `media/stories/media_stories_view.cpp` (stealth mode state query)

- [ ] [MAJOR] Story reply `onAttach` uploads raw files via `engine.uploadFile` — this does not include the story reply context (`replyToId: 'story:${_current.id}'`), meaning attached files are sent as plain messages without the story reply, unlike the text send path which correctly includes `replyToId` — `media_viewer.dart:7356-7364`

- [ ] [MAJOR] `_viewStatistics` shows a bottom sheet with stats, but AyuGram opens the full Statistics page (Info controller, `InfoStatisticsWidget`). The Dart implementation uses a simple `showModalBottomSheet` with only Views/Forwards/Reactions — `media_viewer.dart:3172-3227` ← `media_view_overlay_widget.cpp:2109-2117` (calls `showMediaOverview` → full info page)

- [ ] [MAJOR] "Set as Profile Photo" (`_setAsUserpic`) calls `engine.uploadProfilePhoto` — this always sets the bot account's own profile photo, ignoring whether the current context is a group/channel photo (where `api().peerPhoto().set(peer, photo)` is the right call). AyuGram correctly sets group/channel photo for admins vs own photo for personal — `media_viewer.dart:3130-3144` ← `media_view_overlay_widget.cpp:2142-2157`

- [ ] [MAJOR] `_saveMediaToDownloads` copies from `msg.mediaLocalPath` directly without checking save restrictions (`noForwards`). A message with `noForwards=true` will still be saved to disk — `media_viewer.dart:2774-2805` ← `media_view_overlay_widget.cpp:2100-2106` (`hasCopyMediaRestriction(true)`)

- [ ] [MAJOR] Story viewer loads all stories from `widget.stories` but does not handle loading more stories from the engine when approaching the end of the list. AyuGram has a paginated story load that fetches more from the API as the user navigates. The Dart viewer silently stops and calls `Navigator.maybePop()` at the end of the local list — `media_viewer.dart:6562-6569`

- [ ] [MAJOR] `_deleteMedia` shows a generic AlertDialog instead of AyuGram's `DeleteMessagesBox` which handles revoke/delete-for-everyone options and shows the appropriate message text based on peer type. The Dart dialog says only "Are you sure?" with no revoke option — `media_viewer.dart:2955-2994` ← `media_view_overlay_widget.cpp:3345-3353` (uses `Box<DeleteMessagesBox>`)

- [ ] [MAJOR] `_forwardMedia` shows a custom `_MediaForwardBox` but does not call `chatState.forwardMessages` with proper multi-message grouping or album handling — each selected destination chat triggers a separate `forwardMessages([msg.msgId], chatId)` call in a loop, which can cause rate limiting and doesn't support album forwarding — `media_viewer.dart:2940-2941`

- [ ] [MAJOR] `_messageLink` generates `https://t.me/c/${msg.chatId}/${msg.msgId}` — for private supergroups, the chatId should be stripped of the `-100` prefix (Telegram's internal format). For example, chat `-1001234567` should produce `https://t.me/c/1234567/...`. The current code uses the raw chatId with the minus prefix — `media_viewer.dart:3078-3089`

- [ ] [MAJOR] `_ThumbItem` in the gallery strip loads full-size images for photo thumbnails (`Image.file(widget.message.mediaLocalPath, ...)`) when `mediaType == 1 || mediaType == 6`. It should use `mediaThumbB64` or a downscaled cached version — loading full-size originals for 56px thumbnails wastes memory — `media_viewer.dart:3943-3951`

# message_bubble — Audit findings

- [ ] [CRITICAL] `switch_inline` inline button never opens peer chooser when `samePeer=false` — `btn.samePeer` is decoded in the model but `_onTap` always inserts into current chat's compose box regardless; for `samePeer=false` a peer-chooser should open first — `message_bubble.dart:10296–10311` ← `AyuGram/Telegram/SourceFiles/api/api_bot.cpp:454–492`

- [ ] [MAJOR] No "Retract Vote" on single-answer polls — once `_hasVoted` is set to `true` the UI locks; AyuGram exposes a context-menu action calling `sendVotes` with empty options to retract; the engine supports `votePollMulti` but the UI never triggers retraction — `message_bubble.dart:8435` ← `AyuGram/Telegram/SourceFiles/history/view/history_view_context_menu.cpp:1922`

- [ ] [MAJOR] Poll result rows show only percentage, never the absolute voter count per option; AyuGram's result row renders the integer vote count below the bar for public polls after voting — `message_bubble.dart:8259–8271` ← `AyuGram/Telegram/SourceFiles/history/view/media/history_view_poll.cpp`

- [ ] [MAJOR] `request_peer` inline button peer-type filter not applied — `_showPeerSelectionDialog` shows all chats from `chatState.chatsForAccount(activeId)` with zero filtering; AyuGram's `ShowChoosePeerBox` reads `button->peerTypes` constraints (user/group/channel/bot, admin rights, username requirements) and filters accordingly — `message_bubble.dart:10400–10505` ← `AyuGram/Telegram/SourceFiles/boxes/peers/choose_peer_box.cpp`

- [ ] [MAJOR] Collapsible blockquote not implemented — the Go bridge drops the `collapsed` flag from `MessageEntityBlockquote`, and `_RichMessageText` renders all blockquotes as always-expanded with no expand/collapse toggle — `message_bubble.dart:7196–7232` ← `AyuGram/Telegram/SourceFiles/history/view/history_view_text_helper.cpp:36–43`

- [ ] [MAJOR] Telegram Stars (`XTR`) currency not handled in `_InvoiceCard` — `_formatAmount` divides all amounts by 100 (wrong for Stars which use whole units) and `_currencySymbol` lacks the `⭐` symbol; correct display is `⭐ N` with no decimal component — `message_bubble.dart:10820–10838` ← `AyuGram/Telegram/SourceFiles/payments/`

- [ ] [MAJOR] `telegram_story` web-page type opens chat via `_openChatFromUrl` instead of in-app story viewer; AyuGram calls `ShowStoryMediaBox` to open the story viewer overlay — `message_bubble.dart:8883` + `9002` ← `AyuGram/Telegram/SourceFiles/history/view/history_view_element.cpp`

- [ ] [MAJOR] Live location map image never refreshes — static `maps.telegram.org` URL is baked at render time; when new coordinates arrive via engine events the `Image.network` widget is never re-rendered with updated coordinates — `message_bubble.dart:5004–5019`

- [ ] [MAJOR] Premium sticker effect layer is empty — `_VisualMedia` allocates bounding-box space using `kPremiumMultiplier = 1.49` but renders nothing in the effect layer; AyuGram plays a separate Lottie/WEBM effect document from `DocumentData::sticker()->setData.effects` alongside the sticker — `message_bubble.dart:3460–3465` ← `AyuGram/Telegram/SourceFiles/history/view/media/history_view_document.cpp`

# my_profile_page — Edit Profile / My Profile page

- [ ] [CRITICAL] Color tab order reversed: Dart shows "Name" first (default), AyuGram shows "Profile" first (default) — `my_profile_page.dart:2040` ← `AyuGram/boxes/peers/edit_peer_color_box.cpp:2462` (`lng_settings_color_tab_profile` is tab index 0, profile wrap shown by default at line 2476)

- [ ] [CRITICAL] Profile color initial state uses name color as baseline: `_profileColorId` is initialized to `widget.currentColorId` (the name color), but there's no separate load of the user's actual current profile color; if name color ≠ profile color the profile tab always shows the wrong selection — `my_profile_page.dart:1925` ← `AyuGram/boxes/peers/edit_peer_color_box.cpp:2129` (`peerColors->colorProfileFor(peer)` independently loaded for profile section)

- [ ] [CRITICAL] Custom emoji in bio inserts Unicode fallback text, not a rich entity: `_BioEmojiSuggestion.insertText` returns `customEmoji?.emoji ?? ''` (plain Unicode), but Telegram bio requires a formatted entity for custom emoji (Premium feature); the autocomplete shows thumbnails but the actual saved bio will contain only the fallback glyph — `my_profile_page.dart:720` ← `AyuGram/settings/sections/settings_information.cpp:654` (bio uses `Ui::InputField` with entity support via `st::settingsBioMargins`)

- [ ] [MAJOR] Birthday picker allows selecting future dates within the current year: AyuGram clamps available months to `max.month()` when `year == maxYear`, and clamps days to `max.day()` when `year == maxYear && month == max.month()`; Dart's `_daysInMonth()` ignores the current date entirely, so the user can pick e.g. December 31 of the current year even if today is May — `my_profile_page.dart:3472` ← `AyuGram/ui/boxes/edit_birthday_box.cpp:108` and line `146`

- [ ] [MAJOR] Birthday privacy "Manage" / visibility link navigates to the general `PrivacySettingsScreen` instead of the birthday-specific privacy entry: AyuGram uses `u"internal:edit_privacy_birthday"_q` to open the birthday privacy section directly — `my_profile_page.dart:516` ← `AyuGram/settings/sections/settings_information.cpp:489` (`tr::lng_settings_birthday_about_link` with `edit_privacy_birthday` URL)

- [ ] [MAJOR] `_EditPeerColorBoxState._save()` save condition for profile color is wrong: `if (_profileColorId != widget.currentColorId || _profileEmojiId != 0)` compares `_profileColorId` against the initial NAME color ID (`widget.currentColorId`), not against the user's actual current profile color; if both happen to be 0 but the user changes the profile tab, the save is skipped — `my_profile_page.dart:2450` ← `AyuGram/boxes/peers/edit_peer_color_box.cpp:2501` (profile section has its own independent save button and state)

# notification_popup — Audit Findings

## Findings

- [ ] [CRITICAL] Reply text is sent as plain text without markdown formatting — `notification_popup.dart:383` (`popup.replyController.text.trim()`) ← `notifications_manager_default.cpp:1173` (`_replyArea->getTextWithAppliedMarkdown()`). AyuGram applies markdown before sending (bold, italic, code, etc.); the Dart port silently strips all formatting.

- [ ] [MAJOR] Ctrl+Enter does not submit the reply — `notification_popup.dart:1064-1072` (only `LogicalKeyboardKey.enter` handled, no Ctrl+Enter branch) ← `notifications_manager_default.cpp:1138` (`_replyArea->setSubmitSettings(Ui::InputField::SubmitSettings::Both)`). `SubmitSettings::Both` means both plain Enter AND Ctrl+Enter submit the reply. Dart handles only plain Enter; Ctrl+Enter is silently ignored.

- [ ] [MAJOR] Reply button text is not uppercased — `notification_popup.dart:979` (`'Reply'`) ← `notifications_manager_default.cpp:679` (`_reply->setTextTransform(Ui::RoundButtonTextTransform::ToUpper)`). AyuGram renders "REPLY" in all caps via `ToUpper` transform; Dart shows "Reply" in mixed case.

- [ ] [MAJOR] Reply field placeholder text differs from AyuGram — `notification_popup.dart:1085` (`hintText: 'Reply...'`) ← `notifications_manager_default.cpp:1132` (`tr::lng_message_ph()` = "Message…"). AyuGram uses the standard message placeholder; Dart uses a different custom string.

- [ ] [MAJOR] Send icon size undersized — `notification_popup.dart:1101` (`Icons.send, size: 18`) ← `window.style:75-82` (`notifySendReply: IconButton { width: 36px; height: 36px; iconPosition: point(6px, 6px) }`). AyuGram icon occupies a 24×24 area (36 − 2×6) within the 36×36 button; Dart renders an 18px icon, visually smaller than spec.

## notifications_settings_screen — Pinned-messages not persisted, ringtone selection not saved to engine, notification preview always shows identical text

- [ ] [CRITICAL] Pinned messages toggle (`_buildEventsSection`) updates local AppState only — never calls engine to persist the setting. AyuGram saves via `Core::App().settings().setNotifyAboutPinned()` + `saveSettingsDelayed()`. The Dart code does `appState.setNotifPinnedMessages(v)` with zero engine call, so the toggle resets on restart — `notifications_settings_screen.dart:564-568` ← `AyuGram/settings/sections/settings_notifications.cpp:1316-1323`

- [ ] [CRITICAL] Selecting a ringtone in `_showRingtonesBox` / `_NotificationTypeSubPage` never persists the selected tone ID or volume back to the engine. The `.then()` block only calls `setState` — there is no `engine.updateDefaultNotifySettings(... soundId: ...)` or equivalent call — `notifications_settings_screen.dart:2207-2229`. AyuGram calls `settings->defaultUpdate(type, {}, {}, sound)` immediately on selection — `AyuGram/settings/sections/settings_notifications_type.cpp:550-557`

- [ ] [MAJOR] `_NotificationPreview` widget — both `displayTitle` and `displayText` produce identical strings regardless of whether `showName`/`showText` is toggled. Lines read `final displayTitle = showName ? 'UniClient' : 'UniClient'` and `final displayText = showText ? 'You have a new message' : 'You have a new message'`. The preview never reflects name/text being hidden — `notifications_settings_screen.dart:3587-3589`. AyuGram renders the actual sender name vs app-name and real message text vs generic placeholder depending on view mode — `AyuGram/settings/sections/settings_notifications.cpp:807-834`

- [ ] [MAJOR] The `_ReactionsSubPage._showFromDialog` dialog does not apply the user's selection — after the OK button calls `onChanged(selected)` inside the `.then()` branch only when `selected != current`, but the dialog returns `void` (no `Navigator.pop(result)`) so `showDialog` always resolves with `null` and `onChanged` is never reached — `notifications_settings_screen.dart:3380-3392`. AyuGram applies the selection inline via the callback passed to `ShowFromBox` — `AyuGram/settings/sections/settings_notifications_reactions.cpp:130-133`

- [ ] [MAJOR] `_RingtonesBoxDialog` volume slider only calls `setState(() => _volume = v)` — it does not call any engine method to preview or persist the volume while sliding. AyuGram calls `Core::App().notifications().playSound(session, toneValue().id, 0.01 * volume)` on each slider change for live preview — `notifications_settings_screen.dart:4406-4412` ← `AyuGram/settings/sections/settings_notifications_type.cpp:522-529`

- [ ] [MAJOR] Exception rows show "Muted"/"Unmuted" status but the status is derived from `_NotifException.isMuted` which is set from `exc['muted']` in `_loadExceptions`. The `_NotifException` field is called `isMuted` but the engine returns key `'muted'` — this is fine — however when `onRemove` fires the item is removed from `_exceptions` list locally but the exception count returned to the parent page via `Navigator.pop(_exceptions.length)` in `PopScope` will be 0 if all exceptions are removed, yet AyuGram uses a live reactive `_count` that updates whenever an exception is cleared via the `resetToDefault` callback, so the count stays consistent. The Dart implementation does match except: the `PopScope.onPopInvokedWithResult` path (line 1811) `Navigator.pop(_exceptions.length)` is correct but the `AppBar.onPressed` path (line 1821) also pops with `_exceptions.length` — both paths are consistent, no issue here. (Downgraded — not a bug.)

- [ ] [MAJOR] The notification monitor hover preview (`_showSampleNotifications` on Linux) fires `Process.run('notify-send', ...)` for every hover enter on any corner zone — this sends real OS notifications on mouseover, not just on corner click. AyuGram shows internal `SampleWidget` overlays on hover and only changes the setting on mouse-press+release. The Dart code emits OS popups continuously as the mouse moves across corner regions — `notifications_settings_screen.dart:974-983` ← `AyuGram/settings/sections/settings_notifications.cpp:568-614`

## payment_panel — Checkout panel missing critical flows and save-to-server logic

- [ ] [CRITICAL] "Save information" checkbox entirely missing from card entry form — AyuGram always shows a save-to-server checkbox when `canSaveCredentials` is true; the `saveOnServer` flag on `NewCredentials` controls whether `MTPDinputPaymentCredentials::Flag::f_save` is sent; Dart form collects card data but never asks user and always submits without the flag — `payment_panel.dart:1519–1756` ← `AyuGram/payments/ui/payments_edit_card.cpp:369–380` and `payments_form.cpp:962–965`

- [ ] [CRITICAL] "Save information" checkbox entirely missing from personal-info edit dialogs (name/email/phone/shipping) — AyuGram's `EditInformation` always adds `_save = Checkbox("Save information", true)` and passes `_save->checked()` as the `save` field of `RequestedInformation`; Dart dialogs never ask and always call `validatePaymentInfo(… save: true)` unconditionally — `payment_panel.dart:1885–2018, 2020–2176` ← `AyuGram/payments/ui/payments_edit_information.cpp:205–217`

- [ ] [CRITICAL] TmpPasswordRequired flow is completely unimplemented — AyuGram fires `TmpPasswordRequired` when a saved credential is selected and there is no valid tmp-password cached; it then calls `requestPassword()` which opens a `PasscodeBox` to get the cloud-password and then calls `Form::submit(result)` which fetches `MTPaccount_GetTmpPassword`; the Dart side detects `password_missing` at form-load time but never handles the case where a saved card is chosen but the tmp-password has expired at submit time — `payment_panel.dart:409–415, 744–776` (only handles missing password at load) ← `AyuGram/payments/payments_form.cpp:929–933`, `payments_checkout_process.cpp:405–408, 846–866`

- [ ] [CRITICAL] WebView payment form: `payment_form_submit` JavaScript message is never parsed — AyuGram's webview payment page posts `["payment_form_submit", "{"title":"…","credentials":{…}}"]` via `window.TelegramWebviewProxy.postEvent`; the C++ handler in `payments_panel.cpp:600–603` receives this JSON array and calls `panelWebviewMessage` which extracts `.credentials` object and `.title` string, setting `saveOnServer` from the save-checkbox state; the Dart `_PaymentWebViewPage` only handles a `tg://` URL navigation to extract `payment_token` — will completely miss the standard credential submission path that doesn't redirect to a tg:// URL — `payment_panel.dart:2600–2632` ← `AyuGram/payments/ui/payments_panel.cpp:600–626`, `payments_checkout_process.cpp:681–729`

- [ ] [CRITICAL] `performInitialSilentValidation` entirely absent — AyuGram silently calls `validateInformation(saved)` right after `FormReady` when all required fields are already filled in the saved info, so shipping options are pre-resolved before the user even clicks; if that silent validation fails the error is swallowed and form is still shown; without this, a form that needs shipping options will always show "Not selected" even when shipping address is already saved and accepted by the bot — `payment_panel.dart` (no such call exists) ← `AyuGram/payments/payments_checkout_process.cpp:381–383, 956–968`

- [ ] [MAJOR] `VerificationNeeded` result from `SendPaymentForm` is not handled — AyuGram's `Form::submit` can receive `MTPDpayments_paymentVerificationNeeded` which fires `VerificationNeeded{url}`, which the checkout process turns into an embedded webview (keeping the panel open with a "Processed by …" footer); Dart's `sendPaymentForm` engine call can return a `verify_url` field but the Dart side has no code path for it — after `sendPaymentForm` succeeds Dart always transitions to `_PanelState.done` and pops — `payment_panel.dart:479–489` ← `AyuGram/payments/payments_form.cpp:970–973`, `payments_checkout_process.cpp:416–425`

- [ ] [MAJOR] `REQUESTED_INFO_INVALID`, `SHIPPING_OPTION_INVALID`, `PAYMENT_CREDENTIALS_INVALID`, `PAYMENT_CREDENTIALS_ID_INVALID`, and `TMP_PASSWORD_INVALID` error codes from Send step are not handled — AyuGram maps all four to a generic "payment failed" toast plus a second toast about not being billed, and `TMP_PASSWORD_INVALID` triggers `requestPassword()` again; Dart's catch block only handles a subset of error codes and maps none of these four — `payment_panel.dart:492–563` ← `AyuGram/payments/payments_checkout_process.cpp:560–567`

- [ ] [MAJOR] `PROVIDER_ACCOUNT_INVALID` / `PROVIDER_ACCOUNT_TIMEOUT` Form-level errors not handled — AyuGram shows a critical error overlay (replaces panel content) for these errors; Dart only shows a generic error state — `payment_panel.dart:400–407` ← `AyuGram/payments/payments_checkout_process.cpp:457–464`

- [ ] [MAJOR] Country code in shipping address and card billing-country uses raw 2-letter text field instead of a country picker — AyuGram's `EditInformation` and `EditCard` use the proper countries dropdown (`Countries::Instance()`) so the user selects a country by name; the address-display in the summary also calls `Countries::Instance().countryNameByISO2()` to show the country name; Dart renders a raw `TextField` accepting 2-char ISO code, shows raw ISO code in the summary label — `payment_panel.dart:1940–1956, 2381–2400` ← `AyuGram/payments/ui/payments_form_summary.cpp:513–520`

- [ ] [MAJOR] Tip value shown inline in price list even when tip is 0 — AyuGram only shows the tips row (with a clickable link) when `tipsMax > 0` (tips are allowed) and only displays the tips line when a non-zero tip is selected; the custom tip dialog in the Dart panel shows an extra "Other" button row unconditionally at the bottom of the tip button grid even if no suggested tips exist — `payment_panel.dart:1300–1326` ← `AyuGram/payments/ui/payments_form_summary.cpp:357–367, 373–377`

# peer_short_info — Peer Short Info Box Audit

## Findings

- [ ] [MAJOR] Context menu includes "Report", "Delete Contact", and "Block User" items that AyuGram's ShortInfoBox never has — AyuGram's standard `PrepareShortInfoBox` only adds "Open in New Window" via its `menuFiller` callback; Report/Delete/Block belong to the full Info panel — `peer_short_info.dart:405-428` ← `prepare_short_info_box.cpp:504-513`

- [ ] [MAJOR] Profile fields (bio, phone, username, birthday, notes, personal channel) are fetched once on open via `_loadProfile()` and never reactively updated — AyuGram uses `FieldsValue(peer)` which is a reactive stream monitoring `Name | PersonalChannel | PhoneNumber | Username | About | Birthday | ContactNote` flags and re-renders immediately on any peer data change; the Dart box will show stale data if the peer updates while open — `peer_short_info.dart:297-327` ← `prepare_short_info_box.cpp:203-247`

## photo_crop_editor — Paint mode, text tools, export, persistence

- [ ] [CRITICAL] Brush tool state is never persisted to disk and never loaded back: AyuGram serializes all 5 brush colors+sizeRatios to `Core::App().settings().photoEditorBrush()` on every brush change and deserializes them at startup. Dart `_toolBrushes` is built from hardcoded defaults every time `_PhotoCropEditorState.initState()` runs — selecting a custom color and closing the editor loses it permanently. — `photo_crop_editor.dart:405-408` ← `AyuGram/editor/photo_editor.cpp:233-234,356-372`

- [ ] [CRITICAL] Text items have only one style (plain colored text). AyuGram's `ItemText` supports three `TextStyle` variants: `Plain`, `Framed` (colored background, auto black/white text for contrast), and `SemiTransparent` (semi-transparent bg auto-matching text brightness). The Dart `_TextAnnotation` has no `textStyle` field and no style-toggle button — `Framed` and `SemiTransparent` modes are completely missing. — `photo_crop_editor.dart:149-225` ← `AyuGram/editor/scene/scene_item_text.cpp:261-370`

- [ ] [CRITICAL] `_applyCropAndExport` draws the base image twice onto the same canvas under the same transform. Line 1054 draws `_image!` onto the canvas (as the base layer). Then `drawExportImage()` at line 1071 is a second identical draw used only inside the blur-mask save-layer. After the blur loop, the function falls through to draw regular strokes and text annotations — on top of a canvas that already has the image painted at line 1054. This double-draw causes the base image to be composited over itself, producing a visually wrong (over-saturated / double-painted) result for any image with non-full-opacity areas (PNGs with alpha). — `photo_crop_editor.dart:1054-1064,1071-1083` ← `AyuGram/editor/photo_editor_content.cpp` (image drawn once per save path)

- [ ] [CRITICAL] The `_done()` method at line 989 deletes the cropped temp file immediately after calling `onDone`, before the caller can use it: `croppedFile.delete().ignore()` at line 1001-1002. If `onDone` is async and the caller reads the file after the future completes (e.g., uploads it), the file is already gone. AyuGram does not generate a temp file at all — it returns `PhotoModifications` (crop rect + paint scene). Callers decide their own save path. Dart should not delete the output file; that is the caller's responsibility. — `photo_crop_editor.dart:998-1003` ← `AyuGram/editor/photo_editor.cpp:417-420`

- [ ] [CRITICAL] The sticker panel (`_EditorStickerPicker`) only renders sticker thumbnails from `thumbB64` which is the pack thumbnail, not per-sticker thumbnails. `StickerInfoItem.thumbB64` is populated at the pack level in engine models, not per-sticker. When a pack has no thumb (empty `thumbB64`), all stickers in that pack fall back to rendering their emoji text. Real Telegram sticker panels show per-sticker TGS/WebP thumbnails. This means sticker selection is completely broken visually for most packs. — `photo_crop_editor.dart:3804-3833` ← `AyuGram/editor/scene/scene_item_sticker.cpp`

- [ ] [MAJOR] The color picker "custom color" button (`+`) at line 1415-1421 correctly calls `showColorPickerBox` which is a real full-featured HSV picker — this is wired. However, when a custom color is picked and added to the palette, it is appended to the visible palette row via `_paletteColorsWithCustom` but the palette row renders all colors using a fixed-size `Row` of `CustomPaint` items. The row overflows horizontally when 11 colors are shown (10 standard + 1 custom) because the `Row` has no scroll and no `MainAxisSize.min` constraint preventing overflow. AyuGram uses a fixed palette of exactly 10 colors and shows the custom color by replacing the color button ring, not by appending to the row. — `photo_crop_editor.dart:883-892,3153-3207` ← `AyuGram/editor/color_picker.cpp:265-278`

- [ ] [MAJOR] The in-canvas text editor (`_inlineTextActive` / `EditableText`) position is calculated using hardcoded pixel math: `left: _kContentMarginLeft + _inlineTextPosition!.dx - 120`. The `- 120` offset (half of the fixed 240px container width) is not responsive and will misplace the text input widget when the canvas area is narrower than 240px (e.g., on small mobile viewports), or place it partially off-screen when the text annotation is near the left edge. AyuGram opens a dedicated in-scene `QGraphicsTextItem` that clamps itself to the scene bounds automatically. — `photo_crop_editor.dart:1347-1383` ← `AyuGram/editor/scene/scene_item_text.cpp`

- [ ] [MAJOR] The brush size control (`_VerticalBrushSizeControl`) is positioned with `Positioned(left: 0, ...)` at the left edge of the screen, completely outside the image content area. AyuGram positions the size control aligned to the left edge of the canvas/image rect (`st::photoEditorBrushSizeControlLeftSkip: 0px` from the canvas, not from the screen edge). On wide-screen desktop layouts, the control appears in the black letterbox area far from the image, which is wrong. — `photo_crop_editor.dart:1332-1344` ← `AyuGram/editor/color_picker.cpp:492-495`

- [ ] [MAJOR] Undo/redo for the `_UndoKind.text` path is broken for sticker annotations: when undoing a text undo-kind, `_undoneAnnotations.add(_paintStrokes.removeLast())` is called correctly in `_paintUndo()`, but `_undoneAnnotations` stores `_TextAnnotation` objects by reference. When the sticker is a reference-typed object with a lazily decoded `_decodedImage`, the undo list holds the same mutable object. Calling `_paintRedo()` after `_paintUndo()` on a sticker can put back a different object state than what was removed (if `decodeImage()` ran async during the undo window). This is a race condition that results in sticker annotations losing their decoded image on redo. — `photo_crop_editor.dart:583-605` ← `AyuGram/editor/controllers/undo_controller.cpp`

- [ ] [MAJOR] The `_ControlBar` in paint mode has an `IgnorePointer`-wrapped "brush active" icon button at line 2780-2786 that exists purely as a decorative indicator. In AyuGram, the paint mode button in the bottom bar is the active-state `_paintModeButtonActive` which has `Qt::WA_TransparentForMouseEvents` set. The problem in Dart is this button passes `onPressed: () {}` — an empty closure — as a prop even through `IgnorePointer`. If the `IgnorePointer` is ever removed or the widget rebuilt without it, this empty callback becomes a silent no-op button which the user can tap without any feedback. The empty callback should not exist; the button should either have the correct handler or not render at all. — `photo_crop_editor.dart:2780-2786` ← `AyuGram/editor/photo_editor_controls.cpp:305-326`

# strings — Critical mismatch: fabricated notification strings

- [ ] [CRITICAL] Notification content type strings (`lngNotifPhoto`, `lngNotifVideo`, etc. at lines 44-58) do NOT exist in AyuGram source. AyuGram uses `lng_in_dlg_photo`, `lng_in_dlg_video`, `lng_in_dlg_audio`, etc. in `data_media_types.cpp` instead. These are completely fabricated strings. — `strings.dart:44-58` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_media_types.cpp` (actual strings like `lng_in_dlg_photo`, not `lng_notif_photo`)

- [ ] [CRITICAL] Reaction notification strings (`lngNotifReactedToMessage`, `lngNotifReactedToPhoto`, etc. at lines 64-88) do NOT exist in AyuGram source. AyuGram uses `lng_reaction_*` strings (e.g., `lng_reaction_photo`, `lng_reaction_video`, `lng_reaction_sticker`) in `notifications_manager.cpp:ComposeReactionNotification()`. These are completely fabricated and incompatible with actual AyuGram implementation. — `strings.dart:64-88` ← `AyuGramDesktop/Telegram/SourceFiles/window/notifications_manager.cpp:ComposeReactionNotification()` (uses `lng_reaction_*`, not `lng_notif_reacted_to_*`)

## Verified Correct Strings

- ✅ Theme warning strings (lines 15-19): match `window_theme_warning.cpp` (`lng_theme_sure_keep`, `lng_theme_reverting`, `lng_theme_keep_changes`, `lng_theme_revert`)
- ✅ Passcode strings (lines 22-28): match `window_lock_widgets.cpp` (`lng_passcode_*`)
- ✅ Report reaction strings (lines 91-94): match `info_profile_actions.cpp` (`lng_report_reaction_title`, `lng_report_reaction_about`, `lng_report_and_ban_button`)
- ✅ Auto-delete strings (lines 97-98): match `delete_messages_box.cpp` (`lng_enable_auto_delete`, `lng_edit_auto_delete_settings`)
- ✅ Paid post deletion strings (lines 101-107): match `delete_messages_box.cpp` (`lng_suggest_warn_*`)
- ✅ Forward & album strings (lines 39-41): match `notifications_manager.cpp` (`lng_forward_messages`, `lng_in_dlg_album`)
- ✅ Intro strings (lines 8-12): match `intro_signup.cpp`, `intro_step.cpp`, `intro_password_check.cpp` (`lng_intro_finish`, `lng_intro_next`, `lng_signin_cant_email_forgot`)
- ✅ AyuForward strings (lines 120-127): match `ayu_forward.cpp` (`ayu_AyuForwardStatus*`)

## Impact

The fabricated notification strings mean:
1. Flutter app has incompatible notification content type labeling vs. AyuGram Desktop
2. Reaction notifications use wrong format entirely
3. If this file is meant to sync with AyuGram localization, it will fail on all content type notifications
4. ~40 lines of completely unused/incorrect string definitions (lines 44-88)

# popup_menu — Audit findings

## popup_menu — Popup/context menu widget

- [ ] [MAJOR] Animation uses custom sine curve for both open and close, but AyuGram uses sine for open and linear for close; Dart reverses correctly (`reverseCurve: Curves.linear`) but the open-animation `_kOpenDuration` is 200ms matching `showDuration: 200` and close is 150ms matching `duration: 150` — these values are correct. However the Dart `widthFactor` starts at 0.5 and the `heightFactor` at 0.45, whereas AyuGram's `PanelAnimation` expands from the corner origin using a captured grab — the Dart implementation clips an `Align` widget at fractional factors instead of using a proper panel animation frame, producing a visible content-reveal that differs from TDesktop's full-width-then-height panel reveal — `popup_menu.dart:292-297` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/popup_menu.cpp:682-707`

- [ ] [MAJOR] Icon is rendered using a `Positioned` widget with hardcoded offsets `left: -54 + 15, top: -8 + 5` (= left:−39, top:−3) relative to its parent Stack, derived from reversing the padding `left:54, top:8`. AyuGram paints the icon at `_st.itemIconPosition` which is `point(15px, 5px)` for `menuWithIcons` — the effective icon position is (15, 5) from the item's top-left corner. The Dart calculation back-computes the same coordinates but is fragile: the Stack has `clipBehavior: Clip.none`, and the icon positioning is inverted arithmetic rather than direct pixel coordinates — `popup_menu.dart:923-933` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/widgets.style:1702`

- [ ] [MAJOR] Ripple animation color for light theme is hardcoded as `Color(0xFFe5e5e5)` which matches `windowBgRipple: #e5e5e5`, but for dark theme the ripple color is hardcoded as `Color(0xFF24303d)` — this color does not appear in any AyuGram palette or style file. AyuGram uses `menuBgRipple` → `windowBgRipple` for the ripple in all themes via `defaultRippleAnimation`. The dark ripple color is invented — `popup_menu.dart:872` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/widgets.style:712-716`

- [ ] [MAJOR] Hover background color for dark theme is hardcoded as `Color(0xFF232e3c)` which does not match `menuBgOver` → `windowBgOver`. AyuGram's `windowBgOver` is `#f1f1f1` for light (correct in Dart at line 869) but the dark value `#232e3c` is invented — it is not defined in any AyuGram palette file. The night theme uses different values not publicly available in source, but the Dart code invents a specific dark value rather than using theme-resolved colors — `popup_menu.dart:868` ← `AyuGramDesktop/Telegram/lib_ui/ui/colors.palette:11,54`

- [ ] [MAJOR] Item content height is hardcoded as `29` (with icon) or `28` (without icon) pixels. AyuGram computes height as `_st.itemPadding.top() + _st.itemStyle.font->height + _st.itemPadding.bottom()`. With `itemPadding: margins(17px, 8px, 17px, 7px)` and font height from `fsize: 13px` (which at 1x density gives approximately 15px font height), the computed height is `8 + 15 + 7 = 30px` for items without icons. With icons `itemPadding: margins(54px, 8px, 17px, 8px)` gives `8 + 15 + 8 = 31px`. The Dart hardcodes 28/29 which is ~2px short — `popup_menu.dart:1004` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/menu/menu_action.cpp:62-64` and `AyuGramDesktop/Telegram/lib_ui/ui/widgets/widgets.style:982`

- [ ] [MAJOR] Separator rendering uses `padding: symmetric(vertical: 5)` + 1px line for both variants, matching `defaultMenuSeparator: padding: margins(0px, 5px, 0px, 5px); width: 1px` but the `popupMenuWithIcons` menu uses `scrollPadding: margins(0px, 5px, 0px, 5px)` while `defaultPopupMenu` uses `scrollPadding: margins(0px, 8px, 0px, 8px)`. The Dart chooses `scrollPadding` of 5.0 when there are icons and 8.0 without, matching the C++ style correctly — this is fine. However the separator `Padding(padding: EdgeInsets.symmetric(vertical: 5))` adds 5px above and below the line, but `defaultMenuSeparator` padding is `margins(0px, 5px, 0px, 5px)` meaning no left/right margin on the line, while the Dart `Container(color: separatorColor)` stretches full width with no left/right padding — this matches — `popup_menu.dart:753-759` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/widgets.style:965-968`

- [ ] [MAJOR] Shortcut text is rendered right-aligned using a trailing `Text` widget in a `Row`. AyuGram renders shortcut text at a fixed right position via `p.drawTextRight(_st.itemPadding.right(), _st.itemPadding.top(), width(), _shortcut)`. In Dart, the shortcut is in a `Row` after an `Expanded` label — if the label is short this produces the same result, but with very long labels the `Expanded` widget can push the shortcut out, whereas AyuGram always draws shortcut at right-pad. The Dart also lacks the `itemRightSkip: 6px` gap between text/submenu arrow and the right edge visible in AyuGram (`const SizedBox(width: 6)` is only added before shortcut/arrow but not as a final right margin) — `popup_menu.dart:950-970` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/menu/menu_action.cpp:143-151` and `AyuGramDesktop/Telegram/lib_ui/ui/widgets/widgets.style:983`

- [ ] [CRITICAL] Submenu overlay is inserted into `Overlay.of(context)` but is never reinserted or repositioned if the parent menu scrolls or the window resizes. AyuGram's submenu is a native `QWidget` that repositions via `prepareGeometryFor` on geometry changes — `popup_menu.dart:594-641` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/popup_menu.cpp:390-413`

- [ ] [MAJOR] The `_AnimatedSubmenuReveal` widget uses its own `AnimationController` that starts immediately in `initState`, duplicating the animation logic from `_TelegramMenuOverlayState`. This means submenu animation is always a fresh 200ms forward play with no coordination with the parent route animation, and there is no reverse animation on submenu close — `popup_menu.dart:460-518` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/popup_menu.cpp:597-706`

- [ ] [MAJOR] `menuWithIconsAttention` style in AyuGram sets the entire menu's `itemFg` and `itemFgOver` to `attentionButtonFg` (i.e. all items are red), not just the attention item. The Dart `fullAttention` flag only colors text red on items where `item.isAttention == true`; a per-item `isAttention` flag colors only that one item. The `fullAttention` parameter animates ALL items toward `attentionColor` as route animation progresses — this is a different semantics from `menuWithIconsAttention` which sets the global foreground — `popup_menu.dart:59,241,893-894` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/widgets.style:1707-1710`

- [ ] [MAJOR] The dark theme text color for disabled items is hardcoded as `Color(0xFF3d4e5c)` which does not appear in AyuGram palettes. AyuGram uses `menuFgDisabled: #cccccc` in all themes (including dark). The light value `Color(0xFFcccccc)` matches, but the dark value is invented — `popup_menu.dart:1083-1086` ← `AyuGramDesktop/Telegram/lib_ui/ui/colors.palette:59`

- [ ] [MAJOR] The submenu arrow is drawn as a solid filled triangle using `_SubmenuArrowPainter` (5×8px). AyuGram uses `defaultMenuArrow: icon {{ "menu/submenu_arrow", windowBoldFg }}` — a dedicated icon asset. The triangle shape may differ from the actual icon asset — `popup_menu.dart:1147-1166` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/widgets.style:958`

- [ ] [MAJOR] On `AppLifecycleState.inactive/hidden/paused` the menu calls `widget.onSelected(null)` which dismisses the menu. AyuGram listens for `Integration::Instance().forcePopupMenuHideRequests()` — a signal driven by the application — and calls `hideMenu(true)`. The Dart fires dismiss on any lifecycle change to inactive (including switching to Settings, which temporarily goes inactive on some platforms), potentially closing context menus incorrectly — `popup_menu.dart:229-234` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/popup_menu.cpp:73-77`

# privacy_settings_screen — Audit

- [ ] [MAJOR] `_archiveKeepUnmuted` and `_archiveKeepFolders` are loaded from the backend and pushed back on every change (via `_pushArchiveSettings()`), but the toggle functions `_toggleArchiveKeepUnmuted` / `_toggleArchiveKeepFolders` are never called from any UI handler — dead code, users have no way to modify these two settings — `privacy_settings_screen.dart:1016-1023` ← `AyuGram/settings/sections/settings_advanced.cpp:1832-1914` (AyuGram exposes both as separate toggles in `ArchiveSettingsBox`: "Always in archive" and "Chats from folders", mapped to `UnarchiveOnNewMessage::None / NotInFoldersUnmuted / AnyUnmuted`)

# reactions_detail — Tab styling, icon, and scroll reset issues

- [ ] [MAJOR] Inactive tab pill background uses `windowBg` (panel background) instead of `contactsBgOver` (`windowBgOver` = `#f1f1f1` light-gray); unselected tabs are visually indistinguishable from the panel without the compensating border hack — `reactions_detail.dart:767` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/widgets.style:1085` (`textBg: contactsBgOver`)

- [ ] [MAJOR] "All reactions" tab uses `Icons.auto_awesome` (sparkles) instead of AyuGram's `reactionsTabAll` icon (`menu/read_reactions`, a reaction-bubbles icon) — `reactions_detail.dart:678` ← `AyuGramDesktop/Telegram/SourceFiles/ui/chat/chat.style:862` (`reactionsTabAll: icon {{ "menu/read_reactions", windowFg }}`)

- [ ] [MAJOR] Inactive tabs have an artificial `Border.all(color: windowFg.withValues(alpha: 0.12))` that does not exist in AyuGram's design; this border was introduced to compensate for the wrong background colour and should be removed when the background is corrected — `reactions_detail.dart:781-783` ← `AyuGramDesktop/Telegram/lib_ui/ui/widgets/widgets.style:1080-1098` (no border field in `MultiSelectItem`)

- [ ] [MAJOR] Scroll position is not reset to 0 when switching between tabs; `_scrollController.jumpTo(0)` is only called for the specific case of switching to the "all" tab when master cache is populated — all other tab switches (e.g. reactions→read, read→emoji, emoji→emoji) leave the list scrolled to the previous offset, causing the new tab's list to open mid-scroll — `reactions_detail.dart:379-419` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/reactions/history_view_reactions_list.cpp:247-281` (AyuGram clears and replaces rows entirely on tab switch, which implicitly resets the viewport)

# send_files_box — Album Layout Deviations

- [ ] [MAJOR] 3-item top-and-other album layout: Dart distributes bottom-row widths proportionally to aspect ratio (`bw0 = clamp(botH * cr[1], minCW, maxW-sp-minCW)`), but AyuGram always uses equal-width bottom cells (`secondWidth = (maxWidth - spacing) / 2`). Visually, Dart gives differently-sized bottom cells where AyuGram gives equal ones. — `send_files_box.dart:3793` ← `AyuGram/ui/grouped_layout.cpp:313`

- [ ] [MAJOR] 4-item left-and-other album layout: Dart caps the left cell width at 50% (`min(0.5 * (maxW - sp), ...)`), but AyuGram caps it at 60% (`min(..., (_maxWidth - _spacing) * 0.6)`). Left cell is up to 10% narrower than AyuGram reference. — `send_files_box.dart:3819` ← `AyuGram/ui/grouped_layout.cpp:387`

# settings_screen — Settings screen audit vs AyuGram Desktop

## Critical Issues

- [ ] [CRITICAL] `_ProfileHeader` avatar uses 80px (`width: 80, height: 80, radius: 40`) but spec uses `infoProfileCover.photo.size = 72px` (`infoProfilePhotoInnerSize: 72px`). Container is hard-coded to `height: 104` but spec computes `settingsPhotoTop(8) + photoHeight(72) + settingsPhotoBottom(16) = 96px`. Both avatar size and total container height are wrong — `settings_screen.dart:729,742-743` ← `AyuGram/settings/settings.style:445-446`, `AyuGram/info/info.style:527-530`, `AyuGram/settings/sections/settings_main.cpp:144-147`

- [ ] [CRITICAL] Username tap behavior is wrong: `_onUsernameTap` always opens the `showUsernameBox` edit dialog, but the spec says tapping a non-empty username copies the `t.me/<username>` link to clipboard and shows a toast; only an empty username opens the UsernamesBox — `settings_screen.dart:1010-1018` ← `AyuGram/settings/sections/settings_main.cpp:301-313`

- [ ] [CRITICAL] `_reloadSettingsData` reads wrong JSON keys from `CloudPasswordState`: reads `pwState['has_password']`, `pwState['pending_email']`, `pwState['phone_unconfirmed']` but the Go struct serializes to `hasPassword`, `emailUnconfirmedPattern`, `hasRecovery` — no `pending_email` or `phone_unconfirmed` key exists. Both validation banners will never show (always false) — `settings_screen.dart:150-154` ← `go/cores/telegram.go:18772-18779`

- [ ] [CRITICAL] Phone validation banner "Confirm" action (`onAction`) just sets `_showPhoneValidation = false` — it dismisses the banner without opening a phone number confirmation flow. AyuGram opens the security/privacy section for phone number change — `settings_screen.dart:283-285` ← `AyuGram/settings/sections/settings_main.cpp:853-955`

- [ ] [CRITICAL] Password validation banner logic is doubly broken: `_showPasswordValidation = !hasPassword && pendingEmail` — but `pendingEmail` reads `pwState['pending_email']` which is always null/false (key doesn't exist in Go struct). The correct condition from AyuGram's SetupValidatePasswordSuggestion is to check whether there is an email unconfirmed pattern (`emailUnconfirmedPattern` non-empty). Banner never shows — `settings_screen.dart:151,154` ← `go/cores/telegram.go:18772-18779`

## Major Issues

- [ ] [MAJOR] Text column left position is `22 (photoLeft) + 80 (avatar) + 10 (gap) = 112px`, which accidentally matches `settingsNameLeft=112px`, but is based on the wrong avatar size (80 vs 72). If avatar is corrected to 72px, the gap must become 18px to keep text at 112px: `22 + 72 + 18 = 112`. Currently gap is `SizedBox(width: 10)` — `settings_screen.dart:785` ← `AyuGram/settings/settings.style:448`

- [ ] [MAJOR] `_PremiumRow` (Premium/Stars/Business rows) is missing the chevron `Icons.chevron_right` that `_SettingsRow` has. AyuGram standard settings buttons all show a right arrow. The `_PremiumRow` widget ends with `const SizedBox(width: 22)` with no arrow — `settings_screen.dart:1762` ← `AyuGram/settings/settings.style:12-16`

- [ ] [MAJOR] `_callsSettingsTabState._loadSettings` calls `engine.getCallsDisabledHere(accountId)` — the result is cast as `bool` from `results[4]` but `results[4]` is the 5th item in `Future.wait`. If any earlier future fails and is replaced by a null fallback, index alignment breaks silently. No error handling on individual futures in the `Future.wait` call — `settings_screen.dart:2343-2372`

- [ ] [MAJOR] Device selection in `_CallsSettingsTab` sets the device on the local `_selectedOutput/_selectedInput` state but the initial load always picks `outputDevs.first` (line 2362-2364) rather than reading the currently-configured device from the engine. On open, the displayed device will always be the first in the list even if a different device was previously selected — `settings_screen.dart:2362-2364` ← `AyuGram/settings/sections/settings_calls.cpp:167-183` (reads `settings->playbackDeviceIdValue()`)

- [ ] [MAJOR] `_BusinessSubPage._buildLocationEditor` creates `TextEditingController(text: ...)` inline inside `build()` for latitude/longitude fields (lines 3744, 3764). These controllers are not stored/disposed — each rebuild creates a leaked controller. Edits will be lost on any `setState` — `settings_screen.dart:3744,3764`

- [ ] [MAJOR] `_BusinessScreen.features` uses keys `('hours', 'location', 'greeting', 'away', 'quick_replies', 'chatbots', 'intro', 'links')` which are passed to `engine.getBusinessFeature(accountId, featureKey)` and `engine.setBusinessFeature(accountId, featureKey, data)`. These are informal string keys with no validation against the actual engine API — if the engine expects different keys the feature silently fails — `settings_screen.dart:3262-3271`

- [ ] [MAJOR] `_InterfaceScaleSection` scale slider range is capped dynamically: `_kMax = _snap((300 / dpr).clamp(100, 400))` making max scale only 150% on a 2x display. AyuGram's `SetupInterfaceScale` allows up to 300% regardless of DPI (it uses `kScalePercentsTo` which tops at 300) — `settings_screen.dart:1824-1826` ← `AyuGram/settings/sections/settings_main.cpp:499-521`

- [ ] [MAJOR] `_showEmojiStatusPanel` and `_showEmojiAvatarPicker` only load the first 64 items (`items.take(64)`) from installed emoji sets. AyuGram shows all available emoji stickers across all installed sets with scrolling — `settings_screen.dart:1047,1208`

- [ ] [MAJOR] `_showQrDialog` "Share" button action (line 1543-1547) just copies the link to clipboard and shows "Link copied to share" toast — it does NOT call the system share sheet. The button should invoke `Share.share(link)` (share_plus package) or equivalent. It is a stub disguised as a share action — `settings_screen.dart:1543-1547`

- [ ] [MAJOR] `_ProfileHeaderState._showCopyMenu` positions the popup using `RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy)` — right and bottom are set to the same as left/top, giving zero width/height in the rect. This causes the popup to appear in an undefined position — `settings_screen.dart:963-964`

- [ ] [MAJOR] `_GiftCatalogScreen._showRecipientPicker` loads contacts via `engine.getContacts()` inside a `StatefulBuilder` without a guard, so `getContacts` is called on every rebuild while `contacts == null`. The `if (contacts == null)` check is inside the builder but `contacts` is a local variable that never persists across rebuilds — contacts will be re-fetched on every state change — `settings_screen.dart:4271-4281`

# settings_style.dart — Icon dimensions don't match AyuGram source

## Critical Issues

- [ ] **[CRITICAL]** Icon size constant is wrong — `iconSize = 28` should be `24` per AyuGram `settings/icons/*.png` source files. AyuGram uses 24×24px icons for settings buttons (`settingsIconChat`, `settingsIconStickers`, etc. are all 24×24). Dart comment claims `20 + 28 + 12 = 60` but correct calculation is `20 + 24 + 16 = 60`. This causes layout misalignment with AyuGram reference. — `settings_style.dart:29` ← `AyuGramDesktop/Telegram/Resources/icons/settings/*.png` (verified via `file` command: 24×24)

- [ ] **[CRITICAL]** Icon gap constant is wrong — `iconGap = 12` should be `16` to match the corrected icon size. With 24px icons, the gap needed to reach 60px text-start position is 16px, not 12px. This is dependent on the iconSize fix above. — `settings_style.dart:30` ← Calculated from `settingsButton.padding (60px) - iconLeft (20px) - actual_iconSize (24px)` per `AyuGramDesktop/Telegram/SourceFiles/settings/settings.style:15-16`

## Verification

**AyuGram Source Truth:**
- Settings button padding: `margins(60px, 10px, 22px, 10px)` (settings.style:15)
- Icon left position: `iconLeft: 20px` (settings.style:16)
- Icon files in `/Telegram/Resources/icons/settings/`:
  - `chat.png`: 24×24
  - `interface_scale.png`: 24×24
  - `stickers.png`: 24×24
  - `emoji.png`: 24×24
  - `account.png`: 24×24
  - (verified across all standard settings icons — 24×24 is the canonical size)

**Spec Reference:**
- Section 14.9 ("Visual Style Constants") lists constants but does NOT explicitly specify icon size
- Relies on AyuGram reference as ground truth
- Calculation in Dart comment is internally consistent (20+28+12=60) but uses wrong base value (28 instead of 24)

**Impact:**
- Icons will be rendered 4px too wide, pushing text rightward
- Gap will be 4px too narrow, creating visual crowding
- Layout deviation >5% from reference is visible at normal viewing distances

---

## Non-Issues (Verified ✓)

- ✓ Animation constants: 200ms transition duration matches AyuGram typical 200-250ms per research/telegram_desktop_ui.md:2141
- ✓ Curve selection (easeOutCubic for slide, easeIn for fade) is correct per research section on slide animations
- ✓ Other padding constants (iconRowPadding, buttonPadding, checkboxPadding, etc.) match settings.style values exactly
- ✓ infoPhotoSize = 100, infoPhotoHeight = 162 match settings.style:205-206
- ✓ accentColorSize = 24 matches settings.style:313
- ✓ backgroundThumb = 76 matches settings.style:171
- ✓ bioMargins match settings.style:245
- ✓ themePreviewSize = Size(80, 92) matches settings.style:279
- ✓ themeBubbleSize = Size(40, 14) matches settings.style:280

# shell — Audit Findings

- [ ] [CRITICAL] "Try now" button calls `_tryReconnect()` → `showProxiesDialog()` instead of triggering an engine reconnect. AyuGram's retry link handler calls `_account->mtp().restart()` to immediately reconnect. The Go bridge exposes `Reconnect` (`dispatch_gen.go:14549`) but it is not wired in `EngineService` and not called here; both the "Try now" tap and the entire-pill tap use the same handler that only opens the proxy settings dialog — `shell.dart:1070-1073,1275` ← `window_connecting_widget.cpp:641-642`

- [ ] [MAJOR] `_contentWidthAnim.forward()` and `_contentWidthAnim.reverse()` are called directly inside `_buildPill()` which is invoked from `build()` (lines 1220, 1222). Mutating/starting an `AnimationController` during a widget build is a Flutter anti-pattern: it schedules a new frame from within the current build frame, which triggers "Dirty build callback called during build" assertion errors in debug mode and causes stuttering in release — `shell.dart:1220-1222`

- [ ] [MAJOR] Connecting-state text color uses `p.menuIconFg` but AyuGram paints the connecting text with `st::windowSubTextFg`. In dark theme these are distinct colors (`windowSubTextFg` = `#708499`, `menuIconFg` = `#6C7883`), producing a visually wrong pill text colour in dark mode — `shell.dart:1269` ← `window_connecting_widget.cpp:552` and `window.style:149`

- [ ] [MAJOR] "Try now" link text color uses `p.windowBgActive` (the active background fill colour, semantically wrong for a text link). AyuGram uses `st::connectingRetryLink` (a `LinkButton` derived from `defaultLinkButton`) whose text uses the standard link foreground — `shell.dart:1280` ← `window.style:186`

# shortcuts_settings_screen — Keyboard Shortcuts Settings

- [ ] [MAJOR] `_buildCommandRows` (lines 581–644) is dead code — defined but never called from `build()`. The build path uses `_buildEntry()` with a flat `entries` list via `ListView.builder`. The method duplicates row-building logic from `_buildEntry` and appears to be a leftover from an earlier implementation approach that was never removed. — `shortcuts_settings_screen.dart:581` ← `settings_shortcuts.cpp:214` (AyuGram builds buttons inline inside `fill()`, no equivalent dead path exists)

- [ ] [MAJOR] `_showContextMenu` does not check whether a popup menu is already open before showing a new one. AyuGram guards with `if (const auto strong = *menu) { strong->hideMenu(); return; }` — right-clicking while the menu is visible hides it instead of stacking another popup. In Dart, repeated right-clicks stack multiple `showMenu` routes on the Navigator, producing duplicate/overlapping menus. — `shortcuts_settings_screen.dart:317` ← `settings_shortcuts.cpp:284`

# spoiler_animation — Reveal stub, speed formula wrong, corner masking wrong

- [ ] [CRITICAL] `SpoilerRevealManager` is a stub — `hideAll()` is the only method; there is no `reveal()`, per-spoiler state, or reveal-progress tracker. `SpoilerTilePainter.revealProgress` is a dead parameter that nothing ever animates. `SpoilerAnimationMixin` wires no tap handler. Users can see the spoiler overlay but can never dismiss it — `spoiler_animation.dart:703-710` ← `AyuGram/lib_ui/ui/effects/spoiler_mess.h:87-107` (`SpoilerAnimation` + `revealAnimation` in `MediaSpoiler` at `history_view_media_spoiler.h:25`)

- [ ] [MAJOR] Particle velocity formula is DPR-incorrect. Dart: `pvx = spd * xDir * dpr * 0.033` (pixels-per-frame includes DPR factor). C++ speed is total-displacement over one lifetime in device pixels: `k = speed / lifetime_ms`, position += `k * elapsed_ms`. At dpr=1 Dart moves particles at 60% reference speed; at dpr=2 it overdrives ~20%. Formula should be `pvx = spd / totalLifetimeFrames` per frame (without the dpr multiply, since canvas is already in device pixels) — `spoiler_animation.dart:381-382` ← `AyuGram/lib_ui/ui/effects/spoiler_mess.cpp:124-146` (`RandomSpeed`)

- [ ] [MAJOR] Image-spoiler corner masking uses `canvas.clipRRect(borderRadius)` (uniform geometric clip) instead of the reference `CornersMaskRef` / `cornerCache` per-pixel compositing. Telegram message bubbles use asymmetric per-corner pixel masks (e.g. sharp tail corner), which a `BorderRadius` cannot represent — `spoiler_animation.dart:594-601` ← `AyuGram/lib_ui/ui/effects/spoiler_mess.cpp:510-623` (`FillSpoilerRect` with `CornersMaskRef`)

# stats_chart — Chart rendering behavioral divergences from AyuGram

- [ ] [MAJOR] Ruler label value format threshold wrong: Dart K-formats values ≥ 1,000 (e.g. 5000 → "5.0K"), but C++ uses locale-formatted strings below 10,000 (e.g. 5000 → "5,000") and only K/M-formats at ≥ 10,000 — `stats_chart.dart:2315-2322` ← `AyuGram/statistics/chart_rulers_data.cpp:26-32`

- [ ] [MAJOR] Pie label Y-shift uses `tp.height / 2` in Dart but C++ uses `textW / 2` (width-based) for BOTH x and y shifts — causes vertical label misplacement proportional to `(width - height) / 2` — `stats_chart.dart:2297` ← `AyuGram/statistics/view/stack_linear_chart_view.cpp:745-746`

- [ ] [MAJOR] StackLinear pie morph animation algorithm diverges: Dart uses simple linear interpolation from stacked positions toward pie arc positions — `stats_chart.dart:2099-2258`. C++ uses a two-stage rotation-based transform where the first 60% (`kStraightLinePart = 0.6`) morphs into straight lines using per-layer rotation matrices, and only the last 40% converges to the pie shape — `AyuGram/statistics/view/stack_linear_chart_view.cpp:247-551`. Animation looks visually different.

- [ ] [MAJOR] Bar chart footer mini-chart uses filled `drawRect` per bar column (`stats_chart.dart:2485-2490`) but C++ `BarChartView::paintChartAndSelected` with `!_isStack` builds a stepped polyline stroke path (histogram outline) — `AyuGram/statistics/view/bar_chart_view.cpp:94-110`. Regular Bar footer renders as filled blocks instead of a stepped outline.

- [ ] [MAJOR] Date labels and header subtitle dates use hardcoded English month/weekday names (`stats_chart.dart:736-740, 1583-1587`). C++ uses `Statistic::LangDayMonth(r)` → `tr::lng_stats_day_month` for bottom axis labels (`AyuGram/data/data_statistics_chart.cpp:67`) and `LangDayMonthYear` for header subtitle (`AyuGram/statistics/chart_widget.cpp:76`). All date text is non-localizable in the Dart implementation.

# main — PasscodeLockScreen text colors not from palette

- [ ] [MAJOR] `_PasscodeLockScreen` hardcodes `textColor` and `subtextColor` instead of reading from the palette. `textColor = isDark ? Color(0xFFF5F5F5) : Color(0xFF000000)` and `subtextColor = isDark ? Color(0xFF6C7883) : Color(0xFF999999)` will not match any custom theme that uses non-default foreground colors. AyuGram draws passcode header and input with `windowFg` (palette foreground). Should use `palette.windowFg` for textColor and a palette subtext token for subtextColor — `main.dart:2708-2709` ← `AyuGram/SourceFiles/window/window_lock_widgets.cpp:248` (`p.setPen(st::windowFg)`)

# sticker_pack_viewer — Audit Findings

- [ ] [CRITICAL] Long-press preview reuses live Video widget with shared VideoController — for webm stickers, `_showStickerPreview` at line 813 passes `child` (which is `Video(controller: _webmController!)`) into an OverlayEntry (line 1095: `child: stickerWidget`), creating two Video elements in the tree sharing one `VideoController`. MediaKit `VideoController` is single-consumer; the behavior is undefined (likely a frozen or crashed preview). AyuGram instead calls `_show->showMediaPreview()` which creates an independent `MediaPreviewWidget` renderer. — `sticker_pack_viewer.dart:813` ← `boxes/sticker_set_box.cpp:1521`

- [ ] [CRITICAL] Long-press preview on Lottie stickers fires `onLoaded` on the overlay clone, disposing and replacing `_lottieController`, freezing the original tile's animation — when the overlay Lottie element initialises it calls `_onLottieLoaded` (line 722–728) which disposes the existing `_lottieController` and assigns a new one. The original tile's Lottie widget briefly freezes. AyuGram uses a separate `MultiPlayer`-based preview (`showMediaPreview`) that never touches the grid element's player. — `sticker_pack_viewer.dart:722-728` ← `boxes/sticker_set_box.cpp:1521`

- [ ] [MAJOR] `GridView.builder` with `shrinkWrap: true` renders all sticker cells simultaneously — line 404–405: `shrinkWrap: true` forces Flutter to lay out the entire grid in one pass, triggering `getStickerFiles` engine calls for every sticker at once even if the pack has 100+ items. AyuGram's `paintEvent` only renders rows that fall within the visible viewport (`from`/`to` row indices, lines 2052–2070). — `sticker_pack_viewer.dart:404` ← `boxes/sticker_set_box.cpp:2052-2070`

- [ ] [MAJOR] No hover highlight on sticker tiles — the `GestureDetector` at line 808 handles taps and long-presses but there is no `MouseRegion`/`onHover` and no over-animation. AyuGram tracks `_selected` index, calls `startOverAnimation(_selected, 0., 1.)` on mouse-move (lines 1969–1972), and paints `st::emojiPanHover` background with `Ui::StickerHoverCorners` rounding around the hovered cell (lines 2334–2347). — `sticker_pack_viewer.dart:808` ← `boxes/sticker_set_box.cpp:1969-1972,2334-2347`

- [ ] [MAJOR] Missing sticker send animation — `_sendSticker` at line 210 calls `engine.sendSticker` then immediately pops the sheet. AyuGram computes the chosen sticker's pixel rect from grid position (`left = padding.left + col * singleSize.width`, lines 1683–1687), passes it to `chosen()`, and triggers the fly-to-input-field animation before closing the box. — `sticker_pack_viewer.dart:210-211` ← `boxes/sticker_set_box.cpp:1683-1699`

- [ ] [MAJOR] Context menu "Send Sticker" entry ignores schedule/silent-send options — `case 'send': widget.onTap?.call()` at line 891 sends immediately with no send-menu. AyuGram calls `SendMenu::FillSendMenu()` (line 1760) providing "Schedule message" and "Send silently" sub-menu items before dispatching. — `sticker_pack_viewer.dart:890-891` ← `boxes/sticker_set_box.cpp:1760-1764`

- [ ] [MAJOR] No drag-to-reorder for creator packs — the code checks `isCreator` (line 422) and exposes delete/add-to-set, but there is no reorder UI. AyuGram implements full drag reorder with a shake animation for each sticker cell (`_dragging.enabled`, shake amplitude loop lines 2280–2324), triggered from a "Reorder stickers" context menu entry. — `sticker_pack_viewer.dart:422` ← `boxes/sticker_set_box.cpp:1416,2280-2324`

- [ ] [MAJOR] `_showAddToSetDialog` can fire multiple `getCreatedStickerSets` engine calls — `getCreatedStickerSets()` is called inside the `StatefulBuilder` builder function (line 965) guarded only by the closure variable `loadingSets`. If anything triggers a rebuild of the `StatefulBuilder` before the future resolves (parent widget rebuild propagation, theme change, etc.), `loadingSets` is still `true` and a second network request fires with no deduplication. AyuGram uses a one-shot request whose result is stored before the box is shown (sticker_set_box.cpp operates on already-loaded sticker data). — `sticker_pack_viewer.dart:964-965` ← `boxes/sticker_set_box.cpp:521-563`

# story_editor — Audit Findings

## story_editor — Story Editor layer vs AyuGram stories source

- [ ] [CRITICAL] Lottie sticker rendering crashes silently in exported story image: `_renderCanvasToBytes` enters the `if (item.isSticker)` branch when `lottieComposition != null` but `stickerImageBytes == null`, then calls `item.stickerImageBytes!` which throws a null-dereference. The `try/catch` at line 645 swallows it silently — animated stickers simply vanish from exported stories — `story_editor.dart:628-645` ← `api.tl:2895` (stories.sendStory expects composed image; sticker content must render)

- [ ] [CRITICAL] Emoji button in caption bar is a non-functional placeholder: `const Icon(Icons.emoji_emotions_outlined)` at line 1658 is a bare icon with no GestureDetector — tapping it does nothing. CLAUDE.md bans all placeholder UI elements that look functional but aren't — `story_editor.dart:1658-1659` ← `media_stories_reply.h` (ReplyArea::tryProcessKeyInput — emoji input is a real feature, not cosmetic)

- [ ] [CRITICAL] `trimStart`/`trimEnd` passed to `sendStoryWithPhoto` (photo stories have no timeline): lines 517–520 send these parameters to the engine which accepts and forwards them via `dispatch_engine.go:4049-4063`, but `stories.sendStory` has no trim concept for photo media — these fields are always ignored, indicating a wiring mismatch — `story_editor.dart:517-520` ← `api.tl:2895` (`stories.sendStory` has no trim field; period is story *display* duration, not media trim)

- [ ] [MAJOR] Video story editor shows only a static cover frame — no real video playback preview: `_buildCanvasContent` at lines 842–865 renders `_videoCoverFrame` (a single screenshot via `player.screenshot()`) or the first thumbnail. TG Desktop plays the video live in the editor so the user can judge cuts, timing, and overlays. The Dart implementation never creates a `VideoPlayer` widget for the canvas — `story_editor.dart:842-865` ← `media_stories_controller.cpp:912` (story media is played back live in the controller)

- [ ] [MAJOR] No media areas support — interactive story elements completely missing: `stories.sendStory` has `media_areas:flags.5?Vector<MediaArea>` for location pins, URL buttons, mention tags, reaction areas, etc. Neither the Dart UI, the engine bridge, nor the Go telegram core accept or pass any `media_areas` data. The entire interactive overlay feature is absent — `story_editor.dart:492-520` ← `api.tl:2895` (`media_areas:flags.5?Vector<MediaArea>` field in stories.sendStory; `data_story.cpp:37-198` ParseArea/ParseLocation/ParseUrlArea/ParseWeatherArea)

- [ ] [MAJOR] No drag-to-trash delete zone for scene items — deletion is keyboard-only: scene items can only be deleted via keyboard Delete/Backspace (`story_editor.dart:2128-2140`). On touch devices (and in TG Desktop) dragging a sticker/text towards the bottom reveals a trash zone that removes the item on release. Without this, mobile users cannot delete overlaid items — `story_editor.dart:985-1023` ← `media_stories_view.h` (View class handles pointer-based item removal)

- [ ] [MAJOR] "Allow sharing" toggle unconditionally hidden for Close Friends privacy: line 1599 wraps the toggle in `if (_privacy != StoryPrivacyOption.closeFriends)`. In the TL, `noforwards` is a fully independent flag from `close_friends`/`privacy_rules` — TG Desktop allows setting noforwards for *any* privacy option including Close Friends. This silently forces `allowSharing = true` for Close Friends stories — `story_editor.dart:1599-1606` ← `api.tl:2895` (`noforwards:flags.4?true` is orthogonal to `close_friends:flags.8?true` in storyItem)

- [ ] [MAJOR] No maximum video duration enforcement — stories are limited to 60 seconds: the video duration read at line 357 is stored but never validated against a maximum. A user can upload a 10-minute video, set trim to cover the full range, and submit it. The TG API rejects stories longer than 60 seconds (or 30 for non-premium channel stories). No client-side guard prevents a failed upload — `story_editor.dart:337-411` ← `api.tl:2895` (period/media constraints on stories.sendStory)

- [ ] [MAJOR] Sticker grid in `_StickerPickerPanel` shows only 64 hardcoded emoji — no emoji search, no categories tab: the emoji section at lines 3132–3143 contains 4 hardcoded lists of 16 emoji each. TG Desktop's emoji picker shows hundreds of emoji across proper Unicode categories with search. Users cannot access the vast majority of the emoji set from the story editor's overlay picker — `story_editor.dart:3132-3144` ← `media_stories_reactions.h` (Reactions class wires full emoji set for story overlays)

# telegram_toast — Sticker toast behavior deviations

- [ ] [MAJOR] `isReaction` path is invented — AyuGram `StickerToast` has no reaction-specific text or routing; `Section` enum only has `Message` and `TopicIcon` (no `Reaction`). The Dart adds a separate `isReaction` bool that shows "This reaction is from the X pack." text and a tappable pack-name link not present in the reference — `telegram_toast.dart:453-464` ← `history_view_sticker_toast.cpp:142-156` (only `toSaved`, `isEmoji`, and sticker-premium text paths exist)

- [ ] [MAJOR] Missing installed-set check for emoji "View" button routing — AyuGram checks whether the emoji set is already installed (`i->second->flags & Data::StickersSetFlag::Installed`) and routes to `ShowPremiumPreviewBox` if installed OR to `StickerSetBox` if not; Dart `_viewCallback` always returns `onShowPremium` for any `isEmoji` case, so uninstalled emoji packs always open the premium screen instead of the set box — `telegram_toast.dart:538` ← `history_view_sticker_toast.cpp:241-251`

# telegram_tooltip — 3 issues found

- [ ] [MAJOR] `_onHover` dismisses tooltip using Euclidean distance with threshold 4.0px; AyuGram uses Manhattan distance (`manhattanLength`) against `QApplication::startDragDistance()` (~10px). Tooltip dismisses ~2.5× more aggressively on any minor cursor wobble. — `telegram_tooltip.dart:75-79` ← `AyuGram/Telegram/lib_ui/ui/widgets/tooltip.cpp:68`

- [ ] [MAJOR] `ImportantTooltip` default `preferredSide` is `TooltipSide.bottom` (tooltip below target) but AyuGram's `pointAt` defaults to `RectPart::Top | RectPart::Left` (tooltip above target). Every call-site using the default will place the tooltip on the wrong side. — `telegram_tooltip.dart:244` ← `AyuGram/Telegram/lib_ui/ui/widgets/tooltip.h:98`

- [ ] [MAJOR] `_resolveSide` checks available space using hardcoded `minSpace = 28px` (`_kArrowHeight + padding.top + padding.bottom + 16`) instead of actual rendered inner height. AyuGram calls `countInner().height() + _st.shift + _st.arrow` at layout time, using the real content height. For any multi-line `ImportantTooltip`, side resolution can pick the wrong side because the content exceeds 28px. — `telegram_tooltip.dart:371` ← `AyuGram/Telegram/lib_ui/ui/widgets/tooltip.cpp:266`

# theme_editor — Theme Editor Screen Audit

- [ ] [CRITICAL] `_referenceChain` is always empty when the editor opens fresh: `initState()` at line 68 only calls `paletteToMap()` which returns no reference data. The chain is only populated via `_handleImport()` at line 426. On first open, all tokens show no "= copyName" label, `_updateColor()` propagation does nothing, and the "New color scheme keys" section is always empty — `theme_editor.dart:41,68-76` ← `window_theme_editor.cpp:564-597` (`readData()` populates both existingRows and newRows from palette file on every open)

- [ ] [CRITICAL] `_tokenDescription()` at line 1167 generates fake descriptions by splitting camelCase token names (e.g. `windowBgActive` → "Window Bg Active"). In C++, descriptions come from `style::main_palette::data()` — actual documentation strings like "Active background of the main window". Every token description shown in the Dart editor is wrong — `theme_editor.dart:1167-1199` ← `window_theme_editor.cpp:569-593` (`feedDescription()` called with `row.description` from style data)

- [ ] [MAJOR] Importing a theme does not apply its background image to the running app. `_handleImport()` at line 430 sets `_currentBackground = parsed.backgroundImage` but never applies it via `widget.onPaletteChanged` or any background setter. In C++, `importTheme()` calls `Background()->set(...)` and `Background()->setTile(parsed.tiled)` and `Ui::ForceFullRepaint(...)` — `theme_editor.dart:405-437` ← `window_theme_editor.cpp:808-821`

- [ ] [MAJOR] Close confirmation uses `_isDirty` bool (line 293) instead of actual content comparison. If a user changes a color then changes it back to the original, `_isDirty` is still `true` and the discard-changes dialog is shown incorrectly. C++ uses `PaletteChanged(_inner->paletteContent(), _cloud)` which does a byte-level comparison — `theme_editor.dart:292-303` ← `window_theme_editor.cpp:914-919` + `window_theme_editor_box.cpp:226-232`

- [ ] [MAJOR] `_updateColor()` reference chain propagation is semantically broken. When token A is updated, all tokens referencing A (e.g. B = A) get `_colorMap[B] = newColor` at line 217, making them explicit-valued. But `_referenceChain` still shows `B: 'A'` and `_PaletteEntryRow` still renders "= A" at line 838. B is now displayed as a copy-reference but has an independent value — editing B later won't show the correct color. C++ writes the new value to the palette TEXT via `ReplaceValueInPaletteContent()`, so the reference chain in text is always the ground truth — `theme_editor.dart:207-229,838` ← `window_theme_editor.cpp:626-661`

- [ ] [MAJOR] Missing `BackgroundUpdate` listener. C++ subscribes to `Background()->updates()` at line 432 and reverts if someone tries to change the theme while the editor is open (showing a toast: "Can't change theme while editing"). Dart has no equivalent — the editor would silently become inconsistent if the background changes externally — `theme_editor.dart:38-102` ← `window_theme_editor.cpp:432-445`

# titlebar — Drag timing wrong; missing synthetic release after system move

- [ ] [MAJOR] Window drag starts after 300ms timer (`kDoubleTapTimeout`) instead of immediately on first mouse move — AyuGram calls `startSystemMove()` on the very first `mouseMoveEvent` while pressed, with no delay — `titlebar.dart:289` ← `AyuGram/lib_ui/ui/platform/ui_platform_window_title.cpp:487-495`

- [ ] [MAJOR] After `startDrag()` fires, no synthetic pointer-release is sent to reset button state — AyuGram calls `SendSynteticMouseEvent(this, QEvent::MouseButtonRelease, Qt::LeftButton)` immediately after `startSystemMove()` to prevent stale "button held" state in the widget — `titlebar.dart:292` ← `AyuGram/lib_ui/ui/platform/ui_platform_window_title.cpp:490-494`

# web_app_panel — Bot WebView Panel

- [ ] [CRITICAL] `_injectBridgeScript` destroys the Flutter JS channel: `addJavaScriptChannel('TelegramWebviewProxy', ...)` (line 209) creates `window.TelegramWebviewProxy` with a native `postMessage` method; then `_injectBridgeScript` (lines 247–255) replaces the entire object with `window.TelegramWebviewProxy = { postEvent: fn }`. Inside `postEvent`, `TelegramWebviewProxy.postMessage(...)` now resolves to the new plain object's `postMessage` which is `undefined` — TypeError on every call. All web-app→Flutter events (`web_app_ready`, `web_app_close`, every `web_app_*`) are silently dropped. AyuGram avoids this by using `window.external.invoke(JSON.stringify([eventType, eventData]))` (a separate native mechanism that never conflicts with any Flutter channel) — `web_app_panel.dart:209,247-255` ← `attach_bot_webview.cpp:1092-1099`

- [ ] [MAJOR] Fullscreen toggle fires only `fullscreen_changed` but not `safe_area_changed` or `content_safe_area_changed`. AyuGram's fullscreen reactive handler (lines 442–449) calls `sendFullScreen()`, `sendSafeArea()`, and `sendContentSafeArea()` every time fullscreen state changes. Dart (lines 366–376) fires only `fullscreen_changed`. Web apps that update layout on `content_safe_area_changed` (e.g. to avoid the fullscreen close button) will never update when entering/exiting fullscreen — `web_app_panel.dart:366-376` ← `attach_bot_webview.cpp:442-449`

# country_data — Phone formatting groups mismatch with AyuGram

- [ ] [CRITICAL] Phone group format mismatch for dial code "44" (UK) — `country_data.dart:31` has `[4, 3, 3]` but AyuGram has `[4, 6]` ← `AyuGramDesktop/Telegram/SourceFiles/countries/countries_instance.cpp:88`
- [ ] [CRITICAL] Phone group format mismatch for dial code "49" (Germany) — `country_data.dart:32` has `[3, 3, 4]` but AyuGram has `[4, 7]` ← `AyuGramDesktop/Telegram/SourceFiles/countries/countries_instance.cpp:69`
- [ ] [CRITICAL] Phone group format mismatch for dial code "39" (Italy) — `country_data.dart:34` has `[3, 3, 4]` but AyuGram has `[3, 3, 3]` ← `AyuGramDesktop/Telegram/SourceFiles/countries/countries_instance.cpp:117`
- [ ] [CRITICAL] Phone group format mismatch for dial code "20" (Egypt) — `country_data.dart:59` has `[3, 3, 4]` but AyuGram has `[2, 4, 4]` ← `AyuGramDesktop/Telegram/SourceFiles/countries/countries_instance.cpp:77`
- [ ] [CRITICAL] Phone group format mismatch for dial code "234" (Nigeria) — `country_data.dart:61` has `[3, 3, 4]` but AyuGram has `[2, 4, 4]` ← `AyuGramDesktop/Telegram/SourceFiles/countries/countries_instance.cpp:169`

**Impact:** Phone numbers will be formatted incorrectly for these countries. Users in UK, Germany, Italy, Egypt, and Nigeria will see malformed phone number separators (e.g., "4471234 567" instead of "447123 456789" for UK). This is a UI correctness issue that violates the AyuGram Desktop spec.

**Fix Required:** Regenerate the `_phoneGroups` map from the AyuGram countries data to ensure all 37 dial codes have correct formatting groups.

# safe_string — UTF-16 sanitization utilities

## Summary
Three utility functions for safe text handling: `safeStr()` sanitizes malformed UTF-16, `safeInitial()` extracts first character for avatars, `safeTruncate()` truncates text safely without breaking surrogate pairs.

## Issues Found

- [ ] [MAJOR] `safeInitial()` function exported but never called — `safe_string.dart:48-56` ← No usage found in codebase
  - Function is defined to extract first character for use in avatar initials, but zero callers
  - Suggests user avatar feature with initials is not yet implemented
  - Violates CLAUDE.md "ZERO placeholders" rule — infrastructure for unimplemented features
  - Recommendation: Either remove if not needed, or add the avatar feature that uses it

- [ ] [MAJOR] `safeTruncate()` function exported but never called — `safe_string.dart:60-69` ← No usage found in codebase
  - Function is defined for text truncation with safe surrogate pair handling, but zero callers
  - No code paths currently truncate text for display
  - Violates CLAUDE.md "ZERO placeholders" rule — infrastructure without consumer
  - Recommendation: Either remove if not needed, or wire up text truncation feature

- [ ] [OK] `safeStr()` is correctly implemented and actively used in engine_service.dart and engine_models.dart
  - Sanitizes all string data from backend before display
  - UTF-16 surrogate handling is correct per Unicode standard (0xD800-0xDBFF high, 0xDC00-0xDFFF low)
  - Replacement character U+FFFD is correct per standard
  - Fast path optimization avoids unnecessary work

## Behavioral Correctness vs AyuGram

All implementations match Telegram Desktop / AyuGram approach:
- `toUpper()`/`.toUpperCase()` for initials matches AyuGram empty_userpic.cpp:672
- Surrogate pair validation is correct per UTF-16 standard
- No issues with character handling logic

## Recommendation

These two unused exported functions should either be:
1. **REMOVE** them if user avatars and text truncation features are deferred
2. **IMPLEMENT THE FEATURES** that use them (avatar display with initials, text truncation in chat list, etc.)

As-is, they violate the "no placeholder infrastructure for features not yet implemented" principle.

## engine_models — field audit vs AyuGram data structures

- [ ] [MAJOR] `GroupCallParticipant` missing `applyVolumeFromMin` field — present in AyuGram C++ struct but absent from Dart model; controls whether volume from min-loaded participant data is applied — `engine_models.dart:2500` ← `AyuGram/data/data_group_call.h:55`

- [ ] [MAJOR] `GroupCallInfo` missing `scheduleStartSubscribed` field — AyuGram `GroupCall` exposes `scheduleStartSubscribed()` for whether user subscribed to scheduled call start, not present in Dart `GroupCallInfo` — `engine_models.dart:2578` ← `AyuGram/data/data_group_call.h:120`

- [ ] [MAJOR] `GroupCallInfo` missing `recordVideo` field — AyuGram `GroupCall::recordVideo()` returns whether recording includes video; absent from `GroupCallInfo` — `engine_models.dart:2578` ← `AyuGram/data/data_group_call.h:129`

- [ ] [MAJOR] `GroupCallInfo` missing `joinMuted` field — AyuGram `GroupCall::joinMuted()` indicates whether new participants join muted; absent from `GroupCallInfo` — `engine_models.dart:2578` ← `AyuGram/data/data_group_call.h:197`

- [ ] [MAJOR] `GroupCallInfo` missing `canManage` field — AyuGram `GroupCall::canManage()` controls host-level permissions; absent from `GroupCallInfo` — `engine_models.dart:2578` ← `AyuGram/data/data_group_call.h:88`

- [ ] [MAJOR] `CallHistoryEntry` missing `state` field — AyuGram `Call::State` (CallState enum) has 7 states: Missed, Busy, Disconnected, Hangup, MigrateConferenceCall, Invitation, Active; Dart only models this as a single `isMissed: bool`, losing Busy/Disconnected/Hangup/Invitation/Active distinctions — `engine_models.dart:3654` ← `AyuGram/data/data_media_types.h:44`

- [ ] [MAJOR] `CallHistoryEntry` missing `otherParticipants` field — AyuGram `Call::otherParticipants` (vector of PeerData) stores conference call participants; absent from Dart `CallHistoryEntry` causing data loss for conference calls — `engine_models.dart:3654` ← `AyuGram/data/data_media_types.h:85`

- [ ] [MAJOR] `CallHistoryEntry` missing `conferenceId` field — AyuGram `Call::conferenceId` (CallId) links call to a group call conference; absent from Dart `CallHistoryEntry` — `engine_models.dart:3654` ← `AyuGram/data/data_media_types.h:86`

- [ ] [MAJOR] `StoryItem` missing `albumIds` field — AyuGram `Story` has `albumIds()` returning a flat_set<int> of story album IDs; absent from Dart `StoryItem` causing story albums to be non-functional — `engine_models.dart:3405` ← `AyuGram/data/data_story.h:244`

- [ ] [MAJOR] `StoryItem` missing `interactions` field — AyuGram `Story::interactions()` returns total engagement count (views + reactions + forwards combined); absent from Dart `StoryItem` — `engine_models.dart:3405` ← `AyuGram/data/data_story.h:212`

- [ ] [MAJOR] `StoryItem` missing `fromPeer` field — AyuGram `Story::fromPeer()` returns original author when story is forwarded through a channel; absent from `StoryItem` — `engine_models.dart:3405` ← `AyuGram/data/data_story.h:247`

- [ ] [MAJOR] `MessageReaction.byMe` is bool but AyuGram uses `chosen()` returning a vector — AyuGram `MessageReactions::chosen()` returns `std::vector<ReactionId>` because a user can send multiple distinct reactions; Dart models this as a single `byMe: bool` losing multi-reaction support — `engine_models.dart:1443` ← `AyuGram/data/data_message_reactions.h:421`

- [ ] [MAJOR] `ForumTopic` `notifySound` is typed as `int` but AyuGram uses `NotifySound` struct — AyuGram `PeerNotifySettings::sound()` returns `std::optional<NotifySound>` (struct with title/data/id/none fields); Dart stores this as a bare `int` — `engine_models.dart:403` ← `AyuGram/data/notify/data_peer_notify_settings.h:22`

- [ ] [MAJOR] `GroupCallInfo` missing `canChangeJoinMuted` field — AyuGram `GroupCall::canChangeJoinMuted()` controls whether current user can change join-muted setting; absent from `GroupCallInfo` — `engine_models.dart:2578` ← `AyuGram/data/data_group_call.h:198`

