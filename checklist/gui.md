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






## theme revert — Enter key keeps theme; Escape reverts (correct), but no paint-event title/body layout


# reactions_detail — Audit Findings

## reactions_detail — Reactions detail panel (who reacted / who read)


# send_files_box — Audit Findings




# settings_screen — Audit Findings

## settings_screen — Main Settings Screen


# stats_chart — Audit findings

## stats_chart — statistics chart widget

# story_editor — Story Editor Layer

# telegram_toast — Toast widget audit


# theme_confirm_overlay — Behavioral mismatch on removal animation

## Issues Found


## Non-Issues (design differences appropriate for Flutter/mobile)

- Button layout: AyuGram uses bottom-right stacked layout (RoundButton, `st::defaultBox.buttonPadding`); Flutter uses side-by-side Row centered at bottom. This is appropriate responsive design for mobile/web vs desktop.
- Button type: AyuGram uses `Ui::RoundButton`; Flutter uses `TextButton`. Appropriate for Flutter Material Design.
- Colors: Hardcoded in Dart (0xFF3390EC, 0xFF40A7E3); AyuGram uses theme values (`st::boxBg`, etc.). Acceptable for single-theme app.
- Countdown timer: Both 15999ms, updates every 100ms ✓
- Escape key behavior: Both revert on Escape ✓
- Fade animation: Both have fade in on show (200ms) ✓
- Auto-revert on timeout: Both auto-revert when countdown reaches 0 ✓
- Backend wiring: onKeep → `appState.keepAppliedTheme()`, onRevert → `appState.revertTheme()` ✓

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

