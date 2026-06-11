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
fully engine-wired; the findings below were the verified CRITICAL/MAJOR deviations —
all now FIXED and closed (see the Stage 2 verification summary that follows).
Several MAJOR items were UI elements wired to a Go-engine method that silently dropped
or never emitted the needed field — the Dart looked functional but the feature was dead;
per the audit rubric these were counted as broken-wiring defects (root cause in
`go/cores/telegram.go` was noted inline and fixed).

Verified (ralph Stage 2): all 16 CRITICAL/MAJOR items are now FIXED and confirmed —
checked 1:1 against the cited AyuGram sources (exact `lang.strings` matches, full
FFI-stack wiring traced end-to-end, and live UI testing of every reachable screen in
BOTH desktop 1024×768 and mobile 400×720). Closed fixes:

- History-visibility "Hidden" sub-text is now legacy-aware — legacy basic groups keep `lng_manage_history_visibility_hidden_legacy` ("…won't see more than 100 previous messages."), supergroups use `lng_manage_history_visibility_hidden_about` ("…won't see earlier messages."). Confirmed live on the legacy group.
- Discussion-link "Create a new group" now opens the interactive create-megagroup wizard (title pre-filled "<channel> Chat", editable description/photo) whose creation callback stages the link. Confirmed live: the "New Group" wizard opens pre-filled "Test Channel Flow Chat" — no silent `createMegagroup`.
- Verify Accounts wired through a new typed `SetBotCustomVerification` across telegram.go / engine.go / dispatch_engine.go / engine_service.dart (f_bot | f_enabled | f_custom_description, matching Setup/Remove); tap now routes through a confirm box with an editable custom-description field gated by `canModifyDescription`; candidate list spans users + channels + supergroups (not just mutual contacts). No more `unknown engine method`.
- Reactions box: groups get the All/Some/None radios; broadcast channels get the single enable-reactions toggle + max slider + paid toggle (matching `addOption`'s `!isGroup` early-return). Group radios confirmed live.
- Manage-section rows gated per-row by canEditReactions / canEditPermissions / canHaveInviteLink / canViewAdmins / canViewMembers (new can_ban / can_invite / can_view_participants flags from the Go core, matching `data_channel.cpp`). Confirmed live: a broadcast channel now hides Permissions and shows Sign Messages/Profiles.
- Media master-toggle now ON when ANY sub-flag is allowed (`allowedCount > 0`) and a click bans all (matching `setChecked(count > 0)` + invert-all-inner); fixed at both instances.
- `edit_rank` ("Edit own tag") is now a normal toggleable restriction, serialized through `RestrictMemberWithRights` → `ChatBannedRights.EditRank`.
- ManageRanks ("Edit member tags") admin right now saved — `ManageRanks: rights["manage_ranks"]` added to the Go `ChatAdminRights` builder.
- Star-ref setup: existing program duration pre-filled from `GetBotManageInfo.star_ref_program.duration_months` (0 → forever/999), with the irreversibility floor set from it; ended-program 24h cooldown disables the Start button with a live "Available in {time}" countdown (`end_date` now emitted + a 1s tick timer).
- Invite-link revoke and single-delete now route through confirm boxes with exact AyuGram text (`lng_group_invite_about_new` permanent / `lng_group_invite_revoke_about` regular / `lng_group_invite_delete_sure`). Revoke confirm with the exact permanent-link string confirmed live.
- Real-user booster rows now emit `avatar_b64` (engine caches `list.Users`) so the actual userpic renders instead of the letter placeholder.
- Stars→USD now `stars * usd_rate` (removed the extra `/1000`) at both conversion sites (`formatAmount`, `_fmtUsd`), matching AyuGram `ToUsd` = `value() * rate`.

Go + Flutter both rebuilt clean (the fresh `libcores.so` was synced into the bundle); app launches and runs in both desktop and mobile modes with no crashes, no Dart exceptions from the changed files, and no `unknown engine method`.

## Sections audited — no CRITICAL/MAJOR issues

These components were diffed against their AyuGram sources end-to-end (UI → engine_service → Go core) and verified faithful and fully wired:

- **EditPeerPermissions box** (default member rights) — full flag set, media sub-group with master toggle, slowmode (8 values), boosts-unrestrict (1–5), charge-stars slider, flag interdependencies, locked-state logic, and all 5 engine round-trips match `edit_peer_permissions_box.cpp`.
- **AdminLog screen** (recent actions + filter) — all 53 `GenerateItems` event-type phrases present, `getAdminLogEvents` wired with query/maxId/filter/admins, debounced search, scroll pagination, `ListView.builder`, actor-name→profile click, filter dialog mirrors AyuGram's 3 sections + per-admin selector (`history_admin_log_item.cpp`, `history_admin_log_filter.cpp`, `history_admin_log_inner.cpp`).
- **MemberList screen** (members/admins/banned/restricted/requests + picker) — per-role RPC filters, add/remove/ban/unban, join-request approve/dismiss, anti-spam header gating, contact+global picker search order, per-role context menus, `ListView.builder` + pagination (`edit_participants_box.cpp`, `add_participants_box.cpp`, `edit_peer_requests_box.cpp`).
- **Statistics screen** (overview + charts + recent posts) — real MTProto data (no fakes), all 12 channel / 8 group charts, series toggle, crosshair tooltip, draggable range-footer, server zoom, growth-badge formula, `ListView.builder` + `RepaintBoundary` (`info_statistics_inner_widget.cpp`, `chart_widget.cpp`, `api_statistics.cpp`).
- **StarRefJoin screen** (join other bots' programs) — connected + suggested lists fetched & paginated, 3 sort orders, join-confirmation box before connect, revoke/leave, copy/share, commission/duration from data, `ListView.builder` (`info_bot_starref_join_widget.cpp`, `info_bot_starref_common.cpp`).

# call_screen — group-call panel, big mute button, settings, menus & minimised call bar

Audited `dart/lib/ui/call_screen.dart` against AyuGram `calls/group/*` + `calls/*`. The port is
structurally faithful (mute-button labels/colours, narrow/wide button sets, context-menu gating,
leave/end dialogs, scheduled overlay all match). The CRITICAL/MAJOR findings below were features
that *looked* wired but were driven by fabricated backend data or the wrong invite API, plus a few
behavioural/dimensional deviations — all now FIXED and closed.

Verified (ralph Stage 2): all 8 CRITICAL/MAJOR items are now FIXED and confirmed 1:1 against the
cited AyuGram sources, with Go (`libcores.so`) + Flutter linux debug both building clean and the app
launching/running with zero exceptions (the new InviteToGroupCall / GetGroupCallSettings /
GetGroupCallAudioLevels / SetNoiseSuppression methods raise no engine errors). Closed fixes:

- Invite Members now branches conference-vs-normal: a new end-to-end `InviteToGroupCall`
  (`phone.inviteToGroupCall`) across core/engine/bridge/Dart drives normal voice chats
  (`isConference = info.conferenceInviteLink.isNotEmpty`), with success/failure snackbar feedback —
  no more silent conference-only no-op. ← `calls_group_call.cpp:4131` vs the conference branch `:4059`.
- Participant speaking blobs / `graphic_eq` / levels are now driven by REAL call audio: per-SSRC
  levels parsed from the RTP `ssrc-audio-level` header extension (RFC 6464) on incoming SFU audio,
  mapped SSRC→userID, exposed via `GetGroupCallAudioLevels`. The synthetic sine generator and the
  fabricated `isSpeaking` snapshot fallback are deleted. ← `calls_group_members_row.cpp:175/339`.
- Settings mic-test meter now captures the SELECTED microphone directly (parec/pw-record/rec/ffmpeg)
  and shows its real peak regardless of call/mute state — AyuGram's `AudioInputTester` equivalent;
  the synthetic `getCallSoundPeak` oscillator is gone. ← `calls_group_settings.cpp:255/363`.
- "Mute new participants" / "Enable messages" toggles seed from real server state via
  `GetGroupCallSettings` (joinMuted/messagesEnabled cached from `UpdateGroupCall` + lazy
  `phone.getGroupCall` fetch); both open paths pass `callId`+`isCanManage`, so the box reflects the
  server value, not a hardcoded false. ← `calls_group_settings.cpp:274-309`.
- Noise-suppression toggle passes the real `callId`; the engine applies it live to the running call
  (the core stores the per-call flag — the canonical source of truth in this DSP-free pure-Go/no-CGo
  build) and still persists the default. The empty-callId / config-only bug is fixed. ←
  `calls_group_settings.cpp:383`.
- Group-panel subtitle drops the invented running duration (member count only, matching
  `lng_group_call_members`); the per-second timer now fires ONLY for the scheduled-call countdown,
  so active calls no longer rebuild the whole panel every second. ← `calls_group_panel.cpp:2810`.
- Audio-level rebuilds scoped: a `_levels` `ValueNotifier` + `ValueListenableBuilder` around each row
  blob / `graphic_eq` / wide viewport means the 100 ms tick rebuilds only those, not the whole panel;
  the dead `_selfAudioLevel` field is removed. ← `calls_group_members_row.cpp:339-355`.
- Wide (video) mode opens at `groupCallWideModeSize` (960×580); RTMP keeps `groupCallWidthRtmp`
  (720); the panel is now drag-resizable from the bottom-right corner. ← `calls.style:1358`.

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

