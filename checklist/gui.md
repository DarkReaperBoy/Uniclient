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

---

# GUI Implementation Checklist -- Sections 1-7

## 1. Window Layout & Column Structure

### 1.5 Linux Titlebar

### 1.6 Animations

---

## 2. Chat List Sidebar

### 2.1 Folder Tabs

### 2.2 Search Bar

### 2.3 Chat List Rows

### 2.4 Chat Item States

### 2.5 Special Rows

### 2.6 Sorting

### 2.7 Swipe & Drag

---

## 3. Hamburger Menu

### 3.1 Profile Area / Cover

### 3.2 Account Section (collapsible)

### 3.3 Menu Items
- [ ] Settings row with menuIconSettings (S3)
- [ ] Night Mode row with menuIconNightMode and inline toggle (S3)
- [ ] Archive row (shown when user has archive folder) (S3)
- [ ] Row padding: 61px left, 11px top, 20px right, 9px bottom (S3)
- [ ] Row label font: semiboldTextStyle 13px semibold (S3)
- [ ] Row label color: windowBoldFg inactive, windowBoldFgOver hover (S3)
- [ ] Row icon: 24x24 from menu_icons, menuIconColor, at 21px horizontal (S3)
- [ ] Row hover/pressed: windowBgOver background + ripple (S3)
- [ ] Toggle skip: 19px between label and trailing toggle (S3)
- [ ] PlainShadow divider below My Profile/Bots block with 6px padding (S3)
- [ ] AyuGram-exclusive rows gated by showXInDrawer settings (S3)

### 3.4 Night Mode Toggle
- [ ] Night mode: SettingsButton with trailing toggle switch (S3)
- [ ] Toggle "on" pill color: mainMenuCoverBg (S3)
- [ ] Toggle-shift animation offset: 11px (S3)
- [ ] Moon icon: menuIconNightMode in menuIconColor (S3)
- [ ] Label: "Night Mode" in semiboldTextStyle (S3)
- [ ] Toggle off color: windowSubTextFg, on: mainMenuCoverBg (S3)
- [ ] Toggle animation: ~150ms (S3)
- [ ] Theme cross-fade: full-window palette animation on toggle (S3)
- [ ] System dark mode: auto-update toggle when system theme changes (S3)
- [ ] Confirmation dialog when theme editor is active (S3)

### 3.5 Settings Sections
- [ ] My Account with menuIconProfile (S3)
- [ ] Notifications with menuIconNotifications (S3)
- [ ] Privacy and Security with menuIconLock (S3)
- [ ] Chat Settings with menuIconChatBubble (S3)
- [ ] Folders with menuIconShowInFolder (S3)
- [ ] Advanced with menuIconManage (S3)
- [ ] Devices / Active Sessions with menuIconUnmute (S3)
- [ ] Power Saving Mode with menuIconPowerUsage (S3)
- [ ] Language with dynamic label (S3)

### 3.6 Footer
- [ ] Footer container at bottom of scroll area, min height 80px (S3)
- [ ] Top line: product name/website link at left 25px (S3)
- [ ] Top line font: semiboldFont 13px semibold, windowSubTextFg color (S3)
- [ ] Top line link color: windowSubTextFg (NOT blue-tinted) (S3)
- [ ] Top line vertical position: height - 38px - label.height (S3)
- [ ] Bottom line: version + "About" link at left 25px (S3)
- [ ] Bottom line font: 13px regular, windowSubTextFg color (S3)
- [ ] Bottom line vertical position: height - 17px - label.height (S3)
- [ ] Version format: "Version X.Y.Z" with alpha/beta/arch/debug modifiers (S3)
- [ ] "About" link: opens AboutBox (S3)
- [ ] Version link: opens changelog channel (S3)
- [ ] Tooltip on version hover: "Build date: {date}" (S3)

---

## 4. Chat Header / Top Bar

### 4.1 Dimensions & Background
- [ ] Fixed height: 54px (topBarHeight) (S4)
- [ ] Background: topBarBg (day #ffffff, night #17212b) (S4)
- [ ] 1px PlainShadow divider below bar (shadowFg color) (S4)
- [ ] Divider hidden during one-column slide transitions (S4)

### 4.2 Left-to-Right Layout
- [ ] Back button: visible in single-column or forum topic/sublist (S4)
- [ ] Back button: left-arrow icon, 60px width style (S4)
- [ ] Back button right-click: call-type menu (S4)
- [ ] Avatar: UserpicButton, 52x54px hit-area, 42px photo diameter (S4)
- [ ] Avatar photo offset inside hit-area: (2, -1) (S4)
- [ ] Avatar horizontal position based on back button presence (60px or 17px) (S4)
- [ ] Title text: semibold font, elided with ellipsis (S4)
- [ ] Verified/scam/fake badge inline after title (S4)
- [ ] Subtitle/status: dialogsTextFont (S4)
- [ ] DM subtitle: "online" (green) or "last seen [time]" (S4)
- [ ] Group subtitle: "X members, Y online" (S4)
- [ ] Channel subtitle: "X subscribers" (S4)
- [ ] Typing indicator: animated typing/recording/uploading replaces subtitle (S4)

### 4.3 Right-Side Buttons
- [ ] Shared button chrome: 40px width, 54px height, 40px circular ripple (S4)
- [ ] Ripple area position (0, 7), size 40px (S4)
- [ ] Icon colors: menuIconFg normal, menuIconFgOver hover (S4)
- [ ] Icon glyph ~20px inside 40px hit-area (S4)
- [ ] Menu toggle (three-dot): 44px width override, icon at (16, 17) (S4)
- [ ] Menu toggle opens: New Window, Archive, Pin, View Profile, Mute submenu, Mark Read/Unread, Clear History, Delete Chat, Leave Channel (S4)
- [ ] Info toggle: icon top_bar_profile, toggles right info panel (S4)
- [ ] Info toggle active color: windowActiveTextFg (S4)
- [ ] Info toggle hidden in single-column (S4)
- [ ] Call button: icon top_bar_call, 1:1 DMs only (S4)
- [ ] Call button right-click: audio/video call submenu (S4)
- [ ] Group call button: icon top_bar_group_call, for groups/channels (S4)
- [ ] Search button: icon top_bar_search, toggles inline search (S4)
- [ ] Inline search: text field replaces title, with date/user filters (S4)
- [ ] Buttons flush (0-gap), topBarSkip -5px pulls menu tighter (S4)
- [ ] Disabled state: grayscale icon at ~40% alpha, ripple disabled (S4)

### 4.4 Pinned Message Bar
- [ ] Bar height: 49px (historyReplyHeight) (S4)
- [ ] Thumbnail: 32x32px, centered vertically, ~3px corner radius (S4)
- [ ] Title: semiboldTextStyle, color windowActiveTextFg (blue accent) (S4)
- [ ] Title text: "Pinned Message" (single), "Previous Pinned Message" (count==2), "Pinned Message #N" (S4)
- [ ] Preview text: defaultTextStyle, historyComposeAreaFg color (S4)
- [ ] Preview: max 1 line, elided (S4)
- [ ] Close/unpin button: 49x49 hit-area, 40px ripple at (4,4), box_button_close icon (S4)
- [ ] Close button colors: historyReplyCancelFg / historyReplyCancelFgOver (S4)
- [ ] Multi-pin "Show All" button: same size, pinned_show_all icon (S4)
- [ ] Background: historyPinnedBg (day #ffffff, night #1b2734) (S4)
- [ ] Left accent stripe: 2px wide, 36px tall, msgInReplyBarColor (S4)
- [ ] Accent stripe offset: point(1, 0), followed by 10px skip (S4)
- [ ] Content change animation: 160ms (S4)

### 4.5 Contact Status / Action Bar
- [ ] Base button: height 49px, textTop 16px, semiboldFont (S4)
- [ ] Base button color: windowActiveTextFg (blue accent) (S4)
- [ ] Base button: hover bg historyComposeButtonBg, ripple historyComposeButtonBgOver (S4)
- [ ] Destructive variant (Block, Report Spam): attentionButtonFg (red) (S4)
- [ ] Unblock button: height 46px, textTop 14px, attentionButtonFg color (S4)
- [ ] Status label: FlatLabel, minWidth 240px (S4)
- [ ] Inter-button gap: minimum 16px (S4)
- [ ] No icons next to labels (S4)
- [ ] Full-width FlatButtons splitting bar (S4)

### 4.6 Group Call Bar
- [ ] Active call bar with overlapping participant userpics (S4)
- [ ] Green speaking-indicator rings on userpics (S4)
- [ ] "Join" button (S4)

### 4.7 Selection Mode
- [ ] Selection controls slide in from below at topBarHeight (S4)
- [ ] Title/subtitle translate up during selection (S4)
- [ ] Slide animation: slideWrapDuration ~200ms, easeOutCirc (S4)
- [ ] Forward button: defaultActiveButton (blue pill), "FORWARD" uppercase (S4)
- [ ] Send Now button: same style, "SEND NOW" uppercase (S4)
- [ ] Delete button: same style, "DELETE" uppercase (S4)
- [ ] Animated count badge on each button via setNumbersText (S4)
- [ ] Inter-button gap: topBarActionSkip 10px (S4)
- [ ] Corner radii: 8px large on outer ends, small on inner ends (segmented pill) (S4)
- [ ] Cancel/Clear button: RoundButton(defaultLightButton), width -18px (S4)
- [ ] Cancel button right-aligned at 10px from right edge (S4)
- [ ] Cancel label: "CLEAR" / "CANCEL" uppercase (S4)

---

## 5. Message List & Bubbles

### 5.1 Message List
- [ ] Scroll newest-at-bottom with lazy loading via slices (S5)
- [ ] Scroll-to-bottom FAB: 52x62px hit-area, 42px visible disc (S5)
- [ ] FAB icon: two-layer (disc + shadow below, arrow above) (S5)
- [ ] FAB colors (day): disc #ffffff, hover #f1f1f1, arrow menuIconFg, shadow #00000040 (S5)
- [ ] FAB colors (night): inherit windowBg/menuIconFg, shadow unchanged (S5)
- [ ] FAB position: 12px right margin, 10px above viewport bottom (S5)
- [ ] Stacking multiple corner buttons: 4px gap between them (S5)
- [ ] Corner button order bottom-to-top: Jump-down, Mentions, Reactions, PollVotes (S5)
- [ ] FAB slide-in animation: 150ms (S5)
- [ ] Mentions/Reactions/PollVotes slide from off-screen right (S5)
- [ ] Jump-down slides up from below (S5)
- [ ] FAB show threshold: 480px from bottom (S5)
- [ ] Unread-count badge on jump-down: 22px min height, semibold 13px font (S5)
- [ ] Unread badge 4px above button top (S5)
- [ ] Unread badge muted palette: bg #bbbbbb day / #3e546a night, text white (S5)
- [ ] Date separators: centered text in fully-rounded service pill (S5)
- [ ] Date separator font: msgServiceFont 13px semibold (S5)
- [ ] Date separator padding: 12px horizontal, 3px top, 4px bottom (S5)
- [ ] Date separator margins: 10px above, 2px below (S5)
- [ ] Date separator bg: msgServiceBg (#517c417f day / #213040d5 night) (S5)
- [ ] Date separator text: #ffffff (S5)
- [ ] Date separators scroll with messages, NOT sticky (S5)
- [ ] "Unread Messages" bar: full-width band above first unread message (S5)

### 5.2 Message Bubbles
- [ ] Own messages right-aligned, received left-aligned (S5)
- [ ] Saved Messages: forwarded-from-self right, others left (S5)
- [ ] Bubble corner radii: large 16px, small 6px (S5)
- [ ] Each corner independently: None, Small, Large, or Tail (S5)
- [ ] Tail on bottom corner of sender's side (S5)
- [ ] Max bubble width: 430px (542px in wide mode) (S5)
- [ ] Bubble colors day: msgInBg #ffffff, msgOutBg #effdde (S5)
- [ ] Bubble colors day selected: msgInBgSelected #c2dcf2, msgOutBgSelected #b7dbdb (S5)
- [ ] Bubble colors night: msgInBg #182533, msgOutBg #2b5278 (S5)
- [ ] Bubble colors night selected: msgInBgSelected #2e70a5, msgOutBgSelected #2e70a5 (S5)
- [ ] Bubble shadows day: msgInShadow 16% alpha, msgOutShadow 11% alpha (S5)
- [ ] Bubble shadows night: all 00 alpha (disabled) (S5)
- [ ] Bubble margins: left 16px, top 6px, right 56px, bottom 2px (S5)
- [ ] Attached-to-previous: top margin collapses to 0px (S5)
- [ ] Internal padding: 11px horizontal, 8px vertical (S5)

### 5.3 Consecutive Message Grouping
- [ ] AttachedToPrevious/Next flags for spacing (S5)
- [ ] BubbleAttachedToPrevious/Next flags for corner rounding (S5)
- [ ] Top corners: attached-to-prev on sender side = Small 6px, else Large 16px (S5)
- [ ] Bottom corners: attached-to-next on sender side = Small, else Tail or Large (S5)
- [ ] Tail only on last message in group (S5)
- [ ] Sender name + avatar only on first message of group (S5)
- [ ] Avatar size: 33px (S5)
- [ ] Avatar skip: 40px (S5)

### 5.4 Bubble Content Layout
- [ ] Sender name: semibold, colored per user, hidden if attached/DM/own (S5)
- [ ] Admin/creator badge after sender name (S5)
- [ ] Topic button (forums): small pill with topic icon + name (S5)
- [ ] Via bot label (shown if no sender name and no forward header) (S5)
- [ ] Forward header: "Forwarded from Name" (S5)
- [ ] Reply block: 2px wide colored left bar, 36px tall (S5)
- [ ] Reply block: sender name + preview text, 10px gap (S5)
- [ ] Reply block clickable: jump to original message (S5)
- [ ] Message text: rich text support (bold, italic, code, links, spoilers, blockquotes) (S5)
- [ ] Blockquotes with colored outlines (S5)
- [ ] Bottom info: bottom-right with timestamp + edited + status + views + forwards (S5)
- [ ] Bottom info font: msgDateFont 13px regular (S5)
- [ ] Bottom info spacing: 8px before views/replies, 20px per icon, 24px pin, 24px send-state (S5)
- [ ] Icon sizes: sent 13x11, received 18x11, clock 11x11, views 16x11, replies 16x11, pin 18x18 (S5)
- [ ] Tick offset inside send-state slot: point(2, 4) (S5)
- [ ] Outgoing tick color: #57b84c day / #6bbfff night (S5)
- [ ] Media-overlay ticks: #ffffff both themes (S5)
- [ ] Sending clock outgoing: #98d292 day / #70a4d2 night (S5)
- [ ] Sending clock incoming: #a0adb5 day / #76838b night (S5)
- [ ] Sending clock media: #ffffffc8 (S5)
- [ ] Timestamp text colors: day in #a0acb6 / out #6db566, night in #6d7f8f / out #7da8d3 (S5)
- [ ] Selected timestamp colors: day in #6a9cc5 / out #56b2a6, night #ffffff (S5)
- [ ] Edited indicator: localized "edited" text, same font and color as timestamp (S5)
- [ ] Bottom info inside bubble for text messages (S5)
- [ ] Bottom info overlaid on media-only bubbles with translucent background (S5)
- [ ] Media overlay padding: point(8, 2), margin 4px from corner (S5)
- [ ] Reactions: InlineList of emoji, inside or outside bubble (S5)

### 5.5 Sender Name Colors
- [ ] 7 base colors assigned by id % 7 (S5)
- [ ] Color remap via map: [0,7,4,1,6,3,5] (S5)
- [ ] Day colors: #c03d33 red, #4fad2d green, #d09306 yellow, windowActiveTextFg blue, #8544d6 purple, #cd4073 pink, #2996ad sea, #ce671b orange (S5)
- [ ] Night colors: #fb6169, #85de85, #f3bc5c, #65bdf3, #b48bf2, #ff5694, #62d4e3, #faa357 (S5)
- [ ] Selected variants: night = #ffffff, day = same as unselected (S5)
- [ ] Extended 64-entry palette (indices 8-63): fetched at runtime from server (S5)

### 5.6 Selection Mode
- [ ] Long-press or checkbox to select (not single click) (S5)
- [ ] Round checkbox on each message: 20px diameter, 2px stroke (S5)
- [ ] Checkbox empty border: windowBg (white), fill #00000040 (25% black) (S5)
- [ ] Checkbox checked fill: boxTextFgGood (day #4ab44a, night #5598db) (S5)
- [ ] Check glyph color: windowBg (white) (S5)
- [ ] Checkbox position: bottom-right of bubble, 5px above bottom edge (S5)
- [ ] Selection offset: 30px shift left when active (S5)
- [ ] Check-mark animation: 160ms (S5)
- [ ] Top action bar: Forward, Delete, Copy based on selected capabilities (S5)

### 5.7 Service Messages
- [ ] Centered text in rounded pill (S5)
- [ ] Service bg: day #517c417f, night #213040d5 (S5)
- [ ] Service bg selected: day #96b38ba2, night #2e7ab4 (S5)
- [ ] Service text: #ffffff both themes (S5)
- [ ] Radius: height/2 for single-line (fully rounded pill) (S5)
- [ ] Multi-line: per-corner BubbleRounding Large (S5)
- [ ] Service padding: 12px horizontal, 3px top, 4px bottom (S5)
- [ ] Service margins: 10px top, 2px bottom (S5)
- [ ] Service text style: 13px semibold (S5)

---

## 6. Media Message Types

### 6.1 Shared Constants
- [ ] Max media dimension: 430px (S6)
- [ ] Min photo dimension: 100px (S6)
- [ ] Aspect ratio always preserved, never upscaled (S6)

### 6.2 Photos
- [ ] Photos inline in bubble, downscaled to 430x430 max, 100px min (S6)
- [ ] Caption below narrows the photo width (S6)
- [ ] Four-tier loading: full, thumbnail, small, blurred inline placeholder (S6)
- [ ] Click opens media viewer (S6)
- [ ] Enlarge button in bottom-right for large photos (S6)

### 6.3 Spoiler Overlay
- [ ] Per-media spoiler instance (not shared across album) (S6)
- [ ] Animated "spoiler mess" noise: 3000 particles per 128px canvas (S6)
- [ ] Particle sizes: 1.5-2.0 logical px (S6)
- [ ] Particle speed: 10-20 logical px/frame (S6)
- [ ] 5 unique particle shapes, 60 frames at 33ms (~30fps loop) (S6)
- [ ] Particle fade in/out: 300ms each (S6)
- [ ] Spoiler composited across media rect with bubble rounding mask (S6)
- [ ] Tile darkened by alpha 32/255 (S6)
- [ ] Tap-to-reveal: 200ms fadeWrapDuration, sineInOut easing (S6)
- [ ] Once revealed, does NOT re-cover within session (S6)
- [ ] Spoiler paused when off-screen or power-saving on (S6)
- [ ] Text spoiler: 9000 particles, 4-8 speed, 1.5-2px size, 200ms fade (S6)

### 6.4 Photo Albums
- [ ] Up to 10 items per album (S6)
- [ ] Album spacing: 4px between items (S6)
- [ ] Album width: 100-430px (S6)
- [ ] 1-4 items: maxHeight = maxWidth (square ceiling) (S6)
- [ ] 5+ items: maxHeight = maxWidth * 4/3 (S6)
- [ ] Aspect ratio classes: wide (>1.2), narrow (<0.8), square (0.8-1.2) (S6)
- [ ] 2 items: top/bottom or left/right split based on ratios (S6)
- [ ] 3 items: left column + two right, or top + two below (S6)
- [ ] 4 items: wide top + three below, or left + three stacked right (S6)
- [ ] 5-10 items: ComplexLayouter with ratio clamping and scoring (S6)
- [ ] Corner rounding only at group's outer edges (S6)

### 6.5 Videos
- [ ] Same layout as photos (430px max, aspect ratio) (S6)
- [ ] Play button centered on thumbnail (S6)
- [ ] Duration badge + file size in bottom corner (S6)
- [ ] Semi-transparent background behind badge (S6)

### 6.6 GIFs
- [ ] Max width: 320px (smaller than photos) (S6)
- [ ] Auto-play and loop, no audio (S6)
- [ ] Corner badge "GIF" (S6)
- [ ] Max inline area: 1920x1080px (S6)

### 6.7 Stickers
- [ ] No bubble background, standalone (S6)
- [ ] Max size: 224px (static/animated), 256px (emoji stickers) (S6)
- [ ] Lottie for animated (TGS), WEBM for video stickers (S6)
- [ ] Click opens sticker pack (S6)
- [ ] No outline/glow/drop-shadow on stickers (S6)
- [ ] msgStickerOverlay tint only during selection (S6)
- [ ] Auto-play on creation for Lottie + WEBM (S6)
- [ ] Off-screen: unload player, cache state (S6)
- [ ] Static stickers: thumb only, no playback (S6)
- [ ] Power saving: premium effects skip but base animation plays (S6)
- [ ] Premium effect multiplier: 1.49x on both dimensions (S6)
- [ ] Incoming premium stickers mirrored horizontally, outgoing NOT (S6)
- [ ] Premium effect fires once per view (S6)

### 6.8 Voice Messages
- [ ] Voice inside bubble with play/pause button (44px thumb) left (S6)
- [ ] Duration + played status at status line (S6)
- [ ] Interactive seeking by tap position (S6)
- [ ] Optional transcribe button (S6)
- [ ] Waveform: fixed 100 samples, re-bucketed to visible bar count (S6)
- [ ] If no waveform data: 31 random peaks generated (S6)
- [ ] Waveform bar: 2px width, 1px gap, 3px min height, 17px max height (S6)
- [ ] Waveform vertically centered around 17px track (S6)
- [ ] Waveform colors inbox played: windowBgActive #40a7e3 (S6)
- [ ] Waveform colors inbox unplayed: #d4dee6 (S6)
- [ ] Waveform colors outbox played: #5ebd66, unplayed: #b3e2b4 (S6)
- [ ] Waveform selected variants: #51a3d3 / #9cc1e1 / #6badad / #91c3c3 (S6)
- [ ] Playback cursor: color boundary split (no separate cursor line) (S6)
- [ ] Hover highlight: bars in hover range overpainted at alpha 0.30 (S6)

### 6.9 Video Messages (Round Video)
- [ ] Circular, max 360px diameter (S6)
- [ ] Duration badge (S6)
- [ ] Click opens playback (S6)
- [ ] Progress arc stroke: 3px with RoundCap (S6)
- [ ] Arc inset by half stroke width (S6)
- [ ] Arc starts at 12 o'clock (top), sweeps clockwise (S6)
- [ ] Arc color: historyVideoMessageProgressFg (bubble bg color) (S6)
- [ ] Arc global opacity: 0.72 (S6)
- [ ] Auto-play muted when on-screen (S6)
- [ ] Tap toggles sound (S6)

### 6.10 Files/Documents
- [ ] 44px thumbnail/icon left (S6)
- [ ] Filename: middle-truncated (S6)
- [ ] File size displayed right of filename (S6)
- [ ] 11px gap between icon and text (S6)
- [ ] Name at 12px from top, status at 34px (S6)
- [ ] Icon states: download arrow, cancel X, play triangle (S6)

### 6.11 Audio/Music
- [ ] Same layout as document but 44px play/pause button (S6)
- [ ] Track title + artist via FormatSongNameFor (S6)
- [ ] Duration as "played/total" during playback (S6)
- [ ] Cover art replaces generic icon when available (S6)

### 6.12 Polls
- [ ] Question: historyPollQuestionStyle (S6)
- [ ] Radio buttons for single-choice polls (18px diameter, 2px stroke) (S6)
- [ ] Rounded rect checkbox for multi-choice (18px, 3px corner radius) (S6)
- [ ] Untoggled color: checkboxFg, toggled: windowBgActive #40a7e3 (S6)
- [ ] Checked state: icon (check/X) inside filled circle (S6)
- [ ] Idle opacity: 0.7, hover: 1.0 (S6)
- [ ] Toggle animation: 120ms (S6)
- [ ] Loading spinner: InfiniteRadialAnimation 18x18, 2px thickness (S6)
- [ ] After voting: percentage + colored filling bar, easeOutCirc animation (S6)
- [ ] Quiz correct: green (S6)
- [ ] Quiz wrong: red + shake animation (S6)
- [ ] Quiz shake: 400ms linear, +/-3 degree rotation, +/-3% scale (S6)
- [ ] Quiz shake: 8 rotation segments, 2 scale segments (S6)
- [ ] Quiz correct fireworks: 60+30 particles, 480x320 canvas (S6)
- [ ] Fireworks: 6 fixed colors, 2px particles, ~2.5-3s duration (S6)
- [ ] Footer: total votes count (S6)
- [ ] Timed polls: remaining seconds display (S6)
- [ ] Recent voter userpics in a row (S6)

### 6.13 Locations
- [ ] Static map thumbnail: 430px max, 100px min (S6)
- [ ] Optional venue title (2 lines max) + description (3 lines max) (S6)
- [ ] Click opens coordinates (S6)
- [ ] Live-location ring: 28px, in bottom bar (NOT over map) (S6)
- [ ] Ring stroke: 2 logical px (S6)
- [ ] Ring color: msgServiceFg (tinted with bubble style) (S6)
- [ ] Background ring at 0.20 opacity, elapsed arc at full opacity (S6)
- [ ] Arc: starts at 12 o'clock, sweeps counter-clockwise (S6)
- [ ] Progress update: one tick per 1/360 of total period (S6)
- [ ] Remaining minutes number: semiboldFont, center-aligned inside ring (S6)
- [ ] "Until turned off" mode: infinity glyph inside ring (S6)

### 6.14 Contacts
- [ ] Circular userpic left (S6)
- [ ] Name + phone number beside userpic (S6)
- [ ] Action buttons: "Send Message" / "Add Contact" / "View Details" (S6)

### 6.15 Web Page Previews
- [ ] Two modes: Article (small thumbnail right) and Standard (full-width media below) (S6)
- [ ] Mode selection by webpage type, NOT media dimensions (S6)
- [ ] ForceLargeMedia -> Standard, ForceSmallMedia -> Article (S6)
- [ ] Default mode based on page type, siteName, content presence (S6)
- [ ] Article thumbnail: square, clamped to line-height, 8px gutter from text (S6)
- [ ] Description line cap: 3-5 lines depending on siteName/title presence (S6)
- [ ] Fonts: site name and title semibold 13px, description regular (S6)
- [ ] Site name always 1 line (S6)
- [ ] Twitter/Instagram hashtag/mention linking to respective platforms (S6)
- [ ] Video webpages: Standard mode, generic play button overlay (S6)
- [ ] No YouTube-specific styling (no red play button, no branding) (S6)
- [ ] "Open" button 36px for video webpages (S6)

---

## 7. Compose Area

### 7.1 Text Input Field
- [ ] InputField, center of compose strip (S7)
- [ ] Auto-grows vertically, capped at historyComposeFieldMaxHeight (224px) (S7.1)
- [ ] Height min 36px, max 72px before scrolling (S7.1)
- [ ] Document margin: 4px (S7)
- [ ] Placeholder: "Write a message..." (normal), "Broadcast..." (channels), "Edit message" (editing) (S7)
- [ ] Rich text: Bold (Ctrl+B), Italic (Ctrl+I), Underline (Ctrl+U) (S7)
- [ ] Rich text: Strikethrough (Ctrl+Shift+X), Monospace (Ctrl+Shift+M) (S7)
- [ ] Rich text: Spoiler (Ctrl+Shift+P), Blockquote (S7)
- [ ] Instant emoji replacements (:) -> emoji) (S7)
- [ ] Link detection after 500ms debounce (S7)
- [ ] No visible outline: border 0, borderActive 0 (S7.1)
- [ ] Min strip height ~54px (36 + 2x9 padding) (S7.1)
- [ ] Field fade height 6px (top/bottom fade mask on scroll) (S7.1)

### 7.2 Compose Strip Layout
- [ ] Horizontal layout: (botMenu) (attach|replaceMedia) (sendAs) -- field -- (ttl) (scheduled) (silent|botCmd) emojiToggle send (S7.1)
- [ ] Strip bg: historyComposeAreaBg (day #ffffff, night #212121) (S7.1)
- [ ] Strip fg: historyComposeAreaFg (day #000000, night #ffffff) (S7.1)
- [ ] Strip radius: 0px (no rounded corners on desktop) (S7.1)
- [ ] Strip padding: 2px horizontal, 9px vertical (S7.1)

### 7.3 Slot Buttons
- [ ] All slots inherit historyAttach: 44px width, 46px height (S7.1)
- [ ] Slot ripple: 40x40 at (2, 3) (S7.1)
- [ ] Icon colors: historyComposeIconFg (day #a0acb6, hover #639ac6) (S7.1)
- [ ] Send button size: 44x46 (S7.1)
- [ ] Emoji toggle: 20x20 circle ring, line 1.5 (S7.1)

### 7.4 Attachment Button
- [ ] Left side of input (S7)
- [ ] Desktop: opens native OS file picker (NOT mobile-style popup) (S7.2)
- [ ] Attach-bots menu: shown on hover/click if registered attach-bots (S7.2)
- [ ] First attach-bot entry ("Default") falls through to native picker (S7.2)
- [ ] Other attach-bot entries open Web Apps (S7.2)

### 7.5 Send Menu (long-press/right-click on Send)
- [ ] Send silently option with menuMute icon (S7.2)
- [ ] Schedule message option with menuSchedule icon (S7.2)
- [ ] Send until online option with menuWhenOnline icon (for ScheduledToUser) (S7.2)
- [ ] High quality toggle (check) with menuQualityHigh icon (S7.2)
- [ ] Spoiler effect toggle (check) with menuSpoiler icon (S7.2)
- [ ] Caption above/below with menuAbove/Below icon (S7.2)
- [ ] Make/change price with menuPrice icon (S7.2)
- [ ] Premium emoji-effect picker appended for user DMs (S7.2)
- [ ] Popup origin: TopRight, drops down-left (S7.2)
- [ ] Popup animation: 150ms scale+fade, easeOutCirc (S7.2)

### 7.6 Emoji/Sticker/GIF Button
- [ ] Right of input, left of send (S7)
- [ ] Toggles emoji/sticker/GIF panel (S7)
- [ ] Can be floating overlay or third-column panel (S7)

### 7.7 Send Button States
- [ ] Eight states: Send, Schedule, Save, Record, Round, Cancel, Slowmode, EditPrice (S7.3)
- [ ] Editing -> Save (icon chat/input_save) (S7.3)
- [ ] Inline bot -> Cancel (X) (S7.3)
- [ ] Empty field + recording available -> Record or Round (S7.3)
- [ ] Round mode: recordVideoMessages setting && audio+video devices (S7.3)
- [ ] Otherwise -> Send or Schedule (S7.3)
- [ ] Forbidden state: icon at 0.5 opacity (S7.3)
- [ ] Cross-fade morph between non-voice states: 120ms (S7.3)
- [ ] Morph: outgoing fades out + scales to 5x, incoming fades in from 5x to 1x (S7.3)
- [ ] Voice<->Round: Lottie swap animation (mic rolls into camera) (S7.3)
- [ ] Lottie frame cap: 30 frames (S7.3)
- [ ] Slowmode state: "M:SS" countdown, cursor disabled (S7.3)
- [ ] Stars-to-send chip: pill with star-count + icon, height 28px (S7.3)
- [ ] Ripple shape switches per state (ellipse, round rect, etc.) (S7.3)

### 7.8 Voice Record Bar
- [ ] Replaces input during recording (S7.4)
- [ ] Red pulsing circle: 5px signal dot radius (S7.4)
- [ ] Blob radii: main 23-37px, major 43-50px, minor 40-47px (S7.4)
- [ ] Timer font: 13px, duration skip 12px, fg historyComposeAreaFg (S7.4)
- [ ] "Slide to cancel" hint: text width 210px, margins left=15 right=25 (S7.4)
- [ ] Cancel button: 100px width, lightButtonFg color, horizontally centered (S7.4)
- [ ] Duration limit: 100 minutes max, 0.2s minimum (S7.4)
- [ ] Timer precision: 1 decimal place (S7.4)
- [ ] Lock widget: 75x133px, positioned at right=1, top=22 above bar (S7.4)
- [ ] Lock pull-rotate angle: 15 degrees (S7.4)
- [ ] Lock body: 14x17, padlock arc 4px (S7.4)
- [ ] Lock show/hide duration: 150ms (S7.4)
- [ ] Hold-to-record: pointer-down arms timer, release before ~200ms cancels with tooltip (S7.4)
- [ ] Tap-lock: drag up to lock, hands-free recording (S7.4)
- [ ] Locked state: send button morphs to stop-square (12px width) (S7.4)
- [ ] Locked state: cancel text fades out, separate cancel button appears (S7.4)
- [ ] Video-record mode: triggered when Send is Type::Round (S7.4)
- [ ] TTL "voice once" ring: 2px line width on lock when armed (S7.4)

### 7.9 Reply / Edit / Forward Bar (FieldHeader)
- [ ] Above input, height 49px (historyReplyHeight) (S7.1)
- [ ] Reply: author name + text excerpt + 32px thumbnail (S7)
- [ ] Reply: blue/accent vertical bar (2px wide, 36px tall) (S7)
- [ ] Reply: close (x) button (S7)
- [ ] Reply: navigation arrows for stepping through replies (S7)
- [ ] Bar icon: 22x22 at position point(7, 7) (S7.1)
- [ ] Bar cancel button: 49x49 hit-area, 40x40 ripple at (4, 4) (S7.1)
- [ ] Edit: "Edit message" label + original text (S7)
- [ ] Edit: send button -> Save state (S7)
- [ ] Edit: confirmation dialog on cancel (S7)
- [ ] Forward: forwarding author name + message preview (S7)
- [ ] Forward: option to hide sender name (S7)
- [ ] Forward: close button (S7)
- [ ] Web preview: link preview with title + description (S7)

### 7.10 Bot Keyboard
- [ ] Reply keyboard: sticky below field, in ScrollArea (S7.5)
- [ ] Scroll style: defaultSolidScroll (visible thumb, no autohide) (S7.5)
- [ ] Button height: 38px, textTop 9, margin 10, padding 10 (S7.5)
- [ ] Tiny button variant: 25px height, margin 4, padding 3 (S7.5)
- [ ] Text style: 15px semibold (S7.5)
- [ ] Expand/collapse animation: 200ms (S7.5)
- [ ] Keyboard height capped by remaining compose area space (S7.5)
- [ ] Toggle show/hide buttons: 44x46 from historyAttach (S7.5)
- [ ] Single-use keyboard auto-hides after tap (S7.5)
- [ ] Inline keyboard (under message): 36px button height, 2px margin, 10px padding (S7.5)
- [ ] Inline keyboard icons: URL arrow, switch PM, payment card, webview, copy (S7.5)
- [ ] Inline keyboard icon-text padding: 4px (S7.5)
- [ ] Inline keyboard colors: msgBotKbBg/DownBg/IconFg (palette-driven) (S7.5)

### 7.11 Drag & Drop
- [ ] File drag shows drop zone overlay (S7.6)
- [ ] Drag font: 27px semibold, subfont 19px semibold (S7.6)
- [ ] Drag color: windowSubTextFg resting, windowActiveTextFg hovered (S7.6)
- [ ] Drop zone: rounded card with boxBg fill + boxRoundShadow (NOT full-screen wash) (S7.6)
- [ ] Drag margin: 0/10/0/10, padding: 20/10/20/10 (S7.6)
- [ ] Drag area height: 72px (S7.6)
- [ ] Five drop states: None, Files, PhotoFiles, MediaFiles, Image (S7.6)
- [ ] Two cards: document and photo, either full or split vertically (S7.6)
- [ ] Opacity animation 0-1 over boxDuration (S7.6)
- [ ] Cache grabbed as QPixmap on transition start (S7.6)

### 7.12 SendFilesBox
- [ ] Preview width: 308px (S7.7)
- [ ] Image height cap: 1280px (S7.7)
- [ ] Row gap: 10px (S7.7)
- [ ] Top-right 3-dots menu: 48x54, icon title_menu_dots, ripple 42x42 at (1, 6) (S7.7)
- [ ] Caption field: max height 158px (~7 lines), then scrolls (S7.7)
- [ ] Inline emoji button: 30x30 transparent bg at 20px from field top (S7.7)
- [ ] Caption visibility: shown iff list can add caption (S7.7)
- [ ] Invert caption toggle: swap above/below via send menu (S7.7)
- [ ] "Group as album" checkbox (visible if group option available) (S7.7)
- [ ] "Compress images" checkbox (checked = compressed) (S7.7)
- [ ] Compress label varies by count: singular/plural (S7.7)
- [ ] Toggling checkboxes regenerates preview + re-checks limits (S7.7)
- [ ] Limit violation reverts toggle (S7.7)
- [ ] AlbumPreview thumbnail grid: one per contiguous block (S7.7)
- [ ] Max album items: 10 (S7.7)
- [ ] Per-item right-click context menu: Replace, Edit photo, Rename, Edit caption, Spoiler, Edit/Clear video cover (S7.7)
- [ ] Send button: RoundButton, paid peer overrides with price label (S7.7)
- [ ] Send button long-press: same send menu as compose (S7.7)
- [ ] Cancel button (S7.7)
- [ ] Add file button (left): secondary file picker (S7.7)
- [ ] Auto-selected send mode from settings (S7.7)
- [ ] Compression toggle: whole-grid cross-fade (preview rebuilds) (S7.7)
- [ ] Spoiler: per-item via context menu, bulk via top-right menu (S7.7)

### 7.13 Autocomplete
- [ ] @mentions autocomplete (S7)
- [ ] #hashtags autocomplete (S7)
- [ ] /commands autocomplete (S7)
- [ ] Inline bot results (S7)
- [ ] Emoji suggestions while typing :emoji_name (S7)

### 7.14 Additional Controls
- [ ] Send As: sender identity selector for channels (S7)
- [ ] Silent Toggle: broadcast without notification (S7)
- [ ] Scheduled Button: opens scheduled messages view (S7)
- [ ] TTL Button: disappearing message timer (S7)
- [ ] Characters Limit: remaining count near limit (S7)
- [ ] Bot Command Start: "/" button for bot command entry (S7)
- [ ] Gift button: sidebar IconButton when canSendGift (S7.2)

### 7.15 Fallback Compose Buttons
- [ ] Unblock button: height 46px, textTop 14px, attentionButtonFg (red) (S7.1)
- [ ] Start bot / Discuss / Report spam: height 46px, textTop 14px, semiboldFont 13px (S7.1)
- [ ] Contact status button: 49px height variant (S7.1)

# GUI Checklist: Sections 8-14

## 8. Info / Details Panel (Third Column)

### 8.0 Panel Chrome & Layout
- [ ] Panel minimum width 324px, preferred 392px (§8)
- [ ] Layer mode with 48px margin each side (§8)
- [ ] Top bar height: 54px (side mode), 56px (layer mode) (§8)
- [ ] Three wrap modes: Side (persistent), Narrow (full-width takeover), Layer (modal overlay with fade) (§8)
- [ ] Navigation stack: push on sub-section click, pop on back (§8)
- [ ] Slide animation: FromRight to open, FromLeft to go back (§8)
- [ ] Entire panel as one continuous scrollable column (§8)
- [ ] Layer mode rounded top edges via setRoundEdges (§8.6)
- [ ] Layer mode top whitespace: infoLayerTopMinimal=20px, infoLayerTopMaximal=40px (§8.6)
- [ ] Layer mode bg: boxBg, radius: boxRadius (§8.6)
- [ ] Wrap enum: Narrow, Side, Layer, Search, StoryAlbumEdit (§8.6)

### 8.1 Cover / TopBar Compression
- [ ] Cover area: 80px avatar centered, name + username/status below (§8)
- [ ] TopBar fully expanded height: 236px (§8.1)
- [ ] TopBar minimum collapsed height: 56px (§8.1)
- [ ] Three snap-scroll resting heights: 0 (236px), step1 (112px scroll = action row collapsed), step2 (180px scroll = fully collapsed to 56px) (§8.1)
- [ ] Snap animation: easeOutQuint easing, 260ms duration (§8.1)
- [ ] Flexible top bar that compresses on scroll (§8)
- [ ] Avatar photo: 80px diameter, top offset 24px (§8.1)
- [ ] Title top: 113px, status top: 134px (§8.1)
- [ ] Photo bg shift: 55px (has-actions), 30px (no-actions) (§8.1)
- [ ] Height application: clamp(max - scrollTop, 56, 236) (§8.1)
- [ ] Direction reversal mid-animation re-bases via timeOffset (§8.1)
- [ ] Back/title fade: FadeWrap with infoTopBarScale=0.7, infoTopBarDuration=150ms (§8.1)
- [ ] Cover gradient for collectible status / color profile (§8.6)
- [ ] Gradient cached as _cachedGradient, clip path rounds rect in Layer mode (§8.6)
- [ ] Animated emoji-status pattern behind avatar (Premium status) (§8.6)
- [ ] Story ring outline on cover avatar (§8.6)

### 8.2 Action Button Row
- [ ] Action buttons: 52px square, 23px icons, 68px total row height (§8.2)
- [ ] HorizontalFitContainer with 10px spacing between buttons (§8.2)
- [ ] 18px left + 18px right padding around button row (§8.2)
- [ ] Max 3 primary buttons; overflow to "More" popup menu (§8.2)
- [ ] Side wrap mode always uses More button (§8.2)
- [ ] Button roster by peer type: Message, Join, Mute/Unmute, Call, Discuss, Manage/Edit, Leave, Gift, Report, More (§8.2)
- [ ] Mute toggle with Lottie crossfade animation (profile_muting/profile_unmuting) (§8.2)
- [ ] Right-click on mute button opens mute duration menu (§8.2)
- [ ] Action-row collapse: buttons shrink linearly 52->0 past 50% mark of scroll ratio (§8.1)
- [ ] Per-button opacity = height / ActionButtonSize (linear fade) (§8.1)
- [ ] Icon scale holds full size to 40%, then scales with button (§8.1)
- [ ] Text scales with max(0.4, progress) (§8.1)
- [ ] Button label text: font(11px) (§8.2)
- [ ] Themed button colors: bgColor, fgColor, shadowColor from edge color (§8.2)
- [ ] Gradient bg variant for collectible/channel color profiles (§8.2)

### 8.3 Shared Media Navigation
- [ ] No horizontal tab strip -- shared media is tree of full-screen sub-sections (§8.3)
- [ ] Media types: Photo, GIF, Video, MusicFile, File, RoundVoiceFile, Link, RoundFile, Poll (§8.3)
- [ ] Vertical type-button stack (Saved Messages only): Photo, Video, File, MusicFile, Link, RoundVoiceFile, GIF (§8.3)
- [ ] Each media type row hidden when count = 0 (§8.3)
- [ ] Button style: infoSharedMediaButton = infoProfileButton (§8.3)
- [ ] Bottom skip: infoSharedMediaBottomSkip = 12px (§8.3)
- [ ] Normal profile additional rows: Common Groups, Similar Channels, Gifts, Stories, Saved, Polls, Channel Statistics, Downloads (§8.3)
- [ ] Icon tokens for each media type (infoIconMediaPhoto, Video, Gif, File, Audio, Link, Group, Channel, Voice, Poll, Stories, Saved, Gifts) (§8.3)
- [ ] In-section search: SearchFieldRow 44px height, padding margins(8,6,8,6) (§8.3)
- [ ] Layer variant search: 46px height (§8.3)
- [ ] Sub-tab style for stories-archive/gift-category chips (§8.3)

### 8.4 Members Row / List
- [ ] Member row: 42px avatar at position (18, 6), name at (79, 11), status at (79, 31) (§8.4)
- [ ] Row height ~52px (§8.4)
- [ ] 19px gap between avatar right-edge and name left-edge (§8.4)
- [ ] Members header: 56px height (§8.4)
- [ ] Add member button: 38x38px with circle ripple (§8.4)
- [ ] Search button: 38x38px, positioned left of add member (§8.4)
- [ ] Admin/Creator tags: "owner" and "admin" pill badges (§8.4)
- [ ] Tag pill padding: margins(5, -1, 5, 0) (§8.4)
- [ ] Right-action area: tag pill OR remove-cross (§8.4)
- [ ] Online state via status text ("online"/"last seen recently") (§8.4)
- [ ] Stories outline around avatar for unread-stories ring (§8.4)
- [ ] No online/offline divider -- flat list, online-then-alpha sort (§8.4)
- [ ] Context menu on member row: View Profile, Send Message, Promote, Demote, Restrict, Remove, Ban, Copy Username/ID (§8.4)
- [ ] Stories shown on member rows (§8.4)

### 8.5 Grid Columns (Photos/Videos/Gifts)
- [ ] Minimum grid cell size: 82px (§8.5)
- [ ] Grid skip: 2px between cells (§8.5)
- [ ] Grid left/right padding: 3px (§8.5)
- [ ] Grid margin: margins(0, 6, 0, 2) (§8.5)
- [ ] Column count formula: max(1, floor((listWidth - 4) / 84)) (§8.5)
- [ ] Cell side formula: floor((listWidth - 6 - 2(columns-1)) / columns) (§8.5)
- [ ] Square thumbnails for photos/videos (§8.5)
- [ ] 9:16 aspect ratio for Stories grids (§8.5)
- [ ] Date section headers: 28px height, semibold text at offset (14, 6) (§8.5)
- [ ] GIF layout: masonry/waterfall with variable aspect ratios (§8)
- [ ] Files/Links/Audio/Voice: single-column list items (§8)
- [ ] Empty-state widget when list height <= threshold (§8.5)
- [ ] Gifts grid: same formula with taller gift-card aspect override (§8.5)

### 8.6 Additional Info Panel Features
- [ ] Pinned-to-top gifts row: 6 slots around avatar, gift size 20px (§8.6)
- [ ] "Show my last seen" pill: height 18px, font 12px, position point(3, 58) (§8.6)
- [ ] Stars-rating badge: left 107px, top 57px (§8.6)
- [ ] Unique-badge tooltip on click (verified/premium/emoji-status badge) (§8.6)
- [ ] Channel subtitle: "N subscribers" / "N members, M online" (§8.6)
- [ ] Bot About + Commands section below cover (§8.6)
- [ ] Business Hours / Location / Birthday / Personal Channel rows (§8.6)
- [ ] AyuGram ID row (unconditional) (§8.6)
- [ ] Music mini-player hook: padding margins(12, 8, 24, 8), performer sublabel, title bold label (§8.6)

### User Profile (DM)
- [ ] Cover: 72x72px avatar centered, name, username/status below (§8)
- [ ] Action buttons row: Message, Call, Video Call, Search, More (§8)
- [ ] Details fields: phone, username, bio with TextWithLabel style (§8)
- [ ] Details padding: 23px left, 9px top, 20px right, 7px bottom (§8)
- [ ] Empty fields auto-hide (§8)
- [ ] Notifications toggle: reactive on/off (§8)
- [ ] Shared media buttons with count: Photos, Videos, Files, Audio, Links, Voice, GIFs (§8)
- [ ] Common Groups row (§8)
- [ ] Actions: Share/Edit/Delete Contact, Block/Unblock (§8)

### Group Info
- [ ] Cover shows member count as status (§8)
- [ ] Admin/member management buttons for supergroups (§8)
- [ ] Actions: Leave Group, Report, Edit Group (if admin) (§8)
- [ ] Members list inline: 40px avatar + name + online status (§8)
- [ ] Owner/admin badges on member rows (§8)
- [ ] "Add Member" button (§8)
- [ ] Member search toggle (§8)
- [ ] Click on member pushes user profile (§8)

### Channel Info
- [ ] Subscriber count instead of members (§8)
- [ ] No inline members (only admins visible to admins) (§8)
- [ ] Similar Channels button (§8)
- [ ] Join/Leave Channel actions (§8)

### State & Reactivity
- [ ] All values are live streams: name, phone, bio, member count, notifications update in real-time (§8)
- [ ] Memento system saves: scroll position, search query, active media tab, navigation stack (§8)

---

## 9. Context Menus & Actions

### 9.1 Context Menu Chrome
- [ ] Corner radius: 8px (§9.1)
- [ ] Open animation: 200ms, sineInOut (§9.1)
- [ ] Close animation: 150ms fade-out (§9.1)
- [ ] Min popup width: 156px, max: 300px (§9.1)
- [ ] Scroll padding: (0,8,0,8) default / (0,5,0,5) icons variant (§9.1)
- [ ] Item font: normalFont = font(13) (§9.1)
- [ ] Item padding (no icon): margins(17, 8, 17, 7), height ~28px (§9.1)
- [ ] Item padding (with icon): margins(54, 8, 17, 8), height ~29px (§9.1)
- [ ] Icon position: point(15, 5), icon size 20x20 (§9.1)
- [ ] Icon-to-text gap: ~17px after icon (§9.1)
- [ ] Item right skip: 6px before submenu arrow / shortcut (§9.1)
- [ ] Submenu arrow: menu/submenu_arrow tinted windowBoldFg (§9.1)
- [ ] Separator: 1px with margins(0,5,0,5), slot 11px (§9.1)
- [ ] Separator color: menuSeparatorFg (day #f1f1f1 / night #232f39) (§9.1)
- [ ] Ripple: showDuration 650ms, hideDuration 200ms (§9.1)
- [ ] Ripple color: windowBgRipple (day #e5e5e5 / night #24303d) (§9.1)
- [ ] Shadow: blurRadius 5, offset (0, 1), opacity 0.25 (§9.1)
- [ ] PanelAnimation reveal: width 0.5->1.0 over 0.6 of duration, height 0.3->1.0 over 0.9, opacity 0.2->1.0 over 0.3 (§9.1)
- [ ] Top fade: fadeHeight 0.2, fadeOpacity 1.0, fadeBg menuBg (§9.1)
- [ ] Bg color: windowBg (day #ffffff / night #17212b) (§9.1)
- [ ] Hover color: windowBgOver (day #f1f1f1 / night #232e3c) (§9.1)
- [ ] Text color: windowFg (day #000000 / night #f5f5f5) (§9.1)
- [ ] Icon resting color: menuIconFg (day #999999 / night #6c7883) (§9.1)
- [ ] Icon hover color: menuIconFgOver (day #8a8a8a / night #dcdcdc) (§9.1)

### 9.2 Attention-Style Items
- [ ] Attention icon color: attentionButtonFg (day #d14e4e / night #ec3942) (§9.2)
- [ ] Default UX: red icon, normal-colored text (§9.2)
- [ ] Full red-text only for menuWithIconsAttention variant (e.g. Leave-group confirmation submenu) (§9.2)
- [ ] Confirmation box button uses attentionBoxButton (red fill) (§9.2)
- [ ] boxTextFgError for inline error labels (day #d84d4d / night #dc3d3d) (§9.2)

### Message Context Menu
- [ ] Reply / Quote and Reply (§9)
- [ ] Voice Timecode action (on playing voice messages) (§9)
- [ ] Copy Selected Text (§9)
- [ ] Translate Selected (§9)
- [ ] Go to Message (in pinned/preview context) (§9)
- [ ] View Replies / View Topic / View Thread (§9)
- [ ] Edit (own messages within edit time window) (§9)
- [ ] Pin / Unpin (§9)
- [ ] Copy Message/Post Link (§9)
- [ ] Forward (§9)
- [ ] Send Now (scheduled only) (§9)
- [ ] Reschedule (scheduled, max 20) (§9)
- [ ] Save/Copy Image (photos) (§9)
- [ ] Attached Stickers / Open/Save GIF / Sticker Pack Info (§9)
- [ ] Favorite/Unfavorite Sticker (§9)
- [ ] Show in Folder/Finder (local files) (§9)
- [ ] Copy Text (full message) (§9)
- [ ] Translate (§9)
- [ ] Copy Link (on URLs) (§9)
- [ ] Report (§9)
- [ ] Select / Clear Selection (§9)
- [ ] Delete (attention-styled; "Cancel Upload" for uploading) (§9)
- [ ] Poll-specific: Translate Poll, Retract Vote, Stop Poll, per-option submenu (§9)

### 9.6 Item Ordering
- [ ] Pass 1 top actions: Reply, Voice timecode, Todo-list, Copy selected, Copy text, Translate, Copy link (§9.6)
- [ ] Pass 2 message actions: Post Link, Forward, Send Now, Delete, Download Files, Report, Select, Reschedule (§9.6)
- [ ] Pass 3 post-actions: EmojiPacks, SelectRestriction, WhoReacted/WhenEdited (§9.6)
- [ ] AyuGram additions: Edits History, Hide Message, User's Messages, Repeat Message, Message Details submenu, Read Until, Burn (§9.6)
- [ ] Selection-mode top-bar menu: Forward Selected, Send Now Selected, Delete Selected, Download Files, Clear Selection (§9.6)
- [ ] Copy is NOT a submenu -- flat siblings at top level (§9.6)
- [ ] Saved-Messages tag menu: filter by tag, tag rename, tag pack (§9.6)

### Chat List Context Menu
- [ ] Pin/Unpin (§9)
- [ ] Mute submenu (ringtone, toggle sound, preset durations, custom, mute forever/unmute) (§9)
- [ ] Mark as Read/Unread (§9)
- [ ] Archive/Unarchive (§9)
- [ ] New Window (§9)
- [ ] Folder actions (expand/collapse, settings, mark read) (§9)
- [ ] Clear History (§9)
- [ ] Delete/Leave (attention-styled) (§9)

### User Context Menu
- [ ] View Profile (§9)
- [ ] Mention (§9)
- [ ] Send Message (§9)
- [ ] Add/Edit/Delete Contact (§9)
- [ ] Share Contact (§9)
- [ ] Block/Unblock (§9)
- [ ] Report (§9)
- [ ] Admin actions: Promote, Restrict, Ban, Delete All from User (§9)

### 9.3 Reaction Picker
- [ ] Strip height: 40px, slot size: 32px, emoji render: 26px (§9.3)
- [ ] Strip skip/padding: 7px (§9.3)
- [ ] Strip extends: margins(21, 49, 39, 0) bubble margin (§9.3)
- [ ] Strip min width: 60px (§9.3)
- [ ] Strip bubble right: 20px (§9.3)
- [ ] Per-message corner reaction button: pill size 36x32, anchor point(7, -9) (§9.3)
- [ ] Corner reaction image: 22px (§9.3)
- [ ] Corner reaction shadow: margins(4, 8, 4, 8) (§9.3)
- [ ] Floating strip appears after 300ms hover delay (§9.3)
- [ ] Toggle duration: 120ms (rest to shown) (§9.3)
- [ ] Activate duration: 150ms (press feedback) (§9.3)
- [ ] Expand duration: 300ms (strip to full selector) (§9.3)
- [ ] Collapse duration: 250ms (full selector to strip) (§9.3)
- [ ] Full duration: 420ms (expand + scale) (§9.3)
- [ ] Default columns: 8 visible quick reactions (§9.3)
- [ ] Per-icon hover scale: 1.24x over 200ms (§9.3)
- [ ] Selected reaction scales 1.24x over 200ms (§9)
- [ ] Expand chevron opens full panel (§9)
- [ ] Full panel expand: 300-420ms, easeOutCirc (§9)
- [ ] Emoji grid with category tabs, search, sticker effects (§9)
- [ ] Reaction fly-up: 50px vertical travel on pick (§9.3)
- [ ] Reaction appear shift: 20px vertical travel (§9.3)
- [ ] Inline reaction counter: 15px size, 30px image, 3px skip, 6px digit skip, 3px between (§9.3)
- [ ] Premium animated emoji support in strip (§9.3)
- [ ] Button show delay: 300ms, hide delay: 300ms (§9.3)

### 9.4 Forward Dialog (ShareBox)
- [ ] Rows top: 12px above first recipient row (§9.4)
- [ ] Row height: 108px per row (avatar + name) (§9.4)
- [ ] Photo top: 6px, name top: 6px, column skip: 6px (§9.4)
- [ ] Activate duration: 150ms row ripple (§9.4)
- [ ] Scroll duration: 300ms scroll-to selected recipient (§9.4)
- [ ] List item name font: 11px (§9.4)
- [ ] Selected row: blue ring (windowActiveTextFg), avatar shrinks 28->24px (§9.4)
- [ ] Comment field: hidden until recipient selected, slides in (§9.4)
- [ ] Comment field: heightMin 36px, heightMax 72px, no floating label (§9.4)
- [ ] Comment padding: margins(5, 5, 5, 5) (§9.4)
- [ ] Search field at top of box (§9.4)
- [ ] 3-dot menu with forward options: "Show sender's name" and "Show caption" checkmarks (§9.4)
- [ ] 3-dot menu: Schedule option, Send as silent / without-sound / whenOnline (§9.4)
- [ ] Menu opens upward from 3-dots (forced vertical origin Bottom) (§9.4)
- [ ] Send button: "Send" / "Forward", right-click opens same menu (§9.4)
- [ ] Self-chat prioritized first in chat list (§9)
- [ ] Chat filter tabs (folder-based) (§9)

### 9.5 Delete Confirmation Box
- [ ] Single message delete with optional moderate panel (ban + delete-all + report spam) (§9.5)
- [ ] Bulk selection delete (§9.5)
- [ ] Delete by date range (§9.5)
- [ ] Clear history vs leave group/channel (§9.5)
- [ ] Body text matrix: different text per peer type (channel, self, user, group, megagroup) (§9.5)
- [ ] Moderate panel checkboxes: Ban User, Report Spam, Delete All from User (§9.5)
- [ ] Delete button gets "(N)" suffix when delete-all checked (§9.5)
- [ ] "Also delete for X" checkbox with revoke preference remembered (§9.5)
- [ ] Nested "Remember" checkbox when user toggles off-default (§9.5)
- [ ] Hint lines below body per peer type (§9.5)
- [ ] Width: boxWidth, Padding: boxPadding (§9.5)
- [ ] Skips: boxMediumSkip before first checkbox, boxLittleSkip between checkboxes (§9.5)
- [ ] Delete button: attentionBoxButton (red fill) (§9.5)
- [ ] Button text animates between "Delete" and "Leave" as revoke toggles (§9.5)
- [ ] Auto-delete link (clear-history only) (§9.5)

---

## 10. Emoji / Sticker / GIF Panels

### 10.1 Panel Chrome
- [ ] Panel anchors to bottom-right of compose area (§10.1)
- [ ] Panel width: 345px (§10.1)
- [ ] Panel min height: 278px, max height: 640px (§10.1)
- [ ] Panel margins: margins(10, 10, 10, 10) (§10.1)
- [ ] Corner radius: 8px (§10.1)
- [ ] Show duration: 200ms (§10.1)
- [ ] Slide duration: 200ms (§10.1)
- [ ] Height formula: emojiPanHeightRatio x window height, clamped to [278px, 640px] (§10.1)
- [ ] Auto-hide: 300ms on mouse-leave (§10.1)
- [ ] Delayed hide: 3000ms when context menu open (§10.1)
- [ ] Shadow via BoxShadow around rounded-rect content (§10.1)
- [ ] Background fill: emojiPanBg theme token (§10.1)
- [ ] PanelAnimation for show/hide (§10.1)

### 10.2 Tab Bar
- [ ] Three text labels: Emoji / Stickers / GIFs (§10.2)
- [ ] Tab switching via TabbedSelector switchTab (§10.2)
- [ ] Slide animation: 200ms linear horizontal translate + alpha crossfade (§10.2)
- [ ] Both old and new tabs captured as QPixmap for animation (§10.2)
- [ ] Slide direction derived from tab index delta (§10.2)
- [ ] SettingsSlider subclass, semiboldFont labels (§10.2)
- [ ] Active section underline using activeLineFg (§10.2)

### 10.3 Emoji Tab
- [ ] 8 category icons: Recent, Smileys, Nature, Food, Activities, Travel, Objects, Symbols (§10.3)
- [ ] Category icon via Lottie/static PNG (§10.3)
- [ ] Active category: activeFg fill behind icon (§10.3)
- [ ] Grid columns: (panelWidth - 2*padding) / singleSize (§10.3)
- [ ] Cell size ~37-42px depending on DPR (§10.3)
- [ ] Skin-tone popup: long-press 500ms delay (§10.3)
- [ ] Skin-tone popup: base + 5 Fitzpatrick variants (§10.3)
- [ ] Skin-tone popup chrome: emojiColorsPadding = 8px, emojiColorsSep = 1px (§10.3)
- [ ] Skin-tone selection persists per-emoji in settings (§10.3)
- [ ] Custom emoji packs: sections after standard categories (§10.3)
- [ ] Locked packs: "Unlock" button (premium gate) (§10.3)
- [ ] Public free packs: "Add" button (§10.3)
- [ ] Collapsed sets: 3 rows + "+N" overflow badge (§10.3)

### 10.4 Sticker Tab
- [ ] Grid columns by panel width vs stickerPanSize (~64px) (§10.4)
- [ ] Sticker padding: 11px around grid (§10.4)
- [ ] Footer: kVisibleIconsCount = 8 pack icons, horizontally scrollable (§10.4)
- [ ] Active pack highlighted with selection bg (rounded corners in emojiPanRadius) (§10.4)
- [ ] Scroll-to-pack animation: stickerIconMove = 400ms, easeOutCubic (§10.4)
- [ ] "Recent" section (server-capped at 20 stickers) (§10.4)
- [ ] Installed packs with semibold header (§10.4)
- [ ] Featured/trending packs with inline "Add" button (~26px tall) (§10.4)
- [ ] Search row: 400ms debounce before server query (§10.4)
- [ ] Empty search state shows recent popular packs (§10.4)
- [ ] Context menu on sticker: Fave/Unfave, View Set (§10.4)
- [ ] Custom emoji packs context menu: also Copy Link (§10.4)

### 10.5 GIF Tab (Masonry)
- [ ] GIF padding: margins(9, 5, 3, 9) (§10.5)
- [ ] Left padding negated by panel radius (§10.5)
- [ ] Top padding extended by search bar height (§10.5)
- [ ] Inter-item skip: 3px on both axes (§10.5)
- [ ] Line-packing layout (NOT true masonry): fill each row until next item won't fit (§10.5)
- [ ] Row height uniform within one row, varies between rows (§10.5)
- [ ] Default source: saved GIFs (@gif favorites) (§10.5)
- [ ] Query switches to inline @gif bot results (§10.5)
- [ ] Category shortcuts in footer: emoji tokens (cat, heart, dance, etc.) (§10.5)
- [ ] Context menu: Save GIF / Delete GIF (§10.5)

### 10.6 Inline Suggestions (Field Autocomplete)
- [ ] Separate widget, NOT part of TabbedPanel (§10.6)
- [ ] Anchored above compose field (§10.6)
- [ ] Triggered by @, /, :text, #hashtag, or emoji sequence (§10.6)
- [ ] Row height: 40px (mentionHeight) (§10.6)
- [ ] Max visible: 4.5 rows, panel height cap ~180px (§10.6)
- [ ] Scrolls beyond cap (§10.6)
- [ ] Emoji suggestions (:text trigger): horizontally scrollable row, ~40px cells (§10.6)
- [ ] 8px fade padding at ends of emoji scroll viewport (§10.6)
- [ ] Selected emoji replaces :text token in-place (§10.6)
- [ ] Sticker suggestions (Unicode emoji trigger): half-width cells, server query, click sends (§10.6)
- [ ] Inline bot results: 400ms debounce, mosaic row-packing (§10.6)
- [ ] Arrow keys / Tab navigate, Enter picks (§10.6)
- [ ] Mentions/hashtags/commands: no debounce, client-side filter (§10.6)
- [ ] Mention row: 40px avatar + name + subtitle (§10.6)

### 10.7 Additional
- [ ] No "Masks" tab in default build (§10.7)
- [ ] Power-save gating: panel animation skips when PowerSaving::kEmojiPanel is on (§10.7)
- [ ] Context-menu teardown: 3000ms delayed hide while menu is open (§10.7)
- [ ] AyuGram: per-pack "Hide" toggle in sticker-pack context menu (§10.7)

---

## 11. Authentication / Login Flow

### 11.1 Architecture
- [ ] Step stack managed by Intro::Widget (§11.1)
- [ ] Each screen = Step subclass sharing Data struct (phone, phoneHash, codeLength, callStatus, pwdState, termsLock) (§11.1)
- [ ] Navigation: goNext / goBack / goReplace with slide/cover animations (§11.1)
- [ ] Persistent bottom bar: _next RoundButton, _back IconButton, _changeLanguage LinkButton, _settings button, optional _resetAccount button (§11.1)

### 11.2 Next Button
- [ ] Next button width: 300px, height: 42px, radius: 6px, textTop: 11px (§11.2)
- [ ] Base Y position: introNextTop = 266px (§11.2)
- [ ] Slide-in Y interpolation from introNextTop + 200px to introNextTop (§11.2)
- [ ] Visibility toggle: 150ms linear fade (§11.2)
- [ ] Button text reactive via nextButtonText stream (§11.2)
- [ ] No spinner overlay; loading state via per-step UI (§11.2)
- [ ] Submit flood: button disabled until server responds (§11.2)
- [ ] On error: button stays visible, failing field gets shake + red border (§11.2)

### 11.3 QR Code Screen
- [ ] QR max size: 180px (§11.3)
- [ ] White-card padding: 12px around QR matrix (§11.3)
- [ ] Card corner radius: 8px (§11.3)
- [ ] Center logo disc: 44px, blue (#40A7E3) with Telegram plane glyph (§11.3)
- [ ] Radial spinner while waiting for token: sized to 180px, 1-2px stroke, #40A7E3 color (§11.3)
- [ ] Spinner opacity fades with (1 - shown) as QR appears (§11.3)
- [ ] QR generated with Quartile (~25% error correction) redundancy (§11.3)
- [ ] New QR token crossfades over old one, no slide (§11.3)
- [ ] Layout: centered QR + 3 numbered instruction lines (bold step number, regular instruction) (§11.3)
- [ ] "Log in by phone number" link below instructions (§11.3)
- [ ] Next button hidden on QR screen (§11.3)

### 11.4 Phone Number Screen
- [ ] Country picker: width 300px, heightMin 61px (§11.4)
- [ ] Country code field: fixed 64px wide, "+" prefix, digit-only mask (§11.4)
- [ ] Phone body field: ~236px wide, digit-only mask with space separators per country pattern (§11.4)
- [ ] Country picker popup: MultiSelect search filter + scrollable row list (§11.4)
- [ ] Row: flag emoji + country name + +XX code (§11.4)
- [ ] Phone-body validation: length > 1 digit required (§11.4)
- [ ] PHONE_NUMBER_INVALID: inline error label under phone field, field shake (§11.4)
- [ ] PHONE_NUMBER_BANNED: modal dialog with support-email link (§11.4)
- [ ] Flood: inline warning + countdown (§11.4)

### 11.5 OTP Code Screen
- [ ] Cell height: 50px, width: 40px (height x 0.8) (§11.5)
- [ ] Cell border width: 4px (§11.5)
- [ ] Inter-cell gap: 10px (§11.5)
- [ ] Digit font: 20px (§11.5)
- [ ] Cell bg: windowBgOver (§11.5)
- [ ] Unfocused border: windowBgRipple (§11.5)
- [ ] Focused border: windowActiveTextFg (§11.5)
- [ ] Error border: activeLineFgError (§11.5)
- [ ] New digit animation: fade in + slide up 10px (§11.5)
- [ ] Delete animation: scale-down + fade-out (§11.5)
- [ ] Animation duration: 120ms linear (§11.5)
- [ ] Error shake on wrong code (§11.5)
- [ ] Arrow/Home/End navigate cells; Backspace deletes + moves left (§11.5)
- [ ] Paste auto-fills + submits when complete (§11.5)
- [ ] Each cell is its own focus target (§11.5)
- [ ] Call countdown row: "Telegram will call you in X:XX" -> "Calling..." (§11.5)
- [ ] "Didn't get the code?" link for alternate delivery (§11.5)

### 11.6 2FA Password Screen
- [ ] Password top offset: 74px (§11.6)
- [ ] PasswordInput field: 300px wide (§11.6)
- [ ] Hint label: "Hint: {hint}" only when configured (§11.6)
- [ ] SRP hash computed client-side (§11.6)
- [ ] Error: shake + red border + automatic selectAll (§11.6)
- [ ] "Forgot password?" link: swaps to recovery-code mode (§11.6)
- [ ] Recovery: password hides, code input appears, copy shows email pattern (§11.6)
- [ ] No recovery email: info box with "Reset account" button (7-day timer) (§11.6)

### 11.7 Registration Screen
- [ ] Avatar: UserpicButton at top offset 10px (§11.7)
- [ ] Tap opens system photo picker, server crop-upload (§11.7)
- [ ] First name + Last name fields, each 300px wide, stacked vertically (§11.7)
- [ ] RTL swap: last-name first for Arabic/Farsi/Hebrew (§11.7)
- [ ] Title: "Your Name", description: "Enter your name and add a profile photo" (§11.7)
- [ ] Terms acceptance dialog gates submit when termsLock set (§11.7)
- [ ] Next button text: "Start Messaging" (§11.7)

### 11.8 Inter-Screen Animations
- [ ] Cover height: 208px gradient (introCoverHeight) (§11.8)
- [ ] Gradient: vertical linear from introCoverTopBg to introCoverBottomBg (blue sweep) (§11.8)
- [ ] Logo placement: centered minus introCoverIconLeft=50px, top introCoverIconTop=46px (§11.8)
- [ ] Slide easing: easeOutCirc for cover transitions (QR/phone), linear otherwise (§11.8)
- [ ] Title/description crossfade: 200ms (introCoverDuration) (§11.8)
- [ ] Non-cover slide: horizontal translate over 200ms with clipping (§11.8)
- [ ] Direction from goNext vs goBack (§11.8)

---

## 12. Calls UI

### 12.1 1-on-1 Call Panel
- [ ] Default window size: 720x540 (§12.1)
- [ ] Minimum window size: 380x520 (§12.1)
- [ ] Incoming state: centered userpic 160px circle, caller name 21px semibold (§12.1)
- [ ] Incoming status text: "Incoming call..." (§12.1)
- [ ] Incoming buttons: Decline (red), Answer (green with animated ripple ring) (§12.1)
- [ ] Answer ripple: radius tracks ringtone peak audio level, anchored at 135deg (§12.1)
- [ ] Background: gradient sampled from caller profile-photo dominant colors (§12.1)
- [ ] Active audio call: userpic, name, duration timer mm:ss (1Hz tick) (§12.1)
- [ ] Bottom button row order: Screencast, Camera, Hangup (red, centered, "End Call"), Mute, Add People (§12.1)
- [ ] Button row crossfade: 150ms on state change (§12.1)
- [ ] Remote pills: "[User] muted their microphone" tooltip (§12.1)
- [ ] Low-battery indicator pill (same style as muted pill) (§12.1)
- [ ] Controls auto-hide: 5000ms in fullscreen, 2000ms on mouse-leave (§12.1)
- [ ] Mouse movement restores controls (§12.1)

### 12.2 Signal Bars
- [ ] 4 bars total (§12.2)
- [ ] Bar width: 2px, min height: 4px, max height: 10px, skip: 2px, radius: 1px (§12.2)
- [ ] Bar heights left to right: 4, 6, 8, 10px (§12.2)
- [ ] Active bar: callBarFg at full opacity (§12.2)
- [ ] Inactive bar: same color at 0.5 opacity (§12.2)
- [ ] Signal quality [0..100] mapped to [0..4] active bars (§12.2)
- [ ] Bars snap to new count, no interpolation (§12.2)

### 12.3 Encryption Fingerprint
- [ ] 4 emoji displayed at rest (§12.3)
- [ ] Carousel: 10 emojis cycled during reveal animation (§12.3)
- [ ] Stagger: 50ms between adjacent emoji carousels (§12.3)
- [ ] Per-emoji hop: 100ms (total reveal ~1200ms) (§12.3)
- [ ] Tooltip hover delay: 1000ms ("Call is end-to-end encrypted...") (§12.3)
- [ ] Emoji indices from SHA-256 fingerprint over 658-emoji table (§12.3)
- [ ] Pill container: radius = height/2 (§12.3)
- [ ] Embedded next to signal bars (§12.3)

### 12.4 Video Call / PIP
- [ ] Remote video: fills main area with KeepAspectRatio crop (§12.4)
- [ ] Userpic/name/status hidden while remote stream is live (§12.4)
- [ ] Self-view VideoBubble: default 160x110px (§12.4)
- [ ] Snap-to-corners: TopLeft, TopRight, BottomLeft, BottomRight (default BottomRight) (§12.4)
- [ ] On mouse-release: picks nearest corner by Euclidean center distance (§12.4)
- [ ] Snap animation: 12px inset rest position, ~120ms easeOutCirc (§12.4)
- [ ] Self-view mirror default ON (flipped horizontally) (§12.4)
- [ ] Mirror OFF during local screen-share (§12.4)
- [ ] Pre-connect outgoing preview: scales between 360x120 and 1620x540 based on window height (§12.4)
- [ ] Preview size formula: size = min + (max - min) x (h - hMin) / (hDefault - hMin) (§12.4)
- [ ] Camera button: active = camera glyph, disabled = crossed-out camera (§12.4)
- [ ] Camera button corner chevron: device-selector menu for camera/mic switch (§12.4)

### 12.5 Group Call - Narrow / Wide
- [ ] Width threshold: 600px (groupCallWideModeWidthMin) (§12.5)
- [ ] Wide mode when: rtmp() or (hasVideoWithFrames && width >= 600) (§12.5)
- [ ] Narrow mode: single column -- participants list + bottom controls (§12.5)
- [ ] Narrow minimum width: 380px (§12.5)
- [ ] Wide mode: video viewport + members sidebar (§12.5)
- [ ] Transition animation via slideWrapDuration (~150-200ms) (§12.5)
- [ ] Title bar: group name, participant count subtitle, menu toggle (§12.5)
- [ ] Recording state: 6px red dot with 1200ms opacity-breathing loop (§12.5)

### 12.6 Speaker Blob Animation
- [ ] Blob min radius: 27px, max radius: 29px (§12.6)
- [ ] Minor blob: inner, scale factor 0.545, 6 vertices (§12.6)
- [ ] Major blob: outer, scale factor 0.605, 8 vertices (§12.6)
- [ ] Level duration: 215ms interpolation between min/max radii (§12.6)
- [ ] Userpic scale: pulses between 80% and 100% with voice level (§12.6)
- [ ] kWideScale = 5 for centered wide-mode userpic (§12.6)

### 12.7 Mute Button (Big)
- [ ] 36x36 Lottie icon inside 42px-diameter circle (§12.7)
- [ ] Three states: green (unmuted), gray (muted), purple (force-muted by admin) (§12.7)
- [ ] Each state change plays dedicated Lottie segment (§12.7)
- [ ] Blob ring surrounding circle pulses with 215ms envelope (§12.7)

### 12.8 Minimised TopBar
- [ ] Bar height: 38px (§12.8)
- [ ] Contents: group name, mm:ss duration, participant userpic strip (each 28px, 8px overlap), mute toggle, hangup (red) (§12.8)
- [ ] Gradient states: Active (greens), Muted by self (grays), Connecting (solid callBarBgMuted), Force-muted (purples) (§12.8)
- [ ] Gradient transition: sweeps across bar width, mute-icon cross-line interpolates simultaneously (§12.8)

### 12.9 Screen-Share Source Chooser
- [ ] Dual-tab layout: "Windows" vs "Full Screen" (§12.9)
- [ ] Thumb geometry: 235x165px, 2px horizontal gap, 10px vertical gap (§12.9)
- [ ] Optional "Share audio" checkbox (Linux PipeWire gated) (§12.9)
- [ ] Standard BoxContent modal chrome (§12.9)

### 12.10 Rating Dialog
- [ ] 5 star icons (reported 36x36 with 24px padding -- unverified) (§12.10)
- [ ] Unselected color: windowSubTextFg (§12.10)
- [ ] Selected color: lightButtonFg (§12.10)
- [ ] Comment input below, max height 135px (§12.10)
- [ ] Submit: (rating 1-5, comment) via phone.setCallRating (§12.10)

---

## 13. Mobile / Web Compatibility Notes

### 13.1 Adaptive Layout Breakpoints
- [ ] Minimum sidebar width: 260px (columnMinimalWidthLeft) (§13.1)
- [ ] Minimum message list width: 380px (columnMinimalWidthMain) (§13.1)
- [ ] Minimum info panel width: 292px (columnMinimalWidthThird) (§13.1)
- [ ] Wide chat bubbles centering threshold: 880px (adaptiveChatWideWidth) (§13.1)
- [ ] OneColumn mode: < 640px (§13.1)
- [ ] Normal / Two-column: 640px to 932px (§13.1)
- [ ] ThreeColumn: >= 932px (§13.1)
- [ ] isOneColumn(), isNormal(), isThreeColumn() predicates (§13.1)
- [ ] Group call narrow/wide switch: 600px (distinct from main window) (§13.1)

### 13.2 OneColumn Mode (< 640px)
- [ ] Only one panel visible at a time (dialogs OR chat OR info) (§13.2)
- [ ] Chat list fills full window width (§13.2)
- [ ] Tapping chat slides message view in from right (§13.2)
- [ ] Back button appears in chat top-bar (§13.2)
- [ ] Info panel opens as full-width takeover layer (§13.2)
- [ ] Folder tabs switch from vertical rail to horizontal strip below search bar (§13.2)
- [ ] Compose area full-width, controls unchanged (§13.2)
- [ ] No resize handles (§13.2)
- [ ] Slide animation: easeOutCirc (incoming), easeInCirc (outgoing), ~200-250ms (§13.2)
- [ ] Both sides rendered as cached pixmaps with hardware-accelerated translate (§13.2)

### 13.3 Other Responsive Adaptations
- [ ] Sidebar cannot shrink below 260px (§13.3)
- [ ] No "avatar-only" strip mode in upstream (§13.3)
- [ ] Wide chat mode (>= 880px): bubbles center with gutters (§13.3)
- [ ] Emoji panel height clamped to [278px, 640px] (§13.3)
- [ ] Forward/Share dialog: full-screen overlay regardless of width (§13.3)

### 13.4 Touch vs Mouse
- [ ] Long-press instead of right-click for context menus (§13.4)
- [ ] Long-press threshold: ~500ms desktop / ~300ms mobile (§13.4)
- [ ] Swipe gestures: Manhattan distance gate ~5-10px (§13.4)
- [ ] Drag-to-reorder threshold: 30px vertical (§13.4)
- [ ] Drag-to-filter thresholds: 30px horizontal, 75px vertical (§13.4)
- [ ] Folder tab auto-switch while dragging: 2000ms hover freeze timeout (§13.4)
- [ ] Voice recording: hold-to-record, slide up to lock (§13.4)
- [ ] Long-press to enter selection mode (§13.4)

### 13.5 Flutter-Web Divergence
- [ ] Hide on web: system tray icon, global hotkeys, native file picker, clipboard image read, process-level single-instance (§13.5)
- [ ] Web alternative: Web Notifications API + favicon badge instead of tray (§13.5)
- [ ] Web alternative: <input type=file> and HTML5 drop events instead of native file picker (§13.5)
- [ ] Degraded: keyboard shortcuts yield to browser-reserved combos (§13.5)
- [ ] Degraded: native notifications use window.Notification (requires permission) (§13.5)
- [ ] Degraded: fullscreen requires user gesture (§13.5)
- [ ] Degraded: WebRTC getUserMedia constrains device-selection UX (§13.5)
- [ ] Mobile-web: hover states become tap-only (§13.5)
- [ ] Mobile-web: compose-toolbar formatting buttons visible instead of Ctrl+B/I/U (§13.5)

---

## 14. Settings -- General & My Account

### 14.1 Opening Settings
- [ ] Settings reached via hamburger menu item "Settings" (§14.1)
- [ ] Pushes Main settings section as full-height inner panel (§14.1)
- [ ] Top bar: back arrow (infoTopBarBack) + title "Settings" (§14.1)
- [ ] Three-dot overflow menu: Add Account, Edit Profile, Log Out (§14.1)
- [ ] Add Account: hidden at max accounts (10 Premium, 3 free), icon menuIconAddAccount (§14.1)
- [ ] Edit Profile: navigates to My Account/Information section, icon menuIconEdit, hidden in support mode (§14.1)
- [ ] Log Out: confirmation dialog (lng_sure_logout), attentionBoxButton (red), icon menuIconLeaveAttention (§14.1)

### 14.2 Main Settings Page -- Cover / Profile Header
- [ ] Cover total height: settingsPhotoTop (8px) + photo height (88px) + settingsPhotoBottom (16px) = 112px (§14.2)
- [ ] Avatar: 88px circular UserpicButton at (22px left, 8px top) (§14.2)
- [ ] Avatar role: OpenPhoto -- clicking opens full photo viewer (§14.2)
- [ ] Avatar hover: semi-transparent overlay with camera icon (§14.2)
- [ ] Avatar menu: Upload photo from file, Choose from emoji/stickers (§14.2)
- [ ] Circular progress indicator during upload (§14.2)
- [ ] Display Name: FlatLabel at (112px left, 12px top), 17px semibold (§14.2)
- [ ] Name: selectable text, right-click "Copy Full Name" (§14.2)
- [ ] User ID: FlatLabel at (112px left, 37px top), defaultFlatLabel style (§14.2)
- [ ] User ID: right-click "Copy ID" (AyuGram addition) (§14.2)
- [ ] Username: FlatLabel at (112px left, 58px top), windowSubTextFg color (§14.2)
- [ ] Username: displayed as link, if empty shows "Add" link text (§14.2)
- [ ] Username click: if exists, copies t.me/username link + shows toast; if empty, opens Usernames box (§14.2)
- [ ] QR Code button: right-aligned, vertically centered, only visible with username (§14.2)
- [ ] QR button: IconButton using infoProfileLabeledButtonQr style (§14.2)
- [ ] Premium badge: inline after name at (4px right, 2px down), clicking opens emoji status panel (§14.2)
- [ ] Cover is not collapsible -- scrolls out of view (§14.2.2)
- [ ] No parallax, no pinned-header shrink, no fade (§14.2.2)
- [ ] Name max-width: recomputed on resize = width - QR button - badge - right padding (§14.2.3)

### 14.3 Main Settings Page -- Navigation Buttons
- [ ] Each button: SettingsButton with icon in rounded-square bg, title, right chevron (§14.3)
- [ ] All buttons have ripple animation on press (§14.3)
- [ ] Row total height: ~41px (10px top + 10px bottom padding + 21px text) (§14.3.1)
- [ ] Left padding: 60px (icon column) (§14.3.1)
- [ ] Icon horizontal position: 20px from left edge (§14.3.1)
- [ ] Icon background: 6px rounded square (settingsIconRadius) (§14.3.1)
- [ ] Right padding: 22px (§14.3.1)
- [ ] Right chevron/label skip: 23px (§14.3.1)
- [ ] Label text style: boxTextStyle (14px regular) (§14.3.1)
- [ ] No inter-row separators -- grouping via AddSkip + AddDivider pairs (§14.3.1)
- [ ] Hover state: settingsButton hover fill (§14.3.1)
- [ ] Pressed state: ripple originating at cursor (§14.3.1)

#### Navigation Button Order
- [ ] 1. AyuGram Preferences -- icon menuIconPremium (star), followed by skip+divider+skip (§14.3)
- [ ] 2. My Account -- icon menuIconProfile, hidden in support mode (§14.3)
- [ ] 3. Notifications and Sounds -- icon menuIconNotifications (bell) (§14.3)
- [ ] 4. Privacy and Security -- icon menuIconLock (padlock) (§14.3)
- [ ] 5. Chat Settings -- icon menuIconChatBubble (§14.3)
- [ ] 6. Folders -- icon menuIconShowInFolder, conditional on chat folders enabled (§14.3)
- [ ] 7. Advanced -- icon menuIconManage (gear/wrench) (§14.3)
- [ ] 8. Devices -- icon menuIconUnmute (speaker) (§14.3)
- [ ] 9. Power Saving -- icon menuIconPowerUsage (battery), opens dialog not subsection (§14.3)
- [ ] 10. Language -- icon menuIconTranslate (globe/A), right label shows current language name (§14.3)
- [ ] Language click opens LanguageBox with searchable list (§14.3)

#### Button Grouping
- [ ] Group 1: AyuGram Preferences (standalone, skip+divider+skip after) (§14.3.1)
- [ ] Group 2: My Account, Notifications, Privacy, Chat Settings, Folders (no inter-row dividers) (§14.3.1)
- [ ] Group 3: Advanced, Devices (skip+divider+skip before and after) (§14.3.1)
- [ ] Group 4: Power Saving, Language (§14.3.1)

### 14.4 Interface Scale
- [ ] "Use Default Scale" toggle button with switch on right (§14.4)
- [ ] When ON: follows system DPI (kScaleAuto) (§14.4)
- [ ] Scale slider: continuous MediaSlider, seek handle 15x15px (§14.4)
- [ ] Slider padding (standard): margins(60, 7, 22, 4) (§14.4.1)
- [ ] Slider padding (wide/big): margins(21, 7, 21, 4) (§14.4.1)
- [ ] Right-side percentage label: FlatLabel with windowActiveTextFg color (§14.4.1)
- [ ] Step: 5 percentage-point discrete stops (§14.4.1)
- [ ] Range: kScaleMin (100%) to MaxScaleForRatio(DPR), typically 100%-300% (§14.4.1)
- [ ] Preview tooltip: floating ScalePreview above thumb during drag (§14.4)
- [ ] UI scale does NOT change in real-time -- applied on pointer-release (§14.4.1)
- [ ] Restart confirmation dialog when scale differs: "Restart Now" / "Cancel" (§14.4)
- [ ] Cancel reverts slider, Accept calls Core::Restart() (§14.4.1)
- [ ] SlideWrap on slider: collapses to zero height when "Use Default" is ON (§14.4.1)

### 14.5 My Account / Edit Profile
- [ ] Title: "Edit Profile" (§14.5)
- [ ] Vertically scrolling panel (§14.5)

#### 14.5.1 Profile Photo Area
- [ ] Photo area height: 162px (settingsInfoPhotoHeight) (§14.5.1)
- [ ] Photo: UserpicButton 100x100px, centered horizontally, 2px top offset (§14.5.1)
- [ ] Click opens full photo viewer (§14.5.1)
- [ ] Upload sub-button: small circular overlay at bottom-right, 6px from right edge (§14.5.1)
- [ ] Name: FlatLabel 17px semibold, max height 24px, centered below photo with 7px gap (§14.5.1)
- [ ] Online status: FlatLabel windowSubTextFg, centered below name with -1px spacing (§14.5.1)

#### 14.5.2 Bio Input
- [ ] InputField: transparent bg, multiline, placeholder "Bio" (§14.5.2)
- [ ] Margins: 22px left, 6px top, 22px right, 4px bottom (§14.5.2)
- [ ] Min height: 32px (§14.5.2)
- [ ] Character counter: top-right corner, shows remaining chars (§14.5.2)
- [ ] Counter color: grey when >= 0, red (boxTextFgError) when < 0 (§14.5.2.1)
- [ ] Max length: 70 chars (non-Premium), 140 chars (Premium) (§14.5.2.1)
- [ ] Input accepts up to premiumLimit x 2 chars (negative count rather than truncation) (§14.5.2.1)
- [ ] Auto-save: debounced 1000ms (§14.5.2)
- [ ] Also saves on Enter and widget destruction (§14.5.2)
- [ ] Emoji suggestions enabled, instant replacements follow global settings (§14.5.2)
- [ ] Footer: "Any details such as age, occupation or city." (§14.5.2)

#### 14.5.3 Profile Information Rows
- [ ] Name row: icon menuIconProfile, label "Name", click opens EditNameBox (§14.5.3)
- [ ] Name row: right-click "Copy Full Name" (§14.5.3)
- [ ] Phone row: icon menuIconPhone, label "Phone Number", click copies + toast 500ms (§14.5.3)
- [ ] Phone row: right-click "Copy Phone Number" (§14.5.3)
- [ ] Username row: icon menuIconUsername, label "Username", click opens UsernamesBox (§14.5.3)
- [ ] Username row: right-click "Copy @mention" (§14.5.3)
- [ ] Footer: "People can message you using your username without knowing your phone number." (§14.5.3)
- [ ] Row layout: 60px left icon column, icon at 20px inside 6px rounded square fill (§14.5.3.1)
- [ ] Primary line: value in boxTextStyle 14px (§14.5.3.1)
- [ ] Secondary line: label in defaultFlatLabel with windowSubTextFg (§14.5.3.1)
- [ ] No trailing chevron -- hover ripple covers full width (§14.5.3.1)
- [ ] Copy entry disabled when text contains entities losing meaning on plain-text copy (§14.5.3.1)

#### 14.5.4 Personal Channel & Color
- [ ] Channel row: icon menuIconChannel, "Personal Channel", shows channel name or "Add" (§14.5.4)
- [ ] Your Color button: AddPeerColorButton showing name color swatch (§14.5.4)
- [ ] Color click opens EditPeerColorBox (§14.5.4)

#### 14.5.5 Birthday
- [ ] Birthday row: icon menuIconGiftPremium, "Date of Birth", formatted date or "Add" (§14.5.5)
- [ ] Click opens date picker (§14.5.5)
- [ ] Footer: dynamic text based on birthday privacy, with "[Manage]" link to privacy settings (§14.5.5)

#### 14.5.6 Accounts List
- [ ] All logged-in accounts as SettingsButton rows with small avatar, name, badge (§14.5.6)
- [ ] Max accounts: 10 Premium, 3 free (§14.5.6)
- [ ] Click active account: closes settings (§14.5.6)
- [ ] Click inactive: switches account (§14.5.6)
- [ ] Ctrl+Click: opens in new window (§14.5.6)
- [ ] Right-click context menu: Copy Phone, Mark All Read, Activate, Log Out (red) (§14.5.6)
- [ ] Log Out hidden for active account (§14.5.6.1)
- [ ] Drag-and-drop reorder supported (§14.5.6)
- [ ] Reorder: pinned interval locks slots beyond Premium limit for free users (§14.5.6.1)
- [ ] Add Account button: plus icon with windowBgActive fill, hidden at max (§14.5.6)
- [ ] Ctrl+Click on Add Account: add in new window (§14.5.6)
- [ ] Account row badges: unread (loud/muted), Premium/emoji-status, supporter/verified (§14.5.6.1)
- [ ] Add Account row inside SlideWrap, grays out at premium limit (§14.5.6.1)
- [ ] Userpic ringed by active-account indicator (§14.5.6.1)

### 14.6 Chat Settings
- [ ] Title: "Chat Settings" (§14.6)
- [ ] Top bar overflow: "Create New Theme" (§14.6)

#### 14.6.1 Themes
- [ ] Horizontal row of 4 theme cards: Default, Day, Dark, Night Blue (§14.6.1)
- [ ] Card size: 80x92px (settingsThemePreviewSize) (§14.6.1)
- [ ] Mini chat bubble: 40x14px (settingsThemeBubbleSize) (§14.6.1)
- [ ] Bubble corner radius: 2px (§14.6.1)
- [ ] Bubble anchor: point(6, 8) first bubble top-left (§14.6.1)
- [ ] Radio dot bottom inset: 12px (§14.6.1)
- [ ] Top skip: 10px, bottom skip: 8px (§14.6.1)
- [ ] Cards try 80px width; scale down proportionally if space tight (§14.6.1.1)
- [ ] Selected ring: CloudListCheck with radio duration spring animation (§14.6.1.1)
- [ ] Each card renders miniature bg, two chat bubbles, radio dot, accent color (§14.6.1.1)
- [ ] Accent color palette: row of 24px circular dots (§14.6.1)
- [ ] Rightmost dot: multi-colored custom picker opening HSL ColorEditor (§14.6.1)
- [ ] "Use system accent color" checkbox (Qt6+ only) (§14.6.1)

#### 14.6.2 Theme Settings
- [ ] Your Color: name color preview, opens EditPeerColorBox (§14.6.2)
- [ ] Auto-Night Mode toggle (shown if system reports dark mode preference) (§14.6.2)
- [ ] Font Family: shows current font name, opens ChooseFontBox with chat preview (§14.6.2)

#### 14.6.3 Cloud Themes
- [ ] Horizontal scrollable list of cloud themes in SlideWrap (§14.6.3)
- [ ] "Show All" toggle expands from 2-row grid to full grid (§14.6.3.1)
- [ ] Each entry uses settingsThemePreviewSize card footprint (§14.6.3.1)
- [ ] "Edit Current Theme" button: only when active theme is user-owned cloud theme (§14.6.3.1)
- [ ] Edit launches full theme editor window (§14.6.3.1)
- [ ] "Create New Theme" in top-bar overflow, not inline button (§14.6.3.1)

#### 14.6.4 Chat Background
- [ ] Background preview: 76px square thumbnail with rounded corners (§14.6.4)
- [ ] "Choose from gallery" link (§14.6.4)
- [ ] "Choose from file" link (§14.6.4)
- [ ] "Tile Background" checkbox (non-pattern/non-solid only) (§14.6.4)
- [ ] "Adaptive Layout for Wide Screens" checkbox (wide layout mode only) (§14.6.4)

#### 14.6.5 Chat List Quick Action
- [ ] Radio buttons for left-swipe: Mute, Pin, Read, Archive, Delete, Disabled (§14.6.5)
- [ ] Live preview widget with animated Lottie icon demonstrating chosen action (§14.6.5)

#### 14.6.6 Stickers and Emoji
- [ ] Checkboxes in order: Large Emoji, Replace Emojis, Suggest Emoji, Suggest Stickers by Emoji, Loop Animated Stickers (§14.6.6)
- [ ] Suggest Animated Emoji nested row (Premium only) (§14.6.6.1)
- [ ] Your Stickers button: opens StickersBox, icon menuIconStickers (§14.6.6.1)
- [ ] Emoji Sets button: opens ManageSetsBox, icon menuIconEmoji (§14.6.6.1)
- [ ] Checkbox padding: margins(22, 10, 10, 10) (§14.6.6.1)

#### 14.6.7 Messages
- [ ] Send by: Radio -- Enter or Ctrl+Enter (Cmd+Enter on Mac) (§14.6.7)
- [ ] Radio padding: margins(22, 5, 10, 5) (§14.6.7.1)
- [ ] Double-click action: Radio -- Reply or React (§14.6.7)
- [ ] React option: inline animated preview of current favorite reaction (§14.6.7.1)
- [ ] Show reply button in corner checkbox (§14.6.7)
- [ ] Show reaction button in corner checkbox (§14.6.7)
- [ ] Subsection title + skip between Send by and Double-click groups (§14.6.7.1)
- [ ] Divider + skip between radio groups and corner checkboxes (§14.6.7.1)

#### 14.6.8 Sensitive Content
- [ ] Toggle "Disable filtering" with footer about sensitive media (§14.6.8)
- [ ] Hidden if server disallows changing (§14.6.8)

#### 14.6.9 Shortcuts & Archive
- [ ] Keyboard Shortcuts: navigates to Shortcuts section (§14.6.9)
- [ ] Archive Settings: opens ArchiveSettingsBox (§14.6.9)

### 14.7 Advanced Section

#### 14.7.0 Build Order
- [ ] Software Update (top position when non-auto-updating) (§14.7.0)
- [ ] Data and Storage (§14.7.0)
- [ ] Automatic Media Download (§14.7.0)
- [ ] Window Title (§14.7.0)
- [ ] Window Close Behavior (Linux only) (§14.7.0)
- [ ] System Integration (§14.7.0)
- [ ] Performance (§14.7.0)
- [ ] Spellchecker (§14.7.0)
- [ ] Screen Reader (§14.7.0)
- [ ] Software Update (bottom position when auto-updating) (§14.7.0)
- [ ] Export Data (§14.7.0)
- [ ] Each section separated by skip + divider + skip (§14.7.0)
- [ ] Conditional subsections use SlideWrap for animate in/out (§14.7.0)

#### 14.7.1 Data and Storage
- [ ] Connection Type button (with proxy info) (§14.7.1)
- [ ] Download Path button (§14.7.1)
- [ ] Local Storage button (§14.7.1)
- [ ] Downloads button (§14.7.1)
- [ ] "Ask download path" toggle (§14.7.1)

#### 14.7.2 Automatic Media Download
- [ ] In Private Chats button -> AutoDownloadBox (§14.7.2)
- [ ] In Groups button -> AutoDownloadBox (§14.7.2)
- [ ] In Channels button -> AutoDownloadBox (§14.7.2)

#### 14.7.3 Window Title
- [ ] "Show chat name" checkbox (always visible) (§14.7.3)
- [ ] "Show account name" checkbox (SlideWrap, multi-account only) (§14.7.3)
- [ ] "Show unread count" checkbox (§14.7.3)
- [ ] Native/Qt frame toggle (SlideWrap, platform-gated) (§14.7.3)

#### 14.7.4 Window Close Behavior (Linux only)
- [ ] Radio: Run in Background (§14.7.4)
- [ ] Radio: Close to Taskbar (§14.7.4)
- [ ] Radio: Quit (§14.7.4)

#### 14.7.5 System Integration
- [ ] "Show tray icon" checkbox (§14.7.5)
- [ ] "Show taskbar icon" checkbox (at least one required, toast on block) (§14.7.5)
- [ ] "Monochrome tray icon" checkbox (slide-wrapped, tray+monochrome supported) (§14.7.5)
- [ ] "Launch at startup" checkbox (slide-wrapped, platform-gated) (§14.7.5)
- [ ] "Start minimized" checkbox (nested SlideWrap, gated on autostart ON) (§14.7.5)
- [ ] "Add to Send To menu" checkbox (Windows only) (§14.7.5)

#### 14.7.6 Performance
- [ ] Power Saving button -> PowerSavingBox (§14.7.6)
- [ ] Hardware-accelerated video toggle (slide-wrapped, platform-gated) (§14.7.6)
- [ ] OpenGL/ANGLE toggle (restart dialog on change) (§14.7.6)

#### 14.7.7 Spellchecker
- [ ] System/Custom spellchecker toggle (§14.7.7)
- [ ] Auto-download dictionaries toggle (§14.7.7)
- [ ] Manage dictionaries button with installed count (§14.7.7)

#### 14.7.8 Software Update
- [ ] Auto-update toggle with version/progress label (§14.7.8)
- [ ] Install beta versions toggle (§14.7.8)
- [ ] Check for updates / "Update Telegram" button (§14.7.8)

### 14.8 Premium & Help Sections

#### Premium Section
- [ ] Telegram Premium: gradient-backed button style, star glyph (§14.8.1)
- [ ] Telegram Stars: with live-updating balance label (§14.8.1)
- [ ] TON Currency: icon menuIconTon, hidden when balance empty (§14.8.1)
- [ ] Telegram Business: icon menuIconShop (§14.8.1)
- [ ] Send a Gift: conditional, newBadge indicator until interacted (§14.8.1)

#### Help Section
- [ ] Telegram FAQ: opens external browser (§14.8.2)
- [ ] Telegram Features: opens features channel link (§14.8.2)
- [ ] Ask a Question: confirmation dialog before contacting support (§14.8.2)
- [ ] All three Help rows: settingsButton style with 60px icon column (§14.8.2)
- [ ] About-label below Premium group: left inset 59px (§14.8.2)

### 14.9 Visual Style Constants
- [ ] settingsButton.padding: margins(60, 10, 22, 10) (§14.9)
- [ ] settingsButton.iconLeft: 20px (§14.9)
- [ ] settingsButtonNoIcon.padding: margins(22, 10, 22, 8) (§14.9)
- [ ] settingsIconRadius: 6px (§14.9)
- [ ] settingsInfoPhotoSize: 100px (§14.9)
- [ ] settingsInfoPhotoHeight: 162px (§14.9)
- [ ] settingsAccentColorSize: 24px (§14.9)
- [ ] settingsBackgroundThumb: 76px (§14.9)
- [ ] settingsThemePreviewSize: 80x92px (§14.9)
- [ ] settingsThemeBubbleSize: 40x14px (§14.9)
- [ ] settingsCheckboxPadding: margins(22, 10, 10, 10) (§14.9)
- [ ] settingsSendTypePadding: margins(22, 5, 10, 5) (§14.9)
- [ ] settingsBioMargins: margins(22, 6, 22, 4) (§14.9)
- [ ] settingsCoverName.font: 17px semibold (§14.9)

### 14.10 Animations and Transitions
- [ ] Section navigation: horizontal slide + fade from right (§14.10)
- [ ] Toggle switches: pill-shaped toggle, knob slides with default animation duration (§14.10)
- [ ] Color dot selection: selected ring animates over defaultRadio.duration x 2 (§14.10)
- [ ] Scale preview: floating tooltip during slider manipulation (§14.10)
- [ ] Account list reorder: drag-and-drop with spring physics (§14.10)
- [ ] SlideWrap sections: smooth height animation or instant show/hide (§14.10)
- [ ] Ripple on all SettingsButton instances (§14.10)
- [ ] Theme card radio: standard radio check animation (§14.10)

# GUI Implementation Checklist: Sections 15-22

---

## 15. Settings -- Notifications

### 15.1 Multi-Account Notifications
- [ ] Conditionally show section only when 2+ accounts logged in (§15.1)
- [ ] Section title "Show notifications from" -- 14px semibold, `windowActiveTextFg` (§15.1)
- [ ] "All accounts" toggle with `settingsButtonNoIcon` style (§15.1)
- [ ] Default toggle state: ON (§15.1)
- [ ] On toggle OFF: clear notifications from all non-active accounts (§15.1)
- [ ] Divider text explanation below toggle (§15.1)

### 15.2 Global Settings
- [ ] Section title "Global settings" (§15.2)
- [ ] "Desktop notifications" toggle -- `menuIconNotifications` icon, default ON (§15.2)
- [ ] Platform-specific flash/bounce toggle -- `menuIconDockBounce` icon, default ON (§15.2)
- [ ] Flash/bounce label varies by platform: Windows/macOS/Linux variants (§15.2)
- [ ] "Allow sound" toggle -- `menuIconUnmute` icon, default ON (§15.2)
- [ ] All three toggles use `settingsButton` style with 60px left padding (§15.2)

### 15.2.1 Global Master-Volume Slider
- [ ] Volume slider in `SlideWrap`, visible when sound enabled (§15.2.1)
- [ ] ~150ms slide animation on show/hide (§15.2.1)
- [ ] Subtitle "Volume" above slider -- 14px semibold `windowActiveTextFg` (§15.2.1)
- [ ] Horizontal `MediaSlider` with trailing percentage label (§15.2.1)
- [ ] 15x15px seek thumb (§15.2.1)
- [ ] 100 discrete steps, values 1-100 (no zero) (§15.2.1)
- [ ] Label format: plain number + "%" (e.g. "100%") in `windowActiveTextFg` (§15.2.1)
- [ ] Label updates live on drag (§15.2.1)
- [ ] Plays notification sound preview on drag (§15.2.1)
- [ ] Default value: 100 (§15.2.1)
- [ ] Slider padding: 21px left/right, 7px top, 4px bottom (§15.2.1)
- [ ] Debounced persistence (not per-step) (§15.2.1)

### 15.3 Notification Preview
- [ ] Preview in `SlideWrap`, shown when desktop notifications ON (§15.3)
- [ ] Plain divider when desktop notifications OFF (§15.3)
- [ ] Preview bubble: chat-themed rectangle on wallpaper, `boxRadius` corners, `msgInBg` fill (§15.3)
- [ ] Userpic 36x36px at (14,11) -- dinosaur SVG when "Name" checked, app logo when unchecked (§15.3)
- [ ] Title at (64,9) -- "Dino Rex" when "Name" checked, app name when unchecked (§15.3)
- [ ] Text at (64,30) -- sample text when "Text" checked, generic "You have a new message" when unchecked (§15.3)
- [ ] Bubble margins: 40/20/40/58px (§15.3)
- [ ] Two overlay checkboxes centered horizontally, 12px apart (§15.3)
- [ ] `ChatServiceCheckbox` style (rounded pill, service-message background, white text) (§15.3)
- [ ] Unchecking "Name" auto-unchecks "Text" (§15.3)
- [ ] Checking "Text" auto-checks "Name" (§15.3)
- [ ] Three states: ShowPreview, ShowName, ShowNothing (§15.3)

### 15.4 Notifications for Chats
- [ ] Section title "Notifications for chats" (§15.4)
- [ ] Four split-toggle rows: Private chats, Groups, Channels, Reactions (§15.4)
- [ ] Each row: 40px height, 60px left padding (`settingsNotificationType` style) (§15.4)
- [ ] Left portion clickable -> sub-page, with icon + label + status subtitle (§15.4)
- [ ] Right toggle area 70px wide (§15.4)
- [ ] 1px vertical separator between label area and toggle (§15.4.1)
- [ ] Separator height: row height minus 2*toggle border, centered vertically (§15.4.1)
- [ ] Separator color: `textBgOver` of `settingsNotificationType` (§15.4.1)
- [ ] No horizontal dividers between rows (§15.4.1)
- [ ] Status subtitle: "Click here to change" or "On/Off, N exception(s)" (§15.4)
- [ ] Confirmation dialog when toggling with exceptions (§15.4)
- [ ] Icons: `menuIconProfile`, `menuIconGroups`, `menuIconChannel`, `menuIconGroupReactions` (§15.4)

### 15.5 Per-Type Sub-Page
- [ ] "Enable notifications" toggle with `menuIconNotifications`, right-click opens Mute Menu (§15.5.1)
- [ ] "Sound" toggle in `SlideWrap`, visible when notifications enabled (§15.5.1)
- [ ] "Notification tone" row in nested `SlideWrap`, visible when sound enabled (§15.5.1)
- [ ] Tone row: `menuIconSoundOn` icon, right label shows current tone name (§15.5.1.1)
- [ ] Default tone right label: "Default" (§15.5.1.1)
- [ ] Right label updates reactively on tone changes (§15.5.1.1)
- [ ] Click opens Ringtones Box (§15.5.1.1)
- [ ] Per-type volume slider: same widget as global, 1-100% (§15.5.1.2)
- [ ] Per-type slider plays selected tone (not global default) on drag (§15.5.1.2)
- [ ] Slider visibility: both Enable and Sound must be ON (§15.5.1.2)

### 15.5.2 Exceptions List
- [ ] "Add an exception" button -- `settingsButtonActive`, `menuIconInviteSettings` (§15.5.2)
- [ ] Exception rows: userpic + name, "Muted"/"Unmuted" status, "Remove" link on right (§15.5.2)
- [ ] Click on exception row opens context menu (view profile + mute options) (§15.5.2)
- [ ] "Delete all exceptions" button -- red attention style, shown when >1 exception (§15.5.2)
- [ ] Confirmation dialog for delete all (§15.5.2)

### 15.5.3 Mute Menu
- [ ] `PopupMenu` with `popupMenuWithIcons` style (§15.5.3)
- [ ] "Select tone" -> Ringtones Box (§15.5.3)
- [ ] "Disable/Enable sound" toggle (§15.5.3)
- [ ] Recent mute durations (0-2 items) with compact labels (§15.5.3)
- [ ] "Mute for..." -> duration picker (§15.5.3)
- [ ] "Mute forever" / "Unmute" -- animated red/green color transition (§15.5.3)
- [ ] Mute Duration Picker: drum-picker wheel (§15.5.3)
- [ ] Duration values: 15min to 1mo (§15.5.3)
- [ ] "Custom" option with arbitrary precision from top-right menu (§15.5.3)

### 15.6 Ringtones Box
- [ ] `GenericBox`, 364px wide, titled "Notification Sound" (§15.6)
- [ ] Subsection title "Cloud" -- 14px semibold (§15.6.1)
- [ ] "Default" radio (plays default sound on select) (§15.6.1)
- [ ] "No sound" radio (silent, hides volume slider when selected) (§15.6.1)
- [ ] Custom tones radio list (filename without extension) (§15.6.1)
- [ ] Play sound on selecting custom radio (if document loaded) (§15.6.1)
- [ ] Right-click on custom tone -> popup with "Delete" action (§15.6.1)
- [ ] "Upload Sound" button -- `ringtonesBoxButton` style, `settingsIconAdd` icon (§15.6.1)
- [ ] File dialog filtered to `*.mp3` (§15.6.1)
- [ ] Upload constraints: max 100KB, max 5 seconds, max 100 cloud ringtones (§15.6.1)
- [ ] Upload error handling: duration too long, size too big, invalid MIME (§15.6.1)
- [ ] In-box volume slider (conditional), hidden for "No sound" (§15.6.1)
- [ ] 7px skip after slider (§15.6.1)
- [ ] Footer text about saving from voice notes (§15.6.1)
- [ ] 7px skip after footer (§15.6.1)
- [ ] "Save" and "Cancel" buttons (§15.6.1)
- [ ] No spinner during load -- renders whatever list is cached (§15.6.1)
- [ ] Audio device attach on box open, 250ms detach delay on close (§15.6.1)

### 15.7 Reactions Sub-Page
- [ ] Title: "Notifications for reactions" (§15.7)
- [ ] Two split-toggle rows: "Reactions to my messages", "Votes in my polls" (§15.7.1)
- [ ] Icons: `menuIconMarkUnread`, `menuIconCreatePoll` (§15.7.1)
- [ ] Left click (when enabled) -> dialog with "From everyone"/"From my contacts" radio (§15.7.1)
- [ ] "Show sender's name" toggle (§15.7.2)

### 15.8 Events
- [ ] "Contact joined Telegram" toggle -- `menuIconInvite`, default ON (§15.8)
- [ ] "Pinned messages" toggle -- `menuIconPin`, default ON (§15.8)

### 15.9 Calls
- [ ] "Accept calls on this device" toggle -- `menuIconCallsReceive` (§15.9)

### 15.10 Badge Counter
- [ ] "Include muted chats in unread count" toggle, default ON (§15.10)
- [ ] "Include muted chats in folder counters" toggle, shown if folders exist (§15.10)
- [ ] "Count unread messages" toggle (ON = message count, OFF = chat count) (§15.10)
- [ ] All toggles use `settingsButtonNoIcon` style (§15.10)

### 15.11 System Integration (Native Notifications)
- [ ] Hidden if platform doesn't support or enforces native notifications (§15.11)
- [ ] "Use native notifications" toggle (§15.11)
- [ ] Toggle recreates notification backend (§15.11)

### 15.11.1 Windows Focus Mode
- [ ] "Respect system Focus mode" toggle -- Windows only (§15.11.1)
- [ ] `settingsButtonNoIcon` style (§15.11.1.1)

### 15.11.2 Multi-Display Selector
- [ ] Shown when multiple monitors detected (§15.11.2)
- [ ] Radio group: "Default" + one per display with name and resolution (§15.11.2)
- [ ] `settingsSendType` style with `settingsSendTypePadding` (§15.11.2.1)
- [ ] Selection persisted by screen name checksum (§15.11.2.1)

### 15.11.3 Notification Position (Monitor Widget)
- [ ] Interactive monitor widget: 280x160px screen area (§15.11.3)
- [ ] `notificationsBoxScreenBg` fill (§15.11.3)
- [ ] Monitor frame icon centered horizontally (§15.11.3.1)
- [ ] Five clickable corners: TopLeft, TopCenter, TopRight, BottomRight, BottomLeft (§15.11.3)
- [ ] Sample notification bars: 64x16px (§15.11.3)
- [ ] Selected corner: up to 5 bars at full opacity (§15.11.3.1)
- [ ] Non-selected corners: 1 bar at 0.5 opacity (§15.11.3.1)
- [ ] Per-bar fade animation: 150ms (§15.11.3.1)
- [ ] 3x3 hit-test grid for corner detection (§15.11.3.1)
- [ ] Cursor changes to pointer on corner hover (§15.11.3.1)
- [ ] Hover spawns desktop sample notification windows at corner (§15.11.3)
- [ ] Sample windows: 320x80px, userpic 62px, app logo, title, text, close button (§15.11.3)
- [ ] Sample windows positioned at real desktop coordinates (§15.11.3.1)
- [ ] Click selects corner, default: BottomRight (§15.11.3)
- [ ] Leave event hides all sample windows (§15.11.3.1)

### 15.11.4 Notification Count
- [ ] Segmented slider with 5 positions labeled "1" through "5" (§15.11.4)
- [ ] `settingsSlider` style (§15.11.4.1)
- [ ] Default: 3 (§15.11.4.1)
- [ ] Selecting animates sample bars in monitor widget (150ms per bar) (§15.11.4.1)

### 15.12 Animations
- [ ] SlideWrap: ~300ms height animation (§15.12)
- [ ] Toggle switches: sliding pill with `anim::type::normal` (§15.12)
- [ ] Sample notification bars: independent 150ms fade per bar (§15.12)
- [ ] Desktop sample windows: 150ms fade in/out (§15.12)
- [ ] Mute menu color: red/green transition (§15.12)

---

## 16. Settings -- Privacy & Security

### 16.1 Navigation
- [ ] "Privacy and Security" row in Settings list (§16.1)
- [ ] Icon: `menuIconLock`, label: "Privacy and Security" (§16.1)
- [ ] `settingsButton` style (padding 60/10/22/10) (§16.1)
- [ ] Scrollable `VerticalLayout` section (§16.1)
- [ ] 60-second polling timer for data refresh (§16.1)
- [ ] Build seven subsections in order (§16.1)

### 16.2 Security Section
- [ ] 14px vertical skip, subsection title "Security" (§16.2)

### 16.2.1 Two-Step Verification
- [ ] Button "Two-Step Verification" -- `menuIcon2SV` icon (§16.2.1)
- [ ] Right label: "Loading..." / "On" / "Off" (dynamic) (§16.2.1)
- [ ] Loading state: click does nothing (§16.2.1)
- [ ] On state -> CloudPasswordInput screen (§16.2.1)
- [ ] CloudPasswordInput: Lottie `cloud_password/password_input` 100x100px (§16.2.1)
- [ ] Title "Enter your password", description label (§16.2.1)
- [ ] Single password input field with placeholder (§16.2.1)
- [ ] Hint shown as `lng_signin_hint` below field (hidden when error visible) (§16.2.1)
- [ ] "Forgot password?" link button below input (§16.2.1)
- [ ] Forgot password: recovery email flow vs no-email reset flow (§16.2.1)
- [ ] Reset countdown label and "Cancel Reset" link (§16.2.1)
- [ ] "Check" button, wrong password error `lng_cloud_password_wrong` (§16.2.1)
- [ ] Off state -> CloudPasswordStart intro screen (§16.2.1)
- [ ] CloudPasswordStart: Lottie `cloud_password/intro` 100x100px, padding (0,19,0,5) (§16.2.1)
- [ ] "Set Password" button navigating to create flow (§16.2.1)
- [ ] Create flow: two password fields, hint step, email setup step (§16.2.1)
- [ ] Unconfirmed state -> email confirmation screen (§16.2.1)
- [ ] PasscodeBox field metrics: boxWidth, padding, inter-field spacing (§16.2.1.1)
- [ ] Error ring/red outline on wrong password or mismatch (§16.2.1.1)
- [ ] Recovery email field with "Skip" link and warning dialog (§16.2.1.1)

### 16.2.2 Auto-Delete Messages (Global TTL)
- [ ] Button "Auto-Delete Messages" -- `menuIconTTL` icon (§16.2.2)
- [ ] Right label: formatted TTL or "Off" (§16.2.2)
- [ ] GlobalTTL section with Lottie `ttl` 100x100px (loops) in `BoxContentDivider` (§16.2.2)
- [ ] Subsection title (§16.2.2)
- [ ] Radio buttons: Off, 1 day, 7 days, 31 days (§16.2.2)
- [ ] Custom values inserted and sorted into list (§16.2.2)
- [ ] Radio rows: `settingsButtonNoIcon` with overlaid `Radiobutton` (§16.2.2.1)
- [ ] Confirmation dialog when selecting non-zero from zero (§16.2.2)
- [ ] "Set Custom Period" button (§16.2.2)
- [ ] Footer with clickable link to apply TTL to existing chats (§16.2.2)

### 16.2.3 Passcode Lock
- [ ] Button "Passcode Lock" -- `menuIconLock` icon (§16.2.3)
- [ ] Right label: "On" / "Off" (§16.2.3)
- [ ] No passcode -> LocalPasscodeCreate screen (§16.2.3)
- [ ] Lottie `local_passcode_enter`, animates once on show (§16.2.3)
- [ ] Two password fields, width 256px (`settingLocalPasscodeInputField`) (§16.2.3)
- [ ] Error label on mismatch: `lng_passcode_differ` (§16.2.3)
- [ ] "Create" button -> navigates to LocalPasscodeManage (§16.2.3)
- [ ] Passcode set -> LocalPasscodeCheck screen (§16.2.3)
- [ ] Single password field, "Next" button, wrong passcode error (§16.2.3)
- [ ] LocalPasscodeManage: "Change Passcode" (`menuIconLock`) (§16.2.3)
- [ ] "Auto-Lock" button (`menuIconTimer`) with right label showing duration (§16.2.3)
- [ ] AutoLockBox: radios 1min/5min/1h/5h + custom HH:MM input (§16.2.3)
- [ ] AutoLockBox metrics: `autolockWidth`, preset timeouts, custom `TimeInput` (§16.2.3.1)
- [ ] System Unlock toggle (platform-specific) (§16.2.3)
- [ ] "Turn Off Passcode" button (red attention style) with confirmation (§16.2.3)

### 16.2.4 Passkeys
- [ ] Shown only if platform supports WebAuthn or user has passkeys (§16.2.4)
- [ ] Button "Passkeys" -- `menuIconPermissions` icon (§16.2.4)
- [ ] Right label: passkey name/count/"Off" (§16.2.4)

### 16.2.5 Login Email
- [ ] Shown only if login email configured (§16.2.5)
- [ ] Button with `menuIconRecoveryEmail` icon (§16.2.5)
- [ ] Right label: masked email pattern (§16.2.5)

### 16.2.6 Blocked Users
- [ ] Button "Blocked Users" -- `menuIconBlock` icon (§16.2.6)
- [ ] Right label: blocked count or "None" (§16.2.6)
- [ ] Empty state: Lottie `blocked_peers_empty`, title, description, min height 240px (§16.2.6.1)
- [ ] "Block user" button: `settingsButtonActive` with `menuIconBlockSettings` (§16.2.6.1)

### 16.2.7 Active Sessions
- [ ] Button "Active Sessions" -- `menuIconDevices` icon (§16.2.7)
- [ ] Right label: session count (§16.2.7)
- [ ] Current device: 70px userpic with 52px lottie (§16.2.7)
- [ ] Per-device rows: 84px height, 42px photo (§16.2.7)
- [ ] Platform-specific icons (Windows, Mac, Ubuntu, Linux, iPhone, iPad, Android, browsers) (§16.2.7)
- [ ] Close button per session: 34x34px (§16.2.7)
- [ ] "Terminate All Other Sessions" button (§16.2.7)
- [ ] Auto-terminate inactive sessions timer (§16.2.7)

### 16.3 Privacy Section
- [ ] Subsection title "Privacy" (§16.3)
- [ ] Each privacy setting: `settingsButtonNoIcon` (padding 22/10/22/8) (§16.3)
- [ ] Right label format: base value + exception counts (+N, -N) (§16.3)
- [ ] Click opens `EditPrivacyBox` -- 364px wide (§16.3)
- [ ] Radio options: Everyone / My Contacts / Close Friends / Nobody (§16.3)
- [ ] Premium-locked options: 14px lock icon (§16.3)
- [ ] Warning/description label in `DividerLabel` (§16.3)
- [ ] "Always Allow" and "Never Allow" exception buttons (§16.3)
- [ ] Exception buttons open `PeerListBox` with checkable rows (§16.3)
- [ ] Premium Users toggle in exceptions where applicable (§16.3)
- [ ] "Save" + "Cancel" buttons (§16.3)
- [ ] EditPrivacyBox shared internals: option row padding, radio-row top pad, exception link style (§16.3.0)

### 16.3.1 Phone Number Privacy
- [ ] Options: Everyone / My Contacts / Nobody (§16.3.1)
- [ ] "Nobody" -> sub-section "Who can find me by my number?" with Everyone/Contacts radios (§16.3.1)
- [ ] Phone-based link warning when not set to Nobody (§16.3.1)

### 16.3.2 Last Seen & Online
- [ ] Options: Everyone / My Contacts / Nobody (§16.3.2)
- [ ] First-time restriction confirmation dialog (§16.3.2)
- [ ] "Hide Read Time" toggle below (when not Everyone) (§16.3.2)
- [ ] Non-Premium: "Subscribe to Telegram Premium" button (§16.3.2)

### 16.3.3 Profile Photo
- [ ] Options: Everyone / My Contacts / Nobody (§16.3.3)
- [ ] "Set Public Photo" / "Update Public Photo" button (opens photo editor with ellipse crop) (§16.3.3)
- [ ] "Remove Public Photo" button (red attention style, when public photo exists) (§16.3.3)

### 16.3.4 Forwarded Messages
- [ ] Options: Everyone / My Contacts / Nobody (§16.3.4)
- [ ] Above widget: live forwarded message preview bubble (§16.3.4)
- [ ] Preview matches user's theme, bubble color, fonts (§16.3.4.1)
- [ ] "Forwarded from" header with current user's name (§16.3.4.1)
- [ ] Tooltip changes based on selected option (§16.3.4)
- [ ] Tooltip: `toastBg` background, `toastFg` text, 7px arrow (§16.3.4)

### 16.3.5 Calls Privacy
- [ ] Options: Everyone / My Contacts / Nobody (§16.3.5)
- [ ] Peer-to-Peer sub-section with `menuIconNetwork` icon (§16.3.5)
- [ ] P2P opens second `EditPrivacyBox` for P2P settings (§16.3.5)

### 16.3.6 Voice Messages
- [ ] Options: Everyone / My Contacts / Nobody (§16.3.6)
- [ ] Non-Premium: lock icons on restricted options (§16.3.6)
- [ ] Selecting restricted option reverts to Everyone with Premium promo toast (§16.3.6)

### 16.3.7 Messages from Non-Contacts
- [ ] Three radio options: Everyone / Contacts & Premium / Charge Stars (§16.3.7)
- [ ] "Charge Stars" reveals star price slider (§16.3.7)
- [ ] Slider: 1 to max, step scheme: 1-step for 1-99, 10-step for 100-999, 100-step for 1000+ (§16.3.7.1)
- [ ] Star preview label above thumb ("star + count") (§16.3.7.1)
- [ ] Commission/USD info below slider (updates live on drag) (§16.3.7.1)
- [ ] "Remove fee for" exceptions button (§16.3.7.1)

### 16.3.8 Birthday Privacy
- [ ] Standard three-option privacy (§16.3.8)
- [ ] Above widget: "set your birthday" link if not yet set (§16.3.8)

### 16.3.9 Gifts (Auto-Save)
- [ ] "Show Icon" toggle above radio options (Premium-locked) (§16.3.9)
- [ ] "Accepted Types" subsection below with five toggles (§16.3.9)
- [ ] Toggles: Limited, Unlimited, Unique, From Channels, Premium (§16.3.9.1)
- [ ] All six toggles are Premium-locked (14px padlock for non-Premium) (§16.3.9.1)

### 16.3.10-12 Bio, Saved Music, Groups & Channels
- [ ] Bio: standard three-option privacy, no special widgets (§16.3.10)
- [ ] Saved Music: standard three-option privacy, no special widgets (§16.3.11)
- [ ] Groups & Channels: standard three-option with Premiums toggle in Always Allow (§16.3.12)

### 16.4 Archive and Mute Section
- [ ] Conditionally shown (Premium or `showArchiveAndMute`) (§16.4)
- [ ] "Archive and Mute" toggle (§16.4)

### 16.5 Bots and Websites
- [ ] "Clear Payment and Shipping Info" button (§16.5)
- [ ] ClearPaymentInfoBox: two checkboxes (Shipping Info, Payment Info), both default-checked (§16.5.1)
- [ ] `defaultBoxCheckbox` style (§16.5.1)
- [ ] "Clear" button in `attentionBoxButton` style (red) (§16.5.1)
- [ ] Button disabled (grey) when both unchecked (§16.5.1)

### 16.6 File Confirmations Section
- [ ] Conditionally shown (has no-warning extensions or disabled IP reveal) (§16.6)
- [ ] Multi-line input for file extensions (space-separated) (§16.6.1)
- [ ] Max 10240 chars, max 1024 entries (§16.6.1)
- [ ] "Show IP in WebRTC calls" toggle (§16.6)

### 16.7 Suggest Frequent Contacts
- [ ] "Suggest Frequent Contacts" toggle (§16.7)

### 16.8 Self-Destruction (Account Auto-Delete)
- [ ] "If away for..." button with right label (§16.8)
- [ ] SelfDestructionBox: radios for 1/3/6/12/18/24 months (§16.8)
- [ ] Box width: `boxWidth` (§16.8.1)
- [ ] Info label above radios explaining consequence (§16.8.1)
- [ ] Radio style: `autolockButton`, option spacing: `boxOptionListSkip` (§16.8.1)
- [ ] "Save" (blue) + "Cancel" buttons (§16.8.1)

### 16.9 Blocked Users Screen
- [ ] "Block User" button (top, active style) opens peer picker (§16.9)
- [ ] Already-blocked peers shown as disabled in picker (§16.9)
- [ ] Blocked peer list: photo, name, status, "Unblock" link (§16.9)
- [ ] Empty state: Lottie animation, title, description, min 240px height (§16.9)

### 16.11 Animations
- [ ] SlideWrap for conditional sections (§16.11)
- [ ] Lottie icons: cloud password intro/input, local passcode, TTL, blocked users empty (§16.11)
- [ ] Password input icon animates on typing, reverses on clear (§16.11)
- [ ] Fireworks on successful password validation (§16.11)
- [ ] Exception count updates: reactive, no animation (§16.11)

---

## 17. Settings -- Data, Storage & Advanced

### 17.1 Navigation
- [ ] "Data and Storage" row -- `menuIconManage` icon (§17.1)
- [ ] Build subsections in order: Update, Data/Storage, Auto-Download, Window Title, Close Behavior, System Integration, Performance, Spellchecker, Screen Reader, Update, Export (§17.1)

### 17.2 Data and Storage
- [ ] Subsection title "Data and Storage" (§17.2)

### 17.2.1 Connection Type
- [ ] Button "Connection type" -- `menuIconNetwork` icon (§17.2.1)
- [ ] Dynamic right label: "Using TCP" / "Connecting..." / proxy status (§17.2.1)
- [ ] ProxiesBox: 364px wide (§17.2.1)
- [ ] "Try connecting through IPv6" checkbox (padding 22/8/22/5) (§17.2.1)
- [ ] Radio group: Disabled / Use system settings / Use custom proxy (§17.2.1)
- [ ] "Use proxy for calls" checkbox in SlideWrap (§17.2.1.1)
- [ ] Divider text about proxy usage (§17.2.1)
- [ ] Share-list button (visible when shareable entries exist) (§17.2.1.1)
- [ ] Top-right menu: "Import from clipboard" and "Delete all" (§17.2.1.1)
- [ ] Bottom "Add" button (§17.2.1.1)
- [ ] ProxyRow: radio circle with `easeOutCirc` selection animation (§17.2.1.2)
- [ ] ProxyRow title: "SOCKS5/HTTP/MTPROTO host:port" in semibold (§17.2.1.2)
- [ ] ProxyRow status: Online (blue), Available (green+ping), Checking/Connecting (gray+spinner), Unavailable (red) (§17.2.1.3)
- [ ] Context menu: Edit, Share, QR Code, Delete/Restore (§17.2.1.4)
- [ ] Keyboard: Ctrl+C copies all, Ctrl+V pastes proxy URLs (§17.2.1.4)
- [ ] Edit Proxy Dialog: 364px, type radio, host+port inputs (160px+55px), credentials (§17.2.1)
- [ ] Smart paste splits "host:port" (§17.2.1)
- [ ] MTPROTO shows sponsor warning (§17.2.1)
- [ ] Proxy list empty state label (§17.2.1.1)

### 17.2.2 Download Path
- [ ] Button "Download path" -- `menuIconShowInFolder` icon (§17.2.2)
- [ ] Right label: "Default folder" / "Temp folder" / custom path (§17.2.2)
- [ ] Hidden when "Always ask" checked (§17.2.2)

### 17.2.3 Manage Local Storage
- [ ] LocalStorageBox: 320px wide (§17.2.3)
- [ ] Summary row: 50px height, "All data" + size + "Clear All" button (§17.2.3)
- [ ] Total cache size slider: 18 positions (200MB-10GB) (§17.2.3)
- [ ] Media cache size slider: 18 positions (100MB-9GB), linked to total (§17.2.3)
- [ ] Time limit slider: 16 positions (1 week to "Forever") (§17.2.3)
- [ ] Per-tag rows: Images, Stickers, Voice, Video messages, Animations, Media cache (§17.2.3.2)
- [ ] Each tag row: title, size, individual "Clear" button (hidden when count=0) (§17.2.3.2)
- [ ] OK button at bottom (§17.2.3.2)

### 17.2.4-5 Recent Downloads & Always Ask
- [ ] "Recent Downloads" button -- `menuIconDownload` icon (§17.2.4)
- [ ] "Always ask download path" toggle, `settingsButtonNoIcon` (§17.2.5)
- [ ] When ON: hides download path button (§17.2.5)

### 17.3 Automatic Media Download
- [ ] Three buttons: "In private chats", "In groups", "In channels" (§17.3)
- [ ] Icons: `menuIconProfile`, `menuIconGroups`, `menuIconChannel` (§17.3)
- [ ] AutoDownloadBox: `boxWidth` wide (§17.3.1)
- [ ] Download section: Photos/Files toggles + size limit slider (default 10MB) (§17.3.1)
- [ ] Auto-play section: Video messages/Videos/GIFs toggles + size limit slider (default 50MB) (§17.3.1)
- [ ] Size limit label showing "N MB" (§17.3.1)

### 17.4 Window Title Content
- [ ] "Chat name" checkbox (§17.4)
- [ ] "Account name" checkbox in `SlideWrap` (visible when 2+ accounts) (§17.4)
- [ ] "Total count" checkbox (§17.4)
- [ ] All use `settingsCheckbox` style with `settingsCheckboxPadding` (§17.4)

### 17.5 Window Close Behavior (Linux Only)
- [ ] Linux/BSD only (compiled out on Windows/macOS) (§17.5)
- [ ] Three radio options: Run in Background, Close to Taskbar, Quit (§17.5)
- [ ] `settingsSendType` style with `settingsSendTypePadding` (§17.5)
- [ ] Hidden when tray icon unavailable (§17.5)

### 17.6 System Integration
- [ ] "Show tray icon" checkbox -- interlocked with taskbar (§17.6)
- [ ] "Show taskbar icon" checkbox -- interlocked with tray (§17.6.1)
- [ ] Both OFF rejected (at least one required) (§17.6.1)
- [ ] "Monochrome tray icon" checkbox -- slide-animated, visible when tray enabled (§17.6.2)
- [ ] "Launch at startup" checkbox (§17.6.3)
- [ ] "Start minimized" checkbox (visible when autostart ON, forced off when passcode set) (§17.6.3)
- [ ] "Add to Send to menu" -- Windows only (§17.6)
- [ ] macOS-specific: Warn before quit, System text replacements, Round dock icon (§17.6)
- [ ] Windows native notifications toggle (§17.6.4)

### 17.7 Performance

### 17.7.1 Power Saving
- [ ] Button opens PowerSavingBox (364px) (§17.7.1)
- [ ] 11 toggle flags in groups (§17.7.1)
- [ ] Top shadow: 1px (§17.7.1.1)
- [ ] Subtitle with padding `powerSavingSubtitlePadding` (§17.7.1.1)
- [ ] Toggle rows: `powerSavingButton` style (§17.7.1.1)
- [ ] Stickers group: Panel + Chat toggles (§17.7.1.1)
- [ ] Emoji group: Panel + Reactions + Chat + Status toggles (§17.7.1.1)
- [ ] Chat group: Background + Spoiler + Effects toggles (§17.7.1.1)
- [ ] Calls: standalone toggle (§17.7.1.1)
- [ ] Interface Animations: standalone toggle (§17.7.1.1)
- [ ] Battery Saver auto-toggle (conditional, only when OS exposes battery-saver) (§17.7.1.1)
- [ ] Forced-disable overlay: `boxBg` at alpha 96 over toggles (§17.7.1.1)
- [ ] Toast on overlay click: 3000ms duration (§17.7.1.1)

### 17.7.2-4 Hardware & Graphics
- [ ] "Enable hardware acceleration for video" toggle (§17.7.2)
- [ ] ANGLE Backend button (Windows only) -- right label showing current backend (§17.7.3)
- [ ] ANGLE: 5 options in SingleChoiceBox, restart dialog on change (§17.7.3)
- [ ] OpenGL toggle (Linux/Windows only) with restart dialog (§17.7.4)

### 17.8 Spellchecker
- [ ] "Enable" toggle (system or custom label) (§17.8)
- [ ] "Auto-download dictionaries" toggle (visible when custom ON) (§17.8)
- [ ] "Manage dictionaries" button with count label (visible when custom ON) (§17.8)

### 17.9 Screen Reader Accessibility
- [ ] Shown only when screen reader detected and mode disabled (§17.9)
- [ ] "Disable screen reader mode" toggle (§17.9)

### 17.10 Software Update
- [ ] Position: top when auto-update OFF, bottom when ON (§17.10)
- [ ] Auto-update toggle -- `settingsUpdateToggle` style (§17.10)
- [ ] State label: `settingsUpdateState` style at `settingsUpdateStatePosition` (§17.10)
- [ ] State labels: current version, checking, downloading+progress, ready, latest, failed (§17.10.1)
- [ ] "Install beta versions" toggle (hidden for alpha builds and during download) (§17.10)
- [ ] "Check for updates" button -- `settingsButtonNoIcon` (§17.10)
- [ ] Install ready overlay: accent button "Update Telegram" -> calls restart (§17.10)
- [ ] Progress rendering: downloaded/total with human-readable units (§17.10.2)
- [ ] Retry timer: 10s, auto-reattempts on failure (§17.10.3)

### 17.11 Export & Experimental
- [ ] "Export Telegram Data" button -- `menuIconExport` icon (§17.11)
- [ ] "Experimental Settings" button -- `menuIconExperimental` icon (§17.11)
- [ ] Experimental: top warning label `boxLabel` style (§17.11.1)
- [ ] Reset button (appears only when flags changed) (§17.11.1)
- [ ] Toggle rows: `settingsButtonNoIcon`, disabled rows: `settingsOptionDisabled` (§17.11.1)
- [ ] Flags auto-surface from registry (§17.11.2)
- [ ] Import/Export via base64url clipboard strings (prefix `tdesktop-flags:`) (§17.11.3)
- [ ] Export: serialize -> zlib compress -> base64url -> clipboard (§17.11.3)
- [ ] Import: validate prefix -> decode -> decompress -> apply (§17.11.3)
- [ ] Error toasts for invalid import (§17.11.3)

---

## 18. Settings -- Folders

### 18.1 Page Structure
- [ ] Full scrollable section, title "Folders" (§18.1)
- [ ] Icon in parent menu: `menuIconShowInFolder` (§18.1)
- [ ] Request suggested filters from server on open (§18.1)
- [ ] Layout: header, folder list, recommended, tags toggle, view section (§18.1)
- [ ] Auto-save pending changes on page destruction (§18.1)

### 18.2 Animated Header
- [ ] `BoxContentDivider` background (§18.2)
- [ ] Lottie `filters` 74x74px, padding (0,17,0,5), plays once on show (§18.2)
- [ ] Description text: `settingsFilterDividerLabel` style, min width 200px (§18.2)
- [ ] Description padding: (0,16,0,22) (§18.2)
- [ ] Balanced line wrapping (§18.2)
- [ ] Font: 13px regular (`normalFont`), color: `windowSubTextFg` (§18.2.1)

### 18.3 Existing Folders List
- [ ] Subsection title "Folders" (§18.3)
- [ ] Each folder: `FilterRowButton` -- custom `RippleButton`, 52px row height (§18.3)
- [ ] Folder icon: `activeButtonBg` (normal), `activeButtonBgOver` (hover) (§18.3)
- [ ] Title: `contactsNameStyle`, `contactsNameFg`, supports custom emoji (§18.3)
- [ ] Status: `contactsStatusFont`, `contactsStatusFg`, "{N} chats" + shareable indicator (§18.3)
- [ ] Color dot: circle diameter height/3, `EmptyUserpic::UserpicColor.color2` (§18.3)
- [ ] Color dot animation via `_colorIndexProgress` (§18.3)
- [ ] Remove (X) button right-aligned: `filtersRemove` style (§18.3)
- [ ] Restore button: `RoundButton` "Restore", 26px height, full radius (§18.3)
- [ ] Row states: Normal (clickable, hover+ripple), Removed (dimmed 0.4 opacity), Suggested (§18.3)
- [ ] Hover fill: `windowBgOver`, instant (no fade) (§18.3.1)
- [ ] Ripple: `defaultRippleAnimation` (§18.3.1)
- [ ] Normal click opens `EditFilterBox` (§18.3)
- [ ] Remove with chatlist links: confirmation dialog (§18.3)
- [ ] Remove shared chatlist: leave suggestions peer-selection dialog (§18.3)
- [ ] Tag fade duration: 120ms (`universalDuration`) (§18.3.1)
- [ ] No drag-to-reorder on settings page (reorder is in sidebar/topbar only) (§18.3.1)

### 18.4 Create New Folder
- [ ] "Create New Folder" button -- `settingsButtonActive`, `settingsIconAdd` icon (§18.4)
- [ ] Check folder limit on click (show `FiltersLimitBox` if reached) (§18.4)
- [ ] Opens `EditFilterBox` (§18.4)

### 18.5 Recommended (Suggested) Folders
- [ ] `SlideWrap` visible when suggestions > 0 AND count < limit (§18.5)
- [ ] Divider + subtitle "Recommended folders" (§18.5)
- [ ] Each suggestion: `FilterRowButton` in Suggested state (§18.5)
- [ ] No icon on left, title + server description, "Add" button (26px, full radius) (§18.5)

### 18.6 Edit Filter Box
- [ ] `GenericBox`, 364px wide (§18.6)
- [ ] Title: "New Folder" / "Edit Folder" (§18.6)
- [ ] `closeByOutsideClick` = false (§18.6)
- [ ] Buttons: "Create"/"Save" + "Cancel" (§18.6)

### 18.6.1 Folder Name Input
- [ ] `InputField` styled `windowFilterNameInput` (§18.6.1)
- [ ] Right margin 87px (room for icon toggle + emoji button) (§18.6.1)
- [ ] Placeholder: "Folder name" (§18.6.1)
- [ ] Max length: 12 characters (§18.6.1)
- [ ] Supports custom emoji (Premium) and standard emoji (§18.6.1)
- [ ] Character counter always visible at (75, 27) from right (§18.6.1)
- [ ] Emoji button at (-65, 22) -- opens `TabbedPanel` in `EmojiOnly` mode (§18.6.1)
- [ ] Icon selector toggle: 36x36px at (-4, 18) inside name field (§18.6.1)
- [ ] Icon painted in `dialogsUnreadBgMuted` (§18.6.1)
- [ ] Click opens FilterIconPanel grid (§18.6.1)
- [ ] Auto-title: auto-fills based on selected types when creating (§18.6.1)

### 18.6.2 Included Chats Section
- [ ] Subtitle: "Included Chats" (§18.6.2)
- [ ] "Add Chats" button: `settingsButtonActive`, `settingsIconAdd` (§18.6.2)
- [ ] Preview widget (`FilterChatsPreview`): vertical stack of 44px rows (§18.6.2)
- [ ] Each row: 34px photo at (13, 5), name at (59, 14), remove button 10px from right (§18.6.2)
- [ ] Chat type rows: gradient circle userpics with white icons (§18.6.2)
- [ ] 5 include types: Contacts (green), NonContacts (cyan), Groups (green), Channels (red), Bots (purple) (§18.6.2)
- [ ] Name text elides to leave clearance for remove button (§18.6.2.2)
- [ ] Footer text about choosing chats (§18.6.2)

### 18.6.3 Excluded Chats Section
- [ ] Hidden when `chatlist` is true (§18.6.3)
- [ ] Subtitle: "Excluded Chats" (§18.6.3)
- [ ] "Remove Chats" button: `settingsButtonActive`, `settingsIconRemove` (§18.6.3)
- [ ] Same preview widget as included (§18.6.3)
- [ ] 3 exclude types: Muted (purple), Archived (green), Read (cyan) (§18.6.3)
- [ ] Footer text (§18.6.3)

### 18.6.4 Tag Color Section (Premium)
- [ ] Visible when Premium is possible (§18.6.4)
- [ ] Subtitle "Tag Color" with inline tag preview badge (14px offset from title) (§18.6.4)
- [ ] 8 circular color buttons, evenly spaced (§18.6.4)
- [ ] Chip size: 30px, full circle (§18.6.4.1)
- [ ] Colors 0-6 from `EmptyUserpic::UserpicColor(i).color2` (palette-indexed, not hardcoded) (§18.6.4.1)
- [ ] Color 7: "no tag" with X icon (`historyPeerArchiveUserpicBg`) (§18.6.4.1)
- [ ] Chip spacing: `(row_width - 8*30) / 7` (§18.6.4.1)
- [ ] Row padding: `boxRowPadding` (22px left/right) (§18.6.4.1)
- [ ] Selection ring on selected chip (§18.6.4.1)
- [ ] Selection animation: 120ms, color crossfade via `anim::color` (§18.6.4.1)
- [ ] Non-Premium: clicking opens `PremiumPreviewBox(FilterTags)` (§18.6.4.1)
- [ ] Footer: "Choose a color for the folder tag." (§18.6.4)

### 18.6.5 Shareable Link Section
- [ ] Title: "Share Folder" (no links) / "Invite Links" (has links) (§18.6.5)
- [ ] "Create Link" button: `settingsButtonActive`, `settingsFolderShareIcon` (§18.6.5)
- [ ] "Add Link" button (when links exist): `settingsIconAdd` (§18.6.5)
- [ ] Link rows: green circle userpic (`msgFile1Bg`) with `inviteLinkIcon` (§18.6.5)
- [ ] Row: 52px height, icon at (9,4), name at (60,6), status at (60,26), 44px icon size (§18.6.5.1)
- [ ] Three-dots icon right-aligned, `inviteLinkThreeDotsSkip` 12px from right (§18.6.5.1)
- [ ] Context menu: Copy, Share, QR Code, Name it, Delete (§18.6.5)
- [ ] Validation on create: no exclusions or rule flags allowed (toast) (§18.6.5)

### 18.6.6 Validation on Save
- [ ] Empty or >12 char title -> `showError()`, scroll to top (§18.6.6)
- [ ] No include types AND no chats -> toast "folder can't be empty" (§18.6.6)
- [ ] All types + NoArchived, no specific chats -> toast "would include all chats" (§18.6.6)

### 18.7 Include/Exclude Chats Picker
- [ ] `PeerListBox` with `EditFilterChatsListController` (§18.7)
- [ ] Title: "Include Chats" / "Exclude Chats" (§18.7)
- [ ] `closeByOutsideClick` = false (§18.7)
- [ ] Chat type section subtitle: "Chat types" (semibold, `searchedBarFg`, 28px height, `searchedBarBg`) (§18.7)
- [ ] Type rows: 44px height, 34px gradient circle photo, checkbox toggle (§18.7)
- [ ] Include types: NewChats, ExistingChats, Contacts, NonContacts, Groups, Channels, Bots (§18.7)
- [ ] Exclude types: NoMuted, NoRead, NoArchived (§18.7)
- [ ] Counter: "{selected} / {limit}" (§18.7)

### 18.8 Filter Icon Picker Panel
- [ ] Grid: 6 columns x 5 rows (§18.8)
- [ ] Cell size: 44x42px (§18.8)
- [ ] Padding: (10, 36, 10, 8) -- 36px top for header (§18.8.1)
- [ ] Header text at (18, 14): "Folder Icon" in `emojiPanHeaderFont`/`emojiPanHeaderFg` (§18.8.1)
- [ ] 30 icons in specified order (Cat through Setup) (§18.8)
- [ ] Normal color: `sideBarIconFg`, active: `sideBarIconFgActive` (§18.8)
- [ ] Icon tint normal: `dialogsUnreadBgMuted`, hover: `dialogsUnreadBgMutedOver` (§18.8.1)
- [ ] Panel background: `dialogsBg` with large rounded corners (§18.8.1)
- [ ] Hover highlight: `dialogsBgOver` with `StickerHoverCorners` rounding (§18.8.1)
- [ ] Show animation: `PanelAnimation` with `Origin::TopRight` (§18.8.1)
- [ ] Hide-after-leave timeout: 300ms (§18.8.1)
- [ ] Anchor offset: (-2, -1) relative to toggle (§18.8.1)
- [ ] Click selects icon, fires `_chosen` signal (§18.8.1)
- [ ] Auto-icon selection based on filter types (§18.8)

### 18.9 Show Link Box
- [ ] `PeerListBox` with `LinkController`, `inviteLinkChatList` style (§18.9)
- [ ] Header: Lottie `cloud_filters` 74x74px, description with folder name bold (§18.9)
- [ ] `InviteLinkLabel` with URL, Copy + Share buttons (§18.9)
- [ ] Chat list with subtitle + select/deselect toggle (§18.9)
- [ ] Disabled rows (bots, private users, non-admin channels) with dashed circle overlay (§18.9)
- [ ] Dashed circle: 1.5dp width, 11 segments, `windowSubTextFg` (§18.9)
- [ ] Buttons: "Save"/"Cancel" when changes, "Done" when unchanged (§18.9)

### 18.10 Chatlist Folder Removal Dialog
- [ ] `PeerListBox` in `filterInviteBox` style (button height 42px) (§18.10)
- [ ] Shows channels from folder's always-list (§18.10)
- [ ] Server-suggested peers to leave pre-selected (§18.10)
- [ ] Action button shows selected count badge (§18.10)

### 18.11 Folder Tags Toggle (Premium)
- [ ] "Show Folder Tags" text (§18.11)
- [ ] `settingsButtonNoIconLocked` with toggle (§18.11)
- [ ] Non-Premium: locked, clicking opens `PremiumPreviewBox(FilterTags)` (§18.11)
- [ ] Premium: toggling sends request with 500ms debounce (§18.11)
- [ ] Tag animation: all folder row color dots animate in/out via 120ms `universalDuration` (§18.11)

### 18.12 Tab View Section
- [ ] Visible only when window width >= 452px (§18.12.1)
- [ ] Two radio options: "Side panel" / "Top bar" (§18.12)
- [ ] `settingsCheckbox` style, margins (22, 5, 10, 5) (§18.12)
- [ ] Sidebar mode: 72px width, vertical tabs, long-press drag reorder (§18.12.1)
- [ ] Top-bar mode: horizontal strip, horizontal-scroll on overflow (§18.12.1)
- [ ] Drag threshold: platform `startDragDistance` (~10px) (§18.12.1)
- [ ] Shift animation: 150ms (`slideWrapDuration`) (§18.12.1)
- [ ] Auto-scroll factor near edge: 0.05 (§18.12.1)
- [ ] Pinned interval support for fixed "All chats" tab (§18.12.1)

### 18.13 Premium Limits
- [ ] Total folders: 10 free / 20 premium (§18.13)
- [ ] Chats per folder: 100 free / 200 premium (§18.13)
- [ ] Shareable folders: 2 free / 20 premium (§18.13)
- [ ] Links per folder: 3 free / 20 premium (§18.13)
- [ ] Limit boxes: `FiltersLimitBox`, `FilterChatsLimitBox`, `ShareableFiltersLimitBox`, `FilterLinksLimitBox` (§18.13)
- [ ] All limit boxes: animated infographic, Premium icon, description (§18.13)

---

## 19. Settings -- Sessions, Power Saving & Language

### 19.1 Active Sessions Overview
- [ ] Title "Active Sessions", icon `menuIconDevices` (§19.1)
- [ ] Auto-refresh every 60 seconds (§19.1)
- [ ] Loading state: spinner with "Loading..." in `noContactsFont`/`noContactsColor` (§19.1)
- [ ] Six zones with conditional visibility (§19.1)

### 19.2 Current Session Display
- [ ] "This device" header with "Rename" link button on right (§19.2)
- [ ] Link offset: 11px + 12px from right edge (§19.2.1)
- [ ] Link style: `defaultLinkButton` (blue, underline on hover) (§19.2.1)
- [ ] Row: 84px height, 42px photo at (21, 10) (§19.2)
- [ ] Photo: vertical gradient circle + platform icon (§19.2.2)
- [ ] Gradient: vertical `QLinearGradient` top->bottom, platform-specific color pairs (§19.2.2)
- [ ] Name: `msgNameFont` 13px semibold at (78, 11) (§19.2)
- [ ] Status at (78, 32) in `boxTextFg` (§19.2)
- [ ] Location at y=54, `normalFont` 13px, `sessionInfoFg` (§19.2)
- [ ] Location format: "{location} . {active_date}" (§19.2)
- [ ] No terminate button on current session (§19.2)
- [ ] Standard `windowBg` background (no special gradient) (§19.2.2)

### 19.3 Device Type Detection & Icons
- [ ] Classification by API ID first, then keyword detection (§19.3)
- [ ] 13 device types with specific gradients, list icons, Lottie animations (§19.3)
- [ ] Windows/Mac/Other: green gradient (§19.3)
- [ ] Ubuntu: orange gradient (§19.3)
- [ ] Linux: purple gradient (§19.3)
- [ ] iPhone/iPad: cyan gradient (§19.3)
- [ ] Android: red gradient (§19.3)
- [ ] Web/Chrome/Edge/Firefox/Safari: pink gradient (§19.3)
- [ ] All icons use `historyPeerUserpicFg` (white), centered in gradient circle (§19.3)

### 19.4 Other Sessions List
- [ ] Header "Active sessions" with 14px top skip (§19.4)
- [ ] Each row: 84px height (§19.4)
- [ ] Terminate button: 34x34px, `smallCloseIcon`, top 8px, right 11px (§19.4)
- [ ] Row click -> SessionInfoBox (§19.4)
- [ ] Terminate click -> confirmation dialog (§19.4)
- [ ] Footer: explanatory divider text (§19.4)
- [ ] No between-row hairline dividers (§19.4.1)
- [ ] Row separation via 84px height + `windowBgOver` hover fill (§19.4.1)

### 19.5 Incomplete Login Attempts
- [ ] Header "Incomplete Login Attempts" with 14px top skip (§19.5)
- [ ] Same row style as other sessions (§19.5)
- [ ] Sorted newest first (§19.5)
- [ ] Footer explanation (§19.5)

### 19.6 Session Detail View (SessionInfoBox)
- [ ] Width: 364px (`boxWideWidth`) (§19.6)
- [ ] Header: 70px userpic + 52px Lottie, padding (0,18,0,7) (§19.6)
- [ ] Lottie plays once on show (§19.6)
- [ ] Device name: 20px semibold, `boxTitleFg`, max height 29px (§19.6)
- [ ] Date: `windowSubTextFg`, full datetime, bottom margin 19px (§19.6)
- [ ] Info rows: Application, System, IP Address, Location (§19.6)
- [ ] Each info row: icon at (20, 9), value at 61px left indent, caption in `windowSubTextFg` (§19.6)
- [ ] Icons: `menuIconDevices`, `menuIconInfo`, `menuIconIpAddress`, `menuIconAddress` (§19.6)
- [ ] AyuGram addition: "Official App" row (Yes/No) (§19.6.1)
- [ ] "OK" button (closes box) (§19.6)
- [ ] Non-current sessions: "Terminate Session" button (`attentionBoxButton`, red) (§19.6.1)
- [ ] Terminate confirmation dialog (§19.6.1)

### 19.7 Terminate All Sessions
- [ ] "Terminate All Other Sessions" button -- `infoBlockButton` with `infoIconBlock` (§19.7)
- [ ] Visible when other sessions > 0 (§19.7)
- [ ] Confirmation: "Are you sure?" with "Terminate" in `attentionBoxButton` (§19.7)

### 19.8 Rename Device Dialog
- [ ] Title "Rename Device" (§19.8)
- [ ] Input: `settingsDeviceName` style (transparent bg, 29px min height) (§19.8)
- [ ] Placeholder: device model name (§19.8.1)
- [ ] Max 32 characters (§19.8.1)
- [ ] "Save" + "Cancel" buttons (§19.8)
- [ ] Empty input reverts to platform model name (§19.8.1)

### 19.9 Auto-Terminate Inactive Sessions
- [ ] "If Inactive For" button with right label -- `settingsButtonNoIcon` (§19.9)
- [ ] SelfDestructionBox (Sessions): radios 1 week, 1/3/6/12 months (§19.9.1)
- [ ] Box width: `boxWidth` (§19.9.1)
- [ ] Description above radios (§19.9.1)
- [ ] Radio style: `autolockButton`, spacing: `boxOptionListSkip` (§19.9.1)
- [ ] "Save" + "Cancel" buttons (§19.9.1)

### 19.10-11 Power Saving Settings
- [ ] `GenericBox`, title "Power Saving", 364px wide (§19.10)
- [ ] Not inlined in §17, standalone box (§19.10.1)
- [ ] All toggles: `powerSavingButton` style (padding 57/8/22/8, iconLeft 20px) (§19.11)
- [ ] Stickers header + 2 toggles (Panel, Messages) (§19.11)
- [ ] Emoji header + 4 toggles (Panel, Reactions, Messages, Status) (§19.11)
- [ ] Chat header + 3 toggles (Background, Spoiler, Effects) (§19.11)
- [ ] Calls standalone toggle (§19.11)
- [ ] Interface Animations standalone toggle (§19.11)
- [ ] Total 11 flags (§19.11)
- [ ] Category headers: standard subsection-title style (§19.11)
- [ ] Sub-items: `powerSavingButtonNoIcon` padding (22/8/22/8) (§19.10.1)

### 19.12 Automatic Mode & Battery
- [ ] Shown only when OS provides battery status (§19.12)
- [ ] "Automatic Power Saving" toggle -- `powerSavingButtonNoIcon` (§19.12)
- [ ] Auto ON + battery saver active: overlay `boxBg` at alpha 96/255 (§19.12)
- [ ] Overlay covers subtitle + controls, OK button remains clickable (§19.12.1)
- [ ] Click overlay: toast "Turn off your device's power saving mode..." for 3s (§19.12.1)
- [ ] Overlay disappears when OS exits battery saver (§19.12.1)

### 19.13 Language Selection (LanguageBox)
- [ ] Title "Language", width 320px (§19.13)
- [ ] Max list height: 492px (§19.13)

### 19.14 Translation Settings
- [ ] Three toggles above language list (logged-in only) (§19.14)
- [ ] "Show Translate Button" toggle -- `settingsButtonNoIcon` (§19.14)
- [ ] "Translate Entire Chats" toggle -- `settingsButtonNoIconLocked`, Premium-locked (§19.14)
- [ ] "Do Not Translate" in `SlideWrap`, shown when either toggle above ON (§19.14)
- [ ] Right label: language name (if 1) or "{N} languages" (if multiple) (§19.14.1)
- [ ] Click opens skip-languages editor (ChooseLanguageBox) (§19.14.1)
- [ ] Divider text explaining translation feature (§19.14)

### 19.14.2 Skip-Languages Editor
- [ ] Title "Do Not Translate" (§19.14.2)
- [ ] Checkbox-based multi-select (not tag chips) (§19.14.2)
- [ ] Enforced minimum: one language must remain selected (§19.14.2)
- [ ] Toast if user tries to deselect all (§19.14.2)

### 19.15 Language List
- [ ] `MultiSelect` search field with "Search" placeholder (§19.15)
- [ ] Used purely as search bar (no tag chips) (§19.15.1)
- [ ] Two sections separated by `BoxContentDivider` (§19.15)
- [ ] Recent languages section (current language sorted to top) (§19.15)
- [ ] Official languages section (de-duplicated against recent) (§19.15)
- [ ] Empty state: "No languages found" centered, `membersAbout` style (§19.15)

### 19.16 Language Row Layout
- [ ] Radio button: `langsRadio` 22px diameter, `windowBgActive` when selected (§19.16)
- [ ] Title (native name): `semiboldTextStyle`, `windowFg`, left 66px, top 8px (§19.16)
- [ ] Description (English name): `defaultTextStyle`, `windowSubTextFg`, left 66px (§19.16)
- [ ] Menu toggle (3-dot): `topBarMenuToggle`, right side (§19.16)
- [ ] Row hover: `windowBgOver` (§19.16)
- [ ] Click activates language (§19.16)
- [ ] Row height: ~54px computed (8 + 18 + 4 + 16 + 8) (§19.16.1)

### 19.17 Language Row Context Menu
- [ ] Non-official rows only (§19.17)
- [ ] `dropdownMenuWithIcons` style (§19.17)
- [ ] "Share" -- copies language link to clipboard (`menuIconShare`) (§19.17)
- [ ] "Delete" -- marks removed, dims row (`menuIconDelete`) (§19.17)
- [ ] "Restore" -- un-marks removed (`menuIconRestore`) (§19.17)

---

## 20. Media Viewer / Lightbox

### 20.1 Window Modes & Geometry
- [ ] Three window states: full-screen (default), maximized, windowed (§20.1)
- [ ] State persisted to settings (§20.1)
- [ ] Full-screen: covers entire screen (§20.1)
- [ ] macOS: `Qt::Tool | Qt::FramelessWindowHint` (§20.1)
- [ ] Minimum size: 480x360px (§20.1)
- [ ] Default windowed: 800x600 at (160, 120) (§20.1)
- [ ] Title bar buttons: 44x32px each (§20.1)
- [ ] Title bar height: 32px (§20.1)
- [ ] Title text: "Media viewer" (§20.1)

### 20.2 Background & Shadows
- [ ] Background: `mediaviewBg` (opaque dark) (§20.2)
- [ ] Top and bottom gradient shadow overlays (§20.2)
- [ ] Shadows rendered at `_controlsOpacity` (0.0-1.0) (§20.2)

### 20.3 Content Display
- [ ] Media centered in available area (§20.3)
- [ ] Photo: progressive loading (thumbnailInline -> Small -> Thumbnail -> Large) (§20.3)
- [ ] Video/GIF: streaming frames (§20.3)
- [ ] Document bubble: `mediaviewFileBg`, 340x116px, 80x80px icon area (§20.3)
- [ ] Theme preview: 903x584px with Apply/Cancel/Share buttons (§20.3)

### 20.4 Zoom & Pan
- [ ] Zoom range: -7 (1/8x) to +7 (8x) (§20.4)
- [ ] Fit-to-screen zoom level: kZoomToScreenLevel (1024) (§20.4)
- [ ] Ctrl+/Ctrl- zoom in/out (§20.4)
- [ ] Ctrl+0 toggle 1:1 / fit-to-screen (§20.4)
- [ ] Middle mouse: zoom reset (§20.4)
- [ ] Mouse wheel + Ctrl: zoom per step (§20.4)
- [ ] Mouse wheel (no modifier): navigate prev/next (§20.4)
- [ ] Pan when zoomed: left-click-drag, `cur_sizeall` cursor (§20.4)
- [ ] Pan snapped to bounds (§20.4)
- [ ] Zoom transitions animate with `widgetFadeDuration` (§20.4)
- [ ] DPR-aware: stamp DevicePixelRatio before draw (§20.4.1)
- [ ] Max display image size cap: 4096px (§20.4.1)

### 20.5 Rotation & Flip
- [ ] Rotation: 0/90/180/270, each click subtracts 90 degrees (§20.5)
- [ ] Rotate button in bottom-right toolbar (§20.5)
- [ ] Flip: H key = horizontal, V key = vertical (photo only, not stories) (§20.5)

### 20.6 Navigation Controls
- [ ] Two side areas for prev/next (§20.6)
- [ ] Normal width: 90px, Stories width: 64px (§20.6)
- [ ] Normal icons: `mediaview/next` (flipped for left) (§20.6)
- [ ] Stories icons: `stories/next` (§20.6)
- [ ] Hover: 36px circle (`mediaviewIconOver`), none for stories (§20.6)
- [ ] Left/Right arrow keys navigate (§20.6)
- [ ] Touch/swipe: 80px threshold (§20.6)
- [ ] Preloading: 3 items ahead, 48 IDs in each direction (§20.6)

### 20.7 Footer / Header Area
- [ ] Bottom-left, painted at `_controlsOpacity` (§20.7)
- [ ] Header: "Photo N of M" or filename (§20.7)
- [ ] `mediaviewThickFont` semibold, position (14, height-47) (§20.7)
- [ ] Max width: width/3, middle-elided (§20.7)
- [ ] Clickable -> opens media overview (§20.7)
- [ ] Sender name: `mediaviewFont` normal, position (14, height-26) (§20.7)
- [ ] Clickable -> peer info (§20.7)
- [ ] Separator: bullet with 5px spacing (§20.7)
- [ ] Date: formatted datetime + DC number (§20.7)
- [ ] Date clickable -> navigate to message in chat (§20.7)
- [ ] Color: `mediaviewControlFg` (§20.7)

### 20.8 Bottom-Right Toolbar
- [ ] Icons right-to-left in 46x54px cells (§20.8)
- [ ] Hover: 36px circle (§20.8)
- [ ] More/menu: `title_menu_dots` (always) (§20.8)
- [ ] Rotate: `mediaview/rotate` (not stories/theme) (§20.8)
- [ ] Share: `mediaview/viewer_share` (stories + shareable) (§20.8)
- [ ] Save: `mediaview/download` (loaded content) (§20.8)
- [ ] Draw: `mediaview/draw` (photo/image doc) (§20.8)
- [ ] OCR: `mediaview/recognize` (OCR results available) (§20.8)
- [ ] Icon hover fade: 150ms (`mediaviewFadeDuration`), `anim::linear` (§20.8)

### 20.8.1 More-Menu Contents
- [ ] Dropdown menu with up to 18 conditional items (§20.8.1)
- [ ] Same items as right-click context menu (§20.8.1)
- [ ] Cancel download, Show in Chat, Retract Vote (§20.8.1)
- [ ] Archive/Save to Profile, Show in Folder (§20.8.1)
- [ ] Copy Image/Copy Frame, Attached Stickers (§20.8.1)
- [ ] Forward, Share at Time, Share Story (§20.8.1)
- [ ] Delete, Save As, Show All Photos/Files (§20.8.1)
- [ ] Set as Userpic, Report Userpic (§20.8.1)
- [ ] View Statistics, Stealth Mode, Report Story (§20.8.1)
- [ ] Sponsored messages suppress entire menu (§20.8.1)

### 20.9 Caption Display
- [ ] Background: `mediaviewCaptionBg`, radius 6px (§20.9)
- [ ] No background in stories (§20.9)
- [ ] Padding: 11/6/11/6px (§20.9)
- [ ] Text: `mediaviewCaptionStyle`, color `mediaviewCaptionFg` (§20.9)
- [ ] Links: `mediaviewTextLinkFg` (§20.9)
- [ ] Max height: 1/4 of `_maxUsedHeight` (§20.9)
- [ ] Stories: collapsed to `kCollapsedCaptionLines` with "Show more" (§20.9)
- [ ] Position: bottom-aligned above playback controls, centered, 11px margin (§20.9)
- [ ] Spoiler support and timestamp links (§20.9)

### 20.10 Video Playback Controls
- [ ] Rounded-rect panel: `mediaviewSaveMsgBg` background (§20.10)
- [ ] Max width 480px, height 72px + optional 10px timestamp (§20.10)
- [ ] Centered horizontally (§20.10)
- [ ] Volume toggle: 32x32px, icons `player_volume_off/_small/_on` (§20.10)
- [ ] Volume slider: 75px wide, `mediaviewPlayback` style (§20.10)
- [ ] Time played: 12px semibold, `mediaviewPlaybackProgressFg` (§20.10)
- [ ] Progress bar: 3px track, 12px seek handle (§20.10)
- [ ] Time remaining with minus prefix (§20.10)
- [ ] Play/Pause: 40x40px centered, `player_play_big`/`player_pause_big` (§20.10)
- [ ] Settings (speed): 32x32px, shows speed value or quality (§20.10)
- [ ] PiP button: 32x32px, `player_pip` (§20.10)
- [ ] Fullscreen button: 32x32px, `player_fullscreen`/`player_minimize` (§20.10)
- [ ] Progress active: `mediaviewPlaybackActive` (§20.10)
- [ ] Progress inactive: `mediaviewPlaybackInactive` (§20.10)
- [ ] Progress buffer: `mediaviewPlaybackInactiveOver` (§20.10)
- [ ] Chapter dividers: 2x10px marks (§20.10)
- [ ] Controls fade in 200ms, fade out 600ms (§20.10)

### 20.11 Video Player Behavior
- [ ] Play/Pause: Space, Enter, or click video area (§20.11)
- [ ] Seek: drag progress, Left/Right +/-5s in fullscreen (§20.11)
- [ ] 0-9 keys: jump to 0%-90% in fullscreen (§20.11)
- [ ] Alt+Left/Right: chapter navigation (§20.11)
- [ ] Speed: 0.5x-3.0x, saved to settings (§20.11)
- [ ] Quality menu: list of heights (360/720/1080), seamless switch (§20.11)
- [ ] Volume: 0.0-1.0, toggle mutes/restores, default 0.8 (§20.11)
- [ ] Loop: animations loop, sound videos don't (§20.11)
- [ ] Auto-pause on Telegram call (§20.11)

### 20.12 Full-Screen Video Mode
- [ ] Toggle: double-click, Alt+Enter, Ctrl+Enter, Ctrl+F, or button (§20.12)
- [ ] Content fills screen, overlay controls hidden (§20.12)
- [ ] Auto-hide after 1100ms with blank cursor (§20.12)
- [ ] Escape exits fullscreen (doesn't close viewer) (§20.12)

### 20.13 Picture-in-Picture (PiP)
- [ ] Floating always-on-top window (§20.13)
- [ ] Default 320px, minimum 120px (§20.13)
- [ ] Resize area: 10px edges (§20.13)
- [ ] Own play/pause, close, enlarge, volume controls (§20.13)
- [ ] Playback track: 2px default, 4px hover (§20.13)
- [ ] Geometry persisted (§20.13)
- [ ] Closing returns to full overlay at same position (§20.13)
- [ ] Edge-snap: `pipBorderSnapArea` 16px threshold (§20.13.1)
- [ ] Snap margin: `pipBorderSkip` 20px from screen edge (§20.13.1)
- [ ] Default landing: top-left corner (§20.13.1)
- [ ] Release animation: `easeOutCirc`, ~150ms (§20.13.1)
- [ ] Z-order: `WindowStaysOnTopHint | WindowDoesNotAcceptFocus` (§20.13.1)

### 20.14 Gallery / Group Thumbs Strip
- [ ] Horizontal thumbnails at bottom (§20.14)
- [ ] Width range: 56px to 160px, height 80px (§20.14)
- [ ] Padding: 0/14/0/14px, skip 3px between, 12px for current item (§20.14)
- [ ] Current thumb centered in strip (§20.14.1)
- [ ] Current thumb: 160px width, neighbours: 56px (§20.14.1)
- [ ] No scrollbar, no drag-scroll (§20.14.1)
- [ ] Overflow: cap visible neighbours based on available width (§20.14.1)
- [ ] Click navigates to item (§20.14)
- [ ] In/out animation: 150ms per slide (§20.14.1)
- [ ] Active thumb emphasis via width only (no stroke ring) (§20.14.1)

### 20.15 Save/Download Toast
- [ ] Centered toast: `mediaviewSaveMsgBg` background (§20.15)
- [ ] Check icon at (23, 21)px (§20.15)
- [ ] Padding: 55/19/29/20px (§20.15)
- [ ] Text: 16px `mediaviewSaveMsgStyle`, color `mediaviewSaveMsgFg` (§20.15)
- [ ] Animation: fade in 200ms, hold 2s, fade out 2.5s (§20.15)
- [ ] Clickable "Downloads" link (§20.15)

### 20.16 Context Menu
- [ ] Right-click opens dark-themed popup (§20.16)
- [ ] `groupCallMenuBg` background, `groupCallMembersFg` text (§20.16)
- [ ] Same items as more-menu with per-content-type conditionals (§20.16.1)
- [ ] Rotate NOT in context menu (toolbar-only + keyboard) (§20.16.1)

### 20.17 Stories Viewer
- [ ] Delegates to `Stories::View` (§20.17)
- [ ] Aspect-fit within 540x960px with 8px radius (§20.17)
- [ ] Sibling story previews as thumbnails (§20.17)
- [ ] Controls always visible (§20.17)
- [ ] No zoom/rotation for stories (§20.17)
- [ ] Collapsed captions with "Show more" (§20.17)

### 20.18 Keyboard Shortcuts
- [ ] Escape: close (or exit fullscreen video) (§20.18)
- [ ] Space: play/pause video / toggle pause stories (§20.18)
- [ ] Left/Right: prev/next (or seek +/-5s in fullscreen) (§20.18)
- [ ] Alt+Left/Right: jump to prev/next chapter (§20.18)
- [ ] 0-9: jump to 0%-90% in fullscreen video (§20.18)
- [ ] Ctrl+F / Alt+Enter: toggle fullscreen video (§20.18)
- [ ] Ctrl+/Ctrl-: zoom in/out (§20.18)
- [ ] Ctrl+0: zoom reset (§20.18)
- [ ] Ctrl+S: save as (§20.18)
- [ ] Ctrl+C: copy media/frame (§20.18)
- [ ] H / V: flip horizontal/vertical (photo only) (§20.18)

### 20.19 Animations
- [ ] Controls auto-hide: 1100ms idle -> 600ms fade out (§20.19)
- [ ] Mouse activity -> 200ms fade in (§20.19)
- [ ] Blank cursor when hidden (§20.19)
- [ ] Icon hover: 150ms per-icon fade (§20.19)
- [ ] Between-media: rect interpolation with rotation over `widgetFadeDuration` (§20.19)
- [ ] Radial loading: spinning arc (§20.19)
- [ ] Open animation: 200ms, `Curves.linear` (§20.19.1)
- [ ] Close animation: 600ms, `Curves.linear` (§20.19.1)
- [ ] Rect coordinates: linear interpolation component-wise (§20.19.1)
- [ ] Rotation: shortest-path wrap through +/-180 degrees (§20.19.1)
- [ ] Overlay background fade: `mediaviewBg` 0->1 on 200ms ramp (§20.19.1)

---

## 21. Create Group / Channel Wizard

### 21.1 Overview
- [ ] Multi-step layered-box flow (§21.1)
- [ ] Entry: hamburger menu "New Group" / "New Channel" (§21.1)
- [ ] All boxes: 364px width (§21.1)
- [ ] Group flow: InfoBox -> Member picker (§21.1)
- [ ] Channel flow: InfoBox -> SetupChannelBox -> Member picker (§21.1)

### 21.2 Step 1 -- Group/Channel Info Box
- [ ] Title bar: 48px height, 16px semibold font (§21.2)
- [ ] Userpic button: 72x72px at (24, 10) (§21.2)
- [ ] Default userpic: `EmptyUserpic` with gradient + first letter of title (§21.2.1)
- [ ] Gradient: vertical top->bottom from `historyPeerNUserpicBg` pairs (§21.2.1)
- [ ] Initials: up to 2 letters, uppercased, 28px font at 72px frame (§21.2.1)
- [ ] Centered text in full square frame (§21.2.1)
- [ ] Forum userpic: rounded rect with forum radius multiplier (§21.2.1)
- [ ] Change icon at (21, 23), always visible when no image (§21.2.1)
- [ ] Upload overlay: 24px height, `msgDateImgBgOver` (§21.2)
- [ ] Progress ring: 3px line, 8px margin, 500ms animation (§21.2)
- [ ] Click: popup menu (File / Camera / Clipboard / Emoji builder) (§21.2.1)
- [ ] Title input: position left 99px, top 5px, width ~217px (§21.2)
- [ ] Max 128 characters, emoji suggestions enabled (§21.2)
- [ ] Description (channels only): MultiLine, max 255 chars, max height 116px (§21.2)
- [ ] Description top margin: 13px below userpic (§21.2)
- [ ] TTL menu (groups only): top-bar menu button with current TTL value (§21.2)
- [ ] Buttons: "Create" (channels) / "Next" (groups) + "Cancel" (§21.2)
- [ ] Empty title -> focus + shake (§21.2)
- [ ] Error handling: NO_CHAT_TITLE, USERS_TOO_FEW, CHANNELS_TOO_MUCH (§21.2)

### 21.2.2 Forum Entry -- "Enable Topics"
- [ ] Toggle in post-creation Manage Group settings (not in Step 1) (§21.2.2)
- [ ] Row style: `manageGroupTopicsButton`, icon `menuIconTopics`, "NEW" badge (§21.2.2)
- [ ] Label: "Topics" (§21.2.2)
- [ ] Clickable nav (arrow chevron), NOT inline toggle (§21.2.2)
- [ ] Child screen with Tabs/List layout radios + enable toggle (§21.2.2)
- [ ] Member-count gate: minimum from AppConfig, fallback 200 (§21.2.2)
- [ ] Below threshold: shows "need at least N members" message, confirm disabled (§21.2.2)
- [ ] Forces pre-join history visible when enabled (§21.2.2)

### 21.3 Step 2a -- Member Picker
- [ ] `PeerListBox` with `MultiSelect` search/chips bar (§21.3)
- [ ] MultiSelect bar: `boxSearchBg` background, 8px padding, max 104px height (§21.3)
- [ ] Chips: 32px height, max 128px width (§21.3)
- [ ] Chip background: `contactsBgOver` (normal), `activeButtonBg` (active) (§21.3)
- [ ] Chip delete cross: 32px, 1.5px stroke, 150ms animation (§21.3)
- [ ] Chip spacing: 8px (§21.3)
- [ ] Search field: transparent bg, 32px min height, search icon at (10, 9) (§21.3)
- [ ] Contact rows: 56px height, 42px avatar at (16, 7) (§21.3)
- [ ] Name at (74, 9) semibold, status at (74, 30) (§21.3)
- [ ] Avatar as checkbox: checked shows round check overlay with `windowActiveTextFg` tint (§21.3)
- [ ] "Invite via Link" button above list if `canHaveInviteLink()` (§21.3)
- [ ] Counter: "42 / 200000" in title bar (§21.3)
- [ ] Buttons: "Create" + "Cancel" (new group) or "Invite" + "Skip" (post-channel) (§21.3)

### 21.4 Step 2b -- Channel Setup Box
- [ ] Width 364px (§21.4)
- [ ] Privacy radios: Public / Private (§21.4)
- [ ] `defaultBoxCheckbox` style, 27px skip between (§21.4)
- [ ] About text in `windowSubTextFg` (§21.4)
- [ ] Username field (when public): `t.me/` prefix, `setupChannelLink` style (32px min height) (§21.4)
- [ ] Validation after 200ms debounce (§21.4.1)
- [ ] Client-side pre-checks: too short (<5), bad symbols, empty (§21.4.1)
- [ ] API check: available (green text), invalid (red), occupied (red) (§21.4.1)
- [ ] No animated tick -- green text label only (§21.4.1)
- [ ] Username: min 5, max 32 characters, `[A-Za-z0-9_]` only (§21.4)
- [ ] Invite link (when private): clickable, copies to clipboard with toast (§21.4)
- [ ] Too many public usernames: auto-switch to private, show `PublicLinksLimitBox` (§21.4)

### 21.4.2 PublicLinksLimitBox
- [ ] Width 364px (`boxWideWidth`) (§21.4.2)
- [ ] Title "Public Link Limit Reached" (§21.4.2)
- [ ] Bubble row with icon + numeric counter (§21.4.2)
- [ ] Free cap: 10 public links, Premium cap: 20 (§21.4.2)
- [ ] Description with current/premium limits (§21.4.2)
- [ ] Revoke list: avatar + peer title + status + "Revoke" link (red) (§21.4.2)
- [ ] Revoke confirmation -> release all collectible links (§21.4.2)
- [ ] Premium upsell button (non-Premium): "Increase Limit" with gradient (§21.4.2)
- [ ] Plain close button for Premium/non-eligible (§21.4.2)

### 21.4 Buttons
- [ ] "Save" + "Skip"/"Cancel" buttons (§21.4)

### 21.5 Edit Peer Type Box
- [ ] Width 364px (§21.5)
- [ ] Privacy radios: `editPeerPrivacyBoxCheckbox` with margins (0,8,0,8) (§21.5)
- [ ] Explanation labels: min width 220px, `windowSubTextFg`, margins (42,0,34,0) (§21.5)
- [ ] Bottom skip: 16px (§21.5)
- [ ] Username section (public): draggable usernames list for collectible usernames (§21.5)
- [ ] Invite link section (private): permanent link block with copy/share (§21.5)

### 21.5.1 Group Permission Toggles
- [ ] Row anatomy: full-width button, icon left, label, toggle right (§21.5.1)
- [ ] Toggle at `toggleSkip` from right edge (§21.5.1)
- [ ] Locked toggle: dimmed/unresponsive via `setLocked()` (§21.5.1)
- [ ] Separator between rows: `lineWidth` horizontal line (§21.5.1)
- [ ] "Only members can send messages" toggle (§21.5.1)
- [ ] "Slow mode" slider: 8 positions (0/5/10/30/60/300/900/3600 seconds) (§21.5.1)
- [ ] Slow mode step labels: Off, 5s, 10s, 30s, 1min, 5min, 15min, 1h (§21.5.1)
- [ ] "Topics" row (conditional, forum): `manageGroupTopicsButton` with "NEW" badge (§21.5.1)
- [ ] "Approve New Members" toggle nested under "Only Members" (§21.5.1)
- [ ] "Restrict Saving Content" toggle (§21.5.1)
- [ ] Color tokens: `windowBg` bg, `windowBoldFg`/`windowSubTextFg` labels, `toggleActiveFg` on, `shadowFg` separator (§21.5.1)

### 21.6 Complete Flow Sequences
- [ ] Create Group: InfoBox -> MemberPicker -> API -> chat (§21.6)
- [ ] Create Channel: InfoBox -> API -> SetupChannelBox -> MemberPicker -> channel (§21.6)

---

## 22. Forum Topics UI

### 22.1 Topic Data Model
- [ ] ForumTopic fields: rootId, title, colorId, iconId, creatorId, creationDate, flags (§22.1)
- [ ] General topic: rootId = 1 (§22.1)
- [ ] Capabilities: canEdit, canDelete, canToggleClosed, canTogglePinned (§22.1)

### 22.2 Topic Icon System

#### Predefined Colors
- [ ] 6 predefined colors: blue (0x6FB9F0), yellow (0xFFD67E), violet (0xCB86DB), green (0x8EEE98), rose (0xFF93B2), red (0xFB6F5F) (§22.2)
- [ ] SVG files at `:/gui/topic_icons/{name}.svg` (§22.2)
- [ ] SVG viewBox 84x84, speech-bubble-with-tail silhouette (§22.2.1)
- [ ] Body: top-to-bottom linear gradient fill + gradient stroke (2.95px) (§22.2.1)
- [ ] Inner highlight arc at top-left, 37.5% opacity (§22.2.1)
- [ ] Color selection picks SVG file, NOT runtime hue shift (§22.2.1)

#### Default Icon Rendering
- [ ] Colored circle + first non-emoji letter, centered in white (§22.2)
- [ ] `defaultForumTopicIcon`: 21px, bold 11px, textTop 2px (§22.2)
- [ ] `normalForumTopicIcon`: 19px, bold 10px, textTop 2px (§22.2)
- [ ] `largeForumTopicIcon`: 26px, bold 13px, textTop 3px (§22.2)
- [ ] `infoForumTopicIcon`: 32px, bold 15px, textTop 4px (§22.2)
- [ ] Z-order: background SVG first, then letter overlay (white, no shadow) (§22.2.2)
- [ ] DPR-aware rendering (§22.2.1)

#### General Topic Icon
- [ ] `general.svg`: 20x20 viewBox, stylized hash shape (§22.2)
- [ ] Source fill white, recolored at paint time by palette (§22.2)
- [ ] Colors: `dialogsTextFg` normal, `dialogsTextFgOver` hover, `dialogsTextFgActive` active (§22.2)
- [ ] Re-rendered on palette changes (§22.2)
- [ ] No color-background underneath (§22.2.2)

#### Custom Emoji Icon
- [ ] When `iconId != 0`: loaded via `CustomEmojiManager` (§22.2)
- [ ] Loops once then freezes (§22.2)
- [ ] Painted directly, no bubble-shape background (§22.2.2)
- [ ] Narrow-mode centering: re-center in context rect (§22.2.2)
- [ ] Context text color: `dialogsNameFgActive` / `dialogsNameFgOver` / `dialogsNameFg` (§22.2.2)

### 22.3 Forum Topic List Layout
- [ ] Topic list replaces normal message history when forum opened (§22.3)
- [ ] Topic row: 54px height, padding 8/7/10/7px (§22.3)
- [ ] Icon: 20px (photoSize), nameLeft 39px, nameTop 7px (§22.3)
- [ ] Text preview: textLeft 39px, textTop 29px (§22.3)
- [ ] Unread mark: 8px diameter (§22.3)
- [ ] Each row paints: icon, name (semibold), closed lock (if closed), date, preview, badges, pin icon (§22.3)
- [ ] NO separator lines between rows (§22.3.1)
- [ ] Row states: transparent (idle), `dialogsBgOver` (hover), `dialogsBgActive` (active) (§22.3.1)
- [ ] Ripple: `dialogsRipple` on click (§22.3.1)

### 22.4 Forum Group in Main Chat List
- [ ] Forum group row: 80px height (96px with tags) (§22.4)
- [ ] TopicsView: up to 8 recent topic names horizontally (§22.4)
- [ ] Unread topics in bold (§22.4)
- [ ] Inter-title gap: 8px normal, 14px after jump bubble (§22.4)
- [ ] Topic jump bubble: rounded (radius 11px), padding 8/3/8/3px (§22.4)
- [ ] Arrow icon in jump bubble (§22.4)
- [ ] Click navigates to topic (§22.4)
- [ ] Two-rect stepped outline for multi-line spanning (§22.4)
- [ ] Expanded bar: `dialogsBgActive`, `roundRadiusLarge`, animated 0.0-1.0 (§22.4)
- [ ] Topics preview height: 21px (§22.4)

### 22.5 Create / Edit Topic Dialog
- [ ] `EditForumTopicBox` -- `GenericBox`, max height 408px (§22.5)
- [ ] Title input: `defaultInputField`, margin 70/2/22/18px (§22.5)
- [ ] Placeholder: "Topic Name" (or "Bot Thread Title" for bots) (§22.5.1)
- [ ] Icon button at (24, 19): shows custom emoji or default circle at 26px (§22.5)
- [ ] Click cycles to random next color (from remaining pool) (§22.5.1)
- [ ] Color cycling disabled when custom emoji set or editing existing topic (§22.5.1)
- [ ] Divider text: "Choose a title and an icon for the topic" (§22.5)
- [ ] Not shown for General topic (§22.5.1)
- [ ] Icon selector panel: `EmojiListWidget` in `Mode::TopicIcon` (§22.5)
- [ ] Recent section: default icon sentinel + server emoji set (§22.5.1)
- [ ] Non-default custom emoji require Premium (toast on non-Premium select) (§22.5.1)
- [ ] Fly animation: `EmojiFlyAnimation` from selector to icon button (§22.5)
- [ ] Shadow separator below pinned-top cover (§22.5.1)
- [ ] Auto-title reactivity: icon re-renders with new first letter on typing (§22.5)
- [ ] Create: validates non-empty title, reserves local ID, navigates to topic (§22.5)
- [ ] Save: calls `EditForumTopic` API, General topic cannot change icon (§22.5)
- [ ] Title `showError()` on empty title submit (§22.5.1)
- [ ] Box title: "New Topic" (creating) / "Edit Topic" (editing) (§22.5.1)

### 22.6 Topic Header Bar
- [ ] Standard `info_top_bar`, height 54px (§22.6)
- [ ] Back button -> topic list (§22.6)
- [ ] Title with icon prefix, optional subtitle (§22.6)
- [ ] Selection mode: cancel + count + forward/delete (§22.6)

### 22.7 Topic Info Panel
- [ ] Third column (or full-screen push in one-column) (§22.7)
- [ ] Cover height: 77px (§22.7)
- [ ] Icon: 36x36px at (22, 18) (§22.7)
- [ ] Name at (79, 14), status at (79, 38) (§22.7)
- [ ] General icon: `windowSubTextFg` (§22.7)
- [ ] Custom emoji: loaded at cover size (§22.7)
- [ ] Default: 32px circle with bold 15px letter (§22.7)
- [ ] Sections: notifications toggle, shared media, members list, topic link (§22.7)

### 22.8 Topic Context Menus

#### Topic List Right-Click
- [ ] Create Topic (§22.8)
- [ ] View Group Info (§22.8)
- [ ] View as Messages (§22.8)
- [ ] Search (if >1 topic) (§22.8)
- [ ] Manage Group, Add Members, Video Chat (§22.8)
- [ ] Report, Leave/Join (§22.8)

#### Specific Topic Row Right-Click
- [ ] New Window (always shown) (§22.8.1)
- [ ] Pin/Unpin (admin only, `canTogglePinned`) (§22.8.1)
- [ ] View Info (conditional on setting) (§22.8.1)
- [ ] Mute submenu (suppressed on self, sublist, forum-group row) (§22.8.1)
- [ ] Mark Read/Unread (`canToggleUnread`) (§22.8.1)
- [ ] Close/Reopen (`canToggleClosed`, label flips on state) (§22.8.1)
- [ ] Add to Folder (requires filters + chatlist) (§22.8.1)
- [ ] Clear History (§22.8.1)
- [ ] Delete Topic (`canDelete`, red attention, hard-blocked on General) (§22.8.1)
- [ ] Conditional matrix: admin vs creator vs non-admin, General vs closed vs pinned (§22.8.1)

#### Inside Topic (Burger Menu)
- [ ] Mute, Create Topic, Topic/Group Info, View as Topics (§22.8)
- [ ] Manage Group, standard items (§22.8)

#### Topic Info Panel Menu
- [ ] TTL, Copy Topic Link, Edit Topic, Close/Reopen (§22.8)
- [ ] Standard profile items, Delete Topic (§22.8)
- [ ] Edit Topic: profile menu only, requires `canEdit` (§22.8.1)
- [ ] Copy Topic Link: profile menu only, requires public channel (§22.8.1)

### 22.9 General Topic
- [ ] rootId = 1 (§22.9)
- [ ] Cannot be deleted (§22.9)
- [ ] Cannot change icon (uses `general.svg`) (§22.9)
- [ ] Can be hidden (§22.9)
- [ ] Title prefixed with "# " in rich text (§22.9)

### 22.10 Navigation & Column Integration
- [ ] One-column: forum replaces dialog list, back returns to main (§22.10)
- [ ] Two/three-column: topic list in dialog column, topics in chat, info in third (§22.10)
- [ ] "View as Messages/Topics" toggle, saves preference (§22.10)
- [ ] Loading: first 20 topics, then 500/page, stale refresh 100/request (§22.10)
- [ ] Auto-preload when <20 topics loaded (§22.10)
- [ ] Recent topics for chat list: 8 (§22.10)

### 22.11 Animations
- [ ] Userpic loop reset: after `slideDuration`, custom emoji stops and frees memory (§22.11)
- [ ] Topic jump ripple: standard `dialogsRipple` (§22.11)
- [ ] Expanded bar: 0.0-1.0 float drives left-edge bar animation (§22.11)
- [ ] Icon fly: `EmojiFlyAnimation` in edit dialog (§22.11)
- [ ] Highlight: info top bar fade between `bg` and `highlightBg` (§22.11)

# GUI Implementation Checklist: Sections 23-29

## 23. Scheduled Messages

### 23.1 Data Model
- [ ] Implement remapped scheduled message ID space with `ServerMaxMsgId + 1` offset (S23.1)
- [ ] Handle `kScheduledUntilOnlineTimestamp = 0x7FFFFFFE` magic value for "send when online" (S23.1)
- [ ] Enforce `kMinimalSchedule = 10` seconds minimum scheduling offset (S23.1)
- [ ] Enforce 1-year maximum scheduling horizon (S23.1)
- [ ] Implement `isScheduled()`, `allowsSendNow()`, `allowsReschedule()` item predicates (S23.1)
- [ ] Implement `scheduleRepeatPeriod()` with repeat interval tracking (S23.1)
- [ ] Support `isSilent()` flag on scheduled messages (S23.1)
- [ ] Implement `SendMenu::Type` enum: Scheduled, ScheduledToUser, Reminder, SilentOnly (S23.1)
- [ ] Implement `CanScheduleUntilOnline(peer)` check (non-self, non-bot, last-seen visible) (S23.1)

### 23.2 Schedule Picker Dialog
- [ ] Build `ChooseDateTimeBox` as a GenericBox, width 364px (`boxWideWidth`) (S23.2)
- [ ] Content row fixed height 95px (`scheduleHeight`) with centered date/time row (S23.2)
- [ ] Date field: 136px wide, InputField at y=38px, text margins 2/0/2/0px, min height 30px (S23.2)
- [ ] Time field: 72px wide, InputField at y=38px, min height 28px, HH:MM format (S23.2)
- [ ] "at" label: centered between fields, y=42px, 24px skip on each side (S23.2)
- [ ] Center all three elements as a group with symmetric padding calculation (S23.2)
- [ ] Date field click opens CalendarBox overlay (S23.2)
- [ ] Date field mouse-wheel increments/decrements date by one day, clamped to min/max (S23.2)
- [ ] After date selection, focus moves to time field (S23.2)
- [ ] Time separator ":" glyph, 14px font, padding 2/0/2/0px (S23.2)
- [ ] Time field validation on Enter: invalid time triggers `showError()` shake animation (S23.2)
- [ ] Dynamic title: "Schedule message" vs "Set a reminder" for self-chat (S23.2)
- [ ] Submit button label: "Schedule" (S23.2)
- [ ] Silent shortcut: holding Ctrl when confirming schedules silently (S23.2)
- [ ] Default schedule time: now + 600 seconds (S23.2)
- [ ] "Send when online" button: top-right IconButton, PopupMenu with single action, only for ScheduledToUser (S23.2)
- [ ] Repeat period widget below date/time row with dropdown label "Repeat: {period}" (S23.2)
- [ ] Repeat period dropdown: default PopupMenu (no icons), 8 period options + test-mode extras (S23.2)
- [ ] Non-Premium users: lock icon inline in label, clicking opens Premium promo toast (S23.2)
- [ ] Premium users: dropdown arrow icon inline in label (S23.2)
- [ ] RTL layout: swap Date and Time slots, keep 24px spacing symmetric (S23.12.1)

### 23.3 Scheduled Messages Toggle Button
- [ ] Clock icon button in compose area, 44x46px, ripple area 40px at (2,3) offset (S23.3)
- [ ] Two-layer icon: `chat/input_scheduled` + red attention dot `chat/input_scheduled_dot` (S23.3)
- [ ] Normal color `historyComposeIconFg`, hover `historyComposeIconFgOver` (S23.3)
- [ ] Position: right side of compose area, right-to-left button layout order (S23.3)
- [ ] Dynamic visibility: created when scheduled count > 0, destroyed when count = 0 (S23.3)
- [ ] Click opens ScheduledWidget section with horizontal slide transition (S23.3)

### 23.4 Scheduled Messages Section
- [ ] Full SectionWidget replacing main chat column (S23.4)
- [ ] Top bar title: "Reminders" (self-chat) or "Scheduled messages" (other), `historySavedFont` (S23.4)
- [ ] No status line or online indicator in top bar (S23.4)
- [ ] Selection mode top bar: "Send Now" + "Delete" + "Clear selection (x)" buttons (S23.4)
- [ ] Top bar "..." menu: only "Create Poll" and "Create To-do List" actions (S23.4)
- [ ] Standard ListWidget with ScrollArea, messages sorted by scheduled date (S23.4)
- [ ] Empty state: service-style bubble with "No scheduled messages" in semibold (S23.4)
- [ ] Date separators: "Scheduled for {date}" or "Scheduled until online" (S23.4)
- [ ] Auto-scroll to newly added scheduled message (S23.4)
- [ ] Full ComposeControls in Scheduled mode: every send opens schedule picker (S23.4)
- [ ] File drag-and-drop support with "Photo" and "Document" drop zones (S23.4)
- [ ] Only "scroll to bottom" corner button, no unread counter (S23.4)
- [ ] Section enter: horizontal slide from right with animation controls (S23.4)
- [ ] Section exit: slide back left on Escape or showBackFromStack (S23.4)

### 23.5 Message Rendering in Scheduled View
- [ ] Timestamp display shows scheduled delivery time HH:MM in bottom-info (S23.5)
- [ ] Repeat period prefix in timestamp: daily/weekly/biweekly/monthly/etc. (S23.5)
- [ ] Video processing prefix: approximate label instead of repeat period (S23.5)
- [ ] Silent indicator: muted bell emoji U+1F515 appended to tooltip on new line (S23.5, S23.12.5)
- [ ] No on-bubble visual indicator for silent; tooltip only (S23.12.5)
- [ ] Timestamp hover tooltip: full datetime + message ID, silent emoji if applicable (S23.5)
- [ ] Multi-select allowed; items selectable only if not sending and not failed (S23.5)

### 23.6 Context Menu Actions
- [ ] "Send now" single message: condition `allowsSendNow()`, icon `menuIconSend` (S23.6)
- [ ] "Send now" grouped: all group items must allow send-now (S23.6)
- [ ] "Send now selected": all selected items canSendNow, icon `menuIconSend` (S23.6)
- [ ] Send Now confirmation dialog: single vs multiple message text variants (S23.6)
- [ ] Messages sorted by date before sending (S23.6)
- [ ] "Reschedule" single: condition `allowsReschedule()`, icon `menuIconReschedule` (S23.6)
- [ ] "Reschedule selected": max 20 messages (`kRescheduleLimit`), icon `menuIconReschedule` (S23.6)
- [ ] Reschedule action: pre-filled date/repeat period, per-peer SendMenu::Type logic (S23.6)
- [ ] Reschedule multiple: +1 second offset per subsequent message for ordering (S23.6)
- [ ] Grouped messages deduplicated during reschedule (S23.6)
- [ ] Auto-close reschedule box if item deleted during dialog (S23.6)
- [ ] Edit action preserves `scheduleRepeatPeriod` (S23.6)
- [ ] Delete via DeleteMessagesBox (S23.6)

### 23.7 Sent-to-Scheduled Toast & Navigation
- [ ] Auto-navigate to ScheduledWidget on `sentToScheduled` event, scrolled to new message (S23.7)

### 23.8 Video Processing Flow
- [ ] Stage 1: top-attached toast with title/text, 4000ms duration (S23.8)
- [ ] Stage 2: ImportantTooltip bubble anchored to effect icon, RectPart::Top, 8px shift (S23.8)
- [ ] Tooltip: dark rounded rectangle (~8px radius), white text, mouse-transparent (S23.12.3)
- [ ] Tooltip auto-hides after 4000ms with fade animation (S23.8)
- [ ] Published notification toast: rounded video thumbnail + bold text + "View" button (S23.8)
- [ ] Toast: top-attached, 4000ms, padding 19/17/19/17, max width 380px (S23.8, S23.12.4)
- [ ] Preview: moveToLeft(8,8), size = font.height*2, radius ImageRoundRadius::Small (S23.12.4)
- [ ] "View" button: right-aligned, vertically centered, navigates to message in history (S23.12.4)
- [ ] Right-click on toast dismisses it (S23.8)

### 23.9 Forum Topic Support
- [ ] ScheduledWidget supports ForumTopic filtering (S23.9)
- [ ] Context switches to `Context::ScheduledTopic` (S23.9)
- [ ] Send actions include `topicRootId` in reply-to structure (S23.9)
- [ ] Write restrictions respect both peer-level and topic-level closed state (S23.9)

### 23.10 Animations & Timing
- [ ] Section enter/exit slide: 150-200ms (S23.10)
- [ ] Schedule box open: standard box animation (S23.10)
- [ ] Calendar popup open: standard layer animation (S23.10)
- [ ] Selection bar appear/disappear: standard top-bar animation (S23.10)
- [ ] Corner button show/hide: standard corner button animation (S23.10)
- [ ] Video tooltip appear/dismiss: fade, 4000ms auto-hide (S23.10)
- [ ] Published toast: 4000ms duration (S23.10)
- [ ] Date field wheel scroll: immediate, no animation (S23.10)
- [ ] Time field error: showError() shake animation (S23.10)

---

## 24. Keyboard Shortcuts

### 24.1 Architecture
- [ ] Implement Command enum with 70+ shortcut commands (S24.1)
- [ ] Reactive event stream for command dispatch with priority-based handlers (S24.1)
- [ ] Auto-repeat support for ChatPrevious/Next, ChatFirst/Last, MediaPrevious/Next (S24.1)
- [ ] Global pause/unpause mechanism for shortcut recording in Settings (S24.1)

### 24.2 Shortcut Customization
- [ ] Write `shortcuts-default.json` on startup with all current default bindings (S24.2)
- [ ] Load `shortcuts-custom.json` to override/add/remove bindings, max 2048 entries (S24.2)
- [ ] Custom file format: JSON array with command/keys objects, null command to disable (S24.2)
- [ ] macOS note in custom file about ctrl/meta mapping (S24.2)
- [ ] Settings UI: list every command grouped by category with separators (S24.2)
- [ ] Row layout: command label left, key binding right (S24.2)
- [ ] Left-click row enters recording mode: green italic "Recording..." text (S24.2)
- [ ] Press any key combination to assign; Escape to cancel; Backspace/Delete to clear (S24.2)
- [ ] Right-click row: popup menu "Add another binding" for multiple key sequences (S24.2)
- [ ] Conflict detection: old binding shows strikethrough in red (`attentionButtonFg`) (S24.2)
- [ ] "Reset to defaults" button in SlideWrap, visible only when bindings differ (S24.2)
- [ ] macOS key display symbols: Cmd U+2318, Ctrl U+2303, Alt U+2325, Shift U+21E7 (S24.2)
- [ ] Reject bare letter/number keys without modifiers; allow bare function/media keys (S24.2)

### 24.3 Platform Modifier Mapping
- [ ] Map primary modifier: Ctrl on Win/Linux, Cmd on macOS (S24.3)
- [ ] Map secondary modifier: Alt on Win/Linux, Option on macOS (S24.3)
- [ ] Text formatting shortcuts use platform-native sequences (Cmd+B on mac) (S24.3)

### 24.4 Default Shortcuts — Application/Window
- [ ] Ctrl+W / Ctrl+F4: close window (S24.4)
- [ ] Ctrl+L: lock app (requires passcode) (S24.4)
- [ ] Ctrl+M: minimize window (S24.4)
- [ ] Ctrl+Q: quit application (S24.4)
- [ ] Ctrl+F: open search in current context (S24.4)

### 24.4 Default Shortcuts — Chat Navigation
- [ ] Ctrl+Tab / Ctrl+Shift+Tab: chat switcher overlay (S24.4)
- [ ] Ctrl+PgDn / Alt+Down: next chat (S24.4)
- [ ] Ctrl+PgUp / Alt+Up: previous chat (S24.4)
- [ ] Ctrl+Alt+Home / Ctrl+Alt+End: first/last chat (S24.4)
- [ ] Ctrl+0: Saved Messages (S24.4)
- [ ] Ctrl+9: Archived Chats (S24.4)
- [ ] Ctrl+J: Contacts (S24.4)

### 24.4 Default Shortcuts — Pinned & Folders
- [ ] Ctrl+1 through Ctrl+8: pinned chats (S24.4)
- [ ] Folder shortcuts Ctrl+1-8: all chats + folders 1-6 + last folder (S24.4)
- [ ] Ctrl+Shift+Down/Up: next/previous folder (S24.4)
- [ ] Folder commands take priority over pinned when folders exist (S24.12.2)

### 24.4 Default Shortcuts — Account Switching
- [ ] Account1-6 commands exist but are unbound by default (S24.4, S24.12.1)

### 24.4 Default Shortcuts — Chat Actions
- [ ] Ctrl+R: mark chat as read / start voice recording (dual-bound) (S24.4)
- [ ] Ctrl+\\: show chat context menu (S24.4)
- [ ] Ctrl+]: show chat preview popup (S24.4)

### 24.4 Default Shortcuts — Media Playback
- [ ] Hardware media keys: play, pause, playpause, stop, previous, next (S24.4)
- [ ] Media shortcuts toggled on/off with active media player (S24.4)

### 24.5 Ctrl+Tab Chat Switcher
- [ ] Modal overlay widget: 72x104px cells, margins 16px, padding 12px (S24.5, S24.12.3)
- [ ] Semi-transparent overlay background, rounded-rect panel with boxRoundShadow (S24.12.3)
- [ ] Each button: centered userpic on top + name label below, 6px side skip (S24.12.3)
- [ ] Userpic top padding 8px, selection ring outline 3px with boxRoundShadow.bgActive (S24.12.3)
- [ ] Grid layout: auto-sized to window width, max 7 per row for multi-row, max 4 for 3+ rows (S24.12.3)
- [ ] Navigation: Tab/Right next, Shift+Tab/Left previous, Up/Down by row (S24.5)
- [ ] Q key removes selected chat from recent history (S24.12.3)
- [ ] Enter/release Ctrl confirms selection, Escape cancels (S24.5)
- [ ] Content from `recentPeers().collectChatOpenHistory()`, min 2 entries (S24.12.3)
- [ ] Forum topic variant with TopicIconButton + small badge userpic (S24.12.3)
- [ ] Hover triggers selection mirroring keyboard selection (S24.12.3)

### 24.6 Compose Box Key Handling
- [ ] Submit settings: Enter, CtrlEnter, Both, None modes (S24.6)
- [ ] Enter/Return: send or newline based on submit mode (S24.6)
- [ ] Shift+Enter: insert newline (Enter mode) or send (Both mode) (S24.6)
- [ ] Ctrl+Enter: send (CtrlEnter/Both mode) (S24.6)
- [ ] Ctrl+Shift+Enter: always sends (S24.6)
- [ ] Escape: cancel current action (reply/edit) (S24.6)
- [ ] Tab: trigger autocomplete (emoji/mention/command) (S24.6)
- [ ] Up arrow (empty field): edit last sent message (S24.6)
- [ ] Ctrl+Up/Down: reply navigation to previous/next message (S24.6)
- [ ] PageUp/PageDown: scroll chat history (S24.6)
- [ ] Ctrl+O: open file picker to attach file (S24.6)
- [ ] Ctrl+Shift+V: paste as plain text (S24.6)
- [ ] Three consecutive Enters inside blockquote exits the block (S24.6)

### 24.7 Message History Key Handling
- [ ] Escape: cancel reply/edit/search or navigate back (S24.7)
- [ ] PageDown/PageUp: scroll down/up (S24.7)
- [ ] Up (empty field, no edit/reply): edit last editable message or open EditCaptionBox (S24.7)
- [ ] Ctrl+Up/Down: reply navigation, skipping local messages (S24.7)
- [ ] Enter: send /start if bot start button visible (S24.7)

### 24.8 Text Formatting Shortcuts
- [ ] Ctrl+B / Cmd+B: Bold (S24.8)
- [ ] Ctrl+I / Cmd+I: Italic (S24.8)
- [ ] Ctrl+U / Cmd+U: Underline (S24.8)
- [ ] Ctrl+Shift+X / Cmd+Shift+X: Strikethrough (S24.8)
- [ ] Ctrl+Shift+M / Cmd+Shift+M: Monospace (S24.8)
- [ ] Ctrl+Shift+. / Cmd+Shift+.: Blockquote (S24.8)
- [ ] Ctrl+Shift+P / Cmd+Shift+P: Spoiler (S24.8)
- [ ] Ctrl+Shift+N / Cmd+Shift+N: Clear formatting (S24.8)
- [ ] Ctrl+K / Cmd+K: Insert/edit link (opens EditLinkBox) (S24.8, S24.12.4)
- [ ] Ctrl+Shift+D / Cmd+Shift+D: Insert/edit date (S24.8)
- [ ] EditLinkBox: two-field dialog (display text + URL), boxWidth, tab focus cycling (S24.12.4)
- [ ] EditCodeLanguageBox: single field, regex validation, max kCodeLanguageLimit chars (S24.12.4)
- [ ] Context menu shows formatting actions with shortcut strings (S24.8)

### 24.9 Media Viewer Shortcuts
- [ ] Left/Right: previous/next media item (S24.9)
- [ ] Escape: close viewer or exit fullscreen (S24.9)
- [ ] Ctrl+S / Ctrl+Shift+S: save as (S24.9)
- [ ] Ctrl+C: copy media to clipboard (S24.9)
- [ ] Enter/Return/Space: toggle play/pause or open document (S24.9)
- [ ] H/V: flip image horizontally/vertically (S24.9)
- [ ] K: toggle play/pause (video) (S24.9)
- [ ] Space hold: speed boost (300ms hold delay) (S24.9)
- [ ] J/L: seek backward/forward 10 seconds (S24.9)
- [ ] Left/Right (fullscreen): seek backward/forward 5 seconds (S24.9)
- [ ] Alt+Enter / Ctrl+Enter: toggle fullscreen (S24.9)
- [ ] 0-9 (fullscreen): seek to 0%-90% of duration (S24.9)
- [ ] Period/Comma (paused): step forward/backward one frame, 150ms throttle (S24.9)
- [ ] Alt+Left/Right: jump to previous/next chapter (S24.9)
- [ ] Ctrl+Plus/Minus/Scroll: zoom in/out (disabled in fullscreen video) (S24.9)
- [ ] Scroll without Ctrl: previous/next media item (S24.9)
- [ ] Stories mode: Space toggles pause/resume (S24.9)

### 24.10 Support Mode Shortcuts
- [ ] F5: reload templates (S24.10)
- [ ] Ctrl+Delete: toggle muted (S24.10)
- [ ] Ctrl+Insert: scroll to current (S24.10)
- [ ] Ctrl+Shift+X: support history back (conflicts with strikethrough) (S24.10)
- [ ] Ctrl+Shift+C: support history forward (S24.10)
- [ ] Support templates panel: max height ~180px, docked above compose, search field (S24.12.5)

### 24.11 Scope & Priority
- [ ] Global shortcuts: always active when app has focus (S24.11)
- [ ] Context-specific shortcuts: require specific widget focus (S24.11)
- [ ] Priority system: higher priority handler wins for same command (S24.11)
- [ ] Focus chain gating: check InFocusChain, AppInFocus, isActiveWindow, !isLayerShown (S24.11)

### 24.12 Settings Shortcuts UI
- [ ] Settings screen under Chat Settings, icon `menuIconShortcut` (S24.12.6)
- [ ] "Reset to defaults" button in SlideWrap, visible only when modified (S24.12.6)
- [ ] Reset button style: `settingsButtonNoIcon`, label `lng_shortcuts_reset` (S24.12.6)
- [ ] Entry rows: SettingsButton with right-hand key label via FlatLabel (S24.12.6)
- [ ] Right-hand label positioned at `settingsButtonRightSkip` from right (S24.12.6)
- [ ] Recording state: green italic "Recording..." text in `boxTextFgGood` (S24.12.6)
- [ ] Conflict state: strikethrough in red `attentionButtonFg` (S24.12.6)
- [ ] Right-click popup: "Add another binding" with `menuIconTopics` (S24.12.6)
- [ ] Recording state machine: modifier-only press stays recording, Backspace clears (S24.12.6)
- [ ] 11 separator rows chunking commands into visual groups (S24.12.6)

---

## 25. Theming & Color System

### 25.1 Palette Architecture
- [ ] Single global palette with ~370 named color tokens (S25.1)
- [ ] Token format: `tokenName: #rrggbb;` or `#rrggbbaa;` or reference to other token (S25.1)
- [ ] Reference resolution at load time, no forward references (S25.1)
- [ ] Max scheme file size 1 MB (S25.1)
- [ ] Token hierarchy: window-level -> component -> domain-specific (S25.1)

### 25.2 Color Token Reference
- [ ] Implement all window/global tokens: windowBg, windowFg, windowBgOver, windowBgRipple, etc. (S25.2.1)
- [ ] Implement all button tokens: activeButton*, lightButton*, attentionButton*, outlineButton* (S25.2.2)
- [ ] Implement dialog list tokens: dialogsBg, dialogsNameFg, dialogsDateFg, etc. (S25.2.3)
- [ ] Implement message bubble tokens: msgInBg, msgOutBg, msgServiceBg, etc. (S25.2.4)
- [ ] Implement 8 peer name colors cycling by user ID (fixed across themes) (S25.2.5)
- [ ] Implement 4 file type color groups (blue/green/red/yellow) with 4 states each (S25.2.6)
- [ ] Implement voice waveform tokens: active/inactive for in/out (S25.2.7)
- [ ] Implement media viewer tokens: overlay bg, controls, caption, playback (S25.2.8)
- [ ] Implement intro/login tokens: cover gradients, plane icons (S25.2.9)
- [ ] Implement scroll bar tokens: day dark-on-light, night light-on-dark (S25.2.10)

### 25.3 Built-in Themes
- [ ] Default (Classic Day): accent #40a7e3, outgoing #eaffdc (S25.3.1)
- [ ] Day Blue: accent #40a7e3, outgoing #d7f0ff, 369 tokens (S25.3.2)
- [ ] Night (Tinted): accent #5288c1, 467 tokens, dark flag (S25.3.3)
- [ ] Night Green: accent #3fc1b0, 467 tokens, dark flag (S25.3.4)
- [ ] Custom base themes for day/night colorizer canvas (S25.3.5)

### 25.4 Accent Color System
- [ ] 8 preset accent colors per theme type as circles in Settings (S25.4.1)
- [ ] Night palettes deliberately desaturated/darkened (S25.4.1)
- [ ] Accent circle UI: circle diameter, border width, selection ring skip (S25.4.2)
- [ ] Selection animation: 2x defaultRadio.duration (~200ms) (S25.4.2)
- [ ] Custom color button: 7 small circles (1 center + 6 around), opens color picker (S25.4.2)
- [ ] System accent color checkbox on Qt 6.6+ (S25.4.2)
- [ ] Colorizer algorithm: HSV shift, saturation scale, lightness clamp (S25.4.3)
- [ ] Day themes lightness clamp [0, 160], Night themes [64, 255] (S25.17.1)
- [ ] Hue threshold: 15 degrees minimum delta for recoloring (S25.17.1)
- [ ] 63-token colorize exclusion list (peer colors, file types, etc.) (S25.17.2)
- [ ] Night themes: keepContrast map for 10-12 element pairs (S25.4.3)
- [ ] Accent persistence: serialize per-theme-type as EmbeddedType -> QColor (S25.4.4)

### 25.5 Theme File Format
- [ ] .tdesktop-theme as ZIP archive, max 5 MB container (S25.5)
- [ ] Palette file named `colors.tdesktop-theme` or `colors.tdesktop-palette`, max 1 MB (S25.5)
- [ ] Background image: `background.*` (scaled) or `tiled.*` (repeating), JPEG/PNG (S25.5)
- [ ] Cloud theme metadata between SERVICE INFO comment markers (S25.5)

### 25.6 Theme Editor
- [ ] Editor layout: close button, menu toggle, search field, scrollable list, save button (S25.6.1)
- [ ] Min dimensions: windowMinWidth x windowMinHeight (S25.6.1)
- [ ] Search field filters rows by token name substring (S25.6.1)
- [ ] Palette entry row: color name, reference name, color swatch, description (S25.6.2)
- [ ] Swatch rendering: shadow, transparent checkerboard for alpha, solid fill (S25.6.2)
- [ ] Row states: normal dialogsBg, hover dialogsBgOver, active dialogsBgActive (S25.6.2)
- [ ] Ripple animation on click, keyboard navigation with arrows/PageUp/Down/Enter (S25.6.2)
- [ ] Color edit: hex input #RRGGBB or #RRGGBBAA, live preview via ApplyEditedPalette (S25.6.3)
- [ ] Export: ZIP with .tdesktop-theme extension (S25.6.4)
- [ ] Import: file dialog with theme/palette filter (S25.6.4)
- [ ] Editor geometry: close, menu toggle, search, topShadow, leftShadow, scroll, save (S25.17.3)
- [ ] Menu items: Export (menuIconExportTheme), Import (menuIconImportTheme), Show (menuIconPalette) (S25.17.3)

### 25.6.5 Save Theme Dialog
- [ ] SaveThemeBox: boxWideWidth, name field, link field (5-64 chars slug) (S25.6.5)
- [ ] Background section: thumbnail preview, "Choose from file", tile checkbox (S25.6.5, S25.17.3)
- [ ] Thumbnail rounding: ImageRoundRadius::Small (S25.17.3)
- [ ] JPEG export quality: 87 (S25.17.3)

### 25.7 Theme Name Generator
- [ ] Auto-generate names from accent color using weighted Euclidean distance (S25.7)
- [ ] Two patterns: "{Adjective} {ColorName}" or "{ColorName} {Subjective}" (S25.7)
- [ ] Word lists: 101 colors, 97 adjectives, 81 nouns (S25.7)

### 25.8 Chat Wallpaper System
- [ ] Four wallpaper types: Image, Pattern, Gradient, Solid (S25.8.1)
- [ ] Wallpaper flags: Pattern, Default, Creator, Dark (S25.8.1)
- [ ] backgroundColors: 1-4 QColor for gradient/solid (S25.8.2)
- [ ] patternIntensity: -100 to +100, default 50 (S25.8.2, S25.17.4)
- [ ] gradientRotation: snapped to 45-degree increments (S25.8.2)
- [ ] blurred flag for image wallpapers (S25.8.2)
- [ ] 2-color gradient: linear at specified rotation angle (S25.8.3)
- [ ] 3-4 color gradient: animated rotation with doubled base rotation (S25.8.3)
- [ ] Pattern rendering: SoftLight for positive intensity, DestinationIn for negative (S25.8.4, S25.17.4)
- [ ] Pattern inversion when positive intensity AND background HSV value <= 0.3 (S25.17.4)
- [ ] Images smaller than 512px tiled to minimum size (S25.8.4)
- [ ] Image processing: ARGB32_Premultiplied, max 2960px, blur radius 24 if blurred (S25.8.5)
- [ ] Built-in wallpaper IDs for Default, Legacy 2-4, Custom, Theme-bundled (S25.8.6)
- [ ] Wallpaper upload: JPEG 87% quality, 320px thumbnail (S25.8.7)
- [ ] Wallpaper URL format with slug, bg_color, intensity, rotation, mode params (S25.8.8)
- [ ] 6 adaptive service colors auto-adjust based on wallpaper average color (S25.8.9)
- [ ] ThemeAdjustedColor: transplant hue+saturation of wallpaper onto original lightness (S25.17.5)
- [ ] CountAverageColor: exhaustive pixel-level mean, BGRA byte order (S25.17.5)

### 25.9 Night Mode
- [ ] Dark detection: dialogsBg HSV value < 0.5 threshold (S25.9.1)
- [ ] Hamburger menu: inline toggle switch for Night Mode (S25.9.2)
- [ ] Settings: "Auto-Night Mode" checkbox reading system dark mode (S25.9.2)
- [ ] Separate tile settings for day/night (S25.9.2)
- [ ] Theme switch confirmation overlay: 16s countdown, "Keep Changes"/"Revert" (S25.9.3)
- [ ] Confirmation dimensions: themeWarningWidth x themeWarningHeight, rounded corners (S25.9.3)
- [ ] Fade in/out animation, boxDuration (S25.9.3)
- [ ] Escape triggers revert (S25.9.3)
- [ ] Theme revert mechanism: save palette before apply, restore on timeout/revert (S25.9.4)

### 25.10 Theme Caching
- [ ] Cache parsed themes: colors, background BMP, checksums, tile flag (S25.10)
- [ ] Skip parsing on launch if checksums match stored theme (S25.10)

### 25.11 Per-Chat Themes
- [ ] ChatThemeKey: {uint64 id, bool dark} for light/dark variants (S25.11.1)
- [ ] Bubble color derivation from accent/bubblesData (S25.11.2)
- [ ] Contrast validation: min ratio 1.14, flip text colors if below (S25.11.2)
- [ ] Background cache: fast 200ms, debounced 1000ms (S25.11.3)
- [ ] Background transition: 200ms fade animation (S25.11.3)
- [ ] Per-chat theme chooser: horizontal scrollable theme pills at chat bottom (S25.11.4)
- [ ] Theme pill: miniature background + sample bubbles + emoji indicator (S25.11.4)
- [ ] Selection ring: activeLineFg pen, borderActive width, outside card geometry (S25.17.6)
- [ ] Ring corner radius: roundRadiusLarge + offset (concentric with card) (S25.17.6)
- [ ] Control buttons: "Apply" and "Change Wallpaper" with defaultLightButton style (S25.17.6)
- [ ] Drag-to-scroll and wheel events on theme strip (S25.11.4)

### 25.12 Cloud Themes
- [ ] Cloud theme structure: id, accessHash, slug, title, emoticon, settings per dark/light (S25.12.1)
- [ ] Cloud theme grid: 4 per row, card with background preview + bubble indicators + radio (S25.12.2)
- [ ] CloudListCheck: settingsThemePreviewSize, ImageRoundRadius::Large, bubble rects (S25.17.7)
- [ ] Radio button contrast enforcement against local background average (S25.17.7)
- [ ] Ripple explicitly disabled on CloudListCheck (S25.17.7)
- [ ] Right-click context menu: Share, Edit (own + applied), Delete (S25.12.3)
- [ ] Theme sharing link format: `addtheme/{slug}` (S25.12.3)

### 25.13 Theme Preview
- [ ] Preview image at themePreviewSize with dialogs panel + message history layout (S25.13)
- [ ] 9 conversation rows with avatars, names, previews, timestamps, badges (S25.13)
- [ ] Sample message bubbles with attachments, tails, corners, delivery states (S25.13)

### 25.14 Settings — Chat Appearance
- [ ] 4 theme radio buttons arranged horizontally with preview colors (S25.14.1)
- [ ] Check mark at top corner of selected theme (S25.14.1)
- [ ] Background row: thumbnail, "Choose from gallery", "Choose from file", loading indicator (S25.14.2)
- [ ] Tile background checkbox (conditional on non-pattern) (S25.14.3)
- [ ] Adaptive wide mode checkbox (S25.14.3)
- [ ] Auto-night mode checkbox (S25.14.3)
- [ ] Font family picker with restart on change (S25.14.3)

### 25.15 AyuGram-Specific Theming
- [ ] Message bubble radius slider: 0-16, live preview, restart prompt (S25.15.1)
- [ ] Message tail removal toggle (S25.15.2)
- [ ] Material Design switches toggle (S25.15.3)
- [ ] Avatar corner radius slider with live preview (S25.15.4)
- [ ] Disable custom backgrounds toggle (S25.15.5)
- [ ] Simple quotes and replies toggle (S25.15.6)
- [ ] Semi-transparent deleted messages toggle (beta) (S25.15.7)
- [ ] Android-style palette extraction: 6 targets, median-cut quantization (S25.15.8)
- [ ] Message shot theme support (S25.15.9)
- [ ] Drawer menu theme toggle visibility controls (S25.15.10)

---

## 26. Admin Tools

### 26.1 Group/Channel Edit Screen
- [ ] EditPeerInfoBox: scrollable BoxContent dialog (S26.1)
- [ ] Photo: UserpicButton with Role::ChangePhoto, margins 22/8/22/8px (S26.1.2)
- [ ] Photo context menu: "Set Photo", "Set Video", "Remove Photo" (S26.1.2)
- [ ] Title field: editPeerTitleField, margins 27/13/22/8px, max 128 chars, auto-focused (S26.1.3)
- [ ] Description field: MultiLine, margins 22/3/22/2px, max 255 chars (S26.1.4)
- [ ] Settings buttons with icons and right-side value labels (S26.1.5)
- [ ] Group Type / Channel Type button with "Public"/"Private" value (S26.1.5)
- [ ] Discussion Group / Linked Channel button (S26.1.5)
- [ ] Direct Messages button (channels with monoforum): Off/Free/star amount (S26.1.5, S26.12.1)
- [ ] Visible History button: "Shown"/"Hidden" (S26.1.5)
- [ ] Topics button: "Off"/"Tabs"/"List" (S26.1.5)
- [ ] Auto-Translation toggle (channels at boost level) (S26.1.5)
- [ ] Sign Messages toggle (channels) (S26.1.5)
- [ ] Sign with Profile toggle (slides in when Sign on) (S26.1.5)
- [ ] Admin control buttons: Permissions, Invite Links, Admins, Members, Removed, Join Requests (S26.1.6)
- [ ] Sticker set section (groups only): "Group Stickers" with "Add Stickers" button (S26.1.7)
- [ ] Delete button: `manageDeleteGroupButton` red style, confirmation dialog (S26.1.8)
- [ ] Dialog chrome: "Edit Group"/"Edit Channel"/"Edit Bot" title, Save + Cancel (S26.1.9)

### 26.2 Permissions Management
- [ ] Permission toggle rows: rightsButton style, 22/8/22/8px padding, 20px toggle skip (S26.2.1)
- [ ] Toggle colors: allowed = windowBgActive, restricted = attentionButtonFg (S26.2.1)
- [ ] Lock icon for non-editable permissions (S26.2.1)
- [ ] Group 1 (Text): SendOther toggle (S26.2.1)
- [ ] Group 2 (Media): collapsible with expand/collapse arrow, checked count badge (S26.2.1)
- [ ] 7 media permission toggles: photos, videos, video messages, music, voice, files, stickers (S26.2.1)
- [ ] Expand/collapse animation: slideWrapDuration, easeOutCubic (S26.2.1)
- [ ] Group 3 (Other): 7 toggles including EmbedLinks, SendPolls, AddParticipants, etc. (S26.2.1)
- [ ] Permission dependency rules: EmbedLinks requires SendOther, all send require ViewMessages (S26.2.1, S26.12.2)
- [ ] Stickers/GIFs/Games/Inline bidirectional equivalence class (S26.12.2)
- [ ] Locked permission toast: 3000ms duration (S26.2.1)
- [ ] Exceptions list: "Add Exception" button, user picker, custom restrictions (S26.2.2)
- [ ] Slowmode slider: 8 discrete positions (Off, 5s, 10s, 30s, 1m, 5m, 15m, 1h) (S26.2.3)
- [ ] Slowmode label positioning: first/last aligned to edges, middle centered (S26.2.3)
- [ ] Boosts unrestrict slider: 5 positions with boost emoji + count (S26.2.4)
- [ ] Charge Stars section for channels with paidMessagesAvailable (S26.2.5)
- [ ] Direct Messages price box: MediaSliderWheelless, non-linear scale, commission label (S26.12.1)
- [ ] Convert to Supergroup suggestion at 1000+ members (S26.2.6)

### 26.3 Individual Member Restrict/Ban Dialog
- [ ] Cover widget: 60x60px photo, name at 109px/33px, status at 109px/57px (S26.3.1)
- [ ] Photo margin: 20/0/15/18px (S26.3.1)
- [ ] Per-user permission toggles matching group defaults (S26.3.2)
- [ ] Duration picker radio group: Forever, 1 Day, 1 Week, Custom (S26.3.3)
- [ ] Max restrict delay: 366 days (S26.3.3)
- [ ] Custom rank field via EditTagControl (S26.3.4)
- [ ] Save + Cancel buttons (S26.3.5)

### 26.4 Admin Appointment Dialog
- [ ] Cover widget: same layout as 26.3 (S26.4.1)
- [ ] "Add as Admin" checkbox with collapsible admin controls SlideWrap (S26.4.2)
- [ ] Admin rights header: "What can this admin do?" semibold windowActiveTextFg (S26.4.3)
- [ ] Group admin rights: 3 sections (Core, Stories, Meta) with toggles (S26.4.3)
- [ ] Channel admin rights: 4 sections with PostMessages, EditMessages, etc. (S26.4.3)
- [ ] ManageDirect admin right for channel DM pricing (S26.12.3)
- [ ] Custom title/rank field via EditTagControl (S26.4.4)
- [ ] Transfer Ownership button in SlideWrap, visible when all rights selected (S26.4.5)
- [ ] Transfer ownership flow: dry-run, 2FA password, confirmation, success toast (S26.12.4)
- [ ] Dismiss Admin button in settingsAttentionButton red style (S26.4.6)
- [ ] "Promoted by [Name]" info with clickable link (S26.4.7)

### 26.5 Admin Log / Recent Actions
- [ ] Top bar: back button with userpic, 35px userpic skip, 17px left padding (S26.5.1)
- [ ] Search toggle with 150ms slide animation, cancel button 40x54px (S26.5.1)
- [ ] "What is this?" FAQ button in windowActiveTextFg (S26.5.1)
- [ ] Events as service messages in reverse-chronological order (S26.5.2)
- [ ] Event rendering: admin name link + italic action + optional quoted bubble (S26.5.2)
- [ ] Quoted bubbles are full chat bubbles via normal HistoryView::Message path (S26.12.5)
- [ ] 51 distinct admin log event types with specific tr keys (S26.5.3, S26.12.6)
- [ ] Empty state: centered text at (width-260)/2, width 260px, padding 10/12/10/12 (S26.5.4, S26.12.9)
- [ ] No Lottie, no icon on empty state; just centered gray text (S26.12.9)
- [ ] Floating date badge at viewport top with opacity animation (S26.5.5)
- [ ] Date fade: historyDateFadeDuration, hide after 1000ms scroll inactivity (S26.5.5)
- [ ] Pagination: first page 20, subsequent 50 events (S26.5.6)
- [ ] No progress spinner; pagination is asynchronous but silent (S26.12.7)
- [ ] Filter dialog: 3 collapsible sections (Members, Settings, Messages) with checkboxes (S26.5.7)
- [ ] 19 filter flags as uint32 enum (S26.5.7)
- [ ] Optional per-admin filter with admin list (S26.5.7)

### 26.6 Invite Links Management
- [ ] InviteLinksBox at boxWideWidth (S26.6.1)
- [ ] Permanent link display, "Create a New Link" button (S26.6.1)
- [ ] Active links list, revoked links section with "Delete All" button (S26.6.1)
- [ ] Other Admins section with per-admin invite count (S26.6.1)
- [ ] Link row: circular badge with color-coded background + progress arc (S26.6.2)
- [ ] 6 color states: Permanent, Expiring, Expire Soon, Expired, Revoked, Subscription (S26.6.2)
- [ ] Progress arc: rounded-cap, span = fullLength * (1-progress), timer updates (S26.6.2)
- [ ] Link text: stripped URL, usage count, remaining slots, days left (S26.6.2)
- [ ] Three-dots menu icon on each link row (S26.6.2)
- [ ] Context menu: Copy, Share, QR Code, Edit, Revoke, Delete (conditional) (S26.6.3)
- [ ] Single link info box: URL label, Copy/Share buttons, usage/expiry divider (S26.6.4)
- [ ] Joined users list with pagination (first 20, then 100) (S26.6.4)
- [ ] Joined userpic strip: max 3 overlapping avatars (S26.6.4)
- [ ] QR Code dialog via FillPeerQrBox (S26.6.5)
- [ ] Create/Edit link form: Label (max 32), Expiration radios, Usage radios (S26.6.6)
- [ ] Expiration options: Never, 1h, 1d, 7d, Custom; default 30 days (S26.6.6)
- [ ] Usage options: Unlimited, 1, 10, 100, Custom (S26.6.6)
- [ ] Request Approval toggle (hides usage limit via SlideWrap) (S26.6.6)
- [ ] Subscription Credits NumberInput for channel links (S26.6.6)
- [ ] Admin links list with avatar, name, invite count per admin (S26.6.7)

### 26.7 Member List with Role Tabs
- [ ] 5 roles: Members, Admins, Restricted, Kicked, Profile (S26.7.1)
- [ ] Integrated search bar with server-side debounced queries (S26.7.2)
- [ ] Pagination: first page 16, subsequent 200, online sort delay 1000ms (S26.7.3)
- [ ] Row layout: 56px height, 42px avatar, name at (74,9), status at (74,30) (S26.7.4)
- [ ] Row content: avatar, name with admin/creator badge, status/rank, right action (S26.7.4)
- [ ] Members sorted by online status with binary threshold search (S26.7.5)
- [ ] Add button at top: varies by role (add members, add admin, add restriction) (S26.7.6)
- [ ] Context menu: View Profile, Edit Tag, Promote, Restrict, Remove, Promoted/Restricted by (S26.7.7)
- [ ] Members info panel: 56px header, 38x38px button, 15px search top (S26.7.8)

### 26.8 Banned Users List
- [ ] Same row layout as member list (S26.8)
- [ ] Status shows ban reason or "Banned" with restriction details (S26.8)
- [ ] Context menu: "Unban", "View Profile" (S26.8)
- [ ] "Add to Banned" button at top (S26.8)

### 26.9 Slow Mode Settings
- [ ] Non-admin members restricted to one message per interval (S26.9)
- [ ] Send button shows countdown timer: "m:ss" text, normalFont, windowSubTextFg (S26.9, S26.12.11)
- [ ] Countdown replaces send button icon entirely, centered with al_center (S26.12.11)
- [ ] Updates once per second, reverts to Type::Send when seconds == 0 (S26.12.11)
- [ ] Admins and bots exempt from slowmode (S26.9)
- [ ] Discrete snap slider positions only (S26.9)

### 26.10 Anti-Spam Settings
- [ ] Toggle in group edit screen (S26.10)
- [ ] Requires megagroup with participantsCount >= appConfig minimum (default 100) (S26.10, S26.12.12)
- [ ] Toggle always shown to creators/admins; disabled below threshold (S26.12.12)
- [ ] Below-threshold divider text: `lng_manage_peer_antispam_not_enough` (S26.12.12)
- [ ] Admin log records toggle events (S26.10)

---

## 27. Passcode Lock Screen

### 27.1 Settings Entry Point
- [ ] Row in Privacy & Security: icon menuIconLock, title "Local passcode" (S27.1)
- [ ] Reactive label: "On" when passcode set, "Off" when not (S27.1)
- [ ] Click with passcode: navigate to LocalPasscodeCheck (S27.1)
- [ ] Click without passcode: navigate to LocalPasscodeCreate (S27.1)

### 27.2 Passcode Create Flow
- [ ] Full-page settings section with vertical layout (S27.2)
- [ ] Lottie animation: "local_passcode_enter" at normalBoxLottieSize, plays on showFinished (S27.2)
- [ ] Two PasswordInput fields: 256px wide, masked dots (S27.2)
- [ ] First field placeholder: "Enter a passcode" (S27.2)
- [ ] Second field placeholder: "Re-enter your passcode" (S27.2)
- [ ] Description text: 256px min width, 53px height, 15px bottom skip (S27.2)
- [ ] Icon padding: margins(0,19,0,5); button padding: margins(0,19,0,35) (S27.2)
- [ ] Validation: empty check, mismatch shows "Passcodes don't match" error (S27.2)
- [ ] Error label: 256px min width, attentionButtonFg color, auto-hides on typing (S27.2)
- [ ] On success: store hash, offer system unlock setup, transition to Manage (S27.2)

### 27.3 Passcode Check Flow
- [ ] Single PasswordInput field, 256px wide, placeholder "Enter your passcode" (S27.3)
- [ ] Same Lottie animation as create flow (S27.3)
- [ ] Flood protection: passcodeCanTry() check, "Please try again later" on block (S27.3)
- [ ] Wrong passcode: increment bad tries, "Wrong passcode" error (S27.3)
- [ ] Correct passcode: reset bad tries, navigate to Manage (S27.3)

### 27.4 Passcode Management Page
- [ ] Change Passcode button: icon menuIconLock (S27.4)
- [ ] Auto-Lock button: icon menuIconTimer, formatted duration label (S27.4)
- [ ] System Unlock toggle (conditional per platform) (S27.4)
- [ ] Platform labels: "Windows Hello", "Touch ID", "Apple Watch", "Use system password" (S27.4)
- [ ] Disable Passcode button pinned to bottom with confirmation dialog (S27.4)

### 27.5 Passcode Change Flow
- [ ] Two-field layout, same as Create (S27.5)
- [ ] Extra validation: new must differ from current ("The passcode is the same") (S27.5)
- [ ] Auto-close timer: 10 minutes idle navigates back (S27.5)

### 27.6 Auto-Lock Timer Dialog
- [ ] Modal box: 320px wide, padding 24/14/24/8px (S27.6)
- [ ] 5 radio options: 1 min, 5 min, 1 hr, 5 hr, Custom (S27.6)
- [ ] Radio vertical gap: 20px (boxOptionListSkip) (S27.6)
- [ ] Custom radio has empty label; adjacent TimeInput widget HH:MM (S27.6)
- [ ] autolockButton: 200px wide checkbox style (S27.16)
- [ ] autolockTimeField: 52px wide, heightMin 20px (S27.16)
- [ ] TimeInput: two numeric fields + colon, max 23:59 (S27.16)
- [ ] Focusing TimeInput auto-selects Custom radio (S27.16)
- [ ] Validation: 0:00 treated as error, showError() on field (S27.16)
- [ ] Pre-selection: match stored value to preset or select Custom with pre-fill (S27.16)
- [ ] Save: setAutoLock(seconds), saveSettingsDelayed(), checkAutoLock() (S27.6)

### 27.7 Passcode Dialog Box (Legacy/Cloud)
- [ ] Modal box: 320px wide (S27.7)
- [ ] Fields stacked: old passcode, new, reenter, hint, email (S27.7)
- [ ] Field widths: 272px (320 - 24 - 24 padding) (S27.7)
- [ ] Vertical spacing: passcodeTextLine 28px, passcodeLittleSkip 5px, passcodeSkip 23px (S27.7)
- [ ] About text: passcodeTextStyle lineHeight 20px, boxTextFg color (S27.7)
- [ ] Error text: boxTextFgError color, 28px line area (S27.7)
- [ ] Hint text: normalFont, vertically centered in 28px line (S27.7)
- [ ] Tab order: Old -> New -> Reenter -> Hint -> Email -> save() (S27.7)
- [ ] Recovery link widget for cloud passwords (S27.7)

### 27.8 Lock Screen
- [ ] Full-window overlay replacing entire app UI, background windowBg (S27.8)
- [ ] Header: "Please enter your passcode", 19px font, centered, 80px above input (S27.8)
- [ ] Passcode input: 225px wide, margins 1/27/1/6, at height/3 from top (S27.8)
- [ ] Submit button: 225px wide, 42px tall, 6px radius, 40px below input (S27.8)
- [ ] Logout link: centered below submit, link font ascent offset (S27.8)
- [ ] Error text: boxTextFgError, centered in 40px gap between input and submit (S27.8)
- [ ] System unlock button: 32x36px IconButton, platform-specific icon (S27.8)
- [ ] "Unlock later" label: defaultFlatLabel, windowSubTextFg (S27.8)
- [ ] System unlock skip: 12px between elements (S27.8)
- [ ] System unlock cooldown: 1000ms before retry (S27.8)
- [ ] No account identity shown (no name, avatar, phone) on lock screen (S27.15)

### 27.9 Lock Screen Transition
- [ ] Slide animation: easeOutCirc arriving, easeInCirc departing (S27.9)
- [ ] Old content captured as pixmap, slides out while lock slides in (S27.9)
- [ ] Opacity crossfade between departing and arriving content (S27.9)
- [ ] Duration: ~150-200ms (S27.9)

### 27.10 Error Handling & Brute-Force Protection
- [ ] Input field error: border transitions to borderFgError, 150ms duration (S27.10)
- [ ] Error animation: 0.0 to 1.0 interpolation, triggers startBorderAnimation (S27.10)
- [ ] Text selected and field focused on error (S27.10)
- [ ] No pixel-displacement shake; error via color change + selection only (S27.10)
- [ ] Bad-tries tracking: counter, timestamp, flood protection (S27.10)
- [ ] Error clears when user types (changed() callback) (S27.10)

### 27.11 Keyboard Shortcut
- [ ] Ctrl+L: lock app, only when local passcode exists (S27.11)

### 27.12 Auto-Lock Timer
- [ ] Base timer with checkAutoLock() callback (S27.12)
- [ ] Calculate shouldLockInMs from settings autoLock value (S27.12)
- [ ] Late timeout grace: 3000ms (S27.12)
- [ ] lockByPasscode(): set passcodeLock flag, setupPasscodeLock on all windows (S27.12)
- [ ] unlockPasscode(): reset bad tries, clearPasscodeLock on all windows (S27.12)
- [ ] localPasscodeChanged(): reset timer, re-evaluate lock state (S27.12)

### 27.13 Notification Behavior When Locked
- [ ] Hide sender names, message text, avatars when locked (S27.13)
- [ ] Show generic "New message" notification (S27.13)
- [ ] Click notification while locked: bring window to front, focus passcode input (S27.13)
- [ ] Clear all pending notifications, do NOT navigate to chat (S27.13)

### 27.14 System Unlock Support
- [ ] Capability query: SystemUnlockStatus { available, withBiometrics, withCompanion } (S27.14)
- [ ] UI label resolution per platform (S27.14)
- [ ] System unlock wrap slides away when biometrics unavailable at runtime (S27.14)
- [ ] Lock screen icon: Windows keeps default, macOS/POSIX overrides per type (S27.14)
- [ ] Linux: no system-unlock implementation, users get passcode only (S27.14)

### 27.15 Multi-Account Lock
- [ ] Single global lock for whole application, not per-account (S27.15)
- [ ] One passcode hash in Storage::Domain local file (S27.15)
- [ ] lockByPasscode() iterates windows, not accounts (S27.15)
- [ ] Unlocking any window unlocks all windows simultaneously (S27.15)
- [ ] Media viewer and web views force-closed at lock time (S27.15)
- [ ] Log Out link: logs out active account only, auto-clears passcode if last account (S27.15)
- [ ] Passcode auto-cleans when zero accounts remain (S27.15)

---

## 28. Two-Factor Authentication (2FA / Cloud Password) Setup

### 28.1 Entry Point
- [ ] Settings button: icon menuIcon2SV, title "Two-Step Verification" (S28.1)
- [ ] Dynamic right label: "Loading..." / "On" / "Off" (S28.1)
- [ ] Cloud password state polled every 60 seconds (S28.1)
- [ ] Navigate to Start (Off), Input check (On), or EmailConfirm (Unconfirmed) (S28.1)

### 28.2 Step Architecture
- [ ] All steps inherit AbstractStep extending AbstractSection (S28.2)
- [ ] StepData struct passed between steps via std::any (S28.2.1)
- [ ] Common header: Lottie 100x100px, padding 0/19/0/5, subtitle 17px semibold, description 256px min (S28.2.2)
- [ ] Lottie animations: intro, password_input, validate, hint, email (S28.2.2)
- [ ] Password field: PasswordInput 256px wide, 61px slot, horizontally centered (S28.2.3, S28.2.3a)
- [ ] Text field: InputField 256px, full width (not centered) (S28.2.3)
- [ ] Error label: FlatLabel, boxTextFgError, 256px min, auto-hides on input change (S28.2.3)
- [ ] Error ring: borderFgError for unfocused+error, 150ms fade animation (S28.2.3a)
- [ ] AddSkipInsteadOfField: 61px phantom spacer for alignment (S28.2.3a)
- [ ] Link button docking: 28px below input baseline (S28.2.5)
- [ ] Done button: 300px wide, 42px tall, 6px radius, accent background (S28.2.4)
- [ ] Auto-close timer: 60s check, 10 min idle timeout (S28.2.6)
- [ ] Step transitions: horizontal slide-right (showOther), slide-left (showBack) (S28.2.7)

### 28.3 Flow 1 — Create New Password
- [ ] Start screen: Lottie intro, "Set Password" button, skip spacers for alignment (S28.3)
- [ ] Create password: interactive Lottie (lock animation on text change) (S28.3)
- [ ] Two password fields: "Enter a password" + "Re-enter your password" (S28.3)
- [ ] Validation: empty check, mismatch "Passwords don't match" (S28.3)
- [ ] Enter in password focuses reenter; Enter in reenter triggers button (S28.3)
- [ ] Hint step: Lottie hint, text field "Password hint", "Skip" link (S28.3)
- [ ] Hint validation: not empty, not same as password (S28.3)
- [ ] Email step: Lottie email, "Your email" field, "Skip" link (S28.3)
- [ ] Skip email: warning confirm box with attentionBoxButton (S28.3)
- [ ] API responses: SetOk with code -> EmailConfirm; SetOk without -> Manage (S28.3)
- [ ] Error handling: EMAIL_INVALID, flood, PASSWORD_HASH_INVALID (S28.3)

### 28.3.5 Email Confirmation Step
- [ ] SentCodeField (single field, NOT per-digit cells) for 2FA email confirm (S28.3.5a)
- [ ] Auto-submit when digit count reaches expected length (S28.3.5a)
- [ ] Digit-only display filtering with optional hyphen grouping (S28.3.5a)
- [ ] Resend link: "Resend code", calls resendEmailCode() (S28.3.5b)
- [ ] Resend-info label: green confirmation "Code resent" (S28.3.5b)
- [ ] Top bar menu: "Abort Two-Step Verification Setup" with menuIconCancel (S28.3.5b)
- [ ] Recovery path: title "Recovery Email", button "Check" (S28.3.5b)
- [ ] Error handling: CODE_INVALID, EMAIL_HASH_EXPIRED, flood (S28.3.5b)
- [ ] Navigation stack cleanup via removeTypes() (S28.3.5b)

### 28.4 Flow 2 — Check & Manage
- [ ] Check password: single field, placeholder "Current password" (S28.4)
- [ ] Hint display: FlatLabel "Hint: {hint}" below input when non-empty (S28.4)
- [ ] Forgot password link with 3-state machine: Recover, CancelReset, Reset (S28.4)
- [ ] Cancel Reset: countdown timer, updates every 999ms (S28.4)
- [ ] SRP_ID_INVALID handling: re-fetch, timeout 60s for repeated (S28.4)
- [ ] Manage screen: Lottie intro in BoxContentDivider (S28.4)
- [ ] Change Password button with menuIconPermissions (S28.4)
- [ ] Change/Set Recovery Email button with menuIconRecoveryEmail (S28.4)
- [ ] Disable password: pinned bottom button, settingsAttentionButton, confirm box (S28.4)
- [ ] Auto-close: 10 min idle timer with StrongFocus (S28.4)
- [ ] Deep-link highlight IDs: 2sv/change, 2sv/change-email, 2sv/disable (S28.4)

### 28.5 Flow 3 — Change Password
- [ ] Change mode detected by non-empty currentPassword in StepData (S28.5)
- [ ] Title: "Change Password", two password fields (S28.5)
- [ ] Same validation as create mode; reuses full pipeline (S28.5)

### 28.6 Flow 4 — Change Email Only
- [ ] setOnlyRecoveryEmail flag hides "Skip" link (S28.6)
- [ ] Uses cloudPassword().setEmail() instead of set() (S28.6)

### 28.7 Flow 5 — Password Recovery
- [ ] Recovery with email: request recovery code, navigate to EmailConfirm (S28.7.1)
- [ ] Recovery EmailConfirm: "Can't access email?" link, confirm box for timed reset (S28.7.1)
- [ ] Recreate mode: two new password fields + "Disable" link (S28.7.1)
- [ ] Recovery without email: confirm box for delayed reset, countdown display (S28.7.2)
- [ ] Minimum displayed reset duration: 60 seconds (S28.7.2)

### 28.8 Flow 6 — Login-Time 2FA
- [ ] PasswordCheckWidget: full-screen intro step, 380px content width (S28.8)
- [ ] Title at 1px, description at 34px, password at 74px, hint at 151px (S28.8.1)
- [ ] Password field: introPassword style, 300px wide, 61px height (S28.8.1)
- [ ] Recovery code field at 96px, initially hidden (S28.8.1)
- [ ] "Forgot password?" link at 24px below code field (S28.8.1)
- [ ] Error label at 220px, introError style (S28.8.1)
- [ ] Next button at 266px, 300x42px, accent background (S28.8.1)
- [ ] SRP password check with hash computation (S28.8.2)
- [ ] Recovery mode: hide password, show code field + "Try password" link (S28.8.3)
- [ ] Reset Account button shown when no recovery available (S28.8.3)
- [ ] Passport data loss warning before recovery submission (S28.8.3)

### 28.9 Flow 7 — Login Email Setup
- [ ] Login email entry: Lottie email, email field, spinner on button during request (S28.9)
- [ ] Login email code confirmation: CodeInput widget (per-digit cells) (S28.9)
- [ ] CodeInput cells: 40x50px each, 10px gap, 4px border, 20px font (S28.9.1a)
- [ ] Cell fill: windowBgOver background, border windowBgRipple (unfocused) / windowActiveTextFg (focused) (S28.9.1a)
- [ ] Digit fill/clear animation: 120ms universalDuration, 10px slide distance (S28.9.1a)
- [ ] Shake error animation: ~300ms shakeDuration, horizontal wobble (S28.9.1a)
- [ ] No confirm button; auto-submits on last digit filled (S28.9.1a)
- [ ] Context menu: Paste and Copy actions (S28.9.1a)
- [ ] IME support: Qt::ImhDigitsOnly hint (S28.9.1a)
- [ ] Fireworks animation on successful verification (S28.9)

### 28.10 Password Validation Suggestion
- [ ] Lottie: cloud_password/validate, plays full sequence immediately (S28.10)
- [ ] Completion screen: fireworks + thumbs-up emoji 100x100 + "Done" button (S28.10)
- [ ] Emoji rendered as animated custom sticker, plays once (S28.10)
- [ ] Existing content widget deleted and replaced by completion content (S28.10)

### 28.11 Legacy PasscodeBox
- [ ] Standard BoxContent dialog, boxWidth, passcodePadding (S28.11)
- [ ] Stacked fields: old -> recover link -> new -> reenter -> hint -> about -> email (S28.11.1)
- [ ] Dynamic title: Create/Change/Remove cloud password (S28.11.1)
- [ ] Confirmation toasts: was_set, updated, removed (S28.11.1)

### 28.12 Error States
- [ ] PASSWORD_HASH_INVALID: "Wrong password!" (S28.12)
- [ ] SRP_PASSWORD_CHANGED: password expired, quit wizard (S28.12)
- [ ] SRP_ID_INVALID: silent retry, server error if repeated within 60s (S28.12)
- [ ] CODE_INVALID: "Invalid code" (S28.12)
- [ ] EMAIL_INVALID: "Invalid email address" (S28.12)
- [ ] EMAIL_HASH_EXPIRED: "Email confirmation expired" (S28.12)
- [ ] EMAIL_NOT_ALLOWED: "Email not allowed" (S28.12)
- [ ] PASSWORD_RECOVERY_NA / EXPIRED: fall back to password mode (S28.12)
- [ ] FLOOD_WAIT: "Too many attempts" (S28.12)

### 28.13 Lottie Animation Reference
- [ ] All icons at 100x100px with padding 0/19/0/5 = total 100x124px widget (S28.13)
- [ ] cloud_password/intro: play once on showFinished (S28.13)
- [ ] cloud_password/password_input: interactive, frame 0 to midpoint on text change (S28.13)
- [ ] cloud_password/validate: full sequence on setup (S28.13)
- [ ] cloud_password/hint: play once on showFinished (S28.13)
- [ ] cloud_password/email: play once on showFinished (S28.13)

---

## 29. Chat Export

### 29.1 Entry Points
- [ ] Settings > Advanced: "Export Telegram Data" button, icon menuIconExport (S29.1.1)
- [ ] boxDuration delay (~150ms) before starting export (S29.1.1)
- [ ] Chat context menu: "Export Chat History" / "Export Topic History" (S29.1.2)
- [ ] Server-triggered suggestion: SuggestBox, boxWidth 360px, "OK"/"Cancel" (S29.1.3)

### 29.2 Export Panel Window
- [ ] SeparatePanel: 364x480px, frameless, onAllSpaces (S29.2)
- [ ] Dynamic title: per mode (full/per-chat/per-topic/progress/completion) (S29.2)
- [ ] Close during processing requires confirmation (S29.2)
- [ ] hideOnDeactivate: true during progress, false after completion (S29.2)

### 29.3 Settings Screen (Full Export)
- [ ] Scrollable vertical layout with fixed bottom button bar (S29.3)

#### 29.3.1 Account Data Options
- [ ] Checkboxes: Personal info, Contact list, Stories, Profile music (S29.3.1)
- [ ] Checkbox padding: 22/8/22/8px, description padding: 22/0/22/16px (S29.3.1, S29.3.6)
- [ ] Description labels: windowSubTextFg, min width 175px (S29.3.1)
- [ ] No section header for account data options (implicit leading group) (S29.3.6)
- [ ] Personal info carries compound mask PersonalInfo|Userpics (S29.3.6)

#### 29.3.2 Chats Section
- [ ] Header: "Chats", 15px semibold, padding 22/20/22/9px (S29.3.2)
- [ ] 6 chat type checkboxes: Personal, Bot, Private Groups/Channels, Public Groups/Channels (S29.3.2)
- [ ] "Only my messages" sub-checkbox with SlideWrap animation (S29.3.2)
- [ ] Sub-option padding: 56/4/22/12px (34px further indented) (S29.3.2)
- [ ] Public groups/channels: "Only my messages" forced on and disabled (S29.3.2)

#### 29.3.3 Media Section
- [ ] Entire section in SlideWrap, hidden when no chat/ProfileMusic selected (S29.3.3)
- [ ] Header: "Media" (S29.3.3)
- [ ] 7 media type checkboxes: Photos, Video, Voice, Video msgs, Stickers, GIFs, Files (S29.3.3)
- [ ] Size limit slider: 15x15px seek handle, 100 discrete positions (S29.3.3)
- [ ] Non-linear size mapping: 1-4000 MB across 100 positions (S29.3.3)
- [ ] Default 8 MB, max 4000 MB (S29.3.3)
- [ ] Size label: right-aligned, 18px above slider top, boxTextFont (S29.3.3)

#### 29.3.4 Other Data Section
- [ ] Header: "Other" (S29.3.4)
- [ ] Active sessions and Other data checkboxes with descriptions (S29.3.4)

#### 29.3.5 Output Format Section
- [ ] Header: "Output format" (S29.3.5)
- [ ] Location label: clickable path link, max height 21px, padding 22/8/22/8 (S29.3.5)
- [ ] Format radio buttons: HTML, JSON, HTML+JSON (S29.3.5)

#### 29.3.5 Bottom Buttons
- [ ] "Export" button: right-aligned, visible when types != 0 (S29.3.6)
- [ ] "Cancel" button: always visible, left of Export (S29.3.6)
- [ ] Scroll shadows: FadeShadow at top/bottom of scroll area (S29.3.6)

### 29.4 Settings Screen (Per-Chat/Topic)
- [ ] No account data options, no chat type selection (S29.4)
- [ ] Media options shown directly (S29.4)
- [ ] Combined format+location label with clickable links (S29.4)
- [ ] ChooseFormatBox: GenericBox with 3 radio buttons + Save/Cancel (S29.4)
- [ ] Date range filter: "From {date} till {date}" with clickable date/time links (S29.4.1)
- [ ] From date: CalendarBox, min Aug 1 2013, reset "From the beginning" (S29.4.1)
- [ ] Till date: CalendarBox, max today, reset "Till now" (S29.4.1)
- [ ] Time editing: ChooseTimeWidget in GenericBox, HH:MM input (S29.4.1)
- [ ] ChooseTimeWidget: hours (0-23) and minutes (0-59) side-by-side, no colon separator (S29.4.1.1)
- [ ] Wheel stepping: hours +/-1, minutes +/-10 per notch (S29.4.1.1)
- [ ] No preset chips; pure numeric editor (S29.4.1.1)
- [ ] Safety offset: 600s minimum gap between from/till (S29.4.1)
- [ ] CalendarBox: 320px wide, 40px day row, 42x38 cell, 32px selected circle (S29.4.2)

### 29.5 Progress Screen
- [ ] Panel title changes to "Exporting Data..." (S29.5)
- [ ] Sequential processing steps: Initializing through Dialogs/Topic (S29.5.1)

#### 29.5.2 Progress Row Layout
- [ ] Row height 30px, padding 22/10/22/10, row spacing 10px (S29.5.2)
- [ ] Step label: 14px semibold, windowBoldFg, max height 20px, end-elision (S29.5.2, S29.5.2.1)
- [ ] Info label: windowSubTextFg, max height 20px, natural width (never elided) (S29.5.2, S29.5.2.1)
- [ ] Info takes natural width; label takes remaining width (S29.5.2.1)
- [ ] Progress bar: 3px thick at row bottom (S29.5.2)
- [ ] Active color: mediaPlayerActiveFg (accent), inactive: mediaPlayerInactiveFg (grey) (S29.5.2)
- [ ] Base track: full-width shadowFg rectangle under progress (S29.5.2.1)
- [ ] Progress animation: sineInOut easing, 200ms duration (S29.5.2)
- [ ] Opacity crossfade: 200ms for step transitions (S29.5.2)
- [ ] Progress bar resets without animation when new value is lower (S29.5.2, S29.5.2.1)
- [ ] Old instances repainted behind current with fading opacity (S29.5.2.1)
- [ ] No ETA or time-remaining label (S29.5.2.1)
- [ ] Up to 3 visible rows for full export, 2 for per-chat (S29.5.2)

#### 29.5.3 Skip File Link
- [ ] Appears after 5000ms of file download (S29.5.3)
- [ ] "Skip file" link fades in, positioned at 22px left (S29.5.3)
- [ ] Hides and restarts timer on file change (S29.5.3)

#### 29.5.4 About Label
- [ ] "Please wait, export is in progress." during export (S29.5.4)
- [ ] Changes to "Your data was successfully exported." on completion (S29.5.4)
- [ ] Style: windowSubTextFg, padding 22/10/22/0 (S29.5.4)

#### 29.5.5 Cancel Button
- [ ] Centered horizontally, 200x44px, 15px semibold, attentionBoxButton style (S29.5.5)
- [ ] Bottom margin 30px from panel bottom (S29.5.5)
- [ ] Opens confirmation dialog on click (S29.5.5)

### 29.6 Stop Confirmation Dialog
- [ ] ConfirmBox: "Are you sure?" text (S29.6)
- [ ] Confirm: "Stop" with attentionBoxButton (red) (S29.6)
- [ ] On confirm: cancelExportFast(), transition to CancelledState (S29.6)

### 29.7 Completion Screen
- [ ] 3 done rows: "Data exported successfully", file count, total size (S29.7.1)
- [ ] All rows progress = 1.0, id = "done" (S29.7.1)
- [ ] "Show My Data" button: 200x44px, defaultActiveButton, max 304px expanded width (S29.7.2)
- [ ] Button opens export folder in system file manager, hides panel (S29.7.2)
- [ ] Panel title reverts, hideOnDeactivate false, about text changes (S29.7.3)

### 29.8 Error States
- [ ] TAKEOUT_INVALID: MakeInformBox, no title, OK button only (S29.8.1, S29.8.1.1)
- [ ] InformBox: escape disabled, outside-click disabled, standard close X available (S29.8.1.1)
- [ ] Post-dismiss: panel stays visible, user can retry from scratch (S29.8.1.1)
- [ ] TAKEOUT_INIT_DELAY: info box with hours remaining + exact timestamp (S29.8.2)
- [ ] Disk/IO error: full-panel label in boxTextFgError, min width 175px, top at panelHeight/4 (S29.8.3)
- [ ] Generic API error: full-panel critical error with code/type/description (S29.8.4)

### 29.9 In-App Export Top Bar
- [ ] Height: mediaPlayerHeight + lineWidth (~36px) (S29.9.1)
- [ ] Background: mediaPlayerBg (S29.9.1)
- [ ] 3 labels: bold "Exporting Data --", step label (middle-elision), info (windowSubTextFg) (S29.9.1)
- [ ] Progress bar: FilledSlider at bottom, full width (S29.9.1)
- [ ] Shadow: PlainShadow widget, controllable visibility (S29.9.1)
- [ ] Click activates export panel window (S29.9.1)
- [ ] Animated show/hide: slides down/up, content scrolls to accommodate (S29.9.2)
- [ ] Lifecycle: created on progress start, destroyed on finish/cancel (S29.9.2)

### 29.10 Settings Persistence
- [ ] Export settings saved to local storage with 1000ms debounce (S29.10)
- [ ] Default path cleared on save (adapts to future changes) (S29.10)
- [ ] Persisted: types, fullChats, media types, size limit, format, path, availableAt (S29.10)

### 29.11 Output Formats
- [ ] HTML: human-readable pages with CSS (S29.11)
- [ ] JSON: machine-readable structured data (S29.11)
- [ ] HTML+JSON: both simultaneously (S29.11)
- [ ] Output to `{path}/DataExport_{date}/` or user-chosen path (S29.11)

# GUI Checklist: Sections 30-36

## 30. Bot Interactions

### 30.1 Bot Command Button & Menu Button
- [ ] Render command slash button (`historyBotCommandStart`) at 44x46px in compose controls strip (§30.1)
- [ ] Icon `chat/input_bot_command` in `historyComposeIconFg`, hover `historyComposeIconFgOver` (§30.1)
- [ ] Click inserts `/` into compose field, triggering command autocomplete (§30.1)
- [ ] Visibility: shown when peer has `botCommandSend` and user not blocked (§30.1)
- [ ] Hide slash button when bot menu button replaces it (§30.1)
- [ ] Bot menu button (`historyBotMenuButton`): RoundButton, height 30px, auto-width with 24px padding per side (§30.1)
- [ ] Bot menu button width clamped: min = 30px (square icon mode), max = 160px (`historyBotMenuMaxWidth`) (§30.1)
- [ ] Bot menu button label: 3-tier fallback -- custom text, "Menu" default, close X glyph (§30.1)
- [ ] Label elided with ellipsis at 112px usable width when exceeding 160px total (§30.1)
- [ ] Skip from adjacent controls: 8px (`historyBotMenuSkip`) (§30.1)
- [ ] Appear/disappear animation: width 0 to buttonWidth over 120ms cubic ease (§30.1)
- [ ] Label swap animation: cross-fade over 120ms with parallel width animation (§30.1)
- [ ] Press ripple: `activeButtonBgRipple` (§30.1)
- [ ] Background `activeButtonBg`, text `activeButtonFg`, hover `activeButtonBgOver` (§30.1)
- [ ] Toast `lng_bot_menu_not_supported` when webview unavailable (§30.1)

### 30.2 Command Autocomplete Dropdown
- [ ] Trigger on `/` in compose field when peer has bots with commands (§30.2)
- [ ] Row height 40px (`mentionHeight`), userpic 33px (`mentionPhotoSize`), left inset 8px (§30.2)
- [ ] Command text in semibold after 49px offset, description text right-aligned in normal font (§30.2)
- [ ] Dropdown width matches compose field, max 4.5 rows visible (180px), scrollable (§30.2)
- [ ] Case-insensitive substring match filtering (§30.2)
- [ ] In groups, commands suffixed with `@botusername` when multiple bots present (§30.2)
- [ ] Recent inline bots: X delete icon on hover (§30.2)
- [ ] Keyboard Up/Down moves highlight, hover fills `mentionBgOver`, click/Enter sends command (§30.2)
- [ ] Opacity fade animation over 200ms (`emojiPanDuration`) (§30.2)
- [ ] Top/bottom border: 1px separator (§30.2)

### 30.3 Inline Bot Results Panel
- [ ] Trigger on `@botname ` (with trailing space) in compose field (§30.3)
- [ ] Panel width 345px (`emojiPanWidth`), min height 278px, max height 640px (§30.3)
- [ ] Height ratio 0.75 of available space, margins 10px, corner radius 8px (§30.3)
- [ ] Show/hide: opacity fade over 200ms with corner masks (§30.3)
- [ ] Mosaic grid layout: content width minus scroll and 11px left margin (§30.3)
- [ ] Item skip 3px, row margin 6px, row border 1px separator (§30.3)
- [ ] Photo/GIF results: height 96px, proportional width, aspect-fill clipped, GIFs auto-play (§30.3)
- [ ] Radial progress 44px during load (`inlineRadialSize`) (§30.3)
- [ ] Sticker results: 64x64px centered, with blur fallback (§30.3)
- [ ] Video results: 64px thumbnail left, title/description/duration right (§30.3)
- [ ] Article/Contact results: optional 64px thumbnail or letter avatar (§30.3)
- [ ] File results: circular icon background 64px with radial progress (§30.3)
- [ ] Thumb-to-text skip 10px, min item width 48px (§30.3)
- [ ] Background `emojiPanBg`, solid scroll style (§30.3)
- [ ] 350ms debounce before sending inline query (§30.3)
- [ ] Repaint throttle 33ms, scroll-to-bottom triggers next page (§30.3)
- [ ] Switch PM button above results with `inline_button_switch` icon in `msgBotKbIconFg` (§30.3)

### 30.4 Reply Keyboard (Below Compose)
- [ ] Full-width reply keyboard below compose area when bot sends `ReplyKeyboardMarkup` (§30.4)
- [ ] Show/hide toggle buttons with 200ms animation (`botKbDuration`) (§30.4)
- [ ] Keyboard hides on non-empty text unless `Persistent` flag set (§30.4)
- [ ] Handle flags: SingleUse, ForceReply, Persistent, Resize (§30.4)
- [ ] Normal button style: margin 10px, padding 10px, height 38px, textTop 9px (§30.4)
- [ ] Tiny button style: margin 4px, padding 3px, height 25px, textTop 2px (§30.4)
- [ ] Tiny style used when available width cannot fit normal buttons (§30.4)
- [ ] Text style: 15px semibold (`botKbStyle`) (§30.4)
- [ ] Button colors: Normal (`botKbBg`/`botKbColor`), Primary (`botKbPrimaryBg`/white), Danger, Success (§30.4)
- [ ] Fill behind keyboard: `historyComposeAreaBg` (§30.4)
- [ ] Corner rounding: BubbleCornerRounding::Large on all corners (§30.4)
- [ ] Scrollable with `botKbScroll` (defaultSolidScroll) (§30.4)
- [ ] Mouse tracking, tooltips after 350ms hover (§30.4)

### 30.5 Inline Keyboard (Buttons Under Messages)
- [ ] Render below message bubble, position with `msgBotKbButton.margin` (2px) (§30.5)
- [ ] Button style: margin 2px, padding 10px, height 36px, textTop 8px (§30.5)
- [ ] Buttons distributed across bubble width, proportional to text content (§30.5)
- [ ] Text single-line, center-aligned, elided, RTL mirrors X (§30.5)
- [ ] All button types: Default, Url, Callback, RequestPhone/Location/Poll/Peer, SwitchInline, Game, Buy, Auth, WebView, CopyText, Suggest variants, CreateBot (§30.5)
- [ ] Button type icons: `inline_button_url` (arrow), `inline_button_switch`, `inline_button_web`, `inline_button_copy`, `inline_button_card` (§30.5)
- [ ] Icon placement at bottom-right with 4px offset (`msgBotKbIconPadding`), color `msgBotKbIconFg` (§30.5)
- [ ] Custom emoji icon support, Buy button star icon (§30.5)
- [ ] Hover animation: 0.0 to 1.0 over 200ms, deselection 1.0 to 0.0 (§30.5)
- [ ] Over background `msgBotKbOverBgAdd` with corner variants (§30.5)
- [ ] Ripple on press: `RoundRectMask`, corner-rounding context-aware (§30.5)
- [ ] Loading state: radial spinner overlay on callback buttons while processing (§30.5)
- [ ] Fast buttons mode: numbered badges 1-9 in `dialogsUnreadFont`/`msgServiceFg` on last keyboard (§30.5)

### 30.6 Web Apps / Mini Apps
- [ ] Open as SeparatePanel overlay, default size 384x694px (§30.6)
- [ ] Header bar: bot name (semibold, custom emoji support), close X, back button, settings button (§30.6)
- [ ] Verified badge `infoVerifiedStar` when applicable (§30.6)
- [ ] Title color overridable via `web_app_set_header_color` (§30.6)
- [ ] Bottom bar: `@botusername`, background overridable, padding 12px all sides (§30.6)
- [ ] Main button: height 40px, textTop 11px, visible/hidden/active/inactive/progress states (§30.6)
- [ ] Main button custom text/colors, ripple auto-calculated from background HSV (§30.6)
- [ ] Secondary button: same style, 4 position options (top/bottom/left/right), skip 12px/8px (§30.6)
- [ ] Progress indicator: radial animation, stroke 3px, 200ms fade, 0.3 opacity (§30.6)
- [ ] Menu popup: maxHeight 360px, items: Open Bot, Remove from Menu/Main Menu, Share Game (§30.6)
- [ ] Theme integration: bot app colors, theme params JSON (§30.6)
- [ ] Loading screen: content area bg from `theme_params.bg_color`, centered 24x24 spinner (§30.6)
- [ ] Loading state machine: pre-open, chrome-only, webview loading, ready (400ms fade), error (§30.6)
- [ ] Confirmation dialogs: unverified bot disclaimer, write access checkbox, close confirmation (§30.6)
- [ ] Prolong timeout 60s, bot list refresh 3600s, clipboard read timeout 10000ms (§30.6)
- [ ] Handle webview events: data_send, color overrides, button setup, fullscreen, clipboard, close (§30.6)

### 30.7 Bot Start Screen
- [ ] Empty state painter when no messages in bot conversation (§30.7)
- [ ] Bot image: 280x140px (`managedBotImageWidth/Height`), gradient background from emoji/peer color (§30.7)
- [ ] Description text with `ItemTextBotNoMonoOptions`, service-style block (§30.7)
- [ ] Intro area: width 224px, sticker 96px, sticker padding (10,8,10,16), title margin, body margin (§30.7)
- [ ] Label opacity 0.85 for secondary text (§30.7)
- [ ] Service message styling: `msgServiceBg`, padding (12,3,12,4), margin (10,10,10,2), semibold centered (§30.7)
- [ ] Start button: full-width FlatButton, 46px height, `windowActiveTextFg` text (§30.7)
- [ ] Start button text: "START" or "RESTART", left-click sends `/start`, right-click clears token (§30.7)
- [ ] Start button hover `historyComposeButtonBgOver`, ripple `historyComposeButtonBgRipple` (§30.7)
- [ ] Bot profile actions: /help, /settings command buttons, privacy policy, Add to Group, Main app, Block/Restart (§30.7)

### 30.8 Game Messages
- [ ] Game card in message bubble: title (semibold, 2 lines max), description (up to 4096 lines) (§30.8)
- [ ] Skip between sections 5px, `msgPadding` bubble padding (§30.8)
- [ ] Media attachment below text, aspect-fill (§30.8)
- [ ] GAME badge: uppercase, `msgDateFont`, bottom-right of media, `msgDateImgBgCorners` background (§30.8)
- [ ] Badge position: inset by `msgDateImgDelta` (4px), bg black 45% alpha, 4px radius (§30.8)
- [ ] Play button: full-width, semibold text, 1px separator, height 36px, padding (13,8,13,8) (§30.8)
- [ ] Play button idle state: transparent bg, 1px top separator, label 100% alpha (§30.8)
- [ ] Play button hover: `msgBotKbOverBgAdd` fill, 0-1 over 150ms (`fadeWrapDuration`) (§30.8)
- [ ] Play button pressed: ripple at pointer position, 200ms expand, 250ms fade-out (§30.8)
- [ ] Play button loading: 14x14px radial spinner, stroke 2px, accent color (§30.8)
- [ ] Loading timeout: 15s, then spinner fades, toast "Failed to open game" (§30.8)
- [ ] Ripple corner-aware: bottom corners match bubble, top corners sharp (§30.8)
- [ ] Score service messages: centered, `msgServiceBg`, "{User} scored {X} in {Game}", click navigates (§30.8)

### 30.9 Login URL Buttons (Auth Confirmation)
- [ ] Auth confirmation dialog on inline keyboard `Auth` button click (§30.9)
- [ ] Bot userpic (64x64px circle) and name, verified badge if applicable (§30.9)
- [ ] Dialog box width 320px, title "Log in to {domain}" with bold domain (§30.9)
- [ ] Unverified app: domain prefixed with "(unverified)" in red (§30.9)
- [ ] Detailed view: device/location rows with 16x16 icons, padding (22,8,22,8), 10px icon-text skip (§30.9)
- [ ] Checkbox 1: "Log in as {user}" (always present, default checked) (§30.9)
- [ ] Checkbox 2: "Allow {bot} to message me" (conditional on bot, pre-checked) (§30.9)
- [ ] Dependency: unchecking checkbox 1 disables and unchecks checkbox 2 (§30.9)
- [ ] Checkbox style: 14px label, 18x18px box, `boxRowPadding` padding, 4px spacing between (§30.9)
- [ ] Phone sharing sub-dialog: "Share phone number" title, Allow/Don't allow buttons (§30.9)
- [ ] Match-codes: 4 emoji in horizontal row, 48x48px rounded buttons (§30.9)
- [ ] Full-width buttons: "Open link"/"Log in" primary, "Cancel" secondary, 8px vertical stack (§30.9)
- [ ] Box animation: slide up over 200ms ease-out, checkbox toggles 120ms (§30.9)
- [ ] Success toast "Success!" for 3s, failure toasts (§30.9)

### 30.10 Bot Payments (Invoice & Receipt)
- [ ] Payment panel: 392x600px (`paymentsPanelSize`) (§30.10)
- [ ] Invoice cover: thumbnail 80x80px with 6px radius, skip 18px, padding (26,0,26,13) (§30.10)
- [ ] Title (semibold 16px, 2 lines max), description (14px, 10 lines), seller (13px, `windowSubTextFg`) (§30.10)
- [ ] Prices section: padding (28,6,28,5), top skip 12px, bottom skip 13px (§30.10)
- [ ] Individual price rows: label left, amount right-aligned (§30.10)
- [ ] Tips buttons: padding (26,6,26,6), height 28px, skip 8px, flex-row with wrap (§30.10)
- [ ] Tip unselected: 10% alpha bg, selected: 80% alpha bg with white text (§30.10)
- [ ] Custom tip entry: modal with money input, max validation, save/cancel (§30.10)
- [ ] Six section buttons: payment method, address, shipping, name, email, phone (§30.10)
- [ ] Section button padding (68,11,14,9), disabled in receipt view (§30.10)
- [ ] Shipping picker: radio-button group, label at (43,8), price at (43,29), margin (27,11,27,20) (§30.10)
- [ ] Shipping form: 9 fields top-to-bottom, field padding (28,0,28,2), save checkbox (28,20,28,8) (§30.10)
- [ ] Provider notice: 12px `windowSubTextFg`, "Processed by {name}" (§30.10)
- [ ] Pay button: width -36px, height 36px, "PAY $X" label, disabled/loading/error states (§30.10)
- [ ] Pay button disabled: alpha 40% text, 50% bg, no ripple (§30.10)
- [ ] Pay button loading: centered radial spinner replaces text (§30.10)
- [ ] Terms of Service gate: mandatory checkbox before Pay proceeds (§30.10)
- [ ] Receipt mode: same layout, date formatting, disabled sections, total with tips (§30.10)
- [ ] Loading overlay: 24x24px spinner, thickness 4px, centered, 400ms fade, 0.3 opacity (§30.10)

### 30.11 Bot Settings in Chat Header
- [ ] No dedicated bot settings button in header; settings accessed via info panel (§30.11)
- [ ] /settings, /help commands in bot profile if declared (§30.11)
- [ ] Privacy policy button in info panel (§30.11)
- [ ] Business bot bar at top of chat with pause/resume toggle and manage/remove options (§30.11)

---

## 31. Saved Messages

### 31.1 Saved Messages Chat Entry
- [ ] Saved Messages as special peer in chat list with bookmark icon userpic (§31.1)
- [ ] Bookmark avatar: vertical gradient circle (#5caffa top to #408acf bottom) with white bookmark silhouette (§31.1)
- [ ] Bookmark shape: vector path, stroke size*0.055, width size*0.15*2+inc, height size*0.19*2+inc (§31.1)
- [ ] Bookmark notch offset size*0.064, rounded top corners, sharp V-notch bottom (§31.1)
- [ ] Chat name "Saved Messages" in `dialogsNameFg`/semibold, no badges (§31.1)
- [ ] Sorts by last message date, supports pinning (§31.1)
- [ ] Hamburger menu entry "Saved Messages" with `menuIconSavedMessages` icon (§31.1)

### 31.2 Saved Messages Sub-Peers (Sublists)
- [ ] Sublist view: each sublist represents messages from a single source peer (§31.2)
- [ ] Sublist name from underlying peer's `chatListName()` (§31.2)
- [ ] Sort by last message timestamp, separate Dialogs::MainList (§31.2)
- [ ] Visibility: shown if has displayable last message or is pinned (§31.2)

### 31.3 Sublist Navigation & Info Panel
- [ ] Dialog list switches to sublists from `savedMessages().chatsList()` on enter (§31.3)
- [ ] Sublist rows: peer's actual userpic, message preview, unread badges (§31.3)
- [ ] Standard `defaultDialogRow` style (62px height) for sublist rows (§31.3)
- [ ] Top bar title: "Loading..." while loading, "My Notes" for self, "Author Hidden", or peer name (§31.3)
- [ ] Info panel: title "Saved Messages", dynamic subtitle "N chats", scrollable sublist list (§31.3)
- [ ] Media filter section: 8 media-type filter buttons (Photo, Video, File, Audio, Link, Poll, Voice, GIF) (§31.3)
- [ ] Each filter button with FloatingIcon overlay at `infoSharedMediaButtonIconPosition` (§31.3)

### 31.4 My Notes
- [ ] My Notes sublist for non-forwarded messages, peer is self (§31.4)
- [ ] My Notes avatar: same blue gradient, different icon `dialogs/avatar_notes` (notepad) (§31.4)
- [ ] Display name "My Notes" everywhere (§31.4)

### 31.5 Saved Messages Loading & Pagination
- [ ] Auto-load when fewer than 20 sublists loaded (`kLoadedSublistsMinCount`) (§31.5)
- [ ] First batch 10 sublists, subsequent 50 (§31.5)
- [ ] Pinned sublists loaded separately (§31.5)
- [ ] Recent sublists: up to 6 sorted by date, version counter for UI refresh (§31.5)

### 31.6 Reaction Tags System
- [ ] Tag data: ReactionId, custom title, count per tag (§31.6)
- [ ] Tags support standard Unicode emoji and custom emoji (animated) (§31.6)
- [ ] Tag operations: refresh, get info, increment/decrement, rename (§31.6)

### 31.7 Tag-Based Search & Filtering

#### 31.7a SearchTags Widget
- [ ] Horizontal tag strip above saved-messages list (§31.7a)
- [ ] Chip visual: pill with notched tail (price-tag shape) (§31.7a)
- [ ] Chip height 18px (`reactionInlineSize`), font 12px, custom emoji 32px scaled to 18px (§31.7a)
- [ ] Chip padding (5,2,7,2), emoji-to-label skip 6px (§31.7a)
- [ ] Left radius 6px, right radius 3px, arrow tail 5px, dot hole 5px with 2px inset (§31.7a)
- [ ] Horizontal skip between chips 8px, vertical wrap skip 4px, bottom margin 10px (§31.7a)
- [ ] Selected chip bg `dialogsBgActive`, normal bg `dialogsBgOver`, promo uses premium accent (§31.7a)
- [ ] Label color: active `dialogsNameFgActive`, normal `windowSubTextFg` (§31.7a)
- [ ] Dot hole transparent (window bg shows through) (§31.7a)
- [ ] Left-click toggles selection (single-select without Shift, multi with Shift) (§31.7a)
- [ ] Right-click: context menu with "Edit tag name", "Filter by tag", "Remove tag" (§31.7a)
- [ ] Non-premium click opens premium preview box (§31.7a)
- [ ] Sort by count descending, no drag reorder (§31.7a)
- [ ] Promo chip for non-premium with "Unlock Tags" text (§31.7a)
- [ ] Additional promo hint text below chips with inline arrow icon (§31.7a)
- [ ] Empty state: widget height 0 when no tags and not premium-preview (§31.7a)

#### 31.7b EditTagNameBox
- [ ] "Add tag name" / "Edit tag name" title depending on existing title (§31.7b)
- [ ] About label explaining tag names visible only to you (§31.7b)
- [ ] InputField with inline emoji preview at left margin (§31.7b)
- [ ] Placeholder "Tag name", max 12 characters (24 UTF-16 code units) (§31.7b)
- [ ] Length-limit badge "N / 12" right-aligned, turns red when over (§31.7b)
- [ ] Save/Cancel buttons, Enter = Save, Escape = Cancel (§31.7b)
- [ ] Empty name allowed (clears title) (§31.7b)
- [ ] Box width 320px, standard open/close animation (§31.7b)
- [ ] Field error: horizontal shake ~300ms (§31.7b)
- [ ] Auto-focus on field when box opens (§31.7b)

#### 31.7c Query Encoding
- [ ] Tag-to-query conversion: `#tag-custom:{id}` or `#tag-emoji:{emoji}` (§31.7c)

### 31.8 Forward-to-Saved Flow
- [ ] Forward to self = forward to Saved Messages, appears in source sublist (§31.8)
- [ ] Post-forward tag suggestion toast with emoji selector (§31.8)
- [ ] Toast auto-dismiss: 3s initial, 2s on mouse leave, hover pauses (§31.8)
- [ ] Tagged confirmation toast after selecting a tag (§31.8)

### 31.9 Subsection Tabs

#### 31.9a Width Computation & Overflow
- [ ] Horizontal strip height 36px, toggle button 64px wide (§31.9a)
- [ ] Toggle icon: `top_bar_profile-flip_horizontal` in `menuIconFg`, no ripple (§31.9a)
- [ ] 1px hairline shadow at strip edge (§31.9a)
- [ ] Vertical mode: strip width 64px, each tab 50px tall, 28px userpic at 8px top (§31.9a)
- [ ] Vertical tab name: 54px max width, 10px font, at 42px top (§31.9a)
- [ ] Vertical active indicator: 8px left-edge bar, 4px radius, `sliderBgActive`, 150ms animation (§31.9a)
- [ ] Horizontal tab width: 18px strict skip + label maxWidth + optional badge width (§31.9a)
- [ ] Label: semibold 13px, label top 9px inside 36px button (§31.9a)
- [ ] Horizontal active indicator: bar at 33px top, 6px tall, 2px radius, transparent fg (§31.9a)
- [ ] Active state: text color change only (`windowSubTextFg` to `lightButtonFg`) (§31.9a)
- [ ] Ripple: `windowBgOver` normal, `lightButtonBgOver` active, 1px bottom skip (§31.9a)
- [ ] Hidden scrollbar for horizontal tabs (§31.9a)
- [ ] Wheel-Y to scroll-X redirection (§31.9a)
- [ ] Scroll-to-active with half-tab-peek affordance (§31.9a)
- [ ] Dynamic slice expansion: initial 12 tabs, doubles when scrollMax <= 3x viewport (§31.9a)
- [ ] Drag-reorder for pinned sublists, API sync (§31.9a)
- [ ] Right-click context menu: same as dialogs sidebar (Pin, Mute, Mark as Read, Delete) (§31.9a)
- [ ] Toggle button flips between Horizontal and Vertical layout (instant, no crossfade) (§31.9a)

### 31.10 Chat List Row with Tags
- [ ] Tagged dialog row: height 72px (vs 62px), textTop 30px, tagTop 52px (§31.10)
- [ ] Tagged forum dialog row: height 96px, tagTop 77px (§31.10)
- [ ] Tag pills: pre-rendered cached QImage, horizontal layout at nameLeft with 4px gap (§31.10)
- [ ] Tag pill font: 10px (§31.10)

### 31.11 Hidden Author Messages
- [ ] "Author Hidden" sublist with generic hidden-author userpic (§31.11)
- [ ] Functions identically to named sublists (§31.11)

### 31.12 Saved Messages in Search
- [ ] Saved Messages in global search results with bookmark avatar (§31.12)
- [ ] Tag + text combined search support (§31.12)

### 31.13 Unread State Management
- [ ] Per-sublist unread count tracking (§31.13)
- [ ] Read marking with batched server sync (§31.13)
- [ ] Global `clearAllUnreadReactions()` (§31.13)

---

## 32. Stories

### 32.1 Stories Bar (Chat List)
- [ ] Horizontal avatar strip above chat list, below search bar and folder tabs (§32.1)
- [ ] Collapsed state: height 35px, avatar 21px at (4,4), shift 16px, unread ring 1.5px (§32.1)
- [ ] Max 3 small thumbnails shown (`kSmallThumbsShown`) (§32.1)
- [ ] Expanded state: height 77px, avatar 42px at (10,9), unread ring 2px, read ring 1px (§32.1)
- [ ] Name text: 11px font at 56px top, centered below avatar (§32.1)
- [ ] Read items opacity 0.6, own stories 1.0 (§32.1)
- [ ] Expansion trigger at 0.72 overscroll ratio, collapse at 0.68, friction 0.15 (§32.1)
- [ ] Catch-up animation 200ms, slideWrap/fadeWrap transitions (§32.1)
- [ ] Unread gradient ring: QLinearGradient top-right #0dcc39 to bottom-left #0992ef (§32.1)
- [ ] Segmented arcs for multiple stories with gaps between segments (§32.1)
- [ ] Read stories: `dialogsUnreadBgMuted` ring color (§32.1)
- [ ] Horizontal scroll via touch drag or wheel (Y redirected to X) (§32.1)
- [ ] Preload trigger at 2 pages from end (§32.1)
- [ ] Ordering: reverse chronological, premium users weighted higher, "My Story" always first (§32.1)
- [ ] Tap on avatar opens story viewer, long-press/right-click shows context menu (§32.1)
- [ ] Tooltip: up to 3 names on hover (§32.1)

### 32.2 Story Viewer Overlay
- [ ] Full-screen overlay, max content 540x960px, corner radius 8px (§32.2)
- [ ] Header "Outside" (above) or "Normal" (overlaid) based on vertical space (§32.2)
- [ ] Sibling previews: blurred, width ratio 0.448 default, 0.72 max, 0.24 outside overflow (§32.2)
- [ ] Sibling userpic 0.3 of width, min width 200px (§32.2)
- [ ] Sibling opacity 0.5 default, 0.4 hover, name opacity 0.8/1.0, scale +5% hover (§32.2)
- [ ] Sibling thumbnail 200ms fade-in, two-stage loading (blur then hi-res crossfade) (§32.2)
- [ ] Progress bar: 2px height, 4px segment gap, margin (8,7,8,6) (§32.2)
- [ ] Active segment 1.0 opacity, inactive 0.4, max 180 segments (§32.2)
- [ ] Dynamic segment width formula: (totalWidth - (count-1)*gap) / count (§32.2)
- [ ] Photo playback: 5000ms duration, 100ms progress interval (§32.2)
- [ ] Video playback: duration from media player, volume control 75px at 20px from bottom (§32.2)
- [ ] Mark-as-read: 0.2s threshold, 3s server delay, 5s view increment delay (§32.2)
- [ ] Navigation: tap left third = previous, right third = next, subjump at boundary (§32.2)
- [ ] Close: tap outside, swipe down, Escape (§32.2)
- [ ] Content fade on interaction: 0.6 opacity with sineInOut easing (§32.2)
- [ ] Long-press pauses playback, release resumes; also pause on window inactive/menu/tooltip (§32.2)
- [ ] Preloading: 3 peers, 5 stories, 3 next media, 1 previous, max 10 concurrent (§32.2)

### 32.3 Story Header
- [ ] Margin (12,4,12,8), avatar 28px, name at (50,0), date at (50,17) (§32.3)
- [ ] Name semibold FlatLabel, date normal FlatLabel (§32.3)
- [ ] Counter format: bullet separator "3/7" (§32.3)
- [ ] Opacity: name 1.0, date 0.8, controls 0.65 default / 1.0 hover / 0.45 disabled (§32.3)
- [ ] Privacy badges: badge shift (5,4), outline 2px, padding (1,1,1,1) (§32.3)
- [ ] Close Friends = green star, Contacts badge, Selected Contacts badge, Public = no badge (§32.3)
- [ ] Timestamp display: "Just now", "X minutes ago", "X hours ago", time, date formats (§32.3)
- [ ] Play/pause button 40x40px at (54,0), volume button 40x40px at (10,0) (§32.3)
- [ ] Volume slider 75px width (§32.3)

### 32.4 Story Reactions
- [ ] Reaction panel: width 210px expandable to 420px, bottom skip 29px (§32.4)
- [ ] Like button 42x42px at position (85,30) (§32.4)
- [ ] Reaction bubble: speech-bubble with two tail circles (big 0.264, small 0.110) (§32.4)
- [ ] Scale-out animation 1000ms, target 0.7, counter fade 150ms (§32.4)
- [ ] Suggested reactions at normalized coordinates, flipped/dark styling support (§32.4)
- [ ] Weather areas: emoji/sticker at `chatIntroStickerSize`, temp in C/F, color by luminance (§32.4)

### 32.5 Story Reply Compose
- [ ] Background #2c333d, hover #323a45, ripple #39424f, radius 21px (§32.5)
- [ ] Padding (1,8,1,6), field left 10px (§32.5)
- [ ] Text white #ffffff, accent blue #4db8ff (§32.5)
- [ ] Attachment button 42x42px, supports photos/files/voice (§32.5)
- [ ] Placeholder text: varies by context (reply/comment/stealth countdown/paid) (§32.5)
- [ ] Min controls width 280px, extend by 4px (§32.5)
- [ ] Input field: heightMin 36px, heightMax 72px, textMargins (2,0,2,0) (§32.5)
- [ ] Buttons all 42x42px: Emoji, Attach, Send, Like, each with 40px ripple at (1,1) (§32.5)
- [ ] Send icon offset (9,9), fill padding 5px (§32.5)
- [ ] Comments controls: 42x42px, skip 8px, unread dot 6px at (24,8) (§32.5)

### 32.6 Story Caption
- [ ] Collapsed: FlatLabel min width 36px, padding (11,6,11,6) (§32.6)
- [ ] Tap to expand with fadeWrap animation and sineInOut easing (§32.6)
- [ ] Expanded: ElasticScroll, pull-to-close threshold 50px (§32.6)
- [ ] Height animates between collapsed and full via interpolate (§32.6)
- [ ] Content fade to 0.6 when caption expanded or reply active (§32.6)

### 32.7 Story Repost View
- [ ] Background rgba(0,0,0,64), historyReplyPadding (§32.7)
- [ ] Name in semibold, subtitle in normal font (§32.7)
- [ ] Simple repost: padding (8,2,8,2), radius 10px, no outline (§32.7)
- [ ] Quote repost: messageQuoteStyle (§32.7)
- [ ] Width constraint `maxSignatureSize`, ripple `defaultRippleAnimation` (§32.7)

### 32.8 Story Privacy Controls
- [ ] Four levels: Everyone, Contacts, Close Friends, Selected Contacts (§32.8)
- [ ] Privacy badge on own story header (others' stories don't show) (§32.8)

### 32.9 Story Views List
- [ ] Stacked avatars: 24px userpic, 9px shift, 4px stroke (§32.9)
- [ ] Views position (4,29), text at (26,14); likes position (0,29), text at (41,14) (§32.9)
- [ ] Recent views skip 8px (§32.9)
- [ ] View count + reaction count display, "No views" for empty (§32.9)
- [ ] Load 50 entries per batch, trigger at 2 pages threshold (§32.9)
- [ ] Placeholder rows while loading (§32.9)
- [ ] No filter/sort/search UI -- flat chronological list (§32.19)
- [ ] Menu style: 240px width, 320px max height, 7px radius (§32.19)

### 32.10 Stealth Mode
- [ ] Activation flow: check active, check premium, check cooldown, then activate (§32.10)
- [ ] Logo icon `stories/stealth_logo` on `windowBgActive` bg, 12px extra margin (§32.10)
- [ ] Feature icons: `stories/stealth_5m` (past), `stories/stealth_25m` (next) in accent (§32.10)
- [ ] Button states: Non-premium "UNLOCK" + lock, Cooldown "H:MM:SS" at 0.5 opacity, Ready "ENABLE" (§32.10)
- [ ] Button height 42px, padding 10px, textTop 12px, semibold (§32.10)
- [ ] Countdown updates every 250ms, format H:MM:SS or M:SS or 0:SS (§32.10)
- [ ] Toast notifications: 4000ms duration, 3 types (already active, enabled, cooldown) (§32.10)
- [ ] Close button: `box_button_close`, 40px ripple at (4,4) (§32.10)

### 32.11 Story Expiry & Archive
- [ ] Stories expire at `_expires` timestamp, timer max 86400s (§32.11)
- [ ] Archive: first page 30 items, subsequent 100 (§32.11)
- [ ] Album IDs: saved=0, archive=-1 (§32.11)

### 32.12 Profile Stories (Highlights/Saved)
- [ ] SubTabs: "All" tab, album tabs, "Add" tab pinned right (§32.12)
- [ ] Grid: responsive columns from viewport width, `infoMediaMinGridSize` = 82px (§32.12)
- [ ] Item skip 2px (`infoMediaSkip`), left 3px, min grid size 82px (§32.12)
- [ ] Preload 4 screens each direction (§32.12)
- [ ] Album drag-reorder with API sync (§32.12)

### 32.13 Story Interactive Areas
- [ ] Area types: StoryLocation, SuggestedReaction, ChannelPost, UrlArea, WeatherArea (§32.13)
- [ ] Normalized coordinates (0-1), rotation transforms, corner radius (§32.13)

### 32.14 Story Sharing
- [ ] Share box with link-only or full sharing based on permissions (§32.14)
- [ ] Silent posting, scheduled, quick reply, effects, paid stars support (§32.14)

### 32.15 Story Creation Editor
- [ ] Full-window layer, no dismiss by outside click, blurred dimmed background (§32.15.1)
- [ ] Content margins: (20,20,20,146), 9:16 aspect ratio canvas (§32.15.1)
- [ ] Close X button (64px hit area), overflow menu for discard (§32.15.1)
- [ ] Two stacked 48px button bars, 422px max width, radius = min(w,h)/2, 200ms bar slide (§32.15.1)
- [ ] Cancel edge button: 14px semibold, padding (22,0,22,0) (§32.15.1)
- [ ] Done edge button: accent blue, same geometry (§32.15.1)
- [ ] Canvas 9:16, max 540x960px, corner radius 8px while editing (§32.15.2)
- [ ] Canvas zoom: min 1.0, max 8.0, step 1.15 (§32.15.2)
- [ ] Video trim slider: 48px height, 12 thumbnail frames at 36x36, pill handles 8x48px (§32.15.3)
- [ ] Trim constraints: max 60s, min 1s (§32.15.3)
- [ ] Sticker picker: TabbedPanel with Emoji/Stickers/Custom Emoji tabs (§32.15.4)
- [ ] Sticker placement: half shorter canvas edge at scene center (§32.15.4)
- [ ] Item drag body translates, corner handle scales+rotates (0.2 to 6.0 clamped) (§32.15.4)
- [ ] Text tool: alignment (L/C/R), bg style (none/filled/outlined/shadowed), font picker (7 fonts) (§32.15.5)
- [ ] Text color picker: 10 swatches + custom HSL color editor (§32.15.5)
- [ ] Drawing tool: 5 brush tools (pen, arrow, marker 0.35 opacity, blur radius 20, eraser) (§32.15.6)
- [ ] Color picker: 24px color button, 5 Lottie tool buttons at 20px, 18px gap (§32.15.6)
- [ ] Color palette: 20px squares, 6px gap, 2px selection ring (§32.15.6)
- [ ] Brush size slider: vertical 280px, collapsed 2px width, expanded 4-25px, 200ms animation (§32.15.6)
- [ ] Undo/Redo buttons with inactive state (§32.15.6)
- [ ] Caption bar: reuses compose controls, multi-line max 6 lines, Post button (§32.15.7)
- [ ] Privacy selector: chip row, height 32px, radius 16px, padding (14,0,14,0), spacing 8px (§32.15.8)
- [ ] Privacy dialog: 320px box, 4 options (Everyone/Contacts/Close Friends/Selected), radio indicators (§32.15.8)
- [ ] Duration picker: chip with abbreviated duration, popup menu with 4 options (6h/12h/24h/48h) (§32.15.9)
- [ ] 48h is premium-gated with lock icon (§32.15.9)
- [ ] Save to Profile toggle: bookmark icon, "Keep on my page" (§32.15.10)
- [ ] Allow Sharing toggle: forward-arrow icon, hidden for Close Friends (§32.15.10)
- [ ] Toggle switch: 36x20 pill, off rgba(255,255,255,0.15), on #4db8ff, 16px thumb, 200ms slide (§32.15.10)
- [ ] Post button: 36x36 accent circle, arrow icon, disabled alpha 0.35 (§32.15.11)
- [ ] Upload progress ring: 2px stroke white, clockwise fill (§32.15.11)
- [ ] Complete: 150ms crossfade to checkmark, 250ms layer slide-down dismiss (§32.15.11)
- [ ] Error: 200ms red flash then idle, toast with error (§32.15.11)
- [ ] Keyboard shortcuts: Esc, Enter/Return, Ctrl+Z/Y, Del/Backspace (§32.15.12)

---

## 33. Contacts Screen

### 33.1 Box Shell & Title Bar
- [ ] Box width `boxWideWidth` (~364px), title "Contacts" in 17px semibold at 48px height (§33.1)
- [ ] Close button bottom-right "Close" (§33.1)
- [ ] Add Contact button bottom-left, opens AddContactBox (§33.1)
- [ ] Sort toggle button top-right: 48x54px hit area, 42px ripple at (1,6), icon at (10,-1) (§33.1)
- [ ] Online sort (default): clock icon, sorted by onlineTill descending (§33.1)
- [ ] Alphabetical sort: A-Z icon, sorted by `chatListNameSortKey()` (§33.1)
- [ ] Instant icon swap on toggle (no crossfade) (§33.1)

### 33.2 Stories Bar in Contacts
- [ ] Contacts with active stories get colored ring around avatar in their row (§33.2)
- [ ] Ring uses `dialogsStoriesFull.lineTwice` stroke width (§33.2)
- [ ] Click on avatar area opens story viewer, elsewhere opens chat (§33.2)
- [ ] Unread gradient ring segments, read = muted grey, video = red (§33.2)
- [ ] Row style with stories: height 52px, photo at (18,5), name at (70,7), status at (70,27) (§33.2)

### 33.3 Search Field
- [ ] MultiSelect widget below title bar, always visible (§33.3)
- [ ] Local filtering: instant match on `nameWords()` and `nameFirstLetters()` (§33.3)
- [ ] Global search fallback with `AutoSearchTimeout` debounce (§33.3)
- [ ] No results: "No contacts found" centered with `membersAboutLimitPadding` (§33.3)
- [ ] Loading label during server search (§33.3)
- [ ] Escape clears query (§33.3)

### 33.4 Contact List Layout
- [ ] Flat vertical scroll, no letter section headers (§33.4)
- [ ] Row height 56px, avatar 42px at (16,7), name at (74,9), status at (74,30), padding 16px (§33.4)
- [ ] Avatar: 42px circle, colored initials fallback, Saved Messages bookmark for self (§33.4)
- [ ] Name: semibold ~14px, `contactsNameFg`, single-line elided, inline badges (verified/premium/scam) (§33.4)
- [ ] Status font: ~13px normal, 3 color states: green (online), gray (offline), gray-over (hover) (§33.4)
- [ ] Status types: Online, LastSeen (recently/week/month/long ago/exact), Custom, CustomActive (§33.4)
- [ ] Status refresh based on `OnlinePhraseChangeInSeconds()` (§33.4)
- [ ] Hover: ripple animation, background tint (§33.4)
- [ ] Click opens chat, middle-click new window, right-click context menu (§33.4)
- [ ] Story click area opens viewer instead of chat (§33.4)

### 33.5 Add Contact Dialog
- [ ] Width `boxWideWidth`, top padding 2px, bottom padding 14px (§33.5)
- [ ] Fields: first name, last name (skip 9px), phone number (skip 30px from last name) (§33.5)
- [ ] Country code picker: opens CountrySelectBox on click/Enter/Space (§33.5)
- [ ] CountrySelectBox: width 320px, title "Choose a country", search field (§33.5)
- [ ] Country row: ~36px height, name left, +code right, no flag emoji (§33.5)
- [ ] Country row states: normal/hover/pressed with ripple animation (§33.5)
- [ ] Country keyboard nav: arrows, PageUp/Down, Enter submits, Esc closes (§33.5)
- [ ] No-results: "No countries found" label (§33.5)
- [ ] Language-aware name ordering (`langFirstNameGoesSecond`) (§33.5)
- [ ] Phone validation: strips non-digits, min 8 digits (§33.5)
- [ ] Tab cycles First -> Last -> Phone -> Submit, Enter advances/saves (§33.5)
- [ ] Retry state if phone not on Telegram (§33.5)

### 33.6 Edit Contact Dialog
- [ ] Cover: 108px fixed height, avatar 72x72 at (19,18), name at (109,33), status at (109,57) (§33.6)
- [ ] Name: 16px semibold, reactive updates from form input (§33.6)
- [ ] Status: phone formatted or "Mobile hidden" (§33.6)
- [ ] No badges in edit contact cover (§33.6)
- [ ] Avatar: UserpicButton OpenPhoto role, press shows 40% dim overlay (§33.6)
- [ ] Name right-click: "Copy full name" (§33.6)
- [ ] Name/last name InputFields with max length, locale-aware ordering (§33.6)
- [ ] Notes field: multi-line with emoji panel, premium character limit (§33.6)
- [ ] Photo buttons: Suggest photo (Lottie 0-21 frames), Set personal photo, Reset to default (§33.6)
- [ ] Delete contact button: red text at bottom (§33.6)

### 33.7 Delete Contact Confirmation
- [ ] Standard confirmation box, "Delete" (destructive/red) + "Cancel" (§33.7)
- [ ] On confirm: API call, flags cleared, row removed, chat history preserved (§33.7)
- [ ] Note deletion via separate API (§33.7)

### 33.8 Contact Actions (Context Menu & Profile)
- [ ] Actions: Add Contact, Share Contact, Edit Contact, Delete Contact, Block User (§33.8)
- [ ] Each with specific icon and condition (§33.8)
- [ ] Share Contact: ShareBox with grid (4 columns, 108px row, 6px avatar top, 6px name top) (§33.8)
- [ ] Share selection animation: name color over 150ms (§33.8)
- [ ] Share search: local + remote with debounce (§33.8)
- [ ] Share send button hidden when no selection, right-click for scheduling (§33.8)
- [ ] Share comment field: MultiLine InputField, hidden initially (§33.8)

### 33.9 Mutual Contact Indicator
- [ ] No dedicated visual indicator in contacts list (§33.9)
- [ ] Phone display in profile via FormatPhone, "hidden" for collectible numbers (§33.9)

### 33.11 Sort Options
- [ ] Online sort: by onlineTill descending, throttle 3000ms (§33.11)
- [ ] Alphabetical sort: by `chatListNameSortKey()`, stable (§33.11)

### 33.12 Empty State
- [ ] No contacts: description label area (§33.12)
- [ ] Search no results: "No contacts found" centered (§33.12)
- [ ] Search loading label (§33.12)

---

## 34. Calls History

### 34.1 Access Points
- [ ] Hamburger menu entry "Calls" with `menuIconPhone`, gated by `showCallsInDrawer()` (§34.1)
- [ ] Three-dot menu "Call Settings" navigates to Settings > Calls (§34.1)

### 34.2 Box Structure
- [ ] GenericBox with 3 vertical sections: active group calls, create call, call history (§34.2)
- [ ] Title "Calls", bottom button "Close" (§34.2)
- [ ] Top-right menu: "Call Settings" and "Clear All" (red, attention style) (§34.2)

### 34.3 Active Group Calls Section
- [ ] SlideWrap, auto-shown when any channel has active group call (§34.3)
- [ ] GroupCallRow: channel name, custom status (chat type), right action button 40x56px (§34.3)
- [ ] Right action: `top_bar_group_call` icon, click starts/joins group call (§34.3)
- [ ] Subsection title "Active Group Calls" (§34.3)
- [ ] Divider + skip separator before call history (§34.3)

### 34.4 Call History List
- [ ] PeerListContent with BoxController, first page 20, subsequent 100 items (§34.4)
- [ ] New calls prepended on MessageUpdate::NewAdded (§34.4)
- [ ] Item removal on message delete, row removal when empty (§34.4)
- [ ] Empty state: "Your recent calls will appear here." (§34.4)
- [ ] Loading state: "Loading..." (§34.4)
- [ ] No date-group headers -- dates embedded in per-row status (§34.8.1)

### 34.5 Call Row Design
- [ ] Row height 56px, avatar 42px at (16,7), name at (74,9), status at (74,30) (§34.5)
- [ ] Name: semibold 13px, `contactsNameFg` (§34.5)
- [ ] Multiple same-peer/date/type calls grouped into single row (§34.5)

### 34.6 Call Direction & Type Indicators
- [ ] Direction arrows in status: incoming (green), outgoing (green), missed/busy (red) (§34.6)
- [ ] Arrow offset (-2,1), skip 4px before timestamp (§34.6)
- [ ] Type: Out, Missed, In based on message flags (§34.6)
- [ ] Voice vs Video distinction for redial button icon (§34.6)

### 34.7 Redial Button
- [ ] Voice: 40x56px, `calls/call_answer` icon, ripple 40px at (0,8) (§34.7)
- [ ] Video: same dimensions, `calls/call_camera_active` icon (§34.7)
- [ ] Right action margins (0,0,12,0) (§34.7)
- [ ] Click starts outgoing call (§34.7)

### 34.8 Status Text Format
- [ ] Today: "{time}", Yesterday: "yesterday at {time}", Older: "{date} at {time}" (§34.8)
- [ ] Grouped: "({amount}) {status}" prefix (§34.8)
- [ ] Locale-dependent short format (§34.8)

### 34.9 Context Menu
- [ ] Right-click: "Delete" with `menuIconDelete`, "Show in Chat" with `menuIconShowInChat` (§34.9)

### 34.10 Row Click
- [ ] Navigate to peer chat scrolled to newest call message (§34.10)

### 34.11 Clear Call History Dialog
- [ ] GenericBox: "Are you sure?" label, "Also delete for other participants" checkbox (§34.11)
- [ ] Confirm "Clear" calls API with optional revoke flag, handles pagination (§34.11)
- [ ] Cancel closes box (§34.11)

### 34.12 Create Call Button
- [ ] SettingsButton styled as `inviteViaLinkButton` with floating icon (§34.12)
- [ ] Label "Create Call", divider text with participant limit below (§34.12)
- [ ] Click opens conference call creation flow (§34.12)
- [ ] Highlight animation when `highlightStartCall = true` (§34.12)

### 34.13 Rate Call Dialog
- [ ] 5 star buttons: 36x36px each, unfilled `windowSubTextFg`, filled `lightButtonFg` blue (§34.13)
- [ ] Stars centered, padding (24,12,24,0), starTop 4px (§34.13)
- [ ] Comment field: MultiLine, max 200 chars, heightMax 135px, top margin 8px (§34.13)
- [ ] Comment shown for ratings < 5, destroyed at 5 stars (§34.13)
- [ ] Send button appears after rating > 0, Cancel always present (§34.13)
- [ ] Title: "Please rate the quality of your call" (§34.13)
- [ ] Box width `boxWideWidth` (364px) (§34.13)
- [ ] Star fill toggle instant (no animation) (§34.13)

### 34.14 Call Settings Section
- [ ] Output device selector, Input device selector with live LevelMeter (18px, 3px, 5px, 44 lines) (§34.14)
- [ ] Camera device selector with live video preview (§34.14)
- [ ] "Use same devices for calls" toggle (§34.14)
- [ ] "Accept incoming calls on this device" toggle (§34.14)

### 34.15 Active Call Top Bar
- [ ] Bar height 38px (`callBarHeight`) (§34.15)
- [ ] Mute toggle: 41x38px, icon `calls/call_record_active` in `callBarFg`, ripple 32px at (5,3) (§34.15)
- [ ] Cross-line animation on mute: 2px stroke diagonal slash (§34.15)
- [ ] Duration label: semibold, `callBarFg`, top 10px, updates each second (§34.15)
- [ ] Signal bars: 4 bars 3px wide, 1px skip, heights 3-12px, 50% inactive opacity (§34.15)
- [ ] Info label: semibold `callBarFg`, max height 28px, full/short name swap (§34.15)
- [ ] Hangup label: "End call" text, skip 10px (§34.15)
- [ ] Hangup button: 41x38px at right edge minus 12px (`callBarRightSkip`) (§34.15)
- [ ] 1:1 background: green `callBarBg` unmuted, gray `callBarBgMuted` muted (§34.15)
- [ ] Group background: animated gradient -- Active green, Muted blue/purple, ForceMuted 3-stop (§34.15)
- [ ] State transition: gradient crossfade over ~150ms (`universalDuration`) (§34.15)
- [ ] Group call extras: userpics row 28px size / 8px shift / 2px stroke (§34.15)
- [ ] Group blob animation: 3 linear blobs (5/7/8 segments), idle 3px, max 4/12/12px (§34.15)
- [ ] Blob update 100ms, level duration 250ms, hide 500ms (§34.15)
- [ ] Info click opens call panel, Ctrl+click debug info (§34.15)
- [ ] Hangup click: 1:1 hangup, group with manage shows LeaveBox (§34.15)
- [ ] Bar placement: one-column = dialogs width, multi-column = main section width (§34.15)
- [ ] Show/hide: SlideWrap slide-down ~200ms (§34.15)

### 34.17 Create Conference Call Box
- [ ] PeerListBox with ConfInviteController, title "New Call" (§34.17.1)
- [ ] Box width 364px, dynamic height (§34.17.1)
- [ ] Primary button reactive: 0 selected = "Create Call", 1+ = "Start Call" (§34.17.1)
- [ ] List rows: 52px height, 40px avatar at (12,6), name at (63,7), status at (63,26) (§34.17.2)
- [ ] Per-row Video (36x52px) and Audio (36x52px) element buttons (§34.17.3)
- [ ] Active element icons in `windowActiveTextFg` (§34.17.3)
- [ ] Selection checkbox, already-in DisabledChecked state (§34.17.3)
- [ ] Row filter: skip self, bots, service users, inaccessible (§34.17.3)
- [ ] Share-invite-link button: `inviteViaLink` style, accent blue text, icon at (23,2) (§34.17.4)
- [ ] Prioritized contacts section: divider below, keyboard navigation across boundary (§34.17.5)
- [ ] Participant limit enforcement: toast on overflow, no counter (§34.17.6)
- [ ] Create flow: 0 selected = conference, 1 = 1:1 call, 2+ = conference (§34.17.7)
- [ ] Invite via Link: creates empty conference, shows link box (§34.17.8)
- [ ] Re-activate flow: custom header with logo, "Call Ended" title, description, divider (§34.17.9)
- [ ] Join Link Box: title "Call Link", Copy/Share buttons (42px height), link preview (§34.17.10)
- [ ] Initial mode: "Or Join" footer link below buttons (§34.17.10)

---

## 35. Empty, Error & Loading States

### 35.1 Empty Chat List
- [ ] Lottie `no_chats.tgs` at 120x120px, plays once (§35.1)
- [ ] Text "You have no conversations yet." in semibold 14px, `windowFg` (§35.1)
- [ ] "New Message" button (defaultActiveButton) with 12px bottom padding (§35.1)
- [ ] Click opens Contacts box (§35.1)
- [ ] Subtitle "Your contacts on Telegram" below Lottie (§35.1)

### 35.2 Empty Folder
- [ ] "No chats currently belong to this folder." in `windowSubTextFg`, 13px normal (§35.2)
- [ ] Inline "Edit" link opens folder editor (§35.2)
- [ ] Label style: `dialogsEmptyLabel`, minWidth 32px, align top (§35.2)

### 35.3 Empty Forum
- [ ] "No topics currently created in this group." text (§35.3)
- [ ] "Create topic" action link opens NewForumTopicBox (§35.3)

### 35.4 Empty Saved Sublists
- [ ] "You can save messages from other chats here." text, no action link (§35.4)

### 35.5 Chat List Loading
- [ ] Skeleton rows matching real DialogRow geometry (§35.5)
- [ ] Avatar placeholder: filled ellipse, `windowBgOver` (§35.5)
- [ ] Name bar: rounded rect, 60px width, semibold font ascent height (§35.5)
- [ ] Status bar: rounded rect, 100px width (randomized: width/4 + random(width/2)) (§35.5)
- [ ] 2 skeleton rows by default (§35.5)
- [ ] Glare animation: 1000ms pause + 1000ms sweep, horizontal gradient left-to-right (§35.5)
- [ ] RTL: painting mirrored (§35.5)

### 35.6 No Chat Selected
- [ ] "Select a chat to start messaging" in service-message bubble (§35.6)
- [ ] Font: semibold ~13px (`msgServiceFont`), color `msgServiceFg` (§35.6)
- [ ] Bubble padding: inner (12,3,12,4), outer (11,8,11,8) (§35.6)
- [ ] Centered horizontally and vertically above compose field (§35.6)

### 35.7 Empty Search Results
- [ ] Search waiting: Lottie `search.tgs` at 100x100px, "Search for messages" (§35.7.1)
- [ ] Hashtag variant: "Enter a hashtag to find messages containing it." (§35.7.1)
- [ ] No results: Lottie `noresults.tgs` at 100x100px, bold "No Results" + description (§35.7.2)
- [ ] Query truncated with ellipsis in description (§35.7.2)
- [ ] "Search in All Messages" link when filter active (§35.7.2)
- [ ] Icon at 1/3 height, label below with 10px gap, margins 10px, min height 220px (§35.7.2)

### 35.8 Empty Recent Search
- [ ] Lottie `search.tgs`, "Recent search results will appear here." (§35.8)

### 35.9 Empty Channels List
- [ ] Lottie `noresults.tgs`, "You are not currently subscribed to any channels." (§35.9)

### 35.10 Empty Shared Media Tabs
- [ ] Per-type icons: Photo, Video, Audio, File, Voice, Link, each tinted `windowSubTextFg` (§35.10)
- [ ] Icon at 120px from bottom (`infoEmptyIconTop`), label at 40px from bottom (§35.10)
- [ ] Label: minWidth 220px, centered, `windowSubTextFg` (§35.10)
- [ ] Icon center at 1/3 of available height (§35.10)
- [ ] Label width = widget width - 40px (§35.10)
- [ ] Per-type empty text and search empty text variants (§35.10)

### 35.11 Empty Downloads Manager
- [ ] File icon, "No files here yet" / "No files found" (search) (§35.11)

### 35.12 Empty Sticker Panel
- [ ] `stickersEmpty` icon, "No stickers found", loading: "Loading..." (§35.12)
- [ ] Icon centered at 1/3 height, text below in `normalFont`/`tabs.labelFg` (§35.12)

### 35.13 Empty Emoji Panel
- [ ] `emojiEmpty` icon, "No emoji found" (§35.13)

### 35.14 Empty GIF Panel
- [ ] No saved GIFs: "You have no saved GIFs yet.", with query: "No results." (§35.14)
- [ ] Text in `normalFont`/`noContactsColor`, centered in upper 2/3 of panel (§35.14)

### 35.15 Chat Intro (No Messages Yet)
- [ ] Title bold "No messages here yet...", description "Send a message or click on the greeting below" (§35.15)
- [ ] Sticker 96px, width 224px, title margin (11,16,11,4), body margin (11,0,11,0) (§35.15)
- [ ] Service-message style bubble, sticker clickable to send (§35.15)
- [ ] Business custom intro: customizable title/description/sticker (§35.15)

### 35.16 New Group Created
- [ ] Service bubble: "You created a group" header bold, "Groups can have:" subtext (§35.16)
- [ ] 4 bullet items about group features (§35.16)
- [ ] Padding (24,16,24,16), bullet skip 16px, header skip 10px, text skip 10px, item skip 8px (§35.16)

### 35.17 New Forum Topic
- [ ] Own: "Almost done!" / "Send a message to start the topic." (§35.17)
- [ ] Other's: "Topic started!" / "Send a message to start the topic." (§35.17)
- [ ] Topic icon rendered above header (§35.17)

### 35.18 Empty Contacts Search
- [ ] "No contacts found" (§35.18)

### 35.19 Empty Member/Peer List Search
- [ ] "No users found." (§35.19)

### 35.20 Empty Blocked Users
- [ ] Loading: "Loading...", Title: "No blocked users", Description with explanation (§35.20)
- [ ] Lottie `blocked_peers_empty.tgs` (§35.20)

### 35.21 Admin Log Empty
- [ ] No events: "No actions yet" title, 48-hour description (group/channel variants) (§35.21)
- [ ] No results: "No actions found" title, filter/search descriptions (§35.21)

### 35.22 Connection State Widget
- [ ] Pill at bottom-left, margins (2,2,2,2), text padding (18,11,18,0) (§35.22)
- [ ] Radial spinner: 20x20px, 2px thickness, `menuIconFg` (§35.22)
- [ ] Connecting: spinner always visible, "Connecting..." on hover (§35.22)
- [ ] Waiting: "Reconnect in N s..." with "Try now" retry link (§35.22)
- [ ] 1000ms delay before showing, fade 150ms (`connectingDuration`) (§35.22)
- [ ] Pill body: three icons (left/body/right) in `windowBg`, shadow in `windowShadowFg` (§35.22)
- [ ] Proxy icons: off `menuIconFg`, on `windowBgActive` (§35.22)
- [ ] Hidden when connected, update ready, or window not exposed (§35.22)
- [ ] Proxy states: auto connecting, through proxy, checking, available, unavailable (§35.22)

### 35.23 Flood Wait Errors
- [ ] "Too many tries. Please try again later." toast (§35.23)
- [ ] Phone flood: extended error about re-creating account (§35.23)

### 35.24 File Download States
- [ ] Ready: file size text, download arrow icon (§35.24)
- [ ] Downloading: "X / Y MB" with radial progress (3px line for files, 2px for audio) (§35.24)
- [ ] Cancel icon during download (§35.24)
- [ ] Loaded: duration/size text, play/open icon (§35.24)
- [ ] Failed: "Failed" status text (§35.24)
- [ ] Download path errors: info/confirm boxes with retry (§35.24)

### 35.25 Media Loading (Photos/Videos/GIFs)
- [ ] Three-stage thumbnail: inline (blurhash), blurred, full resolution (§35.25)
- [ ] Loading overlay: semi-transparent dark, centered radial progress + icon (§35.25)
- [ ] Download/cancel icon swap during load (§35.25)
- [ ] Upload progress: same radial overlay, opacity fades on complete (§35.25)

### 35.26 Media Viewer Loading
- [ ] InfiniteRadialAnimation centered in media area, streaming waitingState (§35.26)
- [ ] Error: silent fallback to download/redisplay (§35.26)

### 35.27 PiP Loading
- [ ] Same spinner as media viewer when waiting (§35.27)

### 35.28-35.29 Not Found States
- [ ] "Sticker set not found." in preview box (§35.28)
- [ ] "Message doesn't exist." toast (§35.29)
- [ ] "Empty Message" for `MTPDmessageEmpty` service text (§35.29)

### 35.30 Call Status States
- [ ] 10 call states: incoming, connecting, exchanging keys, waiting, requesting, etc. (§35.30)
- [ ] Group call: "Connecting..." and "Click to join" (§35.30)

### 35.31 Emoji/Sticker Download States
- [ ] Ready: "Download {size}", Downloading: "{percent}, {progress}", Downloaded: "Downloaded" (§35.31)
- [ ] Pack: "Add" / "Added" (§35.31)

### 35.32 Update Check States
- [ ] Checking, Downloading {progress}, Ready, Failed, Prompt "Update Telegram" (§35.32)

### 35.33 Skeleton Animation
- [ ] Slide 1000ms + wait 1000ms = 2s cycle (§35.33)
- [ ] Base alpha 0.5, gradient alpha 0.2 on `windowSubTextFg` (§35.33)
- [ ] Pill-shaped placeholders: thickness = font height / 2, radius = thickness / 2 (§35.33)
- [ ] Width from real text-layout widths (§35.33)

### 35.34 Dialog Row Loading Skeleton
- [ ] Same as §35.5 with glare effect (§35.34)

### 35.35 Stories Empty States
- [ ] "Your stories will be here.", "Channel posts will be here." (§35.35)
- [ ] "No views yet" for story views (§35.35)
- [ ] Album empty: title + description text (§35.35)

### 35.36 Profile Loading
- [ ] "Loading..." for profile info, "Getting Link Info..." for link previews (§35.36)

### 35.37 Forum "No messages"
- [ ] "No messages" in forum topic preview (§35.37)

### 35.38-35.39 Other Empty States
- [ ] Polls: "No polls found" (§35.38)
- [ ] Gifts: multiple empty states with Lottie `my_gifts_empty.tgs` (§35.39)

### 35.40 Button Loading Spinners
- [ ] InfiniteRadialAnimation centered on RoundButton, hides text while active (§35.40)

### 35.41 Transcription Loading
- [ ] Lottie `transcribe_loading.tgs` in voice message bubble (§35.41)

---

## 36. Common Dialog & Modal Patterns

### 36.1 Box/Dialog Infrastructure
- [ ] Title bar: 16px semibold at (24,13), height 48px, optional close X (§36.1)
- [ ] Content area: scrollable, padded 24px left/right, `boxLabel` 22px line height (§36.1)
- [ ] Button row at bottom with padding, height from style, right-aligned primary then cancel (§36.1)
- [ ] Default button: 30px min width, 34px height, 7px textTop, 14px semibold (§36.1)
- [ ] Box dimensions: standard 320px, wide 364px, maxListHeight 492px (§36.1)
- [ ] Box padding: (24,14,24,8), littleSkip 10px, mediumSkip 20px (§36.1)
- [ ] Box corner radius 8px, background `boxBg` (§36.1)
- [ ] Animation: 200ms (`boxDuration`), easeOutCirc for master, linear for box opacity (§36.1)
- [ ] Opacity 0-1 on show, 1-0 on hide (§36.1)
- [ ] Keyboard: Escape closes, Enter/Return confirms, Tab cycles fields (§36.1)
- [ ] DeleteMessagesBox: Enter only for message deletion, not history clearing (§36.1)

### 36.2 Confirmation Dialogs
- [ ] ConfirmBox: text, confirmed/cancelled callbacks, confirm/cancel labels, style override (§36.2)
- [ ] Default confirm "OK", cancel "Cancel" (§36.2)
- [ ] Destructive actions: `attentionBoxButton` with red text (§36.2)
- [ ] Inform variant: single "OK" button, no cancel (§36.2)
- [ ] Title optional, body with `boxLabel` 22px line height (§36.2)
- [ ] All standard confirmations: delete msg, clear history, leave, block, pin, logout, etc. (§36.2)
- [ ] Moderate variant: additional Ban User, Report Spam, Delete all checkboxes (§36.2)
- [ ] Auto-delete settings link when TTL supported (§36.2)

### 36.3 Alert/Info Dialogs
- [ ] InformBox: same as ConfirmBox with inform=true, single OK button (§36.3)
- [ ] Used for: copy restrictions, bot errors, report thanks, flood wait (§36.3)

### 36.4 Input Dialogs
- [ ] Username box: live validation, debounced API checks, status line (§36.4)
- [ ] Add contact box: name fields + PhoneInput with country code (§36.4)
- [ ] Passcode box: old/new/confirm password fields, inline errors (§36.4)
- [ ] Edit invite link: label, expiry, usage limit, approval toggle (§36.4)
- [ ] Create poll: question + dynamic option fields + mode checkboxes (§36.4)

### 36.5 Choice Dialogs
- [ ] SingleChoiceBox: radio-button selection, title + options + "OK" button (§36.5)
- [ ] Selection auto-closes box (§36.5)
- [ ] Padding: `boxOptionListPadding.top()`, left margin = `boxPadding.left()` + `boxOptionListPadding.left()` (§36.5)
- [ ] Auto-lock variant: 5 preset options + custom TimeInput (§36.5)

#### 36.5.1 PopupMenu Defaults
- [ ] Radius 8px, show 200ms, hide 150ms, scroll padding (0,8,0,8) (§36.5.1)
- [ ] Shadow: 5px blur, offset (0,1), opacity 0.25 (§36.5.1)
- [ ] Menu item padding (17,8,17,7), right skip 6px, width 156-300px (§36.5.1)
- [ ] Separator: (0,5,0,5) margins x 1px stroke (§36.5.1)
- [ ] Ripple show 650ms, hide 200ms (§36.5.1)
- [ ] PanelAnimation clip-reveal: width start 0.5/60%, height 0.3/90%, opacity 0.2/30% (§36.5.1)

### 36.6 Date/Time Picker

#### 36.6.1 CalendarBox
- [ ] Width 364px, cell 48x40px, inner highlight 34px circle (§36.6.1)
- [ ] Day-row header 40px, title bar 48px with 16px semibold (§36.6.1)
- [ ] Day font: normalFont ~13px (§36.6.1)
- [ ] Nav arrows: jump month, long-press fast-jump, arrow keys navigate days (§36.6.1)
- [ ] Month-selector triangle 6px baseline (§36.6.1)
- [ ] Scroll area: 3px deltas, 8px width (§36.6.1)

#### 36.6.2 ChooseDateTimeBox
- [ ] Content height 95px, date at 38px top, "at" label at 42px (§36.6.2)
- [ ] Date field 136px, time field 72px, "at" skip 24px (§36.6.2)
- [ ] Date field min height 30px, time field min height 28px / 14px font (§36.6.2)
- [ ] Optional repeat-period dropdown with premium lock (§36.6.2)

#### 36.6.3 Schedule Message Box
- [ ] Wraps ChooseDateTimeBox with "Send when online" option (§36.6.3)
- [ ] Min 10s from now, max 1 year (§36.6.3)

#### 36.6.4 TimePickerBox
- [ ] Drum/wheel picker, 16 entries from 15m to 3mo (§36.6.4)
- [ ] Active band with `activeLineFg` lines (§36.6.4)
- [ ] Mouse drag, wheel, Up/Down arrow input (§36.6.4)

### 36.7 Color Picker
- [ ] 2D gradient square for saturation x brightness/lightness (§36.7)
- [ ] Crosshair cursor: 16px diameter, 1px stroke (§36.7)
- [ ] Hue slider: vertical bar (§36.7)
- [ ] Opacity slider (RGBA mode) / Lightness slider (HSL mode) (§36.7)
- [ ] HSB fields (H 0-360, S/B 0-100), RGB fields (0-255), hex result field (§36.7)
- [ ] Current vs new color swatches side by side (§36.7)
- [ ] Bidirectional sync between all controls (§36.7)
- [ ] Submit on Enter, reactive `colorValue()` producer (§36.7)

### 36.8 File Picker
- [ ] Native OS file dialogs via Qt (async callbacks) (§36.8)
- [ ] Four functions: open single/multiple, save, folder selection (§36.8)
- [ ] Common filters: AllFiles, Images, PhotoVideo (§36.8)

### 36.9 Toast/Snackbar Notifications
- [ ] Default padding (19,13,19,12), margin (13,13,13,13), max width 480px, radius 6px (§36.9)
- [ ] Fade in 200ms, fade out 1000ms, slide 160ms (§36.9)
- [ ] Default duration 1500ms (§36.9)
- [ ] Multiline: min 160px, max 360px (§36.9)
- [ ] Centered or edge-attached with slide animation (§36.9)
- [ ] Rounded rect `toastBg`, text `toastFg`, no shadow (§36.9)
- [ ] All common toast messages: link/text/code copied, report thanks, share done, etc. (§36.9)

### 36.10 Context Menus
- [ ] PopupMenu: shadow, rounded rect background, scrollable menu, nested submenus (§36.10)
- [ ] PanelAnimation with origin from 4 corners, opacity+clip reveal (§36.10)
- [ ] Keyboard: arrows navigate, Enter activates, Escape closes, Right/Left for submenus (§36.10)
- [ ] Positioning constrained to parent screen bounds (§36.10)

#### 36.10.1 Chat List Context Menu
- [ ] Items: open in new window, archive, pin, view profile, mute submenu, mark read, move to folder, block, clear, delete/leave (§36.10.1)

#### 36.10.2 Message Context Menu
- [ ] Top: go to message, view replies, edit, factcheck, pin (§36.10.2)
- [ ] Middle: copy link, forward, send now, delete (with TTL countdown), download, report, select, reschedule (§36.10.2)
- [ ] Reply section: reply, quote & reply, add todo tasks (§36.10.2)

#### 36.10.3 Photo Context Menu
- [ ] Save As, Copy Image, Attached Stickers (§36.10.3)

#### 36.10.4 Document/Media Context Menu
- [ ] Cancel download, open GIF, add to GIFs, sticker set, favorites, show in folder, save as, copy filename (§36.10.4)

#### 36.10.5 Link Context Menu
- [ ] Copy Link, Copy Email, Copy Hashtag, Copy Username, Copy Card Number (§36.10.5)

#### 36.10.6 Archive Context Menu
- [ ] Expand, Collapse, Move to main menu / chat list, Archive settings (§36.10.6)

#### 36.10.7 Forum Context Menu
- [ ] Create Topic, View info, View as Messages, Search, Manage, Add Members, Boost, Video Chat, Report, Leave/Join (§36.10.7)

### 36.11 Tooltip Popups
- [ ] Standard tooltip: `tooltipBg`/`tooltipFg`/`tooltipBorderFg`, padding (5,2,5,2) (§36.11)
- [ ] Show delay 1000ms, hide-by-leave 10ms, max width 800px, max 12 lines (§36.11)
- [ ] Corner radius `roundRadiusSmall`, no drop shadow (§36.11)
- [ ] Important tooltip: `importantTooltipBg`, margin (4,4,4,4), padding (10,3,10,5) (§36.11)
- [ ] Arrow: triangle 8x4px, arrowSkipMin 24px, arrowSkip 66px (§36.11)
- [ ] Radius 4px, shift 12px, duration 200ms show/hide (§36.11)

### 36.12 Permission Request Dialogs
- [ ] Check permission status: Granted/CanRequest/Denied (§36.12)
- [ ] OS-level request for Microphone/Camera (§36.12)
- [ ] Denied: ConfirmBox with "Settings" button to open system settings (§36.12)
- [ ] Screen share: ChooseSourceProcess with thumbnails, Start/Stop/Share Audio buttons (§36.12)

### 36.13 Report Flow
- [ ] Step 1: Choose reason (9 options as clickable buttons) (§36.13)
- [ ] Step 2: Details input with optional comment, "Report" submit (§36.13)
- [ ] Report reaction variant: title + body + "Ban user" button (§36.13)

### 36.14 Share Box
- [ ] MultiSelect search at top, scrollable peer grid, optional comment field (§36.14)
- [ ] Send button with send menu (schedule/silent), Cancel, optional Copy Link (§36.14)
- [ ] Multi-selection with chips, chat filter tabs, forward options (§36.14)
- [ ] Dark mode style override available (§36.14)

### 36.15 Sticker Toast
- [ ] Specialized toast for emoji/sticker pack notifications with clickable link (§36.15)

### 36.16 Button Labels & Styles
- [ ] Destructive: red text (`attentionBoxButton`), Cancel default (§36.16)
- [ ] Neutral: OK/Done/Yes default style (§36.16)
- [ ] Button order: right-aligned, primary rightmost, cancel left of it (§36.16)

# GUI Checklist: §37-§44

## §37 — Desktop Notifications

### 37.1 Architecture / Manager Selection
- [ ] Implement three-tier notification architecture: System scheduler, Manager base, Platform backend (§37.1)
- [ ] Implement manager selection logic: native vs custom vs dummy (§37.1)
- [ ] Support `kOptionCustomNotification` toggle to force custom popups (§37.1)

### 37.2 Native OS Notifications
- [ ] Linux DBus backend: `call_notify()`, `call_close_notification()`, capability queries (§37.2.1)
- [ ] Linux DBus: send userpic as RGBA8888 bytes via image-data hint (§37.2.1)
- [ ] Linux DBus: support inline reply via `signal_notification_replied` (§37.2.1)
- [ ] Linux DBus: "mail-mark-read" action for mark-as-read (§37.2.1)
- [ ] Linux DBus: sound file path hint when daemon supports `sound-file` (§37.2.1)
- [ ] Linux DBus: respect freedesktop Inhibited property for DND (§37.2.1)
- [ ] Linux GNotification backend: Gio::NotificationPriority::HIGH_, PNG userpic (§37.2.1)
- [ ] Linux: hierarchical notification tracking by ContextId/MsgId (§37.2.1)
- [ ] Windows WinRT toast: XML template with image, 3 text elements, silent audio (§37.2.2)
- [ ] Windows toast: fast reply text input + send button (Windows 10+) (§37.2.2)
- [ ] Windows toast: mark-as-read background activation button (§37.2.2)
- [ ] Windows: DND/Focus Assist detection via registry and QueryFocusAssist (§37.2.2)
- [ ] Windows: App User Model ID for toast notifier registration (§37.2.2)
- [ ] macOS NSUserNotification: title, subtitle, informativeText, userInfo dictionary (§37.2.3)
- [ ] macOS: "Mark as Read" button and reply button via hasReplyButton (§37.2.3)
- [ ] macOS: sound file path to NSUserNotification (§37.2.3)
- [ ] macOS: background thread queue for clearing notifications (§37.2.3)
- [ ] macOS: screen lock detection via `Core::App().screenIsLocked()` (§37.2.3)

### 37.3 Custom In-App Notification Popups
- [ ] Frameless top-level widget with WindowStaysOnTopHint, BypassWindowManagerHint, Tool flags (§37.3.2)
- [ ] Corner selection: TopLeft, TopRight, BottomLeft, BottomRight, TopCenter (§37.3.3)
- [ ] Display monitor selection by checksum (§37.3.3)
- [ ] Start position calculation per corner with RTL swap (§37.3.3)
- [ ] Standard width 320px, TopCenter width 480px (§37.3.3)
- [ ] Notification widget: 320x80px min size (§37.3.4)
- [ ] Userpic: 62x62px at position (9, 9) (§37.3.4)
- [ ] Close button: 30x30px, top-right offset (1, 2), icon at (10, 10), ripple 20x20 at (5, 5) (§37.3.4)
- [ ] Title label: semiboldFont, single line elided, positioned at userpic right + 12px, top 7px (§37.3.4)
- [ ] Message text: dialogsTextFont, up to 2 lines, right edge masked by notifyFadeRight (§37.3.4)
- [ ] Border: 1px on all edges, color windowShadowFgFallback (§37.3.4)
- [ ] Inter-notification gap: 7px (§37.3.4)
- [ ] Edge margin: 6px from screen edge (§37.3.4)
- [ ] Hide All button: 36px height, full notify width (§37.3.4)
- [ ] Reply button: 9px inset from bottom-right, hidden until hover with 200ms fade (§37.3.4)
- [ ] Reply input field: 282px wide (442px TopCenter), 36-72px height, multiline (§37.3.4a)
- [ ] Reply send button: 36x36px with historySendIcon (§37.3.4)
- [ ] Reply field text margins: (8, 8, 8, 6) (§37.3.4a)
- [ ] Reply field grow: height = notifyMinHeight + replyArea.height + borderWidth (117-153px total) (§37.3.4a)
- [ ] Reply field max height scrolling when above 72px (§37.3.4a)
- [ ] Reply submit via Enter/Ctrl+Enter, cancel via Escape (§37.3.4a)

### 37.3.5 Animation and Timing
- [ ] Fade in: 150ms linear (§37.3.5)
- [ ] Slow hide (auto-dismiss): 4000ms easeInCirc (§37.3.5)
- [ ] Fast hide (manual dismiss): 150ms linear (§37.3.5)
- [ ] Shift animation (reposition): 150ms linear (§37.3.5)
- [ ] Action buttons fade: 200ms linear (§37.3.5)
- [ ] Auto-dismiss flow: input polling 300ms, 3000ms wait after input, then 4000ms fade (§37.3.5)
- [ ] Hover: stop all hiding timers, show Reply button with 200ms fade-in (§37.3.5)
- [ ] Leave: restart all hiding, hide Reply button with 200ms fade-out (§37.3.5)
- [ ] Active reply field suspends auto-dismiss for all notifications (§37.3.5)
- [ ] Stacking: newest at corner, stack outward; direction per corner (§37.3.5)
- [ ] Hide All button appears when 2+ notifications or queue non-empty (§37.3.5)

### 37.3.6 Click and Dismiss
- [ ] Left-click body: open chat/topic, navigate to message, clear thread notifications (§37.3.6)
- [ ] Ctrl+click body: open in separate window (§37.3.6)
- [ ] Right-click body: dismiss notification (§37.3.6)
- [ ] Close button: dismiss, accepts both left and right click (§37.3.6)
- [ ] Reply button click: expand with input field, stop auto-dismiss (§37.3.6)
- [ ] Submit reply: send via api().sendMessage() with replyTo, then hide all (§37.3.6)
- [ ] Cancel reply (Escape): dismiss notification (§37.3.6)
- [ ] Hide All click: clearAll, remove all notifications and queue (§37.3.6)

### 37.3.7 Stack Overflow
- [ ] Max notification count: 5 cap, default 3 (§37.3.7)
- [ ] Queue: FIFO deque for overflow notifications (§37.3.7)
- [ ] Evict oldest non-reply, non-hover notification when at capacity (§37.3.7)
- [ ] Sticky notifications: open reply or hovered cannot be evicted (§37.3.7)
- [ ] Stack repositioning: reverse iterate, 7px initial shift, per-notification height + 7px (§37.3.7)
- [ ] No client-side scroll for overflow; queue items wait (§37.3.7)
- [ ] Cross-screen: entire stack on one chosen screen (§37.3.7)
- [ ] Demo mode: single fake notification at 150ms fade for settings preview (§37.3.7)

### 37.4 Notification Content
- [ ] Title: app name when privacy hides name, "Reminder" for scheduled-to-self (§37.4.1)
- [ ] Title: "TopicTitle (ChatName)" for forum topics (§37.4.1)
- [ ] Title: peer name for regular chats, calendar emoji prefix for scheduled (§37.4.1)
- [ ] Title: append " -> username" for multiple accounts (§37.4.1)
- [ ] Subtitle: reactor name for reactions, sender name in groups (§37.4.2)
- [ ] Message text composition for all types: text, photo, video, sticker, voice, etc. (§37.4.3)
- [ ] Spoiler characters replaced with U+259A blocks in notification text (§37.4.3)
- [ ] Reaction notification text: context-specific phrasing per media type (§37.4.4)

### 37.5 Notification Sounds
- [ ] Default sound: msg_incoming.mp3 from Qt resource (§37.5.1)
- [ ] Custom ringtones: per-thread, looked up via notifySettings (§37.5.2)
- [ ] Custom sound tracks cache by DocumentId (§37.5.2)
- [ ] Volume control: per-chat, per-type default, global (0-100) (§37.5.3)
- [ ] Sound playback conditions: soundNotify, not muted, not silent, not none, volume supported (§37.5.4)
- [ ] Native sound delegation: Linux sound-file hint, Windows silent toast, macOS sound path (§37.5.4)

### 37.6 Scheduling and Grouping
- [ ] Timing delays: 100ms min, 500ms forward, 500ms alert dedup, 1000ms album wait (§37.6.1)
- [ ] Cloud delay logic: offline/online device detection (§37.6.1)
- [ ] Forward/album grouping: 1000ms timer, batch forwarded/album messages (§37.6.2)
- [ ] Notification deduplication: per-thread, by messageId + type (§37.6.3)
- [ ] Reaction dedup: once per hour per item (§37.6.3)

### 37.7-37.8 Muted Chat and DND
- [ ] Muted chat handling: skip entirely if thread AND sender muted (§37.7)
- [ ] Scheduled messages in muted chats: show but force silent (§37.7)
- [ ] Unmuted sender in muted group: show with sound (§37.7)
- [ ] DND integration: defer to OS-level DND on all platforms (§37.8)

### 37.9 Notification Actions
- [ ] Reply from custom notification: hover reveals button, expand, submit, cancel (§37.9.1)
- [ ] Reply from native: Linux inline reply, Windows fast reply, macOS reply button (§37.9.1)
- [ ] Reply button hidden when: text hidden, non-message type, can't send, broadcast, slowmode, etc. (§37.9.2)

### 37.10-37.13 Flash/Badge/Privacy/Userpic
- [ ] Flash taskbar / bounce dock: per-platform, controlled by flashBounceNotify toggle (§37.10)
- [ ] Badge/unread counter: update on unreadBadgeChanges, respect IncludeMuted/CountMessages (§37.11)
- [ ] Privacy levels: ShowPreview, ShowName, HideAll (§37.12)
- [ ] Passcode locked: force hide-everything mode (§37.12)
- [ ] Screen locked (native): forceHideDetails, hide content (§37.12)
- [ ] Spoiler login codes: replace with spoiler characters for notification users (§37.12)
- [ ] Hidden userpic placeholder: app logo scaled to 62x62, square (not rounded) (§37.12.1)
- [ ] Native hidden userpic: omit image (Linux), omit element (Windows), nil contentImage (macOS) (§37.12.1)
- [ ] Native userpic caching: 64px PNG in tdata/temp/, 60s TTL, keyed by InMemoryKey (§37.13)

---

## §38 — User Profile Popup (PeerShortInfoBox)

### 38.1 Triggers
- [ ] Ctrl+Click on "View Profile" context menu item opens ShortInfoBox (§38.1)
- [ ] Click user row in "Public Groups/Channels" limit box opens ShortInfoBox (§38.1)
- [ ] Click user avatar in gift/premium boxes opens ShortInfoBox (§38.1)

### 38.2 Cover Section
- [ ] Box width: 304px (§38.2/38.5)
- [ ] Square userpic area: 304x304px, fill width (§38.2)
- [ ] No-photo state: solid black square (§38.2)
- [ ] Multi-photo navigation: progress bars at top, left-third previous, right-two-thirds next (§38.2)
- [ ] Progress bars: 2px height, 8px padding, 4px gaps, groupCallVideoTextFg color, rounded caps (§38.2)
- [ ] Active bar fill progress, inactive bars at 50% opacity (§38.2)
- [ ] Name label: 15px semibold, white, position (25px left, 37px from bottom) (§38.2)
- [ ] Status label: below name, (25px left, 14px from bottom), groupCallVideoSubTextFg (§38.2)
- [ ] Additional status: "photo set by you" or "public photo" when applicable (§38.2)
- [ ] Shadow gradient: 80px from transparent to semi-opaque black at bottom (§38.2)
- [ ] Top shadow gradient for progress bar visibility (§38.2)
- [ ] Video profile photos: auto-play loop, radial loading indicator 2px thick (§38.2)
- [ ] Photo loading radial progress indicator while high-res loading (§38.2)
- [ ] Rounded top corners: 6px boxRadius (§38.2)

### 38.2 Info Rows Section
- [ ] Labeled key-value rows with 24px horizontal padding, 16px top padding (§38.2)
- [ ] Channel field: clickable channel name link (users with personal channel only) (§38.2)
- [ ] Link field: t.me link for groups/channels with public username (§38.2)
- [ ] Phone field: formatted phone number, "Copy Phone Number" context menu (§38.2)
- [ ] Bio/About field: multi-line with entity support, "Bio" for users / "About" for bots/groups (§38.2/38.7)
- [ ] Username field: @handle format, "Copy Mention" context menu (§38.2)
- [ ] Birthday field: dynamic label ("Birthday" / "Birthday today") (§38.2)
- [ ] Notes field: personal notes, multi-line with entity support (§38.2)
- [ ] Single-line fields: double-click selects paragraph (§38.2)
- [ ] Empty fields hidden via SlideWrap collapse (§38.2)

### 38.2 Buttons
- [ ] Right button: "Close" (§38.2)
- [ ] Left button for users: "Send Message" (§38.2)
- [ ] Left button for groups: "View Group" (§38.2)
- [ ] Left button for channels: "View Channel" (§38.2)
- [ ] No left button for Self type (§38.2/38 Self-Type)

### 38.3 Animations
- [ ] Appear/disappear: 200ms boxDuration, easeOutCirc, layerBg dimming (§38.3)
- [ ] Photo loading radial: fade in after fadeWrapDuration, fade out on complete (§38.3)
- [ ] No slide/crossfade between photos — instant update (§38.3)
- [ ] Scrolling parallax: name/status alpha fade proportional to scroll, progress bars fade (§38.3)
- [ ] Video playback: start immediately when ready, loop continuously (§38.3)

### 38.4-38.5 Positioning and Sizing
- [ ] Center horizontally and vertically in parent window (§38.4)
- [ ] Height clamped to parentHeight - margin (§38.4)
- [ ] Scroll bar: 8px wide, 3px inset, 150ms show, 1000ms hide delay (§38.5)
- [ ] Shadow max alpha: 80/255 (~31%) (§38.5)

### 38.6-38.7 Group/Bot Differences
- [ ] Groups/channels: member/subscriber count in status, no multi-photo slider (§38.6)
- [ ] Groups/channels: no phone, no birthday, no notes; Link field instead of username (§38.6)
- [ ] Bots: "About" label instead of "Bio" (§38.7)

### 38.9 Interaction
- [ ] Close by outside click on dimmed background (§38.9)
- [ ] Close by Escape key (§38.9)
- [ ] Right-click context menu: "Open in New Window" with popupMenuWithIcons style (§38.9)
- [ ] Photo navigation: left-click left-third/right-two-thirds, modular wrap (§38.9)
- [ ] Text selection: double-click paragraph select, right-click copy with contextual text (§38.9)
- [ ] Scrollable info rows with custom ScrollArea (§38.9)
- [ ] Cover fixed with parallax on scroll (§38.9)

### 38.10-38.12 Exclusions
- [ ] No story ring display (§38.10)
- [ ] No premium badges, verified badge, scam badge, or emoji status (§38.11)
- [ ] No keyboard photo navigation (§38.12)

---

## §39 — Photo & Avatar Cropping Dialog

### 39.1-39.2 Trigger and Layout
- [ ] Trigger from own profile photo upload, set photo for user, group/channel photo, camera capture (§39.1)
- [ ] Full-window layer, no close by outside click (§39.2)
- [ ] Blurred dimmed background: downscale 4x, 24px Gaussian blur, upscale, semi-transparent overlay (§39.2)
- [ ] Background dim: QColor(16,16,16,192) light, QColor(16,16,16,128) dark (§39.2)
- [ ] Background recache debounce: 200ms fast, 1000ms full, 200ms cross-fade (§39.14)
- [ ] Optional about text for set/suggest photo flows, centered above image (§39.2)
- [ ] Content margins: 20px left/top/right, 146px bottom (§39.2)

### 39.3 Image Display
- [ ] Image centered in content area, scaled to fit maintaining aspect ratio (§39.3)
- [ ] Rotation and flip transforms via QTransform (§39.3)
- [ ] Minimum 640x640 upscale for profile photos (§39.3)
- [ ] Extreme aspect ratio rejection (>10x) with error dialog (§39.3)

### 39.4 Crop Overlay
- [ ] Ellipse shape for standard user avatars (§39.4)
- [ ] RoundedRect shape for forum-type groups (§39.4)
- [ ] Rect shape for general image editing (§39.4)
- [ ] Square lock (1:1 ratio) for profile photos, corner-only handles (§39.4)
- [ ] Semi-transparent dark overlay outside crop: photoCropFadeBg (§39.4)
- [ ] Crop border: photoCropPointFg, 2x lineWidth, MiterJoin (§39.4)
- [ ] Corner indicators: bold white lines at all 4 corners, 4x lineWidth (§39.4)
- [ ] Rule-of-thirds grid: 3x3 inside crop, visible during drag only, 200ms fade (§39.4)
- [ ] 8 resize handles: 4 corners (10x10px), 4 edges (when not aspect-locked) (§39.4)
- [ ] Minimum crop size: 20px (§39.4)
- [ ] Initial crop: centered square at min(width, height) (§39.4)

### 39.5 Zoom Controls
- [ ] No zoom controls of any kind: no slider, no scroll-wheel, no pinch, no keyboard (§39.5)

### 39.6 Pan/Drag
- [ ] Move crop region: drag inside crop, clamp to image bounds (§39.6)
- [ ] Resize crop: drag corner/edge handles, aspect-ratio constraint for profiles (§39.6)
- [ ] Cursor feedback: diagonal resize for corners, h/v resize for edges, sizeall inside, default outside (§39.6)

### 39.7 Rotation
- [ ] 90-degree rotation via rotate button, wraps at 360 (§39.7)
- [ ] Horizontal flip via flip button, toggle icon to active color when flipped (§39.7)
- [ ] No free-angle rotation (§39.7)

### 39.9 Sticker/Emoji Avatar Builder
- [ ] Emoji builder as separate layer via AddEmojiBuilderAction menu item (§39.9)
- [ ] Full-screen layer with back button and "Save" button (§39.9)
- [ ] Sticker/emoji selector, gradient color picker, live circular preview (§39.9)
- [ ] Suggested stickers rotation with 1500ms cycle timer (§39.9)

### 39.11 Button Bar
- [ ] Bar height: 48px, width: 422px (§39.11)
- [ ] Bar outer padding: 2px left/right (§39.11)
- [ ] Left edge: "Cancel" in mediaviewCaptionFg on shadowFg background (§39.11)
- [ ] Center icons: Flip, Rotate, Paint Mode (brush) (§39.11)
- [ ] Right edge: "Set Photo" / "Suggest" / "Done" in mediaviewTextLinkFg (§39.11)
- [ ] Edge button margins: 4px all sides (§39.11)
- [ ] Text button horizontal padding: 22px each side (§39.11)
- [ ] Button label: 14px semibold, text top at 15px (§39.11)
- [ ] Icon tint: idle mediaviewPipControlsFg, hover mediaviewPipControlsFgOver, active lightButtonFg, disabled mediaviewPipPlaybackInactive (§39.11)
- [ ] Paint mode top bar: Undo, Redo with inactive styling when unavailable (§39.11)
- [ ] Paint mode bottom bar: Cancel, Paint icon, Stickers button, Done (§39.11)
- [ ] Aspect ratio menu: Original, Square, 3:2, 16:9, 9:16, Free (when available) (§39.11)

### 39.12 Keyboard Shortcuts
- [ ] Enter/Return: trigger Done action (§39.12)
- [ ] Escape: Cancel (Paint mode returns to Transform, Transform closes editor) (§39.12)
- [ ] Ctrl+Z: Undo paint action (§39.12)
- [ ] Ctrl+Y / Ctrl+Shift+Z: Redo paint action (§39.12)

### 39.13 Size Constraints
- [ ] Minimum output: 640x640px, upscale if smaller (§39.13)
- [ ] Minimum input: upscale to 640px before editor (§39.13)
- [ ] Max aspect ratio: reject if dimension exceeds 10x other (§39.13)

### 39.14 Animation
- [ ] Layer open/close: standard slide-up animation (§39.14)
- [ ] Control bar toggle: slide down + slide up, 200ms (§39.14)
- [ ] Grid overlay: instant fade-in on drag start, 200ms fade-out on drag end (§39.14)
- [ ] About text: FadeWrap toggle with 200ms animation on mode switch (§39.14)
- [ ] About label margins: 10px left/right, 22px top, 0px bottom (§39.14a)

---

## §40 — Send Files Dialog

### 40.1 Trigger
- [ ] Open via paperclip button with file picker (§40.1)
- [ ] Open via drag-and-drop files onto chat area (§40.1)
- [ ] Open via paste from clipboard (image data or files) (§40.1)
- [ ] Constructor receives PreparedList, prefilled caption, recipient, send type, limits (§40.1)

### 40.2 Album Preview
- [ ] Grouped album layout using LayoutMediaGroup algorithm (§40.2)
- [ ] Drag-to-reorder: shrink 5px inset over 150ms, drag spring-back 200ms (§40.2)
- [ ] Manhattan distance for closest-thumb target during drag (§40.2)
- [ ] Delete button (X) per thumbnail: sendBoxAlbumGroupButtonMediaDelete icon (§40.2)
- [ ] Edit/Replace button per thumbnail: sendBoxAlbumGroupButtonMediaMore icon (§40.2)
- [ ] Button capsule: 48x26px horizontal, top-right offset (5, 5), internal gap 8px (§40.2)
- [ ] Vertical capsule fallback: 30x50px for narrow thumbs (§40.2)
- [ ] Small group button: 30x25px with 27px circular button for smallest thumbs (§40.2)
- [ ] Double-click photo area: open photo editor (§40.2)

### 40.3 Send As Modes
- [ ] "Group files" checkbox: visible when 2+ compatible files, hidden in slowmode (§40.3)
- [ ] "Send as documents" checkbox: label changes by count (§40.3)
- [ ] "Remember" checkbox: appears only when user changed toggles, persists settings (§40.3)

### 40.4 Compression / Quality Toggle
- [ ] "Send in high quality" / "Send in standard quality" in hamburger menu (§40.4)
- [ ] HD badge: rounded pill with "HD" text, font from mediaPlayerSpeedButton (§40.4)
- [ ] HD badge: 2px h-padding, 0px v-padding, 1px stroke, radius height/3 (§40.4)
- [ ] HD badge: fill roundedBg, text roundedFg, 3px outer skip from corner (§40.4)
- [ ] Photo side limit: standard 1280px, HD 2560px (§40.4)

### 40.5 Spoiler Toggle
- [ ] Per-file spoiler via right-click context menu on thumbnail (§40.5)
- [ ] Bulk spoiler toggle in top-right menu (§40.5)
- [ ] Spoiler forced when paid price is set (§40.5)
- [ ] SpoilerAnimation renders animated blur/sparkle on preview (§40.5)

### 40.6 Caption Field
- [ ] InputField in MultiLine mode at dialog bottom (§40.6)
- [ ] Character limit: 4096, CharactersLimitLabel near emoji button (§40.6)
- [ ] Formatting support: bold, italic, underline, strikethrough, monospace, spoiler, links, custom emoji (§40.6)
- [ ] Emoji button: opens TabbedPanel in EmojiOnly mode (§40.6)
- [ ] Emoji suggestions: inline autocomplete via SuggestionsController (§40.6)
- [ ] Mention/hashtag autocomplete via FieldAutocomplete (§40.6)
- [ ] Submit settings: respect global send-submit-way (Enter/Ctrl+Enter) (§40.6)
- [ ] Caption hidden when canAddCaption returns false (§40.6)
- [ ] Caption position toggle: above/below media via menu (§40.6)
- [ ] Per-file captions when sending as documents, right-click "Edit caption" (§40.6)
- [ ] Paste interception: pasted images added as attachments, not inline text (§40.6)

### 40.7 Individual File Cards
- [ ] Thumbed layout: 64x64px rounded square, 4px radius, nameTop 7px, statusTop 37px, thumbSkip 10px (§40.7)
- [ ] Icon layout: 44x44px filled ellipse with icon, nameTop 6px, statusTop 27px, thumbSkip 11px (§40.7)
- [ ] Audio icon: history_file_play tinted historyFileInIconFg (§40.7)
- [ ] Image icon: history_file_image tinted historyFileInIconFg (§40.7)
- [ ] Document icon: history_file_document tinted historyFileInIconFg (§40.7)
- [ ] File name: semiboldFont, elided middle, max 64 chars (§40.7)
- [ ] File size/status: normalFont, FormatSizeText (§40.7)
- [ ] Caption line: below thumb, 6px top offset, single line elided (§40.7)
- [ ] Edit + Delete buttons: IconButton, top-right offset (2, 5), -1px gap (overlap) (§40.7)
- [ ] Drag-and-drop reorder for file blocks with custom MIME type (§40.7)

### 40.8 Grouped/Album Layout Algorithm
- [ ] Max album count: 10 items (§40.8)
- [ ] Album bounding width: 308px (§40.8)
- [ ] Sub-cell minimum width: 50px (§40.8)
- [ ] Spacing between cells: 2px (§40.8)
- [ ] Wide/narrow/square thresholds: >1.2, <0.8, between (§40.8)
- [ ] Corner rounding: outer corners only, radius 6px (§40.8)

### 40.9 Add More Files
- [ ] "Add" button at dialog bottom-left (§40.9)
- [ ] Async preparation for files beyond 10, one at a time (§40.9)
- [ ] Ctrl+O keyboard shortcut opens add-file dialog (§40.9)

### 40.10 Send Button
- [ ] Send button: right side, label "Send" / star cost for paid channels (§40.10)
- [ ] Send menu (right-click/long-press): silent send, schedule, send when online (§40.10)
- [ ] Send menu: spoiler on/off, caption above/below, photo quality toggles (§40.10)
- [ ] Send as sticker option: single image to WEBP conversion (§40.10)
- [ ] Ctrl+Shift+Enter: send with ctrlShiftEnter flag (§40.10)

### 40.11 File Type Detection
- [ ] Photo detection: valid image, MIME image/*, not animated, valid dimensions (§40.11)
- [ ] Video detection: PreparedFileInformation::Video with valid thumbnails (§40.11)
- [ ] Music detection: PreparedFileInformation::Song metadata (§40.11)
- [ ] Sticker detection: .tgs extension or IsMimeSticker (§40.11)
- [ ] MimeDataState classification: PhotoFiles, MediaFiles, Image, Files (§40.11)

### 40.12 Size Limits
- [ ] Free user: ~2.0 GiB file limit (§40.12)
- [ ] Premium user: ~4.0 GiB file limit (§40.12)
- [ ] Preview height cap: 1280px (§40.12)
- [ ] ValidateThumbDimensions: max 20x ratio (§40.12)
- [ ] TooLargeFile error handling (§40.12)

### 40.13 Drag-and-Drop Overlay
- [ ] Photo drop zone: for PhotoFiles/Image/MediaFiles when sendImagesAsPhotos (§40.13)
- [ ] Document drop zone: for Files or when photo-mode off (§40.13)
- [ ] Caption field acceptDrops(false) while drag zone active (§40.13)
- [ ] Mutual exclusion: only one zone visible at a time (§40.13)
- [ ] Opacity fade animation for drop zone overlay (§40.13)

### 40.14 Paste Handling
- [ ] MIME data hook: check for images or local file URLs (§40.14)
- [ ] Insert phase: route through PrepareMediaList or ReadMimeImage (§40.14)
- [ ] Append valid files to existing list, refresh preview (§40.14)

### 40.15-40.16 GIF and Audio
- [ ] GIF: classified as Type::None, animated playback in photo mode, icon in file mode (§40.15)
- [ ] Audio: SingleFilePreview with "Artist — Title" format (§40.16)
- [ ] Audio cover art: circular thumbnail if available, else colored circle with play icon (§40.16)
- [ ] Audio: no waveform in send preview (§40.16)

### 40.17 Keyboard Shortcuts
- [ ] Enter/Return: send (respecting submit-way setting) (§40.17)
- [ ] Ctrl+Shift+Enter: send with flag (§40.17)
- [ ] Ctrl+O: open add-file dialog (§40.17)
- [ ] Escape: close dialog, preserve unsaved caption (§40.17)

### 40.18 Animation
- [ ] Dialog open/close: standard BoxContent layer animation (§40.18)
- [ ] Album reorder: shrink 150ms, move 200ms, spring-back 200ms (§40.18)
- [ ] Height transitions: smooth animation on layout height change (§40.18)
- [ ] Emoji panel: toggleAnimated slide up/down (§40.18)
- [ ] Content shadow: fade shadows at top/bottom of scroll area (§40.18)

---

## §41 — Message Formatting Toolbar

### 41.1-41.2 Trigger and Position
- [ ] No floating toolbar — formatting via right-click context menu only (§41.1)
- [ ] Context menu at cursor position (e->globalPos()) with screen-edge avoidance (§41.2)
- [ ] "Formatting" item after "Delete" action, separated by divider (§41.2)

### 41.3 Layout
- [ ] Formatting submenu with all options and keyboard shortcut labels (§41.3)
- [ ] Submenu items: Bold, Italic, Underline, Strikethrough, Quote, Monospace, Spoiler (§41.3)
- [ ] Separator then: Create/Edit link, Date (§41.3)
- [ ] Separator then: Clear formatting (§41.3)
- [ ] Formatting parent action disabled when no text selected and no editLinkCallback (§41.3)

### 41.4 Formatting Options
- [ ] Bold: tag `**`, Ctrl+B, toggle on selection (§41.4)
- [ ] Italic: tag `__`, Ctrl+I, toggle on selection (§41.4)
- [ ] Underline: tag `^^`, Ctrl+U, toggle on selection (§41.4)
- [ ] Strikethrough: tag `~~`, Ctrl+Shift+X, toggle on selection (§41.4)
- [ ] Quote: tag `>`, Ctrl+Shift+., block-level at line boundaries (§41.4)
- [ ] Monospace: smart toggle — kTagPre for full lines, kTagCode for inline, Ctrl+Shift+M (§41.4)
- [ ] Spoiler: tag `||`, Ctrl+Shift+P, animated shimmer overlay (§41.4)
- [ ] Create/Edit link: Ctrl+K, opens EditLinkBox, validate URL contains `.` or `:` (§41.4)
- [ ] Date: Ctrl+Shift+D, CalendarBox then ChooseDateTimeBox, range 1970-2036 (§41.4)
- [ ] Clear formatting: Ctrl+Shift+N, remove all tags from selection (§41.4)

### 41.5 Notes Mode
- [ ] Reduced submenu for Saved Messages: no Quote, Monospace, Link, Date (§41.5)

### 41.6 Edit Link Dialog
- [ ] Box width: 320px (§41.6.1)
- [ ] Title: "Create Link" or "Edit Link" (§41.6.1)
- [ ] Field padding: margins(22, 0, 22, 10) per row (§41.6.1)
- [ ] Inner field width: 276px (§41.6.1)
- [ ] Text field: 276x55px, defaultInputField style, placeholder "Text" (§41.6.2)
- [ ] Text field: instant replaces, emoji suggestions, spellcheck (§41.6.2)
- [ ] URL field: 276px wide, placeholder "URL", pre-filled from clipboard (http/https/tonsite) (§41.6.3)
- [ ] URL field: height grows from 55px to max 148px for long URLs (§41.6.3)
- [ ] Submit validation: empty text/URL shows error border (§41.6.4)
- [ ] Enter in text field moves focus to URL field (§41.6.4)
- [ ] Enter in URL field: submit if text present, else focus text (§41.6.4)
- [ ] Tab cycling between fields (§41.6.4)
- [ ] Buttons: "Save"/"Create" primary, "Cancel" secondary (§41.6.5)

### 41.7 Code Block Language Dialog
- [ ] Box opened by clicking kTagPre block header strip (§41.7)
- [ ] Title: "Code Language" (§41.7.1)
- [ ] Description: "Language for syntax highlighting." with settingsAddReplyLabel style (§41.7.1)
- [ ] Language field: settingsAddReplyField style, 36px min height, placeholder "Auto-Detect" (§41.7.2)
- [ ] Max length: 32 chars with length limit counter (§41.7.3)
- [ ] Allowed chars: ASCII letters, digits, +, - only (§41.7.3)
- [ ] Auto-select all on open (§41.7.3)
- [ ] Buttons: "Save" primary, "Cancel" secondary (§41.7.4)
- [ ] Invalid regex shows error border, box stays open (§41.7.4)

### 41.8 Keyboard Shortcuts
- [ ] All 10 shortcuts: Ctrl+B/I/U, Ctrl+Shift+X/./M/P/K/D/N (§41.8)
- [ ] Shortcuts as QShortcut with Qt::WidgetShortcut scope (§41.8)
- [ ] Check _markdownEnabledState before applying (§41.8)

### 41.9 Markdown Auto-Conversion
- [ ] Live auto-conversion disabled (processMarkdownReplaces commented out) (§41.9)
- [ ] Send-time parsing via getTextWithAppliedMarkdown: **bold**, __italic__, ~~strike~~, `code`, ```block```, ||spoiler|| (§41.9)
- [ ] No markdown syntax for underline (^^) or blockquote (>) (§41.9)

### 41.10 Nested Formatting
- [ ] Tags stored as pipe-separated strings (§41.10)
- [ ] Toggle: remove if entire selection has tag, add if partial/missing (§41.10)
- [ ] Inline formats freely combinable (§41.10)
- [ ] Code/monospace replaces font entirely (§41.10)
- [ ] Block tags (blockquote, code block) contain inline tags (§41.10)
- [ ] Spoiler combines with any inline format (§41.10)
- [ ] Link coexists with formatting tags (§41.10)

### 41.11 Animation
- [ ] PopupMenu show: PanelAnimation expand from origin corner with clip+opacity (§41.11)
- [ ] Submenu: standard Qt hover mechanics, same PanelAnimation (§41.11)
- [ ] No animation for individual formatting actions — instant text style change (§41.11)

### 41.13 Visual Rendering in Compose Field
- [ ] Bold: bold font weight (§41.13)
- [ ] Italic: italic font style (§41.13)
- [ ] Underline: underline decoration (§41.13)
- [ ] Strikethrough: strikeout decoration (§41.13)
- [ ] Monospace/Code: monospace font + monoFg color (§41.13)
- [ ] Code block: monospace + monoFg + pre quote box with 20px header strip (§41.13)
- [ ] Spoiler: FieldSpoilerOverlay animated shimmer (§41.13)
- [ ] Link: linkFg color (§41.13)
- [ ] Blockquote: left rule + mini-quote icon, padding (10, 2, 20, 2) (§41.13.1)
- [ ] Blockquote base: 3px outline, 2px outlineShift, 5px radius, 4px verticalSkip (§41.13.1)
- [ ] Pre block: 20px header, scrollable, mini_copy icon at (4, 2) from top-right (§41.13.1)
- [ ] Blockquote expand/collapse chevron at (6, 4) from top-right (§41.13.1)

---

## §42 — Reactions Detail Popup

### 42.1 Triggers
- [ ] Right-click reaction button under message: ShowWhoReactedMenu popup (§42.1)
- [ ] Context menu "Who Reacted" row: summary line with up to 3 userpic circles (§42.1)
- [ ] "Show all" / click summary: open full Info Section panel (§42.1)
- [ ] Tag reactions in Saved Messages: ShowTagMenu instead (filter/edit/remove tag) (§42.1)

### 42.2 Context Menu Popup (Mode A)
- [ ] PopupMenu styled with whoReadMenu (§42.2)
- [ ] Optional "Set as Quick Reaction" action at top (§42.2)
- [ ] User list: WhoReactedEntryAction menu items (§42.2)
- [ ] "Show all reactions" row at bottom when fullReactionsCount > displayed (§42.2)
- [ ] Optional "Emoji Pack" action at bottom for custom emoji reactions (§42.2)

### 42.3 Full Info Section Panel (Mode B)
- [ ] Opens as layer widget or side panel (§42.3)
- [ ] Top bar title: "Seen by N" / "Listened by N" / "Watched by N" / "Reactions" (§42.3)
- [ ] Tab bar: horizontal row of pill-shaped buttons (§42.3)
- [ ] Scrollable peer list below tabs with 2px top/bottom margins (§42.3)

### 42.4 Tab Bar
- [ ] "Read" tab: shown when group with read receipts, icon per message type (§42.4.1)
- [ ] "All" tab: always present, reactionsTabAll icon (§42.4.1)
- [ ] Per-reaction tabs: one per distinct reaction, sorted by count descending (§42.4.1)
- [ ] Counts formatted with Lang::FormatCountDecimal (no abbreviation) (§42.4.1)
- [ ] Pill height: 32px (§42.4.2)
- [ ] Pill corner radius: 16px (fully rounded) (§42.4.2)
- [ ] Pill h-padding: 6px left, 12px right (§42.4.2)
- [ ] Pill width: 32 + 6 + textWidth + 12 = 50 + textWidth (§42.4.2)
- [ ] Icon area: 32x32px, emoji centered inside (§42.4.2)
- [ ] Icon size: 18 logical px (emojiSize) (§42.4.2)
- [ ] Icon left skip: 3px (§42.4.2)
- [ ] Font: semiboldFont 13px (§42.4.2)
- [ ] Background unselected: windowBg; selected: activeButtonBg (§42.4.2)
- [ ] Text color unselected: windowFg; selected: activeButtonFg (§42.4.2)
- [ ] Selection transition: 150ms (§42.4.2)
- [ ] Container padding: margins(12, 10, 12, 10) (§42.4.3)
- [ ] Inter-tab gap: 8px horizontal and vertical (§42.4.3)
- [ ] Wrapping: flow left-to-right, break to new row when no fit, no horizontal scroll (§42.4.3)
- [ ] Tab switching: instant, no transition animation (§42.4.4)
- [ ] Ripple animation: rounded-rect mask, radius height/2, 200ms (§42.4.5)

### 42.5 User List Items (Mode B)
- [ ] Row height: 58px (§42.5.1)
- [ ] Avatar size: 46px (§42.5.1)
- [ ] Avatar position: (18, 6) (§42.5.1)
- [ ] Name position: (79, 11) (§42.5.1)
- [ ] Status position: (79, 31) (§42.5.1)
- [ ] Name font: semiboldTextStyle 13px (§42.5.1)
- [ ] Name color: contactsNameFg; status color: windowSubTextFg (§42.5.1)
- [ ] Right-action emoji: 18x18px, margins L9/T20/R27/B0, centered vertically (§42.5.2)
- [ ] Custom emoji with AdjustCustomEmojiSize, animation with pause control (§42.5.2)
- [ ] Right action is decorative (disabled click) (§42.5.2)
- [ ] Date line in Mode A only (not Mode B full panel) (§42.5.3)
- [ ] Date icons: whoReadDateChecks (viewed), whoLikedDateHeart (reacted), whoRepostedDateHeart (reposted), whoForwardedDateHeart (forwarded) (§42.5.3)
- [ ] Date format: FormatReadDate today/yesterday/date (§42.5.3)

### 42.6-42.7 Pagination and Empty State
- [ ] First page: 20 items, subsequent: 100 items (§42.6)
- [ ] Infinite scroll: loadMoreRows when near bottom (§42.6)
- [ ] Separate allOffset and filteredOffset for pagination (§42.6)
- [ ] Loading state: "Loading..." description text (§42.6)
- [ ] Empty state: description cleared after results arrive (§42.7)

### 42.8-42.10 Anonymous/Custom/Tag Reactions
- [ ] Channels: canViewReactions flag required for reactor list (§42.8)
- [ ] Custom emoji in tabs: animated via ReactedMenuFactory with pause control (§42.9)
- [ ] Custom emoji in rows: right-side indicator, AdjustCustomEmojiSize (§42.9)
- [ ] "Emoji Pack" menu item for custom emoji from sticker sets (§42.9)
- [ ] Tag reactions: no user list, tag-specific menu (filter/edit/remove/sticker pack) (§42.10)

### 42.11 Animation
- [ ] Context menu popup: whoReadMenu duration, userpic delay after appear (§42.11)
- [ ] Tab switching: instant, clear and repopulate (§42.11)
- [ ] Info layer: _heightAnimation with slideDuration, slide down from top (§42.11)
- [ ] Custom emoji: Lottie-based, pause via GifPauseReason::Layer (§42.11)
- [ ] Ripple on tab press (§42.11)

### 42.12 Sizing
- [ ] Info panel desired width: 392px (§42.12)
- [ ] Info panel minimum margin: 48px (§42.12)
- [ ] Info panel top margin: windowHeight/24, clamped 20-40px (§42.12)
- [ ] Context menu entry height: 40px (photoSkip*2 + photoSize) (§42.12)
- [ ] Context menu avatar: 30px, photoLeft 13px, nameLeft 57px (§42.12)
- [ ] Context menu item padding: (44, 9, 17, 7) (§42.12)
- [ ] Summary userpics: size 22px, shift 8px, stroke 4px (§42.12)

### 42.13-42.15 Interaction
- [ ] Click user in Mode B: navigate to user profile info (§42.13)
- [ ] Click user in Mode A submenu: navigate to user profile with reaction context (§42.13)
- [ ] Click summary row (single user): open profile directly (§42.13)
- [ ] "Show all reactions" in submenu: open Mode B with DefaultSelectedTab (§42.13)
- [ ] Groups: both "who read" and "who reacted" tabs when eligible (§42.14)
- [ ] Channels: reaction tabs only, no "Read" tab (§42.14)
- [ ] DMs: WhenReadContextAction with "Read at HH:mm" (§42.14)
- [ ] Context menu keyboard: Enter/arrow keys, submenu on hover/right-arrow (§42.15)
- [ ] Full panel keyboard: tab focus, PeerListContent arrow/enter navigation (§42.15)

---

## §43 — Read Receipts Detail

### 43.1 Trigger
- [ ] Right-click context menu on messages: "Seen by N" / "Listened by N" / "Watched by N" (§43.1)
- [ ] Right-click reaction bubble: ShowWhoReactedMenu for specific emoji (§43.1)
- [ ] 1:1 chats: WhenReadContextAction with formatted read timestamp (§43.1)

### 43.2 Availability
- [ ] Private chats: outgoing, read, younger than pm_read_date_expire_period, not bot/service/self (§43.2)
- [ ] Small groups: outgoing, read, within chat_read_mark_expire_period, members <= 50 (§43.2)
- [ ] Excluded: channels, large groups (>50), self-chat, bot chats, ParticipantsHidden, monoforum (§43.2)
- [ ] Who-reacted list shown if canViewReactions, even for non-outgoing (§43.2)

### 43.3 Layout
- [ ] Context menu submenu (Mode A): icon + summary text + up to 3 userpic thumbnails (§43.3)
- [ ] Submenu max height: 400px with scroll padding (6px top, 4px bottom) (§43.3)
- [ ] Full info panel (Mode B): tabs at top + scrollable peer list (§43.3)
- [ ] Title adapts: "Seen by N" / "Listened by N" / "Watched by N" / "Reactions" (§43.3)

### 43.4 User List Items
- [ ] Row height: 40px (5*2 + 30) (§43.4.1)
- [ ] Avatar: 30px circular, left offset 13px, top offset 5px (§43.4.1)
- [ ] Name left: 57px from row left (§43.4.1)
- [ ] Name top single-line: centered vertically (§43.4.1)
- [ ] Name top with date: 3px from row top (§43.4.1)
- [ ] Date line top: 20px from row top (§43.4.1)
- [ ] Date icon-to-text gap: 15px (§43.4.1)
- [ ] Date icon position offset: (-7, -4) relative to text baseline (§43.4.1)
- [ ] Right edge inset: 17px (§43.4.1)
- [ ] Preloader skeleton: alpha 0.2 for avatar circle and name placeholder (§43.4.1)
- [ ] Date line icons: Viewed (read_ticks_s), Reacted (read_react_s), Reposted (mini_repost), Forwarded (mini_stats_share) (§43.4.2)
- [ ] Date text style: 12px font, color windowSubTextFg / windowSubTextFgOver (§43.4.3)
- [ ] Custom emoji reaction indicator at right edge, animated with pause control (§43.4.4)

### 43.5 Loading State
- [ ] Summary shows "Loading..." while WhoReadState::Unknown (§43.5)
- [ ] Userpic thumbnails delayed until _appeared flag set (menu animation complete) (§43.5)
- [ ] Full panel: "Loading..." description until results arrive (§43.5)
- [ ] Preloader skeleton: semi-transparent circle + rounded rect placeholder (§43.5)

### 43.6 Empty State
- [ ] "Nobody has seen yet" / "Nobody listened" / "Nobody watched" / "No reactions yet" (§43.6)
- [ ] Menu item disabled when participants empty and state is not MyHidden (§43.6)

### 43.7 Partial Reads
- [ ] Merge reaction and read lists: users who read AND reacted get merged entry (§43.7)
- [ ] Combined summary: "N reacted / M seen" format (§43.7)
- [ ] Per-user type tag: Viewed (checkmarks) vs Reacted (heart) (§43.7)

### 43.8 Time Info
- [ ] Per-user read timestamps: private via GetOutboxReadDate, groups via GetMessageReadParticipants (§43.8)
- [ ] FormatReadDate: "Today, HH:mm" / "Yesterday, HH:mm" / "Mon DD, HH:mm" / "Mon DD YYYY, HH:mm" (§43.8)
- [ ] dateReacted flag: reaction time vs read time icon selection (§43.8)

### 43.9 Animation
- [ ] Context menu: standard PopupMenu appear/disappear (§43.9)
- [ ] Userpic thumbnails delayed: render after menu animation completes (§43.9)
- [ ] Fallback call_delayed ensures userpics appear (§43.9)
- [ ] Submenu: standard Qt PopupMenu slide-in from side (§43.9)

### 43.10 Sizing
- [ ] Summary row: item padding (44, 9, 17, 7), height ~30px (§43.10.1)
- [ ] Summary left icon at (15, 7) (§43.10.1)
- [ ] Summary right userpics: 22px size, 8px shift, 4px stroke, max 3 circles (§43.10.1)
- [ ] Submenu whoReadMenu: scroll padding (0, 6, 0, 4), max height 400px (§43.10.2)
- [ ] When-read line (1:1): padding (34, 3, 17, 4), icon at (8, 0), 3px gap (§43.10.3)
- [ ] When-read font: 12px, row height ~19px (§43.10.3)
- [ ] "Show" button: pill with font->height radius, 6px h-padding (§43.10.3)
- [ ] Summary icons: whoReadChecks (seen), whoReadPlayed (listened/watched), whoReadReactions (reacted) at (15, 7) (§43.10.4)
- [ ] Disabled icon variants tinted menuFgDisabled (§43.10.4)
- [ ] Animation timing: userpic reveal delayed by parentMenu->st().duration (~150ms) (§43.10.5)

### 43.11 Interaction
- [ ] Single participant: click opens user profile (§43.11)
- [ ] Multiple with reactions: click opens full Info::ReactionsList panel (§43.11)
- [ ] Submenu user entry: click navigates to user profile info (§43.11)
- [ ] "Show All" entry: opens full panel when fullReactionsCount > visible (§43.11)
- [ ] Full panel row click: navigate to user profile (§43.11)

### 43.12 Privacy
- [ ] MyHidden state: "Read time hidden" with "Show" pill button (§43.12)
- [ ] HisHidden state: other user has hidden read time (§43.12)
- [ ] TooOld state: message older than expiry period (§43.12)
- [ ] "Show" click: dialog to disable hide-read-time or get Premium (§43.12)
- [ ] readDatesPrivate flag: no read receipt UI shown (§43.12)

### 43.13 AyuGram-Specific
- [ ] Ghost Mode: sendReadMessages toggle suppresses read receipts (§43.13)
- [ ] Ghost Mode: sendReadStories toggle suppresses story views (§43.13)
- [ ] Ghost Mode: markReadAfterAction marks read on reply/react (§43.13)
- [ ] Blocked user filtering: silently remove blocked peers from lists (§43.13)
- [ ] showViewsPanelInContextMenu: visibility control for read receipt menu item (§43.13)
- [ ] showMessageSeconds: "HH:mm:ss" timestamp format (§43.13)

---

## §44 — Spoiler Animation

### 44.1 Text Spoiler Rendering
- [ ] Text drawn at reduced opacity (1 - spoilerOpacity), fully hidden at 1.0 (§44.1)
- [ ] Collect spoiler ranges into _spoilerRanges, convert to pixel rects (max 512) (§44.1)
- [ ] Tile particle animation frame over each rect via FillSpoilerRect() (§44.1)
- [ ] Separate rect lists for normal (spoilerFg) and selected (selectSpoilerFg) states (§44.1)
- [ ] SpoilerMessCache: up to 24 color variants, reset on palette change (§44.1)
- [ ] Cross-fade: text opacity = revealValue, particles opacity = 1 - revealValue (§44.1)

### 44.2 Media Spoiler Rendering
- [ ] Blurred background: smallest thumbnail scaled to fill, rounded with bubble corners (§44.2)
- [ ] Particle overlay tiled via fillImageSpoiler() with corner masks (§44.2)
- [ ] Darken layer: kImageSpoilerDarkenAlpha = 32 (QColor(0,0,0,32)) (§44.2)
- [ ] Real image underneath at opacity = revealed, cross-fade on reveal (§44.2)

### 44.3 Shimmer Effect — Particle Sprite Sheet
- [ ] Text spoiler: 9,000 particles, speed 4-8 dp/ms, fade in/shown/out 200/200/200ms (§44.3)
- [ ] Image spoiler: 3,000 particles, speed 10-20 dp/ms, fade in/out 300/0/300ms (§44.3)
- [ ] Particle size: 1.5-2.0 dp, lifetime 600ms (§44.3)
- [ ] 5 sprite variants: rounded rectangles varying in aspect ratio (§44.3)
- [ ] Canvas: 128dp x DPR (§44.3)
- [ ] Frame count: 60 frames at 33ms (~30 FPS), 1,980ms total loop (§44.3)
- [ ] Sprite sheet: 10 frames per row, 10x6 grid (§44.3)
- [ ] Particle position: linear motion with seamless wrapping (§44.3)
- [ ] Particle opacity: fade-in, full, fade-out lifecycle (§44.3)
- [ ] Disk caching: grayscale PNG with xxHash32 check, max 5MB (§44.3)
- [ ] Colorize on demand: expand grayscale to ARGB32 premultiplied (§44.3)

### 44.4 Reveal on Click
- [ ] Text reveal: SpoilerClickHandler, 200ms fadeWrapDuration, linear (§44.4)
- [ ] Reveals all spoilers in text block at once (§44.4)
- [ ] Re-hiding: instant (no animation) via hideShownSpoilers on navigation (§44.4)
- [ ] Media reveal: 200ms fadeWrapDuration, real image at opacity=revealed (§44.4)
- [ ] Media re-hiding: instant, reset on navigate away and back (§44.4)
- [ ] Track revealed views in _shownSpoilers set (§44.4)

### 44.5 Compose Field Spoiler
- [ ] FieldSpoilerOverlay: WA_TransparentForMouseEvents, clicks pass through (§44.5)
- [ ] Compute spoiler rects from _spoilerRangesText and _spoilerRangesEmoji (§44.5)
- [ ] Tile text spoiler particles with defaultTextPalette.spoilerFg (§44.5)
- [ ] Cursor inside spoiler: overlay fades to 0.5 opacity over 200ms (§44.5)
- [ ] Cursor leaves spoiler: overlay fades back to full opacity (§44.5)
- [ ] Background filled with textBg (or blockquoteBg inside blockquote) (§44.5)
- [ ] Opacity: bgOpacity = shown, fgOpacity = 1.0*shown + 0.5*(1-shown) (§44.5)

### 44.6 Spoiler in Notifications
- [ ] Replace spoiler characters with U+259A (checkerboard block) (§44.6)
- [ ] Login code auto-spoiler: regex for numeric codes from notification/verify bots (§44.6)

### 44.7 Performance
- [ ] Pre-rendered sprite sheet: 60 frames computed once, cached to disk (§44.7)
- [ ] FillSpoilerRect: batched tiling, full-tile vs partial-tile optimized paths (§44.7)
- [ ] Auto-pause after 1000ms if not visible (§44.7)
- [ ] Power saving kChatSpoiler (bit 7): freeze animation when enabled (§44.7)
- [ ] Corner masking: CompositionMode_DestinationIn for rounded bubble corners (§44.7)
- [ ] Single SpoilerAnimationManager for all instances (§44.7)

### 44.8 Style Constants
- [ ] fadeWrapDuration: 200ms reveal/hide (§44.8)
- [ ] kDefaultFrameDuration: 33ms frame interval (§44.8)
- [ ] kDefaultFramesCount: 60 frames (§44.8)
- [ ] kFramesPerRow: 10 (§44.8)
- [ ] kImageSpoilerDarkenAlpha: 32 (§44.8)
- [ ] kAutoPauseTimeout: 1000ms (§44.8)
- [ ] kSpoilerHiddenOpacity: 0.5 (§44.8)
- [ ] kDefaultSpoilerCacheCapacity: 24 (§44.8)
- [ ] kMaxCacheSize: 5MB (§44.8)
- [ ] spoilerFg: msgInDateFg; selectSpoilerFg: msgInDateFgSelected (§44.8)
- [ ] PowerSaving::kChatSpoiler: bit 7 (0x80) (§44.8)

# GUI Checklist: Sections 45-54

## 45. Custom Emoji Rendering

### 45.1 Inline Rendering
- [ ] Render custom emoji inline at 18px logical size with 1.12x adjusted frame (20px) (§45.1)
- [ ] Apply -1px centering offset for custom emoji within text flow (§45.1)
- [ ] Add 1px horizontal padding on each side of inline custom emoji (§45.1)
- [ ] Align custom emoji vertically with QTextCharFormat::AlignTop (§45.1)
- [ ] Tint custom emoji to match surrounding text color when UseTextColor flag is set (§45.1)

### 45.2 Large Emoji (Isolated Messages)
- [ ] Detect messages containing only custom emoji (no text/links) and render as UnwrappedMedia (§45.2)
- [ ] Render 1-emoji messages at 112px sticker-like size (§45.2)
- [ ] Render 2-emoji messages at ~78px (0.7x scale) in sticker grid (§45.2)
- [ ] Render 3-emoji messages at ~58px (0.52x scale) in sticker grid (§45.2)
- [ ] Render 4-5 emoji messages at ~43px Isolated SizeTag (§45.2)
- [ ] Render 6-7 emoji messages at ~27px Large SizeTag (§45.2)
- [ ] Render 8+ emoji messages at ~20px Normal SizeTag (§45.2)
- [ ] Support native emoji isolated rendering (1-3 native emoji) via IsolatedEmoji (§45.2)

### 45.3 Animated Custom Emoji
- [ ] Support TGS (Lottie) custom emoji animation playback (§45.3)
- [ ] Support WebM (video sticker) custom emoji playback (§45.3)
- [ ] Support WebP (static) custom emoji rendering (§45.3)
- [ ] Decode animation frames asynchronously on worker thread (§45.3)
- [ ] Preload 3 frames ahead of current playback position (§45.3)
- [ ] Cap animations at 180 frames maximum (§45.3)
- [ ] Pause animations when context.paused is true (§45.3)
- [ ] Respect PowerSaving flags (kEmojiChat, kEmojiPanel, kEmojiReactions, kEmojiStatus) (§45.3)
- [ ] Support LimitedLoopsEmoji wrapper to freeze after N loops (§45.3)

### 45.4 Premium-Only Indicators
- [ ] Bypass premium restriction for custom emoji (AyuGram: AllowEmojiWithoutPremium = true) (§45.4)
- [ ] Fall back to sticker alt text for non-premium users in non-AyuGram mode (§45.4)

### 45.5 Custom Emoji in Names (Emoji Status)
- [ ] Render emoji status next to peer name in chat headers, dialogs, and profile (§45.5)
- [ ] Support collectible emoji status with custom center/edge colors (§45.5)
- [ ] Support userpic emoji prefix rendering circular userpic inline (§45.5)
- [ ] Respect kEmojiStatus power saving flag for status animations (§45.5)

### 45.6 Custom Emoji in Reactions
- [ ] Render default Unicode reactions via centerIcon at 2x emojiSize (§45.6)
- [ ] Render custom emoji reactions at SizeTag::Normal (18px/20px) (§45.6)
- [ ] Open floating preview overlay on custom emoji reaction click (§45.6)
- [ ] Show clickable pack-name label as "View Pack" affordance in preview overlay (§45.6)

### 45.7 Loading States
- [ ] Show SVG path preview placeholder at 12.5% opacity during loading (§45.7)
- [ ] Show cross-resolution image preview as fallback during loading (§45.7)
- [ ] Show blank space when no preview exists (§45.7)
- [ ] Transition from Loading to Caching (paint decoded frames as they arrive) (§45.7)
- [ ] Transition from Caching to Cached (all frames in sprite atlas) (§45.7)

### 45.8 Caching
- [ ] Implement in-memory instance cache per (DocumentId, SizeTag) (§45.8)
- [ ] Share instances across multiple Object wrappers with reference counting (§45.8)
- [ ] Implement disk sprite atlas cache with LZ4 compression (§45.8)
- [ ] Pack frames 16-per-row in sprite atlas (§45.8)
- [ ] Support cross-resolution preview from cached frames at different size tiers (§45.8)
- [ ] Evict in-memory instances when all Object references removed (§45.8)

### 45.9 Click Behavior
- [ ] Make custom emoji in text messages clickable via CustomEmojiClickHandler (§45.9)
- [ ] Open reaction/emoji preview overlay on click (§45.9)
- [ ] Show "View Pack" rounded rectangle in overlay with pack name label (§45.9)
- [ ] Open StickerSetBox on "View Pack" click for Data::StickersType::Emoji (§45.9)
- [ ] Support tap splash interaction effect for single isolated custom emoji (§45.9)

### 45.10 Custom Emoji in Input Field
- [ ] Render custom emoji in compose field using QTextObjectInterface system (§45.10)
- [ ] Insert custom emoji with Unicode fallback alt text and custom emoji link tag (§45.10)
- [ ] Size custom emoji in input at 20px width, max(fontLineHeight, 18px) height (§45.10)
- [ ] Coalesce repaint requests for multiple emoji in input field (§45.10)

### 45.11 Performance
- [ ] Batch repaint requests by (when, duration) into RepaintBunch buckets (§45.11)
- [ ] Batch unknown document IDs up to 100 per API resolution call (§45.11)
- [ ] Use static PaintCache QImage for text-color-tinted emoji to avoid per-frame allocation (§45.11)

### 45.14 Reaction/Emoji Preview Overlay
- [ ] Render MediaPreviewWidget centered in viewport with 120ms show/hide animation (§45.14)
- [ ] Show full-viewport invisible click-catcher with semi-transparent backdrop (§45.14)
- [ ] Render "View Pack" rounded-shadow rectangle at 75% vertical position (§45.14)
- [ ] Apply box shadow with 10px extend margins around View Pack rectangle (§45.14)
- [ ] Fill View Pack rectangle with windowBg at 8px boxRadius corner rounding (§45.14)
- [ ] Show FlatLabel with pack name inside View Pack rectangle (§45.14)
- [ ] Cross-fade View Pack rectangle in/out over 120ms (§45.14)
- [ ] Dismiss overlay on click outside, Escape key, or window resize (§45.14)

---

## 46. Link Preview in Compose

### 46.1 Detection
- [ ] Parse URLs in compose field using regex domain matching (§46.1)
- [ ] Debounce URL detection: 0ms for large changes (>2 chars), 500ms for small changes (§46.1)
- [ ] Trigger immediate parse on whitespace keypress or drop event (§46.1)
- [ ] Skip URLs inside code/pre formatting blocks (§46.1)
- [ ] Handle custom links (markdown link tags with explicit URLs) (§46.1)

### 46.2 Preview Card (FieldHeader)
- [ ] Render FieldHeader bar at 49px height, full width above compose field (§46.2)
- [ ] Paint left icon (historyLinkIcon) at position (7, 7) from top-left (§46.2)
- [ ] Swap left icon for edit/reply/quote/forward variants per bar state (§46.2)
- [ ] Render 32x32px thumbnail at (53, 8) when available (§46.2)
- [ ] Start text at 95px when thumbnail present, 53px when absent (§46.2)
- [ ] Render title in semibold font, color historyReplyNameFg, single line elided (§46.2)
- [ ] Render description below title in messageTextStyle, color historyComposeAreaFg (§46.2)
- [ ] Show 49x49px cancel (X) button anchored top-right with 40px ripple area (§46.2)
- [ ] Paint flat historyComposeAreaBg background (no border, no shadow) (§46.2)
- [ ] Elide text width = bar.width - previewLeft - 49 - 11 (§46.2)

### 46.3 Large vs Small Media
- [ ] Default to small (article) layout for profile pages (§46.3)
- [ ] Default to large layout for Twitter, Facebook, ArticleWithIV types (§46.3)
- [ ] Default to large layout for collage pages and pages without text metadata (§46.3)
- [ ] Support forceLargeMedia / forceSmallMedia toggles in DraftOptionsBox (§46.3)

### 46.4 Preview Above/Below Text
- [ ] Support WebPageDraft.invert flag to position preview above message text (§46.4)
- [ ] Show "Move up" / "Move down" buttons in DraftOptionsBox with appropriate icons (§46.4)

### 46.5 Multiple URLs
- [ ] Pick first URL with cached resolved page or untried URL for preview (§46.5)
- [ ] Show "Tap on a link in the message to choose a preview" divider for multiple URLs (§46.5)
- [ ] Support clicking different links in PreviewWrap to switch active preview (§46.5)

### 46.6 Preview Loading
- [ ] Show "Loading..." title and URL as description while page is pending (§46.6)
- [ ] Hide thumbnail during loading state (§46.6)
- [ ] Start retry timer based on pendingTill timestamp (§46.6)
- [ ] Auto-update preview when page data arrives via webPageUpdates stream (§46.6)

### 46.7 No Preview Available
- [ ] Fall through to next link when current link resolves to null (§46.7)
- [ ] Clear preview data when all links resolve to null (§46.7)
- [ ] Show toast "Sorry, the preview for this link is not available." in DraftOptionsBox (§46.7)

### 46.8 Remove Preview
- [ ] Remove preview on cancel (X) button click, set WebPageDraft.removed = true (§46.8)
- [ ] Persist removed flag in draft so preview stays hidden while typing (§46.8)
- [ ] Show red "Remove link preview" button in DraftOptionsBox (§46.8)
- [ ] Auto-reset removed flag when all URLs are deleted from compose field (§46.8)

### 46.9 Webpage Types
- [ ] Support 30+ WebPageType enum values with correct layout behavior (§46.9)
- [ ] Render article layout (small thumbnail right, text left) for _asArticle=1 (§46.9)
- [ ] Render full-width media layout for _asArticle=0 (§46.9)
- [ ] Show action button bar (36px height) on rendered messages for applicable types (§46.9)
- [ ] Render action button labels centered in semibold font with cache->icon color (§46.9)
- [ ] Draw 1px top divider line at 30% alpha above action button (§46.9)
- [ ] Show correct per-type action label (INSTANT VIEW, VIEW CHANNEL, etc.) (§46.9)
- [ ] Show DraftOptionsBox modal for compose-side preview controls (§46.9)
- [ ] Support DraftOptionsBox buttons: Move up/down, Enlarge/Shrink photo, Remove preview (§46.9)

### 46.10 Instant View
- [ ] Detect Instant View availability when WebPageData.iv is non-null (§46.10)
- [ ] Show "INSTANT VIEW" button in message preview bubble (§46.10)
- [ ] Open built-in Instant View reader on IV button click (§46.10)

### 46.11 API Call
- [ ] Call MTPmessages_GetWebPagePreview for URL resolution (§46.11)
- [ ] Support AyuGram getBetterLinkPreview URL rewriting (x.com -> fixupx.com, etc.) (§46.11)
- [ ] Attach preview via MTPinputMediaWebPage with force_large/small/optional flags on send (§46.11)

### 46.12 Debouncing
- [ ] Implement two-level debouncing: link parsing (0ms/500ms) and API request (single active) (§46.12)
- [ ] Cancel previous API requests when switching to different link (§46.12)

### 46.13 Cache
- [ ] Implement resolver-level URL-to-WebPageData in-memory cache (§46.13)
- [ ] Maintain session-level WebPageData cache keyed by WebPageId (§46.13)
- [ ] Persist WebPageDraft in message draft for cross-session continuity (§46.13)

---

## 47. Restricted Permissions UI

### Write Restriction Bar
- [ ] Replace entire compose area with write restriction widget at 46px height (§47)
- [ ] Show Rights restriction: centered FlatLabel with restriction text, no click handler (§47)
- [ ] Show PremiumRequired restriction: label "{user} only accepts messages from Premium users" + "Unlock" RoundButton + lock icon (§47)
- [ ] Open Premium promo toast on PremiumRequired "Unlock" click (§47)
- [ ] Show Frozen restriction: title "Your account is frozen" + subtitle "Click to view details" in red (§47)
- [ ] Open freeze info dialog on Frozen restriction click (§47)
- [ ] Hide compose area completely for Hidden restriction type (stories) (§47)
- [ ] Show boost button "Boost this group to send messages" when boostsToLift > 0 (§47)

### Permission-Specific Restriction Text
- [ ] Show timed personal restriction messages with date/time for all 11 restriction types (§47)
- [ ] Show permanent personal restriction messages for all 11 restriction types (§47)
- [ ] Show default group restriction messages for all 11 restriction types (§47)
- [ ] Show user-level restriction messages for voice/video/premium in DMs (§47)

### Grayed/Forbidden Send Button
- [ ] Paint record/round button at 50% opacity when forbidden (§47)
- [ ] Suppress ripple effect on forbidden buttons (§47)
- [ ] Show toast with restriction error text when forbidden button is tapped (§47)
- [ ] Set default (non-pointer) cursor on forbidden buttons (§47)

### Slow Mode
- [ ] Display countdown timer in MM:SS format on send button during slowmode (§47)
- [ ] Render countdown in 13px normalFont, windowSubTextFg color, centered (§47)
- [ ] Refresh countdown every 200ms (§47)
- [ ] Set non-pointer cursor during slowmode countdown (§47)
- [ ] Show accessible name "Slow Mode is active. You can send your next message in {duration}" (§47)
- [ ] Disable send button while message is still being sent in slowmode (§47)
- [ ] Block multiple file sends in slowmode with error toast (§47)
- [ ] Block long text that would split into multiple messages in slowmode (§47)

### Banned/Kicked State
- [ ] Show "Sorry, this group is not accessible." for kicked/banned users (§47)
- [ ] Show full-width "UNBLOCK" button for blocked users (§47)
- [ ] Show "RESTART" instead of "UNBLOCK" for blocked bots (§47)
- [ ] Call unblockUser API on unblock button click (§47)

### Join to Send
- [ ] Show "JOIN CHANNEL" / "JOIN GROUP" / "APPLY TO JOIN GROUP" button for non-members (§47)
- [ ] Uppercase all join button text (§47)
- [ ] Call session.api.joinChannel on click (§47)

### Mute/Unmute State
- [ ] Show "MUTE" / "UNMUTE" full-width button for broadcast channels without post rights (§47)
- [ ] Show "DISCUSS" button alongside mute button when discussion group exists (§47)

### Forum Topic Closed
- [ ] Show "This topic is closed." restriction bar for closed topics (§47)
- [ ] Reactively restore compose field when admin reopens topic (§47)
- [ ] Keep compose functional for users with ManageTopics admin right even when topic closed (§47)

### Channel Comments Button
- [ ] Show comments toggle IconButton in compose area for broadcast channels with discussion groups (§47)
- [ ] Support three visual states: Empty, Shown, Hidden, WithNew (§47)
- [ ] Render new-comments dot indicator (6px, dialogsBgActive color) on WithNew state (§47)
- [ ] Position comments button leftmost in compose bar (§47)

### Send Button States
- [ ] Render Send type: arrow icon in filled blue circle (§47)
- [ ] Render Record type: microphone Lottie animation in historyRecordVoiceFg (§47)
- [ ] Render Round type: video camera Lottie animation (§47)
- [ ] Render Cancel type: X icon for inline bot cancel (§47)
- [ ] Render Save type: checkmark icon for message editing (§47)
- [ ] Render Schedule type: clock icon in filled circle (§47)
- [ ] Render Slowmode type: text countdown with no icon (§47)
- [ ] Animate Record <-> Round transitions via Lottie playback (§47)
- [ ] Crossfade other type transitions with opacity + scale over universalDuration (§47)
- [ ] Show star icon + count for paid messages (starsToSend > 0) (§47)
- [ ] Gray out send icon when disabled (historyRecordVoiceFg color) (§47)

### Bot Start Button
- [ ] Show "START" button for first-time bot chats (§47)
- [ ] Include start token prefix in button text if present (§47)

### Toast Behavior
- [ ] Show restriction toast at bottom center, 1500ms duration (§47.16)
- [ ] Apply toast padding 19/13/19/12px, width 160-360px, 6px corner radius (§47.16)
- [ ] Animate toast: 200ms fade in, 1000ms fade out, 160ms slide (§47.16)

---

## 48. Drag-and-Drop File Overlay

### 48.1 Drop Zone Appearance
- [ ] Render drop zones as rounded rectangles with boxBg background and boxRoundShadow (§48.1)
- [ ] Apply drag margin (0, 10, 0, 10)px and drag padding (20, 10, 20, 10)px (§48.1)
- [ ] Render main text in 27px semibold font (§48.1)
- [ ] Render subtext in 19px semibold font (§48.1)
- [ ] Start text color at windowSubTextFg (subdued gray) (§48.1)
- [ ] Animate text color to windowActiveTextFg (accent) on hover (§48.1)

### 48.2 Two-Zone Layout
- [ ] Show single document zone for Files state (full height) (§48.2)
- [ ] Show two zones (document top, photo bottom) for PhotoFiles state (§48.2)
- [ ] Show two zones with media labels for MediaFiles state (§48.2)
- [ ] Show single photo zone for Image state (full height) (§48.2)

### 48.3 Zone Detection
- [ ] Detect cursor inside padded region on drag move and trigger highlight (§48.3)
- [ ] Set drop action to CopyAction when inside zone, IgnoreAction when outside (§48.3)

### 48.4 File Type Detection
- [ ] Classify dragged files: Image, PhotoFiles, MediaFiles, Files, or None (§48.4)
- [ ] Reject null data, forward data, non-local URLs, directories, files >4GB (§48.4)
- [ ] Classify GIFs as MediaFiles/Files, never PhotoFiles (§48.4)

### 48.5 Animation
- [ ] Fade overlay in/out over 200ms (boxDuration) with pixmap cache (§48.5)
- [ ] Animate highlight color transition over 200ms on zone hover (§48.5)
- [ ] Instant hide (no fade) on drop (§48.5)

### 48.6 Text Labels
- [ ] Show correct localized text labels for each drag state (§48.6)

### 48.8 Edge Cases
- [ ] No overlay for text-only drags (§48.8)
- [ ] No overlay for message forward drags (application/x-td-forward) (§48.8)
- [ ] No overlay during active voice recording (§48.8)

### 48.9 Disabled State
- [ ] Check CanSendAnyOf permission before showing overlay (§48.9)
- [ ] Verify canWriteMessage on drop (§48.9)

### 48.11 Forwarding via Drag
- [ ] Support dragging messages between chats with x-td-forward MIME (§48.11)
- [ ] Open target chat after 1s hover over dialog in chat list (§48.11)
- [ ] Navigate back after 1s hover over back button during drag (§48.11)
- [ ] Show topic chooser for forum peer drops (§48.11)

---

## 49. Scroll Behaviors

### 49.1 Infinite Scroll
- [ ] Preload messages when within 3 viewport heights of loaded content edge (§49.1)
- [ ] Fetch 50 messages per page (30 for first load) (§49.1)
- [ ] Shift viewer around position using 9-screen window (4+1+4) (§49.1)

### 49.2 Jump-to-Date
- [ ] Open CalendarBox on sticky date header click (§49.2)
- [ ] Set calendar min date to Telegram launch (Aug 2013) or first message (§49.2)
- [ ] Support month thumbnail images for media-filtered searches (§49.2)
- [ ] Resolve closest message ID via API on date selection and navigate (§49.2)

### 49.3 Jump-to-Message
- [ ] Animate short scroll (delta <= 1 viewport) with sine in-out easing (§49.3)
- [ ] Jump instantly then ease-out cubic for long scroll (delta > 1 viewport) (§49.3)
- [ ] Show highlight effect: 400ms fade-in, optional hold+collapse, 2000ms fade-out (§49.3)
- [ ] Queue multiple highlights and process sequentially (§49.3)

### 49.4 Unread Marker
- [ ] Show "N unread messages" divider bar on first unread message (§49.4)
- [ ] Destroy unread bar when user scrolls to bottom or sends message (§49.4)

### 49.5 Scroll-to-Bottom Button
- [ ] Show circular JumpDownButton with down-arrow at 12px right, 10px from bottom (§49.5)
- [ ] Show button when scrolled up >480px or unread messages exist below (§49.5)
- [ ] Render unread badge (22px circle/pill) with semibold 13px font at button top (§49.5)
- [ ] Jump to UnreadMessagePosition on click (Ctrl: force jump, no Ctrl: reply-return) (§49.5)
- [ ] Animate button slide-up over 150ms (§49.5)
- [ ] Render 52x62px button with shadow circle + ripple + arrow icon layers (§49.15)

### 49.6 New Message Scroll
- [ ] Auto-scroll to bottom on own sent messages (§49.6)
- [ ] Only process incoming messages when already at bottom (§49.6)
- [ ] Increment unread badge when not at bottom (§49.6)

### 49.7 Scroll Position Preservation
- [ ] Save scrollTopItem + scrollTopOffset per History on chat switch (§49.7)
- [ ] Restore saved scroll position on return to chat (§49.7)
- [ ] Bracket every refreshRows call with saveScrollState/restoreScrollState (§49.7)

### 49.8 Smooth Scrolling
- [ ] Animate scroll over 240ms (slideDuration) (§49.8)
- [ ] Use sineInOut easing for short scrolls, easeOutCubic for long scrolls (§49.8)
- [ ] Anchor animation to specific HistoryItem for stability during content changes (§49.8)

### 49.9 Scroll-to-Mention Button
- [ ] Show "@" icon corner button when unread mentions exist (§49.9)
- [ ] Jump to oldest unread mention on click (§49.9)
- [ ] Stack above scroll-to-bottom button with 4px gap (§49.9)

### 49.10 Scroll-to-Reaction Button
- [ ] Show heart icon corner button when unread reactions exist (§49.10)
- [ ] Jump to oldest unread reaction on click (§49.10)
- [ ] Stack above mentions button (§49.10)

### 49.11 Keyboard Scrolling
- [ ] Forward PageUp/PageDown/Down keys to scroll widget (§49.11)
- [ ] Trigger "edit last message" on Up key when field empty (§49.11)
- [ ] Support middle-click autoscroll with directional cursor and continuous scroll (§49.11)
- [ ] Stop autoscroll on Escape or any mouse button (§49.11)

### 49.13 Sticky Date Header
- [ ] Paint date header as overlay that sticks to viewport top during scroll (§49.13)
- [ ] Fade date header in/out over 200ms (§49.13)
- [ ] Auto-hide date header after 1000ms of no scrolling (§49.13)
- [ ] Render date badge with 13px semibold font, 12px horizontal / 3px top / 4px bottom padding (§49.16)
- [ ] Use msgServiceBg background and msgServiceFg text color (§49.16)
- [ ] Open calendar popup on date header click (§49.13)

### 49.17 Corner Buttons Stack Layout
- [ ] Position all corner buttons at 12px from right edge (§49.17)
- [ ] Stack buttons vertically with 4px gap, animated independently (§49.17)
- [ ] Calculate total stack height: 4x62 + 3x4 + 10 = 270px when all visible (§49.17)
- [ ] Smoothly slide buttons when middle button hides/shows (§49.17)

---

## 50. Streamer Mode & Read Toggles (AyuGram)

### 50.1-50.2 Streamer Mode
- [ ] Implement OS-level display affinity toggle for screen-capture exclusion (§50.2)
- [ ] Apply WDA_EXCLUDEFROMCAPTURE on Windows (§50.2)
- [ ] Apply NSWindowSharingNone on macOS (§50.2)
- [ ] Stub Linux implementation (no-op with tooltip explaining limitation) (§50.2)
- [ ] Apply affinity to all windows including newly opened ones (§50.2)
- [ ] Keep Streamer Mode non-persistent (reset to OFF on cold launch) (§50.2)

### 50.3 Activation Surfaces
- [ ] Show Streamer Mode toggle in drawer (gated by showStreamerToggleInDrawer, default false) (§50.3.1)
- [ ] Render drawer toggle: 48px row, 24x24 icon, "Streamer Mode" label, toggle switch (§50.3.1)
- [ ] Show Streamer Mode action in tray menu (gated by showStreamerToggleInTray, default false) (§50.3.2)
- [ ] Toggle tray label between "Enable Streamer Mode" / "Disable Streamer Mode" (§50.3.2)
- [ ] Show showStreamerToggleInDrawer / showStreamerToggleInTray settings on Ghost Mode page (§50.3.3)

### 50.4 Visual Indicators
- [ ] Reflect Streamer Mode state in drawer toggle switch position (§50.4)
- [ ] Reflect state in tray menu label text (§50.4)

### 50.5 Scope
- [ ] Make Streamer Mode global (process-wide, all windows, all accounts) (§50.5)
- [ ] Make showStreamerToggle settings global and persistent (§50.5)

### 50.7 Read Toggles
- [ ] Implement sendReadMessages toggle (block messages.readHistory when false) (§50.7)
- [ ] Implement sendReadStories toggle (block stories.readStories when false) (§50.7)
- [ ] Implement sendOnlinePackets toggle (block account.updateStatus online when false) (§50.7)
- [ ] Implement sendUploadProgress toggle (block messages.setTyping when false) (§50.7)
- [ ] Implement sendOfflinePacketAfterOnline toggle (auto-offline after going online) (§50.7)
- [ ] Implement markReadAfterAction toggle (local badge zeroing on reply/react/forward) (§50.7)
- [ ] Support locked variants for each toggle (prevent changes by master Ghost toggle) (§50.7)
- [ ] Implement "Read Message" chat-list context action with confirmation dialog (§50.7)
- [ ] Implement per-peer Read/Typing exclusions (Never Read / Always Read) (§50.7)

---

## 51. Ghost Mode (AyuGram)

### 51.1 Architecture
- [ ] Store Ghost settings per-account keyed by user ID (§51.1)
- [ ] Support global mode (key "0") applying same settings to all accounts (§51.1)
- [ ] Compute isGhostModeActive from all five core toggles + lock states (§51.1)

### 51.2 Core Toggles (5)
- [ ] Render 5 core toggles inside collapsible "Ghost Mode" section (§51.2.1)
- [ ] Implement "Don't Read Messages" toggle (blocks messages.readHistory) (§51.2.1)
- [ ] Implement "Don't Read Stories" toggle (blocks stories.readStories) (§51.2.1)
- [ ] Implement "Don't Send Online" toggle (blocks account.updateStatus online) (§51.2.1)
- [ ] Implement "Don't Send Typing" toggle (blocks messages.setTyping) (§51.2.1)
- [ ] Implement "Go Offline Automatically" toggle (auto-offline after online) (§51.2.1)
- [ ] Support Shift+click lock mechanism on each checkbox (§51.2.1)
- [ ] Render locked checkboxes at 40% opacity (§51.2.1)
- [ ] Prevent locking the last unlocked toggle (§51.2.1)
- [ ] Master toggle sets all unlocked sub-toggles to ghost values (§51.2.1)

### 51.2.2 Additional Toggles (3)
- [ ] Implement "Read on Interact" toggle (auto-mark read on send/react/vote) (§51.2.2)
- [ ] Implement "Schedule Messages" toggle (auto-schedule ~12s in future) (§51.2.2)
- [ ] Make "Read on Interact" and "Schedule Messages" mutually exclusive (§51.2.2)
- [ ] Implement "Send without Sound" toggle (silent sends by default) (§51.2.2)
- [ ] Flip send menu label to "Send with Sound" when sendWithoutSound active (§51.2.2)

### 51.3 Per-Account Settings & Account Picker
- [ ] Show account picker LinkButton next to "Ghost essentials" title (when >1 account) (§51.3)
- [ ] Render small down-arrow icon next to picker button in windowActiveTextFg (§51.3)
- [ ] Open PopupMenu with "Global Settings" + per-account items on picker click (§51.3)
- [ ] Render "Global Settings" item with purple gradient circle avatar "GS" (§51.3)
- [ ] Render account items with userpic and name (§51.3)
- [ ] Show toast on scope switch ("Switched to same/individual settings...") (§51.3)
- [ ] Auto-migrate to global mode when only 1 account exists (§51.3)

### 51.4 Settings Screen Layout
- [ ] Render Ghost settings at Settings > AyuGram > AyuGram (first category) (§51.4)
- [ ] Layout: Ghost essentials (collapsible), Read on Interact, Schedule Messages, Send without Sound (§51.4)
- [ ] Layout: Spy essentials (Save Deleted, Save History, Save for Bots) (§51.4)
- [ ] Layout: Other (Local Premium, Disable Ads) (§51.4)
- [ ] Show divider text descriptions below each toggle (§51.4)

### 51.5 Drawer Integration
- [ ] Show Ghost Mode toggle in drawer (gated by showGhostToggleInDrawer, default true) (§51.5)
- [ ] Render ghost icon (ayuGhostIcon) with toggle switch bound to ghostModeActiveValue (§51.5)
- [ ] Support LRead and SRead toggle buttons in drawer (§51.5)

### 51.6 System Tray Integration
- [ ] Show Ghost Mode toggle in tray menu (gated by showGhostToggleInTray, default true) (§51.6)
- [ ] Toggle tray label between "Enable Ghost Mode" / "Disable Ghost Mode" (§51.6)
- [ ] Support Windows Jump List "Enter with Ghost" item with ghost icon (§51.6)

### 51.7 Command-Line Flag
- [ ] Support -ghost CLI flag to enable Ghost Mode at startup (§51.7)

### 51.8 Visual Indicators
- [ ] Update drawer toggle switch state in real-time (§51.8)
- [ ] Update tray menu label dynamically (§51.8)
- [ ] Show toast "Ghost Mode turned on/off" on toggle (§51.8)
- [ ] Reflect master toggle state in settings collapsible (§51.8)

### 51.10 API Interception
- [ ] Intercept messages.readHistory when sendReadMessages=false (§51.10)
- [ ] Intercept messages.readDiscussion when sendReadMessages=false (§51.10)
- [ ] Intercept messages.getMessagesViews increment flag (§51.10)
- [ ] Intercept stories.readStories and incrementStoryViews (§51.10)
- [ ] Intercept account.updateStatus online (§51.10)
- [ ] Trigger auto-offline via AyuWorker polling every 3 seconds (§51.10)
- [ ] Intercept messages.setTyping (§51.10)
- [ ] Apply ghost scheduling to outgoing messages via applyGhostScheduling (§51.10)
- [ ] Auto-read on react/poll-vote when markReadAfterAction=true (§51.10)

---

## 52. Anti-Recall & Message History (AyuGram)

### 52.1 Settings & Toggles
- [ ] Implement "Save deleted messages" toggle (default true) (§52.1)
- [ ] Implement "Save messages history" toggle (default true) (§52.1)
- [ ] Implement "Save for bots" toggle (default false) (§52.1)
- [ ] Implement "Semi-transparent deleted" toggle (default false) (§52.1)
- [ ] Support customizable deletedMark (default broom emoji) via EditMarkBox (§52.1)
- [ ] Support customizable editedMark via EditMarkBox (§52.1)
- [ ] Implement "Replace marks with icons" toggle (default true) (§52.1)

### 52.2 Anti-Recall Behavior
- [ ] Intercept UpdateDeleteMessages and call processMessageDelete (§52.2)
- [ ] Check isMessageSavable (respecting saveDeletedMessages and saveForBots settings) (§52.2)
- [ ] Call item.setDeleted() instead of item.destroy() for savable messages (§52.2)
- [ ] Save deleted message to SQLite via AyuMessages.addDeletedMessage (§52.2)
- [ ] Clean up unread mentions and reactions on deletion (§52.2)
- [ ] Append deletedMark to service message text via setAyuHint (§52.2)

### 52.3 Visual Styling of Deleted Messages
- [ ] Mode 1 (text marks): Prepend deletedMark to bottom-info date text (§52.3)
- [ ] Support custom deletedMark text via EditMarkBox with reset-to-default (§52.10)
- [ ] Mode 2 (icon marks): Render trash bin icon for deleted, pencil for edited, flame for burnt (§52.3)
- [ ] Render icons before timestamp in order: burnt, deleted, edited, time (§52.3)
- [ ] Mode 3 (semi-transparent): Animate opacity 1.0 -> 0.7 over 500ms with easeOutCubic (§52.3)
- [ ] Apply 70% opacity to entire message bubble (text, media, reactions, timestamp) (§52.3)
- [ ] Handle grouped messages: full group at 0.7 if all deleted, else individual (§52.3)
- [ ] Always render deleted messages at 1.0 opacity in AdminLog context (§52.3)
- [ ] Transfer animation state to new Element on view refresh (§52.3)

### 52.4 Edit History
- [ ] Intercept UpdateEditMessage before applying edit (§52.4)
- [ ] Save pre-edit text to SQLite when saveMessagesHistory enabled (§52.4)
- [ ] Skip saves for local messages, self-authored, hide-edits, and identical text (§52.4)
- [ ] Show "Edits history" context menu item with pencil icon (§52.4)
- [ ] Only show "Edits history" when message has HistoryMessageEdited and revisions exist (§52.4)
- [ ] Render edit history as full-width section panel replacing chat view (§52.4)
- [ ] Show BackButton with peer name + userpic in FixedBar (§52.4)
- [ ] Render each revision as standard message bubble with sender, date, formatting (§52.4)
- [ ] Order revisions newest-first (oldest version at bottom) (§52.4)
- [ ] Paginate: first page 20 messages, subsequent pages 30 (§52.4)

### 52.5 Deleted Messages Viewer
- [ ] Show "View deleted messages" in chat-list right-click menu (§52.5)
- [ ] Open MessageHistory section with item=nullptr for deleted messages (§52.5)
- [ ] Support search with debounced AutoSearchTimeout and SQL LIKE matching (§52.5)
- [ ] Filter by topicId for forum chats (§52.5)
- [ ] Support Ctrl+F keyboard shortcut for search (§52.5)
- [ ] Show peer name and userpic in FixedBar back button (§52.5)

### 52.6 Database Storage
- [ ] Store deleted/edited messages in ayudata.db SQLite database (§52.6)
- [ ] Support DeletedMessage, EditedMessage, DeletedDialog, SchemaVersion tables (§52.6)
- [ ] Create indexes on (userId, dialogId, topicId, messageId) for deleted messages (§52.6)
- [ ] Create indexes on (userId, dialogId, messageId) for edited messages (§52.6)
- [ ] Skip saving messages with empty text (§52.6)
- [ ] Handle database corruption by renaming with timestamp and recreating (§52.6)

### 52.7 Context Menu Integration
- [ ] Add "Edits history" menu item with pencil icon when revisions exist (§52.7)
- [ ] Add "Hide message" menu item with clear icon (§52.7)
- [ ] Add "Read until here" menu item when ghost mode blocks read receipts (§52.7)
- [ ] Add "Burn media" menu item for TTL media not yet read (§52.7)
- [ ] Add "View deleted messages" to chat-list context menu (§52.7)
- [ ] Add "Jump to beginning" to chat-list context menu with custom icon (§52.7)

### 52.10 EditMarkBox
- [ ] Render dialog at 320px width with title, input field, Save and Reset buttons (§52.10)
- [ ] Reset input to default value on left button click (§52.10)

---

## 53. Forward Enhancements (AyuGram)

### 53.1 Intelligent Forward
- [ ] Detect restricted messages via isFullAyuForwardNeeded (peer-level) (§53.1)
- [ ] Detect restricted messages via isAyuForwardNeeded (message-level: deleted, AyuNoForwards, TTL) (§53.1)
- [ ] Split selection into chunks: native forward for unrestricted, download-resend for restricted (§53.1)
- [ ] Execute chunks sequentially (§53.1)
- [ ] Run entire operation on background thread (§53.1)

### 53.2 Forward Progress Tracking
- [ ] Show progress bar replacing compose area while AyuForward is active (§53.2)
- [ ] Display state text: "Forwarding messages", "Loading media", "Done" (§53.2)
- [ ] Display detail text: "sent {n} of {total}" + "chunk {n} of {total}" (§53.2)
- [ ] Render title label with frozenRestrictionTitle style (§53.2)
- [ ] Render subtitle label with frozenRestrictionSubtitle style (§53.2)
- [ ] Cancel forward operation on progress bar click (§53.2)
- [ ] Hide labels when width < 2 * defaultDialogRow.photoSize (§53.2)
- [ ] Restore normal compose area when forward finishes (§53.2)

### 53.3 Repeat Message
- [ ] Show "Repeat Message" in context menu with repeat icon (§53.3)
- [ ] Support three-state visibility: Hidden, Visible, VisibleWithModifier (§53.3)
- [ ] No-Quote Mode (Shift held): resend message content as new message without forward header (§53.3)
- [ ] Extract text with entities and send via sendMessage for text-only (§53.3)
- [ ] Reuse existing photo/document file references for media (§53.3)
- [ ] Preserve reply-to when Shift held (§53.3)
- [ ] Standard Forward Mode (no Shift): forward with attribution, route through AyuForward if restricted (§53.3)
- [ ] Apply ghost scheduling before sending (§53.3)

### 53.4 Restriction Override
- [ ] Show "Plain forwarding is not allowed." non-interactive label in context menu for restricted peers (§53.4)
- [ ] Render label with copyright icon for channels/groups (§53.4)
- [ ] Intercept ShareBox submit for restricted content and route through AyuForward (§53.4)
- [ ] Intercept ApiWrap.forwardMessages for restricted content (§53.4)

### 53.5 Download-and-Resend Pipeline
- [ ] Scan items for downloadable media (exclude webpages, polls, games, etc.) (§53.5)
- [ ] Generate new random group IDs for album preservation (§53.5)
- [ ] Download documents via data.save() with 15-minute timeout (§53.5)
- [ ] Download photos via wanted(PhotoSize.Large) with 5-minute timeout (§53.5)
- [ ] Send text-only messages via sendMessageSync (§53.5)
- [ ] Send stickers via SendExistingDocument (reuse file reference) (§53.5)
- [ ] Send voice/video messages via FileLoadTask (§53.5)
- [ ] Send photos/videos/GIFs/documents via sendFiles with PreparedList (§53.5)
- [ ] Batch grouped media with new groupId (§53.5)
- [ ] Skip incomplete downloads silently (§53.5)
- [ ] Wait for server acknowledgment per message with 5-minute timeout (§53.5)

### 53.6 AyuNoForwards Flag System
- [ ] Track message-level AyuNoForwards flag (bit 63) (§53.6)
- [ ] Track channel-level AyuNoForwards flag (§53.6)
- [ ] Track user-level NoForwardsMyEnabled / NoForwardsPeerEnabled flags (§53.6)
- [ ] Check peer-level isAyuNoForwards() polymorphically (§53.6)

### 53.8 Repeat Message UX
- [ ] No tooltip or hint text on Repeat Message menu item (§53.8)
- [ ] Shift-for-no-quote behavior is undiscoverable (silent check) (§53.8)

### 53.10 Error States
- [ ] Transition progress bar to Finished on all failures (no error state) (§53.10)
- [ ] Skip failed downloads silently (§53.10)
- [ ] Log file open failures but continue (§53.10)

---

## 54. AyuGram UI Customization

### 54.1 Avatar Corners
- [ ] Render "Avatar Corners" subsection with badge showing current value (§54.1)
- [ ] Show live preview dialog row with AyuGramReleases channel avatar (§54.1)
- [ ] Implement radius slider with 24 stops (0=square, 23=circle) (§54.1)
- [ ] Compute radius via linear interpolation: corners/23 * size/2 (§54.1)
- [ ] Update preview live on slider drag (§54.1)
- [ ] Show restart prompt on slider release (§54.1)
- [ ] Implement "Single Corner Radius" toggle for forum avatars (default false) (§54.1)
- [ ] Recalculate online badge position based on avatar shape (§54.1)
- [ ] Apply avatar shape to animated userpics (video avatars) (§54.1)

### 54.2 Material Switches (MD3)
- [ ] Implement "MD3 Switch Style" toggle (default true) (§54.2)
- [ ] Render MD3 toggle: 32x18px track, 14px diameter, -2px shift, easeOutCubic easing (§54.2)
- [ ] Render iOS toggle: 36x20px track, 16px diameter, 1px shift, linear easing (§54.2)
- [ ] Animate MD3 growing thumb effect (smaller when untoggled, full size when toggled) (§54.2)

### 54.3 Wide Messages Multiplier
- [ ] Implement slider with 61 stops (1.00 to 4.00 in 0.05 increments) (§54.3)
- [ ] Display current multiplier as "X.XX" label (§54.3)
- [ ] Scale message bubble max width by multiplier (§54.3)
- [ ] Show restart prompt on slider release (§54.3)

### 54.4 Message Bubble Radius
- [ ] Show live MessagePreview widget with two fake messages reacting to settings (§54.4)
- [ ] Implement radius slider with 17 stops (0=square, 16=max roundness) (§54.4)
- [ ] Map slider value to BubbleRadiusLarge and BubbleRadiusSmall via linear interpolation (§54.4)
- [ ] Update preview live via SetBubbleRadiusOverride (§54.4)
- [ ] Show restart prompt on slider release (§54.4)

### 54.5 Message Tail Removal
- [ ] Implement "Remove Message Tail" toggle (default false) (§54.5)
- [ ] Convert Corner::Tail to Corner::Large when enabled (§54.5)
- [ ] Update reactively (no restart required) (§54.5)

### 54.6 Quote & Reply Styling
- [ ] Implement "Disable Colorful Replies" toggle (default false) (§54.6)
- [ ] Set quote background to transparent when enabled (§54.6)
- [ ] Skip loading backgroundEmojiData for replies and webpages when enabled (§54.6)
- [ ] Keep left accent bar and outline colors visible (§54.6)

### 54.7 Context Menu Customization
- [ ] Implement three-state visibility control for 7 AyuGram context menu items (§54.7)
- [ ] Support Hidden, Shown, Extended Menu (Ctrl/Shift held) visibility states (§54.7)
- [ ] Show "choose button" opening single-choice dialog for each item (§54.7)
- [ ] Implement configurable items: Reactions Panel, Views Panel, Hide Message, User Messages, Message Details, Repeat Message, Add Filter (§54.7)
- [ ] Show extended menu description text about Ctrl/Shift modifier (§54.7)
- [ ] Implement fixed context menu actions: View Deleted, Jump to Beginning, Open Channel, Delete Own Messages, Edit History, Read Until, Burn, Create Filter (§54.7)

### 54.8 Drawer/Sidebar Customization
- [ ] Implement 12 boolean toggles for drawer items (Profile, Bots, Groups, Channel, Contacts, Calls, Saved, LRead, SRead, Night, Ghost, Streamer) (§54.8)
- [ ] Gate "Bots" toggle visibility on account having attach-menu bots with inMainMenu flag (§54.8)
- [ ] Gate "Streamer Mode Toggle" on Windows/macOS only (§54.8)
- [ ] Implement 2 tray item toggles (Ghost Mode, Streamer Mode) (§54.8)

### 54.9 Message Field Button Toggles
- [ ] Implement 7 boolean toggles for compose area buttons (Attach, Commands, TTL, Emoji, Voice, Gift, AI Editor) (§54.9)
- [ ] Implement 2 boolean toggles for popup panels (Attach popup, Emoji popup) (§54.9)
- [ ] Keep functionality accessible via shortcuts even when button hidden (§54.9)

### 54.9a AI Editor (ComposeAiBox)
- [ ] Show ComposeAiBox modal with Translate/Style/Fix tabs on AI button click (§54.9a)
- [ ] Render preview card with original text (collapsible) + result text + copy button (§54.9a)
- [ ] Show diff display in Fix mode: green underline inserts, strikethrough deletes (§54.9a)
- [ ] Render 24x24px composite AI button icon (letters + stars) (§54.9a)

### 54.10 Additional Appearance Settings
- [ ] Implement "Disable Custom Backgrounds" toggle (default true) (§54.10)
- [ ] Implement "Hide Premium Statuses" toggle (default false) (§54.10)
- [ ] Implement "Monospace Font" selector opening FontSelectorBox (§54.10)
- [ ] Implement "Hide Notification Counters" toggle (default false) (§54.10)
- [ ] Implement "Hide All Chats Tab" toggle (default false) (§54.10)
- [ ] Implement "Hide Notification Badge" toggle (Windows only, default false) (§54.10)
- [ ] Implement App Icon picker with 12 icon themes in 4-column grid (§54.10)
- [ ] Render icon picker: 64px icons, 4px padding, 12px selection rounding, 200ms selection animation (§54.10a)

### 54.11 Additional Chat Settings
- [ ] Implement "Show Only Added Emojis/Stickers" toggle (default false) (§54.11)
- [ ] Implement "Hide Reactions" collapsible toggle with 3 nested checkboxes (channels/groups/private) (§54.11)
- [ ] Implement "Recent Stickers Count" slider (0-200, default 100) (§54.11)
- [ ] Implement "Channel Bottom Button" three-choice picker (Hidden/MuteUnmute/DiscussWithFallback) (§54.11)
- [ ] Implement "Quick Admin Shortcuts" toggle (default true) (§54.11)
- [ ] Implement "Message Shot" toggle (default true) (§54.11)
- [ ] Implement "Hide Side Share Button" toggle (default false) (§54.11)
- [ ] Implement "Replace Marks with Icons" toggle (default true) (§54.11)
- [ ] Reveal custom mark text sub-settings when icon mode disabled (§54.11)
- [ ] Implement "Translucent Deleted Messages" toggle with beta badge (default false) (§54.11)

### 54.12 Settings Page Structure
- [ ] Render AyuGram settings hierarchy: Appearance, Chats, General, Filters, Other (§54.12)
- [ ] Use AyuSectionBuilder helpers: addSettingToggle, addSlider, addChooseButton, addCollapsibleToggle, addBetaBadge, addSectionDivider (§54.12)

### 54.14 General Settings (AyuGeneral)
- [ ] Implement Translation Provider dropdown (Telegram/Google/Yandex/Native) with beta badge (§54.14)
- [ ] Implement "Disable Stories" toggle (default false) (§54.14)
- [ ] Implement "Disable Open Link Warning" toggle (default false) (§54.14)
- [ ] Implement "Disable Similar Channels" collapsible with 2 nested checkboxes (§54.14)
- [ ] Implement "Disable Notify Delay" toggle (default false) (§54.14)
- [ ] Implement "Filter Zalgo" toggle with beta badge and restart prompt (default true) (§54.14)
- [ ] Implement "Improve Link Previews" toggle (default false) (§54.14)
- [ ] Implement "Show Message Seconds" toggle (default false) (§54.14)
- [ ] Implement "Show Peer ID" dropdown (Hide/Telegram API/Bot API, default Bot API) (§54.14)
- [ ] Implement "Spoof Client as Android" toggle (default false) (§54.14)
- [ ] Implement "Bigger Window" collapsible with Height and Width checkboxes (§54.14)
- [ ] Implement send confirmation toggles for Stickers, GIFs, and Voice Messages (§54.14)

### 54.15 Other Settings (AyuOther)
- [ ] Render donation buttons with custom SVG icons (Boosty, TON, Bitcoin, Ethereum, Solana, Tron) (§54.15)
- [ ] Open DonateQrBox with wallet QR code for crypto buttons (§54.15)
- [ ] Render icon backgrounds: #EEEEEE in night mode, #242B2C in light mode, size/4 radius (§54.15)
- [ ] Implement "Crash Reporting" toggle (default true, only when auto-update enabled) (§54.15)
- [ ] Implement "Register URL Scheme" action with "Done" toast (§54.15)
- [ ] Implement "Reset Settings" action with confirmation dialog (§54.15)

### 54.16 Filters Settings (AyuFilters)
- [ ] Render top-bar menu: Select Chat, Import, Export, Clear All (§54.16)
- [ ] Implement "Enable Regex Filters" master toggle (default false) (§54.16)
- [ ] Implement "Enable Shared in Chats" toggle (default false) (§54.16)
- [ ] Implement "Hide from Blocked" toggle (default false) (§54.16)
- [ ] Show "Shared Filters" navigation button (§54.16)
- [ ] Show "Shadow Ban" navigation button (§54.16)
- [ ] Show per-dialog filters peer list when overrides exist (§54.16)

#### Filter Engine
- [ ] Use ICU/PCRE-compatible regex engine with MULTILINE always-on (§54.16)
- [ ] Build match input blob: message text + URL entities + button labels + type tag (§54.16)
- [ ] Support reversed flag (invert match) (§54.16)
- [ ] Support caseInsensitive per-rule flag (§54.16)
- [ ] Evaluate per-dialog rules first, then shared rules (§54.16)
- [ ] Check per-dialog exclusions before applying shared rules (§54.16)
- [ ] Never filter own outgoing messages (§54.16)
- [ ] Gate regex in DMs/groups behind filtersEnabledInChats (broadcast always enabled) (§54.16)
- [ ] Shadow-ban and hideFromBlocked bypass filtersEnabledInChats gate (§54.16)
- [ ] Hide filtered messages by making them isEmpty() (zero-height render) (§54.16)
- [ ] Skip filtered messages in selection, notifications, media tabs, reply previews, reactions, who-viewed, typing indicators (§54.16)

#### AyuFiltersList Screen
- [ ] Render three modes: Shared filters, Shadow Ban, Per-dialog (§54.16)
- [ ] Show title: "Shadow ban" / "Shared filters" / peer name (truncated 18 chars) (§54.16)
- [ ] Show "Filters" subsection with filter rows (§54.16)
- [ ] Show "Excluded" subsection with exclusion rows when present (§54.16)
- [ ] Show empty state divider text when no filters (§54.16)
- [ ] Render filter rows with muted label color when disabled (§54.16)
- [ ] Show popup menu on row click: Edit, Enable/Disable, Delete (§54.16)
- [ ] Show single Delete action for exclusion rows (§54.16)
- [ ] Support "pick shared pattern to exclude" flow for per-dialog context (§54.16)

#### RegexEditBox
- [ ] Render edit/add filter dialog with title, regex input, error label, 3 checkboxes (§54.16)
- [ ] Auto-focus regex input on open (§54.16)
- [ ] Validate regex on save with ICU-style error message (offset + context) (§54.16)
- [ ] Show inline error label with slide animation (§54.16)
- [ ] Support Enable, Case-insensitive, Reversed checkboxes (§54.16)
- [ ] Generate UUID v4 for new filter IDs (§54.16)
- [ ] Show toast with option to promote per-dialog filter to shared scope (§54.16)
- [ ] Save button + Cancel button + Enter-to-submit (§54.16)

#### Shadow Ban
- [ ] Store shadow-banned IDs as global set (not per-account) (§54.16)
- [ ] Show "Shadow ban" / "Unshadow ban" in chat-list right-click menu (§54.16)
- [ ] Show ghost icon when not banned, eye/show icon when banned (§54.16)
- [ ] Gate on: peer is User or Broadcast, filtersEnabled, not self (§54.16)
- [ ] Toggle instantly on click with no confirmation dialog (§54.16)
- [ ] Silently filter shadow-banned messages locally (server never notified) (§54.16)
- [ ] Filter shadow-banned peers from: who-reacted, reaction summaries, typing indicators, replier strip (§54.16)
- [ ] Show shadow ban list page with delete-only popup on row click (§54.16)

#### ImportFiltersBox
- [ ] Render import/export modal with Clipboard/URL radio buttons (§54.16)
- [ ] Show URL input field for import-URL mode with clipboard auto-prefill (§54.16)
- [ ] Import from clipboard: parse JSON directly (§54.16)
- [ ] Import from URL: HTTP GET and parse response (§54.16)
- [ ] Export to clipboard: serialize filters as JSON and copy (§54.16)
- [ ] Export to URL: POST to dpaste.com and copy returned URL (§54.16)
- [ ] Support JSON v2 format with filters array and exclusions array (§54.16)
- [ ] Show appropriate toast on success/failure (§54.16)

### 54.17 AyuMain Landing Page
- [ ] Render app logo widget (centered, configurable icon from 12 themes) (§54.17)
- [ ] Render version title "AyuGram Desktop v{version}" in boxTitle style (§54.17)
- [ ] Render tagline description in centeredBoxLabel style (§54.17)
- [ ] Show "Categories" subsection with 6 navigation buttons (AyuGram, Filters, General, Appearance, Chats, Other) (§54.17)
- [ ] Render each button with correct icon and right-arrow chevron (§54.17)
- [ ] Show "Links" subsection with 4 link buttons (Channel, Chats, Translate, Documentation) (§54.17)
- [ ] Open Telegram peers in-app, external URLs in browser (§54.17)

### 54.14b Peer ID Display
- [ ] Format Telegram API IDs: always positive bare ID (§54.14b)
- [ ] Format Bot API IDs: positive for users, -bare for groups, -(bare+1000000000000) for channels (§54.14b)
- [ ] Display peer ID in profile info section reactively (§54.14b)

## §55 Channel & Group Statistics

### §55.1 Opening Statistics

- [ ] Menu item "Statistics" in channel/group info three-dot menu with `menuIconStats` icon (§55.1)
- [ ] Gate statistics menu item behind `CanGetStatistics` flag check (§55.1)
- [ ] "Boosts" menu item below statistics with `menuIconBoosts` icon, gated on CanGetStatistics/creator/can-post-stories (§55.1)
- [ ] "Channel Earning" menu item with `menuIconEarn` icon, gated on CanViewRevenue/CanViewCreditsRevenue (§55.1)
- [ ] Navigate to Info section with `Section::Type::Statistics` on menu tap (§55.1)
- [ ] Page title "Statistics" for channel/group stats (§55.1)
- [ ] Page title "Message Statistics" for individual post stats (§55.1)
- [ ] Page title "Story Statistics" for story stats (§55.1)
- [ ] Message statistics sub-page navigation from recent messages list tap (§55.1)

### §55.2 Loading State

- [ ] Centered loading indicator with looping Lottie `stats` animation at `normalBoxLottieSize` (§55.2)
- [ ] "Loading Statistics..." title text below Lottie animation (§55.2)
- [ ] Descriptive subtitle below title, centered, max width 256px, `tryMakeSimilarLines` enabled (§55.2)
- [ ] Loading indicator wrapped in SlideWrap that toggles off when data arrives (§55.2)
- [ ] Lottie animation starts looping only after `showFinished` event (transition completes) (§55.2)
- [ ] Padding around loading indicator using `settingsBlockedListIconPadding` (§55.2)

### §55.3 Channel Statistics — Overview

- [ ] "Overview" section header with date range subtitle (§55.3)
- [ ] Header uses `statisticsChartHeaderPadding` and `statisticsLayerMargins` (§55.3)
- [ ] 2x2 overview grid: top-left Followers, top-right Enabled Notifications %, bottom-left Views Per Post, bottom-right Views Per Story (§55.3)
- [ ] Each card: primary value in 14px `statisticsOverviewValue` font with `FormatCountToShort` formatting (§55.3)
- [ ] Each card: change indicator in 11px `statisticsOverviewSecondValue` showing delta and growth rate (§55.3)
- [ ] Change indicator: green color for positive growth (`settingsIconBg2`), red for negative (`menuIconAttentionColor`) (§55.3)
- [ ] Change indicator: +/- prefix with Unicode minus U+2212 for negative values (§55.3)
- [ ] Change indicator padding: 5px left, 3px top (`statisticsOverviewSecondValuePadding`) (§55.3)
- [ ] Each card: label below value in 11px `statisticsOverviewSubtext`, `windowSubTextFg` color, min width 152px (§55.3)
- [ ] Grid vertical spacing `statisticsOverviewMidSkip` (50px) between rows (§55.3)
- [ ] Right column offset `statisticsOverviewRightSkip` (14px) from halfway point (§55.3)
- [ ] Outer margins `statisticsLayerOverviewMargins` (17px top, 9px bottom) (§55.3)
- [ ] Second 2x2 overview grid for story metrics when story data available (§55.3)
- [ ] Story grid: Shares Per Post, Shares Per Story, Reactions Per Post/Story layout logic (§55.3)

### §55.3 Channel Statistics — Charts

- [ ] Charts separated by dividers with `statisticsChartEntryPadding` (13px top, 2px bottom) (§55.3)
- [ ] Chart widget horizontal margins `statisticsLayerMargins` (20px) (§55.3)
- [ ] Chart 1: "Followers" Linear chart — member count over time (§55.3)
- [ ] Chart 2: "New Followers" Linear chart — daily joins/leaves (§55.3)
- [ ] Chart 3: "Notifications" Linear chart — muted/unmuted ratio (§55.3)
- [ ] Chart 4: "Views By Hours" Linear chart — views by hour of day (§55.3)
- [ ] Chart 5: "Views By Source" StackBar chart — stacked bars by source (§55.3)
- [ ] Chart 6: "New Followers By Source" StackBar chart — join sources (§55.3)
- [ ] Chart 7: "Languages" StackLinear chart — subscriber languages (§55.3)
- [ ] Chart 8: "Interactions" DoubleLinear chart — views + shares (§55.3)
- [ ] Chart 9: "IV Interactions" DoubleLinear chart — Instant View views + shares (§55.3)
- [ ] Chart 10: "Reactions By Emotion" Bar chart (§55.3)
- [ ] Chart 11: "Story Interactions" DoubleLinear chart — story views + shares (§55.3)
- [ ] Chart 12: "Story Reactions By Emotion" Bar chart (§55.3)
- [ ] Omit charts with empty data / no zoom token (§55.3)
- [ ] Async-load charts with only zoom token via SlideWrap reveal (§55.3)

### §55.3 Channel Statistics — Recent Messages

- [ ] "Recent Messages" section header with date range subtitle (§55.3)
- [ ] Message rows as SettingsButton widgets, 56px height, `statisticsRecentPostButton` style (§55.3)
- [ ] Row left: thumbnail square with `roundRadiusLarge` corners, `contactsPhotoSize` 42px (§55.3)
- [ ] Row left: photo/video thumbnail scaled to fit; channel userpic fallback when no media (§55.3)
- [ ] Row left: story thumbnails with gradient outline ring indicator (§55.3)
- [ ] Row left: spoiler media blurred (§55.3)
- [ ] Row center top: message text preview single line elided, `boxTextFg` color (§55.3)
- [ ] Row center bottom: date/time in `windowSubTextFg` color (§55.3)
- [ ] Row right top: view count formatted as "12.3K views" (§55.3)
- [ ] Row right bottom: share count with `statisticsRecentPostShareIcon`, reaction count with `statisticsRecentPostReactionIcon`, 4px gap (§55.3)
- [ ] Pagination: first 10 messages, then "Show More" loads 30 at a time (§55.3)
- [ ] "Show More" button with up/down toggle arrow; hides when all loaded (§55.3)
- [ ] Right-click context menu on message row: "Show in Chat" with `menuIconShowInChat` (§55.3)
- [ ] Tap on message row navigates to individual message statistics page (§55.3)

### §55.4 Group (Supergroup) Statistics — Overview

- [ ] Group overview 2x2 grid: Members, Messages, Viewing Members, Posting Members (§55.4)
- [ ] Same card styling as channel overview (value, change indicator, label) (§55.4)

### §55.4 Group Statistics — Charts

- [ ] Group chart 1: "Members" Linear chart (§55.4)
- [ ] Group chart 2: "New Members" Linear chart (§55.4)
- [ ] Group chart 3: "New Members By Source" StackBar chart (§55.4)
- [ ] Group chart 4: "Members' Primary Language" StackLinear chart (§55.4)
- [ ] Group chart 5: "Messages" StackBar chart — message content types (§55.4)
- [ ] Group chart 6: "Actions" DoubleLinear chart — admin actions (§55.4)
- [ ] Group chart 7: "Top Hours" Linear chart — activity by hour (§55.4)
- [ ] Group chart 8: "Days Of Week" StackLinear chart (§55.4)

### §55.4 Group Statistics — Top Members Lists

- [ ] "Top Senders" section with PeerListContent rows showing avatar, name, "{N} messages, {M} characters" (§55.4)
- [ ] "Top Administrators" section with rows showing "{N} deletions, {M} bans, {K} restrictions" (§55.4)
- [ ] "Top Inviters" section with rows showing "{N} invitations" (§55.4)
- [ ] Each list hidden when data is empty (§55.4)
- [ ] Pagination: "Show More" button, 40 per page (§55.4)
- [ ] Tap on peer row opens user's profile info (§55.4)
- [ ] Section separators: AddSkip + AddDivider + AddSkip + AddSkip (§55.4)

### §55.5 Message Statistics — Preview

- [ ] Original message shown as MessagePreview at top (thumbnail, text preview, date) (§55.5)
- [ ] Story thumbnails with gradient story ring (§55.5)
- [ ] Context menu on message preview: "Show in Chat" (§55.5)
- [ ] Story previews are non-interactive (transparent for mouse events) (§55.5)

### §55.5 Message Statistics — Overview

- [ ] 2x2 grid: Views, Public Shares, Reactions, Private Shares (§55.5)
- [ ] Values displayed as raw numbers without growth indicators (§55.5)

### §55.5 Message Statistics — Charts

- [ ] "Interactions" DoubleLinear chart for this specific post (§55.5)
- [ ] "Reactions By Emotion" Bar chart breakdown (§55.5)

### §55.5 Message Statistics — Public Forwards

- [ ] "Public Shares" section header with total count (§55.5)
- [ ] PeerListContent rows for channels/groups that forwarded the post (§55.5)
- [ ] Each row shows forwarding channel avatar and name (§55.5)
- [ ] Tap navigates to the forward in the forwarding channel (§55.5)
- [ ] Story forward rows show gradient ring outline around avatar (§55.5)

### §55.6 Chart Widget Architecture

- [ ] Chart widget stacked layout: header + 200px chart area + 42px footer + optional filter buttons (§55.6)
- [ ] Chart header: title in semibold `boxFontSize`, subtitle in 11px showing date range (§55.6)
- [ ] Chart header height: 36px (`statisticsChartHeaderHeight`) (§55.6)
- [ ] Header subtitle updates as footer range selector moves (§55.6)
- [ ] Chart area: 200px tall interactive region (`statisticsChartHeight`) (§55.6)
- [ ] Chart area mouse: click/drag shows PointDetailsWidget tooltip at nearest X data point (§55.6)
- [ ] Tooltip horizontal positioning: left of selected point, flips right on overflow, pins to 0 on right overflow (§55.6)
- [ ] Tooltip fade in/out animation over 200ms (§55.6)
- [ ] Clicking same data point again hides tooltip (§55.6)
- [ ] Footer: 42px miniature full-chart with draggable range selector overlay (§55.6)
- [ ] Footer range: highlighted window with semi-transparent side handles (10px each, `statisticsChartFooterSideWidth`) (§55.6)
- [ ] Footer area outside selection dimmed with `statisticsChartInactive` overlay (§55.6)
- [ ] Footer side handles: vertical bars in `premiumButtonFg`, rounded corners 6px, with 10px arrow indicators (§55.6)
- [ ] Footer minimum range width: 5px between handles (`statisticsChartFooterBetweenSide`) (§55.6)
- [ ] Footer drag left handle: adjusts start of visible range (§55.6)
- [ ] Footer drag right handle: adjusts end of visible range (§55.6)
- [ ] Footer drag center area: pans range without changing zoom level (§55.6)
- [ ] Footer click outside range: animates range center to clicked position with sineInOut easing (§55.6)
- [ ] All footer range changes trigger immediate chart re-render with animated transitions (§55.6)

### §55.6 Point Details Tooltip

- [ ] Tooltip background: rounded rect with `boxRadius` corners, `boxBg` background (§55.6)
- [ ] Tooltip shadow: multi-layer painted shadow at 20%/40% opacity offsets (§55.6)
- [ ] Tooltip header: date stamp in semibold 12px; weekly format "1 Jan -- 7 Jan", daily "Mon, Jan 15" (§55.6)
- [ ] Tooltip value lines: one per data series, showing name (12px, `boxTextFg`), value (12px, line color), optional percentage (§55.6)
- [ ] Tooltip value line visibility animated (alpha 0-1) based on filter state (§55.6)
- [ ] Tooltip margins: 12px left/right, 8px top, 11px bottom; padding 6px; 4px between value lines (§55.6)
- [ ] Tooltip zoom arrow: chevron (>) in header when zoom enabled, 3px shift, 1.5px stroke, `windowSubTextFg` (§55.6)
- [ ] Tooltip click triggers zoom action when zoom enabled and values positive (§55.6)
- [ ] Tooltip ripple effect on click (zoom-enabled only) (§55.6)
- [ ] Tooltip currency support: native currency amount + USD conversion for earn/revenue charts (§55.6)

### §55.6 Chart Rendering

- [ ] Horizontal axis: date labels in 10px font, centered, 15px caption height + 6px skip (§55.6)
- [ ] Horizontal axis labels fade in/out as zoom level changes to prevent overlap (§55.6)
- [ ] Edge labels fade when partially clipped (§55.6)
- [ ] Vertical axis: horizontal grid lines with value labels, 4px ruler caption skip (§55.6)
- [ ] Rulers semi-transparent at 0.06 opacity (`kRulerLineAlpha`) (§55.6)
- [ ] New ruler sets animate in with alpha crossfade when Y-axis range changes (§55.6)
- [ ] Line colors mapped from server color keys: BLUE, GREEN, RED, GOLDEN, LIGHTBLUE, LIGHTGREEN, ORANGE, INDIGO, PURPLE, CYAN (§55.6)
- [ ] Line width: 2px (`statisticsChartLineWidth`) (§55.6)
- [ ] Selected point: vertical line at X index with 5px radius dots on each data series (§55.6)
- [ ] Dots colored to match their respective data series line (§55.6)

### §55.7 Chart Types — Linear

- [ ] Linear chart: single continuous line per data series (§55.7)
- [ ] Linear chart: cached QImage rendering with cache key (x-indices, percentage limits, height limits, rect) (§55.7)
- [ ] Linear chart: separate caches for main area and footer (§55.7)

### §55.7 Chart Types — DoubleLinear

- [ ] DoubleLinear chart: two lines with independent Y-axis scaling via `DoubleLineRatios` (§55.7)
- [ ] Each line auto-scaled to use full chart height independently (§55.7)

### §55.7 Chart Types — Bar

- [ ] Bar chart: non-stacked vertical bars, one per data point (§55.7)
- [ ] Bar chart: `SegmentTree` for efficient range min/max queries (§55.7)
- [ ] Bar chart: selected bar highlighted, non-selected bars dimmed (§55.7)

### §55.7 Chart Types — StackBar

- [ ] StackBar chart: stacked vertical bars, multiple series per X position (§55.7)
- [ ] StackBar chart: Y-axis shows cumulative totals with per-series colors (§55.7)

### §55.7 Chart Types — StackLinear

- [ ] StackLinear chart: stacked filled areas, 100% height normalized (§55.7)
- [ ] StackLinear zoom: animates from stacked area to pie chart on tooltip click (§55.7)
- [ ] StackLinear zoom animation: `easeOutCirc` easing, 400ms duration (§55.7)
- [ ] Pie chart: percentage breakdown at specific time point (§55.7)
- [ ] Pie chart: footer range selector zooms to selected range (§55.7)
- [ ] Pie chart: header subtitle updates to specific date (§55.7)
- [ ] "Zoom Out" button in header: 20px height, 11px semibold text, `statisticsHeaderButton` style (§55.7)
- [ ] Pie chart hover: hovered slice pops out 8px (`statisticsPieChartPartOffset`) (§55.7)
- [ ] Pie chart percentage labels on slices in 20px font (`statisticsPieChartFont`) (§55.7)
- [ ] Pie transition animation: line endpoints animate from stacked positions to radial positions (§55.7)
- [ ] `ChangingPiePartController`: smooth percentage value animation when panning in zoomed view (§55.7)
- [ ] "Zoom Out" click animates back to stacked area view (§55.7)

### §55.8 Chart Zoom — Server-Side

- [ ] Server-side zoom for Linear, Bar, DoubleLinear, StackBar charts with `zoomToken` (§55.8)
- [ ] Zoom triggered by tooltip click when `_zoomEnabled` is true (§55.8)
- [ ] `zoomRequests` event fires with X timestamp on zoom trigger (§55.8)
- [ ] API call `requestZoom(token, x)` fetches detailed chart data (§55.8)
- [ ] New `_zoomedChartWidget` overlaid on original with zoomed data (§55.8)
- [ ] Zoomed chart header: parent chart title + specific date range (§55.8)
- [ ] "Zoom Out" button in zoomed chart header (§55.8)
- [ ] Original chart hides with crossfade animation on zoom in (§55.8)
- [ ] "Zoom Out" destroys zoomed widget and reveals original (§55.8)

### §55.8 Chart Zoom — Local (StackLinear)

- [ ] StackLinear local zoom: no server call, client-side pie chart transform (§55.8)
- [ ] Footer range adjusts to zoomed portion (§55.8)
- [ ] Mouse tracking enabled for pie slice hover detection (§55.8)

### §55.9 Filter Buttons

- [ ] Filter buttons shown below footer for charts with >1 data series (§55.9)
- [ ] `ChartLinesFilterWidget`: horizontal flow of FlatCheckbox buttons (§55.9)
- [ ] Each button shows line name, colored with line's color (§55.9)
- [ ] Button padding: 4px horizontal, 3px top, 5px bottom (`statisticsChartFlatCheckboxMargins`) (§55.9)
- [ ] Check mark width: 3px, shrink width 4px (§55.9)
- [ ] Toggling button animates line visibility with alpha fade (§55.9)
- [ ] Y-axis and rulers recompute to fit only visible lines on toggle (§55.9)
- [ ] Some lines start hidden via `isHiddenOnStart` flag from server (§55.9)
- [ ] Long-press behavior on filter button (last-enabled toggle) (§55.9)
- [ ] Filter button container padding: 12px top, 8px bottom (§55.9)

### §55.10 Animation System

- [ ] X-axis animation: linear easing, 200ms (`kXExpandingDuration`) (§55.10)
- [ ] Y-axis animation: `easeInCubic` with adaptive speed based on range change magnitude (§55.10)
- [ ] Y-axis three speed tiers: 0.06, 0.06, 0.09 (`kDtHeightSpeed1/2/3`) (§55.10)
- [ ] Y-axis speed reduced by 1.2x when triggered by filter changes (§55.10)
- [ ] Y-axis instant snap when range change ratio exceeds 0.97 (§55.10)
- [ ] Height alpha crossfade: old rulers fade out, new rulers fade in (`_animationValueHeightAlpha`) (§55.10)
- [ ] Bottom line alpha: date labels crossfade at `easeInCubic`, 200ms (§55.10)
- [ ] FPS-adaptive animation: speed multiplied by (60/currentFPS); doubled below 30 FPS (§55.10)
- [ ] Separate footer height animation track for footer chart Y range (§55.10)

### §55.11 Data Structures

- [ ] `StatisticalValue` model: `.value`, `.previousValue`, `.growthRatePercentage` (§55.11)
- [ ] `StatisticalGraph` model: pre-loaded `.chart` data or deferred `.zoomToken` (§55.11)
- [ ] `StatisticalChart` model: timestamps, lines array, xPercentage, defaultZoomXIndex, weekFormat, hasPercentages, isFooterHidden, currencyRate, currency (§55.11)

## §56 Appendix A — Resolved Style Constants

### §56.1 Global Primitives

- [ ] Implement design token system for global primitives: `fsize` (13px), `boxFontSize` (14px), `normalFont`, `semiboldFont`, `linkFont` (§56.1)
- [ ] Implement duration tokens: `slideDuration` (240ms), `slideWrapDuration` (150ms), `fadeWrapDuration` (200ms), `universalDuration` (120ms) (§56.1)
- [ ] Support `boxTextFont` (14px) as a resolved font token (§56.1)
- [ ] Implement `lineWidth` (1px) and `defaultVerticalListSkip` (6px) spacing tokens (§56.1)

### §56.2 Layer / Box Chrome

- [ ] Implement box dimension tokens: `boxWidth` (320px), `boxWideWidth` (364px), `boxRadius` (8px) (§56.2)
- [ ] Implement `boxPadding` margins token: 24px left/right, 14px top, 8px bottom (§56.2)
- [ ] Implement `boxDuration` (200ms) and `boxRoundShadow` (8px radius soft drop) (§56.2)
- [ ] Implement `boxTitle` FlatLabel style: 24px max height, 14px semibold, `boxTitleFg` color (§56.2)
- [ ] Implement `defaultBox` button layout: 34px button height, margins, `boxBg` background (§56.2)

### §56.3 Main Window Layout

- [ ] Implement window constraint tokens: `windowMinWidth` (380px), `windowMinHeight` (480px) (§56.3)
- [ ] Implement column width tokens: `columnMinimalWidthLeft` (260px), `columnMaximalWidthLeft` (540px), `columnMinimalWidthMain` (380px) (§56.3)
- [ ] Implement `adaptiveChatWideWidth` (880px) breakpoint token (§56.3)
- [ ] Implement `topBarHeight` (54px) and all top bar icon button width tokens (search 40px, close 56px, menu 44px, etc.) (§56.3)
- [ ] Implement `topBarMenuPosition` point(-6px, 45px) for menu popup positioning (§56.3)
- [ ] Implement `topBarInfoButtonSize` (52x54), `topBarInfoButtonInnerSize` (42px) tokens (§56.3)
- [ ] Implement `topBarConnectingPosition` and `topBarConnectingSkip` (6px) tokens (§56.3)
- [ ] Implement chat switch tokens: margins (16px all), padding (12px all), size (72x104), userpic top (8px), name skip (6px), select line (3px) (§56.3)

### §56.4 Chat List / Left Panel

- [ ] Implement `dialogsRowHeight` (62px) and `forumDialogRow.height` (80px) tokens (§56.4)
- [ ] Implement `dialogsUnreadHeight` (19px), `dialogsUnreadPadding` (5px) tokens (§56.4)
- [ ] Implement `defaultDialogRow` compound token: height 62px, padding 10/8/10/8, photoSize 46px, nameLeft 68px, nameTop 10px, textLeft 68px, textTop 34px (§56.4)
- [ ] Implement `dialogsStoriesFull` compound token: height 77px, photo 42px, photoLeft 10px, photoTop 9px, lineTwice 4px (§56.4)
- [ ] Implement `dialogsFilterPadding` (7px each), `dialogsFilterSkip` (4px), `dialogsEmptyHeight` (160px) tokens (§56.4)
- [ ] Implement contacts tokens: `contactsPadding` (16/7/16/7), `contactsStatusFont` (13px), `contactsSortButton` (48x54) (§56.4)

### §56.5 Compose Row / Emoji / WhoRead

- [ ] Implement history reply tokens: `historyReplySkip` (53px), `historyReplyHeight` (49px) (§56.5)
- [ ] Implement `historyReplyNameFg` color reference to `windowActiveTextFg` (§56.5)
- [ ] Implement compose area icon tokens: reply cancel, schedule, edit save, link settings icons (§56.5)
- [ ] Implement `historyRecordVoiceFg`/`FgOver` referencing `historyComposeIconFg`/`FgOver` (§56.5)
- [ ] Implement `historySendIconFg` color: light #3fc1f7, dark #6ab3f3 (§56.5)
- [ ] Implement `historyToDown` TwoIconButton (52x54) and unread mentions/reactions variants (§56.5)
- [ ] Implement emoji/sticker size tokens: `emojiSetSize` (42x39), `emojiPanArea` (34x32), `stickersSize` (64x64) (§56.5)
- [ ] Implement `historySlowmodeCounterMargins` (0/0/10/0) (§56.5)

### §56.6 Contact / Peer List Boxes

- [ ] Implement `normalBoxLottieSize` (120x120) for loading animations (§56.6)
- [ ] Implement `boxLabel` FlatLabel style: 14px boxTextFont, boxTextFg color (§56.6)

### §56.7 Settings Panels

- [ ] Implement settings photo tokens: `settingsPhotoTop` (8px), `settingsPhotoBottom` (16px) (§56.7)
- [ ] Implement accent color tokens: `settingsAccentColorSize` (24px), line (3px), skip (4px) (§56.7)
- [ ] Implement `settingsBackgroundThumb` (76px) and `settingsThemePreviewSize` (80x92) tokens (§56.7)
- [ ] Implement local passcode tokens: button padding, input field width (256px), description min width (256px) (§56.7)
- [ ] Implement `settingsButtonLight` (lightButtonFg colors) and `settingsButtonNoIcon` (22px padding) variants (§56.7)
- [ ] Implement chat theme tokens: entry margin (16/10/16/8), skip (10px), preview size (80x108) (§56.7)

### §56.8 Profile / Shared Media Panes

- [ ] Implement `infoDesiredWidth` (392px) and layer min/max top tokens (20px/40px) (§56.8)
- [ ] Implement `infoMinimalLayerMargin` (48px), `infoProfileSkip` (7px) tokens (§56.8)
- [ ] Implement info members list position tokens: photo (18/6), name (79/11), status (79/31) (§56.8)
- [ ] Implement info top bar tokens: height (54px), scale (0.7), duration (150ms) (§56.8)
- [ ] Implement info top bar button widths: back (60px), close (48px), search (56px), menu (48px), forward (46px) (§56.8)
- [ ] Implement `infoTopBarTitle` FlatLabel: `windowBoldFg`, 20px max height (§56.8)
- [ ] Implement `infoMainButton` SettingsButton: lightButtonFg, semibold, padding 23/10/8/8 (§56.8)

### §56.9 Miscellaneous Tokens

- [ ] Implement `defaultInputField` (47px tall, 14px font, activeLineFg/inactiveLineFg borders) (§56.9)
- [ ] Implement `defaultRadio` (22px, 2px stroke, universalDuration toggle) (§56.9)
- [ ] Implement `defaultMultiSelect` (32px tall chips, 8px radius) for dialogs filter (§56.9)
- [ ] Implement `defaultRoundShadow` (8px blur, offset 0/2) (§56.9)
- [ ] Implement `popupMenuWithIcons` based on defaultPopupMenu with left icon column (§56.9)
- [ ] Implement menu icon set (20x20 glyphs): above, below, lock, timer, savedMessages, permissions, deleteAttention, appleWatch, touchID, winHello (§56.9)
- [ ] Menu icons colored with `menuIconFg`; deleteAttention uses `attentionButtonFg` red (§56.9)
- [ ] Implement radial loader tokens: 44px ring, 3px stroke, `radialBg` (semi-alpha black), `radialFg` (white) (§56.9)
- [ ] Implement `roundedBg`/`roundedFg` colors: light #f1f3f4/#000, dark #2b3036/#fff (§56.9)
- [ ] Implement photo crop tokens: fadeBg (#00000099), pointFg (#fff), animation 200ms, min size 120px, point size 20px (§56.9)

### §56.10–§56.13 Palette & Coverage

- [ ] Implement all 20+ most-referenced palette tokens with light/dark values (windowBg, windowFg, windowBgActive, etc.) (§56.10)
- [ ] Implement derived/compound value resolution: e.g. profile photo band = 8+88+16 = 112px (§56.11)
- [ ] Filter out false-positive tokens (st::All, st::Error, st::Widget, etc.) from style system (§56.12)
- [ ] Track ~25 unresolved tokens (theme editor, passcode, platform-specific) for future deeper grep pass (§56.13)

## §57 Appendix B — Dark Theme Color Palette

### §57 Theme Infrastructure

- [ ] Implement dual-theme color system supporting light (day-blue) and dark (night) palettes simultaneously (§57)
- [ ] Support alias resolution: tokens written as references (e.g. `lightButtonBg: windowBg`) resolve to concrete hex values (§57)
- [ ] Support 8-digit hex colors with alpha channel (e.g. `#00000054`) preserving alpha byte exactly (§57)
- [ ] Implement DPI scaling: all px values scale by user DPI factor (100%/125%/150%/200%/300%) at runtime (§57)
- [ ] Map Telegram hex values to Flutter `Color(0xAARRGGBB)` format correctly (§57)

### §57.1 Window / Chrome Colors

- [ ] Implement window chrome color tokens (windowBg, windowBgOver, windowBgRipple, windowBgActive, windowFg, windowFgOver, windowFgActive) with light/dark values (§57.1)
- [ ] Implement window text color tokens (windowSubTextFg, windowSubTextFgOver, windowBoldFg, windowBoldFgOver, windowActiveTextFg) (§57.1)
- [ ] Implement window shadow tokens (windowShadowFg, windowShadowFgFallback, shadowFg) with alpha values (§57.1)
- [ ] Implement title bar color tokens (titleBg, titleBgActive, titleShadow, titleFg, titleFgActive) (§57.1)
- [ ] Implement `layerBg` (#0000007F — 50% black overlay) for both themes (§57.1)

### §57.2 Dialogs / Chat List Colors

- [ ] Implement dialog background tokens (dialogsBg, dialogsBgOver, dialogsBgActive, dialogsRippleBg, dialogsRippleBgActive) (§57.2)
- [ ] Implement dialog name color tokens (dialogsNameFg, dialogsNameFgOver, dialogsNameFgActive) (§57.2)
- [ ] Implement dialog text color tokens (dialogsTextFg, dialogsTextFgOver, dialogsTextFgActive, dialogsTextFgService) (§57.2)
- [ ] Implement dialog date/draft tokens (dialogsDateFg, dialogsDraftFg) — draft is red #DD4B39 light / #FF525D dark (§57.2)
- [ ] Implement dialog unread badge tokens (dialogsUnreadBg, dialogsUnreadBgMuted, dialogsUnreadBgActive, dialogsUnreadBgMutedActive, dialogsUnreadFg, dialogsUnreadFgActive) (§57.2)
- [ ] Implement dialog online badge tokens (dialogsOnlineBadgeFg, dialogsOnlineBadgeFgActive) (§57.2)
- [ ] Implement dialog icon tokens (dialogsSentIconFg, dialogsSendingIconFg, dialogsVerifiedIconBg, dialogsVerifiedIconFg, dialogsArchiveFg) (§57.2)
- [ ] Implement dialog forward tokens (dialogsForwardBg, dialogsForwardFg) (§57.2)

### §57.3 Top Bar Colors

- [ ] Implement `topBarBg` token: light #FFFFFF, dark #17212B (§57.3)
- [ ] Handle missing top bar tokens: reuse `menuIconFg` for icons, `windowFg` for text, `windowSubTextFg` for subtitle (§57.3)

### §57.4 Message / Bubble Colors

- [ ] Implement incoming message tokens (msgInBg, msgInBgSelected, msgInShadow, msgInDateFg, msgInServiceFg, msgInReplyBarColor, msgInMonoFg, msgFileInBg) (§57.4)
- [ ] Implement outgoing message tokens (msgOutBg, msgOutBgSelected, msgOutShadow, msgOutDateFg, msgOutServiceFg, msgOutReplyBarColor, msgOutMonoFg, msgFileOutBg) (§57.4)
- [ ] Implement message service tokens (msgServiceBg, msgServiceBgSelected, msgServiceFg) with alpha channels (§57.4)
- [ ] Implement message overlay tokens (msgSelectOverlay, msgStickerOverlay) with alpha (§57.4)
- [ ] Implement message date image background tokens (msgDateImgBg, msgDateImgBgOver, msgDateImgBgSelected) (§57.4)
- [ ] Dark theme: msgOutShadow/msgInShadow use alpha 00 — shadows intentionally suppressed (§57.4)

### §57.5 History / Chat Area Colors

- [ ] Implement compose area tokens (historyComposeAreaBg, historyComposeAreaFg, historyComposeIconFg, historyComposeIconFgOver) (§57.5)
- [ ] Implement compose button tokens (historyComposeButtonBg, historyComposeButtonBgOver, historyComposeButtonBgRipple) (§57.5)
- [ ] Implement `historySendIconFg` matching `windowBgActive` (§57.5)
- [ ] Implement history reply/pinned tokens (historyReplyBg, historyReplyIconFg, historyPinnedBg) (§57.5)
- [ ] Implement unread bar tokens (historyUnreadBarBg, historyUnreadBarFg) (§57.5)
- [ ] Implement history scroll tokens (historyScrollBg, historyScrollBgOver, historyScrollBarBg, historyScrollBarBgOver) with alpha (§57.5)
- [ ] Implement scroll-to-bottom button tokens (historyToDownBg, historyToDownBgOver, historyToDownFg) (§57.5)

### §57.6 Peer / Author Colors

- [ ] Implement 8-way peer name color palette (historyPeer1-8NameFg) for group member name coloring (§57.6)
- [ ] Light peer name colors: red #C03D33, green #4FAD2D, yellow #D09306, blue #168ACD, purple #8544D6, pink #CD4073, sea #2996AD, orange #CE671B (§57.6)
- [ ] Dark peer name colors: red #FB6169, green #85DE85, yellow #F3BC5C, blue #65BDF3, purple #B48BF2, pink #FF5694, sea #62D4E3, orange #FAA357 (§57.6)
- [ ] Implement 8-way peer userpic background colors (historyPeer1-8UserpicBg) — same values for both themes (§57.6)

### §57.7 Box / Modal Colors

- [ ] Implement box color tokens (boxBg, boxTextFg, boxTitleFg, boxSearchBg, boxTitleAdditionalFg) (§57.7)
- [ ] Implement box status color tokens (boxTextFgGood, boxTextFgError) (§57.7)
- [ ] Handle `boxDividerBg` fallback to `windowBgOver` (no standalone token) (§57.7)

### §57.8 Profile / Info Colors

- [ ] Implement profile status tokens (profileStatusFgOver) — base falls through to `windowSubTextFg` (§57.8)
- [ ] Implement profile verified check tokens (profileVerifiedCheckBg, profileVerifiedCheckFg) (§57.8)
- [ ] Implement profile admin star tokens (profileAdminStartFg, profileOtherAdminStarFg) (§57.8)

### §57.9 Button / Accent Colors

- [ ] Implement active button tokens (activeButtonBg, activeButtonBgOver, activeButtonBgRipple, activeButtonFg, activeButtonSecondaryFg) (§57.9)
- [ ] Implement active line tokens (activeLineFg, activeLineFgError) (§57.9)
- [ ] Implement attention button tokens (attentionButtonFg, attentionButtonBgOver, attentionButtonBgRipple) — with alpha on dark variants (§57.9)
- [ ] Implement light button tokens (lightButtonBg, lightButtonBgOver, lightButtonBgRipple, lightButtonFg) (§57.9)

### §57.10 Sidebar / Folders Rail Colors

- [ ] Implement sidebar background tokens (sideBarBg, sideBarBgActive, sideBarBgRipple) (§57.10)
- [ ] Implement sidebar text/icon tokens (sideBarTextFg, sideBarTextFgActive, sideBarIconFg, sideBarIconFgActive) (§57.10)
- [ ] Implement sidebar badge tokens (sideBarBadgeBg, sideBarBadgeBgMuted, sideBarBadgeFg) (§57.10)

### §57.11 Missing / Derived Token Handling

- [ ] Handle `dialogsChatBgOver` as synonym for `dialogsBgOver` (§57.11)
- [ ] Handle top bar tokens reusing `menuIconFg`/`windowFg`/`windowSubTextFg` (no dedicated tokens) (§57.11)
- [ ] Handle `historyComposeButton` as compound of Bg/BgOver/BgRipple tokens (§57.11)
- [ ] Handle `profileStatusFg` fallback to `windowSubTextFg` (only Over variant has own token) (§57.11)
- [ ] Handle `boxDividerBg` rendered from `windowBgOver` plus shadow line (§57.11)
- [ ] Handle dark theme `menuBgOver` quirk (#FFFFFF upstream) — override to ~#2B3744 matching AyuGram (§57.11)
- [ ] Handle dark theme shadow suppression: msgOutShadow/msgInShadow alpha 00 on purpose (§57.11)

