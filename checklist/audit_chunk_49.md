# choose_datetime_box — Calendar + Schedule + TimePicker audit

- [ ] [CRITICAL] `_onRepeatTap` shows `SnackBar("Subscribe to Telegram Premium…")` for non-premium users instead of `ShowPremiumPromoToast` with a clickable link to the premium subscription page — `choose_datetime_box.dart:942-948` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_schedule_box.cpp:129-144`

- [ ] [CRITICAL] `_DayCell` registers `widget.onTap` on **both** the outer `GestureDetector` (line 693) **and** the inner `InkWell` (line 701); in Flutter's gesture arena these compete — the InkWell ripple never plays (outer wins) or `Navigator.pop()` fires twice (double-pop crashes) — `choose_datetime_box.dart:691-701` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:820-911` (single click-through via `mouseReleaseEvent`)

- [ ] [MAJOR] Calendar day grid shows empty `SizedBox` for leading cells before the 1st of the month; AyuGram renders those cells as grayed-out days from the previous month (`grayedOut = index < 0 || index >= daysCount`, drawn in `_styleColors.dayTextGrayedOutColor`) — `choose_datetime_box.dart:408-411` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:820-911`

- [ ] [MAJOR] Calendar box "Cancel" button label is wrong; AyuGram uses `tr::lng_close()` ("Close"), not "Cancel" — `choose_datetime_box.dart:385-389` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:1433`

- [ ] [MAJOR] Month/Year picker confirm button says "OK"; AyuGram uses `tr::lng_gift_menu_show()` ("Show") — `choose_datetime_box.dart:586-593` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:180`

- [ ] [MAJOR] Navigation arrows (`_NavArrow`) have no hover tooltip; AyuGram shows "To the beginning" / "To the end" tooltips after `kTooltipDelay = 350 ms` hover and triggers a long-press jump after `kJumpDelay = 700 ms` — `choose_datetime_box.dart:598-631` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/calendar_box.cpp:35-36,1241-1265,1314-1321`
