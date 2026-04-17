# GUI Checklist

**BEFORE STARTING ANY WORK: Read `CLAUDE.md` and obey ALL its rules.**

## Bugs

(none currently)

## TODO

- [ ] Chat row: stories ring
- [ ] Chat row: mini media previews in message preview
- [ ] Search results (top peers, recent contacts, search tabs)
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
- [x] Folder filtering fix — full Telegram filter flag support (contacts, non_contacts, groups, channels, bots, exclude_muted/read/archived, exclude_peers, pinned_peers) across Go→proto→Dart pipeline
- [x] Chat row: online dot indicator — green dot on DM avatars via UserStatusEvent stream
- [x] Pinned message bar — engine GetPinnedMessages query, ChatState integration, _PinnedBar widget
- [x] Selection mode (multi-select messages) — long-press to enter, checkboxes, selection bar with copy/delete/forward
- [x] Forward dialog — searchable chat picker, integrated with selection mode
