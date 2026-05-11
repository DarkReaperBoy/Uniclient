# ayu_section_builder — Section builder utility

- [ ] [CRITICAL] `addBetaBadge(String)` is a complete no-op stub — the entire method body is empty; in AyuGram it attaches a styled badge widget to the parent button with a painted rounded rect background — `ayu_section_builder.dart:103-105` ← `ayu/ui/settings/ayu_builder.cpp:259-261`

- [ ] [CRITICAL] Lock-all prevention missing in `_NestedCheckbox` — AyuGram refuses to lock an entry when doing so would lock ALL entries (`lockedCount + 1 >= checkboxes.size()` guard); Dart's shift-click handler calls `onLockToggle!(!isLocked)` unconditionally, allowing every checkbox to be locked at once — `ayu_section_builder.dart:529-533` ← `ayu/ui/settings/settings_ayu_utils.cpp:386-396`

- [ ] [MAJOR] Beta badge border radius is 3px but must be 4px — AyuGram derives the corner radius from `st::ayuBetaBadgePadding.left()` which equals 4px; Dart hardcodes `BorderRadius.circular(3)` — `ayu_section_builder.dart:203` ← `ayu/ui/settings/settings_ayu_utils.cpp:62-63`, `ayu/ui/ayu_styles.style:119`

- [ ] [MAJOR] Collapsible toggle count rendered as a separate accent-colored `Text` widget instead of bold text appended inline to the label — AyuGram appends `tr::bold("  N/total")` as a `TextWithEntities` fragment using `st::boxLabel`; Dart puts `$checkedCount/$totalCount` in a sibling `Text(style: accentColor)` — `ayu_section_builder.dart:451-458` ← `ayu/ui/settings/settings_ayu_utils.cpp:228-243`

- [ ] [MAJOR] Collapsible toggle uses `Icons.expand_less` / `Icons.expand_more` swapped between states instead of an animated rotating `permissionsExpandIcon` — AyuGram rotates a single icon 180° with `anim::easeOutCubic` over `st::slideWrapDuration`; Dart simply swaps two different icons with no rotation — `ayu_section_builder.dart:477-481` ← `ayu/ui/settings/settings_ayu_utils.cpp:247-298`

- [ ] [MAJOR] `toggledWhenAll` parameter missing from `addCollapsibleToggle` — AyuGram's `CollapsibleToggleArgs::toggledWhenAll` (default `true`) controls whether the master toggle is ON when ALL unlocked items are checked vs ANY item is checked; Dart always uses the all-checked logic with no way to override — `ayu_section_builder.dart:85-101` ← `ayu/ui/settings/ayu_builder.h:46-54`

- [ ] [MAJOR] Slider uses a continuous float model (`double min/max/value`) instead of AyuGram's discrete integer-indexed model (`int steps`, `int current`, `Fn<int(int)> indexToValue`, `Fn<QString(int)> formatLabel`) — the Dart slider cannot represent non-linear or remapped index-to-value mappings — `ayu_section_builder.dart:49-68` ← `ayu/ui/settings/ayu_builder.h:69-82`

- [ ] [MAJOR] Slider value label is static — AyuGram's `label->setText(formatLabel(value))` updates the displayed label reactively on every drag event; Dart's `valueLabel` string is fixed at construction and won't update unless the parent rebuilds — `ayu_section_builder.dart:278-283` ← `ayu/ui/settings/ayu_builder.cpp:219-235`

- [ ] [MAJOR] Slider bottom padding is 4px but must be 8px — `recentStickersLimitPadding` is `margins(22px, 4px, 22px, 8px)`; Dart uses `EdgeInsets.symmetric(horizontal: 22, vertical: 4)` giving equal top/bottom of 4px — `ayu_section_builder.dart:266` ← `ayu/ui/ayu_styles.style:21`

- [ ] [MAJOR] Section divider skip spacing is 7px but must be 6px — AyuGram's `addSectionDivider` calls `_builder.addSkip()` which resolves to `defaultVerticalListSkip = 6px`; Dart hardcodes `SizedBox(height: 7)` — `ayu_section_builder.dart:110-112` ← `ayu/ui/settings/ayu_builder.cpp:263-267`, `lib_ui/ui/basic.style:126`

- [ ] [MAJOR] `_NestedCheckbox` uses Flutter's Material `Checkbox` widget instead of the Telegram-style `Ui::Checkbox` with `st::settingsCheckbox` — AyuGram renders checkboxes using the Telegram checkbox style, not Material Design checkboxes — `ayu_section_builder.dart:546-560` ← `ayu/ui/settings/settings_ayu_utils.cpp:357-362`
