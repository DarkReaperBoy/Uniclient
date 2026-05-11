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
