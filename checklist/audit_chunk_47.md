# chat_switch_overlay — Ctrl+Tab chat switcher overlay

- [ ] [CRITICAL] Forum topic entries not rendered — AyuGram shows a `TopicIconButton` on top of the channel userpic (`chatSwitchUserpicSmall: 24px`) when the thread is a forum topic; Dart renders only a plain circle avatar for all chat types with no topic-icon layer — `chat_switch_overlay.dart:394-418` ← `window/window_chat_switch_process.cpp:99-111`

- [ ] [CRITICAL] Saved sublist dual-userpic not implemented — AyuGram overlays the sublist peer's userpic (40px, `chatSwitchUserpicSublist`) behind the channel userpic (24px, `chatSwitchUserpicSmall`) for saved-sublist threads; Dart renders a single avatar with no secondary peer userpic — `chat_switch_overlay.dart:394-418` ← `window/window_chat_switch_process.cpp:112-127`

- [ ] [MAJOR] Selection border uses wrong color — AyuGram draws the selection rect with `st::defaultRoundCheckbox.bgActive` = `windowBgActive` (#40a7e3, bright fill-blue); Dart uses `p.windowActiveTextFg` (#168acd, text-accent blue); these are distinct semantic colours — `chat_switch_overlay.dart:233` ← `window/window.style:376` + `lib_ui/ui/widgets/widgets.style:1239`

- [ ] [MAJOR] Name label vertical position is ~10px too high — AyuGram places the label by centering it in the space below the userpic: `top = (cell_height + userpic_top + userpic_height − label_height) / 2 ≈ 77.5px`; Dart starts the label at a fixed `userpicTop(8) + userpicSize(56) + SizedBox(4) = 68px`, using top-alignment in the Expanded — `chat_switch_overlay.dart:368-388` ← `window/window_chat_switch_process.cpp:152-155`
