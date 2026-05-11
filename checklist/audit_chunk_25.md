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
