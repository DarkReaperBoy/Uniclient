# Audit: §1-§4 Layout & Navigation

## §1 — Window Layout & Column Structure

## §2 — Chat List Sidebar

## §3 — Hamburger Menu

## §4 — Chat Header / Top Bar

# Audit: §5-§7 Messages & Compose

## §5 — Message List & Bubbles


## §6 — Media Message Types


## §7 — Compose Area

# Audit: §8-§13 Panels & Overlays

## §9 — Context Menus & Actions


## §11 — Authentication / Login Flow

## §12 — Calls UI

## §13 — Mobile / Web Compatibility
# Audit: §14-§19 Settings

---

---

---

---

---

## Cross-Cutting Issues
# Audit: §20-§25 Media Viewer, Groups, Forum, Scheduled, Shortcuts, Theming

## §20 — Media Viewer / Lightbox


## §22 — Forum Topics UI


## §24 — Keyboard Shortcuts


# Audit: &sect;26-&sect;36 Admin, Export, Contacts, Calls, States

## &sect;26 -- Admin Tools

## &sect;27 -- Passcode Lock Screen

## &sect;28 -- Two-Factor Authentication Setup

## &sect;29 -- Chat Export

## &sect;30 -- Bot Interactions

## &sect;31 -- Saved Messages

## &sect;32 -- Stories

## &sect;33 -- Contacts Screen

## &sect;35 -- Empty, Error & Loading States

## &sect;36 -- Common Dialog & Modal Patterns
# Audit: §37-§49 Popups, Formatting & Interactions


## §38 — User Profile Popup

## §39 — Photo & Avatar Cropping Dialog

## §40 — Send Files Dialog

## §41 — Message Formatting Toolbar


## §42 — Reactions Detail Popup

## §43 — Read Receipts Detail



## §46 — Link Preview in Compose

- [ ] spec §46.1 "URL detection debouncing": spec says 500ms debounce for 1-2 char changes, 0ms for paste; code has a `_betterLinkPreviewUrl` function and link preview logic in chat_view.dart — needs detailed verification of debounce timing
- [ ] spec §46.2 "Preview card layout": spec says 49px height bar with left icon at (7,7), thumbnail at 53px left, text at 53/95px, cancel button 49x49px; needs verification that the FieldHeader equivalent in chat_view.dart matches these exact pixel values
- [ ] spec §46.3 "Large vs small media toggle": spec says DraftOptionsBox has "Enlarge photo/video" / "Shrink photo/video" button; needs verification of implementation
- [ ] spec §46.4 "Preview above/below text": spec says `WebPageDraft.invert` flag controls position; needs verification
- [ ] spec §46.5 "Multiple URLs": spec says first link with cached preview is picked; the link-preview flow in chat_view.dart needs verification for multi-URL handling
- [ ] spec §46.8 "Remove preview": spec says clicking cancel X removes preview and sets `removed` flag that persists in draft; needs verification

## §47 — Restricted Permissions UI

- [ ] spec §47 "WriteRestrictionType enum": spec defines None/Rights/PremiumRequired/Frozen/Hidden types; code in chat_view.dart likely implements a restriction bar but full coverage of all 5 types needs verification
- [ ] spec §47 "Per-restriction error strings": spec defines 3 tiers of error messages (timed/permanent/default) for each `ChatRestriction` flag; these localized strings need to come from the engine and be displayed correctly
- [ ] spec §47 "Grayed/forbidden send button": spec says record/round button at 50% opacity when forbidden with suppressed ripple; needs verification in chat_view.dart send button implementation
- [ ] spec §47 "Slowmode countdown": spec says MM:SS countdown on send button using `normalFont` 13px in `windowSubTextFg`; needs verification
- [ ] spec §47 "Join to Send button": spec says unjoin channels show "JOIN CHANNEL" / "JOIN GROUP" / "APPLY TO JOIN GROUP" button; needs verification
- [ ] spec §47 "Bot Start button": spec says first-time bot chats show "START" button; needs verification
- [ ] spec §47 "Unblock button": spec says blocked users show "UNBLOCK" button in `attentionButtonFg` red; needs verification
- [ ] spec §47 "Forum topic closed": spec says closed topics show "This topic is closed." restriction text; needs verification

## §48 — Drag-and-Drop File Overlay

- [ ] spec §48.1 "Drop zone appearance": spec says rounded rectangle with `boxBg` background, `boxRoundShadow` shadow, main text 27px semibold, subtext 19px semibold; code has a `_DragOverlay` widget in chat_view.dart — needs verification of exact dimensions and text sizes
- [ ] spec §48.2 "Two-zone layout": spec defines Files/PhotoFiles/MediaFiles/Image states with top/bottom split for two-zone mode; needs verification of zone classification logic
- [ ] spec §48.4 "File type detection": spec says `ComputeMimeDataState` classifies dragged content; needs verification that the Dart equivalent properly classifies file types
- [ ] spec §48.5 "Animation": spec says `_a_opacity` fades in/out over 200ms; code has `_dragOverlayAnimCtrl` AnimationController — needs verification of duration
- [ ] spec §48.7 "No icons": spec says drop zones are text-only (no icons); needs verification
- [ ] spec §48.9 "Disabled state": spec says drag overlay does not appear if user cannot send any file type; needs verification of permission check

## §49 — Scroll Behaviors

- [ ] spec §49.1 "Infinite scroll preload": spec says preload triggers at 3 viewport heights from edge, fetching 50 messages per page (30 for first load); needs verification in chat_view.dart scroll logic
- [ ] spec §49.2 "Jump-to-date": spec says clicking sticky date header opens `CalendarBox`; code likely has a date click handler — needs verification
- [ ] spec §49.3 "Jump-to-message highlight": spec says highlight effect: 400ms fade in, optional 400ms hold + 200ms collapse, 2000ms fade out; needs verification of highlight animation in chat_view.dart
- [ ] spec §49.4 "Unread marker": code has `_UnreadBar` widget at chat_view.dart:7331 — exists, needs verification of positioning and destruction logic
- [ ] spec §49.5 "Scroll-to-bottom button": spec says 52x62px hit area, down-arrow circular button, shown when scrolled up >480px, 150ms slide animation; code has a jump-down button (chat_view.dart:10447) — needs verification of exact dimensions and threshold
- [ ] spec §49.5 "Unread badge on scroll button": spec says unread count shown in 22px circle badge; needs verification
- [ ] spec §49.6 "New message auto-scroll": spec says own messages always scroll to bottom, incoming only if already at bottom; needs verification
- [ ] spec §49.8 "Smooth scrolling duration": spec says 240ms with sineInOut for short scroll, easeOutCubic for long scroll; needs verification
- [ ] spec §49.9 "Scroll-to-mention button": spec says "@" icon button shown when unread mentions exist, stacked above scroll-to-bottom with 4px gap; code has mention button at chat_view.dart:10547 — needs verification of stacking
- [ ] spec §49.10 "Scroll-to-reaction button": spec says heart icon button for unread reactions stacked above mentions; needs verification
- [ ] spec §49.13 "Sticky date header": spec says date header fades in over 200ms, auto-hides after 1000ms; needs verification of timing constants
# Audit: §50-§57 AyuGram Features & Appendices

## §50 — Streamer Mode & Read Toggles

- [ ] spec §50.2 "Streamer Mode — what it does": No `StreamerModeState` or streamer-mode runtime toggle exists anywhere in the Dart codebase. The spec requires a non-persistent `enabled` boolean with a `Stream<bool>` for drawer/tray sync — `state/app_state.dart` only has `showStreamerToggleInDrawer` / `showStreamerToggleInTray` (visibility gates), but no actual streamer mode on/off state or OS platform channel for `SetWindowDisplayAffinity` / `NSWindow.sharingType`
- [ ] spec §50.3.1 "Drawer toggle": The drawer does not render a Streamer Mode on/off toggle row (only the visibility setting in `ayu_other_page.dart` "Show Streamer Mode toggle in drawer" exists, but the drawer itself has no toggle to flip the actual mode)
- [ ] spec §50.3.2 "Tray menu toggle": No tray menu integration exists — spec requires "Enable/Disable Streamer Mode" action in the system tray context menu; the code only has a setting to show/hide it (`showStreamerToggleInTray`)
- [ ] spec §50.3.3 "Settings page — Drawer/Tray elements": Drawer/Tray elements are located in `ayu_other_page.dart` instead of the Ghost Mode page as spec §50.3.3 requires (spec says these live under "AyuGram settings > Ghost Mode page" subsections "Drawer Elements" / "Tray Elements")
- [ ] spec §50.4 "Visual indicators": No visual indicator that Streamer Mode is active (no icon, no chip, no badge anywhere)
- [ ] spec §50.7 "Read toggles — Local Read / Server Read model": `showLReadToggleInDrawer` and `showSReadToggleInDrawer` settings exist in `ayu_other_page.dart` as drawer visibility toggles, but no actual LRead/SRead drawer toggle rows are rendered in the drawer at runtime
- [ ] spec §50.8 "All referenced settings keys": Missing `showGhostToggleInDrawer` / `showStreamerToggleInDrawer` visibility settings on the Ghost Mode page itself — they only appear on `ayu_other_page.dart` (the "Other" page), not the Ghost Mode settings where the spec places them
- [ ] spec §50.9 "Chat list right-click — Read Message action": No "Read Message" context menu action on chat list items that forces a one-shot server read (spec requires this with a confirmation dialog)
- [ ] spec §50.9 "Chat context — per-peer exclusions": No "Read Exclusion" / "Typing Exclusion" per-peer override submenu on the chat context menu

## §51 — Ghost Mode

- [ ] spec §51.2.1 "Ghost Mode collapsible toggle": The ghost sub-toggles use checkboxes inside `AnimatedSize` which is correct, but the master toggle uses `_GhostMasterToggle` as a separate widget rather than a standard collapsible parent toggle — the visual style differs from spec (spec says "collapsible parent toggle labeled Ghost Mode")
- [ ] spec §51.2.2 "Schedule Messages — mutually exclusive with Read on Interact": Spec §51.2.2 says toggles #6 and #7 are mutually exclusive (enabling one disables the other). Code in `ghost_settings_page.dart` does not enforce mutual exclusivity — both `markReadAfterAction` and `useScheduledMessages` can be ON simultaneously
- [ ] spec §51.3 "Account picker — GlobalAction custom menu item": The `_GlobalSettingsAvatar` uses a purple gradient circle with "GS" text which matches the spec's description. However, the account picker does not show a toast notification on switch as spec requires ("Switched to same settings for all accounts." / "Switched to individual settings for each account.") — code uses `SnackBar` instead of the spec's toast
- [ ] spec §51.4 "Settings screen layout — navigation path": Spec says the ghost settings page is `AyuGhost` section reached via AyuMain > "AyuGram" category button. The code navigates to `GhostSettingsPage` with the app bar title "AyuGram" which is correct, but the page title should be blank per spec (AyuGhost section has no dedicated title bar text; the subsection title "Ghost essentials" is inline)
- [ ] spec §51.5 "Drawer — LRead and SRead toggle buttons": Drawer does not render LRead / SRead toggle buttons at runtime. Only the visibility settings (`showLReadToggleInDrawer`, `showSReadToggleInDrawer`) exist in `ayu_other_page.dart`
- [ ] spec §51.7 "Command-line -ghost flag": No support for `-ghost` launch argument that forces all ghost settings on at startup
- [ ] spec §51.8 "Toast notifications": Ghost mode toggle toast uses `showTelegramToast` in the code which is correct, but the spec's toasts `ayu_GhostModeEnabled` / `ayu_GhostModeDisabled` should match. Verified the strings match ("Ghost Mode turned on" / "Ghost Mode turned off")

## §52 — Anti-Recall & Message History

- [ ] spec §52.1 "Settings — semiTransparentDeletedMessages": Setting exists as `semiTransparentDeleted` in `ayu_chats_page.dart` as a toggle in the Messages section, but spec §52.1 says it should be under "Spy Essentials" subsection. It is implemented on the Chats page instead of the Ghost/AyuGram page
- [ ] spec §52.1 "deletedMark / editedMark — EditMarkBox dialog": No `EditMarkBox` dialog to customize the deleted mark or edited mark text. The `_BubbleRadiusSection` in `ayu_chats_page.dart` uses `deletedMark` and `editedMark` from state for the preview, but there is no settings UI to edit these strings (spec §52.10 describes a 320px dialog with text input and reset-to-default button)
- [ ] spec §52.1 "replaceBottomInfoWithIcons toggle": Toggle exists in the code (`replaceMarksWithIcons` in ayu_chats_page.dart) but there is no sub-settings reveal for the deleted mark and edited mark text customization buttons when this toggle is OFF (spec §54.11 says "When disabled, reveals sub-settings for custom deleted mark text and edited mark text via EditMarkBox dialogs")
- [ ] spec §52.2-52.4 "Deletion/Edit interception flow": No actual deletion or edit interception implementation exists in the Dart codebase. There is no mechanism to preserve deleted messages or capture pre-edit text. The `saveDeletedMessages` and `saveMessagesHistory` toggles in `ghost_settings_page.dart` are persisted but have no functional backend wiring
- [ ] spec §52.5 "Deleted Messages Viewer": No "View deleted messages" section panel or chat-list context menu action. No `MessageHistory` equivalent widget exists
- [ ] spec §52.4 "Edit History Viewer": No "Edits history" context menu item or section panel for viewing edit revisions
- [ ] spec §52.6 "Database Storage": No SQLite `ayudata.db` or equivalent local storage for preserved deleted/edited messages
- [ ] spec §52.7 "Context Menu — Edits history / Hide message / Read until here / Burn media": None of these AyuGram-specific context menu actions are implemented in the message bubble context menu

## §53 — Forward Enhancements

- [ ] spec §53.1 "Intelligent Forward — chunking algorithm": `AyuForward.buildChunks()` in `state/ayu_forward.dart` implements the chunking logic correctly, splitting messages by restriction status. However, there is no `intelligentForward` call path that triggers from the standard forward UI — the method exists but is not wired to any forward dialog or share box intercept
- [ ] spec §53.2 "Forward Progress Tracking — compose area replacement": `ForwardProgress` class exists with correct state machine (Preparing/Downloading/Sending/Finished), but no `AyuForwardWriteRestriction` widget replaces the compose area during an active forward. The progress bar UI described in spec (full-width FlatButton replacing compose field) does not exist
- [ ] spec §53.3 "Repeat Message — context menu action": No "Repeat Message" context menu item on message bubbles. The `showRepeatMessageInContextMenu` setting exists in `ayu_chats_page.dart` (context menu visibility), but no actual menu action is implemented
- [ ] spec §53.3 "Repeat Message — Shift+click for no-quote mode": No implementation of the "send as own without forward header" behavior triggered by Shift+clicking Repeat Message
- [ ] spec §53.4 "Restriction Override — context menu label": No "Plain forwarding is not allowed." label (`ayu_UnforwardableContextMenuText`) in the context menu for restricted messages
- [ ] spec §53.5 "Download-and-Resend Pipeline": `engine.resendAsOwn()` and `engine.resendAlbumAsOwn()` calls exist in `ayu_forward.dart`, but these delegate to the engine service which is the Go bridge — the actual download/re-upload logic depends on the Go backend, not verified here
- [ ] spec §53.8 "Repeat Message — No Hint Text": Irrelevant since the menu item itself doesn't exist yet

## §54 — AyuGram UI Customization

- [ ] spec §54.1 "Avatar Corners — live preview": `_AvatarCornersPreview` renders a static placeholder ("A" letter, purple background) instead of the actual AyuGramReleases channel userpic fetched via `contacts.resolveUsername`. The preview does not resolve a real userpic as spec requires — `ayu_appearance_page.dart`
- [ ] spec §54.1 "Avatar Corners — clicking preview opens channel": Spec says clicking the preview opens the AyuGramReleases channel. The `_AvatarCornersPreview` widget has no `GestureDetector` or `onTap` handler — `ayu_appearance_page.dart`
- [ ] spec §54.1 "Avatar Corners — restart required": Spec says slider release prompts a restart. The code changes corners immediately via `onCornersChanged` with no restart prompt — `ayu_appearance_page.dart`
- [ ] spec §54.2 "Material Switches — track size": Spec §54.2a says MD3 track is 32x18 and iOS track is 36x20. Code in `ayu_toggle.dart` uses md3 32x18 and iOS 36x20, which matches. Verified correct
- [ ] spec §54.3 "Wide Messages Multiplier — slider range": Spec says 61 discrete stops from 1.00 to 4.00 in 0.05 increments. Code uses `divisions: 60` with `min: 1.0, max: 4.0` which gives 61 stops — matches. But spec also says "valid range 0.5-4.0" while the slider only goes from 1.0 to 4.0, missing the 0.5-1.0 range — `ayu_chats_page.dart`
- [ ] spec §54.4 "Message Bubble Radius — live preview": `_MessagePreview` in `ayu_chats_page.dart` renders a preview with two messages including reply quote, deleted+edited marks, tail control, and quote styling. This matches the spec's description well
- [ ] spec §54.5 "Message Tail Removal": Toggle exists and affects the preview. Spec says "No restart required (reactive update)" which matches the code behavior
- [ ] spec §54.7 "Context Menu — Add Filter only if filtersEnabled": Spec says "The 'Add Filter' option only appears in settings if `filtersEnabled` is true." Code shows the Add Filter choose button unconditionally in the context menu items list — `ayu_chats_page.dart` line 229
- [ ] spec §54.8 "Drawer Elements — placement": Spec §54.12 says Drawer Elements and Tray Elements live under the **Appearance** page. Code places them in `ayu_other_page.dart` (the "Other" page) instead — `ayu_other_page.dart`
- [ ] spec §54.8 "Tray Elements — placement": Same as above — Tray Elements are under "Other" instead of "Appearance" as spec requires
- [ ] spec §54.8 "Drawer Elements — Streamer Mode only on Windows/macOS": The Streamer Mode drawer toggle is shown unconditionally (no platform check). Spec says "only appears on Windows and macOS" — `ayu_other_page.dart` line 92
- [ ] spec §54.8 "Tray Elements — Streamer Mode only on Windows/macOS": Same — Streamer Mode tray toggle shown unconditionally — `ayu_other_page.dart` line 109
- [ ] spec §54.9 "Message Field Button Toggles — wiring": Seven message field button toggles exist in `ayu_chats_page.dart` (Attach, Commands, TTL, Emoji, Voice, Gift, AI Editor) but their state is not consumed by the actual compose area to show/hide buttons. The toggles persist settings but the compose area does not read them
- [ ] spec §54.10 "Hide Notification Badge — Windows only": Setting `hideNotificationBadge` is not present anywhere in the Dart codebase. Spec says this is a Windows-only toggle under Appearance > "Appearance" subsection
- [ ] spec §54.10 "App Icon — icon picker": `_AppIconPicker` in `ayu_appearance_page.dart` renders colored squares with a single letter instead of actual SVG icon previews loaded from `AyuAssets.loadPreview()`. The 12 icon themes are listed correctly
- [ ] spec §54.10a "IconPicker — resolved layout": Spec says grid is 4 columns with `iconPickerIconSize` = 64px, `iconPickerSelectedRounding` = 12px. Code uses `SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4)` which matches the column count, but icons are rendered as colored containers with text instead of actual icon images
- [ ] spec §54.11 "Translucent Deleted Messages — beta badge": Setting exists with `showBetaBadge: true` through the section builder. However, it is only in the Messages section of Chats, not in Spy Essentials where spec §52.1 places the visual toggle
- [ ] spec §54.12 "Settings Page Structure": The overall structure (AyuMain > 6 category buttons) is implemented correctly in `ayugram_settings_screen.dart`. However, the category mapping differs: spec maps "AyuGram" button to `AyuGhost` (ghost + spy + other), but code maps it to `GhostSettingsPage` which only covers ghost + spy. Drawer/Tray Elements are on the "Other" page instead of "Appearance"
- [ ] spec §54.14 "Translation Provider — platform-specific options": Code in `ayu_general_page.dart` hardcodes the provider list as {Telegram, Google, Yandex, Linux} without checking `IsTranslateProviderAvailable()`. Spec says the label always shows the platform name but on unavailable, settings init resets to Telegram. The code shows "Linux" unconditionally on all platforms
- [ ] spec §54.14 "Filter Zalgo — restart required": Spec says Filter Zalgo requires app restart (toggling shows a restart prompt). Code does not show any restart prompt — `ayu_general_page.dart`
- [ ] spec §54.15 "Donate icons — theme-adaptive background": Spec says donate button icon background is `#EEEEEE` in night mode and `#242B2C` in light mode. Code in `ayu_other_page.dart` line 290 correctly uses `isDark ? Color(0xFFEEEEEE) : Color(0xFF242B2C)`. Verified correct
- [ ] spec §54.15 "Other subsection — conditionally compiled": Spec says the "Other" subsection with Crash Reporting is conditionally compiled only when `TDESKTOP_DISABLE_AUTOUPDATE` is NOT defined. Code shows Crash Reporting unconditionally — `ayu_other_page.dart`
- [ ] spec §54.17 "AyuMain Landing Page — logo widget": The logo uses `settingsCloudPasswordIconSize` (96px per code). Spec says the size is from `st::settingsCloudPasswordIconSize` = 100px (§56.7). Code uses 96px instead of 100px — `ayugram_settings_screen.dart` line 68

## §55 — Channel & Group Statistics

- [ ] spec §55.1 "Opening Statistics": No statistics menu item or navigation to a statistics page exists in any peer context menu or info panel. `stats_chart.dart` contains the chart rendering infrastructure but no page/section wraps it
- [ ] spec §55.2 "Loading State": No loading state with Lottie animation (`stats` animation) and "Loading Statistics..." text
- [ ] spec §55.3 "Channel Statistics Layout — Overview Section": No 2x2 overview grid with StatisticalValue cards (Followers, Notifications, Views Per Post, Views Per Story). `StatisticalValue` class exists in `stats_chart.dart` but is not rendered anywhere
- [ ] spec §55.3 "Channel Statistics Layout — Charts Section": No statistics page renders charts. `StatsChartWidget` exists and is fully implemented with all 5 chart types (Linear, DoubleLinear, Bar, StackBar, StackLinear) but is never instantiated in any screen
- [ ] spec §55.3 "Recent Messages Section": No "Recent Messages" list with message preview rows, pagination, or "Show More" button
- [ ] spec §55.4 "Group Statistics Layout": No group statistics with Members/Messages/Viewing Members/Posting Members overview or Top Senders/Admins/Inviters peer lists
- [ ] spec §55.5 "Message Statistics Layout": No per-message statistics sub-page
- [ ] spec §55.6 "Chart Widget Architecture — all regions": `StatsChartWidget` implements header (36px), chart area (200px), footer/range selector (42px), and filter buttons correctly. The tooltip (`_buildTooltip`) includes date, per-line values, percentages, currency support, shadow, and zoom arrow. This implementation is comprehensive
- [ ] spec §55.7 "StackLinear — pie chart zoom": Pie chart transition is implemented with `_enterPieMode`/`_exitPieMode`, 400ms `easeOutCirc` animation, hover detection, pop-out on hover (8px), percentage labels. Matches spec. "Zoom Out" button appears in header
- [ ] spec §55.8 "Server-Side Zoom": `_requestServerZoom` fetches data via `onLoadZoomData` callback, creates a nested `StatsChartWidget` with crossfade, "Zoom Out" button. Correctly implemented
- [ ] spec §55.9 "Filter Buttons": `_FilterButton` with checkmark, color, active/inactive state, `Wrap` layout, long-press to solo/unsolo a line. Matches spec
- [ ] spec §55.10 "Animation System — FPS-adaptive": `_onChartTick` implements FPS-adaptive speed (`60 / currentFPS` multiplier, double speed below 30 FPS), three speed tiers, instant snap at 0.97 ratio, filter speed divisor 1.2. Matches spec

## §56 — Appendix A: Resolved Style Constants

- [ ] spec §56.1 "fsize = 13px, boxFontSize = 14px": `TgTokens.fsize = 13` and `TgTokens.boxFontSize = 14` in `theme_tokens.dart`. Matches spec
- [ ] spec §56.1 "slideDuration = 240ms, slideWrapDuration = 150ms, fadeWrapDuration = 200ms, universalDuration = 120ms": All four durations match in `theme_tokens.dart`. Verified correct
- [ ] spec §56.2 "boxWidth = 320, boxWideWidth = 364, boxRadius = 8": All match in `theme_tokens.dart`. Verified correct
- [ ] spec §56.3 "topBarHeight = 54, columnMinimalWidthLeft = 260, adaptiveChatWideWidth = 880": All match in `theme_tokens.dart`. Verified correct
- [ ] spec §56.4 "dialogsRowHeight = 62, dialogsPhotoSize = 46, dialogsNameLeft = 68": All match in `theme_tokens.dart`. Verified correct
- [ ] spec §56.7 "settingsCloudPasswordIconSize = 100px": Not defined in `theme_tokens.dart`. The AyuMain logo widget in `ayugram_settings_screen.dart` uses 96px hardcoded instead of 100px
- [ ] spec §56.8 "infoDesiredWidth = 392, infoTopBarHeight = 54": Both match in `theme_tokens.dart`. Verified correct
- [ ] spec §56.10 "windowBg light = #FFFFFF, dark = #212D3B": Spec §56.10 says dark `windowBg` is `#212D3B`, but §57.1 says dark `windowBg` is `#17212B`. The TelegramPalette `night` theme uses `#17212B` which matches §57.1 (the authoritative source). The §56.10 summary table appears to use the older "canonical Night" values which differ from the day-custom-base/night-custom-base themes in §57
- [ ] spec §56.10 "windowBgActive light = #40A7E3, dark = #2F82C7": Spec §56.10 says dark `windowBgActive` is `#2F82C7`, but §57.1 says `#5288C1`. TelegramPalette uses `#5288C1` for night which matches §57.1

## §57 — Appendix B: Dark Theme Color Palette

- [ ] spec §57.1 "windowBg dark = #17212B": TelegramPalette.night.windowBg must be `Color(0xFF17212B)`. Based on the palette field declarations and the theme system using `TelegramPalette.night`, this should be verified against the actual palette construction (file too large to read fully, but the `AppColors.darkBase = Color(0xFF17212B)` in `theme.dart` confirms the value is used)
- [ ] spec §57.1 "windowBgActive dark = #5288C1": `AppColors.accentDark = Color(0xFF5288C1)` in `theme.dart` matches. `TelegramPalette.night.windowBgActive` should use this value
- [ ] spec §57.2 "dialogsBgActive dark = #2B5278": `AppColors.bubbleSent = Color(0xFF2b5278)` exists but is named as bubble color. The dialog active background should be the same value per spec
- [ ] spec §57.4 "msgInBg dark = #24292E": Spec says dark `msgInBg` is `#24292E` but `AppColors.bubbleReceived = Color(0xFF182533)`. These differ — code uses `#182533`, spec says `#24292E`. The spec §57.4 night value and the code value are different. This may be an intentional AyuGram override or a palette version mismatch
- [ ] spec §57.4 "msgOutBg dark = #265E8C": Spec says dark `msgOutBg` is `#265E8C` but `AppColors.bubbleSent = Color(0xFF2b5278)`. These differ — code uses `#2B5278`, spec says `#265E8C`
- [ ] spec §57.5 "historyComposeIconFg dark = #6C7883": `AppColors.historyComposeIconFgNight = Color(0xFF6c7883)` matches spec value. Verified correct
- [ ] spec §57.6 "historyPeer1NameFg dark = #FB6169": Palette field exists in TelegramPalette. Value should be verified against the full palette definition
- [ ] spec §57.9 "activeButtonBg dark = #2F6EA5": Spec §57.9 says dark `activeButtonBg` is `#2F6EA5`. This differs from §57.1 `windowBgActive` dark = `#5288C1`. TelegramPalette must define these as separate tokens — verify that `activeButtonBg` uses `#2F6EA5` and not the `windowBgActive` alias
- [ ] spec §57.10 "sideBarBg dark = #0E1621": `AppColors.darkSidebar = Color(0xFF0E1621)` matches. Verified correct
- [ ] spec §57.10 "sideBarBgActive dark = #25303E": Needs verification against TelegramPalette.night.sideBarBgActive (palette too large to fully read)

## General / Cross-Cutting Issues

- [ ] No Streamer Mode feature exists at all — neither the runtime toggle, OS hooks, nor any UI surface. This is the largest missing AyuGram feature
- [ ] Ghost mode lock mechanism uses Shift+click on desktop and long-press on mobile (matching spec §51.2.1). Verified correct in `_LockableToggleRow`
- [ ] Per-peer read/typing exclusions (§50.7, §51.5) are entirely missing — no `Map<int64, ReadExclusion>` storage or per-chat override UI
- [ ] "Read Message" chat-list context action (§50.7) with confirmation dialog is missing
- [ ] The collapsible toggle in `ayu_section_builder.dart` does not implement a master toggle that sets all sub-checkboxes — it only shows/hides nested checkboxes. Spec §51.2.1 says the master toggle calls `setGhostModeEnabled(bool)` which flips all five core toggles
- [ ] No `-ghost` command-line flag support for launch-time ghost mode activation
- [ ] Statistics page infrastructure (`StatsChartWidget`, all 5 chart types, tooltip, footer, pie zoom, server zoom, filter buttons, FPS-adaptive animation) is fully built but never wired to any navigation entry point
- [ ] The AyuGram settings page structure partially mismatches spec §54.12: Drawer/Tray Elements are under "Other" instead of "Appearance"; the "AyuGram" category maps to ghost-only instead of ghost+spy+other
