# chat_export — Export Panel (Settings, Progress, Completion, Top Bar)

- [ ] [CRITICAL] `_bringPanelToFront()` recreates the entire overlay (close + show) which disposes the active `_ExportPanelDialog`, cancels all engine subscriptions via `dispose()`, and calls `stopExportBar()` — tapping the export top bar during an active export kills the live panel and shows a fresh settings screen — `chat_export.dart:872` ← `AyuGramDesktop/export/view/export_view_panel_controller.cpp:163` (`activatePanel()` only calls `showAndActivate()` on the existing panel)

- [ ] [CRITICAL] Date range filter values (`_fromDate`, `_tillDate`, `_fromTimeSeconds`, `_tillTimeSeconds`) are never included in the `engine.startExport()` call — per-chat date filtering UI is fully built but the values are silently dropped and the engine always exports without a date range — `chat_export.dart:767` ← `AyuGramDesktop/export/view/export_view_panel_controller.cpp:206` (passes full `*_settings` including `singlePeerFrom`/`singlePeerTill`)

- [ ] [CRITICAL] After `takeout_invalid` and `takeout_delay` errors, `_cleanupExportSubscriptions()` is called but `_phase` stays at `ExportPhase.processing` — the user is left staring at a dead progress screen with a live "Stop" button and no running export — `chat_export.dart:950` ← `AyuGramDesktop/export/view/export_view_panel_controller.cpp:281` (AyuGram hides the entire panel after the info box is dismissed via `_panel->hideGetDuration()`)

- [ ] [MAJOR] Export top bar progress bar is 3 px thick but AyuGram uses `st::mediaPlayerPlayback.fullWidth = 8px` — `chat_export.dart:107` ← `AyuGramDesktop/media/player/media_player.style:289` + `AyuGramDesktop/export/view/export_view_top_bar.cpp:103`

- [ ] [MAJOR] Progress view row padding uses `EdgeInsets.fromLTRB(22, 5, 22, 5)` (5 px top/bottom) but AyuGram specifies `exportProgressRowPadding: margins(22px, 10px, 22px, 10px)` — `chat_export.dart:2083` ← `AyuGramDesktop/export/view/export.style:51`

- [ ] [MAJOR] No inter-row spacer between progress rows — AyuGram inserts a `FixedHeightWidget` of `exportProgressRowSkip: 10px` between every row — `chat_export.dart:2078` (bare `for` loop, no gaps) ← `AyuGramDesktop/export/view/export_view_progress.cpp:322` + `AyuGramDesktop/export/view/export.style:52`

- [ ] [MAJOR] Per-chat settings (`_buildPerChatSettings`) includes a "Media" section header at line 1714, but AyuGram skips the header entirely for single-peer mode (`_singlePeerId != 0`) calling `addMediaOptions` directly without `addHeader` — `chat_export.dart:1714` ← `AyuGramDesktop/export/view/export_view_settings.cpp:220`

- [ ] [MAJOR] Completed view (`_buildCompletedPlaceholder`) replaces the entire panel content with three synthetic rows ("Data exported successfully.", "Total files:", "Total size:") each with a fully-filled progress bar below them — AyuGram reuses the existing progress rows as-is, only changes the about-label text and swaps the Stop button for Show-My-Data — `chat_export.dart:2235` ← `AyuGramDesktop/export/view/export_view_progress.cpp:355`
