# GUI Checklist

**BEFORE STARTING ANY WORK: Read `CLAUDE.md` and obey ALL its rules.**

## MANDATORY: Research-first, AyuGram Desktop 1:1

**Every UI feature MUST match AyuGram Desktop exactly.** Before implementing anything:
1. Check `research/telegram_desktop_ui.md` for the relevant section
2. If info is missing or insufficient, research AyuGram Desktop source (https://github.com/AyuGram/AyuGramDesktop) and ADD findings to `research/telegram_desktop_ui.md` BEFORE writing any code
3. Never guess how a feature should look or behave — find the real implementation

## MANDATORY: Self-test with automated interaction

**After implementing any change, you MUST test it yourself using the automated interaction pipeline.** See `CLAUDE.md` § GUI Automation Toolkit for full command reference (`flutter_inspect.sh`, `flutter_interact.sh`, `flutter_auth.sh`).

**Workflow:** screenshot → identify coordinates → interact → screenshot → verify result. Do NOT mark anything as done until visually confirmed.

## Bugs (fix first, verify with automated interaction)

- [x] **Forward display fixed** — Forwarded messages now show "Forwarded from {name}" header. Fixed: Go `convertMessage` resolves `FwdFrom` to display name (FromName > cached user/channel name > PostAuthor > fallback). Added `channelNames` cache. Migration made idempotent.
- [ ] **Pinned bar jump partially verified** — Old code visually confirmed (clicking pinned bar loads older messages). Added `returnToLatest()` so scroll-to-bottom reloads newest after a jump — NOT yet visually verified after rebuild.
- [ ] **Sender avatars resized (not verified)** — Code updated from 30px to 33px per spec §5 (skip 40px). Avatar now clickable. Compiles clean but NOT screenshot-verified.
- [ ] **Sender profile popup redesigned (not verified)** — Redesigned as compact horizontal card. Code compiles but NOT screenshot-verified.
- [ ] **Sender avatars for basic groups (not verified)** — Go `GetMembers` now falls back to `MessagesGetFullChat` for basic groups. Dart paginates up to 1000 members. Compiles but NOT verified that avatars actually appear.
- [ ] **Sender avatars still fallback for no-photo users** — Users who don't have a profile photo set will always show letter initials. This is correct behavior, not a bug. Very large channels (1000+ active posters) may still have some fallback avatars for non-recent members.
- [ ] **Top bar avatar** — Chat avatar in top bar now uses real photo from `avatarPath` when available, falls back to colored letter avatar. Needs verification that `avatarPath` is populated for most chats.
- [ ] **flutter_inspect.sh log path** — Script reads from `/tmp/uniclient_stdout.log`, must launch app with `> /tmp/uniclient_stdout.log 2>&1` (not `/tmp/uniclient_log.txt`).

## TODO (features not yet implemented)

### Folder management
- [ ] Right-click folder tab → edit folder (include/exclude chats, sync to Telegram)
- [ ] Right-click chat → "Add to folder" submenu (choose folders to add/remove)

### Chat row enhancements
- [ ] Stories ring on avatars
- [ ] Mini media previews in message preview
- [ ] Auto-delete indicator ("1d", "1w" etc.) on DMs with auto-delete enabled

### Chat view / DM
- [ ] Last seen / online status text in top bar ("last seen recently", "online", etc.)
- [ ] Sticker rendering (static + animated + video stickers)
- [ ] GIF rendering and playback
- [ ] Video playback in messages (currently shows placeholder)
- [ ] Animated/video profile pictures
- [ ] Translate to English button (like AyuGram)
- [ ] Reactions display on messages

### Profile/Info panel
- [ ] Full profile view on clicking top bar: pfp, name, status, action buttons (message/mute/call/more)
- [ ] More menu: auto-delete, edit contact, export chat history, add to folder, block, delete contact
- [ ] Profile music/channel links
- [ ] Phone number, bio, username, birthday, notes, number ID display
- [ ] Media tabs (photos, videos, files, links, voice, GIFs)
- [ ] Edit contact / delete contact / block user actions

### Search
- [ ] Search results (top peers, recent contacts, search tabs)

### Other features
- [ ] Contact status/action bar (add contact, block, report)
- [ ] Group call bar
- [ ] Voice/video message players
- [ ] Emoji/sticker/GIF panel
- [ ] Calls UI
- [ ] Settings screens
- [ ] Mobile (OneColumn) slide navigation

## Needs visual review (implemented but not screenshot-verified against AyuGram)

- [ ] Responsive shell layout (UniClientShell) — OneColumn/TwoColumn/ThreeColumn modes
- [ ] Chat list sidebar (ChatListPanel) — search, sorted chat rows
- [ ] Chat list row (ChatListRow) — 62px, avatars, titles, timestamps, badges, previews
- [ ] Hamburger drawer (HamburgerDrawer) — profile cover (134px), collapsible account switcher, menu items, night mode
- [ ] Chat view (ChatView) — top bar, message list, compose area
- [ ] Message bubbles (MessageBubble) — incoming/outgoing, sender colors, replies, reactions
- [ ] Auth screen (AuthScreen) — method choice, phone/OTP/2FA input, QR code
- [ ] Column resize handles — drag to resize dialogs column
- [ ] Context menu on chat rows — pin, mute, archive, read, leave
- [ ] Empty states — no chats, no messages, no account
- [ ] IsOutgoing propagation — Go Core → Engine cache → Protobuf → Dart → UI
- [ ] Message loading fix — fetch live from core when cache has fewer than `limit` messages
- [ ] SQLite schema migration V2 — `is_outgoing` column
- [ ] Cross-platform outgoing detection — Telegram (msg.Out), Bale (sender == self), all other cores
- [ ] Folder tabs (FilterColumn, 72px sidebar) — when active account has folders
- [ ] Horizontal folder tab strip (when sidebar hidden)
- [ ] Chat row: send state icons (check for outgoing messages)
- [ ] Info panel (third column) — user/group/channel info, members list, shared media links
- [ ] Per-account isolation — one active account at a time, chosen via hamburger drawer
- [ ] Folder scoping — folders only shown for the active account
- [ ] Account switcher — profile cover + expand arrow, platform icons, connection dots, checkmark on active
- [ ] Media rendering in messages — auto-download photos, video placeholders, voice waveform, audio/file indicators
- [ ] Media download pipeline — engine MediaManager, auto-download, Telegram access hash persistence, DB schema V4
- [ ] Chat list column width — default ratio 0.17 (~300px on 1920)
- [ ] Avatar/profile picture download — Telegram DownloadChatAvatar, cached to disk, DB avatar_path, Image.file rendering
- [ ] Folder filtering fix — full Telegram filter flag support (contacts, non_contacts, groups, channels, bots, exclude_muted/read/archived) + DialogFilterChatlist support
- [ ] Chat row: online dot indicator — green dot on DM avatars via UserStatusEvent stream + Telegram OnUserStatus handler
- [ ] Pinned message bar — engine GetPinnedMessages with InputMessagesFilterPinned, ChatState integration, _PinnedBar widget
- [ ] Selection mode (multi-select messages) — long-press to enter, checkboxes, selection bar with copy/delete/forward
- [ ] Forward dialog — searchable chat picker, forwardSingle from context menu
- [ ] Message context menu — right-click/long-press popup (reply, copy, forward, select, edit, delete)
- [ ] Dialog pagination — GetDialogs paginates up to 500, first 100 fast + background rest
- [ ] Reply display — sent replies show reply_to_id + reply_preview in bubbles
- [ ] New chat auto-creation — ensureChatExists when message arrives for uncached chat
- [ ] DB corruption fix — ensureChatExists type integer fix + cleanup on startup
- [ ] Gesture dispatch system — debug command handler supports tap/rightClick/longPress/scroll/type/key via `/tmp/uniclient_debug_cmd.json` for automated UI testing
