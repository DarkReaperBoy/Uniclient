## admin_tools — EditPeerInfo / Permissions / AdminLog / InviteLinks / MemberList

- [ ] [CRITICAL] "Recent Actions" button missing from `_buildAdminControlsSection` — AyuGram shows it whenever `hasAdminRights || amCreator`; the function `showAdminLogScreen` is defined but never called from the EditPeerInfo manage section — `admin_tools.dart:752` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1651`

- [ ] [CRITICAL] Slowmode save skips `setSlowMode` when value is 0 (turning off slow mode) — condition is `if (_slowmodeValues[_slowmodeIndex] != 0)` so disabling slowmode never calls `setSlowMode(…, 0)`; AyuGram always calls `SaveSlowmodeSeconds` regardless of value — `admin_tools.dart:1224` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:209`

- [ ] [CRITICAL] `embed_links` flag placed in `_otherFlags` but AyuGram places it inside the media nested group (same nesting level as photos/videos/polls) — Dart puts it after the media section as a peer of `send_polls`, breaking the correct dependency chain and visual grouping — `admin_tools.dart:1172` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:92`

- [ ] [CRITICAL] Missing `send_stickers + send_gifs` mutual dependency — AyuGram enforces that disabling stickers also disables gifs and vice versa (`SendGifs ↔ SendStickers`, `SendGames ↔ SendStickers`, `SendInline ↔ SendStickers`); Dart only implements the `embed_links → send_plain` dependency — `admin_tools.dart:1236` ← `AyuGram/boxes/peers/edit_peer_permissions_box.cpp:266`

- [ ] [CRITICAL] No "Reactions" button in EditPeerInfo manage section — AyuGram calls `editReactions()` for any peer where `canEditReactions()` is true; completely absent from `_buildAdminControlsSection` — `admin_tools.dart:752` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1512`

- [ ] [CRITICAL] No "Pending Requests" button in EditPeerInfo manage section — AyuGram shows it via `fillPendingRequestsButton()` whenever there are pending join requests; absent from `_buildAdminControlsSection` — `admin_tools.dart:752` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1759`

- [ ] [CRITICAL] "Sign Messages" (signatures) for channels should also expose a "Sign Profiles" sub-toggle — AyuGram shows `sign_profiles` as a SlideWrap that appears when signatures are enabled; Dart has only the single signatures toggle — `admin_tools.dart:508` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1276`

- [ ] [MAJOR] `topics` toggle condition is wrong — Dart shows the toggle when `chat.isForum || chat.memberCount > 0` (line 483); AyuGram locks it when member count is below `forum_upgrade_participants_min` (from appConfig, default 200, not 0) and also locks it when a discussion link is set — `admin_tools.dart:483` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1188`

- [ ] [MAJOR] Auto-Translation toggle has no boost-level lock — AyuGram checks `channel->levelHint() < requiredLevel` and shows `AskBoostBox` if not enough level; Dart just toggles unconditionally — `admin_tools.dart:716` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1221`

- [ ] [MAJOR] `EditPeerInfo` is missing a "Color & Emoji" (peer color index) button — AyuGram shows it via `fillColorIndexButton()` when `canEditEmoji`; absent from Dart — `admin_tools.dart:447` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1203`

- [ ] [MAJOR] `EditPeerInfo` is missing the "Direct Messages" price button for broadcast channels — AyuGram shows it via `fillDirectMessagesButton()` for broadcast channels that can edit info; absent from Dart — `admin_tools.dart:447` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:1088`

- [ ] [MAJOR] History visibility toggle should be hidden (SlideWrap) for channels with a public username or a location or a forum or a linked discussion group — AyuGram hides the button using `refreshHistoryVisibility()` in those cases; Dart always shows it for non-channels with no such guard — `admin_tools.dart:474` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:864`

- [ ] [MAJOR] `_EditRestrictedBox._buildRankField` is labeled "Custom Title" and shown for restricted users but AyuGram only shows a custom title field in the **admin** box, not in the restriction box — `admin_tools.dart:2387` ← `AyuGram/boxes/peers/edit_participant_box.cpp:117`

- [ ] [MAJOR] Admin log filter dialog maps "Edit rank" to filter key `['promote']` (same as "Admin rights") instead of the dedicated `EditRank` flag — AyuGram has a separate `Flag::EditRank = (1U << 18)` filter flag — `admin_tools.dart:3823` ← `AyuGram/history/admin_log/history_admin_log_filter_value.h:18`

- [ ] [MAJOR] `_EditAdminBox` initializes `_rankCtrl` with empty text even for existing admins before `_loadExistingRights` completes — rank is loaded asynchronously but the rank text field starts empty, so a fast save will overwrite the existing rank with blank — `admin_tools.dart:2492` ← `AyuGram/boxes/peers/edit_participant_box.cpp:149`

- [ ] [MAJOR] `_InviteLinksBox._buildAdminRow` shows other admins' invite link counts but tapping an admin row does nothing — AyuGram opens that admin's invite link list when tapped; the Dart row has no `onTap` — `admin_tools.dart:4568` ← `AyuGram/boxes/peers/edit_peer_invite_links.cpp`

- [ ] [MAJOR] Permissions box shows "Charge Stars" section for channels (`if (widget.isChannel)`) but AyuGram's charge-stars feature (`UpdatePaidMessagesPrice`) is also applicable to groups/megagroups — the condition should check the engine's stars-per-message capability, not just `isChannel` — `admin_tools.dart:1324` ← `AyuGram/boxes/peers/edit_peer_info_box.cpp:236`
