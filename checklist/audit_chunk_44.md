## chat_list_panel — full panel audit (search, story bar, folder tabs, archived row, forum topics, saved sublists, drag behaviors)

- [ ] [CRITICAL] `_ForumTopicRow._previewText()` always returns empty string for non-general topics, showing no last-message preview text — `chat_list_panel.dart:5204` ← `AyuGram/dialogs/ui/dialogs_topics_view.cpp` (dialogs_layout.cpp handles last-message text rendering per topic row)

- [ ] [CRITICAL] `_ForumTopicRow` context menu "Mark as Unread" branch is missing: when `hasUnread == false`, clicking "Mark as Read/Unread" does nothing (no call to `markChatUnread`) — `chat_list_panel.dart:5041-5044` ← `AyuGram/dialogs/dialogs_inner_widget.cpp:2175-2185` (pressed-row ripple/action logic handles toggle)

- [ ] [CRITICAL] `_ForumTopicRow` context menu "New Window" is a stub — shows toast "Multi-window is not yet supported" instead of opening a new window — `chat_list_panel.dart:5029` ← `AyuGram/dialogs/dialogs_widget.cpp` (no equivalent stub; AyuGram opens secondary window)

- [ ] [CRITICAL] `_RecentContactsList` avatar positioned at `left: 16` but AyuGram spec requires `photoPosition: point(10px, 7px)` (x=10), and name/status at `left: 74`/`left: 74` while AyuGram requires `namePosition: point(64px, 9px)` / `statusPosition: point(64px, 30px)` (x=64) — `chat_list_panel.dart:3175,3220,3236` ← `AyuGram/dialogs/dialogs.style:762-764`

- [ ] [CRITICAL] `_EmptyState._kQueryPreviewLimit` is 18 but AyuGram uses `kQueryPreviewLimit = 32` — truncation is too aggressive — `chat_list_panel.dart:4100` ← `AyuGram/dialogs/dialogs_inner_widget.cpp:109`

- [ ] [CRITICAL] Forward-drag hover timeout is 1000ms (`Duration(milliseconds: 1000)`) — this matches AyuGram's `ChoosePeerByDragTimeout = 1000` for opening a chat on hover. However, AyuGram only auto-opens when NOT in `_dragForward` mode (file-drag); the Dart code fires unconditionally on any `ForwardDragData` hover, including when an in-app forward drag is active — `chat_list_panel.dart:862-869` ← `AyuGram/dialogs/dialogs_widget.cpp:3383-3387` (`_dragForward` guard)

- [ ] [CRITICAL] `_StoriesBar` collapsed state shows "My Story" add button as a plain `Icons.add` circle without fetching or displaying the user's own story ring/avatar — AyuGram shows the user's own userpic with their story ring state; the "add" affordance is only shown when the user has no current story — `chat_list_panel.dart:2700-2725` ← `AyuGram/dialogs/ui/dialogs_stories_list.cpp` (own-story first-item rendering)

- [ ] [MAJOR] `_StoriesBar` switching between collapsed and expanded at `t < 0.5` is an abrupt hard cut (builds either `_buildCollapsed` or `_buildExpanded` with no intermediate cross-fade) — AyuGram uses a smooth height-only animation with a single continuous list that reflows, not a hard rebuild at midpoint — `chat_list_panel.dart:2677-2683` ← `AyuGram/dialogs/ui/dialogs_stories_list.cpp`

- [ ] [MAJOR] `_StoriesBarRingPainter` uses a fixed gradient `[Color(0xFF0dcc39), Color(0xFF0992ef)]` for unread story rings, but AyuGram uses the platform's story-gradient colors (which differ in dark/light mode and follow the theme) — `chat_list_panel.dart:2964-2970` ← `AyuGram/dialogs/ui/dialogs_stories_list.cpp`

- [ ] [MAJOR] `_HorizontalFolderTabs` drag reorder commits on pointer-up using center-of-mass comparison only — AyuGram also uses a threshold-based approach with snap animation at 150ms (`universalDuration`) during drag, but the Dart `AnimatedContainer` `duration` is set to `Duration.zero` when drag is NOT active and 150ms when active, meaning the end-of-drag snap animation is skipped entirely — `chat_list_panel.dart:2283-2285` ← `AyuGram/dialogs/dialogs_widget.h` (filter tab reorder animation)

- [ ] [MAJOR] `_SearchSubFilterRow` photo placeholder uses a `Material Icon` (`Icons.forum_outlined` etc.) instead of the actual avatar/peer photo of the currently selected search-in target. AyuGram renders the peer photo (28px) of the current "search in" context (e.g., group avatar) — `chat_list_panel.dart:3584-3590` ← `AyuGram/dialogs/ui/chat_search_in.cpp` (`dialogsSearchInPhotoSize: 28px`, actual peer userpic)

- [ ] [MAJOR] `_ArchivedChatsRow` wide-mode label left padding is 18px but AyuGram paints it using `defaultDialogRow.padding.left = 10px` plus icon offset (the archive userpic is at `10px` then text follows) — there is no 18px spec value for the text offset — `chat_list_panel.dart:3707` ← `AyuGram/dialogs/dialogs_inner_widget.cpp:1506-1512` + `AyuGram/dialogs/dialogs.style:93-101`

- [ ] [MAJOR] `_ArchivedChatsRow` does not show the archive userpic icon in wide mode — AyuGram shows the archive userpic (a styled folder icon: `dialogsArchiveUserpic`) on the left side of the collapsed archive row even in wide mode — `chat_list_panel.dart:3704-3742` ← `AyuGram/dialogs/dialogs.style:403` (`dialogsArchiveUserpic`) and `dialogs_inner_widget.cpp:1506`

- [ ] [MAJOR] `_TopPeersStrip` uses `_stripHeight = 90.0` and `_itemWidth = 66.0` but AyuGram spec defines `topPeers: photo: 46px, photoLeft: 10px, photoTop: 8px, height: 77px` plus `topPeersMargin: margins(3px, 3px, 3px, 4px)` — total item height and avatar dimensions don't match — `chat_list_panel.dart:2461-2462` ← `AyuGram/dialogs/dialogs.style:746-753`

- [ ] [MAJOR] `_TopPeersStrip` does not show the "FREQUENT CONTACTS" section header (`searchedBarHeight: 28px`, `st::searchedBarLabel`) that AyuGram renders above the top-peers strip — `chat_list_panel.dart:2467-2546` ← `AyuGram/dialogs/ui/top_peers_strip.cpp:81-87`

- [ ] [MAJOR] `_SearchTabsStrip` "Public Posts" tab performs `searchGlobalChats()` only returning channel-type results as fallback, but AyuGram's public posts search uses a dedicated `SearchPostsManager` with a separate server-side posts search endpoint — `chat_list_panel.dart:494-502` ← `AyuGram/dialogs/dialogs_search_posts.cpp`

- [ ] [MAJOR] `_ForumTopicRow` date field uses `topic.creationDateTime` for formatting instead of the actual last-message timestamp — the creation date is not what Telegram Desktop shows; it should show the last message time for the topic — `chat_list_panel.dart:5187-5201`  ← `AyuGram/dialogs/ui/dialogs_layout.cpp` (last-message time rendering)

- [ ] [MAJOR] `_ChatListPanelState` build method sorts the entire chat list on every `build()` call (`List<ChatInfo>.from(displayChats)..sort(...)`) — this is O(n log n) on every widget rebuild (including scrolls, focus changes, hover state changes). AyuGram maintains a pre-sorted `DialogsIndexedList` and only re-sorts on data change events — `chat_list_panel.dart:599-603` ← `AyuGram/dialogs/dialogs_indexed_list.cpp`

- [ ] [MAJOR] `_StoriesBar` uses a `ListView.builder` for the expanded state, but the entire bar is rebuilt with a new `ListView` every time the animation controller ticks (inside `AnimatedBuilder`), causing excessive widget allocation during the expand/collapse animation — `chat_list_panel.dart:2670-2683` ← `AyuGram/dialogs/ui/dialogs_stories_list.cpp` (uses `repaint()` only)

- [ ] [MAJOR] `_ChatListSkeleton` hardcodes only 2 skeleton rows (`_rowCount = 2`) but AyuGram shows skeleton rows filling the entire available viewport height — `chat_list_panel.dart:3905` ← `AyuGram/dialogs/dialogs_inner_widget.cpp` (loading state fills height)

- [ ] [MAJOR] `_SearchSubFilterRow` "Search in" divider bar renders as a grey background bar (`dividerBg`) at 28px, but AyuGram renders the `searchedBar` as a distinct section label with `searchedBarLabel` style (14px font, `searchedBarFg` color, `14px` left position) — colors are approximated as hardcoded hex rather than palette values — `chat_list_panel.dart:3551-3565` ← `AyuGram/dialogs/dialogs.style:843-854`

- [ ] [MAJOR] `_HorizontalFolderTabs` "All" label is hardcoded as the string `'All'` but AyuGram uses `tr::lng_filters_all()` localization which shows "All" or the locale equivalent — `chat_list_panel.dart:2271` ← `AyuGram/dialogs/dialogs_widget.cpp` (filter tab labels)

- [ ] [MAJOR] `_RecentContactsList` status text is hardcoded to either `'online'` or `'last seen recently'` — AyuGram uses the actual last-seen status from the user object (exact time, days, weeks, etc.) — `chat_list_panel.dart:3240` ← `AyuGram/dialogs/dialogs_inner_widget.cpp` (peer status rendering)

- [ ] [MAJOR] `_SavedSublistRow` tag pills in `_buildTagPills` show ALL tags from `chatState.savedReactionTags` on every row rather than only the tags that actually appear in that specific sublist — `chat_list_panel.dart:5870-5898` ← `AyuGram/dialogs/ui/dialogs_topics_view.cpp` (per-row tag data)

- [ ] [MAJOR] `_onChatListScroll` overscroll-to-expand-stories uses `overscrollRatio > 0.72` as threshold, but also accesses `bar._expanded` directly on a private state field via a key lookup — this internal state access pattern is fragile and is not how AyuGram triggers the stories expansion (which uses a scroll observer, not overscroll ratio) — `chat_list_panel.dart:213-221` ← `AyuGram/dialogs/ui/dialogs_stories_list.cpp`
