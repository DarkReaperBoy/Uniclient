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
- [ ] Complete overflow menu actions: Add Account (hidden at max 10 Premium / 3 free), Edit Profile navigates to My Account section, Log Out shows `lng_sure_logout` confirmation dialog with red attentionBoxButton — spec §14.1

### 14.2 Profile Header / Cover — PARTIAL
- [x] Profile header skeleton: 88px circular avatar at (22px left, 8px top), name (17px semibold), phone, username (@) — spec §14.2 — DONE in `settings_screen.dart`
- [ ] Full profile header spec compliance: exact cover height 112px (8+88+16), avatar hover overlay with camera icon, avatar upload menu (file / emoji / stickers), circular upload progress, User ID row, username as tappable link (copies t.me/link or opens UsernamesBox), QR Code button (right-aligned, only with username), Premium badge inline after name clicking emoji status panel, name max-width recomputed on resize — spec §14.2

### 14.3 Navigation Buttons List — PARTIAL
- [x] Core settings rows present: My Account, Notifications, Privacy, Chat Settings, Folders, Advanced, Devices, Language with icon+rounded-square bg, ripple on tap — spec §14.3 — DONE in `settings_screen.dart`
- [ ] Full nav button spec: exact 41px row height (10+21+10), 60px left padding / 20px icon / 6px radius icon-bg (settingsIconRadius) / 22px right padding / no inter-row separators / grouping via skip+divider pairs, all 10 buttons in correct order including AyuGram Preferences (item 1), Power Saving (item 9 — opens dialog not subsection), Language right-label shows current language name — spec §14.3 & §14.3.1

### 14.4 Interface Scale — PARTIAL
- [x] "Default interface scale" toggle stub — DONE in `settings_screen.dart`
- [ ] Full interface scale: "Use Default Scale" toggle, scale slider (15x15 thumb, 5-step discrete, 100%–300% range), right-side percentage label in windowActiveTextFg, floating ScalePreview tooltip during drag, scale applied on pointer-release not real-time, restart confirmation dialog on change, SlideWrap collapses slider when "Use Default" ON — spec §14.4 & §14.4.1

### 14.5 My Account / Edit Profile Sub-Page
- [ ] Edit Profile screen: "Edit Profile" title, vertically scrolling panel — spec §14.5
- [ ] Profile photo area: 162px height (settingsInfoPhotoHeight), 100x100px UserpicButton centered, upload sub-button overlay (bottom-right), name (17px semibold, 24px max height, centered below photo), online status below name — spec §14.5.1
- [ ] Bio input: transparent multiline InputField, margins 22/6/22/4px, 32px min height, character counter (grey ≥0 / red <0), 70-char limit (140 Premium), debounced 1000ms auto-save, emoji suggestions, "Any details…" footer — spec §14.5.2
- [ ] Profile info rows: Name / Phone / Username rows with icon in 6px rounded square, primary value (14px) + secondary label (windowSubTextFg), right-click copy menus, no trailing chevron — spec §14.5.3 & §14.5.3.1
- [ ] Personal Channel & Your Color rows: Channel row with channel name or "Add", AddPeerColorButton showing name color swatch, opens EditPeerColorBox — spec §14.5.4
- [ ] Birthday row: date picker, dynamic footer with "[Manage]" link to privacy — spec §14.5.5
- [ ] Accounts list: all logged-in accounts as rows with avatar+name+badge, drag-to-reorder, right-click menu (Copy Phone / Mark All Read / Activate / Log Out), Add Account button (hidden at limit), premium limit enforcement, active-account ring on userpic — spec §14.5.6 & §14.5.6.1

### 14.6 Chat Settings Sub-Page
- [ ] Chat Settings screen: "Chat Settings" title, "Create New Theme" in top-bar overflow — spec §14.6
- [ ] Theme picker: horizontal row of 4 cards (80x92px, settingsThemePreviewSize), each with mini chat bubbles (40x14px, 2px radius), radio dot (12px bottom inset), accent color palette row of 24px dots, custom HSL color picker as rightmost dot, "Use system accent color" checkbox — spec §14.6.1 & §14.6.1.1
- [ ] Theme settings group: Your Color preview (opens EditPeerColorBox), Auto-Night Mode toggle, Font Family button with ChooseFontBox — spec §14.6.2
- [ ] Cloud themes: horizontal scrollable SlideWrap list, "Show All" toggle, "Edit Current Theme" when user-owned, edit launches theme editor — spec §14.6.3 & §14.6.3.1
- [ ] Chat background: 76px thumbnail with rounded corners, "Choose from gallery" link, "Choose from file" link, "Tile Background" checkbox, "Adaptive Layout" checkbox (wide mode only) — spec §14.6.4
- [ ] Chat list quick action: radio group (Mute/Pin/Read/Archive/Delete/Disabled) with live Lottie preview — spec §14.6.5
- [ ] Stickers & Emoji: five checkboxes (Large Emoji, Replace Emojis, Suggest Emoji, Suggest Stickers, Loop Animated), Suggest Animated Emoji (Premium nested), Your Stickers + Emoji Sets buttons, margins(22,10,10,10) — spec §14.6.6 & §14.6.6.1
- [ ] Messages group: Send by radio (Enter/Ctrl+Enter), Double-click radio (Reply/React with reaction preview), Show reply button checkbox, Show reaction button checkbox, correct subsection titles and dividers — spec §14.6.7 & §14.6.7.1
- [ ] Sensitive content toggle: "Disable filtering" with footer, hidden if server disallows — spec §14.6.8
- [ ] Shortcuts & Archive: Keyboard Shortcuts nav button, Archive Settings button (opens ArchiveSettingsBox) — spec §14.6.9

### 14.7 Advanced Sub-Page
- [ ] Advanced section build order: Update (top when non-auto), Data+Storage, Auto-Download, Window Title, Window Close (Linux), System Integration, Performance, Spellchecker, Screen Reader, Update (bottom when auto), Export — skip+divider+skip between each, conditional SlideWraps — spec §14.7.0
- [ ] Data and Storage: Connection Type button (with proxy right-label), Download Path button, Local Storage button, Downloads button, "Ask download path" toggle — spec §14.7.1
- [ ] Auto Media Download: three buttons (Private/Groups/Channels) each opening AutoDownloadBox — spec §14.7.2
- [ ] Window Title: "Show chat name" / "Show account name" (SlideWrap multi-account) / "Show unread count" checkboxes, native frame toggle (platform-gated) — spec §14.7.3
- [ ] Window Close Behavior (Linux only): three radio options (Run in Background / Close to Taskbar / Quit) — spec §14.7.4
- [ ] System Integration: tray icon / taskbar icon / monochrome tray (SlideWrap) / launch at startup / start minimized (nested SlideWrap) / Add to Send To (Windows) checkboxes — spec §14.7.5
- [ ] Performance: Power Saving button (opens PowerSavingBox), hardware-accelerated video toggle (SlideWrap/platform), OpenGL/ANGLE toggle (restart dialog) — spec §14.7.6
- [ ] Spellchecker: system/custom toggle, auto-download dictionaries toggle, Manage Dictionaries button with count — spec §14.7.7
- [ ] Software Update: auto-update toggle with version/progress label, Install beta toggle, Check for Updates / "Update Telegram" button — spec §14.7.8

### 14.8 Premium & Help Sections
- [ ] Premium group: Telegram Premium (gradient button), Telegram Stars (live balance), TON Currency (hidden when empty), Telegram Business, Send a Gift (newBadge) — spec §14.8.1
- [ ] Help group: Telegram FAQ / Features / Ask a Question rows in settingsButton style (60px icon column), about-label at 59px left inset — spec §14.8.2

### 14.9 Visual Style Constants
- [ ] All settingsButton style constants applied throughout settings: padding 60/10/22/10, iconLeft 20px, settingsButtonNoIcon padding 22/10/22/8, all size tokens (see full list) — spec §14.9

### 14.10 Animations & Transitions
- [ ] Section navigation: horizontal slide + fade right, toggle switches as sliding pills, color dot selection ring animation (defaultRadio.duration × 2), scale preview tooltip, drag-reorder spring physics, all SlideWraps with smooth height animation, ripple on all SettingsButton instances — spec §14.10

---

## §15 — Settings: Notifications

<!-- dart/lib/ui/settings_screen.dart (nav row only); sub-page not yet created -->

### 15.1 Multi-Account Notifications
- [ ] Notifications sub-page: conditional "Show notifications from" section (2+ accounts), "All accounts" toggle (settingsButtonNoIcon), divider explanation — spec §15.1

### 15.2 Global Settings + Volume Slider
- [ ] "Global settings" section: Desktop notifications toggle, platform-specific flash/bounce toggle (label varies by OS), "Allow sound" toggle — all settingsButton with 60px left padding — spec §15.2
- [ ] Master volume slider in SlideWrap (visible when sound ON): "Volume" subtitle, horizontal MediaSlider with 15x15 thumb, 100 steps (1–100), live percentage label, plays preview on drag, 150ms slide animation — spec §15.2.1

### 15.3 Notification Preview Widget
- [ ] Preview bubble in SlideWrap (shown when desktop notifications ON): chat-themed rect on wallpaper, 36x36px userpic, title + text, two pill-style checkboxes ("Name" / "Text") centered horizontally with unchecking/dependency logic, three preview states (ShowPreview/ShowName/ShowNothing) — spec §15.3

### 15.4 Per-Type Notification Rows
- [ ] "Notifications for chats" section: four 40px split-toggle rows (Private/Groups/Channels/Reactions), left area clickable (icon+label+status subtitle), right 70px toggle area, 1px vertical separator between them, confirmation dialog when toggling with exceptions — spec §15.4 & §15.4.1

### 15.5 Per-Type Sub-Page
- [ ] Per-type sub-page: "Enable notifications" toggle (right-click opens Mute Menu), "Sound" toggle (SlideWrap), "Notification tone" row (nested SlideWrap, right-label = current tone name, opens Ringtones Box), per-type volume slider (SlideWrap, plays selected tone) — spec §15.5.1 & §15.5.1.1 & §15.5.1.2
- [ ] Exceptions list: "Add an exception" button, exception rows (userpic+name+status+"Remove"), "Delete all exceptions" red button with confirmation — spec §15.5.2
- [ ] Mute Menu: PopupMenu with popupMenuWithIcons style — Select tone, Disable/Enable sound, recent mute durations, Mute for…, Mute forever/Unmute with red/green animation, drum-picker duration wheel (15min–1mo, Custom option) — spec §15.5.3

### 15.6 Ringtones Box
- [ ] GenericBox 364px "Notification Sound": "Default" + "No sound" radios, custom tones list (play on select, right-click Delete), "Upload Sound" button (mp3, max 100KB/5s/100 tones), in-box volume slider (hidden for No sound), footer text, Save + Cancel buttons — spec §15.6 & §15.6.1

### 15.7 Reactions Sub-Page
- [ ] "Notifications for reactions" sub-page: two split-toggle rows (Reactions to my messages / Votes in my polls), left click (when enabled) opens Everyone/My Contacts radio dialog, "Show sender's name" toggle — spec §15.7

### 15.8–15.10 Events, Calls, Badge Counter
- [ ] Events section: "Contact joined Telegram" toggle (menuIconInvite), "Pinned messages" toggle (menuIconPin) — spec §15.8
- [ ] Calls section: "Accept calls on this device" toggle (menuIconCallsReceive) — spec §15.9
- [ ] Badge Counter section: three settingsButtonNoIcon toggles (include muted / include muted in folders / count messages vs chats) — spec §15.10

### 15.11 System Integration (Native Notifications)
- [ ] Native notifications toggle (hidden if platform unsupported); Windows Focus Mode toggle; multi-display radio selector (shown when multiple monitors) — spec §15.11 & §15.11.1 & §15.11.2
- [ ] Interactive monitor widget (280×160px): five clickable corners, 64×16px sample notification bars at selected corner (full opacity) and others (0.5 opacity), 150ms per-bar fade, 3×3 hit-test grid, hover spawns real sample notification windows at screen coordinates — spec §15.11.3 & §15.11.3.1
- [ ] Notification count segmented slider: 5 positions (1–5), default 3, selecting animates monitor widget bars — spec §15.11.4

### 15.12 Animations
- [ ] All Notifications page animations: SlideWrap ~300ms, toggle pills, sample bar 150ms fade, mute menu color transition — spec §15.12

---

## §16 — Settings: Privacy & Security

<!-- dart/lib/ui/settings_screen.dart (nav row only); sub-page not yet created -->

### 16.1 Privacy & Security Page
- [ ] Privacy & Security scrollable page: settingsButton nav row (menuIconLock), 60s polling timer, seven subsections in order — spec §16.1

### 16.2 Security Section
- [ ] Two-Step Verification button (menuIcon2SV): right-label Loading/On/Off, On→CloudPasswordInput (Lottie 100×100, password field, hint, "Forgot?" link, reset countdown), Off→CloudPasswordStart (Lottie intro, Set Password button), full create flow (two fields, hint step, email step), unconfirmed→email confirmation screen — spec §16.2.1 & §16.2.1.1
- [ ] Auto-Delete Messages button (menuIconTTL): right-label = TTL or "Off", GlobalTTL section with Lottie 100×100 in BoxContentDivider, radio buttons (Off/1d/7d/31d + custom sorted), confirmation dialog on enable, "Set Custom Period" button, footer with apply-to-existing link — spec §16.2.2
- [ ] Passcode Lock button (menuIconLock): On/Off right-label, no passcode→LocalPasscodeCreate (Lottie, two 256px fields, mismatch error), set→LocalPasscodeCheck (single field, Next), LocalPasscodeManage (Change Passcode, Auto-Lock with AutoLockBox radios+HH:MM input, System Unlock toggle, Turn Off red button with confirmation) — spec §16.2.3
- [ ] Passkeys button (menuIconPermissions): shown only if platform supports WebAuthn or user has passkeys, right-label = passkey name/count/Off — spec §16.2.4
- [ ] Login Email button (menuIconRecoveryEmail): shown only if login email configured, right-label = masked email — spec §16.2.5
- [ ] Blocked Users button (menuIconBlock): right-label = count or "None" — spec §16.2.6
- [ ] Active Sessions button (menuIconDevices): right-label = session count — spec §16.2.7

### 16.3 Privacy Section
- [ ] Privacy section: settingsButtonNoIcon rows for each privacy setting, right-label = base value + exception counts, EditPrivacyBox (364px) with radio options (Everyone/My Contacts/Close Friends/Nobody), Premium-locked options with 14px lock, "Always Allow"/"Never Allow" exception buttons, PeerListBox for exceptions, Premium Users toggle, Save+Cancel — spec §16.3 & §16.3.0
- [ ] Phone Number Privacy: Everyone/My Contacts/Nobody, "Nobody"→"Who can find me" sub-section (Everyone/Contacts), phone-link warning — spec §16.3.1
- [ ] Last Seen & Online: first-time confirmation dialog, "Hide Read Time" toggle (non-Everyone only), non-Premium Premium button — spec §16.3.2
- [ ] Profile Photo: Set/Update Public Photo button (ellipse crop), Remove Public Photo (red, when exists) — spec §16.3.3
- [ ] Forwarded Messages: live forwarded message preview bubble matching user theme, "Forwarded from" header with user's name, tooltip (toastBg/toastFg with 7px arrow) changes per option — spec §16.3.4 & §16.3.4.1
- [ ] Calls Privacy: P2P sub-section (menuIconNetwork) opens second EditPrivacyBox — spec §16.3.5
- [ ] Voice Messages: Premium-locked options revert to Everyone with promo toast for non-Premium — spec §16.3.6
- [ ] Messages from Non-Contacts: three radios (Everyone/Contacts+Premium/Charge Stars), Charge Stars reveals star price slider (step scheme: 1/10/100), star preview label, commission/USD info updates live — spec §16.3.7 & §16.3.7.1
- [ ] Birthday Privacy: "set your birthday" link if unset — spec §16.3.8
- [ ] Gifts (Auto-Save): "Show Icon" Premium-locked toggle, "Accepted Types" subsection with five Premium-locked toggles (Limited/Unlimited/Unique/From Channels/Premium) — spec §16.3.9 & §16.3.9.1
- [ ] Bio / Saved Music / Groups & Channels: standard privacy boxes, Groups+Channels has Premiums toggle in Always Allow — spec §16.3.10–12

### 16.4 Archive and Mute
- [ ] Conditional (Premium or showArchiveAndMute): "Archive and Mute" toggle — spec §16.4

### 16.5 Bots and Websites
- [ ] "Clear Payment and Shipping Info" button, ClearPaymentInfoBox (two default-checked checkboxes, red "Clear" button disabled when both unchecked) — spec §16.5 & §16.5.1

### 16.6–16.8 File Confirmations, Frequent Contacts, Self-Destruction
- [ ] File Confirmations section (conditional): multi-line extensions input (max 10240 chars / 1024 entries), "Show IP in WebRTC calls" toggle — spec §16.6 & §16.6.1
- [ ] "Suggest Frequent Contacts" toggle — spec §16.7
- [ ] "If away for…" button, SelfDestructionBox (radios 1/3/6/12/18/24 months, info label, Save+Cancel) — spec §16.8 & §16.8.1

### 16.9 Blocked Users Screen
- [ ] "Block User" top button (opens peer picker, already-blocked disabled), blocked peer list (photo+name+status+"Unblock" link), empty state (Lottie, title, desc, 240px min height) — spec §16.9

### 16.11 Animations
- [ ] All Privacy page animations: SlideWrap conditional sections, Lottie icons (cloud password intro/input, local passcode, TTL, blocked users empty), password input icon animates/reverses on typing, fireworks on password validation success — spec §16.11

---

## §17 — Settings: Data, Storage & Advanced

<!-- dart/lib/ui/settings_screen.dart (nav row only); sub-page not yet created -->

### 17.1 Advanced Page Structure
- [ ] "Advanced" (Data and Storage) sub-page with subsections in spec order, each separated by skip+divider+skip, SlideWraps for conditional sections — spec §17.1

### 17.2 Data and Storage
- [ ] Connection Type button (menuIconNetwork): dynamic right-label (TCP/Connecting/proxy), ProxiesBox (364px) with IPv6 toggle, radio group (Disabled/System/Custom), proxy-for-calls SlideWrap, share-list button, import/delete top-right menu, Add button, ProxyRow (radio + title semibold + status colors: Online/Available/Checking/Unavailable), context menu (Edit/Share/QR/Delete), keyboard Ctrl+C/V — spec §17.2.1 & §17.2.1.2–4
- [ ] Edit Proxy Dialog: 364px, type radio, host(160px)+port(55px), credentials, smart paste "host:port", MTPROTO sponsor warning — spec §17.2.1
- [ ] Download Path button (menuIconShowInFolder): right-label = Default/Temp/custom, hidden when "Always ask" ON — spec §17.2.2
- [ ] LocalStorageBox (320px): summary row (50px, "All data" + size + "Clear All"), total cache slider (18 positions), media cache slider (18 positions, linked to total), time limit slider (16 positions), per-tag rows (Images/Stickers/Voice/Video/Animations/Media cache each with size + "Clear" button), OK button — spec §17.2.3 & §17.2.3.2
- [ ] Recent Downloads button (menuIconDownload), "Always ask download path" toggle (hides download path when ON) — spec §17.2.4–5

### 17.3 Automatic Media Download
- [ ] Three buttons (Private/Groups/Channels), AutoDownloadBox (boxWidth): Download section (Photos/Files toggles + size slider default 10MB), Auto-play section (Video messages/Videos/GIFs toggles + size slider default 50MB), "N MB" label — spec §17.3 & §17.3.1

### 17.4–17.6 Window Title, Close Behavior, System Integration
- [ ] Window Title: "Chat name" / "Account name" (SlideWrap, 2+ accounts) / "Total count" checkboxes (settingsCheckbox + settingsCheckboxPadding) — spec §17.4
- [ ] Window Close Behavior (Linux/BSD only): three radio options (Run in Background/Close to Taskbar/Quit), settingsSendType style, hidden when tray unavailable — spec §17.5
- [ ] System Integration: tray/taskbar interlocked checkboxes (at least one required), monochrome tray (slide-animated), launch at startup, start minimized (nested, forced off with passcode), Add to Send To (Windows), macOS-specific items, Windows native notifications toggle — spec §17.6 & §17.6.1–4

### 17.7 Performance
- [ ] PowerSavingBox (364px): 11 toggle flags in groups (Stickers: Panel+Chat; Emoji: Panel+Reactions+Chat+Status; Chat: Background+Spoiler+Effects; Calls; Interface Animations), category headers, powerSavingButton style, forced-disable overlay (boxBg alpha 96) with 3000ms toast — spec §17.7.1 & §17.7.1.1
- [ ] Hardware-accelerated video toggle (SlideWrap/platform), ANGLE Backend button (Windows, 5 options, restart dialog), OpenGL toggle (Linux/Windows, restart dialog) — spec §17.7.2–4

### 17.8–17.9 Spellchecker, Screen Reader
- [ ] Spellchecker: Enable toggle (system/custom label), auto-download dictionaries toggle (visible when custom ON), Manage Dictionaries button with count — spec §17.8
- [ ] Screen Reader: shown only when reader detected and mode disabled, "Disable screen reader mode" toggle — spec §17.9

### 17.10 Software Update
- [ ] Auto-update toggle (settingsUpdateToggle) with state label (current version / checking / downloading+progress / ready / latest / failed), "Install beta" toggle (hidden for alpha/during download), "Check for updates" button, "Update Telegram" install-ready overlay button, retry timer 10s — spec §17.10 & §17.10.1–3

### 17.11 Export & Experimental
- [ ] "Export Telegram Data" button (menuIconExport), "Experimental Settings" button (menuIconExperimental); Experimental box: top warning label, Reset button (only when flags changed), toggle rows, flags from registry, base64url import/export via clipboard (`tdesktop-flags:` prefix), error toasts — spec §17.11 & §17.11.1–3

---

## §18 — Settings: Folders

<!-- dart/lib/ui/settings_screen.dart (nav row only); dart/lib/ui/filter_column.dart (sidebar rendering) -->

### 18.1 Folders Page Structure
- [ ] Folders settings page: full scrollable section "Folders", request suggested filters on open, build header+folder list+recommended+tags toggle+view section, auto-save on destroy — spec §18.1

### 18.2 Animated Header
- [ ] BoxContentDivider header: Lottie `filters` 74×74px (padding 0/17/0/5, plays once), description label (settingsFilterDividerLabel, 13px regular, windowSubTextFg, min 200px, padding 0/16/0/22, balanced wrapping) — spec §18.2 & §18.2.1

### 18.3 Existing Folders List
- [ ] FilterRowButton rows (52px height, RippleButton): folder icon (activeButtonBg/Over), title (contactsNameStyle + custom emoji support), status "{N} chats" + shareable indicator, color dot (circle height/3 diameter, EmptyUserpic color, animated via _colorIndexProgress), Remove X button (filtersRemove style), Restore RoundButton (26px, full radius), row states (Normal/Removed/Suggested), windowBgOver hover (instant), defaultRippleAnimation, click→EditFilterBox, removal confirmation dialogs — spec §18.3 & §18.3.1

### 18.4 Create New Folder
- [ ] "Create New Folder" button (settingsButtonActive, settingsIconAdd): check folder limit (show FiltersLimitBox if reached), opens EditFilterBox — spec §18.4

### 18.5 Recommended Folders
- [ ] SlideWrap (visible when suggestions > 0 AND count < limit): divider + "Recommended folders" subtitle, each as FilterRowButton in Suggested state (no icon, title + server description, "Add" button 26px full radius) — spec §18.5

### 18.6 Edit Filter Box
- [ ] GenericBox 364px "New Folder"/"Edit Folder": closeByOutsideClick=false, Create/Save + Cancel buttons — spec §18.6
- [ ] Folder name input (windowFilterNameInput): right margin 87px, placeholder "Folder name", max 12 chars, custom emoji support, character counter at (75,27) from right, emoji button at (-65,22) opens TabbedPanel EmojiOnly, icon selector toggle (36×36px at -4/18), icon painted in dialogsUnreadBgMuted, click opens FilterIconPanel, auto-title on creating — spec §18.6.1
- [ ] Included Chats section: "Add Chats" button, FilterChatsPreview widget (44px rows, 34px photo at 13/5, name at 59/14, remove button), 5 type rows with gradient circle userpics (Contacts green/NonContacts cyan/Groups green/Channels red/Bots purple), footer text — spec §18.6.2 & §18.6.2.2
- [ ] Excluded Chats section (hidden when chatlist=true): "Remove Chats" button, same preview widget, 3 exclude types (Muted purple/Archived green/Read cyan), footer — spec §18.6.3
- [ ] Tag Color section (Premium-gated): "Tag Color" subtitle + inline tag preview badge, 8 circular 30px chips evenly spaced, colors 0–6 from palette, color 7 = "no tag" (X icon, historyPeerArchiveUserpicBg), selection ring with 120ms color crossfade, non-Premium→PremiumPreviewBox(FilterTags), footer — spec §18.6.4 & §18.6.4.1
- [ ] Shareable Link section: "Share Folder"/"Invite Links" title, Create/Add Link buttons, link rows (52px, green circle, name+status+three-dots), context menu (Copy/Share/QR/Name it/Delete), validation on create (no exclusions or rule flags) — spec §18.6.5 & §18.6.5.1
- [ ] Save validation: empty/overlong title → showError+scroll to top; no include types + no chats → toast; all types+NoArchived+no specific chats → toast — spec §18.6.6

### 18.7 Include/Exclude Picker
- [ ] PeerListBox with EditFilterChatsListController: "Include/Exclude Chats" title, closeByOutsideClick=false, "Chat types" subtitle (searchedBarBg, 28px), 44px type rows with gradient circle + checkbox, include types (NewChats/ExistingChats/Contacts/NonContacts/Groups/Channels/Bots), exclude types (NoMuted/NoRead/NoArchived), "{selected}/{limit}" counter — spec §18.7

### 18.8 Filter Icon Picker Panel
- [ ] 6×5 grid (44×42px cells), padding 10/36/10/8 (36px top for header), "Folder Icon" header at (18,14), 30 icons in spec order, normal/hover/active colors, panel bg (dialogsBg large rounded corners), hover highlight (StickerHoverCorners), PanelAnimation TopRight show, 300ms hide-after-leave, (-2,-1) anchor offset, click fires _chosen, auto-icon selection by filter types — spec §18.8 & §18.8.1

### 18.9 Show Link Box
- [ ] PeerListBox (inviteLinkChatList style): Lottie `cloud_filters` 74×74 header with bold folder name, InviteLinkLabel with URL + Copy + Share, chat list with select/deselect toggle, disabled rows (bots/private users/non-admin channels) with dashed circle overlay (1.5dp, 11 segments), Save/Cancel or Done buttons — spec §18.9

### 18.10 Chatlist Folder Removal Dialog
- [ ] PeerListBox (filterInviteBox, 42px buttons): channels from folder always-list, server-suggested peers pre-selected, action button with selected count badge — spec §18.10

### 18.11 Folder Tags Toggle
- [ ] "Show Folder Tags" settingsButtonNoIconLocked with toggle: non-Premium→PremiumPreviewBox(FilterTags), Premium→500ms debounce request, tag toggle drives 120ms color dot animations on all folder rows — spec §18.11

### 18.12 Tab View Section
- [ ] Visible only ≥452px width: two radios (Side panel / Top bar, settingsCheckbox margins 22/5/10/5), sidebar mode (72px wide, vertical tabs, long-press drag reorder), top-bar mode (horizontal strip, horizontal-scroll overflow), drag threshold ~10px, 150ms shift animation, auto-scroll factor 0.05 near edge, pinned interval for "All chats" tab — spec §18.12 & §18.12.1

### 18.13 Premium Limits
- [ ] Enforce folder limits (10 free/20 premium total; 100/200 chats per folder; 2/20 shareable; 3/20 links per folder), FiltersLimitBox / FilterChatsLimitBox / ShareableFiltersLimitBox / FilterLinksLimitBox each with animated infographic + Premium icon + description — spec §18.13

---

## §19 — Settings: Sessions, Power Saving & Language

<!-- dart/lib/ui/settings_screen.dart (nav rows only); sub-pages not yet created -->

### 19.1–19.4 Active Sessions Page
- [ ] Active Sessions page (menuIconDevices): auto-refresh 60s, loading spinner state, six conditional zones — spec §19.1
- [ ] Current session display: "This device" header with "Rename" link (defaultLinkButton), 84px row with 42px gradient-circle photo + platform icon, name (msgNameFont 13px semibold), status, location "{location} . {active_date}", no terminate button — spec §19.2 & §19.2.1–2
- [ ] Device type detection: classify by API ID then keyword, 13 types with gradient pairs (Windows/Mac/Other green, Ubuntu orange, Linux purple, iPhone/iPad cyan, Android red, Web/Chrome/Edge/Firefox/Safari pink), all icons white historyPeerUserpicFg — spec §19.3
- [ ] Other sessions list: "Active sessions" header (14px top skip), 84px rows, 34×34px terminate button (top 8px/right 11px), row click→SessionInfoBox, terminate→confirmation, footer divider text, no between-row hairlines — spec §19.4 & §19.4.1

### 19.5 Incomplete Login Attempts
- [ ] "Incomplete Login Attempts" section (conditional): same row style, newest first, footer explanation — spec §19.5

### 19.6 Session Detail View (SessionInfoBox)
- [ ] SessionInfoBox (364px): 70px userpic + 52px Lottie plays-once header, device name (20px semibold, max 29px), date (windowSubTextFg, full datetime), info rows (Application/System/IP/Location with icons), AyuGram "Official App" row, OK button, non-current session: red "Terminate Session" + confirmation — spec §19.6 & §19.6.1

### 19.7–19.9 Terminate All / Rename / Auto-Terminate
- [ ] "Terminate All Other Sessions" button (infoBlockButton, visible when >0), confirmation dialog with red Terminate button — spec §19.7
- [ ] Rename Device dialog: "Rename Device" title, settingsDeviceName input (transparent, 29px min height), placeholder = device model, max 32 chars, empty reverts to platform name, Save+Cancel — spec §19.8 & §19.8.1
- [ ] "If Inactive For" button (settingsButtonNoIcon): SelfDestructionBox(Sessions) with radios (1 week/1/3/6/12 months), description above, autolockButton style, Save+Cancel — spec §19.9 & §19.9.1

### 19.10–19.12 Power Saving Box
- [ ] Power Saving GenericBox (364px): 11 toggles in groups (Stickers: Panel+Messages; Emoji: Panel+Reactions+Messages+Status; Chat: Background+Spoiler+Effects; Calls; Interface Animations), powerSavingButton style (57/8/22/8 padding, 20px iconLeft), category headers, sub-items powerSavingButtonNoIcon (22/8/22/8) — spec §19.10–11
- [ ] Automatic Power Saving toggle (OS battery status conditional): ON + battery saver active → overlay (boxBg alpha 96) over controls (OK still clickable), 3s toast on overlay click, overlay removes when OS exits battery saver — spec §19.12 & §19.12.1

### 19.13–19.14 Language Box
- [ ] Language box (320px, max 492px list height): title "Language" — spec §19.13
- [ ] Translation toggles (logged-in only): "Show Translate Button" (settingsButtonNoIcon), "Translate Entire Chats" (settingsButtonNoIconLocked, Premium), "Do Not Translate" SlideWrap (shown when either toggle ON) with right-label (language name or "{N} languages"), divider explanation text — spec §19.14 & §19.14.1
- [ ] Skip-languages editor: "Do Not Translate" title, checkbox multi-select, enforced minimum 1 language (toast on deselect-all) — spec §19.14.2

### 19.15–19.17 Language List
- [ ] MultiSelect search bar (no tag chips), two sections (Recent / Official) separated by BoxContentDivider, de-duplicated, empty state "No languages found" — spec §19.15 & §19.15.1
- [ ] Language row (54px): langsRadio 22px button, native name (semiboldTextStyle, 66px left, 8px top), English name below (defaultTextStyle, windowSubTextFg), 3-dot menu toggle (topBarMenuToggle), windowBgOver hover, click activates — spec §19.16 & §19.16.1
- [ ] Language row context menu (non-official rows): dropdownMenuWithIcons, Share (copies link) / Delete (dims row) / Restore — spec §19.17

---

## §20 — Media Viewer / Lightbox

<!-- No dart file yet — new file needed: dart/lib/ui/media_viewer.dart -->

### 20.1 Window & Background
- [ ] Media viewer window: three states (full-screen default / maximized / windowed), state persisted, min 480×360px, default windowed 800×600 at (160,120), 44×32px title bar buttons, 32px title bar height, "Media viewer" title — spec §20.1
- [ ] Background: mediaviewBg opaque dark, top+bottom gradient shadow overlays at _controlsOpacity — spec §20.2

### 20.3 Content Display
- [ ] Media centered in available area: photo (progressive thumbnailInline→Small→Thumbnail→Large), video/GIF streaming, document bubble (mediaviewFileBg, 340×116px, 80×80px icon), theme preview (903×584px with Apply/Cancel/Share) — spec §20.3

### 20.4 Zoom & Pan
- [ ] Zoom range -7 to +7 (1/8× to 8×), kZoomToScreenLevel, Ctrl+/- / Ctrl+0 / middle mouse / wheel+Ctrl, pan on left-click-drag (cur_sizeall cursor, snapped to bounds), zoom transitions animate at widgetFadeDuration, DPR-aware, 4096px max cap — spec §20.4 & §20.4.1

### 20.5–20.6 Rotation, Flip, Navigation
- [ ] Rotate (0/90/180/270, each click -90°) and flip (H/V keys, photo only), rotate button in bottom-right toolbar — spec §20.5
- [ ] Side navigation areas (90px normal / 64px stories), prev/next icons, Left/Right arrow keys, touch/swipe 80px threshold, preload 3 ahead + 48 IDs each direction — spec §20.6

### 20.7 Footer / Header
- [ ] Bottom-left header: "Photo N of M"/filename (mediaviewThickFont semibold at (14,height-47), max width/3 middle-elided, clickable→overview), sender name (mediaviewFont at (14,height-26), clickable→peer info), date+DC (clickable→message in chat), mediaviewControlFg color — spec §20.7

### 20.8 Bottom-Right Toolbar + Context Menu
- [ ] Toolbar: 46×54px icon cells (right-to-left), 36px hover circle, 150ms per-icon fade, icons: More/Rotate/Share/Save/Draw/OCR (conditional) — spec §20.8
- [ ] More-menu / right-click: up to 18 conditional items (Cancel download, Show in Chat, Archive/Save, Copy Image, Forward, Delete, Save As, Set as Userpic, Report, etc.), dark-themed popup (groupCallMenuBg/groupCallMembersFg), Rotate NOT in context menu — spec §20.8.1 & §20.16

### 20.9 Caption Display
- [ ] Caption: mediaviewCaptionBg (radius 6px, no bg in stories), padding 11/6/11/6px, mediaviewCaptionStyle/mediaviewCaptionFg, max height 1/4 maxUsedHeight, stories collapsed to kCollapsedCaptionLines with "Show more", bottom-aligned with 11px margin, spoiler + timestamp link support — spec §20.9

### 20.10–20.12 Video Playback Controls
- [ ] Video controls panel (max 480px wide, 72px height): volume toggle (32×32px), volume slider (75px, mediaviewPlayback style), time played (12px semibold), progress bar (3px track, 12px handle), Play/Pause (40×40px centered), speed/quality button (32×32px), PiP button, fullscreen button, chapter marks (2×10px), controls fade 200ms in / 600ms out — spec §20.10
- [ ] Video behavior: Space/Enter/click play-pause, drag seek, Left/Right +/-5s in fullscreen, 0-9 jump, Alt+Left/Right chapter nav, speed 0.5×–3.0×, quality menu, volume 0.0–1.0, loop animations, auto-pause on call — spec §20.11
- [ ] Fullscreen: double-click/Alt+Enter/Ctrl+F toggle, auto-hide 1100ms with blank cursor, Escape exits fullscreen (not viewer) — spec §20.12

### 20.13 Picture-in-Picture
- [ ] PiP floating always-on-top window: default 320px (min 120px), 10px resize edges, own play/pause/close/enlarge/volume, 2px track (4px hover), geometry persisted, closing returns to viewer at same position, 16px snap threshold / 20px snap margin, default top-left, easeOutCirc release animation ~150ms — spec §20.13 & §20.13.1

### 20.14 Gallery Thumbs Strip
- [ ] Horizontal thumbnails (56–160px wide, 80px height), padding 0/14/0/14 with 3px gap (12px for current), current thumb 160px centered, no scrollbar, overflow capped to available width, click navigates, 150ms slide animation, active thumb emphasis via width only — spec §20.14 & §20.14.1

### 20.15 Save/Download Toast
- [ ] Centered toast (mediaviewSaveMsgBg): check icon at (23,21), padding 55/19/29/20px, 16px mediaviewSaveMsgStyle, fade in 200ms / hold 2s / fade out 2.5s, "Downloads" clickable link — spec §20.15

### 20.17 Stories Viewer Mode
- [ ] Stories: delegates to Stories::View, aspect-fit in 540×960 with 8px radius, sibling previews as thumbnails, controls always visible, no zoom/rotation, collapsed captions — spec §20.17

### 20.18–20.19 Keyboard Shortcuts & Animations
- [ ] All keyboard shortcuts: Escape/Space/Left/Right/Alt+Left/Right/0-9/Ctrl+F/Alt+Enter/Ctrl+/Ctrl-/Ctrl+0/Ctrl+S/Ctrl+C/H/V — spec §20.18
- [ ] All viewer animations: controls auto-hide 1100ms→600ms fade, mouse activity 200ms fade-in, blank cursor, icon hover 150ms, between-media rect interpolation with rotation, radial loading arc, open 200ms/close 600ms with overlay bg fade — spec §20.19 & §20.19.1

---

## §21 — Create Group / Channel Wizard

<!-- No dart file yet — new file needed: dart/lib/ui/create_group_wizard.dart -->

### 21.1 Wizard Overview
- [ ] Multi-step layered-box flow (all boxes 364px), entry from hamburger "New Group"/"New Channel", Group flow: InfoBox→MemberPicker, Channel flow: InfoBox→SetupChannelBox→MemberPicker — spec §21.1

### 21.2 Step 1 — Group/Channel Info Box
- [ ] Info box (48px title bar, 16px semibold): UserpicButton 72×72px at (24,10) with EmptyUserpic gradient initials (up to 2 letters, 28px font), forum userpic with rounded rect, change icon always visible when no image, upload overlay (24px, msgDateImgBgOver), progress ring (3px, 8px margin, 500ms) — spec §21.2 & §21.2.1
- [ ] Title input (left 99px, top 5px, ~217px width, max 128 chars, emoji suggestions), description (channels only, multiline, max 255 chars, max 116px height, 13px below userpic), TTL menu (groups only), Create/Next + Cancel buttons, empty-title shake, error handling (NO_CHAT_TITLE/USERS_TOO_FEW/CHANNELS_TOO_MUCH) — spec §21.2
- [ ] Forum "Enable Topics" toggle: in post-creation Manage settings (not Step 1), manageGroupTopicsButton style, "NEW" badge, child screen with Tabs/List radios + enable toggle, member-count gate from AppConfig (fallback 200), forces pre-join history visible — spec §21.2.2

### 21.3 Step 2a — Member Picker

### 21.4 Step 2b — Channel Setup Box
- [ ] Public/Private radios (defaultBoxCheckbox, 27px skip), about text (windowSubTextFg), username field (t.me/ prefix, setupChannelLink style, 32px min height, 200ms validation debounce, client pre-checks, green/red API status label, 5–32 chars alphanumeric+underscore), private invite link (clickable, copies+toast), PublicLinksLimitBox on too many — spec §21.4 & §21.4.1
- [ ] PublicLinksLimitBox (364px): "Public Link Limit Reached", bubble with counter, free(10)/premium(20) limits, revoke list (avatar+title+status+"Revoke" link), revoke confirmation, Premium upsell gradient button or close button — spec §21.4.2

### 21.5 Edit Peer Type Box
- [ ] EditPeerTypeBox (364px): privacy radios (editPeerPrivacyBoxCheckbox, margins 0/8/0/8), explanation labels (min 220px, windowSubTextFg, margins 42/0/34/0), 16px bottom skip, draggable collectible usernames list (public), permanent invite link block with copy/share (private) — spec §21.5
- [ ] Group permission toggles: full-width rows (icon+label+toggle), toggleSkip from right, locked=dimmed, lineWidth separator, "Only members" toggle, slow mode slider (8 positions 0–3600s with step labels), Topics row (conditional forum), Approve New Members nested toggle, Restrict Saving toggle, color tokens — spec §21.5.1

### 21.6 Complete Flow
- [ ] Full flow sequences functional end-to-end: Create Group (InfoBox→MemberPicker→API→chat), Create Channel (InfoBox→API→SetupChannelBox→MemberPicker→channel) — spec §21.6

---

## §22 — Forum Topics UI

<!-- No dart file yet — likely integrates with dart/lib/ui/chat_list_panel.dart, dart/lib/ui/chat_view.dart -->

### 22.1–22.2 Data Model & Icon System
- [ ] ForumTopic data model: rootId/title/colorId/iconId/creatorId/creationDate/flags, General topic rootId=1, capability flags (canEdit/canDelete/canToggleClosed/canTogglePinned) — spec §22.1
- [ ] Predefined color icons: 6 colors (blue/yellow/violet/green/rose/red), SVG bubble-with-tail (84×84 viewBox, gradient fill, gradient stroke 2.95px, highlight arc 37.5%), color selection picks SVG file not runtime hue-shift — spec §22.2 & §22.2.1
- [ ] Default icon rendering: colored circle + first non-emoji letter (white, centered), four size variants (default 21px / normal 19px / large 26px / info 32px), DPR-aware — spec §22.2
- [ ] General topic icon: general.svg 20×20 hash shape, recolored at paint time (dialogsTextFg/Over/Active per context), re-rendered on palette changes, no color background — spec §22.2
- [ ] Custom emoji icon: loaded via CustomEmojiManager when iconId≠0, loops once then freezes, no bubble background, narrow-mode centering, context text color variants — spec §22.2

### 22.3 Topic List Layout
- [ ] Topic list (54px rows, padding 8/7/10/7px): 20px icon / nameLeft 39px nameTop 7px / textLeft 39px textTop 29px / 8px unread mark, paints icon+name (semibold)+closed lock+date+preview+badges+pin, NO separators, row states (transparent/dialogsBgOver/dialogsBgActive), dialogsRipple on click — spec §22.3 & §22.3.1

### 22.4 Forum Group in Chat List
- [ ] Forum group row (80px / 96px with tags): TopicsView with up to 8 recent topic names (unread in bold), 8px/14px inter-title gap, topic jump bubble (radius 11px, padding 8/3/8/3, arrow icon), two-rect stepped outline for multi-line spanning, expanded bar (dialogsBgActive, roundRadiusLarge, animated 0.0–1.0), topics preview height 21px — spec §22.4

### 22.5 Create / Edit Topic Dialog
- [ ] EditForumTopicBox (GenericBox, max 408px): title input (defaultInputField, margins 70/2/22/18), placeholder "Topic Name" or "Bot Thread Title", icon button at (24,19) showing emoji or 26px default circle, click cycles random color from remaining pool (disabled with custom emoji or when editing), divider text, not shown for General topic — spec §22.5 & §22.5.1
- [ ] Icon selector panel (EmojiListWidget Mode::TopicIcon): recent section (default icon sentinel + server emoji set), non-default custom emoji require Premium (toast), EmojiFlyAnimation from selector to icon button, shadow separator below pinned cover, auto-title reactivity on typing — spec §22.5 & §22.5.1
- [ ] Save/Create logic: validates non-empty title, reserves local ID, navigates to topic, calls EditForumTopic API, General topic cannot change icon, showError on empty title submit — spec §22.5

### 22.6 Topic Header Bar
- [ ] Standard info_top_bar (54px): back→topic list, title with icon prefix + optional subtitle, selection mode (cancel+count+forward/delete) — spec §22.6

### 22.7 Topic Info Panel
- [ ] Topic info panel (third column or full-screen push): cover height 77px, 36×36px icon at (22,18), name at (79,14) + status at (79,38), General in windowSubTextFg, custom emoji loaded at cover size, default 32px circle with bold 15px letter, sections (notifications toggle/shared media/members list/topic link) — spec §22.7

### 22.8 Context Menus
- [ ] Topic list right-click: Create Topic / View Group Info / View as Messages / Search / Manage Group / Add Members / Video Chat / Report / Leave/Join — spec §22.8
- [ ] Topic row right-click: New Window (always), Pin/Unpin (admin canTogglePinned), View Info, Mute submenu, Mark Read/Unread, Close/Reopen (label flips), Add to Folder, Clear History, Delete Topic (canDelete, red, blocked on General) — spec §22.8.1
- [ ] Inside topic burger menu: Mute / Create Topic / Topic/Group Info / View as Topics / Manage Group — spec §22.8
- [ ] Topic info panel menu: TTL / Copy Topic Link (public only) / Edit Topic (canEdit) / Close/Reopen / standard profile items / Delete Topic — spec §22.8 & §22.8.1

### 22.9 General Topic
- [ ] rootId=1, cannot be deleted/change icon (uses general.svg), can be hidden, title prefixed with "# " in rich text — spec §22.9

### 22.10 Navigation & Column Integration
- [ ] One-column: forum replaces dialog list, back returns to main; two/three-column: topic list in dialog column; "View as Messages/Topics" toggle (saves preference); loading pagination (first 20, then 500/page, stale 100/request); auto-preload when <20 loaded; 8 recent topics for chat list — spec §22.10

### 22.11 Animations
- [ ] Userpic loop reset after slideDuration (custom emoji stops/frees memory), topic jump ripple (dialogsRipple), expanded bar 0.0–1.0 float drives left-edge bar, EmojiFlyAnimation in edit dialog, info top bar highlight fade between bg and highlightBg — spec §22.11
