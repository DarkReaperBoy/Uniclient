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

- [ ] spec §20.1 "Window Modes": no windowed/maximized mode persistence — `_MediaViewerMode` enum exists but geometry is not saved to or loaded from settings — `media_viewer.dart`
- [ ] spec §20.6 "Navigation Controls": side navigation areas are present but spec requires 90px hover width with `mediaview/next` icon and 36px circle hover indicator — implementation uses simple left/right icon buttons without the 36px hover circle — `media_viewer.dart`
- [ ] spec §20.7 "Footer / Header Area": footer shows "Photo N of M" counter and sender name but missing the bullet separator, date + DC number, and clickable-to-navigate-to-message behavior on the date — `media_viewer.dart`
- [ ] spec §20.8.1 "More-Menu Contents": overflow menu is minimal — missing items: Cancel download, Show in Folder, Copy Image/Copy Frame, Attached Stickers, Share at Time, Delete, Save As, Show All Photos/Files, Set as Userpic, Report Userpic, View Statistics, Stealth Mode — `media_viewer.dart`
- [ ] spec §20.8 "Bottom-Right Toolbar": missing Draw (photo editor) button and OCR/recognize button — only More, Rotate, Save are present — `media_viewer.dart`
- [ ] spec §20.10 "Video Playback Controls": missing quality selector menu (360/720/1080 switch), chapter dividers on progress bar, and time-remaining display with minus prefix — `media_viewer.dart`
- [ ] spec §20.11 "Video Player Behavior": speed control range is present but missing the in-app speed selection menu UI per §20.10 settings button — `media_viewer.dart`
- [ ] spec §20.13 "PiP": PiP is implemented but missing edge-snap rules on drag release — `ClampToEdges()` algorithm with `pipBorderSnapArea=16px` threshold and `3*pipBorderSkip=60px` inner margin is not implemented; PiP snaps to corners instead of edges — `media_viewer.dart`
- [ ] spec §20.13 "PiP Z-order": PiP widget renders inside the app widget tree using `Positioned` overlay, not as a separate always-on-top OS window with `WindowStaysOnTopHint` — platform limitation but behavior diverges from spec — `media_viewer.dart`
- [ ] spec §20.14 "Gallery / Group Thumbs Strip": thumb strip is implemented with correct dimensions but missing the centered layout model — spec says current thumb is centered at `-_fullWidth/2` with neighbours animating in/out; code uses a simpler horizontal list — `media_viewer.dart`
- [ ] spec §20.16.1 "Structured Context Menu": right-click context menu exists but only has Show in Chat, Forward, Save, and Copy — missing: Cancel Download, Show in Folder, Attached Stickers, Share at Time, Delete, Show All Photos/Files, Set as Userpic, Report, Stealth Mode items — `media_viewer.dart`
- [ ] spec §20.17 "Stories Viewer Integration": stories viewer scaffold exists (`_kStoriesMaxWidth`, `_kStoriesMaxHeight` constants) but missing sibling story preview thumbnails and collapsed-caption "Show more" toggle — `media_viewer.dart`
- [ ] spec §20.18 "Keyboard Shortcuts": `J`/`L` seek keys (±10s) and `,`/`.` frame-step keys (§24.9) are missing from `_handleKey` — `media_viewer.dart`
- [ ] spec §20.18 "Keyboard Shortcuts": `K` key for play/pause toggle is missing from `_handleKey` — `media_viewer.dart`
- [ ] spec §20.19.1 "Open/Close Geometry Animation": missing thumbnail-to-lightbox geometry interpolation on open — viewer opens with a simple route push, not an animated rect transition from the source thumbnail — `media_viewer.dart`
- [ ] spec §20.15 "Save/Download Toast": toast animation timings are correct (200ms in, 2s hold, 2.5s out) but missing the "Downloads" clickable link text — only `xdg-open` on tap of the whole toast — `media_viewer.dart`

## §21 — Create Group / Channel Wizard

- [ ] spec §21.2.1 "Default userpic origin": userpic gradient pair index selection uses `name.codeUnitAt(0) % 8` but spec says for a not-yet-created peer (id=0) the first pair is always used — code selects based on text input character, not peer ID — `create_group_wizard.dart`
- [ ] spec §21.2.1 "Default userpic origin": userpic gradient is top-to-bottom but spec uses 8 specific pairs `{historyPeer1UserpicBg, historyPeer1UserpicBg2}...{historyPeer8}` — code defines custom colors that don't match the palette tokens (e.g. first pair is `#FC5C51`/`#E44234` vs spec's `#FF845E`/`#D45246`) — `create_group_wizard.dart`
- [ ] spec §21.2.1 "Initials fallback": initials extraction handles up to 2 letters (first + after space/hyphen) — code has this logic but also handles `afterHyphen` as level 1 fallback, which matches spec — however the font size of `(size * 13) / 33 = 28px at 72px` is not verified in code — `create_group_wizard.dart`
- [ ] spec §21.2 "Photo picker": clicking userpic should open a `PopupMenu` with File / Camera / Clipboard paste / Emoji builder options — code only opens file picker directly, missing Camera, Clipboard paste, and Emoji builder options — `create_group_wizard.dart`
- [ ] spec §21.2 "TTL menu": group creation should have a top-bar menu for "Auto-delete messages" with current TTL value — TTL is implemented in the wizard state but the UI for selecting TTL is minimal (popup menu), missing the spec's top-bar integration — `create_group_wizard.dart`
- [ ] spec §21.3 "Member Picker": MultiSelect chips bar should have max height 104px, chips at 32px height with 128px max width, delete cross with 150ms animation — member picker exists but chip styling does not enforce these exact dimensions — `create_group_wizard.dart`
- [ ] spec §21.3 "Member Picker": avatar acts as checkbox with round check overlay and `windowActiveTextFg` tint — code uses a different visual (simple checkmark icon overlay) rather than the spec's avatar-tint approach — `create_group_wizard.dart`
- [ ] spec §21.3 "Invite via Link button": should appear above contact list if `canHaveInviteLink()` — missing from member picker step — `create_group_wizard.dart`
- [ ] spec §21.4.1 "Username validation": debounce timeout should be 200ms per `kUsernameCheckTimeout` — implementation has debounce but the actual API call uses `channels.CheckUsername` which is correct; however the green "available" label uses `boxTextFgGood` styling but without the exact `tr::lng_create_channel_link_available` format — `create_group_wizard.dart`
- [ ] spec §21.4.2 "PublicLinksLimitBox": when `CHANNELS_ADMIN_PUBLIC_TOO_MUCH` error occurs, should show a Premium limit box with revoke list — code only shows a text error message "Too many public channels", no revoke-list UI — `create_group_wizard.dart`
- [ ] spec §21.6 "Channel flow": after channel creation, should proceed to SetupChannelBox (public/private + username) then to MemberPicker — `CreateChannelScreen` is a flat single-step form that creates the channel and navigates away, missing the multi-step SetupChannelBox and MemberPicker steps — `create_channel_screen.dart`

## §22 — Forum Topics UI

- [ ] spec §22.3 "Forum Topic List Layout": topic row height should be 54px with photoSize 20px, nameLeft 39px, textLeft 39px — `_ForumTopicListView` exists in `chat_list_panel.dart` but topic row styling dimensions are not verified against these exact tokens — `chat_list_panel.dart`
- [ ] spec §22.4 "Forum Group in Main Chat List": forum groups should use expanded row height of 80px (96px with tags) with `TopicsView` rendering up to 8 recent topic names horizontally — not implemented; forum groups render as standard 62px dialog rows — `chat_list_panel.dart`
- [ ] spec §22.4 "Topic Jump Bubble": unread front topic should show a rounded bubble (radius 11px, padding 8/3/8/3px) with arrow icon for direct navigation — not implemented — `chat_list_panel.dart`
- [ ] spec §22.5 "Create/Edit Topic Dialog": icon selector panel should use `EmojiListWidget` in `Mode::TopicIcon` with server emoji set and Premium gating for non-default custom emojis — implementation shows only the 6 predefined color icons in a simple grid, no custom emoji selector — `edit_forum_topic_box.dart`
- [ ] spec §22.5 "Edit Topic": fly animation should use `EmojiFlyAnimation` from selector to icon button — a basic overlay fly animation is implemented but uses simple position/scale tween instead of the full `EmojiFlyAnimation` pattern — `edit_forum_topic_box.dart`
- [ ] spec §22.5 "Create Topic": should reserve local ID via `forum->reserveCreatingId()` and navigate to topic immediately — not connected to the engine's topic creation flow — `edit_forum_topic_box.dart`
- [ ] spec §22.6 "Topic Header Bar": standard `info_top_bar` with back button, title with icon prefix, optional subtitle at 54px height — topic header rendering in chat view exists but not verified for icon prefix positioning — `chat_list_panel.dart`
- [ ] spec §22.7 "Topic Info Panel": third column showing cover (77px height, icon 36x36px at (22,18)), notifications toggle, shared media, members list, topic link — topic info panel section not found as a dedicated widget — `info_panel.dart`
- [ ] spec §22.8 "Topic Context Menus": specific topic row right-click should show New Window, Pin/Unpin, View Info, Mute submenu, Mark Read/Unread, Close/Reopen, Add to Folder, Clear History, Delete Topic — topic list context menu exists (`_showTopicListContextMenu`) but likely missing several items (New Window, Add to Folder, Close/Reopen) — `chat_list_panel.dart`
- [ ] spec §22.9 "General Topic": title should be prefixed with "# " in rich text — not implemented in topic rendering — `forum_topic_icon.dart`
- [ ] spec §22.10 "View as Messages/Topics toggle": saves preference and switches between flat messages and topic list — toggle exists in the context menu but the "View as Messages" flat mode is not a distinct rendering — `chat_list_panel.dart`
- [ ] spec §22.2.1 "Topic Icon SVG": stroke width should be `2.94736842px` scaled — code uses `2.84210526 * s` which differs from spec value (2.95 vs 2.84) — `forum_topic_icon.dart`

## §23 — Scheduled Messages

- [ ] spec §23.3 "Scheduled Messages Toggle Button": clock icon in compose area appears when chat has scheduled messages — `_ScheduledToggleButton` exists in `chat_view.dart` but its visual matches (two-layer icon with `input_scheduled` and `input_scheduled_dot` in `attentionButtonFg`) are not verified — `chat_view.dart`
- [ ] spec §23.4 "Scheduled Messages Section (ScheduledWidget)": a full `SectionWidget` that replaces the main chat column with scheduled messages list, title bar, selection mode (Send Now/Delete), and compose controls — no `ScheduledWidget` or `ScheduledSection` class exists; the scheduled messages view is not implemented as a section — `chat_view.dart`
- [ ] spec §23.4 "Scheduled Section Top Bar": should display "Reminders" for self-chat or "Scheduled messages" for other chats, with selection mode showing Send Now + Delete buttons — missing entirely — no file
- [ ] spec §23.4 "Empty state": should show `EmptyListBubbleWidget` with service-style bubble containing "No scheduled messages" text — not implemented — no file
- [ ] spec §23.5 "Message Rendering": scheduled messages should show delivery time in bottom-info, repeat period prefix, and silent indicator (U+1F515) in tooltip — not implemented — no file
- [ ] spec §23.6 "Context Menu Actions": right-click on scheduled message should show Send Now, Reschedule, Edit, Delete — not implemented — no file
- [ ] spec §23.6 "Send Now Confirmation": should open `ShowSendNowMessagesBox` with "Send this message now?" text — not implemented — no file
- [ ] spec §23.7 "Sent-to-Scheduled Toast": when scheduling from normal compose, should auto-navigate to scheduled section — not implemented — no file
- [ ] spec §23.8 "Video Processing Flow": processing tip toast and published notification toast — not implemented — no file
- [ ] spec §23.2 "ChooseDateTimeBox": date field mouse wheel scroll should increment/decrement by one day — implemented in `_scrollDate()` via `PointerScrollEvent` — `choose_datetime_box.dart` (OK)
- [ ] spec §23.2 "Send when online": only shown for `ScheduledToUser` type — implemented with `isScheduledToUser` parameter and "Send when online" popup menu — `choose_datetime_box.dart` (OK)
- [ ] spec §23.2 "Repeat Period": repeat dropdown uses `defaultPopupMenu` style (no icons, plain text) — code uses `showMenu<int>()` which produces Material-style menu, not matching the Telegram `defaultPopupMenu` appearance — `choose_datetime_box.dart`
- [ ] spec §23.2 "Silent shortcut": holding Ctrl when confirming should schedule silently — implemented with `HardwareKeyboard.instance.isControlPressed` check — `choose_datetime_box.dart` (OK)
- [ ] spec §23.9 "Forum Topic Support": `ScheduledWidget` should support forum topics with `Context::ScheduledTopic` — not implemented since ScheduledWidget does not exist — no file

## §24 — Keyboard Shortcuts

- [ ] spec §24.2 "Shortcut Customization JSON": `shortcuts-default.json` and `shortcuts-custom.json` in config dir — implemented correctly with write/load logic — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.2 "Settings UI": full graphical shortcut editor with recording mode, conflict detection (strikethrough in red), "Reset to defaults" button — `ShortcutsSettingsScreen` exists with recording mode, conflict detection, and reset functionality — `shortcuts_settings_screen.dart` (OK)
- [ ] spec §24.4 "Application / Window": Ctrl+W, Ctrl+F4, Ctrl+L, Ctrl+M, Ctrl+Q — all present in `_defaultBindings` — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.4 "Chat Navigation": Ctrl+Tab, Ctrl+PgDn, Alt+Down, Ctrl+PgUp, Alt+Up, Ctrl+Alt+Home, Ctrl+Alt+End — all present — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.4 "Pinned Chats": Ctrl+1 through Ctrl+8 — present — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.4 "Account Switching": commands exist but unbound by default — commands are defined but no default bindings (matches spec) — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.4 "Folder Navigation": Ctrl+1 through Ctrl+8 for folders, Ctrl+Shift+Down/Up for next/prev folder — present — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.5 "Ctrl+Tab Chat Switcher": overlay with 72x104px cells, grid layout, Q to remove entry — `chatSwitchOverlay` command dispatches to `UniClientShell.showChatSwitchRequest` but the actual overlay widget dimensions (72x104 cells, margins 16px, padding 12px) are not verified here — `keyboard_shortcuts.dart`
- [ ] spec §24.8 "Text Formatting Shortcuts": Ctrl+B/I/U, Ctrl+Shift+X/M/./P/N, Ctrl+K, Ctrl+Shift+D — all 10 formatting shortcuts present in `_defaultBindings` — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.9 "Media Viewer Shortcuts": `J` (seek -10s), `L` (seek +10s), `K` (play/pause), `.` (frame step forward), `,` (frame step backward) are all missing from the media viewer's `_handleKey` — `media_viewer.dart`
- [ ] spec §24.9 "Media Viewer Shortcuts": `Ctrl+S` save-as and `Ctrl+C` copy-media shortcuts in the viewer are missing from `_handleKey` — `media_viewer.dart`
- [ ] spec §24.6 "Compose Box Key Handling": `Ctrl+O` to open file picker — `openFilePicker` command is defined with `chatRequired` scope but no default key binding for Ctrl+O is in `_defaultBindings` — `keyboard_shortcuts.dart`
- [ ] spec §24.10 "Support Mode Shortcuts": F5, Ctrl+Delete, Ctrl+Insert, Ctrl+Shift+X, Ctrl+Shift+C — all present in `_defaultBindings` — `keyboard_shortcuts.dart` (OK)
- [ ] spec §24.3 "Platform Modifier Mapping": macOS Cmd/Ctrl swap — implemented with `_isMac ? hwMeta : hwCtrl` logic — `keyboard_shortcuts.dart` (OK)

## §25 — Theming & Color System

- [ ] spec §25.1 "Palette Architecture": ~370 named tokens in `.tdesktop-theme` files with reference resolution — `paletteToMap()` in `theme_file.dart` exports ~190 tokens, significantly fewer than spec's 369 (Day Blue) — `theme_file.dart`
- [ ] spec §25.2 "Complete Color Token Reference": spec lists 369 Day Blue and 467 Night tokens — `TelegramPalette` class (not fully read due to size) maps ~190 named fields — missing approximately 180 tokens — `telegram_palette.dart`, `theme_file.dart`
- [ ] spec §25.3 "Built-in Themes": four embedded themes (Default/Classic Day, Day Blue, Night, Night Green) — `TelegramPalette` has `dayBlue` and `night` factory constructors visible; `classicDay` and `nightGreen` existence not confirmed from the read portions — `telegram_palette.dart`
- [ ] spec §25.4 "Accent Color System": 8 preset accent colors per theme, accent picker UI, colorizer algorithm to transform palette — `_AccentColorPalette` exists in `chat_settings_screen.dart` but no colorizer algorithm (HSV hue shift + saturation scale + lightness clamp) is implemented in the theme code — `telegram_palette.dart`, `theme_file.dart`
- [ ] spec §25.4.3 "Colorizer Algorithm": extracts HSV, shifts hue, scales saturation, clamps lightness `[0,160]` Day / `[64,255]` Night, with keepContrast map for Night themes — not implemented; accent changes just swap the palette, no programmatic color remapping — `telegram_palette.dart`
- [ ] spec §25.4.4 "Accent Persistence": custom accent serialized per-theme-type — `chat_settings_screen.dart` has `updateAccentColor(hex)` but persistence of accent per embedded theme type is not verified — `chat_settings_screen.dart`
- [ ] spec §25.5 "Theme File Format": ZIP with `colors.tdesktop-theme` + optional `background.jpg/png` or `tiled.jpg/png` — fully implemented with correct parsing, export, and max size limits — `theme_file.dart` (OK)
- [ ] spec §25.6 "Theme Editor": full editor with search, palette rows, color swatch, hex edit dialog, import/export — implemented with search filter, keyboard navigation, hex input, live preview, export/import — `theme_editor.dart` (OK)
- [ ] spec §25.6.2 "Palette Entry Row": spec requires color name + "= referenceName" copy reference text below — code shows only token name + hex value, missing the reference chain display — `theme_editor.dart`
- [ ] spec §25.6.3 "Color Edit Dialog": spec says colors entered as `#RRGGBB` or `#RRGGBBAA` with immediate live preview via `ApplyEditedPalette()` — code applies changes immediately on input change via `_onHexChanged`, matching spec behavior — `theme_editor.dart` (OK)
- [ ] spec §25.6.5 "Save Theme Dialog": name field, link/slug field, background section with thumbnail + "Choose from file" + tile checkbox, width `boxWideWidth` — fully implemented matching spec layout — `theme_editor.dart` (OK)
- [ ] spec §25.7 "Theme Name Generator": weighted Euclidean distance to 101-color dictionary, two patterns (Adj+Color / Color+Noun) — implemented with correct algorithm, 101 colors, 97 adjectives, 81 nouns — `theme_name_generator.dart` (OK)
- [ ] spec §25.8 "Chat Wallpaper System": solid, gradient, pattern, image types with intensity, rotation, blur — `WallpaperData` class with all four types, `patternOpacity`, `gradientRotation`, `blurred` flag, URL parsing — `wallpaper.dart` (OK)
- [ ] spec §25.8.3 "Gradient Rendering": 3-4 color gradients with animated rotation (`ComputeRealRotation` doubles base, modulo 720, toggling progress) — `_MultiColorGradient` implements animated rotation but the exact `realRotation = (base * 2) % 720` formula and phase-based toggle differ from the spec algorithm — `wallpaper.dart`
- [ ] spec §25.8.4 "Pattern Rendering": positive intensity uses `SoftLight`, negative uses `DestinationIn` + darkening overlay — `_PatternOverlay` uses `ShaderMask(blendMode: BlendMode.softLight)` for positive and `ColorFilter.mode(Colors.white, BlendMode.dstIn)` for negative, but missing the secondary `SourceOver` black fill for `-100 < intensity < 0` — `wallpaper.dart`
- [ ] spec §25.8.5 "Image Wallpaper Processing": max 2960px, aspect ratio limit 40:1, blur radius 24 — `_kMaxWallpaperSize=2960`, `_kMaxAspectRatio=40.0`, blur radius 24 all present — `wallpaper.dart` (OK)
- [ ] spec §25.8.7 "Wallpaper Upload": JPEG at 87% quality, thumbnail at 320px — `_kJpegQuality=87`, `_kThumbSize=320` — `wallpaper.dart` (OK)
- [ ] spec §25.8.9 "Adaptive Service Colors": 6 tokens auto-adjust based on wallpaper average color via `ThemeAdjustedColor()` — `themeAdjustedColor()` function exists with correct HSL transplant logic, but it is not wired into automatic palette adjustment when wallpaper changes — `wallpaper.dart`
- [ ] spec §25.9 "Night Mode": dark detection when `dialogsBg` HSV value < 0.5, night mode toggle in hamburger menu, auto-night system dark mode — `TelegramPalette` has an `isDark` getter but no automatic dark detection based on `dialogsBg` HSV value threshold; no system dark mode auto-switch — `theme.dart`, `telegram_palette.dart`
- [ ] spec §25.9.3 "Theme Switch Confirmation": 16-second countdown overlay with "Keep Changes" / "Revert" buttons — not implemented; theme changes apply immediately without confirmation overlay — no file
- [ ] spec §25.9.4 "Theme Revert Mechanism": palette saved before applying, restored on timeout/revert — not implemented — no file
- [ ] spec §25.10 "Theme Caching": parsed themes cached with CRC32 checksums — `ThemeCacheData`, `buildThemeCache()`, `validateThemeCache()`, `saveThemeCache()`, `loadThemeCache()` all implemented — `theme_file.dart` (OK)
- [ ] spec §25.11 "Per-Chat Themes": horizontal scrollable theme pills at bottom of chat with preview cards — `chat_settings_screen.dart` has `_CloudThemeSection` but no per-chat theme chooser panel in the chat view — `chat_settings_screen.dart`
- [ ] spec §25.12 "Cloud Themes": 4-per-row grid with `CloudListCheck` radio buttons, lazy loading, context menu share/edit/delete — `_CloudThemeSection` exists but verification of 4-per-row grid layout and context menu options not confirmed — `chat_settings_screen.dart`
- [ ] spec §25.13 "Theme Preview": 903x584 image with dialogs panel + chat history area — `ThemePreviewImage` at 903x584 with 9 dialog rows, sample bubbles, compose area, correct palette colors — `theme_preview.dart` (OK)
- [ ] spec §25.14 "Settings — Chat Appearance": theme radio buttons, accent circles, background row widget, tile/adaptive-wide/auto-night checkboxes — accent color palette and cloud theme sections exist in `chat_settings_screen.dart`; background row and tile checkbox are in the settings — `chat_settings_screen.dart`
- [ ] spec §25.17.2 "Colorize exclusion list": exactly 63 tokens that never change with accent — no exclusion list is maintained anywhere in the codebase since the colorizer itself is not implemented — `telegram_palette.dart`
# Audit: &sect;26-&sect;36 Admin, Export, Contacts, Calls, States

## &sect;26 -- Admin Tools
- [ ] spec &sect;26.1 "Group/Channel Edit Screen": entire EditPeerInfoBox UI (photo+title+description block, settings buttons, admin control buttons, sticker set, delete button, dialog chrome) is implemented as a single flat panel in `admin_tools.dart` but the file is too large to fully read (45828 tokens). Partial coverage only -- need line-by-line verification of all 26.1 subsections.
- [ ] spec &sect;26.2 "Permissions Management": no permission editor with toggle-style buttons (allowed=blue, restricted=red), collapsible media group with "(5/7)" count badge, or dependency-rule enforcement found in `admin_tools.dart` -- `admin_tools.dart` was too large to fully read but grep for "permission" keywords is needed to confirm presence/absence.
- [ ] spec &sect;26.2.2 "Exceptions List": no "Add Exception" button or per-user custom restriction rows found.
- [ ] spec &sect;26.2.3 "Slowmode Slider": no discrete 8-position slowmode slider (Off/5s/10s/30s/1m/5m/15m/1h) found.
- [ ] spec &sect;26.2.4 "Boosts Unrestrict Slider": no 5-position boosts slider found.
- [ ] spec &sect;26.2.5 "Charge Stars (Paid Messages)": no paid-message stars configuration found.
- [ ] spec &sect;26.3 "Individual Member Restrict/Ban Dialog": no EditRestrictedBox with cover widget (60x60 photo, permission toggles, duration picker with Forever/1Day/1Week/Custom, custom rank field) found.
- [ ] spec &sect;26.4 "Admin Appointment Dialog": no EditAdminBox with "Add as Admin" checkbox, admin rights toggles (3 sections for groups, 4 for channels), custom title/rank field, transfer ownership button, dismiss admin button, or promoted-by info found.
- [ ] spec &sect;26.5 "Admin Log / Recent Actions": no admin log viewer with chronological event rendering, search, filter dialog (19 filter flags), or empty state ("No events found") found.
- [ ] spec &sect;26.6 "Invite Links Management": no InviteLinksBox with permanent link display, "Create a New Link" button, active/revoked link sections, color-coded progress arcs, link context menu (Copy/Share/QR/Edit/Revoke/Delete), single link info box, QR code dialog, or create/edit link form found.
- [ ] spec &sect;26.7 "Member List with Role Tabs": no EditParticipantsBox with five role views (Members/Admins/Restricted/Kicked/Profile), search, pagination (16 first page / 200 subsequent), row rendering (56px height, 42px avatar), or context menu (View Profile/Promote/Restrict/Remove) found.
- [ ] spec &sect;26.8 "Banned Users List": no banned users list with unban action, "Add to Banned" button found.
- [ ] spec &sect;26.9 "Slow Mode Settings": no slowmode send-button countdown (m:ss text replacing send icon) found.
- [ ] spec &sect;26.10 "Anti-Spam Settings": no anti-spam toggle with member-count threshold found.

## &sect;27 -- Passcode Lock Screen
- [ ] spec &sect;27.1 "Settings Entry Point": no "Local passcode" row in Privacy & Security settings with On/Off label and menuIconLock icon found anywhere in the codebase.
- [ ] spec &sect;27.2 "Passcode Create Flow": no Lottie "local_passcode_enter" animation, two PasswordInput fields (256px wide), description text, or validation logic (mismatch error "Passcodes don't match") found.
- [ ] spec &sect;27.3 "Passcode Check Flow": no single-field verify-current-passcode page with flood protection found.
- [ ] spec &sect;27.4 "Passcode Management Page": no change passcode, auto-lock timer, system unlock toggle, or disable passcode buttons found.
- [ ] spec &sect;27.6 "Auto-Lock Timer Dialog (AutoLockBox)": no auto-lock box with 5 radio presets (1min/5min/1hr/5hr/Custom) and HH:MM TimeInput widget found.
- [ ] spec &sect;27.8 "Lock Screen (PasscodeLockWidget)": no full-window lock overlay with 225px passcode input at height/3, 42px submit button, logout link, or system unlock icon button found.
- [ ] spec &sect;27.9 "Lock Screen Transition Animation": no slide animation with easeOutCirc/easeInCirc easing for lock/unlock transitions found.
- [ ] spec &sect;27.11 "Keyboard Shortcut: Ctrl+L": no Ctrl+L lock shortcut handler found.
- [ ] spec &sect;27.12 "Auto-Lock Timer": no auto-lock timer with checkAutoLock() algorithm, kAutoLockTimeoutLateMs=3000ms grace, or lockByPasscode()/unlockPasscode() sequences found.
- [ ] spec &sect;27.13 "Notification Behavior When Locked": no notification content hiding when passcode-locked found.

## &sect;28 -- Two-Factor Authentication Setup
- [ ] spec &sect;28.1 "Entry Point": no "Two-Step Verification" button in Privacy & Security with dynamic On/Off/Loading label found.
- [ ] spec &sect;28.2 "Step Architecture": no 2FA wizard step system with StepData model, common header (Lottie 100x100, subtitle, description), common input fields (256px PasswordInput), error labels, done buttons, or link buttons found.
- [ ] spec &sect;28.3 "Flow 1 -- Create New Password": no Start screen, Create Password screen (interactive lock Lottie), Password Hint screen, Recovery Email screen, or Email Confirmation screen found.
- [ ] spec &sect;28.4 "Flow 2 -- Check Password & Manage": no check password screen with hint display, "Forgot password?" link (3-state machine: Recover/CancelReset/Reset), countdown timer, or Manage screen with Change Password/Change Email/Disable Password buttons found.
- [ ] spec &sect;28.7 "Password Recovery": no recovery flow with email code entry, "Can't access email?" option, or timed reset countdown found.
- [ ] spec &sect;28.8 "Login-Time 2FA Entry": no PasswordCheckWidget for login flow with 380px content width, introPassword style, or recovery mode found.

## &sect;29 -- Chat Export
- [ ] spec &sect;29.2 "Export Panel Window": panel is implemented as a Dialog (showDialog) rather than a SeparatePanel (standalone frameless window). The spec requires a 364x480px standalone panel with onAllSpaces=true -- `chat_export.dart` line 165 uses showDialog instead.
- [ ] spec &sect;29.5.3 "Skip File Link": skip file link appears after 5 seconds but uses AnimatedOpacity fade -- spec says it should fade in with anim::type::normal. Implementation matches intent but skip link position is inline rather than between progress rows and about label as spec requires.
- [ ] spec &sect;29.5.5 "Cancel/Stop Button": stop button uses ElevatedButton with 4px border radius -- spec requires attentionBoxButton style (200x44px, 15px semibold font, text at 12px from top). Button radius should match spec's pill/round style.
- [ ] spec &sect;29.7.2 "Done Button": "Show My Data" button uses 4px radius -- spec requires defaultActiveButton style (200x44px). Button does not actually open the file manager via File::ShowInFolder(path) -- it just closes the dialog.
- [ ] spec &sect;29.9 "In-App Export Top Bar": `ExportTopBar` exists in `chat_export.dart` but uses a 1px progress bar at bottom instead of a `mediaPlayerPlayback` style FilledSlider. Top bar background should use `mediaPlayerBg` token, not `windowBg`.
- [ ] spec &sect;29.3.5 "Output Format Section": location label uses hardcoded "Downloads/TelegramExport" -- spec requires a clickable link that opens FileDialog::GetFolder native folder picker. No actual folder picker integration exists.
- [ ] spec &sect;29.4.2 "Calendar Box": calendar uses 320px width and custom grid -- spec requires `exportCalendarSizes` with 42x38 cells, 32px inner circle, 14px side padding. Current cell sizes are derived from `(320-28)/7` which is approximately 41.7px wide but cell height is 38px (matches spec).

## &sect;30 -- Bot Interactions
- [ ] spec &sect;30.1 "Bot Command Button & Menu Button": no historyBotCommandStart (44x46px) slash button or historyBotMenuButton (RoundButton, 30px height, max 160px label) found in any compose area widget.
- [ ] spec &sect;30.2 "Command Autocomplete Dropdown": no /command autocomplete dropdown with 40px row height, 33px bot userpic, case-insensitive filtering found.
- [ ] spec &sect;30.3 "Inline Bot Results Panel": no @botname inline results panel with 345px width, mosaic grid layout, photo/GIF/sticker/video/article result types found.
- [ ] spec &sect;30.4 "Reply Keyboard (Bot Keyboard Below Compose)": no full-width reply keyboard with botKbButton style (10px margin, 38px height), tiny variant (4px margin, 25px height), color variants (Normal/Primary/Danger/Success), or show/hide toggle found.
- [ ] spec &sect;30.5 "Inline Keyboard (Buttons Under Messages)": no inline keyboard rendering below message bubbles with msgBotKbButton style (2px margin, 36px height), 20+ button types (Default/Url/Callback/Buy/WebView/CopyText etc.), hover animation, or loading spinner found.
- [ ] spec &sect;30.6 "Web Apps / Mini Apps": `web_app_panel.dart` exists but needs audit against spec's SeparatePanel (384x694px default), header bar (bot name + custom emoji + verified badge), bottom bar (@username), main/secondary buttons (40px height), progress indicator (3px stroke), and theme integration. File was not fully read.
- [ ] spec &sect;30.7 "Bot Start Screen": no bot start screen with EmptyPainter, GenerateManagedBotImage (280x140px), chatIntroWidth=224px sticker area, or historyComposeButton "START"/"RESTART" button (46px height) found.
- [ ] spec &sect;30.8 "Game Messages": no game card rendering with webPageTitleStyle, "GAME" badge (msgDateFont, semi-transparent background), or "Play" button (36px height, historyPageButtonLine=1px separator) found.
- [ ] spec &sect;30.9 "Login URL Buttons": no Auth confirmation dialog with bot userpic, account switcher, device/location details, checkbox options, or match code display found.
- [ ] spec &sect;30.10 "Bot Payments": `payment_panel.dart` exists but needs audit against spec's paymentsPanelSize=392x600px, invoice cover (80x80 thumbnail), prices section, tips buttons (28px height), shipping form, and submit button. File was not fully read.

## &sect;31 -- Saved Messages
- [ ] spec &sect;31.1 "Saved Messages Chat Entry": `chat_state.dart` does not treat Saved Messages as a special peer with a dedicated bookmark icon (EmptyUserpic::PaintSavedMessages with blue gradient #5caffa to #408acf and vector bookmark shape). Chat list may use a generic avatar instead.
- [ ] spec &sect;31.2 "Saved Messages Sub-Peers (Sublists)": no sublist-based browsing mode where forwarded messages are grouped by source peer found in `chat_state.dart`.
- [ ] spec &sect;31.3 "Sublist Navigation & Info Panel": no SublistsWidget with dynamic chat count, media filter section (8 media-type buttons), or sublist row rendering found.
- [ ] spec &sect;31.4 "My Notes": no "My Notes" sublist with dedicated notepad icon (dialogsMyNotesUserpic = "dialogs/avatar_notes") found.
- [ ] spec &sect;31.6 "Reaction Tags System": no tag-based categorization with MyTagInfo struct, tag operations (increment/decrement/rename), or SearchTags bar widget found.
- [ ] spec &sect;31.7 "Tag-Based Search & Filtering": no SavedMessagesTagBar (SearchTags) with 18px-tall chips in price-tag shape, click-to-filter, right-click tag rename menu, or tag query encoding (#tag-custom:, #tag-emoji:) found.
- [ ] spec &sect;31.8 "Forward-to-Saved Flow": no self-forwards tagger with post-forward tag suggestion toast (3s auto-dismiss) found.
- [ ] spec &sect;31.9 "Subsection Tabs": no horizontal/vertical subsection tabs for saved messages with 36px strip height, 64px toggle button, dynamic tab width formula, or scroll-to-active logic found.

## &sect;32 -- Stories
- [ ] spec &sect;32.1 "Stories Bar (Chat List)": no horizontal stories strip above chat list with collapsed (35px height, 21px avatar) and expanded (77px height, 42px avatar) states, gradient ring for unread (#0dcc39 to #0992ef), or expansion trigger at 0.72 overscroll ratio found.
- [ ] spec &sect;32.2 "Story Viewer Overlay": no full-screen story viewer with 540x960px max content, 8px corner radius, sibling previews, segmented progress bar (2px height, 4px gap), or navigation (tap left/right third) found.
- [ ] spec &sect;32.3 "Story Header": no story header overlay with 28px avatar, name at (50,0), date at (50,17), privacy badges, or timestamp display found.
- [ ] spec &sect;32.4 "Story Reactions": no reaction panel (210px width), like button (42x42), or suggested reaction bubbles found.
- [ ] spec &sect;32.5 "Story Reply Compose": no story reply compose bar with #2c333d background, 21px corner radius, or storiesComposeWhiteText (#ffffff) found.
- [ ] spec &sect;32.9 "Story Views List": no "Who Viewed" popup with stacked avatars (24px, 9px shift, 4px stroke) or 240x320px menu found.
- [ ] spec &sect;32.10 "Stealth Mode": no stealth mode dialog with logo, 42px button, cooldown countdown, or toast notifications found.
- [ ] spec &sect;32.15 "Story Creation Editor": `story_editor.dart` implements the editor but has notable gaps:
- [ ] spec &sect;32.15.3 "Video Trim Slider": no video trim slider with 12 thumbnail frames, draggable handles, or duration constraints (1s-60s) found -- `story_editor.dart` only supports image files via FilePicker.
- [ ] spec &sect;32.15.4 "Sticker Picker": no sticker panel integration via StickersPanelController/TabbedPanel with emoji/stickers/custom emoji tabs found -- `story_editor.dart` has no sticker insertion.
- [ ] spec &sect;32.15.5 "Text Tool": text tool exists in `story_editor.dart` with alignment cycling, background styles (none/filled/outlined/shadowed), font picker, and color picker. However, only 4 fonts are offered (Regular/Typewriter/Serif/Handwriting) vs spec's 7. No font-size slider (spec requires vertical brush-size-style control mapped to 14-72pt) exists -- font size is hardcoded to 32.
- [ ] spec &sect;32.15.8 "Privacy Selector": privacy dialog exists in `story_editor.dart` but uses a generic AlertDialog with RadioListTile instead of the spec's chip-row with 32px height / 16px radius pills above the caption bar.
- [ ] spec &sect;32.15.9 "Duration Picker": duration picker exists as a PopupMenu with 6h/12h/24h/48h options but lacks the premium gate (lock icon on 48h for non-premium users) specified in the spec.
- [ ] spec &sect;32.15.10 "Save to Profile / Allow Sharing Toggles": toggles exist in `story_editor.dart` with correct switch visual (36x20px pill, #4DB8FF active). "Allow Sharing" correctly hidden for Close Friends. However, subtitle text ("Story will stay on your profile after it expires" / "Let viewers share your story as a link") is missing.

## &sect;33 -- Contacts Screen
- [ ] spec &sect;33.1 "Sort toggle button": `contacts_screen.dart` uses Icons.access_time / Icons.sort_by_alpha as Material icons -- spec requires specific `contactsSortOnlineIcon` / default icon, and a 48x54px hit area with 42px ripple circle at (1px, 6px). The current implementation is close but not pixel-exact.
- [ ] spec &sect;33.2 "Stories Bar": story ring rendering exists on contact rows via `_ContactStoryRingPainter` with gradient ring and segmented arcs. However, it does not use the per-row inline ring approach described in the spec (&sect;33.2 contactsWithStories style override: 52px row height, photo at 18/5, name at 70/7, status at 70/27). The code uses the standard 56px row height with 42px avatar.
- [ ] spec &sect;33.4 "Contact List Layout": row dimensions match spec (56px height, 42px avatar, name at 74/9, status at 74/30). Avatar position uses 16px left / 7px top which matches spec's (16, 7). Name badges (verified, premium, scam, fake) are rendered inline -- matches spec.
- [ ] spec &sect;33.5 "Add Contact Dialog": `_AddContactBox` exists with first name, last name, phone fields, country code picker, and retry state. Field left padding is 49px matching spec's `contactPadding.left()`. Country picker exists with search, 36px row height, name+code layout. Missing: no field icon rendered at contactIconPosition (-5, 23).
- [ ] spec &sect;33.5 "Country Code Picker": `_CountrySelectBox` exists with search, row height 36px, name left-aligned + "+code" right-aligned. Matches spec (no flag emoji, text-only). Keyboard navigation (arrow up/down) is not implemented. No-results state shows "No countries found" -- spec uses `lng_country_none`. Missing: PageUp/PageDown navigation, Enter/Return to select.
- [ ] spec &sect;33.6 "Edit Contact Dialog": `_EditContactBox` exists with cover widget (108px height, 72x72 avatar at 19/18, name at 109/33, status at 109/57) -- matches spec's `infoEditContactCover` dimensions exactly. Live name update works. Phone displays with formatting or "Mobile hidden". Missing: notes field with emoji panel and character limit. Missing: "Suggest photo" button with Lottie animation.
- [ ] spec &sect;33.7 "Delete Contact Confirmation": delete confirmation exists with proper red "Delete" button. However, it uses a generic AlertDialog rather than the spec's ConfirmBox with attentionBoxButton style.
- [ ] spec &sect;33.8 "Contact Actions (Context Menu)": context menu has Edit Contact, Share Contact, Delete Contact, Block User. Missing: "Add Contact" (for non-contacts), proper icon tokens (menuIconInvite, menuIconEdit, menuIconDeleteAttention, menuIconBlock).
- [ ] spec &sect;33.9 "Mutual Contact Indicator": no mutual contact indicator implemented -- matches spec (spec says no visual indicator exists in contacts list UI, only internal flag).
- [ ] spec &sect;33.11 "Sort Options": online sort exists but uses simple isOnline + alphabetical fallback rather than spec's `min(user.lastseen().onlineTill(), now + 1) + 1` descending key. Missing: 3000ms throttle timer (`kSortByOnlineThrottle`) for rapid online status updates.
- [ ] spec &sect;33.12 "Empty State": empty state shows "No contacts yet" / "No contacts found" -- spec requires `lng_blocked_list_not_found` for search results. Loading state shows CircularProgressIndicator instead of "Loading..." text label.

## &sect;34 -- Calls History
- [ ] spec &sect;34.2 "Box Structure": `calls_screen.dart` uses Scaffold (full page) rather than spec's GenericBox (modal dialog). The spec requires a box with title "Calls", Close button, and three-dot menu -- the implementation uses an AppBar with back arrow instead.
- [ ] spec &sect;34.3 "Active Group Calls Section": active group calls section exists with AnimatedSize SlideWrap, channel type label, and join button. Section title "Active Group Calls" matches spec. Missing: `peerListSingleRow` style override.
- [ ] spec &sect;34.5 "Call Row Design": row dimensions match spec (56px height, 42px avatar at (16,7), name at semibold 13px). Grouping logic correctly groups same peer/date/type calls. Missing: name position should be (74, 9) per spec but code uses a Row layout rather than absolute positioning.
- [ ] spec &sect;34.6 "Call Direction & Type Indicators": direction arrows use Icons.call_made / Icons.call_received with green (answered) / red (missed) colors. Transform.translate offset (-2, 1) matches spec's `callArrowPosition`. Arrow-to-text skip is SizedBox(width:4) matching spec's `callArrowSkip=4px`.
- [ ] spec &sect;34.7 "Redial Button": redial button exists with voice (Icons.call) and video (Icons.videocam) variants. Size is SizedBox(width:40, height:56) matching spec's 40x56px. Missing: ripple animation with 40px area at (0,8).
- [ ] spec &sect;34.8 "Status Text Format": timestamp formatting matches spec -- today shows bare time, yesterday shows "yesterday at HH:MM", older shows "Mon DD at HH:MM". Grouped calls show "(N) timestamp" format.
- [ ] spec &sect;34.9 "Context Menu": context menu has "Delete" and "Show in Chat" -- matches spec. Uses custom `showTelegramMenu` with icon colors. Missing: specific icon tokens (menuIconDelete, menuIconShowInChat).
- [ ] spec &sect;34.11 "Clear Call History Dialog": clear dialog exists with "Also delete for other participants" checkbox, Clear/Cancel buttons. Matches spec's structure. Uses `AlertDialog` instead of `GenericBox`.
- [ ] spec &sect;34.12 "Create Call Button": create call button exists with accent-colored circle icon, "Create Call" label, and description text showing participant limit. Highlight animation exists. Missing: `inviteViaLinkButton` style, FloatingIcon at `inviteViaLinkIconPosition`.
- [ ] spec &sect;34.13 "Rate Call Dialog": no rate call dialog with 5-star rating row (36x36 stars), optional comment field (200 char limit, 135px max height), or Send/Cancel buttons found.
- [ ] spec &sect;34.14 "Call Settings Section": call settings screen exists with Output/Input/Call Devices/Camera/Other sections, device selectors, level meter (44 lines, 3px width, 5px spacing, 18px height -- matches spec). Missing: live camera preview (shows placeholder instead).
- [ ] spec &sect;34.15 "Active Call Top Bar": no 38px colored top bar with mute toggle (41x38px), duration label, signal bars, info label, or hangup button found. No gradient background animation for group calls (green/blue/purple states).
- [ ] spec &sect;34.17 "Create Conference Call Box": `_CreateCallBox` exists with participant picker, invite-via-link button, prioritized contacts section, and conference size limit (200) with overflow toast. Matches spec structure. Missing: `createCallListItem` style override (52px height, 40px avatar at (12,6), name at (63,7)), video/audio element buttons use correct 36x52px size.

## &sect;35 -- Empty, Error & Loading States
- [ ] spec &sect;35.1 "Empty Chat List": no Lottie `no_chats.tgs` animation at 120x120px, no "You have no conversations yet" text in dialogEmptyButtonLabel style (semibold), no "New Message" action button at bottom found in `app_state.dart`.
- [ ] spec &sect;35.5 "Chat List Loading": no skeleton row loading animation with 60px name bar width, 100px status bar width, or glare sweep (1000ms slide + 1000ms pause) found. Loading shows CircularProgressIndicator instead of skeleton placeholders.
- [ ] spec &sect;35.6 "No Chat Selected": service-message bubble "Select a chat to start messaging" may exist in the shell but not verified in `app_state.dart`. Needs check in shell.dart or equivalent.
- [ ] spec &sect;35.7 "Empty Search Results": no Lottie `noresults.tgs` at 100x100px, no bold "No Results" title, no "There were no results for..." body text, no "Search in All Messages" link found.
- [ ] spec &sect;35.10 "Empty Shared Media Tabs": no per-type icons (infoEmptyPhoto/Video/Audio/File/Voice/Link) at 1/3 height position, no "No photos/videos/files here yet" labels at 40px from bottom found.
- [ ] spec &sect;35.22 "Connection State Widget": no "Connecting..." pill with 20x20px radial spinner, 150ms fade animation, bottom-left anchoring, or proxy icon found. No "Reconnect in N s..." countdown with "Try now" retry link.
- [ ] spec &sect;35.33 "Skeleton Animation": no skeleton animation system with kSlideDuration=1000ms, kWaitDuration=1000ms, kBaseAlpha=0.5, kGradientAlpha=0.2 constants for FlatLabel loading placeholders found.
- [ ] spec &sect;35.24 "File Download States": no radial progress indicator (InfiniteRadialAnimation) with msgFileRadialLine=3px stroke for file downloads, no "Ready"/"Downloading"/"Loaded"/"Failed" status text transitions found.

## &sect;36 -- Common Dialog & Modal Patterns
- [ ] spec &sect;36.1 "Box/Dialog Infrastructure": `confirm_box.dart` implements TelegramBox with correct dimensions (320/364px width, 8px radius, 48px title height at 24/13 position, 200ms animation). Box animation uses easeOutCirc for dim + linear opacity -- matches spec. Enter key triggers confirm -- matches spec. Missing: boxMaxListHeight=492px is implemented correctly. Missing: close X button uses `box_button_close` icon token -- implementation uses Icons.close.
- [ ] spec &sect;36.2 "Confirmation Dialogs": `showConfirmBox` implements ConfirmBoxArgs pattern with text/confirmed/cancelled/confirmText/cancelText/confirmStyle/title/inform parameters. Destructive variant uses attentionButtonFg. Enter triggers confirm. Missing: `strictCancel` flag, `labelFilter` for links, custom `labelPadding`.
- [ ] spec &sect;36.2 "Delete/Leave ConfirmBox": `showDeleteConfirmBox` implements all four modes (single/bulk/clear/leave) with correct body text, revoke checkbox, moderate panel (Ban/Report/DeleteAll), and dynamic confirm label. Matches spec closely.
- [ ] spec &sect;36.5 "Choice Dialogs (SingleChoiceBox)": `showSingleChoiceBox` exists with radio buttons and auto-close on selection. Matches spec structure.
- [ ] spec &sect;36.6 "Date/Time Picker": CalendarBox exists in `chat_export.dart` with 320px width, month navigation, day grid. Missing: `exportCalendarSizes` with exact 48x40 cells / 34px cellInner (current cells are approximately right). Missing: ChooseDateTimeBox with 95px scheduleHeight, 136px date field, 72px time field.
- [ ] spec &sect;36.9 "Toast / Snackbar Notifications": `telegram_toast.dart` exists (not fully read). Needs audit against spec's defaultToast (padding 19/13/19/12, maxWidth 480px, radius 6px, fadeIn 200ms, fadeOut 1000ms, slide 160ms, duration 1500ms).
- [ ] spec &sect;36.10 "Context Menus": no PopupMenu with spec's defaultPopupMenu (8px radius, 200ms show / 150ms hide, defaultPanelAnimation clip-reveal, defaultMenu item padding 17/8/17/7, width 156-300px, separator 1px at margins 0/5/0/5) found as a reusable component. The code uses `popup_menu.dart` but it was not fully read.
- [ ] spec &sect;36.11 "Tooltip Popups": `telegram_tooltip.dart` exists (not fully read). Needs audit against spec's defaultTooltip (padding 5/2/5/2, show delay 1000ms, maxWidth 800px, 12 lines max) and ImportantTooltip (4px radius, 8x4px arrow, 200ms animation).
- [ ] spec &sect;36.7 "Color Picker (ColorEditor)": HSL color picker exists in `story_editor.dart` (_HSLColorPickerDialog) with H/S/L sliders. Missing: 2D gradient picker square (colorPickerSize), hue slider (colorSliderWidth), opacity slider (RGBA mode), HSB fields, RGB fields, hex result field, and current-vs-new color swatches. The implementation is a simplified 3-slider version.
- [ ] spec &sect;36.12 "Permission Request Dialogs": `confirm_box.dart` implements permission flow with getPermissionStatus, requestPermissionOrFail, and showPermissionDeniedBox. Text matches spec ("needs microphone access..."). openSystemSettingsForPermission covers Linux/macOS/Windows. Microphone+Camera sequential request for video calls implemented correctly.
- [ ] spec &sect;36.13 "Report Flow": two-step report flow exists (showReportReasonBox with 9 reason buttons + showReportDetailsBox with optional comment). Matches spec's ReportReasonBox and ReportDetailsBox. Report reaction variant exists. Missing: specific icon tokens for report reasons.
- [ ] spec &sect;36.14 "Share Box": share contact box exists in `contacts_screen.dart` with grid layout, multi-selection, comment field. Missing: forward options (sender names/captions), stars count display, dark mode style override.
- [ ] spec &sect;36.15 "Sticker Toast": no sticker/emoji pack notification toast with clickable link to open sticker set found.
# Audit: §37-§49 Popups, Formatting & Interactions

## §37 — Desktop Notifications

- [ ] spec §37.3.3 "Corner Selection": notification_popup.dart implements all 5 corners correctly, but `_recalcPositions` does not apply RTL layout swap (left/right should swap in RTL locales per spec) — `notification_popup.dart`
- [ ] spec §37.3.4 "Title text font": spec says title uses `semiboldFont` (13px semibold), code uses `fontSize: 13, fontWeight: FontWeight.w600` which is correct weight but spec says the font token is `st::semiboldFont` — font size is correct but not verified against AyuGram's exact 13px semibold Open Sans — `notification_popup.dart:514`
- [ ] spec §37.3.4 "Message text": spec says message text drawn with `dialogsTextFont` up to 2 lines with right-edge fade-out mask (`notifyFadeRight`); code uses `TextOverflow.ellipsis` instead of a fade-out gradient — `notification_popup.dart:528-530`
- [ ] spec §37.3.4a "Reply field width": spec says reply field width = `notifyWidth - notifySendReply.width - 2*borderWidth` = 282px; code uses `Expanded` in a Row which should produce a similar result but the exact pixel math is not enforced — `notification_popup.dart:731-763`
- [ ] spec §37.3.4a "Reply field text margins": spec says text margins are 8/8/8/6 px; code uses `contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)` missing the asymmetric 6px bottom — `notification_popup.dart:757`
- [ ] spec §37.3.5 "Shift animation": spec says notifications animate their vertical shift over 150ms when added/removed; code sets `currentY = shift` instantly in `_recalcPositions` with no animation — `notification_popup.dart:288-290`
- [ ] spec §37.3.5 "Input polling": spec says when `WaitForInputForCustom` is true and no user input has occurred, auto-dismiss is deferred with 300ms polling; code does not implement input-detection polling at all — `notification_popup.dart`
- [ ] spec §37.3.6 "Ctrl+click": spec says Ctrl+click on notification body opens chat in a separate window; code has no Ctrl modifier detection on tap — `notification_popup.dart:219-223`
- [ ] spec §37.3.7 "Queue overflow eviction": spec says oldest non-reply, non-hover notification is evicted when at capacity and queue is non-empty; `DefaultManager` simply queues the item without evicting any shown notification — `notification_manager_default.dart:60-65`
- [ ] spec §37.3.7 "Hide All button appears with 2+ or queue non-empty": code checks `_active.length >= 2 || _queue.isNotEmpty` in `showHideAll` which is correct, but the popup overlay checks `_popups.length >= 2` only and does not check the queue — `notification_popup.dart:383`
- [ ] spec §37.4.1 "Title composition: monoforum sublist": spec defines monoforum sublist title pattern `SublistPeerShortName (ChatName)`; the `composeNotificationContent` function does not handle monoforum sublists — `notification_types.dart:226-245`
- [ ] spec §37.4.3 "Album text": spec says albums display as `lng_in_dlg_album` ("Album"); code correctly produces "Album" in `_flushGroupedBuffer` — verified OK
- [ ] spec §37.12.1 "Hidden userpic placeholder": spec says the placeholder is a square app logo at 62x62px; code shows a square container with a single letter 'U' as placeholder instead of the app logo — `notification_popup.dart:639-662`
- [ ] spec §37.13 "Userpic caching size": spec says native userpic cache is 64px PNG; code resizes to 64x64 correctly — verified OK in `notification_manager_native.dart:59`

## §38 — User Profile Popup

- [ ] spec §38.1 "Triggers": spec says PeerShortInfoBox triggers from Ctrl+Click on "View Profile" context menu item; the `showPeerShortInfoBox` function exists but there is no evidence of Ctrl modifier detection at the call site — `peer_short_info.dart:38`
- [ ] spec §38.2 "Phone field": the info rows show phone for DM users correctly, but spec says single-line fields use `setDoubleClickSelectsParagraph(true)` for easy selection; code uses `SelectableText` which does not configure this — `peer_short_info.dart:667-698`
- [ ] spec §38.2 "Notes field": spec says a "Notes" row with personal notes should appear; code does not implement a Notes info row — `peer_short_info.dart:526-637`
- [ ] spec §38.2 "Video profile photos": spec says if the current profile photo has a video version it auto-plays in a loop; code shows only static images, no video playback — `peer_short_info.dart:323-349`
- [ ] spec §38.3 "Scrolling parallax": spec says cover image scrolls with parallax and name/status labels fade based on scroll; code implements parallax via `_kParallaxFactor = 0.3` and label fade via `_labelOpacity` — verified implemented, but the parallax factor is custom (spec does not define a specific factor)
- [ ] spec §38.5 "Scroll bar": spec says scroll bar is 8px wide, 3px inset, 150ms show animation, 1000ms hide delay; code uses `RawScrollbar` with matching `_kScrollBarWidth=8`, `_kScrollBarInset=3`, `_kScrollShowDuration=150ms`, `_kScrollHideDelay=1000ms` — verified OK
- [ ] spec §38.9 "Right-click context menu": spec says right-click shows "Open in New Window" menu item only if peer is not already open in a separate window; code always shows the menu item without checking if already open — `peer_short_info.dart:185-208`
- [ ] spec §38.11 "Premium effects": spec says the ShortInfoBox does NOT display verified/scam/fake badges or emoji status next to name; code renders plain text name which is correct — verified OK
- [ ] spec §38.12 "Keyboard navigation": spec says no keyboard shortcuts to navigate profile photos; code has no keyboard photo navigation — verified OK

## §39 — Photo & Avatar Cropping Dialog

- [ ] spec §39.2 "Full-window layer": spec says the editor is a full-window layer that cannot be closed by clicking outside; code uses `barrierDismissible: false` which is correct — verified OK
- [ ] spec §39.2 "Blurred background": spec says background is a downscaled-4x, 24px Gaussian blurred, dimmed screenshot; code uses `BackdropFilter` with `sigmaX/Y: 24` which is a real-time blur rather than the pre-rendered screenshot approach — acceptable Flutter adaptation, but missing the cross-fade animation between old/new backgrounds on resize — `photo_crop_editor.dart:490-510`
- [ ] spec §39.4 "Crop overlay": crop shape rendering (ellipse, roundedRect, rect) with fade overlay, border, corner indicators, and 3x3 grid all implemented correctly — verified OK
- [ ] spec §39.5 "No zoom controls": spec explicitly states no zoom controls exist; code has none — verified OK
- [ ] spec §39.7 "Rotation": spec says rotate button uses `photo_editor/rotate-flip_horizontal` icon; code uses `Icons.rotate_right` Material icon instead of the specific AyuGram icon — `photo_crop_editor.dart:1100`
- [ ] spec §39.7 "Flip icon change": spec says flip button icon changes to active-colored variant when flipped; code correctly switches between `_IconState.active` and `_IconState.idle` for the flip button — verified OK
- [ ] spec §39.9 "Emoji Builder cycle timer": spec says suggested stickers rotate with 1500ms cycle; code uses `_kSuggestedCycleDuration = 1500ms` — verified OK
- [ ] spec §39.11 "Done button label": spec says for profile photos the confirm button reads "Set Photo", for suggestions "Suggest", for general editing "Done"; code accepts a custom `doneLabel` parameter defaulting to "Set Photo" — partially OK, but no automatic label switching based on context
- [ ] spec §39.14 "Grid overlay fade": spec says grid fades in instantly when drag starts, fades out over 200ms when drag ends; code sets `_gridController.value = 1.0` instantly on pointer down and calls `_gridController.reverse()` on pointer up — verified OK

## §40 — Send Files Dialog

- [ ] spec §40.2 "Album preview drag-to-reorder": the `send_files_box.dart` file exists (30435 tokens, could not read fully), but based on the spec, album drag-to-reorder requires shrink animation at 150ms and layout transition at 200ms; needs verification that these animations exist — `send_files_box.dart`
- [ ] spec §40.3 "Group files checkbox": spec says a "Group files" checkbox should be visible when 2+ compatible files are present; needs verification in send_files_box.dart — `send_files_box.dart`
- [ ] spec §40.3 "Send as documents checkbox": spec says an inverted checkbox controls whether images are sent as documents; needs verification — `send_files_box.dart`
- [ ] spec §40.4 "HD badge": spec says a rounded "HD" pill overlay appears on preview when high-quality is enabled; needs verification — `send_files_box.dart`
- [ ] spec §40.5 "Per-file spoiler toggle": spec says right-click context menu on individual thumbs shows "Spoiler effect" toggle; needs verification — `send_files_box.dart`
- [ ] spec §40.6 "Caption field character limit": spec says `kMaxMessageLength = 4096` with a `CharactersLimitLabel`; needs verification — `send_files_box.dart`
- [ ] spec §40.6 "Per-file captions": spec says each file block can have its own caption when sending as documents; needs verification — `send_files_box.dart`
- [ ] spec §40.9 "Ctrl+O shortcut": spec says Ctrl+O opens the add-file dialog; needs verification — `send_files_box.dart`
- [ ] spec §40.10 "Send menu": spec says right-click on send button opens a menu with silent send, schedule, spoiler toggle, caption position, photo quality; needs verification — `send_files_box.dart`

## §41 — Message Formatting Toolbar

- [ ] spec §41.1 "No floating toolbar": spec says there is NO floating toolbar on text selection, only right-click context menu + keyboard shortcuts; code implements `_ComposeFormattingOverlay` which appears to be a context-menu-based approach — `chat_view.dart:11423`
- [ ] spec §41.4 "Date formatting option": spec says Ctrl+Shift+D inserts a date via `CalendarBox` then `ChooseDateTimeBox`; code likely does not implement this custom date entity formatting — needs verification in `chat_view.dart`
- [ ] spec §41.4 "Quote formatting": spec says Ctrl+Shift+. applies blockquote; needs verification that this keyboard shortcut is bound — `chat_view.dart`
- [ ] spec §41.6 "Edit Link Dialog": spec says Ctrl+K opens `EditLinkBox` with text field + URL field, 320px wide box; needs verification of implementation — `chat_view.dart`
- [ ] spec §41.7 "Code block language dialog": spec says clicking a code block's language header opens `EditCodeLanguageBox`; needs verification — `chat_view.dart`
- [ ] spec §41.9 "Markdown auto-conversion disabled": spec says markdown syntax is NOT auto-converted while typing, only at send time; needs verification — `chat_view.dart`

## §42 — Reactions Detail Popup

- [ ] spec §42.2 "Context menu popup (Mode A)": spec defines a context-menu popup with user submenu triggered by right-clicking a reaction button; code implements a full modal panel (Mode B) via `ReactionsDetailPanel.show()` but lacks the inline context-menu Mode A — `reactions_detail.dart:34-70`
- [ ] spec §42.3 "Title text": spec says title adapts: "Seen by N" / "Listened by N" / "Reactions"; code builds title as "Reactions . N" which does not include seen/listened variants — `reactions_detail.dart:276-280`
- [ ] spec §42.4.2 "Pill geometry": spec says pill height is 32px, corner radius is 16px (fully rounded); code uses `height: 32` and `BorderRadius.circular(16)` — verified OK
- [ ] spec §42.4.3 "Container padding": spec says container outer padding is `margins(12,10,12,10)`; code uses `EdgeInsets.fromLTRB(12, 10, 12, 10)` — verified OK
- [ ] spec §42.4.3 "Inter-tab gap": spec says horizontal and vertical gaps are 8px; code uses `Wrap(spacing: 8, runSpacing: 8)` — verified OK
- [ ] spec §42.4.4 "Selection transition duration": spec says 150ms; code uses `AnimationController(duration: Duration(milliseconds: 150))` — verified OK
- [ ] spec §42.4.5 "Ripple animation": spec says each tab supports ripple; code uses `InkWell` with `borderRadius` which provides Material ripple — verified OK
- [ ] spec §42.5.1 "Row geometry Mode B": spec says row height 58px, avatar 46px at (18,6), name at (79,11); code matches exactly — verified OK in `reactions_detail.dart:658-701`
- [ ] spec §42.5.2 "Right-action emoji right margin": spec says right margin 27px from row right edge; code uses `right: 27` — verified OK
- [ ] spec §42.5.3 "Date line in Mode A context menu": spec says per-user date line only in Mode A; code does not implement Mode A at all, so no date lines in the context menu — `reactions_detail.dart`
- [ ] spec §42.6 "Pagination": spec says first page 20, subsequent 100; code uses `_kPerPageFirst = 20` and `_kPerPageMore = 100` — verified OK
- [ ] spec §42.12 "Panel width": spec says desired width 392px with minimum layer margin 48px; code uses `maxWidth: 392` — verified OK
- [ ] spec §42.16 "Blocked user filtering": code implements blocked user filtering via `_blockedIds` set — verified OK

## §43 — Read Receipts Detail

- [ ] spec §43.1 "Trigger": spec says read receipts are accessed via right-click context menu "Seen by N" item; code has a `who_read` context menu item in chat_view.dart — implementation exists
- [ ] spec §43.3 "1:1 private chat WhenReadAction": spec says private chats show "Read at HH:mm" with double-check icon instead of user list; code integrates read participants into the ReactionsDetailPanel Read tab but does not have a separate single-line WhenRead action for 1:1 chats — `reactions_detail.dart`
- [ ] spec §43.4.1 "Row geometry Mode A (context menu submenu)": spec defines 40px rows with 30px avatar for context menu; code only implements Mode B (58px rows, 46px avatar) — no Mode A submenu exists — `reactions_detail.dart`
- [ ] spec §43.5 "Loading state": spec says summary shows "Loading..." while unknown; code shows a `CircularProgressIndicator` while loading which is functionally equivalent — `reactions_detail.dart:313-316`
- [ ] spec §43.8 "Time formatting": spec says timestamps formatted as "Today, HH:mm" / "Yesterday, HH:mm" / "Mon DD, HH:mm"; code implements `_formatReadDateLocal` with matching logic — verified OK in `reactions_detail.dart:777-795`
- [ ] spec §43.10.3 "WhenRead line for private chats": spec defines `whenReadPadding`, `whenReadIconPosition`, `whenReadSkip` for the private-chat read-time row; code does not implement this separate private-chat read-time row — `reactions_detail.dart`
- [ ] spec §43.12 "Privacy states (MyHidden/HisHidden)": spec says privacy states show "Read time hidden" with a clickable "Show" pill button; code does not handle `WhoReadState::MyHidden` or `HisHidden` states — `reactions_detail.dart`

## §44 — Spoiler Animation

- [ ] spec §44.1 "Text spoiler rendering": spec says text behind spoiler is drawn at `opacity = 1 - spoilerOpacity` for cross-fade; `SpoilerTilePainter` draws particle overlay at `opacity = 1 - revealProgress` and the text below is expected to be drawn separately by the caller — particle overlay is correct, but the text cross-fade depends on the message_bubble integration
- [ ] spec §44.3 "Particle counts": spec says text spoiler = 9000 particles, image = 3000; code uses `count = isText ? 9000 : 3000` — verified OK in `spoiler_animation.dart:138`
- [ ] spec §44.3 "Frame count and duration": spec says 60 frames at 33ms (~30fps); code uses `_kFrameCount = 60` with `33ms` frame step — verified OK
- [ ] spec §44.3 "Canvas size": spec says 128dp; code uses `_kCanvasSize = 128.0` — verified OK
- [ ] spec §44.3 "Sprite variants": spec says 5 variants with size variation; code uses `_kSpriteVariants = 5` with correct size variation logic — verified OK
- [ ] spec §44.4 "Reveal duration": spec says reveal animation over 200ms (`fadeWrapDuration`); the `SpoilerTilePainter` accepts `revealProgress` parameter but the 200ms duration must be driven by the caller — `spoiler_animation.dart:266`
- [ ] spec §44.5 "Compose field spoiler": spec says `FieldSpoilerOverlay` with cursor-based 50% opacity (`kSpoilerHiddenOpacity = 0.5`); code provides `SpoilerAnimationMixin` but does not implement compose-field-specific cursor-based opacity reduction — `spoiler_animation.dart`
- [ ] spec §44.6 "Spoiler in notifications": spec says spoiler chars replaced with U+259A; code implements `_applySpoiler` using `_spoilerBlock = '▚'` correctly, and `_maskLoginCodes` with the matching regex — verified OK in `notification_types.dart:199-329`
- [ ] spec §44.7 "Auto-pause timeout": spec says `kAutoPauseTimeout = 1000ms`; code uses `_kAutoPauseTimeoutMs = 1000` — verified OK
- [ ] spec §44.7 "Color cache capacity": spec says `kDefaultSpoilerCacheCapacity = 24`; code defines `_kColorCacheCapacity = 24` but does not implement the actual per-color cache (the `SpoilerTilePainter` uses `ColorFilter.mode` instead of pre-cached colorized sprite sheets) — `spoiler_animation.dart:19`
- [ ] spec §44.7 "Power saving": spec says `kChatSpoiler` flag pauses animations; code reads `AppState.kPowerSavingChatSpoiler` and sets `powerSavingPaused` — verified OK
- [ ] spec §44.8 "Image spoiler darken alpha": spec says `kImageSpoilerDarkenAlpha = 32`; code uses `Color.fromRGBO(0, 0, 0, (32 / 255) * opacity)` — verified OK in `spoiler_animation.dart:289`

## §45 — Custom Emoji Rendering

- [ ] spec §45.1 "Inline rendering size": spec says logical size 18px, adjusted frame 20px; code defines `EmojiSizeTag.normal: 20.0` — verified OK
- [ ] spec §45.2 "Large emoji size tiers": spec defines 1-emoji=112px, 2-emoji=78px, 3-emoji=58px; code defines size constants but rendering of large isolated custom emoji in messages needs verification in message_bubble.dart — `custom_emoji_cache.dart:20-25`
- [ ] spec §45.7 "Loading states": spec describes 3-phase loading (Loading with SVG preview at 12.5% opacity, Caching, Cached); code provides `getThumb`/`getPath`/`getFile` for multi-level loading but the 12.5% opacity SVG preview rendering depends on callers — `custom_emoji_cache.dart:96-103`
- [ ] spec §45.8 "Two-level cache": code implements in-memory instance cache with refcounting (`acquire`/`release`) and disk sprite atlas cache; batched API requests up to 100 IDs — verified OK in `custom_emoji_cache.dart`
- [ ] spec §45.8 "Eviction": spec says when all references drop to zero, file data evicted from memory (disk retained); code implements `_evictFromMemory` that removes from `_files` map — verified OK
- [ ] spec §45.9 "Click behavior": spec says clicking custom emoji opens `ShowReactionPreview` overlay with "View Pack" affordance; this overlay is not implemented in the codebase — no `reaction_preview` or `sticker_preview` overlay exists
- [ ] spec §45.14 "Reaction/emoji preview overlay": spec describes a full-viewport overlay with `MediaPreviewWidget`, clickable "View Pack" rounded-shadow rectangle, and 120ms fade; this entire overlay system is not implemented — missing feature

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
