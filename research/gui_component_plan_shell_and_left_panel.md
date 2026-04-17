# Component Plan: App Shell Layout + Left Panel (Chat List Sidebar)

Written before any code, per `gui_build_process.md` rules.

## Spec Sections Referenced

All section references below are from `research/telegram_desktop_ui.md`:

- **§1** Window Layout & Column Structure
- **§2** Chat List Sidebar (folder tabs, search, rows, states)
- **§3** Hamburger Menu (profile, accounts, menu items)
- **§4** Chat Header / Top Bar (for shell integration)
- **§13** Mobile / Web Compatibility (OneColumn mode)

## Architecture Decisions: UniClient Adaptations

### Where UniClient differs from Telegram Desktop

1. **Multi-platform accounts.** Telegram has one platform; UniClient has many (Telegram, Bale, Matrix, XMPP, IRC, etc.). The filters sidebar in Telegram is for chat folders only. In UniClient, we need to show platform/account context somewhere. **Decision:** Use the hamburger menu's account section for platform/account switching (matches Telegram's existing multi-account pattern). The filters sidebar stays for folders. `AppState.activePlatform` and `AppState.activeAccountId` control filtering.

2. **Unified chat list.** UniClient's `ChatState.chats` is already a unified list across all accounts. Filtering happens via `chatsForPlatform()` / `chatsForAccount()`. The chat list widget just renders whatever `ChatState` provides.

3. **Platform indicator on chat rows.** Since chats come from different platforms, each chat row should show a small platform icon (left of the avatar or as a badge) so users can tell where a chat lives. **This is UniClient-specific, not in the Telegram spec.**

4. **Auth flow.** UniClient's `AuthState` already handles the full flow. The auth screen is a separate concern (will be built later as a dedicated component).

## Widget Hierarchy

```
UniClientShell (StatefulWidget — responsive layout manager)
├── FiltersColumn (72px, optional — shown when folders exist)
│   ├── HamburgerButton (top, opens drawer)
│   ├── FolderFilterList (scrollable, vertical)
│   │   └── FolderFilterButton × N (icon + label, 72px wide)
│   └── EditButton (bottom)
│
├── DialogsColumn (260-540px, resizable)
│   ├── SearchBar (top, 7px padding each side)
│   │   ├── SearchInput (text field, placeholder "Search")
│   │   └── CancelButton (visible when focused)
│   ├── FolderTabStrip (horizontal, only when FiltersColumn hidden)
│   │   └── FolderTab × N (scrollable, underline indicator)
│   └── ChatList (scrollable, main content)
│       ├── ArchivedChatsRow (37px, collapsible, if archived exist)
│       └── ChatListRow × N (62px each)
│           ├── Avatar (46px, with online dot / stories ring)
│           ├── PlatformBadge (UniClient-specific, small icon)
│           ├── ChatName + TypeIcon + MuteIcon + Timestamp
│           ├── MessagePreview + SenderPrefix
│           └── UnreadBadge / PinIcon / SendStateIcon
│
├── ChatColumn (380px min, main content)
│   ├── ChatTopBar (54px) — stub for now
│   ├── MessageList — stub for now
│   └── ComposeArea — stub for now
│
├── InfoColumn (292-392px, optional) — stub for now
│
└── HamburgerDrawer (274px, overlay)
    ├── ProfileArea (134px cover)
    │   ├── Avatar (clickable)
    │   ├── DisplayName + badges
    │   ├── Phone / Username
    │   └── AccountToggleArrow
    ├── AccountList (collapsible)
    │   ├── AccountRow × N (avatar + name)
    │   └── AddAccountButton
    ├── MenuItems
    │   ├── MyProfile
    │   ├── NewGroup
    │   ├── NewChannel
    │   ├── Contacts
    │   ├── Calls
    │   ├── SavedMessages
    │   ├── Settings
    │   └── NightModeToggle (inline switch)
    └── VersionFooter
```

## Key Dimensions (from spec)

| Element | Dimension | Source |
|---|---|---|
| Filters sidebar width | 72px | SS1 |
| Dialogs min width | 260px | SS1 |
| Dialogs max width | 540px | SS1 |
| Dialogs collapse threshold | < 130px → snap to 0 (avatar-only) | SS1 |
| Chat column min width | 380px | SS1 |
| Info panel min/max | 292px / 392px | SS1 |
| OneColumn breakpoint | bodyWidth < 640px | SS1 |
| ThreeColumn breakpoint | bodyWidth >= 932px | SS1 |
| Wide chat mode | chat width >= 880px | SS1 |
| Chat row height | 62px | SS2 |
| Chat row avatar | 46px diameter | SS2 |
| Chat row padding | 10L, 8T, 10R, 8B | SS2 |
| Chat name position | x=68, y=10 | SS2 |
| Message preview position | x=68, y=34 | SS2 |
| Hamburger drawer width | 274px | SS3 |
| Hamburger cover height | 134px | SS3 |
| Top bar height | 54px | SS4 |
| Window min size | 380x480 | SS1 |
| Default size | 800x600 → 1024x768 (large) | SS1 |
| Archived row height | 37px | SS2 |

## Key Colors (from spec, light theme defaults)

| Element | Color |
|---|---|
| Chat row default bg | #ffffff |
| Chat row hover bg | #f1f1f1 |
| Chat row active bg | #419fd9 |
| Chat name (normal) | #222222 |
| Chat name (active) | #ffffff |
| Timestamp/preview (normal) | #999999 |
| Active text | #ffffff |
| Sender prefix | #168acd |
| Draft prefix | #dd4b39 |
| Unread badge (unmuted) | #40a7e3 |
| Unread badge (muted) | #bbbbbb |
| Online dot | #4dc920 |
| Ripple normal | #e5e5e5 |
| Ripple active | #2095d0 |

## States Each Widget Needs

### UniClientShell
- `LayoutMode` (oneColumn, twoColumn, threeColumn) — computed from window width
- `dialogsWidth` (double) — persisted, resizable
- `infoColumnOpen` (bool) — toggle
- `hamburgerOpen` (bool) — drawer state
- Data: `AppState` (accounts, platforms), `AuthState` (active auth flow)

### ChatList
- Data: `ChatState.chats` (filtered by active platform/account/folder)
- `activeChat` — highlighted row
- `scrollController` — for lazy loading
- Sort: pinned first, then by lastMsgTime descending

### ChatListRow
- Data: `ChatInfo` from model
- States: default, hover, active/selected
- Derived: formatted timestamp, truncated preview, badge visibility

### HamburgerDrawer
- Data: `AppState.accounts` grouped by platform
- `accountsExpanded` (bool) — persisted
- Active account highlighting

### SearchBar
- `focused` (bool) — controls showing top peers / recent / cancel button
- `query` (String) — search text
- Results: `ChatState.searchChats()` / `ChatState.searchMessages()`

## Where My Instinct Differs From Spec

1. **INSTINCT:** Put platform icons in a left rail/nav bar. **SPEC:** Telegram uses hamburger menu for account switching, filters sidebar for folders only. **Following spec.**

2. **INSTINCT:** Use Material3 NavigationDrawer. **SPEC:** Custom drawer with specific 274px width, 134px cover, exact menu items. **Building custom.**

3. **INSTINCT:** Make the search bar sticky/floating. **SPEC:** Search bar is at the top of the dialogs column, scrolls with chat list (actually it stays fixed at top, but the results replace the chat list content). **Following spec.**

4. **INSTINCT:** Use ListView.builder for chat list. **ACTUALLY CORRECT** — this matches spec (lazy loading via slices).

5. **INSTINCT:** Skip the resize handle between columns. **SPEC:** Explicit drag handle for resizing dialogs column width. **Must implement.**

## Build Order (smallest self-contained widget first)

1. **UniClientShell** — responsive layout with column structure, placeholder content
2. **ChatListRow** — single chat row widget (most reused, most detailed)
3. **ChatList** — scrollable list of ChatListRow, with sorting/filtering
4. **SearchBar** — search input with focus states
5. **HamburgerDrawer** — menu with profile, accounts, menu items
6. **FiltersColumn** — folder sidebar (only if folders exist)
7. **FolderTabStrip** — horizontal tabs (fallback when no sidebar)
8. **Column resize handles** — drag-to-resize between columns

## Cross-References Checked
- SS1 ↔ SS13: OneColumn mode (< 640px) = single panel with navigation
- SS2 ↔ SS18: Folder tabs reference folder settings
- SS3 ↔ SS14: Settings menu items lead to settings screens (future)
- SS2 ↔ SS4: Search in chat list vs search in top bar (different behaviors)
