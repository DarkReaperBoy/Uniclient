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

# ayu_forward — intelligent forward orchestration (no-forwards bypass / resend-as-own chunking)

Scope: `dart/lib/state/ayu_forward.dart` vs `AyuGram/.../ayu/features/forward/ayu_forward.cpp`
(+ `ayu_sync.cpp`, `apiwrap.cpp` callers). This is a logic/orchestration file — no widgets,
no empty callbacks, no TODO/mock data. The port is faithful: the per-message chunking loop
(`buildChunks` ← `intelligentForward` chunk split, cpp:261-285), the full-resend short-circuit
(`buildChunks` ← `apiwrap.cpp:3487-3492` `isFullAyuForwardNeeded(front)`), the
native-vs-resend dispatch, `isMessageRestricted` ← `isAyuForwardNeeded(item)` (cpp:226-231),
`isFullAyuForwardNeeded` (cpp:233-235), and the `needsIntelligentForward` gate
(← `apiwrap.cpp:3487/3495`) all match. Backend is fully wired: `engine.forwardMessages`,
`resendAsOwn`, `resendAlbumAsOwn` dispatch to real Go engine methods, and the model fields
they key on (`senderNoForwards`, `noForwards`, `unsupportedTTL`, `ttlSeconds`, `groupedId`)
are populated from the engine (`cache_msgs.go:379-412` etc.). The only substantive divergence
is progress fidelity on the re-upload path, below.

- [ ] [MAJOR] Resend-as-own progress count advances on **enqueue**, not on actual send — the bar jumps to "N/N" near-instantly while uploads continue invisibly in background goroutines. The Dart awaits `engine.resendAsOwn` / `resendAlbumAsOwn` then immediately bumps `sentInChunk` and updates progress, but those engine calls are fire-and-forget (`INSERT INTO pending` + `go processPendingItem()` + `return nil` — `go/engine/pending.go:484-489`), so the `await` resolves before any download/upload happens. AyuGram instead sets `state->sentMessages = i + 1` only **after** a synchronous, blocking per-message send (`AyuSync::sendDocumentSync` → `forwardMessages` loop), so the "Forwarding i/N" bar tracks genuine upload progress over the real (potentially long) duration. For a multi-video restricted forward the Dart bar flashes "done" and is cleaned up (`_scheduleCleanup`, 2 s) while messages keep arriving for tens of seconds. — `ayu_forward.dart:306-333` ← `AyuGram/.../ayu/features/forward/ayu_forward.cpp:366-441`

- [ ] [MAJOR] The "Loading media" (Downloading) phase is effectively never shown on the resend path. The Dart sets `phase: downloading` once via the per-chunk reset, then flips to `sending` after the first group's `await` returns (lines 329-332); because the engine enqueues atomically and returns immediately, the download phase lasts a synchronous instant and never paints. AyuGram sets `state == Downloading` and shows `ayu_AyuForwardStatusLoadingMedia` for the **entire** up-front `AyuSync::loadDocuments` call, which blocks on a `TimedCountDownLatch` until every document/photo is fully downloaded (`ayu_sync.cpp:86-130`), so "Loading media" is visible throughout the real download before any send. The Dart's own comment (lines 296-305) acknowledges the engine can't pre-download, but the user-visible Downloading state from AyuGram is lost. — `ayu_forward.dart:268-305` ← `AyuGram/.../ayu/features/forward/ayu_forward.cpp:355-360`

# chat_state — Chat list / active chat / messages state (port of AyuGram Data::Session + SendActionPainter + ChatFilters + Forum + SavedMessages + AutoDownload)

`ChatState` is a large `ChangeNotifier` data layer. It is thoroughly wired to the
engine — every displayed feature (chats, messages, folders, forum topics, saved
sublists, reaction tags, themes, downloads, group calls, connected bots, search)
routes through `_engine.*`, and engine events update the in-memory state. No
placeholders, stubs, empty callbacks, TODO/"coming soon", or hardcoded fake data
were found. Constants (kMessagesPerPageFirst=30 / kMessagesPerPage=50,
kListFirstPerPage=20 / kListPerPage=100 / kLoadedSublistsMinCount=20,
kTopicsFirstLoad=20 / kTopicsPerPage=500, kMaxChatEntryHistorySize=50,
kShowTopicNamesCount=8) all match AyuGram, and the folder unread-badge formula
matches `window_filters_menu.cpp` exactly. The findings below are behavioral
deviations in the send-action/typing port and the chat-theme variant selection.

- [ ] [MAJOR] Per-chat theme day/night variant is chosen from the OS setting (`WidgetsBinding...platformBrightness == Brightness.dark`) instead of the app's actual night-mode state. When the user forces a theme that differs from the OS (the app supports `_config.theme` ∈ light/night/day_blue/system → `AppState.themeMode`), the chat background renders the wrong light/dark variant of the emoticon theme. AyuGram resolves the variant via `IsNightMode()` (the app's current theme background lightness), never the OS brightness. Should resolve `_appState.themeMode` (only consulting `platformBrightness` for `ThemeMode.system`). — `chat_state.dart:2328` ← `AyuGram/data/data_cloud_themes.cpp:234` (and `AyuGram/window/themes/window_theme.cpp:1411` `IsNightMode()`)

- [ ] [MAJOR] All typing/send-action entries expire after a fixed `now + 6000` ms, but the `game_play` action must persist for 10 s. AyuGram uses `kStatusShowClientsidePlayGame = 10 * crl::time(1000)` (every other action is 6 s), and re-emplaces PlayGame on each event. With the fixed 6 s expiry a "playing a game" indicator vanishes ~4 s early. — `chat_state.dart:3230` ← `AyuGram/history/view/history_view_send_action.cpp:43,128`

- [ ] [MAJOR] Multi-user "playing a game" aggregation is missing. `typingSummaryFor` only aggregates entries whose `action == 'typing'` ("N people are typing" / "A and B are typing"); for every non-typing action it shows only `list.first`'s single label. AyuGram, when all active send-actions are PlayGame, aggregates them: >2 → `lng_many_playing_game` ("N people are playing a game"), 2 → `lng_users_playing_game` ("A and B are playing a game"), 1 → `lng_user_playing_game` / `lng_playing_game`. So 2+ game players render as one "X is playing game" instead of the aggregated string. (Also the singular label is "playing game" vs AyuGram "playing a game".) — `chat_state.dart:350-373` (and label `chat_state.dart:402`) ← `AyuGram/history/view/history_view_send_action.cpp:345-366`

- [ ] [MAJOR] `geo_location` and `choose_contact` send-actions are rendered as "choosing location" / "choosing contact", but AyuGram maps both `Type::ChooseLocation` and `Type::ChooseContact` to `lng_typing` / `lng_user_typing` — i.e. plain "typing" / "X is typing" (Telegram Desktop has no distinct strings for these two). The displayed subtitle text deviates from the authority. — `chat_state.dart:400-401` ← `AyuGram/history/view/history_view_send_action.cpp:296-299`

# telegram_palette — Telegram Desktop color palette + accent colorizer (port of `style_palette_colorizer.cpp` + `window_themes_embedded.cpp` + `colors.palette`)

Scope note: the colorize math (piecewise saturation/value, hue shift, HSL-lightness clamp via `lightnessMin/Max`), `hueThreshold=15`, the 4 accent presets, the 68-key `ignoreKeys` exclusion set, the `keepContrast`→`_enforceContrast` pass (incl. Night-only file-icon gating), the `sl()`/`sd()` day-only/night-only split, and the 4 static palettes' hex values were all cross-checked against AyuGram and verified faithful. The findings below are the exceptions — all are colorize-time deviations that surface only in **custom-accent mode** (the 4 default themes are unaffected because `colorize()` early-returns when the accent is unchanged). They stem from four keys not honoring `colors.palette` reference semantics: in C++ a referenced value is copied un-colorized (`window_theme.cpp:195-200`, the non-`#` branch skips `style::colorize`), so a key inherits its referent's *final* (colorized or raw) value.

- [ ] [MAJOR] `historyPeerSavedMessagesBg2` is colorized with `s()`, but it is `historyPeerSavedMessagesBg2: historyPeer4UserpicBg2` — a reference to an **ignoreKey** (`historyPeer4UserpicBg2` is never colorized), so C++ keeps it RAW. With a custom accent this shifts the Saved Messages cloud-avatar gradient (which is accent-independent in AyuGram). Should be a raw passthrough. — `telegram_palette.dart:1764` ← `Telegram/SourceFiles/window/themes/window_themes_embedded.cpp:64` (ignoreKeys) / `Telegram/lib_ui/ui/colors.palette:324`

- [ ] [MAJOR] `historyPeerSavedMessagesBg` is colorized with `sl()` (light-theme colorize), but it is `historyPeerSavedMessagesBg: historyPeer4UserpicBg` — a reference to an **ignoreKey** (`historyPeer4UserpicBg`, never colorized), so C++ keeps it RAW in every theme. In light themes with a custom accent the Saved Messages avatar bg deviates; combined with the `Bg2` bug above the gradient becomes internally inconsistent. Should be raw passthrough. — `telegram_palette.dart:1762` ← `Telegram/SourceFiles/window/themes/window_themes_embedded.cpp:48` (ignoreKeys) / `Telegram/lib_ui/ui/colors.palette:313`

- [ ] [MAJOR] `boxDividerBg` is left RAW (grouped under the wrong "good/error text exclusion" comment), but `boxDividerBg: windowBgOver` references a colorized key (`windowBgOver` is `s()`-colorized at `telegram_palette.dart:1386`) and is NOT in `ignoreKeys`. C++ resolves it to the colorized `windowBgOver`, so the box/layer divider should track the accent tint. Its sibling `boxDividerFg` is correctly `s()`-colorized (`telegram_palette.dart:1681`), confirming the inconsistency. Should be `s(boxDividerBg)`. — `telegram_palette.dart:1570` ← `Telegram/lib_ui/ui/colors.palette:146`

- [ ] [MAJOR] `rankUserFg` is left RAW, but `rankUserFg: windowSubTextFg` references a colorized key (`windowSubTextFg` is `s()`-colorized at `telegram_palette.dart:1392`) and is NOT in `ignoreKeys`. C++ resolves it to the colorized `windowSubTextFg`, so the member-rank badge text should track the accent. (Siblings `rankAdminFg`/`rankOwnerFg` are hex literals → correctly raw; only `rankUserFg` is a reference.) Should be `s(rankUserFg)`. — `telegram_palette.dart:1968` ← `Telegram/lib_ui/ui/colors.palette:688`

# theme — ThemeData factory built from TelegramPalette (colorScheme, input/scrollbar/tooltip themes, text theme)

- [ ] [MAJOR] Scrollbar thumb has no hover/drag highlight state. theme.dart sets `thumbColor: WidgetStateProperty.all(p.scrollBarBg)` — a single resting color for ALL states, which also actively suppresses Flutter's own built-in hover affordance. AyuGram animates the thumb between two distinct palette colors on hover or while dragging: `anim::color(_st->barBg, _st->barBgOver, _a_barOver.value((_overbar || _moving) ? 1. : 0.))`. The two colors differ substantially — `scrollBarBg #00000053` (≈33% opacity) vs `scrollBarBgOver #0000007a` (≈48% opacity), a ~47% opacity jump — so the missing state is clearly visible: the thumb never brightens when grabbed. Fix: use `WidgetStateProperty.resolveWith` returning `p.scrollBarBgOver` for `hovered`/`dragged` and `p.scrollBarBg` otherwise. — `theme.dart:85-87` ← `AyuGram/Telegram/lib_ui/ui/widgets/scroll_area.cpp:289` (palette `colors.palette:62-63`, style `widgets.style:819-820`)

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

## Findings

- [ ] [MAJOR] Palette-file selection inside a zip uses first-match in archive iteration order across BOTH `colors.tdesktop-theme` and `colors.tdesktop-palette`, instead of AyuGram's strict priority (try `colors.tdesktop-theme` first, fall back to `colors.tdesktop-palette` only if absent). If a zip contains both and `colors.tdesktop-palette` appears first, the wrong palette is loaded. The fix is trivial and the data is already on hand — the `entries` map built two lines above is used to give backgrounds their correct fixed priority (`theme_file.dart:513-525`) but is not used for the palette; `entries['colors.tdesktop-theme'] ?? entries['colors.tdesktop-palette']` would restore AyuGram's ordering. (Edge case — standard Telegram themes ship only `colors.tdesktop-theme` — but a genuine behavioral divergence from the authority.) — `theme_file.dart:505-508` ← `AyuGram/window/themes/window_theme.cpp:302-307`

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

- [ ] [MAJOR] Audio waveform is drawn ~22–25% too narrow: the Dart reserves a fixed 50px on the right (`waveRight = bubbleX + bubbleW - 50`), so the bars span `bubbleW-117` and stop ~52px short of the bubble's right edge with empty space after them. AyuGram reserves only `nameright = msgFileLayout.padding.right()` (10px) and the waveform spans `bubble.width - 77 + msgWaveformSkip`, filling to within ~10px of the right edge (≈64 bars vs the Dart's ≈47). The right band the Dart reserves is unused — the duration "0:07" is on the left (`waveLeft`, both impls) and the timestamp sits on a lower row, so there is nothing to clear. — `theme_preview.dart:771` ← `AyuGram/window/themes/window_theme_preview.cpp:938`

# active_sessions_screen — Active Sessions screen (Privacy & Security → Devices)

Scope: `dart/lib/ui/active_sessions_screen.dart` vs AyuGram `settings/sections/settings_active_sessions.cpp`, `api/api_authorizations.cpp`, `boxes/self_destruction_box.cpp`, and `settings/settings.style` / `info/info.style`.

Verified GOOD (no findings): device classification `_classifyDevice` is a faithful 1:1 port of `TypeFromEntry` (telegram→`settings_active_sessions.cpp:167-235`); gradient/icon mappings match (`:237-322`); section ordering + toggle gating (terminate-all on incomplete+other>0, incomplete on >0, other on >0, TTL on other>0, placeholder on other==0) matches `:1023-1031`; `_formatDaysLabel` == `SelfDestructionBox::DaysLabel` (`self_destruction_box.cpp:185-193`); TTL options `[7,30,90,180,365]` == `Values(Sessions)` (`:97`); optimistic single-terminate removal matches `terminateOne` (`:850-877`); row dimensions (84px height, photo 21,10 / 42px, name 78,11, status 78,32, location top 54, terminate 34×34 at right 11/top 8) all match `settings.style:356-423`; engine reads/terminate/TTL-get/TTL-set are all real FFI calls hitting live MTProto APIs.

## Backend wiring

- [ ] [CRITICAL] "Rename current device" is cosmetic / local-only — the rename succeeds in the UI and updates `AppState.customDeviceModel`, but the engine call `setCustomDeviceModel` lands on a Go no-op: `TelegramCore.SetCustomDeviceModel` only stores the string in `t.customDeviceModel` and returns (the doc comment claims it "triggers a help.getConfig call to propagate it via initConnection" but no such call exists, and `customDeviceModel` is never read anywhere in the Go codebase). So the new name is NEVER sent to Telegram, never propagates to other clients, and is lost on a fresh `GetSessions` fetch. AyuGram routes the rename through `Core::App().settings().setCustomDeviceModel()` → `deviceModel()` → MTProto `initConnection.device_model` (propagates on reconnect) and updates the live authorization name reactively via `deviceModelChanges()`. — `active_sessions_screen.dart:824` (+ Go stub `go/cores/telegram.go:14406-14410`) ← `AyuGram/settings/sections/settings_active_sessions.cpp:148-154` + `AyuGram/api/api_authorizations.cpp:103-115,59-61`

- [ ] [MAJOR] Application name/version string is shown raw, skipping AyuGram's `ParseEntry` normalization, so the displayed "Application" text deviates for many sessions. AyuGram builds `info` as: desktop api_ids (2040/611335/17349) → app name forced to `"Telegram Desktop"` and an integer `app_version` reformatted via `Core::FormatVersionDisplay` (e.g. `4016008` → `4.16.8`); non-desktop → version reduced to its parenthetical build segment (`"10.2.0 (12345)"` → `"(12345)"`). The port concatenates the raw `app_name` + raw `app_version` with no transformation, so a desktop session with an integer version renders the unformatted integer, and mobile sessions show the full version instead of the build segment. (Root cause is the raw mapping in Go `GetActiveSessions`, but the Dart is the consumer that displays it in both the row status and the info-box "Application" row.) — `active_sessions_screen.dart:1239-1242` and `active_sessions_screen.dart:596` (+ Go `go/cores/telegram.go:14366-14367`) ← `AyuGram/api/api_authorizations.cpp:41-57,75-77`

## Visual / layout

- [ ] [MAJOR] Hard-coded hex colors instead of the `TelegramPalette` theme tokens — the screen ignores the palette for backgrounds/text/subtext/dividers and inlines dark/light hex pairs that don't match the palette and don't follow the app's themes. The palette exposes exactly the right tokens (`windowBg`, `windowFg`/`boxTextFg`, `windowSubTextFg`), and AyuGram is fully token-driven (e.g. `sessionInfoFg: windowSubTextFg`). Concrete mismatches: dark `textColor 0xFFE1E3E6` ≠ palette `windowFg`/`boxTextFg` dark `0xFFF5F5F5` (`telegram_palette.dart:3659,3855`); dark `subtextColor 0xFF6D7F8F` ≠ `windowSubTextFg` dark `0xFF708499` (`:3662`); light `textColor 0xFF222222` ≠ `windowFg` light `0xFF000000` (`:3031`). The hard-coded `bgColor 0xFF17212B`/`subtext` are also flatly wrong under the app's second dark theme (`windowBg 0xFF282E33`, `:4872`), where this screen still paints `0xFF17212B`. Same pattern is duplicated at `:356-358`, `:492/498`, `:602-607`, `:780-805`, `:864-867`, `:1254`. — `active_sessions_screen.dart:864-867` ← `AyuGram/settings/settings.style:359` (`sessionInfoFg: windowSubTextFg`)

- [ ] [MAJOR] "Terminate All Other Sessions" button is center-aligned with an icon+text Row, but AyuGram renders it as a standard full-width settings button (`CreateButtonWithIcon(..., st::infoBlockButton, {.icon=&st::infoIconBlock})`) — left-aligned: block icon at `iconLeft: 22px` and red text starting at `padding.left: 79px`, not centered. The Dart's `MainAxisAlignment.center` produces a visibly different layout (centered short label vs. left-aligned settings row). — `active_sessions_screen.dart:1053` ← `AyuGram/settings/sections/settings_active_sessions.cpp:961-966` + `AyuGram/info/info.style:731-738` (`infoProfileButton` padding 79px / iconLeft 22px)

# admin_tools — group/channel/bot admin management suite (edit-info, permissions, participants, admin-log, invite-links, statistics, boosts, monetization, star-ref)

Audited the full 15,165-line file in 15 component slices against AyuGram Desktop C++ (ground truth). All CRITICAL items below were re-verified by reading both sources directly (and the Go engine where data-flow is implicated). Sections found faithful with no CRITICAL/MAJOR issues: the group manage-rows + save-pipeline + sticker-set + delete (2000-3094), the admin event log + filter (6160-7797), the manage-invite-links box (7798-8672), and the link-detail + create/edit-link form (8673-9528).

## _EditPeerInfoBox (edit_peer_info_box.cpp + edit_peer_type_box / edit_discussion_link_box / edit_privacy_box)

- [ ] [CRITICAL] "Restrict Saving Content" / "Members Must Join to Send" / "Approve New Members" are rendered as standalone manage-section rows and committed on Save (`toggleNoForwards`/`toggleJoinToSend`/`toggleJoinRequest` at admin_tools.dart:2931/2938/2945). AyuGram has NO such rows in `fillManageSection` — these three settings live exclusively inside `EditPeerTypeBox` (reported back via the `_privacyTypeUpdates` callback). They are ALSO present and wired inside the Dart type box (`create_group_wizard.dart:3376`/`3047`, committing via `toggleNoForwards` at :2921), so the same settings exist in two screens and both POST to the backend — duplicate, divergent controls. — `admin_tools.dart:903-936` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_info_box.cpp:881` (privacy-type callback, no standalone rows) + `edit_peer_type_box.cpp:226`
- [ ] [MAJOR] The "Discussion Group / Linked Channel" row renders unconditionally for every non-bot peer, so it appears for legacy basic groups and for broadcast admins who lack edit rights and have no existing link. AyuGram only creates it when `isChannel && (channel->discussionLink() || (channel->isBroadcast() && channel->canEditInformation()))`. — `admin_tools.dart:852-863` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_info_box.cpp:1470`
- [ ] [MAJOR] Selecting a discussion group applies the link immediately on tap (`setState(_linkedChatId = gId)`) with no confirmation. AyuGram routes every selection through `MakeConfirmBox` carrying the private-channel / hidden-pre-history warnings and only links after the user confirms. — `admin_tools.dart:1068-1077` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_discussion_link_box.cpp:141`
- [ ] [MAJOR] The "Currently linked" entry displays the raw chat-ID string from `getLinkedChatId` instead of the linked peer's name. AyuGram renders the linked peer as a `PeerListRow` with its real name + username/"private" status line. — `admin_tools.dart:1041` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_discussion_link_box.cpp:97`
- [ ] [MAJOR] `_showLinkedChatDialog` has no "Create discussion group" action. For a broadcast with no linked chat, AyuGram adds a `lng_manage_discussion_group_create` button that creates a megagroup and links it — the only way to attach a brand-new group is missing. — `admin_tools.dart:1023-1106` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_discussion_link_box.cpp:268`
- [ ] [MAJOR] Direct-messages Stars price uses a free unbounded `TextField` with no max cap and no commission/USD detail; the parsed save value is `int.tryParse(...) ?? 0` with no clamp, so out-of-range prices can be sent. AyuGram's `EditDirectMessagesPriceBox` uses a `SetupChargeSlider` bounded by `appConfig.paidMessageStarsMax()` (default 10000), seeded with the channel default, and shows a live "≈ $X, N% commission" divider. — `admin_tools.dart:1829` (+ no clamp at :1850) ← `AyuGram/Telegram/SourceFiles/boxes/edit_privacy_box.cpp:1337`

## _EditPeerPermissionsBox (edit_peer_permissions_box.cpp)

- [ ] [MAJOR] Existing `boosts_unrestrict` value is never loaded — `_loadRights` reads `rights['boosts_unrestrict']` but the engine's `GetDefaultBannedRights` response (`go/cores/telegram.go` `DefaultBannedRights` struct) contains no such field, so it is always 0. The boosts toggle/slider therefore always opens OFF even when a threshold is set, and on Save the stale 0 is written back via `setBoostsUnrestrict`, silently clearing the existing threshold. AyuGram seeds it from `channel->boostsUnrestrict()`. — `admin_tools.dart:3223` (+ save at :3248) ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_permissions_box.cpp:954`
- [ ] [MAJOR] Existing `charge_stars` value is never loaded — `_loadRights` reads `rights['charge_stars']` but `GetDefaultBannedRights` never returns it, so the "Charge Stars for Messages" toggle always opens OFF, and on Save the box unconditionally calls `updatePaidMessagesPrice(..., 0, ...)` whenever paid-messages are possible, silently disabling an existing charge. AyuGram seeds it from `commonStarsPerMessage()`. — `admin_tools.dart:3225` (+ save at :3250) ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_permissions_box.cpp:1184`
- [ ] [MAJOR] `edit_rank` permission is a permanently dead toggle — Dart hardcodes `_PermFlag(key: 'edit_rank', ..., locked: true)` and `_toggleFlag` early-returns on locked flags. In AyuGram's default-permissions box `EditRank` is a normal editable checkbox (in `NestedRestrictionLabelsList`, not in the `disabledMessages` lock map), and the Go backend round-trips `edit_rank`, so the toggle should be live. — `admin_tools.dart:3192` (toggle gate at :3266) ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_permissions_box.cpp:99`

## _BotStarRefSetupScreen (info_bot_starref_setup_widget.cpp + info_bot_starref_common.cpp)

- [ ] [CRITICAL] `_save()` writes the program directly via `engine.setStarRefProgram` with NO irreversible-change confirmation. AyuGram gates every save behind `ConfirmUpdate`, which shows a warning box (`lng_star_ref_warning_change`/`_text`: "you won't be able to decrease its commission or duration…") + a summary table, and only commits on confirm. Users can irreversibly cut commission/duration with no warning. — `admin_tools.dart:4106` ← `AyuGram/Telegram/SourceFiles/info/bot/starref/info_bot_starref_setup_widget.cpp:1022` (+ `info_bot_starref_common.cpp:906`)
- [ ] [CRITICAL] `_end()` ends the program directly via `setStarRefProgram(commissionPermille: 0)` with NO confirmation. AyuGram gates ending behind `ConfirmEndBox` — a "Warning" box listing three bullet points (`lng_star_ref_warning_if_end1/2/3`) with "End Anyway"/"Cancel". — `admin_tools.dart:4129` ← `AyuGram/Telegram/SourceFiles/info/bot/starref/info_bot_starref_setup_widget.cpp:745` (+ `info_bot_starref_common.cpp:701`)
- [ ] [MAJOR] No lower-bound lock when a program already exists. AyuGram passes `_state.exists` as `forbidLessThanValue` to both the commission and duration sliders, fading/locking all values below the current ones so an existing program can only be increased. The Dart commission `Slider` always uses `min: _commissionMin` and all duration radios stay selectable, allowing a decrease the server will reject. — `admin_tools.dart:4173` ← `AyuGram/Telegram/SourceFiles/info/bot/starref/info_bot_starref_setup_widget.cpp:667`
- [ ] [MAJOR] Commission/duration min & max are read from `getBotManageInfo` keys (`starref_commission_min`/`max`) the Go engine never returns (`telegram.go` emits only `starref_commission`/`starref_allowed`), so `_load()` always falls back to hardcoded `10`/`900`. AyuGram reads `starref_min/max_commission_permille` from appConfig (server-driven). — `admin_tools.dart:4071` ← `AyuGram/Telegram/SourceFiles/info/bot/starref/info_bot_starref_setup_widget.cpp:626` (+ `main/main_app_config.cpp:92`)
- [ ] [MAJOR] Duration uses a `RadioListTile` list ("3 months"/"2 years"/"Forever") instead of AyuGram's `MakeSliderWithTopLabels` slider with tiny labels (`lng_months_tiny`/`lng_years_tiny` + "∞"); the radio list also cannot express the lower-bound lock the slider provides for existing programs. — `admin_tools.dart:4182` ← `AyuGram/Telegram/SourceFiles/info/bot/starref/info_bot_starref_setup_widget.cpp:700`

## _EditRestrictedBox (edit_participant_box.cpp — EditRestrictedBox)

- [ ] [MAJOR] The "Send media" master toggle force-overwrites every media flag including ones forbidden-for-all-members — toggling it ON sets `f.banned = false` for flags in `_defaultBannedKeys`, granting a permission the chat denies to everyone and writing it as allowed on save, contradicting the locked-ON display in `_buildPermToggle`. AyuGram disables default-restricted checkboxes so no toggle can flip them; the loop must skip `flag.locked`/`_defaultBannedKeys` flags. — `admin_tools.dart:4804` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participant_box.cpp:746`
- [ ] [MAJOR] Media sub-checkboxes render no lock affordance for default-forbidden flags — `_buildMediaCheckbox` shows a plain unchecked box (no lock icon / "Forbidden for all members" subtext) for `_defaultBannedKeys` flags, and tapping silently no-ops (`_toggleFlag` returns early) with no toast, so the forbidden-for-all state is invisible inside the media group. AyuGram renders the locked/disabled state with a tooltip on every nested restriction checkbox. — `admin_tools.dart:4838` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participant_box.cpp:758`

## _EditAdminBox (edit_participant_box.cpp — EditAdminBox + channel_ownership_transfer.cpp)

- [ ] [CRITICAL] Editing an existing admin does NOT load their real saved rights — `_loadExistingRights()` reads `info['admin_rights']`/`info['rank']`, but the engine's `GetParticipantInfo` never populates those for an admin participant (the `ChannelParticipantAdmin` branch in `go/cores/telegram.go:22058` only sets `Role="admin"`; the returned `User` struct has no `admin_rights` map nor `rank` field — only the *banned* branch fills a rights map). So `rights == null` → the method returns at line 5394, flags keep their all-on defaults and rank stays blank. AyuGram seeds the box from the participant's real `_oldRights`/`_oldRank`. — `admin_tools.dart:5384-5394` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participant_box.cpp:304`
- [ ] [CRITICAL] Default rights for a NEW admin are wrong — `_AdminFlag` defaults `enabled = true` for every flag (incl. `anonymous` and `add_admins`), and `_loadExistingRights()` is skipped unless `role=='admin'`. So promoting a plain member pre-checks "Remain anonymous" and "Add new admins", which AyuGram's `defaultRights()` deliberately leaves OFF (megagroup default omits `Anonymous`+`AddAdmins`; broadcast default omits `AddAdmins`). Granting add-admins/anonymous by default is a security-relevant deviation. — `admin_tools.dart:5050` (default) + `:5327`/`:5351`/`:5352` (flags), gated at `:5358` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participant_box.cpp:311`

## _MemberListScreen / _MemberPickerDialog / _MemberRow (edit_participants_box.cpp + add_participants_box.cpp)

- [ ] [MAJOR] Add-member picker has no "Add Members via Link" invite-link button. AyuGram's `AddParticipantsBoxController` renders it at the top of the contacts picker (gated on `canHaveInviteLink`); `_MemberPickerDialog` never offers it. — `admin_tools.dart:10431` ← `AyuGram/Telegram/SourceFiles/boxes/peers/add_participants_box.cpp:912`
- [ ] [MAJOR] Global search is single-username resolve, not a real people search. AyuGram's `requestGlobal` calls `contacts.Search` and auto-appends ALL matching users (by name/username). The Dart `_resolveGlobal` only calls `resolveUsername` (one exact `@username`), triggered manually via a button — partial-name/multi-result search is absent. — `admin_tools.dart:10376` ← `AyuGram/Telegram/SourceFiles/boxes/peers/add_participants_box.cpp:1894`
- [ ] [MAJOR] Broadcast-channel "Add Subscribers" button is missing. AyuGram shows the add button on a broadcast's subscribers list when `canAddMembers() && membersCount < chatSizeMax`. `_canAddForTab(members)` returns `!widget.isChannel && _canInviteUsers`, hard-excluding all channels. — `admin_tools.dart:9707` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participants_box.cpp:1090`
- [ ] [MAJOR] Kicked-tab "Add to Banned" bans the picked user with no confirmation. AyuGram's `kickUser` shows a confirm box (`lng_profile_sure_kick`, + `lng_sure_ban_admin` if target is admin) before banning; the Dart calls `engine.banMember` immediately. — `admin_tools.dart:10125` ← `AyuGram/Telegram/SourceFiles/boxes/peers/add_participants_box.cpp:1653`
- [ ] [MAJOR] Tapping a join-request row body does nothing — `_MemberRow` sets `onTap: isRequest ? null`. AyuGram's `RequestsBoxController::rowClicked` opens the requester's profile. — `admin_tools.dart:10993` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_peer_requests_box.cpp:409`
- [ ] [MAJOR] Admins/Kicked/Restricted row subtitle differs — `_statusText()` shows only static role labels ('owner'/'admin'/'restricted'/'banned'). AyuGram's `refreshCustomStatus` sets the always-visible subtitle to "promoted by {name}" / "removed by {name}" / "restricted by {name}"; the Dart relocates that to a disabled context-menu line. — `admin_tools.dart:10590` ← `AyuGram/Telegram/SourceFiles/boxes/peers/edit_participants_box.cpp:2421`

## _StatisticsScreen / _MessageStatsScreen (info/statistics/*)

- [ ] [MAJOR] Per-message overview reuses the recent-post row's snapshot counters (`widget.views`/`reactions`/`forwards`) and gates the Views/Reactions cards on `> 0`, so opening message stats from a path where those weren't populated hides cards even when the API has the data. AyuGram re-fetches live `views`/`reactions`/`forwards` via `channels.GetMessages` and always shows cards when `>= 0`. — `admin_tools.dart:12669` (+ :12671/:12647) ← `AyuGram/Telegram/SourceFiles/info/statistics/info_statistics_inner_widget.cpp:516` (+ `api/api_statistics.cpp:405`)

## _BoostsScreen / _BoosterRow (info/channel_statistics/boosts/info_boosts_inner_widget.cpp)

- [ ] [CRITICAL] Booster `user_id` arrives as an `int` from the engine but is read with `booster['user_id'] as String?`, which throws a `TypeError` at runtime for every real-user booster — the Go core stores the raw `int64` via `row["user_id"] = uid` (`go/cores/telegram.go:19001`), unlike its other call sites that stringify ids. This crashes the row build for any genuine booster. — `admin_tools.dart:13299` (+ onTap at :13342) ← `AyuGram/Telegram/SourceFiles/info/statistics/info_statistics_list_controllers.cpp:730`
- [ ] [MAJOR] Booster-click behavior is heavily reduced. AyuGram's `boostClicked` resolves gift-code links (`ResolveGiftCode` → `GiftCodePendingBox`), opens `BoostCreditsBox` for credits boosts, and shows the pending-boost toast; the Dart row only ever opens the user profile and silently drops every other branch. — `admin_tools.dart:13342-13348` ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/boosts/info_boosts_inner_widget.cpp:402`
- [ ] [MAJOR] `_BoosterRow` reads `credits`/`stars` state the engine never emits (the Go per-boost row only sets `id/date/expires/gift/giveaway/unclaimed/user_id/user_name/multiplier`), so the `isCredits` "$N Stars" name path and credits styling are dead code that can never trigger. — `admin_tools.dart:13304-13305` ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/boosts/info_boosts_inner_widget.cpp:408` (engine: `go/cores/telegram.go:18992-19013`)
- [ ] [MAJOR] Premium-audience count cell falls back to a literal `0` — the Dart reads `premium_audience['premium']`/`['premium_count']` but the engine emits only `part`/`total`, so the overview renders "0" instead of the real `premiumMemberCount`. — `admin_tools.dart:12932-12933` (+ :12999) ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/boosts/info_boosts_inner_widget.cpp:125`
- [ ] [MAJOR] Booster/gift pagination uses silent scroll-to-bottom auto-loading instead of AyuGram's explicit labeled "Show more (N)" button (`AddShowMoreButton` with `lng_boosts_show_more_boosts`/`_gifts` + live remaining count). — `admin_tools.dart:12920-12930` ← `AyuGram/Telegram/SourceFiles/info/statistics/info_statistics_list_controllers.cpp:1457`

## _MonetizationScreen (info/channel_statistics/earn/info_channel_earn_list.cpp)

- [ ] [MAJOR] TON transaction-detail box reads `tx['recipient'] ?? tx['address']` for the "Recipient" row, but the Go backend's `GetBroadcastRevenueTransactions` never populates `recipient`/`address`/`provider`, so the row is always empty. AyuGram renders `entry.provider` as a code-wrapped recipient row via `AddRecipient`. — `admin_tools.dart:13961` (+ :13987) ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/earn/info_channel_earn_list.cpp:1084`
- [ ] [MAJOR] Stars transaction-detail (`_showTxDetails`) is a custom simplified dialog (Amount/Date/Description/ID). AyuGram routes a Stars/credits history-entry click to `ReceiptCreditsBox` (full receipt: peer bubble, gift/subscription/refund details). Data shown is real but the surface is materially thinner. — `admin_tools.dart:13848` ← `AyuGram/Telegram/SourceFiles/info/channel_statistics/earn/info_channel_earn_list.cpp:1351`

## _StarRefJoinScreen / _ConnectedStarRefRow / _SuggestedStarRefRow (info_bot_starref_join_widget.cpp + info_bot_starref_common.cpp)

- [ ] [MAJOR] Bot userpics never render — both rows read `bot['avatar_b64']` to show a real peer userpic, but the engine's connected/suggested-bots builders never emit `avatar_b64`, so every row always falls back to the colored letter-tile (a `getUserAvatarB64` helper exists in-file but is not called here). — `admin_tools.dart:14994` (+ :15121) ← `AyuGram/Telegram/SourceFiles/info/bot/starref/info_bot_starref_join_widget.cpp:199`
- [ ] [MAJOR] JoinStarRefBox confirm dialog omits the estimated daily-revenue line — AyuGram's `JoinStarRefBox` shows a "≈ X / day" line from `program.revenuePerUser` (`lng_star_ref_one_daily_revenue`). The gotd `StarRefProgram` exposes `DailyRevenuePerUser`, but the Go suggested-bots builder drops it and `_confirmJoin` never renders it. — `admin_tools.dart:14649` ← `AyuGram/Telegram/SourceFiles/info/bot/starref/info_bot_starref_common.cpp:569`

# advanced_settings_screen — Advanced settings page (§14.7) + sub-dialogs (update, proxies, local storage, auto-download, power saving, dictionaries, downloads, experimental)

Audited the full 5110-line file against `settings/sections/settings_advanced.cpp` and the boxes it
opens (`connection_box.cpp`, `auto_download_box.cpp`, `local_storage_box.cpp`,
`dictionaries_manager.cpp`, `download_path_box.cpp`, `info/downloads/info_downloads_widget.cpp`),
plus `settings/settings_power_saving.cpp`, `settings/settings_experimental.cpp` and
`mtproto/mtproto_proxy_data.cpp`. Section ordering, the Update/Data-and-Storage/Window-Title/
Window-Close/System-Integration/Performance/Spellchecker/Screen-Reader/Export sections, the proxy
secret-validation + link-parsing math, the auto-download size curve, the local-storage ladders/tag
accounting, the power-saving flag bits/grouping, and the dictionaries/recent-downloads pipelines were
all verified faithful and wired to real engine calls. Findings below are the deviations that rise to
CRITICAL/MAJOR.

- [ ] [CRITICAL] Experimental toggles are dead — the box persists hyphenated flag IDs (`dialogs-mute-icon`, `forum-hide-chats-list`, `disable-autoplay-next`, `use-small-msg-bubble-radius`, …) via `setExperimentalFlags` + `SetExperimentalFlag`, but every in-app consumer reads a DIFFERENT key: `dialogs_mute_icon` (`chat_list_row.dart:123`), `forum_chat_list` (`chat_list_panel.dart:1039`), `autoplay_gifs` (`message_bubble.dart:6916`), `message_draft_visible` (`chat_list_row.dart:124`), `large_bubble_radius` (`message_bubble.dart:784`). Zero of the 5 consumers match a box flag ID, so toggling anything here has no runtime effect. AyuGram's `option.set(toggled)` writes the very option object the consumer reads back via `base::options::value`. — `advanced_settings_screen.dart:5047` ← `settings/settings_experimental.cpp:220`
- [ ] [MAJOR] `fast-buttons-mode` toggle is always listed; AyuGram only registers it when its value is already true (`if (base::options::lookup<bool>(kOptionFastButtonsMode).value()) addToggle(...)`), so a normal user never sees this control. — `advanced_settings_screen.dart:4848` ← `settings/settings_experimental.cpp:306`
- [ ] [MAJOR] No restart-required handling — AyuGram arms a restart timer + "need restart" confirm box for restart-required options (FreeType, fractional scaling, small bubble radius, custom notifications, legacy Edge, deadlock detector …); the Dart Save path persists silently with no restart prompt. — `advanced_settings_screen.dart:5045` ← `settings/settings_experimental.cpp:196`
- [ ] [MAJOR] Per-option description blocks are absent — AyuGram renders each option's `.description()` as an `AddDividerText` directly under its toggle; the Dart box shows only one global warning line and no per-flag descriptions. — `advanced_settings_screen.dart:5010` ← `settings/settings_experimental.cpp:227`
- [ ] [MAJOR] Proxy "sponsored channel" warning text is semantically altered — Dart shows "…This is done by the proxy provider, not by Telegram." but the original (`lng_proxy_sponsor_warning`) reassures about traffic privacy: "…This doesn't reveal any of your Telegram traffic." — `advanced_settings_screen.dart:4363` ← `boxes/connection_box.cpp:1488`

# auth_screen — Telegram intro/login flow (phone, code, 2FA, QR, signup, email)

Audited `dart/lib/ui/auth_screen.dart` against AyuGram's `intro/` step widgets
(`intro_phone.cpp`, `intro_code.cpp`, `intro_code_input.cpp`,
`intro_password_check.cpp`, `intro_signup.cpp`, `intro_email.cpp`,
`intro_qr.cpp`, `intro_step.cpp`, `intro_widget.cpp`, `intro.style`).

Overall the FSM wiring is real: phone/code/2FA/signup/email/QR all submit
through `AuthState.submitInput`/`switchToMethod` to the engine, the OTP cells
(40×50, 4px border, 10px gap, 20px font, windowBgOver fill, theme borders),
the auto-call countdown (`__resend_code`), the "no telegram code" resend
(`__no_telegram_code`), pushed login-code auto-fill, recovery/reset flows, and
2FA absolute layout (top 1/34/74/151/220 ↔ introTitleTop/DescriptionTop/
PasswordTop/PasswordHintTop/ErrorBelowLinkTop) are faithfully ported. The
passkey link is correctly gated out (`WebAuthn.isSupported()==false`), matching
AyuGram's Linux build, so the no-op `_loginWithPasskey` is unreachable dead code
rather than a visible placeholder. The issues below are real deviations.

- [ ] [MAJOR] Code-step subtitle ignores login-email delivery (`emailPatternLogin`): the masked email is never shown and the subtitle falls through to the generic phone text. AyuGram picks `emailPatternSetup` *or* `emailPatternLogin` (the `auth.sentCodeTypeEmailCode` case) and shows `lng_intro_email_confirm_subtitle` with the masked address. The Dart `AuthStateData` has no `emailPatternLogin` field at all, so the data never reaches the UI — `auth_screen.dart:1346-1356` (+ missing field `dart/lib/models/engine_models.dart:128`) ← `AyuGram/Telegram/SourceFiles/intro/intro_code.cpp:87-90` (and `intro_step.cpp:381-383`).

- [ ] [MAJOR] QR step renders the title (and a lock icon) ABOVE the QR graphic; AyuGram puts the QR graphic at the very top, the title BELOW it, then the 3 numbered steps, then the phone link. `_buildStepContent` builds `[icon, title, label, hint, _buildQR]` so the focal QR code is pushed below a big centered heading — `auth_screen.dart:648-705,700-701` ← `AyuGram/Telegram/SourceFiles/intro/intro_qr.cpp:285-362` with `intro.style:179` (`introQrTop:-18px`), `intro.style:195` (`introQrTitleTop:196px`), `intro.style:199` (`introQrStepsTop:232px`).

- [ ] [MAJOR] Spurious 48px `Icons.lock_outlined` injected at the top of the phone, code, and QR steps. None of AyuGram's `PhoneWidget`/`CodeWidget`/`QrWidget` have a leading icon — the phone/code steps show only title + description, and the QR step shows the QR graphic. The invented icon changes the visual structure of all three steps — `auth_screen.dart:653-660` ← `AyuGram/Telegram/SourceFiles/intro/intro_phone.cpp:92-93`, `intro_code.cpp:30-69`, `intro_qr.cpp:285-362`.

- [ ] [MAJOR] Hardcoded English strings defeat the screen's own live-localization (it watches `LangPack` and re-renders on language change, `auth_screen.dart:338-340`), so these labels stay English in every other language while the rest of the intro translates. AyuGram pulls each from the lang pack: 2FA field labels `'Password'`/`'Recovery Code'` (`auth_screen.dart:810`) ← `lng_signin_password`/`lng_signin_code` (`intro_password_check.cpp:35,37`); `'Forgot password?'`/`'Try password'` (`auth_screen.dart:846`) ← `lng_signin_recover`/`lng_signin_try_password` (`intro_password_check.cpp:38-39`); `'Quick log in using QR code'` (`auth_screen.dart:1596`) ← `lng_phone_to_qr` (`intro_phone.cpp:114`); `'Enter Login Email'` (`auth_screen.dart:1093`, comment even names the key) ← `lng_settings_cloud_login_email_placeholder` (`intro_email.cpp:74`).

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

