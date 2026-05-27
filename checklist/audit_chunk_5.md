# ayu_filter — Regex filter engine data layer

## Reference files
- Dart: `dart/lib/data/ayu_filter.dart`
- C++: `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_controller.cpp`
- C++: `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_utils.cpp`
- C++: `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_cache_controller.cpp`

---

- [ ] [MAJOR] `_serviceMessageType` falls through to `if (msg.mediaType == 2) return 8` which assigns TYPE_GIF (8) to service messages with video mediaType — no such mapping exists in AyuGram; the C++ `typeOfMessage` for service items checks `media->call()`, `media->photo()`, gift types, giveaway results, and then falls back to `return 10 // TYPE_DATE` with no video→GIF case — `ayu_filter.dart:243` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_utils.cpp:604`

- [ ] [MAJOR] `extractMatchBlob` single-message path does not trim text before appending to the match blob — AyuGram does `text = extractSingle(item).trimmed()` for both single and group items; Dart trims group items (`line 271`) but skips trim for single items (`line 278`), causing a divergence: patterns anchored with `^`/`$` or that rely on no leading whitespace behave differently for single messages — `ayu_filter.dart:278` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/features/filters/filters_utils.cpp:667`
