# GUI Audit — Cycle 4 Phase Ayugram (2026-06-09 18:52)

## Code Comparison (Dart vs AyuGram)

# app_state — top-level app/settings state (port of AyuGram core_settings + core_settings_proxy + ayu_settings + main_domain/passcode)

Audited `dart/lib/state/app_state.dart` (4970 lines) against AyuGram C++ ground truth:
`ayu/ayu_settings.{h,cpp}`, `core/core_settings.{h,cpp}`, `core/core_settings_proxy.h`,
`main/main_domain.{h,cpp}`, `boxes/local_storage_box.cpp`.

This is an **exceptionally faithful** port. Verified as MATCHING (no finding):

- Every `AyuSettings` field present with matching defaults (`ayu_settings.h:615-704`) — all bools/enums/ints/strings 1:1, incl. context-menu visibility enums, drawer toggles, message-field button toggles, channelBottomButton=DiscussWithFallback(2), showPeerId=BotApi(2), deletedMark="🧹", editedMark default handled by renderer substitution (`message_bubble.dart:1532` ← `ayu_settings.cpp:358`).
- `GhostModeAccountSettings` defaults + `ghostModeActive` formula + `shouldSendWithoutSound` + `setGhostModeEnabled` + lock logic 1:1 (`ayu_settings.cpp:44-152`).
- `MessageShotSettings` defaults + `setEmbeddedTheme`/`setCloudTheme`/`clearTheme`/`isCloudThemeEmpty` 1:1 (`ayu_settings.cpp:227-354`).
- `validate()` clamp ranges match the load-time clamping (`ayu_settings.cpp:481-533`): bubbleRadius[0,16], avatarCorners[0,23], wideMultiplier[0.5,4.0], recentStickersCount[1,200], context enums[0,2], translationProvider[0,3]+Native→Telegram fallback, embeddedThemeType -1|[0,3].
- Proxy constants `{5,10,15,30,60}` / default 10 (`core_settings_proxy.h:18-25`); `kDefaultVolume=0.9` (`core_settings.h:123`); `kSpeedMin/Max=0.5/2.5` (`media/media_common.h:41-42`).
- `maxAccountLimit` = `min(premiumCount+100, 200)` (`main_domain.cpp:510`, `main_domain.h:34-35`).
- `_timeLimitIndexToDays` matches `TimeLimitInDays` exactly incl. the ternary cascade (`local_storage_box.cpp` `TimeLimitInDays`).
- Auto-lock `kAutoLockTimeoutLateMs=3000` and engine wiring (`SetProxy`/`SetAutoDownload`/`SetLocalStorageLimits`/`SetPowerSaving` all exist in `go/bridge/dispatch_engine.go:1401-1501`; all `engine_service.dart` methods exist).
- Proxy default mode divergence (Dart `disabled`(0) vs C++ `System`) is functionally INVISIBLE — `go/engine/engine.go:313` treats mode 1 (system) identically to mode 0 (direct), so NOT a finding.

# audio_service — media player engine (port of AyuGram `Media::Player::Instance`)

The file is a faithful, fully-wired port of `Media::Player::Instance`: shuffle
bookkeeping, playlist advance, pause-on-call, power-save blockers, notification
ducking, listen tracking (`reportMusicListen`) and saved-position restore all
match the C++ 1:1, and every engine touchpoint is a real bridge call
(`readMessageContents`, `reportMusicListen`, `refreshDocumentFileRef`) — no
stubs, placeholders, or fake data.

Verified & closed (2026-06-10) — the three behavioral deviations below were fixed and confirmed against AyuGram ground truth (806-line rewrite, builds clean, launches without crashes in desktop + mobile):
- StoppedAtEnd persistence: `_onCompleted`→`_finishTrack` now sets `finished=true` and keeps the track LOADED (msgId preserved, never `stop()`), so the player bar persists for replay — mirrors `media_player_instance.cpp:1298-1312` (`StoppedAtEnd` keeps `data->current`) + `media_player_widget.cpp:182-195` (`tracksFinished`→`setType(Song)` restores the song display).
- changeablePlaybackSpeed gate: `_speedFor` returns 1.0× for a non-changeable track, with `changeableSpeed = isSong ? durationSeconds>=60 : true` (voice/round always changeable) — mirrors `LookupPlaybackSpeed` (`media_player_instance.cpp:65-74`) + `data_audio_msg_id.cpp:28-30`; speed control hidden via `currentChangeableSpeed`. (Note: AyuGram's `duration()` is in ms so its literal `>=60` is a 60 ms gate — an upstream unit quirk; the port follows the documented `// 1 minute` intent = 60 s.)
- Independent mixer tracks: `_song`/`_voice` are separate `_AudioTrack`s with their own players (like `_songTracks`/`_audioTracks`, `media_audio.cpp:578-579`); `playVoice` tears down only its own type so a voice over music no longer destroys the music, ducks it to `kSuppressRatioSong` (0.05), and restores the song display when the voice finishes.

# auth_state — auth-flow state controller (ChangeNotifier) bridging engine FSM ↔ intro UI

Audited against AyuGram's intro flow (`intro_widget.cpp`, `intro_step.cpp`, `intro_qr.cpp`,
`intro_code.cpp`, `intro_password_check.cpp`) and the uniclient engine FSM (`go/engine/auth.go`).

**Verified correct (no action needed):** every action is wired to the engine
(`startAuth`/`submitInput`/`switchToMethod`/`cancelAuth` → `EngineService` → Go core); engine
`auth_state` events flow through `_handleAuthEvent` and update `_currentAuth`; the QR-expiry
fallback (`_onQrExpired`, line 255) correctly re-exports via `submitAuthInput('')` and is backed by
the engine's push-based `onQRTokenUpdate` (auth.go:147,164) + guaranteed `EventAuthState` emission
(auth.go:156), so a `ready`-during-refresh is never lost; `qrExpiresIn` is seconds-remaining
(telegram.go:13956) so `qrExpiresIn - 1` (line 249) is a correct early-refresh margin; the pushed
login-code seq pattern (`_handleLoginCode`, line 186) mirrors `setHandleLoginCode`
(intro_code.cpp:59); the SRP_ID_INVALID finalize (line 291) mirrors `handleSrpIdInvalid`
(intro_password_check.cpp:171); all magic-string commands relayed via `submitInput`
(`__resend_code`/`__no_telegram_code`/`__request_recovery`/`__reset_account`) are handled by the
engine (auth.go:489,504,579,594). No placeholders, stubs, mock data, empty callbacks, or TODOs.

Verified & closed (2026-06-10) — back-navigation now does a step-back, not a teardown. Engine `GoBackAuth` (auth.go:246) pops a per-flow step-history (`authFlow.history`, pushed on each genuine forward step in `SubmitAuthInput` — state change or new collected input, skipping in-place refreshes/terminal states) and re-emits the prior step, keeping the MTProto core + collected phone/code intact; `AuthState.goBack()` (auth_state.dart:163) drives it and falls through to `cancelAuth` only at the first step. The intro back arrow is rewired `cancelAuth`→`goBack` (auth_screen.dart:481) and `choose` gains a back arrow as the first-step exit (`_canGoBack`). Confirmed at runtime (desktop 1024×768 + mobile 400×720, Go+Flutter build clean, no crashes): `input`→back returns to `choose` within the SAME live flow (same accountId, `startAuth` count stays 1 → no flow restart; bridge returns the 102B prior-state proto), and back from `choose` returns the 0B "first step" signal → `cancelAuth` exits to the chat list. Faithful to AyuGram `backRequested → historyMove(StackAction::Back)` popping `_stepHistory` (intro_widget.cpp:888,373-385).

Verified & closed (2026-06-10) — ayu_forward — intelligent forward orchestration: resend-as-own progress now tracks genuine send/download, not enqueue. [MAJOR #1] `Engine.ResendAsOwn`/`ResendAlbumAsOwn` now run `processPendingItem` SYNCHRONOUSLY (inline `return e.processPendingItem(...)`, no `go func`; pending.go:484-512) and `processPendingItem` returns its terminal error, so the Dart `await engine.resendAsOwn/resendAlbumAsOwn` blocks until the message is genuinely sent and the per-group `sentInChunk` counter advances on real completion — mirroring AyuGram's `state->sentMessages = i+1` only after each blocking send (ayu_forward.cpp:439). [MAJOR #2] New `Engine.PreloadResendMedia` (pending.go:533, JSON-dispatched via dispatch_engine.go) synchronously downloads the whole chunk's media up front into the shared `os.TempDir()/uniclient_resend/<msgID><ext>` dir; `ayu_forward.dart` (268-340) runs a real blocking `phase: downloading` over that whole call (gated on `_chunkHasDownloadableMedia`, mirroring AyuGram's non-empty `toBeDownloaded`), then a `sending` phase; `executeResendAsOwn`/`executeResendAlbum` reuse the cached file (skip re-download, `alreadyDownloaded` check) so the Sending phase only uploads — mirroring AyuGram's up-front blocking `AyuSync::loadDocuments` + `Downloading` state (ayu_forward.cpp:355-360, ayu_sync.cpp:86-130). Path computation confirmed identical across `PreloadResendMedia`/`executeResendAsOwn`/`executeResendAlbum`; the synchronous blocking runs on the FFI worker-isolate pool (bridge_ffi.dart) so the UI never freezes. Runtime-proven against the live account (Go libcores.so + Flutter debug build clean, app launches/reconnects/renders desktop 1024×768 + mobile 400×720, no crashes): driving the real bridge `dispatchEngine` path, `PreloadResendMedia` BLOCKED 485 ms and produced a complete 37 709-byte file at the shared reuse path before returning (was an instant enqueue), and `ResendAsOwn` BLOCKED 455 ms then completed the send synchronously (`err=nil`) — vs the old fire-and-forget `return nil` in <1 ms.

Verified & closed (2026-06-10) — chat_state send-action/typing port + chat-theme night variant: 4 MAJOR items, all confirmed faithful to AyuGram ground truth (`history/view/history_view_send_action.cpp`, `data/data_cloud_themes.cpp:234`, `window/themes/window_theme.cpp:1411`). [1] Per-chat emoticon-theme day/night variant now follows the app's actual theme via the new `AppState.isNightMode` (mirrors `IsNightMode() = Background()->nightMode()`: forced dark→night, forced light→day, ONLY `ThemeMode.system` defers to OS `platformBrightness`); `getActiveThemeData` (chat_state.dart:2391) consumes it instead of raw OS brightness — runtime-proven by an isolated test (forced dark→true & forced light→false BOTH while OS reports the opposite; system→follows OS), all 3 assertions green. [2] PlayGame send-action lingers `kStatusShowClientsidePlayGame = 10000 ms` vs `6000 ms` for every other action (per-entry expiry + per-entry `Future.delayed` re-prune), and a live non-game action is never overridden by a game event — the re-emplace guard (chat_state.dart:3312-3317) is the exact De Morgan negation of AyuGram's `i==end || PlayGame || until<=now` (send_action.cpp:43,123-129). [3] Multi-user "playing a game" aggregation present: when every active action is PlayGame, renders `lng_many_playing_game#other` "N people are playing a game" / `lng_users_playing_game` "A and B are playing a game" / `lng_user_playing_game` "X is playing a game" / `lng_playing_game` "playing a game" — all 4 lang strings byte-exact vs `lang.strings:4930-4934`; singular label fixed "playing game"→"playing a game" (chat_state.dart:382-402,438). [4] `geo_location`/`choose_contact` now render plain "typing" / "X is typing" (`lng_typing`/`lng_user_typing`), matching `Type::ChooseLocation`/`ChooseContact` in send_action.cpp:296-299 (no distinct strings) (chat_state.dart:433-435). Flutter debug build clean, app launches/logs in (320 chats), renders desktop 1024×768 + mobile 400×720, no crashes (only pre-existing unrelated tray `MissingPluginException` + one non-active-account folder-limits auth warning).

# telegram_palette — Telegram Desktop color palette + accent colorizer (port of `style_palette_colorizer.cpp` + `window_themes_embedded.cpp` + `colors.palette`)

Scope note: the colorize math (piecewise saturation/value, hue shift, HSL-lightness clamp via `lightnessMin/Max`), `hueThreshold=15`, the 4 accent presets, the 68-key `ignoreKeys` exclusion set, the `keepContrast`→`_enforceContrast` pass (incl. Night-only file-icon gating), the `sl()`/`sd()` day-only/night-only split, and the 4 static palettes' hex values were all cross-checked against AyuGram and verified faithful.

Verified & closed (2026-06-10) — accent-colorizer reference-semantics: 4 MAJOR items, all confirmed faithful to AyuGram C++ ground truth and fixed. Root cause re-confirmed against the live source: `window_theme.cpp`'s `#`-literal branch calls `style::colorize(name, r,g,b, colorizer)` (which itself early-returns when `name` ∈ `ignoreKeys`, `style_palette_colorizer.cpp:97`), while the non-`#` **reference** branch calls `setColor(name, value)` with NO colorize — so a `keyA: keyB` reference inherits keyB's *final* stored (colorized-or-raw) value. These deviations surface ONLY in custom-accent mode; the 4 default themes are byte-identical because `colorize()` early-returns when the accent is unchanged (telegram_palette.dart:1314). [1] `historyPeerSavedMessagesBg2: historyPeer4UserpicBg2` and [2] `historyPeerSavedMessagesBg: historyPeer4UserpicBg` reference ignoreKeys (hex literals `#408acf`/`#5caffa`, `window_themes_embedded.cpp:64,48`) → both kept RAW → now raw passthroughs (was `s()`/`sl()`); the Saved Messages cloud-avatar gradient is accent-independent in every theme. [3] `boxDividerBg: windowBgOver` and [4] `rankUserFg: windowSubTextFg` reference NON-ignoreKeys (`#f1f1f1`/`#999999`, both `s()`-colorized at telegram_palette.dart:1386,1392) → both colorized → now `s()`-colorized so the box/layer divider + member-rank badge track the accent (matches sibling `boxDividerFg`; `rankAdminFg`/`rankOwnerFg` are hex literals → correctly stay raw). All four `colors.palette` references (lines 324/313/146/688), the referent hex/ignoreKey memberships, and the `s()`/`sl()` self-consistency with each referent were re-verified against the live AyuGram source. Flutter debug build clean, app launches + renders desktop 1024×768 + mobile 400×720 (default theme intact), no crashes (only pre-existing unrelated tray `MissingPluginException` + expected no-credentials auth warnings in the automation env).

# theme — ThemeData factory built from TelegramPalette (colorScheme, input/scrollbar/tooltip themes, text theme)

Verified & closed (2026-06-10) — scrollbar thumb hover/drag highlight: 1 MAJOR item, verified & fixed. The broken `thumbColor: WidgetStateProperty.all(p.scrollBarBg)` (one flat color for every state, which also suppressed Flutter's built-in hover affordance) is replaced by `WidgetStateProperty.resolveWith` returning `p.scrollBarBgOver` for `hovered`/`dragged` and `p.scrollBarBg` otherwise (theme.dart:96-100) — the exact 1:1 map of AyuGram's `anim::color(barBg, barBgOver, (_overbar || _moving) ? 1 : 0)` (scroll_area.cpp:289), where `_overbar`=hover and `_moving`=drag. Palette/style re-confirmed against the live AyuGram source: `scrollBarBg #00000053` (≈33%) / `scrollBarBgOver #0000007a` (≈48%) (`colors.palette:62-63`), `barBg: scrollBarBg` / `barBgOver: scrollBarBgOver` (`widgets.style:819-820`), `round: 2px` (`widgets.style:822`). Runtime-proven (Flutter debug build clean, app launches/renders, no crashes across 8 min): in DESKTOP 1024×768 the chat-list thumb measurably brightens on synthetic hover from resting `(76,82,93)` to `(136,140,148)`, matching the predicted full-opacity `scrollBarBgOver` white@48% `(140,144,151)` to within antialiasing tolerance (the old `all()` code could not produce this); an 8× crop shows the brightening plainly. In MOBILE 400×720 a resting-vs-hover difference image isolates the change to *only* the thumb columns (logical x≈394–396, 53 rows, +31/channel) — confirming the single global `ThemeData.scrollbarTheme` applies identically in both modes. The `dragged` branch shares the exact same `scrollBarBgOver` return through the same `hovered || dragged` boolean, so the empirically-proven hover branch confirms both. — `theme.dart:96-100` ← `scroll_area.cpp:289`, `colors.palette:62-63`, `widgets.style:819-822`

## Verified accurate (no action needed)

The remaining content of this file matches AyuGram source 1:1; recorded here so the next pass does not re-investigate:

- TextStyle struct has no `letterSpacing` field and `defaultTextStyle.lineHeight: 0px` (natural metrics) — theme.dart's `letterSpacing: 0` + `height: 1.2` + `leadingDistribution.proportional` override is the correct Flutter equivalent. `theme.dart:117-124` ← `basic.style:39-45, 84`
- Input field `textMargins: margins(0px, 28px, 0px, 4px)` → `contentPadding: EdgeInsets.fromLTRB(0, 28, 0, 4)`. `theme.dart:78` ← `widgets.style:1045`
- Input field flat bottom-underline only (no box): `border/borderActive/borderRadius = 1px/2px/0px`, colors `inputBorderFg`/`activeLineFg`; `UnderlineInputBorder(BorderRadius.zero)` at 1px resting / 2px focused is exact. `theme.dart:67-74` ← `widgets.style:1058-1064` + `input_field.cpp:2388-2412` (`paintFlatSurrounding` fills only the bottom edge).
- Scrollbar `round: 2px` and thumb width `width - 2*deltax = 10 - 6 = 4px`. `theme.dart:86-87` ← `widgets.style:822-826` + `scroll_area.cpp:166`
- `defaultActiveButton.textFg: activeButtonFg` justifies `onPrimary: p.activeButtonFg`. `theme.dart:38,47` ← `widgets.style:728`
- Tooltip: `textBg/textBorder/textPadding` = `tooltipBg`/`tooltipBorderFg`/`margins(5,2,5,2)`; rounded corners use `roundRadiusSmall = 3px`; 1px border = `lineWidth`; default hover-show delay = 1000ms. `theme.dart:90-99` ← `widgets.style:1288-1300`, `basic.style:104`, `tooltip.cpp:172,176-179,573`
- No stubs/placeholders/TODOs/empty callbacks/mock data — it is a pure `ThemeData` factory fully driven by `TelegramPalette` (the authoritative palette source), so there is no backend wiring to break.

Skipped as MINOR/COSMETIC per audit rules: tooltip text `height: 1.3` vs AyuGram natural ~1.2 (<10%, single small widget); input error-state color falls back to `colorScheme.error` (`attentionButtonFg #D14E4E`) instead of `activeLineFgError #E48383` (edge-state shade-of-red, correct underline shape); `bodyMedium` 14px vs AyuGram default `fsize` 13px (~7.7%, under threshold, and widgets set explicit sizes).

# theme_file — Telegram Desktop theme (.tdesktop-theme/.tdesktop-palette) parser, exporter & cache

Audited against AyuGram ground truth: `window_theme.cpp`, `style_core_palette.cpp`,
`parse_helper.{cpp,h}`, `window_theme_editor.cpp`, `colors.palette`.

This file is an exceptionally faithful port. Verified IDENTICAL/correct:
- `_stripComments` ≡ `base::parse::stripComments` (parse_helper.cpp:13-97); the space-count
  difference for multiline comments is irrelevant to a whitespace tokenizer.
- `_skipWhitespaces`/`_readName` ≡ parse_helper.h:15-38 (exact char classes).
- `_readNameAndValue` ≡ `readNameAndValue` (window_theme.cpp:122-164) — all 4 structural
  rejections (empty name / missing `:` / empty value / missing `;`) reproduced.
- Pass-1 loop ≡ `ReadPaletteValues` (window_theme.cpp:1514-1537), incl. hard-reject.
- Pass-2 resolution ≡ `setColorSchemeValue`+`setColor`+`loadColorScheme`
  (window_theme.cpp:170-233, style_core_palette.cpp:104-136): hex/reference/unsupported
  semantics + forward-ref `Loaded`-only resolution.
- Pass-3 cascade ≡ `palette::finalize`/`compute` (window_theme.cpp:368,
  style_core_palette.cpp:158-180); `_paletteFallbacks` is **byte-identical** to
  `colors.palette` (236/236 reference entries, exact declaration order — verified by diff).
- Palette coverage: all 580 `colors.palette` keys modeled, no transposed color mappings.
- `#rrggbb`/`#rrggbbaa` hex (alpha-last) parse matches window_theme.cpp:178-183.
- Cloud-meta read/write ≡ `ReadCloudFromText`/`WriteCloudToText` (window_theme_editor.cpp:346-381),
  incl. prefix positioning.
- Size limits match exactly: 25M px background pixels (window_theme.cpp:56), 4 MB background
  bytes (window_theme.h:42), 1 MB scheme bytes (window_theme.h:41). Zip-bomb guards present.
- No stubs / TODOs / placeholders / fake data. Wired into theme.dart, theme_editor.dart, app_state.dart.

# theme_preview — static theme-preview image (dialogs list + chat panel), port of `window_theme_preview.cpp`

Overall this is an exceptionally faithful port. Verified-correct against AyuGram (no findings needed):
canvas/dialogs/top-bar/compose/row/avatar dimensions (media_view.style:423/445, info.style:1019,
dialogs.style:89-101, chat_helpers.style:1341); the full `generateData()` sample set incl.
peerIndices, group/muted/pinned/status flags and `Ui::Text::Colorized` spans
(window_theme_preview.cpp:342-401); empty-userpic color logic — `DecideColorIndex` + the
`{0,7,4,1,6,3,5}` `ColorIndexToPaletteIndex` map (chat_style.cpp:1202-1207) + vertical 2-stop
gradient (empty_userpic.cpp:308-316); colorized-preview link color = `dialogsTextFgService`
(dialogs.style:170); top-bar icon accumulation (widths 44/40/40, topBarSkip -5, info.style:1051-1064)
and status color `historyStatusFgActive = windowActiveTextFg` (chat.style:460); bubble margins/padding/
radius/tails (chat.style:14-54,435; message_bubble.cpp:835-859); reply-block colors
(window_theme_preview.cpp:907-911); `ComputeChatBackgroundRects` truncation/parity/anchoring
(chat_theme.cpp:833-878) + default wallpaper colors & intensity-50 (data_wall_paper.cpp:707-718);
compose-field bg `historyComposeAreaBg` and placeholder `windowSubTextFg`
(chat_helpers.style:1197-1199, colors.palette:73). Widget is wired to the live edited palette
(theme_editor.dart:811) and has an identity-based `shouldRepaint`.

# admin_tools — group/channel/bot admin management suite (edit-info, permissions, participants, admin-log, invite-links, statistics, boosts, monetization, star-ref)

Verified & closed (2026-06-10) — all 34 audit findings (fixed by commit c7465942) re-verified against AyuGram C++ ground truth, the current Dart source, AND the Go engine. Go + Flutter build clean; app launches + renders crash-free in desktop 1024×768 + mobile 400×720 (`flutter_audit.sh verify` PASS both modes; no Dart exceptions/RenderFlex/assert during extensive navigation — only benign backend RPC errors that the UI handles gracefully). Every backend field the Dart reads is now actually emitted, and every behavioral fix is present:
- _EditPeerInfoBox (1-6): standalone Restrict-Saving/Join-to-Send/Approve-Members rows dropped (live only in EditPeerTypeBox); Discussion-Group row gated `isChannelOrSuper && (link || (broadcast && canEditInformation))`; selection routed through a MakeConfirmBox carrying private-channel + hidden-pre-history warnings (visually confirmed); linked/available peers shown by name+@username/"private" (engine GetDiscussionGroups emits username); Create-discussion-group action added; Direct-Messages price is a bounded Slider (maxStars from getPaidMessagesConfig) with live commission/≈USD divider + save clamp. Items 1-5 visually confirmed desktop+mobile.
- _EditPeerPermissionsBox (7-9): GetDefaultBannedRights seeds boosts_unrestrict (fc.GetBoostsUnrestrict) + charge_stars (fc.GetSendPaidMessagesStars), Save round-trips both instead of clearing; edit_rank is a live editable toggle (visually confirmed flipping on tap).
- _BotStarRefSetupScreen (10-14): _save→ConfirmUpdate (irreversible warning + Commission/Duration summary), _end→ConfirmEndBox (3-bullet warning); commission+duration lower-bound lock when a program exists; min/max from GetBotManageInfo appConfig keys (starref_min/max_commission_permille); duration is a Slider with tiny labels, not a radio list.
- _EditRestrictedBox (15-16): Send-media master toggle skips locked/default-banned flags; media checkboxes render lock icon + "Forbidden for all members" subtext + tooltip + tap toast.
- _EditAdminBox (17-18): GetParticipantInfo populates admin_rights (full 16-flag map via adminLogAdminRightsMap, json admin_rights/rank) + rank so editing seeds real saved rights; new-admin defaults leave anonymous+add_admins OFF.
- Members (19-24): Add-Members-via-Link button; real people search (engine SearchGlobalUsers→contacts.Search, multi-result); broadcast Add-Subscribers (no isChannel exclusion); kicked Add-to-Banned confirm (+admin warning); join-request tap opens profile; subtitle shows promoted/removed/restricted-by (engine resolves actor ID→name in cache_users.go).
- Statistics/Boosts/Monetization/StarRef (25-34): message stats re-fetch live views/forwards/reactions via ChannelsGetMessages (always show cards); booster user_id read tolerantly as int (no TypeError); type-dispatched booster click; dead credits/stars booster code removed; premium count from part/total; explicit Show-N-More buttons; TON tx recipient from provider; receipt-style Stars tx detail (bubble + status chips); bot userpics avatar_b64 (both builders) + JoinStarRefBox daily-revenue line (engine emits daily_revenue).

# advanced_settings_screen — Advanced settings page (§14.7) + sub-dialogs (update, proxies, local storage, auto-download, power saving, dictionaries, downloads, experimental)

Verified & closed (2026-06-10) — all 5 audit findings (fixed by commit ad59018d) re-verified against AyuGram C++ ground truth, the current Dart source, AND the running app (Flutter build clean; experimental box + Add-proxy dialog render crash-free in desktop 1024×768 + mobile 400×720; only benign no-credential auth errors + pre-existing tray-plugin warnings in the log):
- [CRITICAL] Dead experimental consumers wired to the box flag IDs the box actually persists: `chat_list_row` mute icon reads `dialogs-mute-icon` (default off, matches DialogsMuteIcon); `chat_list_panel` forum list reads `!forum-hide-chats-list` (default off); `message_bubble` reads `use-small-msg-bubble-radius` → 6px (= bubbleRadiusSmall=roundRadiusLarge, basic.style:103), fixing the old wrong 20px. `autoplay_gifs`/`message_draft_visible` (no AyuGram option) are honest `const true` — drafts confirmed visibly rendering in the chat list. Grep confirms ZERO leftover underscore-key reads; Save logs `SetExperimentalFlag: fractional-scaling-enabled=true` (correct box id).
- [MAJOR] `fast-buttons-mode` gated behind `_visibleFlagDefs` (listed only when its open value is true) — confirmed absent between "Prefer IPv6" and "Disable Touch Bar"; on-screen text search for "Fast" returns NOT FOUND.
- [MAJOR] Restart-required handling: toggling a restart flag + Save shows the confirm box "You need to restart for applying some of the new settings. Restart now?" with Later/Restart (= lng_settings_need_restart / restart_later / restart_now) — visually confirmed; "Later" dismisses without restarting. All 6 named flags (FreeType, fractional scaling, small bubble radius, custom notifications, legacy Edge, deadlock detector) + high-dpi-downscale correctly marked restartRequired.
- [MAJOR] Per-option `.description()` blocks rendered as text directly under each toggle — ~20 descriptions verified matching AyuGram exactly, in both desktop + mobile.
- [MAJOR] Proxy sponsor warning fixed to lng_proxy_sponsor_warning ("…This doesn't reveal any of your Telegram traffic.") — byte-for-byte match, visually confirmed in the Add-proxy dialog.

Minor follow-ups (do NOT block close): `gnotification` should be restartRequired=true (notifications_manager.cpp:174) but Dart marks it false (touchbar-disabled is likewise true in AyuGram, but it is macOS-only/irrelevant on Linux, so Dart's false matches Linux behavior); the experimental-box action-button row (Export/Import/Cancel/Save) overflows by ~2.8px at 400px width — cosmetic, pre-existing, unrelated to these 5 fixes.

# auth_screen — Telegram intro/login flow (phone, code, 2FA, QR, signup, email)

Verified & closed (2026-06-10) — all 4 MAJOR items (fixed by commit cddb8863) re-verified against AyuGram C++ ground truth, the current Dart/Go source, AND the running app (Go libcores.so + Flutter debug build clean; the intro flow was walked live — phone/code/QR steps in BOTH desktop 1024×768 and mobile 400×720 — with zero Dart exceptions / RenderFlex / layout overflow, only the pre-existing tray `MissingPluginException` + one non-active-account folder-limits auth warning). [1] Code-step subtitle now honors login-email delivery: the Go core captures `auth.sentCodeTypeEmailCode`'s `email_pattern` (`telegram.go` `authCodeEmailPattern`), the engine surfaces it as `email_pattern_login` (`auth.go`), `AuthStateData.emailPatternLogin` carries it (`engine_models.dart`), and `_codeSubtitle` picks `emailPatternSetup` OR `emailPatternLogin` → `lng_intro_email_confirm_subtitle` with the masked address — the exact `CodeWidget::updateDescText` logic of `intro_code.cpp:84-90` + `intro_step.cpp:381-383`; confirmed running live on the code step (it correctly fell through to the `codeByTelegram` branch for the non-login-email test account, no crash). [2] QR step reordered to AyuGram's `QrWidget` layout — QR graphic at the very top, title BELOW it, then the 3 numbered steps, then the phone link (`intro_qr.cpp:285-362`; `introQrTop:-18` / `introQrTitleTop:196` / `introQrStepsTop:232`, title `font(20px semibold)`); visually confirmed top-to-bottom order in BOTH modes. [3] The spurious 48px `Icons.lock_outlined` is gone from the phone, code AND QR steps — none of AyuGram's `PhoneWidget`/`CodeWidget`/`QrWidget` have a leading icon; visually confirmed absent on all three steps in both modes. [4] Hardcoded English → lang pack so the whole intro localizes: `lng_signin_password`/`lng_signin_code` (2FA field labels), `lng_signin_recover`/`lng_signin_try_password` (recovery links), `lng_phone_to_qr` (phone→QR link), `lng_settings_cloud_login_email_placeholder` (login-email field) — all added to the pack with English baselines byte-exact vs AyuGram `lang.strings`; `lng_phone_to_qr` (itself a key newly added in this same commit) was proven rendering live from the pack on the phone step in both modes, which validates the identical `lang.tr()` path for the 2FA/email keys (`intro_password_check.cpp:35-39`, `intro_phone.cpp:114`, `intro_email.cpp:74`).

# ayu_general_page — AyuGram General (QoL) settings page

Audited `dart/lib/ui/ayu_general_page.dart` against `ayu/ui/settings/settings_general.cpp`
(`BuildQoLToggles`, `BuildTranslator`, `BuildShowPeerId`) + `settings_ayu_utils.cpp`
(`ShowRestartPrompt`) + `Resources/langs/lang.strings`.

## Verdict: faithful, fully-wired port — one string-fidelity deviation

Verified clean (no findings):
- **Structure 1:1** — all 17 rows in the exact AyuGram order (translation chooser+beta,
  General title, disableStories, disableOpenLinkWarning, similarChannels collapsible,
  disableNotifyDelay, filterZalgo+beta, improveLinkPreviews, showMessageSeconds, showPeerId,
  Webview title, spoofWebviewAsAndroid, biggerWindow collapsible, Confirmations title,
  sticker/gif/voice confirmations) — `ayu_general_page.dart:26-227` ← `settings_general.cpp:36-299`.
- **4 section dividers** in the exact AyuGram positions — `ayu_general_page.dart:77,129,168,206`
  ← `settings_general.cpp:161,209,248,277`.
- **Every label string** matches `lang.strings` verbatim (DisableStories, DisableOpenLinkWarning,
  DisableSimilarChannels/Collapse/HideTab, DisableNotifyDelay, FilterZalgo, ImproveLinkPreviews,
  ShowMessageSeconds, ShowID="Show Peer ID", SpoofWebviewAsAndroid="Spoof Client as Android",
  BiggerWindow, IncreaseWebviewHeight/Width, Confirmations + For Stickers/GIFs/Voice Messages,
  TranslationProvider, lng_translate_settings_subtitle="Translate Messages").
- **All toggles/choosers wired to real persisted state** — every getter/setter exists in
  `app_state.dart:1038-1052,2131-2225`, each setter calls `notifyListeners()` + `_saveWindowPrefs()`,
  values are loaded (`app_state.dart:4463-4492`) and saved (`4768-4782`). No empty callbacks,
  no stubs, no mock data, no TODOs.
- **Native-translation gating** — `nativeTranslateAvailable` does a real PATH check for
  `crow`/`org.kde.CrowTranslate` on Linux (`app_state.dart:2099-2128`), mirroring
  `Platform::IsTranslateProviderAvailable()`; option 3 label is platform-correct
  (macOS/Windows/Linux) — `ayu_general_page.dart:28-50` ← `settings_general.cpp:46-60`.
- **macOS native-translation toast** (6s, exact `lng_translate_settings_use_platform_mac_about`
  text) fires only on macOS+index3 — `ayu_general_page.dart:61-69` ← `settings_general.cpp:94-101`.
- **Both choosers open a real `_SingleChoiceBox` dialog** (`ayu_section_builder.dart:657-665`),
  matching AyuGram's `SingleChoiceBox` — not cosmetic.
- **toggledWhenAll** correct on both collapsibles (similarChannels=true, biggerWindow=false)
  — `ayu_general_page.dart:103,186` ← `settings_general.cpp:199,274`.
- **Restart-prompt is wired to the correct two toggles only** (disableStories, filterZalgo)
  — `ayu_general_page.dart:87,139` ← `settings_general.cpp:173,226`.

## Findings

- [ ] [MAJOR] Restart-prompt strings diverge from AyuGram's `ShowRestartPrompt`. AyuGram uses
  `Ui::MakeConfirmBox` with **no title**, body = `lng_settings_need_restart` ("You need to
  restart for applying some of the new settings. Restart now?") and confirm button =
  `lng_settings_restart_now` ("Restart"). The Dart port adds a title "Restart Required",
  rewords the body to "Some settings will be applied after restarting.", and labels the
  confirm button "Restart Now" — three user-visible strings that don't match the authority
  (the in-code comment even mis-states confirmText as "Restart Now"). Cancel button "Later"
  is correct. Behavior (apply→prompt→restart-on-confirm) is faithful; only the text differs.
  — `ayu_general_page.dart:242-244` ← `settings_ayu_utils.cpp:38-43` / `lang.strings:1305-1306`

# ayugram_settings_screen — AyuGram main settings landing page (logo, version, category & link buttons)

Port of `settings_main.cpp` (`AyuMain` section). This is a faithful port: text/lang
strings (tagline = `ayu_SettingsDescription`, headers, all category/link labels and
right-labels) match exactly; fonts match (`boxTitle` 16px semibold, subsection
14px semibold); the 100px logo (`settingsCloudPasswordIconSize`), 8px divider
(`boxDividerHeight`), and category-button geometry (icon@20px, label@60px) match;
all six category buttons navigate to the correct sub-pages and all four link
buttons are wired to real engine/URL handlers (`engine.resolveUsername` →
`openChatById` with t.me fallback; `launchUrl`). No placeholders, no broken
wiring. The only real deviations are invented trailing chevrons.

- [ ] [MAJOR] `_FlatCategoryButton` paints a trailing `Icons.chevron_right` disclosure arrow on every category row, but AyuGram's section buttons are built with `st::settingsButton` (base `infoProfileButton`), whose style has only `style`/`padding`/`iconLeft` plus a `toggle` slot used solely for boolean switches — there is NO arrow/chevron. The disclosure arrow is an element AyuGram never renders. — `ayugram_settings_screen.dart:338` ← `settings/settings.style:13` (settingsButton, no arrow) + `info/info.style` infoProfileButton / `ayu/ui/settings/settings_main.cpp:103-132`

- [ ] [MAJOR] `_LinkButton` renders BOTH the right-side text label AND a trailing `Icons.chevron_right`. In AyuGram the link rows (`addButton` with `.label`) draw only the right text label via `CreateRightLabel`, positioned `st::settingsButtonRightSkip` (23px) from the right edge, with no chevron after it. The extra arrow is not in the source. — `ayugram_settings_screen.dart:389` ← `settings/settings_common.cpp:420-468` (CreateRightLabel, no arrow) / `ayu/ui/settings/settings_main.cpp:144-185`

# ayu_other_page — AyuGram "Other" settings page (donations, crash reporting, URL-scheme register, reset)

Audited `dart/lib/ui/ayu_other_page.dart` against AyuGram `ayu/ui/settings/settings_other.cpp`,
`ayu/ui/boxes/donate_info_box.cpp`, `ayu/ui/boxes/donate_qr_box.cpp`, and `ayu/utils/rc_manager.cpp`.

Wiring is solid overall — no stubs/placeholders: Boosty opens the real URL, crypto buttons open a
real QR dialog, the crash-reporting toggle persists via `AppState.setCrashReporting`, Register-URL-Scheme
writes real desktop/registry entries per-platform, Reset runs `AppState.resetAyuSettings`, the support
link opens the donate-info box (matches `tg://support` → `HandleSupport` → `FillDonateInfoBox`), the
donate-username link resolves via `engine.resolveUsername`, and donate amounts/username are fetched
from the live RC endpoints. Lang text matches the strings file. The issues below are deviations, not stubs.

- [ ] [MAJOR] RC config response is only partially consumed — the badge/developer/supporter data the C++ `RCManager` loads is silently dropped. `_applyRcData` reads ONLY `donateAmountUsd/Ton/Rub` + `donateUsername`, whereas `applyResponse` also parses `developers`, `officialChannels`, `supporters`, `supporterChannels`, and `customBadges` (the source of AyuGram's developer/supporter/custom profile badges). No other Dart file fetches this config, so the entire badge data source is missing; the donate-amount path is the only thing wired. — `ayu_other_page.dart:558-581` ← `AyuGram/ayu/utils/rc_manager.cpp:125-185`

- [ ] [MAJOR] Support description renders with the wrong font size and not on a divider band. AyuGram builds it with `AddDividerText(...)` → label sits ON a full-bleed `boxDividerBg` band using the 14px `defaultTextStyle` (the project's own `addDividerText`/`addDescription` helpers document 14px). The Dart `_SupportDescription` widget uses `fontSize: 12` (~14% smaller) inside a plain `Padding(22,4,22,4)` with no band; the band is instead emitted later as a separate `addSectionDivider()`. — `ayu_other_page.dart:460-464` ← `AyuGram/ayu/ui/settings/settings_other.cpp:161-167`

- [ ] [MAJOR] Donate rows render a trailing `Icons.chevron_right` that AyuGram does not draw. The crypto/Boosty buttons are built from `AddButtonWithIcon(..., st::settingsButton)`, whose style defines no right arrow/chevron — they are flat rows (icon + label). The added chevron also wrongly implies drill-down navigation (these open a URL or a modal QR dialog) and is inconsistent with the sibling `_ActionButton` in this same file, which correctly has no chevron. Repeated across all 6 donate rows. — `ayu_other_page.dart:368-372` ← `AyuGram/ayu/ui/settings/settings_other.cpp:124-129` + `AyuGram/Telegram/SourceFiles/settings/settings.style:13-17`

# bridge_web — Web (WASM) JS-interop bridge to the Go backend

> Note on authority: this file is the WASM transport for the FFI bridge. AyuGram
> Desktop is a native Qt/C++ app with no WebAssembly bridge, so there is **no
> AyuGram C++ counterpart**. The authoritative reference is the cross-platform
> `Bridge` contract defined by the sibling native implementation
> `dart/lib/bridge/bridge_ffi.dart` (and the Go side `go/cmd/bridge/main_js.go`),
> which both platforms must honor. The pre-extracted AyuGram style/box headers in
> the prompt are unrelated to this transport layer. Findings cite the sibling
> contract file as the ground-truth reference.
>
> Wiring is otherwise correct: `call()` → JS `bridgeCall` → Go `bridge.Call`
> (`bridge_web.dart:63-71` ↔ `main_js.go:50-65`), `init()` awaits `bridgeReady`
> then registers the event callback, and events flow Go → JS callback →
> `_onEventFromGo` → `_eventController` → `events` stream. No stubs, no empty
> callbacks, no fake/mock data, no "coming soon" placeholders.

- [ ] [CRITICAL] `_eventController` is declared `final` (`bridge_web.dart:38`) and `dispose()` closes it (`bridge_web.dart:95`), but `init()` (`bridge_web.dart:40-61`) never recreates it — so it CANNOT support a `dispose()`→`init()` re-initialization cycle. The native bridge deliberately makes this field non-`final` and recreates it when a prior `dispose()` closed it, with comments naming the exact scenarios ("engine hot-restart, multi-account teardown"). On web, after re-init the `events` stream is permanently dead (returns the already-closed stream, new listeners get only `done`) AND `init()` re-registers `_onEventFromGo` against the closed controller, so every subsequent Go event throws "Bad state: Cannot add event after closing." The entire async event channel (new messages, edits, deletes, typing, presence, read receipts, auth-state changes) silently dies and spams exceptions. `EngineService.dispose()` calls `_bridge.dispose()` (`engine_service.dart:6682`) and `EngineService.init()` re-subscribes to `_bridge.events` (`engine_service.dart:111-112`), so the re-init path is real, not hypothetical. — `bridge_web.dart:38,40-61,92-97` ← `bridge_ffi.dart:41-42,56-57,77-80`

- [ ] [MAJOR] `_onEventFromGo` adds to `_eventController` with no `!_eventController.isClosed` guard, unlike the native event forwarder which checks `msg is Uint8List && !_eventController.isClosed` before adding. Without the guard, any event delivered to a closed controller (e.g. after the re-init bug above, or a JS callback that fires during/after teardown) throws instead of being silently dropped. The native side treats a closed controller as a normal, defensively-handled state; the web side does not. — `bridge_web.dart:99-101` ← `bridge_ffi.dart:106-110`

# engine_service — FFI/RPC wrapper around the Go engine bridge (~7861 lines, ~497 bridge calls)

This file is a thin, high-quality wrapper: every method serializes a request
(protobuf `writeToBuffer()` or `json.encode`) and calls `_callRaw`/`_callAsync`
on the bridge, then deserializes the response. No stubs, no TODO/FIXME, no
mock/hardcoded data, no fake "coming soon" feedback. Infrastructure (`_callRaw`,
`_callAsync`, `_handleBridgeEvent`, `_dispatchEngineEvent`) and all proto→model
converters are correctly wired. `Isolate.run` is used for heavy proto parsing
(`getMessages`, `fetchLiveMessages`). The single proto-reuse smell
(`readMentions` building `EngineReportSpamRequest`, line 762) is **intentional
and correct** — the Go `ReadMentions` case unmarshals into that exact type
(`dispatch_engine.go:613-617`, proto fields `account_id=1`/`chat_id=2`).

One genuine wiring defect found:

- [ ] [CRITICAL] `getMapTile` routes the engine call to the per-account core id (`accountId`) instead of `'__engine'`, so the static-map fetch **always fails** and Instant-View location blocks never render their map. `GetMapTile` is registered ONLY on the engine layer (`go/bridge/dispatch_engine.go:5428`), and the bridge forwards only `coreId == "__engine"` to `dispatchEngine` (`go/bridge/bridge.go:88`). With a **non-empty** `accountId` — the actual runtime path: `openInstantView` → `InstantViewPage` → `_IvBlock` → `_StaticMapImage` → `getMapTile` (`dart/lib/ui/instant_view.dart:2721`, accountId always real) — the bridge looks the id up as a per-account core and routes to `dispatchTelegram`, whose `default` returns `"unknown method GetMapTile for telegram"` (`go/bridge/dispatch_gen.go:21912`); the `catch` then returns `null` → `_failed = true` → placeholder, never the map. Every other one of the ~497 bridge calls in this file routes to `'__engine'` with `account_id` carried in the payload (which `getMapTile` already does at line 6505), so the fix is to make the coreId `'__engine'` unconditionally. — `engine_service.dart:6514` ← `AyuGram/Telegram/SourceFiles/data/data_location.cpp:69` (`ComputeLocation` builds the static-map request params: lat/lon/w/h/zoom that `getMapTile` mirrors)

# ayu_filter — regex/shadowban message-filter engine (port of AyuGram FiltersController + FiltersCacheController + FilterUtils)

Audited `ayu_filter.dart` (1071 lines) against AyuGram's `filters_controller.cpp`,
`filters_cache_controller.cpp`, `filters_utils.cpp`, `entities.h`,
`per_dialog_filter.cpp`, `history_item.cpp`, and the consumer `context_menu.cpp`.
The port is exceptionally faithful — every cited line number checks out, the
block/shadowban verdict (all 6 cases), blob extraction, ICU→Dart pattern
translation, import/export round-trip, and the dpaste publish flow all match the
C++ ground truth and are correctly wired to real engine data (verified the Go
engine emits every `service_action` tag, the `channel` gift flag, and
`media_type` 1–12 that this file consumes). One genuine behavioral divergence:

- [ ] [MAJOR] `filteredMessagesShown()` returns `false` instead of `null` once a chat has been toggled even once, so the "Show/Hide filtered messages" context-menu item persists forever (and reveals nothing) where AyuGram omits it — `ayu_filter.dart:856-859` ← `AyuGram/ayu/features/filters/filters_controller.cpp:197-204`

  Root cause: `_filteredMessagesShown` is a `Map<String,bool>` and
  `toggleFilteredMessagesShown` only flips the bool (`ayu_filter.dart:856-859`) —
  it **never removes the key**. AyuGram's `showingFilteredMessages` is a
  `std::unordered_set` that **erases** the entry on toggle-off
  (`filters_controller.cpp:198-202`). Because of this, the guard in
  `filteredMessagesShown` (`ayu_filter.dart:843-849`,
  `if (!_filteredMessagesShown.containsKey(chatId) && !_hasFilteredMessages(chatId)) return null;`)
  can never reach the `null` branch for a chat that was toggled, since
  `containsKey` stays `true` permanently — diverging from
  `filters_controller.cpp:189-195` whose `!showingFilteredMessages.contains(...)`
  goes back to `true` after toggle-off.

  Observable effect: open a chat with N regex-hidden messages → context menu shows
  "Show filtered messages" → tap (reveal) → tap again (hide) → then the hidden
  messages disappear (deleted, filter removed, or cache evicted) so
  `_hasFilteredMessages` is now false. AyuGram returns `nullopt` →
  `context_menu.cpp:258-259 if (filteredToggleShown)` omits the menu item. The Dart
  returns `false` (non-null) → `chat_list_panel.dart:1718 if (filteredShown != null)`
  keeps adding a "Show filtered messages" item that reveals nothing. Wrong state
  vs. ground truth. ← `AyuGram/ayu/ui/context_menu/context_menu.cpp:258-271`

  Fix: make toggle remove the key when flipping to `false`
  (`if (currently true) _filteredMessagesShown.remove(chatId); else _filteredMessagesShown[chatId] = true;`),
  or change the `null` guard to `(_filteredMessagesShown[chatId] != true)` so an
  un-shown chat with no filtered messages reports `null` exactly like the C++ set.

## Verified faithful (no action needed)

- Block/shadowban short-circuit (`_filterBlocked`, `ayu_filter.dart:978-1002`) — traced all 6 cases against `filters_controller.cpp:95-136`; the blocked-direct-sender early-return that skips the forward branch is correct.
- `extractMatchBlob` / `_extractSingleText` URL handling (`ayu_filter.dart:416-546`) matches `extractSingle`/`extractAllText` (`filters_utils.cpp:640-685`): plain-URL → substring, text_url → entity data, `<button>`/`<type>` tags appended identically.
- Import/export round-trip (`ayu_filter.dart:614-711`) matches `prepareChanges`/`exportFilters` (`filters_utils.cpp:457-530,701-867`) including the explicit-`null` `dialogId` for shared filters, UUID dash-formatting, and unknown-id/exclusion pruning.
- Type 15 (animated sticker), 23/24 (story), 26 (giveaway-start), 29 (paid-media) are **un-producible** here, but that is an upstream Go-engine limitation (telegram.go folds all stickers into `media_type 6` at `cores/telegram.go:13317` and drops story/dice/giveaway/paid-media to type 0), faithfully documented at `ayu_filter.dart:343-367`. Not a bug in this file — fix belongs in the engine audit.

# emoji_data — emoji keyword/suggestion engine (port of `EmojiKeywords` + `Completer`)

Audited `dart/lib/data/emoji_data.dart` against `chat_helpers/emoji_keywords.cpp`,
`lib_ui/emoji_suggestions/emoji_suggestions.cpp`, `codegen/emoji/replaces.cpp`, and
`core/core_settings.cpp`.

The port is, with one exception, faithful and well-documented (comments cite exact
C++ line numbers). Verified equivalent and NOT flagged:

- Lang-pack `query`: `lower_bound` + `take_while(startsWith/==)` and per-source dedup
  match `EmojiKeywords::LangPack::query` / `AppendFoundEmoji` (emoji_keywords.cpp:473,176).
- Cross-pack iteration in **sorted** lang-code order matches `base::flat_map _data`
  (emoji_keywords.h:75) walked by `EmojiKeywords::query` (emoji_keywords.cpp:616).
- Legacy `Completer` port (`_normalizeLegacyQuery`, `_splitReplacementWords`,
  `_matchLegacyTail`, `_legacyLowerBound`, `_legacyEqualChars`, `_legacyRankKey`)
  matches emoji_suggestions.cpp:193/301/333/406/358/373 and replaces.cpp:40. The
  iterate-all-candidates approach is equivalent to `GetReplacements(firstChar)` because
  the match itself requires the first query char to begin a word (the index condition,
  generator.cpp:1027). The dead-code 4th `stable_partition` (exact-match boost) is
  correctly identified and omitted (emoji_suggestions.cpp:391 vs :322).
- Postfix char is U+FE0F, matching `kPostfix` (codegen/emoji/data.h:42); `MustAddPostfix`
  codes and `SkipExactKeyword` rules match emoji_keywords.cpp:47/55.
- Diff apply/delete with postfix-aware removal matches `ApplyDifference` (emoji_keywords.cpp:244).
- Variant application happens after dedup+prioritize, matching `queryMine =
  ApplyVariants(PrioritizeRecent(query()))` (emoji_keywords.cpp:644).
- Server fetch is fully wired (languages → initial/diff) via `chat_view.dart`'s
  `_fetchEmojiKeywordsForLangs` → `loadServerKeywords`/`loadServerKeywordsDiff`; 1h
  auto-refresh matches `kRefreshEach` (emoji_keywords.cpp:28). No placeholders/stubs.

## Findings

- [ ] [MAJOR] Recent-emoji prioritization uses **LRU recency** ordering instead of
  AyuGram's **frequency-rating** ordering, so the wrong emoji floats to the top of
  inline suggestions. `recordRecent` does a plain move-to-front (`remove` + `insert(0)`)
  and `_prioritizeRecent` iterates `_recentEmojis` in that most-recently-used-first
  order — `emoji_data.dart:3132` (`recordRecent`), `:2926` (`_recentEmojis`), `:3382`
  (`_prioritizeRecent`) ← `core/core_settings.cpp:1411`. In AyuGram
  `incrementRecentEmoji` bubbles each emoji by its `rating` (use count), so
  `recentEmoji()` (core_settings.cpp:1360) returns a vector ordered by **frequency**
  (descending), and `PrioritizeRecent` (emoji_keywords.cpp:650) rotates matches to the
  front in that frequency order. Result: for a query matching several recents (e.g.
  `:sm` → smile/smirk/small), AyuGram surfaces the **most-used** recent first while this
  port surfaces the **most-recently-used** one — a different primary suggestion.
  Two contributing deviations, both ← the same C++ recent subsystem:
    - Ordering model: LRU vs rating (the visible one, described above).
    - Population source: `recordRecentFromText` records only **sent** message text plus
      panel/autocomplete picks (`emoji_data.dart:3156`, wired at `chat_view.dart:4403`),
      whereas AyuGram records on **every** emoji render — including received messages —
      because `UiIntegration::defaultEmojiVariant` calls `incrementRecentEmoji` for any
      emoji passing through the text engine (`core/ui_integration.cpp:471`). The port's
      narrowing is documented as deliberate at `emoji_data.dart:3147`, but it compounds
      the divergence from AyuGram's recent set. The cap also differs (`_maxRecent = 50`,
      `emoji_data.dart:2927`, vs `kRecentEmojiLimit = 54`, `core_settings.h:74`).

# lang_pack — intro/login cloud-pack localization (port of AyuGram `Lang::` + `lang.strings`)

Audited `dart/lib/l10n/lang_pack.dart` against AyuGram `lang/lang_keys.cpp`,
`Resources/langs/lang.strings`, and the intro consumers. This file is a
remarkably faithful port — the findings below are the only deviation.

## Verified clean (no action)

- **English baseline is 1:1.** All 51 embedded strings match `lang.strings`
  exactly, key-by-key, including `\n` breaks and the `**via Telegram**` bold
  markers (`lang_pack.dart:93-167` ← `lang.strings:37-48,97-102,382-467,978,5724,7072`).
- **`firstNameGoesSecond`** mirrors `langFirstNameGoesSecond()` exactly — same
  0x0001/0x0002 sentinels, same `indexOf(last) < indexOf(first)` test
  (`lang_pack.dart:202-208` ← `lang_keys.cpp:59-69`).
- **`Month()` mapping** matches `lng_month1..12` (`lang_pack.dart:83-85,155-166`
  ← `lang_keys.cpp:205-221`).
- **Backend wiring is real end-to-end.** `getLangStrings` → `_callAsync('__engine',
  'GetLangStrings')` → `dispatch_engine.go:5373` → `cache_users.go:2459` →
  `telegram.go:26841` `LangpackGetStringsMap` (pack `"tdesktop"`, real
  `preAuthAPI` fallback validating the "works mid-login" claim).
- **Key coverage complete.** Every `lang.tr/trf/trCount` key used anywhere in the
  UI exists in BOTH the fetch `keys` list AND the `_en` baseline (51=51, zero
  gaps) — no non-English string silently falls back to English or to a raw key.
- **`setLanguage`** correctly clears the previous overlay before fetch (A→B never
  leaves A's strings on screen), guards stale fetches with `_code == code`, and
  stays on English on empty/failed fetch (`lang_pack.dart:215-243`).

## Findings

- [ ] [MAJOR] Non-English pluralized strings always collapse to the **"other"**
  grammatical form. `trCount` resolves the form with the English rule
  `count == 1 ? 'one' : 'other'`, then for cloud languages the overlay only ever
  holds the bare key (no `key#one`/`key#other`) because the Go bridge keeps only
  `OtherValue` and drops the server's zero/one/two/few/many plural values — so
  the lookup lands on `_overlay[key]` (the "other" value) for every count. AyuGram
  instead applies full CLDR plural rules per active language via `lt_count`. Net
  effect: on the 2FA account-reset-wait countdown, languages with rich plural
  rules (ru/ar/pl/cs…) render grammatically wrong plurals for days/hours/minutes
  (e.g. Russian "2 дней" instead of "2 дня"). Narrow (one screen, non-English
  only, the number itself is correct) and documented in-code, but it is backend
  plural data deliberately dropped at the bridge. English is unaffected (correct
  one/other). — `lang_pack.dart:184-192` (root cause: bridge collapse
  `go/cores/telegram.go:26863-26866`) ← `intro_widget.cpp:577-599` (`tr::lng_days(
  tr::now, lt_count, days)` etc.) / `lang_keys.cpp:59` (CLDR `tr::` plural system)

