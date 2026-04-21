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
