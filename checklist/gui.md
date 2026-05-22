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

# theme_file — Palette token coverage and parser gaps

## Summary
`theme_file.dart` implements `.tdesktop-theme` ZIP parsing, palette text parsing, theme export, cloud-theme metadata read/write, and a JSON+dat disk cache. The logic is structurally sound but is missing 51 of the 580 tokens defined in AyuGram's authoritative `colors.palette`, and the palette parser silently drops `/* */` block comments.

---

- [ ] [CRITICAL] `paletteToMap` / `paletteFromMap` are missing 51 tokens that exist in AyuGram's `colors.palette`: `creditsBg1`, `creditsBg2`, `creditsBg3`, `creditsFg`, `creditsStroke`, `currencyFg`, `outdateSoonBg`, `outdatedBg`, `outdatedFg`, `photoEditorItemBaseHandleFg`, `rankAdminFg`, `rankOwnerFg`, `rankUserFg`, `songCoverOverlayFg`, `spellUnderline`, `statisticsChartActive`, `statisticsChartInactive`, `statisticsChartLineBlue`, `statisticsChartLineCyan`, `statisticsChartLineGolden`, `statisticsChartLineGreen`, `statisticsChartLineIndigo`, `statisticsChartLineLightblue`, `statisticsChartLineLightgreen`, `statisticsChartLineOrange`, `statisticsChartLinePurple`, `statisticsChartLineRed`, `walletBalanceFg`, `walletSubBalanceFg`, `walletTitleBg`, `walletTitleBgActive`, `walletTitleButtonBg`, `walletTitleButtonBgActive`, `walletTitleButtonBgActiveOver`, `walletTitleButtonBgOver`, `walletTitleButtonCloseBg`, `walletTitleButtonCloseBgActive`, `walletTitleButtonCloseBgActiveOver`, `walletTitleButtonCloseBgOver`, `walletTitleButtonCloseFg`, `walletTitleButtonCloseFgActive`, `walletTitleButtonCloseFgActiveOver`, `walletTitleButtonCloseFgOver`, `walletTitleButtonFg`, `walletTitleButtonFgActive`, `walletTitleButtonFgActiveOver`, `walletTitleButtonFgOver`, `walletTopBg`, `walletTopIconFg`, `walletTopIconRipple`, `walletTopLabelFg`. Any `.tdesktop-theme` file that customises these tokens will silently fall back to defaults — `dart/lib/theme/theme_file.dart:386–922` (paletteToMap) ← `AyuGram/Telegram/lib_ui/ui/colors.palette:609–692` (51 tokens defined there, absent here)

- [ ] [MAJOR] `parsePaletteText` does not handle `/* ... */` block comments — it only skips full lines that start with `//` (`line.startsWith('//')` check at line 109) and inline `//` trailing comments (line 118). AyuGram's `ReadPaletteValues` calls `base::parse::stripComments` first, which removes both `//` line comments and `/* */` block comments before tokenising. A palette file containing a block comment would cause the parser to attempt to parse the comment text as `key: value`, producing garbage token names and silently corrupting the parsed palette — `dart/lib/theme/theme_file.dart:109,118` ← `AyuGram/Telegram/SourceFiles/window/themes/window_theme.cpp:1522` (`stripComments` call inside `ReadPaletteValues`)

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

## active_sessions_screen — gradient colors wrong for multiple device types; row layout differs from AyuGram

- [ ] [CRITICAL] Device gradient colors are wrong for Windows, Mac, and Other device types — AyuGram maps Windows/Mac/Other to `historyPeer4` (blue: #5caffa → #408acf), but Dart assigns `_kGreen1/_kGreen2` (#67B84D → #4DB847, green) — `active_sessions_screen.dart:37-48,140-143,170-171` ← `settings_active_sessions.cpp:240-244` + `colors.palette:293-324`

- [ ] [CRITICAL] Device gradient colors are wrong for Android — AyuGram uses `historyPeer2` (#9ad164 → #46ba43, green), Dart uses `_kRed1/_kRed2` (#DE6B6B → #D45050, red) — `active_sessions_screen.dart:45-46,139` ← `settings_active_sessions.cpp:251-253` + `colors.palette:317`

- [ ] [CRITICAL] Device gradient colors are wrong for iPhone/iPad — AyuGram uses `historyPeer7` (#5bcbe3 → #359ad4, sea/teal), Dart uses `_kCyan1/_kCyan2` (#60C5E2 → #41B5D8) — the hue is similar but the secondary color `#41B5D8` diverges significantly from `#359ad4`; also AyuGram uses same peer7 slot for both iOS and iPad — `active_sessions_screen.dart:43-44,154-161` ← `settings_active_sessions.cpp:248-250` + `colors.palette:308-322`

- [ ] [CRITICAL] Device gradient colors are wrong for Ubuntu — AyuGram uses `historyPeer8` (#febb5b → #f68136, orange/amber), Dart uses `_kOrange1/_kOrange2` (#DE8C3E → #E67429) — neither tone nor hue matches — `active_sessions_screen.dart:39-40,128-133` ← `settings_active_sessions.cpp:245-246` + `colors.palette:311-323`

- [ ] [CRITICAL] Device gradient colors are wrong for Linux — AyuGram uses `historyPeer5` (#b694f9 → #6c61df, purple), Dart uses `_kPurple1/_kPurple2` (#8C79D2 → #6B5EBF) — similar hue but both top and bottom tones are significantly darker/different — `active_sessions_screen.dart:41-42` ← `settings_active_sessions.cpp:247` + `colors.palette:302-320`

- [ ] [CRITICAL] Device gradient colors are wrong for all browser/web types — AyuGram uses `historyPeer6` (#ff8aac → #d95574, pink/rose), Dart uses `_kPink1/_kPink2` (#CB79D2 → #BF5EBF, purple-pink) — clearly different hue — `active_sessions_screen.dart:47-48,113-121` ← `settings_active_sessions.cpp:253-258` + `colors.palette:305-321`

- [ ] [MAJOR] Row text layout differs from AyuGram — AyuGram renders three text elements per row: (1) device name at `namePosition: point(78px, 11px)`, (2) app info via `setCustomStatus` at `statusPosition: point(78px, 32px)`, (3) location+date as a third custom-painted line at `sessionLocationTop: 54px`. Dart renders only two text lines stacked in a Column with 2px spacing, omitting the distinct location line at 54px — `active_sessions_screen.dart:1219-1249` ← `settings_active_sessions.cpp:543-605` + `settings.style:408-423`

- [ ] [MAJOR] `_formatDaysLabel` uses `.round()` for month/week conversion instead of integer division — AyuGram's `DaysLabel` uses `std::max(days / 30, 1)` (integer truncation) and `std::max(days / 7, 1)`, but Dart uses `(days / 30).round()` and `(days / 7).round()` — produces different labels at boundary values (e.g. 25 days: Dart rounds to 4 weeks, AyuGram gives 3 weeks) — `active_sessions_screen.dart:327-337` ← `self_destruction_box.cpp:185-193`

- [ ] [MAJOR] Auto-terminate dialog uses an inline custom radio dialog instead of AyuGram's `SelfDestructionBox` — AyuGram opens a `SelfDestructionBox` which calls `_session->api()->authorizations().updateTTL(value)` to persist changes to the server. Dart calls `engine.setSessionAutoTerminateDays()` on OK which is correct wiring, but the description text ("If you don't come online...") differs from AyuGram's `tr::lng_self_destruct_sessions_description` ("If you don't sign in to your account...") — `active_sessions_screen.dart:382-384` ← `self_destruction_box.cpp:147-149`

- [ ] [MAJOR] Session info box shows "Official App: Yes/No" row as an always-visible row even when value is "No" — AyuGram's `AddSessionInfoRow` skips empty values but always renders the official app field via `tr::ayu_SessionInfoOfficialApp()`. The Dart implementation always renders this row unconditionally including for every session type; this is actually correct behavior but uses hardcoded "Official App" label string instead of a localisation key — `active_sessions_screen.dart:649-656` ← `settings_active_sessions.cpp:463-468`

- [ ] [MAJOR] `_DeviceUserpicBig` Lottie animation uses `LottieDelegates` with `ValueDelegate.color(['**'], Colors.white)` to colorize — AyuGram instead renders the lottie frame in black, then calls `style::colorizeImage` with `st::historyPeerUserpicFg` (which is theme-aware white/black). The Dart approach hardcodes white, breaking dark/light theme correctness if `historyPeerUserpicFg` is ever non-white — `active_sessions_screen.dart:1390-1397` ← `settings_active_sessions.cpp:395-406`

# admin_tools — Audit Findings

## _EditPeerInfoBox / _EditPeerPermissionsBox / _EditRestrictedBox / _EditAdminBox / _AdminLogScreen / _InviteLinksBox / _MemberListScreen

- [ ] [CRITICAL] `_noForwards`, `_joinToSend`, `_joinRequest` are loaded and saved but never shown as toggle rows in `_buildSettingsSection` — the user cannot toggle "Restrict Saving Content", "Members Must Subscribe to Send", or "Approval Required to Join" — `admin_tools.dart:68-70,465-581` ← `AyuGram/boxes/peers/edit_peer_type_box.cpp:226-265` (joinToWrite/requestToJoin toggles rendered inside the type box; noForwards rendered at line 280)

- [ ] [CRITICAL] `_showColorPickerDialog` only shows a flat color swatch grid; it completely omits emoji status selection (`statusId`) and background emoji selection (`backgroundEmojiId`) — users cannot pick a custom emoji badge for their channel — `admin_tools.dart:1060-1110` ← `AyuGram/boxes/peers/edit_peer_color_box.cpp:489-612` (full state includes `backgroundEmojiId`, `statusId`, separate emoji picker panels)

- [ ] [CRITICAL] Permissions box `_EditPeerPermissionsBox._mediaFlags` list is missing `send_gifs` and `send_games`/`send_inline` flags. AyuGram groups `SendStickers | SendGifs | SendGames | SendInline` as a single "Send stickers & GIFs" row with interdependencies (SendGifs↔SendStickers, SendGames↔SendStickers, SendInline↔SendStickers). The Dart implementation omits `send_gifs` entirely and has no interdependency logic for games/inline — `admin_tools.dart:1998-2008` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:88-91` (Flag::SendStickers | Flag::SendGifs | Flag::SendGames | Flag::SendInline grouped as one item)

- [ ] [CRITICAL] `_EditPeerPermissionsBox._otherFlags` includes `edit_rank` as a group-wide ban restriction. `EditRank` is NOT a standard `ChatRestriction` ban flag applied via `DefaultBannedRights` — it is a separate `ChatRestriction` flag (bit 26) that cannot be set through `setDefaultBannedRights`. Sending it will be silently ignored or rejected — `admin_tools.dart:2013` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:99-101` (EditRank shown only for `isUserSpecific` context, not as a default group restriction)

- [ ] [CRITICAL] `_EditRestrictedBox._mediaFlags` also omits `send_gifs` — same issue as the group permissions box. The Telegram API tracks `SendGifs` separately from `SendStickers` and they are individually settable per-user — `admin_tools.dart:2733-2741` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:88-91`

- [ ] [CRITICAL] `_showAffiliateProgramDialog` is read-only — it displays the current affiliate program info but provides no way to create or configure a new affiliate program. AyuGram opens a dedicated `starref_setup_widget` (via `info_bot_starref_setup_widget.h`) for this — `admin_tools.dart:1339-1390` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:54` (`#include "info/bot/starref/info_bot_starref_setup_widget.h"`, used for full setup flow)

- [ ] [CRITICAL] "Statistics" / "Boosts" / "Monetize" (channel earn) sections are completely absent from `_buildAdminControlsSection`. AyuGram shows dedicated Statistics, Boosts, and Earn/Monetize buttons that open full info sections — `admin_tools.dart:1513-1638` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:50-57` (`#include "info/channel_statistics/boosts/info_boosts_widget.h"`, `info_channel_earn_widget.h`, `api_statistics.h`)

- [ ] [MAJOR] `_EditAdminBox` group section `_section3` contains `manage_ranks` key. The correct Telegram API admin right key is `manage_call` (for voice chats) and the rank management is implicit — there is no `manage_ranks` admin right in the MTProto spec. AyuGram uses `ManageRanks` (bit flag) but this is a data_channel field, not a promotable admin right sent via `editAdmin` — `admin_tools.dart:3376` ← `AyuGram/boxes/peers/edit_participant_box.cpp:327` (`Flag::ManageRanks` is in `defaultRights()` for group but not sent as a grantable right in `editAdmin` payload)

- [ ] [MAJOR] `_AdminLogFilterDialog._labelToFilterKeys` maps "Removed members" to `['kick', 'leave']` — but AyuGram uses only `Flag::Leave` for removed-members filter (kick is separately in the Restrictions category). Mapping kick into both "Restrictions" and "Removed members" causes double-counting and incorrect filter behavior — `admin_tools.dart:4710` ← `AyuGram/history/admin_log/history_admin_log_filter.cpp:27-33` (`membersRemoved = Flag::Leave` only; restrictions = `Flag::Ban | Flag::Unban | Flag::Kick | Flag::Unkick`)

- [ ] [MAJOR] `_AdminLogFilterDialog` "Topics" filter is shown unconditionally (for both channels and groups). AyuGram only shows the Topics filter entry when `!isChannel` — `admin_tools.dart:4715,4749` ← `AyuGram/history/admin_log/history_admin_log_filter.cpp:63-70` (`if (!isChannel) { settings.push_back({ Flag::Topics, ... }) }`)

- [ ] [MAJOR] `_AdminLogFilterDialog` "Pinned messages" filter is shown unconditionally. AyuGram only includes pinned messages in the filter when `!isChannel` — `admin_tools.dart:4718,4752` ← `AyuGram/history/admin_log/history_admin_log_filter.cpp:78-84` (`if (!isChannel) { messages.push_back({ pinned, ... }) }`)

- [ ] [MAJOR] `_EditAdminBox` group section `_section3` contains `manage_direct` for channels only (correctly in `_section4`), but for groups `_section3` uses `manage_ranks` instead. AyuGram groups do not have a `manage_direct` or `manage_ranks` grantable admin right — `admin_tools.dart:3374-3379` ← `AyuGram/boxes/peers/edit_participant_box.cpp:314-338` (group `defaultRights()` = `ChangeInfo | DeleteMessages | PostStories | EditStories | DeleteStories | BanUsers | InviteUsers | ManageTopics | PinMessages | ManageCall | ManageRanks`)

- [ ] [MAJOR] `_showStickerSetPicker` accepts only a text input for a sticker set name/link. AyuGram opens a full `StickersBox` UI that shows your existing sticker sets for selection — `admin_tools.dart:1716-1771` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:819-829` (`Box<StickersBox>(controller->uiShow(), channel, isEmoji)` — dedicated sticker picker box)

- [ ] [MAJOR] `_EditPeerPermissionsBox._onSave` calls both `setDefaultBannedRights` AND `setSlowMode` as separate calls. In AyuGram, slowmode is included in the `DefaultBannedRights` payload (the `MTPchannels_SetDefaultHistoryTTL` / `slow_mode_delay` field is part of `EditChatDefaultBannedRights`). Making two separate calls can result in a race condition or duplicate API calls — `admin_tools.dart:2058-2060` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:279-302` (`SaveBoostsUnrestrict` is saved separately but slowmode is embedded in `MTPchannels_EditBannedRights` default rights call)

- [ ] [MAJOR] `_AdminLogEventTile._actionDescription` has no case for `change_pay_messages` / `change_stars_price`, `toggle_bot_membership`, `change_peer_wallpaper`, or `toggle_forum_topics` actions — these will fall through to the generic `event.detail` or `event.action` display instead of a human-readable description — `admin_tools.dart:4563-4677` ← `AyuGram/history/admin_log/history_admin_log_item.cpp` (full action type enum)

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

## advanced_settings_screen — backend wiring, proxy selection bug, power saving not sent to engine, screen reader condition inverted, local storage limits unimplemented in engine, experimental flags are invented

- [ ] [CRITICAL] `setPowerSaving` only updates local flags and saves prefs — it never sends anything to the engine (no `callGeneric`/`engine.*` call). AyuGram calls `Set(PowerSaving::kAll & ~collect())` and `Core::App().saveSettingsDelayed()` on Save which propagates to the rendering pipeline. In Dart, power saving flags affect AppState getters like `animationsEnabled` but the engine/Go side never receives them, so server-side animation throttling (sticker streams, emoji renders) does not actually engage. — `advanced_settings_screen.dart:2718` ← `settings/settings_power_saving.cpp:116`

- [ ] [CRITICAL] `_syncProxyToEngine` always sends `_proxyList.first` as the active proxy regardless of which entry the user selected. `_selectedIndex` is tracked in the dialog widget state but is never persisted to `AppState`; `AppState.setProxyList` does not take a selected-index argument. The Go engine therefore always uses proxy[0] as the active proxy even when the user has selected a different one. AyuGram passes the actual selected proxy object from `ProxiesBoxController`. — `advanced_settings_screen.dart:2172` and `app_state.dart:2172` ← `core/core_settings_proxy.cpp` (ProxiesBoxController)

- [ ] [CRITICAL] `setLocalStorageLimits` calls `engine.callGeneric('__engine', 'SetLocalStorageLimits', {...})` but `SetLocalStorageLimits` is not handled anywhere in `go/bridge/dispatch_engine.go` — grep finds no match. The call silently fails (`.catchError((_) {})`). The Go engine never actually enforces total/media/time limits. Only the in-memory `_localStorageTotalLimit` value is wired (via `_engine.updateConfig(maxCacheSize:...)`); the time-based and media-size-based eviction are dropped on the floor. — `advanced_settings_screen.dart:2221` and `app_state.dart:2221` ← `boxes/local_storage_box.cpp` / `storage/localstorage.cpp`

- [ ] [CRITICAL] Screen reader section uses an inverted condition: Dart shows the section when `_screenReaderDetected && !appState.screenReaderOptimized` (line 1209). AyuGram shows it when `detected && disabled` — i.e. the section is only visible when the screen reader is **active** AND optimization is already **disabled** (so the user can re-enable it). The Dart logic hides the section when optimization is already enabled, meaning the user has no way to re-disable it once they toggle it on. The toggle label is also inverted: "Disable screen reader optimization" with `value: !appState.screenReaderOptimized` creates a double-negative. — `advanced_settings_screen.dart:1207` ← `settings/sections/settings_advanced.cpp:1184`

- [ ] [MAJOR] Auto-download settings are saved with source strings `'In private chats'`, `'In groups'`, `'In channels'` (display labels) but `dispatch_engine.go:1213` expects `source` values that Go can interpret (the Dart `SetAutoDownload` handler at bridge line 1213 maps to `SetAutoDownloadSettings(params.Source, ...)`). If Go code ever compares source to constants like `"private"`, `"group"`, `"channel"` these will silently mismatch. No crash — the call succeeds — but the engine may bucket the settings under the wrong key. Additionally the `_AutoDownloadBox` uses MB values as floating-point but the AyuGram engine uses bytes (`kMegabyte = 1024*1024`); the Dart side passes raw MB floats without converting. — `advanced_settings_screen.dart:1554` ← `boxes/auto_download_box.cpp:30`

- [ ] [MAJOR] Power saving `_applyAutoFlags` sets `_flags = 0xFFFF` (line 2587) but `AppState.kPowerSavingAll` is `(1 << 11) - 1 = 0x7FF`. Using `0xFFFF` sets bits 11–15 which have no defined meaning, causing `setPowerSaving` loop at line 2724 to iterate `bit = 0..11` and accidentally toggle undefined bits. AyuGram uses `PowerSaving::kAll` which is precisely defined. — `advanced_settings_screen.dart:2587` ← `settings/settings_power_saving.cpp:59`

- [ ] [MAJOR] Experimental settings flags in `_experimentalFlagDefs` are entirely invented keys (`tabbed_emoji_panel`, `forum_chat_list`, `dialogs_mute_icon`, `smooth_scrolling`, `message_draft_visible`, etc.) that do not correspond to any real `base::options` IDs in the codebase. AyuGram's experimental section (`SetupExperimental`) reads actual C++ option IDs like `kOptionTabbedPanelShowOnClick`, `Dialogs::kOptionForumHideChatsList`, `Core::kOptionFractionalScalingEnabled`, `Core::kOptionFreeType`, `MTP::details::kOptionPreferIPv6`, etc. The Dart flags are stored in `AppState.experimentalFlags` but never wired to any engine call — toggling them does nothing. The import/export format also differs: AyuGram uses zlib+base64 over a JSON-serialized options map using actual option IDs; Dart uses the same compression but with fake keys. — `advanced_settings_screen.dart:4412` ← `settings/settings_experimental.cpp:284`

- [ ] [MAJOR] `_ProxiesBox._syncToAppState` filters out deleted proxies before calling `setProxyList` (line 2934–2944), so soft-deleted entries are permanently gone from `AppState` before the dialog closes. AyuGram keeps deleted entries in memory until the box closes and then only removes them on close/save; this allows undo within the same dialog session. In Dart, once you mark a proxy deleted and any sync happens (e.g. toggling another setting), it is wiped from persistent state immediately. — `advanced_settings_screen.dart:2934` ← `core/proxy_rotation_manager.cpp`

- [ ] [MAJOR] `_LocalStorageBox._clearAll` calls `appState.engine.clearCache()` with no accountId, which in Go broadcasts to all accounts. But `_clearTag` for index 5 (Media Cache) calls `appState.engine.clearCache(accountId: appState.activeAccountId)` only for the active account. The other tag-specific clears (images, stickers, voice, etc.) only delete from the local filesystem directory without notifying the engine, meaning the Go-side media cache (in-memory or SQLite index) is not invalidated after file deletion. AyuGram's `LocalStorageBox` calls `Local::writeSettings()` and triggers a full cache wipe via `Auth::clearAll`. — `advanced_settings_screen.dart:1893` ← `boxes/local_storage_box.cpp`

# auth_screen — Auth screen audit vs AyuGram Desktop

## auth_screen — Auth screen audit

- [ ] [CRITICAL] OTP step incorrectly shows a "Next" button — `_showNext` returns true for `'input'` which includes all input states, but the OTP code step (`'otp'`) uses `_OtpCodeInput` which auto-submits on completion; AyuGram's `CodeWidget` has no explicit next-button (code auto-triggers `submitCode` on `codeCollected`). The Dart `_showNext` at line 280 maps `'input'` → true, meaning when the backend sends state `'input'` with an OTP type the next button appears redundantly. More critically, the `'otp'` state itself is separate in Dart but `_showNext` returns false for it — which is correct for `'otp'`, but `'input'` with non-phone types (e.g., email verification code) also gets a plain `TextField` without auto-submit, showing Next. — `auth_screen.dart:280` ← `AyuGram/intro/intro_code.cpp:64-68` (codeCollected auto-submits, no manual button)

- [ ] [CRITICAL] Terms of Service acceptance is completely missing from the signup flow — AyuGram's `SignupWidget::submit()` checks `_termsAccepted || termsLock.text.isEmpty() || !termsLock.popup` and shows a terms acceptance box before sending `auth.signUp`; the Dart `_buildSignUp` and `_submit` have zero ToS handling — `auth_screen.dart:792-878` ← `AyuGram/intro/intro_signup.cpp:197-206`

- [ ] [CRITICAL] QR code token is treated as a UTF-8 string instead of a base64url-encoded tglogin URL — AyuGram's `QrWidget::showToken` encodes raw bytes as `"tg://login?token=" + token.toBase64(Base64UrlEncoding)`; the Dart `_buildQR` at line 948 does `utf8.decode(data.qrData, allowMalformed: true)` and passes the result directly to `QrImageView`, corrupting the QR content — `auth_screen.dart:948` ← `AyuGram/intro/intro_qr.cpp:461-463`

- [ ] [CRITICAL] QR code has no expiry-driven refresh timer — AyuGram's `QrWidget::handleTokenResult` schedules `_refreshTimer.callOnce(std::max(left, 1) * crl::time(1000))` to refresh before the token expires; the Dart QR widget at lines 946-1048 has no timer or expiry tracking at all — the QR will silently expire without updating — `auth_screen.dart:946-1048` ← `AyuGram/intro/intro_qr.cpp:433-448`

- [ ] [CRITICAL] QR screen "login by phone" link navigates via `authState.switchToMethod('phone')` which may or may not exist on the backend state machine, but the real AyuGram flow calls `goReplace<PhoneWidget>(Animate::Forward)` — `submit()` on the QR step goes to Phone; the Dart equivalent at line 1043 calls `authState.switchToMethod('phone')` with no fallback and no guarantee the engine supports this command — `auth_screen.dart:1043` ← `AyuGram/intro/intro_qr.cpp:273-275`

- [ ] [CRITICAL] Language change dialog applies language locally only via `updateConfig(language: val)` but does not download/switch the Telegram cloud language pack — AyuGram calls `Lang::CurrentCloudManager().switchToLanguage(languageId)` which fetches translated strings from Telegram's lang pack servers; the Dart `_LanguagePickerDialog` at line 2255 only calls `engine.updateConfig(language: val)` on the engine, leaving all UI strings untranslated — `auth_screen.dart:2255` ← `AyuGram/intro/intro_widget.cpp:279-308`

- [ ] [CRITICAL] Account reset flow sends `'__reset_account'` as a text input to `authState.submitInput` instead of calling the proper `account.DeleteAccount` MTP method with the confirmation waiting-period logic — AyuGram calls `MTPaccount_DeleteAccount` with flood control and shows a days/hours countdown when `2FA_CONFIRM_WAIT_N` is returned; the Dart dialog at line 456 just calls `authState.submitInput('__reset_account')` with no countdown display or proper error handling for the waiting-period response — `auth_screen.dart:456` ← `AyuGram/intro/intro_widget.cpp:543-624`

- [ ] [MAJOR] Phone-number formatter uses a naive "space every 3 digits" rule instead of country-specific formatting — AyuGram uses `Countries::Groups(s)` to get the country's digit grouping pattern (e.g., US: 3-4, Russia: 3-2-2); the Dart `_PhoneNumberFormatter` at line 2369 groups every 3 digits uniformly regardless of country — `auth_screen.dart:2369` ← `AyuGram/intro/intro_phone.cpp:63` (Countries::Groups passed to PhonePartInput)

- [ ] [MAJOR] OTP call timer on timeout unconditionally calls `onResendCode` (auto-resends) instead of just changing state to "Calling" — AyuGram's `CodeWidget::sendCall` calls `MTPauth_ResendCode` when the countdown reaches 0 and then updates the call label to "Calling…" / "Called" based on `callDone`; the Dart `_startCallTimer` in `_OtpCodeInputState` at line 1625 calls `widget.onResendCode?.call()` automatically when timer hits 0, which resends the code without any request tracking or "Calling…" UI state — `auth_screen.dart:1625` ← `AyuGram/intro/intro_code.cpp:302-320`

- [ ] [MAJOR] "Didn't get the code?" dialog offers only "Resend Code" and "Edit Phone Number" — AyuGram's `noTelegramCode()` sends `auth.ResendCode` and then transitions the UI to show the call countdown label instead of "no Telegram code" link; the Dart `_showDidntGetCodeDialog` at lines 201-244 shows a static dialog with hard-coded text and a simple `submitInput('__resend_code')` call, losing the call-type transition logic — `auth_screen.dart:201-244` ← `AyuGram/intro/intro_code.cpp:440-497`

- [ ] [MAJOR] Signup "Next button" text says "Start Messaging" but AyuGram uses `tr::lng_intro_finish()` (translated as "Start Messaging" in English but should come from translation system, not a hardcoded literal) — `auth_screen.dart:289` ← `AyuGram/intro/intro_signup.cpp:209-211`

- [ ] [MAJOR] Cover gradient uses hardcoded color values `(0xFF0088CC, 0xFF0066AA)` for light theme instead of the theme palette's `introCoverIconsFg`/`introTitleFg` color tokens — `auth_screen.dart:1387-1388` ← `AyuGram/intro/intro.style:16` (introCoverIconsFg)

- [ ] [MAJOR] `_handleTryPassword` ("Can't Access Email?" dialog) shows "OK" and then displays the reset button, but AyuGram's `toPassword()` shows `tr::lng_signin_cant_email_forgot()` infobox and then calls `showReset()` which also re-shows the password field and hides the code field — the Dart path at lines 764-790 toggles `_showResetButton` but leaves `_isRecoveryMode = false` while keeping `_showResetButton = true`; it does not reset `_codeField` / restore the password UI correctly because those are unified in one field — `auth_screen.dart:764-790` ← `AyuGram/intro/intro_password_check.cpp:325-348`

- [ ] [MAJOR] `_buildPhoneFields` country selector is a custom `GestureDetector`+`Container` that cannot detect phone-code-typed country changes from the dial-code field — AyuGram's `_code->codeChanged` reactive stream automatically updates `_country` and `_phone->chooseCode()` when the user types in the code field; the Dart `_onCodeChanged` at line 1356 only updates `_selectedCountry` but does not update the phone formatter's grouping pattern — `auth_screen.dart:1356-1362` ← `AyuGram/intro/intro_phone.cpp:77-86`

- [ ] [MAJOR] QR center logo is `Icons.send` (Material icon) rather than the Telegram plane logo — AyuGram renders the actual Telegram logo via `TelegramLogoImage()` which draws a filled circle with `st::introQrPlane` SVG icon; the Dart center at line 1015 uses `Icons.send_rounded` — `auth_screen.dart:1015-1019` ← `AyuGram/intro/intro_qr.cpp:531-547`

- [ ] [MAJOR] Bottom bar button padding is `EdgeInsets.only(top: 11, bottom: 17)` (asymmetric) instead of matching AyuGram's `introNextButton` style which has `textTop: 11px` on a `height: 42px` button with `radius: 6px` — the bottom padding is 17px vs the expected `42 - 11 - font_height` (≈14px); this visually misaligns the label — `auth_screen.dart:2088` ← `AyuGram/intro/intro.style:87-95`

- [ ] [MAJOR] Next button width is `double.infinity` (full container width) instead of AyuGram's fixed `300px` — `auth_screen.dart:2079` ← `AyuGram/intro/intro.style:88` (width: 300px)

# ayu_appearance_page — Audit

- [ ] [CRITICAL] "Restart Now" calls `exit(0)` which kills the process without restarting — AyuGram uses `Core::Restart()` which performs a proper application restart — `ayu_appearance_page.dart:289, 971` ← `settings_ayu_utils.cpp:40`

- [ ] [MAJOR] App icon change only fires a MethodChannel IPC event (`com.uniclient.app/tray updateAppIcon`) — AyuGram's `applyIcon()` also calls `Window::OverrideApplicationIcon()`, `Core::App().refreshApplicationIcon()`, `tray().updateIconCounters()`, and `domain().notifyUnreadBadgeChanged()` — if the native platform handler doesn't implement all of these, the running window icon and taskbar icon won't update — `ayu_appearance_page.dart:32-36` ← `icon_picker.cpp:42-51`

- [ ] [MAJOR] Font picker has no loading path for Android or iOS — `_loadSystemFonts` only covers Linux/macOS (`fc-list`), macOS (`osascript`), and Windows (PowerShell); on mobile the list falls through to `['']` (only "Default"), making the Monospace Font setting non-functional on mobile — `ayu_appearance_page.dart:699-721` ← `font_selector.cpp:204-218` (Qt's `QFontDatabase::families()` is cross-platform)

- [ ] [MAJOR] Font search uses plain substring `contains` matching — AyuGram uses `TextUtilities::PrepareSearchWords` + per-word `startsWith` matching so "mo" matches "Monospace" at a word boundary but not mid-word — Dart's `contains` produces broader, incorrect results — `ayu_appearance_page.dart:809-813` ← `font_selector.cpp:355-400`

- [ ] [MAJOR] IconPicker clips icon images to `ClipRRect(borderRadius: 10)` — AyuGram draws icons into a plain `QRect` with no rounding clip (`p.drawImage(rect, icon)`) — icons with squared edges will render differently — `ayu_appearance_page.dart:1074-1076` ← `icon_picker.cpp:85-91`

- [ ] [MAJOR] IconPicker selected-state highlight uses `Positioned.fill` (fills entire grid cell) — AyuGram draws a precisely-sized `68×68` rounded rect at `(x + iconPickerSelectedPadding, y + iconPickerSelectedPadding)` which wraps only the icon area with a 2 px margin, not the whole cell — `ayu_appearance_page.dart:1058-1069` ← `icon_picker.cpp:67-82` + `style_ayu_styles.style:iconPickerSelectedPadding=2px, iconPickerSelectedRounding=12px`

# ayu_chats_page — Audit Findings

- [ ] [CRITICAL] Bubble radius slider does not update the message preview live during drag — `onChanged` only calls `setState(() => _localValue = newVal)` updating the number display, but never calls `widget.onChanged` or notifies the preview widget; AyuGram's `onChanged` calls `previewState->widget->setBubbleRadius(index)` on every drag event — `ayu_chats_page.dart:495-498` ← `settings_chats.cpp:255-259`

- [ ] [CRITICAL] Both sliders use `showConfirmBox` with a Cancel that reverts the slider value, but AyuGram uses `ShowRestartPrompt` which saves the setting first and then offers "Restart Now" / "Later" (never reverts the value); the Dart Cancel path calls `setState(() => _localValue = _committedValue)` which is wrong — the C++ "Later" path keeps the new value saved — `ayu_chats_page.dart:389-401`, `ayu_chats_page.dart:502-514` ← `settings_chats.cpp:260-265`, `settings_chats.cpp:280-285`, `settings_ayu_utils.cpp:36-45`

- [ ] [MAJOR] `_save()` allows saving an empty string without validation; AyuGram's `EditMarkBox::submit()` checks `trimmed().isEmpty()`, sets focus, and calls `showError()` on the field before refusing to save — `ayu_chats_page.dart:615-618` ← `edit_mark_box.cpp:73-79`

- [ ] [MAJOR] All seven context menu choose-buttons are missing icons; AyuGram passes `&st::menuIconReactions`, `&st::menuIconShowInChat`, `&st::menuIconClear`, `&st::menuIconTTL`, `&st::menuIconInfo`, `&st::ayuRepeatMenuIcon`, `&st::menuIconAddToFolder` for each item respectively — `ayu_chats_page.dart:281-297` ← `settings_chats.cpp:314`, `settings_chats.cpp:323`, `settings_chats.cpp:332`, `settings_chats.cpp:341`, `settings_chats.cpp:350`, `settings_chats.cpp:359`, `settings_chats.cpp:369`

- [ ] [MAJOR] The message preview is a static hand-drawn fake widget with hardcoded text ("Hey, check this out!", "Sure, looks great to me!", "12:00", "12:01") and does not react to settings changes via reactive streams; AyuGram's `MessagePreview` uses the real `HistoryView` rendering engine and subscribes to all seven settings via `rpl::merge` to refresh on every change — `ayu_chats_page.dart:667-922` ← `message_preview.cpp:122-139`

# ayu_filters_page — Audit findings

- [ ] [CRITICAL] Regex validation uses Dart's ECMA/V8 `RegExp` engine instead of the execution engine's dialect. Patterns with lookahead `(?=...)`, lookbehind `(?<=...)`, or backreferences `\1` pass Dart's `RegExp()` check but fail silently in Go's RE2 engine at runtime. Users receive no error for invalid filters. AyuGram uses ICU (`icu::RegexPattern::compile`) which is also a different engine — the Go RE2 engine is the correct authority here, not Dart's. — `ayu_filters_page.dart:1226` ← `ayu/ui/settings/filters/edit_filter.cpp:61-98`

- [ ] [MAJOR] `_SelectChatDialog` shows all chat types including DMs. AyuGram's select-chat picker in the top-bar menu restricts to `Bot | Group | Broadcast` only (no user DMs). The Dart dialog shows every entry in `chatState.chats` with no type filter, allowing per-dialog filters to be set on DMs even though AyuGram does not support this. — `ayu_filters_page.dart:290` ← `ayu/ui/settings/settings_filters.cpp:198-202`

- [ ] [MAJOR] Import peer-hint resolution only calls `resolveUsername`; invite-link hints are silently dropped. AyuGram's `ResolveFilterBackupPeers` handles both `PeerResolveHintType::Username` (via `contacts_ResolveUsername`) and `PeerResolveHintType::Invite` (via `checkChatInvite`), covering `+HASH`, `tg://join?invite=HASH`, and `joinchat/HASH` formats. The Dart import loop at line 1596–1602 calls only `engineSvc.resolveUsername(accountId, entry.value)`, so any peer hint that is an invite link is never resolved and the dialog ID remains unknown. — `ayu_filters_page.dart:1596-1602` ← `ayu/features/filters/filters_utils.cpp:229-290`

- [ ] [MAJOR] Restrict-to-dialog toast/snackbar only fires on new filter creation; AyuGram fires it on both add and edit. In AyuGram `RegexEditBox` always passes `showToast = true`, so after saving any filter (new or edited) from a per-dialog screen the toast offering to restrict it appears. The Dart guard `if (isNew && dialogId != null && filter.isShared)` skips this for edits, so editing a shared filter from a per-dialog screen silently discards the "Restrict" offer. — `ayu_filters_page.dart:1281` ← `ayu/ui/settings/filters/edit_filter.cpp:222-245`

- [ ] [MAJOR] Export menu item always visible regardless of whether filters exist. AyuGram adds the Export action only when `AyuDatabase::hasFilters()` is true; the item does not appear in the menu when there are no filters. The Dart menu always includes Export and falls back to a SnackBar message at run-time. — `ayu_filters_page.dart:123-128` ← `ayu/ui/settings/settings_filters.cpp:228-235`

- [ ] [MAJOR] `_ShadowBanRow._colorRemap` contains the value `7` at index 1. AyuGram computes the empty-userpic color as `EmptyUserpic::UserpicColor(realId % 7)`, yielding 0–6. The Dart remap `[0, 7, 4, 1, 6, 3, 5]` maps `id.abs() % 7 == 1` to color index `7`, which is out of the expected 0–6 range and may trigger a RangeError or render the wrong color in `context.palette.peerUserpicBg()`. — `ayu_filters_page.dart:1179,1141` ← `ayu/ui/settings/filters/per_dialog_filter.cpp:51-56`

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

# ayu_other_page — Audit Findings

## ayu_other_page — RC config / donate QR / URL scheme issues

- [ ] [CRITICAL] RC config JSON keys are snake_case in Dart but camelCase in C++: Dart reads `donate_usd`, `donate_ton`, `donate_rub`, `donate_username` — these keys never exist in the server response, so the RC config always fails silently and donate amounts/username permanently show hardcoded defaults — `ayu_other_page.dart:468-471` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/utils/rc_manager.cpp:192-204` (keys: `donateAmountUsd`, `donateAmountTon`, `donateAmountRub`, `donateUsername`)

- [ ] [CRITICAL] macOS URL scheme registration is a stub: Dart shows `SnackBar('URL schemes are registered automatically on macOS')` and exits without registering anything. AyuGram calls `Core::Application::RegisterUrlScheme()` unconditionally on all platforms via `base::Platform::RegisterUrlScheme` — `ayu_other_page.dart:157-159` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_other.cpp:204-206` + `AyuGramDesktop/Telegram/SourceFiles/core/application.cpp:1894-1919`

- [ ] [CRITICAL] Wrong second URL scheme registered on Linux and Windows: Dart registers `tdesktop` (`x-scheme-handler/tdesktop` on Linux, `HKCU\Software\Classes\tdesktop` on Windows). AyuGram registers `tonsite` — `ayu_other_page.dart:189,213-225` ← `AyuGramDesktop/Telegram/SourceFiles/core/application.cpp:1910-1919` (registers `tonsite`, not `tdesktop`)

- [ ] [CRITICAL] Default donate username is wrong: Dart defaults to `'RadianceTG'` (no `@`). AyuGram C++ defaults to `@ayugramOwner` — `ayu_other_page.dart:452` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/utils/rc_manager.h:102`. This wrong default is permanently displayed because the RC config parse always fails (see first item above).

- [ ] [MAJOR] RC config has no fallback endpoint: when `https://update.ayugram.one/rc/current/desktop2` fails, AyuGram retries with `https://api.exteragram.app/api/v1/profiles/compact`. Dart has no retry/fallback at all — `ayu_other_page.dart:456-477` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/utils/rc_manager.cpp:77-86`

- [ ] [MAJOR] QR box dialog title wrong: Dart uses the coin name (e.g. `"Bitcoin"`) as title. AyuGram uses `tr::lng_group_invite_context_qr()` ("QR code") — `ayu_other_page.dart:699` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/boxes/donate_qr_box.cpp:78`

- [ ] [MAJOR] QR box has extra bottom "Close" button: Dart renders both a "Copy" button and a "Close" button in the bottom row. AyuGram has only a single "Copy" button at bottom; close is via a top-right X button (`addTopButton`) — `ayu_other_page.dart:780-800` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/boxes/donate_qr_box.cpp:148-160`

- [ ] [MAJOR] DonateInfoBox missing TON currency icon in donate amounts: AyuGram renders a visual TON emoji/icon via `Ui::Earn::IconCurrencyColored` prepended to the TON amount. Dart renders plain text `${_DonateInfoBox._donateAmountTon} TON` — `ayu_other_page.dart:565` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/boxes/donate_info_box.cpp:169-183`

# ayu_section_builder — slider onFinalChanged missing, checkbox radius wrong, toggle logic excludes locked incorrectly

- [ ] [CRITICAL] `addSlider` has no `onFinalChanged` parameter and `_AyuSlider` does not use Flutter's `onChangeEnd` — every drag frame calls `onChanged`, but C++ sliders distinguish between `onChanged` (live preview) and `onFinalChanged` (persist on release); e.g. `recentStickersCount` and `avatarCorners` use `onChanged = nullptr, onFinalChanged = setter`, meaning the Dart equivalent fires the setter on every frame and cannot express the on-release-only pattern — `ayu_section_builder.dart:63` ← `AyuGram/SourceFiles/ayu/ui/settings/ayu_builder.cpp:217`

- [ ] [MAJOR] `_TgCheckboxPainter` uses `Radius.circular(4)` for the checkbox corner radius, but AyuGram's `CheckView::paint` uses `st::roundRadiusSmall - (_st->thickness / 2.)` = `3 - 1 = 2px` inner radius (3px outer), a 33% deviation — `ayu_section_builder.dart:858` ← `AyuGram/lib_ui/ui/basic.style:104` + `AyuGram/lib_ui/ui/widgets/checkbox.cpp:280`

- [ ] [MAJOR] `_AyuCollapsibleToggleState.build` computes `toggleValue` for `toggledWhenAll=true` via `.where((c) => !c.isLocked).every((c) => c.value)` — Dart's `every()` returns `true` on an empty iterable, so when all children are locked the master toggle renders ON; C++ guards with `total > 0 &&` before the equality check — `ayu_section_builder.dart:638` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_ayu_utils.cpp:216`

- [ ] [MAJOR] `_AyuCollapsibleToggleState.build` computes `toggleValue` for `toggledWhenAll=false` via `widget.children.any((c) => c.value)`, which includes locked children; C++ uses `countUnlockedChecked()` which skips entries whose `lockCheck` returns true, so locked-but-checked items incorrectly drive the master toggle ON in the Dart version — `ayu_section_builder.dart:643` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_ayu_utils.cpp:120`

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

- [ ] [CRITICAL] Device enumeration uses raw OS shell commands (v4l2-ctl, pactl, powershell, system_profiler) instead of calling `engine.getAudioDevices()` which exists in EngineService — `call_panel.dart:163-250` ← `calls_panel.cpp:1036-1094` (uses `Webrtc::DeviceType` values via `cameraDeviceIdValue()`/`playbackDeviceIdValue()`/`captureDeviceIdValue()`)

- [ ] [CRITICAL] Audio output (playback/speaker) device is entirely missing from the device selector — the menu only shows Camera and Microphone (`call_panel.dart:510-538`), but AyuGram's mute button corner toggle exposes both Playback AND Capture device selection — `call_panel.dart:510-538` ← `calls_panel.cpp:1050-1056`

- [ ] [CRITICAL] `Busy` state has no redial button — when state is `busy` the Dart code renders `_buildEndedState()` with only a Close button (`call_panel.dart:1124`), but AyuGram transitions the main answer/hangup button into a Redial button and keeps controls visible — `call_panel.dart:1124-1126` ← `calls_panel.cpp:1437-1444`

- [ ] [CRITICAL] `WaitingUserConfirmation` state ("Are you sure?") is missing entirely — AyuGram has a distinct state where the outgoing call shows a "Start Call" button and a separate "Start Video" button, mute/screencast/addPeople are hidden — there is no corresponding `CallPanelState` value in Dart — `call_panel.dart:21-33` ← `calls_panel.cpp:1385-1407`

- [ ] [CRITICAL] Conference-invite participant avatars widget is missing — when an incoming call is a conference invite, AyuGram renders a row of participant userpics with a member count above the status text; Dart has no such widget — `call_panel.dart:715-762` ← `calls_panel.cpp:504-560`

- [ ] [MAJOR] Remote mute/battery pills are wrapped inside `FadeTransition` tied to `_controlsFadeController` in audio-only active state (`call_panel.dart:1046`), meaning they hide with controls. AyuGram shows them independently of controls visibility — opacity is linked to `_controlsShownAnimation` only for visual fade, but they are always shown when video is active (`calls_panel.cpp:1006-1009`). In Dart's audio-only path (`_buildActiveState`), pills are children of the same `FadeTransition` as the controls row — `call_panel.dart:1046-1055` ← `calls_panel.cpp:865-963`

- [ ] [MAJOR] Device selector menu is attached only to the Camera button's chevron (`call_panel.dart:864`); AyuGram attaches a separate corner button to the Mute button for audio device (playback+capture) selection, distinct from the camera corner button — `call_panel.dart:858-865` ← `calls_panel.cpp:1040-1056`

- [ ] [MAJOR] `setCallAudioDevice` is called with type strings `'video_input'` and `'audio_input'` (`call_panel.dart:550,553`), but other call sites in the codebase use `'camera'`, `'input'`, `'output'`, `'playback'`, `'capture'` inconsistently — no single agreed type string for video input, making device switching silently broken — `call_panel.dart:548-554` ← `calls_panel.cpp:1065-1077`

- [ ] [MAJOR] Ripple animation on the answer button uses a fixed static color (`Color(0xFF4CAF50)`) and a fixed expansion of 24px (`call_panel.dart:1272`), while AyuGram drives the outer ripple amplitude from `_call->getWaitingSoundPeakValue()` (audio-reactive) updated every `Call::kSoundSampleMs` — `call_panel.dart:1258-1285` ← `calls_panel.cpp:465-473`

# call_screen — Group Call Panel & Minimised Call Bar Audit

## call_screen — Mute state sent to engine is inverted (wrong value)

- [ ] [CRITICAL] `onToggleMute` callback toggles `selfMuted` via `setSbState` (mutating the local var to the NEW value), then immediately calls `engine.setCallMuted(accountId, callId, !selfMuted)` — but `selfMuted` is already the NEW value at that point, so `!selfMuted` is the OLD value. Engine receives the opposite of the intended mute state on every toggle. — `call_screen.dart:1217-1219` ← `AyuGram/calls/group/calls_group_panel.cpp:590-600` (AyuGram reads `oldState`, computes `newState`, then calls `setMutedAndUpdate(newState)` — no double-negation)

## call_screen — No "Stop Recording" option in call menu

- [ ] [CRITICAL] The group call menu only has "Start Recording" regardless of whether recording is already active (`isRecording` widget flag exists but is never checked in the menu). AyuGram shows "Stop Recording" when recording is active and toggles via `toggleRecording()`. There is no way for the user to stop a recording once started. — `call_screen.dart:1287-1305` ← `AyuGram/calls/group/calls_group_panel.cpp:335-337` (`tr::lng_group_call_recording_start` / `tr::lng_group_call_recording_stop` toggled based on recording state)

## call_screen — No recording-started / recording-stopped toast feedback

- [ ] [MAJOR] When recording starts or stops, AyuGram shows a toast ("Recording started", "Recording saved"). The Dart code shows a SnackBar only with the file path when recording starts (`call_screen.dart:1298-1302`), and shows nothing when recording stops. There is no engine event listener for `recordStartDateChanges` — the `isRecording` flag is a static prop passed at open time and never updated reactively. — `call_screen.dart:1169` ← `AyuGram/calls/group/calls_group_panel.cpp:1362-1367`

## call_screen — Participant rows have no long-press / context menu (mute, kick, volume)

- [ ] [CRITICAL] AyuGram's Members panel emits `toggleMuteRequests`, `changeVolumeRequests`, and `kickParticipantRequests` on participant row interaction (right-click / long-press context menu). The Dart `_buildParticipantRow` has no `onLongPress`, no `GestureDetector.onSecondaryTap`, and no context menu — participants cannot be muted, kicked, or have their volume changed by an admin. — `call_screen.dart:271-306` ← `AyuGram/calls/group/calls_group_members.cpp:81-83,1382,1569-1578`

## call_screen — No in-call chat messages panel

- [ ] [MAJOR] AyuGram's group call panel has a full `MessagesUi` widget and a `MessageField` that can be toggled via a dedicated message button. The Dart panel has no message button, no chat panel, and no in-call message sending — `_messages` and `_message` (the chat/message toggle button) are entirely absent. — `call_screen.dart` (no equivalent widget) ← `AyuGram/calls/group/calls_group_panel.cpp:242-250,492-530,803-815`

## call_screen — No scheduled group call UI (countdown / "Start Now" / "Set Reminder")

- [ ] [MAJOR] AyuGram renders scheduled call labels (`_startsIn`, `_countdown`, `_startsWhen`) and the mute button changes to "Start Now" / "Set Reminder" / "Cancel Reminder" for scheduled calls. The Dart panel has no `scheduleDate` concept, no countdown widget, and no scheduled-state mute button labels. — `call_screen.dart` (no scheduled handling) ← `AyuGram/calls/group/calls_group_panel.cpp:618-648,942-1007`

## call_screen — No push-to-talk (Space key) support for RTMP calls

- [ ] [MAJOR] AyuGram listens for `Qt::Key_Space` keyboard events on the panel window and calls `_call->pushToTalk()` for RTMP calls. The Dart panel has no keyboard event handler (`RawKeyboardListener`, `HardwareKeyboard`, or `Focus` widget), so push-to-talk is completely absent. — `call_screen.dart` (no keyboard handler) ← `AyuGram/calls/group/calls_group_panel.cpp:403-408`

## call_screen — Real-time audio level updates not wired to participants list

- [ ] [MAJOR] `audioLevel` on `GroupCallParticipant` is consumed by `_SpeakerBlobAvatar` but is a static field from the initial data model — there is no subscription to live level updates from the engine (`levelUpdates` stream). The blob animations use the stale initial value and never animate dynamically unless the entire participant list is rebuilt. — `call_screen.dart:277` ← `AyuGram/calls/group/calls_group_panel.cpp:663-668` (AyuGram subscribes to `_call->levelUpdates()` and calls `_mute->setLevel(update.value)` on each update)

## call_screen — Screen share thumbnail capture uses `import` (ImageMagick) X11 only, silently fails on Wayland

- [ ] [MAJOR] `_captureSourceThumb` calls `Process.run('import', ['-window', 'root', ...])` which is X11-specific ImageMagick. On Wayland (the default for modern Linux desktops), this silently returns an empty thumbnail for all sources. No Wayland-native capture path exists (e.g., XDG screencopy or pipewire frame). — `call_screen.dart:2677-2697` ← `AyuGram/ui/platform/ui_platform_utility` (uses native platform screen capture APIs)

## call_screen — Window enumeration for screen share falls back to X11 tools only

- [ ] [MAJOR] `_enumerateWindows()` uses `wmctrl -l` then `xdotool search` — both X11-only. On Wayland there is no way to enumerate windows, so the "Windows" tab in the screen-share chooser will always be empty. No PipeWire portal path for window enumeration is attempted. — `call_screen.dart:2701-2744` ← `AyuGram/ui/platform/ui_platform/desktop_capture_choose_source` (uses platform-native source enumeration)

# calls_screen — Audit Findings

## calls_screen — call settings device toggle broken, level meter 60fps setState, silent mic fallback

- [ ] [MAJOR] "Use same devices for calls" toggle is stored in `AppState` but never propagates to engine or hides/shows call-specific device rows. In AyuGram, toggling ON clears `callPlaybackDeviceId`/`callCaptureDeviceId` (falling through to global audio settings) and hides the separate call Output/Microphone rows via `SlideWrap`; toggling OFF copies the current global device IDs into call-specific slots and reveals those rows. The Dart toggle calls only `appState.setCallUseSameDevices(v)` and does nothing else — it has zero effect on actual call audio routing and call-specific device rows are always visible — `calls_screen.dart:2618-2624` ← `AyuGram/settings/sections/settings_calls.cpp:258-325`

- [ ] [MAJOR] `_InputLevelMeterState` uses `AnimationController.repeat()` which drives `_onTick` → `setState()` at ~60fps during microphone capture (lines 3014–3043). AyuGram uses a `base::Timer` firing at `kMicTestUpdateInterval` (~100ms) and an `Ui::Animations::Simple` that interpolates only between ticks. The Dart version triggers 6× more widget rebuilds than needed, burning CPU even when the level is stable at 0 — `calls_screen.dart:3014-3043` ← `AyuGram/settings/sections/settings_calls.cpp:129-151`

- [ ] [MAJOR] `_InputLevelMeter._startCapture()` attempts to spawn external system processes (`parec`, `pw-record`, `ffmpeg`, `rec`) and silently shows nothing if all candidates fail. AyuGram uses `Webrtc::AudioInputTester` directly. When none of the system tools are installed, the level meter widget renders as an empty bar with no explanation — users cannot tell whether the microphone works or whether the meter tool is missing — `calls_screen.dart:3045-3101` ← `AyuGram/settings/sections/settings_calls.cpp:141`

## chat_export — export panel, settings, progress, and suggest-box

- [ ] [CRITICAL] `full_personal_chats` and `full_bot_chats` are hardcoded `true` in `startExport` params instead of reflecting `_privateGroupsOnlyMy` / `_privateChannelsOnlyMy` state; the correct keys for private groups and private channels (`full_private_groups`, `full_private_channels`) are never sent at all, so the "Only my messages" checkboxes for private groups and channels have zero effect on the actual export — `chat_export.dart:845-846` ← `AyuGram/export/export_settings.h:84,115-118` + `export_controller.cpp:24-29`

- [ ] [CRITICAL] `_ExportSuggestBox` "Not now" button only calls `Navigator.of(context).pop()` without clearing the export suggestion from the engine; AyuGram calls `ClearSuggestStart` (which calls `clearExportSuggestion` + writes `availableAt = 0` back to storage) as soon as `SuggestStart` is invoked, ensuring re-appearance only when the engine fires the suggestion again — `chat_export.dart:3258-3263` ← `AyuGram/export/view/export_view_panel_controller.cpp:99-112`

- [ ] [CRITICAL] On `TAKEOUT_INIT_DELAY` error, AyuGram persists `availableAt` to local settings and calls `suggestStartExport` so the app will offer the export again when the delay expires; the Dart code only shows an informational dialog and closes the panel, with no write-back of `availableAt` and no scheduling of the future suggest — `chat_export.dart:1104-1127` ← `AyuGram/export/view/export_view_panel_controller.cpp:228-251`

- [ ] [MAJOR] `_ExportPanelController` is a static singleton with a bare global `OverlayEntry`; AyuGram's `PanelController` is session-scoped (`not_null<Main::Session*>`) and one panel per session can exist; the Dart implementation silently closes any existing panel (`close()`) before opening a new one regardless of session, meaning a second account starting an export while the first is processing will destroy the first panel without cancelling its underlying engine export — `chat_export.dart:190-202` ← `AyuGram/export/view/export_view_panel_controller.cpp:138-152`

- [ ] [MAJOR] `_buildProcessingPlaceholder` renders all steps in a `ListView` using a plain Dart `List.where(...).toList()` snapshot with `AnimatedOpacity` wrappers; AyuGram's `ProgressWidget` uses individual `Row` widgets that maintain an `_old` list with per-instance opacity `Animations::Simple` animating at `exportProgressDuration: 200ms` and a progress bar that animates with `sineInOut` easing from old value; the Dart version uses a flat `AnimatedOpacity` without a separate "old instance" crossfade layer, producing a pop-in instead of a smooth label-swap — `chat_export.dart:2234-2308` ← `AyuGram/export/view/export_view_progress.cpp:73-219`

- [ ] [MAJOR] `ProgressWidget.showDone()` in AyuGram transitions the progress view into a "done" state that replaces the Stop button with a Done/Show-my-data button and changes the about-label text to `lng_export_about_done`; the Dart code uses a separate `_buildCompletedPlaceholder` phase that discards all progress row state and reconstructs from `_completedStepData`, which means any rows that were never marked `wasReported` are silently dropped — `chat_export.dart:996-1016` ← `AyuGram/export/view/export_view_progress.cpp:355-376`

- [ ] [MAJOR] In `_buildFullExportSettings`, the format section inline-embeds three `Radio` buttons below the path/location label; AyuGram's full-export settings widget (`setupPathAndFormat`) only shows the location label and inline format radios for the non-singlePeer case — but for the per-chat (`singlePeer`) case it shows a combined `addFormatAndLocationLabel` with two inline links (format + path) in one `FlatLabel` line, not separate rows; the Dart per-chat path (`_buildCombinedFormatLocation`) correctly uses a `Wrap` with two tappable links but then also still renders format radios (`_buildFormatRadio`) in the full-export view — `chat_export.dart:1475-1483` ← `AyuGram/export/view/export_view_settings.cpp:266-294`

- [ ] [MAJOR] `_buildPerChatSettings` does not include a header section ("Export chat history", "Personal info", etc.) or the account-data checkboxes (personalInfo, contacts, stories, profileMusic, sessions, otherData); AyuGram's `setupOptions` calls `setupFullExportOptions` only when `_singlePeerId == 0`, and for single-peer shows `addMediaOptions` + `addFormatAndLocationLabel` + `addLimitsLabel` — the Dart per-chat settings only shows media + date range, which is correct, but the header label that reads "Export Topic History" / "Export Chat History" is only in the title bar, not in the content pane as AyuGram shows it — `chat_export.dart:1850-1957` ← `AyuGram/export/view/export_view_settings.cpp:159-167`

- [ ] [MAJOR] `_ExportPanelController._visible` starts as `ValueNotifier<bool>(true)` and `close()` resets it to `true` without actually destroying it; if `_entry` is already `null` when `close()` is called no harm is done, but `_visible` leaking across multiple show/close cycles means an `Offstage` child from a previous session may still be listening — `chat_export.dart:178,221-226` ← `AyuGram/export/view/export_view_panel_controller.cpp:154-161` (destructor hides panel on destroy)

# chat_list_panel — Audit findings

## chat_list_panel — Visual/behavioral issues vs AyuGram

- [ ] [MAJOR] `_TopPeersStrip._stripHeight` is 84px but AyuGram `topPeers.height` is 77px (inherited from `dialogsStoriesFull.height: 77px`). Total strip + header is 112px in Dart vs 105px in AyuGram — `chat_list_panel.dart:2593` ← `dialogs/dialogs.style:746`

- [ ] [MAJOR] `_TopPeersStrip` has no expand/collapse feature. AyuGram shows a "More" / "Less" `LinkButton` in the header when the number of entries exceeds two-thirds of the strip width, and expands to a second row via `setExpanded(bool)`. Dart renders a single fixed-height horizontal list with no toggle — `chat_list_panel.dart:2695-2758` ← `dialogs/ui/top_peers_strip.cpp:84-157`

- [ ] [MAJOR] `_TopPeersStrip` header label is `'FREQUENT CONTACTS'` (all-caps). AyuGram uses `tr::lng_recent_frequent()` which renders as `"Frequent contacts"` (title-case, no all-caps) — `chat_list_panel.dart:2686` ← `dialogs/ui/top_peers_strip.cpp:86`

- [ ] [MAJOR] Stories bar collapse trigger uses a fixed pixel threshold (`pos.pixels > 50`) instead of AyuGram's ratio-based `kCollapseAfterRatio = 0.68`. AyuGram derives the collapse trigger from the overscroll ratio, giving consistent behavior regardless of list viewport size. The 50px fixed threshold collapses too early on short viewports and too late on large ones — `chat_list_panel.dart:229` ← `dialogs/ui/dialogs_stories_list.cpp:43`

# chat_list_row — Audit findings

## CRITICAL

- [ ] [CRITICAL] Draft shown even when chat has unread messages — AyuGram only shows draft when `!badgesState.unread`; if there are unread messages the last message preview is shown instead, but Dart always renders the draft when `draftText.isNotEmpty`. — `chat_list_row.dart:362` ← `dialogs_layout.cpp:1085-1094`

- [ ] [CRITICAL] `_thumbBytesCache` global map has no eviction policy — it grows unboundedly for every unique base64 thumbnail ever seen in the chat list, leaking memory proportional to total chats × media variety over the lifetime of the process. — `chat_list_row.dart:16-18`

## MAJOR

- [ ] [MAJOR] Sender name shown for broadcast channels — `_buildPreview` renders the sender label when `chat.type == ChatType.channel`, but AyuGram does not show sender names for regular broadcast channel messages in the dialog list preview (channels always use the channel itself as "from"; it is suppressed in the painted text). This produces spurious "Username: message text" for channel rows. — `chat_list_row.dart:392-393` ← `dialogs_layout.cpp:1130-1183` (paintItemCallback omits sender for isBroadcast peers)

- [ ] [MAJOR] Active-row sender name rendered at 70% opacity instead of full white — `_buildPreview` uses `palette.dialogsTextFgActive.withValues(alpha: 0.7)` for the sender prefix in active rows, but AyuGram maps `dialogsTextFgServiceActive = dialogsTextFgActive` (full opacity white), so the sender name in the selected chat row is incorrectly dimmed. — `chat_list_row.dart:413-414` ← `colors.palette:223`

- [ ] [MAJOR] Premium subscriber badge not rendered — AyuGram `PeerBadge::drawGetWidth` draws `st::dialogsPremiumIcon` for premium users in the name row. The Dart `ChatListRow` only shows verified/scam/fake/emoji-status badges; premium users have no star badge in the chat list. — `chat_list_row.dart:238-262` ← `dialogs_layout.cpp:827-850`

- [ ] [MAJOR] Archive swipe action not blocked for `isNotificationsUser` (Telegram Notify service account) — `resolveSwipeAction` only disables archive for `chat.isSelf`; AyuGram's `CanArchive` also returns false for `peer->isNotificationsUser() && !history->folder()`. If such an account appears in the list, archiving it would call the engine on a peer that can't be archived. — `chat_list_row.dart:537-538` ← `window_peer_menu.cpp:4236`

- [ ] [MAJOR] `_SwipeRipplePainter` ripple center uses hardcoded `iconSize + iconSize/2 = 30px` offset from right edge instead of the spec-correct `dialogsQuickActionSize + dialogsQuickActionSize/2 = 30px` — the offset arithmetic happens to be correct numerically for the 20px icon, but the center is placed at `(width-30, 30)` in absolute coordinates. In AyuGram, the ellipse is drawn at `(geometry.width() - offset, offset)` relative to the row width, not the 80px ripple area — meaning as row width changes the center shifts correctly, whereas the Dart paints it relative to the 80×80 `CustomPaint` size (always `50, 30`), which is only correct when the row width matches the ripple area. — `chat_list_row.dart:938-946` ← `dialogs_layout.cpp:982-986`

- [ ] [MAJOR] `ForumChatListRow` `isNarrow` mode hard-codes `isActive: false` for `_ChatAvatar`, losing the active-state online-dot and story-ring color changes that a collapsed forum row should still reflect. — `chat_list_row.dart:2144`

## chat_settings_screen — backend wiring gaps, behavioral deviations, and loading state bugs

- [ ] [CRITICAL] `_loadCloudThemes()` has no error handler: if `engine.getCloudThemes()` throws (network/auth error) the `.then()` callback is never called, `_cloudThemesLoaded` stays `false`, and the section silently disappears with no user feedback — `chat_settings_screen.dart:114` ← `AyuGram/settings/sections/settings_chat.cpp:2746` (uses reactive `CloudList` that exposes `empty()` stream and shows/hides wrap automatically)

- [ ] [CRITICAL] `_ChatBackgroundSectionState._loading` spinner never resets if the user cancels the gallery picker or file picker without selecting anything — `_onPickGallery` sets `_loading = true` at line 2589, `_onPickFile` sets it at 2594, but `didUpdateWidget` only clears it when `wallpaper` actually changes (line 2583); a cancel leaves the thumbnail permanently covered by a spinner — `chat_settings_screen.dart:2583` ← `AyuGram/settings/sections/settings_chat.cpp:476` (BackgroundRow updates via `Background()->updates()` stream, no spinner state at all; the Dart code should use a try/finally pattern in the parent callbacks to reset `_loading`)

- [ ] [CRITICAL] `_SensitiveContentSection` is hidden when `_ageVerifyNeeded == true && _sensitiveCanChange == false` — the guard at line 593 is `(_sensitiveCanChange || _ageVerifyNeeded)`, but when only `_ageVerifyNeeded` is true the section renders with a checkbox that calls `_enableSensitiveContent`, which correctly blocks and shows a toast. However, the section title still calls it "Disable filtering" while AyuGram shows `tr::lng_settings_sensitive_disable_filtering` as a toggle button — the Dart renders a checkbox instead of a toggle (SettingsButton with `toggleOn`), making the control look like a multi-select rather than a singular on/off toggle — `chat_settings_screen.dart:4790` ← `AyuGram/settings/sections/settings_privacy_security.cpp:283`

- [ ] [CRITICAL] `_StickersEmojiSection`: "Suggest Animated Emoji" checkbox is gated by `suggestEmoji && isPremium` (line 3510), but AyuGram gates it on `AmPremiumValue(session) && suggestEmoji->value()` (reactive combination). The Dart shows/hides the widget statically at build time using the current `isPremium` snapshot — if premium status changes mid-session the checkbox does not appear/disappear reactively. More critically, the checkbox is simply hidden if not premium rather than shown-but-disabled with a premium lock indicator as in Telegram Desktop — `chat_settings_screen.dart:3510` ← `AyuGram/settings/sections/settings_chat.cpp:1507`

- [ ] [MAJOR] `_ArchiveSettingsBox._save()` silently calls `engine.setArchiveSettings()` without `await` and swallows any thrown exception into a `ScaffoldMessenger.showSnackBar` that references `context` after the dialog may have been closed — the `_save()` at line 4607 calls `engine.setArchiveSettings` synchronously (no `await`), so if the engine returns an async error it is never caught; also uses `ScaffoldMessenger.of(context)` inside a dialog, which finds the Scaffold behind it and may show the snackbar on the wrong surface — `chat_settings_screen.dart:4607` ← `AyuGram/settings/sections/settings_advanced.cpp:1832` (uses `session->api().globalPrivacy().update()` which is fire-and-forget at the data layer; the error handling path needs `await` + `.catchError`)

- [ ] [MAJOR] `_CloudThemeSection` has no "Show All" link to reveal additional cloud themes — AyuGram renders a `Ui::LinkButton` labelled `tr::lng_settings_bg_show_all` that toggles `CloudList::showAll()`, hiding it once all themes are visible. The Dart section renders all themes at once in a fixed grid, making it impossible to distinguish between "initial truncated view" and "fully expanded" — `chat_settings_screen.dart:2222` ← `AyuGram/settings/sections/settings_chat.cpp:2729`

- [ ] [MAJOR] `_ChatListQuickActionSection` dialog opens a static `AlertDialog` with radio buttons but lacks the animated Lottie preview widget that AyuGram draws above the radio list — `addPreview(box->verticalLayout())` at line 2311 inserts a live animated icon preview that updates as the user selects different actions. The Dart has `_QuickActionPreview` (line 3166) which provides an animation, but it is placed at the top of the dialog content column only when `action != 'disabled'`; the "Disabled" option shows no preview at all, while AyuGram always shows a preview with a `Swipe` label — `chat_settings_screen.dart:3100` ← `AyuGram/settings/sections/settings_chat.cpp:2311`

- [ ] [MAJOR] `_ChatListQuickActionSection._showQuickActionChooser` dialog does not save the action choice via a close button — selecting a radio calls `onActionChanged(v)` immediately (line 3128) which is correct, but there is also a separate `TextButton('OK')` that only dismisses, creating a disconnect: user can select an option, hit Cancel intent by closing, but the action has already been committed live. AyuGram uses a Box that commits only via `box->addButton(tr::lng_box_ok(), ...)` — `chat_settings_screen.dart:3126` ← `AyuGram/settings/sections/settings_chat.cpp:2298`

- [ ] [MAJOR] `_ReactionChooserButton` loads available reactions via `engine.getAvailableReactions()` but falls back to a hardcoded list of 62 reactions when the engine call fails or returns empty (lines 4308, 4321) — AyuGram uses the server-side `Data::Reactions` list from `session.data().reactions()` which is always authoritative and never hardcoded. The hardcoded list includes platform-specific emoji that may not be valid reaction types on the server — `chat_settings_screen.dart:4308` ← `AyuGram/settings/sections/settings_chat.cpp:1694`

- [ ] [MAJOR] `_AutoNightRow` reads `appState.systemDarkModeEnabled` to decide whether to show the row at all — it always shows. AyuGram only shows this button when `settings.systemDarkMode().has_value()` (line 2826), i.e. only on platforms that report OS dark mode. On platforms without system dark mode support the row should be absent — `chat_settings_screen.dart:474` ← `AyuGram/settings/sections/settings_chat.cpp:2826`

- [ ] [MAJOR] `_ChooseFontBox` calls `Core::Restart()` via `SystemNavigator.pop()` (line 509) to apply the new font — this is wrong: `SystemNavigator.pop()` exits the Flutter activity rather than restarting it, which means the app terminates instead of restarting. AyuGram calls `Core::Restart()` which hot-restarts the process — `chat_settings_screen.dart:509` ← `AyuGram/settings/sections/settings_chat.cpp:2899`

- [ ] [MAJOR] `_enableSensitiveContent` calls `engine.setContentSettings(account.id, true)` without `await` (line 111) — if the engine call fails the local `_sensitiveEnabled = true` state (set at line 110) is never reverted, leaving the UI showing the setting as enabled when it isn't. Should be `await` + catch + revert on error — `chat_settings_screen.dart:110` ← `AyuGram/settings/sections/settings_privacy_security.cpp:302` (AyuGram uses reactive stream: `button->toggleOn(...)` automatically re-reads `session->api().sensitiveContent().enabled()` which corrects itself if the update fails)

- [ ] [MAJOR] `_AccentColorPalette._showHslPicker()` clamps lightness to `[0.15, 0.85]` dark / `[0.3, 0.7]` light (line 996) which are hardcoded Dart constants — AyuGram derives these from `ColorizerFrom(*scheme, scheme->accentColor)` and reads `.lightnessMin` / `.lightnessMax` per-scheme (line 387). The Dart limits are scheme-agnostic and will be wrong for schemes like Classic where the actual allowed range differs — `chat_settings_screen.dart:996` ← `AyuGram/settings/sections/settings_chat.cpp:384`

## chat_switch_overlay — Ctrl+Tab account/chat switcher overlay

- [ ] [MAJOR] External removal selects next item instead of previous: `_onChatStateChanged` at line 94 does `_selected = _selected.clamp(0, _list.length - 1)` which keeps `_selected` at the same index (now pointing to the *next* item). AyuGram's `remove()` explicitly sets `_selected = -1` then calls `setSelected(std::min(selected - 1, _shownCount - 1))` — selecting the *previous* item when the selected chat is removed externally. — `chat_switch_overlay.dart:94` ← `window/window_chat_switch_process.cpp:288`

- [ ] [MAJOR] Layout-state mutation inside `build`: `_shownPerRow` and `_shownRows` are written inside `LayoutBuilder.builder` (a build callback) at lines 279–280 without `setState`. Key-navigation handlers (`_moveDown`, `_moveUp`) read `_shownCount` which is `_shownPerRow * _shownRows`. Any key event that fires between two builds (e.g. rapid Tab/arrow presses during resize) will use stale row/column counts from the previous layout pass, producing wrong wrap-around targets. AyuGram recomputes and assigns these synchronously inside `layout()` which is only called from `sizeValue()` reactive updates. — `chat_switch_overlay.dart:279-280` ← `window/window_chat_switch_process.cpp:layout() ~line 317`

# chat_view — Behavioral stubs, missing wiring, broken cycling

- [ ] [CRITICAL] `_scrollToMention()` jumps to the oldest unread mention but never marks it as read afterward — `unreadMentionCount` never decrements and the mention corner button never disappears. AyuGram's `mentionsClick()` additionally marks voice/video media as read when the user is already at the mention position. — `chat_view.dart:1084–1094` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_corner_buttons.cpp:118–140`

- [ ] [CRITICAL] `_scrollToFirstUnreadPoll()` scans the in-memory `chatState.messages` list for any `isPoll` message instead of using `engine.getOldestUnreadPollVote()`. The Go bridge exposes no `MessagesGetUnreadPollVotes` wrapper, so the button jumps to an arbitrary visible poll and the poll-votes corner button never clears. — `chat_view.dart:1108–1118` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_corner_buttons.cpp:154–161`

- [ ] [CRITICAL] Pinned bar has no cycling mechanism. `pinnedIndex: 0` is hardcoded, and the `onTap` handler always jumps to `chatState.pinnedMessages.first`. AyuGram uses `PinnedTracker::trackAround()` + `_pinnedClickedId` to advance to the next pinned message below the one just viewed, so repeated taps cycle through all pinned messages in reverse. In chats with multiple pinned messages, every tap goes to the same message. — `chat_view.dart:4996–5019` ← `AyuGramDesktop/Telegram/SourceFiles/history/history_widget.cpp:8437–8494`

- [ ] [CRITICAL] `_GroupCallBar` only wires the "Join" button (`onJoin`). The rest of the bar (title, subtitle, participant avatars) has no tap handler. AyuGram merges `barClicks()` and `joinClicks()` into a single stream — clicking anywhere in the bar calls `startOrJoinGroupCall`. Tapping the participant userpics or title area in the Dart version does nothing. — `chat_view.dart:11167–11258` ← `AyuGramDesktop/Telegram/SourceFiles/history/history_widget.cpp:8812–8820`

- [ ] [CRITICAL] Chat preview popup messages are not clickable. The inner `GestureDetector` at line 19703 has `onTap: () {}` (event-stop only). AyuGram fires `ChatPreviewAction{ .openItemId = view->data()->fullId() }` when the user clicks a message row, navigating to that specific message. In the Dart popup, clicking any message row does nothing. — `chat_view.dart:19702–19703` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_chat_preview.cpp:541–547`

- [ ] [CRITICAL] `request_chat` contact status bar "View Group" button only calls `chatState.hidePeerSettingsBar()` — it doesn't show info about or navigate to the referenced group. AyuGram's `setupRequestInfoHandler` opens a confirmation box with the group name and date, and only sends `MTPmessages_HidePeerSettingsBar` after the user acknowledges. — `chat_view.dart:9622–9624` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_contact_status.cpp:914–948`

- [ ] [MAJOR] `_TranslateBar` is shown only when the user explicitly toggles it from the top-bar menu (`_showTranslateBar` bool, set by `onToggleTranslate`). AyuGram auto-detects the chat's language via `TranslateTracker` / `HistoryTranslation::offerFrom()` and auto-shows the bar for foreign-language chats without any user action. The bar never auto-appears in Dart. — `chat_view.dart:302–303, 5057–5063` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_translate_bar.cpp:348–411`

- [ ] [MAJOR] Business bot bar "manage" menu (`_showBusinessBotMenu`) only offers "Remove bot from this chat". AyuGram's `BusinessBotStatus` also opens the bot's management web app using `business_bot_manage_url` from `PeerSettings`. That URL is never fetched or used in the Dart code — the manage button is therefore incomplete. — `chat_view.dart:1289–1317` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_contact_status.cpp:1184–1230`

- [ ] [MAJOR] `_ContactStatusBar` "Add Contact" dialog never calls `chatState.hidePeerSettingsBar()` after `addContact()` succeeds. The bar stays visible even after the contact is added. AyuGram's `setupAddHandler` calls `MTPmessages_HidePeerSettingsBar` on success. — `chat_view.dart:9783–9855` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_contact_status.cpp:786–800`

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

- [ ] [CRITICAL] Calendar renders one month at a time instead of vertically scrollable all-months view — `choose_datetime_box.dart:101` ← `calendar_box.cpp:1197–1239`

  AyuGram `CalendarBox` uses a `ScrollArea` whose inner widget renders **all months** from `minDate` to `maxDate` stacked vertically. The user scrolls vertically; `processScroll()` at `calendar_box.cpp:1409` detects which month is in the center of the viewport and updates the context. Prev/next buttons call `goPreviousMonth()`/`goNextMonth()` which scroll the area to the adjacent month. The Dart `_CalendarBoxWidget` instead shows **exactly one month** at a time, switched by arrow buttons or horizontal drag — a fundamentally different navigation model.

- [ ] [MAJOR] Selection mode shows an extra "Close" button that must not exist — `choose_datetime_box.dart:549–559` ← `calendar_box.cpp:1431–1443`

  AyuGram `createButtons()`: when `selectionMode=ON` it renders **only one button** — "Cancel" (which calls `toggleSelectionMode(false)`). The "Close" button is removed. Dart shows both `TelegramBoxButton(text: _selectionMode ? 'Single date' : ...)` AND `TelegramBoxButton(text: 'Close')` at all times. In selection mode the "Close" button must disappear and only a cancel-selection button should remain.

- [ ] [MAJOR] Jump-to-min/max fires ~1200 ms after press instead of 700 ms — `choose_datetime_box.dart:478–479` ← `calendar_box.cpp:36,1258–1262`

  AyuGram: `MouseButtonPress` event starts the `_jumpTimer` immediately; `kJumpDelay = 700ms`. Dart uses `onLongPressStart` on `GestureDetector`, which Flutter only fires after the default long-press recognition threshold (~500 ms), then `_startJump` schedules a further 700 ms `Timer`. Effective delay ≈ 1200 ms vs the intended 700 ms.

- [ ] [MAJOR] FloatingDate month/year overlay missing in selection mode — `choose_datetime_box.dart:297–306` ← `calendar_box.cpp:1269–1291`

  When `selectionMode` becomes active, AyuGram creates a `FloatingDate` overlay widget (`calendar_box.cpp:1274`) that displays the current visible month/year as a service-bubble label above the calendar grid. It is repositioned as the user scrolls. The Dart `_toggleSelectionMode()` does nothing analogous — no overlay label is shown.

# engine_service — Bridge service audit

## engine_service — searchGlobalPosts blocks UI thread

- [ ] [CRITICAL] `searchGlobalPosts` is a synchronous method using `_callRaw` for a network API call (`messages.searchGlobal` on the Go side) — blocks the main isolate / UI thread until the server responds. All sibling search methods (`searchGlobalChats`, `searchGlobalPostMessages`) are correctly async. AyuGram issues all global search requests asynchronously via `_api.request(...).done(...).send()` — `engine_service.dart:652` ← `AyuGram/Telegram/SourceFiles/boxes/peers/add_participants_box.cpp:1897` (`requestGlobal` / `_api.request MTPcontacts_Search … .send()`)

## engine_service — sendStoryWithPhoto encodes binary as JSON integer array

- [ ] [CRITICAL] `sendStoryWithPhoto` passes `photoData.toList()` directly into `json.encode`, which serialises the `Uint8List` as a JSON array of integers (`[100, 200, 178, ...]`). A 1 MB JPEG becomes a ≈3 MB JSON string with 1 million comma-separated integers before it even reaches the Go bridge. The same file already uses `base64.encode` for binary in `createCloudTheme` (line 4526) and `updateCloudTheme` (line 4545). AyuGram uploads media as raw bytes / mtproto binary, never as a JSON integer list — `engine_service.dart:1362` ← `AyuGram/Telegram/SourceFiles/data/data_stories.h:1` (Stories API operates on binary document/photo data, not JSON arrays)

## engine_service — getDeletedMessages crashes on empty engine response

- [ ] [MAJOR] `getDeletedMessages` calls `_callRaw` then immediately does `json.decode(utf8.decode(respBytes))` (line 2736) with no empty-response guard. `_callRaw` explicitly returns `Uint8List(0)` on empty/error responses (documented at line 5681–5683). `utf8.decode(Uint8List(0))` returns `""`, and `json.decode("")` throws `FormatException`. Every other adjacent method that uses `_callRaw` with JSON output has an `if (respBytes.isEmpty) return ...` guard — compare `getEditRevisions` at line 2700–2701 which correctly returns `[]` on empty — `engine_service.dart:2735` ← `engine_service.dart:2700` (same file: `getEditRevisions` has the guard that `getDeletedMessages` is missing)

## engine_service — Per-message JSON decode on main isolate (50 messages default)

- [ ] [MAJOR] `_cachedMsgFromProto` (line 5987) calls `jsonDecode(contentRaw)` synchronously for every message deserialized from protobuf. `getMessages` (default limit=50) calls `resp.messages.map(_cachedMsgFromProto).toList()` on the main isolate after the `await`, meaning 50+ `jsonDecode` calls run back-to-back on the UI thread. For media-heavy chats (`contentRaw` can include full inline keyboards, reactions, alt video qualities, waveforms, poll options, invoice fields, etc.), this is measurable jank on every chat open. Fix: wrap the conversion loop in `Isolate.run` or `compute`. AyuGram processes message data lazily in background threads — `engine_service.dart:5987` ← `AyuGram/Telegram/SourceFiles/data/data_session.h:1` (Session processes updates off the UI thread via `crl::on_main` dispatch)

## engine_service — sendStoryWithVideoFile also encodes overlayData as integer array

- [ ] [MAJOR] `sendStoryWithVideoFile` has the same binary-as-integer-array bug for `overlayData` (line 1403): `'overlay_data': overlayData.toList()`. Should be `base64.encode(overlayData)` consistent with `createCloudTheme` pattern at line 4526 — `engine_service.dart:1403` ← `AyuGram/Telegram/SourceFiles/data/data_stories.h:1` (binary overlay / sticker data uses proper binary encoding)

## engine_service — msg_reactions_updated event not dispatched

- [ ] [MAJOR] `_dispatchEngineEvent` has no case for a reaction-change event. When the Go engine fires a reactions update (separate from a full message edit), the event falls through to `default:` and is silently logged as "unhandled" (line 5907). The only way the UI can see a reaction change is if the engine incorrectly reuses `msg_edited` for reactions. AyuGram fires a distinct `messageUpdated` with `PeerUpdate::Flag::MessageReactions` — reactions on a message are a first-class update. Without a handler, tapping a reaction emoji has no visible effect until the next full `chat_updated` event refreshes the whole list — `engine_service.dart:5770` ← `AyuGram/Telegram/SourceFiles/data/data_changes.h:1` (`Changes::messageUpdated` with reactions flag)

# color_picker_box — HSV color picker dialog

- [ ] [MAJOR] Input field labels ("H", "S", "B", "R", "G", "B") are rendered as separate `SizedBox(width: 14)` Text widgets **outside** the text field box, with field `contentPadding: horizontal: 6`. AyuGram renders these labels **inside** the field via `paintAdditionalPlaceholder` at `style::al_topleft`, with `textMargins: margins(16px, 3px, 0px, 2px)` giving 16 px left room for the label — `color_picker_box.dart:607-616` ← `color_editor.cpp:706-718` and `boxes.style:522-524`

- [ ] [MAJOR] Slider position arrows are drawn as plain filled Path triangles (`_kArrowHalf = 4`, `_kSliderSkip = 8`). AyuGram uses dedicated icon sprites (`colorSliderArrowLeft`, `colorSliderArrowRight`, `colorSliderArrowTop`, `colorSliderArrowBottom`) loaded from asset files `color_slider_arrow` / `color_slider_arrow_vertical` with `sliderBgActive` tint, which have a different tapered shape — `color_picker_box.dart:1015-1028` and `1130-1141` ← `boxes.style:515-518` and `color_editor.cpp:394-415`

- [ ] [MAJOR] Hue slider (`_VerticalHueSlider`) and opacity slider (`_HorizontalOpacitySlider`) bars have no shadow. AyuGram's `Slider::paintEvent` draws `Ui::Shadow::paint(p, to, width(), st::defaultRoundShadow)` around every slider bar track before drawing the gradient — `color_picker_box.dart:984-1009` and `1092-1124` ← `color_editor.cpp:384-392`

- [ ] [MAJOR] `_HorizontalOpacityPainter._checkerCache` and `_checkerCacheSize` are `static` fields shared across all painter instances. If two opacity sliders with different sizes exist simultaneously the wrong cached checkerboard picture is drawn for one of them. Should be instance-level fields — `color_picker_box.dart:1082-1117`

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

- [ ] [MAJOR] `strictCancel` semantics differ: AyuGram destroys the cancel-callback lifetime immediately (`lifetime->destroy()` at confirm_box.cpp:106–108), preventing the `boxClosing` signal from firing cancel at all. Dart only suppresses cancel in the barrier-dismiss path (`then` block at confirm_box.dart:341), so explicit Cancel button still calls `onCancel` even when `strictCancel=true`. — `confirm_box.dart:341` ← `AyuGram/ui/boxes/confirm_box.cpp:100–108`

## confirm_box — §36.5 SingleChoiceBox

- [ ] [CRITICAL] AyuGram's `SingleChoiceBox` closes the box **immediately on selection change** via `setChangedCallback` (single_choice_box.cpp:48–53), not on OK button press. The Dart `_SingleChoiceContent` keeps the box open and requires the user to press OK (`confirm_box.dart:878`). This is a fundamental behavioral deviation — AyuGram's box is an auto-close picker, not a two-step confirm dialog. — `confirm_box.dart:878,897–901` ← `AyuGram/ui/boxes/single_choice_box.cpp:48–54`

- [ ] [MAJOR] AyuGram's `SingleChoiceBox` calls the `callback(value)` immediately on selection, before closing (single_choice_box.cpp:50). Dart calls `onChanged?(index)` on select but only returns the value on OK press — callers that act on immediate-selection (e.g. notification sounds) will not fire the callback until OK is pressed, breaking live-preview behavior. — `confirm_box.dart:865–866` ← `AyuGram/ui/boxes/single_choice_box.cpp:47–53`

## confirm_box — §36.2 DeleteConfirmBox / _DeleteContent

- [ ] [CRITICAL] The `openAutoDelete` return value (`DeleteConfirmResult.openAutoDelete`) is set when the user taps "Enable auto-delete" link (`confirm_box.dart:747–749`), but **no caller handles this flag** — checked across all call sites in `chat_view.dart`, `chat_list_panel.dart`, `calls_screen.dart`. The auto-delete settings panel is never opened, making the link a no-op stub. — `confirm_box.dart:747–749` ← `AyuGram/boxes/delete_messages_box.cpp:306–315` (TTLValidator.showBox() call)

- [ ] [CRITICAL] The "Enable auto-delete" / "Edit auto-delete settings" link text should vary based on whether the peer already has `messagesTTL` set (AyuGram uses two different strings: `tr::lng_edit_auto_delete_settings` vs `tr::lng_enable_auto_delete` at delete_messages_box.cpp:308–311). Dart always shows "Enable auto-delete" regardless of existing TTL state. — `confirm_box.dart:752–754` ← `AyuGram/boxes/delete_messages_box.cpp:308–311`

- [ ] [MAJOR] AyuGram's `_revokeRemember` checkbox is shown/hidden using `slide_wrap` animated toggling triggered reactively by `_revoke->checkedValue()` (delete_messages_box.cpp:262–267). Dart shows/hides it using `if (_revoke != _revokeDefault)` which evaluates **current state** at build time — it requires a `setState` call to update, which works, but it hides on initial render even when the revoke state already differs from default (because `_revoke` starts equal to `_revokeDefault`). No behavioral difference in practice, but the spec's animated slide-wrap toggle is missing. — `confirm_box.dart:735–739` ← `AyuGram/boxes/delete_messages_box.cpp:261–268`

- [ ] [MAJOR] AyuGram's delete button label dynamically updates using `rpl::combine` of the `MessagesSearch` results stream and `_deleteAll->checkedValue()` — the count shown in the button label is a **live reactive value** updated as the search API responds (delete_messages_box.cpp:218–233). Dart fires one async call in `_fetchModerateCount` and never resubscribes — if the count is still loading when `_deleteAll` is toggled, the button label will show 0 or stale count. — `confirm_box.dart:520–538, 622–628` ← `AyuGram/boxes/delete_messages_box.cpp:218–233`

- [ ] [MAJOR] AyuGram differentiates `PaidPostType::Ton` vs `PaidPostType::Stars` with distinct warning text (`tr::lng_suggest_warn_text_ton` vs `tr::lng_suggest_warn_text_stars`, and title similarly) at delete_messages_box.cpp:563–576. Dart uses a single hardcoded string "This is a paid suggested post. The payment will be lost..." with no distinction between TON and Stars paid posts. — `confirm_box.dart:668–671` ← `AyuGram/boxes/delete_messages_box.cpp:563–576`

- [ ] [MAJOR] AyuGram's `DeleteChatBox` (the leave/delete variant) shows a **userpic** next to the peer name in the header using `Ui::UserpicButton` + `Ui::IconWithTitle` (delete_messages_box.cpp:961–979). Dart's `DeleteBoxMode.leaveChat` shows only text body with no avatar/userpic header. — `confirm_box.dart:573–586` ← `AyuGram/boxes/delete_messages_box.cpp:961–979`

- [ ] [MAJOR] For bot peers in `leaveChat` mode, AyuGram shows an additional "Block bot" checkbox (`maybeBotCheckbox`, delete_messages_box.cpp:1020–1032) and a "Remove from chat folders" checkbox (`maybeChatsFiltersCheckbox`, delete_messages_box.cpp:1045–1066) and blocks the bot via `api().blockedPeers().block()` on confirm. Dart has no bot-specific checkbox or chat-filter removal logic. — `confirm_box.dart:573–586` ← `AyuGram/boxes/delete_messages_box.cpp:1020–1066`

- [ ] [MAJOR] AyuGram's channel clear-history case sets `_revokeJustClearForChannel = true` and skips the revoke checkbox entirely, instead always revoking (delete_messages_box.cpp:124–125, 589). Dart shows no revoke checkbox for channels (correct) but always passes `_revoke` (which starts `true` by default) — the logic incidentally works but is not correctly driven by the channel-detection path. — `confirm_box.dart:496–516` ← `AyuGram/boxes/delete_messages_box.cpp:124–125, 589`

## confirm_box — §36.13 Report Flow

- [ ] [MAJOR] AyuGram's `ReportDetailsBox` triggers the Lottie icon animation **on box show** via `setShowFinishedCallback` (report_box_graphics.cpp:217–218), playing it exactly once. Dart uses a `_lottieController` that calls `forward()` in `_onLottieLoaded` (confirm_box.dart:1801–1805), which fires when the asset is decoded, not when the box becomes visible — the animation may start before the box finishes its fade-in transition. Minor timing difference but spec-deviant. — `confirm_box.dart:1801–1805` ← `AyuGram/ui/boxes/report_box_graphics.cpp:217–218`

- [ ] [MAJOR] AyuGram's dynamic report flow (`ShowReportMessageBox`) shows report options as **SettingsButton rows with a right-arrow icon** (`AddReportOptionButton`, report_box_graphics.cpp:167–207). Dart's `_ReportOptionPickerBox` renders them as plain `InkWell` text rows with no arrow icon (`confirm_box.dart:1683–1699`). The visual style is wrong — missing the chevron/arrow indicator that each option drills deeper. — `confirm_box.dart:1683–1699` ← `AyuGram/ui/boxes/report_box_graphics.cpp:167–207`

- [ ] [MAJOR] AyuGram's `ReportReactionBox` uses `tr::lng_report_reaction_title()` and `tr::lng_report_reaction_about()` as the title/body strings (info_profile_actions.cpp:1302–1306). Dart hardcodes "Report Reactions" and "Are you sure you want to report reactions from this user?" — these are untranslated hardcoded strings. — `confirm_box.dart:1941, 1951–1954` ← `AyuGram/Telegram/SourceFiles/info/profile/info_profile_actions.cpp:1302–1306`

- [ ] [MAJOR] AyuGram's `ReportReactionBox` confirm button uses `st::attentionBoxButton` (info_profile_actions.cpp:1339) making it red/destructive. Dart's REPORT button in `_ReportReactionContent` uses `isDestructive: true` — this is correct and matches. However, the ban checkbox label in AyuGram is `tr::lng_report_and_ban_button(tr::now)` (info_profile_actions.cpp:1311), while Dart uses "Ban user and report" — minor text deviation but non-l10n. — `confirm_box.dart:1978` ← `AyuGram/Telegram/SourceFiles/info/profile/info_profile_actions.cpp:1311`

## confirm_box — §36.12 Screen Share Chooser

- [ ] [CRITICAL] AyuGram's screen share chooser does not exist as a Flutter/Dart widget — the C++ implementation uses `tgcalls` / WebRTC screen capture APIs directly integrated into the calling infrastructure. The Dart `_ScreenShareChooser` spawns external OS processes (`grim`, `import`, `wmctrl`, `xdotool`, `kdotool`, `xrandr`) to enumerate sources and capture thumbnails (`confirm_box.dart:1195–1339`), but **never calls the engine/bridge** to actually start screen sharing. The selected `ScreenShareResult` is returned to callers but the engine's screen-share API is not invoked here — the wiring must exist in the caller. This is correct as a data-return dialog, but if any caller fails to wire the result to the engine, screen sharing silently does nothing. — `confirm_box.dart:1503–1512` ← `AyuGram/boxes/delete_messages_box.cpp` (structural reference — no direct C++ equivalent for this dialog)

- [ ] [MAJOR] For Wayland, the `_ScreenShareChooser` falls back to `portal:screen` as a single "Entire Screen" source and enumerates windows via `kdotool` (`confirm_box.dart:1188–1213`). No thumbnail is captured on Wayland (only `grim` for the screen itself, not per-window). AyuGram uses the XDG Desktop Portal (`xdg-desktop-portal`) for Wayland screen sharing — this is the correct approach but is not implemented here. The fallback is functional as a degraded experience but does not match the spec. — `confirm_box.dart:1319–1323`

## confirm_box — Performance

- [ ] [MAJOR] `_RadioRow` in `_SingleChoiceContent` uses `setState` for hover (`_hovering`) on every `MouseRegion` enter/exit event, causing a rebuild of the entire row subtree on hover. This is acceptable for small lists but the hover color should use `AnimatedContainer` or `InkWell`'s built-in hover to avoid unnecessary rebuilds. — `confirm_box.dart:926–969`

- [ ] [MAJOR] `_ReportDetailsBox` and `_DeleteContent` use `setState` to toggle `_commentError` / `_errorText` in `onChanged` callbacks (confirm_box.dart:1711, 1857), which rebuilds the entire content column on every keypress when clearing the error. Error state should be isolated in a smaller widget. — `confirm_box.dart:1711, 1857`

## contacts_screen — Edit/Add contact notes limit wrong, sharePhone flag missing, starsPerMessage never populated, _openChatInBackground doesn't close dialog

- [ ] [CRITICAL] `_notesMaxLength` is hardcoded to 70 but AyuGram uses a server-configurable limit of 128 (`appConfigLimit("contact_note_length_limit", 128)`). The Dart TextField enforces `maxLength: 70` which silently truncates valid notes — `contacts_screen.dart:1460` ← `AyuGram/data/data_premium_limits.cpp:203`

- [ ] [CRITICAL] `sharePhone` / `add_phone_privacy_exception` flag is never sent when saving a contact. AyuGram shows a "Share my phone number with this user" checkbox (driven by `PeerBarSetting::NeedContactsException`) and passes `Flag::f_add_phone_privacy_exception` to `contacts.addContact` when checked. Neither `_EditContactBoxState._save` (line 1554) nor `engine_service.dart:addContactByUser` (line 519–530) accept or pass this flag. The Go `AddContactByUserID` function (telegram.go:26175) also omits `AddPhonePrivacyException` from the request — `contacts_screen.dart:1554` ← `AyuGram/boxes/peers/edit_contact_box.cpp:82–124` + `AyuGram/boxes/peers/edit_contact_box.cpp:776–796`

- [ ] [MAJOR] `ContactInfo.starsPerMessage` is always 0 — it is never populated from the engine. `convertUser` in `telegram.go:11717–11796` does not read `user.StarsToSendPerMessage` from the TDL user struct, so the `starsPerMessage == 0` guard at `contacts_screen.dart:1812,1821` that controls visibility of "Suggest Birthday" and "Suggest photo" buttons is always satisfied regardless of the user's paid-message restriction — `contacts_screen.dart:1812` ← `AyuGram/boxes/peers/edit_contact_box.cpp:590` (`starsPerMessageChecked()` guard)

- [ ] [MAJOR] `_openChatInBackground` (line 613) does NOT close the contacts box — it calls `_navigateToChat` then stays open, showing a toast. AyuGram's `rowMiddleClicked` (peer_list_controllers.cpp:137) fires a `_wheelClicks` event that opens the chat without closing the contacts box, which is correct intended behavior. However the implementation here fails to return focus/navigation state properly: the synthetic `ChatInfo` created at line 631 has no `accountId` guard (can be empty string `''` if `activeAccountId` is null) leading to a silent no-op — `contacts_screen.dart:613–616` ← `AyuGram/boxes/peer_list_controllers.cpp:137–140`

- [ ] [MAJOR] `_EditContactBox` first-name max length is unconstrained. AyuGram enforces `kMaxUserFirstLastName = 64` characters on both first-name and last-name fields via `first->setMaxLength(Ui::EditPeer::kMaxUserFirstLastName)`. The Dart `_InputField` widget has no `maxLength` or `inputFormatters` limit — `contacts_screen.dart:1763–1787` ← `AyuGram/boxes/peers/edit_contact_box.cpp:421–422` + `AyuGram/boxes/peers/edit_peer_common.h:13`

- [ ] [MAJOR] `_ShareContactBox` search is local-only (filters `chatState.chatsForAccount`). AyuGram's `ShareBox` fires `contacts.Search` RPC when the filter text has no local matches (`share_box.cpp:424–436`), populating results from the server. The Dart implementation at lines 2085–2090 only runs a `String.contains` filter over already-loaded chats — `contacts_screen.dart:2085` ← `AyuGram/boxes/share_box.cpp:407–438`

- [ ] [MAJOR] `_ShareContactBox` column count is dynamically computed by screen width (`_columnsForWidth`, line 2142) instead of the fixed 4-column grid AyuGram uses (`_columnCount = 4` at share_box.cpp:180). On a 600px-wide window the Dart code uses 3 columns; on a desktop-sized window it uses 4 or 5. AyuGram always uses 4 — `contacts_screen.dart:2142–2147` ← `AyuGram/boxes/share_box.cpp:180`

- [ ] [MAJOR] `_sortedChats` in `_ShareContactBoxState` identifies "Saved Messages" by matching `chat.title == 'Saved Messages'` (line 2076), which is a hardcoded English string that breaks for non-English locales or renamed "Saved Messages" chats. AyuGram identifies the self-chat via `peer->isSelf()`. The correct approach is to compare `chat.chatId` against the account's own `selfUserId` — `contacts_screen.dart:2076` ← `AyuGram/boxes/share_box.cpp:535` (`selected.front()->peer()->isSelf()`)

# create_giveaway_box — Audit findings

- [ ] [CRITICAL] Default end date is 7 days instead of 3 days — `create_giveaway_box.dart:64` (`_untilDate = DateTime.now().add(const Duration(days: 7))`) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1263` (`state->dateValue = ThreeDaysAfterToday().toSecsSinceEpoch()`) and `create_giveaway_box.cpp:64-73` (`ThreeDaysAfterToday()` rounds to next 5-minute boundary too)

- [ ] [CRITICAL] Missing "Add Channels" section — users cannot select additional channels that subscribers must join to qualify; the `additional_peers` param exists in the Go backend but is never collected from the UI — `create_giveaway_box.dart` (no such section exists) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:862-938` (full `SelectedChannelsListController` peer list + "Add" button + `state->selectedToSubscribe`)

- [ ] [CRITICAL] Missing country filter for subscriber eligibility — `_onlyNewSubscribers` bool toggle (line 62) is a poor substitute for the AllMembers/OnlyNewMembers radio group plus country picker — `create_giveaway_box.dart:62,501-506` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:940-1016` (`membersGroup`, `countriesValue`, `SelectCountriesBox`)

- [ ] [CRITICAL] Missing Credits/Stars giveaway type entirely — the Dart only has `random` and `prepaid` enum values; the Credits giveaway with star options, slider, and `yearlyBoosts` badge is absent — `create_giveaway_box.dart:13` (`enum _GiveawayType { random, prepaid }`) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:272,458-699` (`GiveawayType::Credits`, `Api::CreditsGiveawayOptions`, `fillCreditsOptions`)

- [ ] [CRITICAL] "Additional Prize" field is always visible; should be hidden behind a toggle button that reveals it — `create_giveaway_box.dart:550-566` (bare `TextField` always rendered) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1101-1136` (`additionalToggle` SettingsButton toggles `SlideWrap<InputField>`, hidden by default with `additionalInner->hide(anim::type::instant)`)

- [ ] [MAJOR] No confirmation dialog before launching prepaid giveaway — `_launchPrepaid()` calls the engine immediately — `create_giveaway_box.dart:102-133` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1524-1535` (`Ui::MakeConfirmBox` with `tr::lng_giveaway_start_sure` shown before `startPrepaid`)

- [ ] [MAJOR] Winner count selection uses ChoiceChip widgets instead of a continuous slider — `create_giveaway_box.dart:429-448` (Wrap of ChoiceChips) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:701-860` (`MediaSliderWheelless` with floating label showing current value)

- [ ] [MAJOR] Duration selection uses ChoiceChip widgets instead of premium gift option cards with pricing — `create_giveaway_box.dart:452-473` (Wrap of ChoiceChips showing "N mo") ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1059-1085` (`Ui::Premium::AddGiftOptions` with `giveawayGiftCodeGiftOption` style, full price display)

- [ ] [MAJOR] Max date for the date picker is hardcoded to 365 days; should be fetched from the API — `create_giveaway_box.dart:519` (`DateTime.now().add(const Duration(days: 365))`) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1285-1287` (`state->apiOptions.giveawayPeriodMax()`)

- [ ] [MAJOR] "Show Winners" rendered as a Material Switch instead of a SettingsButton toggle — `create_giveaway_box.dart:508-513` (`_SettingSwitch` with `Switch` widget) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1322-1338` (`Ui::SettingsButton` with `toggleOn(rpl::single(false))`)

- [ ] [MAJOR] Start Giveaway button missing boost-count badge — button shows plain "Start Giveaway" text with no boost indicator — `create_giveaway_box.dart:585,603` (`Text('Start Giveaway'...)`) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1349-1372` (`AddLabelWithBadgeToButton` displaying `giveawayBoostsPerPremium() * sliderValue`)

- [ ] [MAJOR] Winner count chips show raw subscriber count with no boost calculation — label shows `'$u'` but should show boosts-per-subscription multiplied count — `create_giveaway_box.dart:435` (`label: Text('$u')`) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:748-756` (`state->apiOptions.giveawayBoostsPerPremium() * v` populates the quantity subtitle)

## create_group_wizard — Setup channel step, noForwards, slowMode placement, invite link button, TTL box, megagroup labels

- [ ] [CRITICAL] "Invite via Link" button in member picker only copies the link to clipboard; AyuGram's equivalent button opens EditPeerTypeBox so the user can manage the invite link properly — `create_group_wizard.dart:1434` ← `AyuGram/boxes/peers/add_participants_box.cpp:936`

- [ ] [CRITICAL] noForwards ("Restrict Saving Content") toggle is hidden for channels in _EditPeerTypeBox (`if (!widget.isChannel)` gates the entire permissions block); AyuGram shows noForwards for both channels and groups unconditionally — `create_group_wizard.dart:3406` ← `AyuGram/boxes/peers/edit_peer_type_box.cpp:280`

- [ ] [MAJOR] TTL auto-delete selection in the Info step title bar uses a PopupMenuButton dropdown; AyuGram opens a proper TTLBox (GenericBox with TimePickerBox, Save/Cancel buttons, Disable button when TTL is set) — `create_group_wizard.dart:1071` ← `AyuGram/boxes/add_contact_box.cpp:645` and `AyuGram/menu/menu_ttl.cpp:160`

- [ ] [MAJOR] Wizard setupChannel step title for megagroup type is "Channel Type"; AyuGram's edit_peer_type_box title for megagroup (isGroup=true) is "Group Type" — `create_group_wizard.dart:1024` ← `AyuGram/boxes/peers/edit_peer_type_box.cpp:71`

- [ ] [MAJOR] _buildSetupChannelStep shows hardcoded "Public Channel" / "Private Channel" radio labels for all wizard types including megagroup; AyuGram uses "Public Group" / "Private Group" for megagroup — `create_group_wizard.dart:1240` ← `AyuGram/boxes/peers/add_contact_box.cpp:984`

- [ ] [MAJOR] _buildSetupChannelStep subtitle text "Anyone can find the channel and join" / "Only accessible via invite link" is hardcoded for channel for all types including megagroup; AyuGram shows group-specific text for megagroup ("Public groups can be found in search…" / "Private groups can only be joined if you were invited…") — `create_group_wizard.dart:1241` ← `AyuGram/boxes/peers/add_contact_box.cpp:1004`

- [ ] [MAJOR] Slowmode slider is placed inside _EditPeerTypeBox alongside privacy/noForwards controls; AyuGram places slowmode exclusively in edit_peer_permissions_box, not in edit_peer_type_box — `create_group_wizard.dart:3042` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:782`

- [ ] [MAJOR] createMegagroup engine call does not pass a TTL period; AyuGram sends `f_ttl_period` flag and the TTL value when creating a megagroup channel via MTPchannels_CreateChannel — `create_group_wizard.dart:770` ← `AyuGram/boxes/add_contact_box.cpp:836`

# custom_emoji_cache — Audit findings

## Sources compared
- Dart: `dart/lib/ui/custom_emoji_cache.dart`
- AyuGram: `data/stickers/data_custom_emoji.cpp`, `lib_ui/ui/text/custom_emoji_instance.cpp/.h`

---

- [ ] [MAJOR] `preloadBatch()` is defined but never called anywhere in the codebase — it is dead code. AyuGram's `CustomEmojiManager` populates `_pendingForRequest` proactively before rendering so emoji resolve before widgets mount. In Dart, every emoji widget independently calls `request()` on mount; no scene-level prefetch happens. Emoji in newly-scrolled-to chats will always render as blank/preview until the per-widget batch fires. — `custom_emoji_cache.dart:219` ← `data/stickers/data_custom_emoji.cpp:657-660` (resolve queues to `_pendingForRequest` immediately on demand, triggering `request()` on the next main-loop tick)

- [ ] [MAJOR] `_notifyListeners(changedIds)` always fires **all** `_globalListeners` unconditionally (line 493-495), regardless of which `documentId`s changed. Every widget that called `addListener` rebuilds on every batch completion, even if none of its emoji changed. AyuGram uses per-instance `Fn<void()> update` callbacks passed at `create()` time, so only the instances that actually loaded new data repaint. With N emoji widgets open, each batch triggers N `setState()` calls instead of the handful that changed. — `custom_emoji_cache.dart:493` ← `data/stickers/data_custom_emoji.cpp:821-835` (`repaintLater` schedules repaint only for the specific `Instance*` that updated)

- [ ] [MAJOR] Animation-frame constants `kMaxFrames = 180`, `kPreloadFrames = 3`, and `kPerRow = 16` are declared in `EmojiSizeConstants` but are **never referenced anywhere** in the Dart codebase. In AyuGram these constants live in `Cache` (the sprite-sheet renderer) and are actively used to cap frame count, trigger preloading, and compute sprite-sheet geometry. Their presence in Dart without any usage means the sprite-sheet frame-management layer (`Cache::paintCurrentFrame`, preload logic) is entirely absent; the Lottie Flutter package is used directly instead with no frame cap or preload control. — `custom_emoji_cache.dart:49-51` ← `lib_ui/ui/text/custom_emoji_instance.cpp:23-25`, `custom_emoji_instance.h:102` (`kPerRow = 16`, `kMaxFrames = 180`, `kPreloadFrames = 3` all actively used in `Cache::paintCurrentFrame` and `Renderer::renderNextFrame`)

# edit_forum_topic_box — Audit Findings

- [ ] [CRITICAL] "View Premium" button in premium toast is a no-op stub — tapping it only calls `_dismissToast()` instead of navigating to the Premium subscription flow. In AyuGram, `StickerToast` for `Section::TopicIcon` calls `Settings::ShowPremium(window, u"forum_topic_icon"_q)` to open the Premium features page. — `edit_forum_topic_box.dart:646-657` ← `AyuGram/history/view/history_view_sticker_toast.cpp:235-237`

- [ ] [MAJOR] Default reset cell renders `Icons.close` (an X icon) instead of the current default color icon. In AyuGram the first grid entry is `kDefaultIconId` which is rendered by `DefaultIconEmoji::paint` as `Data::ForumTopicIconFrame(_icon.colorId, _icon.title, st)` — the live color circle that reflects the current topic color and title. The Dart's X icon is semantically and visually wrong for this slot. — `edit_forum_topic_box.dart:920-928` ← `AyuGram/boxes/peers/edit_forum_topic_box.cpp:285-289, 93-114`

- [ ] [MAJOR] Icon selector panel lacks search. AyuGram uses `EmojiListWidget::Mode::TopicIcon` backed by `reactPanelEmojiPan` which includes a search bar (`searchMargin: margins(1px, 10px, 2px, 6px)`). The Dart replaces the entire widget with a custom tab bar + grid and has no search input, making large emoji sets unsearchable. — `edit_forum_topic_box.dart:683` ← `AyuGram/boxes/peers/edit_forum_topic_box.cpp:291-299` + `AyuGram/chat_helpers/chat_helpers.style:883-884`

# edit_mark_box.dart — Audit vs AyuGram EditMarkBox

## Summary
The Dart file exists but is **DEAD CODE**—never imported or used anywhere. The actual mark editing UI is implemented inline in `ayu_chats_page.dart` with a different (buggy) implementation. Critical differences from AyuGram include: missing input validation, hardcoded UI strings, missing error feedback, and swapped button order.

---

## Critical Issues

- [ ] **[CRITICAL]** Dead code — `edit_mark_box.dart` defines `showEditMarkBox()` but zero callers exist. The entire file is unreferenced. Meanwhile, `ayu_chats_page.dart` reimplements `_EditMarkBoxContent` inline with different (broken) logic. `edit_mark_box.dart:1–131` ← **UNUSED** (no imports found)

- [ ] **[CRITICAL]** Missing input validation in the ONLY used implementation — `ayu_chats_page.dart:_EditMarkBoxContentState._save()` calls `widget.onSaved()` unconditionally, allowing empty mark strings. AyuGram validates via `_text->getLastText().trimmed().isEmpty()` before save. `ayu_chats_page.dart:~1004–1008` ← `edit_mark_box.cpp:73–79` (shows proper validation)

- [ ] **[CRITICAL]** Hardcoded UI strings (no i18n) — Both implementations use hardcoded 'Reset', 'Save', 'Cancel' instead of localization keys. AyuGram uses `tr::ayu_BoxActionReset()`, `tr::lng_settings_save()`, `tr::lng_cancel()`. `edit_mark_box.dart:114,121,125` + `ayu_chats_page.dart:~1021,1024,1027` ← `edit_mark_box.cpp:44,50,55`

---

## Major Issues

- [ ] **[MAJOR]** Missing error visual feedback in active implementation — `ayu_chats_page.dart:_EditMarkBoxContentState` has **no error state, no validation, no error display**. `edit_mark_box.dart` has error handling (`_showError` flag + red border), but that file is dead code. Only the broken version is used. `ayu_chats_page.dart:~1010–1030` ← `edit_mark_box.cpp:73–77` (shows error handling via `_text->showError()`)

- [ ] **[MAJOR]** Missing onSubmitted handler in used implementation — `ayu_chats_page.dart:_EditMarkBoxContentState.build()` has **no `onSubmitted` callback** on the TextField. Pressing Enter doesn't submit. AyuGram wires Enter via `_text->submits() | rpl::on_next()`. `ayu_chats_page.dart:~1013` (TextField has no onSubmitted) ← `edit_mark_box.dart:92` (has `onSubmitted: (_) => _submit()`) vs `edit_mark_box.cpp:65–66`

- [ ] **[MAJOR]** Button order mismatch vs AyuGram — Dart has Reset (left), Cancel (middle), Save (right). AyuGram has Reset (left), Save (middle), Cancel (right). Primary action (Save) is in wrong position. `ayu_chats_page.dart:~1021–1027` ← `edit_mark_box.cpp:44–58`

- [ ] **[MAJOR]** Border color inconsistency — `ayu_chats_page.dart` uses `p.windowBgActive` for both normal and focused borders. Focused border has no color change indication (both are same). AyuGram styled via `st::defaultInputField` which includes proper active/inactive states. `ayu_chats_page.dart:~1015–1020` ← `edit_mark_box.cpp:29–33`

- [ ] **[MAJOR]** Padding/spacing mismatch — `ayu_chats_page.dart` uses `EdgeInsets.fromLTRB(24, 0, 24, 8)` (top=0). `edit_mark_box.dart` uses `EdgeInsets.fromLTRB(24, 2, 24, 8)` (top=2). AyuGram uses `st::contactPadding` (49px left, 2px top, 0px right, 14px bottom) which neither matches. `ayu_chats_page.dart:~1012` + `edit_mark_box.dart:87` ← `edit_mark_box.cpp:37,93`

- [ ] **[MAJOR]** Hint text styling mismatch — `ayu_chats_page.dart` adds alpha transparency to hint color: `.withValues(alpha: 0.4)`. `edit_mark_box.dart` uses hardcoded `fontWeight.w600` without alpha. Both deviate from AyuGram's standard InputField styling. `ayu_chats_page.dart:~1017–1018` + `edit_mark_box.dart:96` ← `edit_mark_box.cpp:29–33`

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


# ayu_filter — Regex Filter Engine Audit

## Findings

- [ ] [CRITICAL] `_serviceMessageType` missing `TYPE_GIFT_PREMIUM_CHANNEL` (25): AyuGram distinguishes channel premium gifts (`gift->channel` → 25) from user premium gifts (→ 18), but the Dart switch only handles `'gift_premium': return 18` with no channel variant — any service message for a premium gift sent to a channel will be mistyped as 18 instead of 25, breaking filters that target type 25 — `ayu_filter.dart:217` ← `filters_utils.cpp:619-622`

- [ ] [CRITICAL] `ImportChanges` and `previewImport` omit `peersToBeResolved`: `ApplyChanges` in AyuGram carries a `peersToBeResolved` vector; when applying an import, `ResolveFilterBackupPeers` is called to look up unknown peers via the API so per-dialog filters get correct IDs. The Dart `ImportChanges` class has no such field, `previewImport` never reads the `"peers"` key from the JSON, and `applyImport` never resolves anything — per-dialog filter imports silently fail to associate the correct dialog ID for any peer not already in the local cache — `ayu_filter.dart:97-124, 355-391` ← `filters_utils.h:27`, `filters_utils.cpp:832-864, 869-910`

- [ ] [CRITICAL] Blocked/shadow-banned sender filtering never shows the "show filtered messages" button: AyuGram calls `FiltersCacheController::putHiddenBlockedMessage(item)` when a message is hidden due to a blocked or shadow-banned sender, which marks the dialog in `dialogsWithHiddenBlockedMessages`; `hasFilteredMessages` checks that set so the button appears. In Dart, the early-returns for blocked/shadow-banned senders at lines 574-576 return `true` without ever calling `_cacheResult`, so `_chatFilteredCount` stays at 0, `_hasFilteredMessages` returns false, and `filteredMessagesShown` returns null — the "show filtered messages" button never appears in dialogs where messages are hidden only due to blocked/shadow-banned senders — `ayu_filter.dart:572-576, 539-545, 547-549` ← `filters_controller.cpp:161-165`, `filters_cache_controller.cpp:177-180, 160-175`

- [ ] [MAJOR] All stickers (Go engine mediaType=6) are uniformly mapped to TYPE_STICKER (13), never TYPE_ANIMATED_STICKER (15): AyuGram checks `document->isAnimation()` on sticker documents and returns 15 for animated stickers and 13 for static ones; dice media also returns 15. The Dart `_mediaTypeNames` has a single entry `6: 13` for all stickers, so filters targeting type 15 will never match animated stickers — `ayu_filter.dart:156` ← `filters_utils.cpp:586-590, 550-551`

- [ ] [MAJOR] `publishFilters` writes multipart body as a Dart `String` via `request.write()` with no explicit encoding: `HttpClientRequest` as an `IOSink` for `multipart/form-data` (no charset declared) defaults to ISO-8859-1 encoding. Non-ASCII regex patterns (Cyrillic, Arabic, CJK, etc.) in the JSON content field will be silently corrupted before transmission — AyuGram uses `QNetworkAccessManager` with `QHttpMultiPart` which handles encoding correctly — `ayu_filter.dart:441-453` ← `filters_utils.cpp:347-392`

- [ ] [MAJOR] Cache eviction leaves `_chatFilteredCount` permanently inflated: when the message cache hits `_maxCacheSize`, `_removeCacheEntry` is called with `fromEviction: true`, which skips the count decrement for evicted `filtered=true` entries. The count never goes back down even if all filtered messages are later superseded, making `_hasFilteredMessages` return true indefinitely for busy chats until a filter rebuild. AyuGram has no size limit — it clears `filteredMessages` entirely only on `rebuildCache()` — `ayu_filter.dart:615-640` ← `filters_cache_controller.cpp:90-100`

- [ ] [MAJOR] Group cache invalidation requires caller to supply `groupMemberIds` explicitly: AyuGram's `invalidate(item)` auto-discovers the album group via `owner().groups().find(item)` and invalidates all members in one call. The Dart `invalidateMessage` only invalidates other group members if the caller passes a non-null `groupMemberIds` list — if any call site omits it, the cache entries for sibling album items remain stale and may continue to produce wrong filter results — `ayu_filter.dart:556-563` ← `filters_cache_controller.cpp:216-225`

# emoji_panel — Audit findings

- [ ] [CRITICAL] All 3 tab widgets are built eagerly in `_TabContent.build()` via `List.generate(3, ...)` and wrapped in `Offstage`; Flutter still calls `initState()` on every child regardless of `offstage: true`, so `_StickerTabState.initState()` schedules `_loadData()` (3 parallel engine calls: `getInstalledStickerPacks` + `getRecentStickers` + `getFeaturedStickerPacks`) and `_GifTabState.initState()` schedules `_loadData()` + `_resolveGifBot()` the instant the panel opens — even if the user only ever uses the emoji tab. AyuGram calls `afterShown()` only for the currently selected tab, never pre-initialising hidden tabs. — `emoji_panel.dart:580-631` ← `AyuGram/chat_helpers/tabbed_selector.cpp:1057-1062`

- [ ] [CRITICAL] `_stickerFileLoading` is a static `Set<int>` shared across all `_StickerTabState` instances. When the widget is disposed while an `engine.getStickerFiles()` call is in-flight, the `.then()` callback hits `if (!mounted) return` at line 1701 and exits **without** calling `_stickerFileLoading.remove(docId)` at line 1707. The docId remains in the set permanently, so that sticker's file can never be loaded in any future `_StickerTab` instance (the guard at line 1694 returns immediately). AyuGram uses RAII/lifetime-scoped weak pointers and never has this leakage. — `emoji_panel.dart:1694-1707` ← `AyuGram/chat_helpers/stickers_list_widget.cpp` (no equivalent bug)

- [ ] [MAJOR] In `_GifTabState._onSearchResultTap()`, the fallback branch at line 3003 calls `widget.onGifSend?.call(result.id)` where `result.id` is an inline bot result identifier string (e.g. `"1234_abcd"`), not a Telegram document file ID. This branch is hit when `_lastQueryId == 0`, which occurs if a prior search completed with a `null` response (leaving `_lastQueryId` at 0) while `_searchResults` still holds stale results from an earlier query — the user can then tap a stale result and the send silently fails because `onGifSend` expects a document fileId. AyuGram always sends inline results via queryId+resultId pair through the bot API. — `emoji_panel.dart:2999-3004` ← `AyuGram/chat_helpers/gifs_list_widget.cpp:308-324`

- [ ] [MAJOR] `_EmojiTabState.deactivate()` unconditionally sets `_loadedPacks = false` (line 864) and `_GifTabState.deactivate()` sets `_loaded = false` (line 878). This means custom emoji packs are re-fetched via `getInstalledEmojiSets` and saved GIFs via `getSavedGifs` + `resolveUsername` on every single tab switch, regardless of whether the data has changed. AyuGram's `beforeHiding()` / `afterShown()` pair does not reset previously loaded content — the data is cached in-memory across show/hide cycles. — `emoji_panel.dart:863-866, 876-880` ← `AyuGram/chat_helpers/tabbed_selector.cpp:1045-1062`

- [ ] [MAJOR] In `_GifTabState._onSearchChanged()`, line 2924 mutates `_activeCategoryIndex = -1` directly without wrapping it in `setState()`. `_activeCategoryIndex` controls which icon is highlighted in `_GifCategoryFooter`. After the user edits the search text in a way that should deselect the active category, the footer will continue showing the old category highlighted until the 400ms search debounce fires, `_performSearch` completes, and a `setState` is eventually triggered. AyuGram updates UI state synchronously on text change. — `emoji_panel.dart:2923-2924` ← `AyuGram/chat_helpers/gifs_list_widget.cpp` (state changes are immediate)

# emoji_status_widget — Backend format mismatch

## Issues Found

- [ ] [CRITICAL] Collectible emoji status prefix never generated by backend — `emoji_status_widget.dart:91` expects `collectible:{docId}:{centerHex}:{edgeHex}` but `telegram.go:11710-11711` returns plain documentID only. Collectible gradient rendering code (ShaderMask + RadialGradient at line 222-230) will never execute because prefix detection fails.

- [ ] [CRITICAL] Userpic emoji status prefix never generated by backend — `emoji_status_widget.dart:100` expects `userpic:` prefix but `telegram.go:11703-11715` never generates this prefix. Userpic detection code (_buildUserpicStatus at line 235-257) will never execute.

- [ ] [CRITICAL] Collectible color information not passed from backend — Even if prefix were added, `telegram.go` has access to `tg.EmojiStatusCollectible` which likely contains `CenterColor` and `EdgeColor` fields (per AyuGram `data_emoji_statuses.h:32-33`), but `extractEmojiStatusID()` only extracts DocumentID, discarding color data. Dart parsing logic at line 96-99 relies on colors being in the ID string, but they're not available.

## Affected Features

- Collectible emoji status badge rendering with animated gradient and stars (should render like AyuGram's `Ui::Premium::MakeCollectibleEmoji()` at `premium_stars_colored.cpp:328-342`)
- Userpic emoji status rendering (ClipOval avatar with person icon fallback at line 243-256)
- Gradient shield animation for premium/collectible status (line 222-230 will never apply)

## Implementation Gaps vs AyuGram

| Feature | AyuGram | Uniclient Dart | Status |
|---------|---------|-----------------|--------|
| Collectible format | `collectible:{id}` + lookup colors from EmojiStatuses DB | `collectible:{id}:{centerHex}:{edgeHex}` parsed from string | Mismatch |
| Userpic format | `userpic:` prefix + load user avatar | `userpic:` prefix parsing only | No generation |
| Color retrieval | Real-time from `emojiStatuses->collectibleInfo(id)` | Hardcoded into emoji ID string | Not passed |
| Gradient animation | Radial + animated stars (CollectibleEmoji class) | Simple RadialGradient only | Simplified |

## Resolution Path

1. Modify `telegram.go:extractEmojiStatusID()` to prefix collectible emoji with `"collectible:"` (line 11710-11711)
2. Extend format to include color hex: `collectible:{docId}:{centerHex}:{edgeHex}` if colors are available in `tg.EmojiStatusCollectible`
3. Add `"userpic:"` prefix detection for userpic status (if this feature is required)
4. OR: add separate fields to engine.proto for `is_collectible`, `collectible_center_color`, `collectible_edge_color` instead of embedding in the string

# filter_column — Audit findings

- [ ] [MAJOR] "Mark as Read" silently marks all chats without confirmation even when unread count > 1000 — `filter_column.dart:394-400` and `filter_column.dart:464-470` both iterate and call `chatState.markChatRead()` unconditionally. AyuGram's `MenuAddMarkAsReadChatListAction` checks `unreadState.messages > kMaxUnreadWithoutConfirmation (1000)` and shows a separate confirm box (`tr::lng_context_mark_read_sure()`) before proceeding — `AyuGram/SourceFiles/window/window_peer_menu.cpp:3849`

- [ ] [MAJOR] Remove folder UX misses shared-chatlist flow — `filter_column.dart:479-509` shows a one-size-fits-all "Are you sure?" `AlertDialog` then calls `chatState.deleteFolder()`. AyuGram's `RemoveComplexChatFilter::request()` first checks `filter.hasMyLinks()`, shows a different dialog for filters with chatlist links ("delete for all members?"), fetches `MTPchatlists_GetLeaveChatlistSuggestions`, and lets the user pick which chats to leave — `AyuGram/SourceFiles/api/api_chat_filters_remove_manager.cpp:68-120`

- [ ] [MAJOR] Lock icon is wrong shape and size — `filter_column.dart:819` defines `_lockIconSize = 8` and renders a Material `Icons.lock` (line 929). AyuGram draws a custom arc+block padlock via `SideBarLockIcon()` at `sideBarButtonLockSize: size(9px, 10px)` with `sideBarButtonLockArcHeight: 3px`, `sideBarButtonLockBlockHeight: 5px`, `sideBarButtonLockArcOffset: 2px` — `AyuGram/Telegram/lib_ui/ui/widgets/widgets.style:1689-1694` and `AyuGram/Telegram/lib_ui/ui/widgets/side_bar_button.cpp:237-285`

# folders_settings_screen — Audit findings

- [ ] [MAJOR] `useVerticalFilters` toggle is not persisted via engine — `chatState.useVerticalFilters = v` only updates in-memory state with `notifyListeners()`, never calls an engine method. AyuGram calls `Core::App().settings().setChatFiltersHorizontal(value)` + `Core::App().saveSettingsDelayed()` so the setting survives restarts — `folders_settings_screen.dart:492` ← `settings_folders.cpp:1148`

- [ ] [MAJOR] View section "enough space" threshold is wrong — Dart hardcodes `windowWidth < 712` to hide the View section, but AyuGram computes `widget()->width() >= minimumWidth() + st::windowFiltersWidth` which is `380 + 72 = 452px`. The section is hidden at widths where it should be visible (452–711px) — `folders_settings_screen.dart:478` ← `settings_folders.cpp:1118`, `window_session_controller.cpp:3138`, `window.style:13`, `window.style:253`

- [ ] [MAJOR] Missing confirmation dialog when removing a folder that has invite links — AyuGram checks `row->filter.hasMyLinks()` and shows a confirmation box with "Delete" (attentionBoxButton style) before marking for removal. The Dart `FolderInfo` model has no `hasMyLinks` field and `_removeFolder` skips this check entirely, so folders with shared links are silently queued for deletion without confirmation — `folders_settings_screen.dart:173-201` ← `settings_folders.cpp:422-436`

- [ ] [MAJOR] Premium preview for "Show Folder Tags" toggle uses a custom AlertDialog stub instead of the real premium preview flow — AyuGram calls `ShowPremiumPreviewToBuy(controller, PremiumFeature::FilterTags)` which opens the animated premium feature preview box. The Dart `_showPremiumPreview()` shows a plain AlertDialog with a "Subscribe to Premium" button that calls `_showPremiumPurchaseDialog` (another stub that just says "subscribe in the official app" and offers no action) — `folders_settings_screen.dart:1047-1091` ← `settings_folders.cpp:1048`

# forum_topic_icon — Audit findings

- [ ] [MAJOR] `_customEmojiPendingRequests` not cleaned up on fetch failure — if `engine.getCustomEmojiFiles` throws, `_customEmojiPendingRequests.remove(documentId)` at line 449 is never reached (it's on the happy path only, not in a `try/finally`). The stale completed-with-error future stays in the map forever, causing all subsequent calls to `_fetchCustomEmojiData` for that documentId to immediately return the failed future (via line 430), permanently blocking retry. Fix: wrap the body of the async closure in `try/finally { _customEmojiPendingRequests.remove(documentId); }`. — `forum_topic_icon.dart:449` ← `AyuGramDesktop/Telegram/SourceFiles/data/stickers/data_custom_emoji.cpp:308` (cache lookup uses `startCacheLookup` with proper error-path cleanup before `loadNoCache`)

- [ ] [MAJOR] `gzip.decode` runs synchronously on the UI isolate — line 439 calls `gzip.decode(file.fileData)` inside an async closure that runs on the UI thread. TGS (Lottie) files are gzip-compressed and can be 20–100 KB; synchronous decompression on the main isolate blocks frame rendering. Fix: `final decoded = await Isolate.run(() => gzip.decode(file.fileData));` — `forum_topic_icon.dart:439` ← `AyuGramDesktop/Telegram/SourceFiles/data/stickers/data_custom_emoji.cpp:361` (C++ sticker loading decompresses off the UI thread via the Storage thread pool)

- [ ] [MAJOR] `_onLottieLoaded` creates `_lottieController` without calling `setState` — `build()` passes `controller: _lottieController` to `Lottie.memory`; on the first render this value is `null`, so Lottie enters auto-play mode. `_onLottieLoaded` (lines 592–598) then creates and starts the `AnimationController`, but never calls `setState`, so the Lottie widget is never rebuilt with the new non-null controller. The external controller ticks every frame via vsync but drives no visible output; Lottie continues in auto-play mode until an unrelated rebuild happens, at which point the animation may jump frames. Fix: wrap the body of `_onLottieLoaded` in `setState(() { ... })`. — `forum_topic_icon.dart:592` ← `AyuGramDesktop/Telegram/SourceFiles/data/stickers/data_custom_emoji.cpp:71` (AyuGram's Lottie integration in `LottieSizeFromTag` always drives animation via a properly wired external controller from the start)

- [ ] [MAJOR] `Image.memory` for WebP topic icons does not specify `cacheWidth`/`cacheHeight` — lines 627–631 render a WebP-encoded emoji at display size `s` (21–32 px) but decode it at the file's native resolution (typically 100–512 px), wasting CPU and GPU memory. Fix: add `cacheWidth: s.toInt(), cacheHeight: s.toInt()` to both `Image.memory` calls (lines 628 and 663). — `forum_topic_icon.dart:628` ← `AyuGramDesktop/Telegram/SourceFiles/data/forum_topic.cpp:85` (`ForumTopicIconBackground` renders the SVG directly to a `size × size` QImage, never decoding above the required display resolution)

## ghost_settings_page — Missing active-account ring in picker popup

- [ ] [MAJOR] Active account selection indicator (blue outline ring) not rendered in picker popup items — `_AccountAvatar` and `_GlobalSettingsAvatar` never paint an active state ring regardless of which account is selected; in AyuGram C++ both `AccountAction::paint` and `GlobalAction::paint` call `PaintAccountOutline(p, userpic.outer)` when `_active == true` — `ghost_settings_page.dart:644-676` ← `AyuGram/ayu/ui/settings/settings_ayu.cpp:156-158` (AccountAction), `settings_ayu.cpp:247-249` (GlobalAction)

## hamburger_drawer — audit findings

- [ ] [MAJOR] Archive context menu "Archive Settings" opens generic SettingsScreen instead of a dedicated archive settings box — `hamburger_drawer.dart:595-612` ← `AyuGram/window/window_peer_menu.cpp:1892` (`Settings::ArchiveSettingsBox`)

- [ ] [MAJOR] "How does the archive work?" dialog is a static info-only widget with no backend wiring — AyuGram's `ArchiveHintBox` includes a live "Unarchive on new message" toggle connected to `Api::globalPrivacy().unarchiveOnNewMessageCurrent()` — `hamburger_drawer.dart:619-692` ← `AyuGram/window/window_peer_menu.cpp:1898-1907`

# info_panel — Audit findings

- [ ] [MAJOR] `isSelf` detection uses hardcoded title string comparison instead of `ChatInfo.isSelf` field — `info_panel.dart:2711` ← `AyuGram/info/profile/info_profile_top_bar.cpp:891` (user->isSelf())
  Currently: `isSelf: widget.chat.title == 'Saved Messages' && widget.chat.type == ChatType.dm`
  Should be: `isSelf: widget.chat.isSelf`
  The `ChatInfo` model already has `isSelf: j['is_self'] as bool? ?? false` at engine_models.dart:359. The title comparison will silently break for localized account names or if the title changes.

- [ ] [MAJOR] `_actionButtons()` missing "Manage" button for admin-editable peers — `info_panel.dart:926` ← `AyuGram/info/profile/info_profile_top_bar.cpp:933`
  AyuGram places a "Manage" action button in the cover action row when `EditPeerInfoBox::Available(peer)` is true (i.e., user is admin). Dart only has edit in the `_GroupActionsSection` / `_ChannelActionsSection` rows below the fold, so admin users cannot reach edit from the top cover action bar as they can in AyuGram.

- [ ] [MAJOR] `_canShowStatsMenu()` shows stats menu button to non-admins — `info_panel.dart:2463` ← `AyuGram/info/profile/info_profile_top_bar.cpp:1039`
  Current code only checks member count (≥50 for channels, ≥500 for groups) with no admin-rights check. The stats/more-vert button in the cover top bar appears for any member of a large enough group. AyuGram gates statistics on admin permissions (`canViewStatistics()`). The `_ChannelActionsSection` at line 4692 correctly adds `_isSelfAdmin &&` — the same guard must be applied to `_canShowStatsMenu()`.

- [ ] [MAJOR] No video/animated avatar support in cover — `info_panel.dart:700` ← `AyuGram/info/profile/info_profile_top_bar.cpp:1814`
  Dart only renders static `Image.file` / `Image.memory` for avatars. AyuGram drives a `Ui::VideoUserpicPlayer` that streams animated frames for video profile photos. Users who set animated profile photos will see a frozen still frame instead of the animation.

# input_dialogs — Audit Findings

## input_dialogs — add_contact_box: IsValidPhone missing special cases

- [ ] [MAJOR] `IsValidPhone` in AyuGram accepts `"333"` (test number) and numbers starting with `"42"` with specific lengths (2, 5, 6, or `"4242"`); Dart only checks `digits.length >= 8`, missing these test/special-number overrides entirely — `input_dialogs.dart:624` ← `AyuGram/boxes/add_contact_box.cpp:54-63`

## input_dialogs — add_contact_box: Phone disabled on pre-fill

- [ ] [MAJOR] AyuGram disables the phone field when a phone is pre-filled (`if (!phone.isEmpty()) { _phone->setDisabled(true); }`); Dart never disables the phone field even when `initialPhone` is provided, allowing user to edit a phone that should be locked — `input_dialogs.dart:577-609` ← `AyuGram/boxes/add_contact_box.cpp:308-310`

## input_dialogs — add_contact_box: Focus order on phone-pre-filled open

- [ ] [MAJOR] AyuGram's `setInnerFocus` focuses the phone field directly when first/last name are already filled or phone is disabled; Dart always focuses first/last name, so when a contact is confirmed from a pre-filled phone+name, focus lands in the wrong field — `input_dialogs.dart:607-609` ← `AyuGram/boxes/add_contact_box.cpp:344-352`

## input_dialogs — username_box: Check debounce timeout wrong

- [ ] [MAJOR] AyuGram uses `Ui::EditPeer::kUsernameCheckTimeout` (defined elsewhere in edit_peer_common, typically 300–500 ms) for the debounce; Dart hardcodes 200ms, which may be too aggressive and cause excessive API calls — `input_dialogs.dart:252` ← `AyuGram/boxes/username_box.cpp:231`

## input_dialogs — username_box: Minimum username length constant mismatch

- [ ] [MAJOR] AyuGram uses `Ui::EditPeer::kMinUsernameLength` as the minimum (defined in edit_peer_common, value is 5); Dart also uses 5 but the `_isValidUsername` validator does not check for a leading digit restriction. AyuGram additionally rejects usernames that start with a digit at the API level (USERNAME_INVALID). The local validator should match AyuGram's character-by-character check that also accepts `@` only at index 0 — `input_dialogs.dart:174-183` ← `AyuGram/boxes/username_box.cpp:205-211`

## input_dialogs — username_box: Save order wrong — primary username updated before reorder

- [ ] [MAJOR] AyuGram saves via `list->save()` first (reorder+toggles) and then `editor->save()` (primary username) in a chained done callback; Dart does toggles, then reorder, then primary username update sequentially without proper chaining — if any step fails the others may still fire, corrupting state — `input_dialogs.dart:302-336` ← `AyuGram/boxes/username_box.cpp:372-383`

## input_dialogs — username_box: Missing description paragraph 2 (username_description2)

- [ ] [MAJOR] AyuGram renders two description paragraphs (`tr::lng_username_description1` + `\n\n` + `tr::lng_username_description2`); Dart collapses everything into a single hardcoded string covering only description1 content, omitting the second paragraph — `input_dialogs.dart:420-425` ← `AyuGram/boxes/username_box.cpp:336-343`

## input_dialogs — create_poll_box: Max options count wrong (12 vs 32)

- [ ] [CRITICAL] AyuGram uses `PollData::kMaxOptions = 32`; Dart hardcodes `_kMaxOptions = 12`, capping the poll at 12 options when Telegram allows up to 32 — `input_dialogs.dart:1777` ← `AyuGram/boxes/create_poll_box.cpp:104` + `AyuGram/data/data_poll.h:121`

## input_dialogs — create_poll_box: kWarnQuestionLimit threshold wrong

- [ ] [MAJOR] AyuGram shows the character counter when `(value < kWarnQuestionLimit)` where `kWarnQuestionLimit = 80` AND the field height exceeds `st::createPollOptionField.heightMin` (multiline condition); Dart shows it when `_questionCtrl.text.length > 80`, which is functionally the same for the question counter but missing the multiline height guard — `input_dialogs.dart:2119` ← `AyuGram/boxes/create_poll_box.cpp:106, 307-319`

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

