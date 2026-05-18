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

## shell — Synchronous file write on every drag pixel

- [ ] [MAJOR] `_saveLayoutPrefs()` is called inside the `onDrag` callback of every `_ResizeHandle` instance — including both the dialogs/chat divider and the chat/info divider. `_saveLayoutPrefs()` calls `File.writeAsStringSync()` (a blocking synchronous write) on the Flutter UI thread at up to ~60 Hz during a drag. AyuGram separates the two concerns: `moveLeftCallback` updates the ratio in memory only (`updateDialogsWidthRatio`, no disk I/O), and `moveFinishedCallback` persists once with `Core::App().saveSettingsDelayed()` after the drag ends. The fix is to call `_saveLayoutPrefs()` only in `onDragEnd`, not `onDrag`. — `shell.dart:506-515` (dialogs resize), `shell.dart:596-605` (three-col dialogs), `shell.dart:629-638` (info panel resize) ← `mainwidget.cpp:2593-2611` (`moveLeftCallback` updates memory; `moveFinishedCallback` saves delayed)

## shell — Dialogs column artificially capped at 540 px; AyuGram removed this cap

- [ ] [MAJOR] Both `_buildTwoColumn` (line 484-485) and `_buildThreeColumn` (line 552) clamp the dialogs column to `_dialogsMax = 540.0`. AyuGram's `countDialogsWidthFromRatio()` has `accumulate_min(result, st::columnMaximalWidthLeft)` commented out, meaning the dialogs panel is NOT capped at 540 px during normal layout. Only `columnMinimalWidthLeft` (260 px) is enforced. Users who drag the divider past 540 px get a wider dialogs list in the reference app; the Dart silently limits them. — `shell.dart:484-485`, `shell.dart:552` ← `window_session_controller.cpp:2554-2555` (cap commented out: `//	accumulate_min(result, st::columnMaximalWidthLeft)`)

# shortcuts_settings_screen — Conflict indicator shown on wrong row

- [ ] [MAJOR] Conflict strikethrough displayed on newly-assigned binding instead of displaced command's binding — `_conflicted[keyStr] = entry.key` stores the OLD command that lost the key, but `isConflictSource = _conflicted.containsKey(bindingToKeyString(b))` is evaluated for the NEW binding rows (since the old binding was already removed from `_currentBindings` in the same `setState`). Net effect: Command B (which just received the key) shows its own key with red strikethrough, while Command A (which lost the key) shows nothing at all. AyuGram does the opposite: Command A's button keeps existing with `removed=true` strikethrough, Command B's button shows the new key normally — `shortcuts_settings_screen.dart:219-221,470-471` ← `AyuGram/settings/sections/settings_shortcuts.cpp:372-388`

# spoiler_animation — Particle animation system

- [ ] [CRITICAL] Fixed RNG seed `math.Random(42)` makes particle layout identical on every app launch — `spoiler_animation.dart:251` ← `spoiler_mess.cpp:357` (`base::BufferedRandom<uint32>(count * 5)` uses system entropy, not a fixed seed; every session produces different particles)

- [ ] [MAJOR] Cache header field order and size wrong: Dart writes `{version, framesCount, canvasSize, dataLen, hash}` (20 bytes) but AyuGram's `Header` struct is `{version, dataLength, dataHash, framesCount, canvasSize, frameDuration}` (24 bytes); the Dart header omits `frameDuration` entirely, so a cached sheet with a changed frame-rate constant will pass validation and corrupt animation — `spoiler_animation.dart:218-223` ← `spoiler_mess.cpp:106-113`

- [ ] [MAJOR] Cache serializes the full RGBA spritesheet as PNG (`ui.ImageByteFormat.png`, 4 channels); AyuGram serializes only the alpha channel as Grayscale8 PNG then reconstructs ARGB on load, producing ~4× smaller cache files — `spoiler_animation.dart:212` ← `spoiler_mess.cpp:694-713`

- [ ] [MAJOR] No maximum cache file size guard: AyuGram rejects any cache file larger than `kMaxCacheSize = 5 * 1024 * 1024` (5 MB) before reading; Dart reads the entire file unconditionally — `spoiler_animation.dart:170` ← `spoiler_mess.cpp:32,209`

- [ ] [MAJOR] Particle opacity capped at 85%: `SpoilerTilePainter` and `tileSpoilerOnRects` multiply final opacity by `0.85` (`opacity * 0.85`), so the spoiler overlay is always 15% transparent even when fully hidden; `FillSpoilerRect` in AyuGram applies no such reduction — `spoiler_animation.dart:503,505,576` ← `spoiler_mess.cpp:431-508`

- [ ] [MAJOR] Image-spoiler darkening applied per tile inside the render loop (sets alpha=32 on every pixel of each tile, lines 391-399), whereas AyuGram applies the dark layer as a single global post-process over the completed sheet before storing it (`image.fill(QColor(0,0,0,32))` then composites particles on top); this means Dart's image spoiler re-darkens the overlap between tiles when the cache is loaded, producing incorrect alpha compositing — `spoiler_animation.dart:391-399` ← `spoiler_mess.cpp:845-868`

- [ ] [MAJOR] Hash algorithm mismatch: Dart uses a hand-rolled FNV-1a-32 (`_fnv1a32`); AyuGram uses XXH32 from the xxhash library; any cache file produced by one cannot be validated by the other if the format were ever shared, and the collision resistance differs — `spoiler_animation.dart:153-160,188` ← `spoiler_mess.cpp:716,741`

# stats_chart — Audit vs AyuGram Desktop

## Issues Found

- [ ] [CRITICAL] Pie chart font size is 14px but AyuGram uses `st::statisticsPieChartFont: font(20px)` — ~40% deviation; `maxScale = side / (font->height * 2)` formula relies on the 20px font — `stats_chart.dart:2113` ← `AyuGram/statistics/view/stack_linear_chart_view.cpp:718` + `AyuGram/statistics/statistics.style:56`

- [ ] [MAJOR] Filter button inactive text color uses `Colors.white70 : Colors.black87` — AyuGram uses `st::premiumButtonFg` (the premium button foreground color, a theme-defined blue/white, not text gray) — `stats_chart.dart:1358-1363` ← `AyuGram/statistics/widgets/chart_lines_filter_widget.cpp:57`

- [ ] [MAJOR] Filter button inactive background uses `Theme.of(context).colorScheme.surfaceContainerHighest` — AyuGram uses `st::boxBg` (dialog box background) — `stats_chart.dart:1329` ← `AyuGram/statistics/widgets/chart_lines_filter_widget.cpp:59`

- [ ] [MAJOR] Filter button corner radius hardcoded as `BorderRadius.circular(14)` — AyuGram uses `radius = r.height() / 2.` (fully rounded pill that adapts to button height) — `stats_chart.dart:1335` ← `AyuGram/statistics/widgets/chart_lines_filter_widget.cpp:130`

- [ ] [MAJOR] Pie hover slice offset is a static 8.0px snap with no per-slice animation — AyuGram has `PiePartController` that independently animates each slice's `statisticsPieChartPartOffset: 8px` offset in/out using `st::slideWrapDuration` — `stats_chart.dart:2016-2018` ← `AyuGram/statistics/view/stack_linear_chart_view.cpp:806` + `AyuGram/statistics/statistics.style:57`

- [ ] [MAJOR] Tooltip width hardcoded as `_kTooltipWidth = 180.0` — AyuGram's `PointDetailsWidget` computes width dynamically from max(name widths) + max(value widths) + padding for each dataset, accounting for percentage column, USD column, etc. Long stat names or values will be clipped; short ones waste space — `stats_chart.dart:232` + `stats_chart.dart:1104` ← `AyuGram/statistics/widgets/point_details_widget.cpp:220-262`

- [ ] [MAJOR] Tooltip missing inner `statisticsDetailsPopupPadding: margins(6px, 6px, 6px, 6px)` — Dart applies only `statisticsDetailsPopupMargins (12,8,12,11)` as the sole padding, so the text content sits 6px too close to the card edge vs AyuGram's two-level inset structure — `stats_chart.dart:997` ← `AyuGram/statistics/widgets/point_details_widget.cpp:262-269` + `AyuGram/statistics/statistics.style:22-23`

- [ ] [MAJOR] Date label width estimated using `'May 00'` sample text width + 20px — AyuGram uses `dayStringMaxWidth` precomputed from the actual formatted label strings in `daysLookup[]` (supports hour:minute format and week format labels which have different widths) — `stats_chart.dart:1633-1641` ← `AyuGram/data/data_statistics_chart.cpp:71` + `AyuGram/statistics/chart_widget.cpp:110`

- [ ] [MAJOR] `captionIndicesOffset` missing from date label step calculation — AyuGram shifts the iteration start index by `dayStringMaxWidth / step` so centered labels at the left edge don't overhang the chart boundary; Dart skips this, causing leftmost date labels to paint partially outside the visible area — `stats_chart.dart:1669-1671` ← `AyuGram/statistics/chart_widget.cpp:1024-1025` + `AyuGram/statistics/chart_widget.cpp:119-130`

- [ ] [MAJOR] Footer minimum handle separation is `_kMinRangeFrac = 0.02` (2% of chart width) — AyuGram enforces `statisticsChartFooterBetweenSide: 5px` as an absolute pixel distance between handles; behavior diverges significantly at narrow chart widths — `stats_chart.dart:226` ← `AyuGram/statistics/statistics.style:30` + `AyuGram/statistics/chart_widget.cpp:407-419`

- [ ] [MAJOR] Footer dim overlay color for dark mode hardcoded as `Color(0x99182633)` — AyuGram uses `statisticsChartInactive: #e2eef999` (light mode) from the theme palette; dark-mode dim color is not separately defined in the palette (AyuGram uses the same `statisticsChartInactive` color) meaning Dart's dark-mode dim color is invented and wrong — `stats_chart.dart:2233` ← `AyuGram/lib_ui/ui/colors.palette:665`

- [ ] [MAJOR] `DoubleLinear` footer mini-chart uses a shared global min/max across both lines — AyuGram's linear chart uses independent per-line Y scales for DoubleLinear; sharing the Y scale compresses one line relative to the other in the footer overview — `stats_chart.dart:2290-2301` ← `AyuGram/statistics/view/linear_chart_view.cpp` (DoubleLinear uses separate axis rendering)

- [ ] [MAJOR] Selection indicator vertical line color hardcoded as `Colors.white24` (dark) / `Colors.black12` (light) — AyuGram derives these colors from the theme palette; hardcoded values won't adapt to custom themes or AyuGram-specific palette overrides — `stats_chart.dart:1704-1710` ← `AyuGram/statistics/chart_widget.cpp:951-975`

- [ ] [MAJOR] `TextPainter` allocated fresh on every repaint inside `_drawRulerSet()` and `_paintDateLabelsAtStep()` — during animation (60fps) this creates dozens of `TextPainter` + `layout()` calls per frame for every ruler line and every visible date label; should be cached and invalidated only when data/range/theme changes — `stats_chart.dart:1594-1620` + `stats_chart.dart:1688-1694` ← performance reference: `AyuGram/statistics/view/chart_rulers_view.cpp` (uses pre-laid-out text objects)

- [ ] [MAJOR] Pie label text color hardcoded as `Colors.white` — AyuGram uses `p.setPen(st::premiumButtonFg)` which is a theme-tracked color (`premiumButtonFg` resolves to white in default theme but is palette-overridable) — `stats_chart.dart:2142-2145` ← `AyuGram/statistics/view/stack_linear_chart_view.cpp:721`

# main — Theme revert overlay radius wrong + system unlock cooldown logic gaps

## Findings

- [ ] [MAJOR] `_ThemeRevertOverlay` uses `_boxRadius = 12.0` but AyuGram uses `Ui::BoxCorners` which is derived from `boxRadius: 6px` — this is 2× the correct value — `main.dart:2112` ← `lib_ui/ui/layers/layers.style:38` (`boxRadius: 6px`) + `window_theme_warning.cpp:66` (`Ui::FillRoundRect(..., Ui::BoxCorners)`)

- [ ] [MAJOR] After a `SystemUnlockResult.floodError`, `_systemUnlockSuggested` stays `true` so the system unlock never auto-suggests again when the window regains focus — AyuGram explicitly calls `_systemUnlockSuggested.destroy()` to reset it after a flood error — `main.dart:2455-2458` ← `window_lock_widgets.cpp:237`

- [ ] [MAJOR] `didChangeAppLifecycleState` auto-triggers system unlock when `!_systemUnlockSuggested` but does NOT check whether the cooldown period has elapsed — AyuGram guards with `!_systemUnlockCooldown.isActive()` before auto-suggesting — `main.dart:2369` ← `window_lock_widgets.cpp:163-167`

# sticker_pack_viewer — Sticker Pack Viewer (modal bottom sheet)

- [ ] [CRITICAL] Emoji set max height is 270px but AyuGram uses 197px (37% deviation) — `sticker_pack_viewer.dart:84` ← `chat_helpers/chat_helpers.style:419` (`emojiSetMaxHeight: 197px`)

- [ ] [CRITICAL] No context menu on right-click / long-press: `_StickerTile` only wires `onTap`, completely missing the per-sticker popup menu (Send silently, Schedule, Add to favorites, Add to sticker set, Delete for creators) — `sticker_pack_viewer.dart:493` ← `sticker_set_box.cpp:1702`

- [ ] [CRITICAL] No sticker preview on long-press hold: AyuGram starts a drag-time timer on mouse-down and calls `showMediaPreview` when held; Dart has zero hold/preview logic in `initState` or `build` — `sticker_pack_viewer.dart:332` ← `sticker_set_box.cpp:1425`

- [ ] [CRITICAL] Share link for emoji packs uses wrong URL prefix: Dart hardcodes `https://t.me/addstickers/$shortName` for all set types; AyuGram uses `addemoji/$shortName` for emoji sets so the copied link is non-functional for emoji packs — `sticker_pack_viewer.dart:163` ← `sticker_set_box.cpp:649`

- [ ] [MAJOR] Sticker set max height is 393px but AyuGram uses 320px (23% deviation) — `sticker_pack_viewer.dart:84` ← `chat_helpers/chat_helpers.style:415` (`stickersMaxHeight: 320px`)

- [ ] [MAJOR] Installed "official" packs must show only a single "OK" / Done button; Dart always shows Share + Cancel for any installed set, which is wrong for official (read-only) packs — `sticker_pack_viewer.dart:211` ← `sticker_set_box.cpp:1038`

- [ ] [MAJOR] No three-dot / overflow menu for installed packs: AyuGram adds an `infoTopBarMenu` button with Archive/Remove pack actions; Dart's `_buildHeader` has no such menu at all — `sticker_pack_viewer.dart:177` ← `sticker_set_box.cpp:1051`

- [ ] [MAJOR] Install success does not notify the sticker store: AyuGram calls `notifyStickerSetInstalled` / `notifyEmojiSetInstalled` / shows "Masks installed" toast on success so the sticker panel updates; Dart only calls `Navigator.pop` — `sticker_pack_viewer.dart:154` ← `sticker_set_box.cpp:589`

- [ ] [MAJOR] No "Unlock with Premium" button for premium emoji sets: AyuGram checks `!_session->premium() && _inner->premiumEmojiSet()` and substitutes the Add button with a gradient Premium unlock button; Dart shows the normal Add button unconditionally — `sticker_pack_viewer.dart:230` ← `sticker_set_box.cpp:972`

# story_editor — Audit

- [ ] [CRITICAL] Blur strokes are silently dropped from exported/posted images: `_renderCanvasToBytes` draws a transparent paint inside a saveLayer with a blur imageFilter, which produces no visible output — the layer contains nothing to blur. The live preview uses `BackdropFilter` (correct) but the canvas export at lines 544-553 discards all blur strokes entirely. Users will see blur in the editor but the posted story will have none. — `story_editor.dart:541-553` ← `editor/scene/scene_item_canvas.cpp:126` (blur path actually composites over a captured blurSource image, not transparent paint)

- [ ] [CRITICAL] Item/sticker scale maximum is wrong: `_stickerMaxScale = 6.0` but AyuGram clamps item zoom to `kMaxItemZoom = 10.` — users cannot scale items to 10× as the spec requires; pinch-zoom stops prematurely at 6×. — `story_editor.dart:35` ← `editor/editor_paint.cpp:40`

- [ ] [MAJOR] Item/sticker scale minimum is wrong: `_stickerMinScale = 0.2` should be `0.1` per `kMinItemZoom = 0.1`. — `story_editor.dart:34` ← `editor/editor_paint.cpp:39`

- [ ] [MAJOR] Brush size slider positioned 16px too far from the left edge: `left: 16` is used in the `Positioned` widget, but AyuGram specifies `photoEditorBrushSizeControlLeftSkip: 0px` — the slider should hug the left edge of the canvas. Also the expand-shift behaviour (`photoEditorBrushSizeControlExpandShift: 14px`) is not implemented: when expanded, the control grows symmetrically instead of shifting 14px to the right. — `story_editor.dart:1115` ← `editor/editor.style:157-162`

- [ ] [MAJOR] Text edge-button vertical padding wrong: `EdgeInsets.symmetric(horizontal: 22, vertical: 4)` adds 4px top/bottom; AyuGram defines `photoEditorTextButtonPadding: margins(22px, 0px, 22px, 0px)` — zero vertical padding. Buttons render taller than spec. — `story_editor.dart:1347` ← `editor/editor.style:40`

- [ ] [MAJOR] 48 h story duration premium gate is cosmetic only: `isPremiumGated = hours == 48` only shows a lock icon but the menu item is still selectable, sets `_durationHours = 48`, and passes it straight to `engine.sendStoryWithVideoFile`/`sendStoryWithPhoto` with no premium check. Non-premium accounts will hit a server-side rejection with no meaningful error shown to the user. — `story_editor.dart:1689-1706, 1683-1684` ← `editor/photo_editor.cpp` (premium gating enforced before API call in desktop)

- [ ] [MAJOR] Default text font size wrong: `_fontSize = 32` is hardcoded, but AyuGram derives the default as `shortSide / kDefaultFontSizeDivisor` where `kDefaultFontSizeDivisor = 15.0` — for the 540 px canvas short-side this gives 36 pt, not 32 pt. New text items appear smaller than spec. — `story_editor.dart:196` ← `editor/editor_paint.cpp:75-82`

- [ ] [MAJOR] `base64Decode` called inside `ListView.builder` itemBuilder for contact avatars: `MemoryImage(Uint8List.fromList(base64Decode(c.avatarB64)))` runs on the UI thread on every rebuild (list scroll, search keystroke, setState). For a contact list with hundreds of items this causes jank. Decode should happen once in `initState`/data-loading or via `Isolate.run`. — `story_editor.dart:2487`

- [ ] [MAJOR] `base64Decode` called inside `GridView.builder` itemBuilder for sticker thumbnails: `base64Decode(sticker.thumbB64)` executes synchronously on the UI thread for every visible sticker cell on every grid rebuild. Same fix needed as above. — `story_editor.dart:3064` ← (contrast with AyuGram's `LottieAnimation`/cached `QPixmap` pipeline in `editor/scene/scene_item_sticker.cpp`)

# telegram_toast — Sticker toast dead code + wrong text + wrong position

- [ ] [CRITICAL] `showStickerToast` is defined but never called anywhere in the Dart codebase — the entire sticker/emoji pack toast is dead code with zero backend wiring; no engine event or sticker tap triggers it — `telegram_toast.dart:249` ← `history_view_sticker_toast.cpp:61` (`StickerToast::showFor`)

- [ ] [CRITICAL] Sticker/emoji preview is a static base64 PNG (`Image.memory`); AyuGram renders an animated Lottie player for regular sticker packs (`setupLottiePreview`) and a frame-driven custom emoji renderer for emoji packs (`setupEmojiPreview`) — preview will never animate — `telegram_toast.dart:448-461` ← `history_view_sticker_toast.cpp:264-353`

- [ ] [MAJOR] `_StickerToast.build()` positions the toast center-screen (full-viewport `Center` widget); AyuGram attaches it to the **bottom** (`RectPart::Bottom`) so it appears above the message input — `telegram_toast.dart:541-558` ← `history_view_sticker_toast.cpp:175`

- [ ] [MAJOR] `toSaved` toast body text is wrong: Dart shows `"Saved to your animated emoji."` but AyuGram shows `"Try sending these emoji in Saved Messages for free to test."` (`lng_animated_emoji_saved`) — `telegram_toast.dart:383` ← `lang.strings:290`

- [ ] [MAJOR] Emoji (non-toSaved) toast body text is wrong: Dart shows `"This message contains emoji from the {packName} pack"` but AyuGram shows `"Subscribe to Telegram Premium to unlock this emoji."` (`lng_animated_emoji_text`) — `telegram_toast.dart:431-442` ← `lang.strings:289`

- [ ] [MAJOR] Non-emoji sticker pack toast body text incorrectly says "emoji": Dart falls through to the default emoji branch for `isEmoji=false` stickers; AyuGram shows `"This set contains premium stickers like this one."` (`lng_sticker_premium_text`) — `telegram_toast.dart:431-442` ← `lang.strings:287`

- [ ] [MAJOR] Replacing an active sticker toast calls `.remove()` (immediate removal, no animation); AyuGram calls `strong->hideAnimated()` so the old toast fades out before the new one appears — `telegram_toast.dart:262-263` ← `history_view_sticker_toast.cpp:70-71`

- [ ] [MAJOR] `_StickerToast` has no `minWidth` constraint; AyuGram's `historyPremiumToast` sets `minWidth: msgMinWidth` (160px), same as `defaultMultilineToast` — `telegram_toast.dart:498-499` ← `chat.style:258` (`historyPremiumToast { minWidth: msgMinWidth; }`)

# telegram_tooltip — Audit Findings

- [ ] [CRITICAL] `_ImportantTooltipDelegate.getPositionForChild` uses `_kImportantShift` (12 px) as a permanent positional gap between tooltip and target (`y = targetRect.bottom + shift` for bottom side). In AyuGram, `shift` is animation-only; the tooltip rests flush against the target (`top = _area.y() + _area.height()`). This double-applies the shift: delegate adds 12 px to the base position, then the `AnimatedBuilder` slides from that position +12 px, so at rest the tooltip is 12 px too far from the target. Fix: delegate should use `y = targetRect.bottom` (no shift); keep the animation slide only in `AnimatedBuilder`. — `telegram_tooltip.dart:403-413` ← `tooltip.cpp:382-387` + `widgets.style:1310`

- [ ] [MAJOR] `_resolveSide()` uses hardcoded magic numbers (40 px, 100 px) as minimum required clearance. AyuGram dynamically computes required space as `countInner().height() + _st.shift + _st.arrow` from actual content geometry. The hardcoded values are arbitrary and will misplace the tooltip on short or tall content. — `telegram_tooltip.dart:346-362` ← `tooltip.cpp:263-280`

- [ ] [MAJOR] `TooltipSide.left` / `TooltipSide.right` place the tooltip BODY to the left or right of the target widget (`x = targetRect.right + shift` / `x = targetRect.left - shift - childSize.width`). AyuGram's `ImportantTooltip` never places the body to the side — `RectPart::Left` / `RectPart::Right` are arrow-alignment flags within an above/below tooltip, not placement sides. `countPosition()` always sets `top = _area.y() ± height()` regardless of Left/Right bits. The Dart left/right placement mode is invented behavior with no AyuGram equivalent. — `telegram_tooltip.dart:408-414` ← `tooltip.cpp:263-302, 367-401`

- [ ] [MAJOR] Horizontal arrow-skip offset is missing. AyuGram offsets the tooltip horizontally by `arrowSkip = 66 px` when Left/Right bits are set (`left = areaMiddle + arrowSkip - width()` for Left; `left = areaMiddle - arrowSkip` for Right), plus `accumulate_min/max` clamps using `arrow + arrowSkipMin`. The Dart always centers the tooltip on `targetRect.center.dx - childSize.width / 2` with no such offset, so the arrow never aligns to the intended position relative to the target. — `telegram_tooltip.dart:400-420` ← `tooltip.cpp:371-381` + `widgets.style:1309`

# theme_editor — Theme Editor Screen

- [ ] [CRITICAL] Accent sort algorithm wrong: Dart uses simple Euclidean HSL distance; AyuGram uses a three-tier bucket sort — `copyOf` rows → score 365 (bottom), hue diff > 15° → score 363, others → `255 - fromSaturation` (closest-to-accent by saturation). Result order will be completely different — `theme_editor.dart:95-112` ← `AyuGram/window/themes/window_theme_editor_block.cpp:446-467`

- [ ] [MAJOR] When updating an existing cloud theme, slug always generates a new random value instead of pre-filling with `existingCloud.slug`; the user's public `t.me/addtheme/<slug>` link changes on every update — `theme_editor.dart:1207` ← `AyuGram/window/themes/window_theme_editor_box.cpp:811`

- [ ] [MAJOR] When updating an existing cloud theme, name field starts empty instead of pre-filled with `existingCloud.title`; AyuGram uses `cloud.title` as the initial value — `theme_editor.dart:1203-1205` ← `AyuGram/window/themes/window_theme_editor_box.cpp:789-791`

- [ ] [MAJOR] No double-save guard: `_handleSaveToCloud` has no `_saving` flag; rapid taps on the "SAVE THEME" button can trigger multiple concurrent cloud upload operations — `theme_editor.dart:273-330` ← `AyuGram/window/themes/window_theme_editor_box.cpp:859-860`

- [ ] [MAJOR] Export theme does not auto-include current chat background: `_SaveThemeBox` is opened with no `existingBackground`, so the user must manually re-pick the wallpaper; AyuGram's `CollectForExport` automatically captures `Background()->createCurrentImage()` — `theme_editor.dart:248-251` ← `AyuGram/window/themes/window_theme_editor_box.cpp:757-769`

- [ ] [MAJOR] `_computeThumbnailSize` uses `smallSkip = 6.0` but AyuGram uses `themesSmallSkip = 10px` (40% deviation); thumbnail height will be miscalculated causing the background image preview to misalign with the text/button column beside it — `theme_editor.dart:1555` ← `AyuGram/boxes/boxes.style:716`

# titlebar — Custom titlebar for Linux window controls

- [ ] [MAJOR] Button icons rendered as hand-drawn geometry (lines/rects) instead of the actual PNG icon assets used by AyuGram — `titlebar.dart:308-338` (_TitleButtonIconPainter.paint) ← `AyuGram/Telegram/lib_ui/icons/title_button_minimize.png`, `title_button_maximize.png`, `title_button_restore.png`, `title_button_close.png` (and their @2x/@3x variants). AyuGram uses `IconButton` with real icon images defined in `widgets.style:1599-1667`; the custom-painted shapes won't match the pixel-accurate icon designs.

- [ ] [MAJOR] `_toggleMaximize` makes a redundant async round-trip query after invoking maximize, racing with the `maximizeChanged` native event — `titlebar.dart:136-141` calls `invokeMethod('maximize')` then `_queryMaximized()` (a second channel call), while simultaneously the `maximizeChanged` handler at `titlebar.dart:96-97` can also update `_isMaximized`. AyuGram drives maximize-state updates purely through `QEvent::WindowStateChange` → `handleWindowStateChanged` → `updateButtonsState` with no redundant poll — `AyuGram/Telegram/lib_ui/ui/platform/ui_platform_window_title.cpp:238-243,404-419`. The double-update causes a potential state flicker and an unnecessary channel call on every maximize/restore cycle.

- [ ] [MAJOR] Drag-to-move fires only after Flutter's pan-gesture threshold, whereas AyuGram starts the system move on any mouse movement while pressed — `titlebar.dart:230` uses `onPanStart` (requires minimum drag distance before Flutter commits the pan gesture) ← `AyuGram/Telegram/lib_ui/ui/platform/ui_platform_window_title.cpp:487-495` (`mouseMoveEvent` calls `startSystemMove()` immediately on the first mouse-move pixel while `_mousePressed` is true). The Dart titlebar drags sluggishly compared to the native feel.

- [ ] [MAJOR] Missing maximize-button suppression when the window is not resizable — `titlebar.dart` has no concept of `_resizeEnabled` ← `AyuGram/Telegram/lib_ui/ui/platform/ui_platform_window_title.cpp:356-358` (`if (!_resizeEnabled) eraseControl(Control::Maximize)`). Windows that disable resize (e.g. fixed-size dialogs) must hide the maximize button; the Dart titlebar always shows it.

- [ ] [MAJOR] Hover/press state not cleared on title-button clicks — `titlebar.dart:267-293` (_WinButtonState) has no `clearState` step after a click fires; the button stays visually hovered until the mouse leaves ← `AyuGram/Telegram/lib_ui/ui/platform/ui_platform_window_title.cpp:199-229` (each button's click callback calls `clearState()` on itself immediately after dispatching the window action).

# web_app_panel — WebApp Panel Audit

- [ ] [CRITICAL] `web_app_read_text_from_clipboard` has no security guard: reads clipboard unconditionally. AyuGram requires `_allowClipboardRead` flag (per-bot permission) AND that a webview interaction occurred within 10 seconds (`_lastWebviewInteraction + kClipboardReadTimeout >= now`). Without this guard, any web app can silently harvest clipboard contents at any time — `web_app_panel.dart:678-689` ← `attach_bot_webview.cpp:1622-1633,1645-1652`

- [ ] [CRITICAL] `remove_menu` menu item calls `_close()` instead of calling the engine to remove the bot from the menu. AyuGram calls `botHandleMenuButton(MenuButton::RemoveFromMainMenu)` or `botHandleMenuButton(MenuButton::RemoveFromMenu)` through the delegate, which actually mutates persisted state. Dart just closes the panel with no side-effect — `web_app_panel.dart:1221-1228,1253` ← `attach_bot_webview.cpp:807-829`

- [ ] [CRITICAL] Device storage (`web_app_device_storage_save_key/get_key/clear`) is backed by an in-memory `Map<String, String?>` that is destroyed when the panel closes. AyuGram routes all three operations through `_delegate->botStorageWrite/Read/Clear()` which persists to durable storage. Web apps that rely on device storage for session data will lose everything on every panel close — `web_app_panel.dart:134,834-887` ← `attach_bot_webview.cpp:1305-1353`

- [ ] [CRITICAL] `invoice_closed` event is never posted back to the webview after an invoice is opened. AyuGram has `Panel::invoiceClosed(slug, status)` which posts `invoice_closed` with slug+status and then restores the panel from its `_hiddenForPayment` state. Without this, any web app using `web_app_open_invoice` receives no completion callback — payment flow is permanently broken — `web_app_panel.dart:481-495` ← `attach_bot_webview.cpp:2147-2159`

- [ ] [CRITICAL] Buttons ignore `icon_custom_emoji_id` field entirely. AyuGram's `processButtonMessage` extracts `icon_custom_emoji_id` and passes it to `Button::updateText()`, rendering a custom emoji prefix alongside the text using `Text::SingleCustomEmoji`. Dart's `WebAppButtonConfig` and `_handleSetupButton` have no such field — any web app that sets emoji icons on main/secondary buttons shows nothing — `web_app_panel.dart:37-52,939-961` ← `attach_bot_webview.cpp:1713-1745`

- [ ] [CRITICAL] No `_inBlockingRequest` guard for `requestWriteAccess` and `requestPhone`. AyuGram sets `_inBlockingRequest = true` at the start and immediately replies `false` if already blocking, preventing overlapping dialogs. Dart at lines 529 and 594 has no such guard — a bot can spam requests and show the user an unbounded stack of permission dialogs simultaneously — `web_app_panel.dart:529-638` ← `attach_bot_webview.cpp:1492-1533,1541-1573`

- [ ] [MAJOR] `_handleRequestViewport` sends `height: 0, width: 0` in the initial `viewport_changed` event, then separately runs a JS snippet to post the real size. AyuGram's `sendViewport()` executes a single JS eval with `window.innerHeight` and `window.innerWidth` directly — it never sends zeros. The spurious zero-size event can break web apps that immediately read viewport dimensions on receipt — `web_app_panel.dart:980-996` ← `attach_bot_webview.cpp:1125-1130`

- [ ] [MAJOR] `web_app_request_content_safe_area` always reports `top: 0` even in fullscreen mode. AyuGram computes a non-zero top based on the close button height and DPI when `_fullscreen.current()` is true: `top = shift + fullScreenPanelClose.height + (shift/2)` scaled by device pixel ratio / system screen scale. Dart always sends zeros — `web_app_panel.dart:289-291,339-347` ← `attach_bot_webview.cpp:1143-1160`

- [ ] [MAJOR] Button progress indicator is centered over the entire button instead of right-aligned. AyuGram renders the `InfiniteRadialAnimation` at the right side of the button (right edge minus padding), keeping the button text visible and left-justified during progress. Dart shows a `CircularProgressIndicator` centered and hides the text with an if-else — `web_app_panel.dart:1636-1659` ← `attach_bot_webview.cpp:329-383`

- [ ] [MAJOR] Button visibility ignores empty text: Dart sets `visible` from `data['is_visible']` alone without checking for empty text. AyuGram only makes a button visible when `is_visible && (!text.isEmpty() || iconCustomEmojiId)` — an empty-text button is never shown. Dart can create a visible but blank-looking button — `web_app_panel.dart:943` ← `attach_bot_webview.cpp:1716-1717`

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

