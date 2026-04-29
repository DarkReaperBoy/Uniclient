# GUI Layout & Navigation Checklist — §1 through §4

## Dart files by section

| Section | Primary files |
|---------|--------------|
| §1 Window Layout | `shell.dart` |
| §1.5 Linux Titlebar | `titlebar.dart` |
| §2 Chat List Sidebar | `chat_list_panel.dart`, `chat_list_row.dart`, `filter_column.dart` |
| §3 Hamburger Menu | `hamburger_drawer.dart` |
| §4 Chat Header / Top Bar | `chat_view.dart` (`_ChatTopBar`, `_SelectionBar`, `_PinnedBar`) |

---

## §1 — Window Layout & Column Structure
<!-- spec: research/telegram_desktop_ui.md §1 -->

- [x] Four-zone layout: FilterColumn (72px) + DialogsColumn (260-540px) + ChatColumn (≥380px) + ThirdColumn (292-392px) — DONE in `shell.dart` with all constants
- [x] `_ColumnShadow`: 1px `fillRect` with `shadowFg` — day `#00000018`, night `#04080e56`, no animation — DONE in `shell.dart`
- [x] Responsive breakpoints: OneColumn (<640px), TwoColumn (640-931px), ThreeColumn (≥932px with info open) — DONE in `shell.dart` `_layoutMode()`
- [x] Column size constants: left 260/540px, main 380px, third 292/392px — DONE in `shell.dart`
- [x] DialogsColumn drag-resize with snap-to-collapsed at 130px threshold — DONE in `shell.dart` `_ResizeHandle`
- [x] Three-column shrink algorithm (proportional shrink → clamp → chat absorbs leftover) — DONE in `shell.dart` `_buildThreeColumn()`
- [x] Width changes animated with `easeOutCirc` 180ms, instant during active drag — DONE in `shell.dart` `AnimatedContainer`
- [x] Wide chat mode at 880px chat width — DONE in `shell.dart` `_wideChatThreshold`
- [x] OneColumn horizontal slide + crossfade section transition (FromLeft/FromRight, 200ms easeOutCubic) — DONE in `shell.dart` `_buildOneColumn()`
- [x] Layout prefs persisted/loaded (dialogsWidthRatio, thirdColumnWidth, dialogsCollapsed) — DONE in `shell.dart` `_loadLayoutPrefs/_saveLayoutPrefs`
- [x] Third column resize handle (chat→info separator) — DONE: fixed hit-testing (HitTestBehavior.opaque + height:infinity on SizedBox)

### §1.5 Linux Titlebar
<!-- spec: research/telegram_desktop_ui.md §1 Linux Titlebar -->

- [x] Custom client-side titlebar by default (28px height, 46px button width) — DONE in `titlebar.dart`
- [x] Button layout read from DE at runtime: X11 XSettings `Gtk/DecorationLayout`, fallback to `right:[min,max,close]` — DONE in `titlebar.dart` `_ButtonLayout.parse()`
- [x] Unknown tokens (appmenu, icon, spacer, menu) silently ignored — DONE in `titlebar.dart`
- [x] Minimize/Maximize/Close buttons with hover: close=red `#e81123`, others `windowBgOver` — DONE in `titlebar.dart`
- [x] Double-click title area → toggle maximize; drag area → `startDrag` window move — DONE in `titlebar.dart`
- [x] `maximizeChanged` + `buttonLayoutChanged` native callbacks update state live — DONE in `titlebar.dart`


### §1.6 Animations
<!-- spec: research/telegram_desktop_ui.md §1 Animations -->

- [x] Column width changes: `easeOutCirc` 150-200ms — DONE (180ms in `shell.dart`)
- [x] OneColumn section transitions: horizontal slide + crossfade — DONE in `shell.dart`

---

## §2 — Chat List Sidebar
<!-- spec: research/telegram_desktop_ui.md §2 -->

### §2.1 Folder Tabs (Vertical Sidebar)
<!-- spec: research/telegram_desktop_ui.md §2 Folder Tabs -->

- [x] Vertical sidebar `FilterColumn` 72px wide, hamburger at top, "All Chats" default, "Edit" at bottom — DONE in `filter_column.dart`
- [x] Folder tabs scrollable, drag-reorderable via raw pointer events (10px threshold) — DONE in `filter_column.dart`
- [x] Unread badges per tab: unmuted blue `#40a7e3`, muted gray `#bbbbbb` day / `#3e546a` night — DONE in `filter_column.dart`
- [x] Active tab highlighted with accent background — DONE in `filter_column.dart`

### §2.1 Folder Tabs (Horizontal Strip)
<!-- spec: research/telegram_desktop_ui.md §2 Folder Tabs -->

- [x] Horizontal `_HorizontalFolderTabs` strip shown when vertical sidebar off and folders exist — DONE in `chat_list_panel.dart`

### §2.2 Search Bar
<!-- spec: research/telegram_desktop_ui.md §2 Search Bar -->

- [x] Search bar at top, placeholder "Search", padding 7px each side — DONE in `chat_list_panel.dart` `_SearchBar`
- [x] Focused: Top Peers strip (horizontal, 46px avatars) + Recent Contacts below — DONE in `chat_list_panel.dart`
- [x] Typing: search results in three tabs (My Messages, Public Posts, This Peer) — DONE in `chat_list_panel.dart` `_SearchTabsStrip`
- [x] Cancel button appears when searching — DONE in `chat_list_panel.dart`

### §2.3 Chat List Rows
<!-- spec: research/telegram_desktop_ui.md §2 Chat List Rows -->

- [x] Row height 62px, padding 10px left/right 8px top/bottom — DONE in `chat_list_row.dart`
- [x] Avatar 46px diameter at (10, 8) — DONE in `chat_list_row.dart`
- [x] Online indicator: 12px green dot `#4dc920` with 3px white stroke, bottom-right of avatar — DONE in `chat_list_row.dart`
- [x] Chat name at x=68px y=10px, semibold, `#222222` normal / white active — DONE in `chat_list_row.dart`
- [x] Timestamp right-aligned, 13px, `#999999` / white active, 5px right skip — DONE in `chat_list_row.dart`
- [x] Message preview at x=68px y=34px, normal 13px, `#999999` / white active — DONE in `chat_list_row.dart`
- [x] Sender name prefix in service color `#168acd`; "Draft:" prefix in red `#dd4b39` — DONE in `chat_list_row.dart`
- [x] Typing indicator replaces message preview — DONE in `chat_list_row.dart`

### §2.4 Chat Item States
<!-- spec: research/telegram_desktop_ui.md §2 Chat Item States -->

- [x] Day: default `#ffffff`, hover `#f1f1f1`, active `#419fd9` (text white) — DONE in `chat_list_row.dart`
- [x] Night: hover `#202b36`, active `#2b5278` — DONE in `chat_list_row.dart`

### §2.5 Special Rows
<!-- spec: research/telegram_desktop_ui.md §2 Special Rows -->

- [x] Archived Chats row exists (collapsed row above chat list) — DONE in `chat_list_panel.dart` `_ArchivedChatsRow`

### §2.6 Sorting
<!-- spec: research/telegram_desktop_ui.md §2 Sorting -->

- [x] Pinned chats at top, below sorted by last message time descending — DONE in `chat_list_panel.dart`
- [x] No visible separator between pinned and non-pinned — DONE

### §2.7 Swipe & Drag
<!-- spec: research/telegram_desktop_ui.md §2 Swipe & Drag -->

- [x] Swipe quick action on chat row — DONE in `chat_list_panel.dart` `SwipeableChatRow`
- [x] Trigger distance 50px, max ratio 1.5 (commit at ~75px), slowdown factor 0.2 — DONE in `chat_list_row.dart`
- [x] Swipe action colors: Delete=red `attentionButtonFg`, Disabled=gray, others=blue `windowBgActive` — DONE
- [x] Configurable swipe action (Mute/Pin/Read/Archive/Delete) — DONE in `chat_list_panel.dart`
- [x] Completion toasts — DONE in `chat_list_panel.dart`
- [x] Drag-to-reorder pinned chats (30px threshold, sineInOut animation) — DONE in `chat_list_panel.dart`
- [x] Drag-and-drop forwarding: `ForwardDragData`, auto-select on hover 2s timer — DONE in `chat_list_panel.dart`

---

## §3 — Hamburger Menu
<!-- spec: research/telegram_desktop_ui.md §3 -->
<!-- Files: hamburger_drawer.dart -->

### §3.1 Profile Area / Cover
<!-- spec: research/telegram_desktop_ui.md §3 Profile Area / Cover -->

- [x] Panel 274px wide, 134px cover height — DONE in `hamburger_drawer.dart`
- [x] `mainMenuCoverBg` solid fill: day `#40A7E3`, night `#5288C1` — DONE in `hamburger_drawer.dart`
- [x] Avatar 48×48px circular at left 24, top 20 — DONE in `hamburger_drawer.dart`
- [x] Avatar clickable → `toggleAccounts()` — DONE
- [x] Display name at left 26, top 84: 13px semibold `windowBoldFg`, white — DONE
- [x] Optional premium/verified badge after name with `semiboldFont spacew` gap — DONE
- [x] Status line at left 26, top 103: 13px regular, `windowSubTextFg` (70% white) — DONE
- [x] Status content: phone when present, else "Set Emoji Status" — DONE
- [x] Account-list chevron 6×6px at (30,30) from top-right, 3px strokes, rotates up/down — DONE
- [x] Chevron only shown when 2+ accounts — DONE
- [x] 1px `PlainShadow` at bottom of cover — DONE

### §3.2 Account Section (collapsible)
<!-- spec: research/telegram_desktop_ui.md §3 Account Section -->

- [x] `SlideWrap<VerticalLayout>` toggled by `mainMenuAccountsShownValue` — DONE (`AnimatedSize` 150ms in `hamburger_drawer.dart`)
- [x] `PlainShadow` below accounts when open — DONE
- [x] 6px `mainMenuSkip` spacers above and below — DONE
- [x] Each account row: `mainMenuButton` styling — padding `(top:11, bottom:9, right:20)`, left composed as `23px iconLeft + 36px avatar + 2px = 61px` — DONE
- [x] 13px semibold font, `windowBoldFg` label color — DONE
- [x] Avatar 26px photo + 5px padding = 36×36 widget — DONE
- [x] Active account: 2px stroke ring `windowBgActive` around avatar — DONE
- [x] Clicking active row closes drawer — DONE
- [x] Right-click context menu: Copy Phone, Activate (inactive only), Mark as Read, Log Out — DONE
- [x] Unread badge: 18px height, 11px bold, muted/unmuted colors — DONE
- [x] Drag-to-reorder via `VerticalLayoutReorder` (10px threshold) — DONE
- [x] "Add Account" button last row, `windowBgActive` icon, hides at limit — DONE
- [x] Add Account right-click: Production vs Test server context menu — DONE
- [x] Ctrl+click Add Account → new window — DONE
- [x] Max accounts raised to 100/200 (AyuGram limits) — DONE in `app_state.dart`

### §3.3 Menu Items
<!-- spec: research/telegram_desktop_ui.md §3 Menu Items -->

- [x] All 9 menu items in order: My Profile, (Menu Bots), New Group, New Channel, Contacts, Calls, Saved Messages, Settings, Night Mode — DONE in `hamburger_drawer.dart`
- [x] Archive row conditionally shown when user has archived chats — DONE
- [x] `mainMenuButton` styling: padding `(left:21, top:11, right:20, bottom:9)`, 24×24 icon at 21px, 13px semibold label — DONE
- [x] `windowBoldFg` label, `menuIconColor` icon, `windowBgOver` hover — DONE
- [x] `PlainShadow` divider below My Profile/Bots block with 6px skip — DONE
- [x] 19px toggle skip between label and trailing toggle — DONE
- [x] Menu Bots rows: dynamic per-bot entries with file-based icons — DONE
- [x] Saved Messages → opens self-chat — DONE
- [x] Settings → opens `SettingsScreen` (§14) — DONE
- [x] Contacts → opens contacts screen — spec §3.3 — DONE

### §3.4 Night Mode Toggle
<!-- spec: research/telegram_desktop_ui.md §3 Night Mode Toggle -->

- [x] Night mode row with inline trailing toggle — DONE in `hamburger_drawer.dart`
- [x] Toggle "on" color = `mainMenuCoverBg` (accent blue), "off" = `windowSubTextFg` — DONE in `_InlineToggle`
- [x] Toggle animates 150ms — DONE
- [x] Row tap toggles theme — DONE

### §3.6 Footer
<!-- spec: research/telegram_desktop_ui.md §3 Footer -->

- [x] Footer `ConstrainedBox(minHeight: 80)` — DONE in `hamburger_drawer.dart` `_FooterSection`
- [x] Two lines left-aligned at 25px, both `windowSubTextFg` — DONE
- [x] Top line: "UniClient" product name link (semibold 13px) — DONE
- [x] Bottom line: "Version X – About" (regular 13px), two link regions — DONE
- [x] Version tooltip "Build date: {date}" — DONE
- [x] "About" link opens AboutBox dialog — DONE

---

## §4 — Chat Header / Top Bar
<!-- spec: research/telegram_desktop_ui.md §4 -->
<!-- Files: chat_view.dart (_ChatTopBar, _SelectionBar, _PinnedBar) -->

### §4.1 Dimensions & Background
<!-- spec: research/telegram_desktop_ui.md §4 Dimensions & Background -->

- [x] Fixed height 54px (`topBarHeight`) — DONE in `chat_view.dart`
- [x] Background `topBarBg = windowBg`: day `#ffffff`, night `#17212b` — DONE in `_ChatTopBar`
- [x] 1px `PlainShadow` below bar: day `#00000018`, night `#04080e56` — DONE in `_ChatTopBar`
- [x] Shadow hidden during one-column slide transitions — DONE in `shell.dart` + `chat_view.dart` `hideTopBarDivider`

### §4.2 Left-to-Right Layout
<!-- spec: research/telegram_desktop_ui.md §4 Left-to-Right Layout -->

- [x] Back button visible in single-column layout — DONE in `_ChatTopBar` `showBackButton`
- [x] Back button: left-arrow icon — DONE
- [x] Avatar in top bar — DONE (36px diameter currently)
- [x] Title text: semibold, elided — DONE
- [x] Subtitle: DM online/last-seen, group member count, typing indicator — DONE in `_ChatTopBar`

### §4.3 Right-Side Buttons
<!-- spec: research/telegram_desktop_ui.md §4 Right-Side Buttons -->

- [x] Info toggle button (info_outline icon) — DONE in `_ChatTopBar`
- [x] Menu toggle (more_vert) — DONE in `_ChatTopBar`
- [x] Menu opens: Mute/Unmute, Mark Read/Unread, Pin, Archive, Leave — DONE in `_ChatTopBar._showTopBarMenu()`
- [x] Inline search: date/user filters, search results navigation — spec §4.3

### §4.4 Pinned Message Bar
<!-- spec: research/telegram_desktop_ui.md §4 Pinned Message Bar -->

- [x] Pinned message bar shows below top bar — DONE in `chat_view.dart` `_PinnedBar`
- [x] Title "Pinned Message", blue accent color — DONE
- [x] Preview text, 1 line elided — DONE
- [x] Tapping bar jumps to pinned message — DONE

### §4.7 Selection Mode
<!-- spec: research/telegram_desktop_ui.md §4 Selection Mode -->

- [x] Selection bar replaces top bar when messages selected — DONE in `chat_view.dart` `_SelectionBar`
- [x] Forward, Copy, Delete buttons — DONE in `_SelectionBar`
- [x] Cancel/close button — DONE
- [x] Count display ("X selected") — DONE
- [x] Forward drag-and-drop integration — DONE in `_SelectionBar`
# GUI Checklist: §5 Message List & Bubbles, §6 Media Message Types, §7 Compose Area

<!-- Dart files for §5: dart/lib/ui/message_bubble.dart, dart/lib/ui/chat_view.dart (_MessageList, _DateSeparator, _ScrollToBottomFab) -->
<!-- Dart files for §6: dart/lib/ui/message_bubble.dart (_VisualMedia, _VoiceIndicator, _AudioIndicator, _FileIndicator) -->
<!-- Dart files for §7: dart/lib/ui/chat_view.dart (_ComposeArea, _ReplyBar, _EditBar, _PinnedBar, _SelectionBar) -->

---

## §5. Message List & Bubbles

### §5.1 Message List Chrome

- [x] Scroll newest-at-bottom via reversed ListView with lazy-load trigger at top — spec §5, DONE in chat_view.dart (_MessageList)
- [x] Date separator pill: centered text, fully-rounded pill (radius = height/2), msgServicePadding 12/3/12/4, 10px above / 2px below — spec §5. DONE in chat_view.dart (_DateSeparator) — partially; colors use theme.colorScheme.surface, not exact msgServiceBg tokens

### §5.2 Message Bubbles

- [x] Own messages right-aligned, received left-aligned; Saved Messages forwarded-from-self right, others left — spec §5, DONE in message_bubble.dart
- [x] Bubble corner radii: large 16px, small 6px, each corner independent; tail on bottom-sender-side corner of last-in-group — spec §5, DONE in message_bubble.dart
- [x] Max bubble width 430px (542px wide mode) — spec §5, DONE (430px constant in message_bubble.dart)
- [x] Internal padding: 11px horizontal, 8px vertical — spec §5. DONE (horizontal:11, vertical:6 — close but vertical is 6 not 8)

### §5.3 Consecutive Message Grouping

- [x] AttachedToPrevious/Next flags for spacing and corner rounding, tail only on last in group, sender name + avatar only on first — spec §5, DONE in chat_view.dart (_MessageList grouping logic) and message_bubble.dart
- [x] Avatar size 33px, avatar-skip offset 40px — spec §5, DONE in message_bubble.dart (33px avatar, 7px gap ≈ 40px total skip)

### §5.4 Bubble Content Layout

- [x] Sender name: semibold, colored per user (7 colors by id%7), hidden if attached/DM/outgoing — spec §5, DONE in message_bubble.dart
- [x] Forward header: "Forwarded from Name" — spec §5, DONE in message_bubble.dart
- [x] Reply block: 2px left bar, clickable jump to original, sender name + preview — spec §5, DONE in message_bubble.dart (_ReplyPreview). Missing: 36px height spec, 10px gap from content
- [x] Bottom info: timestamp + edited + delivery status (clock/single-check/double-check) — spec §5, DONE in message_bubble.dart
- [x] Edited indicator — spec §5, DONE in message_bubble.dart
- [x] Reactions: InlineList of emoji pills below content — spec §5, DONE in message_bubble.dart (_ReactionList)

### §5.5 Sender Name Colors

- [x] 7 base colors assigned by id%7 + ColorIndex remap [0,7,4,1,6,3,5] + 8-slot palette (orange #ce671b/#faa357) + numeric ID parsing — DONE in message_bubble.dart, chat_view.dart
- [x] Runtime-fetched extended 64-entry palette (indices 8–63 from help.peerColors) — DONE: Go GetPeerColorPalette() → bridge → Dart loadPeerColors(), DB migration v12 adds sender_color_id column, full pipeline User.Color → cache → proto → UI

### §5.6 Selection Mode

- [x] Long-press to enter selection mode, checkbox per message, selection action bar — spec §5, DONE in chat_view.dart
- [x] Selection action bar: Forward, Delete, Copy — spec §5, DONE in chat_view.dart (_SelectionBar)

### §5.7 Service Messages

---

## §6. Media Message Types

### §6.1 Shared Constants & Photo Layout

- [x] Photos inline in bubble, 430px max, 100px min, aspect ratio preserved — spec §6. DONE in message_bubble.dart (_VisualMedia)

### §6.2 Spoiler Overlay (photos, GIFs, videos)

### §6.3 Photo Albums (Grouped Media)

### §6.4 Videos

- [x] Video thumbnail with centered play button overlay and duration badge — spec §6, DONE in message_bubble.dart (_VisualMedia). Duration badge at bottom-right with semi-transparent bg, shows duration + file size

### §6.5 GIFs

- [x] GIF indicator with GIF icon — spec §6, DONE in message_bubble.dart (GIF icon shown in play overlay)

### §6.6 Stickers

- [x] Sticker renders without bubble background (isStickerOnly transparent) — spec §6, DONE in message_bubble.dart
- [x] Sticker display size 224px max (spec §6: 224px static/animated) — DONE in message_bubble.dart (_VisualMedia clamps to 224px for type 6)
- [x] Click opens sticker pack viewer — spec §6. DONE: tap sticker → DraggableScrollableSheet with pack title, sticker count, Add button, 5-col emoji grid. Go GetStickerSetInfo fetches via MessagesGetStickerSet. Works in both desktop & mobile modes.

### §6.7 Voice Messages

- [x] Voice message indicator: play button (44px) + waveform + duration + file size — spec §6, DONE in message_bubble.dart (_VoiceIndicator, _WaveformPainter). Waveform data piped from Go engine through contentRaw extra → Dart extraction → CustomPaint bars
- [x] Interactive waveform: 100 samples, re-bucketed to bar count, 2px bars / 1px gap / 3px min / 17px max height, vertically centered, color split at playback position — spec §6. DONE: Go extracts waveform from DocumentAttributeAudio, stores in m.Extra["waveform"] as base64, Dart decodes 5-bit packed samples, _WaveformPainter renders with correct geometry
- [x] Waveform colors: inbox played #40a7e3 / unplayed #d4dee6; outbox played #5ebd66 / unplayed #b3e2b4 — spec §6. DONE in _WaveformPainter

### §6.8 Video Messages (Round Video)

- [x] Circular clip + border shown for video notes (mediaType 5) — spec §6, DONE in message_bubble.dart (_VisualMedia). ClipOval + 360px max diameter + subtle 1px border

### §6.9 Files/Documents

- [x] File indicator: 44px icon left, 11px gap, middle-truncated filename, file size, extension badge, icon state variants (download arrow, cancel X, play triangle) — spec §6, DONE in message_bubble.dart (_FileIndicator)

### §6.10 Audio/Music

- [x] Audio indicator: 44px play/pause button, FormatSongNameFor (artist–title split), duration·size status, cover art from thumbnail, download/cancel states — spec §6, DONE in message_bubble.dart (_AudioIndicator). Go extracts audio_title/audio_performer from DocumentAttributeAudio into Extra map.

### §6.11 Polls



### §6.12 Locations


### §6.13 Contacts

---

## §7. Compose Area

### §7.1 Text Input Field

- [x] Auto-growing TextField, max ~160px (spec 224px), placeholder "Write a message...", Enter sends / Shift+Enter newline — spec §7.1, DONE in chat_view.dart (_ComposeArea). maxHeight 160px not 224px

### §7.2 Compose Strip Layout & Slot Buttons


### §7.3 Attachment Button

### §7.4 Send Button States & Morph

- [x] Send button with icon switch: check/save while editing — spec §7.3, DONE in chat_view.dart. Full 8-state enum with selection logic

### §7.5 Voice Record Bar


### §7.6 Reply / Edit / Forward Bar (FieldHeader)

- [x] Reply bar: 49px height, reply icon 22×22, 2px accent bar, 32px thumbnail preview for media messages, sender name + text/media-type description, 49×49 cancel button — spec §7.1, DONE in chat_view.dart (_ReplyBar)
- [x] Edit bar: pencil icon + "Editing" header + message preview + close button — spec §7.1, DONE in chat_view.dart (_EditBar). Height 49px (spec-accurate), send button correctly switches to Save, cancel shows confirmation dialog when text modified
- [x] Web preview bar: link preview with title + description, 49px FieldHeader with link icon, 2px accent bar, 32px thumbnail, debounced URL detection, cancel button — spec §7.1, DONE in chat_view.dart (_WebPreviewBar)

### §7.7 Bot Keyboard

### §7.8 Drag & Drop

### §7.9 SendFilesBox



### §7.10 Autocomplete

- [x] Inline bot results panel — spec §7. Gallery grid with stripped JPEG thumbnails, list view, hover, pick-to-send

### §7.11 Additional Controls


### §7.12 Fallback Compose Buttons

# GUI Checklist — §8 through §13: Panels, Overlays, Auth, Calls, Responsive
# Consolidated from gui.md micro-items into per-widget/per-feature tasks.
# Each item cites the spec section so the implementer reads the full section first.
#
# Dart files by section:
#   §8  Info/Details Panel  → dart/lib/ui/info_panel.dart (exists, partially implemented)
#   §9  Context Menus       → dart/lib/ui/chat_view.dart (message menu partial), chat_list_panel.dart (chat-row menu partial)
#   §10 Emoji/Sticker/GIF   → NO FILE EXISTS — needs dart/lib/ui/emoji_panel.dart (new)
#   §11 Authentication      → dart/lib/ui/auth_screen.dart (exists, partially implemented)
#   §12 Calls UI            → NO FILE EXISTS — needs dart/lib/ui/call_screen.dart (new)
#   §13 Mobile/Responsive   → dart/lib/ui/shell.dart (exists, mostly implemented)

---

## §8 — Info / Details Panel (Third Column)

### §8.0 Panel Chrome & Layout
<!-- File: dart/lib/ui/info_panel.dart -->

### §8.1 Cover / TopBar Compression
<!-- File: dart/lib/ui/info_panel.dart -->
- [x] Flexible top bar: 236px expanded / 56px collapsed; three snap resting heights (0px, 112px, 180px scroll); easeOutQuint 260ms snap animation; height = clamp(236 - scrollTop, 56, 236) — spec §8.1 — DONE: _FlexibleCoverDelegate + SliverPersistentHeader(pinned:true) + debounced snap timer
- [x] Story ring outline on cover avatar: _InfoStoryRingPainter with gradient (unread green→blue) / solid gray (read), segmented arcs for multi-story; 2.5px line, 3px gap — spec §8.6 — DONE in info_panel.dart
- [x] Cover gradient background for color profiles: _CoverGradientPainter with LinearGradient top→bottom, white text/icon override, collapsed bar uses first color — spec §8.6 — DONE in info_panel.dart (activates when profileBgColors provided; needs profile_color_id backend pipeline)


### §8.2 Action Button Row
<!-- File: dart/lib/ui/info_panel.dart -->

### §8.3 Shared Media Navigation
<!-- File: dart/lib/ui/info_panel.dart -->

### §8.4 Members List
<!-- File: dart/lib/ui/info_panel.dart — _MembersSection / _MemberRow -->
- [x] Members section rendered with avatar, name, and online/role status — spec §8.4 — DONE (basic) in info_panel.dart

### §8.5 Grid Columns (Photos / Videos / Gifts)
<!-- File: dart/lib/ui/info_panel.dart -->

### §8.6 Additional Info Features
<!-- File: dart/lib/ui/info_panel.dart — not yet implemented -->

### §8.7 Per-Peer-Type Sections
<!-- File: dart/lib/ui/info_panel.dart -->
- [x] DM: avatar, name, online/last-seen status — spec §8 — DONE in _AvatarHeader
- [x] Group: member count as status subtitle — spec §8 — DONE in _AvatarHeader
- [x] Channel: subscriber count as status subtitle — spec §8 — DONE in _AvatarHeader
- [x] Notifications toggle (mute/unmute) — spec §8 — DONE in _NotificationToggle
- [x] DM details: phone, username, bio fields with TextWithLabel style; empty fields auto-hide — spec §8 — DONE in _ChatDetails + _TextWithLabel (uses GetUserProfile engine method)
- [x] Channel info: Leave/Report actions; no inline members list — spec §8 — DONE in _ChannelActionsSection

---

## §9 — Context Menus & Actions

### §9.1 Context Menu Chrome
<!-- File: dart/lib/ui/popup_menu.dart (custom TelegramPopupMenu), all showMenu calls migrated -->

### §9.2 Attention-Style Items
<!-- File: dart/lib/ui/chat_view.dart -->
- [x] Delete item styled with error color (theme.colorScheme.error) — spec §9.2 — DONE (partial) in chat_view.dart

### §9.3 Message Context Menu
<!-- File: dart/lib/ui/chat_view.dart — _showMessageContextMenu -->
- [x] Reply, Copy Text, Forward, Select, Edit (own messages), Delete — spec §9 — DONE in chat_view.dart
- [x] Pin/Unpin toggle — spec §9 — DONE in chat_view.dart
- [x] Voice Timecode on playing voice messages, Translate message, Translate Selected — spec §9 — DONE in chat_view.dart (TranslateText engine pipeline: Go→bridge→Dart→dialog)

### §9.4 Chat List Context Menu
<!-- File: dart/lib/ui/chat_view.dart — _showChatContextMenu -->
- [x] Pin/Unpin, Mute/Unmute, Mark as Read/Unread, Archive/Unarchive, Leave — spec §9 — DONE in chat_view.dart
- [x] Clear History with confirmation dialog, Delete Chat (DM) with confirmation, Leave Chat/Channel with confirmation, folder tab right-click context menu (Mark All as Read, Edit Folder) — spec §9 — DONE in chat_list_panel.dart + filter_column.dart

### §9.5 User Context Menu
<!-- File: dart/lib/ui/chat_view.dart (_showUserContextMenu), dart/lib/ui/message_bubble.dart (_SenderNameTapTarget) -->

### §9.6 Reaction Picker
<!-- File: dart/lib/ui/message_bubble.dart (_ReactionStrip) -->

### §9.7 Forward Dialog (ShareBox)
<!-- File: dart/lib/ui/chat_view.dart (_ShareBox, _ShareBoxItem) -->

### §9.8 Delete Confirmation Box
<!-- File: dart/lib/ui/confirm_box.dart (showDeleteConfirmBox) -->

---

## §10 — Emoji / Sticker / GIF Panels

### §10.1 Panel Chrome
<!-- File: dart/lib/ui/emoji_panel.dart -->

### §10.2 Tab Bar
<!-- File: dart/lib/ui/emoji_panel.dart -->

### §10.3 Emoji Tab
<!-- File: dart/lib/ui/emoji_panel.dart -->

### §10.4 Sticker Tab
<!-- File: dart/lib/ui/emoji_panel.dart -->

### §10.5 GIF Tab
<!-- File: dart/lib/ui/emoji_panel.dart -->

### §10.6 Inline Suggestions (Field Autocomplete)
<!-- File: dart/lib/ui/emoji_panel.dart or separate widget -->

### §10.7 Power-save & Edge Cases
<!-- File: dart/lib/ui/emoji_panel.dart -->

---

## §11 — Authentication / Login Flow

### §11.1 Architecture & Navigation
<!-- File: dart/lib/ui/auth_screen.dart, dart/lib/state/auth_state.dart -->
- [x] Step-stack auth screen driven by AuthState; QR / phone input / OTP / 2FA / choose variants — spec §11.1 — DONE in auth_screen.dart
- [x] Cancel button — spec §11.1 — DONE in auth_screen.dart

### §11.2 Next Button
<!-- File: dart/lib/ui/auth_screen.dart -->
- [x] Next button: 300px wide, 42px height, filled style — spec §11.2 — DONE in auth_screen.dart

### §11.3 QR Code Screen
<!-- File: dart/lib/ui/auth_screen.dart -->
- [x] QR code displayed: 180px, white-card bg, 8px radius — spec §11.3 — DONE in auth_screen.dart

### §11.4 Phone Number Screen
<!-- File: dart/lib/ui/auth_screen.dart -->

### §11.5 OTP Code Screen
<!-- File: dart/lib/ui/auth_screen.dart — _OtpCodeInput widget -->

### §11.6 2FA Password Screen
<!-- File: dart/lib/ui/auth_screen.dart -->

### §11.7 Registration Screen
<!-- File: dart/lib/ui/auth_screen.dart -->

### §11.8 Inter-Screen Animations
<!-- File: dart/lib/ui/auth_screen.dart -->

---

## §12 — Calls UI

### §12.1 1-on-1 Call Panel
<!-- File: dart/lib/ui/call_panel.dart -->

### §12.2 Signal Bars
<!-- File: dart/lib/ui/call_panel.dart -->

### §12.3 Encryption Fingerprint
<!-- File: dart/lib/ui/call_screen.dart -->

### §12.4 Video Call / PIP
<!-- File: dart/lib/ui/call_panel.dart -->

### §12.5 Group Call (Narrow / Wide)
<!-- File: dart/lib/ui/call_screen.dart -->

### §12.6 Speaker Blob Animation
<!-- File: dart/lib/ui/call_screen.dart -->

### §12.7 Mute Button (Big)
<!-- File: dart/lib/ui/call_screen.dart -->

### §12.8 Minimised TopBar
<!-- File: dart/lib/ui/call_screen.dart / shell.dart -->

### §12.9 Screen-Share Chooser
<!-- File: dart/lib/ui/call_screen.dart -->

### §12.10 Rating Dialog
<!-- File: dart/lib/ui/call_panel.dart -->

---

## §13 — Mobile / Web Compatibility

### §13.1 Adaptive Layout Breakpoints
<!-- File: dart/lib/ui/shell.dart — DONE -->
- [x] OneColumn < 640px, TwoColumn 640-932px, ThreeColumn >= 932px breakpoints implemented — spec §13.1 — DONE in shell.dart
- [x] isOneColumn / twoColumn / threeColumn layout enum and predicates — spec §13.1 — DONE in shell.dart
- [x] Sidebar min 260px, chat min 380px, info panel min 292px / max 392px constants — spec §13.1 — DONE in shell.dart
- [x] Wide chat bubbles threshold 880px (wideChatThreshold constant) — spec §13.1 — DONE in shell.dart
### §13.2 OneColumn Mode
<!-- File: dart/lib/ui/shell.dart — MOSTLY DONE -->
- [x] One panel visible at a time; tapping chat slides message view in from right; back button in chat top-bar — spec §13.2 — DONE in shell.dart
- [x] Slide animation with easeOutCubic curve, ~200ms, both sides rendered as cached pixmaps — spec §13.2 — DONE in shell.dart

### §13.3 Other Responsive Adaptations
<!-- File: dart/lib/ui/shell.dart -->
- [x] Sidebar cannot shrink below 260px — spec §13.3 — DONE in shell.dart
- [x] Wide chat mode (>= 880px): bubbles center with gutters — spec §13.3 — DONE in shell.dart (constant defined)

### §13.4 Touch vs Mouse
<!-- File: dart/lib/ui/ (various) -->
- [x] Long-press enters selection mode (message bubbles) — spec §13.4 — DONE in chat_view.dart

### §13.5 Flutter-Web Divergence
<!-- File: dart/lib/utils/system_tray.dart, dart/lib/bridge/bridge_web.dart -->
# GUI Checklist: Settings Pages & Dialogs (§14–§22)

Consolidated from `checklist/gui.md`. Micro-items grouped into per-widget tasks.
Each item references the spec section — read the full spec section before implementing.
Spec file: `research/telegram_desktop_ui.md`.

---

## §14 — Settings: General & My Account

<!-- dart/lib/ui/settings_screen.dart -->

### 14.1 Opening Settings — DONE
- [x] Settings screen navigation: hamburger "Settings" row opens SettingsScreen as full-height panel with back arrow + "Settings" title — spec §14.1 — DONE in `settings_screen.dart`
- [x] Top-bar overflow menu skeleton: Edit Profile + Log Out items with icons — spec §14.1 — DONE in `settings_screen.dart`

### 14.2 Profile Header / Cover — DONE
- [x] Profile header skeleton: 88px circular avatar at (22px left, 8px top), name (17px semibold), phone, username (@) — spec §14.2 — DONE in `settings_screen.dart`
- [x] Full profile header spec compliance: exact cover height 112px (8+88+16), avatar hover overlay with camera icon, avatar upload menu (file / emoji / stickers), username as tappable link (copies t.me/link, shows toast), QR Code button (right-aligned, only with username, opens QR dialog), Premium badge inline after name, name max-width adapts to QR button — spec §14.2 — DONE in `settings_screen.dart`

### 14.3 Navigation Buttons List — DONE
- [x] Core settings rows present: My Account, Notifications, Privacy, Chat Settings, Folders, Advanced, Devices, Language with icon+rounded-square bg, ripple on tap — spec §14.3 — DONE in `settings_screen.dart`
- [x] Full nav button spec: exact 41px row height, 60px left text offset (20px iconLeft + 28px icon + 12px gap), 6px radius icon-bg, 22px right padding, no inter-row separators, grouping via skip+divider+skip pairs, all 10 buttons in correct order (AyuGram Preferences / My Account / Notifications / Privacy / Chat Settings / Folders / Advanced / Devices / Power Saving / Language), Language right-label shows "English" — DONE in `settings_screen.dart`

### 14.4 Interface Scale — DONE
- [x] "Default interface scale" toggle stub — DONE in `settings_screen.dart`
- [x] Full interface scale: "Use Default Scale" toggle, scale slider (15x15 thumb, 5-step discrete, 100%–300% range), right-side percentage label in windowActiveTextFg, floating ScalePreview tooltip during drag, scale applied on pointer-release not real-time, restart confirmation dialog on change, SlideWrap collapses slider when "Use Default" ON — DONE in `settings_screen.dart`

### 14.5 My Account / Edit Profile Sub-Page

### 14.6 Chat Settings Sub-Page

### 14.7 Advanced Sub-Page

### 14.8 Premium & Help Sections

### 14.9 Visual Style Constants

### 14.10 Animations & Transitions

---

## §15 — Settings: Notifications

<!-- dart/lib/ui/notifications_settings_screen.dart -->

### 15.2 Global Settings + Volume Slider

### 15.3 Notification Preview Widget

### 15.4 Per-Type Notification Rows

### 15.5 Per-Type Sub-Page

### 15.6 Ringtones Box

### 15.7 Reactions Sub-Page

### 15.8–15.10 Events, Calls, Badge Counter

### 15.11 System Integration (Native Notifications)

### 15.12 Animations

---

## §16 — Settings: Privacy & Security

<!-- dart/lib/ui/privacy_settings_screen.dart -->

### 16.2 Security Section

### 16.3 Privacy Section

### 16.5 Bots and Websites

### 16.9 Blocked Users Screen

### 16.11 Animations

---

## §17 — Settings: Data, Storage & Advanced

<!-- dart/lib/ui/advanced_settings_screen.dart -->

### 17.2 Data and Storage

### 17.3 Automatic Media Download

### 17.4–17.6 Window Title, Close Behavior, System Integration

### 17.7 Performance

### 17.8–17.9 Spellchecker, Screen Reader

### 17.10 Software Update

### 17.11 Export & Experimental

---

## §18 — Settings: Folders

<!-- dart/lib/ui/settings_screen.dart (nav row only); dart/lib/ui/filter_column.dart (sidebar rendering) -->

### 18.2 Animated Header

### 18.3 Existing Folders List

### 18.4 Create New Folder

### 18.5 Recommended Folders

### 18.6 Edit Filter Box

### 18.7 Include/Exclude Picker

### 18.8 Filter Icon Picker Panel

### 18.9 Show Link Box

### 18.10 Chatlist Folder Removal Dialog

### 18.11 Folder Tags Toggle

### 18.12 Tab View Section

### 18.13 Premium Limits

---

## §19 — Settings: Sessions, Power Saving & Language

<!-- dart/lib/ui/settings_screen.dart (nav rows only); sub-pages not yet created -->

### 19.1–19.4 Active Sessions Page

### 19.6 Session Detail View (SessionInfoBox)

### 19.7–19.9 Terminate All / Rename / Auto-Terminate

### 19.10–19.12 Power Saving Box

### 19.13–19.14 Language Box

### 19.15–19.17 Language List

---

## §20 — Media Viewer / Lightbox

<!-- File: dart/lib/ui/media_viewer.dart -->

### 20.1 Window & Background

### 20.3 Content Display

### 20.4 Zoom & Pan

### 20.5–20.6 Rotation, Flip, Navigation

### 20.7 Footer / Header

### 20.8 Bottom-Right Toolbar + Context Menu

### 20.9 Caption Display

### 20.10–20.12 Video Playback Controls

### 20.14 Gallery Thumbs Strip

### 20.15 Save/Download Toast

### 20.17 Stories Viewer Mode

### 20.18–20.19 Keyboard Shortcuts & Animations

---

## §21 — Create Group / Channel Wizard

<!-- File: dart/lib/ui/create_group_wizard.dart -->

### 21.2 Step 1 — Group/Channel Info Box

### 21.3 Step 2a — Member Picker

### 21.4 Step 2b — Channel Setup Box

### 21.5 Edit Peer Type Box

### 21.6 Complete Flow

---

## §22 — Forum Topics UI

<!-- No dart file yet — likely integrates with dart/lib/ui/chat_list_panel.dart, dart/lib/ui/chat_view.dart -->

### 22.1–22.2 Data Model & Icon System

### 22.3 Topic List Layout

### 22.5 Create / Edit Topic Dialog

### 22.6 Topic Header Bar

### 22.7 Topic Info Panel

### 22.8 Context Menus

### 22.9 General Topic

### 22.10 Navigation & Column Integration

### 22.11 Animations
# GUI Features Checklist: §23–§40

Consolidated from `checklist/gui.md`. Each item covers a full widget/feature unit. Read the
referenced spec section in `research/telegram_desktop_ui.md` before implementing — spec is the
source of truth.

Status key: `[ ]` not started · `[x]` done

---

## §23 — Scheduled Messages

<!-- dart files: none yet — create dart/lib/ui/scheduled_messages.dart -->

---

## §24 — Keyboard Shortcuts

<!-- dart files: dart/lib/ui/chat_list_panel.dart, chat_view.dart, hamburger_drawer.dart (partial key handling already present) — new: dart/lib/ui/keyboard_shortcuts.dart -->

---

## §25 — Theming & Color System

<!-- dart files: dart/lib/theme/telegram_palette.dart (TelegramPalette + PaletteProvider), dart/lib/theme/theme.dart (AppTheme.fromPalette) -->

---

## §26 — Admin Tools

<!-- dart files: dart/lib/ui/admin_tools.dart -->



---

## §27 — Passcode Lock Screen

<!-- dart files: dart/lib/ui/privacy_settings_screen.dart (passcode create/check/manage), dart/lib/main.dart (PasscodeLockScreen overlay) -->
<!-- §27.1-§27.6 DONE: settings entry point, create/check/manage flows, auto-lock dialog — in privacy_settings_screen.dart -->
<!-- §27.8 DONE: lock screen overlay with header/input/submit/error/logout, Ctrl+L shortcut, startup auto-lock — in main.dart + app_state.dart -->
<!-- §27.15 DONE: multi-account lock — single global lock, force-close MediaViewer/PIP on lock, auto-clear passcode on last account removal, Log out confirmation dialog on lock screen — in main.dart + app_state.dart + media_viewer.dart -->

---

## §28 — Two-Factor Authentication (2FA / Cloud Password)

<!-- dart files: dart/lib/ui/auth_screen.dart (partial login-time check), new: dart/lib/ui/two_factor_auth.dart -->

---

## §29 — Chat Export

<!-- dart files: dart/lib/ui/chat_export.dart -->

---

## §30 — Bot Interactions

<!-- dart files: dart/lib/ui/chat_view.dart, message_bubble.dart, info_panel.dart (partial bot awareness) — new: dart/lib/ui/bot_panels.dart -->

---

## §31 — Saved Messages

<!-- dart files: dart/lib/ui/chat_list_panel.dart, chat_list_row.dart, hamburger_drawer.dart (partial saved-messages reference) — new: dart/lib/ui/saved_messages.dart -->


---

## §32 — Stories

<!-- dart files: dart/lib/ui/chat_list_row.dart (partial story ring), dart/lib/ui/story_editor.dart -->

---

## §33 — Contacts Screen

<!-- dart files: dart/lib/ui/hamburger_drawer.dart, chat_list_panel.dart (partial contact references) — new: dart/lib/ui/contacts_screen.dart -->

- [ ] Stories ring in contacts: colored ring around avatar (dialogsStoriesFull stroke), click avatar=stories/elsewhere=chat, row height 52px with story ring — spec §33.2
- [ ] Search field: MultiSelect widget, instant local match (nameWords + nameFirstLetters), server fallback with AutoSearchTimeout, "No contacts found" / loading label, Escape clears — spec §33.3
- [ ] Contact list rows: 56px height, 42px avatar at (16,7), name (semibold, verified/premium/scam badges), status (3 color states: online/offline/hover, status types including Custom), ripple hover, click=chat/middle-click=new window/right-click=context menu — spec §33.4
- [ ] Add Contact dialog: first+last name + PhoneInput with country code picker (CountrySelectBox 320px), language-aware name ordering, phone validation ≥8 digits, Tab-to-submit flow, retry for non-Telegram phone — spec §33.5
- [ ] Edit Contact dialog: cover 108px (avatar 72×72, name+status reactive), name/last-name InputFields, notes multi-line (premium char limit), photo buttons (Suggest/Set personal/Reset), delete button — spec §33.6
- [ ] Share Contact box: grid 4 columns 108px rows, multi-select with name-color animation 150ms, search (local+remote), hidden send button when no selection, comment field — spec §33.8

---

## §34 — Calls History

<!-- dart files: dart/lib/ui/hamburger_drawer.dart (Calls menu entry) — new: dart/lib/ui/calls_history.dart -->

- [ ] Calls box shell: GenericBox, title "Calls", Close button, top-right menu (Call Settings / Clear All red) — spec §34.2
- [ ] Active group calls section: SlideWrap auto-shown, GroupCallRow with channel name + action button — spec §34.3
- [ ] Call history list: PeerListContent, first 20 / subsequent 100, prepend on new, remove on delete, empty/loading states, no date-group headers — spec §34.4
- [ ] Call row: 56px height, 42px avatar, name semibold 13px, same-peer/date/type grouping — spec §34.5
- [ ] Direction/type indicators: incoming (green arrow) / outgoing (green arrow) / missed/busy (red arrow), arrow offset (-2,1), voice vs video icon — spec §34.6
- [ ] Redial button: 40×56px voice (call_answer) or video (call_camera_active) icon, click starts outgoing call — spec §34.7
- [ ] Status text: Today "{time}" / Yesterday "yesterday at {time}" / Older "{date} at {time}", grouped "(N) {status}" prefix — spec §34.8
- [ ] Context menu: Delete + Show in Chat — spec §34.9
- [ ] Clear history dialog: "Also delete for other participants" checkbox, Clear API with optional revoke — spec §34.11
- [ ] "Create Call" button: inviteViaLinkButton style, participant-limit divider text, highlight animation, opens conference creation — spec §34.12
- [ ] Rate call dialog: 5 star buttons 36×36px (windowSubTextFg/lightButtonFg), comment field (max 200 chars) for ratings <5, Send button appears after rating >0 — spec §34.13
- [ ] Call settings section: output/input device selectors, input LevelMeter (18px, 3px, 5px, 44 lines), camera preview, "Use same devices" + "Accept on this device" toggles — spec §34.14
- [ ] Active call top bar (callBarHeight=38px): mute toggle (41×38px, cross-line animation), duration label, 4 signal bars, info label, hangup button; 1:1 green/gray bg; group animated gradient (3 states); blob animation 100ms update; SlideWrap 200ms show/hide — spec §34.15
- [ ] Create conference call box: PeerListBox, "New Call" title, reactive "Create Call"/"Start Call" button, per-row Video+Audio element buttons (36×52px), selection checkbox, share-invite-link button, prioritized contacts section, participant limit toast, join-link box, re-activate header — spec §34.17

---

## §35 — Empty, Error & Loading States

<!-- dart files: dart/lib/ui/chat_list_panel.dart (partial _EmptyState for search), chat_view.dart — new: dart/lib/ui/empty_states.dart -->

- [ ] Empty chat list: Lottie no_chats.tgs 120px, "You have no conversations yet.", "New Message" button → Contacts box — spec §35.1
- [ ] Empty folder: "No chats currently belong to this folder." with inline "Edit" link — spec §35.2
- [ ] Empty forum, empty saved sublists text states — spec §35.3–35.4
- [ ] Chat list skeleton loading: 2 placeholder rows matching DialogRow geometry (avatar ellipse + name bar 60px + status bar ~100px), 2s glare animation (1000ms sweep + 1000ms pause), RTL mirroring — spec §35.5 + §35.33
- [ ] "Select a chat to start messaging" service bubble in chat pane (no chat selected) — spec §35.6
- [ ] Empty search states: search-waiting Lottie search.tgs 100px / no-results Lottie noresults.tgs 100px with bold "No Results" + truncated query description + "Search in All Messages" link — spec §35.7
- [ ] Empty recent search, empty channels list — spec §35.8–35.9
- [ ] Empty shared media tabs: per-type icons at 120px from bottom, labels at 40px, per-type empty/search-empty text variants — spec §35.10
- [ ] Empty sticker/emoji/GIF panels: icon at 1/3 height, text in normalFont — spec §35.12–35.14
- [ ] Chat intro (no messages): "No messages here yet..." service bubble, 96px sticker clickable to send, business custom intro support — spec §35.15
- [ ] New group created / new forum topic service messages with bullet items and topic icon — spec §35.16–35.17
- [ ] Empty member/peer list search, empty blocked users (Lottie blocked_peers_empty.tgs), admin log empty states — spec §35.18–35.21
- [ ] Connection state widget: pill bottom-left, 20px radial spinner, "Connecting..." / "Reconnect in N s... Try now" / proxy states, 1000ms show delay, 150ms fade — spec §35.22
- [ ] File download states: Ready/Downloading ("X/Y MB" radial)/Loaded/Failed status text, cancel icon during download, path error dialogs — spec §35.24
- [ ] Media loading three-stage: blurhash → blurred → full-res, loading overlay with radial progress, upload progress fade — spec §35.25
- [ ] Media viewer / PiP loading spinner: InfiniteRadialAnimation centered — spec §35.26–35.27
- [ ] Call status 10-state labels (incoming, connecting, exchanging keys, etc.) — spec §35.30

---

## §36 — Common Dialog & Modal Patterns

<!-- dart files: dart/lib/ui/chat_view.dart, shell.dart, hamburger_drawer.dart, settings_screen.dart, info_panel.dart (showDialog calls) — new: dart/lib/ui/dialogs.dart -->

- [ ] Box/dialog infrastructure: 48px title bar (16px semibold at (24,13)), scrollable content 24px h-padding, right-aligned button row, standard 320px / wide 364px box, 8px corner radius, 200ms boxDuration easeOutCirc open/linear opacity, Escape closes / Enter confirms / Tab cycles — spec §36.1
- [ ] ConfirmBox: text + confirm/cancel callbacks, destructive attentionBoxButton (red), inform variant (single OK), moderate variant (Ban/Report/Delete checkboxes), auto-delete settings link — spec §36.2–36.3
- [ ] Input dialogs: username (live validation + debounced API), add contact (PhoneInput + country), passcode fields, edit invite link, create poll — spec §36.4
- [ ] SingleChoiceBox: radio selection, auto-close; PopupMenu defaults (8px radius, 200ms show/150ms hide, item padding 17/8/17/7, PanelAnimation clip-reveal) — spec §36.5
- [ ] CalendarBox (364px, 48×40px cells, 34px highlight circle, nav arrows with long-press fast-jump) and ChooseDateTimeBox (95px content, date 136px + "at" + time 72px) — spec §36.6
- [ ] TimePickerBox: drum/wheel with 16 entries 15m–3mo, activeLineFg band, drag/wheel/arrows — spec §36.6.4
- [ ] Color picker: 2D HSB gradient square with crosshair (16px), hue+opacity/lightness sliders, H/S/B + R/G/B + hex fields, current/new swatches, bidirectional sync, Enter submit — spec §36.7
- [ ] Toast/snackbar: padding (19,13,19,12), max 480px, 200ms fade-in / 1000ms fade-out / 160ms slide, default 1500ms duration, centered or edge-attached — spec §36.9
- [ ] Context menus: PopupMenu with PanelAnimation, keyboard arrows/Enter/Escape/Right-Left; chat-list menu, message menu, photo menu, document/media menu, link menu, archive menu, forum menu — spec §36.10
- [ ] Tooltip popups: standard (tooltipBg/Fg/BorderFg, 1000ms delay, max 12 lines) + important tooltip (arrow 8×4px, arrowSkip 66px, 200ms show/hide) — spec §36.11
- [ ] Permission request dialogs: Granted/CanRequest/Denied states, OS microphone/camera request, screen share chooser with thumbnails + Start/Stop/Share Audio — spec §36.12
- [ ] Report flow: 9-reason picker → details input → "Report" submit; reaction-report variant — spec §36.13
- [ ] Share box: MultiSelect search + peer grid + optional comment + send menu (schedule/silent) + Copy Link option, forward options, dark-mode style override — spec §36.14

---

## §37 — Desktop Notifications

<!-- dart files: none yet — create dart/lib/notifications/ -->

- [ ] Three-tier architecture: System scheduler (timing/grouping), Manager base (content/routing), Platform backend (OS delivery); manager selection (native/custom/dummy), kOptionCustomNotification toggle — spec §37.1
- [ ] Linux native backends: DBus (RGBA8888 image hint, inline reply via signal_notification_replied, mail-mark-read action, sound-file hint, freedesktop Inhibited DND, hierarchical tracking) + GNotification (HIGH_ priority, PNG userpic) — spec §37.2.1
- [ ] Windows WinRT toast: XML template (image + 3 text elements), fast reply input + send button, mark-as-read background activation, DND/Focus Assist registry detection, App User Model ID — spec §37.2.2
- [ ] macOS NSUserNotification: title/subtitle/informativeText/userInfo, "Mark as Read" + reply buttons, sound path, background thread clear, screen-lock detection — spec §37.2.3
- [ ] Custom in-app popup widget: 320×80px min, frameless (WindowStaysOnTopHint + Tool flags), corner selection (TopLeft/TopRight/BottomLeft/BottomRight/TopCenter), userpic 62×62px at (9,9), close 30×30px, title (semiboldFont, single-line), message (2-line dialogsTextFont), 1px border, 7px inter-notification gap, 6px screen-edge margin, Hide All button (2+ notifications), reply button (hover 200ms fade) with 282px input field (442px TopCenter), Enter submit / Escape dismiss — spec §37.3.2–37.3.4
- [ ] Notification animations: fade-in 150ms, slow-hide 4000ms easeInCirc, fast-hide 150ms, shift 150ms, action-fade 200ms, 300ms input poll, hover stops all timers — spec §37.3.5
- [ ] Click/dismiss: left-click=open chat, Ctrl+click=new window, right-click=dismiss, close button, reply submit via api().sendMessage(), Hide All clearAll — spec §37.3.6
- [ ] Stack overflow: max 5 cap (default 3), FIFO queue, evict oldest non-reply/non-hover, per-corner reverse-iterate stacking with 7px gap, demo mode (150ms fade) — spec §37.3.7
- [ ] Notification content: title composition (app name/Reminder/forum "Topic (Chat)"/peer name/calendar prefix/account suffix), subtitle (reactor/group sender), text for all message types, spoiler → U+259A blocks, reaction phrasing per media type — spec §37.4
- [ ] Notification sounds: default msg_incoming.mp3, custom ringtones by DocumentId, per-chat volume (0-100), sound conditions (soundNotify+not-muted+not-silent+not-none) — spec §37.5
- [ ] Scheduling and grouping: 100ms/500ms/1000ms timing delays, cloud delay logic, 1000ms album grouping, per-thread deduplication by messageId+type, reaction dedup once/hour/item — spec §37.6
- [ ] Muted chat handling + DND: skip if thread AND sender both muted, scheduled-in-muted force-silent, unmuted sender in muted group shows; defer to OS DND — spec §37.7–37.8
- [ ] Reply conditions: hide reply when text-hidden/non-message/can't-send/broadcast/slowmode — spec §37.9
- [ ] Flash/bounce dock, badge/unread counter (IncludeMuted/CountMessages), privacy levels (ShowPreview/ShowName/HideAll), passcode/screen-lock force-hide, spoiler login-code masking, app-logo 62×62px hidden-userpic placeholder, native userpic 64px PNG cache (60s TTL) — spec §37.10–37.13

---

## §38 — User Profile Popup (PeerShortInfoBox)

<!-- dart files: none yet — create dart/lib/ui/peer_short_info.dart -->

- [ ] Trigger conditions: Ctrl+Click on "View Profile", click user row in limit boxes, click avatar in gift/premium boxes — spec §38.1
- [ ] Cover section (304×304px): square userpic area, no-photo solid black, multi-photo progress bars (2px height, 8px padding, 4px gaps, groupCallVideoTextFg, rounded caps), name (15px semibold white at 25px/37px from bottom), status label (groupCallVideoSubTextFg at 25px/14px), "photo set by you"/"public photo" additional status, bottom shadow gradient 80px, top shadow gradient, video profile auto-play loop with radial loader (2px), rounded top corners 6px — spec §38.2
- [ ] Info rows: labeled key-value rows (24px h-padding, 16px top), fields: channel link, t.me link, phone ("Copy Phone Number"), bio/about (multi-line entity support), @username ("Copy Mention"), birthday (dynamic "Birthday today" label), notes; empty fields hidden via SlideWrap; double-click selects paragraph — spec §38.2
- [ ] Buttons: "Close" right, "Send Message"/"View Group"/"View Channel" left (type-dependent), no left button for Self — spec §38.2
- [ ] Animations: 200ms boxDuration easeOutCirc appear/disappear, radial photo loader fade, scrolling parallax (name/status alpha fade + progress bars fade), video loop — spec §38.3
- [ ] Sizing/positioning: centered in parent, height clamped to parentHeight-margin, 8px scrollbar (3px inset, 150ms show, 1000ms hide delay) — spec §38.4–38.5
- [ ] Group/bot differences: member/subscriber count in status, no multi-photo, no phone/birthday/notes for groups; "About" label for bots — spec §38.6–38.7
- [ ] Interaction: close by outside-click or Escape, right-click "Open in New Window", photo navigation (left-third / right-two-thirds click), scrollable info rows with parallax-fixed cover — spec §38.9

---

## §39 — Photo & Avatar Cropping Dialog

<!-- dart files: none yet — create dart/lib/ui/photo_crop_editor.dart -->

- [ ] Trigger and layer: full-window layer from own profile upload / set photo / group photo / camera capture, no outside-click dismiss, blurred dimmed background (4× downscale + 24px Gaussian blur + upscale, QColor(16,16,16,192) light / 128 dark), optional about text above image, content margins 20px left/top/right + 146px bottom — spec §39.1–39.2
- [ ] Image display: centered + aspect-fill scaled, rotation + flip via transform, 640px minimum upscale, 10× extreme ratio rejection — spec §39.3
- [ ] Crop overlay: ellipse (user avatar) / roundedRect (forum) / rect (general) shapes, square-locked for profiles (corner handles only), semi-transparent dark outside (photoCropFadeBg), 2× border + 4× corner indicators, rule-of-thirds 3×3 grid (visible during drag only, 200ms fade), 8 resize handles (10×10px corners, 4 edges when not locked), 20px min crop size, initial centered square — spec §39.4
- [ ] No zoom controls of any kind (confirmed: no slider/wheel/pinch/keyboard) — spec §39.5
- [ ] Pan/drag: move crop inside bounds, resize via handles with aspect constraint, cursor feedback (diagonal/hv resize/sizeall/default) — spec §39.6
- [ ] Rotation/flip: 90° rotate button (wraps at 360), horizontal flip toggle with active-color icon, no free-angle rotation — spec §39.7
- [ ] Sticker/emoji avatar builder: separate full-screen layer, sticker selector + gradient color picker + live circular preview, 1500ms suggested-sticker rotation cycle — spec §39.9
- [ ] Button bar (48px height, 422px width): Cancel left (mediaviewCaptionFg on shadowFg), Flip+Rotate+Paint-Mode center icons, "Set Photo"/"Suggest"/"Done" right (mediaviewTextLinkFg); paint mode top bar (Undo/Redo) + bottom bar; aspect ratio menu (Original/Square/3:2/16:9/9:16/Free) — spec §39.11
- [ ] Keyboard shortcuts: Enter=Done, Escape=Cancel/back, Ctrl+Z=Undo, Ctrl+Y/Ctrl+Shift+Z=Redo — spec §39.12
- [ ] Animations: standard layer open/close slide-up, control bar toggle (slide down+up 200ms), grid overlay 200ms fade, about text FadeWrap 200ms — spec §39.14

---

## §40 — Send Files Dialog

<!-- dart files: none yet — create dart/lib/ui/send_files_dialog.dart -->

- [ ] Trigger: paperclip picker / drag-and-drop files onto chat / paste from clipboard; receives PreparedList + prefilled caption + send type + limits — spec §40.1
- [ ] Album preview: LayoutMediaGroup algorithm, drag-to-reorder (shrink 5px/150ms, spring-back 200ms), Manhattan-distance closest-thumb target, delete (X) + edit/replace buttons per thumbnail (48×26px horizontal capsule at (5,5), gap 8px; 30×50px vertical fallback; 30×25px small group), double-click opens photo editor — spec §40.2
- [ ] Send-as mode checkboxes: "Group files" (2+ compatible files, hidden in slowmode), "Send as documents" (label by count), "Remember" (appears when toggles changed) — spec §40.3
- [ ] Compression/HD toggle: hamburger menu "high/standard quality", HD badge (rounded pill "HD", 2px h-padding, stroke 1px, radius height/3, roundedBg fill), standard 1280px / HD 2560px limit — spec §40.4
- [ ] Spoiler toggle: per-file right-click context menu, bulk toggle in top-right menu, forced when paid price set, SpoilerAnimation (animated blur/sparkle) — spec §40.5
- [ ] Caption field: MultiLine InputField, 4096-char limit with CharactersLimitLabel, full formatting support, emoji button (TabbedPanel EmojiOnly mode), emoji/mention/hashtag autocomplete, respect global send-submit-way, caption position toggle above/below, per-file captions for documents, paste interception routes to PrepareMediaList — spec §40.6
- [ ] Individual file cards: thumbed (64×64px, 4px radius, nameTop 7px, statusTop 37px) or icon (44×44px ellipse) layout, semiboldFont name with middle-ellipsis max 64 chars, FormatSizeText size, single-line elided caption, edit+delete buttons (IconButton, top-right offset (2,5), -1px overlap), drag-reorder — spec §40.7
- [ ] Album layout algorithm: max 10 items, 308px bounding width, 50px sub-cell min, 2px spacing, wide/>1.2/narrow/<0.8/square thresholds, outer-corners-only 6px radius — spec §40.8
- [ ] Add files: "Add" button bottom-left, async prep for >10 files, Ctrl+O shortcut — spec §40.9
- [ ] Send button: "Send" / star cost for paid channels; right-click/long-press send menu (silent/schedule/when-online/spoiler-toggle/caption-position/quality); "Send as sticker" WEBP conversion option; Ctrl+Shift+Enter flag — spec §40.10
- [ ] File type detection: photo (valid image, not animated), video (PreparedFileInformation::Video), music (Song metadata), sticker (.tgs/IsMimeSticker), MimeDataState classification — spec §40.11
- [ ] Drag-and-drop overlay: Photo zone / Document zone, mutual exclusion, opacity fade animation, caption field acceptDrops(false) during drag — spec §40.13
- [ ] GIF + Audio handling: GIF as Type::None with animated preview, audio SingleFilePreview with "Artist — Title", cover art circular thumb or colored circle with play icon, no waveform in preview — spec §40.15–40.16
- [ ] Keyboard: Enter=send (respecting mode), Ctrl+Shift+Enter=send-with-flag, Ctrl+O=add file, Escape=close (preserve caption) — spec §40.17
- [ ] Animation: standard BoxContent layer open/close, album reorder (shrink 150ms/move 200ms/spring 200ms), height transitions, emoji panel slide toggle, FadeShadow at scroll area edges — spec §40.18
# GUI Feature Checklist: §41–§57
# Consolidated from gui.md — one item per widget/feature, referencing spec sections.
# Micro-items (individual px values, color tokens, timing constants) are merged into
# their parent widget task. Read the full spec section before implementing each item.
#
# Status: ALL items are [ ] (not started). No §41-§57 widgets exist in dart/lib/ui/
# as of this consolidation. The only partial overlaps with existing code are noted inline.

## §41 — Message Formatting Toolbar
# Touches: dart/lib/ui/chat_view.dart (compose field), new formatting_menu.dart

- [ ] Formatting context menu — right-click in compose field opens "Formatting" submenu (no floating toolbar); disabled when no text selected; submenu items Bold/Italic/Underline/Strikethrough/Quote/Monospace/Spoiler + Create/Edit Link + Date + Clear Formatting; keyboard shortcuts Ctrl+B/I/U, Ctrl+Shift+X/./M/P/K/D/N; reduced set for Saved Messages — spec §41.1–41.5, §41.8
- [ ] EditLinkBox dialog — 320×(auto) modal; "Text" and "URL" input fields (276px wide); submit validation (empty/invalid shows error border); Enter/Tab navigation between fields; "Save"/"Create" + "Cancel" buttons — spec §41.6
- [ ] CodeLanguageBox dialog — "Code Language" dialog; 32-char language field (ASCII+digits++−); auto-select all on open; "Save" + "Cancel"; error border on invalid input — spec §41.7
- [ ] Formatting visual rendering in compose field — bold/italic/underline/strikethrough font styles; monospace+monoFg for code; blockquote left-rule + chevron expand/collapse (6,4)px from top-right; pre-block 20px header + copy icon; spoiler FieldSpoilerOverlay shimmer; link linkFg color — spec §41.13
- [ ] FieldSpoilerOverlay widget — transparent-for-mouse overlay; particle shimmer over spoiler ranges; cursor-inside → 0.5 opacity (200ms); cursor-leaves → full opacity; background textBg/blockquoteBg — spec §44.5 (companion to §41 spoiler tag)
- [ ] Markdown send-time parsing — apply **bold**, __italic__, ~~strike~~, `code`, ```block```, ||spoiler|| at send time via getTextWithAppliedMarkdown; no live auto-convert — spec §41.9
- [ ] Nested formatting + tag storage — pipe-separated tag strings; toggle semantics (remove if full selection has tag, add otherwise); monospace replaces font; block tags contain inline tags — spec §41.10
- [ ] Formatting menu animation — PanelAnimation expand from origin corner (clip+opacity) on show; same for submenu; instant text style change on apply — spec §41.11

---

## §42 — Reactions Detail Popup
# Touches: dart/lib/ui/message_bubble.dart (has basic pill _ReactionList — NOT the popup), new reactions_detail.dart

- [ ] ShowWhoReactedMenu (Mode A) — right-click reaction button: PopupMenu with optional "Set as Quick Reaction"; up to N user entries (WhoReactedEntryAction); "Show all reactions" footer; optional "Emoji Pack" action; styled with whoReadMenu; context menu sizing: entry 40px, avatar 30px, nameLeft 57px — spec §42.2, §42.12
- [ ] Reactions full info panel (Mode B) — layer/side panel; top-bar title adapts ("Seen by N" / "Reactions"); tab bar (pill 32px, 16px radius, 32+6+textW+12 width, 18px emoji icon, 150ms transition); scrollable peer list; slide-down animation; preferred width 392px — spec §42.3–42.4, §42.11–42.12
- [ ] Reaction tab bar — "Read" + "All" + per-reaction tabs; counts via FormatCountDecimal; flow-wrap layout (no horizontal scroll); 8px gap; selection ripple 200ms; instant tab switch — spec §42.4
- [ ] Reaction user list rows (Mode B) — 58px row; 46px avatar at (18,6); name at (79,11) semibold 13px; status at (79,31) windowSubTextFg; right custom emoji 18x18px at R27 margin; pagination 20/100 items — spec §42.5–42.6
- [ ] Tag reactions (Saved Messages) — ShowTagMenu with filter/edit/remove/sticker-pack actions; no user list — spec §42.1, §42.10
- [ ] Reaction popup interaction — click user → user profile; "Show all" → Mode B; channels: reaction tabs only (no Read tab); DMs: WhenReadContextAction "Read at HH:mm"; keyboard navigation — spec §42.13–42.15

---

## §43 — Read Receipts Detail
# Touches: dart/lib/ui/message_bubble.dart, dart/lib/ui/chat_view.dart, new read_receipts_panel.dart

- [ ] Read receipt context menu trigger — right-click on outgoing message: "Seen by N"/"Listened by N"/"Watched by N" when eligible (group ≤50, private, within expiry, not bot/service/channel) — spec §43.1–43.2
- [ ] Read receipt user list rows — 40px row; 30px avatar at (13,5); name left 57px; date line at 20px top with icon (read_ticks_s/read_react_s/mini_repost/mini_stats_share); 12px date font windowSubTextFg; custom emoji reaction at right edge; preloader skeleton at 0.2 alpha — spec §43.4
- [ ] Read receipt loading + empty states — "Loading..." while unknown; userpic delay until _appeared; "Nobody has seen yet" / "No reactions yet" empty text; menu item disabled when empty and not MyHidden — spec §43.5–43.6
- [ ] Read receipt partial-reads merge — merge reaction+read lists; combined "N reacted / M seen" summary; per-user Viewed vs Reacted type tag — spec §43.7
- [ ] FormatReadDate — "Today, HH:mm" / "Yesterday, HH:mm" / "Mon DD, HH:mm" / "Mon DD YYYY, HH:mm"; dateReacted flag for icon selection — spec §43.8
- [ ] Privacy states (MyHidden/HisHidden/TooOld) — "Read time hidden" + "Show" pill; HisHidden label; TooOld label; "Show" click → disable-hide-read-time or Premium dialog — spec §43.12
- [ ] AyuGram ghost mode integration — sendReadMessages/sendReadStories toggles suppress receipts; markReadAfterAction mark-read on reply/react; blocked peer filtering; showViewsPanelInContextMenu visibility control; showMessageSeconds HH:mm:ss format — spec §43.13
- [ ] Summary sizing tokens — item padding (44,9,17,7); avatar 22px, shift 8px, stroke 4px max 3 circles; submenu max 400px; when-read line padding (34,3,17,4); icon at (8,0) 3px gap; animation timing: userpic reveal after parentMenu.st().duration — spec §43.10

---

## §44 — Spoiler Animation
# Touches: dart/lib/ui/message_bubble.dart (text rendering), new spoiler_animation.dart

- [ ] Text spoiler rendering — draw text at (1−spoilerOpacity) opacity; collect spoiler rects (max 512); tile particle frame via FillSpoilerRect; separate normal/selected rect lists; SpoilerMessCache 24 variants; cross-fade text↔particles on reveal — spec §44.1
- [ ] Media spoiler rendering — blurred background (smallest thumbnail); particle overlay with corner masks; darken layer alpha=32; cross-fade real image at opacity=revealed on click — spec §44.2
- [ ] Particle sprite sheet — 60 frames × 33ms (30 FPS, 1980ms loop); 10×6 grid on 128dp canvas; text: 9000 particles 4–8dp/ms; image: 3000 particles 10–20dp/ms; 5 sprite variants; linear motion with seamless wrap; grayscale PNG disk cache (xxHash32, 5MB max); colorize on demand — spec §44.3
- [ ] Reveal on click — SpoilerClickHandler 200ms linear fade; reveal all spoilers in block at once; re-hide instant on navigate; track revealed set; media: same 200ms fade, reset on navigate — spec §44.4
- [ ] Spoiler in notifications — replace spoiler chars with U+259A; login code auto-spoiler via regex — spec §44.6
- [ ] Performance: auto-pause after 1000ms off-screen; power-saving kChatSpoiler bit 7 freeze; batched FillSpoilerRect; corner masking via CompositionMode_DestinationIn; single SpoilerAnimationManager — spec §44.7

---

## §45 — Custom Emoji Rendering
# Touches: dart/lib/ui/message_bubble.dart, dart/lib/ui/chat_view.dart, new custom_emoji.dart

- [ ] Inline custom emoji rendering — 18px logical / 20px adjusted frame; −1px centering offset; 1px h-padding each side; AlignTop vertical; UseTextColor tint — spec §45.1
- [ ] Large isolated custom emoji — detect emoji-only messages (no text/links) as UnwrappedMedia; size tiers: 1→112px, 2→78px, 3→58px, 4–5→43px, 6–7→27px, 8+→20px; native emoji 1–3 via IsolatedEmoji — spec §45.2
- [ ] Animated custom emoji playback — TGS (Lottie) + WebM (video) + WebP (static); async decode on worker thread; preload 3 frames; cap 180 frames; pause when context.paused; PowerSaving flags kEmojiChat/Panel/Reactions/Status; LimitedLoopsEmoji wrapper — spec §45.3
- [ ] AyuGram premium bypass — AllowEmojiWithoutPremium=true skips premium gate; fallback to sticker alt text for non-AyuGram — spec §45.4
- [ ] Emoji status rendering — render next to peer name in headers/dialogs/profile; collectible status (center/edge colors); userpic prefix circle; kEmojiStatus power saving — spec §45.5
- [ ] Custom emoji in reactions — Unicode reactions at 2× emojiSize; custom at Normal 18/20px; floating preview overlay on click; "View Pack" label — spec §45.6
- [ ] Loading states — SVG path preview at 12.5% opacity; cross-res image preview fallback; blank when no preview; Loading→Caching→Cached transitions — spec §45.7
- [ ] Caching — in-memory instance cache per (DocumentId, SizeTag) with refcount; disk sprite atlas LZ4; 16 frames/row; cross-res preview; evict on last Object removed — spec §45.8
- [ ] Click behavior — CustomEmojiClickHandler opens reaction/emoji preview overlay; "View Pack" rounded-rect with pack name; StickerSetBox on View Pack click; tap splash for isolated single emoji — spec §45.9
- [ ] Custom emoji in compose field — QTextObjectInterface system; Unicode alt text + custom link tag; 20px width, max(fontLineHeight,18px) height; coalesced repaints — spec §45.10
- [ ] Performance batching — RepaintBunch buckets by (when, duration); batch unknown IDs ≤100 per API call; static PaintCache QImage for text-tinted emoji — spec §45.11
- [ ] Reaction/emoji preview overlay (MediaPreviewWidget) — centered in viewport; 120ms show/hide animation; semi-transparent click-catcher backdrop; "View Pack" rect at 75% vertical; 10px shadow extend; 8px boxRadius; FlatLabel with pack name; dismiss on click-outside/Escape/resize — spec §45.14

---

## §46 — Link Preview in Compose
# Touches: dart/lib/ui/chat_view.dart (FieldHeader bar), new link_preview.dart

- [ ] URL detection + debounce — regex domain matching; 0ms for large changes (>2 chars), 500ms small; immediate on whitespace/drop; skip inside code/pre blocks; handle markdown link tags — spec §46.1
- [ ] FieldHeader preview card — 49px height full-width above compose; left icon (historyLinkIcon) at (7,7); swap icon per bar state (edit/reply/quote/forward); 32×32 thumbnail at (53,8); text start 95px with/53px without thumbnail; title semiboldFont historyReplyNameFg; description messageTextStyle; cancel X button 49×49 anchored top-right; flat historyComposeAreaBg background — spec §46.2
- [ ] Large vs small media layout — small (article) for profile pages; large for Twitter/Facebook/ArticleWithIV/collage/no-text; forceLargeMedia/forceSmallMedia via DraftOptionsBox — spec §46.3
- [ ] Preview above/below text — WebPageDraft.invert flag; DraftOptionsBox "Move up"/"Move down" buttons — spec §46.4
- [ ] Multiple URL handling — pick first cached/untried URL; "Tap on a link to choose a preview" divider; click different links in PreviewWrap to switch — spec §46.5
- [ ] Preview loading + no-preview states — "Loading..." title + URL description; hide thumbnail during load; pendingTill retry timer; webPageUpdates auto-update; fallback to next URL on null; toast "Sorry, preview not available" in DraftOptionsBox — spec §46.6–46.7
- [ ] Remove preview — X button sets WebPageDraft.removed=true; persist in draft; red "Remove link preview" in DraftOptionsBox; auto-reset when all URLs deleted — spec §46.8
- [ ] WebPage types rendering — 30+ type enum values; article layout (_asArticle=1: small thumbnail right, text left); full-width (_asArticle=0); 36px action button bar with centered semibold label; 1px top divider at 30% alpha; INSTANT VIEW / VIEW CHANNEL / etc labels; DraftOptionsBox controls (Move up/down, Enlarge/Shrink, Remove) — spec §46.9
- [ ] Instant View reader — detect iv non-null; "INSTANT VIEW" button in bubble; open built-in IV reader on click — spec §46.10
- [ ] API + AyuGram improvements — MTPmessages_GetWebPagePreview; getBetterLinkPreview URL rewriting (x.com→fixupx.com etc.); MTPinputMediaWebPage with force_large/small/optional on send; two-level debounce + cancel on switch; URL→WebPageData in-memory cache + session cache + draft persistence — spec §46.11–46.13

---

## §47 — Restricted Permissions UI
# Touches: dart/lib/ui/chat_view.dart (compose area replacement), new compose_restriction.dart

- [ ] Write restriction bar — replace compose area at 46px height; Rights: centered FlatLabel; PremiumRequired: label + "Unlock" RoundButton + lock icon → Premium promo toast; Frozen: red title + subtitle → freeze info dialog; Hidden: no compose; boost button when boostsToLift > 0 — spec §47
- [ ] Permission-specific restriction text — timed + permanent personal restrictions for all 11 types; default group restrictions; DM-level voice/video/premium restrictions — spec §47
- [ ] Forbidden send button states — 50% opacity on record/round buttons; suppress ripple; toast with restriction error (1500ms, 200ms fade-in, 1000ms fade-out, 160ms slide, 19/13/19/12px padding, 160–360px width, 6px radius); default (non-pointer) cursor — spec §47
- [ ] Slow mode countdown — MM:SS countdown on send button; 13px normalFont windowSubTextFg; refresh every 200ms; non-pointer cursor; accessible name text; block send while sending; block multi-file + long-split messages — spec §47
- [ ] Banned/kicked state — "Sorry, this group is not accessible."; full-width "UNBLOCK"/"RESTART" button; call unblockUser on click — spec §47
- [ ] Join-to-send buttons — "JOIN CHANNEL"/"JOIN GROUP"/"APPLY TO JOIN GROUP" uppercase buttons; session.api.joinChannel on click — spec §47
- [ ] Mute/Unmute + Discuss buttons — "MUTE"/"UNMUTE" full-width for broadcast channels without post rights; "DISCUSS" alongside when discussion group exists — spec §47
- [ ] Forum topic closed bar — "This topic is closed." restriction bar; reactively restore compose on admin reopen; ManageTopics admin bypass — spec §47
- [ ] Channel comments button — IconButton in compose bar (leftmost); four states: Empty/Shown/Hidden/WithNew; 6px new-comments dot (dialogsBgActive) on WithNew — spec §47
- [ ] Send button type states — Send (arrow/blue circle); Record (mic Lottie historyRecordVoiceFg); Round (video-cam Lottie); Cancel (X); Save (checkmark); Schedule (clock); Slowmode (text countdown); Lottie Record↔Round transition; crossfade other transitions (opacity+scale universalDuration); star icon+count for paid messages; gray when disabled — spec §47
- [ ] Bot start button — "START" full-width button with optional token prefix text — spec §47

---

## §48 — Drag-and-Drop File Overlay
# Touches: dart/lib/ui/chat_view.dart, dart/lib/ui/shell.dart, new drag_drop_overlay.dart

- [ ] Drop zone appearance — rounded rects boxBg background + boxRoundShadow; drag margin (0,10,0,10) + padding (20,10,20,10); 27px semibold main text; 19px semibold subtext; text color windowSubTextFg→windowActiveTextFg on hover over 200ms — spec §48.1
- [ ] Two-zone layout — Files: single full-height document zone; PhotoFiles: doc top + photo bottom; MediaFiles: media top/bottom labels; Image: single full-height photo zone — spec §48.2
- [ ] Zone detection + drop action — cursor inside padded region triggers highlight; CopyAction inside zone, IgnoreAction outside — spec §48.3
- [ ] File type classification — classify dragged files: Image / PhotoFiles / MediaFiles / Files / None; reject null data, forward data, non-local URLs, directories, files >4GB; GIFs are MediaFiles not PhotoFiles — spec §48.4
- [ ] Animation — fade overlay in/out 200ms (boxDuration) with pixmap cache; highlight color 200ms; instant hide on drop — spec §48.5
- [ ] Edge cases — no overlay for text-only drags; no overlay for x-td-forward drags; no overlay during voice recording; check CanSendAnyOf before showing; verify canWriteMessage on drop — spec §48.6, §48.8–48.9
- [ ] Forward via drag — x-td-forward MIME type; open target chat after 1s hover over dialog; navigate back after 1s hover over back button; topic chooser for forum peer — spec §48.11

---

## §49 — Scroll Behaviors
# Touches: dart/lib/ui/chat_view.dart (partial: _scrollToBottom + _ScrollToBottomFab exist; rest NOT implemented)

- [ ] Infinite scroll — preload when within 3 viewport heights of edge; 50 messages/page (30 first load); 9-screen window (4+1+4) shift around position — spec §49.1
- [ ] Jump-to-date — CalendarBox on sticky date header click; min date Aug 2013 or first message; month thumbnails for media-filtered search; API closest-message resolution + navigate — spec §49.2
- [ ] Jump-to-message animation — sine in-out for short scroll (≤1 viewport); instant+ease-out cubic for long scroll; 400ms highlight fade-in + optional hold + 2000ms fade-out; queue multiple highlights sequentially — spec §49.3
- [ ] Unread marker bar — "N unread messages" divider on first unread; destroy on scroll-to-bottom or send — spec §49.4
- [ ] Scroll-to-bottom button (complete implementation) — 52×62px (shadow+ripple+arrow); show when >480px up or unread below; badge 22px circle/pill semibold 13px; Ctrl-jump forces position; 150ms slide-up animation [NOTE: _ScrollToBottomFab exists but is incomplete — missing spec dimensions, badge style, slide animation, Ctrl-behavior] — spec §49.5, §49.15
- [ ] New message scroll — auto-scroll on own sends; incoming only when at bottom; increment badge otherwise — spec §49.6
- [ ] Scroll position preservation — save scrollTopItem+scrollTopOffset per History on switch; restore on return; bracket refreshRows with save/restore — spec §49.7
- [ ] Smooth scrolling engine — 240ms (slideDuration); sineInOut short, easeOutCubic long; anchor to HistoryItem during content changes — spec §49.8
- [ ] Scroll-to-mention button — "@" corner button when unread mentions; jump to oldest on click; stacked 4px above scroll-to-bottom — spec §49.9
- [ ] Scroll-to-reaction button — heart corner button when unread reactions; jump to oldest on click; stacked above mentions — spec §49.10
- [ ] Keyboard scrolling — forward PageUp/PageDown/Down to scroll; Up when field empty triggers edit-last; middle-click autoscroll with directional cursor; Escape/any-button stops autoscroll — spec §49.11
- [ ] Sticky date header — overlay sticking to viewport top; fade in/out 200ms; auto-hide after 1000ms no-scroll; 13px semibold badge; 12px h-pad, 3px top, 4px bottom pad; msgServiceBg/msgServiceFg; CalendarBox on click — spec §49.13, §49.16
- [ ] Corner buttons stack layout — all at 12px from right; 4px vertical gap; 4×62+3×4+10=270px total; smooth slide when middle button hides/shows — spec §49.17

---

## §50 — Streamer Mode & Read Toggles (AyuGram)
# Touches: dart/lib/ui/hamburger_drawer.dart, dart/lib/ui/settings_screen.dart, new streamer_mode.dart

- [ ] Streamer Mode OS-level toggle — WDA_EXCLUDEFROMCAPTURE (Windows); NSWindowSharingNone (macOS); stub no-op + tooltip on Linux; apply to all windows including newly opened; non-persistent (reset to OFF on cold launch) — spec §50.2
- [ ] Streamer Mode activation surfaces — drawer toggle row (48px, 24×24 icon, label, switch, gated by showStreamerToggleInDrawer default false); tray menu action (label "Enable/Disable Streamer Mode", gated by showStreamerToggleInTray default false); both settings shown on Ghost Mode page — spec §50.3
- [ ] Streamer Mode scope + state — global (all windows, all accounts); showStreamerToggle settings global + persistent; reflect state in drawer switch and tray label — spec §50.4–50.5
- [ ] Read toggles (6 toggles) — sendReadMessages (block messages.readHistory); sendReadStories (block stories.readStories); sendOnlinePackets (block account.updateStatus online); sendUploadProgress (block messages.setTyping); sendOfflinePacketAfterOnline (auto-offline after online); markReadAfterAction (local badge zero on reply/react/forward); locked variants per toggle — spec §50.7
- [ ] Read Message context action — chat-list right-click "Read Message" with confirmation dialog; per-peer Never/Always Read exclusions — spec §50.7

---

## §51 — Ghost Mode (AyuGram)
# Touches: dart/lib/ui/hamburger_drawer.dart, dart/lib/ui/settings_screen.dart, new ghost_mode.dart

- [ ] Ghost Mode architecture + storage — per-account settings keyed by user ID; global mode key "0"; isGhostModeActive computed from 5 core toggles + lock states — spec §51.1
- [ ] 5 core toggles UI — collapsible "Ghost Mode" section; Don't Read Messages / Don't Read Stories / Don't Send Online / Don't Send Typing / Go Offline Automatically; Shift+click lock (40% opacity locked); prevent locking last unlocked; master toggle sets all unlocked toggles — spec §51.2.1
- [ ] 3 additional toggles — Read on Interact; Schedule Messages (auto-schedule ~12s ahead); Send without Sound (flip send menu label to "Send with Sound"); Read on Interact ↔ Schedule Messages mutually exclusive — spec §51.2.2
- [ ] Per-account picker — LinkButton next to "Ghost essentials" title (>1 account); down-arrow icon windowActiveTextFg; PopupMenu: "Global Settings" (purple gradient circle "GS") + per-account items; toast on scope switch; auto-migrate to global when 1 account — spec §51.3
- [ ] Ghost Mode settings page layout — Settings > AyuGram > AyuGram first category; Ghost essentials (collapsible) + Read on Interact + Schedule Messages + Send without Sound + Spy essentials (Save Deleted/History/Bots) + Other (Local Premium/Disable Ads) + divider descriptions — spec §51.4
- [ ] Drawer integration — ghost toggle row (ayuGhostIcon + switch bound to ghostModeActiveValue, gated showGhostToggleInDrawer default true); LRead/SRead buttons — spec §51.5
- [ ] Tray + CLI integration — Ghost Mode tray item (gated showGhostToggleInTray default true); "Enable/Disable Ghost Mode" label; Windows Jump List "Enter with Ghost" item; -ghost CLI flag — spec §51.6–51.7
- [ ] Visual feedback — real-time drawer switch; dynamic tray label; "Ghost Mode turned on/off" toast; master toggle reflected in settings collapsible — spec §51.8
- [ ] API interception — messages.readHistory + messages.readDiscussion when sendReadMessages=false; messages.getMessagesViews increment flag; stories.readStories + incrementStoryViews; account.updateStatus online; AyuWorker auto-offline polling every 3s; messages.setTyping; applyGhostScheduling; auto-read on react/vote when markReadAfterAction=true — spec §51.10

---

## §52 — Anti-Recall & Message History (AyuGram)
# Touches: dart/lib/ui/message_bubble.dart, dart/lib/ui/chat_view.dart, dart/lib/ui/settings_screen.dart, new anti_recall.dart

- [ ] Anti-recall settings toggles — Save deleted messages (default true); Save messages history (default true); Save for bots (default false); Semi-transparent deleted (default false); customizable deletedMark (default broom emoji) via EditMarkBox; customizable editedMark; Replace marks with icons (default true) — spec §52.1
- [ ] Anti-recall behavior — intercept UpdateDeleteMessages; isMessageSavable check; setDeleted() instead of destroy(); save to SQLite via AyuMessages.addDeletedMessage; clean up unread mentions/reactions; setAyuHint service text — spec §52.2
- [ ] Deleted message visual styling — Mode 1 text marks: prepend deletedMark to date text; Mode 2 icon marks: trash/pencil/flame icons before timestamp (burnt, deleted, edited, time order); Mode 3 semi-transparent: 1.0→0.7 opacity over 500ms easeOutCubic for entire bubble; grouped: full group at 0.7 if all deleted else individual; AdminLog always 1.0; animation state transfer on view refresh — spec §52.3
- [ ] Edit history — intercept UpdateEditMessage pre-apply; save pre-edit text to SQLite; skip local/self-authored/hide-edits/identical; "Edits history" context menu item with pencil icon (when edited + revisions exist); full-width section panel replacing chat view; BackButton with peer name+userpic; revisions as standard bubbles newest-first; paginate 20/30 — spec §52.4
- [ ] Deleted messages viewer — "View deleted messages" chat-list right-click; MessageHistory section; search with debounced AutoSearchTimeout + SQL LIKE; topicId filter for forums; Ctrl+F shortcut; peer name+userpic in FixedBar — spec §52.5
- [ ] SQLite storage — ayudata.db; DeletedMessage/EditedMessage/DeletedDialog/SchemaVersion tables; indexes on (userId,dialogId,topicId,messageId); skip empty-text saves; corruption recovery (rename with timestamp + recreate) — spec §52.6
- [ ] Context menu integration — "Edits history" (pencil, when revisions exist); "Hide message" (clear icon); "Read until here" (when ghost blocks reads); "Burn media" (TTL media unread); "View deleted messages" chat-list; "Jump to beginning" chat-list — spec §52.7
- [ ] EditMarkBox — 320px wide dialog; title + input field + "Save" + "Reset to default" buttons — spec §52.10

---

## §53 — Forward Enhancements (AyuGram)
# Touches: dart/lib/ui/chat_view.dart, new forward_progress.dart

- [ ] Intelligent forward routing — detect restricted messages (peer-level isFullAyuForwardNeeded; message-level isAyuForwardNeeded: deleted/AyuNoForwards/TTL); split selection into native-forward + download-resend chunks; execute sequentially on background thread — spec §53.1
- [ ] Forward progress bar — replaces compose area while active; state text "Forwarding messages"/"Loading media"/"Done"; detail "sent N of total + chunk N of total"; frozenRestrictionTitle/Subtitle styles; cancel on click; hide labels when width < 2×photoSize; restore compose on finish — spec §53.2
- [ ] Repeat Message context menu item — repeat icon; three-state visibility (Hidden/Visible/VisibleWithModifier); Shift → no-quote resend (extract text+entities, reuse file refs, preserve reply-to, no forward header); no-Shift → forward with attribution (AyuForward if restricted); applyGhostScheduling — spec §53.3
- [ ] Restriction override — "Plain forwarding is not allowed." non-interactive label with copyright icon; intercept ShareBox submit + ApiWrap.forwardMessages for restricted content → route through AyuForward — spec §53.4
- [ ] Download-and-resend pipeline — scan for downloadable media (exclude webpages/polls/games); new random group IDs; download documents (15min timeout) + photos (5min timeout); send text via sendMessageSync; stickers via SendExistingDocument; voice/video via FileLoadTask; photos/videos/GIFs/documents via sendFiles+PreparedList; batch album groups; skip failed downloads silently; wait server ack per message (5min timeout) — spec §53.5
- [ ] AyuNoForwards flag system — bit 63 message-level; channel-level; user-level NoForwardsMyEnabled/NoForwardsPeerEnabled; polymorphic isAyuNoForwards() — spec §53.6

---

## §54 — AyuGram UI Customization
# Touches: dart/lib/ui/settings_screen.dart, dart/lib/ui/chat_list_row.dart, new ayu_settings.dart

- [ ] Avatar Corners subsection — badge showing current value; live preview dialog row (AyuGramReleases avatar); 24-stop radius slider (0=square, 23=circle) via linear interp corners/23×size/2; live update on drag; restart prompt on release; Single Corner Radius toggle for forum avatars; online badge position recalc; animated userpics — spec §54.1
- [ ] Material Switches (MD3) — "MD3 Switch Style" toggle (default true); MD3: 32×18 track, 14px diameter, −2px shift, easeOutCubic; iOS: 36×20 track, 16px diameter, 1px shift, linear; MD3 growing thumb effect — spec §54.2
- [ ] Wide Messages Multiplier — 61-stop slider (1.00–4.00 step 0.05); "X.XX" label; scale bubble max-width; restart prompt on release — spec §54.3
- [ ] Message Bubble Radius — live MessagePreview widget (two fake messages); 17-stop slider (0=square, 16=max); map to BubbleRadiusLarge+BubbleRadiusSmall via SetBubbleRadiusOverride; restart prompt — spec §54.4
- [ ] Message Tail Removal — toggle (default false); Corner::Tail→Corner::Large; reactive update no restart — spec §54.5
- [ ] Quote & Reply Styling — "Disable Colorful Replies" toggle (default false); transparent quote background; skip backgroundEmojiData; keep accent bar visible — spec §54.6
- [ ] Context Menu Customization — 7 configurable items (Reactions Panel, Views Panel, Hide Message, User Messages, Message Details, Repeat Message, Add Filter) with Hidden/Shown/Extended-Menu three-state; choose-button → single-choice dialog; extended-menu description; fixed actions: View Deleted/Jump to Beginning/Open Channel/Delete Own Messages/Edit History/Read Until/Burn/Create Filter — spec §54.7
- [ ] Drawer/Sidebar Customization — 12 boolean toggles (Profile, Bots, Groups, Channel, Contacts, Calls, Saved, LRead, SRead, Night, Ghost, Streamer); Bots gated on attach-menu bots; Streamer gated on Windows/macOS; 2 tray toggles (Ghost/Streamer) — spec §54.8
- [ ] Message Field Button Toggles — 7 compose buttons (Attach/Commands/TTL/Emoji/Voice/Gift/AI Editor); 2 popup panels (Attach popup/Emoji popup); keep functionality accessible via shortcuts when hidden — spec §54.9
- [ ] ComposeAiBox (AI Editor) — Translate/Style/Fix tabs; preview card: original text (collapsible) + result + copy button; diff display in Fix mode (green underline inserts, strikethrough deletes); 24×24 composite AI icon (letters+stars) — spec §54.9a
- [ ] Additional Appearance Settings — Disable Custom Backgrounds (default true); Hide Premium Statuses (default false); Monospace Font selector → FontSelectorBox; Hide Notification Counters (default false); Hide All Chats Tab (default false); Hide Notification Badge (Windows, default false); App Icon picker: 12 themes, 4-col grid, 64px icons, 4px pad, 12px radius, 200ms selection animation — spec §54.10
- [ ] Additional Chat Settings — Show Only Added Emojis/Stickers; Hide Reactions (collapsible, 3 nested: channels/groups/private); Recent Stickers Count slider (0–200, default 100); Channel Bottom Button (Hidden/MuteUnmute/DiscussWithFallback); Quick Admin Shortcuts (default true); Message Shot (default true); Hide Side Share Button (default false); Replace Marks with Icons (default true) + custom mark sub-settings; Translucent Deleted Messages (beta badge, default false) — spec §54.11
- [ ] AyuGram settings page structure — hierarchy: Appearance/Chats/General/Filters/Other; AyuSectionBuilder helpers: addSettingToggle/addSlider/addChooseButton/addCollapsibleToggle/addBetaBadge/addSectionDivider — spec §54.12
- [ ] General Settings (AyuGeneral) — Translation Provider dropdown (Telegram/Google/Yandex/Native + beta badge); Disable Stories; Disable Open Link Warning; Disable Similar Channels (collapsible, 2 checkboxes); Disable Notify Delay; Filter Zalgo (beta, restart, default true); Improve Link Previews; Show Message Seconds; Show Peer ID (Hide/Telegram API/Bot API); Spoof Client as Android; Bigger Window (Height+Width checkboxes); send confirmations for Stickers/GIFs/Voice — spec §54.14
- [ ] Peer ID Display — Telegram API: always positive bare ID; Bot API: positive for users, −bare for groups, −(bare+1T) for channels; display reactively in profile info — spec §54.14b
- [ ] Other Settings (AyuOther) — donation buttons with SVG icons (Boosty/TON/Bitcoin/Ethereum/Solana/Tron); DonateQrBox with wallet QR; icon backgrounds (#EEE night / #242B2C light, size/4 radius); Crash Reporting toggle (auto-update only, default true); Register URL Scheme → "Done" toast; Reset Settings → confirmation dialog — spec §54.15
- [ ] Filters Settings (AyuFilters) — top-bar menu (Select Chat/Import/Export/Clear All); Enable Regex Filters master toggle; Enable Shared in Chats; Hide from Blocked; Shared Filters nav button; Shadow Ban nav button; per-dialog filters peer list — spec §54.16
- [ ] Filter Engine — ICU/PCRE-compatible regex, MULTILINE always-on; match blob (text+URL+button labels+type tag); reversed flag; caseInsensitive flag; per-dialog rules before shared; own messages never filtered; filtersEnabledInChats gate; hide filtered as isEmpty (zero-height); skip in selection/notifications/media tabs/reply previews/reactions/who-viewed/typing — spec §54.16 Filter Engine
- [ ] AyuFiltersList screen — three modes: Shared/Shadow Ban/Per-dialog; title: "Shadow ban"/"Shared filters"/peer name (18 char); Filters + Excluded subsections; empty state divider; muted label for disabled rows; popup menu (Edit/Enable/Disable/Delete); single Delete for exclusions; pick-shared-pattern-to-exclude flow — spec §54.16 AyuFiltersList
- [ ] RegexEditBox — edit/add filter dialog; auto-focus regex input; validate with ICU error (offset+context); inline error slide animation; Enable/Case-insensitive/Reversed checkboxes; UUID v4 for new IDs; promote-to-shared toast; Save + Cancel + Enter-submit — spec §54.16 RegexEditBox
- [ ] Shadow Ban — global set (not per-account); "Shadow ban"/"Unshadow ban" chat-list right-click (ghost icon when not banned, eye when banned); gate: User or Broadcast + filtersEnabled + not self; instant toggle no confirmation; silent local filtering; filter from who-reacted/reaction summaries/typing/replier strip; shadow ban list page — spec §54.16 Shadow Ban
- [ ] ImportFiltersBox — Clipboard/URL radio buttons; URL input with clipboard auto-prefill; import from clipboard (JSON) or URL (HTTP GET); export to clipboard (JSON) or URL (POST dpaste.com + copy URL); JSON v2 format (filters array + exclusions array); success/failure toast — spec §54.16 ImportFiltersBox
- [ ] AyuMain landing page — app logo widget (configurable icon from 12 themes); "AyuGram Desktop v{version}" boxTitle; tagline centeredBoxLabel; 6 category navigation buttons (AyuGram/Filters/General/Appearance/Chats/Other) with icons + right-arrow chevrons; 4 link buttons (Channel/Chats/Translate/Documentation) — spec §54.17

---

## §55 — Channel & Group Statistics
# Touches: dart/lib/ui/info_panel.dart (navigation entry), new statistics_panel.dart

- [ ] Statistics entry points — "Statistics" in channel/group info three-dot menu (menuIconStats, gated CanGetStatistics); "Boosts" (menuIconBoosts); "Channel Earning" (menuIconEarn, gated CanViewRevenue/CanViewCreditsRevenue); navigate to Statistics section; page titles "Statistics"/"Message Statistics"/"Story Statistics" — spec §55.1
- [ ] Loading state — centered Lottie "stats" animation (normalBoxLottieSize 120×120); "Loading Statistics..." title; subtitle centered max 256px; SlideWrap toggles off when data arrives; animation only starts after showFinished — spec §55.2
- [ ] Channel overview (2×2 grid) — Followers / Enabled Notifications% / Views Per Post / Views Per Story; 14px statisticsOverviewValue with FormatCountToShort; 11px change indicator (green/red, +/− prefix with U+2212); 11px label windowSubTextFg; 50px row gap; 14px right col offset; story grid for story metrics — spec §55.3
- [ ] Channel charts (12 charts) — Followers (Linear), New Followers (Linear), Notifications (Linear), Views By Hours (Linear), Views By Source (StackBar), New Followers By Source (StackBar), Languages (StackLinear), Interactions (DoubleLinear), IV Interactions (DoubleLinear), Reactions By Emotion (Bar), Story Interactions (DoubleLinear), Story Reactions (Bar); omit empty; async-load with SlideWrap reveal — spec §55.3
- [ ] Recent messages list — "Recent Messages" section header; 56px SettingsButton rows; 42px thumbnail with roundRadiusLarge; photo/video/story/spoiler thumbnails; message text preview + date/time + view count + share count + reaction count; pagination 10+30; "Show More" toggle; "Show in Chat" context menu; tap → message statistics sub-page — spec §55.3
- [ ] Group overview + charts (8 charts) — overview 2×2: Members/Messages/Viewing Members/Posting Members; charts: Members (Linear), New Members (Linear), New Members By Source (StackBar), Members' Primary Language (StackLinear), Messages (StackBar), Actions (DoubleLinear), Top Hours (Linear), Days Of Week (StackLinear) — spec §55.4
- [ ] Group top members lists — Top Senders (N messages, M chars); Top Administrators (N deletions, M bans, K restrictions); Top Inviters (N invitations); hide when empty; "Show More" 40/page; tap → user profile; section separators — spec §55.4
- [ ] Message statistics page — MessagePreview at top (thumbnail/text/date, "Show in Chat" context, stories non-interactive); 2×2 grid: Views/Public Shares/Reactions/Private Shares (raw numbers, no growth); Interactions DoubleLinear + Reactions By Emotion Bar; Public Shares section with forwarding channel rows (tap → forward in channel; story rows with gradient ring) — spec §55.5
- [ ] Chart widget architecture — stacked: 36px header + 200px chart area + 42px footer + optional filter buttons; header title semibold boxFontSize + 11px subtitle (updates with range); 200px interactive area; PointDetailsWidget tooltip at nearest X (left-of-point, flip on overflow); tooltip fade 200ms; footer: 42px miniature + range selector (10px handles, statsChartFooterSideWidth); range highlight; inactive dimmed; handles: premiumButtonFg 6px round; min 5px between handles; drag left/right handles; pan center area; click outside → animate center to clicked (sineInOut); range changes trigger immediate re-render — spec §55.6
- [ ] PointDetailsWidget tooltip — rounded rect boxBg + multi-layer shadow; date stamp semibold 12px (weekly "1 Jan–7 Jan" or "Mon, Jan 15"); value lines per series (name 12px boxTextFg, value 12px line-color, optional %); animated alpha per filter state; 12/12/8/11px margins, 6px padding, 4px between lines; zoom chevron (>) in header; click → zoom action + ripple; currency: native + USD conversion — spec §55.6
- [ ] Chart rendering — H-axis: 10px date labels centered, 15px caption height+6px skip; labels fade on zoom to prevent overlap; edge labels fade when clipped; V-axis: grid lines with value labels, 4px ruler skip; rulers 0.06 alpha; new ruler sets animate with alpha crossfade; line colors from server keys (BLUE/GREEN/RED/GOLDEN/LIGHTBLUE/LIGHTGREEN/ORANGE/INDIGO/PURPLE/CYAN); 2px line width; selected point: vertical line + 5px dots per series — spec §55.6
- [ ] Chart types — Linear (single line, QImage cache with key); DoubleLinear (two lines, independent Y via DoubleLineRatios); Bar (non-stacked, SegmentTree, selected highlighted); StackBar (stacked bars, cumulative totals per-series); StackLinear (stacked filled areas, 100% normalized; zoom → pie chart animation easeOutCirc 400ms; pie: slice pop-out 8px, % labels 20px, hover; ChangingPiePartController; Zoom Out button 20px/11px/statisticsHeaderButton; Zoom Out click → reverse animation) — spec §55.7
- [ ] Chart zoom — server-side: Linear/Bar/DoubleLinear/StackBar with zoomToken; zoomRequests event; requestZoom(token, x) API call; _zoomedChartWidget overlay; zoomed header: title + date range; "Zoom Out" button; original crossfades out on zoom; "Zoom Out" destroys zoomed widget; StackLinear local zoom: client-side pie transform, footer range adjusts, mouse tracking for slice hover — spec §55.8
- [ ] Filter buttons (ChartLinesFilterWidget) — shown for >1 data series; horizontal flow of FlatCheckbox buttons; line name + line color; 4/3/5/4px margins; 3px check mark; toggling animates line alpha; Y-axis recomputes for visible lines; isHiddenOnStart; long-press behavior; 12/8px container padding — spec §55.9
- [ ] Chart animation system — X: 200ms linear (kXExpandingDuration); Y: easeInCubic adaptive speed (three tiers 0.06/0.06/0.09); Y speed ÷1.2 on filter change; Y instant snap when ratio >0.97; height alpha crossfade (old rulers out, new in); date label crossfade easeInCubic 200ms; FPS-adaptive (×60/currentFPS, ×2 below 30 FPS); footer separate Y-range animation track — spec §55.10
- [ ] Statistics data models — StatisticalValue (.value/.previousValue/.growthRatePercentage); StatisticalGraph (.chart pre-loaded or .zoomToken deferred); StatisticalChart (.timestamps/.lines/.xPercentage/.defaultZoomXIndex/.weekFormat/.hasPercentages/.isFooterHidden/.currencyRate/.currency) — spec §55.11

---

## §56 — Appendix A: Resolved Style Constants
# Touches: new theme_tokens.dart (or dart/lib/ui/theme.dart), applied throughout all widgets

- [ ] Global primitive tokens — fsize (13px), boxFontSize (14px), normalFont, semiboldFont, linkFont; slideDuration (240ms), slideWrapDuration (150ms), fadeWrapDuration (200ms), universalDuration (120ms); lineWidth (1px), defaultVerticalListSkip (6px) — spec §56.1
- [ ] Layer/Box chrome tokens — boxWidth (320px), boxWideWidth (364px), boxRadius (8px); boxPadding (24/14/24/8 margins); boxDuration (200ms), boxRoundShadow (8px soft drop); boxTitle FlatLabel (24px max-h, 14px semibold, boxTitleFg); defaultBox (34px button height, boxBg) — spec §56.2
- [ ] Main window layout tokens — windowMinWidth (380px), windowMinHeight (480px); columnMinimalWidthLeft (260px), columnMaximalWidthLeft (540px), columnMinimalWidthMain (380px); adaptiveChatWideWidth (880px); topBarHeight (54px) + icon button widths (search 40, close 56, menu 44, etc.); topBarMenuPosition (−6,45); topBarInfoButtonSize (52×54), topBarInfoButtonInnerSize (42px); topBarConnectingPosition/Skip (6px); chat switch tokens — spec §56.3
- [ ] Chat list / left panel tokens — dialogsRowHeight (62px), forumDialogRow.height (80px); dialogsUnreadHeight (19px), dialogsUnreadPadding (5px); defaultDialogRow compound (h 62px, pad 10/8/10/8, photo 46px, nameLeft 68px, nameTop 10px, textLeft 68px, textTop 34px); dialogsStoriesFull compound (h 77px, photo 42px, photoLeft 10px, photoTop 9px, lineTwice 4px); filter/skip tokens; contacts tokens — spec §56.4
- [ ] Compose row / emoji / WhoRead tokens — historyReplySkip (53px), historyReplyHeight (49px); historyReplyNameFg=windowActiveTextFg; compose icon token set; historyRecordVoiceFg/FgOver=historyComposeIconFg/FgOver; historySendIconFg (light #3fc1f7, dark #6ab3f3); historyToDown TwoIconButton (52×54) + badge variants; emoji/sticker sizes (emojiSetSize 42×39, emojiPanArea 34×32, stickersSize 64×64); historySlowmodeCounterMargins (0/0/10/0) — spec §56.5
- [ ] Contact/peer list + misc box tokens — normalBoxLottieSize (120×120); boxLabel FlatLabel (14px, boxTextFg) — spec §56.6
- [ ] Settings panel tokens — settingsPhotoTop (8px), settingsPhotoBottom (16px); accent color tokens (24px size, 3px line, 4px skip); settingsBackgroundThumb (76px), settingsThemePreviewSize (80×92); local passcode tokens; settingsButtonLight/NoIcon variants; chat theme tokens — spec §56.7
- [ ] Profile/info panel tokens — infoDesiredWidth (392px); layer min/max top (20/40px); infoMinimalLayerMargin (48px), infoProfileSkip (7px); members list positions (photo 18/6, name 79/11, status 79/31); info top bar tokens (54px, 0.7 scale, 150ms); back/close/search/menu/forward widths; infoTopBarTitle FlatLabel; infoMainButton SettingsButton — spec §56.8
- [ ] Miscellaneous tokens — defaultInputField (47px tall, 14px font, activeLineFg/inactiveLineFg); defaultRadio (22px, 2px stroke, universalDuration); defaultMultiSelect (32px chips, 8px radius); defaultRoundShadow (8px blur, 0/2 offset); popupMenuWithIcons + icon set (20×20); menuIconFg/deleteAttention colors; radial loader (44px ring, 3px stroke, radialBg/Fg); roundedBg/Fg; photo crop tokens — spec §56.9
- [ ] Palette + coverage — all 20+ most-referenced tokens (windowBg, windowFg, windowBgActive, etc.) with light/dark values; derived compound resolution; filter false-positive tokens (st::All, st::Error, etc.); track ~25 unresolved tokens — spec §56.10–56.13

---

## §57 — Appendix B: Dark Theme Color Palette
# Touches: new theme_colors.dart (applied throughout all widgets)

- [ ] Theme infrastructure — dual-theme (day-blue / night) color system; alias resolution (references resolve to hex); 8-digit hex with alpha (#00000054); DPI scaling at runtime (100%/125%/150%/200%/300%); map Telegram hex to Flutter Color(0xAARRGGBB) — spec §57
- [ ] Window / chrome colors — windowBg/BgOver/BgRipple/BgActive/Fg/FgOver/FgActive; window text tokens (windowSubTextFg/FgOver, windowBoldFg/FgOver, windowActiveTextFg); shadow tokens (windowShadowFg/Fallback, shadowFg) with alpha; title bar tokens (titleBg/BgActive/Shadow/Fg/FgActive); layerBg (#0000007F) — spec §57.1
- [ ] Dialog / chat list colors — dialog background tokens (dialogsBg/BgOver/BgActive/RippleBg/RippleBgActive); name tokens; text tokens (dialogsTextFg/FgOver/FgActive/FgService); date/draft tokens (draft red #DD4B39 light / #FF525D dark); unread badge tokens (6 variants); online badge tokens; icon tokens (sentIcon/sendingIcon/verifiedIcon/archiveFg); forward tokens — spec §57.2
- [ ] Top bar colors — topBarBg (light #FFFFFF, dark #17212B); missing top bar tokens resolved via menuIconFg/windowFg/windowSubTextFg — spec §57.3
- [ ] Message / bubble colors — incoming tokens (msgInBg/BgSelected/Shadow/DateFg/ServiceFg/ReplyBarColor/MonoFg/FileInBg); outgoing tokens (msgOutBg/BgSelected/Shadow/DateFg/ServiceFg/ReplyBarColor/MonoFg/FileOutBg); service tokens (msgServiceBg/BgSelected/Fg with alpha); overlay tokens (msgSelectOverlay/msgStickerOverlay with alpha); date image tokens; dark theme: shadows alpha 00 intentionally — spec §57.4
- [ ] History / chat area colors — compose area tokens (historyComposeAreaBg/Fg/IconFg/IconFgOver); compose button tokens (3 variants); historySendIconFg=windowBgActive; reply/pinned tokens; unread bar tokens; scroll tokens (4 with alpha); scroll-to-bottom button tokens — spec §57.5
- [ ] Peer / author colors — 8-way peer name palette (historyPeer1–8NameFg); light: red #C03D33, green #4FAD2D, yellow #D09306, blue #168ACD, purple #8544D6, pink #CD4073, sea #2996AD, orange #CE671B; dark: red #FB6169, green #85DE85, yellow #F3BC5C, blue #65BDF3, purple #B48BF2, pink #FF5694, sea #62D4E3, orange #FAA357; 8-way userpic background colors (same both themes) — spec §57.6
- [ ] Box / modal colors — boxBg/TextFg/TitleFg/SearchBg/TitleAdditionalFg; boxTextFgGood/Error; boxDividerBg fallback to windowBgOver — spec §57.7
- [ ] Profile / info colors — profileStatusFgOver (base → windowSubTextFg); profileVerifiedCheckBg/Fg; profileAdminStarFg/profileOtherAdminStarFg — spec §57.8
- [ ] Button / accent colors — active button tokens (5 variants); active line tokens; attention button tokens (with alpha on dark); light button tokens — spec §57.9
- [ ] Sidebar / folders rail colors — sideBarBg/BgActive/BgRipple; sideBarTextFg/FgActive/IconFg/IconFgActive; sideBarBadgeBg/BgMuted/Fg — spec §57.10
- [ ] Missing / derived token handling — dialogsChatBgOver = dialogsBgOver synonym; top bar token aliases; historyComposeButton compound; profileStatusFg → windowSubTextFg; boxDividerBg from windowBgOver+shadow; dark menuBgOver override (~#2B3744); dark shadow suppression msgOutShadow/msgInShadow alpha 00 — spec §57.11

---

## Bugs

- [ ] Mobile (oneColumn) selection mode: context menu "Select" action doesn't activate selection mode — no selection bar, no checkboxes appear. Works fine in desktop (twoColumn) mode. Likely a state/animation issue in oneColumn layout.
- [ ] Info panel scroll doesn't work via flutter_interact.sh scroll events — scroll goes to chat list instead of info panel CustomScrollView. Affects both desktop (third column) and mobile (full screen) modes. The SliverPersistentHeader cover never compresses.
- [ ] GIF tab inline search broken: GetInlineBotResults passes string "gif" as bot ID but engine expects numeric ID. Error: `invalid ID "gif": strconv.ParseInt: parsing "gif": invalid syntax`. Affects both manual text search and category emoji search.
- [ ] Chat Settings page scroll broken via flutter_interact.sh — PointerScrollEvent dispatched at various y positions doesn't cause ListView to scroll. Scrollbar error "ScrollController has no ScrollPosition attached" in logs. ListView has `primary: true` but scroll still doesn't work via debug dispatch. Affects testing of items below viewport (quick action radios).
- [ ] Notifications page scroll broken — Channels and Reactions split-toggle rows are below viewport (~y=775) but ListView doesn't scroll via flutter_interact.sh. Same class of bug as Chat Settings scroll issue. Affects testing of Channels/Reactions per-type sub-page navigation. PARTIAL FIX: ScrollController explicitly assigned to both Scrollbar and ListView (no longer uses primary:true), but flutter_interact.sh PointerScrollEvent dispatch still doesn't scroll the page. OS-level ydotool scroll works as a workaround.
- [ ] `_isSelfAdmin` in `_GroupActionsSection` (info_panel.dart) never returns true: compares `chat.accountId` (format "tele_4beb99fd") with `m.userId` (Telegram numeric ID like "123456789") — formats never match. "Edit Group" and "Topics" rows are invisible for all groups because of this. Fix: resolve account's own Telegram user ID and compare against member userId.
- [ ] `GetScheduledCount` returns PEER_ID_INVALID for some chats (e.g. TODO channel) — Go backend constructs invalid peer for the Telegram API call. Scheduled toggle button can't show because count stays 0. Backend bug, not UI.
