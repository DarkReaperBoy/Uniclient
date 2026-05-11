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
