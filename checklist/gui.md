# GUI Audit — Cycle 1 Phase Cleanup (2026-05-21 16:44)

## Cleanup Sweep (placeholders, stubs, perf)

# bridge — code quality audit

## CRITICAL Issues


## OK / No issues found

- Bridge wrapper facade (`bridge.dart`) — clean delegation pattern
- FFI implementation (`bridge_ffi.dart`) — proper memory management, isolate handling, event callback setup
- Stub implementation (`bridge_stub.dart`) — intentional and correct
- Event subscription lifecycle (`engine_service.dart:5612`) — properly cancelled in dispose
- Memory cleanup (`bridge_ffi.dart:133-150`) — allocations freed in finally blocks
- Error handling pattern — consistent StateError throws for uninitialized state (FFI)

# spell_service — issues found


## Details

**Line 88 (Stub suggestions):**
- `fetchSpellCheckSuggestions()` marks misspelled words but returns `const []` (empty suggestions list)
- Method name promises suggestions, implementation delivers nothing
- UI will show "word is misspelled" without any way to fix it

**Lines 44 & 186 (Windows paths):**
- `dictsDir` correctly handles platform-specific paths (lines 14–26)
- But string operations at lines 44 and 186 hardcode Unix separator
- On Windows: `C:\Users\Nako\AppData\Roaming\uniclient\dicts\en_US.dic`
- `split('/')` won't split (no forward slashes in string)
- `.last` returns entire path; `replaceAll('.dic', '')` leaves `C:\Users\...\en_US`
- Should use `basename()` or `File(path).uri.pathSegments.last` instead


# notification_types — clean

No issues found.


# bridge_ffi — audit findings

## Issues Found

### [CRITICAL] Event controller not recreated after dispose — reinitialization impossible
**Location:** `bridge_ffi.dart:166`

The `_globalEventController` is a module-level global created once:
```dart
final _globalEventController = StreamController<Uint8List>.broadcast();
```

When `dispose()` closes it (line 89), the stream is permanently closed. Attempting to reinitialize the bridge will fail silently:
- `init()` succeeds and sets `_initialized = true`
- But `events` property returns a closed stream that will never emit
- Any code expecting events after reinit will hang

**Scenario:** 
1. App calls `bridge.init()` → stream active
2. Error recovery or test calls `bridge.dispose()` → stream closed
3. App tries to reinit (common in error handling) → `_initialized` resets but controller is dead forever
4. Next events never arrive, silently breaking auth/message flow

**Fix:** Move controller creation into `init()` method (make it instance-level or recreate if closed):
```dart
void init({String? libraryPath}) {
  if (_initialized) return;
  
  // Recreate controller if needed (allows reinit)
  if (_globalEventController.isClosed) {
    // Would need to refactor to instance-level or use fresh controller
  }
  
  _resolvedLibPath = libraryPath ?? _findLibraryPath();
  ...
}
```

**Better fix:** Make `_globalEventController` and `_eventCallable` instance fields instead of globals — this would also allow multiple independent Bridge instances if needed.

### [MINOR] Unsafe library path construction on macOS
**Location:** `bridge_ffi.dart:106`

```dart
final frameworkPath = '$exeDir/../Frameworks/libcores.dylib';
```

The `..` relative path is not normalized. On some systems this might fail or follow unexpected symlinks. Should use `normalize()` or proper path resolution:
```dart
final parentDir = File(Platform.resolvedExecutable).parent.parent.path;
final frameworkPath = '$parentDir/Frameworks/libcores.dylib';
```

---

## Clean Patterns (Not Issues)

- ✅ Memory management correct — proper calloc/free with try/finally
- ✅ Pointer casting safe — null checks before use
- ✅ Event callback handles async marshalling correctly — NativeCallable.listener prevents isolate crashes
- ✅ Thread safety proper — callback unset before stream close
- ✅ Initialization guarded — both sync/async check `_initialized`


# theme_preview — clean

No critical, major, or maintenance issues found. The widget correctly displays a theme preview with example data (intentional for preview purposes). Image loading has proper error handling and fallback. All UI elements are fully functional and properly wired to the palette.

# wallpaper — audit findings

## Critical Issues


## Minor Issues


## Green Flags

✓ `WallpaperProvider` properly inherits and exposes via `of(context)`
✓ `ChatWallpaper` correctly switch/cases all wallpaper types
✓ `_MultiColorGradient` + `_PatternWallpaper` properly use AnimationController + setState for power saving
✓ `_MultiGradientPainter.shouldRepaint()` correctly checks all fields (line 403-406)
✓ `_PatternWallpaperPainter.shouldRepaint()` correctly checks all fields (line 674-680)
✓ All const constructors on data classes and widgets
✓ Image encoding/decoding check for null gracefully (lines 718, 741, 759)
✓ Color fallback (0xFF527C41) reasonable for small/invalid images
✓ Animation state properly pauses on power saving (lines 329-334, 512-517)
✓ All engine/state wiring verified (AppState.powerSaving, kPowerSavingChatBackground)

## Summary

One blocking bug: `_TiledImage` won't render because async decode doesn't trigger repaint. Needs immediate fix.




# ayu_toggle — clean

# chat_list_panel — cleanup

## CRITICAL

## MAJOR

## chat_switch_overlay — cleanup

# chat_view — cleanup

## MAJOR


## choose_datetime_box — cleanup


# compose_entities — wiring issue

- [CRITICAL] Emoji placeholder replacement doesn't adjust entity lengths for overlapping formatting — `compose_entities.dart:367-373`

  **Issue:** When custom emoji placeholders are replaced with alt text (e.g., 1 char → 6 chars), other formatting entities that span across the emoji don't get their lengths adjusted. Only entities starting *after* the emoji get their offsets shifted.
  
  **Example:** Bold entity [offset: 2, length: 15] spans across emoji at [9, 1]. When emoji is replaced with 6-char alt text (delta=+5), the bold entity should become [2, 20] but stays [2, 15], breaking formatting ranges.
  
  **Root cause:** Line 372 only handles `if (e.offset > ce.offset)` (entities starting after emoji), missing entities that contain or overlap the emoji.
  
  **Impact:** Formatting entities sent to server have wrong byte ranges when they span custom emojis, breaking bold/italic/link/etc across emoji.
  
  **Fix:** After updating emoji entity length, also check and update overlapping entities:
  ```dart
  if (e == ce) {
    e.length = alt.length;
    continue;
  }
  if (e.offset >= ce.offset + ce.length) {
    // Entity starts at/after emoji ends — shift offset
    e.offset += delta;
  } else if (e.offset < ce.offset + ce.length && e.offset + e.length > ce.offset) {
    // Entity overlaps emoji — expand length
    e.length += delta;
  }
  ```


## contacts_screen — cleanup

## create_giveaway_box — cleanup

## emoji_panel — cleanup


# emoji_status_widget — audit

## Issues Found


## Clean Areas

- ✅ Lifecycle management: acquire/release properly balanced in initState/dispose/didUpdateWidget
- ✅ Animation controller: properly disposed and looped
- ✅ Engine wiring: EngineService.context.read() calls at lines 135, 141 are correct
- ✅ Cache listener: registered in initState, removed in dispose
- ✅ Error handling: proper error builders on Image/Lottie widgets
- ✅ State parsing: _parseEmojiStatusId() handles all three formats (collectible/userpic/regular)
- ✅ Color parsing: _parseHexColor() safely handles invalid input
- ✅ Power saving: conditional rendering respects power saving mode
- ✅ Shader masking: RadialGradient collectible effects properly applied


# emoji_data — cleanup

# instant_view — cleanup

# keyboard_shortcuts — cleanup

# language_box — cleanup

# payment_panel — cleanup

## peer_short_info — cleanup

- [ ] [CRITICAL] `TapGestureRecognizer` instances created inline in `_parseTextWithEntities` are never stored or disposed — every `setState` rebuild (status update, photo nav, buffering) that re-invokes `_buildInfoRows` leaks all recognizers from the previous render; Flutter's `RenderParagraph` does not auto-dispose inline recognizers — store them as state fields and dispose in `dispose()` — `peer_short_info.dart:1065-1079`

- [ ] [CRITICAL] `#hashtag` matches in bio/about text are styled as tappable links (rendered in `labelColor`, with a `TapGestureRecognizer`) but the `onTap` handler immediately `return`s — user sees a blue clickable hashtag that does nothing — either strip `#\w+` from the regex so hashtags render as plain text, or implement hashtag search navigation — `peer_short_info.dart:1073-1074`

- [ ] [MAJOR] `Image.file` used without `cacheWidth`/`cacheHeight` for both the primary avatar (`widget.avatarPath`) and navigated photos (`_currentPhotoPath`) — the cover display is 304×304 logical pixels but the full-resolution image file is decoded and cached at its native size, wasting memory proportional to the avatar's actual resolution — set `cacheWidth: (_kCoverSize * MediaQuery.of(context).devicePixelRatio).round()` — `peer_short_info.dart:522-529`

- [ ] [MAJOR] `value.replaceAll(' ', ' ')` at line 946 is a dead no-op — with `maxLines: 1` already enforced on the `SelectableText`, non-breaking space substitution has no effect on wrapping, and if both characters are ASCII 0x20 it allocates a new string on every call for nothing — remove the `replaceAll` call — `peer_short_info.dart:946`

- [ ] [MAJOR] `_PhotoProgressBarsPainter.paint` silently draws nothing when `smallWidth < size.height` (i.e. bar width < 2 px) — for users with many photos the condition triggers at roughly 50+ photos on a 304 px wide box, leaving the nav zones active but with no visual progress indicator; needs graceful degradation (e.g. collapse bars below a minimum count threshold, or reduce `_kBarGap` proportionally) — `peer_short_info.dart:1253-1256`

# photo_crop_editor — cleanup

- [ ] [CRITICAL] blur strokes silently dropped from export — `_applyCropAndExport` (line 1010) skips every stroke where `tool == _PaintTool.blur` via `continue` and never calls the blur rendering equivalent of `_CropPainter._drawBlurStrokes`; users see blur on-screen but the saved file has none — `photo_crop_editor.dart:1010`

- [ ] [CRITICAL] regular strokes drawn twice in eraser export path — when `hasEraser` is true, lines 1009-1013 draw all pen/arrow/marker strokes directly onto the canvas, then lines 1016-1039 draw them again inside a `saveLayer`; strokes from the first pass are already composited so the `BlendMode.clear` eraser can't reach them, producing doubled stroke artifacts and non-functional erasure on the exported image — `photo_crop_editor.dart:1009`

- [ ] [MAJOR] `shouldRepaint` list-identity check always false for strokes and annotations — `old.paintStrokes != paintStrokes` (line 2604) and `old.textAnnotations != textAnnotations` (line 2605) compare the same `List` object reference on every rebuild (both sides point to the same mutable list in `_PhotoCropEditorState`), so the check is never true; text annotations added while `currentStroke` is null won't trigger a canvas repaint — use a generation counter or copy the list reference on mutation — `photo_crop_editor.dart:2604`

- [ ] [MAJOR] `TextPainter` created and laid out on every pointer-move event — `_annotationItemSize` (line 1724) constructs a full `TextPainter`, calls `layout()`, and discards it just to get widget dimensions; this is called from both `_hitTestAnnotations` and `_hitTestAnnotationHandles` on every `PointerMoveEvent`; cache the size per annotation indexed by text+fontSize+scale — `photo_crop_editor.dart:1724`

- [ ] [MAJOR] `TextPainter` created per annotation per paint frame in `_drawTextAnnotations` — lines 2412-2425 allocate and lay out a new `TextPainter` for every text annotation on every call to `paint()`; with frequent repaints (brush drawing, zoom) this fires many times per second; cache layout results keyed by text+fontSize+scale — `photo_crop_editor.dart:2412`

- [ ] [MAJOR] sticker thumbnail base64-decoded on every `GridView.builder` itemBuilder call — line 3689 calls `_decodeThumb(sticker.thumbB64)` followed by `Uint8List.fromList(...)` inside `itemBuilder`; this runs for every visible sticker on every rebuild; decoded bytes should be cached once per sticker (a `Map<String, Uint8List>` in `_EditorStickerPickerState` keyed by sticker id or b64 hash) — `photo_crop_editor.dart:3689`

- [ ] [MAJOR] export temp files written to `/tmp/` hardcoded — lines 1091 and 4092 use `File('/tmp/crop_...')` and `File('/tmp/emoji_avatar_...')`; `/tmp/` does not exist on Android or iOS; replace with `(await getTemporaryDirectory()).path` from `path_provider` — `photo_crop_editor.dart:1091`

# popup_menu — cleanup

- [ ] [MAJOR] `_shadowColor(Brightness b)` ignores its parameter entirely — always returns `Color(0xFF000000)` regardless of light/dark mode; the `Brightness b` argument is dead code — `popup_menu.dart:18`

- [ ] [MAJOR] First-frame expand-origin mismatch: `_origin` defaults to `Alignment.topLeft` (line 205) but the real origin is only resolved during layout and applied one frame later via `addPostFrameCallback` → `setState`. For clicks near the bottom or right screen edge where the true origin is `bottomRight`, the first animation frame expands from the wrong corner before snapping to the correct one — `popup_menu.dart:205` `popup_menu.dart:273`

- [ ] [MAJOR] `_TelegramRippleItem.build`: the ripple `AnimatedBuilder` (line 979) rebuilds and repaints the full item widget on every frame of the 650ms ripple animation with no `RepaintBoundary` isolating the ripple layer; neighboring siblings in the `Column` receive unnecessary repaint requests each frame — `popup_menu.dart:979`

- [ ] [MAJOR] `_panelCurve` static method is duplicated verbatim in two classes: `_TelegramMenuOverlayState` (line 330) and `_AnimatedSubmenuRevealState` (line 495) — extract to a top-level function — `popup_menu.dart:330` `popup_menu.dart:495`

## privacy_settings_screen — cleanup

- [ ] [CRITICAL] Wrong state field key in `_CloudPasswordEmail._setPassword` — reads `state?['unconfirmedEmail']` at line 4221 but the Go engine (telegram.go:18323) serialises the field as `emailUnconfirmedPattern`, which is also what `_fetchPasswordState` at line 131 reads. Result: after setting a 2FA password with a recovery email the unconfirmed email is never detected, `_CloudPasswordEmailConfirm` is never pushed, and the user lands on `_CloudPasswordDone` without ever verifying the email — `privacy_settings_screen.dart:4221`

- [ ] [CRITICAL] `FutureBuilder` in `_showBlockUserPicker` re-fetches contacts on every search keystroke — `_loadContacts(engine, accountId, blockedIds)` is called directly in the `future:` parameter inside `StatefulBuilder`'s builder. Every `setDialogState(() => searchQuery = v)` call triggers a rebuild, creates a new `Future`, and `FutureBuilder` transitions back to `waiting`, causing the list to flash and contacts to be re-fetched from the engine on every typed character — `privacy_settings_screen.dart:7164`

- [ ] [CRITICAL] `_hashPasscodeWithSalt` runs 100 000 SHA-256 iterations synchronously on the UI thread — the `for (var i = 0; i < 99999; i++)` loop at line 5528 blocks the main isolate for ~200–500 ms on every passcode creation (line 5616) and verification (`_LocalPasscodeVerify._verify` line 6039). Must be moved to `compute()` or `Isolate.run()` — `privacy_settings_screen.dart:5528`

- [ ] [CRITICAL] Direct state mutation in `build()` without `setState` in `_BirthdayDayMonthPickerState` — `if (_day > _maxDay) _day = _maxDay;` at line 7802 mutates `_day` during `build`. Flutter does not re-render in response; the dropdown `value` may exceed its `items` list, causing a blank selection or assertion failure when the user picks February with day > 28/29 — `privacy_settings_screen.dart:7802`

- [ ] [MAJOR] Aggressive 15-second polling timer fires 13 engine calls simultaneously — `initState` at line 88 starts a `Timer.periodic` that calls `_fetchPasswordState`, `_fetchGlobalTTL`, `_loadPasscodeState`, `_fetchPasskeys`, `_fetchBlockedCount`, `_fetchSessionsCount`, `_fetchAllPrivacy`, `_fetchMessagesPrivacy`, `_fetchArchiveSettings`, `_fetchAccountTTL`, `_fetchTopPeers`, `_fetchContentSettings`, and `_fetchWebsitesCount` every 15 seconds. Most are network round-trips. On a busy screen this is 52 engine calls/min and will routinely hit FLOOD_WAIT — `privacy_settings_screen.dart:88`

- [ ] [MAJOR] Top peers section renders with wrong default value before data loads — `_buildTopPeersSection` at line 1492 has no `_topPeersLoaded` guard (unlike `_buildArchiveAndMuteSection` which has `if (!_archiveLoaded) return []` and `_buildSensitiveContentSection` which has `if (!_sensitiveLoaded …) return []`). `_topPeersEnabled` defaults to `true`; if the real value is `false` the toggle momentarily shows enabled, and a fast tap can toggle from the wrong initial state — `privacy_settings_screen.dart:1492`

- [ ] [MAJOR] `_openApplyToExisting` fires up to 500 `setHistoryTTL` calls in a tight loop without `await` or rate-limiting — line 5275: `engine.setHistoryTTL(accountId, chat.chatId, _selectedTTL)` inside `for (final chat in chats)` with no await. All 500 requests are dispatched simultaneously; Telegram will return FLOOD_WAIT and the UI reports "applied to N chats" even when most calls failed — `privacy_settings_screen.dart:5275`

## reactions_detail — cleanup

- [ ] [CRITICAL] `_onTabSelected` line 361 — condition `!isReadTab && _masterReactors.isNotEmpty` fires for both the "All" tab (`tab == null`) AND any specific-emoji tab. For a specific emoji it sets `_allReactors = _masterReactors` (the first-page all-reactions data) and returns early, so `_filteredReactors` local-filters that incomplete set instead of fetching the emoji-specific list. If there are 50 😂 reactors but only 3 appear in the first 20 "All" results, the 😂 tab shows 3. Fix: guard should be `tab == null && _masterReactors.isNotEmpty` — `reactions_detail.dart:361`

- [ ] [CRITICAL] `_loadReactors` line 254 — same root cause: `if (_selectedTab != null && _masterReactors.isNotEmpty)` reuses master data for specific-emoji tabs, setting `_allReactors = _masterReactors` and `_nextOffset = _masterNextOffset` (an all-reactions cursor, not an emoji-specific cursor). Subsequent `_loadMore` calls use the all-reactions offset and will miss later pages of the specific emoji. Fix: this branch should only fire when `_selectedTab == null` — `reactions_detail.dart:254`

- [ ] [CRITICAL] DM read tab shows `"User ${participant.userId}"` instead of the peer's name — `_fetchReadInfo` for DM creates `ReadParticipantInfo(userId: widget.message.chatId, date: result.date)` at line 179 with no `name` field, so `_ReadParticipantRow` line 934 always falls back to the literal `'User ${participant.userId}'` string. Need to resolve the peer name from AppState/chat list (or a `GetUserInfo` engine call) before building the `ReadParticipantInfo` — `reactions_detail.dart:179`

- [ ] [MAJOR] `_groupedByEmoji` getter (line 328) and `_filteredReactors` getter (line 336) are both called inside `build()` (lines 426–428) and recompute from scratch on every rebuild — `_groupedByEmoji` builds a full `Map` by iterating all reactors, `_filteredReactors` allocates a new filtered list. Cache both as computed state fields; invalidate in `setState` calls that modify `_allReactors` or `_selectedTab` — `reactions_detail.dart:328`

- [ ] [MAJOR] `Image.file` at line 1088 loads full-resolution avatar photo with no `cacheWidth`/`cacheHeight`; every `_ReactorAvatar` (46 logical px, so ~92px on 2× display) decodes the full image into memory. Add `cacheWidth: (widget.size * 2).toInt(), cacheHeight: (widget.size * 2).toInt()` — `reactions_detail.dart:1088`

- [ ] [MAJOR] `_InlineCustomEmoji._onCacheUpdate` (line 1352) calls `setState(() {})` unconditionally on every global cache event regardless of whether this widget's `documentId` changed. With N custom-emoji widgets open simultaneously, any single cache write triggers N rebuilds. Guard: only call `setState` when `cache.getFile(widget.documentId) != null || cache.getThumb(widget.documentId) != null` changed since last render — `reactions_detail.dart:1352`

- [ ] [MAJOR] `_LoadingPlaceholder.build` (line 1239) uses `AnimatedBuilder` that rebuilds the entire `Column(3 rows)` subtree on every animation tick (~60fps). Wrap the `AnimatedBuilder`'s child in `RepaintBoundary` to isolate animation repaints from the parent widget tree — `reactions_detail.dart:1239`

- [ ] [MAJOR] Dead variable `wasReadTab` declared at line 359 but never referenced. Remove it — `reactions_detail.dart:359`

# send_files_box — cleanup

## CRITICAL

- [ ] [CRITICAL] `_onAiCaptionTap()` is a full stub — shows "Generating AI caption…" toast then exits, never calls any engine method and never updates `_captionController`. Variables `currentCaption` and `accountId` are fetched and immediately discarded. The AI caption button exists in the UI but does nothing for Premium users. — `send_files_box.dart:2098`

- [ ] [CRITICAL] `_tryClipboardImageWindows()` has a timestamp race: the PowerShell command string is interpolated with `DateTime.now().millisecondsSinceEpoch` at call-site, then after `Process.run` returns (ms later) a **second** `DateTime.now()` is used to construct `tmpFile` — the two timestamps will never match so the saved file is never found, and the method silently returns `false` every time. Fix: capture one `final ts = DateTime.now().millisecondsSinceEpoch` before the call and reuse it for both the command and `tmpFile`. — `send_files_box.dart:954`

- [ ] [CRITICAL] `_SendMenuButton` is passed `widget.starsPerMessage` (the immutable constructor prop, frozen at dialog open) instead of `_starsPerMessage` (the mutable state updated by `_showEditPriceDialog`). After the user edits the price, the send button label still shows the original total. Fix: change `starsPerMessage: widget.starsPerMessage` → `starsPerMessage: _starsPerMessage`. — `send_files_box.dart:2682`

## MAJOR

- [ ] [MAJOR] All `Image.file()` calls decode photos at full resolution despite displaying at small sizes — no `cacheWidth`/`cacheHeight` hints provided. Specific locations: `_SingleMediaPreview` (308 px wide preview, line 2866), `_GifPreview` (line 3111), `_FileCard` thumbnail (`_fileThumbSize = 64`, line 4160). Album thumbs at line 3512 also lack hints but have variable widths. Fix: add `cacheWidth: _previewWidth.toInt()` / `cacheWidth: _fileThumbSize.toInt()` to each.

- [ ] [MAJOR] `_AlbumPreviewState` registers `_shrinkAnim.addListener(() => setState(() {}))` — this triggers a full subtree rebuild on every animation frame during drag-shrink. Replace with `AnimatedBuilder` wrapping only the animated subtree. — `send_files_box.dart:3209`

- [ ] [MAJOR] Scroll shadow update is registered twice: `_scrollController.addListener(_updateScrollShadows)` at line 411 AND a `NotificationListener` in `build()` schedules an extra `addPostFrameCallback` call to the same function on every `ScrollNotification` (lines 2238–2244). Every scroll fires the shadow check twice — once inline, once deferred. Remove the `NotificationListener` path; the controller listener is sufficient.

- [ ] [MAJOR] `context.read<AppState>().photoEditorHintCount` is called inside `build()` (line 2388) — `read` does not register a dependency, so when `incrementPhotoEditorHintCount()` bumps the counter past 5, the hint text won't disappear until some unrelated `setState` triggers a rebuild. Replace with `context.watch<AppState>().photoEditorHintCount` or wrap in a `Selector`.

- [ ] [MAJOR] `_FileListPreviewState.build()` constructs all file rows in a `Column` with a `for` loop (line 3965) — all widgets are eagerly built. When many documents are attached (no hard cap in non-slow mode) this wastes build time. Convert to `ListView.builder` with `shrinkWrap: true` and `physics: NeverScrollableScrollPhysics()`.

## settings_screen — cleanup

- [ ] [CRITICAL] `_callsDisabled` never loaded from engine — `getCallsDisabledHere` exists in EngineService but is never called in `_loadSettings()`. The state field defaults to `false`, so "Accept calls on this device" always opens as ON regardless of the actual server setting. Fix: add `engine.getCallsDisabledHere(accountId)` to the `Future.wait` list at line 2138 and read it in the setState block. — `settings_screen.dart:2122-2161`

- [ ] [CRITICAL] New Quick Reply is added with no `shortcut_id` — `_showAddQuickReplyDialog` appends `{'shortcut': ..., 'message': ...}` to `_data['replies']` (line 3385) with no `shortcut_id` key. The delete handler checks `shortcutId > 0` (line 3326) before calling `deleteQuickReplyShortcut`, so newly created replies can never be deleted — the delete button silently no-ops. Fix: after adding, call `setBusinessFeature` immediately to persist and reload to get the server-assigned `shortcut_id`, or call a dedicated `createQuickReplyShortcut` engine method and capture the returned ID. — `settings_screen.dart:3381-3390, 3325-3336`

- [ ] [MAJOR] `base64Decode` called inside `GridView.builder` itemBuilder — In `_GiftCatalogScreen.build` (line 3731) and inside `_showEmojiAvatarPicker` / `_showEmojiStatusPanel` grid builders (lines 1040, 1191), `base64Decode(thumbB64)` runs on every rebuild for each visible item. This is heavy allocation in hot widget code. Fix: decode once into a `List<Uint8List>` when the data is first fetched and pass the decoded bytes down. — `settings_screen.dart:3731, 1040, 1191`

- [ ] [MAJOR] `_sameDevice` preference not persisted — `_sameDevice` defaults to `false` (line 2123) and is never loaded from any engine call or local storage. It resets to "off" every time the Calls tab is opened. Fix: persist the value via `AppState.setCallSameDevice` / a local pref and load it in `_loadSettings`. — `settings_screen.dart:2123`

- [ ] [MAJOR] Missing `RepaintBoundary` on scale-preview animation inner child — `_buildFloatingPreview` wraps its content in `AnimatedBuilder` with per-frame `Opacity` and `Transform.scale` changes (line 1675). The `child:` argument of `AnimatedBuilder` is correctly separated, but the inner `Container` with `_ScalePreviewContent` has no `RepaintBoundary`, so every animation tick dirties the entire preview subtree instead of just the transform layer. Add `RepaintBoundary` around `_ScalePreviewContent`. — `settings_screen.dart:1675-1729`

## shell — cleanup

- [ ] [CRITICAL] group-call `onToggleMute` has no optimistic state update (lines 380–385): personal call version calls `chatState.setActivePersonalCall(personalCall.copyWith(isMuted: !personalCall.isMuted))` immediately so the button reflects the new state while the engine round-trip completes; the group-call branch only fires `engine.setCallMuted(...)` and returns, so the mute icon stays frozen until a `GroupCallStateEvent` arrives — `shell.dart:380`

- [ ] [MAJOR] `isDark` computed but never read in `_buildTwoColumn` (line 512) and `_buildThreeColumn` (line 580) — the dead assignment still calls `Theme.of(context)`, which registers an unnecessary InheritedWidget dependency and causes both helpers to rebuild on every theme change — `shell.dart:512`, `shell.dart:580`

- [ ] [MAJOR] `_saveLayoutPrefs()` is called directly inside `build()` (lines 241 and 249) — this method does synchronous `File.writeAsStringSync` on the UI thread; it fires on every rebuild where `useVerticalFilters` or `forumViewAsMessagesKeys` differs from the cached snapshot, blocking the raster thread for the duration of the JSON encode + disk write — `shell.dart:241`

- [ ] [MAJOR] `_syncVisibility()` is called from `build()` (line 1129) and internally calls `_visibilityAnim.forward()` / `_visibilityAnim.reverse()` / `_slideAnim.forward()` / `_slideAnim.reverse()`; driving animation controllers from inside `build()` schedules extra frame callbacks mid-frame, leading to redundant rebuilds and occasional debug-mode "setState called during build" assertions — move to `addPostFrameCallback` or `didUpdateWidget` — `shell.dart:1129`

## shortcuts_settings_screen — cleanup

- [ ] [CRITICAL] `_commandGroups` (line 11) omits 22 of the 45 `ShortcutCommand` variants — formatting shortcuts (formatBold/Italic/Underline/Strike/Code/Blockquote/Spoiler/Clear/Link/Date), compose/editing (editLastMessage, replyPrevious, replyNext, openFilePicker, pastePlainText), navigation (cancelSearch, chatSwitchOverlay, chatSwitchOverlayReverse), and support commands (supportReloadTemplates/ToggleMuted/ScrollToCurrent/HistoryBack/HistoryForward) — all have real handlers registered in `ShortcutListener` and real default bindings in `_defaultBindings`, but because they are absent from `_commandGroups` they never appear in the settings screen; users cannot see or remap them — `shortcuts_settings_screen.dart:11`

- [ ] [MAJOR] all `_ShortcutRow` and separator widgets are eagerly instantiated inside `build()` before being handed to `ListView.builder` (lines 382–448) — `ListView.builder` only virtualises layout, not object creation; with ~100 items every `setState` (triggered on each row-tap to begin recording) tears down and rebuilds the full widget list — store command-group data and defer widget construction to `itemBuilder` so only visible rows are built — `shortcuts_settings_screen.dart:382`

## spoiler_animation — cleanup

- [ ] [MAJOR] `_generateSheet` has no error handling — if `_renderSpriteSheet` throws (OOM, compute-isolate crash), the `async` exception is swallowed by the fire-and-forget call at line 114/120 (`_generateSheet(type)` is never awaited), `_textGenerating`/`_imageGenerating` stays `true` permanently, all pending completers in `_textCompleters`/`_imageCompleters` are never resolved or rejected, and every subsequent `getSheet()` call silently queues a completer that can never complete — spoiler sprites stop loading for the entire app session. Fix: wrap `_generateSheet` body in try/catch, complete all queued completers with an error (or a fallback sheet), and reset the generating flag in a `finally` block. `spoiler_animation.dart:126`

- [ ] [MAJOR] Frame timing uses magic number `33` instead of `_kFrameDurationMs` — line 91: `timestamp.inMilliseconds ~/ 33`. The constant `_kFrameDurationMs = 33` is defined at line 27 and used correctly everywhere else (cache header write/read, particle lifetime calculations), but the live frame-index calculation ignores it. If `_kFrameDurationMs` is ever changed, the animation advances at the wrong speed while the cache stores frames timed differently, causing the particle motion to look wrong. Fix: `timestamp.inMilliseconds ~/ _kFrameDurationMs`. `spoiler_animation.dart:91`

# main — cleanup

- [ ] [CRITICAL] `_closeBehaviorSyncListener` is added to `appState` at line 353 but never removed in `dispose()` (lines 2023–2060) — all other seven sync-listeners are cleaned up, but this one is missing, leaking the closure and preventing `appState` from being garbage-collected — `main.dart:353`

- [ ] [CRITICAL] Anonymous passcode-lock listener at line 510 (`appState.addListener(() { _notifSystem.passcodeLocked = ... })`) is never stored in a variable, so it cannot be removed in `dispose()` — permanent listener leak for the lifetime of the object — `main.dart:510`

- [ ] [CRITICAL] Hardcoded English strings in the logout confirm dialog — `'Log out'` (title), `'Are you sure you want to log out?'` (body), `'Cancel'`, `'Log out'` (buttons) — must use `TrStrings` like every other string in this file — `main.dart:2786–2805`

- [ ] [CRITICAL] Hardcoded English string `'Please enter your passcode'` in `_submit()` — breaks all non-English locales; rest of passcode UI uses `TrStrings.lngPasscodePh()` etc. — `main.dart:2541`

- [ ] [CRITICAL] Duplicate unreachable `ctrl+r` handler at line 1519 — the identical handler at lines 1403–1406 already calls `ChatView.requestMarkActiveChatRead()` and `return`s, so the second block is dead code and will never execute — `main.dart:1519`

- [ ] [MAJOR] `_ThemeRevertOverlay` countdown timer fires every 100 ms and always calls `setState(() {})`, but the displayed countdown value (`seconds = ceil(remainingMs / 1000)`) only changes ~once per second — 90 % of rebuilds render identical content; track last-displayed seconds and only `setState` when the value actually changes — `main.dart:2261–2267`

- [ ] [MAJOR] `_waitForText` creates a `Timer.periodic` with no way to cancel it if the widget is disposed mid-poll — timer keeps running after unmount, walks the (already-torn-down) widget tree via `_findTextOnScreen`, and writes to a tmp file; the `Timer` reference is never stored — `main.dart:2004–2019`

- [ ] [MAJOR] `_dispatchHover` dispatches `PointerHoverEvent` with `pointer: _hoverPointer` (999999) without a preceding `PointerAddedEvent` for that device/pointer — compare `_dispatchScroll` which explicitly sends `PointerAddedEvent` first; hover may silently no-op or assert in the gesture binding — `main.dart:1339–1342`

- [ ] [MAJOR] `build()` in `_UniClientAppState` recomputes the full palette every rebuild: `palette.colorize(accentColor)` and `palette.adjustServiceColorsForWallpaper(appState.wallpaper)` are called unconditionally on every `context.watch<AppState>()` change (including unrelated state changes like unread count), even though the palette inputs only change when the user edits theme/accent/wallpaper — cache the result keyed on `(themeId, accentHex, wallpaper)` — `main.dart:2067–2087`

- [ ] [MAJOR] `listChats` debug command uses `chatState.chats.indexOf(c)` inside a `map()` over `take(20)`, making it O(n×m) where n is the full chat list size — use `enumerate`/`asMap().entries` on the already-taken slice instead — `main.dart:628`

## stats_chart — cleanup

- [ ] [MAJOR] `_cachedTP` calls `layout()` on every access — text painter cache only prevents allocation, not layout — `stats_chart.dart:1614`

  `TextSpan` does not override `==`, so `tp.text != span` is always true (reference inequality). Every call to `_cachedTP` re-runs `tp.text = span; tp.layout()` even for a cached painter. During ruler animation or footer drag, this fires ~14 layout() calls per paint frame (7 left labels + 7 right for DoubleLinear/currency). Fix: build and layout the painter once on first insert, and return it directly on cache hit:
  ```dart
  TextPainter _cachedTP(String text, TextStyle style) {
    final key = '$text|${style.fontSize}|${style.color?.value}';
    return textCache.putIfAbsent(key, () => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout());
  }
  ```

- [ ] [MAJOR] `_ChartAreaPainter.shouldRepaint` uses reference equality on two mutable maps that are mutated in-place — the comparisons always return `false` — `stats_chart.dart:2302` and `2313`

  `lineVisible` and `pieSliceHoverProgress` are both state maps that get mutated via `_lineVisible[id] = false` and `_pieSliceHoverProgress[key] = v` without ever replacing the map instance. So `lineVisible != old.lineVisible` (line 2302) and `pieSliceHoverProgress != old.pieSliceHoverProgress` (line 2313) are comparing the same object to itself — always `false`. Currently harmless because no `RepaintBoundary` isolates the painter, so `setState` rebuilds force a repaint anyway. If a `RepaintBoundary` is ever added (which is the obvious next optimization for this heavy painter), line toggles and pie hover animation will silently stop repainting.

- [ ] [MINOR] Dead ternary in `_paintPieLabelsInternal` — `isDark` is checked but both branches are identical — `stats_chart.dart:2240`

  ```dart
  final pieLabelColor = isDark ? Colors.white : Colors.white;
  ```
  The `isDark` parameter is ignored. White-on-slice-color is correct for dark mode but may be illegible on light-colored slices in light mode. Either drop the ternary and keep `Colors.white`, or decide on a light-mode color (e.g. `Colors.black87`).

## sticker_pack_viewer — cleanup

- [ ] [CRITICAL] `_showPremiumRequired()` is a stub — "Unlock" button (line 331) calls this, which only shows a SnackBar with text "Subscribe to Telegram Premium". No navigation, no URL open, no real upsell flow. Visible button does nothing actionable. Should open `https://t.me/premium` or a premium subscription dialog — `sticker_pack_viewer.dart:237`

- [ ] [CRITICAL] Silent fail in `_sendSticker` when `activeChat == null` (line 199-200) — returns early with no user feedback, sheet stays open. Reachable via `StickerPackViewer.showByName()` called outside a chat context. Should show a snackbar ("Open a chat first") or disable the send tap when no chat is active — `sticker_pack_viewer.dart:199`

- [ ] [MAJOR] No `RepaintBoundary` around animated `_StickerTile` widgets — Lottie (`_lottieData != null`) and Video (`_webmController != null`) tiles repaint on every animation frame, dirtying the entire grid repaint layer. `GridView.builder` at line 379 should wrap each tile's return in `RepaintBoundary` — `sticker_pack_viewer.dart:379`

- [ ] [MAJOR] WebM temp file path collision (line 542) — writes to `Directory.systemTemp/sticker_$docId.webm` with no unique suffix per instance. Opening the same pack twice simultaneously (or after a crash before dispose cleans up) causes two `_StickerTileState` instances to write concurrently to the same path, corrupting the file or causing playback errors — `sticker_pack_viewer.dart:542`

- [ ] [MAJOR] `Player.dispose()` called fire-and-forget in `dispose()` (line 582) — `media_kit`'s `Player.dispose()` is `async`; calling it without `await` in `dispose()` means audio/video resources (native threads, file handles) may not be released before the widget unmounts. Schedule via `player.dispose().catchError((_){})` assigned to a local before nulling the field — `sticker_pack_viewer.dart:582`

- [ ] [MAJOR] `_loadingFile` never reset to `false` after a failed/type-mismatch load (lines 514, 530) — if `getStickerFiles` returns an entry whose `mimeType` matches neither `isTgs` nor `isWebm`, the flag stays `true` permanently. The guard `if (_loadingFile) return` at line 513/529 then blocks any future retry. Should be reset to `false` in the else branch and catch — `sticker_pack_viewer.dart:514`

## story_editor — cleanup

- [ ] [CRITICAL] `_continueStroke` (line 899-903) mutates `_currentStrokePoints` in-place and then pings `_strokesNotifier`, but `_StrokePainter.shouldRepaint` (line 2182-2184) compares `old.currentPoints != currentPoints` — since it's the **same list object** (only mutated, never reassigned), this is always `false`. Result: `CustomPainter.paint()` is never scheduled during drawing. The live stroke does not render until the user lifts their finger (`_endStroke` calls `setState` which triggers a full rebuild). Fix: in `_continueStroke`, assign a new list (`_currentStrokePoints = [..._currentStrokePoints!, pos/scale]`) so the reference changes and `shouldRepaint` returns true. — `story_editor.dart:899`

- [ ] [CRITICAL] `_renderCanvasToBytes` places scene items at `canvas.translate(item.position.dx * _canvasWidth, item.position.dy * _canvasHeight)` (line 586-590). But `item.position.dx` is already in canvas-pixel units (0.._canvasWidth ≈ 0..540) — multiplying by `_canvasWidth` (540) translates to coordinates like 291600px on a 540px-wide canvas. All stickers and text items land far outside the export bounds and are clipped out. The exported story image contains background + paint strokes only — no text or sticker overlays. Fix: remove the multiplication: `canvas.translate(item.position.dx, item.position.dy)`. — `story_editor.dart:586`

- [ ] [MAJOR] `_ContactPickerDialogState.initState` (line 2458-2464) iterates ALL contacts and base64-decodes their avatar bytes synchronously on the main thread inside `initState`. For accounts with 200+ contacts this blocks the UI thread for tens of milliseconds, causing a visible freeze when the privacy dialog opens. Fix: do the decoding in a microtask or use `compute()`. — `story_editor.dart:2458`

- [ ] [MAJOR] `_StrokePainter.paint()` (line 2066) calls `canvas.saveLayer(Offset.zero & size, Paint())` unconditionally for ALL strokes. A `saveLayer` forces GPU off-screen compositing even for simple opaque pen strokes. Only the marker tool (needs `BlendMode.src` layer) and eraser (needs `BlendMode.clear` layer) actually require a layer. Move `saveLayer`/`restore` inside the `isMarker` and eraser branches; remove the outer one. — `story_editor.dart:2066`

- [ ] [MAJOR] `Image.memory` for sticker widgets (line 992) and in `_buildStickerGrid` (line 3153) provides no `cacheWidth`/`cacheHeight` hint. Flutter decodes the full-resolution sticker PNG on every widget rebuild instead of decoding once at display size. Add `cacheWidth: 120, cacheHeight: 120` to both `Image.memory` calls. — `story_editor.dart:992`

- [ ] [MAJOR] `_buildBlurLayers` (line 841) creates one `BackdropFilter` widget per committed blur stroke with no `RepaintBoundary` isolating them. Every `setState` (including routine pan/drag updates) causes all blur compositing layers to repaint together with the rest of the Stack. Add a single `RepaintBoundary` wrapping the blur layers list, or combine all blur paths into one `ClipPath`+`BackdropFilter`. — `story_editor.dart:841`

- [ ] [MAJOR] `_StickerPickerPanelState._buildStickerGrid` (line 3133-3138) rebuilds `allStickers` by iterating all packs and their stickers on **every** `build()` call. For large sticker collections this is O(N×M) work per frame. Cache the flat list (e.g., compute in `_loadStickerPacks` and store as `_allStickers`). — `story_editor.dart:3133`

- [ ] [MAJOR] `_barAnimDuration` constant (line 25, value `200`) is declared but never referenced. The `AnimationController` (line 252) hardcodes `Duration(milliseconds: 200)` independently. Remove the dead constant or use it. — `story_editor.dart:25`

## telegram_toast — cleanup

- [ ] [CRITICAL] double `OverlayEntry.remove()` assertion crash in `showStickerToast` — when replacing an active toast, `Future.delayed(_kFadeOutMs=1000ms, oldEntry.remove)` forcibly yanks the old entry without calling `_startHide()` on it; the old toast's 3 s hold timer + 1 s reverse animation later fires `onDone → entry.remove()` on the already-removed entry, hitting Flutter's `assert(_overlay != null)` — `telegram_toast.dart:290-296` vs `telegram_toast.dart:320-323`

- [ ] [CRITICAL] dead branch in `_buildMessage()` — the `packCount > 1` path (lines 461-468) returns the exact same `TextSpan` list as the final fallback return (lines 470-475); the pack count is never shown in the message, and the branch distinction does nothing — `telegram_toast.dart:461`

- [ ] [MAJOR] `_fadeOut` field is wrong direction and unused — defined as `CurvedAnimation(parent: ReverseAnimation(_ctrl), curve: Curves.easeIn)` which evaluates 0→1 during `_ctrl.reverse()` (increasing opacity, not decreasing); `build()` correctly bypasses it with `Tween<double>(begin:1, end:0).animate(CurvedAnimation(...))` inline, but this allocates a new `Tween` + `CurvedAnimation` on every animation frame during fade-out — `telegram_toast.dart:94,130-131` vs `telegram_toast.dart:203-208` and `telegram_toast.dart:595-598`

- [ ] [MAJOR] `TapGestureRecognizer` memory leak — two recognizers created inline inside `_buildMessage()` (a method called from `build()`) with no disposal path; gesture recognizers hold native resources and must be stored as state fields and disposed in `dispose()` — `telegram_toast.dart:432,446`

## telegram_tooltip — cleanup

- [ ] [CRITICAL] `_ImportantTooltipDelegate.getPositionForChild` left/right cases use wrong x and y at lines 432–437 — for `TooltipSide.right`, `x = targetRect.center.dx - arrowSkip` places the tooltip to the LEFT of the target center, and `y = targetRect.top - childSize.height` places it ABOVE the target instead of beside it; for `TooltipSide.left`, same y bug; correct values are `x = targetRect.right + _kArrowHeight` / `y = targetRect.center.dy - childSize.height / 2` for right, and `x = targetRect.left - childSize.width - _kArrowHeight` / same y for left — `telegram_tooltip.dart:432`

- [ ] [MAJOR] `_TooltipPositionDelegate.shouldRelayout` at line 200 only compares `pointer`, ignoring `screenSize`, `shift`, and `edgeSkip` — after a window resize the overlay tooltip keeps its stale position until the pointer moves — `telegram_tooltip.dart:200`

- [ ] [MAJOR] `AnimatedBuilder` at line 334 wraps a raw `Opacity` widget, which forces a composited layer on every frame without a `RepaintBoundary` — replace `Opacity`/`Transform.translate` with `FadeTransition`/`SlideTransition` (driven by `_curvedAnim`) to keep animation on the compositor thread, or wrap `tooltipContent` in `RepaintBoundary` — `telegram_tooltip.dart:334`

## theme_editor — cleanup

- [ ] [CRITICAL] `_currentBackground` is never set during `_handleImport` (line 382–413). `parseThemeFile` returns `backgroundImage` for zip themes, but the result is never stored in `_currentBackground`. When the user imports a `.tdesktop-theme` with a background and then exports it, the background is silently dropped. Fix: `_currentBackground = parsed.backgroundImage;` inside the `setState` block in `_handleImport`. — `theme_editor.dart:400`

- [ ] [CRITICAL] Hex editor channel mismatch for transparent colors. `_colorToHexString` emits `#RRGGBBAA` for colors with alpha < 255 (line 1176). `_parseHexColor` reads 8-char hex as `AARRGGBB` — `Color(int.parse(h, radix: 16))` (line 265). Applying the displayed hex value of any semi-transparent token through the inline editor (Apply button or Enter) produces completely wrong RGB and alpha values. Fix in `_parseHexColor`: for 8-char input, swap AA to front — `var reordered = h.substring(6) + h.substring(0, 6);` then parse that. — `theme_editor.dart:260`

- [ ] [MAJOR] Slug field shown and validated for local export. `_SaveThemeBoxState._save()` calls `_validateSlug(slug)` unconditionally (line 1343) even when `widget.cloudSave == false`, where the slug is irrelevant and not used in `_ExportResult`. The slug `TextField` is also rendered unconditionally (lines 1444–1479). This confuses users with a cloud-only concept during local save and can block the save if the user edits the field to something invalid. Fix: guard both the slug field and `_validateSlug` call behind `if (widget.cloudSave)`. — `theme_editor.dart:1343`

- [ ] [MAJOR] `entryIndex` mutable closure in `ListView.builder.itemBuilder` (line 682, incremented at line 800). The counter is a `var` declared once per `build()` call and incremented inside `itemBuilder`. `ListView.builder` may call `itemBuilder` for arbitrary visible indices, and if items are re-built individually (e.g. by key changes or framework-driven rebuilds of specific slots), the cumulative counter drifts. The result is that `_focusedIndex` highlighting and `onTap` capture the wrong entry index. Fix: precompute the entry index for each item when building `_cachedItems` and store it in `_ListItem`, or compute it from `index` by counting headers before `index` in the items list. — `theme_editor.dart:682`

- [ ] [MAJOR] `setState` called inside a `for` loop for PageDown/PageUp key handling (lines 509–524). Each iteration fires a separate `setState(() => _focusedIndex++)`, potentially scheduling tens of redundant rebuilds per keystroke. Flutter batches synchronous `setState` within a single frame but still enqueues a mark-needs-rebuild per call. Fix: compute the final `_focusedIndex` before the loop, then call `setState` once with the result. — `theme_editor.dart:509`

## titlebar — cleanup

- [ ] [MAJOR] `_oneSideControls` and `_resizeEnabled` are never queried at startup — `initState` calls `_queryMaximized()` and `_queryButtonLayout()` but has no equivalent calls for these two fields — they stay at their Dart defaults (`false` / `true`) until the native side pushes a change event — if the platform sets `resizeEnabled=false` at launch the maximize button renders incorrectly until the next native event fires — `titlebar.dart:83-88`

- [ ] [MAJOR] Static `MethodChannel` handler is last-writer-wins — `initState` calls `setMethodCallHandler(_onNativeCall)` and `dispose` sets it to `null` — if two `CustomTitlebar` instances are ever live simultaneously (hot-reload, nested navigation, duplicate mount) the first dispose silences all future native events for every instance — the channel should be wrapped in a reference-counted manager or the widget must be enforced as a strict singleton — `titlebar.dart:87,92`

## web_app_panel — cleanup

- [ ] [CRITICAL] `_handleOpenPopup` invalid-data guard calls `Navigator.of(context).pop()` at line 1095 — this pops the **web app panel itself** (not a dialog, no dialog is open at that point) instead of just ignoring bad input; any mini app that sends a popup with empty message or buttons crashes the user out of the panel — `web_app_panel.dart:1094`

- [ ] [CRITICAL] `_handleOpenScanQrPopup` shows an AlertDialog but never sends `scan_qr_popup_closed` back to the web view — the mini app JS is waiting for either `qr_text_received` or `scan_qr_popup_closed` and will hang in "scanning" state permanently after the user clicks OK — `web_app_panel.dart:519`

- [ ] [CRITICAL] `iconCustomEmojiId` is stored in `WebAppButtonConfig` (line 1042), drives `effectiveVisible` at line 1034 (button becomes visible even with empty text when emoji is set), but is never passed to `_WebAppButton` and `_WebAppButton.build()` renders nothing for it — a button made visible solely via emoji icon appears as a blank active button; the icon never shows — `web_app_panel.dart:1034,1654,1777`

- [ ] [CRITICAL] `_handleRequestEmojiStatusAccess` (line 853) directly calls `BotRequestEmojiStatusAccess` on the engine with no user-facing confirmation dialog — Telegram spec: "Prompts the user to grant permission for the mini app to manage emoji status" — compare `_handleRequestWriteAccess` which correctly shows a dialog first; user never sees the permission prompt — `web_app_panel.dart:853`

- [ ] [CRITICAL] `_handleSwitchInlineQuery` fires `BotSwitchInlineQuery` on the engine (line 484) but never calls `_close()` afterward — per Telegram Mini App spec `web_app_switch_inline_query` must close the mini app and switch to inline query; the panel stays open after the engine call completes — `web_app_panel.dart:483`

- [ ] [MAJOR] `_handleShareToStory` (line 535) shows a blocking AlertDialog saying "not supported" — `web_app_share_to_story` is fire-and-forget per Telegram spec (no response event expected); the dialog blocks the web app's UI thread and is wrong UX — should silently drop — `web_app_panel.dart:535`

- [ ] [MAJOR] Loading overlay is dismissed on `onPageFinished` (line 207) not on `web_app_ready` — Telegram spec: the native app must hide the loading screen only when the mini app sends `web_app_ready` (the app is render-ready, not just DOM-parsed); currently `web_app_ready` handler is a no-op `break` at line 271 — content can flash before the web app has finished its own initialization — `web_app_panel.dart:207,270`

- [ ] [MAJOR] `_SpinnerPainter.shouldRepaint` (line 1915) only checks `progress != oldDelegate.progress` — ignores `color` and `strokeWidth`; if theme changes while spinner is visible the old colors/stroke persist until progress ticks — `web_app_panel.dart:1915`

- [ ] [MAJOR] `_kProgressOpacity` constant (line 23) is defined as `0.3` but never referenced anywhere in the file — spinner color is set directly to `palette.windowSubTextFg` with no opacity applied — dead constant — `web_app_panel.dart:23`

## engine_models — cleanup

- [ ] [MAJOR] `CachedMessage.fromJson` decodes `content_raw` twice: `_decodeContentRawExtra` (line 900) and `_decodeContentRawTop` (line 911) both independently call `base64Decode` + `utf8.decode` + `json.decode` on the same string, then return `parsed['extra']` vs `parsed` respectively. Called back-to-back at lines 766–767 for every message parsed. Fix: merge into one decode that returns the top-level map, then extract `extra` from it at the call site. — `engine_models.dart:766`

- [ ] [MAJOR] `CachedMessage` missing `isVideoNote` getter — mediaType 5 (videonote) is the only media type in the 0–12 range with no boolean getter. All others have one (`isImage`, `isVideo`, `isVoice`, `isSticker`, `isGif`, `isFile`, `isPoll`, `isLocation`, `isContact`, `isInvoice`). Any UI rendering video-notes must use the raw `mediaType == 5` guard inline, and `isVideo` (which only matches type 2) misses them. — `engine_models.dart:1006`

- [ ] [MAJOR] `CachedMessage.copyWith` silently omits 6 contentRaw-derived fields from its parameter list: `topicId`, `topicName`, `topicColorId` (lines 1198–1200) and `stickerSetShortName`, `stickerSetId`, `stickerSetAccessHash` (lines 1209–1211). The body uses `topicId: topicId` etc. which resolves to `this.topicId` (no local). A call to `copyWith(contentRaw: newRaw)` produces an object with updated `contentRaw` but stale topic/sticker fields that were originally decoded from the old `contentRaw`. — `engine_models.dart:1198`

