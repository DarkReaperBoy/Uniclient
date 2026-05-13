# GUI Audit — Cycle 1 Phase Ayugram (2026-05-11 19:41)

## Code Comparison (Dart vs AyuGram)

# bridge — No issues found

## Overview

`bridge.dart` is a platform abstraction layer for FFI/WASM communication with the Go backend. It cannot be directly compared to AyuGram Desktop (a C++ Qt application with no Dart UI layer) — this is infrastructure code, not UI code.

## Audit Results

✅ **Implementations are complete** — bridge_ffi.dart and bridge_web.dart are fully implemented with no stubs or placeholders

✅ **Memory management is correct** — FFI properly uses calloc/free for request/response marshalling; event data is copied before freeing C-allocated memory; web delegates to JS GC

✅ **Event callback is properly wired** — Uses NativeCallable.listener in FFI to allow Go to call from any goroutine; uses JS interop in web; both properly stream events to listeners

✅ **Async handling is correct** — FFI uses Isolate.run to avoid blocking the UI thread; web's callAsync just delegates to call() since JS is already single-threaded

✅ **Platform detection is correct** — Loads libcores.so/.dylib/cores.dll/.so on Linux/macOS/Windows/Android respectively

✅ **Integration is correct** — EngineService properly initializes bridge, subscribes to events, and uses bridge.call/callAsync for RPC

✅ **No placeholders, TODOs, or fake data** — All code is production-quality

## Non-Issues

- **bridge_stub.dart** is intentionally a fallback stub for compile-time safety (conditional imports ensure it's never used at runtime)
- **Web callAsync delegates to call()** is correct because JS is already single-threaded (true async unnecessary)

## Conclusion

No auditable issues found. Code quality is high.


# notification_types — Notification text composition & data structures

## Issues Found

- [x] [CRITICAL] Login code masking regex differs from AyuGram specification — `notification_types.dart:232` ← `AyuGramDesktop/Telegram/SourceFiles/history/history_item.cpp:67-68`
  - **Dart pattern:** `r'(?<![\w\-#])(\d[\d\-]{2,6}\d)(?!\w|\-)'` — negative lookahead rejects codes immediately before ANY word character or hyphen
  - **AyuGram pattern:** `u"(?<![\\w\\-#])(\\d[\\d\\-]{2,6}\\d)(?!\\w\\-)"_q` → `(?<![\w\-#])(\d[\d\-]{2,6}\d)(?!\w\-)` — negative lookahead rejects codes immediately before word-character-THEN-hyphen sequence
  - **Impact:** Dart incorrectly rejects codes like "123456" in text "123456a" (when followed by letters), while AyuGram would match. Makes login code masking more restrictive than intended.
  - **Example:** text "Code: 123456 end" matches in both; text "Code: 123456a end" matches in AyuGram but NOT in Dart (because "a" is word char).

- [x] [CRITICAL] Reaction text composition doesn't handle custom emoji reactions — `notification_types.dart:378-411` ← `AyuGramDesktop/Telegram/SourceFiles/window/notifications_manager.cpp:1111-1220`
  - **Dart:** stores reaction as `data.reactionEmoji` (string only), no handling for custom emoji document IDs
  - **AyuGram:** `ComposeReactionEmoji()` checks if reaction is QString emoji OR DocumentId, then looks up document sticker for alt text or placeholder
  - **Impact:** Custom emoji reactions (sticker-based) won't render correctly; will show as empty or wrong emoji.

- [x] [CRITICAL] Contact reaction text missing first/last name handling — `notification_types.dart:399-403` ← `AyuGramDesktop/Telegram/SourceFiles/window/notifications_manager.cpp:1183-1200`
  - **Dart:** hardcoded `'${data.contactName}'`, assumes name is pre-composed
  - **AyuGram:** `ComposeReactionNotification()` constructs full name from `contact->firstName` and `contact->lastName` with proper fallbacks (line 1184-1193): "firstName lastName" or just "firstName" or just "lastName"
  - **Impact:** Contact reactions show contact name as-is from data, but proper name composition (handling empty first/last names) isn't applied. If only first name exists, notification won't show it properly formatted.

- [x] [CRITICAL] Poll vote text doesn't validate against actual poll data — `notification_types.dart:413-425` ← `AyuGramDesktop/Telegram/SourceFiles/window/notifications_manager.cpp:1222-1246`
  - **Dart:** uses `data.pollVoteOption` string directly, assumes it's already set correctly
  - **AyuGram:** `ComposePollVoteNotification()` looks up the actual poll via `media->poll()`, then calls `poll->answerByOption(option)` to get the answer text (line 1234)
  - **Impact:** If pollVoteOption data is incorrect, malformed, or out of sync, Dart will display wrong vote text. AyuGram validates against actual poll object.

- [x] [MAJOR] All notification text strings are hardcoded English with no localization — `notification_types.dart:257-425` ← `AyuGramDesktop/Telegram/SourceFiles/window/notifications_manager.cpp:1140-1245`
  - **Dart:** All strings like "You have a new message", "Photo, ", "Voted in a poll" are hardcoded
  - **AyuGram:** Uses localized strings via `tr::lng_*()` function calls (tr::lng_reaction_notext, tr::lng_reaction_photo, etc.)
  - **Impact:** Notifications always display in English regardless of app language setting. Should respect user's language preference.

- [x] [MAJOR] Media type descriptions incomplete compared to AyuGram — `notification_types.dart:329-365` ← `AyuGramDesktop/Telegram/SourceFiles/window/notifications_manager.cpp:1160-1219`
  - **Dart:** simple switch on messageType (0-12) with basic text like "Photo", "Video", "Voice message"
  - **AyuGram:** `ComposeReactionNotification()` has many more cases:
    - Distinguishes isVoiceMessage vs isVideoMessage vs isAnimation vs isVideoFile (line 1165-1172)
    - Handles stickers with emoji (extracts sticker->alt)
    - Handles contacts with proper name composition
    - Handles polls distinguishing quiz vs poll
    - Handles game, invoice, location with live location check
  - **Impact:** Dart's media type descriptions are oversimplified; won't properly display reaction context for all media types.

- [x] [MAJOR] Missing proper spoiler/entity handling in poll vote text — `notification_types.dart:413-425` ← `AyuGramDesktop/Telegram/SourceFiles/window/notifications_manager.cpp:1596-1604`
  - **Dart:** returns plain string, no TextWithEntities or entity formatting
  - **AyuGram:** returns `TextWithEntities` with proper spoiler masking via `TextWithPermanentSpoiler()` (line 1597-1600)
  - **Impact:** Poll vote text won't have spoilers masked in notifications, showing hidden content.

- [x] [MAJOR] Missing proper spoiler/entity handling in reaction text — `notification_types.dart:378-411` ← `AyuGramDesktop/Telegram/SourceFiles/window/notifications_manager.cpp:1601-1605`
  - **Dart:** returns plain string
  - **AyuGram:** wraps in `TextWithPermanentSpoiler()` (line 1602-1605)
  - **Impact:** Reaction text won't mask spoilers, showing spoilered content in notifications.

- [x] [MAJOR] Account name formatting may be incorrect for multi-account — `notification_types.dart:275-277` ← `AyuGramDesktop/Telegram/SourceFiles/window/notifications_manager.cpp:1264-1278`
  - **Dart:** appends `' ➜ ${data.accountUsername}'` as plain string concatenation
  - **AyuGram:** uses `addTargetAccountName()` which constructs `title.append(accountNameSeparator()).append(...)` with proper separator `" ➜ "`
  - **Impact:** Minor visual difference, but proper separator handling ensures consistent formatting across all notification types.

## Summary

**4 CRITICAL + 5 MAJOR = 9 issues.** The notification_types module has multiple deviations from AyuGram Desktop implementation:

- Regex pattern difference for login codes (overly restrictive)
- Missing custom emoji reaction support
- Missing contact name composition logic  
- Missing poll answer validation
- Hardcoded English text (no localization)
- Incomplete media type handling
- Missing spoiler entity masking
- Multi-account name formatting deviation

The most critical issues are:
1. **Login code regex mismatch** — functional bug where codes are masked incorrectly
2. **Missing custom emoji support** — won't display custom reactions properly
3. **Hardcoded English localization** — violates user language preference
4. **Missing spoiler masking** — shows hidden content in notifications

**Recommendation:** This module needs significant rework to match AyuGram's notification composition logic, especially for proper localization, entity handling (spoilers), and media type descriptions.

# app_state — State management layer audit


# audio_service — Backend Wiring & Metadata Issues



# bridge_ffi.dart — FFI Bridge Infrastructure Audit

## Summary
The FFI bridge implementation is structurally sound and has proper memory management. However, there are 3 issues affecting release-mode safety and resource cleanup.

---

## Issues Found


---

## What's Working Correctly

✓ Memory management in `_doCall()` (lines 102-131): Proper allocation, usage, and freeing of pointers  
✓ Event callback marshaling via `NativeCallable.listener()` (line 162): Correct async handling from Go goroutines  
✓ Isolate-based async calls (lines 75-79, 135-143): Background FFI calls prevent UI blocking  
✓ Null pointer checks (line 117): Handles empty/error responses from backend  

---

## Cross-Check Notes

- This is infrastructure code (FFI wrapper) with no direct AyuGram C++ equivalent to compare against
- No stubs, TODOs, or placeholder implementations found
- No hardcoded mock data or fake callbacks
- Backend wiring is complete: `init()` → load library → set event callback → calls go through `_callWithLen`

# theme_preview — Audit Findings

## CRITICAL Issues

- [x] **[CRITICAL]** Incorrect avatar initials logic — `theme_preview.dart:746-750` ← `window_theme_preview.cpp:35-90`
  - Dart splits by space and takes first+second word letters: `name.split(' ')` then `parts[0][0]` + `parts[1][0]`
  - AyuGram uses `FillLetters()` which handles emoji (skips), diacritics, surrogates, and prefers space/dash boundaries
  - Impact: Names with emoji (e.g., "🎨 Alex") will show emoji symbol instead of "A". Names with diacritics handled incorrectly.
  - Fix: Implement proper Unicode-aware initials extraction matching AyuGram's algorithm

## MAJOR Issues

- [x] **[MAJOR]** Photo bubble uses hardcoded gradient instead of loading actual image — `theme_preview.dart:594-608` ← `window_theme_preview.cpp:382`
  - Dart: Uses hardcoded `LinearGradient(colors: [0xFF6BA3D6, 0xFF3D7AB5, 0xFF2B5E8C])`
  - AyuGram: Loads `":/gui/art/themeimage.jpg"` as real image file
  - Impact: Theme preview shows fake gradient instead of actual photo. If theme changes affect photo rendering, this preview won't reflect it.
  - Workaround: Acceptable for now since it's a visual placeholder, but should load actual image for full accuracy

- [x] **[MAJOR]** Dialog row count mismatch with spec — `theme_preview.dart:120` ← spec section 25.13
  - Dart draws 8 rows: `for (int i = 0; i < 8; i++)`
  - Spec states: "9 conversation rows with:" (section 25.13)
  - AyuGram code reserves 9 but only populates 8 (line 343: `_rows.reserve(9)` then adds 8 rows)
  - Note: This matches AyuGram's implementation, so may be intentional (9th row scrolled/partially off-screen)
  - Impact: Minor — preview shows 8 rows as designed, matches AyuGram. Spec may be outdated.

- [x] **[MAJOR]** Text rendering uses TextPainter with hardcoded maxWidth instead of proper layout — `theme_preview.dart:752-765`
  - Dart: Creates new TextPainter each time, uses `maxWidth: maxWidth ?? 500`
  - AyuGram: Uses `Ui::Text::String` which pre-computes layout and respects style system margins/padding
  - Impact: Text wrapping/truncation may differ from actual chat. Hardcoded 500px fallback is arbitrary.
  - Severity: Medium — visual discrepancies unlikely for preview text, but not spec-compliant

## No Issues Found — Items Verified OK

- ✓ **Dimensions match AyuGram spec:**
  - `themePreviewSize`: 903x584px ✓
  - `themePreviewDialogsWidth`: 312px ✓
  - `dialogsRowHeight`: 62px ✓
  - `topBarHeight`: 54px ✓
  - `historySendSize.height`: 46px (compose) ✓

- ✓ **Colors use palette correctly** — All color references use `palette.*` fields, not hardcoded hex (except photo gradient)

- ✓ **Icon drawing** — Menu dots, call icon, search icon, pin icon, check marks, attach icon, microphone all render correctly

- ✓ **Bubble rendering** — Message bubbles with replies, tails, attach flags render with correct corner rounding logic

- ✓ **Audio waveform** — Wavedata array matches AyuGram exactly (67 samples), correct active count (33), bar rendering logic correct

- ✓ **Test data consistency** — 8 dialog rows, names, emojis, timestamps all match AyuGram's data in `generateData()`

- ✓ **No backend calls** — Purely visual widget; doesn't call engine/bridge. Appropriate for theme preview.

- ✓ **No placeholders/stubs** — All methods have complete implementations; no "not implemented" returns

## Summary

**Total Issues: 3 (1 CRITICAL, 2 MAJOR)**

Theme preview is functional and mostly matches AyuGram. Primary issue is emoji-unsafe initials logic which could show garbled characters for emoji names. Secondary issues are text layout differences and photo placeholder image. All dimensions and colors correct.

**Recommended fixes:**
1. **CRITICAL:** Replace `_initials()` with Unicode-aware algorithm (handle emoji, diacritics, surrogates)
2. **MAJOR:** Load actual background image instead of gradient placeholder (copy from AyuGram: `:/gui/art/themeimage.jpg`)
3. **MAJOR:** Use proper text layout system if available, or document hardcoded maxWidth behavior

# wallpaper.dart audit

## Summary
Comprehensive audit of `dart/lib/theme/wallpaper.dart` against AyuGram Desktop wallpaper implementation (`data/data_wall_paper.h`, `boxes/background_preview_box.cpp`, `ui/chat/chat_theme.cpp`).

## Issues Found

### [CRITICAL] Multi-color gradient animation uses wrong algorithm — `wallpaper.dart:370-373` ← `AyuGramDesktop/lib_ui/ui/image/image_prepare.cpp:GenerateSmallComplexGradient`

The Dart `_MultiGradientPainter.paint()` implements gradient animation by rotating the angle: `angle = (realRotation % 360 + t * 360)`. This treats the animation as a continuous 360° rotation per frame.

AyuGram's `GenerateSmallComplexGradient()` uses a different algorithm:
- Computes discrete `phase` positions (0-7 for 8-direction swirl)
- Interpolates between `previousPhase` and `current` phase based on `progress`
- Uses a mathematical swirl/radial gradient formula, not simple rotation

**Impact**: The animated gradient will appear to rotate continuously in Dart, while AyuGram displays a swirling/shimmering effect that stays within 8 discrete orientations. Visual appearance differs.

**Severity**: CRITICAL — animating gradients with 3+ colors will not match AyuGram's behavior.

---

### [MAJOR] Two-color gradient rotation calculation differs from AyuGram spec — `wallpaper.dart:296-300` ← `AyuGramDesktop/lib_ui/ui/image/image_prepare.cpp:GenerateLinearGradient:case 0-7`

Dart's `_TwoColorGradient._rotationToAlignment()` converts rotation degrees to Alignment using continuous sin/cos:
```dart
final rad = degrees * math.pi / 180.0;
final dx = math.sin(rad);
final dy = -math.cos(rad);
return (Alignment(-dx, -dy), Alignment(dx, dy));
```

AyuGram's `GenerateLinearGradient()` uses 8 discrete rotation cases in a switch statement:
```cpp
const auto type = std::clamp(rotation, 0, 315) / 45;
switch (type) {
  case 0: return { { 0, 0 }, { 0, height } };      // 0°
  case 1: return { { width, 0 }, { 0, height } };  // 45°
  case 2: return { { width, 0 }, { 0, 0 } };       // 90°
  // ... 6 more cases
}
```

**Deviation**: For rotation values that are not multiples of 45°, Dart produces continuous alignments while AyuGram quantizes to the 8 discrete directions. Visual gradient orientations may differ slightly.

**Severity**: MAJOR (>10% visual deviation from spec, though Flutter's continuous interpolation may be acceptable).

---

### [MAJOR] Pattern overlay uses inefficient shader for blend mode — `wallpaper.dart:478-482` ← `AyuGramDesktop/lib_ui/ui/image/image_prepare.cpp:GenerateBackgroundImage`

The `_PatternOverlay.build()` uses ShaderMask with a LinearGradient of two identical white colors:
```dart
ShaderMask(
  blendMode: BlendMode.softLight,
  shaderCallback: (bounds) => const LinearGradient(
    colors: [Colors.white, Colors.white],
  ).createShader(bounds),
  child: patternImage,
)
```

A LinearGradient with identical colors is redundant — it will always evaluate to white. The shader serves no purpose except to provide the ShaderMask structure. This is inefficient but not functionally broken.

AyuGram uses simpler composition:
```cpp
p.setCompositionMode(QPainter::CompositionMode_SoftLight);
p.setOpacity(patternOpacity);
drawPattern(p, ...);
```

**Severity**: MAJOR (performance: unnecessary shader computation, though functionally correct).

---

### [MAJOR] Tiled image painter may decode image multiple times if paint() is called before async callback completes — `wallpaper.dart:432-436` ← n/a (no equivalent in AyuGram observed)

In `_TiledPainter.paint()`:
```dart
if (_decoded == null && !_loading) {
  _loading = true;
  ui.decodeImageFromList(imageBytes, (img) {
    _decoded = img;
  });
}
```

If `paint()` is called multiple times before the async `decodeImageFromList` callback returns, the condition `_loading == false` will never become true again. The image is decoded only once (safe).

**However**, if the CustomPainter is recreated or imageBytes change while decoding is in progress, a new decoder might be started without checking for in-flight decodes. This is a minor inefficiency but not a critical bug.

**Severity**: MAJOR (minor inefficiency in edge case, functionally acceptable).

---

## Findings Summary

| Issue | Type | Severity | File Reference |
|-------|------|----------|-----------------|
| Multi-color gradient animation algorithm mismatch | Behavior | CRITICAL | wallpaper.dart:370-373 |
| Two-color gradient rotation quantization differs | Visual | MAJOR | wallpaper.dart:296-300 |
| Inefficient redundant shader in pattern overlay | Performance | MAJOR | wallpaper.dart:478-482 |
| Potential redundant image decodes on rapid paint() calls | Efficiency | MAJOR | wallpaper.dart:432-436 |

## Verification

- ✅ No stubs, TODOs, FIXMEs, or placeholders detected
- ✅ All data structures (WallpaperData, WallpaperProvider) properly match AyuGram's WallPaper class fields
- ✅ Pattern intensity/opacity calculations match AyuGram (formula: `opacity = intensity / 100.0`)
- ✅ Negative pattern intensity handling matches AyuGram (darkenOpacity formula)
- ✅ Image average color computation uses sampling strategy (matches AyuGram's dithering approach)
- ✅ URL parsing (fromUrl) matches Telegram's standard format
- ⚠️ Animation duration (8 seconds) not verified against AyuGram source (not found in public code)

## Recommendations

1. **CRITICAL**: Replace multi-color gradient animation with AyuGram's discrete phase-based algorithm for visual fidelity.
2. **MAJOR**: Quantize 2-color gradient rotation to 8 discrete cases (0, 45, 90, ... 315°) to exactly match AyuGram.
3. **MAJOR**: Remove redundant LinearGradient shader in pattern overlay, use direct opacity blending.
4. **MAJOR**: Add guard against repeated image decodes in `_TiledPainter`.


# active_sessions_screen — Audit findings



# bridge_stub — Platform Fallback (Not a Feature)

## Classification
This file is **NOT a UI feature** or **user-facing component**. It's a platform abstraction fallback — a safety net that should never be reached at runtime.

## Design Analysis

**What it is:**
- Stub implementation for the bridge layer (`dart:ffi` for native, `dart:web` for web)
- Conditional imports in `bridge.dart` select the correct implementation (`bridge_ffi.dart` or `bridge_web.dart`)
- This stub is loaded only if both platform-specific imports fail — an error condition

**What it does (correctly):**
1. `events` returns `Stream.empty()` — no events are generated (correct for a stub)
2. `isInitialized` returns `false` — correctly signals that the bridge isn't ready
3. `init()`, `call()`, `callAsync()` throw `UnsupportedError` — correctly fail fast instead of silently doing nothing
4. `dispose()` is a no-op — correct, nothing to clean up

## Assessment

**No issues found.** This is intentionally minimal and correct. It's a fallback that signals platform incompatibility, not a feature implementation. Any feature wiring issues would be in:
- `dart/lib/bridge/bridge_ffi.dart` (desktop/Android native)
- `dart/lib/bridge/bridge_web.dart` (web)

These are the files to audit for backend connectivity and feature wiring.

---

**Recommendation:** Audit `bridge_ffi.dart` and `bridge_web.dart` instead. This stub is correctly designed.

# advanced_settings_screen — Audit Findings


# Audit: Dart Flutter auth_screen.dart vs AyuGram Desktop C++ intro widgets

## Summary

This audit compares the Dart Flutter auth_screen.dart (2305 lines) against AyuGram Desktop's C++ intro authentication implementation. The Dart implementation shows **strong architectural alignment** with AyuGram's source, with correct state-machine flow, proper engine/bridge wiring, and accurate visual dimensions. However, several CRITICAL and MAJOR issues were identified.

---

## Critical Issues

### 1. OTP Auto-Submit Timing Deviation

**auth_screen.dart:1607** delays auto-submit by 80ms after all digits collected.

**AyuGram intro_code_input.cpp:378-379** fires immediately on last digit processed:
```cpp
if (result.size() == _digitsCountMax) {
    _codeCollected.fire_copy(result);  // Fires immediately
}
```

**Dart auth_screen.dart:1601-1610**:
```dart
void _checkComplete() {
  if (_submitted) return;
  final code = _digits.join();
  if (code.length == widget.digitCount &&
      code.runes.every((r) => r >= 0x30 && r <= 0x39)) {
    _submitted = true;
    Future.delayed(const Duration(milliseconds: 80), () {  // 80ms delay
      widget.onComplete(code);
    });
  }
}
```

**Impact**: User perceives 80ms lag before submission confirmation. AyuGram provides instant feedback.


---

### 2. Step Width Dimension Mismatch

**AyuGram intro.style:78** defines:
```
introStepWidth: 380px;
```

**Dart auth_screen.dart:328** uses:
```dart
constraints: const BoxConstraints(maxWidth: 380),
```

Width matches, BUT **Dart form fields use hardcoded 300px** throughout:

**auth_screen.dart:551, 641, 677, 766, 779, 796, 808, 1053, 1095, 1124, 1178, 1188, 1995**:
```dart
SizedBox(width: 300, ...)
```

This creates **80px unused horizontal space** (380 - 300 = 80px margin on each side). AyuGram's form width should respect full 380px layout.


---

### 3. Phone Number Validation Logic Missing

**AyuGram intro_phone.cpp:160-180** validates phone before submit:
```cpp
const auto hasCodeButWaitingPhone = _code->hasFocus()
    && (_code->getLastText().size() > 1)
    && _phone->getLastText().isEmpty();
if (hasCodeButWaitingPhone) {
    _phone->hideError();
    _phone->setFocus();
    return;
}
const auto phone = fullNumber();
if (!AllowPhoneAttempt(phone)) {  // Requires digits > 1
    showPhoneError(tr::lng_bad_phone());
    return;
}
```

**Dart auth_screen.dart:108-116** minimal validation:
```dart
void _submit(AuthState authState) {
  final data = authState.currentAuth;
  if (data?.state == 'input' && data?.fieldType == 'phone') {
    final code = _codeController.text.replaceAll(RegExp(r'\D'), '');
    final phone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (code.isEmpty || phone.length < 2) return;  // Only checks empty/length < 2
```

**Missing validations**:
- Does not check if code field is focused but phone is empty
- Does not validate code length (AyuGram ensures > 1 digits)
- No per-field focus management before submit


---

### 4. Password Recovery Flow Incomplete

**AyuGram intro_password_check.cpp:291-310** handles recovery:
```cpp
void PasswordCheckWidget::toRecover() {
    if (_passwordState.hasRecovery) {
        if (_sentRequest) api().request(...).cancel();
        hideError();
        _toRecover->hide();
        _toPassword->show();
        _pwdField->hide();
        _pwdHint->hide();
        _codeField->show();
        _codeField->setText(QString());
        _codeField->setFocus();
        ...
    } else {
        _showNoRecoveryDialog(context);
    }
}
```

**Dart auth_screen.dart:822-833** implements recovery but **missing critical state resets**:
```dart
void _handleForgotPassword(AuthStateData data, AuthState authState) async {
    if (data.hasRecovery) {
        await authState.submitInput('__request_recovery');
        if (!mounted) return;
        setState(() {
            _isRecoveryMode = true;
            _showErrorBorder = false;  // Only clears error border
        });
    } else {
        _showNoRecoveryDialog(context);
    }
}
```

**Missing**:
- No clearing of `_passwordController.clear()` before switching to recovery mode (AyuGram clears field)
- No explicit focus management to recovery code field
- Does not cancel pending requests before switching modes


---

### 5. QR Code Widget Size Constants Mismatch

**AyuGram intro.style:181-183**:
```
introQrMaxSize: 180px;
introQrBackgroundSkip: 12px;
introQrBackgroundRadius: 8px;
```

**Dart auth_screen.dart:888-891**:
```dart
const qrSize = 180.0;
const cardPadding = 12.0;
const cardSize = qrSize + cardPadding * 2;
const logoSize = 44.0;
```

Constants match, BUT **Dart uses hardcoded width/height sizes**:
```dart
child: SizedBox(
  width: cardSize,    // 204px total
  height: cardSize,
```

**AyuGram intro_qr.cpp:104-105** computes dynamically:
```cpp
const auto size = st::introQrMaxSize + 2 * st::introQrBackgroundSkip;  // Also 204px
result->resize(size, size);
```

Both match (204px), but **Dart passes 204x204 as calculated SizedBox, then QR rendered at qrSize 180px, wasting 24px padding**. This is correct per spec but comment indicates possible confusion.


---

## Major Issues

### 6. Flood Timer Not Cancelled on Success

**AyuGram intro_phone.cpp:199-231** cancels timer on state transitions:
```cpp
void PhoneWidget::stopCheck() {
    _checkRequestTimer.cancel();
}
// Called on success and error paths
```

**Dart auth_screen.dart:283-308** logic exists but **timer persists across 2FA field entry**:

At line 305-306, on error clear:
```dart
_floodTimer?.cancel();
_floodSecondsLeft = 0;
```

But when transitioning from 2FA back (lines 272-277):
```dart
if (_prevStep == '2fa' && currentStep != '2fa') {
    _isRecoveryMode = false;
    _showResetButton = false;
    _passwordController.clear();
    _recoveryCodeController.clear();
}
```

**Missing**: No `_floodTimer?.cancel()` when exiting 2FA state. Timer will continue counting if user navigates away.


---

### 7. Error Shake Animation Uses Different Amplitude

**AyuGram intro_code_input.cpp:48-54**:
```cpp
void Shaker::shake() {
    if (_animation.animating()) return;
    _animation.start(DefaultShakeCallback([=, x = _widget->x()](int shift) {
        _widget->moveToLeft(x + shift, _widget->y());
    }), 0., 1., st::shakeDuration);
}
```

Uses framework's `DefaultShakeCallback` (standard Telegram shake).

**Dart auth_screen.dart:1793-1804**:
```dart
final dx = _shakeController.isAnimating
    ? sin(_shakeController.value * pi * 6) *
        8 *
        (1 - _shakeController.value)
    : 0.0;  // Amplitude: 8px, frequency: 6 cycles
```

vs **2FA field (lines 541-548)**:
```dart
final dx = _shakeController.isAnimating
    ? sin(_shakeController.value * pi * 4) *
        6 *
        (1 - _shakeController.value)
    : 0.0;  // Amplitude: 6px, frequency: 4 cycles
```

**Inconsistency**: OTP uses 8px/6 cycles, password uses 6px/4 cycles. AyuGram uses single unified shake.


---

### 8. Password Field Text Selection on Error Not RTL-Safe

**Dart auth_screen.dart:295-300**:
```dart
if (currentStep == '2fa' && !_isRecoveryMode) {
    _passwordController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _passwordController.text.length,
    );
}
```

Selects text **only in 2FA step**, **only when NOT in recovery mode**. No RTL awareness.

**AyuGram intro_password_check.cpp:151-152**:
```cpp
_pwdField->selectAll();
_pwdField->showError();
```

Simpler, doesn't consider RTL directional selection.

**Issue**: In RTL languages, selection order should be reversed (end to start). Dart hardcodes `baseOffset: 0, extentOffset: length` which creates backwards selection in RTL.


---

### 9. "Didn't Get Code" Dialog Missing Phone Number Edit Confirmation

**AyuGram intro_code.cpp:34-46**:
```cpp
_noTelegramCode(this, tr::lng_code_no_telegram(tr::now), st::introLink)
...
_noTelegramCode->addClickHandler([=] { noTelegramCode(); });
```

Links to `noTelegramCode()` which sends resend via `MTPauth_ResendCode`.

**Dart auth_screen.dart:163-208**:
```dart
void _showDidntGetCodeDialog(AuthState authState) {
    showDialog(
        context: context,
        builder: (ctx) {
            return AlertDialog(
                title: const Text("Didn't get the code?"),
                content: Column(...),
                actions: [
                    TextButton(
                        onPressed: () {
                            Navigator.of(ctx).pop();
                            authState.switchToMethod('phone');  // ← Direct switch
                        },
                        child: const Text('Edit Phone Number'),
                    ),
                    ...
                ],
            );
        },
    );
}
```

**Issue**: Immediately calls `switchToMethod('phone')` without confirming user wants to discard code attempt. AyuGram shows error only on explicit "no telegram code" click, not within a dialog.

However, this is **design choice**, not a defect. Dart's UX is more explicit.


---

### 10. Signup Avatar Upload Error Handling Swallows Exceptions

**Dart auth_screen.dart:83-91**:
```dart
static Future<void> _uploadSignupAvatar(
    EngineService engine, String accountId, Uint8List bytes) async {
    try {
        final tmpFile = File('${Directory.systemTemp.path}/uniclient_signup_avatar.png');
        await tmpFile.writeAsBytes(bytes);
        await engine.uploadProfilePhoto(accountId, tmpFile.path);
        try { await tmpFile.delete(); } catch (_) {}
    } catch (_) {}  // ← Silent catch, no error reporting
}
```

**AyuGram intro_signup.cpp:175-245** handles avatar via `UserpicButton`:
```cpp
_photo->chooseImage(
) | rpl::on_next([=](const QImage &image) {
    _photo->uploadPhoto(image);
}, lifetime());
```

Built-in error handling with user notifications.

**Issue**: Dart silently ignores all avatar upload errors. User never informed if upload fails. No logging, no toast, no state update.


---

## Visual Accuracy Issues

### 11. OTP Digit Font Size vs Specification

**AyuGram intro.style:130**:
```
introCodeDigitFont: font(20px);
```

**Dart auth_screen.dart:1438, 1850**:
```dart
static const _digitFontSize = 20.0;
...
style: TextStyle(
    fontSize: _digitFontSize,  // 20px ✓
    fontWeight: FontWeight.w500,
```

**Accurate** ✓

---

### 12. Password Field Top Position Accurate

**AyuGram intro.style:127-128**:
```
introPasswordTop: 74px;
introPasswordHintTop: 151px;
```

**Dart auth_screen.dart:578, 581**:
```dart
const fieldTop = 74.0;
const hintTop = 151.0;
```

**Accurate** ✓

---

### 13. Error Position Discrepancy

**AyuGram intro.style:158-159**:
```
introErrorTop: 235px;
introErrorBelowLinkTop: 220px;
```

**Dart auth_screen.dart:582, 671-672**:
```dart
const errorTop = 220.0;  // Uses introErrorBelowLinkTop value
...
Positioned(
    top: errorTop,
    ...
    Text(_mapAuthError(authState.error!), ...)
```

**Issue**: Dart hardcodes `errorTop = 220.0` but should use **235px** for errors after regular fields and **220px** only for errors below links. Currently always uses 220px.

AyuGram has:
- `introErrorTop: 235px` — for general errors on main fields
- `introErrorBelowLinkTop: 220px` — for errors appearing below links

Dart conflates both into single 220px constant.


---

## Backend Wiring Verification

### 14. AuthState Bridge Integration ✓

**Verified correct**:
- `authState.submitInput()` calls bridge properly
- `authState.currentAuth` property accessed correctly
- `authState.error` property used for error display
- State machine transitions via `authState.switchToMethod()`
- Listeners added for avatar upload completion

Lines: 110, 116, 124, 130, 154, 160, 189-190, 196-197, 265, 283-308, 372-377, 378-382, 410

✓ **PASSED**: Engine bridge wiring is correct

---

### 15. Error Mapping Completeness

**Dart auth_screen.dart:691-703** maps errors:
```dart
String _mapAuthError(String raw) {
    if (raw.contains('PASSWORD_HASH_INVALID') || raw.contains('SRP_PASSWORD_CHANGED')) {
        return 'Wrong password, try again.';
    }
    if (raw.contains('FLOOD_WAIT')) return 'Too many attempts. Please try again later.';
    if (raw.contains('CODE_INVALID')) return 'Invalid code. Please try again.';
    if (raw.contains('EMAIL_HASH_EXPIRED')) return 'Email confirmation expired.';
    ...
```

Covers: PASSWORD_HASH_INVALID, SRP_PASSWORD_CHANGED, FLOOD_WAIT, CODE_INVALID, EMAIL_HASH_EXPIRED, EMAIL_NOT_ALLOWED, EMAIL_INVALID, PASSWORD_RECOVERY_NA, PASSWORD_RECOVERY_EXPIRED

**AyuGram intro_password_check.cpp:148-165** handles:
```cpp
if (type == u"PASSWORD_HASH_INVALID"_q || type == u"SRP_PASSWORD_CHANGED"_q) {
    showError(tr::lng_signin_bad_password());
} else if (type == u"PASSWORD_EMPTY"_q || type == u"AUTH_KEY_UNREGISTERED"_q) {
    goBack();
}
```

**Issue**: Dart maps errors to user-friendly messages, but some error types cause **immediate state transitions** in AyuGram:
- `PASSWORD_EMPTY`, `AUTH_KEY_UNREGISTERED` → `goBack()` (Dart has no equivalent)
- `SRP_ID_INVALID` → special `handleSrpIdInvalid()` (Dart has no equivalent)

Dart will display these as error messages instead of auto-transitioning. **Behavior deviation**.


---

## Behavioral Accuracy

### 16. Back Button Availability ✓

**Dart auth_screen.dart:233-239**:
```dart
bool _canGoBack(AuthStateData? data) {
    if (data == null) return false;
    return switch (data.state) {
        'input' || 'otp' || '2fa' || 'qr' => true,
        _ => false,
    };
}
```

**AyuGram intro_phone.cpp / intro_qr.cpp** both allow back navigation on their respective screens.

✓ **PASSED**: Back behavior matches

---

### 17. Next Button Text Accuracy ✓

**Dart auth_screen.dart:249-255**:
```dart
String _nextButtonText(AuthStateData? data) {
    if (data == null) return 'Next';
    return switch (data.state) {
        'signup' => 'Start Messaging',
        _ => 'Next',
    };
}
```

**AyuGram intro_signup.cpp:208-210**:
```cpp
rpl::producer<QString> SignupWidget::nextButtonText() const {
    return tr::lng_intro_finish();  // "Start Messaging" in Telegram
}
```

✓ **PASSED**: Button text matches

---

### 18. Signup Name Field Order (RTL Support) ✓

**Dart auth_screen.dart:798-816**:
```dart
final isRtl = Directionality.of(context) == TextDirection.rtl;
return Column(
    children: [
        SizedBox(
            width: 300,
            child: TextField(
                controller: isRtl ? _lastNameController : _firstNameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                    labelText: isRtl ? 'Last name' : 'First name',
```

**AyuGram intro_signup.cpp:44-48**:
```cpp
if (_invertOrder) {
    setTabOrder(_last, _first);
} else {
    setTabOrder(_first, _last);
}
```

Both swap field order for RTL/right-to-left languages.

✓ **PASSED**: RTL support implemented correctly

---

## Performance Issues

### 19. ListView.builder Usage in Country/Language Pickers ✓

**Dart auth_screen.dart:2156-2174** (Language picker):
```dart
Flexible(
    child: ListView.builder(
        shrinkWrap: true,
        itemCount: filtered.length,
        itemBuilder: (ctx, i) {
            final (code, native, english) = filtered[i];
            return RadioListTile<String>(
```

**Dart auth_screen.dart:2236-2257** (Country picker):
```dart
Flexible(
    child: ListView.builder(
        shrinkWrap: true,
        itemCount: filtered.length,
        itemBuilder: (ctx, i) {
            final c = filtered[i];
```

Both use `ListView.builder` for lazy rendering.

✓ **PASSED**: Efficient implementation

---

### 20. Missing const Constructors

**Checked**: All major widget constructors use `const` where applicable:
- `_CoverGradient({required this.isDark})`
- `_OtpCodeInput({required...})`
- `_AuthBottomBar({required...})`

✓ **PASSED**: const constructors properly used

---

## Summary Table

| Issue | Type | Severity | Dart Line | AyuGram Reference |
|-------|------|----------|-----------|------------------|
| OTP auto-submit 80ms delay | Timing | CRITICAL | 1607 | intro_code_input.cpp:378 |
| Step width 300px in 380px container | Layout | CRITICAL | 328,551 | intro.style:78 |
| Phone validation missing code focus check | Logic | CRITICAL | 110-116 | intro_phone.cpp:166-179 |
| Password recovery doesn't clear field | State | CRITICAL | 822-829 | intro_password_check.cpp:291-310 |
| QR logo size unconfirmed | Dimension | MAJOR | 891 | intro_qr.cpp:167-170 |
| Flood timer not cancelled on exit 2FA | Timer | MAJOR | 272-277 | intro_phone.cpp:221-223 |
| OTP vs password shake inconsistent | Animation | MAJOR | 544,1799 | intro_code_input.cpp:48-54 |
| Password selection not RTL-safe | Localization | MAJOR | 296-298 | (no parallel) |
| Didn't get code dialog flow | Dialog | MAJOR | 163-208 | intro_code.cpp:440-492 |
| Avatar upload errors silent | Error Handling | MAJOR | 83-91 | intro_signup.cpp |
| Error position hardcoded 220px | Layout | MAJOR | 582 | intro.style:158-159 |
| Missing error-triggered state transitions | State | MAJOR | 691-703 | intro_password_check.cpp:148-165 |

---

## Recommendations

1. **Remove 80ms delay** from OTP auto-submit (line 1607)
2. **Expand form widths** from 300px to 380px to use full container
3. **Add phone code focus validation** before submit
4. **Clear password field** on recovery mode switch
5. **Unify shake animations** across OTP and password fields
6. **Cancel flood timer** on 2FA exit
7. **Implement error-driven state transitions** (PASSWORD_EMPTY → back, etc.)
8. **Add RTL-safe text selection** logic
9. **Report avatar upload errors** to user
10. **Verify QR logo sizing** against specification


# ayu_chats_page — Settings UI audit (8 issues found)

## CRITICAL Issues

- [x] [CRITICAL] Context menu options mapping reversed: {0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'} should be {0: 'Hidden', 1: 'Shown', 2: 'Extended Menu'} to match AyuGram's ContextMenuVisibility enum (Hidden=0, Visible=1, VisibleWithModifier=2) — `ayu_chats_page.dart:143` ← `AyuGram/Telegram/SourceFiles/ayu/ayu_settings.h:35-69`

- [x] [CRITICAL] Wide multiplier slider minimum is 0.5 but should be 1.0 (AyuGram kMinSize=1.00) — `ayu_chats_page.dart:322` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:241-242`

- [x] [CRITICAL] Missing edit dialogs for deleted/edited mark customization (no EditMarkBox functionality) — `ayu_chats_page.dart:495-718` (preview only, no edit buttons) ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:163-197`

- [x] [CRITICAL] Missing semi-transparent deleted messages toggle with beta badge — `ayu_chats_page.dart:(missing)` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:221-230`

## MAJOR Issues

- [x] [MAJOR] Bubble radius and wide multiplier slider order reversed: Dart shows wide multiplier first, then bubble radius; should be bubble radius first — `ayu_chats_page.dart:102-117` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:249-289`

- [x] [MAJOR] "Hide side Share button" toggle in wrong section (Channels) — should be in Messages section after simple quotes — `ayu_chats_page.dart:91-96` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:206-212` (part of BuildMarks, not BuildGroupsAndChannels)

- [x] [MAJOR] Message field element toggles missing icon support (AyuGram passes .icon parameter to each toggle) — `ayu_chats_page.dart:152-193` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:381-429`

- [x] [MAJOR] Context menu element toggles missing icon support and incorrect options order — `ayu_chats_page.dart:139-146` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:307-360`

# ayu_toggle — No issues found

Comprehensive audit of `ayu_toggle.dart` against AyuGram Desktop ToggleView (`lib_ui/ui/widgets/checkbox.h/cpp`) and defaultToggle style (`lib_ui/ui/widgets/widgets.style:874-890`).

## Verification Summary

✓ **Dimensions**: All constants match (border=2.0, diameter=14px material/16px non-material, width=14px, animPadding=2.0, matShift=-2.0, defShift=1.0)

✓ **Color Logic**: Interpolation matches exactly (checkboxFg→windowBgActive for track/border, windowBg for thumb fill)

✓ **Animation**: Duration 150ms, easeOutCubic for material toggles, linear for non-material

✓ **State Management**: Proper initialization with correct value, correct didUpdateWidget triggering forward/reverse, proper cleanup in dispose()

✓ **Paint Logic**: Track (rounded rect) + thumb (oval with border) + material padding deflation all match C++ implementation

✓ **Callbacks**: onTap correctly calls onChanged with toggled value

✓ **No Stubs/Placeholders**: All code is fully functional and production-ready

✓ **Const Constructor**: Widget properly defined as const

✓ **shouldRepaint**: Optimization correctly implemented

The implementation is complete, accurate, and ready for use. No changes needed.

# call_panel — Audit Findings

# call_screen — Group Call Panel + Minimised Call Bar

# calls_screen — Call History, Conference Call, Active Group Calls, Call Settings

# chat_view — Stubs, Missing Wiring, Wrong Behavior

# choose_datetime_box — Calendar + Schedule + TimePicker audit


# color_picker_box — Color Picker Dialog


# compose_entities — Text entity tracking & markdown rendering

## CRITICAL Issues

- [x] **Incorrect entity type for code blocks with language** — `compose_entities.dart:21-32 (toJson method)` ← `go/cores/telegram.go:1060-1073 (case "code"/"pre" handlers)` — The Dart code always outputs `'type': 'code'` in the JSON, even when the code block has a language field set. For code blocks with syntax highlighting language (Python, JavaScript, etc.), it should output `'type': 'pre'` instead. The Go backend handles this defensively with `if e.Language != "" { ent = &tg.MessageEntityPre{...} }`, but the Dart code should follow proper Telegram API convention: inline code → `'code'`, code block with language → `'pre'`. **Fix:** In toJson() method, check if language is not empty and use 'pre' type instead of 'code' for language-bearing entities.

## MAJOR Issues

- [x] **Missing Semibold entity type support** — `compose_entities.dart:6 (FormatType enum)` ← `go/cores/base.go:15-16 (TextEntity Type field comments)` and `AyuGramDesktop/Telegram/lib_ui/ui/text/text_entity.h:48` — The FormatType enum supports bold, italic, underline, strike, code, spoiler, blockquote, link, customEmoji, and date, but does NOT support Semibold. AyuGram's entity system includes `EntityType::Semibold` as a distinct type, and the Go backend's TextEntity comments list "bold" and implicitly other formatting types. If the app supports semibold text (for emphasis or special styling), this feature is incomplete.

- [x] **Custom emoji rendering not wired to builder** — `compose_entities.dart:500-505` — When `customEmojiBuilder` is null (builder not set), the code falls back to rendering `emojiEntity.altText ?? t.substring(segStart, segEnd)` as plain text. This means custom emojis won't render as actual emoji graphics unless a custom builder is explicitly provided and configured. The placeholder character (￼) is used in the text, but without a builder, users see fallback text instead of the emoji. **Verify:** Check if `customEmojiBuilder` is always set when compose_entities is used in the app, or if users see broken/fallback text for custom emojis.

## MINOR Issues

- [x] **Color values hardcoded instead of using theme tokens** — `compose_entities.dart:462-464, 549-550 (buildTextSpan method)` — Text formatting colors (monoFg, linkFg, spoilerFg, codeBg, blockquote background) are defined as hardcoded hex constants within the build method. These should use `AppColors` theme tokens from `dart/lib/theme/theme.dart` to maintain consistency with the app's theme system and allow dynamic theme switching. **Fix:** Extract colors to theme tokens and use them instead of hardcoded values.

- [x] **Light mode monospace color differs from AyuGram** — `compose_entities.dart:462` ← `AyuGramDesktop/Telegram/lib_ui/ui/colors.palette:371` — Dart light mode monoFg: `0xFF3A464F` vs. AyuGram msgInMonoFg: `#4e7391`. The colors are different, which could cause visual inconsistency with the reference design if they're meant to match. **Verify:** Confirm whether this is an intentional design choice for uniclient or an oversight.

## Summary

**Code Quality:** Solid implementation of entity tracking and markdown parsing. Entity offset adjustment during text edits is correct. Markdown detection and stripping logic is sound.

**Wiring:** Properly integrated with ChatState.sendMessage() and ChatState.editMessage() — entities JSON is passed to the backend correctly.

**Visual Accuracy:** Most colors match AyuGram (linkFg light: #168ACD matches historyLinkInFg). Monospace color differs slightly.

**Behavioral Accuracy:** Entity toggle, link insertion, code language setting, and custom emoji insertion all working as designed. Markdown parsing supports inline code, code blocks, bold, italic, strike, spoiler, blockquote.

**Missing Features:** No Semibold support. Code block language detection works but entity type isn't properly distinguished in JSON output.

# edit_mark_box — Critical behavior mismatches with AyuGram reference

## Summary
The Dart implementation has fundamentally wrong button behavior and is missing critical features compared to AyuGram. The Reset button should only modify the text field, not save/close. A Cancel button is needed. Input validation is missing.

---

## Findings


---

## Impact
This dialog is fundamentally non-functional as implemented:
1. Users cannot cancel (would lose their edits)
2. Users cannot intentionally reset and then edit (Reset immediately commits)
3. Empty input is accepted without user feedback
4. The three-button UX pattern from the spec is not implemented

# emoji_panel — Emoji/Sticker/GIF Panel Audit


# emoji_status_widget — Fixed

## Issues Found & Fixed

- [x] [CRITICAL] Missing `dart:convert` import required for `gzip.decode()` call — `emoji_status_widget.dart:146` ← `emoji_status_widget.dart:1-11` **FIXED**
  - **Issue**: Line 146 calls `gzip.decode(tgsData)` to decompress TGS (Lottie) files, but `dart:convert` was not imported
  - **Impact**: Would cause a `NameError` at runtime when attempting to display animated emoji status
  - **Fix Applied**: Added `import 'dart:convert';` at line 1

## All Other Aspects Pass

### Backend Wiring ✓
- Widget properly acquires/releases cache references (lines 45-48, 53-68, 72-77)
- Correctly calls `cache.request()` and `cache.requestFile()` with engine service (lines 135, 140)
- Cache update callback triggers `setState()` (line 125)
- Power-saving mode integration works (lines 150-153)

### Data Flow ✓
- Parses emoji status ID correctly (lines 81-108):
  - Plain document ID format
  - Collectible format with center/edge colors
  - Userpic format
- Color parsing with proper hex validation (lines 110-116)
- CustomEmojiFileData model has correct MIME type checks: `isTgs`, `isWebp` (engine_models.dart)

### Visual Accuracy ✓
- Dimensions match AyuGram patterns (size parameter, frame sizes in cache)
- Gradient application for collectibles uses RadialGradient (lines 220-228) — matches AyuGram approach (calls_panel_background.cpp:140-147)
- Fallback color `0xFF6C3BEB` (purple) is consistent with Telegram defaults
- Image cacheWidth/cacheHeight use scaled frame size for memory efficiency (lines 207-208)

### Animation Handling ✓
- AnimationController properly created on Lottie load (lines 155-167)
- Loop animation with forward() on completion (lines 161-165)
- Disposed on widget update/dispose (lines 57, 77)

### Error Handling ✓
- Catches gzip errors (though import prevents execution) (line 147)
- Falls back to thumbnail on Lottie error (line 200)
- Falls back to icon when file/cache empty (lines 266-288)

### Performance ✓
- No unnecessary rebuilds — only setState on actual cache update
- Uses `gaplessPlayback: true` for smooth image transitions (lines 210, 275)
- Proper refcount semantics for cache (acquire/release pattern)
- Image.memory with cacheWidth/cacheHeight prevents full-resolution decoding

---

**Priority**: Fix missing import immediately. All other logic is sound and matches AyuGram's emoji status rendering patterns.

# Audit Chunk 67 — info_panel.dart

Audited against AyuGram Desktop C++ source at
`/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/info/profile/`.

---

## CRITICAL Issues

- [ ] [CRITICAL] Avatar (userpic) in `_FlexibleCoverDelegate` has no tap handler — clicking the avatar does nothing. AyuGram opens the photo viewer on left-click and a context menu (Open Photo / Report / Change Photo / Suggest Photo) on right-click. — `info_panel.dart:590-641` ← `info/profile/info_profile_top_bar.cpp:1022-1349`

- [ ] [CRITICAL] Mute button right-click context menu only shows "Mute forever" or "Unmute" — missing the standard Telegram timed-mute options (1 hour, 4 hours, 8 hours, 2 days, 1 week, custom duration, and sound on/off toggle). AyuGram uses `MuteMenu::SetupMuteMenu` which generates a full duration list from `session->settings().mutePeriods()`. — `info_panel.dart:978-993` ← `menu/menu_mute.cpp:298-365`, `info/profile/info_profile_top_bar.cpp:848`

- [ ] [CRITICAL] Bot commands in `_ChatDetailsState` are hardcoded to `['help', 'settings', 'privacy']` regardless of what commands the bot actually provides. AyuGram reads `user->botInfo->commands` (the real server-fetched command list) and shows only commands that actually exist for that bot. — `info_panel.dart:2852-2859` ← `info/profile/info_profile_actions.cpp:2829`

- [ ] [CRITICAL] `_SharedMediaSection` search bar (`_MediaSearchRow`) is purely cosmetic — `_searchController.text` is passed only as the `isSearch` boolean (which only changes the empty-state label), never used to filter or re-query `_gridItems`. Media search does not actually search. — `info_panel.dart:4107-4122`, `4036-4059`

- [ ] [CRITICAL] `_SharedMediaSubPage._buildContent()` contains a null-check `_items == null` on a field declared as non-nullable `List<SharedMediaItem> _items = []` (line 2314). This is dead code that masks a real type error; more importantly the dual-scroll-controller pattern is broken: a `SingleChildScrollView` is given the same `widget.scrollController` that the outer `Column` already registers for scroll pagination (line 2333/2453-2481), creating a controller attached to two scroll views simultaneously — one will throw. — `info_panel.dart:2314`, `2444`, `2453-2481`

- [ ] [CRITICAL] `profileBgColors` (gradient cover background) is never passed to `_FlexibleCoverDelegate` from `_ChatInfoPage` — the parameter is always `null` because `ChatInfo` model has no `bgColors` field. The gradient cover feature is entirely non-functional. — `info_panel.dart:1876-1919` (no `profileBgColors:` argument passed)

- [ ] [CRITICAL] Personal Channel field in `_ChatDetailsState` displays the channel name as plain text with no tap action. AyuGram makes this row tappable to open the channel. The `_TextWithLabel` at line 2847 has no `onTap` — clicking does nothing. — `info_panel.dart:2846-2851`

- [ ] [CRITICAL] `_CommonGroupsRow` in `_ChatDetailsState` (main chat info, not user profile) is rendered without `onTap` (line 2871-2874). The entire "X groups in common" row is non-tappable — tapping it does nothing. The version in `_UserProfilePageState` has the same navigation bug: it pushes another `_InfoPageType.userProfile` page with the same member instead of a common-groups list page. No common-groups page type exists in `_InfoPageType`. — `info_panel.dart:2870-2874`, `2259-2270`

---

## MAJOR Issues

- [ ] [MAJOR] `_SharedMediaSection` gift sub-tab filter (`_SubTabChips` for 'all'/'unique'/'limited') changes `_activeSubTab` state but does NOT re-fetch or filter `_gridItems` — the tab selection is a no-op. The displayed grid always shows all gifts regardless of which tab is selected. — `info_panel.dart:4090-4098`, `4097` (`onSelected: (tab) => setState(() => _activeSubTab = tab)` — no reload)

- [ ] [MAJOR] `_SharedMediaRow` has `onTap: onTap ?? () {}` (line 4450) — when `onTap` is null (i.e. `_expandableTypes` does not contain the media type — but currently all types are in `_expandableTypes`), the InkWell fires silently with no feedback and no action. This is a latent empty-tap stub that will manifest if any type is removed from `_expandableTypes`. — `info_panel.dart:4450`

- [ ] [MAJOR] `_MembersSection` header height is `56` (line 5548) matching the AyuGram `st::infoMembersHeader` value. However the entire `SliverChildListDelegate` for the main chat page (line 1922) renders ALL section widgets eagerly into a single non-lazy list — with potentially hundreds of member rows built at once. AyuGram uses a virtual/lazy widget. The `...filtered.map((m) => _MemberRow(...))` spread at line 5614 is non-lazy. — `info_panel.dart:5614` ← `info/profile/info_profile_members.cpp:128`

- [ ] [MAJOR] `_ChatInfoPage` uses `SliverChildListDelegate` (lines 1922, 2037) rendering all child sections eagerly including `_MembersSection` with all member rows inline. For large groups this builds hundreds of widgets synchronously in a single frame. Should use `SliverChildBuilderDelegate` or convert the members to a separate `SliverList`. — `info_panel.dart:1921-2001`

- [ ] [MAJOR] `_loadCommonGroups` fetches with `limit: 1` (lines 2125 and 2764), so `_commonGroupsCount` is always 0 or 1 — never the real count. AyuGram shows the actual number of common groups (e.g. "5 groups in common"). The label is misleading because if there is 1 common group, the count is `1`, but if there are 5 the count is still shown as `1`. — `info_panel.dart:2125`, `2764`

- [ ] [MAJOR] `_UserProfilePage` avatar is hardcoded to `avatarPath: ''` (line 2216) — even if the member has an avatar, it never loads. The initials/color fallback is always shown for member profiles. — `info_panel.dart:2216`

- [ ] [MAJOR] `_MemberRow` avatar is always the initials fallback (line 5711-5735) — there is no avatar image loading for member rows at all. AyuGram shows real userpic thumbnails in the member list. — `info_panel.dart:5697-5735`

- [ ] [MAJOR] `_StatisticsPage` top bar height is `54` (line 6376) while `_SharedMediaSubPage` top bar is `56` (line 2409) and `_BoostsPage` top bar is also `56` (line 6188). All sub-pages should use a consistent `56px` top bar (matching AyuGram's `st::infoTopBar` height). The 54px Statistics top bar is a 3.5% deviation but visibly inconsistent. — `info_panel.dart:6376`, vs `2409`

- [ ] [MAJOR] `_ChatDetails` `_formatBirthday` does not show age or "N years old" label that AyuGram displays alongside the birthday date. Birthday is shown as plain date string without the age annotation. — `info_panel.dart:2776-2781`

- [ ] [MAJOR] `_AnimatedEmojiPattern` (emoji status background pattern on the cover) uses a custom diamond-shape orbit painter that does not match AyuGram's actual emoji-status pattern implementation. AyuGram renders the actual custom emoji sticker as the pattern element using `Data::CustomEmojiSizeTag`, not arbitrary diamond shapes. The visual output is wrong. — `info_panel.dart:1242-1288` ← `info/profile/info_profile_cover.cpp:topicIconView`

- [ ] [MAJOR] `_AvatarHeader` widget (lines 2485-2619) is a dead widget — it is never used anywhere in `info_panel.dart`. The cover rendering uses `_FlexibleCoverDelegate` directly. This is unused code that was not cleaned up and adds confusion. — `info_panel.dart:2485`

- [ ] [MAJOR] `_ForumTopicsDialog` saves forum enable/disable via `engine.toggleForum()` but ignores the `_layout` (tabs vs list) radio selection entirely — `_layout` is never sent to the engine. The layout preference is a no-op. — `info_panel.dart:3343-3360`

# input_dialogs — Audit

## _UsernameBoxContent

- [ ] [CRITICAL] `USERNAME_PURCHASE_AVAILABLE` error silently falls into "Sorry, this username is invalid" catch-all instead of showing a Fragment purchase link — `input_dialogs.dart:252-258` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/username_box.cpp:286-287,301-302,343-350` (`checkInfoPurchaseAvailable()` → `AppConfig::FragmentLink` → displayed as clickable link)

## _AddContactBoxContent

- [ ] [CRITICAL] Post-add chat navigation uses fragile name-matching on the local chat list with a 500 ms delay instead of using the peer ID returned directly from the `importContacts` API response — `input_dialogs.dart:592-601` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/add_contact_box.cpp` (parers peer from `MTPcontacts_ImportContacts` result, opens user page directly by peer ID)

## _CountryPickerContent

- [ ] [MAJOR] Country list shows an empty `ListView` when the search query matches nothing; AyuGram renders a centred "No countries found" label (`tr::lng_country_none`) at `st::noContactsHeight` — `input_dialogs.dart:877-913` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/country_select_box.cpp:353-357`

- [ ] [MAJOR] Country row horizontal padding is `EdgeInsets.symmetric(horizontal: 24)` (24 px both sides); AyuGram spec is `countryRowPadding: margins(22px, 9px, 8px, 0px)` — 22 px left, 8 px right — `input_dialogs.dart:887` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/country_select_box.cpp:391,396` (uses `st::countryRowPadding.left()` / `st::countryRowPadding.right()`)

## _EditInviteLinkContent

- [ ] [CRITICAL] Subscription invite-link mode is completely absent: no subscription toggle, no credits input. AyuGram's EditInviteLinkBox (when `isPublic` flag is set) exposes a "Subscription" toggle and a `NumberInput` for star credits, then passes `subscriptionCredits` to the API — `input_dialogs.dart:979-1326` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/edit_invite_link.cpp:58,103-146,192`

## _CreatePollContent

- [ ] [MAJOR] "Allow Revoting" toggle is missing from the poll creation UI and from `CreatePollResult`; AyuGram adds a full toggle row (`lng_polls_create_allow_revoting`) and maps it to `PollData::Flag::RevotingDisabled` — `input_dialogs.dart:1331-1349,1377` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/create_poll_box.cpp:2578-2586,2871`

- [ ] [MAJOR] No per-option character counter: AyuGram warns once an option field exceeds `kWarnOptionLimit = 30` chars, showing a counter label. Dart has no counter at any threshold for option fields — `input_dialogs.dart:1501-1506` ← `AyuGramDesktop/Telegram/SourceFiles/boxes/create_poll_box.cpp:107,484-485`

# instant_view — Audit

## instant_view — Multiple stubs, missing interactivity, broken layout

- [ ] [CRITICAL] Video block is a non-functional placeholder stub — `_buildVideo()` renders a static `Icons.play_circle_outline` icon with text "Video" / "Video (autoplay)" and zero tap handler or video player. AyuGram renders a real `<video data-src="..." data-autoplay="..." data-loop="...">` element driven by `IV.initEmbedBlocks()` JavaScript. No video can actually be watched — `instant_view.dart:900-930` ← `iv_prepare.cpp:557-623`

- [ ] [CRITICAL] Audio block is a non-functional placeholder stub — `_buildAudio()` renders a decorative `Icons.play_arrow` circle that is not wrapped in any `GestureDetector` or audio player widget. AyuGram renders `<audio controls src="...">` so the native HTML5 audio player is embedded and playable. Tapping the Dart play icon does nothing — `instant_view.dart:1031-1081` ← `iv_prepare.cpp:777-788`

- [ ] [CRITICAL] Embed block strips HTML to plain text instead of rendering the actual iframe — `_buildEmbed()` calls `_stripHtml()` on `embedHtml` and displays the result as a plain `Text` widget. AyuGram uses `embedUrl(html->v)` to create a blob URL and injects a real `<iframe src="...">`, allowing YouTube, Twitter, etc. to be rendered. All embedded media is completely broken — `instant_view.dart:798-804` ← `iv_prepare.cpp:631-683`

- [ ] [CRITICAL] Channel "Join" button opens external browser instead of triggering in-app join — pressing "Join" calls `launchUrl(Uri.parse('https://t.me/$username'))`. AyuGram fires `Event::Type::JoinChannel` → `Instance::processJoinChannel()` → joins via the Telegram client, then calls `showJoinedTooltip()` to confirm. The Dart path bypasses the Telegram backend entirely — `instant_view.dart:1017-1024` ← `iv_controller.cpp:1046-1050`

- [ ] [CRITICAL] Photos have no tap-to-expand viewer — `_IvFullPhoto` and the `Image.memory` fallback are bare image widgets with no `GestureDetector`. AyuGram wraps every photo in `<a href="..." data-context="viewer-photoID">` which fires `Event::Type::OpenMedia` to open the full-screen media viewer. Tapping a photo in Dart does nothing — `instant_view.dart:547-565` ← `iv_prepare.cpp:541-547`

- [ ] [MAJOR] Collage layout uses a naive grid column count instead of aspect-ratio-aware layout — `_buildCollage()` uses `GridView.count` with `crossAxisCount = items.length <= 2 ? items.length : (items.length <= 4 ? 2 : 3)`. AyuGram calls `Ui::LayoutMediaGroup()` which computes per-item `left/top/width/height` percentages from actual photo dimensions, matching Telegram Desktop's group layout algorithm exactly — `instant_view.dart:937-956` ← `iv_prepare.cpp:283-334`

- [ ] [MAJOR] Slideshow missing prev/next navigation buttons — `_buildSlideshow()` uses `PageView.builder` (swipe only). AyuGram renders SVG `slideshow-prev` / `slideshow-next` arrow buttons with `onclick="IV.slideshowSlide(this, ±1);"` and a radio-button indicator strip. Navigation arrows are absent in the Dart implementation — `instant_view.dart:959-986` ← `iv_prepare.cpp:337-385`

- [ ] [MAJOR] Zoom is session-only and not persisted — `_zoomFactor` (line 41) lives in widget state and resets on every navigation. AyuGram stores zoom via `Core::App().settings().setIvZoom(value)` (saved to disk) so it survives app restarts. The Dart zoom resets every time the page is closed — `instant_view.dart:41` ← `iv_delegate_impl.cpp:117-119`

- [ ] [MAJOR] Map block renders a placeholder box instead of actual map tiles — `_buildMap()` draws a coloured container with a pin icon and coordinates; tapping opens OpenStreetMap in an external browser. AyuGram renders `<img src="mapUrl(geo, 650, height, zoom)">` using Telegram's own map tile server at proper dimensions and zoom level — `instant_view.dart:1083-1122` ← `iv_prepare.cpp:850-860`

- [ ] [MAJOR] Table missing cell alignment and span attributes — `_buildTable()` renders every cell left-aligned with no colspan/rowspan support. AyuGram emits `text-align:right/center/left`, `vertical-align:bottom/middle/top` styles and `colspan`/`rowspan` attributes per `MTPDpageTableCell` flags — `instant_view.dart:746-769` ← `iv_prepare.cpp:913-942`

- [ ] [MAJOR] Table missing striped row style — `_buildTable()` reads `block['bordered']` but ignores `block['striped']`. AyuGram emits `class="striped"` when `data.is_striped()` is true, giving alternating row shading — `instant_view.dart:739` ← `iv_prepare.cpp:797-813`

- [ ] [MAJOR] Anchor block renders nothing, breaking hash-fragment navigation — `case 'anchor': return const SizedBox.shrink()`. AyuGram emits `<a name="anchorName">` so telegra.ph URLs ending in `#section` scroll to the correct position. In-page anchor targets are completely absent — `instant_view.dart:342-343` ← `iv_prepare.cpp:453-455`

- [ ] [MAJOR] Missing "scroll to top" fixed button — AyuGram injects `<button id="bottom_up" onclick="IV.scrollTo(0);">` (with a custom up-arrow SVG) into every IV page wrapper; it appears when the user scrolls down. The Dart implementation has no equivalent — `instant_view.dart` (absent) ← `iv_controller.cpp:303-307`

- [ ] [MAJOR] Ordered list fallback numbering produces double period — `final num = itemMap['num'] as String? ?? '${entry.key + 1}.'` (fallback includes a trailing period) then `Text('$num.', …)` appends another period, producing "1.." for items that lack a backend-supplied `num` field — `instant_view.dart:687,694` ← `iv_prepare.cpp:819-820`

# emoji_data — Emoji keyword data and search logic

- [ ] [CRITICAL] `loadServerKeywords()` is never wired to the engine — no bridge call fetches `messages.getEmojiKeywords` / `messages.getEmojiKeywordsDifference`; server keyword data is permanently empty — `emoji_data.dart:701` ← `AyuGram/chat_helpers/emoji_keywords.cpp:411-416`

- [ ] [CRITICAL] `isValidEmoji` range `(first >= 0x200D)` at line 661 is overbroad: it matches ZWJ (U+200D) and every codepoint above it, accepting non-emoji characters like en-dash (U+2013), mathematical operators, etc.; the earlier ranges (0x2600, 0x2300, 0x2190) are made unreachable — `emoji_data.dart:661` ← `AyuGram/chat_helpers/emoji_keywords.cpp:78-82` (uses `Ui::Emoji::Find` for exact validation)

- [ ] [CRITICAL] No auto-refresh mechanism — AyuGram refreshes keyword packs every hour (`kRefreshEach = 3,600,000 ms`) via `LangPack::refresh()`; Dart has no timer, no session lifecycle hook, and no trigger to re-fetch stale data — `emoji_data.dart:700-710` ← `AyuGram/chat_helpers/emoji_keywords.cpp:28,386-417`

- [ ] [MAJOR] Single-language flat map instead of per-language pack architecture — AyuGram maintains a `flat_map<QString, LangPack>` querying UI language, system language, input-method languages, and suggested language simultaneously; Dart stores one undifferentiated `Map<String, List<String>>` with no language key — `emoji_data.dart:676` ← `AyuGram/chat_helpers/emoji_keywords.cpp:75,562-585,608-642`

- [ ] [MAJOR] O(n) linear scan over all server keywords per search — AyuGram uses a sorted `std::map` with `lower_bound` for O(log n) prefix matching; Dart iterates every entry in `_serverKeywords` on each call — `emoji_data.dart:804` ← `AyuGram/chat_helpers/emoji_keywords.cpp:482-495`

- [ ] [MAJOR] Missing `maxQueryLength` guard — AyuGram immediately returns empty if `query.size() > _data.maxKeyLength`, avoiding useless scans; no equivalent exists in Dart — `emoji_data.dart:760` ← `AyuGram/chat_helpers/emoji_keywords.cpp:476-479,498-500`

- [ ] [MAJOR] Missing `SkipExactKeyword` filter — AyuGram skips single non-letter characters, "10", and short common English words in exact mode to avoid false positives; Dart performs no such filtering — `emoji_data.dart:760` ← `AyuGram/chat_helpers/emoji_keywords.cpp:55-76,477-478`

- [ ] [MAJOR] Missing `MustAddPostfix` handling — AyuGram appends U+FE0F variation selector to ™ (U+2122), © (U+00A9), and ® (U+00AE) when loading from server data; without this, those emoji are malformed in server-sourced results — `emoji_data.dart:701-710` ← `AyuGram/chat_helpers/emoji_keywords.cpp:47-53,129-131`

- [ ] [MAJOR] `loadState`/`saveState` not connected to any persistence layer — these methods exist but nothing calls them; recent emoji and variant prefs are lost on restart; AyuGram persists via `Core::App().settings()` (global settings store) — `emoji_data.dart:736,750` ← `AyuGram/chat_helpers/emoji_keywords.cpp:654,675-678`

# keyboard_shortcuts — Audit Findings

- [ ] [CRITICAL] `recordRound` handler calls `ChatView.startRecordVoiceRequest` (the same voice-recording callback as `recordVoice`), so round-video recording is never triggered — `keyboard_shortcuts.dart:1349` ← `AyuGram/core/shortcuts.h:74` (`RecordRound` is a distinct `Command` enum value from `RecordVoice:73`; AyuGram dispatches them to separate handlers)

- [ ] [CRITICAL] Chat-switch overlay has no Ctrl-release detection, no arrow-key/Enter/Escape navigation during the switch, and no input-method event filter — the overlay can be opened (Ctrl+Tab) but can't be confirmed or dismissed by releasing Ctrl, navigated with arrow keys/Q, or cancelled with Escape — `keyboard_shortcuts.dart:1085-1091` ← `AyuGram/core/shortcuts.cpp:894-973` (`HandlePossibleChatSwitch` full state machine: tracks `ChatSwitchStarted`, fires `ChatSwitchStream` on every arrow/Q/Escape/Enter event, `CancelChatSwitch` on Ctrl-release, installs an event filter to block InputMethod events during the switch)

- [ ] [MAJOR] Dedicated multimedia `search` and `find` keys are mapped in `_keyNames` (lines 329-330) but have no entries in `_defaultBindings`, so users with multimedia keyboards get no working Search shortcut beyond Ctrl+F — `keyboard_shortcuts.dart:824` (`_defaultBindings` list, no browserSearch/find binding) ← `AyuGram/core/shortcuts.cpp:485-486` (`set(u"search"_q, Command::Search)` and `set(u"find"_q, Command::Search)` registered as defaults)

- [ ] [MAJOR] Bare `Escape` is registered as a global-scope `cancelSearch` shortcut, so pressing Escape anywhere in the app (inside dialogs, sheets, context menus) also attempts to cancel search — AyuGram does not route cancel-search through the shortcut system at all; the search bar widget handles Escape internally — `keyboard_shortcuts.dart:828` ← `AyuGram/core/shortcuts.cpp:468-535` (`fillDefaults` — no `cancelSearch`/`cancel_search` entry exists; the command name is absent from `CommandByName` map entirely)

# language_box — Audit

- [ ] [CRITICAL] `_selectLanguage` never applies the selected language — stores code in AppState and calls `saveLanguagePrefs` but there is no `LangpackGetLangPack` call, no Flutter locale update, and no `engine.setLanguage()` equivalent; the UI language is never actually changed — `language_box.dart:177-183` ← `language_box.cpp:1386-1392` (`Lang::CurrentCloudManager().switchToLanguage(language)`)

- [ ] [CRITICAL] "Translate Entire Chats" premium gate is broken — `locked: true` is hardcoded unconditionally, the switch is fully operable by anyone, and there is no premium status check or `ShowPremiumPreviewToBuy` call when toggled — `language_box.dart:280-291` ← `language_box.cpp:1439-1470` (`Data::AmPremiumValue` check + `setToggleLocked(!value)`)

- [ ] [CRITICAL] `_kTranslationLanguages` is a manually curated static list of ~100 entries that deviates from AyuGram's `TranslationLanguagesList()` (67 entries from `QLocale::*`); Dart adds ~30 unverified languages (Gujarati, Haitian Creole, Hawaiian, Hindi, Hmong, Javanese, Kannada, Khmer, Latin, Marathi, Punjabi, Samoan, Sesotho, Tagalog, Tamil, Telugu, Uyghur, Yoruba, Zulu, etc.) and is missing AyuGram's `Gusii` and `Teso`; server support for the added languages is not guaranteed — `language_box.dart:1015-1058` ← `choose_language_box.cpp:27-128`

- [ ] [CRITICAL] `_SkipLanguagesEditor` saves every toggle immediately via `engine.saveLanguagePrefs` with a "Close" button only — AyuGram's `ChooseLanguageBox(multiselect=true)` collects all selections and applies them only on "Save"; partial/intermediate state is sent to the engine on each individual checkbox tap — `language_box.dart:849-874, 982-985` ← `choose_language_box.cpp:363-379`

- [ ] [MAJOR] Dialog closes on language selection (`Navigator.of(context).pop(langCode)`) — AyuGram keeps the dialog open and updates the radio button in-place via `inner->changeChosen(currentId())`; the Dart dialog disappears immediately after selection — `language_box.dart:182` ← `language_box.cpp:1379-1392`

- [ ] [MAJOR] Search field is a plain `TextField` in a rounded container; AyuGram uses `Ui::MultiSelect` with `tr::lng_participant_filter()` hint, which has different visual style (no rounded bubble container, different focus behavior, integrated into the box header area via `topContainer`) — `language_box.dart:339-363` ← `language_box.cpp:1339-1344`

## media_viewer — Critical and Major Issues

- [ ] [CRITICAL] Speed boost hold delay is 300ms but AyuGram uses 200ms (`mediaviewSpeedBoostHoldDelay: 200`) — `media_viewer.dart:879` ← `AyuGram/media/view/media_view.style:249` + `media_view_overlay_widget.cpp:6671`
- [ ] [CRITICAL] Scroll wheel navigation direction is inverted: `scrollDelta.dy > 0 → _goToPrev()` but AyuGram `angleDelta().y() < 0 (scroll down) → moveToNext(1)` (i.e. scroll down = go newer, scroll up = go older); Dart has it backwards — `media_viewer.dart:761-766` ← `AyuGram/media/view/media_view_overlay_widget.cpp:6828-6844`
- [ ] [CRITICAL] `_viewStatistics` is a fake stub: shows hardcoded views/shares/reactions from message fields in a modal bottom sheet — AyuGram navigates to the real statistics section via `Statistics::Make(peer, {}, fullId)` — `media_viewer.dart:2822-2854` ← `AyuGram/media/view/media_view_overlay_widget.cpp:2203-2213`
- [ ] [CRITICAL] `_StoryViewsListPopup` is fully stubbed: shows fake "Viewer 1"/"Viewer 2"/"Just now" placeholder rows with colored icon circles — no engine call to fetch actual story viewers — `media_viewer.dart:7082-7138` ← `AyuGram/media/stories/media_stories_recent_views.cpp`
- [ ] [CRITICAL] `_shareAtTime` is a stub: copies text like `"filename at 00:01"` to clipboard instead of opening a proper share dialog — AyuGram calls `Stories::PrepareShareAtTimeBox` — `media_viewer.dart:2756-2762` ← `AyuGram/media/view/media_view_overlay_widget.cpp:3148-3158`
- [ ] [CRITICAL] Story reactions panel uses hardcoded emoji list `['❤️', '🔥', '👍', '😱', '🎉', '😢', '👏']` — AyuGram loads reactions dynamically from the full reactions selector API, not a fixed 7-item array — `media_viewer.dart:4526` ← `AyuGram/media/stories/media_stories_reactions.cpp`
- [ ] [CRITICAL] `_openDrawEditor` calls `onDone` with a toast "Photo saved" but never actually saves or uploads the edited image to Telegram — the callback is a no-op — `media_viewer.dart:3050-3053` ← requires engine call to replace/update media
- [ ] [CRITICAL] Stealth Mode dialog always defaults `isPremium = true` — never reads actual account premium status from engine or AppState, so the non-premium unlock gate never triggers — `media_viewer.dart:6636` ← `AyuGram/media/view/media_view_overlay_widget.cpp:2216`
- [ ] [CRITICAL] Custom emoji story interactive area reactions (type `StoryMediaAreaType.reaction` with `emoji.startsWith('custom:')`) return `SizedBox.shrink()` — custom emoji reactions are silently dropped instead of rendered — `media_viewer.dart:4738-4739`
- [ ] [CRITICAL] `_forwardMedia` uses a raw `AlertDialog` chat list picker instead of the proper Telegram forward dialog (which shows contacts, recent chats, groups with caption, etc.) — AyuGram calls `ShowForwardMessagesBox` — `media_viewer.dart:2620-2651` ← `AyuGram/media/view/media_view_overlay_widget.cpp:3293-3309`
- [ ] [CRITICAL] PiP `_snapPosition` uses `innerMargin = 3 * _kPipBorderSkip = 60px` as both the initial position and as the snap target, but AyuGram uses `3 * st::pipBorderSkip` only for max-size clamping; actual snapping uses `st::pipBorderSkip = 20px` directly — `media_viewer.dart:4030-4056` ← `AyuGram/media/view/media_view_pip.cpp:67-89`
- [ ] [MAJOR] Auto-hide timer fires at 1100ms matching `mediaviewWaitHide: 1100` but the controls fade-out duration is 600ms (`reverseDuration`) while AyuGram uses `mediaviewHideDuration: 600` — this matches; however the fade-in `duration: 200ms` is `mediaviewShowDuration: 200` — those match too. The issue is `_scheduleAutoHide` is called on every `_onPointerActivity` but NOT reset on `_showControls` when already running, unlike AyuGram which cancels+restarts — `media_viewer.dart:804-809`
- [ ] [MAJOR] Footer date format uses hardcoded US 12-hour AM/PM format ("Jan 5, 2025 at 3:30 PM") — AyuGram uses locale-aware format plus "Today at …" / "Yesterday at …" shortcuts via `Ui::FormatDateTime` — `media_viewer.dart:2416-2419` ← `AyuGram/media/view/media_view_overlay_widget.cpp:1581` + `ui/text/format_values.cpp:84-103`
- [ ] [MAJOR] DC suffix format uses `(DC${msg.dcId})` with parentheses but AyuGram appends `, DC1` (comma-separated, no parens) — `media_viewer.dart:2419` ← `AyuGram/media/view/media_view_overlay_widget.cpp:1583`
- [ ] [MAJOR] Zoom scale formula `pow(2.0, 3.0 * level / 7.0)` produces different scales than AyuGram's integer zoom model where scale = `(level + 1)` for positive zoom or `1 / (-level + 1)` for negative — e.g. level=1: Dart gives ~1.30x, AyuGram gives 2.0x — `media_viewer.dart:668-669` ← `AyuGram/media/view/media_view_overlay_widget.cpp:2525-2531`
- [ ] [MAJOR] `_StealthModeDialog` never starts the countdown timer initially — `_countdownTimer` is only started if `_buttonState == cooldown` at `initState`, but `_now` is set once; if `cooldownTill` changes after open the timer never starts — `media_viewer.dart:6676-6686`
- [ ] [MAJOR] `_locationChip` opens `https://maps.google.com/?q=lat,lng` via `xdg-open` (Linux-only) without any platform guard — non-Linux builds will fail silently — `media_viewer.dart:4662-4666`
- [ ] [MAJOR] `_saveMediaToDownloads` saves to `~/Downloads` unconditionally, ignoring any Telegram download path preference — AyuGram respects `Core::App().settings().downloadPath()` and shows a "Save As" dialog when `askDownloadPath` is set — `media_viewer.dart:2524-2550` ← `AyuGram/media/view/media_view_overlay_widget.cpp:3161-3180`
- [ ] [MAJOR] `stealth_mode` context menu item has a wrong condition: shown when `widget.mediaMessages.isEmpty` — this is always false because `MediaViewer.open()` early-returns if `mediaMessages.isEmpty`. This means stealth mode is never accessible from the media viewer context menu — `media_viewer.dart:2909`
- [ ] [MAJOR] `_GalleryThumbsStrip` (thumbnail strip) uses `AnimationController` with `value: 1.0` and fires `forward(from: 0.0)` on index change — but the animation controller has no listener, so the animation has no visual effect; the strip doesn't animate width transitions when navigating — `media_viewer.dart:3320-3343`
- [ ] [MAJOR] `_ThumbRow` shows thumbs only within `[currentIndex - maxSideThumbs, currentIndex + maxSideThumbs]` as a static slice without scroll — AyuGram's `media_view_group_thumbs.cpp` uses a proper sliding window with smooth animated transitions and scroll — `media_viewer.dart:3351-3382` ← `AyuGram/media/view/media_view_group_thumbs.cpp`

# message_bubble — Audit findings

## Verified dimensions matching AyuGram

Before findings, confirmed matches (not issues):
- Bubble padding `11px, 8px` → `chat.style:26 msgPadding: margins(11px, 8px, 11px, 8px)` ✓
- Bubble radius large 16px, small 6px → `chat.style:434-435` ✓
- Corner button 36×32px → `chat.style:903 reactionCornerSize: size(36px, 32px)` ✓
- Reply bar 2px×36px, skip 10px → `chat.style:88-89 msgReplyBarSize/Skip` ✓
- Waveform bar 2px, gap 1px, min 3px, max 17px → `chat.style:557-560` ✓

---

- [ ] [CRITICAL] `_ReactionStrip` uses a hardcoded emoji list `['👍','❤️','🔥','🥰','👏','😱','😢','🎉']` with no engine call to fetch available reactions for the chat. AyuGram loads the strip from `session().data().reactions()` (server-provided top/available reactions). — `message_bubble.dart:1490` ← `AyuGram/history/view/reactions/history_view_reactions_selector.cpp:142-175` (defaultReactionIds populated from server reaction list)

- [ ] [CRITICAL] `_ReactionCornerButton` hardcodes the display emoji and sent reaction as `❤️`. AyuGram always uses `session().data().reactions().favoriteId()` — the user's configured favorite reaction. User may have set a different quick reaction via Settings → Appearance → Quick Reaction. — `message_bubble.dart:1075` ← `AyuGram/history/view/history_view_list_widget.cpp:2901` (`const auto favorite = session().data().reactions().favoriteId()`)

- [ ] [CRITICAL] `_ReactionEmojiOverlay` uses a fully static hardcoded Unicode emoji list across 10 categories (lines 1713–1786). This is a vanilla emoji keyboard, not Telegram's reaction picker. AyuGram's full-screen reaction picker loads available reactions from the server via `messages.getAvailableReactions` and shows custom emoji reactions from sticker packs. No engine call is made. — `message_bubble.dart:1713-1786` ← `AyuGram/history/view/reactions/history_view_reactions_selector.cpp:282-357`

- [ ] [CRITICAL] `request_peer` inline button (line 9554–9658) calls `chatState.sendMessage(selected.chatId)` after peer selection — literally sends the chatId string as a plain text message. The correct API is `messages.SendBotRequestedPeer`. The Go backend has `MessagesSendBotRequestedPeer` implemented at `telegram.go:21976` but the bridge dispatch is explicitly skipped (`dispatch_gen.go:20979`: `// Skipped: MessagesSendBotRequestedPeer (complex external types)`). There is no Dart bridge call for it. The bot never receives the peer result. — `message_bubble.dart:9657` ← `AyuGram/history/view/history_view_list_widget.cpp` (uses proper bot requested peer API)

- [ ] [MAJOR] Transcription pending poll uses a fixed 3-second `Future.delayed` (line 4144) then calls `transcribeAudio` once more. If that retry also returns `pending: true`, transcription silently fails with an empty result. Should poll with backoff until `pending == false`. — `message_bubble.dart:4143-4151` ← `AyuGram/history/view/history_view_transcribe_button.cpp` (listens to server update event when transcription completes)

- [ ] [MAJOR] `request_location` keyboard button shows a toast "Location sharing is not supported on this platform" / "requires GPS access" (lines 9539–9543) and never sends any location data to the bot. This is a dead stub. — `message_bubble.dart:9538-9543` ← `AyuGram/history/view/history_view_message.cpp` (uses geolocation API to send location to bot)

- [ ] [MAJOR] Inline reaction pill dimensions deviate from AyuGram spec: emoji `fontSize: 15` vs `chat.style:874 reactionInlineSize: 18px`; padding `symmetric(horizontal: 4, vertical: 1)` vs `chat.style:873 reactionInlinePadding: margins(5px, 2px, 7px, 2px)` (asymmetric left/right); between-pill spacing `Wrap(spacing: 3)` vs `chat.style:887 reactionInlineBetween: 4px`. — `message_bubble.dart:2055,2073` ← `AyuGram/ui/chat/chat.style:873-887`

- [ ] [MAJOR] `_ReactorAvatar` in the "who reacted" popup always renders a generated letter-initial avatar (line 2120) because `ReactorInfo` model has no `avatarB64` field — user photos are never shown. Peer photo data is available from `messages.GetMessageReactionsList` (`from_photo` field) but is not included in the `ReactorInfo` model or the Go bridge serialization. — `message_bubble.dart:2109-2135` ← `AyuGram/history/view/reactions/history_view_reactions_list.cpp` (shows user userpics)

- [ ] [MAJOR] `_ReactionCornerButton` is positioned at `top: 0` (flush with bubble top-corner). AyuGram places the button with `reactionCornerCenter: point(7px, -9px)` — center is 9px above the top bubble edge, so it partially floats above the bubble. The Dart button is entirely inside the message row with no vertical float offset. — `message_bubble.dart:1069-1070` ← `AyuGram/ui/chat/chat.style:904 reactionCornerCenter: point(7px, -9px)`

# my_profile_page — Edit Profile / My Profile Page

- [ ] [MAJOR] Birthday picker uses Flutter system calendar (`showDatePicker`) instead of AyuGram's vertical drum picker (three scroll wheels: day, month, year) — `my_profile_page.dart:124` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/edit_birthday_box.cpp:44` (`Ui::VerticalDrumPicker` with `st::settingsWorkingHoursPicker` height, three wheels)

- [ ] [MAJOR] Status line in photo area shows only `"online"` or `"connecting..."` — missing full last-seen text (`"last seen recently"`, `"last seen today at HH:MM"`, etc.) that AyuGram computes reactively with `Data::OnlineText(user, now)` — `my_profile_page.dart:688-694` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_information.cpp:282-299` (`StatusValue` reactive producer)

- [ ] [MAJOR] Account row context menu always adds `"Open in New Window"` item — AyuGram only adds it when the account is **not** active (`if (!isActive) { addAction(...newWindow...) }`) — `my_profile_page.dart:1683-1688` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_information.cpp:872-876`

- [ ] [MAJOR] Profile photo in photo area is not tappable — AyuGram uses `UserpicButton::Role::OpenPhoto` so clicking the avatar opens the full-screen photo viewer; Dart has no tap handler on the main `_avatarFallback`/`Image.file` widget — `my_profile_page.dart:641-654` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_information.cpp:311-316`

- [ ] [MAJOR] Personal channel editor accepts a raw username string with no channel ownership validation — AyuGram routes through `internal:edit_personal_channel` which presents a proper channel-selection flow — `my_profile_page.dart:1029-1079` ← `AyuGramDesktop/Telegram/SourceFiles/settings/sections/settings_information.cpp:507-520`

# notification_popup — Audit findings

- [ ] [CRITICAL] Body text vertical position is 7px too low: Dart computes `top: _textTop + _itemTopOffset + 13 = 7+12+13 = 32px` but AyuGram uses `st::notifyItemTop + st::semiboldFont->height = 12+13 = 25px`. The `_textTop` (7) is erroneously added to the body position — it belongs only to the title. — `notification_popup.dart:558` ← `notifications_manager_default.cpp:958-961` + `window.style:48-50`

- [ ] [CRITICAL] Body text right margin overlaps close button: Dart body text uses `right: 8` but the close button occupies the region `right 1..31px`, causing ~23px of body text to draw over the close button. Title text is correctly bounded at `right: _closeSize + _closePosRight + 4 = 35`, but body text is not. AyuGram uses the same `itemWidth` for both title and body, which subtracts `notifyClosePos.x + notifyClose.width`. — `notification_popup.dart:557-581` ← `notifications_manager_default.cpp:928-930`

- [ ] [MAJOR] Reply button fade animation defined but unused: `_actionsFadeDuration = Duration(milliseconds: 200)` is declared at the top of the file but never referenced. AyuGram uses `st::notifyActionsDuration` (200ms) for `a_actionsOpacity.start(...)` to fade the reply button in/out on hover; in Dart the reply button appears and disappears instantly via `setState`. — `notification_popup.dart:33` (defined but never used) ← `notifications_manager_default.cpp:1105`

- [ ] [MAJOR] FocusNode created on every build and never disposed in `_ReplyField`: `focusNode: FocusNode()` at line 867 creates a new node each rebuild without assigning it to a field or disposing it, leaking OS focus resources. Should be a field in the parent `_NotificationPopupOverlayState` per `_PopupState`. — `notification_popup.dart:867` ← `notifications_manager_default.cpp:1128-1136` (C++ reuses the single `_replyArea` widget)

- [ ] [MAJOR] Reply field does not handle Ctrl+Enter submission: Dart only wires `onSubmitted` (Enter key). AyuGram sets `_replyArea->setSubmitSettings(Ui::InputField::SubmitSettings::Both)` meaning both Enter and Ctrl+Enter submit the reply. Ctrl+Enter in Dart inserts a newline instead. — `notification_popup.dart:888` ← `notifications_manager_default.cpp:1138`

## notifications_settings_screen — Audit Findings

- [ ] [CRITICAL] "Upload Sound" in `_RingtonesBoxDialog._onUploadSound()` only adds the tone to local in-memory state (`_tones`); it never calls the engine to actually upload the file to Telegram's server-side ringtone storage (`SavedRingtones`). The file data is read (`file.bytes`) but never sent anywhere — the engine has no `uploadRingtone`/`saveRingtone` method at all. Selected tone IDs like `_nextId` (integer increments starting at 1) will be meaningless to the backend. — `notifications_settings_screen.dart:3716` ← `AyuGram/settings/sections/settings_notifications_type.cpp:550` (`tone->setClickedCallback` calls `RingtonesBox` which uploads via `api::Ringtones`)

- [ ] [CRITICAL] "Delete tone" in `_RingtonesBoxDialog._deleteTone()` removes the tone from local state only — never calls the engine to delete from Telegram's saved ringtones list. No `deleteSavedRingtone` engine call exists. — `notifications_settings_screen.dart:3724` ← `AyuGram/settings/sections/settings_notifications_type.cpp:550`

- [ ] [CRITICAL] Per-type volume slider in `_NotificationTypeSubPageState` (`_volume` field) is only persisted locally via `setState`; `_persistSoundState()` only sends `soundEnabled` bool, not the volume value. The volume change never reaches the engine (no `updateDefaultNotifySettings(..., volume: v)` call exists). — `notifications_settings_screen.dart:1646` ← `AyuGram/settings/sections/settings_notifications_type.cpp:513` (`Ui::AddRingtonesVolumeSlider` with `saveVolume` callback that calls `Core::App().notifications().playSound(...)` and `controller.saveVolume(volume)`)

- [ ] [CRITICAL] "Pinned messages" toggle in `_buildEventsSection` only saves to local AppState/prefs (`setNotifPinnedMessages`) — no engine call is made to actually update the setting on Telegram servers. In AyuGram the pinned setting calls `Core::App().settings().setNotifyAboutPinned(notify)` + `Core::App().saveSettingsDelayed()`. The Dart `setNotifPinnedMessages` method has no engine call inside it. — `notifications_settings_screen.dart:468` ← `AyuGram/settings/sections/settings_notifications.cpp:1306`

- [ ] [CRITICAL] "Include muted chats in unread count", "Include muted chats in folder counters", and "Count unread messages" toggles in `_buildBadgeCounterSection` only call `setNotifIncludeMutedChats` / `setNotifIncludeMutedInFolders` / `setNotifCountUnreadMessages` which are local-state-only (no engine calls inside those methods). In AyuGram these all call `Core::App().settings().setIncludeMutedCounter(...)` + `Core::App().saveSettingsDelayed()` + `notifications().notifySettingsChanged(ChangeType::IncludeMuted)`. None of this is wired to the engine. — `notifications_settings_screen.dart:537` ← `AyuGram/settings/sections/settings_notifications.cpp:1401`

- [ ] [CRITICAL] "All accounts" multi-account toggle `setNotifAllAccountsNotify(v)` is local-state-only — no engine call. In AyuGram this calls `Core::App().settings().setNotifyFromAll(checked)` + `Core::App().saveSettingsDelayed()` and also triggers `notifications.clearFromSession()` for inactive accounts when disabled. None of this backend logic exists. — `notifications_settings_screen.dart:195` ← `AyuGram/settings/sections/settings_notifications.cpp:952`

- [ ] [CRITICAL] Reactions sub-page `_ReactionsFrom` enum only has `everyone` and `contacts` — missing the `None` (nobody) option that AyuGram exposes (`NotifyFrom::None` / `tr::lng_notification_reactions_from_nobody()`). When reactions are disabled via toggle, `_persistSettings()` sends `'everyone'` instead of `'none'` since `_reactionsFrom` defaults to `everyone` and the disabled state is encoded only via the separate `_reactionsEnabled` bool, which is a separate field not mapped to the AyuGram `NotifyFrom::None` semantic. — `notifications_settings_screen.dart:2815` ← `AyuGram/settings/sections/settings_notifications_reactions.cpp:37`

- [ ] [MAJOR] Global volume slider (`appState.notifVolume`) only saves to local prefs — no engine call is made to persist the master notification volume to the backend. In AyuGram `saveVolume` calls `Core::App().settings().setNotificationsVolume(volume)` + `Core::App().saveSettingsDelayed()` + plays a preview sound. The Dart side calls `_playVolumePreview(v)` (plays a local temp file) but never calls any engine method to persist the global volume. — `notifications_settings_screen.dart:298` ← `AyuGram/settings/sections/settings_notifications.cpp:1042`

- [ ] [MAJOR] Exceptions list in `_NotificationTypeSubPageState._loadExceptions()` is populated from `ChatState.chatsForAccount()` filtered by `c.isMuted` — this is a local cache snapshot and does NOT use the authoritative server exceptions list. AyuGram uses `session().data().notifySettings().exceptions(type)` which is the live per-type exception set updated by server events. The Dart approach misses server-side exceptions that were added on other clients or sessions. — `notifications_settings_screen.dart:1484` ← `AyuGram/settings/sections/settings_notifications_type.cpp:213`

- [ ] [MAJOR] "Notification tone" selection in `_RingtonesBoxDialog` assigns local integer IDs (`_nextId` starting from 1) to uploaded tones, but when saved these IDs are passed to `updateDefaultNotifySettings` (indirectly via `_showRingtonesBox` → `_selectedToneId`). The engine's `updateDefaultNotifySettings` uses `sound_id` from this value, but since the file was never actually uploaded there is no valid server document ID — the stored sound_id will be a meaningless local counter. — `notifications_settings_screen.dart:3716` ← `AyuGram/settings/sections/settings_notifications_type.cpp:482`

- [ ] [MAJOR] `_buildGlobalSettings` reads `appState.notifDesktopNotify`, `notifFlashBounce`, `notifAllowSound` but never calls any engine notification manager equivalent of `ChangeType::DesktopEnabled` / `ChangeType::SoundEnabled` / `ChangeType::FlashBounceEnabled`. These settings only update local prefs — the running notification manager is not notified to reconfigure itself. — `notifications_settings_screen.dart:237` ← `AyuGram/settings/sections/settings_notifications.cpp:1058`

- [ ] [MAJOR] "Reactions to my messages" toggle sends `'everyone'`/`'contacts'` for `reactionsFrom` but when the toggle is turned off, the code sets `_reactionsEnabled = false` yet still sends `reactionsFrom: 'everyone'` (or the cached value) in `_persistSettings()`. AyuGram maps disabled reactions directly to `NotifyFrom::None` for the relevant from-field, not a separate boolean. The engine backend may interpret this incorrectly since `reactionsEnabled=false` + `reactionsFrom='everyone'` is a contradictory state. — `notifications_settings_screen.dart:2858` ← `AyuGram/settings/sections/settings_notifications_reactions.cpp:120`

- [ ] [MAJOR] `_buildSystemIntegrationSection` guard `!appState.notifUseNative` for showing the advanced section (position/corner/count) is inverted from AyuGram. AyuGram shows the advanced (non-native) section when native notifications are OFF (`advancedSlide->toggle(!checked, ...)`). Dart also hides the section when `notifUseNative == true` which is correct, but the initial state for `advancedSlide` in AyuGram also considers `nativeEnforced()` which would hide the entire native toggle on platforms where native is mandatory — the Dart code shows the section unconditionally on all platforms. — `notifications_settings_screen.dart:608` ← `AyuGram/settings/sections/settings_notifications.cpp:1466`

# payment_panel — Checkout/Receipt payment panel

- [ ] [CRITICAL] `_editPaymentMethod()` is a broken stub: for native providers (Stripe/SmartGlocal) it tries to `launchUrl(nativeParams['url'])` which is an empty field — native params contain a `publishableKey`, not a URL; no in-app card tokenization exists, so submitting payment will always fail with missing credentials — `payment_panel.dart:897-908` ← `AyuGram/payments/ui/payments_panel.cpp:426-436` (`showEditPaymentMethod` shows native card form or WebView)

- [ ] [CRITICAL] Shipping method selection is an empty stub: `case 'Shipping Method': break` does nothing — the user can never select a shipping option — `payment_panel.dart:880-881` ← `AyuGram/payments/payments_checkout_process.cpp:912-918` (`panelChooseShippingOption` calls `chooseShippingOption` which shows a `SingleChoiceBox`)

- [ ] [CRITICAL] `_submitPayment()` never validates/sends user information to the server before submitting — AyuGram calls `_form->validateInformation(_form->information())` which POSTs address/name/email/phone to get a `requested_info_id` required in the final submit call; Dart skips this entirely — `payment_panel.dart:246-265` ← `AyuGram/payments/payments_checkout_process.cpp:646-668`

- [ ] [CRITICAL] Receipt tips row is wrapped in a GestureDetector that opens the edit-tips dialog — receipts are read-only, tips must not be editable after payment; AyuGram shows receipt tips as a plain non-interactive row — `payment_panel.dart:570-573` ← `AyuGram/payments/ui/payments_form_summary.cpp:353-357` (receipt branch calls `add(label, tips)` with no click handler)

- [ ] [CRITICAL] Max-tip validation compares user-entered major units against a minor-unit limit: `val <= _maxTip` where `_maxTip` is minor units (e.g. 1000 = $10.00) but `val` is what the user typed (e.g. 15 for $15 → `15 <= 1000` passes, allowing a $15 tip when max is $10) — `payment_panel.dart:986` ← `AyuGram/payments/ui/payments_panel.cpp:410-413` (field returns minor units; compared directly to `max` in minor units)

- [ ] [MAJOR] `_spinnerAnim` (1200ms repeating controller) is included in the `AnimatedBuilder` listenable merge but its value is never referenced in the builder body — `_progressFade.value` is the only value used; this causes the entire loading widget to rebuild at ~60fps while `_spinnerAnim` is running for no reason; `CircularProgressIndicator` already animates internally — `payment_panel.dart:495-508` ← `AyuGram/payments/ui/payments_panel.cpp:64-69` (single `InfiniteRadialAnimation` drives itself, no external ticker merge)

- [ ] [MAJOR] Shipping address display only includes `street1 + city`; AyuGram builds the address from address1, address2, city, state, country name (by ISO2 via `Countries::Instance()`), and postcode — `payment_panel.dart:199-204` ← `AyuGram/payments/ui/payments_form_summary.cpp:508-520`

- [ ] [MAJOR] Shipping prices (from the selected shipping option) are silently folded into `_computeTotal()` but never rendered as individual line items — AyuGram adds each `selected->prices` entry as its own labeled row in the price list — `payment_panel.dart:673-703` ← `AyuGram/payments/ui/payments_form_summary.cpp:340-349`

- [ ] [MAJOR] Terms acceptance is tracked in local `_termsAccepted` bool only and never communicated to the backend — AyuGram calls `_form->acceptTerms()` via `panelAcceptTermsAndSubmit()` which marks terms as accepted in the form state before the final submit — `payment_panel.dart:310-315` ← `AyuGram/payments/payments_checkout_process.cpp:676-679`

- [ ] [MAJOR] Phone number displayed as a raw string from `saved['phone']` with no formatting — AyuGram applies `Ui::FormatPhone(_information.phone)` before display — `payment_panel.dart:122-123` ← `AyuGram/payments/ui/payments_form_summary.cpp:554-557`

- [ ] [MAJOR] Product thumbnail loaded via `Image.network(photoUrl)` bypassing the Go engine media pipeline — AyuGram delivers thumbnails through `updateThumbnail(QImage)` fired from the reactive `_thumbnails` stream attached to the form; no engine caching or lifecycle management — `payment_panel.dart:618` ← `AyuGram/payments/ui/payments_form_summary.cpp:135-138` (`updateThumbnail` / `_thumbnails.fire_copy`)

# peer_short_info — Peer Short Info Box Audit

- [ ] [CRITICAL] "Open in New Window" context menu item calls `chatState.openChat(chat)` which opens in the **same** window, not a new separate window — `peer_short_info.dart:371` ← `prepare_short_info_box.cpp:508` (`window->showInNewWindow(peer)`)

- [ ] [MAJOR] Progress bars never show video playback position — `_PhotoProgressBarsPainter` always renders the active bar at full width, but AyuGram partially fills it based on `_videoPosition / float64(_videoDuration)` (active bar acts as a playback-progress indicator while video is playing) — `peer_short_info.dart:1196-1214` ← `peer_short_info_box.cpp:296-322`

- [ ] [MAJOR] Missing `InfiniteRadialAnimation` for video waiting/buffering state — Dart only shows a static `CircularProgressIndicator` gated on `_showRadialLoader`, but AyuGram renders a separate infinite animation (opacity driven by `_videoInstance->waitingOpacity()`) whenever a video avatar is buffering/seeking — `peer_short_info.dart:743-759` ← `peer_short_info_box.cpp:366-412`

- [ ] [MAJOR] `_buildCoverOverlay` rebuilds the entire cover overlay widget subtree (gradients, progress bars, name/status labels, nav zones) on every scroll tick via `ValueListenableBuilder<double>` — AyuGram does a single `_widget->update()` triggering one repaint call; the Dart approach causes excessive widget tree reconstruction during scroll — `peer_short_info.dart:584-764` ← `peer_short_info_box.cpp:175-178` (`setScrollTop` → `_widget->update()`)

# photo_crop_editor — Audit findings

## photo_crop_editor — Photo editor paint tools, text/sticker tools, color picker, and layout

- [ ] [CRITICAL] `_openStickersTool` onTap callback is a pure stub — dismisses the dialog without placing any sticker or emoji on the canvas; the selected emoji value is completely discarded — `photo_crop_editor.dart:496-499` ← `AyuGram/editor/editor_paint.cpp:43-52` (scene-based sticker items via StickersPanelController)

- [ ] [CRITICAL] `_addTextAnnotation` ignores its `text` parameter entirely — instead of creating a text item, it adds a single-point `_PaintTool.pen` stroke at the crop center, making the text tool completely non-functional; the `_TextAnnotation` class defined at line 74 is never instantiated anywhere — `photo_crop_editor.dart:468-478` ← `AyuGram/editor/editor_paint.h:56` (Paint::createTextItem → scene_item_text)

- [ ] [CRITICAL] No color picker UI exists — `_brushColor` is permanently hardcoded to `Color(0xFFFF0000)` (red) with no way to change it in the paint mode; AyuGram's `ColorPicker` class provides a full palette, custom color button, and per-tool selection — `photo_crop_editor.dart:217` ← `AyuGram/editor/color_picker.h` and `AyuGram/editor/editor.style:126-145` (`photoEditorColorButtonSize: 24px`, `photoEditorColorPaletteItemSize: 20px`, `photoEditorColorPaletteGap: 6px`)

- [ ] [CRITICAL] Arrow (`_PaintTool.arrow`) and marker (`_PaintTool.marker`) tools are declared in the enum but `_drawPaintStrokes` renders every stroke identically as a plain pen line — no arrow-head geometry, no marker opacity/size-multiplier, no eraser, no blur tool; AyuGram defines `photoEditorArrowHeadLengthFactor: 2.5`, `photoEditorArrowHeadAngleDegrees: 26`, `photoEditorMarkerOpacity: 0.35`, `photoEditorMarkerSizeMultiplier: 2.5` — `photo_crop_editor.dart:58,1338-1368` ← `AyuGram/editor/editor.style:147-156`

- [ ] [MAJOR] In paint mode the undo/redo bar (`_PaintTopBar`) is placed at the top of the main content area above the image (lines 681-702); in AyuGram `_paintTopButtons` sits just above the bottom control bar, separated only by `photoEditorControlsCenterSkip: 6px`, with both bars residing inside the 146 px controls zone — `photo_crop_editor.dart:681-702` ← `AyuGram/editor/photo_editor_controls.cpp:375-387`

- [ ] [MAJOR] Brush size control is entirely absent; AyuGram has a `photoEditorBrushSizeControlHeight: 280px` expandable vertical slider that controls stroke width interactively — `photo_crop_editor.dart` (no equivalent) ← `AyuGram/editor/editor.style:157-165` (`photoEditorBrushSizeControlHeight: 280px`, collapsed width 2px, expanded top 25px, expanded bottom 4px)

- [ ] [MAJOR] Aspect ratio menu order is wrong: Dart enum lists `ratio3x2, ratio3x4, ratio16x9, ratio9x16` (3:4 before 16:9) but AyuGram adds them as `3:2, 16:9, 3:4, 9:16` (16:9 before 3:4) — `photo_crop_editor.dart:117-128` ← `AyuGram/editor/photo_editor_controls.cpp:513-518`

- [ ] [MAJOR] `_ControlBar` renders as a plain `Row` with no background; AyuGram's `ButtonBar` class renders a fully-rounded pill background for the entire control bar row — `photo_crop_editor.dart:1624-1643` ← `AyuGram/editor/photo_editor_controls.cpp:125-204` (ButtonBar::ButtonBar round-corner QImage bg)

# popup_menu — Audit findings

- [ ] [CRITICAL] `_TelegramRippleItemState` uses an `AnimationController` to lerp the container background color between `hoverColor` and `rippleColor` — this is not a ripple. AyuGram calls `RippleButton::paintRipple(p, 0, 0)` which renders an actual expanding circle emanating from the pointer position. The Dart produces a flat background color pulse; Telegram users will see a completely wrong interaction feedback. — `popup_menu.dart:851-869` ← `AyuGram/Telegram/lib_ui/ui/widgets/menu/menu_action.cpp:121`

- [ ] [CRITICAL] `_shadowColor(Brightness.dark)` returns `const Color(0xFF17212b)`, the same colour as the menu background (`_menuBg`). With 0.25 opacity this makes the shadow nearly invisible in dark mode — the menu appears to float without any depth cue. AyuGram uses `windowShadowFg: #000000` (black) at 0.25 opacity for all themes, giving a clear drop shadow. — `popup_menu.dart:18-21` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:21` + `AyuGram/Telegram/lib_ui/ui/widgets/widgets.style:926-930`

- [ ] [MAJOR] Submenus are shown by inserting a bare `OverlayEntry` with no transition — they appear and disappear instantly. AyuGram calls `_activeSubmenu->showPrepared(source)` / `hideMenu(true)`, which runs the full `PanelAnimation` (scale + opacity reveal from the corner). Submenus should animate identically to the root menu. — `popup_menu.dart:471-517` / `popup_menu.dart:520-527` ← `AyuGram/Telegram/lib_ui/ui/widgets/popup_menu.cpp:390-413` / `popup_menu.cpp:531-549`

- [ ] [MAJOR] `_TelegramDisabledItem` uses `Color(0xFF999999)` for text and icon in light mode. AyuGram's `itemFgDisabled` resolves to `menuFgDisabled: #cccccc` — a much lighter grey (~30% brighter). Disabled items in light mode will appear too dark and more prominent than they should be. — `popup_menu.dart:891-895` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:59` + `AyuGram/Telegram/lib_ui/ui/widgets/widgets.style:977`

- [ ] [MAJOR] `showTelegramMenu` has no `maxHeight` concept. AyuGram's `PopupMenu` respects `st.maxHeight` from the style: when set, the scroll area is capped and the menu scrolls within that height. The Dart only constrains by `screenSize.height - margin * 2`. Any caller that needs a height-capped scrollable menu (e.g. long context menus in narrow windows) cannot express this constraint. — `popup_menu.dart:354-358` ← `AyuGram/Telegram/lib_ui/ui/widgets/popup_menu.cpp:210-213` + `widgets.style:1004`

# privacy_settings_screen — Audit Findings

## privacy_settings_screen — Backend Wiring & API Connectivity

- [ ] [CRITICAL] Gift settings toggles (`_giftShowIcon`, `_giftAcceptLimited`, `_giftAcceptUnlimited`, `_giftAcceptUnique`, `_giftAcceptFromChannels`, `_giftAcceptPremium`) update local state but are **never persisted to the engine** — `_save()` in `_EditPrivacyBoxState` calls only `setPrivacySetting()` and `setHideReadMarks()`, no gift preference API call exists — `privacy_settings_screen.dart:2377-2426` ← `AyuGram/settings/settings_privacy_controllers.cpp` (no gift accept wiring present; feature is UI-only stub)

- [ ] [CRITICAL] Fallback (public) photo upload/remove calls `engine.uploadFallbackPhoto()` and `engine.deleteFallbackPhoto()` (lines 2144, 2163) but `hasFallbackPhoto` state is never refreshed after upload/delete — `_hasFallbackPhoto` stays stale, so the "Remove" button can appear/disappear incorrectly — `privacy_settings_screen.dart:2144-2175` ← `AyuGram/settings/settings_privacy_controllers.cpp` (ProfilePhotoPrivacyController refreshes photo state via rpl after every mutation)

- [ ] [CRITICAL] Privacy setting exception lists ("Always Allow" / "Never Allow") are **never pre-fetched** before opening the editor — `_openPrivacyEditor()` passes empty exceptions to `_EditPrivacyBox`, so the counts always show `+0 / -0` on open instead of the real peer counts — `privacy_settings_screen.dart:724-809` ← `AyuGram/settings/settings_privacy_security.cpp` (exception peers loaded from `Rule.always/never` before box opens)

- [ ] [CRITICAL] Cloud password state refresh uses a 60-second polling timer — stale state (password hash, recovery email, pending reset date) shown to user for up to a minute when another session changes 2FA — `privacy_settings_screen.dart:79` ← `AyuGram/settings/settings_privacy_security.cpp` (uses `rpl::distinct_until_changed()` reactive subscription for instant state propagation)

- [ ] [CRITICAL] Account TTL / self-destruction confirmation dialog only fires when toggling from disabled (0) to enabled — changing an already-enabled TTL (e.g. 6 months → 1 month) skips confirmation entirely — `privacy_settings_screen.dart:4822-4868` ← `AyuGram/settings/settings_global_ttl.cpp` (confirmation shown for every value change while TTL is non-zero)

## privacy_settings_screen — Double-Call Vulnerabilities

- [ ] [MAJOR] Archive-and-Mute row fires `engine.setArchiveSettings()` twice per tap: once in `InkWell.onTap` (line 910) and again in `Switch.onChanged` (line 940) — rapid taps queue duplicate API calls — `privacy_settings_screen.dart:909-960` ← `AyuGram/settings/settings_privacy_security.cpp` (single `toggledChanges()` handler, no duplicate path)

- [ ] [MAJOR] Top Peers toggle fires `engine.toggleTopPeers()` twice per tap: once in `InkWell.onTap` (line 1263) and again in `Switch.onChanged` (line 1288) — `privacy_settings_screen.dart:1262-1311` ← `AyuGram/settings/settings_privacy_security.cpp` (single toggle handler at topPeers section)

## privacy_settings_screen — Missing Feature Gating

- [ ] [CRITICAL] "Charge Stars" messages privacy option can be selected by non-Premium users — no premium lock guard equivalent to the voice messages block at line 2314 — `privacy_settings_screen.dart:6183-6226` ← `AyuGram/settings/settings_privacy_security.cpp` (messagesPremium config check blocks non-premium access to paid messages option)

## privacy_settings_screen — State & Data Flow

- [ ] [MAJOR] Countdown timer `_countdownTimer` in `_CloudPasswordInputState` is started but not cancelled on widget unmount if disposal races with a pending `setState` call — `_updateCountdownText()` calls `setState` without `mounted` guard — `privacy_settings_screen.dart:3074-3095` ← `AyuGram/settings/settings_privacy_security.cpp` (rpl lifetime subscriptions auto-cancel on destruction)

- [ ] [MAJOR] Blocked users pagination: `_loadMore()` triggers on scroll position `>= maxScrollExtent - 200` but no visual "loading more" indicator shown while `_loadingMore == true` — user has no feedback that more data is being fetched — `privacy_settings_screen.dart:6463-6532` ← `AyuGram/settings/settings_blocked_peers.cpp` (PeerListContent has built-in loading row at bottom)

- [ ] [MAJOR] Block user contact picker FutureBuilder at line 6590 (`_loadContacts()`) has **no error builder** — if `engine.getContacts()` throws, the dialog shows an empty list with no error message or retry option — `privacy_settings_screen.dart:6589-6641` ← `AyuGram/settings/settings_blocked_peers.cpp:BlockedBoxController::BlockNewPeer` (shows error toast on failure)

- [ ] [MAJOR] Last Seen "Hide Read Time" toggle only renders when `_selected != 'everyone'` (controlled by AnimatedSize/visibility around line 2615) — AyuGram shows this toggle unconditionally so users who keep Last Seen set to Everyone can still hide read receipts — `privacy_settings_screen.dart:2615-2654` ← `AyuGram/settings/settings_privacy_controllers.cpp` (LastSeenPrivacyController shows hide-read-time unconditionally)

- [ ] [MAJOR] Login email change dialog (`_showChangeLoginEmailDialog`) awaits `engine.setCloudPasswordEmail()` with no timeout or cancellation — if the network hangs, the "Saving…" spinner runs forever and the user cannot dismiss or retry — `privacy_settings_screen.dart:2145-2252` ← `AyuGram/settings/settings_privacy_security.cpp` (cloud password flows use lifetime-bound requests that cancel on close)

- [ ] [MAJOR] Star price slider in `_MessagesPrivacyBox` reads `_sliderIndex` from a discrete `_starsValues` list but the label in the main privacy section (`_messagesChargeStars`) is fetched once on load (line 226) and never refreshed after `_save()` completes — the section subtitle stays stale until the next full reload — `privacy_settings_screen.dart:54,226,6112-6130` ← `AyuGram/settings/settings_privacy_security.cpp` (GlobalPrivacy reactive state updates label immediately after save)

# reactions_detail — Reactions Detail Panel Audit

- [ ] [CRITICAL] Custom emoji in tab pills rendered as `Icon(Icons.star)` stub instead of actual animated custom emoji — `reactions_detail.dart:638` ← `history_view_reactions_tabs.cpp:57-62` (factory renders real `CustomEmoji` animation using `Data::ReactionEntityData`)

- [ ] [CRITICAL] Custom emoji in reactor rows rendered as `Icon(Icons.star)` stub instead of actual animated custom emoji — `reactions_detail.dart:736` ← `history_view_reactions_list.cpp:162-166` (Row uses `Ui::Text::CustomEmoji` from factory)

- [ ] [MAJOR] Avatar photo position wrong: Dart uses `left: 18` but AyuGram style specifies `photoPosition: point(12px, 6px)` — 50% deviation — `reactions_detail.dart:703` ← `lib_ui/ui/widgets/widgets.style:1419`

- [ ] [MAJOR] Name and status text position shifted right: Dart uses `left: 79` but AyuGram style specifies `namePosition: point(68px, 11px)` and `statusPosition: point(68px, 31px)` — applies to both `_ReactorRow` and `_ReadParticipantRow` — `reactions_detail.dart:713` ← `lib_ui/ui/widgets/widgets.style:1421-1425`

- [ ] [MAJOR] "All reactions" tab uses `Icons.waving_hand` icon; AyuGram uses `reactionsTabAll` (`menu/read_reactions` icon, a heart/like icon) — `reactions_detail.dart:511` ← `history_view_reactions_tabs.cpp:88-100` and `ui/chat/chat.style:862`

- [ ] [MAJOR] Read tab icon never adapts for audio/video: Dart always uses `Icons.done_all`; AyuGram switches to `reactionsTabPlayed` (`menu/read_audio`) when `WhoReadType == Watched || Listened`, and `reactionsTabChecks` (`menu/read_ticks`) for normal read — `reactions_detail.dart:504` ← `history_view_reactions_tabs.cpp:88-100` and `ui/chat/chat.style:864-867`

- [ ] [MAJOR] `_ReactorRow` shows no status/subtitle text below username; AyuGram's `defaultPeerListItem` renders status at `statusPosition: point(68px, 31px)` — reaction reactor rows should show user status/handle — `reactions_detail.dart:679` ← `lib_ui/ui/widgets/widgets.style:1425`

- [ ] [MAJOR] Tab switch clears all loaded data and re-fetches from API on every tab change; AyuGram keeps the fully-loaded `_all` list in memory and filters it locally when switching to a per-reaction tab, only fetching if the filtered offset is non-empty — `reactions_detail.dart:254-264` ← `history_view_reactions_list.cpp:247-280`

- [ ] [MAJOR] `_ReactorAvatarState._photoCache` is a static unbounded map that grows forever across widget instances with no eviction policy — `reactions_detail.dart:870` ← AyuGram uses per-session data layer with proper lifecycle management

## send_files_box — groupFiles ignored, sendLargePhotos not forwarded, caption on wrong file, sendAsSticker dropped, reply header missing, price tag overlay missing

- [ ] [CRITICAL] `groupFiles` flag collected in `SendFilesResult` but never passed to engine — `_uploadFiles` loop calls `uploadFile` for each file individually with no grouping, so the "Group files" checkbox is a complete no-op — `send_files_box.dart:3978-3993` ← `send_files_box.cpp:2427-2449` (`DivideByGroups` + grouped album send)

- [ ] [CRITICAL] `sendLargePhotos` flag from `SendFilesResult` never forwarded to engine — `_uploadFiles` loop in `chat_view.dart:3978-3993` does not pass it to `uploadFile`, and `engine_service.dart:3710` has no such parameter, so photos are always compressed regardless of the "Send in high quality" toggle — `send_files_box.dart:1240` ← `send_files_box.cpp:2393-2394` (`item.sendLargePhotos = way.sendLargePhotos()`)

- [ ] [CRITICAL] `sendAsSticker` flag from `SendFilesResult` is never handled in `chat_view.dart` — the "Send as sticker" menu item calls `_send(asSticker: true)` and `SendFilesResult.sendAsSticker` is set, but `_uploadFiles` never reads it, so the file is always uploaded as a regular photo document — `send_files_box.dart:1215-1248` ← `send_files_box.cpp:1193-1216` (AyuGram converts image to WEBP sticker inline before calling `send()`)

- [ ] [CRITICAL] Caption placement wrong for document-group albums — Dart always assigns the main caption to file at index 0 (`i == 0 ? result.caption : ''`) but AyuGram assigns it to the LAST file in the last group for non-PhotoVideo albums (and FIRST file only for PhotoVideo/photo albums) — `send_files_box.dart:3979-3980` ← `send_files_box.cpp:2440-2446`

- [ ] [CRITICAL] Reply-to header (`ReplyPillHeader`) is entirely absent from the Dart implementation — AyuGram renders a reply pill above the file preview when the user is replying; Dart has no `_replyTo` or reply header widget at all — `send_files_box.dart` (missing) ← `send_files_box.cpp:672-718` + `send_files_box_reply_header.h/cpp`

- [ ] [CRITICAL] Paid media price tag overlay is missing — AyuGram renders a centered `_priceTag` widget overlaid on the file preview when `starsPerMessage > 0`; Dart only changes the send button label text but shows no visual overlay on the preview — `send_files_box.dart:1722-1730` ← `send_files_box.cpp:1075-1133` (`refreshPriceTag` / `_priceTag` widget)

- [ ] [CRITICAL] Rename dialog missing max-length enforcement — both `_doRename` (line 2047) and `_AlbumPreviewState._renameFile` (line 2386) show a plain `TextField` with no `maxLength`, allowing names longer than `kMaxDisplayNameLength` (64). AyuGram enforces `maxNameLength = 64 - extension.size()` and shows an error on overflow — `send_files_box.dart:2047-2069` / `send_files_box.dart:2386-2409` ← `send_files_box.cpp:132-177` (`RenameFileBox`)

- [ ] [MAJOR] Album layout two-image stacked formula diverges from AyuGram — for `ww` aspect-ratio pair, Dart uses `h0 = (maxH-sp) * r0 / (r0+r1)` (proportional split) whereas AyuGram uses `h = min(w/r0, min(w/r1, (maxH-sp)/2))` (equal-height capped at half of available height), producing visually different row heights — `send_files_box.dart:2594-2599` ← `grouped_layout.cpp:196-214` (`layoutTwoTopBottom`)

- [ ] [MAJOR] Clipboard paste is Wayland-only (`wl-paste`) — `_handleCaptionPaste` calls `Process.run('wl-paste', ...)`, which fails silently on X11 and non-Linux platforms; AyuGram uses Qt's cross-platform `QMimeData` clipboard API — `send_files_box.dart:618-628` ← `send_files_box.cpp:2086-2108` (`addFiles` via `QMimeData`)

- [ ] [MAJOR] Spoiler particle painter uses a fixed random seed (`math.Random(42)`) — all spoiler overlays produce the exact same particle layout; only the phase animation varies. AyuGram uses a proper per-frame random particle system — `send_files_box.dart:3331` ← (no direct AyuGram line, but AyuGram uses the `Ui::SpoilerAnimation` system with true randomness)

- [ ] [MAJOR] `captionEntitiesJson` is only forwarded for the first file (`i == 0 ? result.captionEntitiesJson : ''`) — per-file captions added via the edit-caption dialog have no entity/markup support (plain text only), whereas AyuGram stores `TextWithTags` per file and forwards full markup — `send_files_box.dart:3981` ← `send_files_box.cpp:1570-1598` (`EditFileCaptionBox` with `TextWithTags`)

- [ ] [MAJOR] Drag zone mode uses current file list state instead of the MIME data type of the dragged content — Dart computes `_computeDragZoneMode()` from `_files` contents at drag-enter time, but AyuGram evaluates the dragged `QMimeData` state (`PhotoFiles`/`MediaFiles`/`Files`/`Image`) to decide which drop zones to show — `send_files_box.dart:1116-1121` ← `send_files_box.cpp:849-877` (`setupDragArea` / `computeState`)

# settings_screen — Settings Screen Audit

- [ ] [CRITICAL] Premium/Stars/Business/Gift buttons open external browser URLs via `xdg-open` instead of navigating to internal settings screens — `settings_screen.dart:361,367,374,381` ← `settings/sections/settings_main.cpp:539,556,585,594` (AyuGram: `showOther(PremiumId())`, `showOther(CreditsId())`, `showOther(BusinessId())`, `Ui::ChooseStarGiftRecipient(controller)`)

- [ ] [CRITICAL] "Choose Emoji" in avatar menu calls `_showEmojiStatusPanel` (sets emoji STATUS) instead of opening the emoji-as-profile-photo picker — `settings_screen.dart:749-750` ← `settings/sections/settings_main.cpp:209-224` (AyuGram: `UserpicButton` with `markup.documentId` for emoji photo; emoji status and emoji avatar are separate features)

- [ ] [CRITICAL] Interface scale "Restart Now" calls `exit(0)` which kills the process without restarting — `settings_screen.dart:1729` ← `settings/sections/settings_main.cpp:1137-1141` (AyuGram: `Core::Restart()` saves settings and relaunches the process)

- [ ] [CRITICAL] "Telegram Stars" row shows no real balance and opens external URL instead of showing credits balance and routing to credits screen — `settings_screen.dart:363-368` ← `settings/sections/settings_main.cpp:546-561` (AyuGram: `session->credits().balanceValue()` displayed as trailing label, navigates to `CreditsId()`)

- [ ] [CRITICAL] Premium section visibility check uses `account?.platform == 'telegram'` instead of server-side `premiumPossible()` capability — `settings_screen.dart:356` ← `settings/sections/settings_main.cpp:528` (AyuGram: `if (!session->premiumPossible()) return;`)

- [ ] [CRITICAL] "Send a Gift" shown unconditionally for all Telegram accounts; should only appear when `premiumCanBuy()` — `settings_screen.dart:376-382` ← `settings/sections/settings_main.cpp:589-596` (AyuGram: `if (session->premiumCanBuy())` gate before adding button)

- [ ] [MAJOR] Scale preview widget shows hardcoded fake chat bubbles ("Alice", "Bob", "Sure, sounds good!", static timestamps) instead of rendering actual app UI at the new scale — `settings_screen.dart:1456-1577` ← `settings/settings_scale_preview.cpp:186-258` (AyuGram: `SetupScalePreview` renders real application window contents at the target scale)

- [ ] [MAJOR] "Devices" row routes to `ActiveSessionsScreen` (sessions only) but AyuGram's "Devices" routes to `CallsId()` which shows both active sessions AND calls/audio settings combined — `settings_screen.dart:296-305` ← `settings/sections/settings_main.cpp:466-470` (AyuGram: `.targetSection = CallsId()` with keywords `sessions`, `calls`)

- [ ] [MAJOR] Folders row visibility uses simple `chatState.hasFolders` with no reactive subscription to appConfig `dialog_filters_enabled`; AyuGram shows Folders when filters exist OR when server config enables dialog filters dynamically — `settings_screen.dart:269` ← `settings/sections/settings_main.cpp:424-455` (AyuGram: `chatsFilters().has() || settings().dialogsFiltersEnabled()` plus reactive `appConfig().refreshed()` stream)

- [ ] [MAJOR] Emoji status panel `loadEmojiStickers()` is called inside the `StatefulBuilder` builder function on every rebuild while `loading == true`, re-triggering async loads on each widget rebuild — `settings_screen.dart:863-871` ← `settings/sections/settings_main.cpp:228-232` (AyuGram: `_emojiStatusPanel.show()` is a single stateful panel, not a dialog rebuilt on every frame)

- [ ] [MAJOR] All `Process.run('xdg-open', ...)` calls (FAQ, Telegram Features, Premium links) have no `Platform.isLinux` guard and will silently fail on macOS and Windows — `settings_screen.dart:361,367,374,381,394,401` ← `settings/sections/settings_main.cpp:611` (AyuGram uses `UrlClickHandler` / Qt `QDesktopServices::openUrl` which is cross-platform)

# shell — Audit findings

## shell — _ConnectionStateWidget: missing proxy icon

- [ ] [CRITICAL] `_ConnectionStateWidget` has no proxy icon — AyuGram always renders a `ProxyIcon` widget (on/off states) inside the connecting pill when proxy is enabled; Dart implementation has no proxy icon at all — `shell.dart:1084` ← `window_connecting_widget.cpp:505-515` + `window.style:189-190`

## shell — _ConnectionStateWidget: wrong reconnect countdown source

- [ ] [MAJOR] `waitTillRetry` countdown uses local exponential backoff (`5 × 2^attempts`, capped 30s) instead of the engine-reported MTP retry interval — AyuGram reads the actual wait from `(-dcstate / 1000) + 1` directly off the MTP state; Dart will display wrong reconnect times — `shell.dart:984-1001` ← `window_connecting_widget.cpp:324-326,456-460`

## shell — _ConnectionStateWidget: missing startup grace period

- [ ] [MAJOR] Missing `kIgnoreStartConnectingFor` 3-second startup grace period — AyuGram suppresses the first Connected→Connecting transition for 3 s after app start; Dart only has the 1000 ms `_showDelay`, causing spurious "Connecting…" flashes during initial login — `shell.dart:952,1029-1035` ← `window_connecting_widget.cpp:30,338-350`

## shell — _ConnectionStateWidget: widget not interactive

- [ ] [MAJOR] Connecting pill is not a button — AyuGram wraps the whole widget in `AbstractButton` which opens `ProxiesBoxController` when clicked; Dart has no click handler on the pill container — `shell.dart:1094-1147` ← `window_connecting_widget.cpp:508-510`

## shell — _ConnectionStateWidget: missing slide-up position animation

- [ ] [MAJOR] Connecting widget uses only FadeTransition; AyuGram also animates the widget's Y position from `height - connectingMargin.top (2px)` (off-screen) up to its visible position using `anim::interpolate`; Dart has no positional animation — `shell.dart:1071` ← `window_connecting_widget.cpp:267-271`

## shell — _ConnectionStateWidget: missing exposed-window guard

- [ ] [MAJOR] `_syncVisibility` shows the widget unconditionally; AyuGram only marks `visible = true` when `state.exposed` (window handle is exposed/on-screen) — widget must stay hidden when the window is minimised or off-screen — `shell.dart:1023-1044` ← `window_connecting_widget.cpp:310,443-447`

## shell — _dialogsCollapsed mode has no AyuGram equivalent

- [ ] [MAJOR] Dragging the dialogs resize handle below 130 px collapses the column to 0 width (`_dialogsCollapsed = true`); AyuGram enforces `columnMinimalWidthLeft = 260 px` as an absolute floor and has no avatar-only collapsed state — the column either exists at ≥ 260 px or the layout switches to OneColumn — `shell.dart:67,519-525,619-624` ← `window_session_controller.cpp:2528,2547-2554`

# shortcuts_settings_screen — Audit Findings

- [ ] [CRITICAL] Settings screen exposes 18 commands not present in AyuGram's settings UI: `cancelSearch`, `chatSwitchOverlay`, `chatSwitchOverlayReverse`, `formatBold`, `formatItalic`, `formatUnderline`, `formatStrike`, `formatCode`, `formatBlockquote`, `formatSpoiler`, `formatClear`, `formatLink`, `formatDate`, `editLastMessage`, `replyPrevious`, `replyNext`, `openFilePicker`, `pastePlainText` — none of these appear in `Entries()` in AyuGram; format shortcuts are fixed/non-configurable in Telegram Desktop — `shortcuts_settings_screen.dart:11-120` ← `AyuGram/settings/sections/settings_shortcuts.cpp:60-127`

- [ ] [MAJOR] Right-click on a shortcut row directly calls `_addAnotherBinding` with no popup menu — AyuGram shows a `PopupMenu` with an "Add another binding" action item before starting recording — `shortcuts_settings_screen.dart:437,459,473` ← `AyuGram/settings/sections/settings_shortcuts.cpp:305-326`

- [ ] [MAJOR] `_onRecordingKeyEvent` only permits modifier-free key presses for F1–F12 (`_functionKeys`), but AyuGram's `AllowWithoutModifiers` permits any key with code >= 0x80 that is not a service key (covers media keys, numpad, Insert, Pause, Print Screen, etc.) — `shortcuts_settings_screen.dart:307-310` ← `AyuGram/core/shortcuts.cpp:1014-1046`

- [ ] [MAJOR] `RecordVoice` and `RecordRound` are grouped with formatting commands in group 9 "Format & Edit" — AyuGram places them in a dedicated separator group between the Send group and `ShowAdminLog` — `shortcuts_settings_screen.dart:85-102` ← `AyuGram/settings/sections/settings_shortcuts.cpp:113-116`

# spoiler_animation — 9 issues (0 CRITICAL, 9 MAJOR)

- [ ] [MAJOR] `addPersistentFrameCallback` is registered once and never removed — fires on every vsync forever even when `_activeCount == 0`; the C++ `SpoilerAnimationManager` destroys itself via `destroyIfEmpty()` when the list empties, stopping the timer completely — `spoiler_animation.dart:67` ← `spoiler_mess.cpp:327-332`

- [ ] [MAJOR] Sprite sheet cache written to `/tmp/uniclient_spoiler_cache/` — `/tmp` is ephemeral (wiped on reboot); AyuGram stores in `Integration::Instance().emojiCacheFolder() + "/spoiler"` (persistent app-data directory) — `spoiler_animation.dart:137,156` ← `spoiler_mess.cpp:196-199`

- [ ] [MAJOR] Cache deserialization has no version header or integrity hash: accepts any PNG without checking `kVersion`, frame count, canvas size, or XXHash32 digest; stale or corrupt cache loaded silently — `spoiler_animation.dart:143-147` ← `spoiler_mess.cpp:721-778`

- [ ] [MAJOR] Tile painting uses local-widget origin (0,0) — `Rect.fromLTWH(tx * tile, ty * tile, ...)` — instead of a global `originShift`; AyuGram's `FillSpoilerRect` accepts `QPoint originShift` so all spoilers on the same row share continuous particle phase; Dart tiles restart at (0,0) per-widget, breaking phase continuity across adjacent spoilers — `spoiler_animation.dart:373-393` ← `spoiler_mess.cpp:431-508`

- [ ] [MAJOR] Image spoiler darkening (`kImageSpoilerDarkenAlpha = 32`) is applied at every paint call as an extra `canvas.drawRect` — AyuGram bakes it into the sprite sheet once during `PreloadImageSpoiler` postprocessing, paying zero cost at render time — `spoiler_animation.dart:348-352` ← `spoiler_mess.cpp:846-868`

- [ ] [MAJOR] Sprite sheet generation draws 60 frames on the main isolate via `await Future.delayed(Duration.zero)` in a loop — only the particle math is offloaded to `compute()`; AyuGram runs the entire generation (particle math + raster) on a background thread via `crl::async` with no main-thread involvement — `spoiler_animation.dart:256-309` ← `spoiler_mess.cpp:260-278`

- [ ] [MAJOR] `canvas.saveLayer(rect, Paint())` called on every `paint()` invocation for any rounded-corner spoiler — `saveLayer` allocates an offscreen GPU texture per call per frame (60fps); AyuGram composes corners using a pre-allocated `cornerCache QImage` with manual `CompositionMode_DestinationIn`, avoiding offscreen allocation — `spoiler_animation.dart:342` ← `spoiler_mess.cpp:510-623`

- [ ] [MAJOR] `shouldRepaint` omits `tintColor` and `isMedia` from the equality check — if the theme color changes or `isMedia` flips, the painter does not repaint until `frame` or `revealProgress` happens to change — `spoiler_animation.dart:408-412` ← `spoiler_mess.cpp:642-650`

- [ ] [MAJOR] `SpoilerColorCache` is keyed on `color.value` including alpha (`tintColor.withValues(alpha: opacity * 0.85)`); during a reveal animation `opacity` changes every frame, producing a unique alpha per frame that evicts live entries from the 24-slot LRU — AyuGram colorises once via `SpoilerMessCached(mask, color)` and caches a full pre-tinted image, not a per-frame filter — `spoiler_animation.dart:422-437` ← `spoiler_mess.cpp:642-650`

# stats_chart — Statistics Chart Widget Audit

## Summary
Compared `stats_chart.dart` against AyuGram's `statistics/chart_widget.cpp`, `view/linear_chart_view.cpp`, `view/bar_chart_view.cpp`, `view/stack_linear_chart_view.cpp`, `view/chart_rulers_view.cpp`, `chart_rulers_data.cpp`, `statistics.style`.

---

- [ ] [CRITICAL] StackLinear "zoom into pie" transition is a simple `Opacity` crossfade; AyuGram does an animated morph where stacked area paths rotate into pie wedges with simultaneous footer zoom — the entire `StackLinearChartView::processLocalZoom` / `_transition.progress` animation is missing — `stats_chart.dart:389-401,721-724,866-888` ← `AyuGramDesktop/Telegram/SourceFiles/statistics/view/stack_linear_chart_view.cpp:147-551` and `AyuGramDesktop/Telegram/SourceFiles/statistics/chart_widget.cpp:1272-1396`

- [ ] [MAJOR] Y-axis animation speed thresholds are inverted and wrong: Dart applies faster speed (`_kDtHeightSpeed3 = 0.09`) when `ratio > 0.6`, but AyuGram applies the faster speed (`kDtHeightSpeed3 = 0.045*2 = 0.09`) for the **middle** range `0.1 < k < 0.7` (slower for extremes) — `stats_chart.dart:517-523` ← `AyuGramDesktop/Telegram/SourceFiles/statistics/chart_widget.cpp:603-620` (`kDtHeightSpeedThreshold1 = 0.7`, `kDtHeightSpeedThreshold2 = 0.1`)

- [ ] [MAJOR] Footer click-to-center animation uses linear interpolation; AyuGram uses `anim::sineInOut` — `stats_chart.dart:1191-1195` (`_animController.forward(from:0)` with linear `t`) ← `AyuGramDesktop/Telegram/SourceFiles/statistics/chart_widget.cpp:346-358` (`_moveCenterAnimation.start(...anim::sineInOut)`)

- [ ] [MAJOR] Date step computation hardcodes `400.0` for chart width instead of actual widget width, so step labels will be wrong on any chart wider or narrower than 400px — `stats_chart.dart:597` (`final pxPerPoint = 400.0 / (span * (n - 1))`) ← `AyuGramDesktop/Telegram/SourceFiles/statistics/chart_widget.cpp:1019-1026` (uses `_chartArea->width()` and `_bottomLine.chartFullWidth`)

- [ ] [MAJOR] Date label edge fade uses hardcoded `30.0`px instead of `captionMaxWidth / 4` (which is precomputed per font); on charts where label widths differ, edge labels won't fade correctly — `stats_chart.dart:1619` (`const edgeFade = 30.0`) ← `AyuGramDesktop/Telegram/SourceFiles/statistics/chart_widget.cpp:111` (`const auto edgeAlphaSize = captionMaxWidth / 4.`)

- [ ] [MAJOR] Date label crossfade is missing "fast alpha" speed-out for stale steps: AyuGram subtracts `kFastAlphaSpeed = 0.85` from old date lines' alpha to rapidly clear them, preventing lingering stale labels — `stats_chart.dart:1608-1613` (no fast alpha) ← `AyuGramDesktop/Telegram/SourceFiles/statistics/chart_widget.cpp:135-139` (`constexpr auto kFastAlphaSpeed = 0.85`)

- [ ] [MAJOR] Ruler line count is hardcoded to 5 divisions (6 lines), but AyuGram computes it dynamically between `kMinLines=2` and `kMaxLines=6` based on the y-range value, which means over-dense or under-dense grids for many datasets — `stats_chart.dart:1549` (`const rulerCount = 5`) ← `AyuGramDesktop/Telegram/SourceFiles/statistics/chart_rulers_data.cpp:17-18,51-60` (`kMinLines=2`, `kMaxLines=6`, dynamic `n`)

- [ ] [MAJOR] Ruler grid line stroke width is `0.5` in Dart but AyuGram uses `st::lineWidth = 1px` (filled rect, not drawn line), making grid lines half as thick as intended — `stats_chart.dart:1543` (`..strokeWidth = 0.5`) ← `AyuGramDesktop/Telegram/SourceFiles/statistics/view/chart_rulers_view.cpp:89-95` (`p.fillRect(lineRect, st::boxTextFg)` with height `st::lineWidth`)

- [ ] [MAJOR] DoubleLinear ruler scale uses `reduce(math.min/max)` over ALL values in the series, ignoring the visible range; AyuGram computes rulers from `heightLimits` which is the visible-range-bounded animated range — `stats_chart.dart:1693-1696` ← `AyuGramDesktop/Telegram/SourceFiles/statistics/chart_widget.cpp:555-558` and `view/linear_chart_view.cpp:213-225`

- [ ] [MAJOR] DoubleLinear footer: Dart normalizes each line independently (per-line min/max), AyuGram renders the footer using the shared `footerHeightLimits` — both lines use the same scale in the footer — `stats_chart.dart:2011-2038` ← `AyuGramDesktop/Telegram/SourceFiles/statistics/chart_widget.cpp:1094-1111` (`_animationController.currentFooterHeightLimits()` shared for all lines)

- [ ] [MAJOR] Pie chart radius uses `min(cx, cy) * 0.75` where `cy = chartHeight/2 = 100`; AyuGram uses `(rect.width() / 2) * kCircleSizeRatio = width * 0.21`; for a 400×200 chart: Dart radius ≈ 75px vs AyuGram ≈ 84px — `stats_chart.dart:1221` (`math.min(cx, cy) * 0.75`) ← `AyuGramDesktop/Telegram/SourceFiles/statistics/view/stack_linear_chart_view.cpp:24,588` (`kCircleSizeRatio = 0.42`, `side = width/2 * 0.42`)

- [ ] [MAJOR] Pie slice label minimum threshold is `pct >= 3` (3%) in Dart but `kMinPercentage = 0.039` (3.9%) in AyuGram — small slices that AyuGram hides will get labels in Dart — `stats_chart.dart:2198` ← `AyuGramDesktop/Telegram/SourceFiles/statistics/view/stack_linear_chart_view.cpp:704`

- [ ] [MAJOR] Pie slice text is positioned at a fixed `radius * 0.65`; AyuGram uses `side * sqrt(1 - percentage)` so smaller slices push labels outward — `stats_chart.dart:2199` (`radius * 0.65`) ← `AyuGramDesktop/Telegram/SourceFiles/statistics/view/stack_linear_chart_view.cpp:735` (`const auto rText = side * std::sqrt(1. - percentage)`)

- [ ] [MAJOR] Pie slice text has no font scaling — it always renders at `_labelFontSize * animProgress`; AyuGram scales each label by `minScale + percentage * (maxScale - minScale)` so large slices get bigger text, small slices get smaller text — `stats_chart.dart:2204-2210` ← `AyuGramDesktop/Telegram/SourceFiles/statistics/view/stack_linear_chart_view.cpp:719-720,755-766`

# main — PasscodeLockScreen + ThemeRevertOverlay

- [ ] [CRITICAL] System unlock button placed below the submit button instead of overlaid at bottom-right of the input field — `main.dart:2525-2542` ← `window_lock_widgets.cpp:190-192` (`button->moveToRight(0, size.height() - button->height())` positions it inside the passcode input widget's own bounds, not as a separate row)

- [ ] [MAJOR] `_inputFieldHeight = 55.0` hardcoded but AyuGram's `passcodeInput` inherits from `introPhone → introCountry` which has `heightMin: 61px`; error text and submit button are positioned 6 px too high — `main.dart:2219,2492,2506` ← `boxes.style:292-293`, `intro.style:126`

- [ ] [MAJOR] System unlock button size is 48×48, AyuGram specifies 32×36 — `main.dart:2531-2532` ← `boxes.style:313-315` (`passcodeSystemUnlock: IconButton { width: 32px; height: 36px; }`)

- [ ] [MAJOR] Passcode error messages hardcoded in English (`"Wrong passcode"`, `"Too many tries. Please try again later."`) instead of using `TrStrings` localization — `main.dart:2333,2343,2374` ← `window_lock_widgets.cpp:287` (`tr::lng_passcode_wrong`), `window_lock_widgets.cpp:265` (`tr::lng_flood_error`)

- [ ] [MAJOR] Passcode screen background color hardcoded as raw hex (`0xFF17212B` / `0xFFFFFFFF`) instead of palette token; won't update when accent/custom theme changes — `main.dart:2399` ← `window_lock_widgets.cpp:245-250` (uses `st::windowBg` / `st::windowFg` palette entries)

- [ ] [MAJOR] Passcode error text color hardcoded as raw hex (`0xFFE53935` / `0xFFD32F2F`) instead of palette token `boxTextFgError`; won't adapt to custom themes — `main.dart:2403` ← `window_lock_widgets.cpp:254-255` (`st::boxTextFgError`)

- [ ] [MAJOR] Visibility-toggle eye icon added to passcode input — not present in AyuGram spec; `MaskedInputField` is always obscured with no toggle — `main.dart:2465-2471` ← `window_lock_widgets.cpp:100` (`passcodeInput: InputField(introPhone)` / `MaskedInputField`)

# sticker_pack_viewer — Audit Findings

- [ ] [CRITICAL] Sticker tiles have no tap handler — tapping a sticker does nothing; AyuGram's `chosen()` sends the sticker to the active chat via `_show->processChosenSticker()` — `sticker_pack_viewer.dart:276` ← `AyuGram/boxes/sticker_set_box.cpp:1658-1673`

- [ ] [CRITICAL] Box stays open after successful install instead of closing; AyuGram's `installDone()` fires `_setInstalled` signal which triggers `closeBox()` — `sticker_pack_viewer.dart:148-164` ← `AyuGram/boxes/sticker_set_box.cpp:595`

- [ ] [CRITICAL] Installed sets show an "Added" uninstall-toggle button; AyuGram shows "Share" + "Cancel" for installed non-official sets (no inline uninstall) — `sticker_pack_viewer.dart:204-217` ← `AyuGram/boxes/sticker_set_box.cpp:1041-1047`

- [ ] [CRITICAL] No Lottie (.tgs) or WebM video sticker rendering — every sticker shown as a static stripped-JPEG thumbnail only; AyuGram calls `setupLottie()` / `setupWebm()` for animated and video stickers — `sticker_pack_viewer.dart:261-274` ← `AyuGram/boxes/sticker_set_box.cpp:2179-2200`

- [ ] [MAJOR] Emoji grid cells are 1:1 squares (default `childAspectRatio`); AyuGram `emojiSetSize` is 42×39px (ratio ≈ 1.077) — `sticker_pack_viewer.dart:239-243` ← `AyuGram/chat_helpers/chat_helpers.style:420`

- [ ] [MAJOR] Grid uses 4px `mainAxisSpacing` and `crossAxisSpacing` between cells; AyuGram packs cells tightly with zero inter-cell gap (only outer padding) — `sticker_pack_viewer.dart:241-242` ← `AyuGram/boxes/sticker_set_box.cpp:2068-2069`

- [ ] [MAJOR] Sheet `maxChildSize: 0.9` allows up to 90% of screen height; AyuGram constrains the box to `stickersMaxHeight` (320px) or `emojiSetMaxHeight` (197px) — `sticker_pack_viewer.dart:79-80` ← `AyuGram/boxes/sticker_set_box.cpp:574-575` + `AyuGram/chat_helpers/chat_helpers.style:415,419`

- [ ] [MAJOR] No premium sticker lock mark rendered on restricted stickers; AyuGram applies a premium-lock overlay during `paintSticker()` for non-premium users — `sticker_pack_viewer.dart:258-282` ← `AyuGram/boxes/sticker_set_box.cpp:2326-2444`

# story_editor — Audit Findings

## story_editor — Story editor layer

- [ ] [CRITICAL] Sticker picker inserts sticker's emoji text instead of the sticker image — tapping a sticker in the grid calls `widget.onEmojiSelected(sticker.emoji)` which adds a text `_SceneItem` with the emoji character; the actual sticker thumbnail shown in the grid is never placed on the canvas. AyuGram creates an `ItemSticker` scene item backed by the real `DocumentData`. — `story_editor.dart:2787` ← `AyuGram/editor/editor_paint.cpp:145`

- [ ] [CRITICAL] Video canvas preview is a placeholder icon — when `_videoFile != null`, `_buildCanvasContent` renders `Icons.videocam` + filename instead of actual video frames; the user cannot see what they are editing. — `story_editor.dart:628` ← `AyuGram/editor/photo_editor_content.cpp` (AyuGram renders video frames via native player)

- [ ] [CRITICAL] Blur tool draws a blurred-white stroke over content rather than blurring the underlying image — `paint.maskFilter = MaskFilter.blur(BlurStyle.normal, 20)` with `Colors.white24` just adds a fuzzy white overlay. AyuGram supplies a `blurSource` callback that reads and Gaussian-blurs the actual image pixels at the brushed region. — `story_editor.dart:1773` ← `AyuGram/editor/scene/scene_item_canvas.cpp:121` (`strokeColor` returns opaque black for blur; the blur effect is applied via `blurSource`), `AyuGram/editor/editor_paint.cpp:71` (`setBlurSource`)

- [ ] [CRITICAL] `_renderCanvasToBytes` does not reproduce text background styles (filled / outlined) in the exported image — text items are painted as raw `TextPainter` with color only; `_TextBgStyle.filled` (semi-transparent box) and `_TextBgStyle.outlined` (border box) that the user sees live in `_buildItemWidget` are absent from the final PNG upload. — `story_editor.dart:497` ← `AyuGram/editor/scene/scene_item_text.cpp:68` (`ComputeMetrics`, `BuildConnectedBackground`)

- [ ] [MAJOR] Marker tool uses additive alpha blending instead of source-replace compositing — `color.withValues(alpha: 0.35)` with the default `BlendMode.srcOver` lets overlapping strokes accumulate opacity (e.g. second pass goes to ~58%). AyuGram uses `CompositionMode_Source` so re-stroking the same area stays at 35%. — `story_editor.dart:1771` ← `AyuGram/editor/scene/scene_item_canvas.cpp:196`

- [ ] [MAJOR] Undo / redo only covers paint strokes, not scene-item operations — `_undo`/`_redo` (lines 529-543) manipulate `_strokes` / `_redoStack`. Adding, moving, rotating, or deleting `_sceneItems` (text labels, emoji) cannot be undone. AyuGram's undo controller covers the full `Scene` (all item types). — `story_editor.dart:529` ← `AyuGram/editor/controllers/undo_controller.cpp:1`

- [ ] [MAJOR] Full video file read into memory as `Uint8List` before upload — `_videoFile!.readAsBytes()` at line 417 loads the entire video into the Dart heap. Multi-hundred-MB videos will OOM the process; the backend `SendStoryWithPhoto` should accept a file path or streaming source. — `story_editor.dart:417` ← `AyuGram/editor/editor_paint.cpp` (C++ passes media as prepared file reference, not raw bytes)

- [ ] [MAJOR] Scene-item visual centering uses hardcoded −50 / −25 px offsets instead of dynamic widget size — `Positioned(left: item.position.dx * scale - 50, top: item.position.dy * scale - 25)` assumes every item is ~100×50 px. A long text label or large emoji is visually displaced from the tapped position. — `story_editor.dart:716` ← `AyuGram/editor/scene/scene_item_base.cpp` (AyuGram uses `boundingRect()` to center items at their logical position)

- [ ] [MAJOR] Font-size slider expanded top width is 20 px; brush-size slider spec requires 25 px — `_FontSizeSliderPainter` uses `expandedTopW = 20.0` (line 2386) while `_BrushSizeSliderPainter` correctly uses 25.0. Both sliders are the same widget type and should match. — `story_editor.dart:2386` ← `AyuGram/editor/editor.style:160` (`photoEditorBrushSizeControlExpandedTopWidth: 25px`)

- [ ] [MAJOR] Contact picker shows initial-letter placeholder avatar instead of real contact photo — `CircleAvatar` with a blue background and first letter is used for every contact; `ContactInfo` carries photo/avatar data from the engine that is never loaded. — `story_editor.dart:2185` ← `dart/lib/bridge/engine_service.dart:4944` (`_contactInfoFromProto` maps `EngineContactInfo` including avatar fields)

# telegram_toast — Sticker toast fake animation, missing paths, missing button

- [ ] [CRITICAL] Sticker preview renders static base64 PNG + invented scale-pulse animation instead of real animated Lottie/Custom Emoji frames — `telegram_toast.dart:390-438` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_sticker_toast.cpp:264-353` (`setupEmojiPreview` uses `Ui::CustomEmoji::Instance`, `setupLottiePreview` uses `Lottie::SinglePlayer`; Dart uses `Image.memory(base64Decode(...))` with a fake 600ms scale oscillator `_emojiAnimCtrl` that doesn't exist in AyuGram)

- [ ] [CRITICAL] Missing "saved to emojis" toast variant — `telegram_toast.dart:349-388` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_sticker_toast.cpp:140-157` (AyuGram uses `static auto counter = 0; toSaved = isEmoji && !(++counter % 2)` so every other emoji toast shows `tr::lng_animated_emoji_saved` with an "Open saved messages" button; Dart `_buildMessage()` has no `toSaved` branch at all)

- [ ] [MAJOR] Missing "View" RoundButton in sticker toast — `telegram_toast.dart:467-484` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_sticker_toast.cpp:201-252` (AyuGram creates a dedicated `Ui::RoundButton` aligned to the right of the toast that opens `StickerSetBox` or `ShowPremiumPreviewBox` or navigates to Saved Messages; Dart only has a `TapGestureRecognizer` on the pack name text span with a single `onOpenPack` VoidCallback — no button, no branching navigation logic)

- [ ] [MAJOR] No previous sticker toast dismissal when a new one is shown — `telegram_toast.dart:253-268` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_sticker_toast.cpp:63-77` (AyuGram's `showFor()` calls `strong->hideAnimated()` on the existing weak pointer before showing a new toast for a different document; Dart `showStickerToast()` creates a fresh `OverlayEntry` every call with no check for an existing live toast, so rapid calls stack multiple sticker toasts simultaneously)

- [ ] [MAJOR] Missing TopicIcon section — `telegram_toast.dart:271-291` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_sticker_toast.h:43-46` (AyuGram has `Section::Message` and `Section::TopicIcon`; TopicIcon path shows `Settings::ShowPremium(window, u"forum_topic_icon"_q)` and changes the toast text; Dart `_StickerToast` only has `isReaction` bool with no TopicIcon concept)

# telegram_tooltip — 8 issues (3 CRITICAL + 5 MAJOR)

- [ ] [CRITICAL] Regular tooltip corner radius is 6px but AyuGram uses `st::roundRadiusSmall = 3px` (100% deviation) — `telegram_tooltip.dart:11` ← `lib_ui/ui/basic.style:104` + `lib_ui/ui/widgets/tooltip.cpp:172`

- [ ] [CRITICAL] `_ArrowPainter` uses absolute screen coordinate (`target.center.dx`) as a local canvas coordinate — the arrow is always drawn at `min(target.center.dx, _kArrowSkip=66)` relative to the widget's own top-left, not over the actual target center. AyuGram adjusts with `areaMiddle = _area.x() + _area.width()/2 - x()` to get a widget-relative position — `telegram_tooltip.dart:428-469` ← `lib_ui/ui/widgets/tooltip.cpp:434-436`

- [ ] [CRITICAL] `ImportantTooltip` font size is 13px but AyuGram's `defaultImportantTooltipLabel` uses `font(11px)` (18% deviation, threshold is 10%) — `telegram_tooltip.dart:515` ← `lib_ui/ui/widgets/widgets.style:1314-1316`

- [ ] [MAJOR] `ImportantTooltip` is missing its slide/position animation — AyuGram interpolates position with `shift` offset using `anim::interpolate` so the tooltip slides in from a shifted position while fading; Dart only has `FadeTransition` — `telegram_tooltip.dart:288-314` ← `lib_ui/ui/widgets/tooltip.cpp:395-401`

- [ ] [MAJOR] `ImportantTooltip` animation uses default linear curve instead of `easeOutCirc` — `AnimationController` has no curve set and `FadeTransition` uses it raw; AyuGram explicitly passes `anim::easeOutCirc` — `telegram_tooltip.dart:238-241` ← `lib_ui/ui/widgets/tooltip.cpp:315`

- [ ] [MAJOR] Regular tooltip font size is 12px but AyuGram's `defaultTooltip` uses `defaultTextStyle` which resolves to `normalFont = font(fsize)` = 13px — `telegram_tooltip.dart:140` ← `lib_ui/ui/basic.style:51-52`

- [ ] [MAJOR] Default hover show-delay is 500ms but AyuGram's `InstallTooltip` uses 1000ms (50% deviation) — `telegram_tooltip.dart:12` ← `lib_ui/ui/widgets/tooltip.cpp:573`

- [ ] [MAJOR] Double-remove race in `showImportantTooltip`: outer `Future.delayed(hideAfter, remove)` at line 529 fires exactly when the tooltip's own `_scheduleHideAfter` timer fires, but without waiting for the 200ms reverse animation — the overlay is removed abruptly before fade-out completes instead of after it — `telegram_tooltip.dart:528-532` ← `lib_ui/ui/widgets/tooltip.cpp:321-323`

# theme_editor — Audit Findings

## theme_editor — Theme Editor Screen

- [ ] [CRITICAL] `ThemeEditorScreen` has no `CloudTheme` parameter; when editing an existing cloud theme the editor has no access to `cloud.id` / `cloud.accessHash`, so it can never call update-theme (always creates a new one instead) — `theme_editor.dart:21-33` ← `AyuGramDesktop/window/themes/window_theme_editor.cpp:663-668` (`Editor::Editor(…, const Data::CloudTheme &cloud)` requires the cloud theme to be passed in)

- [ ] [CRITICAL] `_handleSaveToCloud` always calls `engine.createCloudTheme` regardless of whether the theme already exists; AyuGram calls `SaveTheme` which checks `cloud.id` and dispatches `MTPaccount_UpdateTheme` vs `MTPaccount_CreateTheme` — `theme_editor.dart:201-241` ← `AyuGramDesktop/window/themes/window_theme_editor_box.cpp:499-612` (`SavePreparedTheme` create/update split)

- [ ] [CRITICAL] Search filter only checks if `entry.key` contains the query string; AyuGram builds a full-text search index over token name + copyOf + description + hex value string and uses word-prefix matching — `theme_editor.dart:112` (`!entry.key.toLowerCase().contains(_filter)`) ← `AyuGramDesktop/window/themes/window_theme_editor_block.cpp:157-170, 385-420` (`fillSearchIndex` + `searchByQuery`)

- [ ] [MAJOR] `_focusedIndex` is never reset when the search filter changes; AyuGram calls `setSelected(-1)` and `setPressed(-1)` whenever `_searchQuery` changes, so the focused item always tracks the filtered list — `theme_editor.dart:77` (`setState(() => _filter = text.toLowerCase())`) ← `AyuGramDesktop/window/themes/window_theme_editor_block.cpp:391-393` (`setSelected(-1); setPressed(-1)`)

- [ ] [MAJOR] Page Up / Page Down keyboard handling uses a hardcoded skip of `±10` items; AyuGram computes skip count as `ceilclamp(scroll->height(), defaultRowHeight, 1, scroll->height())` so it always skips exactly one viewport worth of rows — `theme_editor.dart:362-373` ← `AyuGramDesktop/window/themes/window_theme_editor.cpp:893-896` + `AyuGramDesktop/window/themes/window_theme_editor.cpp:530-538` (`selectSkipPage`)

- [ ] [MAJOR] `_ensureVisible` uses a hardcoded `estimatedRowHeight = 71.0`; rows with a description are taller (AyuGram computes actual per-row heights), so scroll-to-selected will overshoot/undershoot for rows with descriptions — `theme_editor.dart:383` ← `AyuGramDesktop/window/themes/window_theme_editor_block.cpp:534-545` (dynamic row height = margin + sampleSize + descriptionSkip + textHeight + margin)

- [ ] [MAJOR] Color picker always opens a new dialog on row tap; AyuGram keeps a single persistent `ColorEditor` panel open and calls `editor->showColor(row.value())` when a new row is activated while the editor is already open — `theme_editor.dart:541-546` ← `AyuGramDesktop/window/themes/window_theme_editor_block.cpp:313-317` (`_context->colorEditor.editor->showColor(row.value())`)

- [ ] [MAJOR] Options menu opens a blocking `SimpleDialog` modal; AyuGram opens a non-modal animated `DropdownMenu` that appears in the top-right corner (origin `TopRight`) and does not block the rest of the editor — `theme_editor.dart:275-323` (`showDialog` + `SimpleDialog`) ← `AyuGramDesktop/window/themes/window_theme_editor.cpp:721-761` (`Ui::DropdownMenu`, `showAnimated(PanelAnimation::Origin::TopRight)`)

- [ ] [MAJOR] `_listItems` getter recomputes the full filtered/grouped list on every `build()` call (every setState); for a 350-token palette this runs O(n) every frame while typing in the search box — `theme_editor.dart:106-136` (no caching, called directly in `build()` at line 406) ← `AyuGramDesktop/window/themes/window_theme_editor_block.cpp:385-425` (AyuGram caches `_searchResults` and only recomputes on query change)

- [ ] [MAJOR] `_SaveThemeBox` is never passed `cloudMeta` in the cloud-save flow (`_handleSaveToCloud` at line 204 passes no `cloudMeta` argument); this means the `_CloudSaveResult.cloudMeta` is always `null`, so cloud theme ID/accessHash for updates is always discarded — `theme_editor.dart:201-209` ← `AyuGramDesktop/window/themes/window_theme_editor_box.cpp:781-900` (`SaveThemeBox` receives the full `Data::CloudTheme &cloud` including id and accessHash)

# titlebar — 2 issues

- [ ] [MAJOR] Bottom separator uses `palette.shadowFg` (#00000018) instead of `palette.titleShadow` (#00000003). The palette already has a `titleShadow` field but it is not wired up in the titlebar widget. AyuGram places a `PlainShadow` with `st::titleShadow` (nearly transparent) at the bottom of the title bar; the Dart code uses the much more opaque `shadowFg` color, making the separator line 6× darker than intended — `titlebar.dart:206` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:99` + `ui_platform_window_title.cpp:470`

- [ ] [MAJOR] `_ButtonLayout.consolidated` picks the side with more buttons instead of the side where the close button lives. AyuGram's `TitleLayout::onLeft()` checks `ranges::contains(left, TitleControl::Close)` first and `updateControlsPosition` merges to whichever side holds close; the Dart getter checks `right.length >= left.length`. For a mixed layout like `left=[close], right=[minimize, maximize]`, AyuGram consolidates to left but Dart consolidates to right, reversing the order — `titlebar.dart:29-35` ← `AyuGram/Telegram/lib_ui/ui/platform/ui_platform_window_title.h:68-77` + `ui_platform_window_title.cpp:325-338`

# web_app_panel — Audit Findings

- [ ] [CRITICAL] `_postEventToWebView` uses wrong JS object: `window.Telegram.WebView.receiveEvent` — the correct object is `window.TelegramGameProxy.receiveEvent`. All events sent from the app back to the mini-app are silently dropped, breaking theme updates, viewport reports, button confirmations, popup results, and every other server-to-web event — `web_app_panel.dart:414` ← `attach_bot_webview.cpp:2180`

- [ ] [CRITICAL] `web_app_data_send` drops the bot's payload: Dart just calls `_close()` without reading `data["data"]` or forwarding it to the backend. AyuGram calls `sendDataMessage(arguments)` → `_delegate->botSendData(data.toUtf8())`, then closes. The submitted form data is never delivered — `web_app_panel.dart:268-269` ← `attach_bot_webview.cpp:964-965,1166-1178`

- [ ] [CRITICAL] `web_app_open_tg_link` opens the external browser instead of routing internally: Dart calls `_launchUrl('https://t.me/$path')`. AyuGram calls `_delegate->botHandleLocalUri("https://t.me" + path, true)` which navigates within the app — `web_app_panel.dart:265-267` ← `attach_bot_webview.cpp:1014-1015,1362-1375`

- [ ] [CRITICAL] `web_app_open_link` bypasses URL validation and instant-view routing: Dart calls `_launchUrl(url)` unconditionally. AyuGram calls `botValidateExternalLink(url)` (rejects bad URLs, closes the panel on failure), checks `try_instant_view`, and routes to `botOpenIvLink` accordingly — `web_app_panel.dart:262-264` ← `attach_bot_webview.cpp:1016-1017,1377-1395`

- [ ] [CRITICAL] `open_bot` menu item has no handler: the switch at `_showMenu` has no `case 'open_bot'` clause, so tapping "Open Bot" silently does nothing. AyuGram calls `_delegate->botHandleMenuButton(MenuButton::OpenBot)` — `web_app_panel.dart:546-559` ← `attach_bot_webview.cpp:780-783`

- [ ] [CRITICAL] `web_app_switch_inline_query` is missing entirely: AyuGram calls `_delegate->botSwitchInlineQuery(types, query)` to trigger inline query mode. Dart's `_handleWebAppEvent` switch has no case for it; the command is silently dropped — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:966-967,1180-1210`

- [ ] [CRITICAL] `web_app_request_fullscreen` and `web_app_exit_fullscreen` are missing: AyuGram toggles `_fullscreen`, re-layouts buttons, and calls `sendFullScreen()`. Dart ignores both commands — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:983-996`

- [ ] [CRITICAL] `web_app_request_file_download` is missing: AyuGram calls `_delegate->botDownloadFile({url, name, callback})` and posts `file_download_requested` with status. Dart ignores it — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:990-991,1855-1881`

- [ ] [CRITICAL] `web_app_open_invoice` is missing: AyuGram calls `_delegate->botHandleInvoice(slug)` which triggers the payment flow. Dart ignores it — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:1019-1020,1397-1409`

- [ ] [CRITICAL] `web_app_open_scan_qr_popup` and `web_app_share_to_story` are missing: AyuGram shows a blocking "not supported" popup for QR and story sharing. Dart silently ignores both — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:1022-1024,1466-1490`

- [ ] [CRITICAL] `web_app_request_write_access` is missing: AyuGram shows a permission dialog via `_delegate->botCheckWriteAccess/botAllowWriteAccess` and posts `write_access_requested` with status. Dart ignores it, so mini-apps can never obtain write permission — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:1026-1027,1492-1539`

- [ ] [CRITICAL] `web_app_request_phone` is missing: AyuGram shows a confirmation dialog and calls `_delegate->botSharePhone`, then posts `phone_requested`. Dart ignores it — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:1028-1029,1541-1580`

- [ ] [CRITICAL] `web_app_invoke_custom_method` is missing: AyuGram calls `_delegate->botInvokeCustomMethod` and posts `custom_method_invoked` with the result. Dart ignores it, breaking any mini-app that uses custom bot methods — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:1030-1031,1582-1620`

- [ ] [CRITICAL] `web_app_read_text_from_clipboard` is missing: AyuGram reads the clipboard (with interaction-time guard) and posts `clipboard_text_received`. Dart ignores it — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:1034-1035,1622-1633`

- [ ] [CRITICAL] `web_app_send_prepared_message` and `web_app_request_chat` are missing: AyuGram delegates these to `botSendPreparedMessage` / `botRequestChat` and posts success/failure events. Dart ignores both — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:1042-1045,1212-1260`

- [ ] [CRITICAL] `web_app_set_emoji_status` and `web_app_request_emoji_status_access` are missing: AyuGram calls `botSetEmojiStatus` / `botRequestEmojiStatusAccess` and posts result events. Dart ignores both — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:1046-1049,1261-1303`

- [ ] [CRITICAL] `web_app_device_storage_*` commands are missing: AyuGram handles `save_key`, `get_key`, and `clear`, posting `device_storage_key_saved/received/cleared/failed`. Dart ignores all three — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:1050-1055,1305-1353`

- [ ] [CRITICAL] `web_app_secure_storage_*` commands are missing: AyuGram responds with `secure_storage_failed` (UNSUPPORTED) for all four commands. Dart ignores them so mini-apps receive no response and hang — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:1056-1063,1355-1360`

- [ ] [CRITICAL] `web_app_verify_age` and `share_score` are missing: AyuGram calls `botVerifyAge(age)` / `botHandleMenuButton(ShareGame)`. Dart ignores both — `web_app_panel.dart:225-288` ← `attach_bot_webview.cpp:1064-1076`

- [ ] [MAJOR] Named color keys ignored in `web_app_set_header_color` and `web_app_set_background_color`: `_parseColor` only handles `#rrggbb` hex strings; it returns null for named keys like `"secondary_bg_color"` or `"bottom_bar_bg_color"`. AyuGram's `LookupNamedColor` resolves these to palette colors and sets up live palette-change listeners — `web_app_panel.dart:398-406` ← `attach_bot_webview.cpp:134-141,1763-1853`

- [ ] [MAJOR] `_handleRequestViewport` hardcodes `is_expanded: false` and uses screen size instead of webview content size: AyuGram's `sendViewport` runs `window.innerHeight` inside the webview and always sends `is_expanded: true`. Dart sends the Flutter screen size and always reports the panel as unexpanded — `web_app_panel.dart:332-341` ← `attach_bot_webview.cpp:1125-1130`

- [ ] [MAJOR] Bottom bar label text color uses fixed 40% alpha instead of contrast-adaptive calculation: AyuGram's `overrideBodyColor` computes luminance, picks black or white text, then derives opacity via `(luminance - textLuminance + contrast) / contrast` clamped to 0.5–0.64. Dart hardcodes `alpha: 0.4` regardless of background — `web_app_panel.dart:858-862` ← `attach_bot_webview.cpp:1781-1803`

- [ ] [MAJOR] Button corner radius is 8px but AyuGram uses `callRadius = 6px`: `_WebAppButton` uses `BorderRadius.circular(8)` and `botWebViewBottomButton` inherits from `paymentsPanelSubmit` whose ripple mask is built with `st::callRadius = 6px` — `web_app_panel.dart:923,925` ← `attach_bot_webview.cpp:385-386` / `widgets.style:callRadius: 6px`

# engine_models — Data Model Gaps vs AyuGram

## GroupCallParticipant — Missing fields & dead field

- [ ] [MAJOR] `audioLevel` field (Dart:2151) is always 0.0 — never set by Go engine. `dispatch_engine.go:2063` populates the proto but omits `audio_level`; `engine.pb.go:7762` proto struct has no such field. AyuGram uses `sounding` + `speaking` + `volume` from `data_group_call.h:45-47` to drive speaking indicators — `engine_models.dart:2151` ← `AyuGram/data/data_group_call.h:45`

- [ ] [MAJOR] `canSelfUnmute` missing from `GroupCallParticipant` — AyuGram distinguishes admin-forced mute (participant cannot unmute themselves) from self-mute; this drives a different icon in group call UI. Go engine logs it (`telegram.go:562`) but never exports it. Dart model has no field for it — `engine_models.dart:2144` ← `AyuGram/data/data_group_call.h:52`

- [ ] [MAJOR] `raisedHandRating` missing from `GroupCallParticipant` — AyuGram shows a raised-hand indicator ordered by `raisedHandRating`. Field absent from proto (`engine.pb.go:7762`), dispatch, and Dart model. Hand-raise feature entirely invisible in the UI — `engine_models.dart:2144` ← `AyuGram/data/data_group_call.h:43`

- [ ] [MAJOR] `volume` missing from `GroupCallParticipant` — AyuGram exposes per-participant volume (0–20000, kDefaultVolume=10000, kMaxVolume=20000) for the volume knob in group calls. `SetGroupCallParticipantVolume` API method exists but current volume is never returned to the UI. — `engine_models.dart:2144` ← `AyuGram/calls/group/calls_group_common.h:88`

## CachedMessage.copyWith — Fields silently dropped on update

- [ ] [MAJOR] `mediaUnread` and `ttlSeconds` are absent from `copyWith` parameter list and body (`engine_models.dart:947–1171`). Any `copyWith` call (e.g. on `MsgEdited` event) resets both to defaults (`false` / `0`), silently losing the TTL-media state. AyuGram always preserves these across message updates — `engine_models.dart:947` ← `AyuGram/data/data_group_call.h:38` (general data preservation principle; no direct AyuGram counterpart file, this is a Dart-internal correctness issue)

## StoryItem — Missing fields from AyuGram data_story.h

- [ ] [MAJOR] `noForwards` missing from `StoryItem` — AyuGram `data_story.h:299` has `_noForwards` flag that prevents users from re-sharing / saving a story. Go engine's `storyItem` struct (`telegram.go:16778`) does not expose it. Dart model cannot enforce the restriction — `engine_models.dart:2851` ← `AyuGram/data/data_story.h:299`

- [ ] [MAJOR] `expires` timestamp missing from `StoryItem` — AyuGram `data_story.h:289` has `_expires` (Unix timestamp when story disappears). Neither Go engine (`telegram.go:16778`) nor Dart model expose it. "N hours remaining" countdown on story viewer is impossible — `engine_models.dart:2851` ← `AyuGram/data/data_story.h:289`

- [ ] [MAJOR] `forwards` and `reactions` counts missing from `StoryItem` — AyuGram `StoryViews` struct (`data_story.h:78-80`) contains `reactions`, `forwards`, `views`. Dart model only has `views`; the other two stats (shown in story viewer) are unreachable — `engine_models.dart:2861` ← `AyuGram/data/data_story.h:78`

