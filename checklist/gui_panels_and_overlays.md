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
- [ ] Panel chrome: 324px min / 392px preferred width; three wrap modes (Side, Narrow, Layer); layer mode with 48px margin each side, rounded top edges, boxBg background, top whitespace 20-40px — spec §8 / §8.6
- [ ] Navigation stack: push on sub-section click, pop on back; slide animations (FromRight open / FromLeft back); Memento restores scroll position, search query, active media tab — spec §8

### §8.1 Cover / TopBar Compression
<!-- File: dart/lib/ui/info_panel.dart -->
- [ ] Flexible top bar: 236px expanded / 56px collapsed; three snap resting heights (0px, 112px, 180px scroll); easeOutQuint 260ms snap animation; height = clamp(236 - scrollTop, 56, 236) — spec §8.1
- [ ] Avatar: 80px diameter (currently 72px — fix), centered, top offset 24px; name at y=113px, status at y=134px — spec §8.1
- [ ] Back/title fade on collapse: FadeWrap scale 0.7, 150ms; action-row opacity linear with scroll; direction-reversal mid-animation re-base — spec §8.1
- [ ] Cover gradient for collectible/color profiles; animated emoji-status pattern behind avatar (Premium); story ring outline — spec §8.6

### §8.2 Action Button Row
<!-- File: dart/lib/ui/info_panel.dart -->
- [ ] Action buttons: 52px square, 23px icons, 68px total row height, 10px spacing, 18px side padding; HorizontalFitContainer layout; max 3 primary buttons, overflow to "More" popup — spec §8.2
- [ ] Button roster by peer type: Message, Join, Mute/Unmute, Call, Video Call, Discuss, Manage/Edit, Leave, Gift, Report, More — spec §8.2
- [ ] Mute button: Lottie crossfade animation (profile_muting/unmuting); right-click opens mute-duration submenu — spec §8.2
- [ ] Action-row collapse animation: buttons shrink 52→0 past 50% scroll; per-button opacity and icon-scale follow scroll progress — spec §8.1 / §8.2

### §8.3 Shared Media Navigation
<!-- File: dart/lib/ui/info_panel.dart -->
- [ ] Shared media section: vertical type-button stack (Photo, Video, File, Audio, Link, Voice, GIF, Poll, Stories, Saved, Gifts, Common Groups, Similar Channels, Downloads); each row hidden when count=0 — spec §8.3
- [ ] In-section search row: 44px height (46px in Layer mode), margins(8,6,8,6); sub-tab chips for stories-archive / gift-category — spec §8.3

### §8.4 Members List
<!-- File: dart/lib/ui/info_panel.dart — _MembersSection / _MemberRow -->
- [x] Members section rendered with avatar, name, and online/role status — spec §8.4 — DONE (basic) in info_panel.dart
- [ ] Member row spec dimensions: 42px avatar at pos(18,6), name at (79,11), status at (79,31), row height 52px — spec §8.4
- [ ] Members header: 56px height; Add Member button (38x38 circle ripple); Search button (38x38) — spec §8.4
- [ ] Admin/Creator pill badges: "owner" / "admin" pill, margins(5,-1,5,0); right-action area shows pill OR remove-cross — spec §8.4
- [ ] Member row context menu: View Profile, Send Message, Promote, Demote, Restrict, Remove, Ban, Copy Username/ID — spec §8.4
- [ ] Flat list sorted online-first then alpha; no online/offline divider; stories ring on avatar — spec §8.4

### §8.5 Grid Columns (Photos / Videos / Gifts)
<!-- File: dart/lib/ui/info_panel.dart — not yet implemented -->
- [ ] Photo/video grid: column count = max(1, floor((width-4)/84)); cell side = floor((width-6-2(cols-1))/cols); 2px gap, 3px side padding; square thumbnails — spec §8.5
- [ ] Stories grid: 9:16 aspect ratio cells — spec §8.5
- [ ] Date section headers: 28px height, semibold text at offset(14,6) — spec §8.5
- [ ] GIF layout: masonry/waterfall (variable aspect ratios); Files/Links/Audio/Voice: single-column list items — spec §8.5
- [ ] Empty-state widget when list height <= threshold; gifts grid with taller aspect override — spec §8.5

### §8.6 Additional Info Features
<!-- File: dart/lib/ui/info_panel.dart — not yet implemented -->
- [ ] Pinned-to-top gifts row: 6 slots around avatar, 20px gift size — spec §8.6
- [ ] "Show my last seen" pill: 18px height, 12px font, pos(3,58) — spec §8.6
- [ ] Stars-rating badge: left 107px, top 57px; unique-badge tooltip on click — spec §8.6
- [ ] Business Hours / Location / Birthday / Personal Channel detail rows — spec §8.6
- [ ] AyuGram ID row (unconditional) — spec §8.6
- [ ] Music mini-player hook in info panel: performer + title labels, padding margins(12,8,24,8) — spec §8.6

### §8.7 Per-Peer-Type Sections
<!-- File: dart/lib/ui/info_panel.dart -->
- [x] DM: avatar, name, online/last-seen status — spec §8 — DONE in _AvatarHeader
- [x] Group: member count as status subtitle — spec §8 — DONE in _AvatarHeader
- [x] Channel: subscriber count as status subtitle — spec §8 — DONE in _AvatarHeader
- [x] Notifications toggle (mute/unmute) — spec §8 — DONE in _NotificationToggle
- [ ] DM details: phone, username, bio fields with TextWithLabel style; empty fields auto-hide; Share/Edit/Delete Contact, Block/Unblock actions — spec §8
- [ ] Group info: Leave Group, Report, Edit Group (if admin); click member pushes user profile — spec §8
- [ ] Channel info: Similar Channels button; Join/Leave actions; no inline members list — spec §8
- [ ] Live reactivity: name, phone, bio, member count, notifications update as live streams — spec §8

---

## §9 — Context Menus & Actions

### §9.1 Context Menu Chrome
<!-- File: dart/lib/ui/chat_view.dart (showMenu calls) — NOT spec-compliant yet -->
- [ ] Custom popup menu widget: 8px corner radius, 200ms sineInOut open / 150ms fade close; min 156px / max 300px width; shadow blurRadius 5, offset(0,1), opacity 0.25 — spec §9.1
- [ ] PanelAnimation reveal: width 0.5→1.0 over 0.6 duration, height 0.3→1.0 over 0.9, opacity 0.2→1.0 over 0.3 — spec §9.1
- [ ] Item layout (no icon): margins(17,8,17,7), height ~28px, normalFont 13px — spec §9.1
- [ ] Item layout (with icon): margins(54,8,17,8), height ~29px; icon at pos(15,5) size 20x20; submenu arrow tinted windowBoldFg — spec §9.1
- [ ] Separator: 1px height, slot 11px, margins(0,5,0,5), color menuSeparatorFg — spec §9.1
- [ ] Ripple: 650ms show / 200ms hide, color windowBgRipple — spec §9.1
- [ ] Top fade: fadeHeight 0.2, fadeBg menuBg — spec §9.1
- [ ] Theme tokens: bg windowBg, hover windowBgOver, text windowFg, icon menuIconFg / menuIconFgOver — spec §9.1

### §9.2 Attention-Style Items
<!-- File: dart/lib/ui/chat_view.dart -->
- [x] Delete item styled with error color (theme.colorScheme.error) — spec §9.2 — DONE (partial) in chat_view.dart
- [ ] Full attention style: attentionButtonFg red icon, separate menuWithIconsAttention variant for full red text; confirmation box uses attentionBoxButton (red fill) — spec §9.2

### §9.3 Message Context Menu
<!-- File: dart/lib/ui/chat_view.dart — _showMessageContextMenu -->
- [x] Reply, Copy Text, Forward, Select, Edit (own messages), Delete — spec §9 — DONE in chat_view.dart
- [x] Pin/Unpin toggle — spec §9 — DONE in chat_view.dart
- [ ] Additional message actions: Quote and Reply, Voice Timecode, Copy Selected Text, Translate Selected, Go to Message, View Replies/Topic/Thread, Send Now (scheduled), Reschedule, Save/Copy Image, Copy Message/Post Link — spec §9
- [ ] Sticker/GIF actions: Attached Stickers, Open/Save GIF, Sticker Pack Info, Favorite/Unfavorite Sticker — spec §9
- [ ] Report, Show in Folder/Finder (local files), Copy Link (on URLs) — spec §9
- [ ] Poll-specific: Translate Poll, Retract Vote, Stop Poll, per-option submenu — spec §9
- [ ] AyuGram additions: Edits History, Hide Message, User's Messages, Repeat Message, Message Details submenu, Read Until, Burn — spec §9.6
- [ ] Item ordering: Pass 1 top actions → Pass 2 message actions → Pass 3 post-actions; Copy is flat (not submenu) — spec §9.6
- [ ] Selection-mode top-bar menu: Forward Selected, Send Now Selected, Delete Selected, Download Files, Clear Selection — spec §9.6

### §9.4 Chat List Context Menu
<!-- File: dart/lib/ui/chat_view.dart — _showChatContextMenu -->
- [x] Pin/Unpin, Mute/Unmute, Mark as Read/Unread, Archive/Unarchive, Leave — spec §9 — DONE in chat_view.dart
- [ ] Mute submenu: ringtone, toggle sound, preset durations (1h/8h/2d), custom, mute forever/unmute — spec §9
- [ ] New Window action; Folder actions (expand/collapse, settings, mark read); Clear History — spec §9

### §9.5 User Context Menu
<!-- File: not yet implemented -->
- [ ] User context menu: View Profile, Mention, Send Message, Add/Edit/Delete Contact, Share Contact, Block/Unblock, Report; admin actions: Promote, Restrict, Ban, Delete All from User — spec §9

### §9.6 Reaction Picker
<!-- File: not yet implemented -->
- [ ] Reaction strip: 40px height, 32px slot, 26px emoji render, 7px skip; floating strip appears after 300ms hover delay — spec §9.3
- [ ] Per-message corner reaction button: pill 36x32, anchor point(7,-9); 22px corner reaction image — spec §9.3
- [ ] Toggle/activate/expand/collapse animation durations (120ms/150ms/300ms/250ms); 8 quick-reaction slots — spec §9.3
- [ ] Per-icon hover scale 1.24x over 200ms; reaction fly-up 50px on pick; inline reaction counter dimensions — spec §9.3
- [ ] Expand chevron opens full emoji-grid panel with category tabs, search, sticker effects — spec §9.3

### §9.7 Forward Dialog (ShareBox)
<!-- File: not yet implemented -->
- [ ] ShareBox modal: recipient rows 108px height (6px photo top, 6px name top, 6px column skip); search field at top; self-chat first — spec §9.4
- [ ] Selected state: blue ring, avatar shrinks 28→24px; comment field slides in (min 36px / max 72px) — spec §9.4
- [ ] 3-dot menu: Show sender's name, Show caption checkmarks; Schedule, Send silent/without-sound/whenOnline; menu opens upward; Send button right-click opens same menu — spec §9.4
- [ ] Folder-based filter tabs in recipient list — spec §9.4

### §9.8 Delete Confirmation Box
<!-- File: not yet implemented -->
- [ ] Delete/Leave confirmation: single message, bulk, date range, clear history, leave group/channel variants; per-peer-type body text matrix — spec §9.5
- [ ] Moderate panel checkboxes: Ban User, Report Spam, Delete All from User; delete button gets "(N)" suffix when delete-all checked — spec §9.5
- [ ] "Also delete for X" checkbox with remembered revoke preference; nested "Remember" checkbox; button text animates "Delete" ↔ "Leave" — spec §9.5
- [ ] Dimensions: boxWidth, boxPadding, boxMediumSkip, boxLittleSkip; delete button is attentionBoxButton (red fill) — spec §9.5

---

## §10 — Emoji / Sticker / GIF Panels

### §10.1 Panel Chrome
<!-- File: dart/lib/ui/emoji_panel.dart — DOES NOT EXIST YET -->
- [ ] TabbedPanel widget: 345px wide, min 278px / max 640px height; margins(10,10,10,10); 8px corner radius; anchored bottom-right of compose area; shadow via BoxShadow — spec §10.1
- [ ] Show/hide: 200ms PanelAnimation with reveal (width 0.5→1.0, height 0.3→1.0, opacity 0.2→1.0); auto-hide 300ms on mouse-leave; delayed 3000ms when context menu open — spec §10.1
- [ ] Height = emojiPanHeightRatio × window height, clamped [278px, 640px] — spec §10.1

### §10.2 Tab Bar
<!-- File: dart/lib/ui/emoji_panel.dart -->
- [ ] Three-tab bar: Emoji / Stickers / GIFs; SettingsSlider subclass with semibold labels, active underline (activeLineFg); slide 200ms linear horizontal translate + alpha crossfade — spec §10.2

### §10.3 Emoji Tab
<!-- File: dart/lib/ui/emoji_panel.dart -->
- [ ] 8 category icons (Recent, Smileys, Nature, Food, Activities, Travel, Objects, Symbols); active bg (activeFg); grid columns = (panelWidth - 2*padding) / singleSize; cell ~37-42px — spec §10.3
- [ ] Skin-tone popup: 500ms long-press, base + 5 Fitzpatrick variants; chrome emojiColorsPadding=8px, emojiColorsSep=1px; selection persisted per-emoji — spec §10.3
- [ ] Custom emoji pack sections: locked packs show "Unlock" (premium gate); free packs show "Add"; collapsed sets show 3 rows + "+N" overflow badge — spec §10.3

### §10.4 Sticker Tab
<!-- File: dart/lib/ui/emoji_panel.dart -->
- [ ] Sticker grid: ~64px cells, 11px padding; footer with 8 pack icons (horizontally scrollable), active pack highlighted, scroll-to-pack 400ms easeOutCubic; Recent section (server cap 20) — spec §10.4
- [ ] Featured/trending packs with inline "Add" button (~26px); 400ms debounce search; empty search shows recent popular packs — spec §10.4
- [ ] Context menu on sticker: Fave/Unfave, View Set; custom emoji packs: also Copy Link; AyuGram: per-pack "Hide" toggle — spec §10.4 / §10.7

### §10.5 GIF Tab
<!-- File: dart/lib/ui/emoji_panel.dart -->
- [ ] GIF tab: margins(9,5,3,9); line-packing layout (fill rows until next won't fit; row height uniform within row); 3px inter-item skip on both axes — spec §10.5
- [ ] Default source: saved GIFs; query switches to @gif bot results; category shortcuts footer (emoji tokens); context menu: Save GIF / Delete GIF — spec §10.5

### §10.6 Inline Suggestions (Field Autocomplete)
<!-- File: dart/lib/ui/emoji_panel.dart or separate widget -->
- [ ] Inline autocomplete widget (separate from TabbedPanel): anchored above compose field; triggered by @, /, :text, #hashtag, emoji sequence; max 4.5 visible rows (~180px cap) — spec §10.6
- [ ] Emoji suggestions: horizontal row ~40px cells, 8px fade at ends; replaces :text token in-place — spec §10.6
- [ ] Sticker suggestions: half-width cells, server query, click sends; arrow keys / Tab navigate, Enter picks — spec §10.6
- [ ] Mention/hashtag/command rows: 40px height, 40px avatar + name + subtitle; no debounce, client-side filter; @-mentions and /commands — spec §10.6
- [ ] Inline bot results: 400ms debounce, mosaic row-packing layout — spec §10.6

### §10.7 Power-save & Edge Cases
<!-- File: dart/lib/ui/emoji_panel.dart -->
- [ ] Power-save gating: skip panel animation when PowerSaving::kEmojiPanel is on; no Masks tab in default build — spec §10.7

---

## §11 — Authentication / Login Flow

### §11.1 Architecture & Navigation
<!-- File: dart/lib/ui/auth_screen.dart, dart/lib/state/auth_state.dart -->
- [x] Step-stack auth screen driven by AuthState; QR / phone input / OTP / 2FA / choose variants — spec §11.1 — DONE in auth_screen.dart
- [x] Cancel button — spec §11.1 — DONE in auth_screen.dart
- [ ] Persistent bottom bar: Next RoundButton (300x42px, radius 6px), Back IconButton, Change Language LinkButton, Settings button, optional Reset Account button — spec §11.1
- [ ] goNext / goBack / goReplace navigation with slide/cover animations and step sharing Data struct — spec §11.1

### §11.2 Next Button
<!-- File: dart/lib/ui/auth_screen.dart -->
- [x] Next button: 300px wide, 42px height, filled style — spec §11.2 — DONE in auth_screen.dart
- [ ] Next button spec details: radius 6px, textTop 11px, base Y=266px, slide-in from +200px, 150ms linear fade; disabled during flood; error: shake + red border — spec §11.2

### §11.3 QR Code Screen
<!-- File: dart/lib/ui/auth_screen.dart -->
- [x] QR code displayed: 180px, white-card bg, 8px radius — spec §11.3 — DONE in auth_screen.dart
- [ ] QR spec details: 12px card padding, center logo disc 44px blue (#40A7E3) with Telegram plane; radial spinner (180px, 1-2px stroke) fades as QR appears; QR crossfades on token refresh; numbered instruction lines; "Log in by phone number" link; Next button hidden on QR screen — spec §11.3

### §11.4 Phone Number Screen
<!-- File: dart/lib/ui/auth_screen.dart — currently single TextField -->
- [ ] Phone entry: country picker (300px wide, 61px min height); separate country-code field (64px, "+" prefix, digit-only mask) + phone-body field (~236px, digit-only with space separators per country pattern); country picker popup with flag + name + code — spec §11.4
- [ ] Validation: PHONE_NUMBER_INVALID inline error + field shake; PHONE_NUMBER_BANNED modal dialog with support link; flood warning + countdown — spec §11.4

### §11.5 OTP Code Screen
<!-- File: dart/lib/ui/auth_screen.dart — currently single TextField -->
- [ ] OTP cells: cell 40x50px, border 4px, inter-cell gap 10px, digit font 20px; bg windowBgOver; unfocused/focused/error border tokens; each cell is own focus target — spec §11.5
- [ ] Cell animations: new digit fade-in + slide-up 10px; delete scale-down + fade-out; 120ms linear — spec §11.5
- [ ] Error shake on wrong code; paste auto-fills + submits when complete; arrow/Home/End/Backspace navigation — spec §11.5
- [ ] Call countdown row "Telegram will call you in X:XX" → "Calling..."; "Didn't get the code?" link — spec §11.5

### §11.6 2FA Password Screen
<!-- File: dart/lib/ui/auth_screen.dart — currently basic TextField -->
- [ ] 2FA screen: PasswordInput 300px wide, offset 74px; hint label "Hint: {hint}"; SRP hash client-side; error shake + red border + selectAll; "Forgot password?" link swaps to recovery-code mode — spec §11.6
- [ ] No recovery email path: info box with "Reset account" button (7-day timer) — spec §11.6

### §11.7 Registration Screen
<!-- File: dart/lib/ui/auth_screen.dart — not yet implemented -->
- [ ] Registration: UserpicButton at top offset 10px (tap opens photo picker + server crop-upload); first + last name fields 300px wide each; RTL swap for Arabic/Farsi/Hebrew; terms acceptance dialog gates submit — spec §11.7

### §11.8 Inter-Screen Animations
<!-- File: dart/lib/ui/auth_screen.dart -->
- [ ] Cover gradient area: 208px height (introCoverHeight), vertical linear blue sweep; logo centered at (center - 50px, 46px top) — spec §11.8
- [ ] Slide easing: easeOutCirc for cover transitions (QR/phone), linear otherwise; 200ms crossfade; horizontal translate with clipping — spec §11.8

---

## §12 — Calls UI

### §12.1 1-on-1 Call Panel
<!-- File: dart/lib/ui/call_screen.dart — DOES NOT EXIST YET -->
- [ ] Call window: default 720x540, min 380x520; gradient bg from caller profile-photo dominant colors — spec §12.1
- [ ] Incoming state: 160px circle userpic, caller name 21px semibold, "Incoming call..." status, Decline (red) + Answer (green with animated ripple ring tracking ringtone peak level) — spec §12.1
- [ ] Active audio call: userpic, name, mm:ss duration timer (1Hz tick); bottom button row: Screencast, Camera, Hangup (red, centered "End Call"), Mute, Add People — spec §12.1
- [ ] Remote muted pill, low-battery pill; controls auto-hide 5000ms fullscreen / 2000ms mouse-leave; mouse movement restores — spec §12.1

### §12.2 Signal Bars
<!-- File: dart/lib/ui/call_screen.dart -->
- [ ] 4-bar signal indicator: bar width 2px, heights [4,6,8,10]px, skip 2px, radius 1px; active bar full opacity, inactive 0.5 opacity; quality [0..100] maps to [0..4] active bars, snap (no interpolation) — spec §12.2

### §12.3 Encryption Fingerprint
<!-- File: dart/lib/ui/call_screen.dart -->
- [ ] 4 emoji at rest; reveal carousel: 10 emojis cycled per position, 50ms stagger, 100ms per-emoji hop (~1200ms total); indices from SHA-256 over 658-emoji table; tooltip after 1000ms hover; pill container radius = height/2 — spec §12.3

### §12.4 Video Call / PIP
<!-- File: dart/lib/ui/call_screen.dart -->
- [ ] Remote video fills main area (KeepAspectRatio crop); userpic/name/status hidden while stream live — spec §12.4
- [ ] Self-view VideoBubble: default 160x110px; snap-to-corners (TopLeft/TopRight/BottomLeft/BottomRight default BottomRight); 12px inset rest, ~120ms easeOutCirc snap on mouse-release — spec §12.4
- [ ] Self-view mirrored by default (flip horizontal); mirror off during screen-share — spec §12.4
- [ ] Pre-connect outgoing preview scales 360x120→1620x540 based on window height; camera button with corner chevron for device-selector menu — spec §12.4

### §12.5 Group Call (Narrow / Wide)
<!-- File: dart/lib/ui/call_screen.dart -->
- [ ] Width threshold: 600px; narrow = single column (participants + bottom controls, min 380px); wide = video viewport + members sidebar — spec §12.5
- [ ] Title bar: group name, participant count, menu toggle; recording state: 6px red dot with 1200ms opacity-breathing loop — spec §12.5
- [ ] Mode transition animation via slideWrapDuration (~150-200ms) — spec §12.5

### §12.6 Speaker Blob Animation
<!-- File: dart/lib/ui/call_screen.dart -->
- [ ] Blob animation: minor blob (inner, scale 0.545, 6 vertices) + major blob (outer, scale 0.605, 8 vertices); min 27px / max 29px radius; 215ms level-to-level interpolation; userpic pulses 80%→100% with voice level — spec §12.6

### §12.7 Mute Button (Big)
<!-- File: dart/lib/ui/call_screen.dart -->
- [ ] Mute button: 36x36 Lottie icon in 42px circle; three states: green (unmuted), gray (muted), purple (force-muted by admin); each state change plays dedicated Lottie segment; blob ring pulses 215ms — spec §12.7

### §12.8 Minimised TopBar
<!-- File: dart/lib/ui/call_screen.dart / shell.dart -->
- [ ] Minimised call bar: 38px height; group name, mm:ss duration, participant userpic strip (28px each, 8px overlap), mute toggle, red hangup — spec §12.8
- [ ] Gradient states: Active (greens), Muted (grays), Connecting (solid callBarBgMuted), Force-muted (purples); gradient sweeps bar width simultaneously with mute-icon cross-line interpolation — spec §12.8

### §12.9 Screen-Share Chooser
<!-- File: dart/lib/ui/call_screen.dart -->
- [ ] Screen-share source chooser: dual-tab (Windows / Full Screen); thumb 235x165px, 2px horizontal gap, 10px vertical gap; optional "Share audio" checkbox (Linux PipeWire gated) — spec §12.9

### §12.10 Rating Dialog
<!-- File: dart/lib/ui/call_screen.dart -->
- [ ] Post-call rating: 5 star icons (unselected windowSubTextFg, selected lightButtonFg); comment input max 135px height; submits via phone.setCallRating — spec §12.10

---

## §13 — Mobile / Web Compatibility

### §13.1 Adaptive Layout Breakpoints
<!-- File: dart/lib/ui/shell.dart — DONE -->
- [x] OneColumn < 640px, TwoColumn 640-932px, ThreeColumn >= 932px breakpoints implemented — spec §13.1 — DONE in shell.dart
- [x] isOneColumn / twoColumn / threeColumn layout enum and predicates — spec §13.1 — DONE in shell.dart
- [x] Sidebar min 260px, chat min 380px, info panel min 292px / max 392px constants — spec §13.1 — DONE in shell.dart
- [x] Wide chat bubbles threshold 880px (wideChatThreshold constant) — spec §13.1 — DONE in shell.dart
- [ ] Group call narrow/wide switch at 600px (distinct from main window breakpoints) — spec §13.1

### §13.2 OneColumn Mode
<!-- File: dart/lib/ui/shell.dart — MOSTLY DONE -->
- [x] One panel visible at a time; tapping chat slides message view in from right; back button in chat top-bar — spec §13.2 — DONE in shell.dart
- [x] Slide animation with easeOutCubic curve, ~200ms, both sides rendered as cached pixmaps — spec §13.2 — DONE in shell.dart
- [ ] Info panel opens as full-width takeover layer in OneColumn mode — spec §13.2
- [ ] Folder tabs switch from vertical rail to horizontal strip below search bar in OneColumn mode — spec §13.2

### §13.3 Other Responsive Adaptations
<!-- File: dart/lib/ui/shell.dart -->
- [x] Sidebar cannot shrink below 260px — spec §13.3 — DONE in shell.dart
- [x] Wide chat mode (>= 880px): bubbles center with gutters — spec §13.3 — DONE in shell.dart (constant defined)
- [ ] Emoji panel height clamped [278px, 640px] (part of §10 panel, listed here for completeness) — spec §13.3
- [ ] Forward/Share dialog: full-screen overlay regardless of width — spec §13.3

### §13.4 Touch vs Mouse
<!-- File: dart/lib/ui/ (various) -->
- [x] Long-press enters selection mode (message bubbles) — spec §13.4 — DONE in chat_view.dart
- [ ] Long-press context menu threshold: ~500ms desktop / ~300ms mobile — spec §13.4
- [ ] Swipe gestures: Manhattan distance gate 5-10px; drag-to-reorder 30px vertical; drag-to-filter 30px horizontal / 75px vertical — spec §13.4
- [ ] Folder tab auto-switch while dragging: 2000ms hover freeze timeout — spec §13.4
- [ ] Voice recording: hold-to-record, slide-up to lock — spec §13.4

### §13.5 Flutter-Web Divergence
<!-- File: dart/lib/utils/system_tray.dart, dart/lib/bridge/bridge_web.dart -->
- [ ] Web: hide system tray icon, global hotkeys, native file picker, clipboard image read, process-level single-instance — spec §13.5
- [ ] Web: Notifications API + favicon badge instead of tray; <input type=file> + HTML5 drop events — spec §13.5
- [ ] Web degraded: keyboard shortcuts yield to browser-reserved combos; fullscreen requires user gesture; WebRTC getUserMedia device-selection constraints — spec §13.5
- [ ] Mobile-web: hover states become tap-only; compose-toolbar formatting buttons visible — spec §13.5
