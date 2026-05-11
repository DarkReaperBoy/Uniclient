# color_picker_box — Color Picker Dialog

- [ ] [MAJOR] Hue slider spectrum order inverted vs AyuGram: Dart gradient runs hue=0(red)→hue=360(red) top-to-bottom, AyuGram generates the strip left-to-right then applies `QTransform(0,-1,1,0,0,0)` which reverses the order so top=hue≈360, bottom=hue=0; intermediate colors (yellow/green/cyan/blue/magenta) appear in opposite vertical sequence — `color_picker_box.dart:836-841` ← `AyuGram/SourceFiles/ui/widgets/color_editor.cpp:455-467`

- [ ] [MAJOR] Field column width is `Expanded` (fills remaining space, ~89px at default size) instead of AyuGram's fixed `colorSampleSize.width()=60px`; `_kMinFieldWidth=60` is only used in the pickerSize clamp formula, never to constrain the actual field column — `color_picker_box.dart:414-419` ← `AyuGram/SourceFiles/ui/widgets/color_editor.cpp:1054` + `AyuGram/SourceFiles/boxes/boxes.style:520`

- [ ] [MAJOR] Inter-field spacing wrong: Dart uses 3px between fields within each group and 6px between groups; AyuGram stacks fields within a group with zero gap and uses `colorFieldSkip=13px` between the HSB group and RGB group — `color_picker_box.dart:468-483` ← `AyuGram/SourceFiles/ui/widgets/color_editor.cpp:1064-1082` + `AyuGram/SourceFiles/boxes/boxes.style:521`

- [ ] [MAJOR] No unit labels on HSB fields: AyuGram renders ° (degree) on the right side of H field and % on S and B fields via `paintAdditionalPlaceholder`; Dart shows only the bare letter label and number with no units — `color_picker_box.dart:466-482` ← `AyuGram/SourceFiles/ui/widgets/color_editor.cpp:851-860`

- [ ] [MAJOR] Hex output always emits 8 chars (RRGGBBAA) when `showOpacity=true` even when opacity=1.0 (alpha=255); AyuGram's `updateResultField` only appends the alpha bytes when `_new.alpha() != 255`, keeping output as 6-char RRGGBB for fully-opaque colors — `color_picker_box.dart:195-197` ← `AyuGram/SourceFiles/ui/widgets/color_editor.cpp:1013-1015`

- [ ] [MAJOR] Initial focus lands on the outer dialog `FocusNode` (which only handles Escape), not the hex/result field; AyuGram's `setInnerFocus()` explicitly focuses the result field and calls `selectAll()` so the user can start typing a hex code immediately — `color_picker_box.dart:336-339` ← `AyuGram/SourceFiles/ui/widgets/color_editor.cpp:943-946`

- [ ] [MAJOR] Mouse-wheel scroll on numeric fields uses raw `scrollDelta.dy` sign with a fixed ±5 step per event; AyuGram accumulates `angleDelta` across events and divides by `kStep=5`, yielding ~24 units per standard wheel click and respecting platform-specific axis inversion (Mac flips Y) — `color_picker_box.dart:501-505` ← `AyuGram/SourceFiles/ui/widgets/color_editor.cpp:720-739`
