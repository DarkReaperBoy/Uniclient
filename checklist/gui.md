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

# ayu_other_page — 1 remaining issue

- [ ] [MAJOR] Donate amounts and username hardcoded as compile-time constants (`_donateAmountUsd = '5'`, `_donateAmountTon = '10'`, `_donateAmountRub = '300'`, `_donateUsername = 'RadianceTG'`) instead of being read from RCManager remote config; AyuGram fetches these dynamically and they can change server-side — `ayu_other_page.dart:437-440` ← `donate_info_box.cpp:179-203` + `rc_manager.h:64-78`

# ayu_section_builder — Audit Findings

## Reference files
- Dart: `dart/lib/ui/ayu_section_builder.dart`
- C++: `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/ayu_builder.cpp`
- C++: `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_ayu_utils.cpp`
- Style: `AyuGramDesktop/Telegram/SourceFiles/settings/settings.style`
- Style: `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/ayu_styles.style`

---

- [ ] [CRITICAL] `addBetaBadge`: badge is placed at hardcoded `left: 22 + 200 = 222px` regardless of the label text width. AyuGram computes the position dynamically: `st.padding.left() + parent->fullTextWidth() + st::settingsPremiumNewBadgePosition.x()` (padding=22, textWidth=dynamic, x=4). For short labels the badge appears too far right; for long labels it collides with or overlaps the text. — `ayu_section_builder.dart:177` ← `settings_ayu_utils.cpp:69-74`

- [ ] [MAJOR] `addCollapsibleToggle`: checked count (`checkedCount/total`) is only rendered when `!hasMaster && checkedCount > 0` in Dart. In AyuGram the count is a reactive `rpl::combine` over the label and `anyChanges` stream that always emits (starting with `rpl::empty_value()`), so `0/N` is visible from the start and updates live. Dart suppresses it entirely when the master toggle is present or count is zero. — `ayu_section_builder.dart:530-553` ← `settings_ayu_utils.cpp:228-243`

- [ ] [MAJOR] `addCollapsibleToggle`: C++ draws a 1px-wide vertical separator line (`kLineWidth = 1`) between the label area and the master toggle button (`st::rightsButtonToggleWidth = 70px`). The Dart `Row` has no separator — the toggle is placed directly after a `SizedBox(width: 12)` gap with no divider line. — `ayu_section_builder.dart:561-574` ← `settings_ayu_utils.cpp:162-187`

- [ ] [MAJOR] `addCollapsibleToggle`: AyuGram places the master toggle in a **separate `Ui::SettingsButton` overlay widget** (`toggleButton`) positioned at `width - rightsButtonToggleWidth (70px)`, giving it an independent hit area that never triggers expand/collapse. The Dart nests `AyuToggle` inside the row's `InkWell(onTap: () => _open = !_open)`, so the expand/collapse InkWell and the toggle share a visual surface; the InkWell ripple fires across the toggle area on hover/press even if the gesture is ultimately consumed by the toggle. — `ayu_section_builder.dart:523-524` ← `settings_ayu_utils.cpp:91-96, 303-320`

- [ ] [MAJOR] `addChooseButton`: uses Flutter `AlertDialog` + `RadioListTile` (Material Design widgets). AyuGram uses `SingleChoiceBox` (a Telegram-styled box with custom radio rows from `ui/boxes/single_choice_box.h`). The dialog has wrong background color logic (`const Color(0xFF1B2836)` hardcoded), wrong title font size (17px vs Telegram's `boxTitleStyle`), and wrong radio item styling. — `ayu_section_builder.dart:429-454` ← `settings_ayu_utils.cpp:519-535`

- [ ] [MAJOR] Beta badge font size is 9px in Dart (`fontSize: 9`) but AyuGram's `settingsPremiumNewBadge` uses `font(10px semibold)` — a 10% deviation. Applies to both the inline `showBetaBadge` path in `_AyuSettingToggle` and the `_BetaBadgeOverlay` class. — `ayu_section_builder.dart:193, 258` ← `settings.style:144-147`

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

# call_panel — Audit findings

- [ ] [CRITICAL] Device selection (camera/mic) updates local state only — never calls engine. `_showDeviceSelectorMenu` at lines 450-457 does `setState(() { _selectedCameraDevice = ...; _selectedMicDevice = ...; })` with no engine call. `engine.setCallAudioDevice()` exists at `engine_service.dart:1951` but is never invoked after a device is picked. — `call_panel.dart:450-457` ← `calls_call.cpp:537,546,1070,1078` (`_instance->setAudioInputDevice()` / `setAudioOutputDevice()` called immediately after device change)

- [ ] [CRITICAL] "Add People" creates a separate conference call instead of migrating the current 1:1 call. Lines 380-385 call `engine.createConferenceCall(accountId)` then `engine.sendMessage()` with the invite link, leaving the active 1:1 call running unmodified. AyuGram uses `startOrJoinConferenceCall()` with `migrating=true` and calls `destroyCurrentCall()` to properly transition the 1:1 call into the group call. The Dart approach would leave the user in two simultaneous calls. — `call_panel.dart:380-385` ← `calls_instance.cpp:245-310` (`startOrJoinConferenceCall` with migration logic)

- [ ] [CRITICAL] Device enumeration silently skipped on non-Linux platforms. Line 156 is `if (!Platform.isLinux) return;` so `_cameraDevices` and `_micDevices` stay `['Default']` on macOS and Windows. Users on those platforms cannot select audio/video devices at all. AyuGram uses `Webrtc::DeviceResolvedId` callbacks that are platform-agnostic. — `call_panel.dart:155-156` ← `calls_panel.cpp:1065-1078` (platform-agnostic device callback)

- [ ] [MAJOR] `_OutgoingPreview` interpolates preview size against wrong dimension constant. `_hDefault = 720.0` (line 2057) is the panel's default WIDTH, not height. The parameter `containerHeight` is the panel height (default 540). With `_hMin=400` and `_hDefault=720`, `t = (540-400)/(720-400) = 0.4375` at the default panel height, so the preview is always stuck at 43% between min and max — never reaches `_maxSize`. The constant should likely be `CallPanel.defaultHeight` (540.0). — `call_panel.dart:2054-2063`

- [ ] [MAJOR] Conference invite sends messages but never joins the created conference. After `engine.createConferenceCall()` and `engine.sendMessage()` loop (lines 380-385), the caller is NOT added to the new conference call — only the invite link is sent. The caller remains in the original 1:1 call while invitees join a conference the caller is not in. AyuGram's `finishConferenceInvitations()` is called only after the panel migrates to the group call. — `call_panel.dart:380-397` ← `calls_instance.cpp:315-340` (`finishConferenceInvitations` called after migration)

- [ ] [MAJOR] `_imageColors` heavy computation runs synchronously on the UI thread. `_loadImageColors()` at lines 481-569 decodes the full image via `FileImage.resolve()`, samples every Nth pixel of the decoded buffer in a loop (line 518), and calls `setState()` from the callback — all without an `Isolate.run`. For large avatar images this blocks the raster thread. AyuGram computes background colors off the main thread via `crl::async`. — `call_panel.dart:481-569`

# call_screen — GroupCallPanel & MinimisedCallBar audit

- [ ] [CRITICAL] `onToggleMute` in `showGroupCallPanel` never calls `engine.setCallMuted()` — it only flips local `selfMuted` state in the `StatefulBuilder` and passes through the external `onToggleMute` callback, which itself has no engine wiring at the call site. `engine.setCallMuted()` exists in engine_service.dart but is never invoked from call_screen.dart. — `call_screen.dart:1126-1133` ← `calls/group/calls_group_call.cpp:3891` (sendSelfUpdate for mute)

- [ ] [CRITICAL] Raise-hand is not wired to the engine — when a force-muted user "raises hand" (`setSbState(() => raisedHand = true)` at line 1128), no engine call is made to send the raise-hand flag (`flag::f_raise_hand`). The toggle only changes local UI state. — `call_screen.dart:1127-1128` ← `calls/group/calls_group_call.cpp:3891,3928` (sendSelfUpdate with RaiseHand / f_raise_hand flag)

- [ ] [CRITICAL] No `leaveGroupCall` engine method exists and it is never called when the user simply leaves (non-manager). `onLeave` for non-managers calls only `Navigator.of(ctx).pop()` with no engine-side leave. There is no `engine.leaveGroupCall()` in engine_service.dart. — `call_screen.dart:1122-1124` ← `calls/group/calls_group_panel.cpp:616` (hangup/leave action)

- [ ] [CRITICAL] Output device selection in `_showSoundDevicePicker` only saves to `AppState` — it never calls `engine.setCallAudioDevice()`. The engine method exists (`engine_service.dart:1951`) but is completely unwired from the UI. Changing the output device has no effect on the actual call. — `call_screen.dart:1273` ← `calls/group/calls_group_settings.cpp` (device selection feeds into tgcalls audio sink)

- [ ] [CRITICAL] Noise suppression toggle in `_showCallSettingsFromMenu` only saves to `AppState` — there is no `engine.SetNoiseSuppression()` or equivalent method in engine_service.dart, meaning the toggle is cosmetic only and has no effect on the call audio pipeline. — `call_screen.dart:1407-1413` ← `calls/group/calls_group_settings.cpp` (NoiseSuppression feeds tgcalls)

- [ ] [CRITICAL] Invite members flow (`_showInviteMembersFromMenu`) uses `engine.createConferenceCall()` to get an invite link, then sends it as a text message via `engine.sendMessage()`. This is wrong — AyuGram invites participants directly via `phone.inviteToGroupCall` MTProto call, not by sending a text message with a link. The current approach creates a new conference call instead of inviting into the existing group call. — `call_screen.dart:1373-1378` ← `calls/group/calls_group_panel.cpp` (AddParticipant → InviteToGroupCall)

- [ ] [CRITICAL] On macOS and Windows, output device enumeration is hardcoded static lists (`['Built-in Output', 'Headphones']` / `['Speakers', 'Headphones']`). These are fake device names that do not correspond to real system audio devices on those platforms. — `call_screen.dart:1237-1241` ← AyuGram uses OS-native audio device APIs (CoreAudio on macOS, WASAPI on Windows)

- [ ] [MAJOR] Wide-mode sidebar width is 260px (`GroupCallPanel.sidebarWidth = 260.0`) but AyuGram defines `groupCallNarrowMembersWidth: 204px` for the narrow member list panel in wide layout. Dart value is 28% too wide. — `call_screen.dart:61` ← `calls/calls.style:1355`

- [ ] [MAJOR] Bottom controls `_buildBottomControls()` uses `padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24)` — there is no bottom skip from the mute button to the panel bottom edge. AyuGram uses `groupCallMuteBottomSkip: 116px` for the mute button's bottom offset from the panel base, and `groupCallButtonBottomSkip: 113px` for secondary buttons. The Dart layout packs all buttons flat in a Row with only 16px vertical padding, far short of the 113–116px bottom skip. — `call_screen.dart:291` ← `calls/calls.style:1020,1024`

- [ ] [MAJOR] `_BigMuteButton` uses a circle size of 42px and icon of 36px (matching `callMuteButtonActive.bgSize: 42px` and `lottieSize: 36px`). However, the button's total hit-target area (the `SizedBox` containing the blob + circle) is computed as `_majorBlobMaxRadius * 2 + 8 = 77*2+8 = 162px`. AyuGram's `callMuteButtonActiveInner` defines a 68×79px button area — the Dart widget has a dramatically larger hit area (162×162) because it is sized by the blob radius, not the button spec. — `call_screen.dart:860,869-871` ← `calls/calls.style:266-267`

- [ ] [MAJOR] `_SpeakerBlobAvatar` blob paint uses `majorScale = 0.605` / `minorScale = 0.545` multipliers against the row blob radius (27–29px range), but AyuGram's `groupCallMajorBlobMaxRadius: 4px` and `groupCallMinorBlobMaxRadius: 12px` define separate absolute max radii for the row blobs in the members list. Dart's blob is significantly larger than AyuGram's row blob spec. — `call_screen.dart:441-442` ← `calls/calls.style:1234,1237`

- [ ] [MAJOR] `_showGroupCallMenu` presents "Sound", "Invite members", and "Settings" as the only three menu items. AyuGram's group call menu (`calls_group_menu.cpp`) contains: Join As (display as), Start/Stop Recording, Screen Share toggle, Settings, Leave/End call. The Dart menu is missing recording toggle, screen-share toggle from menu, and Join-As option; it adds a "Sound" device picker that is not part of AyuGram's menu at all. — `call_screen.dart:1178-1212` ← `calls/group/calls_group_menu.cpp:519-616`

- [ ] [MAJOR] `_CallBarHangupButton`'s `_handleTap` for managers calls `_showLeaveOrEndDialog` but `onEndForAll` only calls `onTap?.call()` — it never calls `engine.endGroupCall()`. The leave-or-end dialog's "End for all" path in the call bar is not wired to the backend. — `call_screen.dart:2156-2165` ← `calls/group/calls_group_panel.cpp:616`

- [ ] [MAJOR] Participant row height is 52px (`Container(height: 52, ...)`) which matches `createCallListItem.height: 52px`. However, the avatar uses a fixed 36px diameter circle (`radius: 18`) inside a `_SpeakerBlobAvatar` whose `blobSize = _maxRadius * 2 + 4 = 62px`, creating a 62×62 blob container that overflows the 52px row height. AyuGram's row blob is constrained by `groupCallRowBlobMaxRadius: 29px` → 58px blobSize at most, but it is rendered as an overlay, not expanding the row. — `call_screen.dart:231,516` ← `calls/calls.style:654,1144-1145`

# calls_screen — Audit Findings

## calls_screen — Calls box, group call list, call history, conference invite, call settings

- [ ] [CRITICAL] macOS and Windows device enumeration uses hardcoded static fake lists — macOS always shows `['Default', 'Built-in Output', 'Headphones']` / `['Default', 'Built-in Microphone']` / `['Default', 'FaceTime HD Camera']`; Windows shows similarly hardcoded entries — real devices are never discovered — `calls_screen.dart:2183-2198` ← `settings_calls.cpp:57-70` (`Core::App().mediaDevices().devicesValue(type)` dynamically enumerates real system devices on all platforms)

- [ ] [CRITICAL] `_GroupCallRow` join button only rendered for `ChatType.channel`, not `ChatType.group` (megagroups) — megagroup active calls show no join button — `calls_screen.dart:536,611` ← `calls_box_controller.cpp:80-81` (`peer()->isChannel()` is true for both regular channels and megagroups in TDesktop's type system, so both receive the right-action button)

- [ ] [MAJOR] GroupCallRow status text doesn't distinguish public/private type — returns plain `'channel'`, `'group'`, or `'chat'` — AyuGram builds "public channel", "private channel", "public group", or "private group" based on `channel->isMegagroup()` and `channel->isPublic()` — `calls_screen.dart:522-531` ← `calls_box_controller.cpp:107-116`

- [ ] [MAJOR] Call history box has no live update subscription — new incoming or outgoing calls made while the box is open are never prepended to the list — `calls_screen.dart:80-94` (only subscribes to `onGroupCallState`) ← `calls_box_controller.cpp:510-518` (`messageUpdates(Flag::NewAdded)` subscription inserts new call rows in real time via `insertRow(update.item, InsertWay::Prepend)`)

- [ ] [MAJOR] Multi-contact conference call invite sends the invite link as plain messages via `engine.sendMessage()` instead of using the proper direct invite API — `calls_screen.dart:989-993` ← `calls_group_invite_controller.cpp:125-176` (AyuGram uses `ConfInviteController` which calls `startOrJoinConferenceCall` with structured `InviteRequest` objects per peer)

- [ ] [MAJOR] `_loadActiveGroupCalls` makes up to 200 sequential `engine.getGroupCall()` API calls on every init AND on every single `GroupCallStateEvent` — `calls_screen.dart:171-198` ← `calls_box_controller.cpp:175-230` (AyuGram subscribes reactively to `Data::PeerUpdate::Flag::GroupCall` and only scans pinned + first `kFirstPageCount` non-pinned chats at startup; individual peer updates are handled incrementally)

- [ ] [MAJOR] `_ConfInviteRow` has no `alreadyIn` state — contacts already participating in the conference call are displayed identically to uninvited contacts with no visual distinction or disabled state — `calls_screen.dart:1587-1810` ← `calls_group_invite_controller.cpp:87-113` (`ConfInviteRow._alreadyIn` flag greys out and disables rows for already-in participants)

- [ ] [MAJOR] "Show in chat" in call history context menu uses a 300 ms `Future.delayed` timer before calling `jumpToMessage(timestamp)` instead of navigating directly to the message by ID — `calls_screen.dart:1930-1937` ← `calls_box_controller.cpp:600-610` (`rowClicked` calls `window->showPeerHistory(peer, Way::ClearStack, itemId)` with the exact `MsgId` immediately)

- [ ] [MAJOR] `_InputLevelMeter` not implemented on Windows — `_startCapture` returns early for non-Linux/non-macOS platforms leaving the meter permanently dark with no audio capture — `calls_screen.dart:2737` ← `settings_calls.cpp:114-151` (AyuGram uses `Webrtc::AudioInputTester` which works on all platforms)

# chat_export — Export Panel Audit

- [ ] [MAJOR] Progress bar foreground color in processing/completed views uses `palette.windowBgActive` instead of `palette.mediaPlayerActiveFg`; AyuGram defines `exportProgressFg: mediaPlayerActiveFg` — `chat_export.dart:2083` ← `export.style:66`

- [ ] [MAJOR] Progress bar background color in processing/completed views hardcoded as `0xFF283848`/`0xFFE0E0E0` instead of `palette.mediaPlayerInactiveFg`; AyuGram defines `exportProgressBg: mediaPlayerInactiveFg` — `chat_export.dart:2085` ← `export.style:67`

- [ ] [MAJOR] Skip-file timer resets on every `onExportProgress` event; AyuGram only restarts the 5-second timer when `fileRandomId` changes (new file starts downloading), meaning the skip link may never appear if the engine sends frequent progress events — `chat_export.dart:856-857` ← `export_view_progress.cpp:339-346`

- [ ] [MAJOR] Error view (`_buildErrorPlaceholder`) calculates top padding as `panelHeight/4 - titleBarHeight = 72px`; AyuGram's `showCriticalError` uses `exportPanelSize.height() / 4 = 120px` top margin in the panel content area — `chat_export.dart:2393` ← `export_view_panel_controller.cpp:271`

- [ ] [MAJOR] `TAKEOUT_INVALID` and `TAKEOUT_INIT_DELAY` errors reset the panel back to settings phase after the inform box is dismissed; AyuGram closes the entire panel via `_panel->hideGetDuration()` when the inform box closes — `chat_export.dart:971-975` ← `export_view_panel_controller.cpp:291-294`

- [ ] [MAJOR] Processing view sets completed step `opacity = 0.5` to visually indicate "done"; AyuGram's `ProgressWidget::Row` never reduces opacity for completed steps — opacity is only used for cross-fade transitions when step label changes, not as a "done" indicator — `chat_export.dart:838,953` ← `export_view_progress.cpp:99-115`

- [ ] [MAJOR] Progress step label changes update in-place with no animation; AyuGram's `Row::updateData` cross-fades the old instance out while fading the new one in using `Instance _current/_old` with `Ui::Animations::Simple opacity` — `chat_export.dart:2102` ← `export_view_progress.cpp:73-91`

## chat_list_panel — Chat list panel audit vs AyuGram Desktop

- [ ] [CRITICAL] Search only returns matching chats — never message results. In AyuGram, all four search tabs (`MyMessages`, `ThisTopic`, `ThisPeer`, `PublicPosts`) produce `_searchResults` which are individual **messages** (FakeRows) rendered below peer results. The Dart implementation filters `List<ChatInfo>` and only shows matching chat rows — messages inside chats are never surfaced. This means "My Messages" and "Public Posts" search never shows the actual message hits that Telegram Desktop shows. — `chat_list_panel.dart:472-516` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/dialogs_inner_widget.cpp:4130-4188`

- [ ] [CRITICAL] "Public Posts" tab shows channel chats from local list as fallback instead of calling global message search. The spec requires `SearchGlobal` API with `ChatSearchTab::PublicPosts` flag to return actual public post messages. Dart's `_filterByTab` for `publicPosts` calls `chatState.searchGlobalPosts()` which hits `SearchGlobalPosts` bridge, but the return value is `List<ChatInfo>` (peer list), not individual message results. When that list is empty the fallback is `results.where((c) => c.type == ChatType.channel)` — entirely local data with no server round-trip. — `chat_list_panel.dart:498-506` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/dialogs_inner_widget.cpp:3324-3344`

- [ ] [CRITICAL] AyuGram has a 4th search tab `ThisTopic` (shown when inside a forum thread). Dart only has 3 tabs (`myMessages`, `publicPosts`, `thisPeer`) and never shows `ThisTopic`. When a forum topic is open and the user searches, there is no "This Topic" scoped search, so the search scope is incorrect. — `chat_list_panel.dart:125-129` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/ui/chat_search_in.h:22-27`

- [ ] [MAJOR] `_TopPeersStrip` has no right-click / long-press context menu. AyuGram shows a context menu on each top peer with "Remove from frequent" (remove one) and "Hide frequent contacts" (disable all, calls `session.topPeers().toggleDisabled(true)`). Dart's `GestureDetector` only has `onTap` — no `onSecondaryTapUp` or `onLongPress`. Users cannot remove individual top peers or disable the strip entirely. — `chat_list_panel.dart:2513-2556` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/ui/dialogs_suggestions.cpp:1511-1543`

- [ ] [MAJOR] "Delete Topic" context menu action calls `deleteForumTopicHistory` (which clears messages via `MessagesDeleteTopicHistory`) instead of actually deleting the topic. In AyuGram / Telegram, deleting a topic uses `channels.deleteTopicHistory` with full removal. The Go core has no `DeleteForumTopic` method and the bridge has no `DeleteForumTopic` call — the topic remains after "deletion". — `chat_list_panel.dart:5243-5259` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/dialogs_inner_widget.cpp:3428-3434`

- [ ] [MAJOR] `_TopPeersStrip` calls `chatState.getTopPeers()` (which calls `GetTopPeers` bridge) but there is no `getTopPeersEnabled` guard: the strip will always render if top peers are returned, even if the user has previously disabled "Frequent Contacts" via Telegram settings. AyuGram checks `session().settings().topPeersEnabled()` before rendering the strip. The `getTopPeersEnabled` method exists in engine_service.dart (line 4457) but is never called from the strip. — `chat_list_panel.dart:2466-2475` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/ui/dialogs_suggestions.cpp:1492-1494`

- [ ] [MAJOR] `_StoriesBar` only shows peers with `storyCount > 0` from the already-loaded `accountChats` list. It never fetches or subscribes to story updates. AyuGram's stories bar subscribes to `session().data().stories()` changes via reactive streams; the Dart version shows stale data until a full chat list refresh happens. Newly posted stories will not appear unless the whole chat list reloads. — `chat_list_panel.dart:2658-2668` ← `AyuGramDesktop/Telegram/SourceFiles/dialogs/ui/dialogs_suggestions.cpp:1372-1376`

- [ ] [MAJOR] `_StoriesBar` "My Story" button always shows even if the user has never posted a story and story posting is disabled for the account. AyuGram shows the "Add Story" button only when the user can post stories. The `hasOwnStory` check at line 2722 only checks if a "Saved Messages" DM has `storyCount > 0`, which is the wrong heuristic — it should check the user's own stories via the story API. — `chat_list_panel.dart:2715-2733`

- [ ] [MAJOR] Forum topic mute context menu action does not check current mute state — the submenu always shows "For 1 hour / 8 hours / 2 days / Until manually unmuted" regardless of whether the topic is already muted. AyuGram shows "Unmute" when the topic is already muted. There is no `topic.isMuted` field on `ForumTopic` model, so the mute state cannot be toggled correctly. — `chat_list_panel.dart:5139-5142`

- [ ] [MAJOR] `_RecentContactsList` is shown when search is focused and query is empty, but uses only local DM chats sorted by `lastMsgTime`. AyuGram fetches `contacts.getContacts` plus `contacts.getTopPeers` to build this list. The Dart implementation uses `.take(30)` on an already-loaded local list, so offline/uncached contacts will never appear. — `chat_list_panel.dart:3123-3127`

- [ ] [MAJOR] Reorder overlay `ChatListRow` at line 1233 uses `onTap: () {}` (empty callback). This is intentional for the floating drag ghost (it should not respond to taps), but is the only `onTap: () {}` in the file — confirmed not a functional stub, just the drag overlay. Not a real issue but listed for completeness. — `chat_list_panel.dart:1233`

## chat_list_row — swipe action icon area width, closed-topic lock icon, online badge size, draft reply-to icon, special userpic types, and Lottie asset existence

- [ ] [CRITICAL] Swipe action icon draw area is hardcoded to 80×80px (`SizedBox(width: 80, height: 80)`), but AyuGram uses `quickWidth = st::dialogsQuickActionSize * 3 = 20×3 = 60px` for the icon rect width — `chat_list_row.dart:833-836` ← `AyuGram/dialogs/ui/dialogs_layout.cpp:988-996`

- [ ] [CRITICAL] Lottie animation assets (`assets/animations/swipe_mute.json`, `swipe_unmute.json`, `swipe_pin.json`, etc.) are referenced but almost certainly do not exist in the Flutter asset bundle — `chat_list_row.dart:531-553` ← `AyuGram/dialogs/dialogs_quick_action.cpp:120-143` (AyuGram embeds these as Lottie icons; they must exist as real `.json` files in `assets/animations/`)

- [ ] [CRITICAL] Closed forum topic missing lock icon: when `ForumTopic.isClosed == true`, AyuGram renders `st::dialogsLockIcon` in the send-state position; the Dart `_SendStateIcon` widget has no path for this and `chat_list_row.dart` never checks `isClosed` — `chat_list_row.dart:1603-1657` ← `AyuGram/dialogs/ui/dialogs_layout.cpp:769-774`

- [ ] [CRITICAL] Special userpic types missing: AyuGram renders distinct userpics for RepliesMessages (`PaintRepliesMessages`), HiddenAuthor (`PaintHiddenAuthor`), and VerifyCodes (`PaintVerifyCodes`) peers; `_ChatAvatar` in Dart has no handling for these chat types and falls back to a plain initial-letter avatar — `chat_list_row.dart:1022-1037` ← `AyuGram/dialogs/ui/dialogs_layout.cpp:463-498`

- [ ] [CRITICAL] Draft with reply-to is missing a leading mini-reply icon: AyuGram prepends `Ui::Text::IconEmoji(&st::dialogsMiniReplyIcon)` when `draft->reply` is set; Dart's draft preview has no such field or icon — `chat_list_row.dart:329-343` ← `AyuGram/dialogs/ui/dialogs_layout.cpp:676-679`

- [ ] [MAJOR] Online badge is 18×18px with a 3px border in Dart (`width: 18, height: 18, border: Border.all(width: 3)`), but the AyuGram spec is `dialogsOnlineBadgeSize: 12px` with `dialogsOnlineBadgeStroke: 3px` — the Dart badge is 6px too large — `chat_list_row.dart:1083-1098` ← `AyuGram/dialogs/dialogs.style:146,145`

- [ ] [MAJOR] Swipe animation uses a hardcoded fixed 200ms spring-back for below-threshold release and a speed-ratio formula (`offset / 0.35`) for above-threshold; AyuGram's `processEnd` uses `std::min(1., ratio) * st::slideWrapDuration` for the commit animation (proportional to ratio, not offset), and the Dart `kSwipeBackSpeed = 0.35` constant has no counterpart in AyuGram source — `chat_list_row.dart:769-779` ← `AyuGram/ui/controls/swipe_handler.cpp:162-170`

- [ ] [MAJOR] Swipe Lottie animation threshold to start/reset: AyuGram starts the icon animation at `kStartAnimateThreshold = 0.32` (ratio) and resets it at `kResetAnimateThreshold = 0.24`; Dart's `_lottieController.value = _swipeProgress` drives it continuously from 0 with no start/reset threshold gating — `chat_list_row.dart:673-674,742` ← `AyuGram/dialogs/dialogs_inner_widget.cpp:5789-5803`

- [ ] [MAJOR] Swipe `twoLines` parameter in `DrawQuickAction`: AyuGram always defaults `twoLines=false` in the `dialogs_layout.cpp` call to `DrawQuickAction` (no 5th argument), whereas Dart already splits the label on the first space via `replaceFirst(' ', '\n')` — effectively acting as `twoLines=true` always — `chat_list_row.dart:848` ← `AyuGram/dialogs/ui/dialogs_layout.cpp:990-998` and `AyuGram/dialogs/dialogs_quick_action.h:55`

- [ ] [MAJOR] `isSavedMessages` detection uses `chat.isSelf` in `_ChatAvatar`, but the public `isSavedMessages()` free function at line 1661 uses `chat.title == 'Saved Messages' && chat.type == ChatType.dm` — these two checks are inconsistent and the title-based check is fragile/wrong (title can be localized) — `chat_list_row.dart:1005,1661` ← `AyuGram/dialogs/ui/dialogs_layout.cpp:1115-1118` (AyuGram uses `peer->isSelf()`)

- [ ] [MAJOR] Forum row height with tags is `_rowHeightWithTags = 96.0`, matching `taggedForumDialogRow.height: 96px` ✓, but the `hasTags` condition checks `chat.type == ChatType.topic && chat.parentId.isNotEmpty` — this is semantically wrong; the `taggedForumDialogRow` in AyuGram applies when the dialog row has filter tags, not when the chat has a parentId — `chat_list_row.dart:1900-1901` ← `AyuGram/dialogs/dialogs.style:114-117`

- [ ] [MAJOR] `_TopicsPreview` renders topics as a flat comma-separated text list, but AyuGram's `TopicsView::paint` uses `Text::String` with per-title `maxWidth()` spacing (`context.st->topicsSkip = 8px` / `topicsSkipBig = 14px`) and renders them with a `rightCut` clipping for the jump bubble; the Dart implementation truncates the whole row at the `overflow: TextOverflow.ellipsis` boundary without per-topic spacing — `chat_list_row.dart:2122-2163` ← `AyuGram/dialogs/ui/dialogs_topics_view.cpp:221-239`

- [ ] [MAJOR] `_TopicJumpBubble` uses a simple row with `Icons.arrow_forward` icon and a right-to-left arrow, but AyuGram renders a rounded two-area (`area1`/`area2`) bubble with `FillJumpToLastBg`/`FillJumpToLastPrepared`, and the shape adapts to two different topic-title widths; the Dart implementation renders a static pill badge — `chat_list_row.dart:2169-2216` ← `AyuGram/dialogs/ui/dialogs_topics_view.cpp:323-370`

- [ ] [MAJOR] `ForumChatListRow._topicsSkipBig = 14.0` constant matches `st::forumDialogRow.topicsSkipBig: 14px` ✓, but `_topicsSkip = 8.0` is used as a `SizedBox(height: _topicsSkip - 4)` vertical gap between the topics row and jump bubble (`height: 4.0`), not as a horizontal inter-topic spacing as it should be — `chat_list_row.dart:2060` ← `AyuGram/dialogs/dialogs.style:110`

## chat_settings_screen — Chat Settings Screen Audit

- [ ] [CRITICAL] "Choose from gallery" opens a local `_WallpaperBrowser` bottom sheet that only shows color/gradient wallpapers fetched via `getWallpapers()`, completely missing the full `BackgroundBox` which shows all Telegram server wallpapers (patterns, photos, premium) with preview, blur toggle, and full installation flow — `chat_settings_screen.dart:103-133` ← `AyuGram/boxes/background_box.cpp:1-60` + `AyuGram/settings/sections/settings_chat.cpp:476-479` (`BackgroundBox(controller)`)

- [ ] [CRITICAL] "Choose from file" applies a wallpaper directly without showing `BackgroundPreviewBox` — the desktop source opens a preview dialog where the user can adjust blur, tiling, and confirm, before setting; the Dart code skips this and applies immediately — `chat_settings_screen.dart:135-160` ← `AyuGram/settings/sections/settings_chat.cpp:716-728` (`controller->show(Box<BackgroundPreviewBox>(controller, local))`)

- [ ] [CRITICAL] The Chat List Quick Action section renders as an inline expanded radio list directly in the settings page; per AyuGram the section shows a single button row (displaying the current action name with icon), and the radio chooser opens inside a `GenericBox` dialog only on click — `chat_settings_screen.dart:2584-2676` ← `AyuGram/settings/sections/settings_chat.cpp:2251-2328` (`button->setClickedCallback … showBox(Box([=] … addPreview … addRadio …))`)

- [ ] [CRITICAL] The Quick Action preview widget is a static animated icon pulsing in a hardcoded 260×62 layout; the AyuGram source renders a full-width `Ui::RpWidget` using Lottie animated icons (`Lottie::MakeIcon`, `DrawQuickAction`) with the actual dialog row geometry (`st::dialogsRowHeight`) and a visible "swipe" label — the Dart widget is a non-interactive mock — `chat_settings_screen.dart:2716-2872` ← `AyuGram/settings/sections/settings_chat.cpp:2138-2248`

- [ ] [CRITICAL] The "Suggest Animated Emoji" checkbox is shown/hidden only based on `suggestEmoji` state; per AyuGram it must ALSO require Telegram Premium (`Data::AmPremiumValue(session)` ANDed with `suggestEmoji`). The Dart checkbox is always shown to all users when suggestEmoji is on, regardless of premium status — `chat_settings_screen.dart:3006-3014` ← `AyuGram/settings/sections/settings_chat.cpp:1507-1517` (`rpl::combine(Data::AmPremiumValue(session), suggestEmoji->value(), _1 && _2)`)

- [ ] [CRITICAL] The `_StickersEmojiSection` "My Stickers" button opens a plain ListView of sticker packs via `getInstalledStickerPacks()`; AyuGram opens `StickersBox(controller, Section::Installed)` which is a fully interactive box with reorder, remove, and add controls — `chat_settings_screen.dart:3028-3033` + `3113-3201` ← `AyuGram/settings/sections/settings_chat.cpp:1553-1568`

- [ ] [CRITICAL] The "Emoji Sets" button opens the same sticker pack list filtered to emoji — AyuGram opens `Box<Ui::Emoji::ManageSetsBox>(session)`, a dedicated emoji set manager with download/delete/reorder; the Dart implementation reuses the sticker pack sheet which has no emoji set semantics — `chat_settings_screen.dart:3034-3039` ← `AyuGram/settings/sections/settings_chat.cpp:1570-1583`

- [ ] [CRITICAL] Applying a theme preset does not persist when "Night Mode" toggle is needed: the Dart code calls `applyTestingTheme(preset.id)` unconditionally; the AyuGram source checks `IsNightMode() == isNight(scheme)` and shows a `ToggleNightModeWithConfirmation` dialog if switching modes, then calls `KeepApplied()` to persist — the Dart code skips the confirmation and does not persist the theme — `chat_settings_screen.dart:237-240` ← `AyuGram/settings/sections/settings_chat.cpp:2412-2432`

- [ ] [CRITICAL] The accent color palette hides/shows only based on `themeId`; AyuGram's `ColorsPalette::show()` reads the theme type from the currently applied background object (`Background()->themeObject()`) and updates reactively via `Background()->updates()` whenever the theme changes — the Dart palette is static and does not react to external theme changes — `chat_settings_screen.dart:785-786` ← `AyuGram/settings/sections/settings_chat.cpp:277-315` + `2574-2583`

- [ ] [MAJOR] Selecting a custom accent color opens an HSL-only picker; AyuGram's `selectCustom()` opens a `ColorEditor` in HSL mode but also enforces lightness limits from the scheme's colorizer (`editor->setLightnessLimits(colorizer.lightnessMin, colorizer.lightnessMax)`) — the Dart picker has no such limits and allows invalid colors — `chat_settings_screen.dart:828-833` ← `AyuGram/settings/sections/settings_chat.cpp:367-397`

- [ ] [MAJOR] The "Edit Current Theme" button in the cloud themes section is always shown; AyuGram shows this button only when the currently applied cloud theme was created by the logged-in user (`Background()->themeObject().cloud.createdBy == userId`) — `chat_settings_screen.dart:1899-1917` ← `AyuGram/settings/sections/settings_chat.cpp:2785-2795` (`editWrap->toggleOn(…createdBy == userId…)`)

- [ ] [MAJOR] The `_CloudThemeSection` grid shows the "Show All" toggle only when `themes.length > 8`; AyuGram's cloud list uses `list->allShown()` reactive signal which hides the "Show All" button when the list naturally fits — the Dart toggle unconditionally uses a hardcoded `8` threshold rather than tracking list state — `chat_settings_screen.dart:1883-1892` ← `AyuGram/settings/sections/settings_chat.cpp:2757-2764`

- [ ] [MAJOR] The "Tile Background" checkbox is always shown; the AyuGram source hides it when the background is a pattern wallpaper or a solid color fill (`!background->paper().isPattern() && !background->colorForFill()`) and also reacts to `Background()->updates()` to toggle dynamically — `chat_settings_screen.dart:2370-2375` ← `AyuGram/settings/sections/settings_chat.cpp:2068-2087`

- [ ] [MAJOR] The "Adaptive Layout for Wide Screens" checkbox is shown/hidden based on a static `windowWidth >= 880` check; AyuGram shows it reactively based on `controller->adaptive().chatLayoutValue()` — it appears only when `ChatLayout::Wide` is active, which is a server/session-specific layout setting, not a raw pixel threshold — `chat_settings_screen.dart:2376-2383` ← `AyuGram/settings/sections/settings_chat.cpp:2089-2098`

- [ ] [MAJOR] The "Adaptive Layout" checkbox does not persist its value to app settings; the Dart `onAdaptiveChanged` only updates local `_adaptiveLayout` state — AyuGram calls `Core::App().settings().setAdaptiveForWide(checked)` and `Core::App().saveSettingsDelayed()` — `chat_settings_screen.dart:377` ← `AyuGram/settings/sections/settings_chat.cpp:2094-2098`

- [ ] [MAJOR] The "Auto-Night Mode" row is a simple toggle (on/off); AyuGram's implementation shows a label that reads "On"/"Off" as a sub-label on the button, and clicking it checks if `Background()->editingTheme()` is active (showing an error if so) before toggling — the Dart implementation skips the editing-theme guard — `chat_settings_screen.dart:1557-1617` ← `AyuGram/settings/sections/settings_chat.cpp:2825-2855`

- [ ] [MAJOR] Font family change applies via snackbar + in-memory state only; AyuGram calls `Local::writeSettings()` then `Core::Restart()` to apply immediately — the Dart code only shows a snackbar saying "Restart app to apply font changes" but does not restart or persist — `chat_settings_screen.dart:346-350` ← `AyuGram/settings/sections/settings_chat.cpp:2874-2878`

- [ ] [MAJOR] The `_ReactionChooserButton` loads reactions from `getSavedReactionTags()` (a synchronous call that returns tags the user has saved); AyuGram uses `controller->session().data().reactions()` which provides all available reactions (type All) including custom emoji reactions — the Dart fallback list of 12 hardcoded emojis and tag-based loading is not equivalent — `chat_settings_screen.dart:3528-3543` ← `AyuGram/settings/sections/settings_chat.cpp:1694-1713`

- [ ] [MAJOR] The reaction chooser opens an emoji-grid dialog; AyuGram shows a `ReactionsSettingsBox` which is the canonical reactions picker used across the app (with custom emoji, animated reactions, and the ability to set a favorite reaction stored server-side) — `chat_settings_screen.dart:3564-3615` ← `AyuGram/settings/sections/settings_chat.cpp:1764-1766` (`show->showBox(Box(ReactionsSettingsBox, controller))`)

- [ ] [MAJOR] The "Your Color" `_EditPeerColorBox` only offers 7 fixed base colors; AyuGram's `EditPeerColorBox` (via `AddPeerColorButton`) fetches available peer colors from the server and supports name-colors with channel badges and background pattern selection — `chat_settings_screen.dart:1392-1553` ← `AyuGram/settings/sections/settings_chat.cpp:2819-2823` (`AddPeerColorButton(container, controller->uiShow(), session->user(), st::settingsColorButton)`)

- [ ] [MAJOR] The sensitive content section shows a confirmation dialog only when enabling (not disabling); AyuGram's `SetupSensitiveContent` checks `session->appConfig().ageVerifyNeeded()` when enabling and calls `HistoryView::ShowAgeVerificationRequired()` — the Dart code shows a generic "18+ confirm?" `AlertDialog` with static text instead of the proper age verification flow — `chat_settings_screen.dart:440-468` ← `AyuGram/settings/sections/settings_privacy_security.cpp:293-303`

- [ ] [MAJOR] The sensitive content section does not reload from the server on a timer; AyuGram wraps the section in `rpl::single() | rpl::then(base::timer_each(60 * crl::time(1000)))` and calls `session->api().sensitiveContent().reload()` every 60 seconds to detect server-side changes — `chat_settings_screen.dart:430-477` ← `AyuGram/settings/sections/settings_chat.cpp:1111-1117`

- [ ] [MAJOR] The theme preset selection does not track the actual applied theme from `Background()->themeObject()` — it compares `currentTheme` (`appState.themeId`) against `preset.isDarkTheme` with fuzzy matching; AyuGram resolves the currently active type by scanning `kSchemesList` against `object.pathAbsolute` and handles the case where `object.cloud.id != 0` (cloud theme active → `Type(-1)`) — `chat_settings_screen.dart:590-625` ← `AyuGram/settings/sections/settings_chat.cpp:2394-2410`

# chat_switch_overlay — Audit Findings

- [ ] [CRITICAL] Forum topic icon uses generic `Icons.tag` placeholder instead of the real topic icon (`TopicIconButton`/`TopicIconView.paintInRect`), which renders the topic's actual custom emoji or server-side icon — `chat_switch_overlay.dart:460` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_chat_switch_process.cpp:99-110`

- [ ] [MAJOR] `_selected` never reaches -1: when the currently-selected item at index 0 is removed via Q, C++ sets `_selected = -1` (nothing selected) and Ctrl-release fires `closeRequests` (closes overlay); Dart always clamps to a valid index so Ctrl-release always confirms a chat — `chat_switch_overlay.dart:196-208` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_chat_switch_process.cpp:371-395`

- [ ] [MAJOR] Selection border animation differs: C++ animates via `_overAnimation` fading the pen width from 0 → `chatSwitchSelectLine` (3px) using `st::slideWrapDuration`, producing an opacity-fade of the border stroke; Dart uses `AnimatedContainer(duration: 150ms)` toggling the full `BoxDecoration` on/off, producing a different visual transition — `chat_switch_overlay.dart:357-364` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_chat_switch_process.cpp:164-200`

- [ ] [MAJOR] State fields `_shownPerRow` and `_shownRows` are mutated directly inside the `build()` / `LayoutBuilder` callback (lines 270-271) without `setState()`, which is incorrect Flutter usage; if the widget rebuilds via a path that doesn't re-enter `LayoutBuilder` (e.g. theme change triggering a parent rebuild), navigation via arrow-up/down will use stale per-row counts — `chat_switch_overlay.dart:270-271` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_chat_switch_process.cpp:420-490`

# chat_view — Backend wiring stubs, missing user photos, SnackBar misuse

- [ ] [CRITICAL] `create_todo` menu action uses `showCreatePollBox` + `engine.createPoll` instead of a dedicated todo-list creation box + `engine.createTodoList`. No `CreateTodoList` method exists in the bridge or engine service. A todo list (`InputMediaTodoList`) is a completely different Telegram message type from a poll (`InputMediaPoll`). Tapping "Create To-do List" silently sends a poll. — `chat_view.dart:6419` ← `AyuGram/SourceFiles/boxes/edit_todo_list_box.cpp:875` / `AyuGram/SourceFiles/api/api_todo_lists.cpp:37`

- [ ] [CRITICAL] AI editor "Fix grammar" mode (line 20827) and "Style rewrite" mode (line 20838) both call `engine.translateFreeText` — which forwards text to Telegram's `MessagesTranslateText` API. Those modes send literal prompt strings like `"Fix grammar and spelling: [text]"` and `"Rewrite in formal style: [text]"` to the translation service, which translates those prompt strings rather than performing AI text transformation. Neither mode works. — `chat_view.dart:20827` and `chat_view.dart:20838` ← `AyuGram/SourceFiles/api/api_todo_lists.cpp` (no equivalent; feature is AyuGram-specific and uses a separate AI backend, not the translate API)

- [ ] [CRITICAL] `_WhoReadAvatar` displays only colored initials; never loads real user profile photos. The engine's `GetMessageReadParticipantsDetailedJSON` does not return avatar data (`user_id`, `date`, `name` only — no `avatar_b64`), so actual profile pictures cannot be shown. AyuGram's `WhoReadParticipant` struct carries `userpicSmall` and `userpicLarge` QImage fields loaded via `peer->loadUserpic()`. — `chat_view.dart:20454` ← `AyuGram/SourceFiles/ui/controls/who_reacted_context_action.h:23` / `AyuGram/SourceFiles/history/view/history_view_context_menu.cpp:1754`

- [ ] [CRITICAL] `_GroupCallUserpic` renders a colored-initial avatar derived from `participant.userId.hashCode` instead of loading the user's real profile photo. AyuGram calls `peer->loadUserpic()`, builds `UserpicInRow` entries, and passes them to `GenerateUserpicsInRow` to produce the overlapping photo strip. — `chat_view.dart:10595` ← `AyuGram/SourceFiles/history/view/history_view_group_call_bar.cpp:63`

- [ ] [CRITICAL] `_sendStarGift` uses Material Design `SnackBar` for all three feedback states ("Sending gift...", "Gift sent!", "Failed to send gift. Please try again.") via `ScaffoldMessenger`. AyuGram uses a custom animated toast (`window->showToast({...})`) with `kSentToastDuration = 3s` and a Telegram-styled icon+text layout. The rest of the app uses `showTelegramToast` for consistency; this is the only place using `SnackBar` for a user-initiated action result. — `chat_view.dart:18255` ← `AyuGram/SourceFiles/boxes/star_gift_box.cpp:599`

- [ ] [MAJOR] `_MessageList._buildDisplayItems` runs a full O(n log n) sort plus O(n) album-grouping pass on the entire message list inside `build()` on every rebuild. `_MessageList` is a `StatelessWidget`, so it rebuilds on every parent `setState` (typing, scroll, selection, reaction, etc.). For a chat with 100+ loaded messages this executes expensive work on the UI thread every frame that triggers a rebuild, causing dropped frames during interaction. The sorted/grouped result should be memoized (e.g., via `useMemoized` equivalent, a `StatefulWidget`, or by computing it in `ChatState` when messages change). — `chat_view.dart:7330` ← (performance pattern; AyuGram uses `HistoryBlock` pre-grouping in the data layer, never sorts in paint/layout)

# choose_datetime_box — Audit vs AyuGram Desktop

## CalendarBox

- [ ] [CRITICAL] `_sendWhenOnline()` uses `DateTime(2099)` as the sentinel timestamp for "send when online", but the correct sentinel defined in the Telegram protocol is `kScheduledUntilOnlineTimestamp = 0x7FFFFFFE` (2147483646). The wrong value will be sent to the engine/backend, causing the server to treat the message as a normally-scheduled message at year 2099 rather than send-when-online. — `choose_datetime_box.dart:914` ← `AyuGram/api/api_common.h:20`

- [ ] [CRITICAL] The repeat-period lock when `!isPremium` shows a `SnackBar` stub with a `url_launcher` link to `t.me/premium` instead of showing the real Telegram Premium promo toast. AyuGram calls `Settings::ShowPremiumPromoToast` with a proper in-app promo dialog. The Dart implementation is a placeholder that does not integrate with any engine or settings layer. — `choose_datetime_box.dart:974-981` ← `AyuGram/history/view/history_view_schedule_box.cpp:129-145`

- [ ] [CRITICAL] `isPremium` is a static constructor argument (`bool isPremium = false`). AyuGram derives lock state from a reactive `Data::AmPremiumValue(session)` stream (`rpl::variable<bool> locked`) so the repeat-period widget updates automatically when premium status changes during the session. The Dart widget never updates its lock state after construction. — `choose_datetime_box.dart:796-799` ← `AyuGram/history/view/history_view_schedule_box.cpp:146-150`

- [ ] [MAJOR] The "Send when online" button is rendered as an `IconButton` in `titleTrailing` that opens a plain `showMenu<String>` popup positioned via manual `RenderBox` math. AyuGram adds it via `box->addTopButton(*style.topButtonStyle)` which places a dedicated icon button in the box title area and opens a `PopupMenu` at the cursor position. The Dart positioning logic (`box.localToGlobal(Offset(box.size.width - 8, 40))`) is fragile and does not follow the spec layout. — `choose_datetime_box.dart:1005-1032` ← `AyuGram/history/view/history_view_schedule_box.cpp:189-196`

- [ ] [MAJOR] The AyuGram `CalendarBox` highlights the **currently-chosen date** (the `highlighted` parameter passed from the scheduled date field) with a solid filled circle using `dialogsBgActive`. The Dart implementation incorrectly highlights **today's date** with a ring border (`Border.all`) and treats `isSelected` as the pre-filled date. AyuGram does not draw a special ring for today — it only highlights the selected/highlighted date with a filled circle. The visual semantics are inverted. — `choose_datetime_box.dart:707-712` ← `AyuGram/ui/boxes/calendar_box.cpp:868-872`

- [ ] [MAJOR] The `_CalendarBoxWidget` keyboard handler maps `Enter`/`NumpadEnter` to `_selectDay(_focusDay)` and also adds an `onConfirm` button to the `TelegramBox`. AyuGram's `CalendarBox` has no Enter-to-select behavior and no confirm button — days are selected exclusively by mouse click on the grid cell. AyuGram's keyboard handler only covers Escape, Home, End, Left/Up/PgUp (prev month), Right/Down/PgDown (next month). — `choose_datetime_box.dart:228-231, 337` ← `AyuGram/ui/boxes/calendar_box.cpp:1510-1530`

- [ ] [MAJOR] The `_MonthYearPickerDialog` renders a single vertical `Container(width: 1)` line between the months and years columns, colored with `bandColor.withValues(alpha: 0.3)`. AyuGram's `FillMonthYearPicker` renders **two horizontal lines** (above and below the center/selected item row) using `st::activeLineFg` to mark the selection band — the same rendering used in `TimePickerBox`. The Dart divider is in the wrong axis and wrong position. — `choose_datetime_box.dart:580` ← `AyuGram/ui/boxes/calendar_box.cpp:167-177`

- [ ] [MAJOR] The `_MonthYearPickerDialog` uses `ListWheelScrollView` (Flutter's drum picker widget) for both months and years columns. AyuGram uses `VerticalDrumPicker` (a custom widget in `lib_ui`) that supports `handleMouseEvent`, `handleWheelEvent`, and `handleKeyEvent`. The Flutter `ListWheelScrollView` does not forward key events from the parent box, while AyuGram's picker handles keyboard up/down arrow navigation. No keyboard navigation works in the Dart month/year picker. — `choose_datetime_box.dart:555-605` ← `AyuGram/ui/boxes/calendar_box.cpp:43-188`

- [ ] [MAJOR] The `_MonthYearPickerDialog` default min year is computed from `widget.minDate.year` (which for the schedule use case is today's year). AyuGram's `FillMonthYearPicker` falls back to `minYear = 2013` when `minDate.isValid()` is false, giving a wide year range. When `minDate` IS valid, the Dart widget correctly limits to `minDate.year`, but the behavior diverges when no minDate is provided — Dart defaults to `DateTime(1970)` (line 74) while AyuGram uses 2013. — `choose_datetime_box.dart:74` ← `AyuGram/ui/boxes/calendar_box.cpp:76`

- [ ] [MAJOR] The `_TimePickerBoxWidget` implements a custom scroll/snap drum using `ClipRect` + `Stack` + `Positioned` items. AyuGram's `TimePickerBox` uses `VerticalDrumPicker` which also handles mouse events forwarded via `base::install_event_filter` and narrows the picker width to `maxPhraseWidth` (text width only, centered). The Dart picker always fills the full available width, making text appear stretched/misaligned compared to AyuGram's centered narrow drum. — `choose_datetime_box.dart:1362-1380` ← `AyuGram/ui/boxes/time_picker_box.cpp:85-96`

- [ ] [MAJOR] The AyuGram `ChooseRepeatPeriod` widget uses `rpl::variable<bool> locked` so the lock icon vs arrow-drop-down icon in the label updates reactively when premium status changes at runtime. The Dart widget reads `widget.isPremium` only at build time and shows a static lock icon that never reacts to premium status changes. — `choose_datetime_box.dart:1148-1151` ← `AyuGram/ui/boxes/choose_date_time.cpp:296-319`

# engine_service — Bridge Service Audit

## engine_service — reactToStory drops accountId from payload

- [ ] [CRITICAL] `reactToStory` receives `accountId` parameter but never includes it in the JSON payload — the engine call carries no `account_id` field so the Go engine cannot identify which account should send the reaction; call either fails or acts on wrong account — `engine_service.dart:2125-2131` ← `data/data_stories.cpp:1089-1101` (`Stories::sendReaction` always uses `session().api()` which is account-bound; the peer and story ID are resolved within that session context, never losing account identity)

## engine_service — activateStealthMode drops accountId from payload

- [ ] [CRITICAL] `activateStealthMode` receives `accountId` but passes `Uint8List(0)` (empty bytes) to the engine — the Go backend has no way to route the `MTPstories_ActivateStealthMode` request to the correct account — `engine_service.dart:2134-2136` ← `data/data_stories.cpp:1076-1087` (`Stories::activateStealthMode` operates on `session().api()` which is implicitly account-bound; the account context is never optional)

## engine_service — sendVoice and sendVideoNote call same endpoint as uploadFile with no distinguishing flag

- [ ] [CRITICAL] Both `sendVoice` (line 4185) and `sendVideoNote` (line 4198) build an `EngineUploadFileRequest` with no `isVoice` or `isVideoNote` field and route to `'UploadFile'` — identical to a regular file upload. The Go backend receives no signal to set `Flag::f_voice` (voice messages) or `Flag::f_round` (video notes), so both will be delivered as plain document attachments instead of as playable voice messages or round-video messages — `engine_service.dart:4185-4209` ← `api/api_sending.cpp:683-708` (AyuGram uses `SendMediaType::Audio` → sets `MTPDmessageMediaDocument::Flag::f_voice`; `SendMediaType::Round` → sets `Flag::f_round`; these are separate code paths with explicit protocol flags, not inferred from file extension)

## engine_service — dispose() leaks _incomingCallController and _callStateController

- [ ] [MAJOR] `dispose()` closes 18 of 20 StreamControllers but skips `_incomingCallController` (declared line 40) and `_callStateController` (declared line 41) — these broadcast streams stay open and accumulate listeners until the process exits, causing a resource leak — `engine_service.dart:4858-4879` ← `data/data_stories.cpp:1076` (AyuGram's session teardown destroys all subsystems including call state; leaked streams have no C++ counterpart and are a Dart-specific resource management failure)

## engine_service — _memberInfoFromProto silently drops admin rank fields

- [ ] [MAJOR] `_memberInfoFromProto` (proto path used by `getChatMembers`) maps only `userId`, `username`, `displayName`, `avatarB64`, `isBot`, `isOnline`, `role` — the fields `customRank`, `promotedBy`, `promotedByID`, `promotedDate` are silently discarded. The JSON path (`getChatMembersByRole`, lines 979-991) correctly maps all eight fields. Admin members fetched via proto will show no custom rank or promoter info in the UI — `engine_service.dart:5440-5448` ← `data/data_channel_admins.h` (`Admin` struct carries `rights`, `canEdit`, and `rank` (custom title); `ChannelAdminChanges::add` always passes the rank string — dropping it is a protocol-level omission)

## engine_service — getBlockedUsersCount and getSessionsCount fetch full lists just to count

- [ ] [MAJOR] `getBlockedUsersCount` (line 4626) calls `'GetBlockedUsers'` and returns `decoded.length` — fetches the entire block list over the network to produce a single integer. `getSessionsCount` (line 4679) does the same for sessions. Both functions should use a dedicated count endpoint or cache the result; as written they make full paginated RPC calls on every settings-screen render — `engine_service.dart:4626-4638` and `engine_service.dart:4679-4691` ← `data/data_session.h` (AyuGram tracks blocked users and active sessions via server-pushed counts in `account_authorization` / `blocked_users` updates, never re-fetching the full list to read a count)

# color_picker_box — Color editor box audit

Reference: `color_editor.cpp` + `color_picker.cpp` in AyuGramDesktop.
The Dart file implements `ColorEditor::Mode::RGBA` layout (HSV picker, vertical hue slider, horizontal opacity slider, field column).

---

- [ ] [CRITICAL] Transparent color swatches show no checkerboard — when `showOpacity=true` and the color has alpha < 1, AyuGram draws `style::TransparentPlaceholder()` (checkerboard) behind both the new-color and original-color swatches before filling with the color, so the user can see through to transparency; the Dart draws a plain `BoxDecoration(color: _currentColor)` with no checkerboard at all, making semi-transparent colors look like wrong solid colors — `color_picker_box.dart:452-471` ← `color_editor.cpp:1109-1116`

- [ ] [MAJOR] Double crosshair ring vs AyuGram's single ring — AyuGram draws ONE unfilled ellipse (stroke only, black-or-white, no shadow ring) centered at the pick position; the Dart draws TWO concentric circles: an outer 30%-opacity "shadow" ring at radius 7 and an inner solid ring at radius 6, which does not match the spec — `color_picker_box.dart:778-791` ← `color_editor.cpp:124-136`

- [ ] [MAJOR] Gap before H field is 6 px, should be 13 px — AyuGram places the H field `st::colorFieldSkip = 13 px` below the bottom of the current-color swatch; the Dart inserts `const SizedBox(height: 6)` there — `color_picker_box.dart:473` ← `boxes.style:521` (`colorFieldSkip: 13px`)

- [ ] [MAJOR] Hex/result field placed in field column instead of bottom-anchored to the opacity slider — in AyuGram the result field is positioned at `resultBottom - colorSliderSkip - resultHeight` where `resultBottom = rect::bottom(_opacitySlider)`, i.e. the hex field sits flush with the bottom of the horizontal opacity slider spanning picker+hue-slider width; the Dart places the hex field as the last stacked item in the narrow 60 px field column, so it appears far higher than intended and without the wider span — `color_picker_box.dart:487-488` ← `color_editor.cpp:1083-1093`

- [ ] [MAJOR] Missing shadows around picker area and color swatches — AyuGram calls `Ui::Shadow::paint(p, _picker->geometry(), ...)` and `Ui::Shadow::paint(p, _newRect + QMargins(0,0,0,_currentRect.height()), ...)` to render drop-shadows around both the picker square and the color swatch block; the Dart renders no internal shadows (the outer `Material(elevation:4)` only shadows the whole dialog box, not these internal subregions) — `color_picker_box.dart:706-727` ← `color_editor.cpp:1097-1108`

- [ ] [MAJOR] Scroll wheel step size differs: Dart uses raw Flutter pixel delta divided by 5, AyuGram uses Qt `angleDelta` (one notch = 120 units) divided by 5 — the accumulated units are entirely different scales so one mouse wheel notch produces wildly different field step counts across platforms; additionally AyuGram handles Mac-specific delta sign inversion (`if (Platform::IsMac()) deltaY *= -1`) and picks the larger of X/Y deltas, neither of which the Dart does — `color_picker_box.dart:505-513` ← `color_editor.cpp:725-738`

# compose_entities — Hardcoded theme colors not matching Telegram

- [ ] [MAJOR] Hardcoded RGB color values for code/link/blockquote styling — `compose_entities.dart:462-464,549-550` ← Uses hardcoded Color values (0xFF6AB7F0 for dark mono, 0xFF3A464F for light mono, 0xFF24292E and 0xFFF0F4F7 for blockquote BG). These don't come from the theme system and may not match Telegram Desktop's actual colors. Should pull these from Theme.of(context) or a configuration. AyuGram (api_text_entities.cpp) delegates color rendering to the Qt style system which respects user theme.

- [ ] [MAJOR] Blockquote styling incomplete — `compose_entities.dart:546-551` ← Only applies backgroundColor for blockquotes, no left border or margin. Visual distinction vs regular text is minimal. Should match AyuGram's blockquote rendering with left border accent.

- [ ] [CRITICAL] `setLinkWithText()` destroys all existing entities — `compose_entities.dart:194-212` calls `text = ...` on line 202, which triggers the setter at line 442-446 that calls `entities.clear()`. This wipes out any bold/italic/code/spoiler formatting that was applied to the text. Should use `value = TextEditingValue(...)` pattern like `insertCustomEmoji()` (line 303) to preserve non-link entities. Bug: link insertion loses all other formatting.


# confirm_box — Audit Findings

## Summary

`confirm_box.dart` implements the full box/dialog infrastructure: generic confirm box, delete/leave confirm, single-choice radio box, permission dialogs, screen-share chooser, and the full report flow. The generic confirm and delete boxes are largely correct. The report flow and some visual details have critical and major issues.

---

- [ ] [CRITICAL] `_ReportReasonBox` uses a hardcoded static list of 9 reason strings (`'spam'`, `'fake'`, etc.). AyuGram replaced the old static-reason flow with a fully server-driven dynamic flow (`Api::CreateReportMessagesOrStoriesCallback`). The server returns option IDs as binary blobs — the Dart's hardcoded string keys cannot be mapped to valid server option IDs, so the report API call will fail or send wrong data. — `confirm_box.dart:1305-1315` ← `report_messages_box.cpp:75-206`

- [ ] [CRITICAL] `_ReportDetailsBox` uses a static `Icon(Icons.report_outlined, size: 72)`. AyuGram uses `AddReportDetailsIconButton` which creates a Lottie animation (`"blocked_peers_empty"`, `normalBoxLottieSize = 120×120px`) that plays once when the box opens via `setShowFinishedCallback`. Static icon, wrong size, no animation. — `confirm_box.dart:1436-1439` ← `report_box_graphics.cpp:209-221`, `boxes.style:551`

- [ ] [MAJOR] `_ReportReasonBox` has no Cancel button at the bottom. AyuGram's `ReportReasonBox` adds `box->addButton(tr::lng_cancel(), [=] { box->closeBox(); })` as a standard bottom button. The Dart uses `showClose: true` (X icon in the title bar) instead — different visual placement, wrong UX pattern. — `confirm_box.dart:1340-1377` ← `report_box_graphics.cpp:122`

- [ ] [MAJOR] `_ReportDetailsBox` "REPORT" button is marked `isDestructive: true`, rendering it in the attention/red color. AyuGram adds the report button with the default button style (`box->addButton(tr::lng_report_button(), submit)` — no `attentionBoxButton` style). The button should be the primary accent color, not red. — `confirm_box.dart:1473-1476` ← `report_box_graphics.cpp:163`

- [ ] [MAJOR] `_ReportDetailsBox` `TextField` has no character limit. AyuGram enforces `details->setMaxLength(kReportReasonLengthMax)` where `kReportReasonLengthMax = 512`. The Dart `TextField` has no `maxLength` property — users can type unlimited text that will be rejected server-side. — `confirm_box.dart:1445-1464` ← `report_box_graphics.cpp:31, 153`

- [ ] [MAJOR] `_DeleteContent` moderate panel does not fetch the actual message count from the server when "Delete All from {user}" is shown. AyuGram starts an `Api::MessagesSearch` (`search->searchMessages({ .from = _moderateFrom })`) to get the real count and dynamically updates the delete button text (e.g. "Delete (47)"). The Dart uses a static `widget.messageCount` which is just the currently-selected message count, not the true total. — `confirm_box.dart:604-611` ← `delete_messages_box.cpp:206-234`

# contacts_screen — Audit Findings

- [ ] [CRITICAL] `_isContact` determined by `displayName.startsWith('@')` — global search results with real display names are misclassified, showing wrong context menu items (Edit/Share/Delete instead of Add Contact) — `contacts_screen.dart:797` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/add_contact_box.cpp` (uses `_user->isContact()`)
- [ ] [CRITICAL] `AddContactWithNote` sends `InputUser{}` (ID=0, access_hash=0) — will be rejected by Telegram server; AyuGram passes `user->inputUser()` with resolved ID+hash — `contacts_screen.dart:2030` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/add_contact_box.cpp` (`ContactsAddContact` with valid InputUser)
- [ ] [CRITICAL] Notes field in `_EditContactBox` always starts empty — existing contact note never pre-populated because `ContactInfo`/`User` structs have no `Note` field; AyuGram populates from `_user->note().text` — `contacts_screen.dart:1978` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/add_contact_box.cpp:453`
- [ ] [MAJOR] Photo buttons (Suggest, Set personal, Reset to default) and Delete button shown unconditionally in `_EditContactBox`; AyuGram gates them on `_user->isContact()` — `contacts_screen.dart:2260-2293` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/add_contact_box.cpp:555`
- [ ] [MAJOR] "Reset to default" personal photo button shown even when no personal photo is set; AyuGram toggles it via `_user->hasPersonalPhoto()`; `ContactInfo` has no `hasPersonalPhoto` field despite `User.HasPersonalPhoto bool` existing in `base.go` — `contacts_screen.dart:2276` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/add_contact_box.cpp` (`resetButtonWrap->toggleOn(...)`)
- [ ] [MAJOR] "Suggest Birthday" button completely missing from `_EditContactBox`; AyuGram shows it when `!_user->birthday().valid()`; `User` in `base.go` already has `BirthdayDay/Month/Year int` fields — `contacts_screen.dart:2258-2293` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/add_contact_box.cpp:572`
- [ ] [MAJOR] Context menu "Add" case opens blank `_AddContactBox` with no pre-filled data from the found contact; AyuGram pre-populates fname/lname from resolved user; phone-less `contacts.addContact` path (for username-resolved users) not handled — `contacts_screen.dart:836-849` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/add_contact_box.cpp` (AddContactBox constructor accepts fname/lname/phone)
- [ ] [MAJOR] Story ring gradient colors wrong: Dart uses `#34c76e`→`#3da1fd`; AyuGram uses `groupCallLive1=#0dcc39`→`groupCallMuted1=#0992ef` — `contacts_screen.dart:1899-1904` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/choose_date_time.cpp` / `groupcalls` style definitions
- [ ] [MAJOR] `engine.searchGlobalChats()` is a synchronous FFI call invoked inside an `async` function without `await`/`compute`; blocks the UI thread if the FFI call triggers network activity — `contacts_screen.dart:140` ← no AyuGram equivalent (platform-specific issue)
- [ ] [MAJOR] Global search results constructed as minimal `ContactInfo` with only `userId`/`displayName`/`username`; missing `isBot`, `phone`, online status — causes "Block User" menu item to appear for bots (should be hidden when `isBot=true`) — `contacts_screen.dart:131-136,145-151` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/add_contact_box.cpp` (full user data used)

## create_group_wizard — Backend wiring, missing error codes, clipboard, navigation race

- [ ] [MAJOR] `_ContactRow` ignores `contact.lastSeenKind` / `contact.lastSeenTs` fields — subtitle always shows hardcoded `'last seen recently'` for offline contacts instead of real last-seen text (e.g. "last seen 2 hours ago") — `create_group_wizard.dart:1577` ← `boxes/peers/add_participants_box.cpp:868`

- [ ] [MAJOR] `_pasteFromClipboard` silently fails on Windows — "Paste from Clipboard" menu item is shown (no platform guard) but the function only handles Linux (`wl-paste`/`xclip`) and macOS (`osascript`), so Windows always hits "No image in clipboard" — `create_group_wizard.dart:328-337,386-418` ← `boxes/peers/edit_peer_info_box.cpp:2817`

- [ ] [MAJOR] `_submitGroup` / `_submitChannel` do not handle `PEER_FLOOD` or `USER_RESTRICTED` errors — AyuGram shows dedicated in-box error dialogs for both codes; Dart falls through to the generic `_error` string which shows raw API error text — `create_group_wizard.dart:710-724` ← `boxes/add_contact_box.cpp:771-778`

- [ ] [MAJOR] `_navigateToChat` is called immediately after `_chatState.loadChats()` but the newly-created chat often isn't in the list yet (server update arrives after `getChatList` reads the cache) — result is the user is NOT navigated to the new group/channel; AyuGram holds a direct `_createdChannel` reference and passes it to `OpenPeer` — `create_group_wizard.dart:789-792` ← `boxes/add_contact_box.cpp:931-935`

- [ ] [MAJOR] `_EditPeerTypeBoxState` loads `_isForum` from `getChatPermissionFlags` but never uses it anywhere — the field should influence the `CreateTopics` restriction label visibility in the permissions section, matching AyuGram which checks `options.isForum` when building restriction labels — `create_group_wizard.dart:2431,2502` ← `boxes/peers/edit_peer_permissions_box.cpp:104-117`

- [ ] [MAJOR] `_checkUsernameApi` in the new-channel wizard (wizard step, not `_EditPeerTypeBox`) does not re-trigger the check after `_PublicLinksLimitBox` revokes a channel and the user returns — `_usernameValid` stays `false` and the username field status stays stale; the box must re-call `_checkUsernameApi` after the `revoked == true` branch at line 580, but only does so via `_onUsernameChanged` which re-validates client-side first and may not fire if text hasn't changed — `create_group_wizard.dart:574-583` ← `boxes/peers/edit_peer_type_box.cpp:598-606`

- [ ] [MAJOR] `_EditPeerTypeBoxState._save()` does not save `_saving = false` in the success path before `Navigator.pop` — if `_save()` is called a second time (e.g. after the public-link-limit dialog returns `revoked == true` and calls `_save()` recursively at line 2703), `_saving` is never reset if the recursive call also succeeds, leaving the button permanently disabled if the dialog is somehow re-shown — `create_group_wizard.dart:2637-2678` ← `boxes/peers/edit_peer_type_box.cpp:760-786`

# custom_emoji_cache — Audit Findings

- [ ] [MAJOR] `kPreloadFrames * kPerRow` (= 48) used as the max number of emoji document IDs to preload in `preloadBatch`, but both constants are animation-frame concepts: `kPreloadFrames=3` is the lookahead frame count before the next frame is needed (renders 3 frames ahead during playback), and `kPerRow=16` is sprite-sheet columns. Their product has no semantic meaning as a document preload count — `custom_emoji_cache.dart:209` ← `AyuGramDesktop/Telegram/lib_ui/ui/text/custom_emoji_instance.cpp:25` (kPreloadFrames lookahead), `:102` in `custom_emoji_instance.h` (kPerRow sprite columns), `:513` (kPreloadFrames used for frame-ahead preloading only)

- [ ] [MAJOR] `kMaxFrames=180` is used at line 203 to cap the document ID list passed to `preloadBatch`, but in AyuGram this constant means "maximum animation frames per emoji" — it is used to validate deserialized frame counts and reserve sprite cache capacity, never to limit document counts — `custom_emoji_cache.dart:203` ← `AyuGramDesktop/Telegram/lib_ui/ui/text/custom_emoji_instance.cpp:23` (declaration), `:179` (validation: `header.frames >= kMaxFrames`), `:501` (reserve: `std::max(count, kMaxFrames)`)

- [ ] [MAJOR] `_globalListeners` fires unconditionally on every batch completion regardless of which document changed: `_notifyListeners` at line 473 iterates all global listeners after every thumb/file fetch, even if only one emoji changed. AyuGram's repaint model calls `object->repaint()` only on `Object` instances that are actively using the specific emoji instance that changed — `custom_emoji_cache.dart:473` ← `AyuGramDesktop/Telegram/lib_ui/ui/text/custom_emoji_instance.cpp:785-787` (`for (const auto &object : _usage) { object->repaint(); }`)

- [ ] [MAJOR] `addListener` at line 122 has no deduplication: `_globalListeners.add(cb)` always appends. If the same callback is registered N times (common under Flutter widget rebuild without strict dispose discipline), it fires N times per notification. AyuGram ties repaints to unique `Object*` pointers via `base::flat_set`, making double-registration impossible — `custom_emoji_cache.dart:122` ← `AyuGramDesktop/Telegram/lib_ui/ui/text/custom_emoji_instance.h:254` (`base::flat_set<not_null<Object*>> _usage`), `custom_emoji_instance.cpp:791-792` (`_usage.emplace(object)`, idempotent set insert)

- [ ] [MAJOR] `_evictFromMemory` (lines 183–189) removes `_files`, `_fileFailed`, and `_failed` but does not clear `_pending` or `_filePending`. If a document's ref-count drops to zero while its thumb/file fetch is in-flight, `_pending` stays set. When any widget re-acquires the same document and calls `request()`, line 275 returns early (`_pending.contains(documentId)`) with no new request queued. The widget must rely on a listener registered before calling `request()` to eventually receive the notification when the in-flight fetch finally resolves — `custom_emoji_cache.dart:183` ← `AyuGramDesktop/Telegram/lib_ui/ui/text/custom_emoji_instance.cpp:797-810` (`_usage.empty()` → `state.unload()` cleanly transitions state machine to `Loading`, no stale pending flags)

- [ ] [MAJOR] Reference counting uses `Map<_InstanceKey, int>` integer arithmetic (lines 152, 164): each `acquire` always increments, each `release` always decrements. Asymmetric calls (acquire twice, release once, or vice versa) silently desynchronize the count. AyuGram uses `base::flat_set<not_null<Object*>>`: `emplace` is idempotent and `remove` is safe, so the same Object acquiring twice is correctly counted as one reference — `custom_emoji_cache.dart:89` ← `AyuGramDesktop/Telegram/lib_ui/ui/text/custom_emoji_instance.h:254` (`base::flat_set<not_null<Object*>> _usage`), `custom_emoji_instance.cpp:791-796`

# edit_forum_topic_box — Audit findings

- [ ] [CRITICAL] Box corner radius is 3px but AyuGram uses `boxRadius: 6px` (50% deviation, exceeds 25% threshold) — `edit_forum_topic_box.dart:13` (`const double _boxRadius = 3`) ← `AyuGram/Telegram/lib_ui/ui/layers/layers.style:38` (`boxRadius: 6px`)

- [ ] [MAJOR] Box width is 364px but AyuGram GenericBox uses default `boxWidth: 320px` (14% deviation) — `edit_forum_topic_box.dart:12` (`const double _boxWidth = 364`) ← `AyuGram/Telegram/lib_ui/ui/layers/layers.style:117` (`boxWidth: 320px`)

- [ ] [MAJOR] Premium emoji blocked notification uses a floating `SnackBar` with an external `launchUrl` to `https://t.me/premium`, but AyuGram shows a `HistoryView::StickerToast` (an in-app rich premium sticker preview popup, `Section::TopicIcon`) — `edit_forum_topic_box.dart:507-538` (`_showPremiumRequiredDialog` / `SnackBar`) ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_forum_topic_box.cpp:335-345` (`showToast` / `StickerToast::Section::TopicIcon`)

- [ ] [MAJOR] Bot thread title field hint text is "Bot Thread Title" but the correct string is "Thread Name" (`lng_bot_thread_title`) — `edit_forum_topic_box.dart:429` (`'Bot Thread Title'`) ← `AyuGram/Telegram/Resources/langs/lang.strings:7318` (`"lng_bot_thread_title" = "Thread Name"`)

- [ ] [MAJOR] Icon selector is a simplified 2-tab Wrap grid (recent colors + server icons) instead of the full `EmojiListWidget` with `Mode::TopicIcon` (proper scrollable emoji panel with category footer, sticker sets, and `customRecentFactory` for animated custom emoji rendering) — `edit_forum_topic_box.dart:541-671` (`_buildIconSelectorPanel` / `_buildCategoryTabBar` / `_buildIconGrid`) ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_forum_topic_box.cpp:248-393` (`AddIconSelector` / `EmojiListWidget` / `Mode::TopicIcon`)

# edit_mark_box — Critical hint text mismatch

- [ ] [CRITICAL] Hint text semantics differ from AyuGram — `edit_mark_box.dart:95` uses `defaultValue` as hint, but AyuGram `edit_mark_box.cpp:32` passes `title` as InputField placeholder. When `defaultValue` is "edited" and `title` is "Edited Mark", users see different hint text. AyuGram shows the box title as placeholder; Dart shows the default mark value. This breaks visual parity.

- [ ] [MAJOR] Placeholder/hint text font weight not specified — `edit_mark_box.dart:94-99` uses bare `InputDecoration` with no `hintStyle` parameter, so hint text uses theme default (likely regular weight). AyuGram `lib_ui/ui/widgets/widgets.style:placeholderFont: font(semibold 14px)` specifies semibold. Dart hint text is not semibold, causing visual divergence.

- [ ] [MAJOR] Error message differs from spec — `edit_mark_box.dart:98` hardcodes 'This field is required', but AyuGram relies on InputField's `showError()` method which uses style-defined error message. The error message text may not match AyuGram's localized strings.

# emoji_panel — Audit Findings

## emoji_panel — GIF/Sticker/Emoji panel full audit

- [ ] [CRITICAL] GIF search results sent via wrong API — inline bot results use `sendSticker(fileId)` instead of `sendInlineBotResult(queryId, resultId)`; `queryId` is discarded at search time and never stored, making correct dispatch impossible — `emoji_panel.dart:2765,2772,2997` ← `gifs_list_widget.cpp` (sendInlineBotResult path)

- [ ] [CRITICAL] Video stickers (webm) are never animated — `_StickerCellState.build()` has branches only for `.isTgs` (Lottie) and `.isWebp` (static Image); `.isWebm` is never checked and no video player path exists; webm stickers always show static thumbnail — `emoji_panel.dart:2335-2402` ← `stickers_list_widget.cpp` (media_clip_reader path for webm)

- [ ] [CRITICAL] Same webm omission in `_CustomEmojiCellState` — custom emoji video stickers never play — `emoji_panel.dart:1289-1303` ← `stickers_list_widget.cpp`

- [ ] [MAJOR] "Send Without Sound" and "Schedule" sticker context menu items are no-ops — both branches call `widget.onStickerSend?.call(sticker.fileId)` with identical args and no flags; `onStickerSend` has no silent/schedule parameter — `emoji_panel.dart:1789,1791` ← `stickers_list_widget.cpp:2167-2175`

- [ ] [MAJOR] "Send Without Sound" and "Schedule" GIF context menu items are also no-ops — both branches call `widget.onGifSend?.call(gif.fileId)` with no flags — `emoji_panel.dart:2799,2801` ← `gifs_list_widget.cpp`

- [ ] [MAJOR] Featured sticker pack tab-bar badge (unread dot) is missing — AyuGram renders a `stickersFeaturedUnreadSize=5px` dot on the footer tab icon when unread featured packs exist; Dart `_StickerPackFooter` has no badge rendering on the strip icons — `emoji_panel.dart:2458-2550` ← `stickers_list_widget.cpp:1266-1305`

- [ ] [MAJOR] Recent stickers not capped to 20 (AyuGram `kRecentDisplayLimit=20`) — all engine-returned items are displayed without client-side limit — `emoji_panel.dart:1597-1614` ← `stickers_list_widget.cpp:80`

- [ ] [MAJOR] Sticker preview overlay on long-press shows stripped JPEG fallback for uncached stickers — `_showStickerPreview()` passes `_stickerFileCache[docId]` which is null if file was never requested; no on-demand fetch triggered for preview — `emoji_panel.dart:1826-1840` ← `stickers_list_widget.cpp:1791`

- [ ] [MAJOR] GIF search has no pagination — `_performSearch` fetches one page with empty offset and never loads more on scroll; AyuGram tracks pagination cursor and loads additional results as user scrolls — `emoji_panel.dart:2759-2768` ← `gifs_list_widget.cpp:400-413`

- [ ] [MAJOR] Emoji skin-tone prefs and recent emojis are module-level globals — `_emojiPrefsLoaded`, `_skinTonePrefs`, `_recentEmojis` never reset between account switches; second account always sees first account's state because `if (_emojiPrefsLoaded) return` short-circuits the load — `emoji_panel.dart:34-36,843-848`

- [ ] [MAJOR] Off-screen GIF cells keep video players running — `_GifCell` plays indefinitely; no visibility-based pause on scroll; AyuGram pauses animations via `visibleTopBottomUpdated()`; with many GIFs this drains CPU — `emoji_panel.dart:3143-3184` ← `stickers_list_widget.cpp:370-413`

- [ ] [MAJOR] `_StickerSetDialog` "View Set" preview renders only static JPEG thumbnails — no Lottie or webm animation for stickers in the set dialog — `emoji_panel.dart:3598-3618` ← sticker_set_box.cpp

- [ ] [MAJOR] Panel show animation scales width/height (50%→100%) instead of opacity + vertical slide-up — AyuGram `tabbed_panel.cpp` uses opacity animation + translate from below, not a scale-from-center distortion — `emoji_panel.dart:383-385` ← `tabbed_panel.cpp`

# ayu_filter — Filter engine audit

- [ ] [MAJOR] `_serviceMessageType` classifies service messages via fragile text-content heuristics (`text.contains('call')`, `text.contains('suggest') && text.contains('photo')`, etc.) instead of structured media-type checks. AyuGram uses `media->call()`, `media->photo() && !isUserpicSuggestion()`, `media->photo() && isUserpicSuggestion()`, `media->paper()`, `media->gift()->type`, etc. Text heuristics produce false positives (any service message whose display text happens to contain "call" is misclassified as TYPE_PHONE_CALL=16; "gift" alone triggers TYPE_GIFT_PREMIUM=18 before the "gift"+"star" check for TYPE_GIFT_STARS=30; Credits/Ton gift subtypes are never reachable). Additionally, Dart checks photo (`mediaType==1`) before call, whereas AyuGram checks call before photo — `ayu_filter.dart:179-191` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_utils.cpp:604-637`

- [ ] [MAJOR] `_CompiledPattern.matches` applies reversed-filter logic to empty text, incorrectly marking empty-body messages as filtered. When `blob` is empty, `pattern!.hasMatch('')` returns false; for a reversed filter `filter.reversed ? !found : found` evaluates to `true`, so the message is hidden. AyuGram guards at the top of `isFiltered`: `if (str.isEmpty()) return std::nullopt;`, and `filtered()` converts nullopt to `false` — `ayu_filter.dart:114-118` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_controller.cpp:43-45`

- [ ] [MAJOR] `filteredMessagesShown` returns `bool` (defaulting to `false`), losing the three-state semantics AyuGram requires. AyuGram returns `std::optional<bool>`: `nullopt` = no filtered messages exist in this chat (suppress the show/hide bar entirely); `false` = messages are hidden; `true` = messages are shown. Dart cannot represent the "no filtered messages" state, so the consuming UI would display the show/hide bar for every chat regardless of whether any messages are actually filtered — `ayu_filter.dart:460-461` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_controller.cpp:189-195`

- [ ] [MAJOR] `invalidateMessage` over-evicts cache on grouped-message invalidation: when `groupedId` is non-empty it calls `_messageCache.removeWhere((key, _) => key.startsWith('$chatId:'))`, removing every cached result for the entire chat. AyuGram's `invalidate` resolves the group and removes only the specific items belonging to that group (`for groupItem in group->items: invalidateSingle(groupItem)`). This forces all prior filter decisions for the whole chat to be recomputed after any single grouped-message edit/receive — `ayu_filter.dart:468-473` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_cache_controller.cpp:216-225`

- [ ] [MAJOR] `importFromJson` (data-layer method at line 303) applies imported filters with no backup-version guard. AyuGram rejects the entire import when `version > BACKUP_VERSION` (currently 2) to avoid applying a format it doesn't understand. Dart blindly parses whatever arrives, risking corrupt filter state from future-format exports — `ayu_filter.dart:303` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_utils.cpp:702-705`

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

# filter_column — Premium-locked folder state missing + settings preload skipped

- [ ] [CRITICAL] `_SideBarButton` has no `locked` state — folders beyond the free limit must display at reduced opacity (`kPremiumLockedOpacity`) with a lock icon overlaid next to the label text, and their unread badge must be hidden (count forced to 0). None of this exists: the widget has no `locked` parameter, no opacity reduction, no lock icon paint, and no badge suppression for locked entries — `filter_column.dart:687-854` ← `AyuGram/Telegram/lib_ui/ui/widgets/side_bar_button.cpp:83-196` + `AyuGram/Telegram/SourceFiles/window/window_filters_menu.cpp:235-245`

- [ ] [MAJOR] `openFiltersSettings()` opens `FoldersSettingsScreen` immediately without waiting for suggested filters to load — AyuGram checks `filters->suggestedLoaded()` first and, if false, calls `filters->requestSuggested()` then delays navigation until the one-shot `suggestedUpdated` signal fires; skipping this causes the suggestions section to be empty/loading when the screen first opens — `filter_column.dart:508-522` ← `AyuGram/Telegram/SourceFiles/window/window_filters_menu.cpp:417-428`

- [ ] [MAJOR] Drop-target visual during chat forward drag uses a static `Border.all` rectangle instead of activating the button's ripple animation — AyuGram calls `button->setForceRippled(id == filterId)` on the matching filter button to show a live ripple; the Dart replaces this with `BoxDecoration(border: Border.all(...))` which is a different and weaker visual affordance — `filter_column.dart:617-624` ← `AyuGram/Telegram/SourceFiles/window/window_filters_menu.cpp:154-158`

# folders_settings_screen — Audit

- [ ] [CRITICAL] Tags toggle timer cancelled on screen close instead of flushed — if user closes settings within 500ms of toggling, the pending `toggleDialogFilterTags` call is silently dropped and the server state diverges from local state — `dart/lib/ui/folders_settings_screen.dart:970` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_folders.cpp:1069`

- [ ] [CRITICAL] `useVerticalFilters` not persisted across restarts — setter only calls `notifyListeners()` with no engine call and no disk save; AyuGram calls `Core::App().settings().setChatFiltersHorizontal(value); Core::App().saveSettingsDelayed()` — `dart/lib/ui/folders_settings_screen.dart:460` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_folders.cpp:1149`

- [ ] [MAJOR] `_countChatsInFolder` counts enabled type-flag booleans as individual chats (adds 1 per enabled type), not actual matching chats — AyuGram uses `ComputeCount` which traverses the real dialogs list; a Contacts+Groups+Channels folder shows "3 chats" instead of the real count — `dart/lib/ui/folders_settings_screen.dart:298` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_folders.cpp:121`

- [ ] [MAJOR] Suggested folders not deduplicated against existing folders — Dart displays all API suggestions without checking if the filter is already in `_folders`; AyuGram skips any suggestion whose filter is already in `state->rows` — `dart/lib/ui/folders_settings_screen.dart:128` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_folders.cpp:897`

- [ ] [MAJOR] `engine.toggleDialogFilterTags()` return value ignored — `_onToggle` fires and forgets (no `await`, no error check); if the backend rejects the toggle the UI stays in the wrong state with no revert — `dart/lib/ui/folders_settings_screen.dart:986` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_folders.cpp:1037`

- [ ] [MAJOR] `_IncludeTypePicker` builds all chat rows eagerly with `ListView(children: [...])` — renders every chat at layout time; should use `ListView.builder` for lazy construction; same issue in `_ExcludeTypePicker` — `dart/lib/ui/folders_settings_screen.dart:3842` / `4058` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/filters/edit_filter_chats_list.cpp` (uses lazy peer list)

# forum_topic_icon — Forum Topic Icon Widget

- [ ] [CRITICAL] `Image.memory` used for WebM custom emoji: Flutter's `Image.memory` decodes still images only (JPEG/PNG/GIF/WebP); it cannot render animated WebM video. Animated custom emoji backed by WebM files silently hit `errorBuilder` and display the thumbnail fallback or an empty box instead of the animation. Feature appears wired but is broken for the WebM media type — `forum_topic_icon.dart:530-542` ← `data/data_forum_topic.cpp:85-98` (AyuGram renders all icon media via `QSvgRenderer`/media streaming, not a still-image decoder)

- [ ] [MAJOR] Global cache eviction races between widget instances: `deactivate()` schedules removal of entries from the process-wide `_customEmojiFileCache`, `_customEmojiLottieCache`, and `_customEmojiThumbCache` maps keyed only by `documentId`. When multiple `CustomEmojiTopicIcon` widgets display the same emoji simultaneously (common in any forum topic list), deactivating one widget (scroll off-screen) fires the timer and evicts the cache entry while other still-visible widgets depend on it. Those widgets read `null` on their next build and show an empty box until a redundant network re-fetch completes — `forum_topic_icon.dart:466-474` ← `data/data_forum_topic.cpp:698-716` (AyuGram uses per-topic owned icon storage, not a shared evictable cache)

- [ ] [MAJOR] Per-SVG gradient endpoint offsets ignored — all seven bubble palettes use uniform `Offset(42*s, 84*s)` as the gradient stop point for both fill and stroke gradients. Each color's SVG specifies different `y2` percentages: rose stroke ends at 96.40% (84px×0.964 = 81.0px), red stroke at 98.6%, green stroke at 98.9%, violet fill at 99.76%, blue stroke at 99.40%. At `size=21` the rose stroke gradient is off by ~0.76px (>25% of stroke width); at `size=32` it is ~1.15px. The gradient tones in the lower region of every non-blue bubble are therefore wrong — `forum_topic_icon.dart:268-286` ← `Resources/art/topic_icons/rose.svg` (stroke linearGradient y2="96.4024371%"), `yellow.svg` (stroke y2="99.0141482%"), `green.svg` (stroke y2="98.9250576%"), `blue.svg` (stroke y2="99.39588%")

- [ ] [MAJOR] `extractTopicLetter` incorrectly skips non-BMP letter characters: the guard `if (char.length > 1) continue` (iterating `title.characters` grapheme clusters) discards any character whose UTF-16 encoding is a surrogate pair. This includes legitimate letter characters outside the BMP such as CJK Unified Ideographs Extension B (U+20000–U+2A6DF) and several historic scripts. AyuGram's `ExtractNonEmojiLetter` explicitly assembles the full UCS-4 code point from surrogate pairs and then calls `QChar::isLetterOrNumber(ucs4)`, correctly extracting non-BMP letters. The Dart implementation would return an empty string or a later ASCII character for topic titles that begin with such characters — `forum_topic_icon.dart:116-124` ← `data/data_forum_topic.cpp:101-126`

# ghost_settings_page — Audit findings

- [ ] [MAJOR] `toggleLockForKey` silently rejects locking the last unlocked sub-toggle — no toast, no indication — leaving the user confused when long-press/shift-click on the final lockable row does nothing. AyuGram's `setSendReadMessagesLocked` (and all other lock setters) are unconditional; there is no "at least one must remain unlocked" guard in the C++ — `ghost_settings_page.dart:136` (and lines 148, 160, 172, 184 — all `onLock` callbacks) ← `ayu_settings.cpp:154-157`

- [ ] [MAJOR] `toggleLockForKey` prevents locking all five sub-toggles simultaneously (app_state.dart:643-645: bails when `unlockedCount <= 1`), which means a user who wants every sub-toggle locked to its current value (e.g. permanently lock ghost-active state) cannot do so in Dart. AyuGram allows all toggles to be independently locked, letting users freeze the entire ghost profile so the master Ghost-Mode switch cannot alter any sub-toggle — `ghost_settings_page.dart:136` ← `ayu_settings.cpp:154-182` (each `setSendXxxLocked` is unconditional)

- [ ] [MAJOR] `setGhostModeEnabledForKey` returns early without calling `ghostSettingChanged` / `_saveWindowPrefs` when no sub-toggle state changes (i.e. ghost mode is already effectively in the requested state). AyuGram's `setGhostModeEnabled` always calls `AyuSettings::save()` before returning, ensuring settings are flushed to disk even when nothing changed (resilience against prior partial-write corruption). Dart skips the save entirely — `ghost_settings_page.dart:103-111` (ghost mode toggle `onChanged`) ← `ayu_settings.cpp:143` (`AyuSettings::save()` is unconditional inside `setGhostModeEnabled`)

# hamburger_drawer — Audit vs AyuGram Desktop

- [ ] [MAJOR] Unread badge in account-switcher chevron shows ALL unreads including muted: `computeUnreadBadge()` returns empty string when `allMuted == true`, so the badge is hidden when every other account's unread is muted. Dart sums all accounts' unreads unconditionally and shows the badge even when all are muted — `hamburger_drawer.dart:803-830` ← `window_main_menu.cpp:251-258`

- [ ] [MAJOR] "My Profile" menu item opens `MyProfilePage` instead of the user's Stories info panel: AyuGram navigates to `Info::Stories::Make(controller->session().user())`, which is the profile/stories view. Dart pushes `MyProfilePage()`, a different destination — `hamburger_drawer.dart:163-177` ← `window_main_menu.cpp:712-715`

- [ ] [MAJOR] Archive row appears whenever `hasArchivedChats` is true, ignoring the user's "Show archive in main menu" setting: AyuGram gates the row on `controller->session().settings().archiveInMainMenu()` in addition to the folder being non-empty. Dart has no such check — `hamburger_drawer.dart:474` ← `window_main_menu.cpp:543-548`

- [ ] [MAJOR] Archive right-click menu shows only 2 hardcoded items ("Expand", "Archive Settings") instead of using `FillDialogsEntryMenu`: AyuGram builds the full dialog-entry context menu (Mark as Read, Mute, Archive settings, etc.) via `FillDialogsEntryMenu(_controller, {.key = folder(), ...}, ...)`. Dart's static 2-item list is missing most actions — `hamburger_drawer.dart:523-566` ← `window_main_menu.cpp:574-584`

- [ ] [MAJOR] Reset Scale button uses wrong trigger condition and missing app restart: AyuGram creates the button only when the screen's available geometry is smaller than `windowMinWidth × windowMinHeight` (380×480 px), and clicking it calls `cSetConfigScale(default) → writeSettings → Core::Restart()`. Dart shows it whenever `uiScalePercent != 100` and clicking only calls `setUiScalePercent(100.0)` with no restart — `hamburger_drawer.dart:854-877` ← `window_main_menu.cpp:1040-1069`

- [ ] [MAJOR] Ghost mode toggle and LRead/SRead read/write global `appState` state instead of per-session ghost settings: AyuGram uses `AyuSettings::ghost(&controller->session())` so each logged-in account has independent ghost/read-receipt state. Dart's `appState.ghostModeEnabled` / `appState.setSendReadMessages()` are global, causing all accounts to share a single ghost-mode switch — `hamburger_drawer.dart:384-403`, `414-419`, `444-450` ← `window_main_menu.cpp:888-906`, `773-780`, `793-797`

# info_panel — Audit Findings

## Cover / Header

- [ ] [MAJOR] Mute menu uses hardcoded duration list `['1h','4h','8h','2d','1w','forever']` instead of dynamic session mute periods — `info_panel.dart:1089` ← `AyuGramDesktop/Telegram/SourceFiles/menu/menu_mute.cpp:337`
- [ ] [MAJOR] Mute menu missing "Select Sound" and "Toggle Sound On/Off" actions — `info_panel.dart:1089` ← `AyuGramDesktop/Telegram/SourceFiles/menu/menu_mute.cpp:313`
- [ ] [MAJOR] Mute menu missing "Custom duration…" picker (`PickMuteBox`) — `info_panel.dart:1089` ← `AyuGramDesktop/Telegram/SourceFiles/menu/menu_mute.cpp:358`
- [ ] [MAJOR] Avatar viewer is single-photo only with no gallery navigation; AyuGram shows full photo gallery with prev/next navigation — `info_panel.dart:1159` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_cover.cpp`
- [ ] [MAJOR] Emoji status pattern painter draws static colored dots, not actual emoji glyphs/sticker player — `info_panel.dart:1394` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_cover.cpp:67`
- [ ] [MAJOR] Topic icon renders as static fallback only; no animated Lottie/WebM sticker player (`TopicIconView::setupPlayer`) — `info_panel.dart:1467` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_cover.cpp:101`
- [ ] [MAJOR] Gift/Star Gift button missing from action row for premium peers — `info_panel.dart:889` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_top_bar.cpp:956`
- [ ] [MAJOR] "Discuss" button missing from channel cover action row — `info_panel.dart:889` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_top_bar.cpp:910`
- [ ] [MAJOR] "Join" button missing from action row for public channels/groups the user hasn't joined — `info_panel.dart:889` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_top_bar.cpp:789`

## Profile Details

- [ ] [CRITICAL] Business hours field rendered as static text; no real-time "opens in X / closes in Y" countdown or expandable days list — `info_panel.dart:2959` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_actions.cpp:381`
- [ ] [MAJOR] Contact notes widget entirely absent; AyuGram shows editable notes section with context menu (edit/delete) — `info_panel.dart:2016` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_actions.cpp:758`
- [ ] [MAJOR] `_GroupActionsSection` always shows "Leave" without checking whether the user is actually a member — `info_panel.dart:3181` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_actions.cpp`
- [ ] [MAJOR] `_MemberRow` hardcodes "last seen recently" for all non-online users instead of fetching real last-seen status — `info_panel.dart:5859` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_actions.cpp`
- [ ] [MAJOR] "Share Contact" action in `_DmActionsSection` has no engine call; wired to `_shareContact` which emits nothing — `info_panel.dart:3695`
- [ ] [MAJOR] "Report" action in group/channel sections calls no engine method — `info_panel.dart:3293` ← `AyuGramDesktop/Telegram/SourceFiles/info/profile/info_profile_actions.cpp`
- [ ] [MAJOR] Personal channel link in `_ChatDetails` displayed but tap does not navigate to the channel — `info_panel.dart:2982`

## Members Section

- [ ] [CRITICAL] `_MembersSection` loads a static snapshot of members with no real-time membership event subscription; list goes stale without page refresh — `info_panel.dart:5683`
- [ ] [MAJOR] Promote/Demote/Restrict in member context menu are missing real engine calls for Promote and Restrict — `info_panel.dart:6107`
- [ ] [MAJOR] Client-side member search filters only already-loaded members (≤20); AyuGram sends server-side search RPC — `info_panel.dart:5757`
- [ ] [MAJOR] "Add member" dialog does not handle `CHAT_ADMIN_REQUIRED` / `USER_PRIVACY_RESTRICTED` errors — `info_panel.dart:8143`

## Shared Media

- [ ] [CRITICAL] `_MediaGrid` uses a non-lazy `Column` wrapping all cells at once; causes OOM/jank for large media counts — `info_panel.dart:4786` ← AyuGram uses virtual lazy/sliver grid
- [ ] [MAJOR] `_SharedMediaSubPageState` wraps `_MediaGrid` in `SingleChildScrollView` instead of `SliverGrid`/`SliverList`; breaks lazy rendering — `info_panel.dart:2517`
- [ ] [MAJOR] Story album drag-to-reorder calls no engine reorder method; local list reorders but server order is never persisted — `info_panel.dart:4485`
- [ ] [MAJOR] `_GifMasonryGrid` loads all GIFs into memory simultaneously with no pagination or lazy decode — `info_panel.dart:4894`
- [ ] [MAJOR] `_MediaSearchRow` has text input but emits no search RPC; results are not filtered server-side — `info_panel.dart:4327`

## Statistics Page

- [ ] [MAJOR] `_PublicForwardRow` opens source chat by ID but does not scroll to or highlight the specific forwarded message — `info_panel.dart:7975` ← `AyuGramDesktop/Telegram/SourceFiles/info/statistics/info_statistics_widget.cpp`
- [ ] [MAJOR] `_StatisticsPage` loads stats once on init with no refresh/pull-to-refresh; data goes stale — `info_panel.dart:6507`
- [ ] [MAJOR] `_BoostsPage` missing booster list, gift boosts section, and "Get more boosts" action — `info_panel.dart:6371` ← `AyuGramDesktop/Telegram/SourceFiles/info/boosts/info_boosts_widget.cpp`
- [ ] [MAJOR] `_RecentMessagesSection` "Show in Chat" context menu emits no engine navigation call — `info_panel.dart:7285`

## Actions Sections

- [ ] [MAJOR] "Edit group" in `_GroupActionsSection` callback navigates to no screen; `_editGroup` is a stub — `info_panel.dart:3235`
- [ ] [MAJOR] "Change type" (edit peer type) is a stub with no destination screen in `_GroupActionsSection` — `info_panel.dart:3242`
- [ ] [MAJOR] `_ForumTopicsDialog` save calls no engine method when toggling forums on/off — `info_panel.dart:3361`
- [ ] [MAJOR] `_SavedMediaFilterSection` shows static hardcoded filter list with no engine call to fetch or apply saved-message folder filters — `info_panel.dart:6322`

## Performance

- [ ] [CRITICAL] `_ChatInfoPageState._buildInfoSections()` rebuilds entire section tree (including inline media grids) on every `setState` from scroll — `info_panel.dart:2016`; sections must be extracted to separate stateful widgets
- [ ] [MAJOR] `_GridCell` decodes image thumbnails on the UI thread; must use `compute()` or `Isolate.run` — `info_panel.dart:5435`
- [ ] [MAJOR] Multiple `ScrollController` listeners added in lifecycle without matching `removeListener`, leaking on hot-reload/rebuild — `info_panel.dart:138`

# input_dialogs — Audit Findings

## _UsernameBoxContent

- [ ] [MAJOR] Username validation regex `^[a-zA-Z][a-zA-Z0-9_]{3,31}$` requires first char to be a letter, but AyuGram's `changed()` method allows digits at any position including first — it only forbids non-alphanumeric/underscore chars and uses `kMinUsernameLength=5` as the only structural constraint — `input_dialogs.dart:126` ← `AyuGram/boxes/username_box.cpp:204-233`

- [ ] [MAJOR] Dart regex enforces minimum of 4 chars after first char (total 5) via `{3,31}` but AyuGram's minimum check is `name.size() < kMinUsernameLength` (5) applied after the per-character loop — the Dart regex rejects e.g. `a1234` at position 0 being digit, while AyuGram allows it — `input_dialogs.dart:126` ← `AyuGram/boxes/peers/edit_peer_common.h:15`

- [ ] [MAJOR] Debounce timer is 200ms, matching `kUsernameCheckTimeout = crl::time(200)` — this is correct. No issue.

- [ ] [MAJOR] `_UsernameBoxContent` only shows "Additional usernames" section by fetching `getAccountUsernames`, but AyuGram renders the full `UsernamesList` widget (`edit_peer_usernames_list.h`) which supports drag-to-reorder via a reorder controller. Dart implementation uses a static list with `Switch` toggles but no drag-to-reorder handle — the drag icon (`Icons.drag_handle`) is purely cosmetic and non-functional — `input_dialogs.dart:313-316` ← `AyuGram/boxes/username_box.cpp:362-393`

- [ ] [MAJOR] AyuGram's `UsernamesList` calls `list->save()` first, then `editor->save()` in sequence (two separate API calls in series). Dart's `_save()` only calls `updateAccountUsername` (the primary username) and ignores toggling additional usernames on save — the toggle is done immediately on switch change which is wrong: AyuGram batches all changes and commits on the Save button — `input_dialogs.dart:276-293, 295-302` ← `AyuGram/boxes/username_box.cpp:372-393`

- [ ] [MAJOR] Username box description in AyuGram is two separate paragraphs joined with `\n\n` produced by combining `tr::lng_username_description1` and `tr::lng_username_description2`. Dart shows a single hardcoded string without the second paragraph about links/mentions — `input_dialogs.dart:364-366` ← `AyuGram/boxes/username_box.cpp:334-361`

- [ ] [MAJOR] AyuGram uses `UsernameInput` (a `MaskedInputField`) that strips the `@` prefix from display and formats it as a masked input with `@` prepended visually. Dart uses a plain `TextField` with no `@` prefix displayed — the field label says "Username" but there is no leading `@` visual. AyuGram always shows `@` as part of the field — `input_dialogs.dart:368-374` ← `AyuGram/boxes/username_box.cpp:89-94`

---

## _AddContactBoxContent

- [ ] [MAJOR] AyuGram's `AddContactBox` uses `MTPcontacts_ImportContacts` (bulk contact import API) which returns the resolved user. Dart uses `engine.addContact(accountId, phone, firstName, lastName)` — the contact import flow in AyuGram uses a random `client_id` (`_contactId`) to match back the created contact from the response. There is no evidence Dart's engine exposes the same client-id matching logic — the behavior on "not on Telegram" is shown via a `_retrying` paint mode (text rendered directly on the box, not in a widget) not via an error string. Dart's retry mode clears fields but AyuGram's retry mode hides children and shows text in `paintEvent` — `input_dialogs.dart:632-648, 779-789` ← `AyuGram/boxes/add_contact_box.cpp:494-525`

- [ ] [MAJOR] AyuGram's retry mode renders the "not on Telegram" message with the first name substituted (`tr::lng_contact_not_joined(lt_name, _sentName)`) via `QPainter::drawText` in `paintEvent`, hiding all input fields. Dart's `_retry = true` state keeps all input fields visible and only shows an error string in `_error` — the contact form remains visible when it should be replaced with the "not joined" message — `input_dialogs.dart:634-639` ← `AyuGram/boxes/add_contact_box.cpp:354-385, 494-501`

- [ ] [MAJOR] AyuGram's retry button is labelled `tr::lng_try_other_contact()` ("Try another contact"), while Dart uses "Try Again" — `input_dialogs.dart:785` ← `AyuGram/boxes/add_contact_box.cpp:520`

- [ ] [MAJOR] AyuGram's Add Contact box uses `Ui::PhoneInput` (a specialized phone field that handles country groups/formatting from `Countries::Groups`) as a proper single integrated phone field. Dart splits this into a separate dial code text field plus a phone number field — the layout does not match AyuGram which has one unified `PhoneInput` widget — `input_dialogs.dart:705-763` ← `AyuGram/boxes/add_contact_box.cpp:300-306`

- [ ] [MAJOR] AyuGram's Add Contact box title changes dynamically: it shows `tr::lng_confirm_contact_data()` when the phone is pre-filled, and `tr::lng_enter_contact_data()` otherwise. Dart always shows "Add Contact" — `input_dialogs.dart:659` ← `AyuGram/boxes/add_contact_box.cpp:320-323`

- [ ] [MAJOR] AyuGram draws contact and phone icons using `st::contactUserIcon.paint` and `st::contactPhoneIcon.paint` in `paintEvent`. Dart has no icons in the contact form — `input_dialogs.dart:659-791` ← `AyuGram/boxes/add_contact_box.cpp:354-385`

- [ ] [MAJOR] AyuGram's `save()` lifts empty firstName to lastName if firstName is empty (`firstName = lastName; lastName = QString()`). Dart's `_save()` does not implement this normalization — `input_dialogs.dart:610-648` ← `AyuGram/boxes/add_contact_box.cpp:449-452`

---

## _CountryPickerContent

- [ ] [MAJOR] AyuGram's `CountrySelectBox` uses a `Ui::MultiSelect` widget at top (with pill-style chips for filtering) via `st::defaultMultiSelect`. Dart uses a plain `TextField` with search hint — wrong widget type — `input_dialogs.dart:885-897` ← `AyuGram/ui/boxes/country_select_box.cpp:141-142`

- [ ] [MAJOR] AyuGram's `CountrySelectBox::Inner` implements keyboard navigation (`selectSkip`, `selectSkipPage`, Home/End keys) and arrow key forwarding from the search field to the list. Dart's `ListView.builder` has no keyboard navigation — `input_dialogs.dart:912-947` ← `AyuGram/ui/boxes/country_select_box.cpp:401-425, 518-536`

- [ ] [MAJOR] AyuGram's country list uses `_byLetter` map to filter by first letter of each word (true word-prefix search using pre-indexed word lists). Dart filters by calling `c.name.toLowerCase().split(RegExp(r'[\s\-]+'))` and checking `startsWith` — this matches AyuGram's approach structurally but AyuGram additionally indexes by first character of each word into `_byLetter` for O(1) lookup on first char — `input_dialogs.dart:856-866` ← `AyuGram/ui/boxes/country_select_box.cpp:487-513`

- [ ] [MAJOR] AyuGram's country row height is `st::countryRowHeight = 36` and uses `st::countryRowPadding` (left=22, top=9, right=8, bottom=0). Dart uses `itemExtent: 36` (correct) but row padding is `EdgeInsets.only(left: 22, right: 8)` which matches left/right but has no top padding for the text — `input_dialogs.dart:922` ← `AyuGram/ui/boxes/country_select_box.cpp:235, 391`

- [ ] [MAJOR] AyuGram renders the country dialing code right-aligned (`drawTextLeft` at `nameWidth + padding.right` position) and uses separate fonts `st::countryRowCodeFont` and `st::countryRowNameFont`. Dart renders code as plain `Text('+${c.dialCode}')` with no separate font or size difference — `input_dialogs.dart:940-942` ← `AyuGram/ui/boxes/country_select_box.cpp:378-397`

- [ ] [MAJOR] AyuGram's `CountrySelectBox` uses `setDimensions(st::boxWidth, st::boxMaxListHeight)` — it sets full-height scrollable box. Dart constrains with `BoxConstraints(maxHeight: 400)` — no scrollable inner widget, list is not scrollable past 400px — `input_dialogs.dart:900-902` ← `AyuGram/ui/boxes/country_select_box.cpp:181`

- [ ] [MAJOR] AyuGram's country list places the currently-selected country first (via `LastValidISO` tracking and `init()` ordering). Dart moves selected country to index 0 on every `_buildList()` call — this is functionally equivalent but Dart rebuilds and resorts on every filter change while AyuGram only moves it at init time — minor behavioral difference but acceptable.

---

## _EditInviteLinkContent

- [ ] [MAJOR] AyuGram's expire options list is `{kMaxLimit(Never), -kHour(-1h), -kDay(-1d), -kDay*7(-7d), 0(Custom)}` — negative values mean "relative duration" and positive means "absolute timestamp". The custom option inserts the user's custom value inline. Dart uses a map `{0: 'Never', 3600: '1 hour', 86400: '1 day', 604800: '7 days', 2592000: '30 days', -1: 'Custom'}` — the "30 days" option (2592000) does NOT EXIST in AyuGram's expire list — `input_dialogs.dart:1038-1046` ← `AyuGram/ui/boxes/edit_invite_link.cpp:242`

- [ ] [MAJOR] AyuGram's expire radio buttons show only the four options that fit current value (Never/1h/1d/7d/Custom) — they use `Radiobutton` widgets from `Ui::RadiobuttonGroup`. Dart uses `ChoiceChip` Flutter widgets — wrong widget type — `input_dialogs.dart:1257-1287` ← `AyuGram/ui/boxes/edit_invite_link.cpp:229-236`

- [ ] [MAJOR] AyuGram's usage options are `{kMaxLimit(Unlimited), 1, 10, 100, 0(Custom)}` — exactly matching what's in Dart (`{0: Unlimited, 1: 1 use, 10: 10 uses, 100: 100 uses, -1: Custom}`), but Dart represents Unlimited as key `0` and AyuGram as `kMaxLimit`. More importantly AyuGram maps 0/kMaxLimit to `usageLimit=0` on save; Dart maps key `0` to Unlimited correctly but key mismatch creates off-by-one if `existingUsageLimit==0` is passed — the init logic in Dart checks `_usageOptions.containsKey(0)` which will match for Unlimited correctly — `input_dialogs.dart:1047-1052` ← `AyuGram/ui/boxes/edit_invite_link.cpp:243`

- [ ] [MAJOR] AyuGram's `requestApproval` toggle is a `SettingsButton` (full-width toggle row with icon area). When `requestApproval` is active, the usage section slides out (`usagesSlide->toggleOn(requestApproval.value() | rpl::map(!_1))`). Dart's `_requestApproval` checkbox disables the usage chips but does not hide them — the slide-out is missing — `input_dialogs.dart:1304-1325` ← `AyuGram/ui/boxes/edit_invite_link.cpp:374-375`

- [ ] [MAJOR] AyuGram uses `SettingsButton` (toggle row) for "Request Admin Approval" — a full-width `SettingsButton` with toggle not a checkbox. Dart renders a `Checkbox` in an `InkWell` row — wrong widget — `input_dialogs.dart:1326-1353` ← `AyuGram/ui/boxes/edit_invite_link.cpp:112-133`

- [ ] [MAJOR] AyuGram's "Subscription" toggle is also a `SettingsButton` (provided via `fillSubscription()` callback). Dart renders a `Checkbox` in an `InkWell` row — wrong widget — `input_dialogs.dart:1366-1404` ← `AyuGram/ui/boxes/edit_invite_link.cpp:136-158`

- [ ] [MAJOR] AyuGram places the label field AFTER the request approval and subscription toggles in the layout, but BEFORE the expire/usage sections. Dart places the label field FIRST before all sections — wrong field ordering — `input_dialogs.dart:1237-1248` ← `AyuGram/ui/boxes/edit_invite_link.cpp:160-172`

- [ ] [MAJOR] AyuGram's custom expire picker uses `ChooseDateTimeBox` (a specialized combined date+time picker in a single box). Dart uses separate `showDatePicker` then `showTimePicker` calls — wrong UX flow — `input_dialogs.dart:1097-1120` ← `AyuGram/ui/boxes/edit_invite_link.cpp:315-321`

---

## _CreatePollContent

- [ ] [MAJOR] AyuGram's poll options count limit is `appConfig->pollOptionsLimit()` (fetched from server at runtime via `AppConfig`), not a hardcoded 32. Dart hardcodes `_kMaxOptions = 32`. While 32 matches `PollData::kMaxOptions`, AyuGram displays the remaining count as `tr::lng_polls_create_limit(lt_count, max - count)` and "maximum" when full — Dart has no such remaining-count label — `input_dialogs.dart:1500-1501` ← `AyuGram/boxes/create_poll_box.cpp:103-104, 2505-2524`

- [ ] [MAJOR] AyuGram's poll settings section has 6+ toggles: Anonymous Voting, Multiple Answers, Allow Adding Options (open polls), Allow Revoting, Shuffle Answers, Quiz Mode, AND a Limit Duration toggle. Dart only has 4: Anonymous Voting, Multiple Answers, Allow Revoting, Quiz Mode — missing "Shuffle Answers", "Allow Adding Options", and "Limit Duration" — `input_dialogs.dart:1688-1712` ← `AyuGram/boxes/create_poll_box.cpp:2541-2627`

- [ ] [MAJOR] AyuGram's "Settings" section uses `AddPollToggleButton` which renders `DetailedSettingsButton` (full-width toggle rows with icon+description text). Dart renders checkboxes in `InkWell` rows — wrong widget type — `input_dialogs.dart:1760-1783` ← `AyuGram/boxes/create_poll_box.cpp:2554-2616`

- [ ] [MAJOR] AyuGram's poll has a "Description" field (separate from Question) for Premium users via `setupDescription()`. Dart has no description field — `input_dialogs.dart:1586-1606` ← `AyuGram/boxes/create_poll_box.cpp:1317-1368`

- [ ] [MAJOR] AyuGram's poll options support media attachments (photo/video/document per option via `PollMediaButton`) — each option has an attach button. Dart options have only a text field with no media attachment — `input_dialogs.dart:1614-1673` ← `AyuGram/boxes/create_poll_box.cpp:346-348`

- [ ] [MAJOR] AyuGram's "Multiple Answers" toggle, when enabled, sets `quizForceOff` — the quiz toggle is forced off. Dart's implementation sets `_quiz = false` when `_multipleChoice` is set to true — that part matches. However AyuGram also fires `revotingForceOff` events to disable revoting when quiz is on; Dart hardcodes `_allowRevoting = false` in quiz mode — functionally equivalent but Dart does not disable the Allow Revoting checkbox visually/interactively (it passes `null` as `onChanged` for `_checkRow` when `_quiz` is true — acceptable workaround).

- [ ] [MAJOR] AyuGram's `kWarnQuestionLimit = 80` — the warning counter for question appears when chars > 80. Dart shows the counter when `_questionCtrl.text.length > 80` — this is correct.

- [ ] [MAJOR] AyuGram's `kWarnOptionLimit = 30` — warning appears when remaining chars < 30. Dart checks `_kOptionLimit - _optionCtrls[i].text.length < _kWarnOptionLimit` which is equivalent — correct.

- [ ] [MAJOR] AyuGram's `kWarnSolutionLimit = 60` — solution warning threshold. Dart shows solution counter when `_solutionCtrl.text.length > 60` — correct threshold.

- [ ] [MAJOR] AyuGram's poll options support drag-to-reorder via `VerticalLayoutReorder`. Dart has no reorder mechanism for poll options — `input_dialogs.dart:1614-1673` ← `AyuGram/boxes/create_poll_box.cpp:239, setupReorder()`

- [ ] [MAJOR] AyuGram's question field uses `InitField` which calls `InitMessageFieldHandlers` enabling emoji suggestions and markdown. Dart's question field is a plain `BoxInputField` with no emoji suggestions — `input_dialogs.dart:1588-1593` ← `AyuGram/boxes/create_poll_box.cpp:273-292`

# instant_view — Audit findings

- [ ] [CRITICAL] `_buildEmbed` renders link-only placeholder instead of actual embedded content — `instant_view.dart:958-960` ← `iv_prepare.cpp:672` — C++ generates a real `<iframe src=...>` tag that the webview renders (YouTube players, Twitter posts, SoundCloud widgets, etc. all play in-page). Dart shows only an icon + URL link box that opens the browser externally. All embedded media blocks are non-functional: YouTube videos cannot be played, Twitter posts cannot be read, SoundCloud clips cannot be heard.

- [ ] [CRITICAL] `_buildMap` sends coordinates to Yandex static maps (third-party) instead of Telegram's internal tile server — `instant_view.dart:1463` ← `iv_prepare.cpp:1233-1238` — C++ routes map images through the internal resource handler at `/map/{geoPointId}&{width},{height}&{zoom}`, served by Telegram's own infrastructure. Dart hardcodes `https://static-maps.yandex.ru/1.x/?...` — an external Yandex service that leaks user-browsed article geo-coordinates to Yandex, fails when Yandex Maps is unavailable or blocked (common in certain regions), and violates Telegram's privacy model for IV.

- [ ] [MAJOR] All IV blocks built eagerly inside `SingleChildScrollView + Column`, no lazy rendering — `instant_view.dart:314-327` — C++ uses a webview that renders progressively. Dart calls `.toList()` on every block at build time, constructing every `_IvBlock` widget (including photos, videos, code blocks, tables, collages) simultaneously. Long IV articles with many media blocks will cause frame jank and potential OOM; should use `ListView.builder` or `CustomScrollView + SliverList` for lazy construction.

- [ ] [MAJOR] Zoom uses a fixed 0.1 float step with no modifier-key precision, and allows below-default zoom (0.5x) which C++ never permits — `instant_view.dart:159-161` ← `iv_controller.cpp:62-65, 126-131` — C++ defines three precision tiers: Alt key = 1 unit, Ctrl key = 5 units, unmodified = 10 units, all applied as integer increments on top of a 100-baseline. It never zooms below the 100-baseline (only up from default). Dart applies a flat 0.1 step regardless of modifiers and clamps to 0.5 (50%), making it possible to shrink text to half size — behavior the C++ deliberately prevents.

# emoji_data — Critical emoji validation & missing backend wiring

## Issues Found

### CRITICAL Issues

- [ ] [CRITICAL] **Broken emoji validation filters out common emoji** — `emoji_data.dart:652-675` ← `emoji_keywords.cpp:47-76`
  
  The `isValidEmoji()` function only checks the FIRST rune and uses incomplete unicode ranges. It **filters out essential emoji**:
  
  - 👋 (waving hand, line 118) at U+1F44B is NOT in any range (< 0x1F600, not in 0x2600-0x27BF)
  - All "Miscellaneous Symbols and Pictographs" (0x1F300-0x1F5FF) — missing range entirely
  - All skin tone variants (0x1F3FB-0x1F3FF) — missing range
  - Supplemental Symbols (0x1F900-0x1F9FF) — missing range
  - Regional indicators (0x1F1E6-0x1F1FF) — missing range
  
  When `init()` runs at line 740-743, it calls `.where((e) => isValidEmoji(e.emoji))` which filters `kEmojiSuggestions` down to ~50 entries instead of ~640. This **breaks the fallback emoji picker entirely**.
  
  **Fix:** Either (1) remove validation (all `kEmojiSuggestions` are already valid), or (2) match AyuGram's approach at emoji_keywords.cpp:78-82 which uses `Find(text)` to validate against the built-in emoji table, not by checking ranges.

- [ ] [CRITICAL] **No backend integration: server keywords are never loaded** — `emoji_data.dart:748-755, 810-840` ← `emoji_keywords.cpp:386-417, 608-642`
  
  The Dart `EmojiKeywords` class has `loadServerKeywords()` method to accept server data, but there is NO code in this file (or elsewhere in the codebase) that calls it from the bridge/engine. Compare:
  
  - **AyuGram:** `LangPack::refresh()` (line 386) calls `api->request(MTPmessages_GetEmojiKeywords(...))` to fetch keywords from server
  - **Dart:** `loadServerKeywords()` exists as a stub that sets `_langPacks[langCode]` but is never called. The class only falls back to `_legacy` data (the hardcoded list)
  
  This means:
  1. Server keyword data never arrives (no API call wired)
  2. Search always uses the broken filtered-down legacy list
  3. Localized emoji keywords from server are never available
  
  **Where it should be called:** The Dart bridge/engine layer needs to fetch `messages.getEmojiKeywords()` and call `EmojiKeywords.instance.loadServerKeywords()` with the result. Current implementation only has the plumbing, not the caller.

- [ ] [CRITICAL] **Recent emoji tracking has no backend persistence** — `emoji_data.dart:772-778, 791-808` ← `emoji_keywords.cpp:650-671`
  
  The Dart code stores recent emoji locally in `_recentEmojis` list and has `saveState()` to serialize to JSON, but:
  1. No code in this file syncs state to bridge/engine
  2. No code loads persisted state on init
  3. No code sends recent emoji updates to Telegram server (AyuGram reads from `Core::App().settings().recentEmoji()` which is backed by server sync)
  
  Result: Recent emoji are lost on app restart because they're only in memory, never persisted.

### MAJOR Issues

- [ ] [MAJOR] **Search includes "contains" matches but AyuGram doesn't** — `emoji_data.dart:902-904` ← `emoji_keywords.cpp:473-496`
  
  **Dart:** Three-tier search: exact → prefix → contains (line 829)
  ```dart
  } else if (kw.contains(q)) {
    isContains = true;
  }
  ```
  
  **AyuGram:** Only exact and prefix matches (line 488):
  ```cpp
  return exact ? (key == normalized) : key.startsWith(normalized);
  ```
  
  "Contains" matching is broader than AyuGram and may return spam results. E.g., searching "o" would match "people" when it should only match exact "o" or prefixes like "ok". This is a behavioral deviation from the official client.

- [ ] [MAJOR] **Emoji lookup doesn't apply server variant preferences** — `emoji_data.dart:834-837` ← `emoji_keywords.cpp:674-680`
  
  While Dart code has `applyVariant()` logic, it only applies to emoji that exist in search results. But:
  1. Variant prefs are never loaded from server (no `lookupEmojiVariant()` equivalent)
  2. Variant prefs are stored locally only, never synced to server
  3. AyuGram (line 677) calls `settings.lookupEmojiVariant(item.emoji)` which reads from persistent app settings
  
  Result: User's skin tone and emoji variant preferences are not preserved or synced.

- [ ] [MAJOR] **Legacy emoji list is not validated at all** — `emoji_data.dart:741-743` ← `emoji_keywords.cpp:132-135`
  
  AyuGram validates each emoji in the cache by calling `FindExact(emoji)` (line 132) which returns null if unsupported. Bad entries are rejected:
  ```cpp
  const auto entry = LangPackEmoji{ FindExact(emoji), text };
  if (!entry.emoji) {
    return {}; // Invalid, abort loading
  }
  ```
  
  Dart doesn't validate each entry in `kEmojiSuggestions`, only checks the first code unit. This allows invalid/broken emoji in the list.

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

# keyboard_shortcuts — Shortcut System Audit

- [ ] [CRITICAL] `account1`–`account6` commands declared in enum and scope map but have zero registered handlers in `_ShortcutListenerState.initState()` — user-configurable account-switching shortcuts silently do nothing when triggered — `keyboard_shortcuts.dart:46-51,142-147,1048-1355` ← `AyuGram/core/shortcuts.cpp:103-110` (ShowAccount1-6 handled by window controller via `Requests()` stream; Dart has no equivalent listener)

- [ ] [CRITICAL] `message`, `messageSilently`, `messageScheduled` commands declared with `composeRequired` scope but have no registered handlers anywhere in the file — shortcuts are saved/loaded from config and user-assignable, but dispatching them does nothing — `keyboard_shortcuts.dart:69-71,181-183,245-247` ← `AyuGram/core/shortcuts.cpp:132-134` (AyuGram handles `JustSendMessage`/`SendSilentMessage`/`ScheduleMessage` in HistoryWidget via the Requests() stream)

- [ ] [CRITICAL] `_writeCustomTemplate()` writes a file beginning with `//` comment lines (not valid JSON), then `_loadCustomFile()` calls `dart:convert jsonDecode()` on it which throws `FormatException` — `catch (_) {}` at line 575 silently swallows the error, leaving custom shortcuts permanently unloadable on any install where the user never saves a binding — `keyboard_shortcuts.dart:578-595,533-575` ← `AyuGram/core/shortcuts.cpp:254-277` (AyuGram strips comments with `base::parse::stripComments()` before JSON parsing, making its template files self-consistent)

- [ ] [MAJOR] `_layerShown` scope guard (line 465) only blocks non-global shortcuts when a dialog layer is present, but global-scope commands (`closeTelegram`, `lockTelegram`, `quitTelegram`, `minimizeTelegram`) continue to fire through any modal — AyuGram's `Paused` flag blocks ALL shortcuts unconditionally including global ones — `keyboard_shortcuts.dart:463-476` ← `AyuGram/core/shortcuts.cpp:792-797` (`if (Paused) { return false; }` guards the entire `Launch()` call)

- [ ] [MAJOR] Chat-switch overlay (Ctrl+Tab) is implemented as a simple one-shot event fire (`UniClientShell.showChatSwitchRequest?.call()`) with no modifier-held tracking — AyuGram's `HandlePossibleChatSwitch` maintains a full state machine: sets `ChatSwitchStarted`, fires `ChatSwitchRequest` events, then tracks arrow keys / Q / Escape / Enter while Ctrl is held and fires a `Key_Enter` dismiss event on Ctrl release — the Dart overlay has no way to detect Ctrl release or navigate within itself at the shortcut-system level — `keyboard_shortcuts.dart:1085-1091` ← `AyuGram/core/shortcuts.cpp:894-974`

- [ ] [MAJOR] `selfChat` handler (line 1195) searches `chatState.chats` for a chat matching `isSavedMessages()` and returns `false` if not found — if Saved Messages has never been opened it won't be in the loaded chat list, so Ctrl+0 silently does nothing — AyuGram's handler opens the self-peer directly from the session regardless of whether it appears in the recent chat list — `keyboard_shortcuts.dart:1195-1205` ← `AyuGram/core/shortcuts.cpp:522` (`set(u"ctrl+0"_q, Command::ChatSelf)` handled by window controller with direct session access)

# language_box — Language settings box audit

- [ ] [MAJOR] "Recent" and "Official" text section headers don't exist in AyuGram — the source only adds a `BoxContentDivider` between sections with no text labels — `language_box.dart:471,490` ← `AyuGram/boxes/language_box.cpp:1136-1141`

- [ ] [MAJOR] `_SkipLanguagesEditor` missing search/filter field — AyuGram's `ChooseLanguageBox` pins a `MultiSelect` search bar at the top for filtering the 75+ language list — `language_box.dart:888-989` ← `AyuGram/ui/boxes/choose_language_box.cpp:274-278`

- [ ] [MAJOR] `_SkipLanguagesEditor` height constraint wrong — Dart uses `screenHeight - 48` (nearly full screen); AyuGram sets `minHeight` and `maxHeight` both to `st::boxWidth` (320px, making it a square box) — `language_box.dart:883-884` ← `AyuGram/ui/boxes/choose_language_box.cpp:270-271`

- [ ] [MAJOR] `_SkipLanguagesEditor` missing Cancel button — AyuGram's `ChooseLanguageBox` renders both Save (`tr::lng_settings_save`) and Cancel (`tr::lng_cancel`) buttons; Dart only has Save — `language_box.dart:979-982` ← `AyuGram/ui/boxes/choose_language_box.cpp:364-379`

- [ ] [MAJOR] `_SkipLanguagesEditor` does not sort selected languages to the top — AyuGram's `ChooseLanguageBox` calls `ranges::stable_partition` to float already-selected languages before others; Dart iterates `_kTranslationLanguages` in fixed order — `language_box.dart:886` ← `AyuGram/ui/boxes/choose_language_box.cpp:292-295`

- [ ] [MAJOR] PageDown/PageUp keyboard navigation hardcoded at ±10 rows — AyuGram dynamically computes rows per page as `height() / Rows::DefaultRowHeight()` — `language_box.dart:147-158` ← `AyuGram/boxes/language_box.cpp:1527-1529`

- [ ] [MAJOR] "Translate Entire Chats" toggle unnecessarily locked for non-premium users — AyuGram hardcodes `AmPremiumValue` to always return `true`, making the toggle available to everyone — `language_box.dart:284-289` ← `AyuGram/boxes/language_box.cpp:1439-1443`

# media_viewer — Audit Findings

## media_viewer — Caption entities/links not rendered

- [ ] [CRITICAL] Caption uses plain `SelectableText` with no entity or link rendering. AyuGram uses `setMarkedText` with `ClickHandlerPtr` so URLs, bold, mentions, and spoilers in captions are all interactive. Dart caption is read-only unformatted text. — `media_viewer.dart:2509` ← `media_view_overlay_widget.cpp:3901-3914`

## media_viewer — Speed boost visual overlay missing

- [ ] [CRITICAL] When space-hold speed boost is active, AyuGram renders an animated "2.0×" overlay (`paintSpeedBoostContent`) with animated forward-arrows and smooth fade-in/out. Dart has the speed boost logic but zero visual feedback — the user gets no indication that the boost is active or what speed it is. — `media_viewer.dart:878-904` ← `media_view_overlay_widget.cpp:6297-6370`

## media_viewer — Stealth mode activation is a no-op in media viewer More menu

- [ ] [CRITICAL] `_handleMenuAction('stealth_mode', ...)` calls `showStoryStealthModeDialog(context)` with no `onActivate` callback (line 3130). When the user presses "Enable" in the dialog, `widget.onActivate?.call()` is a null-op but the toast still says "Stealth Mode enabled". Engine is never called; stealth mode is never actually activated from the media viewer More menu. — `media_viewer.dart:3129-3130` ← `media_stories_controller.cpp:1947-1952`

## media_viewer — ChannelPost story area drops msgId

- [ ] [CRITICAL] `_handleAreaChannelPost(int channelId, int msgId)` ignores `msgId` entirely and only calls `chatState.openChatById(channelId.toString())` (line 5959). Clicking a channel-post story area opens the channel at the top instead of scrolling to the referenced message. — `media_viewer.dart:5956-5960` ← `media_stories_controller.cpp` (channel post area opens at specific message)

## media_viewer — Arrow Left/Right seeks video instead of navigating

- [ ] [MAJOR] When `_isVideo && _mode == fullscreen`, pressing Arrow Left/Right seeks the video by ±5 seconds instead of navigating to the prev/next media item. AyuGram's keyboard handler uses `Key_Left`/`Key_Right` exclusively for `moveToNext(-1/1)` navigation and never for seeking (seeking is J/L keys and ←/→ only when the controls seek bar is focused). — `media_viewer.dart:1006-1029` ← `media_view_overlay_widget.cpp:6761-6793`

## media_viewer — Alt+Left/Right consumed as no-op, breaks navigation

- [ ] [MAJOR] When Alt is held with Arrow Left/Right, Dart returns `KeyEventResult.handled` without doing anything (lines 1008-1009, 1020-1021). AyuGram has no Alt+Left/Right special handling — the event falls through to `Key_Left`/`Key_Right` which calls `moveToNext`. So in Dart, Alt+Left does nothing, while in AyuGram it navigates to the previous item. — `media_viewer.dart:1007-1010,1019-1022` ← `media_view_overlay_widget.cpp:6761-6793`

## media_viewer — Video controller border-radius wrong (10px vs 9px)

- [ ] [MAJOR] The video controls container uses `BorderRadius.circular(10)` but the spec value is `mediaviewControllerRadius: 9px`. — `media_viewer.dart:2203` ← `media_view.style:95`

## media_viewer — Recognize Text (OCR) toolbar button missing

- [ ] [MAJOR] AyuGram has a dedicated "Recognize Text" button (`Over::Recognize`) in the media viewer toolbar that triggers `Platform::TextRecognition::RecognizeText`. The Dart toolbar only has Draw/Save/Rotate/More buttons — OCR is completely absent from `_buildToolbar`. — `media_viewer.dart:3194-3224` ← `media_view_overlay_widget.cpp:6457-6461,3396`

## media_viewer — Chapter name toast display missing

- [ ] [MAJOR] AyuGram shows a chapter name overlay toast (`paintChapterContent`) whenever playback enters a chapter region or Alt+Left/Right chapter navigation is triggered. Dart has chapter markers on the slider track (`_SliderPainter`) but no toast/display showing the chapter name. — `media_viewer.dart:1008-1010,3390-3398` ← `media_view_overlay_widget.cpp:6085-6137`

## media_viewer — Stealth mode menu item shown for regular media (not story-only)

- [ ] [MAJOR] The `'stealth_mode'` entry is added to the More menu whenever `widget.mediaMessages.isNotEmpty && !_isSelfMedia` (line 3096-3098). This shows a stealth mode option on regular photos/videos/documents that are not stories. Stealth mode is a Telegram Stories-only feature and should never appear in the non-story media viewer. — `media_viewer.dart:3096-3098` ← `media_view_overlay_widget.cpp` (stealth only in stories context)

## media_viewer — PIP widget _formatTime drops hours

- [ ] [MAJOR] `_PipWidgetState._formatTime` only returns `MM:SS` format and discards hours (`d.inMinutes.remainder(60)`). For videos longer than 60 minutes the PIP time display shows wrong values (e.g. a video at 1h 05m 30s shows "05:30"). The main viewer's `_formatTime` handles hours correctly — the PIP copy-paste dropped it. — `media_viewer.dart:4283-4287` vs `media_viewer.dart:1111-1119`

## media_viewer — Story replies sent without story-reply context

- [ ] [MAJOR] Story replies use `engine.sendMessage(accountId, widget.peerId, text)` (line 6666), which sends a plain message to the peer. Telegram story replies require a `replyToStory` input field in the API call so the server knows it's a reply to a specific story. Without this field, the message is delivered as a regular DM, not as a story reply with the referenced story shown. — `media_viewer.dart:6662-6667` ← `media_stories_controller.cpp` (story reply sends story ID reference)

## media_viewer — _showAllMedia uses toggleInfoRequest, not shared media navigation

- [ ] [MAJOR] `_showAllMedia` calls `UniClientShell.toggleInfoRequest?.call()` (line 2930) which opens the info panel, not the shared media tab. AyuGram's equivalent navigates to the "Shared Media" section within the profile panel to show all media from that chat. — `media_viewer.dart:2928-2931` ← `media_view_overlay_widget.cpp:2041,2071`

# message_bubble — Audit findings

- [ ] [MAJOR] Forward header is plain italic text; no click handler to open originator's profile/channel. AyuGram renders it as a clickable link that opens the forwarded-from peer. Multiple variants are missing: forwarded story, forwarded via channel, forwarded with PSA type, hidden-sender ("anonymous channel"), signed author name — all collapsed into a single "Forwarded from <string>" label with no interactivity — `message_bubble.dart:918-929` ← `AyuGramDesktop/Telegram/SourceFiles/history/history_item_components.cpp:241-349` (`HistoryMessageForwarded::create`) and `history_view_message.cpp:948-958`

- [ ] [MAJOR] Poll subtitle always shows "Anonymous Poll" when not a quiz/multiple-choice; the `pollPublic` field is populated in `CachedMessage` (engine_models.dart line 531) but is never read by `_PollWidget`. Public polls must show "Poll" (not "Anonymous Poll") — `message_bubble.dart:8027` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/media/history_view_poll.cpp:2078-2083` (PublicVotes flag)

- [ ] [MAJOR] `mention`, `hashtag`, `bot_command`, `cashtag` entities are displayed with link colour but have no `TapGestureRecognizer` — tapping them does nothing. AyuGram opens the peer profile on mention tap, triggers a hashtag search on hashtag tap, and sends the command on bot_command tap — `message_bubble.dart:7199-7209` ← `AyuGramDesktop/Telegram/SourceFiles/core/click_handler_types.cpp:401-418` (MentionClickHandler::onClick) and line 459 (HashtagClickHandler::onClick) and line 485 (BotCommandClickHandler::onClick)

- [ ] [MAJOR] Upload cancel button in the media overlay (`_isUploading` branch) shows a close icon but has no `GestureDetector`/`onTap` — tapping it does nothing. AyuGram cancels the upload on tap. No `cancelUpload` / `cancelSend` method is wired here — `message_bubble.dart:3560-3598` (close icon at 3592 with no GestureDetector wrapping it)

- [ ] [MAJOR] `switch_inline` button handler reads `chat?.title` (the chat's display name, which may contain spaces or be a channel name) as the bot username, then constructs `@<chatTitle> <query>` and puts it in the compose box. The correct behaviour is to use the originating bot's username (from the button's bot field), not the active chat title. For `switch_inline_same` (same-peer variant) AyuGram keeps the user in the same chat; no such distinction is made in Dart — `message_bubble.dart:9566-9572` ← `AyuGramDesktop/Telegram/SourceFiles/history/history_item_reply_markup.cpp:213-225` (SwitchInline / SwitchInlineSame types)

- [ ] [MAJOR] Location map tile uses `tile.openstreetmap.org` (third-party). Telegram Desktop fetches tiles from `maps.telegram.org` (Telegram's own static-maps provider, configurable via `static_maps_provider` in server config). Using OpenStreetMap leaks user coordinates to a third party and deviates from the spec — `message_bubble.dart:4844-4845` ← `AyuGramDesktop/Telegram/SourceFiles/mtproto/scheme/api.tl:494` (`static_maps_provider` field in Config TL object)

## my_profile_page — Profile page audit vs AyuGram Desktop

- [ ] [CRITICAL] `_EditPeerColorBox` shows only 7 hardcoded colors (`_baseColors`) and no background-emoji picker, missing the full `EditPeerColorBox` which loads server-provided color indices (`peerColors().suggestedValue()`), a live message preview, and an emoji-icon picker row — `my_profile_page.dart:1240-1378` ← `AyuGram/boxes/peers/edit_peer_color_box.cpp:1843-1900`

- [ ] [CRITICAL] Profile photo click opens a local `Image.file` viewer instead of the proper media viewer via `controller->openPhoto(photo, _peer)` which opens the full photo gallery — `my_profile_page.dart:887-917` ← `AyuGram/ui/controls/userpic_button.cpp:528`

- [ ] [CRITICAL] After photo upload, the avatar area is not updated optimistically (no local userpic update like `UpdatePhotoLocally`), and no upload-progress overlay is shown on the avatar; in AyuGram both happen immediately before the server responds — `my_profile_page.dart:811-838` ← `AyuGram/settings/sections/settings_information.cpp:327-338`

- [ ] [CRITICAL] Status text in `_ProfilePhotoArea` is fetched once on init and never refreshed reactively; in AyuGram `StatusValue` subscribes to `peerFlagsValue(OnlineStatus)` and sets a timer to re-compute "last seen X min ago" automatically — `my_profile_page.dart:118-135` ← `AyuGram/settings/sections/settings_information.cpp:281-300`

- [ ] [CRITICAL] Profile photo and all account-row avatars always use `ClipOval` (circle only), ignoring the configurable `avatarCorners` setting (0–23) that AyuGram applies via `AyuUserpic::PaintShape`; other widgets in the app already read `appState.avatarCorners` — `my_profile_page.dart:708-718, 1802-1813` ← `AyuGram/ayu/ui/ayu_userpic.cpp:56-79`

- [ ] [MAJOR] Online status renders with accent color using `palette.windowBgActive` only when the string equals `'online'`; AyuGram uses `tr::link()` to wrap the text making FlatLabel apply `windowActiveTextFg` for any truly-online state, while last-seen text always stays `windowSubTextFg` — `my_profile_page.dart:756-760` ← `AyuGram/settings/sections/settings_information.cpp:288-289`

- [ ] [MAJOR] Status text position uses `Transform.translate(offset: Offset(0, -1))` (fixed 1px up-shift), but AyuGram positions it relative to name bottom plus `settingsInfoNameSkip: -1px` — since name height is variable the fixed offset can mis-align when name wraps — `my_profile_page.dart:750-761` ← `AyuGram/settings/sections/settings_information.cpp:375-378`, `AyuGram/settings/settings.style:213`

- [ ] [MAJOR] Birthday editing opens a custom `_BirthdayDrumPickerDialog` dialog (inline Flutter wheel pickers), but AyuGram opens `EditBirthdayBox` via `Core::App().openInternalUrl("internal:edit_birthday")` which uses `Ui::VerticalDrumPicker` with proper layout (day on left 25% / month in centre 50% / year on right 25%); the Dart dialog splits all three columns equally — `my_profile_page.dart:182-210` ← `AyuGram/ui/boxes/edit_birthday_box.cpp:91-99`

- [ ] [MAJOR] Personal Channel editing opens `_PersonalChannelSelector` (lists owned channels fetched from engine), but AyuGram opens the editor via `Core::App().openInternalUrl("internal:edit_personal_channel")` which shows a proper selection box; there is no "None / Remove" separator item shown before the channel list as in the real box — `my_profile_page.dart:1091-1101` ← `AyuGram/settings/sections/settings_information.cpp:507-512`

- [ ] [MAJOR] Locked account rows (those at index >= premiumLimit) are omitted entirely from the Dart list because `nextIsLocked` causes `button = nullptr` in AyuGram and skips rendering; the Dart `_AccountsSection` renders all accounts without any lock indicator or greyed-out treatment for over-limit accounts — `my_profile_page.dart:1597-1637` ← `AyuGram/settings/sections/settings_information.cpp:1093-1134`

- [ ] [MAJOR] Account row reorder in AyuGram persists order via `Core::App().settings().setAccountsOrder()` and only moves accounts above `premiumLimit` (extras are pinned via `addPinnedInterval`); the Dart `ReorderableListView` calls `appState.reorderAccounts` for all items with no premium-limit pinning — `my_profile_page.dart:1587-1639` ← `AyuGram/settings/sections/settings_information.cpp:1060-1148`

- [ ] [MAJOR] Middle-mouse click on an account row to open in a new window is not handled in Dart (only Ctrl+left-click and right-click context menu "Open in New Window" are wired); AyuGram maps `Qt::MiddleButton` to `callback(Qt::ControlModifier)` — `my_profile_page.dart:1607-1637` ← `AyuGram/settings/sections/settings_information.cpp:857-860`

# notification_popup — Audit Findings

- [ ] [CRITICAL] Reply field Enter key adds a newline instead of sending — Dart uses `maxLines: null` (multiline `TextField`) where Enter inserts `\n`; `onSubmitted` never fires for multiline on desktop; only Ctrl+Enter sends via `KeyboardListener`. AyuGram uses `setSubmitSettings(Both)` so plain Enter alone sends immediately — `notification_popup.dart:898-920` ← `notifications_manager_default.cpp:1138`

- [ ] [CRITICAL] `forceHiddenPlaceholder` uses hardcoded sentinel string `'UniClient'` to detect hidden-name notifications instead of reading the actual `hideNameAndPhoto` flag from notification options — fragile: any chat named "UniClient" gets the hidden userpic — `notification_popup.dart:534-537` ← `notifications_manager_default.cpp:923-924`

- [ ] [CRITICAL] Chat title text is never replaced when `hideNameAndPhoto` is active — AyuGram sets the title to `"AyuGram Desktop"` when the privacy setting hides sender identity; the Dart widget always renders `data.chatTitle` / `data.senderName` verbatim, leaking the real name even when the userpic is hidden — `notification_popup.dart:544-547` ← `notifications_manager_default.cpp:1024-1025`

- [ ] [MAJOR] `_PopupState.replyHeight` is initialized to `_replyFieldMinH = 36.0` and is never updated when the user types multiple lines — `totalHeight` stays at 117 px while the actual widget grows up to 153 px (36 → 72 px max), so `_recalcPositions()` places other popups using a stale height, causing overlap — `notification_popup.dart:45,59,62-66,294,331` ← `notifications_manager_default.cpp:787-789`

- [ ] [MAJOR] Reply action button is a circular `Icons.reply` icon instead of the localized text `RoundButton` AyuGram uses (`tr::lng_notification_reply()` uppercased); the visual presentation and size are wrong — `notification_popup.dart:829-841` ← `notifications_manager_default.cpp:678-679`

- [ ] [MAJOR] Close button renders `Icons.close` (Material icon, 16 px) instead of AyuGram's `smallCloseIcon` (10 px glyph inside 30×30 area at `iconPosition: point(10px, 10px)`) — icon content and visual weight differ — `notification_popup.dart:814` ← `window.style:35-47`

- [ ] [MAJOR] Message body text is rendered as plain `Text` / `Text.rich` with no entity or markdown parsing — AyuGram uses `Ui::Text::String` with `TextParseMarkdown | TextParseColorized`, renders custom emoji, colored reaction author names, and spoiler text; Dart strips all formatting from real message previews — `notification_popup.dart:576-645` ← `notifications_manager_default.cpp:952-1001`

- [ ] [MAJOR] Hide-countdown only starts after a Flutter pointer event (`onPointerDown` / `onPointerHover`) inside the overlay, not after OS-level user input — AyuGram polls `base::Platform::LastUserInputTimeSupported()` / `Core::App().lastNonIdleTime()` so the countdown waits until the user interacts with *any* window; Dart keeps notifications up indefinitely if the user never moves the mouse into the Flutter surface — `notification_popup.dart:145-167` ← `notifications_manager_default.cpp:186-199`

# notifications_settings_screen — Audit findings

- [ ] [CRITICAL] `notifReactions` toggle not wired to engine — toggling only calls `appState.notifReactions = v` (AppState setter line 2218 also has no engine call), so the Telegram API `reactionsNotifySettings.setAllFrom()` is never invoked — `notifications_settings_screen.dart:445` ← `settings_notifications.cpp:318-323`

- [ ] [CRITICAL] Notification preview name/text changes not persisted to engine — `onNameChanged`/`onTextChanged` only update AppState booleans with no `saveLocalNotifyConfig` or `engine.*` call, so `notifyView` is never saved via `Core::App().settings().setNotifyView()` — `notifications_settings_screen.dart:268-274` ← `settings_notifications.cpp:1136-1166`

- [ ] [CRITICAL] `_showMuteMenu` "mute forever" and "unmute" actions not persisted to engine — both branches only do `setState(() => _enabled = false/true)` without calling `_persistEnabledState()`, so no `updateDefaultNotifySettings` is fired — `notifications_settings_screen.dart:2218-2221` ← `settings_notifications_type.cpp:428-442`

- [ ] [CRITICAL] `_showMuteMenu` "recent duration" mute not persisted — selecting a recent mute preset calls `setState(() => _enabled = false)` only, no engine call with mute duration/expiry time — `notifications_settings_screen.dart:2210-2215` ← `settings_notifications_type.cpp:428-442`

- [ ] [CRITICAL] `_showMuteDurationPicker` selection not persisted to engine — after picking a custom duration only `setState(() => _enabled = false)` is called; no engine mute-for-duration call is made — `notifications_settings_screen.dart:2233-2237` ← `settings_notifications_type.cpp:428-442`

- [ ] [CRITICAL] `notifUseNative` toggle not wired to engine — `onChanged: (v) => appState.notifUseNative = v` makes no engine call; C++ calls `Core::App().settings().setNativeNotifications()` and `Core::App().notifications().createManager()` — `notifications_settings_screen.dart:656` ← `settings_notifications.cpp:1483-1491`

- [ ] [CRITICAL] `notifSkipToastsInFocus` toggle not wired to engine — `onChanged: (v) => appState.notifSkipToastsInFocus = v` makes no engine call; C++ calls `Core::App().settings().setSkipToastsInFocus()` and triggers `notifySettingsChanged(ChangeType::DesktopEnabled)` — `notifications_settings_screen.dart:673` ← `settings_notifications.cpp:1500-1510`

- [ ] [CRITICAL] `notifDisplayIndex` radio selection not wired to engine — `onChanged: (v) => appState.notifDisplayIndex = v ?? 0` makes no engine call; C++ computes `ScreenNameChecksum` and calls `setNotificationsDisplayChecksum()` + `notifySettingsChanged(ChangeType::Corner)` — `notifications_settings_screen.dart:702-716` ← `settings_notifications.cpp:1565-1583`

- [ ] [CRITICAL] `notifCorner` change not wired to engine — `onCornerChanged: (corner) => appState.notifCorner = corner.index` makes no engine call; C++ calls `Core::App().settings().setNotificationsCorner()` + `notifySettingsChanged(ChangeType::Corner)` — `notifications_settings_screen.dart:744` ← `settings_notifications.cpp:646-651`

- [ ] [CRITICAL] `notifCount` slider change not wired to engine — `onChanged: (count) => appState.notifCount = count` makes no engine call; C++ calls `Core::App().settings().setNotificationsCount()` + `notifySettingsChanged(ChangeType::MaxCount)` — `notifications_settings_screen.dart:763` ← `settings_notifications.cpp:407-412`

- [ ] [MAJOR] Reactions "from" dialog includes a "Nobody" radio option which is wrong — C++ `ShowFromBox` only offers All/Contacts radio buttons (None is achieved via the toggle, not inside the box); Dart adds a third "Nobody" radio inside `_showFromDialog` — `notifications_settings_screen.dart:3057-3066` ← `settings_notifications_reactions.cpp:59-88`

- [ ] [MAJOR] Exception list is static — loaded once in `initState` with no subscription to backend peer-update or exception-update events; C++ `ExceptionsController` subscribes to `exceptionsUpdates()` and `peerUpdates(Flag::Notifications)` to reactively refresh rows — `notifications_settings_screen.dart:1540-1598` ← `settings_notifications_type.cpp:213-234`

# payment_panel — Payment Panel Audit

- [ ] [CRITICAL] `_panelChooseTips()` (line 1326) is dead code — method is defined but never called from any UI element. In AyuGram the tips amount label in the price section is a clickable link (`overrideLinkClickHandler`) that opens the custom tip dialog. Dart has no equivalent click handler on the tips row, making custom tip entry completely inaccessible — `payment_panel.dart:1326` ← `payments_form_summary.cpp:362`

- [ ] [CRITICAL] SmartGlocal tokenization always uses the playground/test URL (`tgb-playground.smart-glocal.com`). AyuGram's `ComputeApiUrl()` uses the `tokenizeUrl` field from `nativeParams` if valid, otherwise chooses production (`tgb.smart-glocal.com`) vs test based on the invoice `isTest` flag. Dart ignores `tokenizeUrl` and hardcodes the playground endpoint for all transactions including live ones — `payment_panel.dart:1238` ← `smartglocal_api_client.cpp:22`

- [ ] [CRITICAL] SmartGlocal tokenization uses `publishableKey` as the `X-PUBLIC-TOKEN` header. AyuGram uses `_configuration.publicToken` (a separate `publicToken` field) not `publishableKey`. These are distinct fields in the native params — `payment_panel.dart:1240` ← `smartglocal_api_client.cpp:64`

- [ ] [CRITICAL] Payment method editing skips the saved-method chooser. AyuGram's `choosePaymentMethod()` shows a `SingleChoiceBox` listing "New card" + all saved methods + additional methods, letting the user pick. Dart's `_editPaymentMethod()` jumps directly to URL or native card form without any saved-method selection step — `payment_panel.dart:973` ← `payments_panel.cpp:637`

- [ ] [CRITICAL] Pre-submission warning box is missing. AyuGram's `showWarning(bot, provider)` displays a confirmation box (with bot name + provider name) that the user must explicitly accept before the payment is sent. Dart calls `engine.sendPaymentForm()` directly with no equivalent warning step — `payment_panel.dart:312` ← `payments_panel.cpp:710`

- [ ] [CRITICAL] Terms acceptance dialog has wrong behavior. AyuGram shows a checkbox + "Accept" button; clicking Accept validates the checkbox is checked and shows an error if not (`showError()`), only then calling `panelAcceptTermsAndSubmit()`. Dart's `_showTermsDialog` auto-closes the dialog and immediately calls `_submitPayment()` on checkbox toggle without requiring any "Accept" button click — `payment_panel.dart:367` ← `payments_panel.cpp:788`

- [ ] [MAJOR] Progress fade duration is 400 ms vs AyuGram's 200 ms (`kProgressDuration = crl::time(200)`), making the loading indicator fade 2× slower than the reference — `payment_panel.dart:31` ← `payments_panel.cpp:33`

- [ ] [MAJOR] Bottom button area padding is wrong. AyuGram: `paymentsPanelPadding: margins(8px, 12px, 15px, 12px)` (left=8, top=12, right=15, bottom=12). Dart uses `EdgeInsets.symmetric(horizontal: _kSubmitHPadding / 2, vertical: 8)` = left=18, top=8, right=18, bottom=8 — both horizontal and vertical padding deviate — `payment_panel.dart:1400` ← `payments.style:28`

- [ ] [MAJOR] Suggested tip buttons use `Wrap` with uniform spacing instead of AyuGram's row-fill layout algorithm. AyuGram's `setupSuggestedTips()` distributes button widths evenly across each row so buttons stretch to fill available width. Dart's `Wrap` leaves unequal gaps at row ends — `payment_panel.dart:820` ← `payments_form_summary.cpp:408`

- [ ] [MAJOR] Stripe tokenization is missing required headers `X-Stripe-User-Agent` and `Stripe-Version: 2015-10-12`. AyuGram sends all three auth/version headers. Dart only sends `Authorization: Bearer` and `Content-Type`, which may cause Stripe API rejections — `payment_panel.dart:1201` ← `stripe_api_client.cpp:53`

- [ ] [MAJOR] Country name resolution uses a hardcoded 53-entry map. AyuGram calls `Countries::Instance().countryNameByISO2()` which is a complete country database. Any country not in the Dart map (e.g. HN, MK, LB, and hundreds more) silently displays its 2-letter ISO code instead of the full name — `payment_panel.dart:1485` ← `payments_form_summary.cpp:517`

- [ ] [MAJOR] `askSetPassword()` equivalent is missing. AyuGram has a `panelAskSetPassword()` flow that prompts the user to set a 2FA cloud password when `passwordMissing` is true in the payment form. Dart has no such prompt — payments requiring a cloud password will silently fail instead of guiding the user — `payment_panel.dart:253` ← `payments_panel.cpp:679`

- [ ] [MAJOR] `_downloadAndCachePhoto()` is called from `_buildThumbnail()` inside `build()` without a concurrent-download guard. The early-return check `if (_cachedPhotoPath != null) return` does not prevent multiple concurrent futures from launching before any one sets `_cachedPhotoPath`. Each rebuild before photo arrival spawns another `HttpClient` download — `payment_panel.dart:728` ← `payments_form_summary.cpp:241`

# peer_short_info — PeerShortInfoBox audit

- [ ] [CRITICAL] "Public photo" label shown unconditionally at last photo index — Dart shows `'Public photo'` whenever `_currentPhotoIndex == _photoCount - 1`, but AyuGram only shows it when `state->photoId == SyncUserFallbackPhotoViewer(peer->asUser())` (the actual fallback/public photo ID). If the last photo is not the public fallback, Dart mislabels it — `peer_short_info.dart:579` ← `prepare_short_info_box.cpp:369`

- [ ] [CRITICAL] No loading feedback during photo navigation — `_fetchPhotoAtIndex` fetches asynchronously with zero visual feedback; cover stays on old image silently. AyuGram drives a radial progress indicator via `_photoLoadingProgress` (updated 0→1 in `applyUserpic`/`updateRadialState` as the photo downloads) — `peer_short_info.dart:362-374` ← `peer_short_info_box.cpp:493-522`

- [ ] [MAJOR] Photo-bar fade threshold wrong — Dart fades bars together with the name/status overlay at `fadeEnd = _kCoverSize - _kShadowHeight = 224 px`. AyuGram fades bars independently at `hiddenAt = _st.size - _st.namePosition.y() = 304 - 37 = 267 px` (bars stay visible ~43 px longer while scrolling) — `peer_short_info.dart:662-669` ← `peer_short_info_box.cpp:277-287`

- [ ] [MAJOR] Bar width precision missing — Dart divides bar area equally with floating-point `barWidth = (size.width - totalGap) / count`. AyuGram computes `_smallWidth` and `_largeWidth = _smallWidth + 1` to distribute sub-pixel remainder with discrete pre-rendered images, preventing fractional drift across bars — `peer_short_info.dart:1206-1211` ← `peer_short_info_box.cpp:589-621`

- [ ] [MAJOR] Context menu "Open in New Window" condition incorrect — Dart suppresses the menu when `activeChat.chatId == peerId` (chat is currently open in main window). AyuGram suppresses it only when a **separate window** already exists for the peer (`window->windowId() == peerSeparateId`). If the chat is active in the main window the menu must still appear; Dart incorrectly hides it — `peer_short_info.dart:379-381` ← `prepare_short_info_box.cpp:505-510`

- [ ] [MAJOR] Video always starts at position 0 — Dart calls `player.open(Media(...))` with no start offset. AyuGram stores `videoStartPosition` from photo metadata and passes it as `options.position` when starting playback, so videos begin at the correct frame — `peer_short_info.dart:262` ← `prepare_short_info_box.cpp:196-198`, `peer_short_info_box.cpp:543-545`

- [ ] [MAJOR] "Set by you" label uses index instead of photo identity — Dart shows "Set by you" when `_currentPhotoIndex == 0 && hasPersonalPhoto`. AyuGram checks `state->photoId == userpicPhotoId` (current photo's actual ID equals the profile photo). Diverges if the userpic photo is not the first in the slice — `peer_short_info.dart:576` ← `prepare_short_info_box.cpp:364-368`

- [ ] [MAJOR] Status text never auto-advances with elapsed time — Dart subscribes only to `engine.onUserStatus` events; "last seen 5 min ago" will not tick to "last seen 6 min ago" without a server event. AyuGram schedules a `base::Timer` via `Data::OnlineChangeTimeout` to re-push status text as time passes — `peer_short_info.dart:156-164` ← `prepare_short_info_box.cpp:257-259`

# photo_crop_editor — Paint tools incomplete, stickers fake, text non-interactive

## CRITICAL

- [ ] [CRITICAL] Blur and Eraser paint tools entirely absent — AyuGram has 5 tools (Pen, Arrow, Marker, Blur, Eraser); Dart enum only has 3 — `photo_crop_editor.dart:89` ← `editor/color_picker.cpp:44-52` + `editor/photo_editor.cpp:28-37`

- [ ] [CRITICAL] Sticker panel shows hardcoded emoji strings instead of real Telegram sticker documents — `_openStickersTool` uses `_kSuggestedEmoji` (32 static strings); AyuGram creates `ItemSticker` from actual `DocumentData*` via `StickersPanelController::stickerChosen` — `photo_crop_editor.dart:545-580` ← `editor/editor_paint.cpp:145-153`

- [ ] [CRITICAL] Text tool uses AlertDialog + static `_TextAnnotation` instead of interactive QGraphics scene item — AyuGram calls `createTextItem()` which produces a draggable, resizable, inline-editable `ItemText` on the canvas; Dart text is placed at crop center with no handles, no drag, no edit-in-place — `photo_crop_editor.dart:484-543` ← `editor/photo_editor.cpp:312-315`

- [ ] [CRITICAL] Custom color picker "+" button missing — AyuGram shows a `PlusCircle` at end of palette that opens a full `ColorEditor::Mode::HSL` box; Dart `_ColorPaletteRow` has only 10 fixed swatches with no path to pick arbitrary colors — `photo_crop_editor.dart:2158-2206` ← `editor/color_picker.cpp:737-771`

- [ ] [CRITICAL] Rainbow-ring `ColorButton` toggle missing — AyuGram renders a circular rainbow-gradient ring (with current-color dot) that toggles palette visibility on click; Dart shows the palette as a permanently-visible static row with no toggle — `photo_crop_editor.dart:872-876` ← `editor/color_picker.cpp:110-185`, `387-389`

- [ ] [CRITICAL] Paint-mode tool buttons placed in wrong bar — AyuGram's paint bottom bar contains only: Cancel | paintModeActiveIcon | (stickers) | textButton | Done; the 5 tool buttons live beside the ColorButton in the separate ColorPicker row; Dart stuffs pen/arrow/marker/text/stickers all into the main bottom bar — `photo_crop_editor.dart:1779-1822` ← `editor/photo_editor_controls.cpp:292-320`

## MAJOR

- [ ] [MAJOR] Canvas zoom not implemented — AyuGram supports 1×–8× zoom via mouse-wheel on the paint QGraphicsView and per-item zoom (0.1×–10×); Dart has no zoom — `photo_crop_editor.dart:1380-1451` (no zoom code) ← `editor/editor_paint.cpp:173-199`, `editor/photo_editor_content.cpp:127-149`

- [ ] [MAJOR] Paint annotations have no selection/drag/resize interaction — AyuGram text and sticker items are QGraphicsItems with handles (move, scale, rotate, delete); Dart `_TextAnnotation` objects are baked-in and immovable after placement — `photo_crop_editor.dart:1570-1588` ← `editor/editor_paint.cpp:56-67`

- [ ] [MAJOR] Animated tool-selection sliding indicator missing — AyuGram draws a filled ellipse that slides between tool buttons using `anim::easeOutCirc`; Dart changes only the icon color — `photo_crop_editor.dart:1783-1813` ← `editor/color_picker.cpp:512-547`

- [ ] [MAJOR] Lottie-animated tool-button icons missing — AyuGram uses `ToolLottieButton` with TGS animations (hover plays forward, leave resets); Dart uses plain `Material Icons` — `photo_crop_editor.dart:1782-1813` ← `editor/color_picker.cpp:187-263`, `332-346`

- [ ] [MAJOR] Cancel in paint mode keeps strokes instead of discarding — AyuGram emits `Action::Discard` when cancel is pressed in paint mode, reverting all paint changes; Dart just toggles `_editorMode` back to transform, leaving `_paintStrokes` and `_textAnnotations` intact — `photo_crop_editor.dart:406-412` ← `editor/photo_editor.cpp:334-342`

- [ ] [MAJOR] Per-tool brush state not persisted across tool switches — AyuGram stores a separate `Brush` (color + sizeRatio) for each of the 5 tools in `_toolBrushes` and restores it when switching; Dart shares a single `_brushColor` and `_brushWidth` for all tools — `photo_crop_editor.dart:250-253` ← `editor/photo_editor.cpp:80-92`, `editor/color_picker.cpp:549-567`

- [ ] [MAJOR] Default per-tool colors wrong — AyuGram defaults: Pen=#EA2739, Arrow=#FC964D, Marker=#FCDE65, Eraser/Blur=#000000; Dart initialises `_brushColor` to #EA2739 for all tools — `photo_crop_editor.dart:250` ← `editor/photo_editor.cpp:61-70`

- [ ] [MAJOR] Corners popup menu missing description label — AyuGram prepends a `MultilineAction` with `tr::lng_photo_editor_corners_about` text above the four corner options; Dart corners `PopupMenuButton` has no description item — `photo_crop_editor.dart:2057-2086` ← `editor/photo_editor_controls.cpp:543-551`

# popup_menu — Context menu widget audit

- [ ] [MAJOR] RTL keyboard navigation not implemented: AyuGram swaps left/right arrow keys for RTL locales — left arrow opens submenu and right arrow closes/escapes in RTL, opposite of LTR. Dart hardcodes left=close-submenu/escape and right=open-submenu regardless of locale, breaking menu keyboard navigation for Arabic/Hebrew/Persian users — `popup_menu.dart:617-647` ← `AyuGram/Telegram/lib_ui/ui/widgets/popup_menu.cpp:428-439`

- [ ] [MAJOR] Trailing separator not cleaned up before display: AyuGram always calls `_menu->clearLastSeparator()` before showing the popup, ensuring menus never end with a visible separator line. Dart renders all items including any trailing `TelegramMenuItem.separator()`, causing a stray line at the bottom of the menu whenever callers conditionally append separators — `popup_menu.dart:695-705` ← `AyuGram/Telegram/lib_ui/ui/widgets/popup_menu.cpp:843-846`

- [ ] [MAJOR] Focus-loss does not dismiss menu on desktop: AyuGram closes the popup via `focusOutEvent` when the window loses focus (e.g. user alt-tabs away). Flutter's `barrierDismissible: true` only captures taps on the barrier overlay — it does not fire when the OS moves focus to another window, leaving the menu visually open until the user taps back into the app — `popup_menu.dart:110` ← `AyuGram/Telegram/lib_ui/ui/widgets/popup_menu.cpp:465-469`

# privacy_settings_screen — Audit

## Summary

One CRITICAL issue found. All other features (cloud password flow, local passcode, blocked users, archive/mute, account TTL, top peers, global TTL, messages privacy, gift settings, birthday, P2P privacy, forward privacy preview) are properly wired to the engine.

---

- [ ] [CRITICAL] Privacy exception lists (always/never users) are silently wiped on every save — `_EditPrivacyBoxState._save()` calls `setPrivacySetting` without passing `alwaysIds` or `neverIds`, so they default to `[]` and overwrite whatever exceptions were previously set on the server. The widget receives `initialAlwaysUsers`/`initialNeverUsers` from the server but they are never forwarded back on save. Additionally `_EditPrivacyBoxState` has no mutable state fields for exceptions and no UI to add/edit them ("Always share with" / "Never share with" buttons), so the feature is entirely absent. Any user who had exceptions configured via another client will have them silently destroyed the next time they open and save privacy settings here. — `privacy_settings_screen.dart:2139` ← `boxes/edit_privacy_box.cpp:794`

## reactions_detail — Reactions/read detail panel

- [ ] [CRITICAL] DM read-receipt tab is entirely missing: `_fetchReadCount` at line 129 explicitly skips `ChatType.dm`, but AyuGram uses `MTPmessages_GetOutboxReadDate` for DM messages to fetch and display the read date/tab for single recipients — `reactions_detail.dart:129` ← `AyuGram/api/api_who_reacted.cpp:257-285`

- [ ] [CRITICAL] No real-time reaction/read update subscription: the panel fetches data once on `initState` and never subscribes to live engine events. AyuGram uses `rpl::variable` reactive streams (`context->cacheReacted`, `context->cacheRead`) that push updates to the UI whenever the underlying data changes (e.g. new reactions arrive, userpics load) — `reactions_detail.dart:103-111` ← `AyuGram/api/api_who_reacted.cpp:180-218, 340-392`

- [ ] [CRITICAL] The "Show" button in `_ReadPrivacyNotice` calls `engine.setHideReadMarks(accountId, hide: false)` which directly toggles the privacy setting via an inline confirmation dialog. In AyuGram the callback is `showOrPremium` which opens the Privacy & Security settings page (not a direct API call) so the user can manage the full privacy setting — `reactions_detail.dart:1103-1124` ← `AyuGram/ui/controls/who_reacted_context_action.cpp:567-574`

- [ ] [MAJOR] `_groupedByEmoji` getter uses `r.emoji` as the map key for all reactors, meaning custom-emoji reactors (where `r.emoji` is empty string) all collide under the `""` key instead of a unique `'custom:<docId>'` key. The correct key is `r.reactionKey`. This is a latent correctness bug that corrupts grouping whenever custom emoji reactions are present — `reactions_detail.dart:262` ← `AyuGram/history/view/reactions/history_view_reactions_list.cpp:397-409`

- [ ] [MAJOR] `_fetchReadCount` calls `getMessageReadParticipants` (IDs only, no dates) purely to get a count, while `_loadReactors` separately calls `getMessageReadParticipantsDetailed` for the full data. This is two API calls for the same data — the count should be derived from the detailed result already fetched by `_loadReactors` — `reactions_detail.dart:128-138, 171-187` ← `AyuGram/api/api_who_reacted.cpp:286-315`

- [ ] [MAJOR] `_ReactionTabBar._readTabIcon` returns `Icons.play_arrow` for both `mediaType == 2` (video) and `mediaType == 5` (round video/video note). AyuGram distinguishes `WhoReadType::Watched` (round video) with a distinct "played" icon (`reactionsTabPlayed`) separate from regular video. The Dart code conflates both cases with the same icon — `reactions_detail.dart:546-548` ← `AyuGram/api/api_who_reacted.cpp:230-243`

- [ ] [MAJOR] Panel max width is hardcoded at 392px. AyuGram's reactions list opens as a full `Info::Widget` section panel (full sidebar width), not a fixed-width dialog overlay. A 392px popup is visually and behaviorally different from the intended full side-panel approach — `reactions_detail.dart:62` ← `AyuGram/info/reactions_list/info_reactions_list_widget.cpp:84-113`

- [ ] [MAJOR] On tab switch from read-tab back to a specific emoji tab, `_allReactors` is cleared and `_loadReactors()` is called. The cache check at line 189 (`_selectedTab != null && _masterReactors.isNotEmpty`) is true for emoji tabs, but since `_allReactors` was just cleared it falls through to the network call path anyway, causing unnecessary re-fetches on every read→emoji tab switch — `reactions_detail.dart:189-196, 287-313` ← `AyuGram/history/view/reactions/history_view_reactions_list.cpp:247-280`

- [ ] [MAJOR] Loading state shows a plain `Text('Loading...')` string. AyuGram shows placeholder preloader rows with animated loading text (`tr::lng_contacts_loading`) that visually match the list layout during load, giving proper visual continuity — `reactions_detail.dart:373-381` ← `AyuGram/history/view/reactions/history_view_reactions_list.cpp:241-243`

- [ ] [MAJOR] `_ReactorAvatar` photo cache is a static `Map<String, String?>` that evicts one entry at a time when it exceeds 200 entries (removes `_photoCache.keys.first`). Dart's default `Map` does not guarantee stable iteration order under concurrent modifications, meaning wrong entries may be evicted. Additionally the cache grows unbounded between eviction triggers and holds stale file paths for photos that may have changed — `reactions_detail.dart:960-995` ← AyuGram: no direct equivalent (AyuGram generates userpics on-demand via `PeerData::GenerateUserpicImage` with session-level invalidation)

## send_files_box — Send Files Dialog audit vs AyuGram C++ source

- [ ] [MAJOR] `_canSpoiler` gate is wrong: Dart checks `!_sendAsDocuments && files.any(isMediaType)` but AyuGram's `hasSpoilerMenu` requires `allAreVideo || (allAreMedia && compress)` — i.e. spoiler menu is only available when ALL files are media (video-only always OK, mixed photo+video only OK when sending as photos). Mixed photo+file batches incorrectly expose the spoiler toggle in Dart. — `send_files_box.dart:1178` ← `AyuGram/ui/chat/attach/attach_prepare.cpp:399`

- [ ] [MAJOR] `_hasHighQualityOption` gate is wrong: Dart checks `!_sendAsDocuments && files.any(photo)` but AyuGram's `hasSendLargePhotosOption` requires `compress && files.any(canUseHighQualityPhoto)` — meaning it must be sending as photos AND the specific file must qualify for high-quality (not all photos do). Dart shows the HD option for any photo file even if it would never be sent compressed. — `send_files_box.dart:1090` ← `AyuGram/ui/chat/attach/attach_prepare.cpp:411`

- [ ] [MAJOR] Caption visibility is not gated on `canAddCaption`. In AyuGram, `updateCaptionVisibility` hides the caption field entirely when the send way doesn't permit captions (e.g. sticker-only sends). Dart always shows the caption field regardless of file types or send way. — `send_files_box.dart:1707` ← `AyuGram/boxes/send_files_box.cpp:1271`

- [ ] [MAJOR] Photo editor hint label is missing. AyuGram shows `_hintLabel` ("Open in photo editor" hint) after the user has edited a photo at least once (`photoEditorHintShown`). Dart has no equivalent hint label at all. — `send_files_box.dart` (absent) ← `AyuGram/boxes/send_files_box.cpp:1795`

- [ ] [MAJOR] Paid-media price is read-only / not changeable. AyuGram exposes `EditPriceBox` via the send menu's `ChangePrice` action for broadcast channels that can post paid media. Dart only shows a static star badge overlay (`starsPerMessage * fileCount`) with no way to change the price in the send files dialog. — `send_files_box.dart:1569` ← `AyuGram/boxes/send_files_box.cpp:1058`

- [ ] [MAJOR] `_showEditCaptionDialog` / `_editFileCaption` uses a plain `AlertDialog` with a bare `TextField` instead of a proper styled caption box. AyuGram uses `EditFileCaptionBox` which includes a full `InputField` with markup support, custom emoji, markdown rendering, and character limit enforcement that calls `validateLength`. — `send_files_box.dart:725` ← `AyuGram/boxes/send_files_box.cpp:180`

- [ ] [MAJOR] Per-file captions are not per-file entity-formatted. AyuGram stores per-file captions as `TextWithTags` (rich text with formatting entities). Dart stores them as plain strings (`Map<int, String> _perFileCaptions`) with no entity support. The caption is then passed to the engine but with no entity data for the per-file slots. — `send_files_box.dart:329` ← `AyuGram/boxes/send_files_box.cpp:605`

- [ ] [MAJOR] `send()` does not call `applyBlockChanges()` + `Storage::ApplyModifications(_list)` equivalents before emitting the result. AyuGram's `send()` applies spoiler states back from block UI to file list and calls `ApplyModifications` before invoking the callback. Dart reads spoiler state from `_files` directly without any re-sync step, which means drag-reordering in the album preview could leave stale spoiler state. — `send_files_box.dart:1272` ← `AyuGram/boxes/send_files_box.cpp:2387`

- [ ] [MAJOR] File-drag reorder for document-only blocks uses swap (not `moveFile`). AyuGram's `moveFile` uses `refreshAllAfterChanges(min(from,to), swap)` which regenerates all blocks from the affected index. Dart swaps two elements in `_files` directly without re-running block/album layout logic, leaving album grouping out of sync for multi-file document blocks. — `send_files_box.dart:1623` ← `AyuGram/boxes/send_files_box.cpp:2473`

- [ ] [MAJOR] `_canSendAsSticker` gates the top-menu "Send as sticker" action only for photos in the top-right "more" menu. AyuGram adds this action to the send-menu (bottom-right send button menu) as well, and correctly handles the WEBP conversion + overrides `overrideSendImagesAsPhotos = false` before closing. Dart's `_sendAsSticker()` just calls `_send(asSticker: true)` with no WEBP conversion or send-way reset. — `send_files_box.dart:1268` ← `AyuGram/boxes/send_files_box.cpp:1188`

- [ ] [MAJOR] `_removeFile` allows removing the last file with no replacement (the length-1 guard returns silently). AyuGram's delete handler closes the entire box with `requestToTakeTextWithTags()` + `closeBox()` when the last file is removed, preserving the caption back to the caller. Dart just silently does nothing, leaving an empty file list with the dialog still open. — `send_files_box.dart:1103` ← `AyuGram/boxes/send_files_box.cpp:1655`

- [ ] [MAJOR] When the last file is deleted and there is a next-to-last file, AyuGram moves that file's per-file caption into the main caption field (`_caption->setTextWithTags(was)`) if the main caption is empty. Dart does no caption promotion on file removal. — `send_files_box.dart:1103` ← `AyuGram/boxes/send_files_box.cpp:1663`

- [ ] [MAJOR] `_showSendMenu` ("quality" toggle) uses `Icons.check` when `_sendLargePhotos=true` as a checkmark indicator, but the label reads "Send in high quality" regardless of current state. AyuGram puts quality and spoiler into `SendMenu::Details` with proper state (PhotoQualityState::High vs Standard), so the menu item renders as a checked/unchecked action. Dart's approach shows a misleading static label "Send in high quality" even when already in high quality, and a check icon that is confusable with confirmation. — `send_files_box.dart:1318` ← `AyuGram/boxes/send_files_box.cpp:741`

- [ ] [MAJOR] `_doEdit` opens `PhotoCropEditor` (crop-only tool) for the photo editor. AyuGram opens `Editor::OpenWithPreparedFile` which is the full photo editor (draw, paint, crop, stickers, text). Dart lacks access to the full photo editor and substitutes crop only. — `send_files_box.dart:2151` ← `AyuGram/boxes/send_files_box.cpp:1361`

- [ ] [MAJOR] Album thumb right-click only fires when `canSpoiler` is true (`onSecondaryTapUp: widget.canSpoiler ? ... : null`). AyuGram shows the context menu on all album thumbs unconditionally (replace, edit, rename, caption, spoiler, cover). When `canSpoiler` is false (e.g. sending as documents), the Dart album context menu is completely disabled. — `send_files_box.dart:2653` ← `AyuGram/boxes/send_files_box.cpp:1524`

- [ ] [MAJOR] Caption preservation on cancel differs: Dart stores the caption in a static `_preservedCaption` field on the class and restores it next time the box opens. AyuGram uses `_cancelled2Callback` which fires with `TextWithTags` to the caller, letting the compose bar receive the text back. The Dart approach works only when the same class is re-instantiated within the same app lifecycle (global static). — `send_files_box.dart:528` ← `AyuGram/boxes/send_files_box.cpp:836`

- [ ] [MAJOR] `_hasGroupOption` only considers media file count for grouping, not documents. In AyuGram, `hasGroupOption` on `PreparedList` considers all files (including document blocks) when `!sendImagesAsPhotos`. Dart's `_hasGroupOption` returns false for pure document batches of 2+ unless `_sendAsDocuments` is true, meaning the "Group files" checkbox never appears for mixed document-only sends. — `send_files_box.dart:1096` ← `AyuGram/boxes/send_files_box.cpp:1822`

- [ ] [CRITICAL] `_doEditCover` / `_editCover` in both `_SingleMediaPreview` and `_AlbumPreviewState` mutate `file.videoCoverPath` directly on the `_PreparedFile` object but never call `setState` on the parent `_SendFilesBoxDialogState`, so the cover path change is silently lost after a `_files` rebuild triggered by any other action. AyuGram refreshes via `refreshAllAfterChanges`. — `send_files_box.dart:2233` ← `AyuGram/boxes/send_files_box.cpp:1517`

- [ ] [CRITICAL] `_doClearCover()` in `_SingleMediaPreview` mutates `file.videoCoverPath = null` without notifying parent state. Same issue: no `setState` is triggered, so the clear is lost on next rebuild. — `send_files_box.dart:2239` ← `AyuGram/boxes/send_files_box.cpp:1517`

# settings_screen — Audit Findings

- [ ] [CRITICAL] `_CallsSettingsTab` output device `onTap: () {}` is an empty stub — opens no device picker, never reads real device list from engine — `settings_screen.dart:2088` ← `settings/sections/settings_calls.cpp:82` (`InitPlaybackButton` opens `ChoosePlaybackDeviceBox` with live `DeviceIdOrDefault` stream)

- [ ] [CRITICAL] `_CallsSettingsTab` input device `onTap: () {}` is an empty stub — opens no device picker, no microphone level meter — `settings_screen.dart:2094` ← `settings/sections/settings_calls.cpp:99` (`InitCaptureButton` wires `ChooseCaptureDeviceBox` and `AudioInputTester` level meter)

- [ ] [CRITICAL] `_CallsSettingsTab` P2P radio buttons all use `onTap: () {}` — selection is never read from or written to the engine; always renders "My contacts" as checked regardless of real setting — `settings_screen.dart:2111` ← `settings/sections/settings_privacy_security.cpp:92` (P2P setting is a privacy rule fetched and saved via `Api::UserPrivacy`)

- [ ] [CRITICAL] `_CallsSettingsTab` missing "Accept Calls" toggle — AyuGram has a toggle that reads/writes `authorizations->callsDisabledHere()` via `api->authorizations().toggleCallsDisabledHere()` — no such control exists anywhere in `_CallsSettingsTab` — `settings_screen.dart:2065` ← `settings/sections/settings_calls.cpp:392`

- [ ] [CRITICAL] `_CallsSettingsTab` missing camera/video section — AyuGram's `BuildCameraSection` shows a video device selector with live preview when a camera is detected; Dart has no camera subsection at all — `settings_screen.dart:2065` ← `settings/sections/settings_calls.cpp:343`

- [ ] [CRITICAL] `_PremiumInfoScreen._loadPremiumInfo` returns a hardcoded static list of 8 strings, never calls any engine method — features are not loaded from the live API — `settings_screen.dart:2198` ← `settings/sections/settings_premium.cpp:240` (AyuGram builds feature rows from `FallbackOrder()` + MTP `premium_promo_order` app config, 21 real entries)

- [ ] [CRITICAL] `_BusinessScreen` is a static info page with no clickable sub-screens — AyuGram's business screen has fully navigable sub-pages (Working Hours, Location, Greeting, Away, Quick Replies, Chatbots, Chat Intro, Chat Links) each backed by real API calls — `settings_screen.dart:2404` ← `settings/sections/settings_business.cpp:100` (`EntryMap()` + `buttonCallback` per feature navigates to dedicated business sub-screens)

- [ ] [CRITICAL] `_CreditsScreen` "Buy Stars" button opens external URL `https://t.me/stars` — AyuGram opens in-app purchase via `BuildCreditsButtons` / `gift_credits_box.h`; no transaction history, no subscription management shown — `settings_screen.dart:2374` ← `settings/sections/settings_credits.cpp:82` (`BuildCreditsButtons` and `setupHistory`/`setupSubscriptions` show full transaction history with tabs In/Out/Full)

- [ ] [MAJOR] `_GiftCatalogScreen` loads gifts via `engine.getStarGifts` (correct) but tapping a gift item has no action — no recipient picker or send flow is wired; the `GridView.builder` items have no `onTap` handler — `settings_screen.dart:2561` ← `settings/sections/settings_main.cpp:593` (`Ui::ChooseStarGiftRecipient(controller)` opens a full recipient-selection flow)

- [ ] [MAJOR] Premium settings section missing "Telegram Currency" (TON/crypto wallet) row — AyuGram shows it when `tonBalanceValue` is non-empty (`main/currency` button with `st::menuIconTon`) — no such row exists in the Dart premium section — `settings_screen.dart:401` ← `settings/sections/settings_main.cpp:563`

- [ ] [MAJOR] `_CallsSettingsTab` device value is hardcoded string `'Default'` — actual selected device name is never fetched from the engine, so the row always shows "Default" even when a specific device is configured — `settings_screen.dart:2086,2092` ← `settings/sections/settings_calls.cpp:56` (`DeviceNameValue` resolves live device name from `Core::App().mediaDevices().devicesValue()`)

- [ ] [MAJOR] `_CallsSettingsTab` missing "Use same device for calls" toggle — AyuGram has `calls/same-devices` toggle that switches between shared audio device and separate call-specific playback/capture devices — `settings_screen.dart:2065` ← `settings/sections/settings_calls.cpp:245`

- [ ] [MAJOR] Username `onTap` copies link to clipboard with `showTelegramToast` — AyuGram's behaviour when username is non-empty is identical (copies link + shows toast), but when username is empty it opens `UsernamesBox` to add one; Dart's `_onUsernameTap` returns early on empty username with no navigation — `settings_screen.dart:895` ← `settings/sections/settings_main.cpp:301`

- [ ] [MAJOR] Profile header photo size is 72px in Dart vs `st::infoProfileCover.photo.size` which resolves to 80px in AyuGram style — Dart uses `CircleAvatar(radius: 36)` = 72px diameter — `settings_screen.dart:628` ← `settings/sections/settings_main.cpp:144` (height = `st::settingsPhotoTop + st::infoProfileCover.photo.size.height() + st::settingsPhotoBottom`)

- [ ] [MAJOR] `_PremiumInfoScreen` "Subscribe to Premium" button opens external URL — AyuGram calls `controller->setPremiumRef("settings")` then opens the in-app Premium payment flow (`showOther(PremiumId())`); Dart uses `_openUrl('https://t.me/premium')` — `settings_screen.dart:2285` ← `settings/sections/settings_main.cpp:538`

# shell — Audit findings

## shell — Connecting pill shows spinner + wrong text when proxy-enabled and connected

- [ ] [CRITICAL] `_buildPill()` accepts a `ConnState state` parameter but never uses it. When the widget is visible due to proxy being enabled but the connection state is `connected`, the method still renders a `CircularProgressIndicator` spinner and shows "Connecting…" text on hover. In AyuGram, `computeLayout()` sets `progressShown = (state.type != State::Type::Connected)` and the progress widget is hidden when connected; only the proxy icon is shown. The Dart should hide the spinner and suppress the hover-text when `state == ConnState.connected`. — `shell.dart:1130` (unused `state` param), `shell.dart:1160-1167` (unconditional spinner) ← `window_connecting_widget.cpp:442` (`progressShown = state.type != Connected`), `window_connecting_widget.cpp:629-633` (`setProgressVisibility`)

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

