# telegram_palette — Theme Color Accuracy Audit

## Summary

The `TelegramPalette` class defines 4 static theme constants (`dayBlue`, `night`, `classicDay`, `nightGreen`) and a `colorize()` engine. The `dayBlue` theme is the default palette served to all widgets. The ground truth for these themes is AyuGram's embedded `.tdesktop-theme` files plus `lib_ui/ui/colors.palette`.

**Root cause of most issues:** `dayBlue` was populated with values from `colors.palette` (the classic/default green theme) instead of `day-blue.tdesktop-theme`. This makes ALL outgoing message bubbles in the Day Blue theme render green instead of blue — visually identical to the Classic theme.

---

## Findings

- [ ] [CRITICAL] `dayBlue.msgOutBg` is `#EFFDDE` (classic green) instead of `#DEF1FD` (day-blue light blue) — all outgoing message bubbles render the wrong color in the app's default theme — `telegram_palette.dart:2854` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`msgOutBg: #def1fd`)

- [ ] [CRITICAL] `dayBlue.msgOutBgSelected` is `#CBEBB5` (green) instead of `#BBE1FC` (blue) — selected outbox messages show green instead of blue — `telegram_palette.dart:2855` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`msgOutBgSelected: #bbe1fc`)

- [ ] [CRITICAL] `dayBlue.msgInBgSelected` is `#C2DCF2` instead of `#BBE1FC` — selected inbox bubbles use wrong shade — `telegram_palette.dart:2853` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`msgInBgSelected: #bbe1fc`)

- [ ] [CRITICAL] `dayBlue.historyOutIconFg` is `#5DC452` (green checkmark) instead of `#059DE8` (blue) — outgoing message read/sent tick icons are green in Day Blue theme — `telegram_palette.dart:2900` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`historyOutIconFg: #059de8`)

- [ ] [CRITICAL] `dayBlue.dialogsSentIconFg` is `#5DC452` (green) instead of `#2CA6E8` (blue) — chat list sent-message ticks show green in Day Blue — `telegram_palette.dart:2842` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`dialogsSentIconFg: #2ca6e8`)

- [ ] [CRITICAL] `dayBlue.msgFileOutBg` is `#60B867` (green) instead of `#40A7E3` (blue, alias `windowBgActive`) — outbox audio/file download circles are green instead of blue — `telegram_palette.dart:2867` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`msgFileOutBg: windowBgActive`)

- [ ] [CRITICAL] `dayBlue.msgOutServiceFg` is `#529E39` (green) instead of `#168ACD` (blue, `windowActiveTextFg`) — outbox forwarded-from and service text is green — `telegram_palette.dart:2861` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`msgOutServiceFg: windowActiveTextFg`)

- [ ] [CRITICAL] `dayBlue.msgOutDateFg` is `#6FAB69` (green) instead of `#86A8C2` (blue-gray) — outbox timestamp text color wrong — `telegram_palette.dart:2859` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`msgOutDateFg: #86a8c2`)

- [ ] [CRITICAL] `dayBlue.msgOutReplyBarColor` is `#64B05C` (green) instead of `#059DE8` (blue, alias `historyOutIconFg`) — reply bar in outbox messages is green — `telegram_palette.dart:2863` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`msgOutReplyBarColor: historyOutIconFg`)

- [ ] [CRITICAL] `dayBlue.introCoverTopBg` and `introCoverBottomBg` are both `#2B2242` (dark purple, belongs to night themes) instead of `#0F89D0`/`#39B0F0` (blue gradient) — login screen intro shows dark purple instead of blue — `telegram_palette.dart:2966-2967` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`introCoverTopBg: #0f89d0; introCoverBottomBg: #39b0f0`)

- [ ] [CRITICAL] `night.introCoverTopBg` and `introCoverBottomBg` are `#2B2242` instead of `#124A82`/`#23659F` — night theme also shows wrong login gradient — `telegram_palette.dart:3543-3544` ← `AyuGram/Telegram/Resources/night.tdesktop-theme:colors.tdesktop-theme` (`introCoverTopBg: #124a82; introCoverBottomBg: #23659f`)

- [ ] [CRITICAL] `night.introCoverIconsFg` is `#5EC6FF` (day-blue value) instead of `#3B7CBD` — intro cloud graphics wrong color in night theme — `telegram_palette.dart:3545` ← `AyuGram/Telegram/Resources/night.tdesktop-theme:colors.tdesktop-theme` (`introCoverIconsFg: #3b7cbd`)

- [ ] [CRITICAL] `settingsIconBg1`–`settingsIconBg6` are wrong in all 3 themes — colors are reshuffled and use different hues entirely vs. AyuGram's base palette (`#F06964` red, `#6DC534` green, `#ED9F20` orange, `#56B3F5` blue, `#7595FF` purple, `#B580E2` purple); Dart has green/pink/blue/orange/purple/sea for bg1–6 respectively — `telegram_palette.dart:3019-3024` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:326-331`

- [ ] [CRITICAL] `settingsIconBgArchive` is `#FFC535` (bright yellow) in all themes instead of `#9DA2B0` (gray) — archive icon background is wrong color — `telegram_palette.dart:3026` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:333` (`settingsIconBgArchive: #9da2b0`)

- [ ] [MAJOR] `dayBlue.msgOutMonoFg` is `#459866` (green) instead of `#4E7391` (same as inbox) — outbox monospace/code text wrong color — `telegram_palette.dart:2865` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`msgOutMonoFg: #4e7391`)

- [ ] [MAJOR] `dayBlue.historyScrollBarBg` / `historyScrollBarBgOver` / `historyScrollBg` / `historyScrollBgOver` use green-tinted values (`#7A517C41`, `#BC517C41`, `#4C517C41`, `#6B517C41`) instead of transparent-black values (`#00000040`, `#00000053`, `#00000000`, `#0000001A`) — scrollbar in chat area shows green tint in Day Blue — `telegram_palette.dart:2893-2896` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`historyScrollBarBg: #00000040; historyScrollBg: #00000000`)

- [ ] [MAJOR] `dayBlue.msgServiceBg` is `#90527C41` (green-tinted) instead of `#00518059` (blue-tinted) — service message bubbles (date dividers, join messages) wrong color in Day Blue — `telegram_palette.dart:2868` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`msgServiceBg: #00518059`)

- [ ] [MAJOR] `dayBlue.msgOutShadow` is `Color(0x1D3AC346)` (green-based, from default palette) instead of `Color(0x1A0D5A91)` (blue-based) — outbox bubble shadow has wrong color cast — `telegram_palette.dart:2857` ← `AyuGram/Telegram/Resources/day-blue.tdesktop-theme:colors.tdesktop-theme` (`msgOutShadow: #0d5a911a`)

- [ ] [MAJOR] `dayBlue.lightButtonFgOver` is `#12659A` instead of `#168ACD` (should equal `lightButtonFg` per palette alias `lightButtonFgOver: lightButtonFg`) — hover text on light buttons (e.g. Cancel) is slightly wrong — `telegram_palette.dart:2814` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:46` (`lightButtonFgOver: lightButtonFg`)

- [ ] [MAJOR] `dayBlue.tooltipFg` is `#9A9FA3` (medium gray) instead of `#5D6C80` (blue-gray, darker) — tooltip text color significantly off — `telegram_palette.dart:3049` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:95` (`tooltipFg: #5d6c80`)

- [ ] [MAJOR] `night.msgOutBg` is `#265E8C` instead of `#2B5278` — outbox bubble background wrong shade in night theme — `telegram_palette.dart:3431` ← `AyuGram/Telegram/Resources/night.tdesktop-theme:colors.tdesktop-theme` (`msgOutBg: #2b5278`)

- [ ] [MAJOR] `_enforceContrast()` does a generic WCAG 4.5:1 ratio pass adjusting lightness ±0.3 for ALL colors, but AyuGram's `keepContrast` only enforces contrast for specific fg/bg pairs (`activeButtonFg` vs `activeButtonBg`, `profileVerifiedCheckFg` vs `profileVerifiedCheckBg`, `overviewCheckFgActive` vs `overviewCheckBgActive`, and file icon colors) — this over-adjusts colors that AyuGram intentionally leaves as-is — `telegram_palette.dart:2308-2323` ← `AyuGram/Telegram/SourceFiles/window/themes/window_themes_embedded.cpp:140-167`
