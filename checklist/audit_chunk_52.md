# confirm_box — Box/Dialog Infrastructure Audit

- [ ] [CRITICAL] Box corner radius is 8px but AyuGram uses 6px — `confirm_box.dart:17` ← `AyuGram/lib_ui/ui/layers/layers.style:38`

- [ ] [CRITICAL] "Enable auto-delete" link in delete box dismisses dialog without opening TTL settings; should call `validator.showBox()` — `confirm_box.dart:625-628` ← `AyuGram/boxes/delete_messages_box.cpp:300-315`

- [ ] [CRITICAL] Enter key triggers `_confirm` for clearHistory and leaveChat modes; AyuGram explicitly blocks Enter when `_wipeHistoryPeer` is set ("Don't make the clearing history so easy") — `confirm_box.dart:575` ← `AyuGram/boxes/delete_messages_box.cpp:516-524`

- [ ] [MAJOR] Button row container padding is `(12,4,12,12)` but AyuGram `defaultBox` uses `buttonPadding: margins(6,10,10,10)` — `confirm_box.dart:252` ← `AyuGram/lib_ui/ui/layers/layers.style:125`

- [ ] [MAJOR] "Remember this choice" checkbox has 28px extra left indent (total 52px from edge) vs AyuGram's flush 24px — `confirm_box.dart:615` ← `AyuGram/boxes/delete_messages_box.cpp:506-507`

- [ ] [MAJOR] Single-choice radio rows use 6px top+bottom padding (12px total) vs AyuGram's `boxOptionListSkip: 20px` bottom margin per item — `confirm_box.dart:818` ← `AyuGram/lib_ui/ui/layers/layers.style:115`

- [ ] [MAJOR] Report reason list uses generic Material `Icons.*` instead of AyuGram's `SettingsButton` with custom styled per-reason icons (`st.spam`, `st.fake`, `st.violence`, etc.) — `confirm_box.dart:1301-1311` ← `AyuGram/ui/boxes/report_box_graphics.cpp:65-87`

- [ ] [MAJOR] Report details box is missing the Lottie animation icon header (`AddReportDetailsIconButton`) that AyuGram shows at the top of the detail entry dialog — `confirm_box.dart:1409-1456` ← `AyuGram/ui/boxes/report_box_graphics.cpp:130-131`

- [ ] [MAJOR] Report details box provides no error feedback when non-optional field is empty (silently returns); AyuGram calls `details->showError()` and `details->setFocus()` — `confirm_box.dart:1403-1405` ← `AyuGram/ui/boxes/report_box_graphics.cpp:171-176`
