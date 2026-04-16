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

---

## 23. Scheduled Messages

Scheduled messages allow users to compose a message and defer its delivery to a future date/time. Messages scheduled to "Saved Messages" (self-chat) become "Reminders." A special "Send when online" option is available for 1:1 user chats. Scheduled messages live in a dedicated section view per chat, accessible from a toggle button in the compose area or from the top-bar menu.

Source: `history/view/history_view_schedule_box.cpp`, `history/view/history_view_scheduled_section.cpp`, `data/components/scheduled_messages.cpp`, `history/view/history_view_context_menu.cpp`, `ui/boxes/choose_date_time.cpp`, `menu/menu_send.h`.

### 23.1 Data Model

Each chat maintains a `ScheduledMessages` list keyed by `History*`. Items use a remapped ID space: server-side scheduled message IDs are offset by `ServerMaxMsgId + 1` to create local IDs in the range `(ServerMaxMsgId, ScheduledMaxMsgId)`. The predicate `IsScheduledMsgId(id)` checks this range.

**Key constants:**
- `kScheduledUntilOnlineTimestamp = 0x7FFFFFFE` -- magic timestamp meaning "send when recipient comes online."
- `kMinimalSchedule = 10` seconds -- minimum scheduling offset from current time.
- `kRequestTimeLimit = 60000` ms -- cooldown between re-fetching scheduled list from server.
- Maximum scheduling horizon: 1 year from current date.

**Item properties:**
- `isScheduled()` -- true for all items in the scheduled ID range.
- `allowsSendNow()` -- true if scheduled, not sending, not failed, not editing media, not a paid post, not a service message.
- `allowsReschedule()` -- `allowsSendNow() && !awaitingVideoProcessing()`.
- `scheduleRepeatPeriod()` -- repeat interval in seconds (0 = no repeat, Premium feature).
- `isSilent()` -- scheduled messages can also be silent (Ctrl held when confirming schedule).

**SendMenu::Type enum** controls schedule dialog behavior:
- `Scheduled` -- generic scheduling (groups, channels).
- `ScheduledToUser` -- 1:1 user chat; adds "Send when online" option.
- `Reminder` -- self-chat; title changes to "Set a reminder."
- `SilentOnly` -- used for child menus within the schedule box itself.

**CanScheduleUntilOnline(peer):** Returns true only for non-self, non-bot users whose last-seen is not hidden and who do not have stars-per-message or notifications-user status.

### 23.2 Schedule Picker Dialog (ChooseDateTimeBox)

Opened via `PrepareScheduleBox()`. A `GenericBox` with width `boxWideWidth` (364px).

#### Layout

The box has a fixed-height content row (`scheduleHeight = 95px`) containing three inline elements centered horizontally:

| Element | Style token | Width | Vertical position |
|---------|-------------|-------|--------------------|
| Date field | `scheduleDateField` | `scheduleDateWidth = 136px` | `scheduleDateTop = 38px` |
| "at" label | `scheduleAtLabel` | natural width | `scheduleAtTop = 42px` |
| Time field | `scheduleTimeField` | `scheduleTimeWidth = 72px` | `scheduleDateTop = 38px` |

Spacing between elements: `scheduleAtSkip = 24px` on each side of the "at" label.

The three elements are centered as a group: `paddings = contentWidth - atWidth - 2*scheduleAtSkip - scheduleDateWidth - scheduleTimeWidth`, then `left = paddings / 2`.

#### Date Field

`InputField` styled with `scheduleDateField`: `textMargins: 2/0/2/0px`, `placeholderScale: 0`, `heightMin: 30px`, `textAlign: top`. Displays formatted date string: "Month Day" (current year) or "Month Day, Year" (other years).

**Interaction:** Clicking the date field opens a `CalendarBox` overlay. Scrolling the mouse wheel over the date field increments/decrements the date by one day, clamped to `[minDate, maxDate]`. After selecting a date from the calendar or changing via wheel, focus moves to the time field.

#### Time Field

`TimeInput` styled with `scheduleTimeField`: `border: 0`, `borderActive: 0`, `heightMin: 28px`, `placeholderFont: 14px`. Displays `HH:MM` format. Separator between hours and minutes: `scheduleTimeSeparator` (14px font) with `scheduleTimeSeparatorPadding: 2/0/2/0px`.

**Validation:** On submit (Enter key), the time is validated against `[min, max]` range. Invalid time triggers `showError()` animation on the time input.

#### Title

- Normal chats: `tr::lng_schedule_title` ("Schedule message")
- Self-chat: `tr::lng_remind_title` ("Set a reminder")

#### Submit Button

Label: `tr::lng_schedule_button` ("Schedule"). Pressing the button or Enter in the time field collects the datetime, validates range, and invokes the callback.

**Silent shortcut:** Holding Ctrl when confirming schedules the message silently (no notification on delivery).

#### Default Schedule Time

`DefaultScheduleTime() = now + 600` seconds (10 minutes from current time).

#### "Send when online" Button

Only shown when `SendMenu::Type == ScheduledToUser`. A top-right `IconButton` styled as `infoTopBarMenu`. Clicking it opens a `PopupMenu` (styled `popupMenuWithIcons`) with a single action: `tr::lng_scheduled_send_until_online` ("Send when online"), icon `menuIconWhenOnline`. Selecting it submits with `scheduled = kScheduledUntilOnlineTimestamp`.

#### Repeat Period (Premium)

Below the date/time row, a `ChooseRepeatPeriod` widget is shown. Displays a flat label: "Repeat: {period}" with a clickable dropdown arrow (or lock icon for non-Premium users).

**Available periods:**

| Period (seconds) | Label |
|-------------------|-------|
| 0 | Never |
| 86400 (1d) | Daily |
| 604800 (7d) | Weekly |
| 1209600 (14d) | Every 2 weeks |
| 2592000 (30d) | Monthly |
| 7862400 (91d) | Every 3 months |
| 15724800 (182d) | Every 6 months |
| 31536000 (365d) | Yearly |

In test mode, additional entries: "Every minute" (60s), "Every 5 minutes" (300s).

Non-Premium users see a lock icon (`scheduleRepeatDropdownLock`: premium_lock icon, `windowActiveTextFg`, padding -2/1/0/0px) and clicking opens a Premium promo toast. Premium users see a dropdown arrow (`scheduleRepeatDropdownArrow`: intro_country_dropdown icon, `windowActiveTextFg`, padding 3/6/3/0px).

### 23.3 Scheduled Messages Toggle Button

A clock icon button appears in the compose area when the current chat has scheduled messages (count > 0) and the user can send messages.

**Style:** `historyScheduledToggle`, inherits from `historyAttach` (44x46px `IconButton`, ripple area 40px at offset 2/3px). Uses a two-layer icon:
- `chat/input_scheduled` in `historyComposeIconFg` (normal) / `historyComposeIconFgOver` (hover).
- `chat/input_scheduled_dot` in `attentionButtonFg` (red attention dot, always visible).

**Position:** Right side of compose area, to the right of the silent toggle. Buttons are laid out right-to-left: send -> emoji -> bot_command -> silent -> **scheduled** -> TTL.

**Behavior:** Click opens the `ScheduledWidget` section (replaces the current chat view with a horizontal slide transition).

**Accessibility:** `tr::lng_scheduled_messages` ("Scheduled messages").

**Lifecycle:** Created dynamically when `scheduledMessages().count(history) > 0`, destroyed when count drops to 0. Visibility updates on `scheduledMessages().updates(history)` stream.

### 23.4 Scheduled Messages Section (ScheduledWidget)

A full `SectionWidget` that replaces the main chat column. Inherits `WindowListDelegate` and `CornerButtonsDelegate`.

#### Top Bar

Displays the section title instead of peer name:
- Self-chat: `tr::lng_reminder_messages` ("Reminders")
- Other chats: `tr::lng_scheduled_messages` ("Scheduled messages")

Rendered in `st::historySavedFont`, color `dialogsNameFg`, vertically centered in the top bar. No status line, no online indicator.

**Selection mode:** When messages are selected, the top bar shows a selection action bar with:
- **Send Now** button (`tr::lng_selected_send_now`, `defaultActiveButton` style, transforms to uppercase). Visible when `canSendNowCount == selectedCount`.
- **Delete** button. Visible when `canDeleteCount > 0`.
- **Clear selection** (x) button.

Buttons have `topBarActionSkip` spacing. The bar appears with the standard selection animation.

**Menu button:** In scheduled section, the top-bar "..." menu only offers "Create Poll" and "Create To-do List" actions.

#### Message List

Standard `ListWidget` with `ScrollArea`. Messages sorted by `position` (chronological by scheduled date). The list is flat (no unread bars, no read tracking).

**Empty state:** When no scheduled messages exist, an `EmptyListBubbleWidget` is shown as a service-style bubble with `msgServicePadding`, displaying: `tr::lng_scheduled_messages_empty` in semibold.

**Date separators:** Rendered as service-message date badges. For scheduled items:
- Normal: `tr::lng_scheduled_date` ("Scheduled for {date}"), where `{date}` is `langDayOfMonthFull`.
- Until-online: `tr::lng_scheduled_date_until_online` ("Scheduled until online").

**New message highlight:** When a new scheduled message is added (slice grows by exactly 1), the list auto-scrolls to show it at the insertion position.

#### Compose Controls

Full `ComposeControls` in `Mode::Scheduled`. Supports text input, stickers, GIFs, inline bots, file attachments, voice messages, and forwarding. Every send action opens the schedule picker dialog before actually sending (messages sent from the scheduled view are always re-scheduled, not sent immediately).

**Drag & drop:** File drag-and-drop is supported. Drop zones: "Photo" (compress) and "Document" (as-is). Only available when not recording voice.

#### Corner Buttons

Only the "scroll to bottom" button is available (`CornerButtonType::Down`). No unread counter button. Shown when scroll position is above `historyToDownShownAfter` pixels from bottom, or when a reply-return target exists.

#### Section Transition

- **Enter:** Horizontal slide from right (`SectionSlideParams`). Top bar hides controls during animation (`setAnimatingMode`), top bar shadow conditionally shown. Compose controls call `showStarted()` during animation, `showFinished()` after.
- **Exit:** `showBackFromStack()` slides back left. Escape key navigates back (after canceling selection or compose state).
- **Grab for animation:** `Ui::GrabWidget` captures the full widget including top bar and compose area.

### 23.5 Message Rendering in Scheduled View

Scheduled messages render with the same bubble styles as regular messages but with modified metadata.

#### Timestamp Display

The bottom-info area shows the scheduled delivery time (formatted as `HH:MM`). When a repeat period is set, the period label is prepended:

| Repeat period | Display prefix |
|---------------|----------------|
| Daily | "daily" |
| Weekly | "weekly" |
| Every 2 weeks | "biweekly" |
| Monthly | "monthly" |
| Every 3 months | "every 3 months" |
| Every 6 months | "every 6 months" |
| Yearly | "yearly" |

For messages awaiting video processing, the prefix is `tr::lng_approximate` instead.

#### Silent Indicator

If a scheduled message is also silent (`isSilent() && isScheduled()`), a muted bell emoji (U+1F515) is appended to the tooltip date text on a new line.

#### Tooltip (hover over timestamp)

Shows full datetime string plus message ID on a separate line. Silent messages add the muted-bell emoji.

#### Selection

Multi-select is allowed (`listAllowsMultiSelect = true`). Items are selectable only if not currently sending and not failed (`!isSending() && !hasFailed()`). Selection state feeds into the top bar's Send Now / Delete buttons.

### 23.6 Context Menu Actions

Right-click on a scheduled message shows the standard context menu with these scheduled-specific actions:

#### Send Now (single message)

- **Condition:** `item->allowsSendNow()` is true, no multi-selection active.
- **Grouped messages:** If right-clicking a group part, all items in the group must allow send-now.
- **Label:** `tr::lng_context_send_now_msg` ("Send now")
- **Icon:** `menuIconSend`
- **Action:** Opens `ShowSendNowMessagesBox` confirmation dialog.

#### Send Now (selected)

- **Condition:** Multi-selection active, all selected items have `canSendNow`.
- **Label:** `tr::lng_context_send_now_selected` ("Send now selected")
- **Icon:** `menuIconSend`
- **Action:** Confirmation dialog, then navigates back from scheduled section.

#### Send Now Confirmation Dialog

- Single message: `tr::lng_scheduled_send_now` ("Send this message now?")
- Multiple: `tr::lng_scheduled_send_now_many` ("Send {count} messages now?")
- On confirm: calls `MTPmessages_SendScheduledMessages` with sorted message IDs. Messages are sorted by date before sending.

#### Reschedule (single)

- **Condition:** `HasEditMessageAction(request)` and `item->allowsReschedule()` (i.e., allows send-now AND not awaiting video processing).
- **Label:** `tr::lng_context_reschedule` ("Reschedule")
- **Icon:** `menuIconReschedule`

#### Reschedule (selected)

- **Condition:** Multi-selection active, not single-good, all selected items have `canReschedule`, selection size <= `kRescheduleLimit = 20`.
- **Label:** `tr::lng_context_reschedule_selected` ("Reschedule selected")
- **Icon:** `menuIconReschedule`

#### Reschedule Action

Opens the schedule picker dialog with:
- Pre-filled date: the item's current scheduled date (or `DefaultScheduleTime()` if until-online).
- Pre-filled repeat period: the item's current `scheduleRepeatPeriod`.
- `SendMenu::Type` determined by peer: `Reminder` for self, `ScheduledToUser` for eligible users, `Disabled` otherwise (or `SilentOnly` for stars-per-message peers).

When rescheduling multiple messages, each subsequent message gets `options.scheduled += 1` second to preserve ordering. Grouped messages (same `groupId`) are deduplicated (only rescheduled once per group). Selection is cancelled after rescheduling.

If any rescheduled item is deleted during the dialog, the box auto-closes.

#### Edit

Standard edit action is available for scheduled messages (text and caption editing). Edits preserve the `scheduleRepeatPeriod`. Edit uses `Api::EditTextMessage` with the current options.

#### Delete

Standard delete via `DeleteMessagesBox`. Available for all scheduled messages.

### 23.7 Sent-to-Scheduled Toast & Navigation

When a message is scheduled from the normal compose area (not from within the scheduled section):

**Navigation:** If the chat is currently open, `sentToScheduled` fires and the client auto-navigates to the `ScheduledWidget` section, scrolled to the newly scheduled message ID.

### 23.8 Video Processing Flow

When a scheduled video message is sent and the server processes it:

#### Processing Tip Toast (on entry to scheduled section)

When navigating to the scheduled section with a `sentToScheduledId` that maps to a video:
- First, a top-attached toast appears: title `tr::lng_scheduled_video_tip_title`, text `tr::lng_scheduled_video_tip_text`, duration `kVideoProcessingInfoDuration = 4000ms`.
- After 4s, a tooltip bubble appears anchored to the message's effect icon, pointing upward with `processingVideoTipShift = 8px` offset. Max width `processingVideoTipMaxWidth = 364px`. Uses `defaultImportantTooltip` style. Transparent for mouse events. Auto-hides after another 4s with `toggleAnimated(false)`.

#### Published Notification Toast

When a scheduled video completes processing and is sent (`sentFromScheduled` event):
- A toast appears at the top of the window with:
  - Rounded video thumbnail (small, `ImageRoundRadius::Small`) at left, `processingVideoPreviewSkip = 8px` from edges. Size: `font->height * 2` (approximately 26-28px).
  - Bold text: `tr::lng_scheduled_video_published` ("Scheduled video published")
  - "View" button (`processingVideoView` style: -24px width padding, 52px height, `mediaviewTextLinkFg` text, transparent background).
- Toast style: `processingVideoToast` -- `minWidth: 32px`, `maxWidth: 380px`, `padding: 19/17/19/17px`.
- Duration: `kVideoProcessingInfoDuration = 4000ms`.
- Right-click on toast background dismisses it.
- "View" button navigates to the message in the regular chat history.

### 23.9 Forum Topic Support

Scheduled messages work within forum topics. The `ScheduledWidget` can be constructed with a `ForumTopic` pointer, in which case:
- The message list is filtered to only show scheduled messages belonging to that topic.
- The `listContext()` returns `Context::ScheduledTopic` instead of `Context::History`.
- Send actions include `topicRootId` in the reply-to structure.
- Write restrictions respect both peer-level and topic-level closed state.

### 23.10 Animations & Timing

| Animation | Duration | Easing |
|-----------|----------|--------|
| Section enter/exit slide | 150-200ms | Standard section slide |
| Schedule box open | Standard box animation | Default |
| Calendar popup open | Standard layer | Default |
| Selection bar appear | Standard top-bar selection anim | Default |
| Scroll to new message | Animated scroll | Default |
| Corner button show/hide | Standard corner button anim | Default |
| Processing video tooltip appear | `toggleAnimated` | Default fade |
| Processing video tooltip dismiss | 4000ms auto | `toggleAnimated(false)` |
| Published toast duration | 4000ms | Top-attached toast |
| Date field wheel scroll | Immediate (no animation) | N/A |
| Time field error | `showError()` shake | Default input error |

### 23.11 Pixel Dimensions Summary

| Element | Value |
|---------|-------|
| Schedule box width | 364px (`boxWideWidth`) |
| Schedule content row height | 95px (`scheduleHeight`) |
| Date field width | 136px (`scheduleDateWidth`) |
| Date field top | 38px (`scheduleDateTop`) |
| Date field height (min) | 30px |
| Date field text margins | 2/0/2/0px |
| Time field width | 72px (`scheduleTimeWidth`) |
| Time field height (min) | 28px |
| Time separator padding | 2/0/2/0px |
| Time separator font | 14px |
| "at" label skip | 24px (`scheduleAtSkip`) each side |
| "at" label top | 42px (`scheduleAtTop`) |
| Scheduled toggle button | 44x46px (from `historyAttach`) |
| Toggle ripple area | 40px at (2, 3)px |
| Repeat dropdown lock icon padding | -2/1/0/0px |
| Repeat dropdown arrow padding | 3/6/3/0px |
| Reschedule selection limit | 20 messages max |
| Minimal schedule offset | 10 seconds |
| Default schedule offset | 600 seconds (10 min) |
| Until-online timestamp | `0x7FFFFFFE` |
| Video processing tip duration | 4000ms |
| Video tip tooltip shift | 8px |
| Video tip tooltip max width | 364px |
| Published toast min width | 32px |
| Published toast max width | 380px |
| Published toast padding | 19/17/19/17px |
| Published toast preview skip | 8px |
| Published toast "View" button height | 52px |
| Request cooldown | 60000ms |

---

## 24. Keyboard Shortcuts

Telegram Desktop has a comprehensive keyboard shortcut system implemented in `core/shortcuts.cpp`. Shortcuts are driven by a centralized Manager that loads defaults, reads user customizations from JSON, and dispatches commands through a reactive event stream. There is a full in-app Settings UI for viewing and rebinding every shortcut.

Source files: `Telegram/SourceFiles/core/shortcuts.cpp`, `shortcuts.h`, `settings/sections/settings_shortcuts.cpp`, `lib_ui/ui/widgets/fields/input_field.cpp`.

### 24.1 Architecture

**Command system.** Every shortcut maps to a `Command` enum value (70+ commands). Commands are dispatched through `Shortcuts::Requests()`, an `rpl` (reactive) event stream. Widgets subscribe to this stream with priority-based handlers -- higher priority wins if multiple widgets listen for the same command.

**Key registration.** The Manager maintains a `QShortcut` per key-command binding, attached to target widgets via `Shortcuts::Listen(widget)`. When a `QShortcutEvent` fires, the Manager looks up which commands map to that shortcut and fires them through the request stream.

**Auto-repeat commands.** These commands fire repeatedly when the key is held: `ChatPrevious`, `ChatNext`, `ChatFirst`, `ChatLast`, `MediaPrevious`, `MediaNext`.

**Pause/Unpause.** The shortcut system can be globally paused (during shortcut recording in Settings) and unpaused. While paused, no shortcuts fire.

### 24.2 Shortcut Customization

**JSON file pair.** Two files in `tdata/`:
- `shortcuts-default.json` -- Written by the app on startup. Lists all current default bindings. Read-only reference for the user. Regenerated if missing or invalid.
- `shortcuts-custom.json` -- User-editable. Loaded on startup after defaults. Overrides, adds, or removes bindings.

**Custom file format.** JSON array of objects:
```json
[
  { "command": "close_telegram", "keys": "ctrl+f4" },
  { "command": null, "keys": "ctrl+w" }
]
```
- `"command"`: string command name, or `null` to disable a key binding.
- `"keys"`: Qt portable key sequence string (e.g. `"ctrl+shift+m"`, `"alt+down"`, `"f5"`).
- Limit: 2048 entries maximum.

**macOS note in custom file.** On Apple platforms, an auto-inserted comment explains: `ctrl` in key strings maps to the Command key, `meta` maps to the Control key.

**Settings UI (Settings > Chat Settings > Keyboard Shortcuts).** Full graphical shortcut editor:
- Lists every command grouped by category with visual separators.
- Each row shows the command label on the left, current key binding on the right.
- **Left-click** a row to enter recording mode: the key label turns green italic "Recording..." text. Press any key combination to assign it. Press Escape to cancel. Press Backspace/Delete to clear the binding.
- **Right-click** a row to open a popup menu with "Add another binding" -- allows multiple key sequences for one command.
- If a newly recorded key conflicts with another command, the old binding shows strikethrough in red (`attentionButtonFg`).
- A "Reset to defaults" button appears (in a slide-wrap) only when bindings differ from defaults. Clicking it restores all defaults and calls `Shortcuts::ResetToDefaults()`.
- Key display on macOS uses symbols: `Cmd` = `U+2318`, `Ctrl` = `U+2303`, `Alt/Option` = `U+2325`, `Shift` = `U+21E7`.
- Keys that require a modifier (letters, numbers) cannot be assigned bare -- the system rejects them. Function keys (`F1`-`F12`) and media keys can be assigned without modifiers.

### 24.3 Platform Modifier Mapping

| Concept | Windows/Linux | macOS |
|---|---|---|
| Primary modifier | `Ctrl` | `Cmd` (Meta) |
| Secondary modifier | `Alt` | `Option` (Alt) |
| Tertiary modifier | `Win`/`Super` | `Ctrl` (Control) |

In the source, `const auto ctrl = Platform::IsMac() ? u"meta"_q : u"ctrl"_q` determines the primary modifier for folder shortcuts. However, pinned-chat shortcuts (`ctrl+1` through `ctrl+8`) and window shortcuts (`ctrl+w`, `ctrl+q`, etc.) use literal `"ctrl"` which Qt maps to Cmd on macOS automatically via `QKeySequence`.

The text formatting shortcuts use `QKeySequence::Bold` etc., which Qt resolves to `Cmd+B` on macOS and `Ctrl+B` on Windows/Linux.

### 24.4 Default Shortcut Reference

#### Application / Window

| Shortcut | Command | Description |
|---|---|---|
| Ctrl+W | `close_telegram` | Close window (minimize to tray) |
| Ctrl+F4 | `close_telegram` | Close window (alternate) |
| Ctrl+L | `lock_telegram` | Lock app (requires local passcode) |
| Ctrl+M | `minimize_telegram` | Minimize window |
| Ctrl+Q | `quit_telegram` | Quit application |

#### Search

| Shortcut | Command | Description |
|---|---|---|
| Ctrl+F | `search` | Open search in current context |

#### Chat Navigation

| Shortcut | Command | Description |
|---|---|---|
| Ctrl+Tab | *(chat switcher)* | Open chat switcher overlay (hold Ctrl) |
| Ctrl+Shift+Tab | *(chat switcher)* | Open chat switcher, go backwards |
| Ctrl+PgDn | `next_chat` | Move to next chat in list |
| Alt+Down | `next_chat` | Move to next chat (alternate) |
| Ctrl+PgUp | `previous_chat` | Move to previous chat in list |
| Alt+Up | `previous_chat` | Move to previous chat (alternate) |
| Ctrl+Alt+Home | `first_chat` | Jump to first chat |
| Ctrl+Alt+End | `last_chat` | Jump to last chat |
| Ctrl+0 | `self_chat` | Open Saved Messages |
| Ctrl+9 | `show_archive` | Open Archived Chats |
| Ctrl+J | `show_contacts` | Open Contacts |

#### Pinned Chats

| Shortcut | Command | Description |
|---|---|---|
| Ctrl+1 | `pinned_chat1` | Open 1st pinned chat |
| Ctrl+2 | `pinned_chat2` | Open 2nd pinned chat |
| Ctrl+3 | `pinned_chat3` | Open 3rd pinned chat |
| Ctrl+4 | `pinned_chat4` | Open 4th pinned chat |
| Ctrl+5 | `pinned_chat5` | Open 5th pinned chat |
| Ctrl+6 | `pinned_chat6` | Open 6th pinned chat |
| Ctrl+7 | `pinned_chat7` | Open 7th pinned chat |
| Ctrl+8 | `pinned_chat8` | Open 8th pinned chat |

*Note: On macOS, `Ctrl+1`--`Ctrl+8` use the Command key (standard Qt mapping).*

#### Account Switching

| Shortcut | Command | Description |
|---|---|---|
| Cmd+1 / Ctrl+1 | `account1` | Switch to 1st account |
| Cmd+2 / Ctrl+2 | `account2` | Switch to 2nd account |
| Cmd+3 / Ctrl+3 | `account3` | Switch to 3rd account |
| Cmd+4 / Ctrl+4 | `account4` | Switch to 4th account |
| Cmd+5 / Ctrl+5 | `account5` | Switch to 5th account |
| Cmd+6 / Ctrl+6 | `account6` | Switch to 6th account |

*Account shortcuts are not in `fillDefaults()` -- they have no default key binding. Users must assign them manually via Settings or `shortcuts-custom.json`. The commands exist but are unbound by default.*

#### Folder Navigation

| Shortcut (Linux/Win) | Shortcut (macOS) | Command | Description |
|---|---|---|---|
| Ctrl+1 | Cmd+1 | `all_chats` | Show All Chats (folder index 1) |
| Ctrl+2 | Cmd+2 | `folder1` | Show Folder 1 (folder index 2) |
| Ctrl+3 | Cmd+3 | `folder2` | Show Folder 2 |
| Ctrl+4 | Cmd+4 | `folder3` | Show Folder 3 |
| Ctrl+5 | Cmd+5 | `folder4` | Show Folder 4 |
| Ctrl+6 | Cmd+6 | `folder5` | Show Folder 5 |
| Ctrl+7 | Cmd+7 | `folder6` | Show Folder 6 |
| Ctrl+8 | Cmd+8 | `last_folder` | Show last folder |
| Ctrl+Shift+Down | Cmd+Shift+Down | `next_folder` | Switch to next folder |
| Ctrl+Shift+Up | Cmd+Shift+Up | `previous_folder` | Switch to previous folder |

*Folder shortcuts and pinned-chat shortcuts share the same key ranges (Ctrl+1 through Ctrl+8). On macOS, the `ctrl` variable resolves to `meta` (Cmd), so folder shortcuts use `Cmd+1`--`Cmd+8`, while pinned-chat shortcuts use literal `Ctrl` which maps to Cmd too via Qt. In practice, the folder commands take priority when folders are configured, because the folder shortcut loop overwrites the pinned-chat bindings for the same keys. When no folders exist, pinned-chat shortcuts apply.*

#### Chat Actions

| Shortcut | Command | Description |
|---|---|---|
| Ctrl+R | `read_chat` | Mark current chat as read |
| Ctrl+R | `record_voice` | Start voice message recording (dual-bound) |
| Ctrl+\\ | `show_chat_menu` | Open chat context menu (peer menu) |
| Ctrl+] | `show_chat_preview` | Show chat preview popup |
| *(unbound)* | `archive_chat` | Archive current chat |
| *(unbound)* | `show_scheduled` | Open scheduled messages panel |
| *(unbound)* | `show_admin_log` | Open admin log (channels only) |

*`Ctrl+R` is bound to both `read_chat` and `record_voice`. Both handlers fire; the one with higher priority in the active context wins.*

#### Message Sending

| Shortcut | Command | Description |
|---|---|---|
| *(unbound)* | `message` | Send message (just send, no silent/schedule) |
| *(unbound)* | `message_silently` | Send message silently |
| *(unbound)* | `message_scheduled` | Send message with schedule dialog |

*Send shortcuts are unbound by default. Sending is handled by the compose field's Enter/Return behavior (see 24.6).*

#### Media Playback (Global)

| Shortcut | Command | Description |
|---|---|---|
| Media Play | `media_play` | Play media (hardware key) |
| Media Pause | `media_pause` | Pause media (hardware key) |
| Media Play/Pause | `media_playpause` | Toggle play/pause (hardware key) |
| Media Stop | `media_stop` | Stop media playback (hardware key) |
| Media Previous | `media_previous` | Previous track (hardware key) |
| Media Next | `media_next` | Next track (hardware key) |

*Media shortcuts use hardware media keys. They are disabled by default and toggled on via `ToggleMediaShortcuts(true)` when a media player is active. When toggled off, media keys pass through to the OS.*

#### Media Viewer

| Shortcut | Command | Description |
|---|---|---|
| *(unbound)* | `media_viewer_video_fullscreen` | Toggle video fullscreen in media viewer |

### 24.5 Ctrl+Tab Chat Switcher

A modal overlay for quick chat switching, similar to Alt+Tab in window managers.

**Activation.** Pressing `Ctrl+Tab` (or `Ctrl+Shift+Tab`) initiates the chat switch process. The system:
1. Sets `ChatSwitchModifier` to the Ctrl/Meta key.
2. Marks `ChatSwitchStarted = true`.
3. Installs a global event filter that blocks `InputMethod` events.
4. Fires a `ChatSwitchRequest` with `.started = true`.

**Navigation while held.** While Ctrl is held down:
- `Tab` / `Down` / `Right` -- move to next chat.
- `Shift+Tab` / `Up` / `Left` / `Q` -- move to previous chat.
- `Escape` -- cancel without switching.
- `Enter` / `Return` -- confirm selection (same as releasing Ctrl).

**Completion.** Releasing the Ctrl (or Meta on macOS) key fires `CancelChatSwitch(Qt::Key_Enter)`, confirming the selected chat and dismissing the overlay.

**Special keys array:** `Left`, `Right`, `Up`, `Down`, `Q` -- these are the navigable keys during chat switch mode. They are processed via `CheckChatSwitchEvent()` and `NavigateChatSwitch()`.

**Duplicate prevention.** A `ChatSwitchKeyPressHandled` array tracks which special keys have already fired in the current event cycle, preventing double-fire across platform differences (Windows fires both `ShortcutOverride` + `KeyPress`, macOS fires only `ShortcutOverride` on first press).

### 24.6 Compose Box Key Handling

The compose field (`InputField`) handles keyboard input in `keyPressEventInner()`. Behavior depends on the **submit mode** setting (Settings > Chat Settings > "Send by Enter"):

**Submit settings enum:**
- `Enter` -- Enter sends, Shift+Enter inserts newline.
- `CtrlEnter` -- Ctrl+Enter sends, Enter inserts newline.
- `Both` -- Both Enter and Ctrl+Enter send.
- `None` -- Neither sends (used for non-chat fields).

**Submit logic (`ShouldSubmit`).** A message is submitted when:
- `Ctrl+Shift` is pressed (always sends regardless of mode), OR
- `Ctrl` is pressed and mode is not `None` or `Enter`, OR
- Neither Ctrl nor Shift and mode is not `None` or `CtrlEnter`.

| Key | Behavior |
|---|---|
| Enter/Return | Send message (if submit mode allows) or insert newline |
| Shift+Enter | Insert newline (if mode is `Enter`) or send (if mode is `Both`) |
| Ctrl+Enter | Send message (if mode is `CtrlEnter` or `Both`) or insert newline |
| Ctrl+Shift+Enter | Always sends message |
| Escape | Cancel current action (fires `cancelled` signal -- clears reply/edit) |
| Tab | Trigger autocomplete (fires `tabbed` signal -- emoji/mention/command completion). If no handler, moves focus to next widget. Alt+Tab and Ctrl+Tab are ignored (passed to parent). |
| Up arrow (empty field) | Edit last sent message (see 24.7) |
| Ctrl+Up | Reply to previous message |
| Ctrl+Down | Reply to next message / cancel reply |
| Backspace (macOS + Ctrl key) | Delete from cursor to start of line (macOS convention: `Ctrl` is the physical Control key, not Cmd) |
| Backspace | Revert markdown format replacement if applicable, or exit blockquote if at block start |
| PageUp/PageDown | Scroll chat history (when `customUpDown` is true, Up/Down also pass to parent for list navigation) |
| Ctrl+O | Open file picker to attach file |

**Newline insertion.** When Enter does not submit, the field inserts either a hard line break (`kHardLine`) or soft line break (`kSoftLine`) depending on whether a blockquote is active. Three consecutive Enters inside a blockquote exit the block.

**Ctrl+Shift+V.** Paste as plain text. The code detects `Shift+Paste` and strips formatting.

**macOS-specific.** `Ctrl+E` (physical Control key) copies selection to the system Find buffer (`QClipboard::FindBuffer`). `Cmd+Up` and `Cmd+Down` act as Home/End (cursor to start/end of text) when the field has content, so reply navigation (`Ctrl+Up/Down`) only fires when the field is empty on macOS.

### 24.7 Message History Key Handling

The `HistoryWidget::keyPressEvent()` handles keys in the chat view:

| Key | Behavior |
|---|---|
| Escape | Call `escape()` -- cancels reply, edit, search, or navigates back |
| Back (Android/hardware) | Fire cancel request (back navigation) |
| PageDown | Scroll down (forwarded to scroll widget) |
| PageUp | Scroll up (forwarded to scroll widget) |
| Down (no modifier) | Scroll down |
| Up (no modifier, empty field, no edit/reply active) | Edit last editable message. If the last message is a local media message with caption, opens `EditCaptionBox` instead. If no editable message exists, scrolls up. |
| Ctrl+Up | Reply to previous message (`replyToPreviousMessage()`) -- selects the message above the current reply target, highlights it, and sets it as the reply. Skips local (unsent) messages. |
| Ctrl+Down | Reply to next message (`replyToNextMessage()`) -- selects the message below. If at the last message, clears the reply. |
| Enter/Return | If bot start button is visible, sends `/start`. Otherwise, if submit mode allows, sends the composed message. |
| Ctrl+O | Open file chooser (attach file) |

**Reply navigation behavior.** `replyToPreviousMessage()` finds the message displayed before the current reply target (or the last message if no reply is active), scrolls to it via `controller()->showMessage()`, and calls `replyToMessage()` to set it as the reply target. Skips local (pending) messages. Does not work in edit mode, forums, or when replying cross-peer. `replyToNextMessage()` works similarly in the forward direction; reaching the end clears the reply and highlight.

### 24.8 Text Formatting Shortcuts

Applied to selected text in the compose box. Defined as `MarkdownAction` entries with `QKeySequence` bindings. Each shortcut toggles the format on/off for the selection.

| Shortcut (Win/Linux) | Shortcut (macOS) | Format | Tag |
|---|---|---|---|
| Ctrl+B | Cmd+B | **Bold** | `kTagBold` |
| Ctrl+I | Cmd+I | *Italic* | `kTagItalic` |
| Ctrl+U | Cmd+U | Underline | `kTagUnderline` |
| Ctrl+Shift+X | Cmd+Shift+X | ~~Strikethrough~~ | `kTagStrikeOut` |
| Ctrl+Shift+M | Cmd+Shift+M | `Monospace` | `kTagCode` |
| Ctrl+Shift+. | Cmd+Shift+. | Blockquote | `kTagBlockquote` |
| Ctrl+Shift+P | Cmd+Shift+P | Spoiler | `kTagSpoiler` |
| Ctrl+Shift+N | Cmd+Shift+N | Clear formatting | *(clears all tags)* |
| Ctrl+K | Cmd+K | Insert/edit link | *(opens link dialog)* |
| Ctrl+Shift+D | Cmd+Shift+D | Insert/edit date | *(opens date picker)* |

**MarkdownSet variants.** Two action sets exist:
- **Default** (`MarkdownActions()`): All 10 actions above.
- **Notes** (`MarkdownActionsNotes()`): Only Bold, Italic, Underline, Strikethrough, Spoiler, and Clear formatting (no Blockquote, Monospace, Link, or Date).

**Implementation.** Each action is registered as a `QShortcut` with `Qt::WidgetShortcut` scope on the inner `QTextEdit`. When triggered, `executeMarkdownAction()` either toggles the tag on the selection, opens the link/date editor, or clears formatting. If markdown is disabled for the field, all actions are no-ops.

**Context menu.** Right-clicking in the compose field adds formatting actions to the context menu, each showing its shortcut string. The menu groups them as: Bold, Italic, Underline (from Qt standard sequences), then Strikethrough, Blockquote, Monospace, Spoiler (with custom sequences), then Clear formatting and Edit link.

### 24.9 Media Viewer Shortcuts

The `OverlayWidget::handleKeyPress()` function processes keys in the media viewer overlay:

#### Photo/General Navigation

| Key | Action |
|---|---|
| Left | Previous media item |
| Right | Next media item |
| Escape | Close viewer (or exit fullscreen if video is fullscreen). If document is loading, cancels download. |
| Ctrl+S / Ctrl+Shift+S | Save as (file save dialog) |
| Ctrl+C / Copy | Copy media to clipboard |
| Enter / Return / Space | Toggle play/pause (video) or open document (non-video) |
| H | Flip image horizontally |
| V | Flip image vertically |

#### Video Playback

| Key | Action |
|---|---|
| K | Toggle play/pause |
| Space (press) | Start speed boost timer (300ms hold delay). If released before timer, toggles play/pause. If held, activates speed boost. |
| Space (release) | Stop speed boost if active |
| J | Seek backward 10 seconds (`kSeekTimeMsLong = 10000ms`) |
| L | Seek forward 10 seconds |
| Left (fullscreen) | Seek backward 5 seconds (`kSeekTimeMs = 5000ms`) |
| Right (fullscreen) | Seek forward 5 seconds |
| Alt+Enter / Ctrl+Enter | Toggle fullscreen video mode |
| 0 (fullscreen) | Restart video from beginning |
| 1-9 (fullscreen) | Seek to 10%-90% of duration |
| Period (.) (paused) | Step forward one frame |
| Comma (,) (paused) | Step backward one frame |
| Alt+Left | Jump to previous chapter/timestamp |
| Alt+Right | Jump to next chapter/timestamp |

*Frame stepping uses `kFrameStepThrottleMs = 150ms` throttle. Fallback FPS for frame duration calculation: 30 fps.*

#### Zoom

| Key | Action |
|---|---|
| Ctrl+Plus / Ctrl+= / Ctrl+* | Zoom in |
| Ctrl+Minus / Ctrl+_ | Zoom out |
| Ctrl+Scroll Up | Zoom in |
| Ctrl+Scroll Down | Zoom out |
| Scroll Up (no Ctrl) | Previous media item |
| Scroll Down (no Ctrl) | Next media item |

*Zoom is disabled in fullscreen video mode (locked to screen-fit). Zoom uses integer levels: positive values multiply, negative values divide. `kZoomToScreenLevel` = fit-to-screen.*

#### Stories Mode

| Key | Action |
|---|---|
| Space | Toggle story pause/resume |
| *(other keys)* | Forwarded to `_stories->tryProcessKeyInput()` |

### 24.10 Support Mode Shortcuts

Available only when the account is in Telegram Support mode (`session().supportMode()`). These shortcuts are toggled on/off via `ToggleSupportShortcuts()`.

| Shortcut | Command | Description |
|---|---|---|
| F5 | `support_reload_templates` | Reload support reply templates |
| Ctrl+Delete | `support_toggle_muted` | Toggle muted state for support chats |
| Ctrl+Insert | `support_scroll_to_current` | Scroll to current support chat |
| Ctrl+Shift+X | `support_history_back` | Navigate back in support chat history |
| Ctrl+Shift+C | `support_history_forward` | Navigate forward in support chat history |

*Support shortcuts are stored in a separate set and only enabled when support mode is active. `Ctrl+Shift+X` conflicts with Strikethrough formatting -- in support mode, the support command takes priority at the shortcut system level.*

### 24.11 Scope & Priority

**Global shortcuts (always active when app has focus):**
- Window controls: Close, Lock, Minimize, Quit.
- Media hardware keys (when media player active).
- Chat navigation: Next/Previous/First/Last chat.
- Folder navigation: Next/Previous folder, folder jump.
- Account switching.
- Chat switcher (Ctrl+Tab).

**Context-specific shortcuts (require specific widget focus):**
- Search (Ctrl+F) -- requires dialogs or chat widget in focus chain.
- Chat actions (Read, Archive, Menu, Preview) -- require active chat.
- Message sending shortcuts -- require compose field.
- Text formatting -- require compose field with selection.
- Record voice/round -- require history widget with send permission.
- Media viewer shortcuts -- only in media viewer overlay.
- Scheduled messages -- require chat with scheduled messages.
- Admin log -- require channel admin privileges.

**Priority system.** `Request::check(command, priority)` accepts a priority integer. When multiple widgets listen for the same command, the handler with the highest priority wins. Default priority is 0. The `handle()` method registers the handler only if it beats the current best priority. This prevents, for example, a background chat's search handler from stealing Ctrl+F from the active chat.

**Focus chain gating.** Most shortcut handlers check `Ui::InFocusChain(this)`, `Ui::AppInFocus()`, `isActiveWindow()`, and `!controller()->isLayerShown()` before processing. This ensures shortcuts only fire in the appropriate context and are suppressed when dialogs/popups are open.

---

## 25. Theming & Color System

Source: `Telegram/SourceFiles/window/themes/`, `Telegram/SourceFiles/ui/chat/chat_theme.*`, `Telegram/SourceFiles/data/data_wall_paper.*`, `Telegram/SourceFiles/data/data_cloud_themes.*`, `Telegram/SourceFiles/settings/sections/settings_chat.cpp`. AyuGram additions: `Telegram/SourceFiles/ayu/ui/utils/palette.*`, `ayu/ui/settings/settings_appearance.cpp`, `ayu/ui/settings/settings_chats.cpp`.

---

### 25.1 Palette Architecture

The entire Telegram Desktop UI is driven by a single global palette object (`style::main_palette`) containing **~370 named color tokens**. Every widget references tokens by name, never raw hex values. Themes work by replacing the palette wholesale.

**Token format in `.tdesktop-theme` files:**

```
tokenName: #rrggbb;          // opaque color
tokenName: #rrggbbaa;        // color with alpha
tokenName: otherTokenName;   // reference (resolved at load time)
// comments allowed
```

Semicolons terminate each entry. References must point to a previously-defined token (forward references are invalid). Lines starting with `//` are comments. Blank lines ignored. Maximum scheme file size: **1 MB** (`kThemeSchemeSizeLimit`).

**Token hierarchy** -- tokens cascade from generic to specific:

1. **Window-level fallbacks** (`window*`) -- base colors everything inherits from
2. **Component tokens** (`activeButton*`, `lightButton*`, `menuBg*`, etc.) -- typically reference window tokens
3. **Domain-specific tokens** (`dialogs*`, `history*`, `msg*`, `mediaview*`, etc.) -- reference component or window tokens

This means changing `windowBgActive` (the primary accent) cascades through `activeButtonBg`, `dialogsUnreadBg`, `dialogsVerifiedIconBg`, `sliderBgActive`, and dozens more via reference chains.

### 25.2 Complete Color Token Reference

The palette contains **369 tokens** (Day Blue) to **467 tokens** (Night themes, which define more title bar variants). Organized by functional group:

#### 25.2.1 Window & Global Tokens

| Token | Day Blue | Night (Tinted) | Night Green | Purpose |
|-------|----------|----------------|-------------|---------|
| `windowBg` | `#ffffff` | `#17212b` | `#282e33` | Global background fallback |
| `windowFg` | `#000000` | `#f5f5f5` | `#f5f5f5` | Global text fallback |
| `windowBgOver` | `#f1f1f1` | `#232e3c` | `#313b43` | Hover background |
| `windowBgRipple` | `#e5e5e5` | `#24303d` | `#3f4850` | Ripple effect |
| `windowFgOver` | = `windowFg` | `#e9ecf0` | `#e9ecf0` | Hover text |
| `windowSubTextFg` | `#999999` | `#708499` | `#82868a` | Secondary text |
| `windowBoldFg` | `#222222` | `#e9e8e8` | `#e9e8e8` | Bold text |
| `windowBgActive` | `#40a7e3` | `#5288c1` | `#3fc1b0` | **Primary accent fill** |
| `windowFgActive` | `#ffffff` | `#ffffff` | `#ffffff` | Text on accent |
| `windowActiveTextFg` | `#168acd` | `#6ab3f3` | `#4be1c3` | Active text (links, online) |
| `windowShadowFg` | `#000000` | `#000000` | `#000000` | Shadow |
| `shadowFg` | `#00000018` | `#04080e56` | `#00000018` | Semi-transparent shadow |

#### 25.2.2 Button Tokens

| Token | Day Blue | Night | Purpose |
|-------|----------|-------|---------|
| `activeButtonBg` | = `windowBgActive` | `#2f6ea5` | Primary button bg |
| `activeButtonBgOver` | `#39a5db` | `#3476ab` | Primary button hover |
| `activeButtonBgRipple` | `#2095d0` | `#3b7cb1` | Primary button ripple |
| `activeButtonFg` | = `windowFgActive` | `#ffffff` | Primary button text |
| `activeButtonSecondaryFg` | `#cceeff` | `#9abfe7` | Secondary text on primary |
| `lightButtonBg` | = `windowBg` | `#17212b` | Light button bg |
| `lightButtonBgOver` | `#e3f1fa` | `#1d2a39` | Light button hover |
| `lightButtonFg` | = `windowActiveTextFg` | `#6ab2f2` | Light button text |
| `attentionButtonFg` | `#d14e4e` | `#ec3942` | Destructive action text |
| `attentionButtonBgOver` | `#fcdfde` | `#592a2a64` | Destructive hover bg |
| `outlineButtonOutlineFg` | = `windowBgActive` | `#3983c3` | Outlined button border |

#### 25.2.3 Dialog List Tokens

| Token | Day Blue | Night | Purpose |
|-------|----------|-------|---------|
| `dialogsBg` | = `windowBg` | = `windowBg` | Chat list bg |
| `dialogsNameFg` | = `windowBoldFg` | = `windowBoldFg` | Chat name |
| `dialogsDateFg` | = `windowSubTextFg` | = `windowSubTextFg` | Timestamp |
| `dialogsTextFgService` | = `windowActiveTextFg` | = `windowActiveTextFg` | Sender name in preview |
| `dialogsDraftFg` | `#dd4b39` | `#dd4b39` | "Draft:" label |
| `dialogsUnreadBg` | = `windowBgActive` | = `windowBgActive` | Unread badge |
| `dialogsUnreadBgMuted` | `#bbbbbb` | `#bbbbbb` | Muted unread badge |
| `dialogsBgActive` | `#419fd9` | `#2a4e76` | Selected chat row |
| `dialogsOnlineBadgeFg` | `#4dc920` | `#4dc920` | Online indicator |
| `dialogsSentIconFg` | `#2ca6e8` | `#60b9f4` | Read check marks |

#### 25.2.4 Message Bubble Tokens

| Token | Day Blue | Night | Night Green | Purpose |
|-------|----------|-------|-------------|---------|
| `msgInBg` | = `windowBg` | `#182533` | `#33393f` | Incoming bubble bg |
| `msgInBgSelected` | `#bbe1fc` | `#2e70a5` | `#009687` | Incoming selected |
| `msgOutBg` | `#def1fd` | `#2b5278` | `#2a2f33` | Outgoing bubble bg |
| `msgOutBgSelected` | `#bbe1fc` | `#2e70a5` | `#009687` | Outgoing selected |
| `msgSelectOverlay` | `#358cd44c` | `#3585d44c` | `#35d4bf4c` | Media selection overlay |
| `msgInShadow` | `#748ea229` | `#748ea200` | `#748ea200` | Bubble shadow (day only) |
| `msgOutShadow` | `#0d5a911a` | `#00000000` | `#00000000` | Bubble shadow (day only) |
| `msgInDateFg` | `#a0acb6` | `#6d7f8f` | `#828d94` | Timestamp in incoming |
| `msgOutDateFg` | `#86a8c2` | `#7da8d3` | `#737f87` | Timestamp in outgoing |
| `msgServiceBg` | `#00518059` | `#213040d5` | `#363c43c8` | Service msg bg (adjusted) |
| `msgServiceFg` | = `windowFgActive` | = `windowFgActive` | = `windowFgActive` | Service msg text |
| `msgInReplyBarColor` | = `activeLineFg` | `#429bdb` | `#32ceb9` | Reply bar in incoming |
| `msgOutReplyBarColor` | = `historyOutIconFg` | `#65b9f4` | `#32ceb9` | Reply bar in outgoing |
| `historyOutIconFg` | `#059de8` | `#62b2fd` | `#11bfab` | Read ticks in outgoing |
| `msgInMonoFg` | `#4e7391` | `#5a8cb7` | `#5aaba0` | Monospace text incoming |
| `msgOutMonoFg` | `#4e7391` | `#aed1f3` | `#c2f2ec` | Monospace text outgoing |

#### 25.2.5 Peer Name Colors (Fixed Across All Themes)

8 peer colors cycle by user ID. These are in the **colorize exclusion list** and never change with accent:

| Peer # | Name Color | Userpic Bg | Userpic Bg2 |
|--------|------------|------------|-------------|
| 1 | `#c03d33` (red) | `#ff845e` | `#d45246` |
| 2 | `#4fad2d` (green) | `#9ad164` | `#46ba43` |
| 3 | `#d09306` (gold) | `#e5ca77` | `#e5ca77` |
| 4 | = `windowActiveTextFg` (blue) | `#5caffa` | `#408acf` |
| 5 | `#8544d6` (purple) | `#b694f9` | `#6c61df` |
| 6 | `#cd4073` (pink) | `#ff8aac` | `#d95574` |
| 7 | `#2996ad` (teal) | `#5bcbe3` | `#359ad4` |
| 8 | `#ce671b` (orange) | `#febb5b` | `#f68136` |

#### 25.2.6 File Type Colors (Fixed)

| File Type | Bg | Dark | Over | Selected |
|-----------|----|------|------|----------|
| Blue (1) | `#72b1df` | `#5c9ece` | `#5294c4` | `#5099d0` |
| Green (2) | `#61b96e` | `#4da859` | `#44a050` | `#46a07e` |
| Red (3) | `#e47272` | `#cd5b5e` | `#c35154` | `#9f6a82` |
| Yellow (4) | `#efc274` | `#e6a561` | `#dc9c5a` | `#b19d84` |

#### 25.2.7 Voice Waveform Tokens

| Token | Day Blue | Night | Purpose |
|-------|----------|-------|---------|
| `msgWaveformInActive` | = `windowBgActive` | `#549cd7` | Played portion (incoming) |
| `msgWaveformInInactive` | `#d4dee6` | `#3a4d61` | Upcoming portion (incoming) |
| `msgWaveformOutActive` | = `windowBgActive` | `#62b2fd` | Played portion (outgoing) |
| `msgWaveformOutInactive` | `#b3d4e7` | `#4b7fb3` | Upcoming portion (outgoing) |

#### 25.2.8 Media Viewer Tokens

| Token | Day Blue | Night | Purpose |
|-------|----------|-------|---------|
| `mediaviewBg` | `#222222eb` | (same) | Overlay background |
| `mediaviewControlBg` | `#0000003c` | (same) | Control button bg |
| `mediaviewControlFg` | = `windowFgActive` | (same) | Control button fg |
| `mediaviewCaptionBg` | `#11111180` | (same) | Caption area bg |
| `mediaviewPlaybackActive` | `#c7c7c7` | (same) | Progress bar played |
| `mediaviewPlaybackInactive` | `#252525` | (same) | Progress bar remaining |
| `mediaviewPlaybackActiveOver` | `#ffffff` | (same) | Played (hover) |

#### 25.2.9 Intro / Login Tokens

| Token | Day Blue | Purpose |
|-------|----------|---------|
| `introCoverTopBg` | `#0f89d0` | Gradient top |
| `introCoverBottomBg` | `#39b0f0` | Gradient bottom |
| `introCoverIconsFg` | `#5ec6ff` | Floating icons |
| `introCoverPlaneTrace` | `#5ec6ff69` | Plane trail |
| `introCoverPlaneTop` | `#ffffff` | Paper plane |

#### 25.2.10 Scroll Bar Tokens

Day themes use dark-on-light (`#00000053`), night themes use light-on-dark (`#ffffff53`). Over states increase alpha:

| Token | Day | Night | Purpose |
|-------|-----|-------|---------|
| `scrollBarBg` | `#00000053` | `#ffffff53` | Bar thumb |
| `scrollBarBgOver` | `#0000007a` | `#ffffff7a` | Bar thumb (hover) |
| `scrollBg` | `#00000000` | `#ffffff1a` | Track bg |
| `scrollBgOver` | `#0000001a` | `#ffffff2c` | Track bg (hover) |

### 25.3 Built-in Themes

Four embedded themes defined in `window_themes_embedded.cpp` via `EmbeddedThemes()`:

#### 25.3.1 Default (Classic Day)

- **Accent:** `#40a7e3` (Telegram blue)
- **Outgoing bubble:** `#eaffdc` (light green tint)
- **Incoming bubble:** `#ffffff` (white)
- **Background:** `#9bd494` (green -- radio button indicator color)
- **Wallpaper:** none bundled, uses default cloud wallpaper
- **No theme file** -- palette is the app's compiled-in default

#### 25.3.2 Day Blue

- **Accent:** `#40a7e3` (same Telegram blue)
- **Outgoing bubble:** `#d7f0ff` (light blue tint)
- **Incoming bubble:** `#ffffff`
- **Background:** `#7ec4ea` (blue indicator)
- **Theme file:** `:/gui/day-blue.tdesktop-theme`
- **Wallpaper:** `background.png` inside the zip (blue cloudy pattern)
- **369 color tokens** defined

#### 25.3.3 Night (Tinted / Dark Blue)

- **Accent:** `#5288c1` (muted blue)
- **Outgoing bubble:** `#2b5278` (dark blue)
- **Incoming bubble:** `#182533` (darker blue-grey)
- **Background:** `#485761` (dark grey-blue indicator)
- **Theme file:** `:/gui/night.tdesktop-theme`
- **Wallpaper:** `background.png` (dark blue pattern with subtle shapes)
- **467 color tokens** (more title bar variants for Windows)
- **Dark flag:** yes -- `dialogsBg` value < 0.5 lightness triggers dark detection

#### 25.3.4 Night Green

- **Accent:** `#3fc1b0` (teal/green)
- **Outgoing bubble:** `#2a2f33` (near-black)
- **Incoming bubble:** `#33393f` (dark grey)
- **Background:** `#485761` (same indicator as Night)
- **Theme file:** `:/gui/night-green.tdesktop-theme`
- **Wallpaper:** `background.png` (dark neutral pattern)
- **467 color tokens**
- **Dark flag:** yes

#### 25.3.5 Custom Base Themes

Two additional base files exist for the theme editor's colorizer to operate on:

- `day-custom-base.tdesktop-theme` -- Day palette with full comments (543 lines), used when creating a custom day theme via accent color
- `night-custom-base.tdesktop-theme` -- Night palette with full comments (467 lines), used when creating a custom night theme via accent color

These are never shown as user-selectable themes. They serve as the "canvas" that the colorizer remaps when the user picks a custom accent.

### 25.4 Accent Color System

#### 25.4.1 Default Accent Palettes

Each built-in theme offers **8 preset accent colors** shown as circles in Settings > Chat Settings:

| # | Day / Day Blue | Night | Night Green |
|---|----------------|-------|-------------|
| 1 | `#45bce7` (blue) | `#58bfe8` | `#60a8e7` |
| 2 | `#52b440` (green) | `#466f42` | `#4e9c57` |
| 3 | `#d46c99` (pink) | `#aa6084` | `#ca7896` |
| 4 | `#df8a49` (orange) | `#a46d3c` | `#cc925c` |
| 5 | `#9978c8` (purple) | `#917bbd` | `#a58ed2` |
| 6 | `#c55245` (red) | `#ab5149` | `#d27570` |
| 7 | `#687b98` (grey-blue) | `#697b97` | `#7b8799` |
| 8 | `#dea922` (gold) | `#9b834b` | `#cbac67` |

Night palettes are deliberately desaturated/darkened compared to day counterparts.

#### 25.4.2 Accent Color Picker UI

In Settings > Chat Settings, accent circles appear below the theme radio buttons:

- **Circle diameter:** `st::settingsAccentColorSize`
- **Border/ring width:** `st::settingsAccentColorLine`
- **Selection ring skip:** `st::settingsAccentColorSkip`
- **Selection animation:** `st::defaultRadio.duration * 2` (~200ms)
- **Custom color button:** Rendered as 7 small circles (1 center + 6 around), each diameter = `accentColorSize / 8`. Opens a full color picker dialog.
- **Horizontal distribution:** Equal spacing, vertically positioned at `st::defaultVerticalListSkip * 2` below the theme selection row
- **System accent color:** On Qt 6.6+, a checkbox `"Use system accent color"` appears, reading the OS-level accent via `SystemAccentColor()` (uses `QGuiApplication::palette().accent().color()`)

#### 25.4.3 Colorizer Algorithm

When the user selects an accent color, the **colorizer** transforms the base palette:

1. Extract HSV from the theme's **original accent** and the **new accent**
2. For each palette token NOT in the exclusion list (~81 tokens excluded):
   - Convert to HSV
   - Shift hue by the difference between new and original accent hues
   - Scale saturation proportionally
   - Clamp lightness to `[lightnessMin=64, lightnessMax=160]` (for Day themes) -- Night themes have different clamping
3. For Night themes: a **`keepContrast`** map of 12 element pairs ensures critical foreground/background pairs maintain readable contrast (e.g., `activeButtonFg` vs `activeButtonBg` at `#17212b`)
4. The 5 embedded scheme preview colors (background, sent, received, radioActive, radioInactive) are also transformed

**Colorize exclusion list** (~81 tokens that NEVER change with accent):
- All peer name/userpic colors (`historyPeer1NameFg` through `historyPeer8UserpicBg2`)
- All file type colors (`msgFile1Bg` through `msgFile4BgSelected`)
- Media viewer corner colors (`mediaviewFileRedCornerFg` etc.)
- Good/error text (`boxTextFgGood`, `boxTextFgError`)
- Settings icon backgrounds (`settingsIconBg1` through `settingsIconBg6`)
- Premium button gradients (`premiumButtonBg1` through `premiumButtonBg3`)
- Call icon (`callIconFg`)

#### 25.4.4 Accent Persistence

Custom accent selections are serialized per-theme-type via `AccentColors::serialize()`. Storage is a flat map of `EmbeddedType -> QColor`. On app launch, the stored accent is re-applied to the active theme's palette via the colorizer.

### 25.5 Theme File Format (.tdesktop-theme)

A `.tdesktop-theme` file is a **ZIP archive** (renamed extension) containing:

```
mytheme.tdesktop-theme          (ZIP container, max 5 MB)
  |- colors.tdesktop-theme      (palette text file, max 1 MB)
  |- background.jpg             (non-tiled background, max 25 MB)
  OR
  |- background.png
  OR
  |- tiled.jpg                  (tiled background)
  OR
  |- tiled.png
```

**Rules:**
- The palette file must be named `colors.tdesktop-theme` or `colors.tdesktop-palette`
- Background named `background.*` renders as a single image scaled to fit
- Background named `tiled.*` renders as a repeating tile
- If no background image is included, the theme inherits the current wallpaper
- Only one background file allowed; first match wins
- Supported formats: JPEG, PNG

**Palette file syntax:**
```
// Comment line
tokenName: #rrggbb;            // 6-hex RGB
tokenName: #rrggbbaa;          // 8-hex RGBA
tokenName: otherToken;          // reference

// THEME EDITOR SERVICE INFO START
// id:12345 hash:67890
// THEME EDITOR SERVICE INFO END
```

Cloud theme metadata (ID + access hash) is embedded between the `SERVICE INFO` comment markers. The `WriteCloudToText` / `ReadCloudFromText` functions manage this.

### 25.6 Theme Editor

Full in-app theme editor accessible via Settings > Chat Settings > Edit Current Theme (three-dot menu). Source: `window_theme_editor.cpp`, `window_theme_editor_block.cpp`, `window_theme_editor_box.cpp`.

#### 25.6.1 Editor Layout

```
+------------------------------------------+
| [X]  Theme Editor          [...]  [Save] |
|------------------------------------------|
| [ Search / filter tokens...            ] |
|------------------------------------------|
| tokenName               [color swatch]   |
| = referenceName                           |
| description text                          |
|                                           |
| tokenName2              [color swatch]   |
| ...                                       |
| (scrollable list of all palette entries)  |
+------------------------------------------+
```

- **Min dimensions:** `st::windowMinWidth` x `st::windowMinHeight`
- **Search field:** `st::defaultMultiSelect` styling, filters rows by token name substring
- **Shadow dividers** between header, content, and bottom save button

#### 25.6.2 Palette Entry Row

Each row in the scrollable list:

| Element | Position / Style |
|---------|-----------------|
| Color name | Left side, `st::themeEditorNameFont` |
| Copy reference | Below name, "= referenceName" in `st::themeEditorCopyNameFont` |
| Color swatch | Right-aligned, `st::themeEditorSampleSize` |
| Description | Below swatch, wraps to available width |

- **Row height:** `st::themeEditorMargin.top()` + `st::themeEditorSampleSize.height()` + `st::themeEditorDescriptionSkip` + font height + `st::themeEditorMargin.bottom()`
- **Color swatch rendering:** Shadow via `st::defaultRoundShadow`, transparent checkerboard pattern when alpha < 255, solid fill with the token's QColor
- **Row states:** Normal = `st::dialogsBg`, hover = `st::dialogsBgOver`, active/editing = `st::dialogsBgActive`
- **Ripple animation** on click
- **Keyboard navigation:** Arrow keys traverse rows, Page Up/Down scroll by viewport, Enter opens color edit dialog

#### 25.6.3 Color Edit Dialog

Clicking a swatch opens a hex color input. Colors entered as `#RRGGBB` or `#RRGGBBAA`. Validation requires exactly 6 or 8 hex characters after `#`. Changes apply **immediately** (live preview) via `ApplyEditedPalette()` -- the palette file is rewritten to disk at `tdata/editing-theme.tdesktop-palette` and reloaded.

#### 25.6.4 Save/Export

- **Export:** `CollectForExport()` packages palette + background into a ZIP with `.tdesktop-theme` extension. File dialog for save location.
- **Import:** File dialog with filter `"Theme files (*.tdesktop-theme *.tdesktop-palette)"`. Parses via `ParseTheme()`, rebuilds editor rows.
- **Cloud save:** Theme metadata (ID, access hash, slug) embedded in palette text between service info markers.

#### 25.6.5 Save Theme Dialog (SaveThemeBox)

| Element | Details |
|---------|---------|
| Title | "Create a new theme" or cloud theme title |
| Name field | `Ui::InputField`, pre-filled with auto-generated name or cloud title |
| Link field | `Ui::UsernameInput`, 5-64 chars, alphanumeric + underscore slug |
| Background section | Thumbnail preview, "Choose from file" button, tile checkbox |
| Width | `st::boxWideWidth` |

### 25.7 Theme Name Generator

Auto-generated names for new themes (`window_themes_generate_name.cpp`):

**Algorithm:** Takes the accent `QColor`, finds the closest match from a 101-color dictionary using weighted Euclidean distance:

```
distance = (((512 + rMean) * dr^2) >> 8) + (4 * dg^2) + (((767 - rMean) * db^2) >> 8)
```

Then randomly picks one of two patterns:
- **Pattern A:** `{Adjective} {ColorName}` -- e.g., "Sparkling Gold"
- **Pattern B:** `{ColorName} {Subjective}` -- e.g., "Azure Dream"

Word lists: 101 color names (Berry, Coral, Emerald, Azure, Amethyst, Bronze...), 97 adjectives (Ancient, Blazing, Cosmic, Enchanted, Vibrant...), 81 subjective nouns (Ambrosia, Comet, Flame, Jewel, Wonder...).

### 25.8 Chat Wallpaper System

Source: `data/data_wall_paper.h/.cpp`, `window/themes/window_theme.cpp`.

#### 25.8.1 Wallpaper Types

| Type | Flags | Description |
|------|-------|-------------|
| **Image** | none | Full document (photo), scaled to fill |
| **Pattern** | `Pattern` | SVG or image composited over gradient/solid color |
| **Gradient** | none + multiple `backgroundColors` | 1-4 color gradient, no document |
| **Solid** | none + single `backgroundColors` | Single color fill |

**Flags enum (`WallPaperFlag`):**
- `Pattern` (bit 0) -- wallpaper is a pattern overlay
- `Default` (bit 1) -- system default wallpaper
- `Creator` (bit 2) -- current user created it
- `Dark` (bit 3) -- marked as dark wallpaper

#### 25.8.2 Wallpaper Properties

| Property | Range | Details |
|----------|-------|---------|
| `backgroundColors` | 1-4 `QColor` | Base colors for gradient/solid. Pattern uses these as the underlying fill. |
| `patternIntensity` | -100 to +100 | Controls pattern visibility. Positive = `SoftLight` blend, negative = `DestinationIn` blend with darkening |
| `patternOpacity` | -1.0 to +1.0 | Computed as `intensity / 100.0` |
| `gradientRotation` | 0, 45, 90, 135, 180, 225, 270, 315 | Snapped to 45-degree increments |
| `blurred` | bool | Image blur toggle (non-pattern only) |

#### 25.8.3 Gradient Rendering

For 2-color gradients: linear gradient at the specified rotation angle. For 3-4 color gradients, the rotation animates -- `ComputeRealRotation()` doubles the base rotation, applies modulo 720, and toggles progress between 0.5 and 1.0 based on odd/even phases. The gradient image is generated via `Images::GenerateGradient()`.

#### 25.8.4 Pattern Rendering

1. Pattern image loaded from document
2. Images smaller than 512px are tiled to meet minimum size
3. **Positive intensity:** Pattern composited over solid/gradient using `QPainter::CompositionMode_SoftLight`
4. **Negative intensity:** Pattern composited using `QPainter::CompositionMode_DestinationIn` with a darkening overlay. `InvertPatternImage()` extracts alpha channel and replicates across RGB channels.
5. Pattern opacity: `abs(intensity) / 100.0`

#### 25.8.5 Image Wallpaper Processing

1. Convert to `QImage::Format_ARGB32_Premultiplied`
2. Enforce aspect ratio limit (max 40:1)
3. Downscale to maximum 2960px on longest side
4. If `blurred` flag set: apply `BlurLargeImage()` with radius 24
5. Mono-color detection via `CalculateImageMonoColor()` (for optimization)
6. Device pixel ratio adjustment applied

#### 25.8.6 Built-in Wallpaper IDs

| Wallpaper | ID (uint64) |
|-----------|-------------|
| Default | `5933856211186221059` |
| Legacy 2 | `5947530738516623361` |
| Legacy 3 | `5778236420632084488` |
| Legacy 4 | `5945087215657811969` |
| Custom (local) | Derived from legacy -1 |
| Theme-bundled | Derived from legacy -2 |

#### 25.8.7 Wallpaper Upload

Custom wallpapers are encoded as JPEG at **87% quality**. A scaled thumbnail at **320px** is generated alongside. Both are uploaded via the `account.UploadWallPaper` API method.

#### 25.8.8 Wallpaper URL Format

Shareable wallpaper links use the format:
```
bg/{slug}?bg_color=rrggbb~rrggbb~rrggbb~rrggbb&intensity=50&rotation=45&mode=blur
```

- Slug: alphanumeric wallpaper identifier
- `bg_color`: hex colors separated by `~` (multi-color) or `-` (two-color)
- `intensity`: -100 to 100
- `rotation`: gradient rotation degrees
- `mode`: `blur` if blurred

#### 25.8.9 Adaptive Service Colors

Six colors auto-adjust based on the wallpaper's average color via `Ui::ThemeAdjustedColor()`:

| Token | Purpose |
|-------|---------|
| `msgServiceBg` | Service message bubble |
| `msgServiceBgSelected` | Service message selected |
| `historyScrollBg` | Chat scroll track |
| `historyScrollBgOver` | Chat scroll track hover |
| `historyScrollBarBg` | Chat scroll thumb |
| `historyScrollBarBgOver` | Chat scroll thumb hover |

The algorithm samples the wallpaper image, computes a weighted average color, and shifts the service colors to complement it.

### 25.9 Night Mode

#### 25.9.1 Dark Detection

A theme is classified as "dark" when the `dialogsBg` token's HSV value component is below **0.5** (`kDarkValueThreshold`). This is a runtime detection, not a flag in the theme file.

#### 25.9.2 Night Mode Toggle

- **Hamburger menu:** Inline toggle switch next to "Night Mode" item. Instant switch.
- **Settings > Chat Settings:** "Auto-Night Mode" checkbox. Reads `settings->systemDarkMode()` from the OS.
- **When toggled:** Switches between the stored day theme and `":/gui/night.tdesktop-theme"` (or the user's chosen night theme).
- **Separate tile settings** maintained for day (`_tileDayValue`) and night (`_tileNightValue`).
- **System dark mode detection:** Uses OS-level APIs. When `settings->systemDarkModeEnabled()` is true, theme auto-switches on OS mode change. Disabled when `editingTheme()` is active.

#### 25.9.3 Theme Switch Confirmation

When applying a new theme, a **confirmation overlay** appears (`window_theme_warning.cpp`):

- **Countdown:** 15999ms (~16 seconds) before automatic revert
- **Title:** "Are you sure you want to keep this theme?"
- **Countdown text:** "Theme will revert in X seconds" (updates every 100ms)
- **Buttons:** "Keep Changes" (calls `KeepApplied()`), "Revert" (calls `Revert()`)
- **Dimensions:** `st::themeWarningWidth` x `st::themeWarningHeight`
- **Styling:** Rounded corners, shadow via `st::boxRoundShadow`, bg `st::boxBg`
- **Animation:** Fade in/out, duration `st::boxDuration`
- **Escape key:** Triggers revert

#### 25.9.4 Theme Revert Mechanism

1. Before applying: current palette saved to `GlobalApplying.paletteForRevert`
2. `setTestingTheme()` applies the new palette without persisting
3. If user confirms: `KeepApplied()` writes to `Local::writeTheme()`
4. If timeout/revert: `Revert()` restores saved palette and background

### 25.10 Theme Caching

Parsed themes are cached to avoid re-parsing on startup:

| Cached Field | Format | Purpose |
|--------------|--------|---------|
| `colors` | Serialized palette bytes | Full palette state |
| `background` | BMP format | Processed wallpaper image |
| `paletteChecksum` | CRC32 | Palette file integrity |
| `contentChecksum` | CRC32 | Theme ZIP integrity |
| `tileBg` | bool | Tiling flag |

On launch, if both checksums match the stored theme file, palette loading skips file parsing entirely and uses the cache.

### 25.11 Per-Chat Themes

Source: `ui/chat/chat_theme.h/.cpp`, `ui/chat/choose_theme_controller.cpp`.

#### 25.11.1 Chat Theme Data Model

Each chat theme is identified by a `ChatThemeKey` = `{uint64 id, bool dark}`. This allows the same theme emoticon to have separate light and dark variants.

**ChatThemeDescriptor** bundles:
- Key (id + dark flag)
- Palette preparation callback
- `ChatThemeBubblesData`: `vector<QColor> colors` + optional `accent` color
- `ChatThemeBackground`: prepared images (standard + tiled), gradient info, pattern opacity, fill colors
- `basedOnDark` flag

#### 25.11.2 Bubble Color Derivation

Outgoing message bubble colors are computed from the theme's accent/bubble data:

1. If `bubblesData.colors` is provided, those colors are used directly for `msgOutBg`
2. If only `accent` is provided, a **style::colorizer** maps the original `msgOutBg` HSV values to the accent's HSV
3. **Contrast validation:** If the contrast ratio between text and bubble bg falls below `kMinAcceptableContrast = 1.14`, all text colors flip to pure white (dark themes) or pure black (light themes)

#### 25.11.3 Background Rendering & Caching

- **Cache timeouts:** Fast = 200ms (`kCacheBackgroundFastTimeout`), debounced = 1000ms (`kCacheBackgroundTimeout`)
- **Transition animation:** 200ms fade (`kBackgroundFadeDuration`) between `_backgroundState.was` and `_backgroundState.now`, driven by `_backgroundFade` animation (0 to 1). Disabled when `anim::Disabled()`.
- **Gift symbol overlays:** Rendered on patterns at 0.8 opacity, skipping center position
- **Min pattern tile size:** 512px (smaller images are repeated)

#### 25.11.4 Per-Chat Theme Chooser UI

Bottom panel in chat, showing horizontal scrollable theme pills:

| Element | Style Token / Value |
|---------|-------------------|
| Preview size | `st::chatThemePreviewSize` |
| Entry margins | `st::chatThemeEntryMargin` |
| Entry spacing | `st::chatThemeEntrySkip` |
| Selection ring | Active line color border, rounded |
| Active indicator | Emoji below preview thumbnail |

Each pill renders:
1. Miniature background (gradient/pattern)
2. Two sample message bubbles (sent/received) with rounded corners
3. Emoji indicator at bottom center
4. Optional user profile picture (gift themes)

**Interaction:** Tap selects, auto-centers on current selection via `applyInitialInnerLeft()`. Drag-to-scroll via mouse tracking. Wheel events supported. Gift themes lazy-load when scroll approaches the section end.

### 25.12 Cloud Themes

Source: `data/data_cloud_themes.h/.cpp`, `window/themes/window_themes_cloud_list.cpp`.

#### 25.12.1 Cloud Theme Structure

```
CloudTheme {
    id: uint64
    accessHash: uint64
    slug: string              // URL-safe identifier
    title: string             // Display name
    emoticon: string          // Theme emoticon identifier
    documentId: uint64        // Theme file document
    createdBy: UserId
    usersCount: int
    settings: map<CloudThemeType, Settings>  // per Dark/Light
}
```

`CloudThemeType` enum: `Dark`, `Light`.

#### 25.12.2 Cloud Theme List UI

Displayed in a grid: **4 themes per row** (`kShowPerRow = 4`). Each theme rendered as a `Ui::Radiobutton` with a `CloudListCheck` widget:

- Background preview image (from theme document)
- Message bubble color indicators (sent/received)
- Radio button state indicator
- Lazy loading: shows color placeholders until theme document downloads

#### 25.12.3 Theme Sharing

**Share link format:** `addtheme/{slug}`

Right-click context menu options:
- **Share** -- copies `addtheme/{slug}` link to clipboard, shows toast "Link copied"
- **Edit** -- only for themes created by current user and currently applied
- **Delete** -- removes from cloud storage

Locally-created unsaved themes use `kFakeCloudThemeId` until synced.

#### 25.12.4 Theme Lifecycle

1. `refresh()` fetches the theme list with hash-based cache validation
2. `refreshChatThemes()` fetches per-chat theme options separately
3. Gift themes paginated via `myGiftThemesLoadMore()` with token tracking
4. Theme resolution via slug lookup
5. Document loading tracked via `LoadingDocument` struct for async retrieval

### 25.13 Theme Preview

Source: `window_theme_preview.cpp`.

Generated at `st::themePreviewSize` (plus `st::themePreviewMargin` for extended previews). Format: `QImage::Format_ARGB32_Premultiplied` with device pixel ratio.

**Layout structure:**

```
+------------------+---------------------------+
| Dialogs panel    | Top bar (name + status)   |
| (left sidebar)   |---------------------------|
| 9 conversation   | Message history area      |
| rows with:       | - Service date dividers   |
| - avatars        | - Text bubbles (in/out)   |
| - names          | - Photo bubbles           |
| - previews       | - Audio waveform bubbles  |
| - timestamps     | - Reply sections          |
| - unread badges  |---------------------------|
| - pin icons      | Compose area              |
+------------------+---------------------------+
```

Dialogs panel width: `st::themePreviewDialogsWidth`. Colors pulled from preview palette: `st::windowBg`, `st::dialogsBg`, `st::historyTextOutFg`, `st::historyTextInFg`, `st::msgServiceBg`, etc.

Message bubbles support: attachment flags (`attachToTop`, `attachToBottom`), tail rendering, outgoing/incoming status, corner rounding. Sample messages include emoji, formatted text, delivery states, pinned indicators.

### 25.14 Settings — Chat Appearance

The appearance UI in Settings > Chat Settings:

#### 25.14.1 Theme Selection Row

Radio buttons for 4 built-in themes arranged horizontally:
- Each button shows a color preview (background + bubble indicators)
- **Desired width per button:** `st::settingsThemePreviewSize.width()`
- **Min spacing between buttons:** `st::settingsThemeMinSkip`
- **Padding:** `st::settingsButtonNoIcon.padding` (left/right)
- Check mark at top corner of selected theme

#### 25.14.2 Background Row Widget

| Element | Details |
|---------|---------|
| Thumbnail | `st::settingsBackgroundThumb` (square) |
| Button spacing | `st::settingsThumbSkip` from thumbnail |
| "Choose from gallery" | Top button, `st::settingsFromGalleryTop` |
| "Choose from file" | Below gallery, offset `st::settingsFromFileTop` |
| Loading indicator | `st::radialSize`, `st::radialLine`, `st::radialBg`/`st::radialFg` |

#### 25.14.3 Additional Controls

| Control | Token / Behavior |
|---------|-----------------|
| Tile background | Checkbox, visibility depends on `paper.isPattern()` |
| Adaptive wide mode | Checkbox, syncs `Core::App().settings().adaptiveForWide()` |
| Auto-night mode | Checkbox, reads `settings->systemDarkMode()` |
| Font family | Picker dialog, triggers `Core::Restart()` on change |

### 25.15 AyuGram-Specific Theming Additions

AyuGram extends the standard theming system with several custom features. Source: `ayu/ui/settings/settings_appearance.cpp`, `ayu/ui/settings/settings_chats.cpp`, `ayu/ui/utils/palette.*`.

#### 25.15.1 Message Bubble Radius Slider

- **Control:** Slider in AyuGram > Chats settings
- **Range:** 0 to 16 (17 steps)
- **0 = sharp corners, 16 = maximum rounding**
- **Live preview** via `MessagePreview` widget that updates `setBubbleRadius()` in real-time
- **Requires app restart** on final change (shows restart prompt)

#### 25.15.2 Message Tail Removal

Toggle `removeMessageTail` removes the triangular tail from message bubbles, producing a clean rounded rectangle. No restart required.

#### 25.15.3 Material Design Switches

Toggle `materialSwitches` replaces the default Telegram checkbox/toggle style with Material Design-style switches throughout the app.

#### 25.15.4 Avatar Corner Radius

- **Slider:** 0 to `kMaxAvatarCorners` steps
- **0 = square avatars, max = circle (default)**
- **Single corner radius option:** Toggle to apply uniform radius to all corners
- **Live preview** via `AvatarCornersPreview` widget

#### 25.15.5 Custom Background Control

Toggle `disableCustomBackgrounds` disables per-chat custom backgrounds, forcing the global wallpaper everywhere.

#### 25.15.6 Simple Quotes and Replies

Toggle `simpleQuotesAndReplies` (aliases: `disableColorfulReplies`, `replyElements`) removes the colorful reply bar coloring, using a uniform style instead.

#### 25.15.7 Semi-Transparent Deleted Messages

Toggle `semiTransparentDeletedMessages` renders deleted messages (visible via AyuGram's anti-delete feature) with reduced opacity rather than full visibility. Marked as beta.

#### 25.15.8 Android-Style Palette Extraction (Ayu::Ui::Palette)

AyuGram ports Android's `androidx.palette` library to C++ for extracting dominant colors from images:

**Classes:**
- `Swatch` -- individual color + population count, auto-generates readable title/body text colors
- `Target` -- extraction target defining saturation/lightness/population weight ranges
- `Palette` -- main extractor with 6 built-in targets
- `ColorCutQuantizer` -- median-cut quantization algorithm

**6 extraction targets:**

| Target | Saturation | Lightness | Purpose |
|--------|------------|-----------|---------|
| `LIGHT_VIBRANT` | >= 0.35, target 1.0 | 0.55-1.0, target 0.74 | Bright vivid |
| `VIBRANT` | >= 0.35, target 1.0 | 0.30-0.70, target 0.50 | Standard vivid |
| `DARK_VIBRANT` | >= 0.35, target 1.0 | 0.0-0.45, target 0.26 | Deep vivid |
| `LIGHT_MUTED` | 0.0-0.40, target 0.3 | 0.55-1.0, target 0.74 | Bright subtle |
| `MUTED` | 0.0-0.40, target 0.3 | 0.30-0.70, target 0.50 | Standard subtle |
| `DARK_MUTED` | 0.0-0.40, target 0.3 | 0.0-0.45, target 0.26 | Deep subtle |

**Scoring weights:** Saturation 0.24, Lightness 0.52, Population 0.24.

**Constants:**
- Default resize area: `112 * 112` pixels (downscale before quantization)
- Default color count: 16
- Min contrast for title text: 3.0
- Min contrast for body text: 4.5
- Default filter excludes: near-black (L <= 0.05), near-white (L >= 0.95), near-red-I-line (H 10-37, S <= 0.82)

Used for extracting theme-appropriate colors from wallpaper images, profile pictures, and other media.

#### 25.15.9 Message Shot Theme Support

AyuGram's message screenshot feature supports themed rendering:
- Can use any embedded theme (DayBlue through NightGreen) or the current cloud theme
- Respects accent colors and colorful reply settings
- Background display, date visibility, reaction display are configurable per-shot

#### 25.15.10 Drawer Menu Theme Toggle

AyuGram allows showing/hiding the Night Mode toggle in the hamburger drawer menu, as well as Ghost Mode and Streamer Mode quick toggles (platform-specific visibility).

### 25.16 Pixel Dimensions Summary

| Element | Value |
|---------|-------|
| Theme file max size | 5 MB (ZIP container) |
| Palette file max size | 1 MB |
| Background image max size | 25 MB |
| Max background dimension | 2960px |
| Background aspect ratio limit | 40:1 |
| Blur radius (wallpaper) | 24px |
| Pattern min tile size | 512px |
| Wallpaper upload JPEG quality | 87% |
| Wallpaper thumbnail size | 320px |
| Gradient rotation snap | 45-degree increments |
| Pattern intensity range | -100 to +100 |
| Theme warning countdown | ~16 seconds (15999ms) |
| Theme warning update interval | 100ms |
| Background cache fast timeout | 200ms |
| Background cache debounce timeout | 1000ms |
| Background fade duration | 200ms |
| Accent animation duration | 2x `st::defaultRadio.duration` |
| Cloud theme grid columns | 4 per row |
| Color token count (Day Blue) | 369 |
| Color token count (Night themes) | 467 |
| Color token count (Day Custom Base) | 543 (with comments) |
| Peer colors | 8 (cycling by user ID) |
| Default accent palette | 8 colors per theme type |
| Colorize exclusion list | ~81 tokens |
| Bubble radius range (AyuGram) | 0-16 |
| Avatar corners slider (AyuGram) | 0 to kMaxAvatarCorners |
| Palette default resize area | 112x112 (AyuGram) |
| Palette default color count | 16 (AyuGram) |
| Min contrast title text | 3.0 (AyuGram palette) |
| Min contrast body text | 4.5 (AyuGram palette) |
| Theme name word lists | 101 colors, 97 adjectives, 81 nouns |
| Lightness clamp (colorizer) | 64-160 (Day themes) |
| Dark detection threshold | 0.5 (dialogsBg HSV value) |
| Min bubble text contrast | 1.14 (chat themes) |

---

## 26. Admin Tools

Admin tools encompass all group/channel management surfaces: editing group info, managing permissions, appointing/dismissing admins, restricting/banning members, viewing the admin log, managing invite links, and browsing member lists with role-based tabs. All dialogs use `BoxContent` (modal) or the info panel third column.

### 26.1 Group/Channel Edit Screen

Opened via the pencil icon on the group/channel info page, or from the "Edit" context menu item. Uses `EditPeerInfoBox` -- a scrollable `BoxContent` dialog.

#### 26.1.1 Layout Structure

Top-to-bottom vertical layout:

1. **Photo + Title + Description** block
2. **Settings buttons** (type, linked chat, history visibility, etc.)
3. **Admin controls** (permissions, invite links, admins, members, banned)
4. **Sticker set** (groups only)
5. **Delete group/channel** button

#### 26.1.2 Photo / Avatar

- Widget: `UserpicButton` with `Role::ChangePhoto`
- Style: `defaultUserpicButton`
- Margins: `editPeerPhotoMargins` = `margins(22px, 8px, 22px, 8px)`
- Click opens photo picker; supports custom emoji overlay via dropdown panel
- Long-press or right-click: context menu with "Set Photo", "Set Video", "Remove Photo"

#### 26.1.3 Title Field

- Style: `editPeerTitleField`
- Margins: `editPeerTitleMargins` = `margins(27px, 13px, 22px, 8px)`
- Max length: `kMaxGroupChannelTitle` (128 characters)
- Placeholder: "Group Name" / "Channel Name" / "Bot Name" (context-dependent)
- Supports emoji suggestions and instant replacements
- Auto-focused on dialog open

#### 26.1.4 Description Field

- Mode: `InputField::Mode::MultiLine`
- Margins: `editPeerDescriptionMargins` = `margins(22px, 3px, 22px, 2px)`
- Max length: `kMaxChannelDescription` (255 characters)
- Supports emoji suggestions and instant replacements

#### 26.1.5 Settings Buttons

Each button uses `Settings::AddButtonWithIcon` with left icon and right-side value label. Standard height matches `defaultSettingsButton`. Listed in order:

| Button Label | Right Value | Icon | Condition |
|---|---|---|---|
| "Group Type" / "Channel Type" | "Public" / "Private" | `menuIconCustomize` | Always |
| "Discussion Group" / "Linked Channel" | Group/channel name or "Add" | `menuIconGroups` / `menuIconChannel` | Always |
| "Direct Messages" | "Off" / "Free" / star amount | `menuIconChats` | Channels with monoforum |
| "Visible History" | "Shown" / "Hidden" | `menuIconChatBubble` | Private without location/discussion/forum |
| "Topics" | "Off" / "Tabs" / "List" | `menuIconTopics` | Groups (locked if member count too low or discussion link active) |
| "Auto-Translation" | toggle | `menuIconTranslate` | Channels at required boost level |
| "Sign Messages" | toggle | `menuIconSigned` | Channels |
| "Sign with Profile" | toggle | `menuIconSigned` | Channels (slides in when Sign Messages on) |

Divider text appears below sign messages explaining the feature.

#### 26.1.6 Admin Control Buttons

| Button Label | Right Value | Icon |
|---|---|---|
| "Permissions" | "3/7" (restrictions count) | `menuIconPermissions` |
| "Invite Links" | Active link count | `menuIconLinks` |
| "Administrators" | Formatted count | `menuIconAdmin` |
| "Members" / "Subscribers" | Formatted count | `menuIconGroups` |
| "Removed Users" | Formatted count (if > 0) | `menuIconRemove` |
| "Join Requests" | Count (if > 0) | `menuIconInvite` |

Each button navigates to the corresponding management panel.

#### 26.1.7 Sticker Set Section

- Groups only, wrapped in `SlideWrap`
- Section title: "Group Stickers" (`lng_group_stickers`)
- "Add Stickers" button with icon `menuIconStickers`
- Descriptive divider text below

#### 26.1.8 Delete Button

- Style: `manageDeleteGroupButton` (red/attention styling)
- Label: "Delete Group" / "Delete Channel"
- Click triggers confirmation dialog: "Are you sure you want to delete this group/channel?"
- Padding: `editPeerBottomButtonsLayoutMargins`

#### 26.1.9 Dialog Chrome

- Title bar: "Edit Group" / "Edit Channel" / "Edit Bot"
- Buttons: "Save" (primary) + "Cancel"
- Validation failure: scrolls to the first erroneous field

---

### 26.2 Permissions Management

Opened from the "Permissions" button on the edit screen. Uses `EditPeerPermissionsBox` -- returns `EditPeerPermissionsBoxResult { rights, slowmodeSeconds, boostsUnrestrict, starsPerMessage }`.

#### 26.2.1 Default Permissions (Restriction Toggles)

Toggle-style buttons using `rightsButton` style: `margins(22px, 8px, 22px, 8px)`, toggle skip `20px`. Each row has a text label on the left and a colored toggle on the right.

**Toggle colors:**
- Toggled (allowed): `windowBgActive` (blue)
- Untoggled (restricted): `attentionButtonFg` (red)
- Lock icon: `info/info_rights_lock` in `windowBgActive`
- Animation: `universalDuration`

**Permission groups (three nested sections):**

**Group 1 -- Text:**
| Flag | Label |
|---|---|
| `SendOther` | "Send text messages" |

**Group 2 -- Media (collapsible):**

Nested under a parent row with expand/collapse arrow (`permissionsExpandIcon`, rotates 180deg on toggle). Parent row shows checked count badge in bold: "(5/7)".

| Flag | Label |
|---|---|
| `SendPhotos` | "Send photos" |
| `SendVideos` | "Send videos" |
| `SendVideoMessages` | "Send video messages" |
| `SendMusic` | "Send music" |
| `SendVoiceMessages` | "Send voice messages" |
| `SendFiles` | "Send files" |
| `SendStickers` | "Send stickers & GIFs" |

Checkbox style inside nested group: `settingsCheckbox` with ripple overlay.

**Group 3 -- Other:**
| Flag | Label |
|---|---|
| `EmbedLinks` | "Send links" |
| `SendPolls` | "Send polls" |
| `AddParticipants` | "Add members" |
| `CreateTopics` | "Create topics" |
| `PinMessages` | "Pin messages" |
| `EditRank` | "Edit rank" |
| `ChangeInfo` | "Change group info" |

**Dependency rules:**
- "Send links" requires "Send text messages"
- All send permissions require "View Messages"
- Stickers/GIFs/Games/Inline are bidirectionally linked

**Locked permissions:** When the current admin lacks the right to edit a specific permission, clicking shows a toast notification lasting `3000ms` (`kForceDisableTooltipDuration`).

**Expand/collapse animation:** `slideWrapDuration`, easing `easeOutCubic`.

#### 26.2.2 Exceptions List

Below the default permissions, a button "Add Exception" navigates to a user picker. Each exception row shows the user name and a summary of their custom restrictions. Tapping opens `EditRestrictedBox` for that user.

#### 26.2.3 Slowmode Slider

Section header: `rightsHeaderLabel` (semibold, `windowActiveTextFg` color).

Discrete slider with `kSlowmodeValues = 8` positions:

| Index | Value | Label |
|---|---|---|
| 0 | 0s | "Off" |
| 1 | 5s | "5s" |
| 2 | 10s | "10s" |
| 3 | 30s | "30s" |
| 4 | 60s | "1m" |
| 5 | 300s | "5m" |
| 6 | 900s | "15m" |
| 7 | 3600s | "1h" |

Label positioning: first and last labels aligned to slider edges (`-(width/2)`), middle labels centered (`-inner/2`). Descriptive text below explains slowmode effect.

#### 26.2.4 Boosts Unrestrict Slider

Discrete slider with `kBoostsUnrestrictValues = 5` positions (values 1-5). Each position shows a boost emoji icon + count label. Determines how many channel boosts a user needs to bypass restrictions.

#### 26.2.5 Charge Stars (Paid Messages)

Conditional section for channels with `paidMessagesAvailable()`:
- Button: "Charge Stars" (`lng_rights_charge_stars`)
- Description text below
- Default: `kDefaultChargeStars = 10`

#### 26.2.6 Convert to Supergroup

Shown when: creator + member count exceeds `kThresholdOffset = 1000`. Suggests converting basic group to supergroup. Toast on completion.

---

### 26.3 Individual Member Restrict / Ban Dialog

`EditRestrictedBox` -- opened from member context menu or exceptions list.

#### 26.3.1 Cover Widget

Top section with user identity, using `infoEditContactCover` style:

```
photoLeft:    19px     photoTop:   18px
nameLeft:     109px    nameTop:    33px     (15px semibold font)
statusLeft:   109px    statusTop:  57px
rightSkip:    20px
```

Photo: `rightsPhotoButton` = `60x60px`, margin `rightsPhotoMargin` = `margins(20px, 0px, 15px, 18px)`.

#### 26.3.2 Permission Toggles

Same toggle list as default permissions (section 26.2.1), but applied to this specific user. Toggles that match the group default are visually indicated. Disabled toggles show explanatory text.

#### 26.3.3 Duration Picker ("Banned Until")

Radio button group (`_untilGroup`) with four options:

| Option | Label |
|---|---|
| Forever | "Ban forever" (`lng_rights_chat_banned_forever`) |
| 1 Day | "Ban for 1 day" (`lng_rights_chat_banned_day`) |
| 1 Week | "Ban for 1 week" (`lng_rights_chat_banned_week`) |
| Custom | "Custom..." (`lng_rights_chat_banned_custom`) |

Maximum restrict delay: `kMaxRestrictDelayDays = 366` days. Time constants: `kSecondsInDay = 86400`, `kSecondsInWeek = 604800`.

"Custom" opens a date/time picker. The selected date is compared against the current restriction value and old value to pre-select the matching radio button on dialog open.

#### 26.3.4 Custom Rank Field

`EditTagControl` widget for member tag/rank. Accepts session, user data, current rank string, and `BadgeRole` enum (Admin or Creator).

#### 26.3.5 Dialog Buttons

- Save: "Save" (`lng_settings_save`)
- Cancel: "Cancel" (`lng_cancel`)
- Spacing: `rightsDividerMargin` between sections, `infoProfileSkip` vertical gap

---

### 26.4 Admin Appointment Dialog

`EditAdminBox` -- opened from admin list "Add Admin" or member context menu "Promote".

#### 26.4.1 Cover Widget

Same layout as section 26.3.1 (photo 60x60, name at 109px left, 33px top).

#### 26.4.2 "Add as Admin" Checkbox

`_addAsAdmin` checkbox at top. When unchecked, the admin controls section collapses via `SlideWrap` (`_adminControlsWrap`) with `anim::type::normal` animation.

#### 26.4.3 Admin Rights Toggles

Section header: "What can this admin do?" (`lng_rights_edit_admin_header`), styled as `rightsHeaderLabel` (semibold, `windowActiveTextFg`).

**Group admin rights (3 sections):**

**Section 1 -- Core:**
| Flag | Label |
|---|---|
| `ChangeInfo` | "Change group info" |
| `DeleteMessages` | "Delete messages" |
| `BanUsers` | "Ban users" |
| `InviteByLinkOrAdd` | "Invite users via link" |
| `ManageTopics` | "Manage topics" |
| `PinMessages` | "Pin messages" |

**Section 2 -- Stories:**
| Flag | Label |
|---|---|
| `PostStories` | "Post stories" |
| `EditStories` | "Edit stories" |
| `DeleteStories` | "Delete stories" |

**Section 3 -- Meta:**
| Flag | Label |
|---|---|
| `ManageCall` | "Manage voice chats" |
| `ManageRanks` | "Manage ranks" |
| `Anonymous` | "Remain anonymous" |
| `AddAdmins` | "Add new admins" |

**Channel admin rights (4 sections):**

**Section 1:** ChangeInfo

**Section 2 -- Messages:**
| Flag | Label |
|---|---|
| `PostMessages` | "Post messages" |
| `EditMessages` | "Edit messages" |
| `DeleteMessages` | "Delete messages" |

**Section 3 -- Stories:** PostStories, EditStories, DeleteStories

**Section 4 -- Meta:** InviteByLinkOrAdd, ManageCall, ManageDirect, AddAdmins, BanUsers

Each flag uses the same `rightsButton` toggle style as permissions.

#### 26.4.4 Custom Title / Rank

`EditTagControl` below the rights toggles. Free-text field for custom admin title (e.g., "Head Moderator"). Shown with `BadgeRole::Admin` or `BadgeRole::Creator`.

#### 26.4.5 Transfer Ownership

- Button: "Transfer Group Ownership" / "Transfer Channel Ownership" (`lng_rights_transfer_group` / `lng_rights_transfer_channel`)
- Style: `peerPermissionsButton`
- Wrapped in `SlideWrap` -- only visible when ALL ownership-required rights are selected
- Click triggers a multi-step confirmation dialog (2FA password required)

#### 26.4.6 Dismiss Admin

- Button: "Dismiss Admin" (`lng_rights_dismiss_admin`)
- Style: `settingsAttentionButton` (red text)
- Confirmation dialog: "Are you sure you want to remove this admin?" (`lng_profile_sure_remove_admin`)

#### 26.4.7 Promoted-By Info

If the admin was promoted by someone else, shows "Promoted by [Name]" with a clickable link to that user's profile, plus the promotion timestamp.

---

### 26.5 Admin Log / Recent Actions

Shows a chronological log of all administrative actions in the group/channel. Opened via the group info panel or the "..." menu > "Recent Actions".

#### 26.5.1 Top Bar

Fixed bar containing:
- Back button with channel userpic and name
- Userpic skip: `historyAdminLogTopBarUserpicSkip` = `35px`
- Left padding: `historyAdminLogTopBarLeft` = `17px`
- Search toggle (magnifying glass icon)
- Search field slides in with `historyAdminLogSearchSlideDuration` = `150ms`
- Cancel search button: `historyAdminLogCancelSearch` -- `40x54px`, cross icon `32px` with `1.5px` stroke, positioned at `(6px, 11px)`, animation duration `150ms`
- Search top offset: `historyAdminLogSearchTop` = `11px`
- "What is this?" button: FAQ icon in `windowActiveTextFg`

#### 26.5.2 Event Rendering

Events render as service messages in reverse-chronological order (newest at bottom, scrolls up for older). Each event consists of:

1. **Admin name** (clickable link, `fromLink`)
2. **Action description** (italicized via `EntityType::Italic`)
3. **Optional quoted content** (for message edits, deletions, pins -- rendered as `PrepareLogMessage()` with standard message bubble)

Text preparation applies: `TextParseLinks`, `TextParseMentions`, `TextParseHashtags`, `TextParseBotCommands`.

Participant references formatted as: `"Name (@username)"` with `MentionName` entity.

#### 26.5.3 Event Types (45+ types)

**Channel/Group Settings:**
- Title change, description change, username/link change, photo change
- Invite toggle (enabled/disabled), signature toggle
- Linked chat change, slow mode change (displays duration in min/sec)
- History TTL set/remove/change, no-forwards toggle
- Anti-spam toggle, auto-translation toggle
- Peer color change (displays "#N" color index), profile color change
- Wallpaper change, emoji status set/remove/change
- Signature profiles toggle

**Message Management:**
- Message pin (with quoted original), message edit (shows old/new)
- Message deletion (with quoted deleted message), poll termination
- Admin message send

**Participant Management:**
- Join/leave, invite (with participant mention)
- Ban/unban (with `GeneratePermissionsChangeText()` showing ViewMessages flag)
- Admin promotion (skips Creator-to-Admin transitions during ownership transfers)
- Rank edit (3 variants: remove, set, change -- self vs. other)
- Mute/unmute in calls (with volume percentage, 0-10000 scale)
- Join via invite link (with optional request approval indicator)
- Approved join requests, subscription extension (with datetime)

**Permission Changes:**
- Default banned rights change (lists each changed flag: SendPhotos, SendVideos, SendMusic, SendFiles, SendVoiceMessages, SendVideoMessages, SendStickers, EmbedLinks, SendPolls, ChangeInfo, AddParticipants, CreateTopics, PinMessages, EditRank)
- User-specific restriction change (shows indefinite vs. time-limited)

**Content:**
- Sticker set change (clickable, opens `StickerSetBox`)
- Emoji sticker set change
- Available reactions change (disabled or emoji list)

**Forum/Topics:**
- Forum toggle (on/off), topic creation (icon + title link)
- Topic edit (title change, close/reopen, hide/unhide)
- Topic deletion, topic pin/unpin

**Group Calls:**
- Call start/discard (with broadcast variant)
- Call settings change (join-muted toggle)

**Invite Links:**
- Link edit (compares label, expiration, usage limit, request approval)
- Link deletion, link revocation

#### 26.5.4 Empty State

Centered text block:
- Width: `historyAdminLogEmptyWidth` = `260px`
- Padding: `historyAdminLogEmptyPadding` = `margins(10px, 12px, 10px, 12px)`
- Text: "No events found" or "No results for this filter"

#### 26.5.5 Date Headers

Floating date badge at viewport top. Tracks consecutive same-day message packs. Service message top margin: `msgServiceMargin.top()`. Date opacity animates via `_scrollDateOpacity` over `historyDateFadeDuration`. Hides after `1000ms` of scroll inactivity.

#### 26.5.6 Scroll & Interaction

- Initial page: 20 events; subsequent pages: 50 events
- Preload triggers at `PreloadHeightsCount * viewportHeight` from edges
- History padding bottom: `historyPaddingBottom`
- Message margins: `msgMargin`
- Userpic position: `historyPhotoLeft`, size: `msgPhotoSize`
- Left-click: text selection or link activation
- Double-click: word selection; triple-click: paragraph selection
- Right-click: context menu (copy, translate, save media)
- Touch: momentum scrolling with acceleration/deceleration phases

#### 26.5.7 Filter Dialog

Modal box with three collapsible sections of checkboxes. Default: all flags enabled (`~FilterValue::Flags(0)`).

**Section 1 -- Members / Subscribers:**
| Checkbox | Flags |
|---|---|
| "Admin rights" | `Promote \| Demote` |
| "Edit rank" | `EditRank` |
| "Restrictions" | `Ban \| Unban \| Kick \| Unkick` |
| "New members/subscribers" | `Join \| Invite` |
| "Removed members/subscribers" | `Leave` |

**Section 2 -- Settings:**
| Checkbox | Flags |
|---|---|
| "Info and settings" | `Info \| Settings` |
| "Invite links" | `Invites` |
| "Voice chats" | `GroupCall` |
| "Subscription extensions" | `SubExtend` |
| "Topics" (groups only) | `Topics` |

**Section 3 -- Messages:**
| Checkbox | Flags |
|---|---|
| "Deleted messages" | `Delete` |
| "Edited messages" | `Edit` |
| "Pinned messages" (groups only) | `Pinned` |

Labels adjust for channel context ("subscribers" vs "members"). An optional admin-by-admin filter (`std::optional<std::vector<UserData*>>`) restricts events to specific admins.

**Filter flags enum** (19 flags, `uint32`):
```
Join=0, Leave=1, Invite=2, Ban=3, Unban=4, Kick=5, Unkick=6,
Promote=7, Demote=8, Info=9, Settings=10, Pinned=11, Edit=12,
Delete=13, GroupCall=14, Invites=15, Topics=16, SubExtend=17, EditRank=18
```

---

### 26.6 Invite Links Management

Opened from "Invite Links" button on the edit screen. Uses `InviteLinksBox` with `boxWideWidth`.

#### 26.6.1 Section Structure

Top-to-bottom layout:

1. **Permanent link** display (always present if exists)
2. **"Create a New Link"** button -- style: `inviteLinkCreate`, icon size: `inviteLinkCreateIconSize`, skip: `inviteLinkCreateSkip`
3. **Active links list** -- header: "My Links" or admin name
4. **Revoked links section** -- header with "Delete All Revoked Links" button, title padding: `inviteLinkRevokedTitlePadding`
5. **Other Admins** section -- list of admins who created links, showing per-admin invite count in parentheses

#### 26.6.2 Link Row Rendering

Each row uses `inviteLinkList` style with standard item dimensions:
- Photo position and size from `inviteLinkList.item.photoPosition` / `.photoSize`
- Icon skip: `inviteLinkIconSkip`
- Icon stroke: `inviteLinkIconStroke`

**Left icon:** Circular badge with color-coded background and progress arc.

**Color states (6 total):**
| State | Condition | Color Token |
|---|---|---|
| Permanent | No expiry, no usage limit | `msgFile1Bg` (green) |
| Expiring | 0 <= progress < 0.75 | `msgFile2Bg` (blue) |
| Expire Soon | 0.75 <= progress < 1.0 | `msgFile4Bg` (orange) |
| Expired | progress >= 1.0 | `msgFile3Bg` (red) |
| Revoked | Link revoked | `windowSubTextFg` (gray) |
| Subscription | Subscription link | `msgFile2Bg` (blue) |

**Progress computation:** `max(expirationProgress, usageProgress)` where:
- `expirationProgress = (now - startDate) / (expireDate - startDate)`
- `usageProgress = usage / usageLimit`
- Returns `-1` if no limits (permanent)

**Progress arc:** Rounded-cap arc on the circle perimeter. Arc span = `fullLength * (1 - progress)` with quarter-length offset. Timer updates every `~1/720th` of expiration duration.

**Row text:**
- Name: link label or formatted URL (stripped of `https://`, `t.me/+`, `t.me/joinchat/`)
- Status: usage count (`lng_group_invite_joined`), remaining slots, days left (`lng_group_invite_days_left`)

**Three-dots menu:** Icon dimensions: `inviteLinkThreeDotsIcon.width()` x `.height()`, skip: `inviteLinkThreeDotsSkip`

#### 26.6.3 Link Context Menu

| Action | Icon | Condition |
|---|---|---|
| Copy Link | `menuIconCopy` | Always |
| Share Link | `menuIconShare` | Always |
| QR Code | `menuIconQrCode` | Always |
| Edit Link | `menuIconEdit` | Not revoked, not bot admin |
| Revoke Link | `menuIconRemove` | Not revoked, not bot admin |
| Delete Link | `menuIconDelete` | Revoked only |

#### 26.6.4 Single Link Info Box

Opened by clicking a link row. Layout:

1. **Link label** (`InviteLinkLabel`) -- displays URL with `https://` stripped. Click copies. Context menu with Copy/Share/QR/Edit/Revoke.
2. **Copy + Share buttons** -- hidden when revoked or expired. Standard `AddCopyShareLinkButtons` layout.
3. **Reactivate button** -- shown when expired but not revoked, admin is not bot.
4. **Usage/expiry divider:**
   - Normal: `boxDividerLabel` (gray)
   - Expired: `boxAttentionDividerLabel` (red)
   - Usage exhausted: `boxTextFgError` color
5. **Joined users list** -- first page: 20, subsequent: 100. Pagination via scroll.
6. **Joined userpic strip** -- max `kMaxShownJoined = 3` overlapping avatars in header area.
7. **Max height:** `boxMaxListHeight`

#### 26.6.5 QR Code Dialog

`InviteLinkQrBox` delegates to `FillPeerQrBox`:
- Pixel size: `inviteLinkQrPixel`
- Scales to fit: `boxWidth - boxRowPadding.left() - boxRowPadding.right()`
- Centered in dialog

#### 26.6.6 Create / Edit Link Form

`EditInviteLinkBox` / `CreateInviteLinkBox`:

**Fields:**

1. **Label** -- text input, max 32 characters. Header: "Link Name"
2. **Expiration** -- radio button group. Header: "Expire After"

| Option | Value |
|---|---|
| Never | `kMaxLimit` (unlimited) |
| 1 hour | 3600s |
| 1 day | 86400s |
| 7 days | 604800s |
| Custom | Opens date/time picker |

Default: 30 days (2,592,000s); test mode: 300s.

3. **Usage limit** -- radio button group. Header: "Usage Limit"

| Option | Value |
|---|---|
| Unlimited | `kMaxLimit` |
| 1 use | 1 |
| 10 uses | 10 |
| 100 uses | 100 |
| Custom | Numeric input |

4. **Request Approval** -- toggle button. "Approve New Members". Disabled for public or subscription-locked links. When enabled, usage limit section slides away via `SlideWrap`.

5. **Subscription Credits** -- `NumberInput` field (read-only when locked). Only for channel subscription links.

Section spacing: `defaultVerticalListSkip`. Divider labels adjust text based on approval state.

**Return struct:** `InviteLinkFields { link, label, expireDate, usageLimit, subscriptionCredits, requestApproval, isGroup, isPublic }`

#### 26.6.7 Admin Links List

Style: `inviteLinkAdminsList`. Each row shows admin avatar, name, and invite link count. Clicking opens that admin's links in a filtered view.

---

### 26.7 Member List with Role Tabs

`EditParticipantsBox` with `ParticipantsBoxController`. Five role views accessed as separate screens from the edit group page.

#### 26.7.1 Roles

| Role | Entry Point | Search Type |
|---|---|---|
| `Members` | "Members" button | `channelParticipantsSearch` |
| `Admins` | "Administrators" button | `channelParticipantsSearch` |
| `Restricted` | "Exceptions" / restricted list | `channelParticipantsBanned` |
| `Kicked` | "Removed Users" button | `channelParticipantsKicked` |
| `Profile` | Info panel members section | All members |

#### 26.7.2 Search

Integrated search bar at top (`PeerListSearchMode::Enabled`). Server-side queries with `AutoSearchTimeout` debounce after user input. Results cached per query. Empty states: "Loading..." initially, "No participants found" when empty.

#### 26.7.3 Pagination

- First page: `kParticipantsFirstPageCount = 16`
- Subsequent pages: `kParticipantsPerPage = 200`
- Online sort delay: `kSortByOnlineDelay = 1000ms`

#### 26.7.4 Row Rendering

Standard `peerListBoxItem` layout:
```
height:         56px
photoSize:      42px (contactsPhotoSize)
namePosition:   point(74px, 9px)
statusPosition: point(74px, 30px)
```

Each row displays:
- **Avatar** (42px, left-aligned)
- **Name** (semibold) with optional admin/creator badge
- **Status line:** custom rank (e.g., "Head Moderator"), restriction reason, or last-seen / "online" / bot capabilities ("reads all history" / "doesn't read all history")
- **Right action:** context-dependent (remove button, etc.)

#### 26.7.5 Sorting

Members sorted by online status. Binary search finds the threshold between online and offline users. Re-sort batched with 1-second delay to prevent excessive reflows.

#### 26.7.6 Add Button

Top of list, behavior varies by role:
- **Members:** opens `AddParticipantsBox` (invite new users, forwards last `kForwardMessagesOnAdd = 100` messages for context)
- **Admins:** opens `AddSpecialBoxController` for admin selection
- **Restricted / Kicked:** opens `AddSpecialBoxController` for restriction target selection
- Visibility gated on permissions: `canAddMembers`, `canAddAdmins`, `canBanMembers`

#### 26.7.7 Context Menu

Right-click / long-press on a member row:

| Action | Condition |
|---|---|
| "View Profile" / "View Channel" | Always |
| "Edit Member Tag" | Self or has ManageRanks right |
| "Promote to Admin" | Has AddAdmins right |
| "Restrict User" | Has BanUsers right |
| "Remove from Group" | Has BanUsers right |
| "Remove from Banned" | Kicked tab, megagroup only |
| "Promoted by [Name] on [Date]" | Admin tab, info line |
| "Restricted by [Name] on [Date]" | Restricted tab, info line |

#### 26.7.8 Members Info Panel Section

`InfoMembersWidget` in the third column:
- Header height: `infoMembersHeader` = `56px`
- Button position: `infoMembersButtonPosition` = `point(12px, 0px)`
- Button size: `38x38px`
- Search top: `infoMembersSearchTop` = `15px`
- Title: "Participants" (groups) / "Subscribers" (channels)

---

### 26.8 Banned Users List

Accessed from "Removed Users" button on the edit screen. Uses the `Kicked` role of `ParticipantsBoxController`.

- Same row layout as section 26.7.4
- Status line shows ban reason or "Banned" with restriction details
- Context menu: "Unban" (remove from banned list), "View Profile"
- Search: server-side via `channelParticipantsKicked` filter
- "Add to Banned" button at top (if `canBanMembers`)
- Unbanning triggers `MTPchannels_EditBanned` with empty restrictions

---

### 26.9 Slow Mode Settings

Configured within the permissions dialog (section 26.2.3). Not a separate screen.

**Behavior:**
- When enabled (any value > 0), non-admin members can only send one message per interval
- The send button shows a countdown timer during the cooldown period
- Admins and bots are exempt from slowmode
- Setting saved via `MTPchannels_ToggleSlowMode` with seconds parameter

**Slider interaction:** Discrete snap positions only (no freeform). Drag or click to select. Current value highlighted. Label rows render at calculated offsets to prevent overlap at edges.

---

### 26.10 Anti-Spam Settings

Toggle within the group edit screen. Admin log records boolean state changes (`anti_spam_enabled` / `anti_spam_disabled`).

- Requires supergroup with sufficient member count
- Toggle button in settings section with standard `defaultSettingsButton` styling
- When enabled, Telegram's built-in ML filter automatically deletes spam and reports to admin log
- Admin log shows "toggled anti-spam" events as service messages

---

### 26.11 Pixel Dimensions Summary

| Token | Value | Usage |
|---|---|---|
| `rightsPhotoButton` | `60x60px` | User photo in restrict/admin dialogs |
| `rightsPhotoMargin` | `20px, 0px, 15px, 18px` | Photo spacing in restrict/admin dialogs |
| `rightsNameStyle` | `15px semibold` | User name in cover widget |
| `rightsNameTop` | `8px` | Name vertical offset (relative to cover) |
| `rightsStatusTop` | `32px` | Status vertical offset |
| `rightsButton padding` | `22px, 8px, 22px, 8px` | Permission toggle row padding |
| `rightsToggle stroke` | `2px` | Toggle border width |
| `rightsToggle duration` | `universalDuration` | Toggle animation time |
| `rightsHeaderLabel` | semibold, `windowActiveTextFg` | Section header in permissions |
| `editPeerPhotoMargins` | `22px, 8px, 22px, 8px` | Edit screen avatar spacing |
| `editPeerTitleMargins` | `27px, 13px, 22px, 8px` | Edit screen title field spacing |
| `editPeerDescriptionMargins` | `22px, 3px, 22px, 2px` | Edit screen description spacing |
| `infoProfileCover height` | `108px` | Cover widget total height |
| `infoProfileCover photoLeft` | `19px` | Photo horizontal offset |
| `infoProfileCover photoTop` | `18px` | Photo vertical offset |
| `infoProfileCover nameLeft` | `109px` | Name horizontal offset |
| `infoProfileCover nameTop` | `32px` (edit: `33px`) | Name vertical offset |
| `infoProfileCover statusLeft` | `109px` | Status horizontal offset |
| `infoProfileCover statusTop` | `58px` (edit: `57px`) | Status vertical offset |
| `infoProfileCover rightSkip` | `20px` | Right margin for name/status |
| `infoMembersHeader` | `56px` | Members section header height |
| `infoMembersButtonPosition` | `12px, 0px` | Add-member button offset |
| `infoMembersButton` | `38x38px` | Add-member button size |
| `infoMembersSearchTop` | `15px` | Search field top offset |
| `peerListBoxItem height` | `56px` | Member list row height |
| `peerListBoxItem photoSize` | `42px` | Member avatar diameter |
| `peerListBoxItem namePos` | `74px, 9px` | Name position in row |
| `peerListBoxItem statusPos` | `74px, 30px` | Status position in row |
| `historyAdminLogEmptyWidth` | `260px` | Empty state text width |
| `historyAdminLogEmptyPadding` | `10px, 12px, 10px, 12px` | Empty state padding |
| `historyAdminLogCancelSearch` | `40x54px` | Cancel search button |
| `historyAdminLogSearchTop` | `11px` | Search field offset |
| `historyAdminLogSearchSlideDuration` | `150ms` | Search animation |
| `historyAdminLogTopBarLeft` | `17px` | Top bar left padding |
| `historyAdminLogTopBarUserpicSkip` | `35px` | Userpic-to-text skip |
| `inviteLinkQrPixel` | style-defined | QR code module pixel size |
| `inviteLinkRevokedTitlePadding` | style-defined | Revoked section header padding |
| `kFirstPage` (invite joined) | `20` | Initial joined-users page |
| `kPerPage` (invite joined) | `100` | Subsequent pages |
| `kMaxShownJoined` | `3` | Overlapping userpic count |
| `kParticipantsFirstPageCount` | `16` | Initial member list page |
| `kParticipantsPerPage` | `200` | Subsequent member pages |
| `kSortByOnlineDelay` | `1000ms` | Online sort debounce |
| `kForwardMessagesOnAdd` | `100` | Messages forwarded on invite |
| `kSlowmodeValues` | `8` | Slowmode slider positions |
| `kBoostsUnrestrictValues` | `5` | Boosts slider positions |
| `kMaxRestrictDelayDays` | `366` | Max ban duration (days) |
| `kForceDisableTooltipDuration` | `3000ms` | Locked-permission toast |
| `kDefaultChargeStars` | `10` | Default paid message stars |
| `kThresholdOffset` | `1000` | Supergroup convert threshold |


## 27. Passcode Lock Screen

Local passcode protects the app from unauthorized access on a shared device. Unlike cloud password (2FA for Telegram account login), local passcode locks the desktop client only and is stored as a hash in the local database. All code lives in `boxes/passcode_box.cpp`, `window/window_lock_widgets.cpp`, `settings/sections/settings_local_passcode.cpp`, `boxes/auto_lock_box.cpp`, and `core/application.cpp`.

---

### 27.1 Settings Entry Point (Privacy & Security)

In **Settings > Privacy & Security**, a single row provides the passcode entry point:

- **Row ID:** `"security/passcode"`
- **Icon:** `st::menuIconLock` (lock icon, left of title)
- **Title:** "Local passcode" (`tr::lng_settings_passcode_title`)
- **Label:** Reactive -- shows "On" (`tr::lng_settings_cloud_password_on`) when a passcode is set, "Off" (`tr::lng_settings_cloud_password_off`) when not. Updates live via `localPasscodeChanged()` stream.
- **Searchable keywords:** "passcode", "lock", "pin"

**Click behavior:**
- If passcode **exists**: navigates to `LocalPasscodeCheck` (verify current passcode first).
- If passcode **does not exist**: navigates to `LocalPasscodeCreate` (set new passcode).

---

### 27.2 Passcode Create Flow

Full-page settings section (not a dialog box). Three visual zones stacked vertically:

**Lottie animation:** `"local_passcode_enter"` at `st::normalBoxLottieSize` (centered, top of page). Plays on `_showFinished` event.

**Two password input fields:**
- Style: `st::settingLocalPasscodeInputField` (inherits `defaultInputField`, width **256px**).
- First field placeholder: "Enter a passcode" / "Enter passcode for the first time".
- Second field placeholder: "Re-enter your passcode" / "Confirm new passcode".
- Both are `Ui::PasswordInput` (masked, dots replace characters).
- Centered horizontally within the settings page.

**Description text:** `st::settingLocalPasscodeDescription` (minWidth 256px, height ~53px via `settingLocalPasscodeDescriptionHeight`). Explains what local passcode does. Bottom skip: 15px (`settingLocalPasscodeDescriptionBottomSkip`).

**Icon padding:** `margins(0px, 19px, 0px, 5px)` (`settingLocalPasscodeIconPadding`).
**Button padding:** `margins(0px, 19px, 0px, 35px)` (`settingLocalPasscodeButtonPadding`).

**Validation on submit:**
1. Both fields must be non-empty -- if empty, the empty field gets focus and shows error state (border turns `activeLineFgError`, 150ms transition).
2. Fields must match -- if mismatch, error label appears: "Passcodes don't match" (`tr::lng_passcode_differ`). Error label style: `st::settingLocalPasscodeError` (minWidth 256px, uses `attentionButtonFg` color).
3. On success: calls `SetPasscode()` which resets bad-tries counter, stores hash via `domain.local().setPasscode()`, fires `Core::App().localPasscodeChanged()`. Then offers system unlock setup (platform-dependent) and transitions to `LocalPasscodeManage`.

**Error label behavior:** Shown below input fields. Hides automatically when user types in either field (`changed()` callback clears error text).

---

### 27.3 Passcode Check Flow (Verify Current)

Single-field settings page for verifying the current passcode before accessing management options.

**Input:** One `Ui::PasswordInput` field, style `st::settingLocalPasscodeInputField` (256px wide), placeholder "Enter your passcode".

**Lottie animation:** Same `"local_passcode_enter"` at `st::normalBoxLottieSize`.

**Validation:**
1. Empty field: focus + error state on field.
2. Flood protection: `passcodeCanTry()` check -- if too many recent failures, shows "Please try again later" (`tr::lng_flood_error`).
3. Wrong passcode: increments `cPasscodeBadTries()`, records `cPasscodeLastTry(crl::now())`, shows "Wrong passcode" (`tr::lng_passcode_wrong`) in error label (`st::settingLocalPasscodeError`).
4. Correct passcode: resets bad-tries counter to 0, navigates to `LocalPasscodeManage`.

---

### 27.4 Passcode Management Page

After successful verification, displays the management options:

**1. Change Passcode button**
- ID: `"passcode/change"`
- Icon: `st::menuIconLock`
- Navigates to `LocalPasscodeChange` (two-field flow, same as Create but validates new != current).

**2. Auto-Lock button**
- ID: `"passcode/auto-lock"`
- Icon: `st::menuIconTimer`
- Title: "Lock on user inactivity" / "Lock after inactivity"
- **Label:** Formatted duration from current `Core::App().settings().autoLock()` value. Displays as hours/minutes combination (e.g., "1 min", "5 min", "1 hr", "5 hrs", or "2 hrs 30 min" for custom values).
- Click opens `AutoLockBox` modal (see 27.6).
- Label refreshes on `autoLockBoxClosing` event.

**3. System Unlock toggle** (conditional -- only shown when platform supports it)
- Platform detection determines type and label:
  - **Windows:** "Use Windows Hello" with `st::menuIconWinHello`
  - **macOS (biometrics):** "Use Touch ID" with `st::menuIconTouchID`
  - **macOS (companion):** "Use Apple Watch" with `st::menuIconAppleWatch`
  - **Generic fallback:** "Use system password" with `st::menuIconPermissions`
- Toggle saves immediately via `Core::App().settings().setSystemUnlockEnabled()`.

**4. Disable Passcode button** (pinned to bottom)
- ID: `"passcode/disable"`
- Shows confirmation dialog before removal.
- On confirm: calls `SetPasscode(controller, QString())` (empty string removes passcode), also disables system unlock.

**Layout:** Standard settings page with skip spacing between sections, divider text combining descriptions.

---

### 27.5 Passcode Change Flow

Two-field settings page, identical layout to Create (27.2) but with additional validation:

- First field: "Enter a new passcode"
- Second field: "Re-enter your new passcode"
- **Extra rule:** New passcode must differ from current. If same, shows "The passcode is the same" (`tr::lng_passcode_is_same`).
- Auto-close timer: Uses `CloudPassword::SetupAutoCloseTimer` -- if user is idle on this page too long, it auto-navigates back (security measure).
- On success: calls `SetPasscode()` with new value, navigates back.

---

### 27.6 Auto-Lock Timer Dialog (AutoLockBox)

Modal dialog box (`Ui::BoxContent`). Width: **320px** (`st::boxWidth`). Padding: `margins(24px, 14px, 24px, 8px)` (`st::boxPadding`).

**Preset options as radio buttons**, spaced with `st::boxOptionListSkip` (20px) vertical gap:

| Option | Value (seconds) | Display |
|--------|----------------|---------|
| 1 minute | 60 | "1 minute" |
| 5 minutes | 300 | "5 minutes" |
| 1 hour | 3600 | "1 hour" |
| 5 hours | 18000 | "5 hours" |
| Custom | user-defined | HH:MM input |

**Custom option:** When selected, reveals a time input field (HH:MM format) aligned alongside the radio button. Validation: parses by splitting on `:`, calculates `hours * 3600 + minutes * 60`. Invalid format triggers error display.

**Buttons:** "Save" + "Cancel" (standard box button row).

**On save:** `Core::App().settings().setAutoLock(seconds)`, `Core::App().saveSettingsDelayed()`, `Core::App().checkAutoLock()` -- immediately re-evaluates whether the app should lock.

**Current selection:** Pre-selects the radio matching `Core::App().settings().autoLock()`. If current value doesn't match any preset, "Custom" is selected with the value pre-filled.

---

### 27.7 Passcode Dialog Box (Legacy/Cloud)

The `PasscodeBox` (`boxes/passcode_box.cpp`) is a modal dialog (`Ui::BoxContent`) used for both local passcode and cloud password operations. Width: **320px** (`st::boxWidth`).

**Input fields** (visibility depends on mode):
- `_oldPasscode`: Current passcode/password. Width: `boxWidth - boxPadding.left - boxPadding.right` = 320 - 24 - 24 = **272px**. Position: x=24px (`st::boxPadding.left`), y=top of padding area (`st::passcodePadding.top`, ~5px from the zero-padding bottom value).
- `_newPasscode`: New passcode/password. Same width. Y = oldPasscode.y + oldPasscode.height + `st::passcodeTextLine` (28px) + optional hint line (28px if hint shown and recovery link visible).
- `_reenterPasscode`: Confirm new. Y = newPasscode.y + newPasscode.height + `st::passcodeLittleSkip` (5px).
- `_passwordHint`: Cloud password hint. Y = reenterPasscode.y + reenterPasscode.height + `st::passcodeSkip` (23px).
- `_recoverEmail`: Recovery email (cloud only). Y = passwordHint.y + passwordHint.height + `st::passcodeLittleSkip` (5px) + aboutHeight + `st::passcodeLittleSkip` (5px).

**About text:** Drawn below fields. Style: `st::passcodeTextStyle` (lineHeight 20px). Color: `st::boxTextFg`. Position: x=24px, y calculated from last visible field + field height + `st::passcodeLittleSkip` + `st::passcodeAboutSkip` (7px). Text width: `st::boxWidth - st::boxPadding.left - st::boxPadding.right` = 272px.

**Hint text:** When a password hint exists and no error is showing, drawn below oldPasscode field. Font: `st::normalFont`. Y: oldPasscode.y + oldPasscode.height + `(passcodeTextLine - normalFont.height) / 2` (vertically centered in the 28px line).

**Error text:** Color: `st::boxTextFgError` (red/attention color). Drawn in the same 28px line area below oldPasscode. Replaces hint text when visible.

**Dialog buttons:**
- Turning off passcode: "Remove" (`tr::lng_passcode_remove_button`) + "Cancel"
- Setting/changing: "Save" (`tr::lng_settings_save`) + "Cancel"
- Cloud with custom label: uses `_cloudFields.customSubmitButton`

**Recovery link:** `_recover` link widget, shown for cloud passwords. Hidden on wrong passcode if hint is empty.

**Validation in save():**
1. Flood check: `passcodeCanTry()` -- if blocked, shows "Flood error" and error state on old field.
2. Old passcode verification: `domain.local().checkPasscode(old.toUtf8())`. On fail: increments `cPasscodeBadTries`, records `cPasscodeLastTry`, calls `badOldPasscode()`.
3. New field empty: focus + error state.
4. Mismatch: "Passcodes don't match" (`tr::lng_passcode_differ`), selects all in reenter field.
5. Same as old: "The passcode is the same" (`tr::lng_passcode_is_same`).
6. Cloud-specific: hint == password check ("Password hint must be different from password", `tr::lng_cloud_password_bad`).

**Tab order (submit/Enter key):** Old -> New -> Reenter -> Hint -> Email -> save(). Each Enter press moves to the next non-hidden field; final Enter triggers save.

---

### 27.8 Lock Screen (PasscodeLockWidget)

Full-window overlay that replaces the entire app UI when locked. Implemented as `PasscodeLockWidget` inheriting from `LockWidget`, which inherits from `Ui::RpWidget`.

**Background:** Solid fill with `st::windowBg` (white in day theme, dark in night theme). Covers the entire window.

**Layout (resizeEvent positioning):**

| Element | X position | Y position |
|---------|-----------|-----------|
| Header text | Centered (full width) | `_passcode.y - st::passcodeHeaderHeight` (80px above input) |
| Passcode input | `(width - inputWidth) / 2` (centered) | `height / 3` (one-third down the window) |
| Error text | Centered (full width) | `_passcode.y + _passcode.height` to `_passcode.y + _passcode.height + st::passcodeSubmitSkip` |
| Submit button | Same x as `_passcode` | `_passcode.y + _passcode.height + st::passcodeSubmitSkip` (40px below input) |
| Logout link | Centered within `_passcode` width | `_submit.y + _submit.height + st::linkFont.ascent` |

**Header text:**
- Content: "Please enter your passcode" (`tr::lng_passcode_enter`)
- Font: `st::passcodeHeaderFont` -- **19px**.
- Color: `st::windowFg`.
- Alignment: `style::al_center` (horizontally centered, vertically within the 80px header zone).

**Passcode input field:**
- Style: `st::passcodeInput` -- inherits from `introPhone` (which inherits `introCountry`).
- Width: **225px** (inherited from `introPhone`). Height: ~61px (from `introCountry` base).
- Text margins: `margins(1px, 27px, 1px, 6px)` -- 1px left/right, 27px top, 6px bottom.
- Masked input (password dots).
- Placeholder: "Your passcode" (`tr::lng_passcode_ph`).

**Submit button:**
- Style: `st::passcodeSubmit` -- inherits from `introNextButton`.
- Width: **225px**. Height: **42px**. Border radius: **6px**.
- Font: semibold, `boxFontSize`. Text top padding: 11px.
- Colors: inherited from `defaultActiveButton` (blue background, white text).
- Label: "Submit" (`tr::lng_passcode_submit`).

**Logout link:**
- Text: "Log out" (`tr::lng_passcode_logout`).
- Style: standard link (clickable, underlined on hover).
- Positioned centered below the submit button, offset by link font ascent.

**Error text:**
- Font: `st::boxTextFont`.
- Color: `st::boxTextFgError` (red/attention color).
- Alignment: `style::al_center`.
- Drawn in the 40px gap between input and submit button.
- Content: "Wrong passcode" (`tr::lng_passcode_wrong`) on failed attempt.

**System unlock button** (conditional):
- Style: `st::passcodeSystemUnlock` -- `IconButton`, 32x36px, icon at `point(4px, 4px)`, ripple area 32px.
- Icons vary by platform:
  - Touch ID: `st::passcodeSystemTouchID` (`"menu/passcode_finger"`, color `lightButtonFg`)
  - Apple Watch: `st::passcodeSystemAppleWatch` (`"menu/passcode_watch"`, color `lightButtonFg`)
  - System password: `st::passcodeSystemSystemPwd` (`"menu/permissions"`, color `lightButtonFg`)
- "Unlock later" label: `st::passcodeSystemUnlockLater` (`defaultFlatLabel`, align top, color `windowSubTextFg`).
- Skip between system unlock elements: **12px** (`st::passcodeSystemUnlockSkip`).
- Cooldown delay: **1000ms** (`kSystemUnlockDelay`) before retry after failed system unlock attempt.

---

### 27.9 Lock Screen Transition Animation

When the lock screen appears, the current UI is captured as a pixmap snapshot and the lock widget slides in:

**Slide animation:**
- Uses `Window::SlideAnimation` (defined in `lib_ui/ui/effects/slide_animation.cpp`).
- Easing: `anim::easeOutCirc` for arriving content, `anim::easeInCirc` for departing content.
- The old content snapshot slides out while the lock screen slides in simultaneously.
- Opacity crossfade: departing content fades out, arriving content fades in.
- Duration: Caller-specified (typically matches the standard section transition duration, ~150-200ms).

**Setup sequence (`MainWindow::setupPasscodeLock()`):**
1. Capture current UI as pixmap via `grabForSlideAnimation()` (only if `_main` or `_intro` exists).
2. Create `_passcodeLock` widget on `bodyWidget()`.
3. Update controls geometry.
4. Instantly hide settings/layers via `ui_hideSettingsAndLayer(anim::type::instant)`.
5. Hide `_main` and `_intro` widgets.
6. If animated: call `_passcodeLock->showAnimated(oldContentCache)`. Otherwise: `showFinished()` + `setInnerFocus()`.
7. Close any open web view attachments.

**Clear sequence (`MainWindow::clearPasscodeLock()`):**
1. Requires `_intro` or `_main` to exist.
2. Destroys `_passcodeLock` widget.
3. Restores previous UI widgets.

---

### 27.10 Error Handling & Brute-Force Protection

**Input field error animation:**
- On `showError()`: field border transitions from normal to `borderFgError` / `activeLineFgError` color.
- Animation duration: **150ms** (`st::defaultInputField.duration`).
- Uses `_a_error` animation interpolating 0.0 to 1.0 (error on) or 1.0 to 0.0 (error off).
- Simultaneously triggers `startBorderAnimation()` for the underline/border highlight.
- Text in field is selected (`selectAll()`).
- Field receives focus.
- No pixel-displacement shake -- error is communicated via color change + text selection.

**Bad-tries tracking (global state):**
- `cPasscodeBadTries()`: Counter, incremented on each wrong attempt.
- `cPasscodeLastTry()`: Timestamp (`crl::now()`) of last failed attempt.
- `passcodeCanTry()`: Returns false if too many recent failures (flood protection). When blocked, shows "Please try again later" (`tr::lng_flood_error`).
- Reset to 0 on successful entry.

**Error text lifecycle:**
1. Wrong passcode entered -> error string set, `update()` called, field shows error state.
2. User types any character -> `changed()` callback clears error string, `update()` called.
3. Next submit attempt re-evaluates.

---

### 27.11 Keyboard Shortcut: Ctrl+L

Defined in `core/shortcuts.cpp`:

- **Command name:** `"lock_telegram"` mapped to `Command::Lock` enum.
- **Default binding:** `Ctrl+L` (set in `Manager::fillDefaults()`).
- **Handler:** Triggers `Core::App().maybeLockByPasscode()` which calls `lockByPasscode()` wrapped in `preventOrInvoke()` (ensures UI is in a safe state before locking).
- **Prerequisite:** Only effective when a local passcode is set (`domain.local().hasLocalPasscode()`). If no passcode exists, the shortcut does nothing.

---

### 27.12 Auto-Lock Timer

Defined in `core/application.cpp`. Automatically locks the app after user inactivity.

**Timer setup:**
- `_autoLockTimer`: `base::Timer`, initialized in `Application` constructor with callback `checkAutoLock()`.
- `_shouldLockAt`: `crl::time` timestamp when lock should trigger.
- `_lastNonIdleTime`: Updated on every user interaction via `updateNonIdle()`.

**checkAutoLock() algorithm:**
1. **Guard:** If no local passcode, already locked, or no active session -> cancel timer, set `_shouldLockAt = 0`, return.
2. Get `lastNonIdleTime` (from parameter or stored value).
3. Calculate `shouldLockInMs = settings().autoLock() * 1000` (auto-lock setting is in seconds, converted to ms).
4. Calculate `checkTimeMs = now - lastNonIdleTime`.
5. **If idle long enough** (`checkTimeMs >= shouldLockInMs`) OR **if late** (`now > _shouldLockAt + kAutoLockTimeoutLateMs`): lock immediately via `lockByPasscode()`.
6. **Otherwise:** Schedule timer for `shouldLockInMs - checkTimeMs` remaining.

**Late timeout grace:** `kAutoLockTimeoutLateMs = 3000ms` (3 seconds). If the system clock jumped or the timer fired late, this provides a buffer before force-locking.

**lockByPasscode() sequence:**
1. Set `_passcodeLock = true` (reactive variable).
2. Enumerate all windows, call `setupPasscodeLock()` on each.
3. Close media viewer if open.

**unlockPasscode() sequence:**
1. `clearPasscodeLock()` -- resets bad-tries to 0, sets `_passcodeLock = false`.
2. Enumerate all windows, call `clearPasscodeLock()` on each.

**localPasscodeChanged():** Called when passcode is set/removed/changed. Resets `_shouldLockAt` to 0, cancels timer, then calls `checkAutoLock(crl::now())` to re-evaluate (e.g., if passcode was just removed, auto-lock is disabled).

---

### 27.13 Notification Behavior When Locked

When the app is passcode-locked, the notification system enforces privacy:

**Content hiding:**
```
hideEverything = Core::App().passcodeLocked() || forceHideDetails()
```
When `hideEverything` is true:
- Sender names hidden.
- Message text hidden.
- Avatar/photo hidden.
- Notification shows generic "New message" or platform-equivalent.

**Click-to-open behavior:**
When a notification is clicked while locked (`openNotificationMessage`):
1. Get the session window.
2. Bring window to foreground (`showFromTray()`).
3. Set focus to passcode input (`setInnerFocus()`).
4. Clear all pending notifications (`system()->clearAll()`).
5. Return early -- does **not** navigate to the chat. User must unlock first.

**Focus management:** When locked, `MainWindow::setInnerFocus()` delegates to `_passcodeLock->setInnerFocus()`, which calls `_passcode->setFocusFast()`. This ensures the passcode input always receives keyboard focus when the window is activated.

---

### 27.14 Pixel Dimensions & Constants Summary

| Constant | Value | Used in |
|----------|-------|---------|
| `st::passcodeHeaderFont` | 19px font | Lock screen header text |
| `st::passcodeHeaderHeight` | 80px | Vertical space above input for header |
| `st::passcodeInput` | 225px wide, margins(1,27,1,6) | Lock screen input field |
| `st::passcodeSubmit` | 225px wide, 42px tall, 6px radius | Lock screen submit button |
| `st::passcodeSubmitSkip` | 40px | Gap between input and submit button |
| `st::passcodePadding` | margins(0,0,0,5) | Dialog box top area |
| `st::passcodeTextLine` | 28px | Vertical line height for hint/error text |
| `st::passcodeSkip` | 23px | Gap before hint field |
| `st::passcodeLittleSkip` | 5px | Small vertical gap between fields |
| `st::passcodeAboutSkip` | 7px | Gap before about text |
| `st::passcodeTextStyle` | lineHeight 20px | About text in dialog |
| `st::passcodeSystemUnlock` | 32x36px button, ripple 32px | System unlock icon button |
| `st::passcodeSystemUnlockSkip` | 12px | Gap around system unlock elements |
| `kSystemUnlockDelay` | 1000ms | Cooldown after failed system unlock |
| `kAutoLockTimeoutLateMs` | 3000ms | Grace period for late auto-lock |
| `st::settingLocalPasscodeInputField` | 256px wide | Settings page passcode fields |
| `st::settingLocalPasscodeDescriptionHeight` | 53px | Description label height |
| `st::settingLocalPasscodeDescriptionBottomSkip` | 15px | Gap below description |
| `st::settingLocalPasscodeIconPadding` | margins(0,19,0,5) | Lottie icon area padding |
| `st::settingLocalPasscodeButtonPadding` | margins(0,19,0,35) | Submit button area padding |
| `st::boxWidth` | 320px | Dialog box width |
| `st::boxPadding` | margins(24,14,24,8) | Dialog box content padding |
| `st::boxOptionListSkip` | 20px | Radio button vertical spacing |
| `st::defaultInputField.duration` | 150ms | Error/focus border animation |
| Auto-lock presets | 60, 300, 3600, 18000 sec | 1min, 5min, 1hr, 5hr |
| Lock screen input Y | `height / 3` | One-third down window |
| Ctrl+L | `Command::Lock` | Keyboard shortcut to lock |

---

## 28. Two-Factor Authentication (2FA / Cloud Password) Setup

Source: `Telegram/SourceFiles/settings/cloud_password/` (7 step classes + common helpers), `Telegram/SourceFiles/intro/intro_password_check.cpp` (login-time 2FA entry), `Telegram/SourceFiles/boxes/passcode_box.cpp` (legacy box-based flow), `Telegram/SourceFiles/settings/sections/settings_privacy_security.cpp` (entry point), `Telegram/SourceFiles/core/core_cloud_password.h` (state model), `Telegram/SourceFiles/api/api_cloud_password.h` (API surface).

The 2FA system uses a wizard-style flow inside the settings subsection navigation. Each step is a full-height `AbstractSection` page (not a popup box), with horizontal slide transitions between steps. The newer flow (wizard pages) coexists with the legacy `PasscodeBox` dialog, which is still used for some operations (e.g., disabling password from Privacy Settings when `CheckEditCloudPassword` returns true). Both are documented here.

---

### 28.1 Entry Point — Privacy & Security Section

The Two-Step Verification button lives in the Security subsection of Privacy & Security (see section 16.2.1). The button is a `SettingsButton` with:

- **Icon**: `menuIcon2SV`.
- **Title**: `lng_settings_cloud_password_start_title` ("Two-Step Verification").
- **Right label**: Dynamic, shows one of three states:
  - `lng_profile_loading` ("Loading...") while `CloudPasswordState` is being fetched.
  - `lng_settings_cloud_password_on` ("On") when `hasPassword == true`.
  - `lng_settings_cloud_password_off` ("Off") when `hasPassword == false`.
- **Search keywords**: "password", "2fa", "two-factor".

The cloud password state is fetched via `api().cloudPassword().reload()` on section open and polled every 60 seconds (`kUpdateTimeout`).

**Navigation on click** depends on `PasswordState` enum:

| State | Destination | Condition |
|-------|-------------|-----------|
| `Loading` | No-op | State not yet fetched |
| `On` | `CloudPasswordInput` (check mode) | `hasPassword == true` |
| `Off` | `CloudPasswordStart` (intro screen) | `hasPassword == false` |
| `Unconfirmed` | `CloudPasswordEmailConfirm` | `unconfirmedPattern` is non-empty |

---

### 28.2 Step Architecture & Shared Layout

All 2FA wizard steps inherit from `AbstractStep` (which extends `AbstractSection`). Each step is a full-width, vertically-scrollable `VerticalLayout` child. Steps share a common visual language built from helper functions in `settings_cloud_password_common.cpp`.

#### 28.2.1 Step Data Model

A `StepData` struct is passed between steps via `std::any` reference:

```
StepData {
    QString currentPassword;              // verified current password
    QString password;                     // new password being set
    QString hint;                         // hint for new password
    QString email;                        // recovery email
    int unconfirmedEmailLengthCode;       // expected code digit count
    bool setOnlyRecoveryEmail = false;    // change email without changing password
    bool suggestionValidate = false;      // password validation suggestion mode

    ProcessRecover {
        bool setNewPassword = false;      // recovering: set new password after code
        QString checkedCode;              // verified recovery code
        QString emailPattern;             // masked email pattern (e.g. "j***@g****.com")
    } processRecover;
}
```

#### 28.2.2 Common Header (`SetupHeader`)

Most steps share a header layout produced by `SetupHeader()`:

1. **Lottie icon** (optional): Loaded by name from the `cloud_password/` animation set. Size: `settingsCloudPasswordIconSize` = **100x100px**. Padding: `settingLocalPasscodeIconPadding` = **margins(0, 19, 0, 5)**. Plays once on `showFinished` signal. Animation names:
   - `cloud_password/intro` — shield/lock intro animation (Start screen, Manage screen)
   - `cloud_password/password_input` — lock with keyhole (Input screen, check/create/change)
   - `cloud_password/validate` — checkmark validation (suggestion mode)
   - `cloud_password/hint` — lightbulb (Hint screen)
   - `cloud_password/email` — envelope (Email, EmailConfirm screens)
2. **Skip**: `Ui::AddSkip(content)` — default ~8px vertical spacing.
3. **Subtitle**: `FlatLabel` with style `changePhoneTitle` (font: `boxTitle` style, i.e. 17px semibold). Padding: `changePhoneTitlePadding` = **margins(0, 8, 0, 8)**. Centered at top.
4. **Description**: `FlatLabel` with style `settingLocalPasscodeDescription` (inherits `changePhoneDescription`, minWidth 256px). Padding: `changePhoneDescriptionPadding` = **margins(0, 1, 0, 8)**. `tryMakeSimilarLines` enabled. Transparent for mouse events.

#### 28.2.3 Common Input Fields

- **Password field** (`AddPasswordField`): `Ui::PasswordInput` with style `settingLocalPasscodeInputField` (inherits `defaultInputField`, **width: 256px**). Contained in a wrapper whose height = `heightMin` (61px from `introCountry` base). Field is horizontally centered within the wrapper. Dots masking, reveal toggle built into `PasswordInput`.
- **Text field** (`AddWrappedField`): `Ui::InputField` with same `settingLocalPasscodeInputField` style. Used for hint and email inputs. Full width, not centered.
- **Error label** (`AddError`): `FlatLabel` with style `settingLocalPasscodeError` (inherits `changePhoneError`, minWidth 256px, error-red text `boxTextFgError`). Padding: `changePhoneDescriptionPadding`. Initially hidden; shown on validation failure. Auto-hides when the associated input field changes.

#### 28.2.4 Common Done Button

`AddDoneButton` creates a `RoundButton` with style `changePhoneButton` (inherits `defaultActiveButton`, accent background `activeButtonBg`, white text `activeButtonFg`). Padding: `settingLocalPasscodeButtonPadding` = **margins(0, 19, 0, 35)**. Width matches the `changePhoneButton` style (300px from `introNextButton` base). Height: 42px. Border radius: 6px.

#### 28.2.5 Link Buttons

`AddLinkButton` positions a `Ui::LinkButton` below an input field at offset `passcodeTextLine` = **28px** below the input's bottom edge. Uses `defaultLinkButton` style (accent-colored text `windowActiveTextFg`, underline on hover).

#### 28.2.6 Auto-Close Timer

The Manage screen activates `SetupAutoCloseTimer` which checks every **60 seconds** (`kTimerCheck = 60000ms`) whether the user has been idle for **10 minutes** (`kAutoCloseTimeout = 600000ms`). If idle, navigates back to Privacy Settings and clears `StepData`, effectively locking the manage screen.

#### 28.2.7 Transitions

Steps navigate via `showOther(TypeId)` (horizontal slide-right transition) and `showBack()` (horizontal slide-left). The `removeTypes()` mechanism allows a step to declare which previous steps should be removed from the navigation stack (e.g., `EmailConfirm` removes all intermediate steps so "back" returns to Privacy Settings, not to the Email input).

---

### 28.3 Flow 1 — Create New Password (No Existing Password)

Entry: User clicks "Two-Step Verification" when status is "Off".

#### Step 1: Start Screen (`CloudPasswordStart`)

- **Header**: Lottie `cloud_password/intro` (100x100), title `lng_settings_cloud_password_start_title` ("Two-Step Verification"), description `lng_settings_cloud_password_start_about` (explains what 2FA does).
- **Layout below header**: `settingLocalPasscodeDescriptionBottomSkip` (15px) skip, then two `AddSkipInsteadOfField` spacers (each 61px, simulating empty input slots for vertical alignment), then one `AddSkipInsteadOfError` spacer.
- **Button**: `lng_settings_cloud_password_password_subtitle` ("Set Password"). Clicking navigates to `CloudPasswordInput` in create mode.

#### Step 2: Create Password (`CloudPasswordInput` — create mode)

- **Lottie icon**: `cloud_password/password_input` (100x100), **interactive** — animates between frame 0 (empty lock) and midpoint frame when text is typed. The animation responds to input field text changes:
  - Empty -> non-empty: Animate from frame 0 to `framesCount/2 - 1` (lock closing).
  - Non-empty -> empty: Animate back to frame 0 (lock opening).
- **Title**: `lng_settings_cloud_password_password_subtitle` ("Set Password").
- **Description**: `lng_cloud_password_about` (general 2FA explanation).
- **Skip**: 15px below description.
- **Input 1**: Password field, placeholder `lng_cloud_password_enter_new` ("Enter a password").
- **Input 2**: Password field, placeholder `lng_cloud_password_confirm_new` ("Re-enter your password").
- **Error label**: Hidden by default. Clears on reenter field change.
- **Button**: `lng_continue` ("Continue").

**Validation on button click:**
1. If password empty: focus + showError on first field.
2. If reenter empty: focus + showError on reenter field.
3. If password != reenter: Focus reenter, showError, selectAll, show error label with `lng_cloud_password_differ` ("Passwords don't match").
4. If valid: Store password in `StepData.password`, navigate to `CloudPasswordHint`.

**Enter/submit behavior**: Pressing Enter in password field moves focus to reenter field. Pressing Enter in reenter field triggers the button click.

#### Step 3: Password Hint (`CloudPasswordHint`)

- **Header**: Lottie `cloud_password/hint` (100x100), title `lng_settings_cloud_password_hint_subtitle` ("Add a Hint"), description `lng_settings_cloud_password_hint_about` (tells user hint will be shown when entering password).
- **Skip**: 15px below description.
- **Input**: Text field (not password-masked), placeholder `lng_cloud_password_hint` ("Password hint").
- **Error label**: Below input. Hidden by default, clears on input change.
- **Link button**: `lng_settings_cloud_password_skip_hint` ("Skip") below input at 28px offset. Clicking saves empty hint and navigates to Email.
- **Button**: `lng_continue` ("Continue").

**Validation on button click:**
1. If hint empty: focus + showError on input.
2. If hint == password: Show error `lng_cloud_password_bad` ("The hint must be different from your password"), focus + showError on input.
3. If valid: Store hint in `StepData.hint`, navigate to `CloudPasswordEmail`.

#### Step 4: Recovery Email (`CloudPasswordEmail`)

- **Header**: Lottie `cloud_password/email` (100x100), title `lng_settings_cloud_password_email_subtitle` ("Recovery Email"), description `lng_settings_cloud_password_email_about` (explains recovery email purpose).
- **Skip**: 15px below description.
- **Input**: Text field, placeholder `lng_cloud_password_email` ("Your email").
- **Error label**: Below input, hidden by default.
- **Link button**: `lng_cloud_password_skip_email` ("Skip") below input. Only visible during initial setup (hidden when `setOnly` mode).
- **Button**: `lng_settings_cloud_password_save` ("Save").

**Validation on button click:**
1. If email empty: focus + showError.
2. If non-empty: Sends `cloudPassword().set()` API call with all collected data (current password, new password, hint, email).

**Skip without email**: Shows a confirm box:
- Text: `lng_cloud_password_about_recover` (warning that without email, password cannot be recovered).
- Confirm button: `lng_cloud_password_skip_email` with `attentionBoxButton` style (red text `attentionButtonFg`).
- On confirm: Sends set() with empty email.

**API responses:**
- **`SetOk` with `unconfirmedEmailLengthCode > 0`**: Stores code length, navigates to `CloudPasswordEmailConfirm`.
- **`SetOk` with code length 0** (email auto-confirmed): Clears step data, navigates to `CloudPasswordManage`.
- **`EMAIL_INVALID`**: Shows error `lng_cloud_password_bad_email`, focuses input, selectAll.
- **Flood error**: Shows `lng_flood_error`.
- **`PASSWORD_HASH_INVALID` / `SRP_PASSWORD_CHANGED`**: Triggers `isPasswordInvalidError` which shows info box `lng_cloud_password_expired`, clears all steps, returns to Privacy Settings.

#### Step 5: Email Confirmation (`CloudPasswordEmailConfirm`)

- **Header**: Lottie `cloud_password/email` (100x100), title `lng_cloud_password_confirm` ("Check your email"), description `lng_cloud_password_waiting_code` with the masked email pattern wrapped via `Ui::Text::WrapEmailPattern` (e.g., "We've sent a code to j***@g****.com").
- **Skip**: 15px below description.
- **Input**: `Ui::SentCodeField` with style `settingLocalPasscodeInputField`, placeholder `lng_change_phone_code_title` ("Code"). Auto-submit enabled when code reaches expected length (`setAutoSubmit`).
- **Error label**: Below input, hidden by default.
- **Resend link**: `lng_cloud_password_resend` ("Resend code") below input. On click, calls `cloudPassword().resendEmailCode()`. On success, hides error, shows info label `lng_cloud_password_resent` ("Code resent") with `changePhoneLabel` style.
- **Button**: `lng_settings_cloud_password_email_confirm` ("Confirm").

**Top bar menu** (three-dot / hamburger in title bar): Contains one action `lng_settings_password_abort` ("Abort Two-Step Verification Setup") with `menuIconCancel`. Calls `clearUnconfirmedPassword()`. Only visible when `unconfirmedPattern` is non-empty.

**On successful code confirmation**: Clears step data, navigates to `CloudPasswordManage` (if current password is known) or back to Privacy Settings (if password string is empty, e.g., first-time setup completed).

**Error handling:**
- `CODE_INVALID`: `lng_signin_wrong_code` ("Invalid code").
- `EMAIL_HASH_EXPIRED`: `EmailConfirmationExpired` hard-coded string.
- Flood: `lng_flood_error`.

**Navigation stack cleanup**: `removeTypes()` returns all 2FA step types, so pressing "Back" after confirmation returns directly to Privacy Settings.

---

### 28.4 Flow 2 — Check Password & Manage (Password Already Set)

Entry: User clicks "Two-Step Verification" when status is "On".

#### Step 1: Check Password (`CloudPasswordInput` — check mode)

- **Lottie icon**: `cloud_password/password_input` (100x100), interactive (same empty/filled animation as create mode).
- **Title**: `lng_settings_cloud_password_check_subtitle` ("Enter your password").
- **Description**: `lng_settings_cloud_password_manage_about1`.
- **Skip**: 15px.
- **Input**: Single password field, placeholder `lng_cloud_password_enter_old` ("Current password").
- **Hint display**: If `CloudPasswordState.hint` is non-empty, a `FlatLabel` with `defaultFlatLabel` style shows `lng_signin_hint` ("Hint: {hint}") below the input field. Positioned at the error label's geometry. Hidden when error label is visible; re-shown when error hides.
- **Skip**: One `AddSkipInsteadOfField` (61px) to maintain vertical alignment (no second input).

**Forgot password link**: A `LinkButton` positioned at `passcodeTextLine` (28px) below the input. Its text and behavior change dynamically based on a three-state machine:

| `SuggestAction` | Link Text | Behavior |
|----------------|-----------|----------|
| `Recover` | `lng_signin_recover` ("Forgot password?") | If `hasRecovery`: requests recovery code, navigates to `CloudPasswordEmailConfirm` (recovery mode). If no recovery: shows confirm box with `lng_cloud_password_reset_no_email`, offering timed reset. |
| `CancelReset` | `lng_cloud_password_reset_cancel_title` ("Cancel Reset") | Shows confirm box ("Are you sure?"), calls `cancelResetPassword()`. Below the link, a `FlatLabel` with `boxDividerLabel` style shows countdown: `lng_settings_cloud_password_reset_in` ("Password will be reset in {duration}"). |
| `Reset` | `lng_cloud_password_reset_ready` ("Reset Password") | Calls `resetPassword()`. On success, waits for state update with `hasPassword == false`, shows `lng_cloud_password_removed` info box, returns to Settings. |

The countdown timer updates every **999ms** and recalculates `pendingResetDate - base::unixtime::now()`. Duration formatted via `Ui::FormatResetCloudPasswordIn`.

**Button**: `lng_passcode_check_button` ("Check").

**On successful check**: Stores `currentPassword` in `StepData`, cancels any pending reset, navigates to `CloudPasswordManage`.

**Error handling:**
- `PASSWORD_HASH_INVALID` / `SRP_PASSWORD_CHANGED`: `lng_cloud_password_wrong` ("Wrong password!"), input showError + selectAll.
- Flood: `lng_flood_error`.
- `SRP_ID_INVALID`: Re-fetches password data via `MTPaccount_GetPassword`. If two consecutive SRP_ID_INVALID within `kHandleSrpIdInvalidTimeout` (60 seconds), shows server error.

#### Step 2: Manage Screen (`CloudPasswordManage`)

- **Header**: `AddDividerTextWithLottie` — a `BoxContentDivider` background containing Lottie `cloud_password/intro` (100x100) and description `lng_settings_cloud_password_manage_about1`.
- **Skip**: Default.
- **Button row 1**: `lng_settings_cloud_password_manage_password_change` ("Change Password") with icon `menuIconPermissions`. Click navigates to `CloudPasswordInput` (change mode) with `currentPassword` preserved in `StepData`.
- **Button row 2**: Dynamic label — `lng_settings_cloud_password_manage_email_change` ("Change Recovery Email") if `hasRecovery`, else `lng_settings_cloud_password_manage_email_new` ("Set Recovery Email"). Icon: `menuIconRecoveryEmail`. Click navigates to `CloudPasswordEmail` with `setOnlyRecoveryEmail = true`.
- **Skip**: Default.
- **Divider**: `OneEdgeBoxContentDivider` with description `lng_settings_cloud_password_manage_about2`. The divider's bottom edge is conditionally skipped when the bottom disable button is visible.

**Pinned bottom button**: A separate widget pinned to the bottom of the viewport (not scrolling with content). `lng_settings_password_disable` ("Turn Password Off") with `settingsAttentionButton` style (red text `attentionButtonFg`, hover `attentionButtonFgOver`, ripple `attentionButtonBgRipple`). A `OneEdgeBoxContentDivider` fills the gap between scrollable content and the bottom button.

**Disable password flow**: Click shows a confirm box:
- Text: `lng_settings_cloud_password_manage_disable_sure` ("Are you sure you want to disable your password?").
- Confirm: `lng_settings_auto_night_disable` ("Disable") with `attentionBoxButton` style.
- On confirm: Calls `cloudPassword().set()` with empty new password, empty hint, no email. On success, clears step data, returns to Privacy Settings.

**Auto-close**: 10-minute idle timer (see 28.2.6). Focus policy: `Qt::StrongFocus` set immediately on construction.

**Highlight support**: The Manage screen supports deep-link highlighting of specific controls via IDs: `2sv/change`, `2sv/change-email`, `2sv/disable`.

---

### 28.5 Flow 3 — Change Password (From Manage)

Entry: "Change Password" button on the Manage screen.

Uses `CloudPasswordInput` in **change mode** (detected by: `currentPassword` is non-empty in `StepData`, `hasPassword` is true, not `processRecover`).

- **Title**: `lng_settings_cloud_password_manage_password_change` ("Change Password").
- **Description**: `lng_cloud_password_about`.
- **Inputs**: Two password fields — "Enter a password" + "Re-enter your password" (same as create mode).
- **Validation**: Same mismatch/empty checks as create mode.
- **On valid**: Stores new password, navigates to `CloudPasswordHint` -> `CloudPasswordEmail` -> `CloudPasswordEmailConfirm` -> back to `CloudPasswordManage`.

The Hint step in change mode offers the same "Skip" link. The Email step allows skipping (with the same warning box). The full create pipeline is reused.

---

### 28.6 Flow 4 — Change Recovery Email Only (From Manage)

Entry: "Change Recovery Email" or "Set Recovery Email" on the Manage screen.

Sets `StepData.setOnlyRecoveryEmail = true` and navigates to `CloudPasswordEmail`. In this mode:

- The "Skip email" link is **hidden** (since we explicitly want to set an email).
- The API call uses `cloudPassword().setEmail()` instead of `cloudPassword().set()`.
- Title: `lng_settings_cloud_password_manage_email_change` ("Change Recovery Email") if `hasRecovery` is true.
- On success: navigates to `CloudPasswordEmailConfirm`, then back to `CloudPasswordManage`.

---

### 28.7 Flow 5 — Password Recovery (Forgot Password)

#### 28.7.1 Recovery With Email

When the user clicks "Forgot password?" on the check screen and `hasRecovery == true`:

1. Calls `cloudPassword().requestPasswordRecovery()`.
2. On success: receives masked email pattern (e.g., `j***@g****.com`), stores it in `StepData.processRecover.emailPattern`, navigates to `CloudPasswordEmailConfirm` (recovery mode).

**Recovery mode EmailConfirm** differs from setup mode:
- **Title**: `lng_settings_cloud_password_email_recovery_subtitle` ("Recovery Email").
- **Description**: Shows the masked email pattern.
- **Button text**: `lng_passcode_check_button` ("Check") instead of "Confirm".
- **Resend link**: Text becomes `lng_signin_try_password` ("Can't access your email?"). Click shows a confirm box:
  - Text: `lng_cloud_password_reset_with_email` (explains reset will happen with delay).
  - Confirm: `lng_cloud_password_reset_ok` with `attentionBoxButton` style.
  - On confirm: Calls `resetPassword()`. On success with `pendingResetDate`, shows countdown info box, clears data, returns to Settings.

**On valid recovery code**: Calls `checkRecoveryEmailAddressCode()`. On success: sets `processRecover.checkedCode` and `processRecover.setNewPassword = true`, navigates to `CloudPasswordInput` (recreate mode).

**Recreate mode** (`processRecover.setNewPassword == true`):
- Two password fields for setting a new password.
- A "Skip" link (`lng_settings_auto_night_disable` / "Disable") below the reenter field. Clicking this calls `recoverPassword()` with the checked code but empty password/hint, effectively removing the password entirely. Shows `lng_cloud_password_removed` info box, returns to Settings.
- On valid input: Navigates to `CloudPasswordHint` (recreate hint mode). The Hint step in this mode calls `cloudPassword().recoverPassword()` directly with the checked code, new password, and hint — skipping the Email step entirely.

#### 28.7.2 Recovery Without Email

When `hasRecovery == false`:

1. Shows confirm box: `lng_cloud_password_reset_no_email` (warns that without email, a delayed reset is the only option).
2. Confirm button: `lng_cloud_password_reset_ok` with `attentionBoxButton`.
3. On confirm: Calls `resetPassword()`.
   - **`ResetRetryDate` response**: Shows info box with `lng_cloud_password_reset_later` ("You can reset your password in {duration}"). Minimum displayed duration: 60 seconds.
   - **Success (done)**: Reset initiated. The "Forgot password?" link changes to "Cancel Reset" with countdown.

---

### 28.8 Flow 6 — Login-Time 2FA Entry (`PasswordCheckWidget`)

This is the 2FA screen shown during the **login/sign-up flow** (intro sequence), after phone number + OTP verification, when the account has a cloud password set.

**Widget**: `Intro::details::PasswordCheckWidget`, a full-screen intro step (not a settings subsection).

#### 28.8.1 Layout

Uses the intro step layout system (see section 11). Content area width: `introStepWidth` = **380px**, centered horizontally.

- **Title**: `lng_signin_title` ("Enter Your Password") at `introTitleTop` (1px from content top), font 17px semibold.
- **Description**: `lng_signin_desc` ("You have Two-Step Verification enabled, so your account is protected with an additional password.") at `introDescriptionTop` (34px), font with 20px line height.
- **Password field**: `Ui::PasswordInput` with style `introPassword` (inherits `introCountry`: width 300px, heightMin 61px, font 16px, textMargins 3/27/3/6). Positioned at `introPasswordTop` = **74px** from content top.
- **Hint label**: `FlatLabel` with style `introPasswordHint` (inherits `introDescription`, text color `windowFg`). Positioned at `introPasswordHintTop` = **151px** from content top (with `buttonRadius` = ~6px left offset). Hidden if hint is empty.
- **Recovery code field**: `Ui::InputField` (same `introPassword` style). Positioned at `introStepFieldTop` = **96px**. Initially hidden; shown when user enters recovery mode.
- **"Forgot password?" link**: `lng_signin_recover`, positioned at `introLinkTop` = **24px** below the code field's bottom. Uses `defaultLinkButton` style.
- **"Try password" link**: `lng_signin_try_password`, same position. Initially hidden; shown in recovery mode.
- **Error label**: `introError` style at `introErrorBelowLinkTop` = **220px** from content top.
- **Next button**: `introNextButton` style (300px wide, 42px tall, 6px radius, accent background). Text: `lng_intro_submit` ("Next"). Positioned at `introNextTop` = **266px**.

#### 28.8.2 Password Check Mode (Default)

Visible: password field, hint (if non-empty), "Forgot password?" link.
Hidden: code field, "Try password" link.

**Submit flow:**
1. Compute password hash via `Core::ComputeCloudPasswordHash(algo, password_bytes)`.
2. Compute SRP check via `Core::ComputeCloudPasswordCheck(request, hash)`.
3. Send `MTPauth_CheckPassword(check.result)`.
4. On success: Proceed to logged-in state (finish intro).

**Error handling:**
- `PASSWORD_HASH_INVALID` / `SRP_PASSWORD_CHANGED`: `lng_signin_bad_password` ("Wrong password, try again"), selectAll + showError on field.
- Flood: `lng_flood_error`, showError on field.
- `PASSWORD_EMPTY` / `AUTH_KEY_UNREGISTERED`: Go back to previous intro step.
- `SRP_ID_INVALID`: Re-request password data. If repeated within 60s, show server error.

#### 28.8.3 Recovery Mode (After "Forgot password?")

When user clicks "Forgot password?":
- If `hasRecovery == true`: Sends `MTPauth_RequestPasswordRecovery`. On success, receives email pattern.
  - Hides: password field, hint, "Forgot password?" link.
  - Shows: code field, "Try password" link.
  - Description changes to `lng_signin_recover_desc` with masked email pattern.
- If `hasRecovery == false`: Shows info box `lng_signin_no_email_forgot` ("Since you haven't provided a recovery email..."). On box close, calls `showReset()` which shows a "Reset Account" button.

When user clicks "Try password" (can't access email):
- Shows info box `lng_signin_cant_email_forgot`. On box close, calls `showReset()`.

`showReset()` restores the password entry view and shows a reset account button.

**Recovery code submission:**
1. If `notEmptyPassport`: Shows confirm box `lng_cloud_password_passport_losing` (warning that Telegram Passport data will be lost). "Continue" to proceed.
2. Sends `MTPauth_CheckRecoveryPassword(code)`.
3. On success: Opens a `PasscodeBox` in recovery mode (`fromRecoveryCode = code`, `hasPassword = false`) to let user set a new password. On `newAuthorization`, finishes login.

**Recovery code errors:**
- `CODE_INVALID`: `lng_signin_wrong_code`, selectAll + showError.
- `PASSWORD_RECOVERY_NA`: Fall back to password mode.
- `PASSWORD_RECOVERY_EXPIRED`: Clear email pattern, fall back to password mode.
- Flood: `lng_flood_error`.

---

### 28.9 Flow 7 — Login Email Setup & Verification

Separate from 2FA password, this flow sets an email for passwordless login.

#### Login Email Entry (`CloudLoginEmail`)

- **Header**: Lottie `cloud_password/email` (100x100), title `lng_settings_cloud_login_email_title`, description `lng_settings_cloud_login_email_about`.
- **Input**: Text field, placeholder `lng_settings_cloud_login_email_placeholder`. Pre-filled with previous email if returning.
- **Button**: `lng_settings_cloud_login_email_confirm` ("Confirm"). Shows an `InfiniteRadialAnimationWidget` spinner centered on the button while the request is in-flight (`_confirmButtonBusy`). Button text becomes empty string during loading.

**API**: Calls `Api::RequestLoginEmailCode()`. On success with `(length, pattern)`, stores length, navigates to `CloudLoginEmailConfirm`.

**Errors:**
- `EMAIL_INVALID`: `lng_cloud_password_bad_email`.
- `EMAIL_NOT_SETUP`: Server error.
- Flood: `lng_flood_error`.

#### Login Email Code Confirmation (`CloudLoginEmailConfirm`)

- **Header**: Lottie `cloud_password/email` (100x100), title `lng_settings_cloud_login_email_code_title`, description with wrapped email pattern.
- **Input**: `Ui::CodeInput` widget (digit-only, auto-submit on complete). Digit count set from `unconfirmedEmailLengthCode`.
- **Button**: None visible (auto-submits on code completion).

**On success**: Calls `Api::VerifyLoginEmail()`. On done: Shows fireworks animation (`Ui::StartFireworks` on the main content widget), reloads cloud password state, clears data, returns to Settings.

**Errors:**
- `EMAIL_NOT_ALLOWED`: `lng_settings_error_email_not_alowed`.
- `CODE_INVALID`: `lng_signin_wrong_code`.
- `EMAIL_HASH_EXPIRED`: `EmailConfirmationExpired`.

**Stack cleanup**: On `_processFinishes`, removes `CloudLoginEmailId` from the navigation stack.

---

### 28.10 Password Validation Suggestion

When Telegram suggests the user verify their existing password (via `PromoSuggestions::SugValidatePassword`), the `CloudPasswordSuggestionInput` variant of `CloudPasswordInput` is used. It sets `suggestionValidate = true` in `StepData`.

**Differences from normal check mode:**
- **Lottie icon**: `cloud_password/validate` instead of `cloud_password/password_input`. Plays full animation (0 to last frame) immediately on setup.
- **Title**: `lng_settings_suggestion_password_step_input_title`.
- **Description**: `lng_settings_suggestion_password_step_input_about`.
- **No interactive icon animation** (skips the text-change animation).

**On successful validation**: Dismisses the suggestion, then shows a **completion screen** (`setupValidateGood`):
1. **Fireworks**: `Ui::StartFireworks` on the parent widget.
2. **Emoji icon**: The thumbs-up emoji (U+1F44D) rendered as an animated custom emoji sticker at 100x100px. Created via `EmojiValidateGood` which looks up the emoji sticker pack. Displayed as a `LimitedLoopsEmoji` (plays once). Padding: `settingLocalPasscodeIconPadding`. Falls back to no icon if sticker not found.
3. **Title**: `lng_settings_suggestion_password_step_finish_title`.
4. **Description**: `lng_settings_suggestion_password_step_finish_about`.
5. **Button**: `lng_share_done` ("Done"). Click navigates back.

The existing content widget is **deleted** and replaced by the completion content (`delete content`).

---

### 28.11 Legacy PasscodeBox (Dialog-Based Flow)

The `PasscodeBox` is a traditional `BoxContent` dialog (modal popup) still used in certain entry points (e.g., `EditCloudPasswordBox` from older code paths, and during login-time recovery). It supports both local passcode and cloud password operations within a single box.

#### 28.11.1 Layout

- **Width**: `boxWidth` (standard box width, typically ~320px).
- **Text width**: `boxWidth - boxPadding.left * 1.5`.
- **Padding**: `passcodePadding` = **margins(0, 0, 0, 5)**.

**Fields stacked vertically:**
1. **Old password** (`_oldPasscode`): Shown when checking/changing/removing. Style `defaultInputField`, placeholder `lng_cloud_password_enter_old`. Positioned at `passcodePadding.top` (0) from box content top.
2. **Recover link**: Below old password, at `passcodeTextLine` (28px) offset. If hint exists, shifted down by another `passcodeTextLine`. Text: `lng_signin_recover`.
3. **New password** (`_newPasscode`): Below old (if shown) by `passcodeTextLine` + optional hint line. Placeholder `lng_cloud_password_enter_new` (or `lng_cloud_password_enter_first` if no existing password). Style `defaultInputField`.
4. **Re-enter password** (`_reenterPasscode`): Below new by `passcodeLittleSkip` = **5px**. Placeholder `lng_cloud_password_confirm_new`.
5. **Password hint** (`_passwordHint`): Below re-enter by `passcodeSkip` = **23px**. Placeholder `lng_cloud_password_hint` (or `lng_cloud_password_change_hint` when changing). Only shown for cloud password, not local passcode.
6. **About text**: Below hint by `oldPasscode.height + passcodeLittleSkip + passcodeAboutSkip` (5+7=12px). Rendered as `Ui::Text::String` with `passcodeTextStyle`. Text: `lng_cloud_password_about`.
7. **Recovery email** (`_recoverEmail`): Below about by `passcodeLittleSkip` (5px). Placeholder `lng_cloud_password_email`. Only shown for new cloud password creation (hidden when changing or from recovery code).

**Error text** drawn directly via `QPainter` at `boxTextFgError` color, positioned at `passcodeTextLine` (28px) below each field.

**Box title** varies:
- Create: `lng_cloud_password_create` ("Cloud Password").
- Change: `lng_cloud_password_change` ("Change Cloud Password").
- Remove (turningOff): `lng_cloud_password_remove` ("Disable Cloud Password").
- Custom check: Uses `customTitle` producer.

**Buttons**: "Save" (or custom submit text) + "Cancel" in standard box button row.

**Confirmation messages** after success:
- Password set: `lng_cloud_password_was_set`.
- Password updated: `lng_cloud_password_updated`.
- Password removed: `lng_cloud_password_removed`.

---

### 28.12 Error States Summary

| Error Code | Context | User-Facing Message |
|------------|---------|---------------------|
| `PASSWORD_HASH_INVALID` | Check password | `lng_cloud_password_wrong` ("Wrong password!") / `lng_signin_bad_password` (login) |
| `SRP_PASSWORD_CHANGED` | Check password | Same as above; also triggers "password expired" quit in settings wizard |
| `SRP_ID_INVALID` | Check password | Silent retry (re-fetch password data); server error if repeated within 60s |
| `PASSWORD_EMPTY` | Login check | Go back to previous intro step |
| `AUTH_KEY_UNREGISTERED` | Login check | Go back to previous intro step |
| `CODE_INVALID` | Email/recovery code | `lng_signin_wrong_code` ("Invalid code") |
| `EMAIL_INVALID` | Set email | `lng_cloud_password_bad_email` ("Invalid email address") |
| `EMAIL_HASH_EXPIRED` | Confirm email | Hard-coded "Email confirmation expired" |
| `EMAIL_NOT_ALLOWED` | Login email verify | `lng_settings_error_email_not_alowed` |
| `PASSWORD_RECOVERY_NA` | Recovery | Fall back to password mode |
| `PASSWORD_RECOVERY_EXPIRED` | Recovery | Fall back to password mode |
| Flood errors (`FLOOD_WAIT_*`) | Any | `lng_flood_error` ("Too many attempts, please try again later") |

---

### 28.13 Lottie Animation Reference

| Animation Name | Used In | Trigger | Behavior |
|----------------|---------|---------|----------|
| `cloud_password/intro` | Start, Manage (divider) | `showFinished` | Play once |
| `cloud_password/password_input` | Input (create/check/change) | Text change | Interactive: frame 0 (empty) to midpoint (filled), reverses on clear |
| `cloud_password/validate` | Input (suggestion mode) | Immediate on setup | Play full sequence (0 to last frame) once |
| `cloud_password/hint` | Hint | `showFinished` | Play once |
| `cloud_password/email` | Email, EmailConfirm, LoginEmail, LoginEmailConfirm | `showFinished` | Play once |

All Lottie icons are rendered at **100x100px** (`settingsCloudPasswordIconSize`) with padding **margins(0, 19, 0, 5)** (`settingLocalPasscodeIconPadding`), making the total icon widget size **100x124px**.

---

### 28.14 Complete Flow Diagram

```
Privacy & Security
    │
    ├─ [Off] ──► Start ──► Input(create) ──► Hint ──► Email ──► EmailConfirm ──► Manage
    │                        ├─ 2 password fields                  │ skip (with warning)
    │                        └─ interactive lock icon              └──► Manage (no email)
    │
    ├─ [On] ──► Input(check) ──► Manage
    │              │               ├─ Change Password ──► Input(change) ──► Hint ──► Email ──► EmailConfirm ──► Manage
    │              │               ├─ Change/Set Email ──► Email(setOnly) ──► EmailConfirm ──► Manage
    │              │               └─ Disable ──► [confirm box] ──► Privacy & Security
    │              │
    │              └─ Forgot Password?
    │                   ├─ [has recovery] ──► EmailConfirm(recover) ──► Input(recreate) ──► Hint ──► Manage
    │                   │                         │ "Can't access email?" ──► Reset(timed)
    │                   │                         └─ code verified ──► set new password or skip (disable)
    │                   └─ [no recovery] ──► Reset(timed, countdown in check screen)
    │
    └─ [Unconfirmed] ──► EmailConfirm (pending) ──► Manage or Privacy & Security

Login Flow (intro):
    Phone ──► OTP ──► PasswordCheck
                         ├─ correct ──► logged in
                         ├─ Forgot? [has recovery] ──► recovery code ──► PasscodeBox(recover) ──► logged in
                         └─ Forgot? [no recovery] ──► info box ──► Reset Account button
```

---

### 28.15 Pixel Dimensions & Timing Constants Summary

| Constant | Value | Source |
|----------|-------|--------|
| `settingsCloudPasswordIconSize` | 100px | `settings.style` |
| `settingLocalPasscodeIconPadding` | margins(0, 19, 0, 5) | `settings.style` |
| `settingLocalPasscodeInputField` width | 256px | `settings.style` |
| `settingLocalPasscodeDescriptionBottomSkip` | 15px | `settings.style` |
| `settingLocalPasscodeButtonPadding` | margins(0, 19, 0, 35) | `settings.style` |
| `settingLocalPasscodeDescriptionHeight` | 53px | `settings.style` |
| `changePhoneTitlePadding` | margins(0, 8, 0, 8) | `boxes.style` |
| `changePhoneDescriptionPadding` | margins(0, 1, 0, 8) | `boxes.style` |
| `changePhoneButton` width | 300px (from `introNextButton`) | `boxes.style` |
| `changePhoneButton` height | 42px | `boxes.style` |
| `changePhoneButton` radius | 6px | `boxes.style` |
| `passcodeTextLine` | 28px | `boxes.style` |
| `passcodeLittleSkip` | 5px | `boxes.style` |
| `passcodeAboutSkip` | 7px | `boxes.style` |
| `passcodeSkip` | 23px | `boxes.style` |
| `passcodePadding` | margins(0, 0, 0, 5) | `boxes.style` |
| `introStepWidth` | 380px | `intro.style` |
| `introPassword` width | 300px (from `introCountry`) | `intro.style` |
| `introPassword` heightMin | 61px | `intro.style` |
| `introPasswordTop` | 74px | `intro.style` |
| `introPasswordHintTop` | 151px | `intro.style` |
| `introStepFieldTop` | 96px | `intro.style` |
| `introLinkTop` | 24px | `intro.style` |
| `introErrorBelowLinkTop` | 220px | `intro.style` |
| `introNextTop` | 266px | `intro.style` |
| `introNextButton` height | 42px | `intro.style` |
| `introNextButton` width | 300px | `intro.style` |
| `introSlideDuration` | 200ms | `intro.style` |
| `kAutoCloseTimeout` | 600000ms (10 min) | `common.cpp` |
| `kTimerCheck` | 60000ms (1 min) | `common.cpp` |
| `kHandleSrpIdInvalidTimeout` | 60000ms | `core_cloud_password.h` |
| Countdown timer interval | 999ms | `Input::setupRecoverButton` |
| Minimum displayed reset duration | 60 seconds | `Input::setupRecoverButton` |

---


## 29. Chat Export

Source: `Telegram/SourceFiles/export/` (data types, controller, API wrapper, output writers), `Telegram/SourceFiles/export/view/` (settings widget, progress widget, panel controller, top bar, content mapping), `Telegram/SourceFiles/export/output/` (HTML, JSON, combined writers), `Telegram/SourceFiles/settings/sections/settings_advanced.cpp` and `Telegram/SourceFiles/settings/sections/settings_chat.cpp` (settings entry point), `Telegram/SourceFiles/window/window_peer_menu.cpp` (per-chat/topic context menu entry), `Telegram/SourceFiles/mainwidget.cpp` (in-app top bar integration), `export.style` (all pixel dimensions and style tokens).

The export system uses Telegram's Takeout API (`account.initTakeoutSession`) to download a full or partial archive of the user's account data. It operates in a standalone `SeparatePanel` window (not an in-app dialog box) with two screens: a settings/configuration screen and a progress screen. A global singleton `ExportManager` ensures only one export runs at a time across all accounts. During export, an in-app `TopBar` (media-player style) shows progress in the main window.

---

### 29.1 Entry Points

There are three ways to start an export:

#### 29.1.1 Settings > Advanced > Export Telegram Data (Full Export)

Found in both the old Chat settings page and the new Advanced settings page. Both use the same button:

- **Button text**: `lng_settings_export_data` ("Export Telegram Data").
- **Icon**: `menuIconExport`.
- **Search keywords**: "export", "data", "backup".
- **Behavior on click**: Hides the settings layer with `hideSettingsAndLayer()`, then after a `boxDuration` delay (~150ms), calls `Core::App().exportManager().start(session)` with an empty `inputPeerEmpty` (full account export). The delay prevents the export panel from overlapping the settings close animation.

#### 29.1.2 Chat Context Menu > Export Chat History (Per-Chat Export)

Available on any peer where `canExportChatHistory()` returns true. Appears in the right-click context menu (three-dot menu) on a chat in the info panel / chat header.

- **Menu item text**: `lng_profile_export_chat` ("Export Chat History") for chats, `lng_profile_export_topic` ("Export Topic History") for forum topics.
- **Icon**: `menuIconExport`.
- **Behavior**: After a `defaultPopupMenu.showDuration` delay (~150ms), calls `exportManager().start(peer)` for chats, or `exportManager().startTopic(peer, topicRootId, topicTitle)` for forum topics.

#### 29.1.3 Server-Triggered Suggestion (TAKEOUT_INIT_DELAY)

When the server responds with `TAKEOUT_INIT_DELAY_N` error, the client schedules a suggestion. After the delay expires, a `SuggestBox` dialog appears:

- **Title**: `lng_export_suggest_title` ("Export Your Data").
- **Body**: `lng_export_suggest_text` (multi-line explanation).
- **Buttons**: "OK" (starts export) and `lng_export_suggest_cancel` ("Cancel").
- **Width**: Standard `boxWidth` (360px).
- **Close by outside click**: Disabled.

---

### 29.2 Export Panel Window

The export UI runs in a `SeparatePanel` -- a standalone frameless window that floats above the main app.

- **Panel size**: **364 x 480 px** (`exportPanelSize`).
- **`onAllSpaces`**: `true` (visible on all virtual desktops).
- **Title text**: Varies by mode:
  - Full export: `lng_export_title` ("Export Your Data").
  - Per-chat export: `lng_export_header_chats` ("Export Chat History").
  - Per-topic export: `lng_export_header_topic` ("Export Topic History").
  - During progress: `lng_export_progress_title` ("Exporting Data...").
  - On completion/error: Reverts to `lng_export_title`.
- **Close behavior**: Closing the panel hides it (with animation). If export is actively processing, closing requires confirmation (see 29.6). If not processing, closes silently.
- **`hideOnDeactivate`**: `true` during progress, `false` after completion/error.

---

### 29.3 Settings Screen (Full Export Mode)

The settings screen is a scrollable vertical layout (`SettingsWidget`) with a fixed button bar at the bottom. Content is organized in sections with headers and checkboxes.

#### 29.3.1 Account Data Options

Top section, no header (options listed directly). Each option is a `Checkbox` with `defaultBoxCheckbox` style plus a descriptive `FlatLabel` underneath in subdued text color (`windowSubTextFg`).

| Checkbox | Types Flag | Default | Description label |
|----------|-----------|---------|-------------------|
| Personal information | `PersonalInfo \| Userpics` | ON | `lng_export_option_info_about` ("Exports profile photos, name, bio, etc.") |
| Contact list | `Contacts` | ON | `lng_export_option_contacts_about` ("Exports names and phone numbers.") |
| Stories | `Stories` | ON | `lng_export_option_stories_about` |
| Profile music | `ProfileMusic` | ON | `lng_export_option_profile_music_about` |

- **Checkbox padding**: `exportSettingPadding` = **22px left, 8px top, 22px right, 8px bottom**.
- **Description padding**: `exportAboutOptionPadding` = **22px left, 0px top, 22px right, 16px bottom**.
- **Description style**: `exportAboutOptionLabel` -- `windowSubTextFg` color, min width 175px.

#### 29.3.2 Chats Section

Preceded by a section header.

- **Header text**: `lng_export_header_chats` ("Chats").
- **Header style**: `exportHeaderLabel` -- 15px semibold font, `boxTitle` base style.
- **Header padding**: `exportHeaderPadding` = **22px left, 20px top, 22px right, 9px bottom**.

Chat type checkboxes:

| Checkbox | Types Flag | Default | Has "Only my messages" sub-option |
|----------|-----------|---------|-----------------------------------|
| Personal chats | `PersonalChats` | ON | No (always full) |
| Bot chats | `BotChats` | OFF | No (always full) |
| Private groups | `PrivateGroups` | ON | Yes |
| Private channels | `PrivateChannels` | OFF | Yes |
| Public groups | `PublicGroups` | OFF | Yes (forced on, disabled) |
| Public channels | `PublicChannels` | OFF | Yes (forced on, disabled) |

The "Only my messages" sub-checkbox (`lng_export_option_only_my`) appears with a `SlideWrap` animation when the parent chat-type checkbox is checked. For public groups and public channels, it is always checked and disabled (greyed out) -- the API requires public group/channel exports to be self-only.

- **Sub-option padding**: `exportSubSettingPadding` = **56px left, 4px top, 22px right, 12px bottom** (indented 34px further than parent).

#### 29.3.3 Media Section

This entire section is wrapped in a `SlideWrap` that is **hidden** when no chat type is selected and no `ProfileMusic` is selected, and **shown** (animated, `anim::type::normal`) when at least one chat or ProfileMusic flag is active.

- **Header**: `lng_export_header_media` ("Media").

Media type checkboxes (all use `exportSettingPadding`):

| Checkbox | MediaType Flag | Default |
|----------|---------------|---------|
| Photos | `Photo` | ON |
| Video files | `Video` | OFF |
| Voice messages | `VoiceMessage` | OFF |
| Video messages | `VideoMessage` | OFF |
| Stickers | `Sticker` | OFF |
| GIFs | `GIF` | OFF |
| Files | `File` | OFF |

**Size limit slider** follows immediately after the last media checkbox:

- **Slider widget**: `MediaSlider` with `exportFileSizeSlider` style (seek handle: **15 x 15 px**).
- **Slider padding**: `exportFileSizePadding` = **22px left, 8px top, 22px right, 8px bottom**.
- **Value range**: 100 discrete positions (`kSizeValueCount = 100`), index 0..99.
- **Size mapping** (non-linear, by index `i = position + 1`):
  - i 1--10: `i` MB (1--10 MB)
  - i 11--30: `10 + (i-10)*2` MB (12--50 MB)
  - i 31--40: `50 + (i-30)*5` MB (55--100 MB)
  - i 41--60: `100 + (i-40)*10` MB (110--300 MB)
  - i 61--70: `300 + (i-60)*20` MB (320--500 MB)
  - i 71--80: `500 + (i-70)*50` MB (550--1000 MB)
  - i 81--90: `1000 + (i-80)*100` MB (1100--2000 MB)
  - i 91--100: `2000 + (i-90)*200` MB (2200--4000 MB)
- **Maximum file size**: **4000 MB** (`kMaxFileSize = 4000 * 1024 * 1024`).
- **Default**: 8 MB (`MediaSettings.sizeLimit = 8 * 1024 * 1024`).
- **Label**: `exportFileSizeLabel` (uses `boxTextFont`), displays `lng_export_option_size_limit` with value formatted as `"{N} MB"`. Positioned right-aligned (`exportFileSizePadding.right()` = 22px from right), above the slider by `exportFileSizeLabelBottom` = **18px** from the slider's top edge.

#### 29.3.4 Other Data Section

- **Header**: `lng_export_header_other` ("Other").

| Checkbox | Types Flag | Default | Description |
|----------|-----------|---------|-------------|
| Active sessions | `Sessions` | OFF | `lng_export_option_sessions_about` |
| Other data | `OtherData` | OFF | `lng_export_option_other_about` |

Both use `addOptionWithAbout()` with description labels beneath.

#### 29.3.5 Output Format Section

- **Header**: `lng_export_header_format` ("Output format").

**Location label** (`exportLocationLabel`, max height 21px): Displays `lng_export_option_location` with the export path as a clickable link. Default path shows as `"Downloads/{FolderName}"`. Clicking opens a native folder-picker dialog (`FileDialog::GetFolder`). Padding: `exportLocationPadding` = **22px left, 8px top, 22px right, 8px bottom**.

**Format radio buttons** (using `Radioenum<Format>` with `defaultBoxCheckbox` style):

| Option | Format enum | Label |
|--------|-------------|-------|
| HTML | `Format::Html` | `lng_export_option_html` ("Human-readable HTML") |
| JSON | `Format::Json` | `lng_export_option_json` ("Machine-readable JSON") |
| HTML + JSON | `Format::HtmlAndJson` | `lng_export_option_html_and_json` ("HTML and JSON") |

Radio button padding: `exportSettingPadding` (same as checkboxes).

#### 29.3.6 Bottom Buttons

Fixed at the bottom of the panel (not scrollable). Height = `buttonPadding.top + defaultBoxButton.height + buttonPadding.bottom`.

- **"Export" button** (`lng_export_start`): `defaultBoxButton` style. Only shown when at least one data type is selected (`types != 0`) or in single-peer mode. Positioned right-aligned with `buttonPadding.right` margin.
- **"Cancel" button** (`lng_cancel`): `defaultBoxButton` style. Always shown. Positioned to the left of Export button (offset by `buttonPadding.left` gap from Export).

**Scroll shadows**: `FadeShadow` widgets at top and bottom edges of the scroll area. Top shadow visible when `scrollTop > 0`. Bottom shadow visible when scroll has not reached the bottom.

---

### 29.4 Settings Screen (Per-Chat / Per-Topic Export Mode)

When exporting a single chat (`singlePeer != inputPeerEmpty`), the settings screen is simplified:

- **No account data options** (Personal info, Contacts, Stories, Profile music, Sessions, Other) -- all hidden.
- **No chat type selection** -- all chat type flags are forced to `AnyChatsMask`.
- **No section headers** for chats.
- **Media options** are shown directly (no SlideWrap conditional).
- **Format and location** shown as a single combined label (`lng_export_option_format_location`) with two clickable links: one for format (opens a `ChooseFormatBox` modal), one for path (opens folder picker). The `ChooseFormatBox` is a `GenericBox` with the same three radio buttons (HTML, JSON, HTML+JSON) plus Save/Cancel buttons.
- **Date range filter** (`addLimitsLabel`): Displays `lng_export_limits` with clickable "from" and "till" date/time links.

#### 29.4.1 Date Range Filter

Shows a label with format: "From {from_date}, {from_time} till {till_date}, {till_time}".

- **From date**: Clickable link. Opens a `CalendarBox` date picker.
  - Default: `lng_export_beginning` ("the beginning").
  - Min date: August 1, 2013 (Telegram launch date) or the "till" date as maximum.
  - Reset button: `lng_export_from_beginning` ("From the beginning").
- **Till date**: Clickable link. Opens a `CalendarBox`.
  - Default: `lng_export_end` ("now").
  - Min date: the "from" date.
  - Max date: today.
  - Reset button: `lng_export_till_end` ("Till now").
- **Time editing**: When a date is set, clicking the time link opens a `ChooseTimeWidget` inside a `GenericBox` with hour/minute/second input. Title: `lng_settings_ttl_after_custom` (reused). Save/Cancel buttons.
- **Safety offset**: When from/till times would overlap (from >= till), a 600-second (`kOffset`) minimum gap is enforced.
- **Label padding**: `exportLimitsPadding` = **22px left, 0px top, 22px right, 0px bottom**.

#### 29.4.2 Calendar Box (Date Picker)

Uses `CalendarBox` with `exportCalendarSizes`:

- **Width**: 320px.
- **Day row height**: 40px.
- **Cell size**: 42 x 38 px.
- **Cell inner (selected circle)**: 32px diameter.
- **Side padding**: 14px left, 14px right.

---

### 29.5 Progress Screen

Shown after clicking "Export". The panel title changes to `lng_export_progress_title` ("Exporting Data...").

#### 29.5.1 Processing Steps

The export controller runs through steps sequentially. Each active step becomes a progress row:

1. **Initializing** -- creates takeout session, requests dialog list.
2. **DialogsList** -- fetches the full chat list.
3. **PersonalInfo** -- exports profile data.
4. **Userpics** -- exports profile photos (with file download progress).
5. **Stories** -- exports stories (with file download progress).
6. **ProfileMusic** -- exports profile music (with file download progress).
7. **Contacts** -- exports contact list.
8. **Sessions** -- exports active sessions.
9. **OtherData** -- exports other account data.
10. **Dialogs** -- exports each selected chat's messages and media (with per-file download progress).
11. **Topic** -- exports a single forum topic (only in per-topic mode).

For per-chat/per-topic export, only Initializing + Dialogs/Topic steps run. Chat type flags are overridden to `AnyChatsMask`.

#### 29.5.2 Progress Row Layout

Each processing step is displayed as a `Row` widget:

- **Row height**: `exportProgressRowHeight` = **30px**.
- **Row padding**: `exportProgressRowPadding` = **22px left, 10px top, 22px right, 10px bottom**.
- **Row spacing**: `exportProgressRowSkip` = **10px** between rows (via `FixedHeightWidget` spacer).
- **Label** (left-aligned): `exportProgressLabel` -- `windowBoldFg` color, 14px semibold font, max height 20px. Shows the step name (e.g., "Personal information", "Contacts", chat name for dialog steps).
- **Info label** (right-aligned): `exportProgressInfoLabel` -- `windowSubTextFg` color, max height 20px, `boxTextStyle`. Shows entity counts (e.g., "3 / 15") or download progress (e.g., "2.4 MB / 15.7 MB" via `FormatDownloadText`).
- **Progress bar**: Thin colored bar at the bottom of each row.
  - **Thickness**: `exportProgressWidth` = **3px**.
  - **Active color**: `exportProgressFg` = `mediaPlayerActiveFg` (blue/accent).
  - **Inactive color**: `exportProgressBg` = `mediaPlayerInactiveFg` (grey).
  - **Animation**: `sineInOut` easing, `exportProgressDuration` = **200ms**.

Rows fade in/out with opacity animation (200ms) when steps change. Old step rows fade out while new ones fade in. When a step transitions to a new entity (same step, different chat), the label and info update in place; progress bar resets without animation if the new value is lower than the old.

**Main row** (first row) shows the overall step label (e.g., "Chats") with an `"N / M"` entity counter. Sub-rows show the current entity (chat name, file name). Up to 3 rows visible for full export (main + entity + file download), 2 for per-chat export.

#### 29.5.3 Skip File Link

When a file download takes more than **5 seconds** (`kShowSkipFileTimeout = 5000ms`):

- A `LinkButton` (`lng_export_skip_file`, "Skip file") fades in (`anim::type::normal`) at the left side, `exportProgressRowPadding.left` = 22px from left.
- Positioned in a fixed-height wrapper (`defaultLinkButton.font.height + exportProgressRowSkip` tall), between the progress rows and the about label.
- Clicking sends the current file's `randomId` to `Controller::skipFile()`.
- When the file changes (new `randomId`), the skip button hides and the 5-second timer restarts.

#### 29.5.4 About Label

Below the progress rows:

- **Text**: `lng_export_progress` ("Please wait, export is in progress.") during export; changes to `lng_export_about_done` ("Your data was successfully exported.") on completion.
- **Style**: `exportAboutLabel` -- `windowSubTextFg` color.
- **Padding**: `exportAboutPadding` = **22px left, 10px top, 22px right, 0px bottom**.

#### 29.5.5 Cancel / Stop Button

Centered horizontally at the bottom of the panel.

- **Style**: `exportCancelButton` -- based on `attentionBoxButton` (red/destructive), **200px wide, 44px tall**, text at 12px from top, 15px semibold font.
- **Bottom margin**: `exportCancelBottom` = **30px** from panel bottom.
- **Text**: `lng_export_stop` ("Stop").
- **Behavior**: Opens a confirmation dialog (see 29.6).

---

### 29.6 Stop Confirmation Dialog

Triggered when pressing Cancel/Stop during an active export, or when closing the panel window while `ProcessingState` is active.

- **Type**: `ConfirmBox` (standard confirmation dialog).
- **Text**: `lng_export_sure_stop` ("Are you sure you want to stop exporting your data?").
- **Confirm button**: `lng_export_stop` ("Stop") with `attentionBoxButton` style (red/destructive).
- **Cancel button**: Standard cancel.
- **`closeByEscape`**: Not restricted (default behavior).
- **`closeByOutsideClick`**: Not restricted.
- **On confirm**: `cancelExportFast()` is called, which cancels the takeout session and transitions to `CancelledState`.

---

### 29.7 Completion Screen

When export finishes (`FinishedState`), the progress screen transforms:

#### 29.7.1 Done Row Content

Three rows replace the progress rows:

1. **Row 1**: Label = `lng_export_finished` ("Data exported successfully."), progress = 1.0.
2. **Row 2**: Label = `lng_export_total_amount` with `filesCount` (e.g., "Total files: 1,234"), progress = 1.0.
3. **Row 3**: Label = `lng_export_total_size` with formatted size (e.g., "Total size: 256.7 MB"), progress = 1.0.

All rows have `id = Content::kDoneId = "done"`.

#### 29.7.2 Done Button

Replaces the Cancel button:

- **Style**: `exportDoneButton` -- based on `defaultActiveButton` (blue/primary), **200px wide, 44px tall**, 15px semibold font, text at 12px from top.
- **Text**: `lng_export_done` ("Show My Data").
- **Width**: Expands to fit text if needed. Desired width = `font.width(text) + button.height - font.height`, clamped to max `panelWidth - 2 * exportCancelBottom` = 364 - 60 = 304px.
- **Positioned**: Centered horizontally, same `exportCancelBottom` = 30px from panel bottom.
- **Behavior**: Opens the export output folder in the system file manager via `File::ShowInFolder(path)`, then hides the panel.

#### 29.7.3 State Changes

- Panel title reverts to `lng_export_title`.
- `hideOnDeactivate` set to `false` (panel persists when app loses focus).
- Skip file link hidden instantly.
- About text changes to `lng_export_about_done`.

---

### 29.8 Error States

#### 29.8.1 API Error: TAKEOUT_INVALID

Shown as an informational box: `lng_export_invalid` ("Export session expired. Please try again."). Box cannot be closed by Escape or outside click. Closing it hides the panel.

#### 29.8.2 API Error: TAKEOUT_INIT_DELAY_N

Displayed as informational box with delay message: `lng_export_delay` containing hours remaining and the exact date/time when export will be available. The `availableAt` timestamp is saved to local storage and the server suggestion system is triggered.

#### 29.8.3 Disk/IO Error

A full-panel error display (not a popup box):

- **Label**: `exportErrorLabel` -- `boxTextFgError` color (red), min width 175px, top-aligned.
- **Top padding**: `panelHeight / 4` = 120px from top (vertically offset for visual centering).
- **Text**: "Disk Error happened :(\nCould not write path:\n{path}".

#### 29.8.4 Generic API Error

Full-panel critical error: "API Error happened :(\n{code}: {type}\n{description}".

---

### 29.9 In-App Export Top Bar

While an export is in progress, a `TopBar` widget appears at the top of the main window (similar to the media player bar). It persists across chat navigation.

#### 29.9.1 Layout

- **Height**: `mediaPlayerHeight + lineWidth` (the standard media player bar height, typically 35px + 1px shadow).
- **Background**: `mediaPlayerBg`.
- **Three labels** (left to right, all `exportTopBarLabel` style, max height 20px):
  - **Left**: Bold "Exporting Data" + space + em-dash. Positioned at `mediaPlayerPlayLeft + mediaPlayerPadding` from left, `mediaPlayerNameTop - font.ascent` from top.
  - **Middle**: Current step label (e.g., "Contacts", "Chats"). Middle-elision enabled (truncates in the middle if too long). Spaced one `font.spacew` from left label.
  - **Right**: Info text (e.g., "3 / 15") in `windowSubTextFg` color via `Colorized()` markup.
- **Progress bar**: `mediaPlayerPlayback` style `FilledSlider` at the very bottom, full width, height = `mediaPlayerPlayback.fullWidth`. Shows the current step's progress value (0.0--1.0).
- **Shadow**: `PlainShadow` widget, controllable via `showShadow()`/`hideShadow()`.
- **Click**: The entire bar is a clickable `AbstractButton`. Clicking activates (brings to front) the export panel window.

#### 29.9.2 Lifecycle

- Created when `ExportManager::currentView()` emits a non-null `PanelController` and progress state begins.
- Destroyed when the export finishes (row id == `Content::kDoneId`) or the controller is removed (export stopped/cancelled).
- Show/hide animated: slides down on appear (`anim::type::normal`), slides up on disappear. During show animation, `_contentScrollAddToY` is set to the bar height to shift the chat content down smoothly.

---

### 29.10 Settings Persistence

Export settings are saved to local storage (`session->local().writeExportSettings()`) and loaded on next export (`readExportSettings()`). Saving is debounced with a **1000ms** timer (`kSaveSettingsTimeout`). If the default download path is used, the stored path is cleared (empty string) so it adapts to future path changes. Settings saved include: types, fullChats, media types, media size limit, format, path, and `availableAt` timestamp.

---

### 29.11 Output Formats

Three writers produce different output:

| Format | Enum | Description |
|--------|------|-------------|
| HTML | `Format::Html` | Human-readable pages with CSS styling, linked media files |
| JSON | `Format::Json` | Machine-readable structured data |
| HTML + JSON | `Format::HtmlAndJson` | Both outputs written simultaneously |

Output is written to `{path}/DataExport_{date}/` (when `forceSubPath` is true, i.e., using default download path) or directly to the user-chosen path. The writer creates subdirectories for each data category (chats, media, etc.) and produces an index/entry file (`export_results.html` or `result.json`).

---

### 29.12 Pixel Dimensions & Style Constants Summary

| Token | Value | Description |
|-------|-------|-------------|
| `exportPanelSize` | **364 x 480 px** | Export panel window dimensions |
| `exportSettingPadding` | **22, 8, 22, 8 px** | Standard checkbox/radio padding (L,T,R,B) |
| `exportSubSettingPadding` | **56, 4, 22, 12 px** | Indented sub-option padding |
| `exportHeaderLabel` | **15px semibold** | Section header font |
| `exportHeaderPadding` | **22, 20, 22, 9 px** | Section header padding |
| `exportFileSizeSlider.seekSize` | **15 x 15 px** | Slider thumb/handle size |
| `exportFileSizePadding` | **22, 8, 22, 8 px** | Slider container padding |
| `exportFileSizeLabelBottom` | **18px** | Gap between size label and slider top |
| `exportFileSizeLabel.font` | `boxTextFont` | Size label font |
| `exportLocationLabel.maxHeight` | **21px** | Path label max height |
| `exportLocationPadding` | **22, 8, 22, 8 px** | Path label padding |
| `exportLimitsPadding` | **22, 0, 22, 0 px** | Date range label padding |
| `exportAboutOptionLabel.textFg` | `windowSubTextFg` | Description text color |
| `exportAboutOptionLabel.minWidth` | **175px** | Description min width |
| `exportAboutOptionPadding` | **22, 0, 22, 16 px** | Description label padding |
| `exportErrorLabel.textFg` | `boxTextFgError` | Error text color (red) |
| `exportProgressDuration` | **200ms** | Progress bar animation duration |
| `exportProgressRowHeight` | **30px** | Single progress row height |
| `exportProgressRowPadding` | **22, 10, 22, 10 px** | Progress row padding |
| `exportProgressRowSkip` | **10px** | Vertical gap between progress rows |
| `exportProgressLabel.font` | **14px semibold** | Progress step label font |
| `exportProgressLabel.textFg` | `windowBoldFg` | Progress label color |
| `exportProgressInfoLabel.textFg` | `windowSubTextFg` | Progress info color |
| `exportProgressWidth` | **3px** | Progress bar thickness |
| `exportProgressFg` | `mediaPlayerActiveFg` | Progress bar active color (accent blue) |
| `exportProgressBg` | `mediaPlayerInactiveFg` | Progress bar inactive color (grey) |
| `exportCancelButton` | **200 x 44 px** | Cancel/Stop button dimensions |
| `exportCancelButton.font` | **15px semibold** | Cancel button font |
| `exportCancelButton.textTop` | **12px** | Cancel button text offset |
| `exportCancelBottom` | **30px** | Bottom margin for centered button |
| `exportDoneButton` | **200 x 44 px** | Done button dimensions (same size) |
| `exportDoneButton.font` | **15px semibold** | Done button font |
| `exportAboutPadding` | **22, 10, 22, 0 px** | Progress about-text padding |
| `exportCalendarSizes.width` | **320px** | Date picker calendar width |
| `exportCalendarSizes.daysHeight` | **40px** | Calendar day row height |
| `exportCalendarSizes.cellSize` | **42 x 38 px** | Calendar cell dimensions |
| `exportCalendarSizes.cellInner` | **32px** | Calendar selected circle diameter |
| `exportCalendarSizes.padding` | **14, 0, 14, 0 px** | Calendar side padding |
| `exportTopBarLabel.maxHeight` | **20px** | Top bar label max height |
| `kSizeValueCount` | **100** | Number of discrete slider positions |
| `kMaxFileSize` | **4000 MB** | Maximum media file size limit |
| `kShowSkipFileTimeout` | **5000ms** | Delay before "Skip file" link appears |
| `kSaveSettingsTimeout` | **1000ms** | Settings save debounce timer |
| `kOffset` | **600s** | Minimum gap between from/till timestamps |

---

## 30. Bot Interactions

Bot-specific UI surfaces in Telegram Desktop: command entry, inline queries, reply keyboards, inline keyboards under messages, Web App panels, payment flows, game cards, and the bot start screen.

---

### 30.1 Bot Command Button & Menu Button

**Command slash button** (`historyBotCommandStart`): An `IconButton` inheriting `historyAttach` dimensions (44x46 px). Icon: `chat/input_bot_command` in `historyComposeIconFg`, with `historyComposeIconFgOver` on hover. Positioned in the compose area controls strip, left of the text field (same row as attach, emoji, and silent-mode buttons). Clicking inserts a `/` character into the compose field, triggering command autocomplete.

Visibility: Shown when the peer has `botCommandSend` enabled and the user is not blocked. Controlled by `updateBotCommandShown()` and AyuGram's `showCommandsButtonInMessageField()` setting. Hidden when the bot menu button replaces it.

**Bot menu button** (`historyBotMenuButton`): A `RoundButton` replacing the command slash button when the bot declares a menu button. Dimensions: width auto (minimum `-24px` padding, meaning 24px of internal padding on each side beyond text), height 30px, `textTop` 6px. Font: semibold (from `defaultActiveButton`). Max label width: 160px (`historyBotMenuMaxWidth`). Skip from adjacent controls: 8px (`historyBotMenuSkip`). Tapping opens the bot's Web App (see 30.5).

---

### 30.2 Command Autocomplete Dropdown

Triggered when the user types `/` in the compose field and the peer has bots with commands.

**Row layout:** Each row is `mentionHeight` = 40px tall. Left edge: bot userpic at `mentionPhotoSize` = 33px diameter, inset `mentionPadding.left()` = 8px from left. Command text: prefixed with `/`, font `semiboldFont`, starts after `2 * mentionPadding.left() + mentionPhotoSize` = 49px. Description text: right of command, font `mentionFont` (normal weight), right-aligned remainder of row. Padding: `margins(8px, 5px, 8px, 5px)`.

**Dropdown size:** Width matches the compose field. Max visible height: 4.5 rows = 4.5 x 40px = 180px. Scrollable if more commands exist. Positioned above the compose field, anchored at its bottom edge.

**Filtering:** Case-insensitive substring match on command name. In groups/supergroups, commands suffixed with `@botusername` when multiple bots are present. Recent inline bots may appear at list start with a delete affordance (X icon, right-aligned, shown on hover).

**Selection:** Keyboard Up/Down moves highlight. Mouse hover fills background with `mentionBgOver`. Click or Enter sends the command (inserts into field or fires directly depending on context).

**Animation:** Opacity fade over `emojiPanDuration` = 200ms. Top/bottom border: `lineWidth` = 1px separator.

---

### 30.3 Inline Bot Results Panel

Triggered when the user types `@botname ` (with trailing space) in the compose field. The panel reuses the emoji panel infrastructure.

**Panel dimensions:**
- Width: `emojiPanWidth` = 345px.
- Min height: `inlineResultsMinHeight` = 278px.
- Max height: `emojiPanMaxHeight` = 640px (also `inlineResultsMaxHeight`).
- Height ratio: `emojiPanHeightRatio` = 0.75 of available vertical space.
- Margins: `emojiPanMargins` = 10px on all sides.
- Corner radius: `emojiPanRadius` = 8px (panel rounding), `roundRadiusSmall` for content clip.
- Scroll bar width: `emojiScroll.width`.

**Show/hide animation:** Panel grab + opacity fade over `emojiPanShowDuration` = 200ms, using `emojiPanAnimation` (default panel animation). Corner masks applied during animation for rounded clip.

**Content layout -- Mosaic grid:**
- Content width: `emojiPanWidth - emojiScroll.width - inlineResultsLeft` (345 - scroll - 11px).
- Item padding: `stickerPanPadding` = 11px around content.
- Item skip: `inlineResultsSkip` = 3px between items.
- Row margin: `inlineRowMargin` = 6px top/bottom per row.
- Row border: `inlineRowBorder` = 1px separator.

Items are laid out in a dynamic mosaic: multiple items per row, aspect-fill scaling so the smaller dimension covers the cell. Content is clipped, not letterboxed.

**Result types and sizes:**

| Type | Dimensions | Notes |
|---|---|---|
| Photo / GIF | Height = `inlineMediaHeight` = 96px, width proportional | Aspect-fill, clipped. GIFs auto-play. Radial progress `inlineRadialSize` = 44px during load. |
| Sticker | `stickerPanSize` = 64x64px | Centered. Lottie/WebM animated or static PNG fallback with blur. |
| Video | Thumbnail `inlineThumbSize` = 64px left, text right | Title (2 lines max, semibold), description, duration badge. |
| Article / Contact | Thumbnail optional (64px left) or letter avatar | Title + description + URL, text elided. |
| File | Circular icon background, 64px | Radial progress `msgFileRadialLine` width. Title + description + file size. |
| Game | Same as article | Animated document support for thumbnail. |

Thumb-to-text skip: `inlineThumbSkip` = 10px. Min item width: `inlineResultsMinWidth` = 48px.

**Background:** `emojiPanBg`. Scroll style: `inlineBotsScroll` (solid scroll).

**Inline request delay:** 350ms debounce before sending the query to the bot API.

**Repaint throttle:** `kMinRepaintDelay` = 33ms, `kMinAfterScrollDelay` = 33ms. Scroll-to-bottom triggers next page request.

**Switch PM button:** Shown above results when the bot provides `switch_pm`. Skip from results: `inlineResultsSkip`. Icon: `inline_button_switch` in `msgBotKbIconFg`.

---

### 30.4 Reply Keyboard (Bot Keyboard Below Compose)

The full-width reply keyboard appears below the compose area when a bot sends a message with `ReplyKeyboardMarkup`.

**Show/hide:** Toggle buttons `_botKeyboardShow` / `_botKeyboardHide` in the compose controls. Animation duration: `botKbDuration` = 200ms. Keyboard hides automatically when the user types non-empty text (and `singleUse` is not set).

**Flags:**
- `SingleUse`: Keyboard hides after one button press.
- `ForceReply`: Forces a reply to the bot's message.
- `Persistent`: Keyboard stays visible even after user types.
- `Resize`: Keyboard shrinks to fit buttons (smaller margins). Without this flag, keyboard expands to `_maxOuterHeight`.

**Button style selection:** Two presets chosen by `isEnoughSpace()`:
- **Normal** (`botKbButton`): margin 10px, padding 10px, height 38px, textTop 9px. Ripple color: `botKbDownBg`.
- **Tiny** (`botKbTinyButton`): margin 4px, padding 3px, height 25px, textTop 2px. Ripple: `defaultRippleAnimation`.

When the available width cannot fit normal-sized buttons, tiny style is used.

**Text style:** `botKbStyle` = 15px semibold font.

**Colors by button color enum:**
| Color | Background | Text |
|---|---|---|
| Normal | `botKbBg` | `botKbColor` |
| Primary | `botKbPrimaryBg` | white |
| Danger | `botKbDangerBg` | white |
| Success | `botKbSuccessBg` | white |

**Fill behind keyboard:** `historyComposeAreaBg`.

**Corner rounding:** All four corners use `BubbleCornerRounding::Large` (large radius). Small radius also available depending on rounding context.

**Scrolling:** `botKbScroll` = `defaultSolidScroll`. Height: `botKbScroll.deltat + botKbScroll.deltab + naturalHeight()`. Width for buttons: total width minus margin minus scroll bar width.

**Interaction:** Mouse tracking enabled. Tooltips appear after 350ms hover. Click handlers manage active/pressed states.

---

### 30.5 Inline Keyboard (Buttons Under Messages)

Rendered directly below the message bubble, part of the message element.

**Position:** `keyboardPosition` = `(g.left(), g.top() + g.height() + msgBotKbButton.margin)`. The keyboard is painted by `ReplyKeyboard::paint()` within the message's paint call.

**Button style** (`msgBotKbButton`): margin 2px, padding 10px, height 36px, textTop 8px. Ripple: `defaultRippleAnimation`.

**Layout:** Buttons distributed across available bubble width. Each row: buttons share width proportionally based on text content, with `buttonSkip()` (= margin) between them. Min width: `minButtonWidth()` varies by type. Text: single line, center-aligned, elided with `botKbStyle.font->elidew`. RTL layout mirrors X positions.

**Button types** (from `HistoryMessageMarkupButton::Type`):

| Type | Behavior | Icon |
|---|---|---|
| `Default` | Sends button text as message | None |
| `Url` | Opens URL in browser | `inline_button_url` (arrow icon) |
| `Callback` | Sends callback data to bot | None (loading spinner while waiting) |
| `CallbackWithPassword` | Callback requiring 2FA password | None (loading spinner) |
| `RequestPhone` | Shares phone number | None |
| `RequestLocation` | Shares location | None |
| `RequestPoll` | Creates a poll | None |
| `RequestPeer` | Peer selection dialog | None |
| `SwitchInline` | Opens inline query in another chat | `inline_button_switch` |
| `SwitchInlineSame` | Opens inline query in same chat | `inline_button_switch` |
| `Game` | Opens game | None |
| `Buy` | Payment button (text replaced with star emoji) | `inline_button_card` |
| `Auth` | Login URL (see 30.9) | `inline_button_url` |
| `UserProfile` | Opens user profile | None |
| `WebView` | Opens Web App | `inline_button_web` |
| `SimpleWebView` | Opens simple Web App | `inline_button_web` |
| `CopyText` | Copies text to clipboard | `inline_button_copy` |
| `SuggestAccept` | Accept suggestion | None |
| `SuggestDecline` | Decline suggestion | None |
| `SuggestChange` | Change suggestion | None |
| `CreateBot` | Create a bot | None |

**Button colors** (from `HistoryMessageMarkupButton::Color`): Normal, Primary, Danger, Success -- same color scheme as reply keyboard (30.4).

**Icon rendering:** Icons are placed at bottom-right of the button rect with `msgBotKbIconPadding` = 4px offset. Icon color: `msgBotKbIconFg`. Custom emoji icons supported via `Data::SingleCustomEmoji(iconId)`. Buy buttons render a star icon via `starIconEmojiLarge`.

**Hover animation:** `howMuchOver` interpolates 0.0 to 1.0 over `botKbDuration` = 200ms. Background painted via `paintButtonBg()` with the animation value. Deselection animates 1.0 to 0.0. Over background uses `msgBotKbOverBgAdd` corners (small or large radius variants).

**Ripple:** Created on press with `RippleAnimation::RoundRectMask()`. Corner rounding is context-aware: top-left is large only if button is in first row and first column; top-right is large if first row and last column; bottom corners similarly depend on last row position.

**Loading state:** Callback buttons show `paintButtonLoading()` -- a radial spinner overlaid on the button while the bot processes the callback.

**Fast buttons mode:** When enabled, numbered badges (1-9) appear over buttons in `dialogsUnreadFont` with `msgServiceFg` color. Only visible on the last message in history with an active keyboard.

---

### 30.6 Web Apps / Mini Apps

Bot Web Apps open as a separate panel (`SeparatePanel`) overlaid on the main window.

**Panel size:** Default `botWebViewPanelSize` = 384x694px. Increased height and width variants available for expanded mode. Fullscreen toggle supported.

**Opening sources:**
- Button source: `MTPmessages_RequestWebView` (from inline keyboard button).
- Simple source: `MTPmessages_RequestSimpleWebView` (from menu/attachment).
- Main web view: `MTPmessages_RequestMainWebView` (bot menu button).
- App source: `MTPmessages_RequestAppWebView` (direct app link).

**Header bar:**
- Title: Bot name (or custom title) in `semiboldTextStyle`. Custom emoji supported in title.
- Verified badge: `infoVerifiedStar` styling when applicable.
- Title color: Overridable via `web_app_set_header_color`.
- Close button: Standard panel close (X), managed by `SeparatePanel`.
- Back button: Shown/hidden via `setBackAllowed()`. Fires `backRequests()` signal.
- Settings button: Visible in header menu when `_hasSettingsButton` is true.

**Bottom bar:**
- Bot username displayed prefixed with `@`.
- Background: Overridable via `web_app_set_bottom_bar_color`.
- Padding: `botWebViewBottomPadding` = margins(12px, 12px, 12px, 12px).

**Main button** (`botWebViewBottomButton`): Height 40px, `textTop` 11px. Inherits from `paymentsPanelSubmit` styling. States: visible/hidden, active/inactive, progress overlay. Custom text, text color, and background color settable via `web_app_setup_main_button`. Default foreground: `windowFgActive`. Default background: `windowBgActive`. Ripple color auto-calculated from background using HSV: if lightness > 128, darken by 32; if <= 128, lighten by 32.

**Secondary button:** Same style as main button. Four position options relative to main button: `top`, `bottom`, `left`, `right`. Vertical stacking when top/bottom; horizontal when left/right with skip `botWebViewBottomSkip` = point(12px horizontal, 8px vertical). Custom emoji icon support via `iconCustomEmojiId`.

**Progress indicator:** Infinite radial animation. Stroke: `botWebViewRadialStroke` = 3px. Duration: `kProgressDuration` = 200ms fade. Opacity: `kProgressOpacity` = 0.3. Style: `paymentsLoading` (24x24px, thickness 4px). Fade uses `radialDuration * 2`.

**Menu:** `botWebViewMenu` popup with `maxHeight` = 360px. Items: "Open Bot" (`OpenBot`), "Remove from Menu" (`RemoveFromMenu`), "Remove from Main Menu" (`RemoveFromMainMenu`), "Share Game" (`ShareGame`).

**Theme integration:** Bot app colors from bot info: `botAppColorTitleDay/Night`, `botAppColorBodyDay/Night` (applied only if alpha = 255). Theme params passed as JSON via `botThemeParams()`. Updates via `web_app_request_theme`.

**Safe area:** `sendSafeArea()` returns top/right/bottom/left = 0. Content safe area top offset calculated from fullscreen state and DPI scaling.

**Confirmation dialogs:**
- Unverified bot: Confirmation box before opening.
- Write access: Checkbox `lng_url_auth_allow_messages` for message permission.
- Main menu bots: Disclaimer with mandatory checkbox acceptance.
- Close confirmation: Modal confirm when `_closeNeedConfirmation` is true.

**Allowed protocols:** `web_app_allowed_protocols` from app config (defaults: `http`, `https`). Telegram schemes (`tg://`, `tonsite://`, `ton://`) route through `UrlClickHandler::Open()`.

**Session management:**
- Prolong timeout: 60 seconds (`kProlongTimeout`) -- periodic `MTPmessages_ProlongWebView`.
- Bot list refresh: 3600 seconds (`kRefreshBotsTimeout`).
- Process click timeout: 1000ms.
- Clipboard read timeout: 10000ms.

**Webview events (JS to native):**
- `web_app_data_send` -- transmit data back to bot.
- `web_app_set_header_color`, `web_app_set_background_color`, `web_app_set_bottom_bar_color` -- color overrides.
- `web_app_setup_main_button`, `web_app_setup_secondary_button` -- button configuration.
- `web_app_request_fullscreen`, `web_app_exit_fullscreen` -- fullscreen toggle.
- `web_app_read_text_from_clipboard` -- clipboard access.
- `web_app_request_file_download` -- file download.
- `web_app_close` -- close panel.

Communication protocol: JSON array `[command, arguments]` posted via `TelegramWebviewProxy`.

---

### 30.7 Bot Start Screen

When opening a bot conversation for the first time (no messages), a special empty state is displayed.

**Empty state painter:** `HistoryView::EmptyPainter` renders the initial view when `_history->isDisplayedEmpty()` returns true.

**Bot image:** Generated by `GenerateManagedBotImage()`. Dimensions: `managedBotImageWidth` = 280px wide, `managedBotImageHeight` = 140px tall. Background: gradient from bot's emoji status or peer color; falls back to userpic colors indexed by user ID.

**Description text:** Parsed with `ItemTextBotNoMonoOptions`. Displayed as a service-style message block.

**Intro area:**
- Width: `chatIntroWidth` = 224px.
- Sticker: `chatIntroStickerSize` = 96px (greeting sticker if set by bot).
- Sticker padding: `chatIntroStickerPadding` = margins(10px, 8px, 10px, 16px).
- Title margin: `chatIntroTitleMargin` = margins(11px, 16px, 11px, 4px).
- Body margin: `chatIntroMargin` = margins(11px, 0px, 11px, 0px).
- Label opacity: `kLabelOpacity` = 0.85 for secondary text.

**Service message styling:** Background `msgServiceBg`, padding `msgServicePadding` = margins(12px, 3px, 12px, 4px), margin `msgServiceMargin` = margins(10px, 10px, 10px, 2px), font `msgServiceFont` = semibold, centered alignment.

**Start button:** Full-width `historyComposeButton` at bottom of compose area. Style: `FlatButton` with `windowActiveTextFg` text, `historyComposeButtonBg` background, `historyComposeButtonBgOver` hover, `-32px` auto width, 46px height, `textTop` 14px, semibold font. Ripple: `historyComposeButtonBgRipple`. Text: "START" (`lng_bot_start`) or "RESTART" (`lng_bot_restart`). Left-click sends `/start`; right-click clears start token.

**Bot profile actions** (info panel):
- `/help` command button: Shown if bot declares help command.
- `/settings` command button: Shown if bot declares settings command.
- Privacy policy: Opens URL or sends `/privacy`.
- "Add to Group" button: Opens `AddBotToGroupBoxController`.
- Main app button: Shown if `info->hasMainApp`, launches Web App.
- Block/Restart: Contextual text based on current bot state.

---

### 30.8 Game Messages

Game messages render as web page-style cards inside message bubbles.

**Card structure:**
- Title: `webPageTitleStyle` (semibold font), `semiboldPalette` text color, up to 2 lines with elision.
- Description: `webPageDescriptionStyle` (normal font), up to 4096 lines with elision.
- Skip between sections: `mediaInBubbleSkip` = 5px.
- Padding: `msgPadding` (bubble padding), applied asymmetrically for top/bottom bubble position.
- Line height: `UnitedLineHeight()` for consistent vertical spacing.

**Media attachment:** Photo or document rendered below text. Aspect-fill scaling.

**Game badge:** "GAME" label in uppercase, `msgDateFont`, positioned bottom-right of media with `msgDateImgDelta` offset. Background: `msgDateImgBgCorners` (rounded semi-transparent).

**Open button:** Full-width button below the card. Style: `semiboldFont` text, separated by `historyPageButtonLine` = 1px line. Height: `historyPageButtonHeight` = 36px. Padding: `historyPageButtonPadding` = margins(13px, 8px, 13px, 8px). Text: "Play" or customized label. Color: theme icon color.

**Ripple:** `RippleAnimation::RoundRectMask()` with `_st.radius` on click.

**Score service messages:** Displayed as centered service messages with `msgServiceBg` background. Text: "{User} scored {X} in {Game}". Font: `msgServiceFont` (semibold). Padding: `msgServicePadding`. Clicking navigates to the game via `HistoryServiceGameScore::lnk`.

---

### 30.9 Login URL Buttons (Auth Confirmation Dialog)

When a user clicks an inline keyboard button of type `Auth`, a confirmation dialog appears.

**Dialog contents:**
- Bot user profile info (userpic and name).
- Account switcher menu (top-right) for multi-account users.
- Device/browser/location details: browser, platform, IP, region.
- Match code display with emoji representation (if `matchCodesFirst` enabled).

**Checkbox options:**
1. "Allow bot to send me messages" -- toggles `result.allowWrite`.
2. "Share my phone number" -- toggles `result.sharePhone`.

**Buttons:**
- Primary: "Allow" (`lng_allow_bot`).
- Secondary: "Deny" (`lng_url_auth_phone_sure_deny`).
- Confirmation title: `lng_url_auth_phone_sure_title`.

**Flow:** Match code verification (if required) -> Auth dialog with account selection -> Phone sharing confirmation (if requested) -> `MTPmessages_AcceptUrlAuth` on approval, `MTPmessages_DeclineUrlAuth` on denial. Success/failure toast with domain info.

---

### 30.10 Bot Payments (Invoice & Receipt)

Bot payment flows use a dedicated panel.

**Panel size:** `paymentsPanelSize` = 392x600px.

**Invoice cover section:**
- Thumbnail: `paymentsThumbnailSize` = 80x80px, scaled by device pixel ratio.
- Thumbnail skip: `paymentsThumbnailSkip` = 18px from text.
- Cover padding: `paymentsCoverPadding` = margins(26px, 0px, 26px, 13px).
- Title: `paymentsTitle` style, `paymentsTitleTop` = 0px.
- Description: `paymentsDescription` style, `paymentsDescriptionTop` = 3px.
- Seller: `paymentsSeller` style, `paymentsSellerTop` = 4px.

**Prices section:**
- Price padding: `paymentsPricePadding` = margins(28px, 6px, 28px, 5px).
- Top skip: `paymentsPricesTopSkip` = 12px.
- Bottom skip: `paymentsPricesBottomSkip` = 13px.
- Individual rows: label left-aligned, amount right-aligned.
- Shipping costs row (from selected shipping option).
- Tips row (clickable to modify amount).
- Total: `paymentsFullPriceAmount` emphasis style.

**Tips buttons:**
- Padding: `paymentsTipButtonsPadding` = margins(26px, 6px, 26px, 6px).
- Button: `paymentsTipButton`, width `-16px` (auto), height 28px, `textTop` 5px.
- Skip between tips: `paymentsTipSkip` = 8px.
- Dynamic width allocation; wraps to new rows if needed.
- Selected tip: `_tipChosen` style (highlighted). Unselected: `_tipButton` with reduced opacity.
- Error text padding: `paymentTipsErrorPadding` = margins(22px, 6px, 22px, 0px).

**Section buttons** (6 editable sections):
- Payment method, shipping address, shipping method, name, email, phone.
- Button padding: `paymentsSectionButton.padding` = margins(68px, 11px, 14px, 9px).
- Disabled in receipt view via `WA_TransparentForMouseEvents`.

**Shipping section:**
- Margin: `paymentsShippingMargin` = margins(27px, 11px, 27px, 20px).
- Label position: `paymentsShippingLabelPosition` = point(43px, 8px).
- Price position: `paymentsShippingPricePosition` = point(43px, 29px).

**Field input:**
- Field padding: `paymentsFieldPadding` = margins(28px, 0px, 28px, 2px).
- Money field text margins: margins(0px, 4px, 0px, 4px), `heightMin` 30px.
- Expire/CVC skip: `paymentsExpireCvcSkip` = 34px.
- Save checkbox padding: `paymentsSaveCheckboxPadding` = margins(28px, 20px, 28px, 8px).

**Submit button:** `paymentsPanelButton`, width `-36px`, height 36px. Text: "Pay {amount}" when unpaid; hidden when paid.

**Cancel button:** Text: "Cancel" (unpaid) or "Done" (receipt).

**Progress:** `paymentsLoading` = 24x24px, thickness 4px. Fade: 200ms, opacity 0.3. `InfiniteRadialAnimation`.

**Receipt mode:** Same layout as invoice. Date: `langDateTime()` formatting. Dividers between sections. Total shows `receipt.totalAmount`. Tips = total minus computed amount. Section buttons disabled.

**Provider info:** `paymentsToProviderPadding` = margins(28px, 6px, 28px, 6px).
**Billing title padding:** `paymentsBillingInformationTitlePadding` = margins(28px, 26px, 28px, 1px).
**Sections top skip:** `paymentsSectionsTopSkip` = 11px.
**Critical error padding:** `paymentsCriticalErrorPadding` = margins(10px, 40px, 10px, 0px).

**Webview integration:** Payment method selection via embedded `Webview::Window` with theme parameters and `TelegramWebviewProxy` for event posting. `InfiniteRadialAnimation` during loading with `radialDuration * 2` fade and 0.3 opacity.

---

### 30.11 Bot Settings Button in Chat Header

No dedicated "bot settings" button exists in the chat header bar. Bot settings access is routed through the info panel profile actions:

- `/settings` command: Appears as a button in the bot's profile/info panel (third column or layer) if the bot declares a settings command in `botInfo->commands`.
- `/help` command: Same placement, shown if declared.
- Privacy policy: Button in info panel linking to `botInfo->privacyPolicyUrl` or sending `/privacy`.
- Restart/Block: Contextual button in info panel.
- Business bot bar: For business bots assigned to conversations, a `BusinessBotStatus::Bar` appears at the top of the chat with pause/resume toggle and manage/remove options (`historyBusinessBotToggle` styling).

---

### 30.12 Pixel Dimensions Summary

| Constant | Value | Context |
|---|---|---|
| `botKbDuration` | 200ms | Keyboard show/hide & button hover animation |
| `botKbButton.margin` | 10px | Reply keyboard button gap |
| `botKbButton.padding` | 10px | Reply keyboard button inner padding |
| `botKbButton.height` | 38px | Reply keyboard button height |
| `botKbTinyButton.margin` | 4px | Tiny reply keyboard button gap |
| `botKbTinyButton.height` | 25px | Tiny reply keyboard button height |
| `msgBotKbButton.margin` | 2px | Inline keyboard button gap |
| `msgBotKbButton.padding` | 10px | Inline keyboard button inner padding |
| `msgBotKbButton.height` | 36px | Inline keyboard button height |
| `msgBotKbIconPadding` | 4px | Icon offset in inline button |
| `historyBotMenuMaxWidth` | 160px | Bot menu button max label width |
| `historyBotMenuSkip` | 8px | Bot menu button spacing |
| `historyBotMenuButton.height` | 30px | Bot menu button height |
| `botDescSkip` | 8px | Bot description spacing |
| `botWebViewPanelSize` | 384x694px | Web App panel default size |
| `botWebViewBottomButton.height` | 40px | Web App main/secondary button height |
| `botWebViewBottomPadding` | 12px all sides | Web App bottom bar padding |
| `botWebViewBottomSkip` | 12px x 8px | Spacing between main & secondary buttons |
| `botWebViewRadialStroke` | 3px | Web App progress spinner stroke |
| `botWebViewMenu.maxHeight` | 360px | Web App menu popup max height |
| `paymentsPanelSize` | 392x600px | Payment panel size |
| `paymentsThumbnailSize` | 80x80px | Invoice product thumbnail |
| `paymentsTipButton.height` | 28px | Tip amount button height |
| `emojiPanWidth` | 345px | Inline results panel width |
| `inlineResultsMinHeight` | 278px | Inline results panel min height |
| `inlineResultsMaxHeight` | 640px | Inline results panel max height |
| `inlineMediaHeight` | 96px | Inline result media item height |
| `inlineThumbSize` | 64px | Inline result thumbnail size |
| `inlineThumbSkip` | 10px | Gap between thumb and text |
| `inlineResultsSkip` | 3px | Gap between inline items |
| `inlineResultsLeft` | 11px | Left margin for results content |
| `inlineRowMargin` | 6px | Vertical margin per result row |
| `inlineRadialSize` | 44px | Loading spinner in inline results |
| `mentionHeight` | 40px | Command autocomplete row height |
| `mentionPhotoSize` | 33px | Command autocomplete userpic size |
| `chatIntroWidth` | 224px | Bot intro area width |
| `chatIntroStickerSize` | 96px | Bot intro greeting sticker size |
| `managedBotImageWidth` | 280px | Bot about image width |
| `managedBotImageHeight` | 140px | Bot about image height |
| `historyComposeButton.height` | 46px | Start/Restart button height |
| `historyPageButtonHeight` | 36px | Game "Play" button height |
| `msgServicePhotoWidth` | 100px | Service message photo width |
| `historyBotCommandStart` (inherited) | 44x46px | Slash command button size |

## 31. Saved Messages

Saved Messages is a special self-chat that doubles as a personal bookmarking system. Users forward messages to themselves, and Telegram Desktop groups those forwards into virtual sub-chats (sublists) based on the original sender/channel. Messages sent directly (not forwarded) appear under "My Notes." A reaction-based tagging system lets users attach custom emoji tags to saved messages and filter by them.

Source files: `data/data_saved_messages.cpp/h`, `data/data_saved_sublist.cpp/h`, `data/data_message_reactions.cpp/h`, `data/data_message_reaction_id.cpp/h`, `info/saved/info_saved_sublists_widget.cpp/h`, `dialogs/ui/dialogs_layout.cpp`, `ui/empty_userpic.cpp/h`, `history/view/history_view_chat_section.cpp/h`, `history/view/history_view_self_forwards_tagger.cpp/h`, `history/view/history_view_subsection_tabs.cpp/h`, `window/window_main_menu.cpp`, `window/window_session_controller.cpp`.

### 31.1 Saved Messages Chat Entry

Saved Messages appears as a special peer in the chat list. The peer is the user themselves (`session().user()`, `isSelf() == true`).

**Chat list row rendering:** Uses the standard `DialogRow` layout (62px height, 10/8/10/8 padding) but replaces the userpic with a dedicated bookmark icon. Rendering is flag-driven via `Flag::SavedMessages` in `dialogs_layout.cpp`.

**Avatar (bookmark icon):** Painted by `EmptyUserpic::PaintSavedMessages()`. The icon is a vertical-gradient circle with a bookmark silhouette:

- **Background gradient:** Linear vertical gradient from `historyPeerSavedMessagesBg` (top) to `historyPeerSavedMessagesBg2` (bottom). These resolve to `historyPeer4UserpicBg` / `historyPeer4UserpicBg2` = **#5caffa** (top) to **#408acf** (bottom) -- a medium-to-dark blue gradient matching peer color index 4.
- **Icon foreground:** `historyPeerUserpicFg` (white).
- **Bookmark shape** (painted by `PaintSavedMessagesInner()`): A vector path drawn with `QPainterPath`, not a raster icon. Dimensions scale proportionally to `size` (typically 46px for chat list):
  - Stroke thickness: `size * 0.055` (~2.5px at 46px)
  - Bookmark width: `SafeRound(size * 0.15) * 2 + increment` (~14px at 46px)
  - Bookmark height: `SafeRound(size * 0.19) * 2 + increment` (~18px at 46px)
  - Bottom notch offset: `SafeRound(size * 0.064)` (~3px at 46px)
  - Centered within the circle. Top half uses `Qt::RoundJoin` (rounded top corners). Bottom half uses `Qt::MiterJoin` (sharp V-notch at center bottom). Cap style: `Qt::FlatCap`.
  - Shape: Rectangle top (left-top-right path), then left-down to bottom-left, angled line to center (bottom minus notch offset), angled line to bottom-right, right-up to midpoint.

**Chat name:** `tr::lng_saved_messages` ("Saved Messages"). Rendered with standard `dialogsNameFg` / semibold font. No chat-type icon prefix, no verified badge.

**Positioning in chat list:** No `fixedOnTopIndex` -- Saved Messages sorts by last message date like any other chat. It appears at whatever position its most recent message dictates. Pinning is supported (user can pin Saved Messages to top).

**Menu entry (hamburger drawer):** A "Saved Messages" menu item is added via `addAction()` with icon `st::menuIconSavedMessages`. Click handler: `controller->showPeerHistory(controller->session().user())`. Visibility controlled by `settings.showSavedMessagesInDrawer()` (AyuGram setting; always shown in stock Telegram).

### 31.2 Saved Messages Sub-Peers (Sublists)

When the user opens Saved Messages, the view transitions to a sublist-based browsing mode. Each sublist represents messages forwarded from a single source peer (user, group, channel, bot). Messages sent directly by the user (no forward origin) are grouped under "My Notes."

**Data model:** `SavedMessages` owns a `base::flat_map<PeerData*, unique_ptr<SavedSublist>>` keyed by the original forwarding peer. Each `SavedSublist` extends `Data::Thread` (same base class as `ForumTopic`), giving it full chat-list integration: unread counts, badges, pinning, sorting by last message date.

**Sublist creation:** Sublists are created lazily via `SavedMessages::sublist(peer)`. The `sublistLoaded(peer)` variant returns null if not yet fetched from the server.

**Chat list name:** `SavedSublist::chatListName()` delegates to the underlying peer's `chatListName()` -- so a sublist for channel "TechNews" displays "TechNews", a sublist for user "Alice" displays "Alice", etc.

**Sort key:** Same delegation -- `chatListNameSortKey()` from the peer history. Sublists sort by last message timestamp in the saved-messages-specific `Dialogs::MainList` (separate from the main chat list).

**Visibility:** `shouldBeInChatList()` returns true if the sublist has a displayable (non-service) last message, or is pinned. Empty sublists with no messages are hidden.

**Fixed position:** `fixedOnTopIndex()` returns 0 -- no sublist is permanently pinned to top. Pinning uses the standard dialog pinning system.

### 31.3 Sublist Navigation & Info Panel

**Opening sublists view:** When the user navigates to Saved Messages, `InnerWidget::showSavedSublists()` activates:

```
_savedSublists = &session().data().savedMessages();
_filterId = 0;
_openedForum = nullptr;
_st = &st::defaultDialogRow;
refreshShownList();
```

The dialog list widget switches to displaying sublists from `savedMessages().chatsList()` instead of the main chat list. Each sublist row uses the standard `defaultDialogRow` style (62px height).

**Sublist row rendering:** Each row shows the source peer's avatar and name. The avatar is the peer's actual userpic (not the bookmark icon). The message preview shows the most recent saved message from that source. Unread badges display if there are unread saved messages in that sublist.

**Clicking a sublist:** Creates a `ChatMemento` with the sublist reference and navigates via `showSection()`. The `ChatWidget` stores the sublist in `_sublist` and derives `_monoforumPeerId` when applicable:

```
._monoforumPeerId((_sublist && _sublist->parentChat())
    ? _sublist->sublistPeer()->id
    : PeerId())
```

**Top bar in sublist view:** The top bar shows a custom title. Initially displays `tr::lng_contacts_loading` ("Loading...") while data loads. Once resolved:
- If peer is self: displays `tr::lng_my_notes` ("My Notes")
- If peer is hidden author: displays `tr::lng_hidden_author_messages` ("Author Hidden")
- Otherwise: displays the source peer's name

**Info panel (third column):** The `SublistsWidget` (`info/saved/info_saved_sublists_widget.cpp`) provides an info panel view:
- **Title:** `tr::lng_saved_messages` ("Saved Messages")
- **Subtitle:** Dynamic chat count -- `tr::lng_filters_chats_count` formatted ("N chats"), or `tr::lng_contacts_loading` ("Loading...") while fetching. Count from `chatsList()->fullSize()`.
- **Content:** A `Dialogs::InnerWidget` showing the full sublist list, scrollable.
- **Media filter section** (`setupOtherTypes()`): Below the sublist list, a `SlideWrap<VerticalLayout>` with 8 media-type filter buttons:
  - Photo (`infoIconMediaPhoto`)
  - Video (`infoIconMediaVideo`)
  - File (`infoIconMediaFile`)
  - Audio/Music (`infoIconMediaAudio`)
  - Link (`infoIconMediaLink`)
  - Poll (`infoIconMediaPoll`)
  - Voice/Round (`infoIconMediaVoice`)
  - GIF (`infoIconMediaGif`)
  - Each button has a `FloatingIcon` overlay at `st::infoSharedMediaButtonIconPosition`.
  - Section is wrapped in `SlideWrap` for animated show/hide.
  - Spacing: `st::infoProfileSkip` above and below the button group.
  - Divider separator between sublist list and media buttons.

**State persistence:** Uses memento pattern (`SublistsMemento`). Saves/restores scroll position. `Section::Type::SavedSublists` identifies this section type. On unsupported (server signals saved messages not available), auto-navigates backward.

### 31.4 My Notes

"My Notes" is the sublist for messages the user sends directly to Saved Messages without forwarding from another source. The peer is the user themselves (`isSelf() == true`).

**Avatar:** Painted by `EmptyUserpic::PaintMyNotes()`, which delegates to `PaintMyNotesInner()` -> `PaintIconInner()`. Uses the same blue gradient background as Saved Messages (`historyPeerSavedMessagesBg` / `historyPeerSavedMessagesBg2`), but with a different icon: `st::dialogsMyNotesUserpic` which references the asset `"dialogs/avatar_notes"` tinted with `historyPeerUserpicFg` (white). This is a notepad/document icon rather than the bookmark.

**Display name:** `tr::lng_my_notes` ("My Notes"). Used in:
- The sublist row when browsing saved messages sublists
- The top bar title when viewing My Notes messages
- The chat list row if shown as `Flag::MyNotes`

**Behavior:** Identical to other sublists -- supports unread counts, pinning, message preview in row, read state tracking.

### 31.5 Saved Messages Loading & Pagination

**Initial load:** `preloadSublists()` is called when entering saved messages. If fewer than `kLoadedSublistsMinCount` (20) sublists are loaded, triggers `loadMore()`.

**Pagination constants:**
- `kFirstPerPage = 10` -- first batch of sublists per request
- `kPerPage = 50` -- subsequent batches
- `kListFirstPerPage = 20` -- first batch for list API call
- `kListPerPage = 100` -- subsequent list batches
- `kLoadedSublistsMinCount = 20` -- minimum loaded before stopping auto-load
- `kShowSublistNamesCount = 5` -- max recent sublists tracked for display
- `kStalePerRequest = 100` -- batch size for stale peer refresh

**API calls:**
- `MTPmessages_GetSavedDialogs` -- fetches sublist entries with pagination offsets (date, message ID, peer). Flags control pinned-only vs all, and parent peer filtering.
- Pinned sublists loaded separately via `loadPinned()` with a dedicated `_pinnedRequestId`.
- Stale peers (needing refresh) queued in `_stalePeers` and processed in batches of 100 via `requestSomeStale()`.

**Offset tracking:** `SavedMessagesOffsets { TimeId date, MsgId id, PeerData *peer }` -- standard Telegram pagination cursor. Updated from the last valid message in each response batch.

**Recent sublists:** `reorderLastSublists()` maintains a sorted vector of up to `kShowSublistNamesCount + 1` (6) sublists, sorted by message date. Version counter `_lastSublistsVersion` increments on changes, signaling UI refresh.

### 31.6 Reaction Tags System

Saved messages support a reaction-based tagging system. Users attach emoji reactions to saved messages as "tags," then filter by tag to find messages. Tags are per-message reactions that function as categorization labels.

**Data structures:**

`MyTagInfo` struct:
- `ReactionId id` -- tag identifier (either a standard emoji string or a custom emoji `DocumentId`)
- `QString title` -- user-assigned custom name for the tag
- `int count` -- number of messages with this tag

`TagsBySublist` struct (stored in `Reactions::_myTags` flat map, keyed by `SavedSublist*`):
- `vector<Reaction> tags` -- resolved reaction objects
- `vector<MyTagInfo> info` -- tag metadata
- `int hash` -- server hash for change detection
- `mtpRequestId requestId` -- pending request tracker
- Scheduling flags for request/update batching

**Tag operations on `Reactions` class:**
- `refreshMyTags(SavedSublist*)` -- fetches tags from server via `MTPmessages_GetSavedReactionTags`. Supports both global (null sublist) and per-sublist tag queries.
- `myTagsInfo()` -- returns vector of `MyTagInfo` for a sublist
- `myTagTitle(ReactionId)` -- returns custom title for a tag
- `incrementMyTag(ReactionId, SavedSublist*)` -- increments count, maintains sorted order by count
- `decrementMyTag(ReactionId, SavedSublist*)` -- decrements count, re-sorts
- `renameTag(ReactionId, QString)` -- updates title across all sublists, schedules server sync
- `myTagsUpdates()` / `myTagRenamed()` -- reactive signal producers for UI updates
- `myTagsValue(SavedSublist*)` -- yields reactive producer of tag list

**Tag resolution:** `resolveByInfos()` / `resolveByInfo()` convert `MyTagInfo` entries into full `Reaction` objects with emoji rendering data and custom titles. Tags support both standard Unicode emoji and custom emoji (animated stickers).

### 31.7 Tag-Based Search & Filtering

Tags integrate with the search system through query string encoding. When a user selects a tag to filter by, it's converted to a search query that the message search API understands.

**Conversion functions** (in `data_message_reaction_id.cpp`):

`SearchTagToQuery(ReactionId)`:
- Custom emoji tag -> `"#tag-custom:{documentId}"`
- Standard emoji tag -> `"#tag-emoji:{emoji}"`
- Empty tag -> empty string

`SearchTagFromQuery(QString)`:
- Parses the first space-delimited token of a query string
- Recognizes `#tag-custom:` and `#tag-emoji:` prefixes
- Returns the corresponding `ReactionId`

`SearchTagsFromQuery(QString)`:
- Returns a vector of `ReactionId` parsed from the query (currently supports one tag per query)

**Filtering flow:** When user clicks a tag in the tag bar, the UI constructs a search query using `SearchTagToQuery()`, then runs a standard saved-messages search with that query. The search API (`MTPmessages_GetSavedReactionTags`) filters server-side, returning only messages with the matching reaction tag.

### 31.8 Forward-to-Saved Flow & Self-Forwards Tagger

When a user forwards messages to Saved Messages, a post-forward tagging UI appears.

**Forward destination:** In the forward dialog, selecting the user's own chat (self) forwards to Saved Messages. The messages appear in the sublist corresponding to the original source chat/user.

**Self-forwards tagger** (`SelfForwardsTagger`):

Constructor accepts: `SessionController`, parent widget, list widget factory, scroll widget, history factory. Sets up observation of recent self-forwards and chat join events.

**Tag suggestion toast:** After forwarding to saved, `showSelectorForMessages(MessageIdsList)` triggers:
1. Fetches available reactions/tags
2. Creates an emoji selector widget
3. Attaches it to a toast notification showing the forwarding confirmation
4. User can tap an emoji to tag the just-forwarded messages

**Toast behavior:**
- Auto-dismiss timer: **3 seconds** initial, resets to **2 seconds** on mouse leave
- Mouse hover pauses the countdown
- Click on the toast body cancels the auto-dismiss
- Three toast types:
  1. Initial forward notification with emoji tag selector
  2. Confirmation toast showing the selected emoji tag
  3. Channel filter suggestion for newly joined channels

**Tagged confirmation toast:** After selecting a tag, `showTaggedToast(DocumentId)` displays a brief confirmation showing which emoji was applied.

**Event filtering:** Installs `QObject::eventFilter` to detect mouse clicks and hover states, coordinating selector visibility with user engagement. Uses weak pointers for lifecycle safety and deferred deletion during animations.

### 31.9 Subsection Tabs (Saved Messages Mode)

When viewing saved messages sublists, the subsection tabs system (`history_view_subsection_tabs.cpp`) provides tabbed navigation across sublists, similar to forum topic tabs.

**Three layout modes:**
- `Left` (vertical): Side panel with vertical scrolling
- `Top` (horizontal): Top bar strip with horizontal scrolling
- `Bottom` (horizontal): Bottom bar strip with horizontal scrolling

**Tab rendering:**
- Each tab represents a saved sublist (source peer)
- Tab label: peer name
- Tab icon: custom emoji thumbnail via `Ui::DynamicImage` (peer avatar rendered as emoji-sized thumbnail)
- Active tab: highlighted with accent indicator
- Unread badges per tab reflecting sublist unread state

**Scrolling behavior:**
- Mouse wheel on horizontal tabs: Y-axis scroll is redirected to X-axis
- Auto-load: When `scrollMax <= 3 * fullWidth`, doubles the slice limit and triggers `refreshAroundMiddle()`
- Slice limits: initial 12 items, increased dynamically as user scrolls

**Toggle button:** Directional icon button (`st::chatTabsToggle` dimensions) to show/hide the tab strip.

**Reordering:** Drag-reorder supported for pinned sublists. `ApplyReorder()` validates position ranges, reorders the slice vector, and syncs pinned order via `savePinnedOrder()` API call.

**Context menu:** Right-click on a tab opens a context menu via `Window::FillDialogsEntryMenu()` with `SubsectionTabsMenu` entry point, providing thread-specific options (pin, mute, delete, etc.).

**Visual details:**
- Background: window background fill
- Shadow: `st::lineWidth` (1px) foreground shadow for depth
- Ripple animation on tab interaction
- Custom emoji rendering with pause states for performance

### 31.10 Chat List Row with Tags

When a dialog row has associated filter tags, the row height increases to accommodate tag pills below the message preview.

**Tagged dialog row:** `taggedDialogRow` extends `defaultDialogRow`:
- Height: **72px** (vs standard 62px)
- Text top: **30px**
- Tag top: **52px** (vertical position of tag pills)

**Tagged forum dialog row:** `taggedForumDialogRow` extends `forumDialogRow`:
- Height: **96px** (vs standard 80px)
- Tag top: **77px**

**Tag pill rendering:** Tags are pre-rendered as `QImage` objects (cached), drawn via `p.drawImage()` at position `(nameLeft, tagTop)`. Multiple tags render horizontally with `dialogRowFilterTagSkip` (4px) gap between each.

**Tag pill style:**
- Font: `dialogRowFilterTagStyle` = 10px (smaller than message preview text)
- Horizontal layout starting at `nameLeft` (68px, same as chat name and message preview)

**Search tag positioning:**
- `searchTagSkip`: **8px horizontal, 4px vertical** offset
- `searchTagBottom`: **10px** bottom margin

### 31.11 Hidden Author Messages

A special sublist type for messages forwarded from users who have privacy settings hiding their identity.

**Display name:** `tr::lng_hidden_author_messages` ("Author Hidden" / "Hidden Author Messages").

**Avatar:** Uses a generic hidden-author userpic (not the bookmark or notes icon). Rendered via the standard deleted/hidden account avatar system.

**Behavior:** Functions identically to named sublists -- supports unread counts, pinning, tag filtering, and all standard sublist operations. The user cannot navigate to the original author's profile since the identity is hidden.

### 31.12 Saved Messages in Search

When searching globally, Saved Messages appears in results if the search query matches message content within saved messages.

**Search integration:** The search controller queries saved messages using the same `MTPmessages_Search` / `MTPmessages_SearchGlobal` APIs. Results appear in the standard search results list with the Saved Messages bookmark avatar and "Saved Messages" name.

**Tag search:** Users can combine tag filters with text search. The tag is encoded as the first token of the query string (`#tag-custom:ID` or `#tag-emoji:EMOJI`), and the text query follows after a space.

### 31.13 Unread State Management

**Per-sublist unreads:** Each `SavedSublist` tracks its own unread count via `unreadCountCurrent()` and `displayedUnreadCount()`. Read position tracked per inbox/outbox direction.

**Read marking:** `readTill()` marks messages as read locally and schedules server sync via `MTPmessages_ReadSavedHistory`. A batching timer prevents excessive API calls.

**Global operations:** `SavedMessages::clearAllUnreadReactions()` clears reaction-unread state across all sublists. `markUnreadCountsUnknown(readTillId)` resets counts after desync, triggering fresh server data fetch. `updateUnreadCounts(readTillId, counts)` applies server-provided per-sublist counts.

**Chat list badges:** `chatListUnreadState()` and `chatListBadgesState()` provide unread state for the dialog list rendering, including muted/unmuted distinction.

### 31.14 Saved Messages API Updates

The data layer handles several server-pushed updates:

- `MTPDupdatePinnedSavedDialogs` -- Server notifies about pinned sublist order changes. Handled by `SavedMessages::apply()`, triggers `refreshPinned()`.
- `MTPDupdateSavedDialogPinned` -- Individual sublist pin/unpin notification.
- `applySublistDeleted(PeerData*)` -- Removes a sublist when server signals deletion.
- `listMessageChanged(from, to)` -- Updates sublist ordering when a message changes (edit, delete).
- `recentSublistsInvalidate(SavedSublist*)` -- Marks a sublist's recent-list position as stale.

**Active subsection tracking:** `saveActiveSubsectionThread(Thread*)` / `activeSubsectionThread()` persist the currently-viewed sublist across navigation, stored as `_activeSubsectionSublist`.

### 31.15 Pixel Dimensions & Constants Summary

| Token | Value | Description |
|-------|-------|-------------|
| `defaultDialogRow.height` | **62px** | Standard sublist row height |
| `defaultDialogRow.padding` | **10, 8, 10, 8 px** | Row padding (L,T,R,B) |
| `defaultDialogRow.photoSize` | **46px** | Sublist avatar diameter |
| `defaultDialogRow.nameLeft` | **68px** | Name text x-position |
| `defaultDialogRow.nameTop` | **10px** | Name text y-position |
| `defaultDialogRow.textLeft` | **68px** | Message preview x-position |
| `defaultDialogRow.textTop` | **34px** | Message preview y-position |
| `taggedDialogRow.height` | **72px** | Row height with tag pills |
| `taggedDialogRow.textTop` | **30px** | Message preview y (with tags) |
| `taggedDialogRow.tagTop` | **52px** | Tag pill y-position |
| `taggedForumDialogRow.height` | **96px** | Forum row height with tags |
| `taggedForumDialogRow.tagTop` | **77px** | Forum tag pill y-position |
| `dialogRowFilterTagSkip` | **4px** | Horizontal gap between tag pills |
| `dialogRowFilterTagStyle.font` | **10px** | Tag pill text font size |
| `searchTagSkip` | **8px, 4px** | Search tag offset (horiz, vert) |
| `searchTagBottom` | **10px** | Search tag bottom margin |
| Bookmark thickness | **size * 0.055** | ~2.5px at 46px avatar |
| Bookmark width | **SafeRound(size * 0.15) * 2 + inc** | ~14px at 46px avatar |
| Bookmark height | **SafeRound(size * 0.19) * 2 + inc** | ~18px at 46px avatar |
| Bookmark notch | **SafeRound(size * 0.064)** | ~3px at 46px avatar |
| `historyPeerSavedMessagesBg` | **#5caffa** | Avatar gradient top (blue) |
| `historyPeerSavedMessagesBg2` | **#408acf** | Avatar gradient bottom (darker blue) |
| `historyPeerUserpicFg` | **#ffffff** | Bookmark/notes icon color |
| `dialogsMyNotesUserpic` | `"dialogs/avatar_notes"` | My Notes icon asset |
| `menuIconSavedMessages` | (style ref) | Hamburger menu icon |
| `kFirstPerPage` | **10** | First sublist fetch batch |
| `kPerPage` | **50** | Subsequent sublist fetch batch |
| `kListFirstPerPage` | **20** | First list API batch |
| `kListPerPage` | **100** | Subsequent list API batch |
| `kLoadedSublistsMinCount` | **20** | Auto-load threshold |
| `kShowSublistNamesCount` | **5** | Recent sublists tracked |
| `kStalePerRequest` | **100** | Stale peer refresh batch |
| Toast auto-dismiss (initial) | **3000ms** | Self-forward tag toast |
| Toast auto-dismiss (mouse leave) | **2000ms** | Reset after hover |
| Tag name max length | **16 chars** | `InputField` limit in edit UI |
| Subsection tabs slice limit | **12** (initial) | Tab items before auto-expand |

---

## 32. Stories

Stories are ephemeral full-screen media posts (photo or video) that expire after 24 hours. They appear as a horizontal scrollable strip of circular avatars above the chat list, and open in a dedicated full-screen overlay viewer with progress bars, reactions, and reply compose. Users can post stories with privacy controls, pin them to their profile as highlights, and view them anonymously via stealth mode.

Source files: `media/stories/` (viewer, controller, slider, header, reactions, reply, stealth, caption, sibling, share, recent_views, repost_view), `dialogs/ui/dialogs_stories_list.cpp` + `dialogs_stories_content.cpp` (chat list bar), `info/stories/` (profile highlights), `data/data_story.h/.cpp` + `data/data_stories.h/.cpp` (data model), `editor/` (story creation editor).

### 32.1 Stories Bar (Chat List)

A horizontal strip of circular avatar thumbnails displayed above the chat list, below the search bar and folder tabs. Only shown in the main layout (not child layouts like forum topics).

#### Layout States

Two states with animated transition (`kExpandCatchUpDuration = 200ms`):

**Collapsed (Small) state:**
- Height: **35px** (`dialogsStories.height`)
- Avatar size: **21px** (`small.photo`), positioned at (4px left, 4px top)
- Horizontal shift per item: **16px** (`small.shift`)
- Ring thickness (unread): **3px** (`small.lineTwice` / 2 = 1.5px rendered)
- Ring thickness (read): **0px** (`small.lineReadTwice`)
- Name text: 11px left, 10px right, 3px top offset
- Max small thumbnails shown: **3** (`kSmallThumbsShown`)

**Expanded (Full) state:**
- Height: **77px** (`dialogsStoriesFull.height`)
- Avatar size: **42px** (`full.photo`), positioned at (10px left, 9px top)
- Ring thickness (unread): **4px** (`full.lineTwice` / 2 = 2px rendered)
- Ring thickness (read): **2px** (`full.lineReadTwice` / 2 = 1px rendered)
- Name text: 0px left/right, 56px top offset
- Name font: **11px** regular
- Read items opacity: **0.6** (`dialogsStoriesList.readOpacity`)
- Own stories: **1.0** opacity (`dialogsStoriesListMine.readOpacity`)

#### Expansion Trigger

- Expand when overscroll ratio exceeds **0.72** (`kExpandAfterRatio`)
- Collapse when ratio drops below **0.68** (`kCollapseAfterRatio`)
- Friction multiplier in collapsed state: **0.15** (`kFrictionRatio`)
- Virtual overscroll enabled when stories bar present; real overscroll when absent
- Expansion animation: `slideWrapDuration` (primary), `fadeWrapDuration` (fade in/out)
- Catch-up animation duration: **200ms** (`kExpandCatchUpDuration`)

#### Gradient Ring (Unread)

Unread stories display a gradient ring around the avatar. The gradient is a `QLinearGradient` running from top-right to bottom-left of the userpic rect.

- **Stop 0.0** (top-right): `groupCallLive1` = **#0dcc39** (green)
- **Stop 1.0** (bottom-left): `groupCallMuted1` = **#0992ef** (blue)

Created by `Ui::UnreadStoryOutlineGradient()`. For multiple unread stories, the ring is segmented into arcs (one per story) with small gaps between segments. Segments painted via `Ui::PaintOutlineSegments()` with spin animation progress.

Read stories use `dialogsUnreadBgMuted` color (muted gray) for the ring outline.

#### Scrolling & Ordering

- Horizontal scrolling via touch drag or mouse wheel (redirected from vertical)
- Drag threshold: `QApplication::startDragDistance()`
- Preload trigger: when `scrollLeftMax - scrollLeft < width * kPreloadPages` (2 pages)
- Ordering: reverse chronological by last story timestamp, with premium users weighted higher via `key = int64(last) + (premium ? (1 << 47) : 0)`
- "My Story" always first (if present), uses full opacity regardless of read state
- Hidden stories maintained in a separate sorted list

#### Interaction

- Tap on avatar: opens story viewer for that peer
- Long-press / right-click: shows context menu (`ShowMenuRequest`) with options per source
- Cursor: `cur_pointer` when hovering an item, `cur_default` otherwise
- Tooltip: shows up to **3** names (`kMaxTooltipNames`), max width `dialogsStoriesTooltipMaxWidth`
- AyuGram extension: `disableStories()` setting hides the bar entirely

### 32.2 Story Viewer Overlay

Full-screen overlay that displays stories one at a time with progress bars, header info, and navigation. Architecture: `View` (facade) delegates to `Controller` (all logic).

#### Content Area

- Max content size: **540 x 960px** (`storiesMaxSize`)
- Corner radius: **8px** (`storiesRadius`)
- Aspect ratio preserved; content centered in available space
- Header can be "Outside" (above content, when enough vertical space) or "Normal" (overlaid on content)

#### Sibling Previews

Previous/next peer stories are shown as blurred previews flanking the main content:

- Default width ratio: **0.448** of available space (`kSiblingMultiplierDefault`)
- Maximum width ratio: **0.72** (`kSiblingMultiplierMax`)
- Outside overflow: **0.24** (`kSiblingOutsidePart`) -- portion extending off-screen
- Userpic size: **0.3** of sibling width (`kSiblingUserpicSize`)
- Min sibling width: **200px** (`storiesSiblingWidthMin`)
- Base opacity: **0.5** (`kSiblingFade`), hover: **0.4** (`kSiblingFadeOver`)
- Name opacity: **0.8** default, **1.0** on hover (`kSiblingNameOpacity/Over`)
- Scale on hover: **+5%** (`kSiblingScaleOver = 0.05`)
- Thumbnail fade-in duration: **200ms** (`kGoodFadeDuration`)
- Corner radius: same `storiesRadius` (8px)
- Fallback: solid black fill when thumbnail unavailable
- Two-stage loading: blurred inline thumbnail first, then high-quality image with 200ms crossfade

#### Progress Bar (Slider)

Segmented progress bar at the top of the story content area:

- Bar height: **2px** (`storiesSliderWidth`)
- Segment gap: **4px** (`storiesSliderSkip`)
- Margin: **8px top, 7px top (inner), 8px left/right, 6px bottom** (`storiesSliderMargin: margins(8,7,8,6)`)
- Color: `mediaviewControlFg` (white/light)
- Active segment opacity: **1.0** (`kOpacityActive`)
- Inactive segment opacity: **0.4** (`kOpacityInactive`)
- Corner radius: `storiesSliderWidth / 2` (1px, fully rounded)
- Completed segments (before current): full opacity
- Current segment: split into active portion (filled based on progress) and inactive remainder
- Pending segments (after current): inactive opacity
- Dynamic width: `segmentWidth = (totalWidth - (count-1) * gap) / count`
- Maximum segments: **180** (`kMaxSegmentsCount`)

#### Photo Playback

- Duration: **5000ms** (5 seconds) per photo (`kPhotoDuration`)
- Progress update interval: **100ms** (`kPhotoProgressInterval`)
- Timer-based with manual callback progression

#### Video Playback

- Duration determined by video length; progress from media player track state
- Volume control: `storiesVolumeSize = 75px`, positioned `storiesVolumeBottom = 20px` from bottom
- Volume dropdown hide: short **20ms**, long **200ms** timeouts

#### Mark-as-Read

- Threshold: **0.2 seconds** after opening (`kMarkAsReadAfterSeconds`)
- Progress threshold: **0.0** (immediately once time threshold met)
- Server-side delay: **3000ms** (`kMarkAsReadDelay`) before sending read receipt
- View increment delay: **5000ms** (`kIncrementViewsDelay`)

#### Navigation

- Tap left third of content: previous story
- Tap right third of content: next story
- At story boundary within a peer: "subjump" to next/previous peer's stories
- Close: tap outside content area, swipe down, or Escape key
- Content fade on interaction: **0.6** opacity (`kFullContentFade`) with `fadeWrapDuration` animation using `sineInOut` easing

#### Pause Behavior

- Long-press on content: pauses playback (`contentPressed(true)` -> `togglePaused(true)`)
- Release: resumes
- Also pauses when: window inactive, reply field focused, layer/menu/tooltip shown
- `PauseState` enum: Playing, Paused, Inactive, InactivePaused

#### Preloading

- Peers ahead: **3** (`kPreloadPeersCount`)
- Stories ahead: **5** (`kPreloadStoriesCount`)
- Next media items: **3** (`kPreloadNextMediaCount`)
- Previous media items: **1** (`kPreloadPreviousMediaCount`)
- Max concurrent preload sources: **10** (`kMaxPreloadSources`)

### 32.3 Story Header

Overlaid at the top of the story content, below the progress slider.

#### Layout

- Margin: **12px left, 4px top, 12px right, 8px bottom** (`storiesHeaderMargin`)
- Avatar: **28px** diameter (`storiesHeaderPhoto.photoSize`)
- Name position: **(50px, 0px)** from header origin (`storiesHeaderNamePosition`)
- Date position: **(50px, 17px)** (`storiesHeaderDatePosition`)
- Name font: `storiesHeaderName` (semibold, FlatLabel)
- Date font: `storiesHeaderDate` (normal, FlatLabel)
- Counter format: `" \u2022 %1/%2"` (bullet separator, e.g. "3/7")

#### Opacity Values

- Name: **1.0**
- Date: **0.8**
- Controls: **0.65** default, **1.0** hover, **0.45** disabled

#### Privacy Badges

Small icon badge next to the avatar, shifted by `storiesBadgeShift: point(5, 4)` with `storiesBadgeOutline: 2px` and `storiesBadgePadding: margins(1,1,1,1)`:

| Privacy | Icon |
|---|---|
| Close Friends | `storiesBadgeCloseFriends` (green star) |
| Contacts | `storiesBadgeContacts` |
| Selected Contacts | `storiesBadgeSelectedContacts` |

#### Timestamp Display

- < 61 seconds: "Just now" (updates every second)
- < 60 minutes: "X minutes ago"
- < 12 hours: "X hours ago"
- Same day: "Today at HH:MM"
- Yesterday: "Yesterday at HH:MM"
- Older: full date/time

#### Video Controls

- Play/pause button: **40 x 40px** (`storiesPlayButton`), position **(54px, 0px)** from header right (`storiesPlayButtonPosition`)
- Volume button: **40 x 40px** (`storiesVolumeButton`), position **(10px, 0px)** (`storiesVolumeButtonPosition`)
- Volume slider: **75px** width (`storiesVolumeSize`)
- Icons: `storiesPlayIcon` / `storiesPauseIcon`

### 32.4 Story Reactions

#### Reaction Panel

- Panel width: **210px** (`storiesReactionsWidth`), expandable to **420px** (2x)
- Bottom skip: **29px** (`storiesReactionsBottomSkip`)
- Added top spacing: **200px** (`storiesReactionsAddedTop`)
- Like/reactions position: **(85px, 30px)** (`storiesLikeReactionsPosition`)
- Like button: **42 x 42px** (based on `storiesAttach`)

#### Reaction Bubble Geometry

Suggested reaction bubbles use a speech-bubble shape with two tail circles:

- Bubble size: **1.0** (relative to container)
- Big tail: **0.264** diameter, offset **0.464**, rotation **-42.29deg**
- Small tail: **0.110** diameter, offset **0.697**, rotation **-40.87deg**

#### Reaction Animation

- Scale-out duration: **1000ms** (stories), **400ms** (messages)
- Scale-out target: **0.7** (70% of original)
- Counter fade duration: **150ms**
- Base reaction size: **0.7** (without count), **0.55** (with count)

#### Suggested Reactions (Interactive Areas)

Reactions overlaid on story content at normalized coordinates. Supports flipped and dark styling. Scale relative to content geometry with rotation transforms.

#### Weather Areas

- Emoji/sticker size: `chatIntroStickerSize`
- Padding: 1/5 of widget height
- Temperature: millicelsius converted, displayed with degree symbol (0xb0) + C/F
- Text color: white or black based on background luminance (threshold **0.705**, ITU-R BT.601 coefficients)

### 32.5 Story Reply Compose

Input bar at the bottom of the story viewer for sending replies.

#### Layout

- Background: `storiesComposeBg` = **#2c333d** (`groupCallMembersBg`)
- Background hover: **#323a45** (`groupCallMembersBgOver`)
- Background ripple: **#39424f** (`groupCallMembersBgRipple`)
- Corner radius: **21px** (`storiesComposeControls.radius`)
- Padding: **1px left, 8px top, 1px right, 6px bottom** (`storiesComposeControls.padding`)
- Field left offset: **10px**
- Gray text color: `storiesComposeGrayText`
- White text color: `storiesComposeWhiteText` = **#ffffff** (`groupCallMembersFg`)
- Blue accent: `storiesComposeBlue` = **#4db8ff** (`groupCallActiveFg`)

#### Attachment Button

- Size: **42 x 42px** (`storiesAttach`)
- Supports: photos, files, voice messages (`recordMediaMessage: true`)
- Disabled for video stream contexts

#### Placeholder Text

Varies by context:
- Standard reply: localized "Reply to story..." (`lng_story_reply_ph`)
- Comments: "Write a comment..." (`lng_story_comment_ph`)
- Stealth mode active: countdown timer (updates every **250ms**)
- Paid messages: price indicator (`lng_message_stars_ph`)

#### Controls Positioning

Anchored to `layout.controlsBottomPosition`. Autocomplete bounds relative to content area. Voice lock positioned from bottom edge. Minimum controls width: **280px** (`storiesControlsMinWidth`), extend by **4px** (`storiesControlsExtend`).

### 32.6 Story Caption / Text

#### Collapsed Caption

- Style: `storiesCaptionFull` (FlatLabel, min width **36px**)
- Padding: **11px left, 6px top, 11px right, 6px bottom** (`storiesCaptionPadding` / `storiesFieldCaptionPadding`)
- Shows limited lines in collapsed state (`kCollapsedCaptionLines`)
- Tap to expand with `fadeWrapDuration` animation, `sineInOut` easing

#### Expanded Caption (Full View)

- Uses `Ui::ElasticScroll` for overscroll
- Pull-to-close threshold: **50px** (`storiesCaptionPullThreshold`)
- Close triggers: close button, Escape key, or pull-down gesture
- Height animates between `collapsedHeight` and `fullHeight` via `anim::interpolate()`
- Text supports click handlers for links and interactive elements
- Quote entities stripped for display; repost handlers looked up separately

#### Content Fade

When caption expanded or reply field active, story content fades to **0.6** opacity (`kFullContentFade`).

### 32.7 Story Repost View

Displays repost attribution when a story is shared from another user/channel.

- Background: `QColor(0, 0, 0, 64)` (semi-transparent black)
- Padding: `historyReplyPadding` (top, bottom, left, right)
- Name: semibold font height
- Subtitle: normal font height
- Total height: top padding + semibold height + normal height + bottom padding
- Simple repost style: padding **8px left, 2px top, 8px right, 2px bottom**, radius **10px**, no outline
- Quote repost style: uses `messageQuoteStyle`
- Width constraint: `maxSignatureSize`
- Ripple: `defaultRippleAnimation`
- Supports background emoji from source peer

### 32.8 Story Privacy Controls

#### Privacy Levels

| Level | Enum Value | Description |
|---|---|---|
| Everyone | `StoryPrivacy::Public` | Visible to all users |
| Contacts | `StoryPrivacy::Contacts` | Only mutual contacts |
| Close Friends | `StoryPrivacy::CloseFriends` | User-curated close friends list |
| Selected Contacts | `StoryPrivacy::SelectedContacts` | Manually chosen users |

Privacy stored as boolean flags on the `Story` object: `_privacyPublic`, `_privacyCloseFriends`, `_privacyContacts`, `_privacySelectedContacts`.

Privacy badge displayed on the story header (see 32.3). Own stories always show the privacy badge; others' stories do not display it.

### 32.9 Story Views List (Who Viewed)

Shown at the bottom of own stories; tap to expand into a menu.

#### Layout

- Stacked avatars: `storiesWhoViewed` style with userpic size **24px**, shift **9px**, stroke **4px**
- Views position: **(4px, 29px)** (`storiesViewsPosition`), text at **(26px, 14px)**
- Likes position: **(0px, 29px)** (`storiesLikesPosition`), text at **(41px, 14px)**, text right skip **8px**, empty right skip **2px**
- Recent views skip: **8px** (`storiesRecentViewsSkip`)
- Channel reactions text top: **16px** (`storiesChannelReactionsTextTop`)

#### View Count Display

- Regular stories: view count + optional heart emoji + reaction count
- Channels: "View reactions"
- No views: "No views" message

#### Menu Behavior

- Loads **50** entries per batch (`kAddPerPage`)
- Triggers additional loads at **2** pages threshold (`kLoadViewsPages`)
- Menu repositions upward when content extends beyond viewport
- Placeholder rows shown while loading
- Stacked avatar widget: `GroupCallUserpics` with dynamic width

### 32.10 Stealth Mode

Allows viewing stories without appearing in the "who viewed" list. Premium feature.

#### Activation Flow

1. Check if already active (`enabledTill > now`) -> show toast, execute callback
2. If not premium -> show premium preview box with lock icon
3. If in cooldown (`cooldownTill > now`) -> show cooldown toast
4. Otherwise -> call `MTPstories_ActivateStealthMode(flags: f_past | f_future)`

#### Stealth Mode Data

```
StealthMode {
    enabledTill: TimeId  // Unix timestamp when stealth expires
    cooldownTill: TimeId // Unix timestamp when cooldown ends
}
```

#### Dialog UI

- Logo icon: `stories/stealth_logo` on `windowBgActive` background, additional margin **12px** (`storiesStealthLogoAdd`)
- Logo margin: **0px top (from box edge), 28px top (inner), 0px left/right, 7px bottom** (`storiesStealthLogoMargin`)
- Title: "View Stories Anonymously"
- Feature icons: `stories/stealth_5m` (past), `stories/stealth_25m` (next) in `windowActiveTextFg`
- Feature title font: semibold, `windowBoldFg`, min width **10px**, max height **20px**
- Feature description font: normal, `windowSubTextFg`, min width **20px**
- Close button: `box_button_close`, ripple area **40px** at offset **(4, 4)**

#### Button States

| State | Label | Opacity |
|---|---|---|
| Non-premium | "UNLOCK" + lock icon | 1.0 |
| Cooldown active | "COOLDOWN IN H:MM:SS" | 0.5 (`kCooldownButtonLabelOpacity`) |
| Ready (with callback) | "ENABLE AND OPEN" | 1.0 |
| Ready (no callback) | "ENABLE" | 1.0 |

- Button height: **42px**, padding **10px** all sides, text top offset **12px**
- Button font: semibold, color `activeButtonFg`
- Countdown updates every **250ms** (`base::timer_each(250)`)
- Countdown format: `H:MM:SS` or `M:SS` or `0:SS`

#### Toast Notifications

- Duration: **4000ms** (`kAlreadyToastDuration`)
- Three types: "Already active" (with remaining time), "Enabled" (confirmation), "Cooldown active"

### 32.11 Story Expiry & Archive

#### Expiry Logic

- Stories expire when `_expires <= base::unixtime::now()`
- Timer scheduled with max delay of **86400 seconds** (24 hours)
- `registerExpiring(TimeId expires, FullStoryId id)` tracks pending expirations
- `processExpired()` removes expired stories or moves to archive

#### Archive

- Available for own stories and channels with edit permissions
- First page: **30** items (`kArchiveFirstPerPage`)
- Subsequent pages: **100** items (`kArchivePerPage`)
- Album IDs: `kStoriesAlbumIdSaved = 0`, `kStoriesAlbumIdArchive = -1`
- Archives persist indefinitely after 24h expiry

### 32.12 Profile Stories (Highlights / Saved)

Displayed on the user's profile info page via `info/stories/` components.

#### Tab Navigation

Uses `Ui::SubTabs` for album selection:
- "All" tab (default saved stories, album ID 0)
- Individual album tabs (user-created)
- "Add" tab pinned to right for creating new albums

#### Grid Layout

- Responsive grid: columns calculated dynamically from viewport width
- Formula: `itemsInRow = (width - infoMediaSkip) / (infoMediaMinGridSize + infoMediaSkip)`
- Item aspect ratio preserved ("PhotoVideo" layout type)
- Spacing: `infoMediaSkip` applied uniformly
- Preload: **4** screens each direction, **9** total (`kPreloadedScreensCountFull`)

#### Album Management

- Albums support drag-reorder with API sync (`MTPstories_ReorderAlbums`)
- Archive album has special ID (`kStoriesAlbumIdArchive = -1`)
- Recent stories display: right-aligned thumbnails, height = `small.photo + 2 * small.photoTop`, vertically centered

### 32.13 Story Interactive Areas

Stories support overlay interactive elements positioned at normalized coordinates (0.0-1.0 relative to content dimensions).

#### Area Types

| Type | Data | Behavior |
|---|---|---|
| StoryLocation | lat/lng + optional venue (title, address, provider, venueId, venueType) | Opens map or venue page |
| SuggestedReaction | Reaction ID + flipped/dark flags | Tap to react |
| ChannelPost | FullMsgId reference | Opens linked channel message |
| UrlArea | URL string or `tg://nft?slug=` NFT link | Opens browser or in-app |
| WeatherArea | Emoji + color + temperature (millicelsius) | Display only |

Each area has: normalized position (x, y), dimensions (width, height), rotation angle, and corner radius. Rotation transforms applied before hit-testing. Radius-based areas used for weather widgets (`radiusOriginal` stored separately).

### 32.14 Story Sharing

- Share box created via `PrepareShareBox(show, storyId, viewerStyle)`
- Link-only sharing requires `ChatRestriction::SendOther`
- Full story sharing requires both `SendPhotos` AND `SendVideos` permissions
- Sharing with comment generates 2 messages; without comment generates 1
- Link prepended with newline when appending to existing comment text
- Timestamp formatting for video stories: `H:MM:SS` or `MM:SS` (`FormatShareAtTime`)
- Supports: silent posting, scheduled messages, quick reply shortcuts, message effects, suggested posts, media inversion, paid stars

#### Send Flags

`f_reply_to`, `f_silent`, `f_schedule_date`, `f_schedule_repeat_period`, `f_quick_reply_shortcut`, `f_effect`, `f_suggested_post`, `f_invert_media`, `f_allow_paid_stars`

### 32.15 Story Creation / Editor

Story creation reuses the photo editor infrastructure from `editor/`:

#### Available Tools

- **Transform**: rotation, flipping, cropping (aspect ratios: original, square, 3:2, 16:9, 9:16, free)
- **Paint**: freehand drawing with color picker, undo/redo
- **Stickers**: sticker panel integration (when controller available)
- **Text**: via crop ratio button menu

#### Editor Controls Layout

- Button bar height: `photoEditorButtonBarHeight`
- Button bar width: `photoEditorButtonBarWidth` (max constrained to parent)
- Padding: `photoEditorButtonBarPadding`
- Bottom skip: `photoEditorControlsBottomSkip`
- Center skip: `photoEditorControlsCenterSkip`
- Crop point size: `photoEditorCropPointSize`

#### Control Bars

Two button bars with animated mode switching:
- **Transform bar**: flip, rotate, paint mode toggle, crop ratio selector, cancel/done
- **Paint bar (bottom)**: undo, redo, paint mode toggle (active state), stickers, done
- **Paint bar (top)**: undo/redo controls positioned above bottom bar

#### Keyboard Shortcuts

- Enter/Return: confirm (done)
- Escape: cancel
- Ctrl+Z: undo
- Ctrl+Y: redo

#### Privacy Selection

At posting time, user selects privacy via `StoryPrivacy` enum (see 32.8). The privacy choice persists for subsequent stories until changed.

### 32.16 Pixel Dimensions & Constants Summary

| Constant | Value | Context |
|---|---|---|
| **Stories Bar (Collapsed)** | | |
| Bar height | 35px | `dialogsStories.height` |
| Avatar size | 21px | `small.photo` |
| Avatar position | (4px, 4px) | `small.photoLeft/Top` |
| Item shift | 16px | `small.shift` |
| Unread ring thickness | 1.5px | `small.lineTwice` / 2 |
| **Stories Bar (Expanded)** | | |
| Bar height | 77px | `dialogsStoriesFull.height` |
| Avatar size | 42px | `full.photo` |
| Avatar position | (10px, 9px) | `full.photoLeft/Top` |
| Unread ring thickness | 2px | `full.lineTwice` / 2 |
| Read ring thickness | 1px | `full.lineReadTwice` / 2 |
| Name top offset | 56px | `full.nameTop` |
| Name font | 11px | `full.nameStyle` |
| Read opacity | 0.6 | `dialogsStoriesList.readOpacity` |
| **Story Viewer** | | |
| Max content size | 540 x 960px | `storiesMaxSize` |
| Content corner radius | 8px | `storiesRadius` |
| Control button size | 64px | `storiesControlSize` |
| Min controls width | 280px | `storiesControlsMinWidth` |
| Side skip | 145px | `storiesSideSkip` |
| Min sibling width | 200px | `storiesSiblingWidthMin` |
| **Progress Slider** | | |
| Bar height | 2px | `storiesSliderWidth` |
| Segment gap | 4px | `storiesSliderSkip` |
| Margin | (8, 7, 8, 6)px | `storiesSliderMargin` |
| Max segments | 180 | `kMaxSegmentsCount` |
| Active opacity | 1.0 | `kOpacityActive` |
| Inactive opacity | 0.4 | `kOpacityInactive` |
| **Header** | | |
| Margin | (12, 4, 12, 8)px | `storiesHeaderMargin` |
| Avatar size | 28px | `storiesHeaderPhoto.photoSize` |
| Name position | (50, 0)px | `storiesHeaderNamePosition` |
| Date position | (50, 17)px | `storiesHeaderDatePosition` |
| Badge outline | 2px | `storiesBadgeOutline` |
| Badge shift | (5, 4)px | `storiesBadgeShift` |
| Play button | 40 x 40px | `storiesPlayButton` |
| Play button pos | (54, 0)px | `storiesPlayButtonPosition` |
| Volume button | 40 x 40px | `storiesVolumeButton` |
| Volume button pos | (10, 0)px | `storiesVolumeButtonPosition` |
| Volume slider width | 75px | `storiesVolumeSize` |
| Volume bottom margin | 20px | `storiesVolumeBottom` |
| **Reactions** | | |
| Panel width | 210px | `storiesReactionsWidth` |
| Bottom skip | 29px | `storiesReactionsBottomSkip` |
| Like position | (85, 30)px | `storiesLikeReactionsPosition` |
| Attach/like button | 42 x 42px | `storiesAttach` |
| **Reply Compose** | | |
| Corner radius | 21px | `storiesComposeControls.radius` |
| Padding | (1, 8, 1, 6)px | `storiesComposeControls.padding` |
| Field left | 10px | `storiesComposeControls.fieldLeft` |
| Comments skip | 8px | `storiesComposeControls.commentsSkip` |
| Unread dot size | 6px | `storiesComposeControls.unreadSize` |
| Unread dot margin | 2px | `storiesComposeControls.unreadMargin` |
| Background color | #2c333d | `storiesComposeBg` |
| Background hover | #323a45 | `storiesComposeBgOver` |
| Background ripple | #39424f | `storiesComposeBgRipple` |
| Text color | #ffffff | `storiesComposeWhiteText` |
| Accent color | #4db8ff | `storiesComposeBlue` |
| **Views** | | |
| Userpic size | 24px | `storiesWhoViewed.userpics.size` |
| Userpic shift | 9px | stacking overlap |
| Userpic stroke | 4px | outline thickness |
| Views position | (4, 29)px | `storiesViewsPosition` |
| Views text pos | (26, 14)px | relative to views position |
| Likes position | (0, 29)px | `storiesLikesPosition` |
| Likes text pos | (41, 14)px | relative to likes position |
| **Caption** | | |
| Padding | (11, 6, 11, 6)px | `storiesCaptionPadding` |
| Pull-to-close threshold | 50px | `storiesCaptionPullThreshold` |
| Min width | 36px | `storiesCaptionFull.minWidth` |
| **Stealth Mode** | | |
| Button height | 42px | stealth box button |
| Button padding | 10px | all sides |
| Close ripple area | 40px | at offset (4, 4) |
| Logo extra margin | 12px | `storiesStealthLogoAdd` |
| Logo margin | (0, 28, 0, 7)px | `storiesStealthLogoMargin` |
| Toast duration | 4000ms | `kAlreadyToastDuration` |
| Cooldown label opacity | 0.5 | `kCooldownButtonLabelOpacity` |
| **Timing** | | |
| Photo duration | 5000ms | `kPhotoDuration` |
| Photo progress interval | 100ms | `kPhotoProgressInterval` |
| Mark-as-read delay | 200ms | `kMarkAsReadAfterSeconds` |
| Server read delay | 3000ms | `kMarkAsReadDelay` |
| View increment delay | 5000ms | `kIncrementViewsDelay` |
| Content fade opacity | 0.6 | `kFullContentFade` |
| Expansion trigger ratio | 0.72 | `kExpandAfterRatio` |
| Collapse trigger ratio | 0.68 | `kCollapseAfterRatio` |
| Catch-up animation | 200ms | `kExpandCatchUpDuration` |
| Sibling fade-in | 200ms | `kGoodFadeDuration` |
| Reaction scale-out | 1000ms | stories mode |
| Counter fade | 150ms | reaction counter |
| **Gradient Ring Colors** | | |
| Unread green (top-right) | #0dcc39 | `groupCallLive1` |
| Unread blue (bottom-left) | #0992ef | `groupCallMuted1` |

---

## 33. Contacts Screen

The Contacts screen is a modal `PeerListBox` that displays all synced contacts in a flat scrollable list with search, sort toggle, and an "Add Contact" button. It is opened from the hamburger menu ("Contacts" item) or via keyboard shortcut. The box reuses the shared `PeerListBox` / `PeerListContent` infrastructure (same widget that powers "Add Members", "Block List", etc.) with the `ContactsBoxController` driving data and sort logic.

Source files: `boxes/peer_list_box.cpp/h`, `boxes/peer_list_widgets.cpp/h`, `boxes/peer_list_controllers.cpp/h`, `boxes/add_contact_box.cpp/h`, `boxes/peers/edit_contact_box.cpp/h`, `boxes/share_box.cpp/h`, `window/window_peer_menu.cpp`, `info/profile/info_profile_actions.cpp/h`, `data/data_user.cpp/h`, `data/data_lastseen_status.h`, `data/data_peer_values.cpp`.

### 33.1 Box Shell & Title Bar

The Contacts box uses the standard `BoxContent` modal chrome:

- **Width:** `boxWideWidth` (~364px default, inherited from `ui/basic.style`).
- **Title:** `tr::lng_contacts_header` ("Contacts"), rendered in `boxTitleFont` (semibold, 17px) at `boxTitleHeight` (48px) row.
- **Close button:** Bottom-right, label `tr::lng_close` ("Close"), standard `boxButton` style.
- **Add Contact button:** Bottom-left, label `tr::lng_profile_add_contact` ("Add Contact"), standard `boxButton` style. Opens the `AddContactBox` dialog (see 33.5).
- **Sort toggle button:** Top-right corner of the title bar, `st::contactsSortButton` -- 48x54px hit area, 42px ripple circle at offset (1px, 6px), icon at offset (10px, -1px). Two states:
  - **Online sort** (default on open): icon `contactsSortOnlineIcon` (clock/online indicator). Contacts sorted by `onlineTill` descending -- online users first, then recently seen, then older.
  - **Alphabetical sort:** icon switches to default (A-Z). Contacts sorted by `chatListNameSortKey()` (Unicode-aware alphabetical).
  Clicking toggles between modes. Icon swap is instant (no crossfade).

### 33.2 Stories Bar (Optional)

When the user has contacts with active stories, a horizontal stories strip appears above the contact list (below the search field). Managed by `PeerListStories`:

- Each contact with an active story gets a circular avatar with colored segment outlines representing story count.
- **Unread stories:** Gradient brush segments (`dialogsStoriesFull.lineTwice` width).
- **Video stream stories:** Separate visual indicator.
- Clicking a story avatar opens the story viewer instead of the chat.
- The stories bar is enabled via `setStoriesShown(true)` in `PrepareContactsBox()`.

When stories are shown, the item style switches to `st::contactsWithStories`:
- Row height: **52px** (vs 56px default).
- Photo position: **(18px, 5px)**.
- Name position: **(70px, 7px)**.
- Status position: **(70px, 27px)**.

### 33.3 Search Field

A `Ui::MultiSelect` widget sits below the title bar. Behavior:

- **Default state:** Single-line input field with placeholder text. Always visible when search mode is `Enabled`.
- **Typing:** Filters the contact list in real-time. Two search paths:
  1. **Local filtering:** Matches against `nameWords()` and `nameFirstLetters()` indices built per row. Instant, no debounce.
  2. **Global search:** If local yields few results, a `PeerListGlobalSearchController` fires a server request after `AutoSearchTimeout` debounce. Results cached in `_peopleCache` to avoid duplicate API calls.
- **No results state:** Shows `tr::lng_blocked_list_not_found` ("No contacts found") label, centered vertically in the list area with `st::membersAboutLimitPadding` spacing.
- **Loading state:** Shows a loading label during complex server-side search.
- **Escape key:** Clears the query via `clearQuery()`, restoring the full contact list.

### 33.4 Contact List Layout

The contact list is a flat vertical scroll area. **No letter-based section headers** exist -- the desktop client uses a continuous list without alphabet dividers.

#### Row Dimensions (default style `peerListBoxItem`)

| Property | Value |
|---|---|
| Row height | **56px** |
| Avatar diameter | **42px** (`contactsPhotoSize`) |
| Avatar position | **(16px, 7px)** from row top-left |
| Name text position | **(74px, 9px)** |
| Status text position | **(74px, 30px)** |
| Row horizontal padding | **16px** left, **16px** right (`contactsPadding`) |

#### Avatar

- 42px circular userpic. For contacts without a profile photo, a colored circle with initials is rendered (color derived from peer ID hash, same palette as chat list).
- **Saved Messages** row (self-chat): Bookmark icon userpic via `EmptyUserpic::PaintSavedMessages()`.
- **Stories segments:** If the contact has active stories, the avatar gains colored arc segments around it (see 33.2). Arcs use `st::dialogsStoriesFull.lineTwice` stroke width.

#### Name Text

- **Font:** `st.nameStyle` (semibold, ~14px `semiboldFont`).
- **Color:** `st.nameFg` default (#222222 in day theme), animates to `st.nameFgChecked` when the row is selected (checkbox mode).
- **Rendering:** `name.drawLeftElided()` -- single line, ellipsis if truncated.
- **Badges:** Verified, scam, premium, and emoji status badges rendered inline after the name via `Ui::PeerBadge`.
- **Max width:** Available width minus right action size minus right action margins.

#### Status Text

- **Font:** `st::contactsStatusFont` (normal, ~13px `fsize`).
- **Colors (three states):**
  - `st.statusFgActive` (`contactsStatusFgOnline`): Green, shown when user is currently online.
  - `st.statusFg` (`contactsStatusFg`): Gray (#999999), default for offline/last seen.
  - `st.statusFgOver` (`contactsStatusFgOver`): Slightly different gray, on hover.
- **Status types** (enum `PeerListRow::StatusType`):
  - `Online` -- "online" (green).
  - `LastSeen` -- computed from `LastseenStatus`:
    - `isOnline(now)` => "online".
    - Recently => "last seen recently".
    - WithinWeek => "last seen within a week".
    - WithinMonth => "last seen within a month".
    - LongAgo => "last seen a long time ago".
    - Exact timestamp => "last seen today at 3:45 PM", "last seen yesterday at 10:00 AM", or "last seen Jan 15 at 2:30 PM" (formatted via `QLocale`, respects `showMessageSeconds()` AyuSettings for long/short time format).
  - `Custom` -- arbitrary string set by controller.
  - `CustomActive` -- custom string rendered in active (green) color.
- **Refresh:** Status text has a `_statusValidTill` timestamp. `OnlinePhraseChangeInSeconds()` computes when the display string will change (e.g., "X minutes ago" needs refresh every 60s). The controller schedules `refreshStatusTime()` callbacks.

#### Interaction States

- **Hover:** Ripple animation via `st.button.ripple`, background tint `st.button.textBgOver`.
- **Press:** Ripple origin at click point, standard Material-style ink spread.
- **Click:** Opens the peer's chat history via `window->showPeerHistory(peer)`. If the contact has an active story and the click hits the story area, the story viewer opens instead.
- **Middle-click:** `rowMiddleClicked()` -- opens chat in a new window (if supported by controller).
- **Right-click:** Context menu with contact actions (see 33.8).

#### Right Action Column

Rows can have an optional right-side action element:
- **Size:** `rightActionSize()` (controller-defined, typically a small icon button).
- **Margins:** `rightActionMargins()` offset from row edge.
- **Ripple:** Independent ripple animation on the action button.
- **Use cases:** In the contacts screen the right action is not used by default, but subclasses (blocked users list, add members) add delete/checkbox actions here.

### 33.5 Add Contact Dialog

Opened by the "Add Contact" bottom-left button, or via hamburger menu > "Contacts" > "Add Contact". Uses `AddContactBox` (a `BoxContent` modal).

#### Layout

- **Width:** `boxWideWidth`.
- **Top padding:** `contactPadding.top()` (2px).
- **Fields (top to bottom):**
  1. **First name** -- `InputField`, label "First name". Left padding: 49px (`contactPadding.left()`). Max length: `kMaxUserFirstLastName`.
  2. **Last name** -- `InputField`, label "Last name". Spacing from first name: `contactSkip` (9px).
  3. **Phone number** -- `PhoneInput` field with country code selector. Spacing from last name: `contactPhoneSkip` (30px).
- **Bottom padding:** `contactPadding.bottom()` (14px).
- **Field order:** Respects `langFirstNameGoesSecond()` -- in some locales (e.g., Japanese, Korean), last name appears first. The `_invertOrder` flag swaps rendering and tab order.
- **Icon:** Contact icon rendered at `contactIconPosition` (-5px, 23px) relative to each field row.

#### Validation

- **Phone:** `IsValidPhone()` -- strips non-digits, requires >= 8 digits. Special short numbers allowed: "333", patterns matching "42xx".
- **Name:** At least one of first/last name must be non-empty after `TextUtilities::PrepareForSending()` sanitization.
- **Submit flow:** Tab key cycles First -> Last -> Phone -> Submit. Enter on any field triggers `submit()` which advances focus or calls `save()`.

#### API Call

`MTPcontacts_ImportContacts` with a single `MTPInputContact`:
- `client_id`: Random `uint64` (`_contactId`).
- `phone`: Cleaned phone string.
- `first_name`, `last_name`: Sanitized text.

#### Retry State

If the import returns no new users (phone not on Telegram), the dialog enters retry mode:
- Paint area shows a message: "This phone number is not on Telegram yet" (paraphrased).
- Buttons change: "Add Contact" becomes "Try Other Contact".
- `retry()` resets form fields and request state.

### 33.6 Edit Contact Dialog

Opened from the contact's profile info panel (three-dot menu > "Edit Contact") or from the peer context menu. Uses `EditContactBox` function filling a `Ui::GenericBox`.

#### Layout

- **Cover widget (top):** Displays the contact's current avatar, name, and phone status. Observes reactive data streams and updates dynamically. Styled with `st::infoEditContactCover`.
- **Name fields:**
  - First name and last name `InputField` widgets, max length `kMaxUserFirstLastName`.
  - Language-aware ordering (`_invertOrder`).
  - Tab order respects locale.
  - Field margins: `addContactFieldMargin` (19px, 0px, 19px, 10px).
- **Notes field:** Multi-line input with emoji panel integration (`ChatHelpers::TabbedPanel`). Character limit based on `Data::PremiumLimits` (premium users get higher limit). Styled with `st::notesFieldWithEmoji`. Real-time character count validation with toast warnings on overflow.
- **Photo management buttons** (below cover):
  1. "Suggest photo" -- for non-contacts, with Lottie animation (frames 0-21).
  2. "Set personal photo" -- camera icon, opens photo editor with elliptical crop.
  3. "Reset to default" -- confirmation dialog before reverting.
  Styled with `st::settingsButtonLight`.
- **Delete contact option:** Red text button at the bottom. Triggers the delete confirmation (see 33.7).

#### API Call

`MTPcontacts_AddContact` (same endpoint for add and edit):
- Includes `first_name`, `last_name`.
- Note text with entities via `Api::EntitiesToMTP()`.
- Optional `sharePhone` exception flag.

### 33.7 Delete Contact Confirmation

Triggered from Edit Contact dialog or peer context menu ("Delete Contact" item, styled with `st::menuIconDeleteAttention`, marked `isAttention = true` for red/warning styling).

- **Dialog type:** Standard confirmation box.
- **Text:** Asks the user to confirm removing the contact (localized).
- **Buttons:** "Delete" (destructive/red) + "Cancel".
- **On confirm:** Sends `MTPcontacts_DeleteContacts` API call. On success:
  - Contact removed from local `contactsList()`.
  - `UserDataFlag::Contact` and `UserDataFlag::MutualContact` flags cleared.
  - Row removed from the contacts `PeerListContent` if the contacts box is open.
  - Chat history is NOT deleted (user can still message the former contact).
- **Note deletion:** `DeleteContactNote()` separately removes stored contact notes via API.

### 33.8 Contact Actions (Context Menu & Profile)

Actions available from the contact row right-click menu and from the profile info panel:

| Action | Label (lang key) | Icon | Condition |
|---|---|---|---|
| Add Contact | `lng_info_add_as_contact` | `menuIconInvite` | User exists, not already a contact, not self |
| Share Contact | `lng_info_share_contact` | `menuIconInvite` | User is a contact |
| Edit Contact | `lng_info_edit_contact` | `menuIconEdit` | User is a contact, not self |
| Delete Contact | `lng_info_delete_contact` | `menuIconDeleteAttention` | User is a contact |
| Block User | Dynamic (block/unblock/restart bot) | `menuIconBlock` / `menuIconUnblock` / `menuIconRestartBot` | Always for users |

**Menu order in profile panel** (`fillProfileActions`): TTL setting > Support > Add Contact > Share Contact > Edit Contact > Bot to Group > Members > Gifts > Statistics. Delete and Block appear in separate context menu sections.

#### Share Contact

`PeerMenuShareContactBox()` opens a `ShareBox` modal:
- **Layout:** Multi-select filter at top, scrollable grid of chats (4 columns default), comment field at bottom.
- **Grid row height:** `shareRowHeight` (108px). Avatar at `sharePhotoTop` (6px), name below at `shareNameTop` (6px below avatar).
- **Selection animation:** Name color transitions between `nameFg` and `nameFgChecked` over `shareActivateDuration` (150ms).
- **Search:** Local filter via `TextUtilities::PrepareSearchWords()`, plus remote username search with `AutoSearchTimeout` debounce.
- **Send button:** Hidden when no selection. Shows `tr::lng_share_confirm` when peers selected. Supports right-click menu for scheduling.
- **Comment field:** `Ui::InputField` (MultiLine), styled `st::shareComment` with `shareCommentPadding`. Hidden initially, appears when contacts are selected.

#### Call / Video Call

Not directly in the contacts list -- these are in the profile info panel and chat header:
- **Voice call:** `Calls::Instance::startOutgoingCall(user, false)`.
- **Video call:** `Calls::Instance::startOutgoingCall(user, true)`.
- Buttons styled with `st::infoMainButton`.

### 33.9 Mutual Contact Indicator

Telegram tracks mutual contact status via `UserDataFlag::MutualContact` (bit 1 on the user flags). However, **no dedicated visual indicator** appears in the contacts list UI. The flag is used internally:

- Determines whether phone number is visible to the other user.
- Affects privacy setting resolution (e.g., "My Contacts" visibility rules).
- The Edit Contact dialog's `sharePhone` checkbox lets users control phone sharing exceptions.

The contact's phone number is displayed in their profile via `PhoneValue()` / `PhoneOrHiddenValue()`, formatted with `Ui::FormatPhone()`. If the phone is hidden (no username, no bio, no phone), the text shows "hidden" with a special link format for collectible numbers.

### 33.10 Import Contacts Flow

Contact import is handled server-side via `MTPcontacts_ImportContacts`. The flow:

1. **System contacts sync** (mobile clients primarily): On desktop, contacts are added manually via "Add Contact" dialog or arrive via server-side sync from mobile clients that have granted address book access.
2. **API call:** `MTPcontacts_ImportContacts(vector<MTPInputContact>)` -- each input contains `client_id`, `phone`, `first_name`, `last_name`.
3. **Response handling:** Returns lists of imported users, popular invites, and retry contacts. The `AddContactBox` handles the single-contact case; bulk import is a mobile feature.
4. **Desktop behavior:** No "Import from Address Book" button exists on desktop. Contacts arrive from: (a) manually adding via Add Contact dialog, (b) accepting contact shares, (c) server sync from mobile sessions.

### 33.11 Sort Options

Two modes controlled by the sort toggle button (see 33.1):

#### Online Sort (Default)

```
key(row) = min(user.lastseen().onlineTill(), now + 1) + 1
sort: descending by key (highest = most recently online first)
```

- Currently online users bubble to the top.
- Recently seen users next, descending by last activity time.
- Users with hidden status (`LongAgo`, `Recently` without timestamp) sort to the bottom.
- **Throttle:** `kSortByOnlineThrottle = 3000ms`. When online status updates arrive rapidly, re-sort is deferred by 3 seconds via `_sortByOnlineTimer` to prevent visual jitter.

#### Alphabetical Sort

```
delegate()->peerListSortRows([](a, b) {
    return a.chatListNameSortKey().compare(b.chatListNameSortKey()) < 0;
});
```

- Unicode-aware alphabetical ordering via `chatListNameSortKey()`.
- Stable sort preserving insertion order for identical keys.
- No letter section headers -- just a flat sorted list.

### 33.12 Empty State

When no contacts exist or search yields no results:

- **No contacts (list empty):** The description label area shows controller-provided text or remains blank. `checkForEmptyRows()` evaluates after data load.
- **Search no results:** `_searchNoResults` label displays `tr::lng_blocked_list_not_found` ("No contacts found"). Centered in the list area.
- **Search loading:** `_searchLoading` label shown during server-side search.
- **Visibility logic:** `labelHeight()` returns 0 if `_hideEmpty && !shownRowsCount()`, collapsing the label space when intentionally hidden.

Labels use `st::membersAboutLimitPadding` for vertical spacing and `st::contactsPadding.left()` for horizontal alignment.

### 33.13 People Nearby

**Removed from Telegram.** The "People Nearby" feature was deprecated and removed from Telegram clients in 2024. The contacts screen does not include a "People Nearby" section or button. No related source files exist in the current AyuGram codebase.

### 33.14 Pixel Dimensions & Constants Summary

| Constant | Value | Description |
|---|---|---|
| `peerListBoxItem.height` | **56px** | Contact row height (default) |
| `contactsPhotoSize` | **42px** | Avatar diameter |
| `peerListBoxItem.photoPosition` | **(16px, 7px)** | Avatar offset from row top-left |
| `peerListBoxItem.namePosition` | **(74px, 9px)** | Name text offset |
| `peerListBoxItem.statusPosition` | **(74px, 30px)** | Status text offset |
| `contactsPadding` | **margins(16, 7, 16, 7)** | Row content padding |
| `contactsNameTop` | **2px** | Name text top within content area |
| `contactsStatusTop` | **23px** | Status text top within content area |
| `contactsCheckPosition` | **(8px, 16px)** | Checkbox offset in selection mode |
| `contactsSortButton` (w x h) | **48px x 54px** | Sort toggle hit area |
| `contactsSortButton.rippleAreaSize` | **42px** | Ripple circle diameter |
| `contactsSortButton.rippleAreaPosition` | **(1px, 6px)** | Ripple origin offset |
| `contactsSortButton.iconPosition` | **(10px, -1px)** | Icon offset within button |
| `contactsWithStories.height` | **52px** | Row height when stories shown |
| `contactsWithStories.photoPosition` | **(18px, 5px)** | Avatar offset with stories |
| `contactsWithStories.namePosition` | **(70px, 7px)** | Name offset with stories |
| `contactsWithStories.statusPosition` | **(70px, 27px)** | Status offset with stories |
| `contactPadding` | **margins(49, 2, 0, 14)** | Add Contact dialog field padding |
| `contactSkip` | **9px** | Vertical gap between name fields |
| `contactPhoneSkip` | **30px** | Gap before phone field |
| `contactIconPosition` | **(-5px, 23px)** | Field icon offset |
| `addContactFieldMargin` | **margins(19, 0, 19, 10)** | Edit Contact field margins |
| `shareRowHeight` | **108px** | Share dialog grid row height |
| `sharePhotoTop` | **6px** | Share grid avatar top offset |
| `shareNameTop` | **6px** | Share grid name below avatar |
| `shareActivateDuration` | **150ms** | Share selection name color fade |
| `shareScrollDuration` | **300ms** | Share grid scroll animation |
| `shareColumnSkip` | **6px** | Share grid column gap |
| `kSortByOnlineThrottle` | **3000ms** | Online sort debounce timer |
| `kSetOnlineAfterActivity` | **30s** | Grace period before status update |
| `dialogsOnlineBadgeSize` | **12px** | Online green dot diameter |
| `dialogsOnlineBadgeStroke` | **3px** | Online dot white border |
| `dialogsOnlineBadgeDuration` | **150ms** | Online dot appear/disappear fade |
| `membersMarginTop` | **10px** | List top margin |
| `membersMarginBottom` | **10px** | List bottom margin |
| Name font | **semibold ~14px** | `contactsNameStyle` / `semiboldFont` |
| Status font | **normal ~13px** | `contactsStatusFont` / `fsize` |
| `kMaxUserFirstLastName` | **64 chars** | Max name field length (add/edit) |

---

## 34. Calls History

The Calls History screen is a modal box (GenericBox) showing the user's complete call log, active group calls, and a button to create new conference calls. It is accessed from the hamburger menu ("Calls" entry, gated by `showCallsInDrawer()` setting) or from the call settings overflow menu.

Source files: `calls/calls_box_controller.cpp`, `calls/calls_box_controller.h`, `calls/calls.style`, `settings/sections/settings_calls.cpp`.

---

### 34.1 Access Points

**Hamburger menu entry.** Shown only when `Core::Settings::showCallsInDrawer()` returns true (default: true). Menu item: label `lng_menu_calls` ("Calls"), icon `menuIconPhone`. Clicking calls `Calls::ShowCallsBox(controller)`.

**Call settings overflow.** From the calls history box itself, the three-dot menu has "Call Settings" which navigates to `Settings::CallsId()` section (audio devices, camera, accept-calls toggle).

---

### 34.2 Box Structure

The box is constructed via `ShowCallsBox()` (line 807 of `calls_box_controller.cpp`). It uses `GenericBox` with a custom layout containing three vertical sections:

1. **Active Group Calls section** (top, collapsible) -- `SlideWrap<VerticalLayout>`, hidden by default, auto-shown when any subscribed channel has an active group call. Uses `GroupCalls::ListController`.

2. **Create Call button** -- `SettingsButton` styled as `inviteViaLinkButton`, with a floating icon (`inviteViaLinkIcon`). Label: `lng_confcall_create_call` ("Create Call"). Below it: a divider with description text showing the conference call participant limit (`lng_confcall_create_call_description`, substituting `confcallSizeLimit()`).

3. **Call history list** (main content) -- `PeerListContent` managed by `BoxController`. Standard peer list with custom row painting for call direction indicators and redial buttons.

**Box title:** `lng_call_box_title` ("Calls").

**Box width:** Determined by `BoxController::contentWidth()` (inherits standard peer list width, typically ~360px).

**Box height:** Dynamic, tracks `boxHeightValue()` from the controller.

**Bottom button:** "Close" (`lng_close`).

**Top-right menu button:** Styled as `infoTopBarMenu` (three-dot icon). Opens a popup menu with:
- "Call Settings" (`lng_settings_section_call_settings`) -- icon `menuIconSettings`. Navigates to Settings > Calls.
- "Clear All" (`lng_call_box_clear_all`) -- icon `menuIconDeleteAttention`, attention style (red text). Only shown when there are call history rows. Opens `ClearCallsBox`.

---

### 34.3 Active Group Calls Section

Managed by `GroupCalls::ListController`. Style override: `peerListSingleRow` (no top/bottom padding).

**Data source:** Iterates pinned chats and first 20 indexed chats, filtering for channels where `Data::ChannelHasActiveCall()` is true. Listens to `Data::PeerUpdate::Flag::GroupCall` for live updates.

**Row type:** `GroupCallRow` (extends `PeerListRow`). Displays channel/group name with a custom status showing the chat type (e.g., "public channel", "private group") in lowercase.

**Right action button:** Only shown for channels (`peer()->isChannel()`). Uses `callGroupCall` style: 40x56px `IconButton` with `top_bar_group_call` icon in `menuIconFg` / `menuIconFgOver`. Ripple animation on the button area (40px diameter, offset at (0, 8)).

**Row click:** Opens the peer's chat history (`showPeerHistory`, `ClearStack` mode).

**Right action click:** Joins/starts the group call on that peer (`startOrJoinGroupCall`).

**Visibility:** The entire section is wrapped in a `SlideWrap` that toggles on `shownValue()` -- an rpl producer that emits `true` when `_fullCount > 0`. Hidden with `anim::type::instant` initially.

**Subsection title:** `lng_call_box_groupcalls_subtitle` ("Active Group Calls"), followed by the peer list content, then a skip + divider + skip separator before the call history.

---

### 34.4 Call History List

Managed by `BoxController` (extends `PeerListController`).

**Data source:** MTProto `messages.Search` with `inputMessagesFilterPhoneCalls` filter, empty query, `inputPeerEmpty` (searches across all peers). Pagination: first page 20 items (`kFirstPageCount`), subsequent pages 100 items (`kPerPageCount`). Uses `_offsetId` for cursor-based pagination. Loads more rows on scroll via `loadMoreRows()`.

**New call detection:** Listens to `Data::MessageUpdate::Flag::NewAdded` events, filtering for messages with `media()->call() != nullptr`. New calls are prepended.

**Item removal:** Listens to `data().itemRemoved()`. When a call message is deleted, the corresponding row item is removed. If the row becomes empty (no items left), the entire row is removed. If the list becomes empty, the "about" text is refreshed.

**Empty state:** Description text `lng_call_box_about` ("Your recent calls will appear here."). While loading: `lng_contacts_loading` ("Loading...").

**Title:** `lng_call_box_title` ("Calls").

---

### 34.5 Call Row Design

Each row is a `BoxController::Row` (extends `PeerListRow`), using the standard `defaultPeerListItem` / `peerListBoxItem` layout:

**Row height:** 56px (from `peerListBoxItem`).

**Avatar:** 42px diameter (`contactsPhotoSize`), positioned at (16, 7). Standard peer userpic (user's profile photo or colored initials).

**Name:** Position (74, 9). Font: `semiboldTextStyle` (13px semibold). Color: `contactsNameFg`.

**Status line:** Position (74, 30). Contains the direction arrow icon + timestamp text.

**Row grouping logic:** Multiple calls to/from the same peer on the same date with the same type (in/out/missed) are grouped into a single row. The `canAddItem()` check verifies: same `ComputeType`, same `history()` (same peer), same `date()`. Items within a group are sorted by message ID descending (newest first).

---

### 34.6 Call Direction & Type Indicators

**Direction arrows** (painted in `paintStatusText`):

| Type | Icon | Color variable |
|------|------|----------------|
| Incoming (answered) | `calls/call_arrow_in` | `callArrowFg` (green) |
| Outgoing | `calls/call_arrow_out` | `callArrowFg` (green) |
| Missed / Busy | `calls/call_arrow_in` | `callArrowMissedFg` (red) |

Arrow position: offset `callArrowPosition` = (-2, 1) relative to the status text origin. After the arrow icon, a `callArrowSkip` = 4px gap before the timestamp text.

**Type detection** (`ComputeType`):
- `Out`: `item->out()` is true.
- `Missed`: Not outgoing, media exists, call state is `Busy` or `Missed`.
- `In`: Everything else (answered incoming call).

**Voice vs. Video distinction** (`ComputeCallType`):
- `Video`: `call->video` is true.
- `Voice`: Default / `call->video` is false.

This affects the redial button icon (see 34.7).

---

### 34.7 Redial Button (Right Action)

Only shown for user peers (`peer()->isUser()`). Two variants based on call type:

**Voice call redial** (`callReDial`):
- Size: 40x56px.
- Icon: `calls/call_answer` in `menuIconFg`, hover: `menuIconFgOver`.
- Icon position: centered (-1, -1).
- Ripple: `defaultRippleAnimation`, area 40px at position (0, 8).

**Video call redial** (`callCameraReDial`):
- Same dimensions as voice.
- Icon: `calls/call_camera_active` in `menuIconFg` / `menuIconFgOver`.

**Right action margins:** `(0, 0, photoPosition.x, 0)` = (0, 0, 12, 0) -- aligns the button to the right with 12px padding from the right edge.

**Click action:** Starts an outgoing call to the peer via `Core::App().calls().startOutgoingCall(user, {})`.

---

### 34.8 Status Text Format

The status line shows a formatted timestamp string, optionally with a group count prefix.

**Single call:**
- Today: `lng_call_box_status_today` -- "{time}" (e.g., "2:30 PM")
- Yesterday: `lng_call_box_status_yesterday` -- "yesterday at {time}"
- Older: `lng_call_box_status_date` -- "{date} at {time}" (e.g., "January 15 at 2:30 PM")

Time format: `QLocale::ShortFormat` (locale-dependent).

**Grouped calls** (multiple calls same peer/date/type):
- `lng_call_box_status_group` -- "({amount}) {status}" (e.g., "(3) 2:30 PM")

The displayed time is always from the newest item (`_items.front()`).

---

### 34.9 Context Menu

Right-clicking a call row opens a `PopupMenu` with `popupMenuWithIcons` style:

1. **"Delete"** (`lng_context_delete_selected`) -- icon `menuIconDelete`. Opens `DeleteMessagesBox` for all message IDs in the row's grouped items.
2. **"Show in Chat"** (`lng_context_to_msg`) -- icon `menuIconShowInChat`. Navigates to the first message in the row's items via `showMessage()`.

---

### 34.10 Row Click Behavior

Clicking a call history row navigates to the peer's chat, scrolled to the newest call message in the group. Uses `showPeerHistory(peer, ClearStack, maxItemId)`.

---

### 34.11 Clear Call History Dialog

Opened from the three-dot menu "Clear All" action. Uses `GenericBox`.

**Content:**
1. Label: `lng_call_box_clear_sure` ("Are you sure you want to delete all call history?"). Styled as `boxLabel`. Margins: `boxPadding`.
2. Checkbox: `lng_delete_for_everyone_check` ("Also delete for other participants"). Default: unchecked. Styled as `defaultBoxCheckbox`. Margins: `(boxPadding.left, boxPadding.bottom, boxPadding.right, boxPadding.bottom)`.

**Buttons:**
- Confirm: `lng_call_box_clear_button` ("Clear"). Calls `MTPmessages_DeletePhoneCallHistory` with optional `f_revoke` flag based on checkbox state. Handles paginated deletion (offset > 0 means more to delete, recurses). On completion, calls `destroyAllCallItems()` and closes the box.
- Cancel: `lng_cancel` ("Cancel"). Closes the box.

---

### 34.12 Create Call Button

**Style:** `inviteViaLinkButton` (a `SettingsButton` variant).

**Floating icon:** `inviteViaLinkIcon`, positioned via `inviteViaLinkIconPosition` at x=determined by style, vertically centered in the button height.

**Label:** `lng_confcall_create_call` ("Create Call").

**Below the button:** `AddDividerText` with `lng_confcall_create_call_description` showing "You can create a group call for up to {count} participants" (count from `appConfig.confcallSizeLimit()`).

**Click action:** Opens `Group::PrepareCreateCallBox` -- the conference call creation flow. On success (call created), closes the calls history box.

**Highlight animation:** When `ShowCallsBox` is called with `highlightStartCall = true`, the create call button receives a `Settings::HighlightWidget` animation after the box finishes showing. This is used when the user tries to start a call from a context where they should use the create-call feature instead.

**Mouse interaction:** When hovering over the create call button, the call history list's mouse-left-geometry handler fires, removing any hover state from the call list rows (prevents visual conflict).

---

### 34.13 Rate Call Dialog

The rate call dialog is presented after a call ends (triggered by the call panel close flow). Style constants are defined even though the dialog construction is handled at a higher layer.

**Star rating row:**
- Padding: `callRatingPadding` = margins(24, 12, 24, 0).
- 5 star buttons, each `callRatingStar`: 36x36px `IconButton`.
  - Unfilled icon: `calls/call_rating` in `windowSubTextFg` (gray).
  - Filled icon: `callRatingStarFilled` = `calls/call_rating_filled` in `lightButtonFg` (blue).
  - Ripple: `defaultRippleAnimationBgOver`, area 36px at (0, 0).
- Star top offset: `callRatingStarTop` = 4px.

**Comment field** (shown after selecting a rating):
- Style: `callRatingComment` = `InputField` with `textMargins(1, 26, 1, 4)`, max height 135px.
- Top margin from stars: `callRatingCommentTop` = 8px.
- Placeholder: typically "Add an optional comment..."

**API call:** `phone.setCallRating` with the selected star count (1-5) and optional comment string.

---

### 34.14 Call Settings Section

Accessed from the calls history three-dot menu > "Call Settings". Navigates to `Settings::CallsId()` which renders the `Calls` section.

**Subsections:**
1. **Output** -- Playback device selector button with device name label.
2. **Input** -- Capture device selector button with device name label + live `LevelMeter` (18px height, 3px line width, 5px spacing, 44 lines).
3. **Call Devices** -- "Use same devices for calls" toggle. When off, shows separate speaker/microphone selectors for calls vs. general media.
4. **Camera** -- Camera device selector + live video preview bubble (aspect-ratio-preserving, max 480/640 ratio, with `boxRoundShadow` extend).
5. **Other** -- "Accept incoming calls on this device" toggle (synced with `authorizations.callsDisabledHere`). "Open system sound preferences" button.

---

### 34.15 Active Call Top Bar

When a call is active, a colored bar appears at the top of the main window (38px height, `callBarHeight`).

**Layout:**
- Left: Mute toggle button (`callBarMuteToggle`, 41x38px). Icon: `calls/call_record_active` in `callBarFg`. Ripple color: `callBarMuteRipple`. Cross-line animation on mute state (`callTopBarMuteCrossLine`).
- Center-left: Duration label (`callBarLabel`, semibold font, `callBarFg`). Top offset: `callBarLabelTop` = 10px.
- Center-left (after duration): Signal bars widget (3px wide bars, 1px skip, 3-12px height range, `callBarFg` color, 50% inactive opacity).
- Center: Info label (`callBarInfoLabel`, semibold font, `callBarFg`). Shows full name or short name depending on available width. Max height: 28px, top-aligned.
- Right: "End Call" label (`callBarLabel`, "End Call" text). Right skip: `callBarRightSkip` = 12px.
- Right: Hangup button (`callBarHangup`, same dimensions as mute toggle). Icon: `calls/call_discard` in `callBarFg`.

**Background:**
- 1:1 call: `callBarBg` (green gradient) when unmuted, `callBarBgMuted` (gray) when muted.
- Group call: Animated gradient based on state:
  - Active: `groupCallLive1` to `groupCallLive2` (green).
  - Muted: `groupCallMuted1` to `groupCallMuted2` (blue/purple).
  - Force-muted: Three-stop gradient `groupCallForceMutedBar1/2/3` at stops 0.0/0.35/1.0.
  - Connecting: `callBarBgMuted` (solid gray).
- State transition: Animated gradient crossfade, duration `universalDuration` (~150ms).

**Group call extras:**
- Userpics row: `groupCallTopBarUserpics` (28px size, 8px shift, 2px stroke). Painted after the mute button.
- Blob animation under the bar: Three linear blobs with 5/7/8 segments, idle radius 3px, max radii 4/12/12px. Update interval 100ms. Level duration 250ms. Hide animation 500ms. Disabled when power-saving calls mode is on or app is deactivated.

**Click behavior:**
- Info area click: Opens the call panel (for 1:1) or group call panel. With Ctrl+click in debug mode: opens `DebugInfoBox` showing call debug log (updated every 500ms, displayed in `callDebugLabel` with margins(24, 0, 24, 0)).
- Hangup click: For 1:1 calls, hangs up directly. For group calls, if the user can manage the call, shows `Group::LeaveBox`; otherwise hangs up directly.

---

### 34.16 Pixel Dimensions Summary

| Element | Property | Value |
|---------|----------|-------|
| Call history row height | `peerListBoxItem.height` | 56px |
| Row avatar size | `contactsPhotoSize` | 42px |
| Row avatar position | `photoPosition` | (16, 7) |
| Row name position | `namePosition` | (74, 9) |
| Row status position | `statusPosition` | (74, 30) |
| Direction arrow offset | `callArrowPosition` | (-2, 1) |
| Arrow-to-text skip | `callArrowSkip` | 4px |
| Redial button (voice) | `callReDial` | 40x56px |
| Redial button ripple area | `rippleAreaSize` | 40px at (0, 8) |
| Redial button (video) | `callCameraReDial` | 40x56px |
| Group call button | `callGroupCall` | 40x56px |
| Right action margin | `rightActionMargins` | (0, 0, 12, 0) |
| Rating star button | `callRatingStar` | 36x36px |
| Rating padding | `callRatingPadding` | (24, 12, 24, 0) |
| Rating star top | `callRatingStarTop` | 4px |
| Rating comment max height | `callRatingComment.heightMax` | 135px |
| Rating comment top margin | `callRatingCommentTop` | 8px |
| Top bar height | `callBarHeight` | 38px |
| Top bar mute button | `callBarMuteToggle` | 41x38px |
| Top bar hangup button | `callBarHangup` | 41x38px |
| Top bar right skip | `callBarRightSkip` | 12px |
| Top bar label top | `callBarLabelTop` | 10px |
| Top bar inter-element skip | `callBarSkip` | 10px |
| Signal bars width | `callBarSignalBars.width` | 3px |
| Signal bars skip | `callBarSignalBars.skip` | 1px |
| Signal bars min height | `callBarSignalBars.min` | 3px |
| Signal bars max height | `callBarSignalBars.max` | 12px |
| Group call top bar userpics | `groupCallTopBarUserpics.size` | 28px |
| Group call top bar userpic shift | `groupCallTopBarUserpics.shift` | 8px |
| Pagination first page | `kFirstPageCount` | 20 |
| Pagination subsequent pages | `kPerPageCount` | 100 |
| Panel animation duration | `callPanelDuration` | 150ms |
| Blob update interval | `kBlobUpdateInterval` | 100ms |
| Blob level duration | `kBlobLevelDuration` | 250ms |
| Blob hide duration | `kHideBlobsDuration` | 500ms |
| Debug info update interval | `kUpdateDebugTimeoutMs` | 500ms |
