# GUI Features Checklist: §23–§40

Consolidated from `checklist/gui.md`. Each item covers a full widget/feature unit. Read the
referenced spec section in `research/telegram_desktop_ui.md` before implementing — spec is the
source of truth.

Status key: `[ ]` not started · `[x]` done

---

## §23 — Scheduled Messages

<!-- dart files: none yet — create dart/lib/ui/scheduled_messages.dart -->

- [ ] ScheduledMessages data model: ID-space remapping, kScheduledUntilOnlineTimestamp magic, kMinimalSchedule/1-year bounds, SendMenu::Type enum, CanScheduleUntilOnline check, isSilent/allowsSendNow/allowsReschedule predicates — spec §23.1
- [ ] ChooseDateTimeBox dialog (GenericBox 364px): date field 136px + "at" label + time field 72px, CalendarBox overlay on date click, wheel-scroll date, time validation shake, "Send when online" button (ScheduledToUser only), repeat-period dropdown with Premium lock, silent Ctrl-modifier, RTL layout swap — spec §23.2
- [ ] Scheduled-clock toggle button in compose area (44×46px, two-layer icon, dynamic visibility by count, click triggers section) — spec §23.3
- [ ] ScheduledWidget full section: slide transition in/out, title "Scheduled messages"/"Reminders", top-bar menu (Create Poll / Create To-do List only), selection mode with Send Now + Delete, date separators, auto-scroll to new item, file drag-drop zones, no unread counter — spec §23.4
- [ ] Scheduled message rendering: scheduled-time timestamp, repeat-period prefix, silent muted-bell tooltip, multi-select support — spec §23.5
- [ ] Context menu: Send Now (single/group/selected), Send Now confirmation dialog, Reschedule (single up to §23.6 kRescheduleLimit=20), Delete, +1s offset per subsequent message in batch reschedule — spec §23.6
- [ ] sentToScheduled event auto-navigation and toast — spec §23.7
- [ ] Video processing toasts: stage-1 top-attached toast 4000ms, stage-2 ImportantTooltip bubble, published notification toast with thumbnail + "View" button — spec §23.8
- [ ] Section/dialog animation timings: 150–200ms slide, 4000ms toast/tooltip auto-hide, shake on time error — spec §23.10

---

## §24 — Keyboard Shortcuts

<!-- dart files: dart/lib/ui/chat_list_panel.dart, chat_view.dart, hamburger_drawer.dart (partial key handling already present) — new: dart/lib/ui/keyboard_shortcuts.dart -->

- [ ] Shortcut system: Command enum (70+ commands), reactive dispatch stream, priority-based handlers, auto-repeat for navigation commands, global pause/resume for Settings recording mode — spec §24.1
- [ ] Shortcut customization: write shortcuts-default.json on startup, load shortcuts-custom.json (max 2048 entries), null-command to disable, macOS ctrl/meta note — spec §24.2
- [ ] Platform modifier mapping: Ctrl vs Cmd, Alt vs Option; macOS display symbols (⌘⌃⌥⇧) — spec §24.3
- [ ] Application/window shortcuts: Ctrl+W/F4 close, Ctrl+L lock, Ctrl+M minimize, Ctrl+Q quit, Ctrl+F search — spec §24.4
- [ ] Chat navigation shortcuts: Ctrl+Tab switcher, Ctrl+PgDn/Up, Alt+Up/Down, Ctrl+Alt+Home/End, Ctrl+0 Saved/Ctrl+9 Archive/Ctrl+J Contacts — spec §24.4
- [ ] Pinned/folder shortcuts: Ctrl+1-8 (pinned chats or folders), Ctrl+Shift+Down/Up next/prev folder, folder priority over pinned — spec §24.4 + §24.12.2
- [ ] Chat action shortcuts: Ctrl+R mark-read/voice, Ctrl+\\ context menu, Ctrl+] preview popup — spec §24.4
- [ ] Media-key shortcuts: hardware play/pause/stop/prev/next, toggled with active player — spec §24.4
- [ ] Ctrl+Tab chat-switcher overlay: 72×104px cells, grid auto-layout, userpic+name, forum topic variant, Q removes from history, Tab/arrows navigate, Enter/release-Ctrl confirms — spec §24.5 + §24.12.3
- [ ] Compose box key handling: Enter/Shift+Enter/Ctrl+Enter modes, Escape cancel, Tab autocomplete, Up edit-last-message, Ctrl+Up/Down reply-nav, PageUp/Down scroll, Ctrl+O file-picker, Ctrl+Shift+V plain-paste, triple-Enter exits blockquote — spec §24.6
- [ ] History key handling: Escape cancel/back, PageDown/Up scroll, Up edit-last-editable, Ctrl+Up/Down skip-local reply-nav, Enter /start bot — spec §24.7
- [ ] Text formatting shortcuts: Ctrl+B/I/U, Ctrl+Shift+X/M/./P/N/K/D — spec §24.8
- [ ] Media viewer shortcuts: Left/Right prev/next, Esc, Ctrl+S save, H/V flip, K play/pause, J/L seek ±10s, Space speed-boost, period/comma frame-step, Alt+Left/Right chapters, Ctrl+scroll zoom, stories Space toggle — spec §24.9
- [ ] Support-mode shortcuts: F5 reload, Ctrl+Del toggle-muted, Ctrl+Shift+X/C history nav, support templates panel — spec §24.10
- [ ] Shortcut priority/scope system: global vs context-specific, InFocusChain/AppInFocus/isActiveWindow checks — spec §24.11
- [ ] Shortcuts settings UI: Chat Settings entry, command rows with right-aligned key label, green italic "Recording..." state, red strikethrough conflict, "Reset to defaults" SlideWrap button, right-click "Add another binding", 11 separator groups — spec §24.12

---

## §25 — Theming & Color System

<!-- dart files: dart/lib/theme/theme.dart (AppColors/AppTheme skeleton exists — needs full spec implementation) -->

- [ ] Full 370-token palette: implement all windowBg/Fg, button, dialog, message, peer-name (8 colors), file-type (4 groups × 4 states), voice waveform, media viewer, intro/login, scrollbar tokens — spec §25.1–25.2
- [ ] Four built-in themes: Classic Day, Day Blue, Night (Tinted), Night Green — with correct accent, outgoing bubble color, dark flag — spec §25.3
- [ ] Accent color picker: 8 preset circles per theme type, selection ring animation (~200ms), custom color button (7-circle widget), system-accent checkbox; HSV colorizer algorithm with day/night lightness clamps, 63-token exclusion list, keepContrast pairs — spec §25.4
- [ ] Theme file format: .tdesktop-theme ZIP (max 5MB), palette file (max 1MB), background image support, cloud-theme metadata markers — spec §25.5
- [ ] Theme editor: close/menu/search/list/save layout, palette-entry rows with swatch (shadow+checkerboard+solid), ripple+keyboard nav, hex color edit with live preview, Export/Import/Show menu items — spec §25.6
- [ ] SaveThemeBox: name + slug fields, background thumbnail + "Choose from file" + tile checkbox, JPEG 87% export — spec §25.6.5
- [ ] Theme name auto-generator: weighted Euclidean distance, "{Adj} {Color}" / "{Color} {Noun}" patterns — spec §25.7
- [ ] Wallpaper system: Image/Pattern/Gradient/Solid types, 1-4 background colors, pattern intensity ±100, gradient rotation 45° snap, blur flag, 2/3/4-color gradient rendering, pattern SoftLight/DestinationIn compositing, upload (JPEG 87%, 320px thumb), URL format with params — spec §25.8
- [ ] 6 adaptive service message colors from wallpaper average color; ThemeAdjustedColor hue+sat transplant — spec §25.8.9 + §25.17.5
- [ ] Night mode: dark detection by dialogsBg HSV < 0.5, hamburger toggle, auto-night from OS, 16s revert countdown overlay (easeIn/easeOut, boxDuration) — spec §25.9
- [ ] Theme caching: palette + background BMP + checksums, skip re-parse on checksum match — spec §25.10
- [ ] Per-chat themes: ChatThemeKey {id, dark}, bubble color from accent/bubblesData, contrast validation (min 1.14 ratio), 200ms background fade, horizontal scrollable theme-pill strip (miniature bg + sample bubbles + emoji), selection ring, Apply + Change Wallpaper buttons — spec §25.11
- [ ] Cloud themes: {id, accessHash, slug, title, emoticon} structure, 4-per-row grid with background preview + bubble indicators + radio, right-click Share/Edit/Delete, sharing link format — spec §25.12
- [ ] Theme preview image: dialogs panel + chat history with 9 sample rows and message bubbles — spec §25.13
- [ ] Chat Appearance settings: 4 theme radio buttons, background row with thumbnail + gallery/file pickers, tile checkbox, adaptive-wide checkbox, auto-night checkbox, font-family picker — spec §25.14
- [ ] AyuGram-specific: bubble-radius slider (0-16), tail removal toggle, Material switches toggle, avatar-corner-radius slider, disable-backgrounds toggle, simple-quotes toggle, semi-transparent-deleted toggle, Android-style palette extraction, drawer theme-toggle visibility — spec §25.15

---

## §26 — Admin Tools

<!-- dart files: none yet — create dart/lib/ui/admin_tools.dart -->

- [ ] EditPeerInfoBox: scrollable dialog with photo (UserpicButton, context menu Set/Set Video/Remove), title field (128 chars), description field (255 chars), settings rows with right-side value labels (Group/Channel Type, Discussion/Linked, Direct Messages, History, Topics, Auto-Translation, Sign Messages, Sign with Profile), control buttons (Permissions, Invite Links, Admins, Members, Removed, Join Requests), sticker section, delete button (red, confirmation), Save + Cancel — spec §26.1
- [ ] Permissions management: toggle rows with lock icon, group-media collapsible section (7 toggles, expand/collapse 150ms animation), slowmode 8-position slider, boosts-unrestrict 5-position slider, Charge Stars section, dependency rules (EmbedLinks requires SendOther, etc.), exceptions list with custom restrictions, locked-permission 3000ms toast, Convert-to-Supergroup suggestion at 1000+ members — spec §26.2
- [ ] Member restrict/ban dialog: cover 60×60px + name/status, per-user permission toggles, duration picker (Forever/1d/7d/Custom, max 366 days), custom rank field — spec §26.3
- [ ] Admin appointment dialog: "Add as Admin" checkbox with collapsible rights SlideWrap, admin rights sections (Group: 3, Channel: 4), custom title field, Transfer Ownership flow (dry-run → 2FA → confirm → toast), Dismiss Admin button, "Promoted by" link — spec §26.4
- [ ] Admin log / recent actions: top bar with search toggle, "What is this?" FAQ link, events as service messages (51 event types), quoted bubbles, empty state centered text, floating date badge with 1000ms inactivity fade, 20/50 pagination, filter dialog (3 sections, 19 flags, per-admin filter) — spec §26.5
- [ ] Invite links box: permanent link + "Create New Link" + active list + revoked list + "Delete All" + other-admins section; link rows with color-coded progress-arc badge (6 states), context menu (Copy/Share/QR/Edit/Revoke/Delete), single-link info box with joined-users list, QR Code dialog; create/edit form (label, expiry, usage, approval toggle, subscription credits) — spec §26.6
- [ ] Member list with 5 role tabs (Members/Admins/Restricted/Kicked/Profile): search bar with debounced server query, 16/200 pagination with online sort, row 56px with avatar/name/badge/rank, Add button per role, context menu (View/Edit Tag/Promote/Restrict/Remove/Promoted-by), banned-users sublist with Unban — spec §26.7–26.8
- [ ] Slowmode send-button countdown: "m:ss" text replacing icon, 1s updates, exempt for admins/bots — spec §26.9
- [ ] Anti-spam toggle: requires megagroup ≥ appConfig minimum (default 100), creator/admin visibility, below-threshold divider text — spec §26.10

---

## §27 — Passcode Lock Screen

<!-- dart files: none yet — create dart/lib/ui/passcode_screen.dart -->

- [ ] Settings entry point: Privacy & Security row with reactive "On"/"Off" label, navigate to Check (with passcode) or Create (without) — spec §27.1
- [ ] Passcode create flow: Lottie "local_passcode_enter" 100px, two PasswordInput fields 256px, validation (empty + mismatch), error label auto-hides on typing — spec §27.2
- [ ] Passcode check flow: single PasswordInput, flood protection passcodeCanTry(), wrong/correct passcode handling — spec §27.3
- [ ] Passcode management page: Change Passcode + Auto-Lock + System Unlock toggle (platform labels) + Disable Passcode (confirmation) — spec §27.4
- [ ] Passcode change flow: same as create + "same as current" validation, 10-min idle timer — spec §27.5
- [ ] Auto-lock timer dialog: 320px box, 5 radio options (1m/5m/1h/5h/Custom), Custom radio + TimeInput HH:MM 52px, max 23:59, 0:00 = error — spec §27.6
- [ ] Legacy PasscodeBox modal: stacked fields old/new/reenter/hint/email, dynamic title, confirmation toasts — spec §27.7
- [ ] Lock screen full-window overlay: header text, 225px input, 225px submit button, logout link, error text, system-unlock button with platform icon, "Unlock later" label, 1000ms cooldown — spec §27.8
- [ ] Lock/unlock transition: easeOutCirc in / easeInCirc out, pixmap capture crossfade, ~150-200ms — spec §27.9
- [ ] Brute-force protection: border-error animation 150ms, select+focus on error, bad-tries counter + timestamp, error clears on typing — spec §27.10
- [ ] Auto-lock timer logic: checkAutoLock(), 3000ms late-timeout grace, Ctrl+L shortcut, lockByPasscode iterates windows — spec §27.11–27.12
- [ ] Notification behavior when locked: generic "New message" text, click brings window + focuses passcode, no navigation to chat — spec §27.13
- [ ] System unlock support: capability query (available/withBiometrics/withCompanion), platform UI label resolution, SlideWrap hide when unavailable at runtime, Linux = no biometrics — spec §27.14
- [ ] Multi-account lock: single global lock, one passcode hash, unlock all windows simultaneously, force-close media viewer/web views, auto-clear passcode when zero accounts — spec §27.15

---

## §28 — Two-Factor Authentication (2FA / Cloud Password)

<!-- dart files: dart/lib/ui/auth_screen.dart (partial login-time check), new: dart/lib/ui/two_factor_auth.dart -->

- [ ] Settings entry point: "Two-Step Verification" row with Loading.../On/Off reactive label, poll every 60s, navigate to Start/InputCheck/EmailConfirm — spec §28.1
- [ ] AbstractStep architecture: common Lottie 100×100px header, 256px password/text fields, error ring 150ms, 61px phantom spacer, 300×42px done button, 60s idle auto-close, horizontal slide transitions — spec §28.2
- [ ] Create password flow: Start screen → Create (interactive lock Lottie) → Hint step → Email step (+ skip warning) → success navigate to Manage — spec §28.3
- [ ] Email confirmation step: SentCodeField (single field, not per-digit), auto-submit at expected length, resend link with green "Code resent", "Abort" top-bar menu item, recovery path, error handling (CODE_INVALID, EMAIL_HASH_EXPIRED, FLOOD_WAIT) — spec §28.3.5
- [ ] Check & Manage flow: single password field, "Hint: {hint}" label, 3-state forgot-password machine (Recover/CancelReset/Reset), Cancel Reset countdown timer, Manage screen with Change Password/Email/Disable buttons, deep-link highlight IDs — spec §28.4
- [ ] Change password flow (§28.5), change email only flow (§28.6), password recovery with email + without email (timed reset + countdown, min 60s display) — spec §28.5–28.7
- [ ] Login-time 2FA screen (PasswordCheckWidget): 380px content, fixed-position password field 300×61px, recovery code field, "Forgot password?" link, Reset Account button, SRP hash computation — spec §28.8
- [ ] Login email CodeInput (per-digit cells): 40×50px cells, 10px gaps, 4px border, fill/clear 120ms slide, shake error ~300ms, auto-submit on last digit, paste/copy context menu, IME digits-only hint — spec §28.9
- [ ] Fireworks + thumbs-up emoji completion screen on successful verification — spec §28.9–28.10
- [ ] All 9 error states mapped to user-facing strings: PASSWORD_HASH_INVALID, SRP_PASSWORD_CHANGED, SRP_ID_INVALID (silent retry), CODE_INVALID, EMAIL_INVALID, EMAIL_HASH_EXPIRED, EMAIL_NOT_ALLOWED, RECOVERY_NA/EXPIRED, FLOOD_WAIT — spec §28.12

---

## §29 — Chat Export

<!-- dart files: none yet — create dart/lib/ui/chat_export.dart -->

- [ ] Entry points: Settings > Advanced "Export Telegram Data" button, chat context menu "Export Chat History"/"Export Topic History", server-triggered SuggestBox (360px, OK/Cancel) — spec §29.1
- [ ] Export panel: 364×480px frameless SeparatePanel, dynamic title per mode, close-during-progress confirmation, hideOnDeactivate toggle — spec §29.2
- [ ] Full-export settings screen: account data checkboxes (Personal info/Contacts/Stories/Profile music), chats section (6 types + "Only my messages" sub-option with SlideWrap), media section (7 types + non-linear 1-4000MB size slider, default 8MB), other data section, output format radios (HTML/JSON/HTML+JSON) + clickable path link, Export/Cancel buttons with FadeShadow — spec §29.3
- [ ] Per-chat/topic settings screen: media options + format/location + date range filter (CalendarBox min Aug 2013, time editing HH:MM, 600s safety offset) — spec §29.4
- [ ] Progress screen: step rows 30px height (semibold label + windowSubTextFg info, proportional width), 3px progress bar (sineInOut 200ms, opacity crossfade), "Skip file" link after 5000ms, about label text, 200×44px Cancel button (attentionBoxButton), up to 3 visible rows — spec §29.5
- [ ] Stop confirmation dialog: "Are you sure?" / "Stop" red / "Cancel" — spec §29.6
- [ ] Completion screen: 3 done rows at progress=1.0, "Show My Data" 200×44px button opens folder, panel title reverts — spec §29.7
- [ ] Error states: TAKEOUT_INVALID InformBox (no escape/outside-click dismiss), TAKEOUT_INIT_DELAY with hours remaining, disk/IO error full-panel label (boxTextFgError, panelHeight/4 top), generic API error critical panel — spec §29.8
- [ ] In-app export top bar: ~36px, 3 labels + FilledSlider, animated slide down/up, click opens panel, lifecycle matches progress — spec §29.9
- [ ] Export settings persistence: 1000ms debounce save; persist types, fullChats, media types, size limit, format, path, availableAt — spec §29.10

---

## §30 — Bot Interactions

<!-- dart files: dart/lib/ui/chat_view.dart, message_bubble.dart, info_panel.dart (partial bot awareness) — new: dart/lib/ui/bot_panels.dart -->

- [ ] Bot command slash-button (44×46px, `historyComposeIconFg`) and bot menu button (30px height, auto-width 30-160px, 3-tier label fallback, appear/disappear 120ms width animation, cross-fade label) — spec §30.1
- [ ] Command autocomplete dropdown: trigger on `/`, 40px rows with userpic+semibold command+right-aligned description, max 4.5 rows visible, case-insensitive filter, `@botname` suffix in groups, 200ms opacity fade — spec §30.2
- [ ] Inline bot results panel: trigger on `@botname `, 345px panel 278-640px height, mosaic grid layout, photo/GIF 96px, sticker 64px, video/article/file cards, 350ms debounce query, 33ms repaint throttle, Switch PM button — spec §30.3
- [ ] Reply keyboard: full-width below compose, show/hide 200ms, SingleUse/ForceReply/Persistent/Resize flags, normal (38px) and tiny (25px) button styles, 4 color states (Normal/Primary/Danger/Success), corner rounding, 350ms tooltips — spec §30.4
- [ ] Inline keyboard buttons: margin 2px, height 36px, all button types (Default/Url/Callback/RequestPhone/RequestLocation/SwitchInline/Game/Buy/Auth/WebView/CopyText etc.), type icons at bottom-right, hover 200ms animation, loading radial on callbacks, fast-buttons numbered badges — spec §30.5
- [ ] Web/Mini Apps: SeparatePanel 384×694px, header (bot name + close + back + settings), bottom bar, main button (40px, visible/hidden/active/inactive/progress states, custom colors), secondary button (4 positions), progress indicator 200ms fade, menu popup maxHeight 360px, theme integration, loading state machine, confirmation dialogs — spec §30.6
- [ ] Bot start screen: empty-state painter with 280×140px bot image (gradient bg), intro area 224px, sticker 96px, service-message style bubble, "START"/"RESTART" full-width button, right-click clears token — spec §30.7
- [ ] Game message card: title (2-line max) + description + media + "GAME" badge + Play button (36px, 1px separator, hover/press/loading states, 15s load timeout), score service messages — spec §30.8
- [ ] Login URL auth confirmation dialog: bot userpic 64px, domain title, "(unverified)" prefix, device/location rows, two conditional checkboxes with dependency, phone-sharing sub-dialog, match-codes 4 emoji 48×48px, slide-up 200ms, success toast — spec §30.9
- [ ] Bot payments panel (392×600px): invoice cover (80×80px thumb), title/description/seller, price rows, tips buttons (flex-row wrap, 10%/80% alpha states), 6 section buttons, shipping picker + form, ToS gate, receipt mode, loading overlay 400ms fade — spec §30.10
- [ ] Business bot bar in chat header: pause/resume toggle + manage/remove options — spec §30.11

---

## §31 — Saved Messages

<!-- dart files: dart/lib/ui/chat_list_panel.dart, chat_list_row.dart, hamburger_drawer.dart (partial saved-messages reference) — new: dart/lib/ui/saved_messages.dart -->

- [ ] Saved Messages chat list entry: bookmark-icon avatar (vertical gradient #5caffa→#408acf, vector bookmark shape with V-notch), "Saved Messages" name, hamburger menu entry — spec §31.1
- [ ] Sublist navigation: switch dialog list to saved sublists, sublist rows with peer userpic/message-preview/unread badges, top bar loading→"My Notes"/peer name, info panel with "N chats" subtitle + media-filter 8-type buttons — spec §31.2–31.3
- [ ] My Notes sublist: self peer, notepad icon avatar (same gradient), "My Notes" display name everywhere — spec §31.4
- [ ] Sublist loading: auto-load below 20 sublists, first 10 / subsequent 50, pinned sublists separate, 6-entry recent list — spec §31.5
- [ ] Reaction tags system: tag data (ReactionId + custom title + count), Unicode emoji and custom animated emoji, refresh/increment/decrement/rename operations — spec §31.6
- [ ] SearchTags strip: price-tag-shaped chips (18px height, 5/2/7/2 padding, 6px left radius, 3px right radius, 5px arrow tail), selected/normal/promo states, Shift-click multi-select, right-click context menu (Edit tag name/Filter/Remove), promo chip with "Unlock Tags" for non-premium — spec §31.7a
- [ ] EditTagNameBox: 320px box, emoji preview in field, 12-char limit with "N/12" counter turning red, Save/Cancel, shake error — spec §31.7b
- [ ] Forward-to-saved tag suggestion toast: emoji selector, 3s auto-dismiss, 2s on mouse-leave, hover pauses — spec §31.8
- [ ] Subsection tabs strip: 36px horizontal (or 64px vertical) with toggle button, per-tab label + badge, active indicator animation 150ms, hidden scrollbar, wheel-Y→scroll-X, scroll-to-active, drag-reorder for pinned sublists, right-click dialogs sidebar context menu — spec §31.9
- [ ] Tagged dialog rows: height 72px (96px forum), tag pills row at 52px/77px, 10px font, pre-rendered QImage cache — spec §31.10

---

## §32 — Stories

<!-- dart files: dart/lib/ui/chat_list_row.dart (partial story ring) — new: dart/lib/ui/stories.dart -->

- [ ] Stories bar (chat list): collapsed (35px, 21px avatar, 16px shift, unread ring 1.5px, max 3 thumbs) + expanded (77px, 42px avatar, name 11px below), expansion/collapse triggers (0.72/0.68 overscroll ratio), gradient ring (#0dcc39→#0992ef), segmented arcs for multiple stories, tooltip up to 3 names — spec §32.1
- [ ] Story viewer overlay: 540×960px max, 8px corner radius, header inside/outside based on space, sibling previews (blurred, width ratio 0.448, 0.5 opacity), progress bar (2px, 4px gaps), photo 5000ms / video from player, left-third-prev / right-two-thirds-next tap navigation, fade on interaction (0.6 opacity), preloading (3 peers, 5 stories, 10 concurrent) — spec §32.2
- [ ] Story header: margin (12,4,12,8), avatar 28px, name/date labels, counter "3/7", privacy badges (Close Friends green star / Contacts / Selected / Public=none), timestamp formatting, play/pause + volume buttons — spec §32.3
- [ ] Story reactions panel: 210/420px expandable, like button 42×42px, reaction bubble with two tail circles, scale-out 1000ms, weather areas with temp — spec §32.4
- [ ] Story reply compose: dark #2c333d background, radius 21px, attachment button, field heightMin 36px/heightMax 72px, all buttons 42×42px, comments controls with unread dot — spec §32.5
- [ ] Story caption: collapsed FlatLabel, tap-to-expand fadeWrap + sineInOut, pull-to-close 50px threshold, content fade to 0.6 — spec §32.6
- [ ] Story repost view: simple (10px radius, 8px padding) and quote (messageQuoteStyle) variants — spec §32.7
- [ ] Story stealth mode dialog: logo icon, feature icons, button states (Non-premium UNLOCK / Cooldown H:MM:SS / Ready ENABLE), 250ms countdown, 4000ms toasts — spec §32.10
- [ ] Profile stories grid: SubTabs (All/album/Add), responsive column grid (82px min), 2px item skip, album drag-reorder — spec §32.12
- [ ] Story interactive areas: Location/SuggestedReaction/ChannelPost/UrlArea/WeatherArea with normalized coordinates + rotation transforms — spec §32.13
- [ ] Story creation editor: 9:16 canvas (540×960px, 8px radius, zoom 1.0-8.0), two 48px button bars, video trim slider (12 thumbnail frames, 8×48px handles, 1-60s), sticker placement with drag/scale/rotate (0.2-6.0), text tool (align/bg-style/font-picker/10 swatches+HSL), drawing tool (5 brushes, vertical 280px size slider), caption bar reusing compose controls, privacy selector (32px chip row), duration picker (6h/12h/24h/48h), save-to-profile + allow-sharing toggles, post button (36px accent circle, upload progress ring, 150ms checkmark crossfade) — spec §32.15

---

## §33 — Contacts Screen

<!-- dart files: dart/lib/ui/hamburger_drawer.dart, chat_list_panel.dart (partial contact references) — new: dart/lib/ui/contacts_screen.dart -->

- [ ] Contacts box shell: boxWideWidth (364px), title "Contacts", close/add-contact buttons, sort toggle (online↔alphabetical, instant icon swap, 48×54px hit area) — spec §33.1
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
