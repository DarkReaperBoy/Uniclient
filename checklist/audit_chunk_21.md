# telegram_palette — Color palette and colorizer logic

## CRITICAL

- [x] [CRITICAL] `colorize()` saturation shift uses a simple ratio `nSat/oSat` instead of the C++ piecewise interpolation formula — the C++ handles the case where `color.saturation > was.saturation` AND `now.saturation > was.saturation` with a different formula than simple scaling, producing incorrect saturation values for all non-trivially-saturated colors — `telegram_palette.dart:1276` ← `lib_ui/ui/style/style_palette_colorizer.cpp:33-43`

- [x] [CRITICAL] `colorize()` never applies an HSV value (brightness) shift — the C++ colorizer shifts `value` proportionally to the accent change (interpolates up when `color.value > was.value`, scales down when less), meaning colorized colors in Dart will have wrong brightness after accent change — `telegram_palette.dart:1277` ← `lib_ui/ui/style/style_palette_colorizer.cpp:44-57`

- [x] [CRITICAL] `colorize()` clamps HSL lightness on every colorized color — the C++ applies `lightnessMin`/`lightnessMax` only to the new accent color before storing it as the target (in `ColorizerFrom`), not to every individual color; the Dart clamping over-constrains intermediate colors that never exceed bounds in reality — `telegram_palette.dart:1279-1281` ← `SourceFiles/window/themes/window_themes_embedded.cpp:169-182`

## MAJOR

- [x] [MAJOR] `dialogsMentionIconFg` is passed through unchanged in `colorize()` (line 1625), but it is NOT in AyuGram's `kColorizeIgnoredKeys`; since `dialogsMentionIconFg` = `#40a7e3` (hue ~204°, same as the blue accent), it WILL be shifted by the C++ colorizer when the user changes the accent color; mention badges in the chat list will stay blue regardless of accent in Dart — `telegram_palette.dart:1625` ← `SourceFiles/window/themes/window_themes_embedded.cpp:33-102`

- [x] [MAJOR] `_enforceContrast()` does not enforce the `overviewCheckFgActive` / `overviewCheckBgActive` pair — VERIFIED: already implemented at `telegram_palette.dart:2677` — closed as false positive

- [x] [MAJOR] `_enforceContrast()` is missing all 8 `historyFile*` contrast pairs for dark themes — VERIFIED: already implemented at `telegram_palette.dart:2636-2643` — closed as false positive

- [x] [MAJOR] `kColorizeIgnoredKeys` is dead code — removed entirely; exclusions are enforced by not calling `s()` on the relevant fields in `colorize()`

- [x] [MAJOR] `kColorizeIgnoredKeys` contains wrong field names — removed along with the dead set

- [x] [MAJOR] `dayBlue` theme `msgFile2BgSelected` is `Color(0xFF46A07E)` but the canonical palette value is `#50ac9b` = `Color(0xFF50AC9B)` (12% deviation in R, 7% in G, 19% in B); file type colors are colorize-excluded so they should exactly match the palette constant — `telegram_palette.dart:2940` ← `lib_ui/ui/colors.palette:397`

- [x] [MAJOR] `dayBlue` theme `historyScrollBg` is `Color(0x00000000)` — fully transparent, meaning the scroll-track area has zero visual presence even on hover; the canonical palette value `#517c414c` provides a 30%-opacity tinted scroll track; a zero-alpha value produces no feedback when the user interacts with the scrollbar — `telegram_palette.dart:2893` ← `lib_ui/ui/colors.palette:341`
