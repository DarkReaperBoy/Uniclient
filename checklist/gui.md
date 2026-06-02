# GUI Audit — Cycle 1 Phase Ayugram (2026-06-02 00:21)

## Code Comparison (Dart vs AyuGram)

# notification_manager_default — Default in-app notification popup controller

This file ports AyuGram's `Window::Notifications::Default::Manager` (the controller that
queues notifications, fills visible slots, drives auto-hide/hover-hide, and handles the
clear-from-X operations). The actual popup widgets live in `lib/ui/notification_popup.dart`,
wired via the `onShow/onDismiss/onStartHiding*/onUpdateDisplay/onHideAll*` callbacks.

Coverage is otherwise faithful: timing constants match AyuGram exactly
(`_dismissDuration 3000` = `notifyWaitLongHide`, hideAll fallback `150` = `notifyFastAnim`,
`_inputCheckInterval 300` = `_inputCheckTimer.callOnce(300)`), `maxNotificationCount.clamp(1,5)`
matches `std::clamp(..., 1, kMaxNotificationsCount=5)`, queue is FIFO, newest-kept/oldest-evicted
on count reduction matches `settingsChanged(MaxCount)`, and demo-master-opacity is correctly
delegated to the view (`AppState.notifDemoShown → demoDimmed`). The issues below are real
behavioral deviations.

# notification_manager_native — Linux DBus / freedesktop notifications

Audited `dart/lib/notifications/notification_manager_native.dart` against AyuGram's
`platform/linux/notifications_manager_linux.cpp`, `window/notifications_utilities.cpp`,
and `ui/empty_userpic.cpp`.

**Overall: this file is a faithful, fully-wired implementation — NOT a stub.** Verified
correct: the `Notify` call signature + image-data hint struct (width/height/rowstride/
has_alpha=true/bits=8/channels=4/RGBA8888 bytes) matches `notifications_manager_linux.cpp:696-709`;
body markup (`<b>{subtitle}</b>\n{message}` with HTML escaping vs plain
`lng_dialogs_text_with_from`) matches `:776-792`; actions (default/mail-mark-read/inline-reply
gated on `actions`/`inline-reply` caps + hideMarkAsRead/hideReplyButton) match `:613-630`;
the `GetImageKey` spec-version mapping matches `:124-132`; NotificationClosed reason==2 handling
matches `:490-519`; ActionInvoked→onAction and NotificationReplied→onReply are wired to real
engine calls (`main.dart:621-634`: open→_onNotifTap, markRead→markChatRead, reply→sendMessage);
sound caching + `handlesSound`/DND contract match `VolumeSupported()`/`invokeIfNotInhibited`.
The 8 userpic gradient pairs (`:308-317`) and the `[0,7,4,1,6,3,5]` palette map (`:322`) are
byte-exact with `lib_ui/ui/colors.palette` + `chat_style.cpp:1205`.


# notification_sound — NotificationSoundPlayer (media_kit) vs AyuGram Track/System sound playback

Scope: `dart/lib/notifications/notification_sound.dart` — plays the notification
alert sound. Compared against AyuGram `Window::Notifications::System` sound path
(`notifications_manager.cpp`), `Media::Audio::Track` gain (`media_audio_track.cpp`),
and `Settings::getSoundPath` (`core_settings.cpp`).

**What is CORRECT (verified, no action needed):**
- Default sound extraction of bundled `assets/sounds/msg_incoming.mp3` (asset
  exists, declared in `pubspec.yaml:60`) mirrors `getSoundPath("msg_incoming")`
  → `:/sounds/msg_incoming.mp3` (`core_settings.cpp:1245-1251`) and
  `ensureSoundCreated()` (`notifications_manager.cpp:1030-1038`).
- `allowSound` gate (`notification_sound.dart:42`) matches `settings.soundNotify()`
  (`notifications_manager.cpp:761`).
- Volume formula `perChatVolume > 0 ? perChatVolume : settings.volume`
  (`notification_sound.dart:62`) is the correct analogue of AyuGram's
  `AL_GAIN = (volumeOverride > 0) ? volumeOverride : notificationsVolume()/100`
  (`media_audio_track.cpp:155-160`). The 0–100 scale is correct for media_kit
  (`setVolume` defaults to `100.0` = full; confirmed in `media_kit/player.dart:232`).
- Plays once (no loop), matching `playOnce` (`notifications_manager.cpp:775`).
- Properly wired into dispatch with native-sound dedup (`handlesSound`) and a
  per-thread alert throttle (`notification_system.dart:610-627`).

## Findings

# notification_system — Notification scheduling/dedup/grouping `System` port

Dart `NotificationSystem` ports AyuGram's `Window::Notifications::System` (`window/notifications_manager.cpp`).
Overall a faithful port: constants (`kMinimalDelay`/`kMinimalForwardDelay`/`kMinimalAlertDelay`/
`kWaitingForAllGroupedDelay`/`kReactionNotificationEach` — manager.cpp:64-68) match; the mute-unknown
`_settingWaiters` parking + `checkDelayed` re-evaluation, per-thread dedup `_whenMaps`, online-aware
`countTiming`, forward/album grouping, and per-scope clears (`clearForChat`/`clearForAccount`/`clearAll`)
all mirror the C++. Callbacks (`onFlashBounce`, `onQueryMuteState`, `onManagerChanged`,
`onQuerySessionOnline`, `onQueryLastSetOnlineMs`, `onRefreshChatData`, `onNewMessage`) are all wired in
`main.dart:557-681`. Sound is gated on `settings.allowSound` and per-chat volume override matches AyuGram.

Both prior deviations are fixed and verified (commit 5b9209db, Stage-2 PASS): (1) `hideMarkAsRead`
now matches `notifications_manager.cpp:1093-1096` — drops the channel/slowmode/stars conditions (those
belong only to `shouldHideReplyButton`, which retains them), uses `isReaction||isPollVote` (= `type !=
Message`), and adds the `messageId.isEmpty` (`!item`) + `((out||isSelf) && isScheduled)` clauses. (2)
`setServerConfig` is now wired: a conn-state subscription (`main.dart:706`) pulls `GetNotifyConfig`
(Go core `GetNotifyDelayConfig` → engine → bridge) on account-connect and feeds the live notify
cloud/default delays + online cloud timeout (ms→s) into `_countTiming`. No open items.

# notification_types — notification title/subtitle/body text composition

This file mirrors AyuGram's notification text pipeline (`NativeManager::doShowNotification`,
`HistoryItem::notificationText/notificationHeader`, `Media*::notificationText`,
`SpoilerLoginCode`, `TextWithPermanentSpoiler`, `TextWithForwardedChar`,
`WrapFromScheduled`, `addTargetAccountName`). It is a pure logic file — **no placeholders,
stubs, empty callbacks, mock data, or fake feedback**. Verified faithful: all lang strings
(`strings.dart:46-103`) match AyuGram's `lang.strings`; the special glyphs match exactly
(➡️ U+27A1 U+FE0F, ▚ U+259A, 📅 U+1F4C5, ➜ U+279C); the body ternary order
(pollVote→reaction→hidePreview→fwd>1→album→fwdChar), the reply-button gating
(`shouldHideReplyButton`), the login-code regex + entity-intersect guard, the 255-code-unit
truncation, and the reaction/poll-vote `reactedToType` switch all match the C++ 1:1. The
spoiler-entity masking is applied upstream (`chat_state.dart:_applySpoilerEntities`) so the
reaction/text bodies are correctly masked.

# app_state — top-level app settings/state (mirrors AyuGram `ayu_settings.*` + Telegram `core_settings*` + passcode/auto-lock)

Audited `dart/lib/state/app_state.dart` (4448 lines) against AyuGram `ayu/ayu_settings.h`/`.cpp`, `core/core_settings_proxy.h`, `ui/power_saving.h`, `main/main_domain.cpp`.

**What's faithful (verified, no issue):** every AyuGram default value matches (bubbleRadius 16, recentStickersCount 100, avatarCorners 23, deletedMark 🧹, channelBottomButton=DiscussWithFallback, showPeerId=BotApi, all context-menu visibility defaults, all drawer/message-field toggle defaults, disableAds true, etc.); the `ghostModeActive` boolean formula matches `ayu_settings.cpp:62-66` exactly; `shouldSendWithoutSound` matches `ayu_settings.cpp:112-122`; the MessageShotSettings embedded/cloud-theme logic matches `ayu_settings.cpp:263-320`; the ghost-lock "deny if it would lock all" rule matches `settings_ayu_utils.cpp:386-396`; the power-saving bitfield order + `On(flag)=ForceAll()||(Current()&flag)` matches `power_saving.h:13-40`; proxy rotation default 10 / timeouts {5,10,15,30,60} matches `core_settings_proxy.h:18-25`; translationProvider serialized as string + Native→Telegram gating matches the enum + `ayu_settings.cpp:1008-1019`. No stubs / TODO / placeholder / mock data in the file.

---

# audio_service — media-player service (port of AyuGram Media::Player::Instance)

`audio_service.dart` is a **ChangeNotifier** wrapping a `media_kit` `Player`, porting
AyuGram's `media_player_instance.cpp` (+ `media_player_listen_tracker.cpp`). It plays voice
messages and music inline, auto-pauses for calls, reports music-listen time, and saves the
last playback position. Verdict: **high-quality, faithful port — NO placeholders/stubs, and
the core path is genuinely wired** (`playVoice` is called from message bubbles / info-panel /
chat_state; `onNextTrack`/`onPreviousTrack` → `ChatState.moveAudioInPlaylist`; engine methods
`reportMusicListen`/`refreshDocumentFileRef`/`onCallState`/`onGroupCallState` are real). Every
inline-comment line reference was verified accurate against AyuGram. The findings below are
behavioral / feature-completeness gaps vs the ported class, not broken wiring.

Verified-correct (no action): play/pause/seek/stop, call pause→resume (`pauseOnCall`/
`resumeOnCall`, cpp:1089-1110), listen reporting (3s min / 60s pause-timeout / songs-only /
FILE_REFERENCE_ refresh-and-resend, matches listen_tracker.cpp:19/54/29/82-93), position
saving (20-min music threshold, read-then-clear seek, cpp:55-56/125-143/884-886), playback-speed
mapping (`_isSong` ⇒ audio vs voice speed, matches `LookupPlaybackSpeed` cpp:65-74), call-state
heuristic (engine only emits ringing/connecting/active/ended — all handled correctly).

# auth_state — Authentication flow controller (ChangeNotifier)

`auth_state.dart` is the Dart-side controller that drives the intro/auth state
machine (mirroring AyuGram's `Intro::details::Step` subclasses). It wires to the
Go engine via `EngineService.startAuth / submitAuthInput / cancelAuth` and the
`onAuthState` event stream.

Root cause shared by both findings below: **`_engine.startAuth()` is NOT a
refresh — it resets the whole flow.** Go `StartAuth` unconditionally builds a
fresh core, a fresh `initialAuthState`, and an EMPTY `collected` map, overwriting
`authFlows[accountID]` and emitting that initial state as an event
(`go/engine/auth.go:73-104`). For Telegram the initial state is `"choose"`
(method picker), never `"2fa"` or `"qr"` (`go/engine/auth.go:275`). The auth
controller calls `startAuth` as a "refresh" in the SRP-retry and QR-expiry paths,
which destroys the in-progress flow instead of refreshing it.

# chat_state — ChatState (chat list, active chat, messages, folders, forum topics, saved sublists)

Audited `dart/lib/state/chat_state.dart` (3155 lines) against AyuGram Desktop C++.
This is a state/controller class (ChangeNotifier), not a widget — no visual/dimension
findings apply. Every method is wired to the engine (no stubs, no placeholders, no
fake data). All numeric constants verified correct against AyuGram:
`_kPerPage=100`/`_kFirstPerPage=20`/`_kLoadedSublistsMinCount=20` (data_saved_messages.cpp:32-34),
`kShowTopicNamesCount`→`.take(8)` (data_forum.cpp:44), forum `>=20`/`>=500` page sizes
(data_forum.cpp:40-42), message `30`/`50` per page (history_widget.cpp:216-217),
`_maxChatOpenHistory=50` (window_session_controller.cpp:138), typing 6s
(history_view_send_action.cpp:31), login-code peer ids 333000/777000/489000
(data_peer.h:211,283-284 / data_peer.cpp:1593). The findings below are behavior/state bugs.

# telegram_palette — Telegram Desktop color palette + accent colorizer port

Audited `dart/lib/theme/telegram_palette.dart` (5476 lines) against AyuGram's
palette/colorizer sources:
- `lib_ui/ui/style/style_palette_colorizer.cpp` / `.h` (the colorize algorithm)
- `SourceFiles/window/themes/window_themes_embedded.cpp` (ColorizerFrom: ignoreKeys,
  keepContrast, lightness clamp, accent presets)
- `lib_ui/ui/colors.palette` + `Resources/{day-blue,night,night-green}.tdesktop-theme`
  + `Resources/{day,night}-custom-base.tdesktop-theme` (color values)

This is a pure data + algorithm file: no widgets, no callbacks, no engine/bridge
calls. The "placeholder/stub/backend-wiring" categories do not apply (nothing to
wire). `PaletteProvider` is a correct `InheritedWidget` (identity-based
`updateShouldNotify`). No empty callbacks, mock data, TODO/FIXME, or fake feedback.

## Findings

## Verified faithful (no action needed — recorded for the audit trail)

- **Colorize transform** (`telegram_palette.dart:1345-1373`) is a line-accurate port of
  `style_palette_colorizer.cpp:24-58`: hue shift `(h+Δ)%360`, the two-branch
  saturation formula and two-branch value formula (255-scale → 1.0-scale), and the
  `hueThreshold` gate all match. Achromatic (sat<0.01) and transparent skips are
  equivalent to Qt's `hue=-1` behavior.
- **Lightness clamp** (`:1331-1342`) matches `ColorizerFrom` (`window_themes_embedded.cpp:169-182`):
  light themes clamp HSL-L to [0,160/255], dark to [64/255,1.0]; recompute only when clamped.
- **`_cppLightness`** (`:1224-1229`) = `value - value*saturation/511` on 0-255 scale, matching
  `style_palette_colorizer.cpp:119-121`; contrast threshold 64 matches `kEnoughLightnessForContrast`.
- **`_enforceContrast`** (`:2506-3008`) reproduces the Night/NightGreen `keepContrast` map exactly
  (activeButtonFg, profileVerifiedCheckFg, overviewCheckFgActive + the 8 historyFile* in/out icon/radial
  keys), with `includeFileIcons` correctly gating Night (`windowBg==#17212b`) vs NightGreen — matching
  `window_themes_embedded.cpp:140-167`. Only runs for dark themes (light keepContrast is empty).
- **Accent presets** `dayAccents`/`nightAccents`/`nightGreenAccents` (`:1288-1299`) exactly match
  `DefaultAccentColors` (`window_themes_embedded.cpp:291-342`).
- **Palette values**: `classicDay` matches `colors.palette` defaults (0 mismatches across all resolved
  keys); `dayBlue` matches `day-blue.tdesktop-theme` (0 mismatches across 206 direct-hex keys);
  `night`/`nightGreen` match their theme files except `emojiPanHeaderBg` and `menuBgOver`, which the
  Dart stores dark while both AyuGram night source files store white (#fffffff2 / #ffffff) — almost
  certainly an opacity/fallback rendering nuance rather than a Dart bug (opaque-white menu hover would
  be visibly broken in a dark theme), so not flagged. Remaining diffs (`dialogsDateFgOver`,
  `filterInputInactiveBg`) are sub-1%/channel rounding — cosmetic.

# theme_file — Telegram Desktop theme (.tdesktop-theme) parse / export / cache

Pure-logic file (no widgets). Implements `colors.tdesktop-theme`/`colors.tdesktop-palette`
parsing, ZIP theme export, cloud-theme service-block read/write, hex color parsing,
background-image validation, and the local theme cache. It is actively used by
`state/app_state.dart` (theme load + cache) and `ui/theme_editor.dart` (import/export),
so it is not dead code.

Verified MATCHING the AyuGram C++ authority (no issue): size limits
(`window_theme.cpp:55-56`, `window_theme.h:41-42`), background priority order +
tiled flag (`window_theme.cpp:262-276`), two-stage background validation — pixel-area
cap then full decode (`window_theme.cpp:327-343`), uncompressed-size zip-bomb pre-check
(`base/zlib_help.h:258-263`), hex format `#rrggbb`/`#rrggbbaa` with alpha-last and a=255
default (`window_theme_editor.cpp:66-92`), and cloud-meta prefix format + positional-read
compatibility (`window_theme_editor.cpp:346-381`). The local cache's CRC32/structure
checksums (`theme_file.dart:1685-1709`) intentionally differ from `style::palette::Checksum()`
— the cache is JSON, local-only, never shared with AyuGram, so it only needs self-consistency.
That is correct, not a finding.

The two items below are real behavioral divergences from the C++ parser. Both only
manifest on hand-written / non-standard palette files (editor-exported themes are
complete and dependency-ordered, so they parse identically) — but per the audit rubric
the C++ source is the sole authority for behavior, and these produce observably different
results (wrong colors / accept-vs-reject) for those inputs.

# theme_preview — Theme palette preview painter (mock Telegram window: dialogs list + chat)

Renders a static preview of a color theme by drawing a fake Telegram window. This is a
direct replication of AyuGram's `Window::Theme::Generator` (`window_theme_preview.cpp`).
NOTE: the hardcoded data (names, previews, wavedata, times, peer indices, colorized spans,
bubble order/attachment) is CORRECT — it mirrors AyuGram's hardcoded `generateData()`
1:1, so it is NOT a placeholder finding. Dimensions, the peer-color map
`[0,7,4,1,6,3,5]` (= `ColorIndexToPaletteIndex`), the colorized-preview link color
(`dialogsTextFgService`), online-status color (resolves to `windowActiveTextFg`), and the
three separator shadows all match the source. Only two real deviations were found.

# wallpaper — chat background renderer (solid / gradient / pattern / image)

`wallpaper.dart` is a faithful, well-documented port of AyuGram's `image_prepare.cpp`
gradient+dither generation and `chat_theme.cpp` pattern tiling. It is fully wired:
`ChatWallpaper` is rendered in `chat_view.dart:20636` from `WallpaperProvider.of`
(fed by `main.dart:2362` ← `app_state.dart` persisted settings), and set by the user
via `chat_settings_screen.dart` / `message_bubble.dart`. No placeholders, no stubs,
no empty callbacks, no hardcoded/fake data. `computeAverageColor` runs only once per
wallpaper change (memoized in `main.dart:2329-2360` via `identical` check), so it is
not a per-frame cost.

Verified-correct ports (no action): `effectiveGradientRotation` (wallpaper.dart:52)
← `gradientRotation()` data_wall_paper.cpp:260-262; `_snapRotation` (wallpaper.dart:177)
← withUrlParams data_wall_paper.cpp:418; linear-gradient direction table
(wallpaper.dart:391-408) ← image_prepare.cpp:934-941; complex gradient swirl/4th-power
blend (wallpaper.dart:349-378) ← image_prepare.cpp:255-289; dither tiers
(wallpaper.dart:446-453) ← image_prepare.cpp:887-895; pattern softLight/dstIn + black-fill
(wallpaper.dart:901-932) ← chat_theme.cpp:1117-1128; invert color-matrix
(wallpaper.dart:885-890) ← InvertPatternImage chat_theme.cpp:1156-1171; IsPatternInverted
(wallpaper.dart:978-989) ← chat_theme.cpp:925-929; ThemeAdjustedColor (wallpaper.dart:1029)
← chat_theme.cpp:932-938; preprocess crop/scale (wallpaper.dart:1054-1073) ←
PreprocessBackgroundImage chat_theme.cpp:949-964; pattern tiling odd-cols/xshift
(wallpaper.dart:958-976) ← CacheBackgroundByRequest chat_theme.cpp:172-184.

# admin_tools — Group/Channel/Bot admin tools (edit peer, permissions, admin rights, invite links, members, admin log, statistics/boosts/earn)

Audited `dart/lib/ui/admin_tools.dart` (8523 lines) against AyuGram Desktop C++ source. AyuGram C++ is the sole authority. Every finding cites both files with line numbers and was confirmed by reading the cited AyuGram lines. MINOR/COSMETIC findings omitted.

The engine wiring is broadly real (no fake snackbars, no empty `onTap`s in the happy path) — the issues below are wrong gating/flag-sets, missing server-side preconditions (users hit API errors), data the UI can't actually read (shows wrong state), and whole interactive sub-features reduced to read-only.

## _EditPeerPermissionsBox / _EditRestrictedBox (default banned rights + per-user restriction)

- [ ] [MAJOR] `boostsUnrestrict` is saved unconditionally, but AyuGram only persists a non-zero value when send-restrictions or slowmode are actually active (`hasRestrictions ? state->boostsUnrestrict.current() : 0`); Dart always writes `_boostsUnrestrict` so a stale boost-threshold is applied with no restrictions to bypass — `admin_tools.dart:2678` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_permissions_box.cpp:1259`
- [ ] [MAJOR] Boosts-to-unrestrict control is structurally wrong: AyuGram uses a 5-position slider (values 1..5 via `BoostsUnrestrictByIndex = index+1`) whose "off" state is a *separate* `lng_rights_boosts_no_restrict` toggle, and the whole slider is shown only when `hasSendRestrictions`. Dart uses a permanently-visible 6-position slider `[0,1,2,3,4,5]` with no gating, so the control appears even when nothing is restricted — `admin_tools.dart:2589` / `admin_tools.dart:2771` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_permissions_box.cpp:961` (toggle) + `:1226` (gating)
- [ ] [MAJOR] `_EditRestrictedBox` never loads/pre-selects the member's existing ban expiry: it hard-defaults `_duration = forever` and `_loadDefaults()` reads only `banned_rights`, never an `until` value, so re-editing a temporarily-restricted user silently resets the ban to forever. AyuGram seeds `_until = prepareRights.until` and `createUntilVariants()` adds the current expiry as a radio. (Root cause is also engine-side: `GetParticipantInfo` omits `ChannelParticipantBanned.BannedRights.UntilDate`.) — `admin_tools.dart:3336` / `admin_tools.dart:3417` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participant_box.cpp:796`
- [ ] [MAJOR] Custom "Banned until" can silently collapse to forever: tapping `Custom...` then dismissing the date picker leaves `_customDate` null, so `_computeUntilDate()` returns `0` (forever) while the "Custom..." radio stays selected — Save bans forever instead of the intended finite duration. AyuGram reverts the radio group to the previous value when `ChooseDateTimeBox` is cancelled (and that box enforces `min = now`) — `admin_tools.dart:3437` / `admin_tools.dart:3850` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participant_box.cpp:1019`

(Verified matching, not flagged: the `_sendPlain` + 9-item `_mediaFlags` + 5-item `_otherFlags` set/order/nesting matches `NestedRestrictionLabelsList` exactly incl. collapsed Stickers&GIFs; slowmode values/labels match `SlowmodeDelayByIndex`; `kDefaultChargeStars=10`, `kMaxRestrictDelayDays=366` match; the `send_plain`↔`embed_links` lock matches the `{EmbedLinks, SendOther}` dependency.)

## _EditAdminBox (admin rights + ownership transfer)

- [ ] [CRITICAL] Transfer Ownership gating is wrong: Dart shows the Transfer button only when EVERY admin flag is toggled on (`_allOwnerRightsSelected`). AyuGram gates the button's existence on `canTransferOwnership()`, which requires only `amCreator()` (and a non-bot/non-self/accessible target) — a creator promoting any normal admin should always see Transfer regardless of which rights are checked — `admin_tools.dart:3967` / `admin_tools.dart:4291` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participant_box.cpp:654`
- [ ] [CRITICAL] Dart never checks `amCreator`/`isSelf`/`isBot`/`isInaccessible` before offering Transfer Ownership; AyuGram's `canTransferOwnership()` returns false for inaccessible/bot/self targets and otherwise requires the editor be the creator. Dart will render Transfer for a non-owner editor or when editing a bot/self once all toggles happen to be on — `admin_tools.dart:4291` / `admin_tools.dart:4139` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participant_box.cpp:654`
- [ ] [MAJOR] Transfer "all rights" set wrongly includes `anonymous`: AyuGram's `AdminRightsForOwnershipTransfer` explicitly skips `ChatAdminRight::Anonymous`, but Dart's group `_allFlags` includes `anonymous` and requires it enabled, so a group owner must turn on "Remain anonymous" just to see Transfer — `admin_tools.dart:4027` / `admin_tools.dart:3960` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_permissions_box.cpp:1465`
- [ ] [MAJOR] 2FA transfer flow has no pre-flight password-state check and no specific error handling. AyuGram first probes with `messages_EditChatCreator`+`inputCheckPasswordEmpty`, routes through `PrePasswordErrorBox` (special-casing `PASSWORD_MISSING` → "enable 2FA", `PASSWORD_TOO_FRESH_*`/`SESSION_TOO_FRESH_*` → "wait"), and on submit handles `CHANNELS_ADMIN_PUBLIC_TOO_MUCH`/`ADMINS_TOO_MUCH`/etc. Dart just collects a password and shows any failure as a generic `Transfer failed: $e` toast — `admin_tools.dart:4189` ← `AyuGram/Telegram/SourceFiles/boxes/peers/channel_ownership_transfer.cpp:31`
- [ ] [MAJOR] Custom-title (rank) field is shown for broadcast channels, but AyuGram gates it on `hasRank = canSave() && (chat || channel->isMegagroup())` — never added for a broadcast channel. Dart builds `_buildRankField` for both paths, so a channel admin gets a "Custom Title" input that has no effect — `admin_tools.dart:4289` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participant_box.cpp:477`

(Verified matching, not flagged: channel and group admin-flag sets/order/sectioning match `AdminRightLabels`/`NestedAdminRightLabels` incl. ManageTopics-only-when-forum and ManageRanks between ManageCall/Anonymous; rank `maxLength:16` matches `kRankLimit`.)

## _EditPeerInfoBox (edit channel/group/bot)

- [ ] [CRITICAL] "Verify Accounts" dialog shows wrong per-user verified state — it cannot read `peer->botVerifyDetails()` so it starts EVERY contact as "not verified by this bot" and only reflects this-session toggles (its own comment admits this). AyuGram derives the real state from `details && details->botId == peerToUser(_bot->id)`. A user already verified by this bot shows as unverified, and tapping re-sends Setup instead of Remove — `admin_tools.dart:1889` ← `AyuGram/Telegram/SourceFiles/boxes/peers/verify_peers_box.cpp:92`
- [ ] [MAJOR] Channel "Affiliate Program" row is the wrong surface and will error server-side: it opens the create-your-own-program flow (`setStarRefProgram` commission/duration), but in AyuGram the program-SETUP flow is bot-only (`Setup::Allowed` requires the peer be a bot). A channel's only star-ref entry is the JOIN flow (advertising other bots' programs); channels cannot own a star-ref program — `admin_tools.dart:2000` / `admin_tools.dart:1815` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_info_box.cpp:1663`
- [ ] [MAJOR] Color & Emoji change is not gated on boost level — Dart calls `updateChannelColor` directly. AyuGram's `Apply()` always runs `CheckBoostLevel()` for non-self peers and shows an AskBoost box (cancelling the change) when `level < required`. On a low-boost channel the Dart save hits a server error instead of prompting to boost — `admin_tools.dart:1384` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_color_box.cpp:636`
- [ ] [MAJOR] Color & Emoji row gating is wrong — shown unconditionally for every non-bot peer (incl. legacy basic groups and members without ChangeInfo). AyuGram gates `fillColorIndexButton` on `canEditColorIndex = isChannel && channel->canEditEmoji()` (a `ChannelData` whose editor is creator or ChangeInfo admin) — `admin_tools.dart:600` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_info_box.cpp:1495`
- [ ] [MAJOR] Reactions dialog ("Some" mode) ignores the custom-reaction limit, max-count slider, and paid-reaction toggle that AyuGram enforces. `EditAllowedReactionsBox` rejects save / calls `askForBoosts` when custom count exceeds the boost allowance, exposes a max-count slider, and a paid-reactions toggle for broadcasts. Dart lets the user pick any number of emoji with none of these, so over-limit selections are rejected server-side — `admin_tools.dart:1128` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_reactions.cpp:816`
- [ ] [MAJOR] "Direct Messages" dialog cannot turn the feature OFF and omits the enable toggle. AyuGram's `EditDirectMessagesPriceBox` has an "Allow direct messages" toggle that, when off, sends a disabled value. The Dart bare number field treats empty as `0` (free but still ENABLED) and always sends `broadcastEnabled: result >= 0`, so there is no way to disable direct messages — `admin_tools.dart:1404` ← `AyuGram/Telegram/SourceFiles/boxes/edit_privacy_box.cpp:1314`
- [ ] [MAJOR] Direct Messages row not gated on `canEditInformation`. AyuGram gates it on `isChannel && isBroadcast() && canEditInformation()`; Dart shows it for any `chat.type == channel`, so an admin without ChangeInfo sees it and hits a server error on save — `admin_tools.dart:705` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_info_box.cpp:1473`

## _InviteLinksBox / _CreateEditLinkForm / _LinkInfoBox

- [ ] [CRITICAL] Per-link joined-members list and join-requests (approve/dismiss) UI is entirely missing from the single-link info box. AyuGram's `ShowInviteLinkBox` renders a "created by" row, the list of users who joined via the link (`GetChatInviteImporters` slices), and a "Requests to join" block with per-user Add/Dismiss when the link needs approval; Dart's `_LinkInfoBox` shows only static counts, and `getChatInviteImporters` is not wired in the engine — `admin_tools.dart:6234` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_invite_link.cpp:592`
- [ ] [MAJOR] Subscription (star-credits) toggle is shown for groups; AyuGram passes `fillSubscription = nullptr` for groups so it never appears. Dart's `_CreateEditLinkForm` has no group/channel awareness and always renders it — `admin_tools.dart:6623` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_invite_link.cpp:1623`
- [ ] [MAJOR] Subscription toggle is shown for public channels; AyuGram gates it on `!isPublic`. Dart shows it unconditionally — `admin_tools.dart:6623` ← `AyuGram/Telegram/SourceFiles/ui/boxes/edit_invite_link.cpp:136`
- [ ] [MAJOR] Approve-New-Members toggle is shown for public channels; AyuGram sets `requestApproval = (isPublic || subscriptionLocked) ? nullptr` so it is hidden for public channels. Dart only hides it for `_subscriptionLocked` — `admin_tools.dart:6610` ← `AyuGram/Telegram/SourceFiles/ui/boxes/edit_invite_link.cpp:112`
- [ ] [MAJOR] Editing/revoking links created by a bot admin is not suppressed. AyuGram hides Edit/Revoke when `admin->isBot()`; the Dart context menu and info-box always show Edit/Revoke for any non-revoked link regardless of creator — `admin_tools.dart:5864` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_invite_link.cpp:484`

## _MemberListScreen / _MemberTabBody / _MemberRow

- [ ] [CRITICAL] Add Admin/Exception/Banned uses a free-text "Enter username or user ID" TextField + `resolveUsername`/numeric-ID parse instead of AyuGram's searchable participant/contact `PeerListBox` picker (`AddSpecialBoxController`: search-enabled list, click row to select, searches participants→members→contacts→global). Raw numeric IDs and free-text resolution are not how AyuGram adds special members — `admin_tools.dart:7151` ← `AyuGram/Telegram/SourceFiles/boxes/peers/add_participants_box.cpp:1234`
- [ ] [CRITICAL] "Add Member" is likewise a free-text dialog rather than AyuGram's `ContactsBoxController` multi-select contact picker (`AddParticipantsBoxController`) — `admin_tools.dart:7039` ← `AyuGram/Telegram/SourceFiles/boxes/peers/add_participants_box.cpp:768`
- [ ] [CRITICAL] No permission gating on row context-menu actions: Promote/Restrict/Remove are shown for every member/admin row unconditionally, whereas AyuGram gates them via `canAddOrEditAdmin`/`canRestrictParticipant`/`canRemoveParticipant` (can't act on the creator, yourself, or an admin you didn't promote). `MemberInfo` carries no permission/identity flags (`canEditAdmin`/`canRestrict`/`isSelf`/`adminRights`), so the UI has no data to gate on (root cause at `dart/lib/models/engine_models.dart:1909`) — `admin_tools.dart:7356` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participants_box.cpp:1962`
- [ ] [MAJOR] Admins-tab row menu shows "Promote to Admin" for users who are already admins; AyuGram shows "Edit admin rights" when the target already has admin rights and "Promote" only for non-admins — `admin_tools.dart:7357` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participants_box.cpp:1962`
- [ ] [MAJOR] Removed/Kicked-tab menu only offers "Unban"; AyuGram offers "Add to group" (unkick + re-add, gated on `canAddMembers`) AND "Delete" (remove from the removed list) — `admin_tools.dart:7368` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participants_box.cpp:1946`
- [ ] [MAJOR] Members-tab menu hard-codes "Remove from Group"; AyuGram uses `lng_profile_kick`/"Remove" for broadcast channels (`isGroup ? remove_from_group : profile_kick`), so the label/semantics are wrong for channels — `admin_tools.dart:7361` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participants_box.cpp:1990`
- [ ] [MAJOR] Always renders all 5 fixed tabs and always shows the Add button for admins/restricted/kicked, regardless of peer type/rights; AyuGram chooses roles per peer (non-megagroup broadcast has no restrict-without-kick path) and gates each Add button on `canAddNewItem` (`canAddMembers`/`canAddAdmins`/`canBanMembers`) — `admin_tools.dart:6958` / `admin_tools.dart:7034` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participants_box.cpp:1086`

(Verified matching, not flagged: Requests Add/Dismiss fire immediately + remove row + show the add toast, matching `processRequest`; requested-status text matches `PrepareRequestedRowStatus`.)

## _AdminLogScreen / _AdminLogEventTile / _AdminLogFilterDialog

- [ ] [MAJOR] Filter dialog is missing the per-admin selector entirely — AyuGram's FilterBox renders an "All admins" checkbox plus an expandable list of every admin and passes the chosen users as `filter.admins`; Dart's `_AdminLogFilterDialog` only has action-type checkboxes and can never filter by which admin acted — `admin_tools.dart:5346` ← `AyuGram/Telegram/SourceFiles/history/admin_log/history_admin_log_inner.cpp:522`
- [ ] [MAJOR] Edit/Delete/Pin/Send-message events are reduced to a single plain-text service line (plus a text-only quoted block for edits), dropping the actual message bubble and all media. AyuGram builds a real `history->createItem(PrepareLogMessage(...))` so the message renders as a full bubble (photo/video/file/sticker/caption); Dart only shows `event.msgText`, so media-only entries render blank and media+caption render caption-only — `admin_tools.dart:5124` ← `AyuGram/Telegram/SourceFiles/history/admin_log/history_admin_log_item.cpp:1027`
- [ ] [MAJOR] `toggle_autotranslation` and `participant_edit_rank` events display a raw Go type string instead of localized text — AyuGram fully renders both (autotranslate enabled/disabled, the set/changed/removed-rank family), but the Go core has no case for these actions and returns the `%T` type name, so Dart's `default` branch shows e.g. `*tg.ChannelAdminLogEventActionToggleAutotranslation` on screen (the matching Dart cases at 5321/5323 are dead code) — `admin_tools.dart:5334` ← `AyuGram/Telegram/SourceFiles/history/admin_log/history_admin_log_item.cpp:2155`

(Verified matching, not flagged: filter flag categories match `FilterValue::Flag` 1:1 incl. channel-vs-group hiding of Topics/Pinned; text search is genuinely supported by AyuGram.)

## _StatisticsScreen / _StatChart / _BoostsScreen / _MonetizationScreen

- [ ] [CRITICAL] Monetization has no withdraw action: `_MonetizationScreen` shows a read-only balance with a static "Withdrawal is available" note, while AyuGram renders a real withdraw `RoundButton` wired to `Api::HandleWithdrawalButton`/`AddWithdrawalWidget` that launches the withdrawal flow — `admin_tools.dart:8478` ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/earn/info_channel_earn_list.cpp:917`
- [ ] [MAJOR] Monetization omits TON/currency ad-revenue entirely; AyuGram's earn section shows BOTH currency (TON) revenue and Stars (credits) revenue with their own overview/balance/charts, but `_MonetizationScreen` only calls `getStarsRevenueStats` (Stars-only); the engine never fetches broadcast revenue stats so TON revenue + revenue charts are absent — `admin_tools.dart:8378` ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/earn/info_channel_earn_list.cpp:611`
- [ ] [MAJOR] Monetization omits the transaction-history list; AyuGram builds a tabbed history (currency + credits) with paginated "Show more" and per-entry detail boxes — `admin_tools.dart:8454` ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/earn/info_channel_earn_list.cpp:1288`
- [ ] [MAJOR] Statistics silently drops every async-loaded graph: `_StatChart.parse` skips any chart whose inline `data` is empty (`// skip async-only graphs`), but the engine provides `async_token` for `StatsGraphAsync` graphs and AyuGram loads them on demand via `requestZoom(token, 0)` — so whole graphs render as nothing — `admin_tools.dart:7736` ← `AyuGram/Telegram/SourceFiles/info/statistics/info_statistics_inner_widget.cpp:154`
- [ ] [MAJOR] Statistics ignores chart `type`: every series is drawn as a plain line via `_StatGraphPainter`, but each graph is tagged (StackBar/StackLinear/DoubleLinear/Bar) and AyuGram renders bar/stacked/pie chart types accordingly — `admin_tools.dart:7983` ← `AyuGram/Telegram/SourceFiles/info/statistics/info_statistics_inner_widget.cpp:213`
- [ ] [MAJOR] Recent-posts rows are non-interactive: `_RecentPostRow` has no tap action, but AyuGram makes each post a button that opens per-message statistics (`messageStatistic`) plus a "Show in chat" context menu — `admin_tools.dart:7895` ← `AyuGram/Telegram/SourceFiles/info/statistics/info_statistics_inner_widget.cpp:849`
- [ ] [MAJOR] Recent-post preview content is missing: the engine returns `text`/`date`/`media_type`/`thumb_b64` per post, but `_RecentPostRow` shows only views/forwards/reactions — AyuGram renders a full `MessagePreview` (text + thumbnail) — `admin_tools.dart:7892` ← `AyuGram/Telegram/SourceFiles/info/statistics/info_statistics_inner_widget.cpp:822`
- [ ] [MAJOR] Megagroup statistics omits the Top Senders / Top Administrators / Top Inviters member lists entirely; the generic `_StatisticsScreen` only renders humanized overview cards + charts, while AyuGram fills three `AddMembersList` sections for supergroups — `admin_tools.dart:7748` ← `AyuGram/Telegram/SourceFiles/info/statistics/info_statistics_inner_widget.cpp:743`
- [ ] [MAJOR] Boosts screen has no Create-Giveaway / "Get Boosts via Gifts" action; AyuGram's box ends with `FillGetBoostsButton` opening `CreateGiveawayBox`. The feature is fully built in this repo (`create_giveaway_box.dart`, wired in `info_panel.dart`) but `_BoostsScreen` never calls it — `admin_tools.dart:8247` ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/boosts/info_boosts_inner_widget.cpp:532`
- [ ] [MAJOR] Boosts screen has no Boosts/Gifts tab switcher; AyuGram shows two tabs (`firstSliceBoosts` vs `firstSliceGifts`) and `getBoostsList` already accepts `isGifts`, but `_BoostsScreen` only loads the default boosts slice as one flat list — `admin_tools.dart:8115` ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/boosts/info_boosts_inner_widget.cpp:455`
- [ ] [MAJOR] Boosts screen omits the invite/share-link block and prepaid-giveaway rows; AyuGram renders `FillShareLink` (copy/share) and a prepaid-giveaway list, and the engine returns `boost_url` + `prepaid_giveaways`, but `_BoostsScreen` shows neither — `admin_tools.dart:8193` ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/boosts/info_boosts_inner_widget.cpp:341`

# advanced_settings_screen — Advanced settings page (§14.7): update, data/storage, auto-download, window title/close, system integration, performance, spellchecker, screen reader, export, proxies, power saving, experimental flags

This file was audited in full against AyuGram `settings/sections/settings_advanced.cpp` and the
boxes it opens (`auto_download_box.cpp`, `local_storage_box.cpp`, `connection_box.cpp`,
`dictionaries_manager.cpp`, `download_path_box.cpp`, `settings_power_saving.cpp`,
`settings_experimental.cpp`). The implementation is unusually faithful. Verified as correct
(NOT findings):

- Section build order matches `kMeta` exactly (update-top when !autoUpdate → data/storage →
  auto-download → window title → window close → system integration → performance → spellchecker →
  screen reader → update-bottom → export). `advanced_settings_screen.dart:99-111` ← `settings_advanced.cpp:1241-1261`
- Power-saving flags: all 11 flags, correct group order, battery-gated auto toggle, force-disable
  overlay. `advanced_settings_screen.dart:2695-2722` ← `ui/power_saving.h:13-25` + `settings_power_saving.cpp:142-189`
- Experimental flags: all 29 ids in exact registration order. `advanced_settings_screen.dart:4716-4746` ← `settings_experimental.cpp:284-314`
- Auto-download size-limit curve reproduces `SizeLimitByIndex` exactly (100-step piecewise).
  `advanced_settings_screen.dart:1642-1652` ← `export/view/export_view_settings.cpp:89-113`
- Local-storage ladders: 18/18 size steps, 16 time steps, 100 MB floor + both clamp directions.
  `advanced_settings_screen.dart:1880-1956` ← `local_storage_box.cpp:32-58,496-533`
- Proxy link parse + MTProto secret validation faithfully reproduce `proceedUrl` /
  `MtprotoPasswordStatus`. `advanced_settings_screen.dart:3866-3975` ← `connection_box.cpp:305-366` + `mtproto_proxy_data.cpp:16-159`
- "Use proxy for calls" correctly omitted (`supportsCalls()==false`). `advanced_settings_screen.dart:2912-2915` ← `mtproto_proxy_data.cpp:161-163`
- All engine calls exist and do real work — `CheckProxy` is a real DC-connect ping
  (`engine/engine.go:443`), `GetCacheSizesByTag`/`ClearCacheByTag` (`engine/media.go:274,385`),
  `SetExperimentalFlag` (`engine/engine.go:416`), and AppState forwards `SetProxy` /
  `SetAutoDownload` / `SetLocalStorageLimits` to every account (`app_state.dart:2666-2701,2716`).
  No stubs, no placeholders, no fake data, no empty callbacks.

## Findings

- [ ] [MAJOR] Windows "Close to taskbar" checkbox is missing. On Windows (no tray present),
  AyuGram shows a `Close to taskbar` checkbox inside System Integration that toggles the close
  behavior between `CloseToTaskbar` and `Quit`. The Dart `_buildWindowCloseBehavior` returns `[]`
  on any non-Linux platform, and `_buildSystemIntegration` only adds a Windows branch for
  "Add to Send to menu" — so a Windows user with the tray disabled has no control over what
  closing the window does (the Linux radio group is the only close-behavior UI). —
  `advanced_settings_screen.dart:748-777` (Linux-only early return) and `advanced_settings_screen.dart:879-887` (only Windows branch in System Integration) ← `settings_advanced.cpp:585-621` (`#elif defined Q_OS_WIN` closeToTaskbar checkbox, shown via `!Core::App().tray().has()`)

# auth_screen — Telegram intro/login flow (choose · QR · phone · email · OTP · 2FA · signup)

Overall this file is a high-fidelity port. Every interactive element is wired to the
real engine via `AuthState` (`submitInput`, `switchToMethod`, `cancelAuth`,
`updateConfig`, `uploadProfilePhoto`) — no empty callbacks, no mock data, no
"coming soon" stubs. Dimensions/colors track the `.style` values closely
(cover 208px, code cell 40×50/4px border/10px gap, QR 180/12/44, 2FA tops
74/151/220, next-slide 200). The findings below are behavioral-fidelity gaps vs
AyuGram, not broken wiring.

- [ ] [MAJOR] Code step replaces AyuGram's call-status display with a generic resend UI. AyuGram shows a countdown of *when Telegram will auto-call the phone* (`lng_code_call`), then status text `lng_code_calling` → `lng_code_called`, and has **no** manual resend button — the call/resend fires automatically. The Dart labels it "Resend code in M:SS", and after reaching 0 auto-fires resend **and** also renders an extra manual "Resend code" button that AyuGram never shows, with no Calling/Called status states. — `auth_screen.dart:2147` (countdown/button block) + `auth_screen.dart:1803` (`_startCallTimer` auto-fire) ← `AyuGram/intro/intro_code.cpp:117` (`updateCallText` Waiting/Calling/Called) + `AyuGram/intro/intro_code.cpp:302` (`sendCall`)

- [ ] [MAJOR] QR login step is missing the passkey login link. AyuGram's QR step conditionally shows a "Log in with passkey" `LinkButton` (when `settingsDisplayPasskeys()` and `WebAuthn::IsSupported()`) that runs the full WebAuthn passkey login flow. `_buildQR` renders only the QR card, 3 instruction steps, and the "Log in by phone number" link — there is no passkey affordance at all. — `auth_screen.dart:1091` (`_buildQR`) ← `AyuGram/intro/intro_qr.cpp:364` (`setupPasskeyLink`)

- [ ] [MAJOR] Auth screen is not localized despite exposing a "Change Language" control. AyuGram builds every intro string from the lang pack (`tr::lng_phone_title`, `tr::lng_intro_qr_step1..3`, `tr::lng_signin_desc`, etc.), so picking a language re-renders the intro in that language. Here the "Change Language" button calls `EngineService.updateConfig(language:)` (real engine call), but the auth UI text is hardcoded English literals ('Enter Phone Number', 'Scan QR Code', 'Next', the QR instructions, all dialogs…) and the few `TrStrings.*` helpers also return English (i18n is an app-wide pending item, `l10n/strings.dart:2`). Net effect: selecting a non-English language does not translate this screen, unlike AyuGram. App-wide root cause, but most visible here because the picker lives on this screen. — `auth_screen.dart:550` (`_title` literals) + `auth_screen.dart:2324` (Change Language → updateConfig) ← `AyuGram/intro/intro_phone.cpp:92` (`setTitleText(tr::lng_phone_title())` / `setDescriptionText(tr::lng_phone_desc())`)

# ayu_appearance_page — AyuGram Appearance settings (App Icon, Avatar Corners, MD3/backgrounds/mono-font, Chat Folders, Tray & Drawer elements)

Compared against `ayu/ui/settings/settings_appearance.cpp`, `ayu/ui/components/icon_picker.cpp`,
`ayu/ui/components/avatar_corners_preview.cpp`, `ayu/ui/ayu_userpic.cpp`, `ayu/ui/boxes/font_selector.cpp`.

**Verified correct (no findings):** all toggles wired to `AppState` setters 1:1 with AyuGram getters/setters;
App-Icon picker has all 12 assets present + registered in pubspec (not a placeholder), 4 columns / 64px icon /
68px-12r selection highlight match `kColumns=4` + `iconPickerIconSize=64` + `iconPickerSelectedRounding=12`;
avatar radius formula `corners/23 * size/2` matches `ComputeRadius`; `kMaxAvatarCorners=23`, slider steps `23+1`,
`photoSize=46`, `dialogsRowHeight=62` all match; restart prompt and live icon-apply (MethodChannel) are real, not stubs.

- [ ] [MAJOR] "Appearance" subsection title is missing — the MD3 Switch / Disable custom backgrounds / Hide premium statuses / Monospace font group has no header. AyuGram's `BuildAppearance` opens with `builder.addSubsectionTitle(tr::ayu_CategoryAppearance())` ("Appearance", lang.strings:7979) before MaterialSwitches; the Dart jumps straight from `addSectionDivider()` to the MD3 Switch toggle with no `addSectionTitle('Appearance')` (every other group — App Icon, Chat Folders, Tray Elements, Drawer Elements — does get its title). — `ayu_appearance_page.dart:57-59` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_appearance.cpp:191`

- [ ] [MAJOR] Avatar-corners preview rendered as an inset rounded card instead of a full-width dialog row, shifting its content ~10px out of alignment. AyuGram's `AvatarCornersPreview` is added with horizontal margin 0 (`settings_appearance.cpp:152-154`) and paints a full-width row whose avatar sits at the standard 22px settings indent (`userpicX = row.padding.left() + xShift = 10 + (22-10) = 22`) with a full-width rectangular ripple (`RippleAnimation::RectMask(size())`). The Dart wraps it in `Padding(horizontal: 22)` + `Material(borderRadius: 8)` + InkWell, so the avatar lands at 22+10 = 32px (10px right of the "Avatar Corners" title at 22px and all other settings rows) and the ripple is a rounded inset card, not the edge-to-edge row. — `ayu_appearance_page.dart:498-534` ← `AyuGram/SourceFiles/ayu/ui/components/avatar_corners_preview.cpp:43-78`

- [ ] [MAJOR] Empty-userpic fallback uses wrong initials, wrong color algorithm, flat fill, and corner shape. AyuGram builds `_emptyUserpic` from `Data::DecideColorIndex(peerFromChannel(ChannelId(2331068091)))` → one of 8 *gradient* color pairs, derives initials "AR" (first letter + letter after the space in "AyuGram Releases", `empty_userpic.cpp:656-672`), and always paints a **circle** (`paintCircle`, `avatar_corners_preview.cpp:63`) regardless of the corner setting. The Dart hardcodes a flat 8-color palette indexed by `'AyuGramReleases'.hashCode.abs() % 8` (different index → likely different color), shows a single "A", a flat fill, and corner-shapes the fallback with `avatarRadius` so at corners=0 it's a square, not a circle. — `ayu_appearance_page.dart:476-496` ← `AyuGram/SourceFiles/ayu/ui/components/avatar_corners_preview.cpp:29-33,63`

- [ ] [MAJOR] Font selector box is missing the "No fonts found." empty state. AyuGram's font box shows a centered "No fonts found." label (toggled on when the filtered list is empty, `font_selector.cpp:696-717`). The Dart font box renders an empty `ListView.builder` (itemCount 0) with no message when a search matches nothing — only the loading spinner state exists. — `ayu_appearance_page.dart:935-974` ← `AyuGram/SourceFiles/ayu/ui/boxes/font_selector.cpp:702-705`

# ayu_chats_page — AyuGram "Chats" settings section (Settings::AyuChats)

Audited `dart/lib/ui/ayu_chats_page.dart` against `ayu/ui/settings/settings_chats.cpp`
(+ `message_preview.cpp`, `ayu_builder.cpp`, `settings_ayu_utils.cpp`, `ayu_icons.style`).

Structure maps 1:1: Stickers&Emoji, Recent stickers slider, Groups/Channels, Marks +
message preview, bubble radius + wide multiplier, context-menu elements, message-field
elements, message-field popups. All toggles/choose-buttons/edit-mark box are wired to real
`AppState` setters — no empty callbacks, no TODOs, no fake snackbars, no stubs. The message
preview is a faithful hand-drawn approximation (the C++ renders a real `HistoryView::Element`,
impossible in pure Flutter) wired to the live settings. Issues below are behavioral/perf
deviations, not placeholders.

- [ ] [MAJOR] "Hide Reactions" master toggle uses ALL-semantics instead of AyuGram's ANY-semantics: the `addCollapsibleToggle` call omits `toggledWhenAll`, so it defaults to `true` (`ayu_section_builder.dart:116`), computing the master state as "checked only when every child is checked" (`ayu_section_builder.dart:713-715`). AyuGram passes `.toggledWhenAll = false`, so the master is checked when `count != 0` i.e. ANY child checked (`settings_ayu_utils.cpp:216-222`). Result: when only some reaction types are hidden, the Dart "Hide Reactions" toggle shows OFF and clicking it *hides all*, whereas AyuGram shows ON and clicking *un-hides all* — wrong displayed state + inverted click result. — `ayu_chats_page.dart:34-61` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_chats.cpp:67`

- [ ] [MAJOR] "Recent Stickers Count" slider persists + rebuilds the whole page on every drag frame. The slider is wired with `onChanged: (v) => appState.setRecentStickersCount(v)` and NO `onFinalChanged` (`ayu_chats_page.dart:63-70`); `_AyuSlider` fires `onChanged` on every drag frame (`ayu_section_builder.dart:514-518`) and `setRecentStickersCount` calls `notifyListeners()` (`app_state.dart:2274`), forcing a full `AyuChatsPage` rebuild each frame (page is `context.watch<AppState>()`, `ayu_chats_page.dart:18`). AyuGram sets `.onChanged = nullptr` (label-only live update) and persists only in `.onFinalChanged` on release — the exact per-frame-rebuild pattern the bubble/wide sliders were hand-written to avoid, reintroduced here. — `ayu_chats_page.dart:63-70` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_chats.cpp:82-87`

- [ ] [MAJOR] Bubble-radius live preview is missing during drag. The message preview reads `appState.bubbleRadius` (`ayu_chats_page.dart:117`), but `_BubbleRadiusSlider.onChanged` only updates its own local value label (`ayu_chats_page.dart:522-524`) and persists to AppState solely in `onChangeEnd` (`ayu_chats_page.dart:525-531`), so the preview bubble corners change only on release. AyuGram's slider `onChanged` calls `previewState->widget->setBubbleRadius(index)` every frame (`settings_chats.cpp:255-259`), which re-renders the preview live (`message_preview.cpp:194-200`). The preview-next-to-slider exists precisely for live feedback that Dart loses. — `ayu_chats_page.dart:178-182` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_chats.cpp:255-259`

- [ ] [MAJOR] Message-Field Elements (7 rows) and Message-Field Popups (2 rows) are missing their leading icons. Dart calls `addSettingToggle` with no `icon:` for Attach/Commands/TTL/Emoji/Voice/Gift/AI-Editor (`ayu_chats_page.dart:216-257`) and Attach-popup/Emoji-popup (`ayu_chats_page.dart:263-274`), though the builder fully supports icons (`ayu_section_builder.dart:50-57`) and the context-menu section right above does pass them. AyuGram gives every one of these toggles an icon (`.icon = { &st::messageFieldAttachIcon }` …`messageFieldCocoonAiIcon`), which are real defined icons (`ayu_icons.style:26-36`); presence of an icon also switches the row to the wider icon layout (`ayu_builder.cpp:75`), so Dart additionally uses the wrong (22px no-icon) row inset for these 9 rows. — `ayu_chats_page.dart:216-274` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_chats.cpp:386-428`

# ayu_filters_page — Regex Filters settings (shared/shadow-ban/per-dialog + import/export)

Audited against AyuGram's regex-filters feature: `ayu/ui/settings/settings_filters.cpp`,
`ayu/ui/settings/filters/settings_filters_list.cpp`, `edit_filter.cpp`, `per_dialog_filter.cpp`,
`ayu/features/filters/filters_utils.cpp`, `ayu/ui/boxes/import_filters_box.cpp`,
`info/info_wrap_widget.cpp`. Backend wiring is solid — every toggle/menu/row callback calls the
real `AyuFilterEngine`/`AppState` (rebuildCache + notifyListeners), the import/export engine posts
to dpaste and round-trips the v2 backup JSON, and `context.select` rebuilds the list correctly
(all mutators reassign new list instances). Two genuine deviations found.

- [ ] [MAJOR] `_ShadowBanRow` fallback-avatar color uses the wrong palette-remap table `[0, 2, 4, 1, 6, 3, 5]` (index 1 = `2`) instead of AyuGram's `ColorIndexToPaletteIndex` map `[0, 7, 4, 1, 6, 3, 5]`. AyuGram paints the unknown-peer userpic via `EmptyUserpic::UserpicColor(realId % 7)` which indexes through this map. For any shadow-banned peer with `id % 7 == 1` and no downloaded avatar, the Dart shows `historyPeer3UserpicBg` instead of the correct `historyPeer8UserpicBg`. This is a single-character typo: the sibling `_PerDialogFilterRow` in this same file uses the correct `_kUserpicColorRemap` (`ayu_filters_page.dart:533`), and all 20 other `_colorRemap` definitions across the codebase use `[0, 7, 4, 1, 6, 3, 5]`. — `ayu_filters_page.dart:1303` (used at `ayu_filters_page.dart:1265`) ← `AyuGram/Telegram/SourceFiles/ui/chat/chat_style.cpp:1205` (and `ui/empty_userpic.cpp:293`, `ayu/ui/settings/filters/per_dialog_filter.cpp:53-54`)

- [ ] [MAJOR] Import box does not auto-select "URL" mode when the clipboard holds a URL. AyuGram initializes the radio group to `clipboardHasUrl` (`intoURL = RadioenumGroup<bool>(clipboardHasUrl)`) and shows the prefilled URL field, so the "copy share link → Import → click Import" flow fetches from the link. The Dart hardcodes `_useUrl = false` and only prefills `_urlController` (which is hidden while `_useUrl` is false, making the prefill dead code). With a URL on the clipboard, clicking Import takes the Clipboard branch, `jsonDecode`s the URL string, throws `FormatException`, and shows "Failed to import filters" — the primary link-import path is broken until the user manually toggles the URL radio. The Dart already detects the clipboard URL (`startsWith('http')`) but forgets to flip `_useUrl`. — `ayu_filters_page.dart:1573` (and dead prefill at `ayu_filters_page.dart:1581-1591`) ← `AyuGram/Telegram/SourceFiles/ayu/ui/boxes/import_filters_box.cpp:48-50` (and `:78-80`,`:86-91`)

# ayu_general_page — AyuGram "General" settings page

The page is a faithful structural port of AyuGram's `BuildQoLToggles` (settings_general.cpp:157-299): same sections, order, labels, collapsibles, beta badges, and restart prompt. Every toggle is correctly wired to `AppState`, which persists to local JSON (`_saveWindowPrefs`).

**The problem is on the consumption side.** Of the 16 interactive controls, only **2** are actually read by any feature (`showMessageSeconds` → message_bubble.dart:381 etc.; `showPeerId` → info_panel.dart:3865). The other **14 are dead toggles**: the saved value is never read anywhere in `dart/` or `go/`, never serialized into a bridge call, and (for translation) the proto/engine has no field to carry it. Flipping them produces zero observable effect — exactly the "appears to work but doesn't" placeholder the ZERO-placeholders rule bans. AyuGram has a concrete consumption site for every one of these settings (cited below).

## Dead toggles — saved to AppState but never consumed by the feature they control

- [ ] [CRITICAL] "Translation Provider" choose-button (Telegram/Google/Yandex/Native) is never used — uniclient's translate path passes only a target lang code; `EngineTranslateTextRequest` (proto) and Go `Engine.TranslateText(accountID,chatID,msgID,toLang,text)` have NO provider field, so Google/Yandex/Native can never take effect. AyuGram reads `translationProvider()` to select the actual backend — `ayu_general_page.dart:34-47` ← `AyuGram/SourceFiles/lang/translate_provider.cpp:34` (also history/view/history_view_translate_bar.cpp:494)

- [ ] [CRITICAL] "Disable Stories" persists but the stories bar (`chat_list_panel.dart:840`, gated only on `!collapsed && !_searching`) is never gated on it — toggling it leaves stories fully visible — `ayu_general_page.dart:53-62` ← `AyuGram/SourceFiles/dialogs/dialogs_widget.cpp:1003` (also data/data_session.cpp:332, info/info_top_bar.cpp:522)

- [ ] [CRITICAL] "Disable Open Link Warning" controls a warning that does not exist — links open directly via `launchUrl` (message_bubble.dart:7476) with no "Open this link?" confirmation anywhere. AyuGram gates that confirmation box on `!disableOpenLinkWarning()` — `ayu_general_page.dart:64-68` ← `AyuGram/SourceFiles/core/click_handler_types.cpp:260`

- [ ] [CRITICAL] "Collapse Similar Channels" never affects the similar-channels sheet (`info_panel.dart:7967` renders a flat ListView, always expanded). AyuGram checks `collapseSimilarChannels()` when building the recommendation list — `ayu_general_page.dart:82-86` ← `AyuGram/SourceFiles/apiwrap.cpp:1841`

- [ ] [CRITICAL] "Hide Similar Channels Tab" never hides the similar-channels action row (`info_panel.dart:4819`, always shown). AyuGram checks `hideSimilarChannels()` to suppress the block — `ayu_general_page.dart:87-91` ← `AyuGram/SourceFiles/info/profile/info_profile_inner_widget.cpp:367`

- [ ] [CRITICAL] "Disable Notify Delay" persists but the notification/online-window path (app_state.dart:682) never consults it. AyuGram branches on `disableNotificationsDelay()` to bypass the delay — `ayu_general_page.dart:95-99` ← `AyuGram/SourceFiles/window/notifications_manager.cpp:396`

- [ ] [CRITICAL] "Filter Zalgo" controls Zalgo-stripping logic that does not exist in uniclient (no `filterZalgo`/combining-char strip anywhere, even at startup). AyuGram strips Zalgo from peer names when set — `ayu_general_page.dart:104-118` ← `AyuGram/SourceFiles/data/data_user.cpp:365` (impl ayu/utils/telegram_helpers.cpp:1260; also data_channel.cpp:143, data_chat.cpp:122)

- [ ] [CRITICAL] "Improve Link Previews" persists but has no consumer anywhere. AyuGram gates its link-preview improvement on `improveLinkPreviews()` — `ayu_general_page.dart:120-124` ← `AyuGram/SourceFiles/ayu/utils/telegram_helpers.cpp:1535`

- [ ] [CRITICAL] "Spoof Webview as Android" never happens — the bot web app panel builds its WebViewController with no `setUserAgent`/platform override (web_app_panel.dart:206-230). AyuGram returns "android" vs "tdesktop" platform string based on the setting — `ayu_general_page.dart:147-151` ← `AyuGram/SourceFiles/inline_bots/bot_attach_web_view.cpp:779`

- [ ] [CRITICAL] "Increase Content Height" never resizes the web app panel — height is hardcoded `_kPanelHeight = 694.0` (web_app_panel.dart:17), never switched to the increased value (782px). AyuGram applies the increased height when set — `ayu_general_page.dart:164-168` ← `AyuGram/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:420` (botWebViewPanelHeightIncreased=782px, ayu_styles.style)

- [ ] [CRITICAL] "Increase Content Width" never resizes the web app panel — width is hardcoded `_kPanelWidth = 384.0` (web_app_panel.dart:16), never switched to the increased value (512px). AyuGram applies the increased width when set — `ayu_general_page.dart:169-173` ← `AyuGram/SourceFiles/ui/chat/attach/attach_bot_webview.cpp:423` (botWebViewPanelWidthIncreased=512px, ayu_styles.style)

- [ ] [CRITICAL] "For Stickers" confirmation persists but sticker send paths fire `engine.sendSticker(...)` immediately (chat_view.dart:5814, sticker_pack_viewer.dart:210) with no confirm box. AyuGram pops a confirm box before sending when set — `ayu_general_page.dart:181-185` ← `AyuGram/SourceFiles/chat_helpers/stickers_list_widget.cpp:2302`

- [ ] [CRITICAL] "For GIFs" confirmation persists but the GIF send path (chat_view.dart:5817) sends directly with no confirm box. AyuGram pops a confirm box before sending when set — `ayu_general_page.dart:187-191` ← `AyuGram/SourceFiles/chat_helpers/gifs_list_widget.cpp:550`

- [ ] [CRITICAL] "For Voice Messages" confirmation persists but voice send (chat_view.dart:14433) sends directly; the listen-preview UI is unrelated. AyuGram pops a confirm box before sending when set — `ayu_general_page.dart:193-197` ← `AyuGram/SourceFiles/history/view/controls/history_view_voice_record_bar.cpp:3058`

## Behavioral deviation

- [ ] [MAJOR] "Filter Zalgo" toggle uses the wrong confirm flow: a prompt-FIRST "Apply/Cancel" box with no restart action. AyuGram applies the setting immediately on toggle, then shows the standard restart prompt (Restart Now → `Core::Restart()` / Later) — identical to "Disable Stories", which the Dart code DOES port correctly via `_showRestartPrompt` (ayu_general_page.dart:211-231). Filter Zalgo should reuse that same restart prompt — `ayu_general_page.dart:107-116` ← `AyuGram/SourceFiles/ayu/ui/settings/settings_general.cpp:218-228` (+ settings_ayu_utils.cpp:36-45 ShowRestartPrompt)

# ayu_section_builder — AyuGram settings-section widget builder

Pure UI builder (titles, toggles, sliders, choose-buttons, collapsible nested
checkboxes, beta badge) porting AyuGram's `settings_ayu_utils.cpp` +
`ayu_builder.cpp`. No engine calls live here by design — every component takes
caller-supplied callbacks and wires them correctly. No stubs, no placeholders,
no empty callbacks (the lone `onChanged: (_) {}` at line 817 is the intentionally
display-only master `AyuToggle`; the wrapping `GestureDetector` at line 796 does
the real work, matching AyuGram's `toggleButton->clicks` handler). Behaviour for
the collapsible master/lock logic, count display, and shift-to-lock all match the
C++ 1:1. Findings below are layout/color deviations.

- [ ] [MAJOR] Slider value label is rendered in the title row (top, far-right) above a **full-width** slider, but AyuGram renders the value label **inline to the right of the slider track** (slider width = `outer − labelWidth`), with the title as a separate full-width button above it. Both the value's position and the slider's width differ. — `ayu_section_builder.dart:477-525` ← `AyuGram/SourceFiles/ayu/ui/settings/ayu_builder.cpp:193-212` + `AyuGram/SourceFiles/settings/settings_common.cpp:598-609`

- [ ] [MAJOR] When `showTitle == false` the slider drops the value label entirely (the whole `if (widget.showTitle)` row is skipped), but AyuGram still shows the inline value label (`MakeSliderWithLabel` always creates the label; `showTitle=false` only removes the title button and zeroes the min-label-width hint). — `ayu_section_builder.dart:477` ← `AyuGram/SourceFiles/ayu/ui/settings/ayu_builder.cpp:201-221`

- [ ] [MAJOR] Slider value label color is `windowBgActive` (#40A7E3, the bright fill blue) but AyuGram's `settingsScaleLabel` uses `windowActiveTextFg` (#168ACD, the online/active-text blue) — the exact wrong-blue the file's own header comment (lines 18-21) warns against. — `ayu_section_builder.dart:491` ← `AyuGram/SourceFiles/settings/settings.style:70-72`

- [ ] [MAJOR] Choose-button right (current-value) label color is `windowBgActive` (#40A7E3) but AyuGram's `AddButtonWithLabel` right label uses `defaultSettingsRightLabel.textFg = windowActiveTextFg` (#168ACD). Same wrong-blue token as the slider label. — `ayu_section_builder.dart:551,574` ← `AyuGram/lib_ui/ui/widgets/widgets.style:1514-1515,1526`

# ayu_toggle — AyuGram defaultToggle switch (ToggleView port)

Audited `dart/lib/ui/ayu_toggle.dart` against `lib_ui/ui/widgets/checkbox.cpp`
(`ToggleView`), `widgets.style` (`defaultToggle`), `basic.style`
(`universalDuration`), and `animation_value.{h,cpp}` (transitions).

Verified MATCHING (no action needed): all dimensions — border 2px, material
diameter 14px / non-material 16px, width 14px, material shift -2px /
non-material shift 1px, animPadding 2px, durations 150ms / 120ms
(`widgets.style:871-890`, `basic.style:131`); `getSize` formula
(`checkbox.cpp:101`); track rect + thumb rect geometry (`checkbox.cpp:114-119`);
material animPadding shrink `animPadding*(1-t)` (`checkbox.cpp:124-125`,
`animation_value.h:102-104`); colors — track & thumb border lerp
checkboxFg→windowBgActive, thumb fill constant windowBg (`checkbox.cpp:120-136`,
`widgets.style:875-878`); **forward / toggle-ON easing** `1-(1-dt)³`
(`checkbox.cpp:57-62`, `animation_value.cpp:94-104`). `onChanged` is a correct
generic callback (not a stub). No placeholders, TODOs, or fake data.

## Findings

- [ ] [MAJOR] Toggle-OFF animation uses the wrong easing in material mode (the default). AyuGram applies easeOutCubic to the *direction of travel* by calling `start(from=1, to=0, easeOutCubic)` on every toggle, so the OFF transition follows `(1-dt)³` — decelerating into the off position. The Dart port instead drives a linear controller with `reverse()` and applies the curve to its position via `easeOutCubic.transform(controller.value)`; on reverse the controller value is `1-dt`, so the displayed value becomes `easeOutCubic(1-dt) = 1-dt³` — *accelerating* (an ease-IN feel). At the temporal midpoint the thumb sits at ~12.5% (AyuGram) vs ~87.5% (Dart) — a ~75pp trajectory deviation; endpoints are correct but the OFF motion feels inverted. Forward/ON is unaffected (both give `1-(1-dt)³`); non-material is unaffected (linear is symmetric). Fix: replace the `forward()`/`reverse()` + `curve.transform()` pattern with a `CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeOutCubic.flipped)` so the curve is applied in the direction of travel. — `ayu_toggle.dart:79,92` (curve applied to `_controller.value`) + `ayu_toggle.dart:49-55` (`forward()`/`reverse()` in didUpdateWidget) ← `AyuGram/Telegram/lib_ui/ui/widgets/checkbox.cpp:57-62` (fresh `start(from,to,easeOutCubic)` per toggle) + `AyuGram/Telegram/lib_ui/ui/effects/animation_value.h:85-87` (`_cur = _from + func(_delta, dt)`) + `AyuGram/Telegram/lib_ui/ui/effects/animation_value.cpp:94-104` (`easeOutCubic`)

# box_content_divider — AyuGram `Ui::BoxContentDivider` port (8px gray band + edge shadows)

Faithful `StatelessWidget` port of `Ui::BoxContentDivider`. Verified against the authority:
- Band height **8px** (`box_content_divider.dart:29`) = `boxDividerHeight: 8px` (`widgets.style:686`) ✓
- Full-bleed width (`box_content_divider.dart:44`) = `RpWidget` full width ✓
- Fill color **`boxDividerBg`** (`box_content_divider.dart:46`) = `defaultDividerBar.bg: boxDividerBg` → `windowBgOver` `#f1f1f1` (`widgets.style:688`, `colors.palette:146`); Dart palette maps `boxDividerBg = 0xFFF1F1F1` ✓
- Top/bottom toggle (`box_content_divider.dart:48-50`) = `RectPart::Top | RectPart::Bottom` (`box_content_divider.h:29`) ✓
- `const` constructor present, no state, no lists/images/animations/async, no engine wiring required (static visual separator) → no placeholder/stub/mock-data/backend concerns.

One visual rendering divergence from the authoritative paint logic:

- [ ] [MAJOR] Top/bottom edge shadows are drawn as **1px solid `BorderSide(shadowFg)` hairlines** instead of AyuGram's **5px-tall gradient mask icons**. AyuGram's `paintTop`/`paintBottom` fill a rect of `_st.top.height()`/`_st.bottom.height()` — the `box_divider_top.png`/`box_divider_bottom.png` masks are 1×5px, i.e. **5px tall at @1x** — with a soft gradient (mask alpha profile `15→8→3→0→0`: top icon peaks ≈6% black at the very top edge and fades over ~3px; bottom icon peaks ≈1% at the bottom edge), each tinted with `boxDividerFg` (`= windowShadowFg`). The Dart instead paints a crisp 1px line at a fixed `shadowFg` (`0x18000000` ≈ 9.4% black) on both edges, so (a) the soft multi-pixel inset gradient is replaced by a hard hairline, and (b) the top-vs-bottom shadow asymmetry (top noticeably darker than bottom in AyuGram) is lost — both edges render identically. Low visual impact (the dominant 8px gray band is exact and the shadow is faint either way), and the code comment documents it as an intentional approximation, but it is a concrete divergence from the authoritative `box_divider_*` gradient icons. — `box_content_divider.dart:48-50` ← `AyuGram/Telegram/lib_ui/ui/widgets/box_content_divider.cpp:41-57` (icons `boxDividerTop`/`boxDividerBottom` defined `widgets.style:684-685`; PNG masks `lib_ui/icons/box_divider_top.png` = 1×5px)

# call_panel — Telegram 1-on-1 voice/video call panel

Audited `dart/lib/ui/call_panel.dart` (2733 lines) against AyuGram `calls/` source.

**Wiring verdict: clean.** Every control is wired to a real FFI engine call (`setCallMuted`, `toggleCamera`, `toggleScreenSharing`, `setCallAudioDevice`, `getAudioDevices`, `getCallSoundPeak`, `createConferenceCall`, `joinGroupCall`, `inviteToConferenceCall`, `endCall`, `acceptCall`, `declineCall`, `startCall`, `sendCallRating` — all in `engine_service.dart` routing to `_callAsync('__engine', ...)`). No empty callbacks, no mock data, no "coming soon", no TODO/stub. Signal-bar dimensions match `callPanelSignalBars` exactly (width=2, radius=1, skip=2, min=4, max=10, inactiveOpacity=0.5). Device chevrons on both mute and camera buttons match AyuGram's `_cameraDeviceToggle`/`_audioDeviceToggle` corner buttons. Findings below are behavioral/visual deviations, not broken wiring.

- [ ] [MAJOR] Encryption fingerprint + signal-bars badge rendered inline below the caller name instead of pinned to the top-center of the panel. AyuGram positions the fingerprint widget at `top = callFingerprintTop` (8px from panel top), horizontally centered (`desired = (width - fingerprint->width())/2`). The Dart embeds it inside `_buildStatusRow` (with the duration text) which is placed mid-panel below the name. — `call_panel.dart:1006` (badge in status row, placed at `call_panel.dart:1148`) ← `AyuGram/calls/calls_panel.cpp:1179-1188` / `AyuGram/calls/calls.style` (`callFingerprintTop: 8px`)

- [ ] [MAJOR] Fingerprint tooltip text is wrong — it does not tell the user how to verify the call. Dart shows a generic "This call with X is end-to-end encrypted", but AyuGram's tooltip is the security-verification instruction: "If the emoji on {user}'s screen are the same, this call is 100% secure". The meaning differs (assertion vs. actionable instruction). — `call_panel.dart:2102-2104` ← `AyuGram/calls/calls_emoji_fingerprint.cpp:202-205` / `AyuGram/Telegram/Resources/langs/lang.strings:5846` (`lng_call_fingerprint_tooltip`)

- [ ] [MAJOR] "Add People" button is shown unconditionally during an active call; AyuGram only shows it when the server reports conference support. AyuGram: `toggleButton(_addPeople, !isWaitingUser && _conferenceSupported)` and `_addPeople->toggle(_conferenceSupported ...)`. `CallPanelInfo` has no `conferenceSupported` field, so the Dart cannot gate it and always adds the button to the controls row. On a peer/server without conference support, tapping it kicks off `createConferenceCall` that then fails. — `call_panel.dart:981-985` (button always added) + `call_panel.dart:58-99` (`CallPanelInfo` lacks the flag) ← `AyuGram/calls/calls_panel.cpp:1425` / `AyuGram/calls/calls_panel.cpp:653-654`

- [ ] [MAJOR] Upgrading a 1-on-1 call to a conference via "Add People" loses the current mute / camera / screen-share state. AyuGram preserves them when migrating: `migrateConferenceInfo` sets `.muted = muted()`, `.videoCapture = isSharingVideo() ? _videoCapture : nullptr`, `.videoCaptureScreenId = screenSharingDeviceId()`, and the panel passes `.muted`, `.videoCapture`, `.videoCaptureScreenId` into `startOrJoinConferenceCall`. The Dart calls `createConferenceCall(accountId)` with no state args, so the new conference starts with default (un-muted, no video) regardless of the original call. — `call_panel.dart:443-457` (`createConferenceCall(accountId)` then `joinGroupCall`/`endCall`/`inviteToConferenceCall`) + `engine_service.dart:2567` (signature takes only `accountId`) ← `AyuGram/calls/calls_call.cpp:427-433` / `AyuGram/calls/calls_panel.cpp:438-447`

- [ ] [MAJOR] Remote-status pill texts deviate from AyuGram's exact strings and use the full display name instead of the short name. Dart: "X muted their microphone" / "X has low battery". AyuGram: "{user}'s microphone is off" / "{user}'s battery level is low", both formatted with `_user->shortName()`. — `call_panel.dart:928` (mic) and `call_panel.dart:933` (battery) ← `AyuGram/Telegram/Resources/langs/lang.strings:5906-5907` (`lng_call_microphone_off`, `lng_call_battery_level_low`), used in `AyuGram/calls/calls_panel.cpp` `createRemoteAudioMute`/`createRemoteLowBattery`

# call_screen — group-call panel, minimised call bar & screen-share chooser

Audited `dart/lib/ui/call_screen.dart` (4082 lines: `GroupCallPanel`, `MinimisedCallBar`, `_ScreenShareChooserDialog`, plus the group-call menu/settings/join-as/invite/volume dialogs) against AyuGram Desktop calls source. All engine.* calls were confirmed to be real bridge methods (`engine_service.dart`) — no empty/stub callbacks, mock participant lists, or fake "coming soon" feedback were found; participant/message/level data all flow from real model fields. The issues below are missing features, wrong-state machines, and mis-routed backend wiring verified line-by-line against the C++.

## Findings — call_screen.dart

- [ ] [CRITICAL] Manager "Leave voice chat" closes the panel but never disconnects: the leave branch is `onLeave: () => Navigator.of(ctx).pop()` with no `engine.leaveGroupCall` call, so a manager who picks "Leave" (not "End for all") stays joined on the backend. The non-manager path (`call_screen.dart:1811`) correctly calls `leaveGroupCall`. — `call_screen.dart:1794-1795` ← `AyuGram/Telegram/SourceFiles/calls/group/calls_group_panel.cpp:535` (`endCall()`→`_call->hangup()`, wired at :615)
- [ ] [CRITICAL] "Join As" is the wrong feature: `_showJoinAsChooser` lists locally logged-in accounts (`appState.accounts`) and on tap switches the active account then rejoins, whereas Telegram/AyuGram "Join as" lists the join-as *peer identities* (yourself / your channels / anonymous) for the same session via `MTPphone_GetGroupCallJoinAs`. The engine exposes no `possibleJoinAs`/join-as-peer method at all, so the real feature is absent. — `call_screen.dart:2059-2109` (esp. 2061, 2105-2106) ← `AyuGram/.../calls/group/calls_choose_join_as.cpp:362-427` (+ `calls_group_menu.cpp:519-522`)
- [ ] [CRITICAL] Call Settings is missing the microphone/input-device picker (and its live mic-level meter). `_showCallSettingsFromMenu` offers only Noise Suppression + Output Device; AyuGram's settings has a "Microphone" capture-device chooser plus a mic test meter. — `call_screen.dart:2290-2346` ← `AyuGram/.../calls/group/calls_group_settings.cpp:338-367`
- [ ] [MAJOR] Big mute button has no "Connecting" state: `MuteButtonState` is only `{unmuted, muted, forceMuted}`, so the button renders Mute/Unmute immediately even before the call instance is connected. AyuGram shows a dedicated `CallMuteButtonType::Connecting` (gray, "Connecting…") while joining. — `call_screen.dart:21,304-310` ← `AyuGram/.../calls/group/calls_group_panel.cpp:923` + `calls/group/calls_group_call.h:71`
- [ ] [MAJOR] Panel does not react to server-pushed mute changes: `_subscribeToCallState` updates only `_isRecording` and per-participant `_participantSpeaking`; it never updates self/force-mute/raised-hand. The mute button's state comes from `showGroupCallPanel`'s local `selfMuted`/`forceMuted`/`raisedHand` vars, which only change on the user's own taps — so an admin force-muting the local user won't flip the button to "Raise Hand". AyuGram's `setupRealMuteButtonState` binds the button live to `_call->mutedValue()`. — `call_screen.dart:233-260` ← `AyuGram/.../calls/group/calls_group_panel.cpp:869-911`
- [ ] [MAJOR] Scheduled "Set Reminder"/"Cancel Reminder" toggle is never seeded from server state: `GroupCallInfo` has no `scheduleStartSubscribed` field and the panel tracks subscription via a local var initialised to `false`, so an already-subscribed user always sees "Set Reminder" on open. AyuGram reads `real->scheduleStartSubscribed()`/`scheduleStartSubscribedValue()`. — `call_screen.dart:1740,1789` (+ `dart/lib/models/engine_models.dart:2621-2654`) ← `AyuGram/.../calls/group/calls_group_panel.cpp:875,898-921`
- [ ] [MAJOR] In-call chat is wired to the wrong backend surface: it loads regular chat history via `engine.getMessages(chatId)` and sends with `engine.sendMessage(chatId)`, posting permanent messages to the chat instead of the ephemeral group-call message stream. `GroupCallInfo.messagesEnabled`/`messagesMinPrice` are read from the model but ignored. AyuGram uses the dedicated `MTPphone_SendGroupCallMessage` / `updateGroupCallMessage` API. — `call_screen.dart:1712,1923` ← `AyuGram/.../calls/group/calls_group_messages.cpp:174-175,219`
- [ ] [MAJOR] Participant context menu omits "Mute for me"/"Unmute for me": Mute/Unmute are gated entirely behind `widget.isCanManage`, so a non-admin gets only the Volume option. AyuGram offers every user a local `mute_for_me`/`unmute_for_me` action driven by `mutedByMe` (the model field `mutedByMe` exists but the menu never reads it). — `call_screen.dart:483-500` ← `AyuGram/.../calls/group/calls_group_members.cpp:1558-1565,1672-1676`
- [ ] [MAJOR] Participant context menu is missing the "View profile" and "Send message" actions AyuGram shows for every non-self participant. — `call_screen.dart:481-500` ← `AyuGram/.../calls/group/calls_group_members.cpp:1509-1519`
- [ ] [MAJOR] Call Settings is missing Push-to-Talk configuration (PTT toggle + global-shortcut recorder + delay slider). The panel has only an RTMP-specific space-hold PTT (`call_screen.dart:274-302`); the configurable PTT in settings is absent on this desktop build. — `call_screen.dart:2290-2346` ← `AyuGram/.../calls/group/calls_group_settings.cpp:388-591`
- [ ] [MAJOR] Minimised-bar audio-level blobs are hardcoded green regardless of call state; AyuGram paints the blobs with the bar's own state gradient brush (`_groupBrush`), so they turn blue when muted and purple when force-muted. — `call_screen.dart:2793-2797` ← `AyuGram/.../calls/calls_top_bar.cpp:560`
- [ ] [MAJOR] Personal-call bar uses a green→teal gradient (`#0dcc39`→`#0bb6bd`) for the active state; AyuGram fills *personal* calls with a flat solid `callBarBg` (= `dialogsBgActive` `#419fd9`, blue) when active and `callBarBgMuted` (`#8f8f8f`) when muted — only group calls use a gradient. Wrong fill style and wrong color. — `call_screen.dart:2530-2540` ← `AyuGram/.../calls/calls_top_bar.cpp:823-825` (+ `lib_ui/ui/colors.palette:600-602`)
- [ ] [MAJOR] Screen-share "Share audio" choice is silently dropped on the primary Linux path: `showScreenShareChooser` returns the xdg-desktop-portal result immediately with `withAudio: false` hardcoded, and `_tryPortalScreenCast`'s `SelectSources` requests `types: 3` (monitor|window, no audio), so the user never sees the audio checkbox and `toggleScreenSharing` always receives `withAudio: false` whenever the portal succeeds. — `call_screen.dart:3190-3191,3258,3306-3310` ← `AyuGram/.../calls/group/ui/desktop_capture_choose_source.cpp:359,456`

## Caller-side wiring (shell.dart) — feeds call_screen's MinimisedCallBar

The `MinimisedCallBar` widget itself is correctly built, but its group-call call-site in `shell.dart` mis-wires it, so several of its features are dead for group calls. Logged here because they manifest through this file's widget; the fix is in `shell.dart`.

- [ ] [CRITICAL] Group-call hangup calls `endCall` (the personal/1:1-call FFI) instead of `leaveGroupCall`/`endGroupCall` (the convention used everywhere in `call_screen.dart`). No `callId`/`isCanManage` are passed either, so `_CallBarHangupButton`'s own leave/end-for-all dialog never runs. — `dart/lib/ui/shell.dart:383` ← `AyuGram/.../calls/calls_top_bar.cpp:424-440` (+ `calls/group/calls_group_panel.cpp:535`)
- [ ] [MAJOR] Group-call bar receives no `onTap`, so tapping it does nothing — the user cannot return to the call panel. AyuGram's top bar reopens the panel (`showInfoPanel`). — `dart/lib/ui/shell.dart:375-418` ← `AyuGram/.../calls/calls_top_bar.cpp:410-423`
- [ ] [MAJOR] Group-call bar receives no `isConnecting`/`isForceMuted`/`isRaisedHand`/`audioLevel`/`callStartTime`, so the connecting (gray) and force-muted (purple) gradients, the live audio-level blobs, and the duration never appear for group calls. — `dart/lib/ui/shell.dart:375-380` ← `AyuGram/.../calls/calls_top_bar.cpp:343-351,563-572,733-745`

## Notes — verified correct (not flagged)

- Volume mapping is correct: AyuGram `kDefaultVolume=10000` (=100%), `kMaxVolume=20000` (=200%); Dart's `volume/100` display + slider `max:20000`/`divisions:200` match exactly. — `call_screen.dart:491,528,544-545` ← `calls/group/calls_group_common.h` + `calls_volume_item.cpp`
- Speaking-blob radii match spec: `_minRadius=27`/`_maxRadius=29` ← `groupCallRowBlobMinRadius:27px`/`groupCallRowBlobMaxRadius:29px`; `_userpicMinScale=0.8` matches AyuGram.
- Screen/window enumeration is a real implementation (portal → wmctrl/xdotool/kdotool/hyprctl/swaymsg/gdbus + grim/import/gnome-screenshot/spectacle thumbnails), not hardcoded; chosen `sourceId` is passed to `engine.toggleScreenSharing`. Default-to-first-screen matches AyuGram.
- Force-muted→Raise-Hand tap logic, scheduled start-now ≤10s confirmation, leave-vs-end-for-all dialog, scheduled-overlay countdown/"Late by" flip, signal bars (4 bars), recording snackbars (fired only after awaiting real engine calls), and Invite Members (`getContacts`+`inviteToConferenceCall`) are all correctly wired.
- Idiom-only diffs not flagged: Windows/Screens two-tab chooser vs AyuGram's single combined grid; sender name shown on all chat bubbles vs admin-only; three separate row icons vs one animated icon; muted-gray `#7F8A96` vs `#8f8f8f`.

# calls_screen — Calls box, history list, conference-create box, call settings

Overall the file is genuinely wired: every action calls a real `EngineService` FFI method
(`getCallHistory`, `getGroupCall`, `joinGroupCall`, `startCall`, `createConferenceCall`,
`inviteToConferenceCall`, `clearCallHistory`, `getContacts`, `getConfcallSizeLimit`,
`getAudioDevices`, `setCallAudioDevice`, `accountUpdateDeviceLocked`, `deleteMessage`). No
placeholders, empty callbacks, TODO/HACK markers, mock data, or "coming soon" feedback exist.
Pagination (20/100), grouping (peer+date+type), context menu (Delete / Show in Chat), and the
call-settings sections (Output/Input/Call Devices/Camera/Other) all match AyuGram. The findings
below are behavioral/architectural deviations, not broken wiring.

- [ ] [MAJOR] Creating a conference with selected participants shows a share-link box instead of joining the call. The "Create"/"Start Call" path calls `createConferenceCall` → `inviteToConferenceCall` → `_showLinkBox(initial: true)` and never enters the call; the creator must then tap "Join this call yourself". AyuGram's multi-select path calls `startOrJoinConferenceCall(...)`, which opens `Group::Panel` and joins the creator into the live call immediately (then sends invites), so invitees join a call the host is already in. — `calls_screen.dart:1128` (else branch, lines 1128–1136) ← `calls/group/calls_group_invite_controller.cpp:1187` (`startOrJoinConferenceCall`) → `calls/calls_instance.cpp:295` (opens `Group::Panel`)

- [ ] [MAJOR] ~460 lines of dead/duplicate code: `_CallSettingsScreen` and its private helper widgets (`_CallSettingsSectionHeader`, `_CallSettingsDeviceRow`, `_CallSettingsToggleRow`, `_CallSettingsInfoLabel`, `_CallSettingsActionRow`) are never instantiated anywhere in `lib/`. The real "Call Settings" menu item routes to `devicesScreenRoute(initialTab: 1)` in `settings_screen.dart` (see `_openCallSettings`), making this entire screen unreachable and a stale duplicate of the unified Devices settings. (`InputLevelMeter`/`LevelMeterPainter` are NOT dead — they're reused by `settings_screen.dart:2504`.) — `calls_screen.dart:2342` (definition) / `calls_screen.dart:334` (`_openCallSettings` uses `devicesScreenRoute` instead) ← `settings/sections/settings_calls.cpp:739` (`CallsId()` is the real settings section)

- [ ] [MAJOR] Active-group-call discovery over-fetches: `_loadActiveGroupCalls` fires up to ~20+ concurrent `getGroupCall` engine round-trips (pinned + 20 non-pinned group/channel chats), and each call deserializes the entire group-call object including the full participant list (`engine_service.dart:2199–2224`) only to read `gc.active`. AyuGram determines the same thing from the cached, zero-cost `Data::ChannelHasActiveCall(channel)` flag while iterating already-loaded chats — no network/FFI calls. `ChatInfo` exposes no `hasActiveCall` flag, so the fix is engine-side (surface the flag in the chat-list payload). — `calls_screen.dart:206` (per-chat `getGroupCall` in `Future.wait`, lines 206–216) ← `calls/calls_box_controller.cpp:198` (`Data::ChannelHasActiveCall(channel)`)

- [ ] [MAJOR] Redial starts a video call for video-call history entries; AyuGram always redials as voice. `_startRedial` calls `startCall(..., video: group.isVideo)`, so tapping the redial button on a past video call opens a video call. AyuGram's right-action handler calls `startOutgoingCall(user, {})` with a default-constructed `StartOutgoingCallArgs` (`video = false`), i.e. always a voice call regardless of the original call type (only the button icon differs: `callCameraReDial` vs `callReDial`). May be an intentional improvement, but it deviates from the ground-truth behavior. — `calls_screen.dart:2138` (`startCall(..., video: group.isVideo)`) ← `calls/calls_box_controller.cpp:616` (`startOutgoingCall(user, {})`; default in `calls/calls_instance.h:59`, `bool video = false`)

# chat_export — Telegram Data Export panel (full / per-chat / per-topic) + progress, calendar/time/format pickers, export-ready suggestion box

Audited `dart/lib/ui/chat_export.dart` (3281 lines) against AyuGram `export/view/*` and `export/export_settings.*`.
Core flow is genuinely wired: `startExport`/`cancelExport`/`skipExportFile`/`save`+`loadExportSettings` all hit real Go handlers (`dispatch_engine.go:5761-5816`), and `onExportProgress`/`Error`/`Complete` parse real event fields (`engine_models.dart:2741-2830`). Defaults (types, media=Photo only, 8MB size, 100-step slider), panel size 364×480, calendar sizes (320 / cell 38 / inner 32 / pad 14), stop-confirm / takeout / disk-error / delay text all match AyuGram. Issues below are functional only (cosmetic label-wording diffs skipped per rules).

- [ ] [CRITICAL] "Data export ready" suggestion box is dead code — `showExportSuggestBox`/`_ExportSuggestBox` are defined but **never invoked anywhere in the app** (only self-references in this file; nothing reads the persisted `suggestAvailableAt`). AyuGram shows it on startup once the TAKEOUT_INIT_DELAY timer expires (`Session::suggestStartExport()` → `Export::View::SuggestStart`, scheduled from persisted settings at startup). Result: after a takeout delay error, the user is never re-prompted to start the export. — `chat_export.dart:312` (`showExportSuggestBox`), `chat_export.dart:3165` (`_ExportSuggestBox`) ← `AyuGram/export/view/export_view_panel_controller.cpp:99` (`SuggestStart`) + `AyuGram/data/data_session.cpp:1596` (`suggestStartExport()`) + `AyuGram/main/main_domain.cpp:92`

- [ ] [CRITICAL] `callGeneric('SuggestStartExport', …)` and `callGeneric('ClearExportSuggestion', …)` target engine methods that **do not exist** in the Go bridge — `dispatch_engine.go` has no case for either, so the dispatch `default` returns `"unknown engine method"` and the calls always throw (swallowed by `.catchError`). Scheduling/clearing the export suggestion is therefore non-functional. AyuGram implements these as `Session::suggestStartExport(availableAt)` / `ClearSuggestStart` (`session().data().clearExportSuggestion()` + reset `availableAt`). — `chat_export.dart:1138` (SuggestStartExport) & `chat_export.dart:3180` (ClearExportSuggestion) ← `AyuGram/export/view/export_view_panel_controller.cpp:106` (`ClearSuggestStart`) + `AyuGram/data/data_session.cpp:1584` (`suggestStartExport`); no handler at `go/bridge/dispatch_engine.go:6589` (default → unknown method)

- [ ] [MAJOR] "Only my messages" default for **private groups & private channels** is inverted vs AyuGram. Dart defaults `_privateGroupsOnlyMy = false` / `_privateChannelsOnlyMy = false`, so it sends `full_private_groups=true` / `full_private_channels=true` (export ALL messages) by default. AyuGram's `DefaultFullChats()` is only `PersonalChats | BotChats`, and the "Only my messages" checkbox's initial state is `(fullChats & types) != types` — so for private groups/channels (not in fullChats) it is **checked** by default, i.e. only-my-messages. The Dart default thus exports far more data than AyuGram for a fresh export. (Public groups/channels `=true` forced-on are correct.) — `chat_export.dart:372-373` (defaults) & `chat_export.dart:865-866` (`full_private_*` params) ← `AyuGram/export/export_settings.h:115-118` (`DefaultFullChats`) + `AyuGram/export/view/export_view_settings.cpp:751` (`(readData().fullChats & types) != types`)

# chat_list_panel — left panel (search, folder tabs, top peers, stories, recent contacts, search tabs/filters, archived row, forum topics, reaction tags, saved sublists)

The implementation is dimensionally and behaviorally very faithful to AyuGram: stories (35/77px, photo 21/42px, shift 16px, lineTwice 3/4px, lineReadTwice 0/2px), topPeers (photo 46px), recentPeersItem (height 56px, photo 42px, name (64,9), status (64,30)) all match `dialogs.style` exactly; reorder threshold (30), drag-to-filter X/Y (30/75), forward-hover freeze (2s), peer color remap `{0,7,4,1,6,3,5}` (`id % 7`), and story-ring units (5760/160) all match the C++ source. Findings below are the genuine deviations, concentrated in the search-scope UI and two behavioral defaults.

- [ ] [MAJOR] "Public Posts" search tab is shown unconditionally; AyuGram only offers it when the query is a hashtag/cashtag (`publicIcon` is non-null only when `_searchHashOrCashtag != HashOrCashtag::None`, and `apply()` skips tabs with a null icon). For a plain text query the tab should not exist. — `chat_list_panel.dart:3745` (+ strip shown at `:817`) ← `AyuGram/Telegram/SourceFiles/dialogs/dialogs_inner_widget.cpp:4618` (+ `:4636`) & `AyuGram/Telegram/SourceFiles/dialogs/ui/chat_search_in.cpp:321`

- [ ] [MAJOR] "This Peer" search tab is shown unconditionally; AyuGram only offers it when there is an actual peer/sublist scope (`peerIcon` non-null), otherwise the tab is filtered out. With no active chat the Dart tab simply returns an empty result set instead of being hidden. — `chat_list_panel.dart:3746` (filter returns `[]` at `:596`) ← `AyuGram/Telegram/SourceFiles/dialogs/dialogs_inner_widget.cpp:4612` (+ `:4634`) & `AyuGram/Telegram/SourceFiles/dialogs/ui/chat_search_in.cpp:321`

- [ ] [MAJOR] The "This Peer" tab label is hardcoded; AyuGram resolves it by peer type to "This Chat" / "This Channel" / "This Group" (`TabLabel` switches on `ChatSearchPeerTabType`). A channel search shows the wrong scope label. — `chat_list_panel.dart:3746` ← `AyuGram/Telegram/SourceFiles/dialogs/ui/chat_search_in.cpp:70`

- [ ] [MAJOR] The "Search in" sub-filter row implements a fabricated chat-type filter (All Messages / Private / Groups / Channels) that does not exist in AyuGram's `ChatSearchIn`. AyuGram's second section is a "Search from [user]" sender filter (`_from`, `changeFromRequests`, `lng_dlg_search_from`), which is not implemented here at all. — `chat_list_panel.dart:3962` (filters list `:3973`, type-filter logic `:582`) ← `AyuGram/Telegram/SourceFiles/dialogs/ui/chat_search_in.h:80` & `AyuGram/Telegram/SourceFiles/dialogs/ui/chat_search_in.cpp:288`

- [ ] [MAJOR] Stories bar defaults to the expanded 77px state (named avatars). AyuGram's stories list starts collapsed (`State::Small`, 35px small-thumb strip) and only expands on deliberate pull-down/overscroll (`_storiesExplicitExpand` defaults false). On first paint at rest the user sees the expanded layout instead of the small strip. — `chat_list_panel.dart:2939` (`_expanded = true`) ← `AyuGram/Telegram/SourceFiles/dialogs/dialogs_widget.cpp:1487` & `AyuGram/Telegram/SourceFiles/dialogs/dialogs.style:716`

- [ ] [MAJOR] Search message-result rows only open when the result's peer is already in the local chat list (`chatsForAccount(...).where(chatId==...).firstOrNull`; tap is a silent no-op when `chat == null`). AyuGram search-result rows carry their own resolved `History` and open any peer regardless of dialog-list membership. This makes Public-Posts/global results un-openable. — `chat_list_panel.dart:890` ← `AyuGram/Telegram/SourceFiles/dialogs/dialogs_inner_widget.cpp:2840` (+ `:2309`)

- [ ] [MAJOR] Avatar thumbnails are decoded at full file resolution — every `Image.file(...)` for a 21–46px target omits `cacheWidth`/`cacheHeight` (or `ResizeImage`), so large profile photos are decoded into memory at native size. AyuGram caches/paints userpics at the exact display size (e.g. `recentPeersItem.photoSize: 42px`, `topPeers.photo: 46px`). — `chat_list_panel.dart:2806` (also `:3053`, `:3288`, `:3636`, `:4073`, `:4346`, `:6546`) ← `AyuGram/Telegram/SourceFiles/dialogs/dialogs.style:761`

# chat_list_row — chat list row (avatar, preview, badges, swipe, stories, forum row)

Overall a very faithful port. Verified-matching against AyuGram: row 62px / avatar 46px /
contentLeft 68px / forum 80px / topics 21px+8px (`dialogs.style:89-113`); story photo 42/21px
and line widths 2/1/1.5/0px (`dialogs.style:716-738`); story gradient #0dcc39→#0992ef topRight→
bottomLeft (`outline_segments.cpp:98-112`, `colors.palette:582,584`); swipe 50px/1.5/0.2/8px and
lottie 0.32/0.24 (`swipe_handler.cpp:28,63-64`, `dialogs_inner_widget.cpp:5789-5790`); quick-action
colors/labels/lottie names + resolve logic (`dialogs_quick_action.cpp:120-227`); chat-type icons
(`dialogs_layout.cpp:1024-1058`); all callbacks wired, all swipe lottie assets present. The items
below are the genuine deviations.

- [ ] [MAJOR] Chat-list date format diverges from `FormatDialogsDate`: Dart shows a literal "Yesterday" string and omits the 20-hour rule (a message <20h old that crosses midnight should still show the time, not "Yesterday"/day-name), and renders old dates as "Jan 5" (month-abbrev, no year) instead of the locale short-date. AyuGram never prints "Yesterday" and uses time / day-of-week / locale short-date only. — `dart/lib/ui/chat_list_row.dart:37-53` ← `AyuGram/Telegram/SourceFiles/ui/text/format_values.cpp:526-542`

- [ ] [MAJOR] Trailing badge order is reversed. In a `Row`, Dart lays out unread-badge → mention → reaction → poll left-to-right, so the unread counter sits at the LEFT of the badge cluster and poll hugs the right edge. AyuGram's `PaintBadges` paints right-to-left from the right edge: unread badge first (rightmost), then mention/reaction, then poll to its left — i.e. the unread counter must hug the right edge. Visible whenever a chat has an unread count plus a mention/reaction/poll. — `dart/lib/ui/chat_list_row.dart:313-357` ← `AyuGram/Telegram/SourceFiles/dialogs/ui/dialogs_layout.cpp:198-287`

- [ ] [MAJOR] Mention and reaction badges are shown simultaneously. Dart renders separate `if` blocks for `unreadMentionCount`, `unreadReactionCount`, and `unreadPollCount`, so a chat with both unread mentions and unread reactions shows two icon badges. AyuGram paints only ONE of mention/reaction (mention takes priority: `mention ? mention-icon : reaction-icon`) plus poll — never both mention and reaction together. — `dart/lib/ui/chat_list_row.dart:333-348` ← `AyuGram/Telegram/SourceFiles/dialogs/ui/dialogs_layout.cpp:248-272`

- [ ] [MAJOR] Stories ring renders no read/unread per-segment split. Dart paints the entire ring in a single style — all-gradient when `hasUnreadStory`, else all-gray — driven by one bool, with one line width for every segment. AyuGram builds mixed segments in one ring: `storiesReadCount` thin gray segments (`lineReadTwice/2`) + `storiesUnreadCount` thick gradient segments (`lineTwice/2`), so a peer with e.g. 5 stories / 2 unread shows 3 gray + 2 gradient arcs of different widths. (Root cause: `ChatInfo` exposes only `storyCount` + `hasUnreadStory`, not `storiesUnreadCount`; the model needs the unread count to replicate this.) — `dart/lib/ui/chat_list_row.dart:1232-1291` ← `AyuGram/Telegram/SourceFiles/dialogs/dialogs_row.cpp:447-470`

- [ ] [MAJOR] Failed send-state shows the wrong glyph. Dart's `_SendStateIcon` maps `MsgStatus.failed` to `Icons.error_outline`. AyuGram routes both sending AND failed (`item->isSending() || item->hasFailed()`) to `st::dialogsSendingIcon` (the clock glyph) in the dialog row — there is no distinct error icon in the chat-list send-state slot. — `dart/lib/ui/chat_list_row.dart:1728-1730` ← `AyuGram/Telegram/SourceFiles/dialogs/ui/dialogs_layout.cpp:782-798`

# chat_settings_screen — Chat Settings (themes, accent, peer color, background, quick action, stickers, messages, sensitive content, archive)

Compared against AyuGram `settings/sections/settings_chat.cpp` (`BuildChatSectionContent` and its `Setup*` helpers). Backend wiring is generally solid: sensitive content, name color, default reaction, sticker install/uninstall/reorder/search, cloud-theme install/delete, archive settings, and wallpapers are all wired to the engine. The findings below are the real deviations.

- [ ] [CRITICAL] "Use system accent color" is faked on every platform except KDE Linux. `_readSystemAccent()` only parses `~/.config/kdeglobals` on Linux; on macOS, Windows, and non-KDE Linux it returns the hardcoded Telegram blue `#40a7e3`. Toggling the checkbox therefore *looks* like it applies the OS accent but silently applies blue. AyuGram reads the real OS accent cross-platform via `Window::Theme::SystemAccentColor()` and only the actual system color is applied. — `chat_settings_screen.dart:678-699` (also applied at `:443`) ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_chat.cpp:296` / `:2485`

- [ ] [CRITICAL] The "Use system accent color" checkbox is rendered unconditionally instead of being gated by whether the platform can actually report a system accent. AyuGram wraps it in a `SlideWrap` that is toggled on only when `IsSystemAccentColorSupported()` (i.e. `SystemAccentColor().has_value()`) is true and a built-in theme is selected; on unsupported platforms the control is hidden entirely. Here it always shows, exposing the faked behavior above. — `chat_settings_screen.dart:430-462` ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_chat.cpp:106-108` (and toggle logic `:2506-2510`, creation `:2356-2365`)

- [ ] [MAJOR] Picking a manual accent swatch does not uncheck "Use system accent color", leaving an inconsistent state (box stays checked while a custom color is applied). `onColorSelected` only calls `appState.updateAccentColor(hex)`, and `AppState.updateAccentColor` (app_state.dart:3623) never clears `_useSystemAccent`. AyuGram explicitly un-checks the system-accent box when a palette color is chosen (`setSystemAccentColorEnabled(false)` + `systemAccentWrap->entity()->setChecked(false)`). — `chat_settings_screen.dart:425-428` ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_chat.cpp:2661-2665`

- [ ] [MAJOR] Section order is wrong: the Cloud Themes block is placed *before* the peer-color / auto-night / font rows. AyuGram builds `ThemeSettings` (peer color → auto-night → font) **before** `CloudThemes`. Here `_CloudThemeSection` is emitted right after the accent palette, then `_YourColorRow` / `_AutoNightRow` / `_FontFamilyRow` follow — the two whole sections are swapped relative to ground truth. — `chat_settings_screen.dart:463` (cloud themes) vs `:499-519` (peer color/auto-night/font) ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_chat.cpp:1308-1309` (`BuildThemeSettingsSection` before `BuildCloudThemesSection`)

- [ ] [MAJOR] "Suggest Animated Emoji" visibility condition deviates. AyuGram shows this row only when the user is Premium **and** "Suggest Emoji" is enabled (`rpl::combine(AmPremiumValue, suggestEmoji, _1 && _2)`); a non-premium user never sees it. Here it is shown whenever `suggestEmoji` is true regardless of premium status (rendered disabled with a lock icon), and the disabled branch wires a dead empty callback `(_) {}`. — `chat_settings_screen.dart:623-632` ← `AyuGram/Telegram/SourceFiles/settings/sections/settings_chat.cpp:1507-1517`

# chat_switch_overlay — Ctrl+Tab quick chat switcher (alt-tab style grid)

Audited against AyuGram `window/window_chat_switch_process.{cpp,h}`, `window/window.style`, `window/window_session_controller.cpp`, `core/shortcuts.cpp`.

Backend wiring is genuine — no placeholders/stubs. `chats` ← `ChatState.collectChatOpenHistory()`, `onChosen` → `openChat`, `onRemove` → `removeChatFromOpenHistory`, avatars use real `Image.memory/file` + `SavedMessagesUserpic` + topic icons wired to the engine. Dimensions all match the `.style` (cell 72×104, userpic 56/40/24, top 8, nameSkip 6, selectLine 3, margins 16, padding 12, radius `boxRadius=6`, accent `defaultRoundCheckbox.bgActive=windowBgActive`, name font 11px). Self-chat label is correct ("Saved Messages" set by backend telegram.go:12463). Navigation/wrap math (`_moveNext/Prev/Down/Up`), hover-to-select, click-to-confirm, modifier-release-to-confirm, `<2` early dismiss, and selection clamping all match. The two issues below are behavioral/visual divergences.

- [ ] [MAJOR] Forward Ctrl+Tab pre-selects the CURRENT chat instead of the previous one, breaking the single-tap quick-switch gesture. AyuGram opens the switcher with `_selected = 0` (the opened thread, rotated to front) and the *initiating* Tab immediately runs `process(request)` on open, advancing selection to index 1 — so one tap-and-release of Ctrl+Tab switches to the previously-used chat (classic alt-tab). The Dart path opens with `initialIndex: 0` (history[0] = the current chat, since `openChat` inserts it at index 0) and never auto-advances, so a quick Ctrl+Tab→release re-selects the current chat (a no-op switch); the user must press Tab a second time to reach the previous chat. — `chat_switch_overlay.dart:66` (`_selected = widget.initialIndex…`), caller `shell.dart:450` (`initialIndex: _chatSwitchReverse ? history.length - 1 : 0`) ← `AyuGram/window/window_chat_switch_process.cpp:331` (`_selected = 0`) + `:253-259` (Tab → `setSelected(_selected + 1)`) + `AyuGram/window/window_session_controller.cpp:1927` (`_chatSwitchProcess->process(request)` runs the initiating Tab on open)

- [ ] [MAJOR] Whole-window dim overlay that AyuGram does not draw. Dart fills the full `Positioned.fill` with `Container(color: overlayColor)` where `overlayColor = p.layerBg = 0x7F000000` (~50% black), darkening the entire app while the switcher is open. AyuGram's switcher widget is transparent — `setupWidget` only shows the widget and installs a mouse-press-to-close handler with no background paint, and `setupView`'s paint handler draws only the panel rect (`_outer`: drop shadow + `_bg` rounded box), leaving the rest of the UI at full brightness with the panel floating above it. — `chat_switch_overlay.dart:310` (`color: overlayColor`) + `:241` (`overlayColor = p.layerBg`) ← `AyuGram/window/window_chat_switch_process.cpp:298-316` (setupWidget: no bg paint) + `:403-411` (paintRequest paints only `_outer` shadow + `_bg`)

# choose_datetime_box — Calendar / ChooseDateTime / TimePicker boxes

Audited against AyuGram `ui/boxes/calendar_box.cpp`, `ui/boxes/choose_date_time.cpp`,
`ui/boxes/time_picker_box.cpp`, and the schedule wrapper `history/view/history_view_schedule_box.cpp`.

**Overall: high-quality, fully-wired implementation — NO stubs/placeholders found.**
Verified correct: all schedule dimensions (`scheduleHeight 95`, `scheduleDateWidth 136`,
`scheduleTimeWidth 72`, `scheduleAtSkip 24`, `scheduleDateTop 38`, `scheduleAtTop 42`),
calendar cell sizes (`48x40`, inner `34`, daysHeight `40`, pad `14`), `kMinimalSchedule 10`,
`kJumpDelay 700`, tooltip delay `350`, `kScheduledUntilOnlineTimestamp 0x7FFFFFFE`, all 8
repeat-period values, all 16 TTL picker values, fade `200ms`, drum `looped=false`, title
strings exact (`lng_schedule_title`="Send this message on...", `lng_remind_title`="Remind me
on...", `lng_scheduled_send_until_online`="Send when online"). Premium toast → real
`engine.openPremiumSubscription(ref:'schedule_repeat')`; repeat menu, send-when-online, and
calendar are all wired. Findings below are visual/behavioral deviations only.

- [ ] [MAJOR] Schedule date & time fields drawn as filled rounded boxes (Border.all 1px + borderRadius 2 + `fieldBg` fill) — AyuGram's date field is an underline-only input (`borderRadius:0`) and the time field is borderless (`border:0; borderActive:0`), neither has a background fill — `choose_datetime_box.dart:1547` & `choose_datetime_box.dart:2046` ← `AyuGram/boxes/boxes.style:893` (scheduleDateField) + `AyuGram/boxes/boxes.style:899` (scheduleTimeField `border:0`) + `AyuGram/lib_ui/ui/widgets/fields/input_field.cpp:2397` (borderRadius 0 ⇒ bottom-line only)

- [ ] [MAJOR] Repeat-period label text + dropdown/lock icons colored with `windowBgActive` (0xFF40A7E3) instead of `windowActiveTextFg` (0xFF168ACD) used by AyuGram's repeat link/icons — distinct palette tokens — `choose_datetime_box.dart:1456` (accentFg) used at `choose_datetime_box.dart:1618`/`1622`/`1624` ← `AyuGram/boxes/boxes.style:919` & `:923` (scheduleRepeatDropdownLock/Arrow = windowActiveTextFg) + `AyuGram/ui/boxes/choose_date_time.cpp:313` (label via tr::link) [palette: `telegram_palette.dart:3021` vs `:3029`]

- [ ] [MAJOR] Calendar navigation arrows use horizontal chevrons (`Icons.chevron_left`/`chevron_right`) — AyuGram uses vertical up/down chevrons for the vertically-scrolling calendar (prev = up, next = down) — `choose_datetime_box.dart:512` & `choose_datetime_box.dart:525` ← `AyuGram/boxes/boxes.style:423` (calendarPrevious "calendar_down-flip_vertical" = up) + `AyuGram/boxes/boxes.style:432` (calendarNext "calendar_down" = down)

- [ ] [MAJOR] Adjacent-month ("grayed out") day numbers rendered at ~20% opacity (`disabledFg`@0.4 then ×0.5 ≈ subtextFg@0.2) — AyuGram paints them in full-opacity `windowSubTextFg`; in-month days are barely visible by comparison — `choose_datetime_box.dart:638` ← `AyuGram/boxes/boxes.style:480` (dayTextGrayedOutColor: windowSubTextFg) + `AyuGram/ui/boxes/calendar_box.cpp:896`

- [ ] [MAJOR] Calendar range-selection paints each in-range day as a separate filled circle (same as single selection) — AyuGram draws one continuous rounded "pill" bar spanning the selected range per row (`activeButtonBg`, rounded ends). Currently latent: no caller passes `allowsSelection:true` — `choose_datetime_box.dart:1107` ← `AyuGram/ui/boxes/calendar_box.cpp:802`

- [ ] [MAJOR] Calendar selection mode has no drag-to-select and no Shift+click extension; after the first tap every subsequent tap extends the same range (never starts a fresh one) — AyuGram supports mouse-drag selection, Shift+click, and restarting a new selection after one completes. Currently latent (no caller enables selection) — `choose_datetime_box.dart:319` (_selectDay) ← `AyuGram/ui/boxes/calendar_box.cpp:914` (drag in mouseMoveEvent) + `AyuGram/ui/boxes/calendar_box.cpp:996` (Shift / two-press restart)

- [ ] [MAJOR] "Pro tip: hold Ctrl to send silently" only works when clicking the Schedule button — pressing Enter inside the time field submits without applying the Ctrl→silent flag. AyuGram's shared submit lambda applies Ctrl-silent on both paths (button and time-field Enter) — `choose_datetime_box.dart:2111` (onSubmitted → `_submit()` no silent) vs button at `choose_datetime_box.dart:1639` ← `AyuGram/history/view/history_view_schedule_box.cpp:97` (submit checks `IsCtrlPressed`) + `AyuGram/ui/boxes/choose_date_time.cpp:221` (time submitRequests → save → done)

- [ ] [MAJOR] Drum-picker selection band lines (month/year picker + TTL time picker) colored with `windowBgActive` instead of AyuGram's `activeLineFg`; divergence widens in custom themes (e.g. teal: 0x3EE2CC vs 0x3FC1B0) — `choose_datetime_box.dart:849` (month/year band) & `choose_datetime_box.dart:1880` (time-picker band) ← `AyuGram/ui/boxes/calendar_box.cpp:174` + `AyuGram/ui/boxes/time_picker_box.cpp:109` (both st::activeLineFg) [palette: `telegram_palette.dart:3021` vs `:3046`]

# color_picker_box — Color editor dialog (HSV square + hue/opacity sliders + H/S/B, R/G/B, hex fields)

Overall this is a faithful, fully-wired implementation of AyuGram's `ColorEditor` **RGBA (HSV) mode**: no stubs, no empty callbacks, no mock data. All dimensions match `boxes.style` (390 width, 256 picker, 19 slider, 8 slider-skip, 10 edit-skip, 6 mark radius, 1 mark line, 60×34 sample, 13 field-skip), painters reproduce the HSV square/hue-slider/opacity-slider/crosshair/cursor-ring/checkerboard correctly, and field navigation/wheel/arrow-keys/hex parsing all match `color_editor.cpp`. The findings below are about the *second* AyuGram mode that is never implemented.

- [ ] [MAJOR] HSL mode is not implemented — AyuGram's `ColorEditor` has two modes, and 2 of the 3 Dart callers map to `Mode::HSL` (photo-editor brush `editor/color_picker.cpp:751`, chat-settings peer/bubble color `settings/sections/settings_chat.cpp:377`). In HSL mode AyuGram shows a **hue×saturation** picker square plus a **horizontal lightness slider** and **no** vertical hue slider; Dart instead always renders the RGBA-style **saturation×brightness** square + **vertical hue slider** and has no lightness slider at all. The lightness slider element is missing and the square axes are semantically different for those callers. — `color_picker_box.dart:392-457` (single sat/bri square + vertical hue slider built unconditionally) ← `color_editor.cpp:875-881` (HSL branch creates `_lightnessSlider`) + `color_editor.cpp:212-247` (`preparePaletteHSL` builds hue×saturation square) + `color_editor.cpp:1125-1138` (HSL `hsbFromControls`: hue=picker.x, saturation=picker.y, brightness=lightnessSlider)

- [ ] [MAJOR] Lightness limits are applied only to the output color, not to the controls/fields, causing a crosshair-vs-result mismatch — Dart's `_clampedBrightness` clamps lightness only inside the `_currentColor` getter, while the gradient square, crosshair and the editable B field still use the raw unclamped `_brightness`. So in the chat-settings case (`lightnessMax` e.g. 160/255) the user can drag the crosshair into a bright region and type B=100, but the produced/swatch color is silently darker — the visual position no longer matches the result. AyuGram avoids this by bounding lightness inside a dedicated slider range and by clamping the field value itself (`std::clamp(percentToByte(...), _lightnessMin, _lightnessMax)`). — `color_picker_box.dart:206-224` (clamp confined to output getter) + `color_picker_box.dart:255-258` (B field sets `_brightness` with no lightness clamp) ← `color_editor.cpp:1173-1185` (`updateFromHSBFields` clamps brightness to limits) + `color_editor.cpp:568-575` (Slider applies limits) + `color_editor.cpp:1140-1151` (`applyLimits`)

# confirm_box — Box/dialog infra, delete/moderate, single-choice, auto-delete, permissions, screen-share, report flow

Box chrome constants (`kBoxWidth=320`, `kBoxWideWidth=364`, `kBoxRadius=6`, `kBoxPadding=24/14/24/8`,
title 48px/16px-semibold @ (24,13), button 34px/14px-semibold, skips 10/20, maxListHeight 492) all match
`AyuGram/Telegram/lib_ui/ui/layers/layers.style:38-122` exactly. `showConfirmBox` (Enter-confirms,
inform-mode hides cancel, boxClosing→cancel, strictCancel) faithfully mirrors `ConfirmBox`. The issues below
are wiring/fidelity gaps.

- [ ] [CRITICAL] Moderate panel checkboxes (Ban User / Report Spam / Delete All from X) are rendered and returned in `DeleteConfirmResult` but **no caller consumes `banUser`/`reportSpam`/`deleteAll`** — checking them does nothing (no kick, no spam report, no delete-all). A repo-wide grep finds zero readers of those result fields. AyuGram actually performs `chatParticipants().kick`, `Api::ReportSpam`, and `deleteAllFromParticipant` when checked. — `confirm_box.dart:875-893` (render) + `confirm_box.dart:748-750` (result) + ignored at `chat_view.dart:3200-3206` & `chat_view.dart:3225-3227` ← `AyuGram/Telegram/SourceFiles/boxes/delete_messages_box.cpp:636-651`

- [ ] [MAJOR] The "Also delete for everyone / Also delete for {name}" revoke checkbox is **never shown for `clearHistory` or `leaveChat` modes** — `_revokeLabel` only returns a label for `singleMessage`/`bulkMessages`, so even though `delete_chat` passes `canRevoke: chat.type == ChatType.dm` it is silently dropped. Result: clearing history / deleting a DM conversation can only ever be "for me", never "for everyone". AyuGram shows this checkbox (and passes `revoke` to `clearHistory`/`deleteConversation`) whenever `canRevokeFullHistory()`. — `confirm_box.dart:717-729` ← `AyuGram/Telegram/SourceFiles/boxes/delete_messages_box.cpp:166-181` & `AyuGram/Telegram/SourceFiles/boxes/moderate_messages_box.cpp:998-1018,1117`

- [ ] [MAJOR] Auto-delete timer box is implemented as a radio single-choice list (`showSingleChoiceBox`, auto-applies on tap) instead of AyuGram's draggable TTL slider (`CreateSliderForTTL`) plus a descriptive `DividerLabel` and explicit Save/Cancel buttons. Wrong widget structure and missing the explanatory text. — `confirm_box.dart:1142-1167` ← `AyuGram/Telegram/SourceFiles/ui/boxes/auto_delete_settings.cpp:188-265` (slider at `:19-184`)

- [ ] [MAJOR] Auto-delete "1 month" value is `2592000` (30 days) but AyuGram's `indexToPeriod` uses `31 * 86400 = 2678400` (31 days). The TTL period written to the server for the month option is wrong. — `confirm_box.dart:1155` ← `AyuGram/Telegram/SourceFiles/ui/boxes/auto_delete_settings.cpp:221-231`

- [ ] [MAJOR] The entire screen-share chooser (`ScreenShareSource`, `showScreenShareChooser`, `_tryPortalScreenCast`, `_ScreenShareChooser`) is **duplicated and divergent** with a second full implementation in `call_screen.dart` (`ScreenShareSource` w/ geometry+copyWith, `showScreenShareChooser` returning `ScreenShareSource?`, its own `_tryPortalScreenCast`/`_ScreenShareChooserDialog`). `call_panel.dart` uses this file's version; `call_screen.dart` uses its own → two inconsistent screen-share UXs that will drift. AyuGram has one chooser. Violates the "no duplicate methods" rule. — `confirm_box.dart:1323-1840` ← `call_screen.dart:3164-3199` (duplicate) / `AyuGram/Telegram/SourceFiles/calls/group/ui/desktop_capture_choose_source.cpp:617-619`

- [ ] [MAJOR] Screen-share grid uses `crossAxisCount: 2` and shows the "SHARE AUDIO" checkbox unconditionally. AyuGram lays sources out in a 3-column grid (`kColumns = 3`) and only shows the audio checkbox when `chooseSourceWithAudioSupported()` is true (`_withAudio->setVisible(...)`), so an unsupported-audio platform here gets a no-op control. — `confirm_box.dart:1699,1789-1816` ← `AyuGram/Telegram/SourceFiles/calls/group/ui/desktop_capture_choose_source.cpp:31,456`

- [ ] [MAJOR] In `leaveChat` mode for a DM the header beside the avatar shows the contact's name (`widget.peerName`), but AyuGram's `DeleteChatBox` shows the action title `lng_profile_delete_conversation` ("Delete Conversation") for users (it only shows the peer name for groups/channels, "Saved Messages" for self). — `confirm_box.dart:852-862` ← `AyuGram/Telegram/SourceFiles/boxes/moderate_messages_box.cpp:970-979`

- [ ] [MAJOR] When a report step returns both options and a comment field (`hasComment`), `_ReportOptionPickerBox` renders the comment field with no Lottie illustration, but AyuGram's combined options+comment box calls `AddReportDetailsIconButton` (the `blocked_peers_empty` animation) above the field. The standalone `_ReportDetailsBox` path does show it, so the two report paths are inconsistent. — `confirm_box.dart:2038-2075` ← `AyuGram/Telegram/SourceFiles/boxes/report_messages_box.cpp:124-130`

# contacts_screen — Contacts box, contact row, edit-contact dialog, share-contact box

Scope verified: `_ContactsBox` (list + search + sort toggle), `_ContactRow` (avatar/story-ring/status/context-menu), `_EditContactBox`, `_ShareContactBox`.

**What is correct (no findings):** every callback is wired to the engine — `getContacts`, `resolveUsername`, `searchGlobalChats`, `addContact`/`addContactByUser`, `deleteContact`, `blockUser`, `suggestContactPhoto`, `suggestBirthday`, `setPersonalContactPhoto`, `clearPersonalContactPhoto`, `sendContact`, `sendMessage`, `fetchPeerStories`. No stubs, empty callbacks, TODOs, or hardcoded/fake data. Dimensions match AyuGram exactly: peer-list item 56px / photo 42px@(16,7) / name@(74,9) / status@(74,30) (`boxes.style:178-192`); story-variant 52px / photo@(18,5) / name@(70,7) / status@(70,27) (`boxes.style:986-1003`); edit-cover 108px / avatar 72px@(19,18) / name@(109,33) / status@(109,57) (`info.style:535-596`); name-field margin (19,0,19,10) (`boxes.style:819`); sort button 48×54, ripple 42px@(1,6) (`boxes.style:162-170`); sort-by-online throttle 3000ms (`peer_list_controllers.cpp:62`); share grid 108px / radius 28·24 / skip 6 / activate 150ms (`boxes.style:228-248`); note limit 128 (`data_premium_limits.cpp:204`); suggest-birthday/photo/reset visibility conditions match (`edit_contact_box.cpp:590,619,712`).

## Findings

- [ ] [MAJOR] Share-contact box renders as a full-screen `Material` route (no width constraint) instead of a centered fixed-width box — AyuGram presents the contact recipient chooser as a centered `Box<PeerListBox>` and the generic ShareBox as a centered `Ui::BoxContent` (~`st::boxWideWidth`). This also makes it inconsistent with the two sibling dialogs in this very file (`_ContactsBox`/`_EditContactBox` both use `Dialog` + `ConstrainedBox(maxWidth: _boxWideWidth=364)`). On desktop the share box fills the whole window with 4 stretched columns. — `contacts_screen.dart:2049` & `contacts_screen.dart:2226` ← `AyuGram/window/window_peer_menu.cpp:2198`

- [ ] [MAJOR] "Suggest Birthday" opens Flutter's Material `showDatePicker` (calendar grid) instead of Telegram's themed birthday box — AyuGram routes the click to `internal:edit_birthday:suggest:<id>` which opens `EditBirthdayBox` (day/month/year scroller, Telegram-styled). The Material picker is a visually foreign control in both desktop and mobile modes. — `contacts_screen.dart:1593` ← `AyuGram/boxes/peers/edit_contact_box.cpp:582`

- [ ] [MAJOR] "Suggest photo" / "Set personal photo" open a bare `FilePicker` and send the raw file path immediately — AyuGram's `showPhotoMenu` offers a source menu (Photo from file, **Photo from clipboard** when available, **emoji-avatar builder**), then runs the chosen image through `PrepareProfilePhotoFromFile` (ellipse-crop photo editor + a "Suggest/Set photo for {user}?" confirmation) before upload. The Dart skips the source menu, the crop editor, and the confirmation — an arbitrary-aspect image is sent with no preview/confirm. — `contacts_screen.dart:1577` & `contacts_screen.dart:1618` ← `AyuGram/boxes/peers/edit_contact_box.cpp:798`

- [ ] [MAJOR] Edit-contact Notes field is a plain `TextField` with no emoji button and no markdown — AyuGram's notes field (`setupNotesField`) enables markdown (bold/italic/underline/strike/spoiler), attaches a tabbed emoji panel via `AddEmojiToggleToField`, supports custom emoji, and sends the note as `TextWithEntities`. The Dart sends plain text only, so formatting/emoji in contact notes is impossible. — `contacts_screen.dart:1803` ← `AyuGram/boxes/peers/edit_contact_box.cpp:437`

# create_giveaway_box — Boosts via Gifts / Create Giveaway box

Audited `dart/lib/ui/create_giveaway_box.dart` against AyuGram's
`info/channel_statistics/boosts/create_giveaway_box.cpp` and its helpers
(`giveaway/giveaway_list_controllers.cpp`, `giveaway/select_countries_box.cpp`,
`api/api_premium.cpp`). Engine wiring is real (`getGiftCodeOptions`,
`getStarsGiveawayOptions`, `getGiveawayPeriodMax`, `launch{Random,Credits,Prepaid}Giveaway`
all hit `dart/lib/bridge/engine_service.dart` → Go). Findings below are missing
capabilities / data-fidelity gaps vs the source.

- [ ] [CRITICAL] "Award specific users" giveaway mode is entirely missing. In the source the Random/"Premium Subscriptions" row is clickable and opens `AwardMembersListController` (a member peer-picker); selecting members flips `isSpecificUsers()`, retitles the button "Start Giveaway"→"Award", and sends `InvoicePremiumGiftCodeUsers` to gift premium to chosen winners. The Dart tile only toggles a radio with `setState(() => _type = random)` — there is no peer picker, no "Award" mode, and no engine method for it. — `create_giveaway_box.dart:506` / `create_giveaway_box.dart:511` ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:392` (row `setClickedCallback` → `AwardMembersListController`, lines 411-456) + `AyuGram/info/channel_statistics/boosts/giveaway/giveaway_list_controllers.cpp:112`

- [ ] [CRITICAL] Country picker uses a hardcoded 73-country subset instead of the real country database, so ~127 countries can never be selected to restrict a giveaway. The source builds the list from `Countries::Instance().list()` (the full ISO database, ~200 entries with flag/alt-name). A full database already exists in this project at `dart/lib/utils/country_data.dart` (~200 `CountryInfo` with `iso`/`name`/`flag`) but is not used here; the box also re-implements its own `_countryFlag` duplicating `CountryInfo.flag`. — `create_giveaway_box.dart:1597` (hardcoded `_countries` map) / `create_giveaway_box.dart:1643` (filter over it) / `create_giveaway_box.dart:1631` (duplicate flag fn) ← `AyuGram/info/channel_statistics/boosts/giveaway/select_countries_box.cpp:81` (`Countries::Instance().list()`)

- [ ] [MAJOR] Extended Stars (credits) options are permanently unreachable — no "Show More" button. The source renders every option and adds an `AddShowMoreButton` ("Show more") that reveals `option.isExtended` rows on click. The Dart filter drops extended options unless already-default/selected and provides no affordance to expand them, so non-default extended star tiers can never be chosen. — `create_giveaway_box.dart:785` (`return !(opt['extended'] == true) || opt['is_default'] == true || entry.key == _selectedCreditsOptionIndex;`) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:683` (Show-more wrap, lines 683-694; `buttonWrap->toggleOn(creditsState->isExtended...)` line 678)

- [ ] [MAJOR] `boostsPerPremium` is hardcoded to 4 instead of read from app config, so every "× N boosts" figure (slider subtitle, channel status, Start button badge, prepaid fallback) is wrong whenever the server's `giveaway_boosts_per_premium` ≠ 4. The source reads it from `appConfig` (fallback 4). The Go engine already parses the same app-config JSON object for `giveaway_period_max` but never exposes `giveaway_boosts_per_premium`. — `create_giveaway_box.dart:89` (`final int _boostsPerPremium = 4;`) ← `AyuGram/api/api_premium.cpp:689` (`giveawayBoostsPerPremium()` → `appConfig().get("giveaway_boosts_per_premium", 4)`); used at `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:751`

- [ ] [MAJOR] Channels section omits the host-channel row and its boost status. The source always lists the boosted channel itself as row 0 via `SelectedChannelsListController::prepare()` and sets its status to "this channel will receive N boosts" via `setTopStatus`. The Dart `_buildChannelsSection` only renders *additional* channels plus an "Add Channel" button — the host channel and the per-channel boost-count status never appear. — `create_giveaway_box.dart:974` (section builds from `_additionalChannelNames` only) ← `AyuGram/info/channel_statistics/boosts/giveaway/giveaway_list_controllers.cpp:359` (`prepare()` appends host channel) + `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:888` (`setTopStatus` boost count)

- [ ] [MAJOR] Add-Channel picker has wrong eligibility + no confirmation + no max limit. The source fetches eligible channels via `stories.GetChatsToSend` and only collects broadcast channels (`!channel->isMegagroup()`), shows a confirm box when adding a channel that has no public username (`lng_giveaway_channels_confirm`), and enforces `giveawayAddPeersMax()`. The Dart `_addChannel` filters the locally cached chat list including `ChatType.group` (megagroups), adds the selection immediately with no username confirmation, and enforces no maximum. — `create_giveaway_box.dart:306` (`_addChannel`, filter `channel || group` at 313-317) ← `AyuGram/info/channel_statistics/boosts/giveaway/giveaway_list_controllers.cpp:250` (`prepare()` via `stories.GetChatsToSend`) + `:231` (no-username confirm) + `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:924` (`giveawayAddPeersMax` error callback)

- [ ] [MAJOR] Country selection enforces no maximum. The source wraps the done/add path with `CreateErrorCallback(giveawayCountriesMax(), …)` (app-config limit, fallback 10) and refuses additions past the cap with a toast. The Dart `_CountryPickerBox` lets the user check unlimited countries and returns them all. — `create_giveaway_box.dart:1714` (toggle add with no cap) ← `AyuGram/info/channel_statistics/boosts/create_giveaway_box.cpp:967` (`giveawayCountriesMax` error callback) + `AyuGram/api/api_premium.cpp:696` (`giveawayCountriesMax()`)

# ayu_filter — AyuGram regex-filter engine (filtering, blocked/shadowban hiding, import/export)

Audited `dart/lib/data/ayu_filter.dart` against AyuGram's `ayu/features/filters/`
(`filters_controller.cpp`, `filters_cache_controller.cpp`, `filters_utils.cpp`) plus
the context-menu / data-session call sites. The regex compile pipeline, `extractMatchBlob`,
`typeOfMessage` mapping, cache structure, and the per-message regex/exclusion matching are
faithful and genuinely wired into rendering (`chat_view.dart:3155`) and notifications
(`chat_state.dart:2589`). The issues below are unwired engine hooks and one export-format
break.

- [ ] [CRITICAL] "Show / Hide filtered messages" has NO UI entry point — `filteredMessagesShown()` and `toggleFilteredMessagesShown()` are public engine methods with ZERO callers anywhere in `dart/` (grep confirms only self-references). In AyuGram this is the user's only way to reveal regex-hidden messages: a peer context-menu item that reads `FiltersController::filteredMessagesShown(peer)` and flips it via `toggleFilteredMessagesShown(peer)`, label toggling between Show/Hide. Without a caller, once a message is filtered it is permanently invisible in uniclient — the whole reveal capability (and the `_chatFilteredCount`/`_hiddenBlockedChats` bookkeeping that feeds it) is dead. — `ayu_filter.dart:765` (`filteredMessagesShown`), `ayu_filter.dart:778` (`toggleFilteredMessagesShown`) ← `AyuGram/ayu/ui/context_menu/context_menu.cpp:258` (and `258-271`), `AyuGram/ayu/features/filters/filters_controller.cpp:189`

- [ ] [MAJOR] Edited messages are never re-filtered — `invalidateMessage()` (the analogue of AyuGram's `FiltersController::invalidate`) has ZERO callers; in particular the edit handler `ChatState._handleMsgEdited` updates `contentText` and calls `notifyListeners()` but never invalidates the filter cache. Because `isFiltered` returns the `_messageCache[chatId:msgId]` verdict without re-extracting the blob, an incoming message edited to newly match a filter stays visible, and a hidden message edited to no longer match stays hidden — until an unrelated `rebuildCache()`. AyuGram invalidates on every message update so the verdict is recomputed. — `ayu_filter.dart:783` (`invalidateMessage`, no callers; `chat_state.dart:2730` `_handleMsgEdited` omits the call) ← `AyuGram/Telegram/SourceFiles/data/data_session.cpp:2750` (`FiltersController::invalidate(existing)` on edit), `AyuGram/ayu/features/filters/filters_controller.cpp:206`

- [ ] [MAJOR] Shared-filter export omits `dialogId` instead of writing explicit JSON `null`, breaking round-trip into real AyuGram for the most common filter type. `RegexFilter.toJson` only emits the key `if (dialogId != null && dialogId!.isNotEmpty)`, so a shared filter exports with NO `dialogId` field. AyuGram always writes the key — `filterJson["dialogId"] = QJsonValue()` (explicit null) for shared filters. On import AyuGram does `if (!dialogIdValue.isNull()) regex.dialogId = ...toLongLong()`; a *missing* key is `QJsonValue::Undefined`, and `Undefined.isNull()` is **false**, so the branch runs and `Undefined.toVariant().toLongLong()` yields `0`. The shared filter is imported as a per-dialog filter for `dialogId == 0` (filed under `byDialogId[0]`, never matched), i.e. it silently disappears. Export must emit `'dialogId': null` for shared filters. — `ayu_filter.dart:52` (conditional key in `toJson`), `ayu_filter.dart:549` (`exportFilters` reuses `toJson`) ← `AyuGram/ayu/features/filters/filters_utils.cpp:478` (writes explicit null), `AyuGram/ayu/features/filters/filters_utils.cpp:727` (import `!isNull()` check)

- [ ] [MAJOR] `_filterBlocked` runs the forwarded-original-sender shadowban/block check unconditionally; AyuGram gates the entire block check behind `from() != peer`. AyuGram's `filterBlocked` only calls `isBlocked(item)` (which contains the forwarded check) when `item->from() != item->history()->peer`, so in any chat where the sender IS the peer (1-1 DMs, channel posts) it never hides via block/shadowban. uniclient gates only the *direct*-sender branch on `msg.senderId != msg.chatId`, then checks `forwardFrom` regardless. Result: a DM/channel message forwarded from a shadowbanned or blocked user is hidden by uniclient but shown by AyuGram. — `ayu_filter.dart:874` (ungated `fwdId` branch, `868-880`) ← `AyuGram/ayu/features/filters/filters_controller.cpp:31` (`from() != peer` gate around `isBlocked`), `AyuGram/ayu/features/filters/filters_controller.cpp:119` (forwarded check lives inside `isBlocked`)

# emoji_data — emoji keyword data + suggestion/completion engine

Port of AyuGram's emoji keyword system: the legacy built-in `Completer`
(`lib_ui/emoji_suggestions/emoji_suggestions.cpp`) + server lang-pack
`EmojiKeywords` (`SourceFiles/chat_helpers/emoji_keywords.cpp`).

**Wiring is real and complete — NOT a placeholder.** Server keywords are
fetched (chat_view.dart `_fetchEmojiKeywordsForLangs` → `getEmojiKeywordsLanguages`
→ diff/full → `loadServerKeywords`/`loadServerKeywordsDiff`), cache + state are
persisted (main.dart `init`/`saveCallback`/`loadState`), skin-tone variants are
wired (emoji_panel.dart `skinToneResolver`), recents via `recordRecent`, and
`searchEmoji` is consumed by chat_view, input_dialogs, message_bubble,
my_profile_page. `MustAddPostfix`/`_applyPostfix` (0xFE0F), `SkipExactKeyword`,
`NormalizeQuery`/`NormalizeKey`, the whole `Completer` matcher, `PrioritizeRecent`
and `ApplyVariants` all track the C++ faithfully. The findings below are
behavioral/ordering deviations, not stubs.

- [ ] [MAJOR] Built-in keyword word-splitting splits on `'_'` ONLY, but AyuGram splits on **all** non-letter/number chars (keeping `-`/`+` only before a digit). Hyphenated keywords — `blond-haired_man` (+ all skin-tone variants), `e-mail`, `fleur-de-lis`, `non-potable_water` — become single words `blond-haired`/`e-mail`/etc. instead of `blond`+`haired`+`man`, `e`+`mail`, … So interior-word queries that DO match in AyuGram return nothing here: `:haired` → 🧑 (blond-haired person), `:mail` → 📧, `:potable` → 🚱, `:de`/`:lis` → ⚜️. Verified: `_matchLegacyWords(["blond-haired","man"], "haired")` returns -1 (no word starts with "haired"), while C++ `["blond","haired","man"]` matches. — `emoji_data.dart:2899` ← `Telegram/codegen/codegen/emoji/replaces.cpp:47-63`

- [ ] [MAJOR] `_prioritizeRecent` is fed an incomplete recent list, so it rarely prioritizes the emoji the user actually uses. AyuGram's `PrioritizeRecent` reads the single global `Core::App().settings().recentEmoji()`, updated whenever an emoji is used from ANY source (panel pick, sent message, reaction, suggestion). Here `EmojiKeywords._recentEmojis` is fed by `recordRecent`, which is called ONLY when an inline autocomplete suggestion is accepted (chat_view.dart:3902, 3923). Emoji-panel picks update a SEPARATE list (`emoji_panel.dart:911 _recentEmojis`) and never call `recordRecent`; sent text and reactions never record either. Net effect: the most common "recent" source (the panel) does not influence inline suggestion ordering. — `emoji_data.dart:3063` / `emoji_data.dart:3261` ← `Telegram/SourceFiles/chat_helpers/emoji_keywords.cpp:650-654`

- [ ] [MAJOR] Exact-vs-prefix results are bucketed GLOBALLY across sources (`result = [...exactMatches, ...prefixMatches]`), so a built-in/legacy EXACT match floats ahead of a server-lang-pack PREFIX match. AyuGram never does this: `query()` appends all per-pack results first and `AppendLegacySuggestions` inserts legacy results strictly AFTER all pack results (server data always precedes built-in fallback). The Dart global float (`exactMatches`/`prefixMatches` are accumulated across both `_searchLangPack` and `_searchLegacyData`, then concatenated) inverts that precedence whenever legacy contributes an exact match the pack doesn't supply as exact. — `emoji_data.dart:3133-3137` ← `Telegram/SourceFiles/chat_helpers/emoji_keywords.cpp:615-641`

- [ ] [MAJOR] The single-character-query fast path is not replicated, changing the order of 1-char fuzzy suggestions (e.g. `:a`, allowed by the widget since `simple`/exact only applies to non-lowercase `:X`). AyuGram `processInitialList` short-circuits when `_querySize == 1`: it adds EVERY first-char-indexed candidate with `wordsUsed = 1` in declaration order, with no matching pass. Dart always runs `_matchLegacyWords`, so multi-word candidates matched on an interior word get `wordsUsed = 2`, which `_legacyRankKey` then demotes below single-word `wordsUsed = 1` matches — reordering the list versus AyuGram (same result set, different order). — `emoji_data.dart:3188-3230` ← `Telegram/lib_ui/emoji_suggestions/emoji_suggestions.cpp:267-276`

# main — app bootstrap, theme-revert overlay (§25.9.3), passcode lock screen

Audited `dart/lib/main.dart` against AyuGram's `window_theme_warning.cpp` (theme
revert box) and `window_lock_widgets.cpp` (passcode lock screen). The bulk of the
file is app bootstrap, engine/tray/notification wiring, and a `kDebugMode`-only
debug-command poller + gesture/key dispatch (test harness — no AyuGram analogue,
not auditable). The two user-facing UI components that DO map to AyuGram are
faithfully built dimensionally:

- Theme-revert box: width 364 (`_boxWidth`) = `boxWideWidth:364px`; height 150 =
  `themeWarningHeight:150px`; body text top 60 = `themeWarningTextTop:60px`; title
  16px/w600 at (24,13) = `boxTitleFont:font(16px semibold)` + `boxTitlePosition:(24,13)`;
  total 15999ms = `kWaitBeforeRevertMs`; 100ms timer. ✓
- Passcode lock: field width 225 + height 61 = `introPhone` (width:225px / heightMin:61px);
  contentPadding (1,27,1,6) = `passcodeInput.textMargins:(1,27,1,6)`; header 19px in
  80px band = `passcodeHeaderFont:19px` / `passcodeHeaderHeight:80px`; submit 225×42
  radius 6 = `passcodeSubmit{width:225}` over `introNextButton{height:42,radius:6}`;
  submitSkip 40 = `passcodeSubmitSkip:40px`; system-unlock 32×36 = `passcodeSystemUnlock{32,36}`;
  forgot-passcode→resetWithForgottenPasscode wiring correct. ✓ Engine wiring
  (checkPasscode / passcodeCanTry / getPasscodeConfig / system unlock) all real. ✓

Findings below are behavioral / missing-element deviations (skipping pure
color/1px-font/positioning cosmetics).

- [ ] [MAJOR] Theme-revert countdown uses `.ceil()` instead of integer truncation, so it displays "16" and auto-reverts at ~16s, whereas AyuGram displays "15" and reverts at 15s. AyuGram inits `_secondsLeft(kWaitBeforeRevertMs / 1000)` = 15999/1000 = **15** (C++ int division) and recomputes `setSecondsLeft((kWaitBeforeRevertMs - msPassed) / 1000)` by truncation, reverting when that hits ≤0 (msPassed ≥ 15000 = 15.0s). The Dart computes `(_remainingMs / 1000).ceil()` → `ceil(15.999)` = **16** as the first shown value, off-by-one for every tick, and only reverts when `_remainingMs <= 0` at elapsed ≥ 15999ms (~16.0s). Fix: use `~/` (or `.floor()`) for the displayed seconds and the init value. — `main.dart:2542` (timer) & `main.dart:2617` (`_buildBox` display), revert at `main.dart:2539` ← `AyuGramDesktop/Telegram/SourceFiles/window/themes/window_theme_warning.cpp:31` (init `/1000`), `:96` (`setSecondsLeft((...)/1000)`), `:99-100` (`if (secondsLeft <= 0) Revert()`)

- [ ] [MAJOR] Passcode lock screen is missing AyuGram's "system unlock later" info label (`setupSystemUnlockInfo` / `passcodeSystemUnlockLater`). AyuGram has two mutually-exclusive paths: when the account domain IS started it wires the active unlock IconButton (`setupSystemUnlock`), but when the domain is NOT started yet (the cold-start lock that protects local storage, before login) it instead shows a `FlatLabel` beneath the logout link with the platform hint text (Windows Hello / Touch ID / Apple Watch / system password) so the user knows system unlock is available once past this screen. The Dart only ever renders the IconButton (gated on `_showSystemUnlockButton`) and has no equivalent info-label branch, so that startup state shows nothing. — `main.dart:2773-2774` (`_showSystemUnlockButton` is the only gate) & `main.dart:3039-3059` (only the IconButton is built; no info label) ← `AyuGramDesktop/Telegram/SourceFiles/window/window_lock_widgets.cpp:123-129` (started? → `setupSystemUnlock` else `setupSystemUnlockInfo`), `:132-161` (`setupSystemUnlockInfo` builds the label), style `AyuGramDesktop/Telegram/SourceFiles/boxes/boxes.style:319` (`passcodeSystemUnlockLater`)

- [ ] [MAJOR] Empty-passcode submit shows an invented error message instead of AyuGram's silent field-shake. AyuGram's `submit()` on empty input calls only `_passcode->showError()` (the shake/red-border animation) with NO text — there is no `lng_passcode_empty` string in the Telegram lang at all. The Dart calls `_showError(TrStrings.lngPasscodeEmpty())`, and `lngPasscodeEmpty()` is a fabricated string (`'Please enter your passcode'`, `strings.dart:28`) with no AyuGram counterpart, rendering an error label AyuGram never displays. Fix: on empty input, trigger the shake animation only (no error text). — `main.dart:2828-2830` (`if (entered.isEmpty) _showError(TrStrings.lngPasscodeEmpty())`) ← `AyuGramDesktop/Telegram/SourceFiles/window/window_lock_widgets.cpp:260-263` (`if (_passcode->text().isEmpty()) { _passcode->showError(); return; }`)

## static_scan — Mechanical pattern detection (zero AI cost)

- [ ] [CRITICAL] Empty callback — `photo_crop_editor.dart:2784` — `            onPressed: () {},`
- [ ] [CRITICAL] Empty callback — `shell.dart:778` — `          onTap: () {},`
- [ ] [CRITICAL] Empty callback — `shortcuts_settings_screen.dart:545` — `            onTap: () {},`
- [ ] [CRITICAL] Empty callback — `shortcuts_settings_screen.dart:638` — `        onTap: () {},`
- [ ] [CRITICAL] Empty callback — `web_app_panel.dart:1540` — `              onTap: () {},`
- [ ] [CRITICAL] Empty callback — `chat_view.dart:19961` — `          onTap: () {},`
- [ ] [CRITICAL] Empty callback — `chat_list_panel.dart:1396` — `                onTap: () {},`
- [ ] [CRITICAL] Fake feature — `web_app_panel.dart:542` — `        content: const Text('QR code scanning is not supported on this platform.'),`
- [ ] [CRITICAL] Fake feature — `web_app_panel.dart:560` — `        content: const Text('Story sharing is not supported.'),`
- [ ] [CRITICAL] Fake feature — `ayu_appearance_page.dart:1159` — `                      child: const Icon(Icons.image_not_supported,`
- [ ] [CRITICAL] Fake feature — `ayu_other_page.dart:165` — `        const SnackBar(content: Text('URL scheme registration is not supported on this platform')),`
- [ ] [CRITICAL] Fake feature — `advanced_settings_screen.dart:3841` — `          'This proxy type is not supported or the link is invalid.',`
- [ ] [MAJOR] debugPrint stub (should be real implementation) — `contacts_screen.dart:663`
- [ ] [MAJOR] debugPrint stub (should be real implementation) — `create_group_wizard.dart:279`
- [ ] [MAJOR] debugPrint stub (should be real implementation) — `create_group_wizard.dart:801`
- [ ] [MAJOR] debugPrint stub (should be real implementation) — `create_group_wizard.dart:853`
- [ ] [MAJOR] debugPrint stub (should be real implementation) — `chat_view.dart:15127`
- [ ] [MAJOR] debugPrint stub (should be real implementation) — `chat_view.dart:15132`
- [ ] [MAJOR] debugPrint stub (should be real implementation) — `chat_view.dart:15138`
- [ ] [MAJOR] debugPrint stub (should be real implementation) — `chat_view.dart:15143`
- [ ] [MAJOR] debugPrint stub (should be real implementation) — `chat_view.dart:15162`
- [ ] [MAJOR] debugPrint stub (should be real implementation) — `chat_list_panel.dart:1465`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `calls_screen.dart:2567`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `create_giveaway_box.dart:472`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `folders_settings_screen.dart:371`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `folders_settings_screen.dart:3831`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `folders_settings_screen.dart:3957`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `folders_settings_screen.dart:4052`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `folders_settings_screen.dart:4172`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `ghost_settings_page.dart:76`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `hamburger_drawer.dart:96`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `input_dialogs.dart:537`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `input_dialogs.dart:2380`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `my_profile_page.dart:390`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `payment_panel.dart:990`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `peer_short_info.dart:548`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `privacy_settings_screen.dart:661`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `privacy_settings_screen.dart:5355`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `privacy_settings_screen.dart:6339`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `privacy_settings_screen.dart:8146`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:273`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:2472`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:2802`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:3164`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:3287`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:3520`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:3713`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:3797`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:3895`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:4004`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:4106`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `settings_screen.dart:4130`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `chat_settings_screen.dart:375`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `notifications_settings_screen.dart:190`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `notifications_settings_screen.dart:1847`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `notifications_settings_screen.dart:3452`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `admin_tools.dart:298`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `admin_tools.dart:2744`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `admin_tools.dart:3548`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `admin_tools.dart:4243`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `admin_tools.dart:5473`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `admin_tools.dart:5944`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `admin_tools.dart:7748`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `admin_tools.dart:8193`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `admin_tools.dart:8454`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `ayugram_settings_screen.dart:62`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `ayu_section_builder.dart:1054`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `emoji_panel.dart:2726`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `info_panel.dart:5544`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `info_panel.dart:6273`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `info_panel.dart:8347`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `info_panel.dart:8951`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `info_panel.dart:9966`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `chat_view.dart:17653`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `chat_view.dart:18977`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `chat_view.dart:19075`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `chat_view.dart:22172`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `chat_list_panel.dart:786`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `chat_list_panel.dart:4960`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `chat_export.dart:1378`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `chat_export.dart:1899`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `chat_export.dart:2268`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `advanced_settings_screen.dart:149`
- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — `advanced_settings_screen.dart:4470`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `engine_service.dart:5259`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `engine_service.dart:6342`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `audio_service.dart:131`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `audio_service.dart:145`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `audio_service.dart:503`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `audio_service.dart:536`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:983`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:1207`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:1255`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:1289`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:1308`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:1373`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:1402`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:1444`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:1542`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:1557`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:2285`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:2313`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:2453`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:2465`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_state.dart:2995`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:1158`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:1168`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:1178`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:1197`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:1200`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:1210`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:1220`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:1427`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:1431`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:2013`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:2460`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:2690`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:2700`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:2727`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:2958`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:3054`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:3068`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:3274`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:3299`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:3335`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:3410`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:3560`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:3578`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:3598`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:3770`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:4092`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:4105`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:4113`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:4341`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `app_state.dart:4345`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `wallpaper.dart:812`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `spell_service.dart:60`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `debug.dart:40`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `system_tray.dart:105`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_panel.dart:194`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_panel.dart:195`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_panel.dart:196`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_panel.dart:291`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_panel.dart:2595`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:229`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:2140`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:2149`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3413`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3427`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3446`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3461`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3479`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3507`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3525`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3528`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3551`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3554`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3584`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3593`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3619`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `call_screen.dart:3628`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `calls_screen.dart:212`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `calls_screen.dart:291`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `calls_screen.dart:327`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `calls_screen.dart:1039`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `calls_screen.dart:2114`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `calls_screen.dart:2414`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `calls_screen.dart:2429`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `calls_screen.dart:2448`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `calls_screen.dart:2461`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `calls_screen.dart:2478`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `contacts_screen.dart:195`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `contacts_screen.dart:1520`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `contacts_screen.dart:2157`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `create_group_wizard.dart:169`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `create_group_wizard.dart:545`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `create_group_wizard.dart:559`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `create_group_wizard.dart:698`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `create_group_wizard.dart:2715`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `create_group_wizard.dart:2773`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `create_group_wizard.dart:2941`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `custom_emoji_cache.dart:119`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `custom_emoji_cache.dart:237`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `custom_emoji_cache.dart:245`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `custom_emoji_cache.dart:253`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `custom_emoji_cache.dart:327`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `edit_forum_topic_box.dart:237`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_status_widget.dart:144`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `forum_topic_icon.dart:443`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `folders_settings_screen.dart:148`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `folders_settings_screen.dart:160`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `folders_settings_screen.dart:170`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `folders_settings_screen.dart:4455`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `hamburger_drawer.dart:620`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `keyboard_shortcuts.dart:601`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `keyboard_shortcuts.dart:622`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `keyboard_shortcuts.dart:777`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `keyboard_shortcuts.dart:1236`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `instant_view.dart:2874`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:509`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:666`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:681`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:2785`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:3004`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:3009`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:3017`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:3027`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:3055`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:3187`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:4661`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:4672`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:5987`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:6529`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:6844`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `media_viewer.dart:7525`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `my_profile_page.dart:750`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `my_profile_page.dart:941`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `my_profile_page.dart:1375`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `my_profile_page.dart:1386`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `my_profile_page.dart:1394`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `my_profile_page.dart:1410`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `my_profile_page.dart:1426`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `photo_crop_editor.dart:214`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `photo_crop_editor.dart:853`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `peer_short_info.dart:339`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `reactions_detail.dart:168`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `reactions_detail.dart:198`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `reactions_detail.dart:208`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `reactions_detail.dart:1432`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `privacy_settings_screen.dart:829`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `privacy_settings_screen.dart:3436`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `privacy_settings_screen.dart:4477`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `privacy_settings_screen.dart:7528`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `privacy_settings_screen.dart:7832`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:508`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:524`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:535`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:629`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:882`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:888`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:916`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:925`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:1036`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:1076`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:1470`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:1687`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:1722`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:1809`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:2266`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:3143`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:3234`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:3525`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `send_files_box.dart:3618`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:131`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:157`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:1048`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:1065`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:1209`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:1226`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:2776`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:3141`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:3924`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:3986`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:4167`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `settings_screen.dart:4248`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `spoiler_animation.dart:318`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `spoiler_animation.dart:749`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `spoiler_animation.dart:757`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `sticker_pack_viewer.dart:183`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `sticker_pack_viewer.dart:744`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `sticker_pack_viewer.dart:747`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `telegram_toast.dart:410`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `web_app_panel.dart:274`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `web_app_panel.dart:461`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `web_app_panel.dart:477`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `web_app_panel.dart:505`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `web_app_panel.dart:753`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `web_app_panel.dart:1083`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `web_app_panel.dart:1271`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `web_app_panel.dart:1352`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `web_app_panel.dart:1450`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `web_app_panel.dart:1461`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `web_app_panel.dart:1479`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `story_editor.dart:366`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `story_editor.dart:645`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `story_editor.dart:2058`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `story_editor.dart:2105`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `story_editor.dart:3163`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_settings_screen.dart:198`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_settings_screen.dart:236`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_settings_screen.dart:696`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_settings_screen.dart:2006`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_settings_screen.dart:2862`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `ayu_appearance_page.dart:736`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `ayu_appearance_page.dart:766`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `ayu_appearance_page.dart:793`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `ayu_appearance_page.dart:815`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `ayu_appearance_page.dart:837`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notifications_settings_screen.dart:78`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notifications_settings_screen.dart:82`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notifications_settings_screen.dart:93`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notifications_settings_screen.dart:111`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notifications_settings_screen.dart:1714`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notifications_settings_screen.dart:4128`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notifications_settings_screen.dart:4264`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `theme_editor.dart:91`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:2261`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:2372`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:4173`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:4756`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:6158`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:6460`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:6711`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:9110`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:9547`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:9736`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:10152`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `message_bubble.dart:10757`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:152`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:165`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:198`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:738`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:927`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:1101`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:1211`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:1220`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:1238`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:1549`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:1717`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:1836`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:4058`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:5739`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:7319`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:7448`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `admin_tools.dart:7461`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `auth_screen.dart:122`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `auth_screen.dart:2454`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `ayu_other_page.dart:517`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `ayu_other_page.dart:534`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `ayu_filters_page.dart:1735`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `ayu_filters_page.dart:1884`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:79`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:89`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:894`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:1269`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:1412`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:1707`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:2503`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:2643`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:2928`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:3586`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:3723`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:4017`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_panel.dart:4094`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `confirm_box.dart:1501`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `confirm_box.dart:1535`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `confirm_box.dart:1538`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `confirm_box.dart:1556`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `confirm_box.dart:1599`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `confirm_box.dart:1602`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `confirm_box.dart:1662`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `confirm_box.dart:2273`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `info_panel.dart:248`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `info_panel.dart:253`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `info_panel.dart:260`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `info_panel.dart:1254`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `info_panel.dart:3038`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `info_panel.dart:3790`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `info_panel.dart:5425`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `info_panel.dart:7329`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `info_panel.dart:7664`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `info_panel.dart:8088`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `info_panel.dart:8152`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `titlebar.dart:144`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `titlebar.dart:154`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `titlebar.dart:162`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `titlebar.dart:170`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `titlebar.dart:176`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `titlebar.dart:182`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `titlebar.dart:188`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `titlebar.dart:194`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `titlebar.dart:200`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:78`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:87`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:2262`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:2921`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:2952`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:2960`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:2970`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:3007`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:3023`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:3077`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:3768`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:3783`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:3798`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:3860`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:3874`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:5157`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:8776`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:9063`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:10239`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:10393`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:12865`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:14278`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:14318`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:14333`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:14398`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:14422`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:14468`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:14518`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:14893`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:14906`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:19202`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:19360`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:21218`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_view.dart:21743`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_export.dart:230`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_export.dart:539`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_export.dart:598`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_export.dart:634`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_export.dart:640`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_export.dart:1137`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_export.dart:1140`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_export.dart:3182`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_export.dart:3185`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `chat_export.dart:3186`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:55`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:67`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:73`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:79`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:1234`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:1244`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:1992`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:2003`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:2316`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:2589`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:2599`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:2611`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `advanced_settings_screen.dart:4946`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `ayu_filter.dart:426`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_data.dart:3017`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `emoji_data.dart:3044`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notification_manager_native.dart:183`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notification_manager_native.dart:202`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notification_manager_native.dart:613`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notification_manager_native.dart:786`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notification_manager_native.dart:896`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notification_manager_native.dart:938`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notification_manager_native.dart:955`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `notification_manager_native.dart:1130`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `main.dart:73`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `main.dart:320`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `main.dart:327`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `main.dart:1698`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `main.dart:2309`
- [ ] [MAJOR] Empty catch block (silently swallows errors) — `main.dart:2770`
- [ ] [MAJOR] Potential resource leak: 1 listeners/subscriptions added but only 0 removed — `ayu_chats_page.dart`
- [ ] [MAJOR] Potential resource leak: 2 listeners/subscriptions added but only 0 removed — `ayu_filters_page.dart`
- [ ] [MAJOR] Potential resource leak: 1 listeners/subscriptions added but only 0 removed — `chat_list_row.dart`
- [ ] [MAJOR] Potential resource leak: 1 listeners/subscriptions added but only 0 removed — `compose_entities.dart`
- [ ] [MAJOR] Potential resource leak: 5 listeners/subscriptions added but only 2 removed — `instant_view.dart`
- [ ] [MAJOR] Potential resource leak: 27 listeners/subscriptions added but only 24 removed — `media_viewer.dart`
- [ ] [MAJOR] Potential resource leak: 5 listeners/subscriptions added but only 4 removed — `reactions_detail.dart`
- [ ] [MAJOR] Potential resource leak: 6 listeners/subscriptions added but only 0 removed — `stats_chart.dart`
- [ ] [MAJOR] Potential resource leak: 15 listeners/subscriptions added but only 8 removed — `chat_state.dart`
- [ ] [MAJOR] Potential timer leak: 1 timers created but only 0 cancel() calls — `ayu_other_page.dart`
- [ ] [MAJOR] Potential timer leak: 3 timers created but only 0 cancel() calls — `custom_emoji_cache.dart`
- [ ] [MAJOR] Potential timer leak: 11 timers created but only 8 cancel() calls — `emoji_panel.dart`
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/admin_tools.dart:7650` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/admin_tools.dart:8104` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/admin_tools.dart:8379` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/advanced_settings_screen.dart:2343` — setState 2 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/auth_screen.dart:1888` — setState 4 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/ayu_appearance_page.dart:444` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/ayu_appearance_page.dart:738` — setState 4 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/chat_export.dart:2110` — setState 2 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/chat_export.dart:2159` — setState 2 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/chat_settings_screen.dart:2698` — setState 2 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/chat_settings_screen.dart:2707` — setState 2 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/chat_settings_screen.dart:3836` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/chat_settings_screen.dart:3844` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/chat_settings_screen.dart:3870` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/chat_view.dart:21802` — setState 3 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/forum_topic_icon.dart:590` — setState 4 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/info_panel.dart:1488` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/info_panel.dart:7961` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/instant_view.dart:1915` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/instant_view.dart:2884` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/media_viewer.dart:6528` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/media_viewer.dart:8002` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/message_bubble.dart:2630` — setState 5 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/message_bubble.dart:6707` — setState 3 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/my_profile_page.dart:3246` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/privacy_settings_screen.dart:3438` — setState 2 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/privacy_settings_screen.dart:3481` — setState 4 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/privacy_settings_screen.dart:3617` — setState 4 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/privacy_settings_screen.dart:4127` — setState 5 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/privacy_settings_screen.dart:5168` — setState 5 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/privacy_settings_screen.dart:6198` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/privacy_settings_screen.dart:7148` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/reactions_detail.dart:1112` — setState 3 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/reactions_detail.dart:1431` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/send_files_box.dart:1181` — setState 3 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/settings_screen.dart:2383` — setState 4 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/settings_screen.dart:2390` — setState 4 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/settings_screen.dart:2934` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/settings_screen.dart:3140` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/settings_screen.dart:3237` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/settings_screen.dart:3926` — setState 3 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/settings_screen.dart:4169` — setState 3 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/sticker_pack_viewer.dart:708` — setState 5 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/story_editor.dart:365` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/titlebar.dart:143` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/titlebar.dart:161` — setState 1 lines after await
- [ ] [MAJOR] setState after await without mounted check — `/home/nako/Documents/uniclient/dart/lib/ui/titlebar.dart:169` — setState 1 lines after await
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `advanced_settings_screen.dart:2413`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `advanced_settings_screen.dart:2753`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `advanced_settings_screen.dart:4937`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `auth_screen.dart:2451`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `auth_screen.dart:2453`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `ayu_filters_page.dart:79`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `ayu_filters_page.dart:686`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `call_panel.dart:2504`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `call_panel.dart:2505`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `calls_screen.dart:660`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `calls_screen.dart:2169`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `calls_screen.dart:2582`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `chat_list_panel.dart:2715`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `chat_list_panel.dart:2716`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `chat_list_panel.dart:4759`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `chat_list_panel.dart:5000`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `chat_view.dart:21620`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `chat_view.dart:21851`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `emoji_panel.dart:1325`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `emoji_panel.dart:2558`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `folders_settings_screen.dart:398`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `folders_settings_screen.dart:426`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `folders_settings_screen.dart:453`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `folders_settings_screen.dart:454`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `folders_settings_screen.dart:456`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `folders_settings_screen.dart:463`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `info_panel.dart:1973`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `info_panel.dart:3926`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `info_panel.dart:4310`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `info_panel.dart:4395`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `info_panel.dart:4435`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `info_panel.dart:4782`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `info_panel.dart:4919`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `info_panel.dart:10220`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `message_bubble.dart:4292`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `message_bubble.dart:4434`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `message_bubble.dart:5372`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `my_profile_page.dart:3308`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `my_profile_page.dart:3309`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `reactions_detail.dart:965`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `settings_screen.dart:211`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `settings_screen.dart:212`
- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — `settings_screen.dart:3018`

