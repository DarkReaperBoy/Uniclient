# GUI Audit — Cycle 0 Phase Ayugram (2026-05-31 12:01)

## Code Comparison (Dart vs AyuGram)

# auth_state — auth flow controller (intro/* state machine)

`auth_state.dart` is a `ChangeNotifier` controller, not a visual widget — it corresponds to AyuGram's `Intro::details` step controllers (`intro_phone/code/password_check/qr/signup/email`). Audit focuses on behavioral/wiring fidelity, not `.style` dimensions.

Scope notes (verified correct, no finding):
- SRP_ID_INVALID transparent-retry matches `handleSrpIdInvalid` (intro_password_check.cpp:169-179); 60s window == `kHandleSrpIdInvalidTimeout` (core_cloud_password.h:14).
- Resend / "I haven't received the code" / recovery / reset are wired via magic-string inputs through `submitInput` → engine (engine/auth.go:487-592); call countdown lives in the UI `CodeInputField`. Not a controller gap.
- QR scan-detection is event-driven through the engine push callback `onQRTokenUpdate` (engine/auth.go:140-162), mirroring `QrWidget::checkForTokenUpdate` (intro_qr.cpp:262-271); controller advances via `_handleAuthEvent`.
- No placeholders/stubs/TODOs/empty callbacks/fake data — every action calls the engine.

## Findings

# ayu_forward — intelligent forward (native + resend-as-own) routing & progress

Audited `dart/lib/state/ayu_forward.dart` against AyuGram's
`ayu/features/forward/ayu_forward.{cpp,h}` and the call sites that route into it
(`apiwrap.cpp`, `share_box.cpp`, `ayu/ui/context_menu/context_menu.cpp`).

**Wiring verified end-to-end (no stubs):** all three engine calls are real —
`engine.forwardMessages` → pending `ActionForwardBatch` → `ForwardMessagesWithOptions`
(native forward); `engine.resendAsOwn`/`resendAlbumAsOwn` → `executeResendAsOwn`/
`executeResendAlbum` which genuinely download the source media and re-upload it as a
new message (`go/engine/pending.go:875,1051`). The restriction flags driving the
routing (`noForwards`, `senderNoForwards`, `unsupportedTTL`, `ttlSeconds`, `isDeleted`)
are populated by the Go engine (`telegram.go:11211/11219/11783`,
`populateSenderNoForwards` at `cache_msgs.go:330`), so the feature is live, not dead
code. Chunking, restricted→resend / unrestricted→native routing, album grouping,
caption/silent/schedule plumbing, cancellation, and status/detail text all faithfully
mirror the C++. No placeholders, empty callbacks, TODOs, or mock data.

## Findings


# chat_state — chat list / active chat / messages / folders / forum / saved-sublists state (ChangeNotifier)

Audited `dart/lib/state/chat_state.dart` (2925 lines) against AyuGram Desktop C++ source.

## Verified correct (no action needed)
- Saved-sublist pagination constants match: `_kFirstPerPage=20` / `_kPerPage=100` / `_kLoadedSublistsMinCount=20` ← `data/data_saved_messages.cpp:31-34` (kListFirstPerPage/kListPerPage/kLoadedSublistsMinCount), `_kRecentSublistsMax=5` ← `data/data_saved_messages.cpp:35` (kShowSublistNamesCount).
- Recent forum topics cap `take(8)` ← `data/data_forum.cpp:44` (kShowTopicNamesCount=8). Forum pagination `>=20` first / `>=500` more ← `data/data_forum.cpp:40,42` (kTopicsFirstLoad=20, kTopicsPerPage=500).
- Message page sizes first 30 / then 50 ← `history/history_widget.cpp:216-217` (kMessagesPerPageFirst=30, kMessagesPerPage=50).
- `_maxChatOpenHistory=50` ← `window/window_session_controller.cpp:138` (kMaxChatEntryHistorySize=50).
- Typing-clear timeout 6s ← `history/view/history_view_send_action.cpp:31` (kStatusShowClientsideTyping=6*1000).
- No stubs, no placeholders, no mock data, no empty callbacks; all operations wired to `_engine`.

## Findings

- [ ] [MAJOR] Auto-download ignores the user's auto-download settings and hardcodes the policy — `_autoDownloadMedia` only ever downloads media types `{1 photo, 6 sticker, 7 gif}` plus videos `< 5MB`, never reading `_appState.getAutoDownloadForSource(...)` (which the settings UI persists and pushes to the engine via `SetAutoDownload`). Toggling "photos/videos/gifs/files" off or changing `downloadLimit` has no effect on this prefetch, and it does not distinguish source (it auto-downloads in channels too, where AyuGram defaults File/Music to 0). AyuGram gates every auto-download/auto-play through `Data::AutoDownload::Should()/ShouldAutoPlay()` reading per-source/per-type byte limits (default 12MB media / 50MB autoplay), not a fixed 5MB. — `chat_state.dart:2671-2682` (ignores `app_state.dart:2557` `getAutoDownloadForSource`) ← `AyuGram/data/data_auto_download.cpp:20-52` (kDefaultMaxSize=12MB, kDefaultAutoPlaySize=50MB, SetDefaultsForSource) + `AyuGram/data/data_auto_download.h:119-123` (ShouldAutoPlay).

- [ ] [MAJOR] Jump-to-message can only load OLDER messages, never newer — `jumpToMessage` loads a one-sided window with `getMessages(beforeMs: timestampMs + 1)` (older-than-target only) and sets `_hasMoreMessages = true`, but the only pagination path `loadMoreMessages → _loadMessages` also fetches older (`beforeMs: _messages.last.timestamp`). There is no "load newer / load down" path (confirmed: `engine_service.dart:2806` `getMessages` exposes only `beforeMs`, no `afterMs`/`aroundMs`). After jumping from a pinned-bar / reply / search result the user cannot scroll back toward the present except via `returnToLatest`, which discards the jumped position. AyuGram scrolls continuously in both directions around a shown message via `loadMessages()` + `loadMessagesDown()`. — `chat_state.dart:1662-1678` (jumpToMessage, beforeMs only) & `chat_state.dart:1549-1561,2133-2144` (loadMoreMessages → _loadMessages, older only) ← `AyuGram/history/history_widget.cpp:4464,4522` (loadMessages / loadMessagesDown).

- [ ] [MAJOR] Recent forum-topic names populated with pinned-first ordering instead of pure date order — `_checkAndOpenForum`, `openForum`, and `refreshForumTopics` set `_forumRecentTopics[key] = topics.take(8)` from the list AFTER `_sortTopics()`, which sorts pinned-first then by topMessageId. The on-demand `recentTopicsFor()` path sorts purely by topMessageId (date proxy), so the same forum row's recent-topic subtitle can render in two different orders depending on which path filled the cache. AyuGram's `reorderLastTopics()` builds the recent-names list with a pure date-descending comparator (no pinned priority). — `chat_state.dart:1144-1150,1183-1191,1239-1244` (sortTopics pinned-first → recent cache) vs `chat_state.dart:466-471` (recentTopicsFor, date order) ← `AyuGram/data/data_forum.cpp:233-268` (reorderLastTopics, date-only pred).

# telegram_palette — theme palette color tables + colorize/contrast engine

`telegram_palette.dart` defines 4 embedded palettes (`dayBlue`, `night`, `classicDay`,
`nightGreen`) plus the `colorize()` accent-recolor algorithm and `_enforceContrast()`
keep-contrast pass. Audited against AyuGram's `lib_ui/ui/colors.palette` (base/Classic
authority), the embedded `Telegram/Resources/{day-blue,night,night-green}.tdesktop-theme`
override files (the `colors.tdesktop-theme` inside each zip), and
`lib_ui/ui/style/style_palette_colorizer.cpp` + `window/themes/window_themes_embedded.cpp`.

**Method:** parsed each AyuGram palette (base + theme override, references resolved,
`#RRGGBBAA`→`0xAARRGGBB`) and each Dart block, then diffed key-by-key and bucketed by
perceptual RGB delta. Significant deviations: dayBlue 3, classicDay 7, night ~54, nightGreen
~148 (of ~573 shared keys). All hex values below verified against the raw extracted files.

**Algorithm is correct (no finding):** `colorize()` (telegram_palette.dart:1312-1373) faithfully
replicates `style_palette_colorizer.cpp:24-58` — piecewise saturation/value formulas, hue shift +
wrap, the HSL-lightness clamp (min 64 / max 160) from `window_themes_embedded.cpp:132-182`, and
`_enforceContrast()` (telegram_palette.dart:2506-2510) matches the `keepContrast` lightness-delta
≥ `kEnoughLightnessForContrast` (64) logic in `style_palette_colorizer.cpp:109-139`. The
`PaletteProvider` (telegram_palette.dart:5450) is a real `InheritedWidget`; no stubs/TODOs.

## Findings

- [ ] [CRITICAL] `nightGreen` (the default dark theme) broadly deviates from `night-green.tdesktop-theme`: ~148 perceptually-significant keys differ. Many keys were given the raw accent `0xFF3FC1B0` or the light/night palette's values instead of night-green's. e.g. `activeButtonBg` dart `0xFF3FC1B0` vs AyuGram `#2da192` — `telegram_palette.dart:4884` ← `Telegram/Resources/night-green.tdesktop-theme(colors.tdesktop-theme):20`
- [ ] [CRITICAL] `nightGreen` file-type background colors are wrong — and these are colorize-EXCLUDED (`kColorizeIgnoredKeys`, window_themes_embedded.cpp), so the palette value is the sole authority. `msgFile1Bg` dart `0xFF72B1DF` (blue, the light-theme value) vs AyuGram `#3fbbab` (teal); `msgFile2Bg` dart `0xFF61B96E` vs `#8ef5e8` — `telegram_palette.dart:5002` ← `Telegram/Resources/night-green.tdesktop-theme(colors.tdesktop-theme):300`
- [ ] [CRITICAL] `nightGreen` `dialogsTextFgService` (chat-list group-sender / media-type text) dart `0xFF4BE1C3` (teal) vs AyuGram `#ebebeb` (near-white) — completely wrong color family, visible on every group/media row in the chat list — `telegram_palette.dart:4910` ← `Telegram/Resources/night-green.tdesktop-theme(colors.tdesktop-theme):136`
- [ ] [CRITICAL] Premium gradient colors are wrong in ALL 4 themes, and these keys are colorize-EXCLUDED so the base value is authoritative. `premiumIconBg1` dart `0xFF6B93FF` (blue) vs AyuGram `#f38926` (orange) and `premiumIconBg2` dart `0xFF976FFF` (purple) vs `#e44456` (red) — the Dart reused the button gradient for the icon gradient (Δ217/Δ169) — `telegram_palette.dart:3280` (also 3908, 4502, 5091) ← `Telegram/lib_ui/ui/colors.palette:661`
- [ ] [CRITICAL] `night` theme `msgFileOutBg` = `0xFFFFFFFF` (opaque white) instead of `#4c9ce2` (blue) — the outbox audio/file download circle renders solid white; clear transcription error — `telegram_palette.dart:3733` ← `Telegram/Resources/night.tdesktop-theme(colors.tdesktop-theme):297`
- [ ] [MAJOR] `premiumButtonBg1/2/3` differ from authoritative base in all themes: dart `0xFF6B93FF/0xFF976FFF/0xFFE46ACE` vs AyuGram `#55a5ff/#a767ff/#db5c9d` — `telegram_palette.dart:3277-3279` ← `Telegram/lib_ui/ui/colors.palette:656`
- [ ] [MAJOR] `importantTooltipBg` is an opaque `0xFF5D7FA4` in all 4 themes, but AyuGram defines it as `toastBg` — a semi-transparent dark (`#2c3033e5` = `0xE52C3033` light, `#000000b2` dark). Group-call/important tooltips get a wrong opaque blue-gray background — `telegram_palette.dart:3288` (also 3916, 4508, 5097) ← `Telegram/lib_ui/ui/colors.palette:605` (→`:444 toastBg`)
- [ ] [MAJOR] `nightGreen` chat-list & peer colors use the wrong theme's values: `dialogsNameFg` dart `0xFFE9E8E8` vs `#f5f5f5`; `msgFileInBg` dart `0xFF3FC1B0` vs `#50d4c3`; `historyPeer1NameFg` dart `0xFFFB6169` (night/light red) vs night-green's `#ec7577` (all 8 peer colors off) — `telegram_palette.dart:4904` / `:4941` / `:4978` ← `Telegram/Resources/night-green.tdesktop-theme(colors.tdesktop-theme):132` / `:294` / `:218`
- [ ] [MAJOR] Selected-state foregrounds are not white in the dark themes. tdesktop sets `*Selected` message icons/bars to `#ffffff` for contrast on the selection overlay; the Dart keeps the colored value. e.g. `nightGreen` `historyOutIconFgSelected` dart `0xFF11BFAB` vs `#ffffff`; `msgInReplyBarSelColor`/`msgOutReplyBarSelColor` dart `0xFF32CEB9` vs `#ffffff`; `historyFileThumbIconFgSelected` dart `0xFF009687` vs `#ffffff` — selected messages lack the proper white contrast — `telegram_palette.dart:5076` (peer) & nightGreen `*Selected` keys ← `Telegram/Resources/night-green.tdesktop-theme(colors.tdesktop-theme):219`
- [ ] [MAJOR] `overviewCheckFgActive` (shared-files/links selection checkmark) is dark in the dark themes — dart `0xFF17212B` (night) / `0xFF282E33` (nightGreen) vs AyuGram `#ffffff`. A dark checkmark on the accent-colored check circle; the static palette is used directly (colorize/`_enforceContrast` only run when a custom accent is set) — `telegram_palette.dart:4122` / `:5301` ← `Telegram/Resources/night.tdesktop-theme(colors.tdesktop-theme):375`
- [ ] [MAJOR] `dayBlue` uses base `colors.palette` values where `day-blue.tdesktop-theme` overrides them: `scrollBg` dart `0x1A000000` vs `#00000000`; `historyOutIconFgSelected` dart `0xFF45A3AA` vs `#149ce6`; `msgFileThumbLinkInFgSelected` dart `0xFF12659A` vs `#168acd` (lightButtonFgOver) — `telegram_palette.dart:3213` / `:3419` / `:3447` ← `Telegram/Resources/day-blue.tdesktop-theme(colors.tdesktop-theme):75` / `:208` / `:284`
- [ ] [MAJOR] `classicDay` outgoing-bubble colors differ from base `colors.palette`: `msgOutBg` dart `0xFFEAFFDC` vs `#effdde`; `msgFileOutBg` dart `0xFF60B867` vs `#5fbe67`; `msgOutServiceFg` dart `0xFF529E39` vs `#45a32d` — `telegram_palette.dart:4340` / `:4353` / `:4347` ← `Telegram/lib_ui/ui/colors.palette:347` / `:387` / `:353`
- [ ] [MAJOR] `classicDay` `msgWaveformOutActive` is BLUE `0xFF40A7E3` instead of the classic green `#5ebd66` — the played-portion waveform on green outgoing voice messages renders blue (Δ125) — `telegram_palette.dart:4431` ← `Telegram/lib_ui/ui/colors.palette:426`
- [ ] [MAJOR] Media-viewer file-corner placeholder colors are wrong in all dark/classic themes (colorize-EXCLUDED → authoritative): `mediaviewFileGreenCornerFg` dart `0xFF64C05E` vs `#49a957`; also red `0xFFD45050` vs `#d55959`, yellow `0xFFE8A63E` vs `#e8a659`, blue `0xFF5BBFDE` vs `#599dcf` — `telegram_palette.dart:5086` (nightGreen; same pattern night/classicDay) ← `Telegram/lib_ui/ui/colors.palette:512`

## Excluded as ambiguous (not flagged)

A subset of dark-theme keys are literally `#ffffff` in the embedded `night`/`night-green`
files (e.g. `menuBgOver:#ffffff` night.tdesktop-theme:43, `emojiPanHeaderBg:#fffffff2`) with
copied light-theme comments ("white: fallback for background"). The Dart uses sensible dark
values there. Because matching the raw `#ffffff` would visibly break the dark menu/emoji
header, these are NOT treated as Dart bugs (the Dart's dark value is the likely-correct
visual intent). Near-identical pairs like `historyTextOutFgSelected` `0xFFF5F5F5` vs `#ffffff`
were also excluded as imperceptible.

# theme — ThemeData factory (AppTheme) + AppColors / AppSizes constant classes

`theme.dart` (172 lines) has three parts:

- `AppTheme.fromPalette` (theme.dart:98-170) — the **live, correct** theming path.
  Builds a Flutter `ThemeData` from a `TelegramPalette`, wiring `p.*` tokens into
  colorScheme / inputDecoration / scrollbar / tooltip / textTheme. No stubs,
  placeholders, empty callbacks, mock data, or "coming soon" feedback.
- `AppColors` (theme.dart:9-84) — ~70 hardcoded `const Color`s.
- `AppSizes` (theme.dart:86-96) — 9 hardcoded dimension `const`s.

Verified usage (grep over `dart/lib`):
- `AppSizes.*` — **0 production references** (only `dart/test/widget_comprehensive_test.dart` touches it). Entirely dead in the app.
- `AppColors.*` — used in production **only** in `message_bubble.dart:7534-7633`, and only the 4 `selectionCheck*` colors (the animated message-selection checkbox painter). The other ~66 constants are dead.

## Findings

- [ ] [MAJOR] The built-in **nightGreen** theme renders the message-selection checkbox in the wrong color (blue instead of its teal `boxTextFgGood`), because the painter hardcodes two `boxTextFgGood` values keyed on an `isDark` bool instead of reading the theme-aware `palette.boxTextFgGood`. AyuGram binds the check to one palette token: `msgSelectionCheck: RoundCheckbox(...) { bgActive: boxTextFgGood; }`. uniclient's own `TelegramPalette` already carries the correct per-theme values — `dayBlue.boxTextFgGood = #4AB44A`, `night = #5598DB`, `classicDay = #4AB44A`, `nightGreen = #3FC1B0` (telegram_palette.dart:3222/3850/4454/5043) — yet `message_bubble.dart:7534-7536` ignores them, doing `isDark ? selectionCheckBgActiveNight(#5598db) : …Day(#4ab44a)`. Concrete consequence: nightGreen is dark, so `isDark` is true → the check fills blue `#5598db`, not the theme's teal `#3FC1B0`. Same failure for any imported `.tdesktop-theme` (theme_file.dart parses `boxTextFgGood` into the palette) whose value isn't one of the two hardcoded constants — every other surface honors the theme, this one doesn't. Fix: paint from `context.palette.boxTextFgGood`; delete `selectionCheckBgActive{Day,Night}`. — `theme.dart:62-63`, consumed at `dart/lib/ui/message_bubble.dart:7534-7536`; theme selectable at `dart/lib/main.dart:2264` (`'night_green' => TelegramPalette.nightGreen`) ← `AyuGram/Telegram/SourceFiles/ui/chat/chat.style:1246-1247` (`msgSelectionCheck … bgActive: boxTextFgGood`).

- [ ] [MAJOR] `AppSizes` (theme.dart:86-95) — dead, divergent duplicate of the authoritative `TgTokens`. 0 production references; a drift trap because any future widget that adopts it gets non-AyuGram geometry. Stale values: `rightPanelWidth = 260` vs the info/third column's `392` (34% off, below the `292` minimum); `bubbleRadius = 18` vs `bubbleRadiusLarge 16px` (12.5%); `avatarSize = 40` vs `dialogsPhotoSize 46px` (13%); `railWidth = 68` vs `windowFiltersWidth 72px`. (`emojiPanelWidth = 345` *does* match, and the chat list correctly uses its own local `_avatarSize = 46.0`, not this class — so nothing renders wrong today.) Fix: delete `AppSizes`; source dimensions from `TgTokens`. _Not user-visible currently — latent cruft, flagged per the project's no-duplicate / no-cruft rule._ — `theme.dart:86-95` ← `AyuGram/Telegram/SourceFiles/ui/chat/chat.style:435` (`bubbleRadiusLarge: 16px`), `AyuGram/Telegram/SourceFiles/dialogs/dialogs.style:45` (`dialogsPhotoSize: 46px`), `AyuGram/Telegram/SourceFiles/window/window.style` (`columnMinimalWidthThird: 292px`, `columnMaximalWidthThird: 392px`, `windowFiltersWidth: 72px`).

- [ ] [MAJOR] `AppColors` (theme.dart:9-84) is ~94% dead and carries stale values that no longer match `colors.palette` — only the 4 `selectionCheck*` colors are live (finding 1). Dead examples: `historyOutIconFg = 0xFF5dc452` vs palette `#57b84c`; `msgOutDateFg = 0xFF6fab69` vs palette `#6db566`. Nothing renders wrong today, but these are theme-blind single `const`s (no day/night variant) sitting next to the live, theme-aware `TelegramPalette` — copy-paste drift waiting to happen. Fix: delete the unused constants; keep every theme-sensitive color in `TelegramPalette` (single source of truth). _Latent cruft, not user-visible currently._ — `theme.dart:51,49` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:268` (`historyOutIconFg: #57b84c`), `:361` (`msgOutDateFg: #6db566`).

## Verified OK (no action — recorded for the paper trail)

- `AppTheme.fromPalette` (theme.dart:98-170) is fully wired to the passed-in `TelegramPalette`; every ThemeData color flows from `p.*`. No stubs/placeholders/empty callbacks. `dark`/`light` getters resolve `TelegramPalette.night` / `.dayBlue`.
- Selection-check colors are **correct for both default themes**: day `#4ab44a` and night `#5598db` match AyuGram's `boxTextFgGood` for day-blue/night byte-for-byte (verified by extracting the `.tdesktop-theme` ZIP archives). The defect (finding 1) is solely that the value is hardcoded rather than read from `palette.boxTextFgGood`.
- `AppColors.accent = 0xFF40A7E3` matches `colors.palette:18` `windowBgActive: #40a7e3`; `msgInDateFg = 0xFFa0acb6` matches `:359`; `msgDateImgBg = 0x54000000` matches `:376` (`#00000054`); `historySendingOutIconFg`/`historySendingInIconFg` match `:271`/`:272`.
- `AppSizes.emojiPanelWidth = 345` matches AyuGram `chat_helpers.style:494` (`emojiPanWidth: 345px`).

---
_Audit integrity note: the tool layer intermittently batched/duplicated/garbled results during this run, so every load-bearing fact was re-verified against a clean read before recording. Three first-draft findings were corrected:_
1. _A claimed `AppSizes.avatarSize` use in `chat_list_row` — **discarded**; it uses a local `_avatarSize = 46.0`._
2. _A claimed `_dateColor` dead-branch at `message_bubble.dart:425-442` — **discarded**; that range is reaction-rendering code._
3. _A claimed "selection check is green, should be blue" then "night inherits base green" — **both wrong**. Extracting the night theme ZIP with `zipfile` proved `night boxTextFgGood: #5598db` (blue), exactly matching uniclient. The surviving defect is only the hardcode-vs-`palette.boxTextFgGood` wiring gap (finding 1)._

# theme_file — Telegram theme (.tdesktop-theme) parse / export / cache

`theme_file.dart` reimplements AyuGram's `window/themes/window_theme.cpp` (theme load:
zip + plain palette, background size/pixel limits, CRC32 cache) and
`window/themes/window_theme_editor.cpp` (cloud `// THEME EDITOR SERVICE INFO` block).
Most of it is faithful — constants match (`kThemeSchemeSizeLimit` 1 MB → `_maxPaletteFileSize`;
`kThemeBackgroundSizeLimit` 4 MB → `_kThemeBackgroundSizeLimit`; `kBackgroundSizeLimit`
25 M-pixel → `_kBackgroundMaxPixels`), the background probe order
(`background.jpg>background.png>tiled.jpg>tiled.png`) matches, `#rrggbb`/`#rrggbbaa`
hex parsing matches, the cloud block text format matches, and `uint64` id/accessHash
handling is correct. No stubs, placeholders, fake data, or empty callbacks. The export
path is genuinely wired to the engine (`theme_editor.dart:367-390` →
`createCloudTheme`/`updateCloudTheme`). The findings below are real behavioral
divergences from the C++ ground truth.

- [ ] [MAJOR] Cloud `THEME EDITOR SERVICE INFO` block is written at the BOTTOM of the file (after `// Generated by UniClient` header + all color lines), but AyuGram prepends it and reads it POSITIONALLY from the top (`list[1]`=ID, `list[2]`=ACCESS, guarded by `index <= 1`). Exported bytes are uploaded to the Telegram cloud (`theme_editor.dart:367-390`) and consumed by other clients, so AyuGram/TDesktop's `ReadCloudFromText` returns an empty `CloudTheme` for our files — the in-file cloud-theme identity (id/accessHash) is lost. — `theme_file.dart:442-445` (append-after-colors in `_generatePaletteText`, header at `:434`) ← `AyuGram/window/themes/window_theme_editor_box.cpp:231` & `:324` (`WriteCloudToText(cloud) + originalPalette` — prefix) and `AyuGram/window/themes/window_theme_editor.cpp:358-381` (`ReadCloudFromText`, positional `take(...,1)`/`take(...,2)`)

- [ ] [MAJOR] `_stripBlockComments` removes the entire `/* … */` span INCLUDING any newlines it contains, so a multi-line block comment whose `*/` shares a line with following content (or `/*` shares a line with preceding content) collapses two `name: value;` lines into one and the merged line mis-parses → both colors silently dropped. AyuGram's `stripComments` replaces each comment with a single SPACE and PRESERVES newlines, keeping line structure intact. — `theme_file.dart:230-244` ← `AyuGram/lib_base/base/parse_helper.cpp:13-34,58-78` (`feedComment` → `result.append(' ')`; `\n` handled separately so it is retained)

- [ ] [MAJOR] Background image is validated by HEADER ONLY (`_isValidBackgroundImage`: magic bytes + IHDR/SOF dimensions), never actually decoded. AyuGram additionally decodes the bytes via `Images::Read({.content=…, .forceOpaque=true})` and rejects the WHOLE theme when `background.isNull()`. A theme carrying a valid PNG/JPEG header but a corrupt/undecodable body is accepted here but rejected by AyuGram (and will fail to render later in Flutter). — `theme_file.dart:253-265` (`_isValidBackgroundImage`) ← `AyuGram/window/themes/window_theme.cpp:336-343` (`Images::Read(...)` + `if (background.isNull()) return false;`)

# theme_name_generator — theme name generator (Window::Theme::GenerateName port)

`theme_name_generator.dart` is a pure-data port of AyuGram's
`window/themes/window_themes_generate_name.cpp`. The data tables and algorithm
are faithful 1:1: all 99 `kColors` entries (hex→RGB verified individually), the
107 `kAdjectives`, the 81 `kSubjectives`, the redmean distance formula
(`((512+rMean)*dr*dr>>8) + 4*dg*dg + ((767-rMean)*db*db>>8)`), and the 50/50
adjective-prefix / subjective-suffix random selection all match the C++ source
exactly. No placeholders, stubs, empty callbacks, mock data, or unwired UI in
this file. The one substantive deviation is at the call site, which feeds the
wrong palette color in as the "accent".

- [ ] [MAJOR] Theme name is generated from the wrong palette color. AyuGram derives the accent for `GenerateName` from `st::windowActiveTextFg` (default `#168acd`), but the Dart call site passes `windowBgActive` (default `#40a7e3`) into `generateThemeName`. They are distinct palette entries (`telegram_palette.dart` defines both), so for the same theme the nearest-color lookup resolves to a different base name (e.g. ≈"Indigo" vs ≈"Blue" for the default palette) — a different generated theme name than Telegram Desktop / AyuGram produces. Note `main.dart:2540` already uses `windowActiveTextFg` as the accent, so the editor call site is internally inconsistent too. — `dart/lib/ui/theme_editor.dart:1314` ← `AyuGram/Telegram/SourceFiles/window/themes/window_theme_editor_box.cpp:773` (accent = `st::windowActiveTextFg->c`, consumed at `:790` `GenerateName(collected.accent)`)

## Notes (below CRITICAL/MAJOR threshold — not actioned)

- The C++ `kColors` is a `base::flat_map<uint32, const char*>`, so `ranges::min_element` iterates in **color-hex-sorted** order, whereas the Dart `_colors` list iterates in **declaration order**. Both pick the first strict minimum, so on an *exact* redmean-distance tie between two palette colors they could pick different names. This only affects measure-zero exact-tie inputs and still yields a valid name (which is further randomized by the adjective/subjective suffix), so it is MINOR. — `theme_name_generator.dart:15-27` ← `window_themes_generate_name.cpp:16,345`
- C++ applies a `capitalized()` helper to every value; the Dart data is already stored pre-capitalized, so output is identical. No deviation. — `theme_name_generator.dart:46` ← `window_themes_generate_name.cpp:334-340`

# theme_preview — Telegram theme-preview image painter (AyuGram `Window::Theme::Generator`)

`theme_preview.dart` is a manual port of AyuGram's `window_theme_preview.cpp` `Generator::generate()`.
It is a pure `CustomPainter` that takes a `TelegramPalette` and draws a static sample of the
dialogs panel + chat panel. It is NOT a placeholder/stub (the sample data is hardcoded in AyuGram
too) and needs no engine wiring — the palette IS its input. The canvas size (903×584), dialogs
width (312), top-bar height (54), full dialog-row geometry (rowHeight 62, photoSize 46, nameLeft 68,
nameTop 10, textTop 34, padding 10/8), compose area (44/46, sendRight 2, sendPadding 9), bubble
order, sample names/previews/times, the waveform data, mic-icon color (`historyRecordVoiceFg` ==
`historyComposeIconFg`), and the online-status color all match AyuGram exactly. The issues below are
real fidelity deviations from the C++ ground truth.

## Findings

- [ ] [CRITICAL] Incoming photo bubble is the wrong size and aspect-distorted: hardcoded 200×150, but AyuGram renders the image (themeimage.jpg is 654×395, identical file in both repos) at `ConvertScale(width/2) × ConvertScale(height/2)` = **327×197** (bubble width then clamped to min(history−margins=519, 327, msgMaxWidth=430)=327). Dart is 39% too narrow, and `drawImageRect` maps the full 654×395 src into a 1.33 aspect dst vs the correct 1.66, so the image is squished. — `theme_preview.dart:573-574` (`photoW=200, photoH=150`), `theme_preview.dart:611-629` (drawImageRect stretch) ← `AyuGram/window/themes/window_theme_preview.cpp:321-322` (`photoWidth = ConvertScale(photo.width()/2)`) + `:1008-1016` (paint at photoWidth×photoHeight)

- [ ] [MAJOR] Avatar background colors are wrong for 7 of 8 rows. AyuGram maps `peerIndex` through `DecideColorIndex(id)=id%7` then `ColorIndexToPaletteIndex` with table `{0,7,4,1,6,3,5}` → palette slot. Dart instead hardcodes a naive `peerIndex N → historyPeer(N+1)UserpicBg`. Correct vs Dart per row: i1 Peer1≠Peer8, i2 Peer5≠Peer3, i3 Peer8≠Peer2, i4 Peer6≠Peer7, i5 Peer2≠Peer4, i6 Peer7≠Peer5, i7 Peer4≠Peer6 (only i0 Peer1 is correct). — `theme_preview.dart:154-168` (`avatarColors` list) ← `AyuGram/window/themes/window_theme_preview.cpp:1036-1038` → `AyuGram/ui/empty_userpic.cpp:282-293` (`UserpicColor`) → `AyuGram/ui/chat/chat_style.cpp:1202-1206` (`ColorIndexToPaletteIndex` map)

- [ ] [MAJOR] Avatars are filled with a single flat color; AyuGram fills every empty userpic with a vertical `QLinearGradient` from `color1` (historyPeerNUserpicBg) at top to `color2` (historyPeerNUserpicBg2) at bottom. The `historyPeer1..8UserpicBg2` gradient-end colors exist in the Dart palette (telegram_palette.dart:150-157) but are never used here. — `theme_preview.dart:164-168` (`drawCircle` with one `Paint..color`) ← `AyuGram/ui/empty_userpic.cpp:311-316` (gradient stops color1→color2)

- [ ] [MAJOR] Colorized dialog previews are rendered in plain gray. AyuGram wraps several previews in `Ui::Text::Colorized(...)`, which in the dialogs text palette uses `linkFg: dialogsTextFgService` (#168acd accent) — distinct from `dialogsTextFg` (#999999 gray). Affected: "📎 Sticker" (whole), "Eva: Photo" (whole), "Max:" prefix of "Max: Yo-ho-ho!", and "Keynote.pdf" (whole). Dart draws every preview with one `previewFg` (= `dialogsTextFg`), so all four lose the accent color. — `theme_preview.dart:196-199` (single `previewFg`) ← `AyuGram/window/themes/window_theme_preview.cpp:358-376` (`Ui::Text::Colorized`) + `AyuGram/dialogs/dialogs.style:169-172` (`dialogsTextPalette.linkFg: dialogsTextFgService`)

- [ ] [MAJOR] Group chat-type icon is missing before group-row names. AyuGram rows "Evening Club" and "Old Pirates" are `Row::Type::Group` and `paintRow` draws `dialogsChatIcon` at the name's top-left, then shifts the name right by `icon.width() + dialogsChatTypeSkip(3)`. The Dart has no group/channel type concept in its row data and draws all names flush at `_textLeft=68` with no icon. (The `dialogsChatIconFg` palette field exists at telegram_palette.dart:368 but is unused.) — `theme_preview.dart:179-182` (name drawn, no group icon/shift) + `:110-135` (row data has no group flag) ← `AyuGram/window/themes/window_theme_preview.cpp:708-727` (chatTypeIcon paint + name shift) + `:364-365,370-371` (`Type::Group`)

- [ ] [MAJOR] Audio bubble play-button circle is undersized and bubble height is short. AyuGram uses `msgFileLayout.thumbSize = 44px` for the play circle and bubble height `padding.top(8)+thumbSize(44)+padding.bottom(8) = 60`. Dart hardcodes `thumbSize=33` (25% smaller) and `bubbleH=52` (vs 60). — `theme_preview.dart:482-483` (`bubbleH=52`, `thumbSize=33`) ← `AyuGram/window/themes/window_theme_preview.cpp:273` (height = padding.top+thumbSize+padding.bottom) + `AyuGram/ui/chat/chat.style:508-512` (`msgFileLayout` padding 12/8/10/8, `thumbSize: 44px`)

- [ ] [MAJOR] Dialogs search field reads the wrong palette key. AyuGram fills the filter input with `dialogsFilter.textBg = filterInputInactiveBg`; Dart fills it with `windowBgOver`. `filterInputInactiveBg` defaults to `windowBgOver`, so this looks correct for the default theme, but for any previewed theme that overrides `filterInputInactiveBg` independently the preview shows the wrong color — defeating the purpose of a per-theme preview. The `filterInputInactiveBg` field exists in the Dart palette (telegram_palette.dart:310) but is unused. — `theme_preview.dart:106` (`palette.windowBgOver`) ← `AyuGram/window/themes/window_theme_preview.cpp:650` (`setBrush(dialogsFilter.textBg)`) + `AyuGram/dialogs/dialogs.style:317` (`textBg: filterInputInactiveBg`)

## Notes (minor / cosmetic — not flagged above)

- Avatar initials font is 14px vs AyuGram `(size*13)/33 = 18px` (empty_userpic.cpp:308) — ~22% small, but folded under the avatar findings.
- Reply block: name color uses `msgInReplyBarColor` (activeLineFg #37a1de) vs AyuGram `msgInServiceFg` (windowActiveTextFg #168acd), and reply text is dimmed to 0.7 opacity vs AyuGram full `historyTextInFg` (window_theme_preview.cpp:907-911). Close blues; cosmetic.
- Waveform bar metrics: barSpacing 2 vs `msgWaveformSkip 1`, minBarHeight 2 vs `msgWaveformMin 3`, maxBarHeight 16 vs `msgWaveformMax 17` (chat.style:557-560); plus a different resampling loop. Cosmetic for a preview.
- Unread badge height 20 vs `dialogsUnreadHeight 19`; date font 12 vs `dialogsDateFont 13`; filter radius 16 vs `borderRadius 18`; minor sub-pixel offsets on top-bar icons and the hamburger. Cosmetic.
- `shouldRepaint` correctly gates on palette/photoImage identity; no perf issues (static painter, rare repaints).

# theme_tokens — AyuGram .style constant extraction (TgTokens)

`theme_tokens.dart` is a pure-constants file claiming to mirror AyuGram Desktop `.style`
values 1:1 (no widgets, callbacks, or backend wiring — so the audit is purely value
accuracy). ~80 of ~95 tokens were verified correct against the live AyuGram source.
The items below are the values that do **not** match the ground-truth `.style` files.

## Confirmed value mismatches

- [ ] [CRITICAL] `boxRadius = 8` but AyuGram box corner radius is `6px` (33% too large — boxes/popups render visibly over-rounded). Only one `boxRadius:` token exists in the whole tree. — `theme_tokens.dart:34` ← `AyuGram/Telegram/lib_ui/ui/layers/layers.style:38`

- [ ] [MAJOR] `infoProfilePhotoSize = 88` but AyuGram's named `infoProfilePhotoSize` = `size(infoProfilePhotoInnerSize, …)` where `infoProfilePhotoInnerSize: 72px` → 72×72 (22% too large). — `theme_tokens.dart:150` ← `AyuGram/Telegram/SourceFiles/info/info.style:527-528`

- [ ] [MAJOR] `settingsProfileCoverHeight = 112` is hand-derived as `settingsPhotoTop(8)+photo(88)+settingsPhotoBottom(16)`, but the `88` photo is wrong and no AyuGram cover equals 112. The real settings profile-photo block is `settingsInfoPhotoHeight: 162px` with `settingsInfoPhotoSize: 100px` (112 vs 162 ≈ 31% short). — `theme_tokens.dart:151` ← `AyuGram/Telegram/SourceFiles/settings/settings.style:205-206`

- [ ] [MAJOR] `radialSize = 44` but AyuGram `radialSize` = `size(50px, 50px)` → 50 (12% off). Only one `radialSize:` token exists in the whole tree. — `theme_tokens.dart:136` ← `AyuGram/Telegram/lib_ui/ui/basic.style:118`

- [ ] [MAJOR] `defaultInputFieldHeight = 47` but `defaultInputField.heightMin: 55px` (14.5% off). No 47px input-field height exists anywhere in the tree (variants are 55px and 32px). The companion `defaultInputFieldFontSize = 14` is correct (`placeholderFont: font(semibold 14px)`). — `theme_tokens.dart:127` ← `AyuGram/Telegram/lib_ui/ui/widgets/widgets.style:1070`

- [ ] [MAJOR] `defaultRadioDuration = 100ms` but `defaultRadio.duration: universalDuration` and `universalDuration: 120` → 120ms (16.7% off). — `theme_tokens.dart:153` ← `AyuGram/Telegram/lib_ui/ui/widgets/widgets.style:868` (+ `basic.style:131`)

- [ ] [MAJOR] `defaultRadioDurationDouble = 200ms` is derived as `100×2`; since the radio duration is actually 120ms, the doubled value should be `240ms`. — `theme_tokens.dart:154` ← `AyuGram/Telegram/lib_ui/ui/basic.style:131`

- [ ] [MAJOR] `menuIconSize = 20` is an invented/unsourced token — `grep menuIconSize` returns **0** results across all of `lib_ui/` and `SourceFiles/` (only the unrelated color `menuIconFg` exists). The value cannot be traced to any AyuGram style. — `theme_tokens.dart:135` ← `AyuGram/Telegram/lib_ui/ui/basic.style` (no such token)

## Notes (intentionally not flagged — cosmetic or doc-only, per audit rules)

- `defaultMultiSelectRadius = 8`: the `MultiSelectItem` struct has no `radius` field (its
  `height: 32px` IS correct). The chip corner radius is a cosmetic guess. — `theme_tokens.dart:132` / `widgets.style:1080-1098`
- `defaultRoundShadowBlur = 8`, `defaultRoundShadowOffset = Offset(0, 2)`: AyuGram's
  `defaultRoundShadow` is a 9-slice icon shadow with no numeric blur/offset; the closest
  numeric shadow (`defaultBoxShadow`) is blur `5px`, offset `(0,1)`, opacity `0.25`. Flutter
  approximation — cosmetic. — `theme_tokens.dart:133-134` / `widgets.style:911,927`
- The §56.3 header comment attributes all `topBar*` tokens to `window/window.style`, but they
  actually live in `info/info.style:1019-1093`. All the **values** are correct
  (topBarHeight 54, search 40, closeChoose 56, menuToggle 44, infoButton 52×54, etc.); only
  the source-file attribution comment is wrong. Doc-only, not a value bug.

# wallpaper — Chat background rendering (solid / gradient / pattern / image)

`dart/lib/theme/wallpaper.dart` renders the chat background, mirroring AyuGram's
`Ui::ChatTheme` background pipeline (`ui/chat/chat_theme.cpp`), the gradient
generator (`lib_ui/ui/image/image_prepare.cpp`), and the wallpaper data model
(`data/data_wall_paper.cpp`). Several pieces match well — `themeAdjustedColor`
(`wallpaper.dart:736` ← `chat_theme.cpp:932`), `_isPatternInverted`
(`wallpaper.dart:685` ← `chat_theme.cpp:925`), the invert color-matrix
(`wallpaper.dart:583` ← `InvertPatternImage` `chat_theme.cpp:1156`), the
soft-light / destination-in pattern compositing (`wallpaper.dart:599-628` ←
`chat_theme.cpp:108-217`), and the upload crop/scale
(`encodeWallpaperJpeg` `wallpaper.dart:752` ← `PreprocessBackgroundImage`
`chat_theme.cpp:941`). The issues below are real deviations from that authority.

## CRITICAL

- [ ] [CRITICAL] 3–4 color background is drawn as a plain **linear** gradient instead of Telegram's signature **4-point free-flowing** gradient — `_MultiGradientPainter.paint` calls `ui.Gradient.linear` with evenly-spaced stops — `wallpaper.dart:401-409` ← `AyuGram/lib_ui/ui/image/image_prepare.cpp:909-910` (`GenerateGradient` routes `colors.size() > 2` to `GenerateComplexGradient`) + `image_prepare.cpp:172-291` (`GenerateSmallComplexGradient`: 4 control points blended by inverse-4th-power distance with a swirl distortion). The iconic multi-color Telegram background is not produced at all.
- [ ] [CRITICAL] Same wrong gradient inside the pattern background — `_PatternWallpaperPainter._drawGradient` also uses `ui.Gradient.linear` for 3–4 colors instead of the complex gradient — `wallpaper.dart:656-663` ← `AyuGram/lib_ui/ui/image/image_prepare.cpp:909-910` + `293-305` (`GenerateComplexGradient`).
- [ ] [CRITICAL] Multi-color gradient **continuously animates** on an 8-second loop; AyuGram's gradient is static and advances exactly one 45° step (with a 200 ms fade) only when an **outgoing** message is revealed — `_MultiColorGradientState` runs `_ctrl..repeat()` and feeds `_ctrl.value` into the angle every frame — `wallpaper.dart:325-328, 338-356` ← `AyuGram/ui/chat/chat_theme.cpp:638-669` (`generateNextBackgroundRotation`, `kAddRotationDoubled = 720-45`), trigger only on `item->out()` in `history/history_widget.cpp:7718` and `history/view/history_view_list_widget.cpp:2131`; fade is `kBackgroundFadeDuration = 200ms` (`chat_theme.cpp:30`). There is no continuous timer anywhere in AyuGram.
- [ ] [CRITICAL] Pattern background spins continuously too — `_PatternWallpaperState` uses the same perpetual `_ctrl..repeat()` and rebuilds/repaints every frame — `wallpaper.dart:509-512, 537-560` ← `AyuGram/ui/chat/chat_theme.cpp:638-669` (same message-triggered, single-step model).
- [ ] [CRITICAL] Telegram pattern wallpapers cannot render: `WallpaperData.fromPattern` is dead code (no caller). Pattern documents are applied as `WallpaperType.image` and decoded with `Image.memory` — `dart/lib/ui/message_bubble.dart:9335-9343` builds `WallpaperData(type: WallpaperType.image, imageBytes: data, …)` from `downloadWallpaperDocument`, and `go/cores/telegram.go:23661-23679` returns the **raw** document bytes (a pattern doc is `application/x-tgwallpattern`, i.e. a gzipped SVG) — `wallpaper.dart:75-88` ← `AyuGram/ui/chat/chat_theme.cpp:1201-1223` (`PrepareBackgroundImage` builds a `WallPaperFlag::Pattern` background, gradient + tiled pattern).
- [ ] [CRITICAL] Pattern decode path is raster-only and cannot handle Telegram's gzipped-SVG patterns — `_decodePattern` uses `ui.decodeImageFromList` (PNG/JPEG/WebP/BMP/GIF only) — `wallpaper.dart:524-528, 445-449` ← `AyuGram/ui/chat/chat_theme.cpp:1079-1090` (`ReadBackgroundImage` passes `gzipSvg` so `Images::Read` un-gzips and rasterizes the SVG before it is tiled).

## MAJOR

- [ ] [MAJOR] 2-color linear gradient direction is reversed (~180°): `_rotationToAlignment` places `colors[0]` at the opposite end. rotation 0 → Dart puts `colors[0]` at bottom (`begin = Alignment(0, 1)`), AyuGram puts `colors[0]` at top (`start = {0,0}`) — `wallpaper.dart:300-305` ← `AyuGram/lib_ui/ui/image/image_prepare.cpp:931-944` (`GenerateLinearGradient` discrete 8-direction `start/finalStop` table, `colors[0]` at `start`).
- [ ] [MAJOR] Default pattern intensity is `40`; AyuGram's `kDefaultIntensity` is `50`, so patterns render ~20% too faint by default (and URL parses with the wrong default) — `wallpaper.dart:25, 78, 100` ← `AyuGram/data/data_wall_paper.h:110` (`static constexpr auto kDefaultIntensity = 50;`), used in `data_wall_paper.cpp:389`.
- [ ] [MAJOR] `_snapRotation` rounds to nearest 45 (`+22`) then wraps `% 360`; AyuGram floors after clamping to `[0,315]`. Diverges, e.g. 30° → Dart `45` vs AyuGram `0`; 340° → Dart `0` vs AyuGram `315` — `wallpaper.dart:163-166` ← `AyuGram/data/data_wall_paper.cpp:417-418` (`_rotation = (std::clamp(_rotation,0,315)/45)*45;`).
- [ ] [MAJOR] Gradients are never dithered, so large/dark gradients band; AyuGram dithers every multi-color fill gradient — `wallpaper.dart:401-409, 656-663` (no dither step) ← `AyuGram/ui/chat/chat_theme.cpp:1195-1197` (`GenerateDitheredGradient` → `Images::DitherImage`) + `image_prepare.cpp:880-897`.
- [ ] [MAJOR] `toUrlParams` emits `intensity` for **non-pattern** gradients and `rotation` for **3–4 color** gradients, and always joins colors with `~`. AyuGram emits intensity only `if (isPattern())`, rotation only when `backgroundColors().size() == 2`, and uses `-` as the separator for ≤2 colors — `wallpaper.dart:131-144` ← `AyuGram/data/data_wall_paper.cpp:269-291` (`collectShareParams`) + `163-173` (`StringFromColors`).
- [ ] [MAJOR] Pattern tiling only ever draws a single horizontal row (scales pattern height to exactly fill `size.height`), whereas AyuGram fits the pattern into an `(area.height × area.height)` box with `KeepAspectRatio` and tiles across both rows and columns — diverges for non-square patterns (extra/cropped rows) — `wallpaper.dart:666-683` (`_tilePattern`) ← `AyuGram/ui/chat/chat_theme.cpp:122-128` (scale) + `172-210` (`rows = cy`, odd centered `cols`).

# active_sessions_screen — Active Sessions / device management

Audited `dart/lib/ui/active_sessions_screen.dart` against AyuGram's
`settings/sections/settings_active_sessions.cpp`, `boxes/self_destruction_box.cpp`,
`api/api_authorizations.cpp`, and `settings/settings.style`.

**Wiring/structure/dimensions are faithful** — see the verified-OK notes at the
bottom. The findings below are all displayed-text / data-content deviations from
the AyuGram ground-truth lang strings.

- [ ] [MAJOR] "Terminate all" description text is wrong content — Dart shows *"Interrupted sessions will have to go through the full authorization process with a new confirmation code."*, a string that does **not exist anywhere** in AyuGram's lang files. AyuGram's `lng_sessions_terminate_all_about` reads *"Logs out all devices except for this one."* The current text misinforms the user about what the button does. — `active_sessions_screen.dart:1065` ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_active_sessions.cpp:968` (`tr::lng_sessions_terminate_all_about`, value at `Telegram/Resources/langs/lang.strings:1374`)

- [ ] [MAJOR] "Incomplete login attempts" description text deviates from ground truth — Dart shows *"These attempts had the correct login code, but no password was provided. If these attempts weren't made by you, you can terminate them and change your 2FA password."* (not present in AyuGram lang). AyuGram's `lng_sessions_incomplete_about` reads *"The devices above have no access to your messages. The code was entered correctly, but no correct password was given."* — `active_sessions_screen.dart:1095` ← `settings_active_sessions.cpp:979` (`tr::lng_sessions_incomplete_about`, value at `lang.strings:1376`)

- [ ] [MAJOR] Other-sessions section header text is wrong — Dart's `_buildOtherSectionHeader` renders *"Active sessions"*, but that is the **page title** (`lng_settings_sessions_title`). AyuGram's section header for the list of other devices is `lng_sessions_other_header` = *"Active Devices"*. The header should read "Active Devices", distinct from the screen title. — `active_sessions_screen.dart:1107` ← `settings_active_sessions.cpp:987` (`tr::lng_sessions_other_header`, value at `lang.strings:1371`)

- [ ] [MAJOR] Current-session info box hard-codes "online" instead of the real last-active datetime — `_showSessionInfoBox` sets `fullDate = isCurrent ? 'online' : _formatFullDate(...)`. AyuGram's `SessionInfoBox` shows `langDateTimeFull(base::unixtime::parse(data.activeTime))` for **every** session including the current one (the activeTime field is delivered for the current session too), so the box should display the formatted timestamp, not the literal word "online". — `active_sessions_screen.dart:593` ← `settings_active_sessions.cpp:439-446` (`langDateTimeFull(... data.activeTime)`, cpp:443)

- [ ] [MAJOR] Several info-box / dialog labels use different wording than AyuGram's canonical strings (more than casing): (a) System info-row label is *"System"* but AyuGram `lng_sessions_system` = *"System version"* (`active_sessions_screen.dart:673` ← `settings_active_sessions.cpp:460` / `lang.strings:1380`); (b) info-box subsection title is *"Session info"* but AyuGram `lng_sessions_info` = *"Info"* (`active_sessions_screen.dart:651` ← `settings_active_sessions.cpp:451` / `lang.strings:1377`); (c) info-box confirm button is *"OK"* but AyuGram `lng_about_done` = *"Done"* (`active_sessions_screen.dart:747` ← `settings_active_sessions.cpp:484`); (d) rename-dialog title is *"Rename Device"* but AyuGram `lng_settings_rename_device_title` = *"Rename current device"* (`active_sessions_screen.dart:775` ← `settings_active_sessions.cpp:124`); (e) location-disclaimer drops the word "estimate" — Dart *"This location is based on…"* vs AyuGram `lng_sessions_location_about` *"This location estimate is based on…"* (`active_sessions_screen.dart:710` ← `lang.strings:1384`).

<!--
VERIFIED OK (no findings) — checked thoroughly, all faithful to AyuGram:

BACKEND WIRING — all 6 engine calls are real bridge calls (no stubs):
  getSessions → 'GetSessions', terminateSession → 'TerminateSession',
  terminateAllOtherSessions → 'TerminateAllOtherSessions',
  getSessionAutoTerminateDays → 'GetSessionAutoTerminateDays',
  setSessionAutoTerminateDays → 'SetSessionAutoTerminateDays',
  setCustomDeviceModel → 'SetCustomDeviceModel'
  (engine_service.dart:5615-5695, all call _callAsync('__engine', ...)).
  Go Session struct (cores/base.go:567-582) serializes every field the Dart
  reads: id, device, platform, system, app_name, app_version, ip, location,
  last_active, is_current, password_pending, api_id, official_app — data flows
  end-to-end. No hardcoded/mock session data. No empty callbacks, TODOs, or
  "coming soon" snackbars (snackbars are legit error feedback). Device icon PNGs
  and lottie assets all present on disk (assets/icons/devices/, assets/animations/devices/).

STRUCTURE / SECTION-GATING — matches AyuGram setupContent() toggleOn logic 1:1:
  terminate-all shown when (incomplete+other)>0 (cpp:1023-1027); incomplete
  section when incomplete>0 (cpp:1028); other section + TTL section when
  other>0 (cpp:1029-1030); empty placeholder when other==0 (cpp:1031). Dart
  build() slivers gate identically (dart:883,887,913,939,947).

BEHAVIOR — terminateOne (optimistic local-remove + re-render, dart:299-318 ←
  cpp:850-877), terminateAll (reload, dart:320-332 ← cpp:879-892), two-step
  confirm flow via reset box w/ attention-styled button (dart:490-540 ←
  cpp:829-848), info-box terminate→close→confirm (dart:726-731 ← cpp:485-493),
  rename single-write (dart:808-830 ← RenameBox cpp:148-156), customDeviceModel
  overlay on current row+box (dart:578-580,1220-1222 ← deviceModelChanges
  reactive update api_authorizations.cpp:103-115). 60s poll timer (dart:209 ←
  kShortPollTimeout cpp:50) + reconnect refresh.

DEVICE CLASSIFICATION — TypeFromEntry ported exactly: same apiId sets
  {2040,17349,611335}/{2834}/{5,6,24,1026,1083,2458,2521,21724}/{1,7,10840,16352}/
  {2496,739222,1025907}, same browser/desktop detection order
  (dart:108-182 ← cpp:167-235). GradientForType peer-color mapping identical
  (dart:36-58 ← cpp:237-268). Lottie plays once on box show-finished
  (dart:_onLottieLoaded:1390-1411 ← cpp:setShowFinishedCallback+animate:418-388).

DIMENSIONS — row: height 84, photo (21,10) size 42, name (78,11), status
  (78,32), location top 54, terminate btn 34×34 at right 11/top 8
  (dart:1251-1312 ← settings.style sessionListItem:408-423 + sessionLocationTop:356
  + sessionTerminate:362-369). Box widths: info 364=boxWideWidth, TTL 320=boxWidth
  (dart:611,378 ← layers.style:117-118). Big userpic 70 / lottie 52, cover pad
  18/7, date skip 19, subsection skip 14 (dart:1415,1439,615-645 ← settings.style:383-400).

TTL DIALOG — options {7,30,90,180,365} (dart:361 ← self_destruction_box.cpp:97
  Values(Sessions)); DaysLabel logic identical: days>25 → months=max(d/30,1),
  else weeks=max(d/7,1) (dart:_formatDaysLabel:344-352 ← self_destruction_box.cpp:185-193);
  closest-value preselect (dart:363-369 ← cpp:130-135); save → updateTTL +
  reactive reload (dart:444-467 ← cpp:169-181 + active_sessions.cpp:1003).

ActiveDateString — same-day→time, same-week→weekday, else→date
  (dart:_formatActiveDate:553-571 ← api_authorizations.cpp:258-269). LocationAndDate:
  current row shows location only, non-current appends active date
  (dart:1235-1242 ← cpp:160-165). Note: weekday names & date format are
  hard-coded English/DD.MM.YYYY rather than locale-driven (langDayOfWeek /
  QLocale::ShortFormat) — cosmetic localization gap, not flagged.

NOT FLAGGED (cosmetic/minor): extra 1px divider after current row (AyuGram uses
  only 8px sessionCurrentSkip, no divider); "Never" TTL fallback label when days==0
  (AyuGram DaysLabel(0) → empty, but server never returns 0); missing "Device name"
  sub-label in rename dialog (input hint conveys purpose); "IP Address"/"Official App"
  casing vs "IP address"/"Official app"; "If Inactive For" vs "If inactive for…";
  Material icons vs st::menuIcon* (devices/info/language/location_on are correct
  equivalents); settings-search highlight registration (cross-cutting infra, N/A
  to this port).
-->

# admin_tools — group/channel/bot admin management (Edit Peer Info, Permissions, Restrict, Edit Admin, Admin Log, Invite Links, Members, Statistics, Boosts)

Audited `dart/lib/ui/admin_tools.dart` (8075 lines) against AyuGram Desktop C++ source. Slowmode values, charge-stars default (10), boosts-unrestrict range, channel admin-rights order/flags (incl. ManageDirect), media-group nesting of links/polls in the *permissions* box, invite-link form field order, and the admin-log action descriptions all match. The issues below are real deviations/gaps verified against the C++ source.

## CRITICAL

- [ ] [CRITICAL] Member-list "Requests" tab is view-only — join-request rows offer no Approve/Decline action (the context menu has branches only for admins/members/restricted/kicked, never `requests`, so a pending-request row shows just "View Profile"), and the engine exposes no approve/hide-request method at all. AyuGram's requests UI exposes per-row approve/dismiss via `processRequest(user, approved)`. The whole point of the requests view (acting on pending joins) is missing. — `admin_tools.dart:7170-7203` (also `_MemberRow.build` 7283-7337 has no action buttons; tab defined 6814, role 'requests' 6718) ← `AyuGram/boxes/peers/edit_peer_requests_box.h` (`processRequest`/`rowElementClicked`) + `edit_peer_requests_box.cpp`

- [ ] [CRITICAL] "Color & Emoji" dialog asks the user to TYPE a numeric "Custom emoji ID" and "Background emoji ID" into number fields — no real user can know emoji document IDs, so the emoji-status feature is effectively a non-functional placeholder (only the color swatches work). AyuGram presents a real emoji picker (`EmojiStatusPanel` with `CustomChosen`). — `admin_tools.dart:1268-1294` ← `AyuGram/boxes/peers/edit_peer_color_box.cpp:747-754`

## MAJOR

- [ ] [MAJOR] Permissions & Restrict editors split the single combined "Stickers, GIFs, games & inline" permission into FOUR separate toggles with wrong labels ("Send stickers & GIFs", "Send GIFs", "Send games", "Use inline bots"). AyuGram renders ONE checkbox (`SendStickers|SendGifs|SendGames|SendInline` → `lng_rights_chat_stickers`); the Dart cascade in `_toggleFlag` only papers over the structural mismatch, and the media count badge shows `/12` and `/10` instead of AyuGram's `/9`. — `admin_tools.dart:2497-2500` (perms) and `admin_tools.dart:3243-3246` (restricted) ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:88-91`

- [ ] [MAJOR] `_EditRestrictedBox` places "Send links" (embed_links) and "Send polls" (send_polls) as top-level flags OUTSIDE the collapsible "Send media" group, whereas AyuGram nests both inside the media sub-group (the `_EditPeerPermissionsBox` correctly nests them, so the two boxes are also inconsistent with each other). — `admin_tools.dart:3249-3250` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:92-93`

- [ ] [MAJOR] Both permission editors omit the `EditRank` restriction ("Add new admins"/"Edit rank", `lng_rights_group_edit_rank` / `_single`). AyuGram's `NestedRestrictionLabelsList` includes it in the bottom group (rendered as a checkbox; only locked, never removed, via `disabledMessages`). — `admin_tools.dart:2504-2509` (perms `_otherFlags`) and `admin_tools.dart:3248-3255` (restricted `_otherFlags`) ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:99-102`

- [ ] [MAJOR] `_EditAdminBox` group admin rights omit the `ManageRanks` toggle ("Manage rank", `lng_rights_group_manage_ranks`). AyuGram lists it for groups between "Manage voice chats" and "Remain anonymous"; the Dart group section3 only has manage_call/anonymous/add_admins. — `admin_tools.dart:3880-3884` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:140-145` (esp. :142)

- [ ] [MAJOR] `_EditAdminBox` shows the "Manage topics" admin right for ALL groups (the widget has no `isForum` param, so it is always in section1). AyuGram removes `ManageTopics` from group admin rights when `!options.isForum`, so non-forum groups should not show it. — `admin_tools.dart:3866-3874` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:146-153`

- [ ] [MAJOR] `_EditPeerPermissionsBox` renders the "Charge Stars for Messages" section unconditionally (for every group and channel). AyuGram only builds this section when `available = channel && channel->paidMessagesAvailable()`, so a regular group should not show a charge-stars toggle. — `admin_tools.dart:2667-2670` (always calls `_buildChargeStarsSection`) ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:1177,1182`

- [ ] [MAJOR] "Verify Accounts" dialog uses each contact's global Telegram `isVerified` (blue-check) flag as the initial per-bot verification state (`effectiveVerified = c.isVerified ^ toggledIds.contains(...)`). AyuGram determines bot-specific verification from `peer->botVerifyDetails()` and checks `details->botId == bot` — so Telegram-verified users wrongly appear already verified-by-this-bot and tapping them tries to "remove" verification that was never granted. — `admin_tools.dart:1750` ← `AyuGram/boxes/peers/verify_peers_box.cpp:94-95`

- [ ] [MAJOR] "Monetization" is a crude `AlertDialog` that dumps `getStarsRevenueStats` as raw `key: value` rows (`e.key.replaceAll('_',' ')` → `'${e.value}'`). AyuGram provides a full Channel Earn section (~1527-line widget: balances, withdraw button, ad-revenue toggle, charts). Statistics and Boosts got full screens here, but Monetization is a low-fidelity dump. — `admin_tools.dart:2063-2078` ← `AyuGram/info/channel_statistics/earn/info_channel_earn_list.cpp` (full section)

- [ ] [MAJOR] Bot "Public Links" row only shows a toast `'Bot link: t.me/$username'` instead of opening the usernames-management UI. AyuGram's `fillBotUsernamesButton` opens `UsernamesBox` (add/activate/reorder multiple public usernames). The row looks like a manager entry but only echoes one link. — `admin_tools.dart:1396-1405` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1786-1835`

# advanced_settings_screen — Advanced Settings page + sub-dialogs (Update, Data/Storage, Auto-download, Window/System, Performance, Power Saving, Spellchecker, Proxy, Local Storage, Recent Downloads, Experimental)

Audited against AyuGram Desktop C++ (ground truth): `settings/sections/settings_advanced.cpp`, `settings/settings_experimental.cpp`, `settings/settings_power_saving.cpp`, `boxes/connection_box.cpp`, `boxes/auto_download_box.cpp`, `boxes/local_storage_box.cpp`, and backend wiring in `go/engine/`.

Note: Power Saving box (flags, labels, grouping, inversion, battery gating) verified FAITHFUL — no issues. Auto-download visible toggle set (Photo/File + VideoMessage/Video/GIF) verified FAITHFUL. Most main-page rows are wired to real persisted `AppState` setters.

## CRITICAL

- [ ] [CRITICAL] Per-tag "Clear" in Local Storage wipes the ENTIRE cache instead of one tag. `_clearTag` deletes files by extension then calls the blanket `engine.clearCache(accountId:)` — and there is NO per-tag clear anywhere in the backend (only `ClearCache(accountID)` exists, `go/engine/media.go:264`). So clicking "Clear" on e.g. Images nukes all cache. AyuGram's `clearByTag(tag)` surgically clears only that tag's DB entries. — `advanced_settings_screen.dart:1919-1957` (clearCache at `:1955`) ← `AyuGram/Telegram/SourceFiles/boxes/local_storage_box.cpp:379-389`

- [ ] [CRITICAL] Auto-download toggles are not wired to any download-gating backend — settings are stored and never read. `_save` → `appState.setAutoDownloadSettings(...)` reaches Go `SetAutoDownloadSettings`, which only assigns `e.autoDownloadSettings[source] = settings` (`go/engine/engine.go:281-286`); that map is never read anywhere (no `Should()`/`ShouldAutoPlay()` gating). AyuGram's per-source/per-type `bytesLimit` drives real download decisions and fires `photoLoadSettingsChanged`/`documentLoadSettingsChanged`/`checkPlayingAnimations`. The toggles + sliders change nothing about what actually downloads. — `advanced_settings_screen.dart:1577-1590` ← `AyuGram/Telegram/SourceFiles/boxes/auto_download_box.cpp:160-222`

- [ ] [CRITICAL] Local Storage "Media cache size limit" and "Keep media" (time) sliders control nothing — only the total limit has any effect. `_saveAndClose` sends mediaLimit + timeLimit, but Go stores `localStorageMediaMB`/`localStorageTimeDays` (`go/engine/engine.go:361-362`) and never reads them; only `maxCache` (the total) drives eviction (`go/engine/media.go:297-318`). There is no separate media/big-file cache DB and no time-based eviction. (Time is also sent as a bare index, not days.) AyuGram maintains two real DBs with independent size limits and a real `totalTimeLimit`. — `advanced_settings_screen.dart:1983-1990` ← `AyuGram/Telegram/SourceFiles/boxes/local_storage_box.cpp:613-627`

- [ ] [CRITICAL] HTTP proxies are wrongly treated as shareable and `_proxyToUrl` fabricates a `tg://proxy?...&type=http` link that AyuGram never emits. `_ProxyEntry.isShareable => !deleted` is true for ALL types incl. HTTP, so the row menu shows Share/QR for HTTP and `hasShareable`/`_shareList` include it. AyuGram's `ProxyDataIsShareable` returns true ONLY for Socks5/Mtproto, and `ProxyDataToQueryPath` returns an EMPTY string for HTTP (HTTP is not shareable at all). — `advanced_settings_screen.dart:2899` (isShareable), `:3274` (hasShareable), `:3497-3522` (row share/qr), `:3576-3585` (fake http url) ← `AyuGram/Telegram/SourceFiles/boxes/connection_box.cpp:98-126`

- [ ] [CRITICAL] SOCKS5 share/QR URL drops username & password, making authenticated proxies unusable when shared. `_proxyToUrl` for socks5 emits only `tg://socks?server=…&port=…`. AyuGram appends `&user=<url_encoded>` and `&pass=<url_encoded>` when the SOCKS5 proxy has credentials. — `advanced_settings_screen.dart:3577-3578` ← `AyuGram/Telegram/SourceFiles/boxes/connection_box.cpp:118-123`

- [ ] [CRITICAL] Experimental Settings is missing 12 of AyuGram's 29 options (41% deviation). AyuGram registers 29 `addToggle` calls; Dart's `_experimentalFlagDefs` lists 17. Missing user-facing options include: `high-dpi-downscale`, `show-channel-joined-below-about`, `webview-legacy-edge`, `external-media-viewer`, `new-windows-size-as-first`, `alternative-scroll-processing`, `moderate-common-groups`, `force-compose-search-one-column` (plus engine-internal `gnotification`, `skip-url-scheme-register`, `deadlock-detector`, `touchbar-disabled`). — `advanced_settings_screen.dart:4448-4466` ← `AyuGram/Telegram/SourceFiles/settings/settings_experimental.cpp:284-314`

## MAJOR

- [ ] [MAJOR] Local Storage classifies cache by filesystem extension scan, not the engine's per-type cache accounting. `_scanCacheDir` walks `cacheDir` and buckets files by extension (`.jpg→Images`, `.tgs→Stickers`, …, else→Media Cache). AyuGram reads authoritative per-tag byte counts from the cache DB (`_stats.tagged.find(tag)` keyed by `kImageCacheTag`/`kStickerCacheTag`/…). With the SQLite-backed engine cache, extension buckets do not reflect real per-type usage (opaque/hashed blobs fall into "Media Cache"). — `advanced_settings_screen.dart:1886-1906` ← `AyuGram/Telegram/SourceFiles/boxes/local_storage_box.cpp:419-456`

- [ ] [MAJOR] "Share proxy list" and per-row Share copy a local `tg://` link instead of the public `t.me` link. `_shareList` and the row 'share' action both copy `_proxyToUrl` (a `tg://socks`/`tg://proxy` local link). AyuGram's share/copy use `ProxyDataToPublicLink` (`session->createInternalLinkFull(...)` → `https://t.me/...`); only the QR uses the local `tg://` link. — `advanced_settings_screen.dart:3560-3563` (row share), `:3741-3745` (`_shareList`) ← `AyuGram/Telegram/SourceFiles/boxes/connection_box.cpp:133-152`

- [ ] [MAJOR] "Install beta versions" and "Check for updates" are shown when auto-update is OFF. AyuGram wraps both in a `builder.scope(...)` whose visibility is `optionsShown = toggle->toggledValue() && !downloading`, so at the top-placed section (auto-update OFF) only the toggle + version status are visible and both options are collapsed. Dart renders install-beta (gated only on `_updateState != checking`) and check-now (always) regardless of the toggle state. — `advanced_settings_screen.dart:370-399` ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_advanced.cpp:1002-1040`

- [ ] [MAJOR] "Install beta versions" toggle has no effect on the actual update check. `_checkForUpdates` always queries `…/releases/latest` (excludes prereleases) and never reads `installBetaVersions`. AyuGram restarts the `UpdateChecker` on the beta channel when the toggle changes (`cSetInstallBetaVersion` + `writeInstallBetaVersionsSetting` + `checker.start()`). The Dart toggle is persisted but otherwise a no-op. — `advanced_settings_screen.dart:373-374` (toggle) / `:216` (check ignores beta) ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_advanced.cpp:1093-1107`

- [ ] [MAJOR] Native window-frame toggle is missing on Windows. AyuGram gates it on `Ui::Platform::NativeWindowFrameSupported()`, which returns `true` on Windows (`ui_window_win.cpp:966`) and Linux, `false` only on macOS (`ui_window_mac.mm:482`). Dart shows it only under `if (Platform.isLinux)`, so Windows users never get the "Use system window frame" control. — `advanced_settings_screen.dart:692-702` ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_advanced.cpp:329`

- [ ] [MAJOR] "Use monochrome tray icon" is shown on macOS (and unconditionally on Linux). AyuGram only creates this checkbox when `Platform::HasMonochromeSetting()` is true — `false` on macOS (`tray_mac.h:73`), conditional on Windows/Linux. Dart shows it on every platform whenever `showTrayIcon` is on, producing an extra control on macOS AyuGram never displays. — `advanced_settings_screen.dart:785-794` ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_advanced.cpp:457`

- [ ] [MAJOR] Auto-download size-limit slider bounds/steps deviate heavily. Dart hardcodes an 18-step ladder `[0.5,1,2,5,…,7168,8192] MB` topping at 8 GB. AyuGram uses a 100-step (`kSizeValueCount=100`) smooth curve via `Export::View::SizeLimitByIndex`, capped at `kMaxBytesLimit = 8000*512KB ≈ 4000 MB` — far finer granularity and ~half the Dart max. — `advanced_settings_screen.dart:1592-1595` ← `AyuGram/Telegram/SourceFiles/boxes/auto_download_box.cpp:66-72` / `data/data_auto_download.h:15`

- [ ] [MAJOR] Local-storage size-limit ladders use values not in AyuGram and add a non-existent "∞" total option. Dart hardcodes total `[200,500,1024,…,51200,0]` and media `[100,200,500,…,51200]` (values like 500/3072/15360/51200 and the `0`→"∞" entry don't exist in AyuGram). AyuGram computes 18 steps via `TotalSizeLimitInMB`/`MediaSizeLimitInMB`, has NO unlimited option, and enforces a 100 MB floor between total and media (`total − media ≥ 100MB`); Dart only clamps `media ≤ total`. — `advanced_settings_screen.dart:1811-1819` (steps), `:2064-2092` (clamp) ← `AyuGram/Telegram/SourceFiles/boxes/local_storage_box.cpp:39-55`, `:496-533`

- [ ] [MAJOR] Proxy rotation timeout uses a continuous slider with the wrong range/default. Dart slider is min 10, max 300, 29 divisions (default 60s). AyuGram uses a discrete set `kProxyRotationTimeouts = {5,10,15,30,60}` seconds with default 10s. — `advanced_settings_screen.dart:3247-3255` ← `AyuGram/Telegram/SourceFiles/core/core_settings_proxy.h:18-25` / `boxes/connection_box.cpp:70-82`

- [ ] [MAJOR] Missing "Check IP warning" confirmation before pinging proxies. Dart runs `_checkAllProxies`/`_checkProxy` immediately from `initState`. AyuGram gates the connectivity check behind a one-time confirm box (`lng_proxy_check_ip_warning`, persisted via `checkIpWarningShown()`) explaining the proxy will see the user's IP. — `advanced_settings_screen.dart:2944` (initState), `:2971-2997` ← `AyuGram/Telegram/SourceFiles/boxes/connection_box.cpp:1824-1842`

- [ ] [MAJOR] "Use proxy for calls" toggle visibility is wrong. Dart shows it for custom-mode proxies where `supportsCalls => type != _ProxyType.mtproto` (i.e. SOCKS5 AND HTTP). In AyuGram `ProxyData::supportsCalls()` returns `false` for ALL types (`mtproto_proxy_data.cpp:161-163`), so `_currentProxySupportsCallsId` stays 0 and the toggle is never shown; the historical rule (commented out) was SOCKS5-only. HTTP proxies never support Telegram calls, so Dart wrongly offers the toggle for HTTP. — `advanced_settings_screen.dart:2897` (supportsCalls), `:3070-3074` (showCallsToggle) ← `AyuGram/Telegram/SourceFiles/mtproto/mtproto_proxy_data.cpp:161-163` / `boxes/connection_box.cpp:1229-1231,1263`

- [ ] [MAJOR] Proxy status has no "Connecting" state and "Online" is fabricated client-side. `_ProxyStatus` is only `{online, available, checking, unavailable}`; status is set to Online purely because the row is the selected one (`isActive`) and `CheckProxy` returned ok — never from the real MTP connection state. AyuGram has a distinct `Connecting` state (animated) and derives Online/Connecting from `mtp().dcstate()` for the selected+enabled proxy only. — `advanced_settings_screen.dart:2864` (enum), `:3000-3006` ← `AyuGram/Telegram/SourceFiles/boxes/connection_box.cpp:692-721,2255-2262`

- [ ] [MAJOR] Clipboard proxy import skips validation/dedup and misclassifies MTPROTO as HTTP. `_importFromClipboard` adds every regex match with no validity check, no duplicate check, and a generic toast; `_parseProxyUrl` returns HTTP for any `tg://proxy?…` link lacking a `secret`. AyuGram validates each parsed proxy (Unsupported/IncorrectSecret/Invalid boxes), de-dups via `controller->contains(proxy)`, and parses `tg://proxy` strictly as Mtproto (never infers HTTP from a tg:// link). — `advanced_settings_screen.dart:3668-3691` (import), `:3700-3708` (parse) ← `AyuGram/Telegram/SourceFiles/boxes/connection_box.cpp:286-393,311-343`

# auth_screen — Telegram intro/auth flow (choose · QR · phone · email · OTP · 2FA · signup)

Compared `dart/lib/ui/auth_screen.dart` against AyuGram `intro/` widgets.
The file is well-wired: every interaction calls the real engine
(`submitInput → _engine.submitAuthInput`, `switchToMethod`, `cancelAuth`,
`engine.uploadProfilePhoto`, `engine.updateConfig`), QR payload/redundancy,
OTP cell geometry (40×50, 10px gap, 4px border, 20px font, 6px radius),
shake (4px/300ms), 2FA/recovery field tops (74/96/151/220) all match.
**No placeholders, stubs, mock data, or unwired elements — no CRITICAL items.**
The findings below are real deviations from AyuGram's behavior/values.

- [ ] [MAJOR] OTP code-cell borders are not theme-driven and use the wrong palette tokens. AyuGram drives all three states from the theme palette — focused `windowActiveTextFg` (#168acd), unfocused `windowBgRipple`, error `activeLineFgError` — so cells follow custom themes. Dart hardcodes the unfocused border to `#3A4A5A`/`#D0D0D0` (ignores the theme entirely, visibly wrong under custom/dark themes), uses `activeLineFg` (#37a1de) for focus, and `colorScheme.error` for error. The Dart palette already exposes `windowBgRipple`/`windowActiveTextFg`/`activeLineFgError`, so the hardcode is avoidable. — `auth_screen.dart:2026` ← `intro/intro_code_input.cpp:339`
- [ ] [MAJOR] Phone screen is missing the persistent "Log in by QR code" link. AyuGram's PhoneWidget always shows a `lng_phone_to_qr` ("Quick log in using QR code") link that jumps straight to the QR step; the Dart phone form (country picker + code + phone fields) has no QR link — only the reverse (QR → "Log in by phone number") exists at `auth_screen.dart:1182`. Reaching QR from phone requires Back→choose→pick-QR instead of one tap. — `auth_screen.dart:1302` ← `intro/intro_phone.cpp:111`
- [ ] [MAJOR] 2FA "next" button is labeled "Next" instead of "Submit". AyuGram's PasswordCheckWidget overrides the next-button text to `lng_intro_submit` = "Submit" for the password step; the Dart `_nextButtonText` falls through to the default 'Next' for state `2fa`. — `auth_screen.dart:289` ← `intro/intro_password_check.cpp:405`
- [ ] [MAJOR] Signup "finish" button is labeled "Start Messaging" instead of "Sign Up". AyuGram's SignupWidget sets next-button text to `lng_intro_finish` = "Sign Up"; the Dart's `TrStrings.lngIntroFinish()` (the function explicitly mirroring `lng_intro_finish`) returns 'Start Messaging' (`strings.dart:8`), so the wrong label renders. — `auth_screen.dart:290` ← `intro/intro_signup.cpp:209`

# ayu_chats_page — audit vs AyuGram settings_chats.cpp

> Ground truth: `AyuGram/.../ayu/ui/settings/settings_chats.cpp` (497 lines) — the REAL
> "Chats" page (NOT `settings_ayu.cpp`, which is unrelated). All files below were fully read.
> The Dart page maps 1:1 to the C++ `Build*` functions and the section ORDER matches exactly:
> StickersAndEmoji → RecentStickersLimit → GroupsAndChannels → Marks →
> WideMessagesMultiplier → ContextMenuElements → MessageFieldElements → MessageFieldPopups
> (`settings_chats.cpp:463-470` vs `ayu_chats_page.dart:24-274`).
>
> Verified: settings_chats.cpp (full), edit_mark_box.cpp (full), message_preview.cpp (full),
> ayu_settings.h + ayu_settings.cpp (getters/setters/defaults/validateRange). app_state.dart
> Dart setters were NOT read (only first 30 lines) — the one item depending on it is [PARTIAL].

## ayu_chats_page — deviations from AyuGram

- [ ] [MAJOR] Edited-mark default is hardcoded English, not localized. Dart passes
  `defaultValue: 'edited'` for the edited mark (`ayu_chats_page.dart:144`) and also falls back to a
  literal `'edited'` in the preview (`ayu_chats_page.dart:919`). AyuGram's live default is the
  **localized** string: `_editedMark(Core::IsAppLaunched() ? tr::lng_edited(tr::now) : QString("edited"))`
  (`ayu_settings.cpp:358`) and the EditMarkBox is seeded with `tr::lng_edited(tr::now)`
  (`settings_chats.cpp:189`). So non-English users get "edited" instead of their localized word. Use the
  l10n "edited" string for both the default and the preview fallback. — `ayu_chats_page.dart:144` <- `settings_chats.cpp:189` / `ayu_settings.cpp:358`.

- [ ] [MAJOR] Recent Stickers Count allows 0; AyuGram clamps the persisted value to **1..200**.
  `ayu_settings.cpp:519` `validateRange(_recentStickersCount, 1, 200, ...)` (default 100,
  `ayu_settings.h:648`). Dart slider is `steps:201` ⇒ values 0..200 (`ayu_chats_page.dart:65-67`),
  letting the user select 0, which AyuGram's load-time clamp rejects (it would snap 0→1). Note
  AyuGram's own slider is `.steps = 200+1` (`settings_chats.cpp:79`) so the UI stop count matches;
  the gap is only that Dart's persisted 0 isn't clamped to the valid 1..200 range. Enforce min 1 (or
  clamp on persist). — `ayu_chats_page.dart:65-69` <- `ayu_settings.cpp:519`.

- [ ] [PARTIAL] AppState setter persistence not verified. Every toggle/slider/choose-button wires to
  `appState.setXxx` (`ayu_chats_page.dart:28-273`). `app_state.dart` was not read (only its first 30
  lines), so I cannot confirm these setters persist (vs no-ops). AyuGram setters all persist via
  `AyuSettings::getInstance().setXxx` and serialize in `Serialize`/`Deserialize`
  (`ayu_settings.cpp:1069-1234`). Verify the Dart counterparts actually write through.
  — `ayu_chats_page.dart:28-273` <- app_state.dart (UNREAD).

## Notes (parity CONFIRMED — informational, NOT defects)

- **Bubble Radius min 0 is CORRECT.** AyuGram clamps to **0..16** (`ayu_settings.cpp:517`
  `validateRange(_messageBubbleRadius, 0, 16, ...)`, default 16 at `ayu_settings.h:629`), and the slider
  is `.steps = 17` (indices 0..16) (`settings_chats.cpp:252`). Dart `min:0 max:16 divisions:16` (= 17
  stops) (`ayu_chats_page.dart:515-517`) matches exactly. (Earlier draft of this audit wrongly flagged
  min 0; the clamp confirms 0 is valid.)
- **Restart prompt for BOTH sliders is CORRECT.** AyuGram calls `ShowRestartPrompt(controller)` in the
  `onFinalChanged` of bubbleRadius (`settings_chats.cpp:265`) and wideMultiplier (`:284`). Dart fires
  `_showRestartPrompt` for bubble radius (`ayu_chats_page.dart:530`) and wide multiplier (`:424`).
  Match. Dart flushes settings before restart (`flushSettingsSync`, `ayu_chats_page.dart:327`).
- **EditMarkBox parity EXACT.** AyuGram `EditMarkBox` (`edit_mark_box.cpp`): left button
  `ayu_BoxActionReset` sets field to default (`:44-48`); Save (`:50-54`) → `save()` writes via callback
  (`:96-99`); Cancel (`:55-59`); submit() trims and on empty re-focuses + `showError()` (`:73-80`).
  Dart `_EditMarkBoxContent` mirrors all of it: Reset to defaultValue (`ayu_chats_page.dart:691`),
  Save (`:696`), Cancel (`:698-701`), empty-trim → refocus + error state (`:639-645`), uses
  `lngAyuBoxActionReset` / `lngSettingsSave` / `lngCancel` l10n (`:688,695,699`). Match.
- Channel Bottom Button `{0:Hidden,1:Mute/Unmute,2:Discuss (fallback)}` (`ayu_chats_page.dart:79`)
  matches `Hide/Mute/Discuss` (`settings_chats.cpp:104-106`), enum `Hidden/MuteUnmute/DiscussWithFallback`
  (`ayu_settings.h:29-33`).
- Context-menu options `{0:Hidden,1:Shown,2:Extended Menu}` (`ayu_chats_page.dart:200`) match
  `Hidden/Shown/Extended` (`settings_chats.cpp:302-304`); enum ContextMenuVisibility (`ayu_settings.h:35-39`).
- Context-menu item set+order (Reactions, Views, Hide Message, User Messages, Message Details, Repeat,
  +Add Filter when filtersEnabled) matches `settings_chats.cpp:307-371` incl. the `filtersEnabled()`
  gate (`:361`). Dart: `ayu_chats_page.dart:285-308`.
- Message Field Elements set+order (Attach, Commands, TTL, Emoji, Voice, Gift, AI Editor) matches
  `settings_chats.cpp:381-429`. "AI Editor" IS real (`lng_ai_compose_title`, `:425`).
  Dart: `ayu_chats_page.dart:216-257`.
- Message Field Popups (Attach popup, Emoji popup) match `settings_chats.cpp:437-450`.
  Dart: `ayu_chats_page.dart:262-274`.
- Hide Reactions sub-toggles (channels/groups/private, inverted polarity, toggledWhenAll=false) match
  `settings_chats.cpp:47-68`. Dart: `ayu_chats_page.dart:34-61`.
- Wide Multiplier (min 1.0, step 0.05, 61 stops, 2-decimal label) matches AyuGram
  `kMinSize=1.00, kStep=0.05, steps=61, QString::number(...,'f',2)` (`settings_chats.cpp:241-242,277,287`).
  Dart `min:1.0 max:4.0 divisions:60` snapped to /20 (`ayu_chats_page.dart:415-420`). Match.
  (Aside: AyuGram persisted clamp is 0.5..4.0 at `ayu_settings.cpp:518`, slightly wider on the low
  end than the UI's 1.0 floor; Dart clamps display to 1.0..4.0 — acceptable, the UI floor is 1.0 in both.)
- Beta badge ONLY on "Semi-transparent deleted messages" matches `addBetaBadge(semiTransparent)`
  (`settings_chats.cpp:228-230`); no other toggle is beta. Dart: `ayu_chats_page.dart:171`. Match.
- Deleted-mark default 🧹 (U+1F9F9) matches AyuGram `QString::fromUtf8("🧹")` (`ayu_settings.h:646`,
  `settings_chats.cpp:172`). Dart `'\u{1F9F9}'` (`ayu_chats_page.dart:137`). Match.
- `_MessagePreviewStandalone` is a LEGITIMATE port: AyuGram has a live `MessagePreview` widget in
  BuildMarks (`settings_chats.cpp:141-152`; component `message_preview.cpp`). Sample text matches
  AyuGram's own fake items: "AyuGram Releases" (`message_preview.cpp:78`), "Update wehn?" (`:74`),
  "You need to go outside and touch some grass..." (`:89`). Not invented; sample text is faithful.
  The preview is shown as deleted+edited (`:92-93`, `:99-110`), which is why marks always render.

## SUMMARY
CRITICAL: 0. MAJOR: 2 (edited-mark default hardcoded English vs localized `lng_edited`;
Recent Stickers slider allows 0 vs AyuGram's 1..200 clamp). PARTIAL: 1 (Dart AppState setter
persistence — app_state.dart not read). Everything else (section order, all option lists, slider
ranges incl. bubble-radius min 0, beta badge, EditMarkBox reset/empty-validation, restart prompts,
live preview, defaults) is a faithful 1:1 port. No placeholders, stubs, empty callbacks, or invented
features found.

# ayu_filters_page — Regex Filters settings page (Shared / Shadow Ban / Per-Dialog, Import/Export)

Audited `dart/lib/ui/ayu_filters_page.dart` against AyuGram's `settings_filters.cpp`,
`settings_filters_list.cpp`, `edit_filter.cpp`, `per_dialog_filter.cpp`,
`import_filters_box.cpp`, `filters_utils.cpp` and `info_wrap_widget.cpp`.

The page is genuinely wired end-to-end — toggles call `filterEngine.rebuildCache()`
(mirroring `FiltersCacheController::rebuildCache()`/`fireUpdate()`), add/edit/delete/
exclude all persist via `saveFilterEngine()`, import/export/publish hit a real
`HttpClient` + dpaste, peers resolve via `resolveUsername`/`checkChatInvite`, avatars
via `downloadSingleAvatar`, search via `searchChats`. No stubs, placeholders, mock data,
empty callbacks, or "coming soon" feedback were found.

## Findings

- [ ] [MAJOR] Adding a filter from a **per-dialog** list creates a **shared (global)** filter instead of one scoped to that dialog. AyuGram's settings "+" add uses `showToast=false` (`info_wrap_widget.cpp:498` calls `RegexEditBox(nullptr, nullptr, controller->dialogId)`, default `showToast=false` per `edit_filter.h:27`), and the save path does `if (!showToast && dialogId.has_value()) newFilter.dialogId = dialogId;` — i.e. the new filter is assigned directly to the dialog. The Dart always builds the new filter with `dialogId: widget.filter?.dialogId` (null for a new filter → shared) and never sets the dialog scope at creation — `ayu_filters_page.dart:1397-1404` ← `AyuGram/ayu/ui/settings/filters/edit_filter.cpp:198-200`.

- [ ] [MAJOR] Spurious "Restrict" SnackBar shown in the settings add flow (which should be silent). The Dart replicates AyuGram's `showToast=true` toast-with-action behavior — but that path only exists for the *message context-menu* "add filter" flow (`context_menu.cpp:946`, the only caller passing `true`). In the filters **settings** page AyuGram passes `showToast=false`, so no toast/snackbar appears and the filter is silently scoped to the dialog. The Dart instead pops a `SnackBar('Filter added. Tap to restrict to this dialog.')` with a "Restrict" action — `ayu_filters_page.dart:1413-1427` ← `AyuGram/ayu/ui/settings/filters/edit_filter.cpp:222-243`.

- [ ] [MAJOR] Consequence of the above: a filter added via the per-dialog "+" **vanishes from the dialog's list**. The per-dialog "Filters" section is populated by `engine.filtersForDialog(dialogId)` which matches only `f.dialogId == dialogId` (`ayu_filter.dart:325-326`); a freshly-added shared filter (dialogId == null) appears in neither the dialog's "Filters" nor its "Excluded" section, so it disappears from view unless the user taps "Restrict" within the snackbar timeout. AyuGram keeps it visible because the filter is dialog-scoped at creation — `ayu_filters_page.dart:768-777` ← `AyuGram/ayu/ui/settings/filters/settings_filters_list.cpp:214-216`.

# ayu_general_page — AyuGram "General" settings page

Ground truth: `AyuGramDesktop/.../ayu/ui/settings/settings_general.cpp` (`BuildQoLToggles`,
`BuildTranslator`, `BuildShowPeerId`); builder `ayu/ui/settings/ayu_builder.{h,cpp}`;
model `ayu/ayu_settings.h`; labels `Telegram/Resources/langs/lang.strings`.

The page IS implemented and wired (reachable from `ayugram_settings_screen.dart:152`); no
empty callbacks / stubs / mock data. Every AyuGram General setting is present and every
control binds to an `AppState` setter. The findings below are behavioral/content deviations
from the AyuGram source, confirmed against it.

## MAJOR findings

- [ ] [MAJOR] Translation Provider is missing AyuGram's **beta badge**. AyuGram wraps the
  provider button with `ayu.addBetaBadge(button)`; the Dart `addChooseButton` renders no
  badge — `ayu_general_page.dart:31-41` ← `settings_general.cpp:113-115`
- [ ] [MAJOR] "Disable Stories" does not trigger AyuGram's **restart prompt**. AyuGram's
  setter calls `ShowRestartPrompt(controller)` after toggling; the Dart only calls
  `setDisableStories(v)` with no restart prompt, so the option silently fails to take full
  effect — `ayu_general_page.dart:47-52` ← `settings_general.cpp:171-174`
- [ ] [MAJOR] Every toggle has a **fabricated subtitle** that does not exist in AyuGram.
  AyuGram's `SettingToggleArgs`/`ToggleArgs` have no description field (title-only rows), and
  no `*Description` lang strings exist for these settings — the Dart invents secondary text
  on ~10 rows (e.g. "Hide the Stories row from the chat list", "Skip confirmation when
  opening external URLs", "Enhanced link preview metadata extraction") —
  `ayu_general_page.dart:49,56,85,95,112,119,141,174,181,188` ← `ayu_builder.h:22-43` (+ `settings_general.cpp:166-298`)
- [ ] [MAJOR] "Disable Similar Channels" collapsible uses the wrong master-state logic.
  AyuGram builds it with `toggledWhenAll = true` (master on only when BOTH children on),
  but the Dart hardcodes `isExpanded: collapse || hide` (OR) — so with only one child on the
  master state diverges from AyuGram — `ayu_general_page.dart:61-68` ← `settings_general.cpp:184-200` (`.toggledWhenAll = true` at :199; contrast Bigger Window `.toggledWhenAll = false` at :274, which the same Dart OR-logic does match — `ayu_general_page.dart:146-153`)
- [ ] [MAJOR] Translation section header text differs. AyuGram's subsection title is
  `tr::lng_translate_settings_subtitle()` (the Telegram "Translate" subtitle) with the button
  beneath titled `ayu_TranslationProvider`; the Dart instead labels the section header itself
  "Translation Provider" — `ayu_general_page.dart:23` ← `settings_general.cpp:37` (+ button title :83)

## Confirmed correct vs AyuGram (PASS — no action)

- Translation Provider options/order Telegram(0)/Google(1)/Yandex(2)/Native(3), Native gated
  on platform — `ayu_general_page.dart:31-41` ← `settings_general.cpp:41-60`; enum `ayu_settings.h:41-46`
- Show Peer ID choices Hide/Telegram API/Bot API mapping to `PeerIdDisplay{Hidden=0,TelegramApi=1,BotApi=2}` —
  `ayu_general_page.dart:124-133` ← `settings_general.cpp:121-154` + `ayu_settings.h:54-58`
- Disable Open Link Warning / Disable Notify Delay / Improve Link Previews / Show Message
  Seconds all exist on AyuGram's General page — `ayu_general_page.dart:54-122` ← `settings_general.cpp:177-244`
- Filter Zalgo correctly carries a beta badge AND a restart prompt (matches AyuGram) —
  `ayu_general_page.dart:93-108` ← `settings_general.cpp:211-230`
- Spoof Webview as Android + Bigger Window (Increase Height/Width) under "Webview" —
  `ayu_general_page.dart:135-166` ← `settings_general.cpp:250-275`
- Confirmations (Stickers / GIFs / Voice) — `ayu_general_page.dart:168-191` ← `settings_general.cpp:279-298`
- Section order & dividers (Translation → General → Zalgo group → Webview → Confirmations)
  match `BuildQoLToggles` — `ayu_general_page.dart:22-191` ← `settings_general.cpp:157-299`
- No setting present in AyuGram's General page is missing from the Dart, and the Dart adds no
  extra settings beyond AyuGram's General page.

# ayugram_settings_screen — AyuGram settings landing page (logo, version, Categories, Links)

Audited against AyuGram `settings_main.cpp` (the `AyuMain` section: logo → version/description → 6 category buttons → 4 link buttons).

**The port is faithful and fully wired** — verified the following all match AyuGram:
- All 6 category buttons navigate to the correct sub-pages (AyuGram→Ghost, Filters, General, Appearance, Chats, Other) via `showOther`/`Navigator.push` — `settings_main.cpp:103-132`.
- All 4 link buttons are wired: peer links (`@ayugram`, `@ayugramchat`) call the real `engine.resolveUsername` bridge method (`engine_service.dart:4067`, a genuine `ResolveUsername` FFI call) then `openChatById`; web links call `launchUrl`. AyuGram uses `showPeerByLink` / `QDesktopServices::openUrl` — `settings_main.cpp:144-185`. No stubs, no empty callbacks.
- Version label format `"AyuGram Desktop v<ver>"` + font = `boxTitle` (16px semibold, `boxTitleFont`) — matches `settings_main.cpp:73-75`, `layers.style:73`.
- Tagline text matches `tr::ayu_SettingsDescription` verbatim ("Telegram Desktop fork focused on customization and ToS-breaking features.") — `lang.strings:8375`.
- Subsection titles ("Categories"/"Links") use 14px semibold (`boxFontSize semibold`) in `windowActiveTextFg` blue — matches `defaultSubsectionTitle` (`layers.style:148-154`, `basic.style:54`).
- Category-button layout matches `st::settingsButton`: icon left edge at 20px, text column at 60px, 10px vertical padding — `settings.style:13-17`.
- Right-label color (blue accent) matches `defaultSettingsRightLabel.textFg = windowActiveTextFg` — `widgets.style:1514-1518`.
- Logo is driven by `AppState.appIcon`, loads real assets (`assets/icons/ayu/*.png`, 12 files present) with `cacheWidth/Height` set; AyuGram uses `AyuAssets::currentAppLogoPad()` — `settings_main.cpp:41-64`.
- Menu-icon → Material-icon mappings are all reasonable approximations (group_reactions→heart, tag_filter→label, all_media→grid, palette, chat_bubble, favorite→star, channel→campaign, chats→forum, translate, ip_address→dns).

## Findings

- [ ] [MAJOR] Section dividers are rendered as a 1px hairline `Container(height: 1, color: dividerColor)` instead of AyuGram's 8px `BoxContentDivider` band (fills `boxDividerBg` = `windowBgOver` gray, with top/bottom shadow hairlines). Affects both the Categories divider and the Links divider. Note: this is a systemic convention across the Dart settings port (e.g. `ghost_settings_page.dart:253`), so fixing it likely belongs in a shared divider widget rather than this file alone — `ayugram_settings_screen.dart:121` & `:176` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_main.cpp:98` & `:137` (resolves via `ui/vertical_list.cpp:27` `AddDivider` → `BoxContentDivider(st::boxDividerHeight)`, `lib_ui/ui/widgets/widgets.style:686` `boxDividerHeight: 8px`, `widgets.style:687-691` `defaultDividerBar{ bg: boxDividerBg; top/bottom shadows }`)

## ayu_other_page — AyuGram "Other" settings page (donations, crash reporting, URL scheme, reset)

**Wiring verdict: all backend wiring is REAL — no stubs/placeholders.**
Every callback is functional: Boosty/crypto buttons open URLs or a real generated QR (`_DonateQrBox`), "contact support" → `_DonateInfoBox` (correctly mirrors AyuGram's `tg://support` → `HandleSupport` → `FillDonateInfoBox`, `ayu_url_handlers.cpp:134-145`), crash toggle → `appState.setCrashReporting` → `Debug.crashReportingEnabled` (consumed at `utils/debug.dart:23`), Reset → `appState.resetAyuSettings()` (full reset), URL-scheme registration has real Linux/macOS/Windows impls, username link → `engine.resolveUsername` (real bridge call). Donate defaults (`5.00`/`3.50`/`386`/`ayugramOwner`) match `rc_manager.h:102-105`, and the RC fetch (primary→extera fallback) mirrors `rc_manager.cpp:15-16,54`. QR box sizing (487 = aboutWidth*1.25, `boxes.style:351`), center ratio 0.20, copy toast all match `donate_qr_box.cpp`.

**The defects below are all displayed-text divergences from AyuGram's `lang.strings` (the C++ uses `tr::ayu_*` keys; the Dart hardcodes different English). For a 1:1 replication these show the user wrong/altered content.**

- [ ] [MAJOR] Crash Reporting description has INVERTED semantics — Dart says reports are sent **"automatically"**, but AyuGram says the user is **"prompted"** and **decides** each time — `ayu_other_page.dart:106-107` ("Help improve AyuGram by automatically sending crash reports when the app encounters an error.") ← `AyuGram/Telegram/Resources/langs/lang.strings:8072` (`ayu_CrashReportingDescription` = "When this option is enabled, you'll be prompted to send a report after the app crashes. You can decide whether to send it or not.", used at `settings_other.cpp:192`)

- [ ] [MAJOR] Support page description text entirely different + wrong link label — Dart shows "You can support AyuGram development through donations. For questions, [contact support]." but AyuGram shows "[Support Development] and get an unique badge!" (no "contact support" wording; the link text is "Support Development" and the message highlights earning a badge) — `ayu_other_page.dart:452-460` ← `AyuGram/Telegram/Resources/langs/lang.strings:8061-8062` (`ayu_SupportDescription1`/`2`, used at `settings_other.cpp:161-167`)

- [ ] [MAJOR] DonateInfoBox header text wrong — Dart "Support AyuGram Desktop" vs AyuGram "Support Development" — `ayu_other_page.dart:632` ← `AyuGram/Telegram/Resources/langs/lang.strings:8063` (`ayu_SupportBoxHeader`, used at `donate_info_box.cpp:149-155`)

- [ ] [MAJOR] DonateInfoBox intro text wrong AND donation amounts misplaced — Dart puts the amounts ("$5.00, [ton] 3.50 TON, 386₽") inside the top intro line, but AyuGram's intro (`ayu_SupportBoxInfo`) carries NO amounts ("By supporting the project, you not only contribute to its development but also get a unique badge.") — the amounts belong in the "Make a Donation" row instead — `ayu_other_page.dart:642-657` ← `AyuGram/Telegram/Resources/langs/lang.strings:8064` + `donate_info_box.cpp:157-162` (intro) and `donate_info_box.cpp:179-199` (amounts live in the donation row)

- [ ] [MAJOR] DonateInfoBox "Make a Donation" row description wrong — Dart "Use the crypto buttons or visit Boosty." replaces AyuGram's "Transfer an amount of {amount1} ({amount2}) to any of the project's payment details. These can be found in the **Other** section of the app settings." — this is where the $/TON/₽ amounts should render (and they are dropped here) — `ayu_other_page.dart:663-669` ← `AyuGram/Telegram/Resources/langs/lang.strings:8066` (`ayu_SupportBoxMakeDonationInfo`, built at `donate_info_box.cpp:184-199`)

- [ ] [MAJOR] DonateInfoBox "Send Proof" row text wrong + drops required detail — Dart header "Send proof" / "Forward your payment confirmation to @user on Telegram." omits AyuGram's instruction to send a **photo** that "clearly shows the amount, date, and time of the transfer" — `ayu_other_page.dart:671-688` ← `AyuGram/Telegram/Resources/langs/lang.strings:8067-8068` (`ayu_SupportBoxSendProofHeader`/`Info`, used at `donate_info_box.cpp:208-221`)

- [ ] [MAJOR] DonateInfoBox "Receive Badge" row text wrong + drops detail — Dart "After verification, you will receive a supporter badge." omits AyuGram's "...a unique badge that will be displayed on your profile and visible to other users." — `ayu_other_page.dart:690-697` ← `AyuGram/Telegram/Resources/langs/lang.strings:8069-8070` (`ayu_SupportBoxReceiveBadgeHeader`/`Info`, used at `donate_info_box.cpp:225-235`)

- [ ] [MAJOR] Reset-settings confirmation invents an extra paragraph + wrong confirm-button label — Dart adds "This will reset ghost mode, appearance, filters, and all other AyuGram preferences." (not in source) and labels the confirm button "Reset"; AyuGram is a single line and the confirm button is "Yes" (`lng_box_yes`) — `ayu_other_page.dart:273-277,296` ← `AyuGram/Telegram/Resources/langs/lang.strings:8074` (`ayu_ResetSettingsConfirmation`) + `settings_other.cpp:215,221` (`.confirmText = tr::lng_box_yes()`)

- [ ] [MAJOR] QR box title wrong — Dart header "QR code" vs AyuGram box title "Get QR Code" (`lng_group_invite_context_qr`) — `ayu_other_page.dart:835` ← `AyuGram/Telegram/Resources/langs/lang.strings:2743` (set at `donate_qr_box.cpp:78`)

- [ ] [MAJOR] Crash Reporting toggle has an invented subtitle — Dart adds inline subtitle "Send crash reports to developers"; AyuGram's toggle has only a title (`ayu_CrashReporting`) with the explanatory text in the divider below, no per-row subtitle — `ayu_other_page.dart:100` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_other.cpp:183-190` (`.title = tr::ayu_CrashReporting()` only)

# ayu_section_builder — settings section widget toolkit (toggle/slider/choose/collapsible)

Audited `dart/lib/ui/ayu_section_builder.dart` against AyuGram's `ayu_builder.cpp`,
`settings_ayu_utils.cpp`, and the referenced `.style` files. This is a reusable
widget toolkit: its callbacks (`onChanged`) are wired to real `appState` setters
by callers (verified in `ayu_chats_page.dart` / `ayu_general_page.dart`), so it has
**no placeholder/stub/unwired-element CRITICALs**. Every dimensional & color claim
in the file's comments was cross-checked and is accurate (subsection title
`margins(22,7,10,9)` + `windowActiveTextFg`; betaBadge `windowFgActive` + `+4` x-offset
+ radius 4; toggle separator height `2*2+14=18`; `rightsButtonToggleWidth=70`;
`slideWrapDuration=150`; `permissionsExpandIcon` → `windowBoldFg`; slider track `3px`
+ thumb `7.5px` from `seekSize 15px`; divider band `8px` `boxDividerBg`). One genuine
behavioral defect found:

- [ ] [MAJOR] Slider has an off-by-one max: `_AyuSlider` sets `max: widget.steps` and `divisions: widget.steps`, which Flutter renders as `steps+1` discrete stops (indices `0..steps`). AyuGram passes `args.steps` as `valuesCount` to `setPseudoDiscrete`, which computes `sectionsCount = valuesCount - 1` → valid indices `0..steps-1`. Callers pass `steps = valuesCount` (AyuGram `settings_chats.cpp:79` `.steps = 200 + 1`; the Dart caller copies `steps: 201` with identity `indexToValue`). Result: the Dart "Recent Stickers Count" slider lets the user drag to index 201 and `onChanged` writes the out-of-range value **201** (AyuGram caps at 200); the thumb at value 200 also sits left of full-right since the track spans `0..201`. Fix: `max: (widget.steps - 1).toDouble()`, `divisions: widget.steps - 1`. — `ayu_section_builder.dart:503-505` (also init `502`, `464`) ← `Telegram/SourceFiles/ui/widgets/continuous_sliders.h:181-186` (via `ayu_builder.cpp:223-228`, caller `settings_chats.cpp:79`)

# ayu_toggle — AyuGram `defaultToggle` switch (ToggleView replica)

Audited `dart/lib/ui/ayu_toggle.dart` against AyuGram's `ToggleView` (`lib_ui/ui/widgets/checkbox.cpp`) and the `defaultToggle` style (`lib_ui/ui/widgets/widgets.style:874-890`).

The geometry/painting port is faithful: dimensions (border 2 / diameter 14|16 / width 14 / shift -2|1 / animPadding 2), `getSize` → totalW/totalH, track RRect, thumb ellipse, the material `animPadding` deflation (`interpolateToF(animPadding,0,t)=animPadding*(1-t)`, `animation_value.h:102`), and the color lerps (track + thumb-border = checkboxFg→windowBgActive, thumb-fill = windowBg) all match line-for-line. The XV/lock paint branches are correctly omitted — `defaultToggle` sets xsize/vsize/stroke = 0 and no lockIcon, so those branches never execute. `onChanged` is a real controlled-component callback wired by callers (`ayu_section_builder.dart:409`), not a stub.

One behavioral deviation found:

- [ ] [MAJOR] Non-material toggle animation runs at 150ms instead of 120ms. AyuGram switches **both** the duration **and** the curve on `isMaterialSwitches()`: material → `_duration` (=`st.duration`=150ms, `widgets.style:879`) + `easeOutCubic`; non-material → `st::defaultToggleDuration` (=`universalDuration`=120ms, `basic.style:131`) + `linear` (`checkbox.cpp:61-62`). The Dart port switches only the curve (`isMat ? Curves.easeOutCubic : Curves.linear`) but hardcodes the `AnimationController` duration to 150ms for both modes. Because `materialSwitches` is a real persisted, user-toggleable setting (`app_state.dart:979-980`, default true) that callers pass through as `isMaterial` (`ghost_settings_page.dart:367-370`), the non-material path is reachable and animates 25% too slow. Fix: make the controller duration `isMaterial ? 150ms : 120ms` to mirror the C++ duration switch. — `ayu_toggle.dart:30` (hardcoded `Duration(milliseconds: 150)`) ← `AyuGram/Telegram/lib_ui/ui/widgets/checkbox.cpp:61` (`isMaterialSwitches() ? _duration : st::defaultToggleDuration`; `defaultToggleDuration`=`universalDuration`=120, `AyuGram/Telegram/lib_ui/ui/basic.style:131`)

# engine_service — FFI service-layer wrapper for the Go engine

`engine_service.dart` is a 6992-line high-level wrapper around the FFI bridge. It
serializes protobuf/JSON requests, calls into the Go engine via `_callRaw`/`_callAsync`,
deserializes responses, and dispatches engine events to typed Dart streams. It is **not**
a UI file and has no 1:1 AyuGram C++ counterpart, so visual/dimension/color criteria do
not apply.

**Wiring verdict: clean.** All ~250 methods are genuinely wired to the engine. No stubs,
no placeholder/mock data, no empty callbacks, no "coming soon" snackbars, no
`not implemented` returns, no hardcoded fake content. Fallback default values
(e.g. `getConfcallSizeLimit` → 200, `getGiveawayPeriodMax` → 604800,
`getPaidMessagesConfig` commission 150‰) are last-resort error-path defaults that match
Telegram's known config defaults; the real values always come from the engine, so they are
not "faked data" violations. Only the two items below are genuine defects.

- [ ] [MAJOR] Voice waveform decoder hardcodes a fixed 100-sample loop instead of deriving the sample count from the encoded byte length. AyuGram's `documentWaveformDecode` computes `valuesCount = (size * 8) / 5` and decodes exactly that many 5-bit bars, so it renders waveforms of any length. The Dart `_decode5BitWaveform` loops `for (int i = 0; i < 100; i++)` and relies on a `byteIdx >= raw.length` break. The per-bar bit math is equivalent, and the break correctly handles waveforms **shorter** than 100 samples, but any waveform **longer** than 100 samples (≥64 encoded bytes) is silently truncated to 100 bars. The decoder is the production path for both chat voice messages (`_cachedMsgFromProto` → `mediaWaveform`) and the shared-media audio list (`_sharedMediaItemFromProto` → `waveform`). (Standard Telegram voice messages are capped at 100 samples by the sender, so the common path matches; the deviation affects only over-length waveforms originating from other clients/bots.) — `engine_service.dart:6587` ← `AyuGram/Telegram/SourceFiles/data/data_document.cpp:1333`

- [ ] [MAJOR] `dispose()` leaks two broadcast `StreamController`s — it closes 20 of the 22 controllers but omits `_msgReactionsUpdatedController` (declared `engine_service.dart:45`, fed at `engine_service.dart:6117`) and `_notifySettingsController` (declared `engine_service.dart:56`, fed at `engine_service.dart:6185`). On teardown these controllers are never `.close()`d, so their listeners never receive `onDone` and the resources are not released. No AyuGram C++ analog (this is a Dart object-lifecycle defect); reference is the in-file declaration/dispatch sites vs. the incomplete close list. — `engine_service.dart:5916` ← `engine_service.dart:45,56`

# ayu_filter — Regex message-filtering engine

Compared `dart/lib/data/ayu_filter.dart` against AyuGram Desktop's filter feature:
`ayu/features/filters/filters_controller.cpp`, `filters_cache_controller.cpp`,
`filters_utils.cpp`, `filters_controller.h`, and `ayu/data/entities.h`.

**Overall: a faithful port.** No stubs, placeholders, mock data, or dead UI — the
engine is fully wired (real `HttpClient` publish/import, real ICU-equivalent regex
compilation, real blocked/shadowban logic). The blob format
(`\n<type>N</type>`, `<button>text data</button>\n`), the numeric TYPE_* values,
the dpaste publish endpoint, the import diff flow, the shadowban-always /
blocked-only-if-`hideFromBlocked` rules, the `filteredMessagesShown` tri-state, and
the "hidden-blocked dialogs cleared only on rebuild" behaviour all match AyuGram
1:1. Findings below are subtle behavioural divergences, not missing features.

## Findings

- [ ] [MAJOR] Single (non-album) message text is NOT trimmed before matching, but
  AyuGram trims it. Dart writes `buf.write(_extractSingleText(msg, ...))` with no
  `.trim()` for the single-message branch, while the album branch does trim
  (`ayu_filter.dart:273` trims, `:280` does not). AyuGram trims in BOTH branches:
  album items `extractSingle(groupItem).trimmed()` and single
  `text = extractSingle(item).trimmed()`. Because patterns compile with multiline
  mode, leading/trailing whitespace on the first/last line changes whether
  `^…`/`…$`-anchored regexes match. A message `" hello "` → AyuGram first line
  `hello` (matches `^hello$`), Dart first line ` hello ` (does not). —
  `ayu_filter.dart:280` ← `AyuGram/.../filters_utils.cpp:668`

- [ ] [MAJOR] Blocked/shadowban verdicts are written into the same `_messageCache`
  and the cache is consulted BEFORE the block check, so block/unblock and
  shadowban changes do not take effect on already-evaluated messages. Dart returns
  the cached value at `ayu_filter.dart:636` before reaching the block checks at
  `:643-669`, and those checks call `_cacheResult(cacheKey, true)` (`:647,651,660,665`),
  persisting the block verdict. AyuGram deliberately evaluates `filterBlocked(item)`
  on EVERY call, before the regex cache lookup, and never stores block verdicts in
  its per-message cache (`filtered()`: block check at `filters_controller.cpp:161-164`
  → `putHiddenBlockedMessage` only; regex cache checked afterwards at `:168`). Result:
  in AyuGram, blocking/unblocking a sender re-hides/re-shows their already-rendered
  messages on the next render; in the Dart they stay stale until `rebuildCache()`
  (which block-state changes don't trigger). —
  `ayu_filter.dart:634-636,643-669` ← `AyuGram/.../filters_controller.cpp:161-171`

- [ ] [MAJOR] Filter IDs are exported verbatim with no validation/normalization to
  AyuGram's wire format, so filters created via the in-chat quick-action are
  silently dropped when imported into real AyuGram. `RegexFilter.toJson`
  (`ayu_filter.dart:46`) and `exportFilters` (`:379`) emit `id` as the raw string.
  AyuGram requires each id to be a 16-byte value encoded as a 32-hex-char
  (dash-formatted) UUID: `ParseFilterId` strips dashes and rejects anything whose
  length isn't 32 / 16 bytes, and `prepareChanges` does `if (regex.id.empty()) continue;`.
  The settings-page generator (`ayu_filters_page.dart:1369/1396 _generateUuidV4()`)
  is compatible, but the chat quick-filter generator
  `id: DateTime.now().microsecondsSinceEpoch.toString()` (`chat_view.dart:2674`)
  produces a ~16-digit decimal → `ParseFilterId` returns empty → that filter (and
  any exclusion referencing it) is skipped on AyuGram import, breaking the
  cross-client sharing this feature exists for. —
  `ayu_filter.dart:46,379` (+`chat_view.dart:2674`) ← `AyuGram/.../filters_utils.cpp:202-213,734-737`

- [ ] [MAJOR] Service-message type mapping adds cases AyuGram doesn't have, yielding
  different `<type>` values for some service messages. Dart `_serviceMessageType`
  maps `group_call → 16` (`ayu_filter.dart:240`) and the fallback `mediaType==2 → 8`
  (`:245`). AyuGram's `typeOfMessage` service branch only emits 16 for a real 1-1
  `media->call()`; a group-call service action has no `MediaCall` and a video has no
  service path, so both fall through to `return 10; // TYPE_DATE`
  (`filters_utils.cpp:604-635`). So a `<type>16</type>` filter over-matches (catches
  group calls) and a `<type>10</type>` filter under-matches in the Dart vs AyuGram.
  (`phone_call→16`, `set_photo→11`, `suggest_photo→21`, `wallpaper→22`,
  `gift_premium→18/25`, `gift_stars→30`, `giveaway_results→28`, `boost→10` are all
  correct.) — `ayu_filter.dart:240,245` ← `AyuGram/.../filters_utils.cpp:604-635`

- [ ] [MAJOR] Regex engine semantics differ: AyuGram compiles patterns with ICU
  (`icu::RegexPattern::compile`, `UREGEX_MULTILINE` always + `UREGEX_CASE_INSENSITIVE`)
  and matches via `icu::RegexMatcher::find()`. The Dart uses
  `RegExp(text, multiLine: true, caseSensitive: !caseInsensitive)` (Dart's
  ECMAScript/IRRegexp engine) with `pattern.hasMatch(blob)`. Flags and
  search-anywhere semantics line up, but ICU-only syntax in a shared/imported
  filter — POSIX classes (`[[:alpha:]]`), `\p{...}` Unicode-property escapes,
  possessive quantifiers — either fails to compile (silently dropped at
  `ayu_filter.dart:139-142`) or matches differently than it did in AyuGram. This is
  a platform constraint (no ICU in pure Dart), but it means imported AyuGram filters
  are not guaranteed to behave identically. —
  `ayu_filter.dart:138` ← `AyuGram/.../filters_cache_controller.cpp:55-59`

# emoji_data — emoji keyword search & language-pack manager

Dart port of AyuGram's `chat_helpers/emoji_keywords.cpp` (LangPack manager, query, PrioritizeRecent, ApplyVariants, ApplyDifference) + `lib_ui/emoji_suggestions/emoji_suggestions.cpp` (legacy `:shortcode:` Completer).

Core path is genuinely wired (NOT a stub): engine fetch in `chat_view.dart:3789` (`getEmojiKeywordsLanguages`→`getEmojiKeywords`/`getEmojiKeywordsDiff`), versioned diff, `recordRecent` on pick (`chat_view.dart:3874/3895`), recents persisted via `saveCallback` (`main.dart:321`), and `searchEmoji` consumed in 4 UI sites. Server lang-pack binary search (`_searchLangPack`) faithfully mirrors C++ `LangPack::query` (lower_bound + take_while startsWith). The deviations below are real behavior/data-flow gaps vs the authoritative C++.

- [ ] [MAJOR] Legacy/built-in suggestions only match keyword **prefixes from the start** (`kw.startsWith(q)`); C++ matches **interior words** across multi-word replacements via the word-indexed Completer (e.g. query "police" matches `:oncoming_police_car:`, "heart" matches `:couple_with_heart:`). Interior-word matches are silently lost in the built-in English fallback. — `emoji_data.dart:3046` ← `AyuGram/lib_ui/emoji_suggestions/emoji_suggestions.cpp:333` (`matchQueryTailStartingFrom`) & `:406` (`findWordsStartingWith`)

- [ ] [MAJOR] Legacy suggestions are emitted in **static `kEmojiSuggestions` array order with no relevance ranking**; C++ `prepareResult` ranks via 4 stacked `stable_partition` passes (exact match → words-used < 2 → words-used < 3 → first-char-after-colon == query first char). Suggestion ordering/highlight for the built-in set does not match. — `emoji_data.dart:3038` (linear append, no ranking) ← `AyuGram/lib_ui/emoji_suggestions/emoji_suggestions.cpp:373` (`prepareResult`)

- [ ] [MAJOR] Skin-tone **variant preference is inert**: `setVariant` has zero callers anywhere in the app, so `_variantPrefs` is always empty, `saveState` never persists a variant, and `applyVariant` inside `search()` is a permanent no-op — suggestions always render the default (yellow) tone regardless of the user's chosen skin tone. C++ `ApplyVariants` applies the saved variant via `lookupEmojiVariant`. — `emoji_data.dart:2984` (`applyVariant` in search) / `:2931` (uncalled `setVariant`) ← `AyuGram/SourceFiles/chat_helpers/emoji_keywords.cpp:674` (`ApplyVariants` / `lookupEmojiVariant`)

- [ ] [MAJOR] Server-diff keyword **deletions are never honored**: the engine model `EmojiKeywordEntry` carries no deleted flag (`engine_models.dart:3716`) and the diff caller always passes `deleted: const {}` (`chat_view.dart:3813`), so the entire deletion branch is dead code. Even if reached, it removes by comparing the **raw** deleted text against **postfixed** stored values (`existing` holds `_applyPostfix`'d strings), so ™/©/® keyword deletions silently fail. Stale keyword→emoji mappings accumulate vs C++ which prunes them. — `emoji_data.dart:2843` (deletion loop) / `:2848` (postfix mismatch) ← `AyuGram/SourceFiles/chat_helpers/emoji_keywords.cpp:274` (`emojiKeywordDeleted` handling, removes by `LangPackEmoji::text`)

- [ ] [MAJOR] Recent-emoji prioritization **ordering diverges** from C++ `PrioritizeRecent`: Dart searches from `lastRecent` and advances the frontier on `idx == lastRecent`, preserving recency order; C++ searches from `begin(list)` and does **not** advance when the match is already at the frontier (`it > lastRecent` is false with no else), which leapfrogs/reverses already-front recents. e.g. list `[A,B]` + recent `[A,B]` → C++ yields `[B,A]`, Dart yields `[A,B]`. Different first/highlighted suggestion. — `emoji_data.dart:3060` (`_prioritizeRecent`, `idx == lastRecent` branch at `:3074`) ← `AyuGram/SourceFiles/chat_helpers/emoji_keywords.cpp:650` (`PrioritizeRecent`, `:666`)

# strings — localized lang-pack string values vs AyuGram lang.strings

`strings.dart` is a hardcoded English `TrStrings` map standing in for Telegram's
server language pack. It has no callbacks, dimensions, or engine wiring of its own —
so the only meaningful comparison is **string value accuracy** against the AyuGram
ground-truth lang pack (`Telegram/Resources/langs/lang.strings`) and the `.cpp`
sites that consume each key. Findings below are string values that diverge from the
AyuGram source; "wired" items are already displayed via the cited Dart consumer and
render the wrong text to users today, "latent" items are defined-but-not-yet-consumed
and will render wrong text once wired.

## WIRED — wrong text shown to users now

- [ ] [MAJOR] `lngIntroFinish()` returns `'Start Messaging'` but `lng_intro_finish` = `"Sign Up"`; this is wired to the signup submit button (`auth_screen.dart:290` `'signup' => TrStrings.lngIntroFinish()`), which in AyuGram shows "Sign Up". `'Start Messaging'` is the unrelated `lng_start_msgs` key (not used anywhere in AyuGram source). — `strings.dart:8` ← `AyuGram/Telegram/Resources/langs/lang.strings:383` (consumer `intro/intro_signup.cpp:210`, `intro/intro_widget.cpp:684`)

- [ ] [MAJOR] `lngThemeReverting(count)` returns `'Theme will revert in $count second(s)'` but `lng_theme_reverting#one/#other` = `"Reverting to the old theme in {count} second(s)."` — wholesale-different sentence (and missing trailing period). Wired at `main.dart:2579`. — `strings.dart:16` ← `AyuGram/Telegram/Resources/langs/lang.strings:1086` (consumer `window/themes/window_theme_warning.cpp:113`)

- [ ] [MAJOR] `lngAyuForwardStatusPreparing()` returns `'Preparing...'` but `ayu_AyuForwardStatusPreparing` = `"Forwarding messages"`. In AyuGram the Preparing state shows "Forwarding messages" (same string as the Sending state), never "Preparing...". Wired at `ayu_forward.dart:18`. — `strings.dart:139` ← `AyuGram/Telegram/Resources/langs/lang.strings:8323` (consumer `ayu/features/forward/ayu_forward.cpp:85`)

- [ ] [MAJOR] Poll-vote notification strings drop the "your poll" ownership context that AyuGram uses. `lngNotifVotedInPoll()` = `'Voted in a poll'` vs `lng_poll_vote_notext` = `"voted in your poll"`; `lngNotifVotedFor(opt)` = `'Voted for «$option»'` vs `lng_poll_vote_option` = `"voted for \"{option}\" in your poll"` (omits "in your poll" + uses «» instead of straight quotes); `lngNotifVotedInPollNamed(q)` = `'Voted in poll: $question'` vs `lng_poll_vote` = `"voted in your poll \"{title}\""`. Wired at `notification_types.dart:478-488`. — `strings.dart:66` ← `AyuGram/Telegram/Resources/langs/lang.strings:637`

- [ ] [MAJOR] Reaction notification strings are paraphrased rather than matched to the `lng_reaction_*` family. `lngNotifReactedToText(e,t)` = `'$emoji to: $text'` vs `lng_reaction_text` = `"{reaction} to your \"{text}\""`; `lngNotifReactedToContact(e,n)` = `'$emoji to contact: $name'` vs `lng_reaction_contact` = `"{reaction} to your contact {name}"`; `lngNotifReactedToLocation(e)` = `'$emoji to your location'` vs `lng_reaction_location` = `"{reaction} to your map"` (word substitution "location"→"map"). Wired at `notification_types.dart:462-471`. — `strings.dart:85` ← `AyuGram/Telegram/Resources/langs/lang.strings:621`

## LATENT — defined but not yet consumed; wrong values vs source

- [ ] [MAJOR] Suggested-post deletion warnings are rewritten and lose information vs the AyuGram source. Titles are 100% different: `lngSuggestWarnTitleTon()` = `'Delete TON Suggested Post'` vs `lng_suggest_warn_title_ton` = `"TON will be lost"`; `lngSuggestWarnTitleStars()` = `'Delete Stars Suggested Post'` vs `lng_suggest_warn_title_stars` = `"Stars will be lost"`. Body text also diverges and **omits the "must remain visible for at least 24 hours after it was published" rule** that the AyuGram copy states (`lngSuggestWarnTextTon/Stars` say only "payment will be lost"). — `strings.dart:107` ← `AyuGram/Telegram/Resources/langs/lang.strings:5418` (consumer `boxes/delete_messages_box.cpp:566-575`)

- [ ] [MAJOR] The three filter-removal checkbox labels are collapsed into one generic string, losing the bot/group/channel distinction and the "all folders" wording. `lngFiltersCheckboxRemoveBot/Channel/Group()` all return `'Remove from chat folders'`, but AyuGram has three distinct keys: `lng_filters_checkbox_remove_bot` = `"Remove bot from all folders"`, `lng_filters_checkbox_remove_group` = `"Remove group from all folders"`, `lng_filters_checkbox_remove_channel` = `"Remove channel from all folders"` (selected by entity type at the call site). — `strings.dart:117` ← `AyuGram/Telegram/Resources/langs/lang.strings:7139` (consumer `boxes/moderate_messages_box.cpp:1058-1061`)

- [ ] [MAJOR] `lngProfileBlockBot()` returns `'Block bot'` but `lng_profile_block_bot` = `"Stop and block bot"` (the delete-chat box checkbox both stops and blocks). — `strings.dart:116` ← `AyuGram/Telegram/Resources/langs/lang.strings:1625` (consumer `boxes/moderate_messages_box.cpp:1029`)

## Notes (not flagged)

- Casing/punctuation-only differences are skipped as cosmetic: `lngThemeKeepChanges` "Keep Changes" vs "Keep changes"; `lngEnableAutoDelete`/`lngEditAutoDeleteSettings` lowercase vs AyuGram title-case "Auto-Delete"; `lngNotifLiveLocation` "Live location" vs `lng_live_location` "Live Location"; `lngSigninCantEmailForgot` "your email" vs source "the email".
- `lngDialogsTextWithFrom(from,msg) => '$from: $msg'` is correct: AyuGram composes `lng_dialogs_text_with_from` ("{from_part} {message}", lang.strings:4779) with `lng_dialogs_text_from_wrapped` ("{from}:", lang.strings:4780), yielding the same "From: message" output.
- Verified-matching values (no issue): all media-type notif labels (`lng_in_dlg_*`), `lngNotifReminder`, `lngNotifYou` (=`lng_from_you`), `lngForwardMessages` plural (`lng_forward_messages#one/#other`), `lngOpenLink`/`lngContextMarkRead`/`lngNotificationReply`, `lngCancel`, `lngFloodError`, `lngReportReaction*`, `lngSettingsReset*`, `lngSelfDestructSessions*`, and the remaining `lngAyuForwardStatus*` strings.

# main — App shell, theme-revert overlay & passcode lock screen

`main.dart` is mostly Flutter bootstrap, FFI/engine wiring, system-tray + notification sync,
and a `kDebugMode`-gated debug-command poller (test infrastructure, not a production placeholder).
The two genuinely AyuGram-comparable UI widgets are `_ThemeRevertOverlay`
(← `window/themes/window_theme_warning.cpp`) and `_PasscodeLockScreen`
(← `window/window_lock_widgets.cpp`).

Verified matching (no action needed): theme-warning box width 364 (`boxWideWidth`), height 150,
title position (24,13), title font 16px semibold, text top 60; passcode input `contentPadding`
(1,27,1,6) == `passcodeInput.textMargins`, submit width 225, system-unlock button 32×36, 16s
(`15999ms`) auto-revert, escape→revert. All AppState/engine calls are real (not stubs).

- [ ] [MAJOR] Passcode-lock "Log out" only removes the active account instead of resetting all accounts + forgetting the passcode — multi-account users stay locked out. AyuGram's lock-screen logout passes `account = nullptr` (because `passcodeLocked()` is true) into `logoutWithChecks(nullptr)` → `logout(nullptr)` → `_domain->resetWithForgottenPasscode()`, which wipes every account and clears the passcode (the "forgot passcode" escape hatch). The Dart `_doLogout` calls `appState.removeAccount(activeId)`, which removes only the active account; `removePasscodeIfEmpty()` (app_state.dart:3356) clears the passcode **only when `_accounts` becomes empty**. So with 2+ accounts, clicking Log out removes one account, leaves the others, and the user (who forgot the passcode) remains locked with no way in. — `main.dart:2804` ← `AyuGram/window/window_lock_widgets.cpp:106` (+ `window/window_controller.cpp:548`, `core/application.cpp:943`)

- [ ] [MAJOR] Passcode "Enter your passcode" header is top-aligned instead of vertically centered, sitting ~27px too high. AyuGram paints the header with `style::al_center` inside the rect `QRect(0, _passcode->y() - passcodeHeaderHeight, width, passcodeHeaderHeight)` (80px band ending at the input top), so the label's vertical center is ≈ `inputY-40`. The Dart positions the `Text` with `top: inputY - 80` and no vertical centering, placing the label's center ≈ `inputY-67` — a ~27px (≈34% of the 80px header band) upward shift that widens the gap above the input field. — `main.dart:2842` ← `AyuGram/window/window_lock_widgets.cpp:250`

# engine_models — Dart engine model classes (JSON deserialization, constants, computed getters)

`engine_models.dart` is a pure data-model layer (no widgets/callbacks/UI). Audit scope: hardcoded constants that must match Telegram/AyuGram values, decoding logic, and computed getters that drive UI decisions. Most of the file verified **correct** against AyuGram ground truth:

- Forum topic colors (`engine_models.dart:458-465`) match `data/data_forum_topic.cpp:52-57` **exactly** (blue/yellow/violet/green/rose/red).
- `kScheduledUntilOnlineTimestamp = 0x7FFFFFFE` (`engine_models.dart:3560`) matches `api/api_common.h:20`.
- `_kServerMaxMsgId = 1 << 56` (`engine_models.dart:3567`) matches `ServerMaxMsgId = MsgId(1LL << 56)` in `data/data_msg_id.h:80`.
- `kRequestTimeLimitMs = 60000` (`engine_models.dart:3563`) matches `kRequestTimeLimit = 60 * crl::time(1000)` in `data/components/scheduled_messages.cpp:25`.
- `scheduleRepeatPeriod` field is a **real** MTP field (`schedule_repeat_period`), not invented — see `api/api_common.h:28`, `api/api_sending.cpp`.
- `repeatOptions` (`engine_models.dart:3591-3600`) match `ChooseRepeatPeriod` in `ui/boxes/choose_date_time.cpp:254-269` **exactly**, including 3 months = `91*86400 = 7862400` and 6 months = `182*86400 = 15724800`.

## Findings

- [ ] [MAJOR] `WebPagePreview.defaultSmallMedia` deviates from AyuGram's `computeDefaultSmallMedia` — wrong check ordering and wrong results. The getter drives the small-vs-large web-preview layout decision in `chat_view.dart:3528,3552,5508`, so the deviation produces visibly wrong preview rendering. Specific divergences: (1) **Ordering bug** — Dart returns `true` for `type=='profile'` as the very first check, before any content/photo test; AyuGram returns `false` first when `siteName && title && description && author` are all empty, so an empty-content profile page renders large in AyuGram but small here. (2) **Missing photo requirement** — AyuGram only enters the small-media branch when a `photo` exists and `!document && !uniqueGift`; the Dart profile/twitter branches never check for a photo. (3) **Missing type exclusions** — AyuGram excludes `WebPageType::Photo` and `WebPageType::Story` (renders large); the Dart final branch only excludes `video`/`gif`/`document`, so `type=='photo'` and `type=='story'` pages with a thumb wrongly return small. (4) **ArticleWithIV not handled** — AyuGram returns `false` for `ArticleWithIV`; Dart has no IV check and returns small. (5) Empty-content check at `engine_models.dart:2911` omits `author` (AyuGram includes it). — `engine_models.dart:2908-2914` ← `data/data_web_page.cpp:423-449`

- [ ] [MAJOR] `ScheduledMessages.isScheduledMsgId` is missing the upper-bound check present in AyuGram's `IsScheduledMsgId`. Dart: `id > _kServerMaxMsgId`. AyuGram: `(id > ServerMaxMsgId) && (id < ScheduledMaxMsgId)` — so the Dart version also classifies shortcut/business message IDs (`id >= ScheduledMaxMsgId`, see `data/data_msg_id.h:81-82`) as scheduled. The helper is currently **dead code** (no callers in `lib/`), so there is no live behavioral impact today, but the logic is objectively wrong vs the cited ground truth and will misclassify if wired up. — `engine_models.dart:3565` ← `data/components/scheduled_messages.cpp:112-114`

