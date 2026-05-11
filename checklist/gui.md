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


# ayu_forward — Forward state machine and intelligent chunking

# chat_state — State Management Audit

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

---

## Major Issues


---

## Minor/Cosmetic Issues

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


# admin_tools — Placeholders, missing wiring, and behavioral inaccuracies

## _EditAdminBox

## _EditRestrictedBox


## _AdminLogScreen / _AdminLogFilterDialog

## _MemberTabBody


## _InviteLinksBox


# advanced_settings_screen — Audit Findings

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

# call_screen — Group call panel, minimised call bar, screen-share chooser


# calls_screen — Audit Findings


# chat_settings_screen — Audit Findings

## chat_view — Placeholders, broken backend wiring, and behavioral inaccuracies


# color_picker_box — Color picker dialog vs AyuGram ColorEditor

## Reference
- Dart: `dart/lib/ui/color_picker_box.dart`
- AyuGram: `ui/widgets/color_editor.cpp` + `boxes/boxes.style`

---


# engine_service — Bridge/Service Layer Audit

## Summary

`engine_service.dart` is the Dart FFI bridge wrapper. No UI placeholders exist. Issues are all
backend-wiring correctness and performance. AyuGram reference used for protocol behavior
(`api/api_editing.cpp`, `apiwrap.cpp`, `data/data_forum_topic.cpp`).


## contacts_screen — stubs, broken backend wiring, missing DM creation, dropped comment








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

# ayu_filter — Regex filter engine audit


## Major Issues Found


## Warnings (Not showstoppers, but notable differences)


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

# hamburger_drawer — Critical wiring errors, wrong LRead/SRead semantics, positional bugs

# input_dialogs — Input Dialogs Audit

## Create Poll Box

- [x] [CRITICAL] Max options cap is 10 instead of 32 — Dart returns early at 10 options (`if (_optionCtrls.length >= 10) return`); AyuGram sets `kMaxOptionsCount = PollData::kMaxOptions = 32` — `input_dialogs.dart:1142` ← `AyuGram/boxes/create_poll_box.cpp:104` and `AyuGram/data/data_poll.h:121`

- [x] [CRITICAL] Quiz mode missing correct answer selection — Dart's `CreatePollResult` has only `quiz: bool` with no `correctOptionIndex`; AyuGram renders a radio button per option (`enableChooseCorrect`) when quiz mode is toggled so users pick which answer is correct — required by the Telegram API — `input_dialogs.dart:1092-1106,1257-1260` ← `AyuGram/boxes/create_poll_box.cpp:2601-2608`

- [x] [CRITICAL] Quiz solution/explanation field missing — AyuGram shows a dedicated `setupSolution` text field (up to `kSolutionLimit = 200` chars) when quiz mode is enabled; Dart has no such field, making quiz polls uncreatable with explanations — `input_dialogs.dart:1122-1301` ← `AyuGram/boxes/create_poll_box.cpp:1370-1433,2740-2846`

- [x] [CRITICAL] No question character limit — AyuGram enforces `kQuestionLimit = 255` chars and shows a warning at 80; Dart applies no limit to the question field — `input_dialogs.dart:1195-1198` ← `AyuGram/boxes/create_poll_box.cpp:103,1247` (`question->setMaxLength(kQuestionLimit + kErrorLimit)`)

- [x] [CRITICAL] No option character limit — AyuGram enforces `kOptionLimit = 100` chars per option and warns at 30; Dart applies no limit — `input_dialogs.dart:1213-1216` ← `AyuGram/boxes/create_poll_box.cpp:105,372` (`_field->setMaxLength(kOptionLimit + kErrorLimit)`)

# language_box — Language box audit


# emoji_data — Static emoji database vs. server-sourced

## Summary

The Dart emoji_data.dart implements a hardcoded static emoji search database, while AyuGram Desktop loads emoji keywords from Telegram's language pack servers. The Dart version works for basic emoji autocomplete but diverges significantly from AyuGram's architecture in data sourcing, language support, and recent emoji prioritization.

## Critical Issues


## Major Issues

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

# payment_panel — Audit findings


# peer_short_info — Peer Short Info Box Audit


# photo_crop_editor — Audit Findings


# privacy_settings_screen — Audit Findings

## CRITICAL



# Audit Chunk 7 — main.dart

Source: `/home/nako/Documents/uniclient/dart/lib/main.dart`
Ground truth: `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/`

---


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

