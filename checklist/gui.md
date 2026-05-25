# GUI Audit — Cycle 2 Phase Ayugram (2026-05-23 01:12)

## Code Comparison (Dart vs AyuGram)

# bridge — No issues found

## Summary

The bridge.dart and related platform-specific implementations (bridge_ffi.dart, bridge_web.dart, bridge_stub.dart) form a well-designed FFI facade pattern with no placeholders, stubs, or wiring issues.

### Architecture Review

**bridge.dart** (lines 1–35):
- Clean facade pattern delegating to platform-specific implementations
- Proper separation of sync (`call`) and async (`callAsync`) operations
- Event streaming from Go backend via `Stream<Uint8List>`
- Correct initialization and lifecycle management (init/dispose)
- No hardcoded data or fake functionality

**bridge_ffi.dart** (lines 1–184):
- ✅ Correct FFI type definitions for all exported Go functions
- ✅ Proper memory management (calloc/free on both request and response)
- ✅ Uses `NativeCallable.listener` for event callbacks (correct for handling callbacks from any goroutine/thread)
- ✅ Async calls run in `Isolate.run` to avoid blocking the UI thread
- ✅ Proper platform detection and library path resolution (Linux, macOS, Windows, Android)
- ✅ Proper error handling (StateError if not initialized, null checks)
- ✅ Response memory is freed after copying (lines 141–146)

**bridge_web.dart** (lines 1–62):
- ✅ Correct JS interop declarations for WASM exports
- ✅ Event callback registration on init
- ✅ Async calls wrapped in `Future.microtask` (correct for WASM on main thread)
- ✅ Proper error handling and initialization checks

**bridge_stub.dart** (lines 1–25):
- ✅ Proper stub that throws `UnsupportedError` (not returning fake data)
- ✅ Returns empty stream and false for queries (safe defaults)

### No Violations Found

- ✅ No placeholder code (`TODO`, `FIXME`, `// coming soon`)
- ✅ No stub implementations in public API
- ✅ No hardcoded fake data
- ✅ Backend wiring is correct: all calls go through FFI/WASM to Go exports
- ✅ Events flow back from Go→Dart via NativeCallable/JS callback
- ✅ No unnecessary rebuilds (not a UI file)
- ✅ No performance issues (memory properly managed, async separation correct)
- ✅ No visual elements to compare (this is the transport layer, not UI)

### Conclusion

The bridge is the foundational transport layer for Go↔Dart communication. It correctly:
1. Loads platform-specific shared libraries (libcores.so/.dll/.dylib)
2. Manages FFI function pointers and type signatures
3. Handles memory allocation and deallocation
4. Separates blocking and non-blocking calls
5. Streams events from the Go backend
6. Cleans up resources

All platform implementations (native FFI, web WASM, stub) are complete and functional. This file and its dependencies require no changes.

# spell_service — Spell check & dictionary management

## Issues Found

- [x] **[CRITICAL]** Incomplete dictionary download marked as success — `spell_service.dart:200-213` ← `AyuGram/boxes/dictionaries_manager.cpp:300-315`
  - When `.aff` file download fails (HTTP status != 200), code executes `continue` instead of `return false`
  - Returns `true` at line 213 even though only `.dic` was downloaded
  - Hunspell dictionaries REQUIRE both `.dic` and `.aff` files to function
  - AyuGram correctly enforces both files in `DictionaryExists()` (spellchecker_common.cpp:432-441)
  - **Impact:** User sees "download successful" but dictionary is broken and won't be used for spell checking
  - **Fix:** Change line 204-205 to `return false` for both file types, OR track success of both files and return `dicSuccess && affSuccess`



# notification_system — Audit findings


# notification_types — Notification composition and settings

## Summary
✅ **No critical or major issues found.**

The `notification_types.dart` file provides pure, stateless notification composition functions that correctly transform `NotificationData` and `NotificationSettings` into displayable `NotificationContent`. The code is well-structured, properly integrated with the notification system, and aligns with AyuGram Desktop's notification logic.

## Verification Details

### ✅ Placeholders & Stubs
- **Result**: NONE FOUND
- All functions are fully implemented with real logic
- No empty callbacks, TODO comments, or stub returns
- All translation string calls are properly defined in `l10n/strings.dart`

### ✅ Backend Wiring
- `NotificationData` is correctly populated from engine message data in `chat_state.dart:2411-2455`
- Optional multi-account fields (`multiAccount`, `accountUsername`) are set via `copyWith()` in `main.dart:563-566` before display
- Content is properly enriched with spoiler masking and login code masking
- Rich text entities are parsed from JSON with proper error handling (line 412-427)

### ✅ Dimensional Accuracy vs. AyuGram
All notification widget dimensions match AyuGram style values:
- `_notifyWidth = 320.0` ← AyuGram `notifyWidth: 320px` ✓
- `_notifyMinHeight = 80.0` ← AyuGram `notifyMinHeight: 80px` ✓
- `_photoSize = 62.0` ← AyuGram `notifyPhotoSize: 62px` ✓
- `_borderWidth = 1.0` ← AyuGram `notifyBorderWidth: 1px` ✓
- `_notifyDeltaX/Y = 6.0/7.0` ← AyuGram `notifyDeltaX/Y: 6px/7px` ✓
- `_itemTopOffset = 12.0` ← AyuGram `notifyItemTop: 12px` ✓
- `_textTop = 7.0` ← AyuGram `notifyTextTop: 7px` ✓

### ✅ Behavioral Accuracy vs. AyuGram
Notification composition logic correctly implements AyuGram's patterns:

**Privacy handling** (matches `Manager::getNotificationOptions` in notifications_manager.cpp:1079-1108):
- `!settings.previewName` → hide chat/sender name
- `!settings.previewText` → hide message preview
- Spoiler login codes masked when sender is `777000` or other verification services

**Message type handling** (matches media types in `data_media_types.cpp`):
- All 13 types (0=text, 1=photo, 2=video, 3=audio, 4=voice, 5=videonote, 6=sticker, 7=gif, 8=file, 9=poll, 10=location, 11=contact, 12=invoice) correctly mapped
- Sticker emoji included in display
- Captions properly handled for photos/videos

**Reaction notifications** (matches `Manager::ComposeReactionNotification` in notifications_manager.cpp:1133-1220):
- Emoji extracted from reaction data
- Different text composed based on reacted media type
- `hideContent` flag properly respected

**Poll vote notifications** (matches `Manager::ComposePollVoteNotification` in notifications_manager.cpp:1222-1246):
- Option text extracted when available
- Question shown as fallback
- `hideContent` properly respected

**Reply button visibility** (matches `hideReplyButton` logic in notifications_manager.cpp:1097-1103):
- Hidden when previewText disabled ✓
- Hidden for reactions/polls ✓
- Hidden for channels ✓
- Hidden when slowmode active ✓
- Hidden when stars required ✓

### ✅ Error Handling
- JSON parsing in `_composeBodyEntities()` wrapped in try/catch (line 412-427)
- Invalid entity offsets/lengths filtered out (line 421)
- Regex matching for login codes safe and bounded (line 248, 399)
- Empty string checks prevent null/empty content

### ✅ Data Flow Integration
- Composition functions called correctly in `notification_popup.dart:568`
- Content cached to avoid recomputation on color changes
- Grouped notifications properly update `forwardCount` in `notification_system.dart:452`
- Scheduled message indicators (emoji + text) correct

### ✅ No Performance Issues
- Pure functions with no side effects
- String concatenations minimal and O(1)
- JSON parsing deferred until display time
- Regex pattern compiled once at module level
- No unnecessary list allocations

## Conclusion
The notification composition system is production-ready. Data flows correctly from engine → notification system → UI display, with proper privacy handling, media type support, and feature parity with AyuGram Desktop.

# app_state — Audit Findings


# audio_service — Listen reporting and position persistence

## Findings


# ayu_forward — Forward chunking & progress tracking

# bridge_ffi.dart — FFI bridge audit

## Summary
**Status: PASS** — No critical, major, or minor issues found.

`bridge_ffi.dart` is a well-engineered FFI bridge connecting Dart to the Go native library. It properly handles:
- Memory safety (allocation/deallocation with try-finally)
- Thread safety (NativeCallable.listener for async callbacks)
- Error handling (StateError for uninitialized state, null checks, length validation)
- Platform support (Linux, macOS, Windows, Android library paths)
- Complete Go export coverage (BridgeCallWithLen, BridgeFree, BridgeSetEventCallback)
- Integration with EngineService and the event stream

## Detailed Findings

### Memory Management ✓
- **Lines 127-150 (_doCall):** Correct allocation/deallocation pattern
  - Allocates `reqPtr` with `calloc<Uint8>()`
  - Allocates `outLenPtr` with `calloc<Int32>()`
  - Reads result safely
  - Properly freed in finally block (lines 148-149)
  - Frees Go's malloc'd pointer with `free(resultPtr)` (line 145)
  
- **Lines 168-177 (_onEvent):** Correct async callback memory handling
  - Copies bytes into Uint8List before freeing Go's pointer (line 174)
  - Properly frees Go's C.CBytes allocation with `malloc.free()` (line 175)
  - Comment explains why copy is necessary (NativeCallable.listener is async)

### Thread Safety ✓
- **Line 182 (NativeCallable.listener):** Correct choice for multi-threaded callbacks
  - Comment explains why (avoids "Cannot invoke native callback outside an isolate" crashes)
  - Unlike Pointer.fromFunction, marshals calls back to Dart isolate
  
- **Line 166 (broadcast stream):** Thread-safe event distribution
  - StreamController<Uint8List>.broadcast() is inherently thread-safe

### Error Handling ✓
- **Lines 70-71, 78-79:** StateError if not initialized
- **Lines 137-139:** Handles nullptr and len==0 from Go
- **Line 169:** Handles len<=0 in event callback
- **Lines 49-50:** Guards against re-initialization
- **Try-finally blocks:** Guarantee resource cleanup even on exceptions

### Platform Support ✓
- **Lines 93-118 (_findLibraryPath):** Handles all platforms correctly
  - Linux: tries relative/absolute paths, falls back to system search
  - macOS: checks framework path
  - Windows: looks for cores.dll
  - Android: uses system search
  - Unsupported platforms throw UnsupportedError
- **Library names match build output:** libcores.so (Linux/Android), libcores.dylib (macOS), cores.dll (Windows)

### Go Export Coverage ✓
All three Go exports from go/cmd/bridge/main.go are properly loaded:
- **BridgeCallWithLen** (lines 54-57): ✓ Loaded and called
- **BridgeFree** (lines 58): ✓ Loaded and called
- **BridgeSetEventCallback** (lines 59-62): ✓ Loaded and called

### Integration ✓
- **bridge.dart:** Correctly wraps BridgeImpl for platform abstraction
- **engine_service.dart:** Properly uses both sync (_callRaw) and async (_callAsync) paths
- **bridge_test.dart:** Integration tests verify functionality end-to-end
  - Raw bridge calls work (test: 'load library and make raw call')
  - Engine initialization works (test: 'init engine')
  - Async calls don't block (test: 'async bridge does not block')

### Code Quality ✓
- No TODO/FIXME/HACK comments
- No empty callbacks or stubs
- No hardcoded fake data
- Well-commented (explains why, not what)
- Proper resource cleanup in dispose()
- Correct type signatures matching Go exports

---

## No Issues Found
This bridge is production-ready. All requirements from CLAUDE.md are met:
- ✓ Pure Go (no external C dependencies)
- ✓ Uses dart:ffi correctly
- ✓ Memory-safe
- ✓ Properly tested
- ✓ No platform-specific hacks

# telegram_palette — No issues found

Verified against AyuGram Desktop C++ source (`window_themes_embedded.cpp`, `style_palette_colorizer.cpp`).

All checks passed:
- Lightness formula `v - (v * s) / 511` — exact match (`style_palette_colorizer.cpp:119`)
- Hue threshold 15° — matches (`window_themes_embedded.cpp:123`)
- Contrast delta threshold 64 — matches (`kEnoughLightnessForContrast`)
- Saturation & value colorize formulas — mathematically equivalent (0-1 vs 0-255 scale)
- All 24 accent colors (8 × 3 themes: DayBlue, Night, NightGreen) — exact hex match
- Colorize exclusion list (peer names, file colors, premium) — matches
- Night theme contrast enforcement color pairs — matches
- Lightness clamping (64/255 dark min, 160/255 light max) — matches
- Spot-checked dayBlue constant hex values — correct

# theme_preview — Avatar & photo dimensions don't match AyuGram

## Issues Found

- [x] [MAJOR] **Avatar color mapping algorithm mismatch** — `theme_preview.dart:154-163` ← `window_theme_preview.cpp:1037-1038`
  - Dart hardcodes a fixed array: `[Peer1, Peer8, Peer3, Peer2, Peer7, Peer4, Peer5, Peer6]` indexed by loop variable
  - AyuGram uses `Ui::DecideColorIndex(peerIndex) → ColorIndexToPaletteIndex()` with mapping `{0→0, 1→7, 2→4, 3→1, 4→6, 5→3, 6→5, 7→0}`
  - Result: Row indices 1, 2, 6, 7 render with wrong avatar colors compared to AyuGram

- [x] [MAJOR] **Photo bubble dimensions hardcoded instead of scaled** — `theme_preview.dart:573-574` ← `window_theme_preview.cpp:321-322`
  - Dart: `const photoW = 200.0; const photoH = 150.0;` (fixed)
  - AyuGram: `bubble.photoWidth = style::ConvertScale(bubble.photo.width() / 2);` → image is 654×395 → ≈327×197.5 after scaling
  - Result: Dart photo bubble is ~40% smaller than AyuGram. Visual mismatch in theme preview.

- [x] [MINOR] **Text rendering uses simple TextPainter instead of Ui::Text::String** — `theme_preview.dart:862-875` ← `window_theme_preview.cpp:295-310`
  - Dart uses basic `TextPainter.layout()` with maxWidth
  - AyuGram uses `Ui::Text::String` with complex text options, markup support, skip blocks for timestamp/status
  - Impact: Dart may have different word-wrap behavior and doesn't support styled text markup

- [x] [MINOR] **Reply/quote block styling simplified** — `theme_preview.dart:413-435` ← `window_theme_preview.cpp:874-914`
  - Dart: Simple box with left bar and text, no opacity or blockquote outline styling
  - AyuGram: Complex rendering with `kDefaultOutline1Opacity`, `blockquote.outline`, `blockquote.radius`, multi-layer clipping
  - Impact: Quote styling doesn't match AyuGram's visual design

## Status

Both are FUNCTIONAL (not stubs/placeholders). The preview renders complete visuals and all content is displayed. However, visual dimensions and color mappings deviate from AyuGram Desktop source in ways that affect theme preview accuracy.

**Recommendation:** Fix photo dimensions scaling (#573-574) first (high visibility). Avatar color mapping (#154-163) is cosmetic for a preview. Text rendering and reply styling are acceptable simplifications for Flutter—neither breaks functionality.

# wallpaper.dart — Audit Report

## Summary
The `wallpaper.dart` file implements wallpaper rendering (solid, gradient, pattern, image) with custom animated gradient features. The code is well-structured with proper image decoding and rendering. However, there are some findings comparing against AyuGram Desktop source:

---

## Findings

### [CRITICAL] Missing animated gradient duration specification in research/implementation mismatch
- **Description**: The code implements an 8-second repeating animation for multi-color gradients (`_MultiColorGradient`, `_PatternWallpaperState`), but this animation behavior is not documented in SPEC.md or research files. The research file (`research/telegram_desktop_ui.md`) mentions animated gradients for 3+ colors exist, but provides no animation cycle duration (8 seconds appears custom, not from Telegram Desktop).
- **Location**: `wallpaper.dart:315-318` (AnimationController duration) ← `research/telegram_desktop_ui.md` (missing animation cycle spec)
- **Impact**: The 8-second animation cycle is either:
  1. A custom feature not in AyuGram Desktop (unverified against spec)
  2. Hardcoded when it should be configurable or research-documented
  3. Not tested against actual Telegram Desktop behavior
- **Action Required**: Verify against AyuGram Desktop whether 3+ color gradients animate, and if so, document the cycle duration in `research/telegram_desktop_ui.md` (§ wallpapers, animate gradient section)

### [MAJOR] Pattern opacity calculation differs from AyuGram Desktop
- **Description**: The Dart code calculates pattern opacity using `patternIntensity.abs() / 100.0` (line 35), which treats negative intensity as absolute value. However, AyuGram Desktop's pattern opacity handling (in `data_wall_paper.cpp` and `chat_theme.cpp`) uses intensity values where negative means darkening blend mode. The Dart code's `patternOpacity.clamp(0.0, 1.0)` (line 264) loses sign information needed for blend mode selection.
- **Location**: `wallpaper.dart:35,264` ← `chat_theme.cpp:1117-1128` (blend mode selection logic)
- **Analysis**: AyuGram distinguishes:
  - `patternOpacity >= 0`: SoftLight blend mode (lighten)
  - `patternOpacity < 0`: DestinationIn blend mode (darken)
  The Dart code's `clamp(0.0, 1.0)` discards negative values, breaking darkening patterns.
- **Test Case**: Pattern with negative intensity should darken the background, not lighten it.

### [MAJOR] Pattern inversion logic incomplete
- **Description**: The `_isPatternInverted()` method (lines 675-687) inverts patterns based on HSV brightness, but the inversion implementation uses a color filter that only preserves alpha channel (`_invertColorFilter`, lines 573-578). This differs from AyuGram's `InvertPatternImage()` which inverts the alpha channel itself (lines 1156-1171 in `chat_theme.cpp`).
- **Location**: `wallpaper.dart:573-578,598-600` ← `chat_theme.cpp:1156-1171`
- **AyuGram Logic**: 
  ```cpp
  const auto value = (*ints >> 24);  // Extract alpha
  *ints++ = (value << 24) | (value << 16) | (value << 8) | value;  // Set RGBA to alpha
  ```
  (Converts pattern to grayscale by using alpha channel for all color channels)
- **Dart Implementation**:
  ```dart
  const _invertColorFilter = ColorFilter.matrix(<double>[
    0, 0, 0, 1, 0,  // R = A
    0, 0, 0, 1, 0,  // G = A
    0, 0, 0, 1, 0,  // B = A
    0, 0, 0, 1, 0,  // A = A (unchanged)
  ]);
  ```
  Both implementations do the same thing (convert to alpha-based grayscale), **so this is actually CORRECT**.
- **RETRACTION**: Upon detailed comparison, the Dart ColorFilter matrix `[0, 0, 0, 1, 0, ...]` correctly sets each channel to the alpha channel value, matching AyuGram's logic. **No issue here.**

### [MAJOR] Color average computation missing proper color space handling
- **Description**: The `computeAverageColor()` function (lines 699-714) averages RGB channels linearly from raw image bytes without accounting for SRGB gamma correction. AyuGram Desktop's `CalculateImageMonoColor()` approach (used in `chat_theme.cpp:1238-1240`) would handle this in the color space layer.
- **Location**: `wallpaper.dart:699-714` ← `chat_theme.cpp:1238-1240` (reference to `CalculateImageMonoColor`)
- **Impact**: Averaging linear RGB values produces a mathematically correct average but not perceptually uniform. This could result in a computed average that looks darker or lighter than expected. However, this is a minor visual issue for a fallback color.
- **Mitigating Factor**: The computed color is only used when `wallpaper.imageBytes != null` and no background colors are specified — a fallback for pattern/image wallpapers without a background gradient. The error is unlikely to be visible.

### [MAJOR] JPEG quality constant differs from AyuGram
- **Description**: The Dart code defines `_kJpegQuality = 87` (line 727), but AyuGram Desktop may use different JPEG quality constants for different contexts (encoding vs. caching).
- **Location**: `wallpaper.dart:727` ← No directly matching constant found in AyuGram source
- **Impact**: JPEG quality affects file size and visual fidelity during wallpaper encoding. Quality 87 is high-quality and reasonable, but not verified as matching Telegram's original specification.
- **Recommendation**: Document the choice of 87 in a code comment (why this value, not 80 or 90?), or search AyuGram Desktop's `storage/file_upload.cpp` for official wallpaper encoding parameters.

### [MEDIUM] Image tiling implementation differs from expected spec
- **Description**: The `_TiledImage` widget tiles images by scaling a single decoded image and repeating it horizontally (lines 656-673 in `_PatternWallpaper._tilePattern()`). The scaling preserves aspect ratio and centers the tiling pattern. However, there's no evidence in the AyuGram source that chat wallpapers support tiling — background images are typically fit-to-cover, not tiled.
- **Location**: `wallpaper.dart:234-236,656-673` ← `chat_theme.cpp` (no tiled background rendering found)
- **Analysis**: The Dart code has a `tiled` parameter on `WallpaperData`, but it's never used in chat rendering (only exists in factory constructors). The feature is implemented but unused.
- **Impact**: Dead code — tiling is not wired to the UI or engine. If the feature is intended, it needs to be integrated into chat message rendering or removed.

### [MEDIUM] Blur radius constant unverified
- **Description**: The `blurWallpaperImage()` function (line 773) uses a hardcoded blur radius of 24, which matches AyuGram Desktop's `kRadius = 24` (line 1175 in `chat_theme.cpp`). **This is correct.**
- **Location**: `wallpaper.dart:773` ← `chat_theme.cpp:1175`
- **Verdict**: ✓ Verified correct.

### [MEDIUM] Thumbnail size constant differs from AyuGram
- **Description**: The Dart code defines `_kThumbSize = 320` (line 728), but AyuGram Desktop may use different sizes. Need to verify this matches the backend's expectations for chat wallpaper thumbnails.
- **Location**: `wallpaper.dart:728` ← Not directly found in AyuGram source excerpts
- **Impact**: Thumbnails are used for preview rendering before full image load. If the size doesn't match the server's expectations, thumbnails may be resized again (inefficient) or display incorrectly.
- **Recommendation**: Verify with backend specification or test against a real Telegram server.

### [MEDIUM] Maximum wallpaper size constant `_kMaxWallpaperSize = 2960`
- **Description**: The constant is hardcoded and not verified against Telegram's official specification or AyuGram source.
- **Location**: `wallpaper.dart:729` ← No matching constant found in AyuGram source
- **Impact**: Wallpapers larger than 2960×2960 will be rejected or downscaled. If the server supports larger images, this will unnecessarily reject valid uploads.
- **Recommendation**: Verify against Telegram's official wallpaper upload API documentation or dynamic negotiation with the backend.

### [MEDIUM] Maximum aspect ratio constraint `_kMaxAspectRatio = 40.0`
- **Description**: Wallpapers with aspect ratios > 40:1 or < 1:40 are rejected (line 738). This is a reasonable sanity check, but not verified against Telegram's constraints.
- **Location**: `wallpaper.dart:730,738` ← Not found in AyuGram source
- **Impact**: Users cannot upload very wide or very tall wallpapers (e.g., panoramic images). This is likely intentional, but should be documented.
- **Recommendation**: Add a comment explaining why 40:1 is the limit.

### [MINOR] Pattern opacity clamping vs. Dart type safety
- **Description**: The `patternOpacity` parameter is clamped to [0.0, 1.0] (line 264), but AyuGram Desktop uses signed float64 for opacity (-1 to 1). The Dart code's clamping loses the sign needed for blend mode selection (SoftLight vs. DestinationIn).
- **Location**: `wallpaper.dart:264` ← `chat_theme.cpp:1117-1128`
- **Related**: This is part of the [MAJOR] pattern opacity issue above.
- **Verdict**: The clamping is overly restrictive and should preserve sign information.

### [MEDIUM] No engine wiring for wallpaper fetch/set
- **Description**: The `wallpaper.dart` file is pure UI rendering with no calls to the backend engine (no bridge.dart calls). Wallpapers are stored/loaded via `AppState.setWallpaper()` but never fetched from the engine using the bridge.
- **Location**: `wallpaper.dart:1-779` (entire file) ← No `bridge.call()` or engine API calls
- **Impact**: Wallpapers are stored locally in app state but never synchronized with the backend. If the user changes the wallpaper on a different client, the change won't be reflected in this app.
- **Test Case**: 
  1. Open app on Client A, set wallpaper to red
  2. Open app on Client B, set wallpaper to blue
  3. Return to Client A — wallpaper is still red (not synced from Server)
- **Required Action**: Implement backend wallpaper fetch on app startup (call engine's `GetWallpaper()` or equivalent) and sync changes when user modifies the wallpaper.

---

## Pass/Fail Summary

| Aspect | Status | Notes |
|--------|--------|-------|
| **Rendering (solid, gradient, pattern, image)** | ✓ PASS | Correct implementation, well-structured |
| **Animated gradients (3+ colors)** | ⚠ NEEDS VERIFICATION | Feature exists but duration unverified against spec |
| **Pattern inversion** | ✓ PASS | ColorFilter logic matches AyuGram Desktop |
| **Pattern opacity (blend mode selection)** | ✗ FAIL | Sign information lost in clamping |
| **Blur radius** | ✓ PASS | Matches AyuGram (24px) |
| **Image decoding/encoding** | ✓ PASS | Proper async decoding, JPEG encoding with reasonable quality |
| **Tiling feature** | ⚠ UNUSED | Implemented but never wired to chat UI |
| **Backend synchronization** | ✗ FAIL | No engine calls to fetch/set wallpapers |
| **Constant verification** | ⚠ PARTIAL | 87 (JPEG quality), 320 (thumb), 2960 (max size), 40.0 (aspect) all unverified |

---

## Recommended Actions (Priority Order)

1. **[CRITICAL]** Implement backend wallpaper synchronization:
   - Add bridge call to fetch wallpaper on app startup
   - Sync wallpaper changes to backend when user modifies

2. **[MAJOR]** Fix pattern opacity clamping:
   - Preserve sign information to distinguish SoftLight (>= 0) vs. DestinationIn (< 0) blend modes
   - Or split into separate fields: `patternIntensity` (0-100) and `patternBlendDarkens` (bool)

3. **[MAJOR]** Verify animated gradient duration:
   - Test 3+ color gradient animation against real Telegram Desktop or official client
   - Document the 8-second cycle in research file or add to SPEC.md

4. **[MEDIUM]** Remove or wire tiling feature:
   - Either implement chat wallpaper tiling UI or delete the unused `tiled` parameter

5. **[MEDIUM]** Document/verify all hardcoded constants:
   - JPEG quality (87)
   - Thumbnail size (320)
   - Max wallpaper size (2960)
   - Max aspect ratio (40.0)
   - Link to source (Telegram docs, AyuGram source, or backend API spec)

---

## Files Compared

- **Dart**: `/home/nako/Documents/uniclient/dart/lib/theme/wallpaper.dart`
- **AyuGram Desktop**:
  - `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/boxes/background_preview_box.cpp` (wallpaper preview/apply UI)
  - `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/ui/chat/chat_theme.cpp` (gradient rendering, pattern inversion)
  - `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/data/data_wall_paper.h` (wallpaper data structure)
  - `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/ui/chat/chat_theme.h` (API definitions)
- **Research**: `/home/nako/Documents/uniclient/research/telegram_desktop_ui.md` (spec for animated gradients)

# bridge_stub — No issues found

**File:** `dart/lib/bridge/bridge_stub.dart`

## Audit Summary

The stub implementation is correctly structured as a fallback for unsupported platforms. All findings are green.

## Verification

✅ **Interface Compliance** — All required methods match the FFI and web implementations:
- `Stream<Uint8List> get events` — returns empty stream (appropriate for stub)
- `bool get isInitialized` — returns false (appropriate for stub)
- `void init({String? libraryPath})` — throws UnsupportedError (correct stub behavior)
- `Uint8List call(Uint8List requestBytes)` — throws UnsupportedError (correct stub behavior)
- `Future<Uint8List> callAsync(Uint8List requestBytes)` — throws UnsupportedError (correct stub behavior)
- `void dispose()` — no-op (appropriate for stub)

✅ **No Placeholders or Stubs** — No TODO, FIXME, HACK, XXX, placeholder, fake, or mock patterns found.

✅ **Proper Conditional Import** — Used only via `bridge.dart` conditional import pattern:
```dart
import 'bridge_stub.dart'
    if (dart.library.ffi) 'bridge_ffi.dart'
    if (dart.library.js_interop) 'bridge_web.dart' as impl;
```
Fallback is only active on unsupported platforms (correct pattern).

✅ **Error Handling** — Appropriate `UnsupportedError` messages guide developers to use supported platforms.

✅ **Code Quality** — Minimal, focused, no unnecessary complexity. Correct for a fallback stub.

## Result: PASS

No issues found. The stub is well-designed and serves its purpose correctly.



# ayugram_settings_screen — No issues found

Compared against:
- `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_main.cpp` (hub screen)
- `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/ayu_logo.cpp` (logo loading)
- `AyuGramDesktop/Telegram/SourceFiles/settings/settings.style:189` (`settingsCloudPasswordIconSize: 100px`)
- `AyuGramDesktop/Telegram/Resources/langs/lang.strings:7976,8054-8059,8375` (all label strings)

All checks passed:

- **No stub callbacks** — every `onTap` does real work (navigation or engine call)
- **Backend wiring** — `engine.resolveUsername` at `:275` is real (`engine_service.dart:3831`); peer navigation falls back to browser if no active account
- **Logo size** — `TgTokens.settingsCloudPasswordIconSize = 100` matches `st::settingsCloudPasswordIconSize: 100px` exactly
- **Version string** — `'AyuGram Desktop v$appVersionString'` matches C++ `"AyuGram Desktop v" + AppVersionStr`
- **Description text** — hardcoded string at `:113` matches `ayu_SettingsDescription` exactly
- **Category labels** — all six match `ayu_CategoryFilters/General/Appearance/Chats/Other`
- **Link labels/targets** — Channel/Chats/Translate/Documentation match `ayu_Links*` strings and correct URLs
- **Links navigation** — `_navigateToPeer` calls `engine.resolveUsername` then `chatState.openChatById`, correct Flutter equivalent of C++ `showPeerByLink`
- **Overlay cleanup** — overlay is always removed before fallback URL open or navigation, no leak
- **No fake data** — icon index/color arrays are presentation-only fallbacks when PNG asset is missing, not mock data


# ayu_toggle — No issues found

## Summary
The Dart `AyuToggle` widget is a complete and accurate implementation of AyuGram's toggle component. All dimensions, colors, animations, and behaviors match the reference implementation in `AyuGramDesktop/Telegram/lib_ui/ui/widgets/checkbox.cpp` and the style definitions in `widgets.style:871-890`.

## Verification Details

### ✓ Dimensions & Style Constants (VERIFIED)
- `_border = 2.0` ← `widgets.style:880 (border: 2px)`
- `_diameter = 14.0` ← `widgets.style:882 (diameter: 14px)`
- `_width = 14.0` ← `widgets.style:883 (width: 14px)`
- `_animPadding = 2.0` ← `widgets.style:884 (animPadding: 2px)`
- `_matShift = -2.0` ← `widgets.style:881 (shift: -2px)`
- `_defDiameter = 16.0` ← `widgets.style:873 (defaultToggleDiameter: 16px)`
- `_defShift = 1.0` ← `widgets.style:872 (defaultToggleShift: 1px)`
- Duration: 150ms ← `widgets.style:879 (duration: 150)`

### ✓ Animation Curves (VERIFIED)
- Material uses `Curves.easeOutCubic` ← `checkbox.cpp:288 (anim::easeOutCubic)`
- Non-material uses `Curves.linear` ← `checkbox.cpp:288 (anim::linear)`
- Curve selection matches `AyuUiSettings::isMaterialSwitches()` ← `checkbox.cpp:282`

### ✓ Paint Implementation (VERIFIED)
Both implementations perform identical painting:
1. **Track background**: Draws rounded rect with animated color (checkboxFg → windowBgActive) ← `checkbox.cpp:130`
2. **Thumb position**: Interpolates from left to right based on animation value ← `checkbox.cpp:117`
3. **Thumb fill**: Solid background color (windowBg) ← `checkbox.cpp:135-136`
4. **Thumb border**: Stroke with animated color ← `checkbox.cpp:132-136`
5. **Material animation**: Thumb shrinks during animation via `_animPadding` ← `checkbox.cpp:123-126`

### ✓ State Management (VERIFIED)
- `AnimationController` properly initialized with `value: widget.value ? 1.0 : 0.0` (matches `_toggleAnimation.start()` in AyuGram)
- `didUpdateWidget` correctly triggers `forward()`/`reverse()` when value changes
- `dispose()` properly cleans up controller
- `shouldRepaint()` optimization is correct (rebuilds only on t, fgColor, or bgColor changes)

### ✓ Color Wiring (VERIFIED)
- Track color: interpolates between `palette.checkboxFg` and `palette.windowBgActive` ← matches `anim::brush(_st->untoggledFg, _st->toggledFg, toggled)`
- Thumb fill: `palette.windowBg` ← matches `_st->untoggledBg` and `_st->toggledBg` (both map to windowBg)
- Border color: same interpolation as track ← matches pen color in `checkbox.cpp:132`

### ✓ Callback Wiring (VERIFIED)
- `onChanged?.call(!widget.value)` correctly notifies parent of state changes
- Callback is invoked on tap, matching tap interaction model

### ✓ Mathematics (VERIFIED)
All geometric calculations match:
- `innerDiameter = switchDiam - 2 * switchShift` ← `checkbox.cpp:115`
- `innerRadius = innerDiameter / 2` ← `checkbox.cpp:116`
- `toggleLeft = _border + (fullWidth - switchDiam) * t` ← `checkbox.cpp:117`
- Material padding animation: shrink by `animPadding * (1 - t)` on all sides ← `checkbox.cpp:124-125`

### ✓ No Stubs or Placeholders
- No placeholder `onChanged: () {}` — callback is properly passed through
- No hardcoded values or mock data
- No "coming soon" messages or disabled features
- Animation actually runs (not a static widget)

### ✓ Performance
- `CustomPainter.shouldRepaint()` correctly avoids unnecessary repaints
- `AnimatedBuilder` only rebuilds on animation frame updates
- No expensive calculations in build methods
- No redundant state changes

### ✓ Canvas Operations
- Canvas clipping (`clipRect`) prevents overflow (safe practice)
- Canvas save/restore properly manages graphics state
- No missing paint operations

### Design Notes
- Lock icon (_locked) and X/V overlay features are intentionally omitted because `defaultToggle` style has `xsize: 0px, vsize: 0px, stroke: 0px` ← `widgets.style:885-888`
- Ripple effect is not implemented on standalone toggle (ripple handling would be in parent Checkbox widget in AyuGram) — not required for this component

### Sources
- `ayu_toggle.dart:1-176` — Dart implementation
- `AyuGramDesktop/Telegram/lib_ui/ui/widgets/widgets.style:871-890` — Style definitions
- `AyuGramDesktop/Telegram/lib_ui/ui/widgets/checkbox.cpp:1-200` — Reference C++ implementation
- `AyuGramDesktop/Telegram/lib_ui/ui/widgets/checkbox.h:40-65` — ToggleView class definition

## Conclusion
**PASS** — The AyuToggle widget is production-ready. No regressions, missing features, or backend wiring issues detected. Implementation closely mirrors the AyuGram reference in both behavior and visual output.

# call_panel — Backend wiring gaps, missing states, wrong device enumeration


# call_screen — Group Call Panel & Minimised Call Bar Audit


# chat_list_panel — Audit findings

## chat_list_panel — Visual/behavioral issues vs AyuGram

# chat_list_row — Audit findings

## CRITICAL

## MAJOR


# chat_view — Behavioral stubs, missing wiring, broken cycling


# choose_datetime_box — Calendar/DateTime/TimePicker boxes

## Dimensions verified ✓

All numeric constants match AyuGram exactly:
- `_cellW=48`, `_cellH=40`, `_cellInner=34` ← `defaultCalendarSizes` in `boxes.style:446`
- `_calPadH=14` ← `boxes.style:448` (padding margins 14px)
- `_daysRowH=40` ← `boxes.style:445` (daysHeight 40px)
- `_scheduleHeight=95`, `_scheduleDateWidth=136`, `_scheduleTimeWidth=72`, `_scheduleAtSkip=24`, `_scheduleDateTop=38`, `_scheduleAtTop=42` ← `boxes.style:891–909`
- `_kMinimalSchedule=10` ← `choose_date_time.cpp:28`
- `_kJumpDelay=700` ← `calendar_box.cpp:36` (`kJumpDelay = 2 * 350ms`)
- MonthYearPicker `_itemHeight=40`, 5 visible items = 200px ← `settings.style:681–682`
- Repeat period values all correct ← `choose_date_time.cpp:254–268`

---


# engine_service — Bridge service audit


# compose_entities.dart — Audit Findings

## Critical Issues

### [CRITICAL] Missing blockquote collapse state in JSON serialization
**Issue:** AyuGram's blockquote entity supports a `collapsed` flag (see AyuGramDesktop/Telegram/SourceFiles/api/api_text_entities.cpp:239, 372-377), but the Dart `toJson()` method doesn't serialize this state. When sending blockquote entities to the backend, the collapse state is lost.

- `compose_entities.dart:29` (toJson: blockquote mapping) — `AyuGramDesktop/Telegram/SourceFiles/api/api_text_entities.cpp:372-377` (blockquote has collapsed flag in MTP conversion)

### [CRITICAL] Blockquote markdown parsing not implemented
**Issue:** The markdown parser in `getTextWithAppliedMarkdown()` includes delimiters for bold, italic, strike, spoiler, and code (lines 382-389), but blockquote is completely missing. Telegram Desktop and AyuGram support `>` for blockquote markdown, but the Dart code cannot parse it. This means users cannot use markdown blockquotes in composition.

- `compose_entities.dart:382-389` (markdown delimiters: missing blockquote) — `AyuGramDesktop/Telegram/SourceFiles/chat_helpers/message_field.cpp` (markdown parsing should handle blockquote)

### [CRITICAL] Incomplete FormattedDate entity: missing flags
**Issue:** AyuGram's FormattedDate entity has 6 formatting flags (Relative, ShortTime, LongTime, ShortDate, LongDate, DayOfWeek) visible in `api_text_entities.cpp:241-265`. The Dart `insertDateTimestamp()` only stores a timestamp without any of these flags. When the date entity is serialized via `toJson()`, no flags are included, making the date formatting incomplete and potentially rendering incorrectly on the receiving end.

- `compose_entities.dart:293-315` (insertDateTimestamp: stores only timestamp, no flags) — `AyuGramDesktop/Telegram/SourceFiles/api/api_text_entities.cpp:241-265` (FormattedDate has 6 flags)
- `compose_entities.dart:32` (toJson: date maps to 'custom_date', no flag serialization) — `AyuGramDesktop/Telegram/lib_ui/ui/text/text_entity.h:59-68` (FormattedDateFlags enum)

## Major Issues

### [MAJOR] Markdown link syntax not parsed
**Issue:** The markdown parser handles inline formatting (**, __, ~~, ||, `, ```) but does not parse markdown link syntax `[text](url)`. Users cannot create links via markdown notation; they must use the manual link insertion method.

- `compose_entities.dart:382-389` (markdown delimiters list: no link pattern) — `AyuGramDesktop/Telegram/SourceFiles/chat_helpers/message_field.cpp` (markdown link parsing expected)

### [MAJOR] Alt text for blockquote not handled
**Issue:** While blockquotes can be toggled and rendered, there's no mechanism to store or serialize the blockquote's alt text state (if supported in the API). The entity serialization only outputs type, offset, length, URL, language, and documentId—no blockquote-specific data.

- `compose_entities.dart:34-39` (toJson: no blockquote data field) — `AyuGramDesktop/Telegram/SourceFiles/api/api_text_entities.cpp:372-377` (blockquote converted with data)

## Minor Issues

### [MINOR] Comment placement: misleading entity deletion documentation
**Issue:** Line 98 has a comment `// entity fully before deletion` but this appears to be placed incorrectly—it comes after the condition checking if deletion is after the entity. The logic is correct, but the documentation is in the wrong location and could cause confusion.

- `compose_entities.dart:98` (comment placement in deletion logic) — indicates a documentation maintenance issue, not a functional bug

## Summary

**Total Issues:** 5 (3 critical, 1 major, 1 minor)

**Functional Impact:**
1. Blockquote entities lose their collapse state when sent to backend
2. Users cannot format blockquotes using markdown syntax
3. Date formatting loses all flag information (relative, time format, date format, weekday)
4. Markdown link syntax is not supported
5. Blockquote alt text state is not preserved

**Verification Status:** All issues compared against AyuGram Desktop source (api_text_entities.cpp, text_entity.h, message_field.cpp).

# confirm_box — Audit

## confirm_box — §36.2 ConfirmBox / showConfirmBox


## confirm_box — §36.2 DeleteConfirmBox / _DeleteContent

## confirm_box — §36.13 Report Flow



## contacts_screen — Edit/Add contact notes limit wrong, sharePhone flag missing, starsPerMessage never populated, _openChatInBackground doesn't close dialog

- [x] [CRITICAL] `_notesMaxLength` — already fixed: set to 128
- [x] [CRITICAL] `sharePhone` — already fixed: checkbox + flag passed through Dart→Go→TDL (`AddPhonePrivacyException`)
- [x] [MAJOR] `starsPerMessage` — already fixed: populated from `GetSendPaidMessagesStars()` in Go `convertUser`, flows through protobuf
- [x] [MAJOR] `_openChatInBackground` — already fixed: null/empty `accountId` guard at line 614-615 prevents silent no-op
- [x] [MAJOR] `_EditContactBox` first-name max length — already fixed: `maxLength: 64` on both first-name and last-name fields
- [x] [MAJOR] `_ShareContactBox` server search — already fixed: `_doServerSearch` calls `searchGlobalChats` after 300ms debounce
- [x] [MAJOR] `_ShareContactBox` column count — already fixed: `_columnCount = 4` (constant)
- [x] [MAJOR] `_sortedChats` Saved Messages — already fixed: uses `selfUserId` comparison instead of title string

# create_giveaway_box — Audit findings


# edit_mark_box.dart — Audit vs AyuGram EditMarkBox

## Summary
The Dart file exists but is **DEAD CODE**—never imported or used anywhere. The actual mark editing UI is implemented inline in `ayu_chats_page.dart` with a different (buggy) implementation. Critical differences from AyuGram include: missing input validation, hardcoded UI strings, missing error feedback, and swapped button order.

---

## Critical Issues

---

## Major Issues

- [x] **[MAJOR]** Missing error visual feedback in active implementation — `ayu_chats_page.dart:_EditMarkBoxContentState` has **no error state, no validation, no error display**. `edit_mark_box.dart` has error handling (`_showError` flag + red border), but that file is dead code. Only the broken version is used. `ayu_chats_page.dart:~1010–1030` ← `edit_mark_box.cpp:73–77` (shows error handling via `_text->showError()`)

- [x] **[MAJOR]** Missing onSubmitted handler in used implementation — `ayu_chats_page.dart:_EditMarkBoxContentState.build()` has **no `onSubmitted` callback** on the TextField. Pressing Enter doesn't submit. AyuGram wires Enter via `_text->submits() | rpl::on_next()`. `ayu_chats_page.dart:~1013` (TextField has no onSubmitted) ← `edit_mark_box.dart:92` (has `onSubmitted: (_) => _submit()`) vs `edit_mark_box.cpp:65–66`

- [x] **[MAJOR]** Button order mismatch vs AyuGram — Dart has Reset (left), Cancel (middle), Save (right). AyuGram has Reset (left), Save (middle), Cancel (right). Primary action (Save) is in wrong position. `ayu_chats_page.dart:~1021–1027` ← `edit_mark_box.cpp:44–58`

- [x] **[MAJOR]** Border color inconsistency — `ayu_chats_page.dart` uses `p.windowBgActive` for both normal and focused borders. Focused border has no color change indication (both are same). AyuGram styled via `st::defaultInputField` which includes proper active/inactive states. `ayu_chats_page.dart:~1015–1020` ← `edit_mark_box.cpp:29–33`

- [x] **[MAJOR]** Padding/spacing mismatch — `ayu_chats_page.dart` uses `EdgeInsets.fromLTRB(24, 0, 24, 8)` (top=0). `edit_mark_box.dart` uses `EdgeInsets.fromLTRB(24, 2, 24, 8)` (top=2). AyuGram uses `st::contactPadding` (49px left, 2px top, 0px right, 14px bottom) which neither matches. `ayu_chats_page.dart:~1012` + `edit_mark_box.dart:87` ← `edit_mark_box.cpp:37,93`

- [x] **[MAJOR]** Hint text styling mismatch — `ayu_chats_page.dart` adds alpha transparency to hint color: `.withValues(alpha: 0.4)`. `edit_mark_box.dart` uses hardcoded `fontWeight.w600` without alpha. Both deviate from AyuGram's standard InputField styling. `ayu_chats_page.dart:~1017–1018` + `edit_mark_box.dart:96` ← `edit_mark_box.cpp:29–33`

---

## Recommended Actions

1. **Delete `edit_mark_box.dart` entirely** — it's unreferenced dead code that only confuses maintenance.

2. **Fix `ayu_chats_page.dart` implementation:**
   - Add input validation: reject empty strings with visual error feedback
   - Add `onSubmitted: (_) => _save()` to TextField
   - Change button order to match AyuGram: Reset (left), Save (middle), Cancel (right)
   - Use localization keys instead of hardcoded strings
   - Fix border colors: use different color for focused state
   - Align padding with AyuGram style values

3. **Migrate to a unified extracted component** — Once fixed, move the implementation back to a reusable file (but actually import it this time).



# emoji_panel — Audit findings



# filter_column — Audit findings


# folders_settings_screen — Audit findings

# forum_topic_icon — Audit findings

## hamburger_drawer — audit findings

# info_panel — Audit findings



# input_dialogs — Audit Findings





## input_dialogs — create_poll_box: Default close period wrong

- [ ] [MAJOR] AyuGram defaults `closePeriod` to 24 hours (86400 s) when the duration toggle is first enabled; Dart defaults to 300 seconds (5 minutes), which is wrong — `input_dialogs.dart:1796` ← `AyuGram/boxes/create_poll_box.cpp:2722-2725`

## input_dialogs — create_poll_box: Duration picker preset list wrong

- [ ] [MAJOR] AyuGram presets are `{3600, 3*3600, 8*3600, 24*3600, 72*3600}` (1h, 3h, 8h, 24h, 72h); Dart uses `{3600, 10800, 28800, 86400, 259200}` (1h, 3h, 8h, 24h, 3 days). The last entry differs: AyuGram uses 72 hours (3 days = 259200 s), which actually matches. However AyuGram lacks a "3 days" label option. On a recheck, both match in values. No issue here — SKIP.

## input_dialogs — create_poll_box: Missing "Hide Results" toggle

- [ ] [CRITICAL] AyuGram has a "Hide Results" toggle (`tr::lng_polls_create_hide_results`) inside the duration section that sets `Flag::ResultsHidden` on the poll; Dart has no equivalent toggle anywhere in the create-poll UI — `input_dialogs.dart:2271-2296` ← `AyuGram/boxes/create_poll_box.cpp:2728-2738`

## input_dialogs — create_poll_box: addOptions (Allow Adding Options) not locked when quiz mode enabled

- [ ] [MAJOR] AyuGram locks/disables the "Allow Adding Options" toggle when quiz mode is on (`updateAddOptionsLocked` forces it off if `quiz->toggled()`); Dart allows both quiz mode and allow-adding-options to be active simultaneously, which is invalid — `input_dialogs.dart:2225-2230` ← `AyuGram/boxes/create_poll_box.cpp:2760-2770`

## input_dialogs — create_poll_box: Revoting toggle not locked by quiz mode

- [ ] [MAJOR] AyuGram calls `revoting->setToggleLocked` inside `updateQuizDependentLocks` when quiz is toggled (respecting `PollData::Flag::RevotingDisabled`); Dart simply disables `_allowRevoting` via `onChanged: _quiz ? null : ...` but does not prevent the switch from being visually toggled — `input_dialogs.dart:2236-2238` ← `AyuGram/boxes/create_poll_box.cpp:2771-2778`

## input_dialogs — create_poll_box: Quiz + multipleChoice correct answer uses radio only, not checkbox

- [ ] [MAJOR] AyuGram supports `multiCorrect` mode (checkboxes for correct answer when both quiz and multiple-choice are enabled simultaneously); Dart always uses `Radio<int>` for correct-answer selection with no checkbox path, so quiz+multiple-choice gives wrong UX — `input_dialogs.dart:2375-2386` ← `AyuGram/boxes/create_poll_box.cpp:579-621, 836-848`

## input_dialogs — create_poll_box: Option media upload not tracked for stale state

- [ ] [MAJOR] AyuGram tracks `PollMediaState` per option and calls `refreshStaleMedia` with a 45-minute threshold to invalidate uploads that expired; Dart stores only file paths (`_optionMediaPaths`) with no upload state tracking — media attached to options may be silently lost at send time — `input_dialogs.dart:1786, 1967-2007` ← `AyuGram/boxes/create_poll_box.cpp:111, 195-196`

## input_dialogs — create_poll_box: Poll description field missing media attach support

- [ ] [MAJOR] AyuGram calls `addMediaButton(description, state->descriptionMedia)` to allow attaching media to the description field; Dart's description field has no media attach button — `input_dialogs.dart:2133-2151` ← `AyuGram/boxes/create_poll_box.cpp:2485-2486`

## input_dialogs — edit_invite_link: Expire option semantics inverted

- [ ] [CRITICAL] AyuGram stores expire values as negative offsets for preset durations (`-kHour`, `-kDay`, `-kDay*7`) and `kMaxLimit` (INT_MAX) for Never, and positive timestamp for custom; Dart uses positive seconds-from-now offsets (3600, 86400, 604800) mapped directly. When saving, AyuGram does `now - state->expireValue` to convert negative offsets to future timestamps; Dart does `now + _expireOption` which produces the same result numerically, but the Dart custom expiry path (`_customExpireDate`) stores an absolute timestamp and passes it directly — this part is correct. However the preset matching on load (`(remaining - k).abs() < k * 0.1`) is fragile and will misclassify links near boundary — `input_dialogs.dart:1308-1333` ← `AyuGram/boxes/edit_invite_link.cpp:90-94, 242-253`

## input_dialogs — edit_invite_link: Expire section hidden for subscription links but usage section still shown

- [ ] [MAJOR] AyuGram wraps the usage section in `usagesSlide` and hides it when `requestApproval` is on (`toggleOn(state->requestApproval.value() | rpl::map(!_1))`); Dart hides the "Usage Limit" section inside an `AnimatedSize` only when `_requestApproval` is true — this matches. However the Usage section is also hidden in AyuGram when `subscriptionLocked` (early return at line 202 skips both Expire and Usage sections); Dart shows Usage even for subscription-locked links because `if (!_subscriptionLocked)` only gates the Expire section — `input_dialogs.dart:1582` ← `AyuGram/boxes/edit_invite_link.cpp:202-204`

## input_dialogs — edit_invite_link: Request Approval hidden for subscription-locked links

- [ ] [MAJOR] AyuGram explicitly sets `requestApproval = nullptr` when `isPublic || subscriptionLocked`, so it never renders for subscription links; Dart checks `if (!_subscriptionLocked)` for the Subscription toggle but the Request Approval toggle is checked with the same guard — this is correct. However for `isPublic` links, AyuGram also hides Request Approval; Dart renders it because the `isPublic` flag only suppresses the Subscription toggle — `input_dialogs.dart:1510-1530` ← `AyuGram/boxes/edit_invite_link.cpp:112-120`

## input_dialogs — country_select_box: Row height differs

- [ ] [MAJOR] AyuGram uses `st::countryRowHeight` (from `style_boxes.h`, typically 36px) with a top offset `st::countriesSkip` before the first row; Dart uses `itemExtent: 36` but adds a top padding of 12px (`EdgeInsets.only(top: 12)`), not matching `st::countriesSkip` which is a styled value — `input_dialogs.dart:1143` ← `AyuGram/ui/boxes/country_select_box.cpp:361-364`

## input_dialogs — country_select_box: Flag emoji not shown by AyuGram; Dart shows it

- [ ] [MAJOR] AyuGram's country row renders only the country name and calling code (`+XX`) — no flag emoji anywhere in `paintEvent`; Dart shows a flag emoji (`c.flag`) in the phone-prefix picker button and in the country list rows. This adds visual elements not present in the reference — `input_dialogs.dart:817, 1161` ← `AyuGram/ui/boxes/country_select_box.cpp:377-397`

## input_dialogs — country_select_box: Ripple animation missing on row selection

- [ ] [MAJOR] AyuGram renders `RippleAnimation` per row on press (`_ripples[i]->paint`); Dart uses plain `InkWell` with no explicit ripple shape matching the row — visual fidelity mismatch — `input_dialogs.dart:1151-1185` ← `AyuGram/ui/boxes/country_select_box.cpp:371-374`

## input_dialogs — country_select_box: Accessibility roles and screen-reader support absent

- [ ] [MAJOR] AyuGram implements full accessibility roles (`accessibilityRole`, `accessibilityChildFocused`, `accessibilityChildNameChanged`, etc.) on the inner widget; Dart has no accessibility semantics on the country list — `input_dialogs.dart:1080-1195` ← `AyuGram/ui/boxes/country_select_box.cpp:55-65`

# emoji_data — Emoji Keywords Implementation

- [ ] [MAJOR] `loadServerKeywordsDiff` replaces entire keyword emoticon list instead of appending new / removing deleted entries: AyuGram's `ApplyDifference` appends emoticons for `MTPDemojiKeyword` entries and surgically removes individual emoticons for `MTPDemojiKeywordDeleted` entries (keeping the rest intact). Dart unconditionally overwrites `pack.keywords[entry.key]` with the incoming slice, so if a diff only adds 1 new emoticon to a 5-emoticon keyword, the existing 5 are thrown away — `emoji_data.dart:2823` ← `AyuGram/chat_helpers/emoji_keywords.cpp:256-291`

- [ ] [MAJOR] Keys from server diff are not `.trim()`med before storage — AyuGram's `NormalizeKey` does `.toLower().trimmed()` before inserting into `data.emoji`; the Dart `_LangPack.load()` and `loadServerKeywordsDiff` never trim, so a keyword with trailing whitespace in the API response is stored as-is and will silently fail to match any query — `emoji_data.dart:2716-2723` and `dart:2819-2830` ← `AyuGram/chat_helpers/emoji_keywords.cpp:172-173` (NormalizeKey), `251`, `275`

- [ ] [MAJOR] `_prioritizeRecent` compares the full emoji string (possibly with skin-tone modifier) against the stored recent emoji string — AyuGram's `PrioritizeRecent` uses `(*emoji)->original()` to strip the skin-tone variant before comparing, so recents like `👋🏽` correctly bubble up `👋` results; Dart's `e.emoji == recent` direct compare will fail for any variant mismatch, leaving all variant emoji un-promoted — `emoji_data.dart:3026` ← `AyuGram/chat_helpers/emoji_keywords.cpp:660-662`

- [ ] [MAJOR] `loadCacheFromDisk` and `_writeCacheToDisk` run synchronously on the main isolate — AyuGram offloads `ReadLocalCache` and `WriteLocalCache` to a background thread via `crl::async` (returning to main via `crl::on_main`) to prevent UI jank; Dart blocks the Flutter raster thread while parsing/writing potentially thousands of JSON keyword entries — `emoji_data.dart:2837-2863` ← `AyuGram/chat_helpers/emoji_keywords.cpp:372-380` (async read), `442-453` (async write)

- [ ] [MAJOR] No `MTPmessages_GetEmojiKeywordsLanguages` call: AyuGram first queries the server for the correct set of language IDs to fetch (`emoji_keywords.cpp:703`) before requesting any lang-pack data, ensuring only languages with server-side keyword data are fetched. Dart's caller (`chat_view.dart:3722-3725`) hardcodes 3 languages (`selectedLanguageCode`, system locale, `'en'`) without consulting the server, causing unnecessary requests for unsupported languages and potentially missing server-recommended ones — `emoji_data.dart` (API surface of `loadServerKeywords`) ← `AyuGram/chat_helpers/emoji_keywords.cpp:692-716`

- [ ] [MAJOR] `_emojiKeywordsFetched` flag in the caller is never reset when the active account changes — AyuGram's `EmojiKeywords` is instantiated per `Main::Session` and its `apiChanged()` re-triggers a refresh whenever the active session changes; Dart sets `_emojiKeywordsFetched = true` once and never clears it, so switching accounts silently reuses stale keyword data from the previous account — `dart/lib/ui/chat_view.dart:3712-3713` ← `AyuGram/chat_helpers/emoji_keywords.cpp:522-529`

# instant_view — Audit findings

- [ ] [CRITICAL] Generic embed block renders a static link card instead of actual iframe content — non-YouTube/Vimeo/Twitter/SoundCloud embeds (Instagram, TikTok, Reddit posts, etc.) display zero content — `instant_view.dart:2431` (`_buildGenericEmbed` called as fallback) ← `iv/iv_prepare.cpp:672` (`tag("iframe", attributes)` — AyuGram renders a real `<iframe>` via WebView for every embed type)

- [ ] [CRITICAL] YouTube embed play taps `_playVideo("https://www.youtube.com/watch?v=…")` which passes the URL directly to media_kit/mpv — YouTube requires yt-dlp for streaming and will always throw, silently falling back to `launchUrl` (external browser) — the primary "Play" action is dead — `instant_view.dart:2441` ← `iv/iv_prepare.cpp:657-664` (AyuGram renders YouTube via iframe `src=` using the embed URL, which loads the native YouTube player in WebView)

- [ ] [MAJOR] `_buildEmbedPost` does not render the author photo — AyuGram renders a `<figure>` element with `background-image: url(photoFullUrl)` inside the `<address>` — `instant_view.dart:1004-1027` (no photo widget anywhere) ← `iv/iv_prepare.cpp:689-697` (`address += tag("figure", { { "style", "background-image:url('" + src + "')" } })`)

- [ ] [MAJOR] `_buildEmbedPost` does not render the publication date — AyuGram includes a `<time>` tag with the formatted date inside the embed post address block — `instant_view.dart:1004-1027` (no date) ← `iv/iv_prepare.cpp:700-702` (`address += tag("time", Date(date))`)

- [ ] [MAJOR] Channel block always initialises `_joined = false` regardless of actual membership — never queries current membership state — user who already follows the channel still sees "Join" button — `instant_view.dart:2647` ← `iv/iv_prepare.cpp:768-770` (AyuGram conditionally adds `class="joined"` based on real membership data, updated reactively via `inChannelValues` producers)

- [ ] [MAJOR] Map block fetches tiles directly from `https://tile.openstreetmap.org/…` exposing OSM requests from the client — AyuGram routes maps through a Telegram-served resource URL (`resource("map/" + GeoPointId …)`) which is downloaded by the engine, not the UI — `instant_view.dart:1534` ← `iv/iv_prepare.cpp:1233-1238` (`QByteArray Parser::mapUrl(…)` returns a `/map/…` resource path served by the data handler)

- [ ] [MAJOR] Missing "Report IV" action — AyuGram fires `Event::Type::Report` when the page contains a `report-iv` context link (accessible via the page menu) — Dart has no report button, no menu item, and no handler — `instant_view.dart:200-240` (appBar actions list, no report) ← `iv/iv_controller.cpp:1036-1040` (`if (context == u"report-iv") _events.fire({ .type = Event::Type::Report … })`)

- [ ] [MAJOR] Missing keyboard shortcuts Ctrl+W (close IV), Ctrl+M (minimize) — AyuGram handles these inside `processKey` — Dart's `CallbackShortcuts` only wires Ctrl+=, Ctrl+-, Ctrl+0 — `instant_view.dart:189-196` ← `iv/iv_controller.cpp:1020-1025` (`key == u"w"_q && modifier == ctrl → close()`, `key == u"m"_q && modifier == ctrl → minimize()`)

- [ ] [MAJOR] Embed block ignores `is_full_width` and `is_allow_scrolling` flags — AyuGram uses these to set `width: 100%`, fixed pixel height, or autosize mode on the iframe — Dart always derives aspect ratio from `w/h` and renders a fixed-ratio container — `instant_view.dart:2363-2365` (reads `w` and `h` only) ← `iv/iv_prepare.cpp:636-650` (`if (data.is_full_width() && data.is_allow_scrolling()) { autosize = true; … } else if (data.is_full_width() || !data.vw()->v) { width = "100%"; … }`)

# keyboard_shortcuts — Shortcut bindings and overlay state machine

- [ ] [CRITICAL] Pinned-chat default bindings use `alt+1–8` but AyuGram binds `ctrl+1–8` (same keys as folder shortcuts — both commands fire from the same Ctrl+N press via multi-command dispatch) — `keyboard_shortcuts.dart:946-968` ← `AyuGram/core/shortcuts.cpp:502-509`

- [ ] [CRITICAL] `recordVoice` default binding is `ctrl+shift+r` but AyuGram binds it to plain `ctrl+r` (identical key as `readChat`; both commands are registered to the same QAction so pressing Ctrl+R dispatches both — Dart separates them with different modifiers, making the key collision behavior unreachable) — `keyboard_shortcuts.dart:880-882` ← `AyuGram/core/shortcuts.cpp:527,532`

- [ ] [CRITICAL] `MediaViewerFullscreen` command entirely absent — no enum value, no scope entry, no default binding, no handler. AyuGram exposes `media_viewer_video_fullscreen` as a user-customisable command — `keyboard_shortcuts.dart:24-101` ← `AyuGram/core/shortcuts.h:78` and `AyuGram/core/shortcuts.cpp:135,159`

- [ ] [MAJOR] Chat-switch overlay lacks the full AyuGram state machine. AyuGram tracks `ChatSwitchStarted`/`ChatSwitchModifier`, installs an event filter while the overlay is active, and emits navigation events for Arrow keys, Q, Enter (confirm), and Escape (cancel) while Ctrl is held. Dart just fires a one-shot `showChatSwitchRequest` call with no overlay-active guard, no navigation-while-held keys, and no cancel/confirm path — `keyboard_shortcuts.dart:1130-1137` ← `AyuGram/core/shortcuts.cpp:813-974`

# language_box — Language selection not applied; engine prefs dead code; visual toggle mismatch

- [ ] [CRITICAL] Language selection never applies the language change — `_selectLanguage` at `language_box.dart:210-215` only calls `appState.addRecentLanguage(langCode)` and saves prefs, but never calls any engine method to actually switch the Telegram interface language. AyuGram calls `Lang::CurrentCloudManager().switchToLanguage(language)` on every selection (`language_box.cpp:1387`). There is no `SetLanguage`/`SwitchLanguage` method in the Go engine (`go/engine/cache_users.go:2236` has `GetLanguages` but no setter). The box appears fully functional but selecting a language changes nothing in the Telegram session.

- [ ] [MAJOR] `engine.saveLanguagePrefs` is dead code — `_persistLanguagePrefs` at `language_box.dart:221` calls `engine.saveLanguagePrefs(accountId, {'selectedLanguage': ..., ...})` on every language action, but `engine.loadLanguagePrefs` is never called anywhere in the Dart codebase. The engine just writes raw JSON to `language_prefs.json` (`go/engine/cache_users.go:2262-2269`) and no code ever reads it back. Additionally the key used to save is `'selectedLanguage'` while `app_state.dart:3275` loads using `'selectedLanguageCode'` — a latent key mismatch if `loadLanguagePrefs` is ever wired up.

- [ ] [MAJOR] `_SkipLanguagesEditor` uses Material `Switch` widget but AyuGram uses `SettingsButton` toggle-circle style — `language_box.dart:1084-1089` renders a pill-shaped `Switch`, while AyuGram's `ChooseLanguageBox` uses a `Row` class that inherits `SettingsButton` and calls `paintToggle` (a filled circle, not a pill) at `choose_language_box.cpp:179`. The visual appearance differs substantially — circle-fill checkbox vs Material switch toggle.

- [ ] [MAJOR] `_SkipLanguagesEditor._sortedFilteredLangs()` doesn't move the current UI language to front before partitioning — `language_box.dart:935-960` partitions selected languages first, but AyuGram's `ChooseLanguageBox` at `choose_language_box.cpp:287-294` first reorders the current locale language to index 0 via `base::reorder(list, …, 0)`, then stable-partitions selected languages. If the current language is not in the "skip" set, AyuGram still pins it to the top of the unselected group; the Dart version does not.

## media_viewer — audit against AyuGram Desktop source

---

- [ ] [CRITICAL] `_applyQualitySwitch()` re-creates player but omits `stream.completed`, `stream.buffering`, and chapter-detection subscriptions present in `_initVideoIfNeeded()`. After a quality switch: GIF loop stops working, buffering spinner never shows, chapter detection silently breaks. — `media_viewer.dart:2311-2343` ← `media_view_overlay_widget.cpp` (compare full sub list in `_initVideoIfNeeded` at dart:576-609 vs applyQualitySwitch at dart:2325-2335)

- [ ] [CRITICAL] `_deleteMedia()` calls `widget.mediaMessages.removeAt(removedIdx)` — direct mutation of a `final List` passed in from the parent widget. In Flutter this silently mutates the caller's list and causes stale state in the parent's message list (the ChatState message list is not notified). Engine `deleteMessage` is called but the local `mediaMessages` list used by the viewer is the same object passed down from the calling site. — `media_viewer.dart:2935` ← `media_view_overlay_widget.cpp:2713-2714` (AyuGram removes the item from SharedMediaData which is a separate reactive store, never mutated in-place)

- [ ] [CRITICAL] OCR is implemented by shelling out to an external `tesseract` binary via `Process.run`. AyuGram uses `Platform::TextRecognition` (OS vision API on macOS/iOS, ML Kit on Android, WinRT OCR on Windows). The Dart implementation silently fails on all platforms where tesseract is not installed (the common case for desktop users) with only a toast fallback, and completely skips the engine/platform bridge. — `media_viewer.dart:3332-3384` ← `media_view_overlay_widget.cpp:5657-5704` + `platform/platform_text_recognition.h`

- [ ] [MAJOR] Chapter toast fade-out uses `_kChapterToastShowing` (200 ms) as `reverseDuration`, but AyuGram specifies `mediaviewChapterHiding = 400ms` for the hide animation — 2× too fast. — `media_viewer.dart:76` (`_kChapterToastShowing = Duration(milliseconds: 200)`) ← `media_view.style:230` (`mediaviewChapterHiding: 400`)

- [ ] [MAJOR] Chapter toast font is 14 px normal weight. AyuGram uses `mediaviewChapterFont: font(15px semibold)` — wrong size and weight. — `media_viewer.dart:2851` (`fontSize: 14, fontWeight: FontWeight.w500`) ← `media_view.style:227` (`mediaviewChapterFont: font(15px semibold)`)

- [ ] [MAJOR] Chapter toast padding is `EdgeInsets.symmetric(horizontal: 16, vertical: 8)`. AyuGram uses `mediaviewChapterPadding: margins(20px, 12px, 20px, 12px)` — wrong on all sides. — `media_viewer.dart:2837` ← `media_view.style:226`

- [ ] [MAJOR] Thumbnail strip height constant `_kThumbStripHeight = 80.0` and width `_kThumbWidth = 56.0` match AyuGram's `mediaviewGroupHeight: 80px`, `mediaviewGroupWidth: 56px`, `mediaviewGroupWidthMax: 160px` (matches `_kThumbWidthMax = 160.0`). Gap `_kThumbGap = 3.0` matches `mediaviewGroupSkip: 3px` and `_kThumbGapCurrent = 12.0` matches `mediaviewGroupSkipCurrent: 12px`. However, the strip vertical padding `14px` from `mediaviewGroupPadding: margins(0px, 14px, 0px, 14px)` is applied inside `_GalleryThumbsStrip` via `Padding(vertical: 14)` — this is correct. But `_kThumbStripPaddingH = 14.0` maps to horizontal padding, while AyuGram uses 0 for horizontal. Strip items do not have a horizontal pad in AyuGram. — `media_viewer.dart:73` (`_kThumbStripPaddingH = 14.0`) ← `media_view.style:286` (`mediaviewGroupPadding: margins(0px, 14px, 0px, 14px)` — horizontal margin is 0, not 14)

- [ ] [MAJOR] `_StoryViewsListPopup` positions itself using a `Offset position` captured from `context.findRenderObject()` at call time, then places a `Positioned` element relative to screen. The popup is shown via `showDialog()` which creates a new overlay route — the absolute coordinates will be shifted if the dialog barrier doesn't cover the full screen or if the render box offset drifts. Additionally, it sets `bottom: MediaQuery.sizeOf(context).height - widget.position.dy + 8` which anchors to bottom-up from the tap point, but the popup max height is 320 px and position is near the bottom of the story card, making it likely to extend off-screen. No clamp for the bottom edge. — `media_viewer.dart:8035-8037` ← `media_view_overlay_widget.cpp` (AyuGram uses a platform popup with correct screen-relative positioning)

- [ ] [MAJOR] PiP default initial X/Y is `3 * _kPipBorderSkip = 60px` (top-left corner area). AyuGram saves and restores PiP geometry; on first open it uses `st::pipBorderSkip = 20px` as the snap margin, placing PiP in the top-right corner by default (not hard-coded top-left). Dart always opens PiP at top-left (x=60, y=60) on first launch regardless of screen size or saved geometry loading failure. — `media_viewer.dart:4554-4557` ← `media_view_pip.cpp:509` (AyuGram: `position.geometry = QRect(0, 0, st::pipDefaultSize, st::pipDefaultSize)` then `ClampToEdges` snaps to top-right on first show via `KeepWithinRange`)

- [ ] [MAJOR] `_buildVideoControls()` wraps controls in a `Center` with `maxWidth: 480` constraint. AyuGram's video controls span the full bottom width (`media_view_playback_controls.cpp`). The 480 px cap causes controls to be compressed and mis-centered on wide screens. — `media_viewer.dart:2361-2363` ← `media_view_playback_controls.cpp` (no maxWidth constraint; controls fill the bottom bar)

- [ ] [MAJOR] Navigation arrow direction labels use `Icons.chevron_left` for `_hasPrev` (left panel, `_goToPrev` = `_currentIndex++`) and `Icons.chevron_right` for `_hasNext` (right panel, `_goToNext` = `_currentIndex--`). With the Dart ordering (index 0 = newest, higher index = older), left arrow goes to the older item (`_currentIndex++`). AyuGram: Left nav (`_leftNavVisible = _index > 0`) → `moveToNext(-1)` = index-1 = older item. So both left arrows go to older items — direction is consistent. However, Dart uses `_hasPrev` for `Left` and `_hasNext` for `Right` which maps to: left = can go to older (correct), right = can go to newer (correct). This part is fine at a semantic level. — (no issue, SKIPPED)

- [ ] [MAJOR] `_saveMediaToDownloads` uses `FilePicker.platform.getDirectoryPath()` which pops a native file-picker dialog. AyuGram saves directly to the OS Downloads folder with no dialog, showing a toast "Saved to Downloads" (`_saveMsgFilename` = Downloads path). The Dart implementation forces users to pick a folder every time, which is a major UX deviation. — `media_viewer.dart:2746` ← `media_view_overlay_widget.cpp:2843` (`File::ShowInFolder(_saveMsgFilename)` after auto-save to Downloads)

- [ ] [MAJOR] Story viewer: `_muted` toggle for video calls `_videoPlayer?.setVolume(_muted ? 0.0 : 100.0)`. Volume 0.0 in media_kit maps to 0% (correct), but the `setVolume` call passes a 0.0–100.0 range value, and `0.0` is correct for muted. However, `100.0` for unmute hard-codes full volume instead of restoring the previous volume level. — `media_viewer.dart:6917-6918`, `7124` ← (AyuGram restores saved volume on unmute)

- [ ] [MAJOR] `_handleAreaChannelPost` calls `chatState.jumpToMessage(DateTime.now().millisecondsSinceEpoch, highlightMsgId: msgId.toString())`. The timestamp argument passed to `jumpToMessage` is the current time, not the message timestamp — this will navigate to a completely wrong message. The message ID is known (`msgId`) but the timestamp lookup is wrong. — `media_viewer.dart:6635-6641` ← (AyuGram: story channel post area directly opens the specific message by its server ID via `peerHistory()->owner().message(peerId, msgId)`)

## message_bubble — reaction emoji overlay hardcoded static content
- [ ] [CRITICAL] `_ReactionEmojiOverlay` uses hardcoded static emoji categories instead of dynamic content from engine — standard emoji are fully hardcoded inline lists (not fetched from Telegram's available reactions API), so any server-side reaction set changes are never reflected — `message_bubble.dart:1814`

## message_bubble — reaction emoji search filter broken
- [ ] [CRITICAL] `_ReactionEmojiOverlay._filteredEmoji()` performs no actual keyword filtering: when `_search` is non-empty it returns ALL emoji from the current category unchanged rather than filtering by name/keyword match — `message_bubble.dart:1911`

## message_bubble — xdg-open is Linux-desktop-only (no cross-platform)
- [ ] [CRITICAL] URL opening (`_openUrl`), file opening (`_FileIndicator._onTap`), and map coordinate opening (`_LocationIndicator._openCoordinates`) all call `Process.run('xdg-open', ...)` directly — this fails silently on Windows, macOS, Android, and iOS; no platform abstraction exists — `message_bubble.dart:7404` ← no AyuGram equivalent (AyuGram uses Qt's `QDesktopServices::openUrl`)

## message_bubble — request_location inline button uses manual dialog, not GPS
- [ ] [CRITICAL] The `request_location` inline keyboard button type opens a manual coordinate-entry dialog instead of requesting the device's GPS location — the result sent back is whatever the user types, not the actual device location — `message_bubble.dart:10297`

## message_bubble — tapping regular emoji reaction calls nothing
- [ ] [CRITICAL] In `_ReactionList`, tapping a standard (non-custom) emoji reaction has `onTap: null` — the tap handler is only wired for custom emoji reactions. Regular emoji reactions cannot be toggled by the user — `message_bubble.dart:2150`

## message_bubble — poll recent voters avatar shows last char of ID string
- [ ] [CRITICAL] `_ReactorAvatar` label text is `recentVoters[i].substring(recentVoters[i].length - 1)` — this takes the last character of a numeric ID string (e.g. "7" from "12345677"), not a name initial or actual avatar image — `message_bubble.dart:8317`

## message_bubble — kButtonExpandedHideDelay mismatch (0ms vs 300ms)
- [ ] [MAJOR] When the reaction strip is expanded, AyuGram uses `kButtonExpandedHideDelay = 0ms` so the button hides immediately on mouse-leave; the Dart implementation always uses the 300ms hide delay regardless of expansion state — `message_bubble.dart:258` ← `history_view_reactions_button.cpp:43`

## message_bubble — reaction emoji overlay missing custom emoji tab
- [ ] [MAJOR] `_ReactionEmojiOverlay` only shows standard Unicode emoji; there is no tab or section for premium custom emoji packs (fetched via `getAvailableReactions`/`getCustomEmojiStickers`). Users who have premium cannot set custom emoji reactions — `message_bubble.dart:1793`

## message_bubble — WebmEmojiPlayer temp file written per widget init with hash collision risk
- [ ] [MAJOR] `_WebmEmojiPlayer._initPlayer` writes a temp file keyed on `widget.fileData.hashCode` every time the widget initializes — Dart's `hashCode` is not guaranteed unique, so two different emoji blobs can silently share the same temp file path; additionally temp files are never cleaned up, leading to unbounded temp dir growth — `message_bubble.dart:6617`

## message_bubble — GIF player creates new media_kit Player per widget with no pooling
- [ ] [MAJOR] `_GifPlayer` instantiates a fresh `media_kit Player` object for every GIF widget without any pool or reuse strategy — if multiple GIFs are simultaneously visible (e.g. in album or rapid scroll), each holds its own decoder and render surface; no disposal coordination when widgets are recycled off-screen — `message_bubble.dart:3976`

## message_bubble — GIF max width hardcoded 320px independent of bubble width
- [ ] [MAJOR] GIF display width is clamped to 320px unconditionally (`maxGifWidth = 320.0`) without considering the available bubble max width — on wide desktop layouts this makes GIFs appear much narrower than the bubble allows, deviating from AyuGram which sizes GIFs proportionally to available space — `message_bubble.dart:3388`

## message_bubble — via-bot label suppressed incorrectly in group chats
- [ ] [MAJOR] The `viaBotName` label is suppressed when `senderName` is non-empty in group messages (`isOutgoing || senderName.isEmpty || !isFirstInGroup`) — AyuGram renders the via-bot label alongside the sender name row in groups; the Dart condition silently drops the via-bot attribution whenever a sender name is shown — `message_bubble.dart:927`

## my_profile_page — Critical and major issues

- [ ] [CRITICAL] EditPeerColorBox missing "Profile" and "Name" tabs — Dart `_EditPeerColorBox` shows a single flat list of 7 color swatches with one "Background Emoji" section; AyuGram shows a full tabbed box with a "Profile" tab (profile photo + background emoji + profile color selector with `Ui::ColorSelector`) and a "Name" tab (message name color + background emoji), each with a live message preview widget — `my_profile_page.dart:1804-2212` ← `AyuGram/boxes/peers/edit_peer_color_box.cpp:2387-2530`

- [ ] [CRITICAL] Color box uses only 7 hardcoded fallback colors, not `suggestedValue()` from server — AyuGram fetches server-suggested color indices via `peer->session().api().peerColors().suggestedValue()` (a live reactive stream) and passes them to `Ui::ColorSelector`; Dart calls `engine.getPeerColors()` but falls back to static 7 colors and uses simple circular swatch buttons — `my_profile_page.dart:1836-1862` ← `AyuGram/boxes/peers/edit_peer_color_box.cpp:1843-1860`

- [ ] [CRITICAL] Birthday picker minimum year is wrong — Dart uses `_minYear = 1900`; AyuGram uses `Data::Birthday::kYearMin = 1875` — `my_profile_page.dart:3135` ← `AyuGram/data/data_birthday.h:33`

- [ ] [CRITICAL] Birthday box missing "Reset/Remove" left button — AyuGram `EditBirthdayBox` adds a left-side "Remove birthday" button (`box->addLeftButton(tr::lng_settings_birthday_reset(), ...)`) when a birthday is already set and type is `Edit`; Dart `_BirthdayDrumPickerDialog` has no such button to clear an existing birthday — `my_profile_page.dart:3119-3326` ← `AyuGram/ui/boxes/edit_birthday_box.cpp:213-218`

- [ ] [CRITICAL] Birthday drum column order is wrong — AyuGram layout places columns as Day | Month | Year (left to right, day at x=0, month at x=half/2, year at x=half*3/2); Dart's `Row` places them as Day | Month | Year too but uses `Flexible(flex:1)`, `Flexible(flex:2)`, `Flexible(flex:1)` — however AyuGram explicitly positions day on the left half quarter, month in the centre half, year on the right quarter — visual proportion differs significantly — `my_profile_page.dart:3233-3258` ← `AyuGram/ui/boxes/edit_birthday_box.cpp:92-98`

- [ ] [CRITICAL] Personal channel editing uses a custom dialog with `engine.getAdminedPublicChannels()` instead of the peer-list box — AyuGram uses `PersonalChannelController` (a `PeerListController`) that fetches via `MTPchannels_GetAdminedPublicChannels(MTP_flags(Flag::f_for_personal))` and then calls `MTPaccount_UpdatePersonalChannel`; Dart calls `engine.getAdminedPublicChannels()` → `engine.setPersonalChannel()` / `engine.clearPersonalChannel()`. The `f_for_personal` flag filters only channels eligible for personal channel use, not just any admined public channel — `my_profile_page.dart:2955-2960` ← `AyuGram/core/local_url_handlers.cpp:120-170`

- [ ] [CRITICAL] Personal channel editor is missing the "Remove" left button when a channel is already set — AyuGram shows a left-side "Remove" button when `user->personalChannelId()` is set; Dart's `_PersonalChannelSelector` only shows a "None" row inline in the list — `my_profile_page.dart:3014-3050` ← `AyuGram/core/local_url_handlers.cpp:1082-1086`

- [ ] [CRITICAL] Add Account button shows platform chooser (Telegram/Matrix/XMPP/IRC/etc.) — AyuGram `addActivated(Environment::Production)` only adds a new Telegram account auth session; Dart opens a `SimpleDialog` letting the user pick among 10 platforms. AyuGram never shows a platform picker — `my_profile_page.dart:2893-2924` ← `AyuGram/settings/sections/settings_information.cpp:1002-1050`

- [ ] [MAJOR] Bio instant-replacements always enabled — AyuGram gates instant emoji replacements behind `Core::App().settings().replaceEmojiValue()` and `Core::App().settings().systemTextReplaceValue()`; Dart's `_instantReplaces` map is always active with no user setting check — `my_profile_page.dart:277-313` ← `AyuGram/settings/sections/settings_information.cpp:740-743`

- [ ] [MAJOR] Bio emoji autocomplete is a custom in-panel implementation instead of `Ui::Emoji::SuggestionsController` — AyuGram uses `SuggestionsController::Init(container->window(), bio, &self->session())` which provides the full system emoji/custom-emoji popup; Dart builds its own `:query` triggered horizontal panel that only searches `EmojiEntry` (Unicode only, no custom emoji) — `my_profile_page.dart:700-870` ← `AyuGram/settings/sections/settings_information.cpp:744-748`

- [ ] [MAJOR] Profile photo sub-button positioned using `Positioned(right:0, bottom:0)` inside a 100×100 Stack — AyuGram positions the upload sub-button at `(photo.right - upload.width + settingsInfoUploadLeft, photo.bottom - upload.height)` where `settingsInfoUploadLeft = 6px` shifts it 6px inward (not flush to the right edge); Dart uses `right:0, bottom:0` (flush) — `my_profile_page.dart:1067-1074` ← `AyuGram/settings/sections/settings_information.cpp:364-369`, `AyuGram/settings/settings.style:214`

- [ ] [MAJOR] Profile photo area status text positioned with a -1px vertical translate instead of `settingsInfoNameSkip = -1px` applied as name-to-status spacing — AyuGram sets `status.y = name.y + name.height + settingsInfoNameSkip` (-1px between name and status, i.e. name and status slightly overlap); Dart uses `Transform.translate(offset: Offset(0,-1))` on the status widget which achieves the same visual but is applied to the wrong widget — should be spacing from name bottom, not a transform on the status — `my_profile_page.dart:1093-1105` ← `AyuGram/settings/sections/settings_information.cpp:375-378`, `AyuGram/settings/settings.style:213`

- [ ] [MAJOR] Color box preview shows a static hardcoded message ("Hello! This is how your name color looks.") — AyuGram creates a real fake `HistoryItem`/`FakeMessage` with a `PreviewWrap` widget that renders an actual chat bubble using `Ui::ChatStyle` and `Ui::ChatTheme`; Dart shows a simple Row with a colored name label and a grey subtitle — `my_profile_page.dart:1980-2036` ← `AyuGram/boxes/peers/edit_peer_color_box.cpp:1834-1841`

- [ ] [MAJOR] Color box "Background Emoji" section shows emoji as image thumbnails from `getCustomEmojiThumbs()`; AyuGram loads emoji via `CreateEmojiIconButton` which uses a real settings button opening a full emoji/sticker picker panel — Dart's inline expand/collapse grid is a non-standard replacement — `my_profile_page.dart:2038-2075` ← `AyuGram/boxes/peers/edit_peer_color_box.cpp:1876-1896`

- [ ] [MAJOR] Account reorder is blocked for indices >= premiumLimit, but AyuGram pins the accounts past the limit as a pinned interval using `_reorder->addPinnedInterval(premiumLimit, ...)` — Dart blocks drag by conditionally attaching `ReorderableDragStartListener` only on non-locked rows, which differs from the pinned interval semantic (locked rows in AyuGram still appear in the list but cannot be reordered) — `my_profile_page.dart:2444-2447` ← `AyuGram/settings/sections/settings_information.cpp:1139-1141`

- [ ] [MAJOR] Middle-click on account row should trigger Ctrl+click (open in new window) — AyuGram handles `Qt::MiddleButton` in account button clicks to call `callback(Qt::ControlModifier)`; Dart only handles `buttons == 4` via a `Listener.onPointerDown` but the `4` bitmask is middle-button on mouse, which is correct — however this fires on pointer-down, not on click, so it can trigger unintentionally — `my_profile_page.dart:2632-2637` ← `AyuGram/settings/sections/settings_information.cpp:856-859`

# notification_popup — Desktop notification popup widget

- [ ] [MAJOR] Windows hide-countdown trigger: Dart polls `_hasReceivedInput` which is only set by pointer events over the notification overlay; AyuGram's `checkLastInput` uses `GetLastInputInfo()` (system-wide last input time), so any keyboard/mouse activity in any app starts the countdown — Dart notifications on Windows never auto-dismiss if the user only types in another window — `notification_popup.dart:194-209` ← `notifications_manager_default.cpp:767-786`

- [ ] [MAJOR] HideAllButton normal-state background: Dart uses `bgColor` (the notification window background = `windowBg`) for the un-hovered state; AyuGram fills with `st::lightButtonBg` which is a distinct lighter button background color, making the button visually different from the notification body — `notification_popup.dart:879-883` ← `notifications_manager_default.cpp:1334`

- [ ] [MAJOR] Reply button label and shape: Dart shows `'REPLY'` in all-caps with `letterSpacing: 0.5` inside a pill-shaped container with `BorderRadius.circular(14)` and `accentColor` fill; AyuGram uses `Ui::RoundButton` with `st::defaultBoxButton` style and the localized string `tr::lng_notification_reply()` ("Reply", title-case) — wrong label casing and wrong border radius — `notification_popup.dart:941-950` ← `notifications_manager_default.cpp:678`

- [ ] [MAJOR] macOS photo size: Dart declares `_photoSize = 62.0` as a single compile-time constant used on all platforms; AyuGram defines `notifyPhotoSize: 62px` for all platforms **and** a separate `notifyMacPhotoSize: 64px` used on macOS — avatar renders 2px too small on macOS — `notification_popup.dart:15` ← `window.style:31-32`

# notifications_settings_screen — Audit findings

- [ ] [CRITICAL] `_SplitToggleRow.onTap` falls back to an empty lambda `() {}` when `onTap` is null, making the whole left-panel area a silent no-op click instead of navigating to the type subpage — `notifications_settings_screen.dart:3126` ← `settings_notifications.cpp:223` (`button->setClickedCallback([=] { showOther(...); })`)

- [ ] [CRITICAL] `_NotificationPreview` hardcodes fictional sender name "Dino Rex" and message "It's morning in Tokyo 😎" as static strings — AyuGram dynamically renders a real notification bubble using `NotifyPreview::paint()` with translatable strings (`tr::lng_notification_preview_title`, `tr::lng_notification_preview_text`, `tr::lng_notification_preview`) and the real app logo/SVG dino userpic — `notifications_settings_screen.dart:3553-3556` ← `settings_notifications.cpp:760-770`

- [ ] [CRITICAL] `_NotificationPreview` "Name" checkbox disabling "Text" logic is inverted vs AyuGram: Dart sets `if (!v) appState.notifPreviewText = false` when name is toggled off, but AyuGram's `NotifyView` enum is a 3-state value (`ShowNothing`, `ShowName`, `ShowPreview`) and the view level is the single source of truth; the Dart code stores two independent booleans and encodes them as a bitmask `(name ? 1 : 0) | (text ? 2 : 0)`, which does not match AyuGram's `NotifyView` integer ordering where `ShowPreview=0, ShowName=1, ShowNothing=2` (lower value = more detail) — `notifications_settings_screen.dart:299-316` ← `settings_notifications.cpp:1136-1165`

- [ ] [CRITICAL] Pinned-messages toggle is wired to `saveLocalNotifyConfig` with a local-only JSON blob — AyuGram persists this setting via `Core::App().settings().setNotifyAboutPinned(notify)` followed by `Core::App().saveSettingsDelayed()`, which writes to the local settings file, not a server API. The Dart implementation stores it in `AppState._notifPinnedMessages` and sends it through the engine's generic config path, meaning restarts that reload only from Telegram's server settings will lose the state — `notifications_settings_screen.dart:553-558` ← `settings_notifications.cpp:1318-1322`

- [ ] [CRITICAL] `_SplitToggleRow` confirmation dialog when toggling with exceptions shows a generic message "Please note that N chat(s) are listed as exceptions and won't be affected" and does NOT include a "View exceptions" button leading back to the subpage — AyuGram shows a box with `tr::lng_notification_about_{private_chats,groups,channels}` (bold count, "won't be affected by this change") plus an explicit `tr::lng_notification_exceptions_view()` left-panel button and an inform-style `OK` — `notifications_settings_screen.dart:3073-3096` ← `settings_notifications.cpp:241-271`

- [ ] [CRITICAL] Reactions subpage (`_ReactionsSubPageState`) calls `engine.setReactionsNotifySettings(...)` with a `showSenderName` parameter mapped to `show_sender_name` — AyuGram's reactions settings page only exposes `showSender` (mapped to `api().reactionsNotifySettings().updateShowPreviews(checked)`), which is the **preview** toggle, not a separate "sender name" concept; the Dart field name and API semantics are mismatched — `notifications_settings_screen.dart:3238-3280` ← `settings_notifications_reactions.cpp:199-213`

- [ ] [CRITICAL] `_NotificationTypeSubPage` right-click mute menu on the "Enable notifications" toggle shows "Select tone" and "Toggle sound" options — AyuGram uses `MuteMenu::SetupMuteMenu` which shows timed-mute presets only (no tone picker, no sound toggle from the right-click) — `notifications_settings_screen.dart:2402-2480` ← `settings_notifications_type.cpp:427-442`

- [ ] [MAJOR] `_NotificationTypeSubPage` uses `engine.muteDefaultNotifyForDuration(... seconds: 2147483647)` as a stand-in for "no sound" — AyuGram stores the sound preference as `Data::NotifySound{ .none = true }` via `settings->defaultUpdate(type, {}, {}, value)`, not as a mute-for-duration call — `notifications_settings_screen.dart:1748-1749` ← `settings_notifications_type.cpp:542-548`

- [ ] [MAJOR] `_ReactionsSubPage` `_showFromDialog` only presents "From everyone" and "From my contacts" radio options — AyuGram's `ShowFromBox` presents all three values (`NotifyFrom::All`, `NotifyFrom::Contacts`, and implicitly maps `None` back to `All` for the initial selection). More critically, when the dialog is opened while the current value is `None` (disabled), AyuGram resets the initial selection to `All`; Dart passes `current` directly which could be `none`, causing the dialog to open with no valid radio selected — `notifications_settings_screen.dart:3316-3352` ← `settings_notifications_reactions.cpp:54-87`

- [ ] [MAJOR] `_SplitToggleRow` status text for non-zero exceptions reads `"On, N exceptions"` or `"Off, N exceptions"` — AyuGram renders `tr::lng_notification_on(lt_exceptions, ...)` / `tr::lng_notification_off(lt_exceptions, ...)` with the exception count embedded; when count is 0 it shows `tr::lng_notification_click_to_change()` ("Click here to change"). The Dart status is consistent with this intent but uses hardcoded English instead of the engine's locale string — `notifications_settings_screen.dart:3056-3062` ← `settings_notifications.cpp:198-215`

- [ ] [MAJOR] `_RingtonesBoxDialog` plays no preview audio when a ringtone entry is selected — AyuGram's `RingtonesBox` plays a preview via `Core::App().notifications().playSound(session, toneValue().id, 0.01 * volume)` on selection. The Dart box only tracks `_selectedId` state with no audio feedback on row tap — `notifications_settings_screen.dart:4212-4261` ← `settings_notifications_type.cpp:514-529`

- [ ] [MAJOR] `_NotificationMonitorWidget._showSampleNotifications()` shows sample notifications as `OverlayEntry` widgets inside the settings window's own overlay — AyuGram creates actual top-level `SampleWidget` windows (`Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::BypassWindowManagerHint`) that float above all other windows at real screen coordinates. The Dart sample stays inside the app window, not on the desktop — `notifications_settings_screen.dart:961-1001` ← `settings_notifications.cpp:568-614`

- [ ] [MAJOR] `_NotificationTypeSubPage._loadExceptions()` falls back to building the exceptions list from locally-cached `ChatState.chatsForAccount(activeId)` filtered by `c.isMuted` — AyuGram reads exceptions exclusively from `session().data().notifySettings().exceptions(type)` (server-synced `Data::NotifySettings`), which contains only chats with custom notification overrides, not all muted chats. A muted chat with default settings does not appear in AyuGram's exceptions list — `notifications_settings_screen.dart:1694-1716` ← `settings_notifications_type.cpp:260-290`

- [ ] [MAJOR] `_NotificationTypeSubPage` exception row on tap opens a mute-menu popup (`_showExceptionMuteMenu`) — AyuGram's `ExceptionsController::rowClicked` calls `delegate()->peerListShowRowMenu(row, true)` which opens the row's context menu (profile/view + MuteMenu). Dart fires the same popup on left-click and right-click, AyuGram fires the full context menu on right-click only and the toggle menu on left-click — `notifications_settings_screen.dart:1946-1951` ← `settings_notifications_type.cpp:251-253`, `292-322`

- [ ] [MAJOR] `_NotificationTypeSubPage` exceptions list has no real-time update subscription to `session.data().notifySettings().exceptionsUpdates()` — it subscribes to `EngineService.onChatUpdated` which is a general chat-info stream, not a targeted notification-settings change event. Exceptions changed from another device won't trigger a refresh until a broader chat update occurs — `notifications_settings_screen.dart:1585-1587` ← `settings_notifications_type.cpp:216-219`

# payment_panel — Audit Findings

## payment_panel — SmartGlocal URL validation

- [ ] [CRITICAL] SmartGlocal `tokenizeUrl` validation is completely wrong — Dart checks `tokenizeUrl.endsWith('/')` (line 1670) and accepts any non-empty URL verbatim, meaning a malicious bot could set `tokenize_url` to an arbitrary host and receive raw card details. AyuGram validates `url.startsWith("https://") && url.endsWith(".smart-glocal.com/cds/v1/tokenize/card")` and falls back to the default URL if it fails. — `payment_panel.dart:1669` ← `AyuGram/payments/smartglocal/smartglocal_api_client.cpp:49`

## payment_panel — Stripe User-Agent header

- [ ] [CRITICAL] `X-Stripe-User-Agent` header is sent as `{"lang":"dart","publisher":"anthropic"}` (line 1632), which exposes the app as Anthropic-built to Stripe's servers. AyuGram sends `{"lang":"objective-c","bindings_version":"9.1.0"}`, which is the expected client identity. The `"publisher":"anthropic"` tag is not a real Stripe SDK field and will cause Stripe to mis-identify the client. — `payment_panel.dart:1632` ← `AyuGram/payments/stripe/stripe_api_client.cpp:41`

## payment_panel — BOT_TRUST_REQUIRED warning dialog

- [ ] [MAJOR] `_showBotTrustWarning()` shows a generic "Payment Confirmation" dialog with simplified body text (line 450). AyuGram's `Panel::showWarning()` uses `tr::lng_payments_warning_title()` as title and `tr::lng_payments_warning_body(lt_bot1, lt_provider, lt_bot2, lt_bot3)` as body — a multi-sentence warning that names the bot three times in context ("do you want to pay for %bot1 via %provider; after payment %bot2 will receive personal details; you may be charged by %bot3 again"). The Dart text is a single vague sentence that omits these key disclosures. — `payment_panel.dart:450` ← `AyuGram/payments/ui/payments_panel.cpp:710`

## payment_panel — Terms dialog missing bot username and recurring support

- [ ] [MAJOR] `_showTermsDialog()` does not include the bot's `@username` in the terms text and does not differentiate between recurring and one-time payments (lines 479–557). AyuGram's `Panel::requestTermsAcceptance()` takes `username` and `recurring` parameters and renders `tr::lng_payments_terms_text` (recurring) vs `tr::lng_payments_terms_text_once` (one-time), both using `lt_bot` with the bold `@username`. The Dart dialog only shows a generic "payment provider" phrase. — `payment_panel.dart:479` ← `AyuGram/payments/ui/payments_panel.cpp:733`

## payment_panel — Currency formatting incomplete

- [ ] [MAJOR] `_currencySymbol()` only handles 10 currencies (USD/EUR/GBP/RUB/JPY/CNY/IRR/TRY/INR/KRW); all others fall back to the raw ISO code with no symbol (line 648). `_formatAmount()` always places the symbol on the left with no thousands separator or decimal separator customization (line 608). AyuGram's `FillAmountAndCurrency()` covers 100+ currencies via `LookupCurrencyRule()` with per-currency left/right symbol position, thousands separator character, decimal character, and `stripDotZero` flag. — `payment_panel.dart:608` ← `AyuGram/ui/text/format_values.cpp:176`

## payment_panel — Receipt date uses hardcoded English months

- [ ] [MAJOR] `_formatReceiptDate()` uses a hardcoded English month abbreviation array (`['Jan','Feb',...]`, lines 2179–2186). AyuGram formats the receipt date with `langDateTime(base::unixtime::parse(_invoice.receipt.date))` which respects the system locale and produces a locale-correct date string. Dart's output will always be in English regardless of the user's locale. — `payment_panel.dart:2179` ← `AyuGram/payments/ui/payments_form_summary.cpp:324`

## payment_panel — _hasChanges() misses in-progress tokenization

- [ ] [MAJOR] `_hasChanges()` only compares saved field strings (payment method display name, address, name, email, phone) but does not detect when a Stripe or SmartGlocal tokenization request is in flight (line 2233). AyuGram's `Form::hasChanges()` returns `true` while `_stripe != nullptr || _smartglocal != nullptr`, ensuring the close-confirmation dialog appears even if the user opened the card form but hasn't yet tokenized. Dart will silently close without warning if the user enters card data during an in-progress tokenization. — `payment_panel.dart:2233` ← `AyuGram/payments/payments_form.cpp:1064`

# peer_short_info — Audit findings

- [ ] [CRITICAL] Username "onTap" opens `t.me/…` in the external browser via `launchUrl(LaunchMode.externalApplication)` instead of navigating to the peer within the app — `peer_short_info.dart:872` ← `prepare_short_info_box.cpp:453` (`open` callback calls `window->showPeerHistory(peer)`)

- [ ] [CRITICAL] Group/channel "Link" row `onTap` also opens `t.me/…` in the external browser — `peer_short_info.dart:909` ← `prepare_short_info_box.cpp:453` (same `open` callback, internal navigation)

- [ ] [CRITICAL] Context menu is hardcoded to a single "Open in New Window" entry and is not extensible; AyuGram feeds per-peer actions (Report, Block, Delete Contact, etc.) through a `menuFiller` callback wired to `fillMenuRequests` — `peer_short_info.dart:395-415` ← `peer_short_info_box.cpp:856-876` + `prepare_short_info_box.cpp:467-472`

- [ ] [MAJOR] Phone formatter only handles 5 country codes (US +1, RU +7, UK +44, DE +49, IR +98) and falls back to naive 3-digit grouping for every other country; AyuGram delegates to `Countries::Instance().format()` which covers all 200+ ITU country codes — `peer_short_info.dart:1104-1129` ← `format_values.cpp:424-437`

- [ ] [MAJOR] Birthday "today" value shows bare "January 1, 2000" with no cake emoji, no "turns N today" age annotation, and no localized today-sentence; AyuGram wraps the date with `tr::lng_info_birthday_today(lt_emoji, BirthdayCake(), lt_date, …)` and appends age via `tr::lng_info_birthday_today_years` — `peer_short_info.dart:1131-1151` ← `info_profile_values.cpp:749-771`

- [ ] [MAJOR] Birthday gift icon (`birthdayTodayIcon`: the `menu/gift_premium` icon) is never shown on birthday today; AyuGram renders this icon to the right of the birthday row and makes it visible only when `IsBirthdayTodayValue` is true — `peer_short_info.dart:877-887` ← `info_profile_actions.cpp:903-912` + `boxes.style:1060`

- [ ] [MAJOR] Scrollbar thumb uses `Radius.circular(4)` (4 px) instead of the AyuGram `shortInfoScroll` value of `round: 1px` — `peer_short_info.dart:499` ← `info.style:1270`

# photo_crop_editor — Audit findings

- [ ] [CRITICAL] Paint stroke coordinates broken under canvas zoom — `_ImageCropAreaState._onPointerDown` stores raw `event.localPosition` (widget screen coords) at line 1921, but `_CropPainter.paint()` applies a zoom+pan canvas transform (translate/scale/translate at lines 2255–2263) before drawing all strokes. Stored screen-space point `P` is drawn at `(P – center) * zoom + center + offset`, not at `P`. When painting with `_canvasZoom > 1.0`, every stroke appears displaced from where the user drew it; the export (`_applyCropAndExport`) also uses the uncorrected coordinates. Fix: inverse-transform pointer position before storing — `photo_crop_editor.dart:1921` + `photo_crop_editor.dart:2255` ← `AyuGramDesktop/Telegram/SourceFiles/editor/editor_paint.cpp` (uses Qt `QGraphicsView::mapToScene()` to convert widget coords to scene/content coords before recording strokes)

- [ ] [CRITICAL] Custom brush color never added to palette row — AyuGram's `ColorPicker::rebuildPalette()` appends the current `_brush.color` to the displayed colors list when it's not among the 10 defaults (lines 685–710), so the user can click the custom colour dot to re-select it. The Dart `_ColorPaletteRow` always renders the fixed `_kPaletteColors` list (10 items, line 3152); custom colours chosen via the colour-picker box appear only in the rainbow button swatch and are otherwise inaccessible — `photo_crop_editor.dart:3152` ← `AyuGramDesktop/Telegram/SourceFiles/editor/color_picker.cpp:685`

- [ ] [CRITICAL] Tool button Lottie animation freezes at final frame after first hover — `_ToolButtonState._onHoverExit()` (line 3376) only sets `_hovering = false` and does nothing to the `_lottieCtrl`. AyuGram's `ToolLottieButton` (lines 212–222) sets `_resetPending = true` on `QEvent::Leave`; after the animation finishes it calls `reset()` which jumps the icon back to frame 0 (lines 250–258). In the Dart, after the very first hover-over, every tool icon permanently shows its last animation frame (fully animated / "active" pose) instead of the idle frame — `photo_crop_editor.dart:3376` ← `AyuGramDesktop/Telegram/SourceFiles/editor/color_picker.cpp:212`

- [ ] [MAJOR] Tool button hover colour change is instant, not animated — AyuGram defines `photoEditorToolButtonHoverDuration: 350` (editor.style line 139) and the `ToolLottieButton` drives the Lottie icon animation over `crl::time(st::photoEditorToolButtonHoverDuration)` (color_picker.cpp line 248). The Dart `_ToolButtonState._onHoverEnter/_Exit` only toggles `_hovering` via bare `setState()` (lines 3369–3378), causing an instantaneous colour jump instead of a smooth 350 ms fade — `photo_crop_editor.dart:3369` ← `AyuGramDesktop/Telegram/SourceFiles/editor/editor.style:139` + `AyuGramDesktop/Telegram/SourceFiles/editor/color_picker.cpp:248`

- [ ] [MAJOR] Tool button hit-area SizedBox 28 px vs AyuGram spec 20 px — `_kToolButtonSize = 28.0` (line 114) is used as the SizedBox size for each tool button (line 3396). AyuGram's `photoEditorToolButtonSize: 20px` (editor.style line 136) is the visual icon slot; the hit area is extended by `photoEditorToolButtonSelectedExtra: 8px` per side as an invisible overlay (`updateToolButtonsGeometry()` color_picker.cpp line 499–500). The Dart treats 28 px as the visible bounding box. Result: spacing per tool is `28 + 18 = 46 px` in Dart vs `20 + 18 = 38 px` in AyuGram — a 21% wider tool row — `photo_crop_editor.dart:114` ← `AyuGramDesktop/Telegram/SourceFiles/editor/editor.style:136` + `AyuGramDesktop/Telegram/SourceFiles/editor/color_picker.cpp:499`

## popup_menu — Context Menu Widget

- [ ] [CRITICAL] Menu box shadow is inside `ClipRRect` and is permanently clipped — the shadow never renders. `DecoratedBox` (with `BoxShadow`) is a child of `Align` inside `ClipRRect`; `ClipRRect` clips to its own layout bounds, which equal the `Align` bounds (= menu content size). The shadow extends beyond those bounds and is clipped away at all animation phases including `widthFactor = heightFactor = 1.0`. Fix: move the `BoxShadow` decoration outside the `ClipRRect`, keeping only the background color/radius inside the clip. — `popup_menu.dart:301-334` ← `lib_ui/ui/widgets/popup_menu.cpp:342-349` (`paintBg` + `_boxShadow.paint`)

- [ ] [MAJOR] Open animation starts at 50% width / 45% height instead of 0% — menu pops in already half-expanded. AyuGram's `PanelAnimation.paintFrame` runs `progress` 0 → 1 starting from a fully-collapsed state; the Dart hardcodes `widthFactor = 0.5 + 0.5 * curve` and `heightFactor = 0.45 + 0.55 * curve`, so the menu is always at least half its final size at `t = 0`. — `popup_menu.dart:292-294` ← `lib_ui/ui/widgets/popup_menu.cpp:682-708` (`startShowAnimation`, `PanelAnimation` progress 0 → 1)

- [ ] [MAJOR] Disabled item text and icon colour wrong in dark mode: Dart uses `0xFF6c7883` (`menuIconFg`) for both. Night theme defines `menuFgDisabled: #3d4e5c` — a much darker, less-visible grey. Light mode is correct (`0xFFcccccc == menuFgDisabled light`). — `popup_menu.dart:1069-1073` ← `night-custom-base.tdesktop-theme: menuFgDisabled: #3d4e5c` / `lib_ui/ui/widgets/widgets.style:977` (`itemFgDisabled: menuFgDisabled`)

- [ ] [MAJOR] Shortcut (keyboard accelerator) resting colour wrong in dark mode: Dart uses `0xFF8d9ba4` but AyuGram maps `itemFgShortcut → windowSubTextFg` which in the night theme is `#708499` (notably darker / more muted). — `popup_menu.dart:864-865` ← `night-custom-base.tdesktop-theme: windowSubTextFg: #708499` / `lib_ui/ui/widgets/widgets.style:978` (`itemFgShortcut: windowSubTextFg`)

- [ ] [MAJOR] Shortcut hover colour wrong in dark mode: Dart uses `0xFFa0b0b8`; AyuGram maps `itemFgShortcutOver → windowSubTextFgOver` which in the night theme is `#7c90a4`. — `popup_menu.dart:873` ← `night-custom-base.tdesktop-theme: windowSubTextFgOver: #7c90a4` / `lib_ui/ui/widgets/widgets.style:979` (`itemFgShortcutOver: windowSubTextFgOver`)

- [ ] [MAJOR] Shortcut hover colour wrong in light mode: Dart uses `0xFF888888`; AyuGram light palette has `windowSubTextFgOver: #919191`. — `popup_menu.dart:874` ← `lib_ui/ui/colors.palette: windowSubTextFgOver: #919191`

- [ ] [MAJOR] Attention items with icons show default-colour text instead of red when `fullAttention = false`. AyuGram's `menuWithIconsAttention` style unconditionally sets `itemFg: attentionButtonFg` and `itemFgOver: attentionButtonFgOver` for all attention entries regardless of icon presence. The Dart gate `useRedText = item.isAttention && (widget.fullAttention || !hasIcon)` suppresses the red label on icon-bearing destructive actions (e.g. "Delete message") unless callers pass `fullAttention: true`, which they do not by default. — `popup_menu.dart:881` ← `lib_ui/ui/widgets/widgets.style:1707-1710` (`menuWithIconsAttention`)

## privacy_settings_screen — audit vs AyuGram Desktop

- [ ] [CRITICAL] `BuildConfirmationExtensions` only renders the section when `noWarningExtensions` is non-empty OR `ipRevealWarning` is false (i.e. the section is hidden by default and only appears once the user has configured it). Dart always renders the "File Confirmations" section unconditionally, permanently showing "No-Warning Extensions" and "Show IP in WebRTC calls" even for fresh installs — `privacy_settings_screen.dart:1246` ← `settings_privacy_security.cpp:1128`

- [ ] [CRITICAL] AyuGram puts "Show IP in WebRTC calls" (`ipRevealWarning`) inside `OpenFileConfirmationsBox` as a toggle within the same settings box as the extensions list, not as a separate standalone row in the main Privacy screen. Dart exposes it as a top-level inline toggle in `_buildConfirmationExtensionsSection`, which is the wrong location and wrong widget type — `privacy_settings_screen.dart:1277` ← `settings_privacy_security.cpp:376`

- [ ] [CRITICAL] Login Email row opens a custom `_showChangeLoginEmailDialog` that asks the user for their current password and a new email, then calls `engine.setCloudPasswordEmail`. AyuGram opens this via `UrlClickHandler::Open(u"tg://settings/login_email"_q)` — a deep-link that routes to the platform's cloud-password settings flow, not a custom dialog with manual password entry. The Dart implementation is a completely custom stub that does not match the original flow — `privacy_settings_screen.dart:1373` ← `settings_privacy_security.cpp:729`

- [ ] [CRITICAL] `_buildBotsAndWebsitesSection` has "Logged-in Websites" removed from it and only shows "Clear Payment and Shipping Info". However, AyuGram's `BuildBotsAndWebsitesSection` only contains the clear-payment button — the Websites button is in the Security section as a conditionally shown row. The Dart security section correctly conditionally shows Websites (line 766), which matches, but the "Bots and Websites" section title (`tr::lng_settings_security_bots`) in AyuGram covers only payment, and so the Dart section is correct. However the section in Dart is missing a divider/skip after it — `privacy_settings_screen.dart:1187` ← `settings_privacy_security.cpp:1026`

- [ ] [CRITICAL] `_buildArchiveAndMuteSection` renders Archive and Mute + two sub-toggles (Keep Archived Unmuted, Keep Archived in Folders) unconditionally once `_archiveLoaded` is true. In AyuGram, `BuildArchiveAndMuteSection` only shows the entire section when `shown || premium` — where `shown` only becomes true once `privacy->showArchiveAndMute()` emits a true value after a network call. The Dart code skips this visibility gating entirely, always showing the section once loaded, diverging from the AyuGram behaviour — `privacy_settings_screen.dart:1079` ← `settings_privacy_security.cpp:981`

- [ ] [CRITICAL] The Archive and Mute section in Dart has sub-toggles "Keep Archived Unmuted" and "Keep Archived in Folders" as visible rows. AyuGram's `BuildArchiveAndMuteSection` only ever renders the single `lng_settings_auto_archive` toggle button — there are no sub-toggles for keepUnmuted or keepFolders in this section of the AyuGram source. These two toggles either belong to a different API call (GlobalPrivacy extended) or do not exist in the desktop app at all. Dart renders them as if they were always valid, which is incorrect — `privacy_settings_screen.dart:1124` ← `settings_privacy_security.cpp:481`

- [ ] [CRITICAL] `_GlobalTTLScreen._openApplyToExisting` uses `engine.searchChats('', limit: 500)` to enumerate all chats then calls `engine.setHistoryTTL` for each one in a loop with a 200ms delay. AyuGram uses `TTLChatsBoxController` (a peer-list box) that lets the user explicitly select which chats to apply the TTL to, then fires `MTPmessages_SetHistoryTTL` per peer. The Dart implementation silently applies TTL to all 500 chats without user selection, which is a critical behavioural deviation — `privacy_settings_screen.dart:5247` ← `settings_global_ttl.cpp:401`

- [ ] [CRITICAL] `_LocalPasscodeCreate` stores the passcode as a SHA-256 hash (iterated 100000 times) in a local JSON file (`local_passcode.json`). AyuGram uses `controller->session().domain().local().setPasscode(pass.toUtf8())` which stores the passcode in Telegram Desktop's encrypted local storage via `Storage::Domain`. The Dart implementation uses a completely independent local file that is not integrated with the Telegram session storage or lock/unlock flow — `privacy_settings_screen.dart:5620` ← `settings_local_passcode.cpp:44`

- [ ] [MAJOR] `_buildPrivacySection` lists privacy items in order: phone_number, last_seen, profile_photo, forwards, calls, voice_messages, birthday, gifts, about, saved_music, chat_invite. AyuGram's `BuildPrivacySection` lists: phone_number, last_seen, profile_photo, forwards, calls, voices, **messages** (between voices and birthday), birthday, gifts, bio, saved_music, groups. The Messages privacy button is inserted between Voice Messages and Birthday in AyuGram, but in Dart it's appended after all other items as a separate `_PrivacyRow` at the bottom of the section — `privacy_settings_screen.dart:983` ← `settings_privacy_security.cpp:906`

- [ ] [MAJOR] `PrivacyString` in AyuGram computes exception counts using `ExceptionUsersCount` which sums chat/channel member counts, not the raw peer list size. Dart's `_privacyLabel` adds raw `alwaysUsers.length + alwaysChats.length` counts, ignoring that group/channel exceptions should show member counts. This produces incorrect "+N" annotations — `privacy_settings_screen.dart:329` ← `settings_privacy_security.cpp:316`

- [ ] [MAJOR] AyuGram's `PrivacyBase` for `CallsPeer2Peer` uses separate label strings (`lng_edit_privacy_calls_p2p_everyone`, `lng_edit_privacy_calls_p2p_contacts`, `lng_edit_privacy_calls_p2p_nobody`). Dart's `_privacyLabel` uses the same labels as all other privacy keys (Everyone/My Contacts/Nobody) for the `calls_p2p` sub-option. The P2P labels differ from the main privacy labels — `privacy_settings_screen.dart:339` ← `settings_privacy_security.cpp:88`

- [ ] [MAJOR] `PrivacyBase` in AyuGram returns `lng_edit_privacy_no_miniapps` when option is Everyone but `rule.never.miniapps` is true, and `lng_edit_privacy_contacts_and_miniapps` or `lng_edit_privacy_miniapps` for contacts/nobody with miniapps. Dart has no miniapps exception handling in `_privacyLabel` or `_optionLabel` — `privacy_settings_screen.dart:325` ← `settings_privacy_security.cpp:99`

- [ ] [MAJOR] `_CloudPasswordHint._submit` forces the user to enter a non-empty hint. AyuGram's `PasscodeBox` allows setting a password with an empty hint (it simply does not pass a hint parameter). Dart requires a hint entry and shows an error "Please enter a hint" if empty; the "Skip" button calls `_navigateOrRecover('')` which bypasses validation. This forces an extra step that doesn't match the original UX — `privacy_settings_screen.dart:3960` ← `settings_local_passcode.cpp:194`

- [ ] [MAJOR] `_LocalPasscodeManage` implements Auto-Lock with a custom `_AutoLockBox` dialog offering presets (1min, 5min, 1hr, 5hr) and a custom HH:MM field. AyuGram uses `Box<AutoLockBox>` from `boxes/auto_lock_box.h` which may have different preset values and formatting. The AyuGram auto-lock label format uses `lng_passcode_autolock_hours_minutes`, `lng_minutes`, `lng_hours` for formatting — the Dart `_formatAutoLock` uses a custom format. The Dart also reads/writes auto-lock to `local_passcode.json` while AyuGram uses `Core::App().settings().autoLock()` — `privacy_settings_screen.dart:6189` ← `settings_local_passcode.cpp:419`

- [ ] [MAJOR] AyuGram's `LocalPasscodeManage` has an auto-close timer (`CloudPassword::SetupAutoCloseTimer`) that automatically navigates back after idle inactivity. Dart's `_CloudPasswordManage` implements its own idle timer (10-minute timeout checked every 60 seconds via `_lastActivity`), but `_LocalPasscodeManage` has no idle timer at all — `privacy_settings_screen.dart:6134` ← `settings_local_passcode.cpp:632`

- [ ] [MAJOR] `_LocalPasscodeManage.createPinnedToBottom` is missing. AyuGram's `LocalPasscodeManage` uses `createPinnedToBottom` to pin the "Disable Passcode" button at the bottom of the screen as a separate pinned widget. Dart renders "Turn Off Passcode" as an inline row in the `ListView`, not as a pinned-to-bottom widget — `privacy_settings_screen.dart:6350` ← `settings_local_passcode.cpp:599`

- [ ] [MAJOR] `_BlockedUsersScreen._showBlockUserPicker` calls `engine.getContacts` to populate the picker list. AyuGram's blocked users section uses `BlockedBoxController::BlockNewPeer(controller())` which opens a standard global peer search box. The Dart approach only shows existing contacts, whereas AyuGram allows searching any peer globally — `privacy_settings_screen.dart:7114` ← `settings_blocked_peers.cpp:135`

- [ ] [MAJOR] `_WebSessionsScreen` tapping on a session item directly calls `_terminateSession` without showing session details first. AyuGram's `settings_websites.cpp` shows a detail box/sheet for each website session before offering disconnect. Dart has no detail view for individual web sessions — `privacy_settings_screen.dart:8009` ← `settings_websites.cpp` (whole file pattern)

- [ ] [MAJOR] `_openSelfDestructionBox` uses hardcoded account TTL options `[30, 90, 180, 365, 548, 720]` days. AyuGram uses `SelfDestructionBox` with type `Account` and `session->api().selfDestruct().daysAccountTTL()` as the reactive data source. The Dart TTL options (548 days = ~18 months) maps to AyuGram's 548-day option correctly, but the dialog is a plain `AlertDialog` with `RadioListTile` instead of `SelfDestructionBox` — the confirmation dialog and toast shown after setting the value (`lng_settings_ttl_after_toast`) are also missing — `privacy_settings_screen.dart:1601` ← `settings_privacy_security.cpp:1111`

- [ ] [MAJOR] `_GlobalTTLScreen._selectTTL` shows a confirmation dialog before enabling/changing TTL. AyuGram's `RebuildButtons` shows a confirmation box only when current TTL is 0 (off); when TTL is already on, changing it does not require confirmation. Dart always shows confirmation for any non-zero period change, which adds an extra confirmation step not present in AyuGram — `privacy_settings_screen.dart:5193` ← `settings_global_ttl.cpp:225`

# reactions_detail — Audit

- [ ] [MAJOR] "All reactions" tab uses `Icons.favorite` (heart icon) instead of the correct reactions icon. AyuGram uses `reactionsTabAll` which maps to `"menu/read_reactions"` — visually a multi-reaction sparkle icon, not a heart. The heart misleads users into thinking it filters "liked" reactions only. — `reactions_detail.dart:675` ← `ui/chat/chat.style:862`

- [ ] [MAJOR] Scroll position not reset when switching back to "All" tab via cached `_masterReactors` path. In `_onTabSelected`, when `tab == null && _masterReactors.isNotEmpty`, `_loading` stays `false` and the same `ListView.builder` widget is reused in the tree (same `else` branch, same widget type), so Flutter preserves the scroll offset from the previous tab instead of jumping to top. AyuGram clears and rebuilds all rows in `showReaction()` which inherently resets position. — `reactions_detail.dart:383-392` ← `history_view_reactions_list.cpp:253-280`

- [ ] [MAJOR] `formatReadDateLocal` hardcodes 24-hour clock format (`HH:mm` / `HH:mm:ss`) for the non-seconds case. AyuGram uses `QLocale::system().timeFormat(QLocale::ShortFormat)` so the time respects the device's locale (12h for en-US, etc.). Dart always produces 24h regardless of locale. — `reactions_detail.dart:1028-1030` ← `api/api_who_reacted.cpp:699-710`

## send_files_box — Paid price lost, groups structure unused, AI button missing

- [ ] [CRITICAL] `starsPerMessage` (paid-post price) is never included in `SendFilesResult` and never passed to `uploadFile()` — the user-edited price from `_showEditPriceDialog` is silently discarded; paid posts on broadcast channels send without the price applied — `send_files_box.dart:85-124` (missing field in `SendFilesResult`), `chat_view.dart:4238-4252` (no price arg to `uploadFile`), `chat_state.dart:1594` (no price param), `engine_service.dart:4785` (no price param) ← `send_files_box.cpp:2413` (`options.price = hasPrice() ? _price.current() : 0`)

- [ ] [CRITICAL] `result.groups` and `result.captionGroupIndex` are computed in `_doSend` but entirely ignored by the caller — all files in a mixed-type send (e.g. photo + document) share a single `groupId` token regardless of type boundaries, so the engine receives one album spanning incompatible types; caption is assigned using a hardcoded `captionIdx = isDocGroup ? lastIdx : 0` rule rather than the group-aware index, causing captions to land on the wrong file when document groups precede media groups — `chat_view.dart:4227-4252` (single timestamp groupId, ignores `result.groups`/`result.captionGroupIndex`) ← `send_files_box.cpp:2427-2452` (`DivideByGroups` + per-group caption assignment to front/back of each typed bundle)

- [ ] [MAJOR] Compose-AI button is absent from the caption area — C++ sets up `_aiButton` via `Ui::SetupCaptionAiButton` and keeps it geometrically anchored to the caption field, but no equivalent widget exists in the Dart caption row — `send_files_box.dart:2510-2570` (caption row has emoji toggle and formatting toolbar only) ← `send_files_box.cpp:1913` (`_aiButton = Ui::SetupCaptionAiButton({...})`)

# settings_screen — Settings Main + Sub-screens Audit

## Findings

- [ ] [CRITICAL] `_PremiumInfoScreen` falls back to 21 hardcoded premium features when engine call fails — fake data rendered to user as real server content — `settings_screen.dart:2564-2586` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_main.cpp:535` (PremiumId() section uses live server data only, no static fallback)

- [ ] [CRITICAL] "Telegram Currency" row is a stub: `onTap` shows a toast "Telegram Currency management is available in the official app" instead of navigating to a working screen — `settings_screen.dart:460-462` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_main.cpp:565-578` (`showOther(CurrencyId())` navigates to live currency section)

- [ ] [CRITICAL] Missing phone/password validation suggestion banners: AyuGram shows `SetupValidatePhoneNumberSuggestion` and `SetupValidatePasswordSuggestion` cards at the top of settings when the account has unvalidated phone/password — Dart has no equivalent — `settings_screen.dart:217-533` (entire body has no validation suggestions) ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_main.cpp:641-649` (`BuildValidationSuggestions(builder)` always called in setupContent)

- [ ] [CRITICAL] Business Location editor is text-only and cannot submit geographic coordinates — Telegram Business Location API requires `lat`/`lng` fields; Dart stores only a plain address string in `_data['address']` — `settings_screen.dart:3277-3298` ← `AyuGramDesktop/Telegram/SourceFiles/settings/business/settings_location.cpp` (full location picker with map coordinates)

- [ ] [CRITICAL] Username tap when username is set copies a link to clipboard and shows a toast — should display selectable text or open the username editing flow — `settings_screen.dart:930-932` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_main.cpp:334` (`_username->setMarkedText(tr::link(...))` — selectable FlatLabel, not a copy-on-tap action)

- [ ] [MAJOR] Profile header name column left offset: Dart = 22 (padding) + 80 (avatar) + 18 (gap) = **120 px** from window left, but AyuGram `settingsNameLeft = 112 px` — 8 px too far right — `settings_screen.dart:639,650,693` ← `AyuGramDesktop/Telegram/SourceFiles/styles/style_settings.h` (`settingsNameLeft: 112px`) + `settings_main.cpp:317` (`const auto nameLeft = st::settingsNameLeft`)

- [ ] [MAJOR] Profile header `SizedBox` height 96 px; AyuGram calculates `settingsPhotoTop(8) + photo_h(~80) + settingsPhotoBottom(16) = 104 px` — header 8 px too short, bottom of avatar clips — `settings_screen.dart:637` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_main.cpp:145-147` (FixedHeightWidget formula) + `style_settings.h` (`settingsPhotoBottom: 16px`)

- [ ] [MAJOR] Language row trailing text comes from hardcoded 50-entry `_kLanguageNames` map — any language code not in the map shows the raw code; AyuGram reads `Lang::GetInstance().nativeName()` dynamically from the loaded language pack — `settings_screen.dart:36-51,379-381` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_main.cpp:493-498` (`rpl::map([] { return Lang::GetInstance().nativeName(); })`)

- [ ] [MAJOR] QR code dialog is a basic `AlertDialog` with `QrImageView` — missing avatar in QR center, Telegram-branded frame, and download/share button — `settings_screen.dart:1371-1433` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_main.cpp:251-257` (`Ui::DefaultShowFillPeerQrBoxCallback(show, _user)` — full peer QR box)

- [ ] [MAJOR] Gift recipient picker (`_GiftCatalogScreen`) sources only from `chatState.chats` filtered to `type == ChatType.dm` — misses any contact not yet in the local chat list — `settings_screen.dart:3647-3649` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_main.cpp:593-595` (`Ui::ChooseStarGiftRecipient(controller)` — full contacts picker, not just chat list)

- [ ] [MAJOR] Stars transactions categorised by `amount > 0` / `amount < 0` sign — if the amount field means something other than net credit (e.g. absolute amount with a separate direction field), all transactions are mis-sorted — `settings_screen.dart:2735-2736` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_credits.cpp` (credits use typed transaction records with explicit direction)

- [ ] [MAJOR] Missing API reloads when settings screen opens: AyuGram calls `cloudPassword().reload()`, `reloadContactSignupSilent()`, `sensitiveContent().reload()`, `globalPrivacy().reload()`, `premium().reload()`, `cloudThemes().refresh()` in `setupContent()` — Dart only calls `_loadPremiumData()`, leaving privacy/password/theme data stale — `settings_screen.dart:72-75` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_main.cpp:779-786`

- [ ] [MAJOR] Business greeting/away message editor has no recipient filter controls — AyuGram's greeting and away message screens include "who receives this message" and exceptions configuration; Dart shows only a bare text field — `settings_screen.dart:3300-3330` ← `AyuGramDesktop/Telegram/SourceFiles/settings/business/settings_greeting.cpp` and `settings_away_message.cpp`

- [ ] [MAJOR] Business chatbot editor supports only a single `bot_username` string — AyuGram's chatbot screen shows a list of connected bots and supports multiple — `settings_screen.dart:3436` (`final botUsername = _data['bot_username'] as String? ?? ''`) ← `AyuGramDesktop/Telegram/SourceFiles/settings/business/settings_chatbots.cpp` (list of chatbot configurations)

- [ ] [MAJOR] Business working hours stored as bare `"HH:MM - HH:MM"` strings per day — Telegram Business Hours API uses interval objects with open/close flags and timezone; the string format cannot round-trip through the engine correctly — `settings_screen.dart:3191,3257` ← `AyuGramDesktop/Telegram/SourceFiles/settings/business/settings_working_hours.cpp`

- [ ] [MAJOR] Gift catalog thumbnail `base64Decode()` for all items runs on the UI thread inside `_loadGifts()` without `Isolate.run` — can cause frame drops for large catalogs — `settings_screen.dart:3622-3629` ← Flutter performance best practices (CPU-bound decoding must use `Isolate.run`)

# shell — Connecting widget behavior and visual deviations

- [ ] [MAJOR] Tapping connecting widget calls `engine.connectAccount()` (reconnect attempt), but AyuGram opens the Proxy Settings dialog (`ProxiesBoxController::CreateOwningBox(account)`) on widget click — `shell.dart:1184-1185` ← `window_connecting_widget.cpp:508-509`

- [ ] [MAJOR] Connecting widget rendered as a generic Flutter `BoxDecoration` rounded pill (`borderRadius: BorderRadius.circular(15)` + `BoxShadow`) instead of AyuGram's sprite-based design using `connectingLeft`/`connectingRight` end-cap icons and `connectingBody`/`connectingLeftShadow`/`connectingRightShadow`/`connectingBodyShadow` fill sprites — `shell.dart:1205-1216` ← `window.style:173-178`, `window_connecting_widget.cpp:541-546`

- [ ] [MAJOR] Connecting widget collapse animation differs: when hover ends, Dart immediately removes the text node and animates only the padding via `AnimatedContainer`. AyuGram retains the old text in `_currentLayout` while animating `_contentWidth` to the smaller value, so text remains visible until the pill has fully shrunk — `shell.dart:1205-1267` ← `window_connecting_widget.cpp:363-381`

# shortcuts_settings_screen — 2 issues

- [ ] [CRITICAL] `MediaViewerFullscreen` command missing entirely — not in `ShortcutCommand` enum in `keyboard_shortcuts.dart` and not listed in `_commandGroups` in `shortcuts_settings_screen.dart:11-133`. AyuGram includes it as a standalone configurable shortcut between ShowAdminLog and MediaPlay groups — `shortcuts_settings_screen.dart:89-97` ← `settings_shortcuts.cpp:116-126` / `shortcuts.h:78`

- [ ] [MAJOR] Support shortcuts group (`supportReloadTemplates`, `supportToggleMuted`, `supportScrollToCurrent`, `supportHistoryBack`, `supportHistoryForward`) is exposed in the configurable shortcuts settings UI at `shortcuts_settings_screen.dart:126-133`. AyuGram defines these commands in `shortcuts.h:85-89` but deliberately excludes them from the settings `Entries()` function — they are internal support-mode bindings not intended to be user-configurable — `settings_shortcuts.cpp:42-127` (no support entries in list)

# spoiler_animation — 1 issue found

## spoiler_animation — Frame advancement uses wall-clock division instead of capped accumulation

- [ ] [MAJOR] Frame index computed as `(timestamp.inMilliseconds ~/ _kFrameDurationMs) % _kFrameCount` — during jank (a single Flutter frame takes >66ms), the animation skips multiple frames at once. AyuGram caps advancement to exactly one frame per tick via `const auto add = std::min(now - _last, kDefaultFrameDuration)`, so the animation slows but never jumps. Dart's approach causes visible discontinuities when the UI thread hitches. — `spoiler_animation.dart:91` ← `AyuGram/Telegram/lib_ui/ui/effects/spoiler_mess.cpp:794-796`

# main — Audit findings

## main — PasscodeLockScreen show animation uses wrong animation type

- [ ] [MAJOR] Passcode lock screen show animation uses `FractionalTranslation` + `Opacity` (slide+fade combined), but AyuGram uses `SlideAnimation` with `_withFade = false` — a pure horizontal slide with no opacity change. The fade component is absent in the C++ implementation. — `main.dart:2689-2702` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_lock_widgets.cpp:55-68` + `window/window_slide_animation.h:52`

## main — PasscodeLockScreen logout button uses wrong widget type

- [ ] [MAJOR] The logout link at the bottom of the passcode screen is rendered as a `GestureDetector` wrapping a plain `Text`, but AyuGram uses `Ui::LinkButton` — a link-styled control with underline and the `lightButtonFg` foreground color on hover. The Dart version uses `accentColor` (`windowBgActive`) with no text decoration, which does not match the link appearance of the original. — `main.dart:2826-2837` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_lock_widgets.h:89` + `window/window_lock_widgets.cpp:102-107`

## main — PasscodeLockScreen logout confirmation uses wrong overlay mechanism

- [ ] [MAJOR] Logout confirmation is implemented as an in-screen `Positioned.fill` overlay with a custom `Material` card managed by `_showLogoutConfirm` state. AyuGram calls `Controller::showLogoutConfirmation()` which shows a `Ui::MakeConfirmBox` — a proper layer-system modal box rendered above all content, using `st::attentionBoxButton` for the confirm button style. The Dart implementation bypasses the box layer system entirely. — `main.dart:2839-2893` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_controller.cpp:548-569`

# stats_chart — Audit findings

## stats_chart — Stats chart widget

- [ ] [MAJOR] `_paintBar` draws filled grouped side-by-side rectangles (with rounded corners, 70% column width) instead of a step-line stroke connecting bar tops. AyuGram builds a QPainterPath moving to `column.topLeft()` and drawing horizontal lines at each bar's top height, then strokes the outline — no fill, full column width. Dart's render looks like a standard grouped bar chart; AyuGram renders a staircase outline at bar tops — `stats_chart.dart:1924-1958` ← `AyuGram/statistics/view/bar_chart_view.cpp:67-107`

- [ ] [MAJOR] Ruler grid line count is off-by-one. Dart iterates `for (int i = 0; i <= rulerCount; i++)` — inclusive upper bound — drawing `rulerCount+1` lines. When `_computeRulerLineCount` returns 6 (kMaxLines), Dart draws 7 lines. AyuGram constructs `ChartRulersData` with `lines.resize(n)` and `n` equals the same computed count (6), so it draws exactly 6 lines — `stats_chart.dart:1712` ← `AyuGram/statistics/chart_rulers_data.cpp:35,57`

- [ ] [MAJOR] Ruler label values use the wrong spacing formula. Dart computes `val = mn + (mx - mn) * i / rulerCount` — evenly distributing labels from mn to mx. AyuGram computes `step = ceil(Round(maxHeight) / 5)` and assigns `absoluteValue = i * step` for each line, producing step-aligned round numbers (e.g. max=5000 → [0, 1000, 2000, 3000, 4000, 5000]). Dart would produce [0, 833, 1666, 2500, 3333, 4166, 5000] for the same data — `stats_chart.dart:1715` ← `AyuGram/statistics/chart_rulers_data.cpp:39-44`

- [ ] [MAJOR] TextPainter cache key includes the animated alpha component of the color (`${style.color?.value}` encodes the full ARGB value). During ruler crossfade animation, ruler label colors are `Colors.white.withValues(alpha: 0.6 * alpha)` where `alpha` advances every tick. Each tick produces a new unique key, creating one new TextPainter per ruler line per frame that is never evicted. The cache has no size cap or LRU policy, so it grows without bound during any Y-range transition — `stats_chart.dart:1608-1614,1698-1703`

# sticker_pack_viewer — Audit Findings

## Summary
The Dart `sticker_pack_viewer.dart` implements a modal bottom sheet for displaying sticker packs with good backend wiring and mostly accurate visual dimensions. Key findings include proper constraint-based height adjustment, correct padding/margin values matching AyuGram C++, and functional API integration for core operations. Minor behavioral differences exist in context menu handling and custom emoji rendering approach.

---

## Issues Found

### CRITICAL

- [ ] [CRITICAL] Grid uses `childAspectRatio` hardcoded without proper emoji size consideration — `sticker_pack_viewer.dart:392` ← `sticker_set_box.cpp:1271` / `chat_helpers.style`
  - Dart uses `42.0/39.0` for emoji but doesn't account for actual container constraints
  - AyuGram uses `st::emojiSetSize: size(42px, 39px)` with strict padding applied at layout time (line 1143-1145)
  - Risk: Emoji items may overflow or have incorrect vertical centering on different screen sizes

- [ ] [CRITICAL] Custom emoji rendering missing element initialization — `sticker_pack_viewer.dart:629-641` ← `sticker_set_box.cpp:2393-2399`
  - Dart falls back to `_emojiPlaceholder()` showing emoji char when `thumbB64` is empty
  - AyuGram calls `setupEmoji(index)` (line 2364) which initializes custom emoji rendering context before paint (lines 2393-2399)
  - Dart does NOT call any setup phase; custom emoji rendering is deferred to tile build, not hooked to lottie player pool
  - Impact: Custom emojis will show as text fallback instead of rendered icons

- [ ] [CRITICAL] Video player pooling logic differs significantly — `sticker_pack_viewer.dart:423-442` ← `sticker_set_box.cpp:2018-2027`
  - Dart: `maxActive = 3` fixed pool size with simple acquire/release
  - AyuGram: Uses `Lottie::MultiPlayer` (shared pool) for all animated content; webm readers created on demand via `Media::Clip::MakeReader()`
  - Dart pools video separately but doesn't pool lottie animations; no shared multi-player instance
  - Missing: Lottie multi-player integration for efficient frame generation across all stickers

### MAJOR

- [ ] [MAJOR] Bottom sheet height calculation doesn't match AyuGram logic — `sticker_pack_viewer.dart:103-105` ← `sticker_set_box.cpp:572-575`
  - Dart clamps maxHeight to 90% of screen with no scroll fallback
  - AyuGram: Uses `st::stickersMaxHeight` (320px) or `st::emojiSetMaxHeight` (197px) as hard limits, box itself handles internal scrolling
  - Dart allows sheet to expand based on content height, may exceed expected bounds on small screens

- [ ] [MAJOR] Padding calculation for grid doesn't account for layout constraints — `sticker_pack_viewer.dart:382-384` ← `sticker_set_box.cpp:1143-1145`, `chat_helpers.style`
  - Dart applies padding directly to GridView
  - AyuGram values: `stickersPadding: margins(19px, 13px, 19px, 13px)` and `emojiSetPadding: margins(12px, 0px, 12px, 0px)` are applied with strict grid geometry
  - Dart version lacks horizontal padding enforcement (0px margin for emoji in vertical axis)
  - Risk: Emoji rows may not align to grid correctly

- [ ] [MAJOR] Sticker preview overlay positioning uses hardcoded 24px offset — `sticker_pack_viewer.dart:810` ← No direct equivalent in AyuGram
  - Dart: `const previewSize = 200.0` with `y = (position.dy - previewSize - 24).clamp(...)`
  - AyuGram: Does not show persistent preview overlay; uses context menu for sticker operations
  - Behavioral mismatch: AyuGram shows context menu on right-click, Dart shows preview on long-press
  - This is intentional design difference but not wired to backend send feedback

- [ ] [MAJOR] Stripped JPEG thumb decoder may have edge case issues — `sticker_pack_viewer.dart:858-872` ← `sticker_set_box.cpp:2412-2424`
  - Dart implements custom JPEG reconstruction from stripped format with hardcoded header/footer
  - AyuGram uses `media->getStickerSmall()` + image system (line 2412-2414), delegates to data layer
  - Dart's approach is correct but bypasses centralized image cache; could cause redundant decoding

- [ ] [MAJOR] No lottie controller pooling across tiles — `sticker_pack_viewer.dart:470-476` ← `sticker_set_box.cpp:2018-2027`
  - Each `_StickerTile` creates its own AnimationController for lottie
  - AyuGram maintains single `_lottiePlayer` instance (line 440) shared across all stickers
  - Dart approach: Many controller instances active simultaneously on visible tiles
  - Risk: High memory use, frame drops with large sticker sets

### MAJOR (Behavior)

- [ ] [MAJOR] Context menu items differ in structure and capabilities — `sticker_pack_viewer.dart:696-732` ← `sticker_set_box.cpp:1702-1813`
  - Dart: Flat list (send, fav, addtoset, delete)
  - AyuGram: Conditional menu with multiple branches:
    - Emoji: copy, delete (if creator), copy ID (if AyuGram setting enabled)
    - Stickers: send + full SendMenu integration, fav toggle, add to set, delete (if creator)
  - Dart missing: AyuGram's advanced send menu (scheduled, effect selection)
  - Dart missing: Copy/delete emoji specific behavior (lines 1732-1749)

- [ ] [MAJOR] "Add to Set" dialog uses in-app picker instead of native dialog — `sticker_pack_viewer.dart:765-801` ← `sticker_set_box.cpp:1783-1786`
  - Dart: SimpleDialog with map of sets (line 779-784)
  - AyuGram: Calls `Api::AddAddToStickerSetAction()` which integrates with backend for add flow
  - Dart's implementation is complete but doesn't show loading/error states during backend operation
  - Missing async feedback during addition (line 790-800 does show toast but no loading indicator)

- [ ] [MAJOR] Copy link button text hardcoded for emoji detection — `sticker_pack_viewer.dart:188-196` ← `sticker_set_box.cpp:649`, `sticker_set_box.cpp:1014-1017`
  - Dart: Copies https://t.me/addemoji/{shortName} or https://t.me/addstickers/{shortName}
  - AyuGram: Detects via `isEmojiSet()` flag (line 649) and generates correct link
  - Both correct, but Dart stores only shortName without validation that it's non-empty

---

## BACKEND WIRING — All Functional

✓ `getStickerSetInfo()` called on init (line 69-93)
✓ `installStickerSet()` wired to install button (line 164-185)
✓ `uninstallStickerSet()` wired to remove menu action (line 237)
✓ `archiveStickerSet()` wired to archive menu action (line 240)
✓ `faveSticker()` wired to favorite context menu (line 721-725)
✓ `deleteStickerFromSet()` wired to delete dialog (line 757)
✓ `addStickerToExistingSet()` wired to add-to-set dialog (line 790-792)
✓ `getCreatedStickerSets()` called to populate add-to-set picker (line 766)
✓ `getStickerFiles()` called for animated/video sticker loading (line 530-531, 554-555)
✓ `sendSticker()` wired to grid item tap (line 210)

---

## VISUAL ACCURACY — Mostly Compliant

**Dimensions:**
- ✓ stickersMaxHeight: 320.0 matches `st::stickersMaxHeight` (line 103)
- ✓ emojiSetMaxHeight: 197.0 matches `st::emojiSetMaxHeight` (line 103)
- ✓ stickersPadding: (19, 13, 19, 13) matches exactly (line 383-384)
- ✓ emojiSetPadding: (12, 0, 12, 0) matches exactly (line 382-383)
- ✓ Stickers per row: 5 matches `kStickersPerRow` (line 381, cp. sticker_set_box.cpp:90)
- ✓ Emoji per row: 8 matches `kEmojiPerRow` (line 381, cp. sticker_set_box.cpp:91)
- ✓ Grid item size: 64x64 for stickers (implicit via padding + aspect), 42x39 for emoji (line 392)

**Colors & Styling:**
- ✓ Dark background: `0xFF1E2C3A` (line 100) matches AyuGram dark mode
- ✓ Handle bar: gray with alpha 0.4 (line 140)
- ✓ Premium lock icon: bottom-right position (line 669)
- ✓ Premium gradient: `#6B93FF` to `#976FFF` (line 334)

**Behavioral Rendering:**
- ⚠ No rounded clip applied to sticker display (AyuGram line 2383-2390 applies clipped path for stickers)
- Dart shows raw image/lottie without rounding; emoji not clipped at all
- Impact: Minor visual difference but doesn't affect functionality

---

## PERFORMANCE NOTES

- ⚠ GridView.builder is used (correct), no issues with large lists
- ✓ RepaintBoundary wraps each tile (line 397) for optimization
- ⚠ AnimationController created per tile (line 588) — not shared like AyuGram
- ⚠ Large JPEG header template instantiated (874-932) on every thumb decode

---

## PLACEHOLDERS & STUBS

✓ No empty callbacks (`onTap: () {}`) found
✓ No "coming soon" / "not implemented" messages
✓ No hardcoded mock data
✓ All SnackBars show real feedback (installed, copied, added, etc.)
✓ No TODO/FIXME comments in file

---

## File References

- Dart: `/home/nako/Documents/uniclient/dart/lib/ui/sticker_pack_viewer.dart`
- AyuGram Header: `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/boxes/sticker_set_box.h`
- AyuGram Implementation: `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/boxes/sticker_set_box.cpp`
- AyuGram Styles: `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/chat_helpers/chat_helpers.style`

## story_editor — audit findings

- [ ] [CRITICAL] Video trim parameters (`trimStart`, `trimEnd`) are passed to `sendStoryWithVideoFile` but the Go backend (`SendStoryWithVideoFile`) never applies the trim — `overlayVideoWithFFmpeg` only composites overlays; there is no ffmpeg seek/trim invocation in `telegram.go`. The user sees a trim slider and trims are stored, but the full-length video is uploaded. — `story_editor.dart:490-491` ← `go/cores/telegram.go:20122-20183` (no `-ss`/`-t` ffmpeg args)

- [ ] [CRITICAL] `sendStoryWithPhoto` is not passed `trimStart`/`trimEnd` at all at the call site (`story_editor.dart:495-505`), even though the engine service method accepts them and the Go dispatch handler also accepts them. For photo stories these params are always zeroed-out defaults — not a correctness bug for photos, but the dispatched params on line 1369-1370 of engine_service.dart are dead weight for photos. More critically, when the canvas renders video cover frame as a photo (fallback), the user gets a still from the cover rather than the trimmed section. — `story_editor.dart:493-505` ← `dart/lib/bridge/engine_service.dart:1346-1383`

- [ ] [CRITICAL] Eraser tool is implemented as `BlendMode.clear` on a single shared canvas layer, which erases the entire pixel column back to transparency — it does NOT correctly erase only previously drawn strokes underneath it. AyuGram uses a dedicated `ItemEraser` that tests which `ItemLine` objects intersect the mask rect, calls `applyEraser()` on each one individually using `CompositionMode_DestinationIn`, and adds a reversible `ItemEraser` scene item for undo. The Dart eraser will punch holes through the background image rather than just removing prior strokes. — `story_editor.dart:2108-2111` ← `editor/scene/scene.cpp:165-208`

- [ ] [CRITICAL] Blur tool uses `BackdropFilter` with a fixed sigma of 10 (`sigmaX: 10, sigmaY: 10`). AyuGram uses `photoEditorBlurRadius: 20` (style constant) passed to `Images::BlurLargeImage`. Additionally, AyuGram's blur captures the actual composite scene (all existing strokes + image) at that rect and blurs that captured source — meaning the blur effect is composited correctly as a stamped pixel region. The Dart implementation blurs the live widget tree via BackdropFilter which is correct for preview but the `_renderCanvasToBytes` export applies the full-image blur globally with sigma 10, not the masked region at radius 20. — `story_editor.dart:549-568, 843-866` ← `editor/scene/scene.cpp:211-257`, `editor/editor.style:156`

- [ ] [CRITICAL] Brush size formula diverges from AyuGram spec. AyuGram computes effective brush width as `kMinBrush + (kMaxBrush - kMinBrush) * sizeRatio` = `1 + 24 * sizeRatio`, which matches the Dart formula (`1 + 24 * _brushSizeRatio`). However, the marker multiplier in Dart is `2.5×` applied at the base size computation (`_effectiveBrushWidth`), while AyuGram applies `st::photoEditorMarkerSizeMultiplier` (2.5) only inside `strokeWidth()` after the pressure factor. The blur multiplier is `3.0×` in both, matching `st::photoEditorBlurSizeMultiplier`. Arrow head length factor in Dart is hardcoded `2.5` while AyuGram uses `st::photoEditorArrowHeadLengthFactor: 2.5` — values match but the arrow head angle in Dart is `26°` which matches `st::photoEditorArrowHeadAngleDegrees: 26`. These minor alignment issues aside, the **arrow head minimum distance** in Dart is `width * scale * 1.5` while AyuGram uses `_brushData.size * st::photoEditorArrowHeadMinDistanceFactor` (1.5 × brush size without pressure or scale). The Dart implementation uses the scaled width for lookback distance, making the arrow head appear at different thresholds than desktop. — `story_editor.dart:2138-2166` ← `editor/scene/scene_item_canvas.cpp:233-283`, `editor/editor.style:149-151`

- [ ] [MAJOR] Marker opacity in Dart is hardcoded `0.35` (`color.withValues(alpha: 0.35)`) on the marker color itself, while AyuGram applies `st::photoEditorMarkerOpacity: 0.35` via `color.setAlphaF(color.alphaF() * 0.35)` to the existing alpha — so if the user picks a semi-transparent color the behaviors differ. More importantly, AyuGram uses `CompositionMode_Source` for marker strokes inside `renderSegment`, meaning each marker stroke overwrites previous alpha exactly. The Dart implementation uses `BlendMode.src` on the canvas but applies it to the `saveLayer`'s output rather than per-segment — for overlapping marker strokes this produces different visual accumulation. — `story_editor.dart:2102-2104, 2114-2116` ← `editor/scene/scene_item_canvas.cpp:196-204`

- [ ] [MAJOR] Stroke smoothing algorithm diverges from AyuGram. AyuGram uses a 3-point weighted average (`curr * (1-0.5) + (prev+next) * 0.25`) applied twice for segments of 4+ points, plus min/max point distance clamping with interpolation for large jumps (`kMinPointDistanceBase=2, kMaxPointDistance=15`, zoom-adjusted). Dart uses a simple 3-point arithmetic mean (`(pts[i-1] + pts[i] + pts[i+1]) / 3`) without zoom-adjusted distance filtering. The Dart approach produces choppier strokes at high zoom, and fails to interpolate large jumps (fast swipes create gaps). — `story_editor.dart:2173-2188` ← `editor/scene/scene_item_canvas.cpp:96-119, 286-347`

- [ ] [MAJOR] The `_StrokePainter` `ValueListenableBuilder` receives `_strokesNotifier` which only gets a new list value during `_continueStroke`, but the `currentPoints` argument (`showCurrentNonBlur` from `_currentStrokePoints`) is captured at the point `_buildPaintLayer` is called — which only re-executes on a `setState`. `_continueStroke` does NOT call `setState`, it only mutates `_strokesNotifier`. This means the live-stroke preview (`currentPoints`) shown inside the `ValueListenableBuilder` is stale — it uses the `_currentStrokePoints` value captured on the LAST `setState` call, not the current stroke being drawn. Live stroke rendering is visually broken/laggy for non-blur strokes. — `story_editor.dart:870-891, 899-903`

- [ ] [MAJOR] The fake progress timer increments `_uploadProgress` by `0.02` every 200ms uncapped (up to 0.85), firing `setState` ~35 times during upload. This causes full widget-tree rebuilds of the entire editor every 200ms while the actual network upload is in progress. AyuGram tracks real upload progress from the uploader via reactive callbacks. — `story_editor.dart:465-472`

- [ ] [MAJOR] The photo editor completely lacks rotate and flip controls. AyuGram's photo editor exposes dedicated rotate (`photoEditorRotateButton`) and flip (`photoEditorFlipButton`) controls in `photo_editor_controls.cpp`, which are standard editing tools. The Dart story editor has no image rotation or horizontal flip of the media canvas. — `story_editor.dart` (no rotate/flip) ← `editor/photo_editor_controls.cpp:265-479`

- [ ] [MAJOR] Text background styles `outlined` and `shadowed` in Dart (`_TextBgStyle.outlined`, `_TextBgStyle.shadowed`) have no counterpart in AyuGram's `TextStyle` enum. AyuGram only has `Framed` (filled colored background), `SemiTransparent` (semi-transparent same-color background), and `Plain` (no background). The Dart `outlined` and `shadowed` modes are invented behaviors not matching the spec — and the `outlined` variant uses a border rect while `shadowed` applies a `Shadow` with `blurRadius:6 offset:(0,2)`, neither of which matches AyuGram. — `story_editor.dart:63, 627-648, 1045-1053` ← `editor/scene/scene_item_text.h:19-22`

- [ ] [MAJOR] Caption field has no `maxLength` constraint. Telegram API limits captions to 1024 characters (non-Premium) or 2048 characters (Premium). Submitting a story with a caption longer than the server limit will cause an API error at upload time. The field should enforce the limit with a character counter. — `story_editor.dart:1608-1619` ← `data/data_premium_limits.cpp:167-176` (no AyuGram UI counterpart found for story caption input, but limit is spec-defined)

- [ ] [MAJOR] Sticker items are placed at `_canvasWidth/2, _canvasHeight/2` (canvas center in logical coordinates), but the `_onCanvasTap` text placement correctly converts from screen coordinates through scale. Stickers always appear dead center on the canvas regardless of where in the sticker picker the user was looking, while AyuGram places items at the center of the scene rect (`scene.sceneRect()`). This is a minor UX deviation but stickers placed at a fixed position when multiple are added stack on top of each other with no offset. — `story_editor.dart:1962-1965, 1983-1986`

- [ ] [MAJOR] Animated stickers (TGS Lottie format) are rendered as static thumbnails. The `thumbB64` decoded in `_StickerPickerPanel._loadStickerPacks()` is a static preview image. AyuGram uses `ChatHelpers::LottiePlayerFromDocument()` to render the Lottie animation frame-by-frame for stickers placed on the scene canvas. Animated stickers placed on story canvas in AyuGram animate continuously — the Dart implementation renders the static thumb only. — `story_editor.dart:2982-3053` ← `editor/scene/scene_item_sticker.cpp:41-54`

- [ ] [MAJOR] The `_contactPickerDialog` calls `engine.getContacts(accountId)` but `_PrivacyDialog._showContactPicker` and `_showExclusionPicker` are only triggered from within the dialog widget state, which does NOT have a `mounted` check between the `await engine.getContacts` and the `showDialog` push. If the user dismisses the `_PrivacyDialog` while contacts are loading, the `if (!context.mounted) return` guards at lines 2406/2424 will catch it — however the `BuildContext` passed in is the **dialog's** context, not the route context, so the mounted check may be unreliable after the dialog is dismissed. — `story_editor.dart:2399-2440`

- [ ] [MAJOR] The blur export in `_renderCanvasToBytes` pre-blurs the entire background with `sigmaX:10/sigmaY:10` and then composites blur strokes by clipping the blurred image to circular paths. This discards any strokes already composited under the blur strokes. The correct approach (per AyuGram) is to stamp blurred-background regions per-stroke on top of the accumulated layer. The current approach means blur strokes can only see the base image, not painted strokes beneath them. — `story_editor.dart:546-568`

- [ ] [MAJOR] `_decodeAvatars()` in `_ContactPickerDialogState` decodes all avatar base64 strings synchronously in a tight loop with only one `await Future.delayed(Duration.zero)` every 50 items. For accounts with hundreds of contacts this blocks the UI thread for extended periods. Should decode on a compute isolate or decode lazily per-visible-item. — `story_editor.dart:2470-2481`

# telegram_toast — Sticker toast message/behavior deviations

- [ ] [CRITICAL] Emoji sticker toast hardcodes `'Animated Emoji'` as the title line instead of using `widget.packName` — the actual pack name is never shown for the `isEmoji && !toSaved && !topicIcon && !isReaction` branch — `telegram_toast.dart:465` ← `history/view/history_view_sticker_toast.cpp:148` (`tr::bold(title)` always uses the resolved set title)

- [ ] [MAJOR] TopicIcon branch shows wrong message: Dart renders "This icon is from the {packName} pack" with a clickable pack-name link (dart:426–438), but AyuGram treats topicIcon as `isEmoji=true` and shows `lng_animated_emoji_text` = "Subscribe to **Telegram Premium** to unlock this emoji." — `telegram_toast.dart:426` ← `history/view/history_view_sticker_toast.cpp:143–155`

- [ ] [MAJOR] Toast body strings lack inline bold for key phrases: AyuGram uses `tr::rich` which renders `**Telegram Premium**` and `**Saved Messages**` bold mid-sentence; Dart renders both as plain unstyled text — `telegram_toast.dart:421,468` ← `Telegram/Resources/langs/lang.strings:289–290` (`lng_animated_emoji_text`, `lng_animated_emoji_saved`)

- [ ] [MAJOR] Sticker toast "View"/"Open" button is a bare `GestureDetector(child: Text(...))` (dart:560–575) instead of a `Ui::RoundButton` styled with `st::historyPremiumViewSet` (height: 44px, textTop: 13px, transparent bg, no ripple) — button lacks proper tap target size and semantics — `telegram_toast.dart:560` ← `history/view/history_view_sticker_toast.cpp:201–204`

- [ ] [MAJOR] No animated custom-emoji preview: AyuGram's `setupEmojiPreview` uses `CustomEmoji::Instance`/`CustomEmoji::Object` to animate the emoji live inside the toast (sticker_toast.cpp:264–323). Dart has no equivalent renderer — when `stickerLottieData` is null it falls back to plain emoji text (dart:505–519), so animated custom emoji always appear as a static glyph — `telegram_toast.dart:472–503` ← `history/view/history_view_sticker_toast.cpp:264–323`

# telegram_tooltip — Audit Findings

- [ ] [MAJOR] Drag-distance threshold for hiding the hover tooltip is `20.0px` (hardcoded) vs AyuGram's `QApplication::startDragDistance()` (~4px on desktop). Dart keeps the tooltip alive through 5× more cursor movement than expected, so it lingers far too long when the user moves the pointer away. — `telegram_tooltip.dart:35` ← `tooltip.cpp:68`

- [ ] [MAJOR] `arrowSkip` parameter is accepted by `_ImportantTooltipDelegate` (field at line 401) but is never read inside `getPositionForChild()` (lines 420–441). AyuGram uses `_st.arrowSkip` (66px) to offset the tooltip horizontally for Left/Right preferred alignment: `left = areaMiddle + _st.arrowSkip - width()` / `left = areaMiddle - _st.arrowSkip`. Without this, the tooltip is always centered over the target regardless of the requested preferred side, making the arrow point to the wrong spot. — `telegram_tooltip.dart:401,420` ← `tooltip.cpp:374-376`

- [ ] [MAJOR] `_ImportantTooltipDelegate.getConstraintsForChild()` sets only `maxWidth`/`maxHeight` (lines 412–417) with no `minWidth`. AyuGram enforces `size.width() < 2 * (_st.arrowSkipMin + _st.arrow)` → minimum 56px so the arrow clamp range `[arrowSkipMin, width - arrowSkipMin]` is always valid. Without it, on narrow tooltips `size.width - _kArrowSkipMin` can be less than `_kArrowSkipMin`, inverting the clamp and drawing the arrow at the wrong position. — `telegram_tooltip.dart:412` ← `tooltip.cpp:253-255`

- [ ] [MAJOR] RTL (right-to-left) tooltip positioning is not implemented. AyuGram flips the horizontal shift for RTL locales: `p.setX(m.x() - s.width() - _st->shift.x())`. Dart's `_TooltipPositionDelegate.getPositionForChild()` always applies the shift in the same direction regardless of locale, placing the tooltip on the wrong side of the cursor for Arabic/Hebrew users. — `telegram_tooltip.dart:182` ← `tooltip.cpp:111-113`

# theme_editor — Audit findings

- [ ] [CRITICAL] Row tap opens inline hex strip at bottom instead of a full `ColorEditor` RGBA dialog — AyuGram always opens `Ui::show(Box([=](...) { ColorEditor(box, ColorEditor::Mode::RGBA, value) ... }))` directly on row activation; the bottom-strip inline editor (`_buildInlineColorEditor`) is a Dart-only invention that doesn't exist in the reference — `theme_editor.dart:571` ← `AyuGramDesktop/window/themes/window_theme_editor_block.cpp:313`

- [ ] [CRITICAL] "Existing" section header rendered above the existing-color list — AyuGram has **no** header for the existing-rows block; only the new-rows block gets a title drawn in `Inner::paintEvent` (`tr::lng_theme_editor_new_keys`) — `theme_editor.dart:177` ← `AyuGramDesktop/window/themes/window_theme_editor.cpp:544`

- [ ] [CRITICAL] Save box background always starts null for a fresh editor session — AyuGram's `CollectData()` obtains the background via `Background()->createCurrentImage()` so it always contains the live chat wallpaper; the Dart passes `existingBackground: _currentBackground` which is `null` unless the user previously imported a theme file — `theme_editor.dart:294` ← `AyuGramDesktop/window/themes/window_theme_editor_box.cpp:756`

- [ ] [CRITICAL] When the color-editor box is already open, clicking a second row must switch its displayed color instead of opening a new editor — AyuGram checks `if (_context->colorEditor.editor)` and calls `editor->showColor(row.value())` to reuse the open box; the Dart closes/reopens inline state per row with no such reuse — `theme_editor.dart:217` ← `AyuGramDesktop/window/themes/window_theme_editor_block.cpp:314`

- [ ] [MAJOR] `copyOf` reference line rendered at `fontSize: 13` but AyuGram uses `themeEditorCopyNameFont: font(fsize semibold)` which is the default 14 px body size — `theme_editor.dart:1006` ← `AyuGramDesktop/window/window.style:171`

- [ ] [MAJOR] Slug field shows `prefixText: 'addtheme/'` instead of the full server link — AyuGram sets `link->setLinkPlaceholder(session.createInternalLink(u"addtheme/"_q))` which prepends `t.me/` (or the configured server URL); users see a truncated prefix with no domain — `theme_editor.dart:1455` ← `AyuGramDesktop/window/themes/window_theme_editor_box.cpp:823`

- [ ] [MAJOR] No explanation label under the slug field in the save box — AyuGram adds `tr::lng_theme_editor_link_about()` as a `FlatLabel` divider label after the link input (`box->addRow(object_ptr<Ui::FlatLabel>(..., tr::lng_theme_editor_link_about()...))`); the Dart omits this entirely — `theme_editor.dart:1484` ← `AyuGramDesktop/window/themes/window_theme_editor_box.cpp:827`

- [ ] [MAJOR] No loading indicator shown in the save box during upload — AyuGram calls `box->showLoading(true)` before starting `SavePreparedTheme` and `box->showLoading(false)` on failure; the Dart sets `_saving = true` but never disables the save button or shows a spinner in the dialog — `theme_editor.dart:331` ← `AyuGramDesktop/window/themes/window_theme_editor_box.cpp:904`

- [ ] [MAJOR] Search uses linear full-scan per keystroke — AyuGram builds an inverted per-first-char index (`_searchIndex`) and narrows candidates in O(matches) before word-checking; `_matchesFilter()` in Dart iterates the entire `_colorMap` (≈400 tokens) on every character typed — `theme_editor.dart:148` ← `AyuGramDesktop/window/themes/window_theme_editor_block.cpp:385`

# titlebar — Audit findings

- [ ] [MAJOR] Missing accessibility labels on window buttons — AyuGram calls `setAccessibleName(phraseMinimize())`, `setAccessibleName(phraseMaximize()/phraseRestore())`, and `setAccessibleName(phraseButtonClose())` on each button widget. The Dart `_WinButton` has no `Tooltip` or `Semantics` wrapper, making the buttons invisible to screen readers and assistive technology. — `titlebar.dart:383-408` ← `ui_platform_window_title.cpp:92,103,112,123`

- [ ] [MAJOR] Double-click/drag race condition — In AyuGram, `mouseDoubleClickEvent` is a dedicated Qt OS-level event dispatched before the second `mousePressEvent`, so double-click always wins over drag initiation. In Dart, `Listener.onPointerMove` (which sets `_mousePressed = false` and calls `_startDrag()`) and the nested `GestureDetector.onDoubleTap` (which calls `_toggleMaximize()`) share the same raw pointer event stream with no priority ordering. If the pointer moves even one logical pixel during the second press of a double-tap, `_startDrag()` fires and `_toggleMaximize()` is never called. Double-click-to-maximize is therefore unreliable when the user's hand moves slightly. — `titlebar.dart:269-289` ← `ui_platform_window_title.cpp:487-503`

# web_app_panel — Audit

- [ ] [CRITICAL] `_handleShareToStory` is an empty stub — C++ shows a "story sharing not supported" blocking popup to the user; Dart does nothing (silent no-op) — `web_app_panel.dart:538-540` ← `attach_bot_webview.cpp:1479-1490`

- [ ] [MAJOR] `sendViewport` / `_handleRequestViewport` always computes `is_state_stable` from `_loadingState` — C++ always sends `is_state_stable: true` unconditionally; Dart sends `false` while still loading, which breaks bots that rely on stability signal — `web_app_panel.dart:1103-1114` ← `attach_bot_webview.cpp:1125-1130`

- [ ] [MAJOR] `_handleOpenPopup` with empty message or empty buttons posts `popup_closed` event instead of closing — C++ calls `botClose()` on invalid popup args (empty message or buttons); Dart posts `{'button_id': ''}` without closing — `web_app_panel.dart:1123-1125` ← `attach_bot_webview.cpp:1442-1450`

- [ ] [MAJOR] `_handleOpenPopup` does not validate button `type` against the known set — C++ validates each button type against `{default, ok, close, cancel, destructive}` and calls `botClose()` on unknown type; Dart accepts any string, producing incorrect rendering (no `fontWeight` for `ok`, wrong color logic) — `web_app_panel.dart:1133-1145` ← `attach_bot_webview.cpp:1419-1449`

- [ ] [MAJOR] `_handleSetupButton` does not close on empty args — C++ calls `botClose()` when `processButtonMessage` receives empty args; Dart processes the empty map with all-default values instead — `web_app_panel.dart:1058` ← `attach_bot_webview.cpp:1696-1699`

- [ ] [MAJOR] `_handleDeviceStorageSaveKey` missing `QUOTA_EXCEEDED` error path — C++ returns `QUOTA_EXCEEDED` when `botStorageWrite` returns false (quota hit); Dart engine path only handles success/`WRITE_FAILED`, never sends `QUOTA_EXCEEDED` — `web_app_panel.dart:927-944` ← `attach_bot_webview.cpp:1314-1319`

- [ ] [MAJOR] No palette/theme change listener — C++ merges `style::PaletteChanged()` with `_themeUpdateForced` and automatically calls `updateThemeParams` + posts `theme_changed` to the webview on every palette change; Dart only sends `theme_changed` when the webview explicitly requests it via `web_app_request_theme`; system theme switches are never propagated — `web_app_panel.dart:1094-1099` ← `attach_bot_webview.cpp:477-488`

- [ ] [MAJOR] `_handleVerifyAge` skips engine call when `age == 0` — C++ always calls `botVerifyAge(age)` regardless of age value (age 0 means unknown/not detected, which the engine should handle); Dart skips the call entirely when `age == 0` — `web_app_panel.dart:1047` ← `attach_bot_webview.cpp:1063-1073`

- [ ] [MAJOR] `_showCloseConfirmation` has no guard against repeated invocation — C++ uses `_closeWithConfirmationScheduled` flag to ensure only one confirmation dialog is queued at a time (prevents double-pop if user triggers close repeatedly); Dart has no such flag and can stack multiple `showDialog` calls — `web_app_panel.dart:1245-1265` ← `attach_bot_webview.cpp:1654-1659`

- [ ] [MAJOR] `sendContentSafeArea` uses a fixed `_kHeaderHeight + 8` for fullscreen top inset instead of computing from DPI — C++ calculates `top` from panel close button height plus `separatePanelClose.rippleAreaPosition.y()`, then converts to CSS pixels using the screen's logical DPI and device pixel ratio; Dart hardcodes `(56 + 8).round() = 64` CSS px — `web_app_panel.dart:299-302` ← `attach_bot_webview.cpp:1143-1160`

# engine_models — audit findings

## CachedMessage vs HistoryItem / HistoryItemCommonFields

- [ ] [MAJOR] `CachedMessage` missing `effectId` (message effect/animation, e.g. animated confetti) — `engine_models.dart:459` ← `AyuGramDesktop/Telegram/SourceFiles/history/history_item.h:94` (`HistoryItemCommonFields.effectId = 0`)

- [ ] [MAJOR] `CachedMessage` missing `starsPaid` (paid stars for posting in a paid channel) — `engine_models.dart:459` ← `AyuGramDesktop/Telegram/SourceFiles/history/history_item.h:90` (`HistoryItemCommonFields.starsPaid = 0`)

- [ ] [MAJOR] `CachedMessage` missing `shortcutId` (Business Shortcut message ID) — `engine_models.dart:459` ← `AyuGramDesktop/Telegram/SourceFiles/history/history_item.h:89` (`HistoryItemCommonFields.shortcutId = 0`)

- [ ] [MAJOR] `CachedMessage` missing reply-to-story reference (`replyToStoryId`, `replyToStoryPeer`) — `engine_models.dart:472` (`replyToId` is plain string) ← `AyuGramDesktop/Telegram/SourceFiles/data/data_msg_id.h:189` (`FullReplyTo.storyId: FullStoryId`)

- [ ] [MAJOR] `CachedMessage` missing reply quote text and offset — `engine_models.dart:472` (`replyToId` only) ← `AyuGramDesktop/Telegram/SourceFiles/data/data_msg_id.h:191,195` (`FullReplyTo.quote: TextWithEntities`, `FullReplyTo.quoteOffset: int`)

- [ ] [MAJOR] `CachedMessage` missing `topicRootId` as a standalone message-level field for thread navigation — `engine_models.dart:511` (has `topicId` from extra blob) ← `AyuGramDesktop/Telegram/SourceFiles/data/data_msg_id.h:193` (`FullReplyTo.topicRootId: MsgId`)

## MessageReaction vs Data::MessageReaction

- [ ] [MAJOR] `MessageReaction` named field `byMe` should map to C++ `my` — naming divergence is fine as long as the Go bridge uses `by_me`, but `RecentReaction.my` is a separate field and is NOT surfaced in Dart at all; there is no way to identify if the per-user reaction is unread — `engine_models.dart:1293` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_message_reactions.h:377-385` (`RecentReaction.unread`, `RecentReaction.big`, `RecentReaction.my`)

- [ ] [MAJOR] `MessageReaction` missing paid-reaction top-paid-peer data (`topPaid` list showing who sent the most paid reactions) — `engine_models.dart:1293` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_message_reactions.h:388-397` (`MessageReactionsTopPaid: peer, count, top, my`)

## GroupCallParticipant vs Data::GroupCallParticipant

- [ ] [MAJOR] `GroupCallParticipant` uses `hasVideo: bool` but AyuGram tracks `videoJoined` (boolean) and a full `videoParams` struct with camera/screen endpoint details and pause state — `engine_models.dart:2310` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_group_call.h:54` (`GroupCallParticipant.videoJoined = false`)

- [ ] [MAJOR] `GroupCallParticipant` missing `onlyMinLoaded` flag (indicates participant data is a minimal snapshot not yet fully resolved) — `engine_models.dart:2303` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_group_call.h:53` (`GroupCallParticipant.onlyMinLoaded : 1 = false`)

## GroupCallInfo vs Data::GroupCall

- [ ] [MAJOR] `GroupCallInfo` missing `recordStartDate` (when recording started; 0 = not recording) — `engine_models.dart:2363` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_group_call.h:102` (`GroupCall.recordStartDate()`)

- [ ] [MAJOR] `GroupCallInfo` missing `listenersHidden` flag (used in conference/video-stream calls to hide listener list) — `engine_models.dart:2363` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_group_call.h:88` (`GroupCall.listenersHidden()`)

- [ ] [MAJOR] `GroupCallInfo` missing `messagesEnabled` / `messagesMinPrice` fields (group-call chat messages) — `engine_models.dart:2363` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_group_call.h:201,211` (`GroupCall.messagesEnabled()`, `GroupCall.messagesMinPrice()`)

- [ ] [MAJOR] `GroupCallInfo` missing `conferenceInviteLink` (conference mode invite URL) — `engine_models.dart:2363` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_group_call.h:188` (`GroupCall.conferenceInviteLink()`)

## ForumTopic vs Data::ForumTopic

- [ ] [MAJOR] `ForumTopic` stores `iconEmojiId: int` but AyuGram uses `DocumentId` (uint64) for the icon; `int` in Dart is 64-bit so no overflow, but the field is missing the concept that it can be a custom emoji document — semantically correct but `iconEmojiId` set to `0` vs an actual document-id could cause rendering issues. The Go bridge must ensure 0 means "no custom icon" consistently. Potential issue if Go truncates to int32 — `engine_models.dart:377` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_forum_topic.h:233` (`_iconId: DocumentId`)

- [ ] [MAJOR] `ForumTopic` missing `notify` (per-topic notification settings override) — `engine_models.dart:372` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_forum_topic.h:169` (`ForumTopic._notify: PeerNotifySettings`)

## StoryItem vs Data::Story

- [ ] [MAJOR] `StoryItem` uses `reactions: int` (aggregate count only) but AyuGram's `StoryViews` also has per-`ReactionId` reaction counts and stores viewer list — `engine_models.dart:3158` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_story.h:77` (`StoryViews.reactionsCounts: flat_map<ReactionId, int>`)

- [ ] [MAJOR] `StoryItem` missing `sentReactionId` (the reaction the current user sent to this story) — `engine_models.dart:3146` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_story.h:205` (`Story.sentReactionId()`)

- [ ] [MAJOR] `StoryItem` missing `inProfile` flag (story is pinned in the peer's profile grid, separate from the `pinned` field which means "pinned-to-top") — `engine_models.dart:3159` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_story.h:186` (`Story.setInProfile()`, `Story.inProfile()`)

## PollOption vs PollAnswer

- [ ] [MAJOR] `PollOption` missing `recentVoters` list (peers who voted for this specific option) — `engine_models.dart:1388` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_poll.h:46` (`PollAnswer.recentVoters: vector<PeerData*>`)

- [ ] [MAJOR] `PollOption` missing `media` (per-answer photo/document/geo attachment, used in photo polls) — `engine_models.dart:1388` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_poll.h:45` (`PollAnswer.media: PollMedia`)

- [ ] [MAJOR] `CachedMessage.pollOptions` missing quiz `solution` text (explanation shown after quiz closes) — `engine_models.dart:551` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_poll.h:112` (`PollData.solution: TextWithEntities`)

- [ ] [MAJOR] `CachedMessage` poll missing `shuffleAnswers` flag — `engine_models.dart:553` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_poll.h:75` (`PollData::Flag::ShuffleAnswers`)

- [ ] [MAJOR] `CachedMessage` poll missing `revotingDisabled` flag — `engine_models.dart:553` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_poll.h:76` (`PollData::Flag::RevotingDisabled`)

- [ ] [MAJOR] `CachedMessage` poll missing `openAnswers` flag (open-ended poll where users type a custom answer) — `engine_models.dart:553` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_poll.h:77` (`PollData::Flag::OpenAnswers`)

- [ ] [MAJOR] `CachedMessage` poll missing `hideResultsUntilClose` flag — `engine_models.dart:553` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_poll.h:78` (`PollData::Flag::HideResultsUntilClose`)

## StickerSetInfo vs Data::StickersSet

- [ ] [MAJOR] `StickerSetInfo` missing `installDate` (timestamp when user installed the set; 0 = not installed) — `engine_models.dart:2724` ← `AyuGramDesktop/Telegram/SourceFiles/data/stickers/data_stickers_set.h:121` (`StickersSet.installDate: TimeId = 0`)

- [ ] [MAJOR] `StickerSetInfo` missing `textColor` flag (set uses text-color-dependent rendering) — `engine_models.dart:2724` ← `AyuGramDesktop/Telegram/SourceFiles/data/stickers/data_stickers_set.h:51` (`StickersSetFlag::TextColor`)

- [ ] [MAJOR] `StickerSetInfo` missing `channelStatus` flag (set is a channel status sticker set, not shown in regular panels) — `engine_models.dart:2724` ← `AyuGramDesktop/Telegram/SourceFiles/data/stickers/data_stickers_set.h:52` (`StickersSetFlag::ChannelStatus`)

- [ ] [MAJOR] `StickerSetInfo` missing `thumbnailDocumentId` (document ID for the set thumbnail, used when no cover-sticker is loaded) — `engine_models.dart:2724` ← `AyuGramDesktop/Telegram/SourceFiles/data/stickers/data_stickers_set.h:111` (`StickersSet.thumbnailDocumentId: DocumentId = 0`)

## AdminLogEvent vs MTPDchannelAdminLogEvent

- [ ] [MAJOR] `AdminLogEvent` fields `userId: int` and `messageId: int` should be 64-bit compatible — in Dart `int` is 64-bit so no overflow. However, `AdminLogEvent.action` is a plain `String` enum tag while AyuGram generates distinct `HistoryItem` service messages per action type via `GenerateItems` — the Dart model conflates all event types into a flat `action`+`detail`+`oldValue`+`newValue` schema, losing structured sub-data such as old/new permissions objects, sticker-set changes, linked channel changes, etc. This is an architectural limitation rather than a simple field miss — `engine_models.dart:1846` ← `AyuGramDesktop/Telegram/SourceFiles/history/admin_log/history_admin_log_item.h:22` (`GenerateItems` produces per-action HistoryItem with full media/service text)

## FolderInfo vs Data::ChatFilter

- [ ] [MAJOR] `FolderInfo` missing `hasMyLinks` flag (folder has shared invite links created by this user; controls "Manage Links" UI) — `engine_models.dart:1561` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_chat_filters.h:93` (`ChatFilter::Flag::HasMyLinks`, `chatFilter.hasMyLinks()`)

## ScheduledMessages / ScheduleRepeatOption

No critical/major issues. The Dart `ScheduledMessages` utility class closely mirrors what the C++ `Data::ScheduledMessages` exposes at the API layer. The `kScheduledUntilOnlineTimestamp = 0x7FFFFFFE` constant matches the Telegram protocol value. The repeat-period options are app-level UI constants, not protocol-defined.

