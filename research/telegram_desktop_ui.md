# Telegram Desktop UI Specification

Complete reverse-engineered UI spec from Telegram Desktop source code (AyuGram fork). Reference for building a 1:1 Flutter replica with web/mobile compatibility.

Source: `AyuGram/AyuGramDesktop` (dev branch), all `Telegram/SourceFiles/` directories.

---

## 1. Window Layout & Column Structure

### Column System

Four-zone layout (left to right):

1. **Filters sidebar** (optional, leftmost) -- 72px fixed width (`windowFiltersWidth`). Hamburger menu icon at top, vertical folder filter buttons (scrollable, drag-reorderable), "Edit" button at bottom. Shown when user has chat folders enabled.

2. **Dialogs column** (left) -- Chat list. Default width from persisted ratio (`dialogsWidthRatio * bodyWidth`). Min 260px (`columnMinimalWidthLeft`), max 540px (`columnMaximalWidthLeft`). Resizable via drag handle. If dragged below 130px, snaps to 0 (collapsed narrow mode showing only avatars).

3. **Chat column** (center) -- Message history. Min 380px (`columnMinimalWidthMain`). Takes remaining width.

4. **Third column** (right, optional) -- Info panel. Min 292px (`columnMinimalWidthThird`), max 392px (`columnMaximalWidthThird`). Resizable, width persisted.

Shadow separators (1px) between columns.

### Responsive Breakpoints

Three layout modes computed against `bodyWidth` (window width minus filters sidebar):

- **OneColumn** (< 640px): Single panel visible at a time. Tapping a chat slides from dialogs to chat view; back button returns. Third column disabled. **This is the mobile layout.**
- **TwoColumn** (>= 640px, < 932px or third column disabled): Dialogs left, chat right. Standard desktop.
- **ThreeColumn** (>= 932px with info panel enabled): All three columns. If tight, dialogs and third column shrink proportionally while chat stays at 380px min.

**Wide chat mode**: Triggers at 880px chat width (`adaptiveChatWideWidth`), centering the message bubble column within the chat area.

### Window Defaults

- Default: 800x600. Large-screen default: 1024x768. Minimum: 380x480.
- Main menu (hamburger drawer): 274px wide, 134px cover area.

### Animations

- Column width changes: `easeOutCirc` easing, ~150-200ms.
- Section transitions: Horizontal slide with content snapshot crossfade (FromLeft/FromRight).
- Menu expand/collapse: `slideWrapDuration`.

---

## 2. Chat List Sidebar

### Folder Tabs

**Two modes:**

**Vertical sidebar** (wide windows): Left-edge column, 72px. Each tab = `SideBarButton` with icon + folder name. "All Chats" default (filter ID 0, can be hidden). Active tab highlighted. Unread badges per tab (muted vs unmuted color). Scrollable, drag-reorderable. Hamburger button at top.

**Horizontal tab strip** (when vertical sidebar off): Scrollable row below search bar. Active tab has sliding underline indicator. Horizontal mouse-wheel scrolling redirected. Right-click context menu (edit, remove, setup). Drag reorder supported.

### Search Bar

Top of sidebar. Placeholder: "Search". Padding: 7px each side.

When focused: **Top Peers** strip (horizontal, 46px avatars) + **Recent Contacts** list (56px rows, 42px avatars). When typing: results in three tabs (MyMessages with sub-filters Private/Groups/Channels, PublicPosts, ThisPeer). Cancel button appears. Empty results: Lottie animation (100px) + descriptive text.

### Chat List Rows

**Row height:** 62px. **Padding:** 10px left, 8px top, 10px right, 8px bottom.

**Avatar:** 46px diameter, positioned at (10, 8). Online indicator: 12px green dot (#4dc920) with 3px white stroke, bottom-right of avatar. Stories ring: unread = gradient outline, read = thinner line at 60% opacity.

**Chat name:** x=68px, y=10px. Font: semibold. Color: #222222 normal, #ffffff active. Chat-type icon before name (bot/channel/forum/group, 3px skip). Mute icon after name (4px skip). Verified/scam badges after name.

**Timestamp:** Right-aligned, same line as name. Font: 13px. Color: #999999 normal, #ffffff active. Skip from right: 5px. Formats: "12:30" (today), "Yesterday", "Mon" (this week), "Jan 15" (older).

**Message preview:** x=68px, y=34px. Font: normal ~13px. Color: #999999 normal, #ffffff active. Sender name prefix in service color (#168acd). "Draft:" prefix in red (#dd4b39). Typing indicator replaces text with animated dots. Mini media previews: 16px thumbnails.

**Unread badge:** Right side, message preview line. Font: 12px bold. Pill-shaped. Background: #40a7e3 unmuted, #bbbbbb muted. Text: #ffffff. Active row: white badge with blue text. Mention badge: 13x13px icon. Reaction badge: 13x13px icon.

**Pin icon:** Shown when no unreads, right side at textTop position.

**Send state icons:** Sending (clock), sent (single check), received (double check) -- 20px skip.

### Chat Item States

- **Default:** Background #ffffff.
- **Hover:** Background #f1f1f1.
- **Active/selected:** Background #419fd9, all text white, badges inverted.
- **Ripple:** #e5e5e5 normal, #2095d0 on active row.

### Special Rows

**Archived Chats:** 37px height. Folder name + unread counter. Collapsible.

**Saved Messages:** Bookmark icon userpic (no avatar photo).

### Sorting

Pinned chats at top (no visible separator). Below: sorted by last message time descending.

### Swipe & Drag

- Left-to-right swipe: quick action (archive/read).
- Drag-to-reorder: pinned chats only, `sineInOut` animation.
- Drag-and-drop forwarding: `application/x-td-forward` MIME, auto-select on hover timer.

---

## 3. Hamburger Menu

### Profile Area (top)

Circular avatar (clickable), display name with optional verified/premium badge, emoji status. Phone number and @username below. Toggle arrow at top-right expands/collapses account list.

### Account Section (collapsible)

Shows all logged-in accounts (avatar + name each). "Add Account" button at bottom. Toggle appears when 2+ accounts exist. Drag-reorderable. Expanded/collapsed state persisted.

### Menu Items (in order)

| # | Label | Icon |
|---|-------|------|
| 1 | My Profile | `menuIconProfile` |
| 2 | Menu Bots | (dynamic per-bot) |
| 3 | New Group | `menuIconGroups` |
| 4 | New Channel | `menuIconChannel` |
| 5 | Contacts | `menuIconUserShow` |
| 6 | Calls | `menuIconPhone` |
| 7 | Saved Messages | `menuIconSavedMessages` |
| 8 | Settings | `menuIconSettings` |
| 9 | Night Mode | `menuIconNightMode` (inline toggle) |

Archive row appears separately when user has an archive folder.

### Night Mode

Inline toggle switch directly in menu. Animates between day/night themes immediately.

### Settings Sections

| # | Section | Icon |
|---|---------|------|
| 1 | My Account | `menuIconProfile` |
| 2 | Notifications | `menuIconNotifications` |
| 3 | Privacy and Security | `menuIconLock` |
| 4 | Chat Settings | `menuIconChatBubble` |
| 5 | Folders | `menuIconShowInFolder` |
| 6 | Advanced | `menuIconManage` |
| 7 | Devices / Active Sessions | `menuIconUnmute` |
| 8 | Power Saving Mode | `menuIconPowerUsage` |
| 9 | Language | (dynamic label) |

Footer: version number + changelog link.

---

## 4. Chat Header / Top Bar

### Dimensions

Fixed height: 54px (`topBarHeight`). Background: `topBarBg`.

### Left-to-Right Layout

1. **Back button** -- Visible in single-column (narrow/mobile) layout or when navigating into forum topic/sublist. Left-arrow icon. Right-click opens call-type menu.

2. **Avatar** (`UserpicButton`) -- Peer's profile photo. For Saved Messages: saved-messages icon. Transparent to clicks (passes through to info area).

3. **Title text** -- Semibold font. Elided with ellipsis. Verified/scam/fake badge inline after name.

4. **Subtitle / status** -- `dialogsTextFont`. Content by peer type:
   - **DM:** "online" (green) or "last seen [time]"
   - **Groups:** "X members, Y online"
   - **Channels:** "X subscribers"
   - **Typing:** Animated typing/recording/uploading indicator replaces subtitle

### Right-Side Buttons (right to left)

1. **Menu toggle** (three-dot) -- Opens: New Window, Archive, Pin, View Profile, Mute submenu, Mark Read/Unread, Clear History, Delete Chat, Leave Channel.
2. **Info toggle** -- Opens/closes right info panel. Hidden in single-column.
3. **Call button** -- Phone icon, 1:1 DMs only. Right-click submenu: audio/video call.
4. **Group call button** -- For groups/channels when calls permitted.
5. **Search button** -- Toggles inline search (text field replaces title, with "jump to date" / "choose from user" filters).

### Pinned Message Bar (below top bar)

Horizontal bar with: message text preview (optional thumbnail, rounded corners), "Pinned Message" title (or "#X of Y" for multiple pins). Click navigates to pinned message. Close/unpin button.

### Contact Status / Action Bar

Contextual bars: Add Contact, Block, Share Phone Number, Report Spam, Unarchive, Topic Reopen, Join Request Info.

### Group Call Bar

Active call: overlapping participant userpics (green speaking-indicator rings) + "Join" button.

### Selection Mode

Title/subtitle slides out, action buttons slide in: Forward, Send Now, Delete. Count label: "X messages selected".

---

## 5. Message List & Bubbles

### Message List

Scrolls newest-at-bottom. Lazy loading via slices. **Scroll-to-bottom FAB** (`JumpDownButton`) appears when scrolled away, displays unread count badge. Additional corner buttons for unread mentions, reactions.

**Date separators** (`DateBadge`): Centered text in rounded service-message pill (radius = half min service height). Scroll with messages -- NOT sticky headers.

**"Unread Messages" bar**: Full-width horizontal band above first unread message with centered text like "3 unread messages".

### Message Bubbles

**Alignment:** Own messages right-aligned. Received left-aligned. In Saved Messages: forwarded-from-self right, others left.

**Bubble shape:** Two corner radii: `bubbleRadiusLarge: 16px`, `bubbleRadiusSmall: 6px`. Each corner independently set to None (square), Small (6px), Large (16px), or Tail (decorative triangle). Tail on bottom corner of sender's side: bottom-right for outgoing, bottom-left for incoming.

**Max bubble width:** 430px. Wide mode: 542px total (430 + margins).

**Bubble colors:** Four variants: `messageIn`, `messageInSelected`, `messageOut`, `messageOutSelected`. Each has `msgBg` (background) + `msgShadow` (2px bottom shadow). Default: incoming = white/light gray, outgoing = green-tinted.

**Margins:** Left 16px, top 6px, right 56px, bottom 2px. Attached to previous: top margin collapses to 0px. Internal padding: 11px horizontal, 8px vertical.

### Consecutive Message Grouping

Two flag pairs per element: `AttachedToPrevious/Next` (spacing) and `BubbleAttachedToPrevious/Next` (corner rounding).

- **Top corners:** Attached-to-previous on sender's side -> Small (6px), else Large (16px).
- **Bottom corners:** Attached-to-next on sender's side -> Small, else Tail (last message) or Large.
- **Tail** only on last message in group.
- **Sender name + avatar** only on first message. Avatar size: 33px. Avatar skip: 40px.

### Bubble Content Layout (top to bottom)

1. **Sender name** -- Semibold, colored per user. Hidden if attached-to-previous, in DMs, or own outgoing. Admin/creator badge may appear.
2. **Topic button** (forums) -- Small pill with topic icon + name.
3. **Via bot** -- Shown if no sender name and no forward header.
4. **Forward header** -- "Forwarded from Name".
5. **Reply block** -- Colored left bar (2px wide, 36px tall), reply sender name + preview text (10px gap). Clickable to jump to original.
6. **Message text** -- Rich text: bold, italic, code, links, spoilers, blockquotes with colored outlines.
7. **Bottom info** -- Bottom-right: timestamp + "edited" label + delivery status icon (clock/single-check/double-check) + views count + forwards count.
8. **Reactions** -- `InlineList` of reaction emoji, inside or outside bubble depending on `embedReactionsInBubble()`.

### Sender Name Colors

7 base colors (`kSimpleColorIndexCount`), assigned by `id % 7`. Remapped via `{0, 7, 4, 1, 6, 3, 5}` to palette indices `historyPeer1NameFg` through `historyPeer8NameFg`. Consistent per user ID across all groups. Extended: up to 64 colors for premium/collectible name colors.

### Selection Mode

Long-press or checkbox to select (not single click). Round checkbox on each message. Top action bar: Forward, Delete, Copy (based on intersection of selected messages' capabilities).

### Service Messages

Centered text in rounded pill, semi-transparent `msgServiceBg` background. Inverted rounded corners where pill width changes between lines. Semibold font in `msgServiceFg` color.

---

## 6. Media Message Types

### Shared Constants

Max media dimension: 430px. Min photo dimension: 100px. Aspect ratio always preserved, never upscaled.

### Photos

Inline in bubble. Downscaled to 430x430 max, 100px min per axis. Caption below narrows the photo. Four-tier loading: full -> thumbnail -> small -> blurred inline placeholder. Click opens viewer. Spoiler: particle overlay, animates to reveal on tap. Enlarge button in bottom-right for large photos.

### Photo Albums (Grouped Media)

Up to 10 items. Spacing: 4px. Width: 100-430px. Layout rules by count:
- **2 items:** Side-by-side (proportional to ratios) or top/bottom if both very wide.
- **3 items:** Narrow first = left column + two stacked right. Otherwise first spans top, two below.
- **4 items:** Wide first = top row + three below. Otherwise left column + three stacked right.
- **5-10 items:** Complex layouter: clamp ratios to 0.667-2.75, generate all valid row configs (1-4 per row, up to 4 rows), select config whose total height closest to `maxHeight * 4/3`.

Corner rounding only at group's outer edges.

### Videos

Same layout as photos (430px max, aspect ratio). Play button centered on thumbnail. Duration badge + file size in bottom corner over semi-transparent background.

### GIFs

Max: 320px (smaller than photos). Auto-play, loop, no audio. Corner badge "GIF". Max inline area: 1920x1080px.

### Stickers

No bubble background -- standalone. Max: 224px (static/animated), 256px (emoji stickers). Lottie for animated (TGS), WEBM for video stickers. Premium: 1.49x size with mirrored effect. Click opens sticker pack.

### Voice Messages

Inside bubble. Waveform: bars 2px wide, 1px apart, 3-17px tall. Active (played) = `msgWaveformActive`, unplayed = `msgWaveformInactive`. Play/pause button (44px thumb) left. Duration + played status at status line. Interactive seeking by tap position. If no waveform data: 31 random peaks generated. Optional transcribe button.

### Video Messages (Round Video)

Circular, max 360px diameter. Duration badge. Click opens playback. Progress as arc overlay.

### Files/Documents

44px thumbnail/icon left, filename (middle-truncated) + file size right. 11px gap between icon and text. Name at 12px from top, status at 34px. Icon changes by state: download arrow, cancel X, play triangle.

### Audio/Music

Same as document layout but 44px icon = play/pause button. Track title + artist via `FormatSongNameFor()`. Duration as "played/total" during playback. Cover art replaces generic icon when available.

### Polls

Question: `historyPollQuestionStyle`. Options: radio buttons (circle for single, rounded rect for multi) + text. After voting: percentage + colored filling bar (`easeOutCirc` animation). Quiz mode: correct = green, wrong = red + 400ms shake animation. Correct triggers fireworks. Footer: total votes. Timed polls: remaining seconds. Recent voter userpics in a row.

### Locations

Static map thumbnail at `locationSize`, 430px max, 100px min. Optional venue title (2 lines max) + description (3 lines max) below. Click opens coordinates. Live locations: circular progress indicator showing elapsed/remaining time.

### Contacts

Circular userpic left. Name + phone number beside it. Action buttons below: "Send Message" / "Add Contact" / "View Details".

### Web Page Previews

Two modes: **Article** (small thumbnail right, text wraps) and **Standard** (full-width, media below text). Site name, title, description (max 5 lines). YouTube: play icon overlay + duration badge. "Open" button (36px) with localized text.

---

## 7. Compose Area

### Text Input Field

`InputField`, center of compose strip. Auto-grows vertically, capped at `historyComposeFieldMaxHeight`, then scrolls. Document margin: 4px.

**Placeholder text** (context-dependent): "Write a message..." (normal), "Broadcast a message..." (channels), "Edit message" (editing).

**Rich text:** Bold (Ctrl+B), Italic (Ctrl+I), Underline (Ctrl+U), Strikethrough (Ctrl+Shift+X), Monospace (Ctrl+Shift+M), Spoiler (Ctrl+Shift+P), Blockquote. Instant emoji replacements (`:)` -> emoji). Link detection after 500ms debounce.

### Attachment Button

Left side of input. Click opens dropdown: Photo/Video, File, Poll, Location, Contact. Attachment bots (mini-apps) appended dynamically.

### Emoji/Sticker/GIF Button

Right of input, left of send. Toggles panel (see Section 10). Can be pushed to third-column or floating overlay.

### Send Button

Rightmost position. Eight states: **Send**, **Schedule**, **Save**, **Record**, **Round** (video note), **Cancel**, **Slowmode**, **EditPrice**.

State logic: editing -> Save; inline bot -> Cancel; empty field + recording available -> Record/Round; otherwise -> Send/Schedule. State transitions animate between pixmap snapshots. Long-press opens send menu (silent send, scheduled send). Slowmode: countdown display.

### Voice Record Bar

Replaces input during recording. Red pulsing circle + duration timer. Slide left cancels. Slide up locks (hands-free mode). Once locked: stop button, waveform visualization, send button. Supports pause/resume, video messages, TTL (self-destruct), listen-before-send.

### Reply / Edit / Forward Bar (FieldHeader)

Above input, height `historyReplyHeight`.

**Reply:** Replied-to author name + text excerpt + 32px thumbnail preview. Blue/accent vertical bar (2px wide, 36px tall). Close (x) button. Navigation arrows for stepping through replies.

**Edit:** "Edit message" label + original text. Send button -> Save. Confirmation dialog on cancel.

**Forward:** Forwarding author name + message preview. Options to hide sender name. Close button.

**Web preview:** Link preview with title + description below header.

### Bot Keyboard

Below input area. Button height: 36px (2px margin, 10px padding). Tiny buttons: 25px. Animation: 200ms. Show/hide toggle buttons. Inline keyboards (in message bubbles) are separate.

### Drag & Drop

File drag over chat shows drop zone overlay. Accepts files, images, byte arrays.

### Send Files Dialog

Files in grouped "blocks" for album layout. Controls: compress toggle, group toggle, spoiler toggle, caption input with autocomplete, emoji panel, send button with silent/scheduled menu.

### Autocomplete

@mentions, #hashtags, /commands, inline bot results. Emoji suggestions while typing `:emoji_name`.

### Additional Controls

- **Send As:** Sender identity selector for channels.
- **Silent Toggle:** Broadcast without notification.
- **Scheduled Button:** Opens scheduled messages view.
- **TTL Button:** Disappearing message timer.
- **Characters Limit:** Remaining count near limit.
- **Bot Command Start:** `/` button for bot command entry.

---

## 8. Info / Details Panel (Third Column)

### Dimensions & Behavior

Min width: 324px. Preferred: 392px. Layer mode: 48px margin each side. Top bar: 54px (side), 56px (layer).

**Three wrap modes:** Side (persistent, message area shrinks), Narrow (full-width takeover), Layer (modal overlay with fade).

Navigation stack: push on sub-section click, pop on back. Slide animation (FromRight to open, FromLeft to go back).

### Scrolling

Entire panel = one continuous scrollable column. Cover/avatar area is a "flexible top bar" that compresses on scroll. Sub-pages (full members, media tabs) replace content entirely with own scroll.

### User Profile (DM)

Top to bottom:
1. **Cover** -- 72x72px avatar centered. Name, username/status below. Compresses on scroll.
2. **Action buttons** -- 52px square buttons (23px icons), 68px total height. Buttons: Message, Call, Video Call, Search, More.
3. **Details** -- Labeled text fields (`TextWithLabel`): phone, username, bio. Padding: 23px left, 9px top, 20px right, 7px bottom. Empty fields auto-hide.
4. **Notifications toggle** -- Reactive on/off.
5. **Shared media buttons** -- One row per type with count: Photos, Videos, Files, Audio, Links, Voice, GIFs. Hidden when zero. Also: Common Groups.
6. **Actions** -- Share/Edit/Delete Contact, Block/Unblock.

### Group Info

Same structure + differences:
- Cover shows member count as status.
- Admin/member management buttons for supergroups.
- Actions: Leave Group, Report, Edit Group (if admin).
- **Members list** -- Inline: 40px avatar + name + online status. Owner/admin badges. "Add Member" button. Search toggle. Click pushes user profile.

### Channel Info

- Subscriber count instead of members.
- No inline members (only admins visible to admins).
- Similar Channels button.
- Join/Leave Channel actions.

### Shared Media Sub-Pages

**Photo/Video grid:** Columns = `(width - margins + skip) / (82px + 2px skip)`. ~4 columns at 392px, ~3 at 324px. Square thumbnails. Date section headers: 28px height.

**GIF layout:** Masonry/waterfall (variable aspect ratios).

**Files/Links/Audio/Voice:** Single-column list items.

### Reactive Data

All values are live streams -- name, phone, bio, member count, notifications update in real-time. Panel is always live.

### State Persistence

Memento system saves: scroll position, search query, active media tab, navigation stack.

---

## 9. Context Menus & Actions

### Message Context Menu (right-click on message)

Items in order (each gated by permissions):
1. Reply / Quote and Reply
2. Voice Timecode (on playing voice messages)
3. Copy Selected Text
4. Translate Selected
5. Go to Message (in pinned/preview context)
6. View Replies / View Topic / View Thread
7. Edit (own messages within edit time window)
8. Pin / Unpin
9. Copy Message/Post Link
10. Forward
11. Send Now (scheduled only)
12. Reschedule (scheduled, max 20)
13. Save/Copy Image (photos)
14. Attached Stickers / Open/Save GIF / Sticker Pack Info
15. Favorite/Unfavorite Sticker
16. Show in Folder/Finder (local files)
17. Copy Text (full message)
18. Translate
19. Copy Link (on URLs)
20. Report
21. Select / Clear Selection
22. Delete (attention-styled; "Cancel Upload" for uploading)

**Poll-specific:** Translate Poll, Retract Vote, Stop Poll, per-option submenu.

### Chat List Context Menu (right-click sidebar)

- Pin/Unpin
- Mute submenu (ringtone, toggle sound, preset durations, custom, mute forever/unmute)
- Mark as Read/Unread
- Archive/Unarchive
- New Window
- Folder actions (expand/collapse, settings, mark read)
- Clear History
- Delete/Leave (attention-styled)

### User Context Menu (click username/avatar in group)

View Profile, Mention, Send Message, Add/Edit/Delete Contact, Share Contact, Block/Unblock, Report. Admin actions: Promote, Restrict, Ban, Delete All from User.

### Reaction Picker

**Strip:** Horizontal row of recent reactions (up to 8). Appears on message hover or with context menu. Selected reaction scales 1.24x over 200ms. Expand chevron opens full panel.

**Full panel:** Expands from strip (300-420ms, `easeOutCirc`). Emoji grid with category tabs, search, sticker effects.

### Forward Dialog

Full-screen overlay: search/filter bar (multi-select input), chat filter tabs (folder-based), chat grid (4-column, avatars + names + checkboxes). Self-chat prioritized first. Send button options: preserve/drop sender name, preserve/drop caption, send silently, schedule.

### Delete Confirmation

"Delete for me" (always) + "Delete for everyone" (gated by message age, ownership, permissions). Additional checkboxes: Ban User, Report Spam, Delete All from User (moderation). Revoke preference remembered.

---

## 10. Emoji / Sticker / GIF Panels

### Panel Position & Size

Anchors to bottom-right of compose area. Width: 345px fixed. Height: 75% of available vertical, clamped 278-640px. Margins: 10px, corner radius: 8px. Show animation: 200ms expansion from bottom-right. Hide: 200ms opacity fade. Auto-hide 300ms after mouse leaves (3s if context menu open).

### Tab Bar

Three text labels: "Emoji", "Stickers", "GIFs" (optional "Masks"). Switching: 200ms slide animation with pixmap crossfade.

### Emoji Tab

Search row: 33px tall, search icon + input + category icons. Category footer: 8 icons (Recent, Smileys, Nature, Food, Activities, Travel, Objects, Symbols), each 30px wide.

Grid: columns = `floor(innerWidth / 37px)` (~8 columns). Cell: `singleWidth x (singleWidth - 2)px`. Section headers: 33px, semibold. Hover: rounded rect background.

Skin-tone selector: long-press (500ms), floating popup with base + 5 variants. Custom emoji packs as additional sections with "Add"/"Unlock" buttons. Collapsed sets show 3 rows + "+N" badge.

### Sticker Tab

Columns: `floor(width / 64px)` (~5 columns). Cell: square ~64x64px. Render: Lottie (TGS), WEBM, or static WebP. Footer: horizontally scrollable pack icons. Sections: "Recent" (capped at 20) + installed packs (semibold header). Featured/trending with "Add" button (26px). Context menu: Fave/Unfave, View Set. Search: 400ms debounced server query.

### GIF Tab

Masonry/waterfall layout. Padding: 9px/5px/3px/9px, 3px gap. Rows of uniform height with variable aspect ratios (true masonry). Powered by `@gif` inline bot. Saved GIFs as default; search switches to inline results. Category shortcuts in footer (emoji-based). Context menu: Save/Delete GIF.

### Inline Emoji Suggestions

When typing `:text`, dropdown above cursor. Horizontally scrollable, 40px per item, 240px scrolled width, 8px fade padding. Selecting replaces the `:text` token.

### Inline Sticker Suggestions

When typing Unicode emoji, sticker popup above input. Server query for matching stickers. Click sends.

---

## 11. Authentication / Login Flow

### Architecture

Step stack managed by `Intro::Widget`. Each screen = `Step` subclass sharing `Data` struct (phone, phoneHash, codeLength, callStatus, pwdState, termsLock). Navigation: `goNext`/`goBack`/`goReplace` with slide/cover animations.

Persistent bottom bar: `_next` RoundButton (300x42px, 6px radius), `_back` IconButton, `_changeLanguage` LinkButton, `_settings` button, optional `_resetAccount` button.

### Screen 1: QR Code Login (default entry)

QR code centered at `introQrTop`. Max QR size: 180px, 8px rounded background padding. Telegram logo at center (44px circle, blue #40A7E3, paper plane icon). Radial spinner while waiting for token. Cross-fade on new QR arrival.

Below QR: title "Log in to Telegram by QR Code". Three numbered instruction steps: (1) Open Telegram on phone, (2) Go to Settings > Devices > Link Desktop Device, (3) Point phone at screen. Step numbers bold, positioned left.

Below: "Log in by phone number" link. Optional passkey login link. Token auto-refreshes on expiry. Next button hidden.

### Screen 2: Phone Number Entry

Three inputs: country picker dropdown, country code (64px, "+XX"), phone part (remaining). 300px total width.

"Log in via QR code" link as alternative. Next button: "Next".

Validation: phone > 1 digit. Errors: "PHONE_NUMBER_INVALID" inline, "PHONE_NUMBER_BANNED" dialog, flood warning. 1-second poll timer while request pending.

### Screen 3: OTP Code Entry

Custom `CodeInput` with individual digit cells. Each cell: rounded rectangle, `windowBgOver` background. Focused: `windowActiveTextFg` border. Cell height: 50px, width: 40px (0.8x height), border: 4px, spacing: 10px. Font: 20px.

Digit entry animation: fade in + slide up (20% cell height). Deletion: scale down + fade out. Error: shake animation + red borders.

Arrow keys/Home/End navigate cells. Backspace deletes + moves left. Paste auto-fills + auto-submits when complete.

Below input: call countdown ("Telegram will call you in X:XX" / "Calling..."). "Didn't get the code?" link for alternative delivery.

### Screen 4: 2FA Password

`PasswordInput` field, 300px wide. Hint label: "Hint: {hint}" (if set). "Forgot password?" link below.

Submit: SRP hash computation + `auth.checkPassword`. Errors: "Wrong password" + select all + error highlight. "Forgot password" -> recovery code mode.

**Recovery mode:** Hides password field, shows code input. "Recovery code sent to {email_pattern}". If no recovery email: info box + "Reset account" button.

### Screen 5: Registration (New Account)

`UserpicButton` for avatar (right edge at `introPhotoTop`). First name + Last name input fields. RTL languages: swap field order.

Title: "Your Name". Description: "Enter your name and add a profile photo". Terms acceptance dialog if required. Next button: "Start Messaging".

### Animations

**Cover animation** (QR <-> phone): Gradient cover (208px, with icons + app logo) slides vertically. Title/description crossfade with `easeOutCirc`. Content snapshots fade. Duration: `introCoverDuration`.

**Slide animation** (between non-cover steps): Bitmap snapshots, horizontal slide over `introSlideDuration`. Clipped to prevent overflow.

---

## 12. Calls UI

### Incoming Call

Panel opens with `WaitingIncoming` state. Center: userpic (160px circle), caller name (21px semibold), "Incoming call..." status. Bottom: **Decline** (red), **Answer** (green, pulsing outer ripple ring tracking ringtone peak audio level at 135-degree angle). Background: gradient from caller's profile photo colors.

### Active Call (Audio)

Center: userpic, name, duration timer (mm:ss, updates every second). Bottom bar (150ms transition): **Screencast**, **Camera**, **Hangup** (red, center, "End Call"), **Mute** (toggles between mic icon and red muted icon), **Add People**.

**Signal quality:** 4 vertical bars (2px wide, 1px radius, 2px spacing, 4-10px tall). Inactive bars at 50% opacity.

**Encryption fingerprint:** Emoji row at top.

**Remote mute pill:** "[User] muted their microphone" tooltip. Low battery indicator similarly.

Controls auto-hide after 5s in fullscreen (2s on mouse-leave), reappear on mouse movement.

### Video Call

Remote video fills main area (aspect-ratio fill). Userpic/name/status hidden when video active.

**Self-view PIP:** `VideoBubble`, 160x110px default. Draggable, snaps to corners (12px padding from edges). Mirrored horizontally by default (unflips during screen-share).

Pre-connect: outgoing preview centered (360x120 min to 1620x540 max based on window height).

Camera button: active (camera icon) / muted (crossed camera). Corner device-selector arrow for switching cameras/audio devices.

### Group Call

Two modes: **narrow** (380px, list-only) and **wide** (960x580px+, video grid).

Title bar: group name, optional recording dot (6px red circle), participant count subtitle, menu toggle.

**Members list:** Per-participant state: speaking = animated blob ring (green glow, 27-29px radius, pulsating on audio level), muted = crossed mic icon, raised hand = hand icon.

**Mute button:** Large Lottie-animated (36x36 icon, 42px bg circle). Green (unmuted) <-> gray (muted) with blob animations.

**Bottom bar:** Settings (gear), Video (camera toggle), Screen Share, Hangup (red leave).

**Wide mode:** Video tile grid with participant name overlays, pin/unpin toggles, shadow gradients.

**Minimized bar (TopBar):** 38px height atop chat window. Group name, duration, participant userpics (28px, 8px overlap), mute toggle, hangup. Animated gradient background (green=active, gray=muted, purple=force-muted).

### Screen Sharing

Source chooser modal: thumbnails (235x165px, 2px h-spacing, 10px v-spacing) with live previews + title labels. Optional "Share audio" checkbox. During sharing: Screencast button highlighted, PIP shows shared screen (mirroring disabled).

### Post-Call Rating

5 star icons (36x36px, 24px h-padding). Unselected: `windowSubTextFg`. Selected: `lightButtonFg`. Comment input below (max 135px height). Submits 1-5 rating + comment string.

---

## 13. Mobile / Web Compatibility Notes

### OneColumn Mode (< 640px)

This IS the mobile layout. Behaviors:
- Only one panel visible at a time (dialogs OR chat OR info).
- Chat list fills full width. Tapping a chat slides right to message view.
- Back button appears in chat header to return to chat list.
- Third column (info panel) opens as full-width takeover or modal layer.
- Folder tabs switch to horizontal strip below search bar.
- Compose area: full width, same controls.
- No resize handles (columns don't coexist).

### Responsive Adaptations

- **Dialogs collapse:** At extreme narrow widths, dialog list shows only avatars (no text).
- **Wide chat mode (880px+):** Message bubbles center within the chat area instead of stretching.
- **Emoji panel:** Anchors relative to compose area, height scales to 75% of available space.
- **Forward dialog:** Full-screen overlay regardless of width.
- **Calls:** Panel adapts between narrow (list-only) and wide (video grid) at 960px.

### Touch vs Mouse

- **Context menus:** Long-press instead of right-click.
- **Swipe gestures:** Left/right on chat list rows for quick actions.
- **Drag-to-reorder:** Touch-hold + drag for pinned chats and folder tabs.
- **Voice recording:** Hold-to-record on send button, slide up to lock.
- **Message selection:** Long-press to enter selection mode (not right-click).

### Web Considerations

- All rendering is Flutter (Skia/CanvasKit), no native widgets to adapt.
- Keyboard shortcuts (Ctrl+B/I/U etc.) work on desktop web, hidden on mobile web.
- File drag-and-drop available on desktop web only.
- System tray / notifications use Web Notifications API.
- Clipboard paste for images/files via browser APIs.

---

## 14. Settings — General & My Account

Telegram Desktop settings are presented as a layered navigation system. A scrollable panel slides in from the right, with a back arrow and section title in the top bar. All settings sections share the same `settingsButton` style: 60 px left padding (for icon), 22 px right padding, 10 px vertical padding, with text in `boxTextStyle`. Icons sit at `iconLeft: 20px` with `settingsIconRadius: 6px` rounded background fill.

### 14.1 Opening Settings

Settings are reached via the hamburger menu (three horizontal lines at the top-left of the sidebar). The menu item is labelled `lng_menu_settings` ("Settings"). Clicking it pushes the Main settings section onto the navigation stack as a full-height inner panel. The top bar shows a back arrow (`infoTopBarBack`) and the title "Settings". On the right side of the top bar, a three-dot overflow menu provides:

- **Add Account** (`lng_menu_add_account`) — only shown if the account count is below the maximum (currently 10 for Premium, 3 for free). Icon: `menuIconAddAccount`.
- **Edit Profile** (`lng_settings_information`) — navigates to the My Account / Information section. Icon: `menuIconEdit`. Hidden in support mode.
- **Log Out** (`lng_settings_logout`) — opens a confirmation dialog (`lng_sure_logout`). Styled with `attentionBoxButton` (red text). Icon: `menuIconLeaveAttention`.

### 14.2 Main Settings Page — Cover / Profile Header

The top of the Main settings page is a fixed-height cover widget. Its total height is:
```
st::settingsPhotoTop (8px) + photo height (infoProfileCover.photo.size) + st::settingsPhotoBottom (16px)
```

**Layout:**

| Element | Position | Details |
|---------|----------|---------|
| **Avatar** | Left: 22px (`settingsPhotoLeft`), Top: 8px (`settingsPhotoTop`) | `UserpicButton` with `Role::OpenPhoto`. Clicking opens the full profile photo viewer. Hovering shows a camera overlay to change/upload photo. |
| **Display Name** | Left: 112px (`settingsNameLeft`), Top: 12px (`settingsNameTop`) | `FlatLabel` using `infoProfileCover.name` style. Selectable text; right-click shows "Copy Full Name". |
| **User ID** | Left: 112px (`settingsPhoneLeft`), Top: 37px (`settingsPhoneTop`) | `FlatLabel` in `defaultFlatLabel` style. Selectable; right-click context menu offers "Copy ID" (AyuGram addition). |
| **Username** | Left: 112px (`settingsUsernameLeft`), Top: 58px (`settingsUsernameTop`) | `FlatLabel` in `infoProfileMegagroupCover.status` style (subdued text color `windowSubTextFg`). Displayed as a link. If no username is set, shows "Add" link text. Clicking: if username exists, copies `t.me/username` link to clipboard and shows a toast; if empty, opens the Usernames box. |
| **QR Code Button** | Right-aligned, vertically centered | `IconButton` using `infoProfileLabeledButtonQr` style. Only visible when the user has at least one username. Opens a QR code dialog (`PeerQrBox`). |
| **Premium Badge** | Inline after name | `InfoPeerBadge` at `settingsCoverBadge` position (4px right, 2px down from name end). Clicking opens the emoji status panel. |

**Avatar Overlay Interaction:**
When the user hovers over their own avatar, a semi-transparent overlay with a camera icon appears. Clicking opens a popup menu with options:
- Upload photo from file
- Choose from emoji/stickers (sets a markup-based avatar)
The chosen image is uploaded via `api().peerPhoto().upload()`. During upload, a circular progress indicator is shown on the userpic.

### 14.3 Main Settings Page — Navigation Buttons

Below the cover, separated by a full-width divider (`AddDivider`) and skip, the main body lists navigation buttons. Each button is a `SettingsButton` row with an icon on the left (inside a rounded-square background), title text, and a right chevron. Buttons have ripple animation on press.

The order from top to bottom:

1. **AyuGram Preferences** (`ayu_AyuPreferences`) — Icon: `menuIconPremium` (star). Navigates to AyuGram-specific settings. Followed by a skip + divider + skip to separate it.

2. **My Account** (`lng_settings_my_account`) — Icon: `menuIconProfile` (person silhouette). Navigates to the Information/Edit Profile section (Section 14.5). Hidden in support mode. Search keywords: "profile", "edit", "information".

3. **Notifications and Sounds** (`lng_settings_section_notify`) — Icon: `menuIconNotifications` (bell). Keywords: "alerts", "sounds", "badge".

4. **Privacy and Security** (`lng_settings_section_privacy`) — Icon: `menuIconLock` (padlock). Keywords: "security", "passcode", "password", "2fa".

5. **Chat Settings** (`lng_settings_section_chat_settings`) — Icon: `menuIconChatBubble` (speech bubble). Keywords: "themes", "appearance", "stickers". Navigates to Section 14.6.

6. **Folders** (`lng_settings_section_filters`) — Icon: `menuIconShowInFolder` (folder). Keywords: "filters", "tabs". Conditionally shown: only appears if the user already has chat folders enabled, or if the server config `dialog_filters_enabled` is true.

7. **Advanced** (`lng_settings_advanced`) — Icon: `menuIconManage` (gear/wrench). Keywords: "performance", "proxy", "experimental". Navigates to Section 14.7.

8. **Devices** (`lng_settings_section_devices`) — Icon: `menuIconUnmute` (speaker). Keywords: "sessions", "calls".

9. **Power Saving** (`lng_settings_power_menu`) — Icon: `menuIconPowerUsage` (battery). Keywords: "battery", "animations", "power", "saving". Opens a dialog box (`PowerSavingBox`) rather than navigating to a subsection.

10. **Language** (`lng_settings_language`) — Icon: `menuIconTranslate` (globe/A). Keywords: "translate", "localization", "language". Right-side label shows the current language native name (e.g., "English", "Deutsch"). Clicking opens the `LanguageBox` with a searchable list of all available language packs.

### 14.4 Main Settings Page — Interface Scale

Below the navigation buttons, separated by a divider:

**"Use Default Scale" toggle** — A `SettingsButton` with toggle switch on the right. When toggled ON, the app uses `kScaleAuto` (follows system DPI). Search keywords: "zoom", "size", "interface", "ui".

**Scale Slider:** A continuous `MediaSlider` (`settingsScale` style, seek handle 15x15px) with a right-aligned label showing the current percentage (e.g., "125%"). Range: `kScaleMin` to `MaxScaleForRatio(devicePixelRatio)`, step 5%.

**Preview tooltip:** While dragging, a floating preview window (`ScalePreview`) appears above the slider showing how the UI would look at that scale.

**Restart confirmation:** If the user releases the slider at a different scale, a confirmation dialog appears: "Some settings will be applied after restarting. Restart now?" with "Restart Now" / "Cancel" buttons.

### 14.5 My Account / Edit Profile (Information Section)

Navigated to from "My Account" on the main settings page. Title: "Edit Profile". Vertically scrolling panel.

#### 14.5.1 Profile Photo Area

Centered layout at the top, height `settingsInfoPhotoHeight` (162px):

- **Photo:** `UserpicButton` at 100x100px, centered horizontally, top offset 2px. Clicking opens full photo viewer.
- **Upload Sub-Button:** Small circular overlay at bottom-right of photo (6px from right edge). Camera/pencil button for changing photo.
- **Name:** `FlatLabel` in `settingsCoverName` style (17px semibold, max height 24px). Centered below photo with 7px gap.
- **Online Status:** `FlatLabel` in `settingsCoverStatus` style (`windowSubTextFg`). Centered below name with -1px spacing.

#### 14.5.2 Bio Input Field

- **Input Field:** `Ui::InputField` in `settingsBio` style — transparent background, multiline, placeholder "Bio". Margins: 22px left, 6px top, 22px right, 4px bottom. Min height: 32px.
- **Character Counter:** Top-right corner, shows remaining chars. Turns red when negative.
- **Auto-Save:** Debounced 1000ms. Also saves on Enter and widget destruction.
- **Emoji Support:** Emoji suggestions enabled, instant replacements follow global settings.
- **Footer:** "Any details such as age, occupation or city."

#### 14.5.3 Profile Information Rows

| Row | Icon | Label | Value | Click | Right-Click |
|-----|------|-------|-------|-------|-------------|
| **Name** | `menuIconProfile` | "Name" | Full name | Opens `EditNameBox` (first + last name) | "Copy Full Name" |
| **Phone** | `menuIconPhone` | "Phone Number" | Formatted number | Copies to clipboard, toast 500ms | "Copy Phone Number" |
| **Username** | `menuIconUsername` | "Username" | @-prefixed or "Add" link | Opens `UsernamesBox` | "Copy @mention" |

Footer: "People can message you using your username without knowing your phone number."

#### 14.5.4 Personal Channel & Color

- **Channel Row:** Icon `menuIconChannel`, "Personal Channel", shows channel name or "Add".
- **Your Color Button:** `AddPeerColorButton` showing user's name color swatch. Opens `EditPeerColorBox`.

#### 14.5.5 Birthday

- **Birthday Row:** Icon `menuIconGiftPremium`, "Date of Birth", formatted date or "Add". Opens date picker.
- **Footer:** Dynamic text based on birthday privacy setting, with "[Manage]" link to privacy settings.

#### 14.5.6 Accounts List

Lists all logged-in accounts as `SettingsButton` rows with small avatar, name, and badge (Premium/unread). Max accounts: 10 Premium, 3 free.

**Interactions:**
- Click active account: closes settings.
- Click inactive: switches account.
- Ctrl+Click: opens in new window.
- Right-click: context menu (Open in New Window, Copy Phone, Activate, Mark All Read, Log Out).
- Drag-and-drop reorder supported.

**Add Account Button:** Plus icon with `windowBgActive` fill. Hidden at max accounts. Ctrl+Click: add in new window.

### 14.6 Chat Settings Section

Title: "Chat Settings". Top bar overflow: "Create New Theme".

#### 14.6.1 Themes

Horizontal row of 4 theme cards (80x92px each): Default (light), Day (blue tint), Dark, Night Blue. Each shows miniature chat bubble preview (40x14px bubbles) and radio dot at bottom.

**Accent Color Palette:** Row of 24px circular color dots. Rightmost is a multi-colored custom picker opening HSL `ColorEditor`.

**System Accent Color:** Checkbox "Use system accent color" (Qt6+ only).

#### 14.6.2 Theme Settings

- **Your Color** — Name color preview, opens `EditPeerColorBox`.
- **Auto-Night Mode** — Toggle, shown if system reports dark mode preference.
- **Font Family** — Shows current font name, opens `ChooseFontBox` with chat preview.

#### 14.6.3 Cloud Themes

Horizontal scrollable list of cloud themes. "Show All" link if truncated. "Edit Current Theme" button for user-created themes.

#### 14.6.4 Chat Background

- **Background Preview:** 76px square thumbnail with rounded corners. Adjacent links: "Choose from gallery" and "Choose from file".
- **Tile Background** — Checkbox (non-pattern/non-solid backgrounds only).
- **Adaptive Layout for Wide Screens** — Checkbox (wide layout mode only).

#### 14.6.5 Chat List Quick Action

Radio buttons for left-swipe action: Mute, Pin, Read, Archive, Delete, Disabled. Live preview widget with animated Lottie icon demonstrating chosen action.

#### 14.6.6 Stickers and Emoji

Checkboxes: Large Emoji, Replace Emojis, Suggest Emoji, Suggest Animated Emoji (Premium only), Suggest Stickers by Emoji, Loop Animated Stickers. Navigation buttons: Your Stickers, Emoji Sets.

#### 14.6.7 Messages

**Send by:** Radio — Enter or Ctrl+Enter (Cmd+Enter on Mac).

**Double-click action:** Radio — Reply or React (with animated reaction button showing current favorite).

Checkboxes: Show reply button in corner, Show reaction button in corner.

#### 14.6.8 Sensitive Content

Toggle "Disable filtering" with footer about sensitive media in public channels. Hidden if server disallows changing.

#### 14.6.9 Shortcuts & Archive

- **Keyboard Shortcuts** — navigates to Shortcuts section.
- **Archive Settings** — opens `ArchiveSettingsBox`.

### 14.7 Advanced Section

#### 14.7.1 Data and Storage

Buttons: Connection Type (with proxy info), Download Path, Local Storage, Downloads. Toggle: Ask download path.

#### 14.7.2 Automatic Media Download

Three buttons: In Private Chats, In Groups, In Channels — each opens `AutoDownloadBox`.

#### 14.7.3 Window Title

Checkboxes: Show chat name, Show account name (multi-account only), Show unread count, Native/Qt frame toggle.

#### 14.7.4 Window Close Behavior (Linux only)

Radio: Run in Background, Close to Taskbar, Quit.

#### 14.7.5 System Integration

Checkboxes: Show tray icon, Show taskbar icon (at least one required), Monochrome tray icon, Launch at startup, Start minimized (with autostart only), Add to "Send To" menu (Windows only).

#### 14.7.6 Performance

Power Saving button, Hardware video acceleration toggle, OpenGL/ANGLE backend toggle (restart required).

#### 14.7.7 Spellchecker

System/Custom spellchecker toggle, Auto-download dictionaries toggle, Manage dictionaries button with installed count.

#### 14.7.8 Software Update

Auto-update toggle with version/progress label. Install beta versions toggle. Check for updates / "Update Telegram" button.

### 14.8 Premium & Help Sections (Main Page Footer)

**Premium:** Telegram Premium (gradient button), Telegram Stars (with balance), TON Currency (if balance), Telegram Business, Send a Gift.

**Help:** Telegram FAQ, Telegram Features, Ask a Question (confirmation dialog → support chat).

### 14.9 Visual Style Constants

| Token | Value | Usage |
|-------|-------|-------|
| `settingsButton.padding` | `margins(60px, 10px, 22px, 10px)` | Standard settings button insets |
| `settingsButton.iconLeft` | `20px` | Icon horizontal position |
| `settingsButtonNoIcon.padding` | `margins(22px, 10px, 22px, 8px)` | Button without icon |
| `settingsIconRadius` | `6px` | Rounded corner radius for icon backgrounds |
| `settingsInfoPhotoSize` | `100px` | Edit Profile avatar size |
| `settingsInfoPhotoHeight` | `162px` | Edit Profile photo area height |
| `settingsAccentColorSize` | `24px` | Theme accent color dot diameter |
| `settingsBackgroundThumb` | `76px` | Wallpaper preview square size |
| `settingsThemePreviewSize` | `size(80px, 92px)` | Theme card preview dimensions |
| `settingsThemeBubbleSize` | `size(40px, 14px)` | Mini chat bubble in theme card |
| `settingsCheckboxPadding` | `margins(22px, 10px, 10px, 10px)` | Checkbox outer margins |
| `settingsSendTypePadding` | `margins(22px, 5px, 10px, 5px)` | Radio button option margins |
| `settingsBioMargins` | `margins(22px, 6px, 22px, 4px)` | Bio input outer margins |
| `settingsCoverName.font` | `font(17px semibold)` | Settings cover name font |

### 14.10 Animations and Transitions

- **Section navigation:** Sections slide in from the right with horizontal slide + fade.
- **Toggle switches:** Pill-shaped toggle, knob slides with default animation duration.
- **Color dot selection:** Selected ring animates in/out over `defaultRadio.duration * 2`.
- **Scale preview:** Floating preview tooltip during slider manipulation.
- **Account list reorder:** Drag-and-drop with spring physics animations.
- **SlideWrap sections:** Conditional sections toggle with smooth height animation or instant show/hide.
- **Ripple on buttons:** All `SettingsButton` instances have ripple animation on click.
- **Theme card radio:** Standard radio check animation on the dot.

---

## 15. Settings — Notifications

Accessed via **Settings > Notifications and Sounds** (hamburger menu or sidebar Settings entry). The page is built as a vertical layout from seven builder sections, rendered top-to-bottom with skip/divider separators.

### 15.1 Multi-Account Notifications (conditional)

Shown only when 2+ accounts are logged in. Hidden entirely for single-account setups.

- **Section title**: "Show notifications from" — 14px semibold, `windowActiveTextFg`.
- **Toggle**: "All accounts" — `settingsButtonNoIcon` style, toggle on right. Default: ON. When turned OFF, notifications from all non-active accounts are immediately cleared.
- **Divider text**: "Turn this off if you want to receive notifications only from the account you are currently using."

### 15.2 Global Settings

- **Section title**: "Global settings".

Three toggle buttons, each `settingsButton` style (60px left padding, icon area):

| # | Label | Icon | Default | Setting |
|---|-------|------|---------|---------|
| 1 | "Desktop notifications" | `menuIconNotifications` (bell) | ON | `desktopNotify` |
| 2 | Platform-specific flash/bounce | `menuIconDockBounce` | ON | `flashBounceNotify` |
| 3 | "Allow sound" | `menuIconUnmute` (speaker) | ON | `soundNotify` |

Flash/bounce label varies: Windows → "Flash the taskbar icon", macOS → "Bounce the Dock icon", Linux → "Draw attention to the window".

**Volume slider** (below "Allow sound"): `MediaSlider` in `SlideWrap`, visible when sound enabled. 100 positions (1–100%), percentage label in `windowActiveTextFg`. Dragging plays notification sound preview. Slider: `settingsScale` (15x15px seek thumb), padding `settingsBigScalePadding` (21px left/right, 7px top, 4px bottom).

### 15.3 Notification Preview (Name & Text Checkboxes)

Displayed in `SlideWrap` based on `desktopNotify` state. When off, plain divider shown instead.

**Preview bubble**: Chat-themed rectangle on wallpaper background, `boxRadius` corners, `msgInBg` fill.

Inside the bubble:
- **Userpic** (36x36px, at 14px,11px): "Name" checked → dinosaur SVG; unchecked → app logo.
- **Title** (at 64px,9px): "Name" checked → "Dino Rex"; unchecked → app name.
- **Text** (at 64px,30px): "Text" checked → "It's morning in Tokyo 😎"; unchecked → "You have a new message".

Bubble margins: 40px left, 20px top, 40px right, 58px bottom (`notifyPreviewMargins`).

**Two overlay checkboxes** centered horizontally, 12px apart (`notifyPreviewChecksSkip`):
- "Name" and "Text" — `ChatServiceCheckbox` style (rounded pill, service-message background, white text).
- Unchecking "Name" auto-unchecks "Text". Checking "Text" auto-checks "Name".
- Three states: `ShowPreview` (both), `ShowName` (name only), `ShowNothing` (neither).

### 15.4 Notifications for Chats (Per-Type Rows)

- **Section title**: "Notifications for chats".

Four **split-toggle rows** (`settingsNotificationType` style, 40px height, 60px left padding):

| # | Label | Icon | Sub-page |
|---|-------|------|----------|
| 1 | "Private chats" | `menuIconProfile` | NotificationsType(User) |
| 2 | "Groups" | `menuIconGroups` | NotificationsType(Group) |
| 3 | "Channels" | `menuIconChannel` | NotificationsType(Broadcast) |
| 4 | "Reactions" | `menuIconGroupReactions` | NotificationsReactions |

Each row: left portion (clickable → sub-page) with icon + label + status subtitle, 1px vertical separator, right toggle area (70px wide).

**Status subtitle** (`windowSubTextFg`): No exceptions → "Click here to change". With exceptions → "On/Off, N exception(s)".

**Toggle with exceptions**: Confirmation dialog appears: "Please note that N chat(s) are listed as exceptions and won't be affected." with "OK" and "View exceptions" buttons.

### 15.5 Per-Type Sub-Page

#### 15.5.1 Enable / Sound / Tone Controls

- **"Enable notifications"** — toggle with `menuIconNotifications`. Right-click opens Mute Menu popup.
- **"Sound"** — `SlideWrap`, visible when notifications enabled. Toggle.
- **"Notification tone"** — nested `SlideWrap`, visible when sound enabled. Right label shows tone name. Opens Ringtones Box.
- **Volume slider** — per-type, 1–100%.

#### 15.5.2 Exceptions List

- **"Add an exception"** — `settingsButtonActive` (accent text), `menuIconInviteSettings`. Opens peer list picker → mute menu.
- **Exception rows**: Userpic + name, status "Muted"/"Unmuted", "Remove" link on right. Click opens context menu with view profile + mute options.
- **"Delete all exceptions"** — red attention style, shown when >1 exception. Confirmation dialog.

#### 15.5.3 Mute Menu (Popup)

`PopupMenu` with `popupMenuWithIcons` style:
1. "Select tone" → Ringtones Box
2. "Disable/Enable sound" toggle
3. Recent mute durations (0–2 items) with compact labels ("8h")
4. "Mute for..." → duration picker
5. "Mute forever" / "Unmute" — animated color transition (red ↔ green)

**Mute Duration Picker**: Drum-picker wheel with values: 15min, 30min, 1h, 2h, 3h, 4h, 8h, 12h, 1d, 2d, 3d, 1w, 2w, 1mo. Top-right menu offers "Custom" with arbitrary precision.

### 15.6 Ringtones Box

`GenericBox` (364px wide), titled "Notification Sound".

- **Radio list**: "Default" (plays default sound), "No sound" (silent), custom tones (filename, right-click → "Delete").
- **"Upload Sound"** — `ringtonesBoxButton` style, `settingsIconAdd` icon. File dialog filtered to `*.mp3`. Upload constraints: max size and duration from server config.
- **Volume slider** (conditional): Shown when volume controller provided. Hidden for "No sound".
- **Footer**: "Right click on any short voice note or MP3 file in chat and select 'Save for Notifications'."
- **Buttons**: "Save" / "Cancel".

### 15.7 Reactions Sub-Page

Title: "Notifications for reactions".

#### 15.7.1 Notify Me About

Two split-toggle rows:

| # | Label | Icon |
|---|-------|------|
| 1 | "Reactions to my messages" | `menuIconMarkUnread` |
| 2 | "Votes in my polls" | `menuIconCreatePoll` |

Left click (when enabled) → dialog "Notify about reactions from": "From everyone" / "From my contacts" radio. Toggle: ON → All, OFF → None.

#### 15.7.2 Settings

- **"Show sender's name"** — toggle controlling whether reaction notifications show who reacted.

### 15.8 Events

| # | Label | Icon | Default |
|---|-------|------|---------|
| 1 | "Contact joined Telegram" | `menuIconInvite` | ON |
| 2 | "Pinned messages" | `menuIconPin` | ON |

### 15.9 Calls

- **"Accept calls on this device"** — `menuIconCallsReceive`, toggle. Controls `callsDisabledHere` server-side flag.

### 15.10 Badge Counter

All toggles `settingsButtonNoIcon` style:

| # | Label | Default |
|---|-------|---------|
| 1 | "Include muted chats in unread count" | ON |
| 2 | "Include muted chats in folder counters" (shown if folders exist) | ON |
| 3 | "Count unread messages" (ON = message count, OFF = chat count) | ON |

### 15.11 System Integration (Native Notifications)

Hidden if platform doesn't support native notifications or if native is enforced.

- **"Use native notifications"** — toggle. Toggling recreates notification backend.

When native OFF, advanced controls appear:

#### 15.11.1 Windows Focus Mode

- **"Respect system Focus mode"** — toggle, suppresses notifications during Windows Focus Assist.

#### 15.11.2 Multi-Display Selector

Shown when multiple monitors detected. Radio buttons: "Default" + one per display ("{name} ({width}×{height})").

#### 15.11.3 Notification Position

Interactive **monitor widget** (280x160px screen area, `notificationsBoxScreenBg` fill):
- **Five clickable corners**: TopLeft, TopCenter, TopRight, BottomRight, BottomLeft.
- **Sample notification bars** (64x16px): Selected corner shows up to N bars at full opacity; others show 1 bar at 50%.
- **Hover**: Spawns actual desktop sample notification windows (320x80px) at the corresponding screen corner with app logo, title, sample text, close button.
- **Click**: Selects corner. Default: BottomRight.

#### 15.11.4 Notification Count

Discrete slider with 5 positions (1–5). Selecting a count animates sample bars in monitor widget. Default: 3.

### 15.12 Animations and Transitions

- **SlideWrap**: ~300ms height animation (`anim::type::normal`).
- **Toggle switches**: Sliding pill with `anim::type::normal`.
- **Sample notification bars**: Independent 150ms fade per bar when count changes.
- **Desktop sample windows**: 150ms fade in/out.
- **Mute menu color**: Red ↔ green transition over `defaultPopupMenu.showDuration`.

### 15.13 Style Reference

| Token | Value | Usage |
|-------|-------|-------|
| `settingsNotificationType` | 40px height, 60px left, 4px top/bottom | Per-type split rows |
| `rightsButtonToggleWidth` | 70px | Toggle area width in split rows |
| `notifyPreviewMargins` | 40/20/40/58px | Preview bubble container |
| `notifyPreviewUserpicSize` | 36px | Preview userpic |
| `notifyPreviewChecksSkip` | 12px | Gap between Name/Text checkboxes |
| `notificationsBoxScreenSize` | 280x160px | Monitor screen area |
| `notificationSampleSize` | 64x16px | Mini notification bars |
| `notificationSampleOpacity` | 0.5 | Inactive corner bar opacity |
| `notifyWidth` | 320px | Sample notification width |
| `notifyMinHeight` | 80px | Sample notification height |
| `notifyPhotoSize` | 62px | Sample notification userpic |
| `notifyFastAnim` | 150ms | Fade in/out duration |
| `ringtonesBoxButton` | light text, 56px left pad, 25px icon-left | Upload Sound button |

---

## 16. Settings — Privacy & Security

### 16.1 Navigation

From the main Settings screen (the hamburger menu / three-line icon in the sidebar), the "Privacy and Security" row appears in the settings list. It is rendered as a `SettingsButton` with:
- **Icon**: `menuIconLock` (padlock), positioned `iconLeft: 20px` from the left edge.
- **Label**: The localized string `lng_settings_section_privacy` ("Privacy and Security").
- **Style**: `settingsButton` — `padding: margins(60px, 10px, 22px, 10px)`, font from `boxTextStyle`.
- **Search keywords**: "security", "passcode", "password", "2fa".

Tapping this button navigates to the `PrivacySecurity` section, whose title bar shows `lng_settings_section_privacy`. The section is a scrollable `VerticalLayout`. It reloads data on a 60-second polling timer (`kUpdateTimeout = 60 * 1000ms`).

The section is built by `BuildPrivacySecuritySectionContent`, which calls these builders in order:

1. `BuildSecuritySection`
2. `BuildPrivacySection`
3. `BuildArchiveAndMuteSection`
4. `BuildBotsAndWebsitesSection`
5. `BuildConfirmationExtensions` (conditional)
6. `BuildTopPeersSection`
7. `BuildSelfDestructionSection`

---

### 16.2 Security Section

Starts with `settingsPrivacySkip` (14px) vertical skip, then a subsection title `lng_settings_security` ("Security"). Search keywords: "security", "password", "passcode".

#### 16.2.1 Two-Step Verification (Cloud Password)

- **Button**: `lng_settings_cloud_password_start_title` ("Two-Step Verification").
- **Icon**: `menuIcon2SV`.
- **Right label**: Dynamically shows one of:
  - `lng_profile_loading` ("Loading...") while state is fetched.
  - `lng_settings_cloud_password_on` ("On") if password is set.
  - `lng_settings_cloud_password_off` ("Off") if no password.
- **Search keywords**: "password", "2fa", "two-factor".

**State machine** (determined by `PasswordState` enum):
- **Loading**: Button click does nothing.
- **On** (password set): Navigates to `CloudPasswordInput` — a check-password screen with:
  - Animated Lottie icon (`cloud_password/password_input`, 100x100px).
  - Title: `lng_settings_cloud_password_check_subtitle` ("Enter your password").
  - Description: `lng_settings_cloud_password_manage_about1`.
  - Single password input field (`PasswordInput` widget, `lng_cloud_password_enter_old` placeholder).
  - If a hint exists, shown as `lng_signin_hint` below the field (hidden when error is visible).
  - "Forgot password?" link button below the input. Behavior depends on whether recovery email exists:
    - **Has recovery email**: Sends recovery code, navigates to `CloudPasswordEmailConfirm`.
    - **No recovery email**: Shows a confirm box (`lng_cloud_password_reset_no_email`) with an "OK" button that initiates a timed password reset. The link then changes to show "Cancel Reset" with a countdown label (`lng_settings_cloud_password_reset_in`, showing time remaining).
    - **Reset ready**: Link becomes `lng_cloud_password_reset_ready`.
  - "Check" button. On success: navigates to `CloudPasswordManage` (change/disable password). On wrong password: shows error `lng_cloud_password_wrong`, increments bad tries counter.

- **Off** (no password): Navigates to `CloudPasswordStart` — an intro screen:
  - Animated Lottie icon (`cloud_password/intro`, 100x100px), padding `settingLocalPasscodeIconPadding` (0, 19, 0, 5).
  - Title: `lng_settings_cloud_password_start_title`.
  - Description: `lng_settings_cloud_password_start_about`.
  - "Set Password" button navigates to `CloudPasswordInput` (create mode) with two password fields ("Enter password" + "Re-enter password"), then to `CloudPasswordHint`, then to email setup.

- **Unconfirmed** (email confirmation pending): Navigates to `CloudPasswordEmailConfirm` to complete the pending setup.

#### 16.2.2 Auto-Delete Messages (Global TTL)

- **Button**: `lng_settings_ttl_title` ("Auto-Delete Messages").
- **Icon**: `menuIconTTL`.
- **Right label**: Current TTL formatted via `Ui::FormatTTL`, or `lng_settings_ttl_after_off` ("Off").
- **Search keywords**: "ttl", "auto-delete", "timer".

Opens `GlobalTTL` section with:
- Lottie icon (`ttl`, 100x100px) in a `BoxContentDivider` header, loops on show.
- Subsection title: `lng_settings_ttl_after_subtitle`.
- **Radio buttons** for preset periods: Off, 1 day, 7 days, 31 days. If the current value is a custom value, it is added to the list and sorted. Each option is a `SettingsButton` with a `Radiobutton` child overlaid on the right side. Selecting a non-zero value from zero shows a confirmation dialog (`lng_settings_ttl_after_sure`).
- **"Set Custom Period"** button (`lng_settings_ttl_after_custom`): Opens the TTL picker box.
- **Footer**: `lng_settings_ttl_after_about` with a clickable link `lng_settings_ttl_after_about_link` that opens a peer-list box for applying the current TTL to existing chats.

#### 16.2.3 Passcode Lock

- **Button**: `lng_settings_passcode_title` ("Passcode Lock").
- **Icon**: `menuIconLock`.
- **Right label**: "On" / "Off" reflecting whether a local passcode is set.
- **Search keywords**: "passcode", "lock", "pin".

**If no passcode is set**: Opens `LocalPasscodeCreate`:
- Lottie icon (`local_passcode_enter`), animates once on show.
- Title: `lng_passcode_create_title`.
- Two description labels: `lng_passcode_about1` and `lng_passcode_about2`.
- Two password fields: `lng_passcode_enter_first` and `lng_passcode_confirm_new`, width 256px (`settingLocalPasscodeInputField`).
- Error label (hidden by default, appears on mismatch with `lng_passcode_differ`).
- "Create" button. On success: navigates to `LocalPasscodeManage`.

**If passcode is set**: Opens `LocalPasscodeCheck`:
- Same lottie icon, animates once.
- Title: `lng_passcode_check_title`.
- Single password field: `lng_passcode_enter`.
- "Next" button. On wrong passcode: error `lng_passcode_wrong`. On success: navigates to `LocalPasscodeManage`.

**LocalPasscodeManage** screen contains:
- **"Change Passcode"** button (icon: `menuIconLock`).
- **"Auto-Lock"** button (icon: `menuIconTimer`) — right label shows current auto-lock duration. Opens `AutoLockBox` with radio buttons: 1 minute, 5 minutes, 1 hour, 5 hours, plus custom option with `TimeInput` field (HH:MM format, default "10:00").
- **System Unlock toggle** (platform-specific: Windows Hello, Touch ID, Apple Watch, system password).
- **"Turn Off Passcode"** button (red attention style): Shows confirmation dialog, on confirm clears passcode and navigates back.

#### 16.2.4 Passkeys (conditional)

Shown only if platform supports WebAuthn or user has passkeys configured.
- **Button**: `lng_settings_passkeys_title` ("Passkeys").
- **Icon**: `menuIconPermissions`.
- **Right label**: Passkey name (if 1), count (if N), or "Off" (if 0).

#### 16.2.5 Login Email (conditional)

Shown only if user has a login email configured.
- **Button**: `lng_settings_cloud_login_email_section_title`.
- **Icon**: `menuIconRecoveryEmail`.
- **Right label**: Email pattern with asterisks (e.g., `j***@e***.com`).

#### 16.2.6 Blocked Users

- **Button**: `lng_settings_blocked_users` ("Blocked Users").
- **Icon**: `menuIconBlock`.
- **Right label**: Blocked count or "None".

#### 16.2.7 Active Sessions

- **Button**: `lng_settings_show_sessions` ("Active Sessions").
- **Icon**: `menuIconDevices`.
- **Right label**: Session count.

Opens `ActiveSessions` section with:
- Current device at top with 70px userpic and 52px lottie.
- Per-device rows: 84px height, 42px photo, platform-specific icons (Windows, Mac, Ubuntu, Linux, iPhone, iPad, Android, browser icons).
- Close button per session (34x34px).
- "Terminate All Other Sessions" button.
- Auto-terminate inactive sessions timer (7 days / 1-6 months / 1 year).

---

### 16.3 Privacy Section

Subsection title: `lng_settings_privacy_title` ("Privacy").

Each privacy setting is a `SettingsButton` (style: `settingsButtonNoIcon`, padding `22px, 10px, 22px, 8px`) with the setting name on the left and the current value + exception counts on the right. Right label format: `<base_value>` or `<base_value> (+3)` or `<base_value> (+3, -2)` showing Always Allow and Never Allow exception counts.

Clicking any privacy button opens `EditPrivacyBox` (width: `boxWideWidth` = 364px) containing:
1. Optional above-widget (controller-specific).
2. Options title (controller-specific subsection header).
3. **Radio buttons**: Everyone / My Contacts / Close Friends (some settings) / Nobody. Premium-locked options show a lock icon (14px).
4. Warning/description label in a `DividerLabel`.
5. Optional middle widget.
6. **Exceptions section**: "Always Allow" and "Never Allow" buttons, each opening a `PeerListBox` with checkable rows. Premium Users toggle available where applicable.
7. Optional below widget.
8. "Save" + "Cancel" buttons.

#### 16.3.1 Phone Number

Options: Everyone / My Contacts / Nobody. When "Nobody" selected, a sub-section appears: "Who can find me by my number?" with Everyone / My Contacts radio options (controls `AddedByPhone` key separately). Warning shows user's phone-based link when not set to Nobody.

#### 16.3.2 Last Seen & Online

Options: Everyone / My Contacts / Nobody. First-time restriction shows confirmation dialog. Below widget: "Hide Read Time" toggle (when not Everyone). Non-Premium users see "Subscribe to Telegram Premium" button.

#### 16.3.3 Profile Photo

Options: Everyone / My Contacts / Nobody. Middle widget: "Set Public Photo" / "Update Public Photo" button (opens photo editor with ellipse crop) + "Remove Public Photo" button (red attention style, shown when public photo exists).

#### 16.3.4 Forwarded Messages

Options: Everyone / My Contacts / Nobody. Above widget: Live message preview bubble showing a forwarded message with tooltip that changes based on selected option (link included / link for contacts only / name not clickable). Tooltip uses `toastBg` background, `toastFg` text, arrow size 7px.

#### 16.3.5 Calls

Options: Everyone / My Contacts / Nobody. Below widget: Peer-to-Peer sub-section with its own privacy button (`menuIconNetwork` icon) opening a second `EditPrivacyBox` for P2P settings (Everyone / My Contacts / Nobody).

#### 16.3.6 Voice Messages (Premium)

Options: Everyone / My Contacts / Nobody. Non-Premium users see lock icons on restricted options; selecting them reverts to Everyone with Premium promo toast.

#### 16.3.7 Messages from Non-Contacts

Three radio options: Everyone / Contacts & Premium / Charge Stars. "Charge Stars" reveals a star price slider (1 to max) with commission info and USD equivalent, plus "Remove fee for" exceptions button. Non-Premium: restricted options show lock icons.

#### 16.3.8 Birthday

Standard three-option privacy. Above widget shows "set your birthday" link if not yet set.

#### 16.3.9 Gifts (Auto-Save)

Above widget: "Show Icon" toggle (Premium-locked). Below widget: "Accepted Types" with five toggles — Limited, Unlimited, Unique, From Channels, Premium (all Premium-locked).

#### 16.3.10 Bio

Standard three-option privacy, no special widgets.

#### 16.3.11 Saved Music

Standard three-option privacy, no special widgets.

#### 16.3.12 Groups & Channels

Standard three-option privacy. Supports Premiums toggle in Always Allow exceptions.

---

### 16.4 Archive and Mute Section (Conditional)

Shown only if `showArchiveAndMute` is true or user is Premium.
- **Toggle**: "Archive and Mute" — controls auto-archiving of new chats from unknown users.

---

### 16.5 Bots and Websites Section

- **Button**: "Clear Payment and Shipping Info" — opens `ClearPaymentInfoBox` with two checkboxes (Shipping Info, Payment Info) and two-step confirmation with attention-styled "Clear" button.

---

### 16.6 File Confirmations Section (Conditional)

Shown only if user has added no-warning file extensions or disabled IP reveal warning.
- Multi-line input field for file extensions (space-separated, max 10240 chars / 1024 entries).
- "Show IP in WebRTC calls" toggle.

---

### 16.7 Suggest Frequent Contacts Section

- **Toggle**: "Suggest Frequent Contacts" — controls top peers suggestions in search.

---

### 16.8 Self-Destruction Section (Account Auto-Delete)

- **Button**: "If away for..." — right label shows current period.
- Opens `SelfDestructionBox` with radio buttons: 1 month, 3 months, 6 months, 12 months, 18 months, 24 months.

---

### 16.9 Blocked Users Screen

- **"Block User" button** (top, active style): Opens chat-list picker. Already-blocked peers shown as disabled.
- **Blocked peer list**: Each row shows photo, name, status (phone/username/bot), "Unblock" link on right.
- **Empty state**: Lottie animation (`blocked_peers_empty`), title, description. Min height 240px.

---

### 16.10 Styling Summary

| Token | Value | Usage |
|-------|-------|-------|
| `settingsButton` | padding 60/10/22/10, `boxTextStyle`, `iconLeft: 20px` | Standard settings row with icon |
| `settingsButtonNoIcon` | padding 22/10/22/8 | Settings row without icon |
| `settingsButtonLight` | `lightButtonFg` / `lightButtonFgOver` | Positive-action buttons |
| `settingsAttentionButton` | `attentionButtonFg` / `attentionButtonFgOver` | Destructive action buttons |
| `settingsPrivacyOption` | `textPosition: point(13px, 1px)` | Privacy radio buttons |
| `settingsPrivacySkip` | 14px | Standard vertical skip in privacy sections |
| `settingsPrivacySkipTop` | 4px | Extra top padding for radio options |
| `settingsPrivacySecurityPadding` | 12px | Bottom padding before divider |
| `settingsPeerToPeerSkip` | 9px | Skip before P2P sub-section |
| `settingsForwardPrivacyArrowSize` | 7px | Tooltip arrow triangle size |
| `settingLocalPasscodeInputField` | width 256px | Password input field width |
| `settingsBlockedHeightMin` | 240px | Minimum height for blocked users screen |
| `boxWideWidth` | 364px | Width of EditPrivacyBox |
| `sessionListItem` | height 84px, photo 42px at (21,10) | Active session list item |

### 16.11 Animations and Transitions

- **SlideWrap**: Used extensively for conditional sections. Default slide-down/slide-up animation.
- **Lottie icons**: Cloud password intro/input, local passcode enter, TTL settings, blocked users empty state. Typically play once on `showFinished`, except TTL which loops.
- **Password input icon**: Interactive — animates when user starts typing, reverses when cleared.
- **Fireworks**: On successful password validation, `Ui::StartFireworks` triggers particle animation.
- **Exception count updates**: Right labels update reactively via `rpl::producer<QString>` streams (immediate, no animation).

---

## 17. Settings — Data, Storage & Advanced

### 17.1 Navigation

From main Settings, the "Advanced" row: icon `menuIconManage` (gear/wrench), label "Data and Storage", `settingsButton` style. The section builds subsections in order: Update (top when auto-update OFF), Data/Storage, Auto-Download, Window Title, Close Behavior (Linux), System Integration, Performance, Spellchecker, Screen Reader (conditional), Update (bottom when auto-update ON), Export.

### 17.2 Data and Storage

Subsection title: "Data and Storage".

#### 17.2.1 Connection Type

- **Button**: "Connection type", icon `menuIconNetwork`
- **Right label** (dynamic): "Using TCP" / "Connecting..." / "Proxy: {transport}" / "Connected via proxy"
- Click opens **ProxiesBox** (364px wide)

**ProxiesBox layout:**
1. "Try connecting through IPv6" checkbox (padding 22/8/22/5)
2. Radio group: Disabled / Use system settings / Use custom proxy
3. "Use proxy for calls" checkbox (slide-animated, visible when Enabled + proxy supports calls)
4. Divider text about proxy usage
5. Proxy list (or empty state)

**ProxyRow** (each entry): Radio circle on left (animated selection with `easeOutCirc`), title line ("SOCKS5/HTTP/MTPROTO host:port"), status line (Online=blue, Available=green with ping, Checking/Connecting=gray with spinner, Unavailable=red). Context menu: Edit, Share, QR Code, Delete/Restore. Keyboard: Ctrl+C copies all, Ctrl+V pastes proxy URLs.

**Edit Proxy Dialog** (364px): Type radio (HTTP/SOCKS5/MTPROTO), host+port inputs (160px + 55px), credentials (username+password for HTTP/SOCKS5, secret for MTPROTO). Smart paste splits "host:port". MTPROTO shows sponsor warning.

#### 17.2.2 Download Path

- **Button**: "Download path", icon `menuIconShowInFolder`
- **Right label**: "Default folder" / "Temp folder" / custom path
- Hidden when "Always ask" is checked

#### 17.2.3 Manage Local Storage

Opens **LocalStorageBox** (320px):
- Summary row (50px height): "All data" with size + "Clear All" button
- **Total cache size slider**: 18 positions (200MB–10GB)
- **Media cache size slider**: 18 positions (100MB–9GB), linked to total
- **Time limit slider**: 16 positions (1 week–never)
- Per-tag rows: Images, Stickers, Voice, Video messages, Animations, Media cache — each with individual "Clear" button

#### 17.2.4 Recent Downloads

Button "Recent Downloads", icon `menuIconDownload`.

#### 17.2.5 Always Ask Download Path

Toggle, `settingsButtonNoIcon`. When ON, hides download path button.

### 17.3 Automatic Media Download

Three buttons opening `AutoDownloadBox` per source:
- "In private chats" (`menuIconProfile`)
- "In groups" (`menuIconGroups`)
- "In channels" (`menuIconChannel`)

**AutoDownloadBox**: Download section (Photos/Files toggles + size limit slider) and Auto-play section (Video messages/Videos/GIFs toggles + size limit slider). Default download: 10MB, default autoplay: 50MB.

### 17.4 Window Title Content

Checkboxes (`settingsCheckbox` style, text position point(15,1), padding 22/10/10/10):
- "Chat name" — show in title
- "Account name" — shown only when multiple accounts
- "Unread messages count"
- "Use system/Qt window frame" — platform-dependent

### 17.5 Window Close Behavior (Linux Only)

Radio group (`settingsSendType` style, padding 22/5/10/5):
- "Keep running in the background"
- "Minimize to the taskbar"
- "Quit Telegram"

### 17.6 System Integration

#### Checkboxes:
- **Show tray icon** — interlocked with taskbar (at least one required)
- **Show taskbar icon** — interlocked with tray
- **Monochrome tray icon** — slide-animated, visible when tray enabled
- **Launch at startup** — calls `Platform::AutostartToggle`
- **Start minimized** — visible when autostart ON, forced off when passcode set
- **Add to "Send to" menu** — Windows only

#### macOS-specific:
- Warn before quit (shows key combo)
- System text replacements
- Round dock icon (non-App Store)

### 17.7 Performance

#### 17.7.1 Power Saving

Button opens `PowerSavingBox` (364px). 11 toggle flags in groups: Stickers (panel, chat), Emoji (panel, reactions, chat, status), Chat (background, spoiler, effects), Calls, Interface Animations. Battery auto-detection with overlay when active.

#### 17.7.2 Hardware Acceleration

Toggle "Enable hardware acceleration for video".

#### 17.7.3 ANGLE Backend (Windows)

Button with right label showing current backend. Opens `SingleChoiceBox`: Auto, D3D11, D3D9, D3D11on12, Disabled. Change requires restart.

#### 17.7.4 OpenGL Toggle (Linux)

Toggle "Enable OpenGL". Change requires restart.

### 17.8 Spellchecker

- **Enable** toggle (system or custom spellchecker label)
- **Auto-download dictionaries** toggle (visible when custom spellchecker ON)
- **Manage dictionaries** button with count label (visible when custom ON)

### 17.9 Screen Reader Accessibility

Shown only when screen reader detected and mode is disabled. Toggle "Disable screen reader mode".

### 17.10 Software Update

Position: top of section when auto-update OFF, bottom when ON.

- **Auto-update toggle** (`settingsUpdateToggle`, 40px height) with dynamic version label at point(22, 29) in `windowSubTextFg`: version string / "Checking..." / "Downloading {progress}" / "Latest installed" / "Ready to update!" / "Update check failed"
- **Install beta versions** toggle — hidden when auto-update OFF or downloading
- **Check for updates** button — same visibility
- **Update ready overlay**: accent-colored "Update Telegram Desktop" button, calls `Core::Restart()`

### 17.11 Export & Experimental

- **Export Telegram Data** — icon `menuIconExport`, launches export manager
- **Experimental Settings** — icon `menuIconExperimental`, navigates to section with boolean option toggles, import/export via base64url clipboard strings (prefix `tdesktop-flags:`)

---

## 18. Settings — Folders

### 18.1 Page Structure

The Folders settings page is a full scrollable section. Title: "Folders". Icon in parent menu: `menuIconShowInFolder`. On open, requests suggested filters from server.

**Layout (top to bottom):**
1. Animated header with Lottie icon and description
2. "Folders" subsection — list of existing folder rows + "Create New Folder" button
3. "Recommended" subsection — suggested folders from server (hidden when none or at limit)
4. "Show tags" toggle (Premium feature)
5. "View" subsection — vertical/horizontal tab radio buttons (only if enough window space)

On page destruction, auto-saves all pending changes (reorder, additions, removals) to server.

### 18.2 Animated Header

`BoxContentDivider` background containing:
- **Lottie animation**: `"filters"`, **74x74px** (`settingsFilterIconSize`), padded `margins(0, 17, 0, 5)`. Plays once on show.
- **Description**: "Create folders for different groups of chats and quickly switch between them." — `settingsFilterDividerLabel` style (min width 200px, top-aligned), padded `margins(0, 16, 0, 22)`. Balanced line wrapping enabled.

### 18.3 Existing Folders List

Subsection title: "Folders".

Each folder gets a `FilterRowButton` — custom `RippleButton`, row height **52px**.

| Element | Position | Details |
|---|---|---|
| Folder icon | `settingsButtonActive.iconLeft` from left, centered | `LookupFilterIcon()`, painted `activeButtonBg` (or `activeButtonBgOver` on hover) |
| Title | `contactsNameTop` from top, `settingsButtonActive.padding.left` | `contactsNameStyle`, `contactsNameFg`. Supports custom emoji. |
| Status | `contactsStatusTop` from top | `contactsStatusFont`, `contactsStatusFg`. "{N} chats" + " . shareable" if chatlist. |
| Color dot | Left of remove button | Circle, diameter = height/3, `EmptyUserpic::UserpicColor(colorIndex).color2`. Animates via `_colorIndexProgress`. |
| Remove (X) | Right-aligned | Style `filtersRemove` (based on `notifyClose`). Normal state only. |
| Restore button | Same position | `RoundButton` "Restore", height 26px, full radius. Removed state only. |

**Row states:** Normal (clickable → opens `EditFilterBox`, hover highlight + ripple), Removed (dimmed at `stickersRowDisabledOpacity`, restore button), Suggested (add button).

**Remove flow:** If folder has chatlist links → confirmation "This will also delete all invite links" (`attentionBoxButton`). If shared chatlist → requests leave suggestions, shows peer-selection dialog. Otherwise → marks removed immediately (deferred API call on page close).

### 18.4 Create New Folder Button

- Text: "Create New Folder"
- Style: `settingsButtonActive`, icon `settingsIconAdd` (round, `windowBgActive`)
- Checks folder limit on click (shows `FiltersLimitBox` if reached), then opens `EditFilterBox`.

### 18.5 Recommended (Suggested) Folders

`SlideWrap` visible when suggestions > 0 AND count < limit.

Header: divider + subtitle "Recommended folders".

Each suggestion: `FilterRowButton` in Suggested state — no icon on left, title + server description, "Add" button (height 26px, full radius, `settingsFilterAddRecommended` style).

### 18.6 Edit Filter Box (Create / Edit Folder)

`GenericBox`, width **364px** (`boxWideWidth`). Title: "New Folder" / "Edit Folder". `closeByOutsideClick` = false. Buttons: "Create"/"Save" + "Cancel".

#### 18.6.1 Folder Name Input

`InputField` styled `windowFilterNameInput`:
- Right margin 87px (room for icon toggle + emoji button)
- Placeholder: "Folder name"
- Max length: **12 characters**
- Supports custom emoji (Premium) and standard emoji

**Character counter**: Always visible, position `point(75, 27)` from right edge.

**Emoji button**: Position `point(-65, 22)`. Opens `TabbedPanel` in `EmojiOnly` mode.

**Icon selector toggle**: **36x36px**, position `point(-4, 18)` inside name field. Paints current `FilterIcon` in `dialogsUnreadBgMuted`. Click opens `FilterIconPanel` grid.

**Auto-title**: When creating and user hasn't typed, auto-fills based on selected types (Contacts → "Contacts", Groups → "Groups", etc.). Trimmed to 12 chars.

#### 18.6.2 Included Chats Section

- Subtitle: "Included Chats"
- **Add Chats button**: `settingsButtonActive`, `settingsIconAdd`
- **Preview widget** (`FilterChatsPreview`): compact rows, item height **44px**, photo **34px** at `point(13, 5)`, name at `point(59, 14)`, remove button 10px from right edge.

Chat type rows use gradient circle userpics with white icons:

| Flag | Name | Gradient color |
|---|---|---|
| Contacts | "Contacts" | `historyPeer4UserpicBg` (green) |
| NonContacts | "Non-Contacts" | `historyPeer7UserpicBg` (cyan) |
| Groups | "Groups" | `historyPeer2UserpicBg` (green) |
| Channels | "Channels" | `historyPeer1UserpicBg` (red) |
| Bots | "Bots" | `historyPeer6UserpicBg` (purple) |

Footer: "Choose chats and types of chats that will appear in this folder."

#### 18.6.3 Excluded Chats Section

Hidden when `chatlist` is true (shared folders can't have exclusions).

- Subtitle: "Excluded Chats"
- **Remove Chats button**: `settingsButtonActive`, `settingsIconRemove`
- Same preview widget

Exclude types:

| Flag | Name | Gradient color |
|---|---|---|
| NoMuted | "Muted" | `historyPeer6UserpicBg` (purple) |
| NoArchived | "Archived" | `historyPeer4UserpicBg` (green) |
| NoRead | "Read" | `historyPeer7UserpicBg` (cyan) |

Footer: "Choose chats and types of chats that will never appear in this folder."

#### 18.6.4 Tag Color Section (Premium)

Visible when Premium is possible.

- Subtitle: "Tag Color" with inline tag preview badge (14px offset from title end)
- **8 circular color buttons** evenly spaced: Colors 0–6 from `EmptyUserpic::UserpicColor(i).color2`, color 7 = "no tag" with X icon (`historyPeerArchiveUserpicBg`)
- Non-Premium: clicking opens `PremiumPreviewBox(FilterTags)`
- Selection animation: `universalDuration`, circle grows/shrinks, color crossfades

Footer: "Choose a color for the folder tag."

#### 18.6.5 Shareable Link Section

Title switches between "Share Folder" (no links) and "Invite Links" (has links).

**Create Link button**: `settingsButtonActive`, `settingsFolderShareIcon`. **Add Link button** (when links exist): `settingsIconAdd`.

**Link rows** (`inviteLinkList` style): Green circle userpic (`msgFile1Bg`) with `inviteLinkIcon`, link name/URL, "{N} chats" status, three-dots icon.

**Context menu**: Copy, Share, QR Code, Name it, Delete.

**Validation on create**: Filter must not have exclusions or rule flags (toast "Can't create links for this folder"). Only channels with invite permission are shareable.

#### 18.6.6 Validation on Save

1. Empty or >12 char title → `showError()`, scroll to top
2. No include types AND no chats → toast "The folder can't be empty"
3. All types + NoArchived, no specific chats → toast "This folder would include all your chats"

### 18.7 Include/Exclude Chats Picker

`PeerListBox` with `EditFilterChatsListController`. Title: "Include Chats" / "Exclude Chats". `closeByOutsideClick` = false.

**Chat type section**: Subtitle "Chat types" (semibold, `searchedBarFg`, height **28px**, background `searchedBarBg`). Type rows: 44px height, 34px gradient circle photo with white icon. Checkbox toggle.

**Include types**: NewChats, ExistingChats, Contacts, NonContacts, Groups, Channels, Bots.
**Exclude types**: NoMuted, NoRead, NoArchived.

**Chat rows**: Standard peer rows with folder membership status. Counter shows "{selected} / {limit}".

### 18.8 Filter Icon Picker Panel

Grid of 30 folder icons, cell size **44x42px** (`windowFilterIconSingle`), padding `margins(10, 36, 10, 8)`.

Icons include: Cat, Book, Money, Game, Light, Like, Note, Palette, Travel, Sport, Favorite, Study, Airplane, Private, Groups, All, Unread, Bots, Crown, Flower, Home, Love, Mask, Party, Trade, Work, Unmuted, Channels, Custom, Setup.

Normal color: `sideBarIconFg`. Active: `sideBarIconFgActive`.

**Auto-icon selection**: Contacts→Private, Groups→Groups, Channels→Channels, Bots→Bots, NoRead→Unread, NoMuted→Unmuted, mixed→Custom.

### 18.9 Show Link Box (Invite Link Detail)

`PeerListBox` with `LinkController`, style `inviteLinkChatList`.

**Header**: Lottie `"cloud_filters"` 74x74px, description with folder name in bold.

**Link block** (existing links): `InviteLinkLabel` with URL, Copy + Share buttons. Context menu: Copy, Share, QR Code, Name it, Delete.

**Chat list**: Subtitle with select/deselect toggle. Checked peers included in link. Disabled rows (bots, private users, non-admin channels) show status explaining why, with dashed circle overlay (1.5dp dash width, 11 segments, `windowSubTextFg`).

**Buttons**: "Save"/"Cancel" when changes exist (closeByEscape disabled), "Done" when unchanged.

### 18.10 Chatlist Folder Removal Dialog

`PeerListBox` in `filterInviteBox` style (button height 42px, `defaultActiveButton`). Shows channels from folder's always-list. Server-suggested peers to leave are pre-selected. Action button shows selected count badge.

### 18.11 Folder Tags Toggle (Premium)

- Text: "Show Folder Tags"
- Style: `settingsButtonNoIconLocked` with toggle
- Non-Premium: locked, clicking opens `PremiumPreviewBox(FilterTags)`
- Premium: toggling sends request with 500ms debounce
- Tag animation: all `FilterRowButton` color dots animate in/out via `universalDuration`

### 18.12 Tab View Section

Visible only when enough window width for sidebar.

Two radio options (`settingsCheckbox` style, `margins(22, 5, 10, 5)`):
1. "Side panel" — vertical sidebar tabs
2. "Top bar" — horizontal strip above chat list

### 18.13 Premium Limits

| Resource | Free | Premium |
|---|---|---|
| Total folders | 10 | 20 |
| Chats per folder | 100 | 200 |
| Shareable folders | 2 | 20 |
| Links per folder | 3 | 20 |

Limit boxes: `FiltersLimitBox`, `FilterChatsLimitBox`, `ShareableFiltersLimitBox`, `FilterLinksLimitBox` — all `SimpleLimitBox` with animated infographic, Premium icon, and description.

---

## 19. Settings — Sessions, Power Saving & Language

### 19.1 Active Sessions — Overview

Reached from **Privacy & Security > Active Sessions**. Displays every authorized login, grouped into: current session, terminate all, incomplete logins, other sessions, and auto-terminate timer. Searchable with keywords: "current", "device", "session", "terminate", "logout", "active", "auto", "inactive".

**Title:** "Active Sessions". **Icon in parent:** `menuIconDevices`. **Polling:** Auto-refreshes every 60 seconds. Loading state shows spinner with "Loading..." in `noContactsFont`/`noContactsColor`.

| Zone | Visibility |
|---|---|
| "This device" + current session | Always |
| "Terminate All Other Sessions" | incomplete + other > 0 |
| "Incomplete Login Attempts" | incomplete > 0 |
| "Active Sessions" list | other > 0 |
| "If Inactive For" auto-terminate | other > 0 |
| Empty placeholder | other == 0 |

### 19.2 Current Session Display

**Header:** "This device" with "Rename" link button on right (offset `sessionTerminateSkip` 11px + 12px from right edge).

**Row:** `sessionListItem` style:
- Height: 84px, photo 42px at (21px, 10px)
- Photo: gradient circle + platform icon
- Name: `msgNameFont` (13px semibold) at (78px, 11px)
- Status: at (78px, 32px), `boxTextFg`, shows app info
- Location: at y=54px, `normalFont` 13px, `sessionInfoFg` (`windowSubTextFg`). Format: "{location} · {active_date}"
- No terminate button for current session

### 19.3 Device Type Detection & Icons

Sessions classified by API ID first, then keyword detection in device/platform strings.

| Device Type | Gradient | List Icon | Lottie |
|---|---|---|---|
| Windows | `historyPeer4UserpicBg` (green) | `sessionIconWindows` | `device_desktop_win` |
| Mac | `historyPeer4UserpicBg` (green) | `sessionIconMac` | `device_desktop_mac` |
| Ubuntu | `historyPeer8UserpicBg` (orange) | `sessionIconUbuntu` | `device_linux_ubuntu` |
| Linux | `historyPeer5UserpicBg` (purple) | `sessionIconLinux` | `device_linux` |
| iPhone | `historyPeer7UserpicBg` (cyan) | `sessionIconiPhone` | `device_phone_ios` |
| iPad | `historyPeer7UserpicBg` (cyan) | `sessionIconiPad` | `device_tablet_ios` |
| Android | `historyPeer2UserpicBg` (red) | `sessionIconAndroid` | `device_phone_android` |
| Web | `historyPeer6UserpicBg` (pink) | `sessionIconWeb` | static `sessionBigIconWeb` |
| Chrome | `historyPeer6UserpicBg` (pink) | `sessionIconChrome` | `device_web_chrome` |
| Edge | `historyPeer6UserpicBg` (pink) | `sessionIconEdge` | `device_web_edge` |
| Firefox | `historyPeer6UserpicBg` (pink) | `sessionIconFirefox` | `device_web_firefox` |
| Safari | `historyPeer6UserpicBg` (pink) | `sessionIconSafari` | `device_web_safari` |
| Other | `historyPeer4UserpicBg` (green) | `sessionIconOther` | static `sessionBigIconOther` |

All icons use `historyPeerUserpicFg` (white), centered in vertical gradient circle.

### 19.4 Other Sessions List

Header: "Active sessions" with 14px top skip.

Each row: 84px height with terminate button on right — 34x34px hit area (`sessionTerminate`), `smallCloseIcon`, top offset 8px, right offset 11px.

Row click → `SessionInfoBox` (detail view). Terminate click → confirmation dialog.

Footer: explanatory divider text about apps.

### 19.5 Incomplete Login Attempts

Header: "Incomplete Login Attempts" (14px top skip). Same row style as other sessions. Sorted newest first.

Footer: explanation of incomplete logins.

### 19.6 Session Detail View (SessionInfoBox)

Width: 364px (`boxWideWidth`).

**Header:** Large userpic 70px (`sessionBigUserpicSize`) with gradient + Lottie 52px (`sessionBigLottieSize`). Padding `margins(0, 18, 0, 7)`. Lottie plays once on show.

**Device name:** 20px semibold, `boxTitleFg`, max height 29px.
**Date:** `windowSubTextFg`, full datetime, bottom margin 19px.

**Info rows** (each with icon at (20px, 9px), value at 61px left indent, caption in `windowSubTextFg`):

| Row | Icon |
|---|---|
| Application | `menuIconDevices` |
| System | `menuIconInfo` |
| IP Address | `menuIconIpAddress` |
| Location | `menuIconAddress` |

**Buttons:** "OK" (closes). For non-current sessions: "Terminate Session" (`attentionBoxButton`, red).

### 19.7 Terminate All Sessions

Button: "Terminate All Other Sessions" styled `infoBlockButton` with `infoIconBlock`. Visible when other sessions > 0.

Confirmation: "Are you sure?" with "Terminate" in `attentionBoxButton` (red).

### 19.8 Rename Device Dialog

Title: "Rename Device". Input: `settingsDeviceName` style (transparent bg, 29px min height), placeholder = device model name, max 32 characters. Buttons: "Save" + "Cancel".

### 19.9 Auto-Terminate Inactive Sessions

Button: "If Inactive For" with right label showing current value. `settingsButtonNoIcon` style.

Opens `SelfDestructionBox` (Sessions type) with radio buttons: 1 week, 1 month, 3 months, 6 months, 12 months. Width 320px, option spacing 20px. Buttons: "Save" + "Cancel".

### 19.10 Power Saving Settings

`GenericBox` dialog. Title: "Power Saving". Width: 364px.

### 19.11 Power Saving — Toggle Categories

All toggles use `powerSavingButton` style (padding 57/8/22/8, `iconLeft: 20px`). Checked = animation ON.

**Stickers** — header "Stickers":
- "Stickers in Panel" (`menuIconStickers`)
- "Stickers in Messages" (sub-item, no icon)

**Emoji** — header "Emoji":
- "Emoji in Panel" (`menuIconEmoji`)
- "Emoji Reactions" (sub-item)
- "Emoji in Messages" (sub-item)
- "Emoji Status" (sub-item)

**Chat** — header "Chat":
- "Chat Background" (`menuIconChatBubble`)
- "Spoiler Effect" (sub-item)
- "Message Effects" (sub-item)

**Calls** (standalone):
- "Calls" (`menuIconPhone`)

**Animations** (standalone):
- "Interface Animations" (`menuIconStartStream`)

Total: 11 flags.

### 19.12 Power Saving — Automatic Mode & Battery

Shown only when OS provides battery status.

- **"Automatic Power Saving"** toggle — `powerSavingButtonNoIcon` style (22/8/22/8 padding)
- When auto ON + battery saver active: overlay (`boxBg` at alpha 96/255) covers all toggles. Clicking shows toast "Turn off your device's power saving mode to change these settings" (3s duration).

Buttons: "Save" + "Cancel".

### 19.13 Language Selection (LanguageBox)

Title: "Language". Width: 320px. Max list height: 492px.

### 19.14 Translation Settings (Top Area)

Three toggles above the language list (logged-in only):

1. **"Show Translate Button"** — `settingsButtonNoIcon`, toggle
2. **"Translate Entire Chats"** — `settingsButtonNoIconLocked`, Premium-locked (AyuGram bypasses premium check)
3. **"Do Not Translate"** — `SlideWrap`, shown when either toggle above is ON. Right label: language name (if 1) or "{N} languages" (if multiple). Click opens skip-languages editor.

Divider text explains translation feature.

### 19.15 Language List

`MultiSelect` search field with placeholder "Search".

Two sections separated by `BoxContentDivider`:
1. **Recent languages** — previously used, current language sorted to top
2. **Official languages** — from cloud, de-duplicated against recent

**Empty state:** "No languages found" centered, styled `membersAbout`.

### 19.16 Language Row Layout

| Element | Style | Position |
|---|---|---|
| Radio button | `langsRadio` (22px diameter, `windowBgActive` when selected) | Left 22px, centered |
| Title (native name) | `semiboldTextStyle`, `windowFg` | Left 66px, top 8px |
| Description (English name) | `defaultTextStyle`, `windowSubTextFg` | Left 66px, below title + 2px |
| Menu toggle (3-dot) | `topBarMenuToggle` | Right side, centered |

Row hover: `windowBgOver`. Click: activates language. Menu toggle: opens context menu.

### 19.17 Language Row Context Menu

Non-official rows only. `dropdownMenuWithIcons` style:
- **Share** — copies `https://t.me/setlanguage/{id}` to clipboard (`menuIconShare`)
- **Delete** — marks removed, dims row (`menuIconDelete`)
- **Restore** — un-marks removed (`menuIconRestore`)

### 19.18 Styling Summary

| Token | Value | Usage |
|---|---|---|
| `sessionListItem` | height 84px, photo 42px at (21,10) | Session row |
| `sessionTerminate` | 34x34px, icon at (12,12) | Per-row terminate button |
| `sessionBigUserpicSize` | 70px | Detail view avatar |
| `sessionBigLottieSize` | 52px | Detail view lottie |
| `sessionBigName` | 20px semibold, max 29px | Detail view name |
| `sessionDateSkip` | 19px | Date bottom margin |
| `sessionValuePadding` | 37/5/0/0 | Info row indent |
| `powerSavingButton` | padding 57/8/22/8, iconLeft 20px | Power toggle with icon |
| `powerSavingButtonNoIcon` | padding 22/8/22/8 | Auto mode toggle |
| `langsRadio` | 22px diameter, `boxBg` bg | Language radio |
| `passportRowPadding` | 22/8/25/8 | Language row padding |
| `boxMaxListHeight` | 492px | Language list max height |

---

## 20. Media Viewer / Lightbox

The media viewer is a full-screen (or windowed) overlay that displays photos, videos, documents, theme previews, stories, and group call video streams. ~7800 lines of code with optional OpenGL-accelerated rendering.

### 20.1 Window Modes and Geometry

Three window states (saved to `settings.mediaViewPosition.maximized`: 0=windowed, 1=maximized, 2=fullscreen):

- **Full-screen** (default): covers entire screen. On macOS, uses `Qt::Tool | Qt::FramelessWindowHint`.
- **Maximized**: `showMaximized()`.
- **Windowed**: restores persisted `_normalGeometry`.

Minimum: **480x360px** (`mediaviewMinWidth/MinHeight`). Default windowed: 800x600 at (160, 120).

Title bar buttons: 44x32px each (`mediaviewTitleButton`). Title bar height: 32px. Title text: "Media viewer" (`mediaviewTitle` style).

### 20.2 Background and Shadows

Background: `mediaviewBg` (opaque dark, near-black). Two gradient shadow overlays at top and bottom, rendered at `_controlsOpacity` (0.0–1.0).

### 20.3 Content Display

Media centered in available area. Content types:
- **Photo**: progressive loading (thumbnailInline → Small → Thumbnail → Large)
- **Video/GIF**: `Streaming::Instance` provides frames
- **Document bubble**: `mediaviewFileBg`, 340x116px (`mediaviewFileSize`), icon area 80x80px with file info
- **Theme preview**: 903x584px (`themePreviewSize`) with Apply/Cancel/Share buttons

### 20.4 Zoom and Pan

Zoom range: -7 (1/8x) to +7 (8x). Special `kZoomToScreenLevel` (1024) = fit-to-screen.

**Controls:**
- `Ctrl+`/`Ctrl-`: zoom in/out
- `Ctrl+0`: toggle between 1:1 and fit-to-screen
- Middle mouse: zoom reset
- Mouse wheel + Ctrl: zoom per step
- Mouse wheel (no modifier): navigate prev/next

**Pan**: When zoomed in, left-click-drag pans. Cursor: `cur_sizeall`. Snapped to bounds.

Zoom transitions animate with `_geometryAnimation` using `widgetFadeDuration`.

### 20.5 Rotation and Flip

Rotation: 0/90/180/270 degrees, each click subtracts 90°. Rotate button in bottom-right toolbar. Animates on OpenGL renderer.

Flip: `H` key = horizontal, `V` key = vertical (photo only, not stories).

### 20.6 Navigation Controls

Two side areas for prev/next:

| Property | Normal | Stories |
|---|---|---|
| Width | 90px (`mediaviewControlSize`) | 64px (`storiesControlSize`) |
| Icons | `mediaview/next` (flipped for left) | `stories/next` |
| Hover | 36px circle (`mediaviewIconOver`) | none |

**Keyboard**: Left/Right arrows. **Mouse wheel** (non-stories): scroll = navigate. **Touch/swipe**: 80px threshold (`mediaviewSwipeDistance`).

**Preloading**: 3 items ahead, 48 IDs loaded in each direction.

### 20.7 Footer / Header Area

Bottom-left, painted at `_controlsOpacity`:

1. **Header**: "Photo N of M" or filename. `mediaviewThickFont` (semibold), position (14px, height - 47px). Max width: width/3, middle-elided. Clickable → opens media overview.
2. **Sender name**: `mediaviewFont` (normal), position (14px, height - 26px). Clickable → peer info.
3. **Separator**: bullet `•` with 5px spacing each side.
4. **Date**: formatted datetime + DC number. Clickable → navigate to message in chat.

Color: `mediaviewControlFg`.

### 20.8 Bottom-Right Toolbar

Icons right-to-left in 46x54px cells (`mediaviewIconSize`). Hover: 36px circle.

| # | Control | Icon | Condition |
|---|---|---|---|
| 1 | More/menu | `title_menu_dots` | always |
| 2 | Rotate | `mediaview/rotate` | not stories/theme |
| 3 | Share | `mediaview/viewer_share` | stories + shareable |
| 4 | Save | `mediaview/download` | loaded content |
| 5 | Draw | `mediaview/draw` | photo/image doc |
| 6 | OCR | `mediaview/recognize` | OCR results available |

Hover fade: 150ms (`mediaviewFadeDuration`), `anim::linear`.

### 20.9 Caption Display

- **Background**: `mediaviewCaptionBg`, radius 6px (`mediaviewCaptionRadius`). No background in stories.
- **Padding**: 11/6/11/6px (`mediaviewCaptionPadding`)
- **Text**: `mediaviewCaptionStyle`, color `mediaviewCaptionFg`, links `mediaviewTextLinkFg`
- **Max height**: 1/4 of `_maxUsedHeight`. Stories: collapsed to `kCollapsedCaptionLines` with "Show more".
- **Position**: bottom-aligned above playback controls, centered, 11px margin.
- Spoiler support and timestamp links (clickable → seek video, generate chapter marks on progress bar).

### 20.10 Video Playback Controls

Rounded-rect panel, `mediaviewSaveMsgBg` background. Max width 480px, height 72px (`mediaviewControllerSize`) + optional 10px timestamp label. Centered horizontally.

| Element | Size | Details |
|---|---|---|
| Volume toggle | 32x32px | Icons: `player_volume_off/_small/_on` |
| Volume slider | 75px wide | `mediaviewPlayback` style |
| Time played | 12px semibold | `mediaviewPlaybackProgressFg` |
| Progress bar | fills remaining | 3px track, 12px seek handle |
| Time remaining | auto | Prefixed with minus sign |
| Play/Pause | 40x40px, centered | `player_play_big` / `player_pause_big` |
| Settings (speed) | 32x32px | Shows speed value or quality |
| PiP | 32x32px | `player_pip` |
| Fullscreen | 32x32px | `player_fullscreen` / `player_minimize` |

**Progress bar**: Active color `mediaviewPlaybackActive`, inactive `mediaviewPlaybackInactive`, buffer `mediaviewPlaybackInactiveOver`. Chapter dividers: 2x10px marks.

**Fade**: controls in 200ms (`mediaviewShowDuration`), out 600ms (`mediaviewHideDuration`).

### 20.11 Video Player Behavior

- **Play/Pause**: Space, Enter, or click video area
- **Seek**: drag progress bar, Left/Right ±5s in fullscreen, 0–9 keys jump to 0%–90%, Alt+Left/Right for chapters
- **Speed**: 0.5x–3.0x, saved to settings
- **Quality**: menu lists heights (360/720/1080), seamless switch preserving position
- **Volume**: 0.0–1.0, toggle mutes/restores (default 0.8)
- **Loop**: animations loop, sound videos don't
- **Auto-pause on call**: pauses during Telegram calls

### 20.12 Full-Screen Video Mode

Toggled by: double-click, Alt+Enter, Ctrl+Enter, Ctrl+F, or fullscreen button. Content fills screen, overlay controls hidden (only playback controls remain). Auto-hide after 1100ms (`mediaviewWaitHide`) with blank cursor. Escape exits fullscreen (doesn't close viewer).

### 20.13 Picture-in-Picture (PiP)

Floating always-on-top window. Default 320px (`pipDefaultSize`), minimum 120px (`pipMinimalSize`). Resize area 10px edges. Own play/pause, close, enlarge, volume controls. Playback track: 2px default, 4px hover. Geometry persisted. Closing returns to full overlay at same position.

### 20.14 Gallery / Group Thumbs Strip

Horizontal thumbnails at bottom for shared media / multi-photo messages:
- Width: 56px (`mediaviewGroupWidth`) to 160px (`mediaviewGroupWidthMax`), height 80px (`mediaviewGroupHeight`)
- Padding: 0/14/0/14px, skip 3px between, 12px for current item
- Click navigates, active highlighted, items animate in/out

### 20.15 Save/Download Toast

Centered toast: `mediaviewSaveMsgBg` background, check icon at (23, 21)px, padding 55/19/29/20px. Text: 16px (`mediaviewSaveMsgStyle`), color `mediaviewSaveMsgFg`. Animation: fade in 200ms, hold 2s, fade out 2.5s. Clickable "Downloads" link.

### 20.16 Context Menu

Right-click opens dark-themed popup (`groupCallMenuBg` background, `groupCallMembersFg` text):

Items include: Cancel download, Show in Chat, Show in Folder, Copy/Copy Frame, Forward, Share at Time, Delete, Save As, All Photos/Files, Set as Userpic, Report, Stealth Mode (stories).

### 20.17 Stories Viewer Integration

Delegates to `Stories::View`. Content: aspect-fit within 540x960px (`storiesMaxSize`) with 8px radius. Sibling story previews shown as thumbnails. Controls always visible. No zoom/rotation. Collapsed captions with "Show more".

### 20.18 Keyboard Shortcuts

| Key | Action |
|---|---|
| Escape | Close (or exit fullscreen video) |
| Space | Play/pause (video) / Toggle pause (stories) |
| Left/Right | Previous/next media (or seek ±5s in fullscreen video) |
| Alt+Left/Right | Jump to prev/next chapter |
| 0–9 | Jump to 0%–90% (fullscreen video) |
| Ctrl+F / Alt+Enter | Toggle fullscreen video |
| Ctrl+/- | Zoom in/out |
| Ctrl+0 | Zoom reset |
| Ctrl+S | Save as |
| Ctrl+C | Copy media/frame |
| H / V | Flip horizontal/vertical (photo only) |

### 20.19 Animations Summary

- **Controls auto-hide**: 1100ms idle → 600ms fade out. Mouse activity → 200ms fade in. Blank cursor when hidden.
- **Icon hover**: 150ms per-icon fade (`mediaviewFadeDuration`)
- **Between-media**: `_geometryAnimation` interpolates rect + rotation over `widgetFadeDuration`
- **Radial loading**: spinning arc in `radialSize` circle, `radialBg`/`radialFg` colors
- **Save toast**: 200ms in, 2s hold, 2.5s out

---

## 21. Create Group / Channel Wizard

### 21.1 Overview and Entry Points

Multi-step layered-box flow from hamburger menu ("New Group" / "New Channel"). Both share `GroupInfoBox`, diverge by type. All boxes use **364px** width (`boxWideWidth`).

| Type | Description field | Post-create step |
|------|-------------------|------------------|
| Group | No | Member picker |
| Channel | Yes | SetupChannelBox → member picker |
| Megagroup | Yes | SetupChannelBox (forced public) |
| Forum | Yes | SetupChannelBox → member picker |

### 21.2 Step 1 — Group/Channel Info Box

Title bar: 48px height, 16px semibold font.

**Userpic button**: 72x72px, position (24px left, 10px top). Role: ChoosePhoto. Change icon at (21, 23)px. Upload overlay: 24px height, `msgDateImgBgOver`. Progress: 3px line, 8px margin, 500ms animation.

**Title input**: Position left 99px (72px userpic + 27px gap), top 5px. Width ~217px. Max 128 characters. Emoji suggestions enabled.

**Description** (channels only): `MultiLine`, max 255 chars, max height 116px. Top margin 13px below userpic. Width ~316px.

**TTL menu** (groups only): Top-bar menu button, "Auto-delete messages" with current TTL value.

**Buttons**: "Create" (channels) or "Next" (groups) + "Cancel".

**Submit**: Empty title → focus + shake. Channels → `CreateChannel` API → SetupChannelBox. Groups → opens member picker.

**Errors**: NO_CHAT_TITLE → shake title. USERS_TOO_FEW → privacy info. CHANNELS_TOO_MUCH → premium limit box.

### 21.3 Step 2a — Member Picker

`PeerListBox` with `MultiSelect` search/chips bar.

**MultiSelect bar**: Background `boxSearchBg`, padding 8px, max height 104px.

**Chips**: 32px height, max 128px width. Background: `contactsBgOver` (normal), `activeButtonBg` (active). Delete cross: 32px, 1.5px stroke, 150ms animation. Spacing: 8px.

**Search field**: Transparent bg, 32px min height, search icon at (10, 9)px.

**Contact rows**: 56px height, 42px avatar at (16, 7), name at (74, 9) semibold, status at (74, 30). Avatar acts as checkbox — checked shows round check overlay with `windowActiveTextFg` tint.

**"Invite via Link" button**: Above contact list if `canHaveInviteLink()`.

**Counter**: "42 / 200000" in title bar.

**Buttons**: "Create" + "Cancel" (new group) or "Invite" + "Skip" (post-channel).

### 21.4 Step 2b — Channel Setup Box

Public/private choice + username assignment. Width 364px.

**Privacy radios**: Public ("Anyone can find and join") / Private ("Only via invite link"). Style: `defaultBoxCheckbox`. Skip between: 27px. About text: `windowSubTextFg`.

**Username field** (when public): `t.me/` prefix, `setupChannelLink` style (32px min height). Validation after 200ms debounce:
- Too short (<5) → red error
- Bad symbols → red error
- Available → green "This link is available"
- Occupied → red "Already taken"

Username: min 5, max 32 characters, `[A-Za-z0-9_]` only.

**Invite link** (when private): Clickable text, copies to clipboard with toast.

**Too many public usernames**: Auto-switches to private. Trying to go public shows `PublicLinksLimitBox` (premium upsell with revoke list).

**Buttons**: "Save" + "Skip"/"Cancel".

### 21.5 Edit Peer Type Box

For editing existing group/channel type. Width 364px.

**Privacy radios**: `editPeerPrivacyBoxCheckbox` style with `margins(0, 8, 0, 8)`. Explanation labels: `minWidth: 220px`, `windowSubTextFg`. Label margins: `margins(42, 0, 34, 0)`. Bottom skip: 16px.

**Username section** (public): Draggable usernames list for collectible usernames. Validation same as SetupChannelBox.

**Invite link section** (private): Permanent link block with copy/share.

**Additional toggles** (megagroups): "Only Members" send toggle, "Approve New Members" nested toggle, "Restrict Saving Content" toggle.

### 21.6 Complete Flow Sequences

**Create Group**: Menu → GroupInfoBox (name/photo/TTL) → "Next" → Member Picker → "Create" → API → navigate to chat.

**Create Channel**: Menu → GroupInfoBox (name/description/photo) → "Create" → API → SetupChannelBox (public/private + username) → "Save"/"Skip" → Member Picker → "Invite"/"Skip" → navigate to channel.

### 21.7 Style Reference

| Token | Value | Usage |
|-------|-------|-------|
| `boxWideWidth` | 364px | All wizard boxes |
| `boxPadding` | margins(24, 14, 24, 8) | Box content |
| `boxTitleHeight` | 48px | Title bar |
| `newGroupPadding` | margins(4, 6, 4, 3) | Radio area |
| `newGroupSkip` | 27px | Between radios |
| `newGroupInfoPadding` | margins(0, -4, 0, 1) | Photo/title area |
| `newGroupNamePosition` | point(27, 5) | Title offset from userpic |
| `newGroupLinkPadding` | margins(4, 27, 4, 21) | Username field area |
| `setupChannelLink` | textMargins(0,6,0,4), heightMin 32 | Username input |
| `defaultUserpicButton.size` | 72x72px | Photo picker |
| `peerListBoxItem.height` | 56px | Member row height |
| `contactsPhotoSize` | 42px | Member avatar |
| `defaultMultiSelect.maxHeight` | 104px | Chips bar |
| `defaultMultiSelectItem.height` | 32px | Chip height |
| `kMaxGroupChannelTitle` | 128 | Title limit |
| `kMaxChannelDescription` | 255 | Description limit |
| `kMinUsernameLength` | 5 | Username min |
| `kMaxUsernameLength` | 32 | Username max |

---

## 22. Forum Topics UI

Forums are supergroups with the "Forum" flag enabled. When opened, a topic list replaces the normal message history. Each topic is a named thread with its own icon, message history, pinned state, and unread tracking.

### 22.1 Topic Data Model

Each `ForumTopic` has: rootId (MsgId, General = 1), title, colorId (one of 6), iconId (custom emoji or 0 for default), creatorId, creationDate, closed/hidden/my flags, unread state.

Capabilities: `canEdit()` (my or canManageTopics), `canDelete()` (not General, canDeleteMessages or my), `canToggleClosed()` (canEdit, not bot forum), `canTogglePinned()` (canManageTopics).

### 22.2 Topic Icon System

#### Predefined Colors

| Color ID | Name | Visual |
|----------|------|--------|
| `0x6FB9F0` | blue | Light blue |
| `0xFFD67E` | yellow | Gold |
| `0xCB86DB` | violet | Purple |
| `0x8EEE98` | green | Green |
| `0xFF93B2` | rose | Pink |
| `0xFB6F5F` | red | Red/orange |

SVG files at `:/gui/topic_icons/{name}.svg`.

#### Default Icon Rendering

Colored circle + first non-emoji letter from title, centered in white.

| Token | Size | Font | TextTop |
|-------|------|------|---------|
| `defaultForumTopicIcon` | 21px | bold 11px | 2px |
| `normalForumTopicIcon` | 19px | bold 10px | 2px |
| `largeForumTopicIcon` | 26px | bold 13px | 3px |
| `infoForumTopicIcon` | 32px | bold 15px | 4px |

#### General Topic Icon

Special `general.svg`, colorized from theme palette (`dialogsTextFg` normal, `dialogsTextFgOver` hover, `dialogsTextFgActive` active). Re-rendered on palette changes.

#### Custom Emoji Icon

When `iconId != 0`: loaded via `CustomEmojiManager`, loops once then freezes.

### 22.3 Forum Topic List Layout

When a forum group is opened, the chat list column shows the topic list.

#### Topic Row Style (`forumTopicRow`)

```
height: 54px          (vs 62px normal dialogs)
padding: 8/7/10/7px
photoSize: 20px       (small icon vs 46px avatar)
nameLeft: 39px
nameTop: 7px
textLeft: 39px
textTop: 29px
unreadMarkDiameter: 8px
```

Each row paints: topic icon (left), name (semibold), closed lock icon (if closed), date (top-right), message preview, unread badges (bottom-right), pin icon (if pinned, no unreads).

### 22.4 Forum Group in Main Chat List

Forum groups use an expanded row:

```
forumDialogRow height: 80px     (with tags: 96px)
topicsSkip: 8px
topicsSkipBig: 14px
topicsHeight: 21px
```

**Topic Names Row**: `TopicsView` renders up to 8 recent topic names horizontally. Unread topics in bold. Drawing stops when width exhausted.

**Topic Jump Bubble**: When an unread front topic exists, a rounded bubble (radius 11px, padding 8/3/8/3px) with arrow icon appears. Click navigates directly to that topic. Two-rect stepped outline when spanning multiple lines.

**Expanded Bar**: Left-edge animated bar (`dialogsBgActive`, `roundRadiusLarge`) when forum's topic list is shown as child.

### 22.5 Create / Edit Topic Dialog

`EditForumTopicBox` — `GenericBox`, max height 408px.

#### Structure

1. **Title input**: `defaultInputField`, margin 70/2/22/18px (70px left for icon). Placeholder "Topic Name".
2. **Icon button** at (24px, 19px): Shows custom emoji or default circle at 26px. Click cycles to random next color.
3. **Divider text**: "Choose a title and an icon for the topic".
4. **Icon selector panel**: `EmojiListWidget` in `Mode::TopicIcon`. Recent section shows default icon + server emoji set. Non-default custom emoji require Premium.
5. **Fly animation**: `EmojiFlyAnimation` from selector to icon button on selection.

**Auto-title reactivity**: As user types, icon button re-renders with new first letter.

**Create**: Validates non-empty title, reserves local ID, navigates to topic.
**Save**: Calls `EditForumTopic` API. General topic cannot change icon.

### 22.6 Topic Header Bar

Standard `info_top_bar` with: back button (→ topic list), title with icon prefix, optional subtitle. Height: 54px. Selection mode shows cancel + count + forward/delete.

### 22.7 Topic Info Panel

Third column (or full-screen push in one-column).

**Cover** (`infoTopicCover`): height 77px, icon 36x36px at (22, 18), name at (79, 14), status at (79, 38). General icon: `windowSubTextFg`. Custom emoji: loaded at cover size. Default: 32px circle with bold 15px letter.

Sections: Notifications toggle, shared media, members list, topic link.

### 22.8 Topic Context Menus

**Topic list right-click**: Create Topic, View Group Info, View as Messages, Search (if >1 topic), Manage Group, Add Members, Video Chat, Report, Leave/Join.

**Specific topic row**: New Window, Pin/Unpin, View Info, Mute submenu, Mark Read/Unread, Close/Reopen, Add to Folder, Clear History, Delete Topic (red attention).

**Inside topic (burger)**: Mute, Create Topic, Topic/Group Info, View as Topics, Manage Group, standard items.

**Topic info panel**: TTL, Copy Topic Link, Edit Topic, Close/Reopen, standard profile items, Delete Topic.

### 22.9 General Topic

rootId = 1. Cannot be deleted. Cannot change icon (uses `general.svg`). Can be hidden. Title prefixed with "# " in rich text.

### 22.10 Navigation & Column Integration

**One-column**: Forum replaces dialog list, back button returns to main chat list.
**Two/three-column**: Topic list replaces dialog column, topics open in chat column, info in third column.

**View as Messages/Topics toggle**: Saves preference, switches between flat messages and topic list.

**Loading**: First load 20 topics, subsequent 500/page, stale refresh 100/request. Auto-preload when <20 topics loaded. Recent topics for chat list: 8.

### 22.11 Animations

- **Userpic loop reset**: After `slideDuration`, custom emoji icons stop and free memory
- **Topic jump ripple**: Standard `dialogsRipple` on jump bubble
- **Expanded bar**: 0.0–1.0 float drives left-edge bar animation
- **Icon fly**: `EmojiFlyAnimation` in edit dialog
- **Highlight**: Info top bar fade between `bg` and `highlightBg`

### 22.12 Pixel Dimensions Summary

| Element | Value |
|---------|-------|
| Topic row height | 54px |
| Topic row icon | 20px |
| Topic row padding | 8/7/10/7px |
| Topic row name | left 39px, top 7px |
| Topic row text | left 39px, top 29px |
| Forum dialog row | 80px (96px with tags) |
| Topics preview height | 21px |
| Jump bubble radius | 11px |
| Jump bubble padding | 8/3/8/3px |
| Edit dialog icon position | (24px, 19px) |
| Edit dialog title margin | 70/2/22/18px |
| Edit dialog max height | 408px |
| Info cover height | 77px |
| Info cover icon | 36x36px at (22, 18) |
| Info top bar height | 54px |
