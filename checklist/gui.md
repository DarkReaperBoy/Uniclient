# GUI Audit — Cycle 1 (2026-05-08 13:00)

## Constraint Violations (Layer 1)

# Audit: §1 Window Layout & Column Structure

- [ ] [CRITICAL] spec §1 "Filters sidebar — Edit button": "Edit" button `onTap` is wired to `widget.onOpenDrawer` which opens the HamburgerDrawer; spec says the button should open the folder-editing UI (manage/edit chat folders), not the main menu — `dart/lib/ui/filter_column.dart:427-433`

- [ ] [MAJOR] spec §1 "Dialogs column — collapsed narrow mode": when `_dialogsCollapsed == true`, `dialogsWidth` is set to `0.0`, making the `AnimatedContainer` zero-width and the `ChatListPanel` completely invisible; spec says dragging below 130 px should snap to a narrow avatar-only strip (not hide the column entirely); code's own comment confirms the intent — `dart/lib/ui/shell.dart:472-476`

# Audit: §11 Authentication / Login Flow

- [ ] [MAJOR] spec §11.2 "_next Button busy/loading": spinner `CircularProgressIndicator` is shown inside the Next button while `submitting == true`; spec explicitly says "No spinner overlay on the button itself" — loading state must surface via per-step UI, button just disables — `dart/lib/ui/auth_screen.dart:1887-1895`

- [ ] [MAJOR] spec §11.3 "QR center disc color": center logo disc background uses `context.palette.windowBgActive` (theme-variable); spec requires fixed `#40A7E3` fill — `dart/lib/ui/auth_screen.dart:889`

- [ ] [MAJOR] spec §11.5 "'Didn't get the code?' dialog": dialog only shows "Edit Phone Number" and "OK"; spec says it must offer alternate delivery options (SMS, email, other session) — `dart/lib/ui/auth_screen.dart:137-175`

- [ ] [CRITICAL] spec §11.6 "Reset Account action broken": "Reset Account" button in `_showResetAccountDialog` only calls `Navigator.of(ctx).pop()` — no engine call is made; server-side 7-day account reset is never triggered, interaction is completely broken — `dart/lib/ui/auth_screen.dart:372-382`

- [ ] [MAJOR] spec §11.7 "Signup avatar — no in-app crop": tapping the signup avatar opens `PhotoCropEditor.open()`; spec says "no in-app crop dialog in signup flow" — only system photo picker then direct upload — `dart/lib/ui/auth_screen.dart:187-197`

- [ ] [CRITICAL] spec §11.7 "termsLock dialog missing": `AuthStateData` has no `termsLock` field and `_buildSignUp` never shows a terms-acceptance dialog; spec says "Terms acceptance dialog gates submit when server sets `termsLock`" — entirely absent from both `dart/lib/models/engine_models.dart:105-168` and `dart/lib/ui/auth_screen.dart:673-760`

# Audit: §12 Calls UI

- [ ] [CRITICAL] spec §12.2 "Signal Bars in MinimisedCallBar": `_SignalBars` in `call_screen.dart` uses `barWidth=3px` (spec: 2px, 50% over), `skip=1px` (spec: 2px, 50% under), and heights [3,6,9,12] px (spec: [4,6,8,10] px). The `_SignalBarsPainter` in `call_panel.dart` is correct; `call_screen.dart` has a separate wrong implementation used by `MinimisedCallBar` — `call_screen.dart:1374-1377`

- [ ] [MAJOR] spec §12.1 "Answer button ripple animation": spec says "ripple radius tracks ringtone peak audio level"; code drives ripple with a fixed 2000ms looping `AnimationController` with no audio input — `call_panel.dart:117-121,932-960`

- [ ] [MAJOR] spec §12.1 "Answer button ripple anchoring": spec says ripple is "anchored at 135°"; code draws symmetrical full concentric circles with no directional anchor — `call_panel.dart:932-960`

- [ ] [MAJOR] spec §12.4 "Camera button active/disabled state": spec says "Active = camera glyph; disabled = crossed-out camera"; code always shows `Icons.videocam_outlined` with no `isActive` tracking and `_onCameraTap` does not toggle or track camera state — `call_panel.dart:537-543`

- [ ] [MAJOR] spec §12.5 "Wide↔Narrow transition animation": spec says transition uses `st::slideWrapDuration` (≈150–200ms); `GroupCallPanel` switches between `_buildNarrowMode()` and `_buildWideMode()` directly via `LayoutBuilder` with no animation — `call_screen.dart:380-394`

- [ ] [MAJOR] spec §12.6 "kWideScale centred userpic in wide mode": spec says `kWideScale=5` is used for the centred large avatar tile in wide mode; code shows a generic `Icons.videocam_off` placeholder with no large speaker userpic when no video stream is active — `call_screen.dart:309-362`

- [ ] [MAJOR] spec §12.7 "Big mute button Lottie animation": spec says "36×36 Lottie icon" with dedicated Lottie segment per state transition; code uses `AnimatedSwitcher` with plain `Icons.mic`/`Icons.mic_off`, no Lottie — `call_screen.dart:832-860`

- [ ] [MAJOR] spec §12.8 "MinimisedCallBar muted-by-self gradient": spec says `groupCallMuted1→groupCallMuted2` are gray colors; code returns `[Color(0xFF5B6BBE), Color(0xFF7B68EE)]` (blue-purple) for `_CallBarState.muted` — `call_screen.dart:1116-1118`

- [ ] [MAJOR] spec §12.8 "Gradient transition duration": spec says `_switchStateAnimation` duration = `|toState − fromState| × universalDuration` (proportional); code uses a fixed `Duration(milliseconds: 150)` for every state transition — `call_screen.dart:1024-1027`

# Audit: §13 Mobile / Web Compatibility Notes

- [ ] [MAJOR] spec §13.5 "hover fallback on mobile-web": `TelegramTooltip` uses only `MouseRegion` (hover-only); no `GestureDetector` long-press path exists, so all tooltips (folder-tab labels, sidebar buttons, compose-area buttons, etc.) are completely inaccessible on touch devices / mobile-web. Spec says signal-bar tooltips, pinned-bar previews, and reaction-bar pops need a long-press fallback on mobile — `telegram_tooltip.dart` has none — `dart/lib/ui/telegram_tooltip.dart`

# Audit: §14 Settings — General & My Account

- [ ] [MAJOR] spec §14.2.3 "Cover second-line content": spec says the middle slot (settingsPhoneTop=37px) must show the **User ID** (numeric) with right-click "Copy ID" context menu; code shows `account?.phone ?? ''` (phone number) with "Copy Phone" menu instead — `settings_screen.dart:625-635`

- [ ] [MAJOR] spec §14.3 "Folders row visibility": spec says Folders row is conditionally shown only when the user has chat folders enabled or server `dialog_filters_enabled` is true; code always renders the Folders row unconditionally — `settings_screen.dart:247-257`

- [ ] [MAJOR] spec §14.4 "Scale preview position": spec says `ScalePreview` floats **above** the slider thumb during drag; code renders the preview as a Column child **below** the slider row, not as a floating overlay above the thumb — `settings_screen.dart:1275-1350`

- [ ] [MAJOR] spec §14.5 "Profile section order": spec order is §14.5.3 Name/Phone/Username → §14.5.4 Personal Channel & Color → §14.5.5 Birthday → §14.5.6 Accounts; code renders Birthday before Personal Channel & Color, reversing §14.5.4 and §14.5.5 — `my_profile_page.dart:279-365`

- [ ] [MAJOR] spec §14.5.1 "Online status": spec shows the user's actual online status in `settingsCoverStatus` style below the name; code always hardcodes the string `'online'` regardless of actual account state — `my_profile_page.dart:659`

- [ ] [MAJOR] spec §14.5.2 "Bio auto-save on overshoot": spec says auto-save fires even when char count is negative (server rejects the save); code returns early in `_saveBio` when `value.length > bioLimit`, blocking the debounced save entirely when over the limit — `my_profile_page.dart:155`

- [ ] [MAJOR] spec §14.5.2 "Bio formatter cap for non-premium users": spec says the InputField accepts up to `premiumLimit * 2 = 280` chars for all users so the negative counter can be shown; code uses `LengthLimitingTextInputFormatter(maxLen * 2)` which caps non-premium users at 70*2=140 chars instead of 280 — `my_profile_page.dart:545`

- [ ] [MAJOR] spec §14.5.6.1 "Account context menu order and items": spec lists Copy Phone → Mark All Chats as Read → Activate (inactive only) → Log Out (hidden for active); code inserts an extra "Open in New Window" item first (not in spec for this context menu) and orders Activate before Mark All Chats as Read — `my_profile_page.dart:1649-1683`

- [ ] [MAJOR] spec §14.6.1 "Built-in theme names": spec lists four themes as Default (light), Day (blue tint), Dark, Night Blue; code uses Classic, Day Blue, Night, **Night Green** — the fourth preset is Night Green (`night_green`) instead of Night Blue — `chat_settings_screen.dart:493-499`

- [ ] [MAJOR] spec §14.6.3 "Edit Current Theme visibility": spec says the "Edit Current Theme" button "only appears when the currently-applied theme is a cloud theme owned by the user"; code always renders this button unconditionally with no ownership or cloud-theme check — `chat_settings_screen.dart:272-288`

# Audit: §15 Settings — Notifications

- [ ] [CRITICAL] spec §15.6 "Ringtones Box — play on select": clicking any radio option (Default, No sound, or custom tone) does NOT play audio preview; spec requires `playSound()` on every radio tap. Code only calls `setState(() => _selectedId = value)` with no sound playback whatsoever — broken interaction — `dart/lib/ui/notifications_settings_screen.dart:3477`

- [ ] [CRITICAL] spec §15.3 "Notification Preview userpic — name unchecked": spec says unchecked "Name" → shows app logo; code shows `Icons.chat_bubble` (generic icon), not the app logo — wrong element entirely — `dart/lib/ui/notifications_settings_screen.dart:2914-2918`

- [ ] [MAJOR] spec §15.3 "Notification Preview position": preview bubble is embedded between "Desktop notifications" toggle and "Flash/bounce" toggle inside `_buildGlobalSettings`; spec describes §15.2 (three toggles + volume slider) and §15.3 (preview) as separate sequential sections — wrong element order, preview appears mid-section instead of after all three global toggles — `dart/lib/ui/notifications_settings_screen.dart:226-286`

- [ ] [MAJOR] spec §15.6 "Upload Sound button — ringtonesBoxButton padding": spec says `ringtonesBoxButton` style uses `padding margins(56, 10, 22, 8)` (56 px left); code uses `EdgeInsets.fromLTRB(25, 10, 22, 8)` — left padding is 25 px instead of 56 px (55 % deviation) — `dart/lib/ui/notifications_settings_screen.dart:3564`

- [ ] [MAJOR] spec §15.11.3 "Sample notification userpic — notifyPhotoSize": spec defines `notifyPhotoSize = 62 px` for the sample notification card userpic; code renders `width: 48, height: 48` (22.6 % smaller) — `dart/lib/ui/notifications_settings_screen.dart:946-952`

- [ ] [MAJOR] spec §15.11.2 "Multi-Display selector label — ScreenDisplayLabel": spec says row label is built as `"{ScreenDisplayLabel} (WxH)"` using the OS-provided display name, falling back to `"Display (WxH)"` only when the name is empty; code always uses the hardcoded `"Display ${i + 1} (WxH)"` and never reads the actual platform display name — `dart/lib/ui/notifications_settings_screen.dart:611-614`

# Audit: §16 Settings — Privacy & Security

- [ ] [CRITICAL] spec §16.3.0 "EditPrivacyBox exceptions": "Always Allow" and "Never Allow" exception buttons are entirely absent from all privacy setting editors — no peer-list picker for exception management; spec requires two `SlideWrap`-gated link rows with peer pickers for each privacy key — `dart/lib/ui/privacy_settings_screen.dart` (lines 2561–2604)

- [ ] [CRITICAL] spec §16.11 "Lottie icons": All animated icons are replaced with a plain custom `_AnimatedSettingsIcon` (Flutter icon + scale animation); spec requires named Lottie assets: `cloud_password/intro` (CloudPasswordStart), `cloud_password/password_input` (CloudPasswordInput, interactive), `local_passcode_enter` (LocalPasscodeCreate/Check), `ttl` (GlobalTTL header, looping), `blocked_peers_empty` (blocked users empty state) — `dart/lib/ui/privacy_settings_screen.dart`

- [ ] [MAJOR] spec §16.3.7 "Messages from Non-Contacts": privacy row is appended after Groups & Channels (12th position) instead of after Voice Messages (7th position); spec §16.3 defines order as Phone→Last Seen→Profile Photo→Forwards→Calls→Voice Messages→**Messages**→Birthday→Gifts→Bio→Saved Music→Groups & Channels — `dart/lib/ui/privacy_settings_screen.dart` (lines 851–897)

- [ ] [MAJOR] spec §16.2.7 "Active Sessions current device userpic": current session row uses 42px `_DeviceUserpic` (same as all other session rows); spec requires 70px userpic for the current device displayed at the top of the screen — `dart/lib/ui/active_sessions_screen.dart` (line 718)

- [ ] [MAJOR] spec §16.2.2 "GlobalTTL footer link": footer renders plain `Text` with no interactive element; spec requires `lng_settings_ttl_after_about_link` clickable link that opens a peer-list box to apply the chosen TTL to existing chats — `dart/lib/ui/privacy_settings_screen.dart` (lines 4848–4857)

- [ ] [MAJOR] spec §16.3.3 "Profile Photo public photo crop": tapping "Set Public Photo" / "Update Public Photo" calls `FilePicker.platform.pickFiles` and uploads directly; spec requires opening a photo editor with ellipse crop before upload — `dart/lib/ui/privacy_settings_screen.dart` (lines 2017–2042)

- [ ] [MAJOR] spec §16.6 "File Confirmations section conditional": `_buildConfirmationExtensionsSection` always returns content unconditionally; spec says section is shown only if the user has added no-warning extensions or disabled IP-reveal warning — `dart/lib/ui/privacy_settings_screen.dart` (lines 1018–1082)

- [ ] [MAJOR] spec §16.4 "Archive and Mute section conditional": `_buildArchiveAndMuteSection` returns content whenever `_archiveLoaded` is true with no further gating; spec says section is shown only if `showArchiveAndMute` is true or user is Premium — `dart/lib/ui/privacy_settings_screen.dart` (lines 900–907)

- [ ] [MAJOR] spec §16.2.7 "Terminate All Sessions button style": "Terminate" action in confirmation dialog uses `TextButton.styleFrom(foregroundColor: Colors.red)` (red text only); spec requires `st::attentionBoxButton` — a filled red button, matching the destructive-action pattern — `dart/lib/ui/active_sessions_screen.dart` (lines 342–355)

- [ ] [MAJOR] spec §16.2.3.1 "AutoLockBox custom option label": custom sentinel option is labeled `'Custom'`; spec labels it `'If away for...'` and the TimeInput field reveals inline on selection (spec token `kCustom` is the "If away for..." row) — `dart/lib/ui/privacy_settings_screen.dart` (line 5742)

- [ ] [MAJOR] spec §16.3.7 "Charge Stars — Remove fee for button": `_buildChargeStarsSection` renders the slider and commission info but omits the `lng_messages_privacy_remove_fee` ("Remove fee for") button row that opens the no-paid-messages exceptions picker — `dart/lib/ui/privacy_settings_screen.dart` (lines 6160–6252)

# Audit: §17 Settings — Data, Storage & Advanced

- [ ] [MAJOR] spec §17.1 "Navigation row label": settings row is labeled "Advanced" but spec says label "Data and Storage"; AppBar title also says "Advanced" — `dart/lib/ui/settings_screen.dart:265`, `dart/lib/ui/advanced_settings_screen.dart:87`
- [ ] [MAJOR] spec §17.3.1 "AutoDownloadBox width": box uses `maxWidth: 364` but spec says `st::boxWidth` (320px, standard box width; 364px is `st::boxWideWidth` used for ProxiesBox/PowerSavingBox) — `dart/lib/ui/advanced_settings_screen.dart:1379`
- [ ] [MAJOR] spec §17.2.1 "ProxyRow status colors swapped": code assigns Online=`0xFF4CAF50` (green) and Available=accentColor (blue), but spec says Online=`st::proxyRowStatusFgOnline` (blue/accent) and Available=`st::proxyRowStatusFgAvailable` (green with ping ms) — `dart/lib/ui/advanced_settings_screen.dart:2534`
- [ ] [MAJOR] spec §17.2.1 "Missing Connecting proxy status": `_ProxyStatus` enum has only 4 values (online/available/checking/unavailable); spec requires a distinct 5th state `Connecting` with label `lng_proxy_connecting` — `dart/lib/ui/advanced_settings_screen.dart:2146`
- [ ] [MAJOR] spec §17.6.1 "Show taskbar icon shown on macOS": checkbox is rendered on all platforms; spec says only render when `Platform::SkipTaskbarSupported()` is true (Windows + some Linux WMs), hidden on macOS — `dart/lib/ui/advanced_settings_screen.dart:582`
- [ ] [MAJOR] spec §17.6.2 "Monochrome tray visible on Windows": `AnimatedSize` shows monochrome tray checkbox whenever tray is enabled regardless of platform; spec says only visible when `Platform::HasMonochromeSetting()` is true (macOS + certain Linux DEs, not Windows) — `dart/lib/ui/advanced_settings_screen.dart:594`
- [ ] [MAJOR] spec §17.7.1 "PowerSavingBox missing top shadow": spec requires a pinned 1px top shadow widget of height `st::lineWidth` above the scroll area; code has no such shadow — `dart/lib/ui/advanced_settings_screen.dart:1928`
- [ ] [MAJOR] spec §17.7.1 "Battery auto-toggle missing Windows/macOS": `_detectBattery()` returns early with `if (!Platform.isLinux)`; spec says auto-toggle renders on Windows 10+, macOS Low Power Mode, and Linux via UPower — `dart/lib/ui/advanced_settings_screen.dart:1863`
- [ ] [MAJOR] spec §17.7.4 "OpenGL toggle hidden on Windows": guard is `!Platform.isMacOS && !Platform.isWindows`, so the toggle never appears on Windows; spec says `if constexpr (!Platform::IsMac())` — show on both Windows and Linux, hide only on macOS — `dart/lib/ui/advanced_settings_screen.dart:737`
- [ ] [MAJOR] spec §17.9 "Screen reader section always shown": `_buildScreenReader` returns the toggle unconditionally; spec says the entire block is only shown when a screen reader is detected AND the optimization mode is currently disabled — `dart/lib/ui/advanced_settings_screen.dart:1036`
- [ ] [MAJOR] spec §17.10 "Missing Download state with progress": update `_UpdateState` enum has no Download state; spec requires a `lng_settings_downloading_update` label with an `lt_progress` token showing downloaded/total bytes as the update downloads — `dart/lib/ui/advanced_settings_screen.dart:25`

# §18 Settings — Folders audit

- [ ] [CRITICAL] spec §18.6.1 "Emoji button position": spec places emoji button at `point(-65, 22)` = 65px from right edge of name field; code uses `Positioned(right: 40, ...)` — 40px from right (38% deviation of 65px) — `dart/lib/ui/folders_settings_screen.dart:1820-1829`

- [ ] [CRITICAL] spec §18.6.4 "Tag Color — Premium gate missing": spec says non-Premium clicks must open `PremiumPreviewBox(FilterTags)`; `_TagColorSection` receives no `isPremium` param and `onSelect` callback always applies the color index with no premium check — `dart/lib/ui/folders_settings_screen.dart:1922-1928,2059-2069`

- [ ] [CRITICAL] spec §18.6.5 "Invite Link context menu incomplete": spec requires Copy / Share / QR Code / Name it / Delete; `_showLinkContextMenu()` only shows "Copy Link" and "Delete Link" — `dart/lib/ui/folders_settings_screen.dart:1533-1555`

- [ ] [CRITICAL] spec §18.9 "Show Link Box wrong Lottie asset": spec uses `"cloud_filters"` Lottie animation (74×74px); code loads `'assets/animations/filters.json'` (same asset as the §18.2 main header) — `dart/lib/ui/folders_settings_screen.dart:2597-2601`

- [ ] [CRITICAL] spec §18.3 "Remove flow missing chatlist-link confirmation": spec requires showing "This will also delete all invite links" confirmation when the folder has chatlist links; `_removeFolder()` only branches on `folder.isChatList` — folders with invite links but `isChatList == false` skip the warning entirely — `dart/lib/ui/folders_settings_screen.dart:147-155`

- [ ] [CRITICAL] spec §18.6.2 "FilterChatsPreview missing individual peer rows": spec §18.6.2.2 says every selected peer occupies its own 44px row below the type-flag rows; `_FilterChatsPreview` only renders `_PreviewTypeInfo` (type-flag) rows — individually selected chats from `folder.chatIds` are never displayed or editable inside the dialog — `dart/lib/ui/folders_settings_screen.dart:3546-3575`

- [ ] [CRITICAL] spec §18.7 "Include/Exclude Chats Picker has no peer list": spec is a `PeerListBox` with actual chat rows allowing individual-chat selection; `_IncludeTypePicker` / `_ExcludeTypePicker` only render type-toggle rows — there is no way to add or remove specific chat peers from within these pickers — `dart/lib/ui/folders_settings_screen.dart:3667-4080`

- [ ] [MAJOR] spec §18.6.1 "Character counter right position": spec places counter at `point(75, 27)` from right edge = 75px from right; code uses `Positioned(right: 65, ...)` — 10px short (13% deviation) — `dart/lib/ui/folders_settings_screen.dart:1803-1817`

- [ ] [MAJOR] spec §18.12 "Tab View threshold uses wrong width reference": spec gates the "View" subsection on main-window width ≥ 452px (`widget()->width() >= minimumWidth + windowFiltersWidth`); code uses `LayoutBuilder` constraints (`constraints.maxWidth < 452`) which reflects the settings-panel content width, not the full window width — hides the section too aggressively when the settings panel is narrower than 452px while the window is wide — `dart/lib/ui/folders_settings_screen.dart:448-472`

# Audit: §19 Settings — Sessions, Power Saving & Language

- [ ] [CRITICAL] spec §19.2.1 "Rename this device" link label: spec says label is `tr::lng_settings_rename_device` → "Rename this device", code renders just "Rename" (text truncated by >25%) — `dart/lib/ui/active_sessions_screen.dart:707`

- [ ] [CRITICAL] spec §19.6.1 "Official App" info row missing from SessionInfoBox: spec lists `ayu_SessionInfoOfficialApp` ("Yes"/"No") as a required AyuGram-added row in the session detail view; code only renders Application, System, IP Address, Location — `dart/lib/ui/active_sessions_screen.dart:477-512`

- [ ] [MAJOR] spec §19.3 device type classification: spec says sessions are "classified by API ID first, then keyword detection"; code only does keyword matching on device/platform/appName strings with no `api_id` field check at all — `dart/lib/ui/active_sessions_screen.dart:51-82`

- [ ] [MAJOR] spec §19.6 `sessionBigName` max height 29px: spec token `sessionBigName` = "20px semibold, max height 29px" (fits one line); code uses `maxLines: 2` with no height constraint, allowing two-line device names (~52px tall) — `dart/lib/ui/active_sessions_screen.dart:463-467`

- [ ] [MAJOR] spec §19.8.1 RenameBox button order: spec says `addLeftButton(Save)` → Save is left-placed, Cancel right; code's `AlertDialog.actions` list has Cancel first (left), Save second (right) — `dart/lib/ui/active_sessions_screen.dart:601-616`

- [ ] [MAJOR] spec §19.9.1 SelfDestructionBox (Sessions variant) button order: spec says "Save button: left-placed, `tr::lng_settings_save()`"; code's Row has Cancel as first child (left) and Save as second (right) — `dart/lib/ui/active_sessions_screen.dart:264-291`

- [ ] [MAJOR] spec §19.12 PowerSavingBox button order: spec says Save + Cancel (Save is the primary/left-placed action per Telegram GenericBox convention); code's Row has Cancel as first child (left) and Save as second (right) — `dart/lib/ui/advanced_settings_screen.dart:2015-2039`

# §20 Media Viewer / Lightbox — Audit Findings

- [ ] [CRITICAL] spec §20.8 "Bottom-Right Toolbar": Share button (#3 in right-to-left order, "stories + shareable") is entirely absent from `_buildToolbar` — `media_viewer.dart:2872`
- [ ] [CRITICAL] spec §20.13 "Picture-in-Picture": PiP is implemented as an in-app `Positioned` overlay widget, not a separate always-on-top OS window; it is invisible behind other applications (spec requires `Qt::WindowStaysOnTopHint`) — `media_viewer.dart:3947`
- [ ] [CRITICAL] spec §20.17 "Stories Viewer Integration": Stories viewer (`Stories::View`, 540×960px aspect-fit, sibling thumbnails, collapsed captions) is completely unimplemented — `media_viewer.dart` (absent)
- [ ] [CRITICAL] spec §20.16 "Context Menu": Stealth Mode guard is `widget.mediaMessages.isEmpty` (line 2769), which is always `false` when the viewer is open (viewer is only opened with non-empty messages) — item can never appear — `media_viewer.dart:2768`
- [ ] [CRITICAL] spec §20.8 "Copy Image / Copy Frame" (Ctrl+C): `_copyImageToClipboard` and `_copyVideoFrame` both call `Clipboard.setData(ClipboardData(text: path))` — copies a file-path string, not actual image/frame bytes — keyboard shortcut Ctrl+C is functionally broken — `media_viewer.dart:2675,2682`
- [ ] [CRITICAL] spec §20.8 "Draw": Draw button calls `Process.run('xdg-open', [path])` — opens an external system app instead of an in-app photo editor; CLAUDE.md bans placeholders — `media_viewer.dart:2912`
- [ ] [MAJOR] spec §20.4 "Zoom and Pan / Ctrl+0": Ctrl+0 toggles between zoom level 0 and hardcoded level 3 (`_animateZoomTo(3)`); spec requires toggle between 1:1 and `kZoomToScreenLevel` (fit-to-screen) — `media_viewer.dart:954`
- [ ] [MAJOR] spec §20.8 "Bottom-Right Toolbar" order: spec right-to-left is More→Rotate→Share→Save→Draw→OCR; code right-to-left is More→Rotate→Save→OCR→Draw — OCR and Draw are swapped and Share is absent — `media_viewer.dart:2872`
- [ ] [MAJOR] spec §20.10 "Video Playback Controls": video controls panel uses `Color(0xCC000000)` (alpha 204); spec specifies `mediaviewSaveMsgBg` which is `Color(0xB2000000)` (alpha 178) — ~14% opacity deviation — `media_viewer.dart:2187`
- [ ] [MAJOR] spec §20.9 "Caption Display": caption renders plain `SelectableText` with no spoiler span support and no clickable timestamp links that seek video — `media_viewer.dart:2488`
- [ ] [MAJOR] spec §20.15 "Save/Download Toast": check icon rendered as first Row child behind `55px` left padding (lands at ~x=55); spec places it at absolute (23, 21)px within the toast container — `media_viewer.dart:2567`
- [ ] [MAJOR] spec §20.16 §20.8.1 item 3 "Retract Vote": "Retract Vote" (currentPollAnswer set, poll open) is absent from `_buildMediaMenuItems` — `media_viewer.dart:2737`
- [ ] [MAJOR] spec §20.16 item 13 "Show All Photos / Files": `_showAllMedia` calls `Navigator.of(context).pop()` instead of opening a media overview screen — `media_viewer.dart:2701`
- [ ] [MAJOR] spec §20.16 item 1 "Cancel Download": `_cancelDownload` shows a toast without invoking any engine call to cancel the in-progress download transfer — `media_viewer.dart:2705`
- [ ] [MAJOR] spec §20.19.1 "Geometry Animation": zoom animation uses `Curves.easeOutCubic`; spec §20.19.1 Flutter mapping requires `Curves.linear` for all geometry interpolation — `media_viewer.dart:383`

# Audit: §2 Chat List Sidebar

- [ ] [CRITICAL] spec §2 "Horizontal tab strip right-click context menu": "Edit Folder" action is a no-op stub — spec says "edit, remove, setup" all work; code does `case 'edit': break;` (interaction completely broken) — `dart/lib/ui/chat_list_panel.dart:2325`
- [ ] [CRITICAL] spec §2 "Horizontal tab strip right-click context menu": "Edit Folders" (setup) action is a no-op stub — spec says setup opens folder config; code does `case 'setup': break;` (interaction completely broken) — `dart/lib/ui/chat_list_panel.dart:2331`
- [ ] [MAJOR] spec §2 "Search Bar / Top Peers strip": strip shows DM chats only — spec says "Top Peers strip (horizontal, 46px avatars)" with no type restriction; code filters `where((c) => c.type == ChatType.dm)`, excluding groups and channels entirely — `dart/lib/ui/chat_list_panel.dart:2452-2454`
- [ ] [MAJOR] spec §2 "Chat List Rows / Unread counter pill": hover ("Over") badge colors `dialogsUnreadBgOver` / `dialogsUnreadBgMutedOver` are never applied — spec explicitly defines these variants for hovered rows; `_HoverBuilder` tracks `isHovered` but the badge color logic ignores it, always using default (non-hover) colors — `dart/lib/ui/chat_list_panel.dart:100-103`

# Audit: §21 Create Group / Channel Wizard

- [ ] [CRITICAL] spec §21.5.1 "Topics toggle row": `_isForum` flag is loaded from `getChatPermissionFlags` and stored in state but never rendered — the forum/Topics enable toggle row is entirely absent from `_buildPermissionToggles`; all other toggles present (joinToSend, slowmode, noForwards) but forum is missing — `create_group_wizard.dart:2524`

- [ ] [MAJOR] spec §21.4.1 "Username validation — bad symbols": regex `'^[A-Za-z][A-Za-z0-9_]*$'` rejects usernames starting with `_` (e.g. `_testchan`); spec §21.4.1 says only starting with a digit is forbidden, underscore-leading names are valid `[A-Za-z0-9_]` — used in both `_WizardDialogState._onUsernameChanged` (line 388) and `_EditPeerTypeBoxState._onUsernameChanged` (line 2400)

- [ ] [MAJOR] spec §21.2 "Errors — CHANNELS_TOO_MUCH": `_submitInfo()` and `_submitGroup()` map `CHANNELS_TOO_MUCH` to a plain error text string ("You have created too many channels"); spec requires opening a premium limit box (`showPremiumLimitBox`) — `create_group_wizard.dart:575,614`

- [ ] [MAJOR] spec §21.3 "'Invite via Link' button": condition `_inviteLink.isNotEmpty || widget.type == _WizardType.group` causes the button to always render for new-group flow where no invite link has been created yet (`_createdChatId` is empty, `_inviteLink` is always empty); tapping the button silently does nothing — spec requires button only when `canHaveInviteLink()` — `create_group_wizard.dart:1139`

- [ ] [MAJOR] spec §21.4.2 "Premium upsell button": `_PublicLinksLimitBox` has no "Increase Limit" CTA button; spec §21.4.2 requires a premium gradient button ("Increase Limit") at the bottom for non-Premium users that opens the Premium landing page; only a plain "Close" button is present — `create_group_wizard.dart:2148`

- [ ] [MAJOR] spec §21.4.2 "Description — premium variant": `_PublicLinksLimitBox` always shows the non-premium/final text ("Revoke the link from one of the older channels you don't need"); spec §21.4.2 requires showing the premium upsell text ("Subscribe to Telegram Premium to double the limit to 20 public links") for non-Premium users — `create_group_wizard.dart:2123`

- [ ] [MAJOR] spec §21.5 "Username section — draggable usernames list": `_EditPeerTypeBox` renders a single username `TextField` for the public link; spec §21.5 requires a draggable list of collectible usernames for existing public channels/groups, not a single field — `create_group_wizard.dart:2743`

- [ ] [MAJOR] spec §21.7 "`newGroupLinkPadding` = margins(4, 27, 4, 21)": the username field area in SetupChannelBox step uses `SizedBox(height: 16)` between the private radio row and the username section label; spec says 27px top padding for the link area — `create_group_wizard.dart:976`

- [ ] [MAJOR] spec §21.2.1 "Change-photo overlay — Camera option": the userpic popup menu always includes a "Camera" item (which silently falls back to `_pickPhoto()` / file picker); spec §21.2.1 says Camera is only shown "if `CameraBox` available" — `create_group_wizard.dart:294`

# §22 Forum Topics UI — Audit Findings

- [ ] [CRITICAL] spec §22.3 "Topic Row Unread Mark": "Mark as Unread" interaction broken — `case 'mark_read':` handler only calls `markChatRead()` when `hasUnread == true`; when `hasUnread == false` and user clicks "Mark as Unread", nothing happens (no `markChatUnread` call) — `chat_list_panel.dart:5039-5042`

- [ ] [MAJOR] spec §22.8.1 "Topic Context Menu Conditional Matrix": "Edit Topic" appears in topic row right-click menu — spec explicitly states it is reachable only from the profile/info menu (`addManageTopic`), NOT from `fillContextMenuActions` (row right-click); code adds it unconditionally when `topic.canEdit` — `chat_list_panel.dart:4986-4991`

- [ ] [MAJOR] spec §22.8.1 "Topic Context Menu Conditional Matrix": "Hide/Show General Topic" exposed in topic row right-click menu — spec states "no menu entry exposes it in `fillContextMenuActions`; toggled via separate `toggle_topics_box.cpp` flow"; code adds `toggle_hidden` item when `topic.isGeneral && topic.canEdit` — `chat_list_panel.dart:4998-5003`

- [ ] [MAJOR] spec §22.8 "Topic List Right-Click": 4 items missing from `_showTopicListContextMenu` — spec says this menu should include Manage Group, Add Members, Video Chat, and Report; code only has Create Topic / View Group Info / View as Messages / Search / Leave — `chat_list_panel.dart:4441-4470`

- [ ] [MAJOR] spec §22.4 "Forum Group in Main Chat List": expanded left-edge bar animation missing from `ForumChatListRow` — spec says "Left-edge animated bar (`dialogsBgActive`, `roundRadiusLarge`) when forum's topic list is shown as child"; `ForumChatListRow` has no such animated bar — `chat_list_row.dart:1739-1867`

- [ ] [MAJOR] spec §22.4 "Forum Group in Main Chat List": `_rowHeightWithTags = 96.0` is defined but never applied — `effectiveHeight` is hardcoded to `_rowHeight` (80px) at all times; spec says height should be 96px when tags are present — `chat_list_row.dart:1729,1741`

- [ ] [MAJOR] spec §22.3.1 "TopicsView Separator Rule": `_TopicsPreview` separates topic names with commas (`', '` TextSpan) instead of an 8px blank gap — spec says "consecutive topic titles are separated by a blank gap (topicsSkip=8px), not a rule"; no commas exist in the TDesktop implementation — `chat_list_row.dart:1926-1933`

- [ ] [MAJOR] spec §22.7 "Topic Info Panel Cover": default (colored bubble) icon rendered at 36px instead of spec's 32px — spec says "Default: 32px circle with bold 15px letter" inside the 36×36px cover slot; code uses `size: 36` for `ForumTopicIcon` in the cover (deviation: (36-32)/32 = 12.5%) — `info_panel.dart:1314-1318`

- [ ] [MAJOR] spec §22.3 "Topic Row Style": unread mark dot (spec `unreadMarkDiameter: 8px`) never rendered — `ForumTopic` model has no `isUnreadMark` field; `_ForumTopicRow` never shows an unread dot for topics marked read-but-flagged; only `unreadCount > 0` triggers badge — `engine_models.dart:343-407`, `chat_list_panel.dart:4812-4927`

# §23 Scheduled Messages — Audit Findings

- [ ] [CRITICAL] spec §23.2 "Repeat Period (Premium)": non-Premium users clicking the lock icon does nothing (onTap is null); spec says clicking opens a Premium promo toast — `dart/lib/ui/choose_datetime_box.dart:846`

- [ ] [CRITICAL] spec §23.4 "Compose Controls": pressing the send button in scheduled view calls `widget.onSend()` → `_sendMessage(scheduleDate: 0)` which sends immediately; spec says every send action from the scheduled view must open the schedule picker first — `dart/lib/ui/chat_view.dart:15405-15406`

- [ ] [MAJOR] spec §23.1 "kMinimalSchedule = 10 seconds": `_validateTime()` checks `dt.isBefore(DateTime.now())` (0-second offset), never enforcing the 10-second minimum; code accepts schedule times 1–9 seconds in the future — `dart/lib/ui/choose_datetime_box.dart:612`

- [ ] [MAJOR] spec §23.2 "Send when online Button": code uses `Icons.more_vert` with Material's `showMenu<String>` (default popup style) and `Icon(Icons.person_outline)` for the action; spec says the button must be an `IconButton` styled as `infoTopBarMenu` opening a `PopupMenu` styled `popupMenuWithIcons` with icon `menuIconWhenOnline` — `dart/lib/ui/choose_datetime_box.dart:714-742`

- [ ] [MAJOR] spec §23.4 "Selection mode — Send Now": the "SEND NOW" button is shown whenever `isScheduledView` is true regardless of selection state; spec says it must only be visible when `canSendNowCount == selectedCount` (all selected items allow send-now) — `dart/lib/ui/chat_view.dart:9737-9768`

- [ ] [MAJOR] spec §23.1 "CanScheduleUntilOnline(peer)": code checks only `chat?.type == ChatType.dm && !isSelf`; spec requires additionally verifying non-bot, last-seen not hidden, no stars-per-message, no notifications-user status — `dart/lib/ui/chat_view.dart:1745`

- [ ] [MAJOR] spec §23.6 "Reschedule Action — pre-filled repeat period": `showChooseDateTimeBox` is called without passing the message's current `scheduleRepeatPeriod`; reschedule picker always defaults to 0 (Never) instead of pre-filling the existing period — `dart/lib/ui/chat_view.dart:1741-1746`

- [ ] [MAJOR] spec §23.8 "Processing Tip Toast": tip fires whenever `chatState.messages.any((m) => m.isVideo)` (any video in the list); spec says it fires only when navigating to the scheduled section with a `sentToScheduledId` that maps to a video (i.e., a video was just sent to scheduled) — `dart/lib/ui/chat_view.dart:870-875`

- [ ] [MAJOR] spec §23.8 "Processing-video tooltip": `_VideoProcessingTooltip` is rendered at a fixed `Positioned(left: 16, right: 16, top: 62)` with no message anchor; spec says the bubble must be anchored to the specific message's effect icon, pointing upward with `processingVideoTipShift = 8px` offset — `dart/lib/ui/chat_view.dart:18331-18334`

- [ ] [MAJOR] spec §23.6 "Send Now Confirmation Dialog": confirmation uses Material `AlertDialog` via `showDialog`; spec describes it as a Telegram-styled confirmation box (`ShowSendNowMessagesBox`) consistent with all other Telegram dialogs — `dart/lib/ui/chat_view.dart:1710-1716`

- [ ] [MAJOR] spec §23.6 "Send Now (single message) — grouped messages": `canSendNow` is computed only for the right-clicked message (`msg.allowsSendNow`), not verified for all group members; spec says all items in the group must allow send-now before the option appears; partial groups can be sent — `dart/lib/ui/chat_view.dart:1301-1308`

# §24 Keyboard Shortcuts — Audit

- [ ] [CRITICAL] spec §24.4 "Chat Actions": `recordVoice` command handler always returns `false` (stub) so Ctrl+R can never start voice recording — `readChat` (registered first, always returns true) consumes the event and `recordVoice` never fires — `dart/lib/ui/keyboard_shortcuts.dart:1105-1107`

- [ ] [MAJOR] spec §24.5 "Ctrl+Tab Chat Switcher": `chatSwitchOverlayReverse` handler calls the identical `showChatSwitchRequest?.call()` as the forward handler with no reverse indicator; `shell.dart` always opens `ChatSwitchOverlay` with `initialIndex: 1` regardless of direction — Ctrl+Shift+Tab does not go backwards as spec requires — `dart/lib/ui/keyboard_shortcuts.dart:1077-1080`, `dart/lib/ui/shell.dart:373-393`

- [ ] [MAJOR] spec §24.12.3 "Ctrl+Tab Chat Switcher grid navigation": Up/Down arrow keys in `ChatSwitchOverlay._handleHardwareKey` call `_movePrev()`/`_moveNext()` (move by 1), but spec says Up/Down must move by `_shownPerRow` to traverse grid rows; Left/Right/Tab correctly move by 1 — `dart/lib/ui/chat_switch_overlay.dart:86-93`

- [ ] [MAJOR] spec §24.11 "Scope & Priority": `isMediaViewerOpenCallback` uses `Navigator.of(context).canPop()` which returns `true` for any pushed route (settings screens, dialogs), not specifically when the media viewer is open — `mediaViewerVideoFullscreen` scope gating fires incorrectly — `dart/lib/ui/keyboard_shortcuts.dart:1049-1056`

- [ ] [MAJOR] spec §24.9 "Media Viewer Shortcuts / Zoom": Ctrl+* (asterisk/multiply) zoom-in shortcut missing — spec lists "Ctrl+Plus / Ctrl+= / Ctrl+*: Zoom in"; code only handles `equal`, `add`, `numpadAdd`, not `LogicalKeyboardKey.asterisk` or `numpadMultiply` — `dart/lib/ui/media_viewer.dart:936-943`

- [ ] [MAJOR] spec §24.9 "Media Viewer Shortcuts / Video Playback": Alt+Left and Alt+Right chapter-jump handlers are no-op stubs — code catches the events, returns `KeyEventResult.handled`, and does nothing (comment says "no-op if no chapters" but never checks chapters or calls any navigation) — `dart/lib/ui/media_viewer.dart:1003-1018`

- [ ] [MAJOR] spec §24.12.6 "Settings Shortcuts UI row height": Shortcuts settings screen command rows have no fixed height; effective rendered height ≈34 px (14 px font × 1.2 line-height + 10+8 px padding from `noIconPadding`), while spec §24.12.6 specifies 52 px row height; `SettingsStyle.rowHeight = 41` is not applied to command rows and is itself below the 52 px target — `dart/lib/ui/shortcuts_settings_screen.dart:550-551`, `dart/lib/ui/settings_style.dart:33,40`

# Audit Chunk 24 — §25 Theming & Color System

- [ ] [CRITICAL] spec §25.8.4 / §25.17.4 "pattern positive-intensity SoftLight": pattern overlay uses `ShaderMask(blendMode: softLight, shader: white, child: pattern)` then wraps in `Opacity`, which computes `softLight(pattern, white)` — not the spec-required `softLight(gradient_background, pattern)` at patternOpacity; entire positive-intensity pattern rendering mode produces wrong composite — `dart/lib/theme/wallpaper.dart:476-485`

- [ ] [CRITICAL] spec §25.17.5 "CountAverageColor exhaustive pixel mean": `computeAverageColor()` operates on raw compressed JPEG/PNG encoded bytes (not decoded ARGB pixel data), returning meaningless garbage; corrupts all adaptive service colors (`msgServiceBg`, `historyScrollBarBg`, etc.) for image wallpapers — `dart/lib/theme/wallpaper.dart:521-534`

- [ ] [CRITICAL] spec §25.6.3 "live preview via ApplyEditedPalette()": theme editor `onPaletteChanged` callback is wired as `(_) {}` (no-op), so editing any palette token never updates the running app palette; live preview is completely broken — `dart/lib/ui/chat_settings_screen.dart:431`

- [ ] [MAJOR] spec §25.17.4 "kDefaultIntensity = 50": `WallpaperData` default `patternIntensity` is 40, spec requires 50; wallpapers loaded without explicit intensity value render at wrong opacity (20% deviation) — `dart/lib/theme/wallpaper.dart:24`

- [ ] [MAJOR] spec §25.3.3 "Night theme bubble colors": Night theme preview card uses wrong indicator colors — `receivedBubble: Color(0xFF24292E)` (spec `msgInBg = #182533`, RGB 24,37,51 vs code RGB 36,41,46 — wrong hue/saturation) and `sentBubble: Color(0xFF265E8C)` (spec `msgOutBg = #2b5278`, RGB 43,82,120 vs code RGB 38,94,140) — `dart/lib/ui/chat_settings_screen.dart:486-487`

- [ ] [MAJOR] spec §25.9.3 "styling: bg st::boxBg, activeButtonBg for confirm button": `ThemeConfirmOverlay` uses hardcoded `Color(0xFF1E2C3A)` / `Colors.white` for background (instead of `palette.boxBg`) and `Color(0xFF3390EC)` / `Color(0xFF40A7E3)` for the Keep Changes button (Night spec `activeButtonBg = #2f6ea5`, code uses `#3390EC` — wrong color); overlay ignores palette and custom accent changes entirely — `dart/lib/ui/theme_confirm_overlay.dart:80-141`

- [ ] [MAJOR] spec §25.17.3 "_save: full-width bottom button at st::dialogsUpdateButton.height": theme editor Save button is placed in the header bar as a small `TextButton`, spec requires a full-width Save button pinned to the bottom of the editor below the scrollable token list — `dart/lib/ui/theme_editor.dart:262-265`

- [ ] [MAJOR] spec §25.17.3 "menu items: export, import, show (menuIconPalette)": theme editor three-dot menu third item is "Copy Palette Text" (clipboard copy) instead of spec's `lng_theme_editor_menu_show` which opens the palette file location in the file manager — `dart/lib/ui/theme_editor.dart:142-148`

- [ ] [MAJOR] spec §25.12.2 "cloud themes grid: 4 per row (kShowPerRow = 4)": cloud themes section default view is a horizontal scrollable `ListView` (not a grid); the 4-column grid only appears after tapping "Show All" — spec requires an always-visible 4-per-row grid layout — `dart/lib/ui/chat_settings_screen.dart:1864-1882`

# §26 Admin Tools — Audit Findings

- [ ] [CRITICAL] spec §26.1.6 "Admin Control Buttons": "Join Requests" button is missing entirely (spec says show when count > 0; no such row exists in `_buildAdminControlsSection`) — `dart/lib/ui/admin_tools.dart`
- [ ] [CRITICAL] spec §26.4.5 "Transfer Ownership": clicking Transfer button shows a toast stub (`showTelegramToast(context, 'Transfer ownership requires 2FA verification')`) instead of the required multi-step 2FA confirmation flow (dry-run → ConfirmBox → PasscodeBox → real MTPmessages_EditChatCreator) — `dart/lib/ui/admin_tools.dart`
- [ ] [CRITICAL] spec §26.5.7 "Filter Dialog": filter checkbox state is never passed to `_loadEvents()`; `widget.onApply()` is called with no arguments, so toggling any filter checkbox has zero effect on the admin log query — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.1.5 "Settings Buttons": "Direct Messages" row (icon `menuIconChats`, right value Off/Free/star-amount) is missing for channels with monoforum; the entire row and `showEditDirectMessagesBox()` flow are absent — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.1.5 "Settings Buttons": "Sign with Profile" toggle is missing; spec says it slides in when "Sign Messages" is toggled on (via `SlideWrap`), but code has no such row at all — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.1.5 "Settings Buttons": "Visible History" condition is wrong; spec says show only for "Private without location/discussion/forum", code shows it for all `!_isChannel` groups unconditionally — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.2.4 "Boosts Unrestrict Slider": spec says `kBoostsUnrestrictValues = 5` positions with values 1–5; code uses 6 positions (0–5) with an extra "Off" position at index 0 (`_boostsValues = [0,1,2,3,4,5]`, `max: 5, divisions: 5`) — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.2.5 "Charge Stars": spec says a `MediaSliderWheelless` discrete slider (non-linear steps 1…100 then tens, then hundreds up to server max) with commission label and USD estimate; code uses a freeform `TextField` for star count input instead of a discrete slider, and labels it "Charge Stars for Messages" instead of "Charge Stars" — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.2.6 "Convert to Supergroup": entire section missing; spec says show conversion suggestion when creator + member count > `kThresholdOffset = 1000`, with a toast on completion — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.2.1 / §26.12.2 "Permission dependency graph": `ViewMessages` dependency not implemented; toggling any send permission (SendPhotos, SendVideos, SendMusic, etc.) should auto-disable if `ViewMessages` is off, but code only implements the `EmbedLinks ↔ SendOther` pair — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.3.2 "Permission Toggles": "Edit rank" flag (`edit_rank`) is missing from `_EditRestrictedBoxState._otherFlags`; it is present in `_EditPeerPermissionsBox` but absent in the per-user restrict dialog — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.4.4 "Custom Title / Rank": admin rank field always initialised empty (`TextEditingController()`); it should be pre-populated with the existing admin's custom rank (`member.customRank`), as the restrict dialog correctly does — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.5.1 "Top Bar": userpic-to-title skip uses `SizedBox(width: 10)` = 10px; spec says `historyAdminLogTopBarUserpicSkip = 35px` — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.5.1 "Top Bar": search field slides in instantly via `setState`; spec says `historyAdminLogSearchSlideDuration = 150ms` animated slide-in — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.5.2 "Event Rendering": admin name (`event.userName`) rendered as plain text; spec says it must be a clickable link (`fromLink`) that opens the user's profile — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.5.2 "Event Rendering": quoted content rendered as a simplified inline block with a left-border; spec says quoted messages must render as full `HistoryView::Message` chat bubbles via `PrepareLogMessage()` with the message's avatar, media, and normal bubble chrome — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.5.4 "Empty State": empty state container width is hardcoded `300px`; spec says `historyAdminLogEmptyWidth = 260px` (15% deviation) — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.5.7 "Filter Dialog": filter section 1 checkbox labels are "New members" and "Removed members"; spec says they should read "New members/subscribers" and "Removed members/subscribers" and adjust based on channel/group context — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.6.4 "Single Link Info Box": joined users list (first page 20, subsequent 100 entries) and overlapping userpic strip (max `kMaxShownJoined = 3` avatars) are missing entirely; the info box only shows static counters — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.6.4 "Single Link Info Box": "Reactivate" button missing; spec says show it when link is expired (`progress >= 1.0`) but not revoked, for non-bot admins — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.6.6 "Create/Edit Link Form — Expire After": "Custom" option (opens date/time picker) is missing; code substitutes an extra "30 days" option (`2592000`) not in the spec's 5-option list (Never / 1h / 1d / 7d / Custom) — `dart/lib/ui/admin_tools.dart`
- [ ] [MAJOR] spec §26.6.6 "Create/Edit Link Form — Usage Limit": "Custom" option (numeric input) is missing; code only offers the 4 fixed options (Unlimited / 1 / 10 / 100) — `dart/lib/ui/admin_tools.dart`

# Audit: §27 Passcode Lock Screen

- [ ] [CRITICAL] spec §27.2/27.3 "Lottie animation": Both `_LocalPasscodeCreate` and `_LocalPasscodeCheck` render `_AnimatedSettingsIcon` (Flutter icon widget) instead of the required Lottie animation `"local_passcode_enter"` at `st::normalBoxLottieSize`; Lottie animation element is missing entirely — `dart/lib/ui/privacy_settings_screen.dart`

- [ ] [CRITICAL] spec §27.5 "Change passcode validation": `_changePasscode()` pushes `_LocalPasscodeCreate` (the same Create widget) instead of a dedicated Change flow; no validation that the new passcode differs from the current one (spec: shows "The passcode is the same" error), and placeholders say "Enter a passcode" / "Re-enter your passcode" instead of spec's "Enter a new passcode" / "Re-enter your new passcode" — `dart/lib/ui/privacy_settings_screen.dart`

- [ ] [CRITICAL] spec §27.6/27.16 "AutoLockBox zero-duration not rejected": When Custom is selected and the user enters `0:00`, `_resolveSeconds()` returns `0` and the dialog immediately pops with that value; calling code saves `autoLockSeconds = 0` (disabling auto-lock). Spec requires `collect()` → `0` to call `showError()` and keep the dialog open (zero auto-lock is explicitly invalid) — `dart/lib/ui/privacy_settings_screen.dart`

- [ ] [CRITICAL] spec §27.8 "Unlock later label missing": The system-unlock `IconButton` on the lock screen has no accompanying `"Unlock later"` text label (`st::passcodeSystemUnlockLater`, `windowSubTextFg` color, positioned with 12 px gap); the label is entirely absent — `dart/lib/main.dart`

- [ ] [MAJOR] spec §27.6/27.16 "AutoLockBox Custom TimeInput always hidden": The `HH:MM` input row is wrapped in `if (_selected == _customSentinel) ...` and is invisible until Custom is explicitly chosen. Spec (§27.16 widget tree) shows `Ui::TimeInput` always rendered alongside the Custom `Radiobutton` (which has an **empty string** label); the TimeInput is the de facto label and clicking it auto-selects Custom. Code hides the field entirely before selection — `dart/lib/ui/privacy_settings_screen.dart`

- [ ] [MAJOR] spec §27.16 "AutoLockBox TimeInput width": Each of the two custom HH/MM `TextField`s is `SizedBox(width: 60)`; with the colon separator the total is ~136 px. Spec says `st::autolockTimeWidth = 52 px` for the **entire** `Ui::TimeInput` widget — `dart/lib/ui/privacy_settings_screen.dart`

- [ ] [MAJOR] spec §27.16 "AutoLockBox HH/MM range validation": The hours and minutes `TextField`s use only `keyboardType: TextInputType.number` with no `TextInputFormatter` or range check. Spec states hours must be clamped 0–23 and minutes 0–59 at keystroke level; invalid digits are rejected immediately with no error banner — `dart/lib/ui/privacy_settings_screen.dart`

- [ ] [MAJOR] spec §27.8 "Submit button Y position": Submit button is placed at `inputY + 70` (no-error state). Spec positions it at `_passcode.y + _passcode.height + st::passcodeSubmitSkip` = `inputY + ~61 + 40 = ~inputY + 101`; the button is ~31 px too high — `dart/lib/main.dart`

- [ ] [MAJOR] spec §27.8 "Submit button shifts on error": When `_error` is non-empty the submit button shifts down an extra 25 px (`top: inputY + 70 + 25`). Spec keeps the button at a **fixed** Y position; the error text renders within the static 40 px gap between the input bottom and the button top and does not move the button — `dart/lib/main.dart`

- [ ] [MAJOR] spec §27.8 "System unlock button size": System unlock `IconButton` has `iconSize: 28` and `fixedSize: Size(48, 48)`. Spec defines `st::passcodeSystemUnlock` as a 32×36 px `IconButton` with a 32 px ripple area — 48×48 is a 50 % size deviation — `dart/lib/main.dart`

- [ ] [MAJOR] spec §27.9 "Lock screen transition: no old-content slide-out": Only the lock screen widget slides/fades in. Spec requires capturing the current UI as a pixmap snapshot and running a simultaneous `Window::SlideAnimation`: old content slides out with `easeInCirc` while the lock screen slides in with `easeOutCirc`. No snapshot is taken and no departing animation is implemented — `dart/lib/main.dart`

- [ ] [MAJOR] spec §27.13 "Notification tap while locked: missing clearAll": `_onNotifTap` when `passcodeLocked` only calls `_PasscodeLockScreenState._focusPasscode()`. Spec requires also calling `system()->clearAll()` to dismiss all pending notifications before returning; the code does not call `_notifSystem.clearAll()` — `dart/lib/main.dart`

- [ ] [MAJOR] spec §27.5 "Auto-close timer on change page": The passcode Change flow has no idle auto-close timer. Spec uses `CloudPassword::SetupAutoCloseTimer` so that if the user is idle on the change page for too long the app automatically navigates back (security measure) — `dart/lib/ui/privacy_settings_screen.dart`

# Audit: §29 Chat Export

- [ ] [CRITICAL] spec §29.5 "Processing screen": entire progress screen is a non-functional placeholder — `_tickExport()` uses a fake periodic timer with simulated speed (`0.02 + 0.01 * stepIndex`); info labels show percentages ("42%") instead of real entity counts ("N / M") or download progress ("2.4 MB / 15.7 MB"); `_totalFiles`/`_totalSizeBytes` accumulated from fake formulas; no FFI engine export calls made — `dart/lib/ui/chat_export.dart`

- [ ] [MAJOR] spec §29.2 "Export Panel Window": spec defines fixed `exportPanelSize = 364 × 480 px` for all modes; code uses 540px height for per-chat/per-topic modes (`_isPerChat ? 540.0 : _exportPanelHeight`), deviating from the single panel size constant — `dart/lib/ui/chat_export.dart`

- [ ] [MAJOR] spec §29.2 "Export Panel Window": spec requires a `SeparatePanel` standalone frameless window with `onAllSpaces: true` (visible on all virtual desktops); code implements it as an `OverlayEntry` inside the main Flutter widget tree — panel cannot appear on other virtual desktops or be moved to another monitor — `dart/lib/ui/chat_export.dart`

- [ ] [MAJOR] spec §29.5.2 "Progress Row Layout": spec says `exportProgressRowPadding = (22, 10, 22, 10)` is INNER padding within each 30px row (labels pushed 10px from top, 3px progress bar at bottom of padded area); code applies `EdgeInsets.fromLTRB(22, 5, 22, 5)` as OUTER padding around the 30px `SizedBox`, so labels sit flush against row top edge with no inner vertical spacing — `dart/lib/ui/chat_export.dart`

- [ ] [MAJOR] spec §29.5.2 "Progress Row Font": spec says `exportProgressLabel.textFg = windowBoldFg` (light: `Color(0xFF222222)`, dark: `Color(0xFFE9E8E8)`); code hardcodes `isDark ? Color(0xFFF5F5F5) : Color(0xFF000000)` (pure black/white) for step label color instead of `palette.windowBoldFg` — `dart/lib/ui/chat_export.dart`

- [ ] [MAJOR] spec §29.5.2 "Progress bar inactive color": spec says `exportProgressBg = mediaPlayerInactiveFg` (light: `Color(0xFFE1EAEF)`); code hardcodes `isDark ? Color(0xFF283848) : Color(0xFFE0E0E0)` instead of `palette.mediaPlayerInactiveFg` — `dart/lib/ui/chat_export.dart`

- [ ] [MAJOR] spec §29.8.3/§29.8.4 "Error label color": spec says `exportErrorLabel.textFg = boxTextFgError` (light: `Color(0xFFD84D4D)`, dark: `Color(0xFFDC3D3D)`); code uses `context.palette.attentionButtonFg` (light: `Color(0xFFD14E4E)`, dark: `Color(0xFFEC3942)`) — wrong color token — `dart/lib/ui/chat_export.dart`

- [ ] [MAJOR] spec §29.9.1 "Top Bar Labels": spec says middle step-label uses "Middle-elision enabled (truncates in the middle if too long)"; code uses `overflow: TextOverflow.ellipsis` which is end-elision — `dart/lib/ui/chat_export.dart`

# Audit Chunk 29 — §30 Bot Interactions

- [ ] [CRITICAL] spec §30.5 "Inline keyboard — `switch_inline` button": clicking a `switch_inline` inline keyboard button does nothing (`case 'switch_inline': break;`); spec says it should open an inline query in another chat — `dart/lib/ui/message_bubble.dart:9261`

- [ ] [CRITICAL] spec §30.5 "Inline keyboard — `buy` button": clicking a `buy` inline keyboard button does nothing (`case 'buy': break;`); spec says it should open the payment panel (`PaymentPanel.open`) — `dart/lib/ui/message_bubble.dart:9267`

- [ ] [CRITICAL] spec §30.6 "Web Apps — ready state webview": in the `ready` loading state the content area shows a "Web App opened externally" placeholder (globe icon + "Open in Browser" text button) instead of an embedded webview; spec says the webview widget renders in the content area with opacity fade from 0→1 — `dart/lib/ui/web_app_panel.dart:384`

- [ ] [CRITICAL] spec §30.7 "Bot Start Screen — right-click clears start token": `onSecondaryTap` calls `_sendStartBot(chatState)` (sends `/start token`); spec says right-click should *clear* the start token so the next left-click sends plain `/start` — `dart/lib/ui/chat_view.dart:4931`

- [ ] [CRITICAL] spec §30.7 "Bot Start Screen — empty state visual": the entire empty-chat visual is absent — no bot image (280×140 px gradient), no intro area with 96 px greeting sticker, no service-message block with bot description; only the START button exists — `dart/lib/ui/chat_view.dart` (no EmptyPainter / _BotIntroArea)

- [ ] [CRITICAL] spec §30.10 "Payments — section button interactions": payment method, shipping address, and shipping method section buttons all have an empty `() {}` onTap; spec says each opens its respective sub-screen or webview; buttons are fully non-functional — `dart/lib/ui/payment_panel.dart:769`

- [ ] [MAJOR] spec §30.1 "Bot menu button — X/close mode": when the WebApp panel is open the button should collapse to a square (30×30 px) showing only an X glyph and the width should animate back; code has no panel-open state tracking and always shows the text label — `dart/lib/ui/chat_view.dart:14763`

- [ ] [MAJOR] spec §30.3 "Inline bot results — Switch PM button icon": switch-PM button uses `Icons.open_in_new` (Material arrow-out icon); spec says the icon should be `inline_button_switch` (the dedicated switch-inline icon in `msgBotKbIconFg`) — `dart/lib/ui/chat_view.dart:17783`

- [ ] [MAJOR] spec §30.5 "Inline keyboard — no ripple on press": `_InlineButton` only animates a hover color lerp; spec requires a `RippleAnimation::RoundRectMask()` ripple spawned at the pointer position on press — `dart/lib/ui/message_bubble.dart:9114`

- [ ] [MAJOR] spec §30.5 "Inline keyboard — Buy button text not replaced with star emoji": spec says buy-button text is replaced with a star emoji (`starIconEmojiLarge`); code renders the original `btn.text` unchanged — `dart/lib/ui/message_bubble.dart:9327`

- [ ] [MAJOR] spec §30.5 "Inline keyboard — `user_profile` button does nothing": `case 'user_profile': break;` — clicking should open the referenced user's profile — `dart/lib/ui/message_bubble.dart:9284`

- [ ] [MAJOR] spec §30.5 "Inline keyboard — `request_phone/location/poll/peer` buttons do nothing": all four types just `break` with no action; spec says each triggers the corresponding sharing/selection flow — `dart/lib/ui/message_bubble.dart:9286`

- [ ] [MAJOR] spec §30.6 "Web App — loading spinner color": loading spinner color is `(isDark ? Colors.white : palette.windowFg).withValues(alpha: 0.3)`; spec says color should be `windowSubTextFg` (a subdued gray, not the full foreground) — `dart/lib/ui/web_app_panel.dart:378`

- [ ] [MAJOR] spec §30.6 "Web App — progress spinner stroke width": `_kProgressStroke = 4.0` px; spec §30.12 table says `botWebViewRadialStroke` = 3 px — `dart/lib/ui/web_app_panel.dart:17`

- [ ] [MAJOR] spec §30.6 "Web App menu — missing items": menu popup only contains "Open Bot", optional "Settings", and "Remove from Menu"; spec lists four items: "Open Bot", "Remove from Menu", "Remove from Main Menu", and "Share Game" — last two are absent — `dart/lib/ui/web_app_panel.dart:214`

- [ ] [MAJOR] spec §30.7 "Bot start button — label shows token in text": `_botStartLabel` returns `'START ($token)'` or `'START (${token.substring(0,20)}...)'` when a deep-link token is present; spec says the button always shows "START" (`lng_bot_start`) — the token is only passed invisibly via the `/start` command payload — `dart/lib/ui/chat_view.dart:3808`

- [ ] [MAJOR] spec §30.8 "Game card — no ripple on Play button press": `_GameCard` Play button uses `AnimatedContainer` hover color only; spec requires a `RippleAnimation::RoundRectMask()` with bottom-corner awareness on press — `dart/lib/ui/message_bubble.dart:8730`

- [ ] [MAJOR] spec §30.8 "Game card — loading timeout missing failure toast": 15-second timeout (`Future.delayed(15s)`) just clears `_loading` without showing the "Failed to open game" toast (`lng_game_cant_open`) specified by the state machine — `dart/lib/ui/message_bubble.dart:8638`

- [ ] [MAJOR] spec §30.9 "Login URL — phone sharing dialog never shown": `share_phone` is hardcoded to `false` in the result map; spec says a separate "Share phone number" confirmation box must be shown if the flow requests it — `dart/lib/ui/message_bubble.dart:9009`

- [ ] [MAJOR] spec §30.10 "Payments — custom tip entry missing": clicking a tip button only toggles its selected state; spec says clicking the already-selected tip (or a "Custom" button when `tipsMax > 0`) should open a modal `FieldType::Money` input box for custom amounts — `dart/lib/ui/payment_panel.dart:690`

# Audit: §3 Hamburger Menu

- [ ] [MAJOR] spec §3.3 "Dividers": PlainShadow separator below the My Profile/Bots block is rendered unconditionally (hamburger_drawer.dart:201-209) — spec says it only appears "when either entry is shown." When both `showMyProfileInDrawer` and `showBotsInDrawer` are false the divider still renders, producing a floating separator with no items above it. Fix: wrap in `if (appState.showMyProfileInDrawer || appState.showBotsInDrawer)`. — `dart/lib/ui/hamburger_drawer.dart`

# Audit: §31 Saved Messages

- [ ] [CRITICAL] spec §31.3 "Info panel SublistsWidget media filter section": The right-side info panel for Saved Messages is missing its `SublistsWidget` — spec requires a `SlideWrap<VerticalLayout>` with 8 media-type filter buttons (Photo, Video, File, Audio, Link, Poll, Voice, GIF) below the sublist list, plus a divider separator. None of this exists in `info_panel.dart`; the panel shows only the standard avatar/status/shared-media tabs with no Saved-Messages-specific sublist content.

- [ ] [CRITICAL] spec §31.7a "SearchTags non-premium promo chip": When `tags.isEmpty`, code returns `SizedBox.shrink()` (`chat_list_panel.dart:5256`) but spec says non-premium users should see a single promo chip ("Unlock Tags" / `tr::lng_unlock_tags`) with `MakePromoLink` → `ShowPremiumPreviewBox(TagsForMessages)`. Entire premium upsell flow is absent.

- [ ] [CRITICAL] spec §31.9b "Subsection tabs toggle button orientation": Toggle button (`chat_view.dart:10445`) calls `onTap: widget.onCloseSublist` which closes the sublist view entirely; spec says the button should flip the tab strip between Horizontal (Top), Horizontal (Bottom), and Vertical (Left) layout modes. Left and Bottom modes are not implemented at all — only Horizontal Top exists.

- [ ] [MAJOR] spec §31.1 "Saved Messages detection": `isSavedMessages()` identifies the self-chat via `chat.title == 'Saved Messages'` (hardcoded English string) at `chat_list_row.dart:985` and `1503`. Spec says the peer is identified by `isSelf() == true` from the engine. Any non-English locale, renamed self-chat, or differing engine title string silently breaks avatar substitution, hamburger menu routing, and sublist entry.

- [ ] [MAJOR] spec §31.7a "SearchTags chip background colors": `_SearchTagChip` uses hardcoded colors for chip backgrounds — selected: `Color(0xFF2B5278)` / `Color(0xFF419FD9)` instead of `palette.dialogsBgActive`; normal: `Color(0xFF202B36)` / `Color(0xFFF1F1F1)` instead of `palette.dialogsBgOver` (`chat_list_panel.dart:5350-5352`). Custom themes are ignored.

- [ ] [MAJOR] spec §31.7a "SearchTags chip label colors": Selected chip label uses `Colors.white` instead of `palette.dialogsNameFgActive`; normal chip label uses `Color(0xFF8B9BAA)` / `Color(0xFF999999)` instead of `palette.windowSubTextFg` (`chat_list_panel.dart:5353-5355`). Breaks theme-defined text colors.

- [ ] [MAJOR] spec §31.7b "EditTagNameBox about label text": `_EditTagNameDialog` shows only `"Tag names are visible only to you."` (`chat_list_panel.dart:5532`). Spec says `tr::lng_edit_tag_about` reads "Tag names are visible only to you. Use them to organize your saved messages." — second sentence is missing entirely.

- [ ] [MAJOR] spec §31.7b "Custom emoji in tag chips and edit dialog": Custom emoji tags render `'\u{2B50}'` (⭐) as a placeholder at `chat_list_panel.dart:5358` (chip), `5866` (sublist row tag pill), and `chat_view.dart:19082` (tag toast). Spec requires actual animated custom emoji rendered via `Ui::Text::CustomEmoji`; the placeholder breaks the visual identity of every custom-emoji reaction tag.

- [ ] [MAJOR] spec §31.8 "Tag toast body click cancels auto-dismiss": Spec says "Click on the toast body cancels the auto-dismiss." `_SavedTagToast` (`chat_view.dart:19027-19114`) has no body-level `GestureDetector` to cancel the timer on tap — only individual tag emoji buttons (which dismiss by selection) and a close ✕ button exist. Clicking the toast body area does nothing, so the dismiss countdown continues while the user tries to interact.

- [ ] [MAJOR] spec §31.2 "Sublist row nameTop": `_SavedSublistRow` uses `EdgeInsets.only(top: 8)` for outer padding (`chat_list_panel.dart:5787`) with no inner spacer, placing the name at y=8px from row top. Spec says `defaultDialogRow.nameTop = 10px` (20% deviation); `ChatListRow` correctly adds `SizedBox(height: 10)` inside its column before the name row.

- [ ] [MAJOR] spec §31.9a "Subsection tab label shortName": Sublist tab label uses `sub.peerName` (full peer name) at `chat_view.dart:10499`. Spec says tab label should be `peer->shortName()` — for users this is the first name only; for channels/groups the full title. Users with long full names produce oversized tabs instead of compact first-name labels.

# §32 Stories — Audit Findings

## CRITICAL

- [ ] [CRITICAL] spec §32.1 "Collapse trigger": stories bar collapses when overscroll ratio drops below 0.68 (`kCollapseAfterRatio`), but code collapses when `pos.pixels > 50` (any 50px downward scroll — wrong axis/metric entirely) — `dart/lib/ui/chat_list_panel.dart:218`

- [ ] [CRITICAL] spec §32.2 "Sibling Previews": 24% of sibling width must extend off-screen (`kSiblingOutsidePart = 0.24`); `_kSiblingOutsidePart` constant is defined at line 4324 but never applied — siblings render fully within bounds with no overflow — `dart/lib/ui/media_viewer.dart:4324`

- [ ] [CRITICAL] spec §32.17 "Privacy Badge outline": badge outline must be a 2px **white** ring (`storiesBadgeOutline`). Code uses `Border.all(color: Colors.black, width: 2)` — black border instead of white — `dart/lib/ui/media_viewer.dart:5888`

- [ ] [CRITICAL] spec §32.17 "Privacy Badge fill": badge background must be a vertical `QLinearGradient` (e.g. `historyPeer2UserpicBg → historyPeer2UserpicBg2` for CloseFriends). Code uses solid `Color(0xFF000000)` for all privacy types — `dart/lib/ui/media_viewer.dart:5882`

- [ ] [CRITICAL] spec §32.2 "Mark-as-Read": story must be marked read after 0.2 s (`kMarkAsReadAfterSeconds`) with a 3000 ms server-side delay (`kMarkAsReadDelay`). No such timer or read-receipt logic exists anywhere in `_StoriesViewerState` — `dart/lib/ui/media_viewer.dart:5335`

- [ ] [CRITICAL] spec §32.10 "Stealth Mode activation flow step 1": if `enabledTill > now` (stealth already active), show "Already active" toast and call callback immediately. `enabledTill` field is declared in `_StealthModeDialog` but is never consulted in `_buttonState`; the "already active" path is completely missing — `dart/lib/ui/media_viewer.dart:6465`

## MAJOR

- [ ] [MAJOR] spec §32.1 "Ordering": stories ordered by `key = int64(lastTimestamp) + (premium ? (1 << 47) : 0)` — premium users sort to the top. Code sorts only by `hasUnreadStory` then `lastMsgTime`; premium weighting is absent — `dart/lib/ui/chat_list_panel.dart:2623`

- [ ] [MAJOR] spec §32.16 "Avatar position (expanded)": `full.photoLeft = 10px`. Code centers the 42 px avatar in a 72 px wide item → left edge of avatar is 15 px from item boundary (50% deviation on the 10 px spec value) — `dart/lib/ui/chat_list_panel.dart:2777`

- [ ] [MAJOR] spec §32.2 "Navigation — close": close triggers include "swipe down". No `onVerticalDragUpdate`/`onPanUpdate` dismiss handler exists on the story content in `_buildStoryCard` or `_buildNavTapZones` — `dart/lib/ui/media_viewer.dart:5643`

- [ ] [MAJOR] spec §32.3 "Header — outside mode": date position is (50 px, 17 px) — below the name at y=17. `_buildOutsideHeader()` places name and date in the same `Row` (side by side), not stacked — `dart/lib/ui/media_viewer.dart:5728`

- [ ] [MAJOR] spec §32.15.1 "Close button hit area": close `×` button must have a 64 px hit area (`mediaviewClose` style). Code uses plain `IconButton` which defaults to 48 px (`kMinInteractiveDimension`) — 25% under spec — `dart/lib/ui/story_editor.dart:775`

- [ ] [MAJOR] spec §32.15.6 "Color button size": `photoEditorColorButtonSize = 24px`. Code builds color circle at `width: 28, height: 28` — 17% over spec — `dart/lib/ui/story_editor.dart:886`

- [ ] [MAJOR] spec §32.15.6 "Paint top bar": undo/redo must be inside the 48×422 px pill bar (paint top bar) that slides in above the paint bottom bar. Code places undo/redo as plain `IconButton`s in the app chrome header row (outside the pill bar structure entirely) — `dart/lib/ui/story_editor.dart:796`

- [ ] [MAJOR] spec §32.10 "Cooldown button label opacity": `kCooldownButtonLabelOpacity = 0.5` applies to the **label** text. Code applies 0.5 as alpha to `palette.activeButtonBg` (the background color), while the label text stays at full opacity — `dart/lib/ui/media_viewer.dart:6629`

- [ ] [MAJOR] spec §32.21 "Reaction gesture — right-click": on desktop, right-click on the heart button opens the reaction selector panel. Code only handles `onLongPress`; there is no `onSecondaryTap` / right-click handler — `dart/lib/ui/media_viewer.dart:5096`

# Audit: §33 Contacts Screen

- [ ] [CRITICAL] spec §33.2 "Stories Bar — story click": clicking a story avatar opens the chat (`_openStory` just calls `_openChat`); spec says it must open the story viewer — `contacts_screen.dart:541-542`
- [ ] [CRITICAL] spec §33.6 "Edit Contact — photo management buttons": all three buttons ("Suggest photo", "Set personal photo", "Reset to default") have empty `onTap: () {}` stubs — zero functionality — `contacts_screen.dart:2115-2132`
- [ ] [MAJOR] spec §33.4 "Name Text — color": day-theme name color is `#000000`; spec says `st.nameFg = #222222` — `contacts_screen.dart:261`
- [ ] [MAJOR] spec §33.4 / §33.14 "Online badge dimensions": code renders 10×10px dot with 2px border; spec says `dialogsOnlineBadgeSize = 12px`, `dialogsOnlineBadgeStroke = 3px` — `contacts_screen.dart:900-911`
- [ ] [MAJOR] spec §33.4 "Interaction — hover/press ripple": contact rows use `Ink(color: ...)` for hover with no `InkWell`; spec says `st.button.ripple` Material-style ink spread on press — `contacts_screen.dart:980-1031`
- [ ] [MAJOR] spec §33.4 "Interaction — middle-click": `onTertiaryTapDown` calls `widget.onTap()` (opens chat same as left-click); spec says middle-click must open chat in a new window (`rowMiddleClicked`) — `contacts_screen.dart:977`
- [ ] [MAJOR] spec §33.5 "Add Contact — name field max length": first/last name `_InputField` widgets have no `maxLength`; spec says `kMaxUserFirstLastName = 64 chars` — `contacts_screen.dart:1254-1279`
- [ ] [MAJOR] spec §33.2 "Stories Bar — readOpacity": read avatar thumbnail is not faded to 60% alpha (`readOpacity = 0.6`); only the ring colour changes, the avatar image itself is unaffected — `contacts_screen.dart:855-915`
- [ ] [MAJOR] spec §33.6 "Edit Contact — notes field emoji panel": notes `TextField` has no emoji panel integration (`ChatHelpers::TabbedPanel`); spec requires it — `contacts_screen.dart:2086-2106`
- [ ] [MAJOR] spec §33.4 "Name badges — emoji status": `ContactInfo` model has no `emojiStatus` field; emoji status badge (part of `Ui::PeerBadge`) cannot be rendered and is entirely absent from the contact row — `dart/lib/models/engine_models.dart:1436-1469`
- [ ] [MAJOR] spec §33.1 "Sort toggle — icon position": spec says icon at offset `(10px, -1px)` from button top-left (icon center ≈ y=10); code centers icon inside the 42×42 ripple circle at position `(1,6)`, placing icon center at y≈27 — ~17px vertical deviation — `contacts_screen.dart:577-608`
- [ ] [MAJOR] spec §33.12 "Empty state — no-results padding": empty/no-results text uses `EdgeInsets.symmetric(horizontal: 20)`; spec says `contactsPadding.left() = 16px` — `contacts_screen.dart:394-408`

# §34 Calls History — Audit Findings

- [ ] [CRITICAL] spec §34.10 "Row Click Behavior": clicking a call history row does nothing — `onTap: () {}` is an empty handler; spec requires navigating to the peer's chat scrolled to the newest call message in the group — `calls_screen.dart` (`_CallHistoryRowState.build`, line ~1933)

- [ ] [CRITICAL] spec §34.17.10 "Join Call footer": "Join this call yourself" `GestureDetector.onTap` calls `Navigator.of(context).pop()` (just closes the box); spec requires invoking `startOrJoinConferenceCall` with the conference link slug — `calls_screen.dart` (`_ConferenceCallLinkBox.build`, line ~1518)

- [ ] [MAJOR] spec §34.13 "Rate Call Dialog": rating dialog is shown after every call end whenever `callId != null` (in `showCallPanel`'s `closeAndRate` closure); spec requires gating on server-side `is_need_rating()` flag from `mtpc_phoneCallDiscarded` — `call_panel.dart` (`showCallPanel`, line ~1487)

- [ ] [MAJOR] spec §34.12/§34.17 "Conference Size Limit": `_confcallSizeLimit` is hardcoded to `200` in both `_CreateCallButton` (line 711) and `_CreateCallBoxState` (line 873); spec says the value must come from `appConfig.confcallSizeLimit()` (server-supplied) — `calls_screen.dart`

- [ ] [MAJOR] spec §34.8 "Status Text Format": `_formatTimestamp` outputs fixed 24-hour `HH:mm` (e.g. `"14:30"`); spec requires `QLocale::ShortFormat` (locale-dependent, 12-hour AM/PM in English, e.g. `"2:30 PM"`) — `calls_screen.dart` (`_CallHistoryRowState._formatTimestamp`, line ~1811)

# Audit: §35 Empty, Error & Loading States

- [ ] [CRITICAL] spec §35.10 "Empty Shared Media Tabs": `_MediaEmptyState` uses generic Flutter Material icons (`Icons.photo_outlined`, `Icons.videocam_outlined`, `Icons.music_note_outlined`, `Icons.insert_drive_file_outlined`, `Icons.mic_outlined`, `Icons.link_outlined`) instead of the spec-required Telegram PNG icon assets (`info_media_photo_empty.png`, `info_media_video_empty.png`, `info_media_audio_empty.png`, `info_media_file_empty.png`, `info_media_voice_empty.png`, `info_media_link_empty.png`) tinted `windowSubTextFg` — `dart/lib/ui/info_panel.dart:4420-4431`

- [ ] [CRITICAL] spec §35.4 "Empty Saved Sublists": state is entirely missing — `_EmptyState` has no code path to show "You can save messages from other chats here." when Saved Messages is active but has no sublists; no `activeSaved` condition is checked anywhere — `dart/lib/ui/chat_list_panel.dart:4093-4212`

- [ ] [CRITICAL] spec §35.13 "Empty Emoji Panel (Search)": emoji search is entirely absent from `_EmojiTab` (no search bar, no query handling, no results list), so the "No emoji found" state (`lng_emoji_nothing_found`) can never appear — `dart/lib/ui/emoji_panel.dart:762-923`

- [ ] [MAJOR] spec §35.22 "Connecting State": "Connecting..." text is shown unconditionally when `state == ConnState.disconnected || state == ConnState.unstable` (before the 4 s `_isWaiting` timer fires), but spec says text appears ONLY on hover during the Connecting state; code line `showText = _isHovered || _isWaiting || state == ConnState.disconnected || state == ConnState.unstable` always exposes the text for disconnected/unstable states — `dart/lib/ui/shell.dart:1060-1062`

- [ ] [MAJOR] spec §35.12 "Empty Sticker Panel (Search)": search-no-results empty state uses `Icons.sticky_note_2_outlined` (generic Material icon), spec requires the `stickersEmpty` icon asset (`Telegram/Resources/icons/stickers_empty.png`) — `dart/lib/ui/emoji_panel.dart:1669-1673`

- [ ] [MAJOR] spec §35.15 "Chat Intro": greeting sticker is rendered ABOVE the intro bubble and the description reads "Send a message or click on the greeting above"; spec requires the sticker to appear BELOW the bubble with text "Send a message or click on the greeting below" (`lng_chat_intro_default_message`) — `dart/lib/ui/chat_view.dart:9218-9270`

- [ ] [MAJOR] spec §35.20 "Empty Blocked Users List": empty state renders `_AnimatedSettingsIcon(Icons.block, size: 74)` (animated Material icon) instead of the spec's `blocked_peers_empty.tgs` Lottie animation; loading state shows `CircularProgressIndicator()` instead of spec's "Loading..." description text (`lng_contacts_loading`) — `dart/lib/ui/privacy_settings_screen.dart:6572-6595`

# Audit: §36 Common Dialog & Modal Patterns

- [ ] [CRITICAL] spec §36.2 "DeleteMessagesBox Enter-key safety": `_DeleteContent` unconditionally passes `onConfirm: _confirm` to `TelegramBox` for every delete mode, so Enter triggers deletion even in `clearHistory` mode — spec explicitly requires Enter/Return be disabled for history-clearing (safety measure); spec says ONLY message-deletion mode should respond to Enter — `confirm_box.dart:545`

- [ ] [CRITICAL] spec §36.4 "Add contact box — userpic button": Spec says "Userpic button at top" of add-contact form; code jumps directly to first-name `BoxInputField` with no avatar/userpic button present — `input_dialogs.dart:517`

- [ ] [CRITICAL] spec §36.7 "Color Picker modes": Spec requires two modes: RGBA and HSL (with a Lightness slider for HSL mode only, Opacity slider for RGBA mode only); code implements only a single HSB mode with no mode-toggle UI — `color_picker_box.dart:1`

- [ ] [CRITICAL] spec §36.10 "PopupMenu nested submenus": Spec requires nested submenu support with auto-open on hover; `TelegramMenuItem` has no `children`/submenu field and `_TelegramMenuContent` has no submenu rendering path — required for mute-notifications submenu and folder submenu in chat list context menu — `popup_menu.dart:48`

- [ ] [CRITICAL] spec §36.12 "Screen Share live preview": Spec says each source in the screen-share chooser must show a live preview track; code shows only a static `Icons.desktop_windows` icon placeholder — `confirm_box.dart:1076`

- [ ] [MAJOR] spec §36.12 "Screen Share chooser type": Spec says screen share uses "a custom ChooseSourceProcess window (not a box -- a standalone RpWindow)"; code implements it as `showTelegramBox` (a dialog/overlay), wrong widget hierarchy — `confirm_box.dart:948`

- [ ] [MAJOR] spec §36.10 "PopupMenu Right/Left arrow keyboard": Spec says "Submenus open on Right arrow, close on Left"; code `_handleRawKey` only handles Up, Down, Enter, Escape — Right and Left arrow keys are entirely unhandled — `popup_menu.dart:429`

- [ ] [MAJOR] spec §36.13 "Report Details box button labels": Spec `lng_cancel` = "Cancel", `lng_report_button` = "Report"; code uses `text: 'CANCEL'` and `text: 'REPORT'` (all-caps), wrong casing — `confirm_box.dart:1325`

- [ ] [MAJOR] spec §36.13 "Report Details box button style": Spec §36.16 classifies Report action as `defaultBoxButton` (neutral); code uses `isDestructive: true` making the "Report" button render in red (`attentionBoxButton`), wrong style — `confirm_box.dart:1327`

- [ ] [MAJOR] spec §36.13 "Report Reaction box button labels": Spec `lng_cancel` = "Cancel", `lng_report_and_ban_button` = "Ban user"; code uses `text: 'CANCEL'` and `text: 'BAN USER'` (all-caps), wrong casing — `confirm_box.dart:1358`

- [ ] [MAJOR] spec §36.6.4 "TimePickerBox active band color": Spec says active band is bounded by `activeLineFg` lines; code uses `context.palette.windowBgActive` for the band border color — these are distinct palette tokens with different resolved colors — `choose_datetime_box.dart:1020`

# Audit §37 — Desktop Notifications

- [ ] [CRITICAL] spec §37.1 "Manager selection": when native is requested but `nativeNotificationsSupported()` returns false, code sets `targetType = ManagerType.dummy` (silent no-op) instead of `ManagerType.defaultPopup`; users on non-Linux/Mac/Win platforms get zero notifications — `notification_system.dart:148`
- [ ] [CRITICAL] spec §37.2.2/§37.2.3 "Windows/macOS native": `NativeManager.showNotification()` only calls `_showLinuxDBusNotification` when `Platform.isLinux`; on Windows and macOS it does nothing silently, yet `nativeNotificationsSupported()` returns true for both — users get zero notifications on those platforms — `notification_manager_native.dart:290-294`
- [ ] [CRITICAL] spec §37.3.4 "Userpic": `_Avatar` widget receives `avatarPath` but never loads or displays the image; every notification always renders an initials-circle regardless of whether a real avatar path is available — `notification_popup.dart:659-703`
- [ ] [CRITICAL] spec §37.3.6 "Submit reply": `_onReplySend` calls `_startFastHide(popup)` which hides only the replied popup; spec says "starts hiding all" — all visible notifications must be dismissed after reply is sent — `notification_popup.dart:296-303`
- [ ] [CRITICAL] spec §37.3.7 "Hide All button position (bottom corners)": Hide All is placed at `size.height - _notifyDeltaY - _hideAllHeight` (7 px from screen bottom, corner side); spec says it must be at the tail of the stack (above the oldest notification, furthest from corner) — `notification_popup.dart:430-431`
- [ ] [CRITICAL] spec §37.5.1 "Default notification sound": `NotificationSoundPlayer` generates a synthetic two-tone WAV on every fresh install; spec requires the bundled `msg_incoming.mp3` asset (Qt resource `:/sounds/msg_incoming.mp3`) as the default sound — `notification_sound.dart:24-30`
- [ ] [CRITICAL] spec §37.12.1 "Hidden userpic placeholder": `_HiddenUserpicPlaceholder` wraps the logo in `ClipRRect(borderRadius: BorderRadius.circular(4))`, applying rounded corners; spec explicitly states "There is no rounded clip applied — the logo bitmap is drawn as-is, square" — `notification_popup.dart:711`
- [ ] [MAJOR] spec §37.3.5 "Reply button fade animation": reply button is shown/hidden instantly via an `if (popup.hovered)` condition with no transition; spec requires 200 ms linear fade-in on hover enter and 200 ms fade-out on hover exit (`notifyActionsDuration`) — `notification_popup.dart:608-617`
- [ ] [MAJOR] spec §37.6.1 "Cloud notification delay": `_countTiming` always returns `_kMinimalDelay` (100 ms) or `_kMinimalForwardDelay` (500 ms); the three-case cloud delay logic (`notifyCloudDelay` / `notifyDefaultDelay` based on other-device online status and activity) is entirely absent — `notification_system.dart:264-274`
- [ ] [MAJOR] spec §37.8 "Linux DND and custom popups": when `_manager is DefaultManager` and `dnd == true`, the entire custom notification popup is skipped; spec says Linux `Inhibited` state only suppresses sound and flash callbacks — the popup itself must still be shown — `notification_system.dart:369-373`
- [ ] [MAJOR] spec §37.11 "Tray icon badge": `updateUnread()` calls `setTooltip` to put the count in the tooltip label; the tray icon itself is never repainted with an unread count badge — `system_tray.dart:92-101`
- [ ] [MAJOR] spec §37.5.3 "suppressAll audio": after playing a notification sound, no other-audio suppression is applied; spec requires `mixer()->suppressAll(track->getLengthMs())` to mute other audio tracks for the notification sound's duration — `notification_sound.dart`
- [ ] [MAJOR] spec §37.14 "countUnreadMessages default": `NotificationSettings` initialises `countUnreadMessages = true`; spec §37.14 table defines the default as `false` — `notification_types.dart:408`

# §38 User Profile Popup (PeerShortInfoBox) — Audit

- [ ] [CRITICAL] spec §38.2 "Profile photo navigation": `_photoCount` is initialized to `1` and never updated anywhere — `UserProfile` model has no photo count field, so multi-photo progress bars and left/right click navigation regions are permanently dead for all users regardless of actual photo count — `dart/lib/ui/peer_short_info.dart:114`

- [ ] [CRITICAL] spec §38 "Self-Type Behavior": `_isSelf` uses `chat.title == 'Saved Messages'` comparison instead of comparing `peerId` against the current account's own user ID — when viewing own profile from any context other than the Saved Messages chat (e.g. from a group member list), `_isSelf` returns false and the "Send Message" button incorrectly appears — `dart/lib/ui/peer_short_info.dart:239-252`

- [ ] [MAJOR] spec §38.2 "Cover Section": no-avatar fallback renders initials text (80px white letter) over black background, but spec says "a solid black square is shown" with no text — `dart/lib/ui/peer_short_info.dart:362-376`

- [ ] [MAJOR] spec §38.2 "Additional status": third cover label for "photo set by you" / "public photo" cases is entirely absent — only name and status labels are rendered in the cover overlay — `dart/lib/ui/peer_short_info.dart:398-570`

- [ ] [MAJOR] spec §38.2 "Info Rows / Channel": personal channel name field is rendered as non-clickable `SelectableText` with copy menu, but spec says "Shows the channel name as a clickable link" — `dart/lib/ui/peer_short_info.dart:596-604`

# §39 — Photo & Avatar Cropping Dialog

- [ ] [CRITICAL] spec §39 "_done() output": crop/rotation/flip state is computed but never applied — `_done()` passes `widget.imageFile` (original file) unchanged to `onDone`; `_cropRect`, `_rotationDegrees`, `_flipped` are display-only and never used to produce a cropped output image — `dart/lib/ui/photo_crop_editor.dart:353`

- [ ] [CRITICAL] spec §39.13 "minimum input size": upscale condition uses `w < 640 AND h < 640` but spec says "smaller than 640px on either side" (OR); images where one dimension ≥ 640 but the other < 640 are not upscaled — `dart/lib/ui/photo_crop_editor.dart:258`

- [ ] [CRITICAL] spec §39.9 "Sticker/Emoji Avatar": EmojiAvatarBuilder cycles through a hardcoded local 32-entry `_kSuggestedEmoji` list instead of a server-provided emoji list from `Api::PeerPhoto::emojiListValue()` — `dart/lib/ui/photo_crop_editor.dart:1433`

- [ ] [MAJOR] spec §39.14 "background recache debounce": `_kBgDebounceFull = 1000ms` is defined but never used; `_BlurredBackgroundState._onSizeChanged` only arms `_kBgDebouncefast = 200ms`; the full-quality 1000ms recache path is entirely absent — `dart/lib/ui/photo_crop_editor.dart:38,548`

- [ ] [MAJOR] spec §39.14a "about-label margins": spec requires `margins(left=10, top=22, right=10, bottom=0)` but code applies `EdgeInsets.only(bottom: 16)` — missing left/right 10px margins, missing top 22px gap, and uses wrong bottom value (16px instead of 0px) — `dart/lib/ui/photo_crop_editor.dart:423`

- [ ] [MAJOR] spec §39.11 "paint mode bottom bar": spec lists Cancel | Paint-Active icon | Stickers button (if session available) | Done; code renders Cancel | brush icon | Done — Stickers button is entirely absent — `dart/lib/ui/photo_crop_editor.dart:1151`

# Audit: §40 — Send Files Dialog

- [ ] [CRITICAL] spec §40.6 "Caption field — Formatting support": caption field is a plain `TextField` with no rich text support; spec requires full bold/italic/underline/strikethrough/monospace/spoiler/links/custom emoji via `InitMessageFieldHandlers` — `send_files_box.dart:1278`

- [ ] [MAJOR] spec §40.2 "Album Preview — Edit/Replace button": thumbnail edit button (`_ThumbCapsule.onEdit`) directly opens `PhotoCropEditor` without a context menu; spec says the edit button opens a context menu with replace/draw/rename/caption/spoiler options — `send_files_box.dart:1806-1813`

- [ ] [MAJOR] spec §40.3 "Send As Modes — Caption position": caption above/below is exposed as a `_CheckboxRow` inside the dialog body (line 1355–1362) in addition to the send menu; spec says it is menu-only (send menu toggle), not a checkbox — `send_files_box.dart:1355`

- [ ] [MAJOR] spec §40.4 "Compression / Quality Toggle — HD badge": badge uses `EdgeInsets.symmetric(horizontal: 4, vertical: 1)` giving 4 px/side horizontal (spec says `xpadding = 2 px`/side) and 1 px/side vertical (spec says `ypadding = 0 px`); corner radius is `BorderRadius.circular(999)` (full pill) but spec says `height / 3` ≈ 4–5 px — `send_files_box.dart:2608-2624`

- [ ] [MAJOR] spec §40.5 "Spoiler Toggle — Bulk spoiler label": label shows "Remove spoiler" when `_anySpoilered` is true, but spec requires label to change only when all files are spoilered (`SpoilerState::Enabled`); should use `_allSpoilered` — `send_files_box.dart:923`

- [ ] [MAJOR] spec §40.6 "Caption field — Emoji panel": emoji panel is `_EmojiQuickPanel` with 30 hardcoded emojis in a flat grid; spec requires a `TabbedPanel` in `EmojiOnly` mode supporting standard and custom (premium) emoji; `emoji_panel.dart` exists in the project but is not imported or used here — `send_files_box.dart:1316-1331`

- [ ] [MAJOR] spec §40.6 "Caption field — Visibility": caption `TextField` and emoji toggle are always rendered; spec says both are hidden when `canAddCaption` returns false (e.g., when sending `.tgs` sticker files) — `send_files_box.dart:1270-1303`

- [ ] [MAJOR] spec §40.6 "Caption field — Emoji suggestions": no inline emoji autocomplete (`SuggestionsController`) is wired to the caption `TextField` — `send_files_box.dart:1278`

- [ ] [MAJOR] spec §40.6 "Caption field — Mention/hashtag autocomplete": no `FieldAutocomplete` for @mentions or #hashtags is wired to the caption `TextField` — `send_files_box.dart:1278`

- [ ] [MAJOR] spec §40.7 "Individual File Cards — Thumbnail (icon mode)": file icon circle uses type-based hardcoded colors (green for photo, blue for video, red for music, dark blue for file) instead of a single unified `iconBg` palette token; all file types should use the same background color — `send_files_box.dart:2446-2457`

- [ ] [MAJOR] spec §40.10 "Send Button — Send menu": "Send as sticker" option is absent from `_showSendMenu` (right-click/long-press on send button); it appears only in `_showTopMenu` (hamburger); spec says it belongs in the send button menu — `send_files_box.dart:970-1018`

- [ ] [MAJOR] spec §40.10 "Send Button — Send when online": selecting "Send when online" from `_showSendMenu` calls `_send()` directly with no `scheduledDate` and no `sendWhenOnline` flag; `SendFilesResult` has no such field, so the intent is silently lost and the message is sent immediately — `send_files_box.dart:1009-1010`

- [ ] [MAJOR] spec §40.12 "Size Limits": no file size validation is performed when files are selected or added; files exceeding 2 GiB (free) / 4 GiB (premium) are silently added without producing a `TooLargeFile` error — `send_files_box.dart:817-857`

- [ ] [MAJOR] spec §40.14 "Paste Handling": `_handleCaptionPaste` shells out to `wl-paste` (Wayland-only); image paste is completely broken on X11, Windows, and macOS; spec describes a cross-platform MIME data hook — `send_files_box.dart:454-481`

- [ ] [MAJOR] spec §40.15 "GIF Handling — animated playback": `_GifPreview` renders GIFs with `Image.file()` which shows only the static first frame; spec requires animated playback via `Media::Clip::Reader` — `send_files_box.dart:1637-1641`

- [ ] [MAJOR] spec §40.16 "Audio File Handling — Cover art": `_parseAudioTags` reads only title/performer tags; no cover art is extracted or displayed; audio files always render as icon-mode circles even when embedded album art is present — `send_files_box.dart:604-641`

# Audit: §4 Chat Header / Top Bar

- [ ] [MAJOR] spec §4.5 "Unblock button dimensions": Unblock button uses height=49px and textTop=16px, but spec says `historyUnblock` derives from `historyComposeButton` with height=46px and textTop=14px (textTop deviation 14.3%) — `dart/lib/ui/chat_view.dart:8896-8908`

- [ ] [MAJOR] spec §4.4 "historyPinnedBg night theme color": Night theme pinned bar background is `#181e24` but spec says `#1b2734` (a subtle lift above windowBg #17212b); code value is actually *darker* than windowBg, reversing the intended visual lift (green channel 23% off) — `dart/lib/theme/telegram_palette.dart:3289`

- [ ] [CRITICAL] spec §41.4 "Create/Edit link keyboard trigger": `_showLinkDialog` at `chat_view.dart:13769` guards with `if (!sel.isValid || sel.isCollapsed) return` — Ctrl+K does nothing when cursor is placed on an existing link entity without text selected. Spec says Create/Edit link is "Available even without text selection if editLinkCallback is set." Users cannot edit existing links via Ctrl+K unless they first manually select the link text. Same guard in `_showLinkDialogFromHarness` at `chat_view.dart:3716`. — `dart/lib/ui/chat_view.dart`

- [ ] [CRITICAL] spec §41.3 "Formatting submenu enablement": `_ComposeContextMenu` at `chat_view.dart:12778` uses `enabled: hasSelection` to gate the "Formatting" parent menu item. Spec says the item is disabled only "when there is no text selected AND no editLinkCallback is set" — meaning if cursor is on a link (editLinkCallback applies), Formatting must remain enabled even with a collapsed cursor. Code disables Formatting entirely whenever `!hasSelection`, making "Edit link" via context menu inaccessible when cursor is on a link without selection. — `dart/lib/ui/chat_view.dart`

- [ ] [MAJOR] spec §41.4 "Clear Formatting enablement": `_ComposeContextMenu` at `chat_view.dart:12874` adds the "Clear Formatting" submenu item with no `enabled:` check. Spec says it should be "Disabled when selection has no tags." Code always renders the item as active regardless of whether the selection contains any formatting entities. — `dart/lib/ui/chat_view.dart`

- [ ] [MAJOR] spec §41.6.3 "URL field clipboard pre-fill": `_EditLinkBoxContentState._initialUrl()` at `chat_view.dart:19328` returns empty string when `startUrl` is empty. Spec says the URL field should be pre-filled from clipboard "if it starts with `http://`, `https://`, `tonsite://` — else empty." Clipboard is never read; URL field always starts blank when no existing link is provided. — `dart/lib/ui/chat_view.dart`

- [ ] [MAJOR] spec §41.6 "Tab cycling between fields": `_EditLinkBoxContent` at `chat_view.dart:19406–19491` implements only Enter-key cycling (Enter in text field → URL focus; Enter in URL field → submit or text focus) but has no Tab key handler. Spec documents Tab cycling between text/URL fields "with full-selection clearing" (`message_field.cpp:255-282`): pressing Tab selects all text in the destination field. — `dart/lib/ui/chat_view.dart`

- [ ] [MAJOR] spec §41.4 "Date insertion — editing existing date": `_showDatePicker` at `chat_view.dart:13790` always opens `showCalendarBox` first, then `showChooseDateTimeBox`. Spec says "If editing existing date, goes straight to `ChooseDateTimeBox`." The code never checks whether the current selection contains an existing `FormatType.date` entity; it always shows the two-step CalendarBox → ChooseDateTimeBox flow. — `dart/lib/ui/chat_view.dart`

- [ ] [MAJOR] spec §41.13.1 "Block background fill in compose field": `_FormattingPainter._paintBlockDecoration` at `chat_view.dart:12193` draws only the 3 px left rule and the copy/quote icon — no background fill is painted for blockquote or code blocks. Spec §41.13.1 states block-level formats use a background colour ("Background uses `historyComposeAreaBg` instead of bubble-specific colours"), giving the block a distinct tinted fill. Without it the blockquote/code region is visually indistinguishable from plain text except for the left bar. — `dart/lib/ui/chat_view.dart`

# Audit §42 — Reactions Detail Popup

- [ ] [CRITICAL] spec §42.1/§42.2 "Context menu 'Who Reacted' row — Mode A submenu": clicking 'who_reacted' in message context menu jumps directly to Mode B (ReactionsDetailPanel); spec requires the menu row to display a summary line with count + up to 3 userpic circles on the right, and hovering to open a submenu listing individual reactors before reaching Mode B — `dart/lib/ui/chat_view.dart:1352,1523`

- [ ] [CRITICAL] spec §42.2 "Mode A top section — Set as Quick Reaction": the right-click-on-reaction-button popup (`_showWhoReactedMenu`) never shows a "Set as Quick Reaction" action + separator even when the reaction is an active non-quick emoji; option is entirely absent — `dart/lib/ui/message_bubble.dart:254`

- [ ] [CRITICAL] spec §42.2/§42.9 "Mode A bottom section — Emoji Pack action": the right-click-on-reaction-button popup never shows an "Emoji Pack" menu item even when the reaction is a custom emoji belonging to a sticker set; option is entirely absent — `dart/lib/ui/message_bubble.dart:254`

- [ ] [MAJOR] spec §42.4.1 "All tab icon — reactionsTabAll (heart+eye)": the "All" tab pill uses `Icons.favorite` (heart only); spec requires `reactionsTabAll` which combines a heart and an eye icon; the eye component is entirely missing — `dart/lib/ui/reactions_detail.dart:500`

- [ ] [MAJOR] spec §42.4.1 "Per-reaction tab order — count descending": `_ReactionTabBar` renders tabs with `for (final r in reactions)` preserving the data-model order; spec requires tabs sorted by reaction count descending — `dart/lib/ui/reactions_detail.dart:507`

- [ ] [MAJOR] spec §42.5.2 "Right-action emoji — visible on All tab and per-reaction tabs": `_ReactorRow` sets `showEmoji: _selectedTab == null`, so the right-side reaction emoji is hidden on per-reaction filtered tabs; spec §42.5.2 explicitly states "Shown on All tab and on filtered (per-reaction) tabs alike" — `dart/lib/ui/reactions_detail.dart:404`

- [ ] [MAJOR] spec §42.6 "Pagination offsets — separate _allOffset and _filteredOffset": code tracks a single `_nextOffset` for all tabs; switching from a paginated "All" tab to a per-reaction tab (or back) resets to offset '' and loses the previous position; spec requires separate offset strings per filter — `dart/lib/ui/reactions_detail.dart:87,255`

- [ ] [MAJOR] spec §42.11/§42.12 "Info layer panel position — top margin 20–40px": `ReactionsDetailPanel.show()` wraps the panel in `Center()`, placing it vertically centred on screen; spec §42.12 says the layer panel has a top margin clamped between 20 px and 40 px (windowHeight / 24) and slides down from the top — `dart/lib/ui/reactions_detail.dart:53`

- [ ] [MAJOR] spec §42.12 "Info layer minimum margin 48 px per side": `ReactionsDetailPanel` only applies `maxWidth: 392` with no minimum-margin constraint; on screens narrower than 488 px the panel fills full width; spec says minimum lateral margin is 48 px per side (effective min-margin = 96 px total, panel width = parentWidth − 96 px, capped at 392 px) — `dart/lib/ui/reactions_detail.dart:54`

- [ ] [MAJOR] spec §42.2 "Mode A popup styling — st::whoReadMenu": the right-click-on-reaction-button popup uses Flutter Material `showMenu()` with `PopupMenuItem` widgets; all other message context menus in the codebase use the custom `showTelegramMenu()` from `popup_menu.dart`; this produces inconsistent styling (Material drop-shadow and animation vs Telegram-styled popup) — `dart/lib/ui/message_bubble.dart:390`

# §43 Read Receipts Detail — Audit Findings

- [ ] [CRITICAL] spec §43.3 "Context Menu Summary Text": `_readReceiptLabel()` returns hardcoded "Seen by..." / "Listened by..." / "Watched by..." with a literal ellipsis instead of the actual participant count. Spec requires "Seen by N" (e.g., "Seen by 5") resolved from the read participants list. — `dart/lib/ui/chat_view.dart:2183-2187`

- [ ] [CRITICAL] spec §43.3/§43.10.1 "Userpic Strip in Context Menu Item": The `TelegramMenuItem` for `who_read` (`chat_view.dart:1356`) has no inline userpic thumbnail strip on the right side. Spec requires up to 3 overlapping circular thumbnails (22 px diameter, 8 px shift, 4 px stroke) drawn at the right edge of the summary row in the context menu entry itself. The strip only exists in the separate `_WhoReadPopup` dialog, not in the menu item. — `dart/lib/ui/chat_view.dart:1356`

- [ ] [CRITICAL] spec §43.10.3 "WhenRead Inline Timestamp": The private-chat "Read at..." context menu item (`chat_view.dart:1354`) shows a placeholder label and opens a modal dialog on click. Spec §43.10.3 requires the formatted read timestamp (e.g., "Today, 14:32") to be shown **inline as the menu item's own label**, with a double-check icon at left, without requiring any click — the `WhenReadContextAction` renders the time directly in the parent context menu row. — `dart/lib/ui/chat_view.dart:1354`

- [ ] [CRITICAL] spec §43.12 "Show Button Action (MyHidden)": `_WhenReadPopupState._onShowTap()` (`chat_view.dart:20416`) and `_WhoReadPopupState._onShowTap()` (`chat_view.dart:19926`) both show an `AlertDialog` with a single "OK" button (informational only). Spec requires `ShowOrPremiumBox` offering two real actions: (a) call `api.globalPrivacy().updateHideReadTime({})` to disable the hide-read-time setting, or (b) navigate to Premium settings. The "Show" button is entirely non-functional — clicking it does nothing. Same broken stub in `dart/lib/ui/reactions_detail.dart:914`. — `dart/lib/ui/chat_view.dart:20416,19926`

- [ ] [MAJOR] spec §43.6 "Empty State — Item Disabled": The `who_read` context menu item (`chat_view.dart:1355-1356`) is always enabled and clickable regardless of participant count. Spec §43.6 requires the item to be **disabled** (not clickable, no submenu) when the participants list is empty and privacy state is not `MyHidden`. The code opens the popup and shows "Nobody has seen yet" post-click rather than disabling the item before click. — `dart/lib/ui/chat_view.dart:1355-1356`

- [ ] [MAJOR] spec §43.5 "Preloader Skeleton Alpha": `_WhoReadPreloaderRow` uses `palette.windowFg.withValues(alpha: 0.08)` for the avatar circle and name rect skeleton. Spec specifies `kPreloaderAlpha = 0.2` — code is 60% below the required opacity (0.08 vs 0.20). — `dart/lib/ui/chat_view.dart:20179`

- [ ] [MAJOR] spec §43.10.3 "WhenRead Font Size": `_WhenReadPopup` renders the read-time text at `fontSize: 14` (`chat_view.dart:20492`). Spec §43.10.3 specifies `whenReadStyle.font = 12px` for the when-read line content. Code is 16.7% above the specified size (14 vs 12). — `dart/lib/ui/chat_view.dart:20492`

- [ ] [CRITICAL] spec §44.1 "text spoiler particle color": `_TextSpoilerSheetPainter` renders particles as plain white (`Color.fromRGBO(255, 255, 255, opacity * 0.7)` + `BlendMode.plus`) with no tint — spec says particles must be colorized with `defaultTextPalette.spoilerFg` = `msgInDateFg` theme color via `SpoilerMessCache` — `dart/lib/ui/message_bubble.dart`
- [ ] [MAJOR] spec §44.4 "text reveal animation": `_TextSpoilerSheetPainter` applies `opacity * 0.7` (30% reduction) to particle paint alpha — spec defines particle opacity = `1 - revealValue` with no additional reduction factor; at full spoiler lock (revealValue=0) particles should be at 1.0 opacity, code renders at 0.7 — `dart/lib/ui/message_bubble.dart`
- [ ] [MAJOR] spec §44.3/§44.4 "particle opacity": `SpoilerTilePainter` and `tileSpoilerOnRects` both apply `opacity * 0.85` (15% reduction) — spec defines no such factor; media spoiler particles locked at 0 reveal should be at 1.0 opacity, code renders at 0.85 — `dart/lib/ui/spoiler_animation.dart`
- [ ] [MAJOR] spec §44.5 "compose field spoiler particle color": `_paintSpoilerShimmer` uses hardcoded particle colors (`0xFFAABBCC` dark / `0xFF667788` light) instead of theme-aware `defaultTextPalette.spoilerFg` (`msgInDateFg`) — breaks color correctness on non-default themes — `dart/lib/ui/chat_view.dart`
- [ ] [MAJOR] spec §44.6 "notification spoiler replacement": `_applySpoiler` clamps U+259A repeat count to `.clamp(1, 40)` — spec says spoiler characters are "repeated for the spoiler's length" with no maximum; texts longer than 40 chars are misrepresented as shorter — `dart/lib/notifications/notification_types.dart`

# Audit §45 — Custom Emoji Rendering

- [ ] [CRITICAL] spec §45.3 "Animated Custom Emoji — WebM (video sticker) type": WebM files are never rendered in any custom emoji widget; `CustomEmojiFileData.isWebm` is defined but unused in all render paths — `_CustomEmojiInline`, `_LargeCustomEmojiTile`, `_ComposeCustomEmoji`, and `EmojiStatusWidget` all fall through to thumbnail/fallback when `file.isWebm` is true (spec says WebM must play via FFmpeg frame generator; code shows no WebM rendering path in any widget) — `dart/lib/ui/message_bubble.dart`, `dart/lib/ui/chat_view.dart`, `dart/lib/ui/emoji_status_widget.dart`

- [ ] [CRITICAL] spec §45.5 "Custom Emoji in Names — userpic: prefix": `userpic:` emoji status renders as invisible `SizedBox.shrink()` instead of a dynamic circular userpic image — `_parseEmojiStatusId()` sets `_documentId = null` for any `userpic:` ID, causing `build()` to return `SizedBox.shrink()` unconditionally; spec says this should render an inline circular userpic replacement — `dart/lib/ui/emoji_status_widget.dart:101-107`

- [ ] [CRITICAL] spec §45.1 "Inline Rendering — text color tinting": custom emoji with the `UseTextColor` flag are never colorized to match surrounding text color — `_CustomEmojiInline` has no `colorizeImage` / `ShaderMask` tinting logic at all; spec says `document->emojiUsesTextColor()` triggers `style::colorizeImage()` colorization — `dart/lib/ui/message_bubble.dart:6052-6339`

- [ ] [MAJOR] spec §45.1 / §45.10 "Vertical alignment — AlignTop": inline custom emoji in both message text and compose field use `PlaceholderAlignment.middle`, but spec specifies `QTextCharFormat::AlignTop` with height `max(fontHeight, emojiSize)` — `_styledSpan` case `'custom_emoji'` at line 6963 uses `PlaceholderAlignment.middle`; `buildTextSpan` in `RichTextEditingController` at line 11678 also uses `PlaceholderAlignment.middle` — `dart/lib/ui/message_bubble.dart:6963`, `dart/lib/ui/chat_view.dart:11678`

- [ ] [MAJOR] spec §45.14 "View Pack label — pack name colorization": the "Custom emoji from {name}." label renders the entire string in uniform text color; spec says `Ui::Text::Colorized(packName)` accent-colors the pack name portion — `_ViewPackButton.build()` uses a single plain `Text` widget with no `TextSpan` colorization for the pack name — `dart/lib/ui/message_bubble.dart:2374-2426`

# §46 — Link Preview in Compose Audit

- [ ] [MAJOR] spec §46.2 "Thumbnail position in FieldHeader": when `isSmallMedia && hasThumb` the code places the thumbnail on the RIGHT side (`right: rightButtonsWidth`) with text starting at `left: 53`; spec says the FieldHeader thumbnail is always drawn at `(previewLeft=53, 8)` on the LEFT, with text starting at 95px after the thumbnail — small/large media distinction only affects rendered message bubbles (§46.3), not the compose bar — `dart/lib/ui/chat_view.dart` (`_WebPreviewBar`, line 8339–8416)

- [ ] [MAJOR] spec §46.5 "Multiple URLs — Draft Options dialog": when multiple links are detected the code shows prev/next chevrons in the bar but the Draft Options dialog (`_showDraftOptionsBox`) contains no `PreviewWrap` message rendering and no "Tap on a link in the message to choose a preview for it" divider text; spec requires the dialog to render the full message with all links highlighted and call `switchTo(link)` when a different link is tapped — `dart/lib/ui/chat_view.dart` (`_showDraftOptionsBox`, line 3180–3234)

- [ ] [MAJOR] spec §46.7 "No Preview Available — toast": when all links resolve to null the code silently clears the preview state with no user feedback; spec requires showing `tr::lng_preview_cant` ("Sorry, the preview for this link is not available.") toast from the Draft Options dialog — `dart/lib/ui/chat_view.dart` (`_fetchWebPreview`, line 3059–3064)

# §47 — Restricted Permissions UI — Audit Findings

- [ ] [CRITICAL] spec §47 "PremiumRequired unlock button — toast widget": clicking "Unlock" calls `_showPremiumToast` which uses `ScaffoldMessenger.showSnackBar` (Flutter SnackBar) instead of `showTelegramToast`; spec requires a Telegram-styled toast (`st::defaultMultilineToast`, 1500ms, 6px radius, 160–360px width) — `dart/lib/ui/chat_view.dart` line ~9424

- [ ] [CRITICAL] spec §47 "BoostsToLift write restriction — click behavior": clicking "BOOST THIS GROUP TO SEND MESSAGES" shows `showTelegramToast(...)` but spec says "Clicking opens the boost state resolution dialog" — should open a dialog, not a toast — `dart/lib/ui/chat_view.dart` line ~9307

- [ ] [CRITICAL] spec §47 "Channel Comments Button — WithNew dot size": new-comments indicator dot rendered as `width: 6, height: 6` (6px diameter / 3px radius); spec says "6px radius" = 12px diameter dot; 100% size deviation on a small element — `dart/lib/ui/chat_view.dart` line ~14679

- [ ] [MAJOR] spec §47 "Channel Comments Button — visibility during write restrictions": spec says "The button is visible even when write restrictions are active (for PremiumRequired or Rights types)"; code at line ~4951 replaces the entire compose area with `_WriteRestrictionBar` (which contains no comments button), completely hiding the comments toggle during restrictions — `dart/lib/ui/chat_view.dart`

- [ ] [MAJOR] spec §47 "Mute/Unmute + Discuss button colors — theme token": `_ChannelComposeBar` hardcodes `isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd)` instead of `palette.windowActiveTextFg`; this is wrong for Night Green theme where `windowActiveTextFg = Color(0xFF4BE1C3)` but code shows blue `0xFF6ab3f3` — `dart/lib/ui/chat_view.dart` line ~9625

# §48 Drag-and-Drop File Overlay — Audit Findings

- [ ] [CRITICAL] spec §48.2/§48.4 "drag state classification at entry": `onDragEntered` hardcodes `_dragLayout = _DragZoneLayout.photoFiles` for every drag without classifying the dragged files — spec requires `ComputeMimeDataState()` at drag entry to pick the correct layout (`Files` = 1 document zone, `PhotoFiles` = 2 zones, `MediaFiles` = 2 zones, `Image` = 1 photo zone). Dragging pure documents always shows "Drop images here / Drop photos here" (wrong text, wrong zone count); dragging mixed media shows "Drop images here" instead of "Drop files here / Drop photos and videos". Correct layout is only computed at drop time, never during the visible overlay — `dart/lib/ui/chat_view.dart:4168`

- [ ] [MAJOR] spec §48.1 "boxRoundShadow": `_DragCard` shadow uses hardcoded `Color(0x26000000)` instead of `palette.shadowFg` — light theme palette defines `shadowFg = Color(0x18000000)` (~9.4% opacity) and dark theme defines `shadowFg = Color(0x5604080E)` (~34% opacity near-black), so the hardcoded value is wrong for both themes and does not adapt to theme changes — `dart/lib/ui/chat_view.dart:17083`

- [ ] [MAJOR] spec §48.1 "boxRoundShadow painted around the inner rectangle": `_DragCard` shadow uses directional `offset: Offset(0, 2)` (a downward drop shadow), but spec describes `boxRoundShadow` as a shadow "painted around" the rectangle (an ambient/spread glow with no directional offset) — `dart/lib/ui/chat_view.dart:17084-17086`

- [ ] [CRITICAL] spec §49.1 "Infinite Scroll — load newer messages": `_onScroll` only triggers `loadMoreMessages()` when `pos.pixels >= pos.maxScrollExtent - preloadThreshold` (toward older messages). There is no preload trigger for the downward direction (`pos.pixels < preloadThreshold`), and `ChatState` has no `loadMoreMessagesDown()` method at all. After jumping to an old message via `jumpToMessage()`, scrolling back toward newer messages never preloads additional content — the slice stays static. — `dart/lib/ui/chat_view.dart:749-756`, `dart/lib/state/chat_state.dart:1329`

- [ ] [MAJOR] spec §49.5 "Scroll-to-Bottom Button — visibility when isJumped": `_updateFabVisibility()` only shows the FAB when `scrolledFar (offset > 480px) || hasUnreadBelow`. Spec requires showing it also when "History not loaded at bottom" or "reply-return exists" (both correspond to `chatState.isJumped == true`). When `jumpToMessage()` loads a slice near offset=0 with no unreads and offset < 480px, the FAB stays hidden even though the view is not at the live message end. — `dart/lib/ui/chat_view.dart:796-808`

- [ ] [MAJOR] spec §49.5 "Scroll-to-Bottom Button — click navigates to UnreadMessagePosition": Spec says click jumps to `UnreadMessagePosition` (the first unread message / unread bar position). `_scrollToBottom()` calls `_smoothScrollTo(0)` (offset=0 = newest message), skipping past the unread bar which sits at `openedUnreadCount - 1` messages deep. When `openedUnreadCount` exceeds the viewport message capacity the unread bar is not visible after the FAB click. — `dart/lib/ui/chat_view.dart:931-938`

- [ ] [MAJOR] spec §49.10 "Scroll-to-Reaction Button — poll votes corner button absent": `_pollVotesAnimCtrl` is unconditionally reversed on every frame (`if (_showPollVotesBtn) { _showPollVotesBtn = false; _pollVotesAnimCtrl.reverse(); }`). There is no `unreadPollVotesCount` field in `ChatInfo` and no call to evaluate whether the button should show. The `_pollVotes` corner button (spec §49.17 stack position: topmost) is permanently invisible. — `dart/lib/ui/chat_view.dart:4330-4334`

# Audit chunk 49 — §50 Streamer Mode & Read Toggles

- [ ] [CRITICAL] spec §50.3.3 "Settings page — Drawer/Tray Elements location": "Drawer Elements" and "Tray Elements" sections (including the `showStreamerToggleInDrawer` / `showStreamerToggleInTray` / `showGhostToggleInDrawer` / `showGhostToggleInTray` rows) are implemented in `ayu_appearance_page.dart` (Appearance settings) instead of `ghost_settings_page.dart` (Ghost Mode settings). Spec says these belong under Settings → Ayu → Ghost Mode → "Drawer Elements" and "Tray Elements" subsections. — `dart/lib/ui/ayu_appearance_page.dart:90-183`

- [ ] [CRITICAL] spec §50.2 "Linux streamer toggle": Spec says "expose the toggle anyway but mark it inert" on Linux. `ayu_appearance_page.dart` hides the Streamer Mode rows under `if (Platform.isWindows || Platform.isMacOS)` (both Tray Elements line 98 and Drawer Elements line 177), so Linux users can never enable `showStreamerToggleInDrawer` or `showStreamerToggleInTray` (both default `false`). Linux users are permanently locked out of these settings. — `dart/lib/ui/ayu_appearance_page.dart:98-104,177-183`

- [ ] [MAJOR] spec §50.10 item 1 "Streamer Mode platform channel": Spec requires a dedicated method channel `uniclient/streamer_mode` with calls `enable`/`disable` and getter `isEnabled`. Code uses the shared `com.uniclient.app/window` channel with non-spec method names `setDisplayAffinity` (Windows) and `setWindowSharing` (macOS) — no dedicated channel, wrong method names, no `isEnabled` getter. — `dart/lib/state/app_state.dart:847-857`

# Audit: §5 Message List & Bubbles

- [ ] [CRITICAL] spec §5 "scroll-to-bottom FAB badge": unread count badge on jump-down button uses `palette.dialogsUnreadBg` (day #40a7e3 blue / night #4082bc blue) instead of `palette.dialogsUnreadBgMuted` (day #bbbbbb grey / night #3e546a) — spec explicitly requires the muted variant for this badge — `chat_view.dart:11006`

- [ ] [MAJOR] spec §5 "bubble colors" night `msgInBg`: code `Color(0xFF24292E)` = `#24292e` vs spec `#182533` — R channel 50% deviation, G 10.8%, B 10.9% — incoming bubble background is visibly wrong in dark mode — `telegram_palette.dart:3251`

- [ ] [MAJOR] spec §5 "bubble colors" night `msgOutBg`: code `Color(0xFF265E8C)` = `#265e8c` vs spec `#2b5278` — R 11.6%, G 14.6%, B 16.7% deviation — outgoing bubble background is visibly wrong in dark mode — `telegram_palette.dart:3253`

- [ ] [MAJOR] spec §5 "bubble colors" day `msgOutBgSelected`: code `Color(0xFFCBEBB5)` = `#cbebb5` (light green) vs spec `#b7dbdb` (teal) — B channel 17.3%, R channel 10.9% deviation; wrong color family entirely — `telegram_palette.dart:2704`

- [ ] [MAJOR] spec §5 "service messages" night `msgServiceBg` RGB: code `Color(0xD51E2429)` has RGB `#1e2429` (near-black) vs spec `#213040` (blue-grey slate) — G channel 25%, B channel 36% deviation; alpha 0xd5 is correct but the hue is wrong — `telegram_palette.dart:3267`

- [ ] [MAJOR] spec §5 "date separators / service messages" day `msgServiceBg` alpha: code alpha `0x90` (56.5%) vs spec `0x7f` (49.8%), 13.4% deviation — date separators and service pills are more opaque than spec — `telegram_palette.dart:2717`

- [ ] [MAJOR] spec §5 "bottom info" night `msgInDateFg`: code `Color(0xFF7A858F)` = `#7a858f` vs spec `#6d7f8f` — R channel 11.9% deviation — incoming message timestamps are the wrong shade in dark mode — `telegram_palette.dart:3257`

- [ ] [MAJOR] spec §5 "bottom info" selected-state date color: `_bottomInfoColor()` always returns unselected `msgOutDateFg`/`msgInDateFg` regardless of `isSelected`; never applies `msgOutDateFgSelected`/`msgInDateFgSelected` (night = `#ffffff`). Selected messages show wrong timestamp color — `message_bubble.dart:1273-1274`

- [ ] [MAJOR] spec §5 "forward header": "Forwarded from" header rendered with `fontSize: 12, fontStyle: FontStyle.italic, color: theme.textTheme.bodySmall?.color`; spec requires semibold text with peer-name accent color (same style as sender name row) — `message_bubble.dart:893-898`

# Audit: §51 Ghost Mode (AyuGram)

- [ ] [CRITICAL] spec §51.2.1 "collapsible toggle expansion state": sub-toggle section visibility is driven by `appState.ghostModeEnabled` (computed `ghostModeActive`), not a separate `isExpanded` boolean. When the user unticks any individual sub-checkbox while the section is open, `ghostModeActive` becomes false and the entire section collapses immediately, making it impossible to configure individual sub-toggles. The expansion state must be held in `StatefulWidget` state, separate from the computed ghost-active value — `dart/lib/ui/ghost_settings_page.dart:91`

- [ ] [CRITICAL] spec §51.2.2 "Schedule Messages": `useScheduledMessages` auto-scheduling is never injected into the normal send path. `_sendMessage()` is called with `scheduleDate=0` via all normal paths (Enter key `_ComposeArea._onKey`, send button `_SendButtonState._onTap`, bot reply keyboard, forward). Spec requires `isGhostModeActive() && useScheduledMessages()` to auto-schedule every outgoing message ~12 seconds in the future; this is entirely absent from the primary send path — `dart/lib/ui/chat_view.dart:3756`

- [ ] [MAJOR] spec §51.7 "-ghost flag non-persistence": `_cliGhostFlag` triggers `appState.setGhostModeEnabled(true)` which calls `_saveWindowPrefs()` at line 899, persisting the ghost state to disk. Spec explicitly states "This is a one-shot override applied on load — it does not persist." Ghost mode should be forced on for the session without writing to the prefs file — `dart/lib/main.dart:285`, `dart/lib/state/app_state.dart:899`

- [ ] [MAJOR] spec §51.2.2 "Send without Sound auto-silent": when `sendWithoutSound=true`, all outgoing messages must be sent with `silent=true` by default. The send menu label correctly flips to "Send with Sound" (line 15429), but `_sendMessage()` always defaults to `silent=false`; the ghost setting is never injected into any normal send invocation — `dart/lib/ui/chat_view.dart:3756`

- [ ] [MAJOR] spec §51.2.2 "useScheduledMessages condition": `_repeatMessage` applies scheduling via `ghostSchedule = appState.useScheduledMessages ? 0x7FFFFFFE : 0` without checking `ghostModeActive`. Spec: `isUseScheduledMessages() = isGhostModeActive() && useScheduledMessages()`. Messages can be auto-scheduled even when Ghost Mode is off — `dart/lib/ui/chat_view.dart:2082`

- [ ] [MAJOR] spec §51.3 "account picker per-account selection": `onScopeChanged` callback ignores the `userId` argument when switching to per-account mode — it calls `appState.setUseGlobalGhostMode(false)` but never stores the selected account ID. `_ghostKey` always falls back to `activeAccount?.selfUserId`, so selecting a non-active account from the picker shows/edits the active account's ghost settings instead of the selected account's settings. Per-account ghost configuration for non-active accounts is broken — `dart/lib/ui/ghost_settings_page.dart:65`

# Audit: §52 Anti-Recall & Message History (AyuGram)

- [ ] [CRITICAL] spec §52.3 "Mode 1 text marks — deletedMark duplicated": `deletedMark` appears twice in the bottom-info row for deleted messages. `_buildDeletedEditedMarks()` adds it as a standalone text widget (`message_bubble.dart:1299-1303`), and `_buildTimeText()` also prepends it to the timestamp string (`message_bubble.dart:1318-1319`), producing e.g. `[🧹 widget] [🧹 3:42 PM]`. Spec says it should appear exactly once before the time: `[deletedMark] [editedMark] [time]`. — `dart/lib/ui/message_bubble.dart`

- [ ] [CRITICAL] spec §52.3 "Mode 2 icon marks — burnt icon (flame) entirely missing": `CachedMessage` has no `isBurnt` field (`dart/lib/models/engine_models.dart`), and `_buildDeletedEditedMarks()` never renders a burnt/flame icon. Spec says icon order must be `[burnt-icon] [deleted-icon] [edited-icon] [time]`; code renders only `[deleted-icon] [edited-icon] [time]`. The flame icon for self-destructing media that has been viewed is completely absent. — `dart/lib/ui/message_bubble.dart`, `dart/lib/models/engine_models.dart`

- [ ] [MAJOR] spec §52.5 "Ctrl+F opens deleted messages search": When the deleted messages view is active, Ctrl+F must open the search field within that view. The code routes `ShortcutCommand.search` (Ctrl+F) unconditionally to `ChatListPanel.requestFocusSearch()` (the global chat-list search bar), ignoring the deleted messages view entirely. — `dart/lib/ui/keyboard_shortcuts.dart:1058-1060`

# Audit: §53 Forward Enhancements (AyuGram)

- [ ] [MAJOR] spec §53.2 "Forward Progress Tracking — lifecycle": `ForwardProgress.dispose()` is called inside `finishNativeForward` and `intelligentForward` via a 2-second `Future.delayed`, but `_ForwardProgressBarState` still holds an active `addListener` registration at that point. When the parent widget later removes `_ForwardProgressBar` from the tree, `_ForwardProgressBarState.dispose()` calls `widget.progress.removeListener(_onProgress)` on an already-disposed `ChangeNotifier` — throws `AssertionError` in Flutter debug builds and a `NoSuchMethodError` (`_listeners` is null) in release builds. Fix: either don't call `progress.dispose()` in `finishNativeForward`/`intelligentForward` (let the widget's `dispose()` own it), or ensure the parent widget is rebuilt and the `_ForwardProgressBar` is unmounted before calling `progress.dispose()`. — `dart/lib/state/ayu_forward.dart:93-96`, `dart/lib/state/ayu_forward.dart:248-254`, `dart/lib/ui/chat_view.dart:9461-9463`

- [ ] [MAJOR] spec §53.2 "Forward Progress Tracking — compose restore": `AyuForward._activeForwards` is a plain `static Map` with no `ChangeNotifier`/`ValueNotifier` wrapper. After `_activeForwards.remove(toChatId)` fires at t+2 s, `AyuForward.isForwarding(chatId)` returns `false` but no Flutter notification is dispatched. `_ChatViewState` only discovers the change on its next incidental `ChatState` rebuild. If no `ChatState` event arrives soon (e.g. forwarded-message echo is slow or fails), the compose area remains stuck showing "Done" indefinitely — the user cannot type. Spec §53.2 says "when the forward finishes … the normal compose area is restored." Fix: wrap `_activeForwards` in a `ValueNotifier<Map>` or notify `ChatState` after removal so the parent widget rebuilds immediately. — `dart/lib/state/ayu_forward.dart:75-96`, `dart/lib/ui/chat_view.dart:4974`

- [ ] [MAJOR] spec §53.3 "Mode 1: No-Quote Mode": `_repeatMessage` activates the no-forward-header ("send as own") path only when `shiftLeft` or `shiftRight` is pressed. The spec specifies a second trigger condition: **"or when in a replies/thread view (except forums)"** — when viewing a thread or replies pane, clicking Repeat Message without Shift should always use Mode 1 (no attribution). The code has no check for whether the current view is a thread/replies context, so Mode 2 (standard forward with attribution) is incorrectly used in thread views regardless of Shift state. — `dart/lib/ui/chat_view.dart:2080-2095`

# Audit: §54 AyuGram UI Customization

- [ ] [CRITICAL] spec §54.7 "Context Menu visibility enum": values 0 and 1 are swapped — spec defines `Hidden=0, Visible=1` (labels: "Hidden", "Shown"), code maps `{0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'}` — `dart/lib/ui/ayu_chats_page.dart:143`

- [ ] [CRITICAL] spec §54.15 "Register URL Scheme utility action": button is a placeholder stub — shows "Done" SnackBar without calling any actual URL scheme registration function — `dart/lib/ui/ayu_other_page.dart:96-106`

- [ ] [MAJOR] spec §54.1 "Avatar Corners preview click": spec says clicking opens AyuGramReleases channel in-app; code calls `Process.run('xdg-open', ['https://t.me/AyuGramReleases'])` opening an external browser — `dart/lib/ui/ayu_appearance_page.dart:430`

- [ ] [MAJOR] spec §54.12 "Appearance page layout — App Icon position": spec places App Icon picker as the first subsection in Appearance; code renders it last (after Drawer Elements) — `dart/lib/ui/ayu_appearance_page.dart:187-193`

- [ ] [MAJOR] spec §54.17 "AyuMain logo widget": spec requires rendering the currently selected app icon image via `AyuAssets::currentAppLogoPad()`; code shows a generic Flutter `Icons.*` Material icon inside a plain colored circle — `dart/lib/ui/ayugram_settings_screen.dart:62-80`

- [ ] [MAJOR] spec §54.11/§54.12 "Messages subsection — Translucent Deleted Messages and Replace Marks with Icons": both toggles (`semiTransparentDeleted`, `replaceMarksWithIcons`) belong in AyuChats > Messages subsection; they are implemented in `GhostSettingsPage` instead — `dart/lib/ui/ghost_settings_page.dart:205-219`

- [ ] [MAJOR] spec §54.3/§54.12 "Chats page slider order": spec layout shows Message Bubble Radius before Wide Messages Multiplier; code renders Wide Multiplier slider first, then Bubble Radius section — `dart/lib/ui/ayu_chats_page.dart:102-117`

- [ ] [MAJOR] spec §54.3 "Wide Messages Multiplier slider range": spec says 61 discrete stops from 1.00 to 4.00 in 0.05 increments; code uses `min=0.5`, `max=4.0`, `divisions=70` (71 positions, starting at 0.5 instead of 1.0, 70 divisions instead of 60) — `dart/lib/ui/ayu_chats_page.dart:320-325`

- [ ] [MAJOR] spec §54.11 "Hide Side Share Button placement": spec places `hideFastShare` in the Messages subsection; code places it in the Channels subsection — `dart/lib/ui/ayu_chats_page.dart:91-96`

- [ ] [MAJOR] spec §54.14/§54.18 "Disable Similar Channels master toggle logic": spec §54.18 specifies `toggledWhenAll=true` (parent ON only when ALL children checked — AND logic); code uses OR logic `appState.collapseSimilarChannels || appState.hideSimilarChannelsTab` so parent expands when ANY child is checked — `dart/lib/ui/ayu_general_page.dart:63`

- [ ] [MAJOR] spec §54.17 "Links section in-app navigation": spec says Channel (`@ayugram`) and Chats (`@ayugramchat`) buttons open the peers in-app via `showPeerByLink`; code opens `https://t.me/ayugram` and `https://t.me/ayugramchat` in an external browser via `xdg-open` — `dart/lib/ui/ayugram_settings_screen.dart:189,194`

- [ ] [MAJOR] spec §54.16 "Export menu item conditional visibility": spec says Export is only shown in the top-bar overflow menu when `hasFilters()` returns true; code always shows it and only checks `hasFilters()` after the click — `dart/lib/ui/ayu_filters_page.dart:120-122`

- [ ] [CRITICAL] spec §55.1 "Adjacent menu entries": "Boosts" and "Channel Earning" menu entries are entirely missing — spec requires them to appear alongside "Statistics" in the context/three-dot menu; neither `lng_boosts_title` nor `lng_channel_earn_title` item exists anywhere in the stats menu code — `dart/lib/ui/info_panel.dart:1771`

- [ ] [CRITICAL] spec §55.3 "Charts Section": Deferred charts (zoom-token-only, no pre-loaded data) are silently dropped — `StatsChartData.fromMap` returns null when `data` field is absent (`if (dataStr == null || dataStr.isEmpty) return null`), so any chart the server sends as token-only is never rendered; spec requires async load with SlideWrap reveal — `dart/lib/ui/stats_chart.dart:91`, `dart/lib/ui/info_panel.dart:6244`

- [ ] [CRITICAL] spec §55.4 "Top Members Lists": `_TopMemberRow` has no tap handler — the widget contains no `InkWell` or `GestureDetector`; spec requires clicking a row to open that user's profile info — `dart/lib/ui/info_panel.dart:6706`

- [ ] [CRITICAL] spec §55.5 "Public Forwards List": `_PublicForwardRow.onTap` is an empty stub (`onTap: () {}`); clicking any public forward row does nothing; spec requires navigation to the forwarded message or story in the forwarding channel — `dart/lib/ui/info_panel.dart:7437`

- [ ] [MAJOR] spec §55.3 "Overview Section" (second grid): Second 2x2 story-metrics grid always places "Reactions Per Post" bottom-left and "Reactions Per Story" bottom-right unconditionally; spec says when no post reactions exist bottom-left should show per-story reactions and bottom-right should be absent — wrong layout when `reactionsPerPost` is zero — `dart/lib/ui/info_panel.dart:6416`

- [ ] [MAJOR] spec §55.6 "Footer Range Selector": Minimum handle gap uses `_kMinRangeFrac = 0.02` (relative 2% of chart width) instead of fixed `statisticsChartFooterBetweenSide` = 5px; on narrow views (≤250px) the gap falls below 5px, allowing handles to overlap closer than spec permits — `dart/lib/ui/stats_chart.dart:190`

- [ ] [MAJOR] spec §55.6 "Point Details Tooltip": Tooltip appears and disappears instantly (conditional render with no animation); spec requires 200ms fade-in/fade-out — `dart/lib/ui/stats_chart.dart:867`

- [ ] [MAJOR] spec §55.7 "DoubleLinear": Independent per-line Y-axis scaling guard is `visLines.length == 2`; when one line is toggled off via filter buttons the condition fails and both lines collapse to a shared Y range — spec says each line always uses full chart height independently — `dart/lib/ui/stats_chart.dart:1536`

# Audit §56 Appendix A — Resolved Style Constants

- [ ] [MAJOR] spec §56.2 "boxTitle font": spec says `boxTitleFont` = 14px semibold, code uses `fontSize: 16` — `dart/lib/ui/confirm_box.dart:197`
- [ ] [MAJOR] spec §56.10 "windowBgActive (dark)": spec says `#2f82c7`, code uses `#5288c1` (R off by 13.7%) — `dart/lib/theme/telegram_palette.dart:3179`
- [ ] [MAJOR] spec §56.10 "attentionButtonFg (dark)": spec says `#e17076`, code uses `#ec3942` (G off by 21.6%, B off by 20.4% — visually a harsh bright red vs soft rose-red) — `dart/lib/theme/telegram_palette.dart:3211`
- [ ] [MAJOR] spec §56.9 "menuIconFg (light)": spec says `#70777b`, code uses `#999999` (R off 16.1%, G off 13.3%, B off 11.8% — affects all top-bar and menu icons) — `dart/lib/theme/telegram_palette.dart:2860`
- [ ] [MAJOR] spec §56.10 "menuIconFg (dark)": spec says `#8a9399`, code uses `#6c7883` (R off 11.8%, G off 10.6%) — `dart/lib/theme/telegram_palette.dart:3410`
- [ ] [MAJOR] spec §56.5 "historySendIconFg (light)": spec says `#3fc1f7`, code uses `#40a7e3` (G off 10.2%; code reuses the accent color instead of the distinct send-icon blue) — `dart/lib/theme/telegram_palette.dart:2736`
- [ ] [MAJOR] spec §56.5 "historySendIconFg (dark)": spec says `#6ab3f3`, code uses `#5288c1` (G off 16.9%, B off 19.6%) — `dart/lib/theme/telegram_palette.dart:3286`
- [ ] [MAJOR] spec §56.5 "historyComposeIconFg (light)": spec says `#a0acb6`, code uses `#999999` (B off 11.4%; neutral gray instead of blue-tinted gray) — `dart/lib/theme/telegram_palette.dart:2731`

- [ ] [CRITICAL] spec §57.4 "msgOutDateFg" (dark): spec says `#C2E4FFAD` → Flutter `Color(0xADC2E4FF)` (67.8% opaque light-blue timestamp), code uses `Color(0xFF7DA8D3)` (fully opaque medium-blue) — wrong color AND wrong alpha channel; timestamp text on outgoing dark-theme bubbles renders incorrectly — `dart/lib/theme/telegram_palette.dart:3258`
- [ ] [MAJOR] spec §57.4 "msgOutBgSelected" (dark): spec says `#387AAD` → `Color(0xFF387AAD)`, code uses `Color(0xFF2E70A5)` — R channel 17.9% off (56 vs 46); selected outgoing bubble background is wrong shade — `dart/lib/theme/telegram_palette.dart:3254`
- [ ] [MAJOR] spec §57.4 "msgOutReplyBarColor" (dark): spec says `#FFFFFF` (white), code uses `Color(0xFF65B9F4)` (blue) — R channel 60%+ off; reply-bar accent stripe on outgoing messages renders blue instead of white — `dart/lib/theme/telegram_palette.dart:3262`

# Audit: §6 Media Message Types

- [ ] [CRITICAL] spec §6.6 "Stickers — premium effect": Premium sticker effect animation entirely absent — spec requires a particle animation to play once inside the 1.49× bounding box on first display (`_premiumEffectPlayed` flag + `PremiumEffectSize` area); code allocates the correct 1.49× bounding box but renders nothing in the extra space, no effect widget exists — `message_bubble.dart:3294-3299`

- [ ] [MAJOR] spec §6.7 "Voice Messages — waveform fallback": When `mediaWaveform` is empty, spec says 31 random peaks are generated and rendered; code shows static "Voice message" text label instead (`if (hasWaveform) ... else Text('Voice message', ...)`) — `message_bubble.dart:4261-4267`

- [ ] [MAJOR] spec §6.1 "Spoiler overlay — tap-to-reveal easing": Reveal animation controller (`_spoilerRevealCtrl`, 200ms) runs with no `CurvedAnimation` wrapper, producing linear easing; spec says `sineInOut` easing (`fadeWrapDuration = 200ms`, default sineInOut from `lib_ui/ui/effects/animations.h`) — `message_bubble.dart:3079-3082`

- [ ] [MAJOR] spec §6.9 "Files/Documents — icon state": Spec says the whole 44px icon changes by state (download arrow → cancel X → play triangle); code keeps a static `Icons.insert_drive_file` in the 44px area at all times and shows state only via a tiny 16×16 badge positioned at bottom-right; the loaded state badge shows `Icons.insert_drive_file` instead of the play triangle — `message_bubble.dart:5338-5388`

- [ ] [MAJOR] spec §6.11 "Locations — live location ring color": Ring color should be `msgServiceFg` (#FFFFFF in default theme) per spec (`messageStyle()->msgServiceFg`); code passes `locPalette.windowActiveTextFg` (#168ACD, the blue accent color) — visually blue ring instead of white — `message_bubble.dart:4877-4879`

- [ ] [MAJOR] spec §6.3 "Photo Albums — 2-item proportional split formula": For mixed-proportion 2-item albums (else branch), spec computes `secondWidth = min(max(0.4·(W−s), (W−s)·r1/(r0+r1)), W−s−1.5·minWidth)` enforcing a 40% minimum on the second item; code uses `w1 = ((W−s)·r0/(r0+r1)).clamp(minWidth, W−s−minWidth)` with no 40% floor on secondWidth — e.g. at W=430 with ratios [2.0, 0.5], spec gives second item ≈170px but code gives ≈85px (2× too narrow) — `message_bubble.dart:7277-7284`

# Compose Area Audit — §7 (chat_view.dart, send_files_box.dart)

- [ ] [CRITICAL] spec §7.3 "Send button — editPrice state": `SendButtonType.editPrice` returns `SizedBox.shrink()` — button vanishes entirely instead of showing a stars/price indicator widget; spec says it is one of 8 valid button states with distinct visual — `dart/lib/ui/chat_view.dart:15606`

- [ ] [CRITICAL] spec §7.1 "Reply/edit/forward header bar — historyReplyCancel": Forward bar cancel (X) button is `SizedBox(width: 36, height: 36)` — spec says `historyReplyCancel: 49×49, ripple 40×40`; reply and edit bars correctly use 49×49 but forward bar is 26% smaller hit target — `dart/lib/ui/chat_view.dart:8179`

- [ ] [CRITICAL] spec §7.4 "Voice record bar — signal dot": `historyRecordSignalRadius = 5px` but code draws `5.0 * scale(0.45) = 2.25px` — more than 50% smaller than spec; the red signal dot is barely 2 physical pixels — `dart/lib/ui/chat_view.dart:15974`

- [ ] [MAJOR] spec §7.4 "Voice record bar — blob radii": All 3 blob layers scaled by hardcoded `0.45` factor — spec main blob: 23–37px radius, code renders 10.35–16.65px; spec major: 43–50px, code 19.35–22.5px; spec minor: 40–47px, code 18–21.15px; all layers are ~55% smaller than spec values — `dart/lib/ui/chat_view.dart:15956`

- [ ] [MAJOR] spec §7.7 "SendFilesBox — caption field emoji button": `boxAttachEmoji` spec is `30×30, transparent bg, at boxAttachEmojiTop = 20px from field top` (overlaid on field); code places a `36×36` `_EmojiToggleButton` in a horizontal Row beside the TextField — wrong size (36 vs 30) and wrong layout (beside vs overlaid); caption field also lacks the spec's `textMargins right=31px` needed to reserve space for the overlaid button — `dart/lib/ui/send_files_box.dart:2812`

- [ ] [MAJOR] spec §7.7 "SendFilesBox — compress-images checkbox": spec labels the compress toggle `"Compress images"` / `"Compress all N images"` (checked = send as compressed photo); code labels it `"Send as document"` / `"Send as documents"` with inverted semantics (checked = send as document / NOT compressed) — label differs from spec and checkbox meaning is inverted relative to spec's `_sendImagesAsPhotos` — `dart/lib/ui/send_files_box.dart:1349`

# Audit: §8 Info / Details Panel (Third Column)

- [ ] [CRITICAL] spec §8.2 "Action buttons — Message onTap": Message button is wired with `onTap: null` — clicking does nothing (broken interaction) — `info_panel.dart:823`
- [ ] [CRITICAL] spec §8.2 "Action buttons — Call onTap": Call button is wired with `onTap: null` — clicking does nothing (broken interaction) — `info_panel.dart:835`
- [ ] [CRITICAL] spec §8 "Action buttons": Video Call button is entirely absent from the action row and overflow list; spec §8 intro explicitly lists "Message, Call, Video Call, Search, More" — `info_panel.dart:820-844`
- [ ] [CRITICAL] spec §8.2 "Button roster — Join": No Join button in the cover action row for channels/groups the user hasn't joined; spec requires `Join` button when `channel && !channel->amIn()` — `info_panel.dart:820-844`
- [ ] [MAJOR] spec §8.1 "Action-row collapse math": action ratio denominator is `_actionButtonSize + minHeight = 52 + 56 = 108`; spec says denominator = `infoProfileTopBarActionButtonsHeight + infoLayerTopBarHeight = 68 + 56 = 124` — buttons start collapsing ~13% too early — `info_panel.dart:539`
- [ ] [MAJOR] spec §8.6 "Cover gradient offset": gradient background has zero vertical shift; spec says `PhotoBgShift = 55px` when actions are shown, `PhotoBgNoActionsShift = 30px` when no actions — `_CoverGradientPainter` takes no shift parameter — `info_panel.dart:563-572,1014-1037`
- [ ] [MAJOR] spec §8.2 "wrap == Side always uses More": Side wrap mode never forces the More button; spec says "if `wrap == Wrap::Side` (third-column persistent mode always uses More)" — code only adds More when `buttons.length > 3` — `info_panel.dart:837`
- [ ] [MAJOR] spec §8.2 "Right-click on mute = mute menu": mute context menu shows only a single "Mute forever" or "Unmute" item; spec requires duration options via `MuteMenu::SetupMuteMenu` (1 hour, 8 hours, 2 days, etc.) — `info_panel.dart:950-959`
- [ ] [MAJOR] spec §8.4 "Story ring outline on cover avatar": `_UserProfilePage` (member sub-page) does not forward `storyCount`/`hasUnreadStory` to `_FlexibleCoverDelegate`; story ring is never rendered on member profile covers — `info_panel.dart:2153-2166`
- [ ] [MAJOR] spec §8 "Min width: 324px": panel minimum width is 292px (`_thirdMin = 292.0`); spec says 324px — 11% below spec minimum — `shell.dart:69`

# Audit Chunk 8 — §9 Context Menus & Actions

- [ ] [CRITICAL] spec §9.3 "reaction strip — quick reactions": `_ReactionStrip` hardcodes 8 fixed emoji (`['👍','❤️','🔥',…]`) instead of fetching the user's actual recent/allowed reactions from the server; the entire strip always shows the same 8 emoji for every user/chat regardless of server configuration — `message_bubble.dart:1486`

- [ ] [MAJOR] spec §9.1 "shadow fallback color": popup menu day-theme shadow uses `#000000` (pure black); spec requires `windowShadowFgFallback → #f1f1f1` — with 0.25 opacity the shadow is visually far darker than intended — `popup_menu.dart:20-22`

- [ ] [MAJOR] spec §9.1 "scroll padding icons variant": popup menu always applies 8px T/B padding (`_kScrollPaddingVertical = 8.0`); spec requires 5px T/B (`0,5,0,5`) for the `popupMenuWithIcons` variant used by every context menu in the app — 60% deviation on the 5px target — `popup_menu.dart:14`

- [ ] [MAJOR] spec §9.2 "attention text color": `useRedText = item.isAttention && (fullAttention || !hasIcon)` — code turns label text red for attention items that have no icon; spec says text stays `windowFg` for single attention items and only turns red when the whole menu switches to `menuWithIconsAttention` style; chat-list "Delete Chat" and "Leave Channel/Chat" items (no icon) currently render in red text incorrectly — `popup_menu.dart:599`

- [ ] [MAJOR] spec §9.3 "reactionInfoDigitSkip": gap between emoji and count in inline reaction counter is `SizedBox(width: 4)` but spec requires `reactionInfoDigitSkip: 6px` — 33% deviation — `message_bubble.dart:2070`

- [ ] [MAJOR] spec §9.3 "reactionInfoSkip": horizontal inner padding of each reaction pill is `EdgeInsets.symmetric(horizontal: 4)` but spec requires `reactionInfoSkip: 3px` — 33% deviation — `message_bubble.dart:2051`

- [ ] [MAJOR] spec §9.4 "forward dialog grid — 4 columns": `_columnsForWidth` computes `(screenWidth / 90).floor().clamp(3, 10)`, yielding 8–10 columns on typical desktop widths; spec requires a fixed 4-column grid — `chat_view.dart:16698-16699`

- [ ] [MAJOR] spec §9.4 "forward dialog 3-dot menu chrome": 3-dot options menu uses `PopupMenuButton<String>` (Flutter Material chrome) instead of `showTelegramMenu`; the Material popup uses a different open animation (no `PanelAnimation` width/height/opacity multi-curve), different ripple color, and does not guarantee `popupMenuWithIcons` item heights — `chat_view.dart:16524`

- [ ] [MAJOR] spec §9.4 "forward dialog checkmark toggles": "Show sender's name" and "Show caption" items in the 3-dot menu have no checkmark visual (`Menu::ItemWithCheck`); spec requires these to be toggle-checkmark items showing current on/off state — `chat_view.dart:16546-16565`

- [ ] [MAJOR] spec §9.4 "shareRowsTop 12px": the grid has only `SizedBox(height: 8)` above it; spec requires `shareRowsTop: 12px` above the first recipient row — 33% deviation — `chat_view.dart:16233`

- [ ] [MAJOR] spec §9.5 "delete button count suffix": when "Delete All from User" checkbox is checked, the Delete button shows literal `(...)` (`'Delete$suffix'` where `suffix = ' (...)'`); spec requires a live count `(N)` from `MessagesSearch.total` — `confirm_box.dart:512`

- [ ] [MAJOR] spec §9 "chat list context menu — New Window": "New Window" action is entirely absent from the chat-list right-click menu; spec §9 explicitly lists it — `chat_list_panel.dart`

- [ ] [MAJOR] spec §9 "chat list context menu — folder row actions": no context menu items for folder rows (expand/collapse, folder settings, mark-all-read); spec §9 requires "Folder actions (expand/collapse, settings, mark read)" — `chat_list_panel.dart`

- [ ] [MAJOR] spec §9.6 "AddTodoListAction (Pass 1 item 3)": the message context menu Pass 1 is missing the todo-list action (`AddTodoListAction :1397`); spec places it as the 3rd item in the canonical item order between Voice Timecode and Copy Selected — `chat_view.dart`

- [ ] [MAJOR] spec §9.6 "single Reply/QuoteReply item": code emits two separate items — `TelegramMenuItem(value: 'reply', label: 'Reply')` always, plus `TelegramMenuItem(value: 'quote_reply', label: 'Quote and Reply')` whenever `msg.contentText.isNotEmpty`; spec defines a single context-sensitive `AddReplyToMessageAction` that adapts its label (Reply vs Quote and Reply), not two simultaneous items — adds an extra item to every text message menu and shifts all downstream items down by one — `chat_view.dart:1322-1324`

# Audit: §10 Emoji / Sticker / GIF Panels

- [ ] [CRITICAL] spec §10.6 "Inline Suggestions — hashtag": `AutocompleteType.hashtag` is defined but the `_onAutocompleteQuery` handler has no branch for it — falls through to `else` which clears all filtered lists and shows no panel; typing `#` produces zero autocomplete suggestions (broken interaction) — `dart/lib/ui/chat_view.dart:3293-3352`

- [ ] [CRITICAL] spec §10.4 "Sticker Tab context menu — View Set": `View Set` menu item is shown in both `_StickerTabState._showStickerContextMenu` and `_StickerSuggestionPanel._showContextMenu` but neither `.then()` handler has a `view_set` case — clicking "View Set" does nothing (broken interaction) — `dart/lib/ui/emoji_panel.dart:1559-1587`, `dart/lib/ui/chat_view.dart:17465-17487`

- [ ] [MAJOR] spec §10.6 "Inline bot results — debounce": spec `kInlineBotRequestDelay = 400ms`; code uses `Duration(milliseconds: 350)` — 12.5% short — `dart/lib/ui/chat_view.dart:3575`

- [ ] [MAJOR] spec §10.6 "Emoji suggestions — fade padding": spec says 8px fixed fade at ends of scroll viewport; code uses `ShaderMask` stops `[0.0, 0.03, 0.97, 1.0]` which is 3% of container width (≈10px at 345px panel width) — ~29% deviation, not a fixed value — `dart/lib/ui/chat_view.dart:17409-17413`

## Visual Journey Findings (Layer 2)

# Journey Audit: chat_navigation

## Findings

- [ ] [MAJOR] spec §2: Default "All Chats" folder tab (filter ID 0) is labeled `'All'` instead of `'All Chats'` in both the vertical sidebar (desktop) and horizontal tab strip (mobile). Spec states: *"All Chats" default (filter ID 0, can be hidden)*. This also causes the journey automation step `taptext 'All Chats'` to fail with "Text 'All Chats' not found on screen". — `dart/lib/ui/filter_column.dart:335`, `dart/lib/ui/chat_list_panel.dart:2257`

# Journey Audit: search_flow

Tested desktop (1024×768) and mobile (400×720) modes.

## Findings

- [ ] [MAJOR] spec §2 Search Bar: Search field loses keyboard focus during first activation. Tapping the search bar enters search mode (Cancel appears, top peers strip shows) but the TextField does not capture cursor focus — typing is silently discarded. A second tap on the field is required before text input works. Root cause: `_focusSearch()` calls `_searchFocus.requestFocus()` synchronously after `setState(() => _searching = true)`, but the triggered rebuild resets focus before `requestFocus()` takes effect. Fix: defer the `requestFocus()` call via `WidgetsBinding.instance.addPostFrameCallback`. Affects both desktop and mobile modes. — `dart/lib/ui/chat_list_panel.dart:462-466`

# Journey 3 — Settings

## Findings

- [ ] [MAJOR] spec §14.2: Settings cover shows `account.phone` (phone number "96877354040") at the User ID position (`settingsPhoneTop`). Per spec, this field should display `account.selfUserId` (the numeric Telegram user ID), and the right-click context menu label should read "Copy ID" not "Copy Phone". Field `selfUserId` exists on `AccountInfo` but is unused here. — `dart/lib/ui/settings_screen.dart:523,627-630`

