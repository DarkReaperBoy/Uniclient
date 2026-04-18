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

- [x] **Last seen / online in DM top bar verified** — Screenshot-verified: online users show "online" in green, offline show "last seen yesterday at 16:57" etc. Fix: `convertUser` emits `UpdateUserStatus` for all status kinds (online/offline/recently/within_week/within_month/long_ago), seeding the engine cache on initial dialog load instead of waiting for a delta.
- [x] **Forward display fixed** — Forwarded messages now show "Forwarded from {name}" header. Fixed: Go `convertMessage` resolves `FwdFrom` to display name (FromName > cached user/channel name > PostAuthor > fallback). Added `channelNames` cache. Migration made idempotent.
- [x] **Pinned bar jump verified** — Clicking pinned bar scrolls to pinned message; scroll-to-bottom button (with unread badge) returns to newest via `returnToLatest()`. Screenshot-verified in group chat "انجمن اینترنت و فیلترشکن".
- [x] **Sender avatars verified** — 33px circles with letter initials render next to each sender's first message in group chats. Screenshot-verified.
- [x] **Sender profile popup verified** — Tapping sender avatar opens compact horizontal card (avatar + name + ID + "Send Message" action). Screenshot-verified.
- [ ] **Sender avatars for basic groups (cannot verify — no basic groups in account)** — Go `GetMembers` falls back to `MessagesGetFullChat` for basic groups. Dart paginates up to 1000 members. Code path compiles but cannot be visually verified because the active Telegram account has no basic groups (all tele chats in cache are supergroups/channels with `-100...` ID prefix). Verification deferred until a basic group is available.
- [x] **Sender avatars fallback for no-photo users** — Users with no profile photo show colored letter initials. Correct behavior, not a bug (closes item).
- [x] **Top bar avatar verified** — Chat avatar in top bar uses real photo from `avatarPath` when available and falls back to colored letter avatar. Screenshot-verified in "انجمن اینترنت و فیلترشکن" (colorful logo matches sidebar) and "Nakoshi's Diary" (real photo). Top bar avatar stays consistent with sidebar avatar across chats.

## TODO (features not yet implemented)

### Folder management
- [ ] Right-click folder tab → edit folder (include/exclude chats, sync to Telegram)
- [ ] Right-click chat → "Add to folder" submenu (choose folders to add/remove)

### Chat row enhancements
- [ ] Stories ring on avatars
- [ ] Mini media previews in message preview
- [ ] Auto-delete indicator ("1d", "1w" etc.) on DMs with auto-delete enabled

### Chat view / DM
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

- [x] Responsive shell layout (UniClientShell) — OneColumn/TwoColumn/ThreeColumn modes — Screenshot-verified at three widths via kdotool resizing: (1) **OneColumn** at ~490px shows single panel with horizontal folder tabs + hamburger; opening a chat replaces list with chat view + back arrow (slide navigation working). (2) **TwoColumn** at ~1280px shows 72px filter sidebar + dialogs column + chat view. (3) **ThreeColumn** at 1400px after tapping top-bar info icon adds right-side Group Info panel (avatar, ID, Notifications toggle, media tabs, Members). Breakpoints: `_oneColumnBreak=640`, `_threeColumnBreak=932` in `dart/lib/ui/shell.dart`.
- [x] **Chat list sidebar (ChatListPanel) verified** — Screenshot-verified at 1280px: rounded search field with search icon and hamburger (3-column mode hides it, OneColumn shows it). Tapping search focuses the field and reveals a "Cancel" button at the right. Chat rows sort correctly — two pinned chats ("Nakoshi's..." and "./Suburb...") with pin icon appear at the top, followed by non-pinned rows in lastMsgTime descending order (05:22, 05:22, 05:10, 04:58, 04:41, 04:39, 04:06, 03:56, 03:49, 03:39). Search wiring: `searchChats(query)` → engine `SearchChats` RPC → `_searchResults` replaces the visible list (`dart/lib/ui/chat_list_panel.dart:39`).
- [x] **Chat list row (ChatListRow) verified** — Screenshot-verified in active and inactive states. 62px row height, 46px circular avatar at left (real photo + colored letter-initials fallback), chat-type icon (people/megaphone) before title, bold title, right-aligned timestamp ("Yesterday"/"05:35"/etc), sender prefix in blue (`#168acd`), unread badge pill in primary blue (or white when active), pin icon on pinned chats. Active row now renders spec color `#419fd9` (Telegram blue) with white text — verified pixel-exact at `(80, y=180..220) = (65, 159, 217)`. Fix: swapped `Material(color: theme.colorScheme.primary)` for `Container(color: const Color(0xFF419fd9)) + Material.transparency + InkWell` to bypass MD3 Material surface-tint washing `Material(color: primary)` toward white inside a `ColorScheme.dark` scaffold. `dart/lib/ui/chat_list_row.dart:35`.
- [x] **Hamburger drawer (HamburgerDrawer) verified** — Screenshot-verified at 1280px: 274px-wide drawer opens from top-left hamburger icon. Profile cover (134px) shows active account avatar (letter fallback "F" for Fallen Reaper), green connection dot, name + platform ("Telegram"), expand arrow. Tapping arrow expands account list (max 320px scrollable) showing all accounts with platform icons (send/telegram, chat/bale), connection dots, and blue checkmark on active account. Menu items: My Profile, New Group, New Channel, Contacts, Calls, Saved Messages, Settings. Night Mode toggle with moon/sun icon swaps between dark and light theme live (verified background colors change). Version footer "UniClient v0.1.0" at bottom. `dart/lib/ui/hamburger_drawer.dart`.
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
