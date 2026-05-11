# chat_list_row — Audit Findings

- [ ] [CRITICAL] `_TypingDotsIndicator._actionLabel` maps `'geo_location'` → `'choosing location'` and `'choose_contact'` → `'choosing contact'`, but AyuGram's `SendActionPainter` falls both `ChooseLocation` and `ChooseContact` through to the generic `tr::lng_typing` / `tr::lng_user_typing` string (same as plain Typing) — `chat_list_row.dart:1269-1272` ← `AyuGram/SourceFiles/history/view/history_view_send_action.cpp:299-302`

- [ ] [MAJOR] Typing indicator always renders three bouncing `"."` text characters regardless of action type; AyuGram uses type-specific graphical animations: `RecordAnimation` (waveform) for `record_video/record_audio/record_round`, `UploadAnimation` (upload bar) for all upload types, `ChooseStickerAnimation` for `choose_sticker`, and only `TypingAnimation` (bouncing dots) for actual typing — `chat_list_row.dart:1326-1354` ← `AyuGram/SourceFiles/ui/effects/send_action_animations.cpp:634-660`

- [ ] [MAJOR] `resolveSwipeAction` does not disable `mute` for self-chat: AyuGram returns `QuickDialogActionLabel::Disabled` when `history->peer->isSelf()` for the Mute action — `chat_list_row.dart:506-507` ← `AyuGram/SourceFiles/dialogs/dialogs_quick_action.cpp:149-152`

- [ ] [MAJOR] `resolveSwipeAction` does not disable `read` for forum chats with no unread: AyuGram returns `Disabled` when `history->isForum() && !unread` for the Read action — `chat_list_row.dart:510-513` ← `AyuGram/SourceFiles/dialogs/dialogs_quick_action.cpp:164-167`

- [ ] [MAJOR] `resolveSwipeAction` does not check `CanArchive` before allowing the archive action: AyuGram calls `Window::CanArchive(history, peer)` and returns `Disabled` if the chat cannot be archived — `chat_list_row.dart:514-515` ← `AyuGram/SourceFiles/dialogs/dialogs_quick_action.cpp:171-177`

- [ ] [MAJOR] Mini-preview gap between thumbnail and text is `4px` (`SizedBox(width: 4)`), but spec is `dialogsMiniPreviewSkip: 2px` — `chat_list_row.dart:400` ← `AyuGram/SourceFiles/dialogs/dialogs.style:546`

- [ ] [MAJOR] `ForumChatListRow` top gap before the name row is `8px` (`SizedBox(height: 8)`), but `forumDialogRow` inherits `nameTop: 10px` from `defaultDialogRow` (not overridden) — `chat_list_row.dart:1864` ← `AyuGram/SourceFiles/dialogs/dialogs.style:98,108`

- [ ] [MAJOR] `_rowHeightWithTags = 96.0` is declared but `effectiveHeight` is always set to `_rowHeight` (80px), so tagged forum rows never expand to 96px; AyuGram uses `taggedForumDialogRow.height: 96px` for forum rows with filter tags — `chat_list_row.dart:1780,1792` ← `AyuGram/SourceFiles/dialogs/dialogs.style:114-116`

- [ ] [MAJOR] `_TopicsPreview` renders `'No topics'` text when `topics.isEmpty`; AyuGram renders no topics-preview widget at all when there are no recent topics (empty topics area shows nothing) — `chat_list_row.dart:2010-2016` ← `AyuGram/SourceFiles/dialogs/ui/dialogs_topics_view.h`
