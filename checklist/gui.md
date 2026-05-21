# GUI Audit — Cycle 1 Phase Cleanup (2026-05-21 16:44)

## Cleanup Sweep (placeholders, stubs, perf)

# bridge — code quality audit

## CRITICAL Issues


## OK / No issues found

- Bridge wrapper facade (`bridge.dart`) — clean delegation pattern
- FFI implementation (`bridge_ffi.dart`) — proper memory management, isolate handling, event callback setup
- Stub implementation (`bridge_stub.dart`) — intentional and correct
- Event subscription lifecycle (`engine_service.dart:5612`) — properly cancelled in dispose
- Memory cleanup (`bridge_ffi.dart:133-150`) — allocations freed in finally blocks
- Error handling pattern — consistent StateError throws for uninitialized state (FFI)

# spell_service — issues found


## Details

**Line 88 (Stub suggestions):**
- `fetchSpellCheckSuggestions()` marks misspelled words but returns `const []` (empty suggestions list)
- Method name promises suggestions, implementation delivers nothing
- UI will show "word is misspelled" without any way to fix it

**Lines 44 & 186 (Windows paths):**
- `dictsDir` correctly handles platform-specific paths (lines 14–26)
- But string operations at lines 44 and 186 hardcode Unix separator
- On Windows: `C:\Users\Nako\AppData\Roaming\uniclient\dicts\en_US.dic`
- `split('/')` won't split (no forward slashes in string)
- `.last` returns entire path; `replaceAll('.dic', '')` leaves `C:\Users\...\en_US`
- Should use `basename()` or `File(path).uri.pathSegments.last` instead


# notification_types — clean

No issues found.


# bridge_ffi — audit findings

## Issues Found

### [CRITICAL] Event controller not recreated after dispose — reinitialization impossible
**Location:** `bridge_ffi.dart:166`

The `_globalEventController` is a module-level global created once:
```dart
final _globalEventController = StreamController<Uint8List>.broadcast();
```

When `dispose()` closes it (line 89), the stream is permanently closed. Attempting to reinitialize the bridge will fail silently:
- `init()` succeeds and sets `_initialized = true`
- But `events` property returns a closed stream that will never emit
- Any code expecting events after reinit will hang

**Scenario:** 
1. App calls `bridge.init()` → stream active
2. Error recovery or test calls `bridge.dispose()` → stream closed
3. App tries to reinit (common in error handling) → `_initialized` resets but controller is dead forever
4. Next events never arrive, silently breaking auth/message flow

**Fix:** Move controller creation into `init()` method (make it instance-level or recreate if closed):
```dart
void init({String? libraryPath}) {
  if (_initialized) return;
  
  // Recreate controller if needed (allows reinit)
  if (_globalEventController.isClosed) {
    // Would need to refactor to instance-level or use fresh controller
  }
  
  _resolvedLibPath = libraryPath ?? _findLibraryPath();
  ...
}
```

**Better fix:** Make `_globalEventController` and `_eventCallable` instance fields instead of globals — this would also allow multiple independent Bridge instances if needed.

### [MINOR] Unsafe library path construction on macOS
**Location:** `bridge_ffi.dart:106`

```dart
final frameworkPath = '$exeDir/../Frameworks/libcores.dylib';
```

The `..` relative path is not normalized. On some systems this might fail or follow unexpected symlinks. Should use `normalize()` or proper path resolution:
```dart
final parentDir = File(Platform.resolvedExecutable).parent.parent.path;
final frameworkPath = '$parentDir/Frameworks/libcores.dylib';
```

---

## Clean Patterns (Not Issues)

- ✅ Memory management correct — proper calloc/free with try/finally
- ✅ Pointer casting safe — null checks before use
- ✅ Event callback handles async marshalling correctly — NativeCallable.listener prevents isolate crashes
- ✅ Thread safety proper — callback unset before stream close
- ✅ Initialization guarded — both sync/async check `_initialized`


# theme_preview — clean

No critical, major, or maintenance issues found. The widget correctly displays a theme preview with example data (intentional for preview purposes). Image loading has proper error handling and fallback. All UI elements are fully functional and properly wired to the palette.

# wallpaper — audit findings

## Critical Issues

- [ ] [CRITICAL] `_TiledPainter` async decode won't trigger repaint — `wallpaper.dart:423-452`
  - Lines 434-435: `ui.decodeImageFromList()` callback sets `_decoded` asynchronously
  - But CustomPainter doesn't notify Flutter when async state changes
  - `shouldRepaint()` (line 451) only compares `imageBytes` — won't detect `_decoded` changes
  - Result: tiled image decodes but never paints to canvas
  - Fix: Convert `_TiledImage` to StatefulWidget, call `setState()` in decode callback, or use `Image.memory()` directly
  - Pattern: See `_PatternWallpaperState` (line 498-501) — it correctly does `setState(() => _patternImage = image)`

## Minor Issues

- [ ] [MINOR] `_TiledPainter._loading` flag never resets (line 426)
  - Flag is set to true but never reset to false after decode
  - If painter is reused and decode fails, flag stays true and won't retry
  - Not critical since decode only initiates once, but semantically wrong
  - Consider removing the flag or resetting it after decode completes

## Green Flags

✓ `WallpaperProvider` properly inherits and exposes via `of(context)`
✓ `ChatWallpaper` correctly switch/cases all wallpaper types
✓ `_MultiColorGradient` + `_PatternWallpaper` properly use AnimationController + setState for power saving
✓ `_MultiGradientPainter.shouldRepaint()` correctly checks all fields (line 403-406)
✓ `_PatternWallpaperPainter.shouldRepaint()` correctly checks all fields (line 674-680)
✓ All const constructors on data classes and widgets
✓ Image encoding/decoding check for null gracefully (lines 718, 741, 759)
✓ Color fallback (0xFF527C41) reasonable for small/invalid images
✓ Animation state properly pauses on power saving (lines 329-334, 512-517)
✓ All engine/state wiring verified (AppState.powerSaving, kPowerSavingChatBackground)

## Summary

One blocking bug: `_TiledImage` won't render because async decode doesn't trigger repaint. Needs immediate fix.

## active_sessions_screen — cleanup

- [ ] [MAJOR] `_formatDaysLabel(365)` returns "12 months" instead of "1 year" — the math `(365/30).round()` = 12, but Telegram Desktop displays "1 year" for the 365-day option — `active_sessions_screen.dart:284`

- [ ] [MAJOR] `_buildAutoTerminateSection` is gated on `otherSessions.isNotEmpty` (line 858) — users with no other active sessions cannot access the auto-terminate setting at all; Telegram Desktop always shows the "Terminate old sessions" section regardless of other-session count — `active_sessions_screen.dart:858`

- [ ] [MAJOR] When `_autoTerminateDays == 0` (never configured), `_formatDaysLabel` returns `''` and the "If Inactive For" row renders with no value on the right side (line 1078 guard `if (label.isNotEmpty)`) — should show "Never" — `active_sessions_screen.dart:1049`

- [ ] [MAJOR] No user feedback when `terminateSession` or `terminateAllOtherSessions` returns `false` — the `if (ok && mounted) _loadSessions()` branches silently drop failures with no snackbar or retry; from the user's perspective the session appears to still be active — `active_sessions_screen.dart:257,265`

- [ ] [MAJOR] Route animation status listener in `_DeviceUserpicBigState._onLottieLoaded` (line 1298) only removes itself on `AnimationStatus.completed`; if the dialog is popped before the open animation finishes, the listener is never removed from the route's animation — leaves a dead closure holding a reference to `_lottieController` and `route` for the duration of the dismiss animation — `active_sessions_screen.dart:1292`

- [ ] [MAJOR] `_classifyDevice()` called inside `_SessionRow.build()` (line 1140) on every frame — involves three `toLowerCase()` allocations and up to a dozen `contains()` checks per session row; result is never cached — should be computed once in `_recomputeCachedLists()` and stored alongside the session map — `active_sessions_screen.dart:1140`

- [ ] [MAJOR] `Image.asset` in `_DeviceUserpic.build()` (line 1245) renders at `size * 0.52` (≈22 px for the default 42 px icon) but supplies no `cacheWidth`/`cacheHeight` — Flutter decodes and caches the PNG at its full on-disk resolution; every distinct `size` creates a separate cache entry — add `cacheWidth` / `cacheHeight` matching the rendered size — `active_sessions_screen.dart:1245`

- [ ] [MAJOR] Same `Image.asset` issue in `_DeviceUserpicBigState.build()` fallback path (line 1337) — icon rendered at `70 * 0.52 ≈ 36 px` with no `cacheWidth`/`cacheHeight` — `active_sessions_screen.dart:1337`

- [ ] [MAJOR] `context.watch<AppState>()` called inside `_buildCurrentSession()` at line 896, which is a plain method call from `build()` — registers the entire screen's BuildContext as a listener to AppState, so any property change on AppState (messages, chat state, etc.) triggers a full `ActiveSessionsScreen` rebuild; scope this to `customDeviceModel` only via `context.select((s) => s.customDeviceModel)` — `active_sessions_screen.dart:896`

- [ ] [MAJOR] `_loadSessions()` is called concurrently from both the 60-second timer and the `onConnState` listener without deduplication — if a `connected` event fires while a fetch is still in flight, two parallel `getSessions` calls are issued; add an in-flight guard (`_loading` is already present but only checked to show the spinner, not to debounce parallel calls) — `active_sessions_screen.dart:197,199`

# admin_tools — cleanup

- [ ] [CRITICAL] `TextEditingController` created inline inside `build()` in `_buildChargeStarsSection` — line 2504: `TextEditingController(text: '$_chargeStars')` is instantiated fresh on every rebuild with no dispose path. Any `setState` above it (e.g. toggling the switch, moving the slowmode slider) immediately replaces the controller and resets whatever the user typed to the old value. Store a controller in the state and update its text only when `_chargeStars` changes programmatically. — `admin_tools.dart:2504`

- [ ] [CRITICAL] `_showRevenueStats` has no try/catch around `engine.getStarsRevenueStats` (line 1292). If the engine call throws, the async method propagates the exception and the caller's `onTap` receives an unhandled error — no feedback to user, potential crash in error overlay. Wrap in try/catch with a toast. — `admin_tools.dart:1292`

- [ ] [CRITICAL] `_actionDescription` always uses "group" wording for `change_title`, `change_about`, `change_username`, `change_photo` (lines 4550–4556) even when `isChannel == true`. A channel admin log event would say "changed the group title" for a channel. Use `isChannel ? "channel" : "group"` for these four cases. — `admin_tools.dart:4549`

- [ ] [CRITICAL] Double network call on open for megagroups: `initState` fires both `_loadAntiSpamState` (line 94) and `_loadChatFullInfo` (line 95), both of which call `engine.getChatPermissionFlags` with identical arguments (same `accountId`, `chatId`). Move the `antispam` flag read into `_loadChatFullInfo` (which already reads all other flags from the same response) and delete `_loadAntiSpamState`. — `admin_tools.dart:94`

- [ ] [CRITICAL] `_showVerifyAccountsDialog`: after `engine.callGeneric('BotsSetCustomVerification', ...)` succeeds (line 1479), the `isVerified` icon for that contact is never updated — the contact objects are immutable and `setDialogState` is not called with a refreshed list. The user sees stale verification badges after toggling. Either reload contacts or maintain a local `Set<String>` of toggled IDs to flip the icon. — `admin_tools.dart:1479`

- [ ] [MAJOR] Linked chat row always shows hardcoded `value: 'Add'` (line 515) regardless of `_linkedChatId`. After `_loadChatFullInfo` runs, `_linkedChatId` is set but the row still reads "Add". Should show `_linkedChatId.isNotEmpty ? 'Linked' : 'Add'` (or the resolved chat title). — `admin_tools.dart:515`

- [ ] [MAJOR] `_updateDateBadge` is called on every scroll-position change via `_onScroll` (line 4053) and calls `setState(...)` unconditionally (line 4087), rebuilding the entire `_AdminLogScreenState` tree on each scroll frame. It also runs an O(n) linear scan through `_events` on every frame (lines 4068–4081). Replace with a `ValueNotifier<String>` + `ValueListenableBuilder` for the badge, and only call `setState` when the date label actually changes. — `admin_tools.dart:4053`

- [ ] [MAJOR] `_chargeStars` is mutated without `setState` in the TextField `onChanged` at line 2519 (`_chargeStars = parsed`). The description text below (`'Non-admin members must pay $_chargeStars stars...'`) never updates while the user types. Call `setState(() => _chargeStars = parsed)`. — `admin_tools.dart:2519`

- [ ] [MAJOR] `_itemKeys` (line 3989) grows unboundedly during pagination: entries are added for every loaded event index and never pruned for off-screen events when `append: true`. With large logs (hundreds of events across many pages) this accumulates thousands of live `GlobalKey` objects. Clear stale keys when events scroll well off-screen, or limit tracked keys to a sliding window around the visible range. — `admin_tools.dart:3989`

## advanced_settings_screen — cleanup

- [ ] [CRITICAL] Double-toggle bug in `_ManageDictionariesBox`: `InkWell.onTap` (line 2348) and `Checkbox.onChanged` (line 2362) both call `appState.toggleDictionary(d.code)` — Flutter fires both handlers on a single tap, so the dict toggles on then immediately back off. Net effect: clicking a dictionary row never changes its state. Fix: remove the `onChanged` from the `Checkbox` and keep only the `InkWell.onTap`, or wrap the `Checkbox` in `AbsorbPointer` — `advanced_settings_screen.dart:2347`

- [ ] [CRITICAL] `_getDictionaryCountLabel()` always returns `'System'` (lines 1159–1173): On Linux/macOS `isSystem=true` so the Manage Dictionaries row is hidden anyway; on Windows `isSystem=false` and the row is shown, but the function falls through to `return 'System'` without counting custom dictionaries from `UniSpellCheckService`. The label next to "Manage Dictionaries" is permanently "System" on every platform. Should query `UniSpellCheckService` for installed/enabled dict count — `advanced_settings_screen.dart:1159`

- [ ] [CRITICAL] `_downloadAndApplyUpdate` calls `File(tmpPath).rename(exePath)` (line 295) on Linux — this fails with ETXTBSY because you cannot rename over a running executable on Linux. The auto-update write step is broken on Linux. Fix: write to a sibling path, then use a small shell wrapper (`mv "$tmp" "$exe" && exec "$exe"`) launched as a detached process before `exit(0)` — `advanced_settings_screen.dart:295`

- [ ] [CRITICAL] `Process.run('chmod', ['+x', tmpPath])` (line 294) is called unconditionally on all platforms — `chmod` does not exist on Windows, causing a silent error and a non-executable binary being renamed over the app. Needs `if (!Platform.isWindows)` guard — `advanced_settings_screen.dart:294`

- [ ] [MAJOR] `_LocalStorageBox._clearTag` calls `appState.engine.clearCache(accountId: appState.activeAccountId)` for **every** tag index (0–5), not just tag 5 ("Media Cache") — lines 1903–1905. Clearing "Images" or "Stickers" also wipes the engine's entire media cache for the active account. Fix: wrap the engine call in `if (tagIdx == 5)` — `advanced_settings_screen.dart:1903`

- [ ] [MAJOR] `_ProxiesBoxState._checkAllProxies` (lines 2923–2928) fires all proxy `callGeneric('CheckProxy', ...)` calls simultaneously with no concurrency limit or await — all proxies are checked in parallel instantly. With 10+ proxies this could flood the engine. Should add a small delay between checks or use a sequential approach — `advanced_settings_screen.dart:2923`

- [ ] [MAJOR] `_ExperimentalSettingsBoxState._changed` getter (lines 4423–4428) returns `true` if any flag is currently `true`, not if flags differ from what was loaded in `initState`. The "Reset" button is visible whenever any flag is enabled, even when the user opened the dialog with those flags already set and made no changes. Should compare `_flags` against the original snapshot captured in `initState` — `advanced_settings_screen.dart:4423`

## auth_screen — cleanup

- [ ] [CRITICAL] `_hasCover` always returns `false` (line 137) — `_CoverGradient` widget is fully implemented but permanently unreachable. No auth step ever shows the gradient header with UniClient branding. The `_isCover` transition flag (line 308) and the `AnimatedContainer` height logic (line 367) are also dead. Fix: implement `_hasCover` to return `true` for the appropriate step(s) (e.g. `'choose'`) so the cover gradient actually appears. — `auth_screen.dart:137`

- [ ] [MAJOR] `_rebuildDigits` (line 1592) does not reinitialize `_isDeleting` — when `widget.digitCount` changes (handled in `didUpdateWidget` at line 1587), `_digits`, `_digitAnimControllers`, `_fadeAnims`, and `_slideAnims` are all rebuilt to the new length, but `_isDeleting` is never touched. Any subsequent `_isDeleting[i]` access for `i >= old.digitCount` will throw `RangeError`. Add `_isDeleting = List.filled(widget.digitCount, false);` inside `_rebuildDigits`. — `auth_screen.dart:1592`

- [ ] [MAJOR] `_startCallTimer` callback calls `setState` without a `mounted` guard (line 1616) — `dispose()` cancels the timer, but there is a race window where the timer fires after `dispose()` begins but before `cancel()` runs. The callback mutates `_callSecondsLeft` and invokes `widget.onResendCode` unconditionally. Add `if (!mounted) { t.cancel(); return; }` at the top of the callback. — `auth_screen.dart:1616`

- [ ] [MAJOR] `_startFloodCountdown` callback calls `setState` without a `mounted` guard (line 1295) — same race as above. The timer is cancelled in `dispose()` but a pending callback can still fire. Add `if (!mounted) { timer.cancel(); return; }` at the top of the callback. — `auth_screen.dart:1295`

## ayu_appearance_page — cleanup

- [ ] [CRITICAL] Fallback avatar in `_AvatarCornersPreviewState.build()` uses `ClipOval` (line 480) instead of `ClipRRect(borderRadius: BorderRadius.circular(avatarRadius))` — when no real avatar loads (network unavailable, not logged in, etc.), the preview stays circular regardless of the slider position, so the entire corner-radius preview is broken in the no-avatar case. Fix: replace `ClipOval` with `ClipRRect(borderRadius: BorderRadius.circular(avatarRadius))` matching the real-avatar path at line 464. — `ayu_appearance_page.dart:480`

- [ ] [MAJOR] Keyboard scroll offset in `_onKeyEvent` uses `newIdx * 40.0` (line 684) but each font list item is `padding: EdgeInsets.symmetric(vertical: 8)` (16 px) + fontSize 13 text (~16 px) = ~32 px tall. The 40 px constant overshoots by ~25% per item — keyboard navigation scrolls past the selected row. Fix: use the real item height constant (32.0) or use `Scrollable.ensureVisible`. — `ayu_appearance_page.dart:684`

- [ ] [MAJOR] `Image.memory(_userpicBytes!)` at line 466 has no `cacheWidth`/`cacheHeight` — Telegram avatar files can be up to 640×640; the display size is 46×46 (92×92 at 2× DPI). The full-resolution image is decoded and kept in memory. Fix: add `cacheWidth: 92, cacheHeight: 92`. — `ayu_appearance_page.dart:466`

- [ ] [MAJOR] `_filteredFonts` getter (line 797) allocates a new `List<String>` on every invocation — called in `build()` (line 815) AND in `_onKeyEvent` (line 661). With 500+ system fonts, every key-repeat event triggers an O(n) allocation. Fix: cache the filtered result in a field, invalidate only when `_searchQuery` or `_systemFonts` changes (e.g. in the `onChanged` callback and after `_loadSystemFonts` completes). — `ayu_appearance_page.dart:797`

## ayu_chats_page — cleanup

- [ ] [CRITICAL] `_BubbleRadiusSlider` applies change before confirmation — `ayu_chats_page.dart:494-510`
  `onChanged` calls `widget.onChanged(newVal)` on every drag tick, persisting the value immediately.
  `onChangeEnd` then shows a "Restart Required" confirm box **with no `onCancel`** and no revert path.
  Contrast with `_WideMultiplierSlider` (lines 384–399) which only calls `widget.onChanged` inside
  `onConfirm` and reverts the visual on cancel.
  Fix: move `widget.onChanged` out of `onChanged`, into `onChangeEnd`'s `onConfirm` callback, and
  add `onCancel: () => setState(() => _localValue = _committedValue)` — matching the multiplier pattern.
  Also move `_committedValue = newVal` inside `onConfirm` so it isn't clobbered before the user decides.

- [ ] [MAJOR] `_MessagePreviewStandalone.build()` calls `context.read<AppState>()` at line 689 — anti-pattern
  `context.read` inside `build()` does not subscribe to updates.  If `activeAccount` changes (login /
  account switch) without the parent `AyuChatsPage` also rebuilding, the displayed `userName` goes stale.
  Fix: pass `userName` as a constructor parameter from `AyuChatsPage.build()` where `context.watch` is
  already live, or change line 689 to `context.watch<AppState>()`.

- [ ] [MAJOR] `_WideMultiplierSlider` slider range [1.0, 4.0] doesn't match `AppState.setWideMultiplier`
  clamp of [0.5, 4.0] — `ayu_chats_page.dart:381-382` vs `app_state.dart:962`
  Persisted prefs with `wideMultiplier < 1.0` (e.g. from a future import or direct prefs edit) will be
  accepted by the state but clamped to 1.0 silently in `initState` (line 328).  The slider will show 1.0
  while AppState holds 0.7, so the next drag will immediately snap to 1.0 and save that, discarding the
  persisted value.  Fix: align the clamp in both places (either widen the slider min to 0.5 or tighten
  the setter's lower bound to 1.0).

## ayu_filters_page — cleanup

- [ ] [CRITICAL] `_doImport` never reads `parsed['version']` so version validation is silently skipped — `AyuFilterEngine.previewImport()` (`ayu_filter.dart:356-358`) throws on `version > 2`; `_doImport` reimplements parsing inline and never calls `previewImport()`, so a v3+ export is applied without error instead of being rejected — `ayu_filters_page.dart:1510`

- [ ] [MAJOR] `_doImport` (lines 1558–1608) reimplements `AyuFilterEngine.previewImport()` + `applyImport()` inline — the diff computation (add vs update split, exclusion dedup) and the apply loop are duplicated verbatim; call `engine.previewImport(parsed)` then `engine.applyImport(changes)` instead — `ayu_filters_page.dart:1558`

- [ ] [MAJOR] `_doExport` (lines 1703–1802) reimplements `AyuFilterEngine.exportFilters()` + `publishFilters()` inline — both engine methods (`ayu_filter.dart:346`, `ayu_filter.dart:433`) already contain the identical clipboard/dpaste logic and are kept in sync there; the UI copy will drift — `ayu_filters_page.dart:1703`

- [ ] [MAJOR] `_AyuFiltersListScreen.build()` calls `context.watch<AppState>()` (line 559) which triggers a full rebuild — including `_buildFilterListContent`/`_buildShadowBanContent`/`_buildPickExcludeContent` list allocations — on every unrelated `AppState` notification (incoming messages, typing state, etc.); narrow to `context.select` for the filter-specific fields (`filterEngine`, `shadowBanIds`) — `ayu_filters_page.dart:559`

- [ ] [MAJOR] filter rows built as pre-allocated `List<Widget>` inside `_buildFilterListContent` / `_buildPickExcludeContent` (for-loops adding to `children`) rather than lazy `ListView.builder` items — all rows constructed even when off-screen; `ayuSettingsScaffold` passes these as a flat children list so Flutter's deferred rendering cannot help — `ayu_filters_page.dart:640`

## ayugram_settings_screen — cleanup

- [ ] [MAJOR] `launchUrl` return value discarded with no error handling at line 249 — if no browser/handler is installed on Linux the link silently does nothing, user gets zero feedback — `ayugram_settings_screen.dart:249`
- [ ] [MAJOR] Four consecutive `const SizedBox(height: 8)` at lines 118-121 — should be a single `const SizedBox(height: 32)`; confusing and fragile if spacing ever needs adjusting — `ayugram_settings_screen.dart:118`
- [ ] [MAJOR] `Image.asset` at line 72 decoded at full PNG resolution — display size is 100 dp (up to 300px at 3× DPR) but no `cacheWidth`/`cacheHeight` hint, so a 512×512 app icon PNG is decoded at full size and held in the image cache — `ayugram_settings_screen.dart:72`

## ayu_other_page — cleanup

- [ ] [CRITICAL] `_SupportDescription` creates `TapGestureRecognizer()` inline in `build()` (line 409) — a new recognizer is allocated on every parent rebuild and the previous one is never disposed, leaking `GestureRecognizer` objects. Must be converted to a `StatefulWidget` with `late final TapGestureRecognizer _recognizer` initialized in `initState()` and disposed in `dispose()`, same pattern as `_DonateInfoBoxState` — `ayu_other_page.dart:409`

- [ ] [CRITICAL] `_DonateQrBox.name` is a required constructor parameter (line 638) but is never referenced in `build()` — the dialog title is hardcoded as `'QR Code'` (line 668) for every coin. The user cannot tell which coin's address they are looking at. Fix: change title to `Text('$name', ...)` — `ayu_other_page.dart:668`

- [ ] [CRITICAL] `crashReporting` toggle (lines 95–104) is a UI-only stub — `setCrashReporting(v)` (app_state.dart:1381) only stores the preference and calls `_saveWindowPrefs()`; it does not initialize, enable, or disable any crash reporting SDK. No Sentry/Crashlytics/native crash handler is wired anywhere. The feature appears functional but does nothing — `ayu_other_page.dart:99`

- [ ] [MAJOR] `_DonateInfoBox._rcFetched = true` is set before the HTTP request (line 429), before the `try` block. A network failure on first open (cold start, no connectivity) permanently marks the config as fetched for the entire process lifetime; the fallback hardcoded values (`'5.00'`, `'3.50'`, `'386'`, `'RadianceTG'`) are shown forever with no retry. Fix: only set `_rcFetched = true` inside the `if (response.statusCode == 200)` branch, and use a separate in-progress bool to prevent concurrent calls — `ayu_other_page.dart:429`

## ayu_section_builder — cleanup

- [ ] [MAJOR] `_BetaBadgeOverlay.build()` calls `TextPainter.layout()` on every rebuild (lines 204–212) to measure label width for badge x-offset — heavy layout computation inside `build()`, and the painter is never disposed (memory pressure on high-rebuild trees); should cache in a stateful wrapper or use `LayoutBuilder` — `ayu_section_builder.dart:204`

- [ ] [MAJOR] `_BetaBadgeOverlay` badge position uses hardcoded `fontSize: 14` in the measurement `TextSpan` (line 206) without applying `MediaQuery.textScaleFactor` — at non-default system font sizes the measured width diverges from the actual rendered width, causing the beta badge to visually overlap or gap the label text — `ayu_section_builder.dart:206`

- [ ] [MAJOR] Inconsistent accent-color sourcing: `_AyuSlider` derives accent from `context.palette.windowBgActive` (lines 384, 403), but `_AyuChooseButton` (line 452), `_AyuCollapsibleToggle` (line 617), and `_NestedCheckbox` (line 751) all hardcode the same hex literals (`0xFF6AB2F2` / `0xFF3390EC`) — if the palette's `windowBgActive` is ever customised (per-account accent colour, custom themes), those three widgets will stay frozen on the default blue — `ayu_section_builder.dart:452`

- [ ] [MAJOR] `ayuSettingsScaffold` hardcodes AppBar background as `Color(0xFF17212B)` / `Colors.white` (line 878) instead of using `context.palette.titleBg` / `titleBgActive` — bypasses the palette system entirely; will look wrong under any non-default theme — `ayu_section_builder.dart:878`

- [ ] [MAJOR] `addSectionTitle` and `addSubsectionTitle` are byte-for-byte identical (lines 23–38, same padding, same font style, same accent colour) — one of them is dead code; callers cannot produce visually distinct section vs subsection titles, making the distinction a no-op — `ayu_section_builder.dart:32`

# ayu_toggle — clean

## call_panel — cleanup

- [ ] [CRITICAL] "Get Shareable Link" flow calls `endCall` before `joinGroupCall` with no try-catch — if `joinGroupCall` throws after the P2P call is dropped, the user is left with no active call and no error feedback; compare the 'invite' flow at line 442 which correctly joins first, then ends — `call_panel.dart:470-474`

- [ ] [CRITICAL] `_LiveCallPanelDialog` wraps `CallPanel` in a hardcoded `SizedBox(width: 720, height: 540)` — on a 400px mobile screen the dialog overflows and is unusable; needs `LayoutBuilder`/`MediaQuery` to constrain to screen size — `call_panel.dart:2248-2250`

- [ ] [MAJOR] macOS device enumeration adds `coreaudio_output_source` devices (speakers/headphones) to `_cameraDevices` — `SPAudioDataType` output sources are audio outputs, not cameras; only `SPCameraDataType` items should go into the cameras list — `call_panel.dart:203-206`

- [ ] [MAJOR] `_buildUserpic` calls `File(url).existsSync()` synchronously inside `build()` on every rebuild — blocking I/O on the UI thread; should cache the existence check or use `FutureBuilder` — `call_panel.dart:673`

- [ ] [MAJOR] `_SelfViewBubble` uses `_snapController.addListener(() => setState(() {}))` — rebuilds the entire bubble subtree on every animation frame during the snap; replace with `AnimatedBuilder` scoped to the positioned child — `call_panel.dart:2001`

- [ ] [MAJOR] `_durationTimer` calls `setState` on the root `_CallPanelState` every second — forces a full rebuild of the entire call panel (including video widgets) just to update a `mm:ss` counter; extract the timer display into a `ValueListenableBuilder` with a `ValueNotifier<int>` — `call_panel.dart:321-327`

- [ ] [MAJOR] `_filteredContacts` getter allocates a new filtered list on every `build()` call — no memoization; fires on every keystroke `setState` in the search field; cache the result and only recompute when `_searchQuery` or `_contacts` changes — `call_panel.dart:1442-1450`

## call_screen — cleanup

- [ ] [CRITICAL] `_showJoinAsChooser` onTap (line 1360–1362) just calls `Navigator.pop(ctx)` — selecting an account does nothing; no engine call to rejoin/switch identity. The entire "Join As..." feature is a non-functional stub. Need to call `engine.joinGroupCall(selectedAccountId, callId)` and update the active account in the panel. — `call_screen.dart:1360`

- [ ] [CRITICAL] `_showInviteMembersFromMenu` (line 1448) is fully implemented (fetches contacts, shows picker, calls `engine.inviteToConferenceCall`) but is **never called** — there is no "Invite Members" entry in `_showGroupCallMenu` (lines 1248–1308). Invite feature is unreachable from the UI. Add a ListTile for it in `_showGroupCallMenu`. — `call_screen.dart:1448`

- [ ] [CRITICAL] Linux audio device picker (lines 1383–1388) strips and prettifies the PulseAudio sink name before adding it to `devices`, then passes the prettified display name directly to `engine.setCallAudioDevice(accountId, 'output', d)` at line 1437. The engine stores that name in `config.CallOutputDevice` and will use it for routing — but `"pci-0000 00 1f.3 (Analog Stereo)"` is not a valid PulseAudio sink identifier. Fix by storing the raw sink name (`parts[1]`) as the device ID while keeping the prettified string only for display. — `call_screen.dart:1383`

- [ ] [CRITICAL] Recording hardcodes path `/tmp/call_recording_$timestamp.wav` (line 1266) with no platform guard. `/tmp/` does not exist or is sandboxed on macOS, Windows, Android, and iOS; recordings silently fail on those platforms. Use `getTemporaryDirectory()` (from `path_provider`) and show the saved path to the user. — `call_screen.dart:1266`

- [ ] [CRITICAL] macOS/Windows window enumeration in `_enumerateWindows` (lines 2642–2646) returns a single stub entry `ScreenShareSource(id: 'window:0', name: 'All Windows', isScreen: false)`. Selecting it passes the meaningless ID `'window:0'` to the engine. Need real window enumeration via `CGWindowListCopyWindowInfo` on macOS or `EnumWindows` on Windows, or at minimum remove the tab and show "Not supported on this platform". — `call_screen.dart:2643`

- [ ] [MAJOR] `File(p.avatarPath).existsSync()` is called inside `_buildParticipantRow` (line 218), which is invoked synchronously during `build()` for every participant row. Synchronous filesystem I/O on the UI thread causes jank when the participant list scrolls or updates. Cache the result in the model or pre-compute it outside `build()`. — `call_screen.dart:218`

- [ ] [MAJOR] `Image.file(File(p.avatarPath), width: 36, height: 36, ...)` (lines 220–225) specifies display size but omits `cacheWidth`/`cacheHeight`, so Flutter decodes the full-resolution image into the image cache. For a 36×36 px display target use `cacheWidth: 72, cacheHeight: 72` (2× for HiDPI). Same issue in `_ParticipantAvatar` which uses `FileImage(File(avatarPath))` (line 2304) without cache sizing for a 28×28 px avatar. — `call_screen.dart:220`, `call_screen.dart:2304`

- [ ] [MAJOR] `_MinimisedCallBarState` timer (line 1749) increments `_durationSeconds++` on each tick rather than recalculating from `callStartTime`, so the displayed duration drifts under system load. `_GroupCallPanelState` correctly recalculates on every tick (`DateTime.now().difference(_callStartTime).inSeconds`). Apply the same approach here. — `call_screen.dart:1749`

# calls_screen — cleanup

- [ ] [CRITICAL] `_ConferenceCallLinkBox` "Join this call yourself" (line 1679): calls `engine.joinGroupCall` but never calls `showGroupCallPanel` — user enters the call with no UI to mute/hang up. Also skips `requestCallPermissions` check. Compare with the functioning join at line 721 which does both. Fix: add permission check, then after join fetch `GroupCallInfo` via `engine.getGroupCall` and call `showGroupCallPanel`. — `calls_screen.dart:1679`

- [ ] [MAJOR] Side effects inside `_InputLevelMeterState.build()` (lines 3042-3047): `_controller.stop()` and `_controller.repeat()` are called conditionally based on `powerSaving` state — mutating an `AnimationController` inside `build()` violates Flutter's pure-build requirement. Move to `didUpdateWidget` or a separate method triggered by `AppState` listener. — `calls_screen.dart:3042`

- [ ] [MAJOR] `_onMsgReceived` at line 274 triggers a full `getCallHistory` API call for every service message (including "X joined group", "Admin changed title", pin events, etc. — confirmed by Go base.go:282 comment). Should filter to call-type service messages only before refreshing. — `calls_screen.dart:274`

- [ ] [MAJOR] `ListView.builder` at line 431 uses `shrinkWrap: true` inside a `Flexible` parent. The `Flexible` already bounds height, so `shrinkWrap` forces the ListView to compute the full content extent on every layout pass, degrading scroll performance for large call histories. Remove `shrinkWrap: true`. — `calls_screen.dart:431`

- [ ] [MAJOR] `Image.file()` at lines 664 and 2140 (group call row and call history row) lack `cacheWidth`/`cacheHeight` — full-resolution avatar images are decoded into memory and then scaled by the widget. Add `cacheWidth: (avatarSize * 2).toInt()` and `cacheHeight: (avatarSize * 2).toInt()`. — `calls_screen.dart:664`, `calls_screen.dart:2140`

- [ ] [MAJOR] `base64Decode(c.avatarB64)` at line 1806 is called inside `_ConfInviteRowState.build()` on every render of each contact row. Base64 decoding is CPU-intensive; with 100s of contacts this fires frequently (search input triggers setState per keystroke). Cache the decoded bytes in a field keyed to the contact, or compute in `initState`/`didUpdateWidget`. — `calls_screen.dart:1806`

## chat_export — cleanup

- [ ] [CRITICAL] dead branch in `_buildPerChatSettings`: `if (!_isPerChat) _buildSectionHeader('Media export settings', ...)` at line 1851 — `_buildPerChatSettings` is only ever called when `_isPerChat == true` (line 1298–1300), so this condition is always false and the "Media export settings" header is **never rendered** in per-chat mode — media checkboxes appear with no section header above them — `chat_export.dart:1851`

- [ ] [CRITICAL] `_buildErrorPlaceholder` has zero interactive elements in its content area (lines 2520–2553) — error screen shows only a text message; no "Try Again", no "Close" button — user can only escape via the tiny title-bar X — disk IO errors and API errors should offer a retry or at minimum a visible dismiss button inside the content — `chat_export.dart:2520`

- [ ] [MAJOR] direct field mutation outside `setState` throughout `_onExportProgress` (lines 880–933) and `_skipCurrentFile` (lines 1059–1063): `_exportSteps[i].label`, `.progress`, `.info`, `.opacity`, `.wasReported`, plus `_currentStepIndex`, `_totalFiles`, `_totalSizeBytes`, `_fileRandomId`, `_showSkipFile` are all mutated directly, then `setState(() {})` with an empty body is called to trigger rebuild — if any mutation throws before reaching that setState call, state is corrupted with no rebuild scheduled; move all mutations inside the setState callback — `chat_export.dart:880`

- [ ] [MAJOR] `DateTime.now()` is called inside the inner cell-building loop in `_buildDayGrid` (line 2783) — the loop runs up to 42 iterations (6 rows × 7 cols) per build, calling `DateTime.now()` for each cell — hoist it to a single variable before the outer loop — `chat_export.dart:2783`

- [ ] [MAJOR] `_loadExportSettings` (sync, runs at initState) and `_loadEngineSettings` (async, completes later) both set overlapping fields (`_personalInfo`, `_contacts`, `_stories`, `_profileMusic`, `_personalChats`, `_botChats`, `_privateGroups`, `_privateChannels`, `_publicGroups`, `_publicChannels`, `_exportLocation`, `_format`) — when the engine response arrives it calls `setState` and overwrites the already-rendered local values, causing a visible settings jitter on every panel open if engine and local JSON ever diverge — load engine settings first and fall back to local JSON, or merge them once after both resolve — `chat_export.dart:482`

# chat_list_panel — cleanup

## CRITICAL

- [ ] [CRITICAL] Forum "Delete Topic" calls `deleteForumTopicHistory` (clears messages only) instead of `editForumTopic(deleted=true)` — the topic stays in the list after "deletion" — `chat_list_panel.dart:5611`

- [ ] [CRITICAL] `_SavedSublistRow` is constructed at line 6199 without a `tags` argument — the `tags` field defaults to `const []`, `hasTags` is always false, and the `_buildTagPills` method is permanently dead code; per-sublist reaction tag pills are never shown — `chat_list_panel.dart:6199`

- [ ] [CRITICAL] "Public Posts" search tab calls synchronous `chatState.searchGlobalPostMessages` (local cache read, no network) — no live network search is triggered when user types in the Public Posts tab; results are limited to whatever was already cached locally — `chat_list_panel.dart:532`

## MAJOR

- [ ] [MAJOR] `_StoriesBarState._storyRefreshTimer` calls `chatState.loadChats()` (full 500-chat engine sync) every 60 seconds just to refresh story counts — should call a story-specific update path or be removed in favour of engine-pushed events — `chat_list_panel.dart:2847`

- [ ] [MAJOR] `_onSearchChanged` fires both `chatState.searchChats` and `chatState.searchMessages` on every keystroke with no debounce — rapid typing issues multiple concurrent async searches; add a 250–300 ms debounce timer that cancels the previous search before launching a new one — `chat_list_panel.dart:516`

- [ ] [MAJOR] `_ArchivedChatsRow._buildWide()` puts a `Container(width: 46, height: 46)` circle inside a `SizedBox(height: 37)` row — the avatar is constrained/clipped to 37 px and looks wrong; Telegram Desktop spec uses a ~26 px icon for the `dialogsImportantBarHeight` row — `chat_list_panel.dart:4093`

- [ ] [MAJOR] `_buildExpanded` wraps every story item in a top-level `Opacity` widget — forces an offscreen compositing layer for each story while animating; apply opacity directly to the Image/avatar color or use `FadeTransition` to avoid per-item layers — `chat_list_panel.dart:3091`

## chat_list_row — cleanup

- [ ] [CRITICAL] `ForumChatListRow` narrow mode (lines 2120–2141) shows only a bare avatar with no unread indicators — `ChatListRow` narrow mode renders `_UnreadBadge`, `_UnreadDot`, and `@` mention badges in a `Stack` over the avatar, but `ForumChatListRow`'s narrow branch is a plain `Center(child: _ChatAvatar(...))` with nothing else — `chat_list_row.dart:2120`

- [ ] [MAJOR] `base64Decode(chat.lastMsgThumbB64)` called unconditionally inside `build()` on every rebuild — no memoization; decodes the full byte array each time the row redraws (hover, badge change, etc.) — `chat_list_row.dart:405`

- [ ] [MAJOR] `Image.file` for chat avatar missing `cacheWidth`/`cacheHeight` — Flutter caches the full-resolution disk image; for a 46px avatar this wastes significant memory across a long chat list — `chat_list_row.dart:1072`

- [ ] [MAJOR] `context.watch<AppState>()` in `_ChatAvatar.build()` subscribes to the entire `AppState` to read only `avatarCorners` — every AppState notification (unread count update, any setting change, chat arrival) triggers a rebuild of ALL visible chat avatars; replace with `context.select((AppState s) => s.avatarCorners)` — `chat_list_row.dart:1058`

- [ ] [MAJOR] `context.read<AppState>()` used for three UI-affecting flags — `hidePremiumStatuses` (line 224), `experimentalFlags['dialogs_mute_icon']` (line 233), and `experimentalFlags['message_draft_visible']` (line 332) — `context.read` does not subscribe, so the row will not update when the user changes these settings; replace with `context.select` or `context.watch` for each flag — `chat_list_row.dart:224`

- [ ] [MAJOR] `geo_location` action returns `'typing'` (line 1318) and `choose_contact` returns `'typing'` (line 1320) — both should have distinct labels per Telegram's `ChatAction` spec: `geo_location` → `'sending location'`, `choose_contact` → `'sending contact'` — `chat_list_row.dart:1318`

- [ ] [MAJOR] `_formatTime` is implemented identically in both `ChatListRow` (line 473) and `ForumChatListRow` (line 2291) — any future fix to one (e.g. locale, timezone edge-case) must be duplicated manually; extract to a top-level function — `chat_list_row.dart:473`

- [ ] [MAJOR] `_TopicsPreview` wraps its entire `build` in `LayoutBuilder` (line 2330) but the `constraints` parameter is never read inside the builder — `LayoutBuilder` forces an extra layout-constraint measurement pass on every rebuild for no benefit; remove it — `chat_list_row.dart:2330`

- [ ] [MAJOR] `_committed` field (line 656) is set to `true` at line 777 and back to `false` at line 793 but is never read anywhere in the class — dead state that adds noise and suggests the intended commit-lock logic (e.g. block re-trigger during snap-back) was never wired in — `chat_list_row.dart:656`

## chat_settings_screen — cleanup

- [ ] [CRITICAL] `onPaletteChanged: (_) {}` empty callback at lines 634 and 2381 — `ThemeEditorScreen` calls this at lines 212 and 412 of `theme_editor.dart` whenever the user edits colors, but both call-sites in `chat_settings_screen.dart` discard the result. Any palette changes made in the theme editor are silently thrown away and never applied to `AppState`. Needs to call `appState.applyPalette(palette)` or equivalent — `chat_settings_screen.dart:634` and `chat_settings_screen.dart:2381`

- [ ] [CRITICAL] "Use system accent color" checkbox sets hardcoded `#40a7e3` instead of reading any system color — `appState.useSystemAccent` is only ever stored/restored as a preference flag; nothing in the codebase reads it to query a platform accent color. The entire effect of checking this box is `appState.updateAccentColor('#40a7e3')`, which just resets to Telegram's default blue. The flag is effectively dead after being written — `chat_settings_screen.dart:410-413`

- [ ] [CRITICAL] `_EditPeerColorBox` preview swatch shows hardcoded `'Your Name'` / `'Message preview text'` strings — `widget.accountId` is available but the dialog never fetches the user's actual display name from the engine. The preview is supposed to show how the color looks on the user's own name; showing a generic string is a placeholder not a real preview — `chat_settings_screen.dart:1719` and `chat_settings_screen.dart:1729`

- [ ] [MAJOR] Base64 thumbnail decoding runs inside `GridView.builder` itemBuilder — `const Base64Decoder().convert(thumbB64)` is called on every build of each wallpaper tile (line 2769). `GridView.builder` calls itemBuilder during scroll, causing repeated allocations and CPU work per frame. Pre-decode all thumbnails into `Uint8List` once in `_WallpaperBrowser.build` before building the grid — `chat_settings_screen.dart:2766-2772`

- [ ] [MAJOR] Zero-sigma `ImageFilter.blur` applied unconditionally when `_blurred == false` — `ImageFiltered(imageFilter: _blurred ? ImageFilter.blur(...) : ImageFilter.blur(sigmaX: 0, sigmaY: 0), ...)` always wraps the preview image in an `ImageFiltered` widget and compositor layer even when blur is off. Replace with a conditional: only wrap with `ImageFiltered` when `_blurred` is true — `chat_settings_screen.dart:4909-4935`

- [ ] [MAJOR] `_reorder` reads `appState.activeAccount` instead of `widget.accountId` — if the user switches accounts while the sticker pack manager bottom sheet is open, the `reorderStickerSets` call at line 3703 sends the reorder to the newly active account, not the one the pack list was loaded for. Use `widget.accountId` directly — `chat_settings_screen.dart:3699-3703`

- [ ] [MAJOR] Emoji sets load failure silently falls back to sticker packs — when `engine.getInstalledEmojiSets` throws (line 3662), the catch at line 3673 calls `getInstalledStickerPacks` and populates `_packs` with sticker data. The Emoji Sets manager then displays sticker packs to the user without any indication that the emoji load failed. Should show an error state instead of silently substituting sticker packs — `chat_settings_screen.dart:3659-3676`

- [ ] [MAJOR] `_showAllCloudThemes` is always `true`; horizontal scroll grid is dead code — the state field is initialised to `true` and the `onToggleShowAll` callback only sets it to `true` when already `false` (`if (!_showAllCloudThemes) setState(() => _showAllCloudThemes = true)`), so it can never become `false`. The horizontal `ListView` branch in `_buildGrid` (lines 2268-2285) is unreachable. Either wire a real toggle or remove the dead branch — `chat_settings_screen.dart:37` and `chat_settings_screen.dart:437-439`

## chat_switch_overlay — cleanup

- [ ] [MAJOR] `_onChatStateChanged` returns early on `removed.isEmpty` — when `recentTopicsFor` asynchronously loads topic data it calls `notifyListeners()`, which fires this listener, but the listener exits without `setState` because no chats were removed; forum-topic cells in the overlay never redraw to show the loaded custom emoji icon or correct `colorId` — `chat_switch_overlay.dart:78`

- [ ] [MAJOR] `base64Decode` called uncached for parent-badge avatar — lines 490 and 495 call `base64Decode(parentChat.avatarPath)` inline on every rebuild; the main userpic is cached through `_decodeAvatar`/`_avatarCache`, but the 20×20 parent badge for topic cells bypasses the cache entirely, re-decoding a potentially large base64 string on each frame — `chat_switch_overlay.dart:490`

- [ ] [MAJOR] state mutated directly inside `build()` without `setState` — inside the `LayoutBuilder` callback, `_shownPerRow`, `_shownRows`, and `_selected` are all assigned as bare field writes (lines 276–281); Flutter's framework is never notified of the `_selected` clamp, so if a rebuild is triggered by something other than user input (e.g. theme change, ancestor rebuild) before the next keyboard event, the visual selection and the internal field can diverge until the next setState cycle — `chat_switch_overlay.dart:276`

# chat_view — cleanup

## CRITICAL

- [ ] [CRITICAL] `delete_all` case (line 2866) calls `engine.banMember(accountId, chat.chatId, senderId)` — but the menu label is "Delete All from User" and the success toast says "All messages from $senderName deleted". The user gets banned, zero messages are deleted. Should iterate visible messages and call `engine.deleteMessage` for each, or add a dedicated bulk-delete method to the engine. — `chat_view.dart:2861`

- [ ] [CRITICAL] `share_contact` case (lines 2784–2795) copies `profile.phone` to the system clipboard with a toast "Contact phone copied: $phone" — but the menu item is "Share Contact". In Telegram Desktop, Share Contact sends the person as a contact message (vCard) in the current chat. Should call `engine.sendContact(accountId, chatId, phone, firstName, lastName)` instead of `Clipboard.setData`. — `chat_view.dart:2784`

- [ ] [CRITICAL] `_showUserMessages` (line 2134) filters `chatState.messages` — the currently loaded in-memory page (~50–100 items). Older messages are invisible to this dialog. The real "User's Messages" feature searches the full history server-side and opens a filtered search/scroll view. The current dialog silently shows a fraction of all messages with no indication anything is missing. — `chat_view.dart:2134`

## MAJOR

- [ ] [MAJOR] `_WaveformPainter.shouldRepaint` (line 10316) does not check `bars != old.bars`. If the bars list loads or changes after the initial render while `progress` and colors are unchanged (e.g., at position 0.0), the waveform stays blank. Add `bars != old.bars` to the condition. — `chat_view.dart:10316`

- [ ] [MAJOR] `_AiEditorButton` button tooltip says "AI Editor" (line 21615) and `_openAiEditor` is the handler name, but `_AiMode` has exactly one value (`translate`) and the dialog header reads "Translate". The button is mislabeled — either rename tooltip/button to "Translate" or implement the additional AI modes the name implies. — `chat_view.dart:21689`

- [ ] [MAJOR] `_updateStickyDate` (line 901) uses `const avgHeight = 55.0` to estimate which message index sits at the top of the viewport (`topIndex = (topDistance / avgHeight).floor()`). Message heights vary widely: photos ~160–200 px, stickers ~140 px, plain text ~44 px. The estimated index will frequently point to a message from a different day, showing the wrong date badge. Use `ScrollPosition.extentBefore`/position tracking or render the real sticky date from visible items reported by a `ScrollNotification`. — `chat_view.dart:901`

- [ ] [MAJOR] Service message widget dispatch (line 7547) uses `msg.contentText.contains('created the group')` and `contains('created topic')` to choose between `_GroupAboutServiceMessage` and `_TopicCreatedServiceMessage`. These are raw English strings from the Go bridge. Any change in bridge wording silently falls through to the generic `_ServiceMessage` widget with no error. Should use a typed field (e.g., `msg.serviceType` enum) rather than substring-matching localizable text. — `chat_view.dart:7547`

- [ ] [MAJOR] `AnimatedPadding` inside `ListView.builder` item builder (line 7655) fires on every visible row simultaneously when `inSelectionMode` toggles. In a chat with 50+ visible messages, all rows animate padding in parallel (160 ms, `Curves.easeInOut`). At minimum wrap each row's `AnimatedPadding` in a `RepaintBoundary`, or drive a single animation from the parent and propagate it as a plain offset rather than using implicit per-widget animations. — `chat_view.dart:7655`

## choose_datetime_box — cleanup

- [ ] [CRITICAL] `_updateSelection` (line 298) is defined but never called — `_selectDay` always calls `_startSelection`, which resets both start and end to the tapped date on every tap; range selection always collapses to a single day. `_selectionAnchorIndex` is written in `_startSelection` (line 293) but never read anywhere, so the intended "first tap = anchor, second tap = extend" logic was never wired. Fix `_selectDay`: when `_selectionStart != null` (anchor already set), call `_updateSelection` instead of `_startSelection`. — `choose_datetime_box.dart:268`

- [ ] [CRITICAL] `_TimePickerBoxWidgetState._handleKey` (line 1795) is missing the `KeyDownEvent`/`KeyRepeatEvent` guard that every other `_handleKey` in this file has. It fires on `KeyUpEvent` too, so every single arrow-key press triggers the handler twice (once on down, once on up), moving the drum by 2 positions instead of 1. Add: `if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;` at the top. — `choose_datetime_box.dart:1795`

- [ ] [CRITICAL] "Telegram Premium" text in the premium toast (line 1637) has `TextDecoration.underline` and `FontWeight.w600` — the visual affordance of a tappable link — but the `TextSpan` has no `recognizer`. Clicking it does nothing. In Telegram Desktop this opens the premium subscription page. Add a `TapGestureRecognizer` that navigates to the premium upsell flow (or at minimum opens a premium info dialog). — `choose_datetime_box.dart:1637`

- [ ] [MAJOR] `_maxLabelWidth()` is called inside `build()` at line 1830. It iterates all labels and calls `TextPainter.layout()` on each one — allocating N TextPainter objects on every single rebuild of `_TimePickerBoxWidget`. The label list never changes after `initState`. Cache the result as a `late final double _drumWidth` in `initState`. — `choose_datetime_box.dart:1830`

- [ ] [MAJOR] `_measureTextWidth('at', ...)` is called inside the `LayoutBuilder` in `_ChooseDateTimeDialogState.build()` (line 1479). The input is a constant string with a constant font size; it will always return the same value. Allocating a fresh `TextPainter` on every rebuild is wasteful. Cache it as a field computed once in `initState`. — `choose_datetime_box.dart:1479`

- [ ] [MAJOR] `_dynamicImages` map (line 137) is never evicted as the user navigates between months. Each new month loads entries for up to 31 days; each loaded entry holds an `AnimationController` (backed by a `Ticker`). Old months' controllers are not disposed until the entire widget closes. If a user scrolls through many months, controllers accumulate. Cap the cache to ~3 months and dispose evicted controllers immediately. — `choose_datetime_box.dart:162`

- [ ] [MAJOR] `_showRepeatMenu()` (line 1366) calls `context.findRenderObject()` where `context` is `_ChooseDateTimeDialogState`'s root context, giving the entire dialog's `RenderBox`. `Offset(0, box.size.height)` is the bottom-left corner of the dialog in global coordinates — not the position of the Repeat button row. The menu opens at the wrong place. Use a `GlobalKey` on the Repeat row widget and call `key.currentContext!.findRenderObject()` to get the button's own `RenderBox`. — `choose_datetime_box.dart:1366`

# engine_service — cleanup

- [ ] [CRITICAL] `startCallRecording`/`stopCallRecording` pass `accountId` as the `coreId` argument instead of `'__engine'` — routes to the wrong bridge handler, both methods silently fail at runtime — `engine_service.dart:2347` `engine_service.dart:2359`

- [ ] [CRITICAL] `_cachedMsgFromProto` sets `forwardFromId` to `p.forwardFrom` (the display name string) when `forward_from_id` is absent from the extra JSON — contaminates the ID field with a human-readable name; should fall back to `''` — `engine_service.dart:5985`

- [ ] [CRITICAL] `getChatMembersByRole` has no empty-response guard before `json.decode(utf8.decode(respBytes))` — if the engine returns an empty payload (ok=true, no body), `json.decode('')` throws `FormatException` that propagates unhandled — `engine_service.dart:1085`

- [ ] [CRITICAL] `getEditRevisions` has no empty-response guard — same crash path as above (`json.decode(utf8.decode(respBytes))` with no `isEmpty` check) — `engine_service.dart:2691`

- [ ] [CRITICAL] `hasEditRevisions` has no empty-response guard — same crash path — `engine_service.dart:2701`

- [ ] [CRITICAL] `updateProfile` hardcodes `'about': ''` in the payload — every call to change the display name silently overwrites the user's Telegram bio with an empty string — `engine_service.dart:4027`

- [ ] [CRITICAL] `_reactionsFromParsed` filters `.where((r) => r.emoji.isNotEmpty)` — custom emoji reactions (where `emoji` is `''` and `documentId` is the identifier) are dropped entirely and never shown — `engine_service.dart:6147`

- [ ] [MAJOR] `deleteForumTopicHistory` reuses `epb.EngineEditForumTopicRequest` as the proto message type for a delete operation — semantically wrong and fragile; only `account_id`, `chat_id`, `topicId` fields are set, no explicit delete payload — `engine_service.dart:802`

- [ ] [MAJOR] `getSessionsCount` fetches the full session list to get a count, then discards the data — `getBlockedUsersCount` correctly uses `limit: 1` + total field from the paged API; `getSessionsCount` should do the same or expose a dedicated count endpoint — `engine_service.dart:5325`

- [ ] [MAJOR] `_waveformFromParsed` (line 6152) and `_decode5BitWaveform` (line 6279) are identical 5-bit unpackers with different input types (base64 string vs raw bytes) — the base64 path in `_waveformFromParsed` should call `_decode5BitWaveform` after decoding, not duplicate the loop

## color_picker_box — cleanup

- [ ] [MAJOR] `onHover` in `_GradientSquareState` calls `setState` on every mouse move (line 811) — causes a full widget rebuild on every hover event just to update `_pointerPos`. Should pass a `ValueNotifier<Offset?>` as the `repaint` argument to `_CrosshairAndCursorPainter` and update the notifier directly, so only the canvas layer repaints without rebuilding the widget tree — `color_picker_box.dart:811`

- [ ] [MAJOR] `_HorizontalOpacityPainter.paint()` redraws its checkerboard tile-by-tile in a double loop on every call (lines 1092-1100). `shouldRepaint` returns true whenever `color` changes (i.e. every gradient-square drag), so the checkerboard is redrawn from scratch during every opacity slider interaction. The checkerboard is static — cache it as a `ui.Picture` or `ui.Image` on first paint and composite it with `canvas.drawImage`/`canvas.drawPicture` — `color_picker_box.dart:1092`

- [ ] [MAJOR] `_buildFieldColumn` hardcodes text and border colors instead of reading from palette (lines 523–525): `Color(0xFFE0E3EA)` / `Color(0xFF000000)` for text and `Color(0xFF3A4655)` / `Color(0xFFD9D9D9)` for borders. These bypass the `TelegramPalette` system and will look wrong on any non-standard theme — `color_picker_box.dart:523`

- [ ] [MAJOR] All `TextField` decorations in `_numField` and `_hexField` set `border` and `enabledBorder` but omit `focusedBorder` (lines 635–640, 679–683). When a field is focused Flutter falls back to the theme's default blue focus ring instead of the themed border color — `color_picker_box.dart:635`

- [ ] [MAJOR] Wheel scroll direction inconsistency across platforms (lines 593–599): `deltaY` starts as `-event.scrollDelta.dy` (scroll-down = negative), then on macOS it is negated again (`deltaY = -deltaY`), while on other platforms `deltaX` is re-negated instead. Result: scrolling down over a focused field increments the value on macOS but decrements it on Linux/Windows. The platform branch should negate `deltaX` on macOS (where horizontal natural scrolling is reversed) and leave `deltaY` consistent — `color_picker_box.dart:595`

# compose_entities — wiring issue

- [CRITICAL] Emoji placeholder replacement doesn't adjust entity lengths for overlapping formatting — `compose_entities.dart:367-373`

  **Issue:** When custom emoji placeholders are replaced with alt text (e.g., 1 char → 6 chars), other formatting entities that span across the emoji don't get their lengths adjusted. Only entities starting *after* the emoji get their offsets shifted.
  
  **Example:** Bold entity [offset: 2, length: 15] spans across emoji at [9, 1]. When emoji is replaced with 6-char alt text (delta=+5), the bold entity should become [2, 20] but stays [2, 15], breaking formatting ranges.
  
  **Root cause:** Line 372 only handles `if (e.offset > ce.offset)` (entities starting after emoji), missing entities that contain or overlap the emoji.
  
  **Impact:** Formatting entities sent to server have wrong byte ranges when they span custom emojis, breaking bold/italic/link/etc across emoji.
  
  **Fix:** After updating emoji entity length, also check and update overlapping entities:
  ```dart
  if (e == ce) {
    e.length = alt.length;
    continue;
  }
  if (e.offset >= ce.offset + ce.length) {
    // Entity starts at/after emoji ends — shift offset
    e.offset += delta;
  } else if (e.offset < ce.offset + ce.length && e.offset + e.length > ce.offset) {
    // Entity overlaps emoji — expand length
    e.length += delta;
  }
  ```

## confirm_box — cleanup

- [ ] [CRITICAL] `_ReportOptionPickerBox` Back button pops with `null` (line 1721: `Navigator.of(context).pop()`), which causes `showDynamicReportFlow` to hit the `if (picked == null) return false` guard at line 1545 — the entire report flow exits instead of going back one level. Additionally, `showDynamicReportFlow` only tracks `isSubLevel` (bool) with no option stack, so there is no mechanism to restore the previous level anyway. Back navigation in the multi-step report flow is completely broken. — `confirm_box.dart:1545,1721`

- [ ] [CRITICAL] `enum ReportTarget` (line 1504) is declared but never used anywhere in the codebase — no caller passes a target type, `showDynamicReportFlow` ignores target entirely, and `engine.reportMessage` is always called regardless. The enum is dead code and the report flow makes no distinction between reporting a message vs. a channel/bot/story/profilePhoto. — `confirm_box.dart:1504`

- [ ] [MAJOR] `_captureThumbnails()` runs thumbnail captures sequentially with `await` inside a `for` loop (lines 1294–1300). Each capture has a 3-second timeout (lines 1309, 1314, 1321). With up to 12 sources the dialog can take up to 36 seconds to populate. Should use `Future.wait` to capture all thumbnails in parallel. — `confirm_box.dart:1294`

- [ ] [MAJOR] Each thumbnail that arrives calls `setState` individually (line 1298), causing a full rebuild of the TelegramBox + GridView per thumbnail instead of batching. With parallel capture (see above) this would matter less, but even sequentially it's one rebuild per source. Collect all results first, then call `setState` once. — `confirm_box.dart:1297`

- [ ] [MAJOR] `openSystemSettingsForPermission` on Linux (line 1022) calls `Process.run('xdg-open', ['gnome-control-center://sound'])` — `xdg-open` does not handle `gnome-control-center://` URI scheme; the call silently fails on all desktop Linux environments. The fallback (line 1023) `xdg-open x-settings://sound` is also not a real scheme. Should call `gnome-control-center sound` directly (GNOME) or `systemsettings5` (KDE) or a generic `pavucontrol`. Users who click "Settings" on the microphone permission dialog will get no action on Linux. — `confirm_box.dart:1022`

- [ ] [MAJOR] `_SingleChoiceContentState._select()` always calls `Navigator.of(context).pop(index)` immediately on any radio tap (line 867), making the "OK" button (line 898–901) and the `onConfirm` Enter handler (line 879) dead code that can never be reached in normal usage. The OK button renders but never fires because the dialog is already dismissed. Remove the OK button or change `_select` to not auto-dismiss (depending on intended UX). — `confirm_box.dart:864,879,898`

- [ ] [MAJOR] `Image.file` for screen-share thumbnails (line 1395) specifies no `cacheWidth`/`cacheHeight`. Thumbnails are captured at 160×100 pixels by the capture commands (lines 1313, 1320) but Flutter decodes at full display resolution without size hints, wasting memory for each preview card. Add `cacheWidth: 160, cacheHeight: 100`. — `confirm_box.dart:1395`

## contacts_screen — cleanup

- [ ] [CRITICAL] `_columnsForWidth` always returns 4, ignoring the `screenWidth` parameter — stub method; on a 400px mobile screen 4 columns produces ~100px cells that are too cramped — `contacts_screen.dart:2117`

- [ ] [CRITICAL] online status updates silently dropped in alphabetical sort mode — `_throttledRefresh()` returns early at line 297 when `_sortMode != _SortMode.online`, so the mutation to `_contacts[idx]` (and the `_sortedCache = null` at line 331) never triggers `setState`; the contact row keeps stale status text and online dot indefinitely while in alphabetical mode — `contacts_screen.dart:297`

- [ ] [MAJOR] `base64Decode(contact.avatarB64)` called inside `_ContactRowState.build()` — every hover enter/exit fires `setState(() => _hovered = true/false)` which rebuilds and re-decodes the avatar bytes from scratch; should be decoded once and cached as a `Uint8List?` field, updated in `initState`/`didUpdateWidget` — `contacts_screen.dart:1088`

- [ ] [MAJOR] `base64Decode(contact.avatarB64)` called inside `_EditContactBoxState.build()` — same issue; decodes on every setState (saving, name change, _hasBirthday update); decode once in initState — `contacts_screen.dart:1697`

- [ ] [MAJOR] `ListView.builder(shrinkWrap: true)` inside `Flexible` — `shrinkWrap: true` forces the ListView to lay out all items eagerly, defeating lazy rendering; contacts lists of 200–500 entries will build all rows at once; wrap the parent `Column` in a fixed-height `SizedBox` or use `Expanded` with `shrinkWrap: false` — `contacts_screen.dart:509`

- [ ] [MAJOR] `Image.memory` used without `cacheWidth`/`cacheHeight` — Flutter's image cache stores the full-resolution decoded bitmap for each avatar; with 200 contacts each with a 40×40 display size but a 200×200 source JPEG, memory use is 10× what it should be; add `cacheWidth: _avatarSize.toInt(), cacheHeight: _avatarSize.toInt()` — `contacts_screen.dart:1088`

## create_giveaway_box — cleanup

- [ ] [CRITICAL] random-giveaway "Start Giveaway" button calls `_openBoostLink()` (line 539), which just pops the dialog and calls `engine.openPremiumSubscription(..., ref: 'boosts__channel')` — it does NOT start a random giveaway. The entire random-type flow (fetched `_options`, winners/duration chip selection, `_selectedOptionIndex`) is dead state that is silently discarded; no engine call for random giveaway creation exists in engine_service.dart. Needs a real `launchRandomGiveaway` engine call passing the selected option, `_onlyNewSubscribers`, `_showWinners`, `_untilDate`, and `_prizeController.text` — `create_giveaway_box.dart:131-135,539`

- [ ] [MAJOR] no retry button in `_buildError` (line 203) — once `getGiftCodeOptions` fails the user sees the error and can only close the dialog; `_loadOptions` is never re-invokable from the UI — `create_giveaway_box.dart:203`

- [ ] [MAJOR] `uniqueMonths` and `uniqueUsers` sets are recomputed and re-sorted on every `build()` call (lines 352-353 inside `_buildRandomSection`); should be derived once in `_loadOptions` and stored — `create_giveaway_box.dart:352-353`

## create_group_wizard — cleanup

- [ ] [CRITICAL] `_probeUsernameAvailability()` at line 245 passes the hardcoded string `'preston'` to `checkChannelUsername` as a throwaway probe to trigger `CHANNELS_ADMIN_PUBLIC_TOO_MUCH` / `CHANNEL_PUBLIC_GROUP_NA` errors. If the server responds with any other error (e.g. `FLOOD_WAIT`, rate-limit, network failure) the catch block silently ignores it, leaving `_isPublic` in the wrong state with no feedback. Replace with a random/uuid-like string that is guaranteed syntactically invalid (so it always errors before the username-availability check) or add a dedicated engine method for limit probing. — `create_group_wizard.dart:245`

- [ ] [CRITICAL] `_navigateToChat()` is called **without await** at lines 836 and 940, immediately followed by `Navigator.of(context).pop()`. The `pop()` unmounts the widget, and the retry loop inside `_navigateToChat` has `if (!mounted) return;` guards — so every retry fires once, sees `mounted == false`, and exits. Navigation to the newly created group/channel only succeeds if the chat already exists in the local cache at the instant of the first synchronous check; if not, the chat is silently never opened. Fix: either `await _navigateToChat(...)` before popping, or call `pop()` first and then navigate via the returned `chatId` in a context that doesn't depend on the wizard widget. — `create_group_wizard.dart:836,940,944`

- [ ] [MAJOR] `base64Decode(contact.avatarB64)` is called directly inside `_ContactRow.build()` at line 1684 with no caching. Every `setState` call in the parent (search typing, selecting/deselecting contacts) causes `O(visible_rows)` base64 decodes. Decode once in a helper or cache the `Uint8List` on `ContactInfo`. — `create_group_wizard.dart:1684`

- [ ] [MAJOR] `base64Decode(channel.avatarB64)` is called inside `_PublicLinksLimitBox._buildChannelRow()` at line 2498 with no caching. Every rebuild re-decodes all channel avatars. Same fix as above. — `create_group_wizard.dart:2498`

- [ ] [MAJOR] `_EditPeerTypeBoxState._onUsernameChanged()` (line 2763) validates against `value.trim().toLowerCase()`, but `_save()` at line 2824 reads `_usernameController.text.trim()` (original case) for the API call. If the user types "MyGroup", validation passes against "mygroup" and reports it available, but the save sends "MyGroup". Telegram APIs normalise usernames, but this inconsistency means the round-trip value differs from the validated one. Fix: lowercase the controller text before saving, or match the case used during validation. — `create_group_wizard.dart:2763,2824`

- [ ] [MAJOR] `_usernamesOrderChanged()` (line 2644) returns `true` when either the list order OR an entry's `active` flag changed. At lines 2878–2885 the code calls `reorderChannelUsernames` whenever this method returns true, including cases where only active-state toggles changed and the order is identical. `reorderChannelUsernames` is a separate API call from `toggleChannelUsername` — split the condition: call `reorderChannelUsernames` only when the username order actually changed (names in different positions), separately from the active-toggle loop above it. — `create_group_wizard.dart:2870`

- [ ] [MAJOR] Dead variable `cutout` in `_BottomClipper.getClip()` at line 2014. The variable computes the top portion of the shape (`height - height` rect) but is never used; the `return Path.combine(...)` at line 2017 creates a fresh inline `Path()` for the bottom band instead. The dead variable is confusing and looks like a leftover from an earlier implementation. Remove it. — `create_group_wizard.dart:2014`

- [ ] [MAJOR] "Invite via Link" row in `_buildMemberPickerStep` (line 1424) renders an `InkWell` that is always visually active (hover cursor, ripple) while `_loadingInviteLink` is true, but its `onTap` at line 1426 is a no-op when `_inviteLink.isEmpty`. The button appears clickable but does nothing while the link is loading. Either hide the row until the link is available, or show a disabled/loading state on the button itself. — `create_group_wizard.dart:1424`

## custom_emoji_cache — cleanup

- [ ] [MAJOR] `_retryDelayMs = 0` at line 105 — every failed emoji fetch has a retry window of exactly 0 ms, so the next `request()` call (e.g. next frame rebuild) immediately clears `_failed` and re-queues the fetch. On a broken connection or missing document this becomes a per-frame hammer loop with zero backoff. Change to a real delay (e.g. 5000 ms). — `custom_emoji_cache.dart:105`

- [ ] [MAJOR] `_notifyListeners(changedIds)` is called outside the try/catch at lines 447 and 477 with `changedIds = {}` on the error path — doc-specific listeners for the failed IDs are never called (empty set skips the inner loop), so any widget subscribed only via `addListenerForDoc` will hang in the loading/pending state forever and never learn the fetch failed. Fix: populate `changedIds` with `ids` in the catch block before falling through to `_notifyListeners`. — `custom_emoji_cache.dart:439,469`

- [ ] [MAJOR] `preloadBatch()` (line 223) and `request()` (line 293) guard only on `_thumbs.containsKey(id)`, not `_paths.containsKey(id)`. An emoji that was fetched with a path (SVG vector) but no bitmap thumb passes both guards and is re-queued on every `preloadBatch` call, generating redundant engine calls each time the chat list scrolls. Fix: treat `_paths.containsKey` as "already have preview", matching `hasAnyPreview()` semantics. — `custom_emoji_cache.dart:223,293`

# edit_forum_topic_box — cleanup

- [ ] [CRITICAL] "View Premium" button (line 645–647) calls `_dismissToast()` then `Navigator.of(context).pop()` — pops the *edit topic dialog* instead of navigating to a Premium subscription screen; label promises navigation that never happens — `edit_forum_topic_box.dart:645`

- [ ] [MAJOR] `_onTitleChanged` (line 162) calls `setState(() { … })` unconditionally on every keystroke, even when `_titleError` is already false; this rebuilds the entire dialog tree (all icon grid cells, tab bar, overlays) on every character typed — should guard: `if (_titleError) setState(() => _titleError = false);` — `edit_forum_topic_box.dart:161`

- [ ] [MAJOR] `_buildFallback` in `CustomEmojiTopicIcon` (forum_topic_icon.dart:635) calls `base64Decode(thumbB64)` inside `build()` on every rebuild, allocating a new `Uint8List` each time; the decoded bytes are never cached at state level — should decode once in `_loadData` / `initState` and store in state — `forum_topic_icon.dart:635`

- [ ] [MAJOR] Fly animation `OverlayEntry` (line 298–328) wraps an `AnimatedBuilder` that repaints the entire overlay on every animation frame with no `RepaintBoundary`; wrapping the `Positioned` child in `RepaintBoundary` isolates the repaints — `edit_forum_topic_box.dart:299`

- [ ] [MAJOR] Toast `OverlayEntry` (line 603–666) wraps a `FadeTransition` with no `RepaintBoundary`; every opacity tick repaints the toast subtree through the overlay — wrap the `Center` child in `RepaintBoundary` — `edit_forum_topic_box.dart:609`

- [ ] [MAJOR] `_getEngine()` (with try/catch + `context.read`) is called separately inside `_buildCustomEmojiPreview` (line 516), `_buildEmojiSetGrid` (line 810), and `_buildServerIconGridCell` (line 933) — three independent lookups per build pass; resolve once at the top of `build()` and thread the result through — `edit_forum_topic_box.dart:516`

# edit_mark_box — cleanup

- [ ] [MAJOR] Hardcoded error border color at line 99 — using `0xFFe53935` instead of `p.activeLineFgError` from palette — breaks theme switching — `edit_mark_box.dart:99`
- [ ] [MAJOR] Hardcoded focus border color at line 104 — using `0xFF40a7e3` instead of `p.activeLineFg` from palette — breaks theme switching — `edit_mark_box.dart:104`

# ayu_filter — cleanup

- [ ] [CRITICAL] `_mediaTypeNames[12]` is labelled "animated sticker/dice → TYPE_ANIMATED_STICKER (15)" but `engine_models.dart:1021` says `isInvoice => mediaType == 12`. Invoice messages will be tagged as animated-sticker type (15) in the `<type>` blob, and any actual animated-sticker/dice type will map to the wrong bucket. One of these two type-12 assignments is wrong; reconcile against the Go engine's `MediaType` enum and fix whichever side is wrong. — `ayu_filter.dart:163` / `engine_models.dart:1021`

- [ ] [MAJOR] `HttpClient` is never closed in the error paths of `importFromLink` and `publishFilters` — `client.close()` is only called on the happy path; both `FormatException` and generic `catch` blocks return early without closing the client, leaking sockets. Wrap the client in a try/finally or use a local `close()` call before each return. — `ayu_filter.dart:411-431`, `ayu_filter.dart:433-468`

- [ ] [MAJOR] `_chatFilteredCount` is decremented during LRU eviction: the eviction loop at lines 615-618 calls `_removeCacheEntry` for each evicted key, which decrements the per-chat filtered count. Once all filtered-message cache entries for a chat are evicted, `_hasFilteredMessages` returns false and `filteredMessagesShown()` returns `null` — making the "show filtered messages" toggle vanish from the UI until the messages are re-evaluated. The count should not be decremented on eviction (only on `rebuildCache`); split `_chatFilteredCount` into a "total seen" counter that survives eviction, or simply skip the count decrement in `_removeCacheEntry` when it is called from the eviction path. — `ayu_filter.dart:613-638`

## emoji_panel — cleanup

- [ ] [CRITICAL] `_StickerSetDialogCell._initWebmPlayer` bypasses `_GifPlayerPool` entirely — creates one `Player()` per webm sticker in the dialog with no pool limit. Every other webm path (sticker cell, custom emoji cell) uses `tryAcquire`/`release`. If the dialog shows a large animated set, it spawns unlimited concurrent media_kit players — `emoji_panel.dart:3958`

- [ ] [CRITICAL] "View Set" context menu item silently does nothing for stickers in the Recent section — `_buildSectionSlivers` for recent omits `setShortName` (line 2160-2167), so it defaults to `null`. `_viewStickerSet` then calls `engine.getStickerSetInfo(acc.id, shortName: '')`, which returns null, and the method returns early with no user feedback. The menu item exists but is dead for recent stickers — `emoji_panel.dart:1894, 2159`

- [ ] [CRITICAL] `_StickerPreviewOverlay` has no webm rendering branch — handles TGS (Lottie) and WebP, but silently falls through to thumbnail for `video/webm` stickers. Video stickers show a static thumbnail in the long-press preview instead of animating — `emoji_panel.dart:3712`

- [ ] [CRITICAL] `faveSticker`/unfave does not update `isFaved` on visible sticker cells — after the engine call at line 1892, neither `_recentStickers` nor pack stickers are updated. The next time the context menu opens for that sticker, `sticker.isFaved` still holds the old value so the label "Fave"/"Unfave" is wrong until the tab is fully reloaded — `emoji_panel.dart:1892`

- [ ] [CRITICAL] Dead code: `_TabContent._buildPlaceholder` (lines 629–646) is never called and `_buildTabWidget`'s `placeholderColor` parameter (line 566) is passed in but never used inside the function body — `emoji_panel.dart:566, 629`

- [ ] [MAJOR] Every tab switch destroys and recreates all tab widget elements. `_TabContent.build` returns a bare `_EmojiTab`/`_StickerTab`/`_GifTab` when `slideProgress >= 1.0`, but a `LayoutBuilder → Stack → SizedBox` tree when animating. The structural change causes Flutter to unmatch and teardown the existing element tree, calling `deactivate` (which resets `_loaded = false`) and `dispose`, then rebuild fresh on animation start AND again at animation end. Result: every tab switch triggers two full element lifecycle cycles and a fresh API call for the tab — `emoji_panel.dart:579`

- [ ] [MAJOR] `_stickerFileCache` is instance state on `_StickerTabState` (line 1654), which is destroyed on every tab switch due to the above element teardown. Every time the user returns to the sticker tab, all previously fetched sticker file data is gone and must be re-fetched from the engine — `emoji_panel.dart:1654`

- [ ] [MAJOR] No `RepaintBoundary` around individual animated emoji/sticker cells (`_EmojiCell`, `_CustomEmojiCell`, `_StickerCell`). Each cell has an `AnimatedContainer` that updates on hover. Without isolation, hovering over any cell can trigger repaints of all neighbouring cells in the grid row — `emoji_panel.dart:1391, 1560, 2587`

# emoji_status_widget — audit

## Issues Found

- [ ] [MAJOR] Missing cacheWidth/cacheHeight on thumbnail Image.memory() at line 272 — inconsistent with webp handling (line 209-210) — The `cs` variable is computed on line 192 for scaled frame size, but only used in the webp branch. The thumbnail fallback should also cache with same dimensions for consistent performance. Pass `cs` to `_buildThumbOrFallback()` and apply it. — `emoji_status_widget.dart:268-279`

- [ ] [MAJOR] Missing cacheWidth/cacheHeight on userpic Image.file() at line 243-249 — userpic avatar isn't cached at appropriate resolution like emoji images are — `emoji_status_widget.dart:243-249`

## Clean Areas

- ✅ Lifecycle management: acquire/release properly balanced in initState/dispose/didUpdateWidget
- ✅ Animation controller: properly disposed and looped
- ✅ Engine wiring: EngineService.context.read() calls at lines 135, 141 are correct
- ✅ Cache listener: registered in initState, removed in dispose
- ✅ Error handling: proper error builders on Image/Lottie widgets
- ✅ State parsing: _parseEmojiStatusId() handles all three formats (collectible/userpic/regular)
- ✅ Color parsing: _parseHexColor() safely handles invalid input
- ✅ Power saving: conditional rendering respects power saving mode
- ✅ Shader masking: RadialGradient collectible effects properly applied

## filter_column — cleanup

- [ ] [MAJOR] `_onDropHighlightChanged` calls `setState(() {})` unconditionally (line 170), triggering a full `FilterColumn` rebuild every time `dropHighlightIndex` changes — this fires on every pointer-move during a drag-over-folder operation (via `DragTarget.onMove` → `ValueNotifier`). The full rebuild includes the hamburger button, all-chats button, AND all folder tabs. Scope with a `ValueListenableBuilder` wrapping just the folder `Column` to limit redraws to the scrollable list — `filter_column.dart:170`

## folders_settings_screen — cleanup

- [ ] [CRITICAL] Tag color selection is silently dropped on save — `_colorIndex` is correctly tracked in `_EditFilterBoxState` and included in the returned `FolderInfo`, but `ChatState.editFolder()` and `ChatState.createFolder()` have no `colorIndex` parameter, and `EngineService.editFolder`/`createFolder` don't include it in their JSON payloads. The tag color UI is fully visual but persists nothing to the engine. Fix: add `colorIndex` param through the entire call chain (engine_service → chat_state → callers at lines 284 and 304) — `folders_settings_screen.dart:284,304` · `engine_service.dart:880,821`

- [ ] [CRITICAL] Folder icon selection is silently dropped on save — `_selectedIconName` / `_effectiveIconName` is tracked in state but `_onSave()` at line 1766 never sets `emoticon` on the returned `FolderInfo` (field defaults to `''`). `EngineService.editFolder()` and `createFolder()` also have no `emoticon` field in their JSON payloads. The folder icon picker UI is a complete stub. Fix: map `_effectiveIconName` via `_kFilterIconEmoji` to the emoji string, pass as `emoticon` in `FolderInfo` and through the engine call chain — `folders_settings_screen.dart:1766` · `engine_service.dart:880,821`

- [ ] [MAJOR] `_SelectedChatsPreview` uses `chatState.chats` (all accounts) at line 4349 — resolves chatIds to names from the global all-accounts list instead of `chatsForAccount(accountId)`. In multi-account setups a chatId from account A could match a chat from account B. The include/exclude type pickers correctly use `chatsForAccount(accountId)` at lines 1649 and 1679. Fix: pass `accountId` into `_SelectedChatsPreview` and resolve via `chatState.chatsForAccount(accountId)` — `folders_settings_screen.dart:4349`

- [ ] [MAJOR] Synchronous file I/O in `build()` at line 4296 — `_ChatToggleRow.build()` calls `File(chat.avatarPath).existsSync()` which is a blocking disk access on every widget rebuild. This runs on every frame for every visible row while the user scrolls the chat picker. Fix: cache the existence check outside of build (e.g. resolve avatar path once in the parent, or use an `Image.file` with an `errorBuilder` instead of pre-checking) — `folders_settings_screen.dart:4296`

- [ ] [MAJOR] `Image.network` missing `cacheWidth`/`cacheHeight` in `_PeerAvatar` at line 3006 — loads full-resolution images decoded into memory for 44×44 containers with no downscaling hint. Fix: add `cacheWidth: 88, cacheHeight: 88` (2× for HiDPI) — `folders_settings_screen.dart:3006`

- [ ] [MAJOR] Dead ternary always evaluates to `null` at line 3480 — `color: widget.isSelected ? null : (_hovering ? null : null)` — both branches of the inner ternary are `null`, making the entire expression a no-op. Delete the `color` parameter entirely — `folders_settings_screen.dart:3480`

## forum_topic_icon — cleanup

- [ ] [MAJOR] `_BubbleIconPainter.paint()` allocates `Float64List`, two `Path.transform()` calls, three `Paint` objects with gradient shaders, and a `TextPainter` on every repaint — all should be cached per `(targetSize, palette, letter)` and reused until `shouldRepaint` triggers — `forum_topic_icon.dart:280-336`
- [ ] [MAJOR] `_GeneralIconPainter.paint()` allocates a new `Float64List` and calls `Path.transform()` every repaint — the scaled path should be cached per `targetSize` — `forum_topic_icon.dart:399-406`
- [ ] [MAJOR] WebM temp file path `topic_icon_${widget.documentId}.webm` is not unique per instance — two `CustomEmojiTopicIcon` widgets with the same `documentId` mounted simultaneously (e.g. same topic visible twice) will race-write the same file, corrupting the one already being played — use a unique suffix (e.g. `_${identityHashCode(this)}`) — `forum_topic_icon.dart:548`
- [ ] [MAJOR] `Uint8List.fromList(bytes)` in `_buildFallback` is a redundant copy — `base64Decode` already returns `Uint8List`, pass it directly — `forum_topic_icon.dart:640`
- [ ] [MAJOR] `Lottie.memory` and `Video` widgets are animated but have no `RepaintBoundary` wrapper — their per-frame repaints propagate into ancestor layers unnecessarily — wrap each animated branch in `RepaintBoundary` — `forum_topic_icon.dart:584-627`

## ghost_settings_page — cleanup

- [ ] [CRITICAL] `localPremium` toggle is dead state — flag is stored and persisted but never read anywhere outside `app_state.dart` getters/setters. No widget checks `appState.localPremium` to unlock premium UI features, and `updateConfig()` has no `localPremium` parameter so the engine never learns about it. Toggling the switch does nothing functional. — `ghost_settings_page.dart:286`, `app_state.dart:389,753,1367`

- [ ] [CRITICAL] `disableAds` toggle is dead state — same problem as above. The flag is stored and persisted but never consumed to actually filter or suppress sponsored messages anywhere in the codebase. Toggling the switch does nothing functional. — `ghost_settings_page.dart:293`, `app_state.dart:390,754,1374`

- [ ] [MAJOR] `File.existsSync()` called inside `build()` at `_AccountAvatar` — synchronous disk I/O on the UI thread, executed every time the account picker popup opens and for every account in the list. Must be replaced with an async check (e.g. cache the result in state, or use a `FutureBuilder`/`didChangeDependencies` approach). — `ghost_settings_page.dart:717`

- [ ] [MAJOR] `Image.file` at line 719 has no `cacheWidth`/`cacheHeight` — the image is decoded at its full native resolution (potentially a full-size avatar photo) and only scaled down in layout to 30×30. Add `cacheWidth: 60, cacheHeight: 60` (2× for HiDPI) to decode at the display size. — `ghost_settings_page.dart:719`

## hamburger_drawer — cleanup

- [ ] [CRITICAL] Status line always shows hardcoded "Uniclient Preferences" — `_buildStatusLine` receives `AccountInfo? account` but ignores `account.phone` / `account.username` entirely; spec §3 shows phone number / username below the display name — `hamburger_drawer.dart:1051`

- [ ] [CRITICAL] Menu bot `requestBotWebView` call uses `_activeChat` as context — if no chat is open when the drawer is visible, `_activeChat` is null and `requestBotWebView` returns `''` immediately (chat_state.dart:1701-1702), so bot web view silently does nothing; drawer bots need to open via the bot's own peer ID, not the active chat — `hamburger_drawer.dart:207`

- [ ] [CRITICAL] `botUsername: ''` hardcoded when opening menu bot WebAppPanel — `MenuBotInfo` has no `username` field, so the bot's username is never passed to `WebAppPanelData`; if `WebAppPanel` displays or uses `botUsername` anywhere it will always be blank — `hamburger_drawer.dart:215`

- [ ] [MAJOR] Missing `RepaintBoundary` on `_SnowflakeOverlay` — the snowflake `AnimationController` repeats every 10 s at full frame rate; without a boundary, every animation tick invalidates and repaints the entire 274×134 profile cover Stack including avatar, text, and badge widgets — `hamburger_drawer.dart:799`

- [ ] [MAJOR] `ctx.watch<AppState>()` in Profile Cover avatar `Builder` watches the entire AppState just to read `avatarCorners`; any unrelated AppState change (account list update, ghost mode toggle, etc.) rebuilds the avatar — use `Selector<AppState, double>` — `hamburger_drawer.dart:812`

- [ ] [MAJOR] Chevron `Builder` at line 934 calls `ctx.watch<AppState>()` + `ctx.watch<ChatState>()` — iterates all accounts and sums unread counts on every ChatState notification (i.e. every incoming message); should use `Selector` that only triggers when the collapsed-unread aggregate actually changes — `hamburger_drawer.dart:935-936`

- [ ] [MAJOR] `_AccountRow` avatar `Builder` calls `ctx.watch<AppState>()` per account row to read `avatarCorners`; with N accounts this creates N full-AppState listeners, each rebuilding on any AppState change — use `Selector<AppState, double>` — `hamburger_drawer.dart:1499`

- [ ] [MAJOR] `Image.file` for bot menu icon has no `cacheWidth`/`cacheHeight` — the image is decoded at full resolution (potentially 512×512+) then scaled to 24×24 on every drawer open; pass `cacheWidth: 48, cacheHeight: 48` (2× logical pixels) — `hamburger_drawer.dart:1695`

- [ ] [MAJOR] `FileImage` for profile-cover avatar (48×48) and account-row avatars (26×26) has no resize hint — wrap with `ResizeImage(FileImage(File(path)), width: 96, height: 96)` / `ResizeImage(FileImage(File(path)), width: 52, height: 52)` to avoid decoding full-res avatars on every frame — `hamburger_drawer.dart:821`, `hamburger_drawer.dart:1509`

## info_panel — cleanup
- [ ] [CRITICAL] `File.readAsBytesSync()` called inside `build()` — blocks UI thread on every rebuild of `_ChatInfoPage`; load bytes async in `initState`/`didUpdateWidget` and store in state — `info_panel.dart:2692`
- [ ] [CRITICAL] `mute_forever` menu item hits `_ => 0` branch (seconds=0), then calls `data.onTap?.call()` which is the mute toggle — permanently muted chats get unmuted instead; add explicit `'mute_forever'` case that calls `muteChat` with no duration or a sentinel value for permanent mute — `info_panel.dart:1131`
- [ ] [CRITICAL] `_PollListItem` renders as plain `Padding(child: Row(...))` with no `InkWell`/`onTap` — polls cannot be tapped to navigate to the originating message, unlike every other media list type (`_FileListItem`, `_AudioListItem`, `_VoiceListItem`, `_LinkListItem`, `_RoundListItem`); wrap in `InkWell` and wire navigation — `info_panel.dart:6683`
- [ ] [MAJOR] `_daySchedule(d)` called twice per row in `_BusinessHoursWidget.build()` — once for `Text` content and once for the color guard; cache in a local variable — `info_panel.dart:4029`
- [ ] [MAJOR] `_sortedMembers()` allocates a full list copy and O(n log n) sorts it on every `build()` call from `_filteredMembers()`; cache the sorted list and invalidate in `didUpdateWidget` when `widget.members` changes — `info_panel.dart:7257`
- [ ] [MAJOR] `getCommonChats` called twice: `_loadCommonGroups()` fetches the full list but discards it (stores only the count), then `_showCommonGroupsDialog()` fetches from scratch with identical args; store the list from the first call and reuse it — affects both `_UserProfilePageState` (~line 2866) and `_ChatDetailsState` (~line 3670) — `info_panel.dart:2866`
- [ ] [MAJOR] `_MembersSectionState` triggers a full `getChatMembers` API call for every service message received in the chat; most service messages (pin notifications, etc.) don't affect membership; narrow the trigger to join/leave/kick/invite service message types — `info_panel.dart:7143`

## input_dialogs — cleanup

- [ ] [CRITICAL] `_isValidPhone` has hardcoded test-DC bypasses at lines 613–618: `digits == '333'` returns true, and `digits.startsWith('42')` with lengths 2/5/6 or equal to `'4242'` also returns true — these are Telegram test-server phone shortcuts that were never removed; they silently let invalid phones pass validation in production — `input_dialogs.dart:613`

- [ ] [CRITICAL] `chatState.loadChats()` at line 698 is fire-and-forget (not awaited) before `chatState.openChatById(userId)` at line 699 — the chat list hasn't refreshed yet when `openChatById` runs, so the newly-added contact's chat may not be in state and the open call silently does nothing — `input_dialogs.dart:698`

- [ ] [CRITICAL] `_showDurationPicker` passes `RelativeRect.fromLTRB(200, 300, 200, 300)` as the popup menu position (line 1907) — a hardcoded zero-size rect at (200, 300) that is not anchored to the "Limit Duration" row; the menu always spawns at the same fixed screen coordinate regardless of viewport size or scroll position — `input_dialogs.dart:1907`

- [ ] [CRITICAL] `_pickOptionMedia` passes the same hardcoded `RelativeRect.fromLTRB(200, 300, 200, 300)` at line 1954 — the "Choose Photo / File / Remove" context menu always appears at a fixed point rather than near the attachment icon that was tapped — `input_dialogs.dart:1954`

- [ ] [MAJOR] `_UsernameBoxContentState._save` calls `reorderAccountUsernames` unconditionally whenever `_additionalUsernames` is non-empty (lines 297–305), even when the user changed nothing but the primary username or a toggle — sends a redundant API call on every save; should only call if the list order actually changed relative to the loaded order — `input_dialogs.dart:297`

- [ ] [MAJOR] `_showCustomUsageLimit`'s `onConfirm` callback (line 1368–1371, triggered by the Enter key via `TelegramBox`) only checks `val > 0`, missing the `val <= 200000` upper-bound guard that the explicit "Save" button enforces at line 1385 — pressing Enter submits an arbitrarily large limit — `input_dialogs.dart:1368`

- [ ] [MAJOR] `_buildOptionRow` uses `ValueKey(i)` (the loop index) as the widget key in a `ReorderableListView` (line 2329) — after any reorder or removal, Flutter matches widgets by key and the shifted indices cause wrong `TextEditingController`s to be wired to the wrong fields; should use a stable per-option identity (e.g. the controller's object identity or a generated UUID) — `input_dialogs.dart:2329`

- [ ] [MAJOR] `_PollEmojiSuggestionPanel` hardcodes raw hex colors for background, hover, and border (lines 2498–2500) instead of reading from `context.palette` — these colours will not update when the user switches themes and are already inconsistent with the palette values used everywhere else in the file — `input_dialogs.dart:2498`

# emoji_data — cleanup

- [ ] [CRITICAL] `EmojiKeywords.instance.setCacheDir(cacheDir)` is never called in `main.dart` — `_cacheDir` is always `null`, so `_writeCacheToDisk` (line 2822) is dead code (guarded by `if (_cacheDir != null)` at line 2790) and `loadCacheFromDisk` (line 2831) returns immediately at line 2832. Emoji keyword server data is never persisted to disk; every cold start re-fetches all keywords from the server. Fix: add `EmojiKeywords.instance.setCacheDir(cacheDir);` in `main.dart` alongside the `SpoilerAnimationManager.setCacheDir(cacheDir)` call at line 298 — `emoji_data.dart:2757`, `main.dart:298`

- [ ] [CRITICAL] `EmojiKeywords.instance.loadCacheFromDisk()` is never called anywhere — even if `setCacheDir` is fixed, the cached keyword JSON files on disk are never read back into memory on startup. Users always begin with the legacy fallback only, forcing a full server fetch every session. Fix: call `EmojiKeywords.instance.loadCacheFromDisk()` in `main.dart` after `setCacheDir` and before `startAutoRefresh` — `emoji_data.dart:2831`, `main.dart:300`

- [ ] [MAJOR] `void init() {}` at line 2749 is a no-op stub — called from `main.dart:300` but does nothing. All actual initialization is scattered across three separate `main.dart` calls (`loadState`, `setSaveCallback`, `setCacheDir`). Either fill `init()` to consolidate startup logic (setCacheDir + loadCacheFromDisk + loadState) or delete it — `emoji_data.dart:2749`

- [ ] [MAJOR] `maxQueryLength()` (line 2768) iterates all 2669 legacy `EmojiEntry` objects and their keywords on every call — called from `search()` on every keystroke. `_LangPack` caches `maxKeyLength` as a field, but the legacy list max is recomputed from scratch each time. Fix: compute `_legacyMaxKeyLength` once (e.g. as a `late final int` initialized from `kEmojiSuggestions` at field init time) and return `max(pack.maxKeyLength, _legacyMaxKeyLength)` instead — `emoji_data.dart:2768`

# instant_view — cleanup

- [ ] [CRITICAL] `_InstantViewPageState._error` is never set to a non-null value — the catch block in `_navigateTo` (lines 118–122) calls `_openExternal` and returns silently, never assigning `_error`; the `_buildError` branch at line 247 is therefore dead code and the error UI never renders — `instant_view.dart:45,118,247`

- [ ] [CRITICAL] `TapGestureRecognizer` objects created in `_richTextToSpan` for the `url`, `email`, and `phone` cases (lines 1583, 1600, 1634) are allocated on every call but never disposed — `_IvBlock` is a `StatelessWidget` with no `dispose()`, so each rebuild leaks all recognizers from the previous pass; pages with many links will accumulate unbounded recognizer allocations — `instant_view.dart:1583,1600,1634`

- [ ] [MAJOR] `_IvAudioBlock` subscribes to `player.stream.position` and calls `setState` on every tick (line 2130), rebuilding the entire audio widget at the stream's emission rate (typically 8–30 Hz) for the duration of playback — the progress bar is the only thing that needs updating; split it into a separate widget or use `StreamBuilder` scoped to just the progress row — `instant_view.dart:2129`

- [ ] [MAJOR] `_buildHighlightedCode` runs a full regex pass over the entire code string on every `build()` call of the `_IvBlock` `StatelessWidget` (line 522) — any parent rebuild (zoom change, scroll, theme toggle) re-highlights every visible code block; memoize the result in a stateful wrapper or cache spans by text hash — `instant_view.dart:522`

- [ ] [MAJOR] `_IvSlideshowBlock` uses a hardcoded `SizedBox(height: 300)` (line 2701) regardless of item aspect ratios — portrait photos are cropped, landscape photos get extra dead space; height should be derived from the first item's aspect ratio or from `LayoutBuilder` constraints — `instant_view.dart:2701`

# keyboard_shortcuts — cleanup

- [ ] [CRITICAL] `ctrl+R` is bound to BOTH `readChat` AND `recordVoice` in `_defaultBindings` (lines 864–868). The `readChat` handler always returns `true` (line 1139), so `dispatch()` exits before `recordVoice` is ever tried — `recordVoice` keyboard shortcut is permanently dead. Fix: assign `recordVoice` a distinct binding (e.g. `ctrl+shift+V` or similar) — `keyboard_shortcuts.dart:864`

- [ ] [CRITICAL] `ctrl+1` through `ctrl+8` are each bound to TWO commands: a folder command (`allChats`/`folder1-6`/`lastFolder`) AND a pinned-chat command (`pinnedChat1-8`), lines 884–954. Folder bindings appear first in `_bindings`, so their handlers fire first. `requestSwitchFolderByIndex` returns true when a folder exists, silently eating the key and preventing any pinned-chat shortcut from ever dispatching. Pinned-chat shortcuts ctrl+1–8 are dead for users with folders. Fix: use non-overlapping default bindings (e.g. `alt+1`–`alt+8` for pinned chats) — `keyboard_shortcuts.dart:884`

- [ ] [CRITICAL] Config directory is never created before writing. `_writeDefaultsFile()` (line 528) and `_writeCustomTemplate()` (line 599) call `File.writeAsStringSync()` directly; on a fresh install the directory doesn't exist, `FileSystemException` is silently swallowed, and all custom shortcut persistence is permanently broken. Fix: call `Directory(_configDir).createSync(recursive: true)` before any file write — `keyboard_shortcuts.dart:516`

- [ ] [CRITICAL] `_requestController` is a `final` field initialized once at class declaration (line 415). `dispose()` closes it (line 758) but `init()` never recreates it. If `ShortcutListener` is ever disposed and remounted (hot restart, conditional display, auth screen transitions), `dispatch()` at line 635 calls `_requestController.add(command)` on a closed stream → throws `Bad state: Stream is closed`. Fix: move `StreamController` creation into `init()` (close+replace if already set) — `keyboard_shortcuts.dart:415`

- [ ] [CRITICAL] `ShortcutCommand.mediaViewerVideoFullscreen` is declared (line 78), scoped to `ShortcutScope.mediaViewer` (line 196), but has NO default binding in `_defaultBindings` and NO handler registered in `initState()`. The command can never be triggered and does nothing. Either add a binding + handler (e.g. `F` key when media viewer is open, wired to `MediaViewer.toggleFullscreenRequest`) or remove it — `keyboard_shortcuts.dart:78`

- [ ] [MAJOR] `isComposeFieldFocusedCallback` (lines 1089–1095) returns `true` for ANY `EditableText` in the widget tree (search bar, settings fields, dialogs, etc.), not just the compose field. This means compose-scoped shortcuts (`formatBold`, `formatItalic`, `formatLink`, etc.) fire whenever any text field has focus. Fix: check that the focused context is an ancestor of the specific compose `EditableText` (e.g. check for a `ComposeBar` ancestor widget, or use a dedicated `FocusNode` set only when compose is active) — `keyboard_shortcuts.dart:1089`

- [ ] [MAJOR] `_findCommands` (lines 690–711) does a full linear scan of `_bindings` on every `KeyDownEvent` and `KeyRepeatEvent`. With 50+ bindings this is O(n) per keypress. Fix: build a `Map<(LogicalKeyboardKey, bool ctrl, bool shift, bool alt, bool meta), List<ShortcutCommand>>` in `init()` / `replaceAllBindings()` / `addBinding()` / `removeBindingsFor()` for O(1) lookup — `keyboard_shortcuts.dart:690`

- [ ] [MAJOR] `formatStrike` has a registered handler (line 1343) and a scope/name entry but NO default binding in `_defaultBindings` (omitted entirely from lines 829–1023). In Telegram Desktop the default is `Ctrl+Shift+X`. Users cannot strikethrough by keyboard unless they manually add a custom binding — `keyboard_shortcuts.dart:829`

# language_box — cleanup

- [ ] [MAJOR] `shrinkWrap: true` on main `ListView.builder` at line 484 — forces Flutter to measure all ~400 language items to compute intrinsic height before clipping at 492px; kills lazy rendering entirely. Remove `shrinkWrap` — the `Flexible` + `ConstrainedBox(maxHeight: 492)` already bounds the height — `language_box.dart:484`

- [ ] [MAJOR] `shrinkWrap: true` on `_SkipLanguagesEditor`'s `ListView.builder` at line 990 — same problem; lays out all ~90 translation-language items eagerly. Same fix: remove `shrinkWrap`, rely on `Flexible` + `maxHeight: 320` — `language_box.dart:990`

- [ ] [MAJOR] `context.watch<AppState>()` inside `_languageRow` at line 559, called from `ListView.builder`'s `itemBuilder` — every visible row registers its own AppState listener. When AppState fires (e.g. after `addRecentLanguage` selects a language), all visible rows rebuild individually on top of the parent rebuild already triggered by the parent's `watch` at line 268. Change to `context.read<AppState>()` — `language_box.dart:559`

- [ ] [MAJOR] `_sortedFilteredLangs()` called directly in `_SkipLanguagesEditorState.build()` at line 944 — allocates two filtered sublists (`selectedLangs` + `unselectedLangs`) on every build frame. Result must be cached in a field, invalidated only when `_searchQuery` or `_selected` changes — `language_box.dart:916`

- [ ] [MAJOR] `beta` field populated from engine at line 65 but never rendered — AyuGram shows a "BETA" label next to beta-flag language entries in the list. The field is parsed into `_LangEntry.beta` (line 1083) but `_languageRow` never reads it. Add a beta badge/label to the row for entries where `lang.beta == true` — `language_box.dart:65`

## media_viewer — cleanup

- [ ] [CRITICAL] `_handleAreaUrl` calls `Process.run('xdg-open', [u])` — Linux only, silently fails on macOS/Windows. `url_launcher.launchUrl()` is already imported and used everywhere else in the file. — `media_viewer.dart:6515`

- [ ] [CRITICAL] `_deleteMedia` calls `chatState.deleteMessage` then just decrements `_currentIndex`, but `widget.mediaMessages` is a final snapshot list — the deleted item stays in the list. After decrement the user can navigate forward back into the deleted slot and see stale/broken media. Gallery strip still shows the deleted thumbnail. — `media_viewer.dart:2893`

- [ ] [CRITICAL] Custom emoji reaction areas (`isCustomEmoji = emoji.startsWith('custom:')`) in `_ReactionArea` render a generic `Icons.emoji_emotions` placeholder instead of the actual sticker image. The reaction can still be sent but the bubble shows a grey icon. — `media_viewer.dart:5543`

- [ ] [MAJOR] `_buildCaptionSpans` creates `TapGestureRecognizer()` instances inline for `text_url`, `url`, and `mention` entities on every call — they are never disposed. `_buildCaptionRichText` → `_buildCaption` is called from `build()`, which is triggered by the video position stream listener (`setState(() => _position = pos)`) at ~30fps during playback. Recognizers accumulate indefinitely on captioned videos. — `media_viewer.dart:3472`

- [ ] [MAJOR] `_shareAtTime` (line 3016) and `_forwardMedia` (line 2886) always produce `https://t.me/c/$chatId/$msgId` — the private-channel link format. For public channels the correct format is `t.me/@username/msgId`; for regular groups and DMs there is no public link. Both actions silently produce broken/wrong URLs for any non-private-channel context. — `media_viewer.dart:3016`

- [ ] [MAJOR] `_middleElide` runs a binary search that allocates and lays out multiple `TextPainter` instances on every call. It is called from `_buildFooter` which is called from `build()`. Every `setState` (including video position ticks) triggers this O(log n) measurement work. Cache the result or move to a `LayoutBuilder`-aware approach. — `media_viewer.dart:2533`

## message_bubble — cleanup

- [ ] [CRITICAL] Hardcoded fallback `'User'` in `_showWhoReactedMenu` reactor name display — reactor with no name shows fake "User" label instead of empty/omitted — `message_bubble.dart:386,413`
- [ ] [CRITICAL] Hardcoded fallback `'Contact'` in `_ContactIndicator.build()` — `fullName.isNotEmpty ? fullName : 'Contact'` shows fake name when contact has no display name — `message_bubble.dart:5252`
- [ ] [CRITICAL] `_cachedReactions` and `_loadingReactions` are static Maps on `_MessageBubbleState` with no eviction — accumulate entries for every message across all chats and sessions, unbounded memory growth — `message_bubble.dart:211-213`
- [ ] [CRITICAL] `_extendedPalette` is a static Map on `_MessageBubbleState` with no eviction — grows with every unique peer color id loaded via `loadPeerColors`, never cleared — `message_bubble.dart:1274`
- [ ] [CRITICAL] `_StickerCache._progress` and `_StickerCache._webmPositions` are unbounded static Maps — only `_compositions` has the 30-entry LRU cap; these two grow without limit as new stickers are seen — `message_bubble.dart:4015-4016`
- [ ] [MAJOR] `_parseEntities()` (JSON decode + entity construction) called on every `build()` — `_cachedEntities` field exists but is only consulted in `_revealAllSpoilers()`, not used to skip re-parsing in the main build path — `message_bubble.dart:6999`
- [ ] [MAJOR] `TapGestureRecognizer` objects are disposed and recreated on every `build()` call inside `_RichMessageTextState` — expensive for messages with many links, mentions, or hashtags — `message_bubble.dart:6993-6997`
- [ ] [MAJOR] `_emojiByCategory` is a non-static instance getter on `_ReactionEmojiOverlayState` that reconstructs a large nested list of emoji arrays on every access — should be a static const — `message_bubble.dart:1806`
- [ ] [MAJOR] Missing `RepaintBoundary` around continuously-animating widgets: `_PollFireworks`, `_TgsStickerPlayer`, `_WebmStickerPlayer`, `_ReactionStrip` — all animate on every frame and force full parent subtree repaints — `message_bubble.dart:8592,4039,4141,1546`

## my_profile_page — cleanup

- [ ] [CRITICAL] `_getClipboardImage` wl-paste path decodes binary PNG stdout as `String` then calls `.codeUnits` (line 1269–1271) — produces garbage UTF-16 code units instead of raw bytes; clipboard paste is always broken on Wayland Linux — `my_profile_page.dart:1268`

- [ ] [CRITICAL] `_getClipboardImage` xclip path checks `result.stdout is List<int>` (line 1277) but `Process.run` returns `String` stdout by default (no `stdoutEncoding: null` passed) — this check is always false, so xclip clipboard paste always returns `null` on X11 — `my_profile_page.dart:1274`
  - Fix for both: pass `stdoutEncoding: null` to `Process.run` so stdout comes back as `List<int>`, then cast directly

- [ ] [CRITICAL] `_emojiPlaceholder` returns a spinning `CircularProgressIndicator` (lines 2145–2154) as a permanent fallback when an emoji thumbnail is absent — but this is called only after `_loadingEmojis == false`, so the spinner never stops; should show a static fallback (e.g. small icon using the emoji ID) — `my_profile_page.dart:2145`

- [ ] [CRITICAL] Avatar context menu (`_showAvatarMenu`, lines 1119–1175) offers View / Upload / From Clipboard / Set Emoji but has no "Remove Photo" / "Delete Photo" option — once a photo is set there is no way to remove it; Telegram Desktop has this option — `my_profile_page.dart:1119`

- [ ] [CRITICAL] `_SettingsAccountRow._avatarFallback` (lines 2709–2722) always uses `CircleAvatar` (forced circular shape), ignoring `AppState.avatarCorners` — every other avatar in the file (`_ProfilePhotoAreaState._clipAvatar`, `_ProfilePhotoAreaState._avatarFallback`) reads `appState.avatarCorners` and applies the correct radius; account-list avatars are always circular regardless of user's corner setting — `my_profile_page.dart:2709`

- [ ] [MAJOR] `Image.file` in `_ProfilePhotoArea` (line 1029) and `_SettingsAccountRow` (line 2634) has no `cacheWidth`/`cacheHeight` — Flutter decodes avatars at full disk resolution; should set `cacheWidth: 200, cacheHeight: 200` for the 100 px avatar and `cacheWidth: 60, cacheHeight: 60` for the 30 px account-row avatars — `my_profile_page.dart:1029`, `my_profile_page.dart:2634`

- [ ] [MAJOR] `_openProfilePhotoViewer` fetches profile photos in a serial `for` loop (lines 1357–1364) — up to 20 sequential `await engine.getUserPhotoAtIndex(...)` calls before the viewer opens; should use `Future.wait` or a batch engine method — `my_profile_page.dart:1357`

- [ ] [MAJOR] `_BioInputState._handleEmojiKey` intercepts `arrowLeft`/`arrowRight` keys and returns `KeyEventResult.handled` when emoji autocomplete is open (lines 772–782) — these keys never reach the `TextField`, so the cursor cannot be moved while suggestions are visible; only Tab/Enter/Escape should be consumed; arrow keys should navigate suggestions but also fall through to the text field — `my_profile_page.dart:772`

- [ ] [MAJOR] Double rebuild per bio keystroke: parent `_onBioChanged` calls `setState(() {})` unconditionally (line 311), which rebuilds `_MyProfilePageState` and causes `_BioInput` to rebuild; `_checkEmojiAutocomplete()` then independently calls `setState` inside `_BioInputState` if suggestions change — two separate rebuild passes of `_BioInputState` per keystroke; the parent setState is only needed to update the character counter, which could be driven by a `ValueListenableBuilder` on the controller instead — `my_profile_page.dart:311`

## notification_popup — cleanup

- [ ] [CRITICAL] `_onHoverExit` sets `popup.hovered = false` but never calls `setState` — `AnimatedOpacity(opacity: popup.hovered ? 1.0 : 0.0)` doesn't rebuild, so the reply button stays at opacity 1.0 for ~3 seconds after mouse exit until `_startSlowHide` eventually calls `setState`. Fix: add `setState(() { popup.hovered = false; });` at the start of `_onHoverExit` — `notification_popup.dart:269`

- [ ] [CRITICAL] `onReplySend` is nullable but `shouldHideReplyButton` never checks it — if a caller omits `onReplySend`, the reply button still appears for eligible messages, user types a reply and hits send, `widget.onReplySend?.call(...)` silently drops the text, and the popup dismisses (convincing the user it worked). Fix: hide the reply button when `widget.onReplySend == null`, or make the param required — `notification_popup.dart:81, 324, 577 (notification_types.dart)`

- [ ] [MAJOR] `_onUpdateDisplay` ignores its `item` parameter entirely and calls `setState(() {})` unconditionally. `DefaultManager.updateAll()` calls this once per active notification, so with N popups you get N separate full-overlay rebuilds. Should either diff the incoming item against its popup state and skip if unchanged, or at minimum call `setState` once after the loop, not once per item — `notification_popup.dart:158`

- [ ] [MAJOR] `Image.file` in `_Avatar.build` has no `cacheWidth`/`cacheHeight` — the image is decoded at full file resolution and scaled to 62×62 at paint time. Add `cacheWidth: (_photoSize * MediaQuery.devicePixelRatioOf(context)).round()` (or a hardcoded `cacheWidth: 124`) to decode at display size — `notification_popup.dart:741`

- [ ] [MAJOR] `_buildBodySpan` and `_buildEntitySpans` are called inside `_NotificationPopupWidget.build()` on every rebuild. Entity building involves list sorting + repeated `text.substring` calls. The popup overlay rebuilds constantly during position/opacity animations. Cache the result in `_PopupState` (keyed on `item.data` identity) so it is only recomputed when the notification data actually changes — `notification_popup.dart:617, 670, 685`

- [ ] [MAJOR] No `RepaintBoundary` around each `_NotificationPopupWidget`. `AnimatedPositioned` and `AnimatedOpacity` on one popup drive repaints of the entire `Stack`, including all sibling popups. Wrap each `_NotificationPopupWidget` in a `RepaintBoundary` so only the animating popup repaints — `notification_popup.dart:426`

## notifications_settings_screen — cleanup

- [ ] [CRITICAL] `_showCustomDurationInput` custom mute duration is completely non-functional — two bugs: (1) `parentContext.findAncestorStateOfType<_NotificationTypeSubPageState>()` is called from inside a dialog's `BuildContext`; Flutter dialogs live in the Navigator overlay, not in the calling page's widget subtree, so this always returns `null` and the `if (pageState != null)` guard is always false; (2) even if the ancestor were found, `_muteForDuration(seconds)` is never called — only `setState(() => pageState._enabled = false)` is set, so the engine never receives the mute request. Compare with `_showMuteDurationPicker` (same class) which correctly calls `_muteForDuration(seconds)`. Fix: remove `findAncestorStateOfType`, pass a callback from the subpage to the dialog, and add the `_muteForDuration(seconds)` call — `notifications_settings_screen.dart:2728`

- [ ] [MAJOR] `Listenable.merge(_barControllers)` is created inline as the `animation:` argument to `AnimatedBuilder` — a new `_MergedListenable` object is allocated on every `build()` call, which happens on every mouse hover (each `_hoverCorner` change calls `setState`). This causes the `AnimatedBuilder` to unsubscribe and resubscribe on every hover event. Store the merged listenable as a `late final` field, initialized in `initState` — `notifications_settings_screen.dart:1087`

# payment_panel — cleanup

- [ ] [CRITICAL] WebView `onPaymentDone` always passes `null` (line 2417) — `tg://` redirect URLs from providers like Stripe carry the credential token in query params (e.g. `tg://payment_form?credentials=...`); the code never parses them and always fires `widget.onPaymentDone(null)`. The `onPaymentDone` callback at line 2272 guards on `if (token != null)`, so `_credentialsData` is never set through the web flow. `sendPaymentForm` then sends no `credentials_data`, causing all web-provider payments to fail. Fix: parse the `tg://` URL query params for the credentials token before calling `onPaymentDone`. — `payment_panel.dart:2417`

- [ ] [CRITICAL] WebView URL intercept `.contains('done')` and `.contains('success')` (lines 2415–2416) matches too broadly — any URL with those substrings anywhere (e.g. `https://3ds.provider.com/process?order_id=123done`, `https://success.payment.com/landing`) fires `onPaymentDone(null)` and closes the WebView mid-flow. Fix: restrict to `tg://` scheme only, or use a specific regex for known terminal patterns. — `payment_panel.dart:2414`

- [ ] [MAJOR] `accentFg = isDark ? Colors.white : Colors.white` — both branches are identical, always produces `Colors.white` regardless of theme (line 660). On a light theme with a pale accent color, white text on the PAY button will be invisible. — `payment_panel.dart:660`

- [ ] [MAJOR] `Image.network` for product thumbnail has no `cacheWidth`/`cacheHeight` (line 944) — product photos are displayed at 80×80 px but decoded and memory-cached at full resolution. Add `cacheWidth: _kThumbSize.toInt()` and `cacheHeight: _kThumbSize.toInt()`. — `payment_panel.dart:944`

- [ ] [MAJOR] `_buildTipsSection` allocates a redundant list copy (`allItems = [..._suggestedTips]`) and recomputes row chunking on every `build()` call (lines 1088–1095) — `_suggestedTips` only changes at form load. Precompute rows in `_fetchForm`/`setState` and store as a field. — `payment_panel.dart:1088`

## peer_short_info — cleanup

- [ ] [CRITICAL] `TapGestureRecognizer` instances created inline in `_parseTextWithEntities` are never stored or disposed — every `setState` rebuild (status update, photo nav, buffering) that re-invokes `_buildInfoRows` leaks all recognizers from the previous render; Flutter's `RenderParagraph` does not auto-dispose inline recognizers — store them as state fields and dispose in `dispose()` — `peer_short_info.dart:1065-1079`

- [ ] [CRITICAL] `#hashtag` matches in bio/about text are styled as tappable links (rendered in `labelColor`, with a `TapGestureRecognizer`) but the `onTap` handler immediately `return`s — user sees a blue clickable hashtag that does nothing — either strip `#\w+` from the regex so hashtags render as plain text, or implement hashtag search navigation — `peer_short_info.dart:1073-1074`

- [ ] [MAJOR] `Image.file` used without `cacheWidth`/`cacheHeight` for both the primary avatar (`widget.avatarPath`) and navigated photos (`_currentPhotoPath`) — the cover display is 304×304 logical pixels but the full-resolution image file is decoded and cached at its native size, wasting memory proportional to the avatar's actual resolution — set `cacheWidth: (_kCoverSize * MediaQuery.of(context).devicePixelRatio).round()` — `peer_short_info.dart:522-529`

- [ ] [MAJOR] `value.replaceAll(' ', ' ')` at line 946 is a dead no-op — with `maxLines: 1` already enforced on the `SelectableText`, non-breaking space substitution has no effect on wrapping, and if both characters are ASCII 0x20 it allocates a new string on every call for nothing — remove the `replaceAll` call — `peer_short_info.dart:946`

- [ ] [MAJOR] `_PhotoProgressBarsPainter.paint` silently draws nothing when `smallWidth < size.height` (i.e. bar width < 2 px) — for users with many photos the condition triggers at roughly 50+ photos on a 304 px wide box, leaving the nav zones active but with no visual progress indicator; needs graceful degradation (e.g. collapse bars below a minimum count threshold, or reduce `_kBarGap` proportionally) — `peer_short_info.dart:1253-1256`

# photo_crop_editor — cleanup

- [ ] [CRITICAL] blur strokes silently dropped from export — `_applyCropAndExport` (line 1010) skips every stroke where `tool == _PaintTool.blur` via `continue` and never calls the blur rendering equivalent of `_CropPainter._drawBlurStrokes`; users see blur on-screen but the saved file has none — `photo_crop_editor.dart:1010`

- [ ] [CRITICAL] regular strokes drawn twice in eraser export path — when `hasEraser` is true, lines 1009-1013 draw all pen/arrow/marker strokes directly onto the canvas, then lines 1016-1039 draw them again inside a `saveLayer`; strokes from the first pass are already composited so the `BlendMode.clear` eraser can't reach them, producing doubled stroke artifacts and non-functional erasure on the exported image — `photo_crop_editor.dart:1009`

- [ ] [MAJOR] `shouldRepaint` list-identity check always false for strokes and annotations — `old.paintStrokes != paintStrokes` (line 2604) and `old.textAnnotations != textAnnotations` (line 2605) compare the same `List` object reference on every rebuild (both sides point to the same mutable list in `_PhotoCropEditorState`), so the check is never true; text annotations added while `currentStroke` is null won't trigger a canvas repaint — use a generation counter or copy the list reference on mutation — `photo_crop_editor.dart:2604`

- [ ] [MAJOR] `TextPainter` created and laid out on every pointer-move event — `_annotationItemSize` (line 1724) constructs a full `TextPainter`, calls `layout()`, and discards it just to get widget dimensions; this is called from both `_hitTestAnnotations` and `_hitTestAnnotationHandles` on every `PointerMoveEvent`; cache the size per annotation indexed by text+fontSize+scale — `photo_crop_editor.dart:1724`

- [ ] [MAJOR] `TextPainter` created per annotation per paint frame in `_drawTextAnnotations` — lines 2412-2425 allocate and lay out a new `TextPainter` for every text annotation on every call to `paint()`; with frequent repaints (brush drawing, zoom) this fires many times per second; cache layout results keyed by text+fontSize+scale — `photo_crop_editor.dart:2412`

- [ ] [MAJOR] sticker thumbnail base64-decoded on every `GridView.builder` itemBuilder call — line 3689 calls `_decodeThumb(sticker.thumbB64)` followed by `Uint8List.fromList(...)` inside `itemBuilder`; this runs for every visible sticker on every rebuild; decoded bytes should be cached once per sticker (a `Map<String, Uint8List>` in `_EditorStickerPickerState` keyed by sticker id or b64 hash) — `photo_crop_editor.dart:3689`

- [ ] [MAJOR] export temp files written to `/tmp/` hardcoded — lines 1091 and 4092 use `File('/tmp/crop_...')` and `File('/tmp/emoji_avatar_...')`; `/tmp/` does not exist on Android or iOS; replace with `(await getTemporaryDirectory()).path` from `path_provider` — `photo_crop_editor.dart:1091`

# popup_menu — cleanup

- [ ] [MAJOR] `_shadowColor(Brightness b)` ignores its parameter entirely — always returns `Color(0xFF000000)` regardless of light/dark mode; the `Brightness b` argument is dead code — `popup_menu.dart:18`

- [ ] [MAJOR] First-frame expand-origin mismatch: `_origin` defaults to `Alignment.topLeft` (line 205) but the real origin is only resolved during layout and applied one frame later via `addPostFrameCallback` → `setState`. For clicks near the bottom or right screen edge where the true origin is `bottomRight`, the first animation frame expands from the wrong corner before snapping to the correct one — `popup_menu.dart:205` `popup_menu.dart:273`

- [ ] [MAJOR] `_TelegramRippleItem.build`: the ripple `AnimatedBuilder` (line 979) rebuilds and repaints the full item widget on every frame of the 650ms ripple animation with no `RepaintBoundary` isolating the ripple layer; neighboring siblings in the `Column` receive unnecessary repaint requests each frame — `popup_menu.dart:979`

- [ ] [MAJOR] `_panelCurve` static method is duplicated verbatim in two classes: `_TelegramMenuOverlayState` (line 330) and `_AnimatedSubmenuRevealState` (line 495) — extract to a top-level function — `popup_menu.dart:330` `popup_menu.dart:495`

## privacy_settings_screen — cleanup

- [ ] [CRITICAL] Wrong state field key in `_CloudPasswordEmail._setPassword` — reads `state?['unconfirmedEmail']` at line 4221 but the Go engine (telegram.go:18323) serialises the field as `emailUnconfirmedPattern`, which is also what `_fetchPasswordState` at line 131 reads. Result: after setting a 2FA password with a recovery email the unconfirmed email is never detected, `_CloudPasswordEmailConfirm` is never pushed, and the user lands on `_CloudPasswordDone` without ever verifying the email — `privacy_settings_screen.dart:4221`

- [ ] [CRITICAL] `FutureBuilder` in `_showBlockUserPicker` re-fetches contacts on every search keystroke — `_loadContacts(engine, accountId, blockedIds)` is called directly in the `future:` parameter inside `StatefulBuilder`'s builder. Every `setDialogState(() => searchQuery = v)` call triggers a rebuild, creates a new `Future`, and `FutureBuilder` transitions back to `waiting`, causing the list to flash and contacts to be re-fetched from the engine on every typed character — `privacy_settings_screen.dart:7164`

- [ ] [CRITICAL] `_hashPasscodeWithSalt` runs 100 000 SHA-256 iterations synchronously on the UI thread — the `for (var i = 0; i < 99999; i++)` loop at line 5528 blocks the main isolate for ~200–500 ms on every passcode creation (line 5616) and verification (`_LocalPasscodeVerify._verify` line 6039). Must be moved to `compute()` or `Isolate.run()` — `privacy_settings_screen.dart:5528`

- [ ] [CRITICAL] Direct state mutation in `build()` without `setState` in `_BirthdayDayMonthPickerState` — `if (_day > _maxDay) _day = _maxDay;` at line 7802 mutates `_day` during `build`. Flutter does not re-render in response; the dropdown `value` may exceed its `items` list, causing a blank selection or assertion failure when the user picks February with day > 28/29 — `privacy_settings_screen.dart:7802`

- [ ] [MAJOR] Aggressive 15-second polling timer fires 13 engine calls simultaneously — `initState` at line 88 starts a `Timer.periodic` that calls `_fetchPasswordState`, `_fetchGlobalTTL`, `_loadPasscodeState`, `_fetchPasskeys`, `_fetchBlockedCount`, `_fetchSessionsCount`, `_fetchAllPrivacy`, `_fetchMessagesPrivacy`, `_fetchArchiveSettings`, `_fetchAccountTTL`, `_fetchTopPeers`, `_fetchContentSettings`, and `_fetchWebsitesCount` every 15 seconds. Most are network round-trips. On a busy screen this is 52 engine calls/min and will routinely hit FLOOD_WAIT — `privacy_settings_screen.dart:88`

- [ ] [MAJOR] Top peers section renders with wrong default value before data loads — `_buildTopPeersSection` at line 1492 has no `_topPeersLoaded` guard (unlike `_buildArchiveAndMuteSection` which has `if (!_archiveLoaded) return []` and `_buildSensitiveContentSection` which has `if (!_sensitiveLoaded …) return []`). `_topPeersEnabled` defaults to `true`; if the real value is `false` the toggle momentarily shows enabled, and a fast tap can toggle from the wrong initial state — `privacy_settings_screen.dart:1492`

- [ ] [MAJOR] `_openApplyToExisting` fires up to 500 `setHistoryTTL` calls in a tight loop without `await` or rate-limiting — line 5275: `engine.setHistoryTTL(accountId, chat.chatId, _selectedTTL)` inside `for (final chat in chats)` with no await. All 500 requests are dispatched simultaneously; Telegram will return FLOOD_WAIT and the UI reports "applied to N chats" even when most calls failed — `privacy_settings_screen.dart:5275`

## reactions_detail — cleanup

- [ ] [CRITICAL] `_onTabSelected` line 361 — condition `!isReadTab && _masterReactors.isNotEmpty` fires for both the "All" tab (`tab == null`) AND any specific-emoji tab. For a specific emoji it sets `_allReactors = _masterReactors` (the first-page all-reactions data) and returns early, so `_filteredReactors` local-filters that incomplete set instead of fetching the emoji-specific list. If there are 50 😂 reactors but only 3 appear in the first 20 "All" results, the 😂 tab shows 3. Fix: guard should be `tab == null && _masterReactors.isNotEmpty` — `reactions_detail.dart:361`

- [ ] [CRITICAL] `_loadReactors` line 254 — same root cause: `if (_selectedTab != null && _masterReactors.isNotEmpty)` reuses master data for specific-emoji tabs, setting `_allReactors = _masterReactors` and `_nextOffset = _masterNextOffset` (an all-reactions cursor, not an emoji-specific cursor). Subsequent `_loadMore` calls use the all-reactions offset and will miss later pages of the specific emoji. Fix: this branch should only fire when `_selectedTab == null` — `reactions_detail.dart:254`

- [ ] [CRITICAL] DM read tab shows `"User ${participant.userId}"` instead of the peer's name — `_fetchReadInfo` for DM creates `ReadParticipantInfo(userId: widget.message.chatId, date: result.date)` at line 179 with no `name` field, so `_ReadParticipantRow` line 934 always falls back to the literal `'User ${participant.userId}'` string. Need to resolve the peer name from AppState/chat list (or a `GetUserInfo` engine call) before building the `ReadParticipantInfo` — `reactions_detail.dart:179`

- [ ] [MAJOR] `_groupedByEmoji` getter (line 328) and `_filteredReactors` getter (line 336) are both called inside `build()` (lines 426–428) and recompute from scratch on every rebuild — `_groupedByEmoji` builds a full `Map` by iterating all reactors, `_filteredReactors` allocates a new filtered list. Cache both as computed state fields; invalidate in `setState` calls that modify `_allReactors` or `_selectedTab` — `reactions_detail.dart:328`

- [ ] [MAJOR] `Image.file` at line 1088 loads full-resolution avatar photo with no `cacheWidth`/`cacheHeight`; every `_ReactorAvatar` (46 logical px, so ~92px on 2× display) decodes the full image into memory. Add `cacheWidth: (widget.size * 2).toInt(), cacheHeight: (widget.size * 2).toInt()` — `reactions_detail.dart:1088`

- [ ] [MAJOR] `_InlineCustomEmoji._onCacheUpdate` (line 1352) calls `setState(() {})` unconditionally on every global cache event regardless of whether this widget's `documentId` changed. With N custom-emoji widgets open simultaneously, any single cache write triggers N rebuilds. Guard: only call `setState` when `cache.getFile(widget.documentId) != null || cache.getThumb(widget.documentId) != null` changed since last render — `reactions_detail.dart:1352`

- [ ] [MAJOR] `_LoadingPlaceholder.build` (line 1239) uses `AnimatedBuilder` that rebuilds the entire `Column(3 rows)` subtree on every animation tick (~60fps). Wrap the `AnimatedBuilder`'s child in `RepaintBoundary` to isolate animation repaints from the parent widget tree — `reactions_detail.dart:1239`

- [ ] [MAJOR] Dead variable `wasReadTab` declared at line 359 but never referenced. Remove it — `reactions_detail.dart:359`

# send_files_box — cleanup

## CRITICAL

- [ ] [CRITICAL] `_onAiCaptionTap()` is a full stub — shows "Generating AI caption…" toast then exits, never calls any engine method and never updates `_captionController`. Variables `currentCaption` and `accountId` are fetched and immediately discarded. The AI caption button exists in the UI but does nothing for Premium users. — `send_files_box.dart:2098`

- [ ] [CRITICAL] `_tryClipboardImageWindows()` has a timestamp race: the PowerShell command string is interpolated with `DateTime.now().millisecondsSinceEpoch` at call-site, then after `Process.run` returns (ms later) a **second** `DateTime.now()` is used to construct `tmpFile` — the two timestamps will never match so the saved file is never found, and the method silently returns `false` every time. Fix: capture one `final ts = DateTime.now().millisecondsSinceEpoch` before the call and reuse it for both the command and `tmpFile`. — `send_files_box.dart:954`

- [ ] [CRITICAL] `_SendMenuButton` is passed `widget.starsPerMessage` (the immutable constructor prop, frozen at dialog open) instead of `_starsPerMessage` (the mutable state updated by `_showEditPriceDialog`). After the user edits the price, the send button label still shows the original total. Fix: change `starsPerMessage: widget.starsPerMessage` → `starsPerMessage: _starsPerMessage`. — `send_files_box.dart:2682`

## MAJOR

- [ ] [MAJOR] All `Image.file()` calls decode photos at full resolution despite displaying at small sizes — no `cacheWidth`/`cacheHeight` hints provided. Specific locations: `_SingleMediaPreview` (308 px wide preview, line 2866), `_GifPreview` (line 3111), `_FileCard` thumbnail (`_fileThumbSize = 64`, line 4160). Album thumbs at line 3512 also lack hints but have variable widths. Fix: add `cacheWidth: _previewWidth.toInt()` / `cacheWidth: _fileThumbSize.toInt()` to each.

- [ ] [MAJOR] `_AlbumPreviewState` registers `_shrinkAnim.addListener(() => setState(() {}))` — this triggers a full subtree rebuild on every animation frame during drag-shrink. Replace with `AnimatedBuilder` wrapping only the animated subtree. — `send_files_box.dart:3209`

- [ ] [MAJOR] Scroll shadow update is registered twice: `_scrollController.addListener(_updateScrollShadows)` at line 411 AND a `NotificationListener` in `build()` schedules an extra `addPostFrameCallback` call to the same function on every `ScrollNotification` (lines 2238–2244). Every scroll fires the shadow check twice — once inline, once deferred. Remove the `NotificationListener` path; the controller listener is sufficient.

- [ ] [MAJOR] `context.read<AppState>().photoEditorHintCount` is called inside `build()` (line 2388) — `read` does not register a dependency, so when `incrementPhotoEditorHintCount()` bumps the counter past 5, the hint text won't disappear until some unrelated `setState` triggers a rebuild. Replace with `context.watch<AppState>().photoEditorHintCount` or wrap in a `Selector`.

- [ ] [MAJOR] `_FileListPreviewState.build()` constructs all file rows in a `Column` with a `for` loop (line 3965) — all widgets are eagerly built. When many documents are attached (no hard cap in non-slow mode) this wastes build time. Convert to `ListView.builder` with `shrinkWrap: true` and `physics: NeverScrollableScrollPhysics()`.

## settings_screen — cleanup

- [ ] [CRITICAL] `_callsDisabled` never loaded from engine — `getCallsDisabledHere` exists in EngineService but is never called in `_loadSettings()`. The state field defaults to `false`, so "Accept calls on this device" always opens as ON regardless of the actual server setting. Fix: add `engine.getCallsDisabledHere(accountId)` to the `Future.wait` list at line 2138 and read it in the setState block. — `settings_screen.dart:2122-2161`

- [ ] [CRITICAL] New Quick Reply is added with no `shortcut_id` — `_showAddQuickReplyDialog` appends `{'shortcut': ..., 'message': ...}` to `_data['replies']` (line 3385) with no `shortcut_id` key. The delete handler checks `shortcutId > 0` (line 3326) before calling `deleteQuickReplyShortcut`, so newly created replies can never be deleted — the delete button silently no-ops. Fix: after adding, call `setBusinessFeature` immediately to persist and reload to get the server-assigned `shortcut_id`, or call a dedicated `createQuickReplyShortcut` engine method and capture the returned ID. — `settings_screen.dart:3381-3390, 3325-3336`

- [ ] [MAJOR] `base64Decode` called inside `GridView.builder` itemBuilder — In `_GiftCatalogScreen.build` (line 3731) and inside `_showEmojiAvatarPicker` / `_showEmojiStatusPanel` grid builders (lines 1040, 1191), `base64Decode(thumbB64)` runs on every rebuild for each visible item. This is heavy allocation in hot widget code. Fix: decode once into a `List<Uint8List>` when the data is first fetched and pass the decoded bytes down. — `settings_screen.dart:3731, 1040, 1191`

- [ ] [MAJOR] `_sameDevice` preference not persisted — `_sameDevice` defaults to `false` (line 2123) and is never loaded from any engine call or local storage. It resets to "off" every time the Calls tab is opened. Fix: persist the value via `AppState.setCallSameDevice` / a local pref and load it in `_loadSettings`. — `settings_screen.dart:2123`

- [ ] [MAJOR] Missing `RepaintBoundary` on scale-preview animation inner child — `_buildFloatingPreview` wraps its content in `AnimatedBuilder` with per-frame `Opacity` and `Transform.scale` changes (line 1675). The `child:` argument of `AnimatedBuilder` is correctly separated, but the inner `Container` with `_ScalePreviewContent` has no `RepaintBoundary`, so every animation tick dirties the entire preview subtree instead of just the transform layer. Add `RepaintBoundary` around `_ScalePreviewContent`. — `settings_screen.dart:1675-1729`

## shell — cleanup

- [ ] [CRITICAL] group-call `onToggleMute` has no optimistic state update (lines 380–385): personal call version calls `chatState.setActivePersonalCall(personalCall.copyWith(isMuted: !personalCall.isMuted))` immediately so the button reflects the new state while the engine round-trip completes; the group-call branch only fires `engine.setCallMuted(...)` and returns, so the mute icon stays frozen until a `GroupCallStateEvent` arrives — `shell.dart:380`

- [ ] [MAJOR] `isDark` computed but never read in `_buildTwoColumn` (line 512) and `_buildThreeColumn` (line 580) — the dead assignment still calls `Theme.of(context)`, which registers an unnecessary InheritedWidget dependency and causes both helpers to rebuild on every theme change — `shell.dart:512`, `shell.dart:580`

- [ ] [MAJOR] `_saveLayoutPrefs()` is called directly inside `build()` (lines 241 and 249) — this method does synchronous `File.writeAsStringSync` on the UI thread; it fires on every rebuild where `useVerticalFilters` or `forumViewAsMessagesKeys` differs from the cached snapshot, blocking the raster thread for the duration of the JSON encode + disk write — `shell.dart:241`

- [ ] [MAJOR] `_syncVisibility()` is called from `build()` (line 1129) and internally calls `_visibilityAnim.forward()` / `_visibilityAnim.reverse()` / `_slideAnim.forward()` / `_slideAnim.reverse()`; driving animation controllers from inside `build()` schedules extra frame callbacks mid-frame, leading to redundant rebuilds and occasional debug-mode "setState called during build" assertions — move to `addPostFrameCallback` or `didUpdateWidget` — `shell.dart:1129`

## shortcuts_settings_screen — cleanup

- [ ] [CRITICAL] `_commandGroups` (line 11) omits 22 of the 45 `ShortcutCommand` variants — formatting shortcuts (formatBold/Italic/Underline/Strike/Code/Blockquote/Spoiler/Clear/Link/Date), compose/editing (editLastMessage, replyPrevious, replyNext, openFilePicker, pastePlainText), navigation (cancelSearch, chatSwitchOverlay, chatSwitchOverlayReverse), and support commands (supportReloadTemplates/ToggleMuted/ScrollToCurrent/HistoryBack/HistoryForward) — all have real handlers registered in `ShortcutListener` and real default bindings in `_defaultBindings`, but because they are absent from `_commandGroups` they never appear in the settings screen; users cannot see or remap them — `shortcuts_settings_screen.dart:11`

- [ ] [MAJOR] all `_ShortcutRow` and separator widgets are eagerly instantiated inside `build()` before being handed to `ListView.builder` (lines 382–448) — `ListView.builder` only virtualises layout, not object creation; with ~100 items every `setState` (triggered on each row-tap to begin recording) tears down and rebuilds the full widget list — store command-group data and defer widget construction to `itemBuilder` so only visible rows are built — `shortcuts_settings_screen.dart:382`

## spoiler_animation — cleanup

- [ ] [MAJOR] `_generateSheet` has no error handling — if `_renderSpriteSheet` throws (OOM, compute-isolate crash), the `async` exception is swallowed by the fire-and-forget call at line 114/120 (`_generateSheet(type)` is never awaited), `_textGenerating`/`_imageGenerating` stays `true` permanently, all pending completers in `_textCompleters`/`_imageCompleters` are never resolved or rejected, and every subsequent `getSheet()` call silently queues a completer that can never complete — spoiler sprites stop loading for the entire app session. Fix: wrap `_generateSheet` body in try/catch, complete all queued completers with an error (or a fallback sheet), and reset the generating flag in a `finally` block. `spoiler_animation.dart:126`

- [ ] [MAJOR] Frame timing uses magic number `33` instead of `_kFrameDurationMs` — line 91: `timestamp.inMilliseconds ~/ 33`. The constant `_kFrameDurationMs = 33` is defined at line 27 and used correctly everywhere else (cache header write/read, particle lifetime calculations), but the live frame-index calculation ignores it. If `_kFrameDurationMs` is ever changed, the animation advances at the wrong speed while the cache stores frames timed differently, causing the particle motion to look wrong. Fix: `timestamp.inMilliseconds ~/ _kFrameDurationMs`. `spoiler_animation.dart:91`

# main — cleanup

- [ ] [CRITICAL] `_closeBehaviorSyncListener` is added to `appState` at line 353 but never removed in `dispose()` (lines 2023–2060) — all other seven sync-listeners are cleaned up, but this one is missing, leaking the closure and preventing `appState` from being garbage-collected — `main.dart:353`

- [ ] [CRITICAL] Anonymous passcode-lock listener at line 510 (`appState.addListener(() { _notifSystem.passcodeLocked = ... })`) is never stored in a variable, so it cannot be removed in `dispose()` — permanent listener leak for the lifetime of the object — `main.dart:510`

- [ ] [CRITICAL] Hardcoded English strings in the logout confirm dialog — `'Log out'` (title), `'Are you sure you want to log out?'` (body), `'Cancel'`, `'Log out'` (buttons) — must use `TrStrings` like every other string in this file — `main.dart:2786–2805`

- [ ] [CRITICAL] Hardcoded English string `'Please enter your passcode'` in `_submit()` — breaks all non-English locales; rest of passcode UI uses `TrStrings.lngPasscodePh()` etc. — `main.dart:2541`

- [ ] [CRITICAL] Duplicate unreachable `ctrl+r` handler at line 1519 — the identical handler at lines 1403–1406 already calls `ChatView.requestMarkActiveChatRead()` and `return`s, so the second block is dead code and will never execute — `main.dart:1519`

- [ ] [MAJOR] `_ThemeRevertOverlay` countdown timer fires every 100 ms and always calls `setState(() {})`, but the displayed countdown value (`seconds = ceil(remainingMs / 1000)`) only changes ~once per second — 90 % of rebuilds render identical content; track last-displayed seconds and only `setState` when the value actually changes — `main.dart:2261–2267`

- [ ] [MAJOR] `_waitForText` creates a `Timer.periodic` with no way to cancel it if the widget is disposed mid-poll — timer keeps running after unmount, walks the (already-torn-down) widget tree via `_findTextOnScreen`, and writes to a tmp file; the `Timer` reference is never stored — `main.dart:2004–2019`

- [ ] [MAJOR] `_dispatchHover` dispatches `PointerHoverEvent` with `pointer: _hoverPointer` (999999) without a preceding `PointerAddedEvent` for that device/pointer — compare `_dispatchScroll` which explicitly sends `PointerAddedEvent` first; hover may silently no-op or assert in the gesture binding — `main.dart:1339–1342`

- [ ] [MAJOR] `build()` in `_UniClientAppState` recomputes the full palette every rebuild: `palette.colorize(accentColor)` and `palette.adjustServiceColorsForWallpaper(appState.wallpaper)` are called unconditionally on every `context.watch<AppState>()` change (including unrelated state changes like unread count), even though the palette inputs only change when the user edits theme/accent/wallpaper — cache the result keyed on `(themeId, accentHex, wallpaper)` — `main.dart:2067–2087`

- [ ] [MAJOR] `listChats` debug command uses `chatState.chats.indexOf(c)` inside a `map()` over `take(20)`, making it O(n×m) where n is the full chat list size — use `enumerate`/`asMap().entries` on the already-taken slice instead — `main.dart:628`

## stats_chart — cleanup

- [ ] [MAJOR] `_cachedTP` calls `layout()` on every access — text painter cache only prevents allocation, not layout — `stats_chart.dart:1614`

  `TextSpan` does not override `==`, so `tp.text != span` is always true (reference inequality). Every call to `_cachedTP` re-runs `tp.text = span; tp.layout()` even for a cached painter. During ruler animation or footer drag, this fires ~14 layout() calls per paint frame (7 left labels + 7 right for DoubleLinear/currency). Fix: build and layout the painter once on first insert, and return it directly on cache hit:
  ```dart
  TextPainter _cachedTP(String text, TextStyle style) {
    final key = '$text|${style.fontSize}|${style.color?.value}';
    return textCache.putIfAbsent(key, () => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout());
  }
  ```

- [ ] [MAJOR] `_ChartAreaPainter.shouldRepaint` uses reference equality on two mutable maps that are mutated in-place — the comparisons always return `false` — `stats_chart.dart:2302` and `2313`

  `lineVisible` and `pieSliceHoverProgress` are both state maps that get mutated via `_lineVisible[id] = false` and `_pieSliceHoverProgress[key] = v` without ever replacing the map instance. So `lineVisible != old.lineVisible` (line 2302) and `pieSliceHoverProgress != old.pieSliceHoverProgress` (line 2313) are comparing the same object to itself — always `false`. Currently harmless because no `RepaintBoundary` isolates the painter, so `setState` rebuilds force a repaint anyway. If a `RepaintBoundary` is ever added (which is the obvious next optimization for this heavy painter), line toggles and pie hover animation will silently stop repainting.

- [ ] [MINOR] Dead ternary in `_paintPieLabelsInternal` — `isDark` is checked but both branches are identical — `stats_chart.dart:2240`

  ```dart
  final pieLabelColor = isDark ? Colors.white : Colors.white;
  ```
  The `isDark` parameter is ignored. White-on-slice-color is correct for dark mode but may be illegible on light-colored slices in light mode. Either drop the ternary and keep `Colors.white`, or decide on a light-mode color (e.g. `Colors.black87`).

## sticker_pack_viewer — cleanup

- [ ] [CRITICAL] `_showPremiumRequired()` is a stub — "Unlock" button (line 331) calls this, which only shows a SnackBar with text "Subscribe to Telegram Premium". No navigation, no URL open, no real upsell flow. Visible button does nothing actionable. Should open `https://t.me/premium` or a premium subscription dialog — `sticker_pack_viewer.dart:237`

- [ ] [CRITICAL] Silent fail in `_sendSticker` when `activeChat == null` (line 199-200) — returns early with no user feedback, sheet stays open. Reachable via `StickerPackViewer.showByName()` called outside a chat context. Should show a snackbar ("Open a chat first") or disable the send tap when no chat is active — `sticker_pack_viewer.dart:199`

- [ ] [MAJOR] No `RepaintBoundary` around animated `_StickerTile` widgets — Lottie (`_lottieData != null`) and Video (`_webmController != null`) tiles repaint on every animation frame, dirtying the entire grid repaint layer. `GridView.builder` at line 379 should wrap each tile's return in `RepaintBoundary` — `sticker_pack_viewer.dart:379`

- [ ] [MAJOR] WebM temp file path collision (line 542) — writes to `Directory.systemTemp/sticker_$docId.webm` with no unique suffix per instance. Opening the same pack twice simultaneously (or after a crash before dispose cleans up) causes two `_StickerTileState` instances to write concurrently to the same path, corrupting the file or causing playback errors — `sticker_pack_viewer.dart:542`

- [ ] [MAJOR] `Player.dispose()` called fire-and-forget in `dispose()` (line 582) — `media_kit`'s `Player.dispose()` is `async`; calling it without `await` in `dispose()` means audio/video resources (native threads, file handles) may not be released before the widget unmounts. Schedule via `player.dispose().catchError((_){})` assigned to a local before nulling the field — `sticker_pack_viewer.dart:582`

- [ ] [MAJOR] `_loadingFile` never reset to `false` after a failed/type-mismatch load (lines 514, 530) — if `getStickerFiles` returns an entry whose `mimeType` matches neither `isTgs` nor `isWebm`, the flag stays `true` permanently. The guard `if (_loadingFile) return` at line 513/529 then blocks any future retry. Should be reset to `false` in the else branch and catch — `sticker_pack_viewer.dart:514`

## story_editor — cleanup

- [ ] [CRITICAL] `_continueStroke` (line 899-903) mutates `_currentStrokePoints` in-place and then pings `_strokesNotifier`, but `_StrokePainter.shouldRepaint` (line 2182-2184) compares `old.currentPoints != currentPoints` — since it's the **same list object** (only mutated, never reassigned), this is always `false`. Result: `CustomPainter.paint()` is never scheduled during drawing. The live stroke does not render until the user lifts their finger (`_endStroke` calls `setState` which triggers a full rebuild). Fix: in `_continueStroke`, assign a new list (`_currentStrokePoints = [..._currentStrokePoints!, pos/scale]`) so the reference changes and `shouldRepaint` returns true. — `story_editor.dart:899`

- [ ] [CRITICAL] `_renderCanvasToBytes` places scene items at `canvas.translate(item.position.dx * _canvasWidth, item.position.dy * _canvasHeight)` (line 586-590). But `item.position.dx` is already in canvas-pixel units (0.._canvasWidth ≈ 0..540) — multiplying by `_canvasWidth` (540) translates to coordinates like 291600px on a 540px-wide canvas. All stickers and text items land far outside the export bounds and are clipped out. The exported story image contains background + paint strokes only — no text or sticker overlays. Fix: remove the multiplication: `canvas.translate(item.position.dx, item.position.dy)`. — `story_editor.dart:586`

- [ ] [MAJOR] `_ContactPickerDialogState.initState` (line 2458-2464) iterates ALL contacts and base64-decodes their avatar bytes synchronously on the main thread inside `initState`. For accounts with 200+ contacts this blocks the UI thread for tens of milliseconds, causing a visible freeze when the privacy dialog opens. Fix: do the decoding in a microtask or use `compute()`. — `story_editor.dart:2458`

- [ ] [MAJOR] `_StrokePainter.paint()` (line 2066) calls `canvas.saveLayer(Offset.zero & size, Paint())` unconditionally for ALL strokes. A `saveLayer` forces GPU off-screen compositing even for simple opaque pen strokes. Only the marker tool (needs `BlendMode.src` layer) and eraser (needs `BlendMode.clear` layer) actually require a layer. Move `saveLayer`/`restore` inside the `isMarker` and eraser branches; remove the outer one. — `story_editor.dart:2066`

- [ ] [MAJOR] `Image.memory` for sticker widgets (line 992) and in `_buildStickerGrid` (line 3153) provides no `cacheWidth`/`cacheHeight` hint. Flutter decodes the full-resolution sticker PNG on every widget rebuild instead of decoding once at display size. Add `cacheWidth: 120, cacheHeight: 120` to both `Image.memory` calls. — `story_editor.dart:992`

- [ ] [MAJOR] `_buildBlurLayers` (line 841) creates one `BackdropFilter` widget per committed blur stroke with no `RepaintBoundary` isolating them. Every `setState` (including routine pan/drag updates) causes all blur compositing layers to repaint together with the rest of the Stack. Add a single `RepaintBoundary` wrapping the blur layers list, or combine all blur paths into one `ClipPath`+`BackdropFilter`. — `story_editor.dart:841`

- [ ] [MAJOR] `_StickerPickerPanelState._buildStickerGrid` (line 3133-3138) rebuilds `allStickers` by iterating all packs and their stickers on **every** `build()` call. For large sticker collections this is O(N×M) work per frame. Cache the flat list (e.g., compute in `_loadStickerPacks` and store as `_allStickers`). — `story_editor.dart:3133`

- [ ] [MAJOR] `_barAnimDuration` constant (line 25, value `200`) is declared but never referenced. The `AnimationController` (line 252) hardcodes `Duration(milliseconds: 200)` independently. Remove the dead constant or use it. — `story_editor.dart:25`

## telegram_toast — cleanup

- [ ] [CRITICAL] double `OverlayEntry.remove()` assertion crash in `showStickerToast` — when replacing an active toast, `Future.delayed(_kFadeOutMs=1000ms, oldEntry.remove)` forcibly yanks the old entry without calling `_startHide()` on it; the old toast's 3 s hold timer + 1 s reverse animation later fires `onDone → entry.remove()` on the already-removed entry, hitting Flutter's `assert(_overlay != null)` — `telegram_toast.dart:290-296` vs `telegram_toast.dart:320-323`

- [ ] [CRITICAL] dead branch in `_buildMessage()` — the `packCount > 1` path (lines 461-468) returns the exact same `TextSpan` list as the final fallback return (lines 470-475); the pack count is never shown in the message, and the branch distinction does nothing — `telegram_toast.dart:461`

- [ ] [MAJOR] `_fadeOut` field is wrong direction and unused — defined as `CurvedAnimation(parent: ReverseAnimation(_ctrl), curve: Curves.easeIn)` which evaluates 0→1 during `_ctrl.reverse()` (increasing opacity, not decreasing); `build()` correctly bypasses it with `Tween<double>(begin:1, end:0).animate(CurvedAnimation(...))` inline, but this allocates a new `Tween` + `CurvedAnimation` on every animation frame during fade-out — `telegram_toast.dart:94,130-131` vs `telegram_toast.dart:203-208` and `telegram_toast.dart:595-598`

- [ ] [MAJOR] `TapGestureRecognizer` memory leak — two recognizers created inline inside `_buildMessage()` (a method called from `build()`) with no disposal path; gesture recognizers hold native resources and must be stored as state fields and disposed in `dispose()` — `telegram_toast.dart:432,446`

## telegram_tooltip — cleanup

- [ ] [CRITICAL] `_ImportantTooltipDelegate.getPositionForChild` left/right cases use wrong x and y at lines 432–437 — for `TooltipSide.right`, `x = targetRect.center.dx - arrowSkip` places the tooltip to the LEFT of the target center, and `y = targetRect.top - childSize.height` places it ABOVE the target instead of beside it; for `TooltipSide.left`, same y bug; correct values are `x = targetRect.right + _kArrowHeight` / `y = targetRect.center.dy - childSize.height / 2` for right, and `x = targetRect.left - childSize.width - _kArrowHeight` / same y for left — `telegram_tooltip.dart:432`

- [ ] [MAJOR] `_TooltipPositionDelegate.shouldRelayout` at line 200 only compares `pointer`, ignoring `screenSize`, `shift`, and `edgeSkip` — after a window resize the overlay tooltip keeps its stale position until the pointer moves — `telegram_tooltip.dart:200`

- [ ] [MAJOR] `AnimatedBuilder` at line 334 wraps a raw `Opacity` widget, which forces a composited layer on every frame without a `RepaintBoundary` — replace `Opacity`/`Transform.translate` with `FadeTransition`/`SlideTransition` (driven by `_curvedAnim`) to keep animation on the compositor thread, or wrap `tooltipContent` in `RepaintBoundary` — `telegram_tooltip.dart:334`

## theme_editor — cleanup

- [ ] [CRITICAL] `_currentBackground` is never set during `_handleImport` (line 382–413). `parseThemeFile` returns `backgroundImage` for zip themes, but the result is never stored in `_currentBackground`. When the user imports a `.tdesktop-theme` with a background and then exports it, the background is silently dropped. Fix: `_currentBackground = parsed.backgroundImage;` inside the `setState` block in `_handleImport`. — `theme_editor.dart:400`

- [ ] [CRITICAL] Hex editor channel mismatch for transparent colors. `_colorToHexString` emits `#RRGGBBAA` for colors with alpha < 255 (line 1176). `_parseHexColor` reads 8-char hex as `AARRGGBB` — `Color(int.parse(h, radix: 16))` (line 265). Applying the displayed hex value of any semi-transparent token through the inline editor (Apply button or Enter) produces completely wrong RGB and alpha values. Fix in `_parseHexColor`: for 8-char input, swap AA to front — `var reordered = h.substring(6) + h.substring(0, 6);` then parse that. — `theme_editor.dart:260`

- [ ] [MAJOR] Slug field shown and validated for local export. `_SaveThemeBoxState._save()` calls `_validateSlug(slug)` unconditionally (line 1343) even when `widget.cloudSave == false`, where the slug is irrelevant and not used in `_ExportResult`. The slug `TextField` is also rendered unconditionally (lines 1444–1479). This confuses users with a cloud-only concept during local save and can block the save if the user edits the field to something invalid. Fix: guard both the slug field and `_validateSlug` call behind `if (widget.cloudSave)`. — `theme_editor.dart:1343`

- [ ] [MAJOR] `entryIndex` mutable closure in `ListView.builder.itemBuilder` (line 682, incremented at line 800). The counter is a `var` declared once per `build()` call and incremented inside `itemBuilder`. `ListView.builder` may call `itemBuilder` for arbitrary visible indices, and if items are re-built individually (e.g. by key changes or framework-driven rebuilds of specific slots), the cumulative counter drifts. The result is that `_focusedIndex` highlighting and `onTap` capture the wrong entry index. Fix: precompute the entry index for each item when building `_cachedItems` and store it in `_ListItem`, or compute it from `index` by counting headers before `index` in the items list. — `theme_editor.dart:682`

- [ ] [MAJOR] `setState` called inside a `for` loop for PageDown/PageUp key handling (lines 509–524). Each iteration fires a separate `setState(() => _focusedIndex++)`, potentially scheduling tens of redundant rebuilds per keystroke. Flutter batches synchronous `setState` within a single frame but still enqueues a mark-needs-rebuild per call. Fix: compute the final `_focusedIndex` before the loop, then call `setState` once with the result. — `theme_editor.dart:509`

## titlebar — cleanup

- [ ] [MAJOR] `_oneSideControls` and `_resizeEnabled` are never queried at startup — `initState` calls `_queryMaximized()` and `_queryButtonLayout()` but has no equivalent calls for these two fields — they stay at their Dart defaults (`false` / `true`) until the native side pushes a change event — if the platform sets `resizeEnabled=false` at launch the maximize button renders incorrectly until the next native event fires — `titlebar.dart:83-88`

- [ ] [MAJOR] Static `MethodChannel` handler is last-writer-wins — `initState` calls `setMethodCallHandler(_onNativeCall)` and `dispose` sets it to `null` — if two `CustomTitlebar` instances are ever live simultaneously (hot-reload, nested navigation, duplicate mount) the first dispose silences all future native events for every instance — the channel should be wrapped in a reference-counted manager or the widget must be enforced as a strict singleton — `titlebar.dart:87,92`

## web_app_panel — cleanup

- [ ] [CRITICAL] `_handleOpenPopup` invalid-data guard calls `Navigator.of(context).pop()` at line 1095 — this pops the **web app panel itself** (not a dialog, no dialog is open at that point) instead of just ignoring bad input; any mini app that sends a popup with empty message or buttons crashes the user out of the panel — `web_app_panel.dart:1094`

- [ ] [CRITICAL] `_handleOpenScanQrPopup` shows an AlertDialog but never sends `scan_qr_popup_closed` back to the web view — the mini app JS is waiting for either `qr_text_received` or `scan_qr_popup_closed` and will hang in "scanning" state permanently after the user clicks OK — `web_app_panel.dart:519`

- [ ] [CRITICAL] `iconCustomEmojiId` is stored in `WebAppButtonConfig` (line 1042), drives `effectiveVisible` at line 1034 (button becomes visible even with empty text when emoji is set), but is never passed to `_WebAppButton` and `_WebAppButton.build()` renders nothing for it — a button made visible solely via emoji icon appears as a blank active button; the icon never shows — `web_app_panel.dart:1034,1654,1777`

- [ ] [CRITICAL] `_handleRequestEmojiStatusAccess` (line 853) directly calls `BotRequestEmojiStatusAccess` on the engine with no user-facing confirmation dialog — Telegram spec: "Prompts the user to grant permission for the mini app to manage emoji status" — compare `_handleRequestWriteAccess` which correctly shows a dialog first; user never sees the permission prompt — `web_app_panel.dart:853`

- [ ] [CRITICAL] `_handleSwitchInlineQuery` fires `BotSwitchInlineQuery` on the engine (line 484) but never calls `_close()` afterward — per Telegram Mini App spec `web_app_switch_inline_query` must close the mini app and switch to inline query; the panel stays open after the engine call completes — `web_app_panel.dart:483`

- [ ] [MAJOR] `_handleShareToStory` (line 535) shows a blocking AlertDialog saying "not supported" — `web_app_share_to_story` is fire-and-forget per Telegram spec (no response event expected); the dialog blocks the web app's UI thread and is wrong UX — should silently drop — `web_app_panel.dart:535`

- [ ] [MAJOR] Loading overlay is dismissed on `onPageFinished` (line 207) not on `web_app_ready` — Telegram spec: the native app must hide the loading screen only when the mini app sends `web_app_ready` (the app is render-ready, not just DOM-parsed); currently `web_app_ready` handler is a no-op `break` at line 271 — content can flash before the web app has finished its own initialization — `web_app_panel.dart:207,270`

- [ ] [MAJOR] `_SpinnerPainter.shouldRepaint` (line 1915) only checks `progress != oldDelegate.progress` — ignores `color` and `strokeWidth`; if theme changes while spinner is visible the old colors/stroke persist until progress ticks — `web_app_panel.dart:1915`

- [ ] [MAJOR] `_kProgressOpacity` constant (line 23) is defined as `0.3` but never referenced anywhere in the file — spinner color is set directly to `palette.windowSubTextFg` with no opacity applied — dead constant — `web_app_panel.dart:23`

## engine_models — cleanup

- [ ] [MAJOR] `CachedMessage.fromJson` decodes `content_raw` twice: `_decodeContentRawExtra` (line 900) and `_decodeContentRawTop` (line 911) both independently call `base64Decode` + `utf8.decode` + `json.decode` on the same string, then return `parsed['extra']` vs `parsed` respectively. Called back-to-back at lines 766–767 for every message parsed. Fix: merge into one decode that returns the top-level map, then extract `extra` from it at the call site. — `engine_models.dart:766`

- [ ] [MAJOR] `CachedMessage` missing `isVideoNote` getter — mediaType 5 (videonote) is the only media type in the 0–12 range with no boolean getter. All others have one (`isImage`, `isVideo`, `isVoice`, `isSticker`, `isGif`, `isFile`, `isPoll`, `isLocation`, `isContact`, `isInvoice`). Any UI rendering video-notes must use the raw `mediaType == 5` guard inline, and `isVideo` (which only matches type 2) misses them. — `engine_models.dart:1006`

- [ ] [MAJOR] `CachedMessage.copyWith` silently omits 6 contentRaw-derived fields from its parameter list: `topicId`, `topicName`, `topicColorId` (lines 1198–1200) and `stickerSetShortName`, `stickerSetId`, `stickerSetAccessHash` (lines 1209–1211). The body uses `topicId: topicId` etc. which resolves to `this.topicId` (no local). A call to `copyWith(contentRaw: newRaw)` produces an object with updated `contentRaw` but stale topic/sticker fields that were originally decoded from the old `contentRaw`. — `engine_models.dart:1198`

