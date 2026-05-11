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
