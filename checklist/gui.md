# GUI Checklist

## Shell Layout & Left Panel (Step 2a — Telegram reference)

### Done
- [x] Responsive shell layout (UniClientShell) — OneColumn/TwoColumn/ThreeColumn modes
- [x] Chat list sidebar (ChatListPanel) — search, platform filters, sorted chat rows
- [x] Chat list row (ChatListRow) — 62px, avatars, titles, timestamps, badges, previews
- [x] Hamburger drawer (HamburgerDrawer) — profile, accounts, menu items, night mode
- [x] Chat view (ChatView) — top bar, message list, compose area
- [x] Message bubbles (MessageBubble) — incoming/outgoing, sender colors, replies, reactions
- [x] Auth screen (AuthScreen) — method choice, phone/OTP/2FA input, QR code
- [x] Platform filter chips — All + per-platform filtering
- [x] Column resize handles — drag to resize dialogs column
- [x] Context menu on chat rows — pin, mute, archive, read, leave
- [x] Empty states — no chats, no messages, no account
- [x] Smoke tested: builds, launches, renders chat list with real data (28 accounts)
- [x] IsOutgoing propagation (Go Core → Engine cache → Protobuf → Dart → UI) — messages now correctly left/right aligned
- [x] Message loading fix: fetch live from core when cache has fewer than `limit` messages (not just when empty)
- [x] SQLite schema migration V2: added `is_outgoing` column
- [x] Cross-platform outgoing detection: Telegram (msg.Out), Bale (sender == self), all other cores

### Bugs Found & Fixed
- **All messages right-aligned**: `message_bubble.dart` was using `message.status` to detect outgoing — always true for cached messages. Fixed by adding `IsOutgoing` bool through entire stack.
- **Bale messages all left-aligned**: `isSent` getter used `senderId.isEmpty` which only works for some platforms. Fixed with proper `IsOutgoing` field per-platform.
- **Large groups loading only partial messages**: Engine only fetched from core when cache was completely empty (`len(msgs) == 0`), but event-stream messages trickled into cache first. Fixed: `len(msgs) < limit`.

### TODO
- [ ] Folder tabs (FilterColumn, 72px sidebar) — when folders exist
- [ ] Horizontal folder tab strip (when sidebar hidden)
- [ ] Chat row: online dot indicator
- [ ] Chat row: stories ring
- [ ] Chat row: mini media previews in message preview
- [ ] Chat row: send state icons (clock/check/double-check)
- [ ] Info panel (third column) — user/group/channel info
- [ ] Search results (top peers, recent contacts, search tabs)
- [ ] Pinned message bar
- [ ] Contact status/action bar (add contact, block, report)
- [ ] Group call bar
- [ ] Selection mode (multi-select messages)
- [ ] Forward dialog
- [ ] Media rendering in messages (photos, videos, stickers)
- [ ] Voice/video message players
- [ ] Emoji/sticker/GIF panel
- [ ] Calls UI
- [ ] Settings screens
- [ ] Mobile (OneColumn) slide navigation
