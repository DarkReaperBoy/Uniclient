# GUI Ideas & Design Exploration

Living document for UI/UX design decisions. Originally prototyped in `demo_ui.html` (deleted — superseded by the real Flutter implementation in `dart/`). These design decisions now drive the actual Flutter widgets.

## Design Philosophy

**Hybrid of Discord and Telegram** — not a clone of either. Take the best patterns from both and merge them into something that feels native to a multi-platform unified client.

### What we took from Discord
- **Platform rail** (left edge) — vertical strip of icons, one per connected platform (Telegram, Discord, Matrix, IRC, XMPP, Mumble). Behaves like Discord's server bar but represents *platforms* not servers. Active icon gets colored ring + platform brand color.
- **Collapsible folder headers** in chat list (DMs / Groups / Channels) — like Discord's channel categories
- **Collapsible channel sections** inside topic groups (Text / Voice) — same pattern as Discord server channels
- **Voice channels with connected member list** — shows who's in a VC right in the sidebar
- **Voice chat text channels** — each VC has its own persistent text chat you can read/write without joining the call (unlike TeamSpeak where you must join VC to see chat)
- **Right panel** — member list, search results, thread view slide out from right side (like Discord's member sidebar)
- **Message hover actions** — reply, react, more appear on hover (Discord-style)
- **Message selection mode** — multi-select with forward/delete toolbar

### What we took from Telegram
- **Chat bubbles** for messages — sent (right-aligned, blue tint), received (left-aligned, dark) with rounded corners
- **Timestamps inside bubbles** (float right) instead of Discord's separate timestamp column
- **Drill-in sidebar navigation** — clicking a group with topics replaces the chat list with channels/topics, back button returns. One panel, not two. Like Telegram mobile's navigation.
- **Author name above received bubbles** (colored) with avatar to the left
- **Sent messages hide avatar** (you know it's you)
- **Channel (broadcast) style** — messages have no user avatar or author name, just content. Read-only for non-admins with a notice at the bottom.
- **Reply/quote** — inline quote bar above the replied message, with colored left border and author name
- **Pinned messages banner** — top banner with pin icon, click to expand (Telegram-style)
- **Typing indicator** — shown in both chat preview (sidebar) and header

### Hybrid originals (neither Discord nor Telegram)
- **Unified dark palette** — not Discord's gray-purple, not Telegram's navy. Neutral deep charcoal (`#101318` base) with blue-indigo accent (`#4f6ef7`)
- **Platform rail replaces server bar concept** — each icon is a whole platform, not a single server
- **Breadcrumb header** — when inside a channel: `Group Name > Channel Name`
- **Rounded everything** — softer border-radius on bubbles (18px), sidebar items (10px), input (14px)
- **Focus ring on input** — blue glow on focus, not just background change
- **Inter font** — modern, clean, not system default
- **Platform connection status** — green/orange/red dot on each rail icon showing connected/connecting/disconnected
- **Unread count badges on rail** — numbered badges, not just dots, so you know how many unreads per platform
- **Drag-to-reorder rail** — rearrange platforms by dragging

## The 4 Chat Types

The demo showcases exactly 4 distinct chat types, each with different UI behavior:

### 1. DM (Direct Message)
- Avatar with online dot, author name, bubbles
- Has voice/video call buttons in header
- Standard input area
- Typing indicator in header when other person is typing

### 2. Ordinary Group
- Group icon prefix, member count in header
- Has voice/video call buttons (group call)
- No drill-in — flat chat, no topics/channels
- Standard bubbles with avatars and author names

### 3. Topic Group (with Voice Chats)
- Drill-in sidebar: clicking opens channel/topic list with back button
- Text channels (`#general`, `#backend`, `#off-topic`) with descriptions
- Voice channels with connected member list
- **Each voice chat has its own text chat** — chat bubble button on VC items opens the VC's persistent text channel. You can read and write without joining the call (unlike TeamSpeak).
- Breadcrumb header shows `Group > Channel`
- Create channel button on each section header

### 4. Channel (Broadcast)
- No user avatar or author name on messages — just content bubbles
- No voice/video call buttons in header
- Shows subscriber count instead of member count
- Input area hidden, replaced with "Only admins can post" notice
- Channel avatar uses a megaphone icon style
- Admin mode toggle to show input area when user is admin
- Exception note: Telegram has a rare mode where admins can show pfp in channels, but we treat it as the uncommon case

## Navigation Model

```
Platform Rail → Chat List (with folders) → [if DM/ordinary group] Messages directly
                                          → [if topic group] Channel List (drill-in) → Messages
                                          → [if channel] Messages (read-only)
```

- Sidebar is **272px**, single column
- Drill-in uses CSS `translateX` animation (0.28s cubic-bezier)
- Back button in channel view header returns to chat list
- User panel persists at bottom across both views
- VC controls bar appears above user panel when connected to voice

## POC Feature Summary

Everything below was prototyped and validated in the HTML demo (now deleted). Most of these are implemented in Flutter — see `checklist/gui.md` for detailed component status.

### Platform Rail
- SVG logos for major platforms, text fallback for others
- Active state with colored bg + ring, hover squircle morph
- Drag-to-reorder, unread count badges, notification dots
- Connection status indicator (green/orange/red)
- Right-click context menu (settings, reconnect, disconnect)

### Sidebar
- Search box with focus ring
- Collapsible folders (DMs / Groups / Channels) with custom folder creation
- Chat items with avatar, name, preview, time, unread badge
- Typing indicator in preview, muted styling (dimmed badge), pinned indicator
- Right-click context menu per chat type (pin, mute, archive, block, delete, leave)
- Channel list with collapsible sections, create channel buttons, info icons
- Channel right-click context menu (mute, mark read, edit)

### Voice Chat Controls
- VC controls bar with: mute, deafen, video, screen share, disconnect
- Connection quality indicator (signal bars)
- Auto-mute when deafened, green highlight for video/screen active

### User Panel
- Avatar, username, online status
- Status picker dropdown (online, away, DND, invisible) with colored dots
- Custom status text input
- Account switcher with multiple accounts
- Settings gear button

### Chat Header
- Avatar + name (adapts per chat type), click to open info overlay
- Status line (online/members/subscribers), typing indicator
- Call buttons (voice + video) for DMs and groups
- Pinned messages button with count badge + collapsible banner
- Search and members buttons open right panel

### Messages
- Date separator pill, unread separator ("X new messages")
- Reply/quote with colored left border and author name
- Emoji reactions (own reactions highlighted)
- Edit indicator ("edited"), deleted message placeholder
- Media placeholders (image, video), file attachments (icon + name + size)
- Link previews (domain, title, description)
- Code blocks with syntax highlighting (keyword, string, function, comment colors)
- Hover actions toolbar (reply, react, more)
- Right-click context menu (reply, react, copy, forward, edit, select, delete)
- Multi-select mode with selection toolbar (forward, delete, cancel)
- Scroll-to-bottom button with unread count

### Input Area
- Attach button (opens file picker), file drag & drop overlay
- Auto-resizing textarea with focus ring
- Inline buttons: formatting toggle, emoji, mic/camera
- Markdown formatting toolbar (bold, italic, strikethrough, code, code block, link)
- Mention autocomplete popup (@user, #channel)
- Reply bar (shows quoted message, closeable)
- Edit mode bar (green accent, pre-fills text)
- Voice/video recording UI (waveform, timer, cancel/send)
- Send button (accent color, hover scale)
- Hidden for channels with "admin mode" toggle

### Emoji/Sticker/GIF Panel
- Three tabs with active indicator
- Search filtering across all tabs
- Emoji: categorized sections (recent, smileys, gestures, symbols, animals), skin tone picker
- Stickers: pack browser tabs, 4-column grid, hover preview
- GIFs: 2-column grid, hover preview with labels

### Right Panel
- Three tabs: Members, Search, Threads
- Members tab: avatar, name, role badge
- Search tab: search input + result list (author, text, time)
- Threads tab: placeholder

### Theming
- Dark theme (charcoal `#101318`) and light theme (Flutter ThemeData)
- Custom accent color picker (12 preset colors)
- System theme auto-detect (MediaQuery.platformBrightness)
- **All theming belongs in a Settings panel** — not floating UI widgets

### Info Overlay
- Click chat header name/avatar to open full-screen info overlay
- Shows large avatar, name, status/member count, about section
- Member list preview for groups

### Responsive
- 768px breakpoint: smaller rail (52px), narrower sidebar (240px)
- 600px breakpoint: rail hidden, sidebar full-width with toggle, panels overlay

## Explored & Rejected Ideas

| Idea | Why rejected |
|------|-------------|
| Toggle between Discord/Telegram modes | Feels gimmicky; hybrid is better than mode-switching |
| Separate channel panel (side-by-side with chat list) | Too wide, wastes space; drill-in is cleaner and more mobile-friendly |
| Discord's flat message style (no bubbles) | Bubbles give better visual separation, especially in groups |
| Many fake example chats | Bloats the demo; 4 purposeful types cover all cases |
| Must join VC to see VC text chat (TeamSpeak style) | Bad UX — you should be able to read VC chat without joining audio |
| Floating theme toggle widget | Belongs in Settings, not cluttering the chat area |

## Flutter Implementation Status

Protobuf bridge is DONE. The Flutter app implements most of the HTML POC design. See `checklist/gui.md` for detailed component status and remaining work.

## GUI Automation Toolkit

Discovered session 18 (2026-04-15). Allows Claude Code to interact with the running Flutter app without OS-level GUI tools.

### Problem
- User is on KDE Wayland — `xdotool` doesn't work
- `ydotool` coordinate mapping is broken with display scaling (1.25x)
- Need to take screenshots, read widget text, and control auth flow programmatically

### Solution: Flutter VM Service Protocol

Flutter debug builds expose a Dart VM Service over HTTP/WebSocket. The URL is printed at startup:
```
The Dart VM service is listening on http://127.0.0.1:PORT/TOKEN=/
```

#### Key extension methods (via WebSocket JSON-RPC)

**Screenshot** — renders the Flutter widget tree to PNG server-side:
```json
{"method": "ext.flutter.inspector.screenshot",
 "params": {"isolateId": "isolates/XXX", "id": "inspector-8",
            "width": 1280, "height": 800, "margin": 0,
            "maxPixelRatio": 2.0, "debugPaint": false}}
```
Response: `{"result": {"result": "<base64 PNG>"}}`

**Widget tree**:
```json
{"method": "ext.flutter.inspector.getRootWidgetSummaryTree",
 "params": {"isolateId": "isolates/XXX", "objectGroup": "inspect"}}
```
Returns full tree with `valueId` (e.g. `inspector-8`), `description`, `children`, `createdByLocalProject`.

**Widget details**:
```json
{"method": "ext.flutter.inspector.getDetailsSubtree",
 "params": {"isolateId": "isolates/XXX", "arg": "inspector-116", "subtreeDepth": 10}}
```
Returns properties including text content (`data`, `text` fields).

#### Isolate discovery
```bash
curl -s "http://127.0.0.1:PORT/TOKEN=/getVM" | jq '.result.isolates[] | select(.isSystemIsolate == false) | .id'
```

#### WebSocket connection
```bash
echo '{"jsonrpc":"2.0","id":"1","method":"...","params":{...}}' | websocat -n1 "ws://127.0.0.1:PORT/TOKEN=/ws"
```

#### Gotchas
- `websocat` default buffer is 64KB — large widget trees get truncated. The `screenshot` response is usually within this limit.
- Inspector IDs (`inspector-N`) change between app restarts. Use the tree to find the right one, or fall back to `inspector-8` (typically the app root).
- `evaluate` (Dart expression evaluation) doesn't work in custom builds — the JIT compilation service isn't available when using `frontend_server` directly.
- HTTP GET works for some methods (`getVM`, `getIsolate`) but extension methods require WebSocket.

### Auth Flow Automation

Instead of fighting with `evaluate`, we built file-based IPC:

- `AuthState` polls `/tmp/uniclient_auth_cmd.json` every 1s when auth needs input
- CLI writes: `{"action":"choose","value":"phone"}` or `{"action":"submit","value":"12345"}`
- App reads, deletes file, processes command
- Same OTP-file pattern as Go integration tests (`auth/otp_code.txt`)

This avoids all the complexity of runtime Dart evaluation and works on every platform with a filesystem.

### Tools
- `scripts/flutter_inspect.sh` — screenshot, tree, find, details, text
- `scripts/flutter_auth.sh` — status, choose, submit, otp-wait, auto, cancel
- `scripts/flutter_interact.sh` — tap, rightclick, longpress, scroll, type, key, open, send, chats, messages, state

See `CLAUDE.md` § GUI Automation Toolkit for full command reference and usage examples.
