# ayu_other_page — Audit Findings

- [ ] [CRITICAL] "Contact support" link opens a hardcoded static dialog instead of the real FillDonateInfoBox — AyuGram's support dialog fetches live data from `RCManager`: `donateAmountUsd()`, `donateAmountTon()`, `donateAmountRub()`, and `donateUsername()`, then renders donation amounts with a TON symbol and a clickable Telegram link to the support account; the Dart dialog shows none of this — `ayu_other_page.dart:389-461` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/boxes/donate_info_box.cpp:130-248`

- [ ] [CRITICAL] Support username is hardcoded as `"@AyuGramSupport"` instead of coming from `RCManager.donateUsername()` — `ayu_other_page.dart:436` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/utils/rc_manager.h:64-65`

- [ ] [CRITICAL] "Contact support" link is a separate widget placed after the description — AyuGram embeds it as a hyperlink inside a single `AddDividerText` call using `tg://support` URL which triggers `HandleSupport` → opens `FillDonateInfoBox`; there is no standalone "Contact support" widget in AyuGram — `ayu_other_page.dart:82-85` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_other.cpp:161-167`

- [ ] [MAJOR] Support logo size is 72×72 in Dart vs `supportLogoSize: 96px` in AyuGram style (25% smaller) — `ayu_other_page.dart:408-409` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/boxes/donate_info_box.cpp:145` (style value: `ayu_styles.style:supportLogoSize`)

- [ ] [MAJOR] Donate button icons render as plain SVGs without any background — AyuGram's `getImage()` renders each icon on a rounded rectangle background (`QColor(0xEEEEEE)` dark mode / `QColor(0x242B2C)` light mode), which is entirely absent in the Dart `_DonateButton` — `ayu_other_page.dart:286-320` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_other.cpp:49-84`

- [ ] [MAJOR] `_ActionButton` adds a custom colored icon background (Telegram blue at 15% opacity) that does not exist in AyuGram — the C++ action buttons use `st::menuIconLink` / `st::menuIconRestore` as standard icons without any container or tinted background — `ayu_other_page.dart:338-366` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_other.cpp:196-225`
