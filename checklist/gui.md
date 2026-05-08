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

## §47 — Restricted Permissions UI




# Audit: §50-§57 AyuGram Features & Appendices

## §51 — Ghost Mode


## §53 — Forward Enhancements

## §54 — AyuGram UI Customization


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

- [ ] Ghost mode lock mechanism uses Shift+click on desktop and long-press on mobile (matching spec §51.2.1). Verified correct in `_LockableToggleRow`
- [ ] The collapsible toggle in `ayu_section_builder.dart` does not implement a master toggle that sets all sub-checkboxes — it only shows/hides nested checkboxes. Spec §51.2.1 says the master toggle calls `setGhostModeEnabled(bool)` which flips all five core toggles
- [ ] No `-ghost` command-line flag support for launch-time ghost mode activation
- [ ] Statistics page infrastructure (`StatsChartWidget`, all 5 chart types, tooltip, footer, pie zoom, server zoom, filter buttons, FPS-adaptive animation) is fully built but never wired to any navigation entry point
