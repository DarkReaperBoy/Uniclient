# ayu_appearance_page — Audit Findings

- [ ] [CRITICAL] App icon picker shows a "Restart Required" confirm dialog on every icon tap, but AyuGram applies the icon immediately via `applyIcon()` (updates window icon, tray, and notification badge in real-time) with no restart needed — `ayu_appearance_page.dart:862-873` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/components/icon_picker.cpp:42-52,177-181`

- [ ] [MAJOR] `hideNotificationBadge` toggle is guarded by `Platform.isWindows` only; AyuGram guards it with `Q_OS_WIN || Q_OS_MAC` so macOS users should also see this toggle — `ayu_appearance_page.dart:34` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_appearance.cpp:66`

- [ ] [MAJOR] Icon picker shows restart dialog even when tapping the already-selected icon; AyuGram checks `settings.appIcon() != iconName` before doing anything — `ayu_appearance_page.dart:862` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/components/icon_picker.cpp:156`

- [ ] [MAJOR] Icon picker selected-state indicator drawn as an `accentColor` border (Border.all width:2); AyuGram draws a filled `st::boxDividerBg` rounded rect behind the icon with an `easeOutCubic` animated opacity transition — `ayu_appearance_page.dart:879-883` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/components/icon_picker.cpp:67-92`

- [ ] [MAJOR] Avatar corners slider `onChangeEnd` shows a full confirm dialog requiring user action before applying the value; AyuGram applies the value immediately on every slider step and only calls `ShowRestartPrompt` (a non-blocking toast/banner) on final release — `ayu_appearance_page.dart:307-322` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_appearance.cpp:164-173`

- [ ] [MAJOR] Avatar corners preview background is hardcoded (`0xFF24292E` dark / `0xFFF1F1F1` light) instead of using the theme's `windowBg` color, causing it to diverge from the rest of the window background when the user has a custom theme — `ayu_appearance_page.dart:397` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/components/avatar_corners_preview.cpp:50`

- [ ] [MAJOR] Avatar corners preview row has no ripple animation on tap; AyuGram uses `Ui::RippleAnimation` on `mousePressEvent`/`mouseReleaseEvent` — `ayu_appearance_page.dart:432` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/components/avatar_corners_preview.cpp:80-101`

- [ ] [MAJOR] Font selector only enumerates system fonts via `fc-list` on Linux; on Windows and macOS `_loadSystemFonts` falls back to a hardcoded 10-font stub list. AyuGram uses `QFontDatabase::families()` which works cross-platform — `ayu_appearance_page.dart:596-626` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/boxes/font_selector.cpp:204-218`
