# GUI Audit — Cycle 5 Phase Ayugram (2026-06-10 14:32)

## Code Comparison (Dart vs AyuGram)

# app_state — top-level settings/state port (`core_settings` + `ayu/ayu_settings` + domain/passcode/proxy/notify)

Scope: `app_state.dart` ports AyuGram's `AyuSettings` (`ayu/ayu_settings.{h,cpp}`), Telegram `Core::Settings` fragments
(`core/core_settings*.{h,cpp}`), `Main::Domain` account limits, passcode/auto-lock, proxy, power-saving and
notification settings into a single `ChangeNotifier`.

Verified MATCHING 1:1 against AyuGram (no issue): every `AyuSettings` default value (ayu_settings.h:615-704),
`GhostModeAccountSettings`/`MessageShotSettings` defaults + `to_json`/`from_json` + `setEmbeddedTheme`/`setCloudTheme`/
`clearTheme`/`isCloudThemeEmpty` (ayu_settings.cpp:184-354), `ghostModeActive`/`shouldSendWithoutSound`
(ayu_settings.cpp:62-122), the per-account ghost resolution `getOverriddenGhostUserId` (ayu_settings.cpp:437-448),
the full `validate()` clamp set — bubbleRadius[0,16] / wideMultiplier[0.5,4.0] / recentStickersCount[1,200] /
avatarCorners[0,23] / enums[0,2] / translationProvider[0,3] / embeddedThemeType{-1,0..3} (ayu_settings.cpp:481-533),
ghost lock-denial `lockedCount+1 >= size` (settings_ayu_utils.cpp:393-396), `maxAccounts =
min(premium+kMaxAccounts, kPremiumMaxAccounts)` with 100/200 (main_domain.cpp:503-510, main_domain.h:34-35),
proxy-rotation default 10 (core_settings_proxy.h:25), `kDefaultVolume = 0.9` (core_settings.h:123), power-saving
`On(flag)=ForceAll||(flags&flag)` (power_saving.h). No placeholders, stubs, mock data, or dead callbacks exist in
this file.

# auth_state — Telegram intro/auth flow controller (port of AyuGram intro_widget + intro Steps)

## Verified faithful (no action needed — recorded for traceability)

- `switchToMethod` does an in-place step swap on the SAME live MTProto connection via engine `SwitchAuthMethod` (no `cancelAuth`/`core.Close()`, no `_currentAuth = null` flash, no reconnect/re-submit) — mirrors AyuGram `goReplace<PhoneWidget>/<QrWidget>(Animate::Forward)` preserving `_account`/`_data` — `auth_state.dart:151-178`, `engine/auth.go:285-354` (SwitchAuthMethod), `telegram.go` (StartQRAuth re-export on live conn + `teardownPriorAuthAttempt` re-arms the one-shot channel) ← `intro_qr.cpp:274`, `intro_phone.cpp:129`, `intro_step.h:139-142`. Verified live: phone↔QR both directions desktop+mobile, one `SwitchAuthMethod` round-trip each (no `CancelAuth`/2nd `StartAuth`), QR re-entry reuses the connection (~0.3s re-export vs 3.8s first connect), zero panics.

- `startAuth`/`submitInput`/`goBack`/`cancelAuth`/`clear` all call the engine (`_engine.startAuth`/`submitAuthInput`/`goBackAuth`/`cancelAuth`) — `auth_state.dart:83,110,167,141,188`. No stubs, no empty callbacks, no mock data, no TODO/FIXME.
- QR refresh timer (`_updateQrExpiryTimer`/`_onQrExpired`) mirrors `QrWidget::refreshCode` rescheduling at expiry — `auth_state.dart:277-309` ← `intro_qr.cpp:417,440-441`. `qrExpiresIn` is relative seconds (engine computes `int(v.Expires) - int(time.Now().Unix())`, telegram.go:14037/14070), so the `-1` refreshes ~1s early — harmless.
- `_onQrExpired` refreshes in place via `submitAuthInput(id,'')` (engine QR case → `RefreshQRToken`), not `startAuth` — correctly avoids bouncing off the QR screen. ← `intro_qr.cpp:417,441`.
- `_handleLoginCode` applies a Telegram-pushed login code only on the `otp` step and skips Fragment delivery — mirrors `setHandleLoginCode` (installed in CodeWidget ctor, cleared in `finished()`) — `auth_state.dart:217-225` ← `intro_code.cpp:59-62,189`.
- Resend / "no Telegram code" / recovery / reset-account are wired through `submitInput` magic strings (`__resend_code`, `__no_telegram_code`, `__request_recovery`, `__reset_account`), all handled by the engine FSM (auth.go:540,555,631,646) → `ResendOTPCode`/`NoTelegramCode`/`RequestRecoveryDuringAuth` (telegram.go:1396,1442,1687). Real `auth.ResendCode`, not stubs.
- The call-countdown timer ("Telegram will call you in X" → auto-`ResendCode`) correctly lives in the `_OtpCodeInput` UI widget (auth_screen.dart:1856-2042: `_callTimer`/`_startCallTimer`, `_callSecondsLeft = timeoutSecs`, fires `onResendCode` at 0), fed by `AuthState.currentAuth.timeoutSecs`/`codeByTelegram` — matching AyuGram keeping `_callTimer.callEach(1000)` in CodeWidget, not the controller. ← `intro_code.cpp:110-112,302-321`.
- `_finalizeAuthError` maps SRP_ID_INVALID → final "Session expired" (no Dart-side retry) — mirrors `handleSrpIdInvalid` → `showError(ServerError)` on the repeat hit — `auth_state.dart:323-328` ← `intro_password_check.cpp:169-174`.
- Engine emits an `EventAuthState` on every transition in addition to returning the state (auth.go:106,173,267), so `_handleAuthEvent` reliably starts the QR/auto-poll timers even when the state also arrives as a direct return value — no missed-timer bug.
- `goBack` at the first (`choose`) step falls through to `cancelAuth` (engine `GoBackAuth` returns null with empty history) — a reasonable multi-platform adaptation of `backRequested` at the root (intro_widget.cpp:888-900), where the `choose` picker replaces AyuGram's QR-default first step.

# telegram_palette — Telegram Desktop color palette + accent colorizer port

Scope: `dart/lib/theme/telegram_palette.dart` ports three things 1:1 from AyuGram/tdesktop:
(1) the four embedded color schemes (classicDay / dayBlue / night / nightGreen) from
`colors.palette` + the `*.tdesktop-theme` override files, (2) the accent `colorize()`
algorithm from `style_palette_colorizer.cpp` + `ColorizerFrom`, and (3) the dark-theme
contrast pass (`keepContrast` / `kEnoughLightnessForContrast`).

Verification performed: parsed all 580 color keys × 4 themes and diffed them against
`colors.palette` merged with each theme's extracted `colors.tdesktop-theme`, resolving
references and the `#hex | fallback` fallback syntax per the real loader
(`style_core_palette.cpp:158-178`). Result: **classicDay and nightGreen match perfectly
(0/580 diffs); the colorize/contrast algorithms are a faithful, correct port** (HSV
piecewise S/V formulas, HSL lightness clamp, ignoreKeys, keepContrast→`fix()`, the
`includeFileIcons` Night-vs-NightGreen split, and the lightness formula `v-(v*s)/511` all
match). No placeholders, stubs, empty callbacks, fake data, or unwired UI. Average-color
for wallpaper service-tint runs in an isolate (`compute`), `PaletteProvider` is a correct
`InheritedWidget`. Both flagged deviations have been fixed and verified: dayBlue's `|`-fallback now resolves `dialogsReactionIconFg` → `attentionButtonFg` `0xFFD14E4E` and `dialogsPollIconFg` → `historyPeer5NameFg` `0xFF8544D6` (classicDay keeps the explicit `0xFFE05356`/`0xFF997BE1`), and `colorize()` now recolors `premiumIconBg3` via `s(...)` to match `kColorizeIgnoredKeys` (which omits it). Only the sub-threshold notes below remain.

## Notes (sub-threshold, not flagged)
- `night` theme: `filterInputInactiveBg` `0xFF232E3C` vs theme's `0xFF242F3D`, and
  `dialogsDateFgOver` `0xFF8696A8` vs theme's `0xFF8495A9` — each off by 1–2 per channel
  (sub-perceptual; likely a slightly different night.tdesktop-theme revision). Cosmetic.
  Refs: `telegram_palette.dart` night block (3671-4298) ←
  `night.tdesktop-theme/colors.tdesktop-theme` (`filterInputInactiveBg`, `dialogsDateFgOver`).
- `colorize()` hue gate uses `delta > threshold` to skip vs C++ `delta < threshold` to
  change (`style_palette_colorizer.cpp:27-29`); differs only for a color exactly 15.0° from
  the accent hue. Negligible. The added `alpha<0.004` / `saturation<0.01` guards in `s()`
  are defensive and equivalent for the blue/green base accents actually shipped.

# theme — Material `ThemeData` factory from `TelegramPalette` (AyuGram `.style`/`colors.palette` adapter)

Scope: `theme.dart` is a Flutter `ThemeData` builder that maps `TelegramPalette` tokens
onto Material-3 theming. It is NOT a 1:1 widget port; it adapts AyuGram's `.style`
dimensions/colors into Flutter's theme slots. Nearly every value was verified against
AyuGram ground truth and is accurate — see "Verified accurate" below. One real
behavioral divergence was found and is now fixed & verified: dark-theme detection
(`isDark`) uses AyuGram's authoritative `IsThemeDarkValue()` formula —
`HSVColor.fromColor(dialogsBg).value < 0.5` (= Qt `st::dialogsBg->c.valueF() <
kDarkValueThreshold`, 0.5; window_theme.cpp:1506/:58), not the colorizer-lightness
metric (`telegram_palette.dart:1240`; `_cppLightness` retained for the contrast port).

## Verified accurate (no action — recorded so this isn't re-audited)

- Input field theme (`theme.dart:57-80`): flat `UnderlineInputBorder` with `BorderRadius.zero`,
  resting 1px / focused 2px, `contentPadding (0,28,0,4)` — matches `defaultInputField`
  `textMargins: margins(0px,28px,0px,4px)` (`widgets.style:1045`), `border: 1px` /
  `borderActive: 2px` / `borderRadius: 0px` (`widgets.style:1062-1064`), which routes to
  `InputField::paintFlatSurrounding` (`input_field.cpp:2388+`). ✓
- Scrollbar theme (`theme.dart:81-103`): thumb thickness 4px (= `width 10px − 2·deltax 3px`,
  `widgets.style:824/826`, computed at `scroll_area.cpp:166`), radius 2px (`round: 2px`,
  `widgets.style:822`), and `barBg`→`barBgOver` brightening on hover/drag via
  `resolveWith` — matches `anim::color(barBg, barBgOver, (_overbar||_moving)?1.:0.)`
  (`scroll_area.cpp:289`; colors `#00000053`/`#0000007a`, `colors.palette:62-63`). ✓
- Tooltip theme (`theme.dart:104-115`): `tooltipBg`/`tooltipFg`/`tooltipBorderFg` 1px border,
  `padding (5,2,5,2)`, font 13px, radius 3px, 1000ms delay — match `defaultTooltip`
  (`widgets.style:1288`: `textPadding margins(5,2,5,2)`, `textStyle: defaultTextStyle`=13px
  `fsize`/`basic.style:51`), `roundRadiusSmall: 3px` used by `tooltip.cpp:172`/`basic.style:104`,
  and `Tooltip::Show(1000, ...)` (`tooltip.cpp:573`). ✓
- `colorScheme.onPrimary = activeButtonFg` (`theme.dart:38/47`): `defaultActiveButton.textFg:
  activeButtonFg` (`widgets.style:728`) = `windowFgActive` = `#ffffff` (`colors.palette:35/19`,
  `telegram_palette.dart:3051`). ✓
- Text slots (`theme.dart:122-156`): `letterSpacing: 0` and natural metrics correctly reflect
  that AyuGram `TextStyle` has no letter-spacing field (`basic.style:39-45`) and
  `defaultTextStyle.lineHeight: 0px` (`basic.style:84`). ✓

No placeholders, stubs, empty callbacks, TODO/FIXME, mock data, or broken wiring — all
values resolve from real `TelegramPalette` tokens (single source of truth) and the
`night`/`dayBlue` palettes + `isDark` are real implementations, not stubs.

# theme_file — `.tdesktop-theme`/`.tdesktop-palette` parser, exporter & theme cache

Audited `dart/lib/theme/theme_file.dart` (2214 lines) against AyuGram's
`window_theme.cpp`, `window_theme_editor.cpp`, `parse_helper.cpp/.h`,
`style_core_palette.cpp`, `colors.palette`, and `window_theme.h`.

**This file is an exceptionally faithful, complete port — verified mechanically:**
- All four size limits match exactly (5 MB theme / 1 MB scheme / 4 MB bg / 25 M-px bg).
- The comment stripper, whitespace/name tokenizer and `readNameAndValue` reproduce
  `base::parse::*` + `window_theme.cpp:122-164` 1:1 (incl. the four hard-reject errors).
- The 3-pass palette resolver faithfully mirrors `ReadPaletteValues` + `loadColorScheme`
  + `setColorSchemeValue` + `palette::setColor`/`compute`/`finalize`, including the
  Loaded/Created/Initial status semantics and bad-hex → Ok-skip behavior.
- `_paletteFallbacks` is an **exact 1:1 ordered diff** of all 236 references in
  `colors.palette` (verified: zero diff).
- `paletteToMap` covers **all 580** AyuGram palette keys (zero missing); the 5 extras
  are documented §57.11 synonyms. `paletteFromMap` has **zero** field/key/fallback
  mismatches (verified). All fallback keys & values exist in `paletteToMap`.
- Cloud-meta read/write, ZIP file-priority order, zip-bomb guard (`.size` from the zip
  directory before `.content` decompresses), and crc32/structure-checksum caching all
  match AyuGram's pipeline. `getCrc32` is correctly exported by `package:archive`.
- No stubs, TODOs, placeholders, empty callbacks, or fake data anywhere.

The two findings below were genuine deviations and are now both **fixed & verified**:

- Background is **forced opaque at parse time** (was item 2). `_parseZipTheme` runs the
  decoded background through `_decodeOpaqueBackground` (`theme_file.dart:414`), which
  composites any alpha-bearing image over opaque **white** and re-encodes it with no
  alpha — mirroring AyuGram's `Images::Read({.forceOpaque=true})` → `Ui::Images::Opaque`
  (composite over `QColor(Qt::white)`, guarded by `hasAlphaChannel()`;
  `image_prepare.cpp:1214-1233`, skip-for-jpeg at `:506`). Opaque/JPEG inputs pass
  through verbatim. The opaque bytes flow into `parsed.backgroundImage` → `buildThemeCache`
  → cache, so a transparent-PNG wallpaper no longer renders see-through.
  ← `window_theme.cpp:336-339`.
- The **redundant synchronous UI-thread decode on startup** is gone (was item 1).
  `loadThemeCache` (`theme_file.dart:2216-2231`) now reads the cached background bytes
  straight back without `img.decodeImage` — they were already decoded, size-checked and
  forced opaque when the cache was written, so re-decoding only validated-then-discarded
  while blocking `_loadWindowPrefs` at boot. Matches AyuGram's `InitializeFromCache`,
  which re-reads its cached background via `QImageReader` without re-running the
  size/forceOpaque checks. ← `window_theme.cpp:392-400`.

Verified (ralph Stage 2): behavioral tests confirmed transparent→white opaque output,
`hasAlpha==false` stored bytes, opaque pass-through, and a byte-identical cache
round-trip with no decode on load; app boots & renders in desktop+mobile with no THEME
errors. White composite target confirmed against `image_prepare.cpp:1219` (`QColor(Qt::white)`).

# wallpaper — chat-background renderer (solid/gradient/pattern/image, gift patterns)

Verified line-by-line against AyuGram C++ ground truth. Color/URL parsing
(`data_wall_paper.cpp`), complex + linear gradient generation + dither
(`image_prepare.cpp`), pattern tiling, gift-symbol parse/skip/stamp, average
color, pattern inversion, dark-mode dimming, blur, and JPEG preprocessing
(`chat_theme.cpp`) are all faithful ports. Default colors, dither tiers, URL
share params, and the complex-gradient rotation math all match exactly. No
stubs, placeholders, TODOs, fake data, or empty callbacks.

Verified (ralph Stage 2): the one behavioral gap — complex (3+ colour) pattern
wallpapers not rotating their underlying gradient on outgoing-message send — is
now FIXED and confirmed. `_PatternWallpaperState` mirrors `_RasterGradientState`:
subscribes to `ChatBackgroundRotator` when `backgroundColors.length >= 3`,
advances a doubled accumulator by `kAddRotationDoubled` (720-45), derives
rotation/progress via `ComputeRealRotation`/`ComputeRealProgress`, and cross-fades
the new phase in over 200ms (`kBackgroundFadeDuration`) under the static pattern
tile — values match AyuGram `chat_theme.cpp:30,40-57,643,646` exactly. Empirically
confirmed in BOTH desktop (1024×768) and mobile (400×720) with the default
4-colour pattern wallpaper (`background.tgv` + `kDefaultWallpaperColors`):
static-at-rest frame diff = 0.0, and on each outgoing send the entire fixed
background gradient shifts (broad smooth orange→magenta diff with the doodle
swirls visible inside it, bubbles/chat-list unchanged). No crashes or render errors.

# active_sessions_screen — Telegram "Active Sessions" settings (port of AyuGram `Settings::Sessions` + `SessionInfoBox` + `SelfDestructionBox`)

Backend wiring is fully real and field-accurate: `getSessions`/`terminateSession`/
`terminateAllOtherSessions`/`getSessionAutoTerminateDays`/`setSessionAutoTerminateDays`/
`setCustomDeviceModel` all reach live engine dispatch (`dispatch_engine.go:5079-5341`,
`cache_users.go:2208-2404`) → `telegram.go` `AccountGetAuthorizations`/`ResetAuthorization`/
`SetAuthorizationTTL`. `cores.Session` JSON keys (`base.go:611-625`) line up 1:1 with every
key the UI reads, and `last_active` carries the `date_active`→`date_created` fallback
(`telegram.go:31549-31552`) matching `ParseEntry` (`api_authorizations.cpp:72-74`). Device
classification (`_classifyDevice` 108-182) mirrors `TypeFromEntry` 1:1; gradients/icons,
section gating (`(incomplete+list)>0`, `list>0`, `list==0`), TTL options `[7,30,90,180,365]`
+ `DaysLabel`, box widths (info 364 = `boxWideWidth`, dialog 320 = `boxWidth`), row dims
(h84 / photo(21,10,42) / name(78,11) / status(78,32) / location top54 / terminate(34×34,
right11,top8)) and the info-box full date (`_formatFullDate` via MaterialLocalizations, shown
for the current session too) are all faithful. The findings below were localization/format
deviations from the lang.strings ground truth — flagged MAJOR per the bar set in
`audit_chunk_9.md`.

Verified (ralph Stage 2): all 9 MAJOR localization/format deviations are now FIXED
and confirmed. Every affected literal is routed through `TrStrings` (the file's
existing centralised-string layer) with values matching `lang.strings` 1:1 — app-bar
"Active sessions", "Terminate all other sessions", "Incomplete login attempts",
"IP address", "If inactive for..." (casing + ellipsis), "Official app", and all
section/row/about labels. `RenameBox` now renders the `lng_settings_device_name`
("Device name") subsection label above the input, and session-row dates use
locale-aware `DateFormat` (faithful port of `Authorizations::ActiveDateString`).
Confirmed live in BOTH desktop (1024×768) and mobile (400×720) under a Deutsch
locale: rows render "Mittwoch"/"Dienstag" + German short dates (16.5.2026), the
info box shows "Official app" and "Samstag, 16. Mai 2026", and the rename dialog
shows the "Device name" label. No crashes or render errors.

# admin_tools — channel/group/bot admin management (edit info & permissions, restrict/promote members, ownership transfer, admin log, invite links, member browser, statistics, boosts, monetization, affiliate programs)

15,794-line file spanning ~14 distinct admin screens/boxes, each diffed against its
AyuGram Desktop C++ counterpart. The overwhelming majority is faithfully ported and
fully engine-wired; the findings below are the verified CRITICAL/MAJOR deviations.
Several MAJOR items are UI elements wired to a Go-engine method that silently drops
or never emits the needed field — the Dart looks functional but the feature is dead;
per the audit rubric these are counted as broken-wiring defects (root cause in
`go/cores/telegram.go` is noted inline).

## EditPeerInfo box (structure, type / linked-discussion / history / topics dialogs)

- [ ] [MAJOR] History-visibility "Hidden" sub-text is hardcoded to the **legacy basic-group** string and never switches to the supergroup string. The Dart always shows "New members won't see more than 100 previous messages." (the legacy text), but AyuGram passes `isLegacy = _peer->isChat()` and uses `lng_manage_history_visibility_hidden_about` ("New members won't see earlier messages.") for supergroups, reserving the "…100 previous messages." string for legacy basic groups only. Since the Visible-History row is gated to non-broadcast peers (predominantly supergroups), the misleading text shows in the common case — `admin_tools.dart:1295` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_history_visibility_box.cpp:101`
- [ ] [MAJOR] "Create a new group" (discussion link) silently creates a megagroup with a hardcoded name instead of opening the interactive create-group box. `_createDiscussionGroup` directly calls `engine.createMegagroup(accountId, "<title> Chat", '')` with no UI, so the user cannot edit title/description/photo before creation. AyuGram opens `Box<GroupInfoBox>(navigation, Type::Megagroup, channel->name() + " Chat", …)` — the full create-group wizard whose creation callback then links the new group — `admin_tools.dart:1198` (invoked at `admin_tools.dart:1064`) ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_discussion_link_box.cpp:272`

## EditPeerInfo box (reactions / color / paid-messages dialogs + bot rows)

- [ ] [CRITICAL] Verify Accounts dialog is not wired to any backend — tapping a user calls `engine.callGeneric(accountId, 'BotsSetCustomVerification', {bot_id, peer_id, enabled})`, but the bridge has no generic-dispatch handler for that method (`bridge/dispatch_gen.go:19258` explicitly `// Skipped: BotsSetCustomVerification (complex external types)`; the typed `TelegramCore.BotsSetCustomVerification` at `telegram.go:25841` needs a pre-serialized `tg.BotsSetCustomVerificationRequest`, unreachable from a JSON map). Every tap falls through to `unknown engine method` (`bridge/dispatch_engine.go:7393`) and throws — the dialog renders rows, checkmarks and optimistic state but can never grant/revoke verification — `admin_tools.dart:2577` (row at `admin_tools.dart:2135`) ← `AyuGram/Telegram/SourceFiles/boxes/peers/verify_peers_box.cpp:58`
- [ ] [MAJOR] Verify Accounts sends the action immediately on row tap with no confirmation and no custom-description input. AyuGram routes every tap through a `ConfirmBox` (`confirmAdd`/`confirmRemove`) and, when `verifierSettings->canModifyDescription`, shows an editable description field passed as `custom_description` to Setup — the Dart omits both — `admin_tools.dart:2573` ← `AyuGram/Telegram/SourceFiles/boxes/peers/verify_peers_box.cpp:103`
- [ ] [MAJOR] Verify Accounts candidate list is the wrong scope — populated from `engine.getContacts(...)` (mutual user contacts only), but AyuGram lists ALL chats including channels (`createRow`: `peer->isUser() || peer->isChannel()`) via `ChatsListBoxController`, so non-contact users and channels (which are verifiable) cannot be selected — `admin_tools.dart:2467` ← `AyuGram/Telegram/SourceFiles/boxes/peers/verify_peers_box.cpp:231`
- [ ] [MAJOR] Reactions dialog uses an inverted group/broadcast control structure. AyuGram's `EditAllowedReactionsBox` shows the All/Some/None radios ONLY for groups (`addOption` early-returns when `!isGroup`) and a single enable-reactions toggle for broadcast channels; the max-count slider + paid toggle live under the broadcast branch. The Dart renders the 3 radios for ALL peer types and conditions only the slider/paid extras on `_isChannel`, so a broadcast channel gets radios it shouldn't and a group's layout diverges from AyuGram — `admin_tools.dart:1521` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_reactions.cpp:705`

## EditPeerInfo box (group/channel manage rows)

- [ ] [MAJOR] Manage-section rows are not gated by AyuGram's per-row capability checks. `_buildAdminControlsSection` renders Reactions, Permissions, Invite Links, Administrators and Members/Subscribers unconditionally, whereas AyuGram gates each: Reactions by `canEditReactions()`, Permissions by `canEditPermissions`, Invite Links by `canHaveInviteLink()`, Administrators by `canViewAdmins()`, Members by `canViewMembers()`. An admin with a partial right set (e.g. BanUsers-only) sees rows they cannot use. The needed flags (`_amCreator`, `_hasAdminRights`, `_adminCanChangeInfo`) are already loaded but unused for these rows — `admin_tools.dart:2657` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_info_box.cpp:1512`

## EditRestricted box (ban / restrict member)

- [ ] [MAJOR] Media master-toggle has inverted display and click behavior in the partial state. AyuGram sets the group toggle ON when **any** sub-flag is allowed (`checkView->setChecked(count > 0)`) and a click inverts that and applies to all inner flags — so 3/9 allowed reads ON and a click bans all. The Dart sets it ON only when **all** are allowed (`value: allowedCount == total`) and on click does `f.banned = !val`, so 3/9 allowed reads OFF and a click *allows* all — opposite display and opposite bulk action — `admin_tools.dart:5185` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_permissions_box.cpp:453`
- [ ] [MAJOR] The `edit_rank` ("Edit own tag") restriction is hardcoded `locked: true`, so the user can never toggle it and it is always sent as unbanned. In AyuGram this is a normal toggleable restriction checkbox in the user-specific restriction list (`{ Flag::EditRank, lng_rights_group_edit_rank_single }`) and is part of the serialized set (`NegateRestrictions` includes `Flag::EditRank`) — `admin_tools.dart:4690` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_permissions_box.cpp:99`

## EditAdmin box (promote admin + transfer ownership)

- [ ] [MAJOR] The "Edit member tags" / Manage-Ranks admin right is non-functional on save. The toggle (`_AdminFlag(key: 'manage_ranks')`) sends `rights['manage_ranks']` through the whole stack (engine_service → dispatch_engine → engine.AdminRights → cache_users), but the Telegram core's `PromoteAdminWithRights` builds `tg.ChatAdminRights{…}` without ever reading `rights["manage_ranks"]`, so the `ManageRanks` bit (which exists on `tg.ChatAdminRights`) is silently dropped. AyuGram includes ManageRanks in the megagroup `defaultRights()` and saved bitmask — `admin_tools.dart:5773` (save at `admin_tools.dart:5859`) ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participant_box.cpp:327` (root cause `go/cores/telegram.go:14562`)

## BotStarRefSetup screen (affiliate program setup)

- [ ] [MAJOR] An existing program's **duration is never pre-filled** — `_load()` reads `_durationMonths` from `getFullChatInfo()['star_ref_program']['duration_months']`, but the Go core emits no `star_ref_program` field anywhere (`GetBotManageInfo` returns only `starref_commission`, no duration). So for a bot that already has a program the duration slider always initializes to the hardcoded default 12 months, and because the irreversibility floor `_origDurationMonths` is then also 12, a longer/forever program can be silently *shortened* to 12 — violating the "can only increase duration" rule. AyuGram loads it from `state.program.durationMonths` via `ValueForDurationMonths` — `admin_tools.dart:4299` ← `AyuGram/Telegram/SourceFiles/info/bot/starref/info_bot_starref_setup_widget.cpp:679` (`info_bot_starref_common.cpp:95`)
- [ ] [MAJOR] Ended-program 24h-cooldown state missing. AyuGram defines `exists = (commission>0) && !endDate` and `MakeStartButton` renders the Start button **disabled with a live "available in {time}" countdown sublabel** while `endDate > now`. The Dart Start/Update button is only disabled while `_saving`, has no `endDate`/cooldown handling and no sublabel (the Go core never exposes `end_date`), so after ending a program the screen offers "Start Program" as immediately clickable — `admin_tools.dart:4572` ← `AyuGram/Telegram/SourceFiles/info/bot/starref/info_bot_starref_setup_widget.cpp:529`

## InviteLinks (manage box, link info, create/edit form, QR)

- [ ] [MAJOR] Revoking a link skips the confirmation dialog AyuGram always shows. `_revokeLink` calls `engine.revokeChatInviteLink` directly from all three entry points (regular-row menu, permanent-link menu, info-box Revoke button). AyuGram routes every revoke through `RevokeLinkBox` → `Ui::MakeConfirmBox` (permanent links regenerate, invalidating the old URL for everyone), so the missing confirm is a real destructive-action gap — `admin_tools.dart:8576` (also invoked at `:8657`, `:8713`, `:8887`) ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_invite_link.cpp:449`
- [ ] [MAJOR] Deleting a single revoked link skips its confirmation dialog. `_deleteLink` calls `engine.deleteRevokedChatInviteLink` directly from the revoked-row menu, the info-box Delete button, and `_showLinkInfo`. AyuGram routes single-delete through `DeleteLinkBox` → `Ui::MakeConfirmBox({ lng_group_invite_delete_sure })`. (The separate Delete-All path *does* confirm — an internal inconsistency too.) — `admin_tools.dart:8588` (also invoked at `:8659`, `:8715`) ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_invite_link.cpp:457`

## MessageStats + Boosts screens

- [ ] [MAJOR] Real-user booster avatars never render their actual profile photo — the engine `GetBoostsListJSON` never emits an `avatar_b64` for booster rows (only name/user_id/date/expires/flags), so `_BoosterRow` always falls through to the letter-placeholder `_emptyUserpic`. AyuGram renders the real peer userpic for non-special boosters via `generatePaintUserpicCallback`, so booster avatar attribution is broken for real users — `admin_tools.dart:13872` ← `AyuGram/Telegram/SourceFiles/info/statistics/info_statistics_list_controllers.cpp:507` (root cause `go/cores/telegram.go:19113`)

## Monetization screen (channel/bot earn — TON + stars)

- [ ] [MAJOR] Stars→USD conversion divides by an extra 1000, understating every Stars USD figure ~1000×. AyuGram converts credits to USD as `value() * rate` where `CreditsAmount::value()` for stars = the whole star count (`_whole + _nano/1e9`), i.e. `stars * usd_rate` with NO `/1000`. Both AyuGram (`api_credits.cpp:301`) and the Go engine (`telegram.go:22775`) carry the SAME raw TL `usd_rate`. The Dart `_fmtUsd` instead computes `stars * usdRate / 1000`, so every Stars USD figure (overview rows, Stars transaction context) is 1000× too small. (The TON path at `admin_tools.dart:14141`, `(nanotons/1e9) * rate`, is correct.) — `admin_tools.dart:14334` ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/earn/earn_format.cpp:81` (used at `info_channel_earn_list.cpp:407`)

## Sections audited — no CRITICAL/MAJOR issues

These components were diffed against their AyuGram sources end-to-end (UI → engine_service → Go core) and verified faithful and fully wired:

- **EditPeerPermissions box** (default member rights) — full flag set, media sub-group with master toggle, slowmode (8 values), boosts-unrestrict (1–5), charge-stars slider, flag interdependencies, locked-state logic, and all 5 engine round-trips match `edit_peer_permissions_box.cpp`.
- **AdminLog screen** (recent actions + filter) — all 53 `GenerateItems` event-type phrases present, `getAdminLogEvents` wired with query/maxId/filter/admins, debounced search, scroll pagination, `ListView.builder`, actor-name→profile click, filter dialog mirrors AyuGram's 3 sections + per-admin selector (`history_admin_log_item.cpp`, `history_admin_log_filter.cpp`, `history_admin_log_inner.cpp`).
- **MemberList screen** (members/admins/banned/restricted/requests + picker) — per-role RPC filters, add/remove/ban/unban, join-request approve/dismiss, anti-spam header gating, contact+global picker search order, per-role context menus, `ListView.builder` + pagination (`edit_participants_box.cpp`, `add_participants_box.cpp`, `edit_peer_requests_box.cpp`).
- **Statistics screen** (overview + charts + recent posts) — real MTProto data (no fakes), all 12 channel / 8 group charts, series toggle, crosshair tooltip, draggable range-footer, server zoom, growth-badge formula, `ListView.builder` + `RepaintBoundary` (`info_statistics_inner_widget.cpp`, `chart_widget.cpp`, `api_statistics.cpp`).
- **StarRefJoin screen** (join other bots' programs) — connected + suggested lists fetched & paginated, 3 sort orders, join-confirmation box before connect, revoke/leave, copy/share, commission/duration from data, `ListView.builder` (`info_bot_starref_join_widget.cpp`, `info_bot_starref_common.cpp`).

# advanced_settings_screen — Advanced settings page + sub-dialogs (proxy, local storage, power saving, auto-download, dictionaries, recent downloads, experimental)

Audited `dart/lib/ui/advanced_settings_screen.dart` (5262 lines) against AyuGram `settings/sections/settings_advanced.cpp`, `settings/settings_power_saving.cpp`, `boxes/connection_box.cpp`, `boxes/local_storage_box.cpp`, `settings/settings_experimental.cpp`, and `boxes/peers/edit_peer_permissions_box.cpp` (the shared flag-editing widget). The port is largely faithful — section ordering, platform gating, the size/limit math, the experimental flag set/order, the MTProto secret validator, clipboard import, and all engine wiring (GetCacheSizesByTag, ClearCacheByTag, CheckProxy, SetExperimentalFlag) are correct and real (not stubs). Findings below are the genuine structural/behavioral/label deviations.

## Power Saving box (`PowerSavingBox`)

- [ ] [CRITICAL] Collapsible nested-group structure is entirely missing. AyuGram's `PowerSavingLabels` returns 3 groups WITH a `nestingLabel` (Stickers/Emoji/Chat) and 2 WITHOUT (Calls/Animations); `CreateEditFlags` renders any group that has a `nestingLabel` as a collapsible **parent toggle** via `AddInnerToggle` — a `SettingsButton` carrying the group's icon, a bold "checked/total" count badge (e.g. "Animated Stickers  1/2"), an expand/collapse arrow, and a master switch reflecting "any child checked"; its children live HIDDEN in a `SlideWrap` and render as `Ui::Checkbox` rows shown only when expanded. The Dart instead renders Stickers/Emoji/Chat as flat static text headers (`_header`) with every child permanently visible as an individual `Switch` row, no count badge, no expand arrow, and puts the group icon on the first child instead of a parent row. The whole nested-collapsible interaction model is absent. — `advanced_settings_screen.dart:2752-2788` ← `boxes/peers/edit_peer_permissions_box.cpp:724-763` (AddInnerToggle:366-495) + `settings/settings_power_saving.cpp:183-189`

- [ ] [MAJOR] Group header labels wrong: "Stickers"/"Emoji"/"Chat" should be "Animated Stickers"/"Animated Emoji"/"Animations in Chats". — `advanced_settings_screen.dart:2758,2764,2774` ← `settings/settings_power_saving.cpp:184-186` (lang.strings:930,933,938)

- [ ] [MAJOR] Toggle label "Stickers in Panel" wrong — AyuGram `lng_settings_power_stickers_panel` = "Autoplay in panel". — `advanced_settings_screen.dart:2759` ← `settings/settings_power_saving.cpp:145` (lang.strings:931)

- [ ] [MAJOR] Toggle label "Stickers in Messages" wrong — should be "Autoplay in chat". — `advanced_settings_screen.dart:2761` ← `settings/settings_power_saving.cpp:148` (lang.strings:932)

- [ ] [MAJOR] Toggle label "Emoji in Panel" wrong — should be "Autoplay in panel". — `advanced_settings_screen.dart:2765` ← `settings/settings_power_saving.cpp:153` (lang.strings:934)

- [ ] [MAJOR] Toggle label "Emoji Reactions" wrong — should be "Autoplay in reactions menu". — `advanced_settings_screen.dart:2767` ← `settings/settings_power_saving.cpp:156` (lang.strings:935)

- [ ] [MAJOR] Toggle label "Emoji in Messages" wrong — should be "Autoplay in messages". — `advanced_settings_screen.dart:2769` ← `settings/settings_power_saving.cpp:157` (lang.strings:936)

- [ ] [MAJOR] Toggle label "Emoji Status" wrong — should be "Autoplay in premium status". — `advanced_settings_screen.dart:2771` ← `settings/settings_power_saving.cpp:158` (lang.strings:937)

- [ ] [MAJOR] Toggle label "Chat Background" wrong — should be "Wallpaper rotation". — `advanced_settings_screen.dart:2775` ← `settings/settings_power_saving.cpp:163` (lang.strings:939)

- [ ] [MAJOR] Toggle label "Spoiler Effect" wrong — should be "Animated spoiler effect". — `advanced_settings_screen.dart:2777` ← `settings/settings_power_saving.cpp:166` (lang.strings:940)

- [ ] [MAJOR] Toggle label "Message Effects" wrong — should be "Effects in messages". — `advanced_settings_screen.dart:2779` ← `settings/settings_power_saving.cpp:167` (lang.strings:941)

- [ ] [MAJOR] Toggle label "Calls" wrong — AyuGram `lng_settings_power_calls` = "Animations in Calls". — `advanced_settings_screen.dart:2782` ← `settings/settings_power_saving.cpp:172` (lang.strings:942)

## Connection type / Proxy box (`_ProxiesBox`, `_EditProxyDialog`)

- [ ] [MAJOR] MTPROTO secret (and HTTP/SOCKS5 password-without-username) is never validated on save. The Dart `_save()` only checks host non-empty and port 1–65535, then accepts any secret — including empty or malformed — silently producing a non-functional proxy. AyuGram `collectData()` rejects `type==Mtproto && !valid()` (showError on secret) and rejects HTTP/SOCKS5 password-with-empty-user. The Dart already ports the full `_mtprotoSecretStatus` validator (used for clipboard import) but never calls it here. — `advanced_settings_screen.dart:4176-4191` ← `boxes/connection_box.cpp:1439-1465`

- [ ] [MAJOR] List-row ping gating is inverted, and declining fabricates fake status. AyuGram pings every list row unconditionally (`refreshChecker` → `MTP::StartProxyCheck`, no confirmation) on open/add/edit; the `checkIpWarningShown()` gate lives only in the separate `ShowApplyConfirmation` flow (the apply-from-link table's manual "Check Status" link). The Dart instead gates ALL list-row checks behind a one-time IP-exposure dialog and, when declined, fabricates every proxy's status as `Available` with `pingMs=0` (showing fake "Available" data for unchecked proxies). The justification comment citing `connection_box.cpp:1824-1842` is misapplied — those lines are in `ShowApplyConfirmation`, not the list. — `advanced_settings_screen.dart:3098-3153` (fake status 3128-3137) ← `boxes/connection_box.cpp:1894-1917` (gate at 1826 is in 1652-1842)

- [ ] [MAJOR] Box title wrong: "Connection type" should be "Proxy settings" (`lng_proxy_settings`). — `advanced_settings_screen.dart:3306` ← `boxes/connection_box.cpp:978` (lang.strings:1237)

- [ ] [MAJOR] Radio mode labels wrong: "Disabled" → "Disable proxy"; "Use system settings" → "Use system proxy settings" ("Use custom proxy" matches). — `advanced_settings_screen.dart:3376-3378` ← `boxes/connection_box.cpp:1058,1065` (lang.strings:1238-1240)

- [ ] [MAJOR] Rotation toggle label wrong + missing helper text: "Rotate proxies" should be "Auto-switch proxies" (`lng_proxy_auto_switch`), and AyuGram renders an `lng_proxy_auto_switch_about` divider label ("You can choose how quickly the app should auto-connect…") that the Dart omits. — `advanced_settings_screen.dart:3401,3416-3439` ← `boxes/connection_box.cpp:1096` (lang.strings:1242-1243)

- [ ] [MAJOR] Proxy status labels + ping format deviate. AyuGram: "online"/"connecting…"/"checking…"/"not available", and available = "available (ping: {ping} ms)". Dart: "Online"/"Connecting..."/"Checking..."/"Unavailable" and bare "{X} ms". The "Unavailable"→"not available" change and the ping wording are material (casing aside). — `advanced_settings_screen.dart:3607-3613` ← `boxes/connection_box.cpp:787-804` (lang.strings:1249-1253)

- [ ] [MAJOR] Empty-list text wrong: "You have no saved proxies yet." should be "Your saved proxy list will be here." (`lng_proxy_description`). — `advanced_settings_screen.dart:3482` ← `boxes/connection_box.cpp:1307` (lang.strings:1265)

- [ ] [MAJOR] Top-menu item label wrong: "Import from clipboard" should be "Add proxy from clipboard" (`lng_proxy_add_from_clipboard`). — `advanced_settings_screen.dart:3323` ← `boxes/connection_box.cpp:1015` (lang.strings:1269)

- [ ] [MAJOR] Edit dialog omits AyuGram's section labels: "Socket address" (`lng_proxy_address_label`) above host/port, "Credentials (optional)" above SOCKS5/HTTP user+pass, and "Credentials" above the MTPROTO secret. The Dart shows none of these and instead bakes "(optional)" into the field hints, whereas AyuGram field placeholders are plain "Username"/"Password"/"Secret". — `advanced_settings_screen.dart:4241-4358` ← `boxes/connection_box.cpp:1494,1527,1560` (lang.strings:1262-1264)

## Connection type row (Data and Storage)

- [ ] [MAJOR] Connection-type right-label invents states and hardcodes the transport. The Dart builds labels from `proxyMode` + a `ConnState` enum, emitting "Connected via TCP" / "Connection unstable" / "Waiting for network…" — but AyuGram derives the label from `proxy().isEnabled()` + the real MTProto transport string and emits "Default ({transport} used)" (`lng_connection_auto`) / "Connecting through proxy…" (`lng_connection_proxy_connecting`) etc. The "unstable"/"waiting" states have no AyuGram equivalent and the non-proxy label hardcodes "TCP" rather than the actual transport. — `advanced_settings_screen.dart:180-204` ← `settings/sections/settings_advanced.cpp:106-117` (lang.strings:1226-1227)

## Experimental Settings box (`ExperimentalSettingsBox`)

- [ ] [MAJOR] `gnotification` restart-required marking wrong — Dart marks `restartRequired: false`, but AyuGram defines `OptionGNotification` with `.restartRequired = true`, so the Dart fails to arm the restart confirm when this flag changes. — `advanced_settings_screen.dart:4869` ← `window/notifications_manager.cpp:174` (registered `settings/settings_experimental.cpp:299`)

- [ ] [MAJOR] `touchbar-disabled` restart-required marking wrong — Dart marks `restartRequired: false`, but AyuGram defines `OptionDisableTouchbar` with `.restartRequired = true`. — `advanced_settings_screen.dart:4884` ← `window/main_window.cpp:99` (registered `settings/settings_experimental.cpp:309`)

- [ ] [MAJOR] No platform `scope`/`relevant()` gating — the Dart shows all flags on every platform (only `fast-buttons-mode` is gated). AyuGram greys out / hides platform-irrelevant options, so e.g. a Linux user is shown Windows/macOS-only toggles (`webview-legacy-edge`, `touchbar-disabled`, `freetype`, `gnotification`, `custom-notification`, `high-dpi-downscale`, `fractional-scaling-enabled`) as if active. — `advanced_settings_screen.dart:4837-4926` ← `settings/settings_experimental.cpp:284-314`

## Local Storage box (`_LocalStorageBox`)

- [ ] [MAJOR] "Keep media" slider max position is hardcoded "Forever", but AyuGram displays "Never" for the no-time-limit position (`TimeLimitText` → `lng_local_storage_limit_never` = "Never"). — `advanced_settings_screen.dart:1949` ← `boxes/local_storage_box.cpp:111` (lang.strings:1147)

# auth_screen — Telegram intro flow (choose / qr / phone / email / code / 2FA / signup)

Audited `dart/lib/ui/auth_screen.dart` against AyuGram `intro/` (intro_widget,
intro_step, intro_phone, intro_code, intro_code_input, intro_password_check,
intro_signup, intro_qr, intro_email + intro.style).

The port is dimensionally faithful — cover height 208, OTP cells 40×50 / 4px
border / 10px gap / 20px font / 6px(boxRadius) radius, shake constants
(shift 4 / dur 300 / 6-segment pattern), 2FA field offsets 74/96/151/220, next
button 300×42 r6, QR token payload `tg://login?token=<base64url>`, hasBack per
step, and the call-status / login-code / no-telegram-code flows all match. The
issues below are a soft-keyboard wiring bug and a cluster of strings that bypass
the cloud lang pack the rest of the screen uses.

- [ ] [CRITICAL] OTP soft-keyboard / IME entry submits a garbage code: `updateEditingValue` treats the platform's **complete** `TextEditingValue.text` as freshly-typed input and re-inserts every digit through `_insertDigit` on each update, while `setEditingState` is never called to resync the platform buffer to `_digits`. So a soft keyboard (mobile mode — mandated) that reports its growing buffer "1" → "12" → "123" makes the widget append "1","1"+"2","1"+"2"+"3"… producing duplicated/out-of-order digits and auto-submitting a wrong code. AyuGram's `inputMethodEvent` processes only the just-committed delta (`e->commitString()`), one `processDigit` per new char. — `auth_screen.dart:2184-2191` (and never-called `setEditingState`, `auth_screen.dart:1946`) ← `intro/intro_code_input.cpp:363-371`

- [ ] [MAJOR] 2FA password/recovery error text and hint are hardcoded English, bypassing the cloud lang pack used everywhere else on the screen, so a non-English session shows mixed languages. `_mapAuthError` returns literal strings ("Wrong password, try again.", "Invalid code. Please try again.", "Too many attempts…") and the hint is built as `'Hint: ${data.hint}'`. AyuGram localizes all of these: `tr::lng_signin_bad_password`, `tr::lng_signin_wrong_code`, `tr::lng_flood_error`, and `tr::lng_signin_hint`. — `auth_screen.dart:885-911`, `auth_screen.dart:834` ← `intro/intro_password_check.cpp:151,264,142,61-64`

- [ ] [MAJOR] Email-setup error messages are hardcoded English instead of the lang pack. `_mapEmailError` returns literal "This email address is not allowed." / "Please enter a valid email address." / "Email confirmation expired." / "Too many attempts…". AyuGram uses `tr::lng_settings_error_email_not_alowed`, `tr::lng_cloud_password_bad_email`, `Lang::Hard::EmailConfirmationExpired`, `tr::lng_flood_error`. — `auth_screen.dart:1115-1128` ← `intro/intro_email.cpp:111-122`

- [ ] [MAJOR] Phone-step error text and the banned dialog are hardcoded English, not lang-pack sourced. The inline "Invalid phone number. Please check and try again." / "Too many attempts…" labels and the entire `_showBannedDialog` body are literals. AyuGram emits `tr::lng_bad_phone` / `tr::lng_flood_error` and routes banned numbers through the localized `Ui::ShowPhoneBannedError` box. — `auth_screen.dart:1592,1609-1610,1689-1711` ← `intro/intro_phone.cpp:178,271,283`

- [ ] [MAJOR] The persistent next-button label bypasses the lang pack for two states: Fragment delivery returns the literal `'Open Fragment'` and the 2FA step returns `TrStrings.lngIntroSubmit()` which is a hardcoded-English fallback class (`strings.dart:10` → `'Submit'`, comment: "Replace with server-sourced language packs"). AyuGram drives both from the cloud pack: `tr::lng_intro_fragment_button` and `tr::lng_intro_submit`. — `auth_screen.dart:322,328` ← `intro/intro_code.cpp:428`, `intro/intro_password_check.cpp:405-407`

- [ ] [MAJOR] The intro language switcher uses a hardcoded 19-entry list and a hardcoded English "Change Language" label, instead of cloud-sourced language data. `_LanguagePickerDialog._languages` is a static 19-language tuple list (Telegram serves ~60+ via `langpack.getLanguages`), and the bottom-bar trigger text is the literal `'Change Language'`. AyuGram's intro switch link is built from the cloud (`Lang::GetOriginalValue(tr::lng_switch_to_this…)`, fetched via `MTPlangpack_GetStrings`) and is shown conditionally on a suggested/non-default language. — `auth_screen.dart:2619-2639,2581` ← `intro/intro_widget.cpp:267-308`

# ayu_appearance_page — AyuGram Appearance settings (icon picker, avatar corners, mono font, tray/drawer elements)

Overall this is a faithful, fully-wired port of `settings_appearance.cpp`. Verified correct:
section order & elements all present; icon picker (4 cols, 64px icon, 68px selected box,
12px rounding, 200ms easeOutCubic, live apply via native `updateAppIcon` channel) matches
`icon_picker.cpp`; avatar radius formula `corners/23 * size/2` is linear and matches
`ayu_userpic.cpp:37` exactly with `kMaxAvatarCorners=23` and default 23 (circle); preview loads
the real @AyuGramReleases avatar via `resolveUsername`+`downloadSingleAvatar` with a shape-aware
empty fallback (`EmptyUserpic::paintCircle`→`AyuUserpic::PaintShape`, empty_userpic.cpp:341-349);
preview indent 22/name 80/height 62/top-margin 2 match `defaultDialogRow`+`settingsButtonNoIcon`;
mono-font loads real system fonts and persists with a restart prompt matching `ShowRestartPrompt`;
all toggles call real `AppState` setters that persist via `_saveWindowPrefs()`; the Bots drawer
toggle is gated on a real `getMainMenuBots` engine call (mirrors `HasDrawerBots`). Findings below.

- [ ] [MAJOR] Font-selector keyboard navigation + Enter-to-activate are dead in the normal flow: the search `TextField` has `autofocus: true` so it holds primary focus, but the `_onKeyEvent` handler is attached to a `Focus` that wraps only the sibling `ListView`, so Arrow/PageUp/PageDown keys fire on the search field and never reach `_onKeyEvent` (the nav code at lines 717-750 is unreachable while searching), and the field has no `onSubmitted` so Enter never selects. AyuGram handles Up/Down/PageUp/PageDown and submit globally regardless of search focus. — `ayu_appearance_page.dart:982` (+943, +717-750) ← `AyuGram/ayu/ui/boxes/font_selector.cpp:967` (keyPressEvent) & `:928` (setSubmittedCallback→activateBySubmit)

- [ ] [MAJOR] Every toggle renders an invented two-line `subtitle:` description that AyuGram does not have, roughly doubling each row's height and changing the page's information density vs the 1:1 source. In AyuGram the appearance/folder/tray/drawer toggles use only `.title` (descriptions exist solely as separate `addDividerText` blocks for `hideNotificationBadge` and `singleCornerRadius`). Affects ~15 rows (appearance group lines 76/83/90; folders 107/113; tray 124/131; drawer 142/150/157/164/171/178/185/192/199/206/213/221). Likely an app-wide design choice — flagged as a deviation from ground truth for the paper trail. — `ayu_appearance_page.dart:76` ← `AyuGram/ayu/ui/settings/settings_appearance.cpp:193` (materialSwitches toggle, title-only) ; `ayu_appearance_page.dart:142` ← `AyuGram/ayu/ui/settings/settings_appearance.cpp:282` (drawer toggles, title+icon only, no subtitle)

# ayu_filters_page — AyuGram regex/shadow-ban filters settings page

Audited against AyuGram `ayu/ui/settings/settings_filters.cpp`, `ayu/ui/settings/filters/{settings_filters_list,edit_filter,per_dialog_filter}.cpp`, `ayu/ui/boxes/import_filters_box.cpp`, `ayu/features/filters/filters_utils.cpp`, and `info/info_wrap_widget.cpp`. The page is overwhelmingly faithful and fully wired to the real `AyuFilterEngine` + `AppState` (toggles call `rebuildCache()` + persist; CRUD/import/export/publish/regex-validation all hit real backend code, matching the C++ 1:1). One genuine data-flow gap found.

- [ ] [MAJOR] Export `peers` hint map omits group/channel dialogs. `_resolvePeerUsernames` finds the target chat in the already-loaded `chatState.chats` but then **discards `chat.username`** and instead calls the users-only `getUserProfile(accountId, dId)`. `engine.GetUserProfile` resolves only users/bots via `GetFullUser`/`GetOrFetchUser` (`go/engine/cache_users.go:7519-7534`), so for group/channel dialog ids (negative — the predominant Select-Chat targets, which exclude user DMs) it returns null and the peer is left out of the exported `peers` object. AyuGram's `exportFilters` resolves **every** loaded peer via `LoadedPeerFromDialogId` (user *and* channel *and* chat) and writes `peer->username()`, so a per-dialog filter on a public channel/group exports its username for cross-device re-resolution. The Dart already has that username in hand (`ChatInfo.username`, populated for channels at `go/cores/telegram.go:18719` and persisted at `go/engine/cache_chats.go:69,263,365`) — it just routes through the wrong resolver. Result: per-dialog filters on groups/channels export with no peer hint, so they don't auto-resolve their target on import to another device. — `ayu_filters_page.dart:1938` (ignored field at `:1934-1935`) ← `AyuGram/ayu/features/filters/filters_utils.cpp:511-524` (LoadedPeerFromDialogId `:517`, `peer->username()` `:518`)

## Verified correct (no action)

- Toggles (Enable / Enable Shared in Chats / Hide from Blocked) → `setFiltersEnabled` etc. each do `rebuildCache()` + `notifyListeners()` + persist, matching `FiltersCacheController::rebuildCache()`+`fireUpdate()` (`settings_filters.cpp:52-102`, `app_state.dart:2256-2276`).
- "…" menu order Select Chat → sep → Import → (Export iff `hasFilters`) → sep → Clear All matches `fillTopBarMenu` (`settings_filters.cpp:193-258`).
- App-bar icons: Add (+) on every list screen → shadow-ban Select-Chat (Bot|User) vs `RegexEditBox(null,null,dialogId)`; Exclude icon only in per-dialog main view (`showExclude==true`). Matches `info_wrap_widget.cpp:467-513`.
- Filter row context menu (Edit / Enable-Disable / Delete), exclusion row (Delete only), pick-exclude tap→add exclusion, all match `settings_filters_list.cpp:97-200`. `deleteFilter` also drops exclusions-by-filter-id (`ayu_filter.dart:790-795`) per `:132-133`.
- RegexEditBox: title Add/Edit, checkbox defaults (enabled/caseInsensitive=true, reversed=false) + order, empty-text no-op, dialogId scoping `if (!showToast && dialogId)`, no settings-flow toast — match `edit_filter.cpp:127-261`. UUID id format matches `generate_uuid_bytes`/`ParseFilterId`.
- Import/Export box: clipboard-URL autodetect, URL field import-only, change-summary order (new→removed→updated filters, new→removed exclusions, dialogs) + confirm dialog, `publishFilters` dpaste POST (content/syntax/title, no-redirect, Location+".txt"), preview/apply diff logic — match `import_filters_box.cpp` + `filters_utils.cpp:61-138,344-433,701-910`.
- Per-dialog status text ("{n} filter[s]", "{n} excluded"), "UNKNOWN (ID: …)" fallback, userpic-color remap — match `per_dialog_filter.cpp:35-117` + `lang.strings:8147-8150`.

Skipped (minor/cosmetic): Select-Chat picker also lists forum topics (C++ Bot|Group|Broadcast only); empty-state and Clear-All wording differ from `ayu_RegexFiltersListEmpty`/`ayu_FiltersClearPopupText`.

# ayu_other_page — AyuGram "Other" settings (donations, support box, crash reporting, reset)

Scope checked: §Support donations (Boosty + 5 crypto QR), support/donate-info box,
crash-reporting toggle, register-URL-scheme + reset-settings actions, donate QR box.

Backend wiring verified **REAL** — no stubs/placeholders/fake feedback:
- Crypto buttons → real `_DonateQrBox` (`QrImageView`) and `_showDonateInfoBox`; Boosty → real `launchUrl`.
- Crash toggle → `appState.setCrashReporting` → `Debug.crashReportingEnabled`, which genuinely
  gates crash-log file writing (`utils/debug.dart:23`) — not a dead bool.
- Reset → `appState.resetAyuSettings()` (resets dozens of real fields).
- Donate amounts/username → `RcManager` (real live HTTP fetch, AyuGram's exact endpoints + defaults).
- Username link → `engine.resolveUsername` (real FFI), with external-link fallback.
- URL-scheme registration → real per-platform `Process.run`/`.desktop`/`reg` writes.

Text verified 1:1 against `Telegram/Resources/langs/lang.strings` (support-box strings,
reset confirmation, `lng_chat_link_copy`="Copy", `lng_group_invite_context_qr`="Get QR Code",
`lng_text_copied`). Dimensions faithfully ported (429=aboutWidth×1.1, 487=aboutWidth×1.25,
kCenterRatio 0.20, icon-bg 0xEEEEEE/0x242B2C).

- [ ] [MAJOR] Crash-reporting description loses its divider-text band. AyuGram renders the
  description text **on** a full-bleed `boxDividerBg` band via `builder.addDividerText(...)`
  (→ `Ui::AddDividerText`/`DividerLabel`) and then opens the actions block with a plain
  `builder.addSkip()` — **no** separate divider. The Dart instead renders the text with
  `b.addDescription(...)` (plain `Padding`+`Text`, transparent bg — see `ayu_section_builder.dart:178`)
  and then inserts an **extra** empty `b.addSectionDivider()` (6px skip + 8px band + 6px skip).
  Net result: the gray band is empty and sits *below* the text instead of containing it, and an
  8px band exists that AyuGram has nowhere here. This is also internally inconsistent — the sibling
  Support description directly above (`_SupportDescription`, line 91/470) *is* correctly on a
  `boxDividerBg` band, matching `AddDividerText`. — `ayu_other_page.dart:110-115` ← `ayu/ui/settings/settings_other.cpp:192,199`

# birthday_picker — Telegram day/month/year drum-wheel birthday dialog (port of `EditBirthdayBox` + `VerticalDrumPicker`)

Overall this is a faithful, well-wired port. Verified correct against AyuGram source:
dimensions (`viewportHeight 200` / `itemHeight 40` ← `settings.style:681-682`, `bandBorder 2` ←
`defaultInputField.borderActive 2px` widgets.style:1064, `minYear 1875` ← `data_birthday.h:33`,
`fadeWrapDuration 200ms` ← `basic.style:97`, item font 14px ← `boxTextFont`); item text color
(`windowFg` ← `defaultFlatLabel.textFg`) and band color (`activeLineFg`); wheel/keyboard/drag
directions, snap-to-nearest, jump accumulation, leap-year/month-cap/day-cap data logic, max-birthday
serialize comparison, Save result mapping, Remove-button visibility; all button labels match the
English baseline exactly (`Cancel`/`Save`/`Remove`/`Suggest`); month names localized via
`lng_month{n}` (← `Lang::Month`). Both callers (`my_profile_page.dart:296,306`,
`contacts_screen.dart:1769`) are wired to `engine.updateBirthday` / `engine.suggestBirthday`. No
stubs, empty callbacks, TODOs, or fake data. The findings below are color/theming only.

- [ ] [MAJOR] Dialog chrome colors are hardcoded hex instead of `context.palette.*`, so the dialog ignores the user's theme — and several literals don't even match the app's own default palette: dark background `0xFF1E2C3A` ≠ `windowBg 0xFF17212B`, dark subtext `0xFF6C7883` ≠ `windowSubTextFg 0xFF708499`, light accent `0xFF3390EC` ≠ `windowActiveTextFg 0xFF168ACD`. The SAME widget already reads `context.palette.windowFg` (items, line 210) and `context.palette.activeLineFg` (band, line 212), so this is an internal inconsistency. AyuGram derives the box surface from the theme (`boxBg: windowBg`), so on any non-default theme the wheel items render themed while the dialog background/title/buttons stay fixed — a mismatched surface. — `birthday_picker.dart:199-202` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:135` (`boxBg: windowBg`; app's `windowBg` = `0xFF17212B`, telegram_palette.dart:3673)

- [ ] [MAJOR] Cancel and Remove buttons use the wrong color family. The Dart paints Cancel in subtext gray (`subtextColor`, line 330) and Remove in red (`Colors.red[400]`, line 325). In AyuGram all three buttons — confirm (`box->addButton`), cancel (`box->addButton(tr::lng_cancel())`) and the left reset (`box->addLeftButton(tr::lng_settings_birthday_reset())`) — are created with the box's default button style `getDelegate()->style().button` (blue `lightButtonFg`); no attention/destructive style is passed for the reset button, so it is NOT red. Save is correctly blue, but Cancel should be blue (not gray) and Remove should be blue (not red). — `birthday_picker.dart:325,330` ← `AyuGram/Telegram/SourceFiles/ui/boxes/edit_birthday_box.cpp:200,210,214` (+ `lib_ui/ui/layers/box_content.cpp:128-168` — all buttons default to `style().button` = `lightButtonFg`)

# call_panel — 1:1 voice/video call panel (port of AyuGram `Calls::Panel`)

Overall this is a faithful, fully-wired port: signal-bars (`callPanelSignalBars`
width/skip/min/max/radius/inactiveOpacity), fingerprint padding, preview sizes
(`callOutgoingPreviewMin/Default/Max`/`callOutgoingDefaultSize`), the 333-emoji
fingerprint table + `% kEmojiCount`, the answer-button outer ripple (100ms /
`kSoundSampleMs`, `outerRadius:12px`), the rating dialog, the conference-upgrade
flow, and the contact picker are all dimensionally accurate and wired to real
engine methods. No placeholders/stubs/mock-data/empty callbacks. The findings
below are state-binding / missing-control gaps, not fake UI. (Note: AyuGram's
post-call rating box is intentionally disabled — `if (false && data.is_need_rating()…)`
at `calls_call.cpp:809` — so the unused `needRating`/`_closeAndRate` path matches
AyuGram and is NOT a defect.)

- [ ] [MAJOR] Outgoing call-setup states (connecting / ringing / exchangingKeys / waiting / requesting) render ONLY an "End Call" button; AyuGram keeps Mute + Camera + Screencast (+ Add People) visible throughout these states (`toggleButton(_mute, !isWaitingUser)`, `toggleButton(_screencast, !(isBusy||isWaitingUser||incomingWaiting))`, `_camera->setVisible(!_startVideo)`), so during a ringing outgoing call the user cannot mute/enable camera/screencast — `call_panel.dart:857-862` (single button in `_buildConnectingState`, routed at `call_panel.dart:1361-1366`) ← `AyuGram/Telegram/SourceFiles/calls/calls_panel.cpp:1407-1425`

- [ ] [MAJOR] Incoming-call screen shows only Decline + Answer; AyuGram also shows the pre-answer Mute and Camera toggles on the incoming screen (mute toggled visible when `!isWaitingUser`, camera visible when `!_startVideo` even while `incomingWaiting`) — `call_panel.dart:792-807` (`_buildIncomingState`) ← `AyuGram/Telegram/SourceFiles/calls/calls_panel.cpp:1407,1421`

- [ ] [MAJOR] Outgoing self-video preview is never wired for real calls — AyuGram always creates `_outgoingVideoBubble` from `_call->videoOutgoing()` and shows the local camera/screen-share preview (snap-to-corner bubble in active state, in-body preview during setup), but `showCallPanel`/`_LiveCallPanelDialog` only ever pass the always-null `widget.selfVideoWidget` (a self-view is supplied solely by the `flutter_interact` debug command), so toggling the camera/screencast in a real call produces no local preview — `call_panel.dart:2970-2976` (and `showCallPanel` calls omit it at `call_panel.dart:2718,2802`) ← `AyuGram/Telegram/SourceFiles/calls/calls_panel.cpp:685-687,1264-1274`

- [ ] [MAJOR] Call media state (mute / camera / screen-share) is not sourced from the engine: the live `CallPanelInfo` stream populates fingerprint/signal/remote-mute/remote-battery/remote-video but never `isMuted`/`isCameraOn`/`isScreenSharing` (always default false). Consequence — the screencast button can never show its active/"Stop" state and `_onScreenShareTap`'s stop-branch (`if (widget.info.isScreenSharing)`) is permanently dead, so tapping it always re-opens the start chooser with no way to stop sharing; mute/camera are client-side optimistic only and won't reflect engine truth (e.g. mute from another device). AyuGram binds these to `_call->isSharingScreen()` / `mutedValue()` / `isSharingCamera()` — `call_panel.dart:2691-2706,2780-2794` (stream omits media state), `call_panel.dart:353-356` (dead stop-branch), `call_panel.dart:911-916` (button reads `widget.info.isScreenSharing`) ← `AyuGram/Telegram/SourceFiles/calls/calls_panel.cpp:739-768`

# call_screen — group-call panel, big mute button, settings, menus & minimised call bar

Audited `dart/lib/ui/call_screen.dart` against AyuGram `calls/group/*` + `calls/*`. The
port is structurally faithful (mute-button labels/colours, narrow/wide button sets, context-menu
gating, leave/end dialogs, scheduled overlay all match), but several features that *look* wired are
driven by fabricated backend data or the wrong API, plus a few real behavioural deviations.

## Backend wiring / placeholders (CRITICAL)

- [ ] [CRITICAL] "Invite Members" always calls the **conference-only** invite API, so it silently fails for normal group voice chats (the common case). `_showInviteMembersFromMenu` → `engine.inviteToConferenceCall` unconditionally — `call_screen.dart:3611` (menu item `call_screen.dart:3301-3308`) ← `AyuGram/Telegram/SourceFiles/calls/group/calls_group_call.cpp:4131` (`MTPphone_InviteToGroupCall` for normal calls; conference path is the *other* branch at `:4059`). The Go core requires a conference access hash and errors out for non-conference calls (`go/cores/telegram.go:28858-28867` → "no access hash for conference call"), and `engine_service.dart` swallows the error, so the user taps Invite and nothing happens with no feedback.

- [ ] [CRITICAL] Participant speaking blobs / `graphic_eq` speaking icon / audio levels are **fabricated**, not real call audio. The row level + speaking come from `_participantLevels`/`_participantSpeaking`, polled from `engine.getGroupCallParticipantLevels` — `call_screen.dart:319` (rendered at `call_screen.dart:575-576`, `:635-637`, `:653-654`) ← `AyuGram/Telegram/SourceFiles/calls/group/calls_group_members_row.cpp:175` (`setSpeaking(participant.speaking && ssrc != 0)`) + `:339` (`blobs.setLevel(real level)`). The engine method returns a time-based sine generator (`go/engine/cache_chats.go:2447-2480`), and the real participant `Sounding`/`IsSpeaking`/`AudioLevel` fields are **never populated** by the Telegram core (`go/cores/telegram.go:698-706` sets only muted/video/volume), so the fallbacks `p.isSpeaking`/`p.audioLevel` are always false/0 — the entire speaking visualisation is cosmetic.

- [ ] [CRITICAL] Settings mic-test level meter shows a **fake call-sound-peak**, not the microphone. `_CallSettingsSheetState` polls `engine.getCallSoundPeak(accountId, callId)` to drive `_MicLevelMeter` — `call_screen.dart:3674` (rendered `call_screen.dart:3829`) ← `AyuGram/Telegram/SourceFiles/calls/group/calls_group_settings.cpp:354-368` (LevelMeter fed by an independent `Webrtc::AudioInputTester.getAndResetLevel()` on the *selected capture device*, working regardless of call/mute state). `GetCallSoundPeak` is a synthetic oscillator (`go/engine/cache_chats.go:2432-2445`), so the "mic test" never reflects the real microphone and requires an active call.

## State not flowing from server (MAJOR)

- [ ] [MAJOR] "Mute new participants" / "Enable messages" toggles open with hardcoded initial state instead of the real server value. `onOpenSettings` passes `muteNewParticipants: false` always (`call_screen.dart:2917`) and the "…" menu's Settings item passes neither flag (defaults false, `call_screen.dart:3317-3321`) — `call_screen.dart:2917` ← `AyuGram/Telegram/SourceFiles/calls/group/calls_group_settings.cpp:302` (`->toggleOn(rpl::single(joinMuted))`, where `joinMuted = real->joinMuted()` at `:276`; messages toggle seeded from `messagesEnabled` at `:308`). So "Mute new participants" always shows OFF even when the chat has join-muted enabled, and the messages toggle shows OFF when opened from the "…" menu even if enabled.

- [ ] [MAJOR] Noise-suppression toggle is never applied to the running call — only persisted to config. `engine.setNoiseSuppression(accountId, '', v)` is called with an empty callId — `call_screen.dart:3812` ← `AyuGram/Telegram/SourceFiles/calls/group/calls_group_settings.cpp:383` (`call->setNoiseSuppression(enabled)` applies it live to the WebRTC instance). The Go impl ignores callId and only writes `config.NoiseSuppression` (`go/engine/cache_chats.go:2214-2219`), so toggling mid-call has no audible effect.

## Behavioural / dimensional deviations (MAJOR)

- [ ] [MAJOR] Group-panel subtitle appends a running call duration that AyuGram deliberately omits. Renders `'$count participant(s) · ${_formatDuration(_durationSeconds)}'` — `call_screen.dart:511` ← `AyuGram/Telegram/SourceFiles/calls/group/calls_group_panel.cpp:2810` (subtitle is `lng_group_call_members(count)` only; `updateDurationText` early-returns for group calls — duration is a personal-call-only control). The per-second `_durationTimer` also forces a full-panel rebuild every second purely for this invented label.

- [ ] [MAJOR] Audio-level timer rebuilds the entire `GroupCallPanel` subtree every 100 ms. `_startAudioLevelPolling` calls `setState(() {})` on the whole state (participant ListView + controls + viewport) whenever the (fake) levels tick — `call_screen.dart:310`,`call_screen.dart:344` ← `AyuGram/Telegram/SourceFiles/calls/group/calls_group_members_row.cpp:339-355` (blob level updates are scoped to the individual row's `BlobsAnimation`, not a panel-wide relayout). Compounding it, `_selfAudioLevel` is assigned (`call_screen.dart:326`) but **never read in `build()`** — a dead field whose changes still trigger these rebuilds.

- [ ] [MAJOR] Wide (video) mode panel opens at 720 px wide instead of AyuGram's 960 px (~25% narrower). `wantsWide` reuses `defaultWidthRtmp` (720) for *both* RTMP and non-RTMP video — `call_screen.dart:2724-2729` (`defaultWidthRtmp = 720` at `:88`) ← `AyuGram/Telegram/SourceFiles/calls/calls.style:1358` (`groupCallWideModeSize: size(960px, 580px)`; RTMP's 720 px is the *separate* `groupCallWidthRtmp`). The RTMP width is correct, but a video group call's wide stage is undersized, and the dialog is fixed-size (non-resizable) vs AyuGram's resizable window.

# calls_screen — Calls box (history, active group calls, create/conference call, mic level meter)

Audit verdict: this file is well-wired. Every engine call (`getCallHistory`,
`clearCallHistory`, `getChatList`, `joinGroupCall`, `getGroupCall`,
`getConfcallSizeLimit`, `getContacts`, `startCall`, `createConferenceCall`,
`inviteToConferenceCall`, `deleteMessage`) was verified to exist in
`engine_service.dart`. No empty callbacks, stubs, mock data, or "coming soon".
Pagination constants (20/100) match `kFirstPageCount`/`kPerPageCount` exactly.
`defaultLevelMeter` (18px/3px lineWidth/5px spacing/44 lines/mediaPlayerActiveFg)
and `createCallListItem` (52px, photo 12,6 @40px, name 63,7, status 63,26) are
reproduced exactly. Selection toggle logic is a faithful port of
`ConfInviteController`. Findings below are visual/text fidelity deviations only.

- [ ] [MAJOR] Create-call button renders a 42px filled accent **circle** with a white `add_call` glyph; AyuGram's `AddCreateCallButton` is a flat `inviteViaLinkButton` row whose icon is the small `inviteViaLinkIcon` = `"info/edit/group_manage_links"` tinted accent (`lightButtonFg`) placed at `point(23px,2px)`, vertically centered — no filled circle, and row height is ~37px (text 20px + 8/9 padding) not 56px — `calls_screen.dart:918` ← `AyuGram/Telegram/SourceFiles/calls/calls_box_controller.cpp:789` / `AyuGram/Telegram/SourceFiles/boxes/boxes.style:871`

- [ ] [MAJOR] Empty call-history placeholder text is wrong: shows "Your recent calls will appear here." but AyuGram's `refreshAbout()` sets `lng_call_box_about` = "You haven't made any Telegram calls yet." — `calls_screen.dart:428` ← `AyuGram/Telegram/SourceFiles/calls/calls_box_controller.cpp:597` / `AyuGram/Telegram/Resources/langs/lang.strings:5861`

- [ ] [MAJOR] Call-history row context-menu labels deviate from AyuGram's `rowContextMenu`: Dart uses "Delete" (attention/red-tinted) + "Show in Chat"; AyuGram uses `lng_context_delete_selected` = "Delete Selected" with the non-attention `menuIconDelete`, and `lng_context_to_msg` = "Go To Message" — `calls_screen.dart:2103` ← `AyuGram/Telegram/SourceFiles/calls/calls_box_controller.cpp:584` / `AyuGram/Telegram/Resources/langs/lang.strings:5097`

- [ ] [MAJOR] Clear-call-history box text deviates: confirm line is "Are you sure you want to delete all call history?" vs AyuGram `lng_call_box_clear_sure` = "Are you sure you want to completely clear your calls log?", and the revoke checkbox reads "Also delete for other participants" vs AyuGram `lng_delete_for_everyone_check` = "Delete for everyone" (AyuGram's `ClearCallsBox` also sets no box title, while Dart adds "Clear Call History") — `calls_screen.dart:498` ← `AyuGram/Telegram/SourceFiles/calls/calls_box_controller.cpp:719` / `AyuGram/Telegram/Resources/langs/lang.strings:5867`

# engine_service — Dart-side FFI bridge wrapper for the Go engine

`engine_service.dart` (7912 lines) is the high-level data layer: it serializes
requests (protobuf or JSON) to the Go engine over the FFI bridge, deserializes
responses, and fans engine events out to typed Dart streams. It is NOT UI code,
so there are no visual/widget comparisons to make.

Audit result: the file is overwhelmingly clean. All ~511 public operations
(53 sync `_callRaw` + 458 async `_callAsync`) genuinely forward to the engine —
**no stubs, no placeholders, no "coming soon", no hardcoded/fake response data,
no empty callbacks, no unwired methods.** Event dispatch (`_dispatchEngineEvent`,
6856-7033) routes every engine event type to its stream, and `dispose()`
(6730-6758) closes every controller. The proto→model converters (7037-7426) map
every field. The grep hits for `stub/placeholder/mock/fake` are all false
positives (`clamp`, the real bot field `force_reply_placeholder`, the real
account field `is_fake`).

The only concrete deviations from the AyuGram authority are wrong hardcoded
fallback defaults — values used when the engine returns empty / errors, which is
also exactly when AyuGram falls back to its own `appConfig().get<T>(key,
DEFAULT)` default. AyuGram's DEFAULT is the contract these fallbacks are meant to
mirror, and two of them don't.

- [ ] [MAJOR] `getConfcallSizeLimit` falls back to `200`, but AyuGram's conference-call participant cap default is `100` (and `5` in test mode) — the fallback is ~2× too high and drops the test-mode branch entirely, so the conference-invite picker would cap at the wrong size whenever `conference_call_size_limit` is absent from app-config — `engine_service.dart:2425` (also 2427, 2429) ← `AyuGram/SourceFiles/main/main_app_config.cpp:161`

- [ ] [MAJOR] `getPaidMessagesConfig` falls back to `commissionPermille: 150`, but AyuGram's `stars_paid_message_commission_permille` default is `850` — note `150 == 1000 - 850`, i.e. the complement, so this looks like the "amount kept" was used where the "commission taken" is expected; on the fallback path the paid-messages UI would show a ~15% commission instead of the correct 85% — `engine_service.dart:5302` (also 5307) ← `AyuGram/SourceFiles/main/main_app_config.cpp:129`

## Checked and NOT flagged (to avoid false positives)

- `getMegagroupSizeMax` falls back to `200000` while AyuGram's compile-time
  `megagroupSizeMax` default is `10000` (`mtproto/mtproto_config.h:18`). NOT a
  bug: `200000` is the real live-server value and the method's own doc comment
  intentionally documents it as the fallback. AyuGram's `10000` is only its
  conservative pre-config constant.
- `getStarsPaidPostAmountMax` fallback `10000` matches AyuGram
  `stars_paid_post_amount_max` default `10'000` (`boxes/send_files_box.cpp:275`). ✓
- `getPaidMessagesConfig` `withdrawRate` fallback `0.013` vs AyuGram
  `stars_usd_withdraw_rate_x1000`/1000 = `1.3` (`main_app_config.cpp:105`): units
  are ambiguous (USD-per-star vs USD-per-1000-stars), so not flagged.
- Performance: a few message-fetch paths parse heavy protobuf on the UI thread
  (`getPinnedMessages:3309` sync, `getDeletedMessages:3377` sync,
  `searchSavedMessagesByReaction:5861` async-but-no-isolate) where `getMessages`
  (3288) offloads to `Isolate.run`. Real inconsistency, but counts are small
  (pinned/deleted ≤ ~20-30) and there is no AyuGram C++ line to cite against
  (different threading model), so it is not reported as a both-files finding.

# clipboard_image — clipboard→PNG reader for the "Photo from clipboard" avatar action (port of `userpic_button.cpp` `addFromClipboard`)

The utility itself is a faithful, fully-wired implementation: it reads the OS
clipboard via platform tools (Flutter's `Clipboard` is text-only), accepts ANY
`image/*` type and coerces to PNG to mirror Qt's
`qvariant_cast<QImage>(data->imageData())`, returns null for "no image", and
throws `ClipboardToolMissingException` to distinguish "no clipboard tool" from
"no image". No stubs, no placeholders, no mock data; the result flows through
`my_profile_page.dart:1431-1471` into `PhotoCropEditor` → `engine.uploadProfilePhoto`.
One behavioral deviation from AyuGram is noted below.

- [ ] [MAJOR] AyuGram adds the "Photo from clipboard" menu action ONLY when the clipboard actually holds an image (`if (const auto data = ...mimeData()) { if (data->hasImage()) { _menu->addAction(...); } }`); the Dart consumer shows the "From Clipboard" item unconditionally and only discovers the clipboard is empty after the user taps it, then shows a "No image in clipboard" toast. `getClipboardImage()` is the only public entry point and exposes no cheap synchronous has-image probe (it always spawns a subprocess + decodes), so the menu cannot be gated the AyuGram way. Add a lightweight `clipboardHasImage()` (Linux: just scan `--list-types` / `TARGETS` for an `image/*` type, no byte fetch/decode) and gate the menu item on it. — `clipboard_image.dart:34` (sole entry point, no peek variant) / consumer `my_profile_page.dart:1307-1316` (unconditional `PopupMenuItem value:'clipboard'`) ← `AyuGram/Telegram/SourceFiles/ui/controls/userpic_button.cpp:382-398`

# ayu_filter — regex/shadowban message-filter engine (FiltersController + FiltersCacheController + FilterUtils port)

Audited `dart/lib/data/ayu_filter.dart` against AyuGram's
`ayu/features/filters/{filters_controller,filters_cache_controller,filters_utils}.cpp`,
`ayu/data/entities.h`, and `ayu/ui/settings/filters/per_dialog_filter.cpp`.

The vast majority of the port is faithful and well-documented (import/export round-trip
incl. UUID wire format + dialogId null handling, ICU→Dart regex translation, media/service
`<type>` maps, album/group cache propagation, exclusions, the direct-sender block/shadowban
short-circuit, `broadcast==channel` enablement, dpaste publish). The engine is genuinely
wired into the UI (`chat_state.dart:3022`, `chat_view.dart:3221`, `chat_list_panel.dart:1680/1816`).
One real defect found.

- [ ] [CRITICAL] Forwarded-origin block/shadowban hiding never fires — the forward branch parses the numeric origin ID out of `msg.forwardFrom`, but that field carries a **display name**, not an ID. AyuGram hides a message whose forwarded *original* sender is blocked/shadowbanned, keyed on the original sender's real peer ID (`isShadowBanned(originalSender)` / `originalSender->asUser()->isBlocked()`). The Dart calls `_parseForwardSenderId(msg.forwardFrom)` — `ayu_filter.dart:1007` ← `AyuGram/ayu/features/filters/filters_controller.cpp:119-129`. The Go engine populates `forwardFrom` with `GetFromName()` → cached user/channel name → and only as a last-resort fallback the `"User <id>"`/`"Channel <id>"`/`"Chat <id>"` string (`cores/telegram.go:12254-12281`); the numeric ID lives in the separate `forwardFromID` field. `_parseForwardSenderId` (`ayu_filter.dart:1073-1080`, regex `_forwardIdPattern` at `:1071` = `(?:User|Channel|Chat) (\d+)$`) therefore returns `null` for any forward whose origin has a known/cached name — which is the normal case for a user you have actually blocked or shadow-banned (they're cached precisely because you've interacted with them). Result: the entire forwarded-origin half of `_filterBlocked` (`ayu_filter.dart:1004-1011`) is dead in practice, while the direct-sender path (`:990-1003`, which reads the real numeric `msg.senderId`) works. The fix must read the numeric origin ID (`msg.forwardFromId`), not `msg.forwardFrom`.

  Fix caveat (out-of-file, but the fix is incomplete without it): `msg.forwardFromId` is itself empty on messages built through the proto bridge. The Go engine marshals `forward_from_id` as a **top-level** key of `content_raw` (`json.Marshal(msg)` over `cores.Message`, `engine/cache_msgs.go:436` + `cores/base.go:308`), but `engine_service.dart:7148` sources it via `_strFromExtra(extra, 'forward_from_id')`, which only looks inside `content_raw['extra']` (`lib/bridge/engine_service.dart` `_strFromExtra`). The proto `EngineCachedMessage` has no `forward_from_id` field (`go/proto/engine.pb.go:2659` — only `forward_from`), so `cachedMsgToProto` (`go/bridge/dispatch_engine.go:7663-7681`) drops `m.ForwardFromID` entirely. So fully fixing the forwarded-origin hide requires (a) using `forwardFromId` in `_filterBlocked`, and (b) actually plumbing `forward_from_id` to Dart (add the proto field, or have the bridge read the top-level key instead of `extra`).

# emoji_data — emoji keyword/suggestion engine (port of `EmojiKeywords` + `Completer` + built-in replacement data)

Audited `dart/lib/data/emoji_data.dart` against AyuGram's `emoji_keywords.cpp`
(server lang-pack manager), `emoji_suggestions.cpp` (`Completer` legacy
fallback), `core_settings.cpp` (`incrementRecentEmoji` recent ordering), the
`emoji_suggestions_widget.cpp` query path, and the `replaces.cpp` codegen that
bakes the built-in replacement list from `emoji_autocomplete.json`.

The LOGIC is an exceptionally faithful 1:1 port — verified against source:
- `recordRecent`/`_bubbleRecentToFront` == `Settings::incrementRecentEmoji`
  (rating-descending, 0x8000 halving, 54-cap) — core_settings.cpp:1411-1466.
- `_prioritizeRecent` == `PrioritizeRecent` rotate-to-frontier — emoji_keywords.cpp:650-672.
- `_searchLangPack` lower_bound + take_while + cross-pack dedup, sorted lang-code
  iteration == `LangPack::query`/`EmojiKeywords::query` — emoji_keywords.cpp:473-496,608-642.
- `_searchLegacyData`/`_matchLegacyWords`/`_legacyRankKey` == `Completer` (single-char
  fast path, interior-word match, the 4-`stable_partition` ranking with the dead
  `isExactMatch` 4th partition correctly identified as never-reordering) —
  emoji_suggestions.cpp:267-404. Confirmed dead-code: replacements are `:keyword:`
  (len+2) vs colon-stripped query (len), so the size gate is never true.
- `maxQueryLength` folds `legacyLimit`+`modernLimit` (widget did `max(...)`) —
  emoji_suggestions_widget.cpp:959; the off-by-2 vs `GetSuggestionMaxLength` never
  changes output (no keyword lives in the gap).
- Backend wiring is REAL: chat_view fetches `GetEmojiKeywordsLanguages` →
  `GetEmojiKeywords`/`...Difference` → `loadServerKeywords`/`Diff` with version
  tracking + hourly auto-refresh (chat_view.dart:3944-4005); recent recorded on
  send, on incoming receive (chat_state.dart:3010), and on pick (emoji_panel);
  skin-tone resolver wired (emoji_panel.dart:60). No placeholders, no stubs, no
  empty callbacks, no mock data.

The only deviations are in the baked built-in replacement DATA (`kEmojiSuggestions`):
a keyword-multiset diff vs the JSON + codegen showed 4030 of 4034 keywords match
EXACTLY (including duplicate counts); the 5 below are the entire delta.

- [ ] [MAJOR] The 4 hardcoded codegen-added built-in replacements are MISSING from `kEmojiSuggestions`. AyuGram appends `:like:`→👍, `:dislike:`→👎, `:hmm:`→🤔, `:party:`→🥳 *after* parsing the JSON. Effect in the Dart legacy completer: typing `:like`/`:dislike`/`:hmm` yields no built-in suggestion (👍/👎/🤔 exist but lack the alias). Worst case: 🥳 (`1f973`) is NOT in `emoji_autocomplete.json` at all — it exists ONLY via the `:party:` extra — so the Dart never suggests 🥳 via the built-in fallback. — `emoji_data.dart:477` (👍 `['thumbsup','+1','thumbup']`, no `like`), `emoji_data.dart:478` (👎, no `dislike`), `emoji_data.dart:1717` (🤔, no `hmm`), 🥳 absent entirely ← `Telegram/codegen/codegen/emoji/replaces.cpp:281-292`

- [ ] [MAJOR] Extra `shrug` keyword on 🤷 that AyuGram deliberately strips. The codegen removes `:shrug:` from the alias list via the `Exceptions = { ":shrug:" }` filter, so AyuGram's 🤷 carries only `person_shrugging`. The Dart entry keeps `shrug`, so typing `:shrug` suggests 🤷 in the Dart where AyuGram intentionally suppresses it. — `emoji_data.dart:346` (`EmojiEntry('🤷', ['person_shrugging', 'shrug'])`) ← `Telegram/codegen/codegen/emoji/replaces.cpp:220-226`

# strings — TrStrings static lang-pack table (port of AyuGram `tr::lng_*` / `lang.strings`)

`strings.dart` is the embedded English string table (`TrStrings`). It maps ~100
Telegram/AyuGram lang-pack keys to hardcoded English. Verified ~55 keys 1:1
against `AyuGram/Telegram/Resources/langs/lang.strings` (intro, passcode, theme,
file-size-limit box, notification content, all 15 reaction keys, poll-vote keys,
report-reaction, paid-post warnings, delete-chat, folder checkboxes, session
termination, TTL-edit, and the `ayu_AyuForwardStatus*` keys) — values match.
The findings below are the real divergences.

## Localization wiring

- [ ] [MAJOR] `TrStrings` returns hardcoded English literals and never consults the cloud language pack, so all 132 call sites render English regardless of the user's selected language. The repo already ships the correct overlay mechanism next door — `LangPack.tr()` resolves *server overlay → English baseline → key* and is wired to `langpack.getStrings` — but none of these ~100 keys are registered in `LangPack`, and the UI calls `TrStrings.lngXxx()` directly. In AyuGram every `tr::lng_*` resolves through `Lang::Instance::getValue` (returns the cloud-overlaid value or the embedded English default), so all of these strings localize. Result: a user who picks e.g. Spanish gets localized intro/login (via LangPack) but English notifications, passcode, sessions, auto-delete, reports, paid-post warnings and AyuForward status — a visible parity gap. (English baseline is correct, so MAJOR not CRITICAL; the header comment "Replace with server-sourced language packs when i18n is implemented" acknowledges it.) — `strings.dart:4-226` (e.g. `strings.dart:8`) ← `AyuGram/Telegram/SourceFiles/lang/lang_instance.h:90` (cf. in-repo `dart/lib/l10n/lang_pack.dart:188`)

## String-value mismatches vs `lang.strings` (ground truth)

- [ ] [MAJOR] `lngSigninCantEmailForgot()` reads "…restore access to **your** email…" but AyuGram's value is "…restore access to **the** email…" — wrong word in account-recovery copy. — `strings.dart:11-13` ← `AyuGram/Telegram/Resources/langs/lang.strings:440`
- [ ] [MAJOR] `lngThemeKeepChanges()` returns `'Keep Changes'` but `lng_theme_keep_changes` = "Keep changes" (lowercase "changes"). Casing divergence from ground truth. — `strings.dart:19` ← `AyuGram/Telegram/Resources/langs/lang.strings:1088`
- [ ] [MAJOR] `lngNotifLiveLocation()` returns `'Live location'` but `lng_live_location` = "Live Location" (capital "Location"). — `strings.dart:93` ← `AyuGram/Telegram/Resources/langs/lang.strings:4967`
- [ ] [MAJOR] `lngEnableAutoDelete()` returns `'Enable auto-delete'` but `lng_enable_auto_delete` = "Enable Auto-Delete" (title case). — `strings.dart:149` ← `AyuGram/Telegram/Resources/langs/lang.strings:5559`
- [ ] [MAJOR] `lngEditAutoDeleteSettings()` returns `'Edit auto-delete settings'` but `lng_edit_auto_delete_settings` = "Edit Auto-Delete Settings" (title case). — `strings.dart:150` ← `AyuGram/Telegram/Resources/langs/lang.strings:5558`

## Verified correct (no action)

- Intro (`lng_intro_finish/next/submit`), passcode block (`lng_passcode_*` incl. winhello/touchid/applewatch/systempwd), theme (`lng_theme_sure_keep/reverting/revert`), `lng_box_ok/done`, `lng_cancel`, `lng_limits_increase`, `lng_flood_error` — exact.
- File-size box: `lng_file_size_limit_title/1/2` and `#one/#other` "{count} GB" — exact.
- Notification content: `lng_notification_preview/reminder`, `lng_from_you`, `lng_in_dlg_*` (photo/video/audio_file/audio/video_message/sticker/file/poll/contact), `lng_in_dlg_voice_message_ttl`/`_video_message_ttl`, `lng_maps_point`, GIF (hardcoded `u"GIF"_q` in `data_media_types.cpp:1229`) — match.
- All 15 reaction keys (`lng_reaction_*`) and poll-vote keys (`lng_poll_vote`/`_notext`/`_option`) — exact, including placeholder order.
- Report (`lng_report_reaction_*`, `lng_report_and_ban_button`, `lng_report_select_messages`, `lng_report_please_select_messages`), paid-post warnings (`lng_suggest_warn_*`), delete-chat (`lng_profile_delete_conversation`, `lng_profile_block_bot`), folder checkboxes (`lng_filters_checkbox_remove_*`), `lng_settings_save`, `ayu_BoxActionReset`, `lng_settings_theme_accent_title` — exact.
- Sessions (`lng_settings_reset_button/_one_sure/_sure`, `lng_self_destruct_sessions_title/_description`), TTL timer + about (`lng_manage_messages_ttl_*`, `lng_ttl_edit_about*`), `lng_edited` — exact.
- `ayu_AyuForwardStatus*` (Preparing/LoadingMedia/Forwarding/Finished/SentCount/ChunkCount) verified against both `lang.strings:8323-8328` and usage in `ayu_forward.cpp:64-92` — exact, placeholders `{count1}/{count2}` correctly mapped.
- English pluralization (`count == 1 ? '' : 's'`) for `lngThemeReverting`/`lngForwardMessages` matches the `#one`/`#other` CLDR English forms.
- No empty callbacks, TODO/FIXME, mock data, or "coming soon" stubs in the file.

