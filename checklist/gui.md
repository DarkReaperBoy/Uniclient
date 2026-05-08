# GUI Audit — Cycle 1 Phase Ayugram (2026-05-08 18:36)

## Code Comparison (Dart vs AyuGram)

# bridge — FFI bridge & engine event wiring

> **Note on AyuGram comparison:** AyuGram Desktop is a C++ application with no FFI
> bridge layer, no Go backend, and no Dart UI. There is no AyuGram source file that
> corresponds to `bridge.dart` or `engine_service.dart`. Findings below are made
> against the project's own Go engine (`go/engine/events.go`, `go/bridge/`) which IS
> the ground truth for what the Dart bridge must handle.

---

## 1. Personal call events silently dropped — incoming_call

- [ ] [CRITICAL] Go engine emits `incoming_call` events (when `call.State == CallStateRinging`) but `_dispatchEngineEvent` has no `case 'incoming_call':` handler and `EngineService` has no `onIncomingCall` stream. The event is silently discarded after the `switch` falls through without a match. The personal call UI in `main.dart` is driven exclusively by the debug-command interface (`/tmp/uniclient_debug_cmd.json`), not by real engine events. Real incoming calls will never ring. — `engine_service.dart:3695-3792` ← `go/engine/events.go:29,472-473`

## 2. Personal call events silently dropped — call_state

- [ ] [CRITICAL] Go engine emits `call_state` events for all non-ringing personal call state transitions (connecting, connected, hanging up, etc.) but `_dispatchEngineEvent` has no `case 'call_state':` handler and `EngineService` has no `onCallState` stream. These events are silently discarded. Once a call is established, Dart never receives updates about its state — the call bar and call screen cannot reflect real call progress. — `engine_service.dart:3695-3792` ← `go/engine/events.go:30,474-475`

## 3. callAsync is synchronous on web

- [ ] [MAJOR] `bridge_web.dart`'s `callAsync` is implemented as `async => call(requestBytes)` — the `async` keyword makes it return a Future but the underlying `call()` still runs synchronously in the same microtask, blocking the JS event loop. Any WASM operation that takes >16 ms will drop frames on web. Since WASM has no real threads this cannot be fixed with isolates, but callers expecting non-blocking behaviour get none. — `bridge_web.dart:44` ← `go/cmd/bridge/main.go:28` (single-threaded WASM export)

## 4. _resolvedLibPath global shared across BridgeImpl instances

- [ ] [MAJOR] `_resolvedLibPath` is a module-level global (`String?` at top of `bridge_ffi.dart`) while `_initialized` is an instance field on `BridgeImpl`. If two `BridgeImpl` instances are created (e.g. in tests or if `Bridge()` is instantiated more than once), the second call to `init()` overwrites the global `_resolvedLibPath` while the first instance's `callAsync` (`Isolate.run(() => _isolateCall(libPath, ...))`) captures the now-stale value. Background isolate calls from the first instance would load the second instance's library. The fix is to make `_resolvedLibPath` an instance field. — `bridge_ffi.dart:36,46,77-78`

# telegram_palette — Color Palette Token Audit

## Sources compared
- Dart: `dart/lib/theme/telegram_palette.dart`
- Ground truth: `AyuGramDesktop/Telegram/lib_ui/ui/colors.palette`

---

## telegram_palette — Color value discrepancies and missing tokens

- [ ] [CRITICAL] `introCoverTopBg` wrong color: `Color(0xFF0F89D0)` (bright blue) but spec is `#2B2242` (dark purple, 56% B-channel deviation) — login/intro screen background is the wrong color entirely — `telegram_palette.dart:2815` ← `colors.palette:170`

- [ ] [CRITICAL] `introCoverBottomBg` wrong color: `Color(0xFF39B0F0)` (bright blue) but spec is `#2B2242` (dark purple) — login gradient bottom completely wrong — `telegram_palette.dart:2816` ← `colors.palette:171`

- [ ] [CRITICAL] `settingsIconBg1` wrong: `Color(0xFF5BBB6F)` (green) but spec is `#f06964` (red, R-channel 58% off) — settings icons will show wrong semantic colors — `telegram_palette.dart:2870` ← `colors.palette:325`

- [ ] [CRITICAL] `settingsIconBg2` wrong: `Color(0xFFEC7577)` (red-pink) but spec is `#6dc534` (green) — swapped with bg1 — `telegram_palette.dart:2871` ← `colors.palette:326`

- [ ] [CRITICAL] `settingsIconBg3` wrong: `Color(0xFF43A4DF)` (blue) but spec is `#ed9f20` (orange) — `telegram_palette.dart:2872` ← `colors.palette:327`

- [ ] [CRITICAL] `settingsIconBg4` wrong: `Color(0xFFFAAD38)` (orange) but spec is `#56b3f5` (light blue) — `telegram_palette.dart:2873` ← `colors.palette:328`

- [ ] [CRITICAL] `settingsIconBg6` wrong: `Color(0xFF5ABDD6)` (teal) but spec is `#b580e2` (purple) — `telegram_palette.dart:2875` ← `colors.palette:330`

- [ ] [CRITICAL] `settingsIconBgArchive` wrong: `Color(0xFFFFC535)` (yellow) but spec is `#9da2b0` (blue-gray) — archive icon in main menu wrong color — `telegram_palette.dart:2877` ← `colors.palette:332`

- [ ] [CRITICAL] `premiumIconBg1` wrong: `Color(0xFF6B93FF)` (blue) but spec is `#f38926` (orange, 85% B-channel deviation) — premium settings icon gradient color 1 completely wrong — `telegram_palette.dart:2893` ← `colors.palette:661`

- [ ] [CRITICAL] `premiumIconBg2` wrong: `Color(0xFF976FFF)` (purple) but spec is `#e44456` (red) — premium settings icon gradient color 2 completely wrong — `telegram_palette.dart:2894` ← `colors.palette:662`

- [ ] [CRITICAL] `importantTooltipBg` wrong: `Color(0xFF5D7FA4)` (solid opaque blue) but spec is `toastBg = #2c3033e5` (near-black with 89% alpha, used for group call important tooltips) — `telegram_palette.dart:2901` ← `colors.palette:605`

- [ ] [CRITICAL] `msgWaveformOutActive` wrong: `Color(0xFF40A7E3)` (accent blue, same as windowBgActive) but spec is `#5ebd66` (green, 49% B-channel deviation) — played portion of outbox voice message waveform will be wrong color — `telegram_palette.dart:2802` ← `colors.palette:426`

- [ ] [CRITICAL] Group call color tokens entirely absent from `TelegramPalette`: `groupCallBg`, `groupCallActiveFg`, `groupCallMembersBg`, `groupCallMembersBgOver`, `groupCallMembersBgRipple`, `groupCallMembersFg`, `groupCallMemberActiveIcon`, `groupCallMemberActiveStatus`, `groupCallMemberInactiveIcon`, `groupCallMemberInactiveStatus`, `groupCallMemberMutedIcon`, `groupCallMemberNotJoinedStatus`, `groupCallIconFg`, `groupCallLive1`, `groupCallLive2`, `groupCallMuted1`, `groupCallMuted2`, `groupCallForceMutedBar1/2/3`, `groupCallForceMuted1/2/3`, `groupCallMenuBg`, `groupCallMenuBgOver`, `groupCallMenuBgRipple`, `groupCallLeaveBg`, `groupCallLeaveBgRipple`, `groupCallVideoTextFg`, `groupCallVideoSubTextFg` (~27 tokens) — any group call UI widget has no color tokens to use — `telegram_palette.dart:1-560` (absent) ← `colors.palette:569-598`

- [ ] [MAJOR] `msgOutBgSelected` wrong: `Color(0xFFCBEBB5)` (lime-green) but spec is `#b7dbdb` (teal, 15% B-channel deviation, perceptually opposite hue) — selected outbox message background is wrong color — `telegram_palette.dart:2704` ← `colors.palette:347`

- [ ] [MAJOR] `msgWaveformOutInactive` wrong: `Color(0xFFB3D4E7)` (light blue) but spec is `#b3e2b4` (light green, 20% B-channel deviation) — inactive portion of outbox voice waveform wrong color — `telegram_palette.dart:2803` ← `colors.palette:428`

- [ ] [MAJOR] `lightButtonFgOver` wrong: `Color(0xFF12659A)` but spec defines `lightButtonFgOver: lightButtonFg` = `#168ACD` (`0xFF168ACD`) — darker shade used on mouse-over for light buttons — `telegram_palette.dart:2660` ← `colors.palette:45`

- [ ] [MAJOR] `msgOutServiceFg` wrong: `Color(0xFF529E39)` but spec is `#45a32d` — forwarded-from info text on outbox messages is wrong green — `telegram_palette.dart:2710` ← `colors.palette:353`

- [ ] [MAJOR] `msgServiceBg` alpha wrong: `Color(0x90527C41)` (alpha=0x90, 56%) but spec is `#517c417f` (alpha=0x7F, 50%) — service message background opacity is 12% too opaque — `telegram_palette.dart:2717` ← `colors.palette:363`

- [ ] [MAJOR] `tooltipFg` wrong: `Color(0xFF9A9FA3)` (light gray) but spec is `#5d6c80` (dark blue-gray) — tooltip text is much lighter than spec — `telegram_palette.dart:2899` ← `colors.palette:94`

- [ ] [MAJOR] `menuSeparatorFg` wrong: `Color(0xFFE5E5E5)` but spec is `#f1f1f1` (lighter) — popup menu separator is slightly wrong — `telegram_palette.dart:2862` ← `colors.palette:59`

- [ ] [MAJOR] `msgOutDateFg` wrong: `Color(0xFF6FAB69)` but spec is `#6db566` — outbox message timestamp text wrong green shade — `telegram_palette.dart:2708` ← `colors.palette:361`

- [ ] [MAJOR] `msgOutReplyBarColor` wrong: `Color(0xFF64B05C)` but spec is `#5eb854` — reply outline on outbox messages wrong green shade — `telegram_palette.dart:2712` ← `colors.palette:367`

- [ ] [MAJOR] `mainMenuCoverBg` wrong token: `Color(0xFF40A7E3)` (= `windowBgActive`) but spec defines `mainMenuCoverBg: dialogsBgActive` = `#419fd9` — slightly different blue used for main menu header background — `telegram_palette.dart:2866` ← `colors.palette:497`

- [ ] [MAJOR] `kColorizeIgnoredKeys` incomplete — ~30 tokens that are bypassed (not passed through `s()`) in the `colorize()` method are absent from this set, so code that iterates `kColorizeIgnoredKeys` to decide what to skip when loading `.tdesktop-theme` files will incorrectly re-colorize them. Missing entries include: `stickerPanPremium1`, `stickerPanPremium2`, `dialogsMentionIconFg`, `dialogsReactionIconFg`, `dialogsPollIconFg`, `historyCallArrowInFg`, `historyCallArrowInFgSelected`, `historyCallArrowMissedInFg`, `historyCallArrowMissedInFgSelected`, `historyCallArrowOutFg`, `historyCallArrowOutFgSelected`, `historyPeerUserpicFg`, `historyPeerSavedMessagesBg`, `historyPeerArchiveUserpicBg`, `historyPeerSavedMessagesBg2`, `settingsIconFg`, `youtubePlayIconBg`, `youtubePlayIconFg`, `videoPlayIconBg`, `videoPlayIconFg`, `trayCounterBg`, `trayCounterBgMute`, `trayCounterFg`, `trayCounterBgMacInvert`, `trayCounterFgMacInvert`, `paymentsTipActive`, `callArrowFg`, `callArrowMissedFg`, `mapPointDrop`, `mapPointDot`, `callBg`, `callBgOpaque`, `callBgButton`, `callNameFg`, `callStatusFg`, `callIconBg`, `callIconBgActive`, `callIconFgActive`, `callIconActiveRipple`, `callAnswerBg`, `callAnswerRipple`, `callAnswerBgOuter`, `callHangupBg`, `callHangupRipple`, `callMuteRipple`, `premiumButtonFg`, `premiumIconBg3` — `telegram_palette.dart:1148` ← `colors.palette:1-693` (colorize-excluded tokens are those with hardcoded non-accent semantics)

# theme — Color constants, size constants, and AppTheme builder

- [ ] [MAJOR] `AppColors.msgOutDateFg` is `#6fab69` but AyuGram palette defines `msgOutDateFg: #6db566` — wrong shade of green for outbox message timestamps in light theme — `theme.dart:49` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:362`

- [ ] [MAJOR] `AppColors.historyOutIconFg` is `Color(0xFF5dc452)` which matches `dialogsSentIconFg: #5dc452` (the chat-list sent icon), NOT `historyOutIconFg: #57b84c` (the in-chat message tick) — wrong source color applied to wrong context — `theme.dart:51` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:268` (correct) vs `193` (value actually used)

- [ ] [MAJOR] `AppColors.bubbleSentSelectedLight` is `#cbebb5` but AyuGram defines `msgOutBgSelected: #b7dbdb` — wrong selected outbox bubble background for light theme; `#cbebb5` is a warm lime-green, `#b7dbdb` is a grey-teal — `theme.dart:43` ← `AyuGram/Telegram/lib_ui/ui/colors.palette:348`

- [ ] [MAJOR] `AppSizes.bubbleRadius = 18` but AyuGram defines `bubbleRadiusLarge: 16px` — 2px too large on all primary bubble corners — `theme.dart:91` ← `AyuGram/Telegram/SourceFiles/ui/chat/chat.style:435`

- [ ] [MAJOR] `AppSizes.avatarSize = 40` but AyuGram dialog rows use `photoSize: 46px` — avatar in chat list is 6px too small, breaking row proportions (row height is `dialogsRowHeight: 62px`) — `theme.dart:93` ← `AyuGram/Telegram/SourceFiles/dialogs/dialogs.style:96`

- [ ] [MAJOR] `AppTheme.fromPalette` hardcodes `fontFamily: 'Inter'` but AyuGram Desktop uses `normalFont: font(fsize)` (system/platform font resolved at runtime, not Inter) — text rendering will look visibly different from the AyuGram reference on Linux/Windows — `theme.dart:106` ← `AyuGram/Telegram/lib_ui/ui/basic.style:52`

# theme_file — Theme file parser/serializer

## Summary

`theme_file.dart` implements parsing and exporting of Telegram `.tdesktop-theme` ZIP files and plain palette text files. Compared against `window_theme.cpp` and `window_theme_editor.cpp` in AyuGram Desktop.

---

- [ ] [CRITICAL] Cloud metadata key names and format completely wrong — Dart writes/reads `// id:N hash:N` (single line, lowercase keys) but AyuGram uses `// ID: N` and `// ACCESS: N` on separate lines with `: ` separator; any real Telegram Desktop–exported theme loses cloud linkage when parsed, and Dart-exported themes are unreadable by AyuGram — `theme_file.dart:88-94` (regex `id:(\d+)`, `hash:(\d+)`) and `theme_file.dart:172-176` (writes `id:N hash:N`) ← `AyuGram/window/themes/window_theme_editor.cpp:346-356` (writes `// ID: N` / `// ACCESS: N` via `add("ID", ...)` / `add("ACCESS", ...)`)

- [ ] [CRITICAL] 71 palette tokens missing from `paletteToMap`/`paletteFromMap` — Dart maps 509 tokens, AyuGram palette has 580; missing entire feature groups: all 28 `groupCall*` tokens (group call UI colours), 11 `statisticsChart*` tokens (stats charts), 5 `credits*`/`currencyFg` tokens, 4 `wallet*` tokens, `rankAdminFg`/`rankOwnerFg`/`rankUserFg`, `spellUnderline`, `outdatedBg`/`Fg`/`outdateSoonBg`, `songCoverOverlayFg`, `photoEditorItemBaseHandleFg` — importing a theme that sets these tokens silently ignores them (falls back to default), and exported themes are missing these tokens entirely — `theme_file.dart:308-819` (paletteToMap definition) ← `AyuGram/lib_ui/ui/colors.palette:569-680` (groupCallBg, statisticsChartInactive, creditsBg1, etc.)

- [ ] [MAJOR] `ZipEncoder().encode()` returns `List<int>?` (nullable) but return value is used directly without null check — `Uint8List.fromList(encoded)` will throw `ArgumentError` if encoder returns null — `theme_file.dart:168` ← `AyuGram/window/themes/window_theme_editor_box.cpp:333-374` (`PackTheme()` always writes at least the palette file before encoding, but Dart must guard against null return)

- [ ] [MAJOR] No background image pixel-count validation — AyuGram rejects backgrounds whose `width × height > 25 * 1024 * 1024` (25 million pixels); Dart accepts and decodes any-size background byte array, risking OOM on maliciously crafted themes — `theme_file.dart:239-250` (no check on bgBytes) ← `AyuGram/window/themes/window_theme.cpp:56` (`kBackgroundSizeLimit = 25 * 1024 * 1024`) and `window_theme.cpp:332` (`size.width() * size.height() > kBackgroundSizeLimit`)

- [ ] [MAJOR] Background file read size limit missing — AyuGram caps the background file read at `kThemeBackgroundSizeLimit = 4 MB`; Dart reads the entire embedded background byte array from the ZIP with no size guard — `theme_file.dart:239-240` (unconditional `Uint8List.fromList(bgFile.content as List<int>)`) ← `AyuGram/window/themes/window_theme.h:42` (`kThemeBackgroundSizeLimit = 4 * 1024 * 1024`) and `window_theme.cpp:251`

- [ ] [MAJOR] One-pass reference resolution fails for chained palette references (A→B→C) — Dart's second pass resolves each string-reference key against `resolved` (populated only with direct `#hex` colours), so if `foo` references `bar` and `bar` is itself a reference (not a hex), `foo` won't be resolved — `theme_file.dart:119-136` (two-pass resolver, no iteration until stable) ← `AyuGram/window/themes/window_theme.cpp:195-225` (`loadColorScheme` calls `palette.setColor(name, value)` which the palette class resolves recursively against its own already-set values)

# theme_name_generator — Color palette and word lists diverge from AyuGram source

## Summary

`generateThemeName` matches AyuGram's `GenerateName` in algorithm (same weighted-RGB distance
formula, same 50/50 adjective-vs-noun branch), but the three data tables — color palette,
adjective list, noun list — are all substantially wrong relative to the C++ source of truth.

---

- [ ] [CRITICAL] Berry RGB is (142,68,173) — a purple — but C++ stores 0x8e0000 = (142,0,0), a dark red; the distance metric will pick wrong color names for large swaths of the accent-color space — `theme_name_generator.dart:39` ← `window_themes_generate_name.cpp:17`

- [ ] [CRITICAL] Bronze RGB is (205,127,50) but C++ stores 0x3f2109 = (63,33,9); Dart value is 3× brighter on every channel — `theme_name_generator.dart:41` ← `window_themes_generate_name.cpp:79`

- [ ] [CRITICAL] Violet RGB is (127,0,255) — electric purple — but C++ stores 0x240a40 = (36,10,64), near-black deep violet; Dart R is 3.5× higher and B is 4× higher — `theme_name_generator.dart:117` ← `window_themes_generate_name.cpp:78`

- [ ] [CRITICAL] Steel RGB is (113,121,126) but C++ stores 0x262335 = (38,35,53); Dart is ~3× brighter (medium gray vs almost-black) — `theme_name_generator.dart:102` ← `window_themes_generate_name.cpp:109`

- [ ] [CRITICAL] Mahogany RGB is (192,64,0) but C++ stores 0x4e0606 = (78,6,6); Dart G is 10× wrong, B misses entirely — `theme_name_generator.dart:60` ← `window_themes_generate_name.cpp:85`

- [ ] [CRITICAL] Maple RGB is (196,98,16) but C++ stores 0x780109 = (120,1,9); Dart G is 98× the C++ value — `theme_name_generator.dart:61` ← `window_themes_generate_name.cpp:89`

- [ ] [CRITICAL] Cherry RGB is (222,49,99) but C++ stores 0x800b47 = (128,11,71); R differs by 73%, G differs by 77% — `theme_name_generator.dart:129` ← `window_themes_generate_name.cpp:19`

- [ ] [CRITICAL] Mint RGB is (62,180,137) but C++ stores 0x98ff98 = (152,255,152); Dart is 59% of C++ on R, 71% on G, and B has no blue-green component at all — `theme_name_generator.dart:63` ← `window_themes_generate_name.cpp:54`

- [ ] [CRITICAL] Indigo RGB is (75,0,130) but C++ stores 0x4f69c6 = (79,105,198); Dart G is 0 vs C++ 105, Dart B is 130 vs C++ 198 — `theme_name_generator.dart:51` ← `window_themes_generate_name.cpp:59`

- [ ] [CRITICAL] Mocha RGB is (131,106,91) but C++ stores 0x782d19 = (120,45,25); Dart G is 2.4× C++ value, Dart B is 3.6× C++ value — `theme_name_generator.dart:64` ← `window_themes_generate_name.cpp:87`

- [ ] [CRITICAL] Khaki RGB is (195,176,145) but C++ stores 0xf0e68c = (240,230,140); Dart R is 81% lower, G 76% lower, B has a completely different hue (145 tan vs 140 yellow-green) — `theme_name_generator.dart:53` ← `window_themes_generate_name.cpp:90`

- [ ] [CRITICAL] Vanilla RGB is (243,229,171) but C++ stores 0xd1bea8 = (209,190,168); Dart is significantly more yellow and lighter — `theme_name_generator.dart:115` ← `window_themes_generate_name.cpp:100`

- [ ] [CRITICAL] ~42 colors present in C++ kColors are entirely absent from Dart _colors, causing wrong nearest-color matches for those hue ranges: Red (0xff0000), Yellow (0xffff00), Green (0x00ff00), Blue (0x0000ff), Black (0x000000), White (0xffffff), Gray (0x808080), Purple (0x660099), Amber (0xffbf00), Strawberry (0xff3399), Cranberry (0xdb5079), Russet (0x80461b), Seashell (0xf1f1f1), Banana (0xfbe7b2), Citrus (0xa1c50a), Sunflower (0xe4d422), Persimmon (0xff6b53), Clover (0x384910), Cucumber (0x83aa5d), Jungle (0x29ab87), Malachite (0x0bda51), Lagoon (0x017987), Aquamarine (0x71d9e2), Ultramarine (0x120a8f), Blackberry (0x4d0135), Eggplant (0x614051), Rum (0x796989), Sienna (0x882d17), Chocolate (0x370202), Cocoa (0x301f1e), Coffee (0x706555), Chestnut (0xb94e48), Almond (0xeed9c4), Diamond (0xb9f2ff), Porcelain (0xeff2f3), Chrome (0xe8f1d4), Ebony (0x0c0b1dU), Smoke (0xf5f5f5), Apple (0x4fa83d), Melon (0xfebaad), Mulberry (0xc54b8c), Brandy (0xdec196) — `theme_name_generator.dart:38-140` ← `window_themes_generate_name.cpp:16-116`

- [ ] [MAJOR] ~45 color entries exist in Dart _colors that have no counterpart in C++ kColors (invented names outside the source-of-truth palette): Denim, Fern, Mango, Mustard, Oat, Obsidian, Onyx, Papaya, Pistachio, Poppy, Pumpkin, Quartz, Raspberry, Ruby, Rust, Saffron, Sage, Salmon, Seafoam, Sepia, Slate, Snow, Storm, Straw, Tan, Terracotta, Tiger, Umber, Vermilion, Walnut, Wheat, Wisteria, Aqua, Blush, Burgundy, Caramel, Cerulean, Clay, Dusk, Fuchsia, Garnet, Pine, Magenta, Mahogany (wrong value), Honey (wrong value) — these shift nearest-color results away from what AyuGram would pick — `theme_name_generator.dart:38-140` ← `window_themes_generate_name.cpp:16-116`

- [ ] [MAJOR] _adjectives list contains ~65 words absent from C++ kAdjectives (Radiant, Luminous, Vivid, Eternal, Hidden, Silent, Serene, Bold, Brilliant, Celestial, Dancing, Ethereal, Fading, Gleaming, Glowing, Golden, Graceful, Iridescent, Kindled, Lush, Mellow, Noble, Opulent, Pastel, Primal, Pristine, Rustic, Sacred, Shimmering, Silken, Smoky, Soft, Starlit, Stormy, Subtle, Sunlit, Twilit, Veiled, Whispered, Woven, Painted, Poetic, Distant, Fleeting, Fragrant, Ivory, Lavish, Living, Marble, Moonlit, Mosaic, Northern, Organic, Phantom, Regal, Scenic, Timeless, Urban, Weathered, Zephyr, Alpine, Boreal, Coastal, Dappled, Dusted, Earthy) and is missing ~75 words that ARE in C++ (Antique, Baby, Barely, Blushing, Bohemian, Bubbly, Burning, Buttered, Classic, Clear, Cool, Cotton, Cozy, Dark, Daring, Darling, Dawn, Dazzling, Deep, Deepest, Delicate, Delightful, Divine, Double, Downtown, Dusky, Dusty, Endless, Evening, Fantastic, Flirty, Forever, Frigid, Frosty, Heavenly, Hyper, Icy, Innocent, Instant, Luscious, Lustrous, Magic, Majestic, Mambo, Millennium, Morning, Natural, Neon, Night, Opaque, Paradise, Perfect, Perky, Powerful, Rich, Sheer, Simply, Sizzling, Solar, Splendid, Spicy, Stellar, Sugared, Sunny, Super, Sweet, Tenacious, Tidal, Toasted, Totally, True, Twinkling, Ultimate, Ultra, Velvety, Virtual, Warmest, Whipped, Winsome) — `theme_name_generator.dart:142-163` ← `window_themes_generate_name.cpp:118-226`

- [ ] [MAJOR] _nouns list is used in place of C++ kSubjectives but the contents differ substantially: Dart adds ~55 nouns absent from C++ (Horizon, Aurora, Cascade, Echo, Galaxy, Haven, Nebula, Oasis, Phoenix, Prism, Realm, Solstice, Spirit, Tempest, Veil, Whisper, Zenith, Bloom, Breeze, Canyon, Ember, Fable, Garden, Harbor, Isle, Meadow, Moonrise, Petal, Ridge, Ripple, River, Shore, Spark, Starfall, Stone, Stream, Thunder, Tide, Trail, Twilight, Vale, Vista, Voyage, Wave, Wind, Crest, Crystal, Dewdrop, Feather, Forest, Harmony, Journey, Lotus, Orchard, Passage, Serenity, Tundra) and is missing ~60 words from C++ kSubjectives (Attack, Avalanche, Blast, Blossom, Burst, Butter, Candy, Carnival, Chiffon, Cloud, Delight, Dust, Fantasy, Flash, Fire, Freeze, Glade, Glaze, Gleam, Glimmer, Glitter, Grande, Highlight, Ice, Illusion, Intrigue, Jubilee, Kiss, Lights, Lollypop, Love, Luster, Madness, Matte, Moon, Muse, Myth, Nectar, Nova, Parfait, Passion, Pop, Reflection, Rhapsody, Romance, Satin, Sensation, Shine, Spice, Star, Sugar, Sunrise, Sun, Twist, Unbound, Velvet, Vibrant, Waters, Wink, Zone) — `theme_name_generator.dart:165-183` ← `window_themes_generate_name.cpp:228-310`

# theme_preview — Theme Preview Painter Discrepancies

- [ ] [CRITICAL] `_dialogsWidth` hardcoded as 260 but AyuGram style constant `themePreviewDialogsWidth` is 312px — panel is 16.6% too narrow — `theme_preview.dart:37` ← `media_view.style:445`

- [ ] [CRITICAL] Photo bubble (`addPhotoBubble(":/gui/art/themeimage.jpg", ...)`) completely absent — C++ renders it as the first message in chat history — `theme_preview.dart:275-327` ← `window_theme_preview.cpp:382`

- [ ] [CRITICAL] Audio waveform bubble (`addAudioBubble(waveform, 33, "0:07", ...)`) completely absent — C++ renders it as the second message — `theme_preview.dart:275-327` ← `window_theme_preview.cpp:383-387`

- [ ] [CRITICAL] Compose area shows circular send-arrow button; C++ renders a voice-record icon (Lottie `voice_to_video.tgs` painted with `historyRecordVoiceFg`) as the default right-side control — fundamentally wrong compose state — `theme_preview.dart:462-469` ← `window_theme_preview.cpp:570-575`

- [ ] [CRITICAL] All 9 dialog row names/previews/times are entirely fabricated and differ from AyuGram's hardcoded sample set ("Eva Summer", "Alexandra Smith", "Mike Apple", "Evening Club", "Old Pirates", "Max Bright", "Natalie Parker", "Davy Jones") — `theme_preview.dart:81-113` ← `window_theme_preview.cpp:343-401`

- [ ] [MAJOR] Active dialog row is index 2 ("Design Team") but C++ marks row 0 ("Eva Summer") as both `active` and `pinned` — `theme_preview.dart:116` ← `window_theme_preview.cpp:350-351`

- [ ] [MAJOR] Top bar shows "Design Team / 5 members, 2 online" (group info); C++ sets `_topBarName = "Eva Summer"` with `_topBarStatus = "online"` (individual + active status in `historyStatusFgActive`) — `theme_preview.dart:243-246` ← `window_theme_preview.cpp:378-380`

- [ ] [MAJOR] `_composeHeight` hardcoded as 49 but `historySendSize.height()` = 46px — compose bar is 3px too tall — `theme_preview.dart:38` ← `chat_helpers.style:1341`

- [ ] [MAJOR] Compose area background uses `palette.historyComposeAreaBg`; C++ fills with `st::historyReplyBg[_palette]` — wrong palette key — `theme_preview.dart:444` ← `window_theme_preview.cpp:558`

- [ ] [MAJOR] Hamburger/menu-toggle icon absent from dialogs header; C++ paints `st::dialogsMenuToggle.icon` to the left of the search filter — `theme_preview.dart:65-78` ← `window_theme_preview.cpp:632-638`

- [ ] [MAJOR] Top bar action icons (menu toggle, call, search) are entirely missing; C++ paints all three with palette-aware icons — `theme_preview.dart:242-247` ← `window_theme_preview.cpp:537-543`

- [ ] [MAJOR] Group/channel type icons absent from dialog rows; C++ draws `dialogsChatIcon`/`dialogsChannelIcon` for rows typed as Group or Channel — `theme_preview.dart:120-202` ← `window_theme_preview.cpp:708-727`

- [ ] [MAJOR] Send-state icons (sent/received tick) missing from dialog rows; C++ draws `dialogsSentIcon`/`dialogsReceivedIcon` for rows 5 and 6 — `theme_preview.dart:120-202` ← `window_theme_preview.cpp:785-802`

- [ ] [MAJOR] Muted unread badge uses `dialogsUnreadBg` unconditionally; C++ selects `dialogsUnreadBgMuted`/`dialogsUnreadBgMutedActive` for muted rows (row 2 is muted in C++) — `theme_preview.dart:182-193` ← `window_theme_preview.cpp:752-764`

- [ ] [MAJOR] Avatar initials use `names[i].substring(0, 1)` (single character); C++ runs `FillLetters()` which extracts up to two letters (first letter of each word) — e.g. "Saved Messages" → "SM" not "S" — `theme_preview.dart:153` ← `window_theme_preview.cpp:35-90`

- [ ] [MAJOR] Reply bar drawn as a solid 2px-wide `Rect`; C++ renders a blockquote-style bar with two layered fills at `kDefaultOutline1Opacity` + `kDefaultBgOpacity` using rounded rect — structurally different — `theme_preview.dart:403-415` ← `window_theme_preview.cpp:886-913`

- [ ] [MAJOR] History area shadows incomplete: only one vertical right-edge separator drawn; C++ paints three shadow lines (top of history, bottom of history, and left border of history panel) — `theme_preview.dart:204-208` ← `window_theme_preview.cpp:1054-1058`

- [ ] [MAJOR] `_drawText` and `_estimateTextWidth` allocate a new `TextPainter` on every call during `paint()`; with ~50+ text draws per frame this creates significant GC pressure — layout results should be pre-computed in a lazy-init or in a non-paint method — `theme_preview.dart:474-516` ← `window_theme_preview.cpp:414-442` (C++ uses pre-laid-out `Ui::Text::String` objects stored in `_rows`/`_bubbles`)

- [ ] [MAJOR] `shouldRepaint` uses `!identical(old.palette, palette)` which only detects reference changes; in-place mutations to the same `TelegramPalette` instance will never trigger a repaint — `theme_preview.dart:591-592` ← `window_theme_preview.cpp:414-416` (C++ `generate()` is called on-demand, not via `shouldRepaint`)

# theme_tokens — Design Token Value Mismatches

Compared `dart/lib/theme/theme_tokens.dart` against the canonical AyuGram `.style` files.
Every value claimed correct was verified against the source. Only deviations are listed.

---

- [ ] [CRITICAL] `boxRadius` is 8 but AyuGram defines it as 6px — all box/dialog corner rounding is 33% too large — `theme_tokens.dart:34` ← `AyuGram/Telegram/lib_ui/ui/layers/layers.style:38`

- [ ] [CRITICAL] `defaultRoundShadowBlur = 8` is a fabricated token — AyuGram uses icon-sprite–based shadows (`defaultRoundShadow`), not a blur scalar; the only blur value in the codebase is `defaultBoxShadow.blurRadius: 5px` — `theme_tokens.dart:133` ← `AyuGram/Telegram/lib_ui/ui/widgets/widgets.style:926`

- [ ] [MAJOR] `radialSize = 44` but AyuGram defines `radialSize: size(50px, 50px)` — progress ring renders 12% too small — `theme_tokens.dart:136` ← `AyuGram/Telegram/lib_ui/ui/basic.style:118`

- [ ] [MAJOR] `defaultInputFieldHeight = 47` but `defaultInputField.heightMin` is 55px — input fields render 15% shorter than spec — `theme_tokens.dart:127` ← `AyuGram/Telegram/lib_ui/ui/widgets/widgets.style:1070`

- [ ] [MAJOR] `infoProfilePhotoSize = 88` but AyuGram defines `infoProfilePhotoInnerSize: 72px` (the button is `size(72px, 72px)`) — profile photo avatar renders 22% too large — `theme_tokens.dart:150` ← `AyuGram/Telegram/SourceFiles/info/info.style:527`

- [ ] [MAJOR] `settingsProfileCoverHeight = 112` is derived from the wrong photo size (uses 88px instead of 72px) — correct value is `8 + 72 + 16 = 96px`, currently 17% too tall — `theme_tokens.dart:151` ← `AyuGram/Telegram/SourceFiles/settings/settings.style:445`

- [ ] [MAJOR] `defaultRoundShadowOffset = Offset(0, 2)` is a fabricated token — closest AyuGram value is `defaultBoxShadow.offset: point(0px, 1px)`, offset-y is 2× too large — `theme_tokens.dart:134` ← `AyuGram/Telegram/lib_ui/ui/widgets/widgets.style:928`

- [ ] [MAJOR] `menuIconSize = 20` is a fabricated constant — no `menuIconSize` token exists anywhere in the AyuGram `.style` files; menu icons are sized by their icon assets directly — `theme_tokens.dart:135` ← `AyuGram/Telegram/SourceFiles/ui/menu_icons.style` (absent)

- [ ] [MAJOR] `defaultMultiSelectRadius = 8` is a fabricated constant — no such token in AyuGram source; the `defaultMultiSelectItem` struct has no `radius` field — `theme_tokens.dart:131` ← `AyuGram/Telegram/lib_ui/ui/widgets/widgets.style:1080` (absent)

- [ ] [MAJOR] `defaultRadioDuration = Duration(milliseconds: 100)` but AyuGram sets `defaultRadio.duration: universalDuration` which resolves to 120ms — radio toggle animation is 17% too fast — `theme_tokens.dart:153` ← `AyuGram/Telegram/lib_ui/ui/widgets/widgets.style:868`

# wallpaper — WallpaperData, ChatWallpaper, gradient/pattern/tiled rendering

## Critical — data/rendering correctness

- [ ] [CRITICAL] Default `patternIntensity` is 40; AyuGram uses 50 — `wallpaper.dart:25` ← `data_wall_paper.h:110` (`kDefaultIntensity = 50`)

- [ ] [CRITICAL] `fromUrl()` default intensity fallback is 40; must be 50 — `wallpaper.dart:88` ← `data_wall_paper.cpp:389` (`result._intensity = kDefaultIntensity`)

- [ ] [CRITICAL] 2-color gradient direction is inverted (180° off): `begin=Alignment(-dx,-dy)`, `end=Alignment(dx,dy)` produces bottom-to-top at rotation=0, but AyuGram case 0 is top-to-bottom — `wallpaper.dart:296-300` ← `image_prepare.cpp:931-944` (case 0 maps `{0,0}→{0,height}`)

- [ ] [CRITICAL] 3–4 color gradients use a simple `ui.Gradient.linear` through all stops; AyuGram uses `GenerateSmallComplexGradient` — a swirled-coordinate mesh gradient with per-pixel fourth-power distance weighting across 8 phase positions — `wallpaper.dart:337-399` ← `image_prepare.cpp:172-304`

- [ ] [CRITICAL] `_MultiColorGradient` runs a continuous 8-second `AnimationController.repeat()` at 60 fps; AyuGram pre-computes discrete 45° rotation steps (`kAddRotationDoubled = 675`) and crossfades between cached frames (200 ms), triggered from `generateNextBackgroundRotation()` — `wallpaper.dart:319-325` ← `chat_theme.cpp:638-668`

- [ ] [CRITICAL] `_TiledPainter.paint()` starts async `decodeImageFromList` and stores the result in `_decoded`, but never calls `markNeedsPaint()` — after decode the painted area is never invalidated, so tiled wallpapers always render as blank — `wallpaper.dart:432-438`

- [ ] [CRITICAL] `computeAverageColor(imageBytes)` iterates over raw JPEG/PNG-encoded bytes treating every triplet as RGB — encoded bytes are compressed data, not pixels, so the computed color is garbage; AyuGram's `CountAverageColor` works on decoded `QImage` pixels — `wallpaper.dart:520-534` ← `chat_theme.cpp:329-332` (calls `Ui::CountAverageColor(_mutableBackground.prepared)`)

- [ ] [CRITICAL] `toUrlParams()` always joins color hexes with `~`; AyuGram uses `-` for exactly 2-color gradients and `~` for 3–4 — `wallpaper.dart:125` ← `data_wall_paper.cpp:171-172` (`const auto separator = (colors.size() > 2) ? '~' : '-'`)

- [ ] [CRITICAL] `toUrlParams()` emits `intensity` unconditionally; AyuGram only emits it for pattern wallpapers — `wallpaper.dart:128` ← `data_wall_paper.cpp:272-279` (`if (isPattern()) { ... if (_intensity) { ... } }`)

- [ ] [CRITICAL] `toUrlParams()` emits `rotation` for all wallpaper types; AyuGram only emits it when `backgroundColors().size() == 2` — `wallpaper.dart:129` ← `data_wall_paper.cpp:280-281`

## Major — behavioral and performance

- [ ] [MAJOR] `fromUrl()` only reads the `bg_color` query param; AyuGram falls back in order to `bg_color`, `gradient`, `color`, `slug` — `wallpaper.dart:87` ← `data_wall_paper.cpp:397-412`

- [ ] [MAJOR] Color-string separator parsing splits on `RegExp(r'[~\-]')` — accepts mixed separators (e.g. `AABBCC~DDEEFF-001122`); AyuGram only accepts `~` between colors when count > 2, rejecting mixed-separator strings entirely — `wallpaper.dart:93` ← `data_wall_paper.cpp:136-138`

- [ ] [MAJOR] Negative-intensity pattern overlay: `ColorFiltered(colorFilter: ColorFilter.mode(Colors.white, BlendMode.dstIn), child: patternImage)` is a no-op (white src with alpha=1 makes `dst * src.alpha = dst`); AyuGram draws the pattern with `CompositionMode_DestinationIn` over the gradient and then overlays a black fill at `opacity = 1 + patternOpacity` — `wallpaper.dart:493-498` ← `chat_theme.cpp:113-116, 211-217`

- [ ] [MAJOR] `blurWallpaperImage()` encodes the blurred result as PNG (`img.encodePng`); wallpapers use JPEG everywhere else (quality 87); callers expecting JPEG will get PNG bytes — `wallpaper.dart:598`

- [ ] [MAJOR] `_buildImage()` applies blur via `ImageFiltered(imageFilter: ui.ImageFilter.blur(...))` — reprocessed by the GPU on every frame for the lifetime of the chat; AyuGram pre-bakes blur on a background thread before storing the result — `wallpaper.dart:236-240` ← `chat_theme.cpp:706-728` (`crl::async` background caching)

- [ ] [MAJOR] `_MultiColorGradient` holds a live `AnimationController` that fires `AnimatedBuilder` on every vsync (60 fps) even when the chat is idle; the widget has no `RepaintBoundary`, so the repaint propagates up the tree — `wallpaper.dart:319-349`

# active_sessions_screen — Active Sessions Screen Audit

- [ ] [CRITICAL] Device rename not wired to engine: `_saveCustomDeviceModel` writes to a local JSON file (`device_prefs.json`) but never calls the engine, so the custom model is never sent to Telegram servers and future sessions will still show the old device name — `active_sessions_screen.dart:391-399` ← `settings_active_sessions.cpp:148-157` + `api_authorizations.cpp:103-115`

- [ ] [CRITICAL] Device classification ignores `apiId`: `_classifyDevice` uses only string matching against device/platform/appName; AyuGram's `TypeFromEntry` primarily keyed on `apiId` (kDesktop={2040,17349,611335}, kAndroid={5,6,24,1026,1083,2458,2521,21724}, kiOS={1,7,10840,16352}, kWeb={2496,739222,1025907}), so most official Telegram clients would be misclassified (e.g. apiId=5 Android session classified as `Other`) — `active_sessions_screen.dart:51-82` ← `settings_active_sessions.cpp:167-235`

- [ ] [CRITICAL] Browser detection checks `app_name` instead of `device` (device model): AyuGram's `detectBrowser()` checks `entry.name.toLower()` (the device model field, which for web clients contains the user agent string); Dart checks `appName.toLowerCase()` which is the app name (e.g. "Telegram Web"), so browser type is never detected from the actual user agent — `active_sessions_screen.dart:53-60` ← `settings_active_sessions.cpp:168-192`

- [ ] [CRITICAL] Edge browser detection uses wrong string: Dart checks `a.contains('edge')`; AyuGram checks `device.contains("edg/")`, `"edgios/"`, `"edga/"` — modern Edge user agent contains "Edg/" not "edge", so every Edge session is classified as `Other` — `active_sessions_screen.dart:57` ← `settings_active_sessions.cpp:180-182`

- [ ] [CRITICAL] Device classification omits `system` field entirely: AyuGram's `detectDesktop()` checks both `platform` and `system` (system version string) for OS keywords; Dart's `_classifyDevice` only checks `device` and `platform`, missing the `system` field — sessions where the OS is encoded in the system version field will be misclassified — `active_sessions_screen.dart:51-82` ← `settings_active_sessions.cpp:193-207`

- [ ] [MAJOR] `_otherSessions` getter does not sort by last active time: returns `_sessions.where(...)` unsorted; AyuGram does `ranges::sort(_data.list, std::greater<>(), &EntryData::activeTime)` — sessions display in arbitrary order instead of most-recently-active first — `active_sessions_screen.dart:134-136` ← `settings_active_sessions.cpp:787`

- [ ] [MAJOR] No engine event subscription for live updates: sessions are only refreshed by a 60-second `Timer.periodic`; AyuGram subscribes to `_authorizations->listValue()` (reactive push) so session terminations from other devices update immediately — `active_sessions_screen.dart:104` ← `settings_active_sessions.cpp:761-764`

- [ ] [MAJOR] Missing "Terminate All" divider text: `_buildTerminateAllButton` renders just the button + divider; AyuGram adds `AddDividerText(terminateInner, tr::lng_sessions_terminate_all_about())` = "All devices except for the current one will be disconnected." below the button — `active_sessions_screen.dart:732-759` ← `settings_active_sessions.cpp:967-968`

- [ ] [MAJOR] Missing "Terminate Sessions" subsection title above auto-terminate button: AyuGram calls `AddSubsectionTitle(ttlInner, tr::lng_settings_terminate_title())` before the "If Inactive For" button; Dart goes straight to the button — `active_sessions_screen.dart:854-888` ← `settings_active_sessions.cpp:997-998`

- [ ] [MAJOR] Session info box shows "online" instead of full datetime for current session: Dart uses `isCurrent ? 'online' : _formatFullDate(lastActive)`; AyuGram always shows `langDateTimeFull(base::unixtime::parse(data.activeTime))` regardless of which session is current — `active_sessions_screen.dart:433` ← `settings_active_sessions.cpp:439-447`

- [ ] [MAJOR] Missing location disclaimer in session info box: AyuGram shows `AddDividerText(container, tr::lng_sessions_location_about())` = "The location is given with precision to the city by your IP address." after the location row when location is non-empty; Dart omits this entirely — `active_sessions_screen.dart:416-559` ← `settings_active_sessions.cpp:479-481`

- [ ] [MAJOR] Device icons use generic Material icons instead of platform-specific custom icons: AyuGram uses `st::sessionIconWindows`, `st::sessionIconMac`, `st::sessionIconUbuntu`, `st::sessionIconLinux`, `st::sessionIconiPhone`, `st::sessionIconiPad`, `st::sessionIconAndroid`, `st::sessionIconChrome`, `st::sessionIconEdge`, `st::sessionIconFirefox`, `st::sessionIconSafari`, `st::sessionIconOther`; Dart substitutes generic Material icons (`Icons.desktop_windows`, `Icons.phone_iphone`, `Icons.language`, etc.) — `active_sessions_screen.dart:63-81` ← `settings_active_sessions.cpp:270-287`

- [ ] [MAJOR] Session info box uses a static gradient circle instead of animated Lottie: AyuGram's `GenerateUserpicBig` plays a Lottie animation (e.g. `device_desktop_win.lottie`) that starts when the box opens; Dart's `_DeviceUserpic(size: 70)` is a static circle with a Material icon and no animation — `active_sessions_screen.dart:452` ← `settings_active_sessions.cpp:297-409`

- [ ] [MAJOR] Auto-terminate label shows "12 months" instead of "1 year" for 365-day option: `_formatDaysLabel(365)` returns `'12 months'` (365 ~/ 30 = 12); `SelfDestructionBox::DaysLabel` maps 365 → "1 year" — `active_sessions_screen.dart:183-187` ← `settings_active_sessions.cpp:1000-1010`

- [ ] [MAJOR] Empty state widget does not match spec: AyuGram shows a `boxDividerLabel`-styled `FlatLabel` with `tr::lng_sessions_other_desc()` (small divider text inside a padded wrap); Dart shows a centered icon (`Icons.security`, 48px) + "No other active sessions" text — `active_sessions_screen.dart:890-906` ← `settings_active_sessions.cpp:1014-1021`

## admin_tools — Edit Peer Info Box / Admin Management

- [ ] [CRITICAL] Discussion group / linked channel button has empty `onTap: () {}` — clicking it does nothing; AyuGram calls `showEditDiscussionLinkBox()` which fetches groups via `MTPchannels_GetGroupsForDiscussion` and shows a picker — `admin_tools.dart:379` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:901`

- [ ] [CRITICAL] Visible History button has empty `onTap: () {}` — clicking does nothing; AyuGram shows `EditPeerHistoryVisibilityBox` and saves the `hiddenPreHistory` flag back through `saveHistoryVisibility()` — `admin_tools.dart:388` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1330`

- [ ] [CRITICAL] Topics button has empty `onTap: () {}` — clicking does nothing; AyuGram shows `Ui::ToggleTopicsBox`, guards with forum-member-minimum check, and saves `_forumSavedValue` — `admin_tools.dart:397` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1132`

- [ ] [CRITICAL] Auto-Translation toggle has empty `onTap: () {}` — clicking does nothing; AyuGram's `fillAutoTranslateButton()` actually saves `_autotranslateSavedValue` and calls `saveAutotranslate()` at the MTP layer, with boost-level gating — `admin_tools.dart:408` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1213`

- [ ] [CRITICAL] Sign Messages toggle has empty `onTap: () {}` — clicking does nothing; AyuGram's `fillSignaturesButton()` saves `_signaturesSavedValue` and the sign-profiles sub-toggle; both are persisted via `saveSignatures()` — `admin_tools.dart:417` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1276`

- [ ] [CRITICAL] Add Stickers button has empty `onTap: () {}` — clicking does nothing; AyuGram opens `StickersBox` via `controller->show(Box<StickersBox>(...))` — `admin_tools.dart:563` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:826`

- [ ] [CRITICAL] "Promoted by" row in the admin box has `onTap: () {}` — tapping the promoter name does nothing; AyuGram sets a link that opens the promoter's profile — `admin_tools.dart:2569` ← `AyuGram/boxes/peers/edit_participant_box.cpp:402`

- [ ] [CRITICAL] Transfer ownership button shows a toast `'Transfer ownership requires 2FA verification'` and returns immediately — it is a stub; AyuGram instantiates `ChannelOwnershipTransfer` which starts a real ownership-transfer flow with 2FA via `_ownershipTransfer->start()` — `admin_tools.dart:2231` ← `AyuGram/boxes/peers/edit_participant_box.cpp:691`

- [ ] [CRITICAL] "Add to Banned / Add Exception / Add Admin" button at the top of each member-list tab shows a toast `'Select a user to …'` and exits; it does not open a user-picker; AyuGram uses `AddParticipantsBoxController` which shows a real contact/search-based picker — `admin_tools.dart:4796` ← `AyuGram/boxes/peers/edit_participants_box.cpp:89`

- [ ] [CRITICAL] Photo upload from the "Set Photo" menu item is not wired — selecting 'set' in `_showPhotoMenu()` falls through with no action (the `.then()` handler only acts on 'remove'); AyuGram uses `Ui::UserpicButton` with `Role::ChangePhoto` which handles photo picking and upload atomically — `admin_tools.dart:308` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:627`

- [ ] [CRITICAL] "Set Video" menu item has no action handler — selecting 'set_video' in `_showPhotoMenu()` falls through with no effect; there is no video-avatar upload path at all in the Dart code — `admin_tools.dart:305` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:627`

- [ ] [CRITICAL] Admin log filter dialog does not pass filter state to engine — `_AdminLogFilterDialogState` maintains `_checks` map but the `onApply` callback passed from `_showFilterDialog` is just `() => _loadEvents()` with no arguments, so filter selections are completely discarded and the same unfiltered request is made — `admin_tools.dart:2745` ← `AyuGram/history/admin_log/history_admin_log_filter.h`

- [ ] [CRITICAL] `_EditRestrictedBox._loadDefaults()` loads *group-wide* default banned rights and uses them as the user's current restrictions; AyuGram loads the individual user's current `ChatRestrictionsInfo` from the participant record, not the group defaults — `admin_tools.dart:1501` ← `AyuGram/boxes/peers/edit_participant_box.cpp:737`

- [ ] [CRITICAL] `_EditAdminBox` does not load the existing admin's current rights from the engine before displaying them; all flags start as `enabled = true` regardless of actual stored rights; AyuGram receives `ChatAdminRightsInfo _oldRights` in the constructor and applies them as `prepareRights` — `admin_tools.dart:2074` ← `AyuGram/boxes/peers/edit_participant_box.cpp:413`

- [ ] [CRITICAL] Permissions save calls `engine.setDefaultBannedRights()` AND a separate `engine.setSlowMode()` when slowmode != 0, but the two are not sequenced as a stage queue; AyuGram saves them in independent `SaveDefaultRestrictions` + `SaveSlowmodeSeconds` calls tied by the same `close` callback, so any ordering error or double-close is possible — `admin_tools.dart:816` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:310`

- [ ] [MAJOR] Channel-admin rights layout mixes up section groups vs AyuGram: Dart section1=`[change_info]`, section2=`[post, edit, delete]`, section3=`[post_stories, edit_stories, delete_stories]`, section4=`[invite, manage_call, manage_direct, add_admins, ban_users]`; AyuGram for broadcast has first=`[ChangeInfo]`, messages=`[PostMessages, EditMessages, DeleteMessages]`, stories=`[PostStories, EditStories, DeleteStories]`, second=`[InviteByLinkOrAdd, ManageCall, ManageDirect, AddAdmins, BanUsers]` — section labels presented to UI are wrong ('Info'/'Messages'/'Stories'/'Meta' vs AyuGram's actual group headers) — `admin_tools.dart:2084` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:160`

- [ ] [MAJOR] Permission flags order is wrong: Dart places `embed_links` (Send links) as the first item in `_otherFlags`, while AyuGram nests `EmbedLinks` inside the media group alongside `SendPolls`; `AddParticipants`, `CreateTopics`, `PinMessages`, `EditRank`, `ChangeInfo` follow — the send-links/send-polls split from the media group is a behavioral discrepancy — `admin_tools.dart:776` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:72`

- [ ] [MAJOR] Permissions flag dependency chain is incomplete: Dart only handles `embed_links → send_plain`; AyuGram's `Dependencies(ChatRestrictions)` additionally enforces stickers↔gifs, stickers↔games, stickers↔inline, and every send_* → view_messages — all those cascades are missing — `admin_tools.dart:841` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:264`

- [ ] [MAJOR] `edit_rank` is listed as a user-restriction permission flag in `_otherFlags`; AyuGram's `ChatRestriction::EditRank` exists but is in the second group with `ChangeInfo`, not alongside poll/invite flags, and is only present when `options.isUserSpecific` — `admin_tools.dart:783` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:98`

- [ ] [MAJOR] Auto-Translation toggle in `_buildSettingsSection()` is rendered as a non-functional switch (`Switch(value: false, onChanged: (_) => onTap())`) — it always shows as OFF and is not backed by any loaded state; AyuGram's `fillAutoTranslateButton()` reads `channel->autoTranslation()` as initial state — `admin_tools.dart:401` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1236`

- [ ] [MAJOR] Sign Messages toggle is also rendered as `Switch(value: false, onChanged: (_) => onTap())` — always shows OFF, not loaded from channel state; AyuGram reads `channel->addsSignature()` — `admin_tools.dart:410` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1290`

- [ ] [MAJOR] Edit peer info save does not save photo even when `_avatarRemoved = true`; AyuGram's save stage queue includes `savePhoto()` which explicitly calls the photo-remove API — `admin_tools.dart:599` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:2255`

- [ ] [MAJOR] Edit peer info save does not save discussion link, forwards, join-to-write, request-to-join, history visibility, forum toggle, auto-translate, or signatures — it only saves title and description; AyuGram's `save()` runs 13 sequential save stages covering all changed fields — `admin_tools.dart:599` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:2234`

- [ ] [MAJOR] Description load uses `engine.getUserProfile()` passing the *chat ID* as user ID — this is semantically wrong for a group/channel; AyuGram loads the description from `_peer->about()` (already present in the peer object) before opening the box — `admin_tools.dart:70` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:769`

- [ ] [MAJOR] `_EditPeerInfoBox` does not check `canEditInformation()` before rendering editable fields; AyuGram skips photo/title/description entirely when the current user lacks that right — `admin_tools.dart:120` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:842`

- [ ] [MAJOR] Pending join requests button is entirely absent from the admin controls section; AyuGram's `fillPendingRequestsButton()` shows this button when `pendingRequestsCount > 0` — `admin_tools.dart:424` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1759`

- [ ] [MAJOR] Recent Actions (Admin Log) button is missing from the edit peer info screen admin controls section; AyuGram adds it when `hasRecentActions = channel->hasAdminRights() || channel->amCreator()` — `admin_tools.dart:424` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1651`

- [ ] [MAJOR] Reactions button is missing from the edit peer info screen; AyuGram adds it via `editReactions()` with boost-level gating for channels — `admin_tools.dart:424` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1512`

- [ ] [MAJOR] Peer Color button is missing from the edit peer info screen; AyuGram adds it via `fillColorIndexButton()` when `canEditColorIndex = channel->canEditEmoji()` — `admin_tools.dart:354` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1203`

- [ ] [MAJOR] Direct Messages pricing button is missing from the channel edit screen; AyuGram adds it via `fillDirectMessagesButton()` for broadcast channels that can edit information — `admin_tools.dart:354` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1088`

- [ ] [MAJOR] Invite Links button count label is always empty string `''`; AyuGram reactively streams `peer->session().api().inviteLinks().myLinks(peer).count` and shows it as the button badge — `admin_tools.dart:448` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1561`

- [ ] [MAJOR] Admin count displayed in the Administrators button is computed from a locally-passed `members` list (`widget.members?.where(…).length`) which may be `null` or stale; AyuGram streams a live `AdminsCountValue` from the data layer — `admin_tools.dart:426` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1596`

- [ ] [MAJOR] Permissions button count label is always empty; AyuGram shows the fraction `X/Y` of active restrictions (e.g., `"3/14"`) computed from `RestrictionsCountValue` — `admin_tools.dart:432` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1542`

- [ ] [MAJOR] Restriction duration picker in `_EditRestrictedBox` offers only "Ban forever / 1 day / 1 week / Custom"; AyuGram's `setRestrictUntil()` offers 1 day, 1 week, 1 month options plus custom — `admin_tools.dart:1914` ← `AyuGram/boxes/peers/edit_participant_box.cpp:806`

- [ ] [MAJOR] `_EditRestrictedBox` does not load the individual member's existing ban/restriction duration (`_oldRights.until`); the duration picker always defaults to "Ban forever"; AyuGram receives `ChatRestrictionsInfo _oldRights` in the constructor — `admin_tools.dart:1447` ← `AyuGram/boxes/peers/edit_participant_box.cpp:700`

- [ ] [MAJOR] `_EditRestrictedBox` has a `_rankCtrl` text field labeled "Custom Title" for restricted users, but AyuGram's `EditRestrictedBox` only shows the rank/tag field when `peer()->canManageRanks()` is true; the field is always shown unconditionally in the Dart code — `admin_tools.dart:1971` ← `AyuGram/boxes/peers/edit_participant_box.cpp:775`

- [ ] [MAJOR] "Restrict user" box title is hardcoded as "Restrict User" regardless of context; AyuGram uses `tr::lng_rights_user_restrictions()` — `admin_tools.dart:1677` ← `AyuGram/boxes/peers/edit_participant_box.cpp:727`

- [ ] [MAJOR] Admin box does not conditionally show or load initial rights from the member's existing `customRank`; `_rankCtrl` is initialized to an empty string `TextEditingController()`, discarding any existing rank value from `widget.member.customRank` — `admin_tools.dart:2076` ← `AyuGram/boxes/peers/edit_participant_box.cpp:531`

- [ ] [MAJOR] `_EditAdminBox` "Add as Admin" checkbox is only shown; in AyuGram this checkbox is exclusively for *bots being added* (`_addingBot && !_addingBot->existing`); for regular users the admin controls are always visible — `admin_tools.dart:2423` ← `AyuGram/boxes/peers/edit_participant_box.cpp:361`

- [ ] [MAJOR] Member list "Add Admin" / "Add Exception" / "Add Banned" buttons show a toast instead of opening a user picker; as a result admins cannot be added from this screen at all — `admin_tools.dart:4793` ← `AyuGram/boxes/peers/edit_participants_box.cpp:89`

# advanced_settings_screen — 20 issues (15 CRITICAL, 5 MAJOR)

## advanced_settings_screen — Advanced Settings (§14.7)

- [ ] [CRITICAL] `_AutoDownloadBox` "Save" button is a stub — calls `Navigator.of(context).pop()` with no data persistence; all slider/toggle state is discarded on close; auto-download settings are never written to AppState or engine — `advanced_settings_screen.dart:1461` ← `settings_advanced.cpp:225-255` (AyuGram opens `Box<AutoDownloadBox>(session, Source::User)` which saves to `Data::AutoDownload`)

- [ ] [CRITICAL] `_AutoDownloadBox` initializes with hardcoded defaults instead of loading from engine — `_photos = true`, `_files = false`, `_downloadLimit = 10`, `_videoMessages = true`, `_videos = true`, `_gifs = true`, `_autoPlayLimit = 50` are never read from AppState or bridge — `advanced_settings_screen.dart:1326-1333` ← `settings_advanced.cpp:225-255` (AyuGram reads live `Data::AutoDownload` settings per Source)

- [ ] [CRITICAL] `_LocalStorageBox` tag sizes are all hardcoded zeros — `_tagSizes = List<int>.filled(6, 0)` is never populated by an engine call; "Images", "Stickers", "Voice Messages" etc. always show "0 B" instead of real cache sizes — `advanced_settings_screen.dart:1575` ← `settings_advanced.cpp:164-170` (AyuGram calls `LocalStorageBox::Show(controller)` which reads real cache statistics)

- [ ] [CRITICAL] `_LocalStorageBox` sliders (total size, media cache, keep media) are never persisted — "OK" button at close only calls `Navigator.of(context).pop()` without saving `_totalSizeIdx`, `_mediaSizeIdx`, or `_timeLimitIdx` to AppState or engine — `advanced_settings_screen.dart:1703` ← `settings_advanced.cpp:164-170`

- [ ] [CRITICAL] `_LocalStorageBox` "Clear All" and per-tag "Clear" buttons don't call any engine method — they only zero out local widget state (`_tagSizes[tagIdx] = 0`); no actual cache files are deleted — `advanced_settings_screen.dart:1737-1744,1824` ← `settings_advanced.cpp:164-170`

- [ ] [CRITICAL] `_ProxiesBox` proxy list always empty on open — `final List<_ProxyEntry> _proxies = []` is never populated from AppState or engine; all configured proxies are invisible — `advanced_settings_screen.dart:2195` ← `boxes/connection_box.cpp` (AyuGram loads full proxy list from `ProxiesBoxController`)

- [ ] [CRITICAL] `_ProxiesBox` proxies never actually tested — all entries are created with `status = _ProxyStatus.checking` (default) and no async ping/test logic exists anywhere; status never changes from "Checking..." — `advanced_settings_screen.dart:2160-2169` ← `boxes/connection_box.cpp` (AyuGram's `ProxiesBoxController` fires real connectivity checks and updates status reactively)

- [ ] [CRITICAL] `_ProxiesBox` proxy selection never applied to actual MTP connection — `_syncToAppState()` only writes `appState.proxyMode` in Dart memory; no bridge call is made to switch the live network connection — `advanced_settings_screen.dart:2206-2213` ← `settings_advanced.cpp:126-131` (AyuGram calls `ProxiesBoxController::CreateOwningBox(account)` which wires directly to `MTP::Instance`)

- [ ] [CRITICAL] `_ProxiesBox` IPv6 toggle and proxyForCalls toggle are hardcoded to `false` and never loaded from or saved to AppState or engine — `advanced_settings_screen.dart:2194,2197` ← `boxes/connection_box.cpp` (AyuGram persists these in `Core::App().settings()`)

- [ ] [CRITICAL] "Update UniClient" button calls `exit(0)` instead of installing update — pressing "Update UniClient" when a new version is available terminates the process without downloading or applying anything — `advanced_settings_screen.dart:245` ← `settings_advanced.cpp:1139-1144` (`Core::checkReadyUpdate(); Core::Restart();`)

- [ ] [CRITICAL] All sections missing subsection title headers — every `_build*` method renders items directly with no visible section label; AyuGram's `builder.addSubsectionTitle()` renders uppercase labels ("DATA AND STORAGE", "AUTOMATIC MEDIA DOWNLOAD", "WINDOW TITLE", etc.) that are entirely absent — `advanced_settings_screen.dart:43-68` ← `settings_advanced.cpp:99-103,217-221,263-267,367-371,421-426,830-834,886-890,962-967`

- [ ] [CRITICAL] "Manage Dictionaries" dialog is a static stub — shows the text "Spellchecker dictionaries are provided by the system. Install language packs through your operating system settings." with only a Close button; AyuGram opens `Box<Ui::ManageDictionariesBox>(session)` with real per-language dictionary download/install/delete UI — `advanced_settings_screen.dart:982-1034` ← `settings_advanced.cpp:932-941`

- [ ] [CRITICAL] Screen reader section always rendered regardless of whether a screen reader is detected — `_buildScreenReader()` always returns the toggle row; AyuGram (lines 1184–1188) only builds this section when `detected && disabled` i.e. a screen reader is active but the disable-for-screen-reader mode is OFF — `advanced_settings_screen.dart:1036-1054` ← `settings_advanced.cpp:1184-1188`

- [ ] [CRITICAL] Connection type right-label reads stale AppState enum instead of live MTP transport — `_connectionTypeLabel(appState)` returns hardcoded strings like "Using TCP" from `appState.proxyMode`; AyuGram reads the actual live transport name from `account->mtp().dctransport()` (e.g. "WebSocket" or "TCP") and reacts to `connectionTypeChanges()` events — `advanced_settings_screen.dart:103-111` ← `settings_advanced.cpp:105-126`

- [ ] [CRITICAL] `ExperimentalSettingsBox` flags are not wired to any actual runtime behavior — 14 flags (`tabbed_emoji_panel`, `forum_chat_list`, etc.) are saved to `appState.experimentalFlags` but nothing in the codebase reads these flags to change behavior; the entire box is cosmetic UI state — `advanced_settings_screen.dart:3440-3455,3473-3493` ← `settings/settings_experimental.cpp` (AyuGram's experimental settings call real feature toggles through `Core::App().settings()`)

- [ ] [MAJOR] `_AutoDownloadBox` title shows the raw source string ("In private chats") instead of a proper section header — AyuGram's `AutoDownloadBox` has a full settings panel with a "Private Chats / Groups / Channels" header and section subsystem — `advanced_settings_screen.dart:1386-1395` ← `boxes/auto_download_box.cpp`

- [ ] [MAJOR] Spellchecker auto-download dictionaries and "Manage Dictionaries" rows show for system spellchecker — both rows appear when `appState.spellcheckerEnabled` is true; AyuGram gates them behind `if (!isSystem)` — only the custom (Hunspell) spellchecker exposes download/manage options — `advanced_settings_screen.dart:943-963` ← `settings_advanced.cpp:912-942`

- [ ] [MAJOR] "Install beta versions" toggle visibility logic is wrong — Dart shows it when `_updateState != _UpdateState.checking`; AyuGram shows it only when NOT running an alpha build (`cAlphaVersion() ? nullptr : ...`) — `advanced_settings_screen.dart:209-217` ← `settings_advanced.cpp:1017-1025`

- [ ] [MAJOR] "Use system window frame" / native frame checkbox placed in wrong section — Dart puts it in System Integration (`_buildSystemIntegration`, line 561, Linux-only); AyuGram places it in the Window Title section (`BuildWindowTitleSection`, line 329–347) gated by `Ui::Platform::NativeWindowFrameSupported()` (not Linux-only) — `advanced_settings_screen.dart:561-568` ← `settings_advanced.cpp:329-348`

- [ ] [MAJOR] Windows "Close to taskbar" behavior completely missing — `_buildWindowCloseBehavior` returns empty for non-Linux; AyuGram (lines 585–620) adds a `CloseToTaskbar` checkbox inside `BuildSystemIntegrationSection` specifically for Windows, shown only when `!Core::App().tray().has()` — `advanced_settings_screen.dart:522-543` ← `settings_advanced.cpp:585-620`

# bridge_ffi — FFI Bridge Infrastructure

> **Note:** `bridge_ffi.dart` is a pure FFI infrastructure file (Dart→Go shared library bridge).
> AyuGram Desktop is a monolithic C++ application with no FFI layer; no direct AyuGram equivalent
> exists. Findings are therefore cross-referenced against the Go-side FFI export layer
> (`go/cmd/bridge/main.go`) which is the authoritative contract this file must satisfy.

---

- [ ] [CRITICAL] `NativeCallable.listener` is never closed — `_eventCallable.close()` is missing from `dispose()`. `NativeCallable.listener` allocates a native trampoline in the Go-callable address space; failing to call `.close()` leaks that native slot permanently every time the bridge is disposed and re-initialized (e.g. account switch, app restart without process exit). — `bridge_ffi.dart:162-163` ← `go/cmd/bridge/main.go:53-68` (callback registration / teardown contract)

- [ ] [CRITICAL] `assert` guards replaced by no-ops in release builds — Lines 70 and 76 use `assert(_initialized, ...)` to guard `call()` and `callAsync()`. Dart asserts are stripped in profile/release mode. An uninitialized bridge call in production silently dereferences a null `_callWithLen` function pointer, crashing the app with no diagnostic message instead of a readable `StateError`. — `bridge_ffi.dart:70` and `bridge_ffi.dart:76` ← `go/cmd/bridge/main.go:28` (BridgeCallWithLen must not be called before BridgeSetEventCallback wires the engine)

- [ ] [MAJOR] `callAsync` spawns a full new `Isolate.run()` per call — Every async FFI call creates and tears down a Dart isolate. While `DynamicLibrary.open` cheaply reuses the OS handle, Dart isolate creation involves heap allocation, event loop setup, and port wiring (~hundreds of µs overhead per call). For message sends, read receipts, or rapid state polling this produces queued isolate creation storms that block the UI thread's event loop indirectly via the scheduler. A persistent worker isolate with a `ReceivePort`/`SendPort` channel, or Dart's `isolate.run` kept warm, is the correct pattern. — `bridge_ffi.dart:75-79` ← `go/cmd/bridge/main.go:28-38` (BridgeCallWithLen is the hot path called for every engine method)

- [ ] [MAJOR] `_globalEventController` broadcast stream is never closed — The module-level `StreamController<Uint8List>.broadcast()` at line 146 is created once and never closed, not even in `dispose()`. If the bridge is torn down while listeners are active (e.g. during logout), those listeners receive no `done` event and leak subscriptions. The event controller should be closed in `dispose()` and re-created on `init()`. — `bridge_ffi.dart:146` and `bridge_ffi.dart:81-85` ← `go/cmd/bridge/main.go:53-55` (BridgeSetEventCallback(nil) is called on dispose — Go side is wired correctly; Dart side is not)

- [ ] [MAJOR] Linux library fallback `'libcores.so'` relies on `LD_LIBRARY_PATH` — When the bundle path (`$exeDir/lib/libcores.so`) does not exist, `_findLibraryPath()` falls back to the bare name `'libcores.so'` (line 92). `DynamicLibrary.open('libcores.so')` will then search `LD_LIBRARY_PATH` and system library paths. In a sandboxed Flatpak/Snap or on Android-like environments this silently fails with an opaque `DynamicLibraryLoadException` rather than a useful message. The fallback should either throw `FileSystemException` with the attempted path, or check a second well-known location (e.g. adjacent to the executable). — `bridge_ffi.dart:91-92` ← `go/cmd/bridge/main.go:1-3` (build output is `libcores.so` co-located with the bundle)

# auth_screen — Authentication Screen Audit

## Findings

- [ ] [CRITICAL] Signup avatar bytes collected in `_signupAvatarBytes` but never passed to engine — `_submit()` sends only `'$firstName\n$lastName'` with no avatar payload — `auth_screen.dart:122-129` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_signup.cpp` (UserpicButton upload in constructor)

- [ ] [CRITICAL] Forgot-password recovery switches to recovery mode locally but never requests recovery code from server — `_handleForgotPassword` sets `_isRecoveryMode = true` with no `authState.requestPasswordRecovery()` call, so no `MTPauth_RequestPasswordRecovery` is dispatched and the recovery email is never sent — `auth_screen.dart:762-771` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_password_check.cpp:306-313`

- [ ] [CRITICAL] "Reset Account" dialog is a stub — confirm button calls only `Navigator.of(ctx).pop()`, no engine call to delete/reset account — `auth_screen.dart:374-378` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_password_check.cpp:334-348` (`showResetButton()` → `MTPaccount_DeleteAccount`)

- [ ] [CRITICAL] Voice-call countdown timer is a stub — when `_callSecondsLeft` reaches 0, only `_calling = true` is set and "Calling..." text appears; no `auth.resendCode` or call-request engine method is invoked — `auth_screen.dart:1443-1449` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_code.cpp:52` (call timer triggers real MTP request)

- [ ] [MAJOR] "Didn't get the code?" dialog is incomplete — only "Edit Phone Number" + "OK" actions; real desktop has resend-via-SMS and resend-via-call options that dispatch `auth.resendCode`; no resend engine call anywhere in this dialog — `auth_screen.dart:137-175` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_code.cpp:71` (resend fallback handling)

- [ ] [MAJOR] Language picker uses a hardcoded static list; `langpack.getLanguages` is never called — selection calls `addRecentLanguage` only, no locale is applied and no server fetch happens — `auth_screen.dart:1963-1984` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_widget.cpp` (language list fetched from server)

- [ ] [MAJOR] Cover header uses `Icons.send_rounded` (single Material icon) instead of the 4-layer Telegram paper-plane SVG (`introCoverIcon` composed of `intro_plane_trace`, `intro_plane_inner`, `intro_plane_outer`, `intro_plane_top` layers) — `auth_screen.dart:1285-1292` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro.style:16-23`

- [ ] [MAJOR] QR code center logo uses `Icons.send` instead of the dedicated `introQrPlane` SVG icon (`icon {{ "intro_qr_plane", activeButtonFg }}`) — `auth_screen.dart:890-898` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro.style:203`

- [ ] [MAJOR] QR panel missing top offset — spec defines `introQrTop: -18px` (negative offset so QR overlaps content area), Dart uses no offset — `auth_screen.dart:831` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro.style:179`

- [ ] [MAJOR] Phone number formatter uses naïve every-3-digits spacing; AyuGram uses libphonenumber country-specific patterns (e.g. US: `(xxx) xxx-xxxx`, UK: `xxxx xxxxxx`) — `auth_screen.dart:2148-2183` ← `AyuGramDesktop/Telegram/SourceFiles/intro/intro_phone.cpp` (PhonePartInput with country-aware formatting)

# ayu_appearance_page — Audit

## ayu_appearance_page — Section order completely wrong

- [ ] [CRITICAL] Entire section order is inverted vs AyuGram: C++ builds App Icon → Avatar Corners → Appearance toggles → Chat Folders → Tray → Drawer; Dart builds Appearance toggles → Avatar Corners → Chat Folders → Tray → Drawer → App Icon (App Icon is last instead of first) — `ayu_appearance_page.dart:26-195` ← `settings_appearance.cpp:386-393`

- [ ] [CRITICAL] `hideNotificationBadge` toggle is placed in the Chat Folders section (line 80) but in AyuGram it lives inside `BuildAppIcon`, rendered under the App Icon subsection title — `ayu_appearance_page.dart:80-86` ← `settings_appearance.cpp:66-81`

## ayu_appearance_page — Drawer elements ordering wrong

- [ ] [CRITICAL] Drawer toggle order is wrong. AyuGram order: Saved Messages → LRead → SRead → Night Mode → Ghost Mode → Streamer. Dart order: Saved Messages → Night Mode → Ghost Mode → LRead → SRead → Streamer. LRead and SRead appear after Ghost Mode in the Dart, but they should come before Night Mode — `ayu_appearance_page.dart:147-183` ← `settings_appearance.cpp:329-373`

## ayu_appearance_page — Drawer toggle icons completely absent

- [ ] [CRITICAL] Every drawer toggle in AyuGram has a leading icon (menuIconProfile, menuIconBot, menuIconGroups, menuIconChannel, menuIconUserShow, menuIconPhone, menuIconSavedMessages, ayuLReadMenuIcon, ayuSReadMenuIcon, menuIconNightMode, ayuGhostIcon, ayuStreamerModeMenuIcon). The Dart `_ToggleRow` widget has no icon parameter or rendering at all — `ayu_appearance_page.dart:992-1049` ← `settings_appearance.cpp:286-373`

## ayu_appearance_page — Font selector uses hardcoded presets instead of system fonts

- [ ] [CRITICAL] AyuGram's `FontSelectorBox` calls `QFontDatabase::families()` to enumerate every font installed on the system, shows them in a searchable scrollable list with radio buttons and keyboard navigation. Dart's `_FontSelectorBox` uses a hardcoded 11-item preset list (`_presets`) with no system font enumeration, no search, and no keyboard navigation — `ayu_appearance_page.dart:564-569` ← `font_selector.cpp:204-218`

- [ ] [CRITICAL] AyuGram shows a "Restart Required" confirmation box (`tr::lng_settings_need_restart`) with "Restart Now" / "Restart Later" buttons and actually calls `Core::Restart()` after font is saved. Dart's `_save()` just calls `widget.onSaved()` and pops the dialog with no restart prompt — `ayu_appearance_page.dart:697-700` ← `font_selector.cpp:857-868`

- [ ] [CRITICAL] AyuGram's font selector box has a "Reset" left button (`tr::ayu_BoxActionReset`) that clears the font and triggers restart. Dart has no reset button — `ayu_appearance_page.dart:548-700` ← `font_selector.cpp:871-888`

## ayu_appearance_page — App Icon picker shows drawn shapes instead of real assets

- [ ] [CRITICAL] AyuGram's `IconPicker` loads real icon image assets via `AyuAssets::loadPreview(iconName)` (cached in `_cachedIcons`). Dart's `_AppIconPicker` uses `CustomPaint` with hand-drawn geometric approximations for each icon — colored circles, stars, lines — not actual app icon images — `ayu_appearance_page.dart:780-990` ← `icon_picker.cpp:113-118`

- [ ] [CRITICAL] AyuGram's icon picker applies the icon change immediately when clicked (`applyIcon()` at line 177: `Window::OverrideApplicationIcon`, `Core::App().refreshApplicationIcon()`, `Core::App().tray().updateIconCounters()`). Dart's picker only calls `appState.setAppIcon(name)` with no actual icon application to the running app — `ayu_appearance_page.dart:746` ← `icon_picker.cpp:42-52, 169-181`

## ayu_appearance_page — Avatar preview rendering wrong

- [ ] [MAJOR] AyuGram's preview paints against `st::windowBg` (flat, full-width dialog row, `setFixedHeight(row.height)`). Dart renders a rounded card Container (8px radius, custom background color) — `ayu_appearance_page.dart:432-475` ← `avatar_corners_preview.cpp:40-78`

- [ ] [MAJOR] AyuGram preview shows the "Extera Official" badge icon painted next to the channel name (`st::dialogsExteraOfficialIcon.icon.paint`). Dart renders no badge — `ayu_appearance_page.dart:455-462` ← `avatar_corners_preview.cpp:71-73`

- [ ] [MAJOR] AyuGram preview subtext is `"Better late than never"` (hardcoded). Dart shows `"Preview of avatar corners"` — `ayu_appearance_page.dart:466` ← `avatar_corners_preview.cpp:77`

- [ ] [MAJOR] AyuGram preview click opens the peer via `_controller->showPeerByLink(...)` (in-app navigation). Dart calls `Process.run('xdg-open', ['https://t.me/AyuGramReleases'])` which opens an external browser and won't work on Windows/Mac/mobile — `ayu_appearance_page.dart:430` ← `avatar_corners_preview.cpp:97-101`

## ayu_appearance_page — Avatar corners slider behavior wrong

- [ ] [MAJOR] AyuGram slider's `onChanged` immediately calls `AyuSettings::getInstance().setAvatarCorners(val)` AND `previewRaw->update()`, updating the preview in real-time during drag. Dart's `onChanged` only updates `_localCorners` local state and the preview repaints from that, but does NOT commit to `appState` during drag — `ayu_appearance_page.dart:305` ← `settings_appearance.cpp:164-170`

- [ ] [MAJOR] AyuGram's `onFinalChanged` calls `ShowRestartPrompt(controller)` — a standard restart dialog. Dart's `onChangeEnd` shows a custom `showConfirmBox` with "Apply"/"Cancel" buttons. The "Cancel" option rolls back the slider visually. AyuGram does NOT show a cancel-able confirm box — it applies immediately and just asks about restart — `ayu_appearance_page.dart:308-321` ← `settings_appearance.cpp:170-174`

## ayu_appearance_page — Missing divider text after singleCornerRadius

- [ ] [MAJOR] AyuGram adds `builder.addDividerText(tr::ayu_SingleCornerRadiusDescription())` below the single corner radius toggle (line 184). Dart has no divider text/description below this toggle — `ayu_appearance_page.dart:326-333` ← `settings_appearance.cpp:183-186`

## ayu_appearance_page — General section title missing

- [ ] [MAJOR] AyuGram calls `builder.addSubsectionTitle(tr::ayu_CategoryAppearance())` at the start of `BuildAppearance` (line 191). Dart starts the section with a toggle directly (no section header for the general appearance block) — `ayu_appearance_page.dart:26-33` ← `settings_appearance.cpp:188-191`

# ayu_chats_page — AyuGram Chats Settings Page

## Summary
`ayu_chats_page.dart` implements the AyuGram "Chats" settings page (not the chat list).
Ground truth: `/home/nako/Documents/AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp`

---

- [ ] [CRITICAL] Context menu option values are semantically inverted: Dart maps `{0: 'Shown', 1: 'Hidden', 2: 'Extended Menu'}` but AyuGram's `ContextMenuVisibility` enum is `Hidden=0, Visible=1, VisibleWithModifier=2`. Every context menu setting stores 0 meaning "Shown" in Dart but "Hidden" in the engine — data corruption on every save/load — `ayu_chats_page.dart:143` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:301-305`

- [ ] [CRITICAL] Entire "Marks" subsection is missing from UI: `replaceBottomInfoWithIcons` toggle (the main switch for icons vs text), `deletedMark` text-input field (default `"🧹"`), `editedMark` text-input field, and `semiTransparentDeletedMessages` toggle are all passed as props into `_BubbleRadiusSection` for the preview but have zero UI controls — users cannot change these four settings — `ayu_chats_page.dart:107-117` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:132-233`

- [ ] [CRITICAL] Wide Multiplier minimum is wrong: Dart uses `min: 0.5` but AyuGram's range is `1.00–4.00` (step 0.05, 61 divisions). Dart allows values below 1.0 that the engine does not support and uses 70 divisions instead of 60 — `ayu_chats_page.dart:321-323` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:274-289`

- [ ] [MAJOR] `hideFastShare` is placed in the "Channels" section (Dart line 92) but AyuGram places it in the "Marks" sub-section of Messages (`BuildMarks`, line 206). It is semantically unrelated to channel settings — `ayu_chats_page.dart:92-96` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:206-212`

- [ ] [MAJOR] Section ordering does not match AyuGram. AyuGram order: Stickers&Emoji → RecentStickersLimit → GroupsAndChannels → Marks → WideMessagesMultiplier → ContextMenuElements → MessageFieldElements → MessageFieldPopups. Dart order: Stickers&Emoji+recentStickersCount → Channels → Messages(wideMultiplier+bubbleRadius+removeTail+simpleQuotes) → ContextMenu → MessageField → Popups. `recentStickersCount` is merged into S&E instead of its own section, and Marks is split/merged incorrectly — `ayu_chats_page.dart:21-212` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:453-472`

- [ ] [MAJOR] Message preview (`_MessagePreview`) always renders BOTH a deleted mark AND an edited mark simultaneously regardless of state — a real message is either deleted or edited, never both. AyuGram's preview widget shows only the relevant mark(s) based on active settings state — `ayu_chats_page.dart:683-717` ← `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_chats.cpp:141-152`

# ayu_filters_page — Filters Settings Page

- [ ] [CRITICAL] Shadow ban row shows hardcoded `"User $id"` label and fixed `'U'` avatar initial instead of resolved peer name and real userpic — real peer must be looked up via `getPeerFromDialogId` and fall back to `"UNKNOWN (ID: ...)"` — `ayu_filters_page.dart:853-854` ← `ayu/ui/settings/filters/per_dialog_filter.cpp:35-58`

- [ ] [CRITICAL] Per-dialog filter entries on the main page display raw dialog ID strings (`dId` from `filterEngine.dialogIdsWithFilters()`) instead of resolved peer names — AyuGram looks up the actual peer via `getPeerFromDialogId` and falls back to `"UNKNOWN (ID: N)"` only when peer is absent from session data — `ayu_filters_page.dart:89` ← `ayu/ui/settings/filters/per_dialog_filter.cpp:35-40`

- [ ] [CRITICAL] Import flow applies changes immediately with no confirmation dialog — AyuGram calls `prepareChanges()`, then shows a `ConfirmBox` with a full change summary (new/removed/updated filter counts, exclusion counts, peers to resolve) before applying — `ayu_filters_page.dart:1183-1227` ← `ayu/features/filters/filters_utils.cpp:417-432`

- [ ] [CRITICAL] Import JSON parsing ignores `removeFiltersById`, `removeExclusions`, and `peers` fields entirely — AyuGram processes all five fields (`filters`, `exclusions`, `removeFiltersById`, `removeExclusions`, `peers`) for a complete diff-and-merge; Dart only reads `filters` and `exclusions`, so any import payload that removes filters or resolves peer hints is silently dropped — `ayu_filters_page.dart:1192-1197` ← `ayu/features/filters/filters_utils.cpp:786-855`

- [ ] [CRITICAL] Export JSON omits `removeFiltersById`, `removeExclusions`, and `peers` fields — AyuGram always emits all five top-level keys and populates `peers` with `{dialogId: username}` entries for known peers so a fresh session can resolve them via API; Dart export only emits `version`, `filters`, `exclusions` — `ayu_filters_page.dart:1231-1237` ← `ayu/features/filters/filters_utils.cpp:457-529`

- [ ] [CRITICAL] Toggling `filtersEnabled`, `filtersEnabledInChats`, or `hideFromBlocked` only calls the setter — no cache rebuild or propagation event is fired; AyuGram calls `FiltersCacheController::rebuildCache()` and `FiltersCacheController::fireUpdate()` after every toggle so the active message-filtering pipeline picks up the change immediately — `ayu_filters_page.dart:31-44` ← `ayu/ui/settings/settings_filters.cpp:60-66`

- [ ] [MAJOR] "Select Chat" opens a `ListView` built from the already-loaded `ChatState.chats` — AyuGram uses `Window::ShowChooseRecipientBox` (Telegram's full native peer-picker with search, avatars, and all peer types including bots, groups, and channels) so any peer reachable in the session can be picked, not just those already cached locally — `ayu_filters_page.dart:165-229` ← `ayu/ui/settings/settings_filters.cpp:196-219`

- [ ] [MAJOR] Default `caseInsensitive` for a new filter is `false` in Dart; AyuGram defaults it to `true` so new filters are case-insensitive out of the box — `ayu_filters_page.dart:900` ← `ayu/ui/settings/filters/edit_filter.cpp:141-144`

- [ ] [MAJOR] Regex validation uses Dart's `RegExp` (RE2/Irregexp engine) instead of ICU; AyuGram validates and matches with `icu::RegexPattern::compile` — the two engines differ in lookahead/lookbehind support and Unicode category syntax, so a pattern that validates on one can reject or misbehave on the other — `ayu_filters_page.dart:913-920` ← `ayu/ui/settings/filters/edit_filter.cpp:57-99`

# ayu_general_page — AyuGram General Settings Audit

Ground truth: `AyuGramDesktop/Telegram/SourceFiles/ayu/ui/settings/settings_general.cpp`

- [ ] [MAJOR] Translation Provider button missing BETA badge — `ayu_general_page.dart:31-41` ← `settings_general.cpp:113-115`
  AyuGram calls `ayu.addBetaBadge(button)` on the Translation Provider button. Dart `addChooseButton` has no `showBetaBadge` argument, so the badge never renders.

- [ ] [MAJOR] "Disable Stories" toggle missing restart prompt — `ayu_general_page.dart:51-52` ← `settings_general.cpp:170-175`
  AyuGram setter: `AyuSettings::getInstance().setDisableStories(enabled); ShowRestartPrompt(controller);` — change is applied then user is notified to restart. Dart only calls `appState.setDisableStories(v)` with no restart notification, so the user never learns they need to restart for the change to take effect.

- [ ] [MAJOR] Filter Zalgo behavioral inversion — `ayu_general_page.dart:96-108` ← `settings_general.cpp:217-230`
  AyuGram: toggle flips immediately → `setFilterZalgo(enabled)` applied → `ShowRestartPrompt(controller)` shown as a post-apply notification. Dart: toggle visually flips → `showConfirmBox` blocks the change behind an "Apply/Cancel" dialog → setting only applied on confirm. The Dart approach inverts the UX: the toggle appears to flip before the user confirms, leaving the widget in a visually inconsistent state if the user cancels (toggle shows new value, `appState.filterZalgo` still holds old value).

# ayugram_settings_screen — AyuGram Settings Hub

- [ ] [CRITICAL] Logo renders as a colored Material-icon circle instead of the real app logo image. C++ loads `AyuAssets::currentAppLogoPad()` (actual PNG/image asset) and draws it scaled to `st::settingsCloudPasswordIconSize`. Dart fakes it with a color-filled circle + a Material icon (e.g. `Icons.send` for the default theme) — no image asset loaded at all — `ayugram_settings_screen.dart:65-80` ← `settings_main.cpp:41-65`

- [ ] [CRITICAL] Channel and Chats links open in the system browser via `xdg-open` instead of navigating in-app. C++ calls `controller->showPeerByLink({ .usernameOrId = "ayugram" })` and `"ayugramchat"` to open the peer inside the running Telegram session. Dart fires `Process.run('xdg-open', ['https://t.me/ayugram'])` which lands in a browser — `ayugram_settings_screen.dart:189-196` ← `settings_main.cpp:149-164`

- [ ] [CRITICAL] `_openUrl` uses `Process.run('xdg-open', ...)` which is Linux-only and silently fails on Android, Windows, macOS, and Web builds. All URL opening (Translate, Documentation, and the two Telegram links above) should use Flutter's `url_launcher` / `launchUrl()` for cross-platform support — `ayugram_settings_screen.dart:245-247` ← `settings_main.cpp:171-185`

- [ ] [MAJOR] Category buttons render colored rounded-square backgrounds behind each icon (e.g. `Color(0xFF6B72D5)` for AyuGram, `Color(0xFF5288C1)` for Filters, etc.). The C++ `addSectionButton` renders a standard Telegram settings row with a flat icon — no colored container exists anywhere in the C++ source. These decorative backgrounds are invented, not from the AyuGram spec — `ayugram_settings_screen.dart:125-168` ← `settings_main.cpp:103-133`

- [ ] [MAJOR] All six category button icons deviate from the C++ originals: AyuGram uses `Icons.emoji_emotions` (C++: `st::menuIconGroupReactions`), General uses `Icons.visibility` (C++: `st::menuIconShowAll`), Filters uses `Icons.filter_alt` (C++: `st::menuIconTagFilter`). The palette/chat/star icons are approximately correct but not sourced from `st::menuIcon*` equivalents — `ayugram_settings_screen.dart:126,135,142` ← `settings_main.cpp:106,110,114`

- [ ] [MAJOR] Documentation link uses `Icons.description`; C++ uses `st::menuIconIpAddress` (a network/IP icon). These are semantically and visually different — `ayugram_settings_screen.dart:209` ← `settings_main.cpp:179`

- [ ] [MAJOR] "Ghost Mode active" subtitle on the AyuGram category button does not exist in the C++ source. `addSectionButton` has no subtitle field — it is a plain title+icon row. This is an invented UI element not present in AyuGram Desktop — `ayugram_settings_screen.dart:129` ← `settings_main.cpp:103-107`

- [ ] [MAJOR] Description text is hardcoded English: `'Telegram Desktop fork focused on customization and ToS-breaking features.'`. C++ uses `tr::ayu_SettingsDescription()` which pulls from the localisation system. The string itself happens to match the translation value, but hardcoding breaks i18n and will not update if the upstream string changes — `ayugram_settings_screen.dart:100-106` ← `settings_main.cpp:82-90`

# ayu_other_page — AyuOther Settings Page

- [ ] [CRITICAL] All five crypto wallet addresses are truncated — QR codes generated from them encode garbage/invalid addresses that will misdirect donations. TON: `'UQA4i8U3'` vs full `'UQA4i8U8vP3mYUZSV3KqDQEHPwmhninEqCkkKc7BITQ652de'`; Bitcoin: `'bc1qdk6qq'` vs `'bc1qdk6qq4mzq5yap3fpy0qau3246w3m3uwac9f0xd'`; Ethereum: `'0x405589'` vs `'0x405589857C8DFAb45B2027c68ad1e58877FDa347'`; Solana: `'8ZHQpPxp'` vs `'8ZHQpPxpsdRjsWoBcF1dmvRM5dB6zEhJ3jMBFZjYfyHs'`; Tron: `'TRpbajq3'` vs `'TRpbajq38qU8joThgAfKJLyEPbNjzsdPJ1'` — `ayu_other_page.dart:38,46,54,62,70` ← `settings_other.cpp:154-158`

- [ ] [CRITICAL] "Register URL Scheme" button is a no-op stub — shows a `SnackBar('Done')` without calling any actual OS URL scheme registration. AyuGram calls `Core::Application::RegisterUrlScheme()` — `ayu_other_page.dart:100-105` ← `settings_other.cpp:204-208`

- [ ] [MAJOR] Donate row icons use plain text characters ('B', '💎', '₿', 'Ξ', 'S', 'T') rendered in a tinted container instead of SVG icons from `:/gui/icons/ayu/donates/{name}.svg`. AyuGram uses `QSvgRenderer` to render the actual SVG logo over a rounded background at `st::menuIconLink` size — `ayu_other_page.dart:211` ← `settings_other.cpp:60-117`

- [ ] [MAJOR] Donate QR box is missing the currency SVG icon overlaid at center of the QR code. AyuGram's `MakeQrWithIcon` draws a white ellipse (20% of QR area) then renders the currency SVG inside it. Dart just renders a plain `QrImageView` with no icon — `ayu_other_page.dart:344-350` ← `donate_qr_box.cpp:31-67`

- [ ] [MAJOR] Donate QR box is missing the "Copy" button. AyuGram adds a full-width copy button that copies the address to clipboard and shows a toast (`tr::lng_text_copied`). Dart only has a "Close" button — `ayu_other_page.dart:362-375` ← `donate_qr_box.cpp:148-158`

- [ ] [MAJOR] Donate QR box title should be `tr::lng_group_invite_context_qr()` ("QR Code"), not the currency name. Dart uses the currency name (e.g. "TON") as the dialog title — `ayu_other_page.dart:332-335` ← `donate_qr_box.cpp:78`

- [ ] [MAJOR] "Contact support" link is a separate widget below the description text instead of being inline. AyuGram embeds the `tg://support` link directly inside the `tr::ayu_SupportDescription2` formatted text using `Ui::Text::Link`. Dart renders plain description text then a separate `_ContactSupportLink` widget after it — `ayu_other_page.dart:73-77` ← `settings_other.cpp:161-167`

- [ ] [MAJOR] URL opening uses `Process.run('xdg-open', ...)` which is Linux-only. AyuGram uses `QDesktopServices::openUrl()` which is cross-platform. Flutter equivalent is the `url_launcher` package — `ayu_other_page.dart:30,297` ← `settings_other.cpp:152`

# ayu_section_builder — AyuSectionBuilder utility class

- [ ] [CRITICAL] Beta badge background uses hardcoded orange `0xFFFF9500` instead of theme-reactive `st::windowBgActive` (accent blue); badge will always render orange in both light and dark themes regardless of theme color — `ayu_section_builder.dart:108` ← `settings_ayu_utils.cpp:62` (`p.setBrush(st::windowBgActive)`)

- [ ] [CRITICAL] Beta badge in `_AyuSettingToggle` is inline in a `Row` next to the label text; in AyuGram the badge is an overlay child widget absolutely positioned after `parent->fullTextWidth()` so it floats over the button at the correct x/y offset — `ayu_section_builder.dart:205-219` ← `settings_ayu_utils.cpp:66-76`

- [ ] [CRITICAL] `addChooseButton` renders a `DropdownButton<int>` in-line, but AyuGram opens a full `SingleChoiceBox` modal dialog with radio-button style selection; the entire interaction model is wrong — `ayu_section_builder.dart:346` ← `settings_ayu_utils.cpp:517-535`

- [ ] [CRITICAL] `_AyuCollapsibleToggle` missing shift+click lock mechanism: in AyuGram, Shift+clicking a nested checkbox locks it (opacity 0.4, excluded from master toggle), shift+clicking again unlocks it, and the master toggle skips locked items; none of this exists in the Dart implementation — `ayu_section_builder.dart:370-485` ← `settings_ayu_utils.cpp:380-415`

- [ ] [CRITICAL] `_AyuCollapsibleToggle` header label missing checked-count indicator: AyuGram appends bold `"  N/M"` text entity inline in the toggle label showing how many children are checked; Dart shows only a blue dot indicator (`anyChecked` case) with no count — `ayu_section_builder.dart:435-445` ← `settings_ayu_utils.cpp:231-243`

- [ ] [MAJOR] `addSectionDivider` only adds a 7px skip AFTER the divider; AyuGram calls `AddSkip` + `AddDivider` + `AddSkip` (skip before AND after) — `ayu_section_builder.dart:125-132` ← `ayu_builder.cpp:263-267`

- [ ] [MAJOR] `_AyuCollapsibleToggle` master toggle has wrong tap-target structure: in AyuGram there is a 1px vertical separator between the expand-label area and the toggle button area, and the two areas have independent tap handlers; in Dart the entire row `InkWell` only toggles expand, with the `AyuToggle` as an embedded widget — missing the separator and independent geometry — `ayu_section_builder.dart:420-465` ← `settings_ayu_utils.cpp:162-207`

- [ ] [MAJOR] `addSlider` missing `showTitle` flag: in AyuGram the slider title button is conditionally rendered and is transparent to mouse events (label only); Dart always renders the label row unconditionally with no way to suppress it — `ayu_section_builder.dart:48-66` ← `ayu_builder.cpp:193-198`

# ayu_toggle — Custom toggle switch widget

- [ ] [CRITICAL] Hardcoded inactive track color bypasses theme palette: light mode uses `0xFFCBCBCB` but `checkboxFg` is `0xFFB3B3B3`, dark mode uses `0xFF5A6A78` but `checkboxFg` is `0xFF546778`; must use `context.palette.checkboxFg` — `ayu_toggle.dart:89-91` ← `colors.palette:79` + `widgets.style:878`

- [ ] [CRITICAL] Thumb rendered without border: AyuGram draws a `border: 2px` stroke on the thumb whose color interpolates between `untoggledFg` (checkboxFg) and `toggledFg` (windowBgActive), but Dart draws a plain white borderless circle — `ayu_toggle.dart:118-124` ← `checkbox.cpp:132-136` + `widgets.style:880`

- [ ] [MAJOR] Material mode thumb travel distance wrong: Dart thumb starts at x=0 and travels 18px (ending at x=18, flush with right edge), but AyuGram starts at x=`border`=2 and travels `width`=14px (ending at x=16, leaving a 2px right-side gap) — `ayu_toggle.dart:98-99` ← `checkbox.cpp:117` + `widgets.style:883`

- [ ] [MAJOR] Material mode initial thumb size wrong: Dart shrinks thumb to `thumbD - animPad*2*(1-t)` = 10px at t=0, but AyuGram shrinks via `animPadding` to `14 - 2 = 12px` at t=0 (subtracts `animPadding` once per side, not `animPad*2`) — `ayu_toggle.dart:94-96` ← `checkbox.cpp:123-126` + `widgets.style:885`

- [ ] [MAJOR] Non-material (iOS) track geometry wrong: Dart fills the full 36×20 `SizedBox` with the rounded track, but AyuGram draws a narrower inset track (`fullWidth - 2*defaultToggleShift` = 28px wide, `defaultToggleDiameter - 2*defaultToggleShift` = 14px tall) centered inside the widget bounds — `ayu_toggle.dart:102-109` ← `checkbox.cpp:114-119` + `widgets.style:872-873`

- [ ] [MAJOR] Missing ripple animation on tap: AyuGram implements a rounded-rect ripple with `rippleAreaPadding: 8px` that fires on mouse press/release; Dart `GestureDetector` fires `onTap` with no visual ripple feedback — `ayu_toggle.dart:81-82` ← `checkbox.cpp:232-234` + `widgets.style:889`

# call_panel — Call panel UI stubs, wrong background, no engine wiring

- [ ] [CRITICAL] Mute button onTap is empty `() {}` — tapping Mute does nothing, no engine call — `call_panel.dart:553` ← `AyuGramDesktop/calls/calls_panel.cpp:389-393` (`_call->setMuted(!_call->muted())`)

- [ ] [CRITICAL] Add People button onTap is empty `() {}` — tapping Add People does nothing, no engine call — `call_panel.dart:558` ← `AyuGramDesktop/calls/calls_panel.cpp:425-458` (opens invite box, migrates to conference call)

- [ ] [CRITICAL] `_onScreenShareTap` screen share start: comment-only stub `// Screen share selected — source: result.source, audio: result.withAudio` with no engine call — `call_panel.dart:213-214` ← `AyuGramDesktop/calls/calls_panel.cpp:394-418` (`chooseSourceAccepted(sourceId, audio)`)

- [ ] [CRITICAL] `_onScreenShareTap` screen share stop: early `return` with comment "Stop sharing — no permission needed", no engine call to stop sharing — `call_panel.dart:208-210` ← `AyuGramDesktop/calls/calls_panel.cpp:403-406` (`chooseSourceStop()`)

- [ ] [CRITICAL] `_onCameraTap` does nothing after permission — comment `// Camera toggle proceeds` with no engine call — `call_panel.dart:219-221` ← `AyuGramDesktop/calls/calls_panel.cpp:419-424` (`_call->toggleCameraSharing(!_call->isSharingCamera())`)

- [ ] [CRITICAL] `showCallPanel` passes `onAccept: () {}` — answering an incoming call does nothing — `call_panel.dart:1503` ← `AyuGramDesktop/calls/calls_panel.cpp:474-488` (`_call->answer()`)

- [ ] [CRITICAL] Device selector menu shows hardcoded `'Default Camera'` / `'Default Microphone'` fake items, not populated from actual detected devices — `call_panel.dart:229-237` ← `AyuGramDesktop/calls/ui/calls_device_menu.h` (real device enumeration via webrtc environment)

- [ ] [CRITICAL] `CallPanel` has no engine event subscriptions — `CallPanelInfo` is immutable and never updated from backend. Call state transitions (connecting→active), remote mute, signal quality, fingerprint changes all require the parent to rebuild with new `CallPanelInfo`. No `StreamSubscription` to any `EngineService` stream in `_CallPanelState` — `call_panel.dart:102-826` ← `AyuGramDesktop/calls/calls_panel.cpp:387-498` (continuous reactive subscriptions to call state, mute, signal)

- [ ] [MAJOR] Background uses `LinearGradient(topCenter→bottomCenter)` — AyuGram uses a `QRadialGradient` centered on the userpic position — `call_panel.dart:809-815` ← `AyuGramDesktop/calls/calls_panel_background.cpp:77-88` (`QRadialGradient(center, radius)` where center is userpic center)

- [ ] [MAJOR] Background colors computed by pixel-averaging the avatar image — AyuGram derives colors from peer's server-side color profile (`peerColors().colorProfileFor(_peer)`), not from pixel analysis of the photo — `call_panel.dart:239-350` ← `AyuGramDesktop/calls/calls_panel_background.cpp:175-184` (`updateColors()`)

- [ ] [MAJOR] `_CallControlButton` size is 48×48 — AyuGram `callButton` is `width: 68px, height: 79px` — `call_panel.dart:989-1000` ← `AyuGramDesktop/calls/calls.style:89-98`

- [ ] [MAJOR] `_CallActionButton` default size is 56×56 — AyuGram `callAnswer` bgSize is 44px inside a 68×79 button — `call_panel.dart:841-843` ← `AyuGramDesktop/calls/calls.style:107-120`

- [ ] [MAJOR] Status label `fontSize: 15` — AyuGram `callStatus` specifies `font(14px)` — `call_panel.dart:415` ← `AyuGramDesktop/calls/calls.style:347-355`

- [ ] [MAJOR] Missing connecting-state radial animation — `_buildConnectingState` shows no spinner. AyuGram has `callConnectingRadial: InfiniteRadialAnimation` displayed during connecting states — `call_panel.dart:441-499` ← `AyuGramDesktop/calls/calls.style:333-336`

- [ ] [MAJOR] `_OutgoingPreview` interpolation uses `_hDefault = 720.0` as the height at which preview reaches max size — AyuGram's default preview at `callHeight = 540px` is `size(540px, 180px)`, not the max size. Dart incorrectly maps default height to `_maxSize`. Should interpolate min→default at callHeightMin→callHeight, then default→max beyond — `call_panel.dart:1443-1449` ← `AyuGramDesktop/calls/calls.style:70-73` (`callOutgoingPreview: size(540px, 180px)` for `callHeight: 540px`)

- [ ] [MAJOR] `callFingerprintPadding` right is 8px, bottom is 5px — Dart uses `EdgeInsets.symmetric(horizontal: 10, vertical: 4)` giving right=10 and bottom=4 — `call_panel.dart:1174` ← `AyuGramDesktop/calls/calls.style:77` (`margins(10px, 4px, 8px, 5px)`)

- [ ] [MAJOR] `callRatingPadding` top is 12px — Dart uses `padding: EdgeInsets.only(left: 24, top: 8, right: 24)` giving top=8 — `call_panel.dart:1606` ← `AyuGramDesktop/calls/calls.style:426` (`margins(24px, 12px, 24px, 0px)`)

- [ ] [MAJOR] `callRemoteAudioMute` in AyuGram is a plain text label near the userpic with `font(12px)` and `textFg: videoPlayIconFg` — Dart renders a dark-background pill with icon+text at a fixed top position below the header — `call_panel.dart:501-523` ← `AyuGramDesktop/calls/calls.style:356-363`

- [ ] [MAJOR] `callBodyLayout` uses fixed pixel positions (`photoTop: 21px`, `nameTop: 221px`, `statusTop: 254px`) — Dart uses `Spacer(flex: 3)` / `Spacer(flex: 4)` which produces different proportional layout, not matching the spec positions — `call_panel.dart:396-437` ← `AyuGramDesktop/calls/calls.style:46-56`

# bridge_stub — FFI Bridge Infrastructure Audit

**Note:** `bridge_stub.dart` has no direct AyuGram Desktop C++ counterpart. AyuGram is a
monolithic C++ process; its equivalent layer is `ApiWrap` + RPL reactive streams
(`apiwrap.h`, `data/data_changes.h`), all in-process with no FFI boundary. Citations
below reference sibling Dart files as ground truth where AyuGram has no analog.

---

## Stub silent-failure mode (bridge_stub.dart)

- [ ] [CRITICAL] `events` returns `const Stream.empty()` instead of throwing `UnsupportedError`. If the stub is accidentally reached (broken conditional import on a new platform), callers subscribe and receive zero events forever with no error — silent, undetectable failure — `bridge_stub.dart:9` ← `bridge_ffi.dart:44` (real impl throws/returns real stream; stub must match error contract of `init`/`call`/`callAsync`)

- [ ] [CRITICAL] `isInitialized` returns hard-coded `false` instead of throwing. Code that checks `isInitialized` before calling `init()` will silently believe the bridge is not initialized and may skip initialization entirely, causing cascading null-deref failures downstream — `bridge_stub.dart:10` ← `bridge_ffi.dart:46-47`

- [ ] [MAJOR] `dispose()` is a silent no-op (line 24) while all three callable methods throw `UnsupportedError`. If the stub is reached and `dispose()` is called during app teardown, it succeeds silently, giving the impression the bridge shut down cleanly — `bridge_stub.dart:24` ← `bridge_ffi.dart:81-85` (real dispose actively unregisters the native callback)

---

## Resource leaks in the real FFI implementation (bridge_ffi.dart)

- [ ] [CRITICAL] `_globalEventController` is a module-level `StreamController.broadcast()` (never closed). `BridgeImpl.dispose()` calls `_setEventCallback(nullptr)` to stop events arriving but never calls `_globalEventController.close()`. Any subscriber that called `bridge.events.listen(...)` holds a live subscription on a zombie stream forever — `bridge_ffi.dart:146` vs `bridge_ffi.dart:81-85`

- [ ] [CRITICAL] `_eventCallable` (a `NativeCallable<_EventCallbackC>.listener`) is created at module level (line 162) and never closed. `NativeCallable.close()` must be called to release the native-to-Dart trampoline and avoid the Dart VM keeping the isolate alive. `dispose()` never calls `_eventCallable.close()` — `bridge_ffi.dart:162` vs `bridge_ffi.dart:81-85`

- [ ] [CRITICAL] The global `_globalEventController` is shared across all `BridgeImpl` instances (line 44 reads from it, line 146 declares it globally). If two `Bridge` objects are created (e.g. during a hot-restart or test), both receive all events from all Go callbacks — event duplication and cross-contamination — `bridge_ffi.dart:44,146`

- [ ] [MAJOR] `_isolateCall` calls `DynamicLibrary.open(libPath)` on every `callAsync` invocation (line 136). The comment claims this is "cheap" because the OS reuses the handle, but on Android, `dlopen` with the same path is not guaranteed to be free and adds measurable overhead on every async call. The lib handle should be passed to the isolate rather than re-opened — `bridge_ffi.dart:135-143`

---

## Web implementation blocks main thread (bridge_web.dart)

- [ ] [CRITICAL] `callAsync` on web is not asynchronous: `async => call(requestBytes)` (line 44) runs the Go WASM function synchronously on the Dart/JS main thread. Every engine call (auth, chat list, send message) blocks the browser event loop for the full duration of the Go computation. Heavy operations (crypto, network round-trips) will freeze the web UI — `bridge_web.dart:44` ← `bridge_ffi.dart:75-79` (FFI correctly uses `Isolate.run` to offload to a background thread)

---

## Conditional import coverage gap (bridge.dart)

- [ ] [MAJOR] The conditional import chain (`if (dart.library.ffi) bridge_ffi.dart` / `if (dart.library.js_interop) bridge_web.dart`) has no fallback guard. On any future platform where neither `dart:ffi` nor `dart:js_interop` is available (e.g., Dart native without FFI, server-side Dart), the stub is silently selected and `init()` throws at runtime with a generic `UnsupportedError`. There is no compile-time or startup assertion to detect this condition early — `bridge.dart:9-11` ← `bridge_stub.dart:12-14`

# call_screen — Group call panel + minimised call bar + screen-share chooser

## Backend Wiring (no engine import in file)

- [ ] [CRITICAL] `showGroupCallPanel()` passes `onToggleMute: null` — mute button is a dead GestureDetector; call to `group->setMuted()` never happens — `call_screen.dart:956-968` ← `calls/calls_top_bar.cpp:291-304` (`_mute->setClickedCallback` calls `group->setMuted`)
- [ ] [CRITICAL] `showGroupCallPanel()` passes `onToggleVideo: null` — video toggle button fully inert, no engine method called — `call_screen.dart:956-968` ← `calls/group/calls_group_panel.cpp` (`_video->setClickedCallback`)
- [ ] [CRITICAL] `showGroupCallPanel()` passes `onOpenMenu: null` — ⋯ button does nothing; AyuGram opens the full group call menu — `call_screen.dart:158` ← `calls/group/calls_group_menu.cpp`
- [ ] [CRITICAL] `onLeave: () => Navigator.of(ctx).pop()` dismisses the Flutter dialog only; `group->hangup()` / `LeaveBox` is never called — user appears to leave visually but is still in the call engine — `call_screen.dart:962` ← `calls/calls_top_bar.cpp:424-439` (`_hangup->setClickedCallback` calls `call->hangup()` or shows `Group::LeaveBox`)
- [ ] [CRITICAL] `showScreenShareChooser()` result is discarded — `_confirm()` pops with `_selected` but the return value of `showDialog` is awaited nowhere; no engine method for starting screen capture is ever called — `call_screen.dart:1695-1698` ← `calls/group/calls_group_panel.cpp` (desktop capture → `_call->setScreenCaptureDevice`)
- [ ] [CRITICAL] `_GroupCallPanelState._durationTimer` starts at 0 and self-increments — real call duration from engine (`call->getDurationMs()`) is never read; timer resets every time dialog opens — `call_screen.dart:72-76` ← `calls/calls_top_bar.cpp:733-750` (`updateDurationText` reads `_call->getDurationMs()` and schedules next tick at exact millisecond boundary)
- [ ] [CRITICAL] `MinimisedCallBar` has no engine import anywhere in `call_screen.dart`; `onToggleMute`, `onHangup`, `onTap` are callbacks that callers must wire — but the file contains zero `bridge.call` invocations, making every callback a potential no-op stub — `call_screen.dart:986-1003` ← `calls/calls_top_bar.cpp:291-439`
- [ ] [CRITICAL] Audio level never fed to `_SpeakerBlobAvatar`; `p.audioLevel` is a static field on `GroupCallParticipant` model with no reactive subscription to real tgcalls audio level events — blob stays frozen unless external code rebuilds the widget — `call_screen.dart:212` ← `calls/calls_top_bar.cpp:563-572` (`group->levelUpdates()` → `state->paint.setLevel`)

## Missing UI Elements

- [ ] [CRITICAL] Bottom controls bar is missing the Settings, Share, and Messages buttons — AyuGram group call has 5+ controls; Dart only has Screen/Video/Hangup/Mute — `call_screen.dart:264-297` ← `calls.style:929-1001` (`groupCallSettings`, `groupCallShare`, `groupCallMessage`, `groupCallHangup`, `callMuteButton` all defined)
- [ ] [CRITICAL] No "Join As" / profile switcher control (shown when multiple accounts can join) — `call_screen.dart` (absent) ← `calls/group/calls_group_panel.h` (`_joinAsToggle` userpic button)
- [ ] [CRITICAL] No raised-hand button / raised-hand state in bottom controls — AyuGram `ForceMuted` state allows raising hand — `call_screen.dart` (absent) ← `calls.style:903` (`groupCallMemberRaisedHand` icon) and `ui/controls/call_mute_button.cpp:158-163` (`RaisedHand` type)

## Dimension Deviations

- [ ] [CRITICAL] `sidebarWidth = 260.0` vs AyuGram `groupCallNarrowMembersWidth: 204px` — 27.5% wider than spec — `call_screen.dart:48` ← `calls.style:1355`
- [ ] [CRITICAL] `_BigMuteButtonState._blobMinRadius = 28.0; _blobMaxRadius = 33.0` — AyuGram: minor blob min=64px max=74px, major blob min=67px max=77px — Dart radii are ~57% smaller, blob animation will look completely different — `call_screen.dart:717-718` ← `calls.style:324-327` (`callMuteMinorBlobMinRadius: 64px`, `callMuteMinorBlobMaxRadius: 74px`, `callMuteMajorBlobMinRadius: 67px`, `callMuteMajorBlobMaxRadius: 77px`)
- [ ] [MAJOR] `defaultHeight = 540.0` vs AyuGram `groupCallHeight: 520px` — 20px taller, 3.8% off — `call_screen.dart:47` ← `calls.style:546`
- [ ] [MAJOR] Recording mark gap `SizedBox(width: 8)` vs AyuGram `groupCallRecordingMarkSkip: 4px` — double the specified gap — `call_screen.dart:129` ← `calls.style:848`

## Wrong Visual Behavior

- [ ] [CRITICAL] `_BigMuteButton` uses blob segment counts 6+8 — AyuGram `CallMuteButton` uses 9 (minor) + 12 (major) segments for smooth organic shape — `call_screen.dart:736-737` ← `ui/controls/call_mute_button.cpp:108-134` (`MuteBlobs()` returns `segmentsCount = 9` and `segmentsCount = 12`)
- [ ] [MAJOR] `_BigMuteButton` uses Material `Icons.mic` / `Icons.mic_off` with `AnimatedSwitcher` — AyuGram uses Lottie animations (`voice.lottie`, `hands.lottie`) with frame-precise state transitions (ForceMuted→Muted: frames 0-35, Muted→Active: 36-68, etc.) — `call_screen.dart:835-844` ← `ui/controls/call_mute_button.cpp:653-665` (`refreshIcons` loads lottie) and `676-708` (frame map per state pair)
- [ ] [MAJOR] `ForceMuted` mute state in `_BigMuteButton` uses `Icons.mic_off` + purple color — AyuGram shows a raised-hand Lottie icon with hand-waving animation on tap — `call_screen.dart:836-838` ← `ui/controls/call_mute_button.cpp:734-747` (`randomWavingState()` plays hands.lottie waving frames)
- [ ] [MAJOR] `_UserpicStrip` shows up to 5 participants — AyuGram `kMaxUserpics = 4` — `call_screen.dart:1413` ← `ui/chat/group_call_userpics.cpp:25` (`constexpr auto kMaxUserpics = 4`)
- [ ] [MAJOR] `_BigMuteButtonState._pulsePeriodMs = 430` gives a fixed-frequency pulse for the unmuted state; AyuGram drives blob level from real audio input via `group->levelUpdates()` observable — Dart fakes constant oscillation regardless of actual microphone level — `call_screen.dart:769-773` ← `calls/calls_top_bar.cpp:563-572` (real `LevelUpdate` events from group call engine)
- [ ] [MAJOR] `_SignalBars` accepts a static `quality` int — AyuGram `SignalBars` subscribes to `call->signalBarCountValue()` reactive value and repaints automatically on signal change — Dart bar never updates after construction unless the widget is rebuilt externally — `call_screen.dart:1353-1364` ← `calls/calls_signal_bars.cpp:26-30` (`call->signalBarCountValue() | rpl::on_next(...)`)
- [ ] [MAJOR] `MinimisedCallBar` gradient for `muted` group call state is `[Color(0xFF5B6BBE), Color(0xFF7B68EE)]` — AyuGram uses `groupCallMuted1` / `groupCallMuted2` theme colors (not hardcoded) — `call_screen.dart:1116-1117` ← `calls/calls_top_bar.cpp:119-128` (`Colors()` map uses `st::groupCallMuted1->c`, `st::groupCallMuted2->c`)
- [ ] [MAJOR] `MinimisedCallBar` gradient for `forceMuted` uses 3-stop gradient with hardcoded `[0xFF9B59B6, 0xFF7B68EE, 0xFF8E44AD]` — AyuGram uses `groupCallForceMutedBar1/2/3` theme colors at stops 0.0, 0.35, 1.0 — `call_screen.dart:1120-1121` ← `calls/calls_top_bar.cpp:110-117` (GradientStops at `{ 0.0, st::groupCallForceMutedBar1 }`, `{ .35, st::groupCallForceMutedBar2 }`, `{ 1.0, st::groupCallForceMutedBar3 }`)

## Performance Issues

- [ ] [MAJOR] `_BlobPainter.shouldRepaint` always returns `true` even when level and blobs haven't changed — combined with every-frame `setState` in `_onTick` this repaints the entire `CustomPaint` tree unconditionally — `call_screen.dart:636` (should compare `old.level != level` or `old.majorBlob != majorBlob`)
- [ ] [MAJOR] `_BigMuteButtonState._onTick` calls `setState((){})` on every animation frame (60 fps) for the entire `_BigMuteButton` subtree, including the `Column`, `AnimatedContainer`, `AnimatedSwitcher`, and text label — AyuGram uses a dedicated `BlobsWidget` (`RpWidget`) that is a separate widget subtree so only the blob region repaints — `call_screen.dart:763-767` ← `ui/controls/call_mute_button.cpp:316-556` (separate `BlobsWidget` class)
- [ ] [MAJOR] `_ScreenShareChooserDialogState._enumerateWindows()` forks child processes (`kdotool`, `wmctrl`) synchronously in `async` without `Isolate.run` — on Wayland with many windows this iterates N `kdotool getwindowname` calls serially on the platform thread — `call_screen.dart:1591-1639` (should use `Isolate.run` or batch to avoid UI jank during enumeration)

# calls_screen — Calls Box / Call History / Call Settings

- [ ] [CRITICAL] `onTap: () {}` on call history row — clicking any call history row does nothing; AyuGram opens the peer chat scrolled to the call message (`window->showPeerHistory(peer, ..., itemId)`) — `calls_screen.dart:1933` ← `calls/calls_box_controller.cpp:601-609`

- [ ] [CRITICAL] `_InputLevelMeter` is fake animation — the level meter oscillates `_controller.value * 0.35` on a fixed 800ms loop; AyuGram drives it from a real `AudioInputTester` that captures actual microphone input — `calls_screen.dart:2558-2559` ← `settings/sections/settings_calls.cpp:113-151`

- [ ] [CRITICAL] Device picker always shows hardcoded `['Default']` — `_showDevicePicker` builds the list from `final devices = ['Default']` only; AyuGram calls `Core::App().mediaDevices().devicesValue(type)` to enumerate real system devices — `calls_screen.dart:2241` ← `settings/sections/settings_calls.cpp:63-69`

- [ ] [CRITICAL] "Accept incoming calls" toggle has no backend wiring — `_acceptCalls` is a local `bool` variable; AyuGram reads/writes `api->authorizations().callsDisabledHere()` and calls `authorizations->toggleCallsDisabledHere(!value)` on change — `calls_screen.dart:2109,2205-2212` ← `settings/sections/settings_calls.cpp:392-409`

- [ ] [CRITICAL] "Use same devices for calls" toggle not persisted — `_useSameDevices` is a local `bool`; AyuGram reads/writes `settings->callPlaybackDeviceId()` + `settings->callCaptureDeviceId()` and calls `Core::App().saveSettingsDelayed()` — `calls_screen.dart:2108,2177-2187` ← `settings/sections/settings_calls.cpp:246-275`

- [ ] [CRITICAL] Output/Input/Camera device selection never written to engine — `setState(() => _outputDevice = d)` only updates local widget state; AyuGram calls `settings->setPlaybackDeviceId(id)` / `settings->setCaptureDeviceId(id)` / `settings->setCameraDeviceId(id)` + `saveSettingsDelayed()` — `calls_screen.dart:2151-2154,2163-2166,2197-2200` ← `settings/sections/settings_calls.cpp:83-89,103-111,773-785`

- [ ] [CRITICAL] "Share Link" button closes dialog and does nothing — `onPressed: () => Navigator.of(context).pop()` on the "Share Link" `OutlinedButton` in `_ConferenceCallLinkBox`; should open OS share sheet or copy link — `calls_screen.dart:1483-1498` ← `calls/calls.style:1607-1610` (`confcallLinkShareButton`)

- [ ] [CRITICAL] "Open system sound preferences" is empty — `onTap: () {}` on `_CallSettingsActionRow`; AyuGram calls `Platform::OpenSystemSettings(SystemSettingsType::Audio)` — `calls_screen.dart:2224` ← `settings/sections/settings_calls.cpp:411-425`

- [ ] [MAJOR] Active group call scan is sequential — `_loadActiveGroupCalls` iterates chats with `await engine.getGroupCall(...)` serially inside a `for` loop; 20 sequential round-trips instead of `Future.wait()` in parallel; adds multi-second latency to box open — `calls_screen.dart:181-192` ← `calls/calls_box_controller.cpp:215-231`

- [ ] [MAJOR] Group call row subtext shows only "group" or "channel" — `_chatTypeLabel` returns only 3 possible strings; AyuGram sets "public channel", "private channel", "public group", "private group" from actual peer flags — `calls_screen.dart:520-529` ← `calls/calls_box_controller.cpp:107-117`

- [ ] [MAJOR] "Show in Chat" jumps by timestamp instead of message ID — `chatState.jumpToMessage(newestTimestamp)` uses `group.newest.timestamp * 1000`; AyuGram passes the exact `itemId` (message ID) to `showPeerHistory` — `calls_screen.dart:1886-1889` ← `calls/calls_box_controller.cpp:601-609`

- [ ] [MAJOR] `confcallSizeLimit` hardcoded to 200 — defined as `static const _confcallSizeLimit = 200` in two widgets; AyuGram reads the live value from `controller->session().appConfig().confcallSizeLimit()` so the description and enforcement update if Telegram changes the server limit — `calls_screen.dart:711,873` ← `calls/calls_box_controller.cpp:785`

- [ ] [MAJOR] Camera settings section has no live preview — the "Camera" device row shows a picker but no video preview; AyuGram renders a live `VideoBubble` under the device row driven by `tgcalls::VideoCaptureInterface` — `calls_screen.dart:2191-2202` ← `settings/sections/settings_calls.cpp:743-851`

- [ ] [MAJOR] Microphone permission never requested in Call Settings — `_CallSettingsScreen.initState` does not request microphone permission before starting the level meter; AyuGram calls `GetPermissionStatus(PermissionType::Microphone)` on construction and shows a confirmation box if denied — `calls_screen.dart:2104` ← `settings/sections/settings_calls.cpp:695-726`

- [ ] [MAJOR] `_groupCallEntries` called synchronously inside `setState` on every data update — rebuilds the full grouped list O(n) on the UI thread; for 100+ entries this causes visible jank; should use `compute()` or `Isolate.run()` — `calls_screen.dart:109,131,359-363` ← (performance — no direct AyuGram equivalent; `calls/calls_box_controller.cpp:644-663` does incremental insertion not full rebuild)

# chat_export — Export dialog and top bar

- [ ] [CRITICAL] Entire export execution is fake: `_startExport()` uses `Timer.periodic` to simulate progress with fixed speed constants; never calls any engine/bridge method. No Takeout API session is opened, no messages are downloaded, no files are written. AyuGram calls `_process->startExport(*_settings, PrepareEnvironment(_session))` which invokes the real MTP Takeout API — `chat_export.dart:677-755` ← `export_view_panel_controller.cpp:204-206`

- [ ] [CRITICAL] Completed state shows fake file counts and sizes: `_totalFiles` is accumulated as `10 + _currentStepIndex * 5` and `_totalSizeBytes` as `(512 + _currentStepIndex * 256) * 1024` — hardcoded fake math. AyuGram's `FinishedState` carries real `filesCount` and `bytesCount` from the actual export operation — `chat_export.dart:732-733` ← `export_controller.h:89-93`

- [ ] [CRITICAL] `_skipCurrentFile()` advances a local fake index and does nothing to the backend. AyuGram sends the actual file's `randomId` to the controller via `_process->skipFile(randomId)` so the API skips the real in-flight file download — `chat_export.dart:766-775` ← `export_view_panel_controller.cpp:315-317`

- [ ] [CRITICAL] `_handleClose()` during processing only cancels the `_exportTimer` Timer; no backend Takeout session is cancelled. AyuGram calls `_process->cancelExportFast()` which sends an MTProto cancel and clears `_takeoutId` — `chat_export.dart:583-593` ← `export_view_panel_controller.cpp:351-355`

- [ ] [CRITICAL] `PasswordCheckState` phase is completely absent. AyuGram begins export with a password check state (`PasswordCheckState`) before the processing phase starts; this state carries `singlePeer` for the per-chat path. Dart goes directly from settings → fake processing — `chat_export.dart:(no implementation)` ← `export_controller.h:26-35`

- [ ] [CRITICAL] `_bringPanelToFront()` is an explicit no-op (comment: "no-op — panel is already a dialog in the overlay"). This means tapping the `ExportTopBar` during an active export does nothing. AyuGram calls `activatePanel()` → `_panel->showAndActivate()` to bring the floating panel window to front — `chat_export.dart:690-692` ← `export_view_panel_controller.cpp:163-167`

- [ ] [MAJOR] Processing view progress bar fill uses `context.palette.windowBgActive` as the active-fill color. AyuGram style explicitly sets `exportProgressFg: mediaPlayerActiveFg`; the fill must use `palette.mediaPlayerActiveFg` — `chat_export.dart:1896` ← `export.style:66`

- [ ] [MAJOR] Processing view row vertical padding is `EdgeInsets.fromLTRB(22, 5, 22, 5)` (5 px top/bottom). AyuGram style specifies `exportProgressRowPadding: margins(22px, 10px, 22px, 10px)` — top and bottom must be 10 px — `chat_export.dart:1921` ← `export.style:51`

# chat_list_panel — Chat List Panel Audit

## Placeholders & Stubs

- [ ] [CRITICAL] `SwipeAction.unread` calls `chatState.markRead()` instead of a mark-unread method — no `markChatUnread` exists anywhere in the codebase; swiping a chat to "unread" silently marks the active chat as read instead — `chat_list_panel.dart:934-936` ← `dialogs/dialogs_inner_widget.cpp:1753` (`addToggleUnreadMark` calls `history->peer->markReadTillEnd` / toggle, not noop)

- [ ] [CRITICAL] Context menu "Mark as Unread" does nothing — `case 'read'` guard `if (chat.unreadCount > 0)` means the else-branch (label "Mark as Unread") has zero engine call; `markChatUnread` does not exist — `chat_list_panel.dart:1336,1417-1419` ← `window/window_peer_menu.cpp:1753` (`addToggleUnreadMark`)

- [ ] [CRITICAL] Forum topic context menu "Mark as Unread" does nothing — same missing method: `case 'mark_read': if (hasUnread) { markChatRead(...); }` has no else branch when topic has zero unreads — `chat_list_panel.dart:5039-5042` ← `window/window_peer_menu.cpp:1753`

- [ ] [CRITICAL] Drag-to-filter drop onto a folder is a `debugPrint` stub — `_onReorderPointerUp` only prints `'[DRAG-TO-FILTER] Drop chat ...'` but never calls `chatState.editFolder(...)` to actually add the chat to the folder — `chat_list_panel.dart:1073-1078` ← `dialogs/dialogs_inner_widget.cpp:1773-1779` (`performDrag → FillDialogsEntryMenu → addToggleFolder`)

- [ ] [CRITICAL] Horizontal folder tab right-click "Edit Folder" → `break` — `showEditFolderBox` is imported at line 23 and called elsewhere (line 4136) but not here; clicking the menu item does nothing — `chat_list_panel.dart:2322-2325` ← `window/window_peer_menu.cpp:702` (`Filler::addNewWindow` triggers folder editing via `Window::Show`)

- [ ] [CRITICAL] Horizontal folder tab right-click "Edit Folders" → `break` — no navigation to `FoldersSettingsScreen` or similar; clicking does nothing — `chat_list_panel.dart:2331-2332` ← `dialogs/dialogs_widget.cpp` (settings button opens ChatsFilter editor)

- [ ] [CRITICAL] Search tags strip "Remove tag" context menu action not handled — `then((action) { if (action == 'edit') {...} else if (action == 'filter') {...} })` silently drops `'remove'`; clicking "Remove tag" does nothing — `chat_list_panel.dart:5301-5307` ← `dialogs/ui/dialogs_suggestions.cpp:1094` (tag deletion wired via `removeReactionTag`)

- [ ] [CRITICAL] Forum topic context menu "New Window" shows `showTelegramToast(ctx, 'Multi-window is not yet supported')` — explicit "coming soon" toast for a visible menu item — `chat_list_panel.dart:5026-5027` ← `window/window_peer_menu.cpp:702` (`Filler::addNewWindow`)

- [ ] [CRITICAL] `_ForumTopicRow._previewText` always returns `''` for non-general topics — `ForumTopic` model has no `lastMsgText` field (only `topMessageId`); all non-general topic rows render blank preview text — `chat_list_panel.dart:5201-5204` ← `dialogs/dialogs.style:666-675` (forumTopicRow has textLeft/textTop showing last message preview)

## Backend Wiring

- [ ] [CRITICAL] `_TopPeersStrip` not wired to any engine call — uses local `chats.where(type == dm)` sorted by `lastMsgTime` instead of calling `contacts.getTopPeers` API; shows recently-messaged chats, not algorithm-ranked top peers — `chat_list_panel.dart:2451-2458` ← `dialogs/ui/dialogs_suggestions.cpp` (TopPeers wired to `contacts.getTopPeers` RPC)

- [ ] [CRITICAL] Context menu missing "Open in New Window" — AyuGram's `fillContextMenuActions()` calls `addNewWindow()` as the first item for every chat row; Dart's `_showChatContextMenu` has no such entry — `chat_list_panel.dart:1323-1384` ← `window/window_peer_menu.cpp:1744`

- [ ] [CRITICAL] Context menu missing "Add to Folder / Remove from Folder" — AyuGram's `fillContextMenuActions()` calls `addToggleFolder()` for every dialog row; Dart's chat-row context menu has no folder-toggle entry (only the forum topic context menu has "Add to Folder") — `chat_list_panel.dart:1323-1384` ← `window/window_peer_menu.cpp:1754`

- [ ] [CRITICAL] Context menu missing "Block User" for non-contact DMs — AyuGram's `fillContextMenuActions()` calls `addBlockUser()` when the peer is a non-contact user; Dart's context menu never offers blocking — `chat_list_panel.dart:1323-1384` ← `window/window_peer_menu.cpp:1757`

## Data Not Flowing

- [ ] [MAJOR] `_ForumTopicRow._formatDate` uses `topic.creationDateTime` (topic creation date) instead of last-message date — `topMessageId` is available but there is no `lastMsgTime` on `ForumTopic`; all forum topic rows display the wrong date — `chat_list_panel.dart:5184-5198` ← `dialogs/dialogs.style:666-675` (date column shows last activity time)

- [ ] [MAJOR] `_RecentContactsList` hardcodes `'last seen recently'` for every non-online user — actual last-seen time from the engine is never used; all offline contacts display the same static string — `chat_list_panel.dart:3219` ← `dialogs/ui/dialogs_suggestions.cpp` (status text comes from `PeerListEntry::status`)

# chat_list_row — Chat List Row Audit

## Sources compared
- Dart: `dart/lib/ui/chat_list_row.dart`
- AyuGram: `dialogs/dialogs.style`, `dialogs/ui/dialogs_layout.cpp`, `dialogs/dialogs_quick_action.cpp`, `dialogs/dialogs_row.cpp`, `ui/controls/swipe_handler.cpp`

---

- [ ] [CRITICAL] `_TopicsPreview` renders "No topics" placeholder text when `topics.isEmpty` — hardcoded stub string with no AyuGram equivalent; AyuGram shows nothing when topics list is empty — `chat_list_row.dart:1909-1917` ← `dialogs/ui/dialogs_topics_view.cpp` (no empty-state text exists)

- [ ] [CRITICAL] Saved Messages identified by fragile title-string check `chat.title == 'Saved Messages'` instead of a proper API flag — breaks for any non-English or renamed self-chat; AyuGram uses `Flag::SavedMessages` set from `peer->isSelf()` — `chat_list_row.dart:985-987` ← `dialogs/ui/dialogs_layout.cpp:463`

- [ ] [CRITICAL] `resolveSwipeAction('mute', chat)` never returns `SwipeAction.disabled` for Saved Messages (self-chat) — AyuGram explicitly returns `Disabled` when `history->peer->isSelf()` — `chat_list_row.dart:491` ← `dialogs_quick_action.cpp:150-153`

- [ ] [CRITICAL] `resolveSwipeAction('read', chat)` never returns `SwipeAction.disabled` for forum chats with zero unread messages — AyuGram returns `Disabled` for `history->isForum() && !unread` — `chat_list_row.dart:494-497` ← `dialogs_quick_action.cpp:165-167`

- [ ] [CRITICAL] `resolveSwipeAction('archive', chat)` doesn't guard against non-archivable chats — AyuGram checks `!Window::CanArchive(history, peer)` and returns `Disabled`; Dart always returns `archive`/`unarchive` — `chat_list_row.dart:498-500` ← `dialogs_quick_action.cpp:172-176`

- [ ] [CRITICAL] Tagged dialog row variants (`taggedDialogRow`: 72px, `taggedForumDialogRow`: 96px) are defined as dead constants but never rendered — `_rowHeightWithTags = 96.0` is assigned at `chat_list_row.dart:1729` but `effectiveHeight` always uses `_rowHeight = 80.0` at line 1741; filter tags are entirely unimplemented — `chat_list_row.dart:1729,1741` ← `dialogs/dialogs.style:102-117`

- [ ] [CRITICAL] TTL badge missing entirely — AyuGram shows a 20px TTL countdown badge at the avatar's bottom-right for self-destructing chats — `chat_list_row.dart` (absent) ← `dialogs/dialogs.style:156-159`

- [ ] [CRITICAL] Active call badge missing entirely — AyuGram shows a 16px call badge at the avatar corner during active calls — `chat_list_row.dart` (absent) ← `dialogs/dialogs.style:150-152`

- [ ] [CRITICAL] Subscription badge missing entirely — AyuGram shows a 16px subscription badge at the avatar corner — `chat_list_row.dart` (absent) ← `dialogs/dialogs.style:153-155`

- [ ] [CRITICAL] Poll unread badge missing entirely — AyuGram has `dialogsUnreadPoll`/`dialogsUnreadPollBadge` icons for chats with unread polls — `chat_list_row.dart` (absent) ← `dialogs/dialogs.style:600-638`

- [ ] [MAJOR] Verified badge uses `Icons.verified` (generic Material icon) instead of AyuGram's two-layer SVG composed of `dialogs_verified_star` + `dialogs_verified_check` with three-state (normal/over/active) variants — wrong visual appearance — `chat_list_row.dart:203` ← `dialogs/dialogs.style:447-458`

- [ ] [MAJOR] Mute icon color uses `dialogsTextFg`/`dialogsTextFgActive` (text foreground) instead of `dialogsUnreadBgMuted`/`dialogsUnreadBgMutedActive` — AyuGram's `dialogsMuteIcon` uses the muted-badge color family, not the text color — `chat_list_row.dart:228-229` ← `dialogs/dialogs.style:641-645`

- [ ] [MAJOR] Swipe action icon+label vertical layout allocates 54px (20px icon + 2px gap + 32px label) vs AyuGram's `innerHeight = iconSize * 2 = 40px` where icon occupies the top half and label text anchors to the bottom — 35% height deviation — `chat_list_row.dart:836-860` ← `dialogs_quick_action.cpp:241-264`

- [ ] [MAJOR] Online badge has no appear/disappear animation — AyuGram animates the badge over `dialogsOnlineBadgeDuration: 150ms` using a managed animation layer; Dart renders it statically as a plain `Container` — `chat_list_row.dart:1057-1077` ← `dialogs/dialogs.style:148`, `dialogs_row.cpp:207-213`

- [ ] [MAJOR] Hover state never updates unread badge colors to Over variants — `isHovered` is received from `_HoverBuilder` at `chat_list_row.dart:99` but `badgeBg`/`badgeText` at lines 100-103 only branch on `isActive`/`chat.isMuted`, ignoring `isHovered`; AyuGram switches to `dialogsUnreadBgOver`, `dialogsUnreadBgMutedOver`, `dialogsUnreadFgOver` on `context.selected` — `chat_list_row.dart:100-103` ← `dialogs/dialogs.style:76-78`

- [ ] [MAJOR] Forum topic jump bubble uses `Icons.arrow_forward` (Material) instead of `forumDialogJumpArrow` asset (`dialogs/dialogs_topic_arrow`) with three-state color variants — `chat_list_row.dart:1992` ← `dialogs/dialogs.style:138-139`

- [ ] [MAJOR] `ForumChatListRow` applies `SizedBox(height: 8)` before the name row, but AyuGram's `forumDialogRow` inherits `defaultDialogRow.nameTop: 10px` — name is rendered 2px too high — `chat_list_row.dart:1813` ← `dialogs/dialogs.style:93-113`

- [ ] [MAJOR] `ForumChatListRow` uses `fontSize: 14` for the forum group name while AyuGram uses the same `st::semiboldFont` (13px semibold) for all dialog rows without size distinction between forum and non-forum — `chat_list_row.dart:1824` ← `dialogs/dialogs.style:89`

## chat_settings_screen — Chat/display settings screen

- [ ] [CRITICAL] `_fontFamily` is stored in local widget state only and never persisted — `onFontChanged: (f) => setState(() => _fontFamily = f)` (line 307) and init hardcodes `'Inter'` (line 34); no engine or app-state call to save or reload it, so the choice is lost on navigation — `chat_settings_screen.dart:34` ← `AyuGram/settings/sections/settings_chat.cpp:2859` (`settings->customFontFamily()` init) / `settings_chat.cpp:2876` (`settings->setCustomFontFamily(chosen)` + `Local::writeSettings()` + `Core::Restart()`)

- [ ] [CRITICAL] Font family change does not trigger an app restart to apply — `_ChooseFontBox.onFontSelected` at line 1750 just calls `widget.onFontSelected(_selected)` with no restart; in AyuGram, `Core::Restart()` is called immediately after saving so the new font actually renders — `chat_settings_screen.dart:1750` ← `AyuGram/settings/sections/settings_chat.cpp:2879`

- [ ] [CRITICAL] `_useSystemAccent` is never persisted — checkbox `onChanged` at line 235 only calls `setState(() => _useSystemAccent = v ?? false)`; no engine or app-state write; initial value is always `false` (line 30), never read from settings — `chat_settings_screen.dart:30` ← `AyuGram/settings/sections/settings_chat.cpp:2362` (init: `settings.systemAccentColorEnabled()`) / `settings_chat.cpp:2547` (save: `settings.setSystemAccentColorEnabled(checked)`)

- [ ] [CRITICAL] `_adaptiveLayout` is never persisted — `onAdaptiveChanged: (v) => setState(() => _adaptiveLayout = v)` at line 334; no engine or app-state write; initial value is hardcoded `true` (line 39), never read from settings — `chat_settings_screen.dart:39` ← `AyuGram/settings/sections/settings_chat.cpp:2064` (init: `Core::App().settings().adaptiveForWide()`) / `settings_chat.cpp:2096` (save: `Core::App().settings().setAdaptiveForWide(checked)`)

- [ ] [CRITICAL] "My Stickers" and "Emoji Sets" nav buttons are defined (`_StickerNavButton`, line 2861) but never instantiated — `_StickersEmojiSection.build()` (lines 2735–2789) contains only checkboxes and no navigation buttons; the two buttons are required at the bottom of the stickers section — `chat_settings_screen.dart:2735` ← `AyuGram/settings/sections/settings_chat.cpp:1553` (`stickersButton` → `StickersBox::Section::Installed`) / `settings_chat.cpp:1563` (`emojiSetsButton` → `ManageSetsBox`)

- [ ] [CRITICAL] Cloud theme "delete" action is a stub — `_showDeleteConfirmation()` at line 1977 shows a dialog whose confirm branch (line 1994) calls only `showTelegramToast(context, 'Theme deleted')` with no engine call; the theme is not actually deleted from the server — `chat_settings_screen.dart:1994` ← `AyuGram/settings/sections/settings_chat.cpp:2703` (`SetupCloudThemes` delete path)

- [ ] [CRITICAL] Cloud theme "edit" action is an empty stub — `case 'edit': break;` at line 1970 does nothing; no navigation to theme editor, no engine call — `chat_settings_screen.dart:1970` ← `AyuGram/settings/sections/settings_chat.cpp:2703`

- [ ] [CRITICAL] Double-click "React" option shows a static `Icons.favorite` heart (line 3011) instead of the user's current live favorite reaction; AyuGram renders an animated icon fetched from `reactions.favoriteId()` and adds a circle button that opens `ReactionsSettingsBox` to pick a different favorite reaction — the "React" row in Dart has no wiring to the favorite reaction system at all — `chat_settings_screen.dart:3010` ← `AyuGram/settings/sections/settings_chat.cpp:1678` (circle button + `AddReactionAnimatedIcon`) / `settings_chat.cpp:1756` (`ReactionsSettingsBox` click handler)

- [ ] [MAJOR] `suggestAnimatedEmoji` checkbox is shown to non-premium users — Dart shows it whenever `suggestEmoji` is true (line 2767), with a decorative star icon only; AyuGram gates visibility on `Data::AmPremiumValue(session) && suggestEmoji` so non-premium users never see the option — `chat_settings_screen.dart:2767` ← `AyuGram/settings/sections/settings_chat.cpp:1511` (`rpl::combine(Data::AmPremiumValue(session), suggestEmoji->value(), _1 && _2)`)

- [ ] [MAJOR] "Tile Background" change is not saved for non-image wallpapers — `onTileChanged` callback (line 318) only calls `appState.setWallpaper(...)` when `wp.isImage`; for gradient/color wallpapers the change is stored in `_tileBackground` local state only and lost on navigation; AyuGram always persists via `background->setTile(checked)` regardless of paper type — `chat_settings_screen.dart:321` ← `AyuGram/settings/sections/settings_chat.cpp:2087`

# chat_switch_overlay — Ctrl+Tab Chat Switcher

- [ ] [CRITICAL] Userpic size is 46px but AyuGram specifies 56px — `chat_switch_overlay.dart:13` ← `window/window.style:355` (`chatSwitchUserpic: size(56px, 56px)`)

- [ ] [CRITICAL] Up/Down arrow keys call `_movePrev()`/`_moveNext()` which moves by 1; AyuGram moves Up/Down by `_shownPerRow` positions with wrapping (`now = _selected ± _shownPerRow; bound = wrap`) — row-based grid navigation is entirely broken — `chat_switch_overlay.dart:86-92` ← `window/window_chat_switch_process.cpp:267-274`

- [ ] [CRITICAL] `_nameSkip = 6.0` is applied as **horizontal** padding (`EdgeInsets.symmetric(horizontal: _nameSkip)`), but `chatSwitchNameSkip` in AyuGram is the **vertical** gap between userpic bottom and label top; the vertical gap in Dart is a hardcoded `SizedBox(height: 4)` (4px instead of the correct 6px) — `chat_switch_overlay.dart:15,277,274` ← `window/window.style:375`

- [ ] [CRITICAL] "Saved Messages" chat detected by hardcoded English string comparison (`chat.title == 'Saved Messages'`) — breaks for all non-English locales; AyuGram uses proper thread-type checks via `showMyNotesOnSelf()` on the data layer — `chat_switch_overlay.dart:297` ← `window/window_chat_switch_process.cpp:319`

- [ ] [MAJOR] `perRow` computed with **ceiling** division (`(total / rows).ceil()`) but AyuGram uses **floor** division (`count / _shownRows`); with 5 chats, 2 rows: Dart gives perRow=3 (shows all 5), AyuGram gives perRow=2 (shows 4, hides 1) — wrong number of visible chats — `chat_switch_overlay.dart:181` ← `window/window_chat_switch_process.cpp:439`

- [ ] [MAJOR] Secondary row-reduction logic missing: AyuGram reduces `_shownRows` from 3→2 when `_shownPerRow * 2 > _shownRows * 4`, and from 2→1 when `_shownPerRow > _shownRows * 7`; Dart applies no such reduction after the initial rows assignment — `chat_switch_overlay.dart:176-183` ← `window/window_chat_switch_process.cpp:440-452`

- [ ] [MAJOR] No topic support: AyuGram shows topics with a compound `chatSwitchUserpicSmall` (24px) plus topic icon (`TopicIconButton`); Dart renders all chat types identically with a single round avatar — missing from Dart entirely ← `window/window.style:362-365`, `window/window_chat_switch_process.cpp:111-127`

- [ ] [MAJOR] No saved-messages sublist support: AyuGram renders Saved Messages sublist entries with a 40px `chatSwitchUserpicSublist` peer avatar beside the 24px small userpic; Dart has no sublist rendering path — missing from Dart entirely ← `window/window.style:358-361`, `window/window_chat_switch_process.cpp:111-127`

# chat_view — Stubs, Broken Wiring, Wrong Behavior

## CRITICAL — Placeholders and broken backend wiring

- [ ] [CRITICAL] `_addFilter` dialog "Save" button shows toast "Filter added" but makes zero engine calls and never persists the filter pattern — input is silently discarded — `chat_view.dart:2347` ← `dart/lib/data/ayu_filter.dart` (filter persistence layer exists but is never called from the save handler)

- [ ] [CRITICAL] "Delete All from User" context menu action calls `engine.banMember()` — banning is not the same as deleting messages; AyuGram calls a separate DeleteMessagesBox / delete-user-history API — `chat_view.dart:2656` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_context_menu.cpp:908`

- [ ] [CRITICAL] `_showScheduledMenu` ("..." in scheduled view top bar) shows "Create Poll" and "Create To-do List" items but the returned `Future<String?>` is discarded with no `.then()` handler — selecting either item does nothing — `chat_view.dart:6030` ← `AyuGramDesktop/Telegram/SourceFiles/history/history_widget.cpp:7469`

- [ ] [CRITICAL] "Mark as Unread" in top-bar context menu has no implementation — the switch case at line 5748 only handles `if (chat.unreadCount > 0)` with no `else` branch to call markDialogUnread; clicking "Mark as Unread" is a no-op — `chat_view.dart:5748` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_chat_preview.cpp:466`

- [ ] [CRITICAL] `_extractTopicTitle` bug: both `start` and `end` assign `text.indexOf('"')` (same call, same index), so `end > start` is always false and the function always returns `''` — topic creation service messages never show the topic name — `chat_view.dart:7639` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_service_message.cpp`

- [ ] [CRITICAL] PollVotes corner button is fully implemented but permanently suppressed: `_showPollVotesBtn` is hardcoded to `false` in `build()` with comment "no data field yet — always hidden"; the Mentions and Reactions buttons fire correctly but PollVotes never appears — `chat_view.dart:4330` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_list_widget.cpp`

## MAJOR — Wrong behavior and performance

- [ ] [MAJOR] `_updateStickyDate` estimates the top-visible message using `const avgHeight = 55.0` — a hardcoded constant applied to a list of variable-height messages (bubbles, media, service messages, albums all differ). Date shown in the sticky pill is frequently wrong, especially in media-heavy chats — `chat_view.dart:829` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_list_widget.cpp`

- [ ] [MAJOR] Middle-click autoscroll max speed is `(delta / 8.0).clamp(-30.0, 30.0)` px/frame at 16ms → max ≈ 1,800 px/s; AyuGram specifies `middleClickAutoscrollMaxSpeed: 7200px` (per second) — scroll is 4× too slow at maximum displacement — `chat_view.dart:1107` ← `AyuGramDesktop/Telegram/SourceFiles/ui/chat/chat.style:62`

- [ ] [MAJOR] `_buildDisplayItems` (including an O(n log n) `sort()` over all messages) is called inside `_MessageList.build()`, which is a `StatelessWidget` that rebuilds on every parent `setState` — scroll events, FAB visibility updates, and sticky-date updates all trigger parent rebuilds, running the full sort on the UI thread each time — `chat_view.dart:7079` ← (performance; `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_list_widget.cpp` uses persistent sorted layout trees, not re-sorting on every frame)

- [ ] [MAJOR] Unread bar height renders ≈27 px (13 px text + 7+7 px symmetric padding) but AyuGram specifies `historyUnreadBarHeight: 32px` — bar is visually too short (>15% deviation) — `chat_view.dart:7800` ← `AyuGramDesktop/Telegram/SourceFiles/ui/chat/chat.style:463`

# choose_datetime_box — Schedule/Calendar/TimePicker dialogs

- [ ] [CRITICAL] `sendWhenOnline` sentinel is `DateTime(2099)` (~4,070,908,800s epoch) instead of Telegram's magic constant `kScheduledUntilOnlineTimestamp = 0x7FFFFFFE` (~2,147,483,646s epoch, Jan 2038); any caller that passes `result.dateTime` as a unix timestamp directly will send the wrong value and the backend will not honour "send until online" — `choose_datetime_box.dart:637` ← `AyuGramDesktop/Telegram/SourceFiles/api/api_common.h:20`

- [ ] [CRITICAL] Schedule validation accepts any time ≥ `DateTime.now()` (0-second gap) via `dt.isBefore(DateTime.now())`; AyuGram enforces a hard 10-second minimum (`kMinimalSchedule = TimeId(10)`) so messages cannot be scheduled in the immediate present — `choose_datetime_box.dart:612` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/choose_date_time.cpp:28`

- [ ] [MAJOR] `_CalendarBoxWidget` opens via explicit `GestureDetector.onTap` on the date field; AyuGram opens the CalendarBox automatically whenever the date `InputField` receives keyboard focus (`state->day->focusedChanges()` subscription), so clicking anywhere that focuses the field also opens the calendar — `choose_datetime_box.dart:775-779` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/choose_date_time.cpp:173-196`

- [ ] [MAJOR] TimePickerBox selection indicator is a `Container` with `Border.symmetric(horizontal: BorderSide(color: bandColor, width: 2))` — a full-width accent-colour rectangle border; AyuGram draws two plain `st::activeLineFg` horizontal lines (one at `centerY`, one at `centerY + itemHeight`) painted directly onto the content widget with no fill between them — `choose_datetime_box.dart:1071-1088` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/time_picker_box.cpp:103-111`

- [ ] [MAJOR] TimePickerBox initial index resolution uses `v.indexOf(initialValue)` which only finds exact matches and falls back to 0 for any non-listed value; AyuGram uses `ranges::lower_bound` + nearest-neighbour logic (left/right distance comparison) so non-exact values snap to the closest entry — `choose_datetime_box.dart:921` ← `AyuGramDesktop/Telegram/SourceFiles/ui/boxes/time_picker_box.cpp:49-60`

- [ ] [MAJOR] "Send until online" option is displayed via Flutter's built-in `showMenu<String>` using Material `PopupMenuItem` widgets; AyuGram uses a `Ui::PopupMenu` with `st::popupMenuWithIcons` style and an explicit `menuIconWhenOnline` icon — visually wrong theme — `choose_datetime_box.dart:720-738` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_schedule_box.cpp:45-62`

- [ ] [MAJOR] Tapping the repeat label when `!isPremium` silently returns without feedback; AyuGram calls `Settings::ShowPremiumPromoToast(...)` with a rich text promo message and "Get Premium" link before the `filter` guard short-circuits the menu — `choose_datetime_box.dart:678` ← `AyuGramDesktop/Telegram/SourceFiles/history/view/history_view_schedule_box.cpp:128-145`

# color_picker_box — Color Picker Dialog

- [ ] [CRITICAL] Opacity slider is rendered vertically to the right of the hue slider, but AyuGram places it horizontally below the picker. `_VerticalOpacitySlider` placed in the picker row (dart:297-311) is fundamentally wrong — `Slider::Direction::Horizontal, Slider::Type::Opacity` is placed below the picker via `rectSlider` geometry (AyuGram:1036-1043). The entire layout for opacity is inverted. — `color_picker_box.dart:297` ← `ui/widgets/color_editor.cpp:871-874`

- [ ] [CRITICAL] Color swatch boxes are displayed side-by-side horizontally below the picker, but AyuGram stacks them vertically (new on top, current below) to the RIGHT of the hue slider at picker-top Y. `_buildSwatchRow` with `Row` (dart:317-329) vs `_newRect` / `_currentRect` computed at `fieldLeft` (right of hue area), `y=colorEditSkip` and `y=colorEditSkip+34` (AyuGram:1056-1062). — `color_picker_box.dart:317` ← `ui/widgets/color_editor.cpp:1056-1062`

- [ ] [CRITICAL] Clicking the "current" color swatch to reset the picker to the original color is not implemented. AyuGram's `mousePressEvent` checks `myrtlrect(_currentRect).contains(e->pos())` and calls `updateFromColor(_current)` (AyuGram:1119-1123). Dart's `_SwatchBox` has no gesture handler at all. — `color_picker_box.dart:495` ← `ui/widgets/color_editor.cpp:1119-1123`

- [ ] [CRITICAL] Tab key field navigation missing. AyuGram's `fieldSubmitted()` cycles focus through all 7 fields (H→S→B→R→G→B→hex); submitting the last field fires `_submitRequests` (AyuGram:960-980). In Dart every field's `onSubmitted` immediately calls `_submit()`, closing the dialog instead of advancing focus. — `color_picker_box.dart:341` ← `ui/widgets/color_editor.cpp:960-980`

- [ ] [CRITICAL] Mouse wheel scroll on focused numeric fields is not implemented. AyuGram's `Field::wheelEvent` increments/decrements the field value by `wheelDelta / 5` steps when focused (AyuGram:720-738). Dart's `_NumericField` has no wheel event support. — `color_picker_box.dart:524` ← `ui/widgets/color_editor.cpp:720-738`

- [ ] [CRITICAL] Up/Down arrow keys to increment/decrement field values are not implemented. AyuGram's `Field::keyPressEvent` handles `Qt::Key_Up` (+1) and `Qt::Key_Down` (-1) (AyuGram:752-760). Dart's `TextField` has no such key handling. — `color_picker_box.dart:564` ← `ui/widgets/color_editor.cpp:752-760`

- [ ] [CRITICAL] Hex field only accepts 6-character input; AyuGram accepts 6 OR 8 characters (RRGGBBAA with alpha channel). `updateFromResultField` checks `text.size() != 6 && text.size() != 8` (AyuGram:1199-1219). Dart uses `LengthLimitingTextInputFormatter(6)` blocking 8-char input. — `color_picker_box.dart:427` ← `ui/widgets/color_editor.cpp:1199`

- [ ] [MAJOR] Slider position indicators use circular markers; AyuGram uses triangular arrow icons. AyuGram's `Slider::paintEvent` draws `st::colorSliderArrowLeft` and `st::colorSliderArrowRight` (or Top/Bottom for vertical) icon sprites (AyuGram:393-416). Dart draws two nested circles in `_HueSliderPainter` and `_OpacitySliderPainter`. — `color_picker_box.dart:756` ← `ui/widgets/color_editor.cpp:393-416`

- [ ] [MAJOR] Picker crosshair color is always white regardless of underlying color. AyuGram calculates luminance (`0.2989*r + 0.5870*g + 0.1140*b`) and uses black pen when lightness > 0.6, white otherwise (AyuGram:121-128). Dart's `_CrosshairPainter` always paints white circle. — `color_picker_box.dart:700-703` ← `ui/widgets/color_editor.cpp:121-128`

- [ ] [MAJOR] Picker crosshair radius is wrong: Dart uses `_kCrosshairRadius = 8`, AyuGram uses `st::colorPickerMarkRadius = 6px` (boxes.style:512). Dart also draws two rings (outer 9px semi-black + inner 8px white) while AyuGram draws a single circle with adaptive pen color. — `color_picker_box.dart:691` ← `boxes/boxes.style:512`

- [ ] [MAJOR] HSL mode not implemented. AyuGram's `ColorEditor` supports `Mode::RGBA` and `Mode::HSL` — HSL mode swaps the 2D picker axis interpretation and replaces the opacity slider with a horizontal lightness slider (AyuGram:875-881, 1125-1138). Dart has no HSL support at all; it only ever uses HSV. — `color_picker_box.dart:50` ← `ui/widgets/color_editor.h:15-18`

- [ ] [MAJOR] Numeric field unit suffixes are missing. AyuGram passes a degree symbol `°` to the H field and `%` to S and B fields as the `units` parameter, displayed right-aligned inside the field (AyuGram:851-858, `paintAdditionalPlaceholder`:706-718). Dart shows bare labels ('H', 'S', 'B') with no unit suffix. — `color_picker_box.dart:331` ← `ui/widgets/color_editor.cpp:851-858`

- [ ] [MAJOR] Custom circular cursor for the picker area is missing. AyuGram generates a 16px double-ring cursor (`generateCursor`, AyuGram:69-94) and sets it on the picker widget. Dart uses the default system cursor. — `color_picker_box.dart:637` ← `ui/widgets/color_editor.cpp:69-94`

- [ ] [MAJOR] Shadow painting on picker and swatch areas is missing. AyuGram's `paintEvent` calls `Ui::Shadow::paint` on `_picker->geometry()` and on the combined swatch rect `_newRect + _currentRect` (AyuGram:1096-1108). Dart paints no shadows. — `color_picker_box.dart:204` ← `ui/widgets/color_editor.cpp:1096-1108`

# bridge_web — Web (WASM) Bridge Implementation

**Note:** `bridge_web.dart` is platform infrastructure with no direct AyuGram Desktop C++ equivalent
(AyuGram is a native Qt/C++ app with no Flutter/WASM layer). The reference implementation is
`bridge_ffi.dart` (the native bridge this file must mirror) and `bridge.dart` (the interface
contract). AyuGram's `mtproto/mtproto_concurrent_sender.h` is cited where it establishes the
correct async-dispatch pattern that the web bridge violates.

---

- [ ] [CRITICAL] `callAsync` is fake async — it calls `call()` synchronously on the Dart/JS main
  isolate, blocking the UI thread for the entire duration of every bridge call (auth, SendMessage,
  GetChatList, etc.). The `async` keyword here only wraps the return value in a Future; it does
  **not** move work off-thread. On web/WASM, Go executes on the same single JS thread, so any
  Go call that does network I/O freezes the entire Flutter UI until it returns. The FFI
  implementation correctly uses `Isolate.run()` to dispatch to a background isolate.
  This violates the documented contract in `bridge.dart:30`: "Async call — runs the FFI call on
  a background isolate. Use for any operation that might block (network calls, auth, etc)."
  AyuGram's concurrent sender (`ConcurrentSender::Handlers` with `done`/`fail` callbacks) shows
  that async RPC must never block the calling thread. —
  `bridge_web.dart:44` ← `bridge_ffi.dart:75-79` /
  `AyuGram/mtproto/mtproto_concurrent_sender.h:37-43`

- [ ] [CRITICAL] `_onEventFromGo` fires on a closed `StreamController` after `dispose()`. The
  `_eventController` is closed at `dispose():49`, but the JS callback
  (`_jsBridgeSetEventCallback`) is cleared **after** the controller is closed (line 48 then 49).
  Any in-flight JS event that arrives between those two lines — or a race where the JS runtime
  has already queued the callback before `dispose()` runs — will call
  `_eventController.add(data.toDart)` on a closed stream, throwing
  `StateError: Cannot add event after closing` and crashing the isolate. The FFI implementation
  avoids this entirely by using a module-level `_globalEventController` that is never closed. —
  `bridge_web.dart:48-54` ← `bridge_ffi.dart:146-156`

- [ ] [CRITICAL] Re-initializing after `dispose()` creates a zombie bridge. `dispose()` closes
  the `final _eventController` (line 49) and resets `_initialized = false` (line 50). A
  subsequent `init()` call passes the `if (_initialized) return` guard (line 29) and sets the
  JS callback again (line 32) and `_initialized = true` (line 33). The bridge now reports itself
  as initialized, but `_eventController` is permanently closed — every event from Go will throw
  `StateError` in `_onEventFromGo`. Because the field is `final` (line 26), it cannot be
  reassigned on re-init. The FFI bridge's global controller pattern (`bridge_ffi.dart:146`)
  never has this problem because the controller lives for the process lifetime. —
  `bridge_web.dart:26,29,49` ← `bridge_ffi.dart:146`

- [ ] [MAJOR] `_onEventFromGo` has no guard against the stream being closed. Even without a
  re-init race, a single late JS callback after dispose (e.g. a Go goroutine that had already
  queued its result) will throw unhandled. The FFI `_onEvent` (bridge_ffi.dart:148) checks
  `if (len <= 0) return` and uses a global controller that is never closed, making the callback
  unconditionally safe. The web callback needs at minimum
  `if (_eventController.isClosed) return;` before `_eventController.add()`. —
  `bridge_web.dart:53-55` ← `bridge_ffi.dart:148-156`

# engine_service — Bridge service layer audit

## Summary
`engine_service.dart` is the Dart-side FFI bridge wrapper (~4337 lines). It does not map 1:1 to
a single AyuGram C++ file — its closest counterparts are `apiwrap.cpp` (API calls) and
`data/data_*.cpp` (data models). AyuGram source is cited as ground-truth for what the correct
parameters/behaviour should be.

---

- [ ] [CRITICAL] `joinChannel` (line 1817-1822) uses `EngineLeaveChatRequest` — a leave-chat proto — to join a channel. The Go engine receives a `chatId` field nominally intended for leaving, routed to `JoinChannel`. These are opposite operations and the proto field semantics are inverted. — `engine_service.dart:1817` ← `AyuGram/apiwrap.cpp:1786` (`MTPchannels_JoinChannel`)

- [ ] [CRITICAL] `clearHistory` (line 1855-1859) uses `EngineLeaveChatRequest`. History-clear and chat-leave are distinct operations in Telegram: clear keeps the conversation, leave removes it. The Go engine must distinguish them, but both use the same proto type here with no discriminating field. — `engine_service.dart:1855` ← `AyuGram/apiwrap.cpp:2060` (`deleteHistory(peer, justClear=true)`)

- [ ] [CRITICAL] `deleteChat` (line 1862-1867) uses `EngineLeaveChatRequest`. In AyuGram, deleting a regular chat calls `MTPmessages_DeleteChatUser` while leaving a channel calls `MTPchannels_LeaveChannel`; they are distinct request types. Both are now mapped to the same proto, meaning the Go engine cannot dispatch them differently. — `engine_service.dart:1862` ← `AyuGram/apiwrap.cpp:2066` (`MTPmessages_DeleteChatUser`)

- [ ] [CRITICAL] `reportSpam` (line 379-383) uses `EngineLeaveChatRequest` with only `chatId` set. AyuGram's report-spam API requires both a sender peer and a list of message IDs (`MTPchannels_ReportSpam`). Neither the sender nor the message IDs are present in the proto being sent. — `engine_service.dart:379` ← `AyuGram/api/api_report.cpp:147` (`ReportSpam(sender, msgIds)`)

- [ ] [CRITICAL] `getLinkedChatId` (line 386-393) uses `EngineLeaveChatRequest` and parses the response with `String.fromCharCodes(respBytes)` instead of a proper protobuf response type. The request carries only `chatId`, same as leave-chat; the Go engine cannot distinguish the intent. Response parsing bypasses proto entirely. — `engine_service.dart:386` ← `AyuGram/data/data_channel.cpp:1369` (`vlinked_chat_id()`)

- [ ] [CRITICAL] `readMessageContents` (line 419-424) uses `EngineMarkChatReadRequest` but sets only `upToMsgId`; the `chatId` field is never set (defaults to empty string). AyuGram's `markContentsRead` routes per-channel vs per-chat based on peer identity — without `chatId` the Go engine cannot route correctly. — `engine_service.dart:419` ← `AyuGram/apiwrap.cpp:1358` (`markContentsRead`, requires peer context)

- [ ] [CRITICAL] `pinForumTopic` (line 487-493) passes the `pinned` boolean through `req.colorId` (sets `colorId = pinned ? 1 : 0`). `colorId` is a colour integer (0–8), not a boolean flag. The Go engine receives a colour field with value 0 or 1 and must infer pin state from it — a semantic abuse that breaks if any topic ever has colorId=1. — `engine_service.dart:487` ← `AyuGram/data/data_forum_topic.cpp:479` (`EditForumTopic` with `f_pinned` flag)

- [ ] [CRITICAL] `toggleForumTopicClosed` (line 496-503) passes `closed` boolean through `req.colorId` (same abuse as pinForumTopic). AyuGram uses an explicit `f_closed` flag in `MTPmessages_EditForumTopic`. Setting colorId=1 when closing means any topic with color 1 is ambiguous. — `engine_service.dart:496` ← `AyuGram/data/data_forum_topic.cpp:479` (`MTPmessages_EditForumTopic f_closed`)

- [ ] [CRITICAL] `toggleGeneralTopicHidden` (line 506-512) passes `hidden` boolean through `req.colorId` (same abuse) and hardcodes `topicId = Int64(1)`. The constant is correct for the General topic, but the colorId hack remains — the Go engine cannot distinguish "set color to 1" from "hide general topic". — `engine_service.dart:506` ← `AyuGram/data/data_forum_topic.cpp:479` (`EditForumTopic f_hidden`)

- [ ] [CRITICAL] `editChatTitle` (line 1831-1837) uses `EngineSaveDraftRequest` with `text = title`. AyuGram uses `MTPchannels_EditTitle` for channels and `MTPmessages_EditChatTitle` for regular chats — two different request types. The Go engine receives a draft-save request routed to `EditChatTitle` with the title stuffed into the draft `text` field. — `engine_service.dart:1831` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:2464` (`MTPchannels_EditTitle`)

- [ ] [CRITICAL] `editChatDescription` (line 1839-1845) uses `EngineSaveDraftRequest` with `text = description`. Same semantic abuse as `editChatTitle`. — `engine_service.dart:1839` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:2464` (description edit path)

- [ ] [CRITICAL] `toggleForum` (line 1847-1853) uses `EngineMuteChatRequest` with `muted = enabled` to pass the forum-toggle state. Mute and forum-mode are unrelated operations sharing the same proto. The `muted` boolean is reused as an on/off switch for a completely different feature. — `engine_service.dart:1847` ← `AyuGram/data/data_channel.cpp` (`ToggleForum` flag)

- [ ] [CRITICAL] `deleteContact` (line 404-409) uses `EngineBlockUserRequest`. Block and delete-contact are different Telegram API calls (`contacts.deleteContacts` vs `contacts.block`). The Go engine receives a block-user request routed to `DeleteContact`. — `engine_service.dart:404` ← `AyuGram/apiwrap.cpp` (contacts management)

- [ ] [CRITICAL] `getCommonChats` (line 2505) passes `accountId` as the `coreId` argument to `_callAsync` instead of `'__engine'`. Every other call in this file uses `'__engine'`. This routes the RPC to the per-account core (which won't have a `GetCommonChats` handler) instead of the engine. The call will always fail or route incorrectly. — `engine_service.dart:2505` ← compare `engine_service.dart:91` (all other calls use `'__engine'`)

- [ ] [CRITICAL] `editMessage` (line 1793-1800) accepts an `entities` parameter but never sets it on the request proto. Entities (bold, italic, links, mentions) are silently dropped on every message edit — rich formatting is destroyed. — `engine_service.dart:1793` ← `AyuGram/apiwrap.cpp` (`editMessage` sends entities for formatting preservation)

- [ ] [MAJOR] `dispose()` (line 3592-3609) closes every `StreamController` except `_groupCallStateController` (declared at line 39). The stream controller is never closed, leaking its internal buffer and any downstream listeners permanently. — `engine_service.dart:3607` ← `engine_service.dart:39` (controller opened, never closed)

- [ ] [MAJOR] `getMessages`, `getChatList`, `searchMessages`, `searchChats`, `getSharedMedia`, `getSharedMediaCounts`, `getPinnedMessages`, `getDeletedMessages`, `getEditRevisions`, `hasEditRevisions` all use `_callRaw` (synchronous FFI call, lines 1656, 152, 3037, 3047, 3090, 3102, 1680, 1722, 1689, 1702). Any DB query or cache miss in the Go engine will block the Flutter UI isolate. AyuGram processes all data fetches on a background thread. — `engine_service.dart:1656` ← `AyuGram/apiwrap.cpp` (all fetches dispatched to background `crl::on_main` queue)

- [ ] [MAJOR] `_dispatchEngineEvent` (line 3690) calls `json.decode` on the UI isolate for every incoming engine event. High-frequency events (rapid message delivery, typing storms) will cause cumulative jank. AyuGram processes updates on a dedicated update queue before posting to the main thread. — `engine_service.dart:3690` ← `AyuGram/apiwrap.cpp:updates_handler` (update processing off main thread)

- [ ] [MAJOR] `updateConfig` (line 3135) cannot persist `downloadDir` — a comment at line 3159 documents it: "downloadDir not yet in EngineUpdateConfigRequest proto — stored locally only." This means the user's chosen download directory is not saved to engine config and resets on restart. — `engine_service.dart:3159` ← `AyuGram/data/data_session.cpp` (all config fields persisted in session)

# app_state — AppState / GhostModeAccountSettings

## Power saving bitfield constants wrong

- [ ] [CRITICAL] `kPowerSavingStickersPanel = 1 << 0` uses bit 0 which C++ assigns to `kAnimations`, not StickersPanel; `kPowerSavingStickersChat = 1 << 1` uses bit 1 which is `kStickersPanel` in C++; bits 0–2 are all shifted/wrong — `app_state.dart:324–325` ← `ui/power_saving.h:13–15`

- [ ] [CRITICAL] `kPowerSavingChatEffects = 1 << 8` and `kPowerSavingCalls = 1 << 10` are **swapped** vs C++: C++ has `kCalls = 1U << 8` and `kChatEffects = 1U << 10` — `app_state.dart:332–333` ← `ui/power_saving.h:21–23`

- [ ] [CRITICAL] `kPowerSavingAnimations = 1 << 11` does not exist in C++; `kAll = (1U << 11) - 1` lives at that boundary and is a mask, not a named feature flag — `app_state.dart:334` ← `ui/power_saving.h:25`

- [ ] [CRITICAL] `kAnimations` (bit 0) and `kStickersChat` (bit 2) have no matching Dart constants at all — `app_state.dart:324–334` ← `ui/power_saving.h:13–15`

## screenReaderOptimized not persisted

- [ ] [CRITICAL] `_screenReaderOptimized` has a setter that calls `_saveWindowPrefs()` (line 1693) and a getter, but the key `'screenReaderOptimized'` is absent from both the save JSON and the load block — the setting is silently discarded on every restart — `app_state.dart:135,1690–1695` vs `_saveWindowPrefs` at `app_state.dart:2800–2975` (key missing)

## swipeAction not persisted

- [ ] [CRITICAL] The `swipeAction` setter (line 1861–1866) does **not** call `_saveWindowPrefs()`, and `'swipeAction'` does not appear anywhere in `_saveWindowPrefs` or `_loadWindowPrefs` — the configurable swipe action (§2.7) resets to `'archive'` on every cold start — `app_state.dart:162,1861–1866`

## ContextMenuVisibility integer convention inverted

- [ ] [MAJOR] Dart uses 0=visible, 1=hidden, 2=visibleWithModifier (comment at line 248), while C++ enum is `Hidden=0, Visible=1, VisibleWithModifier=2`. All seven context-menu fields store the opposite integer for visible/hidden. Any future engine call with these values would invert the user's settings — `app_state.dart:248–254` ← `ayu/ayu_settings.h:35–39`

  Concrete example: C++ default `_showViewsPanelInContextMenu = Visible` serialises to JSON as `1`; Dart stores it as `0` ("visible"). If the Go engine ever reads this JSON field it gets `0` = Hidden.

## sendWithoutSound reduced from 3-value enum to bool

- [ ] [MAJOR] C++ `SendWithoutSoundOption { Never=0, InGhostMode=1, Always=2 }` has three states; Dart collapses this to `bool sendWithoutSound` (line 308, `GhostModeAccountSettings`). The `InGhostMode` option (send without sound only while ghost mode is active) is entirely unrepresentable and will be lost when migrating from a C++ settings file — `app_state.dart:308` ← `ayu/ayu_settings.h:48–52,170`

## materialSwitches fallback wrong on migration

- [ ] [MAJOR] `_loadWindowPrefs` line 2633: `data['materialSwitches'] as bool? ?? false` — fallback is `false`. C++ default is `true` (line 635 of `ayu_settings.h`), and the Dart field initialiser is also `true` (line 173). On upgrade from an older `window_prefs.json` that lacks the key, `materialSwitches` wrongly defaults to `false` instead of `true` — `app_state.dart:2633` ← `ayu/ayu_settings.h:635`

## suggestGhostModeBeforeViewingStory entirely missing

- [ ] [MAJOR] C++ `GhostModeAccountSettings` has `_suggestGhostModeBeforeViewingStory = true` (line 171) with full getter/setter/rpl value; Dart `GhostModeAccountSettings` has no field, no getter, no setter, not serialised — feature is absent — `app_state.dart:20–90` ← `ayu/ayu_settings.h:98,171`

## _saveWindowPrefs is synchronous UI-thread file I/O

- [ ] [MAJOR] Every single settings setter calls `_saveWindowPrefs()` which calls `File(path).writeAsStringSync(jsonEncode({...}))` — a synchronous disk write of the entire ~5 KB prefs blob on the main isolate. With 100+ settings in the map this serialises/writes on every toggle, risking 50–100 ms frame drops. C++ uses asynchronous background I/O for settings persistence — `app_state.dart:2799–2976`

# audio_service — Voice/audio playback state service

## Summary
`AudioService` is a thin `media_kit` wrapper for voice message playback. Compared to AyuGram's `Media::Player::Instance` it is missing call-pause integration, markMediaRead, playback speed, auto-next, repeat/order modes, position persistence, seek pause, and error recovery. One keyboard-shortcut code path passes an empty file path to `playVoice`, silently breaking resume.

---

- [ ] [CRITICAL] Voice messages never marked as read in the engine when played — AyuGram calls `document->owner().markMediaRead(document)` immediately on play for voice/video messages; `AudioService.playVoice` makes no engine call at all — `audio_service.dart:34` ← `media_player_instance.cpp:829`

- [ ] [CRITICAL] Keyboard shortcut "play" passes empty file path — `keyboard_shortcuts.dart:1206` calls `audio.playVoice('', audio.currentMsgId)` which reaches `player.open(Media(''))` and silently fails; no resume occurs — `audio_service.dart:84` ← `media_player_instance.cpp:799` (`play(AudioMsgId::Type)` resumes the existing streamed instance, never re-opens)

- [ ] [CRITICAL] Keyboard shortcut "play/pause" also passes empty file path — `keyboard_shortcuts.dart:1218` calls `audio.playVoice('', audio.currentMsgId)`; same silent failure as above — `audio_service.dart:84` ← `media_player_instance.cpp:1070`

- [ ] [CRITICAL] No call pause/resume integration — AyuGram subscribes to `currentCallValue`/`currentGroupCallValue` and calls `pauseOnCall`/`resumeOnCall` for both Voice and Song types; `AudioService` has no awareness of call state — audio keeps playing during calls — `audio_service.dart:5` ← `media_player_instance.cpp:188`

- [ ] [MAJOR] No playback speed support — AyuGram's `LookupPlaybackSpeed` (lines 65–75) applies user-configured voice speed vs music speed; `AudioService` always plays at 1× with no speed API — `audio_service.dart:34` ← `media_player_instance.cpp:65`

- [ ] [MAJOR] Auto-next not implemented — AyuGram's `emitUpdate` auto-plays the next playlist item when `StoppedAtEnd` (with configurable disable option); `AudioService.completed` handler at line 77–82 only resets `_position` to zero and calls `notifyListeners` — no next-track attempt — `audio_service.dart:77` ← `media_player_instance.cpp:1300`

- [ ] [MAJOR] No repeat modes — AyuGram supports `RepeatMode::None/One/All`; `AudioService` has no repeat concept — `audio_service.dart:5` ← `media_player_instance.cpp:1198`

- [ ] [MAJOR] No order/shuffle modes — AyuGram supports `OrderMode::Default/Reverse/Shuffle` with a full shuffle playlist that remembers up to 16 played tracks; `AudioService` has no ordering concept — `audio_service.dart:5` ← `media_player_instance.cpp:1211`

- [ ] [MAJOR] Last playback position not saved or restored — AyuGram calls `SaveLastPlaybackPosition` on clear/stop for tracks longer than 20 minutes and restores via `local.mediaLastPlaybackPosition` on next play; `AudioService` always starts from zero — `audio_service.dart:49` ← `media_player_instance.cpp:125`

- [ ] [MAJOR] Seek does not pause playback first — AyuGram's `startSeeking` explicitly pauses before seeking and fires `Seeking::Start`/`Seeking::Finish` events so UI can show seek state; `AudioService.seek` (lines 87–93) seeks directly on the playing stream with no pause/resume around it, risking audio glitches — `audio_service.dart:87` ← `media_player_instance.cpp:1147`

- [ ] [MAJOR] No error handling for open/stream failures — AyuGram's `handleStreamingError` recovers from `NotStreamable` (triggers download) and `OpenFailed` (save-to-file); `AudioService.playVoice` has no error listener — a bad file path silently leaves the service in a broken state — `audio_service.dart:62` ← `media_player_instance.cpp:1412`

- [ ] [MAJOR] New `Player()` instance created on every `playVoice()` call — AyuGram reuses a `Streaming::Instance` per type and only calls `clearStreamed` when switching tracks; `AudioService` constructs a fresh `Player()` and disposes the old one on every call (including pause→resume of the same message if it was stopped), causing unnecessary allocation and teardown — `audio_service.dart:51` ← `media_player_instance.cpp:853`

# auth_state — Auth flow state machine

## auth_state — Auth state event wipes rich context fields

- [ ] [CRITICAL] `_handleAuthEvent()` constructs a bare `AuthStateData` with only 4 fields (`accountId`, `state`, `label`, `error`), destroying `hint`, `codeLength`, `sentTo`, `timeoutSecs`, `canResend`, `hasRecovery`, `qrData`, `options`, `displayName`, `avatarB64` every time any engine event fires — `auth_state.dart:172-177` ← `AyuGram/intro/intro_widget.cpp:137-141` (mtpUpdates handler preserves widget state across updates; `handleUpdate()` only processes specific fields, never nukes the step's own data)

- [ ] [CRITICAL] `AuthStateEvent` model has only 4 fields (`accountId`, `state`, `prompt`, `error`) so the rich auth context produced by `startAuth()` (hint, codeLength, sentTo, qrData, hasRecovery, canResend, options) can never be carried through engine events — `engine_models.dart:1731-1737` ← `AyuGram/intro/intro_password_check.cpp:29-69` (`PasswordCheckWidget` constructor reads `getData()->pwdState` which contains `hint`, `hasRecovery`, etc. — all preserved in the shared Data struct across steps)

## auth_state — SRP_ID_INVALID retry is architecturally wrong

- [ ] [CRITICAL] On `SRP_ID_INVALID`, Dart retries `submitInput(input)` directly (recursive call at `auth_state.dart:115`) without re-fetching the SRP challenge from the server — this guarantees the same error again because the SRP request ID hasn't changed. AyuGram calls `requestPasswordData()` which issues `MTPaccount_GetPassword` to get a fresh SRP request before re-submitting — `auth_state.dart:103-116` ← `AyuGram/intro/intro_password_check.cpp:169-201` (`handleSrpIdInvalid()` → `requestPasswordData()` → `MTPaccount_GetPassword` → `passwordChecked()`)

- [ ] [MAJOR] `kHandleSrpIdInvalidTimeout` is `60 * crl::time(1000)` = 60,000 ms in AyuGram and compared with `crl::now()` (millisecond precision). Dart uses `inSeconds < 60` (second precision, integer truncation) — drift of up to 999ms per check — `auth_state.dart:105` ← `AyuGram/core/core_cloud_password.h:14` and `AyuGram/intro/intro_password_check.cpp:171-172`

## auth_state — Missing auth states

- [ ] [CRITICAL] No `2fa_recovery` state — AyuGram's `toRecover()` flow switches to a recovery-code input field (`_codeField`) and issues `MTPauth_RequestPasswordRecovery`. The Dart state machine only models `2fa` with no way to transition to recovery code entry — `auth_state.dart:46-49` ← `AyuGram/intro/intro_password_check.cpp:292-322` (`toRecover()` shows code field, hides password field, fetches recovery email pattern)

- [ ] [CRITICAL] No `terms` state — AyuGram's signup flow requires explicit Terms of Service acceptance via `showTerms()`/`acceptTerms()` before session creation. The Dart state machine has no `terms` state and no ToS acceptance pathway — `auth_state.dart:46-49` ← `AyuGram/intro/intro_widget.cpp:509-536` (`showTerms()` renders ToS link and `acceptTerms()` callback)

## auth_state — Race condition in switchToMethod

- [ ] [MAJOR] In `switchToMethod()`, `_engine.cancelAuth(accountId)` is called without `await` at line 132, then `startAuth(accountId)` immediately begins. If cancelAuth is async and takes time, the engine may have two concurrent auth sessions for the same account — `auth_state.dart:132-138` ← `AyuGram/intro/intro_widget.cpp:381-430` (`historyMove()` with `StackAction::Back` calls `cancelled()` synchronously on the prior step before constructing the next one — strictly sequential)

## auth_state — Missing error handling

- [ ] [MAJOR] No flood error detection — `FLOOD_WAIT_X` errors from Telegram should be shown with a distinct user-facing message and must NOT be silently retried. Dart lumps all non-SRP errors into `_error = errStr` at line 121 — `auth_state.dart:119-122` ← `AyuGram/intro/intro_password_check.cpp:140-145` (`MTP::IsFloodError(error)` check shows `tr::lng_flood_error()`, sets field error state)

- [ ] [MAJOR] `startAuth()` error handler hardcodes `recoverable: true` for all errors at line 77. Recoverability depends on error type (e.g. network error = recoverable, banned phone = not recoverable) — `auth_state.dart:77` ← `AyuGram/intro/intro_phone.cpp:50-64` (phone ban detection leads to `PhoneBannedBox` with no retry path)

## auth_state — Missing account reset flow

- [ ] [MAJOR] No account reset flow — when 2FA password is forgotten and recovery is unavailable, AyuGram shows a `showResetButton()` that triggers `resetAccount()` → `MTPaccount_DeleteAccount` with full confirmation dialog and `2FA_CONFIRM_WAIT_*` timed-delay handling. Dart has no equivalent — `auth_state.dart:1-240` ← `AyuGram/intro/intro_widget.cpp:491-629` (`showResetButton()`, `resetAccount()`, `2FA_CONFIRM_WAIT_` error with days/hours/minutes formatting)

# ayu_forward — AyuGram intelligent forward state machine

- [ ] [CRITICAL] `_groupByAlbum` appends all album groups at the end of the list instead of preserving chronological order — non-album messages are added inline but albums are accumulated in a map and appended via `groups.addAll(albumMap.values)`, so [text1, albumA_photo, albumA_video, text2, albumB_photo] becomes [text1, text2, albumA, albumB] instead of [text1, albumA, text2, albumB], scrambling send order — `ayu_forward.dart:152-165` ← `ayu_forward.cpp:136-150` (C++ iterates items in order, batches consecutive same-groupId items inline without breaking order)

- [ ] [CRITICAL] `buildChunks` forces ALL messages to `resendAsOwn` when `isChatRestricted(sourceChat)` is true (line 124), but C++ `intelligentForward` applies per-item `isAyuForwardNeeded(item)` only — peer-level `noForwards` is handled separately in `isFullAyuForwardNeeded` which is NOT called during chunk-building in C++; messages that are not individually restricted should be forwarded natively even in restricted chats — `ayu_forward.dart:124-125` ← `ayu_forward.cpp:269-285`

- [ ] [MAJOR] `isForwarding` checks only `_activeForwards.containsKey(peerId)` but C++ checks `state != Finished && currentChunk < totalChunks && !stopRequested && ((totalChunks && totalMessages) || state == Downloading)` — the Dart returns true during the 2-second post-finish cleanup window and for cancelled forwards whose finally-block hasn't fired yet, causing false positives — `ayu_forward.dart:79` ← `ayu_forward.cpp:33-43`

- [ ] [MAJOR] `statusText` returns `'Forwarding messages'` for BOTH `preparing` and `sending` phases (lines 34–36 share the same case body) — C++ returns `tr::ayu_AyuForwardStatusPreparing` for Preparing and `tr::ayu_AyuForwardStatusForwarding` for Sending, which are distinct localized strings — `ayu_forward.dart:33-36` ← `ayu_forward.cpp:84-89`

- [ ] [MAJOR] `detailText` uses middle dot `·` (U+00B7) as separator and prepends the literal word `chunk` — C++ uses bullet `•` (U+2022) and the chunk portion comes from `tr::ayu_AyuForwardStatusChunkCount` which already encodes "chunk X of Y" format; the Dart's extra `· chunk` prefix would double the word if the translation string already contains it — `ayu_forward.dart:47-49` ← `ayu_forward.cpp:80`

- [ ] [MAJOR] `isMessageRestricted` has no check for `unsupportedTTL` — C++ `isAyuForwardNeeded` checks `item->unsupportedTTL()` as a separate condition from `item->media()->ttlSeconds()`; messages with unsupported TTL types (not reflected in `ttlSeconds` field) pass through as native forwards instead of being resent-as-own — `ayu_forward.dart:99-103` ← `ayu_forward.cpp:226-228`

- [ ] [MAJOR] No static `cancelForward(peerId)` method on `AyuForward` — C++ exposes `void cancelForward(const PeerId &id, const Main::Session &session)` at namespace level which looks up state by peer ID and calls `updateBottomBar` to trigger UI refresh; Dart forces callers to do `AyuForward.getProgress(peerId)?.cancel()` and skips the peer-update notification path — `ayu_forward.dart` (missing) ← `ayu_forward.h:14`, `ayu_forward.cpp:46-51`

# chat_state — Chat state management audit

## Findings

- [ ] [CRITICAL] `togglePinSavedSublist` never calls the engine — comment explicitly says "backend wiring (MessagesToggleSavedDialogPin) TBD". Only modifies local `_pinnedSublists`/`_regularSublists` lists; pin state resets on reload — `chat_state.dart:1188` ← `AyuGramDesktop/Telegram/SourceFiles/window/window_peer_menu.cpp:471` (`MTPmessages_ToggleSavedDialogPin`)

- [ ] [CRITICAL] `markSavedSublistRead` is a complete stub — body is just `notifyListeners()` with no engine call. Unread count never actually resets on the server — `chat_state.dart:1211` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_saved_sublist.cpp:713` (`MTPmessages_ReadSavedHistory`)

- [ ] [CRITICAL] `deleteSavedSublist` only removes from local lists, never calls the engine. Sublist survives on the server and reappears after restart — `chat_state.dart:1215` ← `AyuGramDesktop/Telegram/SourceFiles/apiwrap.cpp:1469` (`MTPmessages_DeleteSavedHistory`)

- [ ] [CRITICAL] `_autoPreloadForumTopics` passes no offset to `_engine.getForumTopics` — always fetches the same first page. `loadMoreForumTopics` delegates to this function, so "load more" is effectively a no-op: it deduplicates the same page instead of loading the next. Large forums never load past the first batch — `chat_state.dart:1007` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_forum.cpp` (requires `offset_date`/`offset_id`/`offset_topic` in `MTPchannels_GetForumTopics`)

- [ ] [MAJOR] `reorderFolders` updates local list only and never calls the engine — order is lost on next `loadFoldersForAccount`. AyuGram persists via `MTPmessages_UpdateDialogFiltersOrder` — `chat_state.dart:811` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_chat_filters.cpp:913`

- [ ] [MAJOR] Saved Messages detection uses English title string `chat.title == 'Saved Messages'` — breaks for non-English locales and any user who renames the chat. AyuGram identifies Saved Messages via `user->isSelf()` peer flag, not display name — `chat_state.dart:891` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_user.h` (`isSelf`)

- [ ] [MAJOR] `openChatById` calls `_chats.first` as fallback when chat is not found — throws `StateError: No element` if `_chats` is empty (e.g. called before first chat load or after account switch). Even when non-empty, the orElse result is immediately discarded by the `if (chat.chatId == chatId)` guard, making the fallback pointless — `chat_state.dart:963`

- [ ] [MAJOR] Folder DM type-filtering collapses `contacts`, `nonContacts`, and `bots` flags into a single "any DM" test with comment acknowledging the limitation. AyuGram uses separate `ChatFilter::Flag::Contacts`, `NonContacts`, `Bots` flags to filter dialog lists correctly — `chat_state.dart:703` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_chat_filters.h:42`

- [ ] [MAJOR] `_startPolling` fires `_refreshMessages()` every 3 seconds unconditionally for the entire time any chat is open. `_refreshMessages` calls `_engine.getMessages`, merges results, and calls `notifyListeners()` — constant network + full rebuild every 3 seconds even when idle. AyuGram uses reactive MTProto push events with no polling — `chat_state.dart:2043`

- [ ] [MAJOR] `_ensureEnoughTaggedMessages` calls `_loadMessages()` up to 5 times inside a synchronous while loop. Each `_loadMessages()` call triggers its own `notifyListeners()`, causing up to 5 consecutive full widget-tree rebuilds before control returns to the caller — `chat_state.dart:362`

## Visual Journey Findings (Layer 2)

