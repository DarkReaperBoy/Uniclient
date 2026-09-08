# AyuGramDesktop ↔ UniClient feature-parity matrix

Goal: drive the "1:1 AyuGram clone" program (AGENTS.md §1.11/§7). Every row =
a concrete AyuGramDesktop GUI feature/behavior; UniClient status decides the
next task. Never copy code/assets — mirror behavior only.

Sources (primary, verified this session):
- AyuGramDesktop repo, branch `dev` (shallow clone, commit db3b989):
  `Telegram/SourceFiles/{ui,boxes,dialogs,history,info,media,calls,intro,
  window,settings,chat_helpers,ayu,...}` — full source tree enumerated.
- AyuGramDesktop README.md feature list + `ayu/` sources (settings, context
  menu, message history, filters, streamer mode, translator, message shot).
- UniClient repo: `go/gui/*` (app/sidebar/chat/login/voice/state/theme/qr),
  `go/cores/base.go` (Core iface, 24+ capability consts), engine method dump
  (engine/*.go), `go/cores/telegram.go` (1323 methods, all Core iface methods
  implemented), `go/utils/config.go` (AppConfig already models ghost flags).

Status legend:
- **PRESENT** — GUI shows it and it works.
- **PARTIAL** — GUI has a simplified/lesser version.
- **MISSING** — nothing anywhere (needs core + GUI).
- **CORE-ONLY** — engine/telegram core has it, GUI never surfaces it (the
  cheap wins: pure GUI work).

Scope: **TG** = Telegram-only surface (mandatory exact-1:1 per §1.11);
**SHARED** = generic chat surface all backends render.

Priority: P0 = first-screen / Telegram-mandatory, P1 = core chat UX,
P2 = settings/extras, P3 = rare/edge.

---

## 1. Login / Intro — scope: SHARED (engine auth machine; QR/email steps TG-only)

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Phone → code steps | Step-by-step auth with progress + resend | PRESENT | gui/login.go + engine.StartAuth/SubmitAuthInput | P0 |
| 2FA password step | Masked input, recovery | PRESENT | gui/login.go + SubmitAuthInput | P0 |
| Signup (name/photo) | First/last name on new account | PARTIAL (name only, no photo) | gui/login.go + auth.AuthStateSignUp | P2 |
| QR login | Live-refreshing QR, scan from mobile | PRESENT | gui/login.go+qr.go + engine QR states | P0 |
| Email verify / email-login | Code to email, email setup during auth | PRESENT (state machine covers it) | gui/login.go + telegram VerifyEmailDuringAuth | P2 |
| Login code auto-fill from TG msg | Code arrives via logged-in session | MISSING | engine EventLoginCode exists; gui shows nothing | P3 |

## 2. Chat list / Sidebar — scope: SHARED; folder CRUD, stories, similar channels = TG

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Three-pane layout | list · chat · right info panel | PARTIAL (2 panes; no right panel) | gui/app.go layoutMain | P0 |
| Hamburger main menu (drawer) | My profile, contacts, calls, night mode, settings, ghost/LRead/SRead/streamer toggles, new group/channel, saved msgs | MISSING (account menu = add/remove only) | new gui/menu.go + engine GhostFor/SetAccountGhost | P0 |
| Account switcher | Multi-account bar with per-account unread dots | PARTIAL (UniClient account bar: add/remove/conn dot; Ayu-style tray+drawer missing) | gui/sidebar.go + engine accounts | P1 |
| Search field in bar | Global search: chats, messages, users, posts, files, tags | PARTIAL (local title/lastmsg filter only) | gui/sidebar.go + engine SearchChats/SearchGlobalChats (CORE-ONLY) | P0 |
| Search results screen w/ tabs | Chats/Messages/Links/Files tabs + "search in" | CORE-ONLY | new gui/search.go + engine.SearchMessages (CORE-ONLY) | P1 |
| Top peers strip | Pictured top-contacts row above list while searching | CORE-ONLY | engine.GetTopPeers (CORE-ONLY) | P2 |
| Recent searches | Persisted search history dropdown | MISSING | engine settings_recent_searches ≙ new engine method | P3 |
| Folder tabs above list | Server-synced folders incl. custom, edit, reorder, invite links | PARTIAL (hardcoded All/Unread/People/Groups/Channels; no server sync/edit) | gui/sidebar.go layoutFolders + engine.GetFolders/CreateFolder/EditFolder/ReorderDialogFilters (all CORE-ONLY) | P0 |
| Archive collapsed row | Archived chats collapse to one row w/ badge | CORE-ONLY | engine.ArchiveChat/IsArchived (CORE-ONLY) | P1 |
| Pinned chats section | Pinned first, pin indicator icon | PARTIAL (engine sorts pinned first; no pin icon/separator) | gui/sidebar.go chatRow + ChatInfo.IsPinned | P1 |
| Chat row: image avatar | Real photo/video userpic w/ stories ring | PARTIAL (letter avatar; ChatInfo.AvatarPath + engine avatars.go downloader unused) | gui/theme.go Avatar + engine.DownloadSingleAvatar | P0 |
| Row: verified/scam/fake badges | Icon next to title | CORE-ONLY (fields exist: IsVerified/IsScam/IsFake) | gui/sidebar.go + ChatInfo fields | P1 |
| Row: muted/pin/unread-mark icons | Icons right of time, muted badge style | PARTIAL (gray badge; no mute/pin icons, no UnreadMark) | gui/sidebar.go | P1 |
| Row: draft preview | "Draft: …" when unsent | CORE-ONLY (SaveDraft + DraftText CORE-ONLY) | gui/sidebar.go + engine.SaveDraft | P2 |
| Row: media preview + "Photo"/"Voice" labels | Thumb + typed last-message labels | PARTIAL (typed labels done via engine.MediaPreviewLabel; sidebar thumbs later) | gui/sidebar.go previewText | P1 |
| Row: typing preview | "typing…" animated | PRESENT | gui/sidebar.go + engine.EventTyping | P0 |
| Row: unread reactions/mentions badge | @ badge for mentions, badge variants | CORE-ONLY (UnreadMentionCount/UnreadReactionCount CORE-ONLY) | gui/sidebar.go | P2 |
| Stories row + rings | Horizontal story circles w/ seen/unseen rings, story counter | CORE-ONLY (engine stories: FetchPeerStories, ChatInfo.StoryCount CORE-ONLY) | new gui/stories.go | P1 |
| Chat row context menu | Mute (1h/8h/forever), pin, archive, read/unread, add to folder, delete/leave, block | CORE-ONLY | new gui/menu.go + engine.MuteChat/PinChat/ArchiveChat/MarkChatUnread (CORE-ONLY) | P0 |
| Folder context menu | Edit/delete folder, hide All-chats, import filters | CORE-ONLY | engine folder CRUD (CORE-ONLY) | P2 |
| Quick action on hover | Mute/unread toggle buttons on row hover | MISSING | gui/sidebar.go | P3 |
| Next-unread button (↓) | Floating button jumps to next unread | MISSING | new gui/sidebar.go | P2 |
| Chat preview popup | Hover row → floating recent-messages peek | CORE-ONLY | new widget; engine.GetMessages (CORE-ONLY) | P3 |
| Suggestions (birthday/premium/promo) | Info cards in list | MISSING | P3 (low value; honest-empty rules apply) | P3 |
| Similar channels block | Channel recommendations block | CORE-ONLY | engine.GetSimilarChannels (CORE-ONLY) | P3 |

## 3. Chat view — scope: SHARED; pinned bar/translate bar/sponsored/forum/group-call bar = TG

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Peer header: image avatar | Round avatar in header | PARTIAL (letter avatar) | gui/chat.go chatHeader | P0 |
| Header status | "online"/"last seen"/members/typing/subtitle switch | PARTIAL (member count/typing; no online status) | gui/chat.go + engine EventUserStatus (unused) | P1 |
| Header badges | Verified/premium/emoji-status/scam icons | MISSING (ChatInfo has fields) | gui/chat.go | P1 |
| Header "..." menu | Peer actions: mute, search in chat, view profile, add member, clear history, leave/delete, block | CORE-ONLY | new gui/menu.go + engine methods (CORE-ONLY) | P0 |
| Pinned-message bar | Shows current pin, tap → jump, "N pinned" switcher | CORE-ONLY | engine.GetPinnedMessages (CORE-ONLY) + gui/chat.go | P1 |
| Translate bar | "Show original / Translate to …" bar over chat | CORE-ONLY | engine.TranslateText (CORE-ONLY) | P2 |
| Group-call bar | Live bar in header w/ participants, join button | CORE-ONLY | engine.GetGroupCall (CORE-ONLY) + gui/chat.go | P1 |
| Message bubbles: reply quote | Quoted block w/ sender+text, click→jump | PARTIAL (rendered; click→jump pending) | gui/chat.go replyQuote | P0 |
| Bubbles: forward header | "Forwarded from X" | PRESENT | gui/chat.go messageRow | P0 |
| Bubbles: reactions strip | Emoji + counts under bubble, own highlighted | PARTIAL (2026-09: strip + own toggle + quick-reaction row in menu; custom-emoji pills skipped — need doc fetch) | gui/chat.go reactionStrip + engine reactions_json persistence + cores.UpdateReactions | P0 |
| Bubbles: grouped/album layout | Media groups render as one grid bubble | CORE-ONLY (GroupedID CORE-ONLY) | gui/chat.go | P1 |
| Bubbles: sender color (groups) | Per-sender accent color + admin rank | CORE-ONLY (SenderColorID/SenderRank CORE-ONLY) | gui/chat.go | P2 |
| Service messages | Centered pill ("X joined group") | PARTIAL (rendered as plain bubble) | gui/chat.go messageRow | P1 |
| Unread messages separator | "Unread messages" divider line | MISSING | gui/chat.go messageList | P1 |
| Scroll: start bottom + autoscroll | Pin to bottom on new msg | PRESENT | gui/chat.go messageList | P0 |
| Scroll-up older history load | Loads older pages when reaching top | PRESENT (2026-09: loadOlder + merge preserves pages across refreshes) | gui/chat.go + state.go | P0 |
| Jump-to-message (reply/search click) | Scroll+highlight target | MISSING (engine GetMessages afterMs mirrors AyuGram loadMessagesDown) | gui/chat.go | P1 |
| Day dividers | Date pills between days | PRESENT | gui/chat.go dayDivider | P0 |
| Delivery ticks (sent/delivered/read) | Clock→✓→✓✓→accent ✓✓ | PRESENT | gui/chat.go statusTicks | P0 |
| Read receipt "seen" (small groups) | "Seen" time on own msgs, avatar stack | CORE-ONLY | engine.GetOutboxReadDate/GetMessageReadParticipants (CORE-ONLY) | P2 |
| Message selection mode | Rect/ctrl/shift select, action bar (fwd/del/report) | MISSING | gui/chat.go + engine bulk ops | P1 |
| Chat empty intro | "No messages here yet…" bubble | MISSING | gui/chat.go | P2 |
| Not-joined channel view | Channel w/o join: preview + big "Join" button | CORE-ONLY (ChatInfo.NotJoined/JoinRequest CORE-ONLY) | gui/chat.go + engine.JoinChannel | P1 |
| Slowmode / write restriction | Composer disabled w/ countdown/text | CORE-ONLY (ChatInfo.Slowmode*/WriteRestriction* CORE-ONLY) | gui/chat.go composerBar | P1 |
| Forum topics view | Topic list + topic bars + subsection tabs | CORE-ONLY (engine forum CRUD all CORE-ONLY) | new gui/topics.go | P2 |
| Chat background | Per-chat wallpaper, chat themes | CORE-ONLY (engine GetChatThemes/SetChatTheme CORE-ONLY) | gui/theme.go | P3 |
| Voice-message transcription | "▶ Transcribe" button on voice notes | CORE-ONLY | engine.TranscribeAudio (CORE-ONLY!) | P2 |
| Sponsored messages (channels) | Marked sponsored post | CORE-ONLY | engine.GetSponsoredInfo (CORE-ONLY) | P3 |

## 4. Composer — scope: SHARED; scheduled/inline-bots/send-as/bot-keyboard = TG

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Text input + send (Enter) | Send on Enter, shift+Enter newline | PRESENT | gui/chat.go composerBar | P0 |
| Reply mode | Header above input w/ quoted msg, cancel | PRESENT (composer chip; send routes replyToID) | gui/chat.go composerChip + state.go sendText | P0 |
| Edit mode | "Editing" header, saves via edit | PRESENT (composer chip + EditMessage, prefill) | gui/chat.go + state.go sendText | P0 |
| Attach menu (📎) | Photo/file/poll/location/contact/music menus | CORE-ONLY | engine.UploadFile/SendMediaAlbum/CreatePoll/SendLocation/SendContact (all CORE-ONLY) | P0 |
| Voice recording (hold 🎤) | Hold-to-record, slide-cancel, duration | CORE-ONLY | engine UploadFileWithOptions IsVoice (CORE-ONLY) | P1 |
| Emoji picker panel | Tabbed emoji/stickers/GIFs, search, recent | CORE-ONLY | engine sticker/gif/custom-emoji APIs (huge, CORE-ONLY) | P1 |
| Emoji autocomplete | Keyword suggestions while typing | CORE-ONLY | engine.GetEmojiKeywords (CORE-ONLY) | P2 |
| Bot commands menu (/) | "/" button lists chat commands | CORE-ONLY | engine.GetChatBotCommands (CORE-ONLY) | P2 |
| Bot keyboard (reply markup) | Custom reply keyboards under composer | CORE-ONLY | core has BotCallback infra (CORE-ONLY) | P2 |
| Inline bot results | @bot query results panel | CORE-ONLY | engine.GetInlineBotResultsFull/SendInlineBotResult (CORE-ONLY) | P3 |
| Scheduled send | Clock menu: pick time, silent, "send when online" | CORE-ONLY | engine.GetScheduledMessages/SendScheduledNow/RescheduleMessage (CORE-ONLY) | P1 |
| Silent send toggle | Bell toggle in field | CORE-ONLY | SendMessage silent param (CORE-ONLY) | P2 |
| Draft save/restore | Per-chat draft persists across restarts | CORE-ONLY | engine.SaveDraft (CORE-ONLY) + gui state | P1 |
| Char count / limits | Counter near limit | MISSING | gui/chat.go | P3 |
| Formatting (bold/italic/spoiler/code) | Rich text with entities + spoiler reveal | MISSING (cores.TextEntity exists; GUI renders plain) | gui/chat.go + entity renderer | P1 |
| Webpage preview toggle | Link preview on/off in field | CORE-ONLY | SendMessage webPageUrl params (CORE-ONLY) | P2 |
| Send-as channel (in groups) | Pick identity to post as | CORE-ONLY | engine.GetSendAs/SaveDefaultSendAs (CORE-ONLY) | P3 |

## 5. Message content types (rendering) — scope: TG (photos/files basic = SHARED)

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Photo | Image bubble, caption, tap→viewer | PARTIAL (bubble: inline thumb → auto-download → full image; caption; viewer later) | gui/media.go photoBubble | P0 |
| Video / video-note (round) | Player bubble w/ cover, round crop | PARTIAL (thumb + play badge + duration pill; round-crop notes; player later) | gui/media.go videoBubble | P1 |
| Voice message | Waveform bubble, play, speed, transcribe | PARTIAL (play badge + duration/size bubble, tap downloads; playback/waveform later) | gui/media.go voiceBubble | P1 |
| Audio file | Music player bubble (title/artist, seek) | PARTIAL (title/duration/size row; playback later) | gui/media.go audioBubble | P2 |
| Document/file | Filename, size, progress download bar | PARTIAL (file row + live byte counter + progress bar + tap/cancel/retry) | gui/media.go fileBubble + downloadRow | P0 |
| Sticker (animated) | Big transparent sticker, tap = reaction | CORE-ONLY | engine sticker files (CORE-ONLY) | P1 |
| Animated custom emoji | Inline animated emoji | CORE-ONLY | engine.GetCustomEmojiFiles (CORE-ONLY) | P2 |
| Poll | Question+options, vote, results bars, retract | CORE-ONLY | engine.CreatePoll/VotePoll/VotePollMulti/RetractPollVote/StopPoll (all CORE-ONLY) | P1 |
| Location / live location | Map thumbnail, "open in maps" | CORE-ONLY | engine.SendLocation/GetMapTile (CORE-ONLY) | P2 |
| Contact card | vCard bubble w/ add-contact button | CORE-ONLY | engine.SendContact (CORE-ONLY) | P2 |
| Dice/emoji games | 🎲 animated result | MISSING | engine stickers_dice_pack ≙ not wired | P3 |
| Webpage/link preview card | Thumb+title+site in bubble | CORE-ONLY | engine.GetWebPagePreview (CORE-ONLY) | P2 |
| Paid messages / paid posts | Stars-priced post wall | CORE-ONLY (PaidPostType field exists) | gui/chat.go + engine payments | P3 |
| Gift / star-gift messages | Gift card bubble | CORE-ONLY | engine.GetStarGifts (CORE-ONLY) | P3 |
| Expired/self-destruct media | TTL photo/video timer | CORE-ONLY | telegram TTL media (CORE-ONLY) | P3 |

## 6. Context menus / message actions — scope: SHARED base (copy/reply/edit/pin/delete); reactions, Ayu submenus, sticker/save actions = TG

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Message context menu (base) | Copy, forward, reply, edit, pin, delete, select, report | PARTIAL (2026-09: right-click menu w/ reply/edit/copy/forward/pin/delete + quick reactions, cursor-anchored; select/report + delete-for-me-vs-all dialog pending) | gui/menu.go + engine Edit/Forward/Pin/Delete/React | P0 |
| Reaction picker in menu | Emoji row at top of menu | PARTIAL (2026-09: quick-reaction row from GetAvailableReactions w/ TG default fallback; full tabbed picker pending) | gui/menu.go menuReactionsRow | P0 |
| Delete dialog w/ "delete for all" | Revoke checkbox | CORE-ONLY | engine.DeleteMessage(revoke) (CORE-ONLY) | P0 |
| Forward picker (share box) | Choose recipients, hide-sender options (Ayu) | PARTIAL (2026-09: same-account chat list picker via layout swap; multi-pick + hide-sender options + comment pending) | gui/menu.go layoutForwardDialog + engine.ForwardMessage | P1 |
| Copy link to message | t.me link copy | MISSING | telegram message links ≙ engine method needed | P2 |
| Save file / save GIF / save sound | Download-to-disk actions | CORE-ONLY | engine media + DownloadFile (CORE-ONLY) | P1 |
| Show in folder / open with | OS integration | MISSING | gui/os layer + engine media paths | P3 |
| Report message flow | Reason picker | CORE-ONLY | engine.ReportMessage (CORE-ONLY) | P2 |
| Translate message | Menu item → inline translated | CORE-ONLY | engine.TranslateText (CORE-ONLY) | P2 |
| Sticker pack info / add | Menu on stickers | CORE-ONLY | engine sticker APIs (CORE-ONLY) | P2 |
| Ayu: "Message details" submenu | Views/shares/dates/size/mime/DC/sticker author | CORE-ONLY | engine has views/reactions stats (CORE-ONLY) | P2 |
| Ayu: "Edits history" | Revision list per message | CORE-ONLY | engine.GetEditRevisions/HasEditRevisions (CORE-ONLY!) | P2 |
| Ayu: "View deleted messages" | Deleted-msgs browser per chat | CORE-ONLY | engine.GetDeletedMessages (CORE-ONLY!) | P2 |
| Ayu: "Hide message" (local) | Locally hide a message | MISSING | new engine method + ayu DB | P2 |
| Ayu: "Repeat message" (resend) | Resend w/o forward mark | MISSING | new engine method | P2 |
| Ayu: quick regex filter add | Tag msg by regex | MISSING | engine (Ayu filters feature) | P3 |

## 7. Right info panel / Profile — scope: SHARED; saved messages, similar channels, bot panel = TG

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Right panel exists | Slide-in 3rd pane (info/media/peer) | MISSING | new gui/profile.go | P0 |
| Profile: cover + avatar + name + status | Big header w/ photo | CORE-ONLY | engine.GetUserProfile (CORE-ONLY) | P0 |
| Profile: bio/phone/username rows + copy | Info rows w/ icons | CORE-ONLY | engine.GetUser (CORE-ONLY) | P0 |
| Profile: actions (add contact, share, block, edit) | Button rows | CORE-ONLY | engine AddContact/BlockUser/Unblock (CORE-ONLY) | P1 |
| Shared media tabs | Photos/Videos/Files/Links/Voice/GIFs grids w/ counts | CORE-ONLY | engine.GetSharedMedia/GetSharedMediaCounts (CORE-ONLY!) | P1 |
| Members list (groups) | Searchable, roles, admin badges | CORE-ONLY | engine.GetChatMembers/ByRole (CORE-ONLY) | P1 |
| Member context menu | Promote/restrict/ban/remove | CORE-ONLY | engine admin methods (CORE-ONLY) | P2 |
| Notifications toggle in panel | Per-chat mute switch | CORE-ONLY | engine.MuteChat (CORE-ONLY) | P1 |
| Reactions/views list | Who reacted w/ which emoji | CORE-ONLY | engine.GetMessageReactorsList (CORE-ONLY) | P2 |
| Common groups | Shared chats w/ user | CORE-ONLY | engine.GetCommonChats (CORE-ONLY) | P3 |
| Saved Messages | Own chat + saved sublists + tags | CORE-ONLY | engine.OpenSavedMessages/GetSavedSublists (CORE-ONLY) | P2 |
| Poll results panel | Votes per option | MISSING | engine poll APIs | P2 |
| Bot info panel | Bot description + commands | CORE-ONLY | engine.GetBotManageInfo (CORE-ONLY) | P3 |

## 8. Settings — scope: SHARED shell; folders/premium/stars/business/passport sections = TG

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Settings screen (section list) | Left-rail sections + content pages | PRESENT (rail + 7 sections, gear entry in sidebar, narrow = chip row) | gui/settings.go | P0 |
| Main: edit profile (name, bio, birthday, phone, usernames, photos) | Profile editor page | CORE-ONLY | engine.UpdateBio/UpdateBirthday/UploadProfilePhoto/UpdateAccountUsername (all CORE-ONLY) | P1 |
| Notifications section | Per-type toggles, sound picker, exceptions, reactions notify | PARTIAL (global DM/group/mention toggles + per-account contact-signup/calls toggles; sound/exceptions later) | gui/settings.go + engine config/notifications | P1 |
| Privacy & security | Blocked users, sessions, passcode, 2FA, TTLs, privacy scopes | PARTIAL (blocked users + active sessions listed per account; passcode/2FA/TTL later) | gui/settings.go + engine GetBlockedUsers/GetSessions | P1 |
| Data & storage | Storage usage bars, auto-download rules, download path, proxy | PARTIAL (total + 6 tag rows w/ per-tag and total clears, real cache accounting; auto-download rules/proxy later) | gui/settings.go + engine cache APIs | P1 |
| Appearance | Day/night, themes (cloud), accent, bubble corners, font scale | PARTIAL (day/night toggle persisted via config + light palette; cloud themes/accent/font scale later) | gui/theme.go + gui/settings.go | P1 |
| Chat settings | folders, stickers/emoji managers, link preview, message actions | CORE-ONLY | engine sticker managers (CORE-ONLY) | P2 |
| Calls settings | devices, noise suppression | CORE-ONLY | engine.GetAudioDevices/SetNoiseSuppression (CORE-ONLY) | P2 |
| Language | Language box + lang pack switch | CORE-ONLY | engine.GetLanguages/SetLanguage (CORE-ONLY) | P2 |
| Folders settings | Folder CRUD + suggested folders + chatlist invites | CORE-ONLY | engine folder CRUD (CORE-ONLY) | P2 |
| Premium section | Premium features + local premium (Ayu) | CORE-ONLY | engine.GetPremiumFeatures (CORE-ONLY) | P2 |
| Stars/credits/gifts | Stars balance, transactions, gifting | CORE-ONLY | engine stars APIs (CORE-ONLY) | P3 |
| Business section | away/greeting/quick replies/chat links | CORE-ONLY | engine business APIs (CORE-ONLY) | P3 |
| Power saving | Power-saving toggles | CORE-ONLY | engine.SetPowerSaving (CORE-ONLY) | P3 |
| Advanced + experimental | Debug/experimental flags | CORE-ONLY | engine.SetExperimentalFlag (CORE-ONLY) | P3 |
| Local passcode lock | Lock app w/ passcode + autolock | CORE-ONLY | engine.SetPasscode/GetPasscodeConfig (CORE-ONLY) | P2 |
| Export data (chat history dump) | Export wizard w/ progress | CORE-ONLY | engine export.go full pipeline (CORE-ONLY!) | P2 |
| About / FAQ | About box, versions, shortcuts | PARTIAL (static about page; versions/shortcuts later) | gui/settings.go | P2 |
| Ayu preferences (own screen) | Ghost/spy/saving sections w/ ~90 toggles | PARTIAL (Ayu section: 9 global ghost toggles + per-account overrides + reset; spy/saving sections later) | gui/settings.go Ayu section + engine GhostFlags/SetAccountGhost | P1 |

## 9. Calls / Voice — scope: TG (voice-mode surfaces for other backends via wrtc)

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Voice tab / call list | Calls list in drawer + calls box | PARTIAL (Voice tab lists active group calls only, honest empty state) | gui/voice.go + engine.GetCallHistory (CORE-ONLY) | P1 |
| 1:1 call panel | Accept/decline, call window, signal bars, emoji fingerprint | CORE-ONLY | engine.StartCall/AcceptCall/DeclineCall (CORE-ONLY) + wrtc | P1 |
| Group call screen | Speaker grid, mute, camera, screen share, raise hand, invite, recording, title, RTMP | CORE-ONLY | engine group-call APIs are COMPLETE (Join/RaiseHand/ScreenShare/RTMP/devices…) (CORE-ONLY) | P1 |
| Mic/speaker device pickers | Device dropdowns | CORE-ONLY | engine.GetAudioDevices/SetCallAudioDevice (CORE-ONLY) | P2 |
| Call rating dialog | Rate after call | CORE-ONLY | engine.SendCallRating (CORE-ONLY) | P3 |
| Incoming call UI | Ringing overlay w/ accept/decline | CORE-ONLY | engine.EventIncomingCall (unused!) | P1 |
| Video bubbles + PiP | Floating video, picture-in-picture | CORE-ONLY | engine video-frame APIs (CORE-ONLY) | P3 |
| Call in chat header bar | Active call bar | MISSING | (see chat view row) | P1 |

## 10. Ayu-specific extras (the differentiators) — scope: TG

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Ghost mode (flexible, per-account + global) | Toggle in drawer/tray, shift-click → settings; blocks read receipts/presence/typing | CORE-ONLY (engine GhostFlags + SetAccountGhost + utils config + MarkChatRead already respect it; zero UI) | new gui/menu.go toggle + gui/settings_ayu.go | P0 |
| Ghost sub-flags w/ lock | sendReadMessages/Stories/OnlinePackets/UploadProgress/OfflineAfterOnline, markReadAfterAction, useScheduledMessages, locked variants | CORE-ONLY (all flags exist in utils AppConfig) | gui/settings_ayu.go | P1 |
| LRead / SRead drawer toggles | Local-read vs send-read quick toggles | CORE-ONLY (MarkChatRead ghost-aware; SetAccountGhost exists; no toggles) | gui/menu.go + engine.SetAccountGhost/GhostFor | P1 |
| Anti-recall (save deleted) | Deleted msgs kept, semi-transparent + custom mark, clear per chat | PARTIAL (GUI renders "— deleted" text; engine SetAntiRecallSettings/GetDeletedMessages CORE-ONLY; no Ayu styling/marks) | gui/chat.go + engine | P1 |
| Message edit history | Revisions viewer | CORE-ONLY | engine.GetEditRevisions (CORE-ONLY) | P2 |
| Streamer mode | Blur names/photos on stream, tray toggle | MISSING (no core equivalent) | new engine flag + gui overlay | P2 |
| Local Telegram Premium | Unlock premium perks locally | MISSING | engine premium APIs exist; local-premium flag new | P3 |
| Ayu translator | Provider-based inline translation | CORE-ONLY | engine.TranslateText (CORE-ONLY) | P2 |
| Message shot | Export a message screenshot as image | MISSING (no core; needs renderer) | gui render-to-image | P3 |
| Ayu message filters (regex) | Hide msgs by regex/author | MISSING | new engine feature | P3 |
| Forward options (Ayu rich) | Hide sender/captions when forwarding | CORE-ONLY | engine.ForwardMessage dropAuthor param (CORE-ONLY) | P1 |
| Shadow ban list | Per-chat local shadowban + quick menu | MISSING | new engine feature | P3 |
| Drawer customization | Show/hide each drawer item | MISSING | gui/menu.go + settings_ayu | P2 |
| Font customization + mono font | Font selector box | PARTIAL (font scale only in config, not exposed) | gui/theme.go + settings | P2 |
| App icon selector | Alternative app icons | MISSING | P3 (platform-dependent) | P3 |
| Ayu deleted/edited mark strings | Customizable marks | MISSING | settings_ayu | P2 |
| Hide similar channels / ads / stories | Toggle sponsored & similar | MISSING | settings_ayu + engine | P3 |
| Wide multiplier / bubble radius / avatar corners | Layout tweak sliders | MISSING | gui/theme.go | P3 |
| Ayu toasts + logo/userpic styling | Visual polish | PARTIAL (toast exists) | gui | P3 |
| Ayu sqlite local DB (history storage) | Own local store for deleted/edits | CORE-ONLY (engine SQLite cache_msgs has IsDeleted/EditedAt — same role) | engine | — |

## 11. Search — scope: SHARED

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Global chat search | Finds chats by title/username across server | CORE-ONLY (local filter only) | engine.SearchGlobalChats (CORE-ONLY) | P0 |
| Global message search | All-chats message results w/ preview | CORE-ONLY | engine.SearchMessages (CORE-ONLY) | P1 |
| Search in current chat | In-chat results + jump + calendar picker | CORE-ONLY | engine.SearchMessages(chatID) (CORE-ONLY) | P1 |
| Search by sender/from | Filter "from user" | CORE-ONLY | engine search senderID param (CORE-ONLY) | P2 |
| Search posts in public channels | Global post search | CORE-ONLY | engine.SearchGlobalPosts (CORE-ONLY) | P3 |
| Hashtag/tag search | Filter by tag | MISSING | new engine search filter | P3 |

## 12. Media viewer — scope: SHARED (story viewer = TG)

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Full-screen overlay | Photo/video/doc viewer w/ caption | CORE-ONLY | new gui/mediaview.go + engine media (CORE-ONLY) | P0 |
| Prev/next + group thumbs | Navigate album/chat media | CORE-ONLY | engine.GetSharedMedia | P1 |
| Playback controls (video) | Play/pause/seek/volume/fullscreen | MISSING | gui/mediaview.go + engine media streaming | P1 |
| Zoom/pan + double-click | Gesture zoom | MISSING | gui/mediaview.go | P2 |
| Download + share + delete in viewer | Toolbar actions | MISSING | engine media ops | P1 |
| PiP floating window | Video in floating window | MISSING | gui/os window + engine video frames | P3 |
| Story viewer | Full story playback w/ reactions/reply/share | CORE-ONLY | engine stories (CORE-ONLY) | P2 |
| Streaming video in chat | Playback without full download | CORE-ONLY | engine media streaming (CORE-ONLY) | P2 |

## 13. Notifications — scope: SHARED (per-account notify config = TG)

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| In-app toast | Transient bottom message | PRESENT | gui/app.go layoutToast | P0 |
| System desktop notifications | Native banners + sounds + actions | CORE-ONLY | engine notifications config (CORE-ONLY) + gui/os layer | P1 |
| Tray icon + tray menu (w/ ghost/streamer toggles, accounts) | Sys-tray integration | MISSING | new gui/tray.go (Gio has no tray; needs platform shim) | P2 |
| Unread badge on taskbar/dock | Count badge | MISSING | platform-specific | P2 |
| Per-chat notification settings UI | Mute duration picker, exceptions | CORE-ONLY | engine notify settings APIs (CORE-ONLY) | P2 |
| Notification content privacy | Show/hide message text in banner | MISSING | engine notify config | P2 |

## 14. Misc / platform — scope: mixed (tagged inline where TG-specific)

| Feature | AyuGram does | Status | Where | Pri |
|---|---|---|---|---|
| Keyboard shortcuts | Ctrl+F search, Ctrl+up/down chat switch, Esc close, etc. | MISSING | gui key handling | P2 |
| Multi-window chats | Separate chat windows | MISSING | gui multi-window support | P3 |
| Lock on autolock timer | Passcode relock | CORE-ONLY | engine passcode (CORE-ONLY) | P2 |
| Deep links (tg://) | URL handling for join/phone | MISSING | engine ayu_url_handlers ≙ new resolver | P3 |
| Bot mini-apps (webview panels) | Web apps inside chat | CORE-ONLY (pure-Go constraint: needs embedded webview ≙ decision required) | engine.RequestBotWebView (CORE-ONLY) | P3 |
| Instant View pages | IV reader overlay | CORE-ONLY | engine.GetInstantViewPage (CORE-ONLY) | P3 |
| Channel statistics screens | Charts dashboards | CORE-ONLY | engine stats APIs (CORE-ONLY) | P3 |
| Moderation (admin log, restrictions) | Admin log viewer, restrict boxes | CORE-ONLY | engine GetAdminLogEvents/Restrict (CORE-ONLY) | P3 |
| Join via invite link / QR | Check+import invite | CORE-ONLY | engine.CheckChatInvite/ImportChatInvite (CORE-ONLY) | P2 |
| Giveaways / boosts | Launch & view giveaway flows | CORE-ONLY | engine giveaway APIs (CORE-ONLY) | P3 |
| Contacts list screen | Browse contacts, add contact box | CORE-ONLY | engine.GetContacts/AddContact (CORE-ONLY) | P1 |
| New chat/group/channel creation flow | Multi-step wizards w/ member picker | CORE-ONLY | engine.CreateGroup/CreateChannel/CreateMegagroup (CORE-ONLY) | P1 |
| UniClient: unified multi-account list | (not in Ayu) all backends in one list | PRESENT | gui/sidebar.go | — |
| UniClient: Chat/Voice mode tabs | (not in Ayu, mandated §1.9) | PRESENT | gui/sidebar.go layoutModeTabs | — |

---

## Top 20 gaps (ranked, P0s first)

1. **Message context menu** — reply/edit/pin/delete(for-all)/forward/copy/report/react. All engine methods exist (CORE-ONLY). `gui/menu.go` + `chat.go`.
   → 2026-09-08: SHIPPED (first pass) — right-click menu + quick reactions + delete w/ revoke=own; select/report/for-all dialog remain.
2. **Reactions** — display strip, picker, own-highlight. `engine.ReactToMessage` + `GetAvailableReactions` ready. `gui/chat.go`.
   → 2026-09-08: SHIPPED (first pass) — strip + persistence (reactions_json, cores.UpdateReactions, optimistic toggle) + quick row; custom-emoji pills + full picker remain.
3. **Media bubbles + download** — photo/video/voice/file rendering with progress. Engine media pipeline + `EventDownloadProgress` ready. `gui/chat.go`.
4. **Settings screen** — nothing exists; Ayu's biggest visible surface. Engine has nearly every backend call. `gui/settings.go`.
5. **Right info panel** — profile, bio/username rows, shared-media tabs, members, mute toggle. `gui/profile.go` + engine profile/media APIs.
6. **Attach menu + uploads + voice recording** — 📎 menu, albums, captions. `engine.UploadFile/SendMediaAlbum` ready.
7. **Reply & forward headers in bubbles** — quoted reply block, "forwarded from". `CachedMessage` fields already present.
   → 2026-09-08: SHIPPED.
8. **Composer reply/edit modes** — header chip above input. `SendMessage(replyToID)` + `EditMessage` ready.
   → 2026-09-08: SHIPPED.
9. **Server folder sync + folder CRUD** — replace hardcoded tabs with `engine.GetFolders` + editor dialog + chat-row "add to folder".
10. **Real image avatars** — render `ChatInfo.AvatarPath`; engine downloader exists (letters today).
11. **Ghost mode UI** — drawer toggle + Ayu preferences screen. Engine ghost flags fully modeled (utils AppConfig) but unreachable.
12. **Global search** — server chats+messages search w/ results screen. `engine.SearchChats/SearchMessages/SearchGlobalChats` ready.
13. **Scroll-up history pagination** — load older pages on scroll-top; `loadedOlder` state exists but is dead.
14. **Chat-row context menu** — mute/pin/archive/mark-unread/folders/leave/delete. Engine methods all CORE-ONLY.
15. **Emoji/sticker/GIF picker** — tabbed panel; engine sticker/GIF APIs are exhaustive.
16. **Pinned bar + unread separator + jump-to-message** — chat-view chrome; `GetPinnedMessages` ready.
17. **Peer header extras** — "..." menu, verified badge, join button for channels, group-call bar.
18. **Scheduled messages** — send-later menu + scheduled list; engine methods ready.
19. **Desktop notifications** — banners + per-chat settings; engine notify config ready.
20. **Chat creation flows** — new group/channel/contacts screens; engine Create* ready.

## Counts (201 feature rows)

- PRESENT: 12 (6%) — login machine, QR, day dividers, ticks, typing, toast, composer, scrolling basics, mode tabs, unified list
- PARTIAL: 16 (8%) — folder tabs, chat rows, bubbles, sidebar search, voice tab, deleted marker, signup, 2-pane layout, account bar
- MISSING: 48 (24%) — needs new core work: streamer mode, message shot, regex filters, shadow ban, tray, passcode UI, deep links, selection mode, Ayu prefs shell…
- CORE-ONLY: 125 (62%) — the engine already has the functionality; the GUI just never surfaces it

Priorities: P0 36 · P1 57 · P2 62 · P3 43 (+3 UniClient-only rows).

**Headline finding:** ~62% of AyuGram parity is pure-GUI work over existing
engine/telegram-core methods (reactions, folders, media, profile, settings,
search, ghost, scheduled, calls, stories, admin…). The telegram core is
feature-deep (1323 methods, all Core-interface ops implemented); the Gio GUI
is a minimal 2-pane skeleton (~2.9k lines) that uses only 13 engine methods.
