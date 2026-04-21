# GUI Checklist: §5 Message List & Bubbles, §6 Media Message Types, §7 Compose Area

<!-- Dart files for §5: dart/lib/ui/message_bubble.dart, dart/lib/ui/chat_view.dart (_MessageList, _DateSeparator, _ScrollToBottomFab) -->
<!-- Dart files for §6: dart/lib/ui/message_bubble.dart (_VisualMedia, _VoiceIndicator, _AudioIndicator, _FileIndicator) -->
<!-- Dart files for §7: dart/lib/ui/chat_view.dart (_ComposeArea, _ReplyBar, _EditBar, _PinnedBar, _SelectionBar) -->

---

## §5. Message List & Bubbles

### §5.1 Message List Chrome

- [x] Scroll newest-at-bottom via reversed ListView with lazy-load trigger at top — spec §5, DONE in chat_view.dart (_MessageList)
- [ ] Scroll-to-bottom FAB: 52×62px hit-area, 42px ripple disc, two-layer icon (historyToDownBelow shadow + historyToDownAbove arrow), 12px right / 10px bottom anchor, 150ms slide-in animation — spec §5 (S5). Current impl: FloatingActionButton.small at (16,16), wrong size/icon/position/animation
- [ ] FAB show threshold: 480px from bottom (not current ~200px offset check) — spec §5
- [ ] Stacked corner buttons order (bottom→top): Jump-down → Mentions → Reactions → PollVotes, 4px gap, Mentions/Reactions/PollVotes slide from right, Jump-down slides up — spec §5
- [ ] FAB unread-count badge: 22px min height, semibold 13px, muted palette (bgMuted #bbbbbb day / #3e546a night), 4px above button top — spec §5. Current: uses primary color, not muted palette
- [x] Date separator pill: centered text, fully-rounded pill (radius = height/2), msgServicePadding 12/3/12/4, 10px above / 2px below — spec §5. DONE in chat_view.dart (_DateSeparator) — partially; colors use theme.colorScheme.surface, not exact msgServiceBg tokens
- [ ] Date separator exact colors: day #517c417f / night #213040d5, text #ffffff — spec §5. Current uses colorScheme.surface.withAlpha(0.8)
- [ ] "Unread Messages" full-width band above first unread message — spec §5

### §5.2 Message Bubbles

- [x] Own messages right-aligned, received left-aligned; Saved Messages forwarded-from-self right, others left — spec §5, DONE in message_bubble.dart
- [x] Bubble corner radii: large 16px, small 6px, each corner independent; tail on bottom-sender-side corner of last-in-group — spec §5, DONE in message_bubble.dart
- [x] Max bubble width 430px (542px wide mode) — spec §5, DONE (430px constant in message_bubble.dart)
- [ ] Exact bubble colors: msgInBg #ffffff / msgOutBg #effdde day; #182533 / #2b5278 night; selected variants — spec §5. Current uses AppColors.bubbleSentLight etc. — verify tokens match
- [ ] Bubble shadows: msgInShadow 16% alpha / msgOutShadow 11% alpha day; disabled (00 alpha) night — spec §5. Not implemented
- [ ] Bubble margins: left 16px, top 6px, right 56px, bottom 2px; attached-to-prev collapses top to 0px — spec §5. Current uses symmetric padding 16px, not per-spec margins
- [x] Internal padding: 11px horizontal, 8px vertical — spec §5. DONE (horizontal:11, vertical:6 — close but vertical is 6 not 8)

### §5.3 Consecutive Message Grouping

- [x] AttachedToPrevious/Next flags for spacing and corner rounding, tail only on last in group, sender name + avatar only on first — spec §5, DONE in chat_view.dart (_MessageList grouping logic) and message_bubble.dart
- [x] Avatar size 33px, avatar-skip offset 40px — spec §5, DONE in message_bubble.dart (33px avatar, 7px gap ≈ 40px total skip)
- [ ] BubbleAttachedToPrevious/Next: top corners on sender's side collapse to Small (6px) when not first-in-group; bottom corners collapse to Small when not last-in-group — spec §5. Current: bottomSenderSide is always _radiusSmall regardless of isLastInGroup, which deviates from spec

### §5.4 Bubble Content Layout

- [x] Sender name: semibold, colored per user (7 colors by id%7), hidden if attached/DM/outgoing — spec §5, DONE in message_bubble.dart
- [ ] Admin/creator badge after sender name — spec §5. Not implemented
- [ ] Topic button (forums): small pill with topic icon + name — spec §5. Not implemented
- [ ] Via-bot label (shown if no sender name and no forward header) — spec §5. Not implemented
- [x] Forward header: "Forwarded from Name" — spec §5, DONE in message_bubble.dart
- [x] Reply block: 2px left bar, clickable jump to original, sender name + preview — spec §5, DONE in message_bubble.dart (_ReplyPreview). Missing: 36px height spec, 10px gap from content
- [ ] Message text: rich text rendering — bold, italic, code spans, links, spoilers, blockquotes with colored outlines — spec §5. Current: plain Text() only
- [x] Bottom info: timestamp + edited + delivery status (clock/single-check/double-check) — spec §5, DONE in message_bubble.dart
- [ ] Bottom info exact metrics: msgDateFont 13px regular, historyViewsSpace 8px, 20px per icon, 24px pin, 24px send-state; exact icon sizes (sent 13×11, received 18×11, clock 11×11, views 16×11) — spec §5. Current uses fontSize 11 and Icons.*
- [ ] Bottom info exact colors: msgInDateFg #a0acb6 / #6d7f8f; msgOutDateFg #6db566 / #7da8d3; outgoing ticks #57b84c day / #6bbfff night — spec §5. Current uses theme.textTheme.bodySmall color
- [ ] Bottom info: media-overlay variant with translucent bg (msgDateImgPadding 8/2, delta 4px from corner), inverted icon colors #ffffff — spec §5. Not implemented (media messages always use inline bottom info)
- [ ] Views count + forwards count in bottom info — spec §5. Not implemented
- [x] Edited indicator — spec §5, DONE in message_bubble.dart
- [x] Reactions: InlineList of emoji pills below content — spec §5, DONE in message_bubble.dart (_ReactionList)

### §5.5 Sender Name Colors

- [x] 7 base colors assigned by id%7 — spec §5, DONE in message_bubble.dart (_senderColor). Colors are approximate variants; exact spec day palette: #c03d33 / #4fad2d / #d09306 / windowActiveTextFg / #8544d6 / #cd4073 / #2996ad
- [ ] Exact day palette hex values (see above) and exact night palette: #fb6169 / #85de85 / #f3bc5c / #65bdf3 / #b48bf2 / #ff5694 / #62d4e3 — spec §5. Current approximations differ
- [ ] ColorIndex remap via map [0,7,4,1,6,3,5]; runtime-fetched extended 64-entry palette (indices 8–63 from help.peerColors) — spec §5. Not implemented (static 7-color array only)

### §5.6 Selection Mode

- [x] Long-press to enter selection mode, checkbox per message, selection action bar — spec §5, DONE in chat_view.dart
- [ ] Round checkbox: 20px diameter, 2px stroke, empty border = windowBg (white), fill #00000040, checked fill boxTextFgGood (#4ab44a day / #5598db night), check glyph white — spec §5. Current uses Icons.check_circle / Icons.circle_outlined at 22px, no spec colors
- [ ] Checkbox position: bottom-right of bubble, 5px above bottom edge — spec §5. Not implemented (checkbox is in the Row before the bubble, not overlaid)
- [ ] Selection offset: 30px shift left when active — spec §5. Not implemented
- [ ] Check-mark animation 160ms — spec §5. Not implemented
- [x] Selection action bar: Forward, Delete, Copy — spec §5, DONE in chat_view.dart (_SelectionBar)

### §5.7 Service Messages

- [ ] Service messages: centered text in rounded pill, msgServiceBg day #517c417f / night #213040d5, msgServiceFg #ffffff, msgServicePadding 12/3/12/4, 10px above / 2px below, 13px semibold — spec §5. Not implemented as a distinct service-message widget; system messages arrive as regular text bubbles

---

## §6. Media Message Types

### §6.1 Shared Constants & Photo Layout

- [x] Photos inline in bubble, 430px max, 100px min, aspect ratio preserved — spec §6. DONE in message_bubble.dart (_VisualMedia). Current max is 300px, not 430px
- [ ] Fix max dimension to 430px (currently 300px) and min to 100px (currently 80px) — spec §6
- [ ] Four-tier photo loading: full → thumbnail → small → blurred inline placeholder — spec §6. Current: local file or base64 thumb only, no progressive tiers
- [ ] Click opens media viewer (lightbox, spec §20) — spec §6. Not implemented (no tap handler on media)
- [ ] Photo enlarge button in bottom-right corner for large photos — spec §6. Not implemented
- [ ] Caption below photo narrows the photo width — spec §6. Not implemented (captions are separate text blocks above media)

### §6.2 Spoiler Overlay (photos, GIFs, videos)

- [ ] Per-media spoiler animation: 3000 particles / 128px canvas, 5 shapes, 60 frames at 33ms, 1.5–2px size, 10–20px speed, 300ms fade in/out, composited with bubble rounding mask, α=32/255 darkening — spec §6. Not implemented
- [ ] Tap-to-reveal: 200ms fadeWrapDuration sineInOut, revealed state persists for session — spec §6. Not implemented
- [ ] Text spoiler descriptor: 9000 particles, 4–8 speed, 1.5–2px size, 200ms fade — spec §6. Not implemented

### §6.3 Photo Albums (Grouped Media)

- [ ] Album layout: up to 10 items, 4px spacing, 100–430px width, per-count layout rules (2-item split, 3-item columns, 4-item grid, 5–10 ComplexLayouter with scoring), corner rounding only at outer edges — spec §6. Not implemented (each photo renders individually)

### §6.4 Videos

- [x] Video thumbnail with centered play button overlay and duration badge — spec §6, DONE in message_bubble.dart (_VisualMedia). Duration badge is bottom-left, not bottom-right corner with semi-transparent bg
- [ ] Fix duration badge position to bottom-right with semi-transparent background, include file size — spec §6
- [ ] Click to open video playback — spec §6. Not implemented

### §6.5 GIFs

- [x] GIF indicator with GIF icon — spec §6, DONE in message_bubble.dart (GIF icon shown in play overlay)
- [ ] GIF max width 320px (not 300px), auto-play and loop, no audio, corner badge "GIF" text — spec §6. Current: static thumbnail with gif icon, no autoplay
- [ ] GIF max inline area 1920×1080px — spec §6

### §6.6 Stickers

- [x] Sticker renders without bubble background (isStickerOnly transparent) — spec §6, DONE in message_bubble.dart
- [x] Sticker display size ~200px max — spec §6. DONE (_VisualMedia clamps to 200px for type 6)
- [ ] Sticker spec max: 224px (static/animated), 256px (emoji stickers) — spec §6. Current uses 200px
- [ ] Lottie animated stickers (TGS format), WEBM video stickers, auto-play on creation — spec §6. Not implemented (static image only)
- [ ] Sticker off-screen: unload player, cache state — spec §6. Not applicable until animation implemented
- [ ] Click opens sticker pack viewer — spec §6. Not implemented
- [ ] No outline/glow/drop-shadow; msgStickerOverlay tint only during selection — spec §6. Not implemented
- [ ] Premium effect multiplier 1.49×, incoming mirrored horizontally, outgoing not — spec §6. Not implemented

### §6.7 Voice Messages

- [x] Voice message indicator: play-button icon + "Voice message" label + duration + file size — spec §6, DONE in message_bubble.dart (_VoiceIndicator). No actual playback or waveform (correctly omitted per CLAUDE.md zero-placeholders)
- [ ] Interactive waveform: 100 samples, re-bucketed to bar count, 2px bars / 1px gap / 3px min / 17px max height, vertically centered, color split at playback position — spec §6. Requires waveform data from engine (bridge not yet piped)
- [ ] Waveform colors: inbox played #40a7e3 / unplayed #d4dee6; outbox played #5ebd66 / unplayed #b3e2b4 — spec §6
- [ ] Hover highlight: bars in hover range overpainted at α=0.30 — spec §6
- [ ] Play/pause control with interactive seeking by tap position — spec §6. Not implemented
- [ ] Optional transcribe button — spec §6. Not implemented

### §6.8 Video Messages (Round Video)

- [x] Circular clip + border shown for video notes (mediaType 5) — spec §6, DONE in message_bubble.dart (_VisualMedia). Uses ClipRRect + circular border, not actual circular clip of image
- [ ] Circular mask: proper ClipOval, max 360px diameter — spec §6. Current shows ClipRRect(8px) + circular border overlay, not a true circle clip
- [ ] Progress arc overlay: 3px stroke with RoundCap, inset by 1.5px, starts 12 o'clock, sweeps clockwise, historyVideoMessageProgressFg color, 0.72 opacity — spec §6. Not implemented
- [ ] Duration badge — spec §6. Not implemented for round video
- [ ] Auto-play muted when on-screen, tap toggles sound — spec §6. Not implemented

### §6.9 Files/Documents

- [x] File indicator: 40px icon left, filename + file size, extension badge — spec §6, DONE in message_bubble.dart (_FileIndicator). Icon 40px (spec says 44px), gap 8px (spec 11px), vertical positioning differs from spec (name at 12px, status at 34px)
- [ ] Fix to 44px icon, 11px gap, middle-truncated filename, icon state variants (download arrow, cancel X, play triangle) — spec §6
- [ ] Click to download/open file — spec §6. Not implemented

### §6.10 Audio/Music

- [x] Audio indicator: play/pause icon + filename + duration + file size — spec §6, DONE in message_bubble.dart (_AudioIndicator). Track title/artist via filename only, no cover art
- [ ] 44px play/pause button, FormatSongNameFor (artist–title split), "played/total" format during playback, cover art — spec §6. Not fully implemented

### §6.11 Polls

- [ ] Full poll widget: question text, radio buttons (18px, 2px stroke) for single-choice / rounded-rect checkboxes (18px, 3px radius) for multi-choice, idle 0.7 opacity / hover 1.0, 120ms toggle animation — spec §6. Not implemented
- [ ] After voting: percentage bars with easeOutCirc animation — spec §6. Not implemented
- [ ] Quiz mode: correct answer green, wrong answer red + 400ms shake (±3° rotation 8 segs / ±3% scale 2 segs) — spec §6. Not implemented
- [ ] Quiz correct fireworks: 60+30 particles, 480×320 canvas, 6 fixed colors, ~2.5–3s — spec §6. Not implemented
- [ ] Footer: total votes count; timed polls: remaining seconds; recent voter userpics row — spec §6. Not implemented

### §6.12 Locations

- [ ] Static map thumbnail 430px max / 100px min, venue title (2 lines) + description (3 lines), click opens coordinates — spec §6. Not implemented
- [ ] Live-location ring: 28px, 2px stroke, msgServiceFg color, bg ring at 0.20 opacity, elapsed arc full opacity, counter-clockwise sweep from 12 o'clock, 1 tick per 1/360 period — spec §6. Not implemented
- [ ] Remaining minutes inside ring (semibold), infinity glyph for "until turned off" — spec §6. Not implemented

### §6.13 Contacts

- [ ] Contact message: circular userpic left, name + phone number, action buttons (Send Message / Add Contact / View Details) — spec §6. Not implemented (renders as _FileIndicator or plain text)

### §6.14 Web Page Previews

- [ ] Article mode: small square thumbnail right, text wraps, 3–5 line description cap, 8px gutter — spec §6. Not implemented
- [ ] Standard mode: full-width media below text, site name + title semibold 13px, description regular — spec §6. Not implemented
- [ ] Mode selection by webpage type (not media dimensions): ForceLargeMedia → Standard, ForceSmallMedia → Article, type-based fallback — spec §6. Not implemented
- [ ] Video webpage: Standard mode, generic play button overlay, "Open" 36px button — spec §6. Not implemented
- [ ] Twitter/Instagram hashtag/mention platform-linking — spec §6. Not implemented

---

## §7. Compose Area

### §7.1 Text Input Field

- [x] Auto-growing TextField, max ~160px (spec 224px), placeholder "Write a message...", Enter sends / Shift+Enter newline — spec §7.1, DONE in chat_view.dart (_ComposeArea). maxHeight 160px not 224px
- [ ] Fix max height to 224px (historyComposeFieldMaxHeight), min 36px; 6px top/bottom fade mask on scroll — spec §7.1
- [ ] Placeholder context variants: "Broadcast a message..." for channels, "Edit message" while editing — spec §7.1. Current always shows "Write a message..."
- [ ] Rich text formatting: Bold (Ctrl+B), Italic (Ctrl+I), Underline (Ctrl+U), Strikethrough (Ctrl+Shift+X), Monospace (Ctrl+Shift+M), Spoiler (Ctrl+Shift+P), Blockquote — spec §7. Not implemented
- [ ] Instant emoji replacement (:) → emoji) — spec §7. Not implemented
- [ ] Link detection after 500ms debounce — spec §7. Not implemented
- [ ] No visible outline: border 0, borderActive 0; strip min height 54px (36 + 2×9 padding) — spec §7.1. Current uses rounded OutlineInputBorder with fillColor

### §7.2 Compose Strip Layout & Slot Buttons

- [ ] Exact strip layout: (botMenu)(attach|replaceMedia)(sendAs)--field--(ttl)(scheduled)(silent|botCmd) emojiToggle send — spec §7.1. Current: only field + send button, no slot buttons
- [ ] Strip bg historyComposeAreaBg: day #ffffff / night #212121; no rounded corners (radius 0px); padding 2px horizontal / 9px vertical — spec §7.1. Current uses colorScheme.surface + 8px/6px padding + rounded field
- [ ] Slot buttons inherit historyAttach: 44×46px, ripple 40×40 at (2,3); icon color historyComposeIconFg #a0acb6 / hover #639ac6 — spec §7.1. Not implemented
- [ ] Emoji toggle: 20×20 circle ring, line 1.5 — spec §7.1. Not implemented

### §7.3 Attachment Button

- [ ] Paperclip button left of input: desktop fires native OS file picker directly (NOT mobile popup) — spec §7.2. Not implemented
- [ ] Attach-bots menu on hover/click if user has registered bots; first entry ("Default") falls through to native picker — spec §7.2. Not implemented

### §7.4 Send Button States & Morph

- [x] Send button with icon switch: check/save while editing — spec §7.3, DONE in chat_view.dart. Basic edit→save state only
- [ ] Full 8-state send button: Send / Schedule / Save / Record / Round / Cancel / Slowmode / EditPrice with correct selection logic — spec §7.3. Only Send and Save implemented
- [ ] Cross-fade morph: 120ms universalDuration, outgoing scales 1×→5×, incoming scales 5×→1×, both fade — spec §7.3. Not implemented
- [ ] Voice↔Round Lottie swap animation (mic → camera), 30-frame cap — spec §7.3. Not implemented
- [ ] Forbidden state: icon at 0.5 opacity — spec §7.3. Not implemented
- [ ] Slowmode: "M:SS" countdown display, cursor disabled — spec §7.3. Not implemented
- [ ] Stars-to-send pill chip: height 28px, star-count + icon, widens send button — spec §7.3. Not implemented
- [ ] Send menu (right-click/long-press): Silent, Schedule, WhenOnline, HQ, Spoiler, CaptionAbove/Below, Price; 150ms scale+fade popup animation — spec §7.2. Not implemented

### §7.5 Voice Record Bar

- [ ] Voice record bar replacing input during recording: red pulsing blob (main 23–37px, major 43–50px, minor 40–47px), timer (13px, 1 decimal), "Slide to cancel" (210px wide, margins 15/25), cancel button 100px — spec §7.4. Not implemented
- [ ] Hold-to-record: pointer-down arms timer, release before ~200ms cancels with tooltip — spec §7.4. Not implemented
- [ ] Drag-up-to-lock widget (75×133px, 150ms show/hide, 15° pull-rotate angle), hands-free mode, stop-square button 12px — spec §7.4. Not implemented
- [ ] Video-record round-message mode triggered when send is Type::Round — spec §7.4. Not implemented
- [ ] TTL "voice once" 2px ring on lock when armed — spec §7.4. Not implemented

### §7.6 Reply / Edit / Forward Bar (FieldHeader)

- [x] Reply bar: 2px colored left bar, sender name + text excerpt, close (×) button, 44px height — spec §7.1, DONE in chat_view.dart (_ReplyBar). Height is 44px (spec says 49px historyReplyHeight), missing thumbnail and navigation arrows
- [ ] Fix height to 49px (historyReplyHeight); add 32px thumbnail preview; add navigation arrows for stepping through replies — spec §7.1
- [ ] Bar icon 22×22 at point(7,7); cancel button 49×49 hit-area, ripple 40×40 at (4,4) — spec §7.1
- [x] Edit bar: pencil icon + "Editing" header + message preview + close button — spec §7.1, DONE in chat_view.dart (_EditBar). Height 44px (spec 49px), send button correctly switches to Save
- [ ] Edit bar: fix height to 49px; confirmation dialog on cancel — spec §7.1. No cancel confirmation implemented
- [ ] Forward bar: forwarding author name + message preview + hide-sender-name option + close — spec §7.1. Not implemented as distinct bar (forward uses dialog instead)
- [ ] Web preview bar: link preview with title + description — spec §7.1. Not implemented

### §7.7 Bot Keyboard

- [ ] Reply keyboard sticky below field: 38px row height (textTop 9, margin 10, padding 10), tiny variant 25px, 15px semibold, 200ms expand/collapse, single-use auto-hide — spec §7.5. Not implemented
- [ ] Inline keyboard under messages: 36px height, 2px margin, 10px padding, URL/switchPM/payment/webview/copy icons with 4px padding — spec §7.5. Not implemented

### §7.8 Drag & Drop

- [ ] File drag overlay: rounded card (not full-screen wash) with boxBg fill + boxRoundShadow, two cards (document top / photo bottom), five DragState modes, 72px area height, 27px/19px semibold fonts, windowSubTextFg resting / windowActiveTextFg hovered, opacity 0→1 animation — spec §7.6. Not implemented

### §7.9 SendFilesBox

- [ ] SendFilesBox dialog: 308px preview, AlbumPreview thumbnail grid (up to 10 items), compress-images checkbox, group-as-album checkbox, caption field (max 158px), per-item right-click context menu (Replace/Edit/Rename/Caption/Spoiler/Cover) — spec §7.7. Not implemented (currently jumps straight to OS picker without preview/confirmation dialog)
- [ ] Send button: long-press opens send menu; paid peer overrides with price label — spec §7.7. Not implemented
- [ ] Spoiler per-item via context menu; bulk via top-right 3-dots menu — spec §7.7. Not implemented

### §7.10 Autocomplete

- [ ] @mentions, #hashtags, /commands autocomplete panel above compose — spec §7. Not implemented
- [ ] Inline bot results panel — spec §7. Not implemented
- [ ] Emoji suggestions while typing :emoji_name — spec §7. Not implemented

### §7.11 Additional Controls

- [ ] Send As selector (channel sender identity) — spec §7. Not implemented
- [ ] Silent Toggle button — spec §7. Not implemented
- [ ] Scheduled Messages button — spec §7. Not implemented
- [ ] TTL/disappearing message timer button — spec §7. Not implemented
- [ ] Characters-remaining counter near limit — spec §7. Not implemented
- [ ] Bot Command Start "/" button — spec §7. Not implemented
- [ ] Gift button (historyGiftToUser) when canSendGift — spec §7.2. Not implemented

### §7.12 Fallback Compose Buttons

- [ ] Unblock button: 46px height, textTop 14px, attentionButtonFg (red), semibold 13px — spec §7.1. Not implemented
- [ ] Start bot / Discuss / Report spam button: 46px height, textTop 14px — spec §7.1. Not implemented
- [ ] Contact status button: 49px height variant — spec §7.1. Not implemented
