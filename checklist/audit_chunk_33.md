# ayu_chats_page — Settings UI audit (8 issues found)

## CRITICAL Issues

- [x] [CRITICAL] Context menu options mapping reversed: {0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'} should be {0: 'Hidden', 1: 'Shown', 2: 'Extended Menu'} to match AyuGram's ContextMenuVisibility enum (Hidden=0, Visible=1, VisibleWithModifier=2) — `ayu_chats_page.dart:143` ← `AyuGram/Telegram/SourceFiles/ayu/ayu_settings.h:35-69`

- [x] [CRITICAL] Wide multiplier slider minimum is 0.5 but should be 1.0 (AyuGram kMinSize=1.00) — `ayu_chats_page.dart:322` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:241-242`

- [x] [CRITICAL] Missing edit dialogs for deleted/edited mark customization (no EditMarkBox functionality) — `ayu_chats_page.dart:495-718` (preview only, no edit buttons) ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:163-197`

- [x] [CRITICAL] Missing semi-transparent deleted messages toggle with beta badge — `ayu_chats_page.dart:(missing)` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:221-230`

## MAJOR Issues

- [x] [MAJOR] Bubble radius and wide multiplier slider order reversed: Dart shows wide multiplier first, then bubble radius; should be bubble radius first — `ayu_chats_page.dart:102-117` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:249-289`

- [x] [MAJOR] "Hide side Share button" toggle in wrong section (Channels) — should be in Messages section after simple quotes — `ayu_chats_page.dart:91-96` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:206-212` (part of BuildMarks, not BuildGroupsAndChannels)

- [x] [MAJOR] Message field element toggles missing icon support (AyuGram passes .icon parameter to each toggle) — `ayu_chats_page.dart:152-193` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:381-429`

- [x] [MAJOR] Context menu element toggles missing icon support and incorrect options order — `ayu_chats_page.dart:139-146` ← `AyuGram/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:307-360`
