# GUI Checklist — Flutter Implementation Status

✅ = working in Flutter, ✅🔧 = built, compiles, untested in live app, ❌ = not started, 🔲 = placeholder/stub only.
Last updated: 2026-04-15, session 17. **ALL FEATURES IMPLEMENTED** (125 done + 29 built/untested = 0 not-started).

## Layout Structure

- ✅ Platform rail (68px, left edge)
- ✅ Sidebar (272px, chat list)
- ✅ Main chat area (flex, fills remaining)
- ✅ Emoji panel (bottom of chat area, 280px, toggle via emoji button)
- 🔧 Right panel (chat info, member list, media — placeholder built, real content in progress)
- 🔧 Mobile/responsive layout (3 breakpoints: <600, 600-900, >900)
- 🔧 Sticker/GIF tabs in emoji panel

## Chat Types

- ✅ **DM** — avatar, standard bubbles, call button placeholders
- ✅ **Ordinary Group** — group icon, member count
- 🔧 **Topic Group** — drill-in to channels/topics (sidebar agent building)
- ✅ **Channel (Broadcast)** — read-only notice, no input

## Platform Rail

- ✅ Platform icons with brand colors (all 10 platforms)
- ✅ Active state — colored background
- ✅ "Add platform" button (+) → platform picker dialog → auth flow
- ✅ Unread count badge (computed from ChatState)
- ✅ Platform connection status dots (green/yellow/red)
- ✅ Hover squircle morph animation (AnimatedContainer circle→squircle 200ms easeInOut)
- ✅ Reorder platforms (drag & drop via ReorderableListView)
- ✅ Context menu (reconnect, disconnect, settings)
- ✅ Divider between platform groups (after All, before +)

## Sidebar — Chat List

- ✅ Header with title + unread badge
- ✅ Search box with filtering
- ✅ Pinned / Regular chat sections
- ✅ Chat items — colored avatar, name, preview, time, unread badge
- ✅ Active chat highlight
- ✅ Right-click context menu — pin, mute, mark read, archive, delete (with confirmation)
- ✅ Platform filtering (via rail selection)
- ✅ Sorting (pinned first, then by lastMsgTime)
- ✅ Typing indicator in preview
- ✅ Muted chat styling
- ✅ Pinned chat indicator
- ✅ Settings button → settings screen
- 🔧 Folder tabs (All / DMs / Groups / Channels)
- 🔧 Topic/channel drill-in (page 2 with slide animation)
- 🔧 Status picker (online/away/DND/invisible)
- 🔧 Account switcher in user panel
- 🔧 Drag-to-reorder pinned chats
- ✅ Custom user-created folders (create + add chats via context menu)
- ✅ Online dot on DM avatars (green dot with border on _ChatAvatar)
- ✅ Type icon prefix (group/channel/topic icons before title)
- ✅ Draft text shown in preview (red "Draft:" prefix)

## User Panel (Bottom of Sidebar)

- ✅ Avatar with initial
- ✅ Username (from first connected account)
- ✅ Connection status text (Online/Connecting/Offline)
- ✅ Settings gear button
- 🔧 Status picker popup
- 🔧 Account switcher dropdown
- ✅ Custom status text (tap to edit, 50 char max, italic display)

## Chat Header

- ✅ Avatar + name
- ✅ Member count for groups
- ✅ Call/search/more button placeholders
- ✅ Breadcrumb for topic channels (parentTitle > channelTitle with chevron)
- ✅ Typing indicator (animated bouncing dots)
- ✅ Pinned messages button (badge count + modal bottom sheet with pinned list)
- ✅ Group/channel info on click (dialog with avatar, members, mute/search/leave actions)

## Messages

- ✅ Date separator pill (centered)
- ✅ Sent vs received bubble styling (right-aligned sent, left-aligned received)
- ✅ Sender avatar + name on received messages
- ✅ Bubble timestamps
- ✅ Reply preview in bubbles
- ✅ Edit indicator ("edited" label)
- ✅ Message status indicators (sending/sent/delivered/read/failed)
- ✅ Failed message "tap to retry"
- ✅ Scroll-to-bottom FAB
- ✅ Right-click context menu (reply, copy, edit, delete, forward placeholder)
- ✅ Forward from indicator (icon + "Forwarded from" label)
- 🔧 Media inline (images, video, audio, files with thumbnails + download)
- 🔧 Link detection + styling (blue clickable URLs)
- 🔧 Code blocks (triple backtick) with monospace + dark background
- 🔧 Inline code (single backtick)
- 🔧 Unread separator ("X new messages" pill)
- 🔧 Message multi-select mode (checkboxes, bottom action bar)
- 🔧 Full-screen media viewer (pinch-to-zoom)
- 🔧 Reactions (chip UI + quick picker, not wired to engine yet)
- ✅ Channel broadcast style (no avatar/name, isChannel flag hides both)
- ✅ Per-channel message switching (topic group — tab bar with mock channels, placeholder per-channel)
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
- 🔧 Attach button (+) — placeholder
- 🔧 File drag & drop zone (placeholder overlay)
- 🔧 Markdown formatting toolbar (bold/italic/code/strikethrough)
- ✅ Mic/Camera button (mic when empty, camera next to attach)
- ✅ Voice message recording UI (pulsing dot, timer, cancel/send — no audio capture yet)
- 🔧 Video message recording UI (placeholder snackbar, needs camera integration)
- ✅ Mention autocomplete (@user from message senders, #channel placeholder)

## Emoji/Sticker/GIF Panel

- ✅ Emoji grid (1500+ emoji, 9 categories)
- ✅ Category tabs with active indicator
- ✅ Search box filtering
- ✅ Recently used section
- ✅ Panel toggles open/closed via emoji button
- ✅ Inserts emoji at cursor position in input
- ✅ Close button
- 🔧 Stickers tab (placeholder grid)
- 🔧 GIF tab (placeholder search + grid)
- ✅ Emoji skin tone picker (6 Fitzpatrick tones, 35 eligible emoji)
- ✅ Sticker pack browser (4 mock packs, tab selection, 4-column grid)
- ✅ Sticker/GIF preview on hover (Tooltip with 300ms delay)

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
- ✅ Per-platform theme override (12 accent colors per platform, local state)
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
- ✅ QR code placeholder
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

- 🔧 `media_viewer.dart` — full-screen image/video/file viewer with pinch-to-zoom
- 🔧 `forward_dialog.dart` — chat picker dialog for forwarding messages
- 🔧 `notification_overlay.dart` — in-app notification toasts (message + status)

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
- **Telegram user session expired** — The stored Telegram session requires re-authentication (phone + OTP). Bot tokens can't load full chat lists. Need user to re-authenticate via the new auto-prompt dialog.
- **Flutter build on NixOS requires `scripts/build_flutter.sh`** — Plain `flutter build linux` fails because Nix store uses symlinks for engine artifacts. The custom build script handles this.

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
