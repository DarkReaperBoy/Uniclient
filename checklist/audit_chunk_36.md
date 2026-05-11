# ayugram_settings_screen — Audit findings

- [ ] [CRITICAL] Category buttons rendered as iOS-style colored icon tiles (28×28 `BoxDecoration` with custom hex colors) instead of standard flat Telegram settings buttons with themed monochrome icons — `ayugram_settings_screen.dart:296-348` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_main.cpp:103-132` (`addSectionButton` uses `st::settingsButton` + flat icon, no colored containers; `infoProfileButton` padding puts text at 79px, Dart puts it at 60px)

- [ ] [MAJOR] Version title font size 17px; AyuGram spec is 16px semibold (`st::boxTitle`) — `ayugram_settings_screen.dart:101` ← `AyuGramDesktop/Telegram/lib_ui/ui/layers/layers.style:73` (`boxTitleFont: font(16px semibold)`)

- [ ] [MAJOR] Logo rendered without the 12px inner padding that `currentAppLogoPad()` applies — Dart fills the full 100×100 box; AyuGram renders the logo as ~76px centered in a 100px container — `ayugram_settings_screen.dart:71-92` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/ayu_logo.cpp:99` (`CreateImage(…, Size(256), 12)`)

- [ ] [MAJOR] `ClipRRect` with `circular(50)` applied to all logo assets including PNG; AyuGram only clips SVG logos via `QPainterPath::addRoundedRect`, PNG images are drawn flat with `p.drawImage()` — `ayugram_settings_screen.dart:69-81` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/ayu_logo.cpp:44-92`

- [ ] [MAJOR] Version string shows hardcoded "alpha" stage suffix by default (`String.fromEnvironment('APP_STAGE', defaultValue: 'alpha')`) producing "v0.1.0 alpha"; AyuGram shows only "AyuGram Desktop v{version}" with no stage — `ayugram_settings_screen.dart:282-291` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_main.cpp:73-74`

- [ ] [MAJOR] "Channel" link button uses `Icons.campaign` (megaphone); AyuGram uses `st::menuIconChannel` — `ayugram_settings_screen.dart:198` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_main.cpp:147`

- [ ] [MAJOR] "Documentation" link button uses `Icons.description` (document); AyuGram uses `st::menuIconIpAddress` (network/address icon) — `ayugram_settings_screen.dart:217` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_main.cpp:179`
