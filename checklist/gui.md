# GUI Audit — Cycle 2 Phase Ayugram (2026-06-04 03:56)

## Code Comparison (Dart vs AyuGram)

# notification_sound — in-app notification ringtone player (volume resolution + audio ducking)

Scope: `NotificationSoundPlayer` plays the alert sound for a notification (custom
per-chat ringtone or bundled `msg_incoming.mp3`), applies the resolved ringtone
volume, and asks the host to duck other in-app audio for the sound's length —
mirroring AyuGram `System::showNext()` sound block (`notifications_manager.cpp:761-779`).

Verified CORRECT (no finding — recorded so the next pass doesn't re-chase them):
- Player is real and fully wired: constructed `notification_system.dart:93`, `init()`
  `:182`, `play()` `:624`, `dispose()` `:841`; `onDuck` bound to `AudioService.duckFor`
  in `main.dart:577`. No stubs, no placeholders, no empty callbacks.
- 3-tier volume chain matches AyuGram exactly: per-chat → per-notify-type is resolved
  upstream in `app_state.ringtoneVolume()` (`app_state.dart:3099-3104`) and passed as
  `perChatVolume`; the global fallback lives here (`notification_sound.dart:68`). Equals
  AyuGram `ringtoneVolume(peer)→ringtoneVolume(DefaultNotifyType)→notificationsVolume()`
  (`notifications_manager.cpp:763-772`, `media_audio_track.cpp:158-160`).
- `allowSound` / `soundNone` gates and custom-ringtone-vs-default selection match
  `settings.soundNotify()` + `sound(thread).none/.id` (`notifications_manager.cpp:761`,
  `:987-1004`). The legacy/hidden global `_soundOverrides` path (`core_settings.cpp:1245`,
  only reachable via migration + settings-code easter-egg) is reasonably omitted.

# notification_system — scheduling/dedup/grouping/alert orchestration (ports AyuGram `Window::Notifications::System`)

Overall the port is faithful: `_countTiming` (online-aware cloud/default delay), `_passesDedup`
(per-thread reaction/poll 1-hour window), the single pending forward/album group buffer with
flush-on-different-group, the muteStateUnknown deferral + `checkDelayed` resolution, passcode-lock
forcing hide-details, and per-chat/account/all clears all match the C++ closely. The findings below
are real behavioral divergences and one dead subsystem — no fake UI or mock data.

# notification_types — notification content composition (title/subtitle/body/entities)

This file is a faithful, heavily-annotated 1:1 port of AyuGram's notification text
composition. Verified matching: `_composeTitle` ↔ `NativeManager::doShowNotification`
title block (notifications_manager.cpp:1566-1585), `_composeSubtitle` ↔
`notificationHeader()` (history_item.cpp:2767-2776), `_composeBody` ordering
(notifications_manager.cpp:1596-1616), media-type strings (data_media_types.cpp
MediaPhoto/MediaFile/MediaContact/MediaLocation/MediaInvoice), `WithCaptionNotificationText`
"Type, caption" format (data_media_types.cpp:103-124), `TextWithForwardedChar` ➡️
(notifications_manager.cpp:81-86), `TextWithPermanentSpoiler` ▚=0x259A
(notifications_manager.cpp:88-100), `SpoilerLoginCode` regex + intersection guard
(history_item.cpp:105-124), 255-cap truncation (history_item.cpp:4325-4329),
reaction/poll-vote strings (notifications_manager.cpp:1140-1245), and account-name
suffix ` ➜ ` with displayName fallback (notifications_manager.cpp:1264-1278 +
chat_state.dart:2791-2796). The two findings below are real gaps.

# app_state — top-level AppState + AyuGram settings mirror (Ghost Mode, Message Shot, window/notification/call/proxy prefs)

`app_state.dart` is a state container mirroring AyuGram's `ayu/ayu_settings.{h,cpp}`, Telegram-core `core_settings*.h`, and `main_domain.cpp`. Defaults, validate()/clamp ranges, ghost-mode resolution, lock toggles, message-shot theme logic, proxy-rotation timeouts and the 100/200 account limits were all checked 1:1 and **match** AyuGram. The issue below is broken/dead engine wiring — settings that look functional but never reach the backend.

Verified & closed (call audio devices): the audio-device vocabulary mismatch + stubbed `enumerateAudioDevices` finding is fixed and verified. `_loadSettings` (`settings_screen.dart:2361-2362`) and the Output/Input picker callbacks (`:2504-2518`, now routed through `AppState.setCallOutputDevice/setCallInputDevice`) use the engine's `output`/`input` vocabulary that `GetAudioDevices`/`SetCallAudioDevice` accept — live logs show `GetAudioDevices OK`×3 and `SetCallAudioDevice OK`, no `unknown device type`. `enumerateAudioDevices` (`cache_chats.go:2032+`) is no longer an empty stub: real pure-Go enumeration (PulseAudio/PipeWire `pactl` → ALSA `/proc/asound/{pcm,cards}` fallback → V4L2 `/sys/class/video4linux`); on the test box (no pactl) it returned 8 output / 1 input / 1 camera real devices. The pickers list real OS devices with a prepended `Default` sentinel, reflect the persisted selection, and a non-default pick persists to engine + prefs — confirmed in desktop (1024×768) and mobile (400×720).

Verified & closed (P2P call-privacy picker): the `phone_p2p`→`calls_p2p` vocabulary-mismatch finding is fixed and verified. `_CallsSettingsTab` now reads (`settings_screen.dart:2364`) and writes via `_setP2P` (`:2399`) the `'calls_p2p'` key that the engine's `privacyKeyMap` (`go/bridge/dispatch_engine.go:6965`) maps to `InputPrivacyKeyPhoneP2P` — matching AyuGram ground truth `Key::CallsPeer2Peer → MTP_inputPrivacyKeyPhoneP2P()` (`api_user_privacy.cpp:206`). No `phone_p2p` strings remain in `lib/`. Live logs show `GetPrivacySetting OK` / `SetPrivacySetting OK` with zero `unknown privacy key` errors (7/7 privacy calls OK, 0 Flutter exceptions). The "Use peer-to-peer with" radio reflects the real server value (showed `Nobody`, not the `?? 'contacts'` fallback); each selection persists round-trip (Everyone / My contacts / Nobody each fire `SetPrivacySetting OK`, and a fresh re-read returns the persisted value) — confirmed in desktop (1024×768) and mobile (400×720).

# audio_service — media player playback engine (port of Media::Player::Instance)

`audio_service.dart` is a faithful port of AyuGram's `media/player/media_player_instance.cpp`.
Verified correct and fully wired: shuffle/order/repeat-all advance math (`nextInPlaylist`,
`_shuffleNext`, `_ensureShuffleMove` ↔ `moveInPlaylist`/`ensureShuffleMove`), pause-on-call
(`_subscribeToCallState`/`_pauseForCall`/`_resumeAfterCallEnd` ↔ pauseOnCall/resumeOnCall),
notification ducking (`duckFor` ↔ mixer suppressAll, wired in `main.dart:577`), save/restore
position (music 20-min threshold, read-and-clear on play), playback-speed selection
(`_currentSpeed` ↔ LookupPlaybackSpeed), and music-listen reporting (3s min / 60s pause-timeout
match `kReportDurationSecondsMin`/the listen-tracker pause timer; `reportMusicListen` +
`refreshDocumentFileRef` resolve to real engine→Go `MessagesReportMusicListen`). Playlist
navigation callbacks and settings sync are wired in `main.dart:374-389` and
`chat_state.dart:3040`. No stubs, placeholders, or fake data.

Verified & closed (two behavioral deviations): (1) repeat-one is now gated with `_isSong && _repeatMode == AudioRepeatMode.one` (`audio_service.dart:597`), so a finished voice / round-video message advances via `next()` instead of re-seeking to 0 and looping forever — mirrors C++ `repeat()` returning `RepeatMode::None` for non-Song (`media_player_instance.cpp:1198-1202`) in the StoppedAtEnd handler (`:1300-1310`); consistent with the already-gated repeat-ALL path (`:276`). (2) `playVoice` now calls the engine `readMessageContents` on a fresh non-song play (`audio_service.dart:553`, after the same-message toggle early-return), marking incoming unread voice/round messages as listened — mirrors `Instance::play → markMediaRead` for voice/video (`media_player_instance.cpp:829-831`); placing it in the single `Player()`-creating method covers all 7 callers (chat_state/info_panel ×3/message_bubble ×3), and the server treats `messages.readMessageContents` as a no-op for outgoing/already-read messages. Build clean, app stable in desktop (1024×768) + mobile (400×720), no crashes.

# ayu_forward — AyuForward intelligent-forward engine (no-forwards bypass / resend-as-own)

Overall this is a faithful, heavily-documented port. Verified correct against C++ ground truth:
chunking predicate `isMessageRestricted` == `isAyuForwardNeeded(item)` (`ayu_forward.dart:141-147` ↔ `ayu_forward.cpp:226-231`),
full-resend gate `isFullAyuForwardNeeded` (`ayu_forward.dart:170-172` ↔ `ayu_forward.cpp:233-235`),
caller gate `needsIntelligentForward` (`ayu_forward.dart:337-352` ↔ `apiwrap.cpp:3487-3501` + `window_peer_menu.cpp:3248`),
chunk builder (`ayu_forward.dart:197-215` ↔ `ayu_forward.cpp:261-285`),
status/detail text (`ayu_forward.dart:55-76` ↔ `ayu_forward.cpp:54-97`),
`isForwarding` (`ayu_forward.dart:104-114` ↔ `ayu_forward.cpp:33-44`, the `<`→`<=` off-by-one is correctly compensated by the per-chunk index representation),
cancel (`ayu_forward.dart:78-82` ↔ `ayu_forward.cpp:46-52`, wired to the bar at `chat_view.dart:10965`).
Engine methods are real protobuf→Go calls (`engine_service.dart:3994-4048` → `engine/pending.go:465,492,875`); backend emits `sender_no_forwards`/`no_forwards` (`dispatch_engine.go:7260,7189`); field mappings match (`item->isAyuNoForwards()` is message-level per `history_item.cpp:2003`). The two issues below are behavioral-state deviations, not broken wiring.

Verified & closed (two progress-state deviations, both fixed against C++ ground truth): (1) Resend-as-own no longer oscillates `downloading`↔`sending` per album group. `intelligentForward` sets `phase=downloading` exactly ONCE per resend chunk (`ayu_forward.dart:273-278`) and the album-group loop only ever advances `phase: sending`/`sent` (`:329-332`), never flipping back to `downloading` — so the status shows "Loading media" once, then a continuous "Forwarding k/N", mirroring AyuGram's single `loadDocuments` Downloading phase followed by one send loop (`ayu_forward.cpp:356-359` then `363-441`). The atomic download+reupload per group is a documented engine divergence (comment `:296-305`) but the DISPLAYED phase sequence now matches. (2) Plain (non-restricted) forwards no longer show the AyuForward bar. `startNativeForward`/`finishNativeForward` are fully removed (no definitions/callers — only the explanatory comment at `:126-135`); the non-restricted dispatch branch loops `_engine.forwardMessage` directly and registers NO `ForwardProgress` (`chat_state.dart:1851-1862`), so `isForwarding(toChatId)` stays false (`ayu_forward.dart:104-114`) and the compose area is NOT replaced by `_ForwardProgressBar` (`chat_view.dart:5784-5787`) — matching AyuGram, whose `ApiWrap::forwardMessages` falls through both early returns to the normal Telegram batch path with no `ForwardState` (`apiwrap.cpp:3487-3501`); a `ForwardProgress` is created only on the `intelligentForward`/full-resend path (`chat_state.dart:1837`). Build clean (removed helpers leave no dangling refs), app stable in desktop (1024×768) + mobile (400×720), no crashes/exceptions in the forward path.

# chat_state — chat list + active chat + messages controller (ChangeNotifier)

Audited `dart/lib/state/chat_state.dart` (3249 lines) against AyuGram Desktop C++.
This is the controller/state layer, so the audit focused on backend wiring and
behavioral accuracy (not visual dimensions).

Verified correct (no findings): all numeric constants match AyuGram exactly —
message page sizes 30/50 (`history_widget.cpp:216-217`), saved-sublist
20/100/min-20/recent-5 (`data_saved_messages.cpp:30-35`), forum
20/500/recent-8 (`data_forum.cpp:40-44`), chat-history-stack 50
(`window_session_controller.cpp:138`). Recent-topic/recent-sublist ordering
(by last-message date desc, no pinned-first) matches `Forum::reorderLastTopics`
/ `SavedMessages::reorderLastSublists`. Saved-sublist pagination offset unit is
correct (`last_msg_time` is ms from Go `telegram.go:30250`, divided by 1000 for
offset_date). Message regex/shadowban filtering is correctly delegated to the
view layer (`chat_view.dart:3216`), not a wiring gap. No stubs, placeholders,
TODOs, mock data, or dead callbacks found — engine wiring is real throughout.

Verified & closed (jumpToMessage now loads a CENTERED window, fixed against C++ ground truth): `jumpToMessage` (`chat_state.dart:1757`) issues two parallel cache reads — `getMessages(beforeMs: ts+1, limit: 25)` → `[target, older…]` and `getMessages(afterMs: ts, limit: 25)` → `[newer…]` — and stitches them newest-first with msgId de-dup, so the newer-context half is present on the initial jump. Mirrors AyuGram `HistoryWidget::firstLoadMessages`' jump branch `offset = -kMessagesPerPage/2; offsetId = _showAtMsgId` with `kMessagesPerPage = 50` → half = 25 (`history_widget.cpp:4420-4423`, constant at `:217`). Two reads are required because the engine treats `beforeMs`/`afterMs` as mutually exclusive — one SQL query each, `afterMs` taking precedence (`cache_msgs.go:100-117`); the `+1` boundary keeps same-ms siblings in the older half (disjoint by timestamp). Runtime-verified live against a busy channel: clicking the pinned-message bar fired exactly TWO parallel `GetMessages` (one `beforeMs`, one `afterMs`) per jump in the engine log — the old one-sided code fired one — and produced a contiguous window centered on the target (window top = a msgId strictly newer than the target, target mid-list, older below, with a scroll-to-bottom badge showing the ~100 newer messages still ahead); under the old bug the target would have been index 0 with zero newer context. `_hasMoreMessagesDown`/`_jumpedUntil` are now set only when a full newer page (≥ 25) returns — a faithful port of AyuGram's at-present detection (a short newer half = present already in view). Verified in desktop (1024×768) + mobile (400×720); build clean, no crashes/exceptions in the jump path. ← `AyuGram/Telegram/SourceFiles/history/history_widget.cpp:4421`

# telegram_palette — Telegram Desktop color palette + accent colorizer (Dart port)

Scope: `telegram_palette.dart` is a data+algorithm file (no widgets/wiring). It ports
Telegram/AyuGram's `colors.palette` master + the 4 embedded theme palettes
(classic/day/tinted/night), plus the accent `colorize()` engine
(`style_palette_colorizer.cpp`), the `ignoreKeys`/`keepContrast` maps and the
contrast-enforcement pass (`ColorizerFrom` in `window_themes_embedded.cpp`).

What is CORRECT (verified, not findings — listed so the deviations below are in context):
- `colorize()` HSV piecewise sat/val formulas, hue wrap, HSL-lightness clamp match
  `style_palette_colorizer.cpp:24-58` + `window_themes_embedded.cpp:115-184`.
- `hueThreshold=15`, the full `ignoreKeys` set (peer colors, msgFile*, settingsIconBg*,
  premium*, boxTextFgGood/Error, callIconFg) passed raw, and all 11 `keepContrast`
  pairs (`_enforceContrast`/`fix`) map correctly incl. the `includeFileIcons` Night gate.
- `classicDay` is a byte-exact match to the resolved `colors.palette` default (0 deviations).
- Accent presets (`dayAccents`/`nightAccents`/`nightGreenAccents`) match `DefaultAccentColors`.

Root cause of the findings: `dayBlue`/`night`/`nightGreen` were baked from the exported
theme files, but for `key: #literal | fallback;` keys (`colors.palette`) that are ABSENT
from those exports — meaning at runtime `palette::compute()`
(`style_core_palette.cpp:158-180`) makes them INHERIT the theme-overridden `fallback` —
the Dart instead hardcoded the `colors.palette` literal default (a light-theme value) or
a wrong proxy. So in the dark/day themes these keys show the wrong color.

All 5 fallback-inheritance findings above VERIFIED & CLOSED (commit 3e702d2): every one of the
19 changed values is byte-exact against the AyuGram ground truth, computed by resolving each
`key: #literal | fallback;` against the extracted `night`/`night-green`/`day-blue.tdesktop-theme`
exports. mention→dialogsVerifiedIconBg (#6AB3F3 / #53EDDE); reaction→attentionButtonFg
(#EC3942 / #F57474) & poll→historyPeer5NameFg (#B48BF2 / #B383F3); archiveFg→dialogsNameFg
(#F5F5F5) & archiveFgOver→dialogsNameFgOver→windowBoldFgOver (#E9E9E9); dayBlue
emojiSubIconFgActive→windowBoldFg #222222, callBarBgMuted→dialogsUnreadBgMuted #BBBBBB,
callArrowFg→boxTextFgGood #4AB44A, callArrowMissedFg/historyCallArrowMissedInFg→boxTextFgError
#D84D4D, mainMenuCloudBg→activeButtonBgRipple #2095D0; spellUnderline→attentionButtonFg opaque
(#EC3942 / #F57474 / #D14E4E). Each target key confirmed ABSENT from its theme export (⇒ inherits).
Build clean; app launches & renders in desktop+mobile with no crash (light/classicDay default theme
untouched, as intended).

# theme — Material ThemeData bridge from TelegramPalette (input/scrollbar/tooltip/text defaults)

Scope: `theme.dart` maps `TelegramPalette` → Flutter `ThemeData`. It has no 1:1
AyuGram C++ analogue (Qt uses per-widget `.style` structs, not a global theme),
so the audit verifies that each dimensional/color value matches the corresponding
AyuGram `.style`/`.cpp` source. Most values are accurate; one structural deviation
in the global input-field default.

VERIFIED CORRECT (no action):
- Scrollbar thumb width 4px, radius 2px, color `scrollBarBg` — matches
  `widgets.style:822-826` (defaultScrollArea round 2px / width 10 / deltax 3 → thumb 4)
  and `scroll_area.cpp:166` (`width() - 2*deltax`).
- Tooltip bg/fg/border/padding/radius/font/wait — `tooltipBg`/`tooltipFg`/`tooltipBorderFg`,
  pad (5,2,5,2), radius 3 (`roundRadiusSmall`, basic.style:104), font 13 (`fsize`,
  basic.style:51), wait 1000ms — all match `widgets.style:1288-1293`, `tooltip.cpp:172,573`.
- Input field resting/focused border colors + widths (`inputBorderFg` 1px / `activeLineFg` 2px)
  match `widgets.style:1058-1063`.
- `dark`/`light` getters are exercised by test/ (not dead code).

Both input-field findings VERIFIED & CLOSED (commit 4ea812c): the global input
default now uses `UnderlineInputBorder` for both resting (1px `inputBorderFg`) and
focused (2px `activeLineFg`) borders — matching AyuGram `paintFlatSurrounding`
(`input_field.cpp:2389` `fillRect(0, height()-border, width(), border, borderFg)`,
bottom underline only; `defaultInputField.borderRadius: 0px`, `widgets.style:1064`)
— and `contentPadding: EdgeInsets.fromLTRB(0, 28, 0, 4)` matches
`defaultInputField.textMargins: margins(0px, 28px, 0px, 4px)` (`widgets.style:1045`)
exactly. Confirmed visually in the Add-Quick-Reply dialog (default-decoration
`TextField`s) in BOTH desktop (1024×768) and mobile (400×720): every unstyled field
renders as a flat bottom-underline field — not a box — with placeholder text flush
to the left edge (zero horizontal inset). Build clean; app launches, navigates 5+
screens and the dialog, and processes live events with no crash.

# theme_file — Telegram `.tdesktop-theme`/`.tdesktop-palette` parser, exporter & disk cache

Audited `theme_file.dart` (1865 lines) against AyuGram's `window_theme.cpp`,
`window_theme_editor.cpp`, `style_core_palette.cpp`, `parse_helper.cpp`,
`zlib_help.h`, and `colors.palette`.

Overall the file is a careful, near-1:1 replication: all 580 real Telegram
palette keys are present in `paletteToMap` (zero missing); the size limits
(5 MB file / 25 M-pixel bg / 1 MB scheme / 4 MB bg-bytes) match
`kThemeFileSizeLimit`/`kBackgroundSizeLimit`/`kThemeSchemeSizeLimit`/`kThemeBackgroundSizeLimit`;
the in-order reference resolution (`unsupported` map, `KeyNotFound`/`ValueNotFound`
semantics, last-value-wins on duplicate), the cloud-meta read/write
(`WriteCloudToText`/`ReadCloudFromText`, uint64 unsigned formatting), the
background priority order (background.jpg > .png > tiled.jpg > .png), the
anti-zip-bomb uncompressed-size check, and the CRC32 cache scheme
(`palette::Checksum()` + `base::crc32(content)`, validate both) are all faithful.
The public API is wired (`parseThemeFile`/`exportThemeFile`→`theme_editor.dart`,
cache fns→`app_state.dart`). No stubs/TODOs/placeholders/fake data.

All three findings VERIFIED & CLOSED (commit b21a11f). Confirmed against AyuGram
ground truth + a focused parser test exercising the real `parsePaletteText`/
`parseThemeFile` code paths (15/15 pass), plus a runtime launch in desktop+mobile
with no crash/theme errors:
- [CRITICAL] `finalize()` cascade now implemented (Pass 3 over `_paletteFallbacks`
  in colors.palette declaration order, mirroring `compute()` style_core_palette.cpp:158-180
  run via finalize() window_theme.cpp:368). A theme setting only `windowBg:#000000;`
  now cascades menuBg & msgInBg (colors.palette:53/:345 `:windowBg`) to black, and
  the chain is transitive (`windowBgOver→menuBgOver→botKbBg`); explicit colors still
  win and an unset-fallback key keeps its own default — verified by test.
- [MAJOR] Line-based tokenizer replaced by a streaming, newline-agnostic port of
  `readNameAndValue`/`ReadPaletteValues` (window_theme.cpp:122-164,1514-1537) with a
  faithful `_stripComments`. Cross-line `windowBg:\n#ffffff;` and multi-pair
  `windowBg:#123456; windowFg:#abcdef;` both parse; comments/whitespace tolerated;
  structural errors (missing `;`/`:`, empty value) still hard-reject — parity with AyuGram.
- [MAJOR] Background validation now format-agnostic: `_isValidBackgroundImage`
  decodes via `package:image` (≡ Images::Read, window_theme.cpp:328-343) instead of
  gating on JPEG/PNG magic bytes. BMP/TGA stored as `background.png` are accepted;
  undecodable bytes still reject the theme.

# theme_name_generator — Telegram Desktop theme-name generator (redmean nearest-color + random adjective/subjective)

Port is near-perfect: the redmean distance formula (incl. `>>8` truncations, `4*g*g`, `512+rMean`, `767-rMean`), `rMean` (`(r+c.r)>>1` ≡ C++ `(r1+r2)/2`), the 50/50 adjective-prefix/subjective-suffix branch, and all three data tables were verified 1:1 — 99 colors (hex→RGB all correct), 107 adjectives, 81 subjectives, with matching order including the non-alphabetical quirks ("Flash","Fire"; "Shine","Shadow","Shimmer"). Wiring is correct: `generateThemeName(widget.palette.windowActiveTextFg)` (theme_editor.dart:1317) matches AyuGram's `GenerateName(collected.accent)` where `collected.accent = st::windowActiveTextFg->c` (window_theme_editor_box.cpp:773,790). The one genuine algorithmic divergence is now VERIFIED & CLOSED (commit 801ed7f),
confirmed against AyuGram ground truth + a focused test that drives the real
`generateThemeName` against an independent C++-data reference (flat_map +
min_element semantics), plus a desktop+mobile launch with no crash/theme errors:

- [MAJOR] Nearest-color tie-break now matches `base::flat_map` + `ranges::min_element`.
  `generateThemeName` scans a key-sorted view (`_sortedColors`, ascending packed-RGB
  key) with a strict `<`, so equidistant accents resolve to the LOWEST-key entry —
  identical to AyuGram (window_themes_generate_name.cpp:16,345). Verified: the Dart
  `_colors` table is a 1:1 transcription of C++ `kColors` (99/99 entries, all keys
  distinct, key-sorted view == flat_map order); the real `generateThemeName` == the
  C++ reference across the full palette + a 1728-accent grid; the two named exact
  ties resolve correctly (rgb(42,81,186) Azure→Sapphire, rgb(3,96,93) Lagoon→Teal);
  a 140608-accent sweep finds 12 decl-vs-key divergences, all genuine ties won by
  the lower key. `_colors` stays in declaration order for 1:1 source verification.
  — `theme_name_generator.dart:11-43,61-62`

# theme_preview — Telegram Desktop theme-preview image (dialogs + chat mock)

`theme_preview.dart` is a faithful `CustomPainter` port of AyuGram's `Window::Theme::Generator` (`window_theme_preview.cpp`), which renders a static 903×584 preview of the dialogs list + chat view for a given palette. It is a *static* renderer (the C++ original is also a one-shot `QImage Generator::generate()`), so there is **no backend wiring to check** — the hardcoded rows/bubbles/waveform are correct because they mirror AyuGram's `generateData()` 1:1. Verified faithful: canvas 903×584 (`media_view.style:423`), dialogs width 312 (`media_view.style:445`), row height 62 / photoSize 46 / nameLeft 68 / nameTop 10 / textTop 34 (`dialogs.style:89-101`), top-bar 54 / compose 46, dialog-list `startY=54` (= 7+40+7), the 8 rows' names/peerIndex/unread/muted/pinned/status/group flags, colorized-preview link color = `dialogsTextFgService` (`dialogs.style:170`), avatar gradient + `colorIndexToPalette = [0,7,4,1,6,3,5]` (= `chat_style.cpp:1205` `map[]`), waveform data (67 samples, waveactive 33), default wallpaper colors `[DBDDBB,6BA587,D5D88D,88B884]` (`data_wall_paper.cpp:710-715`), themeimage.jpg (654×395, identical bytes), audio file layout, bubble radius 16. No placeholders, stubs, TODOs, fake feedback, empty callbacks, or unbounded lists. `shouldRepaint` is identity-gated (no per-frame rebuilds); widget is wired into `theme_editor.dart:811`.

## Checked and intentionally NOT flagged (cosmetic / within tolerance)

- Bubble **tails** rendered as 4px rounded corners instead of `Corner::Tail` shapes, and attached/`Small` corners 4px vs AyuGram's 6px (`bubbleRadiusSmall: roundRadiusLarge=6`, `basic.style:103`). Cosmetic at preview scale, and AyuGram itself ships a `removeMessageTail()` option (`message_bubble.cpp:50-55`) that converts tails to rounded corners — so a tailless appearance is a supported AyuGram rendering. — `theme_preview.dart:507-514`
- Filter "Search" placeholder uses `windowSubTextFg` vs AyuGram's `placeholderFg` (`dialogs.style:321`) — both muted greys, divergence < 3% in bundled themes. — `theme_preview.dart:144`
- `msgWaveformMin` 2 vs 3, `msgWaveformMax` 16 vs 17 (`chat.style:559-560`); reply-bar opacity 1.0/0.1 vs `kDefaultOutline1Opacity 0.9` / `kDefaultBgOpacity 0.12`; service-bubble vPad 5 vs 3/4; left separator at x=311 vs 312 — all ≤2px / negligible.
- Waveform downsampling is point-sampled rather than AyuGram's max-over-range (`window_theme_preview.cpp:951-977`); active/inactive split matches (compares data index to waveactive, per the in-code comment). Visually equivalent.

# theme_tokens — AyuGram `.style` value mapping (TgTokens design tokens)

Scope: `theme_tokens.dart` is a pure design-token reference — `TgTokens` mirrors
AyuGram Desktop `.style` literals into Dart constants. No widgets, callbacks,
engine calls, or state — so the audit is value-fidelity vs the AyuGram source.

Verification result: ~70 numeric/size/duration/margin tokens were cross-checked
against the actual AyuGram `.style` files and **all but one match exactly**, with
line-accurate source citations already present in the file's comments
(e.g. `widgets.style:1070`, `info.style:527`, `settings.style:205` all verified
correct). Both flagged issues are now VERIFIED & CLOSED (commit e7fa47a) —
confirmed 1:1 against AyuGram ground truth (window.style, boxes.style,
widgets.style, multi_select.cpp, ayu_userpic.cpp) plus a clean `flutter analyze`
(no issues) and a desktop build + launch with no crash. These are dead reference
constants (unreferenced in `lib/`), so the audit is pure value-fidelity.

- [MAJOR] `unresolvedTokens` false-positives FIXED. The 9 tokens that live in the
  `.style` files this table already reads are now resolved literals with
  line-accurate citations, each matching AyuGram exactly: `themeEditorSampleSize`
  size(90,51), `themeEditorMargin` margins(17,10,17,10), `themeEditorDescriptionSkip`
  10, `themeEditorNameFont` 15px semibold (window.style:167-170);
  `localStorageRowHeight` 50, `localStorageRowPadding` margins(22,5,20,5)
  (boxes.style:202-203); `passcodeHeaderFont` 19px, `passcodeHeaderHeight` 80,
  `passcodePadding` margins(0,0,0,5) (boxes.style:290-291,299). The 16 remaining
  `unresolvedTokens` were re-checked and are genuinely absent as scalar `.style`
  literals (`localStorageLimitSlider` is a non-scalar MediaSlider object,
  boxes.style:223); §56.13 rewritten to justify each. — `theme_tokens.dart:65-118,212-222`
- [MAJOR] `defaultMultiSelectRadius` 8 → 16 FIXED. Pill radius is
  `min(ComputeRadius(32), 32/2)` (multi_select.cpp:184); with default
  `avatarCorners = 23 == kMaxAvatarCorners` (ayu_settings.h:697, ayu_ui_settings.h:11)
  `ComputeRadius(32)` returns `32/2 = 16` (ayu_userpic.cpp:35), so `min(16,16) = 16`
  — a full pill, not a rounded-rect. Verified against ground truth. — `theme_tokens.dart:159`

## Notes (not flagged — adaptation / out of CRITICAL-MAJOR scope)

- `defaultRoundShadowBlur = 8` / `defaultRoundShadowOffset = Offset(0, 2)` (lines 133-134) are Flutter `BoxShadow` approximations of AyuGram's icon-based 9-slice glow `roundShadowRadius8px` (`widgets.style:931-944`), which is symmetric (`extend: margins(10px,10px,10px,10px)`) with no blur/offset concept. The downward `(0,2)` offset is invented (the source glow is centered), but this is a deliberate cross-framework adaptation, both tokens are unused in `lib/`, and the deviation is cosmetic — not reported as a finding.
- Everything else verified exact: basic.style primitives (fsize, fonts, radial, durations), layers.style box chrome (incl. `defaultBox.buttonPadding/buttonHeight/margin`), info.style topbar + info widths, dialogs.style row/stories geometry, chat_helpers.style, settings.style, and all §56.11 derived values.

# wallpaper — chat-background rendering (solid/gradient/pattern/image), gradient math, dithering

Overall this is a faithful, well-wired port. Verified 1:1 against AyuGram:
`ColorsFromString`/`ColorFromString`/`StringFromColors` (data_wall_paper.cpp:96-173),
`withUrlParams`/`collectShareParams`/`gradientRotation` (data_wall_paper.cpp:260-421),
`ConstructDefault` default colors (data_wall_paper.cpp:707-718), the complex gradient
(`GenerateSmallComplexGradient`, image_prepare.cpp:172-291), linear 8-direction gradient
(`GenerateLinearGradient`, image_prepare.cpp:916-966), dither tiers + shift math
(`DitherImage`/`DitherGeneric`, image_prepare.cpp:880-897/100-170), complex-gradient
rotation accumulator (`ComputeRealRotation`/`ComputeRealProgress`/`kAddRotationDoubled`,
chat_theme.cpp:40-57/646), pattern tiling + odd-column centering (chat_theme.cpp:172-185),
`IsPatternInverted` threshold + `InvertPatternImage` alpha→white matrix (chat_theme.cpp:925-930/1156-1171),
`ThemeAdjustedColor` (chat_theme.cpp:932-939), and `PreprocessBackgroundImage` crop/scale
(chat_theme.cpp:941-966). Rotation trigger is correctly gated on outgoing-message reveal
(chat_view.dart:909 ← history_widget.cpp:4095/7717). Wallpaper data flows from the real
engine document download (message_bubble.dart:9419 `downloadWallpaperDocument`). No
placeholders, stubs, empty callbacks, mock data, or broken wiring found.

# advanced_settings_screen — Advanced settings page (§14.7): update, data/storage, auto-download, window title/close, system integration, performance, spellchecker, screen reader, export + Proxies/LocalStorage/PowerSaving/AutoDownload/Experimental dialogs

Overall this is a high-fidelity port. Section order, the auto-download size-limit curve (`SizeLimitByIndex`), local-storage limit ladders + 100 MB floor + 6 cache tags, the experimental-flag list (all 29 in exact order), proxy link parsing / MTProto secret validation / public-link generation / rotation timeouts, and the engine wiring (`GetCacheSizesByTag`, `ClearCacheByTag`, `CheckProxy`, `SetExperimentalFlag`, `SetLocalStorageLimits`, `recentDownloads`) were all verified against AyuGram and the Go engine and match. Three MAJOR behavioral deviations were found and fixed (verified in desktop + mobile): (1) the Power Saving box no longer clobbers/persists the user's per-feature flags when the OS power-saver is detected — `_applyAutoFlags()` removed and save gated on `!_overlayActive`, matching `settings_power_saving.cpp:121-123`; (2) the "Add proxy" dialog now defaults a brand-new proxy to MTPROTO with radio order MTPROTO/SOCKS5/HTTP + Secret field, matching `connection_box.cpp:1468-1472,1582-1584`; (3) the Spellchecker `isSystem` predicate now matches `IsSystemSpellchecker()` (true on Windows/macOS/Linux), `settings_advanced.cpp:882` + `spellcheck_win.cpp:335-339`.

# auth_screen — Telegram intro/auth flow (phone, code, 2FA, email, signup, QR)

Verified against AyuGram intro sources (`intro_code.cpp`, `intro_password_check.cpp`,
`intro_signup.cpp`, `intro_email.cpp`, `lang_keys.cpp`) and `Resources/langs/lang.strings`;
all 7 MAJOR deviations fixed and confirmed (commit da6ba9e7). (1) Signup name-field order
now keyed to name *ordering* via `LangPack.firstNameGoesSecond` — a 1:1 port of
`langFirstNameGoesSecond()` (sentinel chars 0x01/0x02 + `indexOf` compare, `lang_keys.cpp:59-69`),
replacing the wrong RTL `Directionality` probe; field controllers + `lng_signup_firstname/lastname`
labels invert on it (`intro_signup.cpp:37,84-89`). (2) Code/OTP step title shows the formatted
phone (`_otpPhone` ← `Ui::FormatPhone`), Fragment title only for Fragment delivery
(`intro_code.cpp:52-57`) — **visually confirmed desktop+mobile**: title rendered "+98 920 405 9095".
(3) Code link = `lng_code_no_telegram` "Send code via SMS" (`intro_code.cpp:35,73`) — **visually
confirmed desktop+mobile**. (4) 2FA title/desc = `lng_signin_title`/`lng_signin_desc`
(`intro_password_check.cpp:55,358`). (5) Signup title/desc = `lng_signup_title`/`lng_signup_desc`
(`intro_signup.cpp:53-54`). (6) Email title/about = `lng_intro_email_setup_title`/
`lng_settings_cloud_login_email_about` (`intro_email.cpp:45,53`). (7) Fragment instruction =
`lng_intro_fragment_about` interpolating the phone via `trf` (`intro_code.cpp:96-100`). All 12
embedded baseline strings match `lang.strings` exactly; the `lang.tr/trf` pipeline is proven
end-to-end (phone + code steps render localized values, no raw keys, no crashes).

# ayu_appearance_page — AyuGram Appearance settings (app icon, avatar corners, mono font, folder/tray/drawer elements)

Audited `dart/lib/ui/ayu_appearance_page.dart` against AyuGram's `settings_appearance.cpp`
and the components it builds (`icon_picker.cpp`, `avatar_corners_preview.cpp`,
`font_selector.cpp`). Section structure, ordering, the app-icon picker, the avatar-corners
slider/preview, the mono-font selector, and the tray/drawer toggle lists all match and are
wired to real `AppState` setters that are consumed by real rendering code. The restart-prompt
dialogs match `ShowRestartPrompt`. Three toggles were previously non-functional (flipped &
persisted but unconsumed); all three are now wired to their rendering consumers and verified
1:1 against AyuGram — `disableCustomBackgrounds` gates the per-chat `WallpaperProvider`
(`chat_view.dart:6082` ↔ `section_widget.cpp:544-550`), `singleCornerRadius` drives the forum
avatar shape (`chat_list_row.dart:1114` ↔ `dialogs_row.cpp:472-478`, forum-default 0.3·size vs
`ComputeRadiusF` corners/23·size/2), and `hideNotificationBadge` forces the OS tray/taskbar
unread count + muted to 0 (`main.dart:819` ↔ `main_window_win.cpp:638-642`/`tray_win.cpp:145`).

## Verified correct (no action needed)

- App-icon picker: 12 icons match AyuGram's list 1:1 (`icon_picker.cpp:24-37`); all 12 assets exist
  under `assets/icons/ayu/` and are registered in `pubspec.yaml`; `kColumns=4`, 64px icon, 68px
  selected box (64+2·2), 12px rounding all match `ayu_styles.style`; 200ms easeOutCubic cross-fade
  matches `icon_picker.cpp:158-167`; click wires to `setAppIcon` + native `updateAppIcon` channel
  (`linux/my_application.cc`) mirroring `applyIcon()`.
- Avatar corners: `kMax=23` matches `kMaxAvatarCorners`; 24 slider steps match `.steps = kMax+1`;
  `radius = photoSize/2 · corners/23` matches `ComputeRadiusF`; SQUARE/CIRCLE/number badge matches
  `mapRadius`; preview downloads the real @AyuGramReleases userpic via the engine with an
  EmptyUserpic fallback (whose shape correctly follows `paintCircle → AyuUserpic::PaintShape`);
  62px row height / 46px photo / 22px indent match `defaultDialogRow`; tap opens the channel
  (resolves on-demand if needed) matching `mouseReleaseEvent`. `avatarCorners` is consumed across
  5 UI files.
- Mono-font selector: enumerates real system fonts (fc-list/osascript/PowerShell/mobile dirs),
  prefix-word filtering matches `Rows::filter`, arrow/page keyboard nav present, Save/Reset wire to
  `setMonoFont('')`/value with restart prompt matching the OK/Reset buttons; `monoFont` is applied
  as the code/pre `fontFamily` in `message_bubble.dart:7354,7373`.
- All other toggles are wired to real consumers: `materialSwitches` (ayu_toggle + pages),
  `hidePremiumStatuses` (4 files), `hideNotificationCounters`/`hideAllChatsFolder` (filter_column,
  chat_list_panel), tray toggles (`main.dart`), all 12 drawer toggles (`hamburger_drawer.dart`,
  order/labels/icons match `BuildDrawerElements`).
- Restart dialogs match `ShowRestartPrompt` (Restart Now → relaunch, Restart Later → dismiss).

# ayu_chats_page — AyuGram Chats settings page (settings_chats.cpp port)

Overall this is a faithful, fully-wired port. All 9 AyuGram build sections are
present in the correct order, and all 31 settings call real `AppState` setters
(no stubs, no empty callbacks, no fake/unwired controls). The bubble-radius live
preview, restart prompt, collapsible "Hide Reactions" ANY-semantics, semi-
transparent opacity (0.7), and the demo message-preview content all match the
AyuGram ground truth. All 3 MAJOR deviations were found and fixed (verified in
desktop, commit 1b0a65b9; all three are width-independent — radius math, a
centered modal, and single-line rows — with no responsive variants): (1) the
bubble-radius preview tail corner now uses `MapBubbleRadius(sliderValue,
st::bubbleRadiusSmall)` with `bubbleRadiusSmall = roundRadiusLarge = 6px`
(`chat_style_radius.cpp:39-48`, `chat.style:434`, `basic.style:103`) — 6px at the
default radius (16) and scaling 6→3→2 across the slider — replacing the
hardcoded, non-scaling `4.0`; the live preview was confirmed to re-render and
scale its corners as the slider moves. (2) The edit-mark "Save" button now calls
`save()` directly (so an empty mark CAN be cleared) while only Enter/`submit()`
validates, matching `edit_mark_box.cpp:50-54,73-80` — confirmed: clearing the
Deleted mark via Save removed it from the preview, while Enter on an empty field
kept the box open. (3) The ~15 fabricated per-toggle subtitles were removed so
every toggle row is single-line, matching AyuGram's subtitle-less
`addSettingToggle` (`settings_chats.cpp`, `settings_ayu_utils.cpp:641-665`).

# ayu_filters_page — AyuGram Regex Filters settings page (toggles, shared/shadow-ban/per-dialog lists, regex edit box, import/export)

Overall the port is faithful and fully wired: every toggle calls `filterEngine.rebuildCache()` + `notifyListeners()` + persist (the equivalent of AyuGram's `FiltersCacheController::rebuildCache()` + `fireUpdate()`), add/edit/delete/toggle filter, exclusions, shadow-ban add/remove, clear-all, select-chat, and import/export (clipboard + URL/dpaste) all reach the real engine. No placeholders, stubs, empty callbacks, mock data, or "coming soon" feedback found. All 3 MAJOR deviations were found and fixed (commit 646850ca), and verified in
both desktop (1024×768) and mobile (400×720, sized via the compositor since the
GTK window-resize IPC is a no-op on Wayland) — the `_AyuFiltersListScreen`
app-bar `actions` carry no responsive/`MediaQuery` branches, so the icons render
identically at any width. The per-dialog exclude flow now mirrors AyuGram's
`AyuFiltersList` top bar (`info_wrap_widget.cpp:467-514`): (1)+(2) the inline
`_AddExclusionButton` list row was removed entirely and Exclude is now a
dedicated top-bar `IconButton` (`Icons.label_off_outlined` ← `st::filtersExcludeIcon`
/ `menu/tag_remove`) built whenever `mode == perDialog && showExclude` (the
per-dialog main view), independent of the body's empty-state early return — so it
stays reachable on a fresh dialog with no filters (confirmed: a group opened via
the top-menu "Select Chat" shows two top-bar icons, Add + Exclude, above an empty
"No filters." body, in both desktop and mobile). (3) the Add (`+`) icon is now
built unconditionally for every non-shadow-ban screen (plain `else` branch, no
longer gated by `mode != perDialog || showExclude`), including the pick-exclude
sub-screen, where it opens `_RegexEditBox` scoped to the current `dialogId`
(← `RegexEditBox(nullptr, nullptr, controller->dialogId)`) — confirmed the
pick-exclude screen now shows a single Add icon that opens the "Add Filter" box.
Regression-checked: Shared and Shadow-ban screens show only the Add icon (no
Exclude leak), and the Shadow-ban Add opens the Select-Chat picker. No crashes.

# ayu_general_page — AyuGram General settings page (Translate / QoL / Webview / Confirmations)

Audited `dart/lib/ui/ayu_general_page.dart` against `ayu/ui/settings/settings_general.cpp`
(`BuildQoLToggles` / `BuildTranslator` / `BuildShowPeerId`) and its helpers in
`settings_ayu_utils.cpp`.

This is an almost 1:1 port. Section order, dividers, subsection titles, collapsible
`toggledWhenAll` flags, restart-prompt-on-toggle for Disable Stories & Filter Zalgo,
the beta badges, and Show Peer ID options all match the C++. Every control is wired to
a real `AppState` setter that persists via `_saveWindowPrefs()`, and every setting is
actually consumed downstream (disableStories→chat_list_panel, similarChannels→info_panel,
improveLinkPreviews/showMessageSeconds/confirmations/translationProvider→chat_view,
showPeerId→info_panel, spoof/increaseWebview→web_app_panel, disableNotifyDelay→main.dart,
filterZalgo→safe_string global). No stubs, no empty callbacks, no mock data.

One real behavioral deviation was found and fixed (commit 26a115b7), then verified:

The Native translation provider option is now gated on availability instead of being shown
unconditionally on any desktop platform. The choose-button's `items` map adds the native entry
only when `nativeProviderName != null && appState.nativeTranslateAvailable`
(`ayu_general_page.dart:48-49`), mirroring AyuGram's `Platform::IsTranslateProviderAvailable()`
gate (`settings_general.cpp:46-60`; Linux: `!Command().isEmpty()` = `crow`/`org.kde.CrowTranslate`
on PATH, `translate_provider_linux.cpp:86-88`). Verified end-to-end: on this Linux host with
neither `crow` nor `org.kde.CrowTranslate` on PATH, the Translation Provider dialog shows only
Telegram/Google/Yandex — no "Linux" entry — in both desktop (1024×768) and mobile (400×720)
modes. Positive control: dropping a fake `crow` executable on PATH and relaunching makes the
"Linux" option appear, confirming the gate is bidirectional and reads the same two executables
as the setter clamp (`app_state.dart:2051,2083-2092`). No crashes.

# ayu_section_builder — AyuGram settings section builder (toggles, sliders, choose buttons, collapsible toggles, dividers)

Most of this file is a faithful 1:1 port: dimensions, padding, the slider's
`setPseudoDiscrete` index math, the collapsible master-toggle/lock logic, the
checked/total count display, the beta-badge positioning, and the divider/skip
metrics all match the AyuGram source after verification against
`ayu_builder.cpp`, `settings_ayu_utils.cpp`, `settings_common.cpp`,
`continuous_sliders.h`, and the relevant `.style` files. The empty
`onChanged: (_) {}` at line 880 is intentional (the toggle is `IgnorePointer`-
wrapped and taps are handled by the parent `GestureDetector`), not a stub. All 3
MAJOR `_AyuChooseButton`/`_SingleChoiceBox` deviations were found and fixed
(commit 5df1a89a) and verified live in both desktop (1024×768) and mobile
(400×720) on the real AyuGram → Chats → "Context Menu Elements" choose buttons:

- [MAJOR] Choose-button dialog title FIXED & VERIFIED. `addChooseButton` now
  takes a `boxTitle` distinct from the row `label`, and `_AyuChooseButton`'s
  `_showChoiceDialog` titles the box `boxTitle ?? label` (`ayu_section_builder.dart:108,661`)
  — mirroring AyuGram's `AddChooseButton(..., boxTitle, ...)` → `SingleChoiceBox{.title = boxTitle}`
  (`settings_ayu_utils.cpp:499,530`). The context-menu rows pass the shared generic
  title `'Choose when to show the item'` (= `ayu_SettingsContextMenuTitle`,
  `lang.strings:8109`, used by all 7 buttons at `settings_chats.cpp:310-365`)
  (`ayu_chats_page.dart:248`). Confirmed: tapping "Reactions Panel" opens a dialog
  titled "Choose when to show the item", NOT "Reactions Panel" — desktop + mobile.
  ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_ayu_utils.cpp:528`
- [MAJOR] Radio marker FIXED & VERIFIED. `_SingleChoiceBox` now builds each option
  as a real `Radio<bool>` (activeColor `windowBgActive`) on the LEFT with the label
  `Expanded` to its right (`ayu_section_builder.dart:710-727`) — matching AyuGram's
  `Ui::Radiobutton`. Confirmed via 4× zoom: the selected option renders a blue ring
  with a FILLED inner dot on the left, unselected options are hollow rings, text to
  the right — not a hollow right-side ring. Desktop + mobile.
  ← `AyuGram/Telegram/SourceFiles/ui/boxes/single_choice_box.cpp:34`
- [MAJOR] Bottom button label FIXED & VERIFIED. The box's action button now reads
  "OK" (`ayu_section_builder.dart:740`) = `tr::lng_box_ok()` ("OK", `lang.strings:125`),
  not "Cancel". Confirmed: button labeled "OK" closes the box; selection auto-applies
  on option tap (live Hidden→Extended Menu→Hidden round-trip, row right-label tracks
  the value). Desktop + mobile. No crashes/exceptions in the choose-button/dialog path.
  ← `AyuGram/Telegram/SourceFiles/ui/boxes/single_choice_box.cpp:22`

# chat_list_panel — left panel (search, folder tabs, stories, top peers, chat list, forum/saved sublists)

Audited dart/lib/ui/chat_list_panel.dart (6984 lines) against AyuGram Desktop C++.
No placeholders/stubs/fake-data/empty-callbacks found — search, context menus, drag,
forum, saved-sublists and search-tabs are all wired to ChatState/EngineService/AppState.
Most dimensions are faithful ports (verified below). The findings are real behavioral /
dimensional / performance deviations from the C++ ground truth.

Verified MATCHING (no action — recorded so they aren't re-flagged): stories small/full
geometry 35/77 height, 21/42 photo, 16 shift, lines 3px/4px/2px→1.5/2.0/1.0, readOpacity
0.6 (`dialogs.style:716-744,827`); stories overscroll expand/collapse at 0.72/0.68 ratios
is wired in `_onChatListScroll` (`chat_list_panel.dart:271-285`); top-peers avatar 46 /
item 66 / strip 77 / expand toggle (`dialogs.style:746-748`, `top_peers_strip.cpp:90-120`);
reorder/drag thresholds 30/30/75 (`dialogs_inner_widget.cpp:106-108`); forum topic row
54px / pad 8,7,10,7 / icon 20 / nameLeft 39 / textTop 29 (`dialogs.style:666-673`); recent
contacts row 56 / photo 42 / name(64,9) / status(64,30) (`dialogs.style:759-764`); search
tabs 33h / barTop30 / barStroke6 / barRadius2 / 150ms (`dialogs.style:799-817`);
searchIn height 38 / photo 28 (`dialogs.style:518-519`); IsHashOrCashtag &
searchFromPeer group-gating (`chat_search_in.cpp:237`, `dialogs_widget.cpp:4459`).

# chat_list_row — chat-list row, swipe quick-actions, stories ring, special userpics, forum row

Audited `dart/lib/ui/chat_list_row.dart` against AyuGram Desktop (`dialogs.style`,
`dialogs_layout.cpp`, `dialogs_row.cpp`, `dialogs_quick_action.cpp`,
`dialogs_topics_view.cpp`, `ui/controls/swipe_handler.cpp`, `ui/text/format_values.cpp`).

Overall this file is a faithful, fully-wired port. Verified matching against the C++ authority:
dimensions (62px row, 46px photo, 68px nameLeft, 10px nameTop, 80px forum row, 19px/5px/12px-bold
unread badge, 13px fonts), badge paint order (unread → mention/reaction → poll, right-to-left),
send-state icon placement + state mapping, `ChatTypeIcon` selection (bot/channel/forum/group, no
icon for DMs), stories-ring read/unread line widths (2.0/1.0) and live-stream red ring, swipe
constants (50px threshold, 1.5 max ratio, 0.2 slow, 150ms commit, haptic at ratio≥1), quick-action
label/bg-color/Lottie-name resolution (all 10 swipe Lottie assets present + registered in pubspec),
and the draft-vs-unread gating (`unreadCount == 0` correctly mirrors AyuGram's
`(!item || !badgesState.unread)` guard). Rows are instantiated with real engine state in
`chat_list_panel.dart` (`recentTopicsFor`, `typingUserFor`, `openTopic`, `_performSwipeAction`).
No stubs, empty callbacks, mock data, or unwired elements found.

# chat_settings_screen — Telegram Desktop "Chat Settings" page (themes, accent, peer color, fonts, cloud themes, wallpaper, quick action, stickers/emoji, messages, sensitive content, archive)

Backend wiring is solid across the file — every engine call is real (`getSelfColorAndChannel`, `getContentSettings`/`setContentSettings`, `getCloudThemes`, `getWallpapers`, `downloadWallpaperDocument`, `getPeerColors`, `updateNameColor`, `installCloudTheme`/`deleteCloudTheme`, `getInstalledStickerPacks`/`getInstalledEmojiSets`, `install`/`uninstall`/`reorder`/`searchStickerSets`, `getAvailableReactions`/`setDefaultReaction`, `getArchiveSettings`/`setArchiveSettings`). No empty callbacks, no "coming soon" stubs, no fake/mock data. The cloud-theme context menu (Share→addtheme link, Edit when owner+active, Delete with confirm) matches AyuGram 1:1. Section ordering matches `BuildChatSectionContent`. All 13 label/color/title deviations verified fixed & closed against AyuGram ground truth (theme names Day/Tinted/Night + night-card bubble colors `#5ca7d4`/`#6b808d` & `#6b808d`/`#6b808d`, Themes/Theme-settings/Chat-wallpaper subsection titles, Messages header with no double-click sub-header, "Send with Enter"/"Send with Ctrl+Enter", "Reply button on messages"/"Reaction button on messages", "Show 18+ Content" toggle, "Change folder" quick action + folder icon + about text, "Custom themes"/"Show all themes", "Manage sticker sets"/"Choose emoji set") — desktop 1024x768 + mobile 400x720, no overflow/exceptions.

# chat_switch_overlay — Ctrl+Tab alt-tab-style chat switcher overlay

Overall a faithful, fully-wired port of AyuGram's `ChatSwitchProcess`. Data
source is real (`chatState.collectChatOpenHistory()` ↔
`recentPeers().collectChatOpenHistory()`), navigation key arithmetic matches
`process()` exactly (Tab/Backtab/Left/Right/Up/Down/Q, Escape, Enter,
modifier-release confirm), layout math (canPerRow/canRows/shownRows) is a
line-for-line port of `layout()`, and every dimension matches `window.style`
(cell 72×104, userpic 56, top 8, name skip 6, select line 3, margin 16, padding
12, radius 6, font 11px, anim 150ms = `slideWrapDuration`). No placeholders or
stubs. Both behavioral deviations verified fixed & closed against AyuGram ground truth: (1) Q-removing the currently-viewed chat now also closes the open conversation — `shell.dart` onRemove drops the id from open-history and then calls `chatState.closeChat()` when the removed chat is the active one, mirroring `Key_Q` → `CloseInWindows(thread)` → `clearSectionStack` on the window whose `activeChatCurrent().thread() == thread` (`window_chat_switch_process.cpp:275-282`, `:61-82`); verified activeChat→null + chat view replaced by the empty-state/chat-list (`closeChat` → `clearActiveChat` fires in logs). (2) The panel `Container` is wrapped in a tap-absorbing `GestureDetector` (empty `onTap`, opaque) so a press on the 12px padding ring wins the gesture arena over the outer `onCancel` detector and is a no-op, while presses outside the panel still close the switcher — mirroring `_view` accepting every `MouseButtonPress` (`:413-417`) vs only `_widget` presses firing `_closeRequests` (`:307-313`). Verified desktop 1024x768 + mobile 400x720 (byte-identical screenshots: padding-ring taps leave the overlay open, outside taps close it), no overflow/exceptions.

# choose_datetime_box — CalendarBox + ChooseDateTimeBox + ScheduleBox + TimePickerBox + MonthYearPicker

Overall the file is a faithful, well-wired port: no stubs, no empty callbacks, no
mock data, no TODOs. Title strings, `kScheduledUntilOnlineTimestamp` (0x7FFFFFFE),
jump delay (700ms), tooltip delay (350ms), wheel steps (hour 1 / minute 10), drum
heights (200px = 5×40), and the all-weeks scrollable grid all match AyuGram. The
premium-toast link, send-when-online, repeat menu, and calendar date-pick are all
wired to the engine / navigator. All 5 MAJOR findings verified fixed & closed
against AyuGram ground truth: (1) "Select days" is now a bottom-LEFT button
(`isLeft: true`) with "Close" on the right, matching `createButtons()`
addLeftButton/addButton split (calendar_box.cpp:1431-1444) — the shared
`_buildButtonRow` partitions left buttons before the `Spacer()` and right after
(confirm_box.dart:236-288); latent (no in-app caller passes `allowsSelection:true`),
code-verified. (2) The schedule submit button gained the send-options secondary
menu: right-click (desktop) + long-press (mobile) open a "Send without sound" menu
→ `_submit(silent: true)` — both modes verified live to return `silent:true`
(Type::SilentOnly, history_view_schedule_box.cpp:183-187; effects omitted, no
session effect picker exists). (3) Repeat label is now two-tone — "Repeat:" in the
default label color (titleFg) + a BOLD accent value (windowActiveTextFg) carrying
the dropdown/lock icon, verified desktop 1024×768 + mobile 400×720
(choose_date_time.cpp:300-318). (4) Dynamic-image fade now animates per-frame: a
listener on `fadeController` rebuilds the grid each tick so the rising
`fadeController.value` (read at the _DayCell call site, :753) drives opacity 0→1
over 200ms, mirroring `Ui::Animations::Basic` (calendar_box.cpp:674-694); latent
(no caller passes `dynamicImageForDate`), code-verified. (5) Dynamic day-image now
decodes pre-sized via `cacheWidth/cacheHeight = _cellInner×2 = 68px` (retina of the
34px cell) instead of native-res-then-downscale, matching
`state.image->image(_st.cellInner)` where cellInner=34px (calendar_box.cpp:841,
boxes.style:447); latent, code-verified. No crashes in desktop or mobile runs.

# color_picker_box — HSV/HSL colour editor (AyuGram `ColorEditor`)

Faithful, fully-functional port of `ui/widgets/color_editor.{h,cpp}`. The colour
math is provably identical (the two-layer Flutter gradients reduce to AyuGram's
4-corner bilinear interpolation for both RGBA and HSL), every numeric/hex field
and every slider is wired to real state, the lightness-limit clamping mirrors
`applyLimits`, and all three Dart callers (theme editor → RGBA+opacity, chat
accent → HSL+limits, brush picker → HSL) match their AyuGram counterparts. No
stubs, placeholders, mock data, or dead callbacks. All 3 MAJOR layout-fidelity
findings verified fixed & closed against AyuGram `resizeEvent` ground truth
(color_editor.cpp:1019-1094) via real render-geometry measurement at desktop
1024×768 + mobile 400×720, both RGBA and HSL: (1) HSL right-hand column now widens
to `colorSampleSize.width + colorEditSkip` = 60+10 = 70px (RGBA stays 60), folding
the freed hue-slider width into the fields/swatch — measured fieldWidth 70 (HSL) /
60 (RGBA) in both modes (cpp:1053-1054). (2) The picker+sliders+fields cluster is
now horizontally centered (`MainAxisAlignment.center`), giving symmetric margins —
measured L==R in all four cases (desktop RGBA 13.5/13.5, HSL 27/27; mobile RGBA
4/4, HSL 0/0) instead of slack dumped on the right (cpp:1026). (3) The vertical hue
slider spacer is now `colorEditSkip - colorSliderSkip` = 2px so its bar (carrying
an internal 8px skip) lands exactly `colorEditSkip` = 10px from the picker edge —
measured 10.00px in both modes (cpp:1030). `flutter_audit.sh verify` PASS, no
crashes/overflow in desktop or mobile runs.

# edit_forum_topic_box — Create/Edit forum topic dialog (title + color + topic-icon/custom-emoji selector)

Audited against AyuGram `boxes/peers/edit_forum_topic_box.cpp` + `chat_helpers/emoji_list_widget.cpp` + `dialogs/dialogs.style`.

Verified correct (no findings needed):
- Box dimensions: `_boxWidth=320` ← `layers.style:117 boxWidth:320px`; `_boxMaxHeight=408` ← `dialogs.style:679 editTopicMaxHeight:408px`; icon `_iconButtonSize=26` ← `dialogs.style:66 largeForumTopicIcon.size:26px`.
- Title field left inset = 70px (icon at x24 + 8+26+8 pad + 4 gap) ← `dialogs.style:677 editTopicTitleMargin margins(70,2,22,18)` + `:678 editTopicIconPosition point(24,19)`.
- Search bar padding `fromLTRB(1,10,2,6)` ← `chat_helpers.style:884 reactPanelEmojiPan.searchMargin margins(1,10,2,6)`.
- Title/buttons/general-topic logic, icon color-cycle on button tap, fly animation, premium gating + premium toast (`ref:'forum_topic_icon'` ← `emoji_list_widget.cpp:2409`), and result wiring to `engine.createForumTopic` (caller `chat_list_panel.dart:5420`) all match.

## Findings

# emoji_data — Telegram emoji keyword/suggestion engine port (emoji_keywords.cpp + emoji_suggestions.cpp)

Scope: `dart/lib/data/emoji_data.dart` ports `Ui::Emoji::Completer`
(`emoji_suggestions.cpp`) + `ChatHelpers::EmojiKeywords`
(`emoji_keywords.cpp`). This is a **faithful, complete port** — no stubs, no
placeholders, no fake data, no empty callbacks. Backend wiring is real and
verified end-to-end:

- Server lang packs fetched via the Go bridge (`GetEmojiKeywords` /
  `GetEmojiKeywordsDifference` / `GetEmojiKeywordsLanguages`,
  `engine_service.dart:1444-1494`) and fed in through `chat_view.dart:3935-3987`
  → `loadServerKeywords`/`loadServerKeywordsDiff`.
- Recents/variants persisted via `init(saveCallback)` + `saveState`/`loadState`
  (`main.dart:329-347`); recents recorded on send (`chat_view.dart:4366`) and on
  suggestion accept; skin-tone resolver wired from the emoji panel
  (`emoji_panel.dart:59`).
- Algorithm parity verified for `NormalizeQuery`, `ReplacementWords`,
  `matchQueryTailStartingFrom`, `findEqualCharsCount`, `LangPack::query`
  (lower_bound + take_while), `SkipExactKeyword`, `MustAddPostfix`,
  `PrioritizeRecent` (leapfrog), `ApplyVariants`, diff add/delete, and the
  `maxQueryLength = max(legacyLimit, modernLimit)` cutoff
  (`emoji_suggestions_widget.cpp:959`). All match.

Two behavioral deviations from the C++ authority remain (both make the Dart
*stricter to intent* than the shipped C++, so they read as improvements — but
they are reproducible divergences in suggestion output, flagged per the
"C++ is the only authority" rule):

- [ ] [MAJOR] Exact-match suggestions are floated to the top, but the C++ authority's exact-match boost is dead code and never reorders — so legacy/built-in suggestion ORDER diverges. Dart computes `isExact = (rawKw == q)` and `_legacyRankKey` makes `exact` the most-dominant bucket (`exact << 3`), pushing an exact built-in keyword (e.g. `:key:` → 🔑) ahead of equal-rank prefix matches (e.g. `keyboard` → ⌨️). In C++, `Completer::prepareResult`'s 4th `stable_partition` calls `isExactMatch(replacement)`, which is size-gated: it requires `replacement.size() == _initialQuery.size() + 1`, comparing the colon-wrapped baked replacement (`":key:"`, the `^:[\+\-a-z0-9_]+:$` codegen form) against the colon-stripped query (`"key"`, stripped at `emoji_suggestions_widget.cpp:326`). `keyword_len+2 == keyword_len+1` is never true, so the exact partition is a no-op and C++ keeps declaration order for same-rank results. — `emoji_data.dart:3307` (`rawKw == q`) + `emoji_data.dart:2894`/`2898` (`exact` bucket) ← `AyuGram/lib_ui/emoji_suggestions/emoji_suggestions.cpp:322` (`isExactMatch` size gate) + `:391-393` (the no-op partition)

- [ ] [MAJOR] Uppercase shortcodes (e.g. `:TM`) return built-in suggestions in Dart but NOTHING from the legacy path in C++ — different result set. Dart lowercases the query first (`q = query.toLowerCase()`) and the legacy search runs on that lowercased `q`, so `:TM` → `q="tm"` → 🅣🅜 ™️ is suggested. C++ passes the RAW (un-lowercased) query to the legacy completer (`AppendLegacySuggestions(result, query)` uses the original arg, not `normalized`), and `Completer::NormalizeQuery` keeps only chars where `IsLetterOrNumber` is true — and `IsLetterOrNumber` accepts only lowercase `'a'..'z'`. An all-uppercase query therefore normalizes to empty and `resolve()` returns `{}` (server packs key on `tm` shortcodes, not on the built-in `tm`→™️ entry, so the user sees an empty box). — `emoji_data.dart:3195` (`toLowerCase`) + `emoji_data.dart:2760` (lowercase-only `isLetter`, fed already-lowercased `q`) ← `AyuGram/SourceFiles/chat_helpers/emoji_keywords.cpp:639` (raw query to legacy) + `AyuGram/lib_ui/emoji_suggestions/emoji_suggestions.cpp:101-103` (`IsLetterOrNumber` is lowercase-only) + `:225-227` (empty normalized query → no results)

Non-blocking (not flagged): the legacy search iterates every entry in
`_legacyCandidates` per keystroke (`emoji_data.dart:3285`) instead of using a
first-char index like C++ `GetReplacements(first)`
(`generator.cpp:1129`); work is bounded (~1.5k short entries, candidates
pre-built once via `late final`) so impact is negligible. The cache-load
(`init`) and server-fetch (chat open) ordering isn't enforced as C++ enforces
it (constructor `readLocalCache` → `refresh`, `emoji_keywords.cpp:369-371`), but
in practice startup cache I/O always completes before the post-auth chat-open
fetch, so a stale-overwrite race is not reachable.

# hamburger_drawer — MainMenu drawer (cover, account switcher, menu items, footer)

Audited against AyuGram `window/window_main_menu.cpp`, `window/window_main_menu_helpers.cpp`,
`settings/sections/settings_information.cpp` and `window/window.style`.
The file is well-wired overall — no empty callbacks, no "coming soon" stubs, no mock data;
account/chat data flows from real state. Findings below are deviations from the AyuGram source.

- [ ] [MAJOR] Menu item ORDER for LRead/SRead is wrong: AyuGram adds "Mark All Read (Silent)" (LRead) and "Mark Stories as Viewed" (SRead) immediately AFTER Saved Messages and BEFORE Settings/Night Mode/Ghost. The Dart places them AFTER Settings → Night Mode → Ghost Mode, near the bottom of the list. — `hamburger_drawer.dart:410-459` ← `AyuGram/SourceFiles/window/window_main_menu.cpp:767-843`

- [ ] [MAJOR] Archive row is placed at the WRONG position. AyuGram calls `setupArchive()` BEFORE `setupMenu()` and both append to the same `_menu` VerticalLayout, so the Archive button (with a PlainShadow divider directly below it) renders at the TOP of the menu, above "My Profile". The Dart appends the Archive row at the very BOTTOM of `_lvKids`, after Streamer Mode and just before the footer, with no divider. — `hamburger_drawer.dart:477-502` ← `AyuGram/SourceFiles/window/window_main_menu.cpp:358-359` and `:550-564`

- [ ] [MAJOR] PlainShadow divider after the My Profile/Bots block is rendered unconditionally. AyuGram gates it: `if (settings.showMyProfileInDrawer() || settings.showBotsInDrawer())` add PlainShadow. The Dart adds the divider as a plain (un-`if`'d) entry in `_lvKids`, so when BOTH "My Profile" and "Bots" rows are hidden, a stray separator line appears at the top of the menu. — `hamburger_drawer.dart:228-234` ← `AyuGram/SourceFiles/window/window_main_menu.cpp:720-723`

- [ ] [MAJOR] Cover status line (the line under the name at `mainMenuCoverStatusTop` 103px) shows the wrong content and opens the wrong destination. AyuGram's `_setEmojiStatus` displays the localized link text "AyuGram Preferences" (`tr::ayu_AyuPreferences()`) and its click handler opens the AyuGram settings page (`controller->showSettings(Settings::AyuMain::Id())`). The Dart instead renders `@username` / phone / platform-label as an underlined link that opens the generic `SettingsScreen`. — `hamburger_drawer.dart:1066-1105` (built at `:960`) ← `AyuGram/SourceFiles/window/window_main_menu.cpp:111-116`, `:314`, `:667-671`

- [ ] [MAJOR] "Add Test Account" / "Test Server" does not actually create a test-server account. The drawer's right-click context menu (`production` vs `test`) and the test-mode dialog only change the dialog TITLE; the platform tap calls `appState.addAccount(p.$1)` with no test flag, and `addAccount(String platform)` in `app_state.dart:3809` has no testMode parameter at all — so picking a platform under "Add Test Account" creates a normal production account. AyuGram's Test Server action calls `add(Environment::Test)`, connecting to the actual test datacenter. — `hamburger_drawer.dart:754-790` (drop at `:783`), context menu `:1290-1295` ← `AyuGram/SourceFiles/settings/sections/settings_information.cpp:1043-1048`

- [ ] [MAJOR] "My Groups" / "My Channels" popup lists ALL groups/channels the user is in, not only the ones the user created/owns. AyuGram's `AddMyChannelsBox` filters with `amCreator()` (groups: `(c && c->amCreator()) || (g && g->amCreator())`; broadcasts: `channel->amCreator()`) — i.e. only chats the user is the creator of. The Dart `_showMyGroupsPopup` filters only by `c.type == group/channel` over `chatsForAccount`, with no ownership/creator check. — `hamburger_drawer.dart:731-752` (filter at `:736-738`) ← `AyuGram/SourceFiles/window/window_main_menu_helpers.cpp:206-232`

# info_panel — Telegram Desktop Info section (profile cover, details, shared media, members, statistics, boosts)

`dart/lib/ui/info_panel.dart` (~10,750 lines) reimplements AyuGram's `info/` subsystem: the flexible profile cover/top bar, chat/user/channel/topic info pages, details block (bio/username/phone/business-hours/personal-channel), mute & notification settings, shared media (photos/videos/files/audio/voice/links/gifs/music/stories/gifts), member list with admin management, similar channels, channel/group statistics, boosts, per-message statistics and add-member.

Overall the engine wiring is genuine — almost every interactive element reaches a real `engine.*`/`chatState.*` method, dimensions in the cover delegate match `info.style` precisely (236/56px extents, 113/134/24px positions, 80px photo, 52px action buttons, 23px icons, 82px media grid), and there are no "coming soon" snackbars. The findings below are the real gaps: missing tap wiring on media cells, a member sub-page that never loads its data, permission gating that ignores backend flags, and a set of missing/relocated features and behavioral deviations versus the AyuGram ground truth.

## Profile cover, top bar & mute/notification dialogs

- [ ] [MAJOR] Action-button row overflow threshold differs: AyuGram hard-caps the top-bar action row at 3 buttons and appends "More" beyond that; the Dart `_actionButtons()` only overflows when `buttons.length > 4` (slices at index 3), so it can show 4 distinct buttons with no "More" (~33% deviation in max visible buttons) — `info_panel.dart:959` ← `AyuGram/info/profile/info_profile_top_bar.cpp:715`
- [ ] [MAJOR] Mute action-button left-click does the wrong thing: AyuGram opens the full mute menu on a left click when the peer is not muted (and only unmutes directly when already muted); the Dart button's left tap calls `onMuteToggle` which immediately mutes-forever, and the duration menu is only reachable via right-click — `info_panel.dart:1064` ← `AyuGram/info/profile/info_profile_top_bar.cpp:846`
- [ ] [MAJOR] Two AyuGram top-bar action buttons are missing entirely: "Report" (un-joined non-admin channels/groups) and "Leave"/Delete-and-leave (joined non-topic chats/channels). `_actionButtons()` only emits Join/Message/Mute/Call/Discuss/Manage/Gift — `info_panel.dart:921` ← `AyuGram/info/profile/info_profile_top_bar.cpp:986`
- [ ] [MAJOR] Mute context-menu contents deviate from AyuGram's `FillMuteMenu`: Dart adds a standalone "Notification volume" entry (AyuGram exposes volume only via the slider inside the ringtones box, not in the mute menu) and hardcodes six fixed durations (1h/4h/8h/18h/3d/1w) instead of AyuGram's dynamic last-used `mutePeriods()` list — `info_panel.dart:1094` ← `AyuGram/menu/menu_mute.cpp:313`
- [ ] [MAJOR] Ringtone picker dialog omits the per-chat volume slider AyuGram's RingtonesBox embeds (`AddRingtonesVolumeSlider`); Dart split volume into a separate menu item + `_ChatVolumeDialog`, leaving the sound list with no volume control — `info_panel.dart:1529` ← `AyuGram/boxes/ringtones_box.cpp:352`
- [ ] [MAJOR] Avatar/userpic context menu is missing AyuGram entries: AyuGram offers "Open Photo" plus conditional "Report", "Set Photo For…" / "Suggest Photo…"; Dart's `_showAvatarContextMenu` only offers "Open Photo" — `info_panel.dart:1334` ← `AyuGram/info/profile/info_profile_top_bar.cpp:1234`

## ChatInfo & UserProfile pages

- [ ] [CRITICAL] `_UserProfilePage` (pushed member sub-page) never calls `getUserProfile`, so it shows no bio/about, phone, birthday, working hours, business location, personal channel or notes — it renders only username/ID/role from `MemberInfo`. AyuGram's user `setupInfo` renders all of these, the engine supplies them, and the sibling `_ChatDetails` already fetches them (line 2564) — `info_panel.dart:3073-3296` ← `AyuGram/info/profile/info_profile_actions.cpp:1709-1799`
- [ ] [CRITICAL] `_UserProfilePage` omits the user Actions block entirely (Share Contact, Edit/Add Contact, Delete Contact, Block User, and for bots Add-to-Group / commands / Report). AyuGram's `fillUserActions` always builds these for a user profile — `info_panel.dart:3235-3290` ← `AyuGram/info/profile/info_profile_actions.cpp:3015-3032`
- [ ] [MAJOR] "Common groups" is a standalone tappable row inside the details column loaded once via a `Future` with no live updates; AyuGram renders it as a shared-media-style button created in `setupSharedMedia` (`AddCommonGroupsButton`), grouped with Photos/Video/Files and reactive via `CommonGroupsCountValue` — `info_panel.dart:3269-3276` (and `:4444`) ← `AyuGram/info/media/info_media_buttons.cpp:211-227`
- [ ] [MAJOR] Section ordering deviates from AyuGram: AyuGram's `setupContent` is SavedMusic → Details → SharedMedia → Channel-Members/Manage → Actions → group Members (members come AFTER actions); the Dart body orders Details → Notification toggle → SharedMedia → Members → Group/Channel actions, placing the member list before the actions block — `info_panel.dart:2733-2815` ← `AyuGram/info/profile/info_profile_inner_widget.cpp:196-256`

## Details block (business hours, personal channel)

- [ ] [MAJOR] Business hours are not shifted to the viewer's local timezone: AyuGram converts owner intervals via `ShiftedIntervals(hours.intervals, timezoneDelta)` and displays that by default; the Dart widget evaluates raw owner-timezone intervals against local `DateTime.now()`, producing wrong open/closed status & times across timezones — `info_panel.dart:4153` ← `AyuGram/info/profile/info_profile_actions.cpp:477`
- [ ] [MAJOR] Missing the "My time / Local time" timezone toggle AyuGram renders to switch between owner-local and viewer-local hours; `_BusinessHoursWidget` has no such control — `info_panel.dart:4228` ← `AyuGram/info/profile/info_profile_actions.cpp:611`
- [ ] [MAJOR] Business-hours expanded day list uses a fixed Monday→Sunday order; AyuGram shows today's status at top and the following days via `(day + i) % 7` for i=1..6 — `info_panel.dart:4252` ← `AyuGram/info/profile/info_profile_actions.cpp:690`
- [ ] [MAJOR] No "Open 24 hours" handling: AyuGram returns `lng_info_hours_open_full` for a fully-open day (`IsFullOpen`); Dart prints the literal interval "00:00 – 24:00" — `info_panel.dart:4194` ← `AyuGram/info/profile/info_profile_actions.cpp:346`
- [ ] [MAJOR] No next-day wrapping for intervals crossing midnight: AyuGram's `FormatDayTime` appends `lng_info_hours_next_day` past `kDay`, but Dart's `_formatMinute` does `(m ~/ 60) % 24`, silently collapsing past-midnight end times — `info_panel.dart:4188` ← `AyuGram/info/profile/info_profile_actions.cpp:314`
- [ ] [MAJOR] Personal-channel row omits the subscriber count AyuGram appends to the label (`· N subscribers` via `channelLabelFactory`/`membersCount()`); Dart shows only the bare channel name under a static "Personal Channel" label — `info_panel.dart:4019` ← `AyuGram/info/profile/info_profile_actions.cpp:2026`

## Group / channel action sections

- [ ] [MAJOR] Report row is shown unconditionally for groups; AyuGram hides Report when the self user is the chat creator/owner (`!chat || chat->amCreator()`) — `info_panel.dart:4616` ← `AyuGram/window/window_peer_menu.cpp:985`
- [ ] [MAJOR] Report row is shown unconditionally for channels; AyuGram only adds it `if (!channel->amCreator())` — `info_panel.dart:4942` ← `AyuGram/info/profile/info_profile_actions.cpp:3042`
- [ ] [MAJOR] Statistics row gated by an invented heuristic (`_isSelfAdmin && memberCount >= 500`) for groups; AyuGram gates statistics on the server `CanGetStatistics`/`can_view_stats` flag with no member threshold — `info_panel.dart:4539` ← `AyuGram/data/data_channel.cpp:1323`
- [ ] [MAJOR] Statistics row gated by invented `_isSelfAdmin && memberCount >= 50` heuristic for channels; same `CanGetStatistics` flag should be used instead of a member threshold — `info_panel.dart:4885` ← `AyuGram/data/data_channel.cpp:1323`

## Shared-media cells & list items

- [ ] [CRITICAL] Photo/video grid cells have no tap handler at all — tapping a photo or video in shared media does nothing (no media-viewer open, no download). `_GridCell` has no internal gesture and is placed bare in both the inline section and the full sub-page. AyuGram's `Photo::getState` returns an open-viewer link and `Video::getState` returns open/download links — `info_panel.dart:7007` (used bare at `:3538` and `:6211`) ← `AyuGram/overview/overview_layout.cpp:479`
- [ ] [CRITICAL] `_GifCell` only renders a static `Image.memory` thumbnail; it never plays the animated GIF and has no tap handler, despite being the "animated gif cell". AyuGram's `Gif` uses a `Media::Clip` player (`iconAnimated()` true) and `Gif::getState` returns open/download/cancel links — `info_panel.dart:7233` (used bare at `:3645`, `:6365`) ← `AyuGram/overview/overview_layout.cpp:2406`
- [ ] [MAJOR] No download-progress indicator on any media row/cell: while downloading, file/audio/voice/round rows and photo/video/gif cells show only a static icon/placeholder. AyuGram draws a live `_radial` ring with `dataProgress()` for every media item — `info_panel.dart:6469` (and `:6583`, `:7150`) ← `AyuGram/overview/overview_layout.cpp:899`
- [ ] [MAJOR] `_FileListItem` shows no thumbnail and no document-type generic icon — it always renders just the extension text in a colored box. AyuGram's `Document` loads and draws the real file thumbnail (`withThumb()` → `loadThumbnail`) or a typed generic icon — `info_panel.dart:6481` ← `AyuGram/overview/overview_layout.cpp:1167`
- [ ] [MAJOR] `_PollListItem` shows a hardcoded literal `'Poll'` subtitle with no vote counts, options or closed/anonymous state — poll result data is not surfaced at all — `info_panel.dart:6970` ← `AyuGram/history/view/media/history_view_poll.cpp:1` (polls render full results in-message; never a static "Poll" string)
- [ ] [MAJOR] Tiny media cells decode at full source resolution — no `cacheWidth`/`cacheHeight` on `Image.memory`/`Image.file`. `_GridCell` `Image.file(localPath)` in particular can decode a full-size downloaded photo into an ~82px cell; AyuGram scales the pixmap to the exact cell size before painting (`->pix(inner.size())`) — `info_panel.dart:7167` (and `:7296`, `:6884`) ← `AyuGram/overview/overview_layout.cpp:871`

## Members list & admin management

- [ ] [CRITICAL] Member context-menu actions are gated only on the `member.role` string and ignore the per-permission flags the engine supplies (`canEditAdmin`, `canRestrict`, `isCreator`, `isSelf`), so a non-admin viewer sees Promote/Restrict/Remove/Ban on every member and they even appear on self. AyuGram gates each action independently via `canAddOrEditAdmin`, `canRestrictParticipant`, `canRemoveParticipant` — `info_panel.dart:7932-7954` ← `AyuGram/boxes/peers/edit_participants_box.cpp:1962-1998` (flags at `dart/lib/models/engine_models.dart:1933-1936`)
- [ ] [MAJOR] Custom rank never displayed: the admin pill always shows literal "owner"/"admin"; AyuGram uses the member's custom rank text (`_type.rank`) as the pill when set, falling back to the owner/admin badge — `info_panel.dart:7816-7818` ← `AyuGram/info/profile/info_profile_members_controllers.cpp:44-55` (rank at `dart/lib/models/engine_models.dart:1927`)
- [ ] [MAJOR] Admin action is split into separate "Promote" + "Demote" items; AyuGram shows ONE action (`lng_context_promote_admin` for non-admins / `lng_context_edit_permissions` for existing admins) both opening the EditAdmin box — there is no standalone "Demote" or "Edit permissions" context item — `info_panel.dart:7946-7949` ← `AyuGram/boxes/peers/edit_participants_box.cpp:1962-1973`
- [ ] [MAJOR] "Restrict" offered for every non-owner; AyuGram only shows it when `canRestrictWithoutKick` (chat creator, or megagroup and not gigagroup) — `info_panel.dart:7950-7951` ← `AyuGram/boxes/peers/edit_participants_box.cpp:1975-1986`
- [ ] [MAJOR] Search and Add-member header buttons are always rendered; AyuGram only shows search when member count ≥ 8 (`kEnableSearchMembersAfterCount`) and add-member only when permission-gated (`CanAddMemberValue`) — `info_panel.dart:7644-7667` ← `AyuGram/info/profile/info_profile_members.cpp:40` (and `:210-225`)

## Boosts & statistics

- [ ] [MAJOR] Boosts overview is missing the "Premium audience"/"Premium members" metric (with percentage): the Go backend returns `premium_audience` but Dart never reads it, instead showing a "Boosts via gifts" row that AyuGram does not display as an overview cell — `info_panel.dart:8478-8548` ← `AyuGram/info/channel_statistics/boosts/info_boosts_inner_widget.cpp:135-140`
- [ ] [MAJOR] Prepaid giveaways are not rendered as a dedicated, directly-clickable on-page section (header "Prepaid Giveaways", per-row boost badge + months/credits, tap opens that giveaway). The Dart page only forwards `prepaid_giveaways` into the box opened by "Get More Boosts" — `info_panel.dart:8554-8642` ← `AyuGram/info/channel_statistics/boosts/info_boosts_inner_widget.cpp:341-397`

## Message statistics & public forwards

- [ ] [MAJOR] Public-forward row subtitle is incomplete: it shows only `"<views> views"` and is missing the members/subscribers count and the `lng_stories_no_views` ("No views") fallback. AyuGram builds the status as `"<subscribers/members>, <views> views"`; the Go backend also never returns the member count (`PublicForwardMessage` emits only name/peer_id/msg_id/views/date) — `info_panel.dart:10360-10412` ← `AyuGram/info/statistics/info_statistics_list_controllers.cpp:421-434`

# music_player_bar — now-playing media-player bar (port of AyuGram `Media::Player::Widget`)

Overall this file is well-wired: every `onTap` calls a real `AudioService`/`AppState`
method, the repeat/order/speed/autoplay settings flow UI → `AppState` →
`main.dart:377-390` listener → `AudioService` → playback (verified in
`audio_service.dart` `nextInPlaylist`/`setRate`/completion handler). No stubs,
no mock data, no TODO/`coming soon`. The findings below are missing controls and
behavioral/visual deviations from the AyuGram source.

- [ ] [CRITICAL] Volume control is entirely absent — AyuGram's player bar has a `_volumeToggle` mute button (icon reflects 0 / <0.66 / full volume) plus a hover/wheel-driven volume dropdown slider; the Dart controls list (prev, play, next, title, time, repeat, order, speed, more, close) has no volume toggle and no volume widget exists anywhere in the player UI — `music_player_bar.dart:80-136` ← `AyuGram/media/player/media_player_widget.cpp:57` + `AyuGram/media/player/media_player.style:241-250`

- [ ] [MAJOR] Speed control offers only a discrete 4-value popup `[0.5, 1.0, 1.5, 2.0]`, but AyuGram's speed dropdown is a continuous slider over `kSpeedMin..kSpeedMax = 0.5..2.5` (sticky points 0.8/1.0/1.2/1.5/1.7/2.0/2.2) plus preset speed icons — the Dart caps at 2.0× (cannot reach 2.2/2.5×, a 20% short top end) and drops the slider/presets — `music_player_bar.dart:213-219` ← `AyuGram/media/media_common.h:41-42` + `AyuGram/media/player/media_player_dropdown.cpp:39-47` + `AyuGram/media/player/media_player.style:178-215`

- [ ] [MAJOR] Order button is a 3-way tap-cycle (Default→Reverse→Shuffle→Default); AyuGram's order button opens a dropdown menu with two toggle actions ("Reverse", "Shuffle") where clicking an active mode returns to Default — different interaction model and menu contents — `music_player_bar.dart:180-198` ← `AyuGram/media/player/media_player_dropdown.cpp:646-693`

- [ ] [MAJOR] Seek bar draws a static 2px line; AyuGram's `mediaPlayerPlayback` `FilledSlider` line is 4px at rest (`lineWidth`) and animates up to 8px (`fullWidth`) on hover over 150ms — the Dart line is half the resting thickness and has no hover-grow animation — `music_player_bar.dart:412-431` ← `AyuGram/media/player/media_player.style:288-295` + `AyuGram/ui/widgets/continuous_sliders.cpp:228`

- [ ] [MAJOR] Title/name tap always calls `jumpToMessage`; AyuGram only "shows the item" (jumps) when `_type == Voice` or the song is from another session — for a current-session song, clicking the name toggles the playlist dropdown instead and the cursor stays default (not pointer) — `music_player_bar.dart:105-112` ← `AyuGram/media/player/media_player_widget.cpp:477-514` (note: the playlist dropdown panel itself is a separate unported component)

- [ ] [MAJOR] Responsive breakpoint uses `maxWidth >= 600` to gate time text + inline repeat/order (else overflow menu); AyuGram's `mediaPlayerWideWidth` is 460px and the narrow mechanism differs — when narrow AyuGram hides the entire right-controls group (time/volume/repeat/order/speed) and reveals it on hover, rather than moving repeat/order into an overflow menu — so at 460–599px the two diverge on which controls are visible — `music_player_bar.dart:76` ← `AyuGram/media/player/media_player.style:88` + `AyuGram/media/player/media_player_widget.cpp:365,403-407`

# my_profile_page — Edit Profile / My Account settings page (§14.5)

Implements the self-profile settings page: photo, bio, name/phone/username rows,
birthday, personal channel, name color box, and the multi-account list. Maps to
AyuGram `settings/sections/settings_information.cpp` (`Information` section),
`boxes/peers/edit_peer_color_box.cpp`, and `ui/controls/userpic_button.cpp`.

Overall the page is well wired to the engine (bio save/load, name, birthday,
personal channel, color save, photo upload/remove, accounts, add account all hit
real bridge calls). The issues below are data-flow gaps, a degraded sub-feature,
and layout/menu deviations — no empty-callback stubs or mock data were found.

- [ ] [MAJOR] Name-color box never loads the current background emoji, profile color, or profile background emoji — only the name `colorId` is fetched, so re-opening the box always shows "Off" for the background emoji and resets the Profile tab to the name color regardless of the user's real settings. `getSelfColorAndChannel` returns only `color_id`/`channel_name`, and `_selectedEmojiId`/`_profileColorId`/`_profileEmojiId` are initialized to defaults (0 / name color) and never populated from the server. AyuGram seeds the box from four distinct current values: `peer->colorIndex()`, `peer->colorProfileIndex()`, `peer->backgroundEmojiId()`, and `peer->profileBackgroundEmojiId()`. — `my_profile_page.dart:1867-1873` (+ `dart/lib/bridge/engine_service.dart:4609-4612`) ← `AyuGram/boxes/peers/edit_peer_color_box.cpp:501-506`

- [ ] [MAJOR] Birthday section is ordered before Personal Channel + Your Color, but AyuGram lays out Personal Channel and the color button first, then Birthday. The Dart build list emits `_BirthdayRow` (line 461) ahead of `_PersonalChannelRow` (line 544) and `_YourColorRow` (line 551), whereas AyuGram calls `SetupPersonalChannel` (channel + `AddPeerColorButton`) before `SetupBirthday`. — `my_profile_page.dart:461` ← `AyuGram/settings/sections/settings_information.cpp:1288-1289`

- [ ] [MAJOR] Custom-emoji suggestions in the bio field are misleading: the autocomplete popup renders custom-emoji thumbnails from installed packs, but selecting one inserts the plain fallback Unicode emoji (`insertText` returns `customEmoji?.emoji`), not the animated custom emoji — the underlying widget is a plain `TextField` that cannot hold custom-emoji entities. AyuGram's bio is a `Ui::InputField` wired through `Ui::Emoji::SuggestionsController::Init`, which inserts real custom-emoji entities (DocumentId-backed). — `my_profile_page.dart:727` (+ `my_profile_page.dart:979`) ← `AyuGram/settings/sections/settings_information.cpp:744-747`

- [ ] [MAJOR] Avatar/upload menu is missing the "Set Public Photo" privacy action. For the self user, AyuGram's ChoosePhoto sub-button menu adds `lng_edit_privacy_profile_photo_public_set`, which opens the profile-photo `EditPrivacyBox` wired to `Api::UserPrivacy::Key::ProfilePhoto`. The Dart menu only offers View / Upload / From Clipboard / Set Emoji / Remove and has no public-photo privacy entry. — `my_profile_page.dart:1226-1267` ← `AyuGram/ui/controls/userpic_button.cpp:448-467`

# strings — Centralised translatable string table (mirror of Telegram/AyuGram lang pack)

`TrStrings` is a static table of hardcoded English strings mirroring AyuGram/Telegram
Desktop's `lang.strings` keys (`tr::lng_*`) and AyuGram-specific `ayu_*` keys. Audit
verified every string value against `AyuGram/Telegram/Resources/langs/lang.strings`
and the cited `.cpp` sources. ~70 strings checked; the overwhelming majority are
byte-for-byte exact matches (intro, passcode, theme-revert plural `#one/#other`,
all reaction notifications `lng_reaction_*`, poll votes `lng_poll_vote*`, paid-post
warnings `lng_suggest_warn_*`, TTL box `lng_manage_messages_ttl_*`, sessions
`lng_settings_reset_*` / `lng_self_destruct_sessions_*`, AyuForward `ayu_AyuForwardStatus*`).
One material deviation found.

- [ ] [MAJOR] `lngFileTooLarge` is a fabricated string — the text "The file exceeds the size limit." / "$count files exceed the size limit." exists nowhere in AyuGram's lang pack (only unrelated `ayu_AttachmentsFolderMaxSizeDescription` uses "exceeds"). AyuGram's real over-sized-file flow is `FileSizeLimitBox` (a `SimpleLimitBox`), titled `lng_file_size_limit_title` = "File Too Large" with body `lng_file_size_limit1` = "The document can't be sent, because it is larger than {size}." where `{size}` is the actual backend-provided limit (bold, e.g. "2 GB"), plus a Premium upsell `lng_file_size_limit2` = "You can double this limit to {size} per document by subscribing to **Telegram Premium**." The Dart string drops the backend `{size}` value and the Premium upsell entirely, and is rendered as a generic `SnackBar` (`chat_view.dart:4906`) instead of the box — so the user never sees what the limit actually is. — `strings.dart:41-42` ← `AyuGram/Telegram/SourceFiles/boxes/premium_limits_box.cpp:1036` (`lng_file_size_limit1`, title `:1055`, premium `:1042`; lang.strings:270-271, title :267) / box triggered from `storage/localimageloader.cpp:1066`

## Verified-correct (no action — recorded for completeness)

- `lngDialogsTextWithFrom` correctly composes `lng_dialogs_text_from_wrapped` ("{from}:") + `lng_dialogs_text_with_from` ("{from_part} {message}") into "$from: $message" — lang.strings:4779-4780.
- `lngNotifGif` = 'GIF' matches AyuGram's hardcoded literal `u"GIF"_q` — `data_media_types.cpp:1229/1279` (not a lang key).
- `lngNotifInvoice` fallback 'Invoice' only fires when `invoiceTitle` is empty; AyuGram's `MediaInvoice::notificationText()` returns `_invoice.title` (`data_media_types.cpp:2193`) — the Dart uses the title when present and only falls back, which is a harmless default.
- `lngThemeReverting`/`lngForwardMessages` inline `count == 1` pluralization correctly reproduces the `#one`/`#other` forms (lang.strings:1086-1087, 5309-5310) for English. (Note: only English plural categories are handled — acceptable given the file's documented English-only, no-server-lang-pack design; revisit when i18n lands.)

## Cosmetic-only deviations (skipped per severity rules — listed for the i18n pass)

- `lngThemeKeepChanges` 'Keep Changes' vs lang.strings:1088 "Keep changes" (case).
- `lngEnableAutoDelete` 'Enable auto-delete' / `lngEditAutoDeleteSettings` 'Edit auto-delete settings' vs lang.strings:5559/5558 "Enable Auto-Delete" / "Edit Auto-Delete Settings" (case).
- `lngNotifLiveLocation` 'Live location' vs lang.strings + `data_media_types.cpp:1688` `lng_live_location` = "Live Location" (case).
- `lngSigninCantEmailForgot` "...access to your email..." vs lang.strings:440 "...access to the email..." (one word).

# main — app bootstrap, theme-revert overlay (§25.9.3), passcode lock screen

Scope: `dart/lib/main.dart` = `main()` bootstrap, `UniClientApp` (engine init,
tray, notifications, theme cross-fade, palette cache, debug-command poller,
`build()`/MaterialApp), `_ThemeRevertOverlay`, `_PasscodeLockScreen`,
`_LinkButton`. Verified against `window/themes/window_theme_warning.cpp`,
`window/window_lock_widgets.cpp`, `boxes/boxes.style`, `layers.style`.

Verified-correct (no finding): theme-warning box 364×150 / text-top 60 / title
(24,13) (`boxes.style:347-349`, `layers.style:81`); 15.999s truncating countdown
(`window_theme_warning.cpp:24,95-96`); warning button placement right:10/bottom:10/gap:6
(`defaultBox.buttonPadding (6,10,10,10)`); passcode input 225×61 / submit 42 /
header band 80 / submitSkip 40 / system-unlock btn 32×36 (`boxes.style:290-323`,
`intro.style:87-122`); submit/empty/flood/wrong + cold-start vs started
system-unlock gating (`window_lock_widgets.cpp:111-128,163-199,259-291`); forgot-passcode
logout = reset-all-accounts (`window_controller.cpp:548-557`). No stubs / empty
callbacks / TODO / mock data found. `updateNonIdle()` is throttled 1/s — pointer
handlers do not cause rebuild storms.

- [ ] [MAJOR] Passcode lock hardcodes text/subtext colors from a brightness check instead of reading the palette, so they don't follow custom/colorized themes — and the dark subtext value is wrong even for the two built-in dark themes. `subtextColor = isDark ? 0xFF6C7883 : …` drives the field placeholder (`main.dart:3123`) and the cold-start system-unlock info label (`main.dart:3223`), but AyuGram's `passcodeSystemUnlockLater`/input `placeholderFg` = `windowSubTextFg`, which is `0xFF708499` for `night` (`telegram_palette.dart:3662`) and `0xFF82868A` for `nightGreen` (`telegram_palette.dart:4879`) — neither equals `0xFF6C7883`. Should be `palette.windowSubTextFg`. — `main.dart:3046` ← `AyuGram/boxes/boxes.style:319-322` (passcodeSystemUnlockLater `textFg: windowSubTextFg`)
- [ ] [MAJOR] Same hardcoding for the header + input text color: `textColor = isDark ? 0xFFF5F5F5 : 0xFF000000` (`main.dart:3045`, used at header `main.dart:3092` and input style `main.dart:3132`). AyuGram paints the header with `st::windowFg` and the input `textFg: windowFg`, so a custom palette or accent-colorized theme (build() supports `customPalette` + `colorize()`) renders the lock-screen text in the wrong color. Should be `palette.windowFg`. — `main.dart:3045` ← `AyuGram/window/window_lock_widgets.cpp:249` (`p.setPen(st::windowFg)`)
- [ ] [MAJOR] Theme-revert overlay "Revert" button text color is the neutral `p.boxTextFg`, but AyuGram styles BOTH the Revert and Keep buttons with `st::defaultBoxButton`, whose text color is `lightButtonFg` (accent). Only the "Keep" button is given the accent color here; Revert renders grey instead of the accent blue. — `main.dart:2765` ← `AyuGram/window/themes/window_theme_warning.cpp:33` (`_revert(this, …, st::defaultBoxButton)`) + `AyuGram/lib_ui/ui/layers/layers.style:44` (`defaultBoxButton: RoundButton(defaultLightButton)` → `textFg: lightButtonFg`)
- [ ] [MAJOR] Lock-screen logout-confirm "Cancel" button uses a hardcoded English literal `'Cancel'` instead of the centralized `TrStrings.lngCancel()` that every other string in the file routes through; AyuGram's confirm box uses `tr::lng_cancel()`. (Visual output is identical today because `TrStrings` is still all-English literals, so this is a latent i18n / convention break rather than a current visible bug.) — `main.dart:3269` ← `AyuGram/window/window_controller.cpp:563-567` (`Ui::MakeConfirmBox` default cancel `tr::lng_cancel()`)

