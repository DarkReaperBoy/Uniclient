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

# chat_export — Telegram data-export panel (settings / progress / error, single-peer + full)

Engine wiring is complete and real — `startExport`, `onExportProgress/Error/Complete`,
`skipExportFile`, `cancelExport`, `save/loadExportSettings`, `SuggestStartExport`/
`ClearExportSuggestion` are all live FFI calls; no stubs, placeholders, mock data, or
dead callbacks. Default type/fullChats selections, the size-limit curve (`SizeLimitByIndex`),
`requiredRows` (2 single-peer / 3 full), the stop-confirmation copy, the suggest-box copy,
the critical-error layout (no buttons, top-pad = panelH/4), and `FormatDownloadText` all
match AyuGram. The text/behavioral fidelity gaps previously listed here were all fixed and verified 2026-06-09 — every option label & about-description, the combined format/location ("Format: {f}, Path: {p}") and date-range ("From: {x}, to: {y}") labels, the format/header strings ("Both", "Location and format", "Account information", "Videos", "Contacts list"/"Story archive"/"Music on Profiles"/"Miscellaneous data"), the calendar "Reset" / "Set Custom Time" / "Choose export format" box titles, the date null states ("the oldest message"/"present"), the per-field date offset clamp, the progress top-bar en-dash (U+2013) + "Exporting your data" title, the FinishedState title reset to "Export Your Data", and the `_formatSize` (no GB tier, truncated) / plain total-files count now mirror AyuGram 1:1 — confirmed live in desktop + mobile, full + single-peer, including a real end-to-end export reaching the finished state.

# chat_list_panel — left dialogs panel (search, folders, stories, top peers, forum/saved, reaction tags)

Audited the full 7243-line file against AyuGram dialogs sources. Implementation is
mature: no stubs/placeholders/empty callbacks/"coming soon", every menu action and
button is wired to `chatState`/`engine`, and many dimensions are exact ports
(stories small/full 35/77px, photo 21/42px, shift 16px, lineTwice 3/4px → 1.5/2.0px,
read 1.0px, readOpacity 0.6 — `dialogs.style:716-745`; topPeers item 66px / strip 77px
/ avatar 46px — `dialogs.style:746-750`; search-tabs slider 33px/barTop 30/barStroke 6/
barRadius 2/labelTop 7/strictSkip 18 — `dialogs.style:799-817`; drag thresholds
30/30/75 — `dialogs_inner_widget.cpp:106-108`; archive bar 37px = dialogsImportantBarHeight;
`_colorRemap` value 7 is valid against the 8-colour `peerUserpicBg`). The 5 deviations
previously listed here were all fixed and verified 2026-06-09 (commit cf3c070a): the unread
story ring now uses AyuGram's `UnreadStoryOutlineGradient` colours (`groupCallLive1` #0dcc39
green → `groupCallMuted1` #0992ef blue) drawn topRight→bottomLeft, matching `outline_segments.cpp:110-111`;
the search-tab order is now most-specific-first (`This Topic`→`This Peer`→`My Messages`→`Public Posts`,
matching the `_searchIn->apply` order at `dialogs_inner_widget.cpp:4632-4637`); the search-from
label reads `"From: {user}"` / `"From: "` (`lng_dlg_search_from`); the no-chats empty state shows
`"Your chats will be here"` (`lng_no_chats`) + a `"New contact"` (`lng_add_contact_button`) text
link to the add-contact form (`showAddContactBox`); and the wide-mode collapsed archive row is
plain semibold `dialogsNameFg` text at `dialogsTopBarLeftPadding` (18px) with no leading userpic
(`dialogs_layout.cpp:1356-1367`). Confirmed live in desktop + mobile — the search-tab order
(This Group < My Messages < Public Posts), the `From:` row, and the icon-less archive row were
visually verified; the story-ring gradient and empty-state copy/handler were code-verified
against exact palette/lang-pack values (their live states are unreachable on the test account:
no contact stories, 315 chats).

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

The 11 deviations previously listed here (forum rows, stories ring, send-state
icon, message preview, swipe quick actions) were all fixed and verified
2026-06-09 (commit f97bce9d):

**Forum rows** — `ForumChatListRow` now renders AyuGram's three-line layout
(name/date → topics 21px → last-message preview) via a new `_ForumPreviewRow`
(sender + 16px `dialogsMiniPreview` thumb + text) drawn below the topics in the
remaining height (`dialogs_message_view.cpp:423-522`). The topic-jump region
background is the subtle grey hover band `dialogsBgOver` (not the blue unread
pill); its area2 is the preview text with the `→` arrow appended (`width2 =
countWidth + forumDialogJumpArrowSkip`, :541,548-550); the front topic is drawn
exactly once (the duplicate `_TopicJumpBubble` is gone, dialogs_topics_view.cpp:
101-112/:221-240); and the 14px `topicsSkipBig` gap follows the front topic when
the jump region is active (`skipBig = _jumpToTopic && !active`, :210,235-239 —
`topicsSkip 8px`, `topicsSkipBig 14px`, `topicsHeight 21px` per dialogs.style).

**Stories ring** — the live-stream ring is a single round-capped
`attentionButtonFg` (#d14e4e) outline segment through the segment painter
(`PaintOutlineSegments`; `_drawSegments` count==1 → full round-capped ring) plus
a `LIVE` pill (`PaintLiveBadge`), not a hardcoded #e53935 filled circle
(dialogs_row.cpp:448-450,483-485). Read segments use the muted palette token
`dialogsUnreadBgMuted` (#bbbbbb light / #3e546a dark) — or
`dialogsUnreadBgMutedActive` when active — at full opacity; the hardcoded colour
and 0.6 dimming are gone (:460-462).

**Send-state icon** — `delivered` (and `sent`) now map to the single check
(`dialogsSentIcon`); only `read` shows the double check (`dialogsReceivedIcon`),
matching `item->unread(thread)` (dialogs_layout.cpp:782-794). The Go→Dart status
enum chain is consistent (Delivered=3, Read=4).

**Message preview** — the invented per-media-type Material glyphs and
`_stripMediaEmoji` are removed; the only graphic is the real 16px thumbnail, and
the media indicator is the emoji baked into the server text
(dialogs_message_view.cpp:473-503).

**Swipe quick actions** — a touch drag tracks the finger 1:1 (`offset -
delta.dx`; the 0.2 `kSwipeSlow` slowdown applies only to the wheel branch,
swipe_handler.cpp:361), clamped to `kMaxRatio` ≈ 75px; spring-back is
`min(1,ratio) * slideWrapDuration` (150ms) for both commit and abort (:168).

Confirmed live in desktop + mobile: the forum three-line layout (Mahsa Net —
topics → grey jump band with `vless://…` preview + `→` arrow; MasterDnsVPN —
`sender: text` preview), the single-check send state on outgoing 1:1 messages,
and media previews rendering the emoji-in-text with no Material glyph were
visually verified. The live-stream / read-story ring colours and the swipe
tracking/spring-back physics were code-verified against the exact AyuGram
constants and palette tokens (their live states are unreachable on the test
account: no stories/live-streams; swipe timing is not observable in static
screenshots). Build clean; no render exceptions in either mode.

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

The five Messages / Stickers-Emoji / Sensitive findings previously listed here
(double-click quick action, corner reply button, corner reaction button, emoji-set
picker, sensitive-content text) were all fixed and verified 2026-06-09 (commit
4b695588):

**Double-click quick action** — `message_bubble.dart` now detects a double-click with
a raw `Listener` (static cross-tap state keyed by msgId so a list rebuild between the
two clicks can't drop it) and runs `_onDoubleClickQuickAction`, which reads
`chatDoubleClickAction`: Reply mode calls `onReply` (opens a reply draft); React mode
toggles the favorite reaction `chatDoubleClickReaction` via `engine.reactToMessage`
(history_view_list_widget.cpp:2873). A `Listener` is used because a
`DoubleTapGestureRecognizer` would lose the arena to the body's SelectableText.

**Corner reply button** — new `_ReplyCornerButton` renders on hover, gated on
`chatShowReplyButton` (watch()), and starts a reply (settings_chat.cpp:1776).

**Corner reaction button** — the hover reaction strip + corner button are gated on
`chatShowReactionButton`; the corner button now shows the favorite reaction
(`chatDoubleClickReaction`) instead of a hardcoded first emoji (settings_chat.cpp:1795).

**Choose emoji set** — the button now opens a real emoji *rendering-set* picker
(`_EmojiSetPicker`: System / bundled Twemoji COLR font) applied app-wide via the theme's
`fontFamilyFallback` and a persisted `emojiSet`, matching `Ui::Emoji::ManageSetsBox`'s
intent rather than the custom-emoji sticker-pack manager (settings_chat.cpp:1570-1577).
Only bundled sets are offered (System + Twemoji); fabricating Apple/JoyPixels rows that
can't be rendered would be a placebo.

**Sensitive-content text** — now reads exactly "Do not hide media that contains content
suitable only for adults." (lng_settings_sensitive_about,
settings_privacy_security.cpp:311).

Confirmed live in desktop + mobile (commit verified 2026-06-09): double-click in Reply
mode opens a reply draft; in React mode it fires `ReactToMessage` and the ❤️ reaction
renders on the message; the corner reply/reaction buttons appear on hover only when their
checkbox is on and vanish when off (differential ON→OFF→ON verified, persisted to
`window_prefs.json`); the emoji-set picker switches rendering app-wide (reaction chips and
message reactions re-render in Twemoji) and persists; the sensitive-content string matches.
Both modes render with zero RenderFlex overflow and zero widget exceptions.

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

One real persistence bug was found and fixed (verified): `usesTextColor` is now persisted into the `.mime` sidecar (second line `0|1`) by `_writeToDisk` and restored by `_loadFromDisk`, surviving the disk-cache round-trip (cold start + evict→re-acquire); legacy single-line `.mime` files default to `false`.

## Notes (below CRITICAL/MAJOR threshold — logged per project rule, not actionable as audit items)

- Dead global-listener path: `_globalListeners` / `addListener` / `removeListener` (`custom_emoji_cache.dart:104,143-144,520-522`) are unreachable in practice — every `_notifyListeners` call site passes a non-empty `changedDocIds` set, which `return`s before the global-listener loop (`:508-519`), and no consumer registers a global listener (all use `addListenerForDoc`). Harmless today (no feature depends on it) but a latent trap if anyone later calls `addListener`.
- In-flight fetch after eviction: if a doc's refcount hits 0 (→ `_evictFromMemory`) while a `_fetchThumbBatch`/`_fetchFileBatch` `await` is outstanding, the completing fetch re-populates `_thumbs`/`_files` for a now-unreferenced doc; it won't be evicted again until some later release. Minor, bounded memory edge case.

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

## Findings — all verified FIXED & closed

The single MAJOR finding was verified FIXED & closed (Stage-2 verification — built the Flutter
debug bundle, launched with a live multi-account session (319 chats, no emoji-related crashes),
cross-checked the fix against AyuGram ground truth, and ran a deterministic test exercising the
production `search()` path the message composer calls via `searchEmoji` / `chat_view.dart:3857`):

- [MAJOR] Language packs now iterate in **sorted language-code order**, not insertion order.
  `search()` walks `for (final langCode in _langPacks.keys.toList()..sort())`
  (`emoji_data.dart:3247`), mirroring AyuGram's key-sorted `base::flat_map<QString,
  std::unique_ptr<LangPack>> _data` (`emoji_keywords.h:75`, confirmed in source) and its sorted
  `EmojiKeywords::query` loop `for (const auto &[language, item] : _data)` (`emoji_keywords.cpp:616`,
  confirmed). Verified behaviorally: injected packs in insertion order fr→en→de and confirmed
  `search()` returns them sorted de→en→fr, with the cross-pack duplicate-winner being the
  sorted-first pack (de) — a result that FAILS under the old `for (final pack in _langPacks.entries)`
  loop. Dart `String.compareTo` (code-unit order) matches `QString`'s default comparator for ASCII
  lang codes (`en` / `pt-br` / `zh-hans`). — `emoji_data.dart:3247` ✓ `emoji_keywords.cpp:616`
  (decl `emoji_keywords.h:75`).
