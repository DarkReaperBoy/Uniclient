# GUI Checklist

**BEFORE STARTING ANY WORK: Read `CLAUDE.md` and obey ALL its rules.**

## Bugs (user-reported, fix first)

- [ ] **Forward display broken** — Forward works server-side (message appears in AyuGram) but forwarded message doesn't show in UniClient's destination chat. Cache refresh issue.
- [ ] **Pinned bar jump inaccurate** — Clicking pinned bar jumps to wrong messages instead of the pinned message. The jumpToMessage timestamp math needs fixing.
- [ ] **No sender avatars in group bubbles** — AyuGram shows sender profile pics next to messages in groups. UniClient doesn't.

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

## Done

- [x] Responsive shell layout (UniClientShell) — OneColumn/TwoColumn/ThreeColumn modes
- [x] Chat list sidebar (ChatListPanel) — search, sorted chat rows
- [x] Chat list row (ChatListRow) — 62px, avatars, titles, timestamps, badges, previews
- [x] Hamburger drawer (HamburgerDrawer) — profile cover (134px), collapsible account switcher, menu items, night mode
- [x] Chat view (ChatView) — top bar, message list, compose area
- [x] Message bubbles (MessageBubble) — incoming/outgoing, sender colors, replies, reactions
- [x] Auth screen (AuthScreen) — method choice, phone/OTP/2FA input, QR code
- [x] Column resize handles — drag to resize dialogs column
- [x] Context menu on chat rows — pin, mute, archive, read, leave
- [x] Empty states — no chats, no messages, no account
- [x] IsOutgoing propagation — Go Core → Engine cache → Protobuf → Dart → UI
- [x] Message loading fix — fetch live from core when cache has fewer than `limit` messages
- [x] SQLite schema migration V2 — `is_outgoing` column
- [x] Cross-platform outgoing detection — Telegram (msg.Out), Bale (sender == self), all other cores
- [x] Folder tabs (FilterColumn, 72px sidebar) — when active account has folders
- [x] Horizontal folder tab strip (when sidebar hidden)
- [x] Chat row: send state icons (check for outgoing messages)
- [x] Info panel (third column) — user/group/channel info, members list, shared media links
- [x] Per-account isolation — one active account at a time, chosen via hamburger drawer
- [x] Folder scoping — folders only shown for the active account
- [x] Account switcher — profile cover + expand arrow, platform icons, connection dots, checkmark on active
- [x] Media rendering in messages — auto-download photos, video placeholders, voice waveform, audio/file indicators
- [x] Media download pipeline — engine MediaManager, auto-download, Telegram access hash persistence, DB schema V4
- [x] Chat list column width — default ratio 0.17 (~300px on 1920)
- [x] Avatar/profile picture download — Telegram DownloadChatAvatar, cached to disk, DB avatar_path, Image.file rendering
- [x] Folder filtering fix — full Telegram filter flag support (contacts, non_contacts, groups, channels, bots, exclude_muted/read/archived) + DialogFilterChatlist support
- [x] Chat row: online dot indicator — green dot on DM avatars via UserStatusEvent stream + Telegram OnUserStatus handler
- [x] Pinned message bar — engine GetPinnedMessages with InputMessagesFilterPinned, ChatState integration, _PinnedBar widget
- [x] Selection mode (multi-select messages) — long-press to enter, checkboxes, selection bar with copy/delete/forward
- [x] Forward dialog — searchable chat picker, forwardSingle from context menu
- [x] Message context menu — right-click/long-press popup (reply, copy, forward, select, edit, delete)
- [x] Dialog pagination — GetDialogs paginates up to 500, first 100 fast + background rest
- [x] Reply display — sent replies show reply_to_id + reply_preview in bubbles
- [x] New chat auto-creation — ensureChatExists when message arrives for uncached chat
- [x] DB corruption fix — ensureChatExists type integer fix + cleanup on startup
