# GUI Audit — Cycle 1 Phase Ayugram (2026-05-15 11:05)

## Code Comparison (Dart vs AyuGram)

# bridge — No issues found

## Summary

The FFI/WASM bridge implementation is production-quality with no critical, major, or minor defects found.

### What was audited:

- **bridge.dart** (lines 1-35): Main bridge facade
- **bridge_stub.dart** (lines 1-26): Stub implementation for platform detection
- **bridge_ffi.dart** (lines 1-184): Native FFI implementation (Linux, macOS, Windows, Android)
- **bridge_web.dart** (lines 1-57): WASM implementation via JS interop
- **engine_service.dart** (initialization section): Bridge integration and wiring
- **app_state.dart** (line 2436): Engine initialization in app startup

### Findings:

✅ **No placeholders or stubs** — The stub.dart is a proper platform-detection fallback, not a placeholder implementation  
✅ **No TODO/FIXME/HACK comments** — Code is complete  
✅ **Backend wiring is complete** — Bridge is properly initialized, events are listened to, and engine calls flow through correctly  
✅ **Memory management is correct** — Proper use of calloc/free (FFI) and malloc.free (event callbacks)  
✅ **Event handling is robust** — Broadcast streams, NativeCallable.listener for thread-safe Go callbacks  
✅ **Isolation for async calls is correct** — Isolate.run properly handles blocking FFI operations  
✅ **WASM implementation is sound** — JS interop correctly delegates to Go WASM exports  
✅ **No hardcoded mock data** — All data flows from the engine

### Architecture verification:

- Conditional imports (`if (dart.library.ffi)` / `if (dart.library.js_interop)`) correctly select platform implementations
- BridgeImpl interface is consistently implemented across all three variants
- Synchronous `call()` and asynchronous `callAsync()` APIs are properly separated
- Event callback marshaling from Go to Dart handles thread boundaries correctly (NativeCallable.listener, not Pointer.fromFunction)
- Library path resolution for each platform (Linux: libcores.so, macOS: libcores.dylib, Windows: cores.dll, Android: libcores.so) is correct

**Status: READY FOR PRODUCTION** ✓


# notification_types.dart — No issues found

Audited against AyuGram Desktop notification composition logic (notifications_manager.cpp, data_media_types.cpp, notifications_manager_default.cpp).

## Summary
- **Data classes** (NotificationData, NotificationContent, NotificationSettings) are correctly structured
- **Composition functions** (_composeTitle, _composeSubtitle, _composeBody, etc.) correctly mirror AyuGram's behavior
- **Message type handling** (12 types: image, video, audio, voice, video message, sticker, GIF, file, poll, location, contact, invoice) — all complete
- **Special cases** (forward messages, reactions, poll votes, spoilers, login code masking) — all implemented
- **Privacy levels** (previewName, previewText) — correctly enforced
- **Integration** — correctly called from notification_system.dart lines 463-470

## Detailed verification

### Composition logic
- Line 261-284 (_composeTitle): Matches AyuGram's addTargetAccountName flow + reminder/topic handling
- Line 286-303 (_composeSubtitle): Correctly shows reactor/sender names conditionally
- Line 305-331 (_composeBody): Correct priority (poll vote → reaction → forward → regular text)
- Line 333-369 (_messageTextForType): All 12 media types match AyuGram's notificationText() implementations

### Spoiler & privacy
- Line 371-374 (_applySpoiler): Matches AyuGram line 93-98, uses ▚ character, 40-char cap
- Line 376-380 (_maskLoginCodes): Regex pattern for 3-8 digit codes with optional dashes, sender ID 777000
- Line 531-546 (shouldHideReplyButton): Correctly hides for reactions, poll votes, passcodeLock, scheduled, slow mode, channels, requiresStars

### Data model
- 67 fields in NotificationData — complete + copyWith() pattern
- NotificationSettings with 21 options — complete
- All defaults reasonable (volume=100, maxNotificationCount=3, corner=bottomRight)

**Status: READY FOR PRODUCTION**


# bridge_ffi — No issues found

**File:** `dart/lib/bridge/bridge_ffi.dart`

**Audit Summary:** Complete FFI bridge implementation with proper memory management, lifecycle handling, and event forwarding.

## Analysis

### Code Quality ✓
- No TODO/FIXME/HACK comments
- No stub implementations or placeholders
- No hardcoded fake data or mock objects
- All functions have complete, working implementations

### Memory Management ✓
- Input buffer allocated and freed correctly (lines 127-129, 148)
- Output length pointer allocated and freed correctly (lines 131, 149)
- Go-allocated result pointer freed after copying (lines 142-145)
- Event data properly freed after copying (lines 174-175)
- All allocations in try-finally blocks ensuring cleanup on errors

### Lifecycle Management ✓
- Idempotent `init()` with guard clause (line 50)
- Proper initialization check before operations (lines 70-71, 78-79)
- Clean `dispose()` with early return if not initialized (line 86)
- Stream and callable properly closed (lines 89-90)

### Event Handling ✓
- NativeCallable.listener correctly handles cross-thread callbacks (line 182)
- Events properly copied before freeing Go memory (lines 174-175)
- Broadcast stream allows multiple listeners (line 166)
- Zero-length event check prevents invalid memory access (line 169)

### Platform Support ✓
- Linux, macOS, Windows, and Android paths properly resolved (lines 93-118)
- Library reuse in Isolate.run avoids redundant loading (lines 155-156)
- Fallback library names for system library paths

### Error Handling ✓
- Explicit StateError for uninitialized bridge access
- Explicit UnsupportedError for unknown platforms
- Null check for null pointers (line 137)
- Empty response on zero-length result (lines 137-139)

## Conclusion

This FFI bridge is a well-engineered, production-ready implementation with no critical, major, or even minor issues. It correctly manages memory across C/Go/Dart boundaries, handles threading safely, and implements both synchronous and asynchronous calling patterns.

# chat_state — Audit

# theme_file.dart — Theme File Parsing & Caching

## Issues Found


## Data Flow Check

Theme caching is **completely broken**:
1. `buildThemeCache()` calls `getCrc32()` which doesn't exist → runtime error
2. `validateThemeCache()` calls `getCrc32()` which doesn't exist → runtime error  
3. `saveThemeCache()` silently fails on file I/O errors → checksums never persist
4. `loadThemeCache()` reads checksums that were never saved → always null/default

Background images are **not validated**:
- No size checks before storing as `Uint8List`
- No format validation (could be arbitrary binary data)
- No decoding attempt to verify validity
- Could be exploited to exhaust memory

## Summary

This is a **data layer module with 5 critical/major issues**:
1. Theme caching feature is completely non-functional (missing getCrc32)
2. Background image handling lacks all safety validations present in AyuGram
3. Error handling is too broad and silent, making debugging impossible

# theme_preview — Audit findings vs AyuGram Desktop

## MAJOR Issues


## Summary

The Dart implementation uses pure custom Canvas painting for all UI elements, while AyuGram Desktop uses the theme style system for icons, buttons, and images. This means:

1. **Photo placeholders won't match actual theme images** — gradient instead of themed wallpaper
2. **Icons are frozen in code** — won't update if theme icon styles change
3. **Buttons/emoji won't scale** — hardcoded sizes instead of style-driven dimensions
4. **No animation** — microphone is static where AyuGram shows animated

The preview will give users an inaccurate impression of how their theme will actually look in the real app.


# wallpaper — Pattern overlay & gradient rendering bugs

- [x] [CRITICAL] Opacity clamping breaks negative intensity patterns — `wallpaper.dart:262` clamps all pattern opacity to [0.0, 1.0], so negative intensity values (-100 to 0) become 0. This breaks the entire negative pattern rendering path. For intensity=-50, patternOpacity should be -0.5 to signal the negative branch in _PatternOverlay, but it gets clamped to 0.0. Compare: `data_wall_paper.cpp:252-257` shows patternIntensity() returns raw intensity (-100..100), and patternOpacity() = intensity/100, with no clamping. ← `wallpaper.dart:262`

- [x] [CRITICAL] ShaderMask approach for positive patterns is incorrect rendering technique — `wallpaper.dart:484-493` uses ShaderMask with BlendMode.softLight to apply the pattern. ShaderMask does NOT use blend modes — it only masks pixels. The correct approach (from AyuGram `chat_theme.cpp:1103-1133`) is:
  1. Draw the gradient background
  2. Use CustomPaint with QPainter::setCompositionMode(SoftLight)
  3. Draw the pattern image at the calculated opacity
  The current ShaderMask + white LinearGradient produces no pattern effect. ← `wallpaper.dart:484-493` ← `chat_theme.cpp:1116-1119`

- [x] [MAJOR] Missing gradient dithering for multi-color backgrounds — AyuGram `chat_theme.cpp:1113` dithers gradients when colors.size() > 1 to avoid banding. Dart _TwoColorGradient and _MultiColorGradient use plain LinearGradient/custom painter with no dithering. This affects visual quality of 2+ color gradients. ← `wallpaper.dart:210-220` ← `chat_theme.cpp:1112-1114`

- [x] [MAJOR] Gradient rotation passed for 3+ color gradients, should be 0 (dynamic) — `wallpaper.dart:252` passes gradientRotation to _MultiColorGradient for all cases. AyuGram `data_wall_paper.cpp:260-263` returns 0 for 3+ colors ("rotation value is dynamic"), only returns stored rotation for 1-2 colors. This means 3+ color gradients use wrong static rotation instead of animating. ← `wallpaper.dart:252` ← `data_wall_paper.cpp:260-263`

- [x] [CRITICAL] Missing pattern inversion logic for dark backgrounds — AyuGram `chat_theme.cpp:925-929` calls IsPatternInverted() which checks if background is dark; if so, InvertPatternImage() converts pattern to grayscale. Dart _PatternOverlay has no inversion logic. Dark-background patterns will render incorrectly/invisibly. ← `wallpaper.dart:474-506` ← `chat_theme.cpp:925-929, 1156-1171`

- [x] [MAJOR] Wrong composition mode for negative patterns — `wallpaper.dart:501-503` uses ColorFilter with BlendMode.dstIn. AyuGram `chat_theme.cpp:1121-1127` uses QPainter::CompositionMode_DestinationIn with custom pattern drawing, then fills with black at opacity (1.0 + patternOpacity). The ColorFilter approach doesn't match the C++ composition semantics. ← `wallpaper.dart:501-503` ← `chat_theme.cpp:1120-1128`

- [x] [MAJOR] Pattern drawn with wrong fit mode — `wallpaper.dart:477` uses BoxFit.cover for pattern image, but the pattern bytes should tile/repeat at original resolution or be scaled to match the background size. AyuGram prepares pattern at the exact background size (`chat_theme.cpp:1149`). ← `wallpaper.dart:475-481` ← `chat_theme.cpp:1148-1150`

- [x] [MINOR] Comment on line 496 references non-existent spec sections — "§25.8.4 / §25.17.4" don't exist in SPEC.md. Remove or verify. ← `wallpaper.dart:496`


# active_sessions_screen — Audit Findings


# admin_tools — Audit Findings

## admin_tools — _MemberTabBody / _showAddMemberDialog

# bridge_stub — No issues found

## Summary

The `bridge_stub.dart` file is correctly implemented as a fallback implementation for the platform-specific bridge. The file:

1. **Conditional import hierarchy is correct:** `bridge.dart` uses `if (dart.library.ffi)` to select `bridge_ffi.dart` on native platforms and `if (dart.library.js_interop)` to select `bridge_web.dart` on web. Only if both conditions fail does it fall back to `bridge_stub.dart`.

2. **Interface is correct:** The `BridgeImpl` class in the stub matches the signature of implementations in both `bridge_ffi.dart` and `bridge_web.dart`:
   - `events` property returns `Stream<Uint8List>` 
   - `isInitialized` property returns `bool`
   - `init()`, `call()`, `callAsync()`, `dispose()` methods all present

3. **Stub behavior is correct:**
   - `events` returns `const Stream.empty()` (appropriate for unused stub)
   - `isInitialized` returns `false` (correct default for uninitialized stub)
   - `init()`, `call()`, `callAsync()` throw `UnsupportedError` (prevents accidental use)
   - `dispose()` is empty (no resources to clean up in a stub)

4. **No placeholders or unimplemented features:** The stub is explicitly designed as a fallback error state, not as a partially-implemented feature.

5. **Usage is correct:** `EngineService` initializes the `Bridge` correctly, and the conditional imports ensure platform-specific implementations are selected before the stub fallback.

**Result:** ✅ This is a properly-designed fallback stub. No issues to report.

# auth_screen — Auth screen audit


# ayu_appearance_page — Audit Findings





# ayu_chats_page — Critical structural gaps vs AyuGram source

## Missing UI Controls (Feature Hidden from User)


## Implementation Differences


## Root Cause

Dart implementation appears to be a UI-only shell that:
1. Receives all settings from AppState (correctly passes them to _MessagePreview widget)
2. But provides NO UI controls to change: replaceMarksWithIcons, deletedMark, editedMark, semiTransparentDeletedMessages
3. Settings are read-only from AppState's defaults and cannot be modified by user

This blocks users from accessing 4 major customization features that are fully implemented in AyuGram Desktop.

## Verification

- AyuGram source: `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp`
- Header: `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.h` (via cpp includes)
- Settings definitions: `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/ayu/ayu_settings.h:276,300-302,452-453,500-505,622,645-647`
- MessagePreview impl: `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/ayu/ui/components/message_preview.cpp:52-235`

# ayu_section_builder — Audit Findings

## Reference files
- Dart: `dart/lib/ui/ayu_section_builder.dart`
- C++: `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/ayu_builder.cpp`
- C++: `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_ayu_utils.cpp`
- Style: `AyuGramDesktop/Telegram/SourceFiles/settings/settings.style`
- Style: `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/ayu_styles.style`


# ayu_toggle — No issues found

## Audit Summary
The `ayu_toggle.dart` implementation is a faithful Dart/Flutter port of the AyuGram Desktop ToggleView widget. All visual, behavioral, and animation logic matches the C++ reference implementation.

## Verification Details

### ✓ Constants Match Exactly
- `_border = 2.0` ↔ `widgets.style:880` border: 2px
- `_diameter = 14.0` ↔ `widgets.style:882` diameter: 14px (material)
- `_defDiameter = 16.0` ↔ `widgets.style:873` defaultToggleDiameter: 16px
- `_width = 14.0` ↔ `widgets.style:883` width: 14px
- `_matShift = -2.0` ↔ `widgets.style:881` shift: -2px (material)
- `_defShift = 1.0` ↔ `widgets.style:872` defaultToggleShift: 1px
- `_animPadding = 2.0` ↔ `widgets.style:884` animPadding: 2px
- `Duration(milliseconds: 150)` ↔ `widgets.style:879` duration: 150

### ✓ Animation Logic Correct
- initState: `_controller.value = widget.value ? 1.0 : 0.0` — matches AyuGram initialization (line 59-60 in checkbox.cpp)
- didUpdateWidget: `forward()` on value=true, `reverse()` on value=false — matches AyuGram setChecked (line 57-62)
- Material curve: `Curves.easeOutCubic` ↔ `checkbox.cpp:62` `anim::easeOutCubic`
- Non-material curve: `Curves.linear` ↔ `checkbox.cpp:62` `anim::linear`

### ✓ Paint Logic Verified
**Track (rounded rect):**
- Position: `(_border + switchShift, _border + switchShift)` ↔ `checkbox.cpp:118`
- Size: `(fullWidth - 2*switchShift, innerDiameter)` ↔ `checkbox.cpp:118`
- Radius: `innerDiameter / 2` ↔ `checkbox.cpp:116`
- Color: animates from `palette.checkboxFg` to `palette.windowBgActive` ↔ `checkbox.cpp:120`

**Thumb (ellipse):**
- Position: `toggleLeft = _border + (fullWidth - switchDiam) * t` ↔ `checkbox.cpp:117`
- Size: `switchDiam × switchDiam` ↔ `checkbox.cpp:119`
- Fill: `palette.windowBg` (constant) ↔ `checkbox.cpp:135`
- Border: `fgColor` (animated) ↔ `checkbox.cpp:132-134`
- Border width: `_border` (2.0) ↔ `checkbox.cpp:133`

**Material Deflation:**
- Deflates thumb by `_animPadding * (1 - t)` ↔ `checkbox.cpp:124-125` `anim::interpolateToF(_st->animPadding, 0, toggled)`
- Shrinks by full 2px at t=0, zero at t=1 ✓

### ✓ State Management
- `onTap` callback: `widget.onChanged?.call(!widget.value)` — proper negation ✓
- `shouldRepaint`: checks `t`, `fgColor`, `bgColor` — sufficient for painter output ✓
- Canvas lifecycle: `save()`/`restore()` — proper cleanup ✓

### ✓ No Placeholders or Stubs
- No empty callbacks
- No TODO/FIXME comments
- No hardcoded test data
- No "coming soon" feedback
- All methods fully implemented

### Optional Features Not in Scope
The following AyuGram features are intentionally omitted (not critical for base toggle):
- Locked state with lock icon (`checkbox.cpp:141-143`)
- X/V animation icons (`checkbox.cpp:145`)
- RTL layout handling via `style::rtlrect` (Flutter's Directionality handles this layer)

## Conclusion
**Status: ✓ PASS — No issues found**

The widget is production-ready and accurately implements the AyuGram Desktop toggle specification.

# call_screen — GroupCallPanel & MinimisedCallBar audit


# calls_screen — Audit Findings

## calls_screen — Calls box, group call list, call history, conference invite, call settings

# chat_export — Export Panel Audit



## chat_settings_screen — Chat Settings Screen Audit

# chat_switch_overlay — Audit Findings


# chat_view — Backend wiring stubs, missing user photos


# choose_datetime_box — Audit vs AyuGram Desktop

## CalendarBox

# color_picker_box — Color editor box audit

Reference: `color_editor.cpp` + `color_picker.cpp` in AyuGramDesktop.
The Dart file implements `ColorEditor::Mode::RGBA` layout (HSV picker, vertical hue slider, horizontal opacity slider, field column).

---


# compose_entities — Hardcoded theme colors not matching Telegram



# confirm_box — Audit Findings

## Summary

`confirm_box.dart` implements the full box/dialog infrastructure: generic confirm box, delete/leave confirm, single-choice radio box, permission dialogs, screen-share chooser, and the full report flow. The generic confirm and delete boxes are largely correct. The report flow and some visual details have critical and major issues.


# contacts_screen — Audit Findings

# edit_forum_topic_box — Audit findings

# edit_mark_box — Remaining issues


# emoji_panel — Audit Findings

## emoji_panel — GIF/Sticker/Emoji panel full audit

# ayu_filter — Filter engine audit

# emoji_status_widget — Audit Report

## Summary
The `EmojiStatusWidget` is a stateful widget that displays emoji status icons (standard, collectible, or userpic). It manages custom emoji caching, handles Lottie animations, and supports power-saving mode. Overall integration is solid with proper resource lifecycle management. However, there is a **CRITICAL missing feature** in collectible emoji rendering.

---

## Issues Found

### [CRITICAL] Collectible emoji animation missing — `emoji_status_widget.dart:222-230` ← `AyuGramDesktop/Telegram/SourceFiles/ui/effects/premium_stars_colored.cpp:entire class`

**Description:** 
AyuGram renders collectible emojis with **animated star particles** around the emoji, using the `centerColor` and `edgeColor` to create a gradient for the particles. The Dart code only applies a static `ShaderMask` with `RadialGradient` to colorize the emoji itself — no animation layer.

**AyuGram behavior** (lines 10-40 in premium_stars_colored.cpp):
- `CollectibleEmoji` class wraps the inner emoji
- Renders animated stars via `ColoredMiniStars` with `paint()` method
- Uses gradient stops created from `centerColor`/`edgeColor`
- Continuously animates particles unless paused/power-saving enabled

**Dart code** (lines 222-230):
```dart
if (_isCollectible && _collectibleCenterColor != null && _collectibleEdgeColor != null) {
  content = ShaderMask(
    shaderCallback: (bounds) => RadialGradient(
      colors: [_collectibleCenterColor!, _collectibleEdgeColor!],
    ).createShader(bounds),
    blendMode: BlendMode.srcATop,
    child: content,
  );
}
```
Only applies static gradient mask — no animated stars.

**Impact:** Collectible emoji status visually incorrect. Users won't see the animated particle effect that identifies collectible emojis in AyuGram.

---

### [MAJOR] Userpic emoji status mode unclear — `emoji_status_widget.dart:235-254` ← `no AyuGram source found`

**Description:**
The widget supports a `userpic:` prefix in `emojiStatusId` (line 100-102), which triggers `_buildUserpicStatus()` (line 235-254). This branch:
- Reads the active account's avatar from disk
- Displays it in a circle with fallback icon
- No emoji rendering involved

**Concern:** This mode doesn't exist in AyuGram Desktop source. It appears to be a custom uniclient feature. Verify this is intentional and not a bug. If it's supposed to show the account's userpic with an emoji overlay, that's not implemented.

**Current behavior:**
```dart
return ClipOval(
  child: Image.file(
    file,
    width: s,
    height: s,
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => _userpicFallback(s),
  ),
);
```

---

## Verification Checklist

- [x] **Emoji Status Parsing** — Three cases handled correctly: `collectible:`, `userpic:`, and document ID (lines 82-108)
- [x] **Cache Lifecycle** — Properly acquired/released with listener attachment/detachment (lines 43-80)
- [x] **Lottie Support** — Gzip decompression, controller lifecycle, looping (lines 146-169)
- [x] **Static Images** — Webp images with `cacheWidth`/`cacheHeight` for memory optimization (lines 204-214)
- [x] **Fallback Chain** — Correct: file → thumb → fallback icon (lines 218-221, 268-282)
- [x] **Power Saving** — Correctly disables animations when flag is set (lines 152-155, 187)
- [x] **Color Parsing** — Hex color parsing handles 6-digit and 8-digit formats (lines 111-117)
- [x] **Backend Wiring** — Cache properly batches requests and sends to engine (custom_emoji_cache.dart, verified)
- [x] **Theming** — Consistent fallback color `0xFF6C3BEB` (lines 262, 288)

---

## Recommendations

1. **Implement animated stars for collectible emoji** (CRITICAL):
   - Port `CollectibleEmoji` wrapper logic from `premium_stars_colored.cpp`
   - Create a `CollectibleEmojiWidget` that layers animated particles over the base emoji
   - Respect power-saving mode to disable animations
   - Use the `centerColor` and `edgeColor` to generate gradient stops for particles

2. **Clarify userpic emoji status** (MAJOR):
   - Confirm with codebase owner if this is intentional
   - If it should show avatar + emoji, implement the emoji rendering layer
   - If it's unused, remove the branch entirely (ZERO placeholders rule)

3. **Document collectible color parsing** (MINOR):
   - The `collectible:docId:color1:color2` format is custom (not in AyuGram)
   - Add comments explaining the format or link to spec documentation

---

## Code Quality Notes

✅ **Strengths:**
- Proper resource cleanup (dispose, cache release, listener removal)
- Memory optimization with `cacheWidth`/`cacheHeight`
- Correct device pixel ratio scaling
- Graceful fallback chain (file → thumb → icon)
- Backend integration via proper engine service calls

⚠️ **Missing Feature (not a code quality issue):**
- Collectible emoji animation layer

# hamburger_drawer — Audit vs AyuGram Desktop


# info_panel — Audit Findings

## Cover / Header


## Members Section



## Statistics Page


# input_dialogs — Audit Findings

---

## _AddContactBoxContent



---

---


# emoji_data — Critical emoji validation & missing backend wiring

## Issues Found

## No Additional Issues

The following aspects match or are acceptable:
- ✅ Exact keyword filtering logic (lines 691-698 match emoji_keywords.cpp:55-76)
- ✅ Postfix application (lines 679-687 match emoji_keywords.cpp:47-53)
- ✅ Search limit defaults (30 matches typical UI)
- ✅ Binary search on sorted keys (lines 856-865)
- ✅ Deduplication by seen set (line 817)

## Summary

The emoji picker is **functionally broken in two ways:**

1. **Legacy fallback is severely degraded:** The validation bug at line 652-675 filters `kEmojiSuggestions` from ~640 emoji down to maybe 50-100, removing common emoji like 👋.
2. **Server keywords never load:** No bridge integration means the app never fetches localized keywords from Telegram, always using the broken fallback.

**Neither of these issues exist in AyuGram.** The client comparison shows AyuGram has full backend integration and proper emoji validation via the built-in emoji table.

**Test to confirm:** Launch the app, open the emoji picker, search for "wave" or "hand". If no results or only 1-2 results appear instead of multiple hand emoji, the validation bug is active.

# media_viewer — Audit Findings









# popup_menu — Context menu widget audit

# privacy_settings_screen — Audit

## Summary

One CRITICAL issue found. All other features (cloud password flow, local passcode, blocked users, archive/mute, account TTL, top peers, global TTL, messages privacy, gift settings, birthday, P2P privacy, forward privacy preview) are properly wired to the engine.

---

## send_files_box — Send Files Dialog audit vs AyuGram C++ source


# shell — Audit findings

# stats_chart — Audit vs AyuGram Desktop

## Issues Found


# sticker_pack_viewer — Sticker Pack Viewer (modal bottom sheet)

# story_editor — Audit

# telegram_toast — Sticker toast dead code + wrong text + wrong position

- [ ] [CRITICAL] `showStickerToast` is defined but never called anywhere in the Dart codebase — the entire sticker/emoji pack toast is dead code with zero backend wiring; no engine event or sticker tap triggers it — `telegram_toast.dart:249` ← `history_view_sticker_toast.cpp:61` (`StickerToast::showFor`)

# telegram_tooltip — Audit Findings

- [ ] [MAJOR] Horizontal arrow-skip offset is missing. AyuGram offsets the tooltip horizontally by `arrowSkip = 66 px` when Left/Right bits are set (`left = areaMiddle + arrowSkip - width()` for Left; `left = areaMiddle - arrowSkip` for Right), plus `accumulate_min/max` clamps using `arrow + arrowSkipMin`. The Dart always centers the tooltip on `targetRect.center.dx - childSize.width / 2` with no such offset, so the arrow never aligns to the intended position relative to the target. — `telegram_tooltip.dart:400-420` ← `tooltip.cpp:371-381` + `widgets.style:1309`

# theme_editor — Theme Editor Screen

# titlebar — Custom titlebar for Linux window controls

- [ ] [MAJOR] Button icons rendered as hand-drawn geometry (lines/rects) instead of the actual PNG icon assets used by AyuGram — `titlebar.dart:308-338` (_TitleButtonIconPainter.paint) ← `AyuGram/Telegram/lib_ui/icons/title_button_minimize.png`, `title_button_maximize.png`, `title_button_restore.png`, `title_button_close.png` (and their @2x/@3x variants). AyuGram uses `IconButton` with real icon images defined in `widgets.style:1599-1667`; the custom-painted shapes won't match the pixel-accurate icon designs.

# web_app_panel — WebApp Panel Audit

# engine_models — Data model gaps in CachedMessage.fromJson and GroupCallParticipant

## Background

`engine_models.dart` contains two distinct parsing paths for `CachedMessage`:
1. **Proto path** — `engine_service.dart:5182–5317` constructs `CachedMessage` from protobuf fields. Correctly populates all fields including keyboard data, `altQualities`, `mediaRemoteRef`, `mediaExtra`.
2. **JSON event path** — `engine_service.dart:5034` → `MsgReceivedEvent.fromJson` → `CachedMessage.fromJson`. Used for real-time `msg_received` events. **Missing multiple fields.**

All CRITICAL issues below affect the JSON event path, meaning newly received messages (while the app is open) will silently lose data that existing cached messages have correctly.

---

## Findings

- [ ] [CRITICAL] `CachedMessage.fromJson` never parses `inlineKeyboard`, `replyKeyboard`, `keyboardHide`, `forceReply`, `forceReplyPlaceholder` from `extra`. The proto path (engine_service.dart:5312–5316) does parse them. Real-time received bot messages will show no keyboard buttons — `engine_models.dart:723` ← `AyuGram/Telegram/SourceFiles/history/history_item_reply_markup.h:29`

- [ ] [CRITICAL] `CachedMessage.fromJson` never parses `altQualities` from `extra`. Proto path uses `_altQualitiesFromParsed(extra)` (engine_service.dart:5252). Video quality selector will always be empty for newly received video messages — `engine_models.dart:723` ← `AyuGram/Telegram/SourceFiles/data/data_group_call.h:54`

- [ ] [CRITICAL] `CachedMessage.fromJson` never parses `mediaRemoteRef` or `mediaExtra` from the top-level JSON. Proto path reads them from `p.mediaRemoteRef`/`p.mediaExtra` (engine_service.dart:5239–5240). Sticker favouriting and GIF operations rely on these fields and will break for event-received messages — `engine_models.dart:723` ← `AyuGram/Telegram/SourceFiles/history/history_item_reply_markup.h:141`

- [ ] [CRITICAL] `CachedMessage.fromJson` never parses `unsupportedTTL` from `extra['unsupported_ttl']`. Proto path parses it (engine_service.dart:5250). Self-destructing media that has already been opened will be shown as normal media for real-time received messages — `engine_models.dart:723` ← `AyuGram/Telegram/SourceFiles/history/history_item_components.h`

- [ ] [MAJOR] `GroupCallParticipant` is missing `mutedByMe` field. AyuGram uses it in 8+ places in the members UI to show a different mute icon when the *local* user muted a participant vs the server muting them, and to determine the mute/unmute action label — `engine_models.dart:2160` ← `AyuGram/Telegram/SourceFiles/data/data_group_call.h:51`

- [ ] [MAJOR] `GroupCallParticipant` is missing `sounding` field (participant's audio is actively playing through local speakers). AyuGram tracks sounding rows in a `_soundingRowBySsrc` map and drives a `_soundingAnimation` from them. `isSpeaking` (`speaking`) is a different state — `engine_models.dart:2160` ← `AyuGram/Telegram/SourceFiles/data/data_group_call.h:46`

- [ ] [MAJOR] `GroupCallParticipant` is missing `ssrc` field. AyuGram maps SSRCs to participant rows (`_soundingRowBySsrc`, calls_group_members.cpp:201) to drive speaking animations and route tgcalls audio per-participant. Without it the audio engine cannot be wired to the UI — `engine_models.dart:2160` ← `AyuGram/Telegram/SourceFiles/data/data_group_call.h:44`

- [ ] [MAJOR] `GroupCallParticipant` is missing `additionalSounding` and `additionalSpeaking` fields for screen-share audio. AyuGram tracks these separately from main camera audio — `engine_models.dart:2160` ← `AyuGram/Telegram/SourceFiles/data/data_group_call.h:48`

- [ ] [MAJOR] `GroupCallParticipant` is missing `lastActive` field (last time participant spoke/was active). AyuGram uses it to sort participants list by recency — `engine_models.dart:2160` ← `AyuGram/Telegram/SourceFiles/data/data_group_call.h:42`

- [ ] [MAJOR] `GroupCallParticipant` is missing `date` field (Unix timestamp when participant joined the call). AyuGram shows "recently joined" based on this — `engine_models.dart:2160` ← `AyuGram/Telegram/SourceFiles/data/data_group_call.h:41`

- [ ] [MAJOR] `GroupCallInfo` is missing `scheduleDate` field. AyuGram tracks scheduled voice chats and shows a countdown timer before they start — `engine_models.dart:2199` ← `AyuGram/Telegram/SourceFiles/data/data_group_call.h:74`

- [ ] [MAJOR] `GroupCallInfo` is missing `origin` field (`Group`/`Conference`/`VideoStream`). AyuGram distinguishes these call types with different UI behaviour (`GroupCallOrigin` enum) — `engine_models.dart:2199` ← `AyuGram/Telegram/SourceFiles/data/data_group_call.h:63`

- [ ] [MAJOR] `CachedMessage.fromJson` never parses `senderNoForwards` from the JSON. Proto path reads it from `p.senderNoForwards` (engine_service.dart:5251). The "no-forwards" restriction for specific senders will not be enforced for real-time received messages — `engine_models.dart:723` ← `AyuGram/Telegram/SourceFiles/history/history_item.h`

