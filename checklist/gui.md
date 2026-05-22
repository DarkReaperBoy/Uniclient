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

# photo_crop_editor — cleanup

# popup_menu — cleanup

## privacy_settings_screen — cleanup

# send_files_box — cleanup

## MAJOR


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

