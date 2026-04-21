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
- [ ] DialogsColumn collapsed/avatar-only mode renders 72px of avatars, not full rows — spec §1 (currently collapses to 72px but ChatListPanel `collapsed:true` passes flag through; verify narrow avatar rendering works correctly in `chat_list_row.dart`)
- [ ] Third column shadow `_thirdShadow` hidden when third column closes (currently always rendered when `_infoOpen`, but shadow should disappear on collapse animation end) — spec §1
- [ ] Third column resize handle (chat→info separator) — spec §1 (partially done: resize handle exists but is placed before info panel; should be between chat and info columns)

### §1.5 Linux Titlebar
<!-- spec: research/telegram_desktop_ui.md §1 Linux Titlebar -->

- [x] Custom client-side titlebar by default (28px height, 46px button width) — DONE in `titlebar.dart`
- [x] Button layout read from DE at runtime: X11 XSettings `Gtk/DecorationLayout`, fallback to `right:[min,max,close]` — DONE in `titlebar.dart` `_ButtonLayout.parse()`
- [x] Unknown tokens (appmenu, icon, spacer, menu) silently ignored — DONE in `titlebar.dart`
- [x] Minimize/Maximize/Close buttons with hover: close=red `#e81123`, others `windowBgOver` — DONE in `titlebar.dart`
- [x] Double-click title area → toggle maximize; drag area → `startDrag` window move — DONE in `titlebar.dart`
- [x] `maximizeChanged` + `buttonLayoutChanged` native callbacks update state live — DONE in `titlebar.dart`
- [ ] Wayland: fall back to XDG portal `org.gnome.desktop.wm.preferences::button-layout` when XSettings unavailable — spec §1 (not implemented; currently only queries via MethodChannel `getButtonLayout`, backend needs to implement the XDG portal path)
- [ ] `NativeTitleRequiresShadow()` — 1px shadow under native frame when enabled — spec §1 (not confirmed, low priority)
- [ ] Native window frame toggle (`Settings → Advanced → Use system window frame`) — spec §1 (toggle exists in settings_screen.dart but integration with `my_application.cc` / `setNativeFrame()` unverified)

### §1.6 Animations
<!-- spec: research/telegram_desktop_ui.md §1 Animations -->

- [x] Column width changes: `easeOutCirc` 150-200ms — DONE (180ms in `shell.dart`)
- [x] OneColumn section transitions: horizontal slide + crossfade — DONE in `shell.dart`
- [ ] Menu expand/collapse `slideWrapDuration` — spec §1 (account switcher uses `AnimatedSize` 150ms `easeOutCirc` which is close but not the library `slideWrapDuration` default)

---

## §2 — Chat List Sidebar
<!-- spec: research/telegram_desktop_ui.md §2 -->

### §2.1 Folder Tabs (Vertical Sidebar)
<!-- spec: research/telegram_desktop_ui.md §2 Folder Tabs -->

- [x] Vertical sidebar `FilterColumn` 72px wide, hamburger at top, "All Chats" default, "Edit" at bottom — DONE in `filter_column.dart`
- [x] Folder tabs scrollable, drag-reorderable via raw pointer events (10px threshold) — DONE in `filter_column.dart`
- [x] Unread badges per tab: unmuted blue `#40a7e3`, muted gray `#bbbbbb` day / `#3e546a` night — DONE in `filter_column.dart`
- [x] Active tab highlighted with accent background — DONE in `filter_column.dart`
- [ ] Vertical sidebar: `SideBarButton` exact 72px icon + folder name layout (currently uses 56px Container with icon+text column; spec requires specific icon size, name truncation, and active-tab highlight matching Telegram's exact sidebar button style) — spec §2.1
- [ ] `SideBarButton` active tab: no rounded background highlight; instead a colored dot or underline (check AyuGram source `sidebar_button.cpp` — current impl uses `BorderRadius.circular(12)` bg which may be incorrect) — spec §2.1

### §2.1 Folder Tabs (Horizontal Strip)
<!-- spec: research/telegram_desktop_ui.md §2 Folder Tabs -->

- [x] Horizontal `_HorizontalFolderTabs` strip shown when vertical sidebar off and folders exist — DONE in `chat_list_panel.dart`
- [ ] Horizontal tabs: `SettingsSlider` style — strip height 33px, horizontal padding 9px, inter-label min gap 18px, labels 14px semibold — spec §2.1 (current impl uses custom widget; needs exact `chatsFiltersTabs` metrics)
- [ ] Active tab: sliding underline indicator 6px stroke, radius 2px, at `barTop: 30px`, color `lightButtonFg` (blue); NO pill fill — spec §2.1
- [ ] Inactive fg = `windowSubTextFg`, active fg = `lightButtonFg`; hover ripple = `windowBgOver`; active ripple = `lightButtonBgOver` — spec §2.1
- [ ] Horizontal mouse-wheel scrolling redirected to tab strip — spec §2.1
- [ ] Right-click context menu on tab: Edit, Remove, Setup — spec §2.1
- [ ] `rippleBottomSkip: 0px` — spec §2.1

### §2.2 Search Bar
<!-- spec: research/telegram_desktop_ui.md §2 Search Bar -->

- [x] Search bar at top, placeholder "Search", padding 7px each side — DONE in `chat_list_panel.dart` `_SearchBar`
- [x] Focused: Top Peers strip (horizontal, 46px avatars) + Recent Contacts below — DONE in `chat_list_panel.dart`
- [x] Typing: search results in three tabs (My Messages, Public Posts, This Peer) — DONE in `chat_list_panel.dart` `_SearchTabsStrip`
- [x] Cancel button appears when searching — DONE in `chat_list_panel.dart`
- [ ] Search tabs: `dialogsSearchTabs` `SettingsSlider` — 33px strip, 9px padding, 18px `strictSkip`, 14px semibold labels, underline indicator (same as folder tabs) — spec §2.2 (current impl uses custom `_SearchTabsStrip`; needs exact metrics)
- [ ] Sub-filters under My Messages (Private/Groups/Channels): `ChatSearchIn` popup from 38px-tall row (`dialogsSearchInHeight`), photo 28px, left padding 10px, name top 9px, dropdown arrow top 15px — spec §2.2 (current impl uses `_SearchSubFilterRow` inline row; needs to match the popup-from-row design)
- [ ] Divider bar 28px (`searchedBarHeight`), normalFont, left padding 14px — spec §2.2
- [ ] Empty results: Lottie animation 100px + descriptive text — spec §2.2 (currently shows `_EmptyState` text only)

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
- [ ] Unread counter pill: 19px height, 5px horizontal padding, min-width = 19px (perfect circle for single digit), fully-round ends (radius = height/2), 12px bold font — spec §2.3 (current impl uses `BorderRadius.circular(9)` which is correct, but need to verify min-width = 19px enforced for single-digit counts)
- [ ] Unread badge colors: unmuted = `dialogsUnreadBg` `#40a7e3` day / accent blue night; muted = `#bbbbbb` day / `#3e546a` night; `*Over` and `*Active` variants — spec §2.3 (partially done; active-row badge color variants not implemented)
- [ ] `..N` truncation when count exceeds `allowDigits + 1` — spec §2.3
- [ ] Unread dot (unread mark, no counter): filled ellipse `unreadMarkDiameter` centered in 19×19 slot — spec §2.3
- [ ] Mention/reaction/poll badges: 18×18 `ThreeStateIcon` glyph (NOT pill), icon color = `dialogsUnreadBg` unmuted / muted — spec §2.3
- [ ] Narrow sidebar: mention/reaction/poll use 13×13 glyph inside 19×19 unread-bg circle — spec §2.3
- [ ] Stories ring: full mode — photo 42px, unread line 2px, read line 1px; small mode — 21px photo, 1.5px unread, no read line — spec §2.3
- [ ] Stories ring unread gradient: `groupCallLive1` (#0dcc39) → `groupCallMuted1` (#0992ef), topRight→bottomLeft — spec §2.3
- [ ] Stories ring read: solid `dialogsUnreadBgMuted` at 0.6 opacity — spec §2.3
- [ ] Live-stream ring: solid `attentionButtonFg` red instead of gradient — spec §2.3
- [ ] Chat-type icon before name (bot/channel/forum/group, 3px skip) — spec §2.3
- [ ] Mute icon after name (4px skip) — spec §2.3
- [ ] Verified/scam badges after name — spec §2.3
- [ ] Timestamp formats: "12:30" (today), "Yesterday", "Mon" (this week), "Jan 15" (older) — spec §2.3 (partially done; verify all cases)
- [ ] Mini media previews: 16px thumbnails in preview line — spec §2.3
- [ ] Pin icon: right side at textTop when no unreads — spec §2.3
- [ ] Send state icons: clock/single-check/double-check at 20px skip — spec §2.3

### §2.4 Chat Item States
<!-- spec: research/telegram_desktop_ui.md §2 Chat Item States -->

- [x] Day: default `#ffffff`, hover `#f1f1f1`, active `#419fd9` (text white) — DONE in `chat_list_row.dart`
- [x] Night: hover `#202b36`, active `#2b5278` — DONE in `chat_list_row.dart`
- [ ] Ripple: day normal `#e5e5e5`, day active-row `#2095d0`; night normal `#25313d`, night active-row `#315a80` — spec §2.4 (current impl uses `hoverColor` but not distinct ripple colors from spec)
- [ ] `defaultRippleAnimation` curve — no custom opacity (spec §2.4)
- [ ] Night unread-on-active-row: `dialogsUnreadBgActive` = white; muted-on-active = `#7aa3ca`; on-hover = `#4082bc`; muted-on-hover = `#4d5762` — spec §2.4 (not implemented; badges always use base palette)

### §2.5 Special Rows
<!-- spec: research/telegram_desktop_ui.md §2 Special Rows -->

- [x] Archived Chats row exists (collapsed row above chat list) — DONE in `chat_list_panel.dart` `_ArchivedChatsRow`
- [ ] Archive row: fixed height 37px (`dialogsImportantBarHeight`), NOT 62px — spec §2.5 (needs verification; `_ArchivedChatsRow` height may not be exactly 37px)
- [ ] Wide sidebar archive row: text label at 18px left padding, 14px semibold `semiboldFont`, `dialogsNameFg` color — spec §2.5
- [ ] Narrow sidebar archive row: stacked-userpic composite centered at 19px width, no text — spec §2.5
- [ ] Archive unread badge: ALWAYS muted/gray regardless of actual mute state — spec §2.5
- [ ] Archive expand/collapse: `Ui::Animations::Simple` ~200ms (`universalDuration`) — spec §2.5 (currently uses `AnimationController` 200ms; should be close)
- [ ] Saved Messages row: bookmark-icon userpic (no avatar photo) — spec §2.5

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
- [ ] Swipe action: Lottie icon (`swipe_{mute,unmute,...}`) at `dialogsQuickActionSize = 20px`; ripple area `dialogsQuickActionRippleSize = 80px` — spec §2.7 (currently uses static icons; Lottie swipe icons not implemented)
- [ ] Swipe label: 13px semibold, auto-shrinks to 5px minimum, `twoLines=true` — spec §2.7
- [ ] Swipe `kSwipeSlow = 0.2` slowdown + spring-back after release (`Ui::Animations` ~200ms) — spec §2.7 (rubber-band feel not verified)
- [ ] Haptic feedback on swipe threshold crossing — spec §2.7 (Linux likely no-op, but hook should exist)

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
- [ ] Emoji-status prompt as clickable link (currently plain text "Set Emoji Status"; should be link-styled to open emoji status picker) — spec §3.1
- [ ] AyuGram/Extera badge after verified badge, offset by `infoVerifiedCheckPosition.x()` — spec §3.1 (low priority)

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
- [ ] Scroll area `defaultSolidScroll` — visible scrollbar thumb, no autohide — spec §3.2 (currently uses `Scrollbar(thumbVisibility: true)` which should be correct; verify thumb is always visible not just on hover)
- [ ] "New Window" option in inactive account context menu — spec §3.2 (currently only Activate/CopyPhone/MarkRead/LogOut; New Window missing)
- [ ] Log-out confirmation dialog matches spec style (currently uses `AlertDialog` which is close) — spec §3.2

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
- [ ] My Profile → opens profile page (currently just closes drawer; profile page not built) — spec §3.3
- [ ] New Group → opens group creation flow (§21) — spec §3.3
- [ ] New Channel → opens channel creation flow — spec §3.3
- [x] Contacts → opens contacts screen — spec §3.3 — DONE
- [ ] Calls → opens calls screen — spec §3.3
- [ ] No divider between individual non-Profile rows (flush list) — spec §3.3 (currently no dividers between rows, correct)

### §3.4 Night Mode Toggle
<!-- spec: research/telegram_desktop_ui.md §3 Night Mode Toggle -->

- [x] Night mode row with inline trailing toggle — DONE in `hamburger_drawer.dart`
- [x] Toggle "on" color = `mainMenuCoverBg` (accent blue), "off" = `windowSubTextFg` — DONE in `_InlineToggle`
- [x] Toggle animates 150ms — DONE
- [x] Row tap toggles theme — DONE
- [ ] System dark mode detection: if `systemDarkModeEnabled`, toggle state reflects system value live — spec §3.4 (not implemented; theme is only set manually)
- [ ] Theme cross-fade full-window palette animation on toggle — spec §3.4 (currently just rebuilds with new theme; no crossfade animation)
- [ ] Confirmation dialog when theme editor is active ("can't change theme while editing") — spec §3.4 (low priority)

### §3.6 Footer
<!-- spec: research/telegram_desktop_ui.md §3 Footer -->

- [x] Footer `ConstrainedBox(minHeight: 80)` — DONE in `hamburger_drawer.dart` `_FooterSection`
- [x] Two lines left-aligned at 25px, both `windowSubTextFg` — DONE
- [x] Top line: "UniClient" product name link (semibold 13px) — DONE
- [x] Bottom line: "Version X – About" (regular 13px), two link regions — DONE
- [x] Version tooltip "Build date: {date}" — DONE
- [x] "About" link opens AboutBox dialog — DONE
- [ ] Version link opens changelog/releases URL — DONE (already opens GitHub releases)
- [ ] Build-time `__DATE__` value injected at compile time — spec §3.6 (currently hardcoded "2026-04-20"; should be set from build system)
- [ ] Version string: append " alpha N" / " beta" / " DEBUG" modifiers as appropriate — spec §3.6 (currently hardcoded "Version 0.1.0 alpha")

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
- [ ] Back button: exact `historyTopBarBack` style — 60px width; `_leftTaken` = 60px when shown, 17px without — spec §4.2 (current uses `IconButton` which is ~48px; needs exact 60px width)
- [ ] Back button right-click: call-type menu — spec §4.2
- [ ] Avatar: `UserpicButton` 52×54px hit-area, 42px photo diameter, offset (2, -1) — spec §4.2 (current uses 36px radius circle; needs exact spec dimensions)
- [ ] Avatar horizontal origin = `_leftTaken` (60px with back, 17px without) — spec §4.2
- [ ] Verified/scam/fake badge inline after title — spec §4.2 (currently shows mute icon but not verified/scam badges)
- [ ] Subtitle font: `dialogsTextFont` — spec §4.2
- [ ] DM subtitle: "online" green `#3BA55C` (done) + "last seen [time]" formatted per §1.4 — spec §4.2 (online done; last-seen format needs verification across all `kind` variants)
- [ ] Group subtitle: "X members, Y online" — spec §4.2 (currently shows "X members" only; "Y online" missing)
- [ ] Channel subtitle: "X subscribers" — spec §4.2 (shows member count but label doesn't say "subscribers")
- [ ] Typing indicator: animated dots replacing subtitle — spec §4.2 (currently shows static text "X is typing..."; needs animated dots)

### §4.3 Right-Side Buttons
<!-- spec: research/telegram_desktop_ui.md §4 Right-Side Buttons -->

- [x] Info toggle button (info_outline icon) — DONE in `_ChatTopBar`
- [x] Menu toggle (more_vert) — DONE in `_ChatTopBar`
- [x] Menu opens: Mute/Unmute, Mark Read/Unread, Pin, Archive, Leave — DONE in `_ChatTopBar._showTopBarMenu()`
- [ ] Shared button chrome: 40px width, 54px height, 40px circular ripple at `(0,7)`, icon 20px — spec §4.3 (current uses `IconButton` default sizing; needs exact spec dimensions)
- [ ] Menu toggle: 44px width override, icon at `(16, 17)` — spec §4.3
- [ ] Menu toggle additional items: New Window, View Profile, Clear History, Delete Chat — spec §4.3
- [ ] Info toggle: active color `windowActiveTextFg` (blue) when info panel open — spec §4.3 (currently no active state on icon)
- [ ] Info toggle hidden in single-column — spec §4.3 (currently always shown)
- [ ] Call button: `top_bar_call` icon, 1:1 DMs only — spec §4.3 (not implemented)
- [ ] Call button right-click: audio/video call submenu — spec §4.3
- [ ] Group call button: `top_bar_group_call` icon for groups/channels — spec §4.3 (not implemented)
- [ ] Search button: `top_bar_search` icon, toggles inline search — spec §4.3 (not implemented)
- [ ] Inline search: text field replaces title, date/user filters — spec §4.3
- [ ] Buttons flush (0-gap); `topBarSkip: -5px` pulls menu toggle tighter — spec §4.3
- [ ] Disabled state: grayscale icon at 40% alpha, ripple disabled — spec §4.3
- [ ] Icon colors: `menuIconFg` normal, `menuIconFgOver` hover — spec §4.3

### §4.4 Pinned Message Bar
<!-- spec: research/telegram_desktop_ui.md §4 Pinned Message Bar -->

- [x] Pinned message bar shows below top bar — DONE in `chat_view.dart` `_PinnedBar`
- [x] Title "Pinned Message", blue accent color — DONE
- [x] Preview text, 1 line elided — DONE
- [x] Tapping bar jumps to pinned message — DONE
- [ ] Bar height: exactly 49px (`historyReplyHeight`) — spec §4.4 (currently 44px; needs to be 49px)
- [ ] Thumbnail: 32×32px centered vertically, ~3px corner radius — spec §4.4 (currently no thumbnail)
- [ ] Title text logic: "Pinned Message" (single), "Previous Pinned Message" (count==2), "Pinned Message #N" — spec §4.4 (currently always "Pinned Message")
- [ ] Close/unpin button: 49×49 hit-area, 40px ripple at (4,4), `box_button_close` icon — spec §4.4 (no close button currently)
- [ ] Close button colors: `historyReplyCancelFg` / `historyReplyCancelFgOver` — spec §4.4
- [ ] Multi-pin "Show All" button: same size, `pinned_show_all` icon — spec §4.4
- [ ] Background: `historyPinnedBg` — day `#ffffff`, night `#1b2734` — spec §4.4 (currently uses `colorScheme.surface`)
- [ ] Left accent stripe: 2px wide, 36px tall, `msgInReplyBarColor`, offset `(1,0)`, 10px skip — spec §4.4 (currently uses generic left bar at different dimensions)
- [ ] Content change animation: 160ms — spec §4.4

### §4.5 Contact Status / Action Bar
<!-- spec: research/telegram_desktop_ui.md §4 Contact Status / Action Bar -->

- [ ] Action bar for unknown/blocked contacts: full-width flat buttons below top bar — spec §4.5 (not implemented)
- [ ] Base button: 49px height, `textTop: 16px`, semibold, `windowActiveTextFg` blue, hover `historyComposeButtonBg` — spec §4.5
- [ ] Destructive variant (Block, Report Spam): `attentionButtonFg` red — spec §4.5
- [ ] Unblock button: 46px height, `textTop: 14px`, `attentionButtonFg` — spec §4.5
- [ ] Status label (bot info): `FlatLabel` `minWidth: 240px` — spec §4.5
- [ ] Inter-button gap: minimum 16px — spec §4.5
- [ ] No icons next to labels — spec §4.5

### §4.6 Group Call Bar
<!-- spec: research/telegram_desktop_ui.md §4 Group Call Bar -->

- [ ] Active group call bar with overlapping participant userpics — spec §4.6 (not implemented)
- [ ] Green speaking-indicator rings on userpics — spec §4.6
- [ ] "Join" button — spec §4.6

### §4.7 Selection Mode
<!-- spec: research/telegram_desktop_ui.md §4 Selection Mode -->

- [x] Selection bar replaces top bar when messages selected — DONE in `chat_view.dart` `_SelectionBar`
- [x] Forward, Copy, Delete buttons — DONE in `_SelectionBar`
- [x] Cancel/close button — DONE
- [x] Count display ("X selected") — DONE
- [x] Forward drag-and-drop integration — DONE in `_SelectionBar`
- [ ] Selection controls slide in from below at `topBarHeight`; title/subtitle translate up — spec §4.7 (current replaces bar instantly; needs `_selectedShown.start()` slide animation 200ms `easeOutCirc`)
- [ ] All three action buttons use `defaultActiveButton` (blue pill `RoundButton`) — spec §4.7 (current uses plain `IconButton`)
- [ ] Button labels uppercase: "FORWARD", "SEND NOW", "DELETE" — spec §4.7 (current shows icons, no labels)
- [ ] Animated count badge on each button via `setNumbersText` — spec §4.7
- [ ] Inter-button gap: `topBarActionSkip 10px` — spec §4.7
- [ ] Corner radii: 8px outer ends, small inner ends (segmented pill) — spec §4.7
- [ ] Cancel button: `RoundButton(defaultLightButton)`, `width: -18px`, right-aligned 10px from edge — spec §4.7
- [ ] Cancel label: "CLEAR" / "CANCEL" uppercase — spec §4.7 (currently close icon only)
- [ ] "Send Now" button for scheduled messages — spec §4.7
