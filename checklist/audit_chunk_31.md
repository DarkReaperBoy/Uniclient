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

- [ ] [CRITICAL] OTP auto-submit delayed 80ms vs AyuGram's immediate fire — `auth_screen.dart:1607` ← `intro_code_input.cpp:378-379`

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

- [ ] [CRITICAL] Step content uses 300px fields in 380px container; 80px wasted space — `auth_screen.dart:328,551` ← `intro.style:78`

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

- [ ] [CRITICAL] Phone validation missing check: if code focused + code.length>1 + phone empty, should focus phone — `auth_screen.dart:110-116` ← `intro_phone.cpp:166-179`

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

- [ ] [CRITICAL] Recovery mode switch doesn't clear password field or manage focus — `auth_screen.dart:822-829` ← `intro_password_check.cpp:291-310`

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

- [ ] [MAJOR] QR logo size (44px) may be too large for 180px QR code; AyuGram uses st::introQrCenterSize — `auth_screen.dart:891` ← `intro_qr.cpp:167-170`

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

- [ ] [MAJOR] Flood timer not cancelled when exiting 2FA step — `auth_screen.dart:272-277` ← `intro_phone.cpp:221-223`

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

- [ ] [MAJOR] OTP and password fields use different shake animations (8px vs 6px amplitude, 6π vs 4π frequency) — `auth_screen.dart:1799,544` ← `intro_code_input.cpp:48-54`

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

- [ ] [MAJOR] Password field text selection (line 296-298) not RTL-aware; selects 0→length regardless of text direction — `auth_screen.dart:296-298` ← No direct AyuGram parallel

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

- [ ] [MAJOR] Dialog for "didn't get code" switches method without API confirmation call — `auth_screen.dart:189-190` ← `intro_code.cpp:440-492` (different flow)

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

- [ ] [MAJOR] Avatar upload errors silently caught and ignored; no user feedback on failure — `auth_screen.dart:83-91` ← `intro_signup.cpp` (uses built-in UserpicButton with error handling)

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

- [ ] [MAJOR] Error top position hardcoded to 220px; should be 235px for main fields, 220px only below links — `auth_screen.dart:582` ← `intro.style:158-159`

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

- [ ] [MAJOR] Error-triggered state transitions missing: PASSWORD_EMPTY/AUTH_KEY_UNREGISTERED should goBack(), SRP_ID_INVALID needs retry logic — `auth_screen.dart:691-703` ← `intro_password_check.cpp:148-165`

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

