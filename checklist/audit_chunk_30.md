# advanced_settings_screen — Audit Findings

- [ ] [CRITICAL] Connection type label is a static 3-string switch on `proxyMode`; never shows actual transport protocol or reacts to connection state changes — `advanced_settings_screen.dart:105-113` ← `settings_advanced.cpp:106-117` (AyuGram queries `account->mtp().dctransport()` and subscribes to `proxy().connectionTypeChanges()` for reactive updates)

- [ ] [CRITICAL] "Manage Dictionaries" dialog is a static placeholder showing only "Install language packs through your operating system settings." — no real dictionary management — `advanced_settings_screen.dart:1034-1037` ← `settings_advanced.cpp:932-942` (AyuGram opens `Box<Ui::ManageDictionariesBox>(session)`)

- [ ] [CRITICAL] Screen reader section is always rendered; AyuGram only shows it when a screen reader is detected AND its optimized mode is currently disabled — `advanced_settings_screen.dart:1058-1076` ← `settings_advanced.cpp:1184-1188` (`if (!detected || !disabled) return;`)

- [ ] [MAJOR] Native window frame toggle placed in System Integration section instead of Window Title section — `advanced_settings_screen.dart:583-590` ← `settings_advanced.cpp:329-347` (AyuGram puts it inside `BuildWindowTitleSection`)

- [ ] [MAJOR] Spellchecker sub-options ("Auto-download dictionaries", "Manage Dictionaries") shown on Linux/macOS even though those platforms use system spellcheckers and should not expose these options — `advanced_settings_screen.dart:965-983` ← `settings_advanced.cpp:912` (`if (!isSystem)` guard missing)

- [ ] [MAJOR] Power saving flags `kPowerSavingStickersPanel`, `kPowerSavingStickersChat`, `kPowerSavingEmojiReactions`, `kPowerSavingChatBackground`, `kPowerSavingChatEffects`, `kPowerSavingCalls`, `kPowerSavingAnimations` are saved to state but never read by any widget — toggling them has no effect — `advanced_settings_screen.dart:2200-2209` ← `settings_power_saving.cpp:59-63` (AyuGram applies flags to `PowerSaving::Current()` which actually controls rendering)

- [ ] [MAJOR] "Recent Downloads" shows only `appState.recentDownloads` (an in-memory list seeded only by explicit `addRecentDownload()` calls); AyuGram opens the full engine-backed Downloads section with all session downloads — `advanced_settings_screen.dart:3476` ← `settings_advanced.cpp:175-186` (`Info::Downloads::Make(controller->session().user())`)

- [ ] [MAJOR] "Restart" button in OpenGL/ANGLE restart dialog calls `exit(0)` (terminates without relaunching); AyuGram calls `Core::Restart()` which relaunches the process — `advanced_settings_screen.dart:818` ← `settings_advanced.cpp:776,814`

- [ ] [MAJOR] Opening a downloaded file uses `Process.run('xdg-open', [path])` which is Linux-only; on macOS `open` is needed, on Windows `explorer.exe` — fails silently on non-Linux platforms — `advanced_settings_screen.dart:3549` ← `settings_advanced.cpp:175-186` (AyuGram uses platform-agnostic `File::OpenWith`)
