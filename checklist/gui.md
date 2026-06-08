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

**Finding:**

- [ ] [MAJOR] Palette entry is decompressed into memory *before* the size guard, so a zip-bomb `colors.tdesktop-theme`/`.tdesktop-palette` (tiny compressed, huge uncompressed) is fully expanded before being rejected — a DoS vector on untrusted theme archives. AyuGram's `readCurrentFileContent` reads `fileInfo.uncompressed_size` from the zip directory and bails *before* `openCurrentFile` when it exceeds the limit. The fix is trivial and already applied to the background path in the same function (`if (bgFile.size > …) return null;` at theme_file.dart:541, with an explicit zip-bomb comment): the palette path should likewise check `paletteFile.size > _maxPaletteFileSize` before reading `.content`. (`archive` 4.0.9 decompresses lazily on `.content`, confirmed archive_file.dart:174-189, so `.size` is available pre-decompression.) — `theme_file.dart:528-529` ← `AyuGram/Telegram/lib_base/base/zlib_help.h:258-263` (cf. window_theme.cpp:302-306 which reads the palette via this `kThemeSchemeSizeLimit`-bounded path)

# theme_preview — Telegram Desktop theme-preview thumbnail renderer (port of `window_theme_preview.cpp`)

Context: `theme_preview.dart` renders the 903×584 theme-preview image (dialogs panel + chat
panel with sample bubbles), a 1:1 port of AyuGram's `Generator` in
`window/themes/window_theme_preview.cpp`. The hardcoded sample chat (Eva Summer, the
wavedata array, "December 26", etc.) is NOT a placeholder — it mirrors the C++
`generateData()` exactly, which is correct for a preview thumbnail. The palette is wired
through every draw call, the `themeimage.jpg`/`background.tgv` assets exist and are
registered in `pubspec.yaml`, the `wallpaper.dart` helpers are real, and
`_computeChatBackgroundRects` faithfully reproduces `Ui::ComputeChatBackgroundRects`.
The findings below are real deviations from the C++ ground truth.

- [ ] [MAJOR] Audio bubble: the voice-message duration ("0:07") and waveform are anchored ~12–14px too low, so the duration ends up at the very bottom edge of the 60px bubble and *below* the timestamp instead of mid-bubble above it. Dart anchors the duration at `y + thumbTop + thumbSize - 4` (= y+48) and the waveform baseline at the play-button center `y + thumbTop + thumbSize/2 + maxBarHeight/2` (= y+38, bars bottom at y+40). C++ places the duration at `statusTop` (= y+34) and the waveform baseline at `padding.top + msgWaveformMax` (= y+25, bars bottom at y+28) — duration sits above the timestamp (~y+42), waveform in the upper "name" row. Result: ~23% of the bubble height of vertical misplacement and the duration text overlaps the bottom padding / sits under the timestamp. — `theme_preview.dart:732` & `theme_preview.dart:759` ← `AyuGram/window/themes/window_theme_preview.cpp:948` & `window_theme_preview.cpp:925` (`statusTop` = `chat.style:511`)

- [ ] [MAJOR] Audio bubble waveform uses `minBarHeight = 2.0` / `maxBarHeight = 16.0`, but AyuGram uses `msgWaveformMin: 3px` / `msgWaveformMax: 17px`. Wrong bar amplitude range (delta 14 in both but offset/cap differ), compounding the vertical-position drift above. — `theme_preview.dart:728-729` ← `AyuGram/ui/chat/chat.style:559-560`

- [ ] [MAJOR] Reply preview block: wrong text colors vs C++. (a) The reply *sender name* is drawn in `replyBarColor` (= `msgInReplyBarColor` → `activeLineFg` #37a1de) but C++ draws it in `msgInServiceFg` (→ `windowActiveTextFg` #168acd) — a different palette accent. (b) The reply *text* is drawn at `textFg.withValues(alpha: 0.7)` but C++ draws it in full-opacity `historyTextInFg`/`historyTextOutFg`. — `theme_preview.dart:623-626` ← `AyuGram/window/themes/window_theme_preview.cpp:907-911` (palette bindings `colors.palette:351`, `:366`, `:256`)

- [ ] [MAJOR] Tailed bubbles render no message tail. Dart draws the "tail" corner as a `Radius.circular(4)` rounded corner (text bubble bottom-left/right, audio bubble bottom-right, photo bubble bottom-left). C++ `Ui::PaintBubble` renders `Corner::Tail` as a *sharp* corner (`Corner::None`, radius 0) plus a drawn tail pointer (`paintTail`/`tailRight`/`tailLeft`). So all tailed bubbles in the preview lose the characteristic Telegram tail pointer and use a rounded corner instead of a sharp one. (Caveat: AyuGram's `removeMessageTail()` setting makes tailless valid, but it is OFF by default, so the ground-truth preview shows tails.) — `theme_preview.dart:585-590`, `theme_preview.dart:691`, `theme_preview.dart:800` ← `AyuGram/window/themes/window_theme_preview.cpp:847-857` & `ui/chat/message_bubble.cpp:59-64`

- [ ] [MAJOR] Compose-area placeholder ("Message") uses `historyComposeAreaFg.withValues(alpha: 0.5)` (= `historyTextInFg`/`windowFg` at 50%), but C++ uses `historyComposeField.placeholderFg` = `placeholderFg` = `windowSubTextFg`. These diverge (notably in dark themes, where `windowFg@50%` is a translucent light gray vs the opaque `windowSubTextFg`). Note the same file already uses the correct `windowSubTextFg` for the dialogs search placeholder (`theme_preview.dart:160`), so this is an inconsistency. — `theme_preview.dart:899` ← `AyuGram/window/themes/window_theme_preview.cpp:616` (`placeholderFg` = `colors.palette:73`)

# theme_tokens — centralized design-token table (mirror of AyuGram .style files)

`theme_tokens.dart` is a pure constants table (no widgets, callbacks, or engine
calls), so the audit reduces to: does every scalar match the AyuGram `.style`
source? I verified all ~95 tokens against the ground-truth `.style` files. The
file is remarkably accurate — every numeric value, font, duration, size, and
margin traces to a real AyuGram literal **except one**, documented below.

## Finding

- [ ] [MAJOR] `defaultRoundShadowBlur = 8` / `defaultRoundShadowOffset = Offset(0, 2)` are fabricated scalars with no AyuGram source. AyuGram's `defaultRoundShadow` is an **icon-based 9-slice `Shadow`** (8 pre-rendered `round_shadow_*` icon slices) whose only scalar is `extend: margins(3px, 2px, 3px, 4px)` — there is no `blur` or `offset` field anywhere. A blur of 8 / down-offset of 2 overshoots the actual 3/2/3/4 extend (~100% larger than the 4px bottom extend) and is unsourced. Either derive from the real `extend` margins or list it as unresolved (the file already does exactly this for the other non-scalar widget-style object, `localStorageLimitSlider`/MediaSlider, in `unresolvedTokens`). — `theme_tokens.dart:160` ← `AyuGram/Telegram/lib_ui/ui/widgets/widgets.style:911` (and `:920` `extend: margins(3px, 2px, 3px, 4px)`)

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

## Missing feature

- [ ] [CRITICAL] Dark-mode dimming of image wallpapers is entirely absent. AyuGram overlays a black rect at `255 * darkModeDimming / 100` alpha over a non-pattern image background whenever the active theme is dark — and `darkModeDimming` defaults to `clamp(patternIntensity,0,100) = 50` for image wallpapers, so a custom image background is dimmed ~50% in every dark theme. The Dart renderer has no theme/brightness awareness at all: `_buildImage` → `_ScaledWallpaperImage`/`_TiledImage` paint the raw image, and the mount point `_ChatBackground` (chat_view.dart:20856-20879) adds no overlay. Result: image wallpapers render at full brightness under dark themes (>25% luminance deviation, readability of the dark UI suffers). — `wallpaper.dart:361` (`_buildImage`, no dimming) ← `AyuGram/SourceFiles/ui/chat/chat_theme.cpp:1228` (dimming applied; default set at `AyuGram/SourceFiles/window/window_session_controller.cpp:3695` + `forDarkMode` :3710)

## Performance — heavy image work on the UI thread

- [ ] [MAJOR] `encodeWallpaperJpeg` does a full synchronous pure-Dart decode + crop + resize + JPEG-encode (`package:image`) and is invoked inline on the UI thread when applying a custom wallpaper (chat_settings_screen.dart:292, not awaited / not isolated). For a typical multi-megapixel phone photo this freezes the UI for ~1–2 s. The same file already proves the correct pattern by running the (lighter) gradient generation off-thread via `compute()` (`_generateGradientBytesAsync`, `wallpaper.dart:673`); AyuGram likewise prepares background images off the main thread. — `wallpaper.dart:1968` ← `AyuGram/SourceFiles/ui/chat/chat_theme.cpp:941` (`PreprocessBackgroundImage`; background prep dispatched via `crl::async` at :705)

- [ ] [MAJOR] `computeAverageColor` fully decodes the wallpaper image synchronously on the UI thread (`img.decodeImage`, slow pure-Dart codec) before sampling, with no `compute()`/isolate. It runs on the UI thread on every switch to an image wallpaper via `WallpaperData.averageColor` → `adjustServiceColorsForWallpaper` (telegram_palette.dart:1983 → main.dart:2467) — a ~0.5–1 s hitch (the result is cached afterward, so it is once-per-change rather than per-frame). AyuGram's `CountAverageColor` sums an already-decoded `QImage` produced off-thread, never re-decoding from bytes on the UI thread. — `wallpaper.dart:1925` ← `AyuGram/SourceFiles/ui/chat/chat_theme.cpp:880` (`CountAverageColor`)

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

Three real deviations follow. **Finding 1 is in this Dart file and hits nearly every
user; findings 2–3 are engine parity gaps that surface as wrong output on this screen.**

Not flagged (MINOR/cosmetic, consistent with this repo's audit calibration): ~22
hard-coded English UI strings (`'Active Sessions'`, `'This device'`, `'Active Devices'`,
section footers, info-box labels, etc., `:654-1188`) where AyuGram uses `tr::lng_*` — the
text is correct, just not routed through `TrStrings`; and the locale format of
`_formatActiveDate` (24h `HH:mm`, `dd.MM.yyyy`, English weekday names vs AyuGram's
`QLocale::ShortFormat`/`langDayOfWeek`).

- [ ] [MAJOR] Session active date/time is rendered in **UTC, not the user's local time** — every timestamp on this screen is shifted by the user's UTC offset. `_formatActiveDate` and `_formatFullDate` call `DateTime.parse()` on the engine's `last_active` and then read `.hour`/`.minute`/`.year`/`.month`/`.day` (and build `TimeOfDay.fromDateTime`) **without `.toLocal()`**. The engine marshals `last_active` as Go `time.Time` (`json.Marshal` of `cores.Session`, `dispatch_engine.go:5214`; value built `time.Unix(...)` → local → RFC3339 *with* offset, e.g. `…+05:30` / `…Z`). Verified empirically: Dart `DateTime.parse` returns a **UTC** `DateTime` (`isUtc=true`) for any offset/`Z` string, so `.hour` is the UTC hour. AyuGram renders **local** time via `base::unixtime::parse` (`langDateTimeFull(base::unixtime::parse(data.activeTime))` and `ActiveDateString`). Net: a session active at 20:00 local shows "14:30" for a +05:30 user, in both the row date and the info-box "active" line; the "is it today / this week" branch also mis-buckets near local midnight since it compares UTC `date` against local `DateTime.now()`. Fix: `DateTime.parse(dateStr).toLocal()` in both functions (the sort helper `_lastActive:231` correctly uses `.toUtc()` and is unaffected). — `active_sessions_screen.dart:556` (and `557-567`), `active_sessions_screen.dart:842` (and `844-848`) ← `AyuGram/Telegram/SourceFiles/api/api_authorizations.cpp:258-269` + `AyuGram/Telegram/SourceFiles/settings/sections/settings_active_sessions.cpp:443`

- [ ] [MAJOR] App version is shown **raw**, not normalized like AyuGram's `ParseEntry`. The row status line (`appName + ' ' + appVersion`) and the info-box "Application" row (`appStr = '$appName $appVersion'`) display `app_version` verbatim. AyuGram formats it before the UI ever sees it: for desktop api-ids a pure-integer version is run through `FormatVersionDisplay` (`4017004` → `4.17.4`; `changelogs.cpp:150-156`), and for non-desktop apps a parenthesized build is trimmed to just `(build)`. The uniclient engine (`telegram.go:14118-14119` `GetActiveSessions`, passed through `GetSessions:30811-30812`) copies `a.AppName`/`a.AppVersion` straight from the MTProto authorization with no normalization, so e.g. a snap/GitHub/legacy desktop session whose `app_version` is a numeric build id renders as a meaningless integer instead of a dotted version (and the desktop "Telegram Desktop"/" (GitHub)" app-name override is absent). Fix belongs in `telegram.go` to mirror `ParseEntry`. — `active_sessions_screen.dart:1235` (and `:592`) ← `AyuGram/Telegram/SourceFiles/api/api_authorizations.cpp:44-57` (and `:75-77`)

- [ ] [MAJOR] `last_active` has no `date_created` fallback, so a session with `date_active == 0` renders as the Unix epoch (`01.01.1970` in the row, "January 1, 1970" in the info box). AyuGram sets `activeTime = date_active ? date_active : date_created` (defensively guarding the zero case, which occurs for some authorizations e.g. incomplete login attempts). The engine builds `LastActive: time.Unix(int64(s.DateActive), 0)` using `DateActive` only — no fallback (`telegram.go:30815`; `DateCreated` is parsed into `ActiveSession` at `:14122` but dropped on the way to `cores.Session`). When `DateActive` is 0 the Dart faithfully displays epoch instead of the creation date AyuGram would show. Fix belongs in `telegram.go GetSessions`. — `active_sessions_screen.dart:586` (and `:596`, `:1230`) ← `AyuGram/Telegram/SourceFiles/api/api_authorizations.cpp:72-74`

# admin_tools — Channel/group admin management (Edit Peer Info, Permissions, Admin/Restricted editors, Recent Actions log, Invite Links, Member list, Statistics, Boosts, Monetization, Star-ref)

Scope: `dart/lib/ui/admin_tools.dart` (14,893 lines) vs AyuGram `boxes/peers/*`, `history/admin_log/*`,
`info/statistics/*`, `info/channel_statistics/*`, `info/bot/starref/*`.

**Overall:** This is a faithful, fully-wired reimplementation. Every screen calls real engine methods
(no `onTap: () {}`, no TODO/FIXME/HACK, no "coming soon", no mock/hardcoded data) — confirmed by grep.
Charts parse real `StatsGraph` JSON and load async graphs via `loadStatsGraph`; withdraw flows do the
2FA password round-trip; member/invite/boost/tx lists paginate against real APIs. The findings below are
behavioural/structural deviations, not stubs.

## Findings

- [ ] [MAJOR] EditAdminBox renders the channel "Manage Messages" (Post/Edit/Delete Messages) and "Manage Stories" (Post/Edit/Delete Stories) admin rights as FLAT toggle rows; AyuGram nests each set inside an expandable `SlideWrap` group with a parent "Manage Messages"/"Manage Stories" checkbox that toggles all children at once. The Dart `_buildRightsSection` even takes a `sectionLabel` arg but ignores it (renders only the toggles). — `admin_tools.dart:5553-5576` & `admin_tools.dart:5743-5755` ← `Telegram/SourceFiles/boxes/peers/edit_peer_permissions_box.cpp:119-186` (`NestedAdminRightLabels` → `lng_rights_channel_manage` / `lng_rights_channel_manage_stories`) & `:724-753` (nested `SlideWrap` + outer toggle render)

- [ ] [MAJOR] The Edit-Peer manage-section rows for **Reactions**, **Permissions** and **Invite Links** pass `value: ''`, so they never display the current-state count AyuGram shows on the right of each `CreateButton` (Reactions → allowed-count / "All" / "Off"; Permissions → "X/Total" restrictions; Invite Links → link count). Administrators/Members rows DO show counts, so the omission is inconsistent and hides live state. — `admin_tools.dart:2402-2438` ← `Telegram/SourceFiles/boxes/peers/edit_peer_info_box.cpp:1523-1534` (reactions count), `:1549-1556` (permissions `X/Total`), `:1581-1593` (invite-links count)

- [ ] [MAJOR] The "Aggressive Anti-Spam" toggle shown above the member-list **Admins** tab is never gated by member count — `_antiSpamHeader` hardcodes `belowThreshold = false` with the comment "membership count not tracked here; show toggle", and `_antispamMin` is loaded but never compared. AyuGram disables the toggle below `appConfig telegram_antispam_group_size_min`, so here a small megagroup shows it enabled and `toggleAntiSpam` fails server-side. (The correct gating exists only in `_buildAntiSpamSection`, which is dead code — never called.) — `admin_tools.dart:9379-9415` (live header) & `admin_tools.dart:2545-2585` (unused correct version) ← `Telegram/SourceFiles/boxes/peers/edit_participants_box.cpp:1350-1356` (AntiSpam validator as the Admins list "above" widget, gated on the group-size-min app config)

- [ ] [MAJOR] Color & Emoji changes are saved only when `colorId >= 0`: `if (colorId >= 0) { await engine.updateChannelColor(... backgroundEmojiId: bgEmojiId, statusEmojiId: statusId); }`. When the channel has no name color set (`peer_color_id` resolves to `-1`) and the admin changes ONLY the background emoji or emoji status, the "changed" guard passes but no RPC fires and no error is shown — the change is silently dropped. AyuGram's color box persists color, background-emoji and emoji-status independently. — `admin_tools.dart:1698-1745` (esp. `:1738`) ← `Telegram/SourceFiles/boxes/peers/edit_peer_color_box.cpp` (`EditPeerColorBox` saves colorIndex, backgroundEmojiId and emojiStatus as separate, independently-applied fields)

- [ ] [MAJOR] The Recent-Actions rights-diff label maps are incomplete, so genuinely-changed rights render no `+`/`−` line in the log. `_adminLabels` omits `manage_direct` ("Manage direct messages") and `manage_ranks` ("Edit member tags"); `_bannedLabels` omits `edit_rank`. A `participant_admin`/`change_default_rights` event that flips one of these shows the headline ("promoted X") but the affected right is invisible in the diff. — `admin_tools.dart:6838-6858` ← `Telegram/SourceFiles/history/admin_log/history_admin_log_item.cpp` (`GenerateParticipantChangeText` / `GenerateAdminChangeText` enumerate every `ChatAdminRight` incl. `ManageDirect`, `ManageRanks`, and every `ChatRestriction` incl. `EditRank`)

# advanced_settings_screen — Advanced settings page (§14.7) + sub-dialogs (proxy, local storage, auto-download, power saving, dictionaries, recent downloads, experimental)

Overall the file is a faithful, fully-wired port: every toggle/slider forwards to the
engine or persists via AppState (`SetProxy`, `SetAutoDownload`, `SetLocalStorageLimits`,
`ClearCacheByTag`, `SetPowerSaving`, `SetExperimentalFlag`, autostart file writes, real
GitHub update download). The auto-download `SizeLimitByIndex` curve, local-storage
ladders, cache-tag order, power-saving bit flags, CloseBehavior enum values, and
MTPROTO secret/proxy-link parsing all match AyuGram exactly. No stubs, empty callbacks,
mock data, or "coming soon" placeholders found. The deviations below are all in the
PowerSavingBox structure/labels.

- [ ] [MAJOR] PowerSavingBox renders the "Automatic" toggle ABOVE the feature checkboxes; AyuGram places it BELOW them after a `AddSkip`+`AddDivider`+`AddSkip`, and follows it with the explanatory `lng_settings_power_auto_about` divider-text ("Automatically disable all animations when your laptop is in a battery saving mode.") — that trailing text is entirely omitted. — `dart/lib/ui/advanced_settings_screen.dart:2744` ← `AyuGram/Telegram/SourceFiles/settings/settings_power_saving.cpp:71`

- [ ] [MAJOR] PowerSavingBox is missing the subtitle shown under the title. AyuGram adds `AddSubsectionTitle(container, tr::lng_settings_power_subtitle())` = "Power saving options" right below the title; the Dart jumps straight from the title to the (mis-placed) auto-toggle / "Stickers" header with no subtitle. — `dart/lib/ui/advanced_settings_screen.dart:2727` ← `AyuGram/Telegram/SourceFiles/settings/settings_power_saving.cpp:46`

- [ ] [MAJOR] PowerSavingBox title text is wrong: Dart shows "Power Saving"; AyuGram `setTitle(tr::lng_settings_power_title())` = "Power Usage". The auto-toggle label is also wrong: Dart "Automatic Power Saving" vs AyuGram `lng_settings_power_auto` = "Save Power on Low Battery". — `dart/lib/ui/advanced_settings_screen.dart:2730` ← `AyuGram/Telegram/Resources/langs/lang.strings:928`

- [ ] [MAJOR] Performance-section button that opens the box is mislabeled "Power Saving"; AyuGram's row uses `tr::lng_settings_power_menu()` = "Battery and Animations" (the icon also differs, but the label is the user-facing key). — `dart/lib/ui/advanced_settings_screen.dart:970` ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_advanced.cpp:838`

# auth_screen — Telegram intro/login flow (phone, code, 2FA, signup, email, QR)

Audited `dart/lib/ui/auth_screen.dart` against AyuGram `intro/*` (phone, code,
code_input, password_check, signup, email, qr, step, widget, intro.style). The
screen is genuinely wired end-to-end: every button calls `authState.submitInput`
/ `switchToMethod` / `cancelAuth`, the engine populates all `AuthStateData`
fields (`go/engine/auth.go`), the special commands (`__no_telegram_code`,
`__resend_code`, `__request_recovery`, `__reset_account`, `qr_code`) are handled,
the QR payload + auto-call countdown + Fragment delivery are real, and the
passkey link is correctly gated out (no fake button under the no-CGo
constraint). The issues below are feature-parity / data-flow gaps, not cosmetics.

- [ ] [CRITICAL] Password-recovery-by-email flow is unreachable. "Forgot password?" calls `_handleForgotPassword`, which only requests recovery when `data.hasRecovery` is true — but the engine hardcodes `HasRecovery = false` on every 2FA entry (`go/engine/auth.go:547,567`) and only flips it true *after* `__request_recovery` succeeds (`auth.go:590`), which the gate prevents from ever being sent. So an account that DOES have a recovery email is wrongly shown the "no recovery email — reset your account" dialog and pushed toward account deletion. AyuGram instead checks the real upfront `_passwordState.hasRecovery` flag (available in the core as `pw.HasRecovery`, `go/cores/telegram.go:21335`) and then issues `MTPauth_RequestPasswordRecovery`. The UI's own `PASSWORD_RECOVERY_NA` handler (`auth_screen.dart:832-837`) is consequently dead code. — `auth_screen.dart:1062-1075` ← `AyuGram/intro/intro_password_check.cpp:292-323`

- [ ] [MAJOR] Code/OTP step omits the persistent "Next" submit button. `_showNext` returns false for `otp` unless Fragment delivery, so the only way to submit a typed code is the implicit auto-submit-on-fill. AyuGram's `CodeWidget::nextButtonText()` returns a non-empty string ("Next") for non-Fragment codes, so the intro keeps the primary RoundButton visible and `submit()` → `_code->requestCode()` always offers a manual submit. — `auth_screen.dart:284-307` ← `AyuGram/intro/intro_code.cpp:424-431` (+ `intro_widget.cpp:729-740`)

- [ ] [MAJOR] Code-step subtitle is hardcoded English "Code sent to {sentTo}" instead of AyuGram's localized, delivery-specific descriptions. AyuGram `updateDescText` picks `lng_intro_email_confirm_subtitle` (email-login, with masked email + "don't forget the spam folder"), `lng_code_from_telegram` ("A code was sent **via Telegram** to your other devices…"), or `lng_code_desc` ("We've sent an activation code to your phone…"). The Dart collapses all three into one un-localized string and drops the "check your other devices" guidance. — `auth_screen.dart:1304-1307` ← `AyuGram/intro/intro_code.cpp:83-115` (esp. 90-102)

- [ ] [MAJOR] Auto-fill of a login code received on another device is not implemented. AyuGram registers `account->setHandleLoginCode([=](const QString &code){ _code->setCode(code); _code->requestCode(); })` so that when Telegram pushes the code as a service message to an already-connected device, the code step fills and submits it automatically. `_OtpCodeInput` only has `onComplete`/`onResendCode` hooks and there is no engine→UI event delivering a received code, so this convenience path is absent end-to-end. — `auth_screen.dart:1309-1323` ← `AyuGram/intro/intro_code.cpp:59-62`

- [ ] [MAJOR] Sensitive 2FA/reset texts are hardcoded English instead of pulled from the lang pack, unlike the rest of the file (which uses `lang.tr`). The recovery-mode description hardcodes "Recovery code sent to …" rather than `lng_signin_recover_desc` (which weaves the masked email via the pack); the no-recovery dialog hardcodes its body instead of `lng_signin_no_email_forgot`; and the reset-account confirmation hardcodes its text plus manual "day/days/hour/hours" pluralization instead of `lng_signin_sure_reset` + `lng_signin_reset_in_days`/`lng_signin_reset_in_hours` (localized plurals). — `auth_screen.dart:733-737, 1083-1086, 459-500` ← `AyuGram/intro/intro_password_check.cpp:350-358, 316-317` (+ `intro_widget.cpp:570-628`)

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

One genuine backend-wiring gap:

- [ ] [CRITICAL] "Bots" drawer-element toggle is dead — it only renders when `appState.menuBots.isNotEmpty`, but `menuBots` is never populated: `AppState.setMenuBots` has ZERO callers anywhere in the Dart tree (its own doc-comment claims it's "called by engine event handler", but no such handler exists, and `EngineService.getAttachMenuBots` returns a different `AttachMenuBotInfo` type that is never converted/forwarded into `setMenuBots`). So `menuBots` is permanently empty and the Bots toggle can never appear. In AyuGram the equivalent gate queries live data — `HasDrawerBots(controller)` iterates `controller->session().attachWebView()->attachBots()` checking `bot.inMainMenu && bot.media` — so the toggle shows for accounts that have main-menu bots. Feature is not wired to the backend. — `ayu_appearance_page.dart:138` (root cause `dart/lib/state/app_state.dart:3023` — never-called `setMenuBots`) ← `AyuGram/ayu/ui/settings/settings_appearance.cpp:291` (gate) + `settings_appearance.cpp:41-51` (`HasDrawerBots`)

# ayu_filters_page — Regex Filters settings (main page, shared/shadow-ban/per-dialog lists, edit box, import/export)

Overall this file is a faithful, fully-wired port of AyuGram's filter UI. All toggles
call `filterEngine.rebuildCache()` (mirroring `FiltersCacheController::rebuildCache`),
the top-bar `+`/exclude icons match `info_wrap_widget.cpp:467-513`, the shadow-ban
picker restricts to Bot|User, the edit box / import / export / clear-all flows match
their C++ counterparts, and the engine import/export logic in `ayu_filter.dart` is a
genuine port (version check, override-only-if-different, cascade deletes, dpaste publish).
No placeholders, stubs, fake data, or dead callbacks were found. Two real deviations
remain, both in the per-dialog row's handling of peers not present in the local chat list.

- [ ] [MAJOR] Per-dialog filter row shows the wrong unknown-peer name. AyuGram's `PerDialogFiltersListRow::generateName()` returns `"UNKNOWN (ID: <id>)"` for an unresolved peer; the Dart instead reuses the screen-title fallback `"Filters (<dialogId>)"` for the row label. (AyuGram only uses `"Filters (<id>)"` as the *screen title* fallback — `ayu_RegexFiltersHeader`="Filters" — never as the row name.) Reachable right after an import, when per-dialog filters reference dialogs still being resolved and not yet in `chatState.chats`. — `ayu_filters_page.dart:145` (used as the row name via `:91`/`:94`) ← `ayu/ui/settings/filters/per_dialog_filter.cpp:40`

- [ ] [MAJOR] Per-dialog filter row never asks the engine to resolve a peer that isn't already in `chatState.chats`. `_PerDialogFilterRow._resolveAvatar()` (and the parent's `_resolveDialogName`) only scan the loaded dialog list, so a per-dialog filter on a peer not in that list renders with no real name and a generic colored letter. AyuGram resolves via `getPeerFromDialogId` (any loaded `userLoaded`/`channelLoaded`/`chatLoaded` peer, broader than the dialog list), and the sibling `_ShadowBanRow` in this very file demonstrates the available fallback (`engine.getUserProfile` + `engine.downloadSingleAvatar`) — the per-dialog row should use the same pattern. — `ayu_filters_page.dart:569-577` (cf. richer resolution at `:1188-1206`) ← `ayu/ui/settings/filters/per_dialog_filter.cpp:35-58`

# ayu_general_page — AyuGram "General" settings page (translation provider, QoL toggles, webview, confirmations)

Compared against `ayu/ui/settings/settings_general.cpp` (`BuildQoLToggles`/`BuildTranslator`/`BuildShowPeerId`) and `ayu/ui/settings/settings_ayu_utils.cpp` (`ShowRestartPrompt`/`AddBetaBadge`).

Overall this file is faithfully wired: section order, dividers, subsection titles, all 15 toggles/choosers match the C++ 1:1; every `appState.setX` setter is real and persists via `_saveWindowPrefs()`; every setting is genuinely consumed by a real feature (verified consumers in chat_list_panel, info_panel, web_app_panel, chat_view, main.dart); `_showRestartPrompt`/`flushSettingsSync` are real (no stubs, no empty callbacks, no mock data). Two behavioral/label deviations found.

- [ ] [MAJOR] "Spoof Webview as Android" label is wrong — AyuGram's `ayu_SettingsSpoofWebviewAsAndroid` string is **"Spoof Client as Android"** (the toggle spoofs the whole client UA, not just the webview). The displayed word "Webview" should be "Client" — `ayu_general_page.dart:153` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_general.cpp:254` (`tr::ayu_SettingsSpoofWebviewAsAndroid()`) / `AyuGram/Telegram/Resources/langs/lang.strings:8129`

- [ ] [MAJOR] Missing macOS native-translation guidance toast — when the user selects the Native (macOS) translation provider, AyuGram shows a 6s toast `lng_translate_settings_use_platform_mac_about` ("Translation on macOS won't work until you download local language packs in System Settings."). The Dart `onChanged` just calls the setter with no toast, so a macOS user picking "macOS" gets no hint that translation will silently fail without OS language packs — `ayu_general_page.dart:51` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_general.cpp:94-101` / `AyuGram/Telegram/Resources/langs/lang.strings:6914`

# ayu_other_page — AyuGram "Other" settings page (donations, crash reporting, URL scheme, reset)

Overall this is a faithful, fully-wired port. Donate addresses/colors/order match `settings_other.cpp:154-158` exactly; all lang strings match `lang.strings:8060-8074`; crash-reporting toggle is wired to `AppState.setCrashReporting` (real), reset → `resetAyuSettings` (comprehensive, not a stub), the support-description link opens the donate info box (matches `tg://support` → `HandleSupport` → `FillDonateInfoBox`, `ayu_url_handlers.cpp:134-145`), the username link calls `engine.resolveUsername` (real bridge `ResolveUsername`), QR copy hits the clipboard + toast, and RC config URLs/defaults/hourly-timer mirror `rc_manager.cpp`. No placeholders, stubs, empty callbacks, or mock data. Two deviations from the C++ authority remain:

- [ ] [MAJOR] DonateInfoBox has no width constraint — C++ pins the box to `int(st::aboutWidth * 1.1)` = 429px, but the Dart returns a bare `Dialog` with no `width`/`ConstrainedBox`, so on a desktop settings window it expands to nearly the full window width (Material `Dialog` only reserves the default 40px inset). The deviation exceeds 25% at desktop sizes. Notably the sibling QR box DOES cap its width (`ayu_other_page.dart:851-852`, `math.min(487, maxWidth)`), making this an inconsistent omission. — `ayu_other_page.dart:640` ← `AyuGram/ayu/ui/boxes/donate_info_box.cpp:134` (with `aboutWidth: 390px` at `AyuGram/boxes/boxes.style:351`)

- [ ] [MAJOR] `_applyRcData` drops the type/empty guards the C++ enforces — C++ `applyResponse` only overwrites a donate field when the JSON value `isString()` AND `!value.isEmpty()`, otherwise it keeps the default. The Dart applies `data['donateAmountUsd'].toString()` whenever the key merely exists, so a JSON number (e.g. `5.0`) renders as `"5.0"`, an empty string blanks the amount (`"Transfer an amount of $ ("`), and a JSON `null` renders the literal `"null"` ("$null") — none of which the C++ would show. — `ayu_other_page.dart:558-573` ← `AyuGram/ayu/utils/rc_manager.cpp:187-206`

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

- [ ] [CRITICAL] Web bridge init races the async WASM load — `window.bridgeReady` is created and
  resolved in the host page but **never awaited anywhere in Dart**, so `init()` can call
  `bridgeSetEventCallback`/`bridgeCall` before the Go WASM module has registered them on
  `globalThis`, throwing `TypeError: bridgeSetEventCallback is not a function`. In `index.html` the
  WASM module is instantiated asynchronously (`WebAssembly.instantiateStreaming(fetch("cores.wasm"))
  .then(... go.run(...); bridgeReadyResolve())`), and Flutter is bootstrapped independently via
  `<script src="flutter_bootstrap.js" async>` — there is **no ordering guarantee** that Go `main()`
  has run before Flutter's Dart `_initEngine` reaches the bridge. The whole chain
  `main.dart _initEngine() → AppState.initialize() (app_state.dart:3542) → EngineService.init()
  (engine_service.dart:102) → BridgeImpl.init()` runs synchronously with no readiness gate, and
  `engine_service.dart:111` then immediately fires a `bridgeCall` for `Init`. A multi-MB
  `cores.wasm` will commonly finish loading *after* Flutter starts, making this a live race, not a
  theoretical one. `grep -rn bridgeReady` over `dart/` returns only the comment on
  `bridge_web.dart:3` and the three lines in `index.html` — nothing reads/awaits the promise. The
  native sibling has no such gap: `bridge_ffi.dart:59` opens the shared library synchronously inside
  `init()`, so the exports are guaranteed present before the first `call()`. Fix belongs here: gate
  on `window.bridgeReady` before touching the JS functions (this also requires the `init()` contract
  to expose async readiness on web — see `bridge.dart:23`, currently `void init`). —
  `bridge_web.dart:33-39` (`init` → `_jsBridgeSetEventCallback` at :37) & `bridge_web.dart:47`
  (`_jsBridgeCall`) ← `dart/web/index.html:21-27` (async load + `bridgeReadyResolve()` never
  awaited) / `go/cmd/bridge/main_js.go:38-39` (functions only registered after `go.run`) /
  `bridge_ffi.dart:59` (native guarantees readiness synchronously)

- [ ] [MAJOR] `callAsync` does not honor the `Bridge.callAsync` contract on web — it runs the Go
  call on the **main UI thread**, blocking it for the full duration of any network/auth operation.
  The public contract at `bridge.dart:28-30` states: *"Async call — runs the FFI call on a
  background isolate. Use for any operation that might block (network calls, auth, etc)."* The
  native impl honors this via `Isolate.run` (`bridge_ffi.dart:103-109`). The web impl instead does
  `Future.microtask(() => call(requestBytes))` (`bridge_web.dart:54-55`), which executes the
  blocking `call()` on the single JS thread — so any UI animation/frame is frozen while the engine
  does network I/O. `EngineService` routes blocking ops (auth, sends, history fetches) through
  `callAsync`, so on web those will jank/freeze the UI. Additionally, the doc-comment on
  `bridge_web.dart:51-53` is technically wrong about Dart scheduling: it claims wrapping in
  `Future.microtask` "ensures pending microtasks **and I/O callbacks** are processed before the
  blocking call starts," but microtasks have strictly higher priority than the event queue in Dart —
  queued I/O/timer callbacks run *after* the microtask, not before. To actually yield to pending I/O
  it would need `Future(() => call(...))` / `Future.delayed(Duration.zero, ...)` (event-queue task),
  and to be genuinely non-blocking it would need a Web Worker (true off-main-thread execution, which
  WASM-on-main-thread cannot provide here). At minimum the misleading comment and the false
  "background isolate" promise for the web path should be corrected. —
  `bridge_web.dart:51-55` (`callAsync` via `Future.microtask`) ← `bridge.dart:28-30` (contract:
  "background isolate", "operation that might block") / `bridge_ffi.dart:103-109` (native honors it
  with `Isolate.run`)

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

- [ ] [MAJOR] No RTL mirroring — the painter always draws the track and thumb left-to-right (`toggleLeft = _border + (fullWidth - switchDiam) * t`, thumb moves left→right as it turns on). AyuGram draws both the track (`bgRect`) and thumb (`fgRect`) through `style::rtlrect(...)`, which in RTL mirrors x to `outerw - x - w`, so the thumb travels right→left and the whole switch flips. The `_TogglePainter` has no `Directionality`/`textDirection` awareness, so in RTL locales the switch points the wrong way. This matters here because target platforms (Bale, Rubika) are Persian/RTL. — `ayu_toggle.dart:178` (and rects `:168-180`) ← `AyuGram/lib_ui/ui/widgets/checkbox.cpp:118-119` (`style::rtlrect`, def `lib_ui/ui/style/style_core_direction.h:47-48`)

- [ ] [MAJOR] Mid-animation interruption diverges in both duration and curve. AyuGram's `Animations::Simple::start` calls `startPrepared`, which sets `from = current value` and animates to the target over the **full** `_duration` (150ms) with a **fresh** easeOutCubic (`checkbox.cpp:57-62` → `animations.h:475-477`; the passed `from`/`to` of 0/1 are overridden by the live value, and 150ms < kLongAnimationDuration=1000ms so the timer fully restarts). The Dart widget drives an `AnimationController` with `forward()`/`reverse()`: (a) those scale the simulation duration by the remaining fraction (e.g. interrupt at t=0.5 → reverse takes ~75ms, not 150ms), and (b) `CurvedAnimation._curveDirection` latches to the first direction and is only reset on completed/dismissed, so an interrupting `reverse()` keeps applying the **forward** `easeOutCubic` instead of the reverse `(1-dt)³` — making the interrupted off-animation *accelerate* into off where AyuGram *decelerates*. Normal (settled) toggles are unaffected; only rapid re-taps within 150ms differ. — `ayu_toggle.dart:66-72` ← `AyuGram/lib_ui/ui/widgets/checkbox.cpp:57-62` (+ `lib_ui/ui/effects/animations.h:475-477`)

- [ ] [MAJOR] `shouldRepaint` omits paint-affecting fields. It compares only `t`, `fgColor`, `bgColor` — not `isMaterial`, `switchDiam`, or `switchShift`. In AyuGram these are derived live from `AyuUiSettings::isMaterialSwitches()` (diameter 14↔16, shift -2↔1, plus the animPadding shrink), and the widget explicitly treats `isMaterial` as a live, user-toggleable setting (`didUpdateWidget` re-derives the duration, `:60-65`). When the user flips the materialSwitches setting while a toggle is at rest (t=0/1, colors unchanged), `shouldRepaint` returns false, so the switch can keep rendering the old diameter/shift/padding until it is next interacted with — the live-update the author built is not fully wired through. — `ayu_toggle.dart:204-205` ← `AyuGram/lib_ui/ui/widgets/checkbox.cpp:24-29` (SwitchShift/SwitchDiameter switch on isMaterialSwitches)

# birthday_picker — Telegram birthday drum picker (day/month/year wheels), port of AyuGram `EditBirthdayBox` + `VerticalDrumPicker`

Scope note: the numeric port is faithful — max-date clamping (`edit_birthday_box.cpp:55-66`), leap-year/month/day counts (`:108,146-154`), year index/"—" handling (`:63-66,104-107`), column widths quarter|half|quarter and order day|month|year (`:92-99`), selection-band lines (`:181-187`), the yScale squish + opacity fade (`vertical_drum_picker.cpp:40-47`), and the result mapping (`:201-206`) all match. Both callers (`my_profile_page.dart:305 updateBirthday`, `contacts_screen.dart:1763 suggestBirthday`) wire the returned record to the engine, so there is no stub/broken-wiring issue. The findings below are missing/wrong interaction behaviors.

- [ ] [MAJOR] Tap/click-to-select is missing. In AyuGram, clicking a non-centered item scrolls it to the center (`toOffset = centerOffset - clickY/itemHeight` then animated `jumpToOffset`), so mouse users select by clicking any visible row. The Dart `_VerticalDrumPicker` only wires `onVerticalDragUpdate`/`onVerticalDragEnd` and a scroll `Listener` — there is no `onTapUp`/tap handler, so tapping a row does nothing. — `birthday_picker.dart:430-441` ← `AyuGram/ui/widgets/vertical_drum_picker.cpp:248-257`

- [ ] [MAJOR] Keyboard navigation is missing. AyuGram installs a box-level event filter that forwards every KeyPress to `years->handleKeyEvent`, and `handleKeyEvent` maps Up/Left → previous, Down/Right → next, PageUp/PageDown → jump a page. The Dart dialog has no `Focus`/`KeyboardListener`/`Shortcuts` and `_VerticalDrumPicker` handles no key events, so arrow/PageUp/PageDown keys do nothing. — `birthday_picker.dart:419-441` (no keyboard handling) ← `AyuGram/ui/boxes/edit_birthday_box.cpp:190-195` + `AyuGram/ui/widgets/vertical_drum_picker.cpp:224-234`

- [ ] [MAJOR] Mouse-wheel scrolling has the wrong granularity. AyuGram advances exactly one item per wheel notch via an animated `jumpToOffset(direction)` (`handleWheelEvent`). The Dart code instead adds the raw `event.scrollDelta.dy` straight onto `_scrollOffset` and then snaps, so a single wheel notch can skip multiple items (and jumps instantly before the snap) rather than stepping one item per notch. — `birthday_picker.dart:420-428` ← `AyuGram/ui/widgets/vertical_drum_picker.cpp:197-222`

- [ ] [MAJOR] Snap animation uses the wrong easing. The Dart snap interpolates `_scrollOffset` with `Curves.easeOutCubic` over 200 ms. AyuGram's `PickerAnimation::jumpToOffset` calls `Animations::Simple::start(..., st::fadeWrapDuration)` with the default transition `anim::linear` and `anim::interpolateF` (linear) — the easeOutCubic in AyuGram is used *only* for the per-item yScale squish in the paint callback, not for the scroll snap. Duration matches (200 ms = `fadeWrapDuration`); the easing curve is the deviation, and because the snap drives the fade/squish it also alters their timeline. — `birthday_picker.dart:350` ← `AyuGram/ui/widgets/vertical_drum_picker.cpp:83-87` (default `anim::linear`, `animations.h:67`)

- [ ] [MAJOR] Month-wheel labels are hardcoded English instead of localized. AyuGram paints month names via `Lang::Month(index + 1)(tr::now)` (locale-aware). The Dart picker uses a hardcoded English `_monthNames` array, so the wheel never localizes. (Note: a project-wide pattern — `lang_pack.dart` has no month strings and other date widgets hardcode them too — but it is still a deviation from the AyuGram source authority.) — `birthday_picker.dart:52-55,221` ← `AyuGram/ui/boxes/edit_birthday_box.cpp:119-124`

# call_panel — 1:1 call panel (incoming / connecting / active / busy / ended), answer button, controls, encryption fingerprint, signal bars, self-view bubble, conference invite, call rating

The widget tree is a faithful visual port of AyuGram's `Calls::Panel` (button order,
body layout, fingerprint badge geometry, signal-bars metrics, self-view snap-to-corner,
outgoing-preview interpolation all match the `.style` values). The problems are all in
the **data path** — the production entry point (`startOutgoingCall` / `showCallPanel`,
both in this file) never feeds the panel the live call data that AyuGram's `Panel`
binds to, so several core call features render only when fed mock data from the
`flutter_interact.sh` debug command (`main.dart:1287`), never in a real call.

- [ ] [CRITICAL] Encryption fingerprint (the security-verification emoji — a core E2E call feature) is never wired to a real call. `startOutgoingCall`'s `onCallState` handler builds `CallPanelInfo` without `fingerprintEmoji`, so it stays `const []` → `_buildFingerprintBadge`'s `hasFingerprint` is always false and the emoji badge never appears for any real outgoing call. The engine's call `meta` (telegram.go:3214-3221) carries no emoji key either. AyuGram creates the badge from the real auth-key SHA once `isKeyShaForFingerprintReady()`. — `call_panel.dart:2560` (and `:968`) ← `AyuGram/calls/calls_panel.cpp:1448` / `calls_call.h:238`

- [ ] [CRITICAL] Signal-strength bars are never wired to a real call. The same `onCallState` handler never sets `signalQuality`, so it defaults to `-1` → `_buildFingerprintBadge`'s `hasSignal` is always false and `_SignalBars` never renders for a real call (only the debug command at `main.dart:1269` injects a value). AyuGram's `SignalBars` binds live to `call->signalBarCountValue()`. — `call_panel.dart:2560` (and `:969`, `:2195`) ← `AyuGram/calls/calls_signal_bars.cpp:26` / `calls_call.h:213`

- [ ] [CRITICAL] 1:1 call video is never displayed. `startOutgoingCall` calls `showCallPanel` without `remoteVideoWidget`/`selfVideoWidget`, and those are one-time constructor args of `_LiveCallPanelDialog` (not part of the streamed `CallPanelInfo`), so there is no channel to ever supply them. Result: `_buildActiveVideoState` (guarded by `remoteVideoWidget != null`, line 1150) and `_SelfViewBubble`/`_OutgoingPreview` (guarded by `selfVideoWidget != null`, lines 1138/1195/845) are unreachable in production — a video call, or enabling the camera mid-call, shows only avatars. AyuGram wires `_call->videoIncoming()`/`videoOutgoing()` to live tracks. — `call_panel.dart:2582` (and `:1150`, `:1138`) ← `AyuGram/calls/calls_panel.cpp:685`

- [ ] [MAJOR] Incoming calls and conference invites have no production trigger. This file exposes only `startOutgoingCall`; the generic `showCallPanel` is called for incoming calls solely by the debug command (`main.dart:1223 'showCallPanel'`), and the engine's `onIncomingCall` stream (engine_service.dart:80) has no listener anywhere. So `_buildIncomingState`, `_AnswerButton`, and `_buildConferenceParticipantsRow` never display for a real incoming call. AyuGram opens the panel from `createCall(user, Call::Type::Incoming, …)` in `handleCallUpdate`. — `call_panel.dart:2605` (and `:760`, `:683`) ← `AyuGram/calls/calls_instance.cpp:707`

- [ ] [MAJOR] Call duration is clocked client-side instead of from the engine. `_startDurationTimer` uses `DateTime.now()` because `startOutgoingCall` never sets `callStartTime` on the streamed `CallPanelInfo` (it builds with `callId`/`state` only), so the timer starts whenever the client first sees `active` rather than the call's true connect time. AyuGram displays `_call->getDurationMs()` — the authoritative duration from the call instance. — `call_panel.dart:327` (and `:2560`) ← `AyuGram/calls/calls_panel.cpp:1482` / `calls_call.h:228`

- [ ] [MAJOR] Remote "microphone off" and "battery low" tooltips are shown together; AyuGram shows only one. `_buildRemotePills` stacks both pills in a Column when both flags are set. AyuGram positions both labels in the same slot and `showRemoteLowBattery()` hides the low-battery label whenever the mute label is visible (`setVisible(!_remoteAudioMute || _remoteAudioMute->isHidden())`) — mute takes priority, never both at once. — `call_panel.dart:877` ← `AyuGram/calls/calls_panel.cpp:965`

# call_screen — group call panel + minimised call bar (AyuGram `Calls::Group::Panel` + `Calls::TopBar`)

Audited `dart/lib/ui/call_screen.dart` (4521 lines) against AyuGram `calls/group/*` + `calls/calls_top_bar.cpp` + `ui/controls/call_mute_button.cpp`. The file is genuinely wired to the engine throughout (no placeholder snackbars / mock data). Findings are deviations in colour-state, layout button-set, menu conditions, and a dead screen-share wiring.

## Big mute button — colours/states (`_BigMuteButton`)

AyuGram's `Colors()` map (`call_mute_button.cpp:146-168`) gives every state a specific palette gradient. The Dart uses three flat colours (`_greenColor 0xFF4DC920`, `_grayColor 0xFF808B94`, `_purpleColor 0xFF7B5EBF`, `call_screen.dart:1936-1938`).

- [ ] [CRITICAL] "Muted" (you muted yourself) renders flat GRAY `0xFF808B94` — identical to the "Connecting…" gray — instead of AyuGram's blue→cyan gradient `#0992ef`→`#16ccfb`. Two distinct states are visually indistinguishable. Connecting should also differ: translucent white `callIconBg #ffffff1f`, not gray. — `call_screen.dart:2011-2016` (`_stateColor` connecting+muted → `_grayColor`) ← `AyuGram/Telegram/SourceFiles/ui/controls/call_mute_button.cpp:147-152` (Muted=`groupCallMuted1/2`, Connecting=`callIconBg`) + `AyuGram/Telegram/lib_ui/ui/colors.palette:557,584-585`
- [ ] [MAJOR] "Active / You are Live" is flat green `0xFF4DC920`; AyuGram is a green→teal gradient `#0dcc39`→`#0bb6bd` (`groupCallLive1/2`). Wrong hex and missing the second stop. — `call_screen.dart:2013-2014` ← `AyuGram/.../call_mute_button.cpp:143` + `colors.palette:582-583`
- [ ] [MAJOR] "ForceMuted"/"RaisedHand" is flat purple `0xFF7B5EBF`; AyuGram is a 3-stop ramp red→purple→blue `#eb5353`→`#9b52e9`→`#4f9cff` (`groupCallForceMuted3/2/1`). — `call_screen.dart:2017-2021` ← `AyuGram/.../call_mute_button.cpp:154-157` + `colors.palette:589-591`
- [ ] [MAJOR] Scheduled "Start Now" uses green + a `play_arrow` icon; AyuGram's scheduled states (`ScheduledCanStart/Notify/Silent`) all reuse the force-muted red/purple/blue ramp with the hands Lottie — there is no green and no play glyph. — `call_screen.dart:2007-2009,2061` (`_stateColor`/`_icon` scheduled) ← `AyuGram/.../call_mute_button.cpp:158-168` (forceMutedTypes includes all scheduled) + `call_mute_button.h:36-46` (enum)

## Bottom control bar (`_buildBottomControls`)

The Dart renders a fixed 5-button `spaceEvenly` row `[Video, Settings, Mute, Chat, Hangup]` in BOTH narrow and wide mode (`call_screen.dart:989-1022`). AyuGram computes the set conditionally (`updateButtonsGeometry`).

- [ ] [CRITICAL] Screen-share button is MISSING from wide mode, and `onToggleScreenShare`/`isScreenShareActive` are passed into `GroupCallPanel` but never invoked by any widget (dead wiring — screen-share is only reachable via the "…" menu). AyuGram makes `_screenShare` a PRIMARY wide-mode bottom button (shown when `!rtmp && !messagesEnabled`). — `call_screen.dart:42,49,76,2606` (callback defined+passed, never used in `build`) ← `AyuGram/Telegram/SourceFiles/calls/group/calls_group_panel.cpp:2514-2518`
- [ ] [MAJOR] Narrow mode hardcodes 5 buttons; AyuGram's narrow DEFAULT (messages off) is 3 buttons `[Video, Mute(center), Hangup]` with `_settings` and `_screenShare` OFF the bar (`toggle(_screenShare,false)`; settings only when `five || !showVideoButton`). The 5-button row only exists when `messagesEnabled`. — `call_screen.dart:989-1022` ← `AyuGram/.../calls_group_panel.cpp:2570-2582,2630,2641`
- [ ] [MAJOR] The 4th button is a generic "Chat" toggle shown unconditionally and wired to a local message-panel toggle; AyuGram's 4th slot is `_message`, gated on the server flag `messagesEnabled` (`toggle(_message, !_callShare && messagesEnabled)`), and is the typing/live-messages control — absent entirely when messages aren't enabled. — `call_screen.dart:1010-1015` ← `AyuGram/.../calls_group_panel.cpp:2647-2650`

## "…" menu (`_showGroupCallMenu`)

AyuGram's `FillMenu` (`calls_group_menu.cpp:488-627`) gates every item; the Dart shows most unconditionally.

- [ ] [MAJOR] "Start/Stop Recording" is shown to ALL users; AyuGram gates it on `addEditRecording = !conference && canManage() && !scheduleDate()`. A non-admin sees an admin action that fails server-side. — `call_screen.dart:2948-2957` ← `AyuGram/.../calls_group_menu.cpp:513-515`
- [ ] [MAJOR] "Share Screen" and "Join As…" are shown unconditionally; AyuGram gates Share Screen on `videoIsWorking() && !scheduleDate()` and Join As on `showChooseJoinAs()`. — `call_screen.dart:2922-2930,2995-2999` ← `AyuGram/.../calls_group_menu.cpp:511,516-517`
- [ ] [MAJOR] "Leave Call" always calls plain `leaveGroupCall` with a fixed label; for a manager AyuGram shows "End"/"Cancel" variants and routes through `LeaveBox` (the "also end the call for everyone" choice / `discard` vs `hangup`). The Dart's leave-or-end dialog exists (`_showLeaveOrEndDialog`) but is NOT used by this menu item, so a manager cannot end-for-all from here. — `call_screen.dart:3030-3040` ← `AyuGram/.../calls_group_menu.cpp:605-626`

(Note: Dart adds an "Invite Members" item that AyuGram's `FillMenu` does not have — extra but functional, so not scored.)

## Call settings sheet (`_CallSettingsSheet`)

- [ ] [MAJOR] Missing the "Share invite link" button — a primary control in AyuGram's `SettingsBox` for normal group/channel calls. The Dart sheet has no link-sharing row at all. — `call_screen.dart:3404-3545` (no share row) ← `AyuGram/Telegram/SourceFiles/calls/group/calls_group_settings.cpp:674-680`

## Participant context menu (`_showParticipantMenu`)

AyuGram builds this in `createRowContextMenu` + `addMuteActionsToContextMenu` (`calls_group_members.cpp:1325-1699`).

- [ ] [MAJOR] "Mute"/"Unmute" is offered on the SELF row (admin) and on fellow admins; AyuGram suppresses the mute action for `isMe`, requires a live ssrc, and protects co-admins (`Inactive && participantIsCallAdmin && canManage` → no action). The Dart gates only on `!p.isMuted && widget.isCanManage` with no self/admin/ssrc check. — `call_screen.dart:634-638` ← `AyuGram/.../calls_group_members.cpp:1662-1678`
- [ ] [MAJOR] "Remove from call" (kick) is offered for any non-self participant when `canManage`; AyuGram's `canKick` excludes the chat creator and other admins (ban-rights / `canRestrictParticipant` logic). The Dart can offer Remove on a co-admin or the creator. — `call_screen.dart:655-661` ← `AyuGram/.../calls_group_members.cpp:1521-1545`
- [ ] [MAJOR] Volume is a plain "Volume: X%" item that opens a separate `AlertDialog` slider; AyuGram embeds a live inline `MenuVolumeItem` slider directly in the popup (which also carries the local mute-for-me toggle). Different interaction model. — `call_screen.dart:650-653,716-756` (`_showVolumeSlider`) ← `AyuGram/.../calls_group_members.cpp:1600-1647`

## Minimised call bar (`MinimisedCallBar`)

- [ ] [MAJOR] The minimised bar renders a running call-duration label for GROUP calls; AyuGram constructs `_durationLabel`/`_signalBars` only when `_call` is non-null (personal 1:1 calls) and `updateDurationText` early-returns for group calls — a group bar shows the info/participants label, never a duration. — `call_screen.dart:4000-4013` ← `AyuGram/Telegram/SourceFiles/calls/calls_top_bar.cpp:259-264,733-734`

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
labels match the lang pack. Two data-flow defects found.

- [ ] [MAJOR] Per-contact video selection is dropped for multi-select / conference calls: the row exposes an audio vs. video toggle and stores it in `_selectedVideo`, but the conference invite passes only user IDs (`inviteToConferenceCall(accountId, result.callId, _selectedIds.toList())`), so every conference invitee is invited audio-only regardless of the video icon the user picked. The video flag is honored only on the single-contact 1:1 path (`startCall(..., video: video)` at `calls_screen.dart:1126`). AyuGram preserves the per-user flag through `ConfInviteController::requests()` which builds `InviteRequest{ user, _withVideo.contains(user) }` and passes it via `.invite` into `startOrJoinConferenceCall` / `inviteUsers`. — `calls_screen.dart:1145` ← `AyuGram/Telegram/SourceFiles/calls/group/calls_group_invite_controller.cpp:504`

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

