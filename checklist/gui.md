# GUI Audit — Cycle 3 Phase Ayugram (2026-06-08 02:57)

## Code Comparison (Dart vs AyuGram)

# telegram_palette — Telegram color palette (4 embedded themes + accent colorizer)

Port of Telegram/AyuGram's theme system: 4 static palettes (classicDay, dayBlue, night,
nightGreen) plus `colorize()` (accent recolor), `_enforceContrast()` (keepContrast), and
`adjustServiceColorsForWallpaper()`. Verified against AyuGram `colors.palette`, the three
embedded `.tdesktop-theme` files, the two `*-custom-base.tdesktop-theme` files, and
`style_palette_colorizer.cpp` / `window_themes_embedded.cpp`.

## What is CORRECT (verified, no action needed)
- classicDay (580/580) and dayBlue (369/369) color values match AyuGram exactly.
- All 580 `colors.palette` keys are present — zero missing.
- `colorize()` HSV hue/sat/value piecewise math is a faithful port of `style_palette_colorizer.cpp:24-58`.
- Accent HSL-lightness clamp (lMin/lMax) matches `window_themes_embedded.cpp:132-184` + struct defaults (`style_palette_colorizer.h:18-19`).
- `_enforceContrast()` keepContrast keys, check-bg/fallback pairs, and the Night-vs-NightGreen
  file-icon gating (`includeFileIcons: windowBg==0xFF17212B`) match `window_themes_embedded.cpp:139-167`.
- `windowBgActive` is a valid `was`/accent reference for all 4 themes (matches each `EmbeddedScheme.accentColor`).

## Findings

## Skipped (COSMETIC, <1% deviation — noted for completeness, not actioned)
- `night.dialogsDateFgOver` FF8696A8 vs AyuGram #8495a9, and `night.filterInputInactiveBg` FF232E3C
  vs #242f3d: the Dart resolved these via the base reference (windowSubTextFgOver / windowBgOver)
  instead of the night theme's explicit override; off by ≤2/255 per channel.
- `colorize()` adds a `saturation < 0.01` early-return (`telegram_palette.dart:1348`) not present in
  C++, and uses `>` vs C++ `<` at the exact hue-threshold boundary (`:1350`): both only affect
  achromatic colors / exact-equality edge cases that the C++ already leaves unchanged in practice.

# theme — Flutter ThemeData mapping from TelegramPalette (AppTheme.fromPalette)

Scope: `theme.dart` is a pure theme-builder (no widgets, callbacks, or engine
calls), so the audit is dimensional/color/typography fidelity vs AyuGram `.style`
files plus the leak-through of Material defaults for tokens the app consumes but
this file never maps.

The explicitly-commented values all VERIFY correct against AyuGram:
- Scrollbar thumb 4px + round 2px — `theme.dart:69-71` ✓ `widgets.style:822,824,826` (10−2·3=4).
- Input underline 1px / active 2px / radius 0 / contentPadding (0,28,0,4) — `theme.dart:51-62` ✓ `widgets.style:1045,1062-1064`.
- Tooltip radius 3px / border 1px / padding (5,2,5,2) / font 13 / wait 1000ms — `theme.dart:76-81` ✓ `widgets.style:1293`, `tooltip.cpp:172,573`, `basic.style:51`.

# theme_file — Telegram Desktop theme-file parser/exporter (palette tokenizer, reference cascade, cloud-theme meta, background validation, theme cache)

Audited the full 2199-line file against AyuGram's `window_theme.cpp`, `window_theme_editor.cpp`,
`style_core_palette.cpp`, `parse_helper.{cpp,h}`, `zlib_help.h` and `colors.palette`.

**Verified faithful (no action needed):**
- Comment stripper `_stripComments` ≡ `base::parse::stripComments` (parse_helper.cpp:13-97); `_skipWhitespaces`/`_readName` ≡ parse_helper.h:15-38.
- Streaming `_readNameAndValue` ≡ `readNameAndValue` (window_theme.cpp:122-164) — all four structural rejections (empty name / missing `:` / empty value / missing `;`) reproduced as whole-theme reject.
- Three-pass resolve (tokenize → in-order setColor → finalize cascade) ≡ `ReadPaletteValues`+`loadColorScheme`+`setColorSchemeValue`+`palette::setColor`/`compute`/`finalize` (window_theme.cpp:218-233 / style_core_palette.cpp:104-180). Forward-ref / ValueNotFound / KeyNotFound semantics all match.
- `_paletteFallbacks` is a **byte-for-byte 1:1 match** with the 236 reference colors in `colors.palette`, in exact declaration order (diff = identical).
- `paletteToMap` covers all **580** `colors.palette` keys (zero missing); the 5 extras are documented derived-getter synonyms (`telegram_palette.dart:1234-1238`) — exported but harmless, AyuGram stores them as `unsupported` on re-import.
- Background priority order `background.jpg > background.png > tiled.jpg > tiled.png` and size limits (`kThemeBackgroundSizeLimit`=4MB, `kBackgroundSizeLimit`=25Mpx, `kThemeSchemeSizeLimit`=1MB) match window_theme.cpp:56/262-274/302-334 + window_theme.h:41-42; whole-theme rejection on oversized/undecodable background matches window_theme.cpp:322-343.
- Cloud-meta markers + write order (`kCloudInTextStart`/`kCloudInTextEnd` incl. trailing `\n\n`) and uint64 high-bit preservation match window_theme_editor.cpp:52-53/346-381.
- Hex serialization `#rrggbb` / `#rrggbbaa` round-trips correctly with `setColorSchemeValue` (window_theme.cpp:178-194).
- No stubs, placeholders, TODOs, empty callbacks, or mock data. `getCrc32` resolves (archive barrel export, standard CRC-32).

**Finding:** none open — the zip-bomb guard (palette `.size > _maxPaletteFileSize` check before `.content`, theme_file.dart:537-541) was verified and closed: matches AyuGram `readCurrentFileContent` (zlib_help.h, reads `uncompressed_size` before `openCurrentFile`, kThemeSchemeSizeLimit=1MB), and `archive` 4.0.9 sets `.size` from the central-directory `uncompressedSize` while decompressing lazily on `.content` (proven by a throwaway test: `.size`≈2MiB while `isCompressed==true`, parseThemeFile→null).

# theme_preview — Telegram Desktop theme-preview thumbnail renderer (port of `window_theme_preview.cpp`)

Context: `theme_preview.dart` renders the 903×584 theme-preview image (dialogs panel + chat
panel with sample bubbles), a 1:1 port of AyuGram's `Generator` in
`window/themes/window_theme_preview.cpp`. The hardcoded sample chat (Eva Summer, the
wavedata array, "December 26", etc.) is NOT a placeholder — it mirrors the C++
`generateData()` exactly, which is correct for a preview thumbnail. The palette is wired
through every draw call, the `themeimage.jpg`/`background.tgv` assets exist and are
registered in `pubspec.yaml`, the `wallpaper.dart` helpers are real, and
`_computeChatBackgroundRects` faithfully reproduces `Ui::ComputeChatBackgroundRects`.
All 5 findings below were verified FIXED & closed (Stage-2 verification — built, launched, opened the Theme Editor preview in BOTH desktop 1024×768 and mobile 400×720, cross-checked code against C++ ground truth, and pixel-sampled the rendered preview):
- (1) Audio-bubble duration now anchored at `statusTop` (y+34, mid-bubble above the timestamp) and the waveform at `padding.top + msgWaveformMax` (y+25, bars bottom y+28, upper "name" row) — `theme_preview.dart:766,770,800` ✓ `window_theme_preview.cpp:925,948,982` (`statusTop`=34 / padding.top=8, `chat.style:509,511`). Visual: waveform sits in the upper row, "0:07" mid-bubble above "5:00".
- (2) Waveform amplitude `msgWaveformMin/Max=3/17`, `Bar/Skip=2/1` — `theme_preview.dart:755-762` ✓ `chat.style:557-560`.
- (3) Reply sender name = `msgInServiceFg`/`msgOutServiceFg`, reply text = full-opacity `historyTextInFg`/`historyTextOutFg` — `theme_preview.dart:649-653` ✓ `window_theme_preview.cpp:907-911`. Sampled: reply name a distinct accent token from the reply bar; reply text `#d7d9dc` ≈ main text `#eaeaeb` (full opacity, not the old 0.7-alpha ~`#969696`).
- (4) Tail corners now SHARP (`Radius.zero`) + drawn tail pointer (`_drawBubbleTail`), no longer `Radius.circular(4)` — `theme_preview.dart:595-617,719-724,843-847,956-970` ✓ `message_bubble.cpp:59-64,153-158`. Visual: outgoing audio bubble shows a sharp bottom-right corner + blue tail protrusion.
- (5) Compose placeholder = `windowSubTextFg` (matches the dialogs search placeholder) — `theme_preview.dart:945` ✓ `window_theme_preview.cpp:616` (`placeholderFg`→`windowSubTextFg`, `colors.palette:73`). Sampled bluish `#7f8da3` ≈ search placeholder `#8694ad`, not the neutral `windowFg@50%` ~`#919191`.
No crashes/render exceptions in the log across both modes.

# theme_tokens — centralized design-token table (mirror of AyuGram .style files)

`theme_tokens.dart` is a pure constants table (no widgets, callbacks, or engine
calls), so the audit reduces to: does every scalar match the AyuGram `.style`
source? I verified all ~95 tokens against the ground-truth `.style` files. The
file is remarkably accurate — every numeric value, font, duration, size, and
margin traces to a real AyuGram literal **except one**, documented below.

## Finding — verified FIXED & closed

The single MAJOR finding was verified FIXED & closed (Stage-2 verification — built the Flutter debug bundle, launched, and confirmed a clean render in BOTH desktop 1024×768 and mobile 400×720 with no crashes/render exceptions in the log; cross-checked the token against AyuGram ground truth `lib_ui/ui/widgets/widgets.style:911-922`):
- Fabricated `defaultRoundShadowBlur = 8` / `defaultRoundShadowOffset = Offset(0, 2)` removed (grep confirms no remaining code references — only the explanatory comment mentions the old names). AyuGram's `defaultRoundShadow` is an icon-based 9-slice `Shadow` (8 `round_shadow_*` icon slices + `fallback: windowShadowFgFallback`) with NO `blur`/`offset` field — confirmed against source. Its only scalar literal, `extend: margins(3px, 2px, 3px, 4px)` (`widgets.style:920`), is now resolved as `defaultRoundShadowExtend = EdgeInsets.fromLTRB(3, 2, 3, 4)` (Telegram `margins(L,T,R,B)` → Flutter `fromLTRB`, the same convention `localStorageRowPadding`/`themeEditorMargin` follow — 0% deviation). The non-scalar icon-slice asset part is documented as unresolved in the §56.13 notes alongside `localStorageLimitSlider`/MediaSlider — i.e. the fix did BOTH options the finding offered. — `theme_tokens.dart:171` ✓ `widgets.style:911-922`

## Verified accurate (no action — recorded for traceability)

- basic.style: `fsize 13`, `boxFontSize 14`, `normalFont/semiboldFont/linkFont/boxTextFont`, `lineWidth 1`, `defaultVerticalListSkip 6`, `slideDuration 240`, `slideWrapDuration 150`, `fadeWrapDuration 200`, `universalDuration 120`, `radialSize 50`, `radialLine 3` — `theme_tokens.dart:7-25,164-165` ← `lib_ui/ui/basic.style:51-131`
- layers.style: `boxWidth 320`, `boxWideWidth 364`, `boxPadding (24,14,24,8)`, `boxOptionListSkip 20`, `boxRadius 6`, `boxDuration 200`, `boxButtonHeight 34` (`defaultBox.buttonHeight`), `boxButtonPadding (6,10,10,10)` (`defaultBox.buttonPadding`), `boxMargin (0,10,0,10)` (`defaultBox.margin`) — `theme_tokens.dart:29-40` ← `lib_ui/ui/layers/layers.style:37-126`
- window.style: window min/column dims, `themeEditorSampleSize (90,51)`, `themeEditorMargin (17,10,17,10)`, `themeEditorDescriptionSkip 10`, `themeEditorNameFont 15 semibold` — `theme_tokens.dart:44-70` ← `window/window.style` + `info/info.style`
- topBar* (note: actually defined in `info/info.style`, not `window.style` as the §56.3 comment says — values all correct): `topBarHeight 54`, `topBarMenuPosition (-6,45)`, `topBarNameRightPadding 3`, `topBarActionSkip 10`, `topBarInfoButtonSize (52,54)`, `topBarInfoButtonInnerSize 42`, `topBarConnectingSkip 6`, `topBarSearchWidth 40`, `topBarCloseChooseWidth 56`, `topBarMenuToggleWidth 44`, `topBarCallWidth 40` — `theme_tokens.dart:50-60` ← `info/info.style:1019-1088`
- dialogs.style: `dialogsRowHeight 62`, `dialogsUnreadHeight 19`, `dialogsUnreadPadding 5`, `dialogsDateSkip 5`, `dialogsEmptyHeight 160`, `forumDialogRowHeight 80`, and `defaultDialogRow.*` (`photoSize 46`, `nameLeft/textLeft 68`, `nameTop 10`, `textTop 34`, `padding (10,8,10,8)`), `dialogsStoriesFull.*` (`height 77`, `photo 42`, `photoLeft 10`, `photoTop 9`) — `theme_tokens.dart:74-90` ← `dialogs/dialogs.style:77-117,731-738`
- chat_helpers.style: `historyReplySkip 53`, `historyReplyHeight 49`, `emojiSetSize (42,39)`, `emojiPanArea (34,32)`, `stickersSize (64,64)`, `historySlowmodeCounterMargins (0,0,10,0)` — `theme_tokens.dart:96-102` ← `chat_helpers/chat_helpers.style:417-1067`
- boxes.style: `normalBoxLottieSize (120,120)`, `localStorageRowHeight 50`, `localStorageRowPadding (22,5,20,5)`, `passcodeHeaderFont 19`, `passcodeHeaderHeight 80`, `passcodePadding (0,0,0,5)`, `contactsPadding (16,7,16,7)` — `theme_tokens.dart:91-118` ← `boxes/boxes.style:202-551`
- settings.style: `settingsCloudPasswordIconSize 100`, `settingsPhotoTop 8`, `settingsPhotoBottom 16`, `settingsAccentColorSize 24`, `settingsAccentColorLine 3`, `settingsAccentColorSkip 4`, `settingsBackgroundThumb 76`, `settingsThemePreviewSize (80,92)`, `settingsProfileCoverHeight 162` (`settingsInfoPhotoHeight`) — `theme_tokens.dart:122-179` ← `settings/settings.style:171-446`
- info.style: `infoDesiredWidth 392`, `infoLayerTopMinimal 20`, `infoLayerTopMaximal 40`, `infoMinimalLayerMargin 48`, `infoProfileSkip 7`, `infoTopBarHeight 54`, `infoTopBarScale 0.7`, `infoTopBarDuration 150`, and info-topbar button widths `Back 60 / Close 48 / Search 56 / Menu 48 / Forward 46`, `infoProfilePhotoSize 72` (`infoProfilePhotoInnerSize`) — `theme_tokens.dart:133-178` ← `info/info.style:131-633`
- widgets.style: `defaultInputFieldHeight 55` (`heightMin`), `defaultInputFieldFontSize 14`, `defaultRadioSize 22` (`diameter`), `defaultRadioStroke 2` (`thickness`), `defaultRadioDuration 120` (`= universalDuration`), `defaultMultiSelectHeight 32` — `theme_tokens.dart:149-182` ← `lib_ui/ui/widgets/widgets.style:860-1082`
- `defaultMultiSelectRadius 16` derivation verified: default `_avatarCorners = 23 == kMaxAvatarCorners` confirmed at `AyuGram/.../ayu/ayu_settings.h:697`, making `min(ComputeRadius(32), 16) = 16` correct — `theme_tokens.dart:159`
- derived values correct: `defaultVerticalListSkipDouble 12` (=6×2), `defaultRadioDurationDouble 240` (=120×2)

# wallpaper — chat-background renderer (gradients, patterns, gift symbols, image fill)

Verified against AyuGram `ui/chat/chat_theme.cpp`, `data/data_wall_paper.cpp`,
`lib_ui/ui/image/image_prepare.cpp`, `window/window_session_controller.cpp`.

This is an exceptionally faithful port. All of the heavy algorithms were checked
line-by-line and MATCH AyuGram: the complex 4-point gradient
(`GenerateSmallComplexGradient`), 8-direction linear gradient
(`GenerateLinearGradient`), `DitherGeneric` nibble math, complex-gradient
send-rotation (`ComputeRealRotation`/`ComputeRealProgress` + `kAddRotationDoubled`),
pattern tiling + odd-centered columns, gift-symbol parse/skip/stamp, `ColorsFromString`/
`StringFromColors`/`withUrlParams` URL round-trip, `IsPatternInverted`, `InvertPatternImage`,
the 4-color default (`ConstructDefault`), and `kDefaultIntensity`. The renderer is fully
wired (`ChatWallpaper` mounted in `chat_view.dart:20874`, `WallpaperData` populated from
prefs + persisted bytes, `ChatBackgroundRotator.rotate()` fired on outgoing-message reveal).
No stubs, no placeholders, no mock data, no empty callbacks. Findings below are the
genuine deviations.

## Findings — all verified FIXED & closed

All three findings were verified FIXED & closed (Stage-2 verification — built the Flutter
debug bundle, injected a bright test image wallpaper via prefs, launched, opened a chat, and
measured the rendered chat-background in BOTH desktop 1024×768 and mobile 400×720, cross-checked
the code against AyuGram ground truth):

- [CRITICAL] Dark-mode dimming of image wallpapers now applied. `_buildImage(bool isDark)` stacks
  a `ColoredBox(Color.fromARGB(255 * darkModeDimming ~/ 100, 0,0,0))` over a non-pattern image
  background while the active theme is dark; `darkModeDimming = patternIntensity.clamp(0,100)` = 50
  default → alpha 127. Brightness read via `Theme.of(context).brightness` (= `TelegramPalette.isDark`
  via `AppTheme.fromPalette`, ≡ AyuGram `forDarkMode = theme.basedOnDark`). Measured A/B on the same
  bright (~lum 200) test image: light-theme chat-bg luminance 205.3, dark-theme 102.7 → **ratio
  exactly 0.500** (50% dim, gated correctly — present in dark, absent in light); mobile dark-theme
  luminance 94.9 (dimmed) too. — `wallpaper.dart:374,408-453` ✓ `chat_theme.cpp:1228-1237` (alpha
  `255*darkModeDimming/100`), default `window_session_controller.cpp:3695-3697` + `forDarkMode` :3710.

- [MAJOR] `encodeWallpaperJpeg` now runs off the UI thread. `encodeWallpaperJpegAsync` =
  `compute(encodeWallpaperJpeg, bytes)`; `chat_settings_screen` `_pickFromFile` now `await`s it with a
  `mounted` recheck before touching `context` (no inline freeze). Grep confirms the sync function has
  ZERO UI-thread callers (only the isolate body). — `wallpaper.dart:2092` + `chat_settings_screen.dart:296`
  ✓ `chat_theme.cpp:941` (`PreprocessBackgroundImage`, dispatched via `crl::async` :705).

- [MAJOR] `computeAverageColor` moved off the UI thread. `averageColor` getter now returns an
  Expando-cached value (`null` until ready — never a sync decode); `ensureAverageColor()` computes it
  via `compute(_averageColorValueIsolate, bytes)`; `AppState._ensureWallpaperAverageColor` kicks it on
  `setWallpaper`/`_loadWallpaper` and `notifyListeners()` once it lands; `main.dart` folds the avg into
  the palette cache key so service colours adapt; `adjustServiceColorsForWallpaper` returns `this` when
  avg is null. Exercised at startup (image wallpaper restored from prefs) with no freeze; grep confirms
  the sync `computeAverageColor` has only the isolate caller. — `wallpaper.dart:296-327,2001-2006` +
  `app_state.dart:2987-2997,4847` + `main.dart:2446,2480` ✓ `chat_theme.cpp:880` (`CountAverageColor`).

# active_sessions_screen — Active Sessions / device management screen (AyuGram `Settings::Sessions` + `SessionsContent`)

Audited `dart/lib/ui/active_sessions_screen.dart` against AyuGram's
`settings/sections/settings_active_sessions.cpp` (UI), `api/api_authorizations.cpp`
(`ParseEntry`/`ActiveDateString` data layer) and `settings/settings.style` (dimensions).

**This is one of the most faithful ports in the tree.** Dimensions are essentially
pixel-exact and the wiring is real (no stubs, no placeholders, no mock data — every
button reaches the engine). Verified-correct against the C++ ground truth:

- **Device classification** `_classifyDevice` (`:108-182`) reproduces `TypeFromEntry`
  (`settings_active_sessions.cpp:167-235`) 1:1 — same apiId arrays
  (`kDesktop/kMac/kAndroid/kiOS/kWeb`), same browser/desktop sub-detectors, same
  precedence chain, same gradient buckets (`_gradientForType` ↔ `GradientForType`,
  `:36-58` ↔ `:237-268`) and icon assets (`historyPeerUserpicFg` colorization matches
  `settings.style:370-386`).
- **Row geometry is exact** (`settings.style:355-423`): height 84 (`:1254`), photo
  21/10 size 42 (`:1258-1260, 1327`), name 78/11 (`:1262-1263`), status 78/32
  (`:1278-1280`), location top 54 (`:1289-1292` = `sessionLocationTop:54px`), terminate
  34×34 at top 8 / right 11 (`:1305-1306` = `sessionTerminate{width/height:34}`,
  `sessionTerminateTop:8`, `sessionTerminateSkip:11`). Big userpic 70 / lottie 52
  (`:1418, 1442-1443` = `sessionBigUserpicSize/sessionBigLottieSize`), cover padding
  18/7 (`:618, 623` = `sessionBigCoverPadding`), date skip 19 (`:646`), value skip 8
  (`:707`).
- **Section gating matches the rpl `toggleOn` graph** (`settings_active_sessions.cpp:1023-1031`):
  terminate-all on `(incomplete+other)>0` (`:886`), incomplete on `>0` (`:890`), other on
  `>0` (`:916`), TTL on `other>0` (`:950`, comment cites `:1030`), placeholder on
  `other==0` (`:942`). Sort newest-first by active time (`:237` ↔ `:787`).
- **Behavior matches**: `terminateOne` local-remove without full reload (`:299-318` ↔
  `:850-877`), titleless attention-styled confirm box (`:490-526` ↔ `:829-848`), rename
  reactive update of the current row (`:820-825, 988, 1029` ↔ `RenameBox`+`deviceModelChanges`),
  current-row has no date & no terminate button (`:1241-1244, 722` ↔ `LocationAndDate`
  hash-guard `:160-165` + info-box left-button hash-guard `:485`), info-box rows skip
  empty values (`:663, 672, 689, 698` ↔ `AddSessionInfoRow` early-return `:1333`),
  location-about divider gated on non-empty location (`:708` ↔ `:480-482`), 60 s poll
  (`:209` ↔ `kShortPollTimeout`), 32-char rename cap (`:787` ↔ `kMaxDeviceModelLength`).
- `_isoWeekNumber` reproduces AyuGram's calendar-year + ISO-week test exactly
  (`:564` ↔ `api_authorizations.cpp:265-266`).

Three real deviations were found and **all three are now fixed & verified**: (1)
timestamps render in local time via `DateTime.parse(...).toLocal()` in
`_formatActiveDate`/`_formatFullDate` (mirrors `base::unixtime::parse`); (2)
`telegram.go GetSessions` normalizes app name/version through `normalizeSessionApp` +
`formatVersionDisplay`, mirroring `Api::ParseEntry`/`Core::FormatVersionDisplay`; (3)
`GetSessions` falls back to `date_created` when `date_active == 0`. Verified empirically
(Dart `DateTime.parse("…+04:00")` → UTC hour, `.toLocal()` → local hour; Go unit test of
`normalizeSessionApp`/`formatVersionDisplay`/fallback; runtime screenshots desktop+mobile
showing local times and normalized "Telegram Desktop" / preserved third-party app names,
no `1970` epoch dates).

Not flagged (MINOR/cosmetic, consistent with this repo's audit calibration): ~22
hard-coded English UI strings (`'Active Sessions'`, `'This device'`, `'Active Devices'`,
section footers, info-box labels, etc., `:654-1188`) where AyuGram uses `tr::lng_*` — the
text is correct, just not routed through `TrStrings`; and the locale format of
`_formatActiveDate` (24h `HH:mm`, `dd.MM.yyyy`, English weekday names vs AyuGram's
`QLocale::ShortFormat`/`langDayOfWeek`).

# admin_tools — Channel/group admin management (Edit Peer Info, Permissions, Admin/Restricted editors, Recent Actions log, Invite Links, Member list, Statistics, Boosts, Monetization, Star-ref)

Scope: `dart/lib/ui/admin_tools.dart` (14,893 lines) vs AyuGram `boxes/peers/*`, `history/admin_log/*`,
`info/statistics/*`, `info/channel_statistics/*`, `info/bot/starref/*`.

**Overall:** This is a faithful, fully-wired reimplementation. Every screen calls real engine methods
(no `onTap: () {}`, no TODO/FIXME/HACK, no "coming soon", no mock/hardcoded data) — confirmed by grep.
Charts parse real `StatsGraph` JSON and load async graphs via `loadStatsGraph`; withdraw flows do the
2FA password round-trip; member/invite/boost/tx lists paginate against real APIs.

Five behavioural/structural deviations were found and **all five are now fixed & verified**
(every fix cross-checked line-by-line against the AyuGram ground truth — exact lang strings,
count semantics, and RPC field flags — plus a clean Go+Flutter build and a no-crash runtime):

1. [MAJOR] EditAdminBox now nests the channel "Manage messages" (Post/Edit/Delete Messages) and
   "Manage stories" (Post/Edit/Delete Stories) admin-right sets in expandable groups with a parent
   master toggle (= any-child-checked), a bold "checked/total" count, and a 180° arrow
   (`_NestedRightsGroup`); `_buildRightsSection` now takes & honors a `nestingLabel` (channel → flat /
   Manage-messages / Manage-stories / flat; group → flat / Manage-stories / flat), mirroring
   `NestedAdminRightLabels` + `AddInnerToggle` (`edit_peer_permissions_box.cpp:119-189`, `:366-472`,
   `:724-763`). Lang strings "Manage messages" / "Manage stories" verbatim.
2. [MAJOR] The Edit-Peer Reactions / Permissions / Invite-Links rows now show live counts —
   `_reactionsCountLabel` (All / count / 1 / Off), `_permissionsCountLabel` (allowed/total via
   `getDefaultBannedRights`, matching `RestrictionsCountValue` = `list.size()-count` over the 14/15-key
   restriction list with keys aligned to the Go struct), and the admin's invite-link count — mirroring
   `edit_peer_info_box.cpp:1523-1593`. **Verified visually**: group shows Off / 13/14 / 1, broadcast
   channel shows All / (permissions hidden) / 8, in both desktop & mobile; engine
   `GetExportedChatInvites` + `GetDefaultBannedRights` succeed in logs.
3. [MAJOR] The live `_antiSpamHeader` now gates on `belowThreshold = _memberCount < _antispamMin`
   (member count forwarded from Go `fc.ParticipantsCount` via `GetChatPermissionFlags`); below threshold
   the toggle is locked + greyed and tapping shows the "not enough members" toast — mirroring
   `menu_antispam_validator.cpp:86-90`. Toast & about lang strings verbatim.
4. [MAJOR] Color/emoji save now fires `channels.updateColor` whenever color OR background-emoji changed
   (color omitted when `colorId < 0`, background-emoji always carried) and a separate
   `channels.updateEmojiStatus`, so bg-emoji / status changes are no longer silently dropped when no name
   color is set — mirroring `edit_peer_color_box.cpp:598-617` (Go `UpdateChannelColorEx` +
   `UpdateChannelEmojiStatus`; Dart `colorChanged`/`bgChanged`/`statusChanged` guards). Confirmed the
   no-color (`colorId < 0`) scenario exists on the test channel and the dialog opens correctly.
5. [MAJOR] The Recent-Actions rights-diff label maps add `manage_direct` ("Manage direct messages"),
   `manage_ranks` ("Edit member tags") and `edit_rank` ("Edit own tags") in both the Dart label tables and
   the Go right-maps (`ManageDirectMessages` / `ManageRanks` / `EditRank`), so those flips now render a
   `+`/`−` diff line — labels verbatim from AyuGram lang strings.

# advanced_settings_screen — Advanced settings page (§14.7) + sub-dialogs (proxy, local storage, auto-download, power saving, dictionaries, recent downloads, experimental)

Overall the file is a faithful, fully-wired port: every toggle/slider forwards to the
engine or persists via AppState (`SetProxy`, `SetAutoDownload`, `SetLocalStorageLimits`,
`ClearCacheByTag`, `SetPowerSaving`, `SetExperimentalFlag`, autostart file writes, real
GitHub update download). The auto-download `SizeLimitByIndex` curve, local-storage
ladders, cache-tag order, power-saving bit flags, CloseBehavior enum values, and
MTPROTO secret/proxy-link parsing all match AyuGram exactly. No stubs, empty callbacks,
mock data, or "coming soon" placeholders found.

Four PowerSavingBox structure/label deviations were found and **all four are now fixed &
verified** (each cross-checked against AyuGram ground truth — `lang.strings:927-945`,
`settings_power_saving.cpp:31-130`, `settings_advanced.cpp:838` — plus a clean Flutter build
and a no-crash runtime smoke-test in BOTH desktop 1024×768 and mobile 400×720):

1. [MAJOR] The "Save Power on Low Battery" auto-toggle now sits BELOW the feature checkboxes
   (after `AddSkip`+`AddDivider`+`AddSkip`: an 8px gap, a `BoxContentDivider`, another 8px gap)
   and is followed by the explanatory `lng_settings_power_auto_about` divider-text on a
   `boxDividerBg` band ("Automatically disable all animations when your laptop is in a battery
   saving mode.") — mirroring `settings_power_saving.cpp:69-80`. **Verified visually** in both
   modes: the toggle renders after Calls / Interface Animations, about-text band directly below it.
2. [MAJOR] The "Power saving options" subtitle (`AddSubsectionTitle(lng_settings_power_subtitle)`)
   now renders right below the title — `settings_power_saving.cpp:46`. Verified visible in both modes.
3. [MAJOR] Title fixed "Power Saving" → "Power Usage" (`lng_settings_power_title`) and the
   auto-toggle label fixed "Automatic Power Saving" → "Save Power on Low Battery"
   (`lng_settings_power_auto`) — `lang.strings:928`/`:944`. Both verified on screen in both modes.
4. [MAJOR] The Performance-section row that opens the box is relabeled "Power Saving" →
   "Battery and Animations" (`lng_settings_power_menu`) — `settings_advanced.cpp:838`,
   `lang.strings:927`. Verified in both modes.

# auth_screen — Telegram intro/login flow (phone, code, 2FA, signup, email, QR)

Audited `dart/lib/ui/auth_screen.dart` against AyuGram `intro/*` (phone, code,
code_input, password_check, signup, email, qr, step, widget, intro.style). The
screen is genuinely wired end-to-end: every button calls `authState.submitInput`
/ `switchToMethod` / `cancelAuth`, the engine populates all `AuthStateData`
fields (`go/engine/auth.go`), the special commands (`__no_telegram_code`,
`__resend_code`, `__request_recovery`, `__reset_account`, `qr_code`) are handled,
the QR payload + auto-call countdown + Fragment delivery are real, and the
passkey link is correctly gated out (no fake button under the no-CGo
constraint). The five feature-parity / data-flow gaps below are **all fixed &
verified FIXED & closed** (Stage-2 verification — clean Go + Flutter debug build,
each fix cross-checked 1:1 against AyuGram ground truth, and a no-crash runtime
smoke-test; items 2 & 3 confirmed VISUALLY on the live OTP step in BOTH desktop
1024×768 and mobile 400×720, items 1/4/5 code-verified end-to-end since the 2FA /
pushed-code / account-reset states need a live OTP the dead test sessions can't read):

1. [CRITICAL] Recovery-by-email is now reachable. The engine reports the REAL
   `pw.HasRecovery` via the new `TelegramCore.Get2FAStateDuringAuth` (reads
   `account.getPassword` on the parked `preAuthAPI`, `telegram.go:1645`) in
   `applyTelegram2FAState` (`auth.go:710`), replacing the hardcoded `false` on the
   actual Telegram-user 2FA path (`SubmitOTP` `auth.go:567`, email-detour `:547`).
   The flag serializes as `has_recovery` → `AuthStateData.fromJson`
   (`engine_models.dart:171`) → `_handleForgotPassword` issues `__request_recovery`
   for accounts WITH a recovery email. (Remaining `HasRecovery=false` sites are
   Bale `:828` and bot-token/other-core `tryAuth` `:1007` — not the TG-user path.)
   ← `intro_password_check.cpp:292-323`.
2. [MAJOR] The code step now keeps a persistent "Next" button for all deliveries
   (`_showNext` true for `otp`); `submit()` → OTP `requestCode()` via GlobalKey
   (shakes the first empty cell on incomplete, submits when full). **Verified
   visually** in both modes: "Next" present on the OTP step; clicking it with empty
   cells neither submits nor crashes. ← `intro_code.cpp:424-431`, `intro_widget.cpp:729-740`.
3. [MAJOR] Code-step subtitle is now localized + delivery-specific
   (`lng_intro_email_confirm_subtitle` / `lng_code_from_telegram` / `lng_code_desc`,
   `**` markers stripped) per `updateDescText`. **Verified visually** in both modes:
   the live OTP step rendered "A code was sent via Telegram to your other devices,
   if you have any connected." (the `lng_code_from_telegram` branch, incl. the
   "other devices" guidance the old hardcode dropped). ← `intro_code.cpp:83-115`.
4. [MAJOR] Auto-fill of a pushed login code is wired end-to-end: core
   `extractLoginCode` parses `tg://login?code=` from 777000 messages →
   `UpdateLoginCode` → `EventLoginCode` → `AuthState._handleLoginCode` (otp,
   non-Fragment guard) → `_OtpCodeInput.applyLoginCode` (setCode + requestCode).
   ← `intro_code.cpp:59-62`.
5. [MAJOR] 2FA/reset texts pulled from the lang pack: `lng_signin_recover_desc`,
   `lng_signin_no_email_forgot`, `lng_signin_sure_reset`/`_reset`, and a localized
   `_resetWaitText` (round-up-by-59s + `lng_signin_reset_in_days`/`_in_hours` +
   `lng_days`/`_hours`/`_minutes` plurals via the new `LangPack.trCount`) — the
   plural math and string values match AyuGram 1:1. ← `intro_password_check.cpp:350-358, 316-317`, `intro_widget.cpp:570-628`.

# ayu_appearance_page — AyuGram Appearance settings (App Icon, Avatar Corners, Appearance, Chat Folders, Tray/Drawer Elements)

Audited `dart/lib/ui/ayu_appearance_page.dart` against AyuGram's `settings_appearance.cpp`,
`icon_picker.cpp`, `avatar_corners_preview.cpp`, and `font_selector.cpp`.

Overall this is a high-fidelity port. Verified to MATCH AyuGram ground truth:
- App-icon grid: 12 icons in identical order, `kColumns=4`, all 12 PNG assets present and
  registered in pubspec, 68px selection box / 64px image / radius 12 / 200ms easeOutCubic
  crossfade (`icon_picker.cpp:24-37,56-65,67-92`, `ayu_styles.style`).
- Avatar corners: `photoSize=46`, row `height=62`, `kMaxAvatarCorners=23`, 22px avatar indent,
  2px preview top-margin, slider 0..23 with 23 divisions, SQUARE/CIRCLE/number badge, radius
  formula `corners/23 * photoSize/2` (`dialogs.style:93-101`, `ayu_ui_settings.h:11`,
  `avatar_corners_preview.cpp:40-78`).
- Preview wired to real engine (`resolveUsername`+`downloadSingleAvatar`), tap opens the channel,
  EmptyUserpic fallback — matches `avatar_corners_preview.cpp:104-130,93-102`.
- Font selector: real system-font enumeration per-platform, search/filter (word-prefix),
  arrow/page-key navigation, "No fonts found." empty state, Reset/Cancel/Save — matches
  `font_selector.cpp:355-400,967-993,696-717`.
- Restart prompt faithfully ported (Restart Now/Later, real `Process.start`+`exit`) — matches
  `ShowRestartPrompt` (`settings_ayu_utils.cpp:36-45`).
- All toggles (Appearance, Chat Folders, Tray, Drawer) present in the same order with persisting
  setters; lang strings (`MD3 Switch Style`, descriptions, etc.) match `lang.strings:8039-8105`.

The one backend-wiring gap below is now **FIXED & verified closed** (Stage-2:
clean Go + Flutter debug build; live `GetMainMenuBots` engine round-trip returned
OK; Drawer Elements section rendered correctly in BOTH desktop 1024×768 and mobile
400×720; no crash):

[CRITICAL] FIXED — the "Bots" drawer-element toggle is now wired to live backend
data. `AppState.setMenuBots` previously had zero callers (so `menuBots` was
permanently empty and the toggle could never appear); it is now fed by the new
`AppState.ensureMenuBotsLoaded`, triggered post-frame from BOTH
`ayu_appearance_page.dart` and `hamburger_drawer.dart` (idempotent, dedup +
retry-on-not-connected). That calls `EngineService.getMainMenuBots` → bridge
`GetMainMenuBots` → `Engine.GetMainMenuBots` → `TelegramCore.GetMainMenuBots`,
which filters `MessagesGetAttachMenuBots` by `ShowInSideMenu` (gotd flag bit 4 =
`show_in_side_menu`) AND a `default_static` icon — an exact mirror of AyuGram's
`HasDrawerBots` gate (`bot.inMainMenu && bot.media`; `ResolveIcon` keys on
`"default_static"` to set `media`), with field semantics confirmed 1:1 against the
gotd/td schema (rules out a false-negative filter). Verified at runtime: the engine
round-trip returned OK live; the connected test account has no `show_in_side_menu`
bot, so the toggle is correctly hidden (Drawer Elements shows My Profile → New
Group adjacent, no Bots row) in BOTH modes — exactly AyuGram's `HasDrawerBots →
false` behavior. (The positive visual case — toggle visible — could not be directly
shown because no available test account has a side-menu bot; the false-negative
filter risk was instead ruled out by the field-semantic verification above.)
— `ayu_appearance_page.dart`, `app_state.dart` `ensureMenuBotsLoaded`,
`telegram.go` `GetMainMenuBots` ← `settings_appearance.cpp:291` + `:41-51`
(`HasDrawerBots`) + `bot_attach_web_view.cpp:113` (`ResolveIcon`).

# ayu_general_page — AyuGram "General" settings page (translation provider, QoL toggles, webview, confirmations)

Compared against `ayu/ui/settings/settings_general.cpp` (`BuildQoLToggles`/`BuildTranslator`/`BuildShowPeerId`) and `ayu/ui/settings/settings_ayu_utils.cpp` (`ShowRestartPrompt`/`AddBetaBadge`).

Overall this file is faithfully wired: section order, dividers, subsection titles, all 15 toggles/choosers match the C++ 1:1; every `appState.setX` setter is real and persists via `_saveWindowPrefs()`; every setting is genuinely consumed by a real feature (verified consumers in chat_list_panel, info_panel, web_app_panel, chat_view, main.dart); `_showRestartPrompt`/`flushSettingsSync` are real (no stubs, no empty callbacks, no mock data). Two behavioral/label deviations were found and both are now fixed & verified (Spoof Client as Android label confirmed in app at desktop+mobile; macOS native-translation toast wired with exact `lng_translate_settings_use_platform_mac_about` text / 6s duration, correctly gated to `Platform.isMacOS` + Native provider — verified no toast erroneously fires on Linux and the provider selection flow works).

# ayu_other_page — AyuGram "Other" settings page (donations, crash reporting, URL scheme, reset)

Overall this is a faithful, fully-wired port. Donate addresses/colors/order match `settings_other.cpp:154-158` exactly; all lang strings match `lang.strings:8060-8074`; crash-reporting toggle is wired to `AppState.setCrashReporting` (real), reset → `resetAyuSettings` (comprehensive, not a stub), the support-description link opens the donate info box (matches `tg://support` → `HandleSupport` → `FillDonateInfoBox`, `ayu_url_handlers.cpp:134-145`), the username link calls `engine.resolveUsername` (real bridge `ResolveUsername`), QR copy hits the clipboard + toast, and RC config URLs/defaults/hourly-timer mirror `rc_manager.cpp`. No placeholders, stubs, empty callbacks, or mock data. Two deviations from the C++ authority were found and both are now fixed & verified: (1) the DonateInfoBox is capped at `int(aboutWidth*1.1)=429px` via a `ConstrainedBox` (`ayu_other_page.dart:655`) — measured exactly 429px logical on a 1024px desktop window (pixel scan of the box background) and shrinks to 320px at 400px width (fits, no overflow; confirmed by a widget test at both surface sizes). (2) `_applyRcData` now overwrites a donate field only when the JSON value `is String && isNotEmpty` (`ayu_other_page.dart:558-580`), mirroring `rc_manager.cpp:187-206` — a JSON number/empty-string/null is rejected and the compiled-in default kept; verified against the live RC endpoint, which returns every donate field as a non-empty string ($5.0 / 2.39 TON / 367₽ / @ayugramOwner), applied identically to C++.

# bridge_web — Web (WASM) JS-interop bridge to the Go cores

`dart/lib/bridge/bridge_web.dart` is the **web/WASM implementation** of `BridgeImpl`, selected at
compile time by the conditional import in `bridge.dart:9-11` when `dart.library.js_interop` is
available. It marshals serialized protobuf bytes to/from the Go cores compiled to `cores.wasm`,
calling the JS functions `globalThis.bridgeCall` / `globalThis.bridgeSetEventCallback` that the Go
WASM `main()` registers (`go/cmd/bridge/main_js.go:38-39`).

**No AyuGram counterpart exists.** AyuGram Desktop is a C++/Qt Telegram client; it has no
Go-backend, no `dart:ffi`/`dart:js_interop` bridge, and does not compile to WASM. This is
project-specific architectural plumbing, not a UI widget/screen/behavior, so there is no AyuGram
`.cpp`/`.style` source to compare against. Per the audit's spirit (find stubs / broken wiring /
bugs), the "reference" side of each finding below cites the **in-repo ground-truth** that defines
what this file must do: the bridge contract (`bridge.dart`), the native sibling that already
satisfies it correctly (`bridge_ffi.dart`), the Go WASM entrypoint (`main_js.go`), and the web
host page (`web/index.html`).

## Findings

Both findings were fixed & verified — no open items remain.

(1) [CRITICAL] **Init race closed.** `bridge_web.dart` now binds `@JS('bridgeReady')` and `init()`
`await`s `window.bridgeReady` before touching the JS exports. The gate is real: `index.html:21`
creates the Promise and resolves it at `:26` *after* `go.run()`, and `main_js.go:34-44` registers
`bridgeCall`/`bridgeSetEventCallback` synchronously inside `main()` before `go.run()` yields — so by
the time the Promise resolves the exports are guaranteed present. The `init()` contract is now
`Future<void>` across `bridge.dart`/`bridge_ffi.dart`/`bridge_stub.dart`, and
`engine_service.dart:111` `await`s it before firing the `Init` call. The native `bridge_ffi.dart`
body stays await-free, so it still completes synchronously and preserves the exports-ready
guarantee — confirmed by the non-awaiting `bridge_test.dart:51` FFI test still passing and the
desktop app reaching `__engine.Init OK` and rendering in both desktop+mobile modes with no crash.

(2) [MAJOR] **`callAsync` corrected.** Switched `Future.microtask(() => call(...))` →
`Future(() => call(...))` (event-queue task) so the loop drains pending microtasks *and* queued
I/O/frame callbacks before the blocking Go call. The `bridge_web.dart` and `bridge.dart` doc-comments
now state the true per-platform behavior (native = worker isolate, non-blocking; web = single JS
thread, still blocks, would need a Web Worker for genuine off-main-thread). `flutter analyze
lib/bridge/` is clean for all four bridge files; `bridge_web.dart` compiles for web (dart2js CFE
reports no js_interop errors — the only web-build failure is the pre-existing app-wide `dart:ffi`
use in the notification system, untouched by this chapter).

## Verified OK (no finding)

- **No placeholders/stubs.** Every method is wired to real JS interop: `init` →
  `bridgeSetEventCallback` (`:37`), `call` → `bridgeCall` (`:47`), events → `_onEventFromGo`
  re-broadcast (`:64-66`). No empty callbacks, TODO/FIXME, mock data, or "coming soon" feedback.
- **Byte marshaling is correct and symmetric** with the Go side: `requestBytes.toJS` /
  `jsResp.toDart` (`:46-48`) pair with `js.CopyBytesToGo` / `js.CopyBytesToJS` in
  `main_js.go:55-64`; empty responses round-trip as `Uint8List(0)`.
- **`dispose()` ordering is safe** (`:57-62`): it clears the JS callback *before* closing the
  controller, so — because JS/WASM is single-threaded — no event can arrive after close. (The native
  sibling's extra `!isClosed` guard at `bridge_ffi.dart:82` is therefore not strictly required here;
  noting only as a defensive-parity nicety, not a bug.)
- **`init({String? libraryPath})` ignoring `libraryPath`** is correct: on web the module is loaded by
  `index.html`, not by a path — matching the conditional-import contract in `bridge.dart:23`.
- **Public API matches the contract** (`events`, `isInitialized`, `init`, `call`, `callAsync`,
  `dispose`) — same surface as `bridge_ffi.dart` and `bridge_stub.dart`, so the conditional import
  type-checks on all platforms.

# ayu_toggle — Custom toggle/switch widget (port of Ui::ToggleView, defaultToggle style)

Overall this is a faithful port: all dimensions (border 2, diameter 14/16, shift -2/1, width 14,
animPadding 2), colors (track/border lerp checkboxFg→windowBgActive, thumb fill windowBg), the
material-vs-non-material duration switch (150ms / 120ms = universalDuration), and the
easeOutCubic-in-direction-of-travel curve all match the source exactly for the normal (un-interrupted,
LTR) case. No placeholders/stubs — `onChanged` is the correct delegation pattern for a presentational
widget. The findings below are genuine behavioral deviations from the C++ source.

All three findings were fixed & verified PASS — no open items remain. (Stage-2: built, launched, exercised in desktop+mobile, cross-checked vs AyuGram source, plus a render+timing test on the painter.)
- RTL mirroring: `_TogglePainter` now maps both track and thumb x through `_rtlX(x,w,outerW)=outerW-x-w` (1:1 port of `style::rtlrect`), driven by the ambient `Directionality` (`ayu_toggle.dart:151,221-222,236,252`). Render test: ON-thumb sits right in LTR (frac 0.72), mirrored to the left in RTL (frac 0.28).
- Mid-animation interruption: `forward()/reverse()` on a `CurvedAnimation` replaced by AyuGram's `startPrepared` model — capture the live value as `_from`, target as `_to`, a fresh transition, then run the controller `forward(from:0)` over the FULL duration; `_currentValue()` lerps manually so the off curve is the true `(1-dt)³` and there is no `CurvedAnimation._curveDirection` to latch (`ayu_toggle.dart:60-107`, exact `_EaseOutCubic` polynomial `:12-22`). Timed test (pumpAndSettle@1ms): normal=151ms, interrupted-at-75ms=151ms (full restart, not the buggy scaled ~75ms), non-material=121ms.
- `shouldRepaint` now includes the paint-affecting fields `isMaterial`/`switchDiam`/`switchShift`/`isRtl` (`ayu_toggle.dart:281-291`). Verified live: flipping the MD3 Switch Style setting repaints at-rest, untouched toggles to the new geometry immediately (fat material pill ⇄ thin non-material track), and back.

# birthday_picker — Telegram birthday drum picker (day/month/year wheels), port of AyuGram `EditBirthdayBox` + `VerticalDrumPicker`

Scope note: the numeric port is faithful — max-date clamping (`edit_birthday_box.cpp:55-66`), leap-year/month/day counts (`:108,146-154`), year index/"—" handling (`:63-66,104-107`), column widths quarter|half|quarter and order day|month|year (`:92-99`), selection-band lines (`:181-187`), the yScale squish + opacity fade (`vertical_drum_picker.cpp:40-47`), and the result mapping (`:201-206`) all match. Both callers (`my_profile_page.dart:305 updateBirthday`, `contacts_screen.dart:1763 suggestBirthday`) wire the returned record to the engine, so there is no stub/broken-wiring issue. The findings below are missing/wrong interaction behaviors.

All five [MAJOR] findings were fixed & verified PASS — no open items remain.
(Stage-2: built + launched, opened the picker live via Settings → My Account →
Date of Birth, exercised it in the running app, plus a render/timing widget test
on `_VerticalDrumPicker`; cross-checked 1:1 vs AyuGram source.)
- Tap-to-select: `onTapUp` maps `i = floor((clickY − topBase + scrollOffset)/itemHeight)`
  and animates that row to the centre band (`birthday_picker.dart:541-547` ←
  `vertical_drum_picker.cpp:252-256`). Live: tapping the off-centre "February" row
  brought it to the centre (cy 426→386, "January" pushed up one 40px item); test taps
  day "3" two slots down → it centres.
- Keyboard nav: dialog-level `Focus(autofocus, onKeyEvent)` forwards arrow/PageUp/
  PageDown to the year wheel only via a GlobalKey (`birthday_picker.dart:169-193,218-220`
  ← `edit_birthday_box.cpp:190-195` + `vertical_drum_picker.cpp:224-234`); Up/Left=prev,
  Down/Right=next, Page=ceil(200/40)=5 items, PageUp/Down skip auto-repeat. Widget test
  (`sendKeyEvent` routes through Focus — which the debug harness's HardwareKeyboard
  injection cannot): Down→1877 centres, Up→back, Right/Left mirror, PageDown→1881, PageUp→back.
- Wheel granularity: `onPointerSignal` steps one item per notch by the SIGN of
  `scrollDelta.dy` via animated `jumpByItems(±1)` (`birthday_picker.dart:513-522` ←
  `vertical_drum_picker.cpp:197-201`). Live + test: a single 200px-delta notch moved
  exactly one year (1876⇄1877), both directions — never the old ~5-item raw-delta skip.
- Snap easing: the snap interpolates `_scrollOffset` LINEARLY off a raw
  `AnimationController.value` over the 200ms `fadeWrapDuration`; easeOutCubic stays only
  on the per-item yScale squish in paint (`birthday_picker.dart:409-418,486` ←
  `vertical_drum_picker.cpp:83-87`, `anim::linear`). Timing test: at 50% of the snap a
  one-item move is ~20px in (linear), refuting easeOutCubic's ~35px.
- Month localization: the month wheel paints `lang.tr('lng_monthN')` from the cloud
  LangPack with an English baseline (`birthday_picker.dart:274`; `lng_month1..12` added to
  `lang_pack.dart` keys+baseline ← `edit_birthday_box.cpp:119-124`). Live screenshot shows
  January/February/March/… localized on the wheel.

# calls_screen — Calls box, conference create/invite, call history, level meter

Audited `dart/lib/ui/calls_screen.dart` against AyuGram's `calls_box_controller.cpp`,
`calls/group/calls_group_invite_controller.cpp`, `calls/group/calls_group_common.cpp`,
and `ui/widgets/level_meter.cpp`.

The file is well-implemented overall: every callback is wired to a real engine method
(`getCallHistory`/`clearCallHistory`/`joinGroupCall`/`startCall`/`createConferenceCall`/
`inviteToConferenceCall`/`getGroupCall`/`deleteMessage`/`getContacts`/`getConfcallSizeLimit`),
there are no stubs/placeholders/fake data, `hasActiveCall` is wired end-to-end
(telegram.go `CallNotEmpty` → SQLite cache → protobuf → Dart model), row dimensions match
(`peerListBoxItem` 56px/42px at (16,7)/(74,9)/(74,30); `callReDial`/`callGroupCall` 40×56 ripple
at (0,8); `createCallListItem` 52px/40px; `callArrowPosition` (-2,1); `callArrowSkip` 4px),
the `LevelMeter` matches `defaultLevelMeter` (44 lines, 3px width, 5px spacing, 18px height,
mediaPlayer active/inactive colors), the contact sort matches `SortMode::Alphabet`, and the
labels match the lang pack. One data-flow defect remains (the per-contact conference-invite video flag was fixed and verified 2026-06-08).

- [ ] [MAJOR] Call-history "Delete" ignores the "delete for everyone" (revoke) choice: the context-menu delete opens `showDeleteConfirmBox` in `singleMessage`/`bulkMessages` mode, which renders the revoke checkbox and returns `confirmResult.revoke`, but the handler only reads `confirmResult.confirmed` and calls `engine.deleteMessage(accountId, peerId, msgId)` (no revoke parameter), so the user's "also delete for the other participant" choice has no effect and call-log entries are never revoked for the peer. AyuGram routes the same delete through `Box<DeleteMessagesBox>(session, ids)`, whose revoke checkbox is applied to the delete request. — `calls_screen.dart:2127` ← `AyuGram/Telegram/SourceFiles/calls/calls_box_controller.cpp:585`

# chat_export — Telegram data-export panel (settings / progress / error, single-peer + full)

Engine wiring is complete and real — `startExport`, `onExportProgress/Error/Complete`,
`skipExportFile`, `cancelExport`, `save/loadExportSettings`, `SuggestStartExport`/
`ClearExportSuggestion` are all live FFI calls; no stubs, placeholders, mock data, or
dead callbacks. Default type/fullChats selections, the size-limit curve (`SizeLimitByIndex`),
`requiredRows` (2 single-peer / 3 full), the stop-confirmation copy, the suggest-box copy,
the critical-error layout (no buttons, top-pad = panelH/4), and `FormatDownloadText` all
match AyuGram. The findings below are text/behavioral fidelity gaps vs the AyuGram lang
pack (the project's centralised string table is meant to mirror it 1:1).

## Wrong user-facing strings (paraphrased instead of mirroring the lang pack)

- [ ] [CRITICAL] All six option "about" descriptions are rewritten paraphrases, not Telegram's actual copy — e.g. contacts shows "Exports names and phone numbers." but the real text explains continuous contact syncing & where to disable it; sessions shows "Exports device and login info." vs the real "We may store this to display your connected devices…". Misrepresents what each toggle does — `chat_export.dart:1466,1474,1482,1490,1574,1582` ← `AyuGram/Telegram/Resources/langs/lang.strings:6826,6828,6830,6832,6834,6837`
- [ ] [CRITICAL] Combined format/location label renders "Export data in {fmt} to {path}" — AyuGram's `lng_export_option_format_location` is "Format: {format}, Path: {path}" (entirely different structure) — `chat_export.dart:2095,2112` ← `AyuGram/Telegram/Resources/langs/lang.strings:6858`
- [ ] [CRITICAL] Date-range limits label renders "From {x} till {y}" — AyuGram's `lng_export_limits` is "From: {from}, to: {till}" (colon + "to", not "till"); also the from/till links concat date+time as "{date}, {time}" which the Dart approximates but with abbreviated month (`Jan 5, 2024`) vs AyuGram `langDayOfMonthFull` ("January 5, 2024") — `chat_export.dart:2164-2272` ← `AyuGram/Telegram/Resources/langs/lang.strings:6863` + `AyuGram/Telegram/SourceFiles/export/view/export_view_settings.cpp:459-464`
- [ ] [MAJOR] First account-data checkbox labelled "Personal information" — AyuGram's `lng_export_option_info` is "Account information" — `chat_export.dart:1465` ← `AyuGram/Telegram/Resources/langs/lang.strings:6825`
- [ ] [MAJOR] Option labels mismatched: "Contact list"→should be "Contacts list", "Stories"→"Story archive", "Profile music"→"Music on Profiles", "Other data"→"Miscellaneous data" — `chat_export.dart:1473,1481,1489,1581` ← `AyuGram/Telegram/Resources/langs/lang.strings:6827,6829,6831,6836`
- [ ] [MAJOR] Media option "Video files" should be "Videos" (`lng_export_option_video_files`) — appears in both full and per-chat lists — `chat_export.dart:1798,1993` ← `AyuGram/Telegram/Resources/langs/lang.strings:6849`
- [ ] [MAJOR] Format choice "HTML and JSON" should be "Both" (`lng_export_option_html_and_json`) — used in the full-export radios, the choose-format box, and the combined label's format name — `chat_export.dart:1597,2089,3236` ← `AyuGram/Telegram/Resources/langs/lang.strings:6862`
- [ ] [MAJOR] Format section header "Format" should be "Location and format" (`lng_export_header_format`) — `chat_export.dart:1590` ← `AyuGram/Telegram/Resources/langs/lang.strings:6856`
- [ ] [MAJOR] Date-range null states show "the beginning" / "now" — AyuGram `lng_export_beginning`="the oldest message", `lng_export_end`="present" — `chat_export.dart:2188,2237` ← `AyuGram/Telegram/Resources/langs/lang.strings:6864,6865`
- [ ] [MAJOR] Calendar reset buttons labelled "From the beginning" / "Till now" — AyuGram `lng_export_from_beginning` and `lng_export_till_end` are BOTH simply "Reset" — `chat_export.dart:2176,2227` ← `AyuGram/Telegram/Resources/langs/lang.strings:6866,6867`
- [ ] [MAJOR] Choose-format box title "Export Format" should be "Choose export format" (`lng_export_option_choose_format`) — `chat_export.dart:3223` ← `AyuGram/Telegram/Resources/langs/lang.strings:6859`
- [ ] [MAJOR] Time-picker box title "Choose Time" should be "Set Custom Time" — AyuGram reuses `lng_settings_ttl_after_custom` for this box title — `chat_export.dart:3070` ← `AyuGram/Telegram/SourceFiles/export/view/export_view_settings.cpp:508` (`AyuGram/Telegram/Resources/langs/lang.strings:1001`)
- [ ] [MAJOR] Progress title "Exporting Data..." should be "Exporting your data" (`lng_export_progress_title`, no ellipsis); the top-bar prefix also uses an em-dash (U+2014) where AyuGram uses an en-dash (U+2013, `QChar(0x2013)`) — `chat_export.dart:482,77` ← `AyuGram/Telegram/Resources/langs/lang.strings:6824` + `AyuGram/Telegram/SourceFiles/export/view/export_view_top_bar.cpp:89-91`

## Behavioral / numeric deviations

- [ ] [MAJOR] `_enforceOffset` always pushes the **till** endpoint forward to `from + 600s` when the range is < 600s apart. AyuGram applies the offset to the field being edited: editing the *from-time* moves **from backward** (`singlePeerFrom = singlePeerTill - kOffset`), and editing a from-*date* applies no offset at all (the calendar maxDate already clamps it). So setting from-time close to till adjusts the wrong endpoint vs AyuGram — `chat_export.dart:2152-2162` ← `AyuGram/Telegram/SourceFiles/export/view/export_view_settings.cpp:527-588`
- [ ] [MAJOR] On finish, the single-peer/topic panel keeps `settingsTitle` ("Chat export settings" / "Topic export settings"). AyuGram's `FinishedState` always resets the panel title to `lng_export_title` ("Export Your Data") regardless of mode — `chat_export.dart:482` ← `AyuGram/Telegram/SourceFiles/export/view/export_view_panel_controller.cpp:408-410`
- [ ] [MAJOR] `_formatSize` (finished "Total size:" row) adds a GB tier and uses `toStringAsFixed(1)` (rounds). AyuGram `FormatSizeText` has NO GB tier — anything ≥1 MB is shown as "X.Y MB" (e.g. a 2 GB export → "2048.0 MB") — and truncates via integer tenths rather than rounding — `chat_export.dart:2659-2668` ← `AyuGram/Telegram/SourceFiles/ui/text/format_values.cpp:54-68`
- [ ] [MAJOR] Finished "Total files:" count is comma-grouped (`_formatFileCount`, e.g. "1,234"); AyuGram `lng_export_total_amount` fills `{amount}` with a plain `QString::number` (no grouping, "1234") — `chat_export.dart:2496,2648-2657` ← `AyuGram/Telegram/SourceFiles/export/view/export_view_content.cpp:181`

# chat_list_panel — left dialogs panel (search, folders, stories, top peers, forum/saved, reaction tags)

Audited the full 7243-line file against AyuGram dialogs sources. Implementation is
mature: no stubs/placeholders/empty callbacks/"coming soon", every menu action and
button is wired to `chatState`/`engine`, and many dimensions are exact ports
(stories small/full 35/77px, photo 21/42px, shift 16px, lineTwice 3/4px → 1.5/2.0px,
read 1.0px, readOpacity 0.6 — `dialogs.style:716-745`; topPeers item 66px / strip 77px
/ avatar 46px — `dialogs.style:746-750`; search-tabs slider 33px/barTop 30/barStroke 6/
barRadius 2/labelTop 7/strictSkip 18 — `dialogs.style:799-817`; drag thresholds
30/30/75 — `dialogs_inner_widget.cpp:106-108`; archive bar 37px = dialogsImportantBarHeight;
`_colorRemap` value 7 is valid against the 8-colour `peerUserpicBg`). The findings below
are the genuine deviations.

- [ ] [MAJOR] Unread story ring uses the **premium** gradient (`premiumButtonBg1`→`premiumButtonBg2`, blue `#55a5ff`→purple `#a767ff`) instead of AyuGram's stories gradient (`groupCallLive1`→`groupCallMuted1`, green `#0dcc39`→blue `#0992ef`). `UnreadStoryOutlineGradient` is the only source AyuGram uses for the unread story outline. Both colours already exist in the Dart palette (`telegram_palette.dart:570,572`), so the ring renders the wrong hue — purple rather than the iconic green-blue Telegram story ring. — `chat_list_panel.dart:3663` ← `AyuGram/ui/effects/outline_segments.cpp:110-111`

- [ ] [MAJOR] Search-tab order is wrong. Dart `_SearchTabsStrip.tabs` renders `[My Messages, Public Posts, This Peer, This Topic]`, but AyuGram builds the possible-tab list (and thus the on-screen order, null-icon tabs skipped) as `[This Topic, This Peer, My Messages, Public Posts]` — most-specific scope first, My Messages third, Public Posts last. (Note: AyuGram presents these via the `ChatSearchIn` dropdown, not a slider; the order is still observable.) — `chat_list_panel.dart:4143-4151` ← `AyuGram/dialogs/dialogs_inner_widget.cpp:4632-4637`

- [ ] [MAJOR] "Search from" label text does not match the source string. Dart shows `"Search from <name>"` (chosen) and `"Search from a member"` (empty affordance); AyuGram's `_from` section uses `lng_dlg_search_from` = `"From: {user}"`. — `chat_list_panel.dart:4470` & `chat_list_panel.dart:4484` ← `AyuGram/dialogs/ui/chat_search_in.cpp:288` (`Resources/langs/lang.strings:475` `"From: {user}"`)

- [ ] [MAJOR] No-chats empty state has wrong text and wrong action. Dart shows `"You have no\nconversations yet."` + subtitle `"Your contacts on Telegram"` + a `FilledButton("New Message")` that calls `showContactsBox` (the contact picker). AyuGram's `EmptyState::NoContacts` shows `lng_no_chats` = `"Your chats will be here"` + a text link `lng_add_contact_button` = `"New contact"` whose handler is `showAddContact()` (the add-contact form). Different copy and a different destination. — `chat_list_panel.dart:5328-5356` ← `AyuGram/dialogs/dialogs_inner_widget.cpp:4402-4438` (`lang.strings:461`, `lang.strings:5514`)

- [ ] [MAJOR] Archived-chats collapsed row (wide mode) adds a 26px circular archive-icon userpic on the left and pushes the label to ~48px. AyuGram's `PaintCollapsedRow` wide branch draws the folder name as plain text at `st::dialogsTopBarLeftPadding` (18px), semibold `dialogsNameFg`, with **no** leading icon (the userpic is drawn only in the narrow branch). — `chat_list_panel.dart:4723-4746` ← `AyuGram/dialogs/ui/dialogs_layout.cpp:1356-1367`

# chat_list_row — sidebar chat-list row (normal + forum), avatar/stories ring, swipe quick actions, badges

Audited against AyuGram `dialogs/ui/dialogs_layout.cpp`, `dialogs/dialogs_row.cpp`,
`dialogs/ui/dialogs_topics_view.cpp`, `dialogs/ui/dialogs_message_view.cpp`,
`dialogs/dialogs_quick_action.cpp`, `ui/controls/swipe_handler.cpp`,
`ui/effects/outline_segments.cpp`, `dialogs/dialogs.style`, `lib_ui/ui/colors.palette`.

Verified as CORRECT (no findings): timestamp formatter (`FormatDialogsDate` 20h/7-day/short-date
rule), 62px/46px row+avatar dims, unread badge geometry (19px/5px/minWidth19/r9.5/12px-bold),
`..N` digit truncation, badge cluster order (poll→mention/reaction→unread, unread hugs right),
mention-vs-reaction exclusivity (mention priority), draft "Draft: " gating, scam/fake 9px badge,
closed-topic→lock, sending/failed→clock, swipe action lottie-names/labels/bg-colors and
disabled/toggle resolution, unread-story gradient colors (#0dcc39→#0992ef = groupCallLive1→
groupCallMuted1), forum row 80px / topics 21px, outline-segment arc math, forum radius ×0.3,
online badge 12px/3px, gesture→`onAction`/`onTopicTap`/`onStoryTap` wiring (all real, no stubs).

## Forum rows (ForumChatListRow / topic jump bubble)

- [ ] [CRITICAL] Forum row omits the last-message preview line entirely. AyuGram's forum row is three stacked lines — name/date, topics (21px), then the last-message preview (`sender` + mini-thumbs + `_textCache`) drawn below the topics in the remaining height. The Dart `ForumChatListRow` Column is only name → `_TopicsPreview` → optional jump bubble, with no message-preview row at all, so a forum chat shows no "what was last said" text. — `chat_list_row.dart:2323-2426` ← `AyuGram/Telegram/SourceFiles/dialogs/ui/dialogs_message_view.cpp:423-522` (paint topics, advance by `topicsHeight`, then draw sender/images/text) + `dialogs/dialogs.style:107-112` (forumDialogRow 80px, topicsHeight 21px)

- [ ] [MAJOR] Topic jump bubble uses the wrong background color. AyuGram fills the jump-to-last region with a subtle grey hover background `st::dialogsBgOver` (or `st::dialogsRippleBg` when selected). The Dart paints it with the blue unread-badge color `dialogsUnreadBg`/`dialogsUnreadBgActive`, making it read as a notification pill rather than a tappable hover band. — `chat_list_row.dart:2542-2550` ← `AyuGram/Telegram/SourceFiles/dialogs/ui/dialogs_message_view.cpp:548-550` (`.bg = context.selected ? st::dialogsRippleBg : st::dialogsBgOver`)

- [ ] [MAJOR] Jump bubble second area is arrow-only; AyuGram's area2 is the last-message preview text with the arrow appended at its end (`width2 = countWidth() + forumDialogJumpArrowSkip`). The Dart bubble shows topic-title (area1) + a bare `keyboard_arrow_right` (area2) and never renders the message preview inside the bubble. — `chat_list_row.dart:2593-2597` ← `AyuGram/Telegram/SourceFiles/dialogs/ui/dialogs_message_view.cpp:541` (`width2 = countWidth() + ...`) + `:523-528` (arrow at end of preview area)

- [ ] [MAJOR] Front (jump) topic is duplicated. AyuGram rotates the front topic to position 0 of `_titles`, draws the whole topic list once, and the jump bubble is a background that wraps that already-drawn front topic (area1) plus the preview (area2) — the front topic is rendered once. The Dart renders `recentTopics.first` both inside `_TopicsPreview` (which draws all `recentTopics`) and again inside the separate `_TopicJumpBubble`, so the front topic name appears twice. — `chat_list_row.dart:2410-2424` ← `AyuGram/Telegram/SourceFiles/dialogs/ui/dialogs_topics_view.cpp:101-112` (rotate front) + `:221-240` (single draw loop)

- [ ] [MAJOR] `topicsSkipBig` (14px) is not implemented. When the jump bubble is active and the row is not the active chat, AyuGram inserts a larger 14px gap after the front topic (`skipBig = _jumpToTopic && !active`), reverting to the normal 8px `topicsSkip` for subsequent topics. The Dart always uses a fixed 8px `_topicsSkip` between every topic. — `chat_list_row.dart:2467,2498` ← `AyuGram/Telegram/SourceFiles/dialogs/ui/dialogs_topics_view.cpp:210,235-239` + `dialogs/dialogs.style:111` (`topicsSkipBig: 14px`)

## Stories ring (`_StoriesRingPainter`)

- [ ] [MAJOR] Live-stream ring uses the wrong color and wrong render path. AyuGram does NOT draw a solid circle for a video-stream peer: it pushes a single outline segment brushed with `st::attentionButtonFg` (#d14e4e) through the normal round-capped `PaintOutlineSegments`, then overlays a "LIVE" pill via `PaintLiveBadge`. The Dart calls `canvas.drawCircle` with a hardcoded `0xFFe53935` (wrong red), bypassing the segment painter and omitting the LIVE badge entirely. — `chat_list_row.dart:1306-1314` ← `AyuGram/Telegram/SourceFiles/dialogs/dialogs_row.cpp:448-450,483-485` (segment `st::attentionButtonFg->b` + `PaintLiveBadge`) + `lib_ui/ui/colors.palette:48` (`attentionButtonFg: #d14e4e`)

- [ ] [MAJOR] Read-story segment color is fabricated and incorrectly dimmed. AyuGram brushes already-seen story segments with the single palette token `st::dialogsUnreadBgMuted` (#bbbbbb) at full opacity (`dialogsUnreadBgMutedActive` when the row is active). The Dart hardcodes a separate dark-mode color `#3e546a` (which does not exist in the AyuGram dialog-row path) and applies a `readOpacity = 0.6` alpha to both themes — the 0.6 opacity belongs to the stories-list strip style, not the dialog-row outline. — `chat_list_row.dart:1326-1328,1282` ← `AyuGram/Telegram/SourceFiles/dialogs/dialogs_row.cpp:460-462` + `lib_ui/ui/colors.palette:195` (`dialogsUnreadBgMuted: #bbbbbb`)

## Send-state icon (`_SendStateIcon`)

- [ ] [MAJOR] `MsgStatus.delivered` is mapped to the double-check (`Icons.done_all`), but AyuGram shows the double-check (`dialogsReceivedIcon`) ONLY once the recipient has read the message (`!item->unread(thread)`). Any outgoing message still unread by the recipient — i.e. sent/delivered-but-unread — gets the single check (`dialogsSentIcon`). The Dart therefore renders a "read" double-tick for merely-delivered messages. Map `delivered` to the single check and reserve `done_all` for `read`. — `chat_list_row.dart:1803-1809` ← `AyuGram/Telegram/SourceFiles/dialogs/ui/dialogs_layout.cpp:782-794` (`item->unread(thread)` → `dialogsSentIcon` single ✓ else `dialogsReceivedIcon` double ✓✓)

## Message preview (`_buildPreview` / `_mediaTypeIcon`)

- [ ] [MAJOR] `_mediaTypeIcon` invents Material media glyphs (photo_camera/videocam/music_note/mic/gif_box/attach_file…) drawn as a 16px leading icon before the preview text when no thumbnail is present. AyuGram's chat-list row has no per-media-type icon: the media indicator is the emoji baked into the server-side preview text, and the only graphical element is the real 16px image thumbnail (`dialogsMiniPreview`). The `_stripMediaEmoji` + Material-icon substitution diverges from the 1:1 source. — `chat_list_row.dart:489-518` ← `AyuGram/Telegram/SourceFiles/dialogs/ui/dialogs_message_view.cpp:473-503` (mini-preview path draws the real image only; no icon glyph)

## Swipe quick actions (`_SwipeableChatRowState`)

- [ ] [MAJOR] `kSwipeSlow` (0.2) is applied to the wrong input path. In AyuGram the 0.2 slowdown is applied ONLY to wheel/trackpad deltas (`state->delta + delta * kSwipeSlow`, inside `case QEvent::Wheel`); a touch drag tracks the finger 1:1 and is simply clamped to `kMaxRatio` (1.5× threshold ≈ 75px). The Dart instead multiplies the touch-drag delta by 0.2 once past the 50px threshold, producing a rubberband lag in the 50–75px range that AyuGram does not have for touch. — `chat_list_row.dart:800-802` ← `AyuGram/Telegram/SourceFiles/ui/controls/swipe_handler.cpp:361` (kSwipeSlow used only in the wheel branch) + `:341,28`

- [ ] [MAJOR] Below-threshold spring-back duration is wrong. AyuGram always animates the reset over `std::min(1., ratio) * st::slideWrapDuration` (150ms) for both commit and abort, so an aborted swipe snaps back in proportion to how far it traveled (ratio 0.5 → 75ms). The Dart uses a fixed 200ms for every below-threshold cancel/release and only scales the commit case. — `chat_list_row.dart:838-842,855` ← `AyuGram/Telegram/SourceFiles/ui/controls/swipe_handler.cpp:168` (`std::min(1., ratio) * st::slideWrapDuration`)

# chat_settings_screen — Settings::Chat (themes, background, quick-action, stickers/emoji, messages, sensitive, archive)

Overall the screen is well-built and the section ORDER matches AyuGram's
`BuildChatSectionContent` (settings_chat.cpp:1306-1317): ThemeOptions →
ThemeSettings → CloudThemes → ChatBackground → ChatListQuickAction →
StickersEmoji → Messages → Sensitive → Archive. All 20 EngineService calls
(themes, wallpapers, peer colors, stickers, reactions, content/archive
settings) are REAL — they reach the Telegram MTProto backend; no stubs. The
theme cards, accent palette, system-accent checkbox, cloud themes, peer color,
auto-night, font, wallpaper, chat-list quick action (`swipeAction` is consumed
in `chat_list_panel.dart:1029`) and the emoji/sticker toggles are all wired and
persisted.

The problems are concentrated in the **Messages** section: four controls there
are placebos — they persist to `window_prefs.json` but **nothing in the app
ever reads them**, so toggling them has zero observable effect. In AyuGram each
is a working feature consumed by the message list.

- [ ] [CRITICAL] Double-click quick-action radios (`Reply` / `React`) + reaction chooser are a placebo — `chatDoubleClickAction`/`chatDoubleClickReaction` are written (chat_settings_screen.dart:679-680, set in app_state.dart:3322/3324) but there is **no `onDoubleTap` handler anywhere in `chat_view.dart`** (grep: zero double-tap on messages) and no reader of the value. In AyuGram these radios drive `Core::App().settings().chatQuickAction()`, consumed when double-clicking a message to reply/react. Building the React radio also sets the favorite reaction; here `setDefaultReaction` is called server-side but the default reaction is never read back by the local reaction UI either (`message_bubble.dart:1850` uses `availableReactions`/a hardcoded list). — `chat_settings_screen.dart:4438-4458` ← `AyuGram/Telegram/SourceFiles/history/view/history_view_list_widget.cpp:2888` (setting built at `settings_chat.cpp:1653-1668`)

- [ ] [CRITICAL] "Reply button on messages" checkbox is a placebo — `chatShowReplyButton` is stored/persisted (chat_settings_screen.dart:681, app_state.dart:3326) but no message bubble renders a corner reply button from it (only references are the storage + this settings screen). In AyuGram `cornerReply` is consumed to draw the hover/corner reply button on messages. — `chat_settings_screen.dart:4465-4470` ← `AyuGram/Telegram/SourceFiles/history/view/history_view_list_widget.cpp:586` (setting built at `settings_chat.cpp:1776`)

- [ ] [CRITICAL] "Reaction button on messages" checkbox is a placebo — `chatShowReactionButton` is stored/persisted (chat_settings_screen.dart:682, app_state.dart:3328) but no message bubble renders a corner reaction button from it. In AyuGram `cornerReaction` is consumed to draw the hover/corner reaction button on messages. — `chat_settings_screen.dart:4471-4476` ← `AyuGram/Telegram/SourceFiles/history/view/history_view_list_widget.cpp:576` (setting built at `settings_chat.cpp:1795`)

- [ ] [MAJOR] "Choose emoji set" opens the wrong manager — it opens `_StickerPackManager(type:'emoji')` which lists/searches/removes installed **custom emoji sticker packs** via `getInstalledEmojiSets`. AyuGram's `lng_emoji_manage_sets` button opens `Ui::Emoji::ManageSetsBox`, the emoji **rendering-set** picker (download/switch Twemoji, JoyPixels, …). The rendering-set feature is absent; the button does a different thing than the source intends. — `chat_settings_screen.dart:3912-3917` ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_chat.cpp:1570-1577` (box defined at `chat_helpers/emoji_sets_manager.cpp:45`)

- [ ] [MAJOR] Sensitive-content description text does not match the source — Dart shows "Display sensitive media in public channels on all your Telegram devices." (an older Telegram string), but AyuGram's `lng_settings_sensitive_about` is "Do not hide media that contains content suitable only for adults." — `chat_settings_screen.dart:5179` ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_privacy_security.cpp:311` (string at `Resources/langs/lang.strings:894`)

# engine_service — FFI bridge/service layer (proto/JSON ↔ Go backend)

Overall: this file is a faithful, fully-wired RPC layer. Every public method
forwards to the Go engine via `_callRaw`/`_callAsync` — no stubs, no mock data,
no empty callbacks, no fabricated lists, no "coming soon" returns. All literal
`return []`/`{}`/`0`/`false` are legitimate empty-response or catch fallbacks.
The waveform decoder (`_decode5BitWaveform`, `engine_service.dart:7266`) matches
AyuGram `documentWaveformDecode` (`data/data_document.cpp:1333`) exactly.

The only genuine deviation class: the file documents `_safeStr` as "the single
choke point where AyuGram's Filter Zalgo strip is applied" (`engine_service.dart:16-20`,
mirroring `filterZalgo` at `ayu/utils/telegram_helpers.cpp:1260`, applied in
AyuGram to peer names `data/data_user.cpp:365`, `data/data_channel.cpp:143`,
`data/data_chat.cpp:122`, and message text `history/history_item.cpp:4157`).
Several manual model-construction paths bypass that choke point, while their
sibling proto converters apply it — proving the omission is unintentional. When
the user enables Filter Zalgo, these paths render unfiltered names/text.

- [ ] [MAJOR] `getDeletedMessages` builds `CachedMessage` with raw `sender_name` and `content_text` (also `reply_preview`, `forward_from`), bypassing `_safeStr` — the sibling `_cachedMsgFromProto` applies `_safeStr` to the exact same fields (`senderName` `:6974`, `contentText` `:6977`, `replyPreview` `:6984`, `forwardFrom` `:6985`). The deleted/anti-recall message viewer therefore shows zalgo-unfiltered text & sender names, unlike the live message view — `engine_service.dart:3331-3332` ← `AyuGram/Telegram/SourceFiles/history/history_item.cpp:4157` (message text) + `AyuGram/Telegram/SourceFiles/data/data_user.cpp:365` (names)

- [ ] [MAJOR] `getChatMembersByRole` builds `MemberInfo` with raw `display_name`, `username`, `custom_rank`, `promoted_by`, bypassing `_safeStr` — the sibling `_memberInfoFromProto` applies `_safeStr` to those same fields (`username` `:7190`, `displayName` `:7191`, `customRank` `:7196`, `promotedBy` `:7197`). The participants/admins/banned lists in the group profile render zalgo-unfiltered member names — `engine_service.dart:1206-1215` ← `AyuGram/Telegram/SourceFiles/data/data_user.cpp:365`

- [ ] [MAJOR] Peer/participant display names bypass `_safeStr` in four more converters that build display models directly, while every other proto→model converter in this file applies it: `_savedSublistFromProto.peerName` (`engine_service.dart:223`, Saved Messages sublist authors), `getSendAs` participant `displayName` (`engine_service.dart:2335`, send-as picker), `getGroupCall` participant `displayName` (`engine_service.dart:2406`, group-call participant list), `getMessageReactorsList` `peerName` (`engine_service.dart:4325`, "who reacted" list). AyuGram renders all of these via the zalgo-filtered `peer->name()` — `engine_service.dart:223,2335,2406,4325` ← `AyuGram/Telegram/SourceFiles/data/data_user.cpp:365` + `AyuGram/Telegram/SourceFiles/data/data_channel.cpp:143`

# chat_switch_overlay — Ctrl+Tab "alt-tab" chat switcher overlay (AyuGram ChatSwitchProcess port)

Audited against `window/window_chat_switch_process.cpp` + `window/window.style`. The
overlay is a remarkably faithful port: every dimension matches the style table
(cell 72×104, userpic 56/40/24, top 8, nameSkip 6, selectLine 3, margins 16,
padding 12, radius `boxRadius`=6, maxPerRow 7, maxRows 3), the selection color is
`defaultRoundCheckbox.bgActive`=`windowBgActive` with the 150ms `slideWrapDuration`,
the row/column layout algorithm (`layout()` cpp:420-457) is reproduced line-for-line,
keyboard nav (Tab/Backtab/arrows/Q/Esc/Enter + Ctrl-release confirm), the initiating
Tab/Backtab step, tap-outside-to-close vs panel-absorb (the `onTap: () {}` at :371 is
the deliberate `e->accept()` absorber from cpp:415, NOT a stub), and the backend wiring
(`collectChatOpenHistory`→`onChosen`/`openChat`, `onRemove`/`removeChatFromOpenHistory`,
Ctrl+Tab trigger via keyboard_shortcuts.dart) are all correct and fully connected.

Two avatar-rendering deviations from the codebase's own canonical userpic renderer
(`chat_list_row.dart`) and from AyuGram's `Ui::UserpicButton`:

- [ ] [MAJOR] Avatar `Image.file`/`Image.memory` decode at full source resolution — no `cacheWidth`/`cacheHeight`. The canonical userpic renderer caps decode at `photoSize*2`, and AyuGram's `Ui::UserpicButton` rasterizes only at the fixed `photoSize` (56/40/24px); here a 640px avatar file is decoded at full res for a 56px (or 20px badge) display, ~30× the needed pixels, across up to 21 cells. Affects all four image calls (`:509`, `:518`, `:592`, `:598`). — `chat_switch_overlay.dart:518` ← `AyuGram/Telegram/SourceFiles/window/window.style:356` (`photoSize: 56px`); canonical in-repo pattern: `chat_list_row.dart:1134` (`cacheWidth: (photoSize * 2).toInt()`)

- [ ] [MAJOR] Avatar images have no `errorBuilder` fallback — a missing/corrupt avatar file renders Flutter's default broken-image glyph instead of the initials/empty-userpic fallback. The initials fallback (`_buildBaseUserpic` :524-541) is only reached when `avatarPath.isEmpty`; a non-empty path that fails to load is unhandled. AyuGram's `Ui::UserpicButton` always renders a valid userpic via the empty-userpic system and never shows a broken image; the canonical renderer wires `errorBuilder → _fallback(...)`. Affects `:509`, `:518`, `:592`, `:598`. — `chat_switch_overlay.dart:518` ← `AyuGram/Telegram/SourceFiles/window/window_chat_switch_process.cpp:129` (`Ui::CreateChild<Ui::UserpicButton>` always-valid userpic); canonical in-repo pattern: `chat_list_row.dart:1137` (`errorBuilder: (_, __, ___) => _fallback(...)`)

# choose_datetime_box — Calendar / ChooseDateTime / MonthYearPicker / TimePicker boxes

Audited `dart/lib/ui/choose_datetime_box.dart` (CalendarBox, ChooseDateTimeBox,
MonthYearPicker, TimePickerBox) against AyuGram `ui/boxes/calendar_box.cpp`,
`ui/boxes/choose_date_time.cpp`, `ui/boxes/time_picker_box.cpp`,
`ui/widgets/vertical_drum_picker.cpp`, `lib_ui/ui/widgets/time_input.cpp` and
`history/view/history_view_schedule_box.cpp`.

The file is broadly faithful: dimensions (cell 48×40, cellInner 34, scheduleHeight
95, scheduleDateWidth 136, scheduleTimeWidth 72, scheduleAtSkip 24, drum 200/40px
= 5 items) all match the `.style` files; the schedule result (`silent`,
`repeatPeriod`, `sendWhenOnline`) is wired to real engine/navigation callers;
`openPremiumSubscription` is a real bridge call; the repeat-row `showRepeat`
gating matches AyuGram (repeat only on the message-schedule path); `looped=false`
matches the drum default; title strings match the lang pack exactly; calendar
keyboard/jump/selection/floating-date behaviour mirrors `calendar_box.cpp`. No
stubs, placeholders, mock data, or dead callbacks were found.

The following are genuine deviations from the AyuGram source:

- [ ] [MAJOR] Time field has NO underline, unlike AyuGram. AyuGram's `TimeInput` paints its border from the **date-field** style (`_stDateField` = `scheduleDateField`, which inherits `border: 1px` / `borderActive: 2px` from `defaultInputField`), so the time field shows a static 1px underline plus an animated 2px focus/error underline — visually matching the date field. The Dart `_TimeInputField` renders a borderless `SizedBox` with no underline at all, leaving the date field (which DOES draw a bottom border at `choose_datetime_box.dart:1760-1765`) and the time field visually asymmetric — `choose_datetime_box.dart:2272` ← `lib_ui/ui/widgets/time_input.cpp:234-237`

- [ ] [MAJOR] Validation error flashes the wrong element. AyuGram's error animation tints the time field's **border** red (`anim::brush(_st.borderFgActive, _st.borderFgError, errorDegree)` on the underline; the digits keep their colour). The Dart instead lerps the **digit/separator text** to red (`Color.lerp(titleFg, errorBorder, t)` / `Color.lerp(separatorFg, errorBorder, t)`) because it assumed the field is borderless — so the error feedback appears on the digits rather than on the (missing) underline — `choose_datetime_box.dart:1800-1804` ← `lib_ui/ui/widgets/time_input.cpp:247-249`

- [ ] [MAJOR] MonthYearPicker drum (`_DrumColumn`) is rendered flat — missing the cylinder scale + opacity effect. AyuGram's `VerticalDrumPicker::DefaultPaintCallback` scales each row vertically (`yScale = 0.2 + 0.8 * easeOutCubic(1 - |distanceFromCenter|)`) and fades it (`p.setOpacity(1 - |distanceFromCenter|)`) so the drum reads as a rotating cylinder. The Dart positions every item at full size/opacity and only dims non-selected rows by colour, so the picker looks like a flat scrolling list — `choose_datetime_box.dart:1128` ← `ui/widgets/vertical_drum_picker.cpp:40-44`

- [ ] [MAJOR] TimePickerBox drum (`_TimePickerBoxWidget`) is rendered flat — same missing cylinder scale/opacity effect as the MonthYearPicker. Items are drawn at constant size with colour-only dimming instead of AyuGram's per-row `yScale` (min 0.2) and `opacity = 1 - |distanceFromCenter|`, so the auto-delete-timer wheel does not curve/fade toward its edges — `choose_datetime_box.dart:2158` ← `ui/widgets/vertical_drum_picker.cpp:40-44`

# clipboard_image — System clipboard → PNG bytes for "Photo from clipboard" avatar feature

Utility `getClipboardImage()` backing the "From Clipboard" photo-menu action
(callers: `my_profile_page.dart:1431`, `contacts_screen.dart:1662`). It is a real,
fully-wired implementation — no stubs, placeholders, TODOs, mock data, or empty
callbacks. Mirrors AyuGram's `addFromClipboard` path in
`ui/controls/userpic_button.cpp:382-399`. Findings below are behavioral deviations
from that Qt path, both Linux-specific.

- [ ] [MAJOR] Linux retrieval is hardcoded to `image/png` only — `wl-paste --type image/png` and `xclip -t image/png` return nothing when the source app offers the image only as `image/jpeg`/`image/bmp`/`image/tiff` (common from browsers, screenshot tools, GIMP), so the avatar-from-clipboard feature silently fails for valid clipboard images. AyuGram tests `data->hasImage()` and reads `qvariant_cast<QImage>(data->imageData())`, which Qt converts to QImage from ANY clipboard image format. (Note: the Windows `Clipboard.GetImage()` and macOS `«class PNGf»` paths DO coerce any format, so this gap is Linux-only.) — `clipboard_image.dart:12,19-20` ← `AyuGram/SourceFiles/ui/controls/userpic_button.cpp:384,391`

- [ ] [MAJOR] Empty `catch (_) {}` on the Linux branches conflates "clipboard tool missing" with "no image present" — if neither `wl-paste` (wl-clipboard) nor `xclip` is installed/on PATH, both `Process.run` calls throw, the errors are swallowed, and the function returns `null`, indistinguishable from an empty clipboard; the caller then shows "No image in clipboard" even when an image IS present, leaving the feature dead with no diagnostic. AyuGram reads the clipboard natively via `QGuiApplication::clipboard()->mimeData()` with no external-binary dependency, so this failure mode cannot occur. — `clipboard_image.dart:17,25` ← `AyuGram/SourceFiles/ui/controls/userpic_button.cpp:383-384`

# color_picker_box — AyuGram ColorEditor (ui/widgets/color_editor.cpp) port

Scope: `color_picker_box.dart` mirrors AyuGram's `ColorEditor` (RGBA + HSL modes).
The core widget is a faithful, fully-wired port — picker square (RGBA sat×bri /
HSL hue×sat palettes), vertical hue slider, horizontal opacity & lightness
sliders, H/S/B(L)/R/G/B numeric fields, hex result field, new/current swatches
with click-to-revert, crosshair + cursor ring, keyboard nav (arrows/enter/wheel),
lightness limits, and `setInnerFocus`→hex-field-select-all all match AyuGram's
math and behavior. All color math is local (same as AyuGram — no engine/bridge
wiring is required for this widget). No stubs, no mock data, no dead callbacks.
Dimensional constants match `boxes.style:509-526` (256 picker, 19 slider,
8 slider-skip, 10 edit-skip, 6 mark-radius, 60×34 sample, 13 field-skip). The
only deviations are user-visible text that bypasses the project's `TrStrings`
lang pack and disagrees with AyuGram's per-context labels.

- [ ] [MAJOR] Action buttons use hardcoded English literals `'Cancel'` / `'Apply'` instead of the project's localized `TrStrings` (sibling boxes use `TrStrings.lngCancel()` etc.), and the positive label `'Apply'` matches none of AyuGram's per-context labels: AyuGram uses `tr::lng_settings_save()` ("Save") for the theme-editor (RGBA) and chat-accent (HSL) boxes and `tr::lng_box_done()` ("Done") for the photo-editor brush box, always paired with `tr::lng_cancel()`. Should be `TrStrings.lngCancel()` + `TrStrings.lngSettingsSave()` (and ideally a caller-supplied positive label so the photo editor can say "Done"). — `color_picker_box.dart:853,858` ← `AyuGram/window/themes/window_theme_editor_block.cpp:347-348` (+ `editor/color_picker.cpp:759,769`, `settings/sections/settings_chat.cpp:393-394`)

- [ ] [MAJOR] Box title defaults to the hardcoded English literal `'Choose Color'` rather than a localized `TrStrings` key, so it bypasses the lang pack and produces the wrong title for the chat-accent picker. AyuGram never uses a generic "Choose Color" title: the theme editor titles the box with the palette token name (`box->setTitle(name)`) and the chat-accent picker uses `tr::lng_settings_theme_accent_title()`; the chat-settings Dart caller passes no title and therefore falls back to this hardcoded default instead of the accent title. — `color_picker_box.dart:34` ← `AyuGram/settings/sections/settings_chat.cpp:395` (+ `window/themes/window_theme_editor_block.cpp:349`)

# compose_entities — rich-text compose controller (markdown parsing, entity tracking, in-field formatting render)

Scope: `RichTextEditingController` mirrors AyuGram's `Ui::InputField` markdown/entity engine. Wiring is solid end-to-end — `toJson`/`entitiesJson`/`getTextWithAppliedMarkdown` feed `req.entitiesJson` → Go `dispatch_engine.go:766` → `telegram.go:1810-1837` builds real `tg.MessageEntity*` (bold/italic/spoiler/text_url/custom_emoji/blockquote/pre + `MessageEntityFormattedDate` with all date flags). No stubs, no placeholders, no dead callbacks. The findings below are behavioral parser/editor deviations from AyuGram's `check()` rules.

- [ ] [MAJOR] Markdown parser omits AyuGram's separator guards (good-before / bad-after / good-after): the delimiter scan finds `**`/`__`/`~~`/`||`/`` ` `` purely by `indexOf` with no test that the **opening** delimiter is preceded by a separator nor that the **closing** delimiter is followed by one. AyuGram requires `isGoodBefore(before)` at the open edge and `isGoodAfter(after)` at the close edge (separators = whitespace/punctuation only, never alphanumerics), plus `badAfter`/`badBefore` rejections. Result: ordinary text gets mangled into formatting AyuGram leaves verbatim — `config__settings__backup` → italic "settings" with the underscores stripped, `a**b**` → bold "b", `x~y~z` → strike "y". snake_case identifiers, filenames, and emphasis-less prose are silently corrupted on send. (URLs are protected via `urlRanges`, but plain text is not.) — `compose_entities.dart:474-499` ← `AyuGram/lib_ui/ui/widgets/fields/input_field.cpp:508-527` (and `TagStartExpressions` 567-618, separators `lib_ui/ui/text/text_entity.cpp:48-76`)

- [ ] [MAJOR] Fenced `` ``` `` (Pre) is not anchored to line start: the block-delimiter branch matches an opening `` ``` `` anywhere via `src.indexOf(d, contentStart)` with no preceding-newline check, so inline `foo```bar```` ` mid-line is turned into a Pre/code block. AyuGram explicitly rejects a `kTagPre` open whose preceding char is not `\n`/`\r` (`if (tag == kTagPre && before != '\n' && before != '\r') return false;`). — `compose_entities.dart:485-486` ← `AyuGram/lib_ui/ui/widgets/fields/input_field.cpp:511`

- [ ] [MAJOR] `clearFormatting` over-removes — it nukes every entity that *overlaps* the selection wholesale (`entities.removeWhere((e) => e.offset < end && e.offset + e.length > start)`), so clearing a sub-range of a longer bold/italic span also strips the formatting *outside* the selection. AyuGram's `clearSelectionMarkdown` → `RemoveDocumentTags(_st, document(), from, till)` clears the char format only within `[from, till]` via `cursor.mergeCharFormat`, leaving the surrounding formatting intact (tags are split at the boundary). Note the file's own `toggleFormat` already splits boundary-crossing entities (lines 200-210), so `clearFormatting` is inconsistent with both AyuGram and its sibling method. This button is wired across all compose surfaces (`send_files_box.dart:4935`, `contacts_screen.dart:2319`, `chat_view.dart:566`). — `compose_entities.dart:223-224` ← `AyuGram/lib_ui/ui/widgets/fields/input_field.cpp:5014-5015` (`RemoveDocumentTags` body 978-1004; `clearSelectionMarkdown` 5062-5064)

# create_channel_screen — Orphaned wrapper screen; delegated channel flow itself is real

`create_channel_screen.dart` is a 35-line `StatefulWidget` that, on first frame, pops
itself and calls `showCreateChannelWizard(context)` (implemented in
`create_group_wizard.dart`). The delegated wizard flow (InfoBox → `createChannel` →
SetupChannelBox → member picker) faithfully mirrors AyuGram's
`GroupInfoBox::createChannel` → `channelReady()` → `Box<SetupChannelBox>` chain
(`add_contact_box.cpp:825`, `:931`, `:939`) and is wired to real engine calls
(`createChannel`, `checkChannelUsername`, `updateChannelUsername`, `getInviteLink`,
`addMembers`, `editChannelPhoto`). So the channel-creation **feature** is genuinely
implemented — but it lives entirely in `create_group_wizard.dart` (separate chunk),
not in this file. This file's own problems:

- [ ] [MAJOR] `CreateChannelScreen` is dead/orphaned code — never imported, instantiated, or registered in any route table (verified: zero references outside its own definition). The real "New Channel" entry point already calls `showCreateChannelWizard(context)` directly from the hamburger drawer (`dart/lib/ui/hamburger_drawer.dart:308`), exactly mirroring AyuGram, which shows its box directly via `_window->show(Box<GroupInfoBox>(this, GroupInfoBox::Type::Channel))` with no intermediate screen. This whole widget is leftover scaffolding that duplicates the entry point and should be removed (or be the actual entry). — `create_channel_screen.dart:11` ← `AyuGram/Telegram/SourceFiles/window/window_session_controller.cpp:3185`

- [ ] [MAJOR] Fragile pop-then-reopen pattern in `initState`: the post-frame callback calls `Navigator.of(context).pop()` and then immediately `showCreateChannelWizard(context)` using the *same* (just-popped) `context`. AyuGram never pops-then-reopens — `GroupInfoBox` is pushed once as a layer and stays until the flow completes (`window_session_controller.cpp:3185` → `add_contact_box.cpp:931` keeps the same box stack). This redirect-via-route-pop is a Dart-specific anti-pattern with no AyuGram counterpart; it only happens not to misbehave because the widget is never reached (see above). If this screen were ever wired into navigation, popping its own route before reading providers / pushing the dialog from the defunct context is a latent crash/visual-flash risk (a full-screen `Scaffold` spinner at `create_channel_screen.dart:30` would also flash for one frame). — `create_channel_screen.dart:22` ← `AyuGram/Telegram/SourceFiles/window/window_session_controller.cpp:3185`

Note: The channel-creation logic, dimensions, public/private setup, username checking,
invite-link, and member-picker steps all reside in `create_group_wizard.dart` and are
out of scope for this file — audit them under that file's chunk. No placeholder/stub or
broken backend wiring exists in the delegated flow itself.

# create_giveaway_box — Channel giveaway creation box (Premium / Stars / Prepaid + Award)

Audited `dart/lib/ui/create_giveaway_box.dart` against AyuGram's
`info/channel_statistics/boosts/create_giveaway_box.cpp` (+ `giveaway_type_row.cpp`,
`select_countries_box.cpp`, `lang.strings`). The implementation is genuinely wired:
all nine engine calls (`getGiftCodeOptions`, `getStarsGiveawayOptions`,
`getGiveawayConfig`, `launchRandomGiveaway`, `launchCreditsGiveaway`,
`launchPrepaidGiveaway`, `awardPremiumGiveaway`, `getChatsToSend`,
`getChatMembersByRole`) are real FFI bridge calls (verified in
`engine_service.dart:7364-7504`), no empty callbacks, no mock data, no TODO/stub
markers. Findings below are correctness / missing-element deviations.

- [ ] [MAJOR] Prepaid **Stars/credits** giveaways are rendered as Premium. The prepaid section reads only `g['months']`/`g['quantity']` and hardcodes `'$qty × $months months Premium'` + `'$boosts boosts for your channel'`, never inspecting `g['credits']`. For a credits prepaid giveaway (`credits > 0`, `months == 0`) this displays the false text "N × 0 months Premium". AyuGram branches on `prepaid->credits` to show a `PrepaidCredits` row with `lng_boosts_prepaid_giveaway_credits_status` ("{amount} among {count} winners"). Note `info_panel.dart:9529-9540` already handles both variants, so the data path is real — only this box mishandles it. — `create_giveaway_box.dart:863-911` (title `:894`, subtitle `:901`) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:365-391`

- [ ] [MAJOR] Missing the Premium **terms / "review features" link**. AyuGram adds a `DividerLabel` with `lng_premium_gift_terms` ("You can review the list of features and more details about Telegram Premium {link}") under the duration gift-options (and inside the prepaid date container), whose link calls `Settings::ShowPremium`. The Dart box has no terms text or link anywhere (grep for `terms`/`ShowPremium`/`features` in the file returns nothing). — `create_giveaway_box.dart:981-1015` (duration section, no terms appended) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:1019-1035, 1074-1079`

- [ ] [MAJOR] The **"Telegram Stars" type tile is shown unconditionally**, even when the channel has zero stars-giveaway options. AyuGram's `fillCreditsTypeWrap` returns early (`if (state->apiCreditsOptions.options().empty()) return;`) so the Credits row is never created in that case; the Dart always renders the tile and tapping it dead-ends on a "No star giveaway options available." message instead of hiding the option. — `create_giveaway_box.dart:834-841` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:474-491`

# ayu_filter — AyuGram regex message filters (data layer)

Audited `dart/lib/data/ayu_filter.dart` against AyuGram's `ayu/features/filters/*`
(`filters_controller.cpp`, `filters_cache_controller.cpp`, `filters_utils.cpp`,
`entities.h`). The port is overall faithful and well-implemented — no stubs, no
placeholders, no mock data. Verified-correct: filter-id wire format
(`generateFilterId`/`_formatFilterIdForWire` ↔ `ParseFilterId`/`exportFilters`),
ICU→Dart regex translation (`compileFilterPattern`/`_translateIcuPattern`),
media/service type mapping (`_mediaTypeNames`/`_resolveFilterType`/`_serviceMessageType`
↔ `typeOfMessage`, with engine constants confirmed in `go/engine/db.go:372-384` and
`go/cores/telegram.go:12639-12664`), the match-blob builder (`extractMatchBlob` ↔
`extractAllText`/`extractSingle`), `_isEnabledForChat` ↔ `isEnabled` (channel==broadcast
confirmed `telegram.go:13222-13230`), and the `previewImport`/`exportFilters` diff logic.
The three findings below are real behavioral deviations.

- [ ] [MAJOR] Album/group filter verdict is not propagated to the other group members, so a type- or button-specific filter on a mixed-media album hides only the matching tiles instead of the whole album. AyuGram's `putFiltered` marks **every** item in the group as filtered when any one matches (`filteredMessages[...][groupItem->id.bare] = true` for all `group->items`). The Dart caches only the single message it was asked about; `isFiltered` builds `_groupIndex` for invalidation but never writes a verdict for the siblings. Because the UI filters each album member independently (`chat_view.dart:3221` calls `isFiltered(m, …, groupMessages: group)` inside a `.where()`), and each member's blob carries its own per-member `<type>`/`<button>` tag (`extractMatchBlob` appends `_resolveFilterType(msg)`/`msg.inlineKeyboard` of the specific msg), a filter like `.*<type>1</type>` matches only the photo member and leaves the video member visible — a broken partial album. (Text/keyword filters are unaffected: they match the shared concatenated text blob for every member.) — `ayu_filter.dart:977-990` (and `924-952`) ← `AyuGram/ayu/features/filters/filters_cache_controller.cpp:194-198`

- [ ] [MAJOR] `_filterBlocked` over-hides forwarded messages: a blocked direct sender does not short-circuit the forwarded-origin check the way AyuGram does. In AyuGram's `isBlocked(item)`, once the direct sender is found to be a blocked user the lambda **returns** `from()->id != peer->id` and never reaches the forwarded-origin branch. The Dart only returns early for a blocked sender when `hideFromBlocked` is on (`if (appState.hideFromBlocked && appState.isBlocked(senderId)) return true;`); with `hideFromBlocked` off it falls through and still evaluates `forwardFrom`. Consequence: a message **from a blocked user** (in a group, `hideFromBlocked` off) that is **forwarded from a shadow-banned user** is hidden by the Dart but shown by AyuGram (AyuGram's blocked-user branch already returned, so the shadow-ban-on-forward path never runs). Narrow but a genuine wrong-hide in the core block/shadow-ban logic. — `ayu_filter.dart:964-975` ← `AyuGram/ayu/features/filters/filters_controller.cpp:113-129`

- [ ] [MAJOR] `importFromLink` (lines 721-742) is dead/duplicate code — it faithfully mirrors AyuGram's `FilterUtils::importFromLink` (the live entry point there) but is never called anywhere in the Dart tree; the UI reimplements link-import inline with its own `HttpClient` + `previewImport` (`ayu_filters_page.dart:1633-1669`). The dead method also carries a latent divergence: it gates on `ImportChanges.hasChanges`, which omits `peersToBeResolved` from its OR-chain, whereas AyuGram's `HasChanges` includes `!changes.peersToBeResolved.empty()`. So a peers-only backup (resolve hints, no filter changes) that AyuGram treats as importable would be rejected as "No changes to import" by this path. The live UI compensates for the `hasChanges` gap (`ayu_filters_page.dart:1703` also checks its own `peersToResolve`), so the user-facing import works — this is dead-code/duplicate cleanup, not a functional break. — `ayu_filter.dart:721-742` (and `137-142`) ← `AyuGram/ayu/features/filters/filters_utils.cpp:292-342` (and `61-68`)

# custom_emoji_cache — singleton cache for custom-emoji thumbs / vector paths / animated files (refcount + disk cache + batched engine fetch)

Audited `custom_emoji_cache.dart` against AyuGram's `CustomEmojiManager`
(`data/stickers/data_custom_emoji.cpp`) and the size/frame math in
`ui/text/text_custom_emoji.cpp` + `ui/emoji_config.cpp`.

Overall this file is well-wired and faithful: real protobuf bridge calls
(`getCustomEmojiThumbs` / `getCustomEmojiFiles`), correct end-to-end data flow
(engine → cache → per-doc listeners → `getThumb`/`getPath`/`getFile` render),
balanced acquire/release refcounting across all 5 consumers, batching at
`kMaxPerRequest = 100` (matches `data_custom_emoji.cpp:48`), `Timer(Duration.zero)`
flush (matches `crl::on_main` request scheduling), and accurate frame sizes
20/27/43/24 (verified against `FrameSizeFromTag`/`EmojiSizeFromTag`,
`data_custom_emoji.cpp:1011-1015` + `:83-95`, `emoji_config.cpp:497-498`). No
stubs, no placeholders, no mock data, no TODO/FIXME, no fake feedback. Base64
thumb decode is correctly off-loaded to an isolate via `compute`.

One real persistence bug was found.

- [ ] [MAJOR] `usesTextColor` (monochrome / "text-color" emoji tint flag) is silently dropped on the disk-cache round-trip. `_writeToDisk` persists only `.dat` (fileData) and `.mime` (mimeType) and never serializes `data.usesTextColor`; `_loadFromDisk` then rebuilds `CustomEmojiFileData(mimeType:…, fileData:…)` with no `usesTextColor`, so it defaults to `false` (`engine_models.dart:3299`). The flag is fetched correctly live from the engine, but after any disk round-trip — cold app start (disk-cache hit via `initDiskCache` scan) OR scroll-away→evict→re-acquire→`_loadFromDisk` — a text-color emoji loses its flag and renders in its original color instead of being tinted to the row/name/text color. AyuGram persists this on the document itself (`Flag::UseTextColor`, `data_document.cpp:393` + `:803-811`) and drives tinting from it via `fillColoredFlags`→`setColored` (`data_custom_emoji.cpp:799-806`), so the tint survives across sessions. Fix: write a `.txc` (or fold a flag byte into `.mime`) in `_writeToDisk` and restore it in `_loadFromDisk`. — `custom_emoji_cache.dart:255-256` (write path) + `custom_emoji_cache.dart:292-295` (read path) ← `AyuGram/data/stickers/data_custom_emoji.cpp:799-806` + `AyuGram/data/data_document.cpp:803-811`

## Notes (below CRITICAL/MAJOR threshold — logged per project rule, not actionable as audit items)

- Dead global-listener path: `_globalListeners` / `addListener` / `removeListener` (`custom_emoji_cache.dart:104,143-144,520-522`) are unreachable in practice — every `_notifyListeners` call site passes a non-empty `changedDocIds` set, which `return`s before the global-listener loop (`:508-519`), and no consumer registers a global listener (all use `addListenerForDoc`). Harmless today (no feature depends on it) but a latent trap if anyone later calls `addListener`.
- In-flight fetch after eviction: if a doc's refcount hits 0 (→ `_evictFromMemory`) while a `_fetchThumbBatch`/`_fetchFileBatch` `await` is outstanding, the completing fetch re-populates `_thumbs`/`_files` for a now-unreferenced doc; it won't be evicted again until some later release. Minor, bounded memory edge case.

# edit_forum_topic_box — New/Edit forum topic & bot thread dialog (icon + color picker)

Overall the component is faithfully wired: create/edit paths call real engine
methods (`createForumTopic`/`editForumTopic`), the icon grid renders real
engine-backed custom emoji (`CustomEmojiTopicIcon` → Lottie/WebM/image), premium
gating + StickerToast + fly animation are all present, color IDs (0x6FB9F0…
0xFB6F5F) match `ForumTopicIcons()` exactly, and key dimensions match
(`editTopicMaxHeight 408`, title margin left=70, `searchMargin 1,10,2,6`). Two
behavioral deviations from the C++ source:

- [ ] [MAJOR] Colored-letter topic-icon preview does NOT update live while typing the title. `_onTitleChanged` only calls `setState` when *clearing* an error, so normal keystrokes never rebuild the dialog and the icon (and the grid's default reset cell) keep showing a stale first-letter until some other `setState` fires. AyuGram wires `title->changes()` → `state->defaultIcon = {title, colorId}`, which repaints the icon with the new first letter on every keystroke. — `edit_forum_topic_box.dart:176-178` (also preview `:511-515`, default cell `:1168-1172`) ← `AyuGram/boxes/peers/edit_forum_topic_box.cpp:488-494`

- [ ] [MAJOR] Wrong dialog title for the *create-a-bot-thread* case: Dart shows "New Thread" (`isBot && !isEditing`), but AyuGram always uses `tr::lng_forum_topic_new()` = "New Topic" when `creating`, regardless of `bot` — there is no `lng_bot_thread_new` string (the bot variant only exists for *edit*: `lng_bot_thread_edit` = "Edit Thread"). — `edit_forum_topic_box.dart:411-416` ← `AyuGram/boxes/peers/edit_forum_topic_box.cpp:415-419` (lang.strings:7317-7322)

# emoji_data — emoji keyword/suggestion engine (port of Telegram/AyuGram `EmojiKeywords` + `Completer`)

Audited `dart/lib/data/emoji_data.dart` against the three C++ sources it ports:
`chat_helpers/emoji_keywords.cpp`, `lib_ui/emoji_suggestions/emoji_suggestions.cpp`,
and `codegen/codegen/emoji/replaces.cpp`. The port is unusually faithful — the
following non-trivial claims in the Dart comments were independently verified
against the C++ and found **correct**, so they are NOT issues:

- `isExactMatch` (emoji_suggestions.cpp:321-393) is genuinely dead code — the
  leading `:` is stripped at `emoji_suggestions_widget.cpp:326` (`text.mid(1)`)
  before reaching `GetSuggestions`, so the 4th `stable_partition` never fires.
  The Dart correctly does NOT boost exact matches (`_legacyRankKey`, :2912).
- Same-emoji replacements are baked consecutively per emoji (replaces.cpp:369-381),
  so C++'s adjacent-only dedup in `addResult` is equivalent to the Dart's
  per-emoji `best`/`seen` grouping (:3318-3351).
- `maxQueryLength()` folding the legacy max in (:2997-3003) correctly mirrors the
  widget's combined `length-i > legacyLimit && length-i > modernLimit` early-out
  (emoji_suggestions_widget.cpp:959), since `GetSuggestionMaxLength()` and the
  pack max are both consulted there.
- Recent-emoji and skin-tone wiring is live (emoji_panel.dart:60,
  chat_view.dart:4403, message_bubble.dart:286), so `_prioritizeRecent` /
  `applyVariant` are not dead features.

## Findings

- [ ] [MAJOR] Language packs are iterated in insertion order, but C++ iterates them in **sorted language-code order**. `_langPacks` is a plain insertion-ordered `Map` (`final Map<String, _LangPack> _langPacks = {};`) and `search()` walks it as-is (`for (final pack in _langPacks.entries)`). In C++ the pack container is `base::flat_map<QString, std::unique_ptr<LangPack>> _data;` (sorted by key) and `EmojiKeywords::query` iterates it sorted (`for (const auto &[language, item] : _data)`). Because cross-pack de-duplication keeps the **first** pack's emoji and concatenates packs in iteration order, a multi-language user (the common case — `_fetchEmojiKeywordsForLangs` loads `{selectedLanguageCode, systemLocale, 'en'}` plus any server-expanded langs, inserted in server-return order) gets a different suggestion order and a different duplicate-winner than AyuGram. Fix: iterate `_langPacks` keys sorted (e.g. `for (final key in _langPacks.keys.toList()..sort())`). — `emoji_data.dart:3237` (decl `emoji_data.dart:2924`) ← `AyuGram/SourceFiles/chat_helpers/emoji_keywords.cpp:616` (decl `AyuGram/SourceFiles/chat_helpers/emoji_keywords.h:75`)
