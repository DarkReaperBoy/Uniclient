# GUI Audit — Cycle 1 Phase Ayugram (2026-05-18 21:51)

## Code Comparison (Dart vs AyuGram)

# bridge — Platform-specific FFI/WASM bridge to Go backend

## Issues Found

### [CRITICAL] Web bridge uses `assert()` instead of error throw — breaks in release builds
- **File:** `dart/lib/bridge/bridge_web.dart:37`
- **Issue:** The check `assert(_initialized, '...')` is stripped in release builds. The function will try to call uninitialized JS interop functions, causing cryptic JS errors instead of a clear error message.
- **Fix:** Change to match FFI pattern (line 70 in `bridge_ffi.dart`):
  ```dart
  // WRONG (current):
  assert(_initialized, 'Bridge not initialized. Call init() first.');
  
  // RIGHT (FFI pattern):
  if (!_initialized) {
    throw StateError('Bridge not initialized. Call init() first.');
  }
  ```
- **Severity:** CRITICAL — the code appears to work in debug builds but silently fails in release

### [MAJOR] Missing initialization check in `call()` — no guard for uninitialized state
- **File:** `dart/lib/bridge/bridge_web.dart:36-42`
- **Issue:** After fixing the assertion, also add the same guard to `call()`:
  ```dart
  Uint8List call(Uint8List requestBytes) {
    if (!_initialized) {
      throw StateError('Bridge not initialized. Call init() first.');
    }
    // ... rest of method
  }
  ```
- **Severity:** MAJOR — if init() is skipped, the code fails with unclear JS errors

## Verification Status

### What was verified:
- ✅ FFI implementation (bridge_ffi.dart) — memory management, isolate usage, event callbacks all correct
- ✅ WASM implementation (bridge_web.dart) — JS interop setup correct, event flow correct
- ✅ Stub implementation (bridge_stub.dart) — intentionally throws, correct
- ✅ Facade pattern (bridge.dart) — clean delegation, no logic issues
- ✅ Test suite (bridge_test.dart) — comprehensive tests covering init, sync call, async call, event stream
- ✅ Integration with EngineService — properly called and used end-to-end

### Notes:
- The bridge is properly wired to Go backend (tests confirm end-to-end flow)
- Event system works correctly via NativeCallable.listener on native, JS callback on web
- Async bridge correctly uses Isolate.run on native (non-blocking), wraps sync in Future on web (idiomatic)
- No stubs or placeholders in actual implementation — only intentional fallback stub
- Memory management is proper in FFI (calloc cleanup, pointer freeing)

## Recommendation:
Fix both asserts→throws in bridge_web.dart before shipping web version. Desktop/native (FFI) version is solid.


# notification_system — NotificationSystem orchestrator


# notification_types — Reaction/PollVote fields never populated from backend

## Critical Issues



# auth_state — Auth flow state machine gaps

# ayu_forward — Forward state machine and intelligent forward logic

# bridge_ffi.dart — No issues found

## Summary
The FFI bridge implementation is **correctly designed and fully functional**. All memory management, event handling, and platform compatibility are properly implemented.

## Verification Checklist

### Memory Management ✅
- **Line 127-129:** Request buffer allocated and copied correctly via `calloc`
- **Line 131:** Output length pointer allocated via `calloc`
- **Line 148-149:** Both pointers properly freed in finally block
- **Line 142:** Result copied to Uint8List before freeing C memory
- **Line 145:** Go-allocated memory freed via `free(resultPtr)` callback
- **Line 175:** Event data freed via `malloc.free(data)` after copying (correct for C.CBytes)
  - ✅ Matches Go side comment in `cmd/bridge/main.go:50-52` ("Dart frees it after copying")
  - ✅ Proper pairing: Go allocates via C.malloc, Dart frees via malloc.free

### Event Callback System ✅
- **Line 182:** `NativeCallable<_EventCallbackC>.listener(_onEvent)` — correct pattern
  - Uses `.listener` (not `.fromFunction`) to marshal calls back to Dart isolate
  - Avoids "Cannot invoke native callback outside an isolate" crashes
  - Matches Go export signature in `cmd/bridge/main.go:55` (`void (*event_callback_t)(void* data, int32_t len)`)
- **Line 168-177:** Event handler properly:
  - Checks for invalid length (line 169)
  - Copies bytes immediately (line 174)
  - Frees Go-allocated memory (line 175)
  - Emits to StreamController (line 176)

### Library Loading ✅
- **Line 94-102 (Linux):** Checks exe directory + lib subdir, fallback to system path
- **Line 104-108 (macOS):** Framework path search correct
- **Line 110-114 (Windows):** Local DLL search correct
- **Line 116 (Android):** Hardcodes `libcores.so` (correct for APK native lib)
- **Line 117:** Throws on unsupported platform (fail-fast)
- **Line 36:** `_resolvedLibPath` shared across isolates (correct for process-wide handle reuse)

### Initialization & Error Handling ✅
- **Line 49-50:** Guards against double-init
- **Line 70-72:** Guard against uninitialized state in `call()`
- **Line 78-79:** Guard against uninitialized state in `callAsync()`
- **Line 137-139:** Defensive check for nullptr and zero-length results
- **Line 169:** Defensive check for invalid event length

### Async Implementation ✅
- **Line 82:** Uses `Isolate.run()` for non-blocking FFI call
  - Correct pattern for blocking operations
  - Isolate.run automatically handles library reloading on same process handle
  - Comment on line 154 correctly notes: "DynamicLibrary.open with the same path reuses the process-wide handle (cheap)"

### Resource Cleanup ✅
- **Line 85-91 `dispose()`:** Proper lifecycle
  - Unregisters event callback (line 87)
  - Closes StreamController (line 89)
  - Closes NativeCallable (line 90)

### No Stubs or Placeholders ✅
- ✅ No `TODO` comments
- ✅ No `TODO()` function calls
- ✅ No hardcoded fake data
- ✅ No "coming soon" stubs
- ✅ No early returns with errors (only defensive checks)
- ✅ All functions are complete implementations

### Performance ✅
- ✅ Async calls use Isolate.run (non-blocking)
- ✅ Event streaming via broadcast StreamController (efficient multicast)
- ✅ Lazy library loading (only loaded on init)
- ✅ No unnecessary copies in hot paths
- ✅ calloc/malloc used appropriately for FFI interop

### Type Safety ✅
- ✅ FFI type signatures match Go exports (`BridgeCallWithLen`, `BridgeFree`, `BridgeSetEventCallback`)
- ✅ Pointer casting correct in `_onEvent` (line 174: `data.cast<Uint8>()`)
- ✅ All FFI types properly declared (lines 13-33)

## Cross-File Verification

### Go Backend Compatibility ✅
- ✅ `BridgeCallWithLen` signature matches Go export in `cmd/bridge/main.go:10-14`
- ✅ `BridgeFree` matches Go export in `cmd/bridge/main.go:21-26`
- ✅ `BridgeSetEventCallback` matches Go export in `cmd/bridge/main.go:31-52`
- ✅ Event callback signature `_EventCallbackC` matches `event_callback_t` typedef in Go

### Bridge Facade Integration ✅
- ✅ Implements `BridgeImpl` interface expected by `bridge.dart:15`
- ✅ All required properties and methods present (`events`, `isInitialized`, `init()`, `call()`, `callAsync()`, `dispose()`)

### EngineService Integration ✅
- ✅ Called via `Bridge` facade in `engine_service.dart:22`
- ✅ Events properly streamed to `_bridgeEventSub` for parsing (line 54 of engine_service.dart)

## Comparison to AyuGram Desktop
*Note: AyuGram Desktop is pure C++/Qt with no Dart/Flutter UI. Bridge_ffi.dart is architecture-specific to this project's Go+Flutter stack and has no direct AyuGram equivalent. This file implements the low-level FFI binding layer, not UI.*

## Conclusion
**No critical, major, or minor issues detected.**

The FFI bridge is production-ready. All memory management is correct, event handling is robust, platform loading is comprehensive, and integration with Go backend is properly wired. The code exemplifies proper Dart FFI patterns (Isolate.run for blocking, NativeCallable.listener for callbacks, proper cleanup).


# telegram_palette — Color value deviations and algorithm differences

## Scope
Dart file: `dart/lib/theme/telegram_palette.dart`
Ground truth: `/tmp/theme_extract/day-blue/colors.tdesktop-theme`, `/tmp/theme_extract/night/colors.tdesktop-theme`, `AyuGram/Telegram/lib_ui/ui/colors.palette`, `AyuGram/Telegram/lib_ui/ui/style/style_palette_colorizer.cpp`

---

---

## Performance


---

## Summary of root cause

The `dayBlue` preset incorrectly uses green-tinted values (from the classic day/green theme) for several outgoing-message-related colors (`msgOutServiceFgSelected`, `msgOutReplyBarSelColor`, `mediaOutFg`, `msgFileThumbLinkOutFg`, file icon colors). These should be blue-tinted for the day-blue theme.

The `night` preset has pervasive errors: it uses day-theme file type colors unchanged, wrong call UI colors (green answer button instead of night's blue), wrong selected-state colors (many should be `#ffffff` in night mode but aren't), and wrong bot keyboard overlay colors.


# wallpaper.dart — Pattern & gradient rendering

## Issues Found

- [x] [CRITICAL] Default patternIntensity is 40, should be 50 — `wallpaper.dart:25` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_wall_paper.h:110`
  - AyuGram defines `kDefaultIntensity = 50` but Dart hardcodes 40 in WallpaperData constructor
  - This affects all wallpaper creation via `WallpaperData()` and `fromColors()`

- [x] [CRITICAL] Missing pattern inversion for dark backgrounds with positive intensity — `wallpaper.dart:178-276` ← `AyuGramDesktop/Telegram/SourceFiles/ui/chat/chat_theme.cpp:1146,1155-1170`
  - AyuGram spec (research/telegram_desktop_ui.md:7756) requires: "when positive intensity is used AND background is dark (HSV value ≤ 0.3), the pattern is inverted"
  - Pattern inversion: replicate each pixel's alpha byte into R, G, B channels (white-on-transparent silhouette from dark-on-transparent)
  - Dart has NO inversion logic — affects readability of patterns over dark chat backgrounds
  - Severity: high — user-visible rendering bug causing illegible patterns

- [x] [MAJOR] ColorFilter.mode(Colors.white, BlendMode.dstIn) may not correctly implement negative pattern darkening — `wallpaper.dart:501-504` ← `AyuGramDesktop/Telegram/SourceFiles/ui/chat/chat_theme.cpp:116-117`
  - AyuGram uses `setCompositionMode(CompositionMode_DestinationIn)` before drawing pattern when opacity < 0
  - Dart uses `ColorFilter.mode(Colors.white, BlendMode.dstIn)` on the pattern image
  - BlendMode.dstIn semantics: "keep destination where source is opaque"
  - With white source (opaque everywhere), this effectively = noop; does NOT mask the pattern correctly
  - Expected: pattern acts as mask on gradient (darkens gradient where pattern is transparent)
  - Actual: pattern may not composite correctly over gradients
  - Recommend: test negative pattern rendering against AyuGram reference (e.g. -50 intensity)

- [x] [MINOR] Pattern overlay uses Opacity widget (line 484-485) which clamps patternOpacity — `wallpaper.dart:262,485` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_wall_paper.cpp:256-258`
  - Line 262: `opacity = wallpaper.patternOpacity.clamp(0.0, 1.0)` clamps negative opacity to 0
  - Line 485: uses this clamped opacity in Opacity widget
  - This works correctly because line 483 checks `if (intensity >= 0)` first (negative patterns skip Opacity widget)
  - Not a bug, just noted for clarity ✓

---


# bridge_stub.dart — No issues found

## Summary
The stub bridge implementation is **correctly designed and fully implements the expected FFI bridge interface**. All required methods are present with matching signatures and correct behavior for a fallback stub.

## Interface Verification
- ✅ `events` property returns empty stream (correct for no-emit stub)
- ✅ `isInitialized` property returns false (never initialized)
- ✅ `init()` throws UnsupportedError (correct for unsupported platform)
- ✅ `call()` throws UnsupportedError (correct for unsupported platform)  
- ✅ `callAsync()` throws UnsupportedError (correct for unsupported platform)
- ✅ `dispose()` is no-op (correct, nothing to dispose)

## Design Correctness
The stub is a proper compile-time fallback selected by conditional imports in `bridge.dart:9-11` when neither FFI (native platforms) nor web (WASM) implementations are available. It loudly fails at runtime rather than silently succeeding, which is the correct behavior.

All method signatures match both the FFI implementation (`bridge_ffi.dart`) and web implementation (`bridge_web.dart`).

**No critical, major, or minor issues detected.**

# auth_screen — Auth screen behavioral and wiring issues

# ayu_appearance_page — Audit findings


# ayu_chats_page — Audit Findings

# ayu_filters_page — Audit findings

# ayugram_settings_screen — Category icon mismatches

# ayu_other_page — 4 issues

# ayu_section_builder — Settings Section Builder Audit

# ayu_toggle — No issues found

Comprehensive comparison against AyuGram Desktop ToggleView (lib_ui/ui/widgets/checkbox.cpp:108-148, checkbox.h:141-163) and style definitions (lib_ui/ui/widgets/widgets.style:874-890).

**Dimensions verified:**
- Border: 2px ✓ (ayu_toggle.dart:54 ← widgets.style:880)
- Diameter: 14px (material), 16px (default) ✓ (ayu_toggle.dart:55,61 ← widgets.style:882,873)
- Width: 14px ✓ (ayu_toggle.dart:56 ← widgets.style:883)
- Shift: -2px (material), 1px (default) ✓ (ayu_toggle.dart:57,62 ← widgets.style:881,872)
- Anim padding: 2px ✓ (ayu_toggle.dart:58 ← widgets.style:884)

**Animation verified:**
- Duration: 150ms ✓ (ayu_toggle.dart:30 ← widgets.style:879)
- Curve: easeOutCubic (material), linear (default) ✓ (ayu_toggle.dart:68 ← checkbox.cpp:62)
- Direction: forward=true, reverse=false ✓ (ayu_toggle.dart:39-42 ← checkbox.cpp:57-62)

**Color interpolation verified:**
- Track: checkboxFg → windowBgActive ✓ (ayu_toggle.dart:84 ← checkbox.cpp:120, widgets.style:878,876)
- Thumb fill: always windowBg ✓ (ayu_toggle.dart:96 ← checkbox.cpp:135, widgets.style:877,875)
- Thumb border: checkboxFg → windowBgActive ✓ (ayu_toggle.dart:164 ← checkbox.cpp:132-133)

**Paint logic verified:**
- Track rendering (rounded rect with foreground color) ✓ (ayu_toggle.dart:144 ← checkbox.cpp:129-130)
- Thumb position interpolation ✓ (ayu_toggle.dart:147 ← checkbox.cpp:117)
- Material animPadding deflation ✓ (ayu_toggle.dart:152-155 ← checkbox.cpp:123-126)
- Thumb fill and border drawing ✓ (ayu_toggle.dart:158-167 ← checkbox.cpp:135-136)

**State management verified:**
- initState properly creates AnimationController ✓ (ayu_toggle.dart:26-33)
- didUpdateWidget handles value changes ✓ (ayu_toggle.dart:36-45 ← checkbox.cpp:48-68)
- dispose properly cleans up controller ✓ (ayu_toggle.dart:48-51)

**Callback wiring verified:**
- onTap invokes onChanged with inverted value ✓ (ayu_toggle.dart:77)

**Size calculation verified:**
- Total width: 2×border + diameter + width ✓ (ayu_toggle.dart:73 ← checkbox.cpp:101)
- Total height: 2×border + diameter ✓ (ayu_toggle.dart:74 ← checkbox.cpp:101)

**Paint optimization verified:**
- shouldRepaint checks all dynamic properties (t, fgColor, bgColor) ✓ (ayu_toggle.dart:173-174)

**Notes:**
- Ripple animation, X/V marks, and locked state are not present in Dart, but these features are disabled in the default toggle style (xsize=0, vsize=0, stroke=0, all unused in AyuGram for standard toggles)
- Canvas clipping in Dart (line 130) is a safe addition not present in AyuGram paint method
- All color references resolved correctly from theme palette

**Conclusion:** Widget is a faithful, fully-functional port of AyuGram's ToggleView with no missing features for the default style and no implementation bugs.

# call_panel — Call Panel UI

## calls_screen — Calls Box, Create Call, Group Calls, Call Settings


# chat_export — Audit Findings






# chat_list_panel — Audit Findings

# chat_view — Audit chunk 48

## choose_datetime_box — schedule/calendar/time-picker dialog suite


# color_picker_box — Color picker dialog vs AyuGram ColorEditor


# compose_entities — Text Composition & Entity Management

## Summary
**Status**: Functional with minor gaps vs. AyuGram reference  
**Core Logic**: Implemented correctly for single-edit scenarios, entity offset tracking, markdown-to-entity conversion  
**Comparison**: AyuGram C++ (input_field.cpp) vs. Dart implementation (compose_entities.dart)

---

## Findings


---

## Verified Correct Behavior

✓ **Entity offset adjustment during insertions/deletions** (lines 80-115): Correctly handles entity shifting and trimming when text is inserted or deleted.  
✓ **Custom emoji replacement with alt text** (lines 307-332, 349-363): Properly tracks offset changes and updates affected entities.  
✓ **Markdown delimiter parsing** (lines 365-409): Correctly handles nested/overlapping markdown, respects isBlock flag for code blocks, rejects inline code with newlines.  
✓ **Entity offset mapping after markdown stripping** (lines 415-443): Offset map calculation is correct; adjustments preserve entity boundaries.  
✓ **Text span building with proper styling** (lines 474-580): Style merging for overlapping formats, custom emoji rendering, and proper handling of spoiler/code backgrounds match Flutter conventions.  
✓ **JSON serialization to Telegram API format** (lines 21-40): FormatType enum correctly maps to Telegram entity type strings (bold, italic, text_url, custom_emoji, etc.).

---

## Comparison to AyuGram Desktop

| Aspect | Dart (`compose_entities.dart`) | AyuGram C++ (`input_field.cpp`) |
|--------|------|-------|
| Entity structure | Flat list with offset/length + type | QVector<TextWithTags::Tag> with string IDs |
| Text change tracking | Common prefix + delta calculation | QTextEdit document model (more robust) |
| Markdown parsing | Manual delimiter search + offset map | Tag-based system with markdown tag tracking |
| URL protection | ✅ Regex + overlap check (matches AyuGram logic) | ✅ ParseEntities + overlap checks |
| Custom emoji | Placeholder char replacement | QTextEdit-integrated with native support |
| Performance | O(n) for text change, O(n²) for markdown parse | O(n) optimized with tag cache |

---

## Recommendations

1. **[TESTING]** Add test cases for:
   - Markdown inside URLs: `"Check **http://example.com/__path**"` should preserve URL integrity
   - Emoji at text end: Create emoji, then delete characters after it
   - Entity overlap: Multiple entities covering same range with mixed types

---

## No Critical Placeholders or Stubs Found

All methods are fully implemented and wired to entity tracking. No mock data, TODO comments, or disabled functionality detected.

# confirm_box — Audit Findings


## confirm_box — _DeleteContent missing paidPostType / paid-post delete confirmation

- [x] [MAJOR] AyuGram's `deleteAndClear()` checks `paidPostType()` and shows a nested confirmation box (with warning text about Stars/TON) before actually deleting paid suggested posts. The Dart `_confirm()` (line 586-598) has no such check — it always calls `Navigator.pop` immediately. Deleting a paid suggested post will skip the secondary safety confirmation. — `confirm_box.dart:586-598` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/delete_messages_box.cpp:550-578`

## confirm_box — _DeleteContent missing date-range delete mode

- [x] [MAJOR] AyuGram's `DeleteMessagesBox` has a 4th constructor for date-range deletion (`firstDayToDelete`/`lastDayToDelete`) with its own body text (`tr::lng_sure_delete_by_date_one` / `tr::lng_sure_delete_by_date_many`). The Dart `DeleteBoxMode` enum has no equivalent mode, so the date-range bulk-delete confirmation path is entirely absent. — `confirm_box.dart:391` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/delete_messages_box.cpp:72-121`

## confirm_box — _DeleteContent revokeLabel wrong for clearHistory on megagroup/group

- [x] [MAJOR] For `clearHistory` mode on a group/megagroup peer, AyuGram shows a revoke checkbox (calls `revokeText(peer)`) only if `canRevokeFullHistory()` is true and the peer is a user. For channels it sets `_revokeJustClearForChannel = true` and skips the revoke checkbox. The Dart `_revokeLabel` getter returns `null` for all `clearHistory` modes (line 574-584 — it only returns a label for `singleMessage`/`bulkMessages`). This is correct for clear-history but the `canRevoke` field still being `true` at the call site when used for history-clearing DMs would incorrectly suppress the checkbox display because the Dart code only checks `mode`. The fix path must be verified at call sites, but the getter logic here is structurally correct for the cases handled. Not a separate MAJOR.

## confirm_box — ScreenShareChooser uses xrandr/wmctrl (X11-only, no Wayland support)

- [x] [MAJOR] `_ScreenShareChooserState._loadSources()` uses `xrandr --listmonitors` and `wmctrl -l` / `xdotool` to enumerate screens and windows. These are X11 tools. On Wayland (which is the default for KDE/GNOME since ~2023) `xrandr` only works via XWayland and `wmctrl`/`xdotool` don't work at all on native Wayland windows. The AyuGram screen-share chooser uses platform-native APIs (PipeWire on Linux). The Dart implementation will silently fail to enumerate windows on Wayland, falling back to a single "Entire Screen" entry with no window list — `confirm_box.dart:1071-1149` ← AyuGram uses PipeWire/portal (no direct equivalent file, this is a systemic platform limitation)

## confirm_box — ScreenShareChooser source thumbnails missing

- [x] [MAJOR] AyuGram's screen-share chooser shows live thumbnail previews of each screen/window source in the grid. The Dart `_ScreenShareChooser` shows only a static `Icons.desktop_windows` or `Icons.web_asset` icon — no preview thumbnail at all. Users cannot visually identify which window to select. — `confirm_box.dart:1221-1229` ← AyuGram desktop screen-share chooser provides live capture previews

## confirm_box — _RadioRow top padding (20px bottom-only per row) vs AyuGram (boxOptionListSkip: 20px as margin bottom per item)

- [x] [MAJOR] Each `_RadioRow` uses `padding: const EdgeInsets.fromLTRB(24, 0, 24, 20)` (line 860). AyuGram's `SingleChoiceBox` adds each radio with `QMargins(st::boxPadding.left() + st::boxOptionListPadding.left(), 0, st::boxPadding.right(), st::boxOptionListSkip)` where `boxOptionListSkip = 20px` and `boxOptionListPadding = margins(0,0,0,0)`. The left margin in AyuGram is `24 + 0 = 24px` which matches. However AyuGram adds a top-spacer widget of height `st::boxOptionListPadding.top() + st::autolockButton.margin.top()` before the first radio. The Dart adds `const EdgeInsets.only(top: 4, bottom: 8)` padding to the containing Column instead. This is a minor layout difference in the top spacing but the per-row spacing matches. Not enough for MAJOR, skip.

## confirm_box — boxClosing cancel callback not fired when dialog is dismissed via barrier

- [x] [MAJOR] AyuGram's `ConfirmBox` wires `box->boxClosing()` to always fire the cancel callback (line 100-103 in confirm_box.cpp), unless `strictCancel` is set (line 106-108). The Dart `showConfirmBox` tracks `confirmed` and `explicitCancel` booleans and calls `onCancel` in `.then()` if neither is set (line 341-343). However the `strictCancel` handling is inverted: when `strictCancel=true`, AyuGram calls `lifetime->destroy()` to disconnect the boxClosing signal so cancel is NOT fired on barrier dismiss. The Dart code checks `!strictCancel` before calling `onCancel` in `.then()` — which is logically equivalent. This is correct.

## confirm_box — _ReportOptionPickerBox missing left "Back" button

- [x] [MAJOR] AyuGram's dynamic report box (`report_messages_box.cpp:191-196`) adds a left-aligned back button (`tr::lng_create_group_back`) when `!reportInput.optionId.isNull()` (i.e., when at a sub-level of the option tree). The Dart `_ReportOptionPickerBox` only has a "CANCEL" button with no back navigation — meaning users cannot go back one level in a multi-level report option tree, they can only cancel the entire flow. — `confirm_box.dart:1414-1421` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/report_messages_box.cpp:191-196`

## confirm_box — _ReportOptionPickerBox missing "comment" option inline in picker box

- [x] [MAJOR] AyuGram's dynamic box renders both option buttons AND (if `result.commentOption` is set) an inline `InputField` plus a divider label, all within a single box. The Dart `showDynamicReportFlow` handles the `'add_comment'` branch by opening a separate `showReportDetailsBox`. This means the comment input appears in a new box rather than inline, which is a UX difference vs AyuGram (comment field is shown in the same box as other options when `commentOption` is present). — `confirm_box.dart:1349-1369` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/report_messages_box.cpp:124-196`

## confirm_box — getPermissionStatus uses pactl/ls for permission detection (unreliable)

- [x] [MAJOR] `getPermissionStatus` for microphone runs `pactl list sources short` and treats any output as "granted" (line 904-911). This checks PulseAudio/PipeWire availability, not actual permission. A system can have PulseAudio running but still deny microphone access to the app. For camera it checks `/dev/video0` existence (line 912-915), which will show as granted even if the app lacks `video` group membership. AyuGram on Linux uses platform-level permission APIs. These heuristics will return false positives — the app skips the permission denied box when the mic/camera is actually unavailable to it. — `confirm_box.dart:899-919` ← AyuGram uses Qt's permission system (no direct file equivalent, systemic issue)

# contacts_screen — contacts box, row, edit/share dialogs

# edit_mark_box — Text field edit dialog with validation

## Issues Found

- [x] [MAJOR] Hardcoded border colors instead of theme colors — `edit_mark_box.dart:99,104` ← `edit_mark_box.cpp:31` (InputField uses `st::defaultInputField` theme style)
  - Dart hardcodes error color `0xFFe53935` (red) and focus color `0xFF40a7e3` (blue)
  - Should respect theme/palette like other UI elements
  - AyuGram uses `st::defaultInputField` which inherits theme colors from style system

- [x] [MAJOR] Manual error state management instead of InputField's built-in error handling — `edit_mark_box.dart:42-54,64-71` ← `edit_mark_box.cpp:73-80` (uses `_text->showError()`)
  - Dart: Manual `_showError` boolean, manual error clearing logic in listener
  - AyuGram: Uses `_text->showError()` method on InputField widget, cleaner separation of concerns
  - Dart duplicates error management that should be in the TextField/InputField widget

- [x] [MAJOR] Hardcoded font size and weight instead of using style constants — `edit_mark_box.dart:93,96` ← `edit_mark_box.cpp:31` (uses `st::defaultInputField`)
  - Dart hardcodes: `fontSize: 14` for input text, `fontWeight: FontWeight.w600, fontSize: 14` for hint
  - Should use responsive/themed font metrics from palette/style system
  - AyuGram uses `st::defaultInputField` which provides proper font configuration

- [x] [MAJOR] Padding hardcoded instead of using style constants — `edit_mark_box.dart:87` ← `edit_mark_box.cpp:37,41,92-93` (uses `st::contactPadding`, `st::boxPadding`, `st::newGroupInfoPadding`)
  - Dart: `EdgeInsets.fromLTRB(24, 2, 24, 8)` hardcoded
  - AyuGram: Calculates from style constants (`contactPadding.top()`, `boxPadding`, `newGroupInfoPadding`)
  - Makes layout non-responsive to style changes or different screen sizes

- [x] [MAJOR] Static title instead of reactive producer — `edit_mark_box.dart:6-22` (title: String) ← `edit_mark_box.cpp:21-23` (rpl::producer<QString> title)
  - Dart: Simple `String title` parameter - static, cannot update
  - AyuGram: Uses `rpl::producer<QString> title` - reactive, can update after creation
  - Limits use case where title might change dynamically

## Behavioral Differences

- [x] [MAJOR] Input field configuration mismatch — `edit_mark_box.dart:88-110` ← `edit_mark_box.cpp:29-33`
  - Dart: Uses standard Flutter TextField with custom decoration
  - AyuGram: Uses specialized Ui::InputField with:
    - Title passed to constructor (becomes reactive hint/label)
    - Built-in error styling via `showError()` method
    - Built-in focus handling via `setFocusFast()`
    - Reactive submit signal via `submits()` producer
  - Dart's standard TextField doesn't provide these conveniences

- [x] [MAJOR] Resize handling not implemented — `edit_mark_box.dart` lacks resizeEvent ← `edit_mark_box.cpp:82-94`
  - AyuGram: `resizeEvent()` recalculates InputField width and position based on new box width
  - Dart: TextField implicitly fills available width (depends on TelegramBox layout)
  - If box is resizable, Dart version might not reflow properly

## Summary

edit_mark_box.dart is a functional implementation but diverges significantly from AyuGram's design:
1. **Theme integration**: Hardcoded colors/fonts instead of using theme system
2. **Widget design**: Manual state management vs. specialized InputField with built-in behavior
3. **Responsiveness**: Hardcoded padding/dimensions vs. style constants
4. **Reactivity**: Static data vs. reactive producers

The Dart version works but lacks the flexibility and maintainability of the AyuGram reference implementation.

# emoji_panel — Emoji/Sticker/GIF tabbed panel audit

# ayu_filter — Regex filter engine

## Summary
`ayu_filter.dart` maps to `ayu/features/filters/filters_controller.cpp`, `filters_utils.cpp`, and `filters_cache_controller.cpp`. Core logic is largely correct; the critical gaps are: missing import confirmation dialog, wrong service-message type mapping for 25, and O(n) cache scan.

# emoji_status_widget — Critical wiring issues with collectible & userpic formats

## Issues Found

- [x] **[CRITICAL]** Collectible emoji status colors never sent to widget — `emoji_status_widget.dart:96-98` expects format `"collectible:documentId:centerHex:edgeHex"`, but `telegram.go:11470` only returns document ID as plain number. Colors (centerColor, edgeColor) exist in AyuGram's `EmojiStatusCollectible` struct (`data_emoji_statuses.h:32-33`) but are never extracted or sent via FFI bridge.

- [x] **[CRITICAL]** Userpic emoji status not implemented in backend — `emoji_status_widget.dart:100-103` has code to handle `"userpic:"` prefix, but backend's `extractEmojiStatusID()` (`telegram.go:11462-11474`) never generates this format. This feature is completely unimplemented end-to-end.

- [x] **[CRITICAL]** Format mismatch with AyuGram reference — AyuGram's `CollectibleCustomEmojiId()` (`data_custom_emoji.cpp:1110-1111`) returns only `"collectible:" + collectible_id` (no colors, and collectible_id not document_id), but widget parser expects `"collectible:" + documentId + colors`. The IDs themselves are different types (collectible ID vs document ID).

- [x] **[MAJOR]** ShaderMask gradient application incomplete — `emoji_status_widget.dart:222-230` applies RadialGradient shader to collectible emojis, but without actual color data being sent (issue #1), this renders the gradient as transparent fallback. Even if colors were sent, the gradient rendering quality vs AyuGram spec is untested.

## Root Causes

1. **Backend mismatch**: Go's `extractEmojiStatusID()` strips all metadata except plain document ID
2. **Missing feature**: Userpic emoji status parsing never wired to backend
3. **Type confusion**: Collectible ID vs Document ID — AyuGram uses collectible ID for the serialized string, Dart expects document ID
4. **Missing data transport**: EmojiStatusCollectible colors (centerColor, edgeColor from `data_emoji_statuses.h`) need to be extracted and sent through FFI

## What AyuGram Does (Reference)

- Stores colors in `EmojiStatusCollectible` struct: centerColor, edgeColor (`data_emoji_statuses.h:26-39`)
- Serializes collectible status as: `"collectible:" + collectible_id` ONLY (no colors embedded) (`data_custom_emoji.cpp:1110-1111`)
- Colors accessed separately via `EmojiStatuses::collectibleInfo()` (`data_emoji_statuses.h:84`)

## Status

None of these features are fully wired. The widget compiles and renders fallbacks, but collectible gradient colors and userpic emoji status are completely non-functional.


# forum_topic_icon — No issues found

Audited against:
- `AyuGram/Telegram/Resources/art/topic_icons/*.svg` (path/gradient/opacity ground truth)
- `AyuGram/Telegram/SourceFiles/dialogs/dialogs.style:55-74` (size/font/textTop values)
- `AyuGram/Telegram/SourceFiles/data/data_forum_topic.cpp:50-145` (letter extraction, fallback color, icon frame logic)

All CRITICAL and MAJOR checks passed:

**Sizes** — `defaultSize=21`, `normalSize=19`, `largeSize=26`, `infoSize=32` match `dialogs.style:55-74` exactly. Font sizes (11/10/13/15px bold) and textTop values (2/2/3/4px) are correct.

**Colors** — All 7 palettes (blue/yellow/violet/green/rose/red/gray) match their respective SVG `linearGradient` stop-colors exactly. `_defaultColorId=0x9AABAB` correctly mirrors AyuGram's `ForumTopicDefaultIcon()→"gray"` fallback path (`data_forum_topic.cpp:70-73`).

**Gradients** — `fillY1Frac`/`fillY2Frac`/`strokeY1Frac`/`strokeY2Frac` fractions correctly translate all SVG `y1%`/`y2%` values. Blue stroke `strokeY2Frac=0.9939588` matches `blue.svg` linearGradient-2 `y2="99.39588%"`.

**Stroke width** — `2.94736842` matches `blue.svg` and `gray.svg`. Green/red/violet/yellow/rose SVGs use `2.84210526` (~3.5% narrower) while Dart applies the blue value to all — deviation is ~0.026 px at 21 px (cosmetic, below 10% threshold).

**Bubble path shape** — Dart uses the blue/gray path (`M42,4.47368421`) for all 7 palettes; the green-family SVGs use a slightly different variant (`M42,4.42105263`). Pixel deviation is ~0.013 px at 21 px (cosmetic).

**Highlight opacity** — `withValues(alpha: 0.375)` vs SVG `opacity="0.37491644"` — difference is 0.02% (cosmetic).

**Letter extraction** — `title.characters` (Unicode grapheme clusters) + `RegExp(r'[\p{L}\p{N}]', unicode: true)` is semantically equivalent to AyuGram's `Ui::Emoji::Find`-skip + `QChar::isLetterOrNumber` (`data_forum_topic.cpp:101-126`). Both skip emoji sequences and return the first letter-or-digit codepoint.

**Letter alignment** — `(targetSize - tp.width) / 2` horizontal centering matches `style::al_top` (AlignHCenter|AlignTop) with `QRect(0, textTop, size, font->height*2)` (`data_forum_topic.cpp:138-141`).

**General icon** — `_GeneralIconPainter` reproduces `general.svg` (20×20 viewBox, single `#FFFFFF` path recolored via parameter), matching `ForumTopicGeneralIconFrame` (`data_forum_topic.cpp:147-163`).

**Custom emoji backend** — `engine.getCustomEmojiFiles` and `engine.getCustomEmojiThumbs` are both wired (`forum_topic_icon.dart:428,438`). TGS/Lottie, WebP, and WebM all have active render paths with proper fallback chain.

**Lifecycle** — Ref-counting (`_refRetain`/`_refRelease`) and 5-second deferred cache eviction are correctly implemented. `dispose()` cancels the timer, disposes animation/player/temp-file, and releases the ref.


# info_panel — Audit findings

## info_panel — Backend wiring / Stub behavior


## info_panel — Missing features / Missing renderers


## info_panel — Minor wiring notes


# emoji_data — Emoji keyword search data and EmojiKeywords manager


# language_box — Audit Findings



# media_viewer — Audit Findings


# message_bubble — Audit


# notification_popup — Audit vs AyuGram Default Notification Manager

## Dimensions / timing — all pass

All numeric constants match `window/window.style` exactly:
`_notifyWidth`=320, `_notifyMinHeight`=80, `_notifyDeltaX`=6, `_notifyDeltaY`=7,
`_photoSize`=62, `_photoPos`=9, `_closeSize`=30, `_closePosRight`=1, `_closePosTop`=2,
`_textLeft`=83 (9+62+12), `_textTop`=7, `_itemTopOffset`=12, `_borderWidth`=1,
`_hideAllHeight`=36, `_replyButtonSize`=36, `_replyFieldMinH`=36, `_replyFieldMaxH`=72,
`_fadeInDuration`=150 ms, `_slowHideDuration`=4000 ms, `_fastHideDuration`=150 ms,
`_waitBeforeHide`=3000 ms, `_actionsFadeDuration`=200 ms,
reply field padding `fromLTRB(8,8,8,6)` = `notifyReplyArea.textMargins(8,8,8,6)`.
Border color uses `palette?.windowShadowFgFallback` = `notifyBorder: windowShadowFgFallback`. ✓

---

# payment_panel — Payment Panel Audit


# popup_menu — Context menu / popup menu widget


# reactions_detail — Reactions & Read-Receipt Detail Panel


# send_files_box — Audit Findings








# main — Audit findings

## main — Tray Ctrl+click separate window not implemented

- [ ] [CRITICAL] Ctrl+click on a tray account item logs a debug message and then falls through to the same normal account-switch path — no separate window is opened. AyuGram calls `Core::App().ensureSeparateWindowFor({ strong })` on Ctrl+click and skips `maybeActivate` entirely; the Dart does the opposite: it still calls `appState.setActiveAccountId` + `chatState.switchAccount` even when `ctrlPressed == true`, so the window is just switched instead of duplicated. — `main.dart:393-397` ← `tray_accounts_menu.cpp:62-64`

## main — Theme revert overlay timer drift

- [ ] [MAJOR] `_ThemeRevertOverlayState` decrements `_remainingMs` by a fixed 100 on every timer tick (`_remainingMs -= 100`). If the timer fires late (tab throttled, debug breakpoint, frame jank) the countdown underestimates elapsed time and auto-revert fires later than the 16-second spec. AyuGram computes remaining seconds from wall clock (`(kWaitBeforeRevertMs - msPassed) / 1000` where `msPassed = crl::now() - _started`) so it is immune to timer jitter. — `main.dart:2183` ← `window_theme_warning.cpp:99-104`

## main — Passcode lock screen uses hardcoded English strings

- [ ] [MAJOR] `_PasscodeLockScreen` hardcodes four main-UI strings in English while the rest of the app uses the `TrStrings` l10n system and supports 19 locales. The hardcoded strings and their AyuGram equivalents:
  - `'Please enter your passcode'` (AyuGram: `lng_passcode_enter` = "Enter your local passcode") — `main.dart:2561` ← `lang.strings:1173`
  - `'Your passcode'` hint — `main.dart:2592` ← `lang.strings:1174`
  - `'Submit'` button — `main.dart:2639` ← `lang.strings:1175`
  - `'Log out'` link — `main.dart:2674` ← `lang.strings:1176`

  `strings.dart` only declares `lngPasscodeWrong()` (line 15); the other four keys are absent from the l10n file entirely, so non-English users see English text on the passcode screen.

# sticker_pack_viewer — Audit findings

- [ ] [CRITICAL] "View Pack" context menu item is a stub — `case 'pack': break;` does nothing when tapped — `sticker_pack_viewer.dart:648-649` ← `boxes/sticker_set_box.cpp:1782-1801` (AyuGram shows "Add to Set" or navigates to the pack; the Dart case simply breaks with no action)

- [ ] [CRITICAL] Premium Unlock button has empty `onPressed: () {}` — tapping it does nothing — `sticker_pack_viewer.dart:305` ← `boxes/sticker_set_box.cpp:984-988` (AyuGram calls `Settings::ShowPremium(window, u"animated_emoji"_q)` to open the Premium upgrade screen)

- [ ] [CRITICAL] Fave toggle doesn't update local UI state — after calling `faveSticker()` the `sticker.isFaved` field on the `StickerInfoItem` is not flipped, so the context menu immediately reopened still shows the wrong label ("Add to Favorites" when it was just added, or vice versa) — `sticker_pack_viewer.dart:643-647` ← `boxes/sticker_set_box.cpp:1773` (AyuGram reads `isFaved(document)` from the live data layer which is updated synchronously by `ToggleFavedSticker`)

- [ ] [MAJOR] Context menu missing "Delete sticker" action for set creators — AyuGram shows a destructive "Delete" menu item with confirmation box when `amSetCreator()` is true — `sticker_pack_viewer.dart:630-650` ← `boxes/sticker_set_box.cpp:1788-1800`

- [ ] [MAJOR] Context menu missing "Add to Set" action for non-creators — AyuGram adds `Api::AddAddToStickerSetAction` for users who own a custom sticker set but didn't create this one — `sticker_pack_viewer.dart:630-650` ← `boxes/sticker_set_box.cpp:1782-1786`

## story_editor — video story backend missing, disabled premium gate broken, contacts exclusion stub

- [ ] [CRITICAL] `sendStoryWithVideoFile` calls engine command `'SendStoryWithVideo'` but no handler for this command exists anywhere in the Go backend (not in `dispatch_engine.go`, not in `dispatch_gen.go`, not in `telegram.go`) — video story posting always throws an unhandled error — `story_editor.dart:472` ← `go/bridge/dispatch_engine.go:3562` (only `SendStoryWithPhoto` exists, `SendStoryWithVideo` is absent)

- [ ] [CRITICAL] "Contacts" privacy option UI shows subtitle "Exclude people" but clicking it never opens a contact-exclusion picker; selecting `StoryPrivacyOption.contacts` and posting sends `InputPrivacyValueAllowContacts{}` with no disallow-list — the "exclude specific contacts from contacts audience" flow is a stub with misleading UI — `story_editor.dart:2248` ← `data/data_story.h:30` (`StoryPrivacy::Contacts` with exclusion is a distinct privacy mode, not raw AllowContacts)

- [ ] [MAJOR] `_durationItem(48)` creates a `PopupMenuItem` with `enabled: false` and `onTap` set to show a premium toast, but Flutter's `PopupMenuItem` does not fire `onTap` when `enabled: false` — the 48h option is silently unresponsive instead of showing the paywall toast — `story_editor.dart:1700-1707` ← `media/stories/media_stories_controller.cpp:1875` (premium gate check triggers visible prompt)

- [ ] [MAJOR] When a video file is selected and the user reaches the post stage, `_renderCanvasToBytes()` is NOT called and no overlay (paint strokes, text items, stickers) is composited onto the video — all editorial annotations placed on a video story are silently discarded on post — `story_editor.dart:471-483` ← `editor/editor_paint.cpp` (paint layer is composited into the final media before sending)

# telegram_toast — Sticker/emoji premium toast wiring and style issues

- [ ] [CRITICAL] Animated emoji premium toast never triggered — both callers (`message_bubble.dart:3436`, `chat_view.dart:1588`) pass `isEmoji: false`. The toast branches for `isEmoji: true` (animated emoji subscribe prompt, toSaved variant) are completely dead. In AyuGram, `StickerToast::showFor` sets `isEmoji = (setType == Data::StickersType::Emoji)` and triggers a different message for emoji packs. — `telegram_toast.dart:426-449` ← `history_view_sticker_toast.cpp:143-155`

- [ ] [CRITICAL] `onOpenSavedMessages` callback always `null` in every call site — both `message_bubble.dart:3436-3443` and `chat_view.dart:1588-1595` never pass `onOpenSavedMessages`. The "Open" button shown on every second emoji toast would silently do nothing (`_viewCallback` returns `null`, so the button is hidden, but the correct behavior is to navigate to Saved Messages). — `telegram_toast.dart:503` ← `history_view_sticker_toast.cpp:227-233`

- [ ] [MAJOR] Wrong "View"/"Open" button color — Dart uses `Color(0xFF6AB2F2)` (#6ab2f2, R=106 G=178 B=242). AyuGram uses `mediaviewTextLinkFg = #4db8ff` (R=77 G=184 B=255). These are visually distinct colours (>10% channel deviation on R and B). — `telegram_toast.dart:548` ← `colors.palette:527` + `chat.style:266`

- [ ] [MAJOR] Pack name shows technical short name instead of display title — callers pass `message.stickerSetShortName` (e.g. `"AnimatedEmoji"`) as `packName`. AyuGram first looks up the title from the local sets cache, then if missing makes a `messages.getStickerSet` API request to fetch the display title (e.g. `"Animated Emoji"`) before showing the toast. The Dart toast therefore shows the URL short-name to users instead of the human-readable pack title. — `message_bubble.dart:3438-3440` / `chat_view.dart:1590-1592` ← `history_view_sticker_toast.cpp:89-132`

# telegram_tooltip — 5 issues

- [ ] [MAJOR] `_ArrowPainter.paint()` clamps arrow position to `[arrowSkip, size.width - arrowSkip]` (66px minimum from each edge), but AyuGram constrains the tooltip box so the arrow is at least `arrowSkipMin` (24px) from the edge — the clamp bound should come from `arrowSkipMin` (24px), not `arrowSkip` (66px); in edge cases where the target is near a screen edge the Dart arrow is clamped 2.75× too aggressively — `telegram_tooltip.dart:462-463` ← `tooltip.cpp:380-381` + `widgets.style:1308`

- [ ] [MAJOR] `_resolveSide()` never returns `TooltipSide.left` or `TooltipSide.right` — the `left`/`right` cases at lines 351-354 fall through to bottom/top, making `TooltipSide.left` and `TooltipSide.right` dead code; AyuGram preserves Left/Right as distinct sides that affect both layout and animation — `telegram_tooltip.dart:351-355` ← `tooltip.h:96-98` + `tooltip.cpp:372-387`

- [ ] [MAJOR] Animation slide direction is always vertical (`Offset(0.0, slideOffset)`) regardless of tooltip side; AyuGram uses horizontal slide (`x += shift`) for Left/Right sides and vertical slide for Top/Bottom — `telegram_tooltip.dart:327-335` ← `tooltip.cpp:395-401`

- [ ] [MAJOR] Regular `TelegramTooltip` follows the cursor dynamically — `_onHover` updates `_lastPointer` and calls `markNeedsBuild()` causing the overlay to reposition on every pointer move; AyuGram tooltip is static (positioned once when shown) and hides if the cursor moves more than `startDragDistance()` from the initial show position — `telegram_tooltip.dart:71-74` ← `tooltip.cpp:62-72`

- [ ] [MAJOR] No window-active guard before showing the regular tooltip — Dart's `_show()` inserts the overlay unconditionally; AyuGram only shows the tooltip when `tooltipWindowActive()` returns true (i.e., when the application window has focus) — `telegram_tooltip.dart:85-95` ← `tooltip.cpp:49-60`

# theme_editor — Audit Findings

## Sources
- Dart: `dart/lib/ui/theme_editor.dart`
- AyuGram: `Telegram/SourceFiles/window/themes/window_theme_editor.cpp`
- AyuGram: `Telegram/SourceFiles/window/themes/window_theme_editor_block.cpp`
- AyuGram: `Telegram/SourceFiles/window/themes/window_theme_editor_box.cpp`
- Style: `Telegram/SourceFiles/window/window.style:167-170`

---

- [ ] [CRITICAL] `accessHash` hardcoded as `0` when building `CloudThemeMeta` for update path — `account_UpdateTheme` requires a real access hash obtained from `account_GetTheme`, so passing 0 will cause the API call to fail for any existing theme update — `theme_editor.dart:281` ← `window_theme_editor_box.cpp:525` (`MTP_inputTheme(MTP_long(fields.id), MTP_long(fields.accessHash))`)

- [ ] [CRITICAL] Import file picker uses `FileType.any` (accepts all files) — AyuGram filters to `*.tdesktop-theme *.tdesktop-palette` only; accepting arbitrary files causes silent parse failures with no user feedback — `theme_editor.dart:341` ← `window_theme_editor.cpp:787` (`"Theme files (*.tdesktop-theme *.tdesktop-palette)"`)

- [ ] [CRITICAL] "Show in Folder" menu item is disabled unless the user has previously exported a file (`_themeFilePath != null`) — AyuGram always enables this item and shows the live editing palette path (`EditingPalettePath()`), not an export destination; the Dart behavior breaks the primary "show your editing file in folder" use case — `theme_editor.dart:402-406` ← `window_theme_editor.cpp:757-759`

- [ ] [CRITICAL] When editing a token whose value is referenced (copied) by other tokens, Dart only updates the single token in `_colorMap` — AyuGram propagates the change through all dependent copies via `checkCopiesChanged()` cascading through `_context.changed` events — `theme_editor.dart:169-178` (`_updateColor`) ← `window_theme_editor_block.cpp:624-637` (`checkCopiesChanged`)

- [ ] [MAJOR] Active editing row uses `accentColor.withAlpha(30)` (~12% tinted background) — AyuGram fills the row with solid `st::dialogsBgActive` (fully opaque selection blue), a dramatically different visual — `theme_editor.dart:771` ← `window_theme_editor_block.cpp:717` (`p.fillRect(rect, active ? st::dialogsBgActive : ...)`)

- [ ] [MAJOR] When a color editor is open (editing state), AyuGram dims all rows below the active row with a `st::layerBg` semi-transparent overlay to visually focus attention — Dart has no such overlay; all non-editing rows remain fully opaque, breaking the focus UX — `theme_editor.dart` (no overlay anywhere in `_PaletteEntryRow`) ← `window_theme_editor_block.cpp:751-752` (`if (isEditing() && !active ...) p.fillRect(rect, st::layerBg)`)

- [ ] [MAJOR] Close button is positioned on the LEFT of the toolbar (`Row` starts with `IconButton(Icons.close)`) — AyuGram places the close button on the RIGHT via `_close->moveToRight(0, 0)` with the menu toggle immediately to its left — `theme_editor.dart:657-661` ← `window_theme_editor.cpp:857-858`

- [ ] [MAJOR] `updateCloudTheme` engine call does not pass the access hash — the bridge method signature omits it (`updateCloudTheme(accountId, themeId, title, slug, themeData)`) while the MTProto `account.updateTheme` requires `InputTheme` which is `{id, access_hash}` — `theme_editor.dart:311-316` ← `window_theme_editor_box.cpp:522-525`

- [ ] [MAJOR] Page-down/page-up keyboard navigation uses estimated row heights via `_estimateRowHeight` instead of reading actual rendered positions — AyuGram computes `selectSkipPage` from the real scroll height and iterates through actual row heights (`st::themeEditorMargin.top() + st::themeEditorSampleSize.height() + ...`) — `theme_editor.dart:462-483` ← `window_theme_editor.cpp:530-538`

- [ ] [MAJOR] `_sortByAccentDistance` computes accent distance using HSL lightness (via `HSLColor`) but returns score `255 - (color.saturation * 255).round()` — AyuGram sorts by `255 - fromSaturation` where `fromSaturation` is QColor's HSL saturation (0–255 int range), while Flutter's `HSLColor.saturation` is 0.0–1.0; the `clamp(0,255)` at the end masks the error but the sort order is computed identically only by accident — `theme_editor.dart:116-122` ← `window_theme_editor_block.cpp:454-466`

- [ ] [MAJOR] Background image in `_SaveThemeBox` is always re-encoded as JPEG at quality 87, even if the source was a PNG — AyuGram preserves the original format (`parsed.isPng`) and writes `background.png` vs `background.jpg` accordingly; Dart always produces JPEG — `theme_editor.dart:1173-1177` (`_encodeAsJpeg87`) ← `window_theme_editor_box.cpp:338-343` (`parsed.isPng ? ".png" : ".jpg"`)

- [ ] [MAJOR] Save precondition checks (passcode lock, session existence) are absent from the Dart SAVE THEME button — AyuGram blocks the save with a toast if the account is passcode-locked or has no session before opening the save box — `theme_editor.dart:275-337` (`_handleSaveToCloud` — no lock check) ← `window_theme_editor.cpp:837-842`

# titlebar — Custom CSD titlebar

- [ ] [CRITICAL] `_startDrag()` is called on **every** `onPointerMove` event during a drag, spamming the native channel with repeated `startDrag` method calls. AyuGram calls `startSystemMove()` once and immediately sends a synthetic `MouseButtonRelease` to clear `_mousePressed`, guaranteeing a single invocation per drag gesture — `titlebar.dart:241` (`onPointerMove: (_) => _startDrag()`) ← `ui_platform_window_title.cpp:487-494` (`if (_mousePressed) { window()->windowHandle()->startSystemMove(); SendSynteticMouseEvent(…, Qt::LeftButton); }`)

- [ ] [MAJOR] Window context menu is shown on `onSecondaryTapUp` (right-button **release**), but AyuGram shows it on `mousePressEvent` with `Qt::RightButton` (right-button **press-down**). The menu appears immediately on press in the reference — `titlebar.dart:238` (`onSecondaryTapUp: (_) => _showWindowMenu()`) ← `ui_platform_window_title.cpp:476-478` (`} else if (e->button() == Qt::RightButton) { ShowWindowMenu(window(), e->windowPos().toPoint()); }`)

- [ ] [MAJOR] Button icons use generic Flutter Material icons (`Icons.remove`, `Icons.crop_square`, `Icons.filter_none`, `Icons.close`) instead of Telegram's custom SVG assets (`title_button_minimize`, `title_button_maximize`, `title_button_restore`, `title_button_close`). The restore icon in particular (`Icons.filter_none`) is visually wrong — the reference uses a distinct overlapping-squares glyph — `titlebar.dart:296-302` ← `widgets.style:1602,1620,1635-1648,1653` (`{ "title_button_minimize", … }`, `{ "title_button_maximize", … }`, `{ "title_button_restore", … }`, `{ "title_button_close", … }`)

# web_app_panel — WebApp Mini-App Panel

- [ ] [CRITICAL] `_allowClipboardRead` is always `false` and never set — `WebAppPanelData` has no `allowClipboardRead` field so it can never be passed in; the flag stays false forever and blocks all clipboard reads even for bots that have permission — `web_app_panel.dart:136` ← `attach_bot_webview.h:272` (`_allowClipboardRead : 1 = false` initialized from `args.allowClipboardRead`)

- [ ] [CRITICAL] `_lastWebviewInteraction` is initialized to epoch and never updated — `setInteractionHandler` wires up a native callback that updates this timestamp on every webview interaction; Dart never wires this up, so `timeSinceInteraction.inSeconds` is always billions of seconds > 10, meaning clipboard reads are permanently blocked even when `_allowClipboardRead` were true — `web_app_panel.dart:137,715-717` ← `attach_bot_webview.cpp:920-922` (`raw->setInteractionHandler([=] { _lastWebviewInteraction = crl::now(); });`)

- [ ] [CRITICAL] `web_app_close` incorrectly triggers close-confirmation dialog — AyuGram calls `_delegate->botClose()` directly (no confirmation) because the bot itself is requesting close; Dart calls `_close()` which checks `_closeNeedConfirmation` and may show a dialog, contradicting the spec — `web_app_panel.dart:263-264` ← `attach_bot_webview.cpp:963`

- [ ] [MAJOR] `web_app_open_tg_link` missing `keepOpen=true` — AyuGram passes `keepOpen = true` so the panel stays open when the TG link is handled; Dart's engine call has no equivalent and the panel may close unexpectedly — `web_app_panel.dart:435-438` ← `attach_bot_webview.cpp:1374` (`_delegate->botHandleLocalUri("https://t.me" + path, true)`)

- [ ] [MAJOR] Downloads submenu missing from the three-dot menu — AyuGram checks `botDownloads(true)`, and if non-empty inserts a full downloads submenu with per-entry actions above Settings; Dart's `_showMenu` has no downloads section at all — `web_app_panel.dart:1256-1313` ← `attach_bot_webview.cpp:752-830`

- [ ] [MAJOR] Button state is accumulated progressively using `prev.*` — AyuGram reads all fields fresh from the incoming args object on each `processButtonMessage` call (`args["is_active"].toBool()` defaults to `false` when absent, `args["text"].toString()` defaults to empty string); Dart substitutes `prev.active` / `prev.text` when fields are absent, causing stale button state when bots send partial updates — `web_app_panel.dart:1023-1036` ← `attach_bot_webview.cpp:1713-1745`

- [ ] [MAJOR] `invoiceClosed` / `hideForPayment` not implemented — AyuGram hides the panel with `hideForPayment()` while the native payment UI runs and re-shows it via `invoiceClosed(slug, status)` after completion; Dart immediately fires `invoice_closed` from the engine call result without any panel hiding/re-showing, breaking the native payment flow — `web_app_panel.dart:487-508` ← `attach_bot_webview.cpp:2147-2163`

- [ ] [MAJOR] `openPopup` with empty `message` doesn't close bot — AyuGram calls `_delegate->botClose()` if message is empty or buttons array is empty; Dart shows the dialog with an empty message or no buttons instead — `web_app_panel.dart:1082-1109` ← `attach_bot_webview.cpp:1442-1450`

- [ ] [MAJOR] Viewport not re-sent on webview geometry changes — AyuGram sends `viewport_changed` inside the container geometry listener (`rpl::combine(container->geometryValue(), _footerHeight.value()) | rpl::on_next(...)`) so bots get live resize updates; Dart only sends viewport when the bot explicitly requests it with `web_app_request_viewport` — `web_app_panel.dart:1067-1080` ← `attach_bot_webview.cpp:940-951`

- [ ] [MAJOR] Progress spinner color is wrong — AyuGram uses `st::paymentsLoading.color` which maps to `windowSubTextFg` (a dedicated muted color, fully opaque); Dart uses `(isDark ? Colors.white : palette.windowFg).withValues(alpha: _kProgressOpacity)` (30% opacity of the foreground text color); the constant `_kProgressOpacity = 0.3` in AyuGram is used for the background fill overlay, not the spinner arc — `web_app_panel.dart:1531-1532` ← `attach_bot_webview.cpp:637-644` + `payments.style:137-141`

## engine_models — Data model audit

### GroupCallParticipant — fields in Dart class never populated from Go JSON

The Go engine struct `engine.GroupCallParticipant` (`go/engine/cache_chats.go:1434`) only emits these JSON keys:
`user_id`, `display_name`, `is_muted`, `is_speaking`, `has_video`, `avatar_path`, `can_self_unmute`, `raised_hand_rating`, `volume`, `audio_level`.

The event handler (`go/engine/events.go:464`) constructs with even fewer fields (no `can_self_unmute`, `raised_hand_rating`, `volume`, `audio_level`).

The following Dart fields exist in the constructor and are parsed in `fromJson` but the Go bridge **never emits them** — they will always be their zero defaults:

- [ ] [CRITICAL] `mutedByMe` — defined at `engine_models.dart:2257`, parsed `fromJson` at `engine_models.dart:2296`, but `go/engine/cache_chats.go:1434` has no `muted_by_me` JSON field. AyuGram `data_group_call.h:51` has `mutedByMe`. Add `MutedByMe bool json:"muted_by_me,omitempty"` to `engine.GroupCallParticipant` and populate from `cores.CallParticipant`.
- [ ] [CRITICAL] `sounding` — defined at `engine_models.dart:2259`, parsed at `engine_models.dart:2298`, but `go/engine/cache_chats.go:1434` has no `sounding` field. AyuGram `data_group_call.h:46`. Add to Go struct.
- [ ] [CRITICAL] `additionalSounding` — defined at `engine_models.dart:2267`, parsed at `engine_models.dart:2306`, not in `go/engine/cache_chats.go:1434`. AyuGram `data_group_call.h:48`. Add to Go struct.
- [ ] [CRITICAL] `additionalSpeaking` — defined at `engine_models.dart:2268`, parsed at `engine_models.dart:2307`, not in `go/engine/cache_chats.go:1434`. AyuGram `data_group_call.h:49`. Add to Go struct.
- [ ] [CRITICAL] `ssrc` — defined at `engine_models.dart:2266`, parsed at `engine_models.dart:2305`, not in `go/engine/cache_chats.go:1434`. AyuGram `data_group_call.h:44` (`uint32 ssrc`). Required for audio routing. Add to Go struct.
- [ ] [CRITICAL] `lastActive` — defined at `engine_models.dart:2269`, parsed at `engine_models.dart:2308`, not in `go/engine/cache_chats.go:1434`. AyuGram `data_group_call.h:42` (`TimeId lastActive`). Add to Go struct.
- [ ] [CRITICAL] `date` — defined at `engine_models.dart:2270`, parsed at `engine_models.dart:2309`, not in `go/engine/cache_chats.go:1434`. AyuGram `data_group_call.h:41` (`TimeId date`). Add to Go struct.

### GroupCallInfo — fields in Dart class never populated from Go JSON

The Go engine struct `engine.GroupCallInfo` (`go/engine/cache_chats.go:1424`) only has: `call_id`, `chat_id`, `title`, `participants_count`, `participants`, `active`.

- [ ] [CRITICAL] `isRtmp` — defined at `engine_models.dart:2320`, parsed `fromJson` at `engine_models.dart:2344`, but `go/engine/cache_chats.go:1424` has no `is_rtmp` field. AyuGram `data_group_call.h:86` (`bool rtmp() const`). Add `IsRtmp bool json:"is_rtmp,omitempty"` to `engine.GroupCallInfo` and populate from `cores.CallSession.Meta["is_rtmp"]`.
- [ ] [CRITICAL] `scheduleDate` — defined at `engine_models.dart:2321`, parsed `fromJson` at `engine_models.dart:2346`, but `go/engine/cache_chats.go:1424` has no `schedule_date` field. AyuGram `data_group_call.h:75` (`TimeId scheduleDate`). Add to Go struct and populate from `cores.CallSession.Meta["schedule_date"]`.
- [ ] [CRITICAL] `origin` — defined at `engine_models.dart:2322`, parsed `fromJson` at `engine_models.dart:2347`, but `go/engine/cache_chats.go:1424` has no `origin` field. AyuGram `data_group_call.h:63` (`enum GroupCallOrigin: Group, Conference, VideoStream`). Add `Origin string json:"origin,omitempty"` to Go struct.

### CachedMessage — field parsed but never emitted by Go bridge

- [ ] [CRITICAL] `forwardFromId` — defined at `engine_models.dart:468`, parsed `fromJson` at `engine_models.dart:767` (`j['forward_from_id']`), but `go/engine/cache_msgs.go:42` only has `ForwardFrom string json:"forward_from"` — there is no `forward_from_id` field anywhere in the Go engine JSON. The field will always be empty string. Either add `ForwardFromID string json:"forward_from_id,omitempty"` to `engine.CachedMessage` (populated from `cores.CoreMessage.ForwardFromID` at `go/cores/base.go:274`), or remove `forwardFromId` from the Dart model if unused.

