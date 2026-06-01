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

All 7 findings resolved & verified against AyuGram source (2026-05-31): photo 327×197 aspect-correct, avatar DecideColorIndex color mapping, avatar vertical gradient, colorized previews accent, group chat-type icon, audio play-circle 44/bubble 60, search field filterInputInactiveBg key.

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

All 8 findings resolved & verified against AyuGram .style ground truth (2026-05-31):
boxRadius 6 (layers.style:38), infoProfilePhotoSize 72 (info.style:527),
settingsProfileCoverHeight 162 (settings.style:205), radialSize 50 (basic.style:118),
defaultInputFieldHeight 55 (widgets.style:1070), defaultRadioDuration 120ms /
defaultRadioDurationDouble 240ms (widgets.style:868 = universalDuration, basic.style:131),
menuIconSize removed (0 occurrences across AyuGram lib_ui/+SourceFiles). Flutter build
PASS; app launches & runs (engine init, chat list, live events) with no errors tied to
these tokens.

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

## MAJOR

# active_sessions_screen — Active Sessions / device management

Audited `dart/lib/ui/active_sessions_screen.dart` against AyuGram's
`settings/sections/settings_active_sessions.cpp`, `boxes/self_destruction_box.cpp`,
`api/api_authorizations.cpp`, and `settings/settings.style`.

**Wiring/structure/dimensions are faithful** — see the verified-OK notes at the
bottom. All displayed-text / data-content deviations from the AyuGram
ground-truth lang strings have been fixed and verified (desktop + mobile,
against live session data) — section closed.

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

# auth_screen — Telegram intro/auth flow (choose · QR · phone · email · OTP · 2FA · signup)

Compared `dart/lib/ui/auth_screen.dart` against AyuGram `intro/` widgets.
The file is well-wired: every interaction calls the real engine
(`submitInput → _engine.submitAuthInput`, `switchToMethod`, `cancelAuth`,
`engine.uploadProfilePhoto`, `engine.updateConfig`), QR payload/redundancy,
OTP cell geometry (40×50, 10px gap, 4px border, 20px font, 6px radius),
shake (4px/300ms), 2FA/recovery field tops (74/96/151/220) all match.
**No placeholders, stubs, mock data, or unwired elements — no CRITICAL items.**
All MAJOR findings have been fixed and verified (desktop + mobile, against a live
session). The last one — the persistent phone→QR "Quick log in using QR code" link
(`lng_phone_to_qr`, `intro_phone.cpp:111`) — now sits below the phone field and uses
`switchToMethod('qr_code')` (the engine's choose-step option id at `auth.go:279/385`;
`'qr'` is only the state name). Tapping it in both modes drives
choose→`submitInput(qr_code)`→`state=qr` and renders the live QR screen. Section closed.

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

All 3 findings resolved & verified in-app on 2026-06-01 (desktop 1024×768 + mobile 400×720) against AyuGram source: the per-dialog "+" now scopes the new filter to its dialog (`dialogId: widget.dialogId`) — it appears in the dialog’s "Filters" section and surfaces a "Per-Dialog Filters" entry, and is absent from "Shared Filters" ← edit_filter.cpp:198-200; the save is silent with no "Restrict" SnackBar (`Navigator.pop` only; the toast-with-action is context-menu-only, context_menu.cpp:946 showToast=true) ← edit_filter.cpp:222-243; the added filter stays visible via `filtersForDialog` instead of vanishing ← settings_filters_list.cpp:214-216.

# ayu_general_page — AyuGram "General" settings page

Ground truth: `AyuGramDesktop/.../ayu/ui/settings/settings_general.cpp` (`BuildQoLToggles`,
`BuildTranslator`, `BuildShowPeerId`); builder `ayu/ui/settings/ayu_builder.{h,cpp}`;
model `ayu/ayu_settings.h`; labels `Telegram/Resources/langs/lang.strings`.

The page IS implemented and wired (reachable from `ayugram_settings_screen.dart:152`); no
empty callbacks / stubs / mock data. Every AyuGram General setting is present and every
control binds to an `AppState` setter. The findings below are behavioral/content deviations
from the AyuGram source, confirmed against it.

## MAJOR findings

All 5 findings resolved & verified in-app on 2026-06-01 (desktop 1024×768 + mobile 400×720)
against AyuGram source:
(1) Translation Provider now carries a "BETA" badge wrapped in `IgnorePointer` so taps fall
through to the choose button — verified: tapping the badge opens the provider dialog
← `settings_general.cpp:113-115` + `settings_ayu_utils.cpp:47-76`.
(2) "Disable Stories" applies the setting then shows a "Restart Now"/"Later" prompt — verified
apply-then-prompt in both modes; "Later" dismisses without restarting and keeps the setting
← `settings_general.cpp:171-174` + `settings_ayu_utils.cpp:36-45`.
(3) All 10 fabricated toggle subtitles removed — every General row renders title-only
← `ayu_builder.h:22-43` (`ToggleArgs`/`SettingToggleArgs` have no description field).
(4) Collapsibles now pass explicit `toggledWhenAll` and start collapsed — verified: Disable
Similar Channels (`toggledWhenAll=true`, AND) shows master OFF at 1/2 and ON at 2/2; Bigger
Window (`toggledWhenAll=false`, OR) shows master ON at 1/2
← `settings_general.cpp:199,274` + `settings_ayu_utils.cpp:216-222,454`.
(5) Translation subsection header is now "Translate Messages" (`lng_translate_settings_subtitle`)
with the button beneath still titled "Translation Provider"
← `settings_general.cpp:37,83` + `lang.strings:6911`.

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

# ayu_toggle — AyuGram `defaultToggle` switch (ToggleView replica)

Audited `dart/lib/ui/ayu_toggle.dart` against AyuGram's `ToggleView` (`lib_ui/ui/widgets/checkbox.cpp`) and the `defaultToggle` style (`lib_ui/ui/widgets/widgets.style:874-890`).

The geometry/painting port is faithful: dimensions (border 2 / diameter 14|16 / width 14 / shift -2|1 / animPadding 2), `getSize` → totalW/totalH, track RRect, thumb ellipse, the material `animPadding` deflation (`interpolateToF(animPadding,0,t)=animPadding*(1-t)`, `animation_value.h:102`), and the color lerps (track + thumb-border = checkboxFg→windowBgActive, thumb-fill = windowBg) all match line-for-line. The XV/lock paint branches are correctly omitted — `defaultToggle` sets xsize/vsize/stroke = 0 and no lockIcon, so those branches never execute. `onChanged` is a real controlled-component callback wired by callers (`ayu_section_builder.dart:409`), not a stub.

One behavioral deviation found:

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

All 5 findings resolved & verified on 2026-06-01 against AyuGram source (code review +
22-case unit test + live app, desktop 1024×768 + mobile 400×720, no FILTER FAILED):
(1) Single (non-album) message text is now trimmed before matching, like AyuGram's
`extractSingle(item).trimmed()` ← filters_utils.cpp:668.
(2) Block/shadowban verdict is evaluated on EVERY isFiltered() call — before isEnabled()
and before the regex cache — and never cached (only the dialog is marked via
`_hiddenBlockedChats`), so block/unblock & shadowban changes re-hide/re-show already-rendered
messages instead of going stale until rebuildCache() ← filters_controller.cpp:161-171.
(3) Filter ids use AyuGram's 16-byte UUID-v4 wire format via shared `generateFilterId()`; the
in-chat quick-filter no longer emits a decimal microsecond ts that ParseFilterId drops on import;
`exportFilters` canonicalises every id/exclusion filterId ← filters_utils.cpp:202-213,445-451,734-737.
(4) Service-type mapping dropped `group_call`→16 and `mediaType==2`→8; 16 is emitted only
for a real 1-1 call, group calls/service videos fall through to TYPE_DATE (10) ← filters_utils.cpp:604-635.
(5) ICU→Dart regex bridge: `compileFilterPattern()`/`_translateIcuPattern()` translate POSIX
classes and possessive quantifiers in an escape-aware pass and opt into Unicode mode for
`\p{...}`/`\u{...}`; the validator (`_validateRegex`) shares that path ← filters_cache_controller.cpp:55-59.

## Notes (known platform limitation — not flagged)

- Negated POSIX classes `[[:^alpha:]]` are translated to their *positive* body (the leading `^`
  is stripped and the positive range emitted), so a negated POSIX class would match the opposite
  set. This is a rare ICU-only construct and Dart character classes cannot express nested
  set-negation the way ICU does, so it sits in the same "no ICU in pure Dart" bucket as finding 5.
  The common POSIX classes (`[[:alpha:]]`, `[[:digit:]]`, combined) compile and match correctly. —
  `ayu_filter.dart` (`_translateIcuPattern` POSIX branch)

# emoji_data — emoji keyword search & language-pack manager

Dart port of AyuGram's `chat_helpers/emoji_keywords.cpp` (LangPack manager, query, PrioritizeRecent, ApplyVariants, ApplyDifference) + `lib_ui/emoji_suggestions/emoji_suggestions.cpp` (legacy `:shortcode:` Completer).

Core path is genuinely wired (NOT a stub): engine fetch in `chat_view.dart:3789` (`getEmojiKeywordsLanguages`→`getEmojiKeywords`/`getEmojiKeywordsDiff`), versioned diff, `recordRecent` on pick (`chat_view.dart:3874/3895`), recents persisted via `saveCallback` (`main.dart:321`), and `searchEmoji` consumed in 4 UI sites. Server lang-pack binary search (`_searchLangPack`) faithfully mirrors C++ `LangPack::query` (lower_bound + take_while startsWith). The deviations below are real behavior/data-flow gaps vs the authoritative C++.

All 5 findings resolved & verified on 2026-06-01 against AyuGram source (code review +
5-case unit test + live app smoke in the chat composer, no emoji errors, no crashes; Go +
Flutter build clean). These are screen-size-independent suggestion logic — identical in
desktop & mobile (the suggestion popup widget is shared; the window-resize MethodChannel is
a no-op on this Wayland host, so the live shot is desktop 1024×768):
(1) Interior-word matching — the built-in fallback ports `Completer::matchQueryTailStartingFrom` +
`findWordsStartingWith` over first-char-sorted keyword words; unit-tested "police"→🚔
(`:oncoming_police_car:`) and "heart"→💑 (`:couple_with_heart:`), both lost under the old
`kw.startsWith(q)` ← emoji_suggestions.cpp:333,406.
(2) Ranking — `_legacyRankKey` reproduces `prepareResult`'s 4 stacked `stable_partition`s as a
bit-priority (exact > words-used<3 > words-used<2 > first-char-after-colon==query-first-char);
unit-tested exact ❤️ ranks first for "heart" and first-char-good 🚓 precedes first-char-bad 🚔
for "police" ← emoji_suggestions.cpp:373.
(3) Variants live — `skinToneResolver` is wired to the emoji panel's `_displayEmoji` at startup
and on account switch (`initEmojiSuggestionVariants`), and `applyVariant` routes through it;
unit-tested `search()` applies the resolved tone instead of the default (was a permanent no-op)
← emoji_keywords.cpp:674 (`ApplyVariants`/`lookupEmojiVariant`).
(4) Deletions honored — Go core now distinguishes `emojiKeyword` vs `emojiKeywordDeleted`, the
`deleted` flag flows engine→Dart model→`chat_view` (added/deleted split, no more `deleted:{}`),
and the delete path postfixes the raw text before matching the postfixed store; also fixed
`MessagesGetEmojiKeywords` to return `interface{}` so the engine fetcher assertion matches —
verified live: `GetEmojiKeywords` now returns 231KB/331KB (the whole server path was previously
dead) ← emoji_keywords.cpp:274.
(5) Recents — `_prioritizeRecent` searches the whole list from the start and rotates a match to
the frontier only when strictly past it (`removeAt`+`insert` ≡ `std::rotate`, no `==`-advance
branch); unit-tested list+recent `[❤️,💑]`→`[💑,❤️]` leapfrog ← emoji_keywords.cpp:650.

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

_All wired string issues resolved — verified verbatim against `lang.strings`._

## LATENT — RESOLVED (verified Stage 2, commit fb8bf1c0)

_All three LATENT string values verified verbatim against `lang.strings` AND wired into their real consumer `dart/lib/ui/confirm_box.dart`, replacing the previously-hardcoded divergent English:_

- _Suggested-post warning → `_showPaidPostWarning` now uses `lngSuggestWarnTitle/Text{Ton,Stars}` + `lngSuggestWarnDeleteAnyway`; added a `boldMarkup` path so `**TON**`/`**24 hours**` render bold (Telegram `tr::rich`). Titles "TON/Stars will be lost" + the "must remain visible for at least 24 hours" rule restored. (= lang.strings:5418-5422)_
- _`lngProfileBlockBot()` = "Stop and block bot" → delete-chat bot checkbox (confirm_box.dart:866). (= lang.strings:1625)_
- _`lngFiltersCheckboxRemoveBot()` = "Remove bot from all folders" → delete-chat bot checkbox (confirm_box.dart:871). (= lang.strings:7139)_

_Verification notes: build clean; app launches & loads chats; delete-confirm box renders correctly and the `isBot && leaveChat` checkbox gate was confirmed (correctly hidden for a non-bot DM). The bot-checkbox and paid-post variants could not be rendered live in this session (test account has no real bot DM and global search is broken — see below), but the strings are direct, transformation-free `_checkbox`/`Text` renders of the verbatim-correct values._

## FOLLOW-UP — gaps found during Stage-2 verification (strings correct, consumer paths still incomplete)

- [ ] [MAJOR] Folder-removal checkbox is wired for **bots only**. `lngFiltersCheckboxRemoveGroup()`/`lngFiltersCheckboxRemoveChannel()` ("Remove group/channel from all folders", verbatim-correct) are defined but unconsumed — `confirm_box.dart:864-872` shows the "remove from folders" checkbox only under `widget.isBot && leaveChat`. AyuGram's `maybeChatsFiltersCheckbox` shows it for non-bot non-user peers (groups/channels) too, picking the label by entity type and only when the chat is actually in a folder. ← `boxes/moderate_messages_box.cpp:1044-1066`
- [ ] [MINOR] Paid-post deletion warning is currently unreachable: no `showDeleteConfirmBox` caller passes `isPaidPost: true`, and `engine_models.dart` Message has no suggested-post/paid flag. The corrected `lngSuggestWarn*` strings + `boldMarkup` path are wired but cannot render until suggested-post detection is added and the single/bulk delete call sites set `isPaidPost`. ← `boxes/delete_messages_box.cpp:563-576`
- [ ] [CRITICAL] (engine, not strings — found while testing this section) Global chat search is broken: typing in the dialog search box → `__engine.SearchChats FAILED: sql: expected 44 destination arguments in Scan, not 46` (`engine_service.dart:5143` ← `chat_list_panel.dart:539`). Search shows only frequent contacts; no chat/global results render.

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

