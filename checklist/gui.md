# GUI Checklist

Current state of the UI as built in `demo_ui.html`. Updated as we iterate.

## Layout Structure

- [x] Platform rail (68px, left edge)
- [x] Sidebar (272px, single panel with drill-in/out)
- [x] Main chat area (flex, fills remaining)
- [x] Emoji/Sticker/GIF panel (right side, slides open 320px)
- [x] Right panel (member list, search results, thread view)
- [x] Mobile/responsive layout

## Chat Types (4 distinct types)

- [x] **DM** — avatar, online dot, call buttons, standard bubbles
- [x] **Ordinary Group** — group icon, member count, call buttons, no drill-in
- [x] **Topic Group** — drill-in to channels/topics, text + voice sections, VC text chat
- [x] **Channel (Broadcast)** — no user avatar/name, subscriber count, read-only, admin notice

## Platform Rail

- [x] Platform icons with SVG logos (Telegram, Discord, Matrix)
- [x] Text fallback icons (IRC, XMPP, Mumble)
- [x] Active state — colored bg + ring
- [x] Hover — squircle morph (border-radius 50% -> 14px)
- [x] Notification dot (red, top-right)
- [x] Divider between platform groups
- [x] "Add platform" button (+)
- [x] Reorder platforms (drag & drop)
- [x] Unread count badge (number, not just dot)
- [x] Platform connection status indicator
- [x] Context menu (disconnect, settings, etc.)

## Sidebar — Chat List (Page 1)

- [x] Header with title + compose button
- [x] Search box with focus ring
- [x] Collapsible folders (DMs / Groups / Channels)
- [x] Chat items — avatar, name, preview, time, unread badge
- [x] Online dot on DM avatars
- [x] Type icon prefix (group icon, megaphone for channels)
- [x] Channel avatar style (distinct from user/group avatars)
- [x] Active chat highlight
- [x] **Right-click context menu** — pin, mute, archive, mark read, leave/delete (per type)
- [x] Drag to reorder / move between folders (folder add button)
- [x] Custom user-created folders (+ button on folder headers)
- [x] Typing indicator in preview
- [x] Muted chat styling (dimmed badge)
- [x] Pinned chat indicator

## Sidebar — Channel List (Page 2, Drill-in)

- [x] Back button to return to chat list
- [x] Group avatar + name + member count header
- [x] Collapsible channel sections (Text / Voice)
- [x] Text channels (# icon)
- [x] Voice channels (speaker icon) — click to join VC
- [x] Voice members shown under VC
- [x] **VC text chat button** — chat icon on voice channels to open their text chat
- [x] Active channel highlight
- [x] Slide animation (translateX, 0.28s)
- [x] Channel context menu (mute, mark read, edit)
- [x] Create channel / topic button (+ on section headers)
- [x] Channel description / info (info icon on hover)
- [x] Drag to reorder channels (via rail drag infrastructure)

## Voice Chat Controls (above user panel)

- [x] **VC controls bar** — appears when connected to voice
- [x] "Voice Connected" label + channel name
- [x] Mute button (toggles, turns red when muted)
- [x] Deafen button (toggles, auto-mutes when deafened)
- [x] Disconnect button (red, ends VC)
- [x] Clicking VC channel in sidebar joins and shows controls
- [x] Video toggle
- [x] Screen share toggle
- [x] VC connection quality indicator

## User Panel (Bottom of Sidebar)

- [x] Avatar with initial
- [x] Username
- [x] Online status (green text)
- [x] Settings gear button
- [x] Status picker (online, away, DND, invisible)
- [x] Custom status text
- [x] Account switcher

## Chat Header

- [x] Avatar + name (adapts per chat type)
- [x] Status line — online (DM), member count (group), subscriber count (channel)
- [x] Breadcrumb when in topic channel (`Group > Channel`)
- [x] Call buttons shown for DM/group, hidden for channels
- [x] Search + more buttons
- [x] Pinned messages button + banner
- [x] Typing indicator
- [x] Group/channel info on click

## Messages

- [x] Date separator pill (centered, uppercase)
- [x] **DM/Group**: avatar + author name + bubbles (received), right-aligned bubbles (sent)
- [x] **Channel**: no avatar, no author name — just content bubbles (broadcast style)
- [x] Bubble timestamps inside last bubble
- [x] Bubble radius — 18px with 6px tail corner
- [x] Per-channel message switching (topic group)
- [x] VC text chat has its own message history
- [x] Reply/quote (swipe or click)
- [x] Reactions
- [x] Edit indicator
- [x] Delete indicator
- [x] Media (images, video, files) inline
- [x] Link previews
- [x] Code blocks with syntax highlight
- [x] Message hover actions (reply, react, more)
- [x] Unread separator ("X new messages")
- [x] Scroll-to-bottom button
- [x] Message selection (multi-select, forward, delete)

## Input Area

- [x] Attach button (+)
- [x] Text input with border + focus ring (wrapped with inline buttons)
- [x] Auto-resize textarea
- [x] Send button (rounded, accent color)
- [x] **Emoji button** — inside input, opens emoji panel on right
- [x] **Mic/Camera button** — inside input, click to toggle mode, hold to record (placeholder)
- [x] **Hidden for channels** — replaced with "Only admins can post" notice
- [x] Admin mode for channels (show input when user is admin)
- [x] Voice message recording UI (waveform, duration)
- [x] Video message recording UI
- [x] Reply bar (shows quoted message above input)
- [x] Edit mode bar
- [x] File drag & drop
- [x] Markdown formatting toolbar
- [x] Mention autocomplete (@user, #channel)

## Emoji/Sticker/GIF Panel

- [x] **Three tabs** — Emoji, Stickers, GIFs
- [x] Tab switching with active indicator
- [x] Search box
- [x] Emoji grid (clickable, inserts into input)
- [x] Sticker grid (larger items, 4-column)
- [x] GIF grid (2-column, placeholder labels)
- [x] Panel slides open (320px) from right side of chat area
- [x] Emoji button in input toggles panel open/closed
- [x] Recent/frequently used section
- [x] Emoji skin tone picker
- [x] Sticker pack browser
- [x] GIF search (via search filter)
- [x] Sticker/GIF preview on hover

## Context Menu (Right-Click)

- [x] **DM context menu** — pin, mute, archive, block, delete
- [x] **Group context menu** — pin, mute, mark read, archive, leave
- [x] **Channel context menu** — pin, mute, mark read, leave
- [x] Danger items styled red
- [x] Separator lines between sections
- [x] Auto-positioned (clamped to viewport)
- [x] Closes on click outside
- [x] Message context menu (reply, copy, forward, delete)
- [x] Channel item context menu in drill-in view

## Theming

- [x] Dark theme (charcoal base #101318)
- [x] Blue-indigo accent (#4f6ef7)
- [x] Inter font family
- [x] Light theme
- [x] Custom accent color picker
- [x] Per-platform theme override (via accent color)
- [x] System theme auto-detect

## Pre-GUI: Protobuf Bridge

Before implementing in Flutter, replace JSON FFI bridge with Protocol Buffers (`.proto` → codegen for Go + Dart). Backend changes then break at compile time, not runtime.

## Demo File

Working prototype: `demo_ui.html` (project root, not committed)
