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




## engine_models — cleanup

- [ ] [MAJOR] `CachedMessage.fromJson` decodes `content_raw` twice: `_decodeContentRawExtra` (line 900) and `_decodeContentRawTop` (line 911) both independently call `base64Decode` + `utf8.decode` + `json.decode` on the same string, then return `parsed['extra']` vs `parsed` respectively. Called back-to-back at lines 766–767 for every message parsed. Fix: merge into one decode that returns the top-level map, then extract `extra` from it at the call site. — `engine_models.dart:766`

- [ ] [MAJOR] `CachedMessage` missing `isVideoNote` getter — mediaType 5 (videonote) is the only media type in the 0–12 range with no boolean getter. All others have one (`isImage`, `isVideo`, `isVoice`, `isSticker`, `isGif`, `isFile`, `isPoll`, `isLocation`, `isContact`, `isInvoice`). Any UI rendering video-notes must use the raw `mediaType == 5` guard inline, and `isVideo` (which only matches type 2) misses them. — `engine_models.dart:1006`

- [ ] [MAJOR] `CachedMessage.copyWith` silently omits 6 contentRaw-derived fields from its parameter list: `topicId`, `topicName`, `topicColorId` (lines 1198–1200) and `stickerSetShortName`, `stickerSetId`, `stickerSetAccessHash` (lines 1209–1211). The body uses `topicId: topicId` etc. which resolves to `this.topicId` (no local). A call to `copyWith(contentRaw: newRaw)` produces an object with updated `contentRaw` but stale topic/sticker fields that were originally decoded from the old `contentRaw`. — `engine_models.dart:1198`

