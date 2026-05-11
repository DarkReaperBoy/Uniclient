# main — PasscodeLockScreen + ThemeRevertOverlay

- [ ] [CRITICAL] System unlock button placed below the submit button instead of overlaid at bottom-right of the input field — `main.dart:2525-2542` ← `window_lock_widgets.cpp:190-192` (`button->moveToRight(0, size.height() - button->height())` positions it inside the passcode input widget's own bounds, not as a separate row)

- [ ] [MAJOR] `_inputFieldHeight = 55.0` hardcoded but AyuGram's `passcodeInput` inherits from `introPhone → introCountry` which has `heightMin: 61px`; error text and submit button are positioned 6 px too high — `main.dart:2219,2492,2506` ← `boxes.style:292-293`, `intro.style:126`

- [ ] [MAJOR] System unlock button size is 48×48, AyuGram specifies 32×36 — `main.dart:2531-2532` ← `boxes.style:313-315` (`passcodeSystemUnlock: IconButton { width: 32px; height: 36px; }`)

- [ ] [MAJOR] Passcode error messages hardcoded in English (`"Wrong passcode"`, `"Too many tries. Please try again later."`) instead of using `TrStrings` localization — `main.dart:2333,2343,2374` ← `window_lock_widgets.cpp:287` (`tr::lng_passcode_wrong`), `window_lock_widgets.cpp:265` (`tr::lng_flood_error`)

- [ ] [MAJOR] Passcode screen background color hardcoded as raw hex (`0xFF17212B` / `0xFFFFFFFF`) instead of palette token; won't update when accent/custom theme changes — `main.dart:2399` ← `window_lock_widgets.cpp:245-250` (uses `st::windowBg` / `st::windowFg` palette entries)

- [ ] [MAJOR] Passcode error text color hardcoded as raw hex (`0xFFE53935` / `0xFFD32F2F`) instead of palette token `boxTextFgError`; won't adapt to custom themes — `main.dart:2403` ← `window_lock_widgets.cpp:254-255` (`st::boxTextFgError`)

- [ ] [MAJOR] Visibility-toggle eye icon added to passcode input — not present in AyuGram spec; `MaskedInputField` is always obscured with no toggle — `main.dart:2465-2471` ← `window_lock_widgets.cpp:100` (`passcodeInput: InputField(introPhone)` / `MaskedInputField`)
