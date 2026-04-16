# GUI Checklist — Flutter Implementation Status

**STATUS: ALPHA — scaffold exists but many features are placeholders, stubs, or broken.**

✅ = actually working with live data, 🔲 = placeholder/stub (UI exists, no backend), ❌ = not started, 🐛 = known bug.
Last updated: 2026-04-15, session 29.

## CRITICAL BUGS — Fixed in session 24

- ✅ **#24 Notification spam** — Fixed: suppressed notifications for active chat, added 500ms gap.
- ✅ **#25 Platform rail tap broken** — Fixed: `ReorderableDelayedDragStartListener` replaces `DragStartListener` so taps pass through.
- ✅ **#26 User panel shows "User"** — Fixed: `emitAccountList()` after `UpdateAccountDisplay` so Dart gets display name.
- ✅ **#27 Reply preview never shows** — Fixed: engine auto-populates `reply_preview` from cache in `cache_msgs.go`.
- ✅ **#28 "Channels" folder tab cut off** — Fixed: removed icons from tabs, `Expanded` layout fits all 4 tabs.
- ✅ **#29 New messages separator broken** — Fixed: `openedUnreadCount` snapshot saved at chat open time.
- ✅ **#30 Non-Telegram cores show nothing** — Fixed: unified chat list limit raised to 500, drill-in falls back to parentId filter when GetForumTopics returns empty, added JoinChat engine method + UI dialog for IRC.

## BUGS FIXED — Session 25 (full codebase debug audit)

### Dart (4 files)
- ✅ **#31 notifyListeners after dispose** — `chat_state.dart` typing indicator `Future.delayed` callback called `notifyListeners()` on disposed ChangeNotifier. Added `_disposed` guard.
- ✅ **#32 Bridge event stream leak** — `engine_service.dart` never cancelled `_bridge.events.listen()` subscription. Stored and cancelled in dispose. Also missing `_userStatusController.close()`.
- ✅ **#33 Notification toast ignores theme** — `notification_overlay.dart` hardcoded `AppColors.darkSurfaceAlt`/`darkText` etc. Now respects `Theme.of(context).brightness`.
- ✅ **#34 Missing widget keys** — `home_screen.dart` 5 spread-mapped lists (accounts, platforms, members, chat/msg search results) lacked keys → state corruption on reorder. Added `ValueKey`s.
- ✅ **#35 Infinite media gallery auto-load** — `home_screen.dart` `_SharedMediaGallery` used `addPostFrameCallback` in a `shrinkWrap` grid, causing unbounded page loading. Replaced with manual tap trigger.

### Go (11 files)
- ✅ **#36 proto.Marshal nil return** — `bridge.go` discarded marshal errors, returning nil bytes to FFI. Added fallback error bytes.
- ✅ **#37 Vault zero-salt encryption** — `vault.go` `io.ReadFull(rand.Reader, salt)` errors discarded → all-zero salt. Checked errors. Removed dead salt generation in `Save()`.
- ✅ **#38 IRC msgCounter data race** — `irc.go` `int64` accessed from multiple goroutines → `atomic.Int64`.
- ✅ **#39 IRC deadlock** — `irc.go` `handlePart`/`handleKick` acquired `channelsMu→mu` while `handleNickChange` acquired `mu→channelsMu`. Fixed lock ordering.
- ✅ **#40 Mumble msgCounter data race** — `mumble.go` same as IRC → `atomic.Int64`.
- ✅ **#41 Mumble type assertion panic** — `mumble.go` bare `*ecdsa.PrivateKey` assertion → safe comma-ok form.
- ✅ **#42 GitHub nil pointer** — `github.go` `commentToMessage` panics when both user/author absent → fallback empty map.
- ✅ **#43 Compression race** — `compression.go` shared zstd encoder/decoder across goroutines → added mutexes.
- ✅ **#44 TeamSpeak silent parse errors** — `teamspeak.go` 30+ `strconv.Atoi` errors ignored → proper error propagation/skip.
- ✅ **#45 Matrix goroutine leak** — `matrix.go` call timeout goroutine not in WaitGroup → tracked.
- ✅ **#46 Session file corruption** — `session.go` non-atomic `WriteFile` → write-to-tmp + rename.
- ✅ **#47 FileSplit OOM** — `filesplit.go` no upper bound on buffer allocation → capped at 100MB.
- ✅ **#48 Proxy CONNECT parsing** — `proxy.go` fragile byte-offset status check → `strings.Contains(" 200 ")`.
- ✅ **#49 Bridge MkdirAll unchecked** — `bridge.go` `os.MkdirAll` error ignored → checked.

## BUGS FIXED — Session 26 (GUI smoke test + automation)

### Dart (6 files)
- ✅ **#50 UTF-16 crash: lone surrogates from `title[0]`** — sidebar `_ChatAvatar`, chat_view info dialog, and search results extracted first char with `[0]`, splitting emoji surrogate pairs (e.g. 😀 = D83D+DE00). `[0]` yields lone D83D → Skia crash. Fixed: `safeInitial()` in `safe_string.dart` checks for high surrogate and takes both code units.
- ✅ **#51 UTF-16 crash: `.substring()` splits surrogates** — `forward_dialog.dart` truncated message preview with `.substring(0, 120)` and `.substring(0, 40)`, splitting emoji at the boundary. Fixed: `safeTruncate()` backs up one code unit if it would split a pair.
- ✅ **#52 UTF-16: unsanitized proto fields** — `AccountInfo.displayName`, `AuthStateData` (label/hint/error/sentTo/displayName/message), and `SearchResult` (senderName/text/chatTitle) from proto converters lacked `_safeStr()` wrapping. Fixed in `engine_service.dart`.
- ✅ **#53 loadChats() storm on startup** — 18 calls during init because conn_state, account_list, chat_snapshot events all triggered `loadChats()` independently. Fixed: 300ms debounce timer in `chat_state.dart`, reduced to ~3-4 calls.
- ✅ **#54 markChatRead silent fail** — Context menu "mark read" on non-active chats found no messages (only active chat messages in `_messages`). Fixed: always call engine with empty upToMsgId.
- ✅ **#55 notifyListeners/setState after dispose** — Multiple event handlers in `chat_state.dart` and `home_screen.dart` callbacks lacked `_disposed`/`mounted` guards. Added guards to all handlers.
- ✅ **#56 Excessive polling** — 3-second timer called `loadChats()` (full DB roundtrip). Changed to only refresh messages for active chat.

### Go (1 file)
- ✅ **#57 Mumble channel join fails** — `engine.go` `JoinChat()` only had `joiner` (IRC JoinKey) and `roomJoiner` (Matrix JoinRoom) interfaces. Mumble uses `MoveToChannel(uint32)`. Added `channelMover` interface with numeric channel ID parsing.

### Layout (1 file)
- ✅ **#58 Platform rail removed** — Replaced 68px vertical PlatformRail with inline dropdown in sidebar header. Platform switching, connection status, context menu (reconnect/disconnect), and "add platform" all integrated into the sidebar. Saves horizontal space.

## SESSION 27 — Must Fix placeholders wired + cleanup

### New engine method
- ✅ **LeaveChat** — Added `LeaveChat(accountID, chatID)` to Go engine (`engine.go`), proto (`engine.proto` + regenerated `engine.pb.go` + Dart proto), bridge dispatch (`dispatch_engine.go`), Dart service (`engine_service.dart`), and chat state (`chat_state.dart`). Clears local cache (messages/chats/media) and emits `chat_removed` event.

### Must Fix — All 8 items wired (see below)
### Should Fix — 4 items fixed (DM profile, #channel autocomplete, drag-and-drop cleanup, removed stale "new compose" entry)

### Sidebar cleanup
- ✅ **#59 Unused auth_state import** — `sidebar.dart` imported `auth_state.dart` but never used `AuthState`. Removed.
- ✅ **#60 Sidebar delete calls archiveChat** — `_showDeleteConfirmation` in chat context menu called `archiveChat` instead of real delete. Fixed: now calls `chatState.leaveChat()`.
- ✅ **#61 Channel context menu stubs** — Channel item context menu mute/mark-read/delete were snackbar-only. Wired to `chatState.muteChat()`, `chatState.markChatRead()`, and `chatState.leaveChat()` respectively.

### New features
- ✅ **Keyboard shortcuts** — Ctrl+K focuses sidebar search, Escape closes active chat. `CallbackShortcuts` in `home_screen.dart`, search `FocusNode` passed to Sidebar.
- ✅ **Native desktop notifications** — `notify-send` on Linux fires alongside in-app toast for message notifications. Non-blocking, graceful fallback if not installed.
- ✅ **Chat type icons** — Group chats now show a small group icon badge on their avatar (bottom-right). Channels already had campaign icon. DMs keep online dot.
- ✅ **File upload cleanup** — Removed misleading drag-and-drop overlay (Flutter lacks native OS drop support in this version). File upload works via + button (zenity picker) and Ctrl+V paste.

### Data fix
- ✅ **#62 Bale session path collision** — `~/.config/uniclient/sessions/bale` was a 2-byte file (`{}`) instead of a directory, blocking core creation. Removed file and created directory.

## PLACEHOLDERS — Audit (session 26, updated session 27)

Comprehensive audit of all stubs, "coming soon", and empty handlers found in the Dart codebase:

### Must Fix (broken UX — user expects these to work)
- ✅ **Leave/delete chat** — Added `LeaveChat` to engine + bridge + Dart. Confirmation dialog in info panel (home_screen.dart). (session 27)
- ✅ **Media download button** — Saves media to ~/Downloads with dedup naming. (session 27)
- ✅ **"Open with..." button** — Opens with xdg-open/open/cmd per platform. (session 27)
- ✅ **Channel mute** — Wired to `chatState.muteChat()` in channel context menu. (session 27)
- ✅ **Channel mark-read** — Wired to `chatState.markChatRead()` in channel context menu. (session 27)
- ✅ **Channel delete** — Wired to `chatState.leaveChat()` with confirmation dialog. (session 27)
- ✅ **Language picker** — 12-language selection dialog, saves to config. (session 27)
- ✅ **Cache size tile** — Tapping shows clear cache confirmation (reuses existing dialog). (session 27)

### Should Fix (visible stubs users will notice)
- ✅ **DM user profile panel** — Shows user ID and last active time. (session 27)
- ❌ **Video playback** — `media_viewer.dart:289` "Video playback coming soon"
- ❌ **Voice/video calls** — `chat_view.dart:236,246` "coming soon" snackbar
- ✅ **File drag-and-drop** — Removed misleading overlay. Upload via + button (zenity) and Ctrl+V paste already work. (session 27)
- ✅ **QR code auth** — Real `qr_flutter` rendering with auto-refresh polling, Telegram QR login token export. (session 28)
- ✅ **#channel autocomplete** — Pulls group/channel names from chat list. (session 27)

### Nice to Have (deep features, less visible)
- ❌ **Per-topic message loading** — `chat_view.dart:1094` uses 4 hardcoded mock channels
- ❌ **Audio waveform** — `chat_view.dart:1732`, `media_viewer.dart:330` static bars, not real
- ✅ **Sender avatars** — Chat/account/user avatars rendered from cached `avatarPath` files when available, falls back to initials. (session 28)
- ❌ **Channel edit** — `sidebar.dart:1040` "coming soon" snackbar

## MISSING FEATURES — Not Started

- ✅ **System tray** — AppIndicator tray icon on Linux (bundled .so libs), Show/Hide + Quit menu, minimize to tray on close, unread count tooltip. Graceful fallback when unavailable. (session 28)
- ✅ **Native notifications** — `notify-send` on Linux for message notifications. (session 27)
- ✅ **Chat type icons** — Group badge on avatars, channels have campaign icon, DMs have online dot. (session 27)
- ✅ **Telegram folders** — Synced from Telegram's dialog filters via engine `GetFolders`. Shown as folder tabs alongside built-in All/DMs/Groups/Channels. (session 28)
- ❌ **Platform-specific notification sounds** — No distinct sound/vibration per platform.
- ❌ **IRC channel join UI** — No way to browse/join IRC channels from the GUI. Must use CLI.
- ✅ **Multi-account UX** — Per-platform account picker (chip row with connection dots), platform grouping in All view (section headers + counts), platform icon badges on chat avatars. (session 28)
- ❌ **Voice/video calls** — Call buttons show "coming soon" snackbar. No actual call UI.
- ❌ **Voice message recording** — Mic button shows pulsing UI but no actual audio capture.
- ❌ **Real sticker packs** — Sticker tab has 9 hardcoded mock packs. No Telegram/platform sticker sync.
- ❌ **Real GIF search** — GIF tab has 12 hardcoded categories. No Giphy/Tenor/platform GIF API.
- ✅ **Drag & drop file upload** — Removed (Flutter lacks native OS drop in this version). Upload via + and Ctrl+V works. (session 27)
- ❌ **Video message recording** — Camera button shows snackbar placeholder.
- ❌ **Mention autocomplete from real data** — @mention popup uses message sender names, not real member list.
- ❌ **Message search in chat** — Search button opens dialog but FTS5 search may not return results for all platforms.
- ✅ **Keyboard shortcuts** — Ctrl+K focuses search, Escape closes active chat. (session 27)
- ❌ **Accessibility** — No semantic labels, no screen reader support, no focus management.
- ❌ **Distribution packaging** — No Flatpak, AppImage, AUR, .deb, or .rpm packages.

## PLACEHOLDERS — UI Exists, Backend Missing

- 🔲 Sticker tab (mock packs, no real sticker data)
- 🔲 GIF tab (mock categories, no real GIF API)
- 🔲 Voice recording UI (pulsing dot + timer, no audio capture)
- 🔲 Video recording UI (snackbar only)
- 🔲 Drag & drop file overlay (visual only)
- 🔲 Markdown formatting toolbar (wraps text with markers but no rich text rendering in sent messages)
- 🔲 Emoji skin tone picker (works locally but skin tone preference not persisted)
- 🔲 Per-platform theme override (UI exists, not persisted to engine)
- 🔲 Custom user-created folders (local state only, lost on restart)
- 🔲 Online dot on DM avatars (shows for all users, not real presence data)
- 🔲 Draft text in preview (local state only, lost on restart)
- ✅ QR code auth (real qr_flutter rendering with Telegram token export)

## SESSION 29 — Bale auth fix, phantom account removal

### Bugs Fixed
- ✅ **#63 Bale OTP truncated to 5 digits** — `engine/auth.go` set `CodeLength = 5` for Bale but Bale sends 6-digit codes. Flutter TextField `maxLength` silently truncated → "PHONE_CODE_INVALID". Fixed: `CodeLength = 6`.
- ✅ **#64 Failed auth creates phantom accounts** — `sidebar.dart` `showDialog<void>` ignored auth result, leaving fake accounts in the list after failed login. Fixed: `showDialog<bool>`, `Navigator.pop(context, false)` on failure, `appState.removeAccount(id)` on `success != true`.
- ✅ **#65 Bale SubmitOTP race condition** — `select { default: return nil }` in SubmitOTP could return nil before error channel was written. Fixed: blocking `return <-b.authErrCh`.

### Known Bugs (not yet fixed)
- 🐛 **#66 Bale chats don't load** — GetDialogs returns 0 results after WebSocket connect. WS handshake added but RPC calls still return empty. Needs WS lifecycle restructuring.
- 🐛 **#67 Session path conflict** — `sessions/bale` can be file or directory depending on core init order. Causes `SaveSession`/`MkdirAll` failures.

## Bugs Found & Fixed (previous sessions)
- ✅ **Multi-platform chat list wipe** (session 23) — `onChatSnapshot` replaced entire `_chats` with per-account snapshot. Fixed: unified SQLite query.
- ✅ **Sidebar Stack layout** (session 23) — `StackFit.loose` gave Column children `minHeight=0`. Fixed with `StackFit.expand`.

## Layout Structure

- ✅ Platform rail (68px, left edge)
- ✅ Sidebar (272px, chat list)
- ✅ Main chat area (flex, fills remaining)
- ✅ Emoji panel (bottom of chat area, 280px, toggle via emoji button)
- ✅ Right panel (chat info, real member list via engine, shared media gallery with tabs)
- ✅ Mobile/responsive layout (3 breakpoints: <600, 600-900, >900) — back button + nav fixed session 21
- ✅ Sticker/GIF tabs in emoji panel — polished placeholders with categories/search

## Chat Types

- ✅ **DM** — avatar, standard bubbles, call button placeholders
- ✅ **Ordinary Group** — group icon, member count
- ✅ **Topic Group** — drill-in to channels/topics (wired to engine GetForumTopics)
- ✅ **Channel (Broadcast)** — read-only notice, no input

## Platform Rail

- ✅ Platform icons with brand colors (all 10 platforms)
- ✅ Active state — colored background
- ✅ "Add platform" button (+) → platform picker dialog → auth flow
- ✅ Unread count badge (computed from ChatState)
- ✅ Platform connection status dots (green/yellow/red)
- ✅ Hover squircle morph animation (AnimatedContainer circle→squircle 200ms easeInOut)
- ✅ Reorder platforms (drag & drop via ReorderableListView) — **fixed session 24 (#25)**
- ✅ Context menu (reconnect, disconnect, settings)
- ✅ Divider between platform groups (after All, before +)

## Sidebar — Chat List

- ✅ Header with title + unread badge
- ✅ Search box with filtering
- ✅ Pinned / Regular chat sections
- ✅ Chat items — colored avatar, name, preview, time, unread badge
- ✅ Active chat highlight
- ✅ Right-click context menu — pin, mute, mark read, archive, delete (with confirmation)
- ✅ Platform filtering (via rail selection) — **fixed session 24 (#25)**
- ✅ Sorting (pinned first, then by lastMsgTime)
- ✅ Typing indicator in preview
- ✅ Muted chat styling
- ✅ Pinned chat indicator
- ✅ Settings button → settings screen
- ✅ Folder tabs (All / DMs / Groups / Channels) — **fixed session 24 (#28)**
- ✅ Topic/channel drill-in (page 2 with slide animation, wired to engine)
- 🔲 Status picker (online/away/DND/invisible) — local UI state only, not synced to any platform
- 🔲 Account switcher in user panel — platform filter, local state only
- 🔲 Drag-to-reorder pinned chats (ReorderableListView, local state, not persisted)
- 🔲 Custom user-created folders (create + add chats via context menu) — local state, lost on restart
- 🔲 Online dot on DM avatars — shows hardcoded, not real presence data
- ❌ Type icon prefix (DM/group/channel/bot icons) — **missing, all chats look the same (#30 missing)**
- 🔲 Draft text shown in preview — local state, lost on restart

## User Panel (Bottom of Sidebar)

- ✅ Avatar with initial
- ✅ Username — **fixed session 24 (#26)**
- ✅ Connection status text (Online/Connecting/Offline)
- ✅ Settings gear button
- 🔲 Status picker popup — local UI state only, not synced
- 🔲 Account switcher dropdown — local state only
- 🔲 Custom status text — local state, lost on restart

## Chat Header

- ✅ Avatar + name
- ✅ Member count for groups
- ✅ Call buttons (snackbar feedback), search (FTS5 dialog), more (mute/pin/info popup)
- ✅ Breadcrumb for topic channels (parentTitle > channelTitle with chevron)
- ✅ Typing indicator (animated bouncing dots)
- ✅ Pinned messages button (badge count + modal bottom sheet with pinned list)
- ✅ Group/channel info on click (dialog with avatar, members, mute/search/leave actions)

## Messages

- ✅ Date separator pill (centered)
- ✅ Sent vs received bubble styling (right-aligned sent, left-aligned received)
- ✅ Sender avatar + name on received messages
- ✅ Bubble timestamps
- ✅ Reply preview in bubbles — **fixed session 24 (#27)**
- ✅ Edit indicator ("edited" label)
- ✅ Message status indicators (sending/sent/delivered/read/failed)
- ✅ Failed message "tap to retry"
- ✅ Scroll-to-bottom FAB
- ✅ Right-click context menu (reply, copy, edit, delete, forward)
- ✅ Forward from indicator (icon + "Forwarded from" label)
- ✅ Media inline (images, video, audio, files with thumbnails + download)
- ✅ Link detection + styling (blue clickable URLs, opens via xdg-open)
- ✅ Code blocks (triple backtick) with monospace + dark background
- ✅ Inline code (single backtick)
- ✅ Unread separator ("X new messages" pill) — **fixed session 24 (#29)**
- ✅ Message multi-select mode (checkboxes, bulk delete + bulk forward via engine)
- ✅ Full-screen media viewer (pinch-to-zoom)
- ✅ Reactions (chip UI + quick picker, wired to engine ReactToMessage)
- ✅ Channel broadcast style (no avatar/name, isChannel flag hides both)
- 🔲 Per-channel message switching (topic group — tab bar with mock channels, placeholder per-channel)
- ✅ Message hover actions (reply/react/more on desktop hover)

## Input Area

- ✅ Text input with border styling
- ✅ Auto-resize textarea (multiline)
- ✅ Send button (rounded, accent color, changes to checkmark in edit mode)
- ✅ Enter to send, Shift+Enter for newline
- ✅ Emoji button → toggles emoji panel
- ✅ Reply bar (quoted message above input)
- ✅ Edit mode bar (pre-fills text, warning color)
- ✅ Channel read-only notice
- ✅ Double-send prevention (`_sending` guard)
- ✅ Attach button (+) — zenity file picker → engine UploadFile
- ✅ Clipboard image paste (Ctrl+V detects image via xclip, uploads via engine)
- 🔲 Markdown formatting toolbar (wraps text with markers, but sent messages aren't rendered as rich text)
- 🔲 Mic/Camera button (mic shows recording UI but **no actual audio capture**)
- 🔲 Voice message recording UI (pulsing dot + timer, **no audio capture — stub only**)
- 🔲 Video message recording UI (placeholder snackbar only)
- 🔲 Mention autocomplete (@user from message senders, not from real member list)

## Emoji/Sticker/GIF Panel

- ✅ Emoji grid (1500+ emoji, 9 categories)
- ✅ Category tabs with active indicator
- ✅ Search box filtering
- ✅ Recently used section
- ✅ Panel toggles open/closed via emoji button
- ✅ Inserts emoji at cursor position in input
- ✅ Close button
- 🔲 Stickers tab (9 **hardcoded mock** packs, no real sticker data from any platform)
- 🔲 GIF tab (12 **hardcoded mock** categories, no real GIF API)
- ✅ Emoji skin tone picker (6 Fitzpatrick tones, 35 eligible emoji)
- 🔲 Sticker pack browser (4 **mock** packs, no real data)
- 🔲 Sticker/GIF preview on hover (works but shows mock data)

## Context Menus

- ✅ Chat context menu — pin, mute, mark read, archive, delete
- ✅ Delete confirmation dialog
- ✅ Message context menu — reply, copy, edit (own), delete (own), forward
- ✅ Danger items styled red
- ✅ Channel item context menu in drill-in view (mute, mark read, edit, delete)

## Theming

- ✅ Dark theme (charcoal base #101318)
- ✅ Light theme
- ✅ Blue-indigo accent (#4f6ef7)
- ✅ Inter font family
- ✅ Theme picker in settings (dark/light/system)
- ✅ Custom accent color picker (12 preset colors with checkmark selection)
- 🔲 Per-platform theme override (12 accent colors per platform, **local state only, lost on restart**)
- ✅ System theme auto-detect (ThemeMode.system → Flutter handles platform brightness)

## Settings Screen

- ✅ Theme picker (dark/light/system) — persisted to engine
- ✅ Font scale slider (0.5x-2.0x) — persisted to engine
- ✅ Max cache size picker (256MB-5GB) — persisted to engine
- ✅ Privacy toggles (read receipts, typing indicator) — persisted to engine
- ✅ Notification toggles (DMs, groups, mentions only) — persisted to engine
- ✅ Account list with connection state
- ✅ Clear cache button
- ✅ Debug logging toggle
- ✅ Download directory picker (text input dialog, no file_picker dep needed)
- ✅ Account removal from settings (delete icon + confirmation dialog + engine call)

## Auth Flow

- ✅ Full 7-state auth FSM (choose/input/otp/2fa/qr/ready/error)
- ✅ Platform picker dialog
- ✅ Code entry with auto-sizing
- ✅ 2FA recovery option
- ✅ Error display with retry
- 🔲 QR code placeholder (**no real QR generation**)
- ✅ Auto-connect on auth success

## Data Pipeline

- ✅ Protobuf bridge (Go ↔ Dart via FFI)
- ✅ 13 typed event streams (auth, conn, chat, msg, typing, download)
- ✅ Async FFI bridge (Isolate.run for network-hitting ops)
- ✅ NativeCallable.listener for Go→Dart events
- ✅ 3-second polling fallback for event delivery
- ✅ UTF-8 sanitization (Go) + UTF-16 sanitization (Dart)
- ✅ Message pagination (50 per page)
- ✅ Chat list auto-reload on connect/account_list events
- ✅ Media metadata fields in proto (type, name, size, thumb, path, download state)

## New Widgets (session 16)

- ✅ `media_viewer.dart` — full-screen image/video/file viewer with pinch-to-zoom, wired to tap-to-open
- ✅ `forward_dialog.dart` — chat picker dialog for forwarding messages (wired to engine ForwardMessage)
- 🐛 `notification_overlay.dart` — in-app notification toasts (**spams every message, no rate limit, #24**)

## Automated Tests

- ✅ `bridge_test.dart` — 14 tests: FFI, engine init, accounts, config, cache, search, auth
- ✅ `telegram_auth_test.dart` — full live Telegram auth with automated OTP read
- ✅ `telegram_send_test.dart` — auth + send + verify in chat history
- ✅ `widget_test.dart` — 2 tests: loading state, multi-size rendering
- ✅ `widget_comprehensive_test.dart` — 83 tests (models, rendering, interactions, reactions, themes, state)

## Bugs Found & Fixed (Session 18 — Live App Smoke Test)

### Fixed
- **#19 Missing Debug import in chat_state.dart** — `Debug.log` used without importing `debug.dart`. Added import.
- **#20 No auto-re-auth when session expires** — When engine reports `auth_required`, app showed red dot + "No chats yet" with no way to re-authenticate from the main screen. Fixed: HomeScreen now auto-shows AuthScreen dialog when any account enters `authRequired` state.
- **#21 Context menu missing re-auth option** — Platform rail right-click menu only had Reconnect/Disconnect/Settings. When auth is required, Reconnect won't help. Added "Re-authenticate" option that opens the auth dialog directly.
- **#22 Auth-required rail indicator indistinguishable from disconnected** — Both `authRequired` and `disconnected` showed the same red dot. Changed `authRequired` to use warning (orange) color so users can tell the difference.
- **#23 `_bestConnState` didn't detect `authRequired`** — The connection state priority check skipped `authRequired`, falling through to generic `disconnected`. Added explicit check.

### Known Issues
- **Flutter build on NixOS requires `scripts/build_flutter.sh`** — Plain `flutter build linux` fails because Nix store uses symlinks for engine artifacts. The custom build script handles this.
- **Telegram session re-auth** — Session is still valid but engine reports `auth_required` on reconnect (session 19: goes straight to `ready` after phone submit, no OTP needed).

## GUI Automation Toolkit

Three scripts for automated smoke-testing without OS-level mouse/keyboard automation:

### `scripts/flutter_inspect.sh` — See & inspect the UI
Connects to the Flutter VM Service (WebSocket JSON-RPC) exposed by debug builds. Takes screenshots server-side (no display/window focus needed), dumps widget tree, reads text content.
- `screenshot [output.png]` — renders Flutter UI to PNG via `ext.flutter.inspector.screenshot`
- `tree` — full widget tree with inspector IDs
- `find <name>` — find widgets by name
- `details <inspector-ID>` — widget properties
- `text <inspector-ID>` — text content
- Requires: `websocat` (auto-fetched via nix), running debug app

### `scripts/flutter_auth.sh` — Control auth flow
Writes JSON commands to `/tmp/uniclient_auth_cmd.json` which `AuthState` polls every second during auth.
- `status` — show auth state from logs
- `choose <method>` — pick auth method (phone, bot_token, qr)
- `submit <value>` — enter phone/OTP/password/token
- `otp-wait` — poll `auth/otp_code.txt`, auto-submit when found
- `auto <method> [phone]` — full automated flow
- `cancel` — cancel auth

### How the auth automation works internally
`AuthState` (`dart/lib/state/auth_state.dart`) has a `Timer.periodic(1s)` that polls `/tmp/uniclient_auth_cmd.json` whenever `needsInput` is true (states: choose/input/otp/2fa). File format: `{"action":"submit","value":"12345"}`. File is deleted after reading. Polling stops on auth completion/cancel/dispose.

### Window management (KDE Wayland)
`xdotool` doesn't work on Wayland. Use `kdotool` (via `nix-shell -p kdotool`) to find/activate windows by PID. `spectacle -b -n -f -o output.png` for OS-level screenshots. But `flutter_inspect.sh screenshot` is preferred since it doesn't need window focus.
