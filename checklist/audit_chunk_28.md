# active_sessions_screen — Audit findings

- [ ] [CRITICAL] Device icons use Material Design icons (`Icons.desktop_windows`, `Icons.phone_android`, etc.) instead of Telegram's dedicated platform SVG icons (`st::sessionIconWindows`, `st::sessionIconAndroid`, etc.) — `active_sessions_screen.dart:64-122` ← `AyuGram/settings/settings.style:370-382`

- [ ] [CRITICAL] Session info box uses a Flutter scale+fade animation (`Curves.elasticOut`) instead of a Lottie animated device icon. AyuGram calls `LottieForType()` to get a Lottie animation that plays when the box is shown; only `Web` and `Other` types fall back to a static icon — `active_sessions_screen.dart:1076-1143` ← `AyuGram/settings/sections/settings_active_sessions.cpp:297-409`

- [ ] [CRITICAL] Auto-terminate row opens a custom Flutter `Dialog` with hand-rolled radio buttons instead of `SelfDestructionBox`. AyuGram calls `Box<SelfDestructionBox>(&session, SelfDestructionBox::Type::Sessions, _ttlDays.value())` which uses the proper `api().authorizations().updateTTL(value)` call — `active_sessions_screen.dart:236-347` ← `AyuGram/settings/sections/settings_active_sessions.cpp:1000-1009`

- [ ] [CRITICAL] "Terminate All Other Sessions" button has no description text below it. AyuGram adds `AddDividerText(terminateInner, tr::lng_sessions_terminate_all_about())` immediately after the button — `active_sessions_screen.dart:789-816` ← `AyuGram/settings/sections/settings_active_sessions.cpp:967-968`

- [ ] [CRITICAL] Session info box is missing the divider + "Session info" subsection title above the info rows. AyuGram calls `Ui::AddDivider(container)`, `Ui::AddSkip(container, st::sessionSubtitleSkip)`, then `Ui::AddSubsectionTitle(container, tr::lng_sessions_info())` before rendering `AddSessionInfoRow` entries — `active_sessions_screen.dart:526-570` ← `AyuGram/settings/sections/settings_active_sessions.cpp:448-452`

- [ ] [CRITICAL] Session info box is missing the location-about divider text. AyuGram appends `AddDividerText(container, tr::lng_sessions_location_about())` when `data.location` is non-empty — `active_sessions_screen.dart:570` ← `AyuGram/settings/sections/settings_active_sessions.cpp:479-483`

- [ ] [CRITICAL] Device rename stores the custom name in a local JSON file (`device_prefs.json`) instead of Telegram cloud settings. AyuGram calls `Core::App().settings().setCustomDeviceModel(result)` + `Core::App().saveSettingsDelayed()` so the name is synced with Telegram's settings storage — `active_sessions_screen.dart:438-447` ← `AyuGram/settings/sections/settings_active_sessions.cpp:148-158`

- [ ] [MAJOR] Auto-terminate section is missing the "Terminate old sessions" subsection title (`tr::lng_settings_terminate_title` = "Terminate old sessions") that AyuGram places above the "If inactive for..." button — `active_sessions_screen.dart:911-944` ← `AyuGram/settings/sections/settings_active_sessions.cpp:997-998`

- [ ] [MAJOR] Auto-terminate dialog title says "If Inactive For" but the correct title (`tr::lng_self_destruct_sessions_title`) is "Session termination" — `active_sessions_screen.dart:264` ← `AyuGram/boxes/self_destruction_box.cpp:198` + `AyuGram/Resources/langs/lang.strings:1579`

- [ ] [MAJOR] Auto-terminate dialog description text is paraphrased. Canonical text (`tr::lng_self_destruct_sessions_description`) is "If you don't come online from a specific session at least once within this period, it will be terminated." — `active_sessions_screen.dart:275` ← `AyuGram/boxes/self_destruction_box.cpp:149` + `AyuGram/Resources/langs/lang.strings:1580`

- [ ] [MAJOR] Row location+date separator uses middle-dot `·` (U+00B7) but AyuGram uses bullet `•` (U+2022, `Ui::kQBullet`) — `active_sessions_screen.dart:1005` ← `AyuGram/settings/sections/settings_active_sessions.cpp:161-163` + `AyuGram/lib_ui/ui/text/text.cpp:27`

- [ ] [MAJOR] `_otherSessions` and `_incompleteSessions` are computed getters that do `where` + `sort` on every access. They are called inside `build()` which can be triggered on every frame — `active_sessions_screen.dart:175-193` ← (performance; AyuGram sorts once in `parse()` at `settings_active_sessions.cpp:787-788`)

- [ ] [MAJOR] Other-sessions and incomplete-sessions lists are built as a flat `Column` with a `for` loop, rendering all rows at once. With many sessions this is unbounded. AyuGram uses a `PeerListContent` (lazy virtual list) — `active_sessions_screen.dart:886-898` ← `AyuGram/settings/sections/settings_active_sessions.cpp:1155-1174`
